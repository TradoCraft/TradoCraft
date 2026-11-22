//! HTTP endpoints of the chatter (ADR 0086).
//!
//! Every endpoint about a record first checks that the record exists in the caller's company and
//! that the caller holds the kind's read permission; writing needs the kind's write permission,
//! except following oneself. Anything else answers 404 so ids reveal nothing.

use axum::body::Bytes;
use axum::extract::{DefaultBodyLimit, Path, Query, State};
use axum::http::StatusCode;
use axum::response::Response;
use axum::Json;
use chrono::{DateTime, NaiveDate, Utc};
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection};
use std::collections::HashMap;
use tradocraft_core::files::{self, FileInfo, MAX_FILE_BYTES};
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
/// Most files on one note.
pub const MAX_FILES_PER_NOTE: usize = 10;
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
        .routes(routes!(update_activity, delete_activity))
        .routes(routes!(list_followers, add_follower))
        .routes(routes!(follow, unfollow))
        .routes(routes!(remove_follower))
        .routes(routes!(mark_read))
        .routes(routes!(inbox))
        .routes(routes!(download_file))
        .merge(
            OpenApiRouter::new()
                .routes(routes!(upload_file))
                .layer(DefaultBodyLimit::max(MAX_FILE_BYTES + 64 * 1024)),
        )
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
    #[schema(value_type = Vec<Object>)]
    pub changes: serde_json::Value,
    pub created_at: DateTime<Utc>,
    pub edited_at: Option<DateTime<Utc>>,
    /// Whether the caller may still edit or delete it (own note, within 15 minutes).
    #[sqlx(default)]
    pub editable: bool,
    /// The files of a note, oldest first.
    #[sqlx(skip)]
    pub files: Vec<FileInfo>,
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
pub struct ChatterNoteInput {
    pub body: String,
    /// Files uploaded to this record by the caller that are not on a note yet (at most 10).
    #[serde(default)]
    pub file_ids: Vec<Uuid>,
    /// Chosen by the client so that a retried post does not post twice.
    pub client_id: Option<Uuid>,
}

/// A new text for an own, recent note. Files cannot be added to a note afterwards.
#[derive(Debug, Deserialize, ToSchema)]
pub struct ChatterNoteEdit {
    pub body: String,
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
    /// `YYYY-MM-DD`; a full datetime (a Dart `DateTime`) is accepted and cut to its date.
    #[serde(deserialize_with = "tradocraft_core::serde_util::date")]
    pub due_date: NaiveDate,
    pub client_id: Option<Uuid>,
}

/// Fields to change on an open activity; absent fields stay as they are.
#[derive(Debug, Default, Deserialize, ToSchema)]
pub struct ActivityPatch {
    pub kind: Option<ActivityKind>,
    pub summary: Option<String>,
    pub note: Option<String>,
    pub assignee_id: Option<Uuid>,
    /// `YYYY-MM-DD`; a full datetime is accepted and cut to its date.
    #[serde(default, deserialize_with = "tradocraft_core::serde_util::opt_date")]
    pub due_date: Option<NaiveDate>,
}

#[derive(Debug, Default, Deserialize, ToSchema)]
pub struct ActivityDoneInput {
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

/// An assignee or an added follower must be an active colleague who may read the record: the
/// activity mail carries its label and summary, and the inbox would list it.
async fn check_assignee(
    state: &AppState,
    conn: &mut PgConnection,
    user: &CurrentUser,
    kind: RecordKind,
    assignee: Uuid,
) -> AppResult<()> {
    check_member(conn, user, assignee).await?;
    let member = CurrentUser::for_member(&state.db, assignee, user.company_id).await?;
    if !member.can(kind.read_permission()) {
        return Err(AppError::Validation(
            "that colleague may not read this record".into(),
        ));
    }
    Ok(())
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
    let mut items: Vec<ThreadItem> = sqlx::query_as(sqlx::AssertSqlSafe(format!(
        "{THREAD_SELECT}
         WHERE m.company_id = $3 AND m.record_kind = $4 AND m.record_id = $5
           AND ($6::uuid IS NULL OR m.id < $6)
         ORDER BY m.id DESC LIMIT $7"
    )))
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
    attach_files(&mut conn, &mut items).await?;
    // The SQL knows the author and the window; the permission is checked here. Someone who lost
    // write access can no longer change a note they wrote a minute ago.
    if !user.can(kind.write_permission()) {
        for item in &mut items {
            item.editable = false;
        }
    }
    Ok(Json(ThreadPage {
        items,
        next_before_id,
    }))
}

async fn load_item(conn: &mut PgConnection, user: &CurrentUser, id: Uuid) -> AppResult<ThreadItem> {
    let item: ThreadItem = sqlx::query_as(sqlx::AssertSqlSafe(format!(
        "{THREAD_SELECT} WHERE m.id = $3 AND m.company_id = $4"
    )))
    .bind(user.user_id)
    .bind(window())
    .bind(id)
    .bind(user.company_id)
    .fetch_optional(&mut *conn)
    .await?
    .ok_or(AppError::NotFound("note"))?;
    let mut items = vec![item];
    attach_files(conn, &mut items).await?;
    Ok(items.remove(0))
}

#[derive(FromRow)]
struct LinkedFile {
    message_id: Uuid,
    #[sqlx(flatten)]
    file: FileInfo,
}

/// Fills `files` of the given thread items, oldest file first.
async fn attach_files(conn: &mut PgConnection, items: &mut [ThreadItem]) -> AppResult<()> {
    let ids: Vec<Uuid> = items.iter().map(|i| i.id).collect();
    if ids.is_empty() {
        return Ok(());
    }
    let rows: Vec<LinkedFile> = sqlx::query_as(
        "SELECT mf.message_id, f.id, f.filename, f.content_type, f.size_bytes, f.uploader_name,
                f.created_at
         FROM chatter.message_files mf JOIN core.files f ON f.id = mf.file_id
         WHERE mf.message_id = ANY($1) ORDER BY mf.created_at, f.id",
    )
    .bind(&ids)
    .fetch_all(&mut *conn)
    .await?;
    let mut by_message: HashMap<Uuid, Vec<FileInfo>> = HashMap::new();
    for r in rows {
        by_message.entry(r.message_id).or_default().push(r.file);
    }
    for item in items {
        item.files = by_message.remove(&item.id).unwrap_or_default();
    }
    Ok(())
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
    params(("kind" = String, Path), ("id" = Uuid, Path)), request_body = ChatterNoteInput,
    responses((status = 201, body = ThreadItem), (status = 200, body = ThreadItem),
              (status = 403, body = ErrorBody), (status = 404, body = ErrorBody),
              (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn post_note(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((kind, id)): Path<(String, Uuid)>,
    Json(input): Json<ChatterNoteInput>,
) -> AppResult<(StatusCode, Json<ThreadItem>)> {
    let body = clean_body(&input.body)?;
    let mut tx = state.db.begin().await?;
    let kind = open(&mut tx, &user, &kind, id, true).await?;
    if let Some(client_id) = input.client_id {
        // A retried post returns the note that exists (200).
        if let Some(item) = existing_note(&mut tx, &user, kind, id, client_id).await? {
            return Ok((StatusCode::OK, Json(item)));
        }
    }
    let mid = new_id();
    // Two requests with the same client id can race: the loser inserts nothing and answers with
    // the winner's note, without any of the side effects below.
    let inserted = sqlx::query(
        "INSERT INTO chatter.messages
             (id, company_id, record_kind, record_id, kind, author_user_id, body, client_id)
         VALUES ($1, $2, $3, $4, 'note', $5, $6, $7)
         ON CONFLICT (company_id, client_id) WHERE client_id IS NOT NULL DO NOTHING",
    )
    .bind(mid)
    .bind(user.company_id)
    .bind(kind.as_str())
    .bind(id)
    .bind(user.user_id)
    .bind(&body)
    .bind(input.client_id)
    .execute(&mut *tx)
    .await?
    .rows_affected();
    if inserted == 0 {
        let item = match input.client_id {
            Some(client_id) => existing_note(&mut tx, &user, kind, id, client_id).await?,
            None => None,
        };
        return match item {
            Some(item) => Ok((StatusCode::OK, Json(item))),
            None => Err(AppError::Conflict("client_id is already used".into())),
        };
    }
    link_files(&mut tx, &user, kind, id, mid, &input.file_ids).await?;
    follow_record(&mut tx, user.company_id, kind, id, user.user_id, "author").await?;
    // Writing a note means the author has seen the thread up to now.
    sqlx::query(
        "UPDATE chatter.followers SET last_read_at = greatest(last_read_at, now())
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

/// The note a retried post refers to; 409 when the client id belongs to another record or author.
async fn existing_note(
    conn: &mut PgConnection,
    user: &CurrentUser,
    kind: RecordKind,
    id: Uuid,
    client_id: Uuid,
) -> AppResult<Option<ThreadItem>> {
    let existing: Option<(Uuid, String, Uuid, Option<Uuid>)> = sqlx::query_as(
        "SELECT id, record_kind, record_id, author_user_id FROM chatter.messages
         WHERE company_id = $1 AND client_id = $2",
    )
    .bind(user.company_id)
    .bind(client_id)
    .fetch_optional(&mut *conn)
    .await?;
    let Some((mid, k, rid, author)) = existing else {
        return Ok(None);
    };
    if k != kind.as_str() || rid != id || author != Some(user.user_id) {
        return Err(AppError::Conflict("client_id is already used".into()));
    }
    Ok(Some(load_item(conn, user, mid).await?))
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
    params(("id" = Uuid, Path)), request_body = ChatterNoteEdit,
    responses((status = 200, body = ThreadItem), (status = 403, body = ErrorBody),
              (status = 404, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn edit_note(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<ChatterNoteEdit>,
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
// Files
// ---------------------------------------------------------------------------------------------

#[derive(Debug, Deserialize, IntoParams)]
pub struct UploadParams {
    /// The original file name.
    pub filename: Option<String>,
    /// A client-chosen id: uploading the same id again returns the first upload (safe retries).
    pub client_id: Option<Uuid>,
}

/// Links the caller's pending uploads to the note that was just written. The files must have
/// been uploaded to this record by the caller and not be on a note yet.
async fn link_files(
    conn: &mut PgConnection,
    user: &CurrentUser,
    kind: RecordKind,
    record_id: Uuid,
    message_id: Uuid,
    file_ids: &[Uuid],
) -> AppResult<()> {
    let mut ids = file_ids.to_vec();
    ids.sort();
    ids.dedup();
    if ids.is_empty() {
        return Ok(());
    }
    if ids.len() > MAX_FILES_PER_NOTE {
        return Err(AppError::Validation(format!(
            "at most {MAX_FILES_PER_NOTE} files per note"
        )));
    }
    let updated = sqlx::query(
        "UPDATE chatter.message_files SET message_id = $1
         WHERE file_id = ANY($2) AND message_id IS NULL AND company_id = $3
           AND record_kind = $4 AND record_id = $5 AND uploaded_by = $6",
    )
    .bind(message_id)
    .bind(&ids)
    .bind(user.company_id)
    .bind(kind.as_str())
    .bind(record_id)
    .bind(user.user_id)
    .execute(&mut *conn)
    .await?;
    if updated.rows_affected() as usize != ids.len() {
        return Err(AppError::Validation(
            "a file was not found on this record or is already used".into(),
        ));
    }
    Ok(())
}

/// Uploads a file to the record: the request body is the file itself (JPEG, PNG, WebP or PDF,
/// at most 12 MB). Put its id in `file_ids` when posting the note.
#[utoipa::path(post, path = "/chatter/{kind}/{id}/files", tag = "chatter", operation_id = "chatter_upload_file",
    params(("kind" = String, Path), ("id" = Uuid, Path), UploadParams),
    request_body(content = String, content_type = "application/octet-stream"),
    responses((status = 201, body = FileInfo), (status = 403, body = ErrorBody),
              (status = 404, body = ErrorBody), (status = 409, body = ErrorBody),
              (status = 422, body = ErrorBody)))]
async fn upload_file(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((kind, id)): Path<(String, Uuid)>,
    Query(p): Query<UploadParams>,
    body: Bytes,
) -> AppResult<(StatusCode, Json<FileInfo>)> {
    let mut tx = state.db.begin().await?;
    let kind = open(&mut tx, &user, &kind, id, true).await?;
    if let Some(client_id) = p.client_id {
        // A retry may only meet its own earlier upload. A file id that exists for any other
        // reason (a ticket attachment, a photo, another record's upload) is never adopted.
        let known: Option<(String, Uuid, Uuid)> = sqlx::query_as(
            "SELECT record_kind, record_id, uploaded_by FROM chatter.message_files WHERE file_id = $1",
        )
        .bind(client_id)
        .fetch_optional(&mut *tx)
        .await?;
        match known {
            Some((k, r, u)) if k == kind.as_str() && r == id && u == user.user_id => {}
            Some(_) => {
                return Err(AppError::Conflict(
                    "this file id belongs to another record".into(),
                ))
            }
            None => {
                let used: bool =
                    sqlx::query_scalar("SELECT EXISTS (SELECT 1 FROM core.files WHERE id = $1)")
                        .bind(client_id)
                        .fetch_one(&mut *tx)
                        .await?;
                if used {
                    return Err(AppError::Conflict("this file id is already used".into()));
                }
            }
        }
    }
    let file = files::store_document(
        &mut tx,
        &state.blobs,
        user.company_id,
        p.client_id,
        p.filename.as_deref().unwrap_or(""),
        &body,
        Some(user.user_id),
        &user.display_name,
    )
    .await?;
    sqlx::query(
        "INSERT INTO chatter.message_files (file_id, company_id, record_kind, record_id, uploaded_by)
         VALUES ($1, $2, $3, $4, $5) ON CONFLICT (file_id) DO NOTHING",
    )
    .bind(file.id)
    .bind(user.company_id)
    .bind(kind.as_str())
    .bind(id)
    .bind(user.user_id)
    .execute(&mut *tx)
    .await?;
    // A retried upload with the same id must be the same upload; any other file id is taken.
    let same: bool = sqlx::query_scalar(
        "SELECT record_kind = $2 AND record_id = $3 AND uploaded_by = $4
         FROM chatter.message_files WHERE file_id = $1",
    )
    .bind(file.id)
    .bind(kind.as_str())
    .bind(id)
    .bind(user.user_id)
    .fetch_one(&mut *tx)
    .await?;
    if !same {
        return Err(AppError::Conflict(
            "this file id belongs to another record".into(),
        ));
    }
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(file)))
}

/// The file itself, as a download. A file not yet on a note is only visible to its uploader.
#[utoipa::path(get, path = "/chatter/{kind}/{id}/files/{file_id}", tag = "chatter", operation_id = "chatter_download_file",
    params(("kind" = String, Path), ("id" = Uuid, Path), ("file_id" = Uuid, Path)),
    responses((status = 200, content_type = "application/octet-stream", body = String),
              (status = 403, body = ErrorBody), (status = 404, body = ErrorBody)))]
async fn download_file(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((kind, id, file_id)): Path<(String, Uuid, Uuid)>,
) -> AppResult<Response> {
    let mut conn = state.db.acquire().await?;
    let kind = open(&mut conn, &user, &kind, id, false).await?;
    let visible: bool = sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM chatter.message_files
            WHERE file_id = $1 AND company_id = $2 AND record_kind = $3 AND record_id = $4
              AND (message_id IS NOT NULL OR uploaded_by = $5))",
    )
    .bind(file_id)
    .bind(user.company_id)
    .bind(kind.as_str())
    .bind(id)
    .bind(user.user_id)
    .fetch_one(&mut *conn)
    .await?;
    if !visible {
        return Err(AppError::NotFound("file"));
    }
    let info = files::get_info(&mut conn, user.company_id, file_id)
        .await?
        .ok_or(AppError::NotFound("file"))?;
    let (content_type, bytes) =
        files::load(&mut conn, &state.blobs, user.company_id, file_id).await?;
    Ok(files::attachment_response(
        &content_type,
        &info.filename,
        bytes,
    ))
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
    let rows = sqlx::query_as(sqlx::AssertSqlSafe(format!(
        "{ACTIVITY_SELECT}
         WHERE a.company_id = $1 AND a.record_kind = $2 AND a.record_id = $3 AND a.done_at IS NULL
         ORDER BY a.due_date, a.id"
    )))
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
    // A retry finds its activity before the assignee is checked again.
    if let Some(client_id) = input.client_id {
        if let Some(a) = existing_activity(&mut tx, &user, kind, id, client_id).await? {
            return Ok((StatusCode::OK, Json(a)));
        }
    }
    check_assignee(&state, &mut tx, &user, kind, input.assignee_id).await?;
    let aid = new_id();
    let inserted = sqlx::query(
        "INSERT INTO chatter.activities
             (id, company_id, record_kind, record_id, kind, summary, note, assignee_id, due_date,
              created_by, client_id)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
         ON CONFLICT (company_id, client_id) WHERE client_id IS NOT NULL DO NOTHING",
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
    .await?
    .rows_affected();
    if inserted == 0 {
        let found = match input.client_id {
            Some(client_id) => existing_activity(&mut tx, &user, kind, id, client_id).await?,
            None => None,
        };
        return match found {
            Some(a) => Ok((StatusCode::OK, Json(a))),
            None => Err(AppError::Conflict("client_id is already used".into())),
        };
    }
    follow_record(
        &mut tx,
        user.company_id,
        kind,
        id,
        input.assignee_id,
        "assigned",
    )
    .await?;
    crate::notify::assigned(
        &mut tx,
        &user,
        kind,
        id,
        input.assignee_id,
        input.kind.as_str(),
        &summary,
        input.due_date,
    )
    .await?;
    let a = load_activity(&mut tx, &user, aid).await?;
    tx.commit().await?;
    publish(&state, &user, kind, id, "chatter_activity");
    Ok((StatusCode::CREATED, Json(a)))
}

/// The activity a retried create refers to; 409 when the client id belongs to another record.
async fn existing_activity(
    conn: &mut PgConnection,
    user: &CurrentUser,
    kind: RecordKind,
    id: Uuid,
    client_id: Uuid,
) -> AppResult<Option<Activity>> {
    let existing: Option<(Uuid, String, Uuid)> = sqlx::query_as(
        "SELECT id, record_kind, record_id FROM chatter.activities
         WHERE company_id = $1 AND client_id = $2",
    )
    .bind(user.company_id)
    .bind(client_id)
    .fetch_optional(&mut *conn)
    .await?;
    let Some((aid, k, rid)) = existing else {
        return Ok(None);
    };
    if k != kind.as_str() || rid != id {
        return Err(AppError::Conflict("client_id is already used".into()));
    }
    Ok(Some(load_activity(conn, user, aid).await?))
}

async fn load_activity(
    conn: &mut PgConnection,
    user: &CurrentUser,
    id: Uuid,
) -> AppResult<Activity> {
    sqlx::query_as(sqlx::AssertSqlSafe(format!(
        "{ACTIVITY_SELECT} WHERE a.id = $1 AND a.company_id = $2"
    )))
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
    params(("id" = Uuid, Path)), request_body = ActivityDoneInput,
    responses((status = 204), (status = 403, body = ErrorBody), (status = 404, body = ErrorBody),
              (status = 422, body = ErrorBody)))]
async fn complete_activity(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<ActivityDoneInput>,
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

#[utoipa::path(patch, path = "/chatter/activities/{id}", tag = "chatter", operation_id = "chatter_update_activity",
    params(("id" = Uuid, Path)), request_body = ActivityPatch,
    responses((status = 200, body = Activity), (status = 403, body = ErrorBody),
              (status = 404, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn update_activity(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(patch): Json<ActivityPatch>,
) -> AppResult<Json<Activity>> {
    let summary = match patch.summary.as_deref().map(str::trim) {
        Some(t) if t.is_empty() || t.chars().count() > MAX_SUMMARY => {
            return Err(AppError::Validation(format!(
                "the summary must be 1 to {MAX_SUMMARY} characters"
            )))
        }
        other => other.map(str::to_string),
    };
    if patch
        .note
        .as_deref()
        .is_some_and(|n| n.chars().count() > MAX_ACTIVITY_NOTE)
    {
        return Err(AppError::Validation(format!(
            "the note is limited to {MAX_ACTIVITY_NOTE} characters"
        )));
    }
    let mut tx = state.db.begin().await?;
    let (kind, record_id, _, _, assignee, creator) = lock_activity(&mut tx, &user, id).await?;
    if user.user_id != assignee && user.user_id != creator {
        return Err(AppError::Forbidden(
            "only the creator or the assignee can change an activity".into(),
        ));
    }
    if let Some(a) = patch.assignee_id {
        check_assignee(&state, &mut tx, &user, kind, a).await?;
        follow_record(&mut tx, user.company_id, kind, record_id, a, "assigned").await?;
    }
    sqlx::query(
        "UPDATE chatter.activities SET
             kind = coalesce($2, kind), summary = coalesce($3, summary),
             note = coalesce($4, note), assignee_id = coalesce($5, assignee_id),
             due_date = coalesce($6, due_date)
         WHERE id = $1",
    )
    .bind(id)
    .bind(patch.kind.map(|k| k.as_str()))
    .bind(summary)
    .bind(patch.note.as_deref().map(str::trim))
    .bind(patch.assignee_id)
    .bind(patch.due_date)
    .execute(&mut *tx)
    .await?;
    let a = load_activity(&mut tx, &user, id).await?;
    // Handing it to somebody else tells them, like scheduling it for them would.
    if patch.assignee_id.is_some_and(|n| n != assignee) {
        crate::notify::assigned(
            &mut tx,
            &user,
            kind,
            record_id,
            a.assignee_id,
            &a.kind,
            &a.summary,
            a.due_date,
        )
        .await?;
    }
    tx.commit().await?;
    publish(&state, &user, kind, record_id, "chatter_activity");
    Ok(Json(a))
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
    check_assignee(&state, &mut tx, &user, kind, input.user_id).await?;
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
        "UPDATE chatter.followers SET last_read_at = greatest(last_read_at, now())
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
    // Kinds the caller may not read are left out in SQL, so they cannot fill the 50 places.
    let readable: Vec<String> = RecordKind::ALL
        .into_iter()
        .filter(|k| user.can(k.read_permission()))
        .map(|k| k.as_str().to_string())
        .collect();
    let unread: Vec<InboxRecord> = sqlx::query_as(
        "SELECT f.record_kind, f.record_id, NULL::text AS label,
                count(*) AS unread, max(m.created_at) AS last_at
         FROM chatter.followers f
         JOIN chatter.messages m
           ON m.company_id = f.company_id AND m.record_kind = f.record_kind
          AND m.record_id = f.record_id AND m.created_at > f.last_read_at
          AND m.author_user_id IS DISTINCT FROM f.user_id
         WHERE f.company_id = $1 AND f.user_id = $2 AND f.muted_at IS NULL
           AND f.record_kind = ANY($3)
         GROUP BY f.record_kind, f.record_id
         ORDER BY max(m.created_at) DESC LIMIT 50",
    )
    .bind(user.company_id)
    .bind(user.user_id)
    .bind(&readable)
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
           AND due_date <= current_date AND record_kind = ANY($3)
         ORDER BY due_date, id LIMIT 50",
    )
    .bind(user.company_id)
    .bind(user.user_id)
    .bind(&readable)
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
