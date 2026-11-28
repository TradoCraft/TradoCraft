//! Opportunities API types and endpoints.

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::{ApiError, Client};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BaselineItemTypeInput {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub active: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub allow_top_level: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub allowed_parent_codes: Option<Vec<String>>,
    pub code: String,
    pub name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sort_order: Option<i32>,
}

/// Everything but the code, which cannot change.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BaselineItemTypeUpdate {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub active: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub allow_top_level: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub allowed_parent_codes: Option<Vec<String>>,
    pub name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sort_order: Option<i32>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MatchRule {
    pub active: bool,
    pub baseline_attribute_key: String,
    pub baseline_type_code: String,
    pub created_at: chrono::DateTime<chrono::Utc>,
    pub id: Uuid,
    pub name: String,
    pub operator: Operator,
    pub product_attribute_key: String,
    pub sort_order: i32,
    pub updated_at: chrono::DateTime<chrono::Utc>,
}

/// How a baseline value is compared with a product attribute.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum Operator {
    #[serde(rename = "within_range")]
    WithinRange,
    #[serde(rename = "at_most")]
    AtMost,
    #[serde(rename = "at_least")]
    AtLeast,
    #[serde(rename = "requires_if_true")]
    RequiresIfTrue,
}

/// A rule is created and replaced with the same fields.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MatchRuleInput {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub active: Option<bool>,
    pub baseline_attribute_key: String,
    pub baseline_type_code: String,
    pub name: String,
    pub operator: Operator,
    pub product_attribute_key: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sort_order: Option<i32>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OpportunityPage {
    pub items: Vec<Opportunity>,
    pub total: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Opportunity {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub building_construction_year: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub closed_at: Option<chrono::DateTime<chrono::Utc>>,
    pub created_at: chrono::DateTime<chrono::Utc>,
    pub customer_id: Uuid,
    pub customer_name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub expected_close: Option<chrono::NaiveDate>,
    pub expected_value: String,
    pub id: Uuid,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub lost_reason: Option<String>,
    pub notes: String,
    pub number: String,
    pub owner_name: String,
    pub owner_user_id: Uuid,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub power_grid_id: Option<Uuid>,
    pub probability: i32,
    pub stage: OpportunityStage,
    pub title: String,
    pub updated_at: chrono::DateTime<chrono::Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum OpportunityStage {
    #[serde(rename = "lead")]
    Lead,
    #[serde(rename = "qualified")]
    Qualified,
    #[serde(rename = "proposal")]
    Proposal,
    #[serde(rename = "negotiation")]
    Negotiation,
    #[serde(rename = "won")]
    Won,
    #[serde(rename = "lost")]
    Lost,
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct ListOpportunitiesParams {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub q: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub stage: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub customer_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub open: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub limit: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub offset: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OpportunityInput {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub building_construction_year: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub clear_building_construction_year: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub clear_power_grid: Option<bool>,
    pub customer_id: Uuid,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub expected_close: Option<chrono::NaiveDate>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub expected_value: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub notes: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub owner_user_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub power_grid_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub probability: Option<i32>,
    pub title: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PipelineStage {
    pub count: i64,
    pub stage: OpportunityStage,
    pub total_value: String,
    pub weighted_value: String,
}

/// One baseline item. `children` is only filled in the tree returned by `GET .../baseline`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BaselineItem {
    pub children: Vec<BaselineItem>,
    pub created_at: chrono::DateTime<chrono::Utc>,
    pub id: Uuid,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub import_source: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub parent_id: Option<Uuid>,
    pub quantity: i32,
    pub sort_order: i32,
    pub type_code: String,
    pub updated_at: chrono::DateTime<chrono::Utc>,
    pub values: serde_json::Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BaselineImportReport {
    pub created: ImportCounts,
    pub dry_run: bool,
    pub items: Vec<ImportPreviewItem>,
    pub replaced: u64,
    pub source_id: String,
    pub unmapped_fields: Vec<UnmappedField>,
    pub warnings: Vec<ImportWarning>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ImportCounts {
    pub bell: u64,
    pub bell_group: u64,
    pub clock_dial: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ImportPreviewItem {
    pub name: String,
    pub type_code: String,
    pub values: serde_json::Value,
}

/// A source field that has no baseline attribute. It is kept in the item's `source_data`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UnmappedField {
    pub count: u64,
    pub field: String,
}

/// Something in the source that could not be used as is. The import carries on.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ImportWarning {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bell: Option<String>,
    pub field: String,
    pub message: String,
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct ImportBaselineParams {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub dry_run: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub source_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BaselineItemInput {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub parent_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub quantity: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sort_order: Option<i32>,
    pub type_code: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub values: Option<serde_json::Value>,
}

/// Replaces an item: what is not sent falls back to its default (no parent, no name, quantity 1,
/// no values); only `sort_order` keeps its stored value when omitted. The type cannot change.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BaselineItemUpdate {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub parent_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub quantity: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sort_order: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub values: Option<serde_json::Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProductMatchPage {
    pub counts: StatusCounts,
    pub items: Vec<ProductMatch>,
    pub total: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StatusCounts {
    pub suitable: i64,
    pub unknown: i64,
    pub unsuitable: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProductMatch {
    pub code: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub family_code: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub family_id: Option<Uuid>,
    pub id: Uuid,
    pub name: String,
    pub reasons: Vec<Reason>,
    pub status: MatchStatus,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Reason {
    pub check: String,
    pub message: String,
    pub status: CheckStatus,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum CheckStatus {
    #[serde(rename = "ok")]
    Ok,
    #[serde(rename = "fail")]
    Fail,
    #[serde(rename = "unknown")]
    Unknown,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum MatchStatus {
    #[serde(rename = "suitable")]
    Suitable,
    #[serde(rename = "unsuitable")]
    Unsuitable,
    #[serde(rename = "unknown")]
    Unknown,
}

#[derive(Debug, Clone, Serialize, Default)]
pub struct ProductMatchesParams {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub status: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub family_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub item_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub product_ids: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub limit: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub offset: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StageInput {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub lost_reason: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub probability: Option<i32>,
    pub stage: OpportunityStage,
}

impl Client {
    /// `POST /api/v1/baseline-item-types`.
    pub async fn create_baseline_item_type(
        &self,
        body: &BaselineItemTypeInput,
    ) -> Result<crate::attributes::BaselineItemType, ApiError> {
        self.post_json("/api/v1/baseline-item-types", body).await
    }

    /// `GET /api/v1/baseline-item-types/{id}`.
    pub async fn get_baseline_item_type(
        &self,
        id: Uuid,
    ) -> Result<crate::attributes::BaselineItemType, ApiError> {
        self.get_json(&format!("/api/v1/baseline-item-types/{id}"), &())
            .await
    }

    /// `PUT /api/v1/baseline-item-types/{id}`.
    pub async fn update_baseline_item_type(
        &self,
        id: Uuid,
        body: &BaselineItemTypeUpdate,
    ) -> Result<crate::attributes::BaselineItemType, ApiError> {
        self.put_json(&format!("/api/v1/baseline-item-types/{id}"), body)
            .await
    }

    /// `DELETE /api/v1/baseline-item-types/{id}`.
    pub async fn delete_baseline_item_type(&self, id: Uuid) -> Result<(), ApiError> {
        self.delete_empty(&format!("/api/v1/baseline-item-types/{id}"))
            .await
    }

    /// `GET /api/v1/match-rules`.
    pub async fn list_match_rules(&self) -> Result<Vec<MatchRule>, ApiError> {
        self.get_json("/api/v1/match-rules", &()).await
    }

    /// `POST /api/v1/match-rules`.
    pub async fn create_match_rule(&self, body: &MatchRuleInput) -> Result<MatchRule, ApiError> {
        self.post_json("/api/v1/match-rules", body).await
    }

    /// `GET /api/v1/match-rules/{id}`.
    pub async fn get_match_rule(&self, id: Uuid) -> Result<MatchRule, ApiError> {
        self.get_json(&format!("/api/v1/match-rules/{id}"), &())
            .await
    }

    /// `PUT /api/v1/match-rules/{id}`.
    pub async fn update_match_rule(
        &self,
        id: Uuid,
        body: &MatchRuleInput,
    ) -> Result<MatchRule, ApiError> {
        self.put_json(&format!("/api/v1/match-rules/{id}"), body)
            .await
    }

    /// `DELETE /api/v1/match-rules/{id}`.
    pub async fn delete_match_rule(&self, id: Uuid) -> Result<(), ApiError> {
        self.delete_empty(&format!("/api/v1/match-rules/{id}"))
            .await
    }

    /// `GET /api/v1/opportunities`.
    pub async fn list_opportunities(
        &self,
        params: &ListOpportunitiesParams,
    ) -> Result<OpportunityPage, ApiError> {
        self.get_json("/api/v1/opportunities", params).await
    }

    /// `POST /api/v1/opportunities`.
    pub async fn create_opportunity(
        &self,
        body: &OpportunityInput,
    ) -> Result<Opportunity, ApiError> {
        self.post_json("/api/v1/opportunities", body).await
    }

    /// `GET /api/v1/opportunities/pipeline`.
    pub async fn opportunity_pipeline(&self) -> Result<Vec<PipelineStage>, ApiError> {
        self.get_json("/api/v1/opportunities/pipeline", &()).await
    }

    /// `GET /api/v1/opportunities/{id}`.
    pub async fn get_opportunity(&self, id: Uuid) -> Result<Opportunity, ApiError> {
        self.get_json(&format!("/api/v1/opportunities/{id}"), &())
            .await
    }

    /// `PUT /api/v1/opportunities/{id}`.
    pub async fn update_opportunity(
        &self,
        id: Uuid,
        body: &OpportunityInput,
    ) -> Result<Opportunity, ApiError> {
        self.put_json(&format!("/api/v1/opportunities/{id}"), body)
            .await
    }

    /// `GET /api/v1/opportunities/{id}/baseline`.
    pub async fn get_baseline(&self, id: Uuid) -> Result<Vec<BaselineItem>, ApiError> {
        self.get_json(&format!("/api/v1/opportunities/{id}/baseline"), &())
            .await
    }

    /// `POST /api/v1/opportunities/{id}/baseline/import`.
    pub async fn import_baseline(
        &self,
        id: Uuid,
        params: &ImportBaselineParams,
        body: &serde_json::Value,
    ) -> Result<BaselineImportReport, ApiError> {
        self.post_json_with_query(
            &format!("/api/v1/opportunities/{id}/baseline/import"),
            params,
            body,
        )
        .await
    }

    /// `POST /api/v1/opportunities/{id}/baseline/items`.
    pub async fn create_baseline_item(
        &self,
        id: Uuid,
        body: &BaselineItemInput,
    ) -> Result<BaselineItem, ApiError> {
        self.post_json(&format!("/api/v1/opportunities/{id}/baseline/items"), body)
            .await
    }

    /// `PUT /api/v1/opportunities/{id}/baseline/items/{item_id}`.
    pub async fn update_baseline_item(
        &self,
        id: Uuid,
        item_id: Uuid,
        body: &BaselineItemUpdate,
    ) -> Result<BaselineItem, ApiError> {
        self.put_json(
            &format!("/api/v1/opportunities/{id}/baseline/items/{item_id}"),
            body,
        )
        .await
    }

    /// `DELETE /api/v1/opportunities/{id}/baseline/items/{item_id}`.
    pub async fn delete_baseline_item(&self, id: Uuid, item_id: Uuid) -> Result<(), ApiError> {
        self.delete_empty(&format!(
            "/api/v1/opportunities/{id}/baseline/items/{item_id}"
        ))
        .await
    }

    /// `GET /api/v1/opportunities/{id}/baseline/items/{item_id}/source`.
    pub async fn get_baseline_source(
        &self,
        id: Uuid,
        item_id: Uuid,
    ) -> Result<serde_json::Value, ApiError> {
        self.get_json(
            &format!("/api/v1/opportunities/{id}/baseline/items/{item_id}/source"),
            &(),
        )
        .await
    }

    /// `GET /api/v1/opportunities/{id}/product-matches`.
    pub async fn product_matches(
        &self,
        id: Uuid,
        params: &ProductMatchesParams,
    ) -> Result<ProductMatchPage, ApiError> {
        self.get_json(
            &format!("/api/v1/opportunities/{id}/product-matches"),
            params,
        )
        .await
    }

    /// `POST /api/v1/opportunities/{id}/stage`.
    pub async fn change_opportunity_stage(
        &self,
        id: Uuid,
        body: &StageInput,
    ) -> Result<Opportunity, ApiError> {
        self.post_json(&format!("/api/v1/opportunities/{id}/stage"), body)
            .await
    }
}
