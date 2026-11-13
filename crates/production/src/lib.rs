//! Production: production orders built from the BOM (ADR 0036).
//!
//! A planner releases a confirmed order (or builds for stock): the active BOM is frozen on a
//! production order, its components are reserved, and completing the order consumes them
//! (backflush) and puts the output into stock. The sales order follows: `in_planning`, `planned`,
//! `in_production`, `ready_for_shipping`, with a promised date.
//!
//! Work centres, routings and operations (ADR 0060) say where and how it is built: a routing on a
//! BOM revision is frozen onto the production order as operations, scheduled on the work centres'
//! calendars, finished with the minutes worked, and shown against capacity.

pub mod capacity;
pub mod complete;
pub mod cost;
pub mod divisions;
pub mod operations;
pub mod orders;
pub mod pdf;
pub mod routing;
pub mod schedule;
pub mod work_centres;

use tradocraft_core::AppState;
use utoipa_axum::router::OpenApiRouter;

/// Builds the production router (divisions, work centres and production orders).
pub fn router() -> OpenApiRouter<AppState> {
    divisions::router()
        .merge(work_centres::router())
        .merge(routing::router())
        .merge(orders::router())
        .merge(operations::router())
        .merge(capacity::router())
        .merge(cost::router())
        .merge(pdf::router())
        .merge(complete::router())
}
