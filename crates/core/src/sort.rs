//! Server-side list sorting (ADR 0082).
//!
//! A list endpoint takes `sort=field` (ascending) or `sort=-field` (descending), optionally several
//! keys separated by commas (`sort=-status,name`, at most [`MAX_KEYS`]). Each endpoint declares a
//! whitelist that maps the API key to the SQL expression to sort by. User input is only ever
//! looked up in that list: it is never put in the SQL text. The direction is a literal.
//!
//! ```ignore
//! const SORT: &[(&str, &str)] = &[("name", "c.name"), ("city", "c.city")];
//! let order = sort::order_by(p.sort.as_deref(), SORT, "c.id", "c.name")?;
//! let sql = format!("{SELECT} {filter} ORDER BY {order} LIMIT $3 OFFSET $4");
//! ```

use crate::error::{AppError, AppResult};

/// The most sort keys one request may carry.
pub const MAX_KEYS: usize = 3;

/// The SQL expression list for an `ORDER BY` (without the keywords).
///
/// - `sort` absent or blank: `default` is returned unchanged.
/// - otherwise the requested keys in order, then `tiebreak` (the primary key), so that paging
///   through equal values is stable. A descending key sorts NULLs last, like an ascending one
///   (PostgreSQL puts NULLs first for `DESC` unless told otherwise).
///
/// An unknown key, a repeated key, an empty key or more than [`MAX_KEYS`] keys is a
/// [`AppError::Validation`].
pub fn order_by(
    sort: Option<&str>,
    whitelist: &[(&str, &str)],
    tiebreak: &str,
    default: &str,
) -> AppResult<String> {
    let Some(raw) = sort.map(str::trim).filter(|s| !s.is_empty()) else {
        return Ok(default.to_owned());
    };
    let mut parts: Vec<String> = Vec::new();
    let mut seen: Vec<&str> = Vec::new();
    for item in raw.split(',') {
        let item = item.trim();
        let (key, dir) = match item.strip_prefix('-') {
            Some(k) => (k, "DESC"),
            None => (item, "ASC"),
        };
        let expr = whitelist
            .iter()
            .find(|(k, _)| *k == key)
            .map(|(_, e)| *e)
            .ok_or_else(|| {
                let shown: String = key.chars().take(40).collect();
                let allowed: Vec<&str> = whitelist.iter().map(|(k, _)| *k).collect();
                AppError::Validation(format!(
                    "unknown sort key '{shown}' (allowed: {})",
                    allowed.join(", ")
                ))
            })?;
        if seen.contains(&key) {
            return Err(AppError::Validation(format!("sort key '{key}' repeated")));
        }
        seen.push(key);
        if seen.len() > MAX_KEYS {
            return Err(AppError::Validation(format!(
                "at most {MAX_KEYS} sort keys are allowed"
            )));
        }
        parts.push(format!("{expr} {dir} NULLS LAST"));
    }
    parts.push(tiebreak.to_owned());
    Ok(parts.join(", "))
}

#[cfg(test)]
mod tests {
    use super::*;

    const WL: &[(&str, &str)] = &[
        ("name", "c.name"),
        ("city", "c.city"),
        ("status", "c.status"),
    ];

    fn ok(s: Option<&str>) -> String {
        order_by(s, WL, "c.id", "c.name").unwrap()
    }

    fn bad(s: &str) -> String {
        match order_by(Some(s), WL, "c.id", "c.name") {
            Err(AppError::Validation(m)) => m,
            other => panic!("expected validation error, got {other:?}"),
        }
    }

    #[test]
    fn absent_or_blank_keeps_the_default_verbatim() {
        assert_eq!(ok(None), "c.name");
        assert_eq!(ok(Some("")), "c.name");
        assert_eq!(ok(Some("   ")), "c.name");
    }

    #[test]
    fn ascending_and_descending() {
        assert_eq!(ok(Some("city")), "c.city ASC NULLS LAST, c.id");
        assert_eq!(ok(Some("-city")), "c.city DESC NULLS LAST, c.id");
    }

    #[test]
    fn multiple_keys_keep_their_order_and_end_with_the_tiebreak() {
        assert_eq!(
            ok(Some("-status, name")),
            "c.status DESC NULLS LAST, c.name ASC NULLS LAST, c.id"
        );
        assert_eq!(
            ok(Some("name,city,status")).matches("NULLS LAST").count(),
            3
        );
    }

    #[test]
    fn unknown_key_is_rejected() {
        assert!(bad("nope").contains("unknown sort key 'nope'"));
        assert!(bad("name,nope").contains("unknown sort key"));
        assert!(bad("c.name").contains("unknown sort key"));
        assert!(bad("--name").contains("unknown sort key"));
        assert!(bad("+name").contains("unknown sort key"));
    }

    #[test]
    fn sql_injection_never_reaches_the_query() {
        for s in [
            "name; DROP TABLE crm.customers",
            "name,(SELECT pg_sleep(10))",
            "name--",
            "1",
            "name ASC",
            "-name DESC",
            "name) , (1",
            "\"name\"",
            "NAME",
            "name\0",
        ] {
            assert!(
                matches!(
                    order_by(Some(s), WL, "c.id", "c.name"),
                    Err(AppError::Validation(_))
                ),
                "{s:?} must be rejected"
            );
        }
    }

    #[test]
    fn output_only_contains_whitelisted_text() {
        let out = ok(Some("-name,city"));
        assert!(!out.contains(';') && !out.contains("--"));
    }

    #[test]
    fn empty_segments_are_rejected() {
        assert!(bad("name,").contains("unknown sort key ''"));
        assert!(bad(",name").contains("unknown sort key ''"));
        assert!(bad("name,,city").contains("unknown sort key ''"));
        assert!(bad("-").contains("unknown sort key ''"));
    }

    #[test]
    fn duplicates_are_rejected_even_with_opposite_directions() {
        assert!(bad("name,name").contains("repeated"));
        assert!(bad("name,-name").contains("repeated"));
    }

    #[test]
    fn more_than_three_keys_are_rejected() {
        let wl: &[(&str, &str)] = &[("a", "a"), ("b", "b"), ("c", "c"), ("d", "d")];
        assert!(order_by(Some("a,b,c"), wl, "id", "a").is_ok());
        assert!(matches!(
            order_by(Some("a,b,c,d"), wl, "id", "a"),
            Err(AppError::Validation(_))
        ));
    }

    #[test]
    fn long_unknown_keys_are_truncated_in_the_message() {
        let m = bad(&"x".repeat(500));
        assert!(m.len() < 200);
    }
}
