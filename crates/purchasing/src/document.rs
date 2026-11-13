//! The purchase order as a document (ADR 0061): data for `templates/purchase_order.typ`, the mail
//! that carries it, and sending an approved order to the supplier.

use std::collections::HashMap;

use serde::{Deserialize, Serialize};
use sqlx::PgConnection;
use tradocraft_core::company::{get_company, Company};
use tradocraft_core::mail::{self, Attachment};
use tradocraft_core::{AppError, AppResult, AppState, CurrentUser};
use tradocraft_documents::{format_amount, format_date, format_number, format_unit_price};
use utoipa::ToSchema;
use uuid::Uuid;

use crate::orders::{self, PurchaseOrderDetail};
use crate::suppliers::{self, normalize_language, Supplier};

#[derive(Serialize)]
struct Party {
    name: String,
    street: String,
    city_line: String,
    country_code: String,
    contact: String,
    vat_number: String,
}

#[derive(Serialize)]
struct DocLine {
    position: i32,
    code: String,
    supplier_code: String,
    description: String,
    quantity: String,
    unit: String,
    unit_price: String,
    total: String,
}

#[derive(Serialize)]
struct Doc {
    language: String,
    /// `preview` for an order that has not gone to the supplier, `cancelled`, or empty.
    watermark: String,
    number: String,
    date: String,
    expected_date: String,
    currency: String,
    payment_terms_days: i32,
    notes: String,
    company: Party,
    supplier: Party,
    /// Where the goods go: the company.
    deliver_to: Party,
    subtotal: String,
    tax_total: String,
    total: String,
    lines: Vec<DocLine>,
}

/// The stock unit of each product, for the quantity column.
async fn units(conn: &mut PgConnection, ids: &[Uuid]) -> AppResult<HashMap<Uuid, String>> {
    let rows: Vec<(Uuid, String)> =
        sqlx::query_as("SELECT id, unit FROM products.products WHERE id = ANY($1)")
            .bind(ids)
            .fetch_all(conn)
            .await?;
    Ok(rows.into_iter().collect())
}

fn watermark(status: &str) -> &'static str {
    match status {
        "draft" | "approved" => "preview",
        "cancelled" => "cancelled",
        _ => "",
    }
}

fn company_party(company: &Company) -> Party {
    Party {
        name: company.name.clone(),
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
        vat_number: company.vat_number.clone().unwrap_or_default(),
    }
}

fn document(
    company: &Company,
    po: &PurchaseOrderDetail,
    supplier: &Supplier,
    units: &HashMap<Uuid, String>,
    language: &str,
) -> Doc {
    let s = &po.summary;
    Doc {
        language: language.to_string(),
        watermark: watermark(&s.status).to_string(),
        number: s.number.clone(),
        date: format_date(s.order_date),
        expected_date: s
            .expected_delivery_date
            .map(format_date)
            .unwrap_or_default(),
        currency: s.currency.clone(),
        payment_terms_days: supplier.payment_terms_days,
        notes: s.notes.clone(),
        company: company_party(company),
        // Suppliers carry no postal address yet: name, contact person, country and tax number.
        supplier: Party {
            name: supplier.name.clone(),
            street: supplier.contact_person.clone(),
            city_line: String::new(),
            country_code: supplier.country.clone(),
            contact: [supplier.phone.clone(), supplier.email.clone()]
                .into_iter()
                .filter(|v| !v.is_empty())
                .collect::<Vec<_>>()
                .join(" · "),
            vat_number: supplier.tax_id.clone(),
        },
        deliver_to: company_party(company),
        subtotal: format_amount(s.subtotal),
        tax_total: format_amount(s.tax_total),
        total: format_amount(s.total),
        lines: po
            .lines
            .iter()
            .map(|l| DocLine {
                position: l.line_number,
                code: l.product_code.clone(),
                supplier_code: l.supplier_product_code.clone(),
                description: if l.description.is_empty() {
                    l.product_name.clone()
                } else {
                    l.description.clone()
                },
                quantity: format_number(l.quantity),
                unit: units.get(&l.product_id).cloned().unwrap_or_default(),
                unit_price: format_unit_price(l.unit_price),
                total: format_amount(l.line_total),
            })
            .collect(),
    }
}

/// Renders the purchase order in `language`.
pub async fn render(
    state: &AppState,
    conn: &mut PgConnection,
    company_id: Uuid,
    po: &PurchaseOrderDetail,
    supplier: &Supplier,
    language: &str,
) -> AppResult<Vec<u8>> {
    let company = get_company(&mut *conn, company_id).await?;
    let ids: Vec<Uuid> = po.lines.iter().map(|l| l.product_id).collect();
    let units = units(conn, &ids).await?;
    let doc = document(&company, po, supplier, &units, language);
    Ok(tradocraft_documents::render_pdf(&state.documents, "purchase_order", &doc).await?)
}

/// The file name of the PDF: the order number.
pub fn pdf_filename(po: &PurchaseOrderDetail) -> String {
    format!("{}.pdf", po.summary.number)
}

/// Subject and body of the mail that carries the purchase order.
pub fn mail_text(
    language: &str,
    company: &str,
    supplier: &str,
    number: &str,
    expected: Option<&str>,
) -> (String, String) {
    let when = |nl: &str| {
        expected
            .map(|d| format!("{nl} {d}.\n\n"))
            .unwrap_or_default()
    };
    match language {
        "nl" => (
            format!("Bestelbon {number}"),
            format!(
                "Geachte {supplier},\n\nIn bijlage vindt u onze bestelbon {number}. {}Gelieve de ontvangst en de leverdatum te bevestigen.\n\nMet vriendelijke groeten\n{company}\n",
                when("Gewenste leverdatum:")
            ),
        ),
        "fr" => (
            format!("Bon de commande {number}"),
            format!(
                "Bonjour {supplier},\n\nVeuillez trouver ci-joint notre bon de commande {number}. {}Merci de nous en accuser réception et de confirmer la date de livraison.\n\nCordialement\n{company}\n",
                when("Date de livraison souhaitée :")
            ),
        ),
        "de" => (
            format!("Bestellung {number}"),
            format!(
                "Guten Tag {supplier},\n\nanbei erhalten Sie unsere Bestellung {number}. {}Bitte bestätigen Sie den Erhalt und den Liefertermin.\n\nMit freundlichen Grüßen\n{company}\n",
                when("Gewünschter Liefertermin:")
            ),
        ),
        "es" => (
            format!("Pedido de compra {number}"),
            format!(
                "Estimado proveedor ({supplier}),\n\nAdjuntamos nuestro pedido de compra {number}. {}Le rogamos que confirme la recepción y la fecha de entrega.\n\nAtentamente\n{company}\n",
                when("Fecha de entrega deseada:")
            ),
        ),
        _ => (
            format!("Purchase order {number}"),
            format!(
                "Dear {supplier},\n\nPlease find attached our purchase order {number}. {}Kindly confirm receipt and the delivery date.\n\nKind regards\n{company}\n",
                when("Requested delivery date:")
            ),
        ),
    }
}

/// A plausible address: one `@` with something on both sides and no spaces. Delivery problems are
/// the mail server's to report.
fn plausible_address(a: &str) -> bool {
    match a.split_once('@') {
        Some((local, domain)) => {
            !local.is_empty()
                && domain.contains('.')
                && !domain.starts_with('.')
                && !domain.ends_with('.')
                && !a.contains(char::is_whitespace)
                && !domain.contains('@')
        }
        None => false,
    }
}

/// Who the order goes to and in which language, when they differ from the supplier's own.
#[derive(Debug, Clone, Default, Deserialize, ToSchema)]
pub struct SendPurchaseOrderInput {
    /// Default: the supplier's e-mail address.
    pub to: Option<String>,
    /// nl | fr | en | de | es. Default: the supplier's language.
    pub lang: Option<String>,
}

/// Sends an approved order: it becomes `sent`, the PDF is rendered in the supplier's language and
/// queued as an e-mail for the worker, all in one transaction. Refused (409) when there is no
/// address to send it to, and nothing changes.
pub async fn send(
    state: &AppState,
    user: &CurrentUser,
    id: Uuid,
    input: SendPurchaseOrderInput,
) -> AppResult<PurchaseOrderDetail> {
    let mut tx = state.db.begin().await?;
    orders::lock(&mut tx, user.company_id, id).await?;
    let po = orders::load(&mut tx, user.company_id, id).await?;
    orders::require_sendable(&po)?;
    let supplier = suppliers::load(&mut tx, user.company_id, po.summary.supplier_id).await?;

    let to = match input.to.as_deref().map(str::trim).filter(|t| !t.is_empty()) {
        Some(t) if plausible_address(t) => t.to_string(),
        Some(_) => return Err(AppError::Validation("to must be an e-mail address".into())),
        None if plausible_address(supplier.email.trim()) => supplier.email.trim().to_string(),
        None => {
            return Err(AppError::Conflict(format!(
                "supplier {} has no usable e-mail address; enter one to send the order to",
                supplier.name
            )))
        }
    };
    let language = match input.lang {
        Some(l) => normalize_language(&l)?,
        None => supplier.language.clone(),
    };

    let sent = orders::send(&mut tx, user, id, &to).await?;
    let pdf = render(state, &mut tx, user.company_id, &sent, &supplier, &language).await?;
    let company = get_company(&mut *tx, user.company_id).await?;
    let (subject, body) = mail_text(
        &language,
        &company.name,
        &supplier.name,
        &sent.summary.number,
        sent.summary
            .expected_delivery_date
            .map(format_date)
            .as_deref(),
    );
    mail::enqueue_with_attachment(
        &mut tx,
        user.company_id,
        &to,
        &subject,
        &body,
        Attachment {
            filename: &pdf_filename(&sent),
            content_type: "application/pdf",
            data: &pdf,
        },
    )
    .await?;
    tx.commit().await?;
    Ok(sent)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn addresses() {
        assert!(plausible_address("buyer@example.com"));
        assert!(plausible_address("a.b+c@sub.example.be"));
        for bad in [
            "",
            "nobody",
            "@example.com",
            "a@",
            "a@example",
            "a b@example.com",
            "a@@example.com",
            "a@.com",
        ] {
            assert!(!plausible_address(bad), "{bad}");
        }
    }

    #[test]
    fn mail_is_written_in_each_language() {
        for lang in tradocraft_core::LANGUAGES {
            let (subject, body) =
                mail_text(lang, "Acme", "Motors", "PO2027-00001", Some("20/01/2027"));
            assert!(subject.contains("PO2027-00001"), "{lang}");
            assert!(body.contains("Motors") && body.contains("Acme"), "{lang}");
            assert!(body.contains("20/01/2027"), "{lang}");
            let (_, without) = mail_text(lang, "Acme", "Motors", "PO2027-00001", None);
            assert!(!without.contains("20/01/2027"), "{lang}");
        }
    }
}
