//! Pricing engine.
//!
//! This crate is deliberately free of I/O: it receives prices and conditions,
//! and returns calculated amounts. Every client (office, mobile, PDF, invoices)
//! gets its numbers from here, so two screens can never disagree on a price.
//!
//! Rules:
//! * Amounts are `Decimal`, never floating point.
//! * The list price comes from the customer's price zone, valid at the quote date.
//! * Discounts cascade: customer discount first, then the line discount.
//! * Line totals are rounded once, to 2 decimals, half away from zero.
//! * VAT is calculated per VAT rate on the sum of the line totals (not per line).
//! * A line may be priced as a percentage of its parent line's unit price (list or net); it is
//!   resolved after the parent is priced ([`percent_of_parent_price`]).

use chrono::NaiveDate;
use rust_decimal::{Decimal, RoundingStrategy};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

const HUNDRED: Decimal = Decimal::ONE_HUNDRED;

#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum PricingError {
    #[error("quantity must be greater than zero")]
    NonPositiveQuantity,
    #[error("discount must be between -100 and 100 percent")]
    InvalidDiscount,
    #[error("VAT rate cannot be negative")]
    NegativeVatRate,
    #[error("percentage of the parent price must be between 0 and 1000")]
    InvalidPercent,
    #[error("no price for this product in price zone {zone_code} on {date}")]
    NoPrice { zone_code: String, date: NaiveDate },
}

/// One entry of a zone price list. Entries are never modified; a new price
/// is a new entry with a later `valid_from`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ZonePrice {
    pub zone_id: Uuid,
    pub unit_price: Decimal,
    pub valid_from: NaiveDate,
}

/// Returns the price of the given zone valid on `date`: the entry with the
/// latest `valid_from` that is not after `date`.
pub fn resolve_zone_price(prices: &[ZonePrice], zone_id: Uuid, date: NaiveDate) -> Option<Decimal> {
    prices
        .iter()
        .filter(|p| p.zone_id == zone_id && p.valid_from <= date)
        .max_by_key(|p| p.valid_from)
        .map(|p| p.unit_price)
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LineInput {
    pub list_unit_price: Decimal,
    pub quantity: Decimal,
    pub customer_discount_percent: Decimal,
    pub line_discount_percent: Decimal,
    pub vat_rate: Decimal,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct PricedLine {
    pub list_unit_price: Decimal,
    pub quantity: Decimal,
    pub customer_discount_percent: Decimal,
    pub line_discount_percent: Decimal,
    /// Net unit price after both discounts, rounded to 4 decimals (informative).
    pub net_unit_price: Decimal,
    /// Line amount excluding VAT, rounded to 2 decimals (authoritative).
    pub line_total: Decimal,
    pub vat_rate: Decimal,
}

fn round_money(d: Decimal) -> Decimal {
    d.round_dp_with_strategy(2, RoundingStrategy::MidpointAwayFromZero)
}

fn round_unit(d: Decimal) -> Decimal {
    d.round_dp_with_strategy(4, RoundingStrategy::MidpointAwayFromZero)
}

/// A rebate or extra line discount between -100 and 100 percent; a negative one is a surcharge.
fn valid_rebate(d: Decimal) -> bool {
    d >= -HUNDRED && d <= HUNDRED
}

/// Prices a single line.
pub fn price_line(input: &LineInput) -> Result<PricedLine, PricingError> {
    if input.quantity <= Decimal::ZERO {
        return Err(PricingError::NonPositiveQuantity);
    }
    if !valid_rebate(input.customer_discount_percent) || !valid_rebate(input.line_discount_percent)
    {
        return Err(PricingError::InvalidDiscount);
    }
    if input.vat_rate < Decimal::ZERO {
        return Err(PricingError::NegativeVatRate);
    }

    let factor = (HUNDRED - input.customer_discount_percent) / HUNDRED
        * (HUNDRED - input.line_discount_percent)
        / HUNDRED;
    let net_unit_exact = input.list_unit_price * factor;

    Ok(PricedLine {
        list_unit_price: input.list_unit_price,
        quantity: input.quantity,
        customer_discount_percent: input.customer_discount_percent,
        line_discount_percent: input.line_discount_percent,
        net_unit_price: round_unit(net_unit_exact),
        // Round once, from the exact value, to avoid double-rounding drift.
        line_total: round_money(net_unit_exact * input.quantity),
        vat_rate: input.vat_rate,
    })
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct VatGroup {
    pub vat_rate: Decimal,
    pub base: Decimal,
    pub vat: Decimal,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Totals {
    pub subtotal: Decimal,
    /// Sorted by VAT rate, descending.
    pub vat_groups: Vec<VatGroup>,
    pub vat_total: Decimal,
    pub total: Decimal,
}

/// Document totals: VAT is computed per rate on the summed bases.
pub fn totals(lines: &[PricedLine]) -> Totals {
    let mut groups: Vec<VatGroup> = Vec::new();
    for line in lines {
        match groups.iter_mut().find(|g| g.vat_rate == line.vat_rate) {
            Some(g) => g.base += line.line_total,
            None => groups.push(VatGroup {
                vat_rate: line.vat_rate,
                base: line.line_total,
                vat: Decimal::ZERO,
            }),
        }
    }
    for g in &mut groups {
        g.vat = round_money(g.base * g.vat_rate / HUNDRED);
    }
    groups.sort_by_key(|g| std::cmp::Reverse(g.vat_rate));

    let subtotal: Decimal = groups.iter().map(|g| g.base).sum();
    let vat_total: Decimal = groups.iter().map(|g| g.vat).sum();
    Totals {
        subtotal,
        vat_total,
        total: subtotal + vat_total,
        vat_groups: groups,
    }
}

// ---------------------------------------------------------------------------------------------
// Percent-of-parent pricing
// ---------------------------------------------------------------------------------------------

/// Which price of the parent line a percent-of-parent line is computed from.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PercentBase {
    /// The parent's list unit price (before rebates). The child then gets its own rebate and line
    /// discount like any list-priced line.
    ParentListUnitPrice,
    /// The parent's net unit price (after the parent's rebate and line discount). The child is
    /// already net: it gets no further rebate and no line discount.
    ParentNetUnitPrice,
}

impl PercentBase {
    pub fn parse(s: &str) -> Option<Self> {
        match s {
            "parent_list_unit_price" => Some(PercentBase::ParentListUnitPrice),
            "parent_net_unit_price" => Some(PercentBase::ParentNetUnitPrice),
            _ => None,
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            PercentBase::ParentListUnitPrice => "parent_list_unit_price",
            PercentBase::ParentNetUnitPrice => "parent_net_unit_price",
        }
    }

    /// Whether the child line is already net (no rebate, no line discount).
    pub fn is_net(self) -> bool {
        self == PercentBase::ParentNetUnitPrice
    }
}

/// The highest percentage accepted (10 times the parent price).
const MAX_PERCENT: Decimal = Decimal::from_parts(1000, 0, 0, false, 0);

/// The unit price of a line priced as `percent` % of its (already priced) parent line, rounded to
/// 4 decimals like other unit prices. It is used as the child's `list_unit_price`; the child's
/// quantity, rebate and line discount then apply as usual (see [`PercentBase`]).
pub fn percent_of_parent_price(
    parent: &PricedLine,
    percent: Decimal,
    base: PercentBase,
) -> Result<Decimal, PricingError> {
    if percent < Decimal::ZERO || percent > MAX_PERCENT {
        return Err(PricingError::InvalidPercent);
    }
    let base_price = match base {
        PercentBase::ParentListUnitPrice => parent.list_unit_price,
        PercentBase::ParentNetUnitPrice => parent.net_unit_price,
    };
    Ok(round_unit(base_price * percent / HUNDRED))
}

// ---------------------------------------------------------------------------------------------
// Rebates
// ---------------------------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RebateScope {
    Product(Uuid),
    Family(Uuid),
}

/// A customer rebate for one product or one product family, optionally limited in time.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RebateRule {
    pub scope: RebateScope,
    pub percent: Decimal,
    pub valid_from: Option<NaiveDate>,
    pub valid_to: Option<NaiveDate>,
}

impl RebateRule {
    fn valid_on(&self, date: NaiveDate) -> bool {
        self.valid_from.is_none_or(|f| f <= date) && self.valid_to.is_none_or(|t| date <= t)
    }
}

/// Where the rebate of a line comes from.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum RebateSource {
    Product,
    Family,
    General,
    /// Net-priced product: no rebate.
    Net,
}

impl RebateSource {
    pub fn as_str(self) -> &'static str {
        match self {
            RebateSource::Product => "product",
            RebateSource::Family => "family",
            RebateSource::General => "general",
            RebateSource::Net => "net",
        }
    }
}

/// The rebate for a product: the most specific rule valid on `date` wins
/// (product, then family, then the customer's general rebate). Non-discountable products get none.
/// If several rules of the same scope are valid, the one that started last applies.
pub fn resolve_rebate(
    rules: &[RebateRule],
    general_percent: Decimal,
    product_id: Uuid,
    family_id: Option<Uuid>,
    non_discountable: bool,
    date: NaiveDate,
) -> (Decimal, RebateSource) {
    if non_discountable {
        return (Decimal::ZERO, RebateSource::Net);
    }
    let best = |scope: RebateScope| {
        rules
            .iter()
            .filter(|r| r.scope == scope && r.valid_on(date))
            .max_by_key(|r| r.valid_from)
            .map(|r| r.percent)
    };
    if let Some(p) = best(RebateScope::Product(product_id)) {
        return (p, RebateSource::Product);
    }
    if let Some(p) = family_id.and_then(|f| best(RebateScope::Family(f))) {
        return (p, RebateSource::Family);
    }
    (general_percent, RebateSource::General)
}

// ---------------------------------------------------------------------------------------------
// Bulk price changes
// ---------------------------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum PriceChange {
    /// Percentage change, e.g. 4.5 for +4.5 %, -2 for -2 %.
    Percent(Decimal),
    /// Fixed amount added to the price (may be negative).
    Amount(Decimal),
}

/// Applies a price change and rounds to the nearest multiple of `step` (e.g. 0.01, 0.05, 1),
/// half away from zero.
pub fn change_price(base: Decimal, change: PriceChange, step: Decimal) -> Decimal {
    let raw = match change {
        PriceChange::Percent(p) => base * (HUNDRED + p) / HUNDRED,
        PriceChange::Amount(a) => base + a,
    };
    let rounded = if step > Decimal::ZERO {
        (raw / step).round_dp_with_strategy(0, RoundingStrategy::MidpointAwayFromZero) * step
    } else {
        raw
    };
    rounded.round_dp(4)
}

#[cfg(test)]
mod tests {
    use super::*;
    use rust_decimal_macros::dec;

    fn line(price: Decimal, qty: Decimal, cust: Decimal, disc: Decimal, vat: Decimal) -> LineInput {
        LineInput {
            list_unit_price: price,
            quantity: qty,
            customer_discount_percent: cust,
            line_discount_percent: disc,
            vat_rate: vat,
        }
    }

    fn d(s: &str) -> NaiveDate {
        NaiveDate::parse_from_str(s, "%Y-%m-%d").unwrap()
    }

    #[test]
    fn plain_line_without_discounts() {
        let p = price_line(&line(dec!(12.50), dec!(4), dec!(0), dec!(0), dec!(21))).unwrap();
        assert_eq!(p.net_unit_price, dec!(12.50));
        assert_eq!(p.line_total, dec!(50.00));
    }

    #[test]
    fn discounts_cascade_not_add() {
        // 10% then 5% = 14.5%, not 15%.
        let p = price_line(&line(dec!(100), dec!(1), dec!(10), dec!(5), dec!(21))).unwrap();
        assert_eq!(p.net_unit_price, dec!(85.50));
        assert_eq!(p.line_total, dec!(85.50));
    }

    #[test]
    fn line_total_rounded_once_from_exact_value() {
        // net unit = 0.33335 * 0.9 = 0.300015 -> unit shown 0.3000;
        // line = 0.300015 * 1000 = 300.015 -> 300.02 (not 0.3000*1000 = 300.00)
        let p = price_line(&line(
            dec!(0.33335),
            dec!(1000),
            dec!(10),
            dec!(0),
            dec!(21),
        ))
        .unwrap();
        assert_eq!(p.net_unit_price, dec!(0.3000));
        assert_eq!(p.line_total, dec!(300.02));
    }

    #[test]
    fn midpoint_rounds_away_from_zero() {
        let p = price_line(&line(dec!(0.005), dec!(1), dec!(0), dec!(0), dec!(21))).unwrap();
        assert_eq!(p.line_total, dec!(0.01));
    }

    #[test]
    fn fractional_quantities() {
        let p = price_line(&line(dec!(19.99), dec!(2.5), dec!(0), dec!(0), dec!(21))).unwrap();
        assert_eq!(p.line_total, dec!(49.98)); // 49.975 -> 49.98
    }

    #[test]
    fn full_discount_gives_zero() {
        let p = price_line(&line(dec!(250), dec!(3), dec!(0), dec!(100), dec!(21))).unwrap();
        assert_eq!(p.line_total, dec!(0.00));
    }

    #[test]
    fn rejects_invalid_input() {
        assert_eq!(
            price_line(&line(dec!(1), dec!(0), dec!(0), dec!(0), dec!(21))),
            Err(PricingError::NonPositiveQuantity)
        );
        assert_eq!(
            price_line(&line(dec!(1), dec!(1), dec!(-100.01), dec!(0), dec!(21))),
            Err(PricingError::InvalidDiscount)
        );
        assert_eq!(
            price_line(&line(dec!(1), dec!(1), dec!(0), dec!(-100.01), dec!(21))),
            Err(PricingError::InvalidDiscount)
        );
        assert_eq!(
            price_line(&line(dec!(1), dec!(1), dec!(0), dec!(100.01), dec!(21))),
            Err(PricingError::InvalidDiscount)
        );
        assert_eq!(
            price_line(&line(dec!(1), dec!(1), dec!(0), dec!(0), dec!(-6))),
            Err(PricingError::NegativeVatRate)
        );
    }

    #[test]
    fn negative_unit_price_is_allowed_and_discounted() {
        let p = price_line(&line(dec!(-125.32), dec!(2), dec!(10), dec!(0), dec!(21))).unwrap();
        assert_eq!(p.net_unit_price, dec!(-112.788));
        assert_eq!(p.line_total, dec!(-225.58));
    }

    #[test]
    fn vat_is_computed_per_rate_on_summed_base() {
        // Three lines of 0.05 at 21%: per-line VAT would be 3 x 0.01 = 0.03,
        // per-rate VAT on 0.15 is 0.0315 -> 0.03. Use values where it differs:
        // 3 x 0.10 at 6%: per line 0.006 -> 0.01 each = 0.03; on base 0.30 -> 0.018 -> 0.02.
        let lines: Vec<_> = (0..3)
            .map(|_| price_line(&line(dec!(0.10), dec!(1), dec!(0), dec!(0), dec!(6))).unwrap())
            .collect();
        let t = totals(&lines);
        assert_eq!(t.subtotal, dec!(0.30));
        assert_eq!(t.vat_total, dec!(0.02));
        assert_eq!(t.total, dec!(0.32));
    }

    #[test]
    fn negative_line_discount_is_an_extra_charge() {
        let p = price_line(&line(dec!(100), dec!(1), dec!(10), dec!(-10), dec!(21))).unwrap();
        // 100 x 0.90 x 1.10
        assert_eq!(p.net_unit_price, dec!(99));
    }

    #[test]
    fn negative_customer_rebate_is_a_surcharge() {
        let p = price_line(&LineInput {
            list_unit_price: dec!(100),
            quantity: dec!(2),
            customer_discount_percent: dec!(-10),
            line_discount_percent: dec!(0),
            vat_rate: dec!(21),
        })
        .unwrap();
        assert_eq!(p.net_unit_price, dec!(110));
        assert_eq!(p.line_total, dec!(220));
        let too_low = price_line(&LineInput {
            list_unit_price: dec!(100),
            quantity: dec!(1),
            customer_discount_percent: dec!(-101),
            line_discount_percent: dec!(0),
            vat_rate: dec!(21),
        });
        assert_eq!(too_low, Err(PricingError::InvalidDiscount));
    }

    #[test]
    fn totals_group_multiple_vat_rates() {
        let lines = vec![
            price_line(&line(dec!(100), dec!(2), dec!(0), dec!(0), dec!(21))).unwrap(),
            price_line(&line(dec!(50), dec!(1), dec!(0), dec!(0), dec!(6))).unwrap(),
            price_line(&line(dec!(10), dec!(1), dec!(0), dec!(0), dec!(21))).unwrap(),
        ];
        let t = totals(&lines);
        assert_eq!(t.vat_groups.len(), 2);
        assert_eq!(
            t.vat_groups[0],
            VatGroup {
                vat_rate: dec!(21),
                base: dec!(210),
                vat: dec!(44.10)
            }
        );
        assert_eq!(
            t.vat_groups[1],
            VatGroup {
                vat_rate: dec!(6),
                base: dec!(50),
                vat: dec!(3.00)
            }
        );
        assert_eq!(t.subtotal, dec!(260));
        assert_eq!(t.vat_total, dec!(47.10));
        assert_eq!(t.total, dec!(307.10));
    }

    #[test]
    fn empty_document_totals_zero() {
        let t = totals(&[]);
        assert_eq!(t.total, Decimal::ZERO);
        assert!(t.vat_groups.is_empty());
    }

    #[test]
    fn zone_price_resolution_uses_latest_valid_entry() {
        let zone_a = Uuid::from_u128(1);
        let zone_b = Uuid::from_u128(2);
        let prices = vec![
            ZonePrice {
                zone_id: zone_a,
                unit_price: dec!(100),
                valid_from: d("2026-01-01"),
            },
            ZonePrice {
                zone_id: zone_a,
                unit_price: dec!(110),
                valid_from: d("2026-07-01"),
            },
            ZonePrice {
                zone_id: zone_a,
                unit_price: dec!(120),
                valid_from: d("2027-01-01"),
            },
            ZonePrice {
                zone_id: zone_b,
                unit_price: dec!(90),
                valid_from: d("2026-01-01"),
            },
        ];
        assert_eq!(resolve_zone_price(&prices, zone_a, d("2025-12-31")), None);
        assert_eq!(
            resolve_zone_price(&prices, zone_a, d("2026-01-01")),
            Some(dec!(100))
        );
        assert_eq!(
            resolve_zone_price(&prices, zone_a, d("2026-06-30")),
            Some(dec!(100))
        );
        assert_eq!(
            resolve_zone_price(&prices, zone_a, d("2026-07-01")),
            Some(dec!(110))
        );
        assert_eq!(
            resolve_zone_price(&prices, zone_a, d("2026-11-05")),
            Some(dec!(110))
        );
        assert_eq!(
            resolve_zone_price(&prices, zone_b, d("2026-11-05")),
            Some(dec!(90))
        );
    }

    // --- rebates -------------------------------------------------------------------------

    const PUMP: Uuid = Uuid::from_u128(10);
    const PUMPS: Uuid = Uuid::from_u128(20);
    const UNITS: Uuid = Uuid::from_u128(21);

    fn rule(
        scope: RebateScope,
        percent: Decimal,
        from: Option<&str>,
        to: Option<&str>,
    ) -> RebateRule {
        RebateRule {
            scope,
            percent,
            valid_from: from.map(d),
            valid_to: to.map(d),
        }
    }

    #[test]
    fn most_specific_rebate_wins() {
        let rules = vec![
            rule(RebateScope::Family(PUMPS), dec!(15), None, None),
            rule(RebateScope::Product(PUMP), dec!(20), None, None),
        ];
        let date = d("2026-11-05");
        assert_eq!(
            resolve_rebate(&rules, dec!(10), PUMP, Some(PUMPS), false, date),
            (dec!(20), RebateSource::Product)
        );
        // Another pump: the family rule applies.
        let other = Uuid::from_u128(11);
        assert_eq!(
            resolve_rebate(&rules, dec!(10), other, Some(PUMPS), false, date),
            (dec!(15), RebateSource::Family)
        );
        // A more specific rule wins even when it is lower.
        let low = vec![rule(RebateScope::Product(PUMP), dec!(2), None, None)];
        assert_eq!(
            resolve_rebate(&low, dec!(10), PUMP, Some(PUMPS), false, date),
            (dec!(2), RebateSource::Product)
        );
        // Other family: general rebate.
        assert_eq!(
            resolve_rebate(
                &rules,
                dec!(10),
                Uuid::from_u128(12),
                Some(UNITS),
                false,
                date
            ),
            (dec!(10), RebateSource::General)
        );
    }

    #[test]
    fn net_products_never_get_a_rebate() {
        let rules = vec![rule(RebateScope::Product(PUMP), dec!(20), None, None)];
        assert_eq!(
            resolve_rebate(&rules, dec!(10), PUMP, Some(PUMPS), true, d("2026-11-05")),
            (dec!(0), RebateSource::Net)
        );
    }

    #[test]
    fn price_on_request_and_indicative_products_get_rebates_like_list_products() {
        assert_eq!(
            resolve_rebate(&[], dec!(7.5), PUMP, None, false, d("2026-11-05")),
            (dec!(7.5), RebateSource::General)
        );
    }

    #[test]
    fn rebate_rules_respect_validity_dates() {
        let rules = vec![
            rule(
                RebateScope::Family(PUMPS),
                dec!(12),
                Some("2026-01-01"),
                Some("2026-06-30"),
            ),
            rule(
                RebateScope::Family(PUMPS),
                dec!(14),
                Some("2026-07-01"),
                None,
            ),
        ];
        let at = |date| resolve_rebate(&rules, dec!(5), PUMP, Some(PUMPS), false, d(date));
        assert_eq!(at("2025-12-31"), (dec!(5), RebateSource::General));
        assert_eq!(at("2026-03-01"), (dec!(12), RebateSource::Family));
        assert_eq!(at("2026-06-30"), (dec!(12), RebateSource::Family));
        assert_eq!(at("2026-07-01"), (dec!(14), RebateSource::Family));
    }

    // --- percent of parent ---------------------------------------------------------------

    fn parent() -> PricedLine {
        // 7200 list, 5 % rebate, 10 % line discount: net 6156.
        price_line(&line(dec!(7200), dec!(2), dec!(5), dec!(10), dec!(21))).unwrap()
    }

    #[test]
    fn percent_of_parent_list_price() {
        let p = parent();
        let unit = percent_of_parent_price(&p, dec!(20), PercentBase::ParentListUnitPrice).unwrap();
        assert_eq!(unit, dec!(1440.0000));
        // The child then gets its own rebate like any list line.
        let child = price_line(&line(unit, dec!(2), dec!(5), dec!(0), dec!(21))).unwrap();
        assert_eq!(child.net_unit_price, dec!(1368.0000));
        assert_eq!(child.line_total, dec!(2736.00));
    }

    #[test]
    fn percent_of_parent_net_price() {
        let p = parent();
        assert_eq!(p.net_unit_price, dec!(6156.0000));
        let unit = percent_of_parent_price(&p, dec!(20), PercentBase::ParentNetUnitPrice).unwrap();
        assert_eq!(unit, dec!(1231.2000));
        assert!(PercentBase::ParentNetUnitPrice.is_net());
        assert!(!PercentBase::ParentListUnitPrice.is_net());
    }

    #[test]
    fn percent_of_parent_rounds_to_four_decimals() {
        let p = price_line(&line(dec!(10.01), dec!(1), dec!(0), dec!(0), dec!(21))).unwrap();
        // 10.01 * 33.33 % = 3.336333
        assert_eq!(
            percent_of_parent_price(&p, dec!(33.33), PercentBase::ParentListUnitPrice),
            Ok(dec!(3.3363))
        );
        // 0 % is allowed (an included option shown at no cost).
        assert_eq!(
            percent_of_parent_price(&p, dec!(0), PercentBase::ParentListUnitPrice),
            Ok(dec!(0.0000))
        );
    }

    #[test]
    fn percent_of_parent_rejects_out_of_range() {
        let p = parent();
        assert_eq!(
            percent_of_parent_price(&p, dec!(-1), PercentBase::ParentListUnitPrice),
            Err(PricingError::InvalidPercent)
        );
        assert_eq!(
            percent_of_parent_price(&p, dec!(1000.01), PercentBase::ParentNetUnitPrice),
            Err(PricingError::InvalidPercent)
        );
        assert!(percent_of_parent_price(&p, dec!(1000), PercentBase::ParentNetUnitPrice).is_ok());
    }

    #[test]
    fn percent_base_round_trips() {
        for b in [
            PercentBase::ParentListUnitPrice,
            PercentBase::ParentNetUnitPrice,
        ] {
            assert_eq!(PercentBase::parse(b.as_str()), Some(b));
        }
        assert_eq!(PercentBase::parse("total"), None);
    }

    // --- bulk price changes --------------------------------------------------------------

    #[test]
    fn price_changes_round_to_the_step() {
        assert_eq!(
            change_price(dec!(100), PriceChange::Percent(dec!(4.5)), dec!(0.01)),
            dec!(104.50)
        );
        assert_eq!(
            change_price(dec!(12.40), PriceChange::Percent(dec!(3)), dec!(0.05)),
            dec!(12.75)
        ); // 12.772
        assert_eq!(
            change_price(dec!(3880), PriceChange::Percent(dec!(2.7)), dec!(1)),
            dec!(3985)
        ); // 3984.76
        assert_eq!(
            change_price(dec!(9.99), PriceChange::Amount(dec!(0.5)), dec!(0.01)),
            dec!(10.49)
        );
        assert_eq!(
            change_price(dec!(10), PriceChange::Percent(dec!(-10)), dec!(0.01)),
            dec!(9.00)
        );
        assert_eq!(
            change_price(dec!(1), PriceChange::Amount(dec!(-2)), dec!(0.01)),
            dec!(-1.00)
        );
        assert_eq!(
            change_price(dec!(-125.32), PriceChange::Percent(dec!(10)), dec!(0.01)),
            dec!(-137.85)
        );
    }
}
