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
    pub fn as_str(self) -> &'static str {
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
        return Err(format!(
            "{name} is required (at most {MAX_TEXT} characters)"
        ));
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

/// What an attribute with a product-scope definition must look like.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProductRule {
    pub kind: DefinitionKind,
    /// Allowed values for a `select`; empty otherwise.
    pub options: Vec<String>,
}

/// The active product-scope definitions of a company by key, for validating product attributes.
pub async fn product_rules(
    conn: &mut sqlx::PgConnection,
    company_id: Uuid,
) -> AppResult<std::collections::HashMap<String, ProductRule>> {
    let rows: Vec<Row> = sqlx::query_as(&format!(
        "{SELECT} WHERE company_id = $1 AND scope = 'product' AND active"
    ))
    .bind(company_id)
    .fetch_all(conn)
    .await?;
    Ok(rows
        .into_iter()
        .map(Row::into_api)
        .map(|d| {
            let rule = ProductRule {
                kind: d.kind,
                options: d.options.into_iter().map(|o| o.value).collect(),
            };
            (d.key, rule)
        })
        .collect())
}

/// How many definitions of a company have this scope (a baseline item type code).
pub async fn count_in_scope(
    conn: &mut sqlx::PgConnection,
    company_id: Uuid,
    scope: &str,
) -> AppResult<i64> {
    Ok(sqlx::query_scalar(
        "SELECT count(*) FROM products.attribute_definitions WHERE company_id = $1 AND scope = $2",
    )
    .bind(company_id)
    .bind(scope)
    .fetch_one(conn)
    .await?)
}

/// The active definitions of one scope (`product` or a baseline item type code) of a company,
/// in display order.
pub async fn active_for_scope(
    conn: &mut sqlx::PgConnection,
    company_id: Uuid,
    scope: &str,
) -> AppResult<Vec<AttributeDefinition>> {
    let rows: Vec<Row> = sqlx::query_as(&format!(
        "{SELECT} WHERE company_id = $1 AND scope = $2 AND active ORDER BY sort_order, key"
    ))
    .bind(company_id)
    .bind(scope)
    .fetch_all(conn)
    .await?;
    Ok(rows.into_iter().map(Row::into_api).collect())
}

#[derive(FromRow)]
struct Row {
    id: Uuid,
    key: String,
    label: String,
    kind: String,
    unit: Option<String>,
    options: SqlJson<Vec<SelectOption>>,
    scope: String,
    sort_order: i32,
    active: bool,
}

impl Row {
    fn into_api(self) -> AttributeDefinition {
        AttributeDefinition {
            id: self.id,
            key: self.key,
            label: self.label,
            // The table CHECK only admits the four kinds.
            kind: DefinitionKind::parse(&self.kind).unwrap_or(DefinitionKind::Text),
            unit: self.unit,
            options: self.options.0,
            scope: self.scope,
            sort_order: self.sort_order,
            active: self.active,
        }
    }
}

const SELECT: &str = "SELECT id, key, label, kind, unit, options, scope, sort_order, active
                      FROM products.attribute_definitions";

async fn load(db: &sqlx::PgPool, company_id: Uuid, id: Uuid) -> AppResult<AttributeDefinition> {
    sqlx::query_as::<_, Row>(&format!("{SELECT} WHERE id = $1 AND company_id = $2"))
        .bind(id)
        .bind(company_id)
        .fetch_optional(db)
        .await?
        .map(Row::into_api)
        .ok_or(AppError::NotFound("attribute definition"))
}

fn checked(input: &AttributeDefinitionInput) -> AppResult<AttributeDefinitionInput> {
    validate(input).map_err(AppError::Validation)
}

/// How many stored values use this definition: product attributes with its key (scope
/// `product`) or baseline items of that type storing the key. Product attributes are shared master
/// data keyed by `key`. crm depends on this crate, so the baseline table is read here directly
/// rather than through a crm function.
async fn stored_uses(
    conn: &mut sqlx::PgConnection,
    company_id: Uuid,
    scope: &str,
    key: &str,
) -> AppResult<(i64, &'static str)> {
    if scope == "product" {
        Ok((
            sqlx::query_scalar("SELECT count(*) FROM products.product_attributes WHERE key = $1")
                .bind(key)
                .fetch_one(conn)
                .await?,
            "products",
        ))
    } else {
        Ok((
            sqlx::query_scalar(
                "SELECT count(*) FROM crm.opportunity_baseline_items
                 WHERE company_id = $1 AND type_code = $2 AND jsonb_exists(\"values\", $3)",
            )
            .bind(company_id)
            .bind(scope)
            .bind(key)
            .fetch_one(conn)
            .await?,
            "baseline items",
        ))
    }
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct ListQuery {
    /// Only definitions of this scope (`product` or a baseline item type code).
    scope: Option<String>,
}

#[utoipa::path(get, path = "/attribute-definitions", tag = "products", params(ListQuery),
    responses((status = 200, body = Vec<AttributeDefinition>)))]
async fn list_definitions(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(q): Query<ListQuery>,
) -> AppResult<Json<Vec<AttributeDefinition>>> {
    user.require(Permission::ProductsRead)?;
    let rows: Vec<Row> = sqlx::query_as(&format!(
        "{SELECT} WHERE company_id = $1 AND ($2::text IS NULL OR scope = $2)
         ORDER BY scope, sort_order, key"
    ))
    .bind(user.company_id)
    .bind(q.scope.as_deref().map(str::trim))
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows.into_iter().map(Row::into_api).collect()))
}

#[utoipa::path(get, path = "/attribute-definitions/{id}", tag = "products", params(("id" = Uuid, Path)),
    responses((status = 200, body = AttributeDefinition), (status = 404, body = ErrorBody)))]
async fn get_definition(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<AttributeDefinition>> {
    user.require(Permission::ProductsRead)?;
    Ok(Json(load(&state.db, user.company_id, id).await?))
}

#[utoipa::path(post, path = "/attribute-definitions", tag = "products", request_body = AttributeDefinitionInput,
    responses((status = 201, body = AttributeDefinition), (status = 409, body = ErrorBody),
        (status = 422, body = ErrorBody)))]
async fn create_definition(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<AttributeDefinitionInput>,
) -> AppResult<(StatusCode, Json<AttributeDefinition>)> {
    user.require(Permission::ProductsWrite)?;
    let input = checked(&input)?;
    let id = new_id();
    let mut tx = state.db.begin().await?;
    sqlx::query(
        "INSERT INTO products.attribute_definitions
            (id, company_id, key, label, kind, unit, options, scope, sort_order, active)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(&input.key)
    .bind(&input.label)
    .bind(input.kind.as_str())
    .bind(&input.unit)
    .bind(SqlJson(&input.options))
    .bind(&input.scope)
    .bind(input.sort_order)
    .bind(input.active)
    .execute(&mut *tx)
    .await?;
    audit::record(
        &mut tx,
        &user,
        "attribute_definition",
        id,
        "created",
        serde_json::json!({ "key": input.key, "scope": input.scope }),
    )
    .await?;
    tx.commit().await?;
    Ok((
        StatusCode::CREATED,
        Json(load(&state.db, user.company_id, id).await?),
    ))
}

#[utoipa::path(put, path = "/attribute-definitions/{id}", tag = "products", params(("id" = Uuid, Path)),
    request_body = AttributeDefinitionInput,
    responses((status = 200, body = AttributeDefinition), (status = 404, body = ErrorBody),
        (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn update_definition(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<AttributeDefinitionInput>,
) -> AppResult<Json<AttributeDefinition>> {
    user.require(Permission::ProductsWrite)?;
    let input = checked(&input)?;
    let mut tx = state.db.begin().await?;
    let (old_key, old_scope, old_kind): (String, String, String) = sqlx::query_as(
        "SELECT key, scope, kind FROM products.attribute_definitions
         WHERE id = $1 AND company_id = $2 FOR UPDATE",
    )
    .bind(id)
    .bind(user.company_id)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or(AppError::NotFound("attribute definition"))?;
    if old_key != input.key || old_scope != input.scope || old_kind != input.kind.as_str() {
        let (used, what) = stored_uses(&mut tx, user.company_id, &old_scope, &old_key).await?;
        if used > 0 {
            return Err(AppError::Conflict(format!(
                "attribute {old_key} is in use on {used} {what}; its key, scope and kind cannot change"
            )));
        }
    }
    let r = sqlx::query(
        "UPDATE products.attribute_definitions
         SET key = $3, label = $4, kind = $5, unit = $6, options = $7, scope = $8,
             sort_order = $9, active = $10, updated_at = now()
         WHERE id = $1 AND company_id = $2",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(&input.key)
    .bind(&input.label)
    .bind(input.kind.as_str())
    .bind(&input.unit)
    .bind(SqlJson(&input.options))
    .bind(&input.scope)
    .bind(input.sort_order)
    .bind(input.active)
    .execute(&mut *tx)
    .await?;
    if r.rows_affected() == 0 {
        return Err(AppError::NotFound("attribute definition"));
    }
    audit::record(
        &mut tx,
        &user,
        "attribute_definition",
        id,
        "updated",
        serde_json::json!({ "key": input.key }),
    )
    .await?;
    tx.commit().await?;
    Ok(Json(load(&state.db, user.company_id, id).await?))
}

/// Deletes an unused definition. A definition whose key is stored on products (scope `product`) or
/// on baseline items of its type is refused with 409 (deactivate it with `active: false` instead,
/// which keeps the stored values readable).
#[utoipa::path(delete, path = "/attribute-definitions/{id}", tag = "products", params(("id" = Uuid, Path)),
    responses((status = 204), (status = 404, body = ErrorBody), (status = 409, body = ErrorBody)))]
async fn delete_definition(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<StatusCode> {
    user.require(Permission::ProductsWrite)?;
    let mut tx = state.db.begin().await?;
    let (key, scope): (String, String) = sqlx::query_as(
        "SELECT key, scope FROM products.attribute_definitions
         WHERE id = $1 AND company_id = $2 FOR UPDATE",
    )
    .bind(id)
    .bind(user.company_id)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or(AppError::NotFound("attribute definition"))?;
    let (used, what) = stored_uses(&mut tx, user.company_id, &scope, &key).await?;
    if used > 0 {
        return Err(AppError::Conflict(format!(
            "attribute {key} is in use on {used} {what} and cannot be deleted; deactivate it instead"
        )));
    }
    sqlx::query("DELETE FROM products.attribute_definitions WHERE id = $1")
        .bind(id)
        .execute(&mut *tx)
        .await?;
    audit::record(
        &mut tx,
        &user,
        "attribute_definition",
        id,
        "deleted",
        serde_json::json!({ "key": key }),
    )
    .await?;
    tx.commit().await?;
    Ok(StatusCode::NO_CONTENT)
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(list_definitions, create_definition))
        .routes(routes!(
            get_definition,
            update_definition,
            delete_definition
        ))
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
        for bad in [
            "",
            "Dial",
            "1dial",
            "_x",
            "dial-size",
            "dial size",
            "diaL",
            "é",
        ] {
            assert!(validate_key(bad).is_err(), "{bad}");
        }
        assert!(validate_key(&"a".repeat(64)).is_ok());
        assert!(validate_key(&"a".repeat(65)).is_err());
    }

    #[test]
    fn plain_kinds_accept_no_options() {
        for k in [
            DefinitionKind::Number,
            DefinitionKind::Range,
            DefinitionKind::Text,
        ] {
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
