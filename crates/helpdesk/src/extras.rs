//! Tags, time entries and merging of tickets.

use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::Json;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection};
use tradocraft_core::{audit, new_id, AppError, AppResult, AppState, CurrentUser, Permission};
use utoipa::ToSchema;
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::tickets::{add_note, load_detail, load_ticket, TicketDetail};

type ErrorBody = tradocraft_core::error::ErrorBody;

// ---------------------------------------------------------------------------------------------
// Tags
// ---------------------------------------------------------------------------------------------

/// A tag as stored: trimmed, lower case, inner whitespace collapsed, at most 40 characters, no
/// commas or control characters.
pub fn normalize_tag(raw: &str) -> AppResult<String> {
    let tag = raw
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
        .to_lowercase();
    if tag.is_empty() {
        return Err(AppError::Validation("a tag cannot be empty".into()));
    }
    if tag.chars().count() > 40 {
        return Err(AppError::Validation(
            "a tag is at most 40 characters".into(),
        ));
    }
    if tag.chars().any(|c| c.is_control() || c == ',') {
        return Err(AppError::Validation(
            "a tag cannot contain commas or control characters".into(),
        ));
    }
    Ok(tag)
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct TagInput {
    pub tag: String,
}

#[derive(Debug, Serialize, FromRow, ToSchema)]
pub struct TagCount {
    pub tag: String,
    pub count: i64,
}

/// All tags in use at this company, for filters and suggestions.
#[utoipa::path(get, path = "/helpdesk/tags", tag = "helpdesk", responses((status = 200, body = Vec<TagCount>)))]
async fn list_tags(
    State(state): State<AppState>,
    user: CurrentUser,
) -> AppResult<Json<Vec<TagCount>>> {
    user.require(Permission::HelpdeskRead)?;
    Ok(Json(
        sqlx::query_as(
            "SELECT g.tag, count(*) AS count FROM helpdesk.ticket_tags g
             JOIN helpdesk.tickets t ON t.id = g.ticket_id WHERE t.company_id = $1
             GROUP BY g.tag ORDER BY g.tag",
        )
        .bind(user.company_id)
        .fetch_all(&state.db)
        .await?,
    ))
}

#[utoipa::path(post, path = "/tickets/{id}/tags", tag = "helpdesk", params(("id" = Uuid, Path)), request_body = TagInput,
    responses((status = 200, body = TicketDetail), (status = 404, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn add_tag(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<TagInput>,
) -> AppResult<Json<TicketDetail>> {
    user.require(Permission::HelpdeskWrite)?;
    let tag = normalize_tag(&input.tag)?;
    let mut tx = state.db.begin().await?;
    load_ticket(&mut tx, user.company_id, id).await?;
    let added = sqlx::query(
        "INSERT INTO helpdesk.ticket_tags (ticket_id, tag) VALUES ($1, $2) ON CONFLICT DO NOTHING",
    )
    .bind(id)
    .bind(&tag)
    .execute(&mut *tx)
    .await?;
    if added.rows_affected() > 0 {
        crate::collab::record_event(
            &mut tx,
            user.company_id,
            id,
            "tag_added",
            Some(user.user_id),
            crate::collab::EventData {
                to_value: Some(tag.clone()),
                ..Default::default()
            },
        )
        .await?;
        audit::record(
            &mut tx,
            &user,
            "ticket",
            id,
            "tag_added",
            serde_json::json!({ "tag": tag }),
        )
        .await?;
    }
    let d = load_detail(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    crate::tickets::notify_change(&state, &user, id, "tag", Some(tag.clone())).await;
    Ok(Json(d))
}

#[utoipa::path(delete, path = "/tickets/{id}/tags/{tag}", tag = "helpdesk", params(("id" = Uuid, Path), ("tag" = String, Path)),
    responses((status = 200, body = TicketDetail), (status = 404, body = ErrorBody)))]
async fn remove_tag(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((id, tag)): Path<(Uuid, String)>,
) -> AppResult<Json<TicketDetail>> {
    user.require(Permission::HelpdeskWrite)?;
    let tag = normalize_tag(&tag)?;
    let mut tx = state.db.begin().await?;
    load_ticket(&mut tx, user.company_id, id).await?;
    let removed = sqlx::query("DELETE FROM helpdesk.ticket_tags WHERE ticket_id = $1 AND tag = $2")
        .bind(id)
        .bind(&tag)
        .execute(&mut *tx)
        .await?;
    if removed.rows_affected() > 0 {
        crate::collab::record_event(
            &mut tx,
            user.company_id,
            id,
            "tag_removed",
            Some(user.user_id),
            crate::collab::EventData {
                to_value: Some(tag.clone()),
                ..Default::default()
            },
        )
        .await?;
        audit::record(
            &mut tx,
            &user,
            "ticket",
            id,
            "tag_removed",
            serde_json::json!({ "tag": tag }),
        )
        .await?;
    }
    let d = load_detail(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    crate::tickets::notify_change(&state, &user, id, "tag", Some(tag.clone())).await;
    Ok(Json(d))
}

// ---------------------------------------------------------------------------------------------
// Time entries
// ---------------------------------------------------------------------------------------------

#[derive(Debug, Serialize, FromRow, ToSchema)]
pub struct TimeEntry {
    pub id: Uuid,
    pub user_id: Uuid,
    pub user_name: String,
    pub minutes: i32,
    pub note: String,
    pub billable: bool,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct TimeEntries {
    pub items: Vec<TimeEntry>,
    pub total_minutes: i64,
    pub billable_minutes: i64,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct TimeEntryInput {
    /// 1 to 1440.
    pub minutes: i32,
    #[serde(default)]
    pub note: String,
    #[serde(default)]
    pub billable: bool,
}

async fn load_time(conn: &mut PgConnection, ticket_id: Uuid) -> AppResult<TimeEntries> {
    let items: Vec<TimeEntry> = sqlx::query_as(
        "SELECT e.id, e.user_id, u.display_name AS user_name, e.minutes, e.note, e.billable, e.created_at
         FROM helpdesk.time_entries e JOIN core.users u ON u.id = e.user_id
         WHERE e.ticket_id = $1 ORDER BY e.created_at, e.id",
    )
    .bind(ticket_id)
    .fetch_all(conn)
    .await?;
    let total_minutes = items.iter().map(|e| i64::from(e.minutes)).sum();
    let billable_minutes = items
        .iter()
        .filter(|e| e.billable)
        .map(|e| i64::from(e.minutes))
        .sum();
    Ok(TimeEntries {
        items,
        total_minutes,
        billable_minutes,
    })
}

#[utoipa::path(get, path = "/tickets/{id}/time-entries", tag = "helpdesk", params(("id" = Uuid, Path)),
    responses((status = 200, body = TimeEntries), (status = 404, body = ErrorBody)))]
async fn list_time(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<TimeEntries>> {
    user.require(Permission::HelpdeskRead)?;
    let mut conn = state.db.acquire().await?;
    load_ticket(&mut conn, user.company_id, id).await?;
    Ok(Json(load_time(&mut conn, id).await?))
}

#[utoipa::path(post, path = "/tickets/{id}/time-entries", tag = "helpdesk", params(("id" = Uuid, Path)), request_body = TimeEntryInput,
    responses((status = 201, body = TimeEntries), (status = 404, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn add_time(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<TimeEntryInput>,
) -> AppResult<(StatusCode, Json<TimeEntries>)> {
    user.require(Permission::HelpdeskWrite)?;
    if !(1..=1440).contains(&input.minutes) {
        return Err(AppError::Validation(
            "minutes must be between 1 and 1440".into(),
        ));
    }
    let mut tx = state.db.begin().await?;
    load_ticket(&mut tx, user.company_id, id).await?;
    let entry = new_id();
    sqlx::query(
        "INSERT INTO helpdesk.time_entries (id, ticket_id, user_id, minutes, note, billable)
         VALUES ($1, $2, $3, $4, $5, $6)",
    )
    .bind(entry)
    .bind(id)
    .bind(user.user_id)
    .bind(input.minutes)
    .bind(input.note.trim())
    .bind(input.billable)
    .execute(&mut *tx)
    .await?;
    audit::record(
        &mut tx,
        &user,
        "ticket",
        id,
        "time_logged",
        serde_json::json!({ "entry_id": entry, "minutes": input.minutes, "billable": input.billable }),
    )
    .await?;
    let t = load_time(&mut tx, id).await?;
    tx.commit().await?;
    crate::tickets::notify_change(&state, &user, id, "time", None).await;
    Ok((StatusCode::CREATED, Json(t)))
}

/// Removes an entry: one's own, or any with the helpdesk admin permission.
#[utoipa::path(delete, path = "/tickets/{id}/time-entries/{entry_id}", tag = "helpdesk",
    params(("id" = Uuid, Path), ("entry_id" = Uuid, Path)),
    responses((status = 200, body = TimeEntries), (status = 403, body = ErrorBody), (status = 404, body = ErrorBody)))]
async fn delete_time(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((id, entry_id)): Path<(Uuid, Uuid)>,
) -> AppResult<Json<TimeEntries>> {
    user.require(Permission::HelpdeskWrite)?;
    let mut tx = state.db.begin().await?;
    load_ticket(&mut tx, user.company_id, id).await?;
    let owner: Uuid = sqlx::query_scalar(
        "SELECT user_id FROM helpdesk.time_entries WHERE id = $1 AND ticket_id = $2",
    )
    .bind(entry_id)
    .bind(id)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or(AppError::NotFound("time entry"))?;
    if owner != user.user_id {
        user.require(Permission::HelpdeskAdmin)?;
    }
    sqlx::query("DELETE FROM helpdesk.time_entries WHERE id = $1")
        .bind(entry_id)
        .execute(&mut *tx)
        .await?;
    audit::record(
        &mut tx,
        &user,
        "ticket",
        id,
        "time_removed",
        serde_json::json!({ "entry_id": entry_id }),
    )
    .await?;
    let t = load_time(&mut tx, id).await?;
    tx.commit().await?;
    crate::tickets::notify_change(&state, &user, id, "time", None).await;
    Ok(Json(t))
}

// ---------------------------------------------------------------------------------------------
// Merge
// ---------------------------------------------------------------------------------------------

#[derive(Debug, Deserialize, ToSchema)]
pub struct MergeInput {
    /// The ticket that stays and receives everything.
    pub target_id: Uuid,
}

/// Merges this ticket into another ticket of the same customer. Articles (with their
/// attachments), tags and time entries move to the target; this ticket is closed with a note
/// and points at the target. A merge cannot be undone. Returns the target.
#[utoipa::path(post, path = "/tickets/{id}/merge", tag = "helpdesk", params(("id" = Uuid, Path)), request_body = MergeInput,
    responses((status = 200, body = TicketDetail), (status = 404, body = ErrorBody), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn merge(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<MergeInput>,
) -> AppResult<Json<TicketDetail>> {
    user.require(Permission::HelpdeskWrite)?;
    let target_id = input.target_id;
    if target_id == id {
        return Err(AppError::Validation(
            "a ticket cannot be merged into itself".into(),
        ));
    }
    let mut tx = state.db.begin().await?;
    // Lock both in a fixed order so two merges cannot deadlock.
    sqlx::query("SELECT id FROM helpdesk.tickets WHERE id = ANY($1) ORDER BY id FOR UPDATE")
        .bind([id, target_id])
        .fetch_all(&mut *tx)
        .await?;
    let source = load_ticket(&mut tx, user.company_id, id).await?;
    let target = load_ticket(&mut tx, user.company_id, target_id).await?;
    match (source.customer_id, target.customer_id) {
        (Some(a), Some(b)) if a == b => {}
        _ => {
            return Err(AppError::Validation(
                "only tickets of the same customer can be merged".into(),
            ))
        }
    }
    if source.merged_into_id.is_some() {
        return Err(AppError::Conflict("this ticket was already merged".into()));
    }
    if target.merged_into_id.is_some() || target.status == "closed" {
        return Err(AppError::Conflict(
            "the target ticket is closed or was merged away".into(),
        ));
    }
    for table in ["articles", "ticket_attachments", "time_entries"] {
        sqlx::query(&format!(
            "UPDATE helpdesk.{table} SET ticket_id = $2 WHERE ticket_id = $1"
        ))
        .bind(id)
        .bind(target_id)
        .execute(&mut *tx)
        .await?;
    }
    sqlx::query(
        "INSERT INTO helpdesk.ticket_tags (ticket_id, tag, created_at)
         SELECT $2, tag, created_at FROM helpdesk.ticket_tags WHERE ticket_id = $1
         ON CONFLICT DO NOTHING",
    )
    .bind(id)
    .bind(target_id)
    .execute(&mut *tx)
    .await?;
    sqlx::query("DELETE FROM helpdesk.ticket_tags WHERE ticket_id = $1")
        .bind(id)
        .execute(&mut *tx)
        .await?;
    // The earliest response of either ticket counts for the one that remains.
    sqlx::query(
        "UPDATE helpdesk.tickets SET first_response_at = LEAST(first_response_at, $2), updated_at = now()
         WHERE id = $1",
    )
    .bind(target_id)
    .bind(source.first_response_at)
    .execute(&mut *tx)
    .await?;
    sqlx::query(
        "UPDATE helpdesk.tickets SET status = 'closed', closed_at = coalesce(closed_at, now()),
                merged_into_id = $2, updated_at = now()
         WHERE id = $1",
    )
    .bind(id)
    .bind(target_id)
    .execute(&mut *tx)
    .await?;
    add_note(
        &mut tx,
        &user,
        id,
        &format!("Merged into ticket {}.", target.number),
    )
    .await?;
    add_note(
        &mut tx,
        &user,
        target_id,
        &format!("Ticket {} was merged into this ticket.", source.number),
    )
    .await?;
    crate::sla::sync(&mut tx, id).await?;
    crate::sla::sync(&mut tx, target_id).await?;
    for (ticket, from, to) in [
        (id, None, Some(target.number.clone())),
        (target_id, Some(source.number.clone()), None),
    ] {
        crate::collab::record_event(
            &mut tx,
            user.company_id,
            ticket,
            "merged",
            Some(user.user_id),
            crate::collab::EventData {
                from_value: from,
                to_value: to,
                ..Default::default()
            },
        )
        .await?;
    }
    for (ticket, other) in [(id, &target.number), (target_id, &source.number)] {
        audit::record(
            &mut tx,
            &user,
            "ticket",
            ticket,
            "merged",
            serde_json::json!({ "source": source.number, "target": target.number, "other": other }),
        )
        .await?;
    }
    let d = load_detail(&mut tx, user.company_id, target_id).await?;
    tx.commit().await?;
    crate::tickets::notify_change(&state, &user, id, "merge", None).await;
    crate::tickets::notify_change(&state, &user, target_id, "merge", None).await;
    Ok(Json(d))
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(list_tags))
        .routes(routes!(add_tag))
        .routes(routes!(remove_tag))
        .routes(routes!(list_time, add_time))
        .routes(routes!(delete_time))
        .routes(routes!(merge))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tags_are_normalised_and_bounded() {
        assert_eq!(
            normalize_tag("  Warranty  Claim ").unwrap(),
            "warranty claim"
        );
        assert!(normalize_tag("   ").is_err());
        assert!(normalize_tag("a,b").is_err());
        assert!(normalize_tag(&"x".repeat(41)).is_err());
        assert!(normalize_tag(&"x".repeat(40)).is_ok());
    }
}
