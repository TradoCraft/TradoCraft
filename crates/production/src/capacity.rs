//! Capacity of the work centres (ADR 0060): per day, the minutes a work centre can work against
//! the load that the open operations of production orders put on it. A view for planners to
//! see overload and move work; loading the work centres finitely (and dragging operations on a
//! board) is the planning board's work-centre half, C3.

use std::collections::HashMap;

use axum::extract::{Query, State};
use axum::Json;
use chrono::NaiveDate;
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use tradocraft_core::{AppError, AppResult, AppState, CurrentUser, Permission};
use utoipa::{IntoParams, ToSchema};
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::schedule::spread_load;
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
    if p.to < p.from {
        return Err(AppError::Validation("to must not be before from".into()));
    }
    if (p.to - p.from).num_days() + 1 > MAX_DAYS {
        return Err(AppError::Validation(format!(
            "the period can be at most {MAX_DAYS} days"
        )));
    }
    let mut conn = state.db.acquire().await?;
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
    .bind(user.company_id)
    .bind(p.division_id)
    .fetch_all(&mut *conn)
    .await?;
    let ids: Vec<Uuid> = centres.iter().map(|c| c.id).collect();
    let calendars = load_calendars(&mut conn, user.company_id, &ids, p.from).await?;
    // Operations of cancelled and completed orders are not work to do, whatever their status.
    let loads: Vec<OpLoad> = sqlx::query_as(
        "SELECT o.work_centre_id, o.planned_minutes, o.planned_start, o.planned_end
         FROM production.order_operations o
         JOIN production.production_orders po ON po.id = o.production_order_id
         WHERE o.company_id = $1 AND o.work_centre_id = ANY($2)
           AND o.status IN ('pending', 'in_progress') AND po.status IN ('released', 'in_progress')
           AND o.planned_start <= $3 AND o.planned_minutes > 0",
    )
    .bind(user.company_id)
    .bind(&ids)
    .bind(p.to)
    .fetch_all(&mut *conn)
    .await?;
    let mut by_day: HashMap<(Uuid, NaiveDate), i64> = HashMap::new();
    for o in &loads {
        let Some(cal) = calendars.get(&o.work_centre_id) else {
            continue;
        };
        // Late work (planned to end before the period) is still to be done: it counts on the
        // first day of the period. Work that reaches into the period keeps its dates; only the
        // days inside the period are counted.
        let (start, end) = if o.planned_end < p.from {
            (p.from, p.from)
        } else {
            (o.planned_start, o.planned_end)
        };
        for (day, minutes) in spread_load(i64::from(o.planned_minutes), start, end, cal) {
            if day >= p.from && day <= p.to {
                *by_day.entry((o.work_centre_id, day)).or_default() += minutes;
            }
        }
    }
    let days: Vec<NaiveDate> = p.from.iter_days().take_while(|d| *d <= p.to).collect();
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
    Ok(Json(ProductionCapacity {
        from: p.from,
        to: p.to,
        centres,
    }))
}

/// The capacity routes.
pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new().routes(routes!(production_capacity))
}
