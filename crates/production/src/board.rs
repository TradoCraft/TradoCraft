//! The work-centre planning board (ADR 0090, C3): what the board shows and a move of one operation
//! that is checked against capacity first. The checks are pure ([`crate::finite`]); this module
//! loads what they need and writes the move through the same path as the unchecked update.

use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use axum::Json;
use chrono::NaiveDate;
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use tradocraft_core::{audit, AppError, AppResult, AppState, CurrentUser, Permission};
use utoipa::{IntoParams, ToSchema};
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::capacity::{
    compute_capacity, earliest_start, overlapping_bookings, spread_bookings,
    ProductionCapacityCentre, ProductionCapacityParams,
};
use crate::finite::{detect, has_errors, Conflict, ConflictKind, MoveCandidate, Severity};
use crate::operations::{
    lock_operation, open_order, write_operation_move, ProductionOperationUpdate,
};
use crate::orders::{load_order, ProductionOrder};
use crate::work_centres::load_calendars;

type ErrorBody = tradocraft_core::error::ErrorBody;

/// An open operation on the board.
#[derive(Debug, Serialize, FromRow, ToSchema)]
pub struct ProductionBoardOperation {
    pub id: Uuid,
    pub production_order_id: Uuid,
    pub order_number: String,
    pub product_name: String,
    pub position: i32,
    pub name: String,
    /// `pending` or `in_progress`.
    pub status: String,
    pub work_centre_id: Uuid,
    pub planned_minutes: i32,
    pub planned_start: NaiveDate,
    pub planned_end: NaiveDate,
    /// When the previous operation of the order ends.
    pub predecessor_end: Option<NaiveDate>,
    /// When the next operation of the order starts.
    pub successor_start: Option<NaiveDate>,
    /// The order's planned-ready date.
    pub planned_ready_date: Option<NaiveDate>,
    /// Planned to end before the period starts: still to do, so it is shown at the start.
    #[sqlx(skip)]
    pub late: bool,
    /// Only a pending operation can be dragged.
    #[sqlx(skip)]
    pub locked: bool,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct ProductionPlanningBoard {
    pub from: NaiveDate,
    pub to: NaiveDate,
    /// Capacity against load per work centre and day, as `GET /production/capacity`.
    pub centres: Vec<ProductionCapacityCentre>,
    /// Open operations of released and in-progress orders on those work centres that start on or
    /// before `to`, in order of start.
    pub operations: Vec<ProductionBoardOperation>,
}

/// What the work-centre board shows: capacity per centre and day and the open operations.
#[utoipa::path(get, path = "/production/planning-board", tag = "production", params(ProductionCapacityParams),
    responses((status = 200, body = ProductionPlanningBoard), (status = 422, body = ErrorBody)))]
async fn production_planning_board(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(p): Query<ProductionCapacityParams>,
) -> AppResult<Json<ProductionPlanningBoard>> {
    user.require(Permission::ProductionRead)?;
    crate::capacity::validate_period(p.from, p.to)?;
    // The capacity and the operations are read in one snapshot, so a move made in between cannot
    // show an operation that the capacity does not count (or the other way round).
    let mut tx = state.db.begin().await?;
    sqlx::query("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY")
        .execute(&mut *tx)
        .await?;
    let capacity = compute_capacity(&mut tx, user.company_id, p.from, p.to, p.division_id).await?;
    let ids: Vec<Uuid> = capacity.centres.iter().map(|c| c.id).collect();
    let mut operations: Vec<ProductionBoardOperation> = sqlx::query_as(
        "SELECT * FROM (
            SELECT o.id, o.production_order_id, po.number AS order_number, p.name AS product_name,
                   o.position, o.name, o.status, o.work_centre_id, o.planned_minutes,
                   o.planned_start, o.planned_end,
                   lag(o.planned_end) OVER w AS predecessor_end,
                   lead(o.planned_start) OVER w AS successor_start,
                   po.planned_ready_date
            FROM production.order_operations o
            JOIN production.production_orders po ON po.id = o.production_order_id
            JOIN products.products p ON p.id = po.product_id
            WHERE o.company_id = $1 AND po.status IN ('released', 'in_progress')
            WINDOW w AS (PARTITION BY o.production_order_id ORDER BY o.position)
         ) x
         WHERE x.status IN ('pending', 'in_progress') AND x.planned_start <= $2
           AND x.work_centre_id = ANY($3)
         ORDER BY x.planned_start, x.order_number, x.position",
    )
    .bind(user.company_id)
    .bind(p.to)
    .bind(&ids)
    .fetch_all(&mut *tx)
    .await?;
    tx.commit().await?;
    for o in &mut operations {
        o.late = o.planned_end < p.from;
        o.locked = o.status != "pending";
    }
    Ok(Json(ProductionPlanningBoard {
        from: capacity.from,
        to: capacity.to,
        centres: capacity.centres,
        operations,
    }))
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct MoveParams {
    /// Only report the conflicts; change nothing (used while dragging).
    #[serde(default)]
    pub dry_run: bool,
    /// Move although there are errors that can be overridden (an overloaded day, a closure, ...).
    #[serde(default)]
    pub force: bool,
}

/// One problem with a move.
#[derive(Debug, Serialize, ToSchema)]
pub struct ProductionMoveConflict {
    /// `inactive_work_centre`, `operation_started`, `on_closure`, `overload`, `before_predecessor`,
    /// `after_successor` or `later_than_ready`.
    pub kind: String,
    /// `error` or `warning`.
    pub severity: String,
    /// The key the app translates, `production.conflict.<kind>`.
    pub message_key: String,
    /// The day concerned, when there is one.
    pub day: Option<NaiveDate>,
}

impl From<&Conflict> for ProductionMoveConflict {
    fn from(c: &Conflict) -> Self {
        let key = c.kind.message_key();
        ProductionMoveConflict {
            kind: key
                .strip_prefix("production.conflict.")
                .unwrap_or(key)
                .to_string(),
            severity: match c.kind.severity() {
                Severity::Error => "error",
                Severity::Warning => "warning",
            }
            .to_string(),
            message_key: key.to_string(),
            day: c.day,
        }
    }
}

#[derive(Debug, Serialize, ToSchema)]
pub struct ProductionOperationMove {
    /// False for a dry run.
    pub applied: bool,
    pub conflicts: Vec<ProductionMoveConflict>,
    /// The production order after the move.
    pub order: Option<ProductionOrder>,
}

/// Moves an operation to another work centre and/or other days, checked against capacity,
/// closures and the order of the operations. Errors among the conflicts refuse the move (409)
/// unless `force=true`; an inactive work centre and an operation that has started are never
/// moved. Warnings never refuse. The conflicts are returned either way; `dry_run` changes
/// nothing. A refused move answers 409 with the same body (`applied: false` and every conflict,
/// warnings included); the other 409s (the order is not open, ...) carry the usual error body.
#[utoipa::path(put, path = "/production-orders/{id}/operations/{operation_id}/move", tag = "production",
    params(("id" = Uuid, Path), ("operation_id" = Uuid, Path), MoveParams), request_body = ProductionOperationUpdate,
    responses((status = 200, body = ProductionOperationMove), (status = 404, body = ErrorBody),
        (status = 409, body = ProductionOperationMove), (status = 422, body = ErrorBody)))]
async fn move_production_operation(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((id, operation_id)): Path<(Uuid, Uuid)>,
    Query(p): Query<MoveParams>,
    Json(input): Json<ProductionOperationUpdate>,
) -> AppResult<Response> {
    user.require(Permission::ProductionWrite)?;
    let mut tx = state.db.begin().await?;
    let po = open_order(&mut tx, &user, id).await?;
    let op = lock_operation(&mut tx, user.company_id, id, operation_id).await?;
    let start = input.planned_start.unwrap_or(op.planned_start);
    let end = input.planned_end.unwrap_or(op.planned_end);
    if end < start {
        return Err(AppError::Validation(
            "an operation cannot end before it starts".into(),
        ));
    }
    let centre = input.work_centre_id.unwrap_or(op.work_centre_id);
    // A real move locks the target work centre (after the order and the operation, always in
    // this order): two moves onto one centre are checked one after the other, and the centre
    // cannot be deactivated before the move is made. A check only reads.
    let active: Option<bool> = if p.dry_run {
        sqlx::query_scalar(
            "SELECT active FROM production.work_centres WHERE id = $1 AND company_id = $2",
        )
    } else {
        sqlx::query_scalar(
            "SELECT active FROM production.work_centres WHERE id = $1 AND company_id = $2
             FOR UPDATE",
        )
    }
    .bind(centre)
    .bind(user.company_id)
    .fetch_optional(&mut *tx)
    .await?;
    let Some(active) = active else {
        return Err(AppError::Validation(
            "the work centre does not exist".into(),
        ));
    };
    let (predecessor_end, successor_start, ready_date): (
        Option<NaiveDate>,
        Option<NaiveDate>,
        Option<NaiveDate>,
    ) = sqlx::query_as(
        "SELECT
            (SELECT planned_end FROM production.order_operations
             WHERE production_order_id = $1 AND company_id = $3 AND position < $2
             ORDER BY position DESC LIMIT 1),
            (SELECT planned_start FROM production.order_operations
             WHERE production_order_id = $1 AND company_id = $3 AND position > $2
             ORDER BY position LIMIT 1),
            (SELECT planned_ready_date FROM production.production_orders
             WHERE id = $1 AND company_id = $3)",
    )
    .bind(id)
    .bind(op.position)
    .bind(user.company_id)
    .fetch_one(&mut *tx)
    .await?;
    // The bookings first: a closure inside a booking's range changes how its minutes are spread,
    // so the calendar reaches back to the earliest booking that overlaps the new dates.
    let bookings =
        overlapping_bookings(&mut tx, user.company_id, centre, operation_id, start, end).await?;
    let mut calendars = load_calendars(
        &mut tx,
        user.company_id,
        &[centre],
        earliest_start(&bookings, start.min(op.planned_start)),
    )
    .await?;
    let cal = calendars
        .remove(&centre)
        .ok_or(AppError::NotFound("work centre"))?;
    let others = spread_bookings(&bookings, &cal);
    let found = detect(
        &MoveCandidate {
            minutes: i64::from(op.planned_minutes),
            start,
            end,
            work_centre_active: active,
            operation_open: op.status == "pending",
            predecessor_end,
            successor_start,
            ready_date,
        },
        &cal,
        &others,
    );
    let report: Vec<ProductionMoveConflict> = found.iter().map(Into::into).collect();
    if p.dry_run {
        return Ok(Json(ProductionOperationMove {
            applied: false,
            conflicts: report,
            order: None,
        })
        .into_response());
    }
    let never = found.iter().any(|c| {
        matches!(
            c.kind,
            ConflictKind::InactiveWorkCentre | ConflictKind::OperationStarted
        )
    });
    if never || (has_errors(&found) && !p.force) {
        // Refused: the whole report, nothing is written (the transaction is dropped).
        return Ok((
            StatusCode::CONFLICT,
            Json(ProductionOperationMove {
                applied: false,
                conflicts: report,
                order: None,
            }),
        )
            .into_response());
    }
    write_operation_move(
        &mut tx,
        &user,
        id,
        &po.number,
        operation_id,
        &op,
        centre,
        start,
        end,
    )
    .await?;
    if has_errors(&found) {
        audit::record(
            &mut tx,
            &user,
            "production_order",
            id,
            "operation_move_forced",
            serde_json::json!({
                "number": po.number, "operation": op.name, "position": op.position,
                "conflicts": report.iter().map(|c| c.message_key.as_str()).collect::<Vec<_>>(),
            }),
        )
        .await?;
    }
    let order = load_order(&mut tx, &user, id).await?;
    tx.commit().await?;
    Ok(Json(ProductionOperationMove {
        applied: true,
        conflicts: report,
        order: Some(order),
    })
    .into_response())
}

/// The planning board routes.
pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(production_planning_board))
        .routes(routes!(move_production_operation))
}
