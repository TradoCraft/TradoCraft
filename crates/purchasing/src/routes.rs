use axum::extract::{Path, Query, State};
use axum::http::{header, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::{Extension, Json};
use serde::Deserialize;
use tradocraft_core::company::get_company;
use tradocraft_core::vat_check::{self, VatCheck, VatCheckParams};
use tradocraft_core::vies::ViesConfig;
use tradocraft_core::{AppError, AppResult, AppState, CurrentUser, Permission};
use utoipa::IntoParams;
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::orders::{
    self, NewPurchaseOrderInput, PurchaseOrderDetail, PurchaseOrderSummary,
    UpdatePurchaseOrderInput,
};
use crate::po_doc;
use crate::receipts::{self, GoodsReceiptDetail, GoodsReceiptSummary, ReceiveGoodsInput};
use crate::supplier_products::{self, SetSupplierProductInput, SupplierProduct};
use crate::suppliers::{self, NewSupplierInput, Supplier, UpdateSupplierInput};

type ErrorBody = tradocraft_core::error::ErrorBody;

/// Query filters for listing suppliers.
#[derive(Debug, Deserialize, IntoParams)]
pub struct ListSuppliersParams {
    pub active_only: Option<bool>,
    /// Searches name, code, e-mail address and contact person, ignoring case and accents.
    pub q: Option<String>,
}

/// Query filters for listing purchase orders.
#[derive(Debug, Deserialize, IntoParams)]
pub struct ListOrdersParams {
    pub supplier_id: Option<Uuid>,
    pub status: Option<String>,
}

// ---------------- Suppliers ----------------

#[utoipa::path(
    get,
    path = "/suppliers",
    tag = "purchasing",
    params(ListSuppliersParams),
    responses(
        (status = 200, body = Vec<Supplier>),
        (status = 401, body = ErrorBody),
        (status = 403, body = ErrorBody)
    )
)]
async fn list_suppliers(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(params): Query<ListSuppliersParams>,
) -> AppResult<Json<Vec<Supplier>>> {
    user.require(Permission::PurchasingRead)?;
    let mut conn = state.db.acquire().await?;
    let list = suppliers::list(
        &mut conn,
        user.company_id,
        params.active_only.unwrap_or(false),
        params.q.as_deref(),
    )
    .await?;
    Ok(Json(list))
}

/// Checks a supplier's VAT number for the supplier form: the format and check digits, other
/// suppliers of the company with the same number, and with `lookup=true` the name and address VIES
/// has for it (ADR 0058). Advice only; nothing is stored. The lookup needs `purchasing.write`.
#[utoipa::path(
    get,
    path = "/suppliers/vat-check",
    tag = "purchasing",
    operation_id = "check_supplier_vat",
    params(VatCheckParams),
    responses(
        (status = 200, body = VatCheck),
        (status = 401, body = ErrorBody),
        (status = 403, body = ErrorBody)
    )
)]
async fn check_supplier_vat(
    State(state): State<AppState>,
    user: CurrentUser,
    Extension(vies): Extension<ViesConfig>,
    Query(p): Query<VatCheckParams>,
) -> AppResult<Json<VatCheck>> {
    user.require(Permission::PurchasingRead)?;
    let lookup = p.lookup.unwrap_or(false);
    if lookup {
        user.require(Permission::PurchasingWrite)?;
    }
    let a = vat_check::assess(&p.vat_number, p.country_code.as_deref());
    let duplicates = if a.has_number() {
        let mut conn = state.db.acquire().await?;
        suppliers::vat_duplicates(&mut conn, user.company_id, &a, p.exclude_id).await?
    } else {
        Vec::new()
    };
    Ok(Json(a.build(duplicates, lookup.then_some(&vies)).await))
}

#[utoipa::path(
    post,
    path = "/suppliers",
    tag = "purchasing",
    request_body = NewSupplierInput,
    responses(
        (status = 201, body = Supplier),
        (status = 400, body = ErrorBody),
        (status = 422, body = ErrorBody),
        (status = 401, body = ErrorBody),
        (status = 403, body = ErrorBody),
        (status = 409, body = ErrorBody)
    )
)]
async fn create_supplier(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<NewSupplierInput>,
) -> AppResult<(StatusCode, Json<Supplier>)> {
    user.require(Permission::PurchasingWrite)?;
    let mut tx = state.db.begin().await?;
    let s = suppliers::create(&mut tx, &user, input).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(s)))
}

#[utoipa::path(
    get,
    path = "/suppliers/{id}",
    tag = "purchasing",
    params(("id" = Uuid, Path, description = "Supplier ID")),
    responses(
        (status = 200, body = Supplier),
        (status = 401, body = ErrorBody),
        (status = 403, body = ErrorBody),
        (status = 404, body = ErrorBody)
    )
)]
async fn get_supplier(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<Supplier>> {
    user.require(Permission::PurchasingRead)?;
    let mut conn = state.db.acquire().await?;
    let s = suppliers::load(&mut conn, user.company_id, id).await?;
    Ok(Json(s))
}

#[utoipa::path(
    put,
    path = "/suppliers/{id}",
    tag = "purchasing",
    params(("id" = Uuid, Path, description = "Supplier ID")),
    request_body = UpdateSupplierInput,
    responses(
        (status = 200, body = Supplier),
        (status = 400, body = ErrorBody),
        (status = 422, body = ErrorBody),
        (status = 401, body = ErrorBody),
        (status = 403, body = ErrorBody),
        (status = 404, body = ErrorBody),
        (status = 409, body = ErrorBody)
    )
)]
async fn update_supplier(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<UpdateSupplierInput>,
) -> AppResult<Json<Supplier>> {
    user.require(Permission::PurchasingWrite)?;
    let mut tx = state.db.begin().await?;
    let s = suppliers::update(&mut tx, &user, id, input).await?;
    tx.commit().await?;
    Ok(Json(s))
}

// ---------------- Supplier Products (Price Lists) ----------------

#[utoipa::path(
    get,
    path = "/suppliers/{id}/products",
    tag = "purchasing",
    params(("id" = Uuid, Path, description = "Supplier ID")),
    responses(
        (status = 200, body = Vec<SupplierProduct>),
        (status = 401, body = ErrorBody),
        (status = 403, body = ErrorBody)
    )
)]
async fn list_supplier_products(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<Vec<SupplierProduct>>> {
    user.require(Permission::PurchasingRead)?;
    let mut conn = state.db.acquire().await?;
    let list = supplier_products::list_for_supplier(&mut conn, user.company_id, id).await?;
    Ok(Json(list))
}

#[utoipa::path(
    post,
    path = "/suppliers/{id}/products/{product_id}",
    tag = "purchasing",
    params(
        ("id" = Uuid, Path, description = "Supplier ID"),
        ("product_id" = Uuid, Path, description = "Product ID")
    ),
    request_body = SetSupplierProductInput,
    responses(
        (status = 200, body = SupplierProduct),
        (status = 400, body = ErrorBody),
        (status = 422, body = ErrorBody),
        (status = 401, body = ErrorBody),
        (status = 403, body = ErrorBody),
        (status = 404, body = ErrorBody)
    )
)]
async fn set_supplier_product(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((id, product_id)): Path<(Uuid, Uuid)>,
    Json(input): Json<SetSupplierProductInput>,
) -> AppResult<Json<SupplierProduct>> {
    user.require(Permission::PurchasingWrite)?;
    let mut tx = state.db.begin().await?;
    let sp = supplier_products::set_supplier_product(&mut tx, &user, id, product_id, input).await?;
    tx.commit().await?;
    Ok(Json(sp))
}

#[utoipa::path(
    delete,
    path = "/suppliers/{id}/products/{product_id}",
    tag = "purchasing",
    params(
        ("id" = Uuid, Path, description = "Supplier ID"),
        ("product_id" = Uuid, Path, description = "Product ID")
    ),
    responses(
        (status = 204),
        (status = 401, body = ErrorBody),
        (status = 403, body = ErrorBody),
        (status = 404, body = ErrorBody)
    )
)]
async fn delete_supplier_product(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((id, product_id)): Path<(Uuid, Uuid)>,
) -> AppResult<StatusCode> {
    user.require(Permission::PurchasingWrite)?;
    let mut tx = state.db.begin().await?;
    supplier_products::delete_supplier_product(&mut tx, &user, id, product_id).await?;
    tx.commit().await?;
    Ok(StatusCode::NO_CONTENT)
}

#[utoipa::path(
    get,
    path = "/products/{id}/suppliers",
    tag = "purchasing",
    params(("id" = Uuid, Path, description = "Product ID")),
    responses(
        (status = 200, body = Vec<SupplierProduct>),
        (status = 401, body = ErrorBody),
        (status = 403, body = ErrorBody)
    )
)]
async fn list_product_suppliers(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<Vec<SupplierProduct>>> {
    user.require(Permission::PurchasingRead)?;
    let mut conn = state.db.acquire().await?;
    let list = supplier_products::list_for_product(&mut conn, user.company_id, id).await?;
    Ok(Json(list))
}

// ---------------- Purchase Orders ----------------

#[utoipa::path(
    get,
    path = "/purchase-orders",
    tag = "purchasing",
    params(ListOrdersParams),
    responses(
        (status = 200, body = Vec<PurchaseOrderSummary>),
        (status = 401, body = ErrorBody),
        (status = 403, body = ErrorBody)
    )
)]
async fn list_orders(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(params): Query<ListOrdersParams>,
) -> AppResult<Json<Vec<PurchaseOrderSummary>>> {
    user.require(Permission::PurchasingRead)?;
    let mut conn = state.db.acquire().await?;
    let list = orders::list(
        &mut conn,
        user.company_id,
        params.supplier_id,
        params.status,
    )
    .await?;
    Ok(Json(list))
}

#[utoipa::path(
    post,
    path = "/purchase-orders",
    tag = "purchasing",
    request_body = NewPurchaseOrderInput,
    responses(
        (status = 201, body = PurchaseOrderDetail),
        (status = 400, body = ErrorBody),
        (status = 422, body = ErrorBody),
        (status = 401, body = ErrorBody),
        (status = 403, body = ErrorBody),
        (status = 404, body = ErrorBody)
    )
)]
async fn create_order(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<NewPurchaseOrderInput>,
) -> AppResult<(StatusCode, Json<PurchaseOrderDetail>)> {
    user.require(Permission::PurchasingWrite)?;
    let mut tx = state.db.begin().await?;
    let po = orders::create(&mut tx, &user, input).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(po)))
}

#[utoipa::path(
    get,
    path = "/purchase-orders/{id}",
    tag = "purchasing",
    params(("id" = Uuid, Path, description = "Purchase Order ID")),
    responses(
        (status = 200, body = PurchaseOrderDetail),
        (status = 401, body = ErrorBody),
        (status = 403, body = ErrorBody),
        (status = 404, body = ErrorBody)
    )
)]
async fn get_order(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<PurchaseOrderDetail>> {
    user.require(Permission::PurchasingRead)?;
    let mut conn = state.db.acquire().await?;
    let po = orders::load(&mut conn, user.company_id, id).await?;
    Ok(Json(po))
}

#[utoipa::path(
    put,
    path = "/purchase-orders/{id}",
    tag = "purchasing",
    params(("id" = Uuid, Path, description = "Purchase Order ID")),
    request_body = UpdatePurchaseOrderInput,
    responses(
        (status = 200, body = PurchaseOrderDetail),
        (status = 400, body = ErrorBody),
        (status = 422, body = ErrorBody),
        (status = 401, body = ErrorBody),
        (status = 403, body = ErrorBody),
        (status = 404, body = ErrorBody),
        (status = 409, body = ErrorBody)
    )
)]
async fn update_order(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<UpdatePurchaseOrderInput>,
) -> AppResult<Json<PurchaseOrderDetail>> {
    user.require(Permission::PurchasingWrite)?;
    let mut tx = state.db.begin().await?;
    let po = orders::update(&mut tx, &user, id, input).await?;
    tx.commit().await?;
    Ok(Json(po))
}

#[utoipa::path(
    post,
    path = "/purchase-orders/{id}/approve",
    tag = "purchasing",
    params(("id" = Uuid, Path, description = "Purchase Order ID")),
    responses(
        (status = 200, body = PurchaseOrderDetail),
        (status = 401, body = ErrorBody),
        (status = 403, body = ErrorBody),
        (status = 404, body = ErrorBody),
        (status = 409, body = ErrorBody)
    )
)]
async fn approve_order(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<PurchaseOrderDetail>> {
    user.require(Permission::PurchasingApprove)?;
    let mut tx = state.db.begin().await?;
    let po = orders::approve(&mut tx, &user, id).await?;
    tx.commit().await?;
    Ok(Json(po))
}

#[utoipa::path(
    post,
    path = "/purchase-orders/{id}/send",
    tag = "purchasing",
    params(("id" = Uuid, Path, description = "Purchase Order ID")),
    responses(
        (status = 200, body = PurchaseOrderDetail),
        (status = 401, body = ErrorBody),
        (status = 403, body = ErrorBody),
        (status = 404, body = ErrorBody),
        (status = 409, body = ErrorBody)
    )
)]
async fn send_order(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<PurchaseOrderDetail>> {
    user.require(Permission::PurchasingWrite)?;
    let mut tx = state.db.begin().await?;
    let po = orders::send(&mut tx, &user, id).await?;
    // The PDF goes to the supplier in the same transaction: if it cannot be made the order stays approved.
    po_doc::mail_to_supplier(&mut tx, &state.documents, &user, &po).await?;
    tx.commit().await?;
    Ok(Json(po))
}

/// Query of the purchase order PDF.
#[derive(Debug, Deserialize, IntoParams)]
pub struct PdfParams {
    /// nl | fr | en | de | es; default: the company's language.
    pub lang: Option<String>,
}

/// The purchase order as a PDF. A draft is a preview and a cancelled order is marked as cancelled.
#[utoipa::path(
    get,
    path = "/purchase-orders/{id}/pdf",
    tag = "purchasing",
    params(("id" = Uuid, Path, description = "Purchase Order ID"), PdfParams),
    responses(
        (status = 200, content_type = "application/pdf", body = Vec<u8>),
        (status = 401, body = ErrorBody),
        (status = 403, body = ErrorBody),
        (status = 404, body = ErrorBody),
        (status = 422, body = ErrorBody)
    )
)]
async fn order_pdf(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Query(p): Query<PdfParams>,
) -> AppResult<Response> {
    user.require(Permission::PurchasingRead)?;
    let mut conn = state.db.acquire().await?;
    let po = orders::load(&mut conn, user.company_id, id).await?;
    let supplier = suppliers::load(&mut conn, user.company_id, po.summary.supplier_id).await?;
    let company = get_company(&mut *conn, user.company_id).await?;
    drop(conn);
    let language = match p.lang.as_deref().map(str::to_lowercase) {
        Some(l) if tradocraft_core::is_language(&l) => l,
        Some(_) => {
            return Err(AppError::Validation(format!(
                "lang must be one of {}",
                tradocraft_core::LANGUAGES.join(", ")
            )))
        }
        None => company.default_language.clone(),
    };
    let bytes = po_doc::render(&state.documents, &company, &supplier, &po, &language).await?;
    Ok((
        [
            (header::CONTENT_TYPE, "application/pdf".to_string()),
            (
                header::CONTENT_DISPOSITION,
                format!("inline; filename=\"{}\"", po_doc::pdf_filename(&po)),
            ),
        ],
        bytes,
    )
        .into_response())
}

#[utoipa::path(
    post,
    path = "/purchase-orders/{id}/cancel",
    tag = "purchasing",
    params(("id" = Uuid, Path, description = "Purchase Order ID")),
    responses(
        (status = 200, body = PurchaseOrderDetail),
        (status = 401, body = ErrorBody),
        (status = 403, body = ErrorBody),
        (status = 404, body = ErrorBody),
        (status = 409, body = ErrorBody)
    )
)]
async fn cancel_order(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<PurchaseOrderDetail>> {
    user.require(Permission::PurchasingWrite)?;
    let mut tx = state.db.begin().await?;
    let po = orders::cancel(&mut tx, &user, id).await?;
    tx.commit().await?;
    Ok(Json(po))
}

// ---------------- Goods Receipts ----------------

#[utoipa::path(
    post,
    path = "/purchase-orders/{id}/receipts",
    tag = "purchasing",
    params(("id" = Uuid, Path, description = "Purchase Order ID")),
    request_body = ReceiveGoodsInput,
    responses(
        (status = 201, body = GoodsReceiptDetail),
        (status = 400, body = ErrorBody),
        (status = 422, body = ErrorBody),
        (status = 401, body = ErrorBody),
        (status = 403, body = ErrorBody),
        (status = 404, body = ErrorBody),
        (status = 409, body = ErrorBody)
    )
)]
async fn receive_goods(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<ReceiveGoodsInput>,
) -> AppResult<(StatusCode, Json<GoodsReceiptDetail>)> {
    user.require(Permission::GoodsReceipt)?;
    let mut tx = state.db.begin().await?;
    let gr = receipts::receive(&mut tx, &user, id, input).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(gr)))
}

#[utoipa::path(
    get,
    path = "/purchase-orders/{id}/receipts",
    tag = "purchasing",
    params(("id" = Uuid, Path, description = "Purchase Order ID")),
    responses(
        (status = 200, body = Vec<GoodsReceiptSummary>),
        (status = 401, body = ErrorBody),
        (status = 403, body = ErrorBody)
    )
)]
async fn list_order_receipts(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<Vec<GoodsReceiptSummary>>> {
    user.require(Permission::PurchasingRead)?;
    let mut conn = state.db.acquire().await?;
    let list = receipts::list_for_po(&mut conn, user.company_id, id).await?;
    Ok(Json(list))
}

#[utoipa::path(
    get,
    path = "/goods-receipts/{id}",
    tag = "purchasing",
    params(("id" = Uuid, Path, description = "Goods Receipt ID")),
    responses(
        (status = 200, body = GoodsReceiptDetail),
        (status = 401, body = ErrorBody),
        (status = 403, body = ErrorBody),
        (status = 404, body = ErrorBody)
    )
)]
async fn get_receipt(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<GoodsReceiptDetail>> {
    user.require(Permission::PurchasingRead)?;
    let mut conn = state.db.acquire().await?;
    let gr = receipts::load(&mut conn, user.company_id, id).await?;
    Ok(Json(gr))
}

/// Registers all purchasing routes with their OpenAPI declarations.
pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(check_supplier_vat))
        .routes(routes!(list_suppliers, create_supplier))
        .routes(routes!(get_supplier, update_supplier))
        .routes(routes!(list_supplier_products))
        .routes(routes!(set_supplier_product, delete_supplier_product))
        .routes(routes!(list_product_suppliers))
        .routes(routes!(list_orders, create_order))
        .routes(routes!(get_order, update_order))
        .routes(routes!(approve_order))
        .routes(routes!(send_order))
        .routes(routes!(order_pdf))
        .routes(routes!(cancel_order))
        .routes(routes!(receive_goods, list_order_receipts))
        .routes(routes!(get_receipt))
}
