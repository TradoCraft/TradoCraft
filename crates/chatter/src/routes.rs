//! HTTP endpoints of the chatter (ADR 0086).
//!
//! Every endpoint about a record first checks that the record exists in the caller's company and
//! that the caller holds the kind's read permission; writing needs the kind's write permission,
//! except following oneself. Anything else answers 404 so ids reveal nothing.

use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::Json;
use chrono::{DateTime, NaiveDate, Utc};
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection};
use tradocraft_core::{new_id, AppError, AppResult, AppState, CurrentUser};
use utoipa::{IntoParams, ToSchema};
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::kind::parse_kind;
use crate::RecordKind;

type ErrorBody = tradocraft_core::error::ErrorBody;

pub const MAX_NOTE: usize = 10_000;
pub const MAX_SUMMARY: usize = 200;
pub const MAX_ACTIVITY_NOTE: usize = 4_000;
/// How long the author may still edit or delete a note.
const EDIT_WINDOW_MINUTES: i64 = 15;
const DEFAULT_LIMIT: i64 = 30;
const MAX_LIMIT: i64 = 100;

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(thread))
        .routes(routes!(post_note))
        .routes(routes!(edit_note, delete_note))
        .routes(routes!(list_activities, create_activity))
        .routes(routes!(complete_activity))
        .routes(routes!(delete_activity))
        .routes(routes!(list_followers, add_follower))
        .routes(routes!(follow, unfollow))
        .routes(routes!(remove_follower))
        .routes(routes!(mark_read))
        .routes(routes!(inbox))
}

// ---------------------------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------------------------

/// One entry of the thread: a note or a change message.
#[derive(Debug, Serialize, FromRow, ToSchema)]
pub struct ThreadItem {
    /// Increases with time; the cursor for the next (older) page.
    pub id: Uuid,
    /// `note` | `system`
    pub kind: String,
    pub author_id: Option<Uuid>,
    pub author_name: Option<String>,
    pub body: String,
    /// The tracked fields of a change message: `[{"field", "from", "to"}]`.
    #[schema(value_type = Object)]
    pub changes: serde_json::Value,
    pub created_at: DateTime<Utc>,
    pub edited_at: Option<DateTime<Utc>>,
    /// Whether the caller may still edit or delete it (own note, within 15 minutes).
    #[sqlx(default)]
    pub editable: bool,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct ThreadPage {
    pub items: Vec<ThreadItem>,
    /// Pass as `before_id` for the next (older) page; absent on the last page.
    pub next_before_id: Option<Uuid>,
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct ThreadQuery {
    pub before_id: Option<Uuid>,
    pub limit: Option<i64>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct NoteInput {
    pub body: String,
    /// Chosen by the client so that a retried post does not post twice.
    pub client_id: Option<Uuid>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum ActivityKind {
    Todo,
    Call,
    Email,
    Meeting,
}

impl ActivityKind {
    fn as_str(self) -> &'static str {
        match self {
            ActivityKind::Todo => "todo",
            ActivityKind::Call => "call",
            ActivityKind::Email => "email",
            ActivityKind::Meeting => "meeting",
        }
    }
}

#[derive(Debug, Serialize, FromRow, ToSchema)]
pub struct Activity {
    pub id: Uuid,
    pub kind: String,
    pub summary: String,
    pub note: String,
    pub assignee_id: Uuid,
    pub assignee_name: String,
    pub due_date: NaiveDate,
    pub created_by: Uuid,
    pub created_at: DateTime<Utc>,
    /// Whether the due date is before today.
    pub overdue: bool,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct ActivityInput {
    pub kind: ActivityKind,
    pub summary: String,
    #[serde(default)]
    pub note: String,
    pub assignee_id: Uuid,
    pub due_date: NaiveDate,
    pub client_id: Option<Uuid>,
}

#[derive(Debug, Default, Deserialize, ToSchema)]
pub struct DoneInput {
    #[serde(default)]
    pub note: String,
}

#[derive(Debug, Serialize, FromRow, ToSchema)]
pub struct Follower {
    pub user_id: Uuid,
    pub user_name: String,
    /// `manual` | `author` | `assigned`
    pub reason: String,
    pub followed_at: DateTime<Utc>,
}

/// The followers of a record and whether the caller is one of them.
#[derive(Debug, Serialize, ToSchema)]
pub struct Followers {
    pub items: Vec<Follower>,
    pub following: bool,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct FollowerInput {
    pub user_id: Uuid,
}

#[derive(Debug, Serialize, FromRow, ToSchema)]
pub struct InboxRecord {
    pub record_kind: String,
    pub record_id: Uuid,
    pub label: Option<String>,
    /// Messages by others since the caller last read the record.
    pub unread: i64,
    pub last_at: DateTime<Utc>,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct InboxActivity {
    pub id: Uuid,
    pub record_kind: String,
    pub record_id: Uuid,
    pub label: Option<String>,
    pub kind: String,
    pub summary: String,
    pub due_date: NaiveDate,
    pub overdue: bool,
}

/// What needs the caller's attention across records, for the notifications centre.
#[derive(Debug, Serialize, ToSchema)]
pub struct Inbox {
    pub unread: Vec<InboxRecord>,
    /// Open activities assigned to the caller that are due today or earlier.
    pub activities: Vec<InboxActivity>,
}

// ---------------------------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------------------------

async fn open(
    conn: &mut PgConnection,
    user: &CurrentUser,
    kind: &str,
    id: Uuid,
    write: bool,
) -> AppResult<RecordKind> {
    let kind = parse_kind(kind)?;
    user.require(kind.read_permission())?;
    if write {
        user.require(kind.write_permission())?;
    }
    kind.ensure_visible(conn, user, id).await?;
    Ok(kind)
}

async fn check_member(conn: &mut PgConnection, user: &CurrentUser, id: Uuid) -> AppResult<()> {
    let member: Option<i32> = sqlx::query_scalar(
        "SELECT 1 FROM core.user_companies WHERE user_id = $1 AND company_id = $2 AND active",
    )
    .bind(id)
    .bind(user.company_id)
    .fetch_optional(&mut *conn)
    .await?;
    member.map(|_| ()).ok_or_else(|| {
        AppError::Validation("that user is not an active colleague of this company".into())
    })
}

/// Starts (or resumes) following; `reason` is kept when the user already follows.
async fn follow_record(
    conn: &mut PgConnection,
    company_id: Uuid,
    kind: RecordKind,
    record_id: Uuid,
    user_id: Uuid,
    reason: &str,
) -> AppResult<()> {
    sqlx::query(
        "INSERT INTO chatter.followers (company_id, record_kind, record_id, user_id, reason)
         VALUES ($1, $2, $3, $4, $5)
         ON CONFLICT (company_id, record_kind, record_id, user_id)
         DO UPDATE SET muted_at = NULL",
    )
    .bind(company_id)
    .bind(kind.as_str())
    .bind(record_id)
    .bind(user_id)
    .bind(reason)
    .execute(&mut *conn)
    .await?;
    Ok(())
}

fn publish(state: &AppState, user: &CurrentUser, kind: RecordKind, id: Uuid, what: &str) {
    // The record version does not move for a note: an open form must not become stale.
    state
        .live_events
        .publish_record_change(user, kind.as_str(), id, 0, what, None);
}

const THREAD_SELECT: &str = "SELECT m.id, m.kind, m.author_user_id AS author_id,
        u.display_name AS author_name, m.body, m.changes, m.created_at, m.edited_at,
        (m.kind = 'note' AND m.author_user_id = $1 AND m.created_at > now() - $2::interval) AS editable
    FROM chatter.messages m LEFT JOIN core.users u ON u.id = m.author_user_id";

fn window() -> String {
    format!("{} minutes", EDIT_WINDOW_MINUTES)
}

// ---------------------------------------------------------------------------------------------
// Thread
// ---------------------------------------------------------------------------------------------

#[utoipa::path(get, path = "/chatter/{kind}/{id}/thread", tag = "chatter", operation_id = "chatter_thread",
    params(("kind" = String, Path), ("id" = Uuid, Path), ThreadQuery),
    responses((status = 200, body = ThreadPage), (status = 403, body = ErrorBody),
              (status = 404, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn thread(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((kind, id)): Path<(String, Uuid)>,
    Query(q): Query<ThreadQuery>,
) -> AppResult<Json<ThreadPage>> {
    let mut conn = state.db.acquire().await?;
    let kind = open(&mut conn, &user, &kind, id, false).await?;
    let limit = q.limit.unwrap_or(DEFAULT_LIMIT).clamp(1, MAX_LIMIT);
    let mut items: Vec<ThreadItem> = sqlx::query_as(&format!(
        "{THREAD_SELECT}
         WHERE m.company_id = $3 AND m.record_kind = $4 AND m.record_id = $5
           AND ($6::uuid IS NULL OR m.id < $6)
         ORDER BY m.id DESC LIMIT $7"
    ))
    .bind(user.user_id)
    .bind(window())
    .bind(user.company_id)
    .bind(kind.as_str())
    .bind(id)
    .bind(q.before_id)
    .bind(limit + 1)
    .fetch_all(&mut *conn)
    .await?;
    let next_before_id = if items.len() as i64 > limit {
        items.truncate(limit as usize);
        items.last().map(|i| i.id)
    } else {
        None
    };
    Ok(Json(ThreadPage {
        items,
        next_before_id,
    }))
}

async fn load_item(conn: &mut PgConnection, user: &CurrentUser, id: Uuid) -> AppResult<ThreadItem> {
    sqlx::query_as(&format!(
        "{THREAD_SELECT} WHERE m.id = $3 AND m.company_id = $4"
    ))
    .bind(user.user_id)
    .bind(window())
    .bind(id)
    .bind(user.company_id)
    .fetch_optional(&mut *conn)
    .await?
    .ok_or(AppError::NotFound("note"))
}

fn clean_body(body: &str) -> AppResult<String> {
    let body = body.trim();
    if body.is_empty() || body.chars().count() > MAX_NOTE {
        return Err(AppError::Validation(format!(
            "a note must be 1 to {MAX_NOTE} characters"
        )));
    }
    Ok(body.to_string())
}

#[utoipa::path(post, path = "/chatter/{kind}/{id}/notes", tag = "chatter", operation_id = "chatter_post_note",
    params(("kind" = String, Path), ("id" = Uuid, Path)), request_body = NoteInput,
    responses((status = 201, body = ThreadItem), (status = 200, body = ThreadItem),
              (status = 403, body = ErrorBody), (status = 404, body = ErrorBody),
              (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn post_note(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((kind, id)): Path<(String, Uuid)>,
    Json(input): Json<NoteInput>,
) -> AppResult<(StatusCode, Json<ThreadItem>)> {
    let body = clean_body(&input.body)?;
    let mut tx = state.db.begin().await?;
    let kind = open(&mut tx, &user, &kind, id, true).await?;
    if let Some(client_id) = input.client_id {
        // A retried post returns the note that exists (200); the id belongs to the company.
        let existing: Option<(Uuid, String, Uuid, Option<Uuid>)> = sqlx::query_as(
            "SELECT id, record_kind, record_id, author_user_id FROM chatter.messages
             WHERE company_id = $1 AND client_id = $2",
        )
        .bind(user.company_id)
        .bind(client_id)
        .fetch_optional(&mut *tx)
        .await?;
        if let Some((mid, k, rid, author)) = existing {
            if k != kind.as_str() || rid != id || author != Some(user.user_id) {
                return Err(AppError::Conflict("client_id is already used".into()));
            }
            let item = load_item(&mut tx, &user, mid).await?;
            return Ok((StatusCode::OK, Json(item)));
        }
    }
    let mid = new_id();
    sqlx::query(
        "INSERT INTO chatter.messages
             (id, company_id, record_kind, record_id, kind, author_user_id, body, client_id)
         VALUES ($1, $2, $3, $4, 'note', $5, $6, $7)",
    )
    .bind(mid)
    .bind(user.company_id)
    .bind(kind.as_str())
    .bind(id)
    .bind(user.user_id)
    .bind(&body)
    .bind(input.client_id)
    .execute(&mut *tx)
    .await?;
    follow_record(&mut tx, user.company_id, kind, id, user.user_id, "author").await?;
    // Writing a note means the author has seen the thread up to now.
    sqlx::query(
        "UPDATE chatter.followers SET last_read_at = now()
         WHERE company_id = $1 AND record_kind = $2 AND record_id = $3 AND user_id = $4",
    )
    .bind(user.company_id)
    .bind(kind.as_str())
    .bind(id)
    .bind(user.user_id)
    .execute(&mut *tx)
    .await?;
    let item = load_item(&mut tx, &user, mid).await?;
    tx.commit().await?;
    publish(&state, &user, kind, id, "chatter_note");
    Ok((StatusCode::CREATED, Json(item)))
}

/// Locks an own, still editable note and returns its address.
async fn lock_own_note(
    conn: &mut PgConnection,
    user: &CurrentUser,
    id: Uuid,
) -> AppResult<(RecordKind, Uuid)> {
    let row: Option<(String, Uuid, Option<Uuid>, String, bool)> = sqlx::query_as(
        "SELECT record_kind, record_id, author_user_id, kind, created_at > now() - $3::interval
         FROM chatter.messages WHERE id = $1 AND company_id = $2 FOR UPDATE",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(window())
    .fetch_optional(&mut *conn)
    .await?;
    let (kind, record_id, author, mkind, in_window) = row.ok_or(AppError::NotFound("note"))?;
    let kind = parse_kind(&kind)?;
    // Same visibility rule as the thread: no read permission, no note.
    open(conn, user, kind.as_str(), record_id, true).await?;
    if mkind != "note" || author != Some(user.user_id) {
        return Err(AppError::Forbidden(
            "only the author can change a note".into(),
        ));
    }
    if !in_window {
        return Err(AppError::Forbidden(format!(
            "a note can only be changed for {EDIT_WINDOW_MINUTES} minutes"
        )));
    }
    Ok((kind, record_id))
}

#[utoipa::path(patch, path = "/chatter/notes/{id}", tag = "chatter", operation_id = "chatter_edit_note",
    params(("id" = Uuid, Path)), request_body = NoteInput,
    responses((status = 200, body = ThreadItem), (status = 403, body = ErrorBody),
              (status = 404, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn edit_note(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<NoteInput>,
) -> AppResult<Json<ThreadItem>> {
    let body = clean_body(&input.body)?;
    let mut tx = state.db.begin().await?;
    let (kind, record_id) = lock_own_note(&mut tx, &user, id).await?;
    sqlx::query("UPDATE chatter.messages SET body = $2, edited_at = now() WHERE id = $1")
        .bind(id)
        .bind(&body)
        .execute(&mut *tx)
        .await?;
    let item = load_item(&mut tx, &user, id).await?;
    tx.commit().await?;
    publish(&state, &user, kind, record_id, "chatter_note");
    Ok(Json(item))
}

#[utoipa::path(delete, path = "/chatter/notes/{id}", tag = "chatter", operation_id = "chatter_delete_note",
    params(("id" = Uuid, Path)),
    responses((status = 204), (status = 403, body = ErrorBody), (status = 404, body = ErrorBody)))]
async fn delete_note(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<StatusCode> {
    let mut tx = state.db.begin().await?;
    let (kind, record_id) = lock_own_note(&mut tx, &user, id).await?;
    sqlx::query("DELETE FROM chatter.messages WHERE id = $1")
        .bind(id)
        .execute(&mut *tx)
        .await?;
    tx.commit().await?;
    publish(&state, &user, kind, record_id, "chatter_note");
    Ok(StatusCode::NO_CONTENT)
}

// ---------------------------------------------------------------------------------------------
// Activities
// ---------------------------------------------------------------------------------------------

const ACTIVITY_SELECT: &str = "SELECT a.id, a.kind, a.summary, a.note, a.assignee_id,
        u.display_name AS assignee_name, a.due_date, a.created_by, a.created_at,
        a.due_date < current_date AS overdue
    FROM chatter.activities a JOIN core.users u ON u.id = a.assignee_id";

#[utoipa::path(get, path = "/chatter/{kind}/{id}/activities", tag = "chatter", operation_id = "chatter_activities",
    params(("kind" = String, Path), ("id" = Uuid, Path)),
    responses((status = 200, body = Vec<Activity>), (status = 403, body = ErrorBody),
              (status = 404, body = ErrorBody)))]
async fn list_activities(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((kind, id)): Path<(String, Uuid)>,
) -> AppResult<Json<Vec<Activity>>> {
    let mut conn = state.db.acquire().await?;
    let kind = open(&mut conn, &user, &kind, id, false).await?;
    let rows = sqlx::query_as(&format!(
        "{ACTIVITY_SELECT}
         WHERE a.company_id = $1 AND a.record_kind = $2 AND a.record_id = $3 AND a.done_at IS NULL
         ORDER BY a.due_date, a.id"
    ))
    .bind(user.company_id)
    .bind(kind.as_str())
    .bind(id)
    .fetch_all(&mut *conn)
    .await?;
    Ok(Json(rows))
}

#[utoipa::path(post, path = "/chatter/{kind}/{id}/activities", tag = "chatter", operation_id = "chatter_create_activity",
    params(("kind" = String, Path), ("id" = Uuid, Path)), request_body = ActivityInput,
    responses((status = 201, body = Activity), (status = 200, body = Activity),
              (status = 403, body = ErrorBody), (status = 404, body = ErrorBody),
              (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn create_activity(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((kind, id)): Path<(String, Uuid)>,
    Json(input): Json<ActivityInput>,
) -> AppResult<(StatusCode, Json<Activity>)> {
    let summary = input.summary.trim().to_string();
    if summary.is_empty() || summary.chars().count() > MAX_SUMMARY {
        return Err(AppError::Validation(format!(
            "the summary must be 1 to {MAX_SUMMARY} characters"
        )));
    }
    if input.note.chars().count() > MAX_ACTIVITY_NOTE {
        return Err(AppError::Validation(format!(
            "the note is limited to {MAX_ACTIVITY_NOTE} characters"
        )));
    }
    let mut tx = state.db.begin().await?;
    let kind = open(&mut tx, &user, &kind, id, true).await?;
    check_member(&mut tx, &user, input.assignee_id).await?;
    if let Some(client_id) = input.client_id {
        let existing: Option<(Uuid, String, Uuid)> = sqlx::query_as(
            "SELECT id, record_kind, record_id FROM chatter.activities
             WHERE company_id = $1 AND client_id = $2",
        )
        .bind(user.company_id)
        .bind(client_id)
        .fetch_optional(&mut *tx)
        .await?;
        if let Some((aid, k, rid)) = existing {
            if k != kind.as_str() || rid != id {
                return Err(AppError::Conflict("client_id is already used".into()));
            }
            let a = load_activity(&mut tx, &user, aid).await?;
            return Ok((StatusCode::OK, Json(a)));
        }
    }
    let aid = new_id();
    sqlx::query(
        "INSERT INTO chatter.activities
             (id, company_id, record_kind, record_id, kind, summary, note, assignee_id, due_date,
              created_by, client_id)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)",
    )
    .bind(aid)
    .bind(user.company_id)
    .bind(kind.as_str())
    .bind(id)
    .bind(input.kind.as_str())
    .bind(&summary)
    .bind(&input.note)
    .bind(input.assignee_id)
    .bind(input.due_date)
    .bind(user.user_id)
    .bind(input.client_id)
    .execute(&mut *tx)
    .await?;
    follow_record(
        &mut tx,
        user.company_id,
        kind,
        id,
        input.assignee_id,
        "assigned",
    )
    .await?;
    let a = load_activity(&mut tx, &user, aid).await?;
    tx.commit().await?;
    publish(&state, &user, kind, id, "chatter_activity");
    Ok((StatusCode::CREATED, Json(a)))
}

async fn load_activity(
    conn: &mut PgConnection,
    user: &CurrentUser,
    id: Uuid,
) -> AppResult<Activity> {
    sqlx::query_as(&format!(
        "{ACTIVITY_SELECT} WHERE a.id = $1 AND a.company_id = $2"
    ))
    .bind(id)
    .bind(user.company_id)
    .fetch_optional(&mut *conn)
    .await?
    .ok_or(AppError::NotFound("activity"))
}

/// Locks an open activity of the company and checks the record permission.
async fn lock_activity(
    conn: &mut PgConnection,
    user: &CurrentUser,
    id: Uuid,
) -> AppResult<(RecordKind, Uuid, String, String, Uuid, Uuid)> {
    let row: Option<(String, Uuid, String, String, Uuid, Uuid)> = sqlx::query_as(
        "SELECT record_kind, record_id, kind, summary, assignee_id, created_by
         FROM chatter.activities WHERE id = $1 AND company_id = $2 AND done_at IS NULL
         FOR UPDATE",
    )
    .bind(id)
    .bind(user.company_id)
    .fetch_optional(&mut *conn)
    .await?;
    let (k, rid, kind, summary, assignee, creator) = row.ok_or(AppError::NotFound("activity"))?;
    let k = parse_kind(&k)?;
    open(conn, user, k.as_str(), rid, true).await?;
    Ok((k, rid, kind, summary, assignee, creator))
}

#[utoipa::path(post, path = "/chatter/activities/{id}/done", tag = "chatter", operation_id = "chatter_complete_activity",
    params(("id" = Uuid, Path)), request_body = DoneInput,
    responses((status = 204), (status = 403, body = ErrorBody), (status = 404, body = ErrorBody),
              (status = 422, body = ErrorBody)))]
async fn complete_activity(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<DoneInput>,
) -> AppResult<StatusCode> {
    if input.note.chars().count() > MAX_ACTIVITY_NOTE {
        return Err(AppError::Validation(format!(
            "the note is limited to {MAX_ACTIVITY_NOTE} characters"
        )));
    }
    let mut tx = state.db.begin().await?;
    let (kind, record_id, akind, summary, _, _) = lock_activity(&mut tx, &user, id).await?;
    sqlx::query(
        "UPDATE chatter.activities SET done_at = now(), done_by = $2, done_note = $3 WHERE id = $1",
    )
    .bind(id)
    .bind(user.user_id)
    .bind(input.note.trim())
    .execute(&mut *tx)
    .await?;
    // The completed activity stays in the thread as a change message.
    sqlx::query(
        "INSERT INTO chatter.messages
             (id, company_id, record_kind, record_id, kind, author_user_id, body, changes)
         VALUES ($1, $2, $3, $4, 'system', $5, $6, $7)",
    )
    .bind(new_id())
    .bind(user.company_id)
    .bind(kind.as_str())
    .bind(record_id)
    .bind(user.user_id)
    .bind(input.note.trim())
    .bind(serde_json::json!([{ "field": "activity_done", "from": akind, "to": summary }]))
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;
    publish(&state, &user, kind, record_id, "chatter_activity");
    Ok(StatusCode::NO_CONTENT)
}

#[utoipa::path(delete, path = "/chatter/activities/{id}", tag = "chatter", operation_id = "chatter_delete_activity",
    params(("id" = Uuid, Path)),
    responses((status = 204), (status = 403, body = ErrorBody), (status = 404, body = ErrorBody)))]
async fn delete_activity(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<StatusCode> {
    let mut tx = state.db.begin().await?;
    let (kind, record_id, _, _, assignee, creator) = lock_activity(&mut tx, &user, id).await?;
    if user.user_id != assignee && user.user_id != creator {
        return Err(AppError::Forbidden(
            "only the creator or the assignee can delete an activity".into(),
        ));
    }
    sqlx::query("DELETE FROM chatter.activities WHERE id = $1")
        .bind(id)
        .execute(&mut *tx)
        .await?;
    tx.commit().await?;
    publish(&state, &user, kind, record_id, "chatter_activity");
    Ok(StatusCode::NO_CONTENT)
}

// ---------------------------------------------------------------------------------------------
// Followers and read state
// ---------------------------------------------------------------------------------------------

async fn followers_of(
    conn: &mut PgConnection,
    user: &CurrentUser,
    kind: RecordKind,
    id: Uuid,
) -> AppResult<Followers> {
    let items: Vec<Follower> = sqlx::query_as(
        "SELECT f.user_id, u.display_name AS user_name, f.reason, f.followed_at
         FROM chatter.followers f JOIN core.users u ON u.id = f.user_id
         WHERE f.company_id = $1 AND f.record_kind = $2 AND f.record_id = $3
           AND f.muted_at IS NULL
         ORDER BY u.display_name, f.user_id",
    )
    .bind(user.company_id)
    .bind(kind.as_str())
    .bind(id)
    .fetch_all(&mut *conn)
    .await?;
    let following = items.iter().any(|f| f.user_id == user.user_id);
    Ok(Followers { items, following })
}

#[utoipa::path(get, path = "/chatter/{kind}/{id}/followers", tag = "chatter", operation_id = "chatter_followers",
    params(("kind" = String, Path), ("id" = Uuid, Path)),
    responses((status = 200, body = Followers), (status = 403, body = ErrorBody),
              (status = 404, body = ErrorBody)))]
async fn list_followers(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((kind, id)): Path<(String, Uuid)>,
) -> AppResult<Json<Followers>> {
    let mut conn = state.db.acquire().await?;
    let kind = open(&mut conn, &user, &kind, id, false).await?;
    Ok(Json(followers_of(&mut conn, &user, kind, id).await?))
}

#[utoipa::path(put, path = "/chatter/{kind}/{id}/follow", tag = "chatter", operation_id = "chatter_follow",
    params(("kind" = String, Path), ("id" = Uuid, Path)),
    responses((status = 200, body = Followers), (status = 403, body = ErrorBody),
              (status = 404, body = ErrorBody)))]
async fn follow(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((kind, id)): Path<(String, Uuid)>,
) -> AppResult<Json<Followers>> {
    let mut tx = state.db.begin().await?;
    let kind = open(&mut tx, &user, &kind, id, false).await?;
    follow_record(&mut tx, user.company_id, kind, id, user.user_id, "manual").await?;
    let out = followers_of(&mut tx, &user, kind, id).await?;
    tx.commit().await?;
    publish(&state, &user, kind, id, "chatter_followers");
    Ok(Json(out))
}

async fn mute(
    conn: &mut PgConnection,
    user: &CurrentUser,
    kind: RecordKind,
    id: Uuid,
    target: Uuid,
) -> AppResult<()> {
    sqlx::query(
        "UPDATE chatter.followers SET muted_at = now()
         WHERE company_id = $1 AND record_kind = $2 AND record_id = $3 AND user_id = $4",
    )
    .bind(user.company_id)
    .bind(kind.as_str())
    .bind(id)
    .bind(target)
    .execute(&mut *conn)
    .await?;
    Ok(())
}

#[utoipa::path(delete, path = "/chatter/{kind}/{id}/follow", tag = "chatter", operation_id = "chatter_unfollow",
    params(("kind" = String, Path), ("id" = Uuid, Path)),
    responses((status = 200, body = Followers), (status = 403, body = ErrorBody),
              (status = 404, body = ErrorBody)))]
async fn unfollow(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((kind, id)): Path<(String, Uuid)>,
) -> AppResult<Json<Followers>> {
    let mut tx = state.db.begin().await?;
    let kind = open(&mut tx, &user, &kind, id, false).await?;
    mute(&mut tx, &user, kind, id, user.user_id).await?;
    let out = followers_of(&mut tx, &user, kind, id).await?;
    tx.commit().await?;
    publish(&state, &user, kind, id, "chatter_followers");
    Ok(Json(out))
}

#[utoipa::path(post, path = "/chatter/{kind}/{id}/followers", tag = "chatter", operation_id = "chatter_add_follower",
    params(("kind" = String, Path), ("id" = Uuid, Path)), request_body = FollowerInput,
    responses((status = 200, body = Followers), (status = 403, body = ErrorBody),
              (status = 404, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn add_follower(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((kind, id)): Path<(String, Uuid)>,
    Json(input): Json<FollowerInput>,
) -> AppResult<Json<Followers>> {
    let mut tx = state.db.begin().await?;
    let kind = open(&mut tx, &user, &kind, id, true).await?;
    check_member(&mut tx, &user, input.user_id).await?;
    follow_record(&mut tx, user.company_id, kind, id, input.user_id, "manual").await?;
    let out = followers_of(&mut tx, &user, kind, id).await?;
    tx.commit().await?;
    publish(&state, &user, kind, id, "chatter_followers");
    Ok(Json(out))
}

#[utoipa::path(delete, path = "/chatter/{kind}/{id}/followers/{user_id}", tag = "chatter", operation_id = "chatter_remove_follower",
    params(("kind" = String, Path), ("id" = Uuid, Path), ("user_id" = Uuid, Path)),
    responses((status = 200, body = Followers), (status = 403, body = ErrorBody),
              (status = 404, body = ErrorBody)))]
async fn remove_follower(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((kind, id, target)): Path<(String, Uuid, Uuid)>,
) -> AppResult<Json<Followers>> {
    let mut tx = state.db.begin().await?;
    let kind = open(&mut tx, &user, &kind, id, true).await?;
    mute(&mut tx, &user, kind, id, target).await?;
    let out = followers_of(&mut tx, &user, kind, id).await?;
    tx.commit().await?;
    publish(&state, &user, kind, id, "chatter_followers");
    Ok(Json(out))
}

#[utoipa::path(post, path = "/chatter/{kind}/{id}/read", tag = "chatter", operation_id = "chatter_mark_read",
    params(("kind" = String, Path), ("id" = Uuid, Path)),
    responses((status = 204), (status = 403, body = ErrorBody), (status = 404, body = ErrorBody)))]
async fn mark_read(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((kind, id)): Path<(String, Uuid)>,
) -> AppResult<StatusCode> {
    let mut conn = state.db.acquire().await?;
    let kind = open(&mut conn, &user, &kind, id, false).await?;
    sqlx::query(
        "UPDATE chatter.followers SET last_read_at = now()
         WHERE company_id = $1 AND record_kind = $2 AND record_id = $3 AND user_id = $4",
    )
    .bind(user.company_id)
    .bind(kind.as_str())
    .bind(id)
    .bind(user.user_id)
    .execute(&mut *conn)
    .await?;
    Ok(StatusCode::NO_CONTENT)
}

// ---------------------------------------------------------------------------------------------
// Inbox
// ---------------------------------------------------------------------------------------------

#[utoipa::path(get, path = "/chatter/inbox", tag = "chatter", operation_id = "chatter_inbox",
    responses((status = 200, body = Inbox)))]
async fn inbox(State(state): State<AppState>, user: CurrentUser) -> AppResult<Json<Inbox>> {
    let mut conn = state.db.acquire().await?;
    let unread: Vec<InboxRecord> = sqlx::query_as(
        "SELECT f.record_kind, f.record_id, NULL::text AS label,
                count(*) AS unread, max(m.created_at) AS last_at
         FROM chatter.followers f
         JOIN chatter.messages m
           ON m.company_id = f.company_id AND m.record_kind = f.record_kind
          AND m.record_id = f.record_id AND m.created_at > f.last_read_at
          AND m.author_user_id IS DISTINCT FROM f.user_id
         WHERE f.company_id = $1 AND f.user_id = $2 AND f.muted_at IS NULL
         GROUP BY f.record_kind, f.record_id
         ORDER BY max(m.created_at) DESC LIMIT 50",
    )
    .bind(user.company_id)
    .bind(user.user_id)
    .fetch_all(&mut *conn)
    .await?;
    let mut out_unread = Vec::new();
    for mut r in unread {
        let Some(kind) = RecordKind::parse(&r.record_kind) else {
            continue;
        };
        if !user.can(kind.read_permission()) {
            continue;
        }
        // A record that is gone has no label; it is not shown.
        let Some(label) = kind.label(&mut conn, user.company_id, r.record_id).await? else {
            continue;
        };
        r.label = Some(label);
        out_unread.push(r);
    }
    let rows: Vec<(Uuid, String, Uuid, String, String, NaiveDate, bool)> = sqlx::query_as(
        "SELECT id, record_kind, record_id, kind, summary, due_date, due_date < current_date
         FROM chatter.activities
         WHERE company_id = $1 AND assignee_id = $2 AND done_at IS NULL
           AND due_date <= current_date
         ORDER BY due_date, id LIMIT 50",
    )
    .bind(user.company_id)
    .bind(user.user_id)
    .fetch_all(&mut *conn)
    .await?;
    let mut activities = Vec::new();
    for (id, rk, rid, kind, summary, due_date, overdue) in rows {
        let Some(k) = RecordKind::parse(&rk) else {
            continue;
        };
        if !user.can(k.read_permission()) {
            continue;
        }
        let Some(label) = k.label(&mut conn, user.company_id, rid).await? else {
            continue;
        };
        activities.push(InboxActivity {
            id,
            record_kind: rk,
            record_id: rid,
            label: Some(label),
            kind,
            summary,
            due_date,
            overdue,
        });
    }
    Ok(Json(Inbox {
        unread: out_unread,
        activities,
    }))
}
