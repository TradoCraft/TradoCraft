//! Serial-number traceability: individual units, their BOM revision, and which serialised
//! components were built into them (with history when components are replaced).

use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::Json;
use chrono::{DateTime, NaiveDate, Utc};
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection};
use tradocraft_core::{audit, new_id, AppError, AppResult, AppState, CurrentUser, Permission};
use tradocraft_products::get_product;
use utoipa::{IntoParams, ToSchema};
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

type ErrorBody = tradocraft_core::error::ErrorBody;

const STATUSES: [&str; 5] = ["in_stock", "built_in", "delivered", "installed", "scrapped"];

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct SerialUnit {
    pub id: Uuid,
    pub product_id: Uuid,
    pub product_code: String,
    pub product_name: String,
    pub serial_number: String,
    /// in_stock | built_in | delivered | installed | scrapped
    pub status: String,
    pub bom_id: Option<Uuid>,
    pub bom_revision: Option<i32>,
    pub customer_id: Option<Uuid>,
    pub customer_name: Option<String>,
    /// The unit this one is currently built into.
    pub parent_id: Option<Uuid>,
    pub parent_serial_number: Option<String>,
    pub notes: String,
    /// The end of the warranty, if known.
    pub warranty_until: Option<NaiveDate>,
    pub warranty_note: String,
    /// in_warranty | expired | unknown (no end date recorded)
    pub warranty_status: String,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// A serialised component in the current as-built tree, depth-first.
#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct SerialComponent {
    pub id: Uuid,
    pub parent_id: Uuid,
    pub level: i32,
    pub product_code: String,
    pub product_name: String,
    pub serial_number: String,
    pub status: String,
    pub added_at: DateTime<Utc>,
}

/// A component link of this unit, including removed ones.
#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct ComponentHistory {
    pub child_id: Uuid,
    pub product_code: String,
    pub serial_number: String,
    pub added_at: DateTime<Utc>,
    pub added_by_name: String,
    pub removed_at: Option<DateTime<Utc>>,
    pub removed_by_name: Option<String>,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct SerialUnitDetail {
    pub unit: SerialUnit,
    pub components: Vec<SerialComponent>,
    pub history: Vec<ComponentHistory>,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct SerialUnitPage {
    pub items: Vec<SerialUnit>,
    pub total: i64,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct SerialInput {
    pub serial_number: String,
    /// BOM revision the unit was built to. Default: the product's active BOM, if any.
    pub bom_id: Option<Uuid>,
    pub customer_id: Option<Uuid>,
    #[serde(default)]
    pub notes: String,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct SerialStatusInput {
    /// in_stock | delivered | installed | scrapped (built_in is set by attaching to another unit)
    pub status: String,
    /// Required for delivered and installed, unless the unit already has a customer.
    pub customer_id: Option<Uuid>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct WarrantyInput {
    /// The last day of the warranty; empty when unknown.
    #[serde(default, deserialize_with = "tradocraft_core::serde_util::opt_date")]
    pub warranty_until: Option<NaiveDate>,
    #[serde(default)]
    pub warranty_note: String,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct AttachInput {
    pub child_id: Uuid,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct DetachInput {
    /// What happens to the removed component: in_stock (default) or scrapped.
    pub child_status: Option<String>,
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct ListParams {
    /// Searches serial number and product code.
    pub q: Option<String>,
    pub product_id: Option<Uuid>,
    pub status: Option<String>,
    pub customer_id: Option<Uuid>,
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}

const SELECT: &str = "SELECT s.id, s.product_id, p.code AS product_code, p.name AS product_name, s.serial_number,
        s.status, s.bom_id, b.revision AS bom_revision, s.customer_id, c.name AS customer_name,
        link.parent_id, ps.serial_number AS parent_serial_number, s.notes, s.warranty_until, s.warranty_note,
        CASE WHEN s.warranty_until IS NULL THEN 'unknown' WHEN s.warranty_until >= current_date THEN 'in_warranty'
             ELSE 'expired' END AS warranty_status, s.created_at, s.updated_at
     FROM engineering.serial_units s
     JOIN products.products p ON p.id = s.product_id
     LEFT JOIN engineering.boms b ON b.id = s.bom_id
     LEFT JOIN crm.customers c ON c.id = s.customer_id
     LEFT JOIN engineering.serial_unit_components link ON link.child_id = s.id AND link.removed_at IS NULL
     LEFT JOIN engineering.serial_units ps ON ps.id = link.parent_id";

async fn load(conn: &mut PgConnection, company_id: Uuid, id: Uuid) -> AppResult<SerialUnit> {
    sqlx::query_as(sqlx::AssertSqlSafe(format!(
        "{SELECT} WHERE s.id = $1 AND s.company_id = $2"
    )))
    .bind(id)
    .bind(company_id)
    .fetch_optional(conn)
    .await?
    .ok_or(AppError::NotFound("serial unit"))
}

async fn lock(conn: &mut PgConnection, ids: &[Uuid]) -> AppResult<()> {
    sqlx::query(
        "SELECT id FROM engineering.serial_units WHERE id = ANY($1) ORDER BY id FOR UPDATE",
    )
    .bind(ids)
    .execute(conn)
    .await?;
    Ok(())
}

/// True if inventory currently holds the unit at a location. Its status is then driven by stock
/// moves (ADR 0019): issue it from stock instead of changing the status here.
async fn has_stock_location(conn: &mut PgConnection, id: Uuid) -> AppResult<bool> {
    Ok(sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM inventory.serial_stock WHERE serial_unit_id = $1)",
    )
    .bind(id)
    .fetch_one(conn)
    .await?)
}

/// The facts inventory needs about a unit, read under a row lock.
#[derive(Debug, Clone)]
pub struct StockUnit {
    pub id: Uuid,
    pub product_id: Uuid,
    pub serial_number: String,
    pub status: String,
    pub customer_id: Option<Uuid>,
    pub built_into: Option<Uuid>,
}

/// Locks a unit of the company for a stock move.
pub async fn lock_for_stock(
    conn: &mut PgConnection,
    company_id: Uuid,
    id: Uuid,
) -> AppResult<StockUnit> {
    lock(conn, &[id]).await?;
    let u = load(conn, company_id, id).await?;
    Ok(StockUnit {
        id: u.id,
        product_id: u.product_id,
        serial_number: u.serial_number,
        status: u.status,
        customer_id: u.customer_id,
        built_into: u.parent_id,
    })
}

/// Finds a unit by serial number (serial numbers are unique per product).
pub async fn find_by_serial(
    conn: &mut PgConnection,
    company_id: Uuid,
    product_id: Uuid,
    serial: &str,
) -> AppResult<Option<Uuid>> {
    Ok(sqlx::query_scalar(
        "SELECT id FROM engineering.serial_units WHERE company_id = $1 AND product_id = $2 AND serial_number = $3",
    )
    .bind(company_id)
    .bind(product_id)
    .bind(serial)
    .fetch_optional(conn)
    .await?)
}

/// Sets the status of a unit as a consequence of a stock move (the caller has checked the
/// transition). `customer_id` replaces the customer when given; `clear_customer` removes it.
pub async fn set_status_from_stock(
    conn: &mut PgConnection,
    id: Uuid,
    status: &str,
    customer_id: Option<Uuid>,
    clear_customer: bool,
) -> AppResult<()> {
    sqlx::query(
        "UPDATE engineering.serial_units
         SET status = $2, customer_id = CASE WHEN $4 THEN NULL ELSE COALESCE($3, customer_id) END, updated_at = now()
         WHERE id = $1",
    )
    .bind(id)
    .bind(status)
    .bind(customer_id)
    .bind(clear_customer)
    .execute(conn)
    .await?;
    Ok(())
}

async fn detail(
    conn: &mut PgConnection,
    company_id: Uuid,
    id: Uuid,
) -> AppResult<SerialUnitDetail> {
    let unit = load(conn, company_id, id).await?;
    let components = sqlx::query_as(
        "WITH RECURSIVE tree AS (
             SELECT l.child_id, l.parent_id, 1 AS level, l.added_at,
                    ARRAY[l.added_at::text || l.child_id::text] AS sort_path
             FROM engineering.serial_unit_components l
             WHERE l.parent_id = $1 AND l.removed_at IS NULL
           UNION ALL
             SELECT l.child_id, l.parent_id, t.level + 1, l.added_at,
                    t.sort_path || (l.added_at::text || l.child_id::text)
             FROM engineering.serial_unit_components l JOIN tree t ON l.parent_id = t.child_id
             WHERE l.removed_at IS NULL AND t.level < 20
         )
         SELECT s.id, t.parent_id, t.level, p.code AS product_code, p.name AS product_name, s.serial_number,
                s.status, t.added_at
         FROM tree t JOIN engineering.serial_units s ON s.id = t.child_id
         JOIN products.products p ON p.id = s.product_id
         ORDER BY t.sort_path",
    )
    .bind(id)
    .fetch_all(&mut *conn)
    .await?;
    let history = sqlx::query_as(
        "SELECT l.child_id, p.code AS product_code, s.serial_number, l.added_at, ua.display_name AS added_by_name,
                l.removed_at, ur.display_name AS removed_by_name
         FROM engineering.serial_unit_components l
         JOIN engineering.serial_units s ON s.id = l.child_id
         JOIN products.products p ON p.id = s.product_id
         JOIN core.users ua ON ua.id = l.added_by
         LEFT JOIN core.users ur ON ur.id = l.removed_by
         WHERE l.parent_id = $1 ORDER BY l.added_at",
    )
    .bind(id)
    .fetch_all(&mut *conn)
    .await?;
    Ok(SerialUnitDetail {
        unit,
        components,
        history,
    })
}

#[utoipa::path(get, path = "/serials", tag = "engineering", params(ListParams),
    responses((status = 200, body = SerialUnitPage)))]
async fn list_serials(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(p): Query<ListParams>,
) -> AppResult<Json<SerialUnitPage>> {
    user.require(Permission::SerialsRead)?;
    let pattern =
        p.q.as_deref()
            .map(|q| format!("%{}%", q.trim().to_lowercase()));
    let filter = "WHERE s.company_id = $1
          AND ($2::text IS NULL OR lower(s.serial_number) LIKE $2 OR lower(p.code) LIKE $2)
          AND ($3::uuid IS NULL OR s.product_id = $3)
          AND ($4::text IS NULL OR s.status = $4)
          AND ($5::uuid IS NULL OR s.customer_id = $5)";
    let items = sqlx::query_as(sqlx::AssertSqlSafe(format!(
        "{SELECT} {filter} ORDER BY p.code, s.serial_number LIMIT $6 OFFSET $7"
    )))
    .bind(user.company_id)
    .bind(&pattern)
    .bind(p.product_id)
    .bind(&p.status)
    .bind(p.customer_id)
    .bind(p.limit.unwrap_or(50).clamp(1, 500))
    .bind(p.offset.unwrap_or(0).max(0))
    .fetch_all(&state.db)
    .await?;
    let total = sqlx::query_scalar(sqlx::AssertSqlSafe(format!(
        "SELECT count(*) FROM engineering.serial_units s JOIN products.products p ON p.id = s.product_id {filter}"
    )))
    .bind(user.company_id)
    .bind(&pattern)
    .bind(p.product_id)
    .bind(&p.status)
    .bind(p.customer_id)
    .fetch_one(&state.db)
    .await?;
    Ok(Json(SerialUnitPage { items, total }))
}

/// Registers a serialised unit in the caller's transaction. Used by [`create_serial`] and by
/// inventory when a serial product is received. `bom_id` defaults to the product's active BOM.
pub async fn register_unit(
    tx: &mut PgConnection,
    user: &CurrentUser,
    product_id: Uuid,
    serial: &str,
    bom_id: Option<Uuid>,
    customer_id: Option<Uuid>,
    notes: &str,
) -> AppResult<Uuid> {
    let product = get_product(&mut *tx, product_id).await?;
    if product.tracking != "serial" {
        return Err(AppError::Validation(format!(
            "{} is not serial-tracked",
            product.code
        )));
    }
    let bom_id: Option<Uuid> = match bom_id {
        Some(bom_id) => {
            let ok: bool = sqlx::query_scalar(
                "SELECT EXISTS (SELECT 1 FROM engineering.boms WHERE id = $1 AND product_id = $2 AND status <> 'draft')",
            )
            .bind(bom_id)
            .bind(product_id)
            .fetch_one(&mut *tx)
            .await?;
            if !ok {
                return Err(AppError::Validation(
                    "bom_id must be an active or obsolete revision of this product".into(),
                ));
            }
            Some(bom_id)
        }
        None => {
            sqlx::query_scalar(
                "SELECT id FROM engineering.boms WHERE product_id = $1 AND status = 'active'",
            )
            .bind(product_id)
            .fetch_optional(&mut *tx)
            .await?
        }
    };
    let id = new_id();
    sqlx::query(
        "INSERT INTO engineering.serial_units (id, company_id, product_id, serial_number, bom_id, customer_id, notes, created_by)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(product_id)
    .bind(serial)
    .bind(bom_id)
    .bind(customer_id)
    .bind(notes)
    .bind(user.user_id)
    .execute(&mut *tx)
    .await?;
    audit::record(
        &mut *tx,
        user,
        "serial_unit",
        id,
        "created",
        serde_json::json!({ "serial_number": serial }),
    )
    .await?;
    Ok(id)
}

/// Registers a serialised unit. (Later also created automatically by production and goods receipt.)
#[utoipa::path(post, path = "/products/{id}/serials", tag = "engineering", params(("id" = Uuid, Path)),
    request_body = SerialInput,
    responses((status = 201, body = SerialUnitDetail), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn create_serial(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(product_id): Path<Uuid>,
    Json(input): Json<SerialInput>,
) -> AppResult<(StatusCode, Json<SerialUnitDetail>)> {
    user.require(Permission::SerialsWrite)?;
    let serial = input.serial_number.trim();
    if serial.is_empty() {
        return Err(AppError::Validation("serial_number is required".into()));
    }
    let mut tx = state.db.begin().await?;
    let id = register_unit(
        &mut tx,
        &user,
        product_id,
        serial,
        input.bom_id,
        input.customer_id,
        &input.notes,
    )
    .await?;
    let d = detail(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(d)))
}

#[utoipa::path(get, path = "/serials/{id}", tag = "engineering", params(("id" = Uuid, Path)),
    responses((status = 200, body = SerialUnitDetail), (status = 404, body = ErrorBody)))]
async fn get_serial(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<SerialUnitDetail>> {
    user.require(Permission::SerialsRead)?;
    let mut conn = state.db.acquire().await?;
    Ok(Json(detail(&mut conn, user.company_id, id).await?))
}

#[utoipa::path(put, path = "/serials/{id}/status", tag = "engineering", params(("id" = Uuid, Path)),
    request_body = SerialStatusInput,
    responses((status = 200, body = SerialUnitDetail), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn set_status(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<SerialStatusInput>,
) -> AppResult<Json<SerialUnitDetail>> {
    user.require(Permission::SerialsWrite)?;
    if !STATUSES.contains(&input.status.as_str()) || input.status == "built_in" {
        return Err(AppError::Validation(
            "status must be in_stock, delivered, installed or scrapped".into(),
        ));
    }
    let mut tx = state.db.begin().await?;
    lock(&mut tx, &[id]).await?;
    let unit = load(&mut tx, user.company_id, id).await?;
    if unit.parent_id.is_some() {
        return Err(AppError::Conflict(format!(
            "{} is built into {}; remove it from that unit first",
            unit.serial_number,
            unit.parent_serial_number.unwrap_or_default()
        )));
    }
    if unit.status == "scrapped" {
        return Err(AppError::Conflict(format!(
            "{} is scrapped",
            unit.serial_number
        )));
    }
    if has_stock_location(&mut tx, id).await? {
        return Err(AppError::Conflict(format!(
            "{} is held in a stock location; issue it from stock to change its status",
            unit.serial_number
        )));
    }
    let customer = input.customer_id.or(unit.customer_id);
    if matches!(input.status.as_str(), "delivered" | "installed") && customer.is_none() {
        return Err(AppError::Validation(format!(
            "a customer is required for status {}",
            input.status
        )));
    }
    sqlx::query("UPDATE engineering.serial_units SET status = $2, customer_id = $3, updated_at = now() WHERE id = $1")
        .bind(id)
        .bind(&input.status)
        .bind(customer)
        .execute(&mut *tx)
        .await?;
    audit::record(
        &mut tx,
        &user,
        "serial_unit",
        id,
        "status_changed",
        serde_json::json!({ "from": unit.status, "to": input.status, "customer_id": customer }),
    )
    .await?;
    let d = detail(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok(Json(d))
}

/// Sets the warranty of a unit: until when, and a note (terms, contract).
#[utoipa::path(put, path = "/serials/{id}/warranty", tag = "engineering", params(("id" = Uuid, Path)),
    request_body = WarrantyInput,
    responses((status = 200, body = SerialUnitDetail), (status = 404, body = ErrorBody)))]
async fn set_warranty(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<WarrantyInput>,
) -> AppResult<Json<SerialUnitDetail>> {
    user.require(Permission::SerialsWrite)?;
    let mut tx = state.db.begin().await?;
    lock(&mut tx, &[id]).await?;
    load(&mut tx, user.company_id, id).await?;
    sqlx::query("UPDATE engineering.serial_units SET warranty_until = $2, warranty_note = $3, updated_at = now() WHERE id = $1")
        .bind(id)
        .bind(input.warranty_until)
        .bind(input.warranty_note.trim())
        .execute(&mut *tx)
        .await?;
    audit::record(
        &mut tx,
        &user,
        "serial_unit",
        id,
        "warranty_changed",
        serde_json::json!({ "warranty_until": input.warranty_until }),
    )
    .await?;
    let d = detail(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok(Json(d))
}

/// Records that `child_id` was built into `id`, in the caller's transaction: the checks and the
/// status change of `POST /serials/{id}/components`, for modules that build units (production,
/// ADR 0036). The child must be in stock without a location (issued with reason `consumption`),
/// belong to the BOM revision of the parent, and not make a loop.
pub async fn attach_component_in(
    conn: &mut PgConnection,
    user: &CurrentUser,
    id: Uuid,
    child_id: Uuid,
) -> AppResult<()> {
    if child_id == id {
        return Err(AppError::Validation("a unit cannot contain itself".into()));
    }
    lock(conn, &[id, child_id]).await?;
    let parent = load(conn, user.company_id, id).await?;
    let child = load(conn, user.company_id, child_id).await?;
    if parent.status == "scrapped" {
        return Err(AppError::Conflict(format!(
            "{} is scrapped",
            parent.serial_number
        )));
    }
    if child.status != "in_stock" || child.parent_id.is_some() {
        return Err(AppError::Conflict(format!(
            "{} is {}, not in stock",
            child.serial_number, child.status
        )));
    }
    if has_stock_location(conn, child_id).await? {
        return Err(AppError::Conflict(format!(
            "{} is held in a stock location; issue it from stock (reason consumption) first",
            child.serial_number
        )));
    }
    let bom_id = parent.bom_id.ok_or_else(|| {
        AppError::Validation(format!(
            "{} has no BOM revision, so its components cannot be checked",
            parent.serial_number
        ))
    })?;
    let bom_quantity: Option<Decimal> = sqlx::query_scalar(
        "SELECT sum(quantity) FROM engineering.bom_lines WHERE bom_id = $1 AND component_product_id = $2",
    )
    .bind(bom_id)
    .bind(child.product_id)
    .fetch_one(&mut *conn)
    .await?;
    let bom_quantity = bom_quantity.ok_or_else(|| {
        AppError::Validation(format!(
            "{} is not a component of {} revision {}",
            child.product_code,
            parent.product_code,
            parent.bom_revision.unwrap_or_default()
        ))
    })?;
    let attached: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM engineering.serial_unit_components l JOIN engineering.serial_units s ON s.id = l.child_id
         WHERE l.parent_id = $1 AND l.removed_at IS NULL AND s.product_id = $2",
    )
    .bind(id)
    .bind(child.product_id)
    .fetch_one(&mut *conn)
    .await?;
    if Decimal::from(attached + 1) > bom_quantity.ceil() {
        return Err(AppError::Conflict(format!(
            "{} already contains {attached} × {} (BOM quantity {})",
            parent.serial_number,
            child.product_code,
            bom_quantity.normalize()
        )));
    }
    // The child may not be an ancestor of the parent (would create a loop).
    let is_ancestor: bool = sqlx::query_scalar(
        "WITH RECURSIVE up AS (
             SELECT parent_id FROM engineering.serial_unit_components WHERE child_id = $1 AND removed_at IS NULL
           UNION
             SELECT l.parent_id FROM engineering.serial_unit_components l JOIN up ON l.child_id = up.parent_id
             WHERE l.removed_at IS NULL
         ) SELECT EXISTS (SELECT 1 FROM up WHERE parent_id = $2)",
    )
    .bind(id)
    .bind(child_id)
    .fetch_one(&mut *conn)
    .await?;
    if is_ancestor {
        return Err(AppError::Validation(format!(
            "{} contains {}",
            child.serial_number, parent.serial_number
        )));
    }
    sqlx::query("INSERT INTO engineering.serial_unit_components (id, parent_id, child_id, added_by) VALUES ($1, $2, $3, $4)")
        .bind(new_id())
        .bind(id)
        .bind(child_id)
        .bind(user.user_id)
        .execute(&mut *conn)
        .await?;
    sqlx::query(
        "UPDATE engineering.serial_units SET status = 'built_in', updated_at = now() WHERE id = $1",
    )
    .bind(child_id)
    .execute(&mut *conn)
    .await?;
    audit::record(
        conn,
        user,
        "serial_unit",
        id,
        "component_added",
        serde_json::json!({ "child_id": child_id, "serial_number": child.serial_number }),
    )
    .await?;
    Ok(())
}

/// Records that a serialised component was built into this unit. The component's product must be
/// part of the unit's BOM revision, and no more units may be attached than the BOM quantity.
#[utoipa::path(post, path = "/serials/{id}/components", tag = "engineering", params(("id" = Uuid, Path)),
    request_body = AttachInput,
    responses((status = 200, body = SerialUnitDetail), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn attach_component(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<AttachInput>,
) -> AppResult<Json<SerialUnitDetail>> {
    user.require(Permission::SerialsWrite)?;
    if input.child_id == id {
        return Err(AppError::Validation("a unit cannot contain itself".into()));
    }
    let mut tx = state.db.begin().await?;
    attach_component_in(&mut tx, &user, id, input.child_id).await?;
    let d = detail(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok(Json(d))
}

/// Removes a component (e.g. replaced during a repair). The link is kept in the history.
#[utoipa::path(post, path = "/serials/{id}/components/{child_id}/remove", tag = "engineering",
    params(("id" = Uuid, Path), ("child_id" = Uuid, Path)), request_body = DetachInput,
    responses((status = 200, body = SerialUnitDetail), (status = 404, body = ErrorBody)))]
async fn detach_component(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((id, child_id)): Path<(Uuid, Uuid)>,
    Json(input): Json<DetachInput>,
) -> AppResult<Json<SerialUnitDetail>> {
    user.require(Permission::SerialsWrite)?;
    let child_status = input.child_status.as_deref().unwrap_or("in_stock");
    if !matches!(child_status, "in_stock" | "scrapped") {
        return Err(AppError::Validation(
            "child_status must be in_stock or scrapped".into(),
        ));
    }
    let mut tx = state.db.begin().await?;
    lock(&mut tx, &[id, child_id]).await?;
    load(&mut tx, user.company_id, id).await?;
    let removed = sqlx::query(
        "UPDATE engineering.serial_unit_components SET removed_at = now(), removed_by = $3
         WHERE parent_id = $1 AND child_id = $2 AND removed_at IS NULL",
    )
    .bind(id)
    .bind(child_id)
    .bind(user.user_id)
    .execute(&mut *tx)
    .await?;
    if removed.rows_affected() == 0 {
        return Err(AppError::NotFound("component link"));
    }
    sqlx::query(
        "UPDATE engineering.serial_units SET status = $2, updated_at = now() WHERE id = $1",
    )
    .bind(child_id)
    .bind(child_status)
    .execute(&mut *tx)
    .await?;
    audit::record(
        &mut tx,
        &user,
        "serial_unit",
        id,
        "component_removed",
        serde_json::json!({ "child_id": child_id, "child_status": child_status }),
    )
    .await?;
    let d = detail(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok(Json(d))
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(list_serials))
        .routes(routes!(create_serial))
        .routes(routes!(get_serial))
        .routes(routes!(set_status))
        .routes(routes!(set_warranty))
        .routes(routes!(attach_component))
        .routes(routes!(detach_component))
}
