//! The purchase order document (data for `templates/purchase_order.typ`) and the e-mail that
//! carries it to the supplier.
//!
//! A supplier has no language of its own yet, so the document and the mail use the language
//! asked for (`?lang=` on the PDF route) or else the company's default language.

use serde::Serialize;
use sqlx::PgConnection;
use tradocraft_core::company::{get_company, Company};
use tradocraft_core::mail::{self, Attachment};
use tradocraft_core::{audit, AppResult, CurrentUser, DocumentConfig};
use tradocraft_documents::{format_amount, format_date, format_number, format_unit_price};

use crate::orders::PurchaseOrderDetail;
use crate::suppliers::{self, Supplier};

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
    /// The supplier's own code for the product, when known.
    supplier_code: String,
    description: String,
    quantity: String,
    unit_price: String,
    total: String,
}

#[derive(Serialize)]
pub struct Doc {
    language: String,
    /// draft | approved | sent | partially_received | received | cancelled. A draft is a preview
    /// and a cancelled order says so on every page.
    status: String,
    number: String,
    date: String,
    expected_delivery: String,
    currency: String,
    payment_terms_days: String,
    notes: String,
    company: Party,
    supplier: Party,
    lines: Vec<DocLine>,
    subtotal: String,
    /// Empty when the order carries no tax.
    tax_total: String,
    total: String,
}

/// The data the template receives.
pub fn document(
    company: &Company,
    supplier: &Supplier,
    po: &PurchaseOrderDetail,
    language: &str,
) -> Doc {
    let s = &po.summary;
    let city_line = |postal: &str, city: &str| format!("{postal} {city}").trim().to_string();
    let join = |parts: Vec<Option<String>>| {
        parts
            .into_iter()
            .flatten()
            .filter(|p| !p.is_empty())
            .collect::<Vec<_>>()
            .join(" · ")
    };
    Doc {
        language: language.to_string(),
        status: s.status.clone(),
        number: s.number.clone(),
        date: format_date(s.order_date),
        expected_delivery: s
            .expected_delivery_date
            .map(format_date)
            .unwrap_or_default(),
        currency: s.currency.clone(),
        payment_terms_days: if supplier.payment_terms_days > 0 {
            supplier.payment_terms_days.to_string()
        } else {
            String::new()
        },
        notes: s.notes.clone(),
        company: Party {
            name: company.name.clone(),
            street: company.street.clone(),
            city_line: city_line(&company.postal_code, &company.city),
            country_code: company.country_code.clone(),
            contact: join(vec![company.phone.clone(), company.email.clone()]),
            vat_number: company.vat_number.clone().unwrap_or_default(),
        },
        // Suppliers carry no postal address yet: name, country and contact details are what we have.
        supplier: Party {
            name: supplier.name.clone(),
            street: String::new(),
            city_line: String::new(),
            country_code: supplier.country.clone(),
            contact: join(vec![
                Some(supplier.contact_person.clone()),
                Some(supplier.email.clone()),
                Some(supplier.phone.clone()),
            ]),
            vat_number: supplier.tax_id.clone(),
        },
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
                unit_price: format_unit_price(l.unit_price),
                total: format_amount(l.line_total),
            })
            .collect(),
        subtotal: format_amount(s.subtotal),
        tax_total: if s.tax_total.is_zero() {
            String::new()
        } else {
            format_amount(s.tax_total)
        },
        total: format_amount(s.total),
    }
}

/// Renders the purchase order to PDF.
pub async fn render(
    documents: &DocumentConfig,
    company: &Company,
    supplier: &Supplier,
    po: &PurchaseOrderDetail,
    language: &str,
) -> anyhow::Result<Vec<u8>> {
    let doc = document(company, supplier, po, language);
    tradocraft_documents::render_pdf(documents, "purchase_order", &doc).await
}

/// File name of the PDF, e.g. `PO2027-00001.pdf`.
pub fn pdf_filename(po: &PurchaseOrderDetail) -> String {
    format!("{}.pdf", po.summary.number)
}

/// Subject and body of the e-mail that carries the purchase order.
pub fn order_mail(
    language: &str,
    company: &str,
    supplier: &str,
    number: &str,
    expected_delivery: &str,
) -> (String, String) {
    let when = |label: &str| {
        if expected_delivery.is_empty() {
            String::new()
        } else {
            format!("{label} {expected_delivery}.")
        }
    };
    let (subject, body) = match language {
        "nl" => (
            format!("Bestelling {number}"),
            format!(
                "Geachte {supplier},\n\nIn bijlage vindt u onze bestelling {number}. {} Gelieve de ontvangst te bevestigen en ons te verwittigen als de leveringstermijn niet haalbaar is.\n\nMet vriendelijke groeten\n{company}\n",
                when("Gewenste leverdatum:")
            ),
        ),
        "fr" => (
            format!("Commande {number}"),
            format!(
                "Bonjour {supplier},\n\nVeuillez trouver ci-joint notre commande {number}. {} Merci de nous en accuser réception et de nous prévenir si le délai n'est pas tenable.\n\nCordialement\n{company}\n",
                when("Date de livraison souhaitée :")
            ),
        ),
        "de" => (
            format!("Bestellung {number}"),
            format!(
                "Guten Tag {supplier},\n\nanbei erhalten Sie unsere Bestellung {number}. {} Bitte bestätigen Sie den Eingang und informieren Sie uns, falls der Termin nicht einzuhalten ist.\n\nMit freundlichen Grüßen\n{company}\n",
                when("Gewünschter Liefertermin:")
            ),
        ),
        "es" => (
            format!("Pedido {number}"),
            format!(
                "Estimado proveedor ({supplier}),\n\nAdjuntamos nuestro pedido {number}. {} Le rogamos que confirme la recepción y que nos avise si el plazo no es viable.\n\nAtentamente\n{company}\n",
                when("Fecha de entrega deseada:")
            ),
        ),
        _ => (
            format!("Purchase order {number}"),
            format!(
                "Dear {supplier},\n\nPlease find attached our purchase order {number}. {} Kindly confirm receipt and let us know if the delivery date cannot be met.\n\nKind regards\n{company}\n",
                when("Requested delivery date:")
            ),
        ),
    };
    // No double space when there is no delivery date.
    (subject, body.replace(".  ", ". "))
}

/// Queues the purchase order as a PDF e-mail to the supplier, in the company's default language,
/// and records it in the audit trail. Returns the address, or `None` when the supplier has no
/// e-mail address: the order is still sent and the PDF can be downloaded and handed over by hand.
pub async fn mail_to_supplier(
    conn: &mut PgConnection,
    documents: &DocumentConfig,
    user: &CurrentUser,
    po: &PurchaseOrderDetail,
) -> AppResult<Option<String>> {
    let supplier = suppliers::load(conn, user.company_id, po.summary.supplier_id).await?;
    let to = supplier.email.trim().to_string();
    if to.is_empty() {
        return Ok(None);
    }
    let company = get_company(&mut *conn, user.company_id).await?;
    let language = company.default_language.clone();
    let pdf = render(documents, &company, &supplier, po, &language).await?;
    let expected = po
        .summary
        .expected_delivery_date
        .map(format_date)
        .unwrap_or_default();
    let (subject, body) = order_mail(
        &language,
        &company.name,
        if supplier.contact_person.is_empty() {
            &supplier.name
        } else {
            &supplier.contact_person
        },
        &po.summary.number,
        &expected,
    );
    mail::enqueue_with_attachment(
        conn,
        user.company_id,
        &to,
        &subject,
        &body,
        Attachment {
            filename: &pdf_filename(po),
            content_type: "application/pdf",
            data: &pdf,
        },
    )
    .await?;
    audit::record(
        conn,
        user,
        "purchase_order",
        po.summary.id,
        "mailed",
        serde_json::json!({ "number": po.summary.number, "to": to }),
    )
    .await?;
    Ok(Some(to))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_language_has_a_subject_and_names_the_order() {
        for lang in ["nl", "fr", "en", "de", "es", "xx"] {
            let (subject, body) = order_mail(lang, "Acme", "Voltaic", "PO2027-00001", "");
            assert!(subject.contains("PO2027-00001"), "{lang}");
            assert!(body.contains("Acme") && body.contains("Voltaic"), "{lang}");
            assert!(!body.contains(".  "), "{lang}: double space");
        }
    }

    #[test]
    fn the_delivery_date_is_mentioned_only_when_known() {
        let (_, with) = order_mail("en", "Acme", "Voltaic", "PO1", "04/05/2027");
        assert!(with.contains("Requested delivery date: 04/05/2027."));
        let (_, without) = order_mail("en", "Acme", "Voltaic", "PO1", "");
        assert!(!without.contains("delivery date:"));
    }
}
