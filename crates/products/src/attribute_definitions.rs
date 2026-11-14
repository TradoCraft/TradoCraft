//! Admin-defined attribute definitions (ADR 0068): key, label, kind, unit and select options for
//! product suitability attributes and site baseline items. Scoped per company; `scope` is
//! `product` or the code of a baseline item type.

use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::Json;
use serde::{Deserialize, Serialize};
use sqlx::types::Json as SqlJson;
use sqlx::FromRow;
use std::collections::HashSet;
use tradocraft_core::{audit, new_id, AppError, AppResult, AppState, CurrentUser, Permission};
use utoipa::{IntoParams, ToSchema};
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

type ErrorBody = tradocraft_core::error::ErrorBody;

const MAX_KEY: usize = 64;
const MAX_TEXT: usize = 200;
const MAX_OPTIONS: usize = 200;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum DefinitionKind {
    Number,
    Range,
    Select,
    Text,
}

impl DefinitionKind {
    fn as_str(self) -> &'static str {
        match self {
            DefinitionKind::Number => "number",
            DefinitionKind::Range => "range",
            DefinitionKind::Select => "select",
            DefinitionKind::Text => "text",
        }
    }

    fn parse(s: &str) -> Option<Self> {
        match s {
            "number" => Some(DefinitionKind::Number),
            "range" => Some(DefinitionKind::Range),
            "select" => Some(DefinitionKind::Select),
            "text" => Some(DefinitionKind::Text),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
pub struct SelectOption {
    pub value: String,
    pub label: String,
}

#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct AttributeDefinition {
    pub id: Uuid,
    pub key: String,
    pub label: String,
    pub kind: DefinitionKind,
    pub unit: Option<String>,
    pub options: Vec<SelectOption>,
    /// `product` or a baseline item type code.
    pub scope: String,
    pub sort_order: i32,
    pub active: bool,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct AttributeDefinitionInput {
    /// snake_case: lowercase letter first, then lowercase letters, digits and `_`.
    pub key: String,
    pub label: String,
    pub kind: DefinitionKind,
    #[serde(default)]
    pub unit: Option<String>,
    /// Required (at least one) for `select`, forbidden for the other kinds.
    #[serde(default)]
    pub options: Vec<SelectOption>,
    #[serde(default = "default_scope")]
    pub scope: String,
    #[serde(default)]
    pub sort_order: i32,
    #[serde(default = "default_true")]
    pub active: bool,
}

fn default_scope() -> String {
    "product".into()
}

fn default_true() -> bool {
    true
}

/// A key is snake_case: starts with a lowercase letter, then lowercase letters, digits, `_`.
pub fn validate_key(key: &str) -> Result<(), String> {
    let mut chars = key.chars();
    let first_ok = chars.next().is_some_and(|c| c.is_ascii_lowercase());
    let rest_ok = chars.all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '_');
    if !first_ok || !rest_ok || key.len() > MAX_KEY {
        return Err(format!(
            "key must be snake_case (a-z, 0-9, _; starting with a letter; at most {MAX_KEY} characters)"
        ));
    }
    Ok(())
}

fn required_text(name: &str, value: &str) -> Result<String, String> {
    let v = value.trim();
    if v.is_empty() || v.len() > MAX_TEXT {
        return Err(format!("{name} is required (at most {MAX_TEXT} characters)"));
    }
    Ok(v.to_string())
}

/// Validates and normalises an input (trims text, drops a blank unit).
pub fn validate(input: &AttributeDefinitionInput) -> Result<AttributeDefinitionInput, String> {
    validate_key(&input.key)?;
    let label = required_text("label", &input.label)?;
    let scope = required_text("scope", &input.scope)?;
    let unit = input
        .unit
        .as_deref()
        .map(str::trim)
        .filter(|u| !u.is_empty())
        .map(str::to_string);
    if unit.is_some() && !matches!(input.kind, DefinitionKind::Number | DefinitionKind::Range) {
        return Err("a unit is only allowed for number and range attributes".into());
    }
    let options = match input.kind {
        DefinitionKind::Select => {
            if input.options.is_empty() || input.options.len() > MAX_OPTIONS {
                return Err(format!("a select needs 1 to {MAX_OPTIONS} options"));
            }
            let mut seen = HashSet::new();
            let mut out = Vec::with_capacity(input.options.len());
            for o in &input.options {
                let value = required_text("option value", &o.value)?;
                let label = required_text("option label", &o.label)?;
                if !seen.insert(value.clone()) {
                    return Err(format!("duplicate option value {value}"));
                }
                out.push(SelectOption { value, label });
            }
            out
        }
        _ => {
            if !input.options.is_empty() {
                return Err("options are only allowed for select attributes".into());
            }
            Vec::new()
        }
    };
    Ok(AttributeDefinitionInput {
        key: input.key.clone(),
        label,
        kind: input.kind,
        unit,
        options,
        scope,
        sort_order: input.sort_order,
        active: input.active,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn opt(v: &str) -> SelectOption {
        SelectOption {
            value: v.into(),
            label: v.to_uppercase(),
        }
    }

    fn input(kind: DefinitionKind) -> AttributeDefinitionInput {
        AttributeDefinitionInput {
            key: "dial_size".into(),
            label: "Dial size".into(),
            kind,
            unit: None,
            options: vec![],
            scope: "product".into(),
            sort_order: 0,
            active: true,
        }
    }

    #[test]
    fn key_must_be_snake_case() {
        for ok in ["a", "dial_size", "d090", "bell_2_weight"] {
            assert!(validate_key(ok).is_ok(), "{ok}");
        }
        for bad in ["", "Dial", "1dial", "_x", "dial-size", "dial size", "diaL", "é"] {
            assert!(validate_key(bad).is_err(), "{bad}");
        }
        assert!(validate_key(&"a".repeat(64)).is_ok());
        assert!(validate_key(&"a".repeat(65)).is_err());
    }

    #[test]
    fn plain_kinds_accept_no_options() {
        for k in [DefinitionKind::Number, DefinitionKind::Range, DefinitionKind::Text] {
            assert!(validate(&input(k)).is_ok());
            let mut i = input(k);
            i.options = vec![opt("a")];
            assert!(validate(&i).is_err(), "{k:?} must reject options");
        }
    }

    #[test]
    fn select_needs_unique_nonblank_options() {
        let mut i = input(DefinitionKind::Select);
        assert!(validate(&i).is_err(), "no options");
        i.options = vec![opt("flying"), opt("falling")];
        assert!(validate(&i).is_ok());
        i.options = vec![opt("flying"), opt("flying")];
        assert!(validate(&i).is_err(), "duplicate values");
        i.options = vec![opt(" ")];
        assert!(validate(&i).is_err(), "blank value");
        i.options = vec![SelectOption {
            value: "x".into(),
            label: " ".into(),
        }];
        assert!(validate(&i).is_err(), "blank label");
    }

    #[test]
    fn unit_only_for_number_and_range() {
        for k in [DefinitionKind::Number, DefinitionKind::Range] {
            let mut i = input(k);
            i.unit = Some(" mm ".into());
            assert_eq!(validate(&i).unwrap().unit.as_deref(), Some("mm"));
        }
        let mut i = input(DefinitionKind::Text);
        i.unit = Some("mm".into());
        assert!(validate(&i).is_err());
        let mut i = input(DefinitionKind::Select);
        i.options = vec![opt("a")];
        i.unit = Some("mm".into());
        assert!(validate(&i).is_err());
        // A blank unit counts as none.
        let mut i = input(DefinitionKind::Text);
        i.unit = Some("  ".into());
        assert_eq!(validate(&i).unwrap().unit, None);
    }

    #[test]
    fn label_and_scope_are_required_and_trimmed() {
        let mut i = input(DefinitionKind::Number);
        i.label = "  ".into();
        assert!(validate(&i).is_err());
        let mut i = input(DefinitionKind::Number);
        i.scope = " ".into();
        assert!(validate(&i).is_err());
        i.scope = " bell ".into();
        assert_eq!(validate(&i).unwrap().scope, "bell");
    }

    #[test]
    fn kind_round_trips_through_text() {
        for k in [
            DefinitionKind::Number,
            DefinitionKind::Range,
            DefinitionKind::Select,
            DefinitionKind::Text,
        ] {
            assert_eq!(DefinitionKind::parse(k.as_str()), Some(k));
        }
        assert_eq!(DefinitionKind::parse("boolean"), None);
    }
}
