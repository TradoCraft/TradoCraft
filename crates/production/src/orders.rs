//! Production orders: releasing an order (or building for stock), the frozen BOM and its reserved
//! components, planning dates, start, cancel, and the order status that follows (ADR 0036).

use crate::cost::{order_costs, ProductionOrderCost};
use crate::operations::{load_operations, snapshot_routing, ProductionOperation};
use std::collections::HashMap;
use std::future::Future;
use std::pin::Pin;

use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::Json;
use chrono::{DateTime, Datelike, NaiveDate, Utc};
use rust_decimal::{Decimal, RoundingStrategy};
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection};
use tradocraft_core::{
    audit, new_id, numbering, AppError, AppResult, AppState, CurrentUser, Permission,
};
use tradocraft_engineering::bom::active_bom_lines;
use tradocraft_inventory::reservations::{
    free_to_reserve, held_by, line_reservation, release_reference, set_reserved, ReservePin,
    ReserveTarget, PRODUCTION_COMPONENT,
};
use utoipa::{IntoParams, ToSchema};
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

type ErrorBody = tradocraft_core::error::ErrorBody;

/// Order statuses in which a sales order can still be released to production.
const RELEASABLE: [&str; 4] = ["confirmed", "in_planning", "planned", "in_production"];

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct ProductionComponent {
    pub id: Uuid,
    pub position: i32,
    pub component_product_id: Uuid,
    pub component_code: String,
    pub component_name: String,
    pub unit: String,
    /// none | serial | lot
    pub tracking: String,
    #[schema(value_type = String, example = "4")]
    pub required_quantity: Decimal,
    /// What is reserved for it in stock right now.
    #[schema(value_type = String, example = "4")]
    pub reserved_quantity: Decimal,
    #[schema(value_type = String)]
    pub consumed_quantity: Decimal,
    #[schema(value_type = String)]
    pub scrap_quantity: Decimal,
    /// The component is itself built from a BOM: it may need a production order of its own.
    pub manufactured: bool,
    /// Not (fully) reserved while the order is still open: stock is short.
    #[sqlx(skip)]
    pub short: bool,
}

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct ProductionOutput {
    pub id: Uuid,
    #[schema(value_type = String)]
    pub quantity: Decimal,
    pub lot_number: Option<String>,
    pub serial_number: Option<String>,
    pub stock_move_id: Uuid,
}

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct ProductionSummary {
    pub id: Uuid,
    pub number: String,
    pub product_id: Uuid,
    pub product_code: String,
    pub product_name: String,
    pub unit: String,
    /// none | serial | lot: what completion needs for the output.
    pub product_tracking: String,
    #[schema(value_type = String)]
    pub quantity: Decimal,
    pub bom_revision: i32,
    pub division_id: Option<Uuid>,
    pub division_name: Option<String>,
    pub order_id: Option<Uuid>,
    pub order_number: Option<String>,
    pub customer_name: Option<String>,
    /// low | normal | expedite: the priority of the sales order (normal for stock).
    pub priority: String,
    /// The sales order was cancelled meanwhile: the planner should cancel this order too.
    pub order_cancelled: bool,
    /// released | in_progress | completed | cancelled
    pub status: String,
    pub planned_ready_date: Option<NaiveDate>,
    pub short_components: i64,
    /// Operations of the routing that was frozen at release (0 without a routing).
    pub operation_count: i64,
    /// How many of them are finished.
    pub operations_done: i64,
    /// An operation that is not finished is scheduled after the planned-ready date.
    pub behind_schedule: bool,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct ProductionOrder {
    #[serde(flatten)]
    pub summary: ProductionSummary,
    pub order_line_id: Option<Uuid>,
    pub parent_order_id: Option<Uuid>,
    pub started_at: Option<DateTime<Utc>>,
    pub completed_at: Option<DateTime<Utc>>,
    #[schema(value_type = Option<String>)]
    pub completed_quantity: Option<Decimal>,
    pub notes: String,
    pub cancel_reason: Option<String>,
    pub components: Vec<ProductionComponent>,
    pub outputs: Vec<ProductionOutput>,
    pub operations: Vec<ProductionOperation>,
    /// The production orders released for its subassemblies.
    pub sub_orders: Vec<ProductionSubOrder>,
    /// The number of the production order this one is a subassembly of.
    pub parent_order_number: Option<String>,
    /// The internal production remark of the sales order line it builds for (never printed for
    /// the customer).
    pub production_remark: Option<String>,
    /// What the order is planned to cost: components at the standard cost frozen at release and
    /// operations at their planned minutes. Only for users who may see cost.
    pub planned_cost: Option<ProductionOrderCost>,
    /// What it cost so far: the components consumed (booked when the order is completed) and the
    /// minutes of the finished operations. Only for users who may see cost, once it has started
    /// (also when it was cancelled afterwards).
    pub actual_cost: Option<ProductionOrderCost>,
    /// When the last operation that is not finished is scheduled to end: the date to suggest as
    /// the planned-ready date. Empty without open operations.
    pub scheduled_end: Option<NaiveDate>,
}

/// A production order released for a subassembly of another one.
#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct ProductionSubOrder {
    pub id: Uuid,
    pub number: String,
    pub product_id: Uuid,
    pub product_code: String,
    pub product_name: String,
    pub unit: String,
    #[schema(value_type = String)]
    pub quantity: Decimal,
    /// released | in_progress | completed | cancelled
    pub status: String,
    pub planned_ready_date: Option<NaiveDate>,
    /// When its last open operation is scheduled to end.
    pub scheduled_end: Option<NaiveDate>,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct ProductionPage {
    pub items: Vec<ProductionSummary>,
    pub total: i64,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct ReleaseProductionInput {
    /// Release a line of a confirmed sales order (with `order_line_id`), or leave both out to build
    /// for stock (with `product_id` and `quantity`).
    pub order_id: Option<Uuid>,
    pub order_line_id: Option<Uuid>,
    pub product_id: Option<Uuid>,
    /// In the stock unit of the product. For an order line it defaults to what is still to be built.
    #[schema(value_type = Option<String>, example = "5")]
    pub quantity: Option<Decimal>,
    /// Defaults to the division that normally builds the product.
    pub division_id: Option<Uuid>,
    #[serde(default, deserialize_with = "tradocraft_core::serde_util::opt_date")]
    pub planned_ready_date: Option<NaiveDate>,
    /// A subassembly order made for a component of this production order.
    pub parent_order_id: Option<Uuid>,
    /// The first day work can start, for scheduling the operations; defaults to today.
    #[serde(default, deserialize_with = "tradocraft_core::serde_util::opt_date")]
    pub start_date: Option<NaiveDate>,
    /// Also release production orders for the subassemblies that stock does not cover (for the
    /// shortfall), and their subassemblies in turn.
    #[serde(default)]
    pub auto_release_subassemblies: bool,
    #[serde(default)]
    pub notes: String,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct UpdateProductionInput {
    pub division_id: Option<Uuid>,
    #[serde(default, deserialize_with = "tradocraft_core::serde_util::opt_date")]
    pub planned_ready_date: Option<NaiveDate>,
    #[serde(default)]
    pub notes: String,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct CancelProductionInput {
    pub reason: String,
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct ListParams {
    /// released | in_progress | completed | cancelled
    pub status: Option<String>,
    pub division_id: Option<Uuid>,
    /// When true, only orders of the caller's own divisions and orders without a division
    /// (unassigned work is never hidden). Default false: everything.
    #[serde(default)]
    pub mine: bool,
    pub order_id: Option<Uuid>,
    /// Searches the number, the product, the sales order and the customer.
    pub q: Option<String>,
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}

const SELECT_SUMMARY: &str = "SELECT po.id, po.number, po.product_id, p.code AS product_code, p.name AS product_name,
        p.unit, p.tracking AS product_tracking, po.quantity, po.bom_revision, po.division_id, d.name AS division_name, po.order_id,
        o.number AS order_number, o.customer_name, COALESCE(o.priority, 'normal') AS priority,
        COALESCE(o.status = 'cancelled', false) AS order_cancelled, po.status, po.planned_ready_date,
        (SELECT count(*) FROM production.order_components c
          WHERE c.production_order_id = po.id AND po.status IN ('released', 'in_progress')
            AND c.required_quantity > COALESCE((SELECT sum(r.quantity) FROM inventory.reservations r
                 WHERE r.reference_type = 'production_component' AND r.reference_id = c.id
                   AND r.status = 'active'), 0)) AS short_components,
        (SELECT count(*) FROM production.order_operations x
          WHERE x.production_order_id = po.id) AS operation_count,
        (SELECT count(*) FROM production.order_operations x
          WHERE x.production_order_id = po.id AND x.status = 'done') AS operations_done,
        (po.status IN ('released', 'in_progress') AND po.planned_ready_date IS NOT NULL
         AND EXISTS (SELECT 1 FROM production.order_operations x
                     WHERE x.production_order_id = po.id AND x.status IN ('pending', 'in_progress')
                       AND x.planned_end > po.planned_ready_date)) AS behind_schedule,
        po.created_at
     FROM production.production_orders po
     JOIN products.products p ON p.id = po.product_id
     LEFT JOIN production.divisions d ON d.id = po.division_id
     LEFT JOIN sales.orders o ON o.id = po.order_id";

const SELECT_COMPONENTS: &str =
    "SELECT c.id, c.position, c.component_product_id, p.code AS component_code,
        p.name AS component_name, p.unit, p.tracking, c.required_quantity,
        COALESCE((SELECT sum(r.quantity) FROM inventory.reservations r
                  WHERE r.reference_type = 'production_component' AND r.reference_id = c.id
                    AND r.status = 'active'), 0) AS reserved_quantity,
        c.consumed_quantity, c.scrap_quantity,
        EXISTS (SELECT 1 FROM engineering.boms b
                WHERE b.product_id = c.component_product_id AND b.status = 'active') AS manufactured
     FROM production.order_components c
     JOIN products.products p ON p.id = c.component_product_id
     WHERE c.production_order_id = $1
     ORDER BY c.position";

/// The production order row that is being changed, locked until the transaction ends.
#[derive(Debug, FromRow)]
pub(crate) struct Locked {
    pub number: String,
    pub product_id: Uuid,
    pub quantity: Decimal,
    pub bom_id: Uuid,
    pub status: String,
    pub order_id: Option<Uuid>,
    pub division_id: Option<Uuid>,
}

/// Locks a production order of the company until the transaction ends.
pub(crate) async fn lock_order(
    conn: &mut PgConnection,
    company_id: Uuid,
    id: Uuid,
) -> AppResult<Locked> {
    sqlx::query_as(
        "SELECT id, number, product_id, quantity, bom_id, status, order_id, division_id
         FROM production.production_orders WHERE id = $1 AND company_id = $2 FOR UPDATE",
    )
    .bind(id)
    .bind(company_id)
    .fetch_optional(conn)
    .await?
    .ok_or(AppError::NotFound("production order"))
}

/// Loads a production order with its components and outputs.
pub(crate) async fn load_order(
    conn: &mut PgConnection,
    user: &CurrentUser,
    id: Uuid,
) -> AppResult<ProductionOrder> {
    let company_id = user.company_id;
    let summary: ProductionSummary = sqlx::query_as(&format!(
        "{SELECT_SUMMARY} WHERE po.id = $1 AND po.company_id = $2"
    ))
    .bind(id)
    .bind(company_id)
    .fetch_optional(&mut *conn)
    .await?
    .ok_or(AppError::NotFound("production order"))?;
    #[derive(FromRow)]
    struct Extra {
        order_line_id: Option<Uuid>,
        parent_order_id: Option<Uuid>,
        started_at: Option<DateTime<Utc>>,
        completed_at: Option<DateTime<Utc>>,
        completed_quantity: Option<Decimal>,
        notes: String,
        cancel_reason: Option<String>,
    }
    let extra: Extra = sqlx::query_as(
        "SELECT order_line_id, parent_order_id, started_at, completed_at, completed_quantity, notes, cancel_reason
         FROM production.production_orders WHERE id = $1",
    )
    .bind(id)
    .fetch_one(&mut *conn)
    .await?;
    let mut components: Vec<ProductionComponent> = sqlx::query_as(SELECT_COMPONENTS)
        .bind(id)
        .fetch_all(&mut *conn)
        .await?;
    let open = matches!(summary.status.as_str(), "released" | "in_progress");
    for c in &mut components {
        c.short = open && c.reserved_quantity < c.required_quantity;
    }
    let outputs = sqlx::query_as(
        "SELECT o.id, o.quantity, lot.lot_number, su.serial_number, o.stock_move_id
         FROM production.order_outputs o
         LEFT JOIN inventory.lots lot ON lot.id = o.lot_id
         LEFT JOIN engineering.serial_units su ON su.id = o.serial_unit_id
         WHERE o.production_order_id = $1 ORDER BY su.serial_number, o.id",
    )
    .bind(id)
    .fetch_all(&mut *conn)
    .await?;
    let operations = load_operations(conn, user, id).await?;
    let scheduled_end = operations
        .iter()
        .filter(|o| o.is_open())
        .map(|o| o.planned_end)
        .max();
    let sub_orders = sqlx::query_as(
        "SELECT c.id, c.number, c.product_id, p.code AS product_code, p.name AS product_name, p.unit,
                c.quantity, c.status, c.planned_ready_date,
                (SELECT max(x.planned_end) FROM production.order_operations x
                  WHERE x.production_order_id = c.id AND x.status IN ('pending', 'in_progress')) AS scheduled_end
         FROM production.production_orders c JOIN products.products p ON p.id = c.product_id
         WHERE c.parent_order_id = $1 AND c.company_id = $2 ORDER BY c.number",
    )
    .bind(id)
    .bind(company_id)
    .fetch_all(&mut *conn)
    .await?;
    let production_remark: Option<String> = match extra.order_line_id {
        Some(line) => {
            sqlx::query_scalar("SELECT production_remark FROM sales.order_lines WHERE id = $1")
                .bind(line)
                .fetch_optional(&mut *conn)
                .await?
        }
        None => None,
    };
    let parent_order_number: Option<String> =
        match extra.parent_order_id {
            Some(parent) => sqlx::query_scalar(
                "SELECT number FROM production.production_orders WHERE id = $1 AND company_id = $2",
            )
            .bind(parent)
            .bind(company_id)
            .fetch_optional(&mut *conn)
            .await?,
            None => None,
        };
    let (planned_cost, actual_cost) = if user.can(Permission::InventoryCost) {
        let (planned, actual) = order_costs(&mut *conn, id).await?;
        // Work was recorded once the order began, whatever became of it since (an order that is
        // cancelled halfway still cost what was worked).
        (Some(planned), extra.started_at.map(|_| actual))
    } else {
        (None, None)
    };
    Ok(ProductionOrder {
        summary,
        order_line_id: extra.order_line_id,
        parent_order_id: extra.parent_order_id,
        started_at: extra.started_at,
        completed_at: extra.completed_at,
        completed_quantity: extra.completed_quantity,
        notes: extra.notes,
        cancel_reason: extra.cancel_reason,
        components,
        outputs,
        operations,
        sub_orders,
        parent_order_number,
        production_remark,
        planned_cost,
        actual_cost,
        scheduled_end,
    })
}

/// Where an order is in the chain production drives; the order never goes back.
fn rank(status: &str) -> i32 {
    match status {
        "in_planning" => 1,
        "planned" => 2,
        "in_production" => 3,
        "ready_for_shipping" => 4,
        _ => 0,
    }
}

const BY_RANK: [&str; 5] = [
    "confirmed",
    "in_planning",
    "planned",
    "in_production",
    "ready_for_shipping",
];

/// Brings the sales order in line with its production orders (ADR 0036). All of them completed:
/// `ready_for_shipping`; any started or completed: `in_production`; all planned: `planned`;
/// otherwise `in_planning`. The promised date is the latest planned-ready date once every open
/// production order has one. The order only moves forward, and a cancelled or shipped order is left
/// alone.
pub(crate) async fn sync_order_status(
    conn: &mut PgConnection,
    user: &CurrentUser,
    order_id: Uuid,
) -> AppResult<()> {
    let head = tradocraft_sales::orders::lock_for_delivery(conn, user.company_id, order_id).await?;
    if !BY_RANK.contains(&head.status.as_str()) {
        return Ok(());
    }
    let rows: Vec<(String, Option<NaiveDate>)> = sqlx::query_as(
        "SELECT status, planned_ready_date FROM production.production_orders
         WHERE order_id = $1 AND status <> 'cancelled'",
    )
    .bind(order_id)
    .fetch_all(&mut *conn)
    .await?;
    if rows.is_empty() {
        return Ok(());
    }
    let all_completed = rows.iter().all(|(s, _)| s == "completed");
    let any_started = rows.iter().any(|(s, _)| s != "released");
    let all_dated = rows.iter().all(|(_, d)| d.is_some());
    let wanted = if all_completed {
        "ready_for_shipping"
    } else if any_started {
        "in_production"
    } else if all_dated {
        "planned"
    } else {
        "in_planning"
    };
    let target = rank(wanted).max(rank(&head.status));
    let promised = if all_dated {
        rows.iter().filter_map(|(_, d)| *d).max()
    } else {
        None
    };
    tradocraft_sales::orders::set_production_status(
        conn,
        user,
        order_id,
        BY_RANK[target as usize],
        promised,
    )
    .await
}

/// A component needs this much for the whole order: BOM quantity x order quantity x (1 + scrap %),
/// rounded up to four decimals so the order never runs short by rounding.
pub(crate) fn required(per_unit: Decimal, quantity: Decimal, scrap_percent: Decimal) -> Decimal {
    (per_unit * quantity * (Decimal::ONE_HUNDRED + scrap_percent) / Decimal::ONE_HUNDRED)
        .round_dp_with_strategy(4, RoundingStrategy::AwayFromZero)
}

/// Reserves what a component needs, all or nothing. Short stock is not an error: the component
/// stays unreserved and is flagged, and `reserve` tries again later. `claimed` is the free stock
/// that an earlier component of the same release already counts on (see [`release_in_tx`]): it is
/// not taken either, so the component stays unreserved exactly as if stock were short. Without a
/// claim for the product nothing changes (and nothing extra is read).
async fn try_reserve(
    conn: &mut PgConnection,
    user: &CurrentUser,
    component_id: Uuid,
    product_id: Uuid,
    want: Decimal,
    claimed: &HashMap<Uuid, Decimal>,
) -> AppResult<()> {
    let product = tradocraft_products::get_product(&mut *conn, product_id).await?;
    if product.product_type == "service" {
        return Ok(());
    }
    if let Some(taken) = claimed.get(&product_id).filter(|t| **t > Decimal::ZERO) {
        if free_to_reserve(&mut *conn, user.company_id, product_id).await? - *taken < want {
            return Ok(());
        }
    }
    let target = ReserveTarget {
        reference_type: PRODUCTION_COMPONENT,
        reference_id: component_id,
        product_id,
    };
    match set_reserved(conn, user, &target, want, &ReservePin::default()).await {
        Ok(_) | Err(AppError::Conflict(_)) => Ok(()),
        Err(e) => Err(e),
    }
}

/// Checks that a division exists in the company and is active.
pub(crate) async fn check_division(
    conn: &mut PgConnection,
    company_id: Uuid,
    division_id: Uuid,
) -> AppResult<()> {
    let ok: bool = sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM production.divisions WHERE id = $1 AND company_id = $2 AND active)",
    )
    .bind(division_id)
    .bind(company_id)
    .fetch_one(conn)
    .await?;
    if ok {
        Ok(())
    } else {
        Err(AppError::Validation(
            "the division does not exist or is not active".into(),
        ))
    }
}

/// How deep subassemblies are released automatically (an order, its subassemblies, their
/// subassemblies, and so on).
const MAX_SUBASSEMBLY_DEPTH: usize = 5;

/// One production order to release.
struct ReleaseSpec {
    product_id: Uuid,
    quantity: Decimal,
    /// The sales order and its line, or none to build for stock.
    order: Option<(Uuid, Uuid)>,
    order_number: Option<String>,
    division_id: Option<Uuid>,
    planned_ready_date: Option<NaiveDate>,
    parent_order_id: Option<Uuid>,
    start_date: Option<NaiveDate>,
    notes: String,
    auto_release_subassemblies: bool,
}

/// What a release made: the order, and when its work (and that of its subassemblies) is scheduled
/// to end.
struct Released {
    id: Uuid,
    scheduled_end: Option<NaiveDate>,
}

type ReleaseFuture<'a> = Pin<Box<dyn Future<Output = AppResult<Released>> + Send + 'a>>;

/// Releases one production order inside the caller's transaction: freezes the active BOM and its
/// routing, creates the order and its components, reserves them and, when asked, releases a
/// production order for every subassembly that is short, with the same rules and below this
/// order. `ancestors` are the products being built above it; `claimed` is the free stock that
/// earlier components of this release already counted on, so that two components (or branches)
/// that need the same product do not both rely on the same units: neither the shortfall maths
/// nor a later reservation (`try_reserve`) takes it again. A reservation stays all or nothing:
/// a claimed component is not given part of its stock, it is simply left for `reserve`.
fn release_in_tx<'a>(
    tx: &'a mut PgConnection,
    user: &'a CurrentUser,
    spec: ReleaseSpec,
    ancestors: &'a mut Vec<Uuid>,
    claimed: &'a mut HashMap<Uuid, Decimal>,
) -> ReleaseFuture<'a> {
    Box::pin(async move {
        let quantity = spec.quantity;
        if quantity <= Decimal::ZERO || quantity.round_dp(4) != quantity {
            return Err(AppError::Validation(
                "quantity must be more than 0, with at most 4 decimals".into(),
            ));
        }
        let product = tradocraft_products::get_product(&mut *tx, spec.product_id).await?;
        if product.product_type == "service" || product.product_type == "purchased" {
            return Err(AppError::Validation(format!(
                "{} is a {} product and is not built",
                product.code, product.product_type
            )));
        }
        if ancestors.contains(&spec.product_id) {
            return Err(AppError::Validation(format!(
                "{} is part of itself",
                product.code
            )));
        }
        let (bom_id, bom_revision, lines) = active_bom_lines(&mut *tx, spec.product_id)
            .await?
            .ok_or_else(|| {
                AppError::Validation(format!("{} has no active BOM to build from", product.code))
            })?;
        if lines.is_empty() {
            return Err(AppError::Validation(format!(
                "the active BOM of {} has no components",
                product.code
            )));
        }
        let division_id = match spec.division_id {
            Some(d) => Some(d),
            None => {
                sqlx::query_scalar(
                    "SELECT pd.division_id FROM production.product_divisions pd
                     JOIN production.divisions d ON d.id = pd.division_id AND d.active
                     WHERE pd.company_id = $1 AND pd.product_id = $2",
                )
                .bind(user.company_id)
                .bind(spec.product_id)
                .fetch_optional(&mut *tx)
                .await?
            }
        };
        if let Some(d) = spec.division_id {
            check_division(&mut *tx, user.company_id, d).await?;
        }
        if let Some(parent) = spec.parent_order_id {
            lock_order(&mut *tx, user.company_id, parent).await?;
        }
        let year = Utc::now().year();
        let seq = numbering::next_number(&mut *tx, user.company_id, "MO", year).await?;
        let number = format!("MO{year}-{seq:05}");
        let id = new_id();
        sqlx::query(
            "INSERT INTO production.production_orders
                 (id, company_id, number, product_id, quantity, bom_id, bom_revision, division_id, order_id,
                  order_line_id, parent_order_id, planned_ready_date, notes, created_by)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)",
        )
        .bind(id)
        .bind(user.company_id)
        .bind(&number)
        .bind(spec.product_id)
        .bind(quantity)
        .bind(bom_id)
        .bind(bom_revision)
        .bind(division_id)
        .bind(spec.order.map(|o| o.0))
        .bind(spec.order.map(|o| o.1))
        .bind(spec.parent_order_id)
        .bind(spec.planned_ready_date)
        .bind(spec.notes.trim())
        .bind(user.user_id)
        .execute(&mut *tx)
        .await?;
        // Subassemblies that are built from a BOM and that stock could not cover: (product, need).
        let mut short: Vec<(Uuid, Decimal)> = Vec::new();
        for (i, l) in lines.iter().enumerate() {
            let component_id = new_id();
            let need = required(l.quantity, quantity, l.scrap_percent);
            // The standard cost is frozen with the component, like the BOM, so the planned and
            // actual cost of the order do not move when a standard cost is changed later.
            let component =
                tradocraft_products::get_product(&mut *tx, l.component_product_id).await?;
            sqlx::query(
                "INSERT INTO production.order_components
                     (id, production_order_id, position, component_product_id, required_quantity, standard_cost)
                 VALUES ($1, $2, $3, $4, $5, $6)",
            )
            .bind(component_id)
            .bind(id)
            .bind(i as i32 + 1)
            .bind(l.component_product_id)
            .bind(need)
            .bind(component.standard_cost)
            .execute(&mut *tx)
            .await?;
            try_reserve(
                &mut *tx,
                user,
                component_id,
                l.component_product_id,
                need,
                &*claimed,
            )
            .await?;
            if spec.auto_release_subassemblies
                && matches!(
                    component.product_type.as_str(),
                    "manufactured" | "configurable"
                )
            {
                let held = held_by(
                    &mut *tx,
                    user.company_id,
                    &ReserveTarget {
                        reference_type: PRODUCTION_COMPONENT,
                        reference_id: component_id,
                        product_id: l.component_product_id,
                    },
                )
                .await?;
                if held < need
                    && tradocraft_engineering::bom::has_active_bom(&mut *tx, l.component_product_id)
                        .await?
                {
                    // A product the order lists on several rows is one need, built once.
                    match short.iter_mut().find(|(p, _)| *p == l.component_product_id) {
                        Some(row) => row.1 += need,
                        None => short.push((l.component_product_id, need)),
                    }
                }
            }
        }
        // The parent row exists, so the subassemblies can point at it. They are built first: this
        // order's own work starts after the last of them is ready.
        let mut children_end: Option<NaiveDate> = None;
        for (component_product, need) in short {
            if ancestors.len() >= MAX_SUBASSEMBLY_DEPTH {
                return Err(AppError::Validation(format!(
                    "subassemblies are nested more than {MAX_SUBASSEMBLY_DEPTH} levels deep"
                )));
            }
            // A serial-tracked need is always whole (a fraction cannot be reserved, so the release
            // would already have been refused), and so is the free stock: so is the shortfall.
            // Free stock that an earlier component of this release already counted on is not
            // counted again (a reservation is all or nothing, so it is still free in the books).
            let free = free_to_reserve(&mut *tx, user.company_id, component_product).await?;
            let taken = claimed
                .get(&component_product)
                .copied()
                .unwrap_or(Decimal::ZERO);
            let available = (free - taken).max(Decimal::ZERO);
            claimed.insert(component_product, taken + need.min(available));
            let shortfall = need - available;
            if shortfall <= Decimal::ZERO {
                continue;
            }
            ancestors.push(spec.product_id);
            let child = release_in_tx(
                &mut *tx,
                user,
                ReleaseSpec {
                    product_id: component_product,
                    quantity: shortfall,
                    order: None,
                    order_number: None,
                    division_id: None,
                    planned_ready_date: None,
                    parent_order_id: Some(id),
                    start_date: spec.start_date,
                    notes: String::new(),
                    auto_release_subassemblies: true,
                },
                &mut *ancestors,
                &mut *claimed,
            )
            .await?;
            ancestors.pop();
            children_end = children_end.max(child.scheduled_end);
        }
        let own_start = spec.start_date.unwrap_or_else(tradocraft_core::today);
        let start = match children_end {
            Some(end) => own_start.max(end.succ_opt().unwrap_or(end)),
            None => own_start,
        };
        let operations = snapshot_routing(&mut *tx, user, id, bom_id, quantity, start).await?;
        audit::record(
            &mut *tx,
            user,
            "production_order",
            id,
            "released",
            serde_json::json!({
                "number": number, "product": product.code, "quantity": quantity, "bom_revision": bom_revision,
                "order": spec.order_number, "division_id": division_id, "operations": operations,
                "parent_order_id": spec.parent_order_id,
            }),
        )
        .await?;
        let own_end: Option<NaiveDate> = sqlx::query_scalar(
            "SELECT max(planned_end) FROM production.order_operations WHERE production_order_id = $1",
        )
        .bind(id)
        .fetch_one(&mut *tx)
        .await?;
        Ok(Released {
            id,
            scheduled_end: own_end.max(children_end),
        })
    })
}

/// Releases a line of a sales order, or a quantity for stock, to production: freezes the active
/// BOM and its routing, creates the production order and its components and reserves them.
/// With `auto_release_subassemblies`, subassemblies that stock does not cover get production
/// orders of their own for the shortfall.
#[utoipa::path(post, path = "/production-orders", tag = "production", request_body = ReleaseProductionInput,
    responses((status = 201, body = ProductionOrder), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn release(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<ReleaseProductionInput>,
) -> AppResult<(StatusCode, Json<ProductionOrder>)> {
    user.require(Permission::ProductionWrite)?;
    let mut tx = state.db.begin().await?;
    let (product_id, default_quantity, order_number) = match (input.order_id, input.order_line_id) {
        (Some(order_id), Some(line_id)) => {
            let head =
                tradocraft_sales::orders::lock_for_delivery(&mut tx, user.company_id, order_id)
                    .await?;
            if !RELEASABLE.contains(&head.status.as_str()) {
                return Err(AppError::Conflict(format!(
                    "order {} is {}; only a confirmed order can be released to production",
                    head.number, head.status
                )));
            }
            let line = tradocraft_sales::orders::delivery_lines(&mut tx, order_id, head.revision)
                .await?
                .into_iter()
                .find(|l| l.id == line_id)
                .ok_or_else(|| {
                    AppError::Validation("not a line of the confirmed revision of the order".into())
                })?;
            let product_id = line
                .product_id
                .ok_or_else(|| AppError::Validation("the order line has no product".into()))?;
            let ordered = line_reservation(&mut tx, user.company_id, line_id, false)
                .await?
                .ordered;
            let planned: Decimal = sqlx::query_scalar(
                "SELECT COALESCE(sum(quantity), 0) FROM production.production_orders
                 WHERE order_line_id = $1 AND status <> 'cancelled'",
            )
            .bind(line_id)
            .fetch_one(&mut *tx)
            .await?;
            (product_id, Some(ordered - planned), Some(head.number))
        }
        (None, None) => {
            let product_id = input.product_id.ok_or_else(|| {
                AppError::Validation("give an order line, or a product to build for stock".into())
            })?;
            (product_id, None, None)
        }
        _ => {
            return Err(AppError::Validation(
                "order_id and order_line_id go together".into(),
            ))
        }
    };
    let quantity = match (input.quantity, default_quantity) {
        (Some(q), _) => q,
        (None, Some(d)) if d > Decimal::ZERO => d,
        (None, Some(_)) => {
            return Err(AppError::Conflict(
                "production orders already cover this order line".into(),
            ))
        }
        (None, None) => {
            return Err(AppError::Validation(
                "a quantity is needed to build for stock".into(),
            ))
        }
    };
    let released = release_in_tx(
        &mut tx,
        &user,
        ReleaseSpec {
            product_id,
            quantity,
            order: input.order_id.zip(input.order_line_id),
            order_number,
            division_id: input.division_id,
            planned_ready_date: input.planned_ready_date,
            parent_order_id: input.parent_order_id,
            start_date: input.start_date,
            notes: input.notes,
            auto_release_subassemblies: input.auto_release_subassemblies,
        },
        &mut Vec::new(),
        &mut HashMap::new(),
    )
    .await?;
    if let Some(order_id) = input.order_id {
        sync_order_status(&mut tx, &user, order_id).await?;
    }
    let out = load_order(&mut tx, &user, released.id).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(out)))
}

#[derive(Debug, Default, Deserialize, ToSchema)]
pub struct ProductionBuildComponentInput {
    /// Also release the subassemblies of the new production order that are short.
    #[serde(default)]
    pub auto_release_subassemblies: bool,
}

#[derive(FromRow)]
struct BuildComponent {
    component_product_id: Uuid,
}

/// Releases a production order for a component that is built from a BOM and that stock does not
/// cover, below this order: it builds what is still missing. The order may list the same
/// component more than once, so this compares everything the order needs of the product with
/// everything that covers it (reserved, free in stock, already under way in open subassembly
/// orders): one build serves all its rows, and building again for another row finds it covered.
#[utoipa::path(post, path = "/production-orders/{id}/components/{component_id}/build", tag = "production",
    params(("id" = Uuid, Path), ("component_id" = Uuid, Path)), request_body = ProductionBuildComponentInput,
    responses((status = 201, body = ProductionOrder), (status = 404, body = ErrorBody), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn build_component(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((id, component_id)): Path<(Uuid, Uuid)>,
    Json(input): Json<ProductionBuildComponentInput>,
) -> AppResult<(StatusCode, Json<ProductionOrder>)> {
    user.require(Permission::ProductionWrite)?;
    let mut tx = state.db.begin().await?;
    let po = lock_order(&mut tx, user.company_id, id).await?;
    if !matches!(po.status.as_str(), "released" | "in_progress") {
        return Err(AppError::Conflict(format!(
            "production order {} is {}; no subassembly can be built for it",
            po.number, po.status
        )));
    }
    let comp: BuildComponent = sqlx::query_as(
        "SELECT component_product_id FROM production.order_components
         WHERE id = $1 AND production_order_id = $2",
    )
    .bind(component_id)
    .bind(id)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or(AppError::NotFound("component"))?;
    let product = tradocraft_products::get_product(&mut *tx, comp.component_product_id).await?;
    if !matches!(
        product.product_type.as_str(),
        "manufactured" | "configurable"
    ) || !tradocraft_engineering::bom::has_active_bom(&mut tx, comp.component_product_id).await?
    {
        return Err(AppError::Validation(format!(
            "{} is not built from a BOM",
            product.code
        )));
    }
    let rows: Vec<(Uuid, Decimal)> = sqlx::query_as(
        "SELECT id, required_quantity FROM production.order_components
         WHERE production_order_id = $1 AND component_product_id = $2",
    )
    .bind(id)
    .bind(comp.component_product_id)
    .fetch_all(&mut *tx)
    .await?;
    let mut required_total = Decimal::ZERO;
    let mut held = Decimal::ZERO;
    for (row, need) in rows {
        required_total += need;
        held += held_by(
            &mut tx,
            user.company_id,
            &ReserveTarget {
                reference_type: PRODUCTION_COMPONENT,
                reference_id: row,
                product_id: comp.component_product_id,
            },
        )
        .await?;
    }
    let free = free_to_reserve(&mut tx, user.company_id, comp.component_product_id).await?;
    let under_way: Decimal = sqlx::query_scalar(
        "SELECT COALESCE(sum(quantity), 0) FROM production.production_orders
         WHERE company_id = $1 AND parent_order_id = $2 AND product_id = $3
           AND status IN ('released', 'in_progress')",
    )
    .bind(user.company_id)
    .bind(id)
    .bind(comp.component_product_id)
    .fetch_one(&mut *tx)
    .await?;
    let shortfall = required_total - held - free - under_way;
    if shortfall <= Decimal::ZERO {
        return Err(AppError::Conflict(format!(
            "stock and the open production orders already cover {}; reserve the components again",
            product.code
        )));
    }
    let released = release_in_tx(
        &mut tx,
        &user,
        ReleaseSpec {
            product_id: comp.component_product_id,
            quantity: shortfall,
            order: None,
            order_number: None,
            division_id: None,
            planned_ready_date: None,
            parent_order_id: Some(id),
            start_date: None,
            notes: String::new(),
            auto_release_subassemblies: input.auto_release_subassemblies,
        },
        &mut vec![po.product_id],
        &mut HashMap::new(),
    )
    .await?;
    let out = load_order(&mut tx, &user, released.id).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(out)))
}

/// Changes the division, the planned-ready date and the notes of an open production order.
#[utoipa::path(put, path = "/production-orders/{id}", tag = "production", params(("id" = Uuid, Path)),
    request_body = UpdateProductionInput,
    responses((status = 200, body = ProductionOrder), (status = 404, body = ErrorBody), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn update_order(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<UpdateProductionInput>,
) -> AppResult<Json<ProductionOrder>> {
    user.require(Permission::ProductionWrite)?;
    let mut tx = state.db.begin().await?;
    let po = lock_order(&mut tx, user.company_id, id).await?;
    if !matches!(po.status.as_str(), "released" | "in_progress") {
        return Err(AppError::Conflict(format!(
            "production order {} is {} and can no longer be changed",
            po.number, po.status
        )));
    }
    // Keeping the division the order already has is fine even when it was deactivated since.
    if let Some(d) = input.division_id.filter(|d| Some(*d) != po.division_id) {
        check_division(&mut tx, user.company_id, d).await?;
    }
    sqlx::query(
        "UPDATE production.production_orders
         SET division_id = $2, planned_ready_date = $3, notes = $4, updated_at = now() WHERE id = $1",
    )
    .bind(id)
    .bind(input.division_id)
    .bind(input.planned_ready_date)
    .bind(input.notes.trim())
    .execute(&mut *tx)
    .await?;
    audit::record(
        &mut tx,
        &user,
        "production_order",
        id,
        "updated",
        serde_json::json!({
            "number": po.number, "division_id": input.division_id, "planned_ready_date": input.planned_ready_date,
        }),
    )
    .await?;
    if let Some(order_id) = po.order_id {
        sync_order_status(&mut tx, &user, order_id).await?;
    }
    let out = load_order(&mut tx, &user, id).await?;
    tx.commit().await?;
    Ok(Json(out))
}

/// Tries again to reserve the components that were short at release.
#[utoipa::path(post, path = "/production-orders/{id}/reserve", tag = "production", params(("id" = Uuid, Path)),
    responses((status = 200, body = ProductionOrder), (status = 404, body = ErrorBody), (status = 409, body = ErrorBody)))]
async fn reserve_components(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<ProductionOrder>> {
    user.require(Permission::ProductionWrite)?;
    let mut tx = state.db.begin().await?;
    let po = lock_order(&mut tx, user.company_id, id).await?;
    if !matches!(po.status.as_str(), "released" | "in_progress") {
        return Err(AppError::Conflict(format!(
            "production order {} is {}; nothing to reserve",
            po.number, po.status
        )));
    }
    let components: Vec<(Uuid, Uuid, Decimal)> = sqlx::query_as(
        "SELECT id, component_product_id, required_quantity FROM production.order_components
         WHERE production_order_id = $1 ORDER BY component_product_id, position",
    )
    .bind(id)
    .fetch_all(&mut *tx)
    .await?;
    for (component_id, product_id, need) in components {
        let held = held_by(
            &mut tx,
            user.company_id,
            &ReserveTarget {
                reference_type: PRODUCTION_COMPONENT,
                reference_id: component_id,
                product_id,
            },
        )
        .await?;
        if held < need {
            try_reserve(
                &mut tx,
                &user,
                component_id,
                product_id,
                need,
                &HashMap::new(),
            )
            .await?;
        }
    }
    let out = load_order(&mut tx, &user, id).await?;
    tx.commit().await?;
    Ok(Json(out))
}

/// Starts a production order: the order is being built.
#[utoipa::path(post, path = "/production-orders/{id}/start", tag = "production", params(("id" = Uuid, Path)),
    responses((status = 200, body = ProductionOrder), (status = 404, body = ErrorBody), (status = 409, body = ErrorBody)))]
async fn start_order(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<ProductionOrder>> {
    user.require(Permission::ProductionRun)?;
    let mut tx = state.db.begin().await?;
    let po = lock_order(&mut tx, user.company_id, id).await?;
    if po.status != "released" {
        return Err(AppError::Conflict(format!(
            "production order {} is {}; only a released order can be started",
            po.number, po.status
        )));
    }
    begin_order(&mut tx, &user, id, &po).await?;
    let out = load_order(&mut tx, &user, id).await?;
    tx.commit().await?;
    Ok(Json(out))
}

/// Puts a released order in progress and moves the sales order along. Starting the order and
/// starting its first operation do the same.
pub(crate) async fn begin_order(
    conn: &mut PgConnection,
    user: &CurrentUser,
    id: Uuid,
    po: &Locked,
) -> AppResult<()> {
    sqlx::query(
        "UPDATE production.production_orders
         SET status = 'in_progress', started_at = now(), updated_at = now() WHERE id = $1",
    )
    .bind(id)
    .execute(&mut *conn)
    .await?;
    audit::record(
        conn,
        user,
        "production_order",
        id,
        "started",
        serde_json::json!({ "number": po.number }),
    )
    .await?;
    if let Some(order_id) = po.order_id {
        sync_order_status(conn, user, order_id).await?;
    }
    Ok(())
}

/// Cancels an open production order and releases the components reserved for it.
#[utoipa::path(post, path = "/production-orders/{id}/cancel", tag = "production", params(("id" = Uuid, Path)),
    request_body = CancelProductionInput,
    responses((status = 200, body = ProductionOrder), (status = 404, body = ErrorBody), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn cancel_order(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<CancelProductionInput>,
) -> AppResult<Json<ProductionOrder>> {
    user.require(Permission::ProductionWrite)?;
    if input.reason.trim().is_empty() {
        return Err(AppError::Validation("a reason is required".into()));
    }
    let mut tx = state.db.begin().await?;
    let po = lock_order(&mut tx, user.company_id, id).await?;
    if !matches!(po.status.as_str(), "released" | "in_progress") {
        return Err(AppError::Conflict(format!(
            "production order {} is {} and cannot be cancelled",
            po.number, po.status
        )));
    }
    release_components(&mut tx, &user, id).await?;
    sqlx::query(
        "UPDATE production.production_orders
         SET status = 'cancelled', cancel_reason = $2, updated_at = now() WHERE id = $1",
    )
    .bind(id)
    .bind(input.reason.trim())
    .execute(&mut *tx)
    .await?;
    audit::record(
        &mut tx,
        &user,
        "production_order",
        id,
        "cancelled",
        serde_json::json!({ "number": po.number, "reason": input.reason.trim() }),
    )
    .await?;
    if let Some(order_id) = po.order_id {
        sync_order_status(&mut tx, &user, order_id).await?;
    }
    let out = load_order(&mut tx, &user, id).await?;
    tx.commit().await?;
    Ok(Json(out))
}

/// Releases every reservation held for the components of a production order.
pub(crate) async fn release_components(
    conn: &mut PgConnection,
    user: &CurrentUser,
    production_order_id: Uuid,
) -> AppResult<()> {
    let ids: Vec<Uuid> = sqlx::query_scalar(
        "SELECT id FROM production.order_components WHERE production_order_id = $1",
    )
    .bind(production_order_id)
    .fetch_all(&mut *conn)
    .await?;
    for component_id in ids {
        release_reference(
            conn,
            user.company_id,
            PRODUCTION_COMPONENT,
            component_id,
            Some(user.user_id),
        )
        .await?;
    }
    Ok(())
}

/// One production order with its components and outputs.
#[utoipa::path(get, path = "/production-orders/{id}", tag = "production", params(("id" = Uuid, Path)),
    responses((status = 200, body = ProductionOrder), (status = 404, body = ErrorBody)))]
async fn get_order(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<ProductionOrder>> {
    user.require(Permission::ProductionRead)?;
    let mut conn = state.db.acquire().await?;
    Ok(Json(load_order(&mut conn, &user, id).await?))
}

/// The production queue: most urgent first (sales order priority, then planned-ready date).
#[utoipa::path(get, path = "/production-orders", tag = "production", params(ListParams),
    responses((status = 200, body = ProductionPage)))]
async fn list_orders(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(p): Query<ListParams>,
) -> AppResult<Json<ProductionPage>> {
    user.require(Permission::ProductionRead)?;
    if let Some(s) = &p.status {
        if !matches!(
            s.as_str(),
            "released" | "in_progress" | "completed" | "cancelled"
        ) {
            return Err(AppError::Validation(
                "status must be released, in_progress, completed or cancelled".into(),
            ));
        }
    }
    let filter = "po.company_id = $1
         AND ($2::text IS NULL OR po.status = $2)
         AND ($3::uuid IS NULL OR po.division_id = $3)
         AND ($4::uuid IS NULL OR po.order_id = $4)
         AND (NOT $6::bool OR po.division_id IS NULL OR po.division_id IN
              (SELECT m.division_id FROM production.division_members m WHERE m.user_id = $7))
         AND ($5::text IS NULL OR po.number ILIKE $5 OR p.code ILIKE $5 OR p.name ILIKE $5
              OR o.number ILIKE $5 OR o.customer_name ILIKE $5)";
    let q =
        p.q.as_deref()
            .map(str::trim)
            .filter(|q| !q.is_empty())
            .map(|q| format!("%{q}%"));
    let items: Vec<ProductionSummary> = sqlx::query_as(&format!(
        "{SELECT_SUMMARY} WHERE {filter}
         ORDER BY (po.status IN ('completed', 'cancelled')),
                  CASE COALESCE(o.priority, 'normal') WHEN 'expedite' THEN 0 WHEN 'normal' THEN 1 ELSE 2 END,
                  po.planned_ready_date NULLS LAST, po.number
         LIMIT $8 OFFSET $9"
    ))
    .bind(user.company_id)
    .bind(&p.status)
    .bind(p.division_id)
    .bind(p.order_id)
    .bind(&q)
    .bind(p.mine)
    .bind(user.user_id)
    .bind(p.limit.unwrap_or(50).clamp(1, 200))
    .bind(p.offset.unwrap_or(0).max(0))
    .fetch_all(&state.db)
    .await?;
    let total: i64 = sqlx::query_scalar(&format!(
        "SELECT count(*) FROM production.production_orders po
         JOIN products.products p ON p.id = po.product_id
         LEFT JOIN sales.orders o ON o.id = po.order_id
         WHERE {filter}"
    ))
    .bind(user.company_id)
    .bind(&p.status)
    .bind(p.division_id)
    .bind(p.order_id)
    .bind(&q)
    .bind(p.mine)
    .bind(user.user_id)
    .fetch_one(&state.db)
    .await?;
    Ok(Json(ProductionPage { items, total }))
}

#[derive(Debug, Serialize, ToSchema)]
pub struct ProductionToRelease {
    pub order_id: Uuid,
    pub order_number: String,
    pub customer_name: String,
    /// low | normal | expedite
    pub priority: String,
    pub order_line_id: Uuid,
    pub product_id: Uuid,
    pub product_code: String,
    pub product_name: String,
    /// Ordered, in the stock unit.
    #[schema(value_type = String)]
    pub ordered: Decimal,
    /// What production orders already cover.
    #[schema(value_type = String)]
    pub planned: Decimal,
    /// Still to be released: ordered minus planned.
    #[schema(value_type = String)]
    pub to_build: Decimal,
}

/// Lines of confirmed orders that are built from a BOM and not yet fully covered by production
/// orders: what a planner can release. Most urgent orders first.
#[utoipa::path(get, path = "/production/to-release", tag = "production",
    responses((status = 200, body = Vec<ProductionToRelease>)))]
async fn to_release(
    State(state): State<AppState>,
    user: CurrentUser,
) -> AppResult<Json<Vec<ProductionToRelease>>> {
    user.require(Permission::ProductionRead)?;
    let mut conn = state.db.acquire().await?;
    #[derive(FromRow)]
    struct OrderRow {
        id: Uuid,
        number: String,
        customer_name: String,
        priority: String,
    }
    let orders: Vec<OrderRow> = sqlx::query_as(
        "SELECT id, number, customer_name, priority FROM sales.orders
         WHERE company_id = $1 AND status = ANY($2)
         ORDER BY CASE priority WHEN 'expedite' THEN 0 WHEN 'normal' THEN 1 ELSE 2 END, order_date, number
         LIMIT 200",
    )
    .bind(user.company_id)
    .bind(RELEASABLE.iter().map(|s| s.to_string()).collect::<Vec<_>>())
    .fetch_all(&mut *conn)
    .await?;
    let mut out = Vec::new();
    for o in orders {
        // A read: no row lock needed.
        let head =
            tradocraft_sales::orders::delivery_head(&mut conn, user.company_id, o.id).await?;
        for line in tradocraft_sales::orders::delivery_lines(&mut conn, o.id, head.revision).await?
        {
            let Some(product_id) = line.product_id else {
                continue;
            };
            let product = tradocraft_products::get_product(&mut *conn, product_id).await?;
            if !matches!(
                product.product_type.as_str(),
                "manufactured" | "configurable"
            ) {
                continue;
            }
            if !tradocraft_engineering::bom::has_active_bom(&mut conn, product_id).await? {
                continue;
            }
            let ordered = line_reservation(&mut conn, user.company_id, line.id, false)
                .await?
                .ordered;
            let planned: Decimal = sqlx::query_scalar(
                "SELECT COALESCE(sum(quantity), 0) FROM production.production_orders
                 WHERE order_line_id = $1 AND status <> 'cancelled'",
            )
            .bind(line.id)
            .fetch_one(&mut *conn)
            .await?;
            if ordered > planned {
                out.push(ProductionToRelease {
                    order_id: o.id,
                    order_number: o.number.clone(),
                    customer_name: o.customer_name.clone(),
                    priority: o.priority.clone(),
                    order_line_id: line.id,
                    product_id,
                    product_code: product.code,
                    product_name: product.name,
                    ordered,
                    planned,
                    to_build: ordered - planned,
                });
            }
        }
    }
    Ok(Json(out))
}

/// The production order routes.
pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(list_orders, release))
        .routes(routes!(get_order, update_order))
        .routes(routes!(reserve_components))
        .routes(routes!(build_component))
        .routes(routes!(start_order))
        .routes(routes!(cancel_order))
        .routes(routes!(to_release))
}
