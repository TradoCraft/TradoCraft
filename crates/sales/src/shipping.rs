//! Shipping-quote workflow (ADR 0026).
//!
//! Products in a packaging category that `requires_shipping_quote` (large flat panels, pallets, ...)
//! cannot be shipped at a standard rate: a person asks the carriers for a price. Saving a quotation
//! keeps one live `shipping_requests` row in step with its lines ([`sync`]); logistics works the
//! queue (`open` -> `requested` -> `quoted`), and the quoted cost enters the quotation as a
//! non-product line with code `SHIPPING`, priced through the normal line, totals and VAT path.
//! While a request is `open` or `requested` the quotation cannot be sent (see `routes.rs`).

use axum::extract::{Path, Query, State};
use axum::Json;
use chrono::{DateTime, Utc};
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection};
use tradocraft_core::{
    audit, mail, new_id, AppError, AppResult, AppState, CurrentUser, Permission,
};
use tradocraft_pricing::{price_line, LineInput};
use utoipa::{IntoParams, ToSchema};
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::model::{QuotationLine, QuotationStatus};
use crate::service;

type ErrorBody = tradocraft_core::error::ErrorBody;

/// Code of the quotation line that carries the quoted shipping cost.
pub const SHIPPING_CODE: &str = "SHIPPING";

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct ShippingRequest {
    pub id: Uuid,
    pub quotation_id: Uuid,
    pub quotation_number: String,
    pub quotation_revision: i32,
    pub customer_name: String,
    pub delivery_country_code: Option<String>,
    /// open | requested | quoted | cancelled
    pub status: String,
    pub carrier: Option<String>,
    #[schema(value_type = Option<String>, example = "180.00")]
    pub quoted_amount: Option<Decimal>,
    pub currency: Option<String>,
    pub notes: String,
    pub requested_at: Option<DateTime<Utc>>,
    pub requested_by: Option<Uuid>,
    pub quoted_at: Option<DateTime<Utc>>,
    pub quoted_by: Option<Uuid>,
    pub created_at: DateTime<Utc>,
}

const SELECT: &str = "SELECT r.id, r.quotation_id, q.number AS quotation_number, q.revision AS quotation_revision,
        q.customer_name, q.delivery_country_code::text AS delivery_country_code, r.status, r.carrier,
        r.quoted_amount, r.currency::text AS currency, r.notes, r.requested_at, r.requested_by,
        r.quoted_at, r.quoted_by, r.created_at
    FROM sales.shipping_requests r JOIN sales.quotations q ON q.id = r.quotation_id";

#[derive(Debug, Deserialize, IntoParams)]
struct ListParams {
    /// open | requested | quoted | cancelled. Default: the work queue (open and requested).
    status: Option<String>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct MarkShippingRequestedInput {
    /// The carrier(s) asked for a price.
    pub carrier: String,
    #[serde(default)]
    pub notes: String,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct ShippingQuoteInput {
    #[schema(value_type = String, example = "180.00")]
    pub amount: Decimal,
    /// Must equal the quotation currency. Defaults to it.
    pub currency: Option<String>,
    /// Carrier chosen; keeps the one entered when marking the request as requested.
    pub carrier: Option<String>,
    pub notes: Option<String>,
}

/// Keeps the live shipping request of a draft quotation in step with its lines.
///
/// * a line with a product that requires a shipping quote and no live request: opens one;
/// * no such line any more: cancels the live request and drops the `SHIPPING` line;
/// * the request is already quoted: makes sure the `SHIPPING` line is on the quotation (saving a
///   draft replaces all lines).
///
/// Sets `shipping_status` and recomputes the totals when it changed a line. Call it inside the
/// transaction that holds the quotation lock, after the lines are written.
pub async fn sync(
    conn: &mut PgConnection,
    user: &CurrentUser,
    quotation_id: Uuid,
) -> AppResult<()> {
    let product_ids: Vec<Uuid> = sqlx::query_scalar(
        "SELECT DISTINCT product_id FROM sales.quotation_lines
         WHERE quotation_id = $1 AND product_id IS NOT NULL",
    )
    .bind(quotation_id)
    .fetch_all(&mut *conn)
    .await?;
    let needed = !tradocraft_products::requiring_shipping_quote(&mut *conn, &product_ids)
        .await?
        .is_empty();
    let active: Option<(Uuid, String, Option<Decimal>)> = sqlx::query_as(
        "SELECT id, status, quoted_amount FROM sales.shipping_requests
         WHERE quotation_id = $1 AND status <> 'cancelled' FOR UPDATE",
    )
    .bind(quotation_id)
    .fetch_optional(&mut *conn)
    .await?;

    let mut totals_changed = false;
    let status = match (needed, active) {
        (true, None) => {
            let id = new_id();
            sqlx::query(
                "INSERT INTO sales.shipping_requests (id, company_id, quotation_id) VALUES ($1, $2, $3)",
            )
            .bind(id)
            .bind(user.company_id)
            .bind(quotation_id)
            .execute(&mut *conn)
            .await?;
            audit::record(
                conn,
                user,
                "quotation",
                quotation_id,
                "shipping_request_opened",
                serde_json::json!({ "request_id": id }),
            )
            .await?;
            notify_logistics(conn, user.company_id, quotation_id).await?;
            "pending"
        }
        (true, Some((_, status, amount))) if status == "quoted" => {
            if let Some(amount) = amount {
                totals_changed =
                    put_shipping_line(conn, user.company_id, quotation_id, amount).await?;
            }
            "quoted"
        }
        (true, Some(_)) => "pending",
        (false, Some((id, _, _))) => {
            sqlx::query(
                "UPDATE sales.shipping_requests SET status = 'cancelled', updated_at = now() WHERE id = $1",
            )
            .bind(id)
            .execute(&mut *conn)
            .await?;
            audit::record(
                conn,
                user,
                "quotation",
                quotation_id,
                "shipping_request_cancelled",
                serde_json::json!({ "request_id": id }),
            )
            .await?;
            totals_changed = remove_shipping_line(conn, quotation_id).await?;
            "not_required"
        }
        (false, None) => {
            totals_changed = remove_shipping_line(conn, quotation_id).await?;
            "not_required"
        }
    };
    sqlx::query("UPDATE sales.quotations SET shipping_status = $2 WHERE id = $1")
        .bind(quotation_id)
        .bind(status)
        .execute(&mut *conn)
        .await?;
    if totals_changed {
        recompute_totals(conn, user.company_id, quotation_id).await?;
    }
    Ok(())
}

/// A revision that keeps the agreed prices keeps the shipping request with its quoted cost.
pub async fn copy_for_revision(
    conn: &mut PgConnection,
    old_id: Uuid,
    new_id_: Uuid,
) -> AppResult<()> {
    sqlx::query(
        "INSERT INTO sales.shipping_requests (id, company_id, quotation_id, status, carrier, quoted_amount,
                currency, notes, requested_at, requested_by, quoted_at, quoted_by)
         SELECT $3, company_id, $2, status, carrier, quoted_amount, currency, notes, requested_at,
                requested_by, quoted_at, quoted_by
         FROM sales.shipping_requests WHERE quotation_id = $1 AND status <> 'cancelled'",
    )
    .bind(old_id)
    .bind(new_id_)
    .bind(new_id())
    .execute(&mut *conn)
    .await?;
    sqlx::query(
        "UPDATE sales.quotations SET shipping_status = (SELECT shipping_status FROM sales.quotations WHERE id = $1)
         WHERE id = $2",
    )
    .bind(old_id)
    .bind(new_id_)
    .execute(&mut *conn)
    .await?;
    Ok(())
}

async fn remove_shipping_line(conn: &mut PgConnection, quotation_id: Uuid) -> AppResult<bool> {
    let r = sqlx::query(
        "DELETE FROM sales.quotation_lines WHERE quotation_id = $1 AND product_id IS NULL AND product_code = $2",
    )
    .bind(quotation_id)
    .bind(SHIPPING_CODE)
    .execute(&mut *conn)
    .await?;
    Ok(r.rows_affected() > 0)
}

/// The `SHIPPING` line for a quotation with these lines: last position, one unit, net price, VAT
/// at the highest rate among the product lines (shipping follows the goods). Shared by the
/// shipping workflow and the pricing preview so both always agree.
pub fn shipping_line(lines: &[QuotationLine], amount: Decimal) -> AppResult<QuotationLine> {
    let vat_rate = lines
        .iter()
        .filter(|l| l.product_id.is_some())
        .map(|l| l.vat_rate)
        .max()
        .unwrap_or_default();
    let p = price_line(&LineInput {
        list_unit_price: amount.round_dp(2),
        quantity: Decimal::ONE,
        customer_discount_percent: Decimal::ZERO,
        line_discount_percent: Decimal::ZERO,
        vat_rate,
    })
    .map_err(|e| AppError::Validation(format!("shipping line: {e}")))?;
    Ok(QuotationLine {
        position: lines.iter().map(|l| l.position).max().unwrap_or(0) + 1,
        product_id: None,
        product_code: SHIPPING_CODE.into(),
        description: "Shipping".into(),
        unit: "pcs".into(),
        quantity: p.quantity,
        list_unit_price: p.list_unit_price,
        pricing_type: "net".into(),
        rebate_percent: Decimal::ZERO,
        rebate_source: "net".into(),
        line_discount_percent: Decimal::ZERO,
        net_unit_price: p.net_unit_price,
        line_total: p.line_total,
        vat_rate: p.vat_rate,
        price_confirmed: true,
        parent_position: None,
        section: None,
        comment: None,
        percent_of_parent: None,
        percent_base: None,
        production_remark: String::new(),
        customer_remark: String::new(),
        customer_remark_language: None,
        favorite_item_id: None,
    })
}

/// The quoted shipping cost that a preview of the draft `quotation_id` may add, or `None` when the
/// quotation is not a draft or has no quoted request. An unknown or foreign id is a 404. The caller
/// still checks with [`needs_quote`] that the previewed products need it.
pub async fn quoted_amount_for_preview(
    conn: &mut PgConnection,
    company_id: Uuid,
    quotation_id: Uuid,
) -> AppResult<Option<Decimal>> {
    let status: String =
        sqlx::query_scalar("SELECT status FROM sales.quotations WHERE id = $1 AND company_id = $2")
            .bind(quotation_id)
            .bind(company_id)
            .fetch_optional(&mut *conn)
            .await?
            .ok_or(AppError::NotFound("quotation"))?;
    if status != "draft" {
        return Ok(None);
    }
    Ok(sqlx::query_scalar(
        "SELECT quoted_amount FROM sales.shipping_requests
         WHERE quotation_id = $1 AND company_id = $2 AND status = 'quoted'",
    )
    .bind(quotation_id)
    .bind(company_id)
    .fetch_optional(&mut *conn)
    .await?
    .flatten())
}

/// Whether any of the products is in a packaging category that requires a shipping quote (when
/// none is, saving would cancel the request and drop the `SHIPPING` line).
pub async fn needs_quote(conn: &mut PgConnection, product_ids: &[Uuid]) -> AppResult<bool> {
    Ok(
        !tradocraft_products::requiring_shipping_quote(conn, product_ids)
            .await?
            .is_empty(),
    )
}

/// Adds or replaces the `SHIPPING` line (last position, one unit, VAT at the highest rate of the
/// product lines). Returns true: the totals need recomputing.
async fn put_shipping_line(
    conn: &mut PgConnection,
    company_id: Uuid,
    quotation_id: Uuid,
    amount: Decimal,
) -> AppResult<bool> {
    remove_shipping_line(conn, quotation_id).await?;
    let q = service::load_quotation(conn, company_id, quotation_id, false).await?;
    let line = shipping_line(&q.lines, amount)?;
    service::insert_lines(conn, quotation_id, &[line]).await?;
    Ok(true)
}

async fn recompute_totals(
    conn: &mut PgConnection,
    company_id: Uuid,
    quotation_id: Uuid,
) -> AppResult<()> {
    let q = service::load_quotation(conn, company_id, quotation_id, false).await?;
    let t = service::stored_totals(&q.lines);
    sqlx::query(
        "UPDATE sales.quotations SET subtotal = $2, vat_total = $3, total = $4, updated_at = now() WHERE id = $1",
    )
    .bind(quotation_id)
    .bind(t.subtotal)
    .bind(t.vat_total)
    .bind(t.total)
    .execute(&mut *conn)
    .await?;
    Ok(())
}

/// Tells logistics (the company's `logistics` users, else its administrators) that a quotation
/// needs a shipping quote. Queued in the caller's transaction.
async fn notify_logistics(
    conn: &mut PgConnection,
    company_id: Uuid,
    quotation_id: Uuid,
) -> AppResult<()> {
    let mut to: Vec<String> = Vec::new();
    for role in ["logistics", "admin"] {
        to = sqlx::query_scalar(
            "SELECT u.email FROM core.user_companies uc JOIN core.users u ON u.id = uc.user_id
             WHERE uc.company_id = $1 AND $2 = ANY(uc.roles) AND u.active ORDER BY u.email",
        )
        .bind(company_id)
        .bind(role)
        .fetch_all(&mut *conn)
        .await?;
        if !to.is_empty() {
            break;
        }
    }
    let (number, customer, country): (String, String, Option<String>) = sqlx::query_as(
        "SELECT number, customer_name, delivery_country_code::text FROM sales.quotations WHERE id = $1",
    )
    .bind(quotation_id)
    .fetch_one(&mut *conn)
    .await?;
    let subject = format!("Shipping quote needed: {number}");
    let body = format!(
        "Quotation {number} for {customer} (delivery to {}) contains products that need a shipping quote.\n\
         Ask the carriers for a price and enter the quoted cost on the quotation's shipping request.\n",
        country.as_deref().unwrap_or("unknown destination")
    );
    for address in &to {
        mail::enqueue(conn, company_id, address, &subject, &body).await?;
    }
    Ok(())
}

/// The shipping requests that logistics works on (open and requested by default).
#[utoipa::path(get, path = "/shipping-requests", tag = "sales", params(ListParams),
    responses((status = 200, body = Vec<ShippingRequest>), (status = 403, body = ErrorBody)))]
async fn list_shipping_requests(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(p): Query<ListParams>,
) -> AppResult<Json<Vec<ShippingRequest>>> {
    user.require(Permission::ShippingManage)?;
    if let Some(s) = &p.status {
        if !["open", "requested", "quoted", "cancelled"].contains(&s.as_str()) {
            return Err(AppError::Validation(format!("unknown status {s}")));
        }
    }
    Ok(Json(
        sqlx::query_as(&format!(
            "{SELECT} WHERE r.company_id = $1
               AND (($2::text IS NULL AND r.status IN ('open', 'requested')) OR r.status = $2)
             ORDER BY r.created_at, r.id"
        ))
        .bind(user.company_id)
        .bind(&p.status)
        .fetch_all(&state.db)
        .await?,
    ))
}

/// Locks the quotation of a request (draft only) and then the request itself, in the same order
/// as `sync`, so saving a quotation and working the request never deadlock.
async fn lock_request(
    tx: &mut PgConnection,
    user: &CurrentUser,
    id: Uuid,
) -> AppResult<(ShippingRequest, crate::model::Quotation)> {
    let quotation_id: Uuid = sqlx::query_scalar(
        "SELECT quotation_id FROM sales.shipping_requests WHERE id = $1 AND company_id = $2",
    )
    .bind(id)
    .bind(user.company_id)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or(AppError::NotFound("shipping request"))?;
    let q = service::load_quotation(tx, user.company_id, quotation_id, true).await?;
    let r: ShippingRequest = sqlx::query_as(&format!("{SELECT} WHERE r.id = $1 FOR UPDATE OF r"))
        .bind(id)
        .fetch_one(&mut *tx)
        .await?;
    if service::status_of(&q) != QuotationStatus::Draft {
        return Err(AppError::Conflict(format!(
            "quotation {} is {}; its shipping request can no longer be changed",
            q.number, q.status
        )));
    }
    Ok((r, q))
}

/// Records that the carriers have been asked for a price.
#[utoipa::path(post, path = "/shipping-requests/{id}/request", tag = "sales", params(("id" = Uuid, Path)),
    request_body = MarkShippingRequestedInput,
    responses((status = 200, body = ShippingRequest), (status = 403, body = ErrorBody),
        (status = 404, body = ErrorBody), (status = 409, body = ErrorBody)))]
async fn mark_shipping_requested(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<MarkShippingRequestedInput>,
) -> AppResult<Json<ShippingRequest>> {
    user.require(Permission::ShippingManage)?;
    if input.carrier.trim().is_empty() {
        return Err(AppError::Validation("carrier is required".into()));
    }
    let mut tx = state.db.begin().await?;
    let (r, _) = lock_request(&mut tx, &user, id).await?;
    if !["open", "requested"].contains(&r.status.as_str()) {
        return Err(AppError::Conflict(format!(
            "shipping request is {}; only open requests can be marked as requested",
            r.status
        )));
    }
    sqlx::query(
        "UPDATE sales.shipping_requests SET status = 'requested', carrier = $2, notes = $3,
                requested_at = now(), requested_by = $4, updated_at = now() WHERE id = $1",
    )
    .bind(id)
    .bind(input.carrier.trim())
    .bind(input.notes.trim())
    .bind(user.user_id)
    .execute(&mut *tx)
    .await?;
    audit::record(
        &mut tx,
        &user,
        "shipping_request",
        id,
        "requested",
        serde_json::json!({ "carrier": input.carrier.trim() }),
    )
    .await?;
    let out = sqlx::query_as(&format!("{SELECT} WHERE r.id = $1"))
        .bind(id)
        .fetch_one(&mut *tx)
        .await?;
    tx.commit().await?;
    Ok(Json(out))
}

/// Enters the quoted shipping cost: the request becomes `quoted` and the quotation gets (or
/// updates) its `SHIPPING` line, with totals and VAT recomputed.
#[utoipa::path(post, path = "/shipping-requests/{id}/quote", tag = "sales", params(("id" = Uuid, Path)),
    request_body = ShippingQuoteInput,
    responses((status = 200, body = ShippingRequest), (status = 403, body = ErrorBody),
        (status = 404, body = ErrorBody), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn enter_shipping_quote(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<ShippingQuoteInput>,
) -> AppResult<Json<ShippingRequest>> {
    user.require(Permission::ShippingManage)?;
    if input.amount < Decimal::ZERO {
        return Err(AppError::Validation("amount cannot be negative".into()));
    }
    let amount = input.amount.round_dp(2);
    let mut tx = state.db.begin().await?;
    let (r, q) = lock_request(&mut tx, &user, id).await?;
    if r.status == "cancelled" {
        return Err(AppError::Conflict(
            "shipping request is cancelled; the quotation no longer needs a quote".into(),
        ));
    }
    let currency = input
        .currency
        .as_deref()
        .map(|c| c.trim().to_uppercase())
        .filter(|c| !c.is_empty())
        .unwrap_or_else(|| q.currency.clone());
    if currency != q.currency {
        return Err(AppError::Validation(format!(
            "currency must be the quotation currency ({})",
            q.currency
        )));
    }
    sqlx::query(
        "UPDATE sales.shipping_requests SET status = 'quoted', quoted_amount = $2, currency = $3,
                carrier = COALESCE(NULLIF(btrim($4), ''), carrier), notes = COALESCE($5, notes),
                quoted_at = now(), quoted_by = $6, updated_at = now() WHERE id = $1",
    )
    .bind(id)
    .bind(amount)
    .bind(&currency)
    .bind(input.carrier.as_deref().unwrap_or(""))
    .bind(input.notes.as_deref().map(str::trim))
    .bind(user.user_id)
    .execute(&mut *tx)
    .await?;
    put_shipping_line(&mut tx, user.company_id, q.id, amount).await?;
    recompute_totals(&mut tx, user.company_id, q.id).await?;
    sqlx::query("UPDATE sales.quotations SET shipping_status = 'quoted' WHERE id = $1")
        .bind(q.id)
        .execute(&mut *tx)
        .await?;
    audit::record(
        &mut tx,
        &user,
        "shipping_request",
        id,
        "quoted",
        serde_json::json!({ "amount": amount, "currency": currency }),
    )
    .await?;
    let out = sqlx::query_as(&format!("{SELECT} WHERE r.id = $1"))
        .bind(id)
        .fetch_one(&mut *tx)
        .await?;
    tx.commit().await?;
    Ok(Json(out))
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(list_shipping_requests))
        .routes(routes!(mark_shipping_requested))
        .routes(routes!(enter_shipping_quote))
}
