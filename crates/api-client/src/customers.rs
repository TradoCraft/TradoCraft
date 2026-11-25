//! Customer DTOs and endpoints (`GET /api/v1/customers`).

use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::client::Client;
use crate::error::ApiError;

/// Customer record returned by `GET /api/v1/customers`.
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
}
