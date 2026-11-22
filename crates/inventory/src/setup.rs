//! Warehouses, locations, units of measure and lots.

use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::Json;
use chrono::NaiveDate;
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use tradocraft_core::{audit, new_id, AppError, AppResult, AppState, CurrentUser, Permission};
use utoipa::{IntoParams, ToSchema};
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

type ErrorBody = tradocraft_core::error::ErrorBody;

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct Location {
    pub id: Uuid,
    pub warehouse_id: Uuid,
    pub code: String,
    pub name: String,
    pub active: bool,
}

#[derive(Debug, Clone, Serialize, FromRow)]
struct WarehouseRow {
    id: Uuid,
    code: String,
    name: String,
    kind: String,
    assigned_user_id: Option<Uuid>,
    assigned_user_name: Option<String>,
    active: bool,
}

#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct Warehouse {
    pub id: Uuid,
    pub code: String,
    pub name: String,
    /// warehouse | van
    pub kind: String,
    /// The technician a service van belongs to.
    pub assigned_user_id: Option<Uuid>,
    pub assigned_user_name: Option<String>,
    pub active: bool,
    pub locations: Vec<Location>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct WarehouseInput {
    pub code: String,
    pub name: String,
    /// warehouse | van. Cannot be changed afterwards.
    pub kind: Option<String>,
    pub assigned_user_id: Option<Uuid>,
    pub active: Option<bool>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct LocationInput {
    /// Required when creating.
    pub warehouse_id: Option<Uuid>,
    pub code: String,
    #[serde(default)]
    pub name: String,
    pub active: Option<bool>,
}

#[derive(Debug, Serialize, FromRow, ToSchema)]
pub struct Uom {
    pub code: String,
    pub name: String,
    /// unit | weight | length | area | volume | time
    pub category: String,
    /// Size in the base unit of the category (kg = 1, g = 0.001).
    #[schema(value_type = String, example = "0.001")]
    pub factor: Decimal,
    pub active: bool,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct UomInput {
    pub code: String,
    pub name: String,
    pub category: String,
    #[schema(value_type = String, example = "0.001")]
    pub factor: Decimal,
}

#[derive(Debug, Serialize, Deserialize, FromRow, ToSchema)]
pub struct ProductUom {
    pub uom_code: String,
    /// Stock units in one of this unit (a box of 12 pieces: 12).
    #[schema(value_type = String, example = "12")]
    pub factor: Decimal,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct ProductUomsInput {
    pub uoms: Vec<ProductUom>,
}

#[derive(Debug, Serialize, FromRow, ToSchema)]
pub struct Lot {
    pub id: Uuid,
    pub product_id: Uuid,
    pub product_code: String,
    pub lot_number: String,
    pub expiry_date: Option<NaiveDate>,
    pub notes: String,
    #[schema(value_type = String)]
    pub on_hand: Decimal,
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct LotParams {
    pub product_id: Option<Uuid>,
    /// Only lots with stock.
    pub in_stock: Option<bool>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct LotInput {
    #[serde(default, deserialize_with = "tradocraft_core::serde_util::opt_date")]
    pub expiry_date: Option<NaiveDate>,
    #[serde(default)]
    pub notes: String,
}

async fn load_warehouses(
    state: &AppState,
    company_id: Uuid,
    only: Option<Uuid>,
) -> AppResult<Vec<Warehouse>> {
    let rows: Vec<WarehouseRow> = sqlx::query_as(
        "SELECT w.id, w.code, w.name, w.kind, w.assigned_user_id, u.display_name AS assigned_user_name, w.active
         FROM inventory.warehouses w LEFT JOIN core.users u ON u.id = w.assigned_user_id
         WHERE w.company_id = $1 AND ($2::uuid IS NULL OR w.id = $2) ORDER BY w.kind, w.code",
    )
    .bind(company_id)
    .bind(only)
    .fetch_all(&state.db)
    .await?;
    let locations: Vec<Location> = sqlx::query_as(
        "SELECT id, warehouse_id, code, name, active FROM inventory.locations
         WHERE company_id = $1 AND warehouse_id IS NOT NULL ORDER BY code",
    )
    .bind(company_id)
    .fetch_all(&state.db)
    .await?;
    Ok(rows
        .into_iter()
        .map(|w| Warehouse {
            locations: locations
                .iter()
                .filter(|l| l.warehouse_id == w.id)
                .cloned()
                .collect(),
            id: w.id,
            code: w.code,
            name: w.name,
            kind: w.kind,
            assigned_user_id: w.assigned_user_id,
            assigned_user_name: w.assigned_user_name,
            active: w.active,
        })
        .collect())
}

#[utoipa::path(get, path = "/inventory/warehouses", tag = "inventory",
    responses((status = 200, body = Vec<Warehouse>)))]
async fn list_warehouses(
    State(state): State<AppState>,
    user: CurrentUser,
) -> AppResult<Json<Vec<Warehouse>>> {
    user.require(Permission::InventoryRead)?;
    Ok(Json(load_warehouses(&state, user.company_id, None).await?))
}

async fn check_assignee(
    state: &AppState,
    company_id: Uuid,
    user_id: Option<Uuid>,
) -> AppResult<()> {
    if let Some(u) = user_id {
        let ok: bool = sqlx::query_scalar(
            "SELECT EXISTS (SELECT 1 FROM core.user_companies WHERE user_id = $1 AND company_id = $2)",
        )
        .bind(u)
        .bind(company_id)
        .fetch_one(&state.db)
        .await?;
        if !ok {
            return Err(AppError::Validation(
                "the assigned user has no access to this company".into(),
            ));
        }
    }
    Ok(())
}

/// Creates a warehouse or service van with one default location (`MAIN`, for a van `VAN`).
#[utoipa::path(post, path = "/inventory/warehouses", tag = "inventory", request_body = WarehouseInput,
    responses((status = 201, body = Warehouse), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn create_warehouse(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<WarehouseInput>,
) -> AppResult<(StatusCode, Json<Warehouse>)> {
    user.require(Permission::InventoryAdmin)?;
    let kind = input.kind.as_deref().unwrap_or("warehouse");
    if !matches!(kind, "warehouse" | "van") {
        return Err(AppError::Validation("kind must be warehouse or van".into()));
    }
    if input.code.trim().is_empty() || input.name.trim().is_empty() {
        return Err(AppError::Validation("code and name are required".into()));
    }
    if kind == "warehouse" && input.assigned_user_id.is_some() {
        return Err(AppError::Validation(
            "only a van is assigned to a user".into(),
        ));
    }
    check_assignee(&state, user.company_id, input.assigned_user_id).await?;
    let id = new_id();
    let mut tx = state.db.begin().await?;
    sqlx::query(
        "INSERT INTO inventory.warehouses (id, company_id, code, name, kind, assigned_user_id, active)
         VALUES ($1, $2, $3, $4, $5, $6, $7)",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(input.code.trim())
    .bind(input.name.trim())
    .bind(kind)
    .bind(input.assigned_user_id)
    .bind(input.active.unwrap_or(true))
    .execute(&mut *tx)
    .await?;
    sqlx::query(
        "INSERT INTO inventory.locations (id, company_id, warehouse_id, code, name) VALUES ($1, $2, $3, $4, $5)",
    )
    .bind(new_id())
    .bind(user.company_id)
    .bind(id)
    .bind(if kind == "van" { "VAN" } else { "MAIN" })
    .bind(input.name.trim())
    .execute(&mut *tx)
    .await?;
    audit::record(
        &mut tx,
        &user,
        "warehouse",
        id,
        "created",
        serde_json::json!({ "code": input.code.trim(), "kind": kind }),
    )
    .await?;
    tx.commit().await?;
    let w = load_warehouses(&state, user.company_id, Some(id)).await?;
    Ok((StatusCode::CREATED, Json(w.into_iter().next().unwrap())))
}

async fn on_hand_in(
    conn: &mut sqlx::PgConnection,
    company_id: Uuid,
    warehouse: Option<Uuid>,
    location: Option<Uuid>,
) -> AppResult<Decimal> {
    Ok(sqlx::query_scalar(
        "SELECT COALESCE(sum(b.quantity), 0) FROM inventory.stock_balances b
         JOIN inventory.locations l ON l.id = b.location_id
         WHERE b.company_id = $1 AND ($2::uuid IS NULL OR l.warehouse_id = $2) AND ($3::uuid IS NULL OR l.id = $3)
           AND b.quantity <> 0",
    )
    .bind(company_id)
    .bind(warehouse)
    .bind(location)
    .fetch_one(conn)
    .await?)
}

#[utoipa::path(put, path = "/inventory/warehouses/{id}", tag = "inventory", params(("id" = Uuid, Path)),
    request_body = WarehouseInput,
    responses((status = 200, body = Warehouse), (status = 404, body = ErrorBody), (status = 409, body = ErrorBody)))]
async fn update_warehouse(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<WarehouseInput>,
) -> AppResult<Json<Warehouse>> {
    user.require(Permission::InventoryAdmin)?;
    if input.code.trim().is_empty() || input.name.trim().is_empty() {
        return Err(AppError::Validation("code and name are required".into()));
    }
    check_assignee(&state, user.company_id, input.assigned_user_id).await?;
    let mut tx = state.db.begin().await?;
    let current: Option<(String, bool)> = sqlx::query_as(
        "SELECT kind, active FROM inventory.warehouses WHERE id = $1 AND company_id = $2 FOR UPDATE",
    )
    .bind(id)
    .bind(user.company_id)
    .fetch_optional(&mut *tx)
    .await?;
    let (kind, was_active) = current.ok_or(AppError::NotFound("warehouse"))?;
    if input.kind.as_deref().is_some_and(|k| k != kind) {
        return Err(AppError::Validation(
            "the kind of a warehouse cannot change".into(),
        ));
    }
    if kind == "warehouse" && input.assigned_user_id.is_some() {
        return Err(AppError::Validation(
            "only a van is assigned to a user".into(),
        ));
    }
    let active = input.active.unwrap_or(was_active);
    if was_active
        && !active
        && on_hand_in(&mut tx, user.company_id, Some(id), None).await? != Decimal::ZERO
    {
        return Err(AppError::Conflict(
            "the warehouse still holds stock; move it out first".into(),
        ));
    }
    sqlx::query(
        "UPDATE inventory.warehouses SET code = $2, name = $3, assigned_user_id = $4, active = $5 WHERE id = $1",
    )
    .bind(id)
    .bind(input.code.trim())
    .bind(input.name.trim())
    .bind(input.assigned_user_id)
    .bind(active)
    .execute(&mut *tx)
    .await?;
    audit::record(
        &mut tx,
        &user,
        "warehouse",
        id,
        "updated",
        serde_json::json!({ "active": active }),
    )
    .await?;
    tx.commit().await?;
    let w = load_warehouses(&state, user.company_id, Some(id)).await?;
    Ok(Json(w.into_iter().next().unwrap()))
}

#[utoipa::path(post, path = "/inventory/locations", tag = "inventory", request_body = LocationInput,
    responses((status = 201, body = Location), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn create_location(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<LocationInput>,
) -> AppResult<(StatusCode, Json<Location>)> {
    user.require(Permission::InventoryAdmin)?;
    let warehouse_id = input
        .warehouse_id
        .ok_or_else(|| AppError::Validation("warehouse_id is required".into()))?;
    if input.code.trim().is_empty() {
        return Err(AppError::Validation("code is required".into()));
    }
    let ok: bool = sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM inventory.warehouses WHERE id = $1 AND company_id = $2 AND active)",
    )
    .bind(warehouse_id)
    .bind(user.company_id)
    .fetch_one(&state.db)
    .await?;
    if !ok {
        return Err(AppError::NotFound("warehouse"));
    }
    let id = new_id();
    let mut tx = state.db.begin().await?;
    sqlx::query(
        "INSERT INTO inventory.locations (id, company_id, warehouse_id, code, name, active)
         VALUES ($1, $2, $3, $4, $5, $6)",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(warehouse_id)
    .bind(input.code.trim())
    .bind(input.name.trim())
    .bind(input.active.unwrap_or(true))
    .execute(&mut *tx)
    .await?;
    audit::record(
        &mut tx,
        &user,
        "location",
        id,
        "created",
        serde_json::json!({ "code": input.code.trim() }),
    )
    .await?;
    let l = sqlx::query_as(
        "SELECT id, warehouse_id, code, name, active FROM inventory.locations WHERE id = $1",
    )
    .bind(id)
    .fetch_one(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(l)))
}

#[utoipa::path(put, path = "/inventory/locations/{id}", tag = "inventory", params(("id" = Uuid, Path)),
    request_body = LocationInput,
    responses((status = 200, body = Location), (status = 404, body = ErrorBody), (status = 409, body = ErrorBody)))]
async fn update_location(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<LocationInput>,
) -> AppResult<Json<Location>> {
    user.require(Permission::InventoryAdmin)?;
    if input.code.trim().is_empty() {
        return Err(AppError::Validation("code is required".into()));
    }
    let mut tx = state.db.begin().await?;
    let current: Option<bool> = sqlx::query_scalar(
        "SELECT active FROM inventory.locations WHERE id = $1 AND company_id = $2 AND warehouse_id IS NOT NULL FOR UPDATE",
    )
    .bind(id)
    .bind(user.company_id)
    .fetch_optional(&mut *tx)
    .await?;
    let was_active = current.ok_or(AppError::NotFound("location"))?;
    let active = input.active.unwrap_or(was_active);
    if was_active
        && !active
        && on_hand_in(&mut tx, user.company_id, None, Some(id)).await? != Decimal::ZERO
    {
        return Err(AppError::Conflict(
            "the location still holds stock; move it out first".into(),
        ));
    }
    sqlx::query("UPDATE inventory.locations SET code = $2, name = $3, active = $4 WHERE id = $1")
        .bind(id)
        .bind(input.code.trim())
        .bind(input.name.trim())
        .bind(active)
        .execute(&mut *tx)
        .await?;
    audit::record(
        &mut tx,
        &user,
        "location",
        id,
        "updated",
        serde_json::json!({ "active": active }),
    )
    .await?;
    let l = sqlx::query_as(
        "SELECT id, warehouse_id, code, name, active FROM inventory.locations WHERE id = $1",
    )
    .bind(id)
    .fetch_one(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(Json(l))
}

#[utoipa::path(get, path = "/inventory/uoms", tag = "inventory", responses((status = 200, body = Vec<Uom>)))]
async fn list_uoms(State(state): State<AppState>, user: CurrentUser) -> AppResult<Json<Vec<Uom>>> {
    user.require(Permission::InventoryRead)?;
    Ok(Json(
        sqlx::query_as("SELECT code, name, category, factor, active FROM inventory.uoms ORDER BY category, factor, code")
            .fetch_all(&state.db)
            .await?,
    ))
}

#[utoipa::path(post, path = "/inventory/uoms", tag = "inventory", request_body = UomInput,
    responses((status = 201, body = Uom), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn create_uom(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<UomInput>,
) -> AppResult<(StatusCode, Json<Uom>)> {
    user.require(Permission::InventoryAdmin)?;
    let code = input.code.trim();
    if code.is_empty() || input.name.trim().is_empty() {
        return Err(AppError::Validation("code and name are required".into()));
    }
    if input.factor <= Decimal::ZERO {
        return Err(AppError::Validation("factor must be greater than 0".into()));
    }
    let mut tx = state.db.begin().await?;
    sqlx::query(
        "INSERT INTO inventory.uoms (code, name, category, factor) VALUES ($1, $2, $3, $4)",
    )
    .bind(code)
    .bind(input.name.trim())
    .bind(&input.category)
    .bind(input.factor)
    .execute(&mut *tx)
    .await?;
    audit::record(
        &mut tx,
        &user,
        "uom",
        new_id(),
        "created",
        serde_json::json!({ "code": code }),
    )
    .await?;
    let u = sqlx::query_as(
        "SELECT code, name, category, factor, active FROM inventory.uoms WHERE code = $1",
    )
    .bind(code)
    .fetch_one(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(u)))
}

#[utoipa::path(get, path = "/inventory/products/{id}/uoms", tag = "inventory", params(("id" = Uuid, Path)),
    responses((status = 200, body = Vec<ProductUom>)))]
async fn product_uoms(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<Vec<ProductUom>>> {
    user.require(Permission::InventoryRead)?;
    tradocraft_products::get_product(&state.db, id).await?;
    Ok(Json(
        sqlx::query_as("SELECT uom_code, factor FROM inventory.product_uoms WHERE product_id = $1 ORDER BY uom_code")
            .bind(id)
            .fetch_all(&state.db)
            .await?,
    ))
}

/// Replaces the product-specific units (for example a box of 12 pieces).
#[utoipa::path(put, path = "/inventory/products/{id}/uoms", tag = "inventory", params(("id" = Uuid, Path)),
    request_body = ProductUomsInput,
    responses((status = 200, body = Vec<ProductUom>), (status = 422, body = ErrorBody)))]
async fn set_product_uoms(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<ProductUomsInput>,
) -> AppResult<Json<Vec<ProductUom>>> {
    user.require(Permission::InventoryAdmin)?;
    let product = tradocraft_products::get_product(&state.db, id).await?;
    let mut seen = std::collections::HashSet::new();
    for u in &input.uoms {
        if u.factor <= Decimal::ZERO {
            return Err(AppError::Validation("factor must be greater than 0".into()));
        }
        if u.uom_code == product.unit {
            return Err(AppError::Validation(
                "the stock unit needs no conversion".into(),
            ));
        }
        if !seen.insert(u.uom_code.clone()) {
            return Err(AppError::Validation(format!(
                "{} is listed twice",
                u.uom_code
            )));
        }
    }
    let mut tx = state.db.begin().await?;
    let locked: Option<Uuid> =
        sqlx::query_scalar("SELECT id FROM products.products WHERE id = $1 FOR UPDATE")
            .bind(id)
            .fetch_optional(&mut *tx)
            .await?;
    if locked.is_none() {
        return Err(AppError::NotFound("product"));
    }
    let existing_uoms: Vec<(String, Decimal)> = sqlx::query_as(
        "SELECT uom_code, factor FROM inventory.product_uoms WHERE product_id = $1 FOR UPDATE",
    )
    .bind(id)
    .fetch_all(&mut *tx)
    .await?;
    let next_uoms: std::collections::HashMap<&str, Decimal> = input
        .uoms
        .iter()
        .map(|u| (u.uom_code.as_str(), u.factor))
        .collect();
    for (uom_code, old_factor) in &existing_uoms {
        if next_uoms.get(uom_code.as_str()) != Some(old_factor) {
            let in_use: bool = sqlx::query_scalar(
                "SELECT EXISTS (
                     SELECT 1
                     FROM sales.order_lines ol
                     JOIN sales.orders o ON o.id = ol.order_id
                     JOIN delivery.delivery_note_lines dl ON dl.order_line_id = ol.id
                     JOIN delivery.delivery_notes dn ON dn.id = dl.delivery_note_id
                     WHERE ol.product_id = $1
                       AND ol.unit = $2
                       AND ol.revision = o.current_revision
                       AND o.status <> 'cancelled'
                       AND dn.status = 'shipped'
                 )",
            )
            .bind(id)
            .bind(uom_code)
            .fetch_one(&mut *tx)
            .await?;
            if in_use {
                return Err(AppError::Conflict(format!(
                    "cannot change or remove unit {uom_code} while open or shipped order lines depend on it"
                )));
            }
        }
    }
    sqlx::query("DELETE FROM inventory.product_uoms WHERE product_id = $1")
        .bind(id)
        .execute(&mut *tx)
        .await?;
    for u in &input.uoms {
        sqlx::query(
            "INSERT INTO inventory.product_uoms (product_id, uom_code, factor) VALUES ($1, $2, $3)",
        )
        .bind(id)
        .bind(&u.uom_code)
        .bind(u.factor)
        .execute(&mut *tx)
        .await?;
    }
    audit::record(
        &mut tx,
        &user,
        "product",
        id,
        "uoms_changed",
        serde_json::json!({ "count": input.uoms.len() }),
    )
    .await?;
    tx.commit().await?;
    Ok(Json(
        sqlx::query_as("SELECT uom_code, factor FROM inventory.product_uoms WHERE product_id = $1 ORDER BY uom_code")
            .bind(id)
            .fetch_all(&state.db)
            .await?,
    ))
}

const SELECT_LOT: &str =
    "SELECT l.id, l.product_id, p.code AS product_code, l.lot_number, l.expiry_date, l.notes,
        COALESCE((SELECT sum(b.quantity) FROM inventory.stock_balances b
                  JOIN inventory.locations loc ON loc.id = b.location_id AND loc.kind = 'internal'
                  WHERE b.lot_id = l.id), 0) AS on_hand
     FROM inventory.lots l JOIN products.products p ON p.id = l.product_id";

#[utoipa::path(get, path = "/inventory/lots", tag = "inventory", params(LotParams),
    responses((status = 200, body = Vec<Lot>)))]
async fn list_lots(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(p): Query<LotParams>,
) -> AppResult<Json<Vec<Lot>>> {
    user.require(Permission::InventoryRead)?;
    // `in_stock` is applied before the limit, so later lots with stock are not cut off by
    // earlier ones without.
    let lots: Vec<Lot> = sqlx::query_as(&format!(
        "{SELECT_LOT} WHERE l.company_id = $1 AND ($2::uuid IS NULL OR l.product_id = $2)
           AND (NOT $3 OR COALESCE((SELECT sum(b.quantity) FROM inventory.stock_balances b
                                    JOIN inventory.locations loc ON loc.id = b.location_id AND loc.kind = 'internal'
                                    WHERE b.lot_id = l.id), 0) > 0)
         ORDER BY l.expiry_date NULLS LAST, l.lot_number LIMIT 500"
    ))
    .bind(user.company_id)
    .bind(p.product_id)
    .bind(p.in_stock.unwrap_or(false))
    .fetch_all(&state.db)
    .await?;
    Ok(Json(lots))
}

#[utoipa::path(put, path = "/inventory/lots/{id}", tag = "inventory", params(("id" = Uuid, Path)),
    request_body = LotInput, responses((status = 200, body = Lot), (status = 404, body = ErrorBody)))]
async fn update_lot(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<LotInput>,
) -> AppResult<Json<Lot>> {
    user.require(Permission::InventoryWrite)?;
    let mut tx = state.db.begin().await?;
    let n = sqlx::query(
        "UPDATE inventory.lots SET expiry_date = $3, notes = $4 WHERE id = $1 AND company_id = $2",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(input.expiry_date)
    .bind(&input.notes)
    .execute(&mut *tx)
    .await?;
    if n.rows_affected() == 0 {
        return Err(AppError::NotFound("lot"));
    }
    audit::record(
        &mut tx,
        &user,
        "lot",
        id,
        "updated",
        serde_json::json!({ "expiry_date": input.expiry_date }),
    )
    .await?;
    let lot = sqlx::query_as(&format!("{SELECT_LOT} WHERE l.id = $1"))
        .bind(id)
        .fetch_one(&mut *tx)
        .await?;
    tx.commit().await?;
    Ok(Json(lot))
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(list_warehouses, create_warehouse))
        .routes(routes!(update_warehouse))
        .routes(routes!(create_location))
        .routes(routes!(update_location))
        .routes(routes!(list_uoms, create_uom))
        .routes(routes!(product_uoms, set_product_uoms))
        .routes(routes!(list_lots))
        .routes(routes!(update_lot))
}
