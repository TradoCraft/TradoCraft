//! Product DTOs and endpoints (`/api/v1/products`).

use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::client::Client;
use crate::error::ApiError;

/// Product record returned by `GET /api/v1/products`, `GET /api/v1/products/{id}`,
/// `POST /api/v1/products`, and `PUT /api/v1/products/{id}`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Product {
    pub id: Uuid,
    pub code: String,
    pub name: String,
    pub description: String,
    pub unit: String,
    /// `purchased | manufactured | configurable | service`
    pub product_type: String,
    pub vat_rate: Decimal,
    /// VAT category used to resolve country-specific default rates (`standard`, `intermediate`,
    /// `reduced`, `zero`).
    #[serde(default)]
    pub vat_category: String,
    /// Optional explicit VAT rate overriding the country-category rate.
    #[serde(default)]
    pub vat_rate_override: Option<Decimal>,
    /// `none | serial | lot`
    pub tracking: String,
    #[serde(default)]
    pub family_id: Option<Uuid>,
    #[serde(default)]
    pub family_code: Option<String>,
    pub non_discountable: bool,
    pub price_on_request: bool,
    pub price_is_indicative: bool,
    #[serde(default)]
    pub included_in_turnover: Option<bool>,
    pub active: bool,
    #[serde(default)]
    pub default_media_id: Option<Uuid>,
    #[serde(default)]
    pub default_media_kind: Option<String>,
    #[serde(default)]
    pub standard_cost: Option<Decimal>,
    #[serde(default)]
    pub reorder_min: Option<Decimal>,
    #[serde(default)]
    pub reorder_max: Option<Decimal>,
    #[serde(default)]
    pub order_multiple: Option<Decimal>,
    #[serde(default)]
    pub safety_stock: Option<Decimal>,
    #[serde(default)]
    pub lead_time_days: Option<i32>,
    #[serde(default)]
    pub barcode: Option<String>,
    #[serde(default)]
    pub packaging_category_id: Option<Uuid>,
    #[serde(default)]
    pub packaging_category_code: Option<String>,
    #[serde(default)]
    pub length_mm: Option<i32>,
    #[serde(default)]
    pub width_mm: Option<i32>,
    #[serde(default)]
    pub height_mm: Option<i32>,
    #[serde(default)]
    pub weight_g: Option<i32>,
    #[serde(default)]
    pub default_production_remark: String,
}

/// Request payload for `POST /api/v1/products` and `PUT /api/v1/products/{id}`
/// (OpenAPI schema `ProductInput`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProductInput {
    pub code: String,
    pub name: String,
    #[serde(default)]
    pub description: String,
    #[serde(default = "default_unit")]
    pub unit: String,
    /// `purchased | manufactured | configurable | service`
    #[serde(default = "default_product_type")]
    pub product_type: String,
    /// Explicit VAT rate (kept for backwards compatibility).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub vat_rate: Option<Decimal>,
    /// `standard` (default), `intermediate`, `reduced`, or `zero`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub vat_category: Option<String>,
    /// Optional explicit VAT rate override (`None` / `null` clears any previous override).
    #[serde(default)]
    pub vat_rate_override: Option<Decimal>,
    /// `none | serial | lot`. Services are not tracked.
    #[serde(default = "default_tracking")]
    pub tracking: String,
    #[serde(default)]
    pub family_id: Option<Uuid>,
    #[serde(default)]
    pub non_discountable: bool,
    #[serde(default)]
    pub price_on_request: bool,
    #[serde(default)]
    pub price_is_indicative: bool,
    /// Whether this product contributes to turnover-based rebates. On update, `None` omits the
    /// field (preserving stored classification) while `Some(None)` sends `null` to clear it.
    #[serde(
        default,
        skip_serializing_if = "Option::is_none",
        deserialize_with = "deserialize_double_option"
    )]
    pub included_in_turnover: Option<Option<bool>>,
    #[serde(default = "default_true")]
    pub active: bool,
    #[serde(default)]
    pub standard_cost: Option<Decimal>,
    #[serde(default)]
    pub reorder_min: Option<Decimal>,
    #[serde(default)]
    pub reorder_max: Option<Decimal>,
    #[serde(default)]
    pub order_multiple: Option<Decimal>,
    #[serde(default)]
    pub safety_stock: Option<Decimal>,
    #[serde(default)]
    pub lead_time_days: Option<i32>,
    #[serde(default)]
    pub barcode: Option<String>,
    #[serde(default)]
    pub packaging_category_id: Option<Uuid>,
    #[serde(default)]
    pub length_mm: Option<i32>,
    #[serde(default)]
    pub width_mm: Option<i32>,
    #[serde(default)]
    pub height_mm: Option<i32>,
    #[serde(default)]
    pub weight_g: Option<i32>,
    #[serde(default)]
    pub default_production_remark: String,
}

/// Request payload for `POST /api/v1/products`.
pub type CreateProductRequest = ProductInput;

/// Request payload for `PUT /api/v1/products/{id}`.
pub type UpdateProductRequest = ProductInput;

fn default_unit() -> String {
    "pcs".to_string()
}

fn default_product_type() -> String {
    "purchased".to_string()
}

fn default_tracking() -> String {
    "none".to_string()
}

fn default_true() -> bool {
    true
}

fn deserialize_double_option<'de, D>(deserializer: D) -> Result<Option<Option<bool>>, D::Error>
where
    D: serde::Deserializer<'de>,
{
    Option::<bool>::deserialize(deserializer).map(Some)
}

impl Default for ProductInput {
    fn default() -> Self {
        Self {
            code: String::new(),
            name: String::new(),
            description: String::new(),
            unit: default_unit(),
            product_type: default_product_type(),
            vat_rate: None,
            vat_category: Some("standard".to_string()),
            vat_rate_override: None,
            tracking: default_tracking(),
            family_id: None,
            non_discountable: false,
            price_on_request: false,
            price_is_indicative: false,
            included_in_turnover: None,
            active: true,
            standard_cost: None,
            reorder_min: None,
            reorder_max: None,
            order_multiple: None,
            safety_stock: None,
            lead_time_days: None,
            barcode: None,
            packaging_category_id: None,
            length_mm: None,
            width_mm: None,
            height_mm: None,
            weight_g: None,
            default_production_remark: String::new(),
        }
    }
}

impl From<&Product> for ProductInput {
    fn from(product: &Product) -> Self {
        Self {
            code: product.code.clone(),
            name: product.name.clone(),
            description: product.description.clone(),
            unit: product.unit.clone(),
            product_type: product.product_type.clone(),
            vat_rate: None,
            vat_category: (!product.vat_category.trim().is_empty())
                .then(|| product.vat_category.clone()),
            vat_rate_override: product.vat_rate_override,
            tracking: product.tracking.clone(),
            family_id: product.family_id,
            non_discountable: product.non_discountable,
            price_on_request: product.price_on_request,
            price_is_indicative: product.price_is_indicative,
            included_in_turnover: Some(product.included_in_turnover),
            active: product.active,
            standard_cost: product.standard_cost,
            reorder_min: product.reorder_min,
            reorder_max: product.reorder_max,
            order_multiple: product.order_multiple,
            safety_stock: product.safety_stock,
            lead_time_days: product.lead_time_days,
            barcode: product.barcode.clone(),
            packaging_category_id: product.packaging_category_id,
            length_mm: product.length_mm,
            width_mm: product.width_mm,
            height_mm: product.height_mm,
            weight_g: product.weight_g,
            default_production_remark: product.default_production_remark.clone(),
        }
    }
}

/// Paginated response from `GET /api/v1/products`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProductPage {
    pub items: Vec<Product>,
    pub total: i64,
}

/// Query parameters for `GET /api/v1/products`.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
pub struct ListProductsParams {
    /// Searches code and name, ignoring case and accents.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub q: Option<String>,
    /// Exact product code match.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub code: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub active: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub family_id: Option<Uuid>,
    /// Comma-separated list of product types (`purchased`, `manufactured`, `configurable`, `service`).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub product_type: Option<String>,
    /// Sort order (`field` or `-field`, up to 3 comma-separated keys).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sort: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub limit: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub offset: Option<i64>,
}

impl ListProductsParams {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn q(mut self, q: impl Into<String>) -> Self {
        self.q = Some(q.into());
        self
    }

    pub fn active(mut self, active: bool) -> Self {
        self.active = Some(active);
        self
    }

    pub fn limit(mut self, limit: i64) -> Self {
        self.limit = Some(limit);
        self
    }

    pub fn offset(mut self, offset: i64) -> Self {
        self.offset = Some(offset);
        self
    }

    pub fn sort(mut self, sort: impl Into<String>) -> Self {
        self.sort = Some(sort.into());
        self
    }
}

impl Client {
    /// Lists products matching `params` (`GET /api/v1/products`).
    pub async fn list_products(
        &self,
        params: &ListProductsParams,
    ) -> Result<ProductPage, ApiError> {
        self.get_json("/api/v1/products", params).await
    }

    /// Fetches a single product by ID (`GET /api/v1/products/{id}`).
    pub async fn get_product(&self, id: Uuid) -> Result<Product, ApiError> {
        self.get_json(&format!("/api/v1/products/{id}"), &()).await
    }

    /// Creates a new product (`POST /api/v1/products`).
    pub async fn create_product(&self, req: &CreateProductRequest) -> Result<Product, ApiError> {
        self.post_json("/api/v1/products", req).await
    }

    /// Updates an existing product (`PUT /api/v1/products/{id}`).
    pub async fn update_product(
        &self,
        id: Uuid,
        req: &UpdateProductRequest,
    ) -> Result<Product, ApiError> {
        self.put_json(&format!("/api/v1/products/{id}"), req).await
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PackagingCategory {
    pub active: bool,
    pub code: String,
    pub description: String,
    pub id: Uuid,
    pub name: String,
    pub product_count: i64,
    pub requires_shipping_quote: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PackagingCategoryInput {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub active: Option<bool>,
    pub code: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    pub name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub requires_shipping_quote: Option<bool>,
}

/// One grid of a country, e.g. 230 V single phase at 50 Hz.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PowerGrid {
    pub active: bool,
    pub country_code: String,
    pub frequency_hz: i32,
    pub id: Uuid,
    pub name: String,
    pub phases: i32,
    pub voltage_v: i32,
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct ListPowerGridsParams {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub country: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PowerGridInput {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub active: Option<bool>,
    pub country_code: String,
    pub frequency_hz: i32,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    pub phases: i32,
    pub voltage_v: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BulkPricePreview {
    pub applied: i64,
    pub conflicts: i64,
    pub lines: Vec<BulkPriceLine>,
    pub valid_from: chrono::NaiveDate,
    pub without_price: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BulkPriceLine {
    pub conflict: bool,
    pub current_price: String,
    pub current_valid_from: chrono::NaiveDate,
    pub new_price: String,
    pub product_code: String,
    pub product_id: Uuid,
    pub product_name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub replaced_price: Option<String>,
    pub zone_code: String,
    pub zone_id: Uuid,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BulkPriceChangeInput {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub family_id: Option<Uuid>,
    pub kind: ChangeKind,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub product_ids: Option<Vec<Uuid>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub replace_planned: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub rounding: Option<String>,
    pub valid_from: chrono::NaiveDate,
    pub value: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub zone_ids: Option<Vec<Uuid>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ChangeKind {
    #[serde(rename = "percent")]
    Percent,
    #[serde(rename = "amount")]
    Amount,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProductFamily {
    pub active: bool,
    pub code: String,
    pub id: Uuid,
    pub name: String,
    pub product_count: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProductFamilyInput {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub active: Option<bool>,
    pub code: String,
    pub name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProductRelation {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub a_family_code: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub a_family_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub a_product_code: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub a_product_id: Option<Uuid>,
    pub active: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub b_family_code: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub b_family_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub b_product_code: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub b_product_id: Option<Uuid>,
    pub bidirectional: bool,
    pub id: Uuid,
    pub kind: String,
    pub note: String,
    pub strength: i32,
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct ListProductRelationsParams {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub product_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub family_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub kind: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProductRelationInput {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub a_family_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub a_product_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub active: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub b_family_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub b_product_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bidirectional: Option<bool>,
    pub kind: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub note: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub strength: Option<i32>,
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct ExportProductsParams {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub format: Option<String>,
}

/// The response of a groups endpoint, ordered by value.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GroupPage {
    pub group_by: String,
    pub groups: Vec<GroupCount>,
}

/// The rows of one group.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GroupCount {
    pub count: i64,
    pub value: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct ProductGroupsParams {
    pub group_by: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub q: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub code: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub active: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub family_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub product_type: Option<String>,
}

/// Outcome of an import (or of its dry run). `errors` is empty on success; with errors nothing was
/// written and the counts are 0.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ImportReport {
    pub created: u64,
    pub errors: Vec<RowError>,
    pub unchanged: u64,
    pub updated: u64,
}

/// One problem in an import file.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RowError {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub column: Option<String>,
    pub message: String,
    pub row: u64,
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct ImportProductsParams {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub dry_run: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sheet: Option<String>,
}

/// One attribute. `value` is text in JSON: a decimal for `number` (e.g. `"0.55"`), `true` or
/// `false` for `boolean`. A `range` uses `value_min` and `value_max` (decimals) instead; its
/// `value` is ignored on input and shown as `min..max` on output.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProductAttribute {
    pub key: String,
    pub kind: AttributeKind,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub unit: Option<String>,
    pub value: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub value_max: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub value_min: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum AttributeKind {
    #[serde(rename = "number")]
    Number,
    #[serde(rename = "text")]
    Text,
    #[serde(rename = "boolean")]
    Boolean,
    #[serde(rename = "range")]
    Range,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProductMedia {
    pub caption: String,
    pub content_type: String,
    pub created_at: chrono::DateTime<chrono::Utc>,
    pub filename: String,
    pub id: Uuid,
    pub is_default: bool,
    pub kind: String,
    pub size_bytes: i32,
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct UploadProductMediaParams {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub caption: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub filename: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub client_id: Option<Uuid>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MediaUpdate {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub caption: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub is_default: Option<bool>,
}

/// An option of a product, with the option product's code and name.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProductOption {
    pub active: bool,
    pub default_quantity: String,
    pub option_active: bool,
    pub option_code: String,
    pub option_name: String,
    pub option_product_id: Uuid,
    pub required: bool,
    pub sort_order: i32,
}

/// One option as set from the product screen.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProductOptionInput {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub active: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub default_quantity: Option<String>,
    pub option_product_id: Uuid,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub required: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sort_order: Option<i32>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PowerCompatibilityReport {
    pub available: Vec<PowerGrid>,
    pub country_code: String,
    pub status: PowerStatus,
    pub supported: Vec<PowerSupply>,
}

/// Machine-readable status of a [`PowerCompatibility`].
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum PowerStatus {
    #[serde(rename = "not_applicable")]
    NotApplicable,
    #[serde(rename = "needs_external_supply")]
    NeedsExternalSupply,
    #[serde(rename = "compatible")]
    Compatible,
    #[serde(rename = "incompatible")]
    Incompatible,
    #[serde(rename = "unknown_grid")]
    UnknownGrid,
}

/// A way to power a product.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PowerSupply {
    pub current_type: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub frequency_hz: Option<i32>,
    pub id: Uuid,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub phases: Option<i32>,
    pub tolerance_pct: i32,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub voltage_max_v: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub voltage_min_v: Option<i32>,
    pub voltage_v: i32,
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct GetProductPowerCompatibilityParams {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub country: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub grid_id: Option<Uuid>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PowerSupplyInput {
    pub current_type: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub frequency_hz: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub phases: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tolerance_pct: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub voltage_max_v: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub voltage_min_v: Option<i32>,
    pub voltage_v: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ZonePriceEntry {
    pub id: Uuid,
    pub unit_price: String,
    pub valid_from: chrono::NaiveDate,
    pub zone_code: String,
    pub zone_id: Uuid,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ZonePriceInput {
    pub unit_price: String,
    pub valid_from: chrono::NaiveDate,
    pub zone_id: Uuid,
}

/// A correction of a zone price that has not started yet.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ZonePriceCorrection {
    pub unit_price: String,
    pub valid_from: chrono::NaiveDate,
}

/// What the rules and the order history say about one product.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RelatedProducts {
    pub rules: Vec<ProductRelation>,
    pub suggestions: Vec<Suggestion>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Suggestion {
    pub because_of_code: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub confidence: Option<f64>,
    pub note: String,
    pub product_code: String,
    pub product_id: Uuid,
    pub product_name: String,
    pub reason: SuggestionReason,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub strength: Option<i32>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum SuggestionReason {
    #[serde(rename = "rule")]
    Rule,
    #[serde(rename = "often_bought_together")]
    OftenBoughtTogether,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProductTranslation {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    pub language: String,
    pub name: String,
}

impl Client {
    /// `GET /api/v1/packaging-categories`.
    pub async fn list_packaging(&self) -> Result<Vec<PackagingCategory>, ApiError> {
        self.get_json("/api/v1/packaging-categories", &()).await
    }

    /// `POST /api/v1/packaging-categories`.
    pub async fn create_packaging(
        &self,
        body: &PackagingCategoryInput,
    ) -> Result<PackagingCategory, ApiError> {
        self.post_json("/api/v1/packaging-categories", body).await
    }

    /// `PUT /api/v1/packaging-categories/{id}`.
    pub async fn update_packaging(
        &self,
        id: Uuid,
        body: &PackagingCategoryInput,
    ) -> Result<PackagingCategory, ApiError> {
        self.put_json(&format!("/api/v1/packaging-categories/{id}"), body)
            .await
    }

    /// `GET /api/v1/power-grids`.
    pub async fn list_power_grids(
        &self,
        params: &ListPowerGridsParams,
    ) -> Result<Vec<PowerGrid>, ApiError> {
        self.get_json("/api/v1/power-grids", params).await
    }

    /// `POST /api/v1/power-grids`.
    pub async fn create_power_grid(&self, body: &PowerGridInput) -> Result<PowerGrid, ApiError> {
        self.post_json("/api/v1/power-grids", body).await
    }

    /// `PUT /api/v1/power-grids/{id}`.
    pub async fn update_power_grid(
        &self,
        id: Uuid,
        body: &PowerGridInput,
    ) -> Result<PowerGrid, ApiError> {
        self.put_json(&format!("/api/v1/power-grids/{id}"), body)
            .await
    }

    /// `POST /api/v1/prices/bulk/apply`.
    pub async fn apply_bulk_prices(
        &self,
        body: &BulkPriceChangeInput,
    ) -> Result<BulkPricePreview, ApiError> {
        self.post_json("/api/v1/prices/bulk/apply", body).await
    }

    /// `POST /api/v1/prices/bulk/preview`.
    pub async fn preview_bulk_prices(
        &self,
        body: &BulkPriceChangeInput,
    ) -> Result<BulkPricePreview, ApiError> {
        self.post_json("/api/v1/prices/bulk/preview", body).await
    }

    /// `GET /api/v1/product-families`.
    pub async fn list_families(&self) -> Result<Vec<ProductFamily>, ApiError> {
        self.get_json("/api/v1/product-families", &()).await
    }

    /// `POST /api/v1/product-families`.
    pub async fn create_family(
        &self,
        body: &ProductFamilyInput,
    ) -> Result<ProductFamily, ApiError> {
        self.post_json("/api/v1/product-families", body).await
    }

    /// `PUT /api/v1/product-families/{id}`.
    pub async fn update_family(
        &self,
        id: Uuid,
        body: &ProductFamilyInput,
    ) -> Result<ProductFamily, ApiError> {
        self.put_json(&format!("/api/v1/product-families/{id}"), body)
            .await
    }

    /// `GET /api/v1/product-relations`.
    pub async fn list_product_relations(
        &self,
        params: &ListProductRelationsParams,
    ) -> Result<Vec<ProductRelation>, ApiError> {
        self.get_json("/api/v1/product-relations", params).await
    }

    /// `POST /api/v1/product-relations`.
    pub async fn create_product_relation(
        &self,
        body: &ProductRelationInput,
    ) -> Result<ProductRelation, ApiError> {
        self.post_json("/api/v1/product-relations", body).await
    }

    /// `PUT /api/v1/product-relations/{id}`.
    pub async fn update_product_relation(
        &self,
        id: Uuid,
        body: &ProductRelationInput,
    ) -> Result<ProductRelation, ApiError> {
        self.put_json(&format!("/api/v1/product-relations/{id}"), body)
            .await
    }

    /// `GET /api/v1/products/export`.
    pub async fn export_products(
        &self,
        params: &ExportProductsParams,
    ) -> Result<Vec<u8>, ApiError> {
        self.get_bytes_with_query("/api/v1/products/export", params)
            .await
    }

    /// `GET /api/v1/products/groups`.
    pub async fn product_groups(
        &self,
        params: &ProductGroupsParams,
    ) -> Result<GroupPage, ApiError> {
        self.get_json("/api/v1/products/groups", params).await
    }

    /// `POST /api/v1/products/import`.
    pub async fn import_products(
        &self,
        params: &ImportProductsParams,
        body: Vec<u8>,
    ) -> Result<ImportReport, ApiError> {
        self.post_bytes("/api/v1/products/import", params, body)
            .await
    }

    /// `GET /api/v1/products/{id}/attributes`.
    pub async fn list_product_attributes(
        &self,
        id: Uuid,
    ) -> Result<Vec<ProductAttribute>, ApiError> {
        self.get_json(&format!("/api/v1/products/{id}/attributes"), &())
            .await
    }

    /// `PUT /api/v1/products/{id}/attributes`.
    pub async fn replace_product_attributes(
        &self,
        id: Uuid,
        body: &Vec<ProductAttribute>,
    ) -> Result<Vec<ProductAttribute>, ApiError> {
        self.put_json(&format!("/api/v1/products/{id}/attributes"), body)
            .await
    }

    /// `GET /api/v1/products/{id}/media`.
    pub async fn list_product_media(&self, id: Uuid) -> Result<Vec<ProductMedia>, ApiError> {
        self.get_json(&format!("/api/v1/products/{id}/media"), &())
            .await
    }

    /// `POST /api/v1/products/{id}/media`.
    pub async fn upload_product_media(
        &self,
        id: Uuid,
        params: &UploadProductMediaParams,
        body: Vec<u8>,
    ) -> Result<ProductMedia, ApiError> {
        self.post_bytes(&format!("/api/v1/products/{id}/media"), params, body)
            .await
    }

    /// `GET /api/v1/products/{id}/media/default`.
    pub async fn get_product_default_media(&self, id: Uuid) -> Result<Vec<u8>, ApiError> {
        self.get_bytes_with_query(&format!("/api/v1/products/{id}/media/default"), &())
            .await
    }

    /// `GET /api/v1/products/{id}/media/{media_id}`.
    pub async fn get_product_media(&self, id: Uuid, media_id: Uuid) -> Result<Vec<u8>, ApiError> {
        self.get_bytes_with_query(&format!("/api/v1/products/{id}/media/{media_id}"), &())
            .await
    }

    /// `DELETE /api/v1/products/{id}/media/{media_id}`.
    pub async fn delete_product_media(&self, id: Uuid, media_id: Uuid) -> Result<(), ApiError> {
        self.delete_empty(&format!("/api/v1/products/{id}/media/{media_id}"))
            .await
    }

    /// `PATCH /api/v1/products/{id}/media/{media_id}`.
    pub async fn update_product_media(
        &self,
        id: Uuid,
        media_id: Uuid,
        body: &MediaUpdate,
    ) -> Result<ProductMedia, ApiError> {
        self.patch_json(&format!("/api/v1/products/{id}/media/{media_id}"), body)
            .await
    }

    /// `GET /api/v1/products/{id}/options`.
    pub async fn list_product_options(&self, id: Uuid) -> Result<Vec<ProductOption>, ApiError> {
        self.get_json(&format!("/api/v1/products/{id}/options"), &())
            .await
    }

    /// `PUT /api/v1/products/{id}/options`.
    pub async fn replace_product_options(
        &self,
        id: Uuid,
        body: &Vec<ProductOptionInput>,
    ) -> Result<Vec<ProductOption>, ApiError> {
        self.put_json(&format!("/api/v1/products/{id}/options"), body)
            .await
    }

    /// `GET /api/v1/products/{id}/power-compatibility`.
    pub async fn get_product_power_compatibility(
        &self,
        id: Uuid,
        params: &GetProductPowerCompatibilityParams,
    ) -> Result<PowerCompatibilityReport, ApiError> {
        self.get_json(
            &format!("/api/v1/products/{id}/power-compatibility"),
            params,
        )
        .await
    }

    /// `GET /api/v1/products/{id}/power-supplies`.
    pub async fn get_product_power_supplies(&self, id: Uuid) -> Result<Vec<PowerSupply>, ApiError> {
        self.get_json(&format!("/api/v1/products/{id}/power-supplies"), &())
            .await
    }

    /// `PUT /api/v1/products/{id}/power-supplies`.
    pub async fn replace_product_power_supplies(
        &self,
        id: Uuid,
        body: &Vec<PowerSupplyInput>,
    ) -> Result<Vec<PowerSupply>, ApiError> {
        self.put_json(&format!("/api/v1/products/{id}/power-supplies"), body)
            .await
    }

    /// `GET /api/v1/products/{id}/prices`.
    pub async fn list_product_prices(&self, id: Uuid) -> Result<Vec<ZonePriceEntry>, ApiError> {
        self.get_json(&format!("/api/v1/products/{id}/prices"), &())
            .await
    }

    /// `POST /api/v1/products/{id}/prices`.
    pub async fn add_product_price(
        &self,
        id: Uuid,
        body: &ZonePriceInput,
    ) -> Result<ZonePriceEntry, ApiError> {
        self.post_json(&format!("/api/v1/products/{id}/prices"), body)
            .await
    }

    /// `PUT /api/v1/products/{id}/prices/{price_id}`.
    pub async fn correct_product_price(
        &self,
        id: Uuid,
        price_id: Uuid,
        body: &ZonePriceCorrection,
    ) -> Result<ZonePriceEntry, ApiError> {
        self.put_json(&format!("/api/v1/products/{id}/prices/{price_id}"), body)
            .await
    }

    /// `DELETE /api/v1/products/{id}/prices/{price_id}`.
    pub async fn delete_product_price(&self, id: Uuid, price_id: Uuid) -> Result<(), ApiError> {
        self.delete_empty(&format!("/api/v1/products/{id}/prices/{price_id}"))
            .await
    }

    /// `GET /api/v1/products/{id}/related`.
    pub async fn get_related_products(&self, id: Uuid) -> Result<RelatedProducts, ApiError> {
        self.get_json(&format!("/api/v1/products/{id}/related"), &())
            .await
    }

    /// `GET /api/v1/products/{id}/translations`.
    pub async fn list_product_translations(
        &self,
        id: Uuid,
    ) -> Result<Vec<ProductTranslation>, ApiError> {
        self.get_json(&format!("/api/v1/products/{id}/translations"), &())
            .await
    }

    /// `PUT /api/v1/products/{id}/translations`.
    pub async fn replace_product_translations(
        &self,
        id: Uuid,
        body: &Vec<ProductTranslation>,
    ) -> Result<Vec<ProductTranslation>, ApiError> {
        self.put_json(&format!("/api/v1/products/{id}/translations"), body)
            .await
    }
}

#[cfg(test)]
mod tests {
    use std::str::FromStr;

    use super::*;

    #[test]
    fn deserialize_product_page() {
        let json = r#"{
            "total": 1,
            "items": [
                {
                    "id": "01900000-0000-7000-8000-000000000100",
                    "code": "PUMP-100",
                    "name": "Circulation Pump 100W",
                    "description": "High-efficiency circulation pump",
                    "unit": "pcs",
                    "product_type": "manufactured",
                    "vat_rate": "21",
                    "vat_category": "standard",
                    "vat_rate_override": null,
                    "tracking": "serial",
                    "family_id": "01900000-0000-7000-8000-000000000200",
                    "family_code": "PUMPS",
                    "non_discountable": false,
                    "price_on_request": false,
                    "price_is_indicative": false,
                    "included_in_turnover": true,
                    "active": true,
                    "default_media_id": null,
                    "default_media_kind": null,
                    "standard_cost": "42.5000",
                    "reorder_min": "10",
                    "reorder_max": "40",
                    "lead_time_days": 7,
                    "barcode": "5412345678901",
                    "packaging_category_id": null,
                    "packaging_category_code": null,
                    "length_mm": 300,
                    "width_mm": 200,
                    "height_mm": 180,
                    "weight_g": 4200,
                    "default_production_remark": "Test pressure before shipping"
                }
            ]
        }"#;
        let page: ProductPage = serde_json::from_str(json).unwrap();
        assert_eq!(page.total, 1);
        assert_eq!(page.items.len(), 1);
        let p = &page.items[0];
        assert_eq!(p.code, "PUMP-100");
        assert_eq!(p.vat_rate, Decimal::from_str("21").unwrap());
        assert_eq!(p.standard_cost, Some(Decimal::from_str("42.5000").unwrap()));
        assert_eq!(p.reorder_min, Some(Decimal::from(10)));
        assert_eq!(p.lead_time_days, Some(7));
    }

    #[test]
    fn list_products_params_serialize_only_set_fields() {
        let params = ListProductsParams::new().q("pump").limit(25);
        let req = reqwest::Client::new()
            .get("http://localhost:8080/api/v1/products")
            .query(&params)
            .build()
            .unwrap();
        assert_eq!(req.url().query(), Some("q=pump&limit=25"));
    }

    #[test]
    fn create_and_update_product_request_serialize_defaults_and_tri_state() {
        let create_req = CreateProductRequest {
            code: "VALVE-10".to_string(),
            name: "Ball Valve DN10".to_string(),
            ..CreateProductRequest::default()
        };
        let value = serde_json::to_value(&create_req).unwrap();
        assert_eq!(value["code"], "VALVE-10");
        assert_eq!(value["unit"], "pcs");
        assert_eq!(value["product_type"], "purchased");
        assert_eq!(value["tracking"], "none");
        assert_eq!(value["vat_category"], "standard");
        assert_eq!(value["active"], true);
        assert!(value.get("included_in_turnover").is_none());
        assert!(value.get("vat_rate").is_none());

        let clear_turnover = UpdateProductRequest {
            included_in_turnover: Some(None),
            ..create_req
        };
        let cleared = serde_json::to_value(&clear_turnover).unwrap();
        assert_eq!(cleared["included_in_turnover"], serde_json::Value::Null);

        let roundtrip: UpdateProductRequest = serde_json::from_value(cleared).unwrap();
        assert_eq!(roundtrip.included_in_turnover, Some(None));
    }

    #[test]
    fn product_input_from_product_preserves_editable_fields() {
        let product = Product {
            id: Uuid::nil(),
            code: "PUMP-100".to_string(),
            name: "Circulation Pump".to_string(),
            description: "High-efficiency".to_string(),
            unit: "pcs".to_string(),
            product_type: "manufactured".to_string(),
            vat_rate: Decimal::from(21),
            vat_category: "standard".to_string(),
            vat_rate_override: Some(Decimal::from(12)),
            tracking: "serial".to_string(),
            family_id: None,
            family_code: Some("PUMPS".to_string()),
            non_discountable: true,
            price_on_request: false,
            price_is_indicative: true,
            included_in_turnover: Some(false),
            active: true,
            default_media_id: None,
            default_media_kind: None,
            standard_cost: Some(Decimal::from_str("42.50").unwrap()),
            reorder_min: Some(Decimal::from(5)),
            reorder_max: Some(Decimal::from(20)),
            order_multiple: None,
            safety_stock: None,
            lead_time_days: Some(7),
            barcode: Some("5412345678901".to_string()),
            packaging_category_id: None,
            packaging_category_code: None,
            length_mm: Some(300),
            width_mm: Some(200),
            height_mm: Some(180),
            weight_g: Some(4200),
            default_production_remark: "Check seal".to_string(),
        };

        let update = UpdateProductRequest::from(&product);
        assert_eq!(update.code, "PUMP-100");
        assert_eq!(update.vat_category.as_deref(), Some("standard"));
        assert_eq!(update.vat_rate_override, Some(Decimal::from(12)));
        assert_eq!(update.included_in_turnover, Some(Some(false)));
        assert_eq!(update.lead_time_days, Some(7));
        assert_eq!(update.default_production_remark, "Check seal");
        assert!(update.vat_rate.is_none());
    }
}
