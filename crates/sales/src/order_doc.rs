//! The order confirmation document: data for `templates/order_confirmation.typ` and the e-mail
//! text that accompanies it. Both are written in the customer's language.

use rust_decimal::Decimal;
use serde::Serialize;
use tradocraft_core::company::Company;
use tradocraft_documents::{format_amount, format_date, format_number, format_unit_price};
use tradocraft_pricing::{totals, PricedLine, Totals};

use crate::orders::{Order, OrderLine};
use crate::pdf::{Party, Vat};

#[derive(Serialize)]
pub struct Doc {
    pub language: String,
    pub draft: bool,
    pub number: String,
    pub revision: i32,
    pub order_date: String,
    pub customer_reference: String,
    pub quotation_number: String,
    pub currency: String,
    pub company: Party,
    pub customer: Party,
    pub lines: Vec<DocLine>,
    /// False for reverse charge (`intra_eu`, `domestic_reverse_charge`) and export (`outside_eu`).
    pub show_vat: bool,
    pub vat_regime: String,
    pub vat_groups: Vec<Vat>,
    pub subtotal: String,
    pub vat_total: String,
    pub total: String,
    pub iban: String,
}

#[derive(Serialize)]
pub struct DocLine {
    pub code: String,
    pub description: String,
    pub quantity: String,
    pub unit: String,
    pub unit_price: String,
    pub discount: String,
    pub net: bool,
    pub vat_rate: String,
    pub total: String,
    /// Remark for the customer, printed under the description (never the production remark).
    pub customer_remark: String,
}

/// The customer as it was on the quotation the order was made from.
pub struct CustomerSnapshot {
    pub vat_number: Option<String>,
    pub street: String,
    pub postal_code: String,
    pub city: String,
    pub country_code: String,
    pub quotation_number: String,
}

/// VAT groups and totals from stored lines, by the same rules as when they were priced.
pub fn order_totals(lines: &[OrderLine]) -> Totals {
    let priced: Vec<PricedLine> = lines
        .iter()
        .map(|l| PricedLine {
            list_unit_price: l.list_unit_price,
            quantity: l.quantity,
            customer_discount_percent: l.rebate_percent,
            line_discount_percent: l.line_discount_percent,
            net_unit_price: l.net_unit_price,
            line_total: l.line_total,
            vat_rate: l.vat_rate,
        })
        .collect();
    totals(&priced)
}

pub fn document(company: &Company, o: &Order, c: &CustomerSnapshot, language: &str) -> Doc {
    let hundred = Decimal::ONE_HUNDRED;
    Doc {
        language: language.to_string(),
        draft: o.revision_status == "draft",
        number: o.order.number.clone(),
        revision: o.revision,
        order_date: format_date(o.order.order_date),
        customer_reference: o.order.customer_reference.clone(),
        quotation_number: c.quotation_number.clone(),
        currency: o.order.currency.clone(),
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
            name: o.order.customer_name.clone(),
            vat_number: c.vat_number.clone().unwrap_or_default(),
            street: c.street.clone(),
            city_line: format!("{} {}", c.postal_code, c.city).trim().to_string(),
            country_code: c.country_code.clone(),
            contact: String::new(),
        },
        lines: o
            .lines
            .iter()
            .map(|l| {
                let net = l.pricing_type == "net";
                let discount = if net {
                    String::new()
                } else if !l.rebate_percent.is_zero() || !l.line_discount_percent.is_zero() {
                    let factor = (hundred - l.rebate_percent) * (hundred - l.line_discount_percent)
                        / hundred;
                    format!("{} %", format_number((hundred - factor).round_dp(2)))
                } else {
                    String::new()
                };
                DocLine {
                    code: l.product_code.clone(),
                    description: l.description.clone(),
                    quantity: format_number(l.quantity),
                    unit: l.unit.clone(),
                    unit_price: format_unit_price(l.list_unit_price),
                    discount,
                    net,
                    vat_rate: format!("{} %", format_number(l.vat_rate)),
                    total: format_amount(l.line_total),
                    customer_remark: l.customer_remark.clone(),
                }
            })
            .collect(),
        show_vat: !tradocraft_core::vat::vat_exempt_for_regime(&o.order.vat_regime),
        vat_regime: o.order.vat_regime.clone(),
        vat_groups: order_totals(&o.lines)
            .vat_groups
            .iter()
            .map(|g| Vat {
                rate: format!("{} %", format_number(g.vat_rate)),
                base: format_amount(g.base),
                vat: format_amount(g.vat),
            })
            .collect(),
        subtotal: format_amount(o.order.subtotal),
        vat_total: format_amount(o.vat_total),
        total: format_amount(o.order.total),
        iban: company.iban.clone().unwrap_or_default(),
    }
}

/// Subject and body of the e-mail that carries the order confirmation.
pub fn confirmation_mail(
    language: &str,
    company: &str,
    customer: &str,
    number: &str,
    revision: i32,
) -> (String, String) {
    let rev = if revision > 1 {
        format!(" (rev. {revision})")
    } else {
        String::new()
    };
    let (subject, body) = match language {
        "nl" => (
            format!("Orderbevestiging {number}{rev}"),
            format!(
                "Geachte {customer},\n\nIn bijlage vindt u de orderbevestiging {number}{rev}. Gelieve deze na te kijken en te bevestigen. Hebt u opmerkingen, laat het ons dan weten.\n\nMet vriendelijke groeten\n{company}\n"
            ),
        ),
        "fr" => (
            format!("Confirmation de commande {number}{rev}"),
            format!(
                "Bonjour {customer},\n\nVeuillez trouver ci-joint la confirmation de commande {number}{rev}. Merci de la vérifier et de nous la confirmer. Pour toute remarque, n'hésitez pas à nous contacter.\n\nCordialement\n{company}\n"
            ),
        ),
        "de" => (
            format!("Auftragsbestätigung {number}{rev}"),
            format!(
                "Guten Tag {customer},\n\nanbei erhalten Sie die Auftragsbestätigung {number}{rev}. Bitte prüfen und bestätigen Sie diese. Bei Anmerkungen melden Sie sich gerne bei uns.\n\nMit freundlichen Grüßen\n{company}\n"
            ),
        ),
        "es" => (
            format!("Confirmación de pedido {number}{rev}"),
            format!(
                "Estimado cliente ({customer}),\n\nAdjuntamos la confirmación de pedido {number}{rev}. Le rogamos que la revise y la confirme. Si tiene alguna observación, póngase en contacto con nosotros.\n\nAtentamente\n{company}\n"
            ),
        ),
        _ => (
            format!("Order confirmation {number}{rev}"),
            format!(
                "Dear {customer},\n\nPlease find attached order confirmation {number}{rev}. Kindly review and confirm it. If you have any remarks, let us know.\n\nKind regards\n{company}\n"
            ),
        ),
    };
    (subject, body)
}
