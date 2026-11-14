//! Operations of a production order (ADR 0063): the routing as it was at release, scheduled on
//! the work centres' calendars, started and finished on the shop floor with the total minutes
//! worked, and closed when the order is completed. Labour is a completion total per operation
//! and who finished it, not time entries per person.

use axum::extract::{Path, State};
use axum::Json;
use chrono::{DateTime, NaiveDate, Utc};
use rust_decimal::prelude::ToPrimitive;
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection};
use tradocraft_core::{audit, new_id, AppError, AppResult, AppState, CurrentUser, Permission};
use utoipa::ToSchema;
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::orders::{begin_order, load_order, lock_order, Locked, ProductionOrder};
use crate::routing::load_routing;
use crate::schedule::{schedule_forward, Calendar, OpSpec};
use crate::work_centres::load_calendars;

type ErrorBody = tradocraft_core::error::ErrorBody;

/// Most minutes that can be recorded for one operation (about two years of working days).
pub const MAX_MINUTES: i32 = 1_000_000;

/// One operation of a production order.
#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct ProductionOperation {
    pub id: Uuid,
    pub position: i32,
    pub name: String,
    pub work_centre_id: Uuid,
    pub work_centre_code: String,
    pub work_centre_name: String,
    pub setup_minutes: i32,
    #[schema(value_type = String, example = "2.5")]
    pub run_minutes_per_unit: Decimal,
    /// Setup plus run time for the quantity of the order, rounded up to whole minutes.
    pub planned_minutes: i32,
    pub planned_start: NaiveDate,
    pub planned_end: NaiveDate,
    /// pending | in_progress | done | skipped
    pub status: String,
    pub started_at: Option<DateTime<Utc>>,
    pub completed_at: Option<DateTime<Utc>>,
    /// Who finished (or, at completion of the order, closed) the operation.
    pub completed_by: Option<Uuid>,
    pub completed_by_name: Option<String>,
    /// Total minutes worked, recorded when the operation is finished.
    pub actual_minutes: Option<i32>,
    /// Cost of an hour at the work centre when the order was released or the operation moved.
    /// Only for users with the cost permission.
    #[schema(value_type = Option<String>, example = "45")]
    pub cost_rate: Option<Decimal>,
    pub notes: String,
}

impl ProductionOperation {
    /// Not finished: it still has work to do and counts in the load of its work centre.
    pub fn is_open(&self) -> bool {
        matches!(self.status.as_str(), "pending" | "in_progress")
    }
}

const SELECT: &str =
    "SELECT o.id, o.position, o.name, o.work_centre_id, w.code AS work_centre_code,
        w.name AS work_centre_name, o.setup_minutes, o.run_minutes_per_unit, o.planned_minutes,
        o.planned_start, o.planned_end, o.status, o.started_at, o.completed_at, o.completed_by,
        u.display_name AS completed_by_name, o.actual_minutes, o.cost_rate, o.notes
     FROM production.order_operations o
     JOIN production.work_centres w ON w.id = o.work_centre_id
     LEFT JOIN core.users u ON u.id = o.completed_by";

/// The operations of a production order in order. The cost rate is left out for users without
/// the cost permission.
pub(crate) async fn load_operations(
    conn: &mut PgConnection,
    user: &CurrentUser,
    production_order_id: Uuid,
) -> AppResult<Vec<ProductionOperation>> {
    let mut ops: Vec<ProductionOperation> = sqlx::query_as(&format!(
        "{SELECT} WHERE o.production_order_id = $1 AND o.company_id = $2 ORDER BY o.position"
    ))
    .bind(production_order_id)
    .bind(user.company_id)
    .fetch_all(conn)
    .await?;
    if !user.can(Permission::InventoryCost) {
        for o in &mut ops {
            o.cost_rate = None;
        }
    }
    Ok(ops)
}

/// Minutes an operation takes for a quantity: setup plus run time per unit times the quantity,
/// rounded up. `None` when that does not fit the column (a typo in the routing, not a real job).
pub(crate) fn planned_minutes(
    setup_minutes: i32,
    run_minutes_per_unit: Decimal,
    quantity: Decimal,
) -> Option<i32> {
    Decimal::from(setup_minutes)
        .checked_add(run_minutes_per_unit.checked_mul(quantity)?)?
        .ceil()
        .to_i64()
        .and_then(|m| i32::try_from(m).ok())
        .filter(|m| *m >= 0)
}

/// Copies the routing of the frozen BOM revision onto a production order as operations, with the
/// planned minutes for its quantity and the work centres' current rates, and schedules them
/// forward from `start`. Does nothing when the revision has no routing. Returns how many.
pub(crate) async fn snapshot_routing(
    conn: &mut PgConnection,
    user: &CurrentUser,
    production_order_id: Uuid,
    bom_id: Uuid,
    quantity: Decimal,
    start: NaiveDate,
) -> AppResult<usize> {
    let routing = load_routing(conn, user.company_id, bom_id).await?;
    if routing.is_empty() {
        return Ok(0);
    }
    let ids: Vec<Uuid> = routing.iter().map(|r| r.work_centre_id).collect();
    let rates: Vec<(Uuid, Option<Decimal>)> = sqlx::query_as(
        "SELECT id, cost_per_hour FROM production.work_centres WHERE company_id = $1 AND id = ANY($2)",
    )
    .bind(user.company_id)
    .bind(&ids)
    .fetch_all(&mut *conn)
    .await?;
    for r in &routing {
        let minutes = planned_minutes(r.setup_minutes, r.run_minutes_per_unit, quantity)
            .filter(|m| *m <= MAX_MINUTES)
            .ok_or_else(|| {
                AppError::Validation(format!(
                    "operation \"{}\" takes too long for this quantity; check its run time",
                    r.name
                ))
            })?;
        let rate = rates
            .iter()
            .find(|(id, _)| *id == r.work_centre_id)
            .and_then(|(_, rate)| *rate);
        sqlx::query(
            "INSERT INTO production.order_operations
                 (id, company_id, production_order_id, position, name, work_centre_id, setup_minutes,
                  run_minutes_per_unit, planned_minutes, planned_start, planned_end, cost_rate, notes)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $10, $11, $12)",
        )
        .bind(new_id())
        .bind(user.company_id)
        .bind(production_order_id)
        .bind(r.position)
        .bind(&r.name)
        .bind(r.work_centre_id)
        .bind(r.setup_minutes)
        .bind(r.run_minutes_per_unit)
        .bind(minutes)
        .bind(start)
        .bind(rate)
        .bind(&r.notes)
        .execute(&mut *conn)
        .await?;
    }
    place_pending(conn, user.company_id, production_order_id, start).await?;
    Ok(routing.len())
}

#[derive(FromRow)]
struct Pending {
    id: Uuid,
    name: String,
    work_centre_id: Uuid,
    planned_minutes: i32,
}

/// The day after `d` (`d` itself at the end of the calendar).
pub(crate) fn day_after(d: NaiveDate) -> NaiveDate {
    d.succ_opt().unwrap_or(d)
}

/// (Re)schedules the operations that are still pending, one after the other from `start`. An
/// operation that is already running holds the work until its planned end.
pub(crate) async fn place_pending(
    conn: &mut PgConnection,
    company_id: Uuid,
    production_order_id: Uuid,
    start: NaiveDate,
) -> AppResult<usize> {
    let pending: Vec<Pending> = sqlx::query_as(
        "SELECT id, name, work_centre_id, planned_minutes FROM production.order_operations
         WHERE production_order_id = $1 AND company_id = $2 AND status = 'pending' ORDER BY position",
    )
    .bind(production_order_id)
    .bind(company_id)
    .fetch_all(&mut *conn)
    .await?;
    if pending.is_empty() {
        return Ok(0);
    }
    let running_until: Option<NaiveDate> = sqlx::query_scalar(
        "SELECT max(planned_end) FROM production.order_operations
         WHERE production_order_id = $1 AND company_id = $2 AND status = 'in_progress'",
    )
    .bind(production_order_id)
    .bind(company_id)
    .fetch_one(&mut *conn)
    .await?;
    // The planned end of a running operation is the last day it works, and how much of that day
    // it uses is not known here, so the next work conservatively starts the day after.
    let from = running_until.map_or(start, |d| start.max(day_after(d)));
    let mut centres: Vec<Uuid> = pending.iter().map(|p| p.work_centre_id).collect();
    centres.sort();
    centres.dedup();
    let mut by_id = load_calendars(conn, company_id, &centres, from).await?;
    let calendars: Vec<Calendar> = centres
        .iter()
        .map(|c| by_id.remove(c).ok_or(AppError::NotFound("work centre")))
        .collect::<AppResult<_>>()?;
    let specs: Vec<OpSpec> = pending
        .iter()
        .map(|p| OpSpec {
            minutes: i64::from(p.planned_minutes),
            calendar: centres
                .iter()
                .position(|c| *c == p.work_centre_id)
                .expect("the work centre was collected from this list"),
        })
        .collect();
    let placed = schedule_forward(&specs, &calendars, from).map_err(|e| {
        AppError::Validation(format!(
            "operation \"{}\": its work centre has no working time in the next two years; check its hours and closures",
            pending[e.op].name
        ))
    })?;
    for (p, at) in pending.iter().zip(placed) {
        sqlx::query(
            "UPDATE production.order_operations SET planned_start = $2, planned_end = $3 WHERE id = $1",
        )
        .bind(p.id)
        .bind(at.start)
        .bind(at.end)
        .execute(&mut *conn)
        .await?;
    }
    Ok(pending.len())
}

/// The operation of a production order, locked until the transaction ends.
#[derive(Debug, FromRow)]
struct OpRow {
    name: String,
    position: i32,
    status: String,
    planned_minutes: i32,
    work_centre_id: Uuid,
    planned_start: NaiveDate,
    planned_end: NaiveDate,
}

async fn lock_operation(
    conn: &mut PgConnection,
    company_id: Uuid,
    production_order_id: Uuid,
    id: Uuid,
) -> AppResult<OpRow> {
    sqlx::query_as(
        "SELECT name, position, status, planned_minutes, work_centre_id, planned_start, planned_end
         FROM production.order_operations
         WHERE id = $1 AND production_order_id = $2 AND company_id = $3 FOR UPDATE",
    )
    .bind(id)
    .bind(production_order_id)
    .bind(company_id)
    .fetch_optional(conn)
    .await?
    .ok_or(AppError::NotFound("operation"))
}

/// Locks the production order and checks that it is still open (operations are only worked on
/// while the order is released or in progress).
async fn open_order(conn: &mut PgConnection, user: &CurrentUser, id: Uuid) -> AppResult<Locked> {
    let po = lock_order(conn, user.company_id, id).await?;
    if !matches!(po.status.as_str(), "released" | "in_progress") {
        return Err(AppError::Conflict(format!(
            "production order {} is {}; its operations can no longer be changed",
            po.number, po.status
        )));
    }
    Ok(po)
}

fn wrong_status(op: &OpRow, wanted: &str) -> AppError {
    AppError::Conflict(format!(
        "operation \"{}\" is {}; {wanted}",
        op.name, op.status
    ))
}

/// Starts an operation. Starting the first one starts the production order.
#[utoipa::path(post, path = "/production-orders/{id}/operations/{operation_id}/start", tag = "production",
    params(("id" = Uuid, Path), ("operation_id" = Uuid, Path)),
    responses((status = 200, body = ProductionOrder), (status = 404, body = ErrorBody), (status = 409, body = ErrorBody)))]
async fn start_production_operation(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((id, operation_id)): Path<(Uuid, Uuid)>,
) -> AppResult<Json<ProductionOrder>> {
    user.require(Permission::ProductionRun)?;
    let mut tx = state.db.begin().await?;
    let po = open_order(&mut tx, &user, id).await?;
    let op = lock_operation(&mut tx, user.company_id, id, operation_id).await?;
    if op.status != "pending" {
        return Err(wrong_status(&op, "only a pending operation can be started"));
    }
    sqlx::query(
        "UPDATE production.order_operations SET status = 'in_progress', started_at = now() WHERE id = $1",
    )
    .bind(operation_id)
    .execute(&mut *tx)
    .await?;
    if po.status == "released" {
        begin_order(&mut tx, &user, id, &po).await?;
    }
    audit::record(
        &mut tx,
        &user,
        "production_order",
        id,
        "operation_started",
        serde_json::json!({ "number": po.number, "operation": op.name, "position": op.position }),
    )
    .await?;
    let out = load_order(&mut tx, &user, id).await?;
    tx.commit().await?;
    Ok(Json(out))
}

/// Records that an operation is finished and how many minutes it took.
#[derive(Debug, Deserialize, ToSchema)]
pub struct ProductionOperationFinish {
    /// Total minutes worked on the operation; defaults to the planned minutes.
    pub actual_minutes: Option<i32>,
    /// Added to the notes of the operation.
    #[serde(default)]
    pub note: String,
}

/// Finishes an operation (also one that was never started: it is started and finished at once).
#[utoipa::path(post, path = "/production-orders/{id}/operations/{operation_id}/finish", tag = "production",
    params(("id" = Uuid, Path), ("operation_id" = Uuid, Path)), request_body = ProductionOperationFinish,
    responses((status = 200, body = ProductionOrder), (status = 404, body = ErrorBody), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn finish_production_operation(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((id, operation_id)): Path<(Uuid, Uuid)>,
    Json(input): Json<ProductionOperationFinish>,
) -> AppResult<Json<ProductionOrder>> {
    user.require(Permission::ProductionRun)?;
    if input
        .actual_minutes
        .is_some_and(|m| !(0..=MAX_MINUTES).contains(&m))
    {
        return Err(AppError::Validation(format!(
            "the minutes must be between 0 and {MAX_MINUTES}"
        )));
    }
    let mut tx = state.db.begin().await?;
    let po = open_order(&mut tx, &user, id).await?;
    let op = lock_operation(&mut tx, user.company_id, id, operation_id).await?;
    if !matches!(op.status.as_str(), "pending" | "in_progress") {
        return Err(wrong_status(
            &op,
            "only an operation that is not finished can be finished",
        ));
    }
    let actual = input.actual_minutes.unwrap_or(op.planned_minutes);
    sqlx::query(
        "UPDATE production.order_operations
         SET status = 'done', started_at = COALESCE(started_at, now()), completed_at = now(),
             completed_by = $2, actual_minutes = $3,
             notes = CASE WHEN $4 = '' THEN notes ELSE concat_ws(E'\\n', NULLIF(notes, ''), $4) END
         WHERE id = $1",
    )
    .bind(operation_id)
    .bind(user.user_id)
    .bind(actual)
    .bind(input.note.trim())
    .execute(&mut *tx)
    .await?;
    if po.status == "released" {
        begin_order(&mut tx, &user, id, &po).await?;
    }
    audit::record(
        &mut tx,
        &user,
        "production_order",
        id,
        "operation_finished",
        serde_json::json!({
            "number": po.number, "operation": op.name, "position": op.position,
            "planned_minutes": op.planned_minutes, "actual_minutes": actual,
        }),
    )
    .await?;
    let out = load_order(&mut tx, &user, id).await?;
    tx.commit().await?;
    Ok(Json(out))
}

/// Takes back the finish (or skip) of an operation, for a mistake.
#[utoipa::path(post, path = "/production-orders/{id}/operations/{operation_id}/reopen", tag = "production",
    params(("id" = Uuid, Path), ("operation_id" = Uuid, Path)),
    responses((status = 200, body = ProductionOrder), (status = 404, body = ErrorBody), (status = 409, body = ErrorBody)))]
async fn reopen_production_operation(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((id, operation_id)): Path<(Uuid, Uuid)>,
) -> AppResult<Json<ProductionOrder>> {
    user.require(Permission::ProductionRun)?;
    let mut tx = state.db.begin().await?;
    let po = open_order(&mut tx, &user, id).await?;
    let op = lock_operation(&mut tx, user.company_id, id, operation_id).await?;
    if !matches!(op.status.as_str(), "done" | "skipped") {
        return Err(wrong_status(
            &op,
            "only a finished or skipped operation can be reopened",
        ));
    }
    // A finished one was worked on, so it goes back to work; a skipped one never was.
    sqlx::query(
        "UPDATE production.order_operations
         SET status = CASE WHEN status = 'done' THEN 'in_progress' ELSE 'pending' END,
             completed_at = NULL, completed_by = NULL, actual_minutes = NULL
         WHERE id = $1",
    )
    .bind(operation_id)
    .execute(&mut *tx)
    .await?;
    audit::record(
        &mut tx,
        &user,
        "production_order",
        id,
        "operation_reopened",
        serde_json::json!({ "number": po.number, "operation": op.name, "position": op.position }),
    )
    .await?;
    let out = load_order(&mut tx, &user, id).await?;
    tx.commit().await?;
    Ok(Json(out))
}

/// What a planner may change on an operation that is not finished. What is left out stays.
#[derive(Debug, Deserialize, ToSchema)]
pub struct ProductionOperationUpdate {
    /// Move the operation to another (active) work centre; its cost rate is taken again.
    pub work_centre_id: Option<Uuid>,
    #[serde(default, deserialize_with = "tradocraft_core::serde_util::opt_date")]
    pub planned_start: Option<NaiveDate>,
    #[serde(default, deserialize_with = "tradocraft_core::serde_util::opt_date")]
    pub planned_end: Option<NaiveDate>,
}

/// Moves an operation to another work centre and/or other dates.
#[utoipa::path(put, path = "/production-orders/{id}/operations/{operation_id}", tag = "production",
    params(("id" = Uuid, Path), ("operation_id" = Uuid, Path)), request_body = ProductionOperationUpdate,
    responses((status = 200, body = ProductionOrder), (status = 404, body = ErrorBody), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn update_production_operation(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((id, operation_id)): Path<(Uuid, Uuid)>,
    Json(input): Json<ProductionOperationUpdate>,
) -> AppResult<Json<ProductionOrder>> {
    user.require(Permission::ProductionWrite)?;
    let mut tx = state.db.begin().await?;
    let po = open_order(&mut tx, &user, id).await?;
    let op = lock_operation(&mut tx, user.company_id, id, operation_id).await?;
    if !matches!(op.status.as_str(), "pending" | "in_progress") {
        return Err(wrong_status(&op, "only an open operation can be changed"));
    }
    let start = input.planned_start.unwrap_or(op.planned_start);
    let end = input.planned_end.unwrap_or(op.planned_end);
    if end < start {
        return Err(AppError::Validation(
            "an operation cannot end before it starts".into(),
        ));
    }
    let centre = input.work_centre_id.unwrap_or(op.work_centre_id);
    let moved = centre != op.work_centre_id;
    if moved {
        let found: Option<(bool, Option<Decimal>)> = sqlx::query_as(
            "SELECT active, cost_per_hour FROM production.work_centres WHERE id = $1 AND company_id = $2",
        )
        .bind(centre)
        .bind(user.company_id)
        .fetch_optional(&mut *tx)
        .await?;
        match found {
            None => {
                return Err(AppError::Validation(
                    "the work centre does not exist".into(),
                ))
            }
            Some((false, _)) => {
                return Err(AppError::Validation("the work centre is not active".into()))
            }
            Some((true, rate)) => {
                sqlx::query("UPDATE production.order_operations SET cost_rate = $2 WHERE id = $1")
                    .bind(operation_id)
                    .bind(rate)
                    .execute(&mut *tx)
                    .await?;
            }
        }
    }
    sqlx::query(
        "UPDATE production.order_operations
         SET work_centre_id = $2, planned_start = $3, planned_end = $4 WHERE id = $1",
    )
    .bind(operation_id)
    .bind(centre)
    .bind(start)
    .bind(end)
    .execute(&mut *tx)
    .await?;
    audit::record(
        &mut tx,
        &user,
        "production_order",
        id,
        "operation_updated",
        serde_json::json!({
            "number": po.number, "operation": op.name, "position": op.position,
            "work_centre_id": centre, "planned_start": start, "planned_end": end,
        }),
    )
    .await?;
    let out = load_order(&mut tx, &user, id).await?;
    tx.commit().await?;
    Ok(Json(out))
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct ProductionScheduleInput {
    /// The first day work can start; defaults to today.
    #[serde(default, deserialize_with = "tradocraft_core::serde_util::opt_date")]
    pub start_date: Option<NaiveDate>,
}

/// Schedules the operations that have not started again from a date, one after the other on the
/// work centres' calendars. The planned-ready date of the order is not changed: the planner
/// sets it, with `scheduled_end` as the suggestion.
#[utoipa::path(post, path = "/production-orders/{id}/schedule", tag = "production",
    params(("id" = Uuid, Path)), request_body = ProductionScheduleInput,
    responses((status = 200, body = ProductionOrder), (status = 404, body = ErrorBody), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn schedule_production_order(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<ProductionScheduleInput>,
) -> AppResult<Json<ProductionOrder>> {
    user.require(Permission::ProductionWrite)?;
    let mut tx = state.db.begin().await?;
    let po = open_order(&mut tx, &user, id).await?;
    let mut start = input.start_date.unwrap_or_else(tradocraft_core::today);
    // Work on this order starts the day after the last of its open subassembly orders is ready.
    let children_end: Option<NaiveDate> = sqlx::query_scalar(
        "SELECT max(x.planned_end) FROM production.order_operations x
         JOIN production.production_orders c ON c.id = x.production_order_id
         WHERE c.parent_order_id = $1 AND c.company_id = $2
           AND x.status IN ('pending', 'in_progress')",
    )
    .bind(id)
    .bind(user.company_id)
    .fetch_one(&mut *tx)
    .await?;
    if let Some(end) = children_end {
        start = start.max(day_after(end));
    }
    let placed = place_pending(&mut tx, user.company_id, id, start).await?;
    audit::record(
        &mut tx,
        &user,
        "production_order",
        id,
        "scheduled",
        serde_json::json!({ "number": po.number, "start_date": start, "operations": placed }),
    )
    .await?;
    let out = load_order(&mut tx, &user, id).await?;
    tx.commit().await?;
    Ok(Json(out))
}

/// The minutes worked on one operation, given when the order is completed.
#[derive(Debug, Deserialize, ToSchema)]
pub struct ProductionOperationActual {
    pub operation_id: Uuid,
    /// Total minutes worked; defaults to the planned minutes.
    pub actual_minutes: Option<i32>,
}

/// Checks the operations named at completion: they belong to the order, once each, with minutes
/// in range.
pub(crate) async fn check_actuals(
    conn: &mut PgConnection,
    company_id: Uuid,
    production_order_id: Uuid,
    actuals: &[ProductionOperationActual],
) -> AppResult<()> {
    let mut seen = std::collections::HashSet::new();
    for a in actuals {
        if !seen.insert(a.operation_id) {
            return Err(AppError::Validation(
                "an operation is named twice".to_string(),
            ));
        }
        if a.actual_minutes
            .is_some_and(|m| !(0..=MAX_MINUTES).contains(&m))
        {
            return Err(AppError::Validation(format!(
                "the minutes must be between 0 and {MAX_MINUTES}"
            )));
        }
        let known: bool = sqlx::query_scalar(
            "SELECT EXISTS (SELECT 1 FROM production.order_operations
             WHERE id = $1 AND production_order_id = $2 AND company_id = $3)",
        )
        .bind(a.operation_id)
        .bind(production_order_id)
        .bind(company_id)
        .fetch_one(&mut *conn)
        .await?;
        if !known {
            return Err(AppError::Validation(
                "an operation does not belong to this production order".into(),
            ));
        }
    }
    Ok(())
}

/// Closes the operations of an order that is completed: the ones named are finished with their
/// minutes, every other open one is skipped (nothing is recorded for it). Operations that are
/// already finished stay as they are. Returns (finished, skipped).
pub(crate) async fn close_operations(
    conn: &mut PgConnection,
    user: &CurrentUser,
    production_order_id: Uuid,
    actuals: &[ProductionOperationActual],
) -> AppResult<(u64, u64)> {
    let mut done = 0;
    for a in actuals {
        done += sqlx::query(
            "UPDATE production.order_operations
             SET status = 'done', started_at = COALESCE(started_at, now()), completed_at = now(),
                 completed_by = $3, actual_minutes = COALESCE($4, planned_minutes)
             WHERE id = $1 AND production_order_id = $2 AND status IN ('pending', 'in_progress')",
        )
        .bind(a.operation_id)
        .bind(production_order_id)
        .bind(user.user_id)
        .bind(a.actual_minutes)
        .execute(&mut *conn)
        .await?
        .rows_affected();
    }
    let skipped = sqlx::query(
        "UPDATE production.order_operations
         SET status = 'skipped', completed_at = now(), completed_by = $2
         WHERE production_order_id = $1 AND status IN ('pending', 'in_progress')",
    )
    .bind(production_order_id)
    .bind(user.user_id)
    .execute(conn)
    .await?
    .rows_affected();
    Ok((done, skipped))
}

/// The operation routes.
pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(start_production_operation))
        .routes(routes!(finish_production_operation))
        .routes(routes!(reopen_production_operation))
        .routes(routes!(update_production_operation))
        .routes(routes!(schedule_production_order))
}

#[cfg(test)]
mod tests {
    use super::*;
    use rust_decimal_macros::dec;

    #[test]
    fn planned_minutes_are_setup_plus_run_rounded_up() {
        assert_eq!(planned_minutes(30, dec!(10), dec!(5)), Some(80));
        assert_eq!(
            planned_minutes(15, dec!(1.5), dec!(5)),
            Some(23),
            "22.5 rounds up"
        );
        assert_eq!(
            planned_minutes(0, dec!(0.0001), dec!(1)),
            Some(1),
            "a sliver still takes a minute"
        );
        assert_eq!(planned_minutes(0, dec!(0), dec!(100)), Some(0));
        assert_eq!(
            planned_minutes(10, dec!(2), dec!(0.25)),
            Some(11),
            "10.5 rounds up"
        );
    }

    #[test]
    fn planned_minutes_multiplication_overflow_is_refused_not_a_panic() {
        assert_eq!(planned_minutes(0, Decimal::MAX, dec!(2)), None);
        assert_eq!(planned_minutes(1, Decimal::MAX, Decimal::MAX), None);
        assert_eq!(planned_minutes(i32::MAX, Decimal::MAX, dec!(1)), None);
    }

    #[test]
    fn day_after_steps_one_day_and_saturates_at_the_end() {
        let d = NaiveDate::from_ymd_opt(2026, 2, 28).unwrap();
        assert_eq!(day_after(d), NaiveDate::from_ymd_opt(2026, 3, 1).unwrap());
        assert_eq!(day_after(NaiveDate::MAX), NaiveDate::MAX);
        let start = NaiveDate::from_ymd_opt(2026, 3, 1).unwrap();
        assert_eq!(start.max(day_after(d)), start, "a later start is kept");
        assert_eq!(
            NaiveDate::from_ymd_opt(2026, 2, 1)
                .unwrap()
                .max(day_after(d)),
            start,
            "an earlier start is raised to the day after"
        );
    }

    #[test]
    fn planned_minutes_that_do_not_fit_are_refused() {
        assert_eq!(planned_minutes(0, dec!(99999999), dec!(99999999)), None);
        assert_eq!(planned_minutes(i32::MAX, dec!(1), dec!(1)), None);
    }
}
