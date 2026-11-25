//! Sales DTOs and endpoints (`/api/v1/quotations`, `/api/v1/orders`).

use std::fmt;
use std::str::FromStr;

use chrono::{DateTime, NaiveDate, Utc};
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::client::Client;
use crate::error::ApiError;

/// Lifecycle status of a quotation (`draft`, `sent`, `accepted`, `rejected`, `superseded`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum QuotationStatus {
    Draft,
    Sent,
    Accepted,
    Rejected,
    Superseded,
}

impl QuotationStatus {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Draft => "draft",
            Self::Sent => "sent",
            Self::Accepted => "accepted",
            Self::Rejected => "rejected",
            Self::Superseded => "superseded",
        }
    }
}

impl fmt::Display for QuotationStatus {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}

impl FromStr for QuotationStatus {
    type Err = String;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s.trim() {
            "draft" => Ok(Self::Draft),
            "sent" => Ok(Self::Sent),
            "accepted" => Ok(Self::Accepted),
            "rejected" => Ok(Self::Rejected),
            "superseded" => Ok(Self::Superseded),
            other => Err(format!("unknown quotation status: {other}")),
        }
    }
}

/// Which price of the parent line a percent-of-parent line is computed from.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PercentBase {
    ParentListUnitPrice,
    ParentNetUnitPrice,
}

impl PercentBase {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::ParentListUnitPrice => "parent_list_unit_price",
            Self::ParentNetUnitPrice => "parent_net_unit_price",
        }
    }
}

impl fmt::Display for PercentBase {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}

/// Summary row returned in `GET /api/v1/quotations`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct QuotationSummary {
    pub id: Uuid,
    pub number: String,
    pub revision: i32,
    pub status: QuotationStatus,
    pub customer_id: Uuid,
    pub customer_name: String,
    #[serde(default)]
    pub opportunity_id: Option<Uuid>,
    /// `installation` | `stock`
    pub purpose: String,
    /// `not_required` | `pending` | `quoted`
    pub shipping_status: String,
    pub quote_date: NaiveDate,
    pub valid_until: NaiveDate,
    pub currency: String,
    pub subtotal: Decimal,
    pub total: Decimal,
}

/// Paginated response from `GET /api/v1/quotations`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct QuotationPage {
    pub items: Vec<QuotationSummary>,
    pub total: i64,
}

/// VAT breakdown group on a quotation.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct VatGroup {
    pub vat_rate: Decimal,
    pub base: Decimal,
    pub vat: Decimal,
}

/// Non-blocking hint about a quotation or order line.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SalesWarning {
    /// `power_grid` | `incompatible_products`
    pub kind: String,
    pub product_code: String,
    pub message: String,
    pub details: serde_json::Value,
}

/// Suggested complementary product on a quotation or order.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SalesSuggestion {
    pub product_id: Uuid,
    pub product_code: String,
    pub product_name: String,
    /// `rule` | `often_bought_together`
    pub reason: String,
    pub because_of_code: String,
    #[serde(default)]
    pub strength: Option<i32>,
    #[serde(default)]
    pub confidence: Option<f64>,
    pub note: String,
}

/// Line item on a [`Quotation`].
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct QuotationLine {
    pub position: i32,
    #[serde(default)]
    pub product_id: Option<Uuid>,
    pub product_code: String,
    pub description: String,
    pub unit: String,
    pub quantity: Decimal,
    pub list_unit_price: Decimal,
    pub non_discountable: bool,
    pub price_on_request: bool,
    pub price_is_indicative: bool,
    pub rebate_percent: Decimal,
    /// `product` | `family` | `general` | `net`
    pub rebate_source: String,
    pub line_discount_percent: Decimal,
    pub net_unit_price: Decimal,
    pub line_total: Decimal,
    pub vat_rate: Decimal,
    pub price_confirmed: bool,
    #[serde(default)]
    pub section: Option<String>,
    #[serde(default)]
    pub parent_position: Option<i32>,
    #[serde(default)]
    pub percent_of_parent: Option<Decimal>,
    #[serde(default)]
    pub percent_base: Option<String>,
    #[serde(default)]
    pub comment: Option<String>,
    #[serde(default)]
    pub customer_remark: String,
    #[serde(default)]
    pub customer_remark_language: Option<String>,
    #[serde(default)]
    pub production_remark: String,
    #[serde(default)]
    pub favorite_item_id: Option<Uuid>,
}

/// Detailed quotation returned by `GET /api/v1/quotations/{id}`, `POST /api/v1/quotations`,
/// `PUT /api/v1/quotations/{id}`, `POST /api/v1/quotations/{id}/send`, and
/// `POST /api/v1/quotations/{id}/accept`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Quotation {
    pub id: Uuid,
    pub company_id: Uuid,
    pub number: String,
    pub revision: i32,
    #[serde(default)]
    pub supersedes_id: Option<Uuid>,
    pub status: QuotationStatus,
    pub customer_id: Uuid,
    pub customer_name: String,
    #[serde(default)]
    pub customer_vat_number: Option<String>,
    pub vat_regime: String,
    #[serde(default)]
    pub vat_regime_override: Option<String>,
    pub customer_street: String,
    pub customer_postal_code: String,
    pub customer_city: String,
    pub customer_country_code: String,
    pub customer_language: String,
    pub price_zone_code: String,
    pub customer_discount_percent: Decimal,
    #[serde(default)]
    pub opportunity_id: Option<Uuid>,
    pub purpose: String,
    #[serde(default)]
    pub delivery_country_code: Option<String>,
    #[serde(default)]
    pub power_grid_id: Option<Uuid>,
    #[serde(default)]
    pub building_construction_year: Option<i32>,
    pub shipping_status: String,
    pub currency: String,
    pub quote_date: NaiveDate,
    pub price_date: NaiveDate,
    pub valid_until: NaiveDate,
    #[serde(default)]
    pub sent_at: Option<DateTime<Utc>>,
    pub notes: String,
    pub subtotal: Decimal,
    pub vat_total: Decimal,
    pub total: Decimal,
    #[serde(default)]
    pub version: i64,
    pub created_by: Uuid,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub lines: Vec<QuotationLine>,
    pub vat_groups: Vec<VatGroup>,
    #[serde(default)]
    pub warnings: Vec<SalesWarning>,
    #[serde(default)]
    pub suggestions: Vec<SalesSuggestion>,
}

/// Line input payload inside [`QuotationInput`].
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct QuotationLineInput {
    pub product_id: Uuid,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    pub quantity: Decimal,
    #[serde(default)]
    pub line_discount_percent: Decimal,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub unit_price: Option<Decimal>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub vat_rate: Option<Decimal>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub section: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub parent_position: Option<i32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub percent_of_parent: Option<Decimal>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub percent_base: Option<PercentBase>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub comment: Option<String>,
    #[serde(default)]
    pub customer_remark: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub customer_remark_language: Option<String>,
    #[serde(default)]
    pub production_remark: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub favorite_item_id: Option<Uuid>,
    #[serde(default)]
    pub add_options: bool,
}

impl Default for QuotationLineInput {
    fn default() -> Self {
        Self {
            product_id: Uuid::nil(),
            description: None,
            quantity: Decimal::ONE,
            line_discount_percent: Decimal::ZERO,
            unit_price: None,
            vat_rate: None,
            section: None,
            parent_position: None,
            percent_of_parent: None,
            percent_base: None,
            comment: None,
            customer_remark: String::new(),
            customer_remark_language: None,
            production_remark: String::new(),
            favorite_item_id: None,
            add_options: false,
        }
    }
}

/// Request payload for `POST /api/v1/quotations` and `PUT /api/v1/quotations/{id}`
/// (OpenAPI schema `QuotationInput`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct QuotationInput {
    pub customer_id: Uuid,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub opportunity_id: Option<Uuid>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub quote_date: Option<NaiveDate>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub price_date: Option<NaiveDate>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub valid_days: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub purpose: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub delivery_country_code: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub power_grid_id: Option<Uuid>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub clear_power_grid: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub building_construction_year: Option<i32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub clear_building_construction_year: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub vat_regime_override: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub clear_vat_regime_override: Option<bool>,
    #[serde(default)]
    pub notes: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub expected_version: Option<i64>,
    pub lines: Vec<QuotationLineInput>,
}

impl Default for QuotationInput {
    fn default() -> Self {
        Self {
            customer_id: Uuid::nil(),
            opportunity_id: None,
            quote_date: None,
            price_date: None,
            valid_days: None,
            purpose: None,
            delivery_country_code: None,
            power_grid_id: None,
            clear_power_grid: None,
            building_construction_year: None,
            clear_building_construction_year: None,
            vat_regime_override: None,
            clear_vat_regime_override: None,
            notes: String::new(),
            expected_version: None,
            lines: Vec::new(),
        }
    }
}

/// Request payload for `POST /api/v1/quotations`.
pub type CreateQuotationRequest = QuotationInput;

/// Request payload for `PUT /api/v1/quotations/{id}`.
pub type UpdateQuotationRequest = QuotationInput;

/// Request payload for `POST /api/v1/quotations/{id}/convert`.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ConvertInput {
    #[serde(default)]
    pub customer_reference: String,
    #[serde(default)]
    pub notes: String,
}

/// Request payload for `POST /api/v1/quotations/{id}/convert`.
pub type ConvertQuotationRequest = ConvertInput;

/// Query parameters for `GET /api/v1/quotations`.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
pub struct ListQuotationsParams {
    /// Searches number and customer name.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub q: Option<String>,
    /// Comma-separated status list (`draft,sent`).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub status: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub customer_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub opportunity_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sort: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub limit: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub offset: Option<i64>,
}

impl ListQuotationsParams {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn q(mut self, q: impl Into<String>) -> Self {
        self.q = Some(q.into());
        self
    }

    pub fn status(mut self, status: impl Into<String>) -> Self {
        self.status = Some(status.into());
        self
    }

    pub fn customer_id(mut self, customer_id: Uuid) -> Self {
        self.customer_id = Some(customer_id);
        self
    }

    pub fn opportunity_id(mut self, opportunity_id: Uuid) -> Self {
        self.opportunity_id = Some(opportunity_id);
        self
    }

    pub fn sort(mut self, sort: impl Into<String>) -> Self {
        self.sort = Some(sort.into());
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
}

/// Summary record returned in `GET /api/v1/orders` and nested inside [`Order`].
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct OrderSummary {
    pub id: Uuid,
    pub number: String,
    pub status: String,
    /// `low` | `normal` | `expedite`
    pub priority: String,
    pub current_revision: i32,
    pub quotation_id: Uuid,
    pub quotation_number: String,
    pub quotation_revision: i32,
    pub customer_id: Uuid,
    pub customer_name: String,
    pub customer_reference: String,
    /// `installation` | `stock`
    pub purpose: String,
    #[serde(default)]
    pub delivery_country_code: Option<String>,
    #[serde(default)]
    pub power_grid_id: Option<Uuid>,
    #[serde(default)]
    pub building_construction_year: Option<i32>,
    #[serde(default)]
    pub vat_regime: String,
    pub order_date: NaiveDate,
    #[serde(default)]
    pub promised_date: Option<NaiveDate>,
    pub currency: String,
    pub subtotal: Decimal,
    pub total: Decimal,
    pub salesperson_id: Uuid,
    pub salesperson_name: String,
}

/// Paginated response from `GET /api/v1/orders`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct OrderPage {
    pub items: Vec<OrderSummary>,
    pub total: i64,
}

/// Revision history entry on an [`Order`].
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct OrderRevisionInfo {
    pub revision: i32,
    /// `draft` | `sent` | `confirmed` | `superseded`
    pub status: String,
    pub subtotal: Decimal,
    pub total: Decimal,
    pub created_at: DateTime<Utc>,
    #[serde(default)]
    pub sent_at: Option<DateTime<Utc>>,
    #[serde(default)]
    pub sent_to: Option<String>,
}

/// Line item on an [`Order`].
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct OrderLine {
    pub id: Uuid,
    pub position: i32,
    #[serde(default)]
    pub product_id: Option<Uuid>,
    pub product_code: String,
    pub description: String,
    pub unit: String,
    pub quantity: Decimal,
    pub list_unit_price: Decimal,
    pub non_discountable: bool,
    pub price_on_request: bool,
    pub price_is_indicative: bool,
    pub rebate_percent: Decimal,
    pub line_discount_percent: Decimal,
    pub net_unit_price: Decimal,
    pub line_total: Decimal,
    pub vat_rate: Decimal,
    #[serde(default)]
    pub customer_remark: String,
    #[serde(default)]
    pub production_remark: String,
}

/// Detailed order (latest revision + lines) returned by `GET /api/v1/orders/{id}`,
/// `POST /api/v1/quotations/{id}/convert`, `POST /api/v1/orders/{id}/send`, and
/// `POST /api/v1/orders/{id}/confirm`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Order {
    pub order: OrderSummary,
    pub revision: i32,
    pub revision_status: String,
    pub vat_total: Decimal,
    pub notes: String,
    #[serde(default)]
    pub version: i64,
    pub created_at: DateTime<Utc>,
    #[serde(default)]
    pub confirmed_at: Option<DateTime<Utc>>,
    #[serde(default)]
    pub confirmed_by: Option<Uuid>,
    #[serde(default)]
    pub confirmed_via: Option<String>,
    #[serde(default)]
    pub confirmed_revision: Option<i32>,
    pub confirmation_note: String,
    pub cancel_reason: String,
    pub revisions: Vec<OrderRevisionInfo>,
    pub lines: Vec<OrderLine>,
    #[serde(default)]
    pub warnings: Vec<SalesWarning>,
    #[serde(default)]
    pub suggestions: Vec<SalesSuggestion>,
}

/// Line edit payload inside [`OrderEditInput`].
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct OrderLineEdit {
    pub position: i32,
    pub quantity: Decimal,
    #[serde(default)]
    pub line_discount_percent: Decimal,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
}

/// Request payload for `PUT /api/v1/orders/{id}`.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct OrderEditInput {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub customer_reference: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub purpose: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub delivery_country_code: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub power_grid_id: Option<Uuid>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub clear_power_grid: Option<bool>,
    #[serde(default)]
    pub notes: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub expected_version: Option<i64>,
    pub lines: Vec<OrderLineEdit>,
}

/// Request payload for `POST /api/v1/orders/{id}/confirm`.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ConfirmOrderInput {
    #[serde(default)]
    pub note: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub revision: Option<i32>,
}

/// Request payload for `POST /api/v1/orders/{id}/confirm`.
pub type ConfirmOrderRequest = ConfirmOrderInput;

/// Query parameters for `GET /api/v1/orders`.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
pub struct ListOrdersParams {
    /// Searches order number, quotation number, customer name, and customer reference.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub q: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub customer_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub status: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub limit: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub offset: Option<i64>,
}

impl ListOrdersParams {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn q(mut self, q: impl Into<String>) -> Self {
        self.q = Some(q.into());
        self
    }

    pub fn customer_id(mut self, customer_id: Uuid) -> Self {
        self.customer_id = Some(customer_id);
        self
    }

    pub fn status(mut self, status: impl Into<String>) -> Self {
        self.status = Some(status.into());
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
}

impl Client {
    /// Lists quotations matching `params` (`GET /api/v1/quotations`).
    pub async fn list_quotations(
        &self,
        params: &ListQuotationsParams,
    ) -> Result<QuotationPage, ApiError> {
        self.get_json("/api/v1/quotations", params).await
    }

    /// Fetches a single quotation by ID (`GET /api/v1/quotations/{id}`).
    pub async fn get_quotation(&self, id: Uuid) -> Result<Quotation, ApiError> {
        self.get_json(&format!("/api/v1/quotations/{id}"), &())
            .await
    }

    /// Creates a new draft quotation (`POST /api/v1/quotations`).
    pub async fn create_quotation(
        &self,
        req: &CreateQuotationRequest,
    ) -> Result<Quotation, ApiError> {
        self.post_json("/api/v1/quotations", req).await
    }

    /// Updates an existing draft quotation (`PUT /api/v1/quotations/{id}`).
    pub async fn update_quotation(
        &self,
        id: Uuid,
        req: &UpdateQuotationRequest,
    ) -> Result<Quotation, ApiError> {
        self.put_json(&format!("/api/v1/quotations/{id}"), req)
            .await
    }

    /// Freezes and sends a draft quotation (`POST /api/v1/quotations/{id}/send`).
    pub async fn send_quotation(
        &self,
        id: Uuid,
        override_shipping: bool,
    ) -> Result<Quotation, ApiError> {
        let path = if override_shipping {
            format!("/api/v1/quotations/{id}/send?override_shipping=true")
        } else {
            format!("/api/v1/quotations/{id}/send")
        };
        self.post_json(&path, &()).await
    }

    /// Marks a sent quotation as accepted (`POST /api/v1/quotations/{id}/accept`).
    pub async fn accept_quotation(&self, id: Uuid) -> Result<Quotation, ApiError> {
        self.post_json(&format!("/api/v1/quotations/{id}/accept"), &())
            .await
    }

    /// Converts a sent or accepted quotation into a draft sales order
    /// (`POST /api/v1/quotations/{id}/convert`).
    pub async fn convert_quotation(
        &self,
        id: Uuid,
        req: &ConvertQuotationRequest,
    ) -> Result<Order, ApiError> {
        self.post_json(&format!("/api/v1/quotations/{id}/convert"), req)
            .await
    }

    /// Lists orders matching `params` (`GET /api/v1/orders`).
    pub async fn list_orders(&self, params: &ListOrdersParams) -> Result<OrderPage, ApiError> {
        self.get_json("/api/v1/orders", params).await
    }

    /// Fetches the latest revision of an order by ID (`GET /api/v1/orders/{id}`).
    pub async fn get_order(&self, id: Uuid) -> Result<Order, ApiError> {
        self.get_json(&format!("/api/v1/orders/{id}"), &()).await
    }

    /// Sends the draft revision of an order (`POST /api/v1/orders/{id}/send`).
    pub async fn send_order(&self, id: Uuid) -> Result<Order, ApiError> {
        self.post_json(&format!("/api/v1/orders/{id}/send"), &())
            .await
    }

    /// Confirms an order on the customer's behalf (`POST /api/v1/orders/{id}/confirm`).
    pub async fn confirm_order(
        &self,
        id: Uuid,
        req: &ConfirmOrderRequest,
    ) -> Result<Order, ApiError> {
        self.post_json(&format!("/api/v1/orders/{id}/confirm"), req)
            .await
    }
}

#[cfg(test)]
mod tests {
    use std::str::FromStr;

    use super::*;

    #[test]
    fn deserialize_quotation_page() {
        let json = r#"{
            "total": 1,
            "items": [
                {
                    "id": "01900000-0000-7000-8000-000000000501",
                    "number": "Q-2026-0001",
                    "revision": 1,
                    "status": "sent",
                    "customer_id": "01900000-0000-7000-8000-000000000401",
                    "customer_name": "Alpha Installaties NV",
                    "opportunity_id": null,
                    "purpose": "installation",
                    "shipping_status": "not_required",
                    "quote_date": "2026-11-20",
                    "valid_until": "2026-12-20",
                    "currency": "EUR",
                    "subtotal": "1200.00",
                    "total": "1452.00"
                }
            ]
        }"#;
        let page: QuotationPage = serde_json::from_str(json).unwrap();
        assert_eq!(page.total, 1);
        assert_eq!(page.items[0].status, QuotationStatus::Sent);
        assert_eq!(page.items[0].number, "Q-2026-0001");
        assert_eq!(page.items[0].total, Decimal::from_str("1452.00").unwrap());
    }

    #[test]
    fn deserialize_quotation_detail_with_lines_and_hints() {
        let json = r#"{
            "id": "01900000-0000-7000-8000-000000000501",
            "company_id": "01900000-0000-7000-8000-000000000001",
            "number": "Q-2026-0001",
            "revision": 1,
            "supersedes_id": null,
            "status": "draft",
            "customer_id": "01900000-0000-7000-8000-000000000401",
            "customer_name": "Alpha Installaties NV",
            "customer_vat_number": "BE0000000097",
            "vat_regime": "domestic",
            "vat_regime_override": null,
            "customer_street": "Havenlaan 10",
            "customer_postal_code": "2000",
            "customer_city": "Antwerpen",
            "customer_country_code": "BE",
            "customer_language": "nl",
            "price_zone_code": "Z2",
            "customer_discount_percent": "5.00",
            "opportunity_id": null,
            "purpose": "installation",
            "delivery_country_code": "BE",
            "power_grid_id": null,
            "building_construction_year": 2010,
            "shipping_status": "not_required",
            "currency": "EUR",
            "quote_date": "2026-11-20",
            "price_date": "2026-11-20",
            "valid_until": "2026-12-20",
            "sent_at": null,
            "notes": "Standard terms apply.",
            "subtotal": "1900.00",
            "vat_total": "399.00",
            "total": "2299.00",
            "version": 2,
            "created_by": "01900000-0000-7000-8000-000000000010",
            "created_at": "2026-11-20T09:00:00Z",
            "updated_at": "2026-11-20T09:05:00Z",
            "lines": [
                {
                    "position": 1,
                    "product_id": "01900000-0000-7000-8000-000000000301",
                    "product_code": "UNIT-100",
                    "description": "Process unit 100",
                    "unit": "pcs",
                    "quantity": "2",
                    "list_unit_price": "1000.00",
                    "non_discountable": false,
                    "price_on_request": false,
                    "price_is_indicative": false,
                    "rebate_percent": "5.00",
                    "rebate_source": "general",
                    "line_discount_percent": "0.00",
                    "net_unit_price": "950.00",
                    "line_total": "1900.00",
                    "vat_rate": "21.00",
                    "price_confirmed": true,
                    "section": "Main units",
                    "parent_position": null,
                    "percent_of_parent": null,
                    "percent_base": null,
                    "comment": null,
                    "customer_remark": "Includes manual",
                    "customer_remark_language": "nl",
                    "production_remark": "Test pressure",
                    "favorite_item_id": null
                }
            ],
            "vat_groups": [
                {
                    "vat_rate": "21.00",
                    "base": "1900.00",
                    "vat": "399.00"
                }
            ],
            "warnings": [
                {
                    "kind": "power_grid",
                    "product_code": "UNIT-100",
                    "message": "Power grid not verified",
                    "details": {"status": "unknown_grid"}
                }
            ],
            "suggestions": [
                {
                    "product_id": "01900000-0000-7000-8000-000000000303",
                    "product_code": "PUMP-05",
                    "product_name": "Pump 0.5 kW",
                    "reason": "rule",
                    "because_of_code": "UNIT-100",
                    "strength": 80,
                    "confidence": null,
                    "note": "Recommended booster pump"
                }
            ]
        }"#;
        let q: Quotation = serde_json::from_str(json).unwrap();
        assert_eq!(q.number, "Q-2026-0001");
        assert_eq!(q.status, QuotationStatus::Draft);
        assert_eq!(q.lines.len(), 1);
        assert_eq!(q.lines[0].product_code, "UNIT-100");
        assert_eq!(q.vat_groups.len(), 1);
        assert_eq!(q.warnings.len(), 1);
        assert_eq!(q.suggestions.len(), 1);
        assert_eq!(q.suggestions[0].strength, Some(80));
    }

    #[test]
    fn serialize_quotation_input_and_convert_input() {
        let req = CreateQuotationRequest {
            customer_id: Uuid::nil(),
            purpose: Some("installation".to_string()),
            notes: "Deliver to gate B".to_string(),
            lines: vec![QuotationLineInput {
                product_id: Uuid::nil(),
                quantity: Decimal::from(2),
                percent_base: Some(PercentBase::ParentNetUnitPrice),
                ..QuotationLineInput::default()
            }],
            ..CreateQuotationRequest::default()
        };
        let value = serde_json::to_value(&req).unwrap();
        assert_eq!(value["purpose"], "installation");
        assert_eq!(value["lines"][0]["quantity"], "2");
        assert_eq!(value["lines"][0]["percent_base"], "parent_net_unit_price");
        assert!(value.get("expected_version").is_none());

        let roundtrip: QuotationInput = serde_json::from_value(value).unwrap();
        assert_eq!(roundtrip.lines[0].quantity, Decimal::from(2));

        let convert = ConvertInput {
            customer_reference: "PO-2026-88".to_string(),
            notes: "Urgent".to_string(),
        };
        let convert_val = serde_json::to_value(&convert).unwrap();
        assert_eq!(convert_val["customer_reference"], "PO-2026-88");
        let convert_rt: ConvertInput = serde_json::from_value(convert_val).unwrap();
        assert_eq!(convert_rt, convert);
    }

    #[test]
    fn deserialize_order_page_and_order_detail() {
        let page_json = r#"{
            "total": 1,
            "items": [
                {
                    "id": "01900000-0000-7000-8000-000000000601",
                    "number": "SO-2026-0001",
                    "status": "sent",
                    "priority": "normal",
                    "current_revision": 1,
                    "quotation_id": "01900000-0000-7000-8000-000000000501",
                    "quotation_number": "Q-2026-0001",
                    "quotation_revision": 1,
                    "customer_id": "01900000-0000-7000-8000-000000000401",
                    "customer_name": "Alpha Installaties NV",
                    "customer_reference": "PO-99",
                    "purpose": "installation",
                    "delivery_country_code": "BE",
                    "power_grid_id": null,
                    "building_construction_year": 2010,
                    "vat_regime": "domestic",
                    "order_date": "2026-11-21",
                    "promised_date": null,
                    "currency": "EUR",
                    "subtotal": "1900.00",
                    "total": "2299.00",
                    "salesperson_id": "01900000-0000-7000-8000-000000000010",
                    "salesperson_name": "Sales User"
                }
            ]
        }"#;
        let page: OrderPage = serde_json::from_str(page_json).unwrap();
        assert_eq!(page.total, 1);
        assert_eq!(page.items[0].number, "SO-2026-0001");
        assert_eq!(page.items[0].customer_reference, "PO-99");

        let order_json = r#"{
            "order": {
                "id": "01900000-0000-7000-8000-000000000601",
                "number": "SO-2026-0001",
                "status": "confirmed",
                "priority": "normal",
                "current_revision": 1,
                "quotation_id": "01900000-0000-7000-8000-000000000501",
                "quotation_number": "Q-2026-0001",
                "quotation_revision": 1,
                "customer_id": "01900000-0000-7000-8000-000000000401",
                "customer_name": "Alpha Installaties NV",
                "customer_reference": "PO-99",
                "purpose": "installation",
                "delivery_country_code": "BE",
                "power_grid_id": null,
                "building_construction_year": 2010,
                "vat_regime": "domestic",
                "order_date": "2026-11-21",
                "promised_date": "2026-12-05",
                "currency": "EUR",
                "subtotal": "1900.00",
                "total": "2299.00",
                "salesperson_id": "01900000-0000-7000-8000-000000000010",
                "salesperson_name": "Sales User"
            },
            "revision": 1,
            "revision_status": "confirmed",
            "vat_total": "399.00",
            "notes": "Confirmed by phone",
            "version": 3,
            "created_at": "2026-11-21T10:00:00Z",
            "confirmed_at": "2026-11-21T12:00:00Z",
            "confirmed_by": "01900000-0000-7000-8000-000000000010",
            "confirmed_via": "staff",
            "confirmed_revision": 1,
            "confirmation_note": "Customer called to confirm",
            "cancel_reason": "",
            "revisions": [
                {
                    "revision": 1,
                    "status": "confirmed",
                    "subtotal": "1900.00",
                    "total": "2299.00",
                    "created_at": "2026-11-21T10:00:00Z",
                    "sent_at": "2026-11-21T10:30:00Z",
                    "sent_to": "info@alpha.example"
                }
            ],
            "lines": [
                {
                    "id": "01900000-0000-7000-8000-000000000701",
                    "position": 1,
                    "product_id": "01900000-0000-7000-8000-000000000301",
                    "product_code": "UNIT-100",
                    "description": "Process unit 100",
                    "unit": "pcs",
                    "quantity": "2",
                    "list_unit_price": "1000.00",
                    "non_discountable": false,
                    "price_on_request": false,
                    "price_is_indicative": false,
                    "rebate_percent": "5.00",
                    "line_discount_percent": "0.00",
                    "net_unit_price": "950.00",
                    "line_total": "1900.00",
                    "vat_rate": "21.00",
                    "customer_remark": "",
                    "production_remark": "Test pressure"
                }
            ],
            "warnings": [],
            "suggestions": []
        }"#;
        let order: Order = serde_json::from_str(order_json).unwrap();
        assert_eq!(order.order.number, "SO-2026-0001");
        assert_eq!(order.revision_status, "confirmed");
        assert_eq!(order.confirmed_via.as_deref(), Some("staff"));
        assert_eq!(order.revisions.len(), 1);
        assert_eq!(order.lines.len(), 1);
        assert_eq!(
            order.lines[0].line_total,
            Decimal::from_str("1900.00").unwrap()
        );
    }

    #[test]
    fn serialize_confirm_and_edit_order_inputs_and_query_params() {
        let confirm = ConfirmOrderInput {
            note: "Confirmed by phone".to_string(),
            revision: Some(1),
        };
        let confirm_val = serde_json::to_value(&confirm).unwrap();
        assert_eq!(confirm_val["note"], "Confirmed by phone");
        assert_eq!(confirm_val["revision"], 1);
        let confirm_rt: ConfirmOrderInput = serde_json::from_value(confirm_val).unwrap();
        assert_eq!(confirm_rt, confirm);

        let edit = OrderEditInput {
            customer_reference: Some("PO-100".to_string()),
            expected_version: Some(1),
            lines: vec![OrderLineEdit {
                position: 1,
                quantity: Decimal::from(3),
                line_discount_percent: Decimal::from(5),
                description: None,
            }],
            ..OrderEditInput::default()
        };
        let edit_val = serde_json::to_value(&edit).unwrap();
        assert_eq!(edit_val["lines"][0]["quantity"], "3");
        let edit_rt: OrderEditInput = serde_json::from_value(edit_val).unwrap();
        assert_eq!(edit_rt, edit);

        let q_params = ListQuotationsParams::new()
            .q("Alpha")
            .status("draft,sent")
            .limit(25);
        let q_req = reqwest::Client::new()
            .get("http://localhost:8080/api/v1/quotations")
            .query(&q_params)
            .build()
            .unwrap();
        assert_eq!(
            q_req.url().query(),
            Some("q=Alpha&status=draft%2Csent&limit=25")
        );

        let o_params = ListOrdersParams::new()
            .q("SO-2026")
            .status("confirmed")
            .limit(10);
        let o_req = reqwest::Client::new()
            .get("http://localhost:8080/api/v1/orders")
            .query(&o_params)
            .build()
            .unwrap();
        assert_eq!(
            o_req.url().query(),
            Some("q=SO-2026&status=confirmed&limit=10")
        );
    }
}
