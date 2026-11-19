//! Bulk price changes: e.g. "+4 % on family PUMPS in all zones from 1 January".
//! Always previewed first; applying adds new dated prices and never edits existing ones.

use axum::extract::State;
use axum::Json;
use chrono::NaiveDate;
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection};
use tradocraft_core::{audit, new_id, AppError, AppResult, AppState, CurrentUser, Permission};
use tradocraft_pricing::{change_price, PriceChange};
use utoipa::ToSchema;
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

type ErrorBody = tradocraft_core::error::ErrorBody;

#[derive(Debug, Clone, Copy, Deserialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum ChangeKind {
    /// Percentage, e.g. 4.5 = +4.5 %, -2 = -2 %.
    Percent,
    /// Amount added to the unit price (may be negative).
    Amount,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct BulkPriceChangeInput {
    /// Zones to change; empty = all zones of the active company.
    #[serde(default)]
    pub zone_ids: Vec<Uuid>,
    /// Limit to one product family.
    pub family_id: Option<Uuid>,
    /// Limit to these products (combined with the family filter, if any).
    #[serde(default)]
    pub product_ids: Vec<Uuid>,
    pub kind: ChangeKind,
    #[schema(value_type = String, example = "4.5")]
    pub value: Decimal,
    /// Round new prices to a multiple of this step, e.g. 0.01, 0.05 or 1. Default 0.01.
    #[schema(value_type = Option<String>, example = "0.05")]
    pub rounding: Option<Decimal>,
    /// First day of the new prices; today or later.
    #[serde(deserialize_with = "tradocraft_core::serde_util::date")]
    pub valid_from: NaiveDate,
    /// Replace prices that are already planned to start on `valid_from` (only when that is after
    /// today) instead of refusing them. The change is then computed from the price before them.
    #[serde(default)]
    pub replace_planned: bool,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct BulkPriceLine {
    pub product_id: Uuid,
    pub product_code: String,
    pub product_name: String,
    pub zone_id: Uuid,
    pub zone_code: String,
    /// Price valid on `valid_from` before the change.
    #[schema(value_type = String)]
    pub current_price: Decimal,
    pub current_valid_from: NaiveDate,
    #[schema(value_type = String)]
    pub new_price: Decimal,
    /// A price starting on exactly `valid_from` already exists.
    pub conflict: bool,
    /// That price, when it is replaced (`replace_planned`).
    #[schema(value_type = Option<String>, required = false)]
    pub replaced_price: Option<Decimal>,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct BulkPricePreview {
    pub valid_from: NaiveDate,
    pub lines: Vec<BulkPriceLine>,
    /// Product/zone combinations without any price to start from (left unchanged).
    pub without_price: i64,
    pub conflicts: i64,
    /// Number of prices created (0 for a preview).
    pub applied: i64,
}

#[derive(FromRow)]
struct Row {
    product_id: Uuid,
    product_code: String,
    product_name: String,
    zone_id: Uuid,
    zone_code: String,
    current_price: Option<Decimal>,
    current_valid_from: Option<NaiveDate>,
    planned_price: Option<Decimal>,
}

async fn compute(
    conn: &mut PgConnection,
    user: &CurrentUser,
    input: &BulkPriceChangeInput,
) -> AppResult<BulkPricePreview> {
    let step = input.rounding.unwrap_or(Decimal::new(1, 2));
    if step <= Decimal::ZERO || step > Decimal::ONE_HUNDRED {
        return Err(AppError::Validation(
            "rounding must be between 0 and 100".into(),
        ));
    }
    if input.value.is_zero() {
        return Err(AppError::Validation("the change is zero".into()));
    }
    if input.replace_planned && input.valid_from <= tradocraft_core::today() {
        return Err(AppError::Validation(
            "only prices starting after today can be replaced; prices in effect stay unchanged"
                .into(),
        ));
    }
    if input.valid_from < tradocraft_core::today() {
        return Err(AppError::Validation(
            "valid_from cannot be in the past: earlier prices are history and stay unchanged"
                .into(),
        ));
    }
    let rows: Vec<Row> = sqlx::query_as(
        "SELECT p.id AS product_id, p.code AS product_code, p.name AS product_name, z.id AS zone_id,
                z.code AS zone_code, cur.unit_price AS current_price, cur.valid_from AS current_valid_from,
                planned.unit_price AS planned_price
         FROM products.products p
         CROSS JOIN pricing.price_zones z
         LEFT JOIN LATERAL (
             SELECT unit_price, valid_from FROM pricing.zone_prices zp
             WHERE zp.zone_id = z.id AND zp.product_id = p.id
               AND (zp.valid_from < $4 OR (NOT $6 AND zp.valid_from = $4))
             ORDER BY zp.valid_from DESC LIMIT 1
         ) cur ON true
         LEFT JOIN pricing.zone_prices planned
             ON planned.zone_id = z.id AND planned.product_id = p.id AND planned.valid_from = $4
         WHERE z.company_id = $1 AND p.active
           AND (cardinality($2::uuid[]) = 0 OR z.id = ANY($2))
           AND ($3::uuid IS NULL OR p.family_id = $3)
           AND (cardinality($5::uuid[]) = 0 OR p.id = ANY($5))
         ORDER BY p.code, z.sort_order",
    )
    .bind(user.company_id)
    .bind(&input.zone_ids)
    .bind(input.family_id)
    .bind(input.valid_from)
    .bind(&input.product_ids)
    .bind(input.replace_planned)
    .fetch_all(&mut *conn)
    .await?;

    let change = match input.kind {
        ChangeKind::Percent => PriceChange::Percent(input.value),
        ChangeKind::Amount => PriceChange::Amount(input.value),
    };
    let mut lines = Vec::new();
    let mut without_price = 0;
    for r in rows {
        let (Some(current), Some(from)) = (r.current_price, r.current_valid_from) else {
            without_price += 1;
            continue;
        };
        let new_price = change_price(current, change, step).map_err(|_| {
            AppError::Validation(format!(
                "{} in zone {} would get a negative price",
                r.product_code, r.zone_code
            ))
        })?;
        lines.push(BulkPriceLine {
            product_id: r.product_id,
            product_code: r.product_code,
            product_name: r.product_name,
            zone_id: r.zone_id,
            zone_code: r.zone_code,
            current_price: current,
            current_valid_from: from,
            new_price,
            conflict: r.planned_price.is_some(),
            replaced_price: r.planned_price.filter(|_| input.replace_planned),
        });
    }
    // Replaced prices are not conflicts: they are what the change is meant to correct.
    let conflicts = lines
        .iter()
        .filter(|l| l.conflict && l.replaced_price.is_none())
        .count() as i64;
    Ok(BulkPricePreview {
        valid_from: input.valid_from,
        lines,
        without_price,
        conflicts,
        applied: 0,
    })
}

/// Shows what a bulk price change would do, without changing anything.
#[utoipa::path(post, path = "/prices/bulk/preview", tag = "products", request_body = BulkPriceChangeInput,
    responses((status = 200, body = BulkPricePreview), (status = 422, body = ErrorBody)))]
async fn preview_bulk(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<BulkPriceChangeInput>,
) -> AppResult<Json<BulkPricePreview>> {
    user.require(Permission::PricesWrite)?;
    let mut conn = state.db.acquire().await?;
    Ok(Json(compute(&mut conn, &user, &input).await?))
}

/// Applies a bulk price change: one new dated price per product and zone.
/// Refused if any product already has a price starting on the same date, unless
/// `replace_planned` is set and that date is after today.
#[utoipa::path(post, path = "/prices/bulk/apply", tag = "products", request_body = BulkPriceChangeInput,
    responses((status = 200, body = BulkPricePreview), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn apply_bulk(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<BulkPriceChangeInput>,
) -> AppResult<Json<BulkPricePreview>> {
    user.require(Permission::PricesWrite)?;
    let mut tx = state.db.begin().await?;
    // One bulk change at a time, so the preview conditions hold while applying.
    sqlx::query("SELECT pg_advisory_xact_lock(hashtext('pricing.bulk_change'))")
        .execute(&mut *tx)
        .await?;
    let mut preview = compute(&mut tx, &user, &input).await?;
    if preview.conflicts > 0 {
        return Err(AppError::Conflict(format!(
            "{} prices already start on {}; replace them, change those individually or pick another date",
            preview.conflicts, input.valid_from
        )));
    }
    if preview.lines.is_empty() {
        return Err(AppError::Validation(
            "no prices match this selection".into(),
        ));
    }
    for l in &preview.lines {
        if l.replaced_price.is_some() {
            sqlx::query(
                "DELETE FROM pricing.zone_prices WHERE zone_id = $1 AND product_id = $2 AND valid_from = $3",
            )
            .bind(l.zone_id)
            .bind(l.product_id)
            .bind(input.valid_from)
            .execute(&mut *tx)
            .await?;
        }
        sqlx::query(
            "INSERT INTO pricing.zone_prices (id, company_id, zone_id, product_id, unit_price, valid_from, created_by)
             VALUES ($1, $2, $3, $4, $5, $6, $7)",
        )
        .bind(new_id())
        .bind(user.company_id)
        .bind(l.zone_id)
        .bind(l.product_id)
        .bind(l.new_price)
        .bind(input.valid_from)
        .bind(user.user_id)
        .execute(&mut *tx)
        .await?;
    }
    preview.applied = preview.lines.len() as i64;
    audit::record(
        &mut tx,
        &user,
        "price_change",
        new_id(),
        "bulk_applied",
        serde_json::json!({
            "valid_from": input.valid_from,
            "kind": format!("{:?}", input.kind),
            "value": input.value,
            "family_id": input.family_id,
            "zones": input.zone_ids,
            "products": input.product_ids,
            "prices": preview.applied,
            "replaced": preview.lines.iter().filter(|l| l.replaced_price.is_some()).count(),
        }),
    )
    .await?;
    tx.commit().await?;
    Ok(Json(preview))
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(preview_bulk))
        .routes(routes!(apply_bulk))
}
