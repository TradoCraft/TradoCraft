//! Finance: supplier invoices as an accounts-payable register with a three-way match of purchase
//! order, goods receipt and invoice (ADR 0046). Not a general ledger: statutory accounting stays
//! in the external package (ADR 0008).

/// Supplier invoices: registration, match, approval, dispute, payment.
pub mod invoices;
/// The three-way match as a pure function.
pub mod matching;
/// HTTP routes and OpenAPI declarations.
pub mod routes;
/// Per-company match tolerances.
pub mod settings;

use tradocraft_core::AppState;
use utoipa_axum::router::OpenApiRouter;

/// Builds the finance router (supplier invoices, match, approval, payment, settings).
pub fn router() -> OpenApiRouter<AppState> {
    routes::router()
}
