//! Material requirements planning (ADR 0091, C2). [`engine`] is pure: it nets what is needed
//! against stock and what is already on order and proposes what to buy or build. [`run`] loads
//! the facts and keeps the proposals; [`routes`] is the API.

pub mod engine;
pub mod routes;
pub mod run;

pub use routes::router;
