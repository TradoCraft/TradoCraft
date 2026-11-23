//! Products (shared master data), price zones and zone price lists (per company).
//!
//! Other modules use [`get_products_for_quoting`] rather than reading these tables.

use std::collections::HashMap;

use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::Json;
use chrono::NaiveDate;
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgExecutor};
use tradocraft_core::{audit, new_id, AppError, AppResult, AppState, CurrentUser, Permission};
use tradocraft_pricing::{resolve_zone_price, ZonePrice};
use utoipa::{IntoParams, ToSchema};
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

const PRODUCT_TYPES: [&str; 4] = ["purchased", "manufactured", "configurable", "service"];
const TRACKING: [&str; 3] = ["none", "serial", "lot"];

pub mod attribute_definitions;
pub mod attributes;
pub mod bulk;
pub mod families;
pub mod import;
pub mod media;
pub use import::{products_import, Products};
pub mod options;
pub mod packaging;
pub mod power;
pub mod price_list_plan;
pub mod price_lists;
pub mod relations;
pub mod translations;

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct Product {
    pub id: Uuid,
    pub code: String,
    pub name: String,
    pub description: String,
    pub unit: String,
    /// purchased | manufactured | configurable | service
    pub product_type: String,
    #[schema(value_type = String, example = "21")]
    pub vat_rate: Decimal,
    /// VAT category used to resolve country-specific default rates (`standard`, `intermediate`, `reduced`, `zero`).
    #[schema(required = false)]
    pub vat_category: String,
    /// Optional explicit VAT rate overriding the country-category rate.
    #[schema(required = false, value_type = Option<String>, example = "12.00")]
    pub vat_rate_override: Option<Decimal>,
    /// none | serial | lot — serial-tracked products get an individual serial number per unit,
    /// lot-tracked products are stocked per lot or batch.
    pub tracking: String,
    pub family_id: Option<Uuid>,
    pub family_code: Option<String>,
    /// Never discounted: no customer rebate and no manual line discount.
    pub non_discountable: bool,
    /// No list price: the price is entered on each quotation line, which cannot be sent before.
    pub price_on_request: bool,
    /// The list price applies but is printed as indicative.
    pub price_is_indicative: bool,
    /// Whether this product contributes to turnover-based rebates. Null means unclassified.
    pub included_in_turnover: Option<bool>,
    pub active: bool,
    /// The default picture or video of the product (`GET /products/{id}/media/{id}`), if it has
    /// media.
    pub default_media_id: Option<Uuid>,
    /// `image` or `video`: a video has no thumbnail to show in a list.
    pub default_media_kind: Option<String>,
    /// Standard cost per stock unit. Only returned with the permission `inventory.cost`, else null.
    #[schema(value_type = Option<String>, example = "42.5000")]
    pub standard_cost: Option<Decimal>,
    /// Reorder when the available stock falls below this quantity.
    #[schema(value_type = Option<String>, example = "10")]
    pub reorder_min: Option<Decimal>,
    /// Order up to this quantity.
    #[schema(value_type = Option<String>, example = "40")]
    pub reorder_max: Option<Decimal>,
    pub lead_time_days: Option<i32>,
    pub barcode: Option<String>,
    pub packaging_category_id: Option<Uuid>,
    pub packaging_category_code: Option<String>,
    /// Outer dimensions of the packed product, in millimetres.
    pub length_mm: Option<i32>,
    pub width_mm: Option<i32>,
    pub height_mm: Option<i32>,
    /// Packed weight in grams.
    pub weight_g: Option<i32>,
    /// Internal remark that new quotation lines of this product start with.
    #[schema(required = false)]
    pub default_production_remark: String,
}

impl Product {
    /// Removes what the user may not see (cost).
    pub fn for_user(mut self, user: &CurrentUser) -> Self {
        if !user.can(Permission::InventoryCost) {
            self.standard_cost = None;
        }
        self
    }
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct ProductInput {
    pub code: String,
    pub name: String,
    #[serde(default)]
    pub description: String,
    #[serde(default = "default_unit")]
    pub unit: String,
    #[serde(default = "default_type")]
    pub product_type: String,
    /// Explicit VAT rate (kept for backwards compatibility). If `vat_category` / `vat_rate_override`
    /// are omitted, resolved via country rules and only treated as an override if no category matches.
    #[serde(default)]
    #[schema(required = false, value_type = Option<String>, example = "21")]
    pub vat_rate: Option<Decimal>,
    /// `standard` (default), `intermediate`, `reduced`, or `zero`.
    #[serde(default)]
    #[schema(required = false)]
    pub vat_category: Option<String>,
    /// Optional explicit VAT rate override (null clears any previous override).
    #[serde(default)]
    #[schema(required = false, value_type = Option<String>, example = "12.00")]
    pub vat_rate_override: Option<Decimal>,
    /// none | serial | lot. Services are not tracked.
    #[serde(default = "default_tracking")]
    pub tracking: String,
    pub family_id: Option<Uuid>,
    /// Never discounted: no customer rebate and no manual line discount.
    #[serde(default)]
    pub non_discountable: bool,
    /// No list price: the price is entered on each quotation line, which cannot be sent before.
    #[serde(default)]
    pub price_on_request: bool,
    /// The list price applies but is printed as indicative.
    #[serde(default)]
    pub price_is_indicative: bool,
    /// Whether this product contributes to turnover-based rebates. On update, omission preserves
    /// the stored classification and null clears it.
    #[serde(default, deserialize_with = "deserialize_turnover_eligibility")]
    #[schema(value_type = Option<bool>, required = false)]
    pub included_in_turnover: Option<Option<bool>>,
    #[serde(default = "default_true")]
    pub active: bool,
    /// Ignored (the stored cost is kept) without the permission `inventory.cost`.
    #[schema(value_type = Option<String>, example = "42.5")]
    pub standard_cost: Option<Decimal>,
    #[schema(value_type = Option<String>, example = "10")]
    pub reorder_min: Option<Decimal>,
    #[schema(value_type = Option<String>, example = "40")]
    pub reorder_max: Option<Decimal>,
    pub lead_time_days: Option<i32>,
    pub barcode: Option<String>,
    /// Must be an active packaging category.
    pub packaging_category_id: Option<Uuid>,
    /// Dimensions (mm) and weight (g) of the packed product; each must be positive when given.
    pub length_mm: Option<i32>,
    pub width_mm: Option<i32>,
    pub height_mm: Option<i32>,
    pub weight_g: Option<i32>,
    /// Internal remark that new quotation lines of this product start with (never printed for
    /// customers).
    #[serde(default)]
    pub default_production_remark: String,
}

fn deserialize_turnover_eligibility<'de, D: serde::Deserializer<'de>>(
    deserializer: D,
) -> Result<Option<Option<bool>>, D::Error> {
    Option::<bool>::deserialize(deserializer).map(Some)
}

pub(crate) fn barcode(input: &ProductInput) -> Option<&str> {
    input
        .barcode
        .as_deref()
        .map(str::trim)
        .filter(|b| !b.is_empty())
}

fn default_tracking() -> String {
    "none".into()
}

fn default_unit() -> String {
    "pcs".into()
}
fn default_type() -> String {
    "purchased".into()
}
fn default_true() -> bool {
    true
}

impl ProductInput {
    /// Every rule the input breaks, each as the message of a validation error.
    pub(crate) fn problems(&self) -> Vec<String> {
        let mut out = Vec::new();
        if self.code.trim().is_empty() || self.name.trim().is_empty() {
            out.push("code and name are required".to_string());
        }
        if !PRODUCT_TYPES.contains(&self.product_type.as_str()) {
            out.push(format!(
                "product_type must be one of {}",
                PRODUCT_TYPES.join(", ")
            ));
        }
        if !TRACKING.contains(&self.tracking.as_str()) {
            out.push(format!("tracking must be one of {}", TRACKING.join(", ")));
        }
        if self.vat_rate.is_some_and(|r| r < Decimal::ZERO)
            || self.vat_rate_override.is_some_and(|r| r < Decimal::ZERO)
        {
            out.push("vat_rate cannot be negative".to_string());
        }
        if self.vat_rate.is_some_and(|r| r >= Decimal::from(100))
            || self
                .vat_rate_override
                .is_some_and(|r| r >= Decimal::from(100))
        {
            out.push("vat_rate must be below 100".to_string());
        }
        if let Some(ref cat) = self.vat_category {
            let trimmed = cat.trim();
            if !trimmed.is_empty()
                && !tradocraft_core::vat_rates::is_valid_product_vat_category(trimmed)
            {
                out.push(format!(
                    "vat_category must be one of {}",
                    tradocraft_core::vat_rates::PRODUCT_VAT_CATEGORIES.join(", ")
                ));
            }
        }
        if self.tracking != "none" && self.product_type == "service" {
            out.push("services cannot be tracked".to_string());
        }
        let negative = |v: Option<Decimal>| v.is_some_and(|v| v < Decimal::ZERO);
        if negative(self.standard_cost) || negative(self.reorder_min) || negative(self.reorder_max)
        {
            out.push("cost and reorder quantities cannot be negative".to_string());
        }
        if let (Some(min), Some(max)) = (self.reorder_min, self.reorder_max) {
            if max < min {
                out.push("reorder_max must be at least reorder_min".to_string());
            }
        }
        if self.lead_time_days.is_some_and(|d| d < 0) {
            out.push("lead_time_days cannot be negative".to_string());
        }
        for (name, v) in [
            ("length_mm", self.length_mm),
            ("width_mm", self.width_mm),
            ("height_mm", self.height_mm),
            ("weight_g", self.weight_g),
        ] {
            if v.is_some_and(|v| v <= 0) {
                out.push(format!("{name} must be positive"));
            }
        }
        if self.default_production_remark.chars().count() > 2000 {
            out.push("default_production_remark is longer than 2000 characters".to_string());
        }
        out
    }

    /// The first broken rule as a validation error.
    pub(crate) fn validate(&self) -> AppResult<()> {
        match self.problems().into_iter().next() {
            Some(m) => Err(AppError::Validation(m)),
            None => Ok(()),
        }
    }
}

/// The packaging category of a product may only be set to an existing, active category (or kept).
async fn check_packaging(
    conn: &mut sqlx::PgConnection,
    category: Option<Uuid>,
    current: Option<Uuid>,
) -> AppResult<()> {
    let Some(id) = category.filter(|c| Some(*c) != current) else {
        return Ok(());
    };
    let active: Option<bool> =
        sqlx::query_scalar("SELECT active FROM products.packaging_categories WHERE id = $1")
            .bind(id)
            .fetch_optional(&mut *conn)
            .await?;
    match active {
        Some(true) => Ok(()),
        Some(false) => Err(AppError::Validation(
            "packaging category is inactive".into(),
        )),
        None => Err(AppError::Validation("unknown packaging category".into())),
    }
}

/// The subset of `product_ids` whose packaging category requires a manual shipping quote.
pub async fn requiring_shipping_quote<'e>(
    db: impl PgExecutor<'e>,
    product_ids: &[Uuid],
) -> AppResult<Vec<Uuid>> {
    Ok(sqlx::query_scalar(
        "SELECT p.id FROM products.products p
         JOIN products.packaging_categories c ON c.id = p.packaging_category_id
         WHERE p.id = ANY($1) AND c.requires_shipping_quote",
    )
    .bind(product_ids)
    .fetch_all(db)
    .await?)
}

#[derive(Debug, Serialize, ToSchema)]
pub struct ProductPage {
    pub items: Vec<Product>,
    pub total: i64,
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct ListParams {
    /// Searches code and name, ignoring case and accents.
    pub q: Option<String>,
    /// Exact product code match.
    pub code: Option<String>,
    pub active: Option<bool>,
    pub family_id: Option<Uuid>,
    /// Only these product types: one value or a comma-separated list (at most 20). Values:
    /// purchased, manufactured, configurable, service. They combine with OR.
    pub product_type: Option<String>,
    /// Sort order: `field` ascending or `-field` descending, comma-separated for several keys (at
    /// most 3). Fields: code, name, unit, product_type, family_code, non_discountable, price_on_request,
    /// price_is_indicative, active.
    /// Default: code.
    pub sort: Option<String>,
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}

/// API sort keys of `GET /products` and the SQL they stand for (columns of `SELECT_PRODUCT`).
const PRODUCT_SORT: &[(&str, &str)] = &[
    ("code", "p.code"),
    ("name", "p.name"),
    ("unit", "p.unit"),
    ("product_type", "p.product_type"),
    ("family_code", "p.family_code"),
    ("non_discountable", "p.non_discountable"),
    ("price_on_request", "p.price_on_request"),
    ("price_is_indicative", "p.price_is_indicative"),
    ("active", "p.active"),
];

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct PriceZone {
    pub id: Uuid,
    pub code: String,
    pub name: String,
    pub sort_order: i32,
    #[schema(value_type = Option<String>, example = "1.1500")]
    pub default_multiplier: Option<Decimal>,
    pub default_rounding: Option<String>,
}

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct ZonePriceEntry {
    pub id: Uuid,
    pub zone_id: Uuid,
    pub zone_code: String,
    #[schema(value_type = String, example = "125.0000")]
    pub unit_price: Decimal,
    pub valid_from: NaiveDate,
}

/// A correction of a zone price that has not started yet.
#[derive(Debug, Deserialize, ToSchema)]
pub struct ZonePriceCorrection {
    #[schema(value_type = String, example = "125.00")]
    pub unit_price: Decimal,
    /// The (possibly corrected) first day of the price; after today.
    #[serde(deserialize_with = "tradocraft_core::serde_util::date")]
    pub valid_from: NaiveDate,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct ZonePriceInput {
    pub zone_id: Uuid,
    #[schema(value_type = String, example = "125.00")]
    pub unit_price: Decimal,
    #[serde(deserialize_with = "tradocraft_core::serde_util::date")]
    pub valid_from: NaiveDate,
}

/// Products with their family code; wrapped so callers can filter on plain column names.
/// The product columns with the family and packaging category codes; `p` is the products table.
macro_rules! product_columns {
    () => {
        "SELECT p.id, p.code, p.name, p.description, p.unit, p.product_type, p.vat_rate,
                p.vat_category, p.vat_rate_override, p.tracking,
               p.family_id, f.code AS family_code, p.non_discountable, p.price_on_request,
               p.included_in_turnover,
               p.price_is_indicative, p.active, dm.file_id AS default_media_id,
               dm.kind AS default_media_kind, p.standard_cost, p.reorder_min,
               p.reorder_max, p.lead_time_days, p.barcode, p.packaging_category_id,
               pc.code AS packaging_category_code, p.length_mm, p.width_mm, p.height_mm, p.weight_g,
               p.default_production_remark
        FROM products.products p LEFT JOIN products.product_families f ON f.id = p.family_id
        LEFT JOIN products.packaging_categories pc ON pc.id = p.packaging_category_id
        LEFT JOIN products.media dm ON dm.product_id = p.id AND dm.is_default"
    };
}

pub(crate) const SELECT_PRODUCT: &str = concat!("SELECT * FROM (", product_columns!(), ") p");

/// Like [`SELECT_PRODUCT`] without the wrapping sub-query, so that a `FOR UPDATE OF p` clause can
/// lock the product rows in the very query that reads them.
pub(crate) const SELECT_PRODUCT_LOCKABLE: &str = product_columns!();

pub async fn get_product<'e>(db: impl PgExecutor<'e>, id: Uuid) -> AppResult<Product> {
    sqlx::query_as(sqlx::AssertSqlSafe(format!(
        "{SELECT_PRODUCT} WHERE id = $1"
    )))
    .bind(id)
    .fetch_optional(db)
    .await?
    .ok_or(AppError::NotFound("product"))
}

/// Like [`get_product`], after taking a shared row lock on the product that holds until the
/// transaction ends. A conversion to a service locks the row `FOR UPDATE`, so it waits for postings
/// in flight and postings wait for it. (The lock is a separate statement: `FOR SHARE` cannot be
/// applied through the outer joins of `SELECT_PRODUCT`.)
pub async fn get_product_for_share(conn: &mut sqlx::PgConnection, id: Uuid) -> AppResult<Product> {
    sqlx::query("SELECT 1 FROM products.products WHERE id = $1 FOR SHARE")
        .bind(id)
        .fetch_optional(&mut *conn)
        .await?
        .ok_or(AppError::NotFound("product"))?;
    get_product(&mut *conn, id).await
}

/// A product with its list price for a given company, zone and date.
#[derive(Debug, Clone)]
pub struct QuotingProduct {
    pub product: Product,
    pub list_unit_price: Decimal,
}

/// Loads the requested products with their zone price valid on `date`.
/// Fails if a product is unknown, inactive or has no price in that zone.
pub async fn get_products_for_quoting(
    db: &sqlx::PgPool,
    company_id: Uuid,
    zone_id: Uuid,
    zone_code: &str,
    date: NaiveDate,
    product_ids: &[Uuid],
) -> AppResult<HashMap<Uuid, QuotingProduct>> {
    get_products_for_quoting_with(db, company_id, zone_id, zone_code, date, product_ids, &[]).await
}

/// The ids of the active products with these codes (matched exactly). Unknown and inactive codes
/// are absent from the result.
pub async fn active_ids_by_code<'e>(
    db: impl PgExecutor<'e>,
    codes: &[String],
) -> AppResult<HashMap<String, Uuid>> {
    let rows: Vec<(String, Uuid)> =
        sqlx::query_as("SELECT code, id FROM products.products WHERE code = ANY($1) AND active")
            .bind(codes)
            .fetch_all(db)
            .await?;
    Ok(rows.into_iter().collect())
}

pub(crate) fn apply_resolved_vat(
    products: &mut [Product],
    country_code: &str,
    rules: &[tradocraft_core::vat_rates::CountryVatRate],
    as_of: NaiveDate,
) {
    for p in products {
        p.vat_rate = tradocraft_core::vat_rates::resolve_rate_from_rules(
            rules,
            &tradocraft_core::vat_rates::VatResolutionContext {
                country_code,
                category: &p.vat_category,
                product_override: p.vat_rate_override,
                vat_regime: None,
                purpose: None,
                building_construction_year: None,
                as_of,
            },
        );
    }
}

pub(crate) async fn resolve_products_for_company(
    db: &sqlx::PgPool,
    company_id: Uuid,
    as_of: NaiveDate,
    products: &mut [Product],
) -> AppResult<()> {
    if products.is_empty() {
        return Ok(());
    }
    let company = tradocraft_core::company::get_company(db, company_id).await?;
    let rules = tradocraft_core::vat_rates::load_country_rules(db, &company.country_code).await?;
    apply_resolved_vat(products, &company.country_code, &rules, as_of);
    Ok(())
}

/// Like [`get_products_for_quoting`], but the products in `price_optional` may lack a zone price
/// (their `list_unit_price` is then zero): used for lines priced from another line, such as a
/// percentage of their parent line.
pub async fn get_products_for_quoting_with(
    db: &sqlx::PgPool,
    company_id: Uuid,
    zone_id: Uuid,
    zone_code: &str,
    date: NaiveDate,
    product_ids: &[Uuid],
    price_optional: &[Uuid],
) -> AppResult<HashMap<Uuid, QuotingProduct>> {
    let mut products: Vec<Product> = sqlx::query_as(sqlx::AssertSqlSafe(format!(
        "{SELECT_PRODUCT} WHERE id = ANY($1)"
    )))
    .bind(product_ids)
    .fetch_all(db)
    .await?;
    resolve_products_for_company(db, company_id, date, &mut products).await?;
    #[derive(FromRow)]
    struct Row {
        product_id: Uuid,
        zone_id: Uuid,
        unit_price: Decimal,
        valid_from: NaiveDate,
    }
    let rows: Vec<Row> = sqlx::query_as(
        "SELECT product_id, zone_id, unit_price, valid_from FROM pricing.zone_prices
         WHERE company_id = $1 AND zone_id = $2 AND product_id = ANY($3) AND valid_from <= $4",
    )
    .bind(company_id)
    .bind(zone_id)
    .bind(product_ids)
    .bind(date)
    .fetch_all(db)
    .await?;

    let mut result = HashMap::new();
    for id in product_ids {
        let product = products
            .iter()
            .find(|p| p.id == *id)
            .ok_or(AppError::NotFound("product"))?;
        if !product.active {
            return Err(AppError::Validation(format!(
                "product {} is inactive",
                product.code
            )));
        }
        let prices: Vec<ZonePrice> = rows
            .iter()
            .filter(|r| r.product_id == *id)
            .map(|r| ZonePrice {
                zone_id: r.zone_id,
                unit_price: r.unit_price,
                valid_from: r.valid_from,
            })
            .collect();
        let price = match resolve_zone_price(&prices, zone_id, date) {
            Some(p) => p,
            // A price-on-request product needs no zone price: its price is entered per line.
            None if price_optional.contains(id) || product.price_on_request => Decimal::ZERO,
            None => {
                return Err(AppError::Validation(format!(
                    "product {} has no price in price zone {zone_code} on {date}",
                    product.code
                )))
            }
        };
        result.insert(
            *id,
            QuotingProduct {
                product: product.clone(),
                list_unit_price: price,
            },
        );
    }
    Ok(result)
}

#[utoipa::path(get, path = "/products", tag = "products", params(ListParams),
    responses((status = 200, body = ProductPage)))]
async fn list_products(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(p): Query<ListParams>,
) -> AppResult<Json<ProductPage>> {
    user.require(Permission::ProductsRead)?;
    let pattern = tradocraft_core::search::pattern(p.q.as_deref());
    let types =
        tradocraft_core::filter::values(p.product_type.as_deref(), "product_type", &PRODUCT_TYPES)?;
    let filter = format!(
        "WHERE ($1::text IS NULL OR {} OR {})
                  AND ($2::boolean IS NULL OR active = $2)
                  AND ($5::uuid IS NULL OR family_id = $5)
                  AND ($6::text[] IS NULL OR product_type = ANY($6))
                  AND ($7::text IS NULL OR code = $7)",
        tradocraft_core::search::matches("code", "$1"),
        tradocraft_core::search::matches("name", "$1"),
    );
    let order = tradocraft_core::sort::order_by(p.sort.as_deref(), PRODUCT_SORT, "p.id", "code")?;
    let mut items: Vec<Product> = sqlx::query_as(sqlx::AssertSqlSafe(format!(
        "{SELECT_PRODUCT} {filter} ORDER BY {order} LIMIT $3 OFFSET $4"
    )))
    .bind(&pattern)
    .bind(p.active)
    .bind(p.limit.unwrap_or(50).clamp(1, 500))
    .bind(p.offset.unwrap_or(0).max(0))
    .bind(p.family_id)
    .bind(&types)
    .bind(&p.code)
    .fetch_all(&state.db)
    .await?;
    resolve_products_for_company(
        &state.db,
        user.company_id,
        tradocraft_core::today(),
        &mut items,
    )
    .await?;
    let total = sqlx::query_scalar(sqlx::AssertSqlSafe(format!(
        "SELECT count(*) FROM products.products {}",
        filter
            .replace("$5", "$3")
            .replace("$6", "$4")
            .replace("$7", "$5")
    )))
    .bind(&pattern)
    .bind(p.active)
    .bind(p.family_id)
    .bind(&types)
    .bind(&p.code)
    .fetch_one(&state.db)
    .await?;
    let items = items
        .into_iter()
        .map(|p: Product| p.for_user(&user))
        .collect();
    Ok(Json(ProductPage { items, total }))
}

#[utoipa::path(get, path = "/products/{id}", tag = "products", operation_id = "get_product", params(("id" = Uuid, Path)),
    responses((status = 200, body = Product), (status = 404, body = tradocraft_core::error::ErrorBody)))]
async fn get_product_handler(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<Product>> {
    user.require(Permission::ProductsRead)?;
    let mut product = get_product(&state.db, id).await?;
    resolve_products_for_company(
        &state.db,
        user.company_id,
        tradocraft_core::today(),
        std::slice::from_mut(&mut product),
    )
    .await?;
    Ok(Json(product.for_user(&user)))
}

async fn resolve_product_fields(
    conn: &mut sqlx::PgConnection,
    company_id: Uuid,
    input: &ProductInput,
) -> AppResult<(String, Option<Decimal>, Decimal)> {
    let company = tradocraft_core::company::get_company(&mut *conn, company_id).await?;
    let today = tradocraft_core::today();
    let rules =
        tradocraft_core::vat_rates::load_country_rules(&mut *conn, &company.country_code).await?;

    if let Some(ov) = input.vat_rate_override {
        let cat = input
            .vat_category
            .as_deref()
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .unwrap_or("standard")
            .to_ascii_lowercase();
        return Ok((cat, Some(ov), ov));
    }
    if let Some(cat_raw) = input
        .vat_category
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
    {
        let cat = cat_raw.to_ascii_lowercase();
        let rate = tradocraft_core::vat_rates::resolve_rate_from_rules(
            &rules,
            &tradocraft_core::vat_rates::VatResolutionContext {
                country_code: &company.country_code,
                category: &cat,
                product_override: None,
                vat_regime: None,
                purpose: None,
                building_construction_year: None,
                as_of: today,
            },
        );
        return Ok((cat, None, rate));
    }
    if let Some(explicit) = input.vat_rate {
        if let Some(inferred) = tradocraft_core::vat_rates::infer_category_for_rate(
            &rules,
            &company.country_code,
            explicit,
            today,
        ) {
            return Ok((inferred.to_string(), None, explicit));
        }
        return Ok(("standard".to_string(), Some(explicit), explicit));
    }
    let rate = tradocraft_core::vat_rates::resolve_rate_from_rules(
        &rules,
        &tradocraft_core::vat_rates::VatResolutionContext {
            country_code: &company.country_code,
            category: "standard",
            product_override: None,
            vat_regime: None,
            purpose: None,
            building_construction_year: None,
            as_of: today,
        },
    );
    Ok(("standard".to_string(), None, rate))
}

/// Inserts a product (validation is the caller's job). The standard cost is stored only when
/// `write_cost` (the user holds `inventory.cost`).
pub(crate) async fn insert_product(
    conn: &mut sqlx::PgConnection,
    id: Uuid,
    company_id: Uuid,
    input: &ProductInput,
    write_cost: bool,
) -> AppResult<()> {
    check_packaging(conn, input.packaging_category_id, None).await?;
    let (vat_category, vat_rate_override, vat_rate) =
        resolve_product_fields(conn, company_id, input).await?;
    sqlx::query(
        "INSERT INTO products.products (id, code, name, description, unit, product_type, vat_rate, vat_category,
                                        vat_rate_override, active, tracking, family_id, non_discountable, standard_cost,
                                        reorder_min, reorder_max, lead_time_days, barcode, packaging_category_id,
                                        length_mm, width_mm, height_mm, weight_g, default_production_remark,
                                        price_on_request, price_is_indicative, included_in_turnover)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20, $21, $22, $23, $24,
                 $25, $26, $27)",
    )
    .bind(id)
    .bind(input.code.trim())
    .bind(input.name.trim())
    .bind(&input.description)
    .bind(&input.unit)
    .bind(&input.product_type)
    .bind(vat_rate)
    .bind(&vat_category)
    .bind(vat_rate_override)
    .bind(input.active)
    .bind(&input.tracking)
    .bind(input.family_id)
    .bind(input.non_discountable)
    .bind(input.standard_cost.filter(|_| write_cost))
    .bind(input.reorder_min)
    .bind(input.reorder_max)
    .bind(input.lead_time_days)
    .bind(barcode(input))
    .bind(input.packaging_category_id)
    .bind(input.length_mm)
    .bind(input.width_mm)
    .bind(input.height_mm)
    .bind(input.weight_g)
    .bind(input.default_production_remark.trim())
    .bind(input.price_on_request)
    .bind(input.price_is_indicative)
    .bind(input.included_in_turnover.flatten())
    .execute(&mut *conn)
    .await?;
    Ok(())
}

/// A product with stock moves cannot become a service.
pub(crate) async fn check_service_conversion(
    conn: &mut sqlx::PgConnection,
    id: Uuid,
    stored_type: &str,
    new_type: &str,
) -> AppResult<()> {
    if new_type == "service" && stored_type != "service" {
        // A service has no stock: turning a product with stock moves into one would drop it from
        // the stock totals and make every later issue, transfer and reversal fail. Products are
        // shared master data, so moves of any company count.
        let has_moves: bool = sqlx::query_scalar(
            "SELECT EXISTS (SELECT 1 FROM inventory.stock_moves WHERE product_id = $1)",
        )
        .bind(id)
        .fetch_one(conn)
        .await?;
        if has_moves {
            return Err(AppError::Conflict(
                "a product with stock moves cannot become a service".into(),
            ));
        }
    }
    Ok(())
}

/// Updates a product; `NotFound` if the id is unknown. The stored standard cost is kept unless
/// `write_cost`.
pub(crate) async fn update_product_row(
    conn: &mut sqlx::PgConnection,
    id: Uuid,
    company_id: Uuid,
    input: &ProductInput,
    write_cost: bool,
) -> AppResult<()> {
    // Lock the row first: stock posting takes it FOR SHARE, so a conversion and a posting for the
    // same product cannot interleave.
    let (stored_type, current_packaging): (String, Option<Uuid>) = sqlx::query_as(
        "SELECT product_type, packaging_category_id FROM products.products WHERE id = $1 FOR UPDATE",
    )
    .bind(id)
    .fetch_optional(&mut *conn)
    .await?
    .ok_or(AppError::NotFound("product"))?;
    check_service_conversion(conn, id, &stored_type, &input.product_type).await?;
    check_packaging(conn, input.packaging_category_id, current_packaging).await?;
    let (vat_category, vat_rate_override, vat_rate) =
        resolve_product_fields(conn, company_id, input).await?;
    sqlx::query("SELECT set_config('tradocraft.updating_product', '1', true)")
        .execute(&mut *conn)
        .await?;
    let updated = sqlx::query(
        "UPDATE products.products SET code = $2, name = $3, description = $4, unit = $5, product_type = $6,
                vat_rate = $7, vat_category = $24, vat_rate_override = $25, active = $8, tracking = $9,
                family_id = $10, non_discountable = $11, price_on_request = $26, price_is_indicative = $27,
                standard_cost = CASE WHEN $12 THEN $13 ELSE standard_cost END,
                reorder_min = $14, reorder_max = $15, lead_time_days = $16, barcode = $17,
                packaging_category_id = $18, length_mm = $19, width_mm = $20, height_mm = $21, weight_g = $22,
                default_production_remark = $23,
                included_in_turnover = CASE WHEN $28 THEN $29 ELSE included_in_turnover END,
                updated_at = now()
         WHERE id = $1",
    )
    .bind(id)
    .bind(input.code.trim())
    .bind(input.name.trim())
    .bind(&input.description)
    .bind(&input.unit)
    .bind(&input.product_type)
    .bind(vat_rate)
    .bind(input.active)
    .bind(&input.tracking)
    .bind(input.family_id)
    .bind(input.non_discountable)
    .bind(write_cost)
    .bind(input.standard_cost)
    .bind(input.reorder_min)
    .bind(input.reorder_max)
    .bind(input.lead_time_days)
    .bind(barcode(input))
    .bind(input.packaging_category_id)
    .bind(input.length_mm)
    .bind(input.width_mm)
    .bind(input.height_mm)
    .bind(input.weight_g)
    .bind(input.default_production_remark.trim())
    .bind(&vat_category)
    .bind(vat_rate_override)
    .bind(input.price_on_request)
    .bind(input.price_is_indicative)
    .bind(input.included_in_turnover.is_some())
    .bind(input.included_in_turnover.flatten())
    .execute(&mut *conn)
    .await?;
    if updated.rows_affected() == 0 {
        return Err(AppError::NotFound("product"));
    }
    Ok(())
}

#[utoipa::path(post, path = "/products", tag = "products", request_body = ProductInput,
    responses((status = 201, body = Product), (status = 409, body = tradocraft_core::error::ErrorBody)))]
async fn create_product(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<ProductInput>,
) -> AppResult<(StatusCode, Json<Product>)> {
    user.require(Permission::ProductsWrite)?;
    input.validate()?;
    let id = new_id();
    let mut tx = state.db.begin().await?;
    insert_product(
        &mut tx,
        id,
        user.company_id,
        &input,
        user.can(Permission::InventoryCost),
    )
    .await?;
    audit::record(
        &mut tx,
        &user,
        "product",
        id,
        "created",
        serde_json::json!({ "code": input.code }),
    )
    .await?;
    tx.commit().await?;
    let mut product = get_product(&state.db, id).await?;
    resolve_products_for_company(
        &state.db,
        user.company_id,
        tradocraft_core::today(),
        std::slice::from_mut(&mut product),
    )
    .await?;
    Ok((StatusCode::CREATED, Json(product.for_user(&user))))
}

#[utoipa::path(put, path = "/products/{id}", tag = "products", params(("id" = Uuid, Path)),
    request_body = ProductInput,
    responses((status = 200, body = Product), (status = 409, body = tradocraft_core::error::ErrorBody)))]
async fn update_product(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<ProductInput>,
) -> AppResult<Json<Product>> {
    user.require(Permission::ProductsWrite)?;
    input.validate()?;
    let mut tx = state.db.begin().await?;
    update_product_row(
        &mut tx,
        id,
        user.company_id,
        &input,
        user.can(Permission::InventoryCost),
    )
    .await?;
    audit::record(
        &mut tx,
        &user,
        "product",
        id,
        "updated",
        serde_json::json!({}),
    )
    .await?;
    tx.commit().await?;
    let mut product = get_product(&state.db, id).await?;
    resolve_products_for_company(
        &state.db,
        user.company_id,
        tradocraft_core::today(),
        std::slice::from_mut(&mut product),
    )
    .await?;
    Ok(Json(product.for_user(&user)))
}

#[utoipa::path(get, path = "/price-zones", tag = "products",
    responses((status = 200, body = Vec<PriceZone>)))]
async fn list_price_zones(
    State(state): State<AppState>,
    user: CurrentUser,
) -> AppResult<Json<Vec<PriceZone>>> {
    user.require(Permission::ProductsRead)?;
    Ok(Json(
        sqlx::query_as(
            "SELECT id, code, name, sort_order, default_multiplier, default_rounding
             FROM pricing.price_zones WHERE company_id = $1 ORDER BY sort_order, code",
        )
        .bind(user.company_id)
        .fetch_all(&state.db)
        .await?,
    ))
}

/// Create/update body of a price zone.
#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct PriceZoneInput {
    pub code: String,
    pub name: String,
    #[serde(default)]
    pub sort_order: i32,
    #[serde(default)]
    #[schema(value_type = Option<String>, example = "1.15")]
    pub default_multiplier: Option<Decimal>,
    #[serde(default)]
    pub default_rounding: Option<String>,
}

const VALID_ROUNDINGS: &[&str] = &[
    "none", "0.01", "0.05", "0.10", "0.50", "1.00", "5.00", "10.00",
];

impl PriceZoneInput {
    /// Trims the fields and rejects a blank or too long (more than 32 characters) code and a blank name.
    fn validate(&mut self) -> AppResult<()> {
        self.code = self.code.trim().to_string();
        self.name = self.name.trim().to_string();
        if self.code.is_empty() || self.code.chars().count() > 32 {
            return Err(AppError::Validation(
                "code is required (at most 32 characters)".into(),
            ));
        }
        if self.name.is_empty() {
            return Err(AppError::Validation("name is required".into()));
        }
        if let Some(m) = self.default_multiplier {
            if m <= Decimal::ZERO || m.normalize().scale() > 4 || m > Decimal::new(9_999_999_999, 4)
            {
                return Err(AppError::Validation(
                    "default_multiplier must be positive and fit NUMERIC(10, 4)".into(),
                ));
            }
        }
        if let Some(ref r) = self.default_rounding {
            let trimmed = r.trim();
            if trimmed.is_empty() {
                self.default_rounding = None;
            } else if !VALID_ROUNDINGS.contains(&trimmed) {
                return Err(AppError::Validation(
                    "default_rounding must be one of none, 0.01, 0.05, 0.10, 0.50, 1.00, 5.00, 10.00".into(),
                ));
            } else {
                self.default_rounding = Some(trimmed.to_string());
            }
        }
        Ok(())
    }
}

/// The 409 answered when a zone code is already used in the company.
fn zone_code_taken() -> AppError {
    AppError::Conflict("a price zone with this code already exists".into())
}

/// Creates a price zone in the active company.
#[utoipa::path(post, path = "/price-zones", tag = "products", request_body = PriceZoneInput,
    responses((status = 201, body = PriceZone), (status = 409, body = tradocraft_core::error::ErrorBody)))]
async fn create_price_zone(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(mut input): Json<PriceZoneInput>,
) -> AppResult<(StatusCode, Json<PriceZone>)> {
    user.require(Permission::PricesWrite)?;
    input.validate()?;
    let id = new_id();
    let mut tx = state.db.begin().await?;
    let zone: PriceZone = sqlx::query_as(
        "INSERT INTO pricing.price_zones (id, company_id, code, name, sort_order, default_multiplier, default_rounding)
         VALUES ($1, $2, $3, $4, $5, $6, $7)
         ON CONFLICT (company_id, code) DO NOTHING
         RETURNING id, code, name, sort_order, default_multiplier, default_rounding",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(&input.code)
    .bind(&input.name)
    .bind(input.sort_order)
    .bind(input.default_multiplier)
    .bind(&input.default_rounding)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or_else(zone_code_taken)?;
    audit::record(
        &mut tx,
        &user,
        "price_zone",
        id,
        "created",
        serde_json::json!({ "code": input.code }),
    )
    .await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(zone)))
}

/// Changes the code, name, sort order, or default pricing formula of a price zone.
#[utoipa::path(put, path = "/price-zones/{id}", tag = "products", params(("id" = Uuid, Path)),
    request_body = PriceZoneInput,
    responses((status = 200, body = PriceZone), (status = 409, body = tradocraft_core::error::ErrorBody)))]
async fn update_price_zone(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(mut input): Json<PriceZoneInput>,
) -> AppResult<Json<PriceZone>> {
    user.require(Permission::PricesWrite)?;
    input.validate()?;
    let mut tx = state.db.begin().await?;
    // The zone must belong to the company before a code conflict is reported.
    sqlx::query_scalar::<_, Uuid>(
        "SELECT id FROM pricing.price_zones WHERE id = $1 AND company_id = $2 FOR UPDATE",
    )
    .bind(id)
    .bind(user.company_id)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or(AppError::NotFound("price zone"))?;
    let clash: bool = sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM pricing.price_zones WHERE company_id = $1 AND code = $2 AND id <> $3)",
    )
    .bind(user.company_id)
    .bind(&input.code)
    .bind(id)
    .fetch_one(&mut *tx)
    .await?;
    if clash {
        return Err(zone_code_taken());
    }
    let zone: PriceZone = sqlx::query_as(
        "UPDATE pricing.price_zones
         SET code = $3, name = $4, sort_order = $5, default_multiplier = $6, default_rounding = $7
         WHERE id = $1 AND company_id = $2
         RETURNING id, code, name, sort_order, default_multiplier, default_rounding",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(&input.code)
    .bind(&input.name)
    .bind(input.sort_order)
    .bind(input.default_multiplier)
    .bind(&input.default_rounding)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or(AppError::NotFound("price zone"))?;
    audit::record(
        &mut tx,
        &user,
        "price_zone",
        id,
        "updated",
        serde_json::json!({ "code": input.code }),
    )
    .await?;
    tx.commit().await?;
    Ok(Json(zone))
}

/// Deletes a price zone that nothing refers to: refused (409) while zone prices or customer terms use it.
#[utoipa::path(delete, path = "/price-zones/{id}", tag = "products", params(("id" = Uuid, Path)),
    responses((status = 204), (status = 404, body = tradocraft_core::error::ErrorBody),
        (status = 409, body = tradocraft_core::error::ErrorBody)))]
async fn delete_price_zone(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<StatusCode> {
    user.require(Permission::PricesWrite)?;
    let mut tx = state.db.begin().await?;
    let code: String = sqlx::query_scalar(
        "SELECT code FROM pricing.price_zones WHERE id = $1 AND company_id = $2 FOR UPDATE",
    )
    .bind(id)
    .bind(user.company_id)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or(AppError::NotFound("price zone"))?;
    let (prices, terms, lists): (i64, i64, i64) = sqlx::query_as(
        "SELECT (SELECT count(*) FROM pricing.zone_prices WHERE zone_id = $1),
                (SELECT count(*) FROM crm.customer_terms WHERE price_zone_id = $1),
                (SELECT count(*) FROM pricing.price_list_zones WHERE price_zone_id = $1)",
    )
    .bind(id)
    .fetch_one(&mut *tx)
    .await?;
    if prices > 0 || terms > 0 || lists > 0 {
        return Err(AppError::Conflict(format!(
            "price zone {code} is in use ({prices} zone prices, {terms} customers, {lists} price lists) and cannot be deleted"
        )));
    }
    sqlx::query("DELETE FROM pricing.price_zones WHERE id = $1")
        .bind(id)
        .execute(&mut *tx)
        .await?;
    audit::record(
        &mut tx,
        &user,
        "price_zone",
        id,
        "deleted",
        serde_json::json!({ "code": code }),
    )
    .await?;
    tx.commit().await?;
    Ok(StatusCode::NO_CONTENT)
}

const SELECT_ZONE_PRICES: &str =
    "SELECT p.id, p.zone_id, z.code AS zone_code, p.unit_price, p.valid_from
     FROM pricing.zone_prices p JOIN pricing.price_zones z ON z.id = p.zone_id
     WHERE p.company_id = $1 AND p.product_id = $2";

/// Full price history of a product in the active company, newest first per zone.
#[utoipa::path(get, path = "/products/{id}/prices", tag = "products", params(("id" = Uuid, Path)),
    responses((status = 200, body = Vec<ZonePriceEntry>)))]
async fn list_product_prices(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<Vec<ZonePriceEntry>>> {
    user.require(Permission::ProductsRead)?;
    Ok(Json(
        sqlx::query_as(sqlx::AssertSqlSafe(format!(
            "{SELECT_ZONE_PRICES} ORDER BY z.sort_order, p.valid_from DESC"
        )))
        .bind(user.company_id)
        .bind(id)
        .fetch_all(&state.db)
        .await?,
    ))
}

/// Adds a price for a zone from a date. Prices in effect are never edited: a new entry supersedes
/// older ones. A price that has not started yet can be corrected or deleted.
#[utoipa::path(post, path = "/products/{id}/prices", tag = "products", params(("id" = Uuid, Path)),
    request_body = ZonePriceInput,
    responses((status = 201, body = ZonePriceEntry), (status = 409, body = tradocraft_core::error::ErrorBody)))]
async fn add_product_price(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(product_id): Path<Uuid>,
    Json(input): Json<ZonePriceInput>,
) -> AppResult<(StatusCode, Json<ZonePriceEntry>)> {
    user.require(Permission::PricesWrite)?;
    let mut tx = state.db.begin().await?;
    let zone_ok: bool = sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM pricing.price_zones WHERE id = $1 AND company_id = $2)",
    )
    .bind(input.zone_id)
    .bind(user.company_id)
    .fetch_one(&mut *tx)
    .await?;
    if !zone_ok {
        return Err(AppError::Validation(
            "price zone does not belong to the active company".into(),
        ));
    }
    get_product(&mut *tx, product_id).await?;
    let id = new_id();
    sqlx::query(
        "INSERT INTO pricing.zone_prices (id, company_id, zone_id, product_id, unit_price, valid_from, created_by)
         VALUES ($1, $2, $3, $4, $5, $6, $7)",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(input.zone_id)
    .bind(product_id)
    .bind(input.unit_price)
    .bind(input.valid_from)
    .bind(user.user_id)
    .execute(&mut *tx)
    .await?;
    audit::record(
        &mut tx,
        &user,
        "product",
        product_id,
        "price_added",
        serde_json::json!({ "zone_id": input.zone_id, "unit_price": input.unit_price, "valid_from": input.valid_from }),
    )
    .await?;
    let entry = sqlx::query_as(sqlx::AssertSqlSafe(format!(
        "{SELECT_ZONE_PRICES} AND p.id = $3"
    )))
    .bind(user.company_id)
    .bind(product_id)
    .bind(id)
    .fetch_one(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(entry)))
}

/// Locks a zone price of a product in the active company and checks that it has not started yet:
/// prices that are or were in effect are history (ADR 0012) and stay as they are.
async fn lock_planned_price(
    conn: &mut sqlx::PgConnection,
    user: &CurrentUser,
    product_id: Uuid,
    price_id: Uuid,
) -> AppResult<ZonePriceEntry> {
    let entry: ZonePriceEntry = sqlx::query_as(sqlx::AssertSqlSafe(format!(
        "{SELECT_ZONE_PRICES} AND p.id = $3 FOR UPDATE OF p"
    )))
    .bind(user.company_id)
    .bind(product_id)
    .bind(price_id)
    .fetch_optional(&mut *conn)
    .await?
    .ok_or(AppError::NotFound("price"))?;
    if entry.valid_from <= tradocraft_core::today() {
        return Err(AppError::Conflict(format!(
            "the price of {} in zone {} is in effect since {}; add a new dated price instead",
            entry.unit_price.normalize(),
            entry.zone_code,
            entry.valid_from
        )));
    }
    Ok(entry)
}

/// Corrects the price or start date of a price that has not started yet (409 for one in effect).
#[utoipa::path(put, path = "/products/{id}/prices/{price_id}", tag = "products",
    params(("id" = Uuid, Path), ("price_id" = Uuid, Path)),
    request_body = ZonePriceCorrection,
    responses((status = 200, body = ZonePriceEntry), (status = 409, body = tradocraft_core::error::ErrorBody),
        (status = 422, body = tradocraft_core::error::ErrorBody)))]
async fn correct_product_price(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((product_id, price_id)): Path<(Uuid, Uuid)>,
    Json(input): Json<ZonePriceCorrection>,
) -> AppResult<Json<ZonePriceEntry>> {
    user.require(Permission::PricesWrite)?;
    if input.valid_from <= tradocraft_core::today() {
        return Err(AppError::Validation(
            "a corrected price must start after today; add a new price to change today's".into(),
        ));
    }
    let mut tx = state.db.begin().await?;
    let old = lock_planned_price(&mut tx, &user, product_id, price_id).await?;
    if input.valid_from != old.valid_from {
        let taken: bool = sqlx::query_scalar(
            "SELECT EXISTS (SELECT 1 FROM pricing.zone_prices
                            WHERE zone_id = $1 AND product_id = $2 AND valid_from = $3)",
        )
        .bind(old.zone_id)
        .bind(product_id)
        .bind(input.valid_from)
        .fetch_one(&mut *tx)
        .await?;
        if taken {
            return Err(AppError::Conflict(format!(
                "zone {} already has a price starting on {}",
                old.zone_code, input.valid_from
            )));
        }
    }
    sqlx::query("UPDATE pricing.zone_prices SET unit_price = $2, valid_from = $3 WHERE id = $1")
        .bind(price_id)
        .bind(input.unit_price)
        .bind(input.valid_from)
        .execute(&mut *tx)
        .await?;
    audit::record(
        &mut tx,
        &user,
        "product",
        product_id,
        "price_corrected",
        serde_json::json!({
            "price_id": price_id,
            "zone_id": old.zone_id,
            "old": { "unit_price": old.unit_price, "valid_from": old.valid_from },
            "new": { "unit_price": input.unit_price, "valid_from": input.valid_from },
        }),
    )
    .await?;
    let entry = sqlx::query_as(sqlx::AssertSqlSafe(format!(
        "{SELECT_ZONE_PRICES} AND p.id = $3"
    )))
    .bind(user.company_id)
    .bind(product_id)
    .bind(price_id)
    .fetch_one(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(Json(entry))
}

/// Deletes a price that has not started yet (409 for one in effect).
#[utoipa::path(delete, path = "/products/{id}/prices/{price_id}", tag = "products",
    params(("id" = Uuid, Path), ("price_id" = Uuid, Path)),
    responses((status = 204), (status = 409, body = tradocraft_core::error::ErrorBody)))]
async fn delete_product_price(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((product_id, price_id)): Path<(Uuid, Uuid)>,
) -> AppResult<StatusCode> {
    user.require(Permission::PricesWrite)?;
    let mut tx = state.db.begin().await?;
    let old = lock_planned_price(&mut tx, &user, product_id, price_id).await?;
    sqlx::query("DELETE FROM pricing.zone_prices WHERE id = $1")
        .bind(price_id)
        .execute(&mut *tx)
        .await?;
    audit::record(
        &mut tx,
        &user,
        "product",
        product_id,
        "price_deleted",
        serde_json::json!({
            "price_id": price_id,
            "zone_id": old.zone_id,
            "unit_price": old.unit_price,
            "valid_from": old.valid_from,
        }),
    )
    .await?;
    tx.commit().await?;
    Ok(StatusCode::NO_CONTENT)
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(list_products, create_product))
        .routes(routes!(get_product_handler, update_product))
        .routes(routes!(list_product_prices, add_product_price))
        .routes(routes!(correct_product_price, delete_product_price))
        .routes(routes!(list_price_zones, create_price_zone))
        .routes(routes!(update_price_zone, delete_price_zone))
        .merge(families::router())
        .merge(packaging::router())
        .merge(power::router())
        .merge(price_lists::router())
        .merge(relations::router())
        .merge(bulk::router())
        .merge(import::router())
        .merge(translations::router())
        .merge(media::router())
        .merge(options::router())
        .merge(attributes::router())
        .merge(attribute_definitions::router())
}
