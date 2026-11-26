//! Staff Knowledge Base DTOs and endpoints (`/api/v1/kb/...`). The public reader lives in
//! [`crate::portal`].

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::client::Client;
use crate::error::ApiError;
use crate::portal::FileInfo;

/// Languages an entry can be written in, in the usual order.
pub const KB_LANGUAGES: [&str; 5] = ["nl", "fr", "en", "de", "es"];

/// `visibility` values of an entry, narrowest first.
pub const KB_VISIBILITIES: [&str; 3] = ["internal", "portal", "public"];

/// Name of a category in one language (OpenAPI schema `CategoryName`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct KbCategoryName {
    pub language: String,
    pub name: String,
}

/// Staff view of a category (OpenAPI schema `Category`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct KbCategory {
    pub id: Uuid,
    #[serde(default)]
    pub parent_id: Option<Uuid>,
    pub sort_order: i32,
    pub active: bool,
    pub names: Vec<KbCategoryName>,
    /// Entries directly in this category (sub-categories not counted).
    pub entry_count: i64,
}

impl KbCategory {
    /// Name in `language`, else English, else any name.
    pub fn name_for(&self, language: &str) -> String {
        self.names
            .iter()
            .find(|n| n.language == language)
            .or_else(|| self.names.iter().find(|n| n.language == "en"))
            .or_else(|| self.names.first())
            .map(|n| n.name.clone())
            .unwrap_or_default()
    }
}

/// Title, summary and body of an entry in one language (OpenAPI schema `EntryText`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct KbEntryText {
    pub language: String,
    pub title: String,
    #[serde(default)]
    pub summary: String,
    #[serde(default)]
    pub body: String,
}

/// Link to a related entry (OpenAPI schema `RelatedEntry`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct KbRelatedEntry {
    pub id: Uuid,
    pub number: String,
    pub status: String,
    pub title: String,
}

/// Search hit or list row (OpenAPI schema `EntrySummary`).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct KbEntrySummary {
    pub id: Uuid,
    pub number: String,
    pub slug: String,
    #[serde(default)]
    pub category_id: Option<Uuid>,
    /// `internal | portal | public`
    pub visibility: String,
    /// `draft | published | archived`
    pub status: String,
    /// Language of the title and snippet shown.
    pub language: String,
    pub fallback: bool,
    pub title: String,
    /// Plain text; matched words are wrapped in U+E000 / U+E001 when searching.
    pub snippet: String,
    pub tags: Vec<String>,
    pub updated_at: DateTime<Utc>,
    #[serde(default)]
    pub published_at: Option<DateTime<Utc>>,
    pub view_count: i64,
    pub helpful_yes: i32,
    pub helpful_no: i32,
    #[serde(default)]
    pub score: Option<f32>,
}

/// Full entry for staff (OpenAPI schema `Entry`).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct KbEntry {
    pub id: Uuid,
    pub number: String,
    pub slug: String,
    #[serde(default)]
    pub category_id: Option<Uuid>,
    /// `internal | portal | public`
    pub visibility: String,
    /// `draft | published | archived`
    pub status: String,
    #[serde(default)]
    pub author_id: Option<Uuid>,
    #[serde(default)]
    pub author_name: Option<String>,
    #[serde(default)]
    pub published_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub view_count: i64,
    pub helpful_yes: i32,
    pub helpful_no: i32,
    /// Latest saved version (0 when never published).
    pub version: i32,
    pub texts: Vec<KbEntryText>,
    pub tags: Vec<String>,
    pub related: Vec<KbRelatedEntry>,
    pub product_ids: Vec<Uuid>,
    pub ticket_categories: Vec<String>,
    pub images: Vec<FileInfo>,
}

impl KbEntry {
    /// Text in `language`, if the entry has one.
    pub fn text_for(&self, language: &str) -> Option<&KbEntryText> {
        self.texts.iter().find(|t| t.language == language)
    }

    /// Turns the entry into an edit payload that keeps everything the editor does not change.
    pub fn to_input(&self) -> KbEntryInput {
        KbEntryInput {
            category_id: self.category_id,
            visibility: self.visibility.clone(),
            texts: self.texts.clone(),
            tags: self.tags.clone(),
            related_ids: self.related.iter().map(|r| r.id).collect(),
            product_ids: self.product_ids.clone(),
            ticket_categories: self.ticket_categories.clone(),
        }
    }
}

/// Request payload for `POST /api/v1/kb/entries` and `PUT /api/v1/kb/entries/{id}`
/// (OpenAPI schema `EntryInput`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct KbEntryInput {
    #[serde(default)]
    pub category_id: Option<Uuid>,
    /// `internal | portal | public`
    pub visibility: String,
    /// At least one language with a title.
    pub texts: Vec<KbEntryText>,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default)]
    pub related_ids: Vec<Uuid>,
    #[serde(default)]
    pub product_ids: Vec<Uuid>,
    #[serde(default)]
    pub ticket_categories: Vec<String>,
}

/// Query parameters for `GET /api/v1/kb/entries`.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
pub struct ListKbEntriesParams {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub q: Option<String>,
    /// Includes sub-categories.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub category_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tag: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub language: Option<String>,
    /// `internal | portal | public`
    #[serde(skip_serializing_if = "Option::is_none")]
    pub visibility: Option<String>,
    /// `draft | published | archived`
    #[serde(skip_serializing_if = "Option::is_none")]
    pub status: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub limit: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub offset: Option<i64>,
}

impl Client {
    /// Lists categories (`GET /api/v1/kb/categories`); needs `kb.read`.
    pub async fn list_kb_categories(&self) -> Result<Vec<KbCategory>, ApiError> {
        self.get_json("/api/v1/kb/categories", &()).await
    }

    /// Lists or searches entries of every status (`GET /api/v1/kb/entries`); needs `kb.read`.
    pub async fn list_kb_entries(
        &self,
        params: &ListKbEntriesParams,
    ) -> Result<Vec<KbEntrySummary>, ApiError> {
        self.get_json("/api/v1/kb/entries", params).await
    }

    /// Reads one entry with all its languages (`GET /api/v1/kb/entries/{id}`); needs `kb.read`.
    pub async fn get_kb_entry(&self, id: Uuid) -> Result<KbEntry, ApiError> {
        self.get_json(&format!("/api/v1/kb/entries/{id}"), &())
            .await
    }

    /// Creates a draft entry (`POST /api/v1/kb/entries`); needs `kb.write`.
    pub async fn create_kb_entry(&self, req: &KbEntryInput) -> Result<KbEntry, ApiError> {
        self.post_json("/api/v1/kb/entries", req).await
    }

    /// Edits an entry (`PUT /api/v1/kb/entries/{id}`); needs `kb.write`, and `kb.admin` to change
    /// the visibility of a published entry.
    pub async fn update_kb_entry(&self, id: Uuid, req: &KbEntryInput) -> Result<KbEntry, ApiError> {
        self.put_json(&format!("/api/v1/kb/entries/{id}"), req)
            .await
    }

    /// Publishes a draft or archived entry (`POST /api/v1/kb/entries/{id}/publish`); needs
    /// `kb.admin`.
    pub async fn publish_kb_entry(&self, id: Uuid) -> Result<KbEntry, ApiError> {
        self.post_json(&format!("/api/v1/kb/entries/{id}/publish"), &())
            .await
    }

    /// Takes a published entry back to draft (`POST /api/v1/kb/entries/{id}/unpublish`); needs
    /// `kb.admin`.
    pub async fn unpublish_kb_entry(&self, id: Uuid) -> Result<KbEntry, ApiError> {
        self.post_json(&format!("/api/v1/kb/entries/{id}/unpublish"), &())
            .await
    }

    /// Archives an entry (`POST /api/v1/kb/entries/{id}/archive`); needs `kb.admin`.
    pub async fn archive_kb_entry(&self, id: Uuid) -> Result<KbEntry, ApiError> {
        self.post_json(&format!("/api/v1/kb/entries/{id}/archive"), &())
            .await
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const ENTRY: &str = r#"{"id":"00000000-0000-0000-0000-000000000001","number":"KB-00001",
        "slug":"reset","category_id":null,"visibility":"public","status":"draft",
        "author_id":null,"author_name":null,"published_at":null,
        "created_at":"2026-11-26T10:00:00Z","updated_at":"2026-11-26T10:00:00Z",
        "view_count":0,"helpful_yes":0,"helpful_no":0,"version":0,
        "texts":[{"language":"en","title":"Reset","summary":"","body":"Steps"}],
        "tags":["howto"],"related":[],"product_ids":[],"ticket_categories":[],"images":[]}"#;

    #[test]
    fn decodes_entry_and_builds_edit_payload() {
        let entry: KbEntry = serde_json::from_str(ENTRY).unwrap();
        assert_eq!(entry.text_for("en").unwrap().title, "Reset");
        assert!(entry.text_for("nl").is_none());
        let input = entry.to_input();
        assert_eq!(input.visibility, "public");
        assert_eq!(input.tags, vec!["howto".to_string()]);
    }

    #[test]
    fn category_name_falls_back_to_english() {
        let cat = KbCategory {
            id: Uuid::nil(),
            parent_id: None,
            sort_order: 0,
            active: true,
            names: vec![
                KbCategoryName {
                    language: "nl".into(),
                    name: "Hulp".into(),
                },
                KbCategoryName {
                    language: "en".into(),
                    name: "Help".into(),
                },
            ],
            entry_count: 0,
        };
        assert_eq!(cat.name_for("nl"), "Hulp");
        assert_eq!(cat.name_for("de"), "Help");
    }

    #[test]
    fn list_params_skip_empty_filters() {
        let params = ListKbEntriesParams {
            q: Some("reset".into()),
            status: Some("draft".into()),
            ..ListKbEntriesParams::default()
        };
        assert_eq!(
            serde_json::to_string(&params).unwrap(),
            r#"{"q":"reset","status":"draft"}"#
        );
    }
}
