//! A planning run: loads what is needed and what is there, plans it with [`crate::engine`] and
//! keeps the proposals (ADR 0091). One transaction: a run that fails leaves the open proposals as
//! they were.

use std::collections::{BTreeSet, HashMap, HashSet};

use chrono::{Datelike, Days, NaiveDate};
use rust_decimal::Decimal;
use sqlx::{FromRow, PgConnection};
use tradocraft_core::{audit, new_id, numbering, AppError, AppResult, CurrentUser};
use uuid::Uuid;

use crate::engine::{
    plan, BomCycle, BomUse, Flow, Item, Peg, PegKind, Proposal, ProposalKind, Reason, Settings,
    Supply,
};

/// The longest horizon of a run.
pub const MAX_HORIZON_DAYS: i32 = 730;
/// The horizon when none is asked for.
pub const DEFAULT_HORIZON_DAYS: i32 = 90;

/// What a run made.
#[derive(Debug, Clone)]
pub struct RunOutcome {
    pub id: Uuid,
    pub number: String,
    pub planned_on: NaiveDate,
    pub horizon_days: i32,
    pub proposals: usize,
}

#[derive(FromRow)]
struct OrderDemand {
    order_id: Uuid,
    number: String,
    product_id: Uuid,
    due: NaiveDate,
    open_qty: Decimal,
}

#[derive(FromRow)]
struct PoReceipt {
    id: Uuid,
    number: String,
    product_id: Uuid,
    due: Option<NaiveDate>,
    open_qty: Decimal,
}

#[derive(FromRow)]
struct OpenBuild {
    id: Uuid,
    number: String,
    product_id: Uuid,
    quantity: Decimal,
    ready: Option<NaiveDate>,
}

#[derive(FromRow)]
struct BuildComponent {
    id: Uuid,
    number: String,
    product_id: Uuid,
    remaining: Decimal,
}

#[derive(FromRow)]
struct ProductInfo {
    id: Uuid,
    code: String,
    product_type: String,
    lead_time_days: Option<i32>,
    reorder_min: Option<Decimal>,
    reorder_max: Option<Decimal>,
    safety_stock: Option<Decimal>,
    order_multiple: Option<Decimal>,
}

fn peg(kind: PegKind, id: Uuid, number: &str, quantity: Decimal) -> Peg {
    Peg {
        kind,
        id: Some(id),
        number: number.to_string(),
        quantity,
    }
}

/// Runs the planning and keeps its proposals. The open proposals of earlier runs are replaced
/// (marked `superseded`); the converted and dismissed ones stay as they were.
pub async fn run(
    conn: &mut PgConnection,
    user: &CurrentUser,
    horizon_days: i32,
) -> AppResult<RunOutcome> {
    if !(1..=MAX_HORIZON_DAYS).contains(&horizon_days) {
        return Err(AppError::Validation(format!(
            "the horizon must be between 1 and {MAX_HORIZON_DAYS} days"
        )));
    }
    let company = user.company_id;
    let today = tradocraft_core::today();
    let horizon_end = today
        .checked_add_days(Days::new(horizon_days as u64))
        .unwrap_or(today);

    // What customers still wait for: the lines of the confirmed revision of an order that is
    // being worked on, less what has shipped, due on the promised date or else the order date.
    let demand: Vec<OrderDemand> = sqlx::query_as(
        "SELECT o.id AS order_id, o.number, l.product_id,
                COALESCE(o.promised_date, o.order_date) AS due,
                l.quantity - COALESCE(sh.q, 0) AS open_qty
         FROM sales.orders o
         JOIN sales.order_lines l
           ON l.order_id = o.id AND l.revision = COALESCE(o.confirmed_revision, o.current_revision)
         LEFT JOIN (
             SELECT dl.order_line_id, sum(dl.quantity) AS q
             FROM delivery.delivery_note_lines dl
             JOIN delivery.delivery_notes n ON n.id = dl.delivery_note_id AND n.status = 'shipped'
             GROUP BY dl.order_line_id
         ) sh ON sh.order_line_id = l.id
         WHERE o.company_id = $1 AND l.product_id IS NOT NULL
           AND o.status IN ('confirmed', 'in_planning', 'planned', 'in_production',
                            'ready_for_shipping', 'partially_shipped')
           AND l.quantity - COALESCE(sh.q, 0) > 0",
    )
    .bind(company)
    .fetch_all(&mut *conn)
    .await?;
    // What suppliers still owe.
    let receipts: Vec<PoReceipt> = sqlx::query_as(
        "SELECT po.id, po.number, l.product_id, po.expected_delivery_date AS due,
                l.quantity - l.quantity_received AS open_qty
         FROM purchasing.purchase_orders po
         JOIN purchasing.purchase_order_lines l ON l.purchase_order_id = po.id
         WHERE po.company_id = $1 AND po.status IN ('approved', 'sent', 'partially_received')
           AND l.quantity - l.quantity_received > 0",
    )
    .bind(company)
    .fetch_all(&mut *conn)
    .await?;
    // What is being built, and what it still takes from stock.
    let builds: Vec<OpenBuild> = sqlx::query_as(
        "SELECT id, number, product_id, quantity, planned_ready_date AS ready
         FROM production.production_orders
         WHERE company_id = $1 AND status IN ('released', 'in_progress')",
    )
    .bind(company)
    .fetch_all(&mut *conn)
    .await?;
    let components: Vec<BuildComponent> = sqlx::query_as(
        "SELECT po.id, po.number, c.component_product_id AS product_id,
                c.required_quantity - c.consumed_quantity AS remaining
         FROM production.order_components c
         JOIN production.production_orders po ON po.id = c.production_order_id
         WHERE po.company_id = $1 AND po.status IN ('released', 'in_progress')
           AND c.required_quantity - c.consumed_quantity > 0",
    )
    .bind(company)
    .fetch_all(&mut *conn)
    .await?;

    let mut requirements: HashMap<Uuid, Vec<Flow>> = HashMap::new();
    let mut incoming: HashMap<Uuid, Vec<Flow>> = HashMap::new();
    for d in &demand {
        requirements.entry(d.product_id).or_default().push(Flow {
            date: d.due,
            quantity: d.open_qty,
            peg: peg(PegKind::SalesOrder, d.order_id, &d.number, d.open_qty),
        });
    }
    for r in &receipts {
        incoming.entry(r.product_id).or_default().push(Flow {
            date: r.due.unwrap_or(today),
            quantity: r.open_qty,
            peg: peg(PegKind::PurchaseOrder, r.id, &r.number, r.open_qty),
        });
    }
    for b in &builds {
        incoming.entry(b.product_id).or_default().push(Flow {
            date: b.ready.unwrap_or(today),
            quantity: b.quantity,
            peg: peg(PegKind::ProductionOrder, b.id, &b.number, b.quantity),
        });
    }
    for c in &components {
        // Reserved at release, but still in the warehouse until it is used.
        requirements.entry(c.product_id).or_default().push(Flow {
            date: today,
            quantity: c.remaining,
            peg: peg(PegKind::ProductionOrder, c.id, &c.number, c.remaining),
        });
    }

    // The products to plan: everything with a requirement or a supply, everything that keeps a
    // stock level, and (below) whatever the built ones are made of.
    let mut queue: Vec<Uuid> = requirements
        .keys()
        .chain(incoming.keys())
        .copied()
        .collect::<BTreeSet<_>>()
        .into_iter()
        .collect();
    let kept: Vec<Uuid> = sqlx::query_scalar(
        "SELECT id FROM products.products
         WHERE active AND product_type <> 'service'
           AND (COALESCE(safety_stock, 0) > 0 OR COALESCE(reorder_min, 0) > 0)",
    )
    .fetch_all(&mut *conn)
    .await?;
    queue.extend(kept);
    let mut seen: HashSet<Uuid> = HashSet::new();
    let mut infos: Vec<(ProductInfo, Option<Vec<BomUse>>)> = Vec::new();
    while let Some(pid) = queue.pop() {
        if !seen.insert(pid) {
            continue;
        }
        let Some(info): Option<ProductInfo> = sqlx::query_as(
            "SELECT id, code, product_type, lead_time_days, reorder_min, reorder_max,
                    safety_stock, order_multiple
             FROM products.products WHERE id = $1",
        )
        .bind(pid)
        .fetch_optional(&mut *conn)
        .await?
        else {
            continue;
        };
        if info.product_type == "service" {
            continue;
        }
        let built = matches!(info.product_type.as_str(), "manufactured" | "configurable");
        let bom = if built {
            tradocraft_engineering::bom::active_bom_lines(&mut *conn, pid)
                .await?
                .map(|(_, _, lines)| lines)
                .filter(|l| !l.is_empty())
        } else {
            None
        };
        let uses = bom.map(|lines| {
            lines
                .into_iter()
                .map(|l| {
                    queue.push(l.component_product_id);
                    BomUse {
                        component: l.component_product_id,
                        quantity: l.quantity,
                        scrap_percent: l.scrap_percent,
                    }
                })
                .collect::<Vec<_>>()
        });
        infos.push((info, uses));
    }

    // Stock in the normal warehouses (reserved stock included: what is reserved is a requirement).
    let ids: Vec<Uuid> = infos.iter().map(|(i, _)| i.id).collect();
    let stock: Vec<(Uuid, Decimal)> = sqlx::query_as(
        "SELECT b.product_id, COALESCE(sum(b.quantity), 0)
         FROM inventory.stock_balances b
         JOIN inventory.locations l ON l.id = b.location_id AND l.kind = 'internal' AND l.active
         JOIN inventory.warehouses w ON w.id = l.warehouse_id AND w.active AND w.kind = 'warehouse'
         WHERE b.company_id = $1 AND b.product_id = ANY($2)
         GROUP BY b.product_id",
    )
    .bind(company)
    .bind(&ids)
    .fetch_all(&mut *conn)
    .await?;
    let on_hand: HashMap<Uuid, Decimal> = stock.into_iter().collect();

    let mut items: Vec<Item> = Vec::with_capacity(infos.len());
    for (info, uses) in infos {
        let (supply, lead) = match uses {
            Some(_) => (Supply::Make, info.lead_time_days.unwrap_or(0)),
            None => {
                let preferred =
                    tradocraft_purchasing::supplier_products::get_preferred_supplier_for_product(
                        &mut *conn, company, info.id,
                    )
                    .await?;
                let lead = preferred
                    .as_ref()
                    .map(|p| p.lead_time_days)
                    .filter(|d| *d > 0)
                    .or(info.lead_time_days)
                    .unwrap_or(0);
                (
                    Supply::Buy {
                        supplier_id: preferred.as_ref().map(|p| p.supplier_id),
                        moq: preferred.map(|p| p.moq).unwrap_or(Decimal::ZERO),
                    },
                    lead,
                )
            }
        };
        let floor = info
            .safety_stock
            .unwrap_or(Decimal::ZERO)
            .max(info.reorder_min.unwrap_or(Decimal::ZERO));
        items.push(Item {
            product_id: info.id,
            code: info.code,
            supply,
            on_hand: on_hand.get(&info.id).copied().unwrap_or(Decimal::ZERO),
            floor,
            reorder_max: info.reorder_max,
            lead_days: i64::from(lead.max(0)),
            multiple: info.order_multiple,
            bom: uses.unwrap_or_default(),
            requirements: requirements.remove(&info.id).unwrap_or_default(),
            receipts: incoming.remove(&info.id).unwrap_or_default(),
        });
    }

    let proposals = plan(items, &Settings { today, horizon_end }).map_err(|BomCycle| {
        AppError::Validation(
            "the bills of materials call each other; planning is not possible".into(),
        )
    })?;

    // Keep the result.
    sqlx::query(
        "UPDATE mrp.proposals SET status = 'superseded' WHERE company_id = $1 AND status = 'open'",
    )
    .bind(company)
    .execute(&mut *conn)
    .await?;
    let year = today.year();
    let seq = numbering::next_number(&mut *conn, company, "MRP", year).await?;
    let number = format!("MRP{year}-{seq:05}");
    let run_id = new_id();
    sqlx::query(
        "INSERT INTO mrp.runs (id, company_id, number, planned_on, horizon_days, run_by, proposals)
         VALUES ($1, $2, $3, $4, $5, $6, $7)",
    )
    .bind(run_id)
    .bind(company)
    .bind(&number)
    .bind(today)
    .bind(horizon_days)
    .bind(user.user_id)
    .bind(proposals.len() as i32)
    .execute(&mut *conn)
    .await?;
    for p in &proposals {
        insert_proposal(conn, company, run_id, p).await?;
    }
    audit::record(
        conn,
        user,
        "mrp_run",
        run_id,
        "run",
        serde_json::json!({
            "number": number, "horizon_days": horizon_days, "proposals": proposals.len(),
        }),
    )
    .await?;
    Ok(RunOutcome {
        id: run_id,
        number,
        planned_on: today,
        horizon_days,
        proposals: proposals.len(),
    })
}

async fn insert_proposal(
    conn: &mut PgConnection,
    company: Uuid,
    run_id: Uuid,
    p: &Proposal,
) -> AppResult<()> {
    sqlx::query(
        "INSERT INTO mrp.proposals
            (id, company_id, run_id, product_id, kind, quantity, need_date, order_date, late,
             supplier_id, reason, pegging)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)",
    )
    .bind(new_id())
    .bind(company)
    .bind(run_id)
    .bind(p.product_id)
    .bind(match p.kind {
        ProposalKind::Purchase => "purchase",
        ProposalKind::Production => "production",
    })
    .bind(p.quantity)
    .bind(p.need_date)
    .bind(p.order_date)
    .bind(p.late)
    .bind(p.supplier_id)
    .bind(match p.reason {
        Reason::Demand => "demand",
        Reason::SafetyStock => "safety_stock",
    })
    .bind(serde_json::to_value(&p.pegging).map_err(|e| AppError::Internal(e.into()))?)
    .execute(conn)
    .await?;
    Ok(())
}
