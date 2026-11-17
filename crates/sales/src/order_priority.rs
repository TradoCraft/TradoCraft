//! Order priority: staff change it with a reason (kept in a history and in the audit log);
//! customers can only ask for a change in the portal, and staff apply or dismiss the request.

use axum::extract::{Path, State};
use axum::Json;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection};
use tradocraft_core::{audit, new_id, AppError, AppResult, AppState, CurrentUser, Permission};
use utoipa::ToSchema;
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::orders::{self, Order};

type ErrorBody = tradocraft_core::error::ErrorBody;

pub const PRIORITIES: [&str; 3] = ["low", "normal", "expedite"];

#[derive(Debug, Deserialize, ToSchema)]
pub struct PriorityInput {
    /// low | normal | expedite
    pub priority: String,
    /// Why the priority changes; required.
    pub reason: String,
    /// The customer request this change answers; it is marked applied.
    pub request_id: Option<Uuid>,
}

#[derive(Debug, Serialize, FromRow, ToSchema)]
pub struct PriorityChange {
    pub id: Uuid,
    pub old_priority: String,
    pub new_priority: String,
    pub reason: String,
    pub changed_by: Uuid,
    pub changed_by_name: String,
    pub changed_at: DateTime<Utc>,
}

#[derive(Debug, Serialize, FromRow, ToSchema)]
pub struct PriorityRequest {
    pub id: Uuid,
    pub order_id: Uuid,
    /// low | expedite
    pub requested_priority: String,
    pub message: String,
    pub requested_by_contact_id: Uuid,
    pub requested_by_name: String,
    /// open | applied | dismissed
    pub status: String,
    pub created_at: DateTime<Utc>,
    pub resolved_at: Option<DateTime<Utc>>,
    pub resolution_note: String,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct DismissRequestInput {
    #[serde(default)]
    pub note: String,
}

const REQUEST_SELECT: &str = "SELECT r.id, r.order_id, r.requested_priority, r.message,
        r.requested_by_contact AS requested_by_contact_id, c.first_name || ' ' || c.last_name AS requested_by_name,
        r.status, r.created_at, r.resolved_at, r.resolution_note
     FROM sales.order_priority_requests r JOIN crm.contacts c ON c.id = r.requested_by_contact";

async fn load_request(
    conn: &mut PgConnection,
    order_id: Uuid,
    id: Uuid,
) -> AppResult<PriorityRequest> {
    sqlx::query_as(&format!(
        "{REQUEST_SELECT} WHERE r.id = $1 AND r.order_id = $2"
    ))
    .bind(id)
    .bind(order_id)
    .fetch_optional(conn)
    .await?
    .ok_or(AppError::NotFound("priority request"))
}

/// Records a customer's request (portal). The caller has checked that the contact may see the order.
pub async fn create_request(
    conn: &mut PgConnection,
    company_id: Uuid,
    order_id: Uuid,
    contact_id: Uuid,
    priority: &str,
    message: &str,
) -> AppResult<PriorityRequest> {
    if !matches!(priority, "low" | "expedite") {
        return Err(AppError::Validation(
            "priority must be expedite or low".into(),
        ));
    }
    if message.trim().is_empty() {
        return Err(AppError::Validation("a message is required".into()));
    }
    let status: String =
        sqlx::query_scalar("SELECT status FROM sales.orders WHERE id = $1 FOR UPDATE")
            .bind(order_id)
            .fetch_one(&mut *conn)
            .await?;
    if matches!(
        status.as_str(),
        "cancelled" | "ready_for_shipping" | "partially_shipped" | "shipped"
    ) {
        return Err(AppError::Conflict(format!(
            "the order is {status}; its priority can no longer change"
        )));
    }
    let id = new_id();
    sqlx::query(
        "INSERT INTO sales.order_priority_requests (id, company_id, order_id, requested_priority, message,
                                                   requested_by_contact)
         VALUES ($1, $2, $3, $4, $5, $6)",
    )
    .bind(id)
    .bind(company_id)
    .bind(order_id)
    .bind(priority)
    .bind(message.trim())
    .bind(contact_id)
    .execute(&mut *conn)
    .await?;
    audit::record_system(
        conn,
        company_id,
        "order",
        order_id,
        "priority_requested",
        serde_json::json!({ "request": id, "priority": priority, "contact": contact_id }),
    )
    .await?;
    load_request(conn, order_id, id).await
}

/// Changes the priority of an order. The reason is required; the change is kept in the history.
#[utoipa::path(put, path = "/orders/{id}/priority", tag = "sales", params(("id" = Uuid, Path)),
    request_body = PriorityInput,
    responses((status = 200, body = Order), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn change_priority(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<PriorityInput>,
) -> AppResult<Json<Order>> {
    user.require(Permission::OrdersWrite)?;
    if !PRIORITIES.contains(&input.priority.as_str()) {
        return Err(AppError::Validation(format!(
            "priority must be one of {}",
            PRIORITIES.join(", ")
        )));
    }
    let reason = input.reason.trim();
    if reason.is_empty() {
        return Err(AppError::Validation(
            "a reason is required to change the priority".into(),
        ));
    }
    let mut tx = state.db.begin().await?;
    let head = orders::lock(&mut tx, user.company_id, id).await?;
    if matches!(
        head.status.as_str(),
        "cancelled" | "ready_for_shipping" | "partially_shipped" | "shipped"
    ) {
        return Err(AppError::Conflict(format!(
            "order {} is {}; its priority can no longer change",
            head.number, head.status
        )));
    }
    let old: String = sqlx::query_scalar("SELECT priority FROM sales.orders WHERE id = $1")
        .bind(id)
        .fetch_one(&mut *tx)
        .await?;
    if old == input.priority {
        return Err(AppError::Validation(format!(
            "the priority is already {old}"
        )));
    }
    if let Some(rid) = input.request_id {
        let applied = sqlx::query(
            "UPDATE sales.order_priority_requests SET status = 'applied', resolved_at = now(), resolved_by = $3,
                    resolution_note = $4
             WHERE id = $1 AND order_id = $2 AND status = 'open'",
        )
        .bind(rid)
        .bind(id)
        .bind(user.user_id)
        .bind(reason)
        .execute(&mut *tx)
        .await?;
        if applied.rows_affected() == 0 {
            return Err(AppError::Conflict(
                "that request does not exist or is already handled".into(),
            ));
        }
    }
    sqlx::query("UPDATE sales.orders SET priority = $2, updated_at = now() WHERE id = $1")
        .bind(id)
        .bind(&input.priority)
        .execute(&mut *tx)
        .await?;
    sqlx::query(
        "INSERT INTO sales.order_priority_history (id, order_id, old_priority, new_priority, reason, changed_by)
         VALUES ($1, $2, $3, $4, $5, $6)",
    )
    .bind(new_id())
    .bind(id)
    .bind(&old)
    .bind(&input.priority)
    .bind(reason)
    .bind(user.user_id)
    .execute(&mut *tx)
    .await?;
    audit::record(
        &mut tx,
        &user,
        "order",
        id,
        "priority_changed",
        serde_json::json!({ "from": old, "to": input.priority, "reason": reason, "request": input.request_id }),
    )
    .await?;
    let order = orders::load_order_locked(&mut tx, user.company_id, id, None).await?;
    tx.commit().await?;
    Ok(Json(order))
}

#[utoipa::path(get, path = "/orders/{id}/priority-history", tag = "sales", params(("id" = Uuid, Path)),
    responses((status = 200, body = Vec<PriorityChange>), (status = 404, body = ErrorBody)))]
async fn priority_history(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<Vec<PriorityChange>>> {
    user.require(Permission::OrdersRead)?;
    let exists: bool = sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM sales.orders WHERE id = $1 AND company_id = $2)",
    )
    .bind(id)
    .bind(user.company_id)
    .fetch_one(&state.db)
    .await?;
    if !exists {
        return Err(AppError::NotFound("order"));
    }
    Ok(Json(
        sqlx::query_as(
            "SELECT h.id, h.old_priority, h.new_priority, h.reason, h.changed_by, u.display_name AS changed_by_name,
                    h.changed_at
             FROM sales.order_priority_history h JOIN core.users u ON u.id = h.changed_by
             WHERE h.order_id = $1 ORDER BY h.changed_at, h.id",
        )
        .bind(id)
        .fetch_all(&state.db)
        .await?,
    ))
}

/// Customer requests to change the priority, newest first.
#[utoipa::path(get, path = "/orders/{id}/priority-requests", tag = "sales", params(("id" = Uuid, Path)),
    responses((status = 200, body = Vec<PriorityRequest>), (status = 404, body = ErrorBody)))]
async fn list_requests(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<Vec<PriorityRequest>>> {
    user.require(Permission::OrdersRead)?;
    Ok(Json(
        sqlx::query_as(&format!(
            "{REQUEST_SELECT} JOIN sales.orders o ON o.id = r.order_id
             WHERE r.order_id = $1 AND o.company_id = $2 ORDER BY r.created_at DESC, r.id"
        ))
        .bind(id)
        .bind(user.company_id)
        .fetch_all(&state.db)
        .await?,
    ))
}

/// Turns a customer request down without changing the priority.
#[utoipa::path(post, path = "/orders/{id}/priority-requests/{request_id}/dismiss", tag = "sales",
    params(("id" = Uuid, Path), ("request_id" = Uuid, Path)), request_body = DismissRequestInput,
    responses((status = 200, body = PriorityRequest), (status = 404, body = ErrorBody), (status = 409, body = ErrorBody)))]
async fn dismiss_request(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((id, request_id)): Path<(Uuid, Uuid)>,
    Json(input): Json<DismissRequestInput>,
) -> AppResult<Json<PriorityRequest>> {
    user.require(Permission::OrdersWrite)?;
    let mut tx = state.db.begin().await?;
    orders::lock(&mut tx, user.company_id, id).await?;
    let done = sqlx::query(
        "UPDATE sales.order_priority_requests SET status = 'dismissed', resolved_at = now(), resolved_by = $3,
                resolution_note = $4
         WHERE id = $1 AND order_id = $2 AND status = 'open'",
    )
    .bind(request_id)
    .bind(id)
    .bind(user.user_id)
    .bind(input.note.trim())
    .execute(&mut *tx)
    .await?;
    if done.rows_affected() == 0 {
        // Either unknown (404) or already handled (409).
        load_request(&mut tx, id, request_id).await?;
        return Err(AppError::Conflict("that request is already handled".into()));
    }
    audit::record(
        &mut tx,
        &user,
        "order",
        id,
        "priority_request_dismissed",
        serde_json::json!({ "request": request_id, "note": input.note.trim() }),
    )
    .await?;
    let r = load_request(&mut tx, id, request_id).await?;
    tx.commit().await?;
    Ok(Json(r))
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(change_priority))
        .routes(routes!(priority_history))
        .routes(routes!(list_requests))
        .routes(routes!(dismiss_request))
}
