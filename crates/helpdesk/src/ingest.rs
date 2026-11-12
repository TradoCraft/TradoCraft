//! Turning an incoming e-mail into a ticket article.
//!
//! Threading (like Zammad): a reply is attached to its ticket through the In-Reply-To /
//! References headers, or through the `[Ticket#T2026-00012]` tag in the subject. Anything else
//! opens a new ticket. The sender is matched to a person (contact) by e-mail address, which also
//! gives the customer and the language to answer in; failing that to a customer by e-mail
//! address, then by company domain; quotation numbers in the text are linked; the language and a category are suggested.

use chrono::Datelike;
use sqlx::{FromRow, PgConnection, PgPool};
use uuid::Uuid;

use crate::classify::{find_quotation_numbers, find_ticket_number, strip_quoted, suggest_category};
use crate::email::{parse, InboundEmail};
use crate::language::detect_language;

#[derive(Debug, Clone)]
pub struct IngestResult {
    pub ticket_id: Uuid,
    pub ticket_number: String,
    pub article_id: Uuid,
    pub new_ticket: bool,
    /// The message was already stored (same Message-ID); nothing changed.
    pub duplicate: bool,
}

/// Free mail providers: a shared domain says nothing about which customer wrote.
const PUBLIC_DOMAINS: [&str; 14] = [
    "gmail.com",
    "googlemail.com",
    "outlook.com",
    "hotmail.com",
    "live.com",
    "yahoo.com",
    "icloud.com",
    "telenet.be",
    "skynet.be",
    "proximus.be",
    "gmx.de",
    "web.de",
    "orange.fr",
    "free.fr",
];

#[derive(FromRow)]
struct CustomerMatch {
    id: Uuid,
    language: String,
}

async fn match_customer(
    conn: &mut PgConnection,
    from: &str,
) -> anyhow::Result<Option<CustomerMatch>> {
    let exact: Option<CustomerMatch> = sqlx::query_as(
        "SELECT id, language::text AS language FROM crm.customers WHERE lower(email) = $1 AND active LIMIT 1",
    )
    .bind(from)
    .fetch_optional(&mut *conn)
    .await?;
    if exact.is_some() {
        return Ok(exact);
    }
    let Some(domain) = from.rsplit_once('@').map(|(_, d)| d.to_string()) else {
        return Ok(None);
    };
    if PUBLIC_DOMAINS.contains(&domain.as_str()) {
        return Ok(None);
    }
    let by_domain: Vec<CustomerMatch> = sqlx::query_as(
        "SELECT id, language::text AS language FROM crm.customers WHERE lower(email) LIKE '%@' || $1 AND active LIMIT 2",
    )
    .bind(&domain)
    .fetch_all(&mut *conn)
    .await?;
    // Only an unambiguous domain match counts.
    Ok(if by_domain.len() == 1 {
        by_domain.into_iter().next()
    } else {
        None
    })
}

#[derive(FromRow)]
struct TicketRef {
    id: Uuid,
    number: String,
}

async fn find_ticket(
    conn: &mut PgConnection,
    company_id: Uuid,
    mail: &InboundEmail,
) -> anyhow::Result<Option<TicketRef>> {
    if !mail.references.is_empty() {
        let t: Option<TicketRef> = sqlx::query_as(
            "SELECT t.id, t.number FROM helpdesk.articles a JOIN helpdesk.tickets t ON t.id = a.ticket_id
             WHERE t.company_id = $1 AND a.message_id = ANY($2)
             ORDER BY a.created_at DESC LIMIT 1",
        )
        .bind(company_id)
        .bind(&mail.references)
        .fetch_optional(&mut *conn)
        .await?;
        if t.is_some() {
            return Ok(t);
        }
    }
    if let Some(number) = find_ticket_number(&mail.subject) {
        // A merged ticket's number leads to the ticket it was merged into.
        return Ok(sqlx::query_as(
            "SELECT t2.id, t2.number FROM helpdesk.tickets t
             JOIN helpdesk.tickets t2 ON t2.id = coalesce(t.merged_into_id, t.id)
             WHERE t.company_id = $1 AND t.number = $2",
        )
        .bind(company_id)
        .bind(number)
        .fetch_optional(&mut *conn)
        .await?);
    }
    Ok(None)
}

#[derive(FromRow)]
struct QuoteMatch {
    id: Uuid,
    created_by: Uuid,
}

/// The latest revision of the first quotation number mentioned (of this customer, if known).
async fn find_quotation(
    conn: &mut PgConnection,
    company_id: Uuid,
    customer_id: Option<Uuid>,
    numbers: &[String],
) -> anyhow::Result<Option<QuoteMatch>> {
    for n in numbers {
        let q: Option<QuoteMatch> = sqlx::query_as(
            "SELECT id, created_by FROM sales.quotations
             WHERE company_id = $1 AND number = $2 AND ($3::uuid IS NULL OR customer_id = $3)
             ORDER BY revision DESC LIMIT 1",
        )
        .bind(company_id)
        .bind(n)
        .bind(customer_id)
        .fetch_optional(&mut *conn)
        .await?;
        if q.is_some() {
            return Ok(q);
        }
    }
    Ok(None)
}

/// The helpdesk mailbox an e-mail was fetched from (ADR 0054).
#[derive(Debug, Clone, Copy)]
pub struct Source {
    pub mailbox_id: Uuid,
    /// New tickets from this mailbox start in this team.
    pub team_id: Option<Uuid>,
}

/// Ingests an e-mail that did not come from a helpdesk mailbox (an imported file, or the
/// worker's single mailbox from the `IMAP_*` variables).
pub async fn ingest(db: &PgPool, company_id: Uuid, raw: &[u8]) -> anyhow::Result<IngestResult> {
    ingest_from(db, company_id, raw, None).await
}

/// Turns a raw e-mail into a new ticket or an article on an existing one. With a `source`, a new
/// ticket remembers the mailbox (replies leave through it) and starts in the mailbox's team.
pub async fn ingest_from(
    db: &PgPool,
    company_id: Uuid,
    raw: &[u8],
    source: Option<Source>,
) -> anyhow::Result<IngestResult> {
    let mail = parse(raw).ok_or_else(|| anyhow::anyhow!("not a valid e-mail message"))?;
    let mut tx = db.begin().await?;

    if let Some(mid) = &mail.message_id {
        let existing: Option<(Uuid, Uuid, String)> = sqlx::query_as(
            "SELECT a.id, t.id, t.number FROM helpdesk.articles a JOIN helpdesk.tickets t ON t.id = a.ticket_id
             WHERE a.message_id = $1 AND t.company_id = $2",
        )
        .bind(mid)
        .bind(company_id)
        .fetch_optional(&mut *tx)
        .await?;
        if let Some((article_id, ticket_id, ticket_number)) = existing {
            return Ok(IngestResult {
                ticket_id,
                ticket_number,
                article_id,
                new_ticket: false,
                duplicate: true,
            });
        }
    }

    let new_text = strip_quoted(&mail.body);
    let body = if new_text.trim().is_empty() {
        mail.body.clone()
    } else {
        new_text
    };
    let contact = tradocraft_crm::contacts::find_by_email(&mut tx, &mail.from_address)
        .await
        .map_err(|e| anyhow::anyhow!("contact lookup failed: {e}"))?;
    let customer = match &contact {
        Some(c) => Some(CustomerMatch {
            id: c.customer_id,
            // The person's own language wins over the customer's.
            language: c.effective_language.clone(),
        }),
        None => match_customer(&mut tx, &mail.from_address).await?,
    };
    let quotation_numbers = find_quotation_numbers(&format!("{}\n{}", mail.subject, body));
    let quotation = find_quotation(
        &mut tx,
        company_id,
        customer.as_ref().map(|c| c.id),
        &quotation_numbers,
    )
    .await?;
    let suggestion = suggest_category(&mail.subject, &body, quotation.is_some());
    let detected = detect_language(&body);

    let existing = find_ticket(&mut tx, company_id, &mail).await?;
    let new_ticket = existing.is_none();
    let (ticket_id, ticket_number) = match existing {
        Some(t) => {
            // A customer reply reopens the ticket; links found now are added if still empty.
            sqlx::query(
                "UPDATE helpdesk.tickets SET
                    status = CASE WHEN status IN ('pending_customer', 'closed') THEN 'open' ELSE status END,
                    closed_at = NULL,
                    quotation_id = coalesce(quotation_id, $2),
                    customer_id = coalesce(customer_id, $3),
                    contact_id = coalesce(contact_id, $5),
                    mailbox_id = coalesce(mailbox_id, $6),
                    suggested_category = $4,
                    updated_at = now()
                 WHERE id = $1",
            )
            .bind(t.id)
            .bind(quotation.as_ref().map(|q| q.id))
            .bind(customer.as_ref().map(|c| c.id))
            .bind(suggestion)
            .bind(contact.as_ref().map(|c| c.id))
            .bind(source.map(|s| s.mailbox_id))
            .execute(&mut *tx)
            .await?;
            crate::sla::sync(&mut tx, t.id).await?;
            crate::collab::notify_watchers(
                &mut tx,
                company_id,
                t.id,
                None,
                &[],
                crate::collab::Change::CustomerReply,
            )
            .await?;
            (t.id, t.number)
        }
        None => {
            let default_language: String = sqlx::query_scalar(
                "SELECT default_language::text FROM core.companies WHERE id = $1",
            )
            .bind(company_id)
            .fetch_one(&mut *tx)
            .await?;
            let language = customer
                .as_ref()
                .map(|c| c.language.clone())
                .or(detected.map(str::to_string))
                .unwrap_or(default_language);
            let year = chrono::Utc::now().year();
            let n = tradocraft_core::numbering::next_number(&mut tx, company_id, "ticket", year)
                .await?;
            let number = format!("T{year}-{n:05}");
            let id = tradocraft_core::new_id();
            sqlx::query(
                "INSERT INTO helpdesk.tickets (id, company_id, number, subject, category, suggested_category, language,
                                               customer_id, contact_name, contact_email, owner_user_id, quotation_id, contact_id, channel,
                                               mailbox_id, team_id)
                 VALUES ($1, $2, $3, $4, $5, $5, $6, $7, $8, $9, $10, $11, $12, 'email', $13,
                         (SELECT id FROM helpdesk.teams WHERE id = $14 AND company_id = $2 AND active))",
            )
            .bind(id)
            .bind(company_id)
            .bind(&number)
            .bind(if mail.subject.is_empty() { "(no subject)" } else { mail.subject.as_str() })
            .bind(suggestion)
            .bind(&language)
            .bind(customer.as_ref().map(|c| c.id))
            .bind(
                contact
                    .as_ref()
                    .map(|c| c.full_name.as_str())
                    .unwrap_or(&mail.from_name),
            )
            .bind(&mail.from_address)
            // A reply about a quotation goes to the salesperson who made it.
            .bind(quotation.as_ref().map(|q| q.created_by))
            .bind(quotation.as_ref().map(|q| q.id))
            .bind(contact.as_ref().map(|c| c.id))
            .bind(source.map(|s| s.mailbox_id))
            .bind(source.and_then(|s| s.team_id))
            .execute(&mut *tx)
            .await?;
            crate::teams::assign_default_team(&mut tx, company_id, id).await?;
            crate::collab::record_event(
                &mut tx,
                company_id,
                id,
                "created",
                None,
                Default::default(),
            )
            .await?;
            crate::sla::sync(&mut tx, id).await?;
            (id, number)
        }
    };

    let article_id = tradocraft_core::new_id();
    sqlx::query(
        "INSERT INTO helpdesk.articles (id, ticket_id, kind, from_address, from_name, to_addresses, cc_addresses,
                                        subject, body, raw_message, language, message_id, in_reply_to, contact_id, mailbox_id)
         VALUES ($1, $2, 'email_in', $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)",
    )
    .bind(article_id)
    .bind(ticket_id)
    .bind(&mail.from_address)
    .bind(&mail.from_name)
    .bind(&mail.to)
    .bind(&mail.cc)
    .bind(&mail.subject)
    .bind(&body)
    .bind(raw)
    .bind(detected)
    .bind(&mail.message_id)
    .bind(mail.references.last())
    .bind(contact.as_ref().map(|c| c.id))
    .bind(source.map(|s| s.mailbox_id))
    .execute(&mut *tx)
    .await?;
    store_attachments(&mut tx, company_id, ticket_id, article_id, &mail).await?;
    crate::automation::run(
        &mut tx,
        company_id,
        ticket_id,
        if new_ticket {
            "created"
        } else {
            "customer_replied"
        },
    )
    .await?;
    tx.commit().await?;
    Ok(IngestResult {
        ticket_id,
        ticket_number,
        article_id,
        new_ticket,
        duplicate: false,
    })
}

/// Stores the files of an incoming mail on the ticket, linked to its article. Files that are not
/// JPEG, PNG, WebP or PDF, empty or too large are left out (the original mail is kept in full in
/// `raw_message`); the same rules as for uploads apply.
async fn store_attachments(
    conn: &mut PgConnection,
    company_id: Uuid,
    ticket_id: Uuid,
    article_id: Uuid,
    mail: &InboundEmail,
) -> anyhow::Result<()> {
    let sender = if mail.from_name.is_empty() {
        mail.from_address.as_str()
    } else {
        mail.from_name.as_str()
    };
    for a in mail
        .attachments
        .iter()
        .take(crate::attachments::MAX_PER_ARTICLE)
    {
        match tradocraft_core::files::store_document(
            conn,
            company_id,
            None,
            &a.filename,
            &a.data,
            None,
            sender,
        )
        .await
        {
            Ok(file) => {
                sqlx::query(
                    "INSERT INTO helpdesk.ticket_attachments (file_id, ticket_id, article_id) VALUES ($1, $2, $3)",
                )
                .bind(file.id)
                .bind(ticket_id)
                .bind(article_id)
                .execute(&mut *conn)
                .await?;
            }
            Err(tradocraft_core::AppError::Validation(reason)) => {
                tracing::info!(file = %a.filename, %reason, "attachment of an incoming e-mail skipped");
            }
            Err(e) => anyhow::bail!("storing an attachment failed: {e}"),
        }
    }
    Ok(())
}
