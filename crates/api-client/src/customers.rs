//! Customer DTOs and endpoints (`/api/v1/customers`).

use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::client::Client;
use crate::error::ApiError;

/// Customer record returned by `GET /api/v1/customers`, `GET /api/v1/customers/{id}`,
/// `POST /api/v1/customers`, and `PUT /api/v1/customers/{id}`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Customer {
    pub id: Uuid,
    /// Optimistic-concurrency version; send back as `expected_version` when updating.
    #[serde(default)]
    pub version: i64,
    pub code: String,
    pub name: String,
    #[serde(default)]
    pub vat_number: Option<String>,
    /// `domestic`, `domestic_reverse_charge`, `intra_eu`, or `outside_eu`.
    pub vat_regime: String,
    #[serde(default)]
    pub email: Option<String>,
    #[serde(default)]
    pub phone: Option<String>,
    pub street: String,
    pub postal_code: String,
    pub city: String,
    pub country_code: String,
    pub language: String,
    pub active: bool,
    #[serde(default)]
    pub price_zone_id: Option<Uuid>,
    #[serde(default)]
    pub price_zone_code: Option<String>,
    #[serde(default)]
    pub discount_percent: Option<Decimal>,
    #[serde(default)]
    pub payment_terms_days: Option<i32>,
}

/// Request payload for `POST /api/v1/customers` and `PUT /api/v1/customers/{id}`
/// (OpenAPI schema `CustomerInput`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CustomerInput {
    pub code: String,
    pub name: String,
    #[serde(default)]
    pub vat_number: Option<String>,
    /// `domestic`, `domestic_reverse_charge`, `intra_eu`, or `outside_eu`. When omitted on
    /// create, derived automatically from the active company's country, the customer's country,
    /// and `vat_number`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub vat_regime: Option<String>,
    #[serde(default)]
    pub email: Option<String>,
    #[serde(default)]
    pub phone: Option<String>,
    #[serde(default)]
    pub street: String,
    #[serde(default)]
    pub postal_code: String,
    #[serde(default)]
    pub city: String,
    #[serde(default = "default_country")]
    pub country_code: String,
    #[serde(default = "default_language")]
    pub language: String,
    #[serde(default = "default_true")]
    pub active: bool,
    pub price_zone_id: Uuid,
    #[serde(default)]
    pub discount_percent: Decimal,
    #[serde(default = "default_payment_terms")]
    pub payment_terms_days: i32,
    /// Optimistic-concurrency version from the loaded [`Customer`]; `409 record_changed` if stale.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub expected_version: Option<i64>,
}

/// Request payload for `POST /api/v1/customers`.
pub type CreateCustomerRequest = CustomerInput;

/// Request payload for `PUT /api/v1/customers/{id}`.
pub type UpdateCustomerRequest = CustomerInput;

fn default_country() -> String {
    "BE".to_string()
}

fn default_language() -> String {
    "nl".to_string()
}

fn default_true() -> bool {
    true
}

fn default_payment_terms() -> i32 {
    30
}

impl Default for CustomerInput {
    fn default() -> Self {
        Self {
            code: String::new(),
            name: String::new(),
            vat_number: None,
            vat_regime: None,
            email: None,
            phone: None,
            street: String::new(),
            postal_code: String::new(),
            city: String::new(),
            country_code: default_country(),
            language: default_language(),
            active: true,
            price_zone_id: Uuid::nil(),
            discount_percent: Decimal::ZERO,
            payment_terms_days: default_payment_terms(),
            expected_version: None,
        }
    }
}

impl CustomerInput {
    /// Builds an update payload from a loaded [`Customer`], preserving `expected_version`.
    pub fn from_customer(customer: &Customer, fallback_price_zone_id: Uuid) -> Self {
        Self {
            code: customer.code.clone(),
            name: customer.name.clone(),
            vat_number: customer.vat_number.clone(),
            vat_regime: (!customer.vat_regime.trim().is_empty())
                .then(|| customer.vat_regime.clone()),
            email: customer.email.clone(),
            phone: customer.phone.clone(),
            street: customer.street.clone(),
            postal_code: customer.postal_code.clone(),
            city: customer.city.clone(),
            country_code: customer.country_code.clone(),
            language: customer.language.clone(),
            active: customer.active,
            price_zone_id: customer.price_zone_id.unwrap_or(fallback_price_zone_id),
            discount_percent: customer.discount_percent.unwrap_or(Decimal::ZERO),
            payment_terms_days: customer.payment_terms_days.unwrap_or(30),
            expected_version: Some(customer.version),
        }
    }
}

/// Paginated response from `GET /api/v1/customers`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CustomerPage {
    pub items: Vec<Customer>,
    pub total: i64,
}

/// Query parameters for `GET /api/v1/customers`.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
pub struct ListCustomersParams {
    /// Searches code, name, VAT number, and city, ignoring case and accents.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub q: Option<String>,
    /// Sort order (`field` or `-field`, up to 3 comma-separated keys).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sort: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub active: Option<bool>,
    /// Comma-separated ISO alpha-2 country codes (`BE,NL`).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub country_code: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub limit: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub offset: Option<i64>,
}

impl ListCustomersParams {
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

    pub fn country_code(mut self, country_code: impl Into<String>) -> Self {
        self.country_code = Some(country_code.into());
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
    /// Lists customers matching `params` (`GET /api/v1/customers`).
    pub async fn list_customers(
        &self,
        params: &ListCustomersParams,
    ) -> Result<CustomerPage, ApiError> {
        self.get_json("/api/v1/customers", params).await
    }

    /// Fetches a single customer by ID (`GET /api/v1/customers/{id}`).
    pub async fn get_customer(&self, id: Uuid) -> Result<Customer, ApiError> {
        self.get_json(&format!("/api/v1/customers/{id}"), &()).await
    }

    /// Creates a new customer (`POST /api/v1/customers`).
    pub async fn create_customer(&self, req: &CreateCustomerRequest) -> Result<Customer, ApiError> {
        self.post_json("/api/v1/customers", req).await
    }

    /// Updates an existing customer (`PUT /api/v1/customers/{id}`).
    pub async fn update_customer(
        &self,
        id: Uuid,
        req: &UpdateCustomerRequest,
    ) -> Result<Customer, ApiError> {
        self.put_json(&format!("/api/v1/customers/{id}"), req).await
    }
}

#[cfg(test)]
mod tests {
    use std::str::FromStr;

    use super::*;

    #[test]
    fn deserialize_customer_page() {
        let json = r#"{
            "total": 1,
            "items": [
                {
                    "id": "01900000-0000-7000-8000-000000000300",
                    "version": 3,
                    "code": "CUST-001",
                    "name": "Van den Berg BV",
                    "vat_number": "BE0412345678",
                    "vat_regime": "domestic",
                    "email": "orders@vandenberg.be",
                    "phone": "+32 3 555 12 34",
                    "street": "Meir 10",
                    "postal_code": "2000",
                    "city": "Antwerpen",
                    "country_code": "BE",
                    "language": "nl",
                    "active": true,
                    "price_zone_id": "01900000-0000-7000-8000-000000000400",
                    "price_zone_code": "TRADE",
                    "discount_percent": "5.00",
                    "payment_terms_days": 30
                }
            ]
        }"#;
        let page: CustomerPage = serde_json::from_str(json).unwrap();
        assert_eq!(page.total, 1);
        assert_eq!(page.items.len(), 1);
        let c = &page.items[0];
        assert_eq!(c.code, "CUST-001");
        assert_eq!(c.version, 3);
        assert_eq!(c.discount_percent, Some(Decimal::from_str("5.00").unwrap()));
        assert_eq!(c.payment_terms_days, Some(30));
    }

    #[test]
    fn list_customers_params_serialize_only_set_fields() {
        let params = ListCustomersParams::new()
            .q("Antwerpen")
            .country_code("BE,NL")
            .limit(50);
        let req = reqwest::Client::new()
            .get("http://localhost:8080/api/v1/customers")
            .query(&params)
            .build()
            .unwrap();
        assert_eq!(
            req.url().query(),
            Some("q=Antwerpen&country_code=BE%2CNL&limit=50")
        );
    }

    #[test]
    fn create_customer_request_serializes_defaults_and_omits_optional_none() {
        let zone_id = Uuid::parse_str("00000000-0000-7000-8000-000000000201").unwrap();
        let req = CreateCustomerRequest {
            code: "C0010".to_string(),
            name: "Nieuw Bedrijf NV".to_string(),
            price_zone_id: zone_id,
            ..CreateCustomerRequest::default()
        };
        let value = serde_json::to_value(&req).unwrap();
        assert_eq!(value["code"], "C0010");
        assert_eq!(value["country_code"], "BE");
        assert_eq!(value["language"], "nl");
        assert_eq!(value["payment_terms_days"], 30);
        assert_eq!(value["discount_percent"], "0");
        assert_eq!(value["price_zone_id"], zone_id.to_string());
        assert!(value.get("vat_regime").is_none());
        assert!(value.get("expected_version").is_none());
    }

    #[test]
    fn customer_input_from_customer_sets_expected_version() {
        let zone_id = Uuid::parse_str("00000000-0000-7000-8000-000000000202").unwrap();
        let customer = Customer {
            id: Uuid::nil(),
            version: 7,
            code: "C0001".to_string(),
            name: "Alpha NV".to_string(),
            vat_number: Some("BE0000000097".to_string()),
            vat_regime: "domestic".to_string(),
            email: Some("info@alpha.example".to_string()),
            phone: None,
            street: "Havenlaan 10".to_string(),
            postal_code: "2000".to_string(),
            city: "Antwerpen".to_string(),
            country_code: "BE".to_string(),
            language: "nl".to_string(),
            active: true,
            price_zone_id: Some(zone_id),
            price_zone_code: Some("Z2".to_string()),
            discount_percent: Some(Decimal::from_str("5.00").unwrap()),
            payment_terms_days: Some(30),
        };
        let update = UpdateCustomerRequest::from_customer(&customer, Uuid::nil());
        assert_eq!(update.expected_version, Some(7));
        assert_eq!(update.price_zone_id, zone_id);
        assert_eq!(update.vat_regime.as_deref(), Some("domestic"));
        assert_eq!(update.discount_percent, Decimal::from_str("5.00").unwrap());
    }
}
