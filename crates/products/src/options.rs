//! Options of a product (ADR 0037): products that are offered with it on a quotation. A required
//! option is added to the quotation together with its parent; the others are offered by the app.
//!
//! Options live in their own table, separate from `product_relations` (compatibility and
//! suggestion rules), so the relation evaluation is not affected.

use std::collections::HashMap;

use axum::extract::{Path, State};
use axum::Json;
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgExecutor};
use tradocraft_core::{audit, new_id, AppError, AppResult, AppState, CurrentUser, Permission};
use utoipa::ToSchema;
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

/// An option of a product, with the option product's code and name.
#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct ProductOption {
    pub option_product_id: Uuid,
    pub option_code: String,
    pub option_name: String,
    /// Quantity of the option per unit of the parent.
    #[schema(value_type = String, example = "1")]
    pub default_quantity: Decimal,
    /// Added to a quotation automatically together with the parent.
    pub required: bool,
    pub sort_order: i32,
    pub active: bool,
    /// Whether the option product itself is active; inactive ones cannot be added to quotations.
    pub option_active: bool,
}

/// One option as set from the product screen.
#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct ProductOptionInput {
    pub option_product_id: Uuid,
    #[serde(default = "one")]
    #[schema(value_type = Option<String>, example = "1")]
    pub default_quantity: Decimal,
    #[serde(default)]
    pub required: bool,
    /// Defaults to the position in the list.
    pub sort_order: Option<i32>,
    #[serde(default = "yes")]
    pub active: bool,
}

/// Serde default for the quantity of an option.
fn one() -> Decimal {
    Decimal::ONE
}
/// Serde default for the active flag of an option.
fn yes() -> bool {
    true
}

/// The columns and join shared by the option queries.
const SELECT: &str = "SELECT o.option_product_id, p.code AS option_code, p.name AS option_name,
        o.default_quantity, o.required, o.sort_order, o.active, p.active AS option_active
    FROM products.product_options o JOIN products.products p ON p.id = o.option_product_id";

/// All options of a product (also the inactive ones), in display order.
async fn load<'e>(db: impl PgExecutor<'e>, product_id: Uuid) -> AppResult<Vec<ProductOption>> {
    Ok(sqlx::query_as(sqlx::AssertSqlSafe(format!(
        "{SELECT} WHERE o.parent_product_id = $1 ORDER BY o.sort_order, p.code"
    )))
    .bind(product_id)
    .fetch_all(db)
    .await?)
}

/// The active, required options of each of `product_ids` that have any, in display order. Used by
/// sales to add them as option lines.
pub async fn required_options<'e>(
    db: impl PgExecutor<'e>,
    product_ids: &[Uuid],
) -> AppResult<HashMap<Uuid, Vec<ProductOption>>> {
    #[derive(FromRow)]
    struct Row {
        parent_product_id: Uuid,
        #[sqlx(flatten)]
        option: ProductOption,
    }
    let rows: Vec<Row> = sqlx::query_as(
        "SELECT o.parent_product_id, o.option_product_id, p.code AS option_code, p.name AS option_name,
                o.default_quantity, o.required, o.sort_order, o.active, p.active AS option_active
         FROM products.product_options o JOIN products.products p ON p.id = o.option_product_id
         WHERE o.parent_product_id = ANY($1) AND o.required AND o.active AND p.active
         ORDER BY o.sort_order, p.code",
    )
    .bind(product_ids)
    .fetch_all(db)
    .await?;
    let mut out: HashMap<Uuid, Vec<ProductOption>> = HashMap::new();
    for r in rows {
        out.entry(r.parent_product_id).or_default().push(r.option);
    }
    Ok(out)
}

/// The options of a product, in display order.
#[utoipa::path(get, path = "/products/{id}/options", tag = "products", params(("id" = Uuid, Path)),
    responses((status = 200, body = Vec<ProductOption>), (status = 404, body = tradocraft_core::error::ErrorBody)))]
async fn list_options(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<Vec<ProductOption>>> {
    user.require(Permission::ProductsRead)?;
    crate::get_product(&state.db, id).await?;
    Ok(Json(load(&state.db, id).await?))
}

/// Replaces the options of a product with the given list. Quotations already made keep their lines.
#[utoipa::path(put, path = "/products/{id}/options", tag = "products", params(("id" = Uuid, Path)),
    request_body = Vec<ProductOptionInput>,
    responses((status = 200, body = Vec<ProductOption>), (status = 404, body = tradocraft_core::error::ErrorBody),
        (status = 422, body = tradocraft_core::error::ErrorBody)))]
async fn replace_options(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<Vec<ProductOptionInput>>,
) -> AppResult<Json<Vec<ProductOption>>> {
    user.require(Permission::ProductsWrite)?;
    let mut seen: Vec<Uuid> = Vec::new();
    for o in &input {
        if o.option_product_id == id {
            return Err(AppError::Validation(
                "a product cannot be an option of itself".into(),
            ));
        }
        // The column keeps four decimals: a value that rounds to zero would be stored as 0.
        if o.default_quantity.round_dp(4) <= Decimal::ZERO
            || o.default_quantity >= Decimal::from(1_000_000)
        {
            return Err(AppError::Validation(
                "default_quantity must be at least 0.0001 and below 1000000".into(),
            ));
        }
        if seen.contains(&o.option_product_id) {
            return Err(AppError::Validation(
                "a product is listed twice as an option".into(),
            ));
        }
        seen.push(o.option_product_id);
    }
    let mut tx = state.db.begin().await?;
    crate::get_product(&mut *tx, id).await?;
    let known: i64 =
        sqlx::query_scalar("SELECT count(*) FROM products.products WHERE id = ANY($1)")
            .bind(&seen)
            .fetch_one(&mut *tx)
            .await?;
    if known != seen.len() as i64 {
        return Err(AppError::Validation(
            "an option refers to an unknown product".into(),
        ));
    }
    sqlx::query("DELETE FROM products.product_options WHERE parent_product_id = $1")
        .bind(id)
        .execute(&mut *tx)
        .await?;
    for (i, o) in input.iter().enumerate() {
        sqlx::query(
            "INSERT INTO products.product_options
                (id, parent_product_id, option_product_id, default_quantity, required, sort_order, active)
             VALUES ($1, $2, $3, $4, $5, $6, $7)",
        )
        .bind(new_id())
        .bind(id)
        .bind(o.option_product_id)
        .bind(o.default_quantity)
        .bind(o.required)
        .bind(o.sort_order.unwrap_or(i as i32))
        .bind(o.active)
        .execute(&mut *tx)
        .await?;
    }
    audit::record(
        &mut tx,
        &user,
        "product",
        id,
        "options_replaced",
        serde_json::json!({ "options": seen.len() }),
    )
    .await?;
    let out = load(&mut *tx, id).await?;
    tx.commit().await?;
    Ok(Json(out))
}

/// The routes for the options of a product.
pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new().routes(routes!(list_options, replace_options))
}
