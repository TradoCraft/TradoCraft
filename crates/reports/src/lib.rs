//! User-defined reports (ADR 0042): a stored definition over a whitelisted catalog of objects,
//! turned into a bound-parameter query when it is run, exported as CSV or PDF.

/// The catalog of objects and fields reports may use.
pub mod catalog;
/// Report definitions and their planning.
pub mod definition;
/// Running a plan against the database.
pub mod engine;
/// The PDF data of a report.
pub mod pdf;
/// Relative dates.
pub mod relative;
mod routes;
/// Scheduled report mails.
pub mod schedule;
mod schedule_routes;

pub use routes::{router, ReportClock};
