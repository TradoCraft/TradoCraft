//! Engineering API types and endpoints.

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::{ApiError, Client};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Bom {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub activated_at: Option<chrono::DateTime<chrono::Utc>>,
    pub created_at: chrono::DateTime<chrono::Utc>,
    pub id: Uuid,
    pub lines: Vec<BomLine>,
    pub notes: String,
    pub product_code: String,
    pub product_id: Uuid,
    pub product_name: String,
    pub revision: i32,
    pub status: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BomLine {
    pub component_code: String,
    pub component_has_bom: bool,
    pub component_name: String,
    pub component_product_id: Uuid,
    pub component_tracking: String,
    pub component_type: String,
    pub component_unit: String,
    pub notes: String,
    pub position: i32,
    pub quantity: String,
    pub scrap_percent: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BomInput {
    pub lines: Vec<BomLineInput>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub notes: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BomLineInput {
    pub component_product_id: Uuid,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub notes: Option<String>,
    pub quantity: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub scrap_percent: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Explosion {
    pub bom_revision: i32,
    pub nodes: Vec<ExplosionNode>,
    pub product_id: Uuid,
    pub quantity: String,
    pub requirements: Vec<Requirement>,
}

/// One row of an exploded structure, depth-first. `parent_index` points into the same list.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExplosionNode {
    pub code: String,
    pub is_leaf: bool,
    pub level: i32,
    pub name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub parent_index: Option<i32>,
    pub product_id: Uuid,
    pub product_type: String,
    pub quantity_per_parent: String,
    pub required_quantity: String,
    pub scrap_percent: String,
    pub unit: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Requirement {
    pub code: String,
    pub name: String,
    pub product_id: Uuid,
    pub product_type: String,
    pub quantity: String,
    pub unit: String,
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct ExplodeBomParams {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub quantity: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BomSummary {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub activated_at: Option<chrono::DateTime<chrono::Utc>>,
    pub created_at: chrono::DateTime<chrono::Utc>,
    pub id: Uuid,
    pub line_count: i64,
    pub notes: String,
    pub product_id: Uuid,
    pub revision: i32,
    pub status: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NewBomInput {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub copy_from: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub notes: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SerialUnitDetail {
    pub components: Vec<SerialComponent>,
    pub history: Vec<ComponentHistory>,
    pub unit: SerialUnit,
}

/// A serialised component in the current as-built tree, depth-first.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SerialComponent {
    pub added_at: chrono::DateTime<chrono::Utc>,
    pub id: Uuid,
    pub level: i32,
    pub parent_id: Uuid,
    pub product_code: String,
    pub product_name: String,
    pub serial_number: String,
    pub status: String,
}

/// A component link of this unit, including removed ones.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ComponentHistory {
    pub added_at: chrono::DateTime<chrono::Utc>,
    pub added_by_name: String,
    pub child_id: Uuid,
    pub product_code: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub removed_at: Option<chrono::DateTime<chrono::Utc>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub removed_by_name: Option<String>,
    pub serial_number: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SerialUnit {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bom_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bom_revision: Option<i32>,
    pub created_at: chrono::DateTime<chrono::Utc>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub customer_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub customer_name: Option<String>,
    pub id: Uuid,
    pub notes: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub parent_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub parent_serial_number: Option<String>,
    pub product_code: String,
    pub product_id: Uuid,
    pub product_name: String,
    pub serial_number: String,
    pub status: String,
    pub updated_at: chrono::DateTime<chrono::Utc>,
    pub warranty_note: String,
    pub warranty_status: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub warranty_until: Option<chrono::NaiveDate>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SerialInput {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bom_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub customer_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub notes: Option<String>,
    pub serial_number: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SerialUnitPage {
    pub items: Vec<SerialUnit>,
    pub total: i64,
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct ListSerialsParams {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub q: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub product_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub status: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub customer_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub limit: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub offset: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AttachInput {
    pub child_id: Uuid,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DetachInput {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub child_status: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SerialStatusInput {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub customer_id: Option<Uuid>,
    pub status: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WarrantyInput {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub warranty_note: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub warranty_until: Option<chrono::NaiveDate>,
}

impl Client {
    /// `GET /api/v1/boms/{id}`.
    pub async fn get_bom(&self, id: Uuid) -> Result<Bom, ApiError> {
        self.get_json(&format!("/api/v1/boms/{id}"), &()).await
    }

    /// `PUT /api/v1/boms/{id}`.
    pub async fn update_bom(&self, id: Uuid, body: &BomInput) -> Result<Bom, ApiError> {
        self.put_json(&format!("/api/v1/boms/{id}"), body).await
    }

    /// `POST /api/v1/boms/{id}/activate`.
    pub async fn activate_bom(&self, id: Uuid) -> Result<Bom, ApiError> {
        self.post_without_body(&format!("/api/v1/boms/{id}/activate"))
            .await
    }

    /// `GET /api/v1/products/{id}/bom/explode`.
    pub async fn explode_bom(
        &self,
        id: Uuid,
        params: &ExplodeBomParams,
    ) -> Result<Explosion, ApiError> {
        self.get_json(&format!("/api/v1/products/{id}/bom/explode"), params)
            .await
    }

    /// `GET /api/v1/products/{id}/boms`.
    pub async fn list_boms(&self, id: Uuid) -> Result<Vec<BomSummary>, ApiError> {
        self.get_json(&format!("/api/v1/products/{id}/boms"), &())
            .await
    }

    /// `POST /api/v1/products/{id}/boms`.
    pub async fn create_bom(&self, id: Uuid, body: &NewBomInput) -> Result<Bom, ApiError> {
        self.post_json(&format!("/api/v1/products/{id}/boms"), body)
            .await
    }

    /// `POST /api/v1/products/{id}/serials`.
    pub async fn create_serial(
        &self,
        id: Uuid,
        body: &SerialInput,
    ) -> Result<SerialUnitDetail, ApiError> {
        self.post_json(&format!("/api/v1/products/{id}/serials"), body)
            .await
    }

    /// `GET /api/v1/serials`.
    pub async fn list_serials(
        &self,
        params: &ListSerialsParams,
    ) -> Result<SerialUnitPage, ApiError> {
        self.get_json("/api/v1/serials", params).await
    }

    /// `GET /api/v1/serials/{id}`.
    pub async fn get_serial(&self, id: Uuid) -> Result<SerialUnitDetail, ApiError> {
        self.get_json(&format!("/api/v1/serials/{id}"), &()).await
    }

    /// `POST /api/v1/serials/{id}/components`.
    pub async fn attach_component(
        &self,
        id: Uuid,
        body: &AttachInput,
    ) -> Result<SerialUnitDetail, ApiError> {
        self.post_json(&format!("/api/v1/serials/{id}/components"), body)
            .await
    }

    /// `POST /api/v1/serials/{id}/components/{child_id}/remove`.
    pub async fn detach_component(
        &self,
        id: Uuid,
        child_id: Uuid,
        body: &DetachInput,
    ) -> Result<SerialUnitDetail, ApiError> {
        self.post_json(
            &format!("/api/v1/serials/{id}/components/{child_id}/remove"),
            body,
        )
        .await
    }

    /// `PUT /api/v1/serials/{id}/status`.
    pub async fn set_status(
        &self,
        id: Uuid,
        body: &SerialStatusInput,
    ) -> Result<SerialUnitDetail, ApiError> {
        self.put_json(&format!("/api/v1/serials/{id}/status"), body)
            .await
    }

    /// `PUT /api/v1/serials/{id}/warranty`.
    pub async fn set_warranty(
        &self,
        id: Uuid,
        body: &WarrantyInput,
    ) -> Result<SerialUnitDetail, ApiError> {
        self.put_json(&format!("/api/v1/serials/{id}/warranty"), body)
            .await
    }
}
