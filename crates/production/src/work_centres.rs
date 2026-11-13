//! Work centres: the machines, benches and crews operations run on, with their opening hours and
//! closures (ADR 0060). The administrator keeps work centres and hours (`production.admin`, like
//! divisions); planners enter closures such as maintenance and holidays (`production.write`).

use std::collections::HashMap;

use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::Json;
use chrono::{NaiveDate, NaiveTime};
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection};
use tradocraft_core::{audit, new_id, AppError, AppResult, AppState, CurrentUser, Permission};
use utoipa::{IntoParams, ToSchema};
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::orders::check_division;
use crate::schedule::{Calendar, HoursBlock};

type ErrorBody = tradocraft_core::error::ErrorBody;

/// A block of working time of a work centre.
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct WorkCentreHoursSlot {
    /// 1 (Monday) to 7 (Sunday).
    pub weekday: i16,
    pub start_time: NaiveTime,
    pub end_time: NaiveTime,
}

/// A work centre with its own opening hours.
#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct WorkCentre {
    pub id: Uuid,
    pub code: String,
    pub name: String,
    pub division_id: Option<Uuid>,
    pub division_name: Option<String>,
    /// Parallel units (machines or crews) the work centre offers at once.
    pub capacity: i32,
    /// Cost of one hour of work in the company currency. Only for users with the cost permission.
    #[schema(value_type = Option<String>, example = "45")]
    pub cost_per_hour: Option<Decimal>,
    pub active: bool,
    pub sort_order: i32,
    pub notes: String,
    /// Operations of production orders that are not finished.
    pub open_operations: i64,
    /// Own opening hours. None: the default week (Monday to Friday 08:00-12:00 and 13:00-17:00).
    #[sqlx(skip)]
    pub hours: Vec<WorkCentreHoursSlot>,
}

/// Input to create or change a work centre.
#[derive(Debug, Deserialize, ToSchema)]
pub struct WorkCentreInput {
    pub code: String,
    pub name: String,
    pub division_id: Option<Uuid>,
    #[serde(default = "one")]
    pub capacity: i32,
    /// Ignored (the stored rate stays) for users without the cost permission.
    #[serde(default)]
    #[schema(value_type = Option<String>, example = "45")]
    pub cost_per_hour: Option<Decimal>,
    #[serde(default = "yes")]
    pub active: bool,
    #[serde(default)]
    pub sort_order: i32,
    #[serde(default)]
    pub notes: String,
}

fn one() -> i32 {
    1
}

fn yes() -> bool {
    true
}

impl WorkCentreInput {
    fn check(&self) -> AppResult<()> {
        if self.code.trim().is_empty() || self.name.trim().is_empty() {
            return Err(AppError::Validation("code and name are required".into()));
        }
        if !(1..=1000).contains(&self.capacity) {
            return Err(AppError::Validation(
                "capacity must be between 1 and 1000".into(),
            ));
        }
        if let Some(rate) = self.cost_per_hour {
            if rate < Decimal::ZERO || rate.round_dp(4) != rate {
                return Err(AppError::Validation(
                    "the cost per hour must be 0 or more, with at most 4 decimals".into(),
                ));
            }
        }
        Ok(())
    }
}

/// Replaces the opening hours of a work centre.
#[derive(Debug, Deserialize, ToSchema)]
pub struct WorkCentreHoursInput {
    /// All blocks; none means the default week applies again.
    pub slots: Vec<WorkCentreHoursSlot>,
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct WorkCentreListParams {
    /// Only active (true) or only inactive (false) work centres.
    pub active: Option<bool>,
    pub division_id: Option<Uuid>,
}

const SELECT: &str = "SELECT w.id, w.code, w.name, w.division_id, d.name AS division_name, w.capacity,
        w.cost_per_hour, w.active, w.sort_order, w.notes,
        (SELECT count(*) FROM production.order_operations o
          WHERE o.work_centre_id = w.id AND o.status IN ('pending', 'in_progress')) AS open_operations
     FROM production.work_centres w
     LEFT JOIN production.divisions d ON d.id = w.division_id";

/// Loads work centres of the company (all matching, or only one) with their hours. The cost is
/// left out for users without the cost permission.
async fn load_all(
    conn: &mut PgConnection,
    user: &CurrentUser,
    only: Option<Uuid>,
    active: Option<bool>,
    division_id: Option<Uuid>,
) -> AppResult<Vec<WorkCentre>> {
    let mut rows: Vec<WorkCentre> = sqlx::query_as(&format!(
        "{SELECT} WHERE w.company_id = $1 AND ($2::uuid IS NULL OR w.id = $2)
           AND ($3::bool IS NULL OR w.active = $3) AND ($4::uuid IS NULL OR w.division_id = $4)
         ORDER BY w.sort_order, w.code"
    ))
    .bind(user.company_id)
    .bind(only)
    .bind(active)
    .bind(division_id)
    .fetch_all(&mut *conn)
    .await?;
    let ids: Vec<Uuid> = rows.iter().map(|r| r.id).collect();
    let hours: Vec<(Uuid, i16, NaiveTime, NaiveTime)> = sqlx::query_as(
        "SELECT work_centre_id, weekday, start_time, end_time FROM production.work_centre_hours
         WHERE work_centre_id = ANY($1) ORDER BY weekday, start_time",
    )
    .bind(&ids)
    .fetch_all(conn)
    .await?;
    let can_cost = user.can(Permission::InventoryCost);
    for r in &mut rows {
        r.hours = hours
            .iter()
            .filter(|(w, ..)| *w == r.id)
            .map(|(_, weekday, start_time, end_time)| WorkCentreHoursSlot {
                weekday: *weekday,
                start_time: *start_time,
                end_time: *end_time,
            })
            .collect();
        if !can_cost {
            r.cost_per_hour = None;
        }
    }
    Ok(rows)
}

/// The work centre as the user may see it, or 404.
async fn load_one(conn: &mut PgConnection, user: &CurrentUser, id: Uuid) -> AppResult<WorkCentre> {
    load_all(conn, user, Some(id), None, None)
        .await?
        .into_iter()
        .next()
        .ok_or(AppError::NotFound("work centre"))
}

/// Calendars of work centres of the company for scheduling: their hours (the default week when
/// none), the closures that end on or after `from`, whole-plant closures included, and their
/// capacity. Ids that are not work centres of the company are absent from the result.
// Used by the operations (ADR 0060, order operations) as they land.
#[allow(dead_code)]
pub(crate) async fn load_calendars(
    conn: &mut PgConnection,
    company_id: Uuid,
    ids: &[Uuid],
    from: NaiveDate,
) -> AppResult<HashMap<Uuid, Calendar>> {
    let centres: Vec<(Uuid, i32)> = sqlx::query_as(
        "SELECT id, capacity FROM production.work_centres WHERE company_id = $1 AND id = ANY($2)",
    )
    .bind(company_id)
    .bind(ids)
    .fetch_all(&mut *conn)
    .await?;
    let found: Vec<Uuid> = centres.iter().map(|(id, _)| *id).collect();
    let hours: Vec<(Uuid, i16, NaiveTime, NaiveTime)> = sqlx::query_as(
        "SELECT work_centre_id, weekday, start_time, end_time FROM production.work_centre_hours
         WHERE work_centre_id = ANY($1)",
    )
    .bind(&found)
    .fetch_all(&mut *conn)
    .await?;
    let closures: Vec<(Option<Uuid>, NaiveDate, NaiveDate)> = sqlx::query_as(
        "SELECT work_centre_id, from_date, to_date FROM production.work_centre_closures
         WHERE company_id = $1 AND to_date >= $2 AND (work_centre_id IS NULL OR work_centre_id = ANY($3))",
    )
    .bind(company_id)
    .bind(from)
    .bind(&found)
    .fetch_all(conn)
    .await?;
    Ok(centres
        .into_iter()
        .map(|(id, capacity)| {
            let blocks = hours
                .iter()
                .filter(|(w, ..)| *w == id)
                .map(|(_, weekday, start, end)| HoursBlock {
                    weekday: *weekday,
                    start: *start,
                    end: *end,
                })
                .collect();
            let own = closures
                .iter()
                .filter(|(w, ..)| w.is_none() || *w == Some(id))
                .map(|(_, f, t)| (*f, *t))
                .collect();
            (id, Calendar::new(blocks, own, capacity))
        })
        .collect())
}

/// The work centres of the company, in their sort order.
#[utoipa::path(get, path = "/production/work-centres", tag = "production", params(WorkCentreListParams),
    responses((status = 200, body = Vec<WorkCentre>)))]
async fn list_work_centres(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(p): Query<WorkCentreListParams>,
) -> AppResult<Json<Vec<WorkCentre>>> {
    user.require(Permission::ProductionRead)?;
    let mut conn = state.db.acquire().await?;
    Ok(Json(
        load_all(&mut conn, &user, None, p.active, p.division_id).await?,
    ))
}

/// Adds a work centre.
#[utoipa::path(post, path = "/production/work-centres", tag = "production", request_body = WorkCentreInput,
    responses((status = 201, body = WorkCentre), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn create_work_centre(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<WorkCentreInput>,
) -> AppResult<(StatusCode, Json<WorkCentre>)> {
    user.require(Permission::ProductionAdmin)?;
    input.check()?;
    let mut tx = state.db.begin().await?;
    if let Some(d) = input.division_id {
        check_division(&mut tx, user.company_id, d).await?;
    }
    let rate = input
        .cost_per_hour
        .filter(|_| user.can(Permission::InventoryCost));
    let id = new_id();
    sqlx::query(
        "INSERT INTO production.work_centres
             (id, company_id, code, name, division_id, capacity, cost_per_hour, active, sort_order, notes)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(input.code.trim())
    .bind(input.name.trim())
    .bind(input.division_id)
    .bind(input.capacity)
    .bind(rate)
    .bind(input.active)
    .bind(input.sort_order)
    .bind(input.notes.trim())
    .execute(&mut *tx)
    .await?;
    audit::record(
        &mut tx,
        &user,
        "production_work_centre",
        id,
        "created",
        serde_json::json!({
            "code": input.code.trim(), "name": input.name.trim(), "capacity": input.capacity,
            "division_id": input.division_id,
        }),
    )
    .await?;
    let out = load_one(&mut tx, &user, id).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(out)))
}

/// Changes a work centre. Deactivating one hides it from new routings; existing routings and
/// operations keep it.
#[utoipa::path(put, path = "/production/work-centres/{id}", tag = "production", params(("id" = Uuid, Path)),
    request_body = WorkCentreInput,
    responses((status = 200, body = WorkCentre), (status = 404, body = ErrorBody), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn update_work_centre(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<WorkCentreInput>,
) -> AppResult<Json<WorkCentre>> {
    user.require(Permission::ProductionAdmin)?;
    input.check()?;
    let mut tx = state.db.begin().await?;
    let current: Option<Option<Uuid>> = sqlx::query_scalar(
        "SELECT division_id FROM production.work_centres WHERE id = $1 AND company_id = $2 FOR UPDATE",
    )
    .bind(id)
    .bind(user.company_id)
    .fetch_optional(&mut *tx)
    .await?;
    let current = current.ok_or(AppError::NotFound("work centre"))?;
    // Keeping the division it already has is fine even when it was deactivated since.
    if let Some(d) = input.division_id.filter(|d| Some(*d) != current) {
        check_division(&mut tx, user.company_id, d).await?;
    }
    sqlx::query(
        "UPDATE production.work_centres
         SET code = $3, name = $4, division_id = $5, capacity = $6,
             cost_per_hour = CASE WHEN $7 THEN $8 ELSE cost_per_hour END,
             active = $9, sort_order = $10, notes = $11
         WHERE id = $1 AND company_id = $2",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(input.code.trim())
    .bind(input.name.trim())
    .bind(input.division_id)
    .bind(input.capacity)
    .bind(user.can(Permission::InventoryCost))
    .bind(input.cost_per_hour)
    .bind(input.active)
    .bind(input.sort_order)
    .bind(input.notes.trim())
    .execute(&mut *tx)
    .await?;
    audit::record(
        &mut tx,
        &user,
        "production_work_centre",
        id,
        "updated",
        serde_json::json!({
            "code": input.code.trim(), "capacity": input.capacity, "active": input.active,
            "division_id": input.division_id,
        }),
    )
    .await?;
    let out = load_one(&mut tx, &user, id).await?;
    tx.commit().await?;
    Ok(Json(out))
}

/// Removes a work centre that nothing uses. One that routings or operations refer to is refused
/// with 409 Conflict: deactivate it instead.
#[utoipa::path(delete, path = "/production/work-centres/{id}", tag = "production", params(("id" = Uuid, Path)),
    responses((status = 204), (status = 404, body = ErrorBody), (status = 409, body = ErrorBody)))]
async fn delete_work_centre(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<StatusCode> {
    user.require(Permission::ProductionAdmin)?;
    let mut tx = state.db.begin().await?;
    let done = sqlx::query("DELETE FROM production.work_centres WHERE id = $1 AND company_id = $2")
        .bind(id)
        .bind(user.company_id)
        .execute(&mut *tx)
        .await
        .map_err(|e| match &e {
            sqlx::Error::Database(d)
                if d.code().as_deref() == Some("23503")
                    && matches!(d.table(), Some("routing_operations" | "order_operations")) =>
            {
                AppError::Conflict(
                    "this work centre is used by routings or operations; deactivate it instead"
                        .into(),
                )
            }
            _ => AppError::from(e),
        })?;
    if done.rows_affected() == 0 {
        return Err(AppError::NotFound("work centre"));
    }
    audit::record(
        &mut tx,
        &user,
        "production_work_centre",
        id,
        "deleted",
        serde_json::json!({}),
    )
    .await?;
    tx.commit().await?;
    Ok(StatusCode::NO_CONTENT)
}

/// Replaces the opening hours of a work centre. No blocks: the default week applies again.
#[utoipa::path(put, path = "/production/work-centres/{id}/hours", tag = "production", params(("id" = Uuid, Path)),
    request_body = WorkCentreHoursInput,
    responses((status = 200, body = WorkCentre), (status = 404, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn set_work_centre_hours(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<WorkCentreHoursInput>,
) -> AppResult<Json<WorkCentre>> {
    user.require(Permission::ProductionAdmin)?;
    let mut slots = input.slots.clone();
    slots.sort_by_key(|s| (s.weekday, s.start_time));
    for s in &slots {
        if !(1..=7).contains(&s.weekday) {
            return Err(AppError::Validation(
                "the weekday must be 1 (Monday) to 7 (Sunday)".into(),
            ));
        }
        if s.end_time <= s.start_time {
            return Err(AppError::Validation(
                "a block must end after it starts".into(),
            ));
        }
    }
    if slots
        .windows(2)
        .any(|w| w[0].weekday == w[1].weekday && w[1].start_time < w[0].end_time)
    {
        return Err(AppError::Validation(
            "blocks on the same day must not overlap".into(),
        ));
    }
    let mut tx = state.db.begin().await?;
    let exists: Option<Uuid> = sqlx::query_scalar(
        "SELECT id FROM production.work_centres WHERE id = $1 AND company_id = $2 FOR UPDATE",
    )
    .bind(id)
    .bind(user.company_id)
    .fetch_optional(&mut *tx)
    .await?;
    exists.ok_or(AppError::NotFound("work centre"))?;
    sqlx::query("DELETE FROM production.work_centre_hours WHERE work_centre_id = $1")
        .bind(id)
        .execute(&mut *tx)
        .await?;
    for s in &slots {
        sqlx::query(
            "INSERT INTO production.work_centre_hours (company_id, work_centre_id, weekday, start_time, end_time)
             VALUES ($1, $2, $3, $4, $5)",
        )
        .bind(user.company_id)
        .bind(id)
        .bind(s.weekday)
        .bind(s.start_time)
        .bind(s.end_time)
        .execute(&mut *tx)
        .await?;
    }
    audit::record(
        &mut tx,
        &user,
        "production_work_centre",
        id,
        "hours_set",
        serde_json::json!({ "blocks": slots.len() }),
    )
    .await?;
    let out = load_one(&mut tx, &user, id).await?;
    tx.commit().await?;
    Ok(Json(out))
}

/// A period in which a work centre (or the whole plant) does not work.
#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct WorkCentreClosure {
    pub id: Uuid,
    /// Empty: the whole plant is closed (a holiday).
    pub work_centre_id: Option<Uuid>,
    pub work_centre_code: Option<String>,
    pub from_date: NaiveDate,
    pub to_date: NaiveDate,
    /// maintenance | holiday | other
    pub kind: String,
    pub note: String,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct WorkCentreClosureInput {
    /// Leave empty to close the whole plant.
    pub work_centre_id: Option<Uuid>,
    #[serde(deserialize_with = "tradocraft_core::serde_util::date")]
    pub from_date: NaiveDate,
    /// Inclusive.
    #[serde(deserialize_with = "tradocraft_core::serde_util::date")]
    pub to_date: NaiveDate,
    /// maintenance | holiday | other
    #[serde(default = "other")]
    pub kind: String,
    #[serde(default)]
    pub note: String,
}

fn other() -> String {
    "other".into()
}

impl WorkCentreClosureInput {
    fn check(&self) -> AppResult<()> {
        if self.to_date < self.from_date {
            return Err(AppError::Validation(
                "the closure must end on or after the day it starts".into(),
            ));
        }
        if !matches!(self.kind.as_str(), "maintenance" | "holiday" | "other") {
            return Err(AppError::Validation(
                "kind must be maintenance, holiday or other".into(),
            ));
        }
        Ok(())
    }
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct WorkCentreClosureParams {
    /// This work centre's closures and the whole-plant ones.
    pub work_centre_id: Option<Uuid>,
    /// Only closures that end on or after this day.
    #[serde(default, deserialize_with = "tradocraft_core::serde_util::opt_date")]
    pub from: Option<NaiveDate>,
    /// Only closures that start on or before this day.
    #[serde(default, deserialize_with = "tradocraft_core::serde_util::opt_date")]
    pub to: Option<NaiveDate>,
}

const SELECT_CLOSURE: &str =
    "SELECT c.id, c.work_centre_id, w.code AS work_centre_code, c.from_date,
        c.to_date, c.kind, c.note
     FROM production.work_centre_closures c
     LEFT JOIN production.work_centres w ON w.id = c.work_centre_id";

async fn load_closure(
    conn: &mut PgConnection,
    company_id: Uuid,
    id: Uuid,
) -> AppResult<WorkCentreClosure> {
    sqlx::query_as(&format!(
        "{SELECT_CLOSURE} WHERE c.id = $1 AND c.company_id = $2"
    ))
    .bind(id)
    .bind(company_id)
    .fetch_optional(conn)
    .await?
    .ok_or(AppError::NotFound("closure"))
}

/// Checks that the work centre of a closure belongs to the company.
async fn check_closure_centre(
    conn: &mut PgConnection,
    company_id: Uuid,
    work_centre_id: Option<Uuid>,
) -> AppResult<()> {
    let Some(w) = work_centre_id else {
        return Ok(());
    };
    let ok: bool = sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM production.work_centres WHERE id = $1 AND company_id = $2)",
    )
    .bind(w)
    .bind(company_id)
    .fetch_one(conn)
    .await?;
    if ok {
        Ok(())
    } else {
        Err(AppError::Validation(
            "the work centre does not exist".into(),
        ))
    }
}

/// Closures, earliest first.
#[utoipa::path(get, path = "/production/closures", tag = "production", params(WorkCentreClosureParams),
    responses((status = 200, body = Vec<WorkCentreClosure>)))]
async fn list_work_centre_closures(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(p): Query<WorkCentreClosureParams>,
) -> AppResult<Json<Vec<WorkCentreClosure>>> {
    user.require(Permission::ProductionRead)?;
    Ok(Json(
        sqlx::query_as(&format!(
            "{SELECT_CLOSURE} WHERE c.company_id = $1
               AND ($2::uuid IS NULL OR c.work_centre_id IS NULL OR c.work_centre_id = $2)
               AND ($3::date IS NULL OR c.to_date >= $3) AND ($4::date IS NULL OR c.from_date <= $4)
             ORDER BY c.from_date, c.id LIMIT 500"
        ))
        .bind(user.company_id)
        .bind(p.work_centre_id)
        .bind(p.from)
        .bind(p.to)
        .fetch_all(&state.db)
        .await?,
    ))
}

/// Adds a closure.
#[utoipa::path(post, path = "/production/closures", tag = "production", request_body = WorkCentreClosureInput,
    responses((status = 201, body = WorkCentreClosure), (status = 422, body = ErrorBody)))]
async fn create_work_centre_closure(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<WorkCentreClosureInput>,
) -> AppResult<(StatusCode, Json<WorkCentreClosure>)> {
    user.require(Permission::ProductionWrite)?;
    input.check()?;
    let mut tx = state.db.begin().await?;
    check_closure_centre(&mut tx, user.company_id, input.work_centre_id).await?;
    let id = new_id();
    sqlx::query(
        "INSERT INTO production.work_centre_closures
             (id, company_id, work_centre_id, from_date, to_date, kind, note, created_by)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(input.work_centre_id)
    .bind(input.from_date)
    .bind(input.to_date)
    .bind(&input.kind)
    .bind(input.note.trim())
    .bind(user.user_id)
    .execute(&mut *tx)
    .await?;
    audit::record(
        &mut tx,
        &user,
        "production_closure",
        id,
        "created",
        serde_json::json!({
            "work_centre_id": input.work_centre_id, "from": input.from_date, "to": input.to_date,
            "kind": input.kind,
        }),
    )
    .await?;
    let out = load_closure(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(out)))
}

/// Changes a closure.
#[utoipa::path(put, path = "/production/closures/{id}", tag = "production", params(("id" = Uuid, Path)),
    request_body = WorkCentreClosureInput,
    responses((status = 200, body = WorkCentreClosure), (status = 404, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn update_work_centre_closure(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<WorkCentreClosureInput>,
) -> AppResult<Json<WorkCentreClosure>> {
    user.require(Permission::ProductionWrite)?;
    input.check()?;
    let mut tx = state.db.begin().await?;
    check_closure_centre(&mut tx, user.company_id, input.work_centre_id).await?;
    let done = sqlx::query(
        "UPDATE production.work_centre_closures
         SET work_centre_id = $3, from_date = $4, to_date = $5, kind = $6, note = $7
         WHERE id = $1 AND company_id = $2",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(input.work_centre_id)
    .bind(input.from_date)
    .bind(input.to_date)
    .bind(&input.kind)
    .bind(input.note.trim())
    .execute(&mut *tx)
    .await?;
    if done.rows_affected() == 0 {
        return Err(AppError::NotFound("closure"));
    }
    audit::record(
        &mut tx,
        &user,
        "production_closure",
        id,
        "updated",
        serde_json::json!({
            "work_centre_id": input.work_centre_id, "from": input.from_date, "to": input.to_date,
            "kind": input.kind,
        }),
    )
    .await?;
    let out = load_closure(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok(Json(out))
}

/// Removes a closure.
#[utoipa::path(delete, path = "/production/closures/{id}", tag = "production", params(("id" = Uuid, Path)),
    responses((status = 204), (status = 404, body = ErrorBody)))]
async fn delete_work_centre_closure(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<StatusCode> {
    user.require(Permission::ProductionWrite)?;
    let mut tx = state.db.begin().await?;
    let done = sqlx::query(
        "DELETE FROM production.work_centre_closures WHERE id = $1 AND company_id = $2",
    )
    .bind(id)
    .bind(user.company_id)
    .execute(&mut *tx)
    .await?;
    if done.rows_affected() == 0 {
        return Err(AppError::NotFound("closure"));
    }
    audit::record(
        &mut tx,
        &user,
        "production_closure",
        id,
        "deleted",
        serde_json::json!({}),
    )
    .await?;
    tx.commit().await?;
    Ok(StatusCode::NO_CONTENT)
}

/// The work centre and closure routes.
pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(list_work_centres, create_work_centre))
        .routes(routes!(update_work_centre, delete_work_centre))
        .routes(routes!(set_work_centre_hours))
        .routes(routes!(
            list_work_centre_closures,
            create_work_centre_closure
        ))
        .routes(routes!(
            update_work_centre_closure,
            delete_work_centre_closure
        ))
}
