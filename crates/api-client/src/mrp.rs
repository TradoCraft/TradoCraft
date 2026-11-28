//! Mrp API types and endpoints.

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::{ApiError, Client};

/// A proposal to buy or build.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MrpProposal {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub converted_at: Option<chrono::DateTime<chrono::Utc>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub converted_to: Option<Uuid>,
    pub id: Uuid,
    pub kind: String,
    pub late: bool,
    pub need_date: chrono::NaiveDate,
    pub order_date: chrono::NaiveDate,
    pub pegging: Vec<MrpPeg>,
    pub product_code: String,
    pub product_id: Uuid,
    pub product_name: String,
    pub quantity: String,
    pub reason: String,
    pub run_id: Uuid,
    pub run_number: String,
    pub status: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub supplier_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub supplier_name: Option<String>,
}

/// What a proposed quantity is for.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MrpPeg {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub id: Option<Uuid>,
    pub kind: String,
    pub number: String,
    pub quantity: String,
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct ListMrpProposalsParams {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub status: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub kind: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub product_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub run_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub limit: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub after: Option<Uuid>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MrpConversion {
    pub converted_to: Uuid,
    pub number: String,
    pub proposal: MrpProposal,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MrpConvertInput {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub division_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub supplier_id: Option<Uuid>,
}

/// A planning run.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MrpRun {
    pub created_at: chrono::DateTime<chrono::Utc>,
    pub horizon_days: i32,
    pub id: Uuid,
    pub number: String,
    pub planned_on: chrono::NaiveDate,
    pub proposals: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MrpRunInput {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub horizon_days: Option<i32>,
}

impl Client {
    /// `GET /api/v1/mrp/proposals`.
    pub async fn list_mrp_proposals(
        &self,
        params: &ListMrpProposalsParams,
    ) -> Result<Vec<MrpProposal>, ApiError> {
        self.get_json("/api/v1/mrp/proposals", params).await
    }

    /// `POST /api/v1/mrp/proposals/{id}/convert`.
    pub async fn convert_mrp_proposal(
        &self,
        id: Uuid,
        body: &MrpConvertInput,
    ) -> Result<MrpConversion, ApiError> {
        self.post_json(&format!("/api/v1/mrp/proposals/{id}/convert"), body)
            .await
    }

    /// `POST /api/v1/mrp/proposals/{id}/dismiss`.
    pub async fn dismiss_mrp_proposal(&self, id: Uuid) -> Result<MrpProposal, ApiError> {
        self.post_without_body(&format!("/api/v1/mrp/proposals/{id}/dismiss"))
            .await
    }

    /// `GET /api/v1/mrp/runs`.
    pub async fn list_mrp_runs(&self) -> Result<Vec<MrpRun>, ApiError> {
        self.get_json("/api/v1/mrp/runs", &()).await
    }

    /// `POST /api/v1/mrp/runs`.
    pub async fn start_mrp_run(&self, body: &MrpRunInput) -> Result<MrpRun, ApiError> {
        self.post_json("/api/v1/mrp/runs", body).await
    }
}
