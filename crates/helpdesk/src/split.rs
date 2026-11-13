//! Splitting a ticket: some of its messages become a new ticket for the same customer.

use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::Json;
use chrono::{DateTime, Datelike, Utc};
use serde::Deserialize;
use tradocraft_core::{audit, new_id, AppError, AppResult, AppState, CurrentUser, Permission};
use utoipa::ToSchema;
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::tickets::{add_note, load_detail, load_ticket, TicketDetail};

type ErrorBody = tradocraft_core::error::ErrorBody;

#[derive(Debug, Deserialize, ToSchema)]
pub struct SplitInput {
    /// The messages (articles) that move to the new ticket. At least one, and not all of them.
    pub article_ids: Vec<Uuid>,
    /// The subject of the new ticket; default: the subject of the first moved message, else the
    /// subject of this ticket.
    pub subject: Option<String>,
}

/// The subject of the new ticket.
pub fn split_subject(requested: Option<&str>, first_moved: &str, source: &str) -> String {
    [requested.unwrap_or(""), first_moved, source]
        .into_iter()
        .map(str::trim)
        .find(|s| !s.is_empty())
        .unwrap_or("(no subject)")
        .to_string()
}

/// Moves the selected messages, with their attachments, into a new ticket for the same customer
/// and contact. The new ticket starts open with its own service level clock, in the same team and
/// with the same owner; both tickets get a note and an audit event. A split cannot be undone
/// (merge can join tickets again). Returns the new ticket.
#[utoipa::path(post, path = "/tickets/{id}/split", tag = "helpdesk", operation_id = "split_ticket", params(("id" = Uuid, Path)), request_body = SplitInput,
    responses((status = 201, body = TicketDetail), (status = 404, body = ErrorBody), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn split(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<SplitInput>,
) -> AppResult<(StatusCode, Json<TicketDetail>)> {
    user.require(Permission::HelpdeskWrite)?;
    let mut selected = input.article_ids.clone();
    selected.sort();
    selected.dedup();
    if selected.is_empty() {
        return Err(AppError::Validation("select at least one message".into()));
    }
    let mut tx = state.db.begin().await?;
    sqlx::query("SELECT id FROM helpdesk.tickets WHERE id = $1 AND company_id = $2 FOR UPDATE")
        .bind(id)
        .bind(user.company_id)
        .fetch_optional(&mut *tx)
        .await?
        .ok_or(AppError::NotFound("ticket"))?;
    let source = load_ticket(&mut tx, user.company_id, id).await?;
    if source.merged_into_id.is_some() {
        return Err(AppError::Conflict(
            "this ticket was merged into another one and cannot be split".into(),
        ));
    }
    let articles: Vec<(Uuid, String, DateTime<Utc>)> = sqlx::query_as(
        "SELECT id, subject, created_at FROM helpdesk.articles WHERE ticket_id = $1 ORDER BY created_at, id",
    )
    .bind(id)
    .fetch_all(&mut *tx)
    .await?;
    let moved: Vec<&(Uuid, String, DateTime<Utc>)> = articles
        .iter()
        .filter(|a| selected.contains(&a.0))
        .collect();
    if moved.len() != selected.len() {
        return Err(AppError::Validation(
            "a selected message is not part of this ticket".into(),
        ));
    }
    if moved.len() == articles.len() {
        return Err(AppError::Conflict(
            "moving every message would leave this ticket empty; keep at least one".into(),
        ));
    }
    let subject = split_subject(input.subject.as_deref(), &moved[0].1, &source.subject);

    let year = Utc::now().year();
    let n =
        tradocraft_core::numbering::next_number(&mut tx, user.company_id, "ticket", year).await?;
    let number = format!("T{year}-{n:05}");
    let new_id_ = new_id();
    sqlx::query(
        "INSERT INTO helpdesk.tickets (id, company_id, number, subject, status, priority, category, language,
                customer_id, contact_id, contact_name, contact_email, owner_user_id, team_id, internal,
                quotation_id, opportunity_id, order_id, channel, split_from_id, created_by, mailbox_id)
         SELECT $3, company_id, $4, $5, 'open', priority, category, language,
                customer_id, contact_id, contact_name, contact_email, owner_user_id, team_id, internal,
                quotation_id, opportunity_id, order_id, channel, id, $6, mailbox_id
         FROM helpdesk.tickets WHERE id = $1 AND company_id = $2",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(new_id_)
    .bind(&number)
    .bind(&subject)
    .bind(user.user_id)
    .execute(&mut *tx)
    .await?;
    sqlx::query(
        "UPDATE helpdesk.articles SET ticket_id = $2 WHERE ticket_id = $1 AND id = ANY($3)",
    )
    .bind(id)
    .bind(new_id_)
    .bind(&selected)
    .execute(&mut *tx)
    .await?;
    sqlx::query(
        "UPDATE helpdesk.ticket_attachments SET ticket_id = $2 WHERE ticket_id = $1 AND article_id = ANY($3)",
    )
    .bind(id)
    .bind(new_id_)
    .bind(&selected)
    .execute(&mut *tx)
    .await?;
    add_note(
        &mut tx,
        &user,
        new_id_,
        &format!(
            "Split from ticket {} ({} message(s) moved here).",
            source.number,
            selected.len()
        ),
    )
    .await?;
    add_note(
        &mut tx,
        &user,
        id,
        &format!(
            "{} message(s) were moved to the new ticket {number}.",
            selected.len()
        ),
    )
    .await?;
    sqlx::query("UPDATE helpdesk.tickets SET updated_at = now() WHERE id = $1")
        .bind(id)
        .execute(&mut *tx)
        .await?;
    crate::sla::sync(&mut tx, new_id_).await?;
    crate::automation::run(&mut tx, user.company_id, new_id_, "created").await?;
    for (ticket, other) in [(id, &number), (new_id_, &source.number)] {
        audit::record(
            &mut tx,
            &user,
            "ticket",
            ticket,
            "split",
            serde_json::json!({
                "source": source.number, "new": number, "other": other,
                "article_ids": selected,
            }),
        )
        .await?;
    }
    let d = load_detail(&mut tx, user.company_id, new_id_).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(d)))
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new().routes(routes!(split))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_subject_of_the_new_ticket_falls_back_in_order() {
        assert_eq!(split_subject(Some("  Own  "), "Moved", "Source"), "Own");
        assert_eq!(split_subject(Some(" "), "Moved", "Source"), "Moved");
        assert_eq!(split_subject(None, "", "Source"), "Source");
        assert_eq!(split_subject(None, "", ""), "(no subject)");
    }
}
