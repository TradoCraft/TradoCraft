//! Delivery notes: what leaves for a customer, picked from the stock reserved for a sales order.
//!
//! * A note is `planned` (editable), then `shipped` (stock is out, the reservations are consumed)
//!   or `cancelled`. Lines are in the stock unit of the product, like stock moves and reservations.
//! * Creating a note proposes lines from the order's reservations (the picking list); lines can be
//!   changed freely while the note is planned, also to pick stock that is not reserved.
//! * An order can be delivered in parts: it becomes `partially_shipped`, then `shipped`.
//! * A planned date on a day the customer is closed follows the company's closure policy.

use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::Json;
use chrono::{DateTime, Datelike, NaiveDate, Utc};
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection};
use tradocraft_core::{
    audit, new_id, numbering, AppError, AppResult, AppState, CurrentUser, Permission,
};
use tradocraft_crm::closures::{closure_on, next_open_day, Closure};
use tradocraft_inventory::reservations::{
    allocations_for, line_reservation, lot_expired, serial_units_at, shipped_outside_deliveries,
    SALES_ORDER_LINE,
};
use tradocraft_inventory::{post_move, virtual_location, NewMove, SerialEffect};
use utoipa::{IntoParams, ToSchema};
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::settings::load_settings;

type ErrorBody = tradocraft_core::error::ErrorBody;

/// Order statuses in which goods can be delivered.
const DELIVERABLE: [&str; 3] = ["confirmed", "ready_for_shipping", "partially_shipped"];

#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct DeliveryShipTo {
    pub name: String,
    pub street: String,
    pub postal_code: String,
    pub city: String,
    pub country_code: String,
}

/// The customer is closed on the planned date.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct ClosureWarning {
    /// The closure that covers the planned date.
    pub closure: Closure,
    /// The first day after the closure(s).
    pub next_open_day: NaiveDate,
}

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct DeliveryNoteLine {
    pub id: Uuid,
    pub position: i32,
    pub order_line_id: Uuid,
    /// Position of the order line on the order.
    pub order_position: i32,
    pub product_id: Uuid,
    pub product_code: String,
    pub product_name: String,
    /// none | serial | lot: serial-tracked lines need a serial number before shipping.
    pub tracking: String,
    /// In the stock unit of the product.
    #[schema(value_type = String, example = "2")]
    pub quantity: Decimal,
    pub unit: String,
    pub location_id: Uuid,
    pub location: String,
    pub lot_id: Option<Uuid>,
    pub lot_number: Option<String>,
    pub serial_unit_id: Option<Uuid>,
    pub serial_number: Option<String>,
    /// The stock move that took the goods out, once shipped.
    pub stock_move_id: Option<Uuid>,
}

#[derive(Debug, Clone, FromRow)]
struct NoteRow {
    id: Uuid,
    number: String,
    order_id: Uuid,
    order_number: String,
    order_revision: i32,
    customer_id: Uuid,
    customer_name: String,
    status: String,
    planned_date: Option<NaiveDate>,
    ship_to_name: String,
    ship_to_street: String,
    ship_to_postal_code: String,
    ship_to_city: String,
    ship_to_country_code: String,
    carrier: String,
    tracking_number: String,
    notes: String,
    planned_on_closure: bool,
    closure_override_reason: Option<String>,
    shipped_at: Option<DateTime<Utc>>,
    created_at: DateTime<Utc>,
    updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct DeliveryNote {
    pub id: Uuid,
    pub number: String,
    pub order_id: Uuid,
    pub order_number: String,
    pub order_revision: i32,
    pub customer_id: Uuid,
    pub customer_name: String,
    /// planned | shipped | cancelled
    pub status: String,
    pub planned_date: Option<NaiveDate>,
    pub ship_to: DeliveryShipTo,
    pub carrier: String,
    pub tracking_number: String,
    pub notes: String,
    /// The customer was closed on the planned date when it was saved.
    pub planned_on_closure: bool,
    /// Why a delivery on a closure was allowed (policy `override`).
    pub closure_override_reason: Option<String>,
    /// Live: the customer is closed on the planned date of a planned note, also when the closure
    /// was added after the date was set.
    pub closure_warning: Option<ClosureWarning>,
    pub shipped_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
    /// Send it back as `expected_updated_at` when saving: a note someone else changed meanwhile is refused.
    pub updated_at: DateTime<Utc>,
    pub lines: Vec<DeliveryNoteLine>,
}

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct DeliverySummary {
    pub id: Uuid,
    pub number: String,
    pub order_id: Uuid,
    pub order_number: String,
    pub customer_id: Uuid,
    pub customer_name: String,
    /// planned | shipped | cancelled
    pub status: String,
    pub planned_date: Option<NaiveDate>,
    pub carrier: String,
    pub tracking_number: String,
    pub planned_on_closure: bool,
    pub line_count: i64,
    pub shipped_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct DeliveryPage {
    pub items: Vec<DeliverySummary>,
    pub total: i64,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct CreateDeliveryInput {
    #[serde(default, deserialize_with = "tradocraft_core::serde_util::opt_date")]
    pub planned_date: Option<NaiveDate>,
    #[serde(default)]
    pub carrier: String,
    #[serde(default)]
    pub notes: String,
    /// Needed to plan on a closed day when the policy is `override`.
    pub closure_override_reason: Option<String>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct DeliveryShipToInput {
    pub name: String,
    #[serde(default)]
    pub street: String,
    #[serde(default)]
    pub postal_code: String,
    #[serde(default)]
    pub city: String,
    pub country_code: String,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct DeliveryLineInput {
    pub order_line_id: Uuid,
    /// In the stock unit of the product, at most four decimals; 1 for a serial-tracked product.
    #[schema(value_type = String, example = "2")]
    pub quantity: Decimal,
    pub location_id: Uuid,
    /// Needed for lot-tracked products.
    pub lot_id: Option<Uuid>,
    /// Needed for serial-tracked products (before shipping).
    pub serial_unit_id: Option<Uuid>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct UpdateDeliveryInput {
    #[serde(default, deserialize_with = "tradocraft_core::serde_util::opt_date")]
    pub planned_date: Option<NaiveDate>,
    #[serde(default)]
    pub carrier: String,
    #[serde(default)]
    pub tracking_number: String,
    #[serde(default)]
    pub notes: String,
    /// Replaces the ship-to address; omitted keeps it.
    pub ship_to: Option<DeliveryShipToInput>,
    /// Replaces all lines; omitted keeps them.
    pub lines: Option<Vec<DeliveryLineInput>>,
    /// Needed to plan on a closed day when the policy is `override`.
    pub closure_override_reason: Option<String>,
    /// The `updated_at` of the note as it was loaded; refused (409) when the note changed since.
    pub expected_updated_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct ShipDeliveryInput {
    /// Sets the carrier and tracking reference as part of shipping.
    pub carrier: Option<String>,
    pub tracking_number: Option<String>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct CancelDeliveryInput {
    pub reason: String,
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct ListParams {
    /// planned | shipped | cancelled
    pub status: Option<String>,
    /// Searches the number, the order number, the customer name and the tracking number.
    pub q: Option<String>,
    pub customer_id: Option<Uuid>,
    /// Planned on or after this day.
    #[serde(default, deserialize_with = "tradocraft_core::serde_util::opt_date")]
    pub planned_from: Option<NaiveDate>,
    /// Planned on or before this day.
    #[serde(default, deserialize_with = "tradocraft_core::serde_util::opt_date")]
    pub planned_to: Option<NaiveDate>,
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}

/// A planned note of an order that was cancelled meanwhile reads as cancelled: the goods will not
/// be delivered (the order's reservations were released). The stored status stays `planned`.
const NOTE_STATUS: &str =
    "CASE WHEN n.status = 'planned' AND o.status = 'cancelled' THEN 'cancelled' ELSE n.status END";

const SELECT_NOTE: &str = "SELECT n.id, n.number, n.order_id, o.number AS order_number, n.order_revision,
        n.customer_id, c.name AS customer_name,
        CASE WHEN n.status = 'planned' AND o.status = 'cancelled' THEN 'cancelled' ELSE n.status END AS status,
        n.planned_date, n.ship_to_name, n.ship_to_street,
        n.ship_to_postal_code, n.ship_to_city, n.ship_to_country_code::text AS ship_to_country_code,
        n.carrier, n.tracking_number, n.notes, n.planned_on_closure, n.closure_override_reason,
        n.shipped_at, n.created_at, n.updated_at
     FROM delivery.delivery_notes n
     JOIN sales.orders o ON o.id = n.order_id
     JOIN crm.customers c ON c.id = n.customer_id";

const SELECT_SUMMARY: &str = "SELECT n.id, n.number, n.order_id, o.number AS order_number, n.customer_id,
        c.name AS customer_name,
        CASE WHEN n.status = 'planned' AND o.status = 'cancelled' THEN 'cancelled' ELSE n.status END AS status,
        n.planned_date, n.carrier, n.tracking_number, n.planned_on_closure,
        (SELECT count(*) FROM delivery.delivery_note_lines l WHERE l.delivery_note_id = n.id) AS line_count,
        n.shipped_at, n.created_at
     FROM delivery.delivery_notes n
     JOIN sales.orders o ON o.id = n.order_id
     JOIN crm.customers c ON c.id = n.customer_id";

const SELECT_LINES: &str =
    "SELECT l.id, l.position, l.order_line_id, ol.position AS order_position,
        l.product_id, COALESCE(l.product_code, p.code) AS product_code,
        COALESCE(l.product_name, p.name) AS product_name, p.tracking, l.quantity,
        COALESCE(l.unit, p.unit) AS unit, l.location_id,
        COALESCE(w.code || '/' || loc.code, loc.code) AS location, l.lot_id, lot.lot_number,
        l.serial_unit_id, su.serial_number, l.stock_move_id
     FROM delivery.delivery_note_lines l
     JOIN sales.order_lines ol ON ol.id = l.order_line_id
     JOIN products.products p ON p.id = l.product_id
     JOIN inventory.locations loc ON loc.id = l.location_id
     LEFT JOIN inventory.warehouses w ON w.id = loc.warehouse_id
     LEFT JOIN inventory.lots lot ON lot.id = l.lot_id
     LEFT JOIN engineering.serial_units su ON su.id = l.serial_unit_id
     WHERE l.delivery_note_id = $1
     ORDER BY l.position";

/// The closure that covers the date of a planned note, and the first open day after it.
async fn warning_for(
    conn: &mut PgConnection,
    customer_id: Uuid,
    date: Option<NaiveDate>,
) -> AppResult<Option<ClosureWarning>> {
    let Some(date) = date else { return Ok(None) };
    let Some(closure) = closure_on(&mut *conn, customer_id, date).await? else {
        return Ok(None);
    };
    let next_open_day = next_open_day(conn, customer_id, date).await?;
    Ok(Some(ClosureWarning {
        closure,
        next_open_day,
    }))
}

/// Loads a note with its lines. A planned note gets a live closure warning.
pub(crate) async fn load_note(
    conn: &mut PgConnection,
    company_id: Uuid,
    id: Uuid,
) -> AppResult<DeliveryNote> {
    let row: NoteRow = sqlx::query_as(sqlx::AssertSqlSafe(format!(
        "{SELECT_NOTE} WHERE n.id = $1 AND n.company_id = $2"
    )))
    .bind(id)
    .bind(company_id)
    .fetch_optional(&mut *conn)
    .await?
    .ok_or(AppError::NotFound("delivery note"))?;
    let lines: Vec<DeliveryNoteLine> = sqlx::query_as(SELECT_LINES)
        .bind(id)
        .fetch_all(&mut *conn)
        .await?;
    let closure_warning = if row.status == "planned" {
        warning_for(conn, row.customer_id, row.planned_date).await?
    } else {
        None
    };
    Ok(DeliveryNote {
        id: row.id,
        number: row.number,
        order_id: row.order_id,
        order_number: row.order_number,
        order_revision: row.order_revision,
        customer_id: row.customer_id,
        customer_name: row.customer_name,
        status: row.status,
        planned_date: row.planned_date,
        ship_to: DeliveryShipTo {
            name: row.ship_to_name,
            street: row.ship_to_street,
            postal_code: row.ship_to_postal_code,
            city: row.ship_to_city,
            country_code: row.ship_to_country_code,
        },
        carrier: row.carrier,
        tracking_number: row.tracking_number,
        notes: row.notes,
        planned_on_closure: row.planned_on_closure,
        closure_override_reason: row.closure_override_reason,
        closure_warning,
        shipped_at: row.shipped_at,
        created_at: row.created_at,
        updated_at: row.updated_at,
        lines,
    })
}

/// What the closure policy decides for a planned date: the override reason to keep, and whether
/// the customer is closed that day.
struct Gate {
    closed: bool,
    override_reason: Option<String>,
}

/// Applies the company's closure policy to a date a delivery is planned on.
/// * `warn`: always allowed; `closed` tells the note to remember the warning.
/// * `override`: allowed with a reason by a user who may override.
/// * `block`: refused.
async fn closure_gate(
    conn: &mut PgConnection,
    user: &CurrentUser,
    customer_id: Uuid,
    date: Option<NaiveDate>,
    override_reason: Option<&str>,
) -> AppResult<Gate> {
    let open = Gate {
        closed: false,
        override_reason: None,
    };
    let Some(warning) = warning_for(conn, customer_id, date).await? else {
        return Ok(open);
    };
    let what = format!(
        "the customer is closed on {} ({} to {}); the next open day is {}",
        date.map(|d| d.to_string()).unwrap_or_default(),
        warning.closure.starts_on,
        warning.closure.ends_on,
        warning.next_open_day
    );
    match load_settings(conn, user.company_id)
        .await?
        .closure_policy
        .as_str()
    {
        "block" => Err(AppError::ConflictCode("customer_closed", what)),
        "override" => {
            let reason = override_reason.map(str::trim).filter(|r| !r.is_empty());
            match reason {
                None => Err(AppError::ConflictCode(
                    "closure_override_required",
                    format!("{what}; give a reason to plan the delivery anyway"),
                )),
                Some(_) if !user.can(Permission::DeliveryOverrideClosure) => {
                    Err(AppError::Forbidden(format!(
                        "{what}; planning on a closed day needs {}",
                        Permission::DeliveryOverrideClosure.as_str()
                    )))
                }
                Some(r) => Ok(Gate {
                    closed: true,
                    override_reason: Some(r.to_string()),
                }),
            }
        }
        _ => Ok(Gate {
            closed: true,
            override_reason: None,
        }),
    }
}

/// What is already delivered (shipped notes, and shipments posted outside delivery notes) and
/// planned (other planned notes) for an order line, in the stock unit.
async fn booked(
    conn: &mut PgConnection,
    company_id: Uuid,
    order_line_id: Uuid,
    except_note: Option<Uuid>,
) -> AppResult<(Decimal, Decimal)> {
    let direct = shipped_outside_deliveries(conn, company_id, order_line_id).await?;
    let (shipped, planned): (Decimal, Decimal) = sqlx::query_as(
        "SELECT COALESCE(sum(l.quantity) FILTER (WHERE n.status = 'shipped'), 0),
                COALESCE(sum(l.quantity) FILTER (WHERE n.status = 'planned' AND n.id IS DISTINCT FROM $2), 0)
         FROM delivery.delivery_note_lines l
         JOIN delivery.delivery_notes n ON n.id = l.delivery_note_id
         WHERE l.order_line_id = $1",
    )
    .bind(order_line_id)
    .bind(except_note)
    .fetch_one(&mut *conn)
    .await?;
    Ok((shipped + direct, planned))
}

/// What a planned note has reserved at a location and lot for an order line.
async fn planned_at(
    conn: &mut PgConnection,
    order_line_id: Uuid,
    location_id: Uuid,
    lot_id: Option<Uuid>,
) -> AppResult<Decimal> {
    Ok(sqlx::query_scalar(
        "SELECT COALESCE(sum(l.quantity), 0)
         FROM delivery.delivery_note_lines l
         JOIN delivery.delivery_notes n ON n.id = l.delivery_note_id
         WHERE l.order_line_id = $1 AND n.status = 'planned' AND l.location_id = $2
           AND l.lot_id IS NOT DISTINCT FROM $3",
    )
    .bind(order_line_id)
    .bind(location_id)
    .bind(lot_id)
    .fetch_one(conn)
    .await?)
}

/// A line to insert: a pick of one order line.
struct Pick {
    order_line_id: Uuid,
    product_id: Uuid,
    quantity: Decimal,
    location_id: Uuid,
    lot_id: Option<Uuid>,
    serial_unit_id: Option<Uuid>,
}

/// The lines a new note starts with: the stock reserved for the order that is not yet delivered
/// or on another planned note. Serial-tracked products get one line per unit; the serial number
/// is chosen before shipping. Returns the picks and the total quantity still open on the order,
/// reserved or not.
async fn propose(
    conn: &mut PgConnection,
    company_id: Uuid,
    order_id: Uuid,
    revision: i32,
) -> AppResult<(Vec<Pick>, Decimal)> {
    let mut picks = Vec::new();
    let mut open_total = Decimal::ZERO;
    for ol in tradocraft_sales::orders::delivery_lines(conn, order_id, revision).await? {
        let Some(product_id) = ol.product_id else {
            continue;
        };
        let product = tradocraft_products::get_product(&mut *conn, product_id).await?;
        if product.product_type == "service" {
            continue;
        }
        let lr = line_reservation(conn, company_id, ol.id, false).await?;
        let (shipped, planned) = booked(conn, company_id, ol.id, None).await?;
        let mut open = lr.ordered - shipped - planned;
        if open > Decimal::ZERO {
            open_total += open;
        }
        for a in &lr.allocations {
            if open <= Decimal::ZERO {
                break;
            }
            if let Some(lot) = a.lot_id {
                if lot_expired(conn, company_id, lot).await? {
                    continue;
                }
            }
            let free = a.quantity - planned_at(conn, ol.id, a.location_id, a.lot_id).await?;
            let quantity = free.min(open);
            if quantity <= Decimal::ZERO {
                continue;
            }
            open -= quantity;
            if product.tracking == "serial" {
                for _ in 0..quantity.trunc().to_string().parse::<u32>().unwrap_or(0) {
                    picks.push(Pick {
                        order_line_id: ol.id,
                        product_id,
                        quantity: Decimal::ONE,
                        location_id: a.location_id,
                        lot_id: a.lot_id,
                        serial_unit_id: None,
                    });
                }
            } else {
                picks.push(Pick {
                    order_line_id: ol.id,
                    product_id,
                    quantity,
                    location_id: a.location_id,
                    lot_id: a.lot_id,
                    serial_unit_id: None,
                });
            }
        }
    }
    Ok((picks, open_total))
}

/// Stores the picks as the lines of a note, numbered from 1.
async fn insert_picks(conn: &mut PgConnection, note_id: Uuid, picks: &[Pick]) -> AppResult<()> {
    for (i, p) in picks.iter().enumerate() {
        sqlx::query(
            "INSERT INTO delivery.delivery_note_lines
                 (id, delivery_note_id, position, order_line_id, product_id, quantity, location_id, lot_id, serial_unit_id)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)",
        )
        .bind(new_id())
        .bind(note_id)
        .bind(i as i32 + 1)
        .bind(p.order_line_id)
        .bind(p.product_id)
        .bind(p.quantity)
        .bind(p.location_id)
        .bind(p.lot_id)
        .bind(p.serial_unit_id)
        .execute(&mut *conn)
        .await?;
    }
    Ok(())
}

/// Checks lines a user entered and turns them into picks: they belong to the delivered revision,
/// are stocked products, stay within what is ordered, and point at real stock locations.
async fn check_lines(
    conn: &mut PgConnection,
    company_id: Uuid,
    order_id: Uuid,
    revision: i32,
    note_id: Uuid,
    inputs: &[DeliveryLineInput],
) -> AppResult<Vec<Pick>> {
    let order_lines = tradocraft_sales::orders::delivery_lines(conn, order_id, revision).await?;
    let mut picks: Vec<Pick> = Vec::new();
    for (i, l) in inputs.iter().enumerate() {
        let n = i + 1;
        let ol = order_lines
            .iter()
            .find(|ol| ol.id == l.order_line_id)
            .ok_or_else(|| {
                AppError::Validation(format!(
                    "line {n}: not a line of the delivered revision of the order"
                ))
            })?;
        let product_id = ol.product_id.ok_or_else(|| {
            AppError::Validation(format!("line {n}: the order line has no product"))
        })?;
        let product = tradocraft_products::get_product(&mut *conn, product_id).await?;
        if product.product_type == "service" {
            return Err(AppError::Validation(format!(
                "line {n}: {} is a service and is not delivered",
                product.code
            )));
        }
        if l.quantity <= Decimal::ZERO || l.quantity.round_dp(4) != l.quantity {
            return Err(AppError::Validation(format!(
                "line {n}: quantity must be more than 0, with at most 4 decimals"
            )));
        }
        if product.tracking == "serial" && l.quantity != Decimal::ONE {
            return Err(AppError::Validation(format!(
                "line {n}: a serial-tracked product is delivered one unit per line"
            )));
        }
        let internal: bool = sqlx::query_scalar(
            "SELECT EXISTS (SELECT 1 FROM inventory.locations
                            WHERE id = $1 AND company_id = $2 AND kind = 'internal')",
        )
        .bind(l.location_id)
        .bind(company_id)
        .fetch_one(&mut *conn)
        .await?;
        if !internal {
            return Err(AppError::Validation(format!(
                "line {n}: the location is not a stock location"
            )));
        }
        if let Some(lot) = l.lot_id {
            let ok: bool = sqlx::query_scalar(
                "SELECT EXISTS (SELECT 1 FROM inventory.lots
                                WHERE id = $1 AND product_id = $2 AND company_id = $3)",
            )
            .bind(lot)
            .bind(product_id)
            .bind(company_id)
            .fetch_one(&mut *conn)
            .await?;
            if !ok {
                return Err(AppError::Validation(format!(
                    "line {n}: the lot is not a lot of {}",
                    product.code
                )));
            }
        }
        if let Some(unit) = l.serial_unit_id {
            let ok: bool = sqlx::query_scalar(
                "SELECT EXISTS (SELECT 1 FROM engineering.serial_units WHERE id = $1 AND product_id = $2)",
            )
            .bind(unit)
            .bind(product_id)
            .fetch_one(&mut *conn)
            .await?;
            if !ok {
                return Err(AppError::Validation(format!(
                    "line {n}: the serial number is not a unit of {}",
                    product.code
                )));
            }
            if picks.iter().any(|p| p.serial_unit_id == Some(unit)) {
                return Err(AppError::Validation(format!(
                    "line {n}: the serial number is on this delivery twice"
                )));
            }
        }
        picks.push(Pick {
            order_line_id: ol.id,
            product_id,
            quantity: l.quantity,
            location_id: l.location_id,
            lot_id: l.lot_id,
            serial_unit_id: l.serial_unit_id,
        });
    }
    // Never more than what is ordered, counting what is delivered and planned elsewhere.
    let mut seen: Vec<Uuid> = Vec::new();
    for p in &picks {
        if seen.contains(&p.order_line_id) {
            continue;
        }
        seen.push(p.order_line_id);
        let here: Decimal = picks
            .iter()
            .filter(|q| q.order_line_id == p.order_line_id)
            .map(|q| q.quantity)
            .sum();
        let lr = line_reservation(conn, company_id, p.order_line_id, false).await?;
        let (shipped, planned) = booked(conn, company_id, p.order_line_id, Some(note_id)).await?;
        if here + shipped + planned > lr.ordered {
            return Err(AppError::Conflict(format!(
                "{} {} of {} is ordered; {} is already delivered or planned, {} more is too much",
                lr.ordered.normalize(),
                "in the stock unit",
                lr.product_code,
                (shipped + planned).normalize(),
                here.normalize()
            )));
        }
    }
    Ok(picks)
}

/// Fails unless the order can still be delivered.
fn check_deliverable(number: &str, status: &str) -> AppResult<()> {
    if DELIVERABLE.contains(&status) {
        Ok(())
    } else {
        Err(AppError::Conflict(format!(
            "order {number} is {status}; only a confirmed order can be delivered"
        )))
    }
}

/// Plans a delivery for an order: a note with lines proposed from the order's reservations.
#[utoipa::path(post, path = "/orders/{id}/deliveries", tag = "delivery", params(("id" = Uuid, Path)),
    request_body = CreateDeliveryInput,
    responses((status = 201, body = DeliveryNote), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn create_note(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(order_id): Path<Uuid>,
    Json(input): Json<CreateDeliveryInput>,
) -> AppResult<(StatusCode, Json<DeliveryNote>)> {
    user.require(Permission::DeliveryWrite)?;
    let mut tx = state.db.begin().await?;
    let head =
        tradocraft_sales::orders::lock_for_delivery(&mut tx, user.company_id, order_id).await?;
    check_deliverable(&head.number, &head.status)?;
    let (picks, open_total) = propose(&mut tx, user.company_id, order_id, head.revision).await?;
    if open_total <= Decimal::ZERO {
        return Err(AppError::Conflict(format!(
            "nothing is left to deliver on order {}",
            head.number
        )));
    }
    let gate = closure_gate(
        &mut tx,
        &user,
        head.customer_id,
        input.planned_date,
        input.closure_override_reason.as_deref(),
    )
    .await?;
    let customer =
        tradocraft_crm::get_customer(&mut *tx, user.company_id, head.customer_id).await?;
    let year = Utc::now().year();
    let seq = numbering::next_number(&mut tx, user.company_id, "DN", year).await?;
    let number = format!("DN{year}-{seq:05}");
    let id = new_id();
    sqlx::query(
        "INSERT INTO delivery.delivery_notes
             (id, company_id, number, order_id, order_revision, customer_id, planned_date, ship_to_name,
              ship_to_street, ship_to_postal_code, ship_to_city, ship_to_country_code, carrier, notes,
              planned_on_closure, closure_override_reason, created_by)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17)",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(&number)
    .bind(order_id)
    .bind(head.revision)
    .bind(head.customer_id)
    .bind(input.planned_date)
    .bind(&customer.name)
    .bind(&customer.street)
    .bind(&customer.postal_code)
    .bind(&customer.city)
    .bind(&customer.country_code)
    .bind(input.carrier.trim())
    .bind(input.notes.trim())
    .bind(gate.closed)
    .bind(&gate.override_reason)
    .bind(user.user_id)
    .execute(&mut *tx)
    .await?;
    insert_picks(&mut tx, id, &picks).await?;
    audit::record(
        &mut tx,
        &user,
        "delivery_note",
        id,
        "created",
        serde_json::json!({
            "number": number, "order": head.number, "planned_date": input.planned_date,
            "lines": picks.len(), "on_closure": gate.closed, "override_reason": gate.override_reason,
        }),
    )
    .await?;
    let note = load_note(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(note)))
}

/// Changes a planned delivery note: date, carrier, address, notes and lines.
#[utoipa::path(put, path = "/deliveries/{id}", tag = "delivery", params(("id" = Uuid, Path)),
    request_body = UpdateDeliveryInput,
    responses((status = 200, body = DeliveryNote), (status = 404, body = ErrorBody), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn update_note(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<UpdateDeliveryInput>,
) -> AppResult<Json<DeliveryNote>> {
    user.require(Permission::DeliveryWrite)?;
    let mut tx = state.db.begin().await?;
    let note = lock_note(&mut tx, user.company_id, id).await?;
    if note.status != "planned" {
        return Err(AppError::Conflict(format!(
            "delivery note {} is {} and can no longer be changed",
            note.number, note.status
        )));
    }
    if input
        .expected_updated_at
        .is_some_and(|expected| expected != note.updated_at)
    {
        return Err(AppError::ConflictCode(
            "delivery_note_changed",
            format!(
                "delivery note {} was changed by someone else; reload it before saving",
                note.number
            ),
        ));
    }
    let head = tradocraft_sales::orders::lock_for_delivery(&mut tx, user.company_id, note.order_id)
        .await?;
    check_deliverable(&head.number, &head.status)?;
    // The closure policy applies when the date changes, not on every edit of an old date.
    let (closed, reason) = if input.planned_date != note.planned_date {
        let gate = closure_gate(
            &mut tx,
            &user,
            note.customer_id,
            input.planned_date,
            input.closure_override_reason.as_deref(),
        )
        .await?;
        (gate.closed, gate.override_reason)
    } else {
        (
            note.planned_on_closure,
            note.closure_override_reason.clone(),
        )
    };
    if let Some(to) = &input.ship_to {
        if to.name.trim().is_empty() || to.country_code.trim().len() != 2 {
            return Err(AppError::Validation(
                "the address needs a name and a 2-letter country code".into(),
            ));
        }
        sqlx::query(
            "UPDATE delivery.delivery_notes SET ship_to_name = $2, ship_to_street = $3,
                 ship_to_postal_code = $4, ship_to_city = $5, ship_to_country_code = $6
             WHERE id = $1",
        )
        .bind(id)
        .bind(to.name.trim())
        .bind(to.street.trim())
        .bind(to.postal_code.trim())
        .bind(to.city.trim())
        .bind(to.country_code.trim().to_uppercase())
        .execute(&mut *tx)
        .await?;
    }
    if let Some(lines) = &input.lines {
        let picks = check_lines(
            &mut tx,
            user.company_id,
            note.order_id,
            note.order_revision,
            id,
            lines,
        )
        .await?;
        sqlx::query("DELETE FROM delivery.delivery_note_lines WHERE delivery_note_id = $1")
            .bind(id)
            .execute(&mut *tx)
            .await?;
        insert_picks(&mut tx, id, &picks).await?;
    }
    sqlx::query(
        "UPDATE delivery.delivery_notes SET planned_date = $2, carrier = $3, tracking_number = $4, notes = $5,
             planned_on_closure = $6, closure_override_reason = $7, updated_at = now()
         WHERE id = $1",
    )
    .bind(id)
    .bind(input.planned_date)
    .bind(input.carrier.trim())
    .bind(input.tracking_number.trim())
    .bind(input.notes.trim())
    .bind(closed)
    .bind(&reason)
    .execute(&mut *tx)
    .await?;
    audit::record(
        &mut tx,
        &user,
        "delivery_note",
        id,
        "updated",
        serde_json::json!({
            "number": note.number, "order": head.number, "planned_date": input.planned_date,
            "lines_replaced": input.lines.is_some(), "on_closure": closed, "override_reason": reason,
        }),
    )
    .await?;
    let out = load_note(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok(Json(out))
}

/// Locks a note row.
async fn lock_note(conn: &mut PgConnection, company_id: Uuid, id: Uuid) -> AppResult<NoteRow> {
    sqlx::query_as(sqlx::AssertSqlSafe(format!(
        "{SELECT_NOTE} WHERE n.id = $1 AND n.company_id = $2 FOR UPDATE OF n"
    )))
    .bind(id)
    .bind(company_id)
    .fetch_optional(conn)
    .await?
    .ok_or(AppError::NotFound("delivery note"))
}

#[derive(FromRow)]
struct ShipLine {
    id: Uuid,
    position: i32,
    order_line_id: Uuid,
    product_id: Uuid,
    quantity: Decimal,
    location_id: Uuid,
    lot_id: Option<Uuid>,
    serial_unit_id: Option<Uuid>,
}

/// Ships a planned delivery note: the goods leave the stock (consuming the reservations of the
/// order) and the order becomes `partially_shipped`, or `shipped` once everything is delivered.
#[utoipa::path(post, path = "/deliveries/{id}/ship", tag = "delivery", params(("id" = Uuid, Path)),
    request_body = ShipDeliveryInput,
    responses((status = 200, body = DeliveryNote), (status = 404, body = ErrorBody), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn ship_note(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<ShipDeliveryInput>,
) -> AppResult<Json<DeliveryNote>> {
    user.require(Permission::DeliveryShip)?;
    let mut tx = state.db.begin().await?;
    let note = lock_note(&mut tx, user.company_id, id).await?;
    if note.status != "planned" {
        return Err(AppError::Conflict(format!(
            "delivery note {} is {}; only a planned note can be shipped",
            note.number, note.status
        )));
    }
    let head = tradocraft_sales::orders::lock_for_delivery(&mut tx, user.company_id, note.order_id)
        .await?;
    check_deliverable(&head.number, &head.status)?;
    let lines: Vec<ShipLine> = sqlx::query_as(
        "SELECT id, position, order_line_id, product_id, quantity, location_id, lot_id, serial_unit_id
         FROM delivery.delivery_note_lines WHERE delivery_note_id = $1 ORDER BY position",
    )
    .bind(id)
    .fetch_all(&mut *tx)
    .await?;
    // Post in a fixed order (product, place, lot), whatever the order of the lines, so two
    // shipments taking the same stock lock its balances in the same order and cannot deadlock.
    let mut lines = lines;
    lines.sort_by_key(|l| (l.product_id, l.location_id, l.lot_id, l.position));
    if lines.is_empty() {
        return Err(AppError::Validation(
            "the delivery note has no lines to ship".into(),
        ));
    }
    let customer_location = virtual_location(&mut tx, user.company_id, "customer").await?;
    for l in lines.iter() {
        let n = l.position;
        let product = tradocraft_products::get_product(&mut *tx, l.product_id).await?;
        if let Some(lot) = l.lot_id {
            if lot_expired(&mut tx, user.company_id, lot).await? {
                return Err(AppError::Validation(format!(
                    "line {n}: the lot of {} is past its expiry date",
                    product.code
                )));
            }
        }
        if product.tracking == "serial" && l.serial_unit_id.is_none() {
            return Err(AppError::Validation(format!(
                "line {n}: choose the serial number of {} before shipping",
                product.code
            )));
        }
        if product.tracking == "lot" && l.lot_id.is_none() {
            return Err(AppError::Validation(format!(
                "line {n}: choose the lot of {} before shipping",
                product.code
            )));
        }
        // What the order's reservation holds at this place and lot is shipped from it; the rest of
        // the pick, if any, is free stock.
        let reserved: Decimal =
            allocations_for(&mut tx, user.company_id, SALES_ORDER_LINE, l.order_line_id)
                .await?
                .iter()
                .filter(|a| a.location_id == l.location_id && a.lot_id == l.lot_id)
                .map(|a| a.quantity)
                .sum();
        let from_reservation = reserved.min(l.quantity);
        let parts = if from_reservation > Decimal::ZERO && from_reservation < l.quantity {
            vec![
                (l.id, from_reservation, true),
                (new_id(), l.quantity - from_reservation, false),
            ]
        } else {
            vec![(l.id, l.quantity, from_reservation > Decimal::ZERO)]
        };
        for (i, (move_id, quantity, consume)) in parts.into_iter().enumerate() {
            let mut m = NewMove::new(
                move_id,
                &user,
                l.product_id,
                quantity,
                l.location_id,
                customer_location,
                "issue",
                "shipment",
            );
            m.lot_id = l.lot_id;
            m.serial_unit_id = l.serial_unit_id;
            m.respect_reservations = true;
            m.reference = Some(("delivery_note".to_string(), id));
            if consume {
                m.consume_reservation = Some((SALES_ORDER_LINE.to_string(), l.order_line_id));
            }
            if product.tracking == "serial" {
                m.serial_effect = SerialEffect::Deliver(Some(note.customer_id));
            }
            let moved = post_move(&mut tx, &m).await?.into_move();
            if i == 0 {
                sqlx::query(
                    "UPDATE delivery.delivery_note_lines SET stock_move_id = $2 WHERE id = $1",
                )
                .bind(l.id)
                .bind(moved.id)
                .execute(&mut *tx)
                .await?;
            }
        }
    }
    // A shipped note keeps the product as it was shipped.
    sqlx::query(
        "UPDATE delivery.delivery_note_lines l
         SET product_code = p.code, product_name = p.name, unit = p.unit
         FROM products.products p
         WHERE l.delivery_note_id = $1 AND p.id = l.product_id",
    )
    .bind(id)
    .execute(&mut *tx)
    .await?;
    sqlx::query(
        "UPDATE delivery.delivery_notes
         SET status = 'shipped', shipped_at = now(), shipped_by = $2, updated_at = now(),
             carrier = COALESCE($3, carrier), tracking_number = COALESCE($4, tracking_number)
         WHERE id = $1",
    )
    .bind(id)
    .bind(user.user_id)
    .bind(input.carrier.as_deref().map(str::trim))
    .bind(input.tracking_number.as_deref().map(str::trim))
    .execute(&mut *tx)
    .await?;
    // Complete when every stocked line of the order is delivered in full.
    let mut complete = true;
    for ol in
        tradocraft_sales::orders::delivery_lines(&mut tx, note.order_id, head.revision).await?
    {
        let Some(product_id) = ol.product_id else {
            continue;
        };
        let product = tradocraft_products::get_product(&mut *tx, product_id).await?;
        if product.product_type == "service" {
            continue;
        }
        let lr = line_reservation(&mut tx, user.company_id, ol.id, false).await?;
        let (shipped, _) = booked(&mut tx, user.company_id, ol.id, None).await?;
        if shipped < lr.ordered {
            complete = false;
        }
    }
    tradocraft_sales::orders::mark_shipped(&mut tx, &user, note.order_id, complete, id).await?;
    if complete {
        // Stock reserved beyond what was shipped goes back to the free stock.
        tradocraft_inventory::release_for_order(
            &mut tx,
            user.company_id,
            note.order_id,
            Some(user.user_id),
        )
        .await?;
    }
    audit::record(
        &mut tx,
        &user,
        "delivery_note",
        id,
        "shipped",
        serde_json::json!({
            "number": note.number, "order": head.number, "lines": lines.len(), "order_complete": complete,
            "tracking_number": input.tracking_number,
        }),
    )
    .await?;
    let out = load_note(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok(Json(out))
}

/// Cancels a planned delivery note. A shipped note cannot be cancelled.
#[utoipa::path(post, path = "/deliveries/{id}/cancel", tag = "delivery", params(("id" = Uuid, Path)),
    request_body = CancelDeliveryInput,
    responses((status = 200, body = DeliveryNote), (status = 404, body = ErrorBody), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn cancel_note(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<CancelDeliveryInput>,
) -> AppResult<Json<DeliveryNote>> {
    user.require(Permission::DeliveryWrite)?;
    if input.reason.trim().is_empty() {
        return Err(AppError::Validation("a reason is required".into()));
    }
    let mut tx = state.db.begin().await?;
    let note = lock_note(&mut tx, user.company_id, id).await?;
    if note.status != "planned" {
        return Err(AppError::Conflict(format!(
            "delivery note {} is {}; only a planned note can be cancelled",
            note.number, note.status
        )));
    }
    sqlx::query(
        "UPDATE delivery.delivery_notes SET status = 'cancelled', cancelled_at = now(), updated_at = now() WHERE id = $1",
    )
    .bind(id)
    .execute(&mut *tx)
    .await?;
    audit::record(
        &mut tx,
        &user,
        "delivery_note",
        id,
        "cancelled",
        serde_json::json!({ "number": note.number, "reason": input.reason.trim() }),
    )
    .await?;
    let out = load_note(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok(Json(out))
}

/// One delivery note with its lines.
#[utoipa::path(get, path = "/deliveries/{id}", tag = "delivery", params(("id" = Uuid, Path)),
    responses((status = 200, body = DeliveryNote), (status = 404, body = ErrorBody)))]
async fn get_note(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<DeliveryNote>> {
    user.require(Permission::DeliveryRead)?;
    let mut conn = state.db.acquire().await?;
    Ok(Json(load_note(&mut conn, user.company_id, id).await?))
}

/// Delivery notes, newest planned date first.
#[utoipa::path(get, path = "/deliveries", tag = "delivery", params(ListParams),
    responses((status = 200, body = DeliveryPage)))]
async fn list_notes(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(p): Query<ListParams>,
) -> AppResult<Json<DeliveryPage>> {
    user.require(Permission::DeliveryRead)?;
    if let Some(s) = &p.status {
        if !matches!(s.as_str(), "planned" | "shipped" | "cancelled") {
            return Err(AppError::Validation(
                "status must be planned, shipped or cancelled".into(),
            ));
        }
    }
    let filter = format!(
        "n.company_id = $1
         AND ($2::text IS NULL OR ({NOTE_STATUS}) = $2)
         AND ($3::uuid IS NULL OR n.customer_id = $3)
         AND ($4::date IS NULL OR n.planned_date >= $4)
         AND ($5::date IS NULL OR n.planned_date <= $5)
         AND ($6::text IS NULL OR n.number ILIKE $6 OR o.number ILIKE $6 OR c.name ILIKE $6
              OR n.tracking_number ILIKE $6)"
    );
    let q =
        p.q.as_deref()
            .map(str::trim)
            .filter(|q| !q.is_empty())
            .map(|q| format!("%{q}%"));
    let limit = p.limit.unwrap_or(50).clamp(1, 200);
    let offset = p.offset.unwrap_or(0).max(0);
    let items: Vec<DeliverySummary> = sqlx::query_as(sqlx::AssertSqlSafe(format!(
        "{SELECT_SUMMARY} WHERE {filter}
         ORDER BY n.planned_date DESC NULLS FIRST, n.created_at DESC, n.id LIMIT $7 OFFSET $8"
    )))
    .bind(user.company_id)
    .bind(&p.status)
    .bind(p.customer_id)
    .bind(p.planned_from)
    .bind(p.planned_to)
    .bind(&q)
    .bind(limit)
    .bind(offset)
    .fetch_all(&state.db)
    .await?;
    let total: i64 = sqlx::query_scalar(sqlx::AssertSqlSafe(format!(
        "SELECT count(*) FROM delivery.delivery_notes n
         JOIN sales.orders o ON o.id = n.order_id
         JOIN crm.customers c ON c.id = n.customer_id
         WHERE {filter}"
    )))
    .bind(user.company_id)
    .bind(&p.status)
    .bind(p.customer_id)
    .bind(p.planned_from)
    .bind(p.planned_to)
    .bind(&q)
    .fetch_one(&state.db)
    .await?;
    Ok(Json(DeliveryPage { items, total }))
}

/// The delivery notes of one order.
#[utoipa::path(get, path = "/orders/{id}/deliveries", tag = "delivery", params(("id" = Uuid, Path)),
    responses((status = 200, body = Vec<DeliverySummary>)))]
async fn list_for_order(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(order_id): Path<Uuid>,
) -> AppResult<Json<Vec<DeliverySummary>>> {
    user.require(Permission::DeliveryRead)?;
    Ok(Json(
        sqlx::query_as(sqlx::AssertSqlSafe(format!(
            "{SELECT_SUMMARY} WHERE n.company_id = $1 AND n.order_id = $2 ORDER BY n.created_at, n.id"
        )))
        .bind(user.company_id)
        .bind(order_id)
        .fetch_all(&state.db)
        .await?,
    ))
}

#[derive(Debug, Serialize, ToSchema)]
pub struct SerialChoice {
    pub id: Uuid,
    pub serial_number: String,
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct SerialParams {
    /// Part of the serial number.
    pub q: Option<String>,
}

/// The serial units that are in stock at the location of a line of a planned note: what can be
/// chosen as its serial number.
#[utoipa::path(get, path = "/deliveries/{id}/lines/{line_id}/serial-units", tag = "delivery",
    params(("id" = Uuid, Path), ("line_id" = Uuid, Path), SerialParams),
    responses((status = 200, body = Vec<SerialChoice>), (status = 404, body = ErrorBody)))]
async fn serial_choices(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((id, line_id)): Path<(Uuid, Uuid)>,
    Query(p): Query<SerialParams>,
) -> AppResult<Json<Vec<SerialChoice>>> {
    user.require(Permission::DeliveryWrite)?;
    let mut conn = state.db.acquire().await?;
    let line: Option<(Uuid, Uuid)> = sqlx::query_as(
        "SELECT l.product_id, l.location_id
         FROM delivery.delivery_note_lines l
         JOIN delivery.delivery_notes n ON n.id = l.delivery_note_id
         WHERE l.id = $1 AND n.id = $2 AND n.company_id = $3",
    )
    .bind(line_id)
    .bind(id)
    .bind(user.company_id)
    .fetch_optional(&mut *conn)
    .await?;
    let (product_id, location_id) = line.ok_or(AppError::NotFound("delivery note line"))?;
    let q = p.q.as_deref().map(str::trim).filter(|q| !q.is_empty());
    Ok(Json(
        serial_units_at(&mut conn, user.company_id, product_id, location_id, q, 50)
            .await?
            .into_iter()
            .map(|u| SerialChoice {
                id: u.id,
                serial_number: u.serial_number,
            })
            .collect(),
    ))
}

/// The delivery note routes.
pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(list_notes))
        .routes(routes!(get_note, update_note))
        .routes(routes!(create_note, list_for_order))
        .routes(routes!(serial_choices))
        .routes(routes!(ship_note))
        .routes(routes!(cancel_note))
}
