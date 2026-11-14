//! Completing a production order: backflush consumption of the reserved components, scrap, the
//! output into stock (lot, or serial units with their as-built genealogy) and the order status that
//! follows (ADR 0036). One transaction: everything happens or nothing does.

use axum::extract::{Path, Query, State};
use axum::Json;
use chrono::NaiveDate;
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection};
use tradocraft_core::{audit, new_id, AppError, AppResult, AppState, CurrentUser, Permission};
use tradocraft_engineering::serials::{attach_component_in, register_unit};
use tradocraft_inventory::ledger::get_or_create_lot;
use tradocraft_inventory::reservations::{
    allocations_for, serial_location, serial_units_in_stock, PRODUCTION_COMPONENT,
};
use tradocraft_inventory::{post_move, virtual_location, NewMove};
use utoipa::{IntoParams, ToSchema};
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::operations::{check_actuals, close_operations, ProductionOperationActual};
use crate::orders::{
    load_order, lock_order, release_components, sync_order_status, ProductionOrder,
};

type ErrorBody = tradocraft_core::error::ErrorBody;

#[derive(Debug, Deserialize, ToSchema)]
pub struct ProductionOutputInput {
    /// What was built, in the stock unit. May be less than ordered; the order is then closed with
    /// the shortfall and another production order covers the rest.
    #[schema(value_type = String, example = "5")]
    pub quantity: Decimal,
    /// The stock location the output goes to.
    pub location_id: Uuid,
    /// Needed for lot-tracked products.
    pub lot_number: Option<String>,
    #[serde(default, deserialize_with = "tradocraft_core::serde_util::opt_date")]
    pub expiry_date: Option<NaiveDate>,
    /// Needed for serial-tracked products: one serial number per unit built.
    #[serde(default)]
    pub serial_numbers: Vec<String>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct ProductionComponentActual {
    pub component_id: Uuid,
    /// What was really consumed; defaults to what the BOM required.
    #[schema(value_type = Option<String>, example = "4")]
    pub consumed_quantity: Option<Decimal>,
    /// Lost on top of the consumption (not for serial-tracked components).
    #[serde(default)]
    #[schema(value_type = String, example = "0")]
    pub scrap_quantity: Decimal,
    /// Where stock beyond the reservation is taken from (needed when more was used than reserved).
    pub extra_location_id: Option<Uuid>,
    pub extra_lot_id: Option<Uuid>,
    /// The serial units that were built in (needed for serial-tracked components, one per unit).
    #[serde(default)]
    pub serial_unit_ids: Vec<Uuid>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct CompleteProductionInput {
    pub output: ProductionOutputInput,
    /// Actual consumption per component; components that are left out use the BOM quantity.
    #[serde(default)]
    pub components: Vec<ProductionComponentActual>,
    /// The minutes worked per operation. Operations named here are finished; any other
    /// operation that is still open is skipped. Never needed: an order without a routing has none,
    /// and open operations do not stop an order from being completed.
    #[serde(default)]
    pub operations: Vec<ProductionOperationActual>,
    #[serde(default)]
    pub note: String,
}

#[derive(FromRow)]
struct CompRow {
    id: Uuid,
    component_product_id: Uuid,
    required_quantity: Decimal,
}

/// Takes `quantity` of a component out of stock for a production order: first from what is
/// reserved for it, then from `extra` (a location, optionally a lot) for the rest.
#[allow(clippy::too_many_arguments)]
async fn take(
    conn: &mut PgConnection,
    user: &CurrentUser,
    order_id: Uuid,
    comp: &CompRow,
    quantity: Decimal,
    reason: &'static str,
    to_location: Uuid,
    actual: Option<&ProductionComponentActual>,
) -> AppResult<()> {
    let mut remaining = quantity;
    for a in allocations_for(conn, user.company_id, PRODUCTION_COMPONENT, comp.id).await? {
        if remaining <= Decimal::ZERO {
            break;
        }
        let part = a.quantity.min(remaining);
        let mut m = NewMove::new(
            new_id(),
            user,
            comp.component_product_id,
            part,
            a.location_id,
            to_location,
            "issue",
            reason,
        );
        m.lot_id = a.lot_id;
        m.respect_reservations = true;
        m.consume_reservation = Some((PRODUCTION_COMPONENT.to_string(), comp.id));
        m.reference = Some(("production_order".to_string(), order_id));
        post_move(conn, &m).await?;
        remaining -= part;
    }
    if remaining > Decimal::ZERO {
        let from = actual.and_then(|a| a.extra_location_id).ok_or_else(|| {
            AppError::Validation(format!(
                "{} more of a component than is reserved: name the location it is taken from",
                remaining.normalize()
            ))
        })?;
        let mut m = NewMove::new(
            new_id(),
            user,
            comp.component_product_id,
            remaining,
            from,
            to_location,
            "issue",
            reason,
        );
        m.lot_id = actual.and_then(|a| a.extra_lot_id);
        m.respect_reservations = true;
        m.reference = Some(("production_order".to_string(), order_id));
        post_move(conn, &m).await?;
    }
    Ok(())
}

/// Completes a production order: consumes the components (backflush, with the actual quantities
/// and scrap), puts the output into stock and moves the sales order on.
#[utoipa::path(post, path = "/production-orders/{id}/complete", tag = "production", params(("id" = Uuid, Path)),
    request_body = CompleteProductionInput,
    responses((status = 200, body = ProductionOrder), (status = 404, body = ErrorBody), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn complete_order(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<CompleteProductionInput>,
) -> AppResult<Json<ProductionOrder>> {
    user.require(Permission::ProductionRun)?;
    let out = &input.output;
    if out.quantity <= Decimal::ZERO || out.quantity.round_dp(4) != out.quantity {
        return Err(AppError::Validation(
            "the output quantity must be more than 0, with at most 4 decimals".into(),
        ));
    }
    let mut tx = state.db.begin().await?;
    let po = lock_order(&mut tx, user.company_id, id).await?;
    if !matches!(po.status.as_str(), "released" | "in_progress") {
        return Err(AppError::Conflict(format!(
            "production order {} is {}; only an open order can be completed",
            po.number, po.status
        )));
    }
    if let Some(order_id) = po.order_id {
        let head =
            tradocraft_sales::orders::lock_for_delivery(&mut tx, user.company_id, order_id).await?;
        if head.status == "cancelled" {
            return Err(AppError::Conflict(format!(
                "order {} was cancelled; cancel this production order instead",
                head.number
            )));
        }
    }
    let product = tradocraft_products::get_product(&mut *tx, po.product_id).await?;
    match product.tracking.as_str() {
        "serial" => {
            let units = Decimal::from(out.serial_numbers.len() as i64);
            if out.quantity.fract() != Decimal::ZERO || units != out.quantity {
                return Err(AppError::Validation(format!(
                    "{} is serial-tracked: give one serial number for each of the {} units built",
                    product.code,
                    out.quantity.normalize()
                )));
            }
        }
        "lot"
            if out
                .lot_number
                .as_deref()
                .map(str::trim)
                .unwrap_or("")
                .is_empty() =>
        {
            return Err(AppError::Validation(format!(
                "{} is lot-tracked: give the lot number of the output",
                product.code
            )));
        }
        _ => {}
    }
    for a in &input.components {
        let known: bool = sqlx::query_scalar(
            "SELECT EXISTS (SELECT 1 FROM production.order_components WHERE id = $1 AND production_order_id = $2)",
        )
        .bind(a.component_id)
        .bind(id)
        .fetch_one(&mut *tx)
        .await?;
        if !known {
            return Err(AppError::Validation(
                "a component does not belong to this production order".into(),
            ));
        }
        if a.consumed_quantity.is_some_and(|q| q < Decimal::ZERO)
            || a.scrap_quantity < Decimal::ZERO
        {
            return Err(AppError::Validation(
                "consumed and scrap quantities cannot be negative".into(),
            ));
        }
    }
    check_actuals(&mut tx, user.company_id, id, &input.operations).await?;
    let components: Vec<CompRow> = sqlx::query_as(
        "SELECT id, component_product_id, required_quantity FROM production.order_components
         WHERE production_order_id = $1 ORDER BY component_product_id, position",
    )
    .bind(id)
    .fetch_all(&mut *tx)
    .await?;
    let consumption = virtual_location(&mut tx, user.company_id, "production_consumption").await?;
    let scrap = virtual_location(&mut tx, user.company_id, "scrap").await?;
    // Serial components that were built in, to attach to the output units afterwards.
    let mut built_in: Vec<Vec<Uuid>> = Vec::new();
    for comp in &components {
        let actual = input.components.iter().find(|a| a.component_id == comp.id);
        let used = actual
            .and_then(|a| a.consumed_quantity)
            .unwrap_or(comp.required_quantity);
        let lost = actual.map_or(Decimal::ZERO, |a| a.scrap_quantity);
        let cp = tradocraft_products::get_product(&mut *tx, comp.component_product_id).await?;
        if cp.tracking == "serial" {
            let units = actual
                .map(|a| a.serial_unit_ids.clone())
                .unwrap_or_default();
            if lost != Decimal::ZERO {
                return Err(AppError::Validation(format!(
                    "{} is serial-tracked: scrap its units separately",
                    cp.code
                )));
            }
            if Decimal::from(units.len() as i64) != used {
                return Err(AppError::Validation(format!(
                    "{} is serial-tracked: choose the {} serial units that were built in",
                    cp.code,
                    used.normalize()
                )));
            }
            if product.tracking != "serial" && !units.is_empty() {
                return Err(AppError::Validation(format!(
                    "{} is built in as serial units: {} must be serial-tracked to record that",
                    cp.code, product.code
                )));
            }
            for unit in &units {
                let at = serial_location(&mut tx, user.company_id, *unit)
                    .await?
                    .ok_or_else(|| {
                        AppError::Validation(format!("a unit of {} is not in stock", cp.code))
                    })?;
                let reserved =
                    allocations_for(&mut tx, user.company_id, PRODUCTION_COMPONENT, comp.id)
                        .await?
                        .iter()
                        .any(|a| a.location_id == at && a.quantity >= Decimal::ONE);
                let mut m = NewMove::new(
                    new_id(),
                    &user,
                    comp.component_product_id,
                    Decimal::ONE,
                    at,
                    consumption,
                    "issue",
                    "consumption",
                );
                m.serial_unit_id = Some(*unit);
                m.respect_reservations = true;
                m.reference = Some(("production_order".to_string(), id));
                if reserved {
                    m.consume_reservation = Some((PRODUCTION_COMPONENT.to_string(), comp.id));
                }
                post_move(&mut tx, &m).await?;
            }
            built_in.push(units);
        } else {
            if used > Decimal::ZERO {
                take(
                    &mut tx,
                    &user,
                    id,
                    comp,
                    used,
                    "consumption",
                    consumption,
                    actual,
                )
                .await?;
            }
            if lost > Decimal::ZERO {
                take(&mut tx, &user, id, comp, lost, "scrap", scrap, actual).await?;
            }
        }
        sqlx::query(
            "UPDATE production.order_components SET consumed_quantity = $2, scrap_quantity = $3 WHERE id = $1",
        )
        .bind(comp.id)
        .bind(used)
        .bind(lost)
        .execute(&mut *tx)
        .await?;
    }
    // The output: a lot, or one unit per serial number with the components built into it.
    let source = virtual_location(&mut tx, user.company_id, "production_output").await?;
    let receipt = |move_id: Uuid, quantity: Decimal| {
        let mut m = NewMove::new(
            move_id,
            &user,
            po.product_id,
            quantity,
            source,
            out.location_id,
            "receipt",
            "production_output",
        );
        m.reference = Some(("production_order".to_string(), id));
        m
    };
    let mut output_units: Vec<Uuid> = Vec::new();
    match product.tracking.as_str() {
        "serial" => {
            for serial in &out.serial_numbers {
                let unit = register_unit(
                    &mut tx,
                    &user,
                    po.product_id,
                    serial.trim(),
                    Some(po.bom_id),
                    None,
                    "",
                )
                .await?;
                let mut m = receipt(new_id(), Decimal::ONE);
                m.serial_unit_id = Some(unit);
                let moved = post_move(&mut tx, &m).await?.into_move();
                record_output(&mut tx, id, Decimal::ONE, None, Some(unit), moved.id).await?;
                output_units.push(unit);
            }
        }
        "lot" => {
            let lot = get_or_create_lot(
                &mut tx,
                user.company_id,
                po.product_id,
                out.lot_number.as_deref().unwrap_or_default(),
                out.expiry_date,
            )
            .await?;
            let mut m = receipt(new_id(), out.quantity);
            m.lot_id = Some(lot);
            let moved = post_move(&mut tx, &m).await?.into_move();
            record_output(&mut tx, id, out.quantity, Some(lot), None, moved.id).await?;
        }
        _ => {
            let moved = post_move(&mut tx, &receipt(new_id(), out.quantity))
                .await?
                .into_move();
            record_output(&mut tx, id, out.quantity, None, None, moved.id).await?;
        }
    }
    // As built: the serial components go into the units that were made, evenly.
    for units in built_in.iter().filter(|u| !u.is_empty()) {
        if units.len() % output_units.len().max(1) != 0 {
            return Err(AppError::Validation(format!(
                "{} serial components cannot be divided over {} units built",
                units.len(),
                output_units.len()
            )));
        }
        let per = units.len() / output_units.len().max(1);
        for (parent, chunk) in output_units.iter().zip(units.chunks(per.max(1))) {
            for child in chunk {
                attach_component_in(&mut tx, &user, *parent, *child).await?;
            }
        }
    }
    release_components(&mut tx, &user, id).await?;
    let (operations_done, operations_skipped) =
        close_operations(&mut tx, &user, id, &input.operations).await?;
    sqlx::query(
        "UPDATE production.production_orders
         SET status = 'completed', completed_at = now(), completed_quantity = $2,
             started_at = COALESCE(started_at, now()), updated_at = now(),
             notes = CASE WHEN $3 = '' THEN notes ELSE concat_ws(E'\\n', NULLIF(notes, ''), $3) END
         WHERE id = $1",
    )
    .bind(id)
    .bind(out.quantity)
    .bind(input.note.trim())
    .execute(&mut *tx)
    .await?;
    audit::record(
        &mut tx,
        &user,
        "production_order",
        id,
        "completed",
        serde_json::json!({
            "number": po.number, "ordered": po.quantity, "built": out.quantity,
            "lot": out.lot_number, "serial_numbers": out.serial_numbers,
            "operations_finished": operations_done, "operations_skipped": operations_skipped,
        }),
    )
    .await?;
    if let Some(order_id) = po.order_id {
        sync_order_status(&mut tx, &user, order_id).await?;
    }
    let result = load_order(&mut tx, &user, id).await?;
    tx.commit().await?;
    Ok(Json(result))
}

/// Notes what a completion put into stock.
async fn record_output(
    conn: &mut PgConnection,
    production_order_id: Uuid,
    quantity: Decimal,
    lot_id: Option<Uuid>,
    serial_unit_id: Option<Uuid>,
    stock_move_id: Uuid,
) -> AppResult<()> {
    sqlx::query(
        "INSERT INTO production.order_outputs
             (id, production_order_id, quantity, lot_id, serial_unit_id, stock_move_id)
         VALUES ($1, $2, $3, $4, $5, $6)",
    )
    .bind(new_id())
    .bind(production_order_id)
    .bind(quantity)
    .bind(lot_id)
    .bind(serial_unit_id)
    .bind(stock_move_id)
    .execute(conn)
    .await?;
    Ok(())
}

#[derive(Debug, Serialize, ToSchema)]
pub struct ProductionSerialCandidate {
    pub id: Uuid,
    pub serial_number: String,
    pub location_id: Uuid,
    pub location: String,
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct SerialParams {
    /// Part of the serial number.
    pub q: Option<String>,
}

/// The serial units in stock of a serial-tracked component, to choose from when completing.
#[utoipa::path(get, path = "/production-orders/{id}/components/{component_id}/serial-units",
    tag = "production", params(("id" = Uuid, Path), ("component_id" = Uuid, Path), SerialParams),
    responses((status = 200, body = Vec<ProductionSerialCandidate>), (status = 404, body = ErrorBody)))]
async fn serial_candidates(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((id, component_id)): Path<(Uuid, Uuid)>,
    Query(p): Query<SerialParams>,
) -> AppResult<Json<Vec<ProductionSerialCandidate>>> {
    user.require(Permission::ProductionRun)?;
    let mut conn = state.db.acquire().await?;
    let product_id: Option<Uuid> = sqlx::query_scalar(
        "SELECT c.component_product_id FROM production.order_components c
         JOIN production.production_orders po ON po.id = c.production_order_id
         WHERE c.id = $1 AND po.id = $2 AND po.company_id = $3",
    )
    .bind(component_id)
    .bind(id)
    .bind(user.company_id)
    .fetch_optional(&mut *conn)
    .await?;
    let product_id = product_id.ok_or(AppError::NotFound("component"))?;
    let q = p.q.as_deref().map(str::trim).filter(|q| !q.is_empty());
    Ok(Json(
        serial_units_in_stock(&mut conn, user.company_id, product_id, q, 50)
            .await?
            .into_iter()
            .map(|u| ProductionSerialCandidate {
                id: u.id,
                serial_number: u.serial_number,
                location_id: u.location_id,
                location: u.location,
            })
            .collect(),
    ))
}

/// The completion routes.
pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(complete_order))
        .routes(routes!(serial_candidates))
}
