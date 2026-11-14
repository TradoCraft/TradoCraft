//! Admin-defined product configurators (ADR 0034).
//!
//! An administrator describes a configurator as one JSON document ([`definition`]): fields per
//! scope (project, group, item), lookup tables, computed values, output rules and validations,
//! written in a small safe formula language ([`expr`]). [`compile`] checks the document,
//! [`engine`] evaluates it purely against a catalogue snapshot, [`store`] keeps models, revisions
//! and saved configurations, and [`routes`] exposes them; a configuration becomes a quotation
//! through `tradocraft_sales::configured::import`.

pub mod compile;
pub mod definition;
pub mod engine;
pub mod expr;
pub mod motor;
pub mod routes;
pub mod store;
pub mod tables;

pub use routes::router;
pub use store::seed_demo;

#[cfg(test)]
mod tests;
