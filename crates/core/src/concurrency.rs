//! Concurrent-edit protection (ADR 0060): optimistic concurrency on a row version.
//!
//! A record that people edit by hand has a `version` column that a trigger raises on every update.
//! The API returns it; a save sends it back as `expected_version`. The check runs after the row is
//! locked (`SELECT ... FOR UPDATE`), so it compares with the latest committed version and two
//! saves that start from the same version cannot both succeed: the second waits, then finds the
//! version moved on.
//!
//! The field is optional so that scripts, imports and older clients keep working; they get the
//! behaviour they always had (the last write wins). The app always sends it.

use crate::{AppError, AppResult};

/// The error code the app looks for to offer a reload.
pub const RECORD_CHANGED: &str = "record_changed";

/// Refuses (409 `record_changed`) a save that was made from an older version of the record.
/// `what` names the record for the message, for example `customer C-100`.
pub fn check_version(expected: Option<i64>, current: i64, what: &str) -> AppResult<()> {
    match expected {
        Some(e) if e != current => Err(AppError::ConflictCode(
            RECORD_CHANGED,
            format!("{what} was changed by someone else; reload it before saving"),
        )),
        _ => Ok(()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn no_expected_version_always_passes() {
        assert!(check_version(None, 7, "customer").is_ok());
    }

    #[test]
    fn matching_version_passes() {
        assert!(check_version(Some(3), 3, "customer").is_ok());
    }

    #[test]
    fn stale_version_is_a_record_changed_conflict() {
        match check_version(Some(2), 3, "customer C-1") {
            Err(AppError::ConflictCode(code, msg)) => {
                assert_eq!(code, RECORD_CHANGED);
                assert!(msg.starts_with("customer C-1 was changed"));
            }
            other => panic!("unexpected {other:?}"),
        }
    }
}
