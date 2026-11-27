//! Shared foundation used by every business module.

pub mod admin;
pub mod audit;
pub mod audit_log;
pub mod auth;
pub mod blob_store;
pub mod companies;
pub mod company;
pub mod concurrency;
pub mod cors;
pub mod csv_io;
pub mod environment;
pub mod error;
pub mod files;
pub mod filter;
pub mod group;
pub mod http_trace;
pub mod identity;
pub mod identity_admin;
pub mod import;
pub mod language;
pub mod languages;
pub mod live_events;
pub mod logo;
pub mod mail;
pub mod modules;
pub mod numbering;
pub mod preferences;
pub mod search;
pub mod serde_util;
pub mod sort;
pub mod state;
pub mod vat;
pub mod vat_check;
pub mod vat_rates;
pub mod vies;
pub mod worker;

pub use auth::{CurrentUser, Permission};
pub use blob_store::BlobStore;
pub use error::{AppError, AppResult};
pub use state::{AppState, DocumentConfig};

/// Whether `code` is a valid language code for stored content: any ISO 639-1 code (ADR 0101).
/// Which languages a company offers is configuration ([`languages`]), not this check.
pub fn is_language(code: &str) -> bool {
    language::is_iso_639_1(code)
}

/// New primary keys are UUIDv7: globally unique (safe to generate offline on
/// mobile devices) and time-ordered (index friendly).
pub fn new_id() -> uuid::Uuid {
    uuid::Uuid::now_v7()
}

/// Today's date (UTC). Business dates are calendar dates without time zone.
pub fn today() -> chrono::NaiveDate {
    chrono::Utc::now().date_naive()
}
