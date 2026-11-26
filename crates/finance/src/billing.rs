//! Outbound invoices and credit notes. A posted document owns its commercial and party snapshots.

use std::collections::{HashMap, HashSet};

use chrono::{DateTime, Datelike, Days, NaiveDate, Utc};
use rust_decimal::{Decimal, RoundingStrategy};
use serde::{Deserialize, Serialize};
use sqlx::{types::Json, FromRow, PgConnection, PgPool, QueryBuilder};
use tradocraft_core::{
    audit,
    auth::{CurrentUser, Permission},
    new_id, numbering,
    vat::vat_exempt_for_regime,
    AppError, AppResult,
};
use utoipa::ToSchema;
use uuid::Uuid;

use crate::customer_rebates::{self, RebateProgress};

#[derive(Debug, Clone, Serialize, Deserialize, FromRow, ToSchema)]
pub struct BillingParty {
    pub name: String,
    pub street: String,
    pub postal_code: String,
    pub city: String,
    pub country_code: String,
    pub vat_number: Option<String>,
}

#[derive(Debug, Serialize, FromRow, ToSchema)]
pub struct BillingSummary {
    pub id: Uuid,
    pub customer_id: Uuid,
    pub customer_name: String,
    pub number: Option<String>,
    pub kind: String,
    pub status: String,
    pub currency: String,
    pub document_date: NaiveDate,
    pub due_date: Option<NaiveDate>,
    pub delivery_note_id: Option<Uuid>,
    pub source_invoice_id: Option<Uuid>,
    pub source_invoice_number: Option<String>,
    pub reason: String,
    pub is_legacy: bool,
    pub evidence_reference: Option<String>,
    #[schema(value_type = String)]
    pub net_total: Decimal,
    #[schema(value_type = String)]
    pub vat_total: Decimal,
    #[schema(value_type = String)]
    pub gross_total: Decimal,
    pub posted_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Serialize, FromRow, ToSchema)]
pub struct BillingLine {
    pub id: Uuid,
    pub position: i32,
    pub product_code: String,
    pub description: String,
    pub unit: String,
    #[schema(value_type = String)]
    pub quantity: Decimal,
    #[schema(value_type = String)]
    pub net_unit_price: Decimal,
    #[schema(value_type = String)]
    pub net_total: Decimal,
    #[schema(value_type = String)]
    pub vat_rate: Decimal,
    #[schema(value_type = String)]
    pub vat_total: Decimal,
    #[schema(value_type = String)]
    pub gross_total: Decimal,
    pub included_in_turnover: Option<bool>,
    pub delivery_line_id: Option<Uuid>,
    pub source_invoice_line_id: Option<Uuid>,
    #[schema(value_type = Option<String>)]
    pub creditable_quantity: Option<Decimal>,
    #[schema(value_type = Option<String>)]
    pub creditable_net_total: Option<Decimal>,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct BillingDocument {
    pub document: BillingSummary,
    pub lines: Vec<BillingLine>,
    pub rebate_progress: Option<RebateProgress>,
    pub language: String,
    pub vat_regime: String,
    pub seller: BillingParty,
    pub customer: BillingParty,
}

#[derive(Debug, Serialize, Deserialize, ToSchema)]
pub struct InvoiceDraftInput {
    pub delivery_note_id: Uuid,
    #[serde(deserialize_with = "tradocraft_core::serde_util::date")]
    pub document_date: NaiveDate,
    pub lines: Vec<InvoiceDraftLineInput>,
    pub request_id: Option<Uuid>,
}

#[derive(Debug, Serialize, Deserialize, ToSchema)]
pub struct InvoiceDraftLineInput {
    pub delivery_line_id: Uuid,
    /// Quantity in the stock unit printed on the delivery note.
    #[schema(value_type = String)]
    pub quantity: Decimal,
}

#[derive(Debug, Serialize, Deserialize, ToSchema)]
pub struct CreditDraftInput {
    pub invoice_id: Uuid,
    #[serde(deserialize_with = "tradocraft_core::serde_util::date")]
    pub document_date: NaiveDate,
    pub reason: String,
    pub lines: Vec<CreditDraftLineInput>,
    pub request_id: Option<Uuid>,
}

#[derive(Debug, Serialize, Deserialize, ToSchema)]
pub struct CreditDraftLineInput {
    pub invoice_line_id: Uuid,
    /// Quantity in the original invoice line's unit.
    #[schema(value_type = String)]
    pub quantity: Decimal,
    /// Optional refund below the line's remaining value, excluding VAT.
    #[schema(value_type = Option<String>)]
    pub net_total: Option<Decimal>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct LegacyInvoiceInput {
    pub customer_id: Uuid,
    pub number: String,
    #[serde(deserialize_with = "tradocraft_core::serde_util::date")]
    pub document_date: NaiveDate,
    pub currency: String,
    pub vat_regime: String,
    /// Reference to the external evidence reviewed by the person registering the invoice.
    pub evidence_reference: String,
    pub lines: Vec<LegacyInvoiceLineInput>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct LegacyInvoiceLineInput {
    pub product_code: String,
    pub description: String,
    pub unit: String,
    #[schema(value_type = String)]
    pub quantity: Decimal,
    #[schema(value_type = String)]
    pub net_total: Decimal,
    #[schema(value_type = String)]
    pub vat_total: Decimal,
    #[schema(value_type = String)]
    pub vat_rate: Decimal,
    pub included_in_turnover: bool,
}

#[derive(Debug, Default, Deserialize)]
pub struct BillingFilter {
    pub kind: Option<String>,
    pub status: Option<String>,
    pub customer_id: Option<Uuid>,
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}

#[derive(FromRow)]
struct Header {
    #[sqlx(flatten)]
    document: BillingSummary,
    language: String,
    vat_regime: String,
    seller: Json<BillingParty>,
    customer: Json<BillingParty>,
    rebate_progress: Option<Json<RebateProgress>>,
}

#[derive(FromRow)]
struct InvoiceContext {
    customer_id: Uuid,
    language: String,
    currency: String,
    vat_regime: String,
    customer: Json<BillingParty>,
    payment_terms_days: i32,
    shipped_date: NaiveDate,
}

#[derive(FromRow)]
struct DeliveredLine {
    order_line_id: Uuid,
    product_id: Uuid,
    stock_unit: String,
    stock_quantity: Decimal,
    product_code: String,
    description: String,
    unit: String,
    order_quantity: Decimal,
    net_unit_price: Decimal,
    line_total: Decimal,
    vat_rate: Decimal,
    included_in_turnover: Option<bool>,
}

struct LineDraft {
    product_id: Option<Uuid>,
    product_code: String,
    description: String,
    unit: String,
    quantity: Decimal,
    stock_quantity: Option<Decimal>,
    net_unit_price: Decimal,
    net_total: Decimal,
    vat_rate: Decimal,
    vat_total: Decimal,
    included_in_turnover: Option<bool>,
    auto_amounts: bool,
    delivery_line_id: Option<Uuid>,
    source_invoice_line_id: Option<Uuid>,
}

const FROM_DOCUMENTS: &str = " FROM finance.customer_documents WHERE company_id = ";
const DOC_FIELDS: &str =
    "id, customer_id, customer_name, number, kind, status, currency::text AS currency,
    document_date, due_date, delivery_note_id, source_invoice_id, source_invoice_number,
    reason, is_legacy, evidence_reference, net_total, vat_total, gross_total, posted_at";

fn validation(message: impl Into<String>) -> AppError {
    AppError::Validation(message.into())
}

fn money(value: Decimal) -> Decimal {
    value.round_dp_with_strategy(2, RoundingStrategy::MidpointAwayFromZero)
}

fn validate_date(date: NaiveDate) -> AppResult<()> {
    if date > Utc::now().date_naive() || date.year() < 1900 {
        return Err(validation("document date must be between 1900 and today"));
    }
    Ok(())
}

fn text(value: &str, name: &str, max_chars: usize) -> AppResult<String> {
    let value = value.trim();
    if value.is_empty() || value.chars().count() > max_chars {
        return Err(validation(format!(
            "{name} must have 1 to {max_chars} characters"
        )));
    }
    Ok(value.to_owned())
}

fn validate_quantity(quantity: Decimal, decimals: u32) -> AppResult<()> {
    if quantity <= Decimal::ZERO || quantity.round_dp(decimals) != quantity {
        return Err(validation(format!(
            "quantity must be positive with at most {decimals} decimals"
        )));
    }
    if quantity >= Decimal::from(100_000_000_000_000_u64) {
        return Err(validation("quantity is too large"));
    }
    Ok(())
}

fn validate_money(value: Decimal) -> AppResult<()> {
    if value < Decimal::ZERO
        || value >= Decimal::from(10_000_000_000_000_000_u64)
        || money(value) != value
    {
        return Err(validation(
            "amount must be nonnegative with at most 2 decimals and fit on the invoice",
        ));
    }
    Ok(())
}

fn validate_lines(ids: impl IntoIterator<Item = Uuid>, len: usize) -> AppResult<()> {
    if !(1..=500).contains(&len) {
        return Err(validation("choose between 1 and 500 document lines"));
    }
    let unique: HashSet<_> = ids.into_iter().collect();
    if unique.len() != len {
        return Err(validation(
            "each source line can occur only once on this document",
        ));
    }
    Ok(())
}

pub async fn list(
    pool: &PgPool,
    user: &CurrentUser,
    filter: BillingFilter,
) -> AppResult<Vec<BillingSummary>> {
    user.require(Permission::CustomerBillingRead)?;
    let mut query = QueryBuilder::new("SELECT ");
    query
        .push(DOC_FIELDS)
        .push(FROM_DOCUMENTS)
        .push_bind(user.company_id);
    if let Some(kind) = filter.kind {
        if !matches!(kind.as_str(), "invoice" | "credit_note") {
            return Err(validation("unknown document kind"));
        }
        query.push(" AND kind = ").push_bind(kind);
    }
    if let Some(status) = filter.status {
        if !matches!(status.as_str(), "draft" | "posted") {
            return Err(validation("unknown document status"));
        }
        query.push(" AND status = ").push_bind(status);
    }
    if let Some(customer_id) = filter.customer_id {
        query.push(" AND customer_id = ").push_bind(customer_id);
    }
    query
        .push(" ORDER BY document_date DESC, id DESC LIMIT ")
        .push_bind(filter.limit.unwrap_or(100).clamp(1, 250))
        .push(" OFFSET ")
        .push_bind(filter.offset.unwrap_or(0).max(0));
    Ok(query.build_query_as().fetch_all(pool).await?)
}

pub async fn get(pool: &PgPool, user: &CurrentUser, id: Uuid) -> AppResult<BillingDocument> {
    user.require(Permission::CustomerBillingRead)?;
    load(&mut *pool.acquire().await?, user.company_id, id).await
}

async fn header(
    conn: &mut PgConnection,
    company_id: Uuid,
    id: Uuid,
    lock: bool,
) -> AppResult<Header> {
    let query: &'static str = if lock {
        "SELECT id, customer_id, customer_name, number, kind, status, currency::text AS currency,
                document_date, due_date, delivery_note_id, source_invoice_id, source_invoice_number,
                reason, is_legacy, evidence_reference, net_total, vat_total, gross_total, posted_at,
                language, vat_regime, seller, customer, rebate_progress
         FROM finance.customer_documents WHERE company_id = $1 AND id = $2 FOR UPDATE"
    } else {
        "SELECT id, customer_id, customer_name, number, kind, status, currency::text AS currency,
                document_date, due_date, delivery_note_id, source_invoice_id, source_invoice_number,
                reason, is_legacy, evidence_reference, net_total, vat_total, gross_total, posted_at,
                language, vat_regime, seller, customer, rebate_progress
         FROM finance.customer_documents WHERE company_id = $1 AND id = $2"
    };
    sqlx::query_as(query)
        .bind(company_id)
        .bind(id)
        .fetch_optional(conn)
        .await?
        .ok_or(AppError::NotFound("customer billing document"))
}

async fn load(conn: &mut PgConnection, company_id: Uuid, id: Uuid) -> AppResult<BillingDocument> {
    let row = header(conn, company_id, id, false).await?;
    let lines = sqlx::query_as(
        "SELECT l.id, l.position, l.product_code, l.description, l.unit, l.quantity, l.net_unit_price,
                l.net_total, l.vat_rate, l.vat_total, l.gross_total, l.included_in_turnover,
                l.delivery_line_id, l.source_invoice_line_id,
                CASE WHEN $2 THEN l.quantity - COALESCE(used.quantity, 0) END AS creditable_quantity,
                CASE WHEN $2 THEN l.net_total - COALESCE(used.net_total, 0) END AS creditable_net_total
         FROM finance.customer_document_lines l
         LEFT JOIN LATERAL (
             SELECT sum(c.quantity) AS quantity, sum(c.net_total) AS net_total
             FROM finance.customer_document_lines c
             JOIN finance.customer_documents d ON d.id = c.document_id
             WHERE $2 AND c.source_invoice_line_id = l.id AND d.status = 'posted'
         ) used ON true
         WHERE l.document_id = $1 ORDER BY l.position",
    )
    .bind(id)
    .bind(row.document.kind == "invoice" && row.document.status == "posted")
    .fetch_all(conn)
    .await?;
    Ok(BillingDocument {
        document: row.document,
        lines,
        rebate_progress: row.rebate_progress.map(|value| value.0),
        language: row.language,
        vat_regime: row.vat_regime,
        seller: row.seller.0,
        customer: row.customer.0,
    })
}

async fn seller(conn: &mut PgConnection, company_id: Uuid) -> AppResult<BillingParty> {
    Ok(sqlx::query_as(
        "SELECT COALESCE(NULLIF(btrim(legal_name), ''), name) AS name,
                street, postal_code, city, country_code::text AS country_code, vat_number
         FROM core.companies WHERE id = $1",
    )
    .bind(company_id)
    .fetch_one(conn)
    .await?)
}

fn request_payload<T: Serialize>(
    request_id: Option<Uuid>,
    input: &T,
) -> AppResult<Option<serde_json::Value>> {
    request_id
        .map(|_| serde_json::to_value(input).map_err(|error| AppError::Internal(error.into())))
        .transpose()
}

async fn retry(
    conn: &mut PgConnection,
    company_id: Uuid,
    request_id: Option<Uuid>,
    request_payload: Option<&serde_json::Value>,
    kind: &str,
) -> AppResult<Option<BillingDocument>> {
    let Some(request_id) = request_id else {
        return Ok(None);
    };
    // A duplicated HTTP request may arrive while the first request is still writing lines.
    sqlx::query("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))")
        .bind(format!(
            "customer-billing-request:{company_id}:{request_id}"
        ))
        .execute(&mut *conn)
        .await?;
    let existing: Option<(Uuid, String, serde_json::Value)> = sqlx::query_as(
        "SELECT id, kind, request_payload FROM finance.customer_documents
         WHERE company_id = $1 AND request_id = $2",
    )
    .bind(company_id)
    .bind(request_id)
    .fetch_optional(&mut *conn)
    .await?;
    match existing {
        None => Ok(None),
        Some((id, existing_kind, existing_payload))
            if existing_kind == kind && request_payload == Some(&existing_payload) =>
        {
            Ok(Some(load(conn, company_id, id).await?))
        }
        Some(_) => Err(AppError::Conflict(
            "request ID is already used for another billing request".into(),
        )),
    }
}

async fn write_lines(
    conn: &mut PgConnection,
    document_id: Uuid,
    lines: Vec<LineDraft>,
) -> AppResult<()> {
    let mut net = Decimal::ZERO;
    let mut vat = Decimal::ZERO;
    for (index, line) in lines.into_iter().enumerate() {
        let gross = line.net_total + line.vat_total;
        validate_money(line.net_total)?;
        validate_money(line.vat_total)?;
        validate_money(gross)?;
        if line.net_unit_price < Decimal::ZERO
            || line.net_unit_price >= Decimal::from(100_000_000_000_000_u64)
        {
            return Err(validation("unit price is outside the supported range"));
        }
        sqlx::query(
            "INSERT INTO finance.customer_document_lines
                 (id, document_id, position, product_id, product_code, description, unit, quantity,
                  stock_quantity, net_unit_price, net_total, vat_rate, vat_total, gross_total,
                  included_in_turnover, auto_amounts, delivery_line_id, source_invoice_line_id)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18)",
        )
        .bind(new_id())
        .bind(document_id)
        .bind((index + 1) as i32)
        .bind(line.product_id)
        .bind(line.product_code)
        .bind(line.description)
        .bind(line.unit)
        .bind(line.quantity)
        .bind(line.stock_quantity)
        .bind(line.net_unit_price)
        .bind(line.net_total)
        .bind(line.vat_rate)
        .bind(line.vat_total)
        .bind(gross)
        .bind(line.included_in_turnover)
        .bind(line.auto_amounts)
        .bind(line.delivery_line_id)
        .bind(line.source_invoice_line_id)
        .execute(&mut *conn)
        .await?;
        net += line.net_total;
        vat += line.vat_total;
    }
    validate_money(net + vat)?;
    sqlx::query(
        "UPDATE finance.customer_documents SET net_total = $2, vat_total = $3, gross_total = $2 + $3
         WHERE id = $1",
    )
    .bind(document_id)
    .bind(net)
    .bind(vat)
    .execute(conn)
    .await?;
    Ok(())
}

async fn invoice_context(
    conn: &mut PgConnection,
    company_id: Uuid,
    delivery_note_id: Uuid,
) -> AppResult<InvoiceContext> {
    sqlx::query_as(
        "SELECT n.customer_id, q.customer_language::text AS language, o.currency::text AS currency,
                o.vat_regime,
                jsonb_build_object('name', o.customer_name, 'street', q.customer_street,
                    'postal_code', q.customer_postal_code, 'city', q.customer_city,
                    'country_code', q.customer_country_code, 'vat_number', q.customer_vat_number) AS customer,
                COALESCE(t.payment_terms_days, 30) AS payment_terms_days,
                (n.shipped_at AT TIME ZONE 'UTC')::date AS shipped_date
         FROM delivery.delivery_notes n
         JOIN sales.orders o ON o.id = n.order_id
         JOIN sales.quotations q ON q.id = o.quotation_id
         LEFT JOIN crm.customer_terms t ON t.customer_id = n.customer_id AND t.company_id = n.company_id
         WHERE n.id = $1 AND n.company_id = $2 AND n.status = 'shipped'
         FOR UPDATE OF n, o",
    )
    .bind(delivery_note_id)
    .bind(company_id)
    .fetch_optional(conn)
    .await?
    .ok_or(AppError::NotFound("shipped delivery"))
}

async fn billed_stock(conn: &mut PgConnection, delivery_line_id: Uuid) -> AppResult<Decimal> {
    Ok(sqlx::query_scalar(
        "SELECT COALESCE(sum(l.stock_quantity), 0)
         FROM finance.customer_document_lines l
         JOIN finance.customer_documents d ON d.id = l.document_id
         WHERE l.delivery_line_id = $1 AND d.status = 'posted'",
    )
    .bind(delivery_line_id)
    .fetch_one(conn)
    .await?)
}

async fn draft_invoice_line(
    conn: &mut PgConnection,
    delivery_note_id: Uuid,
    input: InvoiceDraftLineInput,
    pending_by_order_line: &mut HashMap<Uuid, Decimal>,
) -> AppResult<LineDraft> {
    validate_quantity(input.quantity, 4)?;
    let source: DeliveredLine = sqlx::query_as(
        "SELECT d.order_line_id, d.product_id, d.unit AS stock_unit, d.quantity AS stock_quantity, o.product_code,
                o.description, o.unit, o.quantity AS order_quantity, o.net_unit_price, o.line_total, o.vat_rate,
                p.included_in_turnover
         FROM delivery.delivery_note_lines d
         JOIN sales.order_lines o ON o.id = d.order_line_id
         JOIN products.products p ON p.id = d.product_id
         WHERE d.id = $1 AND d.delivery_note_id = $2",
    )
    .bind(input.delivery_line_id)
    .bind(delivery_note_id)
    .fetch_optional(&mut *conn)
    .await?
    .ok_or(AppError::NotFound("shipped delivery line"))?;
    let billed = billed_stock(conn, input.delivery_line_id).await?;
    if billed + input.quantity > source.stock_quantity {
        return Err(AppError::Conflict(
            "quantity exceeds the remaining shipped quantity".into(),
        ));
    }

    let product = tradocraft_products::get_product(&mut *conn, source.product_id).await?;
    if product.unit != source.stock_unit {
        return Err(AppError::Conflict(
            "the product stock unit changed after shipment".into(),
        ));
    }
    let ordered_stock = tradocraft_inventory::ledger::to_stock_quantity(
        conn,
        &product,
        source.order_quantity,
        Some(&source.unit),
    )
    .await?
    .0;
    if ordered_stock < source.stock_quantity || ordered_stock <= Decimal::ZERO {
        return Err(AppError::Conflict(
            "the order unit conversion no longer matches the shipped quantity".into(),
        ));
    }
    let (posted_stock, posted_quantity, posted_net): (Decimal, Decimal, Decimal) = sqlx::query_as(
        "SELECT COALESCE(sum(l.stock_quantity), 0), COALESCE(sum(l.quantity), 0), COALESCE(sum(l.net_total), 0)
         FROM finance.customer_document_lines l
         JOIN finance.customer_documents d ON d.id = l.document_id
         JOIN delivery.delivery_note_lines p ON p.id = l.delivery_line_id
         WHERE p.order_line_id = $1 AND d.status = 'posted'",
    )
    .bind(source.order_line_id)
    .fetch_one(&mut *conn)
    .await?;
    let pending = pending_by_order_line
        .entry(source.order_line_id)
        .or_default();
    let before = posted_stock + *pending;
    let after = before + input.quantity;
    if after > ordered_stock {
        return Err(AppError::Conflict(
            "the order unit conversion no longer covers the invoiced quantity".into(),
        ));
    }
    *pending += input.quantity;
    // Keep the frozen line totals exact when picks, deliveries, or invoices split an order line.
    let quantity_at =
        |stock: Decimal| (source.order_quantity * (stock / ordered_stock)).round_dp(8);
    let total_at = |stock: Decimal| money(source.line_total * (stock / ordered_stock));
    if posted_quantity != quantity_at(posted_stock) || posted_net != total_at(posted_stock) {
        return Err(AppError::Conflict(
            "the order conversion conflicts with quantities or amounts already posted".into(),
        ));
    }
    let quantity = quantity_at(after) - quantity_at(before);
    validate_quantity(quantity, 8)?;
    let net_total = total_at(after) - total_at(before);

    Ok(LineDraft {
        product_id: Some(source.product_id),
        product_code: source.product_code,
        description: source.description,
        unit: source.unit,
        quantity,
        stock_quantity: Some(input.quantity),
        net_unit_price: source.net_unit_price,
        net_total,
        vat_rate: source.vat_rate,
        vat_total: Decimal::ZERO,
        included_in_turnover: source.included_in_turnover,
        auto_amounts: false,
        delivery_line_id: Some(input.delivery_line_id),
        source_invoice_line_id: None,
    })
}

pub async fn create_invoice(
    pool: &PgPool,
    user: &CurrentUser,
    input: InvoiceDraftInput,
) -> AppResult<BillingDocument> {
    user.require(Permission::CustomerBillingWrite)?;
    validate_date(input.document_date)?;
    validate_lines(
        input.lines.iter().map(|line| line.delivery_line_id),
        input.lines.len(),
    )?;
    let request_payload = request_payload(input.request_id, &input)?;
    let mut tx = pool.begin().await?;
    if let Some(existing) = retry(
        &mut tx,
        user.company_id,
        input.request_id,
        request_payload.as_ref(),
        "invoice",
    )
    .await?
    {
        tx.commit().await?;
        return Ok(existing);
    }
    let context = invoice_context(&mut tx, user.company_id, input.delivery_note_id).await?;
    if input.document_date < context.shipped_date {
        return Err(validation("invoice date cannot precede shipment"));
    }
    let due_date = input
        .document_date
        .checked_add_days(Days::new(context.payment_terms_days as u64))
        .ok_or_else(|| validation("payment terms produce an invalid due date"))?;
    let seller = seller(&mut tx, user.company_id).await?;
    let mut lines = Vec::new();
    let mut pending_by_order_line = HashMap::new();
    for line in input.lines {
        lines.push(
            draft_invoice_line(
                &mut tx,
                input.delivery_note_id,
                line,
                &mut pending_by_order_line,
            )
            .await?,
        );
    }

    if !vat_exempt_for_regime(&context.vat_regime) {
        // Round VAT per rate for this invoice. Allocate the rounded group amount to its lines so
        // partial credits can account for every cent of the original tax.
        let mut base_by_rate: HashMap<Decimal, Decimal> = HashMap::new();
        for line in &mut lines {
            let base = base_by_rate.entry(line.vat_rate).or_default();
            let tax = |amount| money(amount * line.vat_rate / Decimal::ONE_HUNDRED);
            let previous = tax(*base);
            *base += line.net_total;
            line.vat_total = tax(*base) - previous;
        }
    }

    let id = new_id();
    sqlx::query(
        "INSERT INTO finance.customer_documents
             (id, company_id, customer_id, customer_name, kind, status, document_date, due_date,
              currency, language, vat_regime, seller, customer, delivery_note_id, request_id, request_payload, created_by)
         VALUES ($1, $2, $3, $4, 'invoice', 'draft', $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15)",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(context.customer_id)
    .bind(&context.customer.name)
    .bind(input.document_date)
    .bind(due_date)
    .bind(context.currency)
    .bind(context.language)
    .bind(context.vat_regime)
    .bind(Json(seller))
    .bind(&context.customer)
    .bind(input.delivery_note_id)
    .bind(input.request_id)
    .bind(request_payload)
    .bind(user.user_id)
    .execute(&mut *tx)
    .await?;
    write_lines(&mut tx, id, lines).await?;
    audit::record(
        &mut tx,
        user,
        "customer_document",
        id,
        "created",
        serde_json::json!({
            "kind": "invoice", "delivery_note_id": input.delivery_note_id
        }),
    )
    .await?;
    let created = load(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok(created)
}

#[derive(FromRow)]
struct CreditSource {
    product_id: Option<Uuid>,
    product_code: String,
    description: String,
    unit: String,
    quantity: Decimal,
    net_total: Decimal,
    vat_rate: Decimal,
    vat_total: Decimal,
    included_in_turnover: Option<bool>,
}

async fn credit_source(
    conn: &mut PgConnection,
    invoice_id: Uuid,
    line_id: Uuid,
) -> AppResult<CreditSource> {
    sqlx::query_as(
        "SELECT product_id, product_code, description, unit, quantity, net_total,
                vat_rate, vat_total, included_in_turnover
         FROM finance.customer_document_lines WHERE id = $1 AND document_id = $2",
    )
    .bind(line_id)
    .bind(invoice_id)
    .fetch_optional(conn)
    .await?
    .ok_or(AppError::NotFound("original invoice line"))
}

async fn credited(
    conn: &mut PgConnection,
    line_id: Uuid,
) -> AppResult<(Decimal, Decimal, Decimal)> {
    Ok(sqlx::query_as(
        "SELECT COALESCE(sum(l.quantity), 0), COALESCE(sum(l.net_total), 0), COALESCE(sum(l.vat_total), 0)
         FROM finance.customer_document_lines l
         JOIN finance.customer_documents d ON d.id = l.document_id
         WHERE l.source_invoice_line_id = $1 AND d.status = 'posted'",
    )
    .bind(line_id)
    .fetch_one(conn)
    .await?)
}

fn credit_amounts(
    original: &CreditSource,
    quantity: Decimal,
    explicit_net: Option<Decimal>,
    quantity_credited: Decimal,
    net_credited: Decimal,
    vat_credited: Decimal,
) -> AppResult<(Decimal, Decimal)> {
    let net_remaining = original.net_total - net_credited;
    let suggested_net = if quantity_credited + quantity == original.quantity {
        net_remaining
    } else {
        money(original.net_total * (quantity / original.quantity)).min(net_remaining)
    };
    let net_total = explicit_net.unwrap_or(suggested_net);
    if net_total > net_remaining {
        return Err(AppError::Conflict(
            "net amount exceeds what remains creditable on this invoice line".into(),
        ));
    }
    let vat_remaining = original.vat_total - vat_credited;
    let vat_total = if net_total == net_remaining {
        vat_remaining
    } else if original.net_total.is_zero() {
        Decimal::ZERO
    } else {
        money(original.vat_total * (net_total / original.net_total)).min(vat_remaining)
    };
    Ok((net_total, vat_total))
}

async fn draft_credit_line(
    conn: &mut PgConnection,
    invoice_id: Uuid,
    input: CreditDraftLineInput,
) -> AppResult<LineDraft> {
    validate_quantity(input.quantity, 8)?;
    if let Some(net) = input.net_total {
        validate_money(net)?;
    }
    let original = credit_source(conn, invoice_id, input.invoice_line_id).await?;
    let (quantity_credited, net_credited, vat_credited) =
        credited(conn, input.invoice_line_id).await?;
    if quantity_credited + input.quantity > original.quantity {
        return Err(AppError::Conflict(
            "quantity exceeds what remains creditable on this invoice line".into(),
        ));
    }
    let (net_total, vat_total) = credit_amounts(
        &original,
        input.quantity,
        input.net_total,
        quantity_credited,
        net_credited,
        vat_credited,
    )?;
    Ok(LineDraft {
        product_id: original.product_id,
        product_code: original.product_code,
        description: original.description,
        unit: original.unit,
        quantity: input.quantity,
        stock_quantity: None,
        net_unit_price: net_total
            .checked_div(input.quantity)
            .ok_or_else(|| validation("credited unit price is outside the supported range"))?
            .round_dp(4),
        net_total,
        vat_rate: original.vat_rate,
        vat_total,
        included_in_turnover: original.included_in_turnover,
        auto_amounts: input.net_total.is_none(),
        delivery_line_id: None,
        source_invoice_line_id: Some(input.invoice_line_id),
    })
}

pub async fn create_credit(
    pool: &PgPool,
    user: &CurrentUser,
    input: CreditDraftInput,
) -> AppResult<BillingDocument> {
    user.require(Permission::CustomerBillingWrite)?;
    validate_date(input.document_date)?;
    let reason = text(&input.reason, "credit reason", 1000)?;
    validate_lines(
        input.lines.iter().map(|line| line.invoice_line_id),
        input.lines.len(),
    )?;
    let request_payload = request_payload(input.request_id, &input)?;
    let mut tx = pool.begin().await?;
    if let Some(existing) = retry(
        &mut tx,
        user.company_id,
        input.request_id,
        request_payload.as_ref(),
        "credit_note",
    )
    .await?
    {
        tx.commit().await?;
        return Ok(existing);
    }
    let origin = header(&mut tx, user.company_id, input.invoice_id, true).await?;
    if origin.document.kind != "invoice" || origin.document.status != "posted" {
        return Err(validation("credit notes require a posted original invoice"));
    }
    if input.document_date < origin.document.document_date {
        return Err(validation(
            "credit date cannot precede the original invoice",
        ));
    }
    let mut lines = Vec::new();
    for line in input.lines {
        lines.push(draft_credit_line(&mut tx, input.invoice_id, line).await?);
    }
    let id = new_id();
    sqlx::query(
        "INSERT INTO finance.customer_documents
             (id, company_id, customer_id, customer_name, kind, status, document_date, currency, language,
              vat_regime, seller, customer, source_invoice_id, source_invoice_number, reason, request_id, request_payload, created_by)
         SELECT $1, company_id, customer_id, customer_name, 'credit_note', 'draft', $2, currency, language,
                vat_regime, seller, customer, id, number, $3, $4, $5, $6
         FROM finance.customer_documents WHERE id = $7 AND company_id = $8",
    )
    .bind(id)
    .bind(input.document_date)
    .bind(reason)
    .bind(input.request_id)
    .bind(request_payload)
    .bind(user.user_id)
    .bind(input.invoice_id)
    .bind(user.company_id)
    .execute(&mut *tx)
    .await?;
    write_lines(&mut tx, id, lines).await?;
    audit::record(
        &mut tx,
        user,
        "customer_document",
        id,
        "created",
        serde_json::json!({
            "kind": "credit_note", "source_invoice_id": input.invoice_id
        }),
    )
    .await?;
    let created = load(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok(created)
}

#[derive(FromRow)]
struct PostingLine {
    id: Uuid,
    product_id: Option<Uuid>,
    quantity: Decimal,
    stock_quantity: Option<Decimal>,
    net_total: Decimal,
    vat_total: Decimal,
    included_in_turnover: Option<bool>,
    auto_amounts: bool,
    delivery_line_id: Option<Uuid>,
    source_invoice_line_id: Option<Uuid>,
}

/// The delivery lock serializes all posts allocating its picks. Check posted usage after taking it.
async fn check_invoice_post(
    conn: &mut PgConnection,
    company_id: Uuid,
    note_id: Uuid,
    lines: &[PostingLine],
) -> AppResult<()> {
    invoice_context(conn, company_id, note_id).await?;
    let mut pending_by_order_line = HashMap::new();
    let mut product_ids: Vec<_> = lines.iter().filter_map(|line| line.product_id).collect();
    product_ids.sort_unstable();
    product_ids.dedup();
    // Capturing the product setting and posting its line must be atomic with a change to the setting.
    let settings: Vec<(Uuid, Option<bool>)> = sqlx::query_as(
        "SELECT id, included_in_turnover FROM products.products WHERE id = ANY($1) ORDER BY id FOR SHARE",
    )
    .bind(&product_ids)
    .fetch_all(&mut *conn)
    .await?;
    for line in lines {
        let delivery_line_id = line
            .delivery_line_id
            .ok_or_else(|| validation("invoice line has no shipment"))?;
        let stock_quantity = line
            .stock_quantity
            .ok_or_else(|| validation("invoice line has no shipment quantity"))?;
        let current = draft_invoice_line(
            conn,
            note_id,
            InvoiceDraftLineInput {
                delivery_line_id,
                quantity: stock_quantity,
            },
            &mut pending_by_order_line,
        )
        .await?;
        if current.quantity != line.quantity || current.net_total != line.net_total {
            return Err(AppError::ConflictCode(
                "invoice_draft_stale",
                "another invoice or a unit conversion change affected these amounts; recreate the draft".into(),
            ));
        }
        let flag = settings
            .iter()
            .find(|(id, _)| Some(*id) == line.product_id)
            .and_then(|(_, value)| *value)
            .ok_or_else(|| {
                AppError::ConflictCode(
                    "turnover_eligibility_unknown",
                    "set turnover eligibility on each invoiced product before posting".into(),
                )
            })?;
        sqlx::query(
            "UPDATE finance.customer_document_lines SET included_in_turnover = $2 WHERE id = $1",
        )
        .bind(line.id)
        .bind(flag)
        .execute(&mut *conn)
        .await?;
    }
    Ok(())
}

/// The original invoice lock serializes credits from separate draft documents.
async fn check_credit_post(
    conn: &mut PgConnection,
    company_id: Uuid,
    invoice_id: Uuid,
    lines: &[PostingLine],
) -> AppResult<()> {
    let source = header(conn, company_id, invoice_id, true).await?;
    if source.document.status != "posted" || source.document.kind != "invoice" {
        return Err(validation("credit notes require a posted original invoice"));
    }
    for line in lines {
        let source_line_id = line
            .source_invoice_line_id
            .ok_or_else(|| validation("credit line has no original invoice line"))?;
        let original = credit_source(conn, invoice_id, source_line_id).await?;
        if original.included_in_turnover.is_none()
            || original.included_in_turnover != line.included_in_turnover
        {
            return Err(AppError::ConflictCode(
                "turnover_eligibility_unknown",
                "the original invoice must have verified turnover eligibility".into(),
            ));
        }
        let (quantity, net, vat) = credited(conn, source_line_id).await?;
        if quantity + line.quantity > original.quantity
            || net + line.net_total > original.net_total
            || vat + line.vat_total > original.vat_total
        {
            return Err(AppError::Conflict(
                "credit exceeds the remaining quantity or amount on its original invoice line"
                    .into(),
            ));
        }
        if line.auto_amounts {
            let (expected_net, expected_vat) =
                credit_amounts(&original, line.quantity, None, quantity, net, vat)?;
            if line.net_total != expected_net || line.vat_total != expected_vat {
                return Err(AppError::ConflictCode(
                    "credit_draft_stale",
                    "another credit note affected the remaining creditable amounts; recreate the draft"
                        .into(),
                ));
            }
        }
    }
    Ok(())
}

async fn check_turnover_period(
    conn: &mut PgConnection,
    company_id: Uuid,
    document: &BillingSummary,
) -> AppResult<()> {
    // Approval and opening-balance edits take the same customer lock as document posting.
    let sealed: bool = sqlx::query_scalar(
        "SELECT EXISTS (
             SELECT 1 FROM finance.customer_document_lines
             WHERE document_id = $3 AND included_in_turnover AND net_total <> 0
         ) AND (
             EXISTS (
                 SELECT 1 FROM finance.customer_rebate_rates
                 WHERE company_id = $1 AND customer_id = $2 AND rate_year = $4 + 1
             ) OR EXISTS (
                 SELECT 1 FROM finance.customer_rebate_openings
                 WHERE company_id = $1 AND customer_id = $2 AND year = $4 AND cutoff >= $5
             )
         )",
    )
    .bind(company_id)
    .bind(document.customer_id)
    .bind(document.id)
    .bind(document.document_date.year())
    .bind(document.document_date)
    .fetch_one(conn)
    .await?;
    if sealed {
        return Err(AppError::ConflictCode(
            "turnover_period_closed",
            "the document date falls in turnover already verified or used to approve a rebate rate"
                .into(),
        ));
    }
    Ok(())
}

pub async fn post(pool: &PgPool, user: &CurrentUser, id: Uuid) -> AppResult<BillingDocument> {
    user.require(Permission::CustomerBillingPost)?;
    let mut tx = pool.begin().await?;
    let draft = header(&mut tx, user.company_id, id, true).await?;
    if draft.document.status == "posted" {
        let posted = load(&mut tx, user.company_id, id).await?;
        tx.commit().await?;
        return Ok(posted);
    }

    let lines: Vec<PostingLine> = sqlx::query_as(
        "SELECT id, product_id, quantity, stock_quantity, net_total, vat_total,
                included_in_turnover, auto_amounts, delivery_line_id, source_invoice_line_id
         FROM finance.customer_document_lines WHERE document_id = $1 ORDER BY position",
    )
    .bind(id)
    .fetch_all(&mut *tx)
    .await?;
    if lines.is_empty() {
        return Err(validation("document has no lines"));
    }
    let sequence_code = if let Some(note_id) = draft.document.delivery_note_id {
        check_invoice_post(&mut tx, user.company_id, note_id, &lines).await?;
        "INV"
    } else {
        let invoice_id = draft
            .document
            .source_invoice_id
            .ok_or_else(|| validation("credit note has no original invoice"))?;
        check_credit_post(&mut tx, user.company_id, invoice_id, &lines).await?;
        "CN"
    };
    customer_rebates::lock_customer(&mut tx, user.company_id, draft.document.customer_id).await?;
    check_turnover_period(&mut tx, user.company_id, &draft.document).await?;
    let year = draft.document.document_date.year();
    let number = loop {
        let seq = numbering::next_number(&mut tx, user.company_id, sequence_code, year).await?;
        let candidate = format!("{sequence_code}-{year}-{seq:06}");
        let used: bool = sqlx::query_scalar(
            "SELECT EXISTS(SELECT 1 FROM finance.customer_documents WHERE company_id = $1 AND number = $2)",
        )
        .bind(user.company_id)
        .bind(&candidate)
        .fetch_one(&mut *tx)
        .await?;
        if !used {
            break candidate;
        }
    };
    sqlx::query(
        "UPDATE finance.customer_documents SET status = 'posted', number = $2, posted_at = now(), posted_by = $3
         WHERE id = $1",
    )
    .bind(id)
    .bind(&number)
    .bind(user.user_id)
    .execute(&mut *tx)
    .await?;
    if sequence_code == "INV" {
        let progress = customer_rebates::invoice_progress(
            &mut tx,
            user.company_id,
            draft.document.customer_id,
            id,
            draft.document.document_date,
            &draft.language,
        )
        .await?;
        if let Some(progress) = progress {
            sqlx::query("UPDATE finance.customer_documents SET rebate_progress = $2 WHERE id = $1")
                .bind(id)
                .bind(Json(progress))
                .execute(&mut *tx)
                .await?;
        }
    }
    audit::record(
        &mut tx,
        user,
        "customer_document",
        id,
        "posted",
        serde_json::json!({
            "kind": draft.document.kind, "number": number
        }),
    )
    .await?;
    let posted = load(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok(posted)
}

pub async fn discard(pool: &PgPool, user: &CurrentUser, id: Uuid) -> AppResult<()> {
    user.require(Permission::CustomerBillingWrite)?;
    let mut tx = pool.begin().await?;
    let row = header(&mut tx, user.company_id, id, true).await?;
    if row.document.status != "draft" {
        return Err(AppError::Conflict("only a draft can be discarded".into()));
    }
    sqlx::query("DELETE FROM finance.customer_documents WHERE id = $1")
        .bind(id)
        .execute(&mut *tx)
        .await?;
    audit::record(
        &mut tx,
        user,
        "customer_document",
        id,
        "discarded",
        serde_json::json!({
            "kind": row.document.kind
        }),
    )
    .await?;
    tx.commit().await?;
    Ok(())
}

pub async fn register_legacy_invoice(
    pool: &PgPool,
    user: &CurrentUser,
    input: LegacyInvoiceInput,
) -> AppResult<BillingDocument> {
    user.require(Permission::CustomerBillingPost)?;
    validate_date(input.document_date)?;
    if !(1..=500).contains(&input.lines.len()) {
        return Err(validation("register between 1 and 500 invoice lines"));
    }
    let number = text(&input.number, "original invoice number", 100)?;
    let evidence = text(&input.evidence_reference, "evidence reference", 500)?;
    let currency = input.currency.trim().to_ascii_uppercase();
    if currency.len() != 3 || !currency.bytes().all(|byte| byte.is_ascii_uppercase()) {
        return Err(validation("currency must be three letters"));
    }
    if !matches!(
        input.vat_regime.as_str(),
        "domestic" | "domestic_reverse_charge" | "intra_eu" | "outside_eu"
    ) {
        return Err(validation("invalid VAT regime"));
    }
    let mut lines = Vec::new();
    for line in input.lines {
        validate_quantity(line.quantity, 8)?;
        validate_money(line.net_total)?;
        validate_money(line.vat_total)?;
        if line.vat_rate < Decimal::ZERO
            || line.vat_rate > Decimal::ONE_HUNDRED
            || line.vat_rate.round_dp(2) != line.vat_rate
        {
            return Err(validation(
                "VAT rate must be 0 to 100 with at most 2 decimals",
            ));
        }
        if vat_exempt_for_regime(&input.vat_regime) && !line.vat_total.is_zero() {
            return Err(validation("VAT-exempt invoice lines must have zero VAT"));
        }
        let net_unit_price = line.net_total.checked_div(line.quantity).ok_or_else(|| {
            validation("legacy invoice unit price is outside the supported range")
        })?;
        lines.push(LineDraft {
            product_id: None,
            product_code: line.product_code.trim().to_owned(),
            description: text(&line.description, "description", 1000)?,
            unit: text(&line.unit, "unit", 40)?,
            quantity: line.quantity,
            stock_quantity: None,
            net_unit_price: net_unit_price.round_dp(4),
            net_total: line.net_total,
            vat_rate: line.vat_rate,
            vat_total: line.vat_total,
            included_in_turnover: Some(line.included_in_turnover),
            auto_amounts: false,
            delivery_line_id: None,
            source_invoice_line_id: None,
        });
    }
    let mut tx = pool.begin().await?;
    customer_rebates::lock_customer(&mut tx, user.company_id, input.customer_id).await?;
    let cutoff: Option<NaiveDate> = sqlx::query_scalar(
        "SELECT cutoff FROM finance.customer_rebate_openings
         WHERE company_id = $1 AND customer_id = $2 AND year = $3",
    )
    .bind(user.company_id)
    .bind(input.customer_id)
    .bind(input.document_date.year())
    .fetch_optional(&mut *tx)
    .await?;
    if cutoff.is_some_and(|c| input.document_date > c) {
        return Err(AppError::ConflictCode(
            "turnover_period_closed",
            "legacy invoices cannot be dated after the verified opening cutoff for that year"
                .into(),
        ));
    }
    let seller = seller(&mut tx, user.company_id).await?;
    let customer: Option<(String, Json<BillingParty>)> = sqlx::query_as(
        "SELECT language::text, jsonb_build_object('name', name, 'street', street,
                'postal_code', postal_code, 'city', city, 'country_code', country_code, 'vat_number', vat_number)
         FROM crm.customers WHERE id = $1",
    )
    .bind(input.customer_id)
    .fetch_optional(&mut *tx)
    .await?;
    let (language, customer) = customer.ok_or(AppError::NotFound("customer"))?;
    let id = new_id();
    let inserted = sqlx::query(
        "INSERT INTO finance.customer_documents
             (id, company_id, customer_id, customer_name, kind, status, number, document_date, currency,
              language, vat_regime, seller, customer, is_legacy, evidence_reference, created_by, posted_by, posted_at)
         VALUES ($1, $2, $3, $4, 'invoice', 'posted', $5, $6, $7, $8, $9, $10, $11, true, $12, $13, $13, now())
         ON CONFLICT (company_id, number) DO NOTHING",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(input.customer_id)
    .bind(&customer.name)
    .bind(&number)
    .bind(input.document_date)
    .bind(currency)
    .bind(language)
    .bind(input.vat_regime)
    .bind(Json(seller))
    .bind(&customer)
    .bind(&evidence)
    .bind(user.user_id)
    .execute(&mut *tx)
    .await?;
    if inserted.rows_affected() == 0 {
        return Err(AppError::Conflict(
            "invoice number is already registered for this company".into(),
        ));
    }
    write_lines(&mut tx, id, lines).await?;
    audit::record(
        &mut tx,
        user,
        "customer_document",
        id,
        "legacy_registered",
        serde_json::json!({
            "number": number, "evidence_reference": evidence
        }),
    )
    .await?;
    let registered = load(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok(registered)
}
