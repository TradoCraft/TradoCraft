//! Supplier DTOs and endpoints (`/api/v1/suppliers`, `/api/v1/purchase-orders`).

use chrono::{DateTime, NaiveDate, Utc};
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::client::Client;
use crate::error::ApiError;

/// Supplier record returned by `GET /api/v1/suppliers`, `GET /api/v1/suppliers/{id}`,
/// `POST /api/v1/suppliers`, and `PUT /api/v1/suppliers/{id}` (OpenAPI schema `Supplier`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Supplier {
    pub id: Uuid,
    pub company_id: Uuid,
    pub name: String,
    pub code: String,
    pub country: String,
    pub currency: String,
    #[serde(default)]
    pub email: String,
    #[serde(default)]
    pub phone: String,
    #[serde(default)]
    pub contact_person: String,
    pub payment_terms_days: i32,
    #[serde(default)]
    pub tax_id: String,
    pub active: bool,
    #[serde(default)]
    pub notes: String,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// Request payload for `POST /api/v1/suppliers` (OpenAPI schema `NewSupplierInput`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SupplierInput {
    pub name: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub code: Option<String>,
    #[serde(default = "default_country")]
    pub country: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub currency: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub email: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub phone: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub contact_person: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub payment_terms_days: Option<i32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tax_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub notes: Option<String>,
}

/// Request payload for `POST /api/v1/suppliers` (OpenAPI schema alias).
pub type NewSupplierInput = SupplierInput;

/// Request payload for `POST /api/v1/suppliers`.
pub type CreateSupplierRequest = SupplierInput;

fn default_country() -> String {
    "BE".to_string()
}

impl Default for SupplierInput {
    fn default() -> Self {
        Self {
            name: String::new(),
            code: None,
            country: default_country(),
            currency: None,
            email: None,
            phone: None,
            contact_person: None,
            payment_terms_days: None,
            tax_id: None,
            notes: None,
        }
    }
}

/// Request payload for `PUT /api/v1/suppliers/{id}` (OpenAPI schema `UpdateSupplierInput`).
///
/// Partial update; omitted (`None`) fields keep their current value on the server.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct UpdateSupplierInput {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub code: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub country: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub currency: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub email: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub phone: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub contact_person: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub payment_terms_days: Option<i32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub tax_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub active: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub notes: Option<String>,
}

/// Request payload for `PUT /api/v1/suppliers/{id}`.
pub type UpdateSupplierRequest = UpdateSupplierInput;

impl UpdateSupplierInput {
    /// Builds a full update payload from a loaded [`Supplier`].
    pub fn from_supplier(supplier: &Supplier) -> Self {
        Self {
            name: Some(supplier.name.clone()),
            code: Some(supplier.code.clone()),
            country: Some(supplier.country.clone()),
            currency: Some(supplier.currency.clone()),
            email: Some(supplier.email.clone()),
            phone: Some(supplier.phone.clone()),
            contact_person: Some(supplier.contact_person.clone()),
            payment_terms_days: Some(supplier.payment_terms_days),
            tax_id: Some(supplier.tax_id.clone()),
            active: Some(supplier.active),
            notes: Some(supplier.notes.clone()),
        }
    }
}

/// Supplier price list entry for a product returned by
/// `GET /api/v1/suppliers/{id}/products` and `POST /api/v1/suppliers/{id}/products/{product_id}`
/// (OpenAPI schema `SupplierProduct`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SupplierProduct {
    pub id: Uuid,
    pub company_id: Uuid,
    pub supplier_id: Uuid,
    pub supplier_name: String,
    pub product_id: Uuid,
    pub product_code: String,
    pub product_name: String,
    #[serde(default)]
    pub supplier_product_code: String,
    #[serde(default)]
    pub supplier_product_name: String,
    pub currency: String,
    pub unit_price: Decimal,
    pub moq: Decimal,
    pub lead_time_days: i32,
    pub is_preferred: bool,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// Payload to create or replace a supplier price list entry via
/// `POST /api/v1/suppliers/{id}/products/{product_id}`
/// (OpenAPI schema `SetSupplierProductInput`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SupplierProductInput {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub supplier_product_code: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub supplier_product_name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub currency: Option<String>,
    pub unit_price: Decimal,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub moq: Option<Decimal>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub lead_time_days: Option<i32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub is_preferred: Option<bool>,
}

/// Request payload alias matching the OpenAPI schema name `SetSupplierProductInput`.
pub type SetSupplierProductInput = SupplierProductInput;

impl Default for SupplierProductInput {
    fn default() -> Self {
        Self {
            supplier_product_code: None,
            supplier_product_name: None,
            currency: None,
            unit_price: Decimal::ZERO,
            moq: None,
            lead_time_days: None,
            is_preferred: None,
        }
    }
}

impl SupplierProductInput {
    /// Builds an upsert payload from an existing [`SupplierProduct`] entry.
    pub fn from_supplier_product(entry: &SupplierProduct) -> Self {
        Self {
            supplier_product_code: (!entry.supplier_product_code.trim().is_empty())
                .then(|| entry.supplier_product_code.clone()),
            supplier_product_name: (!entry.supplier_product_name.trim().is_empty())
                .then(|| entry.supplier_product_name.clone()),
            currency: (!entry.currency.trim().is_empty()).then(|| entry.currency.clone()),
            unit_price: entry.unit_price,
            moq: Some(entry.moq),
            lead_time_days: Some(entry.lead_time_days),
            is_preferred: Some(entry.is_preferred),
        }
    }
}

/// Query parameters for `GET /api/v1/suppliers`.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
pub struct ListSuppliersParams {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub active_only: Option<bool>,
    /// Searches name, code, e-mail address and contact person, ignoring case and accents.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub q: Option<String>,
}

impl ListSuppliersParams {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn active_only(mut self, active_only: bool) -> Self {
        self.active_only = Some(active_only);
        self
    }

    pub fn q(mut self, q: impl Into<String>) -> Self {
        self.q = Some(q.into());
        self
    }
}

/// Purchase order header with supplier name and totals returned by `GET /api/v1/purchase-orders`
/// (OpenAPI schema `PurchaseOrderSummary`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PurchaseOrderSummary {
    pub id: Uuid,
    pub company_id: Uuid,
    pub number: String,
    pub supplier_id: Uuid,
    pub supplier_name: String,
    /// `draft | approved | sent | partially_received | received | cancelled`
    pub status: String,
    pub order_date: NaiveDate,
    #[serde(default)]
    pub expected_delivery_date: Option<NaiveDate>,
    pub currency: String,
    pub subtotal: Decimal,
    pub tax_total: Decimal,
    pub total: Decimal,
    #[serde(default)]
    pub notes: String,
    pub created_by_user_id: Uuid,
    #[serde(default)]
    pub approved_by_user_id: Option<Uuid>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// Query parameters for `GET /api/v1/purchase-orders`.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
pub struct ListPurchaseOrdersParams {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub supplier_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub status: Option<String>,
}

impl ListPurchaseOrdersParams {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn supplier_id(mut self, supplier_id: Uuid) -> Self {
        self.supplier_id = Some(supplier_id);
        self
    }

    pub fn status(mut self, status: impl Into<String>) -> Self {
        self.status = Some(status.into());
        self
    }
}

impl Client {
    /// Lists suppliers matching `params` (`GET /api/v1/suppliers`).
    pub async fn list_suppliers(
        &self,
        params: &ListSuppliersParams,
    ) -> Result<Vec<Supplier>, ApiError> {
        self.get_json("/api/v1/suppliers", params).await
    }

    /// Fetches a single supplier by ID (`GET /api/v1/suppliers/{id}`).
    pub async fn get_supplier(&self, id: Uuid) -> Result<Supplier, ApiError> {
        self.get_json(&format!("/api/v1/suppliers/{id}"), &()).await
    }

    /// Creates a new supplier (`POST /api/v1/suppliers`).
    pub async fn create_supplier(&self, req: &SupplierInput) -> Result<Supplier, ApiError> {
        self.post_json("/api/v1/suppliers", req).await
    }

    /// Updates an existing supplier (`PUT /api/v1/suppliers/{id}`).
    pub async fn update_supplier(
        &self,
        id: Uuid,
        req: &UpdateSupplierInput,
    ) -> Result<Supplier, ApiError> {
        self.put_json(&format!("/api/v1/suppliers/{id}"), req).await
    }

    /// Lists product prices for a supplier (`GET /api/v1/suppliers/{id}/products`).
    pub async fn list_supplier_products(
        &self,
        supplier_id: Uuid,
    ) -> Result<Vec<SupplierProduct>, ApiError> {
        self.get_json(&format!("/api/v1/suppliers/{supplier_id}/products"), &())
            .await
    }

    /// Creates or replaces a supplier price list entry for a product
    /// (`POST /api/v1/suppliers/{id}/products/{product_id}`).
    pub async fn set_supplier_product(
        &self,
        supplier_id: Uuid,
        product_id: Uuid,
        req: &SupplierProductInput,
    ) -> Result<SupplierProduct, ApiError> {
        self.post_json(
            &format!("/api/v1/suppliers/{supplier_id}/products/{product_id}"),
            req,
        )
        .await
    }

    /// Lists purchase orders matching `params` (`GET /api/v1/purchase-orders`).
    pub async fn list_purchase_orders(
        &self,
        params: &ListPurchaseOrdersParams,
    ) -> Result<Vec<PurchaseOrderSummary>, ApiError> {
        self.get_json("/api/v1/purchase-orders", params).await
    }
}

#[cfg(test)]
mod tests {
    use std::str::FromStr;

    use super::*;

    fn sample_supplier_json() -> &'static str {
        r#"{
            "id": "01900000-0000-7000-8000-000000000500",
            "company_id": "01900000-0000-7000-8000-000000000001",
            "name": "Nordic Components GmbH",
            "code": "SUP-001",
            "country": "DE",
            "currency": "EUR",
            "email": "purchasing@nordic.example",
            "phone": "+49 40 555 0100",
            "contact_person": "Jan Weber",
            "payment_terms_days": 45,
            "tax_id": "DE123456789",
            "active": true,
            "notes": "Primary frame supplier",
            "created_at": "2026-01-15T09:30:00Z",
            "updated_at": "2026-01-16T11:00:00Z"
        }"#
    }

    #[test]
    fn deserialize_supplier() {
        let supplier: Supplier = serde_json::from_str(sample_supplier_json()).unwrap();
        assert_eq!(supplier.code, "SUP-001");
        assert_eq!(supplier.name, "Nordic Components GmbH");
        assert_eq!(supplier.country, "DE");
        assert_eq!(supplier.currency, "EUR");
        assert_eq!(supplier.payment_terms_days, 45);
        assert!(supplier.active);
    }

    #[test]
    fn deserialize_supplier_list() {
        let json = format!("[{}]", sample_supplier_json());
        let suppliers: Vec<Supplier> = serde_json::from_str(&json).unwrap();
        assert_eq!(suppliers.len(), 1);
        assert_eq!(suppliers[0].code, "SUP-001");
        assert_eq!(suppliers[0].contact_person, "Jan Weber");
    }

    #[test]
    fn deserialize_supplier_product_list() {
        let json = r#"[
            {
                "id": "01900000-0000-7000-8000-000000000600",
                "company_id": "01900000-0000-7000-8000-000000000001",
                "supplier_id": "01900000-0000-7000-8000-000000000500",
                "supplier_name": "Nordic Components GmbH",
                "product_id": "01900000-0000-7000-8000-000000000700",
                "product_code": "FRAME-ALU-200",
                "product_name": "Aluminium Frame 200",
                "supplier_product_code": "NC-ALU-200",
                "supplier_product_name": "Alu Frame 200cm",
                "currency": "EUR",
                "unit_price": "142.50",
                "moq": "5.00",
                "lead_time_days": 14,
                "is_preferred": true,
                "created_at": "2026-01-15T09:30:00Z",
                "updated_at": "2026-01-16T11:00:00Z"
            }
        ]"#;
        let items: Vec<SupplierProduct> = serde_json::from_str(json).unwrap();
        assert_eq!(items.len(), 1);
        let item = &items[0];
        assert_eq!(item.product_code, "FRAME-ALU-200");
        assert_eq!(item.supplier_product_code, "NC-ALU-200");
        assert_eq!(item.unit_price, Decimal::from_str("142.50").unwrap());
        assert_eq!(item.moq, Decimal::from_str("5.00").unwrap());
        assert_eq!(item.lead_time_days, 14);
        assert!(item.is_preferred);
    }

    #[test]
    fn list_suppliers_params_serialize_only_set_fields() {
        let params = ListSuppliersParams::new().active_only(true).q("Nordic");
        let req = reqwest::Client::new()
            .get("http://localhost:8080/api/v1/suppliers")
            .query(&params)
            .build()
            .unwrap();
        assert_eq!(req.url().query(), Some("active_only=true&q=Nordic"));

        let empty = ListSuppliersParams::new();
        let req_empty = reqwest::Client::new()
            .get("http://localhost:8080/api/v1/suppliers")
            .query(&empty)
            .build()
            .unwrap();
        assert_eq!(req_empty.url().query(), None);
    }

    #[test]
    fn supplier_input_serializes_defaults_and_omits_optional_none() {
        let req = SupplierInput {
            name: "Vandenberg Staal NV".to_string(),
            code: Some("SUP-010".to_string()),
            ..SupplierInput::default()
        };
        let value = serde_json::to_value(&req).unwrap();
        assert_eq!(value["name"], "Vandenberg Staal NV");
        assert_eq!(value["code"], "SUP-010");
        assert_eq!(value["country"], "BE");
        assert!(value.get("currency").is_none());
        assert!(value.get("payment_terms_days").is_none());
        assert!(value.get("tax_id").is_none());
    }

    #[test]
    fn update_supplier_input_from_supplier_and_partial_serialization() {
        let supplier: Supplier = serde_json::from_str(sample_supplier_json()).unwrap();
        let full_update = UpdateSupplierInput::from_supplier(&supplier);
        assert_eq!(full_update.name.as_deref(), Some("Nordic Components GmbH"));
        assert_eq!(full_update.code.as_deref(), Some("SUP-001"));
        assert_eq!(full_update.active, Some(true));
        assert_eq!(full_update.payment_terms_days, Some(45));

        let partial = UpdateSupplierInput {
            active: Some(false),
            ..UpdateSupplierInput::default()
        };
        let value = serde_json::to_value(&partial).unwrap();
        assert_eq!(value["active"], false);
        assert!(value.get("name").is_none());
        assert!(value.get("country").is_none());
    }

    #[test]
    fn supplier_product_input_serializes_required_and_optional_fields() {
        let req = SupplierProductInput {
            supplier_product_code: Some("NC-ALU-200".to_string()),
            currency: Some("EUR".to_string()),
            unit_price: Decimal::from_str("142.50").unwrap(),
            moq: Some(Decimal::from_str("5").unwrap()),
            lead_time_days: Some(14),
            is_preferred: Some(true),
            ..SupplierProductInput::default()
        };
        let value = serde_json::to_value(&req).unwrap();
        assert_eq!(value["unit_price"], "142.50");
        assert_eq!(value["moq"], "5");
        assert_eq!(value["lead_time_days"], 14);
        assert_eq!(value["is_preferred"], true);
        assert_eq!(value["supplier_product_code"], "NC-ALU-200");
        assert!(value.get("supplier_product_name").is_none());
    }

    #[test]
    fn deserialize_purchase_order_summary_list() {
        let json = r#"[
            {
                "id": "01900000-0000-7000-8000-000000000800",
                "company_id": "01900000-0000-7000-8000-000000000001",
                "number": "PO-2026-0001",
                "supplier_id": "01900000-0000-7000-8000-000000000500",
                "supplier_name": "Nordic Components GmbH",
                "status": "sent",
                "order_date": "2026-11-20",
                "expected_delivery_date": "2026-11-27",
                "currency": "EUR",
                "subtotal": "500.00",
                "tax_total": "105.00",
                "total": "605.00",
                "notes": "",
                "created_by_user_id": "01900000-0000-7000-8000-000000000101",
                "approved_by_user_id": "01900000-0000-7000-8000-000000000101",
                "created_at": "2026-11-20T09:00:00Z",
                "updated_at": "2026-11-20T09:30:00Z"
            }
        ]"#;
        let orders: Vec<PurchaseOrderSummary> = serde_json::from_str(json).unwrap();
        assert_eq!(orders.len(), 1);
        assert_eq!(orders[0].number, "PO-2026-0001");
        assert_eq!(orders[0].supplier_name, "Nordic Components GmbH");
        assert_eq!(orders[0].total, Decimal::from_str("605.00").unwrap());
    }
}
