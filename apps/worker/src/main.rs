//! Background worker.
//!
//! * Writes a heartbeat at the start of every pass (ADR 0052). When the previous beat is too old,
//!   the gap is recorded and the companies' administrators get a "worker was down" mail.
//! * Polls the helpdesk mailbox over IMAP (when IMAP_HOST is set) and turns mails into tickets.
//! * Escalates tickets whose SLA ran out (one internal e-mail per ticket and kind of breach).
//! * Generates the planned jobs of active maintenance contracts before their visits are due.
//! * Recomputes the "often bought together" table from confirmed installation orders (hourly, or
//!   every COOCCURRENCE_SECONDS).
//! * Sends queued outgoing e-mails (ticket replies and system mail such as portal login links)
//!   over SMTP, or writes them as .eml files when
//!   MAIL_TRANSPORT=files (development).
//!
//! Several workers may run at once: outbox rows are locked while sent, and IMAP messages are only
//! marked read after they are stored.

use std::path::PathBuf;
use std::time::Duration;

use anyhow::Context;
use sqlx::postgres::PgPoolOptions;
use tracing_subscriber::EnvFilter;
use tradocraft_helpdesk::imap::{poll, ImapConfig};
use tradocraft_helpdesk::mailer::{process_outbox, process_system_mail, Mailer, SmtpSecurity};
use uuid::Uuid;

fn env(name: &str) -> Option<String> {
    std::env::var(name).ok().filter(|v| !v.trim().is_empty())
}

fn mailer(transport: &str) -> anyhow::Result<Mailer> {
    match transport {
        "smtp" => Mailer::smtp(
            &env("SMTP_HOST").context("SMTP_HOST is required for MAIL_TRANSPORT=smtp")?,
            env("SMTP_PORT")
                .map(|p| p.parse())
                .transpose()?
                .unwrap_or(587),
            env("SMTP_USER"),
            env("SMTP_PASSWORD"),
            match env("SMTP_SECURITY").as_deref().unwrap_or("starttls") {
                "starttls" => SmtpSecurity::StartTls,
                "tls" => SmtpSecurity::Tls,
                "none" => SmtpSecurity::None,
                other => anyhow::bail!("unknown SMTP_SECURITY {other} (starttls, tls or none)"),
            },
        ),
        "files" => {
            let dir = PathBuf::from(env("MAIL_FILES_DIR").unwrap_or_else(|| "outbox".into()));
            tracing::warn!(dir = %dir.display(), "MAIL_TRANSPORT=files: e-mails are written to disk, not sent");
            Ok(Mailer::Files(dir))
        }
        other => anyhow::bail!("unknown MAIL_TRANSPORT {other} (expected smtp or files)"),
    }
}

async fn company_id(db: &sqlx::PgPool) -> anyhow::Result<Uuid> {
    if let Some(id) = env("HELPDESK_COMPANY_ID") {
        return Ok(Uuid::parse_str(&id)?);
    }
    let ids: Vec<Uuid> = sqlx::query_scalar("SELECT id FROM core.companies LIMIT 2")
        .fetch_all(db)
        .await?;
    match ids.as_slice() {
        [one] => Ok(*one),
        _ => anyhow::bail!("set HELPDESK_COMPANY_ID: there is not exactly one company"),
    }
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| "info,sqlx=warn".into()),
        )
        .init();
    let db = PgPoolOptions::new()
        .max_connections(5)
        .connect(&env("DATABASE_URL").context("DATABASE_URL is required")?)
        .await?;
    // One policy for everything that reaches the outside world (ADR 0048): outside live, e-mail is
    // forced to files and the mailbox is not polled unless explicitly opted in.
    let environment = tradocraft_core::environment::EnvironmentConfig::from_env()
        .map_err(|e| anyhow::anyhow!(e))?;
    let requested_transport = env("MAIL_TRANSPORT").unwrap_or_else(|| "files".into());
    let policy = environment.outbound_policy(&requested_transport);
    policy.log_warnings(&requested_transport);
    tracing::info!(
        kind = environment.kind.as_str(),
        name = environment.name.as_deref().unwrap_or("(database name)"),
        "environment"
    );
    let mailer = mailer(&policy.mail_transport)?;
    let interval = Duration::from_secs(
        env("POLL_SECONDS")
            .map(|s| s.parse())
            .transpose()?
            .unwrap_or(30),
    );
    let imap = match env("IMAP_HOST") {
        Some(_) if !policy.imap_allowed => {
            tracing::warn!(
                "IMAP_HOST ignored: not a live environment, incoming e-mail is not fetched"
            );
            None
        }
        Some(host) => Some(ImapConfig {
            host,
            port: env("IMAP_PORT")
                .map(|p| p.parse())
                .transpose()?
                .unwrap_or(993),
            user: env("IMAP_USER").context("IMAP_USER is required")?,
            password: env("IMAP_PASSWORD").context("IMAP_PASSWORD is required")?,
            mailbox: env("IMAP_MAILBOX").unwrap_or_else(|| "INBOX".into()),
            tls: env("IMAP_TLS").as_deref() != Some("false"),
            company_id: company_id(&db).await?,
        }),
        None => {
            tracing::warn!("IMAP_HOST not set: incoming e-mail is not fetched");
            None
        }
    };
    let cooccurrence_every = Duration::from_secs(
        env("COOCCURRENCE_SECONDS")
            .map(|s| s.parse())
            .transpose()?
            .unwrap_or(3600),
    );
    let mut last_cooccurrence: Option<std::time::Instant> = None;
    let heartbeat = tradocraft_core::worker::WorkerInfo {
        started_at: chrono::Utc::now(),
        interval_seconds: i32::try_from(interval.as_secs().max(1)).unwrap_or(i32::MAX),
        version: env!("CARGO_PKG_VERSION").to_string(),
        host: env("HOSTNAME").unwrap_or_else(|| "unknown".into()),
    };
    tracing::info!(seconds = interval.as_secs(), "worker started");
    loop {
        // First, so that a pass that hangs (a stuck IMAP or SMTP server) stops the beat.
        match tradocraft_core::worker::beat(&db, &heartbeat).await {
            Ok(None) => {}
            Ok(Some(o)) => tracing::warn!(
                from = %o.down_from,
                until = %o.down_until,
                "no worker ran for a while; administrators are notified"
            ),
            Err(e) => tracing::error!(error = ?e, "writing the heartbeat failed"),
        }
        if last_cooccurrence.is_none_or(|t| t.elapsed() >= cooccurrence_every) {
            last_cooccurrence = Some(std::time::Instant::now());
            match tradocraft_sales::cooccurrence::recompute(&db).await {
                Ok(n) => tracing::info!(pairs = n, "product co-occurrence recomputed"),
                Err(e) => tracing::error!(error = ?e, "recomputing product co-occurrence failed"),
            }
        }
        if let Some(cfg) = &imap {
            match poll(&db, cfg).await {
                Ok(0) => {}
                Ok(n) => tracing::info!(n, "e-mails fetched"),
                Err(e) => tracing::error!(error = ?e, "IMAP poll failed"),
            }
        }
        match tradocraft_helpdesk::sla::escalate(&db).await {
            Ok(0) => {}
            Ok(n) => tracing::info!(n, "SLA breaches escalated"),
            Err(e) => tracing::error!(error = ?e, "SLA escalation failed"),
        }
        if let Err(e) = tradocraft_helpdesk::collab::cleanup_presence(&db).await {
            tracing::error!(error = ?e, "presence cleanup failed");
        }
        match tradocraft_fieldservice::contracts::generate_due_visits(&db, tradocraft_core::today())
            .await
        {
            Ok(g) if g.jobs == 0 && g.renewed == 0 => {}
            Ok(g) => tracing::info!(
                jobs = g.jobs,
                renewed = g.renewed,
                "maintenance contracts processed"
            ),
            Err(e) => tracing::error!(error = ?e, "generating contract visits failed"),
        }
        match process_outbox(&db, &mailer, 50).await {
            Ok(0) => {}
            Ok(n) => tracing::info!(n, "e-mails sent"),
            Err(e) => tracing::error!(error = ?e, "sending the outbox failed"),
        }
        match process_system_mail(&db, &mailer, 50).await {
            Ok(0) => {}
            Ok(n) => tracing::info!(n, "system e-mails sent"),
            Err(e) => tracing::error!(error = ?e, "sending system e-mail failed"),
        }
        tokio::select! {
            _ = tokio::time::sleep(interval) => {}
            _ = tokio::signal::ctrl_c() => {
                tracing::info!("stopping");
                return Ok(());
            }
        }
    }
}
