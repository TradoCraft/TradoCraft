//! Accent- and case-insensitive list search (ADR 0057, roadmap D5).
//!
//! "Liege" finds "Liège". The folding is done by the database (`core.search_fold`: lower case and
//! `unaccent`), on the column and on the search text alike, so there is one set of rules and the
//! trigram indexes of the migration match what the queries compare.
//!
//! ```ignore
//! let pattern = search::pattern(params.q.as_deref());          // bind as $2
//! let filter = format!(
//!     "WHERE ($2::text IS NULL OR {} OR {})",
//!     search::matches("c.name", "$2"),
//!     search::matches("c.city", "$2"),
//! );
//! ```

/// The `LIKE` pattern for a search text: trimmed, with the user's `%`, `_` and `\` taken
/// literally, wrapped in `%`. `None` when there is nothing to search for (no filter). Bind it to
/// the parameter that [`matches`] is given. It is not folded here: the query folds it.
pub fn pattern(q: Option<&str>) -> Option<String> {
    let q = q?.trim();
    if q.is_empty() {
        return None;
    }
    let mut out = String::with_capacity(q.len() + 2);
    out.push('%');
    for c in q.chars() {
        if matches!(c, '%' | '_' | '\\') {
            out.push('\\');
        }
        out.push(c);
    }
    out.push('%');
    Some(out)
}

/// The SQL test "`expr` contains the search text, ignoring case and accents". `param` is the
/// placeholder the [`pattern`] is bound to (`$2`). A NULL `expr` does not match.
pub fn matches(expr: &str, param: &str) -> String {
    format!("core.search_fold({expr}) LIKE core.search_fold({param}) ESCAPE '\\'")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pattern_trims_wraps_and_escapes() {
        assert_eq!(pattern(Some("  Liège ")).as_deref(), Some("%Liège%"));
        assert_eq!(
            pattern(Some("100%_x\\")).as_deref(),
            Some("%100\\%\\_x\\\\%")
        );
        assert_eq!(pattern(Some("   ")), None);
        assert_eq!(pattern(Some("")), None);
        assert_eq!(pattern(None), None);
    }

    #[test]
    fn matches_builds_the_comparison_on_both_sides() {
        assert_eq!(
            matches("c.name", "$2"),
            r"core.search_fold(c.name) LIKE core.search_fold($2) ESCAPE '\'"
        );
    }
}
