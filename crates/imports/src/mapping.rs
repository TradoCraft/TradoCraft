//! Column mappings: which file column feeds which field of the entity. The rules live here once;
//! saving a mapping and starting a job both validate through [`validate`].

use std::collections::HashSet;

use serde::{Deserialize, Serialize};
use tradocraft_core::import::{is_known_field, ImportEntity};
use tradocraft_core::AppError;
use utoipa::ToSchema;

/// Longest name of a saved mapping, in characters.
pub const MAX_NAME: usize = 100;
/// Longest file column name accepted in a mapping, in characters.
pub const MAX_COLUMN: usize = 200;

/// Longest fixed value accepted in a mapping, in characters.
pub const MAX_VALUE: usize = 1000;

/// One field of a mapping, fed by a file column (`column`) or by a fixed value that every row
/// gets (`value`, read like a text cell of the file): exactly one of the two. File columns are
/// compared trimmed and case-insensitively. The old shape `{column, field}` is a pair with a
/// column.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
pub struct ColumnPair {
    /// The column as the file names it.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub column: Option<String>,
    /// A fixed value for the field in every row, e.g. a date or the code of a list.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub value: Option<String>,
    /// The entity's field it feeds.
    pub field: String,
}

impl ColumnPair {
    /// A pair that feeds `field` from the file column `column`.
    pub fn column(column: impl Into<String>, field: impl Into<String>) -> Self {
        ColumnPair {
            column: Some(column.into()),
            value: None,
            field: field.into(),
        }
    }

    /// A pair that gives `field` the fixed `value`.
    pub fn value(value: impl Into<String>, field: impl Into<String>) -> Self {
        ColumnPair {
            column: None,
            value: Some(value.into()),
            field: field.into(),
        }
    }
}

/// Checks a mapping against the entity and returns it with the file column names trimmed: at least
/// one pair, every field a column of the entity, no field twice, no file column twice (trimmed,
/// case-insensitive), no blank or overlong file column, and each pair either a column or a value
/// that is not blank and not overlong.
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
    let known: Vec<&str> = known.iter().map(String::as_str).collect();
    let mut fields = HashSet::new();
    let mut files = HashSet::new();
    let mut clean = Vec::with_capacity(columns.len());
    for pair in columns {
        if !is_known_field(&known, &pair.field) {
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
        match (&pair.column, &pair.value) {
            (Some(column), None) => {
                let column = column.trim();
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
                if !files.insert(column.to_lowercase()) {
                    return Err(AppError::Validation(format!(
                        "the file column '{column}' is mapped twice"
                    )));
                }
                clean.push(ColumnPair::column(column, pair.field.clone()));
            }
            (None, Some(value)) => {
                if value.trim().is_empty() {
                    return Err(AppError::Validation(format!(
                        "the fixed value of '{}' must not be blank",
                        pair.field
                    )));
                }
                if value.chars().count() > MAX_VALUE {
                    return Err(AppError::Validation(format!(
                        "the fixed value of '{}' is longer than {MAX_VALUE} characters",
                        pair.field
                    )));
                }
                clean.push(ColumnPair::value(value.clone(), pair.field.clone()));
            }
            _ => {
                return Err(AppError::Validation(format!(
                    "the field '{}' needs either a file column or a fixed value",
                    pair.field
                )))
            }
        }
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

/// `(a, b)` string pairs as the format layer takes them.
pub type Pairs = Vec<(String, String)>;

/// The pairs as the format layer binds them: `(file column, field)` tuples and `(field, value)`
/// fixed values.
pub fn to_pairs(columns: &[ColumnPair]) -> (Pairs, Pairs) {
    let mut pairs = Vec::new();
    let mut fixed = Vec::new();
    for c in columns {
        match (&c.column, &c.value) {
            (Some(column), _) => pairs.push((column.clone(), c.field.clone())),
            (None, Some(value)) => fixed.push((c.field.clone(), value.clone())),
            (None, None) => {}
        }
    }
    (pairs, fixed)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::registry::entity;

    fn pair(column: &str, field: &str) -> ColumnPair {
        ColumnPair::column(column, field)
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
    fn a_field_takes_a_column_or_a_fixed_value() {
        let prices = entity("zone_prices").unwrap();
        let ok = validate(
            &prices,
            &[
                pair("Article", "product_code"),
                ColumnPair::value("Z1", "zone"),
                ColumnPair::value(" 2027-01-01", "valid_from"),
            ],
        )
        .unwrap();
        // A value is kept as written: it is read like a text cell.
        assert_eq!(ok[2], ColumnPair::value(" 2027-01-01", "valid_from"));
        let (pairs, fixed) = to_pairs(&ok);
        assert_eq!(pairs, [("Article".to_string(), "product_code".to_string())]);
        assert_eq!(fixed.len(), 2);
        let neither = ColumnPair {
            column: None,
            value: None,
            field: "zone".into(),
        };
        assert!(message(validate(&prices, &[neither])).contains("either"));
        let both = ColumnPair {
            column: Some("Zone".into()),
            value: Some("Z1".into()),
            field: "zone".into(),
        };
        assert!(message(validate(&prices, &[both])).contains("either"));
        assert!(message(validate(&prices, &[ColumnPair::value("  ", "zone")])).contains("blank"));
        assert!(message(validate(
            &prices,
            &[ColumnPair::value("x".repeat(MAX_VALUE + 1), "zone")]
        ))
        .contains("longer"));
        assert!(message(validate(
            &prices,
            &[pair("Zone", "zone"), ColumnPair::value("Z1", "zone")]
        ))
        .contains("mapped twice"));
    }

    #[test]
    fn the_old_shape_still_reads_and_a_pair_writes_only_what_it_has() {
        let old: ColumnPair =
            serde_json::from_value(serde_json::json!({"column": "Naam", "field": "name"})).unwrap();
        assert_eq!(old, pair("Naam", "name"));
        assert_eq!(
            serde_json::to_value(ColumnPair::value("Z1", "zone")).unwrap(),
            serde_json::json!({"value": "Z1", "field": "zone"})
        );
        assert_eq!(
            serde_json::to_value(pair("A", "code")).unwrap(),
            serde_json::json!({"column": "A", "field": "code"})
        );
    }

    #[test]
    fn per_language_fields_are_known() {
        let products = entity("products").unwrap();
        assert!(validate(&products, &[pair("Naam FR", "name_fr")]).is_ok());
        assert!(message(validate(&products, &[pair("X", "name_xx")])).contains("not a field"));
    }

    #[test]
    fn names_are_trimmed_and_bounded() {
        assert_eq!(clean_name("  Old ERP ").unwrap(), "Old ERP");
        assert!(clean_name("   ").is_err());
        assert!(clean_name(&"n".repeat(MAX_NAME + 1)).is_err());
        assert!(clean_name(&"n".repeat(MAX_NAME)).is_ok());
    }
}
