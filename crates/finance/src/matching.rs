//! The three-way match as a pure function (ADR 0046): purchase order vs goods receipt vs invoice.

use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;
use uuid::Uuid;

/// Outcome for one invoice line.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum LineStatus {
    /// Quantity and price are within the order, the receipts and the tolerances.
    Ok,
    /// More is invoiced on the order line than has been received.
    NotReceived,
    /// More is invoiced on the order line than was ordered, beyond the quantity tolerance.
    OverInvoiced,
    /// The unit price differs from the order price beyond the price tolerance.
    PriceVariance,
    /// A free-text line without a purchase order line; it cannot be matched.
    NoPoLine,
}

/// Match tolerances in percent.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Tolerance {
    /// Extra quantity allowed above the ordered quantity.
    pub quantity_pct: Decimal,
    /// Price difference allowed around the order price, in either direction.
    pub price_pct: Decimal,
}

/// What the purchase order and the receipts say about a line.
#[derive(Debug, Clone, Copy)]
pub struct PoFigures {
    /// Ordered quantity.
    pub ordered: Decimal,
    /// Quantity received so far (sum of the goods receipt lines).
    pub received: Decimal,
    /// Unit price on the order.
    pub unit_price: Decimal,
}

/// Input of the match for one invoice line.
#[derive(Debug, Clone, Copy)]
pub struct LineInput {
    /// The order line figures, or `None` for a free-text line.
    pub po: Option<PoFigures>,
    /// Quantity on this invoice line.
    pub quantity: Decimal,
    /// Unit price on this invoice line.
    pub unit_price: Decimal,
    /// Quantity invoiced on the same order line elsewhere: this invoice's other lines plus the
    /// lines of other non-disputed invoices.
    pub other_invoiced: Decimal,
}

/// Evaluated line: the status and the numbers behind it.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct LineMatch {
    /// The invoice line (set by the caller; nil in pure unit tests).
    pub invoice_line_id: Uuid,
    /// The first problem found (not_received, over_invoiced, price_variance), or ok.
    pub status: LineStatus,
    /// Every problem found on the line; empty when ok.
    pub issues: Vec<LineStatus>,
    /// Ordered quantity, if the line points at an order line.
    #[schema(value_type = Option<String>)]
    pub ordered_quantity: Option<Decimal>,
    /// Received quantity, if the line points at an order line.
    #[schema(value_type = Option<String>)]
    pub received_quantity: Option<Decimal>,
    /// Quantity invoiced on the order line in total (this line and all others counted).
    #[schema(value_type = Option<String>)]
    pub invoiced_quantity: Option<Decimal>,
    /// Quantity on this line.
    #[schema(value_type = String)]
    pub line_quantity: Decimal,
    /// Unit price on the order line.
    #[schema(value_type = Option<String>)]
    pub po_unit_price: Option<Decimal>,
    /// Unit price on this line.
    #[schema(value_type = String)]
    pub invoice_unit_price: Decimal,
    /// Invoice price minus order price as a percentage of the order price (a zero order price
    /// and a different invoice price gives 100).
    #[schema(value_type = Option<String>)]
    pub price_variance_pct: Option<Decimal>,
}

/// Evaluated invoice.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct MatchReport {
    /// True only when there is at least one line and every line is ok.
    pub matched: bool,
    /// Quantity tolerance used, percent.
    #[schema(value_type = String)]
    pub quantity_tolerance_pct: Decimal,
    /// Price tolerance used, percent.
    #[schema(value_type = String)]
    pub price_tolerance_pct: Decimal,
    /// One entry per invoice line, in line order.
    pub lines: Vec<LineMatch>,
}

fn hundred() -> Decimal {
    Decimal::from(100)
}

/// Matches one invoice line.
pub fn match_line(input: &LineInput, tol: &Tolerance) -> LineMatch {
    let mut m = LineMatch {
        invoice_line_id: Uuid::nil(),
        status: LineStatus::Ok,
        issues: vec![],
        ordered_quantity: None,
        received_quantity: None,
        invoiced_quantity: None,
        line_quantity: input.quantity,
        po_unit_price: None,
        invoice_unit_price: input.unit_price,
        price_variance_pct: None,
    };
    let Some(po) = input.po else {
        m.status = LineStatus::NoPoLine;
        m.issues.push(LineStatus::NoPoLine);
        return m;
    };
    let invoiced = input.other_invoiced + input.quantity;
    m.ordered_quantity = Some(po.ordered);
    m.received_quantity = Some(po.received);
    m.invoiced_quantity = Some(invoiced);
    m.po_unit_price = Some(po.unit_price);

    if invoiced > po.received {
        m.issues.push(LineStatus::NotReceived);
    }
    if invoiced > po.ordered * (Decimal::ONE + tol.quantity_pct / hundred()) {
        m.issues.push(LineStatus::OverInvoiced);
    }
    let diff = (input.unit_price - po.unit_price).abs();
    let pct = if po.unit_price.is_zero() {
        if diff.is_zero() {
            Decimal::ZERO
        } else {
            hundred()
        }
    } else {
        (input.unit_price - po.unit_price) / po.unit_price * hundred()
    };
    m.price_variance_pct = Some(pct.round_dp(4));
    if diff > po.unit_price * tol.price_pct / hundred() {
        m.issues.push(LineStatus::PriceVariance);
    }
    if let Some(first) = m.issues.first() {
        m.status = *first;
    }
    m
}

/// Matches a whole invoice: matched only when there is a line and every line is ok.
pub fn match_invoice(inputs: &[LineInput], tol: &Tolerance) -> MatchReport {
    let lines: Vec<LineMatch> = inputs.iter().map(|i| match_line(i, tol)).collect();
    MatchReport {
        matched: !lines.is_empty() && lines.iter().all(|l| l.status == LineStatus::Ok),
        quantity_tolerance_pct: tol.quantity_pct,
        price_tolerance_pct: tol.price_pct,
        lines,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use rust_decimal_macros::dec;

    const TOL: Tolerance = Tolerance {
        quantity_pct: dec!(0),
        price_pct: dec!(2),
    };

    fn line(received: Decimal, qty: Decimal, price: Decimal, other: Decimal) -> LineInput {
        LineInput {
            po: Some(PoFigures {
                ordered: dec!(10),
                received,
                unit_price: dec!(12.50),
            }),
            quantity: qty,
            unit_price: price,
            other_invoiced: other,
        }
    }

    #[test]
    fn perfect_match_is_ok() {
        let m = match_line(&line(dec!(10), dec!(10), dec!(12.50), dec!(0)), &TOL);
        assert_eq!(m.status, LineStatus::Ok);
        assert!(m.issues.is_empty());
        assert_eq!(m.invoiced_quantity, Some(dec!(10)));
        assert_eq!(m.price_variance_pct, Some(dec!(0)));
    }

    #[test]
    fn invoicing_more_than_received_is_not_received() {
        let m = match_line(&line(dec!(4), dec!(10), dec!(12.50), dec!(0)), &TOL);
        assert_eq!(m.status, LineStatus::NotReceived);
        assert_eq!(m.received_quantity, Some(dec!(4)));
    }

    #[test]
    fn invoicing_more_than_ordered_is_over_invoiced_unless_within_tolerance() {
        // Ten ordered and eleven received; invoicing eleven exceeds the order.
        let m = match_line(&line(dec!(11), dec!(11), dec!(12.50), dec!(0)), &TOL);
        assert_eq!(m.status, LineStatus::OverInvoiced);
        let loose = Tolerance {
            quantity_pct: dec!(10),
            price_pct: dec!(2),
        };
        let m = match_line(&line(dec!(11), dec!(11), dec!(12.50), dec!(0)), &loose);
        assert_eq!(m.status, LineStatus::Ok);
    }

    #[test]
    fn price_variance_respects_the_tolerance_both_ways() {
        // 2 % of 12.50 is 0.25: 12.75 and 12.25 are on the edge and pass.
        for p in [dec!(12.75), dec!(12.25)] {
            let m = match_line(&line(dec!(10), dec!(10), p, dec!(0)), &TOL);
            assert_eq!(m.status, LineStatus::Ok, "{p}");
        }
        for p in [dec!(12.76), dec!(12.00)] {
            let m = match_line(&line(dec!(10), dec!(10), p, dec!(0)), &TOL);
            assert_eq!(m.status, LineStatus::PriceVariance, "{p}");
        }
        let m = match_line(&line(dec!(10), dec!(10), dec!(13.75), dec!(0)), &TOL);
        assert_eq!(m.price_variance_pct, Some(dec!(10)));
    }

    #[test]
    fn partial_invoices_add_up_against_the_order_line() {
        // Six invoiced elsewhere, four now: ten in total of ten received.
        let m = match_line(&line(dec!(10), dec!(4), dec!(12.50), dec!(6)), &TOL);
        assert_eq!(m.status, LineStatus::Ok);
        // A further two on top of that is more than ordered and received.
        let m = match_line(&line(dec!(10), dec!(2), dec!(12.50), dec!(10)), &TOL);
        assert_eq!(m.status, LineStatus::NotReceived);
        assert_eq!(
            m.issues,
            vec![LineStatus::NotReceived, LineStatus::OverInvoiced]
        );
    }

    #[test]
    fn free_text_lines_are_flagged_and_zero_prices_are_handled() {
        let free = LineInput {
            po: None,
            quantity: dec!(1),
            unit_price: dec!(5),
            other_invoiced: dec!(0),
        };
        assert_eq!(match_line(&free, &TOL).status, LineStatus::NoPoLine);
        let zero = LineInput {
            po: Some(PoFigures {
                ordered: dec!(1),
                received: dec!(1),
                unit_price: dec!(0),
            }),
            quantity: dec!(1),
            unit_price: dec!(0.01),
            other_invoiced: dec!(0),
        };
        let m = match_line(&zero, &TOL);
        assert_eq!(m.status, LineStatus::PriceVariance);
        assert_eq!(m.price_variance_pct, Some(dec!(100)));
    }

    #[test]
    fn invoice_matches_only_when_all_lines_are_ok_and_there_is_one() {
        assert!(!match_invoice(&[], &TOL).matched);
        let ok = line(dec!(10), dec!(10), dec!(12.50), dec!(0));
        let bad = line(dec!(0), dec!(10), dec!(12.50), dec!(0));
        assert!(match_invoice(&[ok], &TOL).matched);
        let r = match_invoice(&[ok, bad], &TOL);
        assert!(!r.matched);
        assert_eq!(r.lines[1].status, LineStatus::NotReceived);
    }
}
