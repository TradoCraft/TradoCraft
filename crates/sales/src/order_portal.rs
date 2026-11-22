//! The customer's view of orders, for the portal. A customer sees only the latest revision that
//! was sent (never a draft; while a newer revision is being prepared they still see the last sent one) and no internal notes. With the `customer` portal scope
//! they see all orders of their customer; with `own` only the orders that were sent to them.

use chrono::{DateTime, NaiveDate, Utc};
use rust_decimal::Decimal;
use serde::Serialize;
use sqlx::{FromRow, PgConnection};
use tradocraft_core::{AppError, AppResult};
use utoipa::ToSchema;
use uuid::Uuid;

use crate::order_priority::{self, PriorityRequest};
use crate::orders::{self, Confirmer};

/// Who is looking, as far as orders are concerned.
pub struct PortalViewer {
    pub company_id: Uuid,
    pub customer_id: Uuid,
    pub contact_id: Uuid,
    /// own | customer
    pub scope: String,
}

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct PortalOrder {
    pub id: Uuid,
    pub number: String,
    /// sent | confirmed | cancelled
    pub status: String,
    /// The revision shown here: the latest that was sent or confirmed, never a draft.
    pub revision: i32,
    pub customer_reference: String,
    pub order_date: NaiveDate,
    pub currency: String,
    #[schema(value_type = String)]
    pub subtotal: Decimal,
    #[schema(value_type = String)]
    pub vat_total: Decimal,
    #[schema(value_type = String)]
    pub total: Decimal,
    pub confirmed_at: Option<DateTime<Utc>>,
    /// True while this revision is the latest and waits for the customer's confirmation.
    pub can_confirm: bool,
    pub open_priority_requests: i64,
}

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct PortalOrderLine {
    pub position: i32,
    pub product_code: String,
    pub description: String,
    pub unit: String,
    #[schema(value_type = String)]
    pub quantity: Decimal,
    #[schema(value_type = String)]
    pub list_unit_price: Decimal,
    #[schema(value_type = String)]
    pub net_unit_price: Decimal,
    #[schema(value_type = String)]
    pub line_total: Decimal,
    #[schema(value_type = String)]
    pub vat_rate: Decimal,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct PortalOrderDetail {
    pub order: PortalOrder,
    pub lines: Vec<PortalOrderLine>,
}

const SELECT: &str = "SELECT o.id, o.number,
        CASE WHEN o.status = 'cancelled' THEN 'cancelled' WHEN o.status IN ('draft', 'sent') THEN 'sent'
             ELSE 'confirmed' END AS status,
        r.revision, o.customer_reference, o.order_date, o.currency::text AS currency, r.subtotal, r.vat_total, r.total,
        o.confirmed_at,
        (o.status = 'sent' AND r.revision = o.current_revision AND r.status = 'sent') AS can_confirm,
        (SELECT count(*) FROM sales.order_priority_requests p WHERE p.order_id = o.id AND p.status = 'open')
            AS open_priority_requests
     FROM sales.orders o
     JOIN sales.order_revisions r ON r.order_id = o.id
          AND r.revision = (SELECT max(x.revision) FROM sales.order_revisions x
                            WHERE x.order_id = o.id AND x.status IN ('sent', 'confirmed', 'superseded'))";

const VISIBLE: &str =
    "o.company_id = $1 AND o.customer_id = $2 AND ($3 = 'customer' OR o.contact_id = $4)";

async fn load(conn: &mut PgConnection, v: &PortalViewer, id: Uuid) -> AppResult<PortalOrder> {
    sqlx::query_as(sqlx::AssertSqlSafe(format!("{SELECT} WHERE {VISIBLE} AND o.id = $5")))
        .bind(v.company_id)
        .bind(v.customer_id)
        .bind(&v.scope)
        .bind(v.contact_id)
        .bind(id)
        .fetch_optional(conn)
        .await?
        .ok_or(AppError::NotFound("order"))
}

pub async fn list(conn: &mut PgConnection, v: &PortalViewer) -> AppResult<Vec<PortalOrder>> {
    Ok(sqlx::query_as(sqlx::AssertSqlSafe(format!(
        "{SELECT} WHERE {VISIBLE} ORDER BY o.order_date DESC, o.number DESC LIMIT 200"
    )))
    .bind(v.company_id)
    .bind(v.customer_id)
    .bind(&v.scope)
    .bind(v.contact_id)
    .fetch_all(conn)
    .await?)
}

pub async fn get(
    conn: &mut PgConnection,
    v: &PortalViewer,
    id: Uuid,
) -> AppResult<PortalOrderDetail> {
    let order = load(conn, v, id).await?;
    let lines = sqlx::query_as(
        "SELECT position, product_code, description, unit, quantity, list_unit_price, net_unit_price, line_total,
                vat_rate
         FROM sales.order_lines WHERE order_id = $1 AND revision = $2 ORDER BY position",
    )
    .bind(id)
    .bind(order.revision)
    .fetch_all(conn)
    .await?;
    Ok(PortalOrderDetail { order, lines })
}

/// The contact confirms the revision they were shown. Older revisions are refused (409).
pub async fn confirm(
    conn: &mut PgConnection,
    v: &PortalViewer,
    id: Uuid,
    revision: i32,
    note: &str,
) -> AppResult<PortalOrderDetail> {
    load(conn, v, id).await?;
    orders::confirm_order(
        conn,
        v.company_id,
        id,
        Some(revision),
        Confirmer::Portal {
            contact_id: v.contact_id,
        },
        note,
    )
    .await?;
    get(conn, v, id).await
}

pub async fn request_priority(
    conn: &mut PgConnection,
    v: &PortalViewer,
    id: Uuid,
    priority: &str,
    message: &str,
) -> AppResult<PriorityRequest> {
    load(conn, v, id).await?;
    order_priority::create_request(conn, v.company_id, id, v.contact_id, priority, message).await
}
