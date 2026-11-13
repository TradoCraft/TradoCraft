//! Cost of what production builds (ADR 0060). Two views, both only for users who may see cost
//! (`inventory.cost`; production planners may not):
//!
//! * the **roll-up** of a product: its BOM and routing walked through every level, material at the
//!   standard cost of what is bought and labour at the work centres' cost per hour;
//! * the **planned and actual cost of a production order**, from the standard costs frozen on its
//!   components and the rates frozen on its operations, so that later changes to either do not
//!   rewrite an order.
//!
//! The ledger still books output at the product's standard cost: valuation at actual cost and
//! work in progress are later work.

use std::future::Future;
use std::pin::Pin;

use axum::extract::{Path, Query, State};
use axum::Json;
use rust_decimal::{Decimal, RoundingStrategy};
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection};
use tradocraft_core::{AppError, AppResult, AppState, CurrentUser, Permission};
use tradocraft_engineering::bom::{active_bom_lines, has_active_bom};
use utoipa::{IntoParams, ToSchema};
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::operations::planned_minutes;
use crate::orders::required;
use crate::routing::load_routing;

type ErrorBody = tradocraft_core::error::ErrorBody;

/// How many levels of subassemblies the roll-up walks before it gives up (a BOM cannot contain
/// itself, so this only guards against a broken structure).
const MAX_LEVELS: i32 = 20;

/// How many built products (the product and every subassembly, each time it is met) one roll-up
/// may visit. A subassembly used several times at several levels is walked once per use, so a
/// structure that doubles at every level would otherwise cost the server exponential work.
const MAX_VISITS: usize = 1000;

fn money(d: Decimal) -> Decimal {
    d.round_dp_with_strategy(4, RoundingStrategy::MidpointAwayFromZero)
}

/// Cost of a production order, in the company currency.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct ProductionOrderCost {
    /// Components at the standard cost they had when the order was released.
    #[schema(value_type = String, example = "83.74")]
    pub material_cost: Decimal,
    /// Operation minutes at the cost per hour the operations had.
    #[schema(value_type = String, example = "80")]
    pub labour_cost: Decimal,
    #[schema(value_type = String, example = "163.74")]
    pub total_cost: Decimal,
    /// A component had no standard cost or an operation no rate: its cost is left out.
    pub incomplete: bool,
}

#[derive(FromRow)]
struct MaterialRow {
    planned: Decimal,
    actual: Decimal,
    missing: Option<bool>,
}

#[derive(FromRow)]
struct LabourRow {
    planned: Decimal,
    actual: Decimal,
    missing: Option<bool>,
}

/// The planned and the actual cost of a production order. Planned: every component at its
/// required quantity and every operation at its planned minutes. Actual: what was consumed and
/// scrapped (booked when the order is completed) and the minutes recorded on finished operations.
pub(crate) async fn order_costs(
    conn: &mut PgConnection,
    production_order_id: Uuid,
) -> AppResult<(ProductionOrderCost, ProductionOrderCost)> {
    let m: MaterialRow = sqlx::query_as(
        "SELECT COALESCE(sum(required_quantity * standard_cost), 0) AS planned,
                COALESCE(sum((consumed_quantity + scrap_quantity) * standard_cost), 0) AS actual,
                bool_or(standard_cost IS NULL) AS missing
         FROM production.order_components WHERE production_order_id = $1",
    )
    .bind(production_order_id)
    .fetch_one(&mut *conn)
    .await?;
    let l: LabourRow = sqlx::query_as(
        "SELECT COALESCE(sum(planned_minutes::numeric / 60 * cost_rate), 0) AS planned,
                COALESCE(sum(actual_minutes::numeric / 60 * cost_rate) FILTER (WHERE status = 'done'), 0) AS actual,
                bool_or(cost_rate IS NULL) FILTER (WHERE planned_minutes > 0) AS missing
         FROM production.order_operations WHERE production_order_id = $1",
    )
    .bind(production_order_id)
    .fetch_one(conn)
    .await?;
    let cost = |material: Decimal, labour: Decimal| ProductionOrderCost {
        material_cost: money(material),
        labour_cost: money(labour),
        total_cost: money(material) + money(labour),
        incomplete: m.missing.unwrap_or(false) || l.missing.unwrap_or(false),
    };
    Ok((cost(m.planned, l.planned), cost(m.actual, l.actual)))
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct CostRollupParams {
    /// How many to cost; default 1. The setup time of each operation is counted once.
    #[param(value_type = Option<String>, example = "10")]
    pub quantity: Option<Decimal>,
}

/// One built product in the roll-up: the product itself and each subassembly below it.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct ProductionCostLevel {
    /// 0 for the product asked for, 1 for its subassemblies, and so on.
    pub level: i32,
    pub product_id: Uuid,
    pub product_code: String,
    pub product_name: String,
    pub unit: String,
    /// How many of it are built.
    #[schema(value_type = String)]
    pub quantity: Decimal,
    /// Components that are bought, at their standard cost (subassemblies are costed on their own
    /// level).
    #[schema(value_type = String)]
    pub material_cost: Decimal,
    /// Its own routing: operation minutes at the work centres' cost per hour.
    #[schema(value_type = String)]
    pub labour_cost: Decimal,
    /// Minutes of its own routing for this quantity.
    pub minutes: i64,
}

/// Something that could not be costed and was left out.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, ToSchema)]
pub struct ProductionCostGap {
    /// standard_cost: a product without a standard cost; cost_per_hour: a work centre without one.
    pub kind: String,
    /// The product or work centre code.
    pub code: String,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct ProductionCostRollup {
    pub product_id: Uuid,
    pub product_code: String,
    pub product_name: String,
    pub unit: String,
    #[schema(value_type = String)]
    pub quantity: Decimal,
    /// The company currency.
    pub currency: String,
    #[schema(value_type = String)]
    pub material_cost: Decimal,
    #[schema(value_type = String)]
    pub labour_cost: Decimal,
    #[schema(value_type = String)]
    pub total_cost: Decimal,
    /// Total cost for one unit of the product.
    #[schema(value_type = String)]
    pub unit_cost: Decimal,
    /// The product and each subassembly, in the order they are met.
    pub levels: Vec<ProductionCostLevel>,
    /// What was left out because it has no cost.
    pub gaps: Vec<ProductionCostGap>,
}

#[derive(Default)]
struct Rollup {
    levels: Vec<ProductionCostLevel>,
    gaps: Vec<ProductionCostGap>,
}

impl Rollup {
    /// Counts a visit and refuses the roll-up when the structure is too large to walk.
    fn visit(&self) -> AppResult<()> {
        if self.levels.len() >= MAX_VISITS {
            return Err(AppError::Validation(format!(
                "the structure has more than {MAX_VISITS} built products (a subassembly counts each time it is used); cost it in parts"
            )));
        }
        Ok(())
    }
}

impl Rollup {
    fn gap(&mut self, kind: &str, code: &str) {
        let gap = ProductionCostGap {
            kind: kind.into(),
            code: code.into(),
        };
        if !self.gaps.contains(&gap) {
            self.gaps.push(gap);
        }
    }
}

type RollupFuture<'a> = Pin<Box<dyn Future<Output = AppResult<()>> + Send + 'a>>;

/// Costs `quantity` of a product that has an active BOM, then each subassembly below it.
fn rollup_level<'a>(
    conn: &'a mut PgConnection,
    company_id: Uuid,
    product_id: Uuid,
    quantity: Decimal,
    level: i32,
    out: &'a mut Rollup,
) -> RollupFuture<'a> {
    Box::pin(async move {
        if level > MAX_LEVELS {
            return Err(AppError::Validation(format!(
                "the structure is more than {MAX_LEVELS} levels deep"
            )));
        }
        out.visit()?;
        let product = tradocraft_products::get_product(&mut *conn, product_id).await?;
        let (bom_id, _, lines) =
            active_bom_lines(&mut *conn, product_id)
                .await?
                .ok_or_else(|| {
                    AppError::Validation(format!("{} has no active BOM to cost", product.code))
                })?;
        let slot = out.levels.len();
        out.levels.push(ProductionCostLevel {
            level,
            product_id,
            product_code: product.code.clone(),
            product_name: product.name.clone(),
            unit: product.unit.clone(),
            quantity,
            material_cost: Decimal::ZERO,
            labour_cost: Decimal::ZERO,
            minutes: 0,
        });
        let mut material = Decimal::ZERO;
        for l in &lines {
            let need = required(l.quantity, quantity, l.scrap_percent);
            let component =
                tradocraft_products::get_product(&mut *conn, l.component_product_id).await?;
            let built = matches!(
                component.product_type.as_str(),
                "manufactured" | "configurable"
            ) && has_active_bom(&mut *conn, l.component_product_id).await?;
            if built {
                rollup_level(
                    &mut *conn,
                    company_id,
                    l.component_product_id,
                    need,
                    level + 1,
                    out,
                )
                .await?;
            } else {
                match component.standard_cost {
                    Some(cost) => material += need * cost,
                    None => out.gap("standard_cost", &component.code),
                }
            }
        }
        let mut labour = Decimal::ZERO;
        let mut minutes = 0_i64;
        for op in load_routing(&mut *conn, company_id, bom_id).await? {
            let m = planned_minutes(op.setup_minutes, op.run_minutes_per_unit, quantity)
                .ok_or_else(|| {
                    AppError::Validation(format!(
                        "operation \"{}\" of {} takes too long for this quantity",
                        op.name, product.code
                    ))
                })?;
            minutes += i64::from(m);
            let rate: Option<Decimal> = sqlx::query_scalar(
                "SELECT cost_per_hour FROM production.work_centres WHERE id = $1 AND company_id = $2",
            )
            .bind(op.work_centre_id)
            .bind(company_id)
            .fetch_one(&mut *conn)
            .await?;
            match rate {
                Some(rate) => labour += Decimal::from(m) / Decimal::from(60) * rate,
                None => out.gap("cost_per_hour", &op.work_centre_code),
            }
        }
        out.levels[slot].material_cost = money(material);
        out.levels[slot].labour_cost = money(labour);
        out.levels[slot].minutes = minutes;
        Ok(())
    })
}

/// The cost of building a quantity of a product from its active BOM and routing, through every
/// level of subassemblies (a subassembly is costed from its own BOM and routing, not from its
/// standard cost). Material uses standard costs, labour the work centres' cost per hour as they
/// are now.
#[utoipa::path(get, path = "/production/products/{id}/cost-rollup", tag = "production",
    params(("id" = Uuid, Path), CostRollupParams),
    responses((status = 200, body = ProductionCostRollup), (status = 403, body = ErrorBody), (status = 404, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn production_cost_rollup(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(product_id): Path<Uuid>,
    Query(p): Query<CostRollupParams>,
) -> AppResult<Json<ProductionCostRollup>> {
    // Cost belongs to inventory.cost (Products module); production.read keeps it off where the
    // Production module is off.
    user.require(Permission::InventoryCost)?;
    user.require(Permission::ProductionRead)?;
    let quantity = p.quantity.unwrap_or(Decimal::ONE);
    if quantity <= Decimal::ZERO || quantity.round_dp(4) != quantity {
        return Err(AppError::Validation(
            "quantity must be more than 0, with at most 4 decimals".into(),
        ));
    }
    let mut conn = state.db.acquire().await?;
    let product = tradocraft_products::get_product(&mut *conn, product_id).await?;
    let mut out = Rollup::default();
    rollup_level(
        &mut conn,
        user.company_id,
        product_id,
        quantity,
        0,
        &mut out,
    )
    .await?;
    let currency: String = sqlx::query_scalar("SELECT currency FROM core.companies WHERE id = $1")
        .bind(user.company_id)
        .fetch_one(&mut *conn)
        .await?;
    let material: Decimal = out.levels.iter().map(|l| l.material_cost).sum();
    let labour: Decimal = out.levels.iter().map(|l| l.labour_cost).sum();
    let total = material + labour;
    Ok(Json(ProductionCostRollup {
        product_id,
        product_code: product.code,
        product_name: product.name,
        unit: product.unit,
        quantity,
        currency,
        material_cost: material,
        labour_cost: labour,
        total_cost: total,
        unit_cost: money(total / quantity),
        levels: out.levels,
        gaps: out.gaps,
    }))
}

/// The cost routes.
pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new().routes(routes!(production_cost_rollup))
}
