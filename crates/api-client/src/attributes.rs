//! Attribute definitions (`/api/v1/attribute-definitions`, ADR 0068): the admin-tunable fields
//! products (and site baseline items) can carry, plus the read-only list of baseline item types
//! that serve as their scopes.

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::client::Client;
use crate::error::ApiError;

/// The kind of value an attribute holds (OpenAPI schema `DefinitionKind`).
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DefinitionKind {
    #[default]
    Number,
    Range,
    Select,
    Text,
    Boolean,
}

impl DefinitionKind {
    pub const ALL: [DefinitionKind; 5] = [
        Self::Number,
        Self::Range,
        Self::Select,
        Self::Text,
        Self::Boolean,
    ];

    /// The wire name (`number`, `range`, ...).
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Number => "number",
            Self::Range => "range",
            Self::Select => "select",
            Self::Text => "text",
            Self::Boolean => "boolean",
        }
    }

    pub fn parse(s: &str) -> Option<Self> {
        Self::ALL.into_iter().find(|k| k.as_str() == s)
    }
}

/// One choice of a `select` attribute (OpenAPI schema `SelectOption`).
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct SelectOption {
    pub value: String,
    pub label: String,
}

/// An attribute definition (OpenAPI schema `AttributeDefinition`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AttributeDefinition {
    pub id: Uuid,
    pub key: String,
    pub label: String,
    pub kind: DefinitionKind,
    #[serde(default)]
    pub unit: Option<String>,
    pub options: Vec<SelectOption>,
    /// `product` or a baseline item type code.
    pub scope: String,
    pub sort_order: i32,
    pub active: bool,
}

/// Create/update body of a definition (OpenAPI schema `AttributeDefinitionInput`).
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct AttributeDefinitionInput {
    pub key: String,
    pub label: String,
    pub kind: DefinitionKind,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub unit: Option<String>,
    /// Required (at least one) for `select`, forbidden for the other kinds.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub options: Option<Vec<SelectOption>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub scope: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sort_order: Option<i32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub active: Option<bool>,
}

/// A kind of thing recorded at a customer's site (OpenAPI schema `BaselineItemType`); only read
/// here, for the scopes of attribute definitions.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct BaselineItemType {
    pub id: Uuid,
    pub code: String,
    pub name: String,
    pub allowed_parent_codes: Vec<String>,
    pub allow_top_level: bool,
    pub sort_order: i32,
    pub active: bool,
}

impl Client {
    /// Every attribute definition (`GET /api/v1/attribute-definitions`).
    pub async fn list_attribute_definitions(&self) -> Result<Vec<AttributeDefinition>, ApiError> {
        self.get_json("/api/v1/attribute-definitions", &()).await
    }

    /// Adds a definition (`POST /api/v1/attribute-definitions`).
    pub async fn create_attribute_definition(
        &self,
        req: &AttributeDefinitionInput,
    ) -> Result<AttributeDefinition, ApiError> {
        self.post_json("/api/v1/attribute-definitions", req).await
    }

    /// Changes a definition (`PUT /api/v1/attribute-definitions/{id}`).
    pub async fn update_attribute_definition(
        &self,
        id: Uuid,
        req: &AttributeDefinitionInput,
    ) -> Result<AttributeDefinition, ApiError> {
        self.put_json(&format!("/api/v1/attribute-definitions/{id}"), req)
            .await
    }

    /// Deletes a definition (`DELETE /api/v1/attribute-definitions/{id}`); 409 while in use.
    pub async fn delete_attribute_definition(&self, id: Uuid) -> Result<(), ApiError> {
        self.delete_empty(&format!("/api/v1/attribute-definitions/{id}"))
            .await
    }

    /// The baseline item types (`GET /api/v1/baseline-item-types`).
    pub async fn list_baseline_item_types(&self) -> Result<Vec<BaselineItemType>, ApiError> {
        self.get_json("/api/v1/baseline-item-types", &()).await
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn kinds_round_trip_and_input_skips_unset_fields() {
        for k in DefinitionKind::ALL {
            assert_eq!(DefinitionKind::parse(k.as_str()), Some(k));
            assert_eq!(
                serde_json::to_string(&k).unwrap(),
                format!("\"{}\"", k.as_str())
            );
        }
        let input = AttributeDefinitionInput {
            key: "width".into(),
            label: "Width".into(),
            kind: DefinitionKind::Number,
            ..AttributeDefinitionInput::default()
        };
        assert_eq!(
            serde_json::to_string(&input).unwrap(),
            r#"{"key":"width","label":"Width","kind":"number"}"#
        );
    }
}
