//! The planning engine. Pure: no database, no clock. Everything it needs is in [`Item`]s and
//! [`Settings`], and what it makes are [`Proposal`]s.
//!
//! For every product, the day by day projection starts at what is on hand, adds the receipts
//! (open purchase orders, production orders in progress) and subtracts the requirements (open
//! sales orders, components of production orders). Whenever the projection falls below the floor
//! (safety stock or reorder level) a proposal is made for the shortfall, rounded to the minimum
//! order quantity and the order multiple, and placed one lead time before it is needed. A proposal
//! counts as supply at once, so one shortage is covered once, even when it is late.
//!
//! Products are planned from the top of the bills of materials down: a proposal to build something
//! is a requirement for its components on the day the build has to start.
//!
//! Simplifications, on purpose (ADR 0091): the lead time is a number of calendar days (a built
//! product's routing times are not used), nothing is reserved for a particular order, and demand
//! beyond the horizon is ignored.

use std::collections::{BTreeMap, HashMap};

use chrono::{Days, NaiveDate};
use rust_decimal::Decimal;
use serde::Serialize;
use uuid::Uuid;

/// What a quantity in a projection is for.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum PegKind {
    SalesOrder,
    ProductionOrder,
    PurchaseOrder,
    /// A proposal to build the product this is a component of.
    Planned,
}

/// A requirement or receipt and where it comes from.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Peg {
    pub kind: PegKind,
    pub id: Option<Uuid>,
    pub number: String,
    #[serde(with = "rust_decimal::serde::str")]
    pub quantity: Decimal,
}

/// Stock leaving (a requirement) or arriving (a receipt) on a day.
#[derive(Debug, Clone)]
pub struct Flow {
    pub date: NaiveDate,
    pub quantity: Decimal,
    pub peg: Peg,
}

/// One component of a bill of materials.
#[derive(Debug, Clone)]
pub struct BomUse {
    pub component: Uuid,
    pub quantity: Decimal,
    pub scrap_percent: Decimal,
}

/// How a product is supplied.
#[derive(Debug, Clone)]
pub enum Supply {
    /// Bought: from the preferred supplier, at least `moq` at a time.
    Buy {
        supplier_id: Option<Uuid>,
        moq: Decimal,
    },
    /// Built from its bill of materials.
    Make,
}

/// A product to plan.
#[derive(Debug, Clone)]
pub struct Item {
    pub product_id: Uuid,
    pub code: String,
    pub supply: Supply,
    pub on_hand: Decimal,
    /// The projection is kept at or above this: the larger of the safety stock and the reorder level.
    pub floor: Decimal,
    /// When set and above the floor, an order tops the projection up to this.
    pub reorder_max: Option<Decimal>,
    pub lead_days: i64,
    pub multiple: Option<Decimal>,
    /// The components of a built product.
    pub bom: Vec<BomUse>,
    pub requirements: Vec<Flow>,
    pub receipts: Vec<Flow>,
}

/// The day the plan starts and the last day that counts.
#[derive(Debug, Clone, Copy)]
pub struct Settings {
    pub today: NaiveDate,
    pub horizon_end: NaiveDate,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ProposalKind {
    Purchase,
    Production,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Reason {
    /// A requirement is not covered: the projection would go below zero.
    Demand,
    /// Only the safety stock or the reorder level is not kept.
    SafetyStock,
}

/// What to buy or build.
#[derive(Debug, Clone, PartialEq)]
pub struct Proposal {
    pub product_id: Uuid,
    pub kind: ProposalKind,
    pub quantity: Decimal,
    pub need_date: NaiveDate,
    /// When to order (or start): the need date less the lead time, but not before today.
    pub order_date: NaiveDate,
    /// The lead time reaches past the need date: the goods will be late.
    pub late: bool,
    pub supplier_id: Option<Uuid>,
    pub reason: Reason,
    /// The requirements this covers.
    pub pegging: Vec<Peg>,
}

/// The bills of materials call each other.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BomCycle;

fn add_days(d: NaiveDate, n: i64) -> NaiveDate {
    d.checked_add_days(Days::new(n.max(0) as u64)).unwrap_or(d)
}

fn sub_days(d: NaiveDate, n: i64) -> NaiveDate {
    d.checked_sub_days(Days::new(n.max(0) as u64)).unwrap_or(d)
}

/// The quantity to order for a shortfall: at least the minimum order quantity, then up to a
/// multiple of the order multiple.
fn lot(target: Decimal, moq: Decimal, multiple: Option<Decimal>) -> Decimal {
    let mut q = target.max(moq);
    if let Some(m) = multiple.filter(|m| *m > Decimal::ZERO) {
        q = (q / m).ceil() * m;
    }
    q.round_dp(4)
}

/// The depth of each item below the top of the bills of materials (0: nobody uses it).
fn levels(items: &[Item], index: &HashMap<Uuid, usize>) -> Result<Vec<usize>, BomCycle> {
    let n = items.len();
    let mut level = vec![0_usize; n];
    for _ in 0..=n {
        let mut changed = false;
        for (i, it) in items.iter().enumerate() {
            for b in &it.bom {
                if let Some(&c) = index.get(&b.component) {
                    if c == i {
                        return Err(BomCycle);
                    }
                    if level[c] < level[i] + 1 {
                        level[c] = level[i] + 1;
                        changed = true;
                    }
                }
            }
        }
        if !changed {
            return Ok(level);
        }
    }
    Err(BomCycle)
}

/// Plans the items. Products that are built come before their components, so what a proposal to
/// build needs of its components is part of their requirements.
pub fn plan(mut items: Vec<Item>, s: &Settings) -> Result<Vec<Proposal>, BomCycle> {
    let index: HashMap<Uuid, usize> = items
        .iter()
        .enumerate()
        .map(|(i, it)| (it.product_id, i))
        .collect();
    let level = levels(&items, &index)?;
    let mut order: Vec<usize> = (0..items.len()).collect();
    order.sort_by(|a, b| {
        level[*a]
            .cmp(&level[*b])
            .then_with(|| items[*a].code.cmp(&items[*b].code))
    });
    let mut out = Vec::new();
    for i in order {
        let before = out.len();
        plan_item(&mut items, i, &index, s, &mut out);
        debug_assert!(out.len() >= before);
    }
    out.sort_by(|a, b| {
        a.order_date
            .cmp(&b.order_date)
            .then(a.need_date.cmp(&b.need_date))
    });
    Ok(out)
}

struct Event {
    delta: Decimal,
    peg: Option<Peg>,
}

fn plan_item(
    items: &mut [Item],
    i: usize,
    index: &HashMap<Uuid, usize>,
    s: &Settings,
    out: &mut Vec<Proposal>,
) {
    let requirements = std::mem::take(&mut items[i].requirements);
    let receipts = std::mem::take(&mut items[i].receipts);
    let it = items[i].clone();
    let mut events: BTreeMap<NaiveDate, Vec<Event>> = BTreeMap::new();
    for f in requirements {
        let date = f.date.max(s.today);
        if f.quantity > Decimal::ZERO && date <= s.horizon_end {
            events.entry(date).or_default().push(Event {
                delta: -f.quantity,
                peg: Some(f.peg),
            });
        }
    }
    for f in receipts {
        let date = f.date.max(s.today);
        if f.quantity > Decimal::ZERO && date <= s.horizon_end {
            events.entry(date).or_default().push(Event {
                delta: f.quantity,
                peg: None,
            });
        }
    }
    // The start is always looked at: stock may be below the floor with nothing due.
    events.entry(s.today).or_default();

    let (supplier_id, moq, kind) = match &it.supply {
        Supply::Buy { supplier_id, moq } => (*supplier_id, *moq, ProposalKind::Purchase),
        Supply::Make => (None, Decimal::ZERO, ProposalKind::Production),
    };
    let mut projected = it.on_hand;
    let mut pegs: Vec<Peg> = Vec::new();
    while let Some((date, evs)) = events.pop_first() {
        for ev in evs {
            projected += ev.delta;
            pegs.extend(ev.peg);
        }
        if projected >= it.floor {
            // Covered: the requirements so far are not what a later order is for.
            if projected >= Decimal::ZERO {
                pegs.clear();
            }
            continue;
        }
        let mut target = it.floor - projected;
        if let Some(max) = it.reorder_max.filter(|m| *m > it.floor) {
            target = target.max(max - projected);
        }
        let quantity = lot(target, moq, it.multiple);
        if quantity <= Decimal::ZERO {
            continue;
        }
        let order_date = sub_days(date, it.lead_days).max(s.today);
        let arrival = add_days(order_date, it.lead_days);
        out.push(Proposal {
            product_id: it.product_id,
            kind,
            quantity,
            need_date: date,
            order_date,
            late: arrival > date,
            supplier_id,
            reason: if projected < Decimal::ZERO {
                Reason::Demand
            } else {
                Reason::SafetyStock
            },
            pegging: std::mem::take(&mut pegs),
        });
        // Planned supply counts at once: this shortage is covered, even if late.
        projected += quantity;
        if matches!(it.supply, Supply::Make) {
            for b in &it.bom {
                let Some(&c) = index.get(&b.component) else {
                    continue;
                };
                // The same quantity, rounded the same way (up to four places), as a release makes.
                let need =
                    tradocraft_production::orders::required(b.quantity, quantity, b.scrap_percent);
                if need > Decimal::ZERO {
                    items[c].requirements.push(Flow {
                        date: order_date,
                        quantity: need,
                        peg: Peg {
                            kind: PegKind::Planned,
                            id: Some(it.product_id),
                            number: it.code.clone(),
                            quantity,
                        },
                    });
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use rust_decimal_macros::dec;

    fn d(day: u32) -> NaiveDate {
        // March 2027: the 1st is a Monday.
        NaiveDate::from_ymd_opt(2027, 3, day).unwrap()
    }

    fn id(n: u128) -> Uuid {
        Uuid::from_u128(n)
    }

    fn settings() -> Settings {
        Settings {
            today: d(1),
            horizon_end: d(31),
        }
    }

    fn peg(kind: PegKind, number: &str, q: Decimal) -> Peg {
        Peg {
            kind,
            id: None,
            number: number.into(),
            quantity: q,
        }
    }

    fn need(day: u32, q: Decimal) -> Flow {
        Flow {
            date: d(day),
            quantity: q,
            peg: peg(PegKind::SalesOrder, "SO-1", q),
        }
    }

    fn receipt(day: u32, q: Decimal) -> Flow {
        Flow {
            date: d(day),
            quantity: q,
            peg: peg(PegKind::PurchaseOrder, "PO-1", q),
        }
    }

    fn bought(n: u128, on_hand: Decimal, lead: i64) -> Item {
        Item {
            product_id: id(n),
            code: format!("P{n}"),
            supply: Supply::Buy {
                supplier_id: Some(id(900)),
                moq: Decimal::ZERO,
            },
            on_hand,
            floor: Decimal::ZERO,
            reorder_max: None,
            lead_days: lead,
            multiple: None,
            bom: vec![],
            requirements: vec![],
            receipts: vec![],
        }
    }

    fn made(n: u128, on_hand: Decimal, lead: i64, bom: Vec<BomUse>) -> Item {
        Item {
            supply: Supply::Make,
            bom,
            ..bought(n, on_hand, lead)
        }
    }

    fn uses(n: u128, q: Decimal) -> BomUse {
        BomUse {
            component: id(n),
            quantity: q,
            scrap_percent: Decimal::ZERO,
        }
    }

    #[test]
    fn nothing_is_proposed_when_nothing_is_needed() {
        let mut p = bought(1, dec!(5), 3);
        p.requirements = vec![need(10, dec!(4))];
        assert!(plan(vec![p], &settings()).unwrap().is_empty());
        assert!(plan(vec![], &settings()).unwrap().is_empty());
    }

    #[test]
    fn a_shortage_is_bought_one_lead_time_before_it_is_needed() {
        let mut p = bought(1, dec!(5), 3);
        p.requirements = vec![need(10, dec!(8))];
        let r = plan(vec![p], &settings()).unwrap();
        assert_eq!(r.len(), 1);
        assert_eq!(r[0].kind, ProposalKind::Purchase);
        assert_eq!(r[0].quantity, dec!(3));
        assert_eq!((r[0].need_date, r[0].order_date), (d(10), d(7)));
        assert!(!r[0].late);
        assert_eq!(r[0].reason, Reason::Demand);
        assert_eq!(r[0].supplier_id, Some(id(900)));
        assert_eq!(r[0].pegging.len(), 1);
        assert_eq!(r[0].pegging[0].number, "SO-1");
    }

    #[test]
    fn what_is_already_on_order_counts() {
        let mut p = bought(1, dec!(0), 3);
        p.requirements = vec![need(10, dec!(8))];
        p.receipts = vec![receipt(8, dec!(8))];
        assert!(plan(vec![p.clone()], &settings()).unwrap().is_empty());
        // Arriving after the need leaves a gap until then: a proposal for the day it is needed.
        p.receipts = vec![receipt(12, dec!(8))];
        let r = plan(vec![p], &settings()).unwrap();
        assert_eq!(r.len(), 1);
        assert_eq!(r[0].need_date, d(10));
    }

    #[test]
    fn a_lead_time_that_reaches_before_today_makes_a_late_proposal() {
        let mut p = bought(1, dec!(0), 10);
        p.requirements = vec![need(5, dec!(2))];
        let r = plan(vec![p], &settings()).unwrap();
        assert_eq!(
            (r[0].need_date, r[0].order_date),
            (d(5), d(1)),
            "ordered today"
        );
        assert!(r[0].late, "it arrives on the 11th");
    }

    #[test]
    fn past_due_requirements_count_as_due_today() {
        let mut p = bought(1, dec!(0), 0);
        p.requirements = vec![Flow {
            date: NaiveDate::from_ymd_opt(2027, 2, 1).unwrap(),
            quantity: dec!(3),
            peg: peg(PegKind::SalesOrder, "SO-0", dec!(3)),
        }];
        let r = plan(vec![p], &settings()).unwrap();
        assert_eq!((r[0].need_date, r[0].order_date), (d(1), d(1)));
        assert!(!r[0].late);
    }

    #[test]
    fn demand_beyond_the_horizon_is_ignored() {
        let mut p = bought(1, dec!(0), 0);
        p.requirements = vec![Flow {
            date: NaiveDate::from_ymd_opt(2027, 4, 15).unwrap(),
            quantity: dec!(3),
            peg: peg(PegKind::SalesOrder, "SO-9", dec!(3)),
        }];
        assert!(plan(vec![p], &settings()).unwrap().is_empty());
    }

    #[test]
    fn the_safety_stock_is_kept_and_says_so() {
        let mut p = bought(1, dec!(10), 2);
        p.floor = dec!(8);
        p.requirements = vec![need(5, dec!(4))];
        let r = plan(vec![p], &settings()).unwrap();
        assert_eq!(r.len(), 1);
        assert_eq!(r[0].quantity, dec!(2), "10 - 4 = 6, 2 short of 8");
        assert_eq!(r[0].reason, Reason::SafetyStock);
    }

    #[test]
    fn stock_below_the_reorder_level_is_topped_up_to_the_maximum_today() {
        let mut p = bought(1, dec!(3), 4);
        p.floor = dec!(5);
        p.reorder_max = Some(dec!(20));
        let r = plan(vec![p], &settings()).unwrap();
        assert_eq!(r.len(), 1);
        assert_eq!(r[0].quantity, dec!(17));
        assert_eq!((r[0].need_date, r[0].order_date), (d(1), d(1)));
        assert!(
            r[0].late,
            "four days of lead time for something needed today"
        );
        assert!(r[0].pegging.is_empty());
    }

    #[test]
    fn the_minimum_and_the_multiple_round_the_quantity_up() {
        let mut p = bought(1, dec!(0), 0);
        p.supply = Supply::Buy {
            supplier_id: None,
            moq: dec!(10),
        };
        p.multiple = Some(dec!(6));
        p.requirements = vec![need(5, dec!(3))];
        assert_eq!(
            plan(vec![p.clone()], &settings()).unwrap()[0].quantity,
            dec!(12)
        );
        p.requirements = vec![need(5, dec!(25))];
        assert_eq!(plan(vec![p], &settings()).unwrap()[0].quantity, dec!(30));
    }

    #[test]
    fn one_shortage_is_covered_once_even_when_the_order_is_late() {
        let mut p = bought(1, dec!(0), 10);
        p.requirements = vec![need(3, dec!(2)), need(5, dec!(2)), need(8, dec!(2))];
        let r = plan(vec![p], &settings()).unwrap();
        // The first shortage is covered when it appears; each later requirement adds its own.
        let total: Decimal = r.iter().map(|x| x.quantity).sum();
        assert_eq!(total, dec!(6));
        assert!(r.iter().all(|x| x.late));
    }

    #[test]
    fn a_built_product_asks_its_components_for_the_day_its_build_starts() {
        let mut top = made(1, dec!(0), 5, vec![uses(2, dec!(3)), uses(3, dec!(1))]);
        top.requirements = vec![need(15, dec!(4))];
        let part = bought(2, dec!(5), 4);
        let sub = made(3, dec!(0), 2, vec![uses(4, dec!(2))]);
        let raw = bought(4, dec!(0), 6);
        let r = plan(vec![raw, sub, part, top], &settings()).unwrap();
        let by = |n: u128| {
            r.iter()
                .filter(|x| x.product_id == id(n))
                .collect::<Vec<_>>()
        };
        // The frame is built from the 10th (needed on the 15th, five days).
        assert_eq!(by(1).len(), 1);
        assert_eq!(by(1)[0].kind, ProposalKind::Production);
        assert_eq!((by(1)[0].need_date, by(1)[0].order_date), (d(15), d(10)));
        assert_eq!(by(1)[0].supplier_id, None);
        // 4 frames need 12 parts; 5 are in stock: 7 are bought, to arrive on the 10th.
        assert_eq!(by(2)[0].quantity, dec!(7));
        assert_eq!((by(2)[0].need_date, by(2)[0].order_date), (d(10), d(6)));
        // The subassembly is built for the 10th (two days), and asks the raw material for the 8th.
        assert_eq!(by(3)[0].quantity, dec!(4));
        assert_eq!((by(3)[0].need_date, by(3)[0].order_date), (d(10), d(8)));
        assert_eq!(by(4)[0].quantity, dec!(8));
        assert_eq!((by(4)[0].need_date, by(4)[0].order_date), (d(8), d(2)));
        // Where it comes from is kept.
        assert_eq!(by(2)[0].pegging[0].kind, PegKind::Planned);
        assert_eq!(by(2)[0].pegging[0].number, "P1");
        assert_eq!(by(2)[0].pegging[0].quantity, dec!(4));
        // Sorted by when to order.
        assert!(r.windows(2).all(|w| w[0].order_date <= w[1].order_date));
    }

    #[test]
    fn scrap_adds_to_what_the_components_need() {
        let mut top = made(
            1,
            dec!(0),
            0,
            vec![BomUse {
                component: id(2),
                quantity: dec!(10),
                scrap_percent: dec!(5),
            }],
        );
        top.requirements = vec![need(10, dec!(2))];
        let part = bought(2, dec!(0), 0);
        let r = plan(vec![top, part], &settings()).unwrap();
        let part_q = r.iter().find(|x| x.product_id == id(2)).unwrap().quantity;
        assert_eq!(part_q, dec!(21), "2 x 10 x 1.05");
    }

    #[test]
    fn components_are_rounded_up_like_a_release_rounds_them() {
        // A fraction beyond the fourth place: 0.00011 per piece is 0.0002 when a production order is
        // released (rounded away from zero), not 0.0001.
        for (per, qty, scrap) in [
            (dec!(0.00011), dec!(1), dec!(0)),
            (dec!(0.3333), dec!(3), dec!(0)),
            (dec!(1.1), dec!(0.37), dec!(2.5)),
            (dec!(10), dec!(2), dec!(5)),
        ] {
            let mut top = made(
                1,
                dec!(0),
                0,
                vec![BomUse {
                    component: id(2),
                    quantity: per,
                    scrap_percent: scrap,
                }],
            );
            top.requirements = vec![need(10, qty)];
            let r = plan(vec![top, bought(2, dec!(0), 0)], &settings()).unwrap();
            let planned = r.iter().find(|x| x.product_id == id(2)).unwrap().quantity;
            // The proposal builds `qty` (nothing is on hand), so a release for it needs this much.
            assert_eq!(
                planned,
                tradocraft_production::orders::required(per, qty, scrap),
                "{per} x {qty} + {scrap} %"
            );
        }
        // Exact quantities stay exact.
        let mut top = made(
            1,
            dec!(0),
            0,
            vec![BomUse {
                component: id(2),
                quantity: dec!(10),
                scrap_percent: dec!(5),
            }],
        );
        top.requirements = vec![need(10, dec!(2))];
        let r = plan(vec![top, bought(2, dec!(0), 0)], &settings()).unwrap();
        assert_eq!(
            r.iter().find(|x| x.product_id == id(2)).unwrap().quantity,
            dec!(21)
        );
    }

    #[test]
    fn a_component_used_by_two_products_adds_up() {
        let mut a = made(1, dec!(0), 0, vec![uses(3, dec!(2))]);
        a.requirements = vec![need(10, dec!(5))];
        let mut b = made(2, dec!(0), 0, vec![uses(3, dec!(1))]);
        b.requirements = vec![need(10, dec!(4))];
        let c = bought(3, dec!(0), 0);
        let r = plan(vec![c, a, b], &settings()).unwrap();
        let q: Decimal = r
            .iter()
            .filter(|x| x.product_id == id(3))
            .map(|x| x.quantity)
            .sum();
        assert_eq!(q, dec!(14), "10 + 4");
    }

    #[test]
    fn a_bill_of_materials_that_calls_itself_is_refused() {
        let a = made(1, dec!(0), 0, vec![uses(2, dec!(1))]);
        let b = made(2, dec!(0), 0, vec![uses(1, dec!(1))]);
        assert_eq!(plan(vec![a, b], &settings()).unwrap_err(), BomCycle);
        let own = made(3, dec!(0), 0, vec![uses(3, dec!(1))]);
        assert_eq!(plan(vec![own], &settings()).unwrap_err(), BomCycle);
    }

    #[test]
    fn the_projection_never_ends_below_the_floor_after_the_plan() {
        // Whatever the arrangement, the planned supply makes up every shortfall.
        for on_hand in [dec!(0), dec!(7), dec!(50)] {
            for floor in [dec!(0), dec!(5)] {
                for lead in [0_i64, 3, 40] {
                    let mut p = bought(1, on_hand, lead);
                    p.floor = floor;
                    p.requirements = vec![need(3, dec!(9)), need(9, dec!(4)), need(20, dec!(30))];
                    p.receipts = vec![receipt(6, dec!(5))];
                    p.multiple = Some(dec!(4));
                    let r = plan(vec![p], &settings()).unwrap();
                    let supply: Decimal = r.iter().map(|x| x.quantity).sum();
                    let projected = on_hand + dec!(5) + supply - dec!(43);
                    assert!(
                        projected >= floor,
                        "on hand {on_hand}, floor {floor}, lead {lead}: ends at {projected}"
                    );
                }
            }
        }
    }
}
