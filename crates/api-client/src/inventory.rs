//! Warehouse and location lookups used when completing production.

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::{ApiError, Client};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Warehouse {
    pub id: Uuid,
    pub code: String,
    pub name: String,
    pub kind: String,
    pub active: bool,
    pub assigned_user_id: Option<Uuid>,
    pub assigned_user_name: Option<String>,
    pub locations: Vec<Location>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Location {
    pub id: Uuid,
    pub warehouse_id: Uuid,
    pub code: String,
    pub name: String,
    pub active: bool,
}

impl Client {
    /// `GET /api/v1/inventory/warehouses`.
    pub async fn list_warehouses(&self) -> Result<Vec<Warehouse>, ApiError> {
        self.get_json("/api/v1/inventory/warehouses", &()).await
    }
}
