//! Reservations of stock for sales order lines, and availability (ATP) on the order.

use std::collections::HashMap;

use axum::extract::{Path, Query, State};
use axum::Json;
use chrono::{DateTime, Utc};
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection};
use tradocraft_core::{audit, new_id, AppError, AppResult, AppState, CurrentUser, Permission};
use tradocraft_products::get_product;
use utoipa::{IntoParams, ToSchema};
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::ledger::to_stock_quantity;

type ErrorBody = tradocraft_core::error::ErrorBody;

/// Order statuses in which stock can be reserved (the customer has confirmed).
const RESERVABLE: [&str; 6] = [
    "confirmed",
    "in_planning",
    "planned",
    "in_production",
    "ready_for_shipping",
    "partially_shipped",
];

#[derive(Debug, Serialize, FromRow, ToSchema)]
pub struct Allocation {
    pub id: Uuid,
    pub location_id: Uuid,
    pub location: String,
    pub lot_id: Option<Uuid>,
    pub lot_number: Option<String>,
    #[schema(value_type = String)]
    pub quantity: Decimal,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct LineReservation {
    pub order_line_id: Uuid,
    pub product_id: Uuid,
    pub product_code: String,
    /// Ordered quantity in the stock unit of the product. 0 when the unit of the line no longer
    /// converts and the response is for a release.
    #[schema(value_type = String)]
    pub ordered: Decimal,
    /// Already shipped from reservations of this line, in the stock unit. What is still to be
    /// reserved is `ordered` minus `consumed`.
    #[schema(value_type = String)]
    pub consumed: Decimal,
    #[schema(value_type = String)]
    pub reserved: Decimal,
    pub allocations: Vec<Allocation>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct ReserveInput {
    /// The quantity that should be reserved for the line in total, in the stock unit of the
    /// product. More reserves additional stock, less releases the newest allocations, 0 releases all.
    #[schema(value_type = String, example = "5")]
    pub quantity: Decimal,
    /// Take additional stock only from this warehouse...
    pub warehouse_id: Option<Uuid>,
    /// ...or this location...
    pub location_id: Option<Uuid>,
    /// ...or this lot.
    pub lot_id: Option<Uuid>,
}

#[derive(FromRow)]
struct LineInfo {
    order_id: Uuid,
    order_number: String,
    order_status: String,
    product_id: Option<Uuid>,
    quantity: Decimal,
    unit: String,
    is_current: bool,
}

/// Loads an order line. With `lock` the order row is locked until the transaction ends, so that a
/// reservation and a cancellation of the same order cannot interleave: the status read here is
/// the status the reservation commits against.
async fn load_line(
    conn: &mut PgConnection,
    company_id: Uuid,
    line_id: Uuid,
    lock: bool,
) -> AppResult<LineInfo> {
    let sql = format!(
        "SELECT o.id AS order_id, o.number AS order_number, o.status AS order_status, ol.product_id, ol.quantity,
                ol.unit, (ol.revision = COALESCE(o.confirmed_revision, o.current_revision)) AS is_current
         FROM sales.order_lines ol JOIN sales.orders o ON o.id = ol.order_id
         WHERE ol.id = $1 AND o.company_id = $2{}",
        if lock { " FOR UPDATE OF o" } else { "" }
    );
    sqlx::query_as(&sql)
        .bind(line_id)
        .bind(company_id)
        .fetch_optional(conn)
        .await?
        .ok_or(AppError::NotFound("order line"))
}

/// The reference type of a sales order line.
pub const SALES_ORDER_LINE: &str = "sales_order_line";
/// The reference type of a component a production order needs.
pub const PRODUCTION_COMPONENT: &str = "production_component";
/// The references a reservation can be for. A new type needs the CHECK in the migration widened.
pub const REFERENCE_TYPES: [&str; 2] = [SALES_ORDER_LINE, PRODUCTION_COMPONENT];

/// The active allocations held for a reference.
pub async fn allocations_for(
    conn: &mut PgConnection,
    company_id: Uuid,
    reference_type: &str,
    reference_id: Uuid,
) -> AppResult<Vec<Allocation>> {
    Ok(sqlx::query_as(
        "SELECT r.id, r.location_id, w.code || '/' || l.code AS location, r.lot_id, lot.lot_number, r.quantity, r.created_at
         FROM inventory.reservations r
         JOIN inventory.locations l ON l.id = r.location_id
         JOIN inventory.warehouses w ON w.id = l.warehouse_id
         LEFT JOIN inventory.lots lot ON lot.id = r.lot_id
         WHERE r.company_id = $1 AND r.reference_type = $2 AND r.reference_id = $3 AND r.status = 'active'
         ORDER BY r.created_at, r.id",
    )
    .bind(company_id)
    .bind(reference_type)
    .bind(reference_id)
    .fetch_all(conn)
    .await?)
}

/// The reservation of an order line. `lenient` is for the response to a release: a line whose
/// unit has lost its conversion reports `ordered` as 0 instead of failing, so the stock can still
/// be released.
/// What is ordered, shipped from reservations and reserved for an order line, with the
/// allocations (the picking list). Used by delivery (ADR 0035).
pub async fn line_reservation(
    conn: &mut PgConnection,
    company_id: Uuid,
    line_id: Uuid,
    lenient: bool,
) -> AppResult<LineReservation> {
    let line = load_line(conn, company_id, line_id, false).await?;
    let product_id = line
        .product_id
        .ok_or_else(|| AppError::Validation("this order line has no product".into()))?;
    let product = get_product(&mut *conn, product_id).await?;
    let ordered = match ordered_in_stock_unit(conn, &product, &line).await {
        Ok(q) => q,
        Err(AppError::Validation(_)) if lenient => Decimal::ZERO,
        Err(e) => return Err(e),
    };
    let consumed = consumed_by(conn, company_id, SALES_ORDER_LINE, line_id, product_id).await?;
    let allocations = allocations_for(conn, company_id, SALES_ORDER_LINE, line_id).await?;
    Ok(LineReservation {
        order_line_id: line_id,
        product_id,
        product_code: product.code,
        ordered,
        consumed,
        reserved: allocations.iter().map(|a| a.quantity).sum(),
        allocations,
    })
}

/// What shipments have taken out of the reservations of a reference, in the stock unit. The
/// quantity stays on the reservation rows after they are closed.
pub async fn consumed_by(
    conn: &mut PgConnection,
    company_id: Uuid,
    reference_type: &str,
    reference_id: Uuid,
    product_id: Uuid,
) -> AppResult<Decimal> {
    Ok(sqlx::query_scalar(
        "SELECT COALESCE(sum(consumed_quantity), 0) FROM inventory.reservations
         WHERE company_id = $1 AND reference_type = $2 AND reference_id = $3 AND product_id = $4",
    )
    .bind(company_id)
    .bind(reference_type)
    .bind(reference_id)
    .bind(product_id)
    .fetch_one(conn)
    .await?)
}

/// What was shipped for an order line by plain shipment issues, outside delivery notes (the
/// issue endpoint names the line as the move's reference), in the stock unit. Reversed moves do
/// not count. Delivery adds this to what its own notes shipped.
pub async fn shipped_outside_deliveries(
    conn: &mut PgConnection,
    company_id: Uuid,
    order_line_id: Uuid,
) -> AppResult<Decimal> {
    Ok(sqlx::query_scalar(
        "SELECT COALESCE(sum(m.quantity), 0) FROM inventory.stock_moves m
         WHERE m.company_id = $1 AND m.kind = 'issue' AND m.reason = 'shipment'
           AND m.reference_type = $2 AND m.reference_id = $3
           AND NOT EXISTS (SELECT 1 FROM inventory.stock_moves r WHERE r.reversed_of = m.id)",
    )
    .bind(company_id)
    .bind(SALES_ORDER_LINE)
    .bind(order_line_id)
    .fetch_one(conn)
    .await?)
}

/// Whether a lot is past its expiry date (stock in it cannot be promised or shipped).
pub async fn lot_expired(
    conn: &mut PgConnection,
    company_id: Uuid,
    lot_id: Uuid,
) -> AppResult<bool> {
    Ok(sqlx::query_scalar(
        "SELECT COALESCE(expiry_date < current_date, false) FROM inventory.lots
         WHERE id = $1 AND company_id = $2",
    )
    .bind(lot_id)
    .bind(company_id)
    .fetch_optional(conn)
    .await?
    .unwrap_or(false))
}

/// A serial unit that is in stock.
#[derive(Debug, FromRow)]
pub struct StockedUnit {
    pub id: Uuid,
    pub serial_number: String,
}

/// Where a serial unit is in stock; `None` when it is not in a stock location.
pub async fn serial_location(
    conn: &mut PgConnection,
    company_id: Uuid,
    serial_unit_id: Uuid,
) -> AppResult<Option<Uuid>> {
    Ok(sqlx::query_scalar(
        "SELECT location_id FROM inventory.serial_stock WHERE serial_unit_id = $1 AND company_id = $2",
    )
    .bind(serial_unit_id)
    .bind(company_id)
    .fetch_optional(conn)
    .await?)
}

/// A serial unit in stock, with where it is.
#[derive(Debug, FromRow)]
pub struct StockedUnitAt {
    pub id: Uuid,
    pub serial_number: String,
    pub location_id: Uuid,
    pub location: String,
}

/// The units of a product in stock anywhere in the company, optionally filtered on (part of) the
/// serial number. Production offers these when serial components are chosen.
pub async fn serial_units_in_stock(
    conn: &mut PgConnection,
    company_id: Uuid,
    product_id: Uuid,
    q: Option<&str>,
    limit: i64,
) -> AppResult<Vec<StockedUnitAt>> {
    Ok(sqlx::query_as(
        "SELECT su.id, su.serial_number, ss.location_id,
                COALESCE(w.code || '/' || l.code, l.code) AS location
         FROM inventory.serial_stock ss
         JOIN engineering.serial_units su ON su.id = ss.serial_unit_id
         JOIN inventory.locations l ON l.id = ss.location_id
         LEFT JOIN inventory.warehouses w ON w.id = l.warehouse_id
         WHERE ss.company_id = $1 AND ss.product_id = $2 AND l.kind = 'internal'
           AND ($3::text IS NULL OR su.serial_number ILIKE $3)
         ORDER BY su.serial_number LIMIT $4",
    )
    .bind(company_id)
    .bind(product_id)
    .bind(q.map(|q| format!("%{q}%")))
    .bind(limit)
    .fetch_all(conn)
    .await?)
}

/// The units of a product that are in stock at a location, optionally filtered on (part of) the
/// serial number. Delivery offers these when a serial number is chosen for a pick.
pub async fn serial_units_at(
    conn: &mut PgConnection,
    company_id: Uuid,
    product_id: Uuid,
    location_id: Uuid,
    q: Option<&str>,
    limit: i64,
) -> AppResult<Vec<StockedUnit>> {
    Ok(sqlx::query_as(
        "SELECT su.id, su.serial_number
         FROM inventory.serial_stock ss
         JOIN engineering.serial_units su ON su.id = ss.serial_unit_id
         WHERE ss.company_id = $1 AND ss.product_id = $2 AND ss.location_id = $3
           AND ($4::text IS NULL OR su.serial_number ILIKE $4)
         ORDER BY su.serial_number LIMIT $5",
    )
    .bind(company_id)
    .bind(product_id)
    .bind(location_id)
    .bind(q.map(|q| format!("%{q}%")))
    .bind(limit)
    .fetch_all(conn)
    .await?)
}

/// The ordered quantity in the stock unit of the product. A line in a unit that does not convert
/// is an error, never a guess.
async fn ordered_in_stock_unit(
    conn: &mut PgConnection,
    product: &tradocraft_products::Product,
    line: &LineInfo,
) -> AppResult<Decimal> {
    Ok(
        to_stock_quantity(conn, product, line.quantity, Some(&line.unit))
            .await?
            .0,
    )
}

#[utoipa::path(get, path = "/inventory/order-lines/{id}/reservation", tag = "inventory", params(("id" = Uuid, Path)),
    responses((status = 200, body = LineReservation), (status = 404, body = ErrorBody)))]
async fn get_reservation(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<LineReservation>> {
    user.require(Permission::InventoryRead)?;
    let mut conn = state.db.acquire().await?;
    Ok(Json(
        line_reservation(&mut conn, user.company_id, id, false).await?,
    ))
}

/// Sets how much stock is reserved for an order line. Idempotent: the same call twice changes
/// nothing the second time.
#[utoipa::path(put, path = "/inventory/order-lines/{id}/reservation", tag = "inventory", params(("id" = Uuid, Path)),
    request_body = ReserveInput,
    responses((status = 200, body = LineReservation), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn set_reservation(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(line_id): Path<Uuid>,
    Json(input): Json<ReserveInput>,
) -> AppResult<Json<LineReservation>> {
    user.require(Permission::InventoryWrite)?;
    if input.quantity < Decimal::ZERO || input.quantity.round_dp(4) != input.quantity {
        return Err(AppError::Validation(
            "quantity must be 0 or more, with at most 4 decimals".into(),
        ));
    }
    let mut tx = state.db.begin().await?;
    let line = load_line(&mut tx, user.company_id, line_id, true).await?;
    let product_id = line
        .product_id
        .ok_or_else(|| AppError::Validation("this order line has no product".into()))?;
    let product = get_product(&mut *tx, product_id).await?;
    if product.product_type == "service" {
        return Err(AppError::Validation(format!(
            "{} is a service and is not stocked",
            product.code
        )));
    }
    let target = ReserveTarget {
        reference_type: SALES_ORDER_LINE,
        reference_id: line_id,
        product_id,
    };
    let pin = ReservePin {
        warehouse_id: input.warehouse_id,
        location_id: input.location_id,
        lot_id: input.lot_id,
    };
    // Raising a reservation needs a confirmed order and at most what is still to be shipped;
    // lowering or releasing is always possible, also when the unit of the line has lost its
    // conversion.
    if input.quantity > held_by(&mut tx, user.company_id, &target).await? {
        if !RESERVABLE.contains(&line.order_status.as_str()) || !line.is_current {
            return Err(AppError::Conflict(format!(
                "order {} is {}; stock can be reserved once the customer has confirmed it",
                line.order_number, line.order_status
            )));
        }
        let ordered = ordered_in_stock_unit(&mut tx, &product, &line).await?;
        let consumed = consumed_by(
            &mut tx,
            user.company_id,
            SALES_ORDER_LINE,
            line_id,
            product_id,
        )
        .await?;
        let remaining = (ordered - consumed).max(Decimal::ZERO);
        if input.quantity > remaining {
            return Err(AppError::Validation(format!(
                "the line still needs {} {} ({} ordered, {} already shipped); cannot reserve {}",
                remaining.normalize(),
                product.unit,
                ordered.normalize(),
                consumed.normalize(),
                input.quantity.normalize()
            )));
        }
    }
    let have = set_reserved(&mut tx, &user, &target, input.quantity, &pin).await?;
    let want = input.quantity;
    audit::record(
        &mut tx,
        &user,
        "order_line",
        line_id,
        "reservation_set",
        serde_json::json!({ "order_id": line.order_id, "product_id": product_id, "from": have, "to": want }),
    )
    .await?;
    let result = line_reservation(&mut tx, user.company_id, line_id, true).await?;
    tx.commit().await?;
    Ok(Json(result))
}

/// What a reservation is for.
#[derive(Debug, Clone, Copy)]
pub struct ReserveTarget<'a> {
    /// One of [`REFERENCE_TYPES`].
    pub reference_type: &'a str,
    pub reference_id: Uuid,
    pub product_id: Uuid,
}

/// Where additional stock may come from; without a pin: normal warehouses, earliest expiry first.
#[derive(Debug, Clone, Copy, Default)]
pub struct ReservePin {
    pub warehouse_id: Option<Uuid>,
    pub location_id: Option<Uuid>,
    pub lot_id: Option<Uuid>,
}

/// The quantity currently held for the reference and product.
pub async fn held_by(
    conn: &mut PgConnection,
    company_id: Uuid,
    t: &ReserveTarget<'_>,
) -> AppResult<Decimal> {
    Ok(sqlx::query_scalar(
        "SELECT COALESCE(sum(quantity), 0) FROM inventory.reservations
         WHERE company_id = $1 AND reference_type = $2 AND reference_id = $3 AND product_id = $4
           AND status = 'active'",
    )
    .bind(company_id)
    .bind(t.reference_type)
    .bind(t.reference_id)
    .bind(t.product_id)
    .fetch_one(conn)
    .await?)
}

/// A serial-tracked product ships one unit at a time: a fraction could never be consumed, so it
/// cannot be reserved. [`set_reserved`] applies this; a caller that decides not to reserve before
/// getting there calls it too, so that it does not hide a refusal `set_reserved` would give.
pub fn check_whole_units(tracking: &str, want: Decimal) -> AppResult<()> {
    if tracking == "serial" && want.fract() != Decimal::ZERO {
        return Err(AppError::Validation(
            "a serial-tracked product can only be reserved in whole units".into(),
        ));
    }
    Ok(())
}

/// Sets how much of a product is held for a reference, in the caller's transaction: more
/// allocates from free stock (all or nothing), less releases the newest allocations first, 0
/// releases everything. Returns the quantity that was held before. The owning module checks that
/// the reference exists and may be reserved for; this function checks the type and the stock.
pub async fn set_reserved(
    conn: &mut PgConnection,
    user: &CurrentUser,
    t: &ReserveTarget<'_>,
    want: Decimal,
    pin: &ReservePin,
) -> AppResult<Decimal> {
    if !REFERENCE_TYPES.contains(&t.reference_type) {
        return Err(AppError::Validation(format!(
            "reference_type must be one of {}",
            REFERENCE_TYPES.join(", ")
        )));
    }
    if want < Decimal::ZERO || want.round_dp(4) != want {
        return Err(AppError::Validation(
            "quantity must be 0 or more, with at most 4 decimals".into(),
        ));
    }
    if want.fract() != Decimal::ZERO {
        let tracking: Option<String> =
            sqlx::query_scalar("SELECT tracking FROM products.products WHERE id = $1")
                .bind(t.product_id)
                .fetch_optional(&mut *conn)
                .await?;
        check_whole_units(tracking.as_deref().unwrap_or_default(), want)?;
    }
    // Serialise reservations and moves on this product, locking balance rows in the same order
    // (location, lot) as `post_move` does.
    sqlx::query(
        "SELECT id FROM inventory.stock_balances WHERE company_id = $1 AND product_id = $2
         ORDER BY location_id, COALESCE(lot_id, '00000000-0000-0000-0000-000000000000'::uuid) FOR UPDATE",
    )
    .bind(user.company_id)
    .bind(t.product_id)
    .execute(&mut *conn)
    .await?;
    let have = held_by(conn, user.company_id, t).await?;
    if want > have {
        allocate(conn, user, t, want - have, pin).await?;
    } else if want < have {
        release_newest(conn, user, t, have - want).await?;
    }
    Ok(have)
}

#[derive(FromRow)]
struct Candidate {
    location_id: Uuid,
    lot_id: Option<Uuid>,
    free: Decimal,
}

/// The stock a reservation can draw from: free quantity (on hand minus what is already reserved)
/// per location and lot, in active warehouses and internal locations, without expired lots. Bound
/// to `$1` company, `$2` product and the pin: `$3` warehouse, `$4` location, `$5` lot.
const CANDIDATES: &str = "SELECT b.location_id, b.lot_id, b.quantity - COALESCE(res.q, 0) AS free
         FROM inventory.stock_balances b
         JOIN inventory.locations l ON l.id = b.location_id AND l.kind = 'internal' AND l.active
         JOIN inventory.warehouses w ON w.id = l.warehouse_id AND w.active
         LEFT JOIN inventory.lots lot ON lot.id = b.lot_id
         LEFT JOIN (
             SELECT location_id, lot_id, sum(quantity) AS q FROM inventory.reservations
             WHERE company_id = $1 AND product_id = $2 AND status = 'active' GROUP BY location_id, lot_id
         ) res ON res.location_id = b.location_id AND res.lot_id IS NOT DISTINCT FROM b.lot_id
         WHERE b.company_id = $1 AND b.product_id = $2
           AND ($3::uuid IS NULL OR w.id = $3) AND ($4::uuid IS NULL OR l.id = $4) AND ($5::uuid IS NULL OR b.lot_id = $5)
           AND (w.kind = 'warehouse' OR $3::uuid IS NOT NULL OR $4::uuid IS NOT NULL)
           AND (lot.expiry_date IS NULL OR lot.expiry_date >= current_date)
           AND b.quantity - COALESCE(res.q, 0) > 0";

/// How much of a product [`set_reserved`] could allocate right now without a pin: free stock in
/// the normal warehouses (what is not reserved, expired lots left out). A read: nothing is locked,
/// so it is a figure to plan with, not a promise.
pub async fn free_to_reserve(
    conn: &mut PgConnection,
    company_id: Uuid,
    product_id: Uuid,
) -> AppResult<Decimal> {
    Ok(sqlx::query_scalar(&format!(
        "SELECT COALESCE(sum(c.free), 0) FROM ({CANDIDATES}) c"
    ))
    .bind(company_id)
    .bind(product_id)
    .bind(None::<Uuid>)
    .bind(None::<Uuid>)
    .bind(None::<Uuid>)
    .fetch_one(conn)
    .await?)
}

async fn allocate(
    conn: &mut PgConnection,
    user: &CurrentUser,
    t: &ReserveTarget<'_>,
    mut needed: Decimal,
    pin: &ReservePin,
) -> AppResult<()> {
    let candidates: Vec<Candidate> = sqlx::query_as(&format!(
        "{CANDIDATES} ORDER BY lot.expiry_date NULLS LAST, w.code, l.code FOR UPDATE OF b"
    ))
    .bind(user.company_id)
    .bind(t.product_id)
    .bind(pin.warehouse_id)
    .bind(pin.location_id)
    .bind(pin.lot_id)
    .fetch_all(&mut *conn)
    .await?;
    let free_total: Decimal = candidates.iter().map(|c| c.free).sum();
    if free_total < needed {
        return Err(AppError::Conflict(format!(
            "only {} available to reserve, {} needed",
            free_total.normalize(),
            needed.normalize()
        )));
    }
    for c in candidates {
        if needed <= Decimal::ZERO {
            break;
        }
        let take = c.free.min(needed);
        // More at a place that already holds stock for this reference adds to that row.
        sqlx::query(
            "INSERT INTO inventory.reservations (id, company_id, reference_type, reference_id, product_id, location_id,
                                                  lot_id, quantity, created_by)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
             ON CONFLICT (reference_type, reference_id, product_id, location_id,
                          (COALESCE(lot_id, '00000000-0000-0000-0000-000000000000'::uuid))) WHERE status = 'active'
             DO UPDATE SET quantity = inventory.reservations.quantity + EXCLUDED.quantity",
        )
        .bind(new_id())
        .bind(user.company_id)
        .bind(t.reference_type)
        .bind(t.reference_id)
        .bind(t.product_id)
        .bind(c.location_id)
        .bind(c.lot_id)
        .bind(take)
        .bind(user.user_id)
        .execute(&mut *conn)
        .await?;
        needed -= take;
    }
    Ok(())
}

async fn release_newest(
    conn: &mut PgConnection,
    user: &CurrentUser,
    t: &ReserveTarget<'_>,
    mut to_release: Decimal,
) -> AppResult<()> {
    let rows: Vec<(Uuid, Decimal)> = sqlx::query_as(
        "SELECT id, quantity FROM inventory.reservations
         WHERE company_id = $1 AND reference_type = $2 AND reference_id = $3 AND product_id = $4 AND status = 'active'
         ORDER BY created_at DESC, id DESC FOR UPDATE",
    )
    .bind(user.company_id)
    .bind(t.reference_type)
    .bind(t.reference_id)
    .bind(t.product_id)
    .fetch_all(&mut *conn)
    .await?;
    for (id, quantity) in rows {
        if to_release <= Decimal::ZERO {
            break;
        }
        if quantity <= to_release {
            sqlx::query("UPDATE inventory.reservations SET status = 'released', closed_at = now(), closed_by = $2 WHERE id = $1")
                .bind(id)
                .bind(user.user_id)
                .execute(&mut *conn)
                .await?;
            to_release -= quantity;
        } else {
            sqlx::query("UPDATE inventory.reservations SET quantity = quantity - $2 WHERE id = $1")
                .bind(id)
                .bind(to_release)
                .execute(&mut *conn)
                .await?;
            to_release = Decimal::ZERO;
        }
    }
    Ok(())
}

/// Releases everything held for a reference (for example the components of a cancelled
/// production order). Returns the number of allocations released.
pub async fn release_reference(
    conn: &mut PgConnection,
    company_id: Uuid,
    reference_type: &str,
    reference_id: Uuid,
    user_id: Option<Uuid>,
) -> Result<u64, sqlx::Error> {
    let done = sqlx::query(
        "UPDATE inventory.reservations SET status = 'released', closed_at = now(), closed_by = $4
         WHERE company_id = $1 AND reference_type = $2 AND reference_id = $3 AND status = 'active'",
    )
    .bind(company_id)
    .bind(reference_type)
    .bind(reference_id)
    .bind(user_id)
    .execute(conn)
    .await?;
    Ok(done.rows_affected())
}

/// Releases every active reservation of an order, for example when it is cancelled. Runs in the
/// caller's transaction; returns the number of allocations released.
pub async fn release_for_order(
    conn: &mut PgConnection,
    company_id: Uuid,
    order_id: Uuid,
    user_id: Option<Uuid>,
) -> Result<u64, sqlx::Error> {
    let done = sqlx::query(
        "UPDATE inventory.reservations r SET status = 'released', closed_at = now(), closed_by = $3
         FROM sales.order_lines ol
         WHERE r.reference_type = 'sales_order_line' AND ol.id = r.reference_id AND ol.order_id = $2
           AND r.company_id = $1 AND r.status = 'active'",
    )
    .bind(company_id)
    .bind(order_id)
    .bind(user_id)
    .execute(conn)
    .await?;
    Ok(done.rows_affected())
}

// -------------------------------------------------------------------------------------------
// Reservation list and availability on the order
// -------------------------------------------------------------------------------------------

#[derive(Debug, Serialize, FromRow, ToSchema)]
pub struct ReservationRow {
    pub id: Uuid,
    /// sales_order_line | production_component
    pub reference_type: String,
    pub reference_id: Uuid,
    /// The order, for a sales order line.
    pub order_id: Option<Uuid>,
    pub order_number: Option<String>,
    pub customer_name: Option<String>,
    pub order_line_id: Option<Uuid>,
    pub position: Option<i32>,
    pub product_id: Uuid,
    pub product_code: String,
    pub location: String,
    pub lot_number: Option<String>,
    /// Still held.
    #[schema(value_type = String)]
    pub quantity: Decimal,
    /// Already shipped or consumed from this allocation.
    #[schema(value_type = String)]
    pub consumed_quantity: Decimal,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct ReservationParams {
    pub product_id: Option<Uuid>,
    pub order_id: Option<Uuid>,
    /// Page size (default 100, at most 500).
    pub limit: Option<i64>,
    /// Rows to skip, in the order of the list.
    pub offset: Option<i64>,
}

/// Active reservations, for example to see which orders hold a product. Paged with `limit` and
/// `offset`; a page shorter than `limit` is the last one.
#[utoipa::path(get, path = "/inventory/reservations", tag = "inventory", params(ReservationParams),
    responses((status = 200, body = Vec<ReservationRow>)))]
async fn list_reservations(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(p): Query<ReservationParams>,
) -> AppResult<Json<Vec<ReservationRow>>> {
    user.require(Permission::InventoryRead)?;
    Ok(Json(
        sqlx::query_as(
            "SELECT r.id, r.reference_type, r.reference_id, o.id AS order_id, o.number AS order_number,
                    c.name AS customer_name, ol.id AS order_line_id,
                    ol.position, r.product_id, pr.code AS product_code, w.code || '/' || l.code AS location,
                    lot.lot_number, r.quantity, r.consumed_quantity, r.created_at
             FROM inventory.reservations r
             LEFT JOIN sales.order_lines ol ON r.reference_type = 'sales_order_line' AND ol.id = r.reference_id
             LEFT JOIN sales.orders o ON o.id = ol.order_id AND o.company_id = r.company_id
             LEFT JOIN crm.customers c ON c.id = o.customer_id
             JOIN products.products pr ON pr.id = r.product_id
             JOIN inventory.locations l ON l.id = r.location_id
             JOIN inventory.warehouses w ON w.id = l.warehouse_id
             LEFT JOIN inventory.lots lot ON lot.id = r.lot_id
             WHERE r.company_id = $1 AND r.status = 'active'
               AND ($2::uuid IS NULL OR r.product_id = $2) AND ($3::uuid IS NULL OR o.id = $3)
             ORDER BY o.number NULLS LAST, ol.position, r.created_at, r.id LIMIT $4 OFFSET $5",
        )
        .bind(user.company_id)
        .bind(p.product_id)
        .bind(p.order_id)
        .bind(p.limit.unwrap_or(100).clamp(1, 500))
        .bind(p.offset.unwrap_or(0).max(0))
        .fetch_all(&state.db)
        .await?,
    ))
}

#[derive(Debug, Serialize, ToSchema)]
pub struct LineAvailability {
    pub order_line_id: Uuid,
    pub position: i32,
    pub product_id: Option<Uuid>,
    pub product_code: String,
    pub description: String,
    pub unit: String,
    /// Ordered quantity, in the unit of the line.
    #[schema(value_type = String)]
    pub ordered: Decimal,
    /// Ordered quantity in the stock unit of the product (0 when the line is not stocked).
    #[schema(value_type = String)]
    pub ordered_stock: Decimal,
    /// Already shipped from reservations of this line, in the stock unit.
    #[schema(value_type = String)]
    pub consumed: Decimal,
    /// Reserved for this line, in the stock unit.
    #[schema(value_type = String)]
    pub reserved: Decimal,
    /// In the warehouses.
    #[schema(value_type = String)]
    pub on_hand: Decimal,
    /// Reserved for all orders.
    #[schema(value_type = String)]
    pub reserved_total: Decimal,
    /// Of the on hand quantity: in lots that are past their expiry date (not available).
    #[schema(value_type = String)]
    pub expired: Decimal,
    /// Available to promise: on hand minus expired stock minus what is reserved in good lots.
    #[schema(value_type = String)]
    pub available: Decimal,
    /// What neither the reservation nor free stock covers.
    #[schema(value_type = String)]
    pub shortfall: Decimal,
    /// reserved | available | partial | short | not_stocked
    pub state: String,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct OrderAvailability {
    pub order_id: Uuid,
    pub order_number: String,
    pub order_status: String,
    /// Stock can be reserved: the customer has confirmed and the order is not cancelled.
    pub reservable: bool,
    pub lines: Vec<LineAvailability>,
}

#[derive(FromRow)]
struct OrderLineRow {
    id: Uuid,
    position: i32,
    product_id: Option<Uuid>,
    product_code: String,
    description: String,
    unit: String,
    quantity: Decimal,
    product_type: Option<String>,
}

/// Availability (ATP) of every line of the order: what is in the warehouses, what is reserved,
/// and what this order's lines still lack. Van stock is not counted.
#[utoipa::path(get, path = "/inventory/orders/{id}/availability", tag = "inventory", params(("id" = Uuid, Path)),
    responses((status = 200, body = OrderAvailability), (status = 404, body = ErrorBody)))]
async fn order_availability(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(order_id): Path<Uuid>,
) -> AppResult<Json<OrderAvailability>> {
    user.require(Permission::InventoryRead)?;
    let mut conn = state.db.acquire().await?;
    let head: Option<(String, String)> =
        sqlx::query_as("SELECT number, status FROM sales.orders WHERE id = $1 AND company_id = $2")
            .bind(order_id)
            .bind(user.company_id)
            .fetch_optional(&mut *conn)
            .await?;
    let (number, status) = head.ok_or(AppError::NotFound("order"))?;
    let lines: Vec<OrderLineRow> = sqlx::query_as(
        "SELECT ol.id, ol.position, ol.product_id, ol.product_code, ol.description, ol.unit, ol.quantity,
                p.product_type
         FROM sales.order_lines ol JOIN sales.orders o ON o.id = ol.order_id
         LEFT JOIN products.products p ON p.id = ol.product_id
         WHERE o.id = $1 AND ol.revision = COALESCE(o.confirmed_revision, o.current_revision)
         ORDER BY ol.position",
    )
    .bind(order_id)
    .fetch_all(&mut *conn)
    .await?;
    let ids: Vec<Uuid> = lines.iter().filter_map(|l| l.product_id).collect();
    // (on hand, of which in expired lots) per product: expired stock stays in the on hand figure
    // but is not available.
    let on_hand: HashMap<Uuid, (Decimal, Decimal)> = sqlx::query_as::<_, (Uuid, Decimal, Decimal)>(
        "SELECT b.product_id, sum(b.quantity),
                    COALESCE(sum(b.quantity) FILTER (WHERE lot.expiry_date < current_date), 0)
             FROM inventory.stock_balances b
             JOIN inventory.locations l ON l.id = b.location_id AND l.kind = 'internal'
             JOIN inventory.warehouses w ON w.id = l.warehouse_id AND w.kind = 'warehouse'
             LEFT JOIN inventory.lots lot ON lot.id = b.lot_id
             WHERE b.company_id = $1 AND b.product_id = ANY($2) GROUP BY b.product_id",
    )
    .bind(user.company_id)
    .bind(&ids)
    .fetch_all(&mut *conn)
    .await?
    .into_iter()
    .map(|(p, q, e)| (p, (q, e)))
    .collect();
    // (reserved, of which in expired lots) per product.
    let reserved: HashMap<Uuid, (Decimal, Decimal)> =
        sqlx::query_as::<_, (Uuid, Decimal, Decimal)>(
            "SELECT r.product_id, sum(r.quantity),
                    COALESCE(sum(r.quantity) FILTER (WHERE lot.expiry_date < current_date), 0)
             FROM inventory.reservations r
             JOIN inventory.locations l ON l.id = r.location_id
             JOIN inventory.warehouses w ON w.id = l.warehouse_id AND w.kind = 'warehouse'
             LEFT JOIN inventory.lots lot ON lot.id = r.lot_id
             WHERE r.company_id = $1 AND r.status = 'active' AND r.product_id = ANY($2) GROUP BY r.product_id",
        )
        .bind(user.company_id)
        .bind(&ids)
        .fetch_all(&mut *conn)
        .await?
        .into_iter()
        .map(|(p, q, e)| (p, (q, e)))
        .collect();
    // (reserved, of which in expired lots) per line of this order.
    let own: HashMap<Uuid, (Decimal, Decimal)> = sqlx::query_as::<_, (Uuid, Decimal, Decimal)>(
        "SELECT r.reference_id, sum(r.quantity),
                COALESCE(sum(r.quantity) FILTER (WHERE lot.expiry_date < current_date), 0)
         FROM inventory.reservations r
         JOIN sales.order_lines ol ON ol.id = r.reference_id
         LEFT JOIN inventory.lots lot ON lot.id = r.lot_id
         WHERE r.company_id = $1 AND r.reference_type = 'sales_order_line' AND r.status = 'active' AND ol.order_id = $2
         GROUP BY r.reference_id",
    )
    .bind(user.company_id)
    .bind(order_id)
    .fetch_all(&mut *conn)
    .await?
    .into_iter()
    .map(|(l, q, e)| (l, (q, e)))
    .collect();
    // Good stock that earlier lines of this order already count on, per product: a later line of
    // the same product only gets what is left.
    let mut claimed: HashMap<Uuid, Decimal> = HashMap::new();

    let mut out = Vec::new();
    for l in lines {
        let stocked =
            l.product_id.is_some() && l.product_type.as_deref().is_some_and(|t| t != "service");
        let mut item = LineAvailability {
            order_line_id: l.id,
            position: l.position,
            product_id: l.product_id,
            product_code: l.product_code,
            description: l.description,
            unit: l.unit.clone(),
            ordered: l.quantity,
            ordered_stock: Decimal::ZERO,
            consumed: Decimal::ZERO,
            reserved: Decimal::ZERO,
            on_hand: Decimal::ZERO,
            reserved_total: Decimal::ZERO,
            expired: Decimal::ZERO,
            available: Decimal::ZERO,
            shortfall: Decimal::ZERO,
            state: "not_stocked".into(),
        };
        if stocked {
            let pid = l.product_id.unwrap();
            let product = get_product(&mut *conn, pid).await?;
            let (ordered_stock, _) =
                to_stock_quantity(&mut conn, &product, l.quantity, Some(&l.unit)).await?;
            let consumed =
                consumed_by(&mut conn, user.company_id, SALES_ORDER_LINE, l.id, pid).await?;
            // What shipments already took is not demand any more.
            let needed = (ordered_stock - consumed).max(Decimal::ZERO);
            item.ordered_stock = ordered_stock;
            item.consumed = consumed;
            let (on, expired) = on_hand.get(&pid).copied().unwrap_or_default();
            let (held, held_expired) = reserved.get(&pid).copied().unwrap_or_default();
            item.on_hand = on;
            item.expired = expired;
            item.reserved_total = held;
            // Expired stock cannot be promised; what was reserved in expired lots no longer
            // reduces the good stock.
            item.available = on - expired - (held - held_expired);
            let (own_held, own_expired) = own.get(&l.id).copied().unwrap_or_default();
            item.reserved = own_held;
            // A reservation in an expired lot does not cover the demand.
            let covered = own_held - own_expired;
            let open = (needed - covered).max(Decimal::ZERO);
            let taken = claimed.get(&pid).copied().unwrap_or_default();
            let free = (item.available - taken).max(Decimal::ZERO);
            item.shortfall = (open - free).max(Decimal::ZERO);
            *claimed.entry(pid).or_default() += open.min(free);
            item.state = if open.is_zero() {
                "reserved"
            } else if item.shortfall.is_zero() {
                "available"
            } else if free.is_zero() && covered.is_zero() {
                "short"
            } else {
                "partial"
            }
            .into();
        }
        out.push(item);
    }
    Ok(Json(OrderAvailability {
        order_id,
        order_number: number,
        reservable: RESERVABLE.contains(&status.as_str()),
        order_status: status,
        lines: out,
    }))
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(get_reservation, set_reservation))
        .routes(routes!(list_reservations))
        .routes(routes!(order_availability))
}
