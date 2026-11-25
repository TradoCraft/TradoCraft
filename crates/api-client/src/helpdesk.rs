//! Helpdesk DTOs and endpoints (`/api/v1/tickets`, `/api/v1/prepared-answers`).

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::client::Client;
use crate::error::ApiError;
use crate::portal::FileInfo;

/// SLA status of one target (`first_response` or `resolution`) on a ticket
/// (OpenAPI schema `TargetState`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TargetState {
    pub breached: bool,
    pub at_risk: bool,
    #[serde(default)]
    pub due_at: Option<DateTime<Utc>>,
    #[serde(default)]
    pub met_at: Option<DateTime<Utc>>,
    #[serde(default)]
    pub minutes_remaining: Option<i64>,
}

/// Evaluated SLA state for a ticket (OpenAPI schema `TicketSla`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TicketSla {
    /// `none | on_time | at_risk | breached`
    pub state: String,
    pub paused: bool,
    pub first_response: TargetState,
    pub resolution: TargetState,
    pub first_response_breached: bool,
    pub resolution_breached: bool,
}

/// Helpdesk ticket record returned by `GET /api/v1/tickets` and nested in [`TicketDetail`]
/// (OpenAPI schema `Ticket`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TicketSummary {
    pub id: Uuid,
    #[serde(default)]
    pub version: i64,
    pub number: String,
    pub subject: String,
    /// `new | open | pending_customer | pending_internal | closed`
    pub status: String,
    /// `low | normal | high | urgent`
    pub priority: String,
    /// `question | lead | quote_change | order_confirmation | production_question | service | complaint | other`
    pub category: String,
    #[serde(default)]
    pub suggested_category: Option<String>,
    /// `nl | fr | en | de | es`
    pub language: String,
    /// `record | detected | agent`
    pub language_source: String,
    #[serde(default)]
    pub customer_id: Option<Uuid>,
    #[serde(default)]
    pub customer_name: Option<String>,
    #[serde(default)]
    pub contact_id: Option<Uuid>,
    pub contact_name: String,
    pub contact_email: String,
    #[serde(default)]
    pub owner_user_id: Option<Uuid>,
    #[serde(default)]
    pub owner_name: Option<String>,
    pub internal: bool,
    #[serde(default)]
    pub quotation_id: Option<Uuid>,
    #[serde(default)]
    pub quotation_number: Option<String>,
    #[serde(default)]
    pub quotation_revision: Option<i32>,
    #[serde(default)]
    pub quotation_status: Option<String>,
    #[serde(default)]
    pub opportunity_id: Option<Uuid>,
    #[serde(default)]
    pub opportunity_number: Option<String>,
    #[serde(default)]
    pub order_id: Option<Uuid>,
    #[serde(default)]
    pub order_number: Option<String>,
    pub article_count: i64,
    pub checklist_total: i64,
    pub checklist_done: i64,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    #[serde(default)]
    pub first_response_at: Option<DateTime<Utc>>,
    #[serde(default)]
    pub closed_at: Option<DateTime<Utc>>,
    #[serde(default)]
    pub team_id: Option<Uuid>,
    #[serde(default)]
    pub team_name: Option<String>,
    #[serde(default)]
    pub tags: Vec<String>,
    pub time_minutes: i64,
    #[serde(default)]
    pub merged_into_id: Option<Uuid>,
    #[serde(default)]
    pub merged_into_number: Option<String>,
    #[serde(default)]
    pub csat_rating: Option<String>,
    #[serde(default)]
    pub csat_comment: Option<String>,
    #[serde(default)]
    pub csat_rated_at: Option<DateTime<Utc>>,
    #[serde(default)]
    pub escalated_at: Option<DateTime<Utc>>,
    #[serde(default)]
    pub escalated_by: Option<Uuid>,
    #[serde(default)]
    pub escalated_by_name: Option<String>,
    pub unread: bool,
    pub watching: bool,
    pub sla: TicketSla,
}

/// Paginated response from `GET /api/v1/tickets` (OpenAPI schema `TicketPage`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TicketPage {
    pub items: Vec<TicketSummary>,
    pub total: i64,
}

/// Message, internal note, or call article in a ticket thread (OpenAPI schema `Article`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TicketArticle {
    pub id: Uuid,
    /// `email_in | email_out | note | call_in | call_out | portal_in`
    pub kind: String,
    pub from_address: String,
    pub from_name: String,
    #[serde(default)]
    pub to_addresses: Vec<String>,
    #[serde(default)]
    pub cc_addresses: Vec<String>,
    pub subject: String,
    pub body: String,
    #[serde(default)]
    pub language: Option<String>,
    #[serde(default)]
    pub author_user_id: Option<Uuid>,
    #[serde(default)]
    pub author_name: Option<String>,
    #[serde(default)]
    pub contact_id: Option<Uuid>,
    #[serde(default)]
    pub contact_name: Option<String>,
    #[serde(default)]
    pub phone_number: Option<String>,
    #[serde(default)]
    pub duration_seconds: Option<i32>,
    /// `queued | sent | failed`
    #[serde(default)]
    pub delivery: Option<String>,
    #[serde(default)]
    pub delivery_error: Option<String>,
    pub created_at: DateTime<Utc>,
    #[serde(default)]
    pub sent_at: Option<DateTime<Utc>>,
    #[serde(default)]
    pub attachments: Vec<FileInfo>,
}

/// Colleague watching a ticket (OpenAPI schema `Watcher`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TicketWatcher {
    pub user_id: Uuid,
    pub user_name: String,
    pub created_at: DateTime<Utc>,
}

/// Colleague who opened a ticket ("seen by") (OpenAPI schema `Reader`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TicketReader {
    pub user_id: Uuid,
    pub user_name: String,
    pub last_read_at: DateTime<Utc>,
}

/// Full ticket detail returned by `GET /api/v1/tickets/{id}` and ticket mutations
/// (OpenAPI schema `TicketDetail`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TicketDetail {
    pub ticket: TicketSummary,
    #[serde(default)]
    pub articles: Vec<TicketArticle>,
    #[serde(default)]
    pub watchers: Vec<TicketWatcher>,
    #[serde(default)]
    pub readers: Vec<TicketReader>,
}

/// Request payload for `POST /api/v1/tickets` (OpenAPI schema `NewTicketInput`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CreateTicketInput {
    pub subject: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub customer_id: Option<Uuid>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub contact_id: Option<Uuid>,
    #[serde(default)]
    pub contact_name: String,
    #[serde(default)]
    pub contact_email: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub language: Option<String>,
    #[serde(default = "default_ticket_category")]
    pub category: String,
    #[serde(default)]
    pub internal: bool,
    /// First internal note describing what was asked.
    pub body: String,
}

fn default_ticket_category() -> String {
    "question".to_string()
}

impl Default for CreateTicketInput {
    fn default() -> Self {
        Self {
            subject: String::new(),
            customer_id: None,
            contact_id: None,
            contact_name: String::new(),
            contact_email: String::new(),
            language: None,
            category: default_ticket_category(),
            internal: false,
            body: String::new(),
        }
    }
}

/// Request payload for `PUT /api/v1/tickets/{id}` (OpenAPI schema `TicketInput`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct UpdateTicketInput {
    pub subject: String,
    pub status: String,
    pub priority: String,
    pub category: String,
    pub language: String,
    #[serde(default)]
    pub owner_user_id: Option<Uuid>,
    #[serde(default)]
    pub customer_id: Option<Uuid>,
    #[serde(default)]
    pub contact_id: Option<Uuid>,
    #[serde(default)]
    pub contact_name: String,
    #[serde(default)]
    pub contact_email: String,
    #[serde(default)]
    pub quotation_id: Option<Uuid>,
    #[serde(default)]
    pub opportunity_id: Option<Uuid>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub expected_version: Option<i64>,
}

impl From<&TicketSummary> for UpdateTicketInput {
    fn from(t: &TicketSummary) -> Self {
        Self {
            subject: t.subject.clone(),
            status: t.status.clone(),
            priority: t.priority.clone(),
            category: t.category.clone(),
            language: t.language.clone(),
            owner_user_id: t.owner_user_id,
            customer_id: t.customer_id,
            contact_id: t.contact_id,
            contact_name: t.contact_name.clone(),
            contact_email: t.contact_email.clone(),
            quotation_id: t.quotation_id,
            opportunity_id: t.opportunity_id,
            expected_version: Some(t.version),
        }
    }
}

/// Published library PDF variant reference attached to a reply (OpenAPI schema `LibraryPdf`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LibraryPdf {
    pub document_id: Uuid,
    pub revision: i32,
    pub language: String,
}

/// Request payload for `POST /api/v1/tickets/{id}/replies` (OpenAPI schema `ReplyInput`).
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ReplyInput {
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub to: Vec<String>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub cc: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub subject: Option<String>,
    pub body: String,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub attachment_ids: Vec<Uuid>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub library_pdfs: Vec<LibraryPdf>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub status: Option<String>,
}

/// Request payload for `POST /api/v1/tickets/{id}/notes` (OpenAPI schema `NoteInput`).
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct NoteInput {
    pub body: String,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub attachment_ids: Vec<Uuid>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub status: Option<String>,
}

/// Request payload for `POST /api/v1/tickets/{id}/tags` (OpenAPI schema `TagInput`).
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TagInput {
    pub tag: String,
}

/// Single logged time entry on a ticket (OpenAPI schema `TimeEntry`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TicketTimeEntry {
    pub id: Uuid,
    pub user_id: Uuid,
    pub user_name: String,
    pub minutes: i32,
    pub note: String,
    pub billable: bool,
    pub created_at: DateTime<Utc>,
}

/// List and totals returned by `GET` / `POST /api/v1/tickets/{id}/time-entries`
/// (OpenAPI schema `TimeEntries`).
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TicketTimeEntries {
    #[serde(default)]
    pub items: Vec<TicketTimeEntry>,
    pub total_minutes: i64,
    pub billable_minutes: i64,
}

/// Request payload for `POST /api/v1/tickets/{id}/time-entries` (OpenAPI schema `TimeEntryInput`).
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TimeEntryInput {
    /// 1 to 1440.
    pub minutes: i32,
    #[serde(default)]
    pub note: String,
    #[serde(default)]
    pub billable: bool,
}

/// Request payload for `POST /api/v1/tickets/{id}/escalate` (OpenAPI schema `EscalateInput`).
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct EscalateInput {
    pub reason: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub to_user_id: Option<Uuid>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub to_team_id: Option<Uuid>,
    #[serde(default)]
    pub raise_priority: bool,
}

/// Request payload for `POST /api/v1/tickets/{id}/status` (OpenAPI schema `TicketStatusInput`).
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TicketStatusInput {
    /// `new | open | pending_customer | pending_internal | closed`
    pub status: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub expected_version: Option<i64>,
}

/// Localized variant of a [`PreparedAnswer`] (OpenAPI schema `AnswerText`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AnswerText {
    /// `nl | fr | en | de | es`
    pub language: String,
    #[serde(default)]
    pub subject: String,
    pub body: String,
}

/// Reusable reply / note template returned by `GET /api/v1/prepared-answers`
/// (OpenAPI schema `PreparedAnswer`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PreparedAnswer {
    pub id: Uuid,
    pub code: String,
    pub name: String,
    #[serde(default)]
    pub category: Option<String>,
    /// `reply | internal_note | handover | notice`
    pub kind: String,
    #[serde(default)]
    pub team_id: Option<Uuid>,
    #[serde(default)]
    pub keywords: Vec<String>,
    pub active: bool,
    pub updated_at: DateTime<Utc>,
    #[serde(default)]
    pub texts: Vec<AnswerText>,
}

/// Query parameters for `GET /api/v1/tickets`.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
pub struct ListTicketsParams {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub q: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub status: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub owner: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub customer_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub category: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub team_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub mine: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub unassigned: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sla: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tag: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub unread: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub watching: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub escalated: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub limit: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub offset: Option<i64>,
}

impl ListTicketsParams {
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

    pub fn owner(mut self, owner: impl Into<String>) -> Self {
        self.owner = Some(owner.into());
        self
    }

    pub fn customer_id(mut self, customer_id: Uuid) -> Self {
        self.customer_id = Some(customer_id);
        self
    }

    pub fn category(mut self, category: impl Into<String>) -> Self {
        self.category = Some(category.into());
        self
    }

    pub fn team_id(mut self, team_id: Uuid) -> Self {
        self.team_id = Some(team_id);
        self
    }

    pub fn mine(mut self, mine: bool) -> Self {
        self.mine = Some(mine);
        self
    }

    pub fn unassigned(mut self, unassigned: bool) -> Self {
        self.unassigned = Some(unassigned);
        self
    }

    pub fn sla(mut self, sla: impl Into<String>) -> Self {
        self.sla = Some(sla.into());
        self
    }

    pub fn tag(mut self, tag: impl Into<String>) -> Self {
        self.tag = Some(tag.into());
        self
    }

    pub fn unread(mut self, unread: bool) -> Self {
        self.unread = Some(unread);
        self
    }

    pub fn watching(mut self, watching: bool) -> Self {
        self.watching = Some(watching);
        self
    }

    pub fn escalated(mut self, escalated: bool) -> Self {
        self.escalated = Some(escalated);
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

/// Query parameters for `GET /api/v1/prepared-answers`.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
pub struct ListPreparedAnswersParams {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub q: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub active: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub kind: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub team_id: Option<Uuid>,
}

impl ListPreparedAnswersParams {
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

    pub fn kind(mut self, kind: impl Into<String>) -> Self {
        self.kind = Some(kind.into());
        self
    }

    pub fn team_id(mut self, team_id: Uuid) -> Self {
        self.team_id = Some(team_id);
        self
    }
}

impl Client {
    /// Lists tickets matching `params` (`GET /api/v1/tickets`).
    pub async fn list_tickets(&self, params: &ListTicketsParams) -> Result<TicketPage, ApiError> {
        self.get_json("/api/v1/tickets", params).await
    }

    /// Creates a ticket manually (`POST /api/v1/tickets`).
    pub async fn create_ticket(&self, req: &CreateTicketInput) -> Result<TicketDetail, ApiError> {
        self.post_json("/api/v1/tickets", req).await
    }

    /// Fetches a ticket with articles, watchers, and readers (`GET /api/v1/tickets/{id}`).
    pub async fn get_ticket(&self, id: Uuid) -> Result<TicketDetail, ApiError> {
        self.get_json(&format!("/api/v1/tickets/{id}"), &()).await
    }

    /// Updates a ticket's properties and links (`PUT /api/v1/tickets/{id}`).
    pub async fn update_ticket(
        &self,
        id: Uuid,
        req: &UpdateTicketInput,
    ) -> Result<TicketDetail, ApiError> {
        self.put_json(&format!("/api/v1/tickets/{id}"), req).await
    }

    /// Queues an email reply to the customer (`POST /api/v1/tickets/{id}/replies`).
    pub async fn reply_ticket(&self, id: Uuid, req: &ReplyInput) -> Result<TicketDetail, ApiError> {
        self.post_json(&format!("/api/v1/tickets/{id}/replies"), req)
            .await
    }

    /// Adds an internal note to a ticket (`POST /api/v1/tickets/{id}/notes`).
    pub async fn add_ticket_note(
        &self,
        id: Uuid,
        req: &NoteInput,
    ) -> Result<TicketDetail, ApiError> {
        self.post_json(&format!("/api/v1/tickets/{id}/notes"), req)
            .await
    }

    /// Adds a tag to a ticket (`POST /api/v1/tickets/{id}/tags`).
    pub async fn add_ticket_tag(&self, id: Uuid, req: &TagInput) -> Result<TicketDetail, ApiError> {
        self.post_json(&format!("/api/v1/tickets/{id}/tags"), req)
            .await
    }

    /// Lists logged time entries on a ticket (`GET /api/v1/tickets/{id}/time-entries`).
    pub async fn list_ticket_time_entries(&self, id: Uuid) -> Result<TicketTimeEntries, ApiError> {
        self.get_json(&format!("/api/v1/tickets/{id}/time-entries"), &())
            .await
    }

    /// Logs a time entry on a ticket (`POST /api/v1/tickets/{id}/time-entries`).
    pub async fn add_ticket_time_entry(
        &self,
        id: Uuid,
        req: &TimeEntryInput,
    ) -> Result<TicketTimeEntries, ApiError> {
        self.post_json(&format!("/api/v1/tickets/{id}/time-entries"), req)
            .await
    }

    /// Escalates a ticket (`POST /api/v1/tickets/{id}/escalate`).
    pub async fn escalate_ticket(
        &self,
        id: Uuid,
        req: &EscalateInput,
    ) -> Result<TicketDetail, ApiError> {
        self.post_json(&format!("/api/v1/tickets/{id}/escalate"), req)
            .await
    }

    /// Changes only the status of a ticket (`POST /api/v1/tickets/{id}/status`).
    pub async fn change_ticket_status(
        &self,
        id: Uuid,
        req: &TicketStatusInput,
    ) -> Result<TicketDetail, ApiError> {
        self.post_json(&format!("/api/v1/tickets/{id}/status"), req)
            .await
    }

    /// Lists prepared answers (`GET /api/v1/prepared-answers`).
    pub async fn list_prepared_answers(
        &self,
        params: &ListPreparedAnswersParams,
    ) -> Result<Vec<PreparedAnswer>, ApiError> {
        self.get_json("/api/v1/prepared-answers", params).await
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_ticket_json() -> &'static str {
        r#"{
            "id": "01900000-0000-7000-8000-000000000801",
            "version": 3,
            "number": "TCK-2026-0007",
            "subject": "Pump noise above 1500 rpm",
            "status": "open",
            "priority": "high",
            "category": "service",
            "suggested_category": "service",
            "language": "nl",
            "language_source": "record",
            "customer_id": "01900000-0000-7000-8000-000000000401",
            "customer_name": "Alpha Installaties NV",
            "contact_id": "01900000-0000-7000-8000-000000000411",
            "contact_name": "Jan Peeters",
            "contact_email": "jan@alpha.example",
            "owner_user_id": "01900000-0000-7000-8000-000000000010",
            "owner_name": "Support Agent",
            "internal": false,
            "quotation_id": null,
            "quotation_number": null,
            "quotation_revision": null,
            "quotation_status": null,
            "opportunity_id": null,
            "opportunity_number": null,
            "order_id": "01900000-0000-7000-8000-000000000601",
            "order_number": "SO-2026-0018",
            "article_count": 2,
            "checklist_total": 3,
            "checklist_done": 1,
            "created_at": "2026-11-20T09:00:00Z",
            "updated_at": "2026-11-20T10:30:00Z",
            "first_response_at": "2026-11-20T09:15:00Z",
            "closed_at": null,
            "team_id": "01900000-0000-7000-8000-000000000701",
            "team_name": "Field Service",
            "tags": ["warranty", "pump"],
            "time_minutes": 45,
            "merged_into_id": null,
            "merged_into_number": null,
            "csat_rating": null,
            "csat_comment": null,
            "csat_rated_at": null,
            "escalated_at": null,
            "escalated_by": null,
            "escalated_by_name": null,
            "unread": true,
            "watching": true,
            "sla": {
                "state": "on_time",
                "paused": false,
                "first_response": {
                    "breached": false,
                    "at_risk": false,
                    "due_at": "2026-11-20T11:00:00Z",
                    "met_at": "2026-11-20T09:15:00Z",
                    "minutes_remaining": null
                },
                "resolution": {
                    "breached": false,
                    "at_risk": false,
                    "due_at": "2026-11-21T17:00:00Z",
                    "met_at": null,
                    "minutes_remaining": 1800
                },
                "first_response_breached": false,
                "resolution_breached": false
            }
        }"#
    }

    #[test]
    fn deserialize_ticket_page_and_detail() {
        let page_json = format!(r#"{{"total": 1, "items": [{}]}}"#, sample_ticket_json());
        let page: TicketPage = serde_json::from_str(&page_json).unwrap();
        assert_eq!(page.total, 1);
        assert_eq!(page.items[0].number, "TCK-2026-0007");
        assert_eq!(page.items[0].tags, vec!["warranty", "pump"]);
        assert_eq!(page.items[0].sla.state, "on_time");
        assert_eq!(page.items[0].sla.resolution.minutes_remaining, Some(1800));

        let detail_json = format!(
            r#"{{
                "ticket": {},
                "articles": [
                    {{
                        "id": "01900000-0000-7000-8000-000000000811",
                        "kind": "email_in",
                        "from_address": "jan@alpha.example",
                        "from_name": "Jan Peeters",
                        "to_addresses": ["support@tradocraft.example"],
                        "cc_addresses": [],
                        "subject": "Pump noise above 1500 rpm",
                        "body": "Bearing hum starts after warm-up.",
                        "language": "nl",
                        "author_user_id": null,
                        "author_name": null,
                        "contact_id": "01900000-0000-7000-8000-000000000411",
                        "contact_name": "Jan Peeters",
                        "phone_number": null,
                        "duration_seconds": null,
                        "delivery": null,
                        "delivery_error": null,
                        "created_at": "2026-11-20T09:00:00Z",
                        "sent_at": null,
                        "attachments": [
                            {{
                                "id": "01900000-0000-7000-8000-000000000821",
                                "filename": "pump-audio.pdf",
                                "content_type": "application/pdf",
                                "size_bytes": 4096,
                                "uploader_name": "Jan Peeters",
                                "created_at": "2026-11-20T09:00:00Z"
                            }}
                        ]
                    }}
                ],
                "watchers": [
                    {{
                        "user_id": "01900000-0000-7000-8000-000000000010",
                        "user_name": "Support Agent",
                        "created_at": "2026-11-20T09:05:00Z"
                    }}
                ],
                "readers": [
                    {{
                        "user_id": "01900000-0000-7000-8000-000000000010",
                        "user_name": "Support Agent",
                        "last_read_at": "2026-11-20T10:30:00Z"
                    }}
                ]
            }}"#,
            sample_ticket_json()
        );
        let detail: TicketDetail = serde_json::from_str(&detail_json).unwrap();
        assert_eq!(detail.ticket.version, 3);
        assert_eq!(detail.articles.len(), 1);
        assert_eq!(detail.articles[0].attachments.len(), 1);
        assert_eq!(detail.watchers.len(), 1);
        assert_eq!(detail.readers.len(), 1);

        let update_from_summary = UpdateTicketInput::from(&detail.ticket);
        assert_eq!(update_from_summary.expected_version, Some(3));
        assert_eq!(update_from_summary.customer_id, detail.ticket.customer_id);
    }

    #[test]
    fn deserialize_time_entries_and_prepared_answers() {
        let time_json = r#"{
            "items": [
                {
                    "id": "01900000-0000-7000-8000-000000000831",
                    "user_id": "01900000-0000-7000-8000-000000000010",
                    "user_name": "Support Agent",
                    "minutes": 45,
                    "note": "Checked pump curve and warranty",
                    "billable": true,
                    "created_at": "2026-11-20T10:15:00Z"
                }
            ],
            "total_minutes": 45,
            "billable_minutes": 45
        }"#;
        let entries: TicketTimeEntries = serde_json::from_str(time_json).unwrap();
        assert_eq!(entries.total_minutes, 45);
        assert_eq!(entries.billable_minutes, 45);
        assert_eq!(entries.items[0].minutes, 45);
        assert!(entries.items[0].billable);

        let answers_json = r#"[
            {
                "id": "01900000-0000-7000-8000-000000000841",
                "code": "pump-bleed",
                "name": "Pump bleeding instructions",
                "category": "service",
                "kind": "reply",
                "team_id": null,
                "keywords": ["air", "noise", "pump"],
                "active": true,
                "updated_at": "2026-11-18T08:00:00Z",
                "texts": [
                    {
                        "language": "en",
                        "subject": "Re: Venting air from pump",
                        "body": "Please open the air vent screw slowly."
                    },
                    {
                        "language": "nl",
                        "subject": "Re: Pomp ontluchten",
                        "body": "Draai de ontluchtingsschroef voorzichtig open."
                    }
                ]
            }
        ]"#;
        let answers: Vec<PreparedAnswer> = serde_json::from_str(answers_json).unwrap();
        assert_eq!(answers.len(), 1);
        assert_eq!(answers[0].code, "pump-bleed");
        assert_eq!(answers[0].texts.len(), 2);
        assert_eq!(answers[0].texts[1].language, "nl");
    }

    #[test]
    fn serialize_inputs_and_query_params() {
        let create = CreateTicketInput {
            subject: "Valve leak".to_string(),
            body: "Customer reported seepage on flange.".to_string(),
            ..CreateTicketInput::default()
        };
        let create_val = serde_json::to_value(&create).unwrap();
        assert_eq!(create_val["category"], "question");
        assert!(create_val.get("customer_id").is_none());

        let reply = ReplyInput {
            body: "We shipped a replacement seal.".to_string(),
            status: Some("pending_customer".to_string()),
            ..ReplyInput::default()
        };
        let reply_val = serde_json::to_value(&reply).unwrap();
        assert!(reply_val.get("to").is_none());
        assert!(reply_val.get("attachment_ids").is_none());
        assert_eq!(reply_val["status"], "pending_customer");

        let note = NoteInput {
            body: "Checked serial number in ERP.".to_string(),
            ..NoteInput::default()
        };
        let note_val = serde_json::to_value(&note).unwrap();
        assert!(note_val.get("status").is_none());

        let tag = TagInput {
            tag: "urgent-field".to_string(),
        };
        assert_eq!(serde_json::to_value(&tag).unwrap()["tag"], "urgent-field");

        let time = TimeEntryInput {
            minutes: 30,
            note: "Diagnostic call".to_string(),
            billable: true,
        };
        let time_val = serde_json::to_value(&time).unwrap();
        assert_eq!(time_val["minutes"], 30);
        assert_eq!(time_val["billable"], true);

        let escalate = EscalateInput {
            reason: "Needs senior engineer".to_string(),
            raise_priority: true,
            ..EscalateInput::default()
        };
        let esc_val = serde_json::to_value(&escalate).unwrap();
        assert_eq!(esc_val["raise_priority"], true);
        assert!(esc_val.get("to_user_id").is_none());

        let status = TicketStatusInput {
            status: "closed".to_string(),
            expected_version: Some(4),
        };
        assert_eq!(serde_json::to_value(&status).unwrap()["status"], "closed");

        let ticket_params = ListTicketsParams::new()
            .q("pump")
            .status("active")
            .mine(true)
            .limit(25);
        let req = reqwest::Client::new()
            .get("http://localhost:8080/api/v1/tickets")
            .query(&ticket_params)
            .build()
            .unwrap();
        assert_eq!(
            req.url().query(),
            Some("q=pump&status=active&mine=true&limit=25")
        );

        let answer_params = ListPreparedAnswersParams::new()
            .q("pump")
            .active(true)
            .kind("reply");
        let ans_req = reqwest::Client::new()
            .get("http://localhost:8080/api/v1/prepared-answers")
            .query(&answer_params)
            .build()
            .unwrap();
        assert_eq!(ans_req.url().query(), Some("q=pump&active=true&kind=reply"));
    }
}
