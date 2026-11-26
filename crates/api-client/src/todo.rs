//! To-do DTOs and endpoints (`/api/v1/todo/...`, ADR 0061).

use chrono::{DateTime, NaiveDate, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::client::Client;
use crate::error::ApiError;

/// One to-do item (OpenAPI schema `TodoItem`). Lists are flat: build the tree from `parent_id`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TodoItem {
    pub id: Uuid,
    #[serde(default)]
    pub parent_id: Option<Uuid>,
    pub position: i32,
    pub title: String,
    #[serde(default)]
    pub notes: String,
    pub owner_id: Uuid,
    #[serde(default)]
    pub owner_name: String,
    #[serde(default)]
    pub assignee_id: Option<Uuid>,
    #[serde(default)]
    pub assignee_name: Option<String>,
    pub created_by: Uuid,
    /// Whether the caller owns the item (only the owner reassigns and deletes).
    pub mine: bool,
    #[serde(default)]
    pub due_date: Option<NaiveDate>,
    pub done: bool,
    #[serde(default)]
    pub done_at: Option<DateTime<Utc>>,
    #[serde(default)]
    pub done_by: Option<Uuid>,
    #[serde(default)]
    pub link_kind: Option<String>,
    #[serde(default)]
    pub link_id: Option<Uuid>,
    #[serde(default)]
    pub link_label: Option<String>,
    #[serde(default)]
    pub link_location: Option<String>,
    #[serde(default)]
    pub client_id: Option<Uuid>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// Request payload for `POST /api/v1/todo/items` (OpenAPI schema `TodoCreate`).
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TodoCreate {
    /// Chosen by the client; a repeated create with the same id returns the existing item.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub client_id: Option<Uuid>,
    /// Makes the item a sub-item of that root item.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub parent_id: Option<Uuid>,
    pub title: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub notes: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub due_date: Option<NaiveDate>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub assignee_id: Option<Uuid>,
}

/// Request payload for `PATCH /api/v1/todo/items/{id}` (OpenAPI schema `TodoPatch`).
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TodoPatch {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub notes: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub due_date: Option<NaiveDate>,
    #[serde(default, skip_serializing_if = "is_false")]
    pub clear_due_date: bool,
}

fn is_false(value: &bool) -> bool {
    !*value
}

/// Which items `GET /api/v1/todo/items` returns (`scope` query parameter).
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum TodoScope {
    /// Handed to me, or mine and not handed to anyone (the server default).
    #[default]
    Mine,
    /// Mine, handed to a colleague.
    Assigned,
    /// Everything I own or that is handed to me.
    AllMine,
}

/// Query parameters for `GET /api/v1/todo/items`.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
pub struct ListTodosParams {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub scope: Option<TodoScope>,
    /// `Some(true)`: finished items only, `Some(false)`: open items only, `None`: both.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub done: Option<bool>,
}

/// Counters for the badge (`GET /api/v1/todo/items/counts`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct TodoCounts {
    pub open: i64,
    pub overdue: i64,
    pub due_today: i64,
}

#[derive(Debug, Serialize)]
struct CompleteBody {
    complete_children: bool,
}

impl Client {
    /// Lists to-do items (`GET /api/v1/todo/items`).
    pub async fn list_todos(&self, params: &ListTodosParams) -> Result<Vec<TodoItem>, ApiError> {
        self.get_json("/api/v1/todo/items", params).await
    }

    /// Open-item counters of the caller (`GET /api/v1/todo/items/counts`).
    pub async fn todo_counts(&self) -> Result<TodoCounts, ApiError> {
        self.get_json("/api/v1/todo/items/counts", &()).await
    }

    /// Creates an item or sub-item (`POST /api/v1/todo/items`).
    pub async fn create_todo(&self, req: &TodoCreate) -> Result<TodoItem, ApiError> {
        self.post_json("/api/v1/todo/items", req).await
    }

    /// Edits an item (`PATCH /api/v1/todo/items/{id}`).
    pub async fn update_todo(&self, id: Uuid, req: &TodoPatch) -> Result<TodoItem, ApiError> {
        self.patch_json(&format!("/api/v1/todo/items/{id}"), req)
            .await
    }

    /// Completes an item (`POST /api/v1/todo/items/{id}/complete`). Without `complete_children`
    /// the server answers 409 `open_sub_items` while sub-items are still open.
    pub async fn complete_todo(
        &self,
        id: Uuid,
        complete_children: bool,
    ) -> Result<TodoItem, ApiError> {
        self.post_json(
            &format!("/api/v1/todo/items/{id}/complete"),
            &CompleteBody { complete_children },
        )
        .await
    }

    /// Reopens a finished item (`POST /api/v1/todo/items/{id}/reopen`).
    pub async fn reopen_todo(&self, id: Uuid) -> Result<TodoItem, ApiError> {
        self.post_json(&format!("/api/v1/todo/items/{id}/reopen"), &())
            .await
    }

    /// Deletes an item and its sub-items (`DELETE /api/v1/todo/items/{id}`); owner only.
    pub async fn delete_todo(&self, id: Uuid) -> Result<(), ApiError> {
        self.delete_empty(&format!("/api/v1/todo/items/{id}")).await
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decodes_item_and_encodes_patch() {
        let item: TodoItem = serde_json::from_str(
            r#"{"id":"00000000-0000-0000-0000-000000000001","parent_id":null,"position":0,
            "title":"Call","notes":"","owner_id":"00000000-0000-0000-0000-000000000002",
            "owner_name":"Admin","assignee_id":null,"assignee_name":null,
            "created_by":"00000000-0000-0000-0000-000000000002","mine":true,
            "due_date":"2026-12-01","done":false,"done_at":null,"done_by":null,
            "link_kind":null,"link_id":null,"link_label":null,"link_location":null,
            "client_id":null,"created_at":"2026-11-26T10:00:00Z","updated_at":"2026-11-26T10:00:00Z"}"#,
        )
        .unwrap();
        assert_eq!(item.due_date, NaiveDate::from_ymd_opt(2026, 12, 1));

        let patch = TodoPatch {
            clear_due_date: true,
            ..TodoPatch::default()
        };
        assert_eq!(
            serde_json::to_string(&patch).unwrap(),
            r#"{"clear_due_date":true}"#
        );
        let query = ListTodosParams {
            scope: Some(TodoScope::AllMine),
            done: Some(false),
        };
        assert_eq!(
            serde_json::to_string(&query).unwrap(),
            r#"{"scope":"all-mine","done":false}"#
        );
    }
}
