//! Data handed to `templates/quotation.typ`. All values are pre-formatted strings.
//!
//! Lines are handed over twice: flat in position order (`lines`, for simple templates) and grouped
//! by section (`groups`). A sub-line without its own section belongs to its parent's section;
//! sections appear in the order of their first line, and lines keep their position order within a
//! section. `level` is the depth below a parent line (0 for a top-level line).

use serde::Serialize;
use tradocraft_core::company::Company;
use tradocraft_documents::{format_amount, format_date, format_number, format_unit_price};

use rust_decimal::Decimal;

use crate::model::{Quotation, QuotationLine};

#[derive(Serialize)]
pub struct Doc {
    pub language: String,
    pub draft: bool,
    pub number: String,
    pub revision: i32,
    pub quote_date: String,
    pub valid_until: String,
    pub currency: String,
    pub notes: String,
    pub company: Party,
    pub customer: Party,
    pub lines: Vec<Line>,
    /// The lines grouped by section, in the order the sections first appear.
    pub groups: Vec<Group>,
    /// Some line still has an unconfirmed (indicative) price: the template explains the marker.
    pub has_indicative: bool,
    /// VAT is charged: only for customers with the `domestic` regime. Otherwise the document
    /// shows no VAT column and no VAT amounts, and says why (`vat_regime`).
    pub show_vat: bool,
    pub vat_regime: String,
    pub vat_groups: Vec<Vat>,
    pub subtotal: String,
    pub vat_total: String,
    pub total: String,
    pub iban: String,
}

#[derive(Serialize)]
pub struct Party {
    pub name: String,
    pub vat_number: String,
    pub street: String,
    pub city_line: String,
    pub country_code: String,
    pub contact: String,
}

#[derive(Serialize)]
pub struct Line {
    pub code: String,
    pub description: String,
    pub quantity: String,
    pub unit: String,
    pub unit_price: String,
    pub discount: String,
    /// Net-priced line: the template prints its own word for "net".
    pub net: bool,
    pub vat_rate: String,
    pub total: String,
    /// Section heading ("" for none), after inheriting the parent's.
    pub section: String,
    /// Depth below a parent line: 0 for a top-level line, 1 for an option of it, ...
    pub level: usize,
    pub comment: String,
    /// Remark for the customer, printed under the description. The production remark is internal
    /// and deliberately not part of the document data.
    pub customer_remark: String,
    /// "20 %" when the line is priced as a percentage of its parent line, else "".
    pub percent_of_parent: String,
    /// The price is an indicative suggestion still to be confirmed (only on drafts).
    pub indicative: bool,
}

#[derive(Serialize)]
pub struct Group {
    /// "" for the lines without a section.
    pub title: String,
    pub lines: Vec<Line>,
    /// Sum of the line totals of the section.
    pub subtotal: String,
}

#[derive(Serialize)]
pub struct Vat {
    pub rate: String,
    pub base: String,
    pub vat: String,
}

/// Section (inherited from the parent when a line has none) and depth of each line, by index.
fn structure(lines: &[QuotationLine]) -> Vec<(String, usize)> {
    let by_position: std::collections::HashMap<i32, usize> = lines
        .iter()
        .enumerate()
        .map(|(i, l)| (l.position, i))
        .collect();
    let index_of = |pos: i32| by_position.get(&pos).copied();
    lines
        .iter()
        .map(|l| {
            let mut section = l.section.clone();
            let mut level = 0;
            let mut parent = l.parent_position.and_then(index_of);
            // Bounded walk: a malformed chain can never loop forever.
            while let Some(pi) = parent {
                level += 1;
                if section.is_none() {
                    section = lines[pi].section.clone();
                }
                if level > lines.len() {
                    break;
                }
                parent = lines[pi].parent_position.and_then(index_of);
            }
            (section.unwrap_or_default(), level)
        })
        .collect()
}

fn line(l: &QuotationLine, section: String, level: usize) -> Line {
    // The document shows one combined discount (rebate and line discount), consistent
    // with the net line total. Net-priced lines are marked as such.
    let net = l.pricing_type == "net" || l.rebate_source == "net";
    // A negative rebate is a surcharge: the document shows only the resulting price, not the
    // (lower) list price it was derived from.
    let hundred = Decimal::ONE_HUNDRED;
    let factor = (hundred - l.rebate_percent) * (hundred - l.line_discount_percent) / hundred;
    let surcharge = !net && (l.rebate_percent < Decimal::ZERO || factor > hundred);
    let combined = if net || surcharge {
        String::new()
    } else if !l.rebate_percent.is_zero() || !l.line_discount_percent.is_zero() {
        format!("{} %", format_number((hundred - factor).round_dp(2)))
    } else {
        String::new()
    };
    Line {
        code: l.product_code.clone(),
        description: l.description.clone(),
        quantity: format_number(l.quantity),
        unit: l.unit.clone(),
        unit_price: format_unit_price(if surcharge {
            l.net_unit_price
        } else {
            l.list_unit_price
        }),
        discount: combined,
        net,
        vat_rate: format!("{} %", format_number(l.vat_rate)),
        total: format_amount(l.line_total),
        section,
        level,
        comment: l.comment.clone().unwrap_or_default(),
        customer_remark: l.customer_remark.clone(),
        percent_of_parent: l
            .percent_of_parent
            .map(|p| format!("{} %", format_number(p.normalize())))
            .unwrap_or_default(),
        indicative: !l.price_confirmed,
    }
}

fn groups(lines: &[QuotationLine]) -> Vec<Group> {
    let shape = structure(lines);
    let mut out: Vec<(String, Vec<Line>, Decimal)> = Vec::new();
    for (l, (section, level)) in lines.iter().zip(shape) {
        let i = match out.iter().position(|g| g.0 == section) {
            Some(i) => i,
            None => {
                out.push((section.clone(), Vec::new(), Decimal::ZERO));
                out.len() - 1
            }
        };
        out[i].2 += l.line_total;
        out[i].1.push(line(l, section, level));
    }
    out.into_iter()
        .map(|(title, lines, subtotal)| Group {
            title,
            lines,
            subtotal: format_amount(subtotal),
        })
        .collect()
}

pub fn document(company: &Company, q: &Quotation) -> Doc {
    let h = q;
    let shape = structure(&q.lines);
    Doc {
        language: h.customer_language.clone(),
        draft: h.status == "draft",
        number: h.number.clone(),
        revision: h.revision,
        quote_date: format_date(h.quote_date),
        valid_until: format_date(h.valid_until),
        currency: h.currency.clone(),
        notes: h.notes.clone(),
        company: Party {
            name: company.name.clone(),
            vat_number: company.vat_number.clone().unwrap_or_default(),
            street: company.street.clone(),
            city_line: format!("{} {}", company.postal_code, company.city)
                .trim()
                .to_string(),
            country_code: company.country_code.clone(),
            contact: [company.phone.clone(), company.email.clone()]
                .into_iter()
                .flatten()
                .collect::<Vec<_>>()
                .join(" · "),
        },
        customer: Party {
            name: h.customer_name.clone(),
            vat_number: h.customer_vat_number.clone().unwrap_or_default(),
            street: h.customer_street.clone(),
            city_line: format!("{} {}", h.customer_postal_code, h.customer_city)
                .trim()
                .to_string(),
            country_code: h.customer_country_code.clone(),
            contact: String::new(),
        },
        lines: q
            .lines
            .iter()
            .zip(shape)
            .map(|(l, (section, level))| line(l, section, level))
            .collect(),
        groups: groups(&q.lines),
        has_indicative: q.lines.iter().any(|l| !l.price_confirmed),
        show_vat: h.vat_regime == "domestic",
        vat_regime: h.vat_regime.clone(),
        vat_groups: q
            .vat_groups
            .iter()
            .map(|g| Vat {
                rate: format!("{} %", format_number(g.vat_rate)),
                base: format_amount(g.base),
                vat: format_amount(g.vat),
            })
            .collect(),
        subtotal: format_amount(h.subtotal),
        vat_total: format_amount(h.vat_total),
        total: format_amount(h.total),
        iban: company.iban.clone().unwrap_or_default(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use rust_decimal_macros::dec;

    fn l(pos: i32, parent: Option<i32>, section: Option<&str>, total: Decimal) -> QuotationLine {
        QuotationLine {
            position: pos,
            product_id: None,
            product_code: format!("P{pos}"),
            description: String::new(),
            unit: "pcs".into(),
            quantity: dec!(1),
            list_unit_price: total,
            pricing_type: "list".into(),
            rebate_percent: dec!(0),
            rebate_source: "general".into(),
            line_discount_percent: dec!(0),
            net_unit_price: total,
            line_total: total,
            vat_rate: dec!(21),
            price_confirmed: true,
            parent_position: parent,
            section: section.map(str::to_string),
            comment: None,
            percent_of_parent: None,
            percent_base: None,
            production_remark: String::new(),
            customer_remark: String::new(),
            customer_remark_language: None,
            favorite_item_id: None,
        }
    }

    #[test]
    fn sub_lines_inherit_the_section_and_are_indented() {
        let lines = vec![
            l(1, None, Some("Unit"), dec!(100)),
            l(2, Some(1), None, dec!(10)),
            l(3, Some(2), None, dec!(1)),
            l(4, None, None, dec!(5)),
            l(5, Some(1), Some("Options"), dec!(20)),
            l(6, None, Some("Unit"), dec!(50)),
        ];
        let shape = structure(&lines);
        assert_eq!(shape[1], ("Unit".to_string(), 1));
        assert_eq!(shape[2], ("Unit".to_string(), 2));
        assert_eq!(shape[3], (String::new(), 0));
        assert_eq!(shape[4], ("Options".to_string(), 1));
        let g = groups(&lines);
        let titles: Vec<&str> = g.iter().map(|g| g.title.as_str()).collect();
        assert_eq!(titles, ["Unit", "", "Options"]);
        let codes: Vec<&str> = g[0].lines.iter().map(|l| l.code.as_str()).collect();
        assert_eq!(codes, ["P1", "P2", "P3", "P6"]);
        assert_eq!(g[0].subtotal, format_amount(dec!(161)));
    }
}
