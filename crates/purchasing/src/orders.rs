use crate::suppliers::normalize_currency;
use chrono::{DateTime, Datelike, NaiveDate, Utc};
use rust_decimal::{Decimal, RoundingStrategy};
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection};
use tradocraft_core::{audit, new_id, numbering, today, AppError, AppResult, CurrentUser};
use utoipa::ToSchema;
use uuid::Uuid;

/// Purchase order header with supplier name and totals.
#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct PurchaseOrderSummary {
    pub id: Uuid,
    pub company_id: Uuid,
    pub number: String,
    pub supplier_id: Uuid,
    pub supplier_name: String,
    /// draft | approved | sent | partially_received | received | cancelled
    pub status: String,
    pub order_date: NaiveDate,
    pub expected_delivery_date: Option<NaiveDate>,
    pub currency: String,
    #[schema(value_type = String)]
    pub subtotal: Decimal,
    #[schema(value_type = String)]
    pub tax_total: Decimal,
    #[schema(value_type = String)]
    pub total: Decimal,
    pub notes: String,
    pub created_by_user_id: Uuid,
    pub approved_by_user_id: Option<Uuid>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// A purchase order line with received quantity.
#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct PurchaseOrderLine {
    pub id: Uuid,
    pub purchase_order_id: Uuid,
    pub line_number: i32,
    pub product_id: Uuid,
    pub product_code: String,
    pub product_name: String,
    pub supplier_product_code: String,
    pub description: String,
    #[schema(value_type = String)]
    pub quantity: Decimal,
    #[schema(value_type = String)]
    pub quantity_received: Decimal,
    #[schema(value_type = String)]
    pub unit_price: Decimal,
    #[schema(value_type = String)]
    pub line_total: Decimal,
    #[schema(required = false, value_type = String, example = "21.00")]
    pub vat_rate: Decimal,
    pub created_at: DateTime<Utc>,
}

/// Purchase order header together with its lines.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct PurchaseOrderDetail {
    #[serde(flatten)]
    pub summary: PurchaseOrderSummary,
    pub lines: Vec<PurchaseOrderLine>,
}

/// A line of a new purchase order.
#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct NewPoLineInput {
    pub product_id: Uuid,
    pub supplier_product_code: Option<String>,
    pub description: Option<String>,
    #[schema(value_type = String)]
    pub quantity: Decimal,
    #[schema(value_type = String)]
    pub unit_price: Decimal,
    /// Optional explicit VAT rate (%). When omitted, domestic suppliers resolve from the product's
    /// VAT category on the order date and cross-border suppliers default to `0`.
    #[serde(default)]
    #[schema(required = false, value_type = Option<String>, example = "21.00")]
    pub vat_rate: Option<Decimal>,
}

/// Payload to create a draft purchase order.
#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct NewPurchaseOrderInput {
    pub supplier_id: Uuid,
    #[serde(default, deserialize_with = "tradocraft_core::serde_util::opt_date")]
    pub order_date: Option<NaiveDate>,
    #[serde(default, deserialize_with = "tradocraft_core::serde_util::opt_date")]
    pub expected_delivery_date: Option<NaiveDate>,
    pub currency: Option<String>,
    pub notes: Option<String>,
    pub lines: Vec<NewPoLineInput>,
}

/// Payload to change a draft purchase order.
#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct UpdatePurchaseOrderInput {
    #[serde(default, deserialize_with = "tradocraft_core::serde_util::opt_date")]
    pub expected_delivery_date: Option<NaiveDate>,
    pub currency: Option<String>,
    pub notes: Option<String>,
    pub lines: Option<Vec<NewPoLineInput>>,
}

const SELECT_SUMMARY: &str = r#"
    SELECT po.id, po.company_id, po.number, po.supplier_id, s.name AS supplier_name,
           po.status, po.order_date, po.expected_delivery_date, po.currency,
           po.subtotal, po.tax_total, po.total, po.notes,
           po.created_by_user_id, po.approved_by_user_id,
           po.created_at, po.updated_at
    FROM purchasing.purchase_orders po
    JOIN purchasing.suppliers s ON s.id = po.supplier_id
"#;

/// Locks the purchase order row for the rest of the transaction (`SELECT ... FOR UPDATE`).
pub async fn lock(conn: &mut PgConnection, company_id: Uuid, id: Uuid) -> AppResult<()> {
    sqlx::query_scalar::<_, Uuid>(
        "SELECT id FROM purchasing.purchase_orders WHERE company_id = $1 AND id = $2 FOR UPDATE",
    )
    .bind(company_id)
    .bind(id)
    .fetch_optional(conn)
    .await?
    .map(|_| ())
    .ok_or(AppError::NotFound("purchase order not found"))
}

/// Loads a purchase order with its lines.
pub async fn load(
    conn: &mut PgConnection,
    company_id: Uuid,
    id: Uuid,
) -> AppResult<PurchaseOrderDetail> {
    let summary = sqlx::query_as::<_, PurchaseOrderSummary>(&format!(
        "{SELECT_SUMMARY} WHERE po.company_id = $1 AND po.id = $2"
    ))
    .bind(company_id)
    .bind(id)
    .fetch_optional(&mut *conn)
    .await?
    .ok_or_else(|| AppError::NotFound("purchase order not found"))?;

    let lines = sqlx::query_as::<_, PurchaseOrderLine>(
        "SELECT l.id, l.purchase_order_id, l.line_number, l.product_id,
                p.code AS product_code, p.name AS product_name,
                l.supplier_product_code, l.description, l.quantity,
                l.quantity_received, l.unit_price, l.line_total, l.vat_rate, l.created_at
         FROM purchasing.purchase_order_lines l
         JOIN products.products p ON p.id = l.product_id
         WHERE l.purchase_order_id = $1
         ORDER BY l.line_number ASC",
    )
    .bind(id)
    .fetch_all(conn)
    .await?;

    Ok(PurchaseOrderDetail { summary, lines })
}

/// Lists purchase orders of the company, optionally filtered by supplier and status.
pub async fn list(
    conn: &mut PgConnection,
    company_id: Uuid,
    supplier_id: Option<Uuid>,
    status: Option<String>,
) -> AppResult<Vec<PurchaseOrderSummary>> {
    let mut q = format!("{SELECT_SUMMARY} WHERE po.company_id = $1");
    if supplier_id.is_some() {
        q.push_str(" AND po.supplier_id = $2");
    }
    if status.is_some() {
        if supplier_id.is_some() {
            q.push_str(" AND po.status = $3");
        } else {
            q.push_str(" AND po.status = $2");
        }
    }
    q.push_str(" ORDER BY po.created_at DESC");

    let mut query = sqlx::query_as::<_, PurchaseOrderSummary>(&q).bind(company_id);
    if let Some(sid) = supplier_id {
        query = query.bind(sid);
    }
    if let Some(st) = status {
        query = query.bind(st);
    }

    query.fetch_all(conn).await.map_err(Into::into)
}

/// Creates a draft purchase order with validated, rounded lines and an audit event.
pub async fn create(
    conn: &mut PgConnection,
    user: &CurrentUser,
    input: NewPurchaseOrderInput,
) -> AppResult<PurchaseOrderDetail> {
    if input.lines.is_empty() {
        return Err(AppError::Validation(
            "purchase order must contain at least one line".into(),
        ));
    }

    // Verify supplier belongs to company
    let supplier_meta: Option<(String, String)> = sqlx::query_as(
        "SELECT currency, country FROM purchasing.suppliers WHERE company_id = $1 AND id = $2 AND active = true",
    )
    .bind(user.company_id)
    .bind(input.supplier_id)
    .fetch_optional(&mut *conn)
    .await?;

    let (default_currency, supplier_country) = match supplier_meta {
        Some(m) => m,
        None => return Err(AppError::NotFound("active supplier not found")),
    };

    let currency = normalize_currency(&input.currency.unwrap_or(default_currency))?;
    let order_date = input.order_date.unwrap_or_else(today);
    let order_year = order_date.year();

    let seq = numbering::next_number(conn, user.company_id, "PO", order_year).await?;
    let number = format!("PO{order_year}-{seq:05}");
    let id = new_id();

    let (subtotal, tax_total, validated_lines) = validate_lines(
        conn,
        user.company_id,
        &supplier_country,
        order_date,
        input.lines,
    )
    .await?;
    let total = subtotal
        .checked_add(tax_total)
        .ok_or_else(|| AppError::Validation("amount too large".into()))?;

    sqlx::query(
        "INSERT INTO purchasing.purchase_orders (
            id, company_id, number, supplier_id, status, order_date, expected_delivery_date,
            currency, subtotal, tax_total, total, notes, created_by_user_id, created_at, updated_at
         )
         VALUES ($1, $2, $3, $4, 'draft', $5, $6, $7, $8, $9, $10, $11, $12, now(), now())",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(&number)
    .bind(input.supplier_id)
    .bind(order_date)
    .bind(input.expected_delivery_date)
    .bind(&currency)
    .bind(subtotal)
    .bind(tax_total)
    .bind(total)
    .bind(input.notes.unwrap_or_default().trim())
    .bind(user.user_id)
    .execute(&mut *conn)
    .await?;

    insert_lines(conn, id, validated_lines).await?;

    audit::record(
        conn,
        user,
        "purchase_order",
        id,
        "created",
        serde_json::json!({
            "number": number,
            "supplier_id": input.supplier_id,
            "total": total.to_string(),
        }),
    )
    .await?;

    load(conn, user.company_id, id).await
}

/// A validated line: line number, input, rounded line total, and effective VAT rate.
type ValidatedLine = (i32, NewPoLineInput, Decimal, Decimal);

/// Validates the lines of a purchase order, resolves line VAT rates, and returns `(subtotal, tax_total, lines)`.
async fn validate_lines(
    conn: &mut PgConnection,
    company_id: Uuid,
    supplier_country: &str,
    order_date: NaiveDate,
    lines: Vec<NewPoLineInput>,
) -> AppResult<(Decimal, Decimal, Vec<ValidatedLine>)> {
    if lines.is_empty() {
        return Err(AppError::Validation(
            "purchase order must contain at least one line".into(),
        ));
    }
    let company = tradocraft_core::company::get_company(&mut *conn, company_id).await?;
    let domestic = supplier_country
        .trim()
        .eq_ignore_ascii_case(&company.country_code);
    let rules = if domestic {
        tradocraft_core::vat_rates::load_country_rules(&mut *conn, &company.country_code).await?
    } else {
        Vec::new()
    };

    let mut subtotal = Decimal::ZERO;
    let mut tax_total = Decimal::ZERO;
    let mut validated_lines = Vec::new();

    for (idx, line) in lines.into_iter().enumerate() {
        if line.quantity <= Decimal::ZERO {
            return Err(AppError::Validation(format!(
                "line {}: quantity must be greater than zero",
                idx + 1
            )));
        }
        if line.unit_price < Decimal::ZERO {
            return Err(AppError::Validation(format!(
                "line {}: unit price cannot be negative",
                idx + 1
            )));
        }
        if line.quantity.scale() > 4 || line.unit_price.scale() > 4 {
            return Err(AppError::Validation(format!(
                "line {}: quantity and unit price allow at most 4 decimal places",
                idx + 1
            )));
        }

        let product_vat: Option<(String, Option<Decimal>)> = sqlx::query_as(
            "SELECT vat_category, vat_rate_override FROM products.products WHERE id = $1",
        )
        .bind(line.product_id)
        .fetch_optional(&mut *conn)
        .await?;

        let (vat_category, vat_override) = match product_vat {
            Some(v) => v,
            None => {
                return Err(AppError::Validation(format!(
                    "line {}: product not found",
                    idx + 1
                )));
            }
        };

        let vat_rate = match line.vat_rate {
            Some(r) => {
                if r < Decimal::ZERO || r >= Decimal::from(100) || r.scale() > 2 {
                    return Err(AppError::Validation(format!(
                        "line {}: vat_rate must be between 0 (inclusive) and 100 (exclusive) with at most 2 decimals",
                        idx + 1
                    )));
                }
                r
            }
            None if domestic => tradocraft_core::vat_rates::resolve_rate_from_rules(
                &rules,
                &tradocraft_core::vat_rates::VatResolutionContext {
                    country_code: &company.country_code,
                    category: &vat_category,
                    product_override: vat_override,
                    vat_regime: Some("domestic"),
                    purpose: None,
                    building_construction_year: None,
                    as_of: order_date,
                },
            ),
            None => Decimal::ZERO,
        };

        let overflow = || AppError::Validation(format!("line {}: amount too large", idx + 1));
        let line_total = line
            .quantity
            .checked_mul(line.unit_price)
            .ok_or_else(overflow)?
            .round_dp_with_strategy(2, RoundingStrategy::MidpointAwayFromZero);
        let line_tax = (line_total.checked_mul(vat_rate).ok_or_else(overflow)?
            / Decimal::from(100))
        .round_dp_with_strategy(2, RoundingStrategy::MidpointAwayFromZero);
        subtotal = subtotal.checked_add(line_total).ok_or_else(overflow)?;
        tax_total = tax_total.checked_add(line_tax).ok_or_else(overflow)?;
        validated_lines.push((idx as i32 + 1, line, line_total, vat_rate));
    }

    Ok((subtotal, tax_total, validated_lines))
}

/// Inserts validated lines for a purchase order.
async fn insert_lines(
    conn: &mut PgConnection,
    id: Uuid,
    validated_lines: Vec<ValidatedLine>,
) -> AppResult<()> {
    for (line_num, line, line_total, vat_rate) in validated_lines {
        let line_id = new_id();
        sqlx::query(
            "INSERT INTO purchasing.purchase_order_lines (
                id, purchase_order_id, line_number, product_id, supplier_product_code,
                description, quantity, quantity_received, unit_price, line_total, vat_rate, created_at
             )
             VALUES ($1, $2, $3, $4, $5, $6, $7, 0, $8, $9, $10, now())",
        )
        .bind(line_id)
        .bind(id)
        .bind(line_num)
        .bind(line.product_id)
        .bind(line.supplier_product_code.unwrap_or_default().trim())
        .bind(line.description.unwrap_or_default().trim())
        .bind(line.quantity)
        .bind(line.unit_price)
        .bind(line_total)
        .bind(vat_rate)
        .execute(&mut *conn)
        .await?;
    }

    Ok(())
}

/// Changes a draft purchase order (header fields and, when given, all lines).
pub async fn update(
    conn: &mut PgConnection,
    user: &CurrentUser,
    id: Uuid,
    input: UpdatePurchaseOrderInput,
) -> AppResult<PurchaseOrderDetail> {
    lock(conn, user.company_id, id).await?;
    let po = load(conn, user.company_id, id).await?;
    if po.summary.status != "draft" {
        return Err(AppError::Conflict(format!(
            "only draft purchase orders can be changed (current status: {})",
            po.summary.status
        )));
    }
    let currency = match input.currency {
        Some(c) => normalize_currency(&c)?,
        None => po.summary.currency.clone(),
    };
    let expected = input
        .expected_delivery_date
        .or(po.summary.expected_delivery_date);
    let notes = match input.notes {
        Some(n) => n.trim().to_string(),
        None => po.summary.notes.clone(),
    };
    let mut subtotal = po.summary.subtotal;
    let mut tax_total = po.summary.tax_total;
    if let Some(lines) = input.lines {
        let supplier_country: String =
            sqlx::query_scalar("SELECT country FROM purchasing.suppliers WHERE id = $1")
                .bind(po.summary.supplier_id)
                .fetch_one(&mut *conn)
                .await?;
        let (st, tt, validated) = validate_lines(
            conn,
            user.company_id,
            &supplier_country,
            po.summary.order_date,
            lines,
        )
        .await?;
        sqlx::query("DELETE FROM purchasing.purchase_order_lines WHERE purchase_order_id = $1")
            .bind(id)
            .execute(&mut *conn)
            .await?;
        insert_lines(conn, id, validated).await?;
        subtotal = st;
        tax_total = tt;
    }
    let total = subtotal
        .checked_add(tax_total)
        .ok_or_else(|| AppError::Validation("amount too large".into()))?;
    sqlx::query(
        "UPDATE purchasing.purchase_orders
         SET expected_delivery_date = $3, currency = $4, notes = $5,
             subtotal = $6, tax_total = $7, total = $8, updated_at = now()
         WHERE company_id = $1 AND id = $2",
    )
    .bind(user.company_id)
    .bind(id)
    .bind(expected)
    .bind(&currency)
    .bind(&notes)
    .bind(subtotal)
    .bind(tax_total)
    .bind(total)
    .execute(&mut *conn)
    .await?;
    audit::record(
        conn,
        user,
        "purchase_order",
        id,
        "updated",
        serde_json::json!({ "number": po.summary.number, "total": total.to_string() }),
    )
    .await?;
    load(conn, user.company_id, id).await
}

/// Approves a draft purchase order (row-locked, audited).
pub async fn approve(
    conn: &mut PgConnection,
    user: &CurrentUser,
    id: Uuid,
) -> AppResult<PurchaseOrderDetail> {
    lock(conn, user.company_id, id).await?;
    let po = load(conn, user.company_id, id).await?;
    if po.summary.status != "draft" {
        return Err(AppError::Conflict(format!(
            "only draft purchase orders can be approved (current status: {})",
            po.summary.status
        )));
    }

    sqlx::query(
        "UPDATE purchasing.purchase_orders
         SET status = 'approved', approved_by_user_id = $2, updated_at = now()
         WHERE company_id = $1 AND id = $3",
    )
    .bind(user.company_id)
    .bind(user.user_id)
    .bind(id)
    .execute(&mut *conn)
    .await?;

    audit::record(
        conn,
        user,
        "purchase_order",
        id,
        "approved",
        serde_json::json!({ "number": po.summary.number }),
    )
    .await?;

    load(conn, user.company_id, id).await
}

/// Marks an approved purchase order as sent; no PDF or e-mail is produced yet.
pub async fn send(
    conn: &mut PgConnection,
    user: &CurrentUser,
    id: Uuid,
) -> AppResult<PurchaseOrderDetail> {
    lock(conn, user.company_id, id).await?;
    let po = load(conn, user.company_id, id).await?;
    if po.summary.status != "approved" {
        return Err(AppError::Conflict(format!(
            "only approved purchase orders can be sent (current status: {})",
            po.summary.status
        )));
    }

    sqlx::query(
        "UPDATE purchasing.purchase_orders
         SET status = 'sent', updated_at = now()
         WHERE company_id = $1 AND id = $2",
    )
    .bind(user.company_id)
    .bind(id)
    .execute(&mut *conn)
    .await?;

    audit::record(
        conn,
        user,
        "purchase_order",
        id,
        "sent",
        serde_json::json!({ "number": po.summary.number }),
    )
    .await?;

    load(conn, user.company_id, id).await
}

/// Cancels a purchase order that has not received goods yet.
pub async fn cancel(
    conn: &mut PgConnection,
    user: &CurrentUser,
    id: Uuid,
) -> AppResult<PurchaseOrderDetail> {
    lock(conn, user.company_id, id).await?;
    let po = load(conn, user.company_id, id).await?;
    if matches!(
        po.summary.status.as_str(),
        "partially_received" | "received" | "cancelled"
    ) {
        return Err(AppError::Conflict(format!(
            "cannot cancel purchase order with status {}",
            po.summary.status
        )));
    }

    sqlx::query(
        "UPDATE purchasing.purchase_orders
         SET status = 'cancelled', updated_at = now()
         WHERE company_id = $1 AND id = $2",
    )
    .bind(user.company_id)
    .bind(id)
    .execute(&mut *conn)
    .await?;

    audit::record(
        conn,
        user,
        "purchase_order",
        id,
        "cancelled",
        serde_json::json!({ "number": po.summary.number }),
    )
    .await?;

    load(conn, user.company_id, id).await
}

/// Looks up the numbers of purchase orders by id (for modules that only hold the id, such as
/// finance). Unknown or foreign ids are simply absent from the result.
pub async fn numbers_by_id(
    conn: &mut PgConnection,
    company_id: Uuid,
    ids: &[Uuid],
) -> AppResult<Vec<(Uuid, String)>> {
    sqlx::query_as::<_, (Uuid, String)>(
        "SELECT id, number FROM purchasing.purchase_orders
         WHERE company_id = $1 AND id = ANY($2)",
    )
    .bind(company_id)
    .bind(ids)
    .fetch_all(conn)
    .await
    .map_err(Into::into)
}
