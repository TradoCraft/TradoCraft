//! Packaging categories: admin-managed master data. A category can flag its products as needing
//! a manual shipping quote (large flat panels, pallets, ...); see the shipping workflow in sales.

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
pub struct PackagingCategory {
    pub id: Uuid,
    pub code: String,
    pub name: String,
    pub description: String,
    /// Quotations with products in this category wait for a shipping quote from a person.
    pub requires_shipping_quote: bool,
    pub active: bool,
    pub product_count: i64,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct PackagingCategoryInput {
    pub code: String,
    pub name: String,
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    pub requires_shipping_quote: bool,
    #[serde(default = "default_true")]
    pub active: bool,
}

fn default_true() -> bool {
    true
}

const SELECT: &str = "SELECT c.id, c.code, c.name, c.description, c.requires_shipping_quote, c.active,
        (SELECT count(*) FROM products.products p WHERE p.packaging_category_id = c.id) AS product_count
     FROM products.packaging_categories c";

async fn load(db: &sqlx::PgPool, id: Uuid) -> AppResult<PackagingCategory> {
    sqlx::query_as(sqlx::AssertSqlSafe(format!("{SELECT} WHERE c.id = $1")))
        .bind(id)
        .fetch_optional(db)
        .await?
        .ok_or(AppError::NotFound("packaging category"))
}

fn validate(input: &PackagingCategoryInput) -> AppResult<()> {
    if input.code.trim().is_empty() || input.name.trim().is_empty() {
        return Err(AppError::Validation("code and name are required".into()));
    }
    Ok(())
}

#[utoipa::path(get, path = "/packaging-categories", tag = "products",
    responses((status = 200, body = Vec<PackagingCategory>)))]
async fn list_packaging(
    State(state): State<AppState>,
    user: CurrentUser,
) -> AppResult<Json<Vec<PackagingCategory>>> {
    user.require(Permission::ProductsRead)?;
    Ok(Json(
        sqlx::query_as(sqlx::AssertSqlSafe(format!("{SELECT} ORDER BY c.code")))
            .fetch_all(&state.db)
            .await?,
    ))
}

#[utoipa::path(post, path = "/packaging-categories", tag = "products", request_body = PackagingCategoryInput,
    responses((status = 201, body = PackagingCategory), (status = 409, body = tradocraft_core::error::ErrorBody)))]
async fn create_packaging(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<PackagingCategoryInput>,
) -> AppResult<(StatusCode, Json<PackagingCategory>)> {
    user.require(Permission::ProductsWrite)?;
    validate(&input)?;
    let id = new_id();
    let mut tx = state.db.begin().await?;
    sqlx::query(
        "INSERT INTO products.packaging_categories (id, code, name, description, requires_shipping_quote, active)
         VALUES ($1, $2, $3, $4, $5, $6)",
    )
    .bind(id)
    .bind(input.code.trim())
    .bind(input.name.trim())
    .bind(input.description.trim())
    .bind(input.requires_shipping_quote)
    .bind(input.active)
    .execute(&mut *tx)
    .await?;
    audit::record(
        &mut tx,
        &user,
        "packaging_category",
        id,
        "created",
        serde_json::json!({ "code": input.code }),
    )
    .await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(load(&state.db, id).await?)))
}

#[utoipa::path(put, path = "/packaging-categories/{id}", tag = "products", params(("id" = Uuid, Path)),
    request_body = PackagingCategoryInput,
    responses((status = 200, body = PackagingCategory), (status = 409, body = tradocraft_core::error::ErrorBody)))]
async fn update_packaging(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<PackagingCategoryInput>,
) -> AppResult<Json<PackagingCategory>> {
    user.require(Permission::ProductsWrite)?;
    validate(&input)?;
    let mut tx = state.db.begin().await?;
    let r = sqlx::query(
        "UPDATE products.packaging_categories
         SET code = $2, name = $3, description = $4, requires_shipping_quote = $5, active = $6, updated_at = now()
         WHERE id = $1",
    )
    .bind(id)
    .bind(input.code.trim())
    .bind(input.name.trim())
    .bind(input.description.trim())
    .bind(input.requires_shipping_quote)
    .bind(input.active)
    .execute(&mut *tx)
    .await?;
    if r.rows_affected() == 0 {
        return Err(AppError::NotFound("packaging category"));
    }
    audit::record(
        &mut tx,
        &user,
        "packaging_category",
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
        .routes(routes!(list_packaging, create_packaging))
        .routes(routes!(update_packaging))
}
