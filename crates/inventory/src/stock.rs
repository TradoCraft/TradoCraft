//! Reading stock: balances per location and lot, totals per product, and the integrity check.

use axum::extract::{Query, State};
use axum::Json;
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use tradocraft_core::{audit, new_id, AppResult, AppState, CurrentUser, Permission};
use utoipa::{IntoParams, ToSchema};
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::ledger::{check_balances, rebuild_balances, BalanceDifference};

/// Stock of one product at one location and lot.
#[derive(Debug, Serialize, FromRow, ToSchema)]
pub struct StockRow {
    pub product_id: Uuid,
    pub product_code: String,
    pub product_name: String,
    pub unit: String,
    pub tracking: String,
    pub warehouse_id: Uuid,
    pub warehouse_kind: String,
    pub location_id: Uuid,
    /// `WAREHOUSE/LOCATION`
    pub location: String,
    pub lot_id: Option<Uuid>,
    pub lot_number: Option<String>,
    pub expiry_date: Option<chrono::NaiveDate>,
    #[schema(value_type = String)]
    pub on_hand: Decimal,
    #[schema(value_type = String)]
    pub reserved: Decimal,
    /// On hand minus reserved; negative when stock was adjusted away from reservations.
    #[schema(value_type = String)]
    pub available: Decimal,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct StockRowPage {
    pub items: Vec<StockRow>,
    pub total: i64,
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct StockParams {
    pub product_id: Option<Uuid>,
    pub warehouse_id: Option<Uuid>,
    pub location_id: Option<Uuid>,
    pub lot_id: Option<Uuid>,
    /// Searches product code, name, barcode and lot number.
    pub q: Option<String>,
    /// Include rows with zero stock (default false).
    pub include_zero: Option<bool>,
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}

const STOCK_ROWS: &str = "SELECT * FROM (
    SELECT b.product_id, p.code AS product_code, p.name AS product_name, p.unit, p.tracking,
           w.id AS warehouse_id, w.kind AS warehouse_kind, b.location_id, w.code || '/' || l.code AS location,
           b.lot_id, lot.lot_number, lot.expiry_date, b.quantity AS on_hand,
           COALESCE((SELECT sum(r.quantity) FROM inventory.reservations r
                     WHERE r.company_id = b.company_id AND r.product_id = b.product_id
                       AND r.location_id = b.location_id AND r.lot_id IS NOT DISTINCT FROM b.lot_id
                       AND r.status = 'active'), 0) AS reserved
    FROM inventory.stock_balances b
    JOIN inventory.locations l ON l.id = b.location_id AND l.kind = 'internal'
    JOIN inventory.warehouses w ON w.id = l.warehouse_id
    JOIN products.products p ON p.id = b.product_id
    LEFT JOIN inventory.lots lot ON lot.id = b.lot_id
    WHERE b.company_id = $1
      AND ($2::uuid IS NULL OR b.product_id = $2)
      AND ($3::uuid IS NULL OR w.id = $3)
      AND ($4::uuid IS NULL OR l.id = $4)
      AND ($5::uuid IS NULL OR b.lot_id = $5)
      AND ($6::text IS NULL OR lower(p.code) LIKE $6 ESCAPE '\\' OR lower(p.name) LIKE $6 ESCAPE '\\'
           OR lower(COALESCE(p.barcode, '')) LIKE $6 ESCAPE '\\'
           OR lower(COALESCE(lot.lot_number, '')) LIKE $6 ESCAPE '\\')
      AND ($7 OR b.quantity <> 0)
) s";

/// `%q%` for a LIKE with `ESCAPE '\\'`: the user's `%`, `_` and `\\` are taken literally.
fn like_pattern(q: &str) -> String {
    let mut out = String::from("%");
    for c in q.trim().to_lowercase().chars() {
        if matches!(c, '%' | '_' | '\\') {
            out.push('\\');
        }
        out.push(c);
    }
    out.push('%');
    out
}

#[utoipa::path(get, path = "/inventory/stock", tag = "inventory", params(StockParams),
    responses((status = 200, body = StockRowPage)))]
async fn list_stock(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(p): Query<StockParams>,
) -> AppResult<Json<StockRowPage>> {
    user.require(Permission::InventoryRead)?;
    let pattern = p.q.as_deref().map(like_pattern);
    let items = sqlx::query_as(sqlx::AssertSqlSafe(format!(
        "SELECT *, on_hand - reserved AS available FROM ({STOCK_ROWS}) x
         ORDER BY product_code, location, lot_number NULLS FIRST LIMIT $8 OFFSET $9"
    )))
    .bind(user.company_id)
    .bind(p.product_id)
    .bind(p.warehouse_id)
    .bind(p.location_id)
    .bind(p.lot_id)
    .bind(&pattern)
    .bind(p.include_zero.unwrap_or(false))
    .bind(p.limit.unwrap_or(100).clamp(1, 1000))
    .bind(p.offset.unwrap_or(0).max(0))
    .fetch_all(&state.db)
    .await?;
    let total = sqlx::query_scalar(sqlx::AssertSqlSafe(format!("SELECT count(*) FROM ({STOCK_ROWS}) x")))
        .bind(user.company_id)
        .bind(p.product_id)
        .bind(p.warehouse_id)
        .bind(p.location_id)
        .bind(p.lot_id)
        .bind(&pattern)
        .bind(p.include_zero.unwrap_or(false))
        .fetch_one(&state.db)
        .await?;
    Ok(Json(StockRowPage { items, total }))
}

/// Stock of one product over all locations.
#[derive(Debug, Serialize, FromRow, ToSchema)]
pub struct ProductStock {
    pub product_id: Uuid,
    pub code: String,
    pub name: String,
    pub unit: String,
    pub tracking: String,
    pub barcode: Option<String>,
    #[schema(value_type = Option<String>)]
    pub reorder_min: Option<Decimal>,
    #[schema(value_type = Option<String>)]
    pub reorder_max: Option<Decimal>,
    pub lead_time_days: Option<i32>,
    /// In the warehouses (or in the chosen warehouse).
    #[schema(value_type = String)]
    pub on_hand: Decimal,
    /// In service vans; not part of the other numbers unless a van is chosen.
    #[schema(value_type = String)]
    pub in_vans: Decimal,
    #[schema(value_type = String)]
    pub reserved: Decimal,
    #[schema(value_type = String)]
    pub available: Decimal,
    /// Available is below the reorder minimum.
    pub below_reorder: bool,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct ProductStockPage {
    pub items: Vec<ProductStock>,
    pub total: i64,
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct ProductStockParams {
    pub product_id: Option<Uuid>,
    /// Count only this warehouse (a van too).
    pub warehouse_id: Option<Uuid>,
    /// Searches code, name and barcode.
    pub q: Option<String>,
    /// Only products that have stock.
    pub in_stock: Option<bool>,
    /// Only products below their reorder minimum.
    pub below_reorder: Option<bool>,
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}

const PRODUCT_STOCK: &str = "SELECT * FROM (
    SELECT p.id AS product_id, p.code, p.name, p.unit, p.tracking, p.barcode, p.reorder_min, p.reorder_max,
           p.lead_time_days,
           COALESCE(s.on_hand, 0) AS on_hand, COALESCE(s.in_vans, 0) AS in_vans, COALESCE(r.reserved, 0) AS reserved,
           COALESCE(s.on_hand, 0) - COALESCE(r.reserved, 0) AS available,
           (p.reorder_min IS NOT NULL AND COALESCE(s.on_hand, 0) - COALESCE(r.reserved, 0) < p.reorder_min) AS below_reorder
    FROM products.products p
    LEFT JOIN (
        SELECT b.product_id,
               sum(b.quantity) FILTER (WHERE ($3::uuid IS NULL AND w.kind = 'warehouse') OR w.id = $3) AS on_hand,
               sum(b.quantity) FILTER (WHERE $3::uuid IS NULL AND w.kind = 'van') AS in_vans
        FROM inventory.stock_balances b
        JOIN inventory.locations l ON l.id = b.location_id AND l.kind = 'internal'
        JOIN inventory.warehouses w ON w.id = l.warehouse_id
        WHERE b.company_id = $1 GROUP BY b.product_id
    ) s ON s.product_id = p.id
    LEFT JOIN (
        SELECT rv.product_id, sum(rv.quantity) AS reserved
        FROM inventory.reservations rv
        JOIN inventory.locations l ON l.id = rv.location_id
        JOIN inventory.warehouses w ON w.id = l.warehouse_id
        WHERE rv.company_id = $1 AND rv.status = 'active'
          AND (($3::uuid IS NULL AND w.kind = 'warehouse') OR w.id = $3)
        GROUP BY rv.product_id
    ) r ON r.product_id = p.id
    WHERE p.product_type <> 'service' AND p.active
      AND ($2::uuid IS NULL OR p.id = $2)
      AND ($4::text IS NULL OR lower(p.code) LIKE $4 ESCAPE '\\' OR lower(p.name) LIKE $4 ESCAPE '\\'
           OR lower(COALESCE(p.barcode, '')) LIKE $4 ESCAPE '\\')
) t
WHERE ($5::boolean IS NOT TRUE OR on_hand <> 0 OR in_vans <> 0) AND ($6::boolean IS NOT TRUE OR below_reorder)";

#[utoipa::path(get, path = "/inventory/stock/products", tag = "inventory", params(ProductStockParams),
    responses((status = 200, body = ProductStockPage)))]
async fn list_product_stock(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(p): Query<ProductStockParams>,
) -> AppResult<Json<ProductStockPage>> {
    user.require(Permission::InventoryRead)?;
    let pattern = p.q.as_deref().map(like_pattern);
    let items = sqlx::query_as(sqlx::AssertSqlSafe(format!("{PRODUCT_STOCK} ORDER BY code LIMIT $7 OFFSET $8")))
        .bind(user.company_id)
        .bind(p.product_id)
        .bind(p.warehouse_id)
        .bind(&pattern)
        .bind(p.in_stock)
        .bind(p.below_reorder)
        .bind(p.limit.unwrap_or(50).clamp(1, 500))
        .bind(p.offset.unwrap_or(0).max(0))
        .fetch_all(&state.db)
        .await?;
    let total = sqlx::query_scalar(sqlx::AssertSqlSafe(format!("SELECT count(*) FROM ({PRODUCT_STOCK}) c")))
        .bind(user.company_id)
        .bind(p.product_id)
        .bind(p.warehouse_id)
        .bind(&pattern)
        .bind(p.in_stock)
        .bind(p.below_reorder)
        .fetch_one(&state.db)
        .await?;
    Ok(Json(ProductStockPage { items, total }))
}

#[cfg(test)]
mod tests {
    use super::like_pattern;

    #[test]
    fn search_text_is_taken_literally() {
        assert_eq!(like_pattern("  Bolt "), "%bolt%");
        assert_eq!(like_pattern("50%_x"), "%50\\%\\_x%");
        assert_eq!(like_pattern("a\\b"), "%a\\\\b%");
    }
}

#[derive(Debug, Serialize, ToSchema)]
pub struct Integrity {
    /// The balance table equals the sum of the ledger.
    pub ok: bool,
    pub differences: Vec<BalanceDifference>,
}

/// Compares the balances with the sum of the ledger.
#[utoipa::path(get, path = "/inventory/integrity", tag = "inventory", responses((status = 200, body = Integrity)))]
async fn integrity(State(state): State<AppState>, user: CurrentUser) -> AppResult<Json<Integrity>> {
    user.require(Permission::InventoryAdmin)?;
    let mut conn = state.db.acquire().await?;
    let differences = check_balances(&mut conn, user.company_id).await?;
    Ok(Json(Integrity {
        ok: differences.is_empty(),
        differences,
    }))
}

#[derive(Debug, Serialize, ToSchema)]
pub struct Rebuilt {
    pub balance_rows: i64,
}

/// Recomputes balances and serial locations from the ledger.
#[utoipa::path(post, path = "/inventory/balances/rebuild", tag = "inventory", responses((status = 200, body = Rebuilt)))]
async fn rebuild(State(state): State<AppState>, user: CurrentUser) -> AppResult<Json<Rebuilt>> {
    user.require(Permission::InventoryAdmin)?;
    let mut tx = state.db.begin().await?;
    let rows = rebuild_balances(&mut tx, user.company_id).await?;
    audit::record(
        &mut tx,
        &user,
        "inventory",
        new_id(),
        "balances_rebuilt",
        serde_json::json!({ "rows": rows }),
    )
    .await?;
    tx.commit().await?;
    Ok(Json(Rebuilt {
        balance_rows: rows as i64,
    }))
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(list_stock))
        .routes(routes!(list_product_stock))
        .routes(routes!(integrity))
        .routes(routes!(rebuild))
}
