//! Sales: quotations.
//!
//! A quotation is a commercial snapshot. While `draft` it is repriced from the
//! current price lists on every change; from `sent` onwards it is immutable and
//! changes go through a new revision (same number, revision + 1).

pub mod configured;
pub mod cooccurrence;
pub mod favorites;
mod model;
pub mod order_doc;
pub mod order_portal;
pub mod order_priority;
pub mod orders;
mod pdf;
pub mod remarks;
mod routes;
pub mod service;
pub mod shipping;

pub use model::*;
pub use routes::router as quotations_router;

pub fn router() -> utoipa_axum::router::OpenApiRouter<tradocraft_core::AppState> {
    quotations_router()
        .merge(orders::router())
        .merge(order_priority::router())
        .merge(shipping::router())
        .merge(configured::router())
        .merge(remarks::router())
        .merge(favorites::router())
}
