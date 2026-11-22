//! The customer's view of the helpdesk, for the portal.
//!
//! A customer sees only tickets of their own customer record that are not internal, and — unless
//! their portal scope is `customer` — only those they raised themselves. Internal notes, phone
//! call summaries and internal states never leave this module.

use chrono::{DateTime, Datelike, Utc};
use serde::Serialize;
use sqlx::{FromRow, PgConnection};
use tradocraft_core::files::FileInfo;
use tradocraft_core::{audit, new_id, AppError, AppResult};
use utoipa::ToSchema;
use uuid::Uuid;

/// Categories a customer can choose when opening a ticket.
pub const PORTAL_CATEGORIES: [&str; 4] = ["question", "service", "complaint", "other"];
const MAX_SUBJECT: usize = 200;
const MAX_BODY: usize = 20_000;

/// Who is looking: the logged-in contact.
#[derive(Debug, Clone)]
pub struct Viewer {
    pub company_id: Uuid,
    pub contact_id: Uuid,
    pub customer_id: Uuid,
    /// own | customer
    pub scope: String,
}

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct PortalTicket {
    pub id: Uuid,
    pub number: String,
    pub subject: String,
    /// open | pending_customer (we wait for the customer) | closed
    pub status: String,
    pub category: String,
    /// Who raised it (colleagues' tickets are visible with the `customer` scope).
    pub contact_name: String,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub closed_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct PortalMessage {
    pub id: Uuid,
    /// incoming (from the customer) | outgoing (from us)
    pub direction: String,
    pub author_name: String,
    pub body: String,
    pub created_at: DateTime<Utc>,
    /// Files sent with the message. Files on internal notes are never shown.
    #[sqlx(skip)]
    pub attachments: Vec<FileInfo>,
}

/// The article kinds a customer may see (and so the files linked to them).
pub const VISIBLE_KINDS: [&str; 3] = ["email_in", "email_out", "portal_in"];

#[derive(Debug, Serialize, ToSchema)]
pub struct PortalTicketDetail {
    pub ticket: PortalTicket,
    pub messages: Vec<PortalMessage>,
}

// Internal states are not shown: new, open and pending_internal all read as "open".
const SELECT: &str = "SELECT t.id, t.number, t.subject,
        CASE WHEN t.status IN ('pending_customer', 'closed') THEN t.status ELSE 'open' END AS status,
        t.category, t.contact_name, t.created_at, t.updated_at, t.closed_at
     FROM helpdesk.tickets t";

const VISIBLE: &str =
    "t.company_id = $1 AND NOT t.internal AND t.merged_into_id IS NULL AND t.customer_id = $2
     AND ($3 = 'customer' OR t.contact_id = $4)";

pub async fn list(conn: &mut PgConnection, v: &Viewer) -> AppResult<Vec<PortalTicket>> {
    Ok(sqlx::query_as(sqlx::AssertSqlSafe(format!(
        "{SELECT} WHERE {VISIBLE} ORDER BY (t.status = 'closed'), t.updated_at DESC LIMIT 200"
    )))
    .bind(v.company_id)
    .bind(v.customer_id)
    .bind(&v.scope)
    .bind(v.contact_id)
    .fetch_all(conn)
    .await?)
}

pub async fn get(conn: &mut PgConnection, v: &Viewer, id: Uuid) -> AppResult<PortalTicketDetail> {
    let ticket: PortalTicket = sqlx::query_as(sqlx::AssertSqlSafe(format!("{SELECT} WHERE t.id = $5 AND {VISIBLE}")))
        .bind(v.company_id)
        .bind(v.customer_id)
        .bind(&v.scope)
        .bind(v.contact_id)
        .bind(id)
        .fetch_optional(&mut *conn)
        .await?
        .ok_or(AppError::NotFound("ticket"))?;
    let mut messages: Vec<PortalMessage> = sqlx::query_as(
        "SELECT a.id,
                CASE WHEN a.kind = 'email_out' THEN 'outgoing' ELSE 'incoming' END AS direction,
                CASE WHEN a.kind = 'email_out' THEN coalesce(u.display_name, a.from_name)
                     ELSE coalesce(nullif(btrim(ct.first_name || ' ' || ct.last_name), ''), a.from_name) END AS author_name,
                a.body, a.created_at
         FROM helpdesk.articles a
         LEFT JOIN core.users u ON u.id = a.author_user_id
         LEFT JOIN crm.contacts ct ON ct.id = a.contact_id
         WHERE a.ticket_id = $1 AND a.kind IN ('email_in', 'email_out', 'portal_in')
         ORDER BY a.created_at, a.id",
    )
    .bind(id)
    .fetch_all(&mut *conn)
    .await?;
    let ids: Vec<Uuid> = messages.iter().map(|m| m.id).collect();
    let mut files = crate::attachments::for_articles(conn, &ids).await?;
    for m in &mut messages {
        m.attachments = files.remove(&m.id).unwrap_or_default();
    }
    Ok(PortalTicketDetail { ticket, messages })
}

fn check_text(subject: Option<&str>, body: &str) -> AppResult<()> {
    if body.trim().is_empty() {
        return Err(AppError::Validation("the message is empty".into()));
    }
    if body.chars().count() > MAX_BODY {
        return Err(AppError::Validation(format!(
            "the message is too long (at most {MAX_BODY} characters)"
        )));
    }
    if let Some(s) = subject {
        if s.trim().is_empty() {
            return Err(AppError::Validation("a subject is required".into()));
        }
        if s.chars().count() > MAX_SUBJECT {
            return Err(AppError::Validation(format!(
                "the subject is too long (at most {MAX_SUBJECT} characters)"
            )));
        }
    }
    Ok(())
}

/// A customer opens a ticket. It starts as `new`, unassigned, in the customer's language.
pub async fn open(
    conn: &mut PgConnection,
    v: &Viewer,
    subject: &str,
    category: &str,
    body: &str,
) -> AppResult<PortalTicketDetail> {
    check_text(Some(subject), body)?;
    if !PORTAL_CATEGORIES.contains(&category) {
        return Err(AppError::Validation(format!(
            "category must be one of {}",
            PORTAL_CATEGORIES.join(", ")
        )));
    }
    let contact = tradocraft_crm::contacts::get_contact(conn, v.contact_id).await?;
    let year = Utc::now().year();
    let n = tradocraft_core::numbering::next_number(conn, v.company_id, "ticket", year).await?;
    let number = format!("T{year}-{n:05}");
    let id = new_id();
    let email = contact.primary_email().unwrap_or_default().to_string();
    sqlx::query(
        "INSERT INTO helpdesk.tickets (id, company_id, number, subject, category, language, customer_id,
                                       contact_id, contact_name, contact_email, channel)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, 'portal')",
    )
    .bind(id)
    .bind(v.company_id)
    .bind(&number)
    .bind(subject.trim())
    .bind(category)
    .bind(&contact.effective_language)
    .bind(v.customer_id)
    .bind(contact.id)
    .bind(&contact.full_name)
    .bind(&email)
    .execute(&mut *conn)
    .await?;
    insert_message(conn, id, &contact, &email, subject.trim(), body).await?;
    crate::teams::assign_default_team(conn, v.company_id, id).await?;
    crate::collab::record_event(conn, v.company_id, id, "created", None, Default::default())
        .await?;
    crate::sla::sync(conn, id).await?;
    crate::automation::run(conn, v.company_id, id, "created").await?;
    audit::record_system(
        conn,
        v.company_id,
        "ticket",
        id,
        "created_in_portal",
        serde_json::json!({ "number": number, "contact_id": contact.id }),
    )
    .await?;
    get(conn, v, id).await
}

async fn insert_message(
    conn: &mut PgConnection,
    ticket_id: Uuid,
    contact: &tradocraft_crm::contacts::Contact,
    email: &str,
    subject: &str,
    body: &str,
) -> AppResult<Uuid> {
    let article_id = new_id();
    sqlx::query(
        "INSERT INTO helpdesk.articles (id, ticket_id, kind, from_address, from_name, subject, body, language, contact_id)
         VALUES ($1, $2, 'portal_in', $3, $4, $5, $6, $7, $8)",
    )
    .bind(article_id)
    .bind(ticket_id)
    .bind(email)
    .bind(&contact.full_name)
    .bind(subject)
    .bind(body.trim())
    .bind(&contact.effective_language)
    .bind(contact.id)
    .execute(conn)
    .await?;
    Ok(article_id)
}

/// A customer adds a message. Like a reply by e-mail, it reopens a ticket that waited for the
/// customer or was closed.
pub async fn add_message(
    conn: &mut PgConnection,
    v: &Viewer,
    ticket_id: Uuid,
    body: &str,
    attachment_ids: &[Uuid],
) -> AppResult<PortalTicketDetail> {
    check_text(None, body)?;
    // Only a ticket the customer may see can be answered; this also checks the company.
    let visible = get(conn, v, ticket_id).await?;
    crate::checklists::lock_ticket(conn, v.company_id, ticket_id).await?;
    let contact = tradocraft_crm::contacts::get_contact(conn, v.contact_id).await?;
    let email = contact.primary_email().unwrap_or_default().to_string();
    let article_id = insert_message(conn, ticket_id, &contact, &email, "", body).await?;
    crate::attachments::link(
        conn,
        ticket_id,
        article_id,
        attachment_ids,
        Some(contact.id),
    )
    .await?;
    sqlx::query(
        "UPDATE helpdesk.tickets SET
            status = CASE WHEN status IN ('pending_customer', 'closed') THEN 'open' ELSE status END,
            closed_at = NULL, updated_at = now()
         WHERE id = $1",
    )
    .bind(ticket_id)
    .execute(&mut *conn)
    .await?;
    crate::sla::sync(conn, ticket_id).await?;
    crate::automation::run(conn, v.company_id, ticket_id, "customer_replied").await?;
    crate::collab::notify_watchers(
        conn,
        v.company_id,
        ticket_id,
        None,
        &[],
        crate::collab::Change::CustomerReply,
    )
    .await?;
    audit::record_system(
        conn,
        v.company_id,
        "ticket",
        ticket_id,
        "portal_message",
        serde_json::json!({ "number": visible.ticket.number, "contact_id": contact.id }),
    )
    .await?;
    get(conn, v, ticket_id).await
}

/// A customer uploads a file to a ticket they can see (JPEG, PNG, WebP or PDF). It becomes part
/// of the conversation when it is passed in `attachment_ids` of the next message.
pub async fn upload_attachment(
    conn: &mut PgConnection,
    blobs: &tradocraft_core::BlobStore,
    v: &Viewer,
    ticket_id: Uuid,
    params: &crate::attachments::UploadParams,
    bytes: &[u8],
) -> AppResult<FileInfo> {
    get(conn, v, ticket_id).await?;
    let contact = tradocraft_crm::contacts::get_contact(conn, v.contact_id).await?;
    crate::attachments::upload(
        conn,
        blobs,
        v.company_id,
        ticket_id,
        params,
        bytes,
        crate::attachments::Uploader {
            user_id: None,
            contact_id: Some(contact.id),
            name: &contact.full_name,
        },
    )
    .await
}

/// A file of a message the customer can see. Files of internal notes are "not found".
pub async fn attachment_data(
    conn: &mut PgConnection,
    blobs: &tradocraft_core::BlobStore,
    v: &Viewer,
    ticket_id: Uuid,
    file_id: Uuid,
) -> AppResult<(String, String, Vec<u8>)> {
    get(conn, v, ticket_id).await?;
    crate::attachments::data(
        conn,
        blobs,
        v.company_id,
        ticket_id,
        file_id,
        Some(&VISIBLE_KINDS),
        Some(v.contact_id),
    )
    .await
}
