//! Column mappings: which file column feeds which field of the entity. The rules live here once;
//! saving a mapping and starting a job both validate through [`validate`].

use std::collections::HashSet;

use serde::{Deserialize, Serialize};
use tradocraft_core::import::ImportEntity;
use tradocraft_core::AppError;
use utoipa::ToSchema;

/// Longest name of a saved mapping, in characters.
pub const MAX_NAME: usize = 100;
/// Longest file column name accepted in a mapping, in characters.
pub const MAX_COLUMN: usize = 200;

/// One `file column -> field` pair. File columns are compared trimmed and case-insensitively.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
pub struct ColumnPair {
    /// The column as the file names it.
    pub column: String,
    /// The entity's field it feeds.
    pub field: String,
}

/// Checks a mapping against the entity and returns it with the file column names trimmed: at least
/// one pair, every field a column of the entity, no field twice, no file column twice (trimmed,
/// case-insensitive), no blank or overlong file column.
pub fn validate(
    entity: &ImportEntity,
    columns: &[ColumnPair],
) -> Result<Vec<ColumnPair>, AppError> {
    if columns.is_empty() {
        return Err(AppError::Validation(
            "a mapping needs at least one column".into(),
        ));
    }
    let known = entity.header();
    let mut fields = HashSet::new();
    let mut files = HashSet::new();
    let mut clean = Vec::with_capacity(columns.len());
    for pair in columns {
        let column = pair.column.trim();
        if column.is_empty() {
            return Err(AppError::Validation(
                "a file column name must not be blank".into(),
            ));
        }
        if column.chars().count() > MAX_COLUMN {
            return Err(AppError::Validation(format!(
                "a file column name is longer than {MAX_COLUMN} characters"
            )));
        }
        if !known.contains(&pair.field.as_str()) {
            return Err(AppError::Validation(format!(
                "'{}' is not a field of {}",
                pair.field,
                entity.describe().key
            )));
        }
        if !fields.insert(pair.field.as_str()) {
            return Err(AppError::Validation(format!(
                "the field '{}' is mapped twice",
                pair.field
            )));
        }
        if !files.insert(column.to_lowercase()) {
            return Err(AppError::Validation(format!(
                "the file column '{column}' is mapped twice"
            )));
        }
        clean.push(ColumnPair {
            column: column.to_string(),
            field: pair.field.clone(),
        });
    }
    Ok(clean)
}

/// The name of a saved mapping, trimmed; blank or overlong names are refused.
pub fn clean_name(name: &str) -> Result<String, AppError> {
    let name = name.trim();
    if name.is_empty() {
        return Err(AppError::Validation("the mapping needs a name".into()));
    }
    if name.chars().count() > MAX_NAME {
        return Err(AppError::Validation(format!(
            "the name is longer than {MAX_NAME} characters"
        )));
    }
    Ok(name.to_string())
}

/// The pairs as the `(file column, field)` tuples the format layer binds with.
pub fn to_pairs(columns: &[ColumnPair]) -> Vec<(String, String)> {
    columns
        .iter()
        .map(|c| (c.column.clone(), c.field.clone()))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::registry::entity;

    fn pair(column: &str, field: &str) -> ColumnPair {
        ColumnPair {
            column: column.into(),
            field: field.into(),
        }
    }

    fn message(r: Result<Vec<ColumnPair>, AppError>) -> String {
        r.unwrap_err().to_string()
    }

    #[test]
    fn a_mapping_is_checked_against_the_entity() {
        let customers = entity("customers").unwrap();
        let ok = validate(
            &customers,
            &[pair("  Klantnr ", "code"), pair("Naam", "name")],
        )
        .unwrap();
        assert_eq!(ok[0], pair("Klantnr", "code"));
        assert!(message(validate(&customers, &[])).contains("at least one"));
        assert!(message(validate(&customers, &[pair("A", "nope")])).contains("not a field"));
        assert!(message(validate(&customers, &[pair("  ", "code")])).contains("blank"));
        assert!(message(validate(
            &customers,
            &[pair("A", "code"), pair("B", "code")]
        ))
        .contains("mapped twice"));
        assert!(message(validate(
            &customers,
            &[pair("Name ", "code"), pair(" name", "name")]
        ))
        .contains("file column 'name' is mapped twice"));
        assert!(
            message(validate(&customers, &[pair(&"x".repeat(201), "code")])).contains("longer")
        );
    }

    #[test]
    fn names_are_trimmed_and_bounded() {
        assert_eq!(clean_name("  Old ERP ").unwrap(), "Old ERP");
        assert!(clean_name("   ").is_err());
        assert!(clean_name(&"n".repeat(MAX_NAME + 1)).is_err());
        assert!(clean_name(&"n".repeat(MAX_NAME)).is_ok());
    }
}
