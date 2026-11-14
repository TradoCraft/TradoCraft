use chrono::{DateTime, Datelike, Utc};
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection};
use tradocraft_core::{audit, new_id, numbering, today, AppError, AppResult, CurrentUser};
use tradocraft_engineering::serials;
use tradocraft_inventory::ledger::{self, NewMove};
use utoipa::ToSchema;
use uuid::Uuid;

/// Goods receipt header.
#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct GoodsReceiptSummary {
    pub id: Uuid,
    pub company_id: Uuid,
    pub number: String,
    pub purchase_order_id: Uuid,
    pub purchase_order_number: String,
    pub supplier_name: String,
    pub warehouse_id: Uuid,
    pub location_id: Uuid,
    pub received_date: DateTime<Utc>,
    pub received_by_user_id: Uuid,
    pub carrier: String,
    pub tracking_number: String,
    pub supplier_delivery_note: String,
    pub notes: String,
    pub created_at: DateTime<Utc>,
}

/// A received line of a goods receipt.
#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct GoodsReceiptLine {
    pub id: Uuid,
    pub goods_receipt_id: Uuid,
    pub po_line_id: Uuid,
    pub product_id: Uuid,
    pub product_code: String,
    pub product_name: String,
    #[schema(value_type = String)]
    pub quantity_received: Decimal,
    pub lot_number: Option<String>,
    pub created_at: DateTime<Utc>,
}

/// Goods receipt header together with its lines.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct GoodsReceiptDetail {
    #[serde(flatten)]
    pub summary: GoodsReceiptSummary,
    pub lines: Vec<GoodsReceiptLine>,
}

/// One purchase order line being received.
#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct ReceiveGoodsLineInput {
    pub po_line_id: Uuid,
    #[schema(value_type = String)]
    pub quantity: Decimal,
    pub lot_number: Option<String>,
    pub serial_numbers: Option<Vec<String>>,
}

/// Payload to book a goods receipt against a purchase order.
#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct ReceiveGoodsInput {
    pub warehouse_id: Uuid,
    pub location_id: Uuid,
    pub carrier: Option<String>,
    pub tracking_number: Option<String>,
    pub supplier_delivery_note: Option<String>,
    pub notes: Option<String>,
    pub lines: Vec<ReceiveGoodsLineInput>,
}

const SELECT_GR_SUMMARY: &str = r#"
    SELECT gr.id, gr.company_id, gr.number, gr.purchase_order_id,
           po.number AS purchase_order_number, s.name AS supplier_name,
           gr.warehouse_id, gr.location_id, gr.received_date, gr.received_by_user_id,
           gr.carrier, gr.tracking_number, gr.supplier_delivery_note, gr.notes,
           gr.created_at
    FROM purchasing.goods_receipts gr
    JOIN purchasing.purchase_orders po ON po.id = gr.purchase_order_id
    JOIN purchasing.suppliers s ON s.id = po.supplier_id
"#;

/// Loads a goods receipt with its lines.
pub async fn load(
    conn: &mut PgConnection,
    company_id: Uuid,
    id: Uuid,
) -> AppResult<GoodsReceiptDetail> {
    let summary = sqlx::query_as::<_, GoodsReceiptSummary>(&format!(
        "{SELECT_GR_SUMMARY} WHERE gr.company_id = $1 AND gr.id = $2"
    ))
    .bind(company_id)
    .bind(id)
    .fetch_optional(&mut *conn)
    .await?
    .ok_or_else(|| AppError::NotFound("goods receipt not found"))?;

    let lines = sqlx::query_as::<_, GoodsReceiptLine>(
        "SELECT grl.id, grl.goods_receipt_id, grl.po_line_id, grl.product_id,
                p.code AS product_code, p.name AS product_name,
                grl.quantity_received, grl.lot_number, grl.created_at
         FROM purchasing.goods_receipt_lines grl
         JOIN products.products p ON p.id = grl.product_id
         WHERE grl.goods_receipt_id = $1
         ORDER BY grl.created_at ASC",
    )
    .bind(id)
    .fetch_all(conn)
    .await?;

    Ok(GoodsReceiptDetail { summary, lines })
}

/// Lists the goods receipts booked against a purchase order.
pub async fn list_for_po(
    conn: &mut PgConnection,
    company_id: Uuid,
    po_id: Uuid,
) -> AppResult<Vec<GoodsReceiptSummary>> {
    sqlx::query_as::<_, GoodsReceiptSummary>(&format!(
        "{SELECT_GR_SUMMARY} WHERE gr.company_id = $1 AND gr.purchase_order_id = $2 ORDER BY gr.received_date DESC"
    ))
    .bind(company_id)
    .bind(po_id)
    .fetch_all(conn)
    .await
    .map_err(Into::into)
}

/// Books a goods receipt: locks the order, posts stock moves and updates line quantities and order status.
pub async fn receive(
    conn: &mut PgConnection,
    user: &CurrentUser,
    po_id: Uuid,
    input: ReceiveGoodsInput,
) -> AppResult<GoodsReceiptDetail> {
    if input.lines.is_empty() {
        return Err(AppError::Validation(
            "receipt must include at least one line".into(),
        ));
    }

    // 1. Lock the PO (serializes with cancel and concurrent receipts), verify status
    crate::orders::lock(&mut *conn, user.company_id, po_id).await?;
    let po = crate::orders::load(&mut *conn, user.company_id, po_id).await?;
    if !matches!(
        po.summary.status.as_str(),
        "approved" | "sent" | "partially_received"
    ) {
        return Err(AppError::Conflict(format!(
            "purchase order {} cannot receive goods in status {}",
            po.summary.number, po.summary.status
        )));
    }

    // 2. Verify destination warehouse and location
    let location_ok: bool = sqlx::query_scalar(
        "SELECT EXISTS (
            SELECT 1 FROM inventory.locations
            WHERE company_id = $1 AND warehouse_id = $2 AND id = $3 AND kind = 'internal'
         )",
    )
    .bind(user.company_id)
    .bind(input.warehouse_id)
    .bind(input.location_id)
    .fetch_one(&mut *conn)
    .await?;

    if !location_ok {
        return Err(AppError::Validation(
            "destination location must be an internal location within the specified warehouse"
                .into(),
        ));
    }

    // 3. Virtual supplier location
    let vendor_location = ledger::virtual_location(&mut *conn, user.company_id, "supplier").await?;

    // 4. Generate GR number
    let gr_year = today().year();
    let seq = numbering::next_number(&mut *conn, user.company_id, "GR", gr_year).await?;
    let gr_number = format!("GR{gr_year}-{seq:05}");
    let gr_id = new_id();

    sqlx::query(
        "INSERT INTO purchasing.goods_receipts (
            id, company_id, number, purchase_order_id, warehouse_id, location_id,
            received_date, received_by_user_id, carrier, tracking_number,
            supplier_delivery_note, notes, created_at
         )
         VALUES ($1, $2, $3, $4, $5, $6, now(), $7, $8, $9, $10, $11, now())",
    )
    .bind(gr_id)
    .bind(user.company_id)
    .bind(&gr_number)
    .bind(po_id)
    .bind(input.warehouse_id)
    .bind(input.location_id)
    .bind(user.user_id)
    .bind(input.carrier.unwrap_or_default().trim())
    .bind(input.tracking_number.unwrap_or_default().trim())
    .bind(input.supplier_delivery_note.unwrap_or_default().trim())
    .bind(input.notes.unwrap_or_default().trim())
    .execute(&mut *conn)
    .await?;

    // 5. Process lines
    for item in input.lines {
        if item.quantity <= Decimal::ZERO {
            return Err(AppError::Validation(
                "received quantity must be greater than zero".into(),
            ));
        }

        let po_line = po
            .lines
            .iter()
            .find(|l| l.id == item.po_line_id)
            .ok_or_else(|| AppError::NotFound("purchase order line not found on this order"))?;

        let remaining = po_line.quantity - po_line.quantity_received;
        if item.quantity > remaining {
            return Err(AppError::Validation(format!(
                "cannot receive {} units for product {}: only {} remaining",
                item.quantity, po_line.product_code, remaining
            )));
        }

        // Check product tracking mode
        let tracking: String =
            sqlx::query_scalar("SELECT tracking FROM products.products WHERE id = $1")
                .bind(po_line.product_id)
                .fetch_one(&mut *conn)
                .await?;

        let gr_line_id = new_id();
        sqlx::query(
            "INSERT INTO purchasing.goods_receipt_lines (
                id, goods_receipt_id, po_line_id, product_id, quantity_received, lot_number, created_at
             )
             VALUES ($1, $2, $3, $4, $5, $6, now())",
        )
        .bind(gr_line_id)
        .bind(gr_id)
        .bind(item.po_line_id)
        .bind(po_line.product_id)
        .bind(item.quantity)
        .bind(item.lot_number.as_deref().map(str::trim))
        .execute(&mut *conn)
        .await?;

        // Update quantity_received on po_line
        let updated = sqlx::query(
            "UPDATE purchasing.purchase_order_lines
             SET quantity_received = quantity_received + $2
             WHERE id = $1 AND quantity_received + $2 <= quantity",
        )
        .bind(item.po_line_id)
        .bind(item.quantity)
        .execute(&mut *conn)
        .await?
        .rows_affected();
        if updated == 0 {
            return Err(AppError::Validation(format!(
                "cannot receive {} units for product {}: exceeds the quantity remaining",
                item.quantity, po_line.product_code
            )));
        }

        let lot_id = match (tracking.as_str(), item.lot_number.as_deref()) {
            ("lot", Some(num)) => Some(
                ledger::get_or_create_lot(
                    &mut *conn,
                    user.company_id,
                    po_line.product_id,
                    num,
                    None,
                )
                .await?,
            ),
            ("lot", None) => {
                return Err(AppError::Validation(format!(
                    "product {} requires a lot number",
                    po_line.product_code
                )));
            }
            _ => None,
        };

        if tracking == "serial" {
            let serials_list = item.serial_numbers.unwrap_or_default();
            // Quantity for serial products must be an integer
            let count = item
                .quantity
                .normalize()
                .to_string()
                .parse::<usize>()
                .map_err(|_| {
                    AppError::Validation("serial-tracked quantity must be a whole number".into())
                })?;
            if serials_list.len() != count {
                return Err(AppError::Validation(format!(
                    "expected {} serial numbers for product {}, but got {}",
                    count,
                    po_line.product_code,
                    serials_list.len()
                )));
            }

            for serial_num in serials_list {
                let note = format!("Received on GR {}", gr_number);
                let unit_id = serials::register_unit(
                    &mut *conn,
                    user,
                    po_line.product_id,
                    &serial_num,
                    None,
                    None,
                    &note,
                )
                .await?;

                let mut m = NewMove::new(
                    new_id(),
                    user,
                    po_line.product_id,
                    Decimal::ONE,
                    vendor_location,
                    input.location_id,
                    "receipt",
                    "purchase_receipt",
                );
                m.reference = Some(("goods_receipt".into(), gr_id));
                m.unit_cost = Some(po_line.unit_price);
                m.currency = Some(po.summary.currency.clone());
                m.serial_unit_id = Some(unit_id);
                ledger::post_move(&mut *conn, &m).await?;
            }
        } else {
            let mut m = NewMove::new(
                new_id(),
                user,
                po_line.product_id,
                item.quantity,
                vendor_location,
                input.location_id,
                "receipt",
                "purchase_receipt",
            );
            m.reference = Some(("goods_receipt".into(), gr_id));
            m.unit_cost = Some(po_line.unit_price);
            m.currency = Some(po.summary.currency.clone());
            m.lot_id = lot_id;
            ledger::post_move(&mut *conn, &m).await?;
        }
    }

    // 6. Check if PO is now fully received
    let any_remaining: bool = sqlx::query_scalar(
        "SELECT EXISTS (
            SELECT 1 FROM purchasing.purchase_order_lines
            WHERE purchase_order_id = $1 AND quantity_received < quantity
         )",
    )
    .bind(po_id)
    .fetch_one(&mut *conn)
    .await?;

    let new_po_status = if any_remaining {
        "partially_received"
    } else {
        "received"
    };

    sqlx::query(
        "UPDATE purchasing.purchase_orders
         SET status = $2, updated_at = now()
         WHERE id = $1",
    )
    .bind(po_id)
    .bind(new_po_status)
    .execute(&mut *conn)
    .await?;

    audit::record(
        conn,
        user,
        "goods_receipt",
        gr_id,
        "received",
        serde_json::json!({
            "number": gr_number,
            "po_number": po.summary.number,
            "po_status": new_po_status,
        }),
    )
    .await?;

    load(conn, user.company_id, gr_id).await
}

/// Total quantity received per purchase order line, summed over the goods receipt lines of the
/// order (ADR 0046: the "received" side of the three-way match). Lines without a receipt are
/// absent from the result.
pub async fn received_quantities(
    conn: &mut PgConnection,
    company_id: Uuid,
    po_id: Uuid,
) -> AppResult<Vec<(Uuid, rust_decimal::Decimal)>> {
    sqlx::query_as::<_, (Uuid, rust_decimal::Decimal)>(
        "SELECT grl.po_line_id, SUM(grl.quantity_received)
         FROM purchasing.goods_receipt_lines grl
         JOIN purchasing.goods_receipts gr ON gr.id = grl.goods_receipt_id
         WHERE gr.company_id = $1 AND gr.purchase_order_id = $2
         GROUP BY grl.po_line_id",
    )
    .bind(company_id)
    .bind(po_id)
    .fetch_all(conn)
    .await
    .map_err(Into::into)
}
