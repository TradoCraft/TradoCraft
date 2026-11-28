//! Record chatter, scheduled activities, followers, and notifications inbox
//! (`/api/v1/chatter/...`, ADR 0086).

use chrono::{DateTime, NaiveDate, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::client::Client;
use crate::error::ApiError;
use crate::portal::FileInfo;

/// Kinds of business record that host a chatter panel.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RecordKind {
    Customer,
    Quotation,
    Order,
    Opportunity,
}

impl RecordKind {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Customer => "customer",
            Self::Quotation => "quotation",
            Self::Order => "order",
            Self::Opportunity => "opportunity",
        }
    }

    pub fn parse(raw: &str) -> Option<Self> {
        match raw {
            "customer" => Some(Self::Customer),
            "quotation" => Some(Self::Quotation),
            "order" => Some(Self::Order),
            "opportunity" => Some(Self::Opportunity),
            _ => None,
        }
    }

    /// App path prefix inside `/app` that opens a record of this kind.
    pub fn route_for(self, id: Uuid) -> String {
        match self {
            Self::Customer => format!("/customers/{id}"),
            Self::Quotation => format!("/quotations/{id}"),
            Self::Order => format!("/orders/{id}"),
            Self::Opportunity => format!("/opportunities/{id}"),
        }
    }

    pub fn label(self) -> &'static str {
        match self {
            Self::Customer => "Customer",
            Self::Quotation => "Quotation",
            Self::Order => "Order",
            Self::Opportunity => "Opportunity",
        }
    }
}

/// Activity category on a chatter record (`OpenAPI schema ActivityKind`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ActivityKind {
    Todo,
    Call,
    Email,
    Meeting,
}

impl ActivityKind {
    pub const ALL: [Self; 4] = [Self::Todo, Self::Call, Self::Email, Self::Meeting];

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Todo => "todo",
            Self::Call => "call",
            Self::Email => "email",
            Self::Meeting => "meeting",
        }
    }

    pub fn parse(raw: &str) -> Option<Self> {
        match raw {
            "todo" => Some(Self::Todo),
            "call" => Some(Self::Call),
            "email" => Some(Self::Email),
            "meeting" => Some(Self::Meeting),
            _ => None,
        }
    }

    pub fn label(self) -> &'static str {
        match self {
            Self::Todo => "To-do",
            Self::Call => "Call",
            Self::Email => "Email",
            Self::Meeting => "Meeting",
        }
    }
}

/// One entry in a chatter thread (note or system change message; OpenAPI schema `ThreadItem`).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ThreadItem {
    pub id: Uuid,
    /// `note` | `system`
    pub kind: String,
    #[serde(default)]
    pub author_id: Option<Uuid>,
    #[serde(default)]
    pub author_name: Option<String>,
    pub body: String,
    pub changes: Vec<serde_json::Value>,
    pub created_at: DateTime<Utc>,
    #[serde(default)]
    pub edited_at: Option<DateTime<Utc>>,
    pub editable: bool,
    pub files: Vec<FileInfo>,
}

/// Cursor-paginated chatter thread (`OpenAPI schema ThreadPage`).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ThreadPage {
    pub items: Vec<ThreadItem>,
    #[serde(default)]
    pub next_before_id: Option<Uuid>,
}

/// Query parameters for `GET /api/v1/chatter/{kind}/{id}/thread`.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
pub struct ListThreadParams {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub before_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub limit: Option<i64>,
}

/// Request payload for `POST /api/v1/chatter/{kind}/{id}/notes` (`ChatterNoteInput`).
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ChatterNoteInput {
    pub body: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub client_id: Option<Uuid>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub file_ids: Vec<Uuid>,
}

/// Request payload for `PATCH /api/v1/chatter/notes/{id}` (`ChatterNoteEdit`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ChatterNoteEdit {
    pub body: String,
}

/// Scheduled activity on a record (`OpenAPI schema Activity`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Activity {
    pub id: Uuid,
    pub kind: String,
    pub summary: String,
    pub note: String,
    pub assignee_id: Uuid,
    pub assignee_name: String,
    pub due_date: NaiveDate,
    pub created_by: Uuid,
    pub created_at: DateTime<Utc>,
    pub overdue: bool,
}

/// Request payload for `POST /api/v1/chatter/{kind}/{id}/activities` (`ActivityInput`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ActivityInput {
    pub kind: ActivityKind,
    pub summary: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub note: String,
    pub assignee_id: Uuid,
    pub due_date: NaiveDate,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub client_id: Option<Uuid>,
}

/// Request payload for `PATCH /api/v1/chatter/activities/{id}` (`ActivityPatch`).
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ActivityPatch {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub kind: Option<ActivityKind>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub summary: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub note: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub assignee_id: Option<Uuid>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub due_date: Option<NaiveDate>,
}

/// Request payload for `POST /api/v1/chatter/activities/{id}/done` (`ActivityDoneInput`).
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ActivityDoneInput {
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub note: String,
}

/// Follower entry on a record (`OpenAPI schema Follower`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Follower {
    pub user_id: Uuid,
    pub user_name: String,
    /// `manual` | `author` | `assigned`
    pub reason: String,
    pub followed_at: DateTime<Utc>,
}

/// Follower list & caller status (`OpenAPI schema Followers`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Followers {
    pub items: Vec<Follower>,
    pub following: bool,
}

/// Request payload for `POST /api/v1/chatter/{kind}/{id}/followers` (`FollowerInput`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct FollowerInput {
    pub user_id: Uuid,
}

/// Followed record with unread messages (`OpenAPI schema InboxRecord`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct InboxRecord {
    pub record_kind: String,
    pub record_id: Uuid,
    #[serde(default)]
    pub label: Option<String>,
    pub unread: i64,
    pub last_at: DateTime<Utc>,
}

/// Due or overdue activity assigned to the caller (`OpenAPI schema InboxActivity`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct InboxActivity {
    pub id: Uuid,
    pub record_kind: String,
    pub record_id: Uuid,
    #[serde(default)]
    pub label: Option<String>,
    pub kind: String,
    pub summary: String,
    pub due_date: NaiveDate,
    pub overdue: bool,
}

/// Notifications inbox (`GET /api/v1/chatter/inbox`, OpenAPI schema `Inbox`).
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Inbox {
    pub unread: Vec<InboxRecord>,
    pub activities: Vec<InboxActivity>,
}

impl Client {
    /// Lists messages in a record's chatter thread (`GET /api/v1/chatter/{kind}/{id}/thread`).
    pub async fn chatter_thread(
        &self,
        kind: &str,
        id: Uuid,
        params: &ListThreadParams,
    ) -> Result<ThreadPage, ApiError> {
        self.get_json(&format!("/api/v1/chatter/{kind}/{id}/thread"), params)
            .await
    }

    /// Posts a note (`POST /api/v1/chatter/{kind}/{id}/notes`).
    pub async fn chatter_post_note(
        &self,
        kind: &str,
        id: Uuid,
        req: &ChatterNoteInput,
    ) -> Result<ThreadItem, ApiError> {
        self.post_json(&format!("/api/v1/chatter/{kind}/{id}/notes"), req)
            .await
    }

    /// Edits an own recent note (`PATCH /api/v1/chatter/notes/{id}`).
    pub async fn chatter_edit_note(
        &self,
        note_id: Uuid,
        req: &ChatterNoteEdit,
    ) -> Result<ThreadItem, ApiError> {
        self.patch_json(&format!("/api/v1/chatter/notes/{note_id}"), req)
            .await
    }

    /// Deletes an own recent note (`DELETE /api/v1/chatter/notes/{id}`).
    pub async fn chatter_delete_note(&self, note_id: Uuid) -> Result<(), ApiError> {
        self.delete_empty(&format!("/api/v1/chatter/notes/{note_id}"))
            .await
    }

    /// Uploads a file before attaching it to a note (`POST /api/v1/chatter/{kind}/{id}/files`).
    pub async fn chatter_upload_file(
        &self,
        kind: &str,
        id: Uuid,
        filename: &str,
        client_id: Option<Uuid>,
        bytes: Vec<u8>,
    ) -> Result<FileInfo, ApiError> {
        let mut query: Vec<(&str, String)> = vec![("filename", filename.to_string())];
        if let Some(cid) = client_id {
            query.push(("client_id", cid.to_string()));
        }
        self.post_bytes(&format!("/api/v1/chatter/{kind}/{id}/files"), &query, bytes)
            .await
    }

    /// Downloads a chatter file (`GET /api/v1/chatter/{kind}/{id}/files/{file_id}`).
    pub async fn chatter_download_file(
        &self,
        kind: &str,
        id: Uuid,
        file_id: Uuid,
    ) -> Result<Vec<u8>, ApiError> {
        self.get_bytes(&format!("/api/v1/chatter/{kind}/{id}/files/{file_id}"))
            .await
    }

    /// Lists open scheduled activities on a record (`GET /api/v1/chatter/{kind}/{id}/activities`).
    pub async fn chatter_activities(
        &self,
        kind: &str,
        id: Uuid,
    ) -> Result<Vec<Activity>, ApiError> {
        self.get_json(&format!("/api/v1/chatter/{kind}/{id}/activities"), &())
            .await
    }

    /// Schedules a new activity (`POST /api/v1/chatter/{kind}/{id}/activities`).
    pub async fn chatter_create_activity(
        &self,
        kind: &str,
        id: Uuid,
        req: &ActivityInput,
    ) -> Result<Activity, ApiError> {
        self.post_json(&format!("/api/v1/chatter/{kind}/{id}/activities"), req)
            .await
    }

    /// Updates an open activity (`PATCH /api/v1/chatter/activities/{id}`).
    pub async fn chatter_update_activity(
        &self,
        activity_id: Uuid,
        req: &ActivityPatch,
    ) -> Result<Activity, ApiError> {
        self.patch_json(&format!("/api/v1/chatter/activities/{activity_id}"), req)
            .await
    }

    /// Completes a scheduled activity (`POST /api/v1/chatter/activities/{id}/done`).
    pub async fn chatter_complete_activity(
        &self,
        activity_id: Uuid,
        req: &ActivityDoneInput,
    ) -> Result<(), ApiError> {
        self.post_json_empty(
            &format!("/api/v1/chatter/activities/{activity_id}/done"),
            req,
        )
        .await
    }

    /// Deletes/cancels a scheduled activity (`DELETE /api/v1/chatter/activities/{id}`).
    pub async fn chatter_delete_activity(&self, activity_id: Uuid) -> Result<(), ApiError> {
        self.delete_empty(&format!("/api/v1/chatter/activities/{activity_id}"))
            .await
    }

    /// Lists followers and whether the caller follows the record (`GET /api/v1/chatter/{kind}/{id}/followers`).
    pub async fn chatter_followers(&self, kind: &str, id: Uuid) -> Result<Followers, ApiError> {
        self.get_json(&format!("/api/v1/chatter/{kind}/{id}/followers"), &())
            .await
    }

    /// Follows a record (`PUT /api/v1/chatter/{kind}/{id}/follow`).
    pub async fn chatter_follow(&self, kind: &str, id: Uuid) -> Result<Followers, ApiError> {
        self.put_empty_json(&format!("/api/v1/chatter/{kind}/{id}/follow"))
            .await
    }

    /// Unfollows a record (`DELETE /api/v1/chatter/{kind}/{id}/follow`).
    pub async fn chatter_unfollow(&self, kind: &str, id: Uuid) -> Result<Followers, ApiError> {
        self.delete_json(&format!("/api/v1/chatter/{kind}/{id}/follow"))
            .await
    }

    /// Adds a colleague as follower (`POST /api/v1/chatter/{kind}/{id}/followers`).
    pub async fn chatter_add_follower(
        &self,
        kind: &str,
        id: Uuid,
        req: &FollowerInput,
    ) -> Result<Followers, ApiError> {
        self.post_json(&format!("/api/v1/chatter/{kind}/{id}/followers"), req)
            .await
    }

    /// Removes a follower from a record (`DELETE /api/v1/chatter/{kind}/{id}/followers/{user_id}`).
    pub async fn chatter_remove_follower(
        &self,
        kind: &str,
        id: Uuid,
        user_id: Uuid,
    ) -> Result<Followers, ApiError> {
        self.delete_json(&format!("/api/v1/chatter/{kind}/{id}/followers/{user_id}"))
            .await
    }

    /// Marks the chatter thread as read (`POST /api/v1/chatter/{kind}/{id}/read`).
    pub async fn chatter_mark_read(&self, kind: &str, id: Uuid) -> Result<(), ApiError> {
        self.post_empty(&format!("/api/v1/chatter/{kind}/{id}/read"))
            .await
    }

    /// Loads unread followed records and due activities (`GET /api/v1/chatter/inbox`).
    pub async fn chatter_inbox(&self) -> Result<Inbox, ApiError> {
        self.get_json("/api/v1/chatter/inbox", &()).await
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn record_kind_maps_routes_and_parses() {
        let id = Uuid::nil();
        assert_eq!(RecordKind::parse("customer"), Some(RecordKind::Customer));
        assert_eq!(RecordKind::parse("unknown"), None);
        assert_eq!(
            RecordKind::Quotation.route_for(id),
            format!("/quotations/{id}")
        );
        assert_eq!(RecordKind::Order.route_for(id), format!("/orders/{id}"));
    }

    #[test]
    fn encodes_note_and_activity_inputs() {
        let note = ChatterNoteInput {
            body: "Followed up with customer".to_string(),
            client_id: None,
            file_ids: Vec::new(),
        };
        assert_eq!(
            serde_json::to_string(&note).unwrap(),
            r#"{"body":"Followed up with customer"}"#
        );

        let activity = ActivityInput {
            kind: ActivityKind::Call,
            summary: "Confirm delivery window".to_string(),
            note: String::new(),
            assignee_id: Uuid::nil(),
            due_date: NaiveDate::from_ymd_opt(2026, 12, 15).unwrap(),
            client_id: None,
        };
        let encoded = serde_json::to_string(&activity).unwrap();
        assert!(encoded.contains(r#""kind":"call""#));
        assert!(encoded.contains(r#""due_date":"2026-12-15""#));
    }
}
