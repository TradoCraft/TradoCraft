//! The stock ledger: posting moves, the balance projection, unit conversion and rebuilding.
//!
//! Every stock change in the system goes through [`post_move`]. Other modules (purchasing,
//! delivery, production) call it in their own transaction.

use chrono::{DateTime, NaiveDate, Utc};
use rust_decimal::{Decimal, RoundingStrategy};
use serde::Serialize;
use sqlx::{FromRow, PgConnection};
use tradocraft_core::{new_id, AppError, AppResult, CurrentUser, Permission};
use tradocraft_engineering::serials;
use tradocraft_products::{get_product_for_share, Product};
use utoipa::ToSchema;
use uuid::Uuid;

/// Quantities have four decimals.
pub const QUANTITY_SCALE: u32 = 4;

pub const KINDS: [&str; 4] = ["receipt", "issue", "transfer", "adjustment"];

/// One row of the ledger, as shown to staff.
#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct StockMove {
    pub id: Uuid,
    /// Position in the ledger; moves are shown newest first by this number.
    pub seq: i64,
    pub product_id: Uuid,
    pub product_code: String,
    pub product_name: String,
    /// The stock unit the quantity is in.
    pub unit: String,
    #[schema(value_type = String, example = "5.0000")]
    pub quantity: Decimal,
    pub from_location_id: Uuid,
    pub from_location: String,
    pub to_location_id: Uuid,
    pub to_location: String,
    pub lot_id: Option<Uuid>,
    pub lot_number: Option<String>,
    pub serial_unit_id: Option<Uuid>,
    pub serial_number: Option<String>,
    /// receipt | issue | transfer | adjustment
    pub kind: String,
    pub reason: String,
    pub reference_type: Option<String>,
    pub reference_id: Option<Uuid>,
    pub note: String,
    /// What the user typed, when it was in another unit than the stock unit.
    #[schema(value_type = Option<String>)]
    pub entered_quantity: Option<Decimal>,
    pub entered_uom: Option<String>,
    /// Cost per stock unit: what the posting module booked, else the standard cost of the product
    /// at the time of the move. Only with `inventory.cost`.
    #[schema(value_type = Option<String>)]
    pub unit_cost: Option<Decimal>,
    /// Currency of `unit_cost`. Only with `inventory.cost`.
    pub currency: Option<String>,
    /// The move this one reverses.
    pub reversed_of: Option<Uuid>,
    /// The move that reversed this one.
    pub reversed_by: Option<Uuid>,
    pub occurred_at: DateTime<Utc>,
    pub created_by_name: String,
    pub created_at: DateTime<Utc>,
}

impl StockMove {
    pub fn for_user(mut self, user: &CurrentUser) -> Self {
        if !user.can(Permission::InventoryCost) {
            self.unit_cost = None;
            self.currency = None;
        }
        self
    }
}

pub const SELECT_MOVE: &str = "SELECT m.id, m.seq, m.product_id, p.code AS product_code, p.name AS product_name, p.unit,
        m.quantity, m.from_location_id, COALESCE(fw.code || '/' || fl.code, fl.kind) AS from_location,
        m.to_location_id, COALESCE(tw.code || '/' || tl.code, tl.kind) AS to_location,
        m.lot_id, lot.lot_number, m.serial_unit_id, su.serial_number, m.kind, m.reason, m.reference_type,
        m.reference_id, m.note, m.entered_quantity, m.entered_uom, m.unit_cost, m.currency::text AS currency, m.reversed_of,
        rev.id AS reversed_by, m.occurred_at, u.display_name AS created_by_name, m.created_at
     FROM inventory.stock_moves m
     JOIN products.products p ON p.id = m.product_id
     JOIN inventory.locations fl ON fl.id = m.from_location_id
     LEFT JOIN inventory.warehouses fw ON fw.id = fl.warehouse_id
     JOIN inventory.locations tl ON tl.id = m.to_location_id
     LEFT JOIN inventory.warehouses tw ON tw.id = tl.warehouse_id
     LEFT JOIN inventory.lots lot ON lot.id = m.lot_id
     LEFT JOIN engineering.serial_units su ON su.id = m.serial_unit_id
     LEFT JOIN inventory.stock_moves rev ON rev.reversed_of = m.id
     JOIN core.users u ON u.id = m.created_by";

pub async fn load_move(
    conn: &mut PgConnection,
    company_id: Uuid,
    id: Uuid,
) -> AppResult<StockMove> {
    sqlx::query_as(sqlx::AssertSqlSafe(format!(
        "{SELECT_MOVE} WHERE m.id = $1 AND m.company_id = $2"
    )))
    .bind(id)
    .bind(company_id)
    .fetch_optional(conn)
    .await?
    .ok_or(AppError::NotFound("stock move"))
}

/// What a serial unit's status does as a consequence of a move.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SerialEffect {
    /// Only the location changes.
    None,
    /// The unit is delivered to a customer.
    Deliver(Option<Uuid>),
    /// The unit is scrapped.
    Scrap,
    /// A delivery or scrapping is undone: back in stock; `clear_customer` removes the customer.
    Restore { clear_customer: bool },
    /// A delivered or installed unit comes back from the customer (a `return` receipt): in stock at
    /// the receiving location, customer removed. The as-built genealogy (ADR 0011) is untouched:
    /// only units that are not built into another unit can be returned.
    Return,
}

/// A move to post. `id` is chosen by the client and makes retries safe.
#[derive(Debug, Clone)]
pub struct NewMove {
    pub id: Uuid,
    pub company_id: Uuid,
    pub user_id: Uuid,
    pub product_id: Uuid,
    /// In the stock unit of the product, at most four decimals.
    pub quantity: Decimal,
    pub from_location_id: Uuid,
    pub to_location_id: Uuid,
    pub lot_id: Option<Uuid>,
    pub serial_unit_id: Option<Uuid>,
    pub kind: &'static str,
    pub reason: String,
    pub reference: Option<(String, Uuid)>,
    pub note: String,
    pub entered: Option<(Decimal, String)>,
    pub reversed_of: Option<Uuid>,
    /// Issues and transfers may not take stock that is reserved for orders.
    pub respect_reservations: bool,
    /// Cost per stock unit booked by the caller (purchasing: the price paid). When absent the
    /// standard cost of the product is used, in the currency of the company.
    pub unit_cost: Option<Decimal>,
    /// Currency of `unit_cost`; default: the currency of the company.
    pub currency: Option<String>,
    /// Use `unit_cost` and `currency` exactly as they are, also when they are empty (a reversal
    /// copies the cost of the move it undoes).
    pub inherit_cost: bool,
    /// The reservation (`reference_type`, `reference_id`) this move ships or consumes. Only that
    /// reservation's quantity at the source location and lot is exempt from the reservation
    /// check, the move may not take more than it holds, and its quantity is reduced (closed as
    /// consumed when nothing is left) in the same transaction.
    pub consume_reservation: Option<(String, Uuid)>,
    pub serial_effect: SerialEffect,
}

impl NewMove {
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        id: Uuid,
        user: &CurrentUser,
        product_id: Uuid,
        quantity: Decimal,
        from_location_id: Uuid,
        to_location_id: Uuid,
        kind: &'static str,
        reason: &str,
    ) -> Self {
        NewMove {
            id,
            company_id: user.company_id,
            user_id: user.user_id,
            product_id,
            quantity,
            from_location_id,
            to_location_id,
            lot_id: None,
            serial_unit_id: None,
            kind,
            reason: reason.to_string(),
            reference: None,
            note: String::new(),
            entered: None,
            reversed_of: None,
            respect_reservations: false,
            unit_cost: None,
            currency: None,
            inherit_cost: false,
            consume_reservation: None,
            serial_effect: SerialEffect::None,
        }
    }
}

pub enum Posted {
    Created(StockMove),
    /// The same move was posted before (a retry); nothing changed.
    Replayed(StockMove),
}

impl Posted {
    pub fn into_move(self) -> StockMove {
        match self {
            Posted::Created(m) | Posted::Replayed(m) => m,
        }
    }
}

#[derive(FromRow)]
struct Existing {
    company_id: Uuid,
    product_id: Uuid,
    quantity: Decimal,
    from_location_id: Uuid,
    to_location_id: Uuid,
    lot_id: Option<Uuid>,
    serial_unit_id: Option<Uuid>,
    kind: String,
    reason: String,
    reversed_of: Option<Uuid>,
    note: String,
    reference_type: Option<String>,
    reference_id: Option<Uuid>,
    entered_quantity: Option<Decimal>,
    entered_uom: Option<String>,
    unit_cost: Option<Decimal>,
}

#[derive(FromRow)]
struct Loc {
    kind: String,
    active: bool,
    warehouse_active: Option<bool>,
    label: String,
}

async fn load_location(conn: &mut PgConnection, company_id: Uuid, id: Uuid) -> AppResult<Loc> {
    sqlx::query_as(
        "SELECT l.kind, l.active, w.active AS warehouse_active, COALESCE(w.code || '/' || l.code, l.kind) AS label
         FROM inventory.locations l LEFT JOIN inventory.warehouses w ON w.id = l.warehouse_id
         WHERE l.id = $1 AND l.company_id = $2",
    )
    .bind(id)
    .bind(company_id)
    .fetch_optional(conn)
    .await?
    .ok_or(AppError::NotFound("location"))
}

/// The virtual location of a kind (`supplier`, `customer`, `production_consumption`,
/// `production_output`, `transit`, `adjustment`, `scrap`), created on first use.
pub async fn virtual_location(
    conn: &mut PgConnection,
    company_id: Uuid,
    kind: &str,
) -> AppResult<Uuid> {
    sqlx::query(
        "INSERT INTO inventory.locations (id, company_id, warehouse_id, code, name, kind)
         VALUES ($1, $2, NULL, $3, $3, $3)
         ON CONFLICT (company_id, kind) WHERE warehouse_id IS NULL DO NOTHING",
    )
    .bind(new_id())
    .bind(company_id)
    .bind(kind)
    .execute(&mut *conn)
    .await?;
    Ok(sqlx::query_scalar(
        "SELECT id FROM inventory.locations WHERE company_id = $1 AND kind = $2 AND warehouse_id IS NULL",
    )
    .bind(company_id)
    .bind(kind)
    .fetch_one(conn)
    .await?)
}

fn same_move(e: &Existing, m: &NewMove) -> bool {
    e.company_id == m.company_id
        && e.product_id == m.product_id
        && e.quantity == m.quantity
        && e.from_location_id == m.from_location_id
        && e.to_location_id == m.to_location_id
        && e.lot_id == m.lot_id
        && e.serial_unit_id == m.serial_unit_id
        && e.kind == m.kind
        && e.reason == m.reason
        && e.reversed_of == m.reversed_of
        && e.note == m.note.trim()
        && e.reference_type == m.reference.as_ref().map(|r| r.0.clone())
        && e.reference_id == m.reference.as_ref().map(|r| r.1)
        && e.entered_quantity == m.entered.as_ref().map(|x| x.0)
        && e.entered_uom == m.entered.as_ref().map(|x| x.1.clone())
        && m.unit_cost.is_none_or(|c| e.unit_cost == Some(c))
}

/// Posts a move: validates it, appends it to the ledger and updates the balances, in the caller's
/// transaction. A retry with the same id and content returns [`Posted::Replayed`].
pub async fn post_move(conn: &mut PgConnection, m: &NewMove) -> AppResult<Posted> {
    if m.quantity <= Decimal::ZERO {
        return Err(AppError::Validation(
            "quantity must be greater than 0".into(),
        ));
    }
    if m.quantity.round_dp(QUANTITY_SCALE) != m.quantity {
        return Err(AppError::Validation(format!(
            "quantity has at most {QUANTITY_SCALE} decimals"
        )));
    }
    if m.from_location_id == m.to_location_id {
        return Err(AppError::Validation(
            "from and to location must differ".into(),
        ));
    }
    if !KINDS.contains(&m.kind) {
        return Err(AppError::Validation(format!(
            "unknown move kind {}",
            m.kind
        )));
    }

    if let Some(posted) = replay(conn, m).await? {
        return Ok(posted);
    }

    let product = get_product_for_share(&mut *conn, m.product_id).await?;
    if product.product_type == "service" {
        return Err(AppError::Validation(format!(
            "{} is a service and is not stocked",
            product.code
        )));
    }
    if let Some(posted) = check_tracking(conn, m, &product).await? {
        return Ok(posted);
    }

    let from = load_location(conn, m.company_id, m.from_location_id).await?;
    let to = load_location(conn, m.company_id, m.to_location_id).await?;
    let (from_internal, to_internal) = (from.kind == "internal", to.kind == "internal");
    let shape_ok = if m.kind == "transfer" {
        from_internal && to_internal
    } else {
        from_internal != to_internal
    };
    if !shape_ok {
        return Err(AppError::Validation(format!(
            "a {} cannot go from {} to {}",
            m.kind, from.label, to.label
        )));
    }
    if m.consume_reservation.is_some() && !from_internal {
        return Err(AppError::Validation(
            "only a move out of stock can consume a reservation".into(),
        ));
    }
    if to_internal && !(to.active && to.warehouse_active.unwrap_or(false)) {
        return Err(AppError::Validation(format!(
            "location {} is inactive",
            to.label
        )));
    }

    let cost = move_cost(conn, m, &product).await?;
    let inserted = sqlx::query(
        "INSERT INTO inventory.stock_moves (id, company_id, product_id, quantity, from_location_id, to_location_id,
             lot_id, serial_unit_id, kind, reason, reference_type, reference_id, note, entered_quantity,
             entered_uom, unit_cost, currency, reversed_of, created_by)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19)
         ON CONFLICT (id) DO NOTHING",
    )
    .bind(m.id)
    .bind(m.company_id)
    .bind(m.product_id)
    .bind(m.quantity)
    .bind(m.from_location_id)
    .bind(m.to_location_id)
    .bind(m.lot_id)
    .bind(m.serial_unit_id)
    .bind(m.kind)
    .bind(&m.reason)
    .bind(m.reference.as_ref().map(|r| r.0.clone()))
    .bind(m.reference.as_ref().map(|r| r.1))
    .bind(m.note.trim())
    .bind(m.entered.as_ref().map(|e| e.0))
    .bind(m.entered.as_ref().map(|e| e.1.clone()))
    .bind(cost.as_ref().map(|c| c.0))
    .bind(cost.as_ref().map(|c| c.1.as_str()))
    .bind(m.reversed_of)
    .bind(m.user_id)
    .execute(&mut *conn)
    .await?;
    // A concurrent retry with this id committed between the check above and the insert: replay it.
    if inserted.rows_affected() == 0 {
        return replay(conn, m).await?.ok_or_else(|| {
            AppError::Conflict(format!("the move id {} could not be posted", m.id))
        });
    }

    // Balances: always in the order of the location ids, so concurrent moves cannot deadlock.
    let mut sides = [
        (m.from_location_id, -m.quantity, from_internal, &from.label),
        (m.to_location_id, m.quantity, to_internal, &to.label),
    ];
    sides.sort_by_key(|s| s.0);
    for (location_id, delta, internal, label) in sides {
        apply_balance(
            conn,
            m,
            &product,
            location_id,
            delta,
            internal,
            label,
            m.respect_reservations && delta < Decimal::ZERO,
        )
        .await?;
    }

    if let Some(unit) = m.serial_unit_id {
        move_serial(conn, m, unit, from_internal, to_internal, &from.label).await?;
    }
    Ok(Posted::Created(load_move(conn, m.company_id, m.id).await?))
}

/// The cost stored on the move: the caller's, the copied one of a reversal, or the standard cost of
/// the product (all in a currency; the company's when none is given).
async fn move_cost(
    conn: &mut PgConnection,
    m: &NewMove,
    product: &Product,
) -> AppResult<Option<(Decimal, String)>> {
    if m.currency.is_some() && m.unit_cost.is_none() && !m.inherit_cost {
        return Err(AppError::Validation("a currency needs a unit cost".into()));
    }
    let explicit = if m.inherit_cost || m.unit_cost.is_some() {
        m.unit_cost
    } else {
        product.standard_cost
    };
    let Some(cost) = explicit else {
        if m.currency.is_some() {
            return Err(AppError::Validation("a currency needs a unit cost".into()));
        }
        return Ok(None);
    };
    if cost < Decimal::ZERO {
        return Err(AppError::Validation("unit cost cannot be negative".into()));
    }
    let currency = match &m.currency {
        Some(c) if m.unit_cost.is_some() || m.inherit_cost => c.trim().to_uppercase(),
        _ => {
            sqlx::query_scalar::<_, String>(
                "SELECT currency::text FROM core.companies WHERE id = $1",
            )
            .bind(m.company_id)
            .fetch_one(conn)
            .await?
        }
    };
    if currency.len() != 3 || !currency.chars().all(|c| c.is_ascii_uppercase()) {
        return Err(AppError::Validation(
            "currency must be a three-letter code such as EUR".into(),
        ));
    }
    Ok(Some((cost, currency)))
}

/// A move with this id that already exists: the same content is a retry and returns that move,
/// different content is a conflict. `None` when the id is free.
async fn replay(conn: &mut PgConnection, m: &NewMove) -> AppResult<Option<Posted>> {
    let existing: Option<Existing> = sqlx::query_as(
        "SELECT company_id, product_id, quantity, from_location_id, to_location_id, lot_id, serial_unit_id,
                kind, reason, reversed_of, note, reference_type, reference_id, entered_quantity, entered_uom,
                unit_cost
         FROM inventory.stock_moves WHERE id = $1",
    )
    .bind(m.id)
    .fetch_optional(&mut *conn)
    .await?;
    match existing {
        None => Ok(None),
        Some(e) if same_move(&e, m) => Ok(Some(Posted::Replayed(
            load_move(conn, m.company_id, m.id).await?,
        ))),
        Some(_) => Err(AppError::Conflict(format!(
            "the move id {} was already used for a different move; choose a new id for a new move",
            m.id
        ))),
    }
}

/// Checks lot and serial rules. Returns the posted move when, once the serial unit is locked, a
/// concurrent request with the same id turns out to have posted it already: the retry then replays
/// instead of failing on the status the first request left behind.
async fn check_tracking(
    conn: &mut PgConnection,
    m: &NewMove,
    product: &Product,
) -> AppResult<Option<Posted>> {
    match product.tracking.as_str() {
        "serial" => {
            let unit = m.serial_unit_id.ok_or_else(|| {
                AppError::Validation(format!("{} needs a serial unit", product.code))
            })?;
            if m.quantity != Decimal::ONE || m.lot_id.is_some() {
                return Err(AppError::Validation(
                    "a serial unit is moved one at a time, without a lot".into(),
                ));
            }
            let u = serials::lock_for_stock(conn, m.company_id, unit).await?;
            if let Some(posted) = replay(conn, m).await? {
                return Ok(Some(posted));
            }
            if u.product_id != m.product_id {
                return Err(AppError::Validation(
                    "the serial unit belongs to another product".into(),
                ));
            }
            if matches!(m.serial_effect, SerialEffect::Return) {
                if !matches!(u.status.as_str(), "delivered" | "installed") || u.built_into.is_some()
                {
                    return Err(AppError::Conflict(format!(
                        "{} is {}; only a delivered or installed unit can come back as a return",
                        u.serial_number,
                        if u.built_into.is_some() {
                            "built into another unit"
                        } else {
                            u.status.as_str()
                        }
                    )));
                }
            } else if matches!(m.serial_effect, SerialEffect::Restore { .. }) {
                if !matches!(u.status.as_str(), "delivered" | "scrapped" | "installed") {
                    return Err(AppError::Conflict(format!(
                        "{} is {}, it was not delivered or scrapped by this move",
                        u.serial_number, u.status
                    )));
                }
            } else if u.status != "in_stock" || u.built_into.is_some() {
                return Err(AppError::Conflict(format!(
                    "{} is {}, not in stock",
                    u.serial_number,
                    if u.built_into.is_some() {
                        "built into another unit"
                    } else {
                        u.status.as_str()
                    }
                )));
            }
        }
        "lot" => {
            let lot = m
                .lot_id
                .ok_or_else(|| AppError::Validation(format!("{} needs a lot", product.code)))?;
            let ok: bool = sqlx::query_scalar(
                "SELECT EXISTS (SELECT 1 FROM inventory.lots WHERE id = $1 AND company_id = $2 AND product_id = $3)",
            )
            .bind(lot)
            .bind(m.company_id)
            .bind(m.product_id)
            .fetch_one(&mut *conn)
            .await?;
            if !ok {
                return Err(AppError::NotFound("lot"));
            }
            if m.serial_unit_id.is_some() {
                return Err(AppError::Validation(
                    "lot products have no serial units".into(),
                ));
            }
        }
        _ => {
            if m.lot_id.is_some() || m.serial_unit_id.is_some() {
                return Err(AppError::Validation(format!(
                    "{} is not lot or serial tracked",
                    product.code
                )));
            }
        }
    }
    Ok(None)
}

#[allow(clippy::too_many_arguments)]
async fn apply_balance(
    conn: &mut PgConnection,
    m: &NewMove,
    product: &Product,
    location_id: Uuid,
    delta: Decimal,
    internal: bool,
    label: &str,
    check_reserved: bool,
) -> AppResult<()> {
    if delta < Decimal::ZERO && internal {
        let have = lock_balance(conn, m.company_id, m.product_id, location_id, m.lot_id).await?;
        if have + delta < Decimal::ZERO {
            return Err(AppError::Conflict(format!(
                "not enough stock of {} at {label}: {} on hand, {} needed",
                product.code,
                have.normalize(),
                (-delta).normalize()
            )));
        }
        // Shipping a reservation's own stock: it may take what that reservation holds, no more.
        let mut exempt = Decimal::ZERO;
        if let Some((reference_type, reference_id)) = &m.consume_reservation {
            let held = sqlx::query_scalar::<_, Decimal>(
                "SELECT quantity FROM inventory.reservations
                 WHERE company_id = $1 AND reference_type = $2 AND reference_id = $3 AND product_id = $4
                   AND location_id = $5 AND lot_id IS NOT DISTINCT FROM $6 AND status = 'active'
                 FOR UPDATE",
            )
            .bind(m.company_id)
            .bind(reference_type)
            .bind(reference_id)
            .bind(m.product_id)
            .bind(location_id)
            .bind(m.lot_id)
            .fetch_optional(&mut *conn)
            .await?
            .unwrap_or(Decimal::ZERO);
            if -delta > held {
                return Err(AppError::Conflict(format!(
                    "{} {} of {} asked from the reservation at {label}, which holds {}",
                    (-delta).normalize(),
                    product.unit,
                    product.code,
                    held.normalize()
                )));
            }
            exempt = held;
        }
        if check_reserved {
            let reserved =
                reserved_at(conn, m.company_id, m.product_id, location_id, m.lot_id).await?;
            if have + delta < reserved - exempt {
                return Err(AppError::Conflict(format!(
                    "{} of {} at {label} is reserved for orders; only {} can be taken",
                    reserved.normalize(),
                    product.code,
                    (have - reserved + exempt).max(Decimal::ZERO).normalize()
                )));
            }
        }
        sqlx::query(
            "UPDATE inventory.stock_balances SET quantity = quantity + $5, updated_at = now()
             WHERE company_id = $1 AND product_id = $2 AND location_id = $3 AND lot_id IS NOT DISTINCT FROM $4",
        )
        .bind(m.company_id)
        .bind(m.product_id)
        .bind(location_id)
        .bind(m.lot_id)
        .bind(delta)
        .execute(&mut *conn)
        .await?;
        if let Some((reference_type, reference_id)) = &m.consume_reservation {
            consume_reservation(conn, m, reference_type, *reference_id, location_id, -delta)
                .await?;
        }
    } else {
        sqlx::query(
            "INSERT INTO inventory.stock_balances (company_id, product_id, location_id, lot_id, quantity, allow_negative)
             VALUES ($1, $2, $3, $4, $5, $6)
             ON CONFLICT (company_id, product_id, location_id, (COALESCE(lot_id, '00000000-0000-0000-0000-000000000000'::uuid)))
             DO UPDATE SET quantity = inventory.stock_balances.quantity + EXCLUDED.quantity, updated_at = now()",
        )
        .bind(m.company_id)
        .bind(m.product_id)
        .bind(location_id)
        .bind(m.lot_id)
        .bind(delta)
        .bind(!internal)
        .execute(conn)
        .await?;
    }
    Ok(())
}

/// Locks the balance of a product at an internal location and lot and returns its quantity. The
/// row is created (with 0) when it does not exist yet, so that two transactions that both want to
/// set or count the stock of a place that has none queue up instead of both reading 0.
pub async fn lock_balance(
    conn: &mut PgConnection,
    company_id: Uuid,
    product_id: Uuid,
    location_id: Uuid,
    lot_id: Option<Uuid>,
) -> AppResult<Decimal> {
    sqlx::query(
        "INSERT INTO inventory.stock_balances (company_id, product_id, location_id, lot_id, quantity, allow_negative)
         VALUES ($1, $2, $3, $4, 0, false)
         ON CONFLICT (company_id, product_id, location_id, (COALESCE(lot_id, '00000000-0000-0000-0000-000000000000'::uuid)))
         DO NOTHING",
    )
    .bind(company_id)
    .bind(product_id)
    .bind(location_id)
    .bind(lot_id)
    .execute(&mut *conn)
    .await?;
    Ok(sqlx::query_scalar(
        "SELECT quantity FROM inventory.stock_balances
         WHERE company_id = $1 AND product_id = $2 AND location_id = $3 AND lot_id IS NOT DISTINCT FROM $4
         FOR UPDATE",
    )
    .bind(company_id)
    .bind(product_id)
    .bind(location_id)
    .bind(lot_id)
    .fetch_one(conn)
    .await?)
}

/// An internal location of the company that may hold stock (not a virtual one).
pub async fn require_internal_location(
    conn: &mut PgConnection,
    company_id: Uuid,
    location_id: Uuid,
) -> AppResult<()> {
    let l = load_location(conn, company_id, location_id).await?;
    if l.kind != "internal" {
        return Err(AppError::Validation(format!(
            "{} is not a stock location",
            l.label
        )));
    }
    Ok(())
}

/// Takes `quantity` out of the reservation a move ships: the row shrinks, and is closed as
/// consumed when nothing is left. The move is recorded on the row.
async fn consume_reservation(
    conn: &mut PgConnection,
    m: &NewMove,
    reference_type: &str,
    reference_id: Uuid,
    location_id: Uuid,
    quantity: Decimal,
) -> AppResult<()> {
    sqlx::query(
        "UPDATE inventory.reservations SET
            consumed_quantity = consumed_quantity + $7,
            closed_move_id = $8,
            status = CASE WHEN quantity <= $7 THEN 'consumed' ELSE status END,
            closed_at = CASE WHEN quantity <= $7 THEN now() ELSE closed_at END,
            closed_by = CASE WHEN quantity <= $7 THEN $9 ELSE closed_by END,
            quantity = CASE WHEN quantity <= $7 THEN quantity ELSE quantity - $7 END
         WHERE company_id = $1 AND reference_type = $2 AND reference_id = $3 AND product_id = $4
           AND location_id = $5 AND lot_id IS NOT DISTINCT FROM $6 AND status = 'active'",
    )
    .bind(m.company_id)
    .bind(reference_type)
    .bind(reference_id)
    .bind(m.product_id)
    .bind(location_id)
    .bind(m.lot_id)
    .bind(quantity)
    .bind(m.id)
    .bind(m.user_id)
    .execute(conn)
    .await?;
    Ok(())
}

/// Quantity reserved for orders at a location and lot.
pub async fn reserved_at(
    conn: &mut PgConnection,
    company_id: Uuid,
    product_id: Uuid,
    location_id: Uuid,
    lot_id: Option<Uuid>,
) -> AppResult<Decimal> {
    Ok(sqlx::query_scalar(
        "SELECT COALESCE(sum(quantity), 0) FROM inventory.reservations
         WHERE company_id = $1 AND product_id = $2 AND location_id = $3 AND lot_id IS NOT DISTINCT FROM $4
           AND status = 'active'",
    )
    .bind(company_id)
    .bind(product_id)
    .bind(location_id)
    .bind(lot_id)
    .fetch_one(conn)
    .await?)
}

/// Keeps `inventory.serial_stock` and the status of the serial unit in step with the move.
async fn move_serial(
    conn: &mut PgConnection,
    m: &NewMove,
    unit: Uuid,
    from_internal: bool,
    to_internal: bool,
    from_label: &str,
) -> AppResult<()> {
    if from_internal {
        let left = sqlx::query(
            "DELETE FROM inventory.serial_stock WHERE serial_unit_id = $1 AND location_id = $2",
        )
        .bind(unit)
        .bind(m.from_location_id)
        .execute(&mut *conn)
        .await?;
        if left.rows_affected() == 0 {
            return Err(AppError::Conflict(format!(
                "the serial unit is not at {from_label}"
            )));
        }
    }
    if to_internal {
        let put = sqlx::query(
            "INSERT INTO inventory.serial_stock (serial_unit_id, company_id, product_id, location_id)
             VALUES ($1, $2, $3, $4) ON CONFLICT (serial_unit_id) DO NOTHING",
        )
        .bind(unit)
        .bind(m.company_id)
        .bind(m.product_id)
        .bind(m.to_location_id)
        .execute(&mut *conn)
        .await?;
        if put.rows_affected() == 0 {
            return Err(AppError::Conflict(
                "the serial unit already has a stock location".into(),
            ));
        }
    }
    match m.serial_effect {
        SerialEffect::None => {}
        SerialEffect::Deliver(customer) => {
            let u = serials::lock_for_stock(conn, m.company_id, unit).await?;
            if customer.or(u.customer_id).is_none() {
                return Err(AppError::Validation(
                    "a customer is required to ship a serial unit".into(),
                ));
            }
            serials::set_status_from_stock(conn, unit, "delivered", customer, false).await?;
        }
        SerialEffect::Scrap => {
            serials::set_status_from_stock(conn, unit, "scrapped", None, false).await?
        }
        SerialEffect::Restore { clear_customer } => {
            serials::set_status_from_stock(conn, unit, "in_stock", None, clear_customer).await?
        }
        SerialEffect::Return => {
            serials::set_status_from_stock(conn, unit, "in_stock", None, true).await?
        }
    }
    Ok(())
}

/// Reverses a move: a new move with the locations swapped. A move can be reversed once and a
/// reversal cannot be reversed. A reversal that would take stock below what is reserved is a 409
/// unless `force` is set (inventory administrators only).
pub async fn reverse_move(
    conn: &mut PgConnection,
    user: &CurrentUser,
    original_id: Uuid,
    new_id: Uuid,
    note: &str,
    force: bool,
) -> AppResult<Posted> {
    if force && !user.can(Permission::InventoryAdmin) {
        return Err(AppError::Forbidden(
            "missing permission inventory.admin".into(),
        ));
    }
    let o = load_move(conn, user.company_id, original_id).await?;
    if o.reference_type.as_deref() == Some("delivery_note") {
        return Err(AppError::Conflict(
            "this move shipped a delivery note; it cannot be reversed on its own, because the delivery \
             and the order would no longer match the stock"
                .into(),
        ));
    }
    if let Some(rev) = o.reversed_of {
        return Err(AppError::Conflict(format!(
            "this move is itself a reversal of {rev}; post a new move instead"
        )));
    }
    if o.reversed_by.is_some_and(|r| r != new_id) {
        return Err(AppError::Conflict("this move was already reversed".into()));
    }
    let kind = KINDS
        .iter()
        .find(|k| **k == o.kind)
        .copied()
        .ok_or_else(|| AppError::Validation("unknown move kind".into()))?;
    let mut m = NewMove::new(
        new_id,
        user,
        o.product_id,
        o.quantity,
        o.to_location_id,
        o.from_location_id,
        kind,
        "reversal",
    );
    m.lot_id = o.lot_id;
    m.serial_unit_id = o.serial_unit_id;
    m.reference = Some(("stock_move".into(), original_id));
    m.reversed_of = Some(original_id);
    m.note = note.to_string();
    m.unit_cost = o.unit_cost;
    m.currency = o.currency.clone();
    m.inherit_cost = true;
    // A reversal that would take reserved stock is refused, unless an inventory administrator
    // forces it (the orders then lack stock).
    m.respect_reservations = !force;
    m.serial_effect = match o.reason.as_str() {
        "shipment" => SerialEffect::Restore {
            clear_customer: true,
        },
        "scrap" => SerialEffect::Restore {
            clear_customer: false,
        },
        _ => SerialEffect::None,
    };
    post_move(conn, &m).await
}

// -------------------------------------------------------------------------------------------
// Units of measure
// -------------------------------------------------------------------------------------------

/// `quantity * numerator / denominator`, rounded to the quantity scale (half away from zero).
pub fn scale_quantity(quantity: Decimal, numerator: Decimal, denominator: Decimal) -> Decimal {
    (quantity * numerator / denominator)
        .round_dp_with_strategy(QUANTITY_SCALE, RoundingStrategy::MidpointAwayFromZero)
}

/// Converts a quantity entered in `uom` to the stock unit of the product.
///
/// * The product's own conversions (`product_uoms`) win.
/// * Otherwise units of the same measurable category (weight, length, area, volume, time) convert
///   through their factors.
/// * Units of the category `unit` (pieces, sets, boxes, every unit that was only ever typed into a
///   product) never convert by themselves: "5 set" on a product kept in pieces is refused unless the
///   product says how many pieces a set is.
///
/// Returns the stock quantity and, when the unit differs, what was entered.
pub async fn to_stock_quantity(
    conn: &mut PgConnection,
    product: &Product,
    quantity: Decimal,
    uom: Option<&str>,
) -> AppResult<(Decimal, Option<(Decimal, String)>)> {
    let uom = match uom.map(str::trim).filter(|u| !u.is_empty()) {
        Some(u) if u != product.unit => u,
        _ => {
            return Ok((quantity, None));
        }
    };
    let own: Option<Decimal> = sqlx::query_scalar(
        "SELECT factor FROM inventory.product_uoms WHERE product_id = $1 AND uom_code = $2",
    )
    .bind(product.id)
    .bind(uom)
    .fetch_optional(&mut *conn)
    .await?;
    let stock = if let Some(f) = own {
        scale_quantity(quantity, f, Decimal::ONE)
    } else {
        #[derive(FromRow)]
        struct U {
            code: String,
            category: String,
            factor: Decimal,
        }
        let rows: Vec<U> = sqlx::query_as(
            "SELECT code, category, factor FROM inventory.uoms WHERE code = ANY($1) AND active",
        )
        .bind(vec![uom.to_string(), product.unit.clone()])
        .fetch_all(&mut *conn)
        .await?;
        let entered = rows.iter().find(|r| r.code == uom);
        let base = rows.iter().find(|r| r.code == product.unit);
        match (entered, base) {
            (Some(e), Some(b)) if e.category == b.category && e.category != "unit" => {
                scale_quantity(quantity, e.factor, b.factor)
            }
            (None, _) => return Err(AppError::Validation(format!("unknown unit {uom}"))),
            _ => {
                return Err(AppError::Validation(format!(
                    "{} is kept in {} and has no conversion from {uom}: add how many {} one {uom} is to the \
                     units of the product",
                    product.code, product.unit, product.unit
                )))
            }
        }
    };
    if stock <= Decimal::ZERO {
        return Err(AppError::Validation(
            "the quantity is too small in the stock unit".into(),
        ));
    }
    Ok((stock, Some((quantity, uom.to_string()))))
}

// -------------------------------------------------------------------------------------------
// Lots
// -------------------------------------------------------------------------------------------

/// Finds the lot by number or creates it. A different expiry date for an existing lot is refused.
pub async fn get_or_create_lot(
    conn: &mut PgConnection,
    company_id: Uuid,
    product_id: Uuid,
    lot_number: &str,
    expiry: Option<NaiveDate>,
) -> AppResult<Uuid> {
    let lot_number = lot_number.trim();
    if lot_number.is_empty() {
        return Err(AppError::Validation("lot_number is required".into()));
    }
    sqlx::query(
        "INSERT INTO inventory.lots (id, company_id, product_id, lot_number, expiry_date)
         VALUES ($1, $2, $3, $4, $5) ON CONFLICT (company_id, product_id, lot_number) DO NOTHING",
    )
    .bind(new_id())
    .bind(company_id)
    .bind(product_id)
    .bind(lot_number)
    .bind(expiry)
    .execute(&mut *conn)
    .await?;
    let (id, current): (Uuid, Option<NaiveDate>) = sqlx::query_as(
        "SELECT id, expiry_date FROM inventory.lots WHERE company_id = $1 AND product_id = $2 AND lot_number = $3",
    )
    .bind(company_id)
    .bind(product_id)
    .bind(lot_number)
    .fetch_one(&mut *conn)
    .await?;
    match (expiry, current) {
        (Some(e), Some(c)) if e != c => Err(AppError::Conflict(format!(
            "lot {lot_number} exists with expiry date {c}"
        ))),
        (Some(e), None) => {
            sqlx::query("UPDATE inventory.lots SET expiry_date = $2 WHERE id = $1")
                .bind(id)
                .bind(e)
                .execute(conn)
                .await?;
            Ok(id)
        }
        _ => Ok(id),
    }
}

// -------------------------------------------------------------------------------------------
// Integrity and rebuild
// -------------------------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct BalanceDifference {
    pub product_id: Uuid,
    pub location_id: Uuid,
    pub lot_id: Option<Uuid>,
    /// Sum of the moves.
    #[schema(value_type = String)]
    pub ledger_quantity: Decimal,
    /// What the balance table holds.
    #[schema(value_type = String)]
    pub balance_quantity: Decimal,
}

const LEDGER_SUMS: &str = "SELECT product_id, location_id, lot_id, sum(q) AS quantity FROM (
        SELECT product_id, to_location_id AS location_id, lot_id, quantity AS q
        FROM inventory.stock_moves WHERE company_id = $1
        UNION ALL
        SELECT product_id, from_location_id, lot_id, -quantity
        FROM inventory.stock_moves WHERE company_id = $1
    ) t GROUP BY product_id, location_id, lot_id";

/// Compares the balance table with the sum of the ledger. Empty when they agree.
pub async fn check_balances(
    conn: &mut PgConnection,
    company_id: Uuid,
) -> AppResult<Vec<BalanceDifference>> {
    Ok(sqlx::query_as(sqlx::AssertSqlSafe(format!(
        "SELECT COALESCE(l.product_id, b.product_id) AS product_id,
                COALESCE(l.location_id, b.location_id) AS location_id,
                COALESCE(l.lot_id, b.lot_id) AS lot_id,
                COALESCE(l.quantity, 0) AS ledger_quantity, COALESCE(b.quantity, 0) AS balance_quantity
         FROM ({LEDGER_SUMS}) l
         FULL OUTER JOIN (SELECT * FROM inventory.stock_balances WHERE company_id = $1) b
           ON b.product_id = l.product_id AND b.location_id = l.location_id AND b.lot_id IS NOT DISTINCT FROM l.lot_id
         WHERE COALESCE(l.quantity, 0) <> COALESCE(b.quantity, 0)"
    )))
    .bind(company_id)
    .fetch_all(conn)
    .await?)
}

/// Recomputes the balance table and the serial locations from the ledger. Returns the number of
/// balance rows.
pub async fn rebuild_balances(conn: &mut PgConnection, company_id: Uuid) -> AppResult<u64> {
    // No move may run between the delete and the insert: every move writes the balances, and this
    // lock conflicts with the row exclusive lock of those writes (and waits for running moves).
    sqlx::query(
        "LOCK TABLE inventory.stock_balances, inventory.serial_stock IN SHARE ROW EXCLUSIVE MODE",
    )
    .execute(&mut *conn)
    .await?;
    sqlx::query("DELETE FROM inventory.stock_balances WHERE company_id = $1")
        .bind(company_id)
        .execute(&mut *conn)
        .await?;
    let rows = sqlx::query(sqlx::AssertSqlSafe(format!(
        "INSERT INTO inventory.stock_balances (company_id, product_id, location_id, lot_id, quantity, allow_negative)
         SELECT $1, s.product_id, s.location_id, s.lot_id, s.quantity, loc.kind <> 'internal'
         FROM ({LEDGER_SUMS}) s JOIN inventory.locations loc ON loc.id = s.location_id"
    )))
    .bind(company_id)
    .execute(&mut *conn)
    .await?;
    sqlx::query("DELETE FROM inventory.serial_stock WHERE company_id = $1")
        .bind(company_id)
        .execute(&mut *conn)
        .await?;
    sqlx::query(
        "INSERT INTO inventory.serial_stock (serial_unit_id, company_id, product_id, location_id)
         SELECT last.serial_unit_id, last.company_id, last.product_id, last.to_location_id FROM (
             SELECT DISTINCT ON (serial_unit_id) serial_unit_id, company_id, product_id, to_location_id
             FROM inventory.stock_moves WHERE company_id = $1 AND serial_unit_id IS NOT NULL
             ORDER BY serial_unit_id, seq DESC
         ) last JOIN inventory.locations l ON l.id = last.to_location_id AND l.kind = 'internal'",
    )
    .bind(company_id)
    .execute(conn)
    .await?;
    Ok(rows.rows_affected())
}

#[cfg(test)]
mod tests {
    use super::*;
    use rust_decimal_macros::dec;

    #[test]
    fn scaling_rounds_half_away_from_zero_to_four_decimals() {
        assert_eq!(scale_quantity(dec!(2), dec!(12), dec!(1)), dec!(24));
        assert_eq!(scale_quantity(dec!(500), dec!(0.001), dec!(1)), dec!(0.5));
        assert_eq!(scale_quantity(dec!(1), dec!(1), dec!(3)), dec!(0.3333));
        assert_eq!(scale_quantity(dec!(2), dec!(1), dec!(3)), dec!(0.6667));
        assert_eq!(
            scale_quantity(dec!(0.00005), dec!(1), dec!(1)),
            dec!(0.0001)
        );
    }
}
