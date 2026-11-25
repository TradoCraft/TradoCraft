//! Capacity of the work centres (ADR 0063): per day, the minutes a work centre can work against
//! the load that the open operations of production orders put on it. A view for planners to
//! see overload and move work; loading the work centres finitely (and dragging operations on a
//! board) is the planning board's work-centre half, C3.

use std::collections::HashMap;

use axum::extract::{Query, State};
use axum::Json;
use chrono::NaiveDate;
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection};
use tradocraft_core::{AppError, AppResult, AppState, CurrentUser, Permission};
use utoipa::{IntoParams, ToSchema};
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::finite::BookedLoad;
use crate::schedule::{spread_load, Calendar};
use crate::work_centres::load_calendars;

type ErrorBody = tradocraft_core::error::ErrorBody;

/// The longest period one request covers, as on the planning board.
const MAX_DAYS: i64 = 62;

#[derive(Debug, Deserialize, IntoParams)]
pub struct ProductionCapacityParams {
    /// First day.
    #[serde(deserialize_with = "tradocraft_core::serde_util::date")]
    #[param(value_type = String, format = Date)]
    pub from: NaiveDate,
    /// Last day, inclusive; at most 62 days after `from`.
    #[serde(deserialize_with = "tradocraft_core::serde_util::date")]
    #[param(value_type = String, format = Date)]
    pub to: NaiveDate,
    /// Only the work centres of this division.
    pub division_id: Option<Uuid>,
}

/// One day of one work centre.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct ProductionCapacityDay {
    pub date: NaiveDate,
    /// What the work centre can work: the minutes of its hours times its capacity, 0 on a closure.
    pub available_minutes: i64,
    /// What the open operations put on the day.
    pub load_minutes: i64,
    /// The load is more than is available.
    pub overloaded: bool,
}

/// A work centre over the period.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct ProductionCapacityCentre {
    pub id: Uuid,
    pub code: String,
    pub name: String,
    pub division_id: Option<Uuid>,
    pub active: bool,
    pub capacity: i32,
    pub days: Vec<ProductionCapacityDay>,
    pub total_available_minutes: i64,
    pub total_load_minutes: i64,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct ProductionCapacity {
    pub from: NaiveDate,
    pub to: NaiveDate,
    pub centres: Vec<ProductionCapacityCentre>,
}

#[derive(FromRow)]
struct CentreRow {
    id: Uuid,
    code: String,
    name: String,
    division_id: Option<Uuid>,
    active: bool,
    capacity: i32,
}

#[derive(FromRow)]
struct OpLoad {
    work_centre_id: Uuid,
    planned_minutes: i32,
    planned_start: NaiveDate,
    planned_end: NaiveDate,
}

/// Capacity against load per work centre and day. Load is the planned minutes of every operation
/// of an open production order that is not finished, spread over the working days between its
/// planned dates in proportion to what each day offers. Work that is already late lands on the
/// first day of the period; an operation that is running still counts in full (no progress is
/// recorded).
#[utoipa::path(get, path = "/production/capacity", tag = "production", params(ProductionCapacityParams),
    responses((status = 200, body = ProductionCapacity), (status = 422, body = ErrorBody)))]
async fn production_capacity(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(p): Query<ProductionCapacityParams>,
) -> AppResult<Json<ProductionCapacity>> {
    user.require(Permission::ProductionRead)?;
    let mut conn = state.db.acquire().await?;
    Ok(Json(
        compute_capacity(&mut conn, user.company_id, p.from, p.to, p.division_id).await?,
    ))
}

/// Capacity against load for the work centres of a company over `[from, to]`, optionally of one
/// division (the body of `GET /production/capacity`, also used by the planning board).
pub(crate) async fn compute_capacity(
    conn: &mut PgConnection,
    company_id: Uuid,
    from: NaiveDate,
    to: NaiveDate,
    division_id: Option<Uuid>,
) -> AppResult<ProductionCapacity> {
    if to < from {
        return Err(AppError::Validation("to must not be before from".into()));
    }
    if (to - from).num_days() + 1 > MAX_DAYS {
        return Err(AppError::Validation(format!(
            "the period can be at most {MAX_DAYS} days"
        )));
    }
    // Inactive work centres show up only while they still have work.
    let centres: Vec<CentreRow> = sqlx::query_as(
        "SELECT w.id, w.code, w.name, w.division_id, w.active, w.capacity
         FROM production.work_centres w
         WHERE w.company_id = $1 AND ($2::uuid IS NULL OR w.division_id = $2)
           AND (w.active OR EXISTS (
                SELECT 1 FROM production.order_operations o
                JOIN production.production_orders po ON po.id = o.production_order_id
                WHERE o.work_centre_id = w.id AND o.status IN ('pending', 'in_progress')
                  AND po.status IN ('released', 'in_progress')))
         ORDER BY w.sort_order, w.code",
    )
    .bind(company_id)
    .bind(division_id)
    .fetch_all(&mut *conn)
    .await?;
    let ids: Vec<Uuid> = centres.iter().map(|c| c.id).collect();
    // Operations of cancelled and completed orders are not work to do, whatever their status.
    let loads: Vec<OpLoad> = sqlx::query_as(
        "SELECT o.work_centre_id, o.planned_minutes, o.planned_start, o.planned_end
         FROM production.order_operations o
         JOIN production.production_orders po ON po.id = o.production_order_id
         WHERE o.company_id = $1 AND o.work_centre_id = ANY($2)
           AND o.status IN ('pending', 'in_progress') AND po.status IN ('released', 'in_progress')
           AND o.planned_start <= $3 AND o.planned_minutes > 0",
    )
    .bind(company_id)
    .bind(&ids)
    .bind(to)
    .fetch_all(&mut *conn)
    .await?;
    // An operation that began before the period is spread over its whole range, so the calendars
    // (closures included) must reach back to the earliest of them, not only to the period.
    let earliest = loads
        .iter()
        .map(|o| o.planned_start)
        .fold(from, NaiveDate::min);
    let calendars = load_calendars(conn, company_id, &ids, earliest).await?;
    let mut by_day: HashMap<(Uuid, NaiveDate), i64> = HashMap::new();
    for o in &loads {
        let Some(cal) = calendars.get(&o.work_centre_id) else {
            continue;
        };
        // Late work (planned to end before the period) is still to be done: it counts on the
        // first day of the period. Work that reaches into the period keeps its dates; only the
        // days inside the period are counted.
        let (start, end) = if o.planned_end < from {
            (from, from)
        } else {
            (o.planned_start, o.planned_end)
        };
        for (day, minutes) in spread_load(i64::from(o.planned_minutes), start, end, cal) {
            if day >= from && day <= to {
                *by_day.entry((o.work_centre_id, day)).or_default() += minutes;
            }
        }
    }
    let days: Vec<NaiveDate> = from.iter_days().take_while(|d| *d <= to).collect();
    let centres = centres
        .into_iter()
        .map(|c| {
            let cal = calendars.get(&c.id);
            let days: Vec<ProductionCapacityDay> = days
                .iter()
                .map(|d| {
                    let available = cal.map_or(0, |cal| cal.capacity_minutes_on(*d));
                    let load = by_day.get(&(c.id, *d)).copied().unwrap_or(0);
                    ProductionCapacityDay {
                        date: *d,
                        available_minutes: available,
                        load_minutes: load,
                        overloaded: load > available,
                    }
                })
                .collect();
            ProductionCapacityCentre {
                total_available_minutes: days.iter().map(|d| d.available_minutes).sum(),
                total_load_minutes: days.iter().map(|d| d.load_minutes).sum(),
                id: c.id,
                code: c.code,
                name: c.name,
                division_id: c.division_id,
                active: c.active,
                capacity: c.capacity,
                days,
            }
        })
        .collect();
    Ok(ProductionCapacity { from, to, centres })
}

/// The minutes the other open operations put on one work centre, per day: every pending or running
/// operation of a released or in-progress order except `exclude`, spread over its own dates like
/// [`compute_capacity`] does. Late work is not moved onto another day here.
pub(crate) async fn other_load(
    conn: &mut PgConnection,
    company_id: Uuid,
    work_centre_id: Uuid,
    exclude: Uuid,
    cal: &Calendar,
) -> AppResult<HashMap<NaiveDate, i64>> {
    let rows: Vec<OpLoad> = sqlx::query_as(
        "SELECT o.work_centre_id, o.planned_minutes, o.planned_start, o.planned_end
         FROM production.order_operations o
         JOIN production.production_orders po ON po.id = o.production_order_id
         WHERE o.company_id = $1 AND o.work_centre_id = $2 AND o.id <> $3
           AND o.status IN ('pending', 'in_progress') AND po.status IN ('released', 'in_progress')
           AND o.planned_minutes > 0",
    )
    .bind(company_id)
    .bind(work_centre_id)
    .bind(exclude)
    .fetch_all(conn)
    .await?;
    let mut by_day: HashMap<NaiveDate, i64> = HashMap::new();
    for o in rows {
        for (day, minutes) in spread_load(
            i64::from(o.planned_minutes),
            o.planned_start,
            o.planned_end,
            cal,
        ) {
            *by_day.entry(day).or_default() += minutes;
        }
    }
    Ok(by_day)
}

/// The minutes other work already books on the work centres, per calendar index and day, for a
/// finite re-schedule of one order: every pending or running operation of a released or
/// in-progress order, except the pending operations of `replacing_order` (they are being placed
/// again). `centres` and `calendars` are parallel lists.
pub(crate) async fn booked_load(
    conn: &mut PgConnection,
    company_id: Uuid,
    centres: &[Uuid],
    calendars: &[Calendar],
    replacing_order: Uuid,
) -> AppResult<BookedLoad> {
    let rows: Vec<OpLoad> = sqlx::query_as(
        "SELECT o.work_centre_id, o.planned_minutes, o.planned_start, o.planned_end
         FROM production.order_operations o
         JOIN production.production_orders po ON po.id = o.production_order_id
         WHERE o.company_id = $1 AND o.work_centre_id = ANY($2)
           AND o.status IN ('pending', 'in_progress') AND po.status IN ('released', 'in_progress')
           AND o.planned_minutes > 0
           AND NOT (o.production_order_id = $3 AND o.status = 'pending')",
    )
    .bind(company_id)
    .bind(centres)
    .bind(replacing_order)
    .fetch_all(conn)
    .await?;
    let mut booked: BookedLoad = vec![HashMap::new(); centres.len()];
    for o in rows {
        let Some(i) = centres.iter().position(|c| *c == o.work_centre_id) else {
            continue;
        };
        for (day, minutes) in spread_load(
            i64::from(o.planned_minutes),
            o.planned_start,
            o.planned_end,
            &calendars[i],
        ) {
            *booked[i].entry(day).or_default() += minutes;
        }
    }
    Ok(booked)
}

/// The capacity routes.
pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new().routes(routes!(production_capacity))
}
