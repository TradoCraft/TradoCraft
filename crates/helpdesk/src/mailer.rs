//! Sending queued e-mails (the outbox) over SMTP or Microsoft Graph, or to files in development.
//!
//! An e-mail leaves through the helpdesk mailbox it belongs to (ADR 0054): the mailbox of the
//! ticket, else the company's default mailbox. Without mailboxes, everything uses the one
//! transport from the worker's `MAIL_TRANSPORT` and `SMTP_*` variables.

use std::collections::HashMap;
use std::path::PathBuf;

use anyhow::Context;
use lettre::message::header::{HeaderName, HeaderValue};
use lettre::message::{Attachment, Mailbox, Message, MultiPart, SinglePart};
use lettre::transport::smtp::authentication::Credentials;
use lettre::{AsyncSmtpTransport, AsyncTransport, Tokio1Executor};
use sqlx::{FromRow, PgPool};
use uuid::Uuid;

use crate::graph::{GraphClient, GraphMailbox};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SmtpSecurity {
    /// STARTTLS on port 587 (default).
    StartTls,
    /// Implicit TLS on port 465.
    Tls,
    /// No encryption: only for a local test server or a trusted internal relay.
    None,
}

pub enum Mailer {
    Smtp(AsyncSmtpTransport<Tokio1Executor>),
    /// Writes each message as an .eml file (development and tests).
    Files(PathBuf),
    /// An Exchange Online mailbox through Microsoft Graph.
    Graph(GraphClient, GraphMailbox),
}

/// The transports of one worker pass.
pub struct Transports<'a> {
    /// The transport from the worker's variables: used when the company has no mailbox.
    pub fallback: &'a Mailer,
    /// One transport per active helpdesk mailbox, or why it cannot send. `None` when mailboxes
    /// must not be used: outside a live environment everything goes to the fallback, which the
    /// outbound policy forces to files (ADR 0048).
    pub mailboxes: Option<&'a HashMap<Uuid, Result<Mailer, String>>>,
}

impl Transports<'_> {
    fn pick(&self, mailbox: Option<Uuid>) -> anyhow::Result<&Mailer> {
        match (self.mailboxes, mailbox) {
            (Some(map), Some(id)) => match map.get(&id) {
                Some(Ok(m)) => Ok(m),
                Some(Err(reason)) => Err(anyhow::anyhow!("{reason}")),
                // Never through another server than the one the sender address belongs to.
                None => Err(anyhow::anyhow!("the mailbox of this e-mail is not active")),
            },
            _ => Ok(self.fallback),
        }
    }
}

impl Mailer {
    pub fn smtp(
        host: &str,
        port: u16,
        user: Option<String>,
        password: Option<String>,
        security: SmtpSecurity,
    ) -> anyhow::Result<Self> {
        let mut b = match security {
            SmtpSecurity::StartTls => AsyncSmtpTransport::<Tokio1Executor>::starttls_relay(host)?,
            SmtpSecurity::Tls => AsyncSmtpTransport::<Tokio1Executor>::relay(host)?,
            SmtpSecurity::None => AsyncSmtpTransport::<Tokio1Executor>::builder_dangerous(host),
        }
        .port(port);
        if let (Some(u), Some(p)) = (user, password) {
            b = b.credentials(Credentials::new(u, p));
        }
        Ok(Mailer::Smtp(b.build()))
    }

    /// Sends the message. Returns the Message-ID the server gave it when that is known and may
    /// differ from the one in the message (Exchange Online).
    async fn send(&self, message: Message, id: Uuid) -> anyhow::Result<Option<String>> {
        match self {
            Mailer::Smtp(t) => {
                t.send(message).await?;
            }
            Mailer::Files(dir) => {
                tokio::fs::create_dir_all(dir).await?;
                tokio::fs::write(dir.join(format!("{id}.eml")), message.formatted()).await?;
            }
            Mailer::Graph(client, mailbox) => {
                return client.send(mailbox, &message.formatted()).await;
            }
        }
        Ok(None)
    }
}

#[derive(FromRow)]
struct Queued {
    id: Uuid,
    from_address: String,
    from_name: String,
    to_addresses: Vec<String>,
    cc_addresses: Vec<String>,
    subject: String,
    body: String,
    message_id: Option<String>,
    in_reply_to: Option<String>,
    references: Option<Vec<String>>,
    attempts: i32,
    /// The mailbox to send through: the article's, else the company's default.
    mailbox_id: Option<Uuid>,
    /// That mailbox's address: the transport only sends as that address.
    mailbox_address: Option<String>,
}

impl Queued {
    /// A queued reply whose mailbox is gone (the article's link is cleared when a mailbox is
    /// deleted) must not leave through the default mailbox under another sender address.
    fn check_sender(&self) -> anyhow::Result<()> {
        match &self.mailbox_address {
            Some(a) if !a.eq_ignore_ascii_case(self.from_address.trim()) => anyhow::bail!(
                "the sender {} does not belong to the mailbox this e-mail would leave through ({a}); \
                 check the mailbox settings and queue the reply again",
                self.from_address
            ),
            _ => Ok(()),
        }
    }
}

const MAX_ATTEMPTS: i32 = 5;

/// A file stored on the ticket and sent along with a reply.
#[derive(FromRow)]
struct FileToSend {
    filename: String,
    content_type: String,
    data: Vec<u8>,
}

fn build(q: &Queued, files: &[FileToSend]) -> anyhow::Result<Message> {
    let from: Mailbox = format!(
        "{} <{}>",
        q.from_name.replace(['<', '>', '"'], ""),
        q.from_address
    )
    .parse()
    .or_else(|_| q.from_address.parse())
    .context("invalid from address")?;
    let mut b = Message::builder().from(from).subject(&q.subject);
    for t in &q.to_addresses {
        b = b.to(t.parse().with_context(|| format!("invalid address {t}"))?);
    }
    for c in &q.cc_addresses {
        b = b.cc(c.parse().with_context(|| format!("invalid address {c}"))?);
    }
    if let Some(id) = &q.message_id {
        b = b.message_id(Some(format!("<{id}>")));
    }
    if let Some(r) = &q.in_reply_to {
        b = b.in_reply_to(format!("<{r}>"));
    }
    if let Some(refs) = q.references.as_ref().filter(|r| !r.is_empty()) {
        b = b.references(
            refs.iter()
                .map(|r| format!("<{r}>"))
                .collect::<Vec<_>>()
                .join(" "),
        );
    }
    let mut m = if files.is_empty() {
        b.body(q.body.clone())?
    } else {
        let mut parts = MultiPart::mixed().singlepart(SinglePart::plain(q.body.clone()));
        for f in files {
            let content_type = f.content_type.parse().context("invalid attachment type")?;
            parts = parts
                .singlepart(Attachment::new(f.filename.clone()).body(f.data.clone(), content_type));
        }
        b.multipart(parts)?
    };
    m.headers_mut().insert_raw(HeaderValue::new(
        HeaderName::new_from_ascii_str("X-Tradocraft-Article"),
        q.id.to_string(),
    ));
    Ok(m)
}

/// Sends up to `batch` queued e-mails. Each article is locked while it is being sent, so several
/// workers can run side by side. Returns the number sent.
pub async fn process_outbox(db: &PgPool, mailer: &Mailer, batch: i64) -> anyhow::Result<usize> {
    let transports = Transports {
        fallback: mailer,
        mailboxes: None,
    };
    process_outbox_with(db, &transports, batch).await
}

/// [`process_outbox`] with one transport per helpdesk mailbox.
pub async fn process_outbox_with(
    db: &PgPool,
    transports: &Transports<'_>,
    batch: i64,
) -> anyhow::Result<usize> {
    let mut sent = 0;
    for _ in 0..batch {
        let mut tx = db.begin().await?;
        let next: Option<Queued> = sqlx::query_as(
            "SELECT a.id, a.from_address, a.from_name, a.to_addresses, a.cc_addresses, a.subject, a.body,
                    a.message_id, a.in_reply_to,
                    (SELECT array_agg(x.message_id ORDER BY x.created_at) FROM helpdesk.articles x
                     WHERE x.ticket_id = a.ticket_id AND x.message_id IS NOT NULL AND x.id <> a.id
                       AND x.kind <> 'note') AS references,
                    a.attempts, coalesce(a.mailbox_id, d.id) AS mailbox_id, e.address AS mailbox_address
             FROM helpdesk.articles a
             JOIN helpdesk.tickets t ON t.id = a.ticket_id
             LEFT JOIN helpdesk.mailboxes d ON d.company_id = t.company_id AND d.is_default AND d.active
             LEFT JOIN helpdesk.mailboxes e ON e.id = coalesce(a.mailbox_id, d.id)
             WHERE a.delivery = 'queued'
             -- An e-mail that failed goes behind the others, so one broken mailbox does not hold
             -- up the rest.
             ORDER BY a.attempts, a.created_at
             LIMIT 1 FOR UPDATE OF a SKIP LOCKED",
        )
        .fetch_optional(&mut *tx)
        .await?;
        let Some(q) = next else { break };
        let files: Vec<FileToSend> = sqlx::query_as(
            "SELECT f.filename, f.content_type, b.data
             FROM helpdesk.ticket_attachments ta JOIN core.files f ON f.id = ta.file_id
             JOIN core.file_blobs b ON b.file_id = f.id
             WHERE ta.article_id = $1 ORDER BY ta.created_at, f.id",
        )
        .bind(q.id)
        .fetch_all(&mut *tx)
        .await?;
        let result = match (build(&q, &files), transports.pick(q.mailbox_id)) {
            // Outside live the fallback writes files whatever the address.
            (Ok(m), Ok(mailer)) => match (transports.mailboxes, q.check_sender()) {
                (Some(_), Err(e)) => Err(e),
                _ => mailer.send(m, q.id).await,
            },
            (Err(e), _) | (_, Err(e)) => Err(e),
        };
        match result {
            Ok(assigned) => {
                // The Message-ID the customer's reply will refer to: the one the server gave.
                sqlx::query(
                    "UPDATE helpdesk.articles SET delivery = 'sent', sent_at = now(), attempts = attempts + 1,
                            delivery_error = NULL, message_id = coalesce($2, message_id), mailbox_id = $3
                     WHERE id = $1",
                )
                .bind(q.id)
                .bind(assigned)
                .bind(q.mailbox_id)
                .execute(&mut *tx)
                .await?;
                sent += 1;
            }
            Err(e) => {
                let failed = q.attempts + 1 >= MAX_ATTEMPTS;
                tracing::warn!(article = %q.id, error = %e, failed, "sending e-mail failed");
                sqlx::query(
                    "UPDATE helpdesk.articles SET attempts = attempts + 1, delivery_error = $2,
                            delivery = CASE WHEN $3 THEN 'failed' ELSE 'queued' END
                     WHERE id = $1",
                )
                .bind(q.id)
                .bind(e.to_string())
                .bind(failed)
                .execute(&mut *tx)
                .await?;
                tx.commit().await?;
                // Leave the rest for the next round.
                break;
            }
        }
        tx.commit().await?;
    }
    Ok(sent)
}

#[derive(FromRow)]
struct QueuedSystem {
    id: Uuid,
    to_address: String,
    subject: String,
    body: String,
    attempts: i32,
    attachment_name: Option<String>,
    attachment_type: Option<String>,
    attachment_data: Option<Vec<u8>>,
    company_name: String,
    company_email: Option<String>,
    /// The company's default mailbox: its address is the sender and it is the transport.
    mailbox_id: Option<Uuid>,
    mailbox_address: Option<String>,
}

fn build_system(q: &QueuedSystem) -> anyhow::Result<Message> {
    let from_address = q
        .mailbox_address
        .as_deref()
        .or(q.company_email.as_deref())
        .filter(|e| e.contains('@'))
        .context("the company has no e-mail address to send from")?;
    let from: Mailbox = format!(
        "{} <{}>",
        q.company_name.replace(['<', '>', '"'], ""),
        from_address
    )
    .parse()
    .or_else(|_| from_address.parse())
    .context("invalid from address")?;
    let builder = Message::builder()
        .from(from)
        .to(q.to_address.parse().context("invalid recipient address")?)
        .subject(&q.subject);
    let mut m = match (&q.attachment_name, &q.attachment_data) {
        (Some(name), Some(data)) => {
            let content_type = q
                .attachment_type
                .as_deref()
                .unwrap_or("application/octet-stream")
                .parse()
                .context("invalid attachment type")?;
            builder.multipart(
                MultiPart::mixed()
                    .singlepart(SinglePart::plain(q.body.clone()))
                    .singlepart(Attachment::new(name.clone()).body(data.clone(), content_type)),
            )?
        }
        _ => builder.body(q.body.clone())?,
    };
    m.headers_mut().insert_raw(HeaderValue::new(
        HeaderName::new_from_ascii_str("X-Tradocraft-Mail"),
        q.id.to_string(),
    ));
    Ok(m)
}

/// Sends up to `batch` queued system e-mails (portal login links). Same rules as the ticket
/// outbox: rows are locked while sent and given up after [`MAX_ATTEMPTS`].
pub async fn process_system_mail(
    db: &PgPool,
    mailer: &Mailer,
    batch: i64,
) -> anyhow::Result<usize> {
    let transports = Transports {
        fallback: mailer,
        mailboxes: None,
    };
    process_system_mail_with(db, &transports, batch).await
}

/// [`process_system_mail`] through the company's default helpdesk mailbox when it has one.
pub async fn process_system_mail_with(
    db: &PgPool,
    transports: &Transports<'_>,
    batch: i64,
) -> anyhow::Result<usize> {
    let mut sent = 0;
    for _ in 0..batch {
        let mut tx = db.begin().await?;
        let next: Option<QueuedSystem> = sqlx::query_as(
            "SELECT m.id, m.to_address, m.subject, m.body, m.attempts,
                    m.attachment_name, m.attachment_type, m.attachment_data, co.name AS company_name, co.email AS company_email,
                    d.id AS mailbox_id, d.address AS mailbox_address
             FROM core.mail_outbox m JOIN core.companies co ON co.id = m.company_id
             LEFT JOIN helpdesk.mailboxes d ON d.company_id = m.company_id AND d.is_default AND d.active
             WHERE m.delivery = 'queued'
             ORDER BY m.attempts, m.created_at
             LIMIT 1 FOR UPDATE OF m SKIP LOCKED",
        )
        .fetch_optional(&mut *tx)
        .await?;
        let Some(q) = next else { break };
        // Outside live the fallback (files) is used; the sender address stays the mailbox's.
        let result = match (build_system(&q), transports.pick(q.mailbox_id)) {
            (Ok(m), Ok(mailer)) => mailer.send(m, q.id).await,
            (Err(e), _) | (_, Err(e)) => Err(e),
        };
        match result {
            Ok(_) => {
                sqlx::query("UPDATE core.mail_outbox SET delivery = 'sent', sent_at = now(), attempts = attempts + 1, delivery_error = NULL WHERE id = $1")
                    .bind(q.id)
                    .execute(&mut *tx)
                    .await?;
                sent += 1;
            }
            Err(e) => {
                let failed = q.attempts + 1 >= MAX_ATTEMPTS;
                tracing::warn!(mail = %q.id, error = %e, failed, "sending system e-mail failed");
                sqlx::query(
                    "UPDATE core.mail_outbox SET attempts = attempts + 1, delivery_error = $2,
                            delivery = CASE WHEN $3 THEN 'failed' ELSE 'queued' END
                     WHERE id = $1",
                )
                .bind(q.id)
                .bind(e.to_string())
                .bind(failed)
                .execute(&mut *tx)
                .await?;
                tx.commit().await?;
                break;
            }
        }
        tx.commit().await?;
    }
    Ok(sent)
}
