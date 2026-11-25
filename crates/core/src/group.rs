//! Server-side list grouping (ADR 0089).
//!
//! A `GET /<resource>/groups` endpoint takes `group_by=<key>` plus the same search and filter
//! parameters as the list and returns one count per distinct value. Each endpoint declares a
//! whitelist that maps the API key to the SQL expression that yields the group value as text.
//! User input is only ever looked up in that list: it is never put in the SQL text. Only columns
//! that are never NULL belong in a whitelist, so that every group can be selected by a filter.
//!
//! ```ignore
//! const GROUPS: &[(&str, &str)] = &[("status", "status")];
//! let expr = group::expr(p.group_by.as_deref(), GROUPS)?;
//! let sql = group::count_sql(expr, &format!("sales.quotations {filter}"));
//! let rows: Vec<(String, i64)> = sqlx::query_as(&sql).bind(..).fetch_all(db).await?;
//! Ok(Json(group::page(p.group_by.as_deref().unwrap_or_default(), rows)?))
//! ```

use serde::Serialize;
use utoipa::ToSchema;

use crate::error::{AppError, AppResult};

/// The most groups one response may carry. More is a validation error: the user filters first.
pub const MAX_GROUPS: usize = 200;

/// The rows of one group.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, ToSchema)]
pub struct GroupCount {
    /// The group value as text (booleans as `true` / `false`).
    pub value: String,
    pub count: i64,
}

/// The response of a groups endpoint, ordered by value.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, ToSchema)]
pub struct GroupPage {
    pub group_by: String,
    pub groups: Vec<GroupCount>,
}

/// The SQL expression for the requested `group_by` key.
///
/// An absent, blank or unknown key is an [`AppError::Validation`] that lists the allowed keys.
pub fn expr<'a>(group_by: Option<&str>, whitelist: &[(&str, &'a str)]) -> AppResult<&'a str> {
    let allowed = || {
        whitelist
            .iter()
            .map(|(k, _)| *k)
            .collect::<Vec<_>>()
            .join(", ")
    };
    let key = group_by
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .ok_or_else(|| {
            AppError::Validation(format!("group_by is required (allowed: {})", allowed()))
        })?;
    whitelist
        .iter()
        .find(|(k, _)| *k == key)
        .map(|(_, e)| *e)
        .ok_or_else(|| {
            let shown: String = key.chars().take(40).collect();
            AppError::Validation(format!(
                "unknown group_by '{shown}' (allowed: {})",
                allowed()
            ))
        })
}

/// The counting statement: `from_where` is the text after `FROM` (table, joins and `WHERE`). The
/// result rows are `(value text, count bigint)` ordered by value. It fetches one row more than
/// [`MAX_GROUPS`] so that [`page`] can tell that the cap was exceeded.
pub fn count_sql(expr: &str, from_where: &str) -> String {
    format!(
        "SELECT ({expr})::text AS value, count(*) AS count FROM {from_where}
         GROUP BY 1 ORDER BY 1 LIMIT {}",
        MAX_GROUPS + 1
    )
}

/// Builds the response from the rows of [`count_sql`]; more than [`MAX_GROUPS`] rows is a
/// validation error.
pub fn page(group_by: &str, rows: Vec<(String, i64)>) -> AppResult<GroupPage> {
    if rows.len() > MAX_GROUPS {
        return Err(AppError::Validation(format!(
            "more than {MAX_GROUPS} groups; narrow the list with a search or a filter first"
        )));
    }
    Ok(GroupPage {
        group_by: group_by.trim().to_owned(),
        groups: rows
            .into_iter()
            .map(|(value, count)| GroupCount { value, count })
            .collect(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    const WL: &[(&str, &str)] = &[("status", "q.status"), ("active", "q.active")];

    fn bad(g: Option<&str>) -> String {
        match expr(g, WL) {
            Err(AppError::Validation(m)) => m,
            other => panic!("expected validation error, got {other:?}"),
        }
    }

    #[test]
    fn known_key_resolves_to_its_expression() {
        assert_eq!(expr(Some("status"), WL).unwrap(), "q.status");
        assert_eq!(expr(Some(" active "), WL).unwrap(), "q.active");
    }

    #[test]
    fn absent_or_blank_is_rejected_and_lists_keys() {
        for g in [None, Some(""), Some("  ")] {
            let m = bad(g);
            assert!(m.contains("required") && m.contains("status, active"));
        }
    }

    #[test]
    fn unknown_key_is_rejected_and_lists_keys() {
        let m = bad(Some("nope"));
        assert!(m.contains("'nope'") && m.contains("status, active"));
        assert!(bad(Some("status; DROP TABLE x")).contains("unknown"));
        assert!(bad(Some("-status")).contains("unknown"));
    }

    #[test]
    fn long_input_is_truncated_in_the_message() {
        assert!(bad(Some(&"x".repeat(500))).len() < 200);
    }

    #[test]
    fn count_sql_groups_orders_and_caps() {
        let sql = count_sql("q.status", "sales.quotations q WHERE true");
        assert!(sql.contains("(q.status)::text"));
        assert!(sql.contains("GROUP BY 1 ORDER BY 1"));
        assert!(sql.contains("LIMIT 201"));
    }

    #[test]
    fn page_keeps_order_and_counts() {
        let p = page("status", vec![("draft".into(), 2), ("sent".into(), 1)]).unwrap();
        assert_eq!(p.group_by, "status");
        assert_eq!(
            p.groups,
            vec![
                GroupCount {
                    value: "draft".into(),
                    count: 2
                },
                GroupCount {
                    value: "sent".into(),
                    count: 1
                }
            ]
        );
    }

    #[test]
    fn exactly_the_cap_is_fine_one_more_is_rejected() {
        let rows = |n: usize| (0..n).map(|i| (format!("v{i}"), 1)).collect::<Vec<_>>();
        assert_eq!(
            page("k", rows(MAX_GROUPS)).unwrap().groups.len(),
            MAX_GROUPS
        );
        assert!(matches!(
            page("k", rows(MAX_GROUPS + 1)),
            Err(AppError::Validation(_))
        ));
    }
}
