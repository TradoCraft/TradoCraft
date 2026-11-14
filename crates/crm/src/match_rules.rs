//! Admin-editable match rules (ADR 0068): a baseline attribute that must fit a product attribute.
//! Reading needs `opportunities.read`; administering needs `products.write`, like the baseline
//! types and attribute definitions the rules refer to. Nothing references a rule, so deleting one
//! is always fine.

use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::Json;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection};
use tradocraft_core::{audit, new_id, AppError, AppResult, AppState, CurrentUser, Permission};
use tradocraft_products::attribute_definitions::{active_for_scope, validate_key, DefinitionKind};
use utoipa::ToSchema;
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::baseline_types;
use crate::matching::{Operator, Rule};

type ErrorBody = tradocraft_core::error::ErrorBody;

const MAX_NAME: usize = 200;

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct MatchRule {
    pub id: Uuid,
    pub name: String,
    /// Code of the baseline item type whose items the rule reads.
    pub baseline_type_code: String,
    /// A `number` attribute of that type.
    pub baseline_attribute_key: String,
    /// A product attribute: `range` for `within_range`, `number` for `at_most` and `at_least`.
    pub product_attribute_key: String,
    #[sqlx(try_from = "String")]
    #[schema(value_type = Operator)]
    pub operator: OperatorColumn,
    pub active: bool,
    pub sort_order: i32,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// The operator as stored; the table CHECK only admits the three known values.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, ToSchema)]
#[serde(transparent)]
pub struct OperatorColumn(pub Operator);

impl TryFrom<String> for OperatorColumn {
    type Error = String;
    fn try_from(s: String) -> Result<Self, String> {
        Operator::parse(&s)
            .map(OperatorColumn)
            .ok_or_else(|| format!("unknown operator {s}"))
    }
}

/// A rule is created and replaced with the same fields.
#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct MatchRuleInput {
    /// Unique per company.
    pub name: String,
    pub baseline_type_code: String,
    pub baseline_attribute_key: String,
    pub product_attribute_key: String,
    pub operator: Operator,
    #[serde(default = "default_true")]
    pub active: bool,
    #[serde(default)]
    pub sort_order: i32,
}

fn default_true() -> bool {
    true
}

impl MatchRule {
    /// The rule as the pure matcher sees it.
    pub fn to_rule(&self) -> Rule {
        Rule {
            name: self.name.clone(),
            baseline_type_code: self.baseline_type_code.clone(),
            baseline_attribute_key: self.baseline_attribute_key.clone(),
            product_attribute_key: self.product_attribute_key.clone(),
            operator: self.operator.0,
            active: self.active,
        }
    }
}

const SELECT: &str = "SELECT id, name, baseline_type_code, baseline_attribute_key,
                             product_attribute_key, operator, active, sort_order, created_at, updated_at
                      FROM crm.match_rules";

/// The company's rules in evaluation order.
pub async fn list_rules(conn: &mut PgConnection, company_id: Uuid) -> AppResult<Vec<MatchRule>> {
    Ok(sqlx::query_as(&format!(
        "{SELECT} WHERE company_id = $1 ORDER BY sort_order, name"
    ))
    .bind(company_id)
    .fetch_all(conn)
    .await?)
}

async fn load(conn: &mut PgConnection, company_id: Uuid, id: Uuid) -> AppResult<MatchRule> {
    sqlx::query_as(&format!("{SELECT} WHERE id = $1 AND company_id = $2"))
        .bind(id)
        .bind(company_id)
        .fetch_optional(conn)
        .await?
        .ok_or(AppError::NotFound("match rule"))
}

/// What the operator needs of the product attribute.
fn product_kind_for(op: Operator) -> DefinitionKind {
    match op {
        Operator::WithinRange => DefinitionKind::Range,
        Operator::AtMost | Operator::AtLeast => DefinitionKind::Number,
    }
}

/// Pure checks: name and key syntax. Whether the keys exist is checked against the definitions.
fn normalise(input: &MatchRuleInput) -> Result<MatchRuleInput, String> {
    let name = input.name.trim();
    if name.is_empty() || name.chars().count() > MAX_NAME {
        return Err(format!("name is required (at most {MAX_NAME} characters)"));
    }
    let (type_code, bk, pk) = (
        input.baseline_type_code.trim(),
        input.baseline_attribute_key.trim(),
        input.product_attribute_key.trim(),
    );
    validate_key(type_code).map_err(|e| format!("baseline_type_code: {e}"))?;
    validate_key(bk).map_err(|e| format!("baseline_attribute_key: {e}"))?;
    validate_key(pk).map_err(|e| format!("product_attribute_key: {e}"))?;
    Ok(MatchRuleInput {
        name: name.to_string(),
        baseline_type_code: type_code.to_string(),
        baseline_attribute_key: bk.to_string(),
        product_attribute_key: pk.to_string(),
        ..input.clone()
    })
}

/// The type must exist, its attribute must be an active `number` definition and the product
/// attribute an active product definition of the kind the operator needs.
async fn check_references(
    conn: &mut PgConnection,
    company_id: Uuid,
    rule: &MatchRuleInput,
) -> AppResult<()> {
    if baseline_types::find_by_code(conn, company_id, &rule.baseline_type_code)
        .await?
        .is_none()
    {
        return Err(AppError::Validation(format!(
            "baseline type {} does not exist",
            rule.baseline_type_code
        )));
    }
    let baseline_defs = active_for_scope(conn, company_id, &rule.baseline_type_code).await?;
    let Some(bdef) = baseline_defs
        .iter()
        .find(|d| d.key == rule.baseline_attribute_key)
    else {
        return Err(AppError::Validation(format!(
            "{} is not an active attribute of baseline type {}",
            rule.baseline_attribute_key, rule.baseline_type_code
        )));
    };
    if bdef.kind != DefinitionKind::Number {
        return Err(AppError::Validation(format!(
            "{} must be a number attribute to be compared",
            rule.baseline_attribute_key
        )));
    }
    let product_defs = active_for_scope(conn, company_id, "product").await?;
    let Some(pdef) = product_defs
        .iter()
        .find(|d| d.key == rule.product_attribute_key)
    else {
        return Err(AppError::Validation(format!(
            "{} is not an active product attribute",
            rule.product_attribute_key
        )));
    };
    let needed = product_kind_for(rule.operator);
    if pdef.kind != needed {
        return Err(AppError::Validation(format!(
            "{} needs a {} product attribute, but {} is a {}",
            rule.operator.as_str(),
            needed.as_str(),
            rule.product_attribute_key,
            pdef.kind.as_str()
        )));
    }
    Ok(())
}

fn name_taken(e: sqlx::Error) -> AppError {
    match &e {
        sqlx::Error::Database(d) if d.is_unique_violation() => {
            AppError::Conflict("a match rule with this name already exists".into())
        }
        _ => e.into(),
    }
}

#[utoipa::path(get, path = "/match-rules", tag = "crm",
    responses((status = 200, body = Vec<MatchRule>)))]
async fn list(State(state): State<AppState>, user: CurrentUser) -> AppResult<Json<Vec<MatchRule>>> {
    user.require(Permission::OpportunitiesRead)?;
    let mut conn = state.db.acquire().await?;
    Ok(Json(list_rules(&mut conn, user.company_id).await?))
}

#[utoipa::path(get, path = "/match-rules/{id}", tag = "crm", params(("id" = Uuid, Path)),
    responses((status = 200, body = MatchRule), (status = 404, body = ErrorBody)))]
async fn get(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<MatchRule>> {
    user.require(Permission::OpportunitiesRead)?;
    let mut conn = state.db.acquire().await?;
    Ok(Json(load(&mut conn, user.company_id, id).await?))
}

#[utoipa::path(post, path = "/match-rules", tag = "crm", request_body = MatchRuleInput,
    responses((status = 201, body = MatchRule), (status = 409, body = ErrorBody),
        (status = 422, body = ErrorBody)))]
async fn create(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<MatchRuleInput>,
) -> AppResult<(StatusCode, Json<MatchRule>)> {
    user.require(Permission::ProductsWrite)?;
    let r = normalise(&input).map_err(AppError::Validation)?;
    let mut tx = state.db.begin().await?;
    check_references(&mut tx, user.company_id, &r).await?;
    let id = new_id();
    sqlx::query(
        "INSERT INTO crm.match_rules
            (id, company_id, name, baseline_type_code, baseline_attribute_key,
             product_attribute_key, operator, active, sort_order)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(&r.name)
    .bind(&r.baseline_type_code)
    .bind(&r.baseline_attribute_key)
    .bind(&r.product_attribute_key)
    .bind(r.operator.as_str())
    .bind(r.active)
    .bind(r.sort_order)
    .execute(&mut *tx)
    .await
    .map_err(name_taken)?;
    audit::record(
        &mut tx,
        &user,
        "match_rule",
        id,
        "created",
        serde_json::json!({ "name": r.name }),
    )
    .await?;
    let rule = load(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(rule)))
}

#[utoipa::path(put, path = "/match-rules/{id}", tag = "crm", params(("id" = Uuid, Path)),
    request_body = MatchRuleInput,
    responses((status = 200, body = MatchRule), (status = 404, body = ErrorBody),
        (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn update(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<MatchRuleInput>,
) -> AppResult<Json<MatchRule>> {
    user.require(Permission::ProductsWrite)?;
    let r = normalise(&input).map_err(AppError::Validation)?;
    let mut tx = state.db.begin().await?;
    load(&mut tx, user.company_id, id).await?;
    check_references(&mut tx, user.company_id, &r).await?;
    sqlx::query(
        "UPDATE crm.match_rules
         SET name = $2, baseline_type_code = $3, baseline_attribute_key = $4,
             product_attribute_key = $5, operator = $6, active = $7, sort_order = $8,
             updated_at = now()
         WHERE id = $1",
    )
    .bind(id)
    .bind(&r.name)
    .bind(&r.baseline_type_code)
    .bind(&r.baseline_attribute_key)
    .bind(&r.product_attribute_key)
    .bind(r.operator.as_str())
    .bind(r.active)
    .bind(r.sort_order)
    .execute(&mut *tx)
    .await
    .map_err(name_taken)?;
    audit::record(
        &mut tx,
        &user,
        "match_rule",
        id,
        "updated",
        serde_json::json!({ "name": r.name }),
    )
    .await?;
    let rule = load(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok(Json(rule))
}

#[utoipa::path(delete, path = "/match-rules/{id}", tag = "crm", params(("id" = Uuid, Path)),
    responses((status = 204), (status = 404, body = ErrorBody)))]
async fn delete(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<StatusCode> {
    user.require(Permission::ProductsWrite)?;
    let mut tx = state.db.begin().await?;
    let rule = load(&mut tx, user.company_id, id).await?;
    sqlx::query("DELETE FROM crm.match_rules WHERE id = $1")
        .bind(id)
        .execute(&mut *tx)
        .await?;
    audit::record(
        &mut tx,
        &user,
        "match_rule",
        id,
        "deleted",
        serde_json::json!({ "name": rule.name }),
    )
    .await?;
    tx.commit().await?;
    Ok(StatusCode::NO_CONTENT)
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(list, create))
        .routes(routes!(get, update, delete))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn input(name: &str, t: &str, b: &str, p: &str) -> MatchRuleInput {
        MatchRuleInput {
            name: name.into(),
            baseline_type_code: t.into(),
            baseline_attribute_key: b.into(),
            product_attribute_key: p.into(),
            operator: Operator::AtMost,
            active: true,
            sort_order: 0,
        }
    }

    #[test]
    fn names_and_keys_are_trimmed_and_checked() {
        let r = normalise(&input(" Rule ", " bell ", " weight_kg ", " max_kg ")).unwrap();
        assert_eq!(
            (
                r.name.as_str(),
                r.baseline_type_code.as_str(),
                r.baseline_attribute_key.as_str(),
                r.product_attribute_key.as_str()
            ),
            ("Rule", "bell", "weight_kg", "max_kg")
        );
        assert!(normalise(&input(" ", "bell", "a", "b")).is_err());
        assert!(normalise(&input(&"x".repeat(201), "bell", "a", "b")).is_err());
        assert!(normalise(&input("r", "Bad Code", "a", "b")).is_err());
        assert!(normalise(&input("r", "bell", "1a", "b")).is_err());
        assert!(normalise(&input("r", "bell", "a", "")).is_err());
    }

    #[test]
    fn operators_need_the_matching_product_kind() {
        assert_eq!(
            product_kind_for(Operator::WithinRange),
            DefinitionKind::Range
        );
        assert_eq!(product_kind_for(Operator::AtMost), DefinitionKind::Number);
        assert_eq!(product_kind_for(Operator::AtLeast), DefinitionKind::Number);
    }
}
