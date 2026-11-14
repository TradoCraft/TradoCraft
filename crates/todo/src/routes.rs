//! HTTP endpoints for to-do items (ADR 0061).
//!
//! Visibility: an item is visible and mutable only to its owner and its assignee, in the active
//! company. Anyone else gets 404, never 403, so the existence of an item is not revealed. Sub-items
//! always share owner and assignee with their root item, so a tree is visible to the same people
//! all the way down.

use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::Json;
use chrono::{DateTime, NaiveDate, Utc};
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection};
use std::collections::HashSet;
use tradocraft_core::audit::{self, Changes};
use tradocraft_core::{new_id, AppError, AppResult, AppState, CurrentUser, Permission};
use utoipa::{IntoParams, ToSchema};
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::link::TodoLinkKind;

type ErrorBody = tradocraft_core::error::ErrorBody;

pub const MAX_TITLE: usize = 200;
pub const MAX_NOTES: usize = 4000;
pub const MAX_LABEL: usize = 200;
pub const MAX_LOCATION: usize = 300;
const MAX_REORDER: usize = 500;
const NOT_FOUND: &str = "to-do item";

// ---------------------------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------------------------

/// One to-do item. Lists are flat: build the tree from `parent_id`.
#[derive(Debug, Serialize, ToSchema)]
pub struct TodoItem {
    pub id: Uuid,
    /// The root item this is a sub-item of; absent for a root item.
    pub parent_id: Option<Uuid>,
    pub position: i32,
    pub title: String,
    pub notes: String,
    pub owner_id: Uuid,
    pub owner_name: String,
    /// The colleague the item is handed to; absent when it stays with the owner.
    pub assignee_id: Option<Uuid>,
    pub assignee_name: Option<String>,
    pub created_by: Uuid,
    /// Whether the caller is the owner (only the owner reassigns and deletes).
    pub mine: bool,
    pub due_date: Option<NaiveDate>,
    pub done: bool,
    pub done_at: Option<DateTime<Utc>>,
    pub done_by: Option<Uuid>,
    pub link_kind: Option<TodoLinkKind>,
    pub link_id: Option<Uuid>,
    /// What the linked record was called when it was linked. Absent when the caller may not read
    /// records of that kind (the app then shows "Linked item").
    pub link_label: Option<String>,
    /// Where the app jumps to for the linked record, e.g. `/quotations/<id>`.
    pub link_location: Option<String>,
    pub client_id: Option<Uuid>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, FromRow)]
struct Row {
    id: Uuid,
    parent_id: Option<Uuid>,
    position: i32,
    title: String,
    notes: String,
    owner_id: Uuid,
    owner_name: String,
    assignee_id: Option<Uuid>,
    assignee_name: Option<String>,
    created_by: Uuid,
    due_date: Option<NaiveDate>,
    done: bool,
    done_at: Option<DateTime<Utc>>,
    done_by: Option<Uuid>,
    link_kind: Option<String>,
    link_id: Option<Uuid>,
    link_label: Option<String>,
    link_location: Option<String>,
    client_id: Option<Uuid>,
    created_at: DateTime<Utc>,
    updated_at: DateTime<Utc>,
}

const SELECT: &str = "SELECT i.id, i.parent_id, i.position, i.title, i.notes, i.owner_id,
        o.display_name AS owner_name, i.assignee_id, a.display_name AS assignee_name,
        i.created_by, i.due_date, i.done, i.done_at, i.done_by, i.link_kind, i.link_id,
        i.link_label, i.link_location, i.client_id, i.created_at, i.updated_at
    FROM todo.items i
    JOIN core.users o ON o.id = i.owner_id
    LEFT JOIN core.users a ON a.id = i.assignee_id";

/// The visibility rule, as SQL: `$1` is the company and `$2` the caller.
const VISIBLE: &str = "i.company_id = $1 AND (i.owner_id = $2 OR i.assignee_id = $2)";

/// Whether the viewer may read the record a link points at: the kind's read permission and, for
/// jobs, the field module's own rule (a technician reads only the jobs they are assigned to).
/// `readable_jobs` holds the job ids of the batch that passed that rule.
pub(crate) fn link_readable(
    user: &CurrentUser,
    kind: Option<TodoLinkKind>,
    id: Option<Uuid>,
    readable_jobs: &HashSet<Uuid>,
) -> bool {
    match kind {
        Some(k) if user.can(k.read_permission()) => {
            k != TodoLinkKind::Job || id.is_some_and(|i| readable_jobs.contains(&i))
        }
        _ => false,
    }
}

/// The job ids among `rows`' links that the viewer may read.
async fn readable_jobs(
    conn: &mut PgConnection,
    user: &CurrentUser,
    rows: &[Row],
) -> AppResult<HashSet<Uuid>> {
    let ids: Vec<Uuid> = rows
        .iter()
        .filter(|r| r.link_kind.as_deref() == Some(TodoLinkKind::Job.as_str()))
        .filter_map(|r| r.link_id)
        .collect();
    readable_job_ids(conn, user, &ids).await
}

pub(crate) async fn readable_job_ids(
    conn: &mut PgConnection,
    user: &CurrentUser,
    ids: &[Uuid],
) -> AppResult<HashSet<Uuid>> {
    if ids.is_empty() || !user.can(TodoLinkKind::Job.read_permission()) {
        return Ok(HashSet::new());
    }
    let found: Vec<Uuid> = sqlx::query_scalar(
        "SELECT j.id FROM field.jobs j
         WHERE j.id = ANY($1) AND j.company_id = $2
           AND ($3 OR EXISTS (SELECT 1 FROM field.job_technicians x
                              WHERE x.job_id = j.id AND x.user_id = $4))",
    )
    .bind(ids)
    .bind(user.company_id)
    .bind(tradocraft_fieldservice::sees_all(user))
    .bind(user.user_id)
    .fetch_all(&mut *conn)
    .await?;
    Ok(found.into_iter().collect())
}

/// Turns rows into items. A link the viewer may not read keeps only its kind (the app shows
/// "Linked item"): id, label and location are left out, since the id and the location would let
/// the viewer reach the record.
async fn to_items(
    conn: &mut PgConnection,
    user: &CurrentUser,
    rows: Vec<Row>,
) -> AppResult<Vec<TodoItem>> {
    let jobs = readable_jobs(conn, user, &rows).await?;
    Ok(rows.into_iter().map(|r| to_item(r, user, &jobs)).collect())
}

fn to_item(r: Row, user: &CurrentUser, jobs: &HashSet<Uuid>) -> TodoItem {
    let kind = r.link_kind.as_deref().and_then(TodoLinkKind::parse);
    let readable = link_readable(user, kind, r.link_id, jobs);
    let (link_id, label, location) = if readable {
        (r.link_id, r.link_label, r.link_location)
    } else {
        (None, None, None)
    };
    TodoItem {
        id: r.id,
        parent_id: r.parent_id,
        position: r.position,
        title: r.title,
        notes: r.notes,
        mine: r.owner_id == user.user_id,
        owner_id: r.owner_id,
        owner_name: r.owner_name,
        assignee_id: r.assignee_id,
        assignee_name: r.assignee_name,
        created_by: r.created_by,
        due_date: r.due_date,
        done: r.done,
        done_at: r.done_at,
        done_by: r.done_by,
        link_kind: kind,
        link_id,
        link_label: label,
        link_location: location,
        client_id: r.client_id,
        created_at: r.created_at,
        updated_at: r.updated_at,
    }
}

async fn load(conn: &mut PgConnection, user: &CurrentUser, id: Uuid) -> AppResult<TodoItem> {
    let row: Option<Row> = sqlx::query_as(&format!("{SELECT} WHERE i.id = $3 AND {VISIBLE}"))
        .bind(user.company_id)
        .bind(user.user_id)
        .bind(id)
        .fetch_optional(&mut *conn)
        .await?;
    let row = row.ok_or(AppError::NotFound(NOT_FOUND))?;
    let mut items = to_items(conn, user, vec![row]).await?;
    Ok(items.remove(0))
}

/// The columns a mutation needs, read under a row lock.
#[derive(Debug, Clone, FromRow)]
struct Raw {
    id: Uuid,
    parent_id: Option<Uuid>,
    position: i32,
    title: String,
    notes: String,
    owner_id: Uuid,
    assignee_id: Option<Uuid>,
    due_date: Option<NaiveDate>,
    done: bool,
    link_kind: Option<String>,
    link_id: Option<Uuid>,
    link_label: Option<String>,
    link_location: Option<String>,
}

const RAW: &str = "SELECT id, parent_id, position, title, notes, owner_id, assignee_id, due_date,
        done, link_kind, link_id, link_label, link_location FROM todo.items";

/// Locks and returns an item the caller may see; 404 otherwise.
async fn lock(conn: &mut PgConnection, user: &CurrentUser, id: Uuid) -> AppResult<Raw> {
    let row: Option<Raw> = sqlx::query_as(&format!(
        "{RAW} WHERE id = $3 AND company_id = $1 AND (owner_id = $2 OR assignee_id = $2)
         FOR UPDATE"
    ))
    .bind(user.company_id)
    .bind(user.user_id)
    .bind(id)
    .fetch_optional(&mut *conn)
    .await?;
    row.ok_or(AppError::NotFound(NOT_FOUND))
}

/// Locks the parent (if any) before the item, the order in which completing a parent locks its
/// sub-items, so two requests cannot wait for each other. `also` is a further parent the request
/// is about to use (a move); it is locked in the same pass, in id order. The item's parent is
/// read first without a lock and checked again once the item is locked: when it was moved in
/// between, the pass starts over.
async fn lock_family(
    conn: &mut PgConnection,
    user: &CurrentUser,
    id: Uuid,
    also: Option<Uuid>,
) -> AppResult<Raw> {
    for _ in 0..3 {
        let parent: Option<Option<Uuid>> = sqlx::query_scalar(
            "SELECT parent_id FROM todo.items
             WHERE id = $3 AND company_id = $1 AND (owner_id = $2 OR assignee_id = $2)",
        )
        .bind(user.company_id)
        .bind(user.user_id)
        .bind(id)
        .fetch_optional(&mut *conn)
        .await?;
        let parent = parent.ok_or(AppError::NotFound(NOT_FOUND))?;
        let mut parents: Vec<Uuid> = parent.into_iter().chain(also).collect();
        parents.sort();
        parents.dedup();
        for p in parents {
            lock(conn, user, p).await?;
        }
        let item = lock(conn, user, id).await?;
        if item.parent_id == parent {
            return Ok(item);
        }
    }
    Err(AppError::Conflict(
        "the item was moved at the same time, try again".into(),
    ))
}

/// A job link is only allowed to a job the caller may read (a technician: one they are assigned
/// to). Other kinds need the kind's read permission only (see ADR 0061).
async fn check_link_target(
    conn: &mut PgConnection,
    user: &CurrentUser,
    link: &Link,
) -> AppResult<()> {
    if link.kind != TodoLinkKind::Job {
        return Ok(());
    }
    if readable_job_ids(conn, user, &[link.id])
        .await?
        .contains(&link.id)
    {
        Ok(())
    } else {
        Err(AppError::NotFound("job"))
    }
}

fn forbidden_not_owner(what: &str) -> AppError {
    AppError::Forbidden(format!("only the owner of a to-do item can {what}"))
}

fn clean_title(t: &str) -> AppResult<String> {
    let t = t.trim();
    if t.is_empty() || t.chars().count() > MAX_TITLE {
        return Err(AppError::Validation(format!(
            "the title must be 1 to {MAX_TITLE} characters"
        )));
    }
    Ok(t.to_string())
}

fn clean_notes(n: &str) -> AppResult<String> {
    if n.chars().count() > MAX_NOTES {
        return Err(AppError::Validation(format!(
            "the notes are limited to {MAX_NOTES} characters"
        )));
    }
    Ok(n.to_string())
}

/// A validated link: the caller may read the kind, the location stays inside the app.
struct Link {
    kind: TodoLinkKind,
    id: Uuid,
    label: Option<String>,
    location: Option<String>,
}

fn clean_link(
    user: &CurrentUser,
    kind: Option<TodoLinkKind>,
    id: Option<Uuid>,
    label: &Option<String>,
    location: &Option<String>,
) -> AppResult<Option<Link>> {
    let (kind, id) = match (kind, id) {
        (None, None) => {
            if label.is_some() || location.is_some() {
                return Err(AppError::Validation(
                    "a link label or location needs link_kind and link_id".into(),
                ));
            }
            return Ok(None);
        }
        (Some(k), Some(i)) => (k, i),
        _ => {
            return Err(AppError::Validation(
                "link_kind and link_id go together".into(),
            ))
        }
    };
    user.require(kind.read_permission())?;
    let label = label
        .as_deref()
        .map(str::trim)
        .filter(|l| !l.is_empty())
        .map(str::to_string);
    if label
        .as_ref()
        .is_some_and(|l| l.chars().count() > MAX_LABEL)
    {
        return Err(AppError::Validation(format!(
            "the link label is limited to {MAX_LABEL} characters"
        )));
    }
    let location = location
        .as_deref()
        .map(str::trim)
        .filter(|l| !l.is_empty())
        .map(str::to_string);
    if let Some(l) = &location {
        if !l.starts_with('/') || l.starts_with("//") || l.chars().count() > MAX_LOCATION {
            return Err(AppError::Validation(format!(
                "the link location must be a path of the app of at most {MAX_LOCATION} characters"
            )));
        }
    }
    Ok(Some(Link {
        kind,
        id,
        label,
        location,
    }))
}

/// An assignee must be an active member of the caller's company.
async fn check_assignee(conn: &mut PgConnection, user: &CurrentUser, id: Uuid) -> AppResult<()> {
    let member: Option<i32> = sqlx::query_scalar(
        "SELECT 1 FROM core.user_companies WHERE user_id = $1 AND company_id = $2 AND active",
    )
    .bind(id)
    .bind(user.company_id)
    .fetch_optional(&mut *conn)
    .await?;
    if member.is_none() {
        return Err(AppError::Validation(
            "the assignee is not an active colleague of this company".into(),
        ));
    }
    Ok(())
}

async fn next_position(
    conn: &mut PgConnection,
    user: &CurrentUser,
    owner_id: Uuid,
    parent_id: Option<Uuid>,
) -> AppResult<i32> {
    let next: Option<i32> = sqlx::query_scalar(
        "SELECT max(position) + 1 FROM todo.items
         WHERE company_id = $1 AND owner_id = $2 AND parent_id IS NOT DISTINCT FROM $3",
    )
    .bind(user.company_id)
    .bind(owner_id)
    .bind(parent_id)
    .fetch_one(&mut *conn)
    .await?;
    Ok(next.unwrap_or(0))
}

/// An open sub-item cannot sit under a finished parent: reopen the parent.
async fn reopen_parent(
    conn: &mut PgConnection,
    user: &CurrentUser,
    parent: &Raw,
    because_of: Uuid,
) -> AppResult<()> {
    if !parent.done {
        return Ok(());
    }
    sqlx::query(
        "UPDATE todo.items SET done = false, done_at = NULL, done_by = NULL, updated_at = now()
         WHERE id = $1",
    )
    .bind(parent.id)
    .execute(&mut *conn)
    .await?;
    audit::record(
        conn,
        user,
        "todo",
        parent.id,
        "reopened",
        serde_json::json!({ "because_of_sub_item": because_of }),
    )
    .await?;
    Ok(())
}

// ---------------------------------------------------------------------------------------------
// Inputs
// ---------------------------------------------------------------------------------------------

#[derive(Debug, Deserialize, ToSchema)]
pub struct TodoCreate {
    /// Chosen by the client; a repeated create with the same id returns the item that exists.
    pub client_id: Option<Uuid>,
    /// Makes this a sub-item of that root item; it then shares the parent's owner and assignee.
    pub parent_id: Option<Uuid>,
    pub title: String,
    #[serde(default)]
    pub notes: String,
    #[serde(default, deserialize_with = "tradocraft_core::serde_util::opt_date")]
    pub due_date: Option<NaiveDate>,
    /// Hands the item to a colleague. Not allowed for sub-items.
    pub assignee_id: Option<Uuid>,
    /// Defaults to the end of its siblings.
    pub position: Option<i32>,
    pub link_kind: Option<TodoLinkKind>,
    pub link_id: Option<Uuid>,
    pub link_label: Option<String>,
    pub link_location: Option<String>,
}

#[derive(Debug, Default, Deserialize, ToSchema)]
pub struct TodoPatch {
    pub title: Option<String>,
    pub notes: Option<String>,
    #[serde(default, deserialize_with = "tradocraft_core::serde_util::opt_date")]
    pub due_date: Option<NaiveDate>,
    #[serde(default)]
    pub clear_due_date: bool,
    /// Owner only; cascades to the sub-items.
    pub assignee_id: Option<Uuid>,
    #[serde(default)]
    pub clear_assignee: bool,
    /// Moves a root item (without sub-items) under another root item of the same owner.
    pub parent_id: Option<Uuid>,
    /// Moves a sub-item up to be a root item.
    #[serde(default)]
    pub make_root: bool,
    pub position: Option<i32>,
    pub link_kind: Option<TodoLinkKind>,
    pub link_id: Option<Uuid>,
    pub link_label: Option<String>,
    pub link_location: Option<String>,
    #[serde(default)]
    pub clear_link: bool,
}

#[derive(Debug, Default, Deserialize, ToSchema)]
pub struct TodoCompleteInput {
    /// Also complete the open sub-items. Without it, completing an item that still has open
    /// sub-items is refused with 409.
    #[serde(default)]
    pub complete_children: bool,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct TodoReorderInput {
    /// The common parent; absent for root items.
    pub parent_id: Option<Uuid>,
    /// The items in their new order. They take the positions the same items had, so items that are
    /// not in the list (for example finished ones that are hidden) keep their places.
    pub ids: Vec<Uuid>,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Deserialize, ToSchema)]
#[serde(rename_all = "kebab-case")]
pub enum TodoScope {
    /// What is on my plate: handed to me, or mine and not handed to anyone.
    #[default]
    Mine,
    /// Mine, handed to a colleague.
    Assigned,
    /// Everything I own or that is handed to me.
    AllMine,
}

#[derive(Debug, Default, Deserialize, IntoParams)]
pub struct TodoQuery {
    /// Defaults to `mine`.
    pub scope: Option<TodoScope>,
    /// `true`: only finished items, `false`: only open ones; absent: both.
    pub done: Option<bool>,
    pub link_kind: Option<TodoLinkKind>,
    /// Needs `link_kind`.
    pub link_id: Option<Uuid>,
    /// Items due strictly before this date.
    #[serde(default, deserialize_with = "tradocraft_core::serde_util::opt_date")]
    pub due_before: Option<NaiveDate>,
}

#[derive(Debug, Serialize, FromRow, ToSchema)]
pub struct TodoCounts {
    /// Open root items on my plate (the list the page shows by default); sub-items are not counted.
    pub open: i64,
    /// Open root items on my plate that were due before today (the database date).
    pub overdue: i64,
    /// Open root items on my plate that are due today.
    pub due_today: i64,
}

// ---------------------------------------------------------------------------------------------
// Router
// ---------------------------------------------------------------------------------------------

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(list_items, create_item))
        .routes(routes!(counts))
        .routes(routes!(get_settings, put_settings))
        .routes(routes!(reorder))
        .routes(routes!(update_item, delete_item))
        .routes(routes!(complete_item))
        .routes(routes!(reopen_item))
}

// ---------------------------------------------------------------------------------------------
// Endpoints
// ---------------------------------------------------------------------------------------------

#[utoipa::path(get, path = "/todo/items", tag = "todo", operation_id = "todo_list",
    params(TodoQuery),
    responses((status = 200, body = Vec<TodoItem>), (status = 403, body = ErrorBody),
              (status = 422, body = ErrorBody)))]
async fn list_items(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(q): Query<TodoQuery>,
) -> AppResult<Json<Vec<TodoItem>>> {
    user.require(Permission::TodoUse)?;
    if q.link_id.is_some() && q.link_kind.is_none() {
        return Err(AppError::Validation("link_id needs link_kind".into()));
    }
    let scope = match q.scope.unwrap_or_default() {
        TodoScope::Mine => "(i.assignee_id = $2 OR (i.owner_id = $2 AND i.assignee_id IS NULL))",
        TodoScope::Assigned => {
            "(i.owner_id = $2 AND i.assignee_id IS NOT NULL AND i.assignee_id <> $2)"
        }
        TodoScope::AllMine => "(i.owner_id = $2 OR i.assignee_id = $2)",
    };
    let rows: Vec<Row> = sqlx::query_as(&format!(
        "{SELECT} WHERE {VISIBLE} AND {scope}
           AND ($3::bool IS NULL OR i.done = $3)
           AND ($4::text IS NULL OR i.link_kind = $4)
           AND ($5::uuid IS NULL OR i.link_id = $5)
           AND ($6::date IS NULL OR i.due_date < $6)
         ORDER BY i.parent_id NULLS FIRST, i.position, i.created_at, i.id"
    ))
    .bind(user.company_id)
    .bind(user.user_id)
    .bind(q.done)
    .bind(q.link_kind.map(|k| k.as_str()))
    .bind(q.link_id)
    .bind(q.due_before)
    .fetch_all(&state.db)
    .await?;
    let mut conn = state.db.acquire().await?;
    Ok(Json(to_items(&mut conn, &user, rows).await?))
}

#[utoipa::path(get, path = "/todo/items/counts", tag = "todo", operation_id = "todo_counts",
    responses((status = 200, body = TodoCounts), (status = 403, body = ErrorBody)))]
async fn counts(State(state): State<AppState>, user: CurrentUser) -> AppResult<Json<TodoCounts>> {
    user.require(Permission::TodoUse)?;
    let counts: TodoCounts = sqlx::query_as(
        "SELECT count(*) AS open,
                count(*) FILTER (WHERE due_date < CURRENT_DATE) AS overdue,
                count(*) FILTER (WHERE due_date = CURRENT_DATE) AS due_today
         FROM todo.items
         WHERE company_id = $1 AND NOT done AND parent_id IS NULL
           AND (assignee_id = $2 OR (owner_id = $2 AND assignee_id IS NULL))",
    )
    .bind(user.company_id)
    .bind(user.user_id)
    .fetch_one(&state.db)
    .await?;
    Ok(Json(counts))
}

#[derive(Debug, Serialize, ToSchema)]
pub struct TodoSettings {
    /// Whether a digest mail is sent when items are due or overdue. On by default.
    pub email_reminders: bool,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct TodoSettingsInput {
    pub email_reminders: bool,
}

async fn email_reminders(
    conn: &mut PgConnection,
    user: &CurrentUser,
) -> Result<Option<bool>, sqlx::Error> {
    sqlx::query_scalar(
        "SELECT email_reminders FROM todo.user_settings WHERE user_id = $1 AND company_id = $2",
    )
    .bind(user.user_id)
    .bind(user.company_id)
    .fetch_optional(conn)
    .await
}

#[utoipa::path(get, path = "/todo/settings", tag = "todo", operation_id = "todo_settings_get",
    responses((status = 200, body = TodoSettings), (status = 403, body = ErrorBody)))]
async fn get_settings(
    State(state): State<AppState>,
    user: CurrentUser,
) -> AppResult<Json<TodoSettings>> {
    user.require(Permission::TodoUse)?;
    let mut conn = state.db.acquire().await?;
    let on = email_reminders(&mut conn, &user).await?.unwrap_or(true);
    Ok(Json(TodoSettings {
        email_reminders: on,
    }))
}

#[utoipa::path(put, path = "/todo/settings", tag = "todo", operation_id = "todo_settings_put",
    request_body = TodoSettingsInput,
    responses((status = 200, body = TodoSettings), (status = 403, body = ErrorBody)))]
async fn put_settings(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<TodoSettingsInput>,
) -> AppResult<Json<TodoSettings>> {
    user.require(Permission::TodoUse)?;
    let mut tx = state.db.begin().await?;
    // Serialise concurrent changes of the same row; the audit row says only the boolean.
    sqlx::query(
        "INSERT INTO todo.user_settings (user_id, company_id) VALUES ($1, $2)
         ON CONFLICT (user_id, company_id) DO NOTHING",
    )
    .bind(user.user_id)
    .bind(user.company_id)
    .execute(&mut *tx)
    .await?;
    let old: bool = sqlx::query_scalar(
        "SELECT email_reminders FROM todo.user_settings
         WHERE user_id = $1 AND company_id = $2 FOR UPDATE",
    )
    .bind(user.user_id)
    .bind(user.company_id)
    .fetch_one(&mut *tx)
    .await?;
    if old != input.email_reminders {
        sqlx::query(
            "UPDATE todo.user_settings SET email_reminders = $3, updated_at = now()
             WHERE user_id = $1 AND company_id = $2",
        )
        .bind(user.user_id)
        .bind(user.company_id)
        .bind(input.email_reminders)
        .execute(&mut *tx)
        .await?;
        audit::record(
            &mut tx,
            &user,
            "todo_settings",
            user.user_id,
            "updated",
            serde_json::json!({ "email_reminders": input.email_reminders }),
        )
        .await?;
    }
    tx.commit().await?;
    Ok(Json(TodoSettings {
        email_reminders: input.email_reminders,
    }))
}

#[utoipa::path(post, path = "/todo/items", tag = "todo", operation_id = "todo_create",
    request_body = TodoCreate,
    responses((status = 201, body = TodoItem), (status = 200, body = TodoItem, description = "The item of this client_id already existed"),
              (status = 403, body = ErrorBody), (status = 404, body = ErrorBody),
              (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn create_item(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<TodoCreate>,
) -> AppResult<(StatusCode, Json<TodoItem>)> {
    user.require(Permission::TodoUse)?;
    let mut tx = state.db.begin().await?;

    if let Some(client_id) = input.client_id {
        let existing: Option<Uuid> = sqlx::query_scalar(
            "SELECT id FROM todo.items WHERE company_id = $1 AND client_id = $2",
        )
        .bind(user.company_id)
        .bind(client_id)
        .fetch_optional(&mut *tx)
        .await?;
        if let Some(id) = existing {
            return existing_item(&mut tx, &user, id).await;
        }
    }

    let title = clean_title(&input.title)?;
    let notes = clean_notes(&input.notes)?;
    let link = clean_link(
        &user,
        input.link_kind,
        input.link_id,
        &input.link_label,
        &input.link_location,
    )?;
    if let Some(l) = &link {
        check_link_target(&mut tx, &user, l).await?;
    }

    let (owner_id, assignee_id) = match input.parent_id {
        Some(parent_id) => {
            let parent = lock(&mut tx, &user, parent_id).await?;
            if parent.parent_id.is_some() {
                return Err(AppError::Validation(
                    "sub-items cannot have sub-items".into(),
                ));
            }
            if input.assignee_id.is_some() {
                return Err(AppError::Validation(
                    "a sub-item follows the assignee of its parent".into(),
                ));
            }
            (parent.owner_id, parent.assignee_id)
        }
        None => {
            let assignee = match input.assignee_id {
                Some(a) if a == user.user_id => None,
                Some(a) => {
                    check_assignee(&mut tx, &user, a).await?;
                    Some(a)
                }
                None => None,
            };
            (user.user_id, assignee)
        }
    };
    let position = match input.position {
        Some(p) => p,
        None => next_position(&mut tx, &user, owner_id, input.parent_id).await?,
    };

    let id = new_id();
    let inserted: Option<Uuid> = sqlx::query_scalar(
        "INSERT INTO todo.items
            (id, company_id, parent_id, position, title, notes, owner_id, assignee_id, created_by,
             due_date, link_kind, link_id, link_label, link_location, client_id)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15)
         ON CONFLICT (company_id, client_id) WHERE client_id IS NOT NULL DO NOTHING
         RETURNING id",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(input.parent_id)
    .bind(position)
    .bind(&title)
    .bind(&notes)
    .bind(owner_id)
    .bind(assignee_id)
    .bind(user.user_id)
    .bind(input.due_date)
    .bind(link.as_ref().map(|l| l.kind.as_str()))
    .bind(link.as_ref().map(|l| l.id))
    .bind(link.as_ref().and_then(|l| l.label.clone()))
    .bind(link.as_ref().and_then(|l| l.location.clone()))
    .bind(input.client_id)
    .fetch_optional(&mut *tx)
    .await?;
    if inserted.is_none() {
        // A concurrent create with the same client_id won.
        let existing: Uuid = sqlx::query_scalar(
            "SELECT id FROM todo.items WHERE company_id = $1 AND client_id = $2",
        )
        .bind(user.company_id)
        .bind(input.client_id)
        .fetch_one(&mut *tx)
        .await?;
        return existing_item(&mut tx, &user, existing).await;
    }

    if let Some(parent_id) = input.parent_id {
        let parent = lock(&mut tx, &user, parent_id).await?;
        reopen_parent(&mut tx, &user, &parent, id).await?;
    }
    // Titles and notes are private: the audit trail is read by administrators, so it records
    // that an item was made and where it sits, not what it says.
    audit::record(
        &mut tx,
        &user,
        "todo",
        id,
        "created",
        serde_json::json!({
            "parent_id": input.parent_id,
            "assignee_id": assignee_id,
            "due_date": input.due_date,
            "link_kind": link.as_ref().map(|l| l.kind.as_str()),
            "link_id": link.as_ref().map(|l| l.id),
        }),
    )
    .await?;
    let item = load(&mut tx, &user, id).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(item)))
}

/// The answer to a repeated create: the item that exists, if the caller may see it.
async fn existing_item(
    conn: &mut PgConnection,
    user: &CurrentUser,
    id: Uuid,
) -> AppResult<(StatusCode, Json<TodoItem>)> {
    match load(conn, user, id).await {
        Ok(item) => Ok((StatusCode::OK, Json(item))),
        // The id is taken by an item that is not the caller's; say nothing more.
        Err(AppError::NotFound(_)) => Err(AppError::Conflict(
            "this client_id is already in use".into(),
        )),
        Err(e) => Err(e),
    }
}

#[utoipa::path(patch, path = "/todo/items/{id}", tag = "todo", operation_id = "todo_update",
    params(("id" = Uuid, Path)), request_body = TodoPatch,
    responses((status = 200, body = TodoItem), (status = 403, body = ErrorBody),
              (status = 404, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn update_item(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(p): Json<TodoPatch>,
) -> AppResult<Json<TodoItem>> {
    user.require(Permission::TodoUse)?;
    let mut tx = state.db.begin().await?;
    // Parents before the item, the new parent included (see `lock_family`).
    let old = lock_family(&mut tx, &user, id, p.parent_id.filter(|x| *x != id)).await?;
    let mut new = old.clone();

    if let Some(t) = &p.title {
        new.title = clean_title(t)?;
    }
    if let Some(n) = &p.notes {
        new.notes = clean_notes(n)?;
    }
    if p.clear_due_date {
        new.due_date = None;
    } else if p.due_date.is_some() {
        new.due_date = p.due_date;
    }
    if let Some(pos) = p.position {
        new.position = pos;
    }

    // Link: replaced as a whole, or cleared.
    if p.clear_link {
        if p.link_kind.is_some() || p.link_id.is_some() {
            return Err(AppError::Validation(
                "clear_link cannot go with a new link".into(),
            ));
        }
        new.link_kind = None;
        new.link_id = None;
        new.link_label = None;
        new.link_location = None;
    } else if p.link_kind.is_some()
        || p.link_id.is_some()
        || p.link_label.is_some()
        || p.link_location.is_some()
    {
        let link = clean_link(
            &user,
            p.link_kind,
            p.link_id,
            &p.link_label,
            &p.link_location,
        )?
        .ok_or_else(|| AppError::Validation("link_kind and link_id go together".into()))?;
        check_link_target(&mut tx, &user, &link).await?;
        new.link_kind = Some(link.kind.as_str().to_string());
        new.link_id = Some(link.id);
        new.link_label = link.label;
        new.link_location = link.location;
    }

    // Hand-over: owner only, roots only, cascades to the sub-items.
    let mut reassigned = false;
    if p.clear_assignee || p.assignee_id.is_some() {
        if p.clear_assignee && p.assignee_id.is_some() {
            return Err(AppError::Validation(
                "clear_assignee cannot go with an assignee".into(),
            ));
        }
        if old.owner_id != user.user_id {
            return Err(forbidden_not_owner("hand it to someone else"));
        }
        // Whether the item is, or becomes, a sub-item: then it follows its parent.
        let sub_item = if p.make_root {
            false
        } else {
            p.parent_id.is_some() || old.parent_id.is_some()
        };
        if sub_item {
            return Err(AppError::Validation(
                "a sub-item follows the assignee of its parent".into(),
            ));
        }
        new.assignee_id = match p.assignee_id {
            Some(a) if a == user.user_id => None,
            Some(a) => {
                check_assignee(&mut tx, &user, a).await?;
                Some(a)
            }
            None => None,
        };
        reassigned = new.assignee_id != old.assignee_id;
    }

    // Moving between parents.
    let mut new_parent: Option<Raw> = None;
    if p.make_root && p.parent_id.is_some() {
        return Err(AppError::Validation(
            "make_root cannot go with a parent".into(),
        ));
    }
    if p.make_root {
        new.parent_id = None;
        if p.position.is_none() && old.parent_id.is_some() {
            new.position = next_position(&mut tx, &user, old.owner_id, None).await?;
        }
    } else if let Some(parent_id) = p.parent_id {
        if parent_id == id {
            return Err(AppError::Validation(
                "an item cannot be its own parent".into(),
            ));
        }
        if old.parent_id != Some(parent_id) {
            let has_children: bool =
                sqlx::query_scalar("SELECT EXISTS (SELECT 1 FROM todo.items WHERE parent_id = $1)")
                    .bind(id)
                    .fetch_one(&mut *tx)
                    .await?;
            if has_children {
                return Err(AppError::Validation(
                    "an item with sub-items cannot become a sub-item".into(),
                ));
            }
            let parent = lock(&mut tx, &user, parent_id).await?;
            if parent.parent_id.is_some() {
                return Err(AppError::Validation(
                    "sub-items cannot have sub-items".into(),
                ));
            }
            if parent.owner_id != old.owner_id {
                return Err(AppError::Validation(
                    "an item can only move under an item of the same owner".into(),
                ));
            }
            new.parent_id = Some(parent_id);
            // A sub-item follows its parent's hand-over.
            new.assignee_id = parent.assignee_id;
            if p.position.is_none() {
                new.position =
                    next_position(&mut tx, &user, parent.owner_id, Some(parent_id)).await?;
            }
            new_parent = Some(parent);
        }
    }

    sqlx::query(
        "UPDATE todo.items SET title = $2, notes = $3, due_date = $4, position = $5,
                parent_id = $6, assignee_id = $7, link_kind = $8, link_id = $9, link_label = $10,
                link_location = $11, updated_at = now(),
                reminded_at = CASE WHEN due_date IS DISTINCT FROM $4 THEN NULL ELSE reminded_at END
         WHERE id = $1",
    )
    .bind(id)
    .bind(&new.title)
    .bind(&new.notes)
    .bind(new.due_date)
    .bind(new.position)
    .bind(new.parent_id)
    .bind(new.assignee_id)
    .bind(&new.link_kind)
    .bind(new.link_id)
    .bind(&new.link_label)
    .bind(&new.link_location)
    .execute(&mut *tx)
    .await?;
    if reassigned && old.parent_id.is_none() && new.parent_id.is_none() {
        sqlx::query(
            "UPDATE todo.items SET assignee_id = $2, updated_at = now() WHERE parent_id = $1",
        )
        .bind(id)
        .bind(new.assignee_id)
        .execute(&mut *tx)
        .await?;
    }
    if let Some(parent) = &new_parent {
        if !new.done {
            reopen_parent(&mut tx, &user, parent, id).await?;
        }
    }

    let changes = Changes::new()
        .field("due_date", &old.due_date, &new.due_date)
        .field("assignee_id", &old.assignee_id, &new.assignee_id)
        .field("parent_id", &old.parent_id, &new.parent_id)
        .field("position", &old.position, &new.position)
        .field("link_kind", &old.link_kind, &new.link_kind)
        .field("link_id", &old.link_id, &new.link_id);
    let mut text = Vec::new();
    if old.title != new.title {
        text.push("title");
    }
    if old.notes != new.notes {
        text.push("notes");
    }
    if old.link_label != new.link_label {
        text.push("link_label");
    }
    // Only that the location changed, never its value.
    if old.link_location != new.link_location {
        text.push("link_location");
    }
    if !changes.is_empty() || !text.is_empty() {
        audit::record(
            &mut tx,
            &user,
            "todo",
            id,
            "updated",
            changes.into_data_with(serde_json::json!({ "text_changed": text })),
        )
        .await?;
    }
    let item = load(&mut tx, &user, id).await?;
    tx.commit().await?;
    Ok(Json(item))
}

#[utoipa::path(post, path = "/todo/items/{id}/complete", tag = "todo", operation_id = "todo_complete",
    params(("id" = Uuid, Path)), request_body = TodoCompleteInput,
    responses((status = 200, body = TodoItem), (status = 403, body = ErrorBody),
              (status = 404, body = ErrorBody),
              (status = 409, body = ErrorBody, description = "Open sub-items and complete_children is false")))]
async fn complete_item(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    input: Option<Json<TodoCompleteInput>>,
) -> AppResult<Json<TodoItem>> {
    user.require(Permission::TodoUse)?;
    let complete_children = input.is_some_and(|Json(i)| i.complete_children);
    let mut tx = state.db.begin().await?;
    let item = lock(&mut tx, &user, id).await?;
    let open_children: Vec<Uuid> = sqlx::query_scalar(
        "SELECT id FROM todo.items WHERE parent_id = $1 AND NOT done ORDER BY id FOR UPDATE",
    )
    .bind(id)
    .fetch_all(&mut *tx)
    .await?;
    if item.done && open_children.is_empty() {
        let item = load(&mut tx, &user, id).await?;
        return Ok(Json(item));
    }
    if !open_children.is_empty() && !complete_children {
        return Err(AppError::ConflictCode(
            "open_sub_items",
            format!("{} sub-item(s) are still open", open_children.len()),
        ));
    }
    if !open_children.is_empty() {
        sqlx::query(
            "UPDATE todo.items SET done = true, done_at = now(), done_by = $2, updated_at = now()
             WHERE id = ANY($1)",
        )
        .bind(&open_children)
        .bind(user.user_id)
        .execute(&mut *tx)
        .await?;
    }
    if !item.done {
        sqlx::query(
            "UPDATE todo.items SET done = true, done_at = now(), done_by = $2, updated_at = now()
             WHERE id = $1",
        )
        .bind(id)
        .bind(user.user_id)
        .execute(&mut *tx)
        .await?;
    }
    audit::record(
        &mut tx,
        &user,
        "todo",
        id,
        "completed",
        serde_json::json!({ "completed_sub_items": open_children }),
    )
    .await?;
    let item = load(&mut tx, &user, id).await?;
    tx.commit().await?;
    Ok(Json(item))
}

#[utoipa::path(post, path = "/todo/items/{id}/reopen", tag = "todo", operation_id = "todo_reopen",
    params(("id" = Uuid, Path)),
    responses((status = 200, body = TodoItem), (status = 403, body = ErrorBody),
              (status = 404, body = ErrorBody)))]
async fn reopen_item(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<TodoItem>> {
    user.require(Permission::TodoUse)?;
    let mut tx = state.db.begin().await?;
    // Parent first, then child: the same order as completing a parent.
    let probe = lock_family(&mut tx, &user, id, None).await?;
    let parent = match probe.parent_id {
        Some(pid) => Some(lock(&mut tx, &user, pid).await?),
        None => None,
    };
    if probe.done {
        sqlx::query(
            "UPDATE todo.items SET done = false, done_at = NULL, done_by = NULL, updated_at = now()
             WHERE id = $1",
        )
        .bind(id)
        .execute(&mut *tx)
        .await?;
        audit::record(
            &mut tx,
            &user,
            "todo",
            id,
            "reopened",
            serde_json::json!({}),
        )
        .await?;
    }
    if let Some(parent) = &parent {
        reopen_parent(&mut tx, &user, parent, id).await?;
    }
    let item = load(&mut tx, &user, id).await?;
    tx.commit().await?;
    Ok(Json(item))
}

#[utoipa::path(post, path = "/todo/items/reorder", tag = "todo", operation_id = "todo_reorder",
    request_body = TodoReorderInput,
    responses((status = 204), (status = 403, body = ErrorBody), (status = 404, body = ErrorBody),
              (status = 422, body = ErrorBody)))]
async fn reorder(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<TodoReorderInput>,
) -> AppResult<StatusCode> {
    user.require(Permission::TodoUse)?;
    if input.ids.len() > MAX_REORDER {
        return Err(AppError::Validation(format!(
            "at most {MAX_REORDER} items can be reordered at once"
        )));
    }
    let mut distinct = input.ids.clone();
    distinct.sort();
    distinct.dedup();
    if distinct.len() != input.ids.len() {
        return Err(AppError::Validation("an item is listed twice".into()));
    }
    let mut tx = state.db.begin().await?;
    // The parent first, then all its visible children in id order (see `lock_family`).
    if let Some(parent_id) = input.parent_id {
        lock(&mut tx, &user, parent_id).await?;
    }
    let siblings: Vec<(Uuid, i32, DateTime<Utc>)> = sqlx::query_as(
        "SELECT id, position, created_at FROM todo.items
         WHERE company_id = $1 AND (owner_id = $2 OR assignee_id = $2)
           AND parent_id IS NOT DISTINCT FROM $3
         ORDER BY id FOR UPDATE",
    )
    .bind(user.company_id)
    .bind(user.user_id)
    .bind(input.parent_id)
    .fetch_all(&mut *tx)
    .await?;
    for id in &input.ids {
        if !siblings.iter().any(|(s, _, _)| s == id) {
            let elsewhere: bool = sqlx::query_scalar(
                "SELECT EXISTS (SELECT 1 FROM todo.items
                 WHERE id = $3 AND company_id = $1 AND (owner_id = $2 OR assignee_id = $2))",
            )
            .bind(user.company_id)
            .bind(user.user_id)
            .bind(id)
            .fetch_one(&mut *tx)
            .await?;
            return Err(if elsewhere {
                AppError::Validation("the items do not all have the given parent".into())
            } else {
                AppError::NotFound(NOT_FOUND)
            });
        }
    }
    // The full order of the siblings, as lists show it (also settles equal positions). The listed
    // items take the places the listed items hold, in the new order; the others stay where they are.
    let mut full = siblings.clone();
    full.sort_by_key(|r| (r.1, r.2, r.0));
    let mut next = input.ids.iter();
    let new_order: Vec<Uuid> = full
        .iter()
        .map(|(id, _, _)| {
            if input.ids.contains(id) {
                *next.next().unwrap_or(id)
            } else {
                *id
            }
        })
        .collect();
    for (slot, id) in new_order.iter().enumerate() {
        let slot = slot as i32;
        let before = siblings
            .iter()
            .find(|(s, _, _)| s == id)
            .map(|(_, p, _)| *p);
        if before == Some(slot) {
            continue;
        }
        sqlx::query("UPDATE todo.items SET position = $2, updated_at = now() WHERE id = $1")
            .bind(id)
            .bind(slot)
            .execute(&mut *tx)
            .await?;
        audit::record(
            &mut tx,
            &user,
            "todo",
            *id,
            "reordered",
            Changes::new()
                .field("position", &before.unwrap_or(0), &slot)
                .into_data(),
        )
        .await?;
    }
    tx.commit().await?;
    Ok(StatusCode::NO_CONTENT)
}

#[utoipa::path(delete, path = "/todo/items/{id}", tag = "todo", operation_id = "todo_delete",
    params(("id" = Uuid, Path)),
    responses((status = 204), (status = 403, body = ErrorBody), (status = 404, body = ErrorBody)))]
async fn delete_item(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<StatusCode> {
    user.require(Permission::TodoUse)?;
    let mut tx = state.db.begin().await?;
    let item = lock(&mut tx, &user, id).await?;
    if item.owner_id != user.user_id {
        return Err(forbidden_not_owner("delete it"));
    }
    let children: Vec<Uuid> =
        sqlx::query_scalar("SELECT id FROM todo.items WHERE parent_id = $1 ORDER BY id")
            .bind(id)
            .fetch_all(&mut *tx)
            .await?;
    sqlx::query("DELETE FROM todo.items WHERE id = $1")
        .bind(id)
        .execute(&mut *tx)
        .await?;
    audit::record(
        &mut tx,
        &user,
        "todo",
        id,
        "deleted",
        serde_json::json!({ "parent_id": item.parent_id, "deleted_sub_items": children }),
    )
    .await?;
    tx.commit().await?;
    Ok(StatusCode::NO_CONTENT)
}
