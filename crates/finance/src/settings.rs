//! Per-company match tolerances (ADR 0046).

use crate::matching::Tolerance;
use chrono::{DateTime, Utc};
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection};
use tradocraft_core::{audit, AppError, AppResult, CurrentUser};
use utoipa::ToSchema;
use uuid::Uuid;

/// The company's finance settings.
#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct FinanceSettings {
    /// Extra quantity (percent of the ordered quantity) that may be invoiced.
    #[schema(value_type = String)]
    pub quantity_tolerance_pct: Decimal,
    /// Price difference (percent of the order price) that is still a match.
    #[schema(value_type = String)]
    pub price_tolerance_pct: Decimal,
    /// When the settings were last saved; `None` while the defaults apply.
    pub updated_at: Option<DateTime<Utc>>,
}

/// Payload to change the settings; omitted fields keep their value.
#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct UpdateFinanceSettingsInput {
    /// New quantity tolerance in percent (0 to 100).
    #[schema(value_type = Option<String>)]
    pub quantity_tolerance_pct: Option<Decimal>,
    /// New price tolerance in percent (0 to 100).
    #[schema(value_type = Option<String>)]
    pub price_tolerance_pct: Option<Decimal>,
}

/// Loads the settings; a company that never saved any gets the defaults (0 % and 2 %).
pub async fn load(conn: &mut PgConnection, company_id: Uuid) -> AppResult<FinanceSettings> {
    let row = sqlx::query_as::<_, FinanceSettings>(
        "SELECT quantity_tolerance_pct, price_tolerance_pct, updated_at
         FROM finance.settings WHERE company_id = $1",
    )
    .bind(company_id)
    .fetch_optional(conn)
    .await?;
    Ok(row.unwrap_or(FinanceSettings {
        quantity_tolerance_pct: Decimal::ZERO,
        price_tolerance_pct: Decimal::from(2),
        updated_at: None,
    }))
}

/// The settings as the match function wants them.
pub async fn tolerance(conn: &mut PgConnection, company_id: Uuid) -> AppResult<Tolerance> {
    let s = load(conn, company_id).await?;
    Ok(Tolerance {
        quantity_pct: s.quantity_tolerance_pct,
        price_pct: s.price_tolerance_pct,
    })
}

/// Saves the tolerances (audited).
pub async fn update(
    conn: &mut PgConnection,
    user: &CurrentUser,
    input: UpdateFinanceSettingsInput,
) -> AppResult<FinanceSettings> {
    for (name, v) in [
        ("quantity tolerance", input.quantity_tolerance_pct),
        ("price tolerance", input.price_tolerance_pct),
    ] {
        if let Some(v) = v {
            if v < Decimal::ZERO || v > Decimal::from(100) || v.scale() > 4 {
                return Err(AppError::Validation(format!(
                    "{name} must be between 0 and 100 percent with at most 4 decimals"
                )));
            }
        }
    }
    // Each column is applied against the row as it is now: an absent input keeps the stored
    // value (the defaults on a first write), whatever a concurrent update did meanwhile.
    sqlx::query(
        "INSERT INTO finance.settings (company_id, quantity_tolerance_pct, price_tolerance_pct,
                                       updated_by_user_id, updated_at)
         VALUES ($1, COALESCE($2, 0), COALESCE($3, 2), $4, now())
         ON CONFLICT (company_id) DO UPDATE
         SET quantity_tolerance_pct = COALESCE($2, finance.settings.quantity_tolerance_pct),
             price_tolerance_pct = COALESCE($3, finance.settings.price_tolerance_pct),
             updated_by_user_id = $4, updated_at = now()",
    )
    .bind(user.company_id)
    .bind(input.quantity_tolerance_pct)
    .bind(input.price_tolerance_pct)
    .bind(user.user_id)
    .execute(&mut *conn)
    .await?;
    let saved = load(conn, user.company_id).await?;
    audit::record(
        conn,
        user,
        "finance_settings",
        user.company_id,
        "updated",
        serde_json::json!({
            "quantity_tolerance_pct": saved.quantity_tolerance_pct.to_string(),
            "price_tolerance_pct": saved.price_tolerance_pct.to_string(),
        }),
    )
    .await?;
    Ok(saved)
}
