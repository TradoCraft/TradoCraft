//! The audit trail viewer (ADR 0059, roadmap D6).
//!
//! `audit.events` is written in the transaction of every business change (`audit::record`). These
//! endpoints read it back for administrators (`audit.view`): the history of one record, and the
//! company-wide trail with filters. Always scoped to the active company: events without a company
//! (there are none today) are not shown to anyone.
//!
//! Paging is by cursor (`before_id`, newest first), not by offset and total: the table grows with
//! every transaction and a count over it would get slower every month.

use axum::extract::{Path, Query, State};
use axum::Json;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgPool};
use utoipa::{IntoParams, ToSchema};
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::{AppResult, AppState, CurrentUser, Permission};

type ErrorBody = crate::error::ErrorBody;

const DEFAULT_LIMIT: i64 = 50;
const MAX_LIMIT: i64 = 200;

/// One audited event: who did what to which record, and when.
#[derive(Debug, Serialize, FromRow, ToSchema)]
pub struct AuditEvent {
    /// Increases with time; the cursor for the next page.
    pub id: i64,
    pub occurred_at: DateTime<Utc>,
    /// Absent for an event without a staff user, such as a customer acting in the portal; who
    /// acted is then in `data`.
    pub user_id: Option<Uuid>,
    pub user_name: Option<String>,
    pub user_email: Option<String>,
    /// The kind of record (`customer`, `quotation`, `supplier_invoice`, ...).
    pub entity: String,
    pub entity_id: Uuid,
    /// What happened (`created`, `updated`, `sent`, ...); the modules name their own.
    pub action: String,
    /// What the module recorded: for an update usually `{"changes": {"field": {"from", "to"}}}`,
    /// but each module decides, and some record nothing but the action.
    #[schema(value_type = Object)]
    pub data: serde_json::Value,
}

/// A page of events, newest first.
#[derive(Debug, Serialize, ToSchema)]
pub struct AuditPage {
    pub items: Vec<AuditEvent>,
    /// Pass as `before_id` for the next (older) page; absent on the last page.
    pub next_before_id: Option<i64>,
}

/// Filters of the company-wide trail. All optional; all must hold together.
#[derive(Debug, Default, Deserialize, IntoParams)]
pub struct AuditQuery {
    /// The kind of record.
    pub entity: Option<String>,
    /// One record.
    pub entity_id: Option<Uuid>,
    /// Exactly this action.
    pub action: Option<String>,
    /// Events by this user.
    pub user_id: Option<Uuid>,
    /// From this moment on (inclusive).
    pub from: Option<DateTime<Utc>>,
    /// Until this moment (exclusive).
    pub to: Option<DateTime<Utc>>,
    /// Only events older than this id: the `next_before_id` of the previous page.
    pub before_id: Option<i64>,
    /// Page size, 50 by default, at most 200.
    pub limit: Option<i64>,
}

/// Paging of one record's history.
#[derive(Debug, Default, Deserialize, IntoParams)]
pub struct HistoryQuery {
    pub before_id: Option<i64>,
    /// Page size, 50 by default, at most 200.
    pub limit: Option<i64>,
}

/// What the filters of the viewer can offer.
#[derive(Debug, Serialize, ToSchema)]
pub struct AuditFacets {
    /// The kinds of record that have events in this company, alphabetically.
    pub entities: Vec<String>,
}

async fn fetch(db: &PgPool, company_id: Uuid, q: &AuditQuery) -> AppResult<AuditPage> {
    let limit = q.limit.unwrap_or(DEFAULT_LIMIT).clamp(1, MAX_LIMIT);
    // One more than asked, to know whether there is another page.
    let mut items: Vec<AuditEvent> = sqlx::query_as(
        "SELECT e.id, e.occurred_at, e.user_id, u.display_name AS user_name, u.email AS user_email,
                e.entity, e.entity_id, e.action, e.data
         FROM audit.events e
         LEFT JOIN core.users u ON u.id = e.user_id
         WHERE e.company_id = $1
           AND ($2::text IS NULL OR e.entity = $2)
           AND ($3::uuid IS NULL OR e.entity_id = $3)
           AND ($4::text IS NULL OR e.action = $4)
           AND ($5::uuid IS NULL OR e.user_id = $5)
           AND ($6::timestamptz IS NULL OR e.occurred_at >= $6)
           AND ($7::timestamptz IS NULL OR e.occurred_at < $7)
           AND ($8::bigint IS NULL OR e.id < $8)
         ORDER BY e.id DESC
         LIMIT $9",
    )
    .bind(company_id)
    .bind(q.entity.as_deref().map(str::trim).filter(|s| !s.is_empty()))
    .bind(q.entity_id)
    .bind(q.action.as_deref().map(str::trim).filter(|s| !s.is_empty()))
    .bind(q.user_id)
    .bind(q.from)
    .bind(q.to)
    .bind(q.before_id)
    .bind(limit + 1)
    .fetch_all(db)
    .await?;
    let next_before_id = if items.len() as i64 > limit {
        items.truncate(limit as usize);
        items.last().map(|e| e.id)
    } else {
        None
    };
    Ok(AuditPage {
        items,
        next_before_id,
    })
}

/// The company-wide audit trail, newest first, with filters.
#[utoipa::path(
    get,
    path = "/audit/events",
    tag = "audit",
    operation_id = "list_audit_events",
    params(AuditQuery),
    responses(
        (status = 200, body = AuditPage),
        (status = 401, body = ErrorBody),
        (status = 403, body = ErrorBody)
    )
)]
async fn list_events(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(q): Query<AuditQuery>,
) -> AppResult<Json<AuditPage>> {
    user.require(Permission::AuditView)?;
    Ok(Json(fetch(&state.db, user.company_id, &q).await?))
}

/// The history of one record, newest first.
#[utoipa::path(
    get,
    path = "/audit/records/{entity}/{id}",
    tag = "audit",
    operation_id = "get_record_history",
    params(
        ("entity" = String, Path, description = "The kind of record, e.g. `customer`"),
        ("id" = Uuid, Path, description = "The record"),
        HistoryQuery
    ),
    responses(
        (status = 200, body = AuditPage),
        (status = 401, body = ErrorBody),
        (status = 403, body = ErrorBody)
    )
)]
async fn record_history(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((entity, id)): Path<(String, Uuid)>,
    Query(h): Query<HistoryQuery>,
) -> AppResult<Json<AuditPage>> {
    user.require(Permission::AuditView)?;
    let q = AuditQuery {
        entity: Some(entity),
        entity_id: Some(id),
        before_id: h.before_id,
        limit: h.limit,
        ..AuditQuery::default()
    };
    Ok(Json(fetch(&state.db, user.company_id, &q).await?))
}

/// The kinds of record the trail has events for, to fill the filter of the viewer.
#[utoipa::path(
    get,
    path = "/audit/facets",
    tag = "audit",
    operation_id = "get_audit_facets",
    responses(
        (status = 200, body = AuditFacets),
        (status = 401, body = ErrorBody),
        (status = 403, body = ErrorBody)
    )
)]
async fn facets(State(state): State<AppState>, user: CurrentUser) -> AppResult<Json<AuditFacets>> {
    user.require(Permission::AuditView)?;
    // A loose index scan: jump from one entity to the next in the (company, entity) index instead
    // of reading every event.
    let entities: Vec<String> = sqlx::query_scalar(
        "WITH RECURSIVE e(entity) AS (
             (SELECT entity FROM audit.events WHERE company_id = $1 ORDER BY entity LIMIT 1)
             UNION ALL
             SELECT (SELECT entity FROM audit.events WHERE company_id = $1 AND entity > e.entity
                     ORDER BY entity LIMIT 1)
             FROM e WHERE e.entity IS NOT NULL
         )
         SELECT entity FROM e WHERE entity IS NOT NULL",
    )
    .bind(user.company_id)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(AuditFacets { entities }))
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(list_events))
        .routes(routes!(record_history))
        .routes(routes!(facets))
}
