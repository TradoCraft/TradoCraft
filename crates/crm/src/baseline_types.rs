//! Admin-defined baseline item types (ADR 0068): clock dial, bell group, bell ... The `code` of a
//! type is the `scope` of the attribute definitions describing its items and never changes.
//! Reading needs `opportunities.read`; administering needs `products.write`, the permission that
//! also guards the attribute definitions the types are edited together with.

use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::Json;
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection};
use tradocraft_core::{audit, new_id, AppError, AppResult, AppState, CurrentUser, Permission};
use tradocraft_products::attribute_definitions::{count_in_scope, validate_key};
use utoipa::ToSchema;
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

type ErrorBody = tradocraft_core::error::ErrorBody;

const MAX_NAME: usize = 200;
const MAX_PARENTS: usize = 50;

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct BaselineItemType {
    pub id: Uuid,
    /// snake_case; the scope of this type's attribute definitions. Fixed once created.
    pub code: String,
    pub name: String,
    /// Type codes an item of this type may be nested under.
    pub allowed_parent_codes: Vec<String>,
    /// Whether an item of this type may stand at the top level of the baseline.
    pub allow_top_level: bool,
    pub sort_order: i32,
    /// Inactive types take no new items; existing items stay.
    pub active: bool,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct BaselineItemTypeInput {
    pub code: String,
    pub name: String,
    #[serde(default)]
    pub allowed_parent_codes: Vec<String>,
    #[serde(default = "default_true")]
    pub allow_top_level: bool,
    #[serde(default)]
    pub sort_order: i32,
    #[serde(default = "default_true")]
    pub active: bool,
}

/// Everything but the code, which cannot change.
#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct BaselineItemTypeUpdate {
    pub name: String,
    #[serde(default)]
    pub allowed_parent_codes: Vec<String>,
    #[serde(default = "default_true")]
    pub allow_top_level: bool,
    #[serde(default)]
    pub sort_order: i32,
    #[serde(default = "default_true")]
    pub active: bool,
}

fn default_true() -> bool {
    true
}

/// Trims the name and normalises the parent codes (valid keys, sorted, no duplicates). Whether the
/// codes exist is checked against the company's types separately.
pub fn normalise(
    name: &str,
    allowed_parent_codes: &[String],
    allow_top_level: bool,
) -> Result<(String, Vec<String>), String> {
    let name = name.trim();
    if name.is_empty() || name.chars().count() > MAX_NAME {
        return Err(format!("name is required (at most {MAX_NAME} characters)"));
    }
    if allowed_parent_codes.len() > MAX_PARENTS {
        return Err(format!("at most {MAX_PARENTS} allowed parent types"));
    }
    let mut codes: Vec<String> = Vec::with_capacity(allowed_parent_codes.len());
    for c in allowed_parent_codes {
        let c = c.trim();
        validate_key(c).map_err(|e| format!("allowed parent type {c:?}: {e}"))?;
        codes.push(c.to_string());
    }
    codes.sort();
    codes.dedup();
    if codes.is_empty() && !allow_top_level {
        return Err(
            "a type without an allowed parent must be allowed at the top level, or it could never be placed"
                .into(),
        );
    }
    Ok((name.to_string(), codes))
}

const SELECT: &str =
    "SELECT id, code, name, allowed_parent_codes, allow_top_level, sort_order, active
                      FROM crm.baseline_item_types";

async fn load(conn: &mut PgConnection, company_id: Uuid, id: Uuid) -> AppResult<BaselineItemType> {
    sqlx::query_as(&format!("{SELECT} WHERE id = $1 AND company_id = $2"))
        .bind(id)
        .bind(company_id)
        .fetch_optional(conn)
        .await?
        .ok_or(AppError::NotFound("baseline item type"))
}

/// The type with this code in the company, if any.
pub async fn find_by_code(
    conn: &mut PgConnection,
    company_id: Uuid,
    code: &str,
) -> AppResult<Option<BaselineItemType>> {
    Ok(
        sqlx::query_as(&format!("{SELECT} WHERE company_id = $1 AND code = $2"))
            .bind(company_id)
            .bind(code)
            .fetch_optional(conn)
            .await?,
    )
}

/// Every allowed parent code must be a type of the company (or the type itself).
async fn check_parent_codes_exist(
    conn: &mut PgConnection,
    company_id: Uuid,
    own_code: &str,
    codes: &[String],
) -> AppResult<()> {
    let known: Vec<String> =
        sqlx::query_scalar("SELECT code FROM crm.baseline_item_types WHERE company_id = $1")
            .bind(company_id)
            .fetch_all(conn)
            .await?;
    match codes
        .iter()
        .find(|c| c.as_str() != own_code && !known.contains(c))
    {
        Some(c) => Err(AppError::Validation(format!(
            "allowed parent type {c} does not exist"
        ))),
        None => Ok(()),
    }
}

#[utoipa::path(get, path = "/baseline-item-types", tag = "crm",
    responses((status = 200, body = Vec<BaselineItemType>)))]
async fn list_types(
    State(state): State<AppState>,
    user: CurrentUser,
) -> AppResult<Json<Vec<BaselineItemType>>> {
    user.require(Permission::OpportunitiesRead)?;
    Ok(Json(
        sqlx::query_as(&format!(
            "{SELECT} WHERE company_id = $1 ORDER BY sort_order, code"
        ))
        .bind(user.company_id)
        .fetch_all(&state.db)
        .await?,
    ))
}

#[utoipa::path(get, path = "/baseline-item-types/{id}", tag = "crm", params(("id" = Uuid, Path)),
    responses((status = 200, body = BaselineItemType), (status = 404, body = ErrorBody)))]
async fn get_type(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<BaselineItemType>> {
    user.require(Permission::OpportunitiesRead)?;
    let mut conn = state.db.acquire().await?;
    Ok(Json(load(&mut conn, user.company_id, id).await?))
}

#[utoipa::path(post, path = "/baseline-item-types", tag = "crm", request_body = BaselineItemTypeInput,
    responses((status = 201, body = BaselineItemType), (status = 409, body = ErrorBody),
        (status = 422, body = ErrorBody)))]
async fn create_type(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<BaselineItemTypeInput>,
) -> AppResult<(StatusCode, Json<BaselineItemType>)> {
    user.require(Permission::ProductsWrite)?;
    let code = input.code.trim().to_string();
    validate_key(&code).map_err(AppError::Validation)?;
    let (name, parents) = normalise(
        &input.name,
        &input.allowed_parent_codes,
        input.allow_top_level,
    )
    .map_err(AppError::Validation)?;
    let mut tx = state.db.begin().await?;
    check_parent_codes_exist(&mut tx, user.company_id, &code, &parents).await?;
    let id = new_id();
    sqlx::query(
        "INSERT INTO crm.baseline_item_types
            (id, company_id, code, name, allowed_parent_codes, allow_top_level, sort_order, active)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(&code)
    .bind(&name)
    .bind(&parents)
    .bind(input.allow_top_level)
    .bind(input.sort_order)
    .bind(input.active)
    .execute(&mut *tx)
    .await?;
    audit::record(
        &mut tx,
        &user,
        "baseline_item_type",
        id,
        "created",
        serde_json::json!({ "code": code }),
    )
    .await?;
    let t = load(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(t)))
}

#[utoipa::path(put, path = "/baseline-item-types/{id}", tag = "crm", params(("id" = Uuid, Path)),
    request_body = BaselineItemTypeUpdate,
    responses((status = 200, body = BaselineItemType), (status = 404, body = ErrorBody),
        (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn update_type(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<BaselineItemTypeUpdate>,
) -> AppResult<Json<BaselineItemType>> {
    user.require(Permission::ProductsWrite)?;
    let (name, parents) = normalise(
        &input.name,
        &input.allowed_parent_codes,
        input.allow_top_level,
    )
    .map_err(AppError::Validation)?;
    let mut tx = state.db.begin().await?;
    let code: String = sqlx::query_scalar(
        "SELECT code FROM crm.baseline_item_types WHERE id = $1 AND company_id = $2 FOR UPDATE",
    )
    .bind(id)
    .bind(user.company_id)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or(AppError::NotFound("baseline item type"))?;
    check_parent_codes_exist(&mut tx, user.company_id, &code, &parents).await?;
    // Existing items must stay placeable under the new rules.
    let stranded: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM crm.opportunity_baseline_items i
         LEFT JOIN crm.opportunity_baseline_items p ON p.id = i.parent_id
         WHERE i.company_id = $1 AND i.type_code = $2
           AND ((i.parent_id IS NULL AND NOT $3)
                OR (i.parent_id IS NOT NULL AND NOT (p.type_code = ANY($4))))",
    )
    .bind(user.company_id)
    .bind(&code)
    .bind(input.allow_top_level)
    .bind(&parents)
    .fetch_one(&mut *tx)
    .await?;
    if stranded > 0 {
        return Err(AppError::Conflict(format!(
            "{stranded} existing {code} items would no longer fit these placement rules"
        )));
    }
    sqlx::query(
        "UPDATE crm.baseline_item_types
         SET name = $2, allowed_parent_codes = $3, allow_top_level = $4, sort_order = $5,
             active = $6, updated_at = now()
         WHERE id = $1",
    )
    .bind(id)
    .bind(&name)
    .bind(&parents)
    .bind(input.allow_top_level)
    .bind(input.sort_order)
    .bind(input.active)
    .execute(&mut *tx)
    .await?;
    audit::record(
        &mut tx,
        &user,
        "baseline_item_type",
        id,
        "updated",
        serde_json::json!({ "code": code }),
    )
    .await?;
    let t = load(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok(Json(t))
}

/// Deletes an unused type. A type that has items, attribute definitions or that other types allow
/// as a parent is refused with 409 (deactivate it with `active: false` instead).
#[utoipa::path(delete, path = "/baseline-item-types/{id}", tag = "crm", params(("id" = Uuid, Path)),
    responses((status = 204), (status = 404, body = ErrorBody), (status = 409, body = ErrorBody)))]
async fn delete_type(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<StatusCode> {
    user.require(Permission::ProductsWrite)?;
    let mut tx = state.db.begin().await?;
    let code: String = sqlx::query_scalar(
        "SELECT code FROM crm.baseline_item_types WHERE id = $1 AND company_id = $2 FOR UPDATE",
    )
    .bind(id)
    .bind(user.company_id)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or(AppError::NotFound("baseline item type"))?;
    let items: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM crm.opportunity_baseline_items WHERE company_id = $1 AND type_code = $2",
    )
    .bind(user.company_id)
    .bind(&code)
    .fetch_one(&mut *tx)
    .await?;
    let definitions = count_in_scope(&mut tx, user.company_id, &code).await?;
    let parent_of: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM crm.baseline_item_types
         WHERE company_id = $1 AND id <> $2 AND $3 = ANY(allowed_parent_codes)",
    )
    .bind(user.company_id)
    .bind(id)
    .bind(&code)
    .fetch_one(&mut *tx)
    .await?;
    if items + definitions + parent_of > 0 {
        return Err(AppError::Conflict(format!(
            "type {code} is in use ({items} items, {definitions} attribute definitions, \
             allowed as parent by {parent_of} types) and cannot be deleted; deactivate it instead"
        )));
    }
    sqlx::query("DELETE FROM crm.baseline_item_types WHERE id = $1")
        .bind(id)
        .execute(&mut *tx)
        .await?;
    audit::record(
        &mut tx,
        &user,
        "baseline_item_type",
        id,
        "deleted",
        serde_json::json!({ "code": code }),
    )
    .await?;
    tx.commit().await?;
    Ok(StatusCode::NO_CONTENT)
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(list_types, create_type))
        .routes(routes!(get_type, update_type, delete_type))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn s(v: &[&str]) -> Vec<String> {
        v.iter().map(|c| (*c).to_string()).collect()
    }

    #[test]
    fn name_is_trimmed_and_required() {
        assert_eq!(normalise(" Bell ", &[], true).unwrap().0, "Bell");
        assert!(normalise("  ", &[], true).is_err());
        assert!(normalise(&"x".repeat(201), &[], true).is_err());
    }

    #[test]
    fn parent_codes_are_valid_sorted_and_unique() {
        let (_, c) = normalise("x", &s(&["bell_group", " assembly ", "bell_group"]), true).unwrap();
        assert_eq!(c, ["assembly", "bell_group"]);
        assert!(normalise("x", &s(&["Bad Code"]), true).is_err());
        assert!(normalise("x", &s(&[""]), true).is_err());
    }

    #[test]
    fn a_type_must_be_placeable() {
        assert!(normalise("x", &[], false).is_err());
        assert!(normalise("x", &s(&["bell_group"]), false).is_ok());
        assert!(normalise("x", &[], true).is_ok());
    }
}
