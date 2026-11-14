//! Supplier invoices: registration, the live three-way match, approval, dispute and payment
//! status (ADR 0046). Purchase order, goods receipt and supplier data are read only through the
//! public `tradocraft_purchasing` functions.

use crate::matching::{self, LineInput, MatchReport, PoFigures};
use crate::settings;
use chrono::{DateTime, Datelike, Duration, NaiveDate, Utc};
use rust_decimal::{Decimal, RoundingStrategy};
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection, QueryBuilder};
use std::collections::HashMap;
use tradocraft_core::{audit, new_id, numbering, today, AppError, AppResult, CurrentUser};
use tradocraft_purchasing::orders::PurchaseOrderDetail;
use tradocraft_purchasing::{orders as po_orders, receipts, suppliers};
use utoipa::ToSchema;
use uuid::Uuid;

/// Invoice statuses.
pub const STATUSES: [&str; 5] = ["draft", "matched", "disputed", "approved", "paid"];

/// A supplier invoice header.
#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct InvoiceSummary {
    /// Invoice id.
    pub id: Uuid,
    /// Owning company.
    pub company_id: Uuid,
    /// Internal document number, e.g. `SI2027-00001`.
    pub number: String,
    /// Supplier (purchasing).
    pub supplier_id: Uuid,
    /// Supplier name, read through purchasing.
    #[sqlx(default)]
    pub supplier_name: String,
    /// The purchase order the invoice is matched against, if any.
    pub purchase_order_id: Option<Uuid>,
    /// Number of that purchase order, read through purchasing.
    #[sqlx(default)]
    pub purchase_order_number: Option<String>,
    /// The supplier's own invoice number; unique per supplier.
    pub invoice_number: String,
    /// Date on the invoice.
    pub invoice_date: NaiveDate,
    /// Payment due date (default: invoice date plus the supplier's payment terms).
    pub due_date: NaiveDate,
    /// Currency; equals the purchase order's currency when there is one.
    pub currency: String,
    /// draft | matched | disputed | approved | paid
    pub status: String,
    /// Sum of the line net amounts.
    #[schema(value_type = String)]
    pub net_total: Decimal,
    /// Sum of the line VAT amounts.
    #[schema(value_type = String)]
    pub vat_total: Decimal,
    /// Net plus VAT.
    #[schema(value_type = String)]
    pub gross_total: Decimal,
    /// Free notes.
    pub notes: String,
    /// Why the invoice was disputed (while disputed).
    pub dispute_reason: String,
    /// Reason given when the invoice was approved against a failed match.
    pub override_reason: String,
    /// Who registered the invoice.
    pub created_by_user_id: Uuid,
    /// Who approved it.
    pub approved_by_user_id: Option<Uuid>,
    /// When it was approved.
    pub approved_at: Option<DateTime<Utc>>,
    /// Payment date, once paid.
    pub paid_at: Option<NaiveDate>,
    /// Bank or payment reference, once paid.
    pub payment_reference: String,
    /// Creation time.
    pub created_at: DateTime<Utc>,
    /// Last change.
    pub updated_at: DateTime<Utc>,
}

/// A supplier invoice line.
#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct InvoiceLine {
    /// Line id.
    pub id: Uuid,
    /// Invoice id.
    pub invoice_id: Uuid,
    /// Position on the invoice, from 1.
    pub line_number: i32,
    /// The purchase order line this line bills; `None` for a free-text line.
    pub purchase_order_line_id: Option<Uuid>,
    /// Product, when known.
    pub product_id: Option<Uuid>,
    /// Description.
    pub description: String,
    /// Invoiced quantity.
    #[schema(value_type = String)]
    pub quantity: Decimal,
    /// Unit price excluding VAT.
    #[schema(value_type = String)]
    pub unit_price: Decimal,
    /// VAT rate in percent.
    #[schema(value_type = String)]
    pub vat_rate: Decimal,
    /// Quantity times price, 2 decimals.
    #[schema(value_type = String)]
    pub line_net: Decimal,
    /// VAT on the net amount, 2 decimals.
    #[schema(value_type = String)]
    pub line_vat: Decimal,
    /// Net plus VAT.
    #[schema(value_type = String)]
    pub line_gross: Decimal,
}

/// An invoice with its lines and the live match report.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct InvoiceDetail {
    /// The header fields.
    #[serde(flatten)]
    pub summary: InvoiceSummary,
    /// The lines in order.
    pub lines: Vec<InvoiceLine>,
    /// The three-way match evaluated now.
    pub match_report: MatchReport,
}

/// A page of invoices.
#[derive(Debug, Serialize, ToSchema)]
pub struct InvoicePage {
    /// The invoices on this page, newest first.
    pub items: Vec<InvoiceSummary>,
    /// Number of invoices matching the filters.
    pub total: i64,
}

/// A line of an invoice being created or replaced.
#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct InvoiceLineInput {
    /// The purchase order line billed; requires the invoice to have a purchase order.
    pub purchase_order_line_id: Option<Uuid>,
    /// Product for a free-text line; taken from the order line otherwise.
    pub product_id: Option<Uuid>,
    /// Description; required for a free-text line, defaults to the product name otherwise.
    pub description: Option<String>,
    /// Invoiced quantity (greater than zero, at most 4 decimals).
    #[schema(value_type = String)]
    pub quantity: Decimal,
    /// Unit price excluding VAT (at most 4 decimals).
    #[schema(value_type = String)]
    pub unit_price: Decimal,
    /// VAT rate in percent, default 0.
    #[schema(value_type = Option<String>)]
    pub vat_rate: Option<Decimal>,
}

/// Payload to register a draft invoice.
#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct NewInvoiceInput {
    /// Supplier; may be left out when a purchase order is given.
    pub supplier_id: Option<Uuid>,
    /// Purchase order to match against. Without `lines` the lines are prefilled from what was
    /// received and not yet invoiced.
    pub purchase_order_id: Option<Uuid>,
    /// The supplier's invoice number.
    pub invoice_number: String,
    /// Date on the invoice.
    #[serde(deserialize_with = "tradocraft_core::serde_util::date")]
    pub invoice_date: NaiveDate,
    /// Due date; default invoice date plus the supplier's payment terms.
    #[serde(default, deserialize_with = "tradocraft_core::serde_util::opt_date")]
    pub due_date: Option<NaiveDate>,
    /// Currency; defaults to the order's (or the supplier's) and must equal the order's.
    pub currency: Option<String>,
    /// Free notes.
    pub notes: Option<String>,
    /// Lines; optional when a purchase order is given.
    pub lines: Option<Vec<InvoiceLineInput>>,
}

/// Payload to change a draft invoice; omitted fields keep their value.
#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct UpdateInvoiceInput {
    /// New supplier invoice number.
    pub invoice_number: Option<String>,
    /// New invoice date.
    #[serde(default, deserialize_with = "tradocraft_core::serde_util::opt_date")]
    pub invoice_date: Option<NaiveDate>,
    /// New due date.
    #[serde(default, deserialize_with = "tradocraft_core::serde_util::opt_date")]
    pub due_date: Option<NaiveDate>,
    /// New notes.
    pub notes: Option<String>,
    /// Replaces all lines when present.
    pub lines: Option<Vec<InvoiceLineInput>>,
}

/// Payload to approve an invoice.
#[derive(Debug, Clone, Default, Deserialize, ToSchema)]
pub struct ApproveInvoiceInput {
    /// Required to approve an invoice whose match is not clean; recorded and audited.
    pub override_reason: Option<String>,
}

/// Payload to dispute an invoice.
#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct DisputeInvoiceInput {
    /// Why the invoice is disputed (required).
    pub reason: String,
}

/// Payload to record a payment.
#[derive(Debug, Clone, Default, Deserialize, ToSchema)]
pub struct MarkPaidInput {
    /// Payment date, default today.
    #[serde(default, deserialize_with = "tradocraft_core::serde_util::opt_date")]
    pub paid_at: Option<NaiveDate>,
    /// Bank or payment reference.
    pub payment_reference: Option<String>,
}

/// Filters for listing invoices.
#[derive(Debug, Clone, Default)]
pub struct InvoiceFilter {
    /// Only this status.
    pub status: Option<String>,
    /// Only this supplier.
    pub supplier_id: Option<Uuid>,
    /// Only this purchase order.
    pub purchase_order_id: Option<Uuid>,
    /// Substring of the supplier invoice number or the internal number.
    pub q: Option<String>,
    /// Page size (default 50, at most 200).
    pub limit: Option<i64>,
    /// Rows to skip.
    pub offset: Option<i64>,
}

/// Columns and table shared by every invoice header query.
const SELECT_SUMMARY: &str = "SELECT id, company_id, number, supplier_id, purchase_order_id,
    invoice_number, invoice_date, due_date, currency, status, net_total, vat_total, gross_total,
    notes, dispute_reason, override_reason, created_by_user_id, approved_by_user_id, approved_at,
    paid_at, payment_reference, created_at, updated_at
    FROM finance.supplier_invoices";

/// Rounds an amount to 2 decimals, half away from zero.
fn money(v: Decimal) -> Decimal {
    v.round_dp_with_strategy(2, RoundingStrategy::MidpointAwayFromZero)
}

/// Maps a unique violation to the duplicate-invoice-number conflict; other errors pass through.
fn duplicate_or(e: sqlx::Error) -> AppError {
    if let sqlx::Error::Database(d) = &e {
        if d.code().as_deref() == Some("23505") {
            return AppError::Conflict(
                "this supplier already has an invoice with that invoice number".into(),
            );
        }
    }
    e.into()
}

/// A validated line ready to be stored.
struct ValidLine {
    po_line_id: Option<Uuid>,
    product_id: Option<Uuid>,
    description: String,
    quantity: Decimal,
    unit_price: Decimal,
    vat_rate: Decimal,
    net: Decimal,
    vat: Decimal,
}

/// Validates line input against the purchase order (if any) and computes the line amounts.
fn validate_lines(
    inputs: Vec<InvoiceLineInput>,
    po: Option<&PurchaseOrderDetail>,
) -> AppResult<Vec<ValidLine>> {
    if inputs.is_empty() {
        return Err(AppError::Validation(
            "invoice must contain at least one line".into(),
        ));
    }
    let mut out = Vec::new();
    for (idx, l) in inputs.into_iter().enumerate() {
        let n = idx + 1;
        let bad = |m: &str| AppError::Validation(format!("line {n}: {m}"));
        if l.quantity <= Decimal::ZERO {
            return Err(bad("quantity must be greater than zero"));
        }
        if l.unit_price < Decimal::ZERO {
            return Err(bad("unit price cannot be negative"));
        }
        if l.quantity.scale() > 4 || l.unit_price.scale() > 4 {
            return Err(bad(
                "quantity and unit price allow at most 4 decimal places",
            ));
        }
        let vat_rate = l.vat_rate.unwrap_or(Decimal::ZERO);
        if vat_rate < Decimal::ZERO || vat_rate > Decimal::from(100) || vat_rate.scale() > 2 {
            return Err(bad(
                "VAT rate must be between 0 and 100 with at most 2 decimals",
            ));
        }
        let mut product_id = l.product_id;
        let mut description = l.description.unwrap_or_default().trim().to_string();
        if let Some(pl_id) = l.purchase_order_line_id {
            let po =
                po.ok_or_else(|| bad("an order line needs an invoice with a purchase order"))?;
            let pl = po
                .lines
                .iter()
                .find(|x| x.id == pl_id)
                .ok_or_else(|| bad("order line does not belong to the purchase order"))?;
            product_id = Some(pl.product_id);
            if description.is_empty() {
                description = pl.product_name.clone();
            }
        } else if description.is_empty() {
            return Err(bad("a free-text line needs a description"));
        }
        let overflow = || bad("amount too large");
        let net = money(l.quantity.checked_mul(l.unit_price).ok_or_else(overflow)?);
        let vat = money(net.checked_mul(vat_rate).ok_or_else(overflow)? / Decimal::from(100));
        out.push(ValidLine {
            po_line_id: l.purchase_order_line_id,
            product_id,
            description,
            quantity: l.quantity,
            unit_price: l.unit_price,
            vat_rate,
            net,
            vat,
        });
    }
    Ok(out)
}

/// Stores the validated lines and returns the net and VAT totals.
async fn insert_lines(
    conn: &mut PgConnection,
    invoice_id: Uuid,
    lines: &[ValidLine],
) -> AppResult<(Decimal, Decimal)> {
    let (mut net, mut vat) = (Decimal::ZERO, Decimal::ZERO);
    for (i, l) in lines.iter().enumerate() {
        sqlx::query(
            "INSERT INTO finance.supplier_invoice_lines
                (id, invoice_id, line_number, purchase_order_line_id, product_id, description,
                 quantity, unit_price, vat_rate, line_net, line_vat, line_gross)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)",
        )
        .bind(new_id())
        .bind(invoice_id)
        .bind(i as i32 + 1)
        .bind(l.po_line_id)
        .bind(l.product_id)
        .bind(&l.description)
        .bind(l.quantity)
        .bind(l.unit_price)
        .bind(l.vat_rate)
        .bind(l.net)
        .bind(l.vat)
        .bind(l.net + l.vat)
        .execute(&mut *conn)
        .await?;
        net += l.net;
        vat += l.vat;
    }
    Ok((net, vat))
}

/// Quantity invoiced per purchase order line by non-disputed invoices, leaving out one invoice
/// (the one being matched) when given.
async fn invoiced_by_po_line(
    conn: &mut PgConnection,
    company_id: Uuid,
    po_line_ids: &[Uuid],
    exclude_invoice: Option<Uuid>,
) -> AppResult<HashMap<Uuid, Decimal>> {
    let rows = sqlx::query_as::<_, (Uuid, Decimal)>(
        "SELECT l.purchase_order_line_id, SUM(l.quantity)
         FROM finance.supplier_invoice_lines l
         JOIN finance.supplier_invoices i ON i.id = l.invoice_id
         WHERE i.company_id = $1 AND i.status <> 'disputed'
           AND l.purchase_order_line_id = ANY($2)
           AND ($3::uuid IS NULL OR i.id <> $3)
         GROUP BY l.purchase_order_line_id",
    )
    .bind(company_id)
    .bind(po_line_ids)
    .bind(exclude_invoice)
    .fetch_all(conn)
    .await?;
    Ok(rows.into_iter().collect())
}

/// Evaluates the three-way match of an invoice now.
pub async fn match_report(
    conn: &mut PgConnection,
    company_id: Uuid,
    invoice: &InvoiceSummary,
    lines: &[InvoiceLine],
) -> AppResult<MatchReport> {
    let tol = settings::tolerance(conn, company_id).await?;
    let mut figures: HashMap<Uuid, PoFigures> = HashMap::new();
    let mut elsewhere = HashMap::new();
    if let Some(po_id) = invoice.purchase_order_id {
        let po = po_orders::load(conn, company_id, po_id).await?;
        let received: HashMap<Uuid, Decimal> =
            receipts::received_quantities(conn, company_id, po_id)
                .await?
                .into_iter()
                .collect();
        for pl in &po.lines {
            figures.insert(
                pl.id,
                PoFigures {
                    ordered: pl.quantity,
                    received: received.get(&pl.id).copied().unwrap_or(Decimal::ZERO),
                    unit_price: pl.unit_price,
                },
            );
        }
        let ids: Vec<Uuid> = figures.keys().copied().collect();
        elsewhere = invoiced_by_po_line(conn, company_id, &ids, Some(invoice.id)).await?;
    }
    // Quantity of this invoice's own lines per order line, to count lines that repeat one.
    let mut own: HashMap<Uuid, Decimal> = HashMap::new();
    for l in lines {
        if let Some(p) = l.purchase_order_line_id {
            *own.entry(p).or_default() += l.quantity;
        }
    }
    let inputs: Vec<LineInput> = lines
        .iter()
        .map(|l| {
            let po = l
                .purchase_order_line_id
                .and_then(|p| figures.get(&p).copied());
            let other = l
                .purchase_order_line_id
                .map(|p| {
                    elsewhere.get(&p).copied().unwrap_or_default()
                        + own.get(&p).copied().unwrap_or_default()
                        - l.quantity
                })
                .unwrap_or_default();
            LineInput {
                po,
                quantity: l.quantity,
                unit_price: l.unit_price,
                other_invoiced: other,
            }
        })
        .collect();
    let mut report = matching::match_invoice(&inputs, &tol);
    for (m, l) in report.lines.iter_mut().zip(lines) {
        m.invoice_line_id = l.id;
    }
    Ok(report)
}

/// Fills supplier names and purchase order numbers, read through purchasing.
async fn fill_names(
    conn: &mut PgConnection,
    company_id: Uuid,
    items: &mut [InvoiceSummary],
) -> AppResult<()> {
    let sup_ids: Vec<Uuid> = items.iter().map(|i| i.supplier_id).collect();
    let po_ids: Vec<Uuid> = items.iter().filter_map(|i| i.purchase_order_id).collect();
    let sup: HashMap<Uuid, String> = suppliers::names_by_id(conn, company_id, &sup_ids)
        .await?
        .into_iter()
        .collect();
    let pos: HashMap<Uuid, String> = po_orders::numbers_by_id(conn, company_id, &po_ids)
        .await?
        .into_iter()
        .collect();
    for i in items {
        i.supplier_name = sup.get(&i.supplier_id).cloned().unwrap_or_default();
        i.purchase_order_number = i.purchase_order_id.and_then(|p| pos.get(&p).cloned());
    }
    Ok(())
}

/// Loads an invoice header of the company, optionally locking the row.
async fn load_summary(
    conn: &mut PgConnection,
    company_id: Uuid,
    id: Uuid,
    lock: bool,
) -> AppResult<InvoiceSummary> {
    let sql = format!(
        "{SELECT_SUMMARY} WHERE company_id = $1 AND id = $2{}",
        if lock { " FOR UPDATE" } else { "" }
    );
    let mut s = sqlx::query_as::<_, InvoiceSummary>(&sql)
        .bind(company_id)
        .bind(id)
        .fetch_optional(&mut *conn)
        .await?
        .ok_or(AppError::NotFound("supplier invoice"))?;
    fill_names(conn, company_id, std::slice::from_mut(&mut s)).await?;
    Ok(s)
}

/// Loads the lines of an invoice in order.
async fn load_lines(conn: &mut PgConnection, invoice_id: Uuid) -> AppResult<Vec<InvoiceLine>> {
    sqlx::query_as::<_, InvoiceLine>(
        "SELECT id, invoice_id, line_number, purchase_order_line_id, product_id, description,
                quantity, unit_price, vat_rate, line_net, line_vat, line_gross
         FROM finance.supplier_invoice_lines WHERE invoice_id = $1 ORDER BY line_number",
    )
    .bind(invoice_id)
    .fetch_all(conn)
    .await
    .map_err(Into::into)
}

/// Loads an invoice with its lines and the live match report.
pub async fn load(conn: &mut PgConnection, company_id: Uuid, id: Uuid) -> AppResult<InvoiceDetail> {
    let summary = load_summary(conn, company_id, id, false).await?;
    let lines = load_lines(conn, id).await?;
    let match_report = match_report(conn, company_id, &summary, &lines).await?;
    Ok(InvoiceDetail {
        summary,
        lines,
        match_report,
    })
}

/// Lists invoices of the company, newest first.
pub async fn list(
    conn: &mut PgConnection,
    company_id: Uuid,
    f: InvoiceFilter,
) -> AppResult<InvoicePage> {
    /// Appends the WHERE clause of the list filters to the query.
    fn filters<'a>(
        qb: &mut QueryBuilder<'a, sqlx::Postgres>,
        company_id: Uuid,
        f: &'a InvoiceFilter,
    ) {
        qb.push(" WHERE company_id = ").push_bind(company_id);
        if let Some(s) = &f.status {
            qb.push(" AND status = ").push_bind(s.as_str());
        }
        if let Some(s) = f.supplier_id {
            qb.push(" AND supplier_id = ").push_bind(s);
        }
        if let Some(p) = f.purchase_order_id {
            qb.push(" AND purchase_order_id = ").push_bind(p);
        }
        if let Some(q) = f.q.as_deref().map(str::trim).filter(|q| !q.is_empty()) {
            let like = format!(
                "%{}%",
                q.replace('\\', "\\\\")
                    .replace('%', "\\%")
                    .replace('_', "\\_")
            );
            qb.push(" AND (invoice_number ILIKE ")
                .push_bind(like.clone())
                .push(" OR number ILIKE ")
                .push_bind(like)
                .push(")");
        }
    }
    if let Some(s) = &f.status {
        if !STATUSES.contains(&s.as_str()) {
            return Err(AppError::Validation(format!(
                "status must be one of {}",
                STATUSES.join(", ")
            )));
        }
    }
    let mut count = QueryBuilder::new("SELECT count(*) FROM finance.supplier_invoices");
    filters(&mut count, company_id, &f);
    let total: i64 = count.build_query_scalar().fetch_one(&mut *conn).await?;

    let mut qb = QueryBuilder::new(SELECT_SUMMARY);
    filters(&mut qb, company_id, &f);
    qb.push(" ORDER BY created_at DESC, id DESC LIMIT ")
        .push_bind(f.limit.unwrap_or(50).clamp(1, 200))
        .push(" OFFSET ")
        .push_bind(f.offset.unwrap_or(0).max(0));
    let mut items: Vec<InvoiceSummary> = qb.build_query_as().fetch_all(&mut *conn).await?;
    fill_names(conn, company_id, &mut items).await?;
    Ok(InvoicePage { items, total })
}

/// Order lines of an invoice's purchase order, prefilled with what is received and not yet
/// invoiced (all non-disputed invoices counted).
async fn prefill(
    conn: &mut PgConnection,
    company_id: Uuid,
    po: &PurchaseOrderDetail,
) -> AppResult<Vec<InvoiceLineInput>> {
    let received: HashMap<Uuid, Decimal> =
        receipts::received_quantities(conn, company_id, po.summary.id)
            .await?
            .into_iter()
            .collect();
    let ids: Vec<Uuid> = po.lines.iter().map(|l| l.id).collect();
    let invoiced = invoiced_by_po_line(conn, company_id, &ids, None).await?;
    Ok(po
        .lines
        .iter()
        .filter_map(|l| {
            let open = received.get(&l.id).copied().unwrap_or_default()
                - invoiced.get(&l.id).copied().unwrap_or_default();
            (open > Decimal::ZERO).then_some(InvoiceLineInput {
                purchase_order_line_id: Some(l.id),
                product_id: Some(l.product_id),
                description: None,
                quantity: open,
                unit_price: l.unit_price,
                vat_rate: None,
            })
        })
        .collect())
}

/// Trims the supplier invoice number and rejects an empty or overlong one.
fn required_number(raw: &str) -> AppResult<String> {
    let n = raw.trim();
    if n.is_empty() || n.len() > 64 {
        return Err(AppError::Validation(
            "invoice number is required (at most 64 characters)".into(),
        ));
    }
    Ok(n.to_string())
}

/// Registers a draft invoice (optionally from a purchase order), audited.
pub async fn create(
    conn: &mut PgConnection,
    user: &CurrentUser,
    input: NewInvoiceInput,
) -> AppResult<InvoiceDetail> {
    let invoice_number = required_number(&input.invoice_number)?;
    let po = match input.purchase_order_id {
        Some(po_id) => {
            po_orders::lock(conn, user.company_id, po_id).await?;
            let po = po_orders::load(conn, user.company_id, po_id).await?;
            if matches!(po.summary.status.as_str(), "draft" | "cancelled") {
                return Err(AppError::Conflict(format!(
                    "purchase order {} is {} and cannot be invoiced",
                    po.summary.number, po.summary.status
                )));
            }
            Some(po)
        }
        None => None,
    };
    let supplier_id = match (&po, input.supplier_id) {
        (Some(po), Some(s)) if po.summary.supplier_id != s => {
            return Err(AppError::Validation(
                "the supplier is not the supplier of the purchase order".into(),
            ))
        }
        (Some(po), _) => po.summary.supplier_id,
        (None, Some(s)) => s,
        (None, None) => {
            return Err(AppError::Validation(
                "supplier_id or purchase_order_id is required".into(),
            ))
        }
    };
    let supplier = suppliers::load(conn, user.company_id, supplier_id).await?;
    let currency = match &po {
        Some(po) => {
            let c = match &input.currency {
                Some(c) => suppliers::normalize_currency(c)?,
                None => po.summary.currency.clone(),
            };
            if c != po.summary.currency {
                return Err(AppError::Validation(format!(
                    "invoice currency {c} differs from the purchase order currency {}",
                    po.summary.currency
                )));
            }
            c
        }
        None => {
            suppliers::normalize_currency(input.currency.as_deref().unwrap_or(&supplier.currency))?
        }
    };
    let lines = match input.lines.filter(|l| !l.is_empty()) {
        Some(l) => l,
        None => match &po {
            Some(po) => {
                let l = prefill(conn, user.company_id, po).await?;
                if l.is_empty() {
                    return Err(AppError::Validation(
                        "nothing received on this purchase order is left to invoice".into(),
                    ));
                }
                l
            }
            None => {
                return Err(AppError::Validation(
                    "invoice must contain at least one line".into(),
                ))
            }
        },
    };
    let valid = validate_lines(lines, po.as_ref())?;
    let due_date = input
        .due_date
        .unwrap_or(input.invoice_date + Duration::days(supplier.payment_terms_days as i64));

    let id = new_id();
    let year = today().year();
    let seq = numbering::next_number(conn, user.company_id, "SI", year).await?;
    let number = format!("SI{year}-{seq:05}");
    sqlx::query(
        "INSERT INTO finance.supplier_invoices
            (id, company_id, number, supplier_id, purchase_order_id, invoice_number, invoice_date,
             due_date, currency, status, notes, created_by_user_id)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, 'draft', $10, $11)",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(&number)
    .bind(supplier_id)
    .bind(input.purchase_order_id)
    .bind(&invoice_number)
    .bind(input.invoice_date)
    .bind(due_date)
    .bind(&currency)
    .bind(input.notes.unwrap_or_default().trim())
    .bind(user.user_id)
    .execute(&mut *conn)
    .await
    .map_err(duplicate_or)?;
    let (net, vat) = insert_lines(conn, id, &valid).await?;
    set_totals(conn, id, net, vat).await?;
    audit::record(
        conn,
        user,
        "supplier_invoice",
        id,
        "created",
        serde_json::json!({
            "number": number,
            "invoice_number": invoice_number,
            "supplier_id": supplier_id,
            "purchase_order_id": input.purchase_order_id,
            "gross_total": (net + vat).to_string(),
        }),
    )
    .await?;
    load(conn, user.company_id, id).await
}

/// Stores the invoice totals.
async fn set_totals(
    conn: &mut PgConnection,
    id: Uuid,
    net: Decimal,
    vat: Decimal,
) -> AppResult<()> {
    sqlx::query(
        "UPDATE finance.supplier_invoices
         SET net_total = $2, vat_total = $3, gross_total = $4, updated_at = now() WHERE id = $1",
    )
    .bind(id)
    .bind(net)
    .bind(vat)
    .bind(net + vat)
    .execute(conn)
    .await?;
    Ok(())
}

/// The 409 for an action the invoice status does not allow.
fn conflict_status(inv: &InvoiceSummary, what: &str) -> AppError {
    AppError::Conflict(format!(
        "invoice {} is {} and cannot be {what}",
        inv.number, inv.status
    ))
}

/// Locks the invoice (and its purchase order, in the same order everywhere) and returns it.
async fn lock(conn: &mut PgConnection, company_id: Uuid, id: Uuid) -> AppResult<InvoiceSummary> {
    let pre = load_summary(conn, company_id, id, false).await?;
    if let Some(po) = pre.purchase_order_id {
        po_orders::lock(conn, company_id, po).await?;
    }
    load_summary(conn, company_id, id, true).await
}

/// Changes a draft invoice and replaces its lines when given (audited); other statuses give 409.
pub async fn update(
    conn: &mut PgConnection,
    user: &CurrentUser,
    id: Uuid,
    input: UpdateInvoiceInput,
) -> AppResult<InvoiceDetail> {
    let inv = lock(conn, user.company_id, id).await?;
    if inv.status != "draft" {
        return Err(conflict_status(&inv, "edited"));
    }
    let invoice_number = match &input.invoice_number {
        Some(n) => required_number(n)?,
        None => inv.invoice_number.clone(),
    };
    sqlx::query(
        "UPDATE finance.supplier_invoices
         SET invoice_number = $2, invoice_date = $3, due_date = $4, notes = $5, updated_at = now()
         WHERE id = $1",
    )
    .bind(id)
    .bind(&invoice_number)
    .bind(input.invoice_date.unwrap_or(inv.invoice_date))
    .bind(input.due_date.unwrap_or(inv.due_date))
    .bind(
        input
            .notes
            .as_deref()
            .map(str::trim)
            .unwrap_or(inv.notes.as_str()),
    )
    .execute(&mut *conn)
    .await
    .map_err(duplicate_or)?;
    if let Some(lines) = input.lines {
        let po = match inv.purchase_order_id {
            Some(p) => Some(po_orders::load(conn, user.company_id, p).await?),
            None => None,
        };
        let valid = validate_lines(lines, po.as_ref())?;
        sqlx::query("DELETE FROM finance.supplier_invoice_lines WHERE invoice_id = $1")
            .bind(id)
            .execute(&mut *conn)
            .await?;
        let (net, vat) = insert_lines(conn, id, &valid).await?;
        set_totals(conn, id, net, vat).await?;
    }
    audit::record(
        conn,
        user,
        "supplier_invoice",
        id,
        "updated",
        serde_json::json!({ "number": inv.number, "invoice_number": invoice_number }),
    )
    .await?;
    load(conn, user.company_id, id).await
}

/// Deletes a draft invoice (audited); other statuses give 409.
pub async fn delete(conn: &mut PgConnection, user: &CurrentUser, id: Uuid) -> AppResult<()> {
    let inv = lock(conn, user.company_id, id).await?;
    if inv.status != "draft" {
        return Err(conflict_status(&inv, "deleted"));
    }
    sqlx::query("DELETE FROM finance.supplier_invoices WHERE id = $1")
        .bind(id)
        .execute(&mut *conn)
        .await?;
    audit::record(
        conn,
        user,
        "supplier_invoice",
        id,
        "deleted",
        serde_json::json!({ "number": inv.number, "invoice_number": inv.invoice_number }),
    )
    .await?;
    Ok(())
}

/// Sets the invoice status.
async fn set_status(conn: &mut PgConnection, id: Uuid, status: &str) -> AppResult<()> {
    sqlx::query(
        "UPDATE finance.supplier_invoices SET status = $2, updated_at = now() WHERE id = $1",
    )
    .bind(id)
    .bind(status)
    .execute(conn)
    .await?;
    Ok(())
}

/// Re-evaluates the match of a draft or matched invoice: all lines ok makes it `matched`,
/// otherwise it is (back) in `draft`. Returns the invoice with the report.
pub async fn submit_match(
    conn: &mut PgConnection,
    user: &CurrentUser,
    id: Uuid,
) -> AppResult<InvoiceDetail> {
    let inv = lock(conn, user.company_id, id).await?;
    if !matches!(inv.status.as_str(), "draft" | "matched") {
        return Err(conflict_status(&inv, "matched again"));
    }
    let lines = load_lines(conn, id).await?;
    let report = match_report(conn, user.company_id, &inv, &lines).await?;
    let status = if report.matched { "matched" } else { "draft" };
    set_status(conn, id, status).await?;
    audit::record(
        conn,
        user,
        "supplier_invoice",
        id,
        "match_evaluated",
        serde_json::json!({
            "number": inv.number,
            "matched": report.matched,
            "issues": report.lines.iter().filter(|l| !l.issues.is_empty()).count(),
        }),
    )
    .await?;
    load(conn, user.company_id, id).await
}

/// Approves an invoice. Needs a clean match now; otherwise an `override_reason` is required and
/// recorded. Only draft and matched invoices can be approved (audited).
pub async fn approve(
    conn: &mut PgConnection,
    user: &CurrentUser,
    id: Uuid,
    input: ApproveInvoiceInput,
) -> AppResult<InvoiceDetail> {
    let inv = lock(conn, user.company_id, id).await?;
    if !matches!(inv.status.as_str(), "draft" | "matched") {
        return Err(conflict_status(&inv, "approved"));
    }
    let lines = load_lines(conn, id).await?;
    let report = match_report(conn, user.company_id, &inv, &lines).await?;
    let reason = input
        .override_reason
        .as_deref()
        .map(str::trim)
        .unwrap_or_default()
        .to_string();
    let clean = report.matched;
    if !clean && reason.is_empty() {
        return Err(AppError::Conflict(format!(
            "invoice {} does not match its purchase order and receipts; an override_reason is required to approve it",
            inv.number
        )));
    }
    let override_reason = if clean { "" } else { reason.as_str() };
    sqlx::query(
        "UPDATE finance.supplier_invoices
         SET status = 'approved', approved_by_user_id = $2, approved_at = now(),
             override_reason = $3, dispute_reason = '', updated_at = now()
         WHERE id = $1",
    )
    .bind(id)
    .bind(user.user_id)
    .bind(override_reason)
    .execute(&mut *conn)
    .await?;
    audit::record(
        conn,
        user,
        "supplier_invoice",
        id,
        "approved",
        serde_json::json!({
            "number": inv.number,
            "override": !clean,
            "override_reason": override_reason,
            "problem_lines": report.lines.iter().filter(|l| !l.issues.is_empty()).count(),
            "gross_total": inv.gross_total.to_string(),
        }),
    )
    .await?;
    load(conn, user.company_id, id).await
}

/// Disputes a draft, matched or approved invoice with a reason (audited). An approval is
/// withdrawn.
pub async fn dispute(
    conn: &mut PgConnection,
    user: &CurrentUser,
    id: Uuid,
    input: DisputeInvoiceInput,
) -> AppResult<InvoiceDetail> {
    let reason = input.reason.trim().to_string();
    if reason.is_empty() {
        return Err(AppError::Validation("a dispute reason is required".into()));
    }
    let inv = lock(conn, user.company_id, id).await?;
    if !matches!(inv.status.as_str(), "draft" | "matched" | "approved") {
        return Err(conflict_status(&inv, "disputed"));
    }
    sqlx::query(
        "UPDATE finance.supplier_invoices
         SET status = 'disputed', dispute_reason = $2, override_reason = '',
             approved_by_user_id = NULL, approved_at = NULL, updated_at = now()
         WHERE id = $1",
    )
    .bind(id)
    .bind(&reason)
    .execute(&mut *conn)
    .await?;
    audit::record(
        conn,
        user,
        "supplier_invoice",
        id,
        "disputed",
        serde_json::json!({ "number": inv.number, "from": inv.status, "reason": reason }),
    )
    .await?;
    load(conn, user.company_id, id).await
}

/// Takes a disputed or matched invoice back to draft so it can be edited (audited). While
/// disputed an invoice does not count as invoiced on its order lines; reopening makes it count.
pub async fn reopen(
    conn: &mut PgConnection,
    user: &CurrentUser,
    id: Uuid,
) -> AppResult<InvoiceDetail> {
    let inv = lock(conn, user.company_id, id).await?;
    if !matches!(inv.status.as_str(), "disputed" | "matched") {
        return Err(conflict_status(&inv, "reopened"));
    }
    sqlx::query(
        "UPDATE finance.supplier_invoices
         SET status = 'draft', dispute_reason = '', updated_at = now() WHERE id = $1",
    )
    .bind(id)
    .execute(&mut *conn)
    .await?;
    audit::record(
        conn,
        user,
        "supplier_invoice",
        id,
        "reopened",
        serde_json::json!({ "number": inv.number, "from": inv.status }),
    )
    .await?;
    load(conn, user.company_id, id).await
}

/// Records that an approved invoice was paid (audited). Payment itself happens in the bank or
/// accounting package (ADR 0008).
pub async fn mark_paid(
    conn: &mut PgConnection,
    user: &CurrentUser,
    id: Uuid,
    input: MarkPaidInput,
) -> AppResult<InvoiceDetail> {
    let inv = lock(conn, user.company_id, id).await?;
    if inv.status != "approved" {
        return Err(conflict_status(&inv, "marked paid"));
    }
    let paid_at = input.paid_at.unwrap_or_else(today);
    let reference = input
        .payment_reference
        .unwrap_or_default()
        .trim()
        .to_string();
    sqlx::query(
        "UPDATE finance.supplier_invoices
         SET status = 'paid', paid_at = $2, payment_reference = $3, updated_at = now()
         WHERE id = $1",
    )
    .bind(id)
    .bind(paid_at)
    .bind(&reference)
    .execute(&mut *conn)
    .await?;
    audit::record(
        conn,
        user,
        "supplier_invoice",
        id,
        "paid",
        serde_json::json!({
            "number": inv.number,
            "paid_at": paid_at.to_string(),
            "payment_reference": reference,
        }),
    )
    .await?;
    load(conn, user.company_id, id).await
}
