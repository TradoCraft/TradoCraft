//! The production order as a traveller PDF for the shop floor (ADR 0062): data for
//! `templates/production_order.typ`. It lists what to build, the components to pick and the
//! operations with room to write down the minutes and tick them off. The internal production
//! remark of the order line is printed; cost never is.

use axum::extract::{Path, Query, State};
use axum::http::header;
use axum::response::{IntoResponse, Response};
use serde::{Deserialize, Serialize};
use tradocraft_core::company::{get_company, user_language, Company};
use tradocraft_core::{AppError, AppResult, AppState, CurrentUser, Permission};
use tradocraft_documents::{format_date, format_number};
use utoipa::IntoParams;
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::orders::{load_order, ProductionOrder};

type ErrorBody = tradocraft_core::error::ErrorBody;

#[derive(Serialize)]
struct DocCompany {
    name: String,
    street: String,
    city_line: String,
    vat_number: String,
}

#[derive(Serialize)]
struct DocComponent {
    position: i32,
    code: String,
    name: String,
    quantity: String,
    unit: String,
    /// none | serial | lot
    tracking: String,
}

#[derive(Serialize)]
struct DocOperation {
    position: i32,
    name: String,
    work_centre: String,
    setup_minutes: String,
    planned_minutes: String,
    planned_start: String,
    planned_end: String,
    notes: String,
}

#[derive(Serialize)]
struct DocSubOrder {
    number: String,
    code: String,
    name: String,
    quantity: String,
    unit: String,
}

#[derive(Serialize)]
struct Doc {
    language: String,
    number: String,
    status: String,
    product_code: String,
    product_name: String,
    quantity: String,
    unit: String,
    /// none | serial | lot: what is written down for the output.
    product_tracking: String,
    bom_revision: i32,
    division: String,
    planned_ready_date: String,
    order_number: String,
    customer: String,
    /// low | normal | expedite
    priority: String,
    parent_number: String,
    notes: String,
    production_remark: String,
    printed: String,
    company: DocCompany,
    components: Vec<DocComponent>,
    operations: Vec<DocOperation>,
    sub_orders: Vec<DocSubOrder>,
}

fn document(company: &Company, po: &ProductionOrder, language: &str) -> Doc {
    let s = &po.summary;
    Doc {
        language: language.to_string(),
        number: s.number.clone(),
        status: s.status.clone(),
        product_code: s.product_code.clone(),
        product_name: s.product_name.clone(),
        quantity: format_number(s.quantity),
        unit: s.unit.clone(),
        product_tracking: s.product_tracking.clone(),
        bom_revision: s.bom_revision,
        division: s.division_name.clone().unwrap_or_default(),
        planned_ready_date: s.planned_ready_date.map(format_date).unwrap_or_default(),
        order_number: s.order_number.clone().unwrap_or_default(),
        customer: s.customer_name.clone().unwrap_or_default(),
        priority: s.priority.clone(),
        parent_number: po.parent_order_number.clone().unwrap_or_default(),
        notes: po.notes.clone(),
        production_remark: po.production_remark.clone().unwrap_or_default(),
        printed: format_date(tradocraft_core::today()),
        company: DocCompany {
            name: company.name.clone(),
            street: company.street.clone(),
            city_line: format!("{} {}", company.postal_code, company.city)
                .trim()
                .to_string(),
            vat_number: company.vat_number.clone().unwrap_or_default(),
        },
        components: po
            .components
            .iter()
            .map(|c| DocComponent {
                position: c.position,
                code: c.component_code.clone(),
                name: c.component_name.clone(),
                quantity: format_number(c.required_quantity),
                unit: c.unit.clone(),
                tracking: c.tracking.clone(),
            })
            .collect(),
        operations: po
            .operations
            .iter()
            .map(|o| DocOperation {
                position: o.position,
                name: o.name.clone(),
                work_centre: format!("{} · {}", o.work_centre_code, o.work_centre_name),
                setup_minutes: o.setup_minutes.to_string(),
                planned_minutes: o.planned_minutes.to_string(),
                planned_start: format_date(o.planned_start),
                planned_end: format_date(o.planned_end),
                notes: o.notes.clone(),
            })
            .collect(),
        sub_orders: po
            .sub_orders
            .iter()
            .map(|c| DocSubOrder {
                number: c.number.clone(),
                code: c.product_code.clone(),
                name: c.product_name.clone(),
                quantity: format_number(c.quantity),
                unit: c.unit.clone(),
            })
            .collect(),
    }
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct ProductionPdfParams {
    /// nl | fr | en | de | es; default: the language of the user, else of the company.
    pub lang: Option<String>,
}

/// The production order as a PDF to print and take to the shop floor.
#[utoipa::path(get, path = "/production-orders/{id}/pdf", tag = "production",
    params(("id" = Uuid, Path), ProductionPdfParams),
    responses((status = 200, content_type = "application/pdf"), (status = 404, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn production_order_pdf(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Query(p): Query<ProductionPdfParams>,
) -> AppResult<Response> {
    user.require(Permission::ProductionRead)?;
    let language = match p.lang.as_deref().map(str::to_lowercase) {
        Some(l) if tradocraft_core::is_language(&l) => Some(l),
        Some(_) => {
            return Err(AppError::Validation(format!(
                "lang must be one of {}",
                tradocraft_core::LANGUAGES.join(", ")
            )))
        }
        None => None,
    };
    let mut conn = state.db.acquire().await?;
    let po = load_order(&mut conn, &user, id).await?;
    let company = get_company(&mut *conn, user.company_id).await?;
    let language = match language {
        Some(l) => l,
        None => user_language(&mut *conn, user.company_id, user.user_id).await?,
    };
    drop(conn);
    let doc = document(&company, &po, &language);
    let bytes =
        tradocraft_documents::render_pdf(&state.documents, "production_order", &doc).await?;
    Ok((
        [
            (header::CONTENT_TYPE, "application/pdf".to_string()),
            (
                header::CONTENT_DISPOSITION,
                format!("inline; filename=\"{}.pdf\"", po.summary.number),
            ),
        ],
        bytes,
    )
        .into_response())
}

/// The PDF route.
pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new().routes(routes!(production_order_pdf))
}
