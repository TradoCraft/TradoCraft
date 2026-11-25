//! Product DTOs and endpoints (`GET /api/v1/products`).

use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::client::Client;
use crate::error::ApiError;

/// Product record returned by `GET /api/v1/products`.
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
}
