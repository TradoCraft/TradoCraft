use axum::extract::{Path, Query, State};
use axum::http::header;
use axum::response::{IntoResponse, Response};
use axum::{Extension, Json};
use tradocraft_core::environment::{EnvKind, EnvironmentConfig};
use tradocraft_core::AppError;
use tradocraft_core::{AppResult, AppState, CurrentUser, Permission};
use tradocraft_documents::{format_amount, format_date, format_number, format_unit_price};
use utoipa_axum::{router::OpenApiRouter, routes};
use uuid::Uuid;

use serde::Deserialize;
use utoipa::IntoParams;

use crate::billing::{
    self, BillingDocument, BillingFilter, BillingSummary, CreditDraftInput, InvoiceDraftInput,
    LegacyInvoiceInput,
};

#[derive(Deserialize, IntoParams)]
#[into_params(parameter_in = Query)]
struct BillingListQuery {
    kind: Option<String>,
    status: Option<String>,
    customer_id: Option<Uuid>,
    limit: Option<i64>,
    offset: Option<i64>,
}

impl From<BillingListQuery> for BillingFilter {
    fn from(value: BillingListQuery) -> Self {
        Self {
            kind: value.kind,
            status: value.status,
            customer_id: value.customer_id,
            limit: value.limit,
            offset: value.offset,
        }
    }
}

#[utoipa::path(
    get, path = "/customer-invoices", tag = "customer_billing",
    params(BillingListQuery),
    responses((status = 200, body = Vec<BillingSummary>), (status = 403), (status = 404), (status = 409), (status = 422))
)]
async fn list_customer_documents(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(filter): Query<BillingListQuery>,
) -> AppResult<Json<Vec<BillingSummary>>> {
    user.require(Permission::CustomerBillingRead)?;
    Ok(Json(billing::list(&state.db, &user, filter.into()).await?))
}

#[utoipa::path(
    post, path = "/customer-invoices", tag = "customer_billing",
    request_body = InvoiceDraftInput,
    responses((status = 200, body = BillingDocument), (status = 403), (status = 404), (status = 409), (status = 422))
)]
async fn create_customer_invoice(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<InvoiceDraftInput>,
) -> AppResult<Json<BillingDocument>> {
    user.require(Permission::CustomerBillingWrite)?;
    Ok(Json(
        billing::create_invoice(&state.db, &user, input).await?,
    ))
}

#[utoipa::path(
    post, path = "/customer-invoices/credits", tag = "customer_billing",
    request_body = CreditDraftInput,
    responses((status = 200, body = BillingDocument), (status = 403), (status = 404), (status = 409), (status = 422))
)]
async fn create_customer_credit(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<CreditDraftInput>,
) -> AppResult<Json<BillingDocument>> {
    user.require(Permission::CustomerBillingWrite)?;
    Ok(Json(billing::create_credit(&state.db, &user, input).await?))
}

#[utoipa::path(
    post, path = "/customer-invoices/legacy", tag = "customer_billing",
    request_body = LegacyInvoiceInput,
    responses((status = 200, body = BillingDocument), (status = 403), (status = 404), (status = 409), (status = 422))
)]
async fn register_legacy_customer_invoice(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<LegacyInvoiceInput>,
) -> AppResult<Json<BillingDocument>> {
    user.require(Permission::CustomerBillingPost)?;
    Ok(Json(
        billing::register_legacy_invoice(&state.db, &user, input).await?,
    ))
}

#[utoipa::path(
    get, path = "/customer-invoices/{id}", tag = "customer_billing",
    params(("id" = Uuid, Path)),
    responses((status = 200, body = BillingDocument), (status = 403), (status = 404), (status = 409), (status = 422))
)]
async fn get_customer_document(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<BillingDocument>> {
    user.require(Permission::CustomerBillingRead)?;
    Ok(Json(billing::get(&state.db, &user, id).await?))
}

#[utoipa::path(
    delete, path = "/customer-invoices/{id}", tag = "customer_billing",
    params(("id" = Uuid, Path)),
    responses((status = 204), (status = 403), (status = 404), (status = 409), (status = 422))
)]
async fn discard_customer_document(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<axum::http::StatusCode> {
    user.require(Permission::CustomerBillingWrite)?;
    billing::discard(&state.db, &user, id).await?;
    Ok(axum::http::StatusCode::NO_CONTENT)
}

#[utoipa::path(
    post, path = "/customer-invoices/{id}/post", tag = "customer_billing",
    params(("id" = Uuid, Path)),
    responses((status = 200, body = BillingDocument), (status = 403), (status = 404), (status = 409), (status = 422))
)]
async fn post_customer_document(
    State(state): State<AppState>,
    user: CurrentUser,
    Extension(environment): Extension<EnvironmentConfig>,
    Path(id): Path<Uuid>,
) -> AppResult<Json<BillingDocument>> {
    user.require(Permission::CustomerBillingPost)?;
    if environment.kind == EnvKind::Live
        && !std::env::var("CUSTOMER_BILLING_LIVE_COMPANIES")
            .unwrap_or_default()
            .split(',')
            .filter_map(|company| company.trim().parse::<Uuid>().ok())
            .any(|company| company == user.company_id)
    {
        return Err(AppError::Forbidden(
            "Live customer billing is disabled for this company until its accounting and invoice delivery handoff is operational.".into(),
        ));
    }
    Ok(Json(billing::post(&state.db, &user, id).await?))
}

pub(super) fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(list_customer_documents, create_customer_invoice))
        .routes(routes!(create_customer_credit))
        .routes(routes!(register_legacy_customer_invoice))
        .routes(routes!(get_customer_document, discard_customer_document))
        .routes(routes!(post_customer_document))
        .routes(routes!(download_customer_document))
}

#[utoipa::path(
    get, path = "/customer-invoices/{id}/pdf", tag = "customer_billing",
    params(("id" = Uuid, Path)),
    responses((status = 200, content_type = "application/pdf", body = Vec<u8>),
              (status = 403), (status = 404), (status = 422))
)]
async fn download_customer_document(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Response> {
    user.require(Permission::CustomerBillingRead)?;
    let detail = billing::get(&state.db, &user, id).await?;
    let document = &detail.document;
    if document.status != "posted" || document.is_legacy {
        return Err(AppError::Validation(
            "A PDF is available for documents posted in TradoCraft.".into(),
        ));
    }

    let lines: Vec<_> = detail
        .lines
        .iter()
        .map(|line| {
            serde_json::json!({
                "code": line.product_code,
                "description": line.description,
                "unit": line.unit,
                "quantity": format_number(line.quantity),
                "net_unit_price": format_unit_price(line.net_unit_price),
                "net_total": format_amount(line.net_total),
                "vat_rate": format_number(line.vat_rate),
                "vat_total": format_amount(line.vat_total),
            })
        })
        .collect();
    let progress = detail.rebate_progress.as_ref().map(|progress| {
        serde_json::json!({
            "eligible_sales": format_amount(progress.eligible_sales),
            "next_threshold": progress.next_threshold.map(format_amount),
            "amount_to_next_tier": progress.amount_to_next_tier.map(format_amount),
            "next_rate": progress.next_rate.map(format_number),
            "rate_year": progress.rate_year,
            "currency": progress.currency,
            "message": progress.message,
        })
    });
    let data = serde_json::json!({
        "number": document.number,
        "kind": document.kind,
        "language": detail.language,
        "date": format_date(document.document_date),
        "due_date": document.due_date.map(format_date),
        "currency": document.currency,
        "vat_regime": detail.vat_regime,
        "source_invoice_number": document.source_invoice_number,
        "reason": document.reason,
        "seller": detail.seller,
        "customer": detail.customer,
        "lines": lines,
        "net_total": format_amount(document.net_total),
        "vat_total": format_amount(document.vat_total),
        "gross_total": format_amount(document.gross_total),
        "rebate": progress,
    });
    let bytes =
        tradocraft_documents::render_pdf(&state.documents, "customer_invoice", &data).await?;
    Ok(([(header::CONTENT_TYPE, "application/pdf")], bytes).into_response())
}
