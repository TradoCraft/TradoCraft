//! Customer rebates for a specific product or product family. The general rebate for all
//! products is the customer's `discount_percent` in their commercial terms.
//! For a product the most specific valid rule wins (see `tradocraft_pricing::resolve_rebate`).

use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::Json;
use chrono::{DateTime, Datelike, NaiveDate, Utc};
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection, PgExecutor};
use tradocraft_core::{audit, new_id, AppError, AppResult, AppState, CurrentUser, Permission};
use tradocraft_pricing::{RebateRule, RebateScope};
use utoipa::ToSchema;
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

type ErrorBody = tradocraft_core::error::ErrorBody;

/// A finance-approved general rebate applies to new pricing in its earned calendar year.
pub async fn approved_general_rate<'e>(
    db: impl PgExecutor<'e>,
    company_id: Uuid,
    customer_id: Uuid,
    price_date: NaiveDate,
) -> AppResult<Option<Decimal>> {
    Ok(sqlx::query_scalar(
        "SELECT rate FROM finance.customer_rebate_rates
         WHERE company_id = $1 AND customer_id = $2 AND rate_year = $3",
    )
    .bind(company_id)
    .bind(customer_id)
    .bind(price_date.year())
    .fetch_optional(db)
    .await?)
}

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct CustomerRebate {
    pub id: Uuid,
    pub customer_id: Uuid,
    /// product | family
    pub scope: String,
    pub product_id: Option<Uuid>,
    pub product_code: Option<String>,
    pub family_id: Option<Uuid>,
    pub family_code: Option<String>,
    #[schema(value_type = String, example = "12.5")]
    pub percent: Decimal,
    pub valid_from: Option<NaiveDate>,
    pub valid_to: Option<NaiveDate>,
    pub notes: String,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct RebateInput {
    /// product | family
    pub scope: String,
    pub product_id: Option<Uuid>,
    pub family_id: Option<Uuid>,
    #[schema(value_type = String, example = "12.5")]
    pub percent: Decimal,
    #[serde(default, deserialize_with = "tradocraft_core::serde_util::opt_date")]
    pub valid_from: Option<NaiveDate>,
    #[serde(default, deserialize_with = "tradocraft_core::serde_util::opt_date")]
    pub valid_to: Option<NaiveDate>,
    #[serde(default)]
    pub notes: String,
}

impl RebateInput {
    fn validate(&self) -> AppResult<()> {
        match (self.scope.as_str(), self.product_id, self.family_id) {
            ("product", Some(_), None) | ("family", None, Some(_)) => {}
            ("product", ..) => {
                return Err(AppError::Validation(
                    "a product rebate needs product_id only".into(),
                ))
            }
            ("family", ..) => {
                return Err(AppError::Validation(
                    "a family rebate needs family_id only".into(),
                ))
            }
            _ => {
                return Err(AppError::Validation(
                    "scope must be product or family".into(),
                ))
            }
        }
        if self.percent < -Decimal::ONE_HUNDRED || self.percent > Decimal::ONE_HUNDRED {
            return Err(AppError::Validation(
                "percent must be between -100 and 100".into(),
            ));
        }
        if let (Some(f), Some(t)) = (self.valid_from, self.valid_to) {
            if t < f {
                return Err(AppError::Validation("valid_to is before valid_from".into()));
            }
        }
        Ok(())
    }
}

const SELECT: &str =
    "SELECT r.id, r.customer_id, r.scope, r.product_id, p.code AS product_code, r.family_id,
        f.code AS family_code, r.percent, r.valid_from, r.valid_to, r.notes, r.created_at
     FROM crm.customer_rebates r
     LEFT JOIN products.products p ON p.id = r.product_id
     LEFT JOIN products.product_families f ON f.id = r.family_id";

/// Rebate rules of a customer in a company, for the pricing engine.
pub async fn rebate_rules<'e>(
    db: impl PgExecutor<'e>,
    company_id: Uuid,
    customer_id: Uuid,
) -> AppResult<Vec<RebateRule>> {
    #[derive(FromRow)]
    struct RuleRow {
        scope: String,
        product_id: Option<Uuid>,
        family_id: Option<Uuid>,
        percent: Decimal,
        valid_from: Option<NaiveDate>,
        valid_to: Option<NaiveDate>,
    }
    let rows: Vec<RuleRow> = sqlx::query_as(
        "SELECT scope, product_id, family_id, percent, valid_from, valid_to
         FROM crm.customer_rebates WHERE company_id = $1 AND customer_id = $2",
    )
    .bind(company_id)
    .bind(customer_id)
    .fetch_all(db)
    .await?;
    Ok(rows
        .into_iter()
        .filter_map(|r| {
            let scope = match (r.scope.as_str(), r.product_id, r.family_id) {
                ("product", Some(p), _) => RebateScope::Product(p),
                ("family", _, Some(f)) => RebateScope::Family(f),
                _ => return None,
            };
            Some(RebateRule {
                scope,
                percent: r.percent,
                valid_from: r.valid_from,
                valid_to: r.valid_to,
            })
        })
        .collect())
}

async fn check_overlap(
    conn: &mut PgConnection,
    company_id: Uuid,
    customer_id: Uuid,
    input: &RebateInput,
    except: Option<Uuid>,
) -> AppResult<()> {
    let overlapping: bool = sqlx::query_scalar(
        "SELECT EXISTS (
             SELECT 1 FROM crm.customer_rebates
             WHERE company_id = $1 AND customer_id = $2 AND scope = $3
               AND product_id IS NOT DISTINCT FROM $4 AND family_id IS NOT DISTINCT FROM $5
               AND ($8::uuid IS NULL OR id <> $8)
               AND daterange(coalesce(valid_from, '-infinity'), coalesce(valid_to, 'infinity'), '[]')
                && daterange(coalesce($6::date, '-infinity'), coalesce($7::date, 'infinity'), '[]'))",
    )
    .bind(company_id)
    .bind(customer_id)
    .bind(&input.scope)
    .bind(input.product_id)
    .bind(input.family_id)
    .bind(input.valid_from)
    .bind(input.valid_to)
    .bind(except)
    .fetch_one(conn)
    .await?;
    if overlapping {
        Err(AppError::Conflict(
            "another rebate for the same product or family overlaps these dates; end it first"
                .into(),
        ))
    } else {
        Ok(())
    }
}

#[utoipa::path(get, path = "/customers/{id}/rebates", tag = "crm", params(("id" = Uuid, Path)),
    responses((status = 200, body = Vec<CustomerRebate>)))]
async fn list_rebates(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(customer_id): Path<Uuid>,
) -> AppResult<Json<Vec<CustomerRebate>>> {
    user.require(Permission::CustomersRead)?;
    Ok(Json(
        sqlx::query_as(&format!(
            "{SELECT} WHERE r.company_id = $1 AND r.customer_id = $2
             ORDER BY r.scope, coalesce(p.code, f.code), r.valid_from NULLS FIRST"
        ))
        .bind(user.company_id)
        .bind(customer_id)
        .fetch_all(&state.db)
        .await?,
    ))
}

#[utoipa::path(post, path = "/customers/{id}/rebates", tag = "crm", params(("id" = Uuid, Path)),
    request_body = RebateInput,
    responses((status = 201, body = CustomerRebate), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn create_rebate(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(customer_id): Path<Uuid>,
    Json(input): Json<RebateInput>,
) -> AppResult<(StatusCode, Json<CustomerRebate>)> {
    user.require(Permission::RebatesWrite)?;
    input.validate()?;
    let mut tx = state.db.begin().await?;
    check_overlap(&mut tx, user.company_id, customer_id, &input, None).await?;
    let id = new_id();
    sqlx::query(
        "INSERT INTO crm.customer_rebates (id, company_id, customer_id, scope, product_id, family_id, percent,
                                           valid_from, valid_to, notes, created_by)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(customer_id)
    .bind(&input.scope)
    .bind(input.product_id)
    .bind(input.family_id)
    .bind(input.percent)
    .bind(input.valid_from)
    .bind(input.valid_to)
    .bind(&input.notes)
    .bind(user.user_id)
    .execute(&mut *tx)
    .await?;
    audit::record(&mut tx, &user, "customer", customer_id, "rebate_created", serde_json::json!({
        "rebate_id": id, "scope": input.scope, "product_id": input.product_id, "family_id": input.family_id,
        "percent": input.percent, "valid_from": input.valid_from, "valid_to": input.valid_to,
    }))
    .await?;
    let r = sqlx::query_as(&format!("{SELECT} WHERE r.id = $1"))
        .bind(id)
        .fetch_one(&mut *tx)
        .await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(r)))
}

#[utoipa::path(put, path = "/customers/{id}/rebates/{rebate_id}", tag = "crm",
    params(("id" = Uuid, Path), ("rebate_id" = Uuid, Path)), request_body = RebateInput,
    responses((status = 200, body = CustomerRebate), (status = 409, body = ErrorBody)))]
async fn update_rebate(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((customer_id, rebate_id)): Path<(Uuid, Uuid)>,
    Json(input): Json<RebateInput>,
) -> AppResult<Json<CustomerRebate>> {
    user.require(Permission::RebatesWrite)?;
    input.validate()?;
    let mut tx = state.db.begin().await?;
    check_overlap(
        &mut tx,
        user.company_id,
        customer_id,
        &input,
        Some(rebate_id),
    )
    .await?;
    let r = sqlx::query(
        "UPDATE crm.customer_rebates SET scope = $4, product_id = $5, family_id = $6, percent = $7,
                valid_from = $8, valid_to = $9, notes = $10
         WHERE id = $1 AND company_id = $2 AND customer_id = $3",
    )
    .bind(rebate_id)
    .bind(user.company_id)
    .bind(customer_id)
    .bind(&input.scope)
    .bind(input.product_id)
    .bind(input.family_id)
    .bind(input.percent)
    .bind(input.valid_from)
    .bind(input.valid_to)
    .bind(&input.notes)
    .execute(&mut *tx)
    .await?;
    if r.rows_affected() == 0 {
        return Err(AppError::NotFound("rebate"));
    }
    audit::record(&mut tx, &user, "customer", customer_id, "rebate_updated", serde_json::json!({
        "rebate_id": rebate_id, "percent": input.percent, "valid_from": input.valid_from, "valid_to": input.valid_to,
    }))
    .await?;
    let r = sqlx::query_as(&format!("{SELECT} WHERE r.id = $1"))
        .bind(rebate_id)
        .fetch_one(&mut *tx)
        .await?;
    tx.commit().await?;
    Ok(Json(r))
}

/// Removes a rebate. Quotations keep the rebate they were priced with.
#[utoipa::path(delete, path = "/customers/{id}/rebates/{rebate_id}", tag = "crm",
    params(("id" = Uuid, Path), ("rebate_id" = Uuid, Path)),
    responses((status = 204), (status = 404, body = ErrorBody)))]
async fn delete_rebate(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((customer_id, rebate_id)): Path<(Uuid, Uuid)>,
) -> AppResult<StatusCode> {
    user.require(Permission::RebatesWrite)?;
    let mut tx = state.db.begin().await?;
    let removed: Option<CustomerRebate> = sqlx::query_as(&format!(
        "{SELECT} WHERE r.id = $1 AND r.company_id = $2 AND r.customer_id = $3"
    ))
    .bind(rebate_id)
    .bind(user.company_id)
    .bind(customer_id)
    .fetch_optional(&mut *tx)
    .await?;
    let removed = removed.ok_or(AppError::NotFound("rebate"))?;
    sqlx::query("DELETE FROM crm.customer_rebates WHERE id = $1")
        .bind(rebate_id)
        .execute(&mut *tx)
        .await?;
    audit::record(
        &mut tx,
        &user,
        "customer",
        customer_id,
        "rebate_deleted",
        serde_json::json!({
            "rebate_id": rebate_id, "scope": removed.scope, "product": removed.product_code,
            "family": removed.family_code, "percent": removed.percent,
        }),
    )
    .await?;
    tx.commit().await?;
    Ok(StatusCode::NO_CONTENT)
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(list_rebates, create_rebate))
        .routes(routes!(update_rebate, delete_rebate))
}
