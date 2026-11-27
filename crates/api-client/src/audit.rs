//! The audit trail (`/api/v1/audit/...`, ADR 0059): who did what to which record, and when.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::client::Client;
use crate::error::ApiError;

/// One audited event (OpenAPI schema `AuditEvent`).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AuditEvent {
    /// Increases with time; the cursor for the next page.
    pub id: i64,
    pub occurred_at: DateTime<Utc>,
    /// The kind of record (`customer`, `quotation`, ...).
    pub entity: String,
    pub entity_id: Uuid,
    /// What happened (`created`, `updated`, ...).
    pub action: String,
    /// What the module recorded; for an update usually `{"changes": {"field": {"from", "to"}}}`.
    pub data: serde_json::Value,
    /// Absent for an event without a staff user.
    #[serde(default)]
    pub user_id: Option<Uuid>,
    #[serde(default)]
    pub user_name: Option<String>,
    #[serde(default)]
    pub user_email: Option<String>,
}

/// A page of events, newest first (OpenAPI schema `AuditPage`).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AuditPage {
    pub items: Vec<AuditEvent>,
    /// Pass as `before_id` for the next (older) page; absent on the last page.
    #[serde(default)]
    pub next_before_id: Option<i64>,
}

/// What the filters can offer (OpenAPI schema `AuditFacets`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AuditFacets {
    /// The kinds of record that have events in this company, alphabetically.
    pub entities: Vec<String>,
}

/// Query parameters of `GET /api/v1/audit/events`.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
pub struct ListAuditEventsParams {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub entity: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub entity_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub action: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub user_id: Option<Uuid>,
    /// Inclusive lower bound of `occurred_at`.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub from: Option<DateTime<Utc>>,
    /// Exclusive upper bound of `occurred_at`.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub to: Option<DateTime<Utc>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub before_id: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub limit: Option<i64>,
}

impl Client {
    /// The company-wide audit trail, newest first (`GET /api/v1/audit/events`).
    pub async fn list_audit_events(
        &self,
        params: &ListAuditEventsParams,
    ) -> Result<AuditPage, ApiError> {
        self.get_json("/api/v1/audit/events", params).await
    }

    /// What the audit filters can offer (`GET /api/v1/audit/facets`).
    pub async fn audit_facets(&self) -> Result<AuditFacets, ApiError> {
        self.get_json("/api/v1/audit/facets", &()).await
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decodes_page_and_encodes_filters() {
        let page: AuditPage = serde_json::from_str(
            r#"{"items":[{"id":7,"occurred_at":"2026-11-26T10:00:00Z","entity":"customer",
            "entity_id":"00000000-0000-0000-0000-000000000001","action":"updated",
            "data":{"changes":{"name":{"from":"A","to":"B"}}},"user_id":null}],"next_before_id":7}"#,
        )
        .unwrap();
        assert_eq!(page.items[0].data["changes"]["name"]["to"], "B");
        assert_eq!(page.next_before_id, Some(7));
        let params = ListAuditEventsParams {
            entity: Some("customer".into()),
            before_id: Some(7),
            ..ListAuditEventsParams::default()
        };
        assert_eq!(
            serde_json::to_string(&params).unwrap(),
            r#"{"entity":"customer","before_id":7}"#
        );
    }
}
