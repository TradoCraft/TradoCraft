//! Sales orders (ADR 0016).
//!
//! An order starts as a draft, a frozen copy of an accepted quotation revision. Sales prepares it,
//! sends the order confirmation to the customer and the customer (or sales on their behalf)
//! confirms it. Changes after sending go through a new revision of the order; once confirmed the
//! order is frozen. Each revision has its own lines, totals and notes.

use axum::extract::{Path, Query, State};
use axum::http::{header, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::Json;
use chrono::{DateTime, Datelike, NaiveDate, Utc};
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection};
use tradocraft_core::company::get_company;
use tradocraft_core::mail::Attachment;
use tradocraft_core::{
    audit, new_id, numbering, AppError, AppResult, AppState, CurrentUser, Permission,
};
use tradocraft_crm::contacts;
use tradocraft_pricing::{price_line, LineInput};
use utoipa::{IntoParams, ToSchema};
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::model::QuotationStatus;
use crate::order_doc::{self, CustomerSnapshot};
use crate::service;

type ErrorBody = tradocraft_core::error::ErrorBody;

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct OrderSummary {
    pub id: Uuid,
    pub number: String,
    /// draft | sent | confirmed | in_planning | planned | in_production | ready_for_shipping |
    /// partially_shipped | shipped | cancelled
    pub status: String,
    /// low | normal | expedite
    pub priority: String,
    /// The latest revision.
    pub current_revision: i32,
    pub quotation_id: Uuid,
    pub quotation_number: String,
    pub quotation_revision: i32,
    pub customer_id: Uuid,
    pub customer_name: String,
    pub customer_reference: String,
    /// installation | stock. Locked once the order is confirmed.
    pub purpose: String,
    /// Country the goods are delivered to (ISO alpha-2).
    pub delivery_country_code: Option<String>,
    /// The grid at the delivery country the goods are connected to (copied from the quotation).
    pub power_grid_id: Option<Uuid>,
    pub order_date: NaiveDate,
    /// When production expects the goods to be ready: the latest planned-ready date of the order's
    /// production orders (ADR 0036). Empty until production has planned it.
    pub promised_date: Option<NaiveDate>,
    pub currency: String,
    #[schema(value_type = String)]
    pub subtotal: Decimal,
    #[schema(value_type = String)]
    pub total: Decimal,
    pub salesperson_id: Uuid,
    pub salesperson_name: String,
}

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct OrderLine {
    /// Identifies the line of this revision (inventory reserves stock against it).
    pub id: Uuid,
    pub position: i32,
    pub product_id: Option<Uuid>,
    pub product_code: String,
    pub description: String,
    pub unit: String,
    #[schema(value_type = String)]
    pub quantity: Decimal,
    #[schema(value_type = String)]
    pub list_unit_price: Decimal,
    /// list | net | indicative
    pub pricing_type: String,
    #[schema(value_type = String)]
    pub rebate_percent: Decimal,
    #[schema(value_type = String)]
    pub line_discount_percent: Decimal,
    #[schema(value_type = String)]
    pub net_unit_price: Decimal,
    #[schema(value_type = String)]
    pub line_total: Decimal,
    #[schema(value_type = String)]
    pub vat_rate: Decimal,
    /// Internal remark for production (never printed for or shown to the customer).
    #[schema(required = false)]
    pub production_remark: String,
    /// Remark printed under the description on the order confirmation.
    #[schema(required = false)]
    pub customer_remark: String,
}

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct OrderRevisionInfo {
    pub revision: i32,
    /// draft | sent | confirmed | superseded
    pub status: String,
    #[schema(value_type = String)]
    pub subtotal: Decimal,
    #[schema(value_type = String)]
    pub total: Decimal,
    pub created_at: DateTime<Utc>,
    pub sent_at: Option<DateTime<Utc>>,
    /// The address the order confirmation was e-mailed to.
    pub sent_to: Option<String>,
}

/// One revision of an order (the latest unless asked otherwise) with its lines.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct Order {
    pub order: OrderSummary,
    /// Raised on every change to the order. Send it back as `expected_version` when saving: an
    /// order someone else changed meanwhile is refused (409 `record_changed`).
    pub version: i64,
    /// The revision these lines and totals belong to.
    pub revision: i32,
    pub revision_status: String,
    #[schema(value_type = String)]
    pub vat_total: Decimal,
    pub notes: String,
    pub created_at: DateTime<Utc>,
    pub confirmed_at: Option<DateTime<Utc>>,
    /// A staff user id (`confirmed_via` = staff) or a contact id (portal).
    pub confirmed_by: Option<Uuid>,
    /// staff | portal
    pub confirmed_via: Option<String>,
    pub confirmed_revision: Option<i32>,
    pub confirmation_note: String,
    pub cancel_reason: String,
    pub revisions: Vec<OrderRevisionInfo>,
    pub lines: Vec<OrderLine>,
    /// Power grid and incompatible-product hints; only filled by the confirm call. Never blocking.
    pub warnings: Vec<crate::model::SalesWarning>,
    /// Products worth adding; only filled by the confirm call.
    pub suggestions: Vec<crate::model::SalesSuggestion>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct ConvertInput {
    /// The customer's purchase order number or reference.
    #[serde(default)]
    pub customer_reference: String,
    #[serde(default)]
    pub notes: String,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct OrderLineEdit {
    /// The position of the line in the current draft revision.
    pub position: i32,
    #[schema(value_type = String, example = "2")]
    pub quantity: Decimal,
    #[serde(default)]
    #[schema(value_type = String, example = "0")]
    pub line_discount_percent: Decimal,
    /// Replaces the description; empty keeps the current one.
    pub description: Option<String>,
}

/// Changes to a draft revision. Lines that are left out are removed; prices and rebates stay as
/// agreed on the quotation, the totals are recomputed by the server.
#[derive(Debug, Deserialize, ToSchema)]
pub struct OrderEditInput {
    pub customer_reference: Option<String>,
    /// `installation` or `stock`; unchanged when omitted. Cannot be changed after confirmation.
    pub purpose: Option<String>,
    /// Delivery country (ISO alpha-2); unchanged when omitted.
    pub delivery_country_code: Option<String>,
    /// The power grid at the delivery country (the new one when it changes, else the stored one);
    /// it must belong to it (422). Unchanged when omitted, except that a grid the new delivery
    /// country does not have is cleared.
    pub power_grid_id: Option<Uuid>,
    /// `true` clears the grid ("any grid of the delivery country"); it wins over keeping the stored
    /// one and is refused (422) together with a `power_grid_id`. Absent or `false`: no effect.
    pub clear_power_grid: Option<bool>,
    #[serde(default)]
    pub notes: String,
    /// The `version` the form was loaded with. An order that has changed since is refused (409
    /// `record_changed`); left out, the save always goes through.
    #[serde(default)]
    pub expected_version: Option<i64>,
    pub lines: Vec<OrderLineEdit>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct ConfirmOrderInput {
    /// The revision being confirmed; refused when it is not the latest. Defaults to the latest.
    pub revision: Option<i32>,
    #[serde(default)]
    pub note: String,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct CancelOrderInput {
    pub reason: String,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct OrderPage {
    pub items: Vec<OrderSummary>,
    pub total: i64,
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct ListParams {
    /// Searches order number, quotation number, customer name and customer reference.
    pub q: Option<String>,
    pub customer_id: Option<Uuid>,
    pub status: Option<String>,
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}

const SELECT: &str = "SELECT o.id, o.number, o.status, o.priority, o.current_revision, o.quotation_id,
        q.number AS quotation_number, q.revision AS quotation_revision, o.customer_id, o.customer_name,
        o.customer_reference, o.purpose, o.delivery_country_code::text AS delivery_country_code,
        o.power_grid_id, o.order_date, o.promised_date, o.currency::text AS currency, o.subtotal, o.total, o.salesperson_id,
        u.display_name AS salesperson_name
     FROM sales.orders o
     JOIN sales.quotations q ON q.id = o.quotation_id
     JOIN core.users u ON u.id = o.salesperson_id";

/// The order row, locked for the rest of the transaction.
#[derive(Debug, FromRow)]
pub(crate) struct Head {
    pub id: Uuid,
    pub number: String,
    pub status: String,
    pub current_revision: i32,
    pub customer_id: Uuid,
    pub quotation_id: Uuid,
    pub version: i64,
}

pub(crate) async fn lock(conn: &mut PgConnection, company_id: Uuid, id: Uuid) -> AppResult<Head> {
    sqlx::query_as(
        "SELECT id, number, status, current_revision, customer_id, quotation_id, version
         FROM sales.orders WHERE id = $1 AND company_id = $2 FOR UPDATE",
    )
    .bind(id)
    .bind(company_id)
    .fetch_optional(conn)
    .await?
    .ok_or(AppError::NotFound("order"))
}

/// What delivery (ADR 0035) needs to know of an order.
#[derive(Debug, FromRow)]
pub struct DeliveryHead {
    pub id: Uuid,
    pub number: String,
    pub status: String,
    pub customer_id: Uuid,
    pub customer_name: String,
    /// The revision that was confirmed: the one that is delivered.
    pub revision: i32,
}

/// Locks an order for delivery (until the transaction ends) and returns what delivery needs.
pub async fn lock_for_delivery(
    conn: &mut PgConnection,
    company_id: Uuid,
    id: Uuid,
) -> AppResult<DeliveryHead> {
    sqlx::query_as(
        "SELECT id, number, status, customer_id, customer_name,
                COALESCE(confirmed_revision, current_revision) AS revision
         FROM sales.orders WHERE id = $1 AND company_id = $2 FOR UPDATE",
    )
    .bind(id)
    .bind(company_id)
    .fetch_optional(conn)
    .await?
    .ok_or(AppError::NotFound("order"))
}

/// What delivery needs to know of an order, without locking it (for reads).
pub async fn delivery_head(
    conn: &mut PgConnection,
    company_id: Uuid,
    id: Uuid,
) -> AppResult<DeliveryHead> {
    sqlx::query_as(
        "SELECT id, number, status, customer_id, customer_name,
                COALESCE(confirmed_revision, current_revision) AS revision
         FROM sales.orders WHERE id = $1 AND company_id = $2",
    )
    .bind(id)
    .bind(company_id)
    .fetch_optional(conn)
    .await?
    .ok_or(AppError::NotFound("order"))
}

/// The lines of one revision of an order.
pub async fn delivery_lines(
    conn: &mut PgConnection,
    order_id: Uuid,
    revision: i32,
) -> AppResult<Vec<OrderLine>> {
    revision_lines(conn, order_id, revision).await
}

/// The statuses production drives, in order. An order only moves forward through them.
const PRODUCTION_STATUSES: [&str; 4] = [
    "in_planning",
    "planned",
    "in_production",
    "ready_for_shipping",
];

/// Sets where an order is in production and when it is promised (ADR 0036). Production calls this
/// after every change to its production orders. Only forward moves are allowed, starting from
/// `confirmed`; a cancelled, shipped or not yet confirmed order is refused. Setting the status it
/// already has only updates the promised date. Audited, in the caller's transaction.
pub async fn set_production_status(
    conn: &mut PgConnection,
    user: &CurrentUser,
    order_id: Uuid,
    status: &str,
    promised_date: Option<NaiveDate>,
) -> AppResult<()> {
    let target = PRODUCTION_STATUSES
        .iter()
        .position(|s| *s == status)
        .ok_or_else(|| AppError::Validation(format!("{status} is not a production status")))?;
    let head = lock(conn, user.company_id, order_id).await?;
    let current = if head.status == "confirmed" {
        None
    } else {
        PRODUCTION_STATUSES
            .iter()
            .position(|s| *s == head.status.as_str())
    };
    if head.status != "confirmed" && current.is_none() {
        return Err(AppError::Conflict(format!(
            "order {} is {}; production can only follow a confirmed order",
            head.number, head.status
        )));
    }
    if current.is_some_and(|c| c > target) {
        return Err(AppError::Conflict(format!(
            "order {} is already {}; it cannot go back to {status}",
            head.number, head.status
        )));
    }
    sqlx::query(
        "UPDATE sales.orders SET status = $2, promised_date = $3, updated_at = now() WHERE id = $1",
    )
    .bind(order_id)
    .bind(status)
    .bind(promised_date)
    .execute(&mut *conn)
    .await?;
    if head.status != status || promised_date.is_some() {
        audit::record(
            conn,
            user,
            "order",
            order_id,
            status,
            serde_json::json!({ "from": head.status, "promised_date": promised_date }),
        )
        .await?;
    }
    Ok(())
}

/// Records that goods of the order have shipped: `partially_shipped` while quantities are open,
/// `shipped` once everything is delivered. The caller (delivery) has locked the order and checked
/// its status.
pub async fn mark_shipped(
    conn: &mut PgConnection,
    user: &CurrentUser,
    order_id: Uuid,
    complete: bool,
    delivery_note_id: Uuid,
) -> AppResult<()> {
    let status = if complete {
        "shipped"
    } else {
        "partially_shipped"
    };
    sqlx::query(
        "UPDATE sales.orders SET status = $2, updated_at = now() WHERE id = $1 AND company_id = $3",
    )
    .bind(order_id)
    .bind(status)
    .bind(user.company_id)
    .execute(&mut *conn)
    .await?;
    audit::record(
        conn,
        user,
        "order",
        order_id,
        status,
        serde_json::json!({ "delivery_note_id": delivery_note_id }),
    )
    .await?;
    Ok(())
}

const LINE_COLUMNS: &str =
    "id, position, product_id, product_code, description, unit, quantity, list_unit_price,
    pricing_type, rebate_percent, line_discount_percent, net_unit_price, line_total, vat_rate,
    production_remark, customer_remark";

pub(crate) async fn revision_lines(
    conn: &mut PgConnection,
    order_id: Uuid,
    revision: i32,
) -> AppResult<Vec<OrderLine>> {
    Ok(sqlx::query_as(&format!(
        "SELECT {LINE_COLUMNS} FROM sales.order_lines WHERE order_id = $1 AND revision = $2 ORDER BY position"
    ))
    .bind(order_id)
    .bind(revision)
    .fetch_all(conn)
    .await?)
}

async fn insert_lines(
    conn: &mut PgConnection,
    order_id: Uuid,
    revision: i32,
    lines: &[OrderLine],
) -> AppResult<()> {
    for l in lines {
        sqlx::query(
            "INSERT INTO sales.order_lines (id, order_id, revision, position, product_id, product_code, description,
                unit, quantity, list_unit_price, pricing_type, rebate_percent, line_discount_percent,
                net_unit_price, line_total, vat_rate, production_remark, customer_remark)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18)",
        )
        .bind(new_id())
        .bind(order_id)
        .bind(revision)
        .bind(l.position)
        .bind(l.product_id)
        .bind(&l.product_code)
        .bind(&l.description)
        .bind(&l.unit)
        .bind(l.quantity)
        .bind(l.list_unit_price)
        .bind(&l.pricing_type)
        .bind(l.rebate_percent)
        .bind(l.line_discount_percent)
        .bind(l.net_unit_price)
        .bind(l.line_total)
        .bind(l.vat_rate)
        .bind(&l.production_remark)
        .bind(&l.customer_remark)
        .execute(&mut *conn)
        .await?;
    }
    Ok(())
}

/// Loads an order with one of its revisions (the latest by default).
pub async fn load_order(
    conn: &mut PgConnection,
    company_id: Uuid,
    id: Uuid,
    revision: Option<i32>,
) -> AppResult<Order> {
    let mut order: OrderSummary =
        sqlx::query_as(&format!("{SELECT} WHERE o.id = $1 AND o.company_id = $2"))
            .bind(id)
            .bind(company_id)
            .fetch_optional(&mut *conn)
            .await?
            .ok_or(AppError::NotFound("order"))?;
    #[derive(FromRow)]
    struct Extra {
        version: i64,
        created_at: DateTime<Utc>,
        confirmed_at: Option<DateTime<Utc>>,
        confirmed_by: Option<Uuid>,
        confirmed_via: Option<String>,
        confirmed_revision: Option<i32>,
        confirmation_note: String,
        cancel_reason: String,
    }
    let extra: Extra = sqlx::query_as(
        "SELECT version, created_at, confirmed_at, confirmed_by, confirmed_via, confirmed_revision, confirmation_note,
                cancel_reason
         FROM sales.orders WHERE id = $1",
    )
    .bind(id)
    .fetch_one(&mut *conn)
    .await?;
    let revisions: Vec<OrderRevisionInfo> = sqlx::query_as(
        "SELECT revision, status, subtotal, total, created_at, sent_at, sent_to
         FROM sales.order_revisions WHERE order_id = $1 ORDER BY revision",
    )
    .bind(id)
    .fetch_all(&mut *conn)
    .await?;
    let wanted = revision.unwrap_or(order.current_revision);
    let info = revisions
        .iter()
        .find(|r| r.revision == wanted)
        .ok_or(AppError::NotFound("order revision"))?
        .clone();
    let (vat_total, notes): (Decimal, String) = sqlx::query_as(
        "SELECT vat_total, notes FROM sales.order_revisions WHERE order_id = $1 AND revision = $2",
    )
    .bind(id)
    .bind(wanted)
    .fetch_one(&mut *conn)
    .await?;
    order.subtotal = info.subtotal;
    order.total = info.total;
    let lines = revision_lines(conn, id, wanted).await?;
    Ok(Order {
        order,
        version: extra.version,
        revision: wanted,
        revision_status: info.status,
        vat_total,
        notes,
        created_at: extra.created_at,
        confirmed_at: extra.confirmed_at,
        confirmed_by: extra.confirmed_by,
        confirmed_via: extra.confirmed_via,
        confirmed_revision: extra.confirmed_revision,
        confirmation_note: extra.confirmation_note,
        cancel_reason: extra.cancel_reason,
        revisions,
        lines,
        warnings: Vec::new(),
        suggestions: Vec::new(),
    })
}

/// Stores totals and notes on a revision and mirrors them on the order row (which always shows
/// the latest revision).
async fn save_totals(
    conn: &mut PgConnection,
    order_id: Uuid,
    revision: i32,
    lines: &[OrderLine],
    notes: &str,
) -> AppResult<()> {
    let t = order_doc::order_totals(lines);
    sqlx::query(
        "UPDATE sales.order_revisions SET subtotal = $3, vat_total = $4, total = $5, notes = $6
         WHERE order_id = $1 AND revision = $2",
    )
    .bind(order_id)
    .bind(revision)
    .bind(t.subtotal)
    .bind(t.vat_total)
    .bind(t.total)
    .bind(notes)
    .execute(&mut *conn)
    .await?;
    sqlx::query(
        "UPDATE sales.orders SET subtotal = $3, vat_total = $4, total = $5, notes = $6, updated_at = now()
         WHERE id = $1 AND current_revision = $2",
    )
    .bind(order_id)
    .bind(revision)
    .bind(t.subtotal)
    .bind(t.vat_total)
    .bind(t.total)
    .bind(notes)
    .execute(conn)
    .await?;
    Ok(())
}

/// Converts a sent or accepted quotation into a draft sales order (revision 1), in the caller's
/// transaction. A sent quotation is marked accepted (and its opportunity won) first.
pub async fn convert_quotation(
    conn: &mut PgConnection,
    user: &CurrentUser,
    quotation_id: Uuid,
    input: &ConvertInput,
) -> AppResult<Uuid> {
    user.require(Permission::OrdersWrite)?;
    let q = service::load_quotation(conn, user.company_id, quotation_id, true).await?;
    let existing: Option<String> =
        sqlx::query_scalar("SELECT number FROM sales.orders WHERE quotation_id = $1")
            .bind(quotation_id)
            .fetch_optional(&mut *conn)
            .await?;
    if let Some(n) = existing {
        return Err(AppError::Conflict(format!(
            "quotation {} is already order {n}",
            q.number
        )));
    }
    match service::status_of(&q) {
        QuotationStatus::Sent => {
            sqlx::query(
                "UPDATE sales.quotations SET status = 'accepted', updated_at = now() WHERE id = $1",
            )
            .bind(quotation_id)
            .execute(&mut *conn)
            .await?;
            audit::record(
                conn,
                user,
                "quotation",
                quotation_id,
                "accepted",
                serde_json::json!({ "from": "sent" }),
            )
            .await?;
            if let Some(opp) = q.opportunity_id {
                tradocraft_crm::opportunities::mark_won(conn, user, opp).await?;
            }
        }
        QuotationStatus::Accepted => {}
        other => {
            return Err(AppError::Conflict(format!(
                "quotation {} rev. {} is {}; only a sent or accepted revision can become an order",
                q.number,
                q.revision,
                other.as_str()
            )))
        }
    }
    let today = tradocraft_core::today();
    let n = numbering::next_number(conn, user.company_id, "order", today.year()).await?;
    let number = format!("SO{}-{n:05}", today.year());
    let id = new_id();
    sqlx::query(
        "INSERT INTO sales.orders (id, company_id, number, status, current_revision, quotation_id, customer_id,
                                   customer_name, customer_reference, order_date, currency, subtotal, vat_total,
                                   total, salesperson_id, notes, created_by, purpose, delivery_country_code, power_grid_id)
         VALUES ($1, $2, $3, 'draft', 1, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18)",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(&number)
    .bind(quotation_id)
    .bind(q.customer_id)
    .bind(&q.customer_name)
    .bind(input.customer_reference.trim())
    .bind(today)
    .bind(&q.currency)
    .bind(q.subtotal)
    .bind(q.vat_total)
    .bind(q.total)
    .bind(q.created_by)
    .bind(&input.notes)
    .bind(user.user_id)
    .bind(&q.purpose)
    .bind(&q.delivery_country_code)
    .bind(q.power_grid_id)
    .execute(&mut *conn)
    .await?;
    sqlx::query(
        "INSERT INTO sales.order_revisions (id, order_id, revision, status, notes, subtotal, vat_total, total,
                                           created_by)
         VALUES ($1, $2, 1, 'draft', $3, $4, $5, $6, $7)",
    )
    .bind(new_id())
    .bind(id)
    .bind(&input.notes)
    .bind(q.subtotal)
    .bind(q.vat_total)
    .bind(q.total)
    .bind(user.user_id)
    .execute(&mut *conn)
    .await?;
    sqlx::query(
        "INSERT INTO sales.order_lines (id, order_id, revision, position, product_id, product_code, description, unit,
                quantity, list_unit_price, pricing_type, rebate_percent, line_discount_percent, net_unit_price,
                line_total, vat_rate, production_remark, customer_remark)
         SELECT gen_random_uuid(), $2, 1, position, product_id, product_code, description, unit, quantity,
                list_unit_price, pricing_type, rebate_percent, line_discount_percent, net_unit_price, line_total,
                vat_rate, production_remark, customer_remark
         FROM sales.quotation_lines WHERE quotation_id = $1",
    )
    .bind(quotation_id)
    .bind(id)
    .execute(&mut *conn)
    .await?;
    audit::record(
        conn,
        user,
        "order",
        id,
        "created",
        serde_json::json!({ "number": number, "quotation": q.number, "revision": q.revision }),
    )
    .await?;
    Ok(id)
}

/// Converts a sent or accepted quotation revision into a draft sales order (revision 1).
#[utoipa::path(post, path = "/quotations/{id}/convert", tag = "sales", params(("id" = Uuid, Path)),
    request_body = ConvertInput,
    responses((status = 201, body = Order), (status = 409, body = ErrorBody)))]
async fn convert(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<ConvertInput>,
) -> AppResult<(StatusCode, Json<Order>)> {
    let mut tx = state.db.begin().await?;
    let order_id = convert_quotation(&mut tx, &user, id, &input).await?;
    let order = load_order(&mut tx, user.company_id, order_id, None).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(order)))
}

#[utoipa::path(get, path = "/orders", tag = "sales", params(ListParams), responses((status = 200, body = OrderPage)))]
async fn list_orders(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(p): Query<ListParams>,
) -> AppResult<Json<OrderPage>> {
    user.require(Permission::OrdersRead)?;
    let pattern =
        p.q.as_deref()
            .map(|q| format!("%{}%", q.trim().to_lowercase()));
    let filter = "WHERE o.company_id = $1
          AND ($2::text IS NULL OR lower(o.number) LIKE $2 OR lower(q.number) LIKE $2
               OR lower(o.customer_name) LIKE $2 OR lower(o.customer_reference) LIKE $2)
          AND ($3::uuid IS NULL OR o.customer_id = $3)
          AND ($4::text IS NULL OR o.status = $4)";
    let items = sqlx::query_as(&format!(
        "{SELECT} {filter} ORDER BY o.order_date DESC, o.number DESC LIMIT $5 OFFSET $6"
    ))
    .bind(user.company_id)
    .bind(&pattern)
    .bind(p.customer_id)
    .bind(&p.status)
    .bind(p.limit.unwrap_or(50).clamp(1, 500))
    .bind(p.offset.unwrap_or(0).max(0))
    .fetch_all(&state.db)
    .await?;
    let total = sqlx::query_scalar(&format!(
        "SELECT count(*) FROM sales.orders o JOIN sales.quotations q ON q.id = o.quotation_id {filter}"
    ))
    .bind(user.company_id)
    .bind(&pattern)
    .bind(p.customer_id)
    .bind(&p.status)
    .fetch_one(&state.db)
    .await?;
    Ok(Json(OrderPage { items, total }))
}

/// The latest revision of an order.
#[utoipa::path(get, path = "/orders/{id}", tag = "sales", params(("id" = Uuid, Path)),
    responses((status = 200, body = Order), (status = 404, body = ErrorBody)))]
async fn get_order(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<Order>> {
    user.require(Permission::OrdersRead)?;
    let mut conn = state.db.acquire().await?;
    Ok(Json(
        load_order(&mut conn, user.company_id, id, None).await?,
    ))
}

/// A specific revision of an order, e.g. an older one that was sent.
#[utoipa::path(get, path = "/orders/{id}/revisions/{revision}", tag = "sales",
    params(("id" = Uuid, Path), ("revision" = i32, Path)),
    responses((status = 200, body = Order), (status = 404, body = ErrorBody)))]
async fn get_order_revision(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((id, revision)): Path<(Uuid, i32)>,
) -> AppResult<Json<Order>> {
    user.require(Permission::OrdersRead)?;
    let mut conn = state.db.acquire().await?;
    Ok(Json(
        load_order(&mut conn, user.company_id, id, Some(revision)).await?,
    ))
}

/// Edits the draft revision: quantities, discounts, descriptions and notes. Prices and rebates
/// stay as agreed on the quotation; totals are recomputed here.
#[utoipa::path(put, path = "/orders/{id}", tag = "sales", params(("id" = Uuid, Path)),
    request_body = OrderEditInput,
    responses((status = 200, body = Order), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn edit_order(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<OrderEditInput>,
) -> AppResult<Json<Order>> {
    user.require(Permission::OrdersWrite)?;
    if input.lines.is_empty() {
        return Err(AppError::Validation(
            "an order needs at least one line".into(),
        ));
    }
    service::check_grid_clear(input.clear_power_grid, input.power_grid_id)?;
    let purpose = input
        .purpose
        .as_deref()
        .map(service::validate_purpose)
        .transpose()?;
    let delivery_country = input
        .delivery_country_code
        .as_deref()
        .map(service::normalize_country)
        .transpose()?
        .flatten();
    let mut tx = state.db.begin().await?;
    let head = lock(&mut tx, user.company_id, id).await?;
    tradocraft_core::concurrency::check_version(
        input.expected_version,
        head.version,
        &format!("order {}", head.number),
    )?;
    if head.status != "draft" {
        let current: String = sqlx::query_scalar("SELECT purpose FROM sales.orders WHERE id = $1")
            .bind(id)
            .fetch_one(&mut *tx)
            .await?;
        if purpose.is_some_and(|p| p != current) {
            return Err(AppError::Conflict(format!(
                "order {} is {}; its purpose can no longer be changed",
                head.number, head.status
            )));
        }
        return Err(AppError::Conflict(format!(
            "order {} is {}; only a draft can be changed (create a new revision for a sent order)",
            head.number, head.status
        )));
    }
    let current = revision_lines(&mut tx, id, head.current_revision).await?;
    let mut seen = Vec::new();
    let mut lines = Vec::with_capacity(input.lines.len());
    for (i, e) in input.lines.iter().enumerate() {
        let old = current
            .iter()
            .find(|l| l.position == e.position)
            .ok_or_else(|| AppError::Validation(format!("there is no line {}", e.position)))?;
        if seen.contains(&e.position) {
            return Err(AppError::Validation(format!(
                "line {} appears twice",
                e.position
            )));
        }
        seen.push(e.position);
        if old.pricing_type == "net" && !e.line_discount_percent.is_zero() {
            return Err(AppError::Validation(format!(
                "line {}: {} has a net price and cannot be discounted",
                e.position, old.product_code
            )));
        }
        let p = price_line(&LineInput {
            list_unit_price: old.list_unit_price,
            quantity: e.quantity,
            customer_discount_percent: old.rebate_percent,
            line_discount_percent: e.line_discount_percent,
            vat_rate: old.vat_rate,
        })
        .map_err(|err| AppError::Validation(format!("line {}: {err}", e.position)))?;
        lines.push(OrderLine {
            id: new_id(),
            position: i as i32 + 1,
            description: e
                .description
                .clone()
                .filter(|d| !d.trim().is_empty())
                .unwrap_or_else(|| old.description.clone()),
            quantity: p.quantity,
            line_discount_percent: p.line_discount_percent,
            net_unit_price: p.net_unit_price,
            line_total: p.line_total,
            ..old.clone()
        });
    }
    sqlx::query("DELETE FROM sales.order_lines WHERE order_id = $1 AND revision = $2")
        .bind(id)
        .bind(head.current_revision)
        .execute(&mut *tx)
        .await?;
    insert_lines(&mut tx, id, head.current_revision, &lines).await?;
    save_totals(&mut tx, id, head.current_revision, &lines, &input.notes).await?;
    if let Some(r) = &input.customer_reference {
        sqlx::query("UPDATE sales.orders SET customer_reference = $2 WHERE id = $1")
            .bind(id)
            .bind(r.trim())
            .execute(&mut *tx)
            .await?;
    }
    let clear_grid = input.clear_power_grid == Some(true);
    if delivery_country.is_some() || input.power_grid_id.is_some() || clear_grid {
        let (stored_country, stored_grid): (Option<String>, Option<Uuid>) = sqlx::query_as(
            "SELECT delivery_country_code::text, power_grid_id FROM sales.orders WHERE id = $1",
        )
        .bind(id)
        .fetch_one(&mut *tx)
        .await?;
        let country = delivery_country.clone().or(stored_country);
        // A given grid must belong to the (new or stored) country; the stored one stays only while
        // it fits, so a country change drops a grid it does not have, and a clear wins.
        let grid = service::resolve_power_grid(
            &mut tx,
            input.power_grid_id,
            if clear_grid { None } else { stored_grid },
            country.as_deref(),
        )
        .await?;
        if grid != stored_grid {
            sqlx::query("UPDATE sales.orders SET power_grid_id = $2 WHERE id = $1")
                .bind(id)
                .bind(grid)
                .execute(&mut *tx)
                .await?;
        }
    }
    if purpose.is_some() || delivery_country.is_some() {
        sqlx::query(
            "UPDATE sales.orders SET purpose = COALESCE($2, purpose),
                    delivery_country_code = COALESCE($3, delivery_country_code)
             WHERE id = $1",
        )
        .bind(id)
        .bind(purpose)
        .bind(&delivery_country)
        .execute(&mut *tx)
        .await?;
    }
    audit::record(
        &mut tx,
        &user,
        "order",
        id,
        "updated",
        serde_json::json!({ "revision": head.current_revision }),
    )
    .await?;
    let order = load_order(&mut tx, user.company_id, id, None).await?;
    tx.commit().await?;
    Ok(Json(order))
}

/// Starts the next revision as a draft, copying the latest one. The sent revision is kept and
/// marked superseded: the customer can no longer confirm it.
#[utoipa::path(post, path = "/orders/{id}/revisions", tag = "sales", params(("id" = Uuid, Path)),
    responses((status = 201, body = Order), (status = 409, body = ErrorBody)))]
async fn new_revision(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<(StatusCode, Json<Order>)> {
    user.require(Permission::OrdersWrite)?;
    let mut tx = state.db.begin().await?;
    let head = lock(&mut tx, user.company_id, id).await?;
    match head.status.as_str() {
        "sent" => {}
        "draft" => {
            return Err(AppError::Conflict(format!(
                "order {} is still a draft; change it directly",
                head.number
            )))
        }
        other => {
            return Err(AppError::Conflict(format!(
                "order {} is {other}; only a sent order can be revised",
                head.number
            )))
        }
    }
    let old = head.current_revision;
    let new = old + 1;
    sqlx::query(
        "UPDATE sales.order_revisions SET status = 'superseded' WHERE order_id = $1 AND revision = $2",
    )
    .bind(id)
    .bind(old)
    .execute(&mut *tx)
    .await?;
    sqlx::query(
        "INSERT INTO sales.order_revisions (id, order_id, revision, status, notes, subtotal, vat_total, total,
                                           created_by)
         SELECT $3, order_id, $4, 'draft', notes, subtotal, vat_total, total, $5
         FROM sales.order_revisions WHERE order_id = $1 AND revision = $2",
    )
    .bind(id)
    .bind(old)
    .bind(new_id())
    .bind(new)
    .bind(user.user_id)
    .execute(&mut *tx)
    .await?;
    let lines = revision_lines(&mut tx, id, old).await?;
    insert_lines(&mut tx, id, new, &lines).await?;
    sqlx::query(
        "UPDATE sales.orders SET current_revision = $2, status = 'draft', updated_at = now() WHERE id = $1",
    )
    .bind(id)
    .bind(new)
    .execute(&mut *tx)
    .await?;
    audit::record(
        &mut tx,
        &user,
        "order",
        id,
        "revised",
        serde_json::json!({ "revision": new, "supersedes": old }),
    )
    .await?;
    let order = load_order(&mut tx, user.company_id, id, None).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(order)))
}

struct Recipient {
    address: String,
    contact_id: Option<Uuid>,
    language: String,
}

/// Who gets the order confirmation: the contact on the ticket the order or its quotation came
/// from, otherwise the customer's main address. The language is the contact's own or the
/// customer's.
async fn recipient(
    conn: &mut PgConnection,
    company_id: Uuid,
    head: &Head,
    customer_language: &str,
) -> AppResult<Recipient> {
    let ticket: Option<(Option<Uuid>, String)> = sqlx::query_as(
        "SELECT t.contact_id, t.contact_email FROM helpdesk.tickets t
         WHERE t.company_id = $1 AND (t.order_id = $2 OR t.quotation_id = $3)
           AND (t.customer_id IS NULL OR t.customer_id = $4)
           AND (t.contact_id IS NOT NULL OR t.contact_email <> '')
         ORDER BY (t.order_id = $2) DESC, t.created_at DESC LIMIT 1",
    )
    .bind(company_id)
    .bind(head.id)
    .bind(head.quotation_id)
    .bind(head.customer_id)
    .fetch_optional(&mut *conn)
    .await?;
    if let Some((contact_id, email)) = ticket {
        if let Some(cid) = contact_id {
            let c = contacts::get_contact(conn, cid).await?;
            if let Some(address) = c.primary_email() {
                return Ok(Recipient {
                    address: address.to_string(),
                    contact_id: Some(cid),
                    language: c.effective_language.clone(),
                });
            }
        }
        if email.contains('@') {
            return Ok(Recipient {
                address: email,
                contact_id,
                language: customer_language.to_string(),
            });
        }
    }
    let email: Option<String> = sqlx::query_scalar("SELECT email FROM crm.customers WHERE id = $1")
        .bind(head.customer_id)
        .fetch_one(&mut *conn)
        .await?;
    match email.filter(|e| e.contains('@')) {
        Some(address) => Ok(Recipient {
            address,
            contact_id: None,
            language: customer_language.to_string(),
        }),
        None => Err(AppError::Conflict(format!(
            "order {} cannot be sent: there is no e-mail address for the customer; add a contact with an \
             address to the ticket or an e-mail address to the customer first",
            head.number
        ))),
    }
}

async fn customer_snapshot(
    conn: &mut PgConnection,
    quotation_id: Uuid,
) -> AppResult<(CustomerSnapshot, String)> {
    #[derive(FromRow)]
    struct Snap {
        number: String,
        customer_vat_number: Option<String>,
        customer_street: String,
        customer_postal_code: String,
        customer_city: String,
        customer_country_code: String,
        customer_language: String,
    }
    let r: Snap = sqlx::query_as(
        "SELECT number, customer_vat_number, customer_street, customer_postal_code, customer_city,
                customer_country_code::text AS customer_country_code, customer_language::text AS customer_language
         FROM sales.quotations WHERE id = $1",
    )
    .bind(quotation_id)
    .fetch_one(conn)
    .await?;
    Ok((
        CustomerSnapshot {
            vat_number: r.customer_vat_number,
            street: r.customer_street,
            postal_code: r.customer_postal_code,
            city: r.customer_city,
            country_code: r.customer_country_code,
            quotation_number: r.number,
        },
        r.customer_language,
    ))
}

async fn render_confirmation(
    state: &AppState,
    company_id: Uuid,
    order: &Order,
    snapshot: &CustomerSnapshot,
    language: &str,
) -> AppResult<Vec<u8>> {
    let company = get_company(&state.db, company_id).await?;
    let doc = order_doc::document(&company, order, snapshot, language);
    Ok(tradocraft_documents::render_pdf(&state.documents, "order_confirmation", &doc).await?)
}

fn pdf_filename(order: &Order) -> String {
    format!("{}-r{}.pdf", order.order.number, order.revision)
}

/// Sends the draft revision: it becomes `sent`, the order confirmation PDF is rendered in the
/// customer's language and queued as an e-mail for the worker. Refused (409) when there is no
/// address to send it to.
#[utoipa::path(post, path = "/orders/{id}/send", tag = "sales", params(("id" = Uuid, Path)),
    responses((status = 200, body = Order), (status = 409, body = ErrorBody)))]
async fn send_order(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<Order>> {
    user.require(Permission::OrdersWrite)?;
    let mut tx = state.db.begin().await?;
    let head = lock(&mut tx, user.company_id, id).await?;
    if head.status != "draft" {
        return Err(AppError::Conflict(format!(
            "order {} is {}; only a draft revision can be sent",
            head.number, head.status
        )));
    }
    let (snapshot, customer_language) = customer_snapshot(&mut tx, head.quotation_id).await?;
    let to = recipient(&mut tx, user.company_id, &head, &customer_language).await?;
    sqlx::query("UPDATE sales.orders SET contact_id = $2 WHERE id = $1")
        .bind(id)
        .bind(to.contact_id)
        .execute(&mut *tx)
        .await?;
    sqlx::query(
        "UPDATE sales.order_revisions SET status = 'sent', sent_at = now(), sent_by = $3, sent_to = $4
         WHERE order_id = $1 AND revision = $2",
    )
    .bind(id)
    .bind(head.current_revision)
    .bind(user.user_id)
    .bind(&to.address)
    .execute(&mut *tx)
    .await?;
    sqlx::query("UPDATE sales.orders SET status = 'sent', updated_at = now() WHERE id = $1")
        .bind(id)
        .execute(&mut *tx)
        .await?;
    let order = load_order(&mut tx, user.company_id, id, None).await?;
    let pdf = render_confirmation(&state, user.company_id, &order, &snapshot, &to.language).await?;
    let company = get_company(&state.db, user.company_id).await?;
    let (subject, body) = order_doc::confirmation_mail(
        &to.language,
        &company.name,
        &order.order.customer_name,
        &order.order.number,
        order.revision,
    );
    tradocraft_core::mail::enqueue_with_attachment(
        &mut tx,
        user.company_id,
        &to.address,
        &subject,
        &body,
        Attachment {
            filename: &pdf_filename(&order),
            content_type: "application/pdf",
            data: &pdf,
        },
    )
    .await?;
    audit::record(
        &mut tx,
        &user,
        "order",
        id,
        "sent",
        serde_json::json!({ "revision": order.revision, "to": to.address }),
    )
    .await?;
    tx.commit().await?;
    Ok(Json(order))
}

/// The order confirmation of one revision as PDF (a draft carries a watermark).
#[utoipa::path(get, path = "/orders/{id}/revisions/{revision}/pdf", tag = "sales",
    params(("id" = Uuid, Path), ("revision" = i32, Path)),
    responses((status = 200, content_type = "application/pdf", body = Vec<u8>), (status = 404, body = ErrorBody)))]
async fn order_pdf(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((id, revision)): Path<(Uuid, i32)>,
) -> AppResult<Response> {
    user.require(Permission::OrdersRead)?;
    let mut conn = state.db.acquire().await?;
    let order = load_order(&mut conn, user.company_id, id, Some(revision)).await?;
    let (snapshot, customer_language) =
        customer_snapshot(&mut conn, order.order.quotation_id).await?;
    let contact: Option<Uuid> =
        sqlx::query_scalar("SELECT contact_id FROM sales.orders WHERE id = $1")
            .bind(id)
            .fetch_one(&mut *conn)
            .await?;
    let language = match contact {
        Some(c) => {
            contacts::get_contact(&mut conn, c)
                .await?
                .effective_language
        }
        None => customer_language,
    };
    drop(conn);
    let bytes = render_confirmation(&state, user.company_id, &order, &snapshot, &language).await?;
    Ok((
        [
            (header::CONTENT_TYPE, "application/pdf".to_string()),
            (
                header::CONTENT_DISPOSITION,
                format!("inline; filename=\"{}\"", pdf_filename(&order)),
            ),
        ],
        bytes,
    )
        .into_response())
}

/// How a confirmation was given.
pub enum Confirmer<'a> {
    Staff(&'a CurrentUser),
    Portal { contact_id: Uuid },
}

/// Confirms the latest sent revision and freezes the order. Only the latest revision can be
/// confirmed; an older one is a conflict. Shared by staff (on the customer's behalf) and the portal.
pub async fn confirm_order(
    conn: &mut PgConnection,
    company_id: Uuid,
    order_id: Uuid,
    revision: Option<i32>,
    by: Confirmer<'_>,
    note: &str,
) -> AppResult<()> {
    let head = lock(conn, company_id, order_id).await?;
    if head.status == "cancelled" {
        return Err(AppError::Conflict(format!(
            "order {} is cancelled",
            head.number
        )));
    }
    if let Some(r) = revision.filter(|r| *r != head.current_revision) {
        return Err(AppError::Conflict(format!(
            "revision {r} of order {} is no longer current; the latest is revision {}",
            head.number, head.current_revision
        )));
    }
    match head.status.as_str() {
        "sent" => {}
        "draft" => {
            return Err(AppError::Conflict(format!(
                "revision {} of order {} has not been sent yet",
                head.current_revision, head.number
            )))
        }
        _ => {
            return Err(AppError::Conflict(format!(
                "order {} is already confirmed",
                head.number
            )))
        }
    }
    let (actor, via) = match &by {
        Confirmer::Staff(u) => (u.user_id, "staff"),
        Confirmer::Portal { contact_id } => (*contact_id, "portal"),
    };
    sqlx::query(
        "UPDATE sales.order_revisions SET status = 'confirmed' WHERE order_id = $1 AND revision = $2",
    )
    .bind(order_id)
    .bind(head.current_revision)
    .execute(&mut *conn)
    .await?;
    sqlx::query(
        "UPDATE sales.orders SET status = 'confirmed', confirmed_at = now(), confirmed_by = $2, confirmed_via = $3,
                confirmed_revision = $4, confirmation_note = $5, updated_at = now()
         WHERE id = $1",
    )
    .bind(order_id)
    .bind(actor)
    .bind(via)
    .bind(head.current_revision)
    .bind(note.trim())
    .execute(&mut *conn)
    .await?;
    // Production is informed through this event; there is no notification mechanism for it yet.
    let data = serde_json::json!({
        "number": head.number, "revision": head.current_revision, "via": via, "by": actor, "note": note.trim(),
    });
    match by {
        Confirmer::Staff(u) => audit::record(conn, u, "order", order_id, "confirmed", data).await?,
        Confirmer::Portal { .. } => {
            audit::record_system(conn, company_id, "order", order_id, "confirmed", data).await?
        }
    }
    Ok(())
}

/// Confirms the order on the customer's behalf (e.g. after a phone call or an e-mail).
#[utoipa::path(post, path = "/orders/{id}/confirm", tag = "sales", params(("id" = Uuid, Path)),
    request_body = ConfirmOrderInput,
    responses((status = 200, body = Order), (status = 409, body = ErrorBody)))]
async fn confirm(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<ConfirmOrderInput>,
) -> AppResult<Json<Order>> {
    user.require(Permission::OrdersWrite)?;
    let mut tx = state.db.begin().await?;
    confirm_order(
        &mut tx,
        user.company_id,
        id,
        input.revision,
        Confirmer::Staff(&user),
        &input.note,
    )
    .await?;
    let mut order = load_order(&mut tx, user.company_id, id, None).await?;
    let customer_country: String = sqlx::query_scalar(
        "SELECT customer_country_code::text FROM sales.quotations WHERE id = $1",
    )
    .bind(order.order.quotation_id)
    .fetch_one(&mut *tx)
    .await?;
    let country = order
        .order
        .delivery_country_code
        .clone()
        .unwrap_or(customer_country);
    let refs: Vec<(Option<Uuid>, &str)> = order
        .lines
        .iter()
        .map(|l| (l.product_id, l.product_code.as_str()))
        .collect();
    order.warnings = service::power_warnings(
        &mut tx,
        &order.order.purpose,
        &country,
        order.order.power_grid_id,
        &refs,
    )
    .await?;
    let (conflicts, suggestions) =
        service::relation_checks(&mut tx, &order.order.purpose, &refs).await?;
    order.warnings.extend(conflicts);
    order.suggestions = suggestions;
    tx.commit().await?;
    Ok(Json(order))
}

/// Cancels the order. Possible until it is ready for shipping; while it is in production only when
/// no production order is open any more (the planner cancels those first).
#[utoipa::path(post, path = "/orders/{id}/cancel", tag = "sales", params(("id" = Uuid, Path)),
    request_body = CancelOrderInput,
    responses((status = 200, body = Order), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn cancel(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<CancelOrderInput>,
) -> AppResult<Json<Order>> {
    user.require(Permission::OrdersWrite)?;
    if input.reason.trim().is_empty() {
        return Err(AppError::Validation("a reason is required".into()));
    }
    let mut tx = state.db.begin().await?;
    let head = lock(&mut tx, user.company_id, id).await?;
    if matches!(
        head.status.as_str(),
        "cancelled" | "ready_for_shipping" | "partially_shipped" | "shipped"
    ) {
        return Err(AppError::Conflict(format!(
            "order {} is {} and can no longer be cancelled",
            head.number, head.status
        )));
    }
    if head.status == "in_production" {
        // Sales cannot depend on production (production depends on sales), so this guard reads
        // production's table directly (ADR 0036).
        let open: bool = sqlx::query_scalar(
            "SELECT EXISTS (SELECT 1 FROM production.production_orders
                            WHERE order_id = $1 AND status IN ('released', 'in_progress'))",
        )
        .bind(id)
        .fetch_one(&mut *tx)
        .await?;
        if open {
            return Err(AppError::Conflict(format!(
                "order {} is in production; cancel its open production orders first",
                head.number
            )));
        }
    }
    sqlx::query(
        "UPDATE sales.orders SET status = 'cancelled', cancelled_at = now(), cancel_reason = $2, updated_at = now()
         WHERE id = $1",
    )
    .bind(id)
    .bind(input.reason.trim())
    .execute(&mut *tx)
    .await?;
    // Stock reserved for the order goes back to the free stock.
    tradocraft_inventory::release_for_order(&mut tx, user.company_id, id, Some(user.user_id))
        .await?;
    audit::record(
        &mut tx,
        &user,
        "order",
        id,
        "cancelled",
        serde_json::json!({ "from": head.status, "reason": input.reason.trim() }),
    )
    .await?;
    let order = load_order(&mut tx, user.company_id, id, None).await?;
    tx.commit().await?;
    Ok(Json(order))
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(convert))
        .routes(routes!(list_orders))
        .routes(routes!(get_order, edit_order))
        .routes(routes!(get_order_revision))
        .routes(routes!(new_revision))
        .routes(routes!(send_order))
        .routes(routes!(order_pdf))
        .routes(routes!(confirm))
        .routes(routes!(cancel))
}
