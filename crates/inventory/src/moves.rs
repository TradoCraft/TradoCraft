//! Receive, issue, transfer, adjust and reverse stock, and read the move history.

use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::Json;
use chrono::NaiveDate;
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use sqlx::PgConnection;
use tradocraft_core::{audit, AppError, AppResult, AppState, CurrentUser, Permission};
use tradocraft_engineering::serials;
use tradocraft_products::{get_product, Product};
use utoipa::{IntoParams, ToSchema};
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::ledger::{
    get_or_create_lot, load_move, lock_balance, post_move, require_internal_location, reverse_move,
    to_stock_quantity, virtual_location, NewMove, Posted, SerialEffect, StockMove, SELECT_MOVE,
};
use crate::reservations::SALES_ORDER_LINE;

type ErrorBody = tradocraft_core::error::ErrorBody;

#[derive(Debug, Deserialize, ToSchema)]
pub struct ReceiptInput {
    /// Chosen by the client; a retry with the same id changes nothing.
    pub id: Uuid,
    pub product_id: Uuid,
    pub location_id: Uuid,
    #[schema(value_type = String, example = "10")]
    pub quantity: Decimal,
    /// Unit the quantity is entered in; default the stock unit of the product.
    pub uom: Option<String>,
    /// Lot-tracked products: the lot (created if new).
    pub lot_number: Option<String>,
    #[serde(default, deserialize_with = "tradocraft_core::serde_util::opt_date")]
    pub expiry_date: Option<NaiveDate>,
    /// Serial-tracked products: an existing unit that is in stock without a location...
    pub serial_unit_id: Option<Uuid>,
    /// ...or a new serial number, which registers the unit.
    pub serial_number: Option<String>,
    /// manual_receipt (default) | return
    pub reason: Option<String>,
    #[serde(default)]
    pub note: String,
    /// What one stock unit cost (needs `inventory.cost`); default: the standard cost.
    #[schema(value_type = Option<String>, example = "12.5")]
    pub unit_cost: Option<Decimal>,
    /// Currency of `unit_cost` (default: the currency of the company).
    pub currency: Option<String>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct IssueInput {
    pub id: Uuid,
    pub product_id: Uuid,
    pub location_id: Uuid,
    #[schema(value_type = String, example = "2")]
    pub quantity: Decimal,
    pub uom: Option<String>,
    pub lot_id: Option<Uuid>,
    pub serial_unit_id: Option<Uuid>,
    /// consumption (default) | shipment | scrap | repair_use
    pub reason: Option<String>,
    /// Serial units shipped: the customer (unless the unit has one).
    pub customer_id: Option<Uuid>,
    /// Ship or consume the stock reserved for this sales order line: only that reservation is
    /// exempt from the "reserved for orders" check, at most its quantity can be taken, and it
    /// shrinks (or closes as consumed) in the same transaction.
    pub consume_reservation_line: Option<Uuid>,
    #[serde(default)]
    pub note: String,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct TransferInput {
    pub id: Uuid,
    pub product_id: Uuid,
    pub from_location_id: Uuid,
    pub to_location_id: Uuid,
    #[schema(value_type = String, example = "2")]
    pub quantity: Decimal,
    pub uom: Option<String>,
    pub lot_id: Option<Uuid>,
    pub serial_unit_id: Option<Uuid>,
    /// transfer (default) | van_replenishment
    pub reason: Option<String>,
    #[serde(default)]
    pub note: String,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct AdjustmentInput {
    pub id: Uuid,
    pub product_id: Uuid,
    pub location_id: Uuid,
    pub lot_id: Option<Uuid>,
    /// Lot-tracked stock that was found: the lot number (created if new).
    pub lot_number: Option<String>,
    #[serde(default, deserialize_with = "tradocraft_core::serde_util::opt_date")]
    pub expiry_date: Option<NaiveDate>,
    /// Set the stock at the location to this quantity...
    #[schema(value_type = Option<String>, example = "12")]
    pub new_quantity: Option<Decimal>,
    /// ...or change it by this much (negative takes stock away).
    #[schema(value_type = Option<String>, example = "-1")]
    pub delta: Option<Decimal>,
    /// Why; required.
    pub note: String,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct ReverseInput {
    /// Chosen by the client for the reversal move.
    pub id: Uuid,
    /// Reverse even when that takes stock that is reserved for orders (they then lack stock).
    /// Inventory administrators only, which this endpoint already requires.
    #[serde(default)]
    pub force: bool,
    #[serde(default)]
    pub note: String,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct MovePage {
    pub items: Vec<StockMove>,
    pub total: i64,
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct MoveParams {
    pub product_id: Option<Uuid>,
    /// Moves from or to this location.
    pub location_id: Option<Uuid>,
    pub lot_id: Option<Uuid>,
    pub serial_unit_id: Option<Uuid>,
    /// receipt | issue | transfer | adjustment
    pub kind: Option<String>,
    pub reference_type: Option<String>,
    pub reference_id: Option<Uuid>,
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}

fn reply(posted: Posted) -> (StatusCode, Json<StockMove>, bool) {
    match posted {
        Posted::Created(m) => (StatusCode::CREATED, Json(m), true),
        Posted::Replayed(m) => (StatusCode::OK, Json(m), false),
    }
}

/// Quantity in the stock unit, from what the user entered. A retry of a move that was posted
/// (`move_id`) keeps the quantity it was posted with, whatever the conversions say now: removing
/// or changing a conversion must not turn a lost response into a conflict or a failure.
async fn stock_quantity(
    conn: &mut PgConnection,
    company_id: Uuid,
    move_id: Uuid,
    product: &Product,
    quantity: Decimal,
    uom: Option<&str>,
) -> AppResult<(Decimal, Option<(Decimal, String)>)> {
    if quantity <= Decimal::ZERO {
        return Err(AppError::Validation(
            "quantity must be greater than 0".into(),
        ));
    }
    if quantity.round_dp(4) != quantity {
        return Err(AppError::Validation(
            "quantity has at most 4 decimals".into(),
        ));
    }
    if let Some(u) = uom
        .map(str::trim)
        .filter(|u| !u.is_empty() && *u != product.unit)
    {
        let posted: Option<(Decimal, Decimal, String)> = sqlx::query_as(
            "SELECT quantity, entered_quantity, entered_uom FROM inventory.stock_moves
             WHERE id = $1 AND company_id = $2 AND product_id = $3
               AND entered_quantity = $4 AND entered_uom = $5",
        )
        .bind(move_id)
        .bind(company_id)
        .bind(product.id)
        .bind(quantity)
        .bind(u)
        .fetch_optional(&mut *conn)
        .await?;
        if let Some((stock, entered, code)) = posted {
            return Ok((stock, Some((entered, code))));
        }
    }
    to_stock_quantity(conn, product, quantity, uom).await
}

/// Receives stock at a location from outside (a manual receipt; purchasing posts its own).
#[utoipa::path(post, path = "/inventory/receipts", tag = "inventory", request_body = ReceiptInput,
    responses((status = 201, body = StockMove), (status = 200, body = StockMove, description = "Retry of a move that was already posted"),
              (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn receive(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<ReceiptInput>,
) -> AppResult<(StatusCode, Json<StockMove>)> {
    user.require(Permission::InventoryWrite)?;
    if (input.unit_cost.is_some() || input.currency.is_some())
        && !user.can(Permission::InventoryCost)
    {
        return Err(AppError::Forbidden(
            "missing permission inventory.cost".into(),
        ));
    }
    let reason = input.reason.as_deref().unwrap_or("manual_receipt");
    if !matches!(reason, "manual_receipt" | "return") {
        return Err(AppError::Validation(
            "reason must be manual_receipt or return".into(),
        ));
    }
    let mut tx = state.db.begin().await?;
    let product = get_product(&mut *tx, input.product_id).await?;
    let (quantity, entered) = stock_quantity(
        &mut tx,
        user.company_id,
        input.id,
        &product,
        input.quantity,
        input.uom.as_deref(),
    )
    .await?;
    let mut lot_id = None;
    let mut unit_id = None;
    match product.tracking.as_str() {
        "lot" => {
            let number = input.lot_number.as_deref().ok_or_else(|| {
                AppError::Validation(format!("{} needs a lot_number", product.code))
            })?;
            lot_id = Some(
                get_or_create_lot(
                    &mut tx,
                    user.company_id,
                    product.id,
                    number,
                    input.expiry_date,
                )
                .await?,
            );
        }
        "serial" => {
            unit_id = Some(
                match (input.serial_unit_id, input.serial_number.as_deref()) {
                    (Some(id), _) => id,
                    (None, Some(serial)) if !serial.trim().is_empty() => {
                        // Two requests registering the same new serial (a retry racing its
                        // original) take turns: the second waits here until the first commits,
                        // then finds the unit instead of failing on the unique serial number.
                        sqlx::query("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))")
                            .bind(format!("serial:{}:{}", product.id, serial.trim()))
                            .execute(&mut *tx)
                            .await?;
                        match serials::find_by_serial(
                            &mut tx,
                            user.company_id,
                            product.id,
                            serial.trim(),
                        )
                        .await?
                        {
                            Some(id) => id,
                            None if reason == "return" => {
                                return Err(AppError::Validation(format!(
                                    "serial number {} is not known; only a unit that was delivered can be returned",
                                    serial.trim()
                                )))
                            }
                            None => {
                                serials::register_unit(
                                    &mut tx,
                                    &user,
                                    product.id,
                                    serial.trim(),
                                    None,
                                    None,
                                    "",
                                )
                                .await?
                            }
                        }
                    }
                    _ => {
                        return Err(AppError::Validation(
                            "a serial product needs serial_number or serial_unit_id".into(),
                        ))
                    }
                },
            );
        }
        _ => {}
    }
    let source = virtual_location(
        &mut tx,
        user.company_id,
        if reason == "return" {
            "customer"
        } else {
            "supplier"
        },
    )
    .await?;
    let mut m = NewMove::new(
        input.id,
        &user,
        product.id,
        quantity,
        source,
        input.location_id,
        "receipt",
        reason,
    );
    m.lot_id = lot_id;
    m.serial_unit_id = unit_id;
    if reason == "return" && product.tracking == "serial" {
        m.serial_effect = SerialEffect::Return;
    }
    m.entered = entered;
    m.note = input.note;
    m.unit_cost = input.unit_cost;
    m.currency = input.currency;
    let (status, body, _) = reply(post_move(&mut tx, &m).await?);
    tx.commit().await?;
    Ok((status, Json(body.0.for_user(&user))))
}

/// Takes stock out of a location. The reason decides where it goes: a customer (`shipment`),
/// production consumption (`consumption`, `repair_use`) or scrap.
#[utoipa::path(post, path = "/inventory/issues", tag = "inventory", request_body = IssueInput,
    responses((status = 201, body = StockMove), (status = 200, body = StockMove), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn issue(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<IssueInput>,
) -> AppResult<(StatusCode, Json<StockMove>)> {
    user.require(Permission::InventoryWrite)?;
    let reason = input.reason.as_deref().unwrap_or("consumption");
    let (target, effect) = match reason {
        "shipment" => ("customer", SerialEffect::Deliver(input.customer_id)),
        "scrap" => ("scrap", SerialEffect::Scrap),
        "consumption" | "repair_use" => ("production_consumption", SerialEffect::None),
        _ => {
            return Err(AppError::Validation(
                "reason must be consumption, shipment, scrap or repair_use".into(),
            ))
        }
    };
    let mut tx = state.db.begin().await?;
    let product = get_product(&mut *tx, input.product_id).await?;
    let (quantity, entered) = stock_quantity(
        &mut tx,
        user.company_id,
        input.id,
        &product,
        input.quantity,
        input.uom.as_deref(),
    )
    .await?;
    let to = virtual_location(&mut tx, user.company_id, target).await?;
    let mut m = NewMove::new(
        input.id,
        &user,
        product.id,
        quantity,
        input.location_id,
        to,
        "issue",
        reason,
    );
    m.lot_id = input.lot_id;
    m.serial_unit_id = input.serial_unit_id;
    m.entered = entered;
    m.note = input.note;
    m.respect_reservations = true;
    if let Some(line) = input.consume_reservation_line {
        m.consume_reservation = Some((SALES_ORDER_LINE.to_string(), line));
        m.reference = Some((SALES_ORDER_LINE.to_string(), line));
    }
    m.serial_effect = if product.tracking == "serial" {
        effect
    } else {
        SerialEffect::None
    };
    let (status, body, _) = reply(post_move(&mut tx, &m).await?);
    tx.commit().await?;
    Ok((status, Json(body.0.for_user(&user))))
}

/// Moves stock between two locations (also from a warehouse to a service van).
#[utoipa::path(post, path = "/inventory/transfers", tag = "inventory", request_body = TransferInput,
    responses((status = 201, body = StockMove), (status = 200, body = StockMove), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn transfer(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<TransferInput>,
) -> AppResult<(StatusCode, Json<StockMove>)> {
    user.require(Permission::InventoryWrite)?;
    let reason = input.reason.as_deref().unwrap_or("transfer");
    if !matches!(reason, "transfer" | "van_replenishment") {
        return Err(AppError::Validation(
            "reason must be transfer or van_replenishment".into(),
        ));
    }
    let mut tx = state.db.begin().await?;
    let product = get_product(&mut *tx, input.product_id).await?;
    let (quantity, entered) = stock_quantity(
        &mut tx,
        user.company_id,
        input.id,
        &product,
        input.quantity,
        input.uom.as_deref(),
    )
    .await?;
    let mut m = NewMove::new(
        input.id,
        &user,
        product.id,
        quantity,
        input.from_location_id,
        input.to_location_id,
        "transfer",
        reason,
    );
    m.lot_id = input.lot_id;
    m.serial_unit_id = input.serial_unit_id;
    m.entered = entered;
    m.note = input.note;
    m.respect_reservations = true;
    let (status, body, _) = reply(post_move(&mut tx, &m).await?);
    tx.commit().await?;
    Ok((status, Json(body.0.for_user(&user))))
}

/// Corrects the stock at a location to a counted quantity, or by a difference.
#[utoipa::path(post, path = "/inventory/adjustments", tag = "inventory", request_body = AdjustmentInput,
    responses((status = 201, body = StockMove), (status = 200, body = StockMove), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn adjust(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<AdjustmentInput>,
) -> AppResult<(StatusCode, Json<StockMove>)> {
    user.require(Permission::InventoryAdmin)?;
    if input.note.trim().is_empty() {
        return Err(AppError::Validation("a reason (note) is required".into()));
    }
    if input.new_quantity.is_some() == input.delta.is_some() {
        return Err(AppError::Validation(
            "give either new_quantity or delta".into(),
        ));
    }
    let mut tx = state.db.begin().await?;
    // A retry returns the move that was posted, whatever the stock is now.
    let earlier: Option<(Uuid, Uuid, Uuid, Uuid)> = sqlx::query_as(
        "SELECT company_id, product_id, from_location_id, to_location_id FROM inventory.stock_moves WHERE id = $1",
    )
    .bind(input.id)
    .fetch_optional(&mut *tx)
    .await?;
    if let Some((company, product, from, to)) = earlier {
        if company == user.company_id
            && product == input.product_id
            && (from == input.location_id || to == input.location_id)
        {
            let m = load_move(&mut tx, user.company_id, input.id).await?;
            return Ok((StatusCode::OK, Json(m.for_user(&user))));
        }
        return Err(AppError::Conflict(
            "this move id was already used for a different move".into(),
        ));
    }
    let product = get_product(&mut *tx, input.product_id).await?;
    if product.tracking == "serial" {
        return Err(AppError::Validation(
            "serial units are not adjusted: receive the unit, or issue it with reason scrap".into(),
        ));
    }
    let lot_id = match (
        product.tracking.as_str(),
        input.lot_id,
        input.lot_number.as_deref(),
    ) {
        ("lot", Some(id), _) => Some(id),
        ("lot", None, Some(n)) => Some(
            get_or_create_lot(&mut tx, user.company_id, product.id, n, input.expiry_date).await?,
        ),
        ("lot", None, None) => {
            return Err(AppError::Validation(format!(
                "{} needs a lot",
                product.code
            )))
        }
        _ => None,
    };
    let delta = match (input.new_quantity, input.delta) {
        (Some(q), _) => {
            if q < Decimal::ZERO {
                return Err(AppError::Validation(
                    "new_quantity cannot be negative".into(),
                ));
            }
            // Lock the place first (creating its balance row when there is none), so two calls that
            // set the same quantity cannot both add it.
            require_internal_location(&mut tx, user.company_id, input.location_id).await?;
            let have = lock_balance(
                &mut tx,
                user.company_id,
                product.id,
                input.location_id,
                lot_id,
            )
            .await?;
            q - have
        }
        (None, Some(d)) => d,
        (None, None) => unreachable!(),
    };
    if delta == Decimal::ZERO {
        return Err(AppError::Validation(
            "the stock is already that quantity".into(),
        ));
    }
    let adj = virtual_location(&mut tx, user.company_id, "adjustment").await?;
    let (from, to) = if delta > Decimal::ZERO {
        (adj, input.location_id)
    } else {
        (input.location_id, adj)
    };
    let mut m = NewMove::new(
        input.id,
        &user,
        product.id,
        delta.abs(),
        from,
        to,
        "adjustment",
        "correction",
    );
    m.lot_id = lot_id;
    m.note = input.note;
    let posted = post_move(&mut tx, &m).await?;
    if let Posted::Created(ref mv) = posted {
        audit::record(
            &mut tx,
            &user,
            "stock_move",
            mv.id,
            "adjusted",
            serde_json::json!({ "product_id": product.id, "delta": delta, "location_id": input.location_id }),
        )
        .await?;
    }
    let (status, body, _) = reply(posted);
    tx.commit().await?;
    Ok((status, Json(body.0.for_user(&user))))
}

/// Undoes a move with a new move in the opposite direction. The original stays in the ledger.
#[utoipa::path(post, path = "/inventory/moves/{id}/reverse", tag = "inventory", params(("id" = Uuid, Path)),
    request_body = ReverseInput,
    responses((status = 201, body = StockMove), (status = 200, body = StockMove), (status = 404, body = ErrorBody), (status = 409, body = ErrorBody)))]
async fn reverse(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<ReverseInput>,
) -> AppResult<(StatusCode, Json<StockMove>)> {
    user.require(Permission::InventoryAdmin)?;
    let mut tx = state.db.begin().await?;
    let posted = reverse_move(&mut tx, &user, id, input.id, input.note.trim(), input.force).await?;
    if let Posted::Created(ref mv) = posted {
        audit::record(
            &mut tx,
            &user,
            "stock_move",
            id,
            "reversed",
            serde_json::json!({ "reversal_id": mv.id, "note": input.note.trim(), "forced": input.force }),
        )
        .await?;
    }
    let (status, body, _) = reply(posted);
    tx.commit().await?;
    Ok((status, Json(body.0.for_user(&user))))
}

#[utoipa::path(get, path = "/inventory/moves", tag = "inventory", params(MoveParams),
    responses((status = 200, body = MovePage)))]
async fn list_moves(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(p): Query<MoveParams>,
) -> AppResult<Json<MovePage>> {
    user.require(Permission::InventoryRead)?;
    let filter = "WHERE m.company_id = $1
        AND ($2::uuid IS NULL OR m.product_id = $2)
        AND ($3::uuid IS NULL OR m.from_location_id = $3 OR m.to_location_id = $3)
        AND ($4::uuid IS NULL OR m.lot_id = $4)
        AND ($5::uuid IS NULL OR m.serial_unit_id = $5)
        AND ($6::text IS NULL OR m.kind = $6)
        AND ($7::text IS NULL OR m.reference_type = $7)
        AND ($8::uuid IS NULL OR m.reference_id = $8)";
    let items: Vec<StockMove> = sqlx::query_as(sqlx::AssertSqlSafe(format!(
        "{SELECT_MOVE} {filter} ORDER BY m.seq DESC LIMIT $9 OFFSET $10"
    )))
    .bind(user.company_id)
    .bind(p.product_id)
    .bind(p.location_id)
    .bind(p.lot_id)
    .bind(p.serial_unit_id)
    .bind(&p.kind)
    .bind(&p.reference_type)
    .bind(p.reference_id)
    .bind(p.limit.unwrap_or(50).clamp(1, 500))
    .bind(p.offset.unwrap_or(0).max(0))
    .fetch_all(&state.db)
    .await?;
    let total = sqlx::query_scalar(sqlx::AssertSqlSafe(format!(
        "SELECT count(*) FROM inventory.stock_moves m {filter}"
    )))
    .bind(user.company_id)
    .bind(p.product_id)
    .bind(p.location_id)
    .bind(p.lot_id)
    .bind(p.serial_unit_id)
    .bind(&p.kind)
    .bind(&p.reference_type)
    .bind(p.reference_id)
    .fetch_one(&state.db)
    .await?;
    Ok(Json(MovePage {
        items: items.into_iter().map(|m| m.for_user(&user)).collect(),
        total,
    }))
}

#[utoipa::path(get, path = "/inventory/moves/{id}", tag = "inventory", params(("id" = Uuid, Path)),
    responses((status = 200, body = StockMove), (status = 404, body = ErrorBody)))]
async fn get_move(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<StockMove>> {
    user.require(Permission::InventoryRead)?;
    let mut conn = state.db.acquire().await?;
    Ok(Json(
        load_move(&mut conn, user.company_id, id)
            .await?
            .for_user(&user),
    ))
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(receive))
        .routes(routes!(issue))
        .routes(routes!(transfer))
        .routes(routes!(adjust))
        .routes(routes!(reverse))
        .routes(routes!(list_moves))
        .routes(routes!(get_move))
}
