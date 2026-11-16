//! Country-aware, temporally valid, and building-age-aware VAT rate lookup
//! and administration (`core.country_vat_rates`).

use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::Json;
use chrono::{DateTime, Datelike, NaiveDate, Utc};
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use serde_json::json;
use sqlx::{FromRow, PgExecutor};
use utoipa::{IntoParams, ToSchema};
use utoipa_axum::{router::OpenApiRouter, routes};
use uuid::Uuid;

use crate::auth::Permission;
use crate::{audit, new_id, AppError, AppResult, AppState, CurrentUser};

type ErrorBody = crate::error::ErrorBody;

/// VAT categories assignable to products.
pub const PRODUCT_VAT_CATEGORIES: [&str; 4] = ["standard", "intermediate", "reduced", "zero"];

/// All VAT rule categories stored in `core.country_vat_rates` (adds `construction`
/// for building-age-based renovation rates).
pub const RULE_VAT_CATEGORIES: [&str; 5] = [
    "standard",
    "intermediate",
    "reduced",
    "zero",
    "construction",
];

/// Whether `category` is one of [`PRODUCT_VAT_CATEGORIES`].
pub fn is_valid_product_vat_category(category: &str) -> bool {
    PRODUCT_VAT_CATEGORIES.contains(&category)
}

/// Whether `category` is one of [`RULE_VAT_CATEGORIES`].
pub fn is_valid_rule_vat_category(category: &str) -> bool {
    RULE_VAT_CATEGORIES.contains(&category)
}

/// A country VAT rate rule with an effective date range and optional building-age threshold.
#[derive(Debug, Clone, Serialize, Deserialize, FromRow, ToSchema)]
pub struct CountryVatRate {
    pub id: Uuid,
    pub country_code: String,
    pub category: String,
    #[schema(value_type = String, example = "21.00")]
    pub rate: Decimal,
    pub min_building_age_years: Option<i32>,
    pub start_date: NaiveDate,
    pub end_date: Option<NaiveDate>,
    pub notes: String,
    pub updated_at: DateTime<Utc>,
}

/// Request payload for creating or updating a country VAT rate rule.
#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct CountryVatRateInput {
    pub country_code: String,
    pub category: String,
    #[schema(value_type = String, example = "21.00")]
    pub rate: Decimal,
    #[serde(default)]
    pub min_building_age_years: Option<i32>,
    #[serde(default, deserialize_with = "crate::serde_util::opt_date")]
    pub start_date: Option<NaiveDate>,
    #[serde(default, deserialize_with = "crate::serde_util::opt_date")]
    pub end_date: Option<NaiveDate>,
    #[serde(default)]
    pub notes: String,
    /// When creating a new rate period, set `end_date = start_date - 1` on any
    /// earlier rule for the same `(country_code, category, min_building_age_years)`
    /// that would otherwise remain open past the new start date.
    #[serde(default)]
    pub close_previous: bool,
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct VatRateListQuery {
    pub country_code: Option<String>,
    pub category: Option<String>,
    pub as_of: Option<NaiveDate>,
}

/// Context used to resolve an effective VAT percentage from country rules.
#[derive(Debug, Clone)]
pub struct VatResolutionContext<'a> {
    pub country_code: &'a str,
    pub category: &'a str,
    pub product_override: Option<Decimal>,
    pub vat_regime: Option<&'a str>,
    pub purpose: Option<&'a str>,
    pub building_construction_year: Option<i32>,
    pub as_of: NaiveDate,
}

/// Pure VAT rate resolver operating on an in-memory slice of [`CountryVatRate`] rows.
///
/// Precedence:
/// 1. Exempt regime (`intra_eu`, `outside_eu`, `domestic_reverse_charge`) -> `0.00`
/// 2. Explicit `product_override` -> override rate
/// 3. Active category rate on `as_of` (with fallback from `intermediate`/`reduced` -> `standard`)
/// 4. If `purpose == Some("installation")`, `category != "zero"`, and `building_construction_year`
///    satisfies an active `"construction"` rule's `min_building_age_years` on `as_of`,
///    returns `min(construction_rate, base_rate)` so lower `reduced` items are preserved.
pub fn resolve_rate_from_rules(
    rules: &[CountryVatRate],
    ctx: &VatResolutionContext<'_>,
) -> Decimal {
    if ctx
        .vat_regime
        .is_some_and(crate::vat::vat_exempt_for_regime)
    {
        return Decimal::ZERO;
    }
    if let Some(rate) = ctx.product_override {
        return rate;
    }

    let country = ctx.country_code.trim().to_ascii_uppercase();
    let active: Vec<&CountryVatRate> = rules
        .iter()
        .filter(|r| {
            r.country_code.eq_ignore_ascii_case(&country)
                && r.start_date <= ctx.as_of
                && r.end_date.is_none_or(|e| ctx.as_of <= e)
        })
        .collect();

    let find_cat = |cat: &str| -> Option<Decimal> {
        active
            .iter()
            .filter(|r| r.category == cat)
            .max_by_key(|r| (r.start_date, r.updated_at))
            .map(|r| r.rate)
    };

    let base_rate = match ctx.category {
        "zero" => find_cat("zero").unwrap_or(Decimal::ZERO),
        "reduced" => find_cat("reduced")
            .or_else(|| find_cat("standard"))
            .unwrap_or(Decimal::ZERO),
        "intermediate" => find_cat("intermediate")
            .or_else(|| find_cat("standard"))
            .unwrap_or(Decimal::ZERO),
        _ => find_cat("standard").unwrap_or(Decimal::ZERO),
    };

    if ctx.purpose == Some("installation") && ctx.category != "zero" {
        if let Some(year) = ctx.building_construction_year {
            let age = (ctx.as_of.year() - year).max(0);
            if let Some(rule) = active
                .iter()
                .filter(|r| {
                    r.category == "construction"
                        && r.min_building_age_years
                            .is_some_and(|min_age| age >= min_age)
                })
                .max_by_key(|r| (r.min_building_age_years.unwrap_or(0), r.start_date))
            {
                return rule.rate.min(base_rate);
            }
        }
    }

    base_rate
}

/// Match an explicit numeric rate (for backwards-compatible product inputs/imports)
/// back to a [`PRODUCT_VAT_CATEGORIES`] entry for `(country_code, as_of)`.
pub fn infer_category_for_rate(
    rules: &[CountryVatRate],
    country_code: &str,
    rate: Decimal,
    as_of: NaiveDate,
) -> Option<&'static str> {
    let country = country_code.trim().to_ascii_uppercase();
    for cat in PRODUCT_VAT_CATEGORIES {
        let matched = rules
            .iter()
            .filter(|r| {
                r.country_code.eq_ignore_ascii_case(&country)
                    && r.category == cat
                    && r.start_date <= as_of
                    && r.end_date.is_none_or(|e| as_of <= e)
            })
            .max_by_key(|r| (r.start_date, r.updated_at))
            .is_some_and(|r| r.rate == rate);
        if matched {
            return Some(cat);
        }
    }
    None
}

/// Load all VAT rate rules for `country_code`, ordered for lookup.
pub async fn load_country_rules<'e>(
    db: impl PgExecutor<'e>,
    country_code: &str,
) -> AppResult<Vec<CountryVatRate>> {
    let country = country_code.trim().to_ascii_uppercase();
    let rows = sqlx::query_as::<_, CountryVatRate>(
        "SELECT id, country_code, category, rate, min_building_age_years,
                start_date, end_date, notes, updated_at
         FROM core.country_vat_rates
         WHERE country_code = $1
         ORDER BY category, start_date DESC, min_building_age_years DESC NULLS LAST",
    )
    .bind(country)
    .fetch_all(db)
    .await?;
    Ok(rows)
}

/// Load all VAT rate rules across all countries.
pub async fn load_all_rules<'e>(db: impl PgExecutor<'e>) -> AppResult<Vec<CountryVatRate>> {
    let rows = sqlx::query_as::<_, CountryVatRate>(
        "SELECT id, country_code, category, rate, min_building_age_years,
                start_date, end_date, notes, updated_at
         FROM core.country_vat_rates
         ORDER BY country_code, category, start_date DESC, min_building_age_years DESC NULLS LAST",
    )
    .fetch_all(db)
    .await?;
    Ok(rows)
}

/// Resolve a single effective VAT rate directly from PostgreSQL rules.
pub async fn resolve_vat_rate<'e>(
    db: impl PgExecutor<'e>,
    ctx: &VatResolutionContext<'_>,
) -> AppResult<Decimal> {
    if ctx
        .vat_regime
        .is_some_and(crate::vat::vat_exempt_for_regime)
    {
        return Ok(Decimal::ZERO);
    }
    if let Some(rate) = ctx.product_override {
        return Ok(rate);
    }
    let rules = load_country_rules(db, ctx.country_code).await?;
    Ok(resolve_rate_from_rules(&rules, ctx))
}

struct NormalizedInput {
    country_code: String,
    category: String,
    rate: Decimal,
    min_building_age_years: Option<i32>,
    start_date: NaiveDate,
    end_date: Option<NaiveDate>,
    notes: String,
    close_previous: bool,
}

fn validate_input(
    input: CountryVatRateInput,
    default_start: NaiveDate,
) -> AppResult<NormalizedInput> {
    let country_code = input.country_code.trim().to_ascii_uppercase();
    if country_code.len() != 2 || !country_code.chars().all(|c| c.is_ascii_uppercase()) {
        return Err(AppError::Validation(
            "country_code must be a 2-letter uppercase ISO code".into(),
        ));
    }
    let category = input.category.trim().to_ascii_lowercase();
    if !is_valid_rule_vat_category(&category) {
        return Err(AppError::Validation(format!(
            "category must be one of: {}",
            RULE_VAT_CATEGORIES.join(", ")
        )));
    }
    if input.rate < Decimal::ZERO || input.rate >= Decimal::from(100) {
        return Err(AppError::Validation(
            "rate must be between 0 (inclusive) and 100 (exclusive)".into(),
        ));
    }
    if category == "construction" {
        match input.min_building_age_years {
            Some(age) if (1..=200).contains(&age) => {}
            _ => {
                return Err(AppError::Validation(
                    "construction rules require min_building_age_years between 1 and 200".into(),
                ));
            }
        }
    } else if input.min_building_age_years.is_some() {
        return Err(AppError::Validation(
            "min_building_age_years is only valid for construction rules".into(),
        ));
    }
    let start_date = input.start_date.unwrap_or(default_start);
    if let Some(end_date) = input.end_date {
        if end_date < start_date {
            return Err(AppError::Validation(
                "end_date must be on or after start_date".into(),
            ));
        }
    }
    Ok(NormalizedInput {
        country_code,
        category,
        rate: input.rate,
        min_building_age_years: input.min_building_age_years,
        start_date,
        end_date: input.end_date,
        notes: input.notes.trim().to_string(),
        close_previous: input.close_previous,
    })
}

async fn has_overlapping_rule(
    conn: &mut sqlx::PgConnection,
    n: &NormalizedInput,
    exclude_id: Option<Uuid>,
) -> AppResult<bool> {
    let exists = sqlx::query_scalar::<_, bool>(
        "SELECT EXISTS(
            SELECT 1 FROM core.country_vat_rates
            WHERE country_code = $1
              AND category = $2
              AND min_building_age_years IS NOT DISTINCT FROM $3
              AND ($6::uuid IS NULL OR id <> $6)
              AND start_date <= COALESCE($5::date, 'infinity'::date)
              AND COALESCE(end_date, 'infinity'::date) >= $4::date
        )",
    )
    .bind(&n.country_code)
    .bind(&n.category)
    .bind(n.min_building_age_years)
    .bind(n.start_date)
    .bind(n.end_date)
    .bind(exclude_id)
    .fetch_one(conn)
    .await?;
    Ok(exists)
}

#[utoipa::path(
    get,
    path = "/vat-rates",
    tag = "core",
    params(VatRateListQuery),
    responses(
        (status = 200, body = [CountryVatRate]),
        (status = 401, body = ErrorBody),
    ),
    security(("bearer" = []))
)]
async fn list_vat_rates(
    State(state): State<AppState>,
    _user: CurrentUser,
    Query(q): Query<VatRateListQuery>,
) -> AppResult<Json<Vec<CountryVatRate>>> {
    let country = q
        .country_code
        .map(|s| s.trim().to_ascii_uppercase())
        .filter(|s| !s.is_empty());
    let category = q
        .category
        .map(|s| s.trim().to_ascii_lowercase())
        .filter(|s| !s.is_empty());

    let rows = sqlx::query_as::<_, CountryVatRate>(
        "SELECT id, country_code, category, rate, min_building_age_years,
                start_date, end_date, notes, updated_at
         FROM core.country_vat_rates
         WHERE ($1::text IS NULL OR country_code = $1)
           AND ($2::text IS NULL OR category = $2)
           AND ($3::date IS NULL OR (start_date <= $3 AND (end_date IS NULL OR end_date >= $3)))
         ORDER BY country_code, category, start_date DESC, min_building_age_years DESC NULLS LAST",
    )
    .bind(country)
    .bind(category)
    .bind(q.as_of)
    .fetch_all(&state.db)
    .await?;

    Ok(Json(rows))
}

// Acquire before row locks so close_previous cannot deadlock with an update.
async fn lock_country(conn: &mut sqlx::PgConnection, country: &str) -> AppResult<()> {
    sqlx::query("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))")
        .bind(format!(
            "country_vat_rates:{}",
            country.trim().to_ascii_uppercase()
        ))
        .execute(conn)
        .await?;
    Ok(())
}

#[utoipa::path(
    post,
    path = "/admin/vat-rates",
    tag = "core",
    request_body = CountryVatRateInput,
    responses(
        (status = 201, body = CountryVatRate),
        (status = 403, body = ErrorBody),
        (status = 409, body = ErrorBody),
        (status = 422, body = ErrorBody),
    ),
    security(("bearer" = []))
)]
async fn create_vat_rate(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(body): Json<CountryVatRateInput>,
) -> AppResult<(StatusCode, Json<CountryVatRate>)> {
    user.require(Permission::UsersAdmin)?;
    let n = validate_input(body, crate::today())?;

    let mut tx = state.db.begin().await?;
    lock_country(&mut tx, &n.country_code).await?;

    if n.close_previous {
        sqlx::query(
            "UPDATE core.country_vat_rates
             SET end_date = ($4::date - INTERVAL '1 day')::date,
                 updated_at = now()
             WHERE country_code = $1
               AND category = $2
               AND min_building_age_years IS NOT DISTINCT FROM $3
               AND start_date < $4::date
               AND (end_date IS NULL OR end_date >= $4::date)",
        )
        .bind(&n.country_code)
        .bind(&n.category)
        .bind(n.min_building_age_years)
        .bind(n.start_date)
        .execute(&mut *tx)
        .await?;
    }

    if has_overlapping_rule(&mut tx, &n, None).await? {
        return Err(AppError::Conflict(
            "VAT rate period overlaps an existing rule for this country and category".into(),
        ));
    }

    let id = new_id();
    let row = sqlx::query_as::<_, CountryVatRate>(
        "INSERT INTO core.country_vat_rates
             (id, country_code, category, rate, min_building_age_years, start_date, end_date, notes)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
         RETURNING id, country_code, category, rate, min_building_age_years,
                   start_date, end_date, notes, updated_at",
    )
    .bind(id)
    .bind(&n.country_code)
    .bind(&n.category)
    .bind(n.rate)
    .bind(n.min_building_age_years)
    .bind(n.start_date)
    .bind(n.end_date)
    .bind(&n.notes)
    .fetch_one(&mut *tx)
    .await?;

    audit::record(
        &mut tx,
        &user,
        "country_vat_rate",
        id,
        "create",
        json!({
            "country_code": row.country_code,
            "category": row.category,
            "rate": row.rate.to_string(),
            "start_date": row.start_date,
            "end_date": row.end_date,
        }),
    )
    .await?;

    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(row)))
}

#[utoipa::path(
    put,
    path = "/admin/vat-rates/{id}",
    tag = "core",
    params(("id" = Uuid, Path, description = "VAT rate rule id")),
    request_body = CountryVatRateInput,
    responses(
        (status = 200, body = CountryVatRate),
        (status = 403, body = ErrorBody),
        (status = 404, body = ErrorBody),
        (status = 409, body = ErrorBody),
        (status = 422, body = ErrorBody),
    ),
    security(("bearer" = []))
)]
async fn update_vat_rate(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(body): Json<CountryVatRateInput>,
) -> AppResult<Json<CountryVatRate>> {
    user.require(Permission::UsersAdmin)?;

    let mut tx = state.db.begin().await?;
    lock_country(&mut tx, &body.country_code).await?;
    let existing = sqlx::query_as::<_, CountryVatRate>(
        "SELECT id, country_code, category, rate, min_building_age_years,
                start_date, end_date, notes, updated_at
         FROM core.country_vat_rates
         WHERE id = $1
         FOR UPDATE",
    )
    .bind(id)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or(AppError::NotFound("vat rate"))?;

    let n = validate_input(body, existing.start_date)?;

    if has_overlapping_rule(&mut tx, &n, Some(id)).await? {
        return Err(AppError::Conflict(
            "VAT rate period overlaps an existing rule for this country and category".into(),
        ));
    }

    let row = sqlx::query_as::<_, CountryVatRate>(
        "UPDATE core.country_vat_rates
         SET country_code = $2,
             category = $3,
             rate = $4,
             min_building_age_years = $5,
             start_date = $6,
             end_date = $7,
             notes = $8,
             updated_at = now()
         WHERE id = $1
         RETURNING id, country_code, category, rate, min_building_age_years,
                   start_date, end_date, notes, updated_at",
    )
    .bind(id)
    .bind(&n.country_code)
    .bind(&n.category)
    .bind(n.rate)
    .bind(n.min_building_age_years)
    .bind(n.start_date)
    .bind(n.end_date)
    .bind(&n.notes)
    .fetch_one(&mut *tx)
    .await?;

    audit::record(
        &mut tx,
        &user,
        "country_vat_rate",
        id,
        "update",
        json!({
            "country_code": row.country_code,
            "category": row.category,
            "rate": row.rate.to_string(),
            "start_date": row.start_date,
            "end_date": row.end_date,
        }),
    )
    .await?;

    tx.commit().await?;
    Ok(Json(row))
}

#[utoipa::path(
    delete,
    path = "/admin/vat-rates/{id}",
    tag = "core",
    params(("id" = Uuid, Path, description = "VAT rate rule id")),
    responses(
        (status = 204),
        (status = 403, body = ErrorBody),
        (status = 404, body = ErrorBody),
    ),
    security(("bearer" = []))
)]
async fn delete_vat_rate(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<StatusCode> {
    user.require(Permission::UsersAdmin)?;

    let mut tx = state.db.begin().await?;
    let removed = sqlx::query_scalar::<_, String>(
        "DELETE FROM core.country_vat_rates WHERE id = $1 RETURNING country_code || ':' || category",
    )
    .bind(id)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or(AppError::NotFound("vat rate"))?;

    audit::record(
        &mut tx,
        &user,
        "country_vat_rate",
        id,
        "delete",
        json!({ "rule": removed }),
    )
    .await?;

    tx.commit().await?;
    Ok(StatusCode::NO_CONTENT)
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(list_vat_rates))
        .routes(routes!(create_vat_rate))
        .routes(routes!(update_vat_rate, delete_vat_rate))
}

#[cfg(test)]
mod tests {
    use super::*;
    use rust_decimal_macros::dec;

    fn d(y: i32, m: u32, day: u32) -> NaiveDate {
        NaiveDate::from_ymd_opt(y, m, day).unwrap()
    }

    fn rule(
        country: &str,
        category: &str,
        rate: Decimal,
        min_age: Option<i32>,
        start: NaiveDate,
        end: Option<NaiveDate>,
    ) -> CountryVatRate {
        CountryVatRate {
            id: Uuid::nil(),
            country_code: country.into(),
            category: category.into(),
            rate,
            min_building_age_years: min_age,
            start_date: start,
            end_date: end,
            notes: String::new(),
            updated_at: DateTime::UNIX_EPOCH,
        }
    }

    fn sample_rules() -> Vec<CountryVatRate> {
        vec![
            rule("BE", "standard", dec!(21), None, d(2000, 1, 1), None),
            rule("BE", "intermediate", dec!(12), None, d(2000, 1, 1), None),
            rule("BE", "reduced", dec!(6), None, d(2000, 1, 1), None),
            rule("BE", "zero", dec!(0), None, d(2000, 1, 1), None),
            rule(
                "BE",
                "construction",
                dec!(6),
                Some(5),
                d(2000, 1, 1),
                Some(d(2016, 2, 11)),
            ),
            rule(
                "BE",
                "construction",
                dec!(6),
                Some(10),
                d(2016, 2, 12),
                None,
            ),
            rule(
                "DE",
                "standard",
                dec!(19),
                None,
                d(2007, 1, 1),
                Some(d(2020, 6, 30)),
            ),
            rule(
                "DE",
                "standard",
                dec!(16),
                None,
                d(2020, 7, 1),
                Some(d(2020, 12, 31)),
            ),
            rule("DE", "standard", dec!(19), None, d(2021, 1, 1), None),
            rule(
                "DE",
                "reduced",
                dec!(7),
                None,
                d(2000, 1, 1),
                Some(d(2020, 6, 30)),
            ),
            rule(
                "DE",
                "reduced",
                dec!(5),
                None,
                d(2020, 7, 1),
                Some(d(2020, 12, 31)),
            ),
            rule("DE", "reduced", dec!(7), None, d(2021, 1, 1), None),
            rule("FR", "standard", dec!(20), None, d(2014, 1, 1), None),
            rule("FR", "reduced", dec!(5.5), None, d(2014, 1, 1), None),
            rule("FR", "construction", dec!(10), Some(2), d(2014, 1, 1), None),
        ]
    }

    #[test]
    fn resolves_temporal_de_covid_rates() {
        let rules = sample_rules();
        let make_ctx = |cat, as_of| VatResolutionContext {
            country_code: "DE",
            category: cat,
            product_override: None,
            vat_regime: Some("domestic"),
            purpose: None,
            building_construction_year: None,
            as_of,
        };
        assert_eq!(
            resolve_rate_from_rules(&rules, &make_ctx("standard", d(2020, 6, 30))),
            dec!(19)
        );
        assert_eq!(
            resolve_rate_from_rules(&rules, &make_ctx("standard", d(2020, 7, 15))),
            dec!(16)
        );
        assert_eq!(
            resolve_rate_from_rules(&rules, &make_ctx("reduced", d(2020, 12, 31))),
            dec!(5)
        );
        assert_eq!(
            resolve_rate_from_rules(&rules, &make_ctx("standard", d(2021, 1, 1))),
            dec!(19)
        );
        // DE has no intermediate category -> falls back to standard.
        assert_eq!(
            resolve_rate_from_rules(&rules, &make_ctx("intermediate", d(2021, 1, 1))),
            dec!(19)
        );
    }

    #[test]
    fn resolves_belgian_construction_age_thresholds_across_history() {
        let rules = sample_rules();
        // Built 2005 -> age 10 in 2015 (>= 5 rule applies), age 21 in 2026 (>= 10 rule applies).
        let ctx_old_2026 = VatResolutionContext {
            country_code: "BE",
            category: "standard",
            product_override: None,
            vat_regime: Some("domestic"),
            purpose: Some("installation"),
            building_construction_year: Some(2015),
            as_of: d(2026, 5, 1),
        };
        assert_eq!(resolve_rate_from_rules(&rules, &ctx_old_2026), dec!(6));

        // Built 2017 -> only 9 years old in 2026 -> standard 21%.
        let ctx_new_2026 = VatResolutionContext {
            building_construction_year: Some(2017),
            ..ctx_old_2026
        };
        assert_eq!(resolve_rate_from_rules(&rules, &ctx_new_2026), dec!(21));

        // Built 2010 in 2015 (6 years old): old 5-year threshold applied before 2016-02-12.
        let ctx_hist_2015 = VatResolutionContext {
            building_construction_year: Some(2010),
            as_of: d(2015, 6, 1),
            ..ctx_old_2026
        };
        assert_eq!(resolve_rate_from_rules(&rules, &ctx_hist_2015), dec!(6));

        // Supply-only never triggers construction rate even on an old building.
        let ctx_supply = VatResolutionContext {
            purpose: Some("supply_only"),
            ..ctx_old_2026
        };
        assert_eq!(resolve_rate_from_rules(&rules, &ctx_supply), dec!(21));
    }

    #[test]
    fn preserves_lower_reduced_rate_when_construction_rate_is_higher() {
        let rules = sample_rules();
        let ctx = VatResolutionContext {
            country_code: "FR",
            category: "reduced",
            product_override: None,
            vat_regime: Some("domestic"),
            purpose: Some("installation"),
            building_construction_year: Some(2010),
            as_of: d(2026, 1, 15),
        };
        assert_eq!(resolve_rate_from_rules(&rules, &ctx), dec!(5.5));
    }

    #[test]
    fn regime_exemption_beats_product_override_and_override_beats_category() {
        let rules = sample_rules();
        let ctx_override = VatResolutionContext {
            country_code: "BE",
            category: "standard",
            product_override: Some(dec!(12)),
            vat_regime: Some("domestic"),
            purpose: Some("installation"),
            building_construction_year: Some(2000),
            as_of: d(2026, 1, 1),
        };
        assert_eq!(resolve_rate_from_rules(&rules, &ctx_override), dec!(12));

        for exempt in ["intra_eu", "outside_eu", "domestic_reverse_charge"] {
            let ctx_exempt = VatResolutionContext {
                vat_regime: Some(exempt),
                ..ctx_override
            };
            assert_eq!(
                resolve_rate_from_rules(&rules, &ctx_exempt),
                dec!(0),
                "{exempt}"
            );
        }
    }

    #[test]
    fn unseeded_country_falls_back_to_zero() {
        let rules = sample_rules();
        let ctx = VatResolutionContext {
            country_code: "ZZ",
            category: "standard",
            product_override: None,
            vat_regime: Some("domestic"),
            purpose: None,
            building_construction_year: None,
            as_of: d(2026, 1, 1),
        };
        assert_eq!(resolve_rate_from_rules(&rules, &ctx), dec!(0));
    }
}
