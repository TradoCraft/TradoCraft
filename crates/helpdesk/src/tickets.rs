//! Tickets: the conversation with a customer (or an internal question), with links to the
//! customer, lead, quotation and order it is about.

use axum::body::Bytes;
use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::Json;
use chrono::{DateTime, Datelike, Utc};
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection};
use tradocraft_core::{
    audit, is_language, new_id, AppError, AppResult, AppState, CurrentUser, Permission, LANGUAGES,
};
use utoipa::{IntoParams, ToSchema};
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::classify::ticket_tag;
use crate::sla::{self, SlaInput, TicketSla};
use tradocraft_core::files::FileInfo;

type ErrorBody = tradocraft_core::error::ErrorBody;

pub const STATUSES: [&str; 5] = [
    "new",
    "open",
    "pending_customer",
    "pending_internal",
    "closed",
];
pub const PRIORITIES: [&str; 4] = ["low", "normal", "high", "urgent"];
pub const CATEGORIES: [&str; 8] = [
    "question",
    "lead",
    "quote_change",
    "order_confirmation",
    "production_question",
    "service",
    "complaint",
    "other",
];

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct Ticket {
    pub id: Uuid,
    pub number: String,
    pub subject: String,
    /// new | open | pending_customer | pending_internal | closed
    pub status: String,
    /// low | normal | high | urgent
    pub priority: String,
    /// question | lead | quote_change | order_confirmation | production_question | service | complaint | other
    pub category: String,
    /// What the system guessed from the last incoming e-mail.
    pub suggested_category: Option<String>,
    /// nl | fr | en | de | es — the language to answer in.
    pub language: String,
    pub customer_id: Option<Uuid>,
    pub customer_name: Option<String>,
    /// The person at the customer this ticket is about (see the contacts of the customer).
    pub contact_id: Option<Uuid>,
    pub contact_name: String,
    pub contact_email: String,
    pub owner_user_id: Option<Uuid>,
    pub owner_name: Option<String>,
    pub internal: bool,
    pub quotation_id: Option<Uuid>,
    pub quotation_number: Option<String>,
    pub quotation_revision: Option<i32>,
    pub quotation_status: Option<String>,
    pub opportunity_id: Option<Uuid>,
    pub opportunity_number: Option<String>,
    pub order_id: Option<Uuid>,
    pub order_number: Option<String>,
    pub article_count: i64,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub first_response_at: Option<DateTime<Utc>>,
    pub closed_at: Option<DateTime<Utc>>,
    /// The queue the ticket waits in (the owner is the person working on it).
    pub team_id: Option<Uuid>,
    pub team_name: Option<String>,
    pub tags: Vec<String>,
    /// Total logged time in minutes.
    pub time_minutes: i64,
    /// Set when this ticket was merged into another one (it is closed).
    pub merged_into_id: Option<Uuid>,
    pub merged_into_number: Option<String>,
    /// The customer's latest satisfaction rating: good | bad.
    pub csat_rating: Option<String>,
    pub csat_comment: Option<String>,
    pub csat_rated_at: Option<DateTime<Utc>>,
    /// Set when a colleague escalated the ticket by hand.
    pub escalated_at: Option<DateTime<Utc>>,
    pub escalated_by: Option<Uuid>,
    pub escalated_by_name: Option<String>,
    /// For the caller: there is activity by others since they last read the ticket and they are
    /// involved (see `collab`). Filled by the list and by `GET /tickets/{id}`.
    #[sqlx(skip)]
    pub unread: bool,
    /// For the caller: they follow the ticket. Filled like `unread`.
    #[sqlx(skip)]
    pub watching: bool,
    /// Due times, breach flags and minutes remaining.
    #[sqlx(skip)]
    pub sla: TicketSla,
    #[serde(skip)]
    sla_first_response_due_at: Option<DateTime<Utc>>,
    #[serde(skip)]
    sla_resolution_due_at: Option<DateTime<Utc>>,
    #[serde(skip)]
    sla_first_response_minutes: Option<i32>,
    #[serde(skip)]
    sla_resolution_minutes: Option<i32>,
    #[serde(skip)]
    sla_paused_at: Option<DateTime<Utc>>,
}

impl Ticket {
    fn with_sla(mut self, cal: Option<&sla::Calendar>) -> Self {
        self.sla = sla::evaluate_in(
            cal,
            &SlaInput {
                first_response_due_at: self.sla_first_response_due_at,
                resolution_due_at: self.sla_resolution_due_at,
                first_response_minutes: self.sla_first_response_minutes,
                resolution_minutes: self.sla_resolution_minutes,
                paused_at: self.sla_paused_at,
                first_response_at: self.first_response_at,
                closed_at: self.closed_at,
            },
            Utc::now(),
        );
        self
    }
}

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct Article {
    pub id: Uuid,
    /// email_in | email_out | note | call_in | call_out | portal_in
    pub kind: String,
    pub from_address: String,
    pub from_name: String,
    pub to_addresses: Vec<String>,
    pub cc_addresses: Vec<String>,
    pub subject: String,
    pub body: String,
    pub language: Option<String>,
    pub author_user_id: Option<Uuid>,
    pub author_name: Option<String>,
    /// The person this message or call is from or to, when known.
    pub contact_id: Option<Uuid>,
    pub contact_name: Option<String>,
    /// For calls: the number as typed.
    pub phone_number: Option<String>,
    pub duration_seconds: Option<i32>,
    /// For outgoing e-mail: queued | sent | failed
    pub delivery: Option<String>,
    pub delivery_error: Option<String>,
    pub created_at: DateTime<Utc>,
    pub sent_at: Option<DateTime<Utc>>,
    /// Files sent or received with the message.
    #[sqlx(skip)]
    pub attachments: Vec<FileInfo>,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct TicketDetail {
    pub ticket: Ticket,
    pub articles: Vec<Article>,
    /// Colleagues who follow the ticket.
    pub watchers: Vec<crate::collab::Watcher>,
    /// Colleagues who opened the ticket, most recent first ("seen by").
    pub readers: Vec<crate::collab::Reader>,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct TicketPage {
    pub items: Vec<Ticket>,
    pub total: i64,
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct ListParams {
    /// Searches number, subject, contact and customer.
    pub q: Option<String>,
    /// A status, or `active` for everything not closed.
    pub status: Option<String>,
    /// `me` for my tickets, `none` for unassigned, or a user id.
    pub owner: Option<String>,
    pub customer_id: Option<Uuid>,
    pub category: Option<String>,
    /// Tickets in this team.
    pub team_id: Option<Uuid>,
    /// Tickets that are mine: I own them, or nobody owns them and they are in one of my teams.
    pub mine: Option<bool>,
    /// Tickets with neither an owner nor a team.
    pub unassigned: Option<bool>,
    /// `breached` or `at_risk` (under 25 % of a window left).
    pub sla: Option<String>,
    /// Tickets with this tag.
    pub tag: Option<String>,
    /// Only tickets that are unread for me.
    pub unread: Option<bool>,
    /// Only tickets I follow.
    pub watching: Option<bool>,
    /// Only tickets that were escalated by hand.
    pub escalated: Option<bool>,
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}

/// A ticket opened by hand (phone call, visit, internal question).
#[derive(Debug, Deserialize, ToSchema)]
pub struct NewTicketInput {
    pub subject: String,
    pub customer_id: Option<Uuid>,
    /// The person; fills in customer, name, e-mail address and language (their own, else the
    /// customer's) unless given.
    pub contact_id: Option<Uuid>,
    #[serde(default)]
    pub contact_name: String,
    #[serde(default)]
    pub contact_email: String,
    /// Defaults to the contact's language, else the customer's, else the company's.
    pub language: Option<String>,
    #[serde(default = "default_category")]
    pub category: String,
    #[serde(default)]
    pub internal: bool,
    /// First internal note (what was asked).
    pub body: String,
}

fn default_category() -> String {
    "question".into()
}

/// Full update of the ticket's fields and links.
#[derive(Debug, Deserialize, ToSchema)]
pub struct TicketInput {
    pub subject: String,
    pub status: String,
    pub priority: String,
    pub category: String,
    pub language: String,
    pub owner_user_id: Option<Uuid>,
    pub customer_id: Option<Uuid>,
    pub contact_id: Option<Uuid>,
    #[serde(default)]
    pub contact_name: String,
    #[serde(default)]
    pub contact_email: String,
    pub quotation_id: Option<Uuid>,
    pub opportunity_id: Option<Uuid>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct NoteInput {
    pub body: String,
    /// Files uploaded to the ticket (`POST /tickets/{id}/attachments`) to attach to this note.
    #[serde(default)]
    pub attachment_ids: Vec<Uuid>,
    /// New ticket status; unchanged when omitted.
    pub status: Option<String>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct ReplyInput {
    /// Defaults to the ticket's contact e-mail.
    #[serde(default)]
    pub to: Vec<String>,
    #[serde(default)]
    pub cc: Vec<String>,
    /// Defaults to "Re: <ticket subject>". The ticket tag is always added.
    pub subject: Option<String>,
    pub body: String,
    /// Files uploaded to the ticket (`POST /tickets/{id}/attachments`) to send with the e-mail.
    #[serde(default)]
    pub attachment_ids: Vec<Uuid>,
    /// New ticket status; defaults to pending_customer.
    pub status: Option<String>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct LeadInput {
    /// Defaults to the ticket subject.
    pub title: Option<String>,
    #[schema(value_type = Option<String>)]
    pub expected_value: Option<Decimal>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct ConvertTicketInput {
    /// The customer's purchase order number or reference.
    #[serde(default)]
    pub customer_reference: String,
    #[serde(default)]
    pub notes: String,
}

/// A question from production about an order, routed to the salesperson who sold it.
#[derive(Debug, Deserialize, ToSchema)]
pub struct ProductionQuestionInput {
    pub order_id: Uuid,
    pub subject: String,
    pub body: String,
}

/// A phone call, logged on a ticket (existing or new).
#[derive(Debug, Deserialize, ToSchema)]
pub struct CallInput {
    /// Add to this ticket; without it a new ticket is opened.
    pub ticket_id: Option<Uuid>,
    /// in (the customer called us) | out (we called the customer)
    pub direction: String,
    /// The number that called or was called, in any format. Used to find the person when
    /// `contact_id` is not given.
    #[serde(default)]
    pub phone_number: String,
    /// Who it was. Defaults to the contact with this phone number, if there is exactly one.
    pub contact_id: Option<Uuid>,
    /// New ticket only, for a caller who is not a known contact yet.
    pub customer_id: Option<Uuid>,
    pub duration_seconds: Option<i32>,
    /// What was discussed.
    pub summary: String,
    /// New ticket only; defaults to the first line of the summary.
    pub subject: Option<String>,
    /// New ticket only.
    #[serde(default = "default_category")]
    pub category: String,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct InboundResult {
    pub ticket_id: Uuid,
    pub ticket_number: String,
    pub new_ticket: bool,
    pub duplicate: bool,
}

const SELECT: &str = "SELECT t.id, t.number, t.subject, t.status, t.priority, t.category, t.suggested_category,
        t.language::text AS language, t.customer_id, c.name AS customer_name, t.contact_id, t.contact_name, t.contact_email,
        t.owner_user_id, u.display_name AS owner_name, t.internal,
        t.quotation_id, q.number AS quotation_number, q.revision AS quotation_revision, q.status AS quotation_status,
        t.opportunity_id, op.number AS opportunity_number, t.order_id, o.number AS order_number,
        (SELECT count(*) FROM helpdesk.articles a WHERE a.ticket_id = t.id) AS article_count,
        t.created_at, t.updated_at, t.first_response_at, t.closed_at,
        t.team_id, tm.name AS team_name,
        coalesce((SELECT array_agg(g.tag ORDER BY g.tag) FROM helpdesk.ticket_tags g WHERE g.ticket_id = t.id), '{}') AS tags,
        coalesce((SELECT sum(e.minutes) FROM helpdesk.time_entries e WHERE e.ticket_id = t.id), 0)::bigint AS time_minutes,
        t.merged_into_id, (SELECT m.number FROM helpdesk.tickets m WHERE m.id = t.merged_into_id) AS merged_into_number,
        cs.rating AS csat_rating, cs.comment AS csat_comment, cs.rated_at AS csat_rated_at,
        t.escalated_at, t.escalated_by, eb.display_name AS escalated_by_name,
        t.first_response_due_at AS sla_first_response_due_at, t.resolution_due_at AS sla_resolution_due_at,
        t.sla_first_response_minutes, t.sla_resolution_minutes, t.sla_paused_at
     FROM helpdesk.tickets t
     LEFT JOIN helpdesk.teams tm ON tm.id = t.team_id
     LEFT JOIN LATERAL (SELECT s.rating, s.comment, s.rated_at FROM helpdesk.csat_surveys s
                        WHERE s.ticket_id = t.id AND s.rated_at IS NOT NULL
                        ORDER BY s.rated_at DESC LIMIT 1) cs ON true
     LEFT JOIN crm.customers c ON c.id = t.customer_id
     LEFT JOIN core.users u ON u.id = t.owner_user_id
     LEFT JOIN core.users eb ON eb.id = t.escalated_by
     LEFT JOIN sales.quotations q ON q.id = t.quotation_id
     LEFT JOIN crm.opportunities op ON op.id = t.opportunity_id
     LEFT JOIN sales.orders o ON o.id = t.order_id";

pub async fn load_ticket(conn: &mut PgConnection, company_id: Uuid, id: Uuid) -> AppResult<Ticket> {
    let ticket =
        sqlx::query_as::<_, Ticket>(&format!("{SELECT} WHERE t.id = $1 AND t.company_id = $2"))
            .bind(id)
            .bind(company_id)
            .fetch_optional(&mut *conn)
            .await?
            .ok_or(AppError::NotFound("ticket"))?;
    let cal = crate::calendar::load_calendar(conn, company_id, ticket.team_id).await?;
    Ok(ticket.with_sla(cal.as_ref()))
}

pub async fn load_detail(
    conn: &mut PgConnection,
    company_id: Uuid,
    id: Uuid,
) -> AppResult<TicketDetail> {
    let ticket = load_ticket(conn, company_id, id).await?;
    let mut articles: Vec<Article> = sqlx::query_as(
        "SELECT a.id, a.kind, a.from_address, a.from_name, a.to_addresses, a.cc_addresses, a.subject, a.body,
                a.language::text AS language, a.author_user_id, u.display_name AS author_name,
                a.contact_id, nullif(btrim(ct.first_name || ' ' || ct.last_name), '') AS contact_name,
                a.phone_number, a.duration_seconds, a.delivery, a.delivery_error, a.created_at, a.sent_at
         FROM helpdesk.articles a LEFT JOIN core.users u ON u.id = a.author_user_id
         LEFT JOIN crm.contacts ct ON ct.id = a.contact_id
         WHERE a.ticket_id = $1 ORDER BY a.created_at, a.id",
    )
    .bind(id)
    .fetch_all(&mut *conn)
    .await?;
    let ids: Vec<Uuid> = articles.iter().map(|a| a.id).collect();
    let mut files = crate::attachments::for_articles(conn, &ids).await?;
    for a in &mut articles {
        a.attachments = files.remove(&a.id).unwrap_or_default();
    }
    let watchers = crate::collab::load_watchers(conn, id).await?;
    let readers = crate::collab::load_readers(conn, id).await?;
    Ok(TicketDetail {
        ticket,
        articles,
        watchers,
        readers,
    })
}

fn check_one_of(field: &str, value: &str, allowed: &[&str]) -> AppResult<()> {
    if allowed.contains(&value) {
        Ok(())
    } else {
        Err(AppError::Validation(format!(
            "{field} must be one of {}",
            allowed.join(", ")
        )))
    }
}

async fn next_ticket_number(conn: &mut PgConnection, company_id: Uuid) -> AppResult<String> {
    let year = Utc::now().year();
    let n = tradocraft_core::numbering::next_number(conn, company_id, "ticket", year).await?;
    Ok(format!("T{year}-{n:05}"))
}

pub(crate) async fn add_note(
    conn: &mut PgConnection,
    user: &CurrentUser,
    ticket_id: Uuid,
    body: &str,
) -> AppResult<Uuid> {
    let id = new_id();
    sqlx::query(
        "INSERT INTO helpdesk.articles (id, ticket_id, kind, from_name, body, author_user_id) VALUES ($1, $2, 'note', $3, $4, $5)",
    )
    .bind(id)
    .bind(ticket_id)
    .bind(&user.display_name)
    .bind(body)
    .bind(user.user_id)
    .execute(conn)
    .await?;
    Ok(id)
}

/// An internal note written by another module on behalf of a colleague (e.g. "repair R2026-00001
/// registered"). Never sent to the customer.
pub async fn add_linked_note(
    conn: &mut PgConnection,
    user: &CurrentUser,
    ticket_id: Uuid,
    body: &str,
) -> AppResult<()> {
    add_note(conn, user, ticket_id, body).await?;
    Ok(())
}

async fn set_status(
    conn: &mut PgConnection,
    user: &CurrentUser,
    ticket_id: Uuid,
    status: &str,
) -> AppResult<()> {
    check_one_of("status", status, &STATUSES)?;
    let old: String = sqlx::query_scalar("SELECT status FROM helpdesk.tickets WHERE id = $1")
        .bind(ticket_id)
        .fetch_one(&mut *conn)
        .await?;
    let was_closed = old == "closed";
    if old != status {
        crate::collab::record_event(
            conn,
            user.company_id,
            ticket_id,
            "status",
            Some(user.user_id),
            crate::collab::EventData {
                from_value: Some(old),
                to_value: Some(status.into()),
                ..Default::default()
            },
        )
        .await?;
    }
    sqlx::query(
        "UPDATE helpdesk.tickets SET status = $2, updated_at = now(),
                closed_at = CASE WHEN $2 = 'closed' THEN coalesce(closed_at, now()) ELSE NULL END
         WHERE id = $1",
    )
    .bind(ticket_id)
    .bind(status)
    .execute(&mut *conn)
    .await?;
    sla::sync(conn, ticket_id).await?;
    if status == "closed" && !was_closed {
        crate::csat::queue_survey(conn, ticket_id).await?;
    }
    Ok(())
}

async fn customer_language(
    conn: &mut PgConnection,
    customer_id: Option<Uuid>,
    company_id: Uuid,
) -> AppResult<String> {
    if let Some(c) = customer_id {
        if let Some(l) = sqlx::query_scalar::<_, String>(
            "SELECT language::text FROM crm.customers WHERE id = $1",
        )
        .bind(c)
        .fetch_optional(&mut *conn)
        .await?
        {
            return Ok(l);
        }
    }
    Ok(
        sqlx::query_scalar("SELECT default_language::text FROM core.companies WHERE id = $1")
            .bind(company_id)
            .fetch_one(conn)
            .await?,
    )
}

#[utoipa::path(get, path = "/tickets", tag = "helpdesk", params(ListParams), responses((status = 200, body = TicketPage)))]
async fn list_tickets(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(p): Query<ListParams>,
) -> AppResult<Json<TicketPage>> {
    user.require(Permission::HelpdeskRead)?;
    let pattern =
        p.q.as_deref()
            .map(|q| format!("%{}%", q.trim().to_lowercase()));
    let (owner, unassigned) = match p.owner.as_deref() {
        Some("me") => (Some(user.user_id), false),
        Some("none") => (None, true),
        Some(id) => (
            Some(Uuid::parse_str(id).map_err(|_| AppError::Validation("invalid owner".into()))?),
            false,
        ),
        None => (None, false),
    };
    let sla_filter = match p.sla.as_deref() {
        None => None,
        Some("breached") => Some(sla::sql::breached()),
        Some("at_risk") => Some(sla::sql::at_risk()),
        Some(_) => {
            return Err(AppError::Validation(
                "sla must be breached or at_risk".into(),
            ))
        }
    };
    let tag = p
        .tag
        .as_deref()
        .map(crate::extras::normalize_tag)
        .transpose()?;
    let filter = format!(
        "WHERE t.company_id = $1
          AND ($2::text IS NULL OR lower(t.number) LIKE $2 OR lower(t.subject) LIKE $2
               OR lower(t.contact_email) LIKE $2 OR lower(t.contact_name) LIKE $2 OR lower(coalesce(c.name, '')) LIKE $2)
          AND ($3::text IS NULL OR ($3 = 'active' AND t.status <> 'closed') OR t.status = $3)
          AND ($4::uuid IS NULL OR t.owner_user_id = $4)
          AND (NOT $5 OR t.owner_user_id IS NULL)
          AND ($6::uuid IS NULL OR t.customer_id = $6)
          AND ($7::text IS NULL OR t.category = $7)
          AND ($8::uuid IS NULL OR t.team_id = $8)
          AND (NOT $9 OR t.owner_user_id = $10
               OR (t.owner_user_id IS NULL AND t.team_id IN (SELECT m.team_id FROM helpdesk.team_members m WHERE m.user_id = $10)))
          AND (NOT $11 OR (t.owner_user_id IS NULL AND t.team_id IS NULL))
          AND ($12::text IS NULL OR EXISTS (SELECT 1 FROM helpdesk.ticket_tags g WHERE g.ticket_id = t.id AND g.tag = $12))
          AND (NOT $13 OR {unread})
          AND (NOT $14 OR {watching})
          AND (NOT $15 OR t.escalated_at IS NOT NULL)
          AND {}",
        sla_filter.as_deref().unwrap_or("true"),
        unread = crate::collab::unread_sql("$10"),
        watching = crate::collab::watching_sql("$10"),
    );
    let mine = p.mine.unwrap_or(false);
    let only_unassigned = p.unassigned.unwrap_or(false);
    let items: Vec<Ticket> = sqlx::query_as(&format!(
        "{SELECT} {filter}
         ORDER BY CASE t.priority WHEN 'urgent' THEN 0 WHEN 'high' THEN 1 ELSE 2 END, t.updated_at DESC
         LIMIT $16 OFFSET $17"
    ))
    .bind(user.company_id)
    .bind(&pattern)
    .bind(&p.status)
    .bind(owner)
    .bind(unassigned)
    .bind(p.customer_id)
    .bind(&p.category)
    .bind(p.team_id)
    .bind(mine)
    .bind(user.user_id)
    .bind(only_unassigned)
    .bind(&tag)
    .bind(p.unread.unwrap_or(false))
    .bind(p.watching.unwrap_or(false))
    .bind(p.escalated.unwrap_or(false))
    .bind(p.limit.unwrap_or(50).clamp(1, 500))
    .bind(p.offset.unwrap_or(0).max(0))
    .fetch_all(&state.db)
    .await?;
    let mut cache = crate::calendar::CalendarCache::default();
    let mut conn = state.db.acquire().await?;
    let mut with_sla = Vec::with_capacity(items.len());
    for t in items {
        let cal = cache.get(&mut conn, user.company_id, t.team_id).await?;
        with_sla.push(t.with_sla(cal));
    }
    drop(conn);
    let mut items: Vec<Ticket> = with_sla;
    let ids: Vec<Uuid> = items.iter().map(|t| t.id).collect();
    let flags = {
        let mut conn = state.db.acquire().await?;
        crate::collab::viewer_flags(&mut conn, user.user_id, &ids).await?
    };
    for t in &mut items {
        if let Some((unread, watching)) = flags.get(&t.id) {
            t.unread = *unread;
            t.watching = *watching;
        }
    }
    let total = sqlx::query_scalar(&format!(
        "SELECT count(*) FROM helpdesk.tickets t LEFT JOIN crm.customers c ON c.id = t.customer_id {filter}"
    ))
    .bind(user.company_id)
    .bind(&pattern)
    .bind(&p.status)
    .bind(owner)
    .bind(unassigned)
    .bind(p.customer_id)
    .bind(&p.category)
    .bind(p.team_id)
    .bind(mine)
    .bind(user.user_id)
    .bind(only_unassigned)
    .bind(&tag)
    .bind(p.unread.unwrap_or(false))
    .bind(p.watching.unwrap_or(false))
    .bind(p.escalated.unwrap_or(false))
    .fetch_one(&state.db)
    .await?;
    Ok(Json(TicketPage { items, total }))
}

#[utoipa::path(get, path = "/tickets/{id}", tag = "helpdesk", params(("id" = Uuid, Path)),
    responses((status = 200, body = TicketDetail), (status = 404, body = ErrorBody)))]
async fn get_ticket(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<TicketDetail>> {
    user.require(Permission::HelpdeskRead)?;
    let mut conn = state.db.acquire().await?;
    let mut d = load_detail(&mut conn, user.company_id, id).await?;
    if let Some((unread, watching)) = crate::collab::viewer_flags(&mut conn, user.user_id, &[id])
        .await?
        .get(&id)
    {
        d.ticket.unread = *unread;
        d.ticket.watching = *watching;
    }
    Ok(Json(d))
}

#[utoipa::path(post, path = "/tickets", tag = "helpdesk", request_body = NewTicketInput,
    responses((status = 201, body = TicketDetail), (status = 422, body = ErrorBody)))]
async fn create_ticket(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<NewTicketInput>,
) -> AppResult<(StatusCode, Json<TicketDetail>)> {
    user.require(Permission::HelpdeskWrite)?;
    if input.subject.trim().is_empty() || input.body.trim().is_empty() {
        return Err(AppError::Validation("subject and text are required".into()));
    }
    check_one_of("category", &input.category, &CATEGORIES)?;
    let mut tx = state.db.begin().await?;
    let contact = match input.contact_id {
        Some(c) => Some(tradocraft_crm::contacts::get_contact(&mut tx, c).await?),
        None => None,
    };
    if let (Some(c), Some(customer)) = (&contact, input.customer_id) {
        if c.customer_id != customer {
            return Err(AppError::Validation(
                "the contact does not work for this customer".into(),
            ));
        }
    }
    let customer_id = contact
        .as_ref()
        .map(|c| c.customer_id)
        .or(input.customer_id);
    let contact_name = match (&contact, input.contact_name.trim()) {
        (Some(c), "") => c.full_name.clone(),
        (_, n) => n.to_string(),
    };
    let contact_email = match (&contact, input.contact_email.trim()) {
        (Some(c), "") => c.primary_email().unwrap_or_default().to_string(),
        (_, e) => e.to_lowercase(),
    };
    let language = match &input.language {
        Some(l) if is_language(l) => l.clone(),
        Some(_) => {
            return Err(AppError::Validation(format!(
                "language must be one of {}",
                LANGUAGES.join(", ")
            )))
        }
        None => match &contact {
            Some(c) => c.effective_language.clone(),
            None => customer_language(&mut tx, customer_id, user.company_id).await?,
        },
    };
    let number = next_ticket_number(&mut tx, user.company_id).await?;
    let id = new_id();
    sqlx::query(
        "INSERT INTO helpdesk.tickets (id, company_id, number, subject, status, category, language, customer_id,
                                       contact_id, contact_name, contact_email, owner_user_id, internal, created_by)
         VALUES ($1, $2, $3, $4, 'open', $5, $6, $7, $8, $9, $10, $11, $12, $11)",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(&number)
    .bind(input.subject.trim())
    .bind(&input.category)
    .bind(&language)
    .bind(customer_id)
    .bind(contact.as_ref().map(|c| c.id))
    .bind(&contact_name)
    .bind(&contact_email)
    .bind(user.user_id)
    .bind(input.internal)
    .execute(&mut *tx)
    .await?;
    add_note(&mut tx, &user, id, &input.body).await?;
    crate::teams::assign_default_team(&mut tx, user.company_id, id).await?;
    crate::collab::record_event(
        &mut tx,
        user.company_id,
        id,
        "created",
        Some(user.user_id),
        Default::default(),
    )
    .await?;
    crate::collab::add_watcher(&mut tx, user.company_id, id, user.user_id).await?;
    sla::sync(&mut tx, id).await?;
    crate::automation::run(&mut tx, user.company_id, id, "created").await?;
    audit::record(
        &mut tx,
        &user,
        "ticket",
        id,
        "created",
        serde_json::json!({ "number": number }),
    )
    .await?;
    let d = load_detail(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(d)))
}

#[utoipa::path(put, path = "/tickets/{id}", tag = "helpdesk", params(("id" = Uuid, Path)), request_body = TicketInput,
    responses((status = 200, body = TicketDetail), (status = 422, body = ErrorBody)))]
async fn update_ticket(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<TicketInput>,
) -> AppResult<Json<TicketDetail>> {
    user.require(Permission::HelpdeskWrite)?;
    check_one_of("status", &input.status, &STATUSES)?;
    check_one_of("priority", &input.priority, &PRIORITIES)?;
    check_one_of("category", &input.category, &CATEGORIES)?;
    check_one_of("language", &input.language, &LANGUAGES)?;
    if input.subject.trim().is_empty() {
        return Err(AppError::Validation("subject is required".into()));
    }
    let mut tx = state.db.begin().await?;
    let old = load_ticket(&mut tx, user.company_id, id).await?;
    let mut input = input;
    if let Some(c) = input.contact_id {
        let contact = tradocraft_crm::contacts::get_contact(&mut tx, c).await?;
        match input.customer_id {
            Some(customer) if customer != contact.customer_id => {
                return Err(AppError::Validation(
                    "the contact does not work for this customer".into(),
                ))
            }
            _ => input.customer_id = Some(contact.customer_id),
        }
    }
    // Links must belong to this company and, when a customer is set, to that customer.
    if let Some(q) = input.quotation_id {
        let ok: bool = sqlx::query_scalar(
            "SELECT EXISTS (SELECT 1 FROM sales.quotations WHERE id = $1 AND company_id = $2
                            AND ($3::uuid IS NULL OR customer_id = $3))",
        )
        .bind(q)
        .bind(user.company_id)
        .bind(input.customer_id)
        .fetch_one(&mut *tx)
        .await?;
        if !ok {
            return Err(AppError::Validation(
                "the quotation does not belong to this customer".into(),
            ));
        }
    }
    if let Some(o) = input.opportunity_id {
        let ok: bool = sqlx::query_scalar(
            "SELECT EXISTS (SELECT 1 FROM crm.opportunities WHERE id = $1 AND company_id = $2
                            AND ($3::uuid IS NULL OR customer_id = $3))",
        )
        .bind(o)
        .bind(user.company_id)
        .bind(input.customer_id)
        .fetch_one(&mut *tx)
        .await?;
        if !ok {
            return Err(AppError::Validation(
                "the opportunity does not belong to this customer".into(),
            ));
        }
    }
    if let Some(owner) = input.owner_user_id {
        let ok: bool = sqlx::query_scalar(
            "SELECT EXISTS (SELECT 1 FROM core.user_companies WHERE user_id = $1 AND company_id = $2)",
        )
        .bind(owner)
        .bind(user.company_id)
        .fetch_one(&mut *tx)
        .await?;
        if !ok {
            return Err(AppError::Validation(
                "the owner is not a member of this company".into(),
            ));
        }
    }
    sqlx::query(
        "UPDATE helpdesk.tickets SET subject = $2, priority = $3, category = $4, language = $5, owner_user_id = $6,
                customer_id = $7, contact_name = $8, contact_email = $9, quotation_id = $10, opportunity_id = $11,
                contact_id = $12, updated_at = now()
         WHERE id = $1",
    )
    .bind(id)
    .bind(input.subject.trim())
    .bind(&input.priority)
    .bind(&input.category)
    .bind(&input.language)
    .bind(input.owner_user_id)
    .bind(input.customer_id)
    .bind(input.contact_name.trim())
    .bind(input.contact_email.trim().to_lowercase())
    .bind(input.quotation_id)
    .bind(input.opportunity_id)
    .bind(input.contact_id)
    .execute(&mut *tx)
    .await?;
    if old.priority != input.priority {
        crate::collab::record_event(
            &mut tx,
            user.company_id,
            id,
            "priority",
            Some(user.user_id),
            crate::collab::EventData {
                from_value: Some(old.priority.clone()),
                to_value: Some(input.priority.clone()),
                ..Default::default()
            },
        )
        .await?;
    }
    crate::collab::owner_changed(&mut tx, &user, id, old.owner_user_id, input.owner_user_id)
        .await?;
    set_status(&mut tx, &user, id, &input.status).await?;
    crate::automation::run(&mut tx, user.company_id, id, "updated").await?;
    audit::record(
        &mut tx,
        &user,
        "ticket",
        id,
        "updated",
        serde_json::json!({ "status": input.status }),
    )
    .await?;
    let d = load_detail(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok(Json(d))
}

/// Adds an internal note: never sent to the customer.
#[utoipa::path(post, path = "/tickets/{id}/notes", tag = "helpdesk", operation_id = "add_note", params(("id" = Uuid, Path)), request_body = NoteInput,
    responses((status = 201, body = TicketDetail)))]
async fn add_note_handler(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<NoteInput>,
) -> AppResult<(StatusCode, Json<TicketDetail>)> {
    user.require(Permission::HelpdeskWrite)?;
    if input.body.trim().is_empty() {
        return Err(AppError::Validation("the note is empty".into()));
    }
    let mut tx = state.db.begin().await?;
    load_ticket(&mut tx, user.company_id, id).await?;
    let note_id = add_note(&mut tx, &user, id, &input.body).await?;
    crate::collab::add_watcher(&mut tx, user.company_id, id, user.user_id).await?;
    crate::attachments::link(&mut tx, id, note_id, &input.attachment_ids, None).await?;
    match &input.status {
        Some(s) => {
            set_status(&mut tx, &user, id, s).await?;
            crate::automation::run(&mut tx, user.company_id, id, "updated").await?;
        }
        None => {
            sqlx::query("UPDATE helpdesk.tickets SET updated_at = now() WHERE id = $1")
                .bind(id)
                .execute(&mut *tx)
                .await?;
        }
    }
    let d = load_detail(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(d)))
}

fn reply_subject(ticket: &Ticket, subject: Option<&str>) -> String {
    let base = subject
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_string)
        .unwrap_or_else(|| {
            let s = ticket.subject.trim();
            if s.to_lowercase().starts_with("re:") {
                s.to_string()
            } else {
                format!("Re: {s}")
            }
        });
    let tag = ticket_tag(&ticket.number);
    if base.contains(&tag) {
        base
    } else {
        format!("{base} {tag}")
    }
}

/// Queues an e-mail to the customer. The worker sends it; delivery status shows on the article.
#[utoipa::path(post, path = "/tickets/{id}/replies", tag = "helpdesk", params(("id" = Uuid, Path)), request_body = ReplyInput,
    responses((status = 201, body = TicketDetail), (status = 403, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn reply(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<ReplyInput>,
) -> AppResult<(StatusCode, Json<TicketDetail>)> {
    user.require(Permission::HelpdeskReply)?;
    if input.body.trim().is_empty() {
        return Err(AppError::Validation("the message is empty".into()));
    }
    let mut tx = state.db.begin().await?;
    let ticket = load_ticket(&mut tx, user.company_id, id).await?;
    let to: Vec<String> = if input.to.is_empty() {
        let fallback: Option<String> = match ticket.customer_id {
            Some(c) => {
                sqlx::query_scalar("SELECT email FROM crm.customers WHERE id = $1")
                    .bind(c)
                    .fetch_one(&mut *tx)
                    .await?
            }
            None => None,
        };
        [Some(ticket.contact_email.clone()), fallback]
            .into_iter()
            .flatten()
            .find(|e| !e.trim().is_empty())
            .into_iter()
            .collect()
    } else {
        input
            .to
            .iter()
            .map(|t| t.trim().to_lowercase())
            .filter(|t| !t.is_empty())
            .collect()
    };
    if to.is_empty() {
        return Err(AppError::Validation(
            "no recipient: enter an e-mail address".into(),
        ));
    }
    if to.iter().chain(&input.cc).any(|a| !a.contains('@')) {
        return Err(AppError::Validation("invalid e-mail address".into()));
    }
    let (company_name, company_email): (String, Option<String>) =
        sqlx::query_as("SELECT name, email FROM core.companies WHERE id = $1")
            .bind(user.company_id)
            .fetch_one(&mut *tx)
            .await?;
    // The reply leaves through the mailbox the ticket came in on, else the default mailbox; a
    // company without mailboxes sends from its own address through the worker's transport.
    let ticket_mailbox: Option<Uuid> =
        sqlx::query_scalar("SELECT mailbox_id FROM helpdesk.tickets WHERE id = $1")
            .bind(id)
            .fetch_one(&mut *tx)
            .await?;
    let sender = crate::mailboxes::sender(&mut tx, user.company_id, ticket_mailbox).await?;
    let from = sender
        .as_ref()
        .map(|s| s.address.clone())
        .or(company_email.filter(|e| e.contains('@')))
        .ok_or_else(|| {
            AppError::Validation("the company has no e-mail address to send from".into())
        })?;
    let domain = from
        .rsplit_once('@')
        .map(|(_, d)| d.to_string())
        .unwrap_or_default();
    let in_reply_to: Option<String> = sqlx::query_scalar(
        "SELECT message_id FROM helpdesk.articles WHERE ticket_id = $1 AND kind = 'email_in' AND message_id IS NOT NULL
         ORDER BY created_at DESC LIMIT 1",
    )
    .bind(id)
    .fetch_optional(&mut *tx)
    .await?;
    let article_id = new_id();
    sqlx::query(
        "INSERT INTO helpdesk.articles (id, ticket_id, kind, from_address, from_name, to_addresses, cc_addresses, subject,
                                        body, language, message_id, in_reply_to, author_user_id, delivery, mailbox_id)
         VALUES ($1, $2, 'email_out', $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, 'queued', $13)",
    )
    .bind(article_id)
    .bind(id)
    .bind(&from)
    .bind(format!("{} | {}", user.display_name, company_name))
    .bind(&to)
    .bind(&input.cc)
    .bind(reply_subject(&ticket, input.subject.as_deref()))
    .bind(&input.body)
    .bind(&ticket.language)
    .bind(format!("{article_id}@{domain}"))
    .bind(in_reply_to)
    .bind(user.user_id)
    .bind(sender.as_ref().map(|s| s.mailbox_id))
    .execute(&mut *tx)
    .await?;
    crate::attachments::link(&mut tx, id, article_id, &input.attachment_ids, None).await?;
    crate::collab::add_watcher(&mut tx, user.company_id, id, user.user_id).await?;
    if ticket.owner_user_id.is_none() {
        crate::collab::record_event(
            &mut tx,
            user.company_id,
            id,
            "assigned",
            Some(user.user_id),
            crate::collab::EventData {
                to_value: Some("owner".into()),
                target_user_id: Some(user.user_id),
                ..Default::default()
            },
        )
        .await?;
    }
    sqlx::query(
        "UPDATE helpdesk.tickets SET first_response_at = coalesce(first_response_at, now()),
                owner_user_id = coalesce(owner_user_id, $2) WHERE id = $1",
    )
    .bind(id)
    .bind(user.user_id)
    .execute(&mut *tx)
    .await?;
    set_status(
        &mut tx,
        &user,
        id,
        input.status.as_deref().unwrap_or("pending_customer"),
    )
    .await?;
    crate::automation::run(&mut tx, user.company_id, id, "updated").await?;
    audit::record(
        &mut tx,
        &user,
        "ticket",
        id,
        "reply_queued",
        serde_json::json!({ "article_id": article_id, "to": to }),
    )
    .await?;
    let d = load_detail(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(d)))
}

/// Turns the ticket into a sales lead: creates an opportunity for its customer and links it.
#[utoipa::path(post, path = "/tickets/{id}/lead", tag = "helpdesk", params(("id" = Uuid, Path)), request_body = LeadInput,
    responses((status = 201, body = TicketDetail), (status = 422, body = ErrorBody)))]
async fn create_lead(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<LeadInput>,
) -> AppResult<(StatusCode, Json<TicketDetail>)> {
    user.require(Permission::HelpdeskWrite)?;
    let mut tx = state.db.begin().await?;
    let ticket = load_ticket(&mut tx, user.company_id, id).await?;
    let customer_id = ticket.customer_id.ok_or_else(|| {
        AppError::Validation("link the ticket to a customer first (or create the customer)".into())
    })?;
    if let Some(n) = &ticket.opportunity_number {
        return Err(AppError::Conflict(format!(
            "the ticket is already linked to opportunity {n}"
        )));
    }
    let opp = tradocraft_crm::opportunities::create(
        &mut tx,
        &user,
        &tradocraft_crm::opportunities::OpportunityInput {
            title: input
                .title
                .filter(|t| !t.trim().is_empty())
                .unwrap_or_else(|| ticket.subject.clone()),
            customer_id,
            owner_user_id: ticket.owner_user_id,
            expected_value: input.expected_value.unwrap_or_default(),
            probability: None,
            expected_close: None,
            notes: format!("From ticket {}", ticket.number),
            power_grid_id: None,
            clear_power_grid: None,
        },
    )
    .await?;
    sqlx::query("UPDATE helpdesk.tickets SET opportunity_id = $2, category = 'lead', updated_at = now() WHERE id = $1")
        .bind(id)
        .bind(opp.id)
        .execute(&mut *tx)
        .await?;
    add_note(
        &mut tx,
        &user,
        id,
        &format!("Lead created: opportunity {}.", opp.number),
    )
    .await?;
    let d = load_detail(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(d)))
}

/// The customer confirmed the linked quotation: convert it into a sales order.
/// If the customer asked for changes, revise the quotation first and link the new revision.
#[utoipa::path(post, path = "/tickets/{id}/convert", tag = "helpdesk", params(("id" = Uuid, Path)),
    request_body = ConvertTicketInput,
    responses((status = 201, body = TicketDetail), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn convert(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<ConvertTicketInput>,
) -> AppResult<(StatusCode, Json<TicketDetail>)> {
    user.require(Permission::HelpdeskWrite)?;
    let mut tx = state.db.begin().await?;
    let ticket = load_ticket(&mut tx, user.company_id, id).await?;
    let quotation_id = ticket.quotation_id.ok_or_else(|| {
        AppError::Validation("link the confirmed quotation to the ticket first".into())
    })?;
    let order_id = tradocraft_sales::orders::convert_quotation(
        &mut tx,
        &user,
        quotation_id,
        &tradocraft_sales::orders::ConvertInput {
            customer_reference: input.customer_reference.clone(),
            notes: input.notes.clone(),
        },
    )
    .await?;
    let order_number: String = sqlx::query_scalar("SELECT number FROM sales.orders WHERE id = $1")
        .bind(order_id)
        .fetch_one(&mut *tx)
        .await?;
    sqlx::query(
        "UPDATE helpdesk.tickets SET order_id = $2, category = 'order_confirmation', updated_at = now() WHERE id = $1",
    )
    .bind(id)
    .bind(order_id)
    .execute(&mut *tx)
    .await?;
    add_note(
        &mut tx,
        &user,
        id,
        &format!(
            "Quotation {} rev. {} converted to order {order_number}{}.",
            ticket.quotation_number.unwrap_or_default(),
            ticket.quotation_revision.unwrap_or_default(),
            if input.customer_reference.trim().is_empty() {
                String::new()
            } else {
                format!(" (customer reference {})", input.customer_reference.trim())
            }
        ),
    )
    .await?;
    let d = load_detail(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(d)))
}

/// Production asks a question about an order. It becomes an internal ticket for the salesperson,
/// in the customer's language, so they can ask the customer and report back in a note.
#[utoipa::path(post, path = "/tickets/production-question", tag = "helpdesk", request_body = ProductionQuestionInput,
    responses((status = 201, body = TicketDetail), (status = 404, body = ErrorBody)))]
async fn production_question(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<ProductionQuestionInput>,
) -> AppResult<(StatusCode, Json<TicketDetail>)> {
    user.require(Permission::HelpdeskWrite)?;
    if input.subject.trim().is_empty() || input.body.trim().is_empty() {
        return Err(AppError::Validation(
            "subject and question are required".into(),
        ));
    }
    let mut tx = state.db.begin().await?;
    #[derive(FromRow)]
    struct O {
        number: String,
        customer_id: Uuid,
        salesperson_id: Uuid,
        quotation_id: Uuid,
        email: Option<String>,
        language: String,
    }
    let o: O = sqlx::query_as(
        "SELECT o.number, o.customer_id, o.salesperson_id, o.quotation_id, c.email, c.language::text AS language
         FROM sales.orders o JOIN crm.customers c ON c.id = o.customer_id
         WHERE o.id = $1 AND o.company_id = $2",
    )
    .bind(input.order_id)
    .bind(user.company_id)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or(AppError::NotFound("order"))?;
    let number = next_ticket_number(&mut tx, user.company_id).await?;
    let id = new_id();
    sqlx::query(
        "INSERT INTO helpdesk.tickets (id, company_id, number, subject, status, priority, category, language, customer_id,
                                       contact_email, owner_user_id, quotation_id, order_id, internal, created_by, channel)
         VALUES ($1, $2, $3, $4, 'open', 'high', 'production_question', $5, $6, $7, $8, $9, $10, true, $11, 'internal')",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(&number)
    .bind(format!("{} – {}", o.number, input.subject.trim()))
    .bind(&o.language)
    .bind(o.customer_id)
    .bind(o.email.unwrap_or_default())
    .bind(o.salesperson_id)
    .bind(o.quotation_id)
    .bind(input.order_id)
    .bind(user.user_id)
    .execute(&mut *tx)
    .await?;
    add_note(&mut tx, &user, id, &input.body).await?;
    crate::collab::record_event(
        &mut tx,
        user.company_id,
        id,
        "created",
        Some(user.user_id),
        Default::default(),
    )
    .await?;
    crate::collab::add_watcher(&mut tx, user.company_id, id, o.salesperson_id).await?;
    crate::collab::add_watcher(&mut tx, user.company_id, id, user.user_id).await?;
    sla::sync(&mut tx, id).await?;
    crate::automation::run(&mut tx, user.company_id, id, "created").await?;
    audit::record(
        &mut tx,
        &user,
        "ticket",
        id,
        "production_question",
        serde_json::json!({ "order": o.number }),
    )
    .await?;
    let d = load_detail(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(d)))
}

fn first_line(text: &str, max: usize) -> String {
    let line = text
        .lines()
        .map(str::trim)
        .find(|l| !l.is_empty())
        .unwrap_or("");
    line.chars().take(max).collect()
}

/// Logs a phone call. The caller is looked up by phone number; the call is added to the given
/// ticket, or a new ticket is opened for it.
#[utoipa::path(post, path = "/helpdesk/calls", tag = "helpdesk", request_body = CallInput,
    responses((status = 201, body = TicketDetail), (status = 404, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn log_call(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<CallInput>,
) -> AppResult<(StatusCode, Json<TicketDetail>)> {
    user.require(Permission::HelpdeskWrite)?;
    check_one_of("direction", &input.direction, &["in", "out"])?;
    check_one_of("category", &input.category, &CATEGORIES)?;
    if input.summary.trim().is_empty() {
        return Err(AppError::Validation(
            "describe what the call was about".into(),
        ));
    }
    if input.duration_seconds.is_some_and(|d| d < 0) {
        return Err(AppError::Validation("duration cannot be negative".into()));
    }
    let kind = if input.direction == "in" {
        "call_in"
    } else {
        "call_out"
    };
    let phone = input.phone_number.trim();
    let mut tx = state.db.begin().await?;
    let country = tradocraft_core::company::get_company(&mut *tx, user.company_id)
        .await?
        .country_code;

    let contact = match input.contact_id {
        Some(c) => Some(tradocraft_crm::contacts::get_contact(&mut tx, c).await?),
        None if !phone.is_empty() => {
            let mut found =
                tradocraft_crm::contacts::find_by_phone(&mut tx, phone, &country).await?;
            // Several people share this number (a switchboard): the agent has to choose.
            if found.len() == 1 {
                found.pop()
            } else {
                None
            }
        }
        None => None,
    };

    let new_ticket = input.ticket_id.is_none();
    let ticket_id = match input.ticket_id {
        Some(t) => {
            let ticket = load_ticket(&mut tx, user.company_id, t).await?;
            if let Some(c) = &contact {
                if ticket.customer_id.is_some_and(|tc| tc != c.customer_id) {
                    return Err(AppError::Validation(
                        "the contact does not work for the customer of this ticket".into(),
                    ));
                }
                // The first call that identifies the person completes the ticket.
                if ticket.contact_id.is_none() {
                    sqlx::query(
                        "UPDATE helpdesk.tickets SET contact_id = $2, customer_id = coalesce(customer_id, $3),
                                contact_name = CASE WHEN contact_name = '' THEN $4 ELSE contact_name END,
                                contact_email = CASE WHEN contact_email = '' THEN $5 ELSE contact_email END
                         WHERE id = $1",
                    )
                    .bind(t)
                    .bind(c.id)
                    .bind(c.customer_id)
                    .bind(&c.full_name)
                    .bind(c.primary_email().unwrap_or_default())
                    .execute(&mut *tx)
                    .await?;
                }
            }
            t
        }
        None => {
            if let (Some(c), Some(customer)) = (&contact, input.customer_id) {
                if c.customer_id != customer {
                    return Err(AppError::Validation(
                        "the contact does not work for this customer".into(),
                    ));
                }
            }
            let customer_id = contact
                .as_ref()
                .map(|c| c.customer_id)
                .or(input.customer_id);
            let language = match &contact {
                Some(c) => c.effective_language.clone(),
                None => customer_language(&mut tx, customer_id, user.company_id).await?,
            };
            let subject = input
                .subject
                .as_deref()
                .map(str::trim)
                .filter(|s| !s.is_empty())
                .map(str::to_string)
                .unwrap_or_else(|| first_line(&input.summary, 80));
            let number = next_ticket_number(&mut tx, user.company_id).await?;
            let id = new_id();
            sqlx::query(
                "INSERT INTO helpdesk.tickets (id, company_id, number, subject, status, category, language, customer_id,
                                               contact_id, contact_name, contact_email, owner_user_id, created_by, channel)
                 VALUES ($1, $2, $3, $4, 'open', $5, $6, $7, $8, $9, $10, $11, $11, 'phone')",
            )
            .bind(id)
            .bind(user.company_id)
            .bind(&number)
            .bind(&subject)
            .bind(&input.category)
            .bind(&language)
            .bind(customer_id)
            .bind(contact.as_ref().map(|c| c.id))
            .bind(contact.as_ref().map(|c| c.full_name.as_str()).unwrap_or_default())
            .bind(contact.as_ref().and_then(|c| c.primary_email()).unwrap_or_default())
            .bind(user.user_id)
            .execute(&mut *tx)
            .await?;
            crate::teams::assign_default_team(&mut tx, user.company_id, id).await?;
            crate::collab::record_event(
                &mut tx,
                user.company_id,
                id,
                "created",
                Some(user.user_id),
                Default::default(),
            )
            .await?;
            crate::collab::add_watcher(&mut tx, user.company_id, id, user.user_id).await?;
            id
        }
    };

    let article_id = new_id();
    sqlx::query(
        "INSERT INTO helpdesk.articles (id, ticket_id, kind, from_name, body, contact_id, phone_number,
                                        duration_seconds, author_user_id)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)",
    )
    .bind(article_id)
    .bind(ticket_id)
    .bind(kind)
    .bind(contact.as_ref().map(|c| c.full_name.as_str()).unwrap_or_default())
    .bind(input.summary.trim())
    .bind(contact.as_ref().map(|c| c.id))
    .bind((!phone.is_empty()).then_some(phone))
    .bind(input.duration_seconds)
    .bind(user.user_id)
    .execute(&mut *tx)
    .await?;
    // An incoming call is a customer reaction: it reopens a ticket that waited for the customer
    // or was closed. Calling the customer back is a response.
    sqlx::query(
        "UPDATE helpdesk.tickets SET updated_at = now(), owner_user_id = coalesce(owner_user_id, $2),
                first_response_at = CASE WHEN $3 THEN coalesce(first_response_at, now()) ELSE first_response_at END,
                status = CASE WHEN $3 AND status = 'new' THEN 'open'
                              WHEN NOT $3 AND status IN ('pending_customer', 'closed') THEN 'open'
                              ELSE status END,
                closed_at = CASE WHEN NOT $3 AND status = 'closed' THEN NULL ELSE closed_at END
         WHERE id = $1",
    )
    .bind(ticket_id)
    .bind(user.user_id)
    .bind(kind == "call_out")
    .execute(&mut *tx)
    .await?;
    sla::sync(&mut tx, ticket_id).await?;
    let trigger = match (new_ticket, kind) {
        (true, _) => "created",
        (false, "call_in") => "customer_replied",
        _ => "updated",
    };
    crate::automation::run(&mut tx, user.company_id, ticket_id, trigger).await?;
    audit::record(
        &mut tx,
        &user,
        "ticket",
        ticket_id,
        "call_logged",
        serde_json::json!({ "direction": input.direction, "article_id": article_id }),
    )
    .await?;
    let d = load_detail(&mut tx, user.company_id, ticket_id).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(d)))
}

/// Imports a raw e-mail (RFC 5322, e.g. a saved .eml file) as if it had arrived in the mailbox.
#[utoipa::path(post, path = "/helpdesk/inbound", tag = "helpdesk",
    request_body(content = String, content_type = "message/rfc822"),
    responses((status = 200, body = InboundResult), (status = 422, body = ErrorBody)))]
async fn inbound(
    State(state): State<AppState>,
    user: CurrentUser,
    body: Bytes,
) -> AppResult<Json<InboundResult>> {
    user.require(Permission::HelpdeskWrite)?;
    let r = crate::ingest::ingest(&state.db, user.company_id, &body)
        .await
        .map_err(|e| AppError::Validation(e.to_string()))?;
    Ok(Json(InboundResult {
        ticket_id: r.ticket_id,
        ticket_number: r.ticket_number,
        new_ticket: r.new_ticket,
        duplicate: r.duplicate,
    }))
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(list_tickets, create_ticket))
        .routes(routes!(get_ticket, update_ticket))
        .routes(routes!(add_note_handler))
        .routes(routes!(reply))
        .routes(routes!(create_lead))
        .routes(routes!(convert))
        .routes(routes!(production_question))
        .routes(routes!(log_call))
        .routes(routes!(inbound))
        .merge(crate::teams::router())
        .merge(crate::mailboxes::router())
        .merge(crate::sla::router())
        .merge(crate::attachments::router())
        .merge(crate::extras::router())
        .merge(crate::csat::router())
        .merge(crate::collab::router())
}
