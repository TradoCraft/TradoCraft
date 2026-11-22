use crate::suppliers::normalize_currency;
use chrono::{DateTime, Utc};
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection};
use tradocraft_core::{audit, new_id, AppError, AppResult, CurrentUser};
use utoipa::ToSchema;
use uuid::Uuid;

/// A supplier price list entry for a product.
#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct SupplierProduct {
    pub id: Uuid,
    pub company_id: Uuid,
    pub supplier_id: Uuid,
    pub supplier_name: String,
    pub product_id: Uuid,
    pub product_code: String,
    pub product_name: String,
    pub supplier_product_code: String,
    pub supplier_product_name: String,
    pub currency: String,
    #[schema(value_type = String)]
    pub unit_price: Decimal,
    #[schema(value_type = String)]
    pub moq: Decimal,
    pub lead_time_days: i32,
    pub is_preferred: bool,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// Payload to create or replace a supplier price list entry.
#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct SetSupplierProductInput {
    pub supplier_product_code: Option<String>,
    pub supplier_product_name: Option<String>,
    pub currency: Option<String>,
    #[schema(value_type = String)]
    pub unit_price: Decimal,
    #[schema(value_type = Option<String>)]
    pub moq: Option<Decimal>,
    pub lead_time_days: Option<i32>,
    pub is_preferred: Option<bool>,
}

const SELECT_QUERY: &str = r#"
    SELECT sp.id, sp.company_id, sp.supplier_id, s.name AS supplier_name,
           sp.product_id, p.code AS product_code, p.name AS product_name,
           sp.supplier_product_code, sp.supplier_product_name, sp.currency,
           sp.unit_price, sp.moq, sp.lead_time_days, sp.is_preferred,
           sp.created_at, sp.updated_at
    FROM purchasing.supplier_products sp
    JOIN purchasing.suppliers s ON s.id = sp.supplier_id
    JOIN products.products p ON p.id = sp.product_id
"#;

/// Creates or updates a supplier price list entry, keeping at most one preferred supplier per product.
pub async fn set_supplier_product(
    conn: &mut PgConnection,
    user: &CurrentUser,
    supplier_id: Uuid,
    product_id: Uuid,
    input: SetSupplierProductInput,
) -> AppResult<SupplierProduct> {
    if input.unit_price < Decimal::ZERO {
        return Err(AppError::Validation("unit price cannot be negative".into()));
    }
    let moq = input.moq.unwrap_or(Decimal::ONE);
    if moq <= Decimal::ZERO {
        return Err(AppError::Validation("moq must be greater than zero".into()));
    }
    let lead_time_days = input.lead_time_days.unwrap_or(0);
    if lead_time_days < 0 {
        return Err(AppError::Validation(
            "lead time days cannot be negative".into(),
        ));
    }
    let currency = normalize_currency(input.currency.as_deref().unwrap_or("EUR"))?;
    let supplier_product_code = input
        .supplier_product_code
        .unwrap_or_default()
        .trim()
        .to_string();
    let supplier_product_name = input
        .supplier_product_name
        .unwrap_or_default()
        .trim()
        .to_string();
    let is_preferred = input.is_preferred.unwrap_or(false);

    // Verify supplier belongs to company
    let supplier_exists: bool = sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM purchasing.suppliers WHERE company_id = $1 AND id = $2)",
    )
    .bind(user.company_id)
    .bind(supplier_id)
    .fetch_one(&mut *conn)
    .await?;

    if !supplier_exists {
        return Err(AppError::NotFound("supplier"));
    }

    // Verify product exists
    let product_exists: bool =
        sqlx::query_scalar("SELECT EXISTS (SELECT 1 FROM products.products WHERE id = $1)")
            .bind(product_id)
            .fetch_one(&mut *conn)
            .await?;

    if !product_exists {
        return Err(AppError::NotFound("product"));
    }

    let id = new_id();

    // Serialize concurrent preferred changes for this product
    sqlx::query("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))")
        .bind(format!("{}{}", user.company_id, product_id))
        .execute(&mut *conn)
        .await?;

    // If setting as preferred, unset previous preferred supplier for this product in company
    if is_preferred {
        sqlx::query(
            "UPDATE purchasing.supplier_products
             SET is_preferred = false, updated_at = now()
             WHERE company_id = $1 AND product_id = $2 AND is_preferred = true",
        )
        .bind(user.company_id)
        .bind(product_id)
        .execute(&mut *conn)
        .await?;
    }

    let item_id: Uuid = sqlx::query_scalar(
        "INSERT INTO purchasing.supplier_products (
            id, company_id, supplier_id, product_id, supplier_product_code, supplier_product_name,
            currency, unit_price, moq, lead_time_days, is_preferred, created_at, updated_at
         )
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, now(), now())
         ON CONFLICT (company_id, supplier_id, product_id)
         DO UPDATE SET
            supplier_product_code = EXCLUDED.supplier_product_code,
            supplier_product_name = EXCLUDED.supplier_product_name,
            currency = EXCLUDED.currency,
            unit_price = EXCLUDED.unit_price,
            moq = EXCLUDED.moq,
            lead_time_days = EXCLUDED.lead_time_days,
            is_preferred = EXCLUDED.is_preferred,
            updated_at = now()
         RETURNING id",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(supplier_id)
    .bind(product_id)
    .bind(&supplier_product_code)
    .bind(&supplier_product_name)
    .bind(&currency)
    .bind(input.unit_price)
    .bind(moq)
    .bind(lead_time_days)
    .bind(is_preferred)
    .fetch_one(&mut *conn)
    .await?;

    audit::record(
        conn,
        user,
        "supplier_product",
        item_id,
        "set",
        serde_json::json!({
            "supplier_id": supplier_id,
            "product_id": product_id,
            "unit_price": input.unit_price.to_string(),
        }),
    )
    .await?;

    let sp = sqlx::query_as::<_, SupplierProduct>(sqlx::AssertSqlSafe(format!("{SELECT_QUERY} WHERE sp.id = $1")))
        .bind(item_id)
        .fetch_one(conn)
        .await?;

    Ok(sp)
}

/// Removes a supplier price list entry and records an audit event.
pub async fn delete_supplier_product(
    conn: &mut PgConnection,
    user: &CurrentUser,
    supplier_id: Uuid,
    product_id: Uuid,
) -> AppResult<()> {
    sqlx::query("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))")
        .bind(format!("{}{}", user.company_id, product_id))
        .execute(&mut *conn)
        .await?;

    let item_id: Uuid = sqlx::query_scalar(
        "DELETE FROM purchasing.supplier_products
         WHERE company_id = $1 AND supplier_id = $2 AND product_id = $3
         RETURNING id",
    )
    .bind(user.company_id)
    .bind(supplier_id)
    .bind(product_id)
    .fetch_optional(&mut *conn)
    .await?
    .ok_or(AppError::NotFound("supplier_product"))?;

    audit::record(
        conn,
        user,
        "supplier_product",
        item_id,
        "deleted",
        serde_json::json!({ "supplier_id": supplier_id, "product_id": product_id }),
    )
    .await?;

    Ok(())
}

/// Lists the price list entries of a supplier.
pub async fn list_for_supplier(
    conn: &mut PgConnection,
    company_id: Uuid,
    supplier_id: Uuid,
) -> AppResult<Vec<SupplierProduct>> {
    sqlx::query_as::<_, SupplierProduct>(sqlx::AssertSqlSafe(format!(
        "{SELECT_QUERY} WHERE sp.company_id = $1 AND sp.supplier_id = $2 ORDER BY p.code ASC"
    )))
    .bind(company_id)
    .bind(supplier_id)
    .fetch_all(conn)
    .await
    .map_err(Into::into)
}

/// Lists the suppliers offering a product, preferred first then cheapest.
pub async fn list_for_product(
    conn: &mut PgConnection,
    company_id: Uuid,
    product_id: Uuid,
) -> AppResult<Vec<SupplierProduct>> {
    sqlx::query_as::<_, SupplierProduct>(sqlx::AssertSqlSafe(format!(
        "{SELECT_QUERY} WHERE sp.company_id = $1 AND sp.product_id = $2 ORDER BY sp.is_preferred DESC, sp.unit_price ASC"
    )))
    .bind(company_id)
    .bind(product_id)
    .fetch_all(conn)
    .await
    .map_err(Into::into)
}

/// Returns the preferred supplier entry for a product, if any.
pub async fn get_preferred_supplier_for_product(
    conn: &mut PgConnection,
    company_id: Uuid,
    product_id: Uuid,
) -> AppResult<Option<SupplierProduct>> {
    sqlx::query_as::<_, SupplierProduct>(sqlx::AssertSqlSafe(format!(
        "{SELECT_QUERY} WHERE sp.company_id = $1 AND sp.product_id = $2 AND sp.is_preferred = true LIMIT 1"
    )))
    .bind(company_id)
    .bind(product_id)
    .fetch_optional(conn)
    .await
    .map_err(Into::into)
}
