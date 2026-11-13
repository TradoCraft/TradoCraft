//! Purchasing: suppliers, price lists, purchase orders, and goods receipts (ADR 0031); the purchase
//! order as a PDF and a mail to the supplier (ADR 0061).

pub mod document;
pub mod orders;
pub mod receipts;
pub mod routes;
pub mod supplier_products;
pub mod suppliers;

use tradocraft_core::AppState;
use utoipa_axum::router::OpenApiRouter;

/// Builds the purchasing router (suppliers, price lists, purchase orders, goods receipts).
pub fn router() -> OpenApiRouter<AppState> {
    routes::router()
}
