//! `{{placeholder}}` substitution for prepared answers.

use std::collections::BTreeMap;

use tradocraft_core::{AppError, AppResult};

/// Replaces `{{key}}` with its value. Unknown or empty placeholders stay visible, so the agent
/// sees what still has to be filled in before sending.
pub fn render(text: &str, values: &BTreeMap<String, String>) -> String {
    let mut out = String::with_capacity(text.len());
    let mut rest = text;
    while let Some(start) = rest.find("{{") {
        out.push_str(&rest[..start]);
        let after = &rest[start + 2..];
        match after.find("}}") {
            Some(end) => {
                let key = after[..end].trim();
                match values.get(key).filter(|v| !v.is_empty()) {
                    Some(v) => out.push_str(v),
                    None => out.push_str(&rest[start..start + 2 + end + 2]),
                }
                rest = &after[end + 2..];
            }
            None => {
                out.push_str(&rest[start..]);
                rest = "";
            }
        }
    }
    out.push_str(rest);
    out
}

/// Placeholders offered to authors of prepared answers.
pub const PLACEHOLDERS: [&str; 15] = [
    "customer.name",
    "contact.name",
    "contact.first_name",
    "contact.last_name",
    "contact.salutation",
    "ticket.number",
    "ticket.subject",
    "agent.name",
    "team.name",
    "company.name",
    "quotation.number",
    "quotation.revision",
    "quotation.total",
    "order.number",
    "order.reference",
];

/// Rejects a `{{name}}` that is not a known placeholder. Used where a text goes out without an
/// agent reading it first (automation mail).
pub fn check_placeholders(field: &str, text: &str) -> AppResult<()> {
    let mut rest = text;
    while let Some(start) = rest.find("{{") {
        let after = &rest[start + 2..];
        let Some(end) = after.find("}}") else { break };
        let name = after[..end].trim();
        if !PLACEHOLDERS.contains(&name) {
            return Err(AppError::Validation(format!(
                "{field}: {{{{{name}}}}} is not a placeholder (use {})",
                PLACEHOLDERS.map(|p| format!("{{{{{p}}}}}")).join(", ")
            )));
        }
        rest = &after[end + 2..];
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn replaces_known_and_keeps_unknown_placeholders() {
        let values = BTreeMap::from([
            ("contact.name".to_string(), "Anna".to_string()),
            ("quotation.number".to_string(), "Q2026-00012".to_string()),
            ("order.number".to_string(), String::new()),
        ]);
        assert_eq!(
            render("Dear {{ contact.name }}, about {{quotation.number}} / {{order.number}} / {{nope}} {{", &values),
            "Dear Anna, about Q2026-00012 / {{order.number}} / {{nope}} {{"
        );
    }

    #[test]
    fn unknown_placeholders_are_found_by_the_check() {
        assert!(check_placeholders("body", "Dear {{contact.name}}, {{ team.name }} {x} { }").is_ok());
        let e = check_placeholders("body", "Dear {{contact.nme}}").unwrap_err().to_string();
        assert!(e.contains("contact.nme"), "{e}");
        assert!(e.contains("body"), "{e}");
    }

    #[test]
    fn the_team_name_is_a_placeholder() {
        assert!(PLACEHOLDERS.contains(&"team.name"));
    }
}
