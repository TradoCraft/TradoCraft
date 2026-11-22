//! Product families: groups of products used for rebates, bulk price changes and reporting.

use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::Json;
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use tradocraft_core::{audit, new_id, AppError, AppResult, AppState, CurrentUser, Permission};
use utoipa::ToSchema;
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct ProductFamily {
    pub id: Uuid,
    pub code: String,
    pub name: String,
    pub active: bool,
    pub product_count: i64,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct ProductFamilyInput {
    pub code: String,
    pub name: String,
    #[serde(default = "default_true")]
    pub active: bool,
}

fn default_true() -> bool {
    true
}

const SELECT: &str = "SELECT f.id, f.code, f.name, f.active,
        (SELECT count(*) FROM products.products p WHERE p.family_id = f.id) AS product_count
     FROM products.product_families f";

async fn load(db: &sqlx::PgPool, id: Uuid) -> AppResult<ProductFamily> {
    sqlx::query_as(sqlx::AssertSqlSafe(format!("{SELECT} WHERE f.id = $1")))
        .bind(id)
        .fetch_optional(db)
        .await?
        .ok_or(AppError::NotFound("product family"))
}

fn validate(input: &ProductFamilyInput) -> AppResult<()> {
    if input.code.trim().is_empty() || input.name.trim().is_empty() {
        return Err(AppError::Validation("code and name are required".into()));
    }
    Ok(())
}

#[utoipa::path(get, path = "/product-families", tag = "products",
    responses((status = 200, body = Vec<ProductFamily>)))]
async fn list_families(
    State(state): State<AppState>,
    user: CurrentUser,
) -> AppResult<Json<Vec<ProductFamily>>> {
    user.require(Permission::ProductsRead)?;
    Ok(Json(
        sqlx::query_as(sqlx::AssertSqlSafe(format!("{SELECT} ORDER BY f.code")))
            .fetch_all(&state.db)
            .await?,
    ))
}

#[utoipa::path(post, path = "/product-families", tag = "products", request_body = ProductFamilyInput,
    responses((status = 201, body = ProductFamily), (status = 409, body = tradocraft_core::error::ErrorBody)))]
async fn create_family(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<ProductFamilyInput>,
) -> AppResult<(StatusCode, Json<ProductFamily>)> {
    user.require(Permission::ProductsWrite)?;
    validate(&input)?;
    let id = new_id();
    let mut tx = state.db.begin().await?;
    sqlx::query(
        "INSERT INTO products.product_families (id, code, name, active) VALUES ($1, $2, $3, $4)",
    )
    .bind(id)
    .bind(input.code.trim())
    .bind(input.name.trim())
    .bind(input.active)
    .execute(&mut *tx)
    .await?;
    audit::record(
        &mut tx,
        &user,
        "product_family",
        id,
        "created",
        serde_json::json!({ "code": input.code }),
    )
    .await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(load(&state.db, id).await?)))
}

#[utoipa::path(put, path = "/product-families/{id}", tag = "products", params(("id" = Uuid, Path)),
    request_body = ProductFamilyInput, responses((status = 200, body = ProductFamily)))]
async fn update_family(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<ProductFamilyInput>,
) -> AppResult<Json<ProductFamily>> {
    user.require(Permission::ProductsWrite)?;
    validate(&input)?;
    let mut tx = state.db.begin().await?;
    let r = sqlx::query(
        "UPDATE products.product_families SET code = $2, name = $3, active = $4 WHERE id = $1",
    )
    .bind(id)
    .bind(input.code.trim())
    .bind(input.name.trim())
    .bind(input.active)
    .execute(&mut *tx)
    .await?;
    if r.rows_affected() == 0 {
        return Err(AppError::NotFound("product family"));
    }
    audit::record(
        &mut tx,
        &user,
        "product_family",
        id,
        "updated",
        serde_json::json!({}),
    )
    .await?;
    tx.commit().await?;
    Ok(Json(load(&state.db, id).await?))
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(list_families, create_family))
        .routes(routes!(update_family))
}
