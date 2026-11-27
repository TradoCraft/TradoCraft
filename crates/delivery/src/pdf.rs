//! The delivery note document: data for `templates/delivery_note.typ`, in the language of the
//! customer unless another one is asked for.

use axum::extract::{Path, Query, State};
use axum::http::header;
use axum::response::{IntoResponse, Response};
use serde::{Deserialize, Serialize};
use tradocraft_core::company::get_company;
use tradocraft_core::{AppError, AppResult, AppState, CurrentUser, Permission};
use tradocraft_documents::{format_date, format_number};
use utoipa::IntoParams;
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::notes::{load_note, DeliveryNote};

type ErrorBody = tradocraft_core::error::ErrorBody;

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
    order_position: i32,
    code: String,
    description: String,
    quantity: String,
    unit: String,
    /// Lot or serial number, when the product is tracked.
    tracking: String,
}

#[derive(Serialize)]
struct Doc {
    language: String,
    /// A planned note is a preview: it has not shipped yet.
    planned: bool,
    number: String,
    order_number: String,
    customer_reference: String,
    date: String,
    carrier: String,
    tracking_number: String,
    notes: String,
    company: Party,
    ship_to: Party,
    lines: Vec<DocLine>,
}

fn document(
    company: &tradocraft_core::company::Company,
    note: &DeliveryNote,
    customer_reference: String,
    language: &str,
) -> Doc {
    let city_line = |postal: &str, city: &str| format!("{postal} {city}").trim().to_string();
    Doc {
        language: language.to_string(),
        planned: note.status != "shipped",
        number: note.number.clone(),
        order_number: note.order_number.clone(),
        customer_reference,
        date: note
            .shipped_at
            .map(|t| format_date(t.date_naive()))
            .or_else(|| note.planned_date.map(format_date))
            .unwrap_or_default(),
        carrier: note.carrier.clone(),
        tracking_number: note.tracking_number.clone(),
        notes: note.notes.clone(),
        company: Party {
            name: company.name.clone(),
            street: company.street.clone(),
            city_line: city_line(&company.postal_code, &company.city),
            country_code: company.country_code.clone(),
            contact: [company.phone.clone(), company.email.clone()]
                .into_iter()
                .flatten()
                .collect::<Vec<_>>()
                .join(" · "),
            vat_number: company.vat_number.clone().unwrap_or_default(),
        },
        ship_to: Party {
            name: note.ship_to.name.clone(),
            street: note.ship_to.street.clone(),
            city_line: city_line(&note.ship_to.postal_code, &note.ship_to.city),
            country_code: note.ship_to.country_code.clone(),
            contact: String::new(),
            vat_number: String::new(),
        },
        lines: note
            .lines
            .iter()
            .map(|l| DocLine {
                position: l.position,
                order_position: l.order_position,
                code: l.product_code.clone(),
                description: l.product_name.clone(),
                quantity: format_number(l.quantity),
                unit: l.unit.clone(),
                tracking: l
                    .serial_number
                    .clone()
                    .or_else(|| l.lot_number.clone())
                    .unwrap_or_default(),
            })
            .collect(),
    }
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct PdfParams {
    /// nl | fr | en | de | es; default: the language of the customer.
    pub lang: Option<String>,
}

/// The delivery note as a PDF. A planned note is a preview; a shipped one is the final document.
#[utoipa::path(get, path = "/deliveries/{id}/pdf", tag = "delivery",
    params(("id" = Uuid, Path), PdfParams),
    responses((status = 200, content_type = "application/pdf"), (status = 404, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn delivery_pdf(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Query(p): Query<PdfParams>,
) -> AppResult<Response> {
    user.require(Permission::DeliveryRead)?;
    let mut conn = state.db.acquire().await?;
    let note = load_note(&mut conn, user.company_id, id).await?;
    let customer =
        tradocraft_crm::get_customer(&mut *conn, user.company_id, note.customer_id).await?;
    let reference: String =
        sqlx::query_scalar("SELECT customer_reference FROM sales.orders WHERE id = $1")
            .bind(note.order_id)
            .fetch_one(&mut *conn)
            .await?;
    let company = get_company(&mut *conn, user.company_id).await?;
    drop(conn);
    let language = match p.lang.as_deref().map(str::to_lowercase) {
        Some(l) if tradocraft_core::is_language(&l) => l,
        Some(_) => {
            return Err(AppError::Validation(
                "lang must be an ISO 639-1 language code".to_string(),
            ))
        }
        None => customer.language.clone(),
    };
    let doc = document(&company, &note, reference, &language);
    let bytes = tradocraft_documents::render_pdf(&state.documents, "delivery_note", &doc).await?;
    Ok((
        [
            (header::CONTENT_TYPE, "application/pdf".to_string()),
            (
                header::CONTENT_DISPOSITION,
                format!("inline; filename=\"{}.pdf\"", note.number),
            ),
        ],
        bytes,
    )
        .into_response())
}

/// The PDF route.
pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new().routes(routes!(delivery_pdf))
}
