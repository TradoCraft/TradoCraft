//! Product names and descriptions per language (ADR 0033).
//!
//! Products are shared master data, so translations have no `company_id` either. Sales takes the
//! name in the customer's language when a quotation line is priced ([`names_in`]) and falls back to
//! the base name of the product.

use std::collections::HashMap;

use axum::extract::{Path, State};
use axum::Json;
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgExecutor};
use tradocraft_core::{audit, AppError, AppResult, AppState, CurrentUser, Permission};
use utoipa::ToSchema;
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize, FromRow, ToSchema)]
pub struct ProductTranslation {
    /// ISO 639-1 code in lower case, e.g. `nl`, `fr`, `de`.
    pub language: String,
    pub name: String,
    #[serde(default)]
    pub description: String,
}

/// The translated names of `product_ids` in `language`; products without one are absent.
pub async fn names_in<'e>(
    db: impl PgExecutor<'e>,
    product_ids: &[Uuid],
    language: &str,
) -> AppResult<HashMap<Uuid, String>> {
    let rows: Vec<(Uuid, String)> = sqlx::query_as(
        "SELECT product_id, name FROM products.product_translations
         WHERE product_id = ANY($1) AND language = $2",
    )
    .bind(product_ids)
    .bind(language.trim().to_lowercase())
    .fetch_all(db)
    .await?;
    Ok(rows.into_iter().collect())
}

async fn ensure_product<'e>(db: impl PgExecutor<'e>, id: Uuid) -> AppResult<()> {
    let exists: bool =
        sqlx::query_scalar("SELECT EXISTS (SELECT 1 FROM products.products WHERE id = $1)")
            .bind(id)
            .fetch_one(db)
            .await?;
    if exists {
        Ok(())
    } else {
        Err(AppError::NotFound("product"))
    }
}

async fn load(db: &sqlx::PgPool, id: Uuid) -> AppResult<Vec<ProductTranslation>> {
    Ok(sqlx::query_as(
        "SELECT language::text AS language, name, description FROM products.product_translations
         WHERE product_id = $1 ORDER BY language",
    )
    .bind(id)
    .fetch_all(db)
    .await?)
}

/// The names and descriptions of a product in other languages.
#[utoipa::path(get, path = "/products/{id}/translations", tag = "products", params(("id" = Uuid, Path)),
    responses((status = 200, body = Vec<ProductTranslation>), (status = 404, body = tradocraft_core::error::ErrorBody)))]
async fn list_translations(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<Vec<ProductTranslation>>> {
    user.require(Permission::ProductsRead)?;
    ensure_product(&state.db, id).await?;
    Ok(Json(load(&state.db, id).await?))
}

/// Replaces all translations of a product with the given list (one entry per language).
/// Quotations already priced keep the name they were priced with.
#[utoipa::path(put, path = "/products/{id}/translations", tag = "products", params(("id" = Uuid, Path)),
    request_body = Vec<ProductTranslation>,
    responses((status = 200, body = Vec<ProductTranslation>), (status = 404, body = tradocraft_core::error::ErrorBody),
        (status = 422, body = tradocraft_core::error::ErrorBody)))]
async fn replace_translations(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<Vec<ProductTranslation>>,
) -> AppResult<Json<Vec<ProductTranslation>>> {
    user.require(Permission::ProductsWrite)?;
    let mut seen: Vec<String> = Vec::new();
    for t in &input {
        let lang = t.language.trim().to_lowercase();
        if lang.len() != 2 || !lang.chars().all(|c| c.is_ascii_lowercase()) {
            return Err(AppError::Validation(format!(
                "language '{}' must be a 2-letter code",
                t.language
            )));
        }
        if t.name.trim().is_empty() {
            return Err(AppError::Validation(format!(
                "the name in '{lang}' is required"
            )));
        }
        if seen.contains(&lang) {
            return Err(AppError::Validation(format!(
                "language '{lang}' is given twice"
            )));
        }
        seen.push(lang);
    }
    let mut tx = state.db.begin().await?;
    // Lock the product as an import does before it writes translations, so the two cannot
    // interleave. Products are shared master data: there is no company to scope by.
    let locked: Option<Uuid> =
        sqlx::query_scalar("SELECT id FROM products.products WHERE id = $1 FOR UPDATE")
            .bind(id)
            .fetch_optional(&mut *tx)
            .await?;
    if locked.is_none() {
        return Err(AppError::NotFound("product"));
    }
    sqlx::query("DELETE FROM products.product_translations WHERE product_id = $1")
        .bind(id)
        .execute(&mut *tx)
        .await?;
    for t in &input {
        sqlx::query(
            "INSERT INTO products.product_translations (product_id, language, name, description)
             VALUES ($1, $2, $3, $4)",
        )
        .bind(id)
        .bind(t.language.trim().to_lowercase())
        .bind(t.name.trim())
        .bind(t.description.trim())
        .execute(&mut *tx)
        .await?;
    }
    audit::record(
        &mut tx,
        &user,
        "product",
        id,
        "translations_replaced",
        serde_json::json!({ "languages": seen }),
    )
    .await?;
    tx.commit().await?;
    Ok(Json(load(&state.db, id).await?))
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new().routes(routes!(list_translations, replace_translations))
}
