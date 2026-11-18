//! Server-side list filters (ADR 0083).
//!
//! A list endpoint takes one optional query parameter per filter it supports. The value is a single
//! value or a comma-separated list (`status=draft,sent`); the values of one filter combine with OR.
//! The parsed values are bound as one array parameter (`= ANY($n)`), never put in the SQL text.
//!
//! ```ignore
//! let status = filter::values(p.status.as_deref(), "status", &["draft", "sent"])?;
//! sqlx::query("... WHERE ($3::text[] IS NULL OR status = ANY($3))").bind(&status)
//! ```

use crate::error::{AppError, AppResult};

/// The most values one filter may carry.
pub const MAX_VALUES: usize = 20;

/// Parses a filter against a fixed list of allowed values.
///
/// `None` for an absent or blank parameter (no filter). Otherwise the trimmed values in request
/// order without duplicates. An empty item, a value that is not in `allowed` or more than
/// [`MAX_VALUES`] distinct values is an [`AppError::Validation`].
pub fn values(raw: Option<&str>, name: &str, allowed: &[&str]) -> AppResult<Option<Vec<String>>> {
    values_with(
        raw,
        name,
        &format!("allowed: {}", allowed.join(", ")),
        |v| allowed.contains(&v).then(|| v.to_owned()),
    )
}

/// Like [`values`] for an open set of values. `normalize` returns the canonical form of a valid
/// value (for example upper-cased) or `None` to reject it; `expected` describes what is accepted
/// and is shown in the error message. Duplicates are removed after normalising.
pub fn values_with(
    raw: Option<&str>,
    name: &str,
    expected: &str,
    normalize: impl Fn(&str) -> Option<String>,
) -> AppResult<Option<Vec<String>>> {
    let Some(raw) = raw.map(str::trim).filter(|s| !s.is_empty()) else {
        return Ok(None);
    };
    let mut out: Vec<String> = Vec::new();
    for item in raw.split(',') {
        let item = item.trim();
        let value = normalize(item).ok_or_else(|| {
            let shown: String = item.chars().take(40).collect();
            AppError::Validation(format!("unknown {name} value '{shown}' ({expected})"))
        })?;
        if !out.contains(&value) {
            out.push(value);
            if out.len() > MAX_VALUES {
                return Err(AppError::Validation(format!(
                    "at most {MAX_VALUES} {name} values are allowed"
                )));
            }
        }
    }
    Ok(Some(out))
}

/// A two-letter country code, upper-cased; `None` for anything else.
pub fn country_code(v: &str) -> Option<String> {
    (v.len() == 2 && v.bytes().all(|b| b.is_ascii_alphabetic())).then(|| v.to_ascii_uppercase())
}

#[cfg(test)]
mod tests {
    use super::*;

    const ALLOWED: &[&str] = &["draft", "sent", "accepted"];

    fn ok(s: Option<&str>) -> Option<Vec<String>> {
        values(s, "status", ALLOWED).unwrap()
    }

    fn bad(s: &str) -> String {
        match values(Some(s), "status", ALLOWED) {
            Err(AppError::Validation(m)) => m,
            other => panic!("expected validation error, got {other:?}"),
        }
    }

    #[test]
    fn absent_or_blank_means_no_filter() {
        assert_eq!(ok(None), None);
        assert_eq!(ok(Some("")), None);
        assert_eq!(ok(Some("   ")), None);
    }

    #[test]
    fn single_and_multiple_values_keep_request_order() {
        assert_eq!(ok(Some("sent")), Some(vec!["sent".into()]));
        assert_eq!(
            ok(Some("sent, draft")),
            Some(vec!["sent".into(), "draft".into()])
        );
    }

    #[test]
    fn duplicates_are_removed() {
        assert_eq!(
            ok(Some("draft,sent,draft")),
            Some(vec!["draft".into(), "sent".into()])
        );
    }

    #[test]
    fn unknown_value_is_rejected_and_names_the_filter_and_allowed_values() {
        let m = bad("draft,nope");
        assert!(m.contains("status") && m.contains("'nope'"));
        assert!(m.contains("draft, sent, accepted"));
        assert!(bad("DRAFT").contains("unknown"));
        assert!(bad("draft; DROP TABLE x").contains("unknown"));
    }

    #[test]
    fn empty_items_are_rejected() {
        assert!(bad("draft,").contains("''"));
        assert!(bad(",draft").contains("''"));
        assert!(bad("draft,,sent").contains("''"));
    }

    #[test]
    fn more_than_twenty_values_are_rejected() {
        let wl: Vec<String> = (0..21).map(|i| format!("v{i}")).collect();
        let allowed: Vec<&str> = wl.iter().map(String::as_str).collect();
        let twenty = allowed[..20].join(",");
        assert_eq!(
            values(Some(&twenty), "f", &allowed).unwrap().unwrap().len(),
            20
        );
        let all = allowed.join(",");
        assert!(matches!(
            values(Some(&all), "f", &allowed),
            Err(AppError::Validation(_))
        ));
    }

    #[test]
    fn long_input_is_truncated_in_the_message() {
        assert!(bad(&"x".repeat(500)).len() < 200);
    }

    #[test]
    fn country_codes_are_uppercased_and_deduplicated() {
        let v = values_with(
            Some("be, nl,BE"),
            "country_code",
            "two letters",
            country_code,
        )
        .unwrap()
        .unwrap();
        assert_eq!(v, vec!["BE", "NL"]);
        for s in ["B", "BEL", "B1", "é", "be,", "1 "] {
            assert!(
                values_with(Some(s), "country_code", "two letters", country_code).is_err(),
                "{s:?}"
            );
        }
    }
}
