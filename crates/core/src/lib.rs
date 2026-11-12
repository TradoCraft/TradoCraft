//! Shared foundation used by every business module.

pub mod admin;
pub mod audit;
pub mod auth;
pub mod companies;
pub mod company;
pub mod cors;
pub mod csv_io;
pub mod environment;
pub mod error;
pub mod files;
pub mod mail;
pub mod modules;
pub mod numbering;
pub mod serde_util;
pub mod state;
pub mod worker;

pub use auth::{CurrentUser, Permission};
pub use error::{AppError, AppResult};
pub use state::{AppState, DocumentConfig};

/// New primary keys are UUIDv7: globally unique (safe to generate offline on
/// mobile devices) and time-ordered (index friendly).
/// Languages used for customer communication.
pub const LANGUAGES: [&str; 5] = ["nl", "fr", "en", "de", "es"];

pub fn is_language(code: &str) -> bool {
    LANGUAGES.contains(&code)
}

pub fn new_id() -> uuid::Uuid {
    uuid::Uuid::now_v7()
}

/// Today's date (UTC). Business dates are calendar dates without time zone.
pub fn today() -> chrono::NaiveDate {
    chrono::Utc::now().date_naive()
}
