//! Helpdesk mailboxes (ADR 0054): a company can have several, each read and sent through
//! Microsoft Graph (Exchange Online) or IMAP/SMTP (Exchange Server on-premises and other servers).
//!
//! The database holds the settings but never a secret: `secret_ref` names the worker environment
//! variable `MAILBOX_SECRET_<secret_ref>`. The worker loads the active mailboxes on every pass,
//! fetches their mail ([`poll_all`]) and builds one transport per mailbox ([`transports`]).

use std::collections::HashMap;

use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::Json;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection, PgPool};
use tradocraft_core::{audit, new_id, AppError, AppResult, AppState, CurrentUser, Permission};
use utoipa::ToSchema;
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::graph::{GraphClient, GraphMailbox};
use crate::imap::ImapConfig;
use crate::ingest::Source;
use crate::mailer::{Mailer, SmtpSecurity};

type ErrorBody = tradocraft_core::error::ErrorBody;

/// The prefix of the worker environment variable that holds a mailbox's secret.
pub const SECRET_ENV_PREFIX: &str = "MAILBOX_SECRET_";

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct Mailbox {
    pub id: Uuid,
    pub name: String,
    /// The address customers write to and replies are sent from.
    pub address: String,
    /// graph | imap_smtp
    pub kind: String,
    /// New tickets from this mailbox start in this team (else the default team).
    pub team_id: Option<Uuid>,
    pub team_name: Option<String>,
    /// Used for system mail and for replies on tickets without a mailbox.
    pub is_default: bool,
    pub active: bool,
    /// Fetch incoming mail; off for a mailbox that only sends.
    pub inbound_enabled: bool,
    /// The secret is the worker environment variable `MAILBOX_SECRET_<secret_ref>`; it is never
    /// stored or returned.
    pub secret_ref: String,
    pub tenant_id: Option<String>,
    pub client_id: Option<String>,
    pub username: Option<String>,
    pub imap_host: Option<String>,
    pub imap_port: Option<i32>,
    pub imap_tls: bool,
    pub imap_folder: String,
    pub smtp_host: Option<String>,
    pub smtp_port: Option<i32>,
    /// starttls | tls | none
    pub smtp_security: String,
    /// When the worker last tried to fetch mail, and when that last succeeded.
    pub last_poll_at: Option<DateTime<Utc>>,
    pub last_ok_at: Option<DateTime<Utc>>,
    /// Why the last attempt failed; empty after a success.
    pub last_error: Option<String>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct MailboxInput {
    pub name: String,
    pub address: String,
    /// graph | imap_smtp
    pub kind: String,
    pub team_id: Option<Uuid>,
    #[serde(default)]
    pub is_default: bool,
    #[serde(default = "yes")]
    pub active: bool,
    #[serde(default = "yes")]
    pub inbound_enabled: bool,
    /// Upper-case letters, digits and underscores, e.g. `SUPPORT`.
    pub secret_ref: String,
    pub tenant_id: Option<String>,
    pub client_id: Option<String>,
    pub username: Option<String>,
    pub imap_host: Option<String>,
    pub imap_port: Option<i32>,
    #[serde(default = "yes")]
    pub imap_tls: bool,
    pub imap_folder: Option<String>,
    pub smtp_host: Option<String>,
    pub smtp_port: Option<i32>,
    pub smtp_security: Option<String>,
}

fn yes() -> bool {
    true
}

const SELECT: &str = "SELECT m.id, m.name, m.address, m.kind, m.team_id, tm.name AS team_name, m.is_default, m.active,
        m.inbound_enabled, m.secret_ref, m.tenant_id, m.client_id, m.username, m.imap_host, m.imap_port,
        m.imap_tls, m.imap_folder, m.smtp_host, m.smtp_port, m.smtp_security, m.last_poll_at, m.last_ok_at,
        m.last_error, m.created_at
    FROM helpdesk.mailboxes m LEFT JOIN helpdesk.teams tm ON tm.id = m.team_id";

async fn load(
    conn: &mut PgConnection,
    company_id: Uuid,
    only: Option<Uuid>,
) -> AppResult<Vec<Mailbox>> {
    Ok(sqlx::query_as(&format!(
        "{SELECT} WHERE m.company_id = $1 AND ($2::uuid IS NULL OR m.id = $2)
         ORDER BY m.is_default DESC, lower(m.name)"
    ))
    .bind(company_id)
    .bind(only)
    .fetch_all(conn)
    .await?)
}

fn clean(v: &Option<String>) -> Option<String> {
    v.as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_string)
}

fn valid_host(h: &str) -> bool {
    !h.is_empty()
        && h.len() <= 253
        && h.chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '.' || c == '-')
}

/// The validated, normalised form of an input.
struct Clean {
    name: String,
    address: String,
    kind: String,
    secret_ref: String,
    tenant_id: Option<String>,
    client_id: Option<String>,
    username: Option<String>,
    imap_host: Option<String>,
    imap_port: Option<i32>,
    imap_folder: String,
    smtp_host: Option<String>,
    smtp_port: Option<i32>,
    smtp_security: String,
}

fn validate(input: &MailboxInput) -> AppResult<Clean> {
    let bad = |m: &str| Err(AppError::Validation(m.into()));
    let name = input.name.trim().to_string();
    if name.is_empty() {
        return bad("a mailbox needs a name");
    }
    let address = input.address.trim().to_lowercase();
    // The address becomes part of a Graph URL: only characters that are safe in a path.
    let valid_address = address.split_once('@').is_some_and(|(local, domain)| {
        !local.is_empty()
            && valid_host(domain)
            && local
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || "._+-'".contains(c))
    });
    if !valid_address {
        return bad("the address is not an e-mail address");
    }
    let secret_ref = input.secret_ref.trim().to_string();
    let ref_ok = secret_ref.len() <= 40
        && secret_ref
            .chars()
            .next()
            .is_some_and(|c| c.is_ascii_uppercase())
        && secret_ref
            .chars()
            .all(|c| c.is_ascii_uppercase() || c.is_ascii_digit() || c == '_');
    if !ref_ok {
        return bad(
            "the secret name must be upper-case letters, digits and underscores, starting with a letter",
        );
    }
    let port_ok = |p: Option<i32>| p.is_none_or(|p| (1..=65535).contains(&p));
    if !port_ok(input.imap_port) || !port_ok(input.smtp_port) {
        return bad("a port must be between 1 and 65535");
    }
    let mut c = Clean {
        name,
        address,
        kind: input.kind.clone(),
        secret_ref,
        tenant_id: None,
        client_id: None,
        username: None,
        imap_host: None,
        imap_port: None,
        imap_folder: "INBOX".into(),
        smtp_host: None,
        smtp_port: None,
        smtp_security: "starttls".into(),
    };
    match input.kind.as_str() {
        "graph" => {
            // Both go into a URL: letters, digits, dots and hyphens only (a GUID or a domain).
            let id_ok = |v: &Option<String>| v.as_deref().is_some_and(valid_host);
            c.tenant_id = clean(&input.tenant_id);
            c.client_id = clean(&input.client_id);
            if !id_ok(&c.tenant_id) || !id_ok(&c.client_id) {
                return bad("Microsoft Graph needs the tenant id and the application (client) id");
            }
        }
        "imap_smtp" => {
            c.username = clean(&input.username);
            c.imap_host = clean(&input.imap_host);
            c.smtp_host = clean(&input.smtp_host);
            c.imap_port = input.imap_port;
            c.smtp_port = input.smtp_port;
            if let Some(f) = clean(&input.imap_folder) {
                c.imap_folder = f;
            }
            if let Some(s) = clean(&input.smtp_security) {
                if !["starttls", "tls", "none"].contains(&s.as_str()) {
                    return bad("SMTP security must be starttls, tls or none");
                }
                c.smtp_security = s;
            }
            if c.username.is_none() {
                return bad("IMAP/SMTP needs a user name");
            }
            if !c.smtp_host.as_deref().is_some_and(valid_host) {
                return bad("IMAP/SMTP needs the SMTP server");
            }
            match c.imap_host.as_deref() {
                Some(h) if valid_host(h) => {}
                None if !input.inbound_enabled => {}
                _ => return bad("fetching mail needs the IMAP server"),
            }
        }
        _ => return bad("the kind must be graph or imap_smtp"),
    }
    Ok(c)
}

async fn check_team(
    conn: &mut PgConnection,
    company_id: Uuid,
    team: Option<Uuid>,
) -> AppResult<()> {
    let Some(team) = team else { return Ok(()) };
    let ok: bool = sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM helpdesk.teams WHERE id = $1 AND company_id = $2 AND active)",
    )
    .bind(team)
    .bind(company_id)
    .fetch_one(conn)
    .await?;
    if ok {
        Ok(())
    } else {
        Err(AppError::Validation(
            "the team does not exist or is not active".into(),
        ))
    }
}

fn conflict(e: sqlx::Error) -> AppError {
    match &e {
        sqlx::Error::Database(d) if d.is_unique_violation() => {
            AppError::Conflict("a mailbox with this name or address already exists".into())
        }
        _ => e.into(),
    }
}

/// Writes the settings of a mailbox (insert when `existing` is empty). A default mailbox must be
/// active; making one the default takes the mark away from the previous one.
async fn save(
    conn: &mut PgConnection,
    company_id: Uuid,
    existing: Option<Uuid>,
    input: &MailboxInput,
) -> AppResult<Uuid> {
    let c = validate(input)?;
    check_team(conn, company_id, input.team_id).await?;
    if input.is_default && !input.active {
        return Err(AppError::Validation(
            "the default mailbox must be active".into(),
        ));
    }
    let id = existing.unwrap_or_else(new_id);
    if input.is_default {
        sqlx::query(
            "UPDATE helpdesk.mailboxes SET is_default = false WHERE company_id = $1 AND id <> $2 AND is_default",
        )
        .bind(company_id)
        .bind(id)
        .execute(&mut *conn)
        .await?;
    }
    let sql = if existing.is_some() {
        "UPDATE helpdesk.mailboxes SET name = $3, address = $4, kind = $5, team_id = $6, is_default = $7, active = $8,
                inbound_enabled = $9, secret_ref = $10, tenant_id = $11, client_id = $12, username = $13,
                imap_host = $14, imap_port = $15, imap_tls = $16, imap_folder = $17, smtp_host = $18,
                smtp_port = $19, smtp_security = $20, updated_at = now()
         WHERE id = $1 AND company_id = $2"
    } else {
        "INSERT INTO helpdesk.mailboxes (id, company_id, name, address, kind, team_id, is_default, active,
                inbound_enabled, secret_ref, tenant_id, client_id, username, imap_host, imap_port, imap_tls,
                imap_folder, smtp_host, smtp_port, smtp_security)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20)"
    };
    let done = sqlx::query(sql)
        .bind(id)
        .bind(company_id)
        .bind(&c.name)
        .bind(&c.address)
        .bind(&c.kind)
        .bind(input.team_id)
        .bind(input.is_default)
        .bind(input.active)
        .bind(input.inbound_enabled)
        .bind(&c.secret_ref)
        .bind(&c.tenant_id)
        .bind(&c.client_id)
        .bind(&c.username)
        .bind(&c.imap_host)
        .bind(c.imap_port)
        .bind(input.imap_tls)
        .bind(&c.imap_folder)
        .bind(&c.smtp_host)
        .bind(c.smtp_port)
        .bind(&c.smtp_security)
        .execute(&mut *conn)
        .await
        .map_err(conflict)?;
    if done.rows_affected() == 0 {
        return Err(AppError::NotFound("mailbox"));
    }
    Ok(id)
}

fn audit_data(m: &Mailbox) -> serde_json::Value {
    serde_json::json!({
        "name": m.name, "address": m.address, "kind": m.kind, "active": m.active,
        "is_default": m.is_default, "inbound_enabled": m.inbound_enabled, "secret_ref": m.secret_ref,
    })
}

/// The mailboxes of the company, the default one first.
#[utoipa::path(get, path = "/helpdesk/mailboxes", tag = "helpdesk",
    responses((status = 200, body = Vec<Mailbox>), (status = 403, body = ErrorBody)))]
async fn list_mailboxes(
    State(state): State<AppState>,
    user: CurrentUser,
) -> AppResult<Json<Vec<Mailbox>>> {
    user.require(Permission::HelpdeskAdmin)?;
    let mut conn = state.db.acquire().await?;
    Ok(Json(load(&mut conn, user.company_id, None).await?))
}

#[utoipa::path(post, path = "/helpdesk/mailboxes", tag = "helpdesk", request_body = MailboxInput,
    responses((status = 201, body = Mailbox), (status = 403, body = ErrorBody), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn create_mailbox(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<MailboxInput>,
) -> AppResult<(StatusCode, Json<Mailbox>)> {
    user.require(Permission::HelpdeskAdmin)?;
    let mut tx = state.db.begin().await?;
    let id = save(&mut tx, user.company_id, None, &input).await?;
    let m = load(&mut tx, user.company_id, Some(id))
        .await?
        .pop()
        .ok_or(AppError::NotFound("mailbox"))?;
    audit::record(
        &mut tx,
        &user,
        "helpdesk_mailbox",
        id,
        "created",
        audit_data(&m),
    )
    .await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(m)))
}

#[utoipa::path(put, path = "/helpdesk/mailboxes/{id}", tag = "helpdesk", params(("id" = Uuid, Path)), request_body = MailboxInput,
    responses((status = 200, body = Mailbox), (status = 403, body = ErrorBody), (status = 404, body = ErrorBody), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn update_mailbox(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<MailboxInput>,
) -> AppResult<Json<Mailbox>> {
    user.require(Permission::HelpdeskAdmin)?;
    let mut tx = state.db.begin().await?;
    save(&mut tx, user.company_id, Some(id), &input).await?;
    // The status belongs to the old settings.
    sqlx::query("UPDATE helpdesk.mailboxes SET last_error = NULL WHERE id = $1")
        .bind(id)
        .execute(&mut *tx)
        .await?;
    let m = load(&mut tx, user.company_id, Some(id))
        .await?
        .pop()
        .ok_or(AppError::NotFound("mailbox"))?;
    audit::record(
        &mut tx,
        &user,
        "helpdesk_mailbox",
        id,
        "updated",
        audit_data(&m),
    )
    .await?;
    tx.commit().await?;
    Ok(Json(m))
}

/// Removes a mailbox. Its tickets and e-mails stay; replies on them then leave through the
/// default mailbox.
#[utoipa::path(delete, path = "/helpdesk/mailboxes/{id}", tag = "helpdesk", params(("id" = Uuid, Path)),
    responses((status = 204), (status = 403, body = ErrorBody), (status = 404, body = ErrorBody)))]
async fn delete_mailbox(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<StatusCode> {
    user.require(Permission::HelpdeskAdmin)?;
    let mut tx = state.db.begin().await?;
    let m = load(&mut tx, user.company_id, Some(id))
        .await?
        .pop()
        .ok_or(AppError::NotFound("mailbox"))?;
    sqlx::query("DELETE FROM helpdesk.mailboxes WHERE id = $1 AND company_id = $2")
        .bind(id)
        .bind(user.company_id)
        .execute(&mut *tx)
        .await?;
    audit::record(
        &mut tx,
        &user,
        "helpdesk_mailbox",
        id,
        "deleted",
        audit_data(&m),
    )
    .await?;
    tx.commit().await?;
    Ok(StatusCode::NO_CONTENT)
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(list_mailboxes, create_mailbox))
        .routes(routes!(update_mailbox, delete_mailbox))
}

/// The mailbox a reply or a system mail leaves through, with its sender address.
#[derive(Debug, Clone, FromRow)]
pub struct Sender {
    pub mailbox_id: Uuid,
    pub address: String,
}

/// The active mailbox to send through: the preferred one (the ticket's) when it is still active,
/// else the company's default mailbox. Empty when the company has neither.
pub async fn sender(
    conn: &mut PgConnection,
    company_id: Uuid,
    preferred: Option<Uuid>,
) -> Result<Option<Sender>, sqlx::Error> {
    sqlx::query_as(
        "SELECT id AS mailbox_id, address FROM helpdesk.mailboxes
         WHERE company_id = $1 AND active AND (id = $2 OR is_default)
         ORDER BY (id = $2) DESC NULLS LAST LIMIT 1",
    )
    .bind(company_id)
    .bind(preferred)
    .fetch_optional(conn)
    .await
}

// --- worker side -------------------------------------------------------------------------------

/// What the worker needs of an active mailbox.
#[derive(Debug, Clone, FromRow)]
pub struct ActiveMailbox {
    pub id: Uuid,
    pub company_id: Uuid,
    pub name: String,
    pub address: String,
    pub kind: String,
    pub team_id: Option<Uuid>,
    pub inbound_enabled: bool,
    pub secret_ref: String,
    pub tenant_id: Option<String>,
    pub client_id: Option<String>,
    pub username: Option<String>,
    pub imap_host: Option<String>,
    pub imap_port: Option<i32>,
    pub imap_tls: bool,
    pub imap_folder: String,
    pub smtp_host: Option<String>,
    pub smtp_port: Option<i32>,
    pub smtp_security: String,
}

pub async fn load_active(db: &PgPool) -> Result<Vec<ActiveMailbox>, sqlx::Error> {
    sqlx::query_as(
        "SELECT id, company_id, name, address, kind, team_id, inbound_enabled, secret_ref, tenant_id, client_id,
                username, imap_host, imap_port, imap_tls, imap_folder, smtp_host, smtp_port, smtp_security
         FROM helpdesk.mailboxes WHERE active ORDER BY created_at, id",
    )
    .fetch_all(db)
    .await
}

/// Looks up a secret by its reference; the worker reads `MAILBOX_SECRET_<reference>`.
pub type SecretLookup<'a> = &'a (dyn Fn(&str) -> Option<String> + Send + Sync);

/// The secret of a mailbox from the process environment.
pub fn env_secret(reference: &str) -> Option<String> {
    std::env::var(format!("{SECRET_ENV_PREFIX}{reference}"))
        .ok()
        .filter(|v| !v.is_empty())
}

fn port(p: Option<i32>, default: u16) -> u16 {
    p.and_then(|p| u16::try_from(p).ok()).unwrap_or(default)
}

impl ActiveMailbox {
    fn secret(&self, secrets: SecretLookup<'_>) -> anyhow::Result<String> {
        secrets(&self.secret_ref).ok_or_else(|| {
            anyhow::anyhow!(
                "the worker has no {SECRET_ENV_PREFIX}{} variable",
                self.secret_ref
            )
        })
    }

    fn source(&self) -> Source {
        Source {
            mailbox_id: self.id,
            team_id: self.team_id,
        }
    }

    fn graph(&self, secret: String) -> anyhow::Result<GraphMailbox> {
        Ok(GraphMailbox {
            mailbox_id: self.id,
            tenant_id: self
                .tenant_id
                .clone()
                .ok_or_else(|| anyhow::anyhow!("no tenant id"))?,
            client_id: self
                .client_id
                .clone()
                .ok_or_else(|| anyhow::anyhow!("no client id"))?,
            client_secret: secret,
            address: self.address.clone(),
        })
    }

    async fn poll(
        &self,
        db: &PgPool,
        graph: &GraphClient,
        secrets: SecretLookup<'_>,
    ) -> anyhow::Result<usize> {
        let secret = self.secret(secrets)?;
        match self.kind.as_str() {
            "graph" => {
                graph
                    .poll(db, &self.graph(secret)?, self.company_id, self.source())
                    .await
            }
            _ => {
                let cfg = ImapConfig {
                    host: self
                        .imap_host
                        .clone()
                        .ok_or_else(|| anyhow::anyhow!("no IMAP server"))?,
                    port: port(self.imap_port, if self.imap_tls { 993 } else { 143 }),
                    user: self.username.clone().unwrap_or_default(),
                    password: secret,
                    mailbox: self.imap_folder.clone(),
                    tls: self.imap_tls,
                    company_id: self.company_id,
                    source: Some(self.source()),
                };
                crate::imap::poll(db, &cfg).await
            }
        }
    }

    fn mailer(&self, graph: &GraphClient, secrets: SecretLookup<'_>) -> anyhow::Result<Mailer> {
        let secret = self.secret(secrets)?;
        match self.kind.as_str() {
            "graph" => Ok(Mailer::Graph(graph.clone(), self.graph(secret)?)),
            _ => {
                let security = match self.smtp_security.as_str() {
                    "tls" => SmtpSecurity::Tls,
                    "none" => SmtpSecurity::None,
                    _ => SmtpSecurity::StartTls,
                };
                let default_port = match security {
                    SmtpSecurity::Tls => 465,
                    SmtpSecurity::StartTls => 587,
                    SmtpSecurity::None => 25,
                };
                Mailer::smtp(
                    self.smtp_host
                        .as_deref()
                        .ok_or_else(|| anyhow::anyhow!("no SMTP server"))?,
                    port(self.smtp_port, default_port),
                    self.username.clone(),
                    Some(secret),
                    security,
                )
            }
        }
    }
}

/// Fetches the mail of every active mailbox that receives, and records per mailbox when it was
/// tried and whether it worked. One failing mailbox does not stop the others. Returns the number
/// of e-mails ingested.
pub async fn poll_all(
    db: &PgPool,
    mailboxes: &[ActiveMailbox],
    graph: &GraphClient,
    secrets: SecretLookup<'_>,
) -> usize {
    let mut total = 0;
    for m in mailboxes.iter().filter(|m| m.inbound_enabled) {
        let result = m.poll(db, graph, secrets).await;
        let error = match &result {
            Ok(n) => {
                total += n;
                None
            }
            Err(e) => {
                tracing::error!(mailbox = %m.name, error = ?e, "fetching mail failed");
                // The whole chain: the first line alone ("connecting to IMAP server") says too little.
                Some(format!("{e:#}").chars().take(500).collect::<String>())
            }
        };
        if let Err(e) = sqlx::query(
            "UPDATE helpdesk.mailboxes SET last_poll_at = now(), last_error = $2,
                    last_ok_at = CASE WHEN $2 IS NULL THEN now() ELSE last_ok_at END
             WHERE id = $1",
        )
        .bind(m.id)
        .bind(&error)
        .execute(db)
        .await
        {
            tracing::error!(mailbox = %m.name, error = ?e, "recording the mailbox status failed");
        }
    }
    total
}

/// One transport per active mailbox, or why it cannot send (e.g. the secret is missing): an
/// e-mail for that mailbox then fails with that reason instead of leaving through another server.
pub fn transports(
    mailboxes: &[ActiveMailbox],
    graph: &GraphClient,
    secrets: SecretLookup<'_>,
) -> HashMap<Uuid, Result<Mailer, String>> {
    mailboxes
        .iter()
        .map(|m| {
            (
                m.id,
                m.mailer(graph, secrets)
                    .map_err(|e| format!("mailbox {}: {e:#}", m.name)),
            )
        })
        .collect()
}
