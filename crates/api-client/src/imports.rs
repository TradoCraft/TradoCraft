//! Data import (`/api/v1/imports/...`): upload a file, preview it, map its columns (with saved
//! mappings), check it in a dry run and apply it, as background jobs with a history.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::client::Client;
use crate::error::ApiError;

/// What kind of value a column holds (OpenAPI schema `ColumnKind`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ColumnKind {
    Text,
    Code,
    Decimal,
    Integer,
    Boolean,
}

/// One column of an entity's import file (OpenAPI schema `ImportColumn`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ImportColumn {
    pub name: String,
    pub kind: ColumnKind,
    /// Must have a value when the row creates a record.
    pub required: bool,
    /// A family `<name>_<language>` (one column per ISO 639-1 code).
    #[serde(default)]
    pub per_language: bool,
}

/// An importable entity (OpenAPI schema `ImportDescription`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ImportDescription {
    /// `customers`, `products`.
    pub key: String,
    pub audit_entity: String,
    /// The first column of the key; upserts match on the key.
    pub key_column: String,
    /// The columns that together identify a record.
    #[serde(default)]
    pub key_columns: Vec<String>,
    pub file_stem: String,
    pub columns: Vec<ImportColumn>,
}

/// An uploaded file (OpenAPI schema `ImportFile`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ImportFile {
    pub id: Uuid,
    pub filename: String,
    /// `csv`, `xlsx` or `ods`, detected from the content.
    pub format: String,
    pub size_bytes: i64,
    /// The sheets of a workbook in order; empty for CSV.
    pub sheets: Vec<String>,
}

/// The start of a file (OpenAPI schema `ImportPreview`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ImportPreview {
    pub format: String,
    pub sheets: Vec<String>,
    #[serde(default)]
    pub sheet: Option<String>,
    pub header_row: u64,
    /// The header cells as written.
    pub columns: Vec<String>,
    /// Data rows in the file.
    pub row_count: u64,
    /// The first 20 data rows as text, in header order.
    pub rows: Vec<Vec<String>>,
}

/// One problem of an import (OpenAPI schema `StoredError`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct StoredError {
    pub row: u64,
    #[serde(default)]
    pub column: Option<String>,
    pub message: String,
}

/// One import run (OpenAPI schema `ImportJob`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ImportJob {
    pub id: Uuid,
    pub entity: String,
    pub filename: String,
    pub format: String,
    #[serde(default)]
    pub sheet: Option<String>,
    pub dry_run: bool,
    /// `queued`, `running`, `done`, `failed` or `cancelled`.
    pub status: String,
    /// While running: `reading`, `validating` or `writing`.
    #[serde(default)]
    pub phase: Option<String>,
    pub total_rows: i32,
    pub processed_rows: i32,
    pub created: i32,
    pub updated: i32,
    pub unchanged: i32,
    pub error_count: i32,
    /// The first 100 errors (none in the list endpoint).
    pub errors: Vec<StoredError>,
    /// Why a `failed` job could not be carried out.
    #[serde(default)]
    pub message: Option<String>,
    #[serde(default)]
    pub requested_by: Option<Uuid>,
    #[serde(default)]
    pub requested_by_name: Option<String>,
    pub created_at: DateTime<Utc>,
    #[serde(default)]
    pub started_at: Option<DateTime<Utc>>,
    #[serde(default)]
    pub finished_at: Option<DateTime<Utc>>,
}

impl ImportJob {
    /// A job that is not finished: it is polled until it is.
    pub fn is_active(&self) -> bool {
        self.status == "queued" || self.status == "running"
    }
}

/// A page of runs, newest first (OpenAPI schema `ImportJobPage`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ImportJobPage {
    pub items: Vec<ImportJob>,
    pub total: i64,
}

/// One field of a mapping, fed by a file column or a fixed value (OpenAPI schema `ColumnPair`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ColumnPair {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub column: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub value: Option<String>,
    pub field: String,
}

impl ColumnPair {
    /// A pair that feeds `field` from the file column `column`.
    pub fn column(column: impl Into<String>, field: impl Into<String>) -> Self {
        ColumnPair {
            column: Some(column.into()),
            value: None,
            field: field.into(),
        }
    }
}

/// A saved column mapping (OpenAPI schema `ImportMapping`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ImportMapping {
    pub id: Uuid,
    pub entity: String,
    pub name: String,
    pub columns: Vec<ColumnPair>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// Saves a mapping; an existing one with the same name is replaced (OpenAPI schema `MappingInput`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct MappingInput {
    pub entity: String,
    pub name: String,
    pub columns: Vec<ColumnPair>,
}

/// Starts a run (OpenAPI schema `CreateJob`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CreateJob {
    pub file_id: Uuid,
    pub entity: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sheet: Option<String>,
    /// Absent: the header names the entity's columns exactly.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub columns: Option<Vec<ColumnPair>>,
    /// Validate and count only.
    pub dry_run: bool,
}

/// Query parameters of `GET /api/v1/imports/jobs`.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
pub struct ListImportJobsParams {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub status: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub limit: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub offset: Option<i64>,
}

#[derive(Debug, Serialize)]
struct FilenameQuery<'a> {
    filename: &'a str,
}

#[derive(Debug, Serialize)]
struct SheetQuery<'a> {
    #[serde(skip_serializing_if = "Option::is_none")]
    sheet: Option<&'a str>,
}

#[derive(Debug, Serialize)]
struct EntityQuery<'a> {
    entity: &'a str,
}

impl Client {
    /// The entities the caller may import (`GET /api/v1/imports/entities`).
    pub async fn list_import_entities(&self) -> Result<Vec<ImportDescription>, ApiError> {
        self.get_json("/api/v1/imports/entities", &()).await
    }

    /// Uploads a file as raw bytes (`POST /api/v1/imports/files`).
    pub async fn upload_import_file(
        &self,
        filename: &str,
        bytes: Vec<u8>,
    ) -> Result<ImportFile, ApiError> {
        self.post_bytes("/api/v1/imports/files", &FilenameQuery { filename }, bytes)
            .await
    }

    /// The header and first rows of a file (`GET /api/v1/imports/files/{id}/preview`).
    pub async fn preview_import_file(
        &self,
        id: Uuid,
        sheet: Option<&str>,
    ) -> Result<ImportPreview, ApiError> {
        self.get_json(
            &format!("/api/v1/imports/files/{id}/preview"),
            &SheetQuery { sheet },
        )
        .await
    }

    /// The saved mappings of an entity (`GET /api/v1/imports/mappings`).
    pub async fn list_import_mappings(&self, entity: &str) -> Result<Vec<ImportMapping>, ApiError> {
        self.get_json("/api/v1/imports/mappings", &EntityQuery { entity })
            .await
    }

    /// Saves a mapping (`PUT /api/v1/imports/mappings`).
    pub async fn save_import_mapping(&self, req: &MappingInput) -> Result<ImportMapping, ApiError> {
        self.put_json("/api/v1/imports/mappings", req).await
    }

    /// Deletes a saved mapping (`DELETE /api/v1/imports/mappings/{id}`).
    pub async fn delete_import_mapping(&self, id: Uuid) -> Result<(), ApiError> {
        self.delete_empty(&format!("/api/v1/imports/mappings/{id}"))
            .await
    }

    /// Starts a run (`POST /api/v1/imports/jobs`): a small file comes back finished (200), a
    /// larger one queued (202).
    pub async fn create_import_job(&self, req: &CreateJob) -> Result<ImportJob, ApiError> {
        self.post_json("/api/v1/imports/jobs", req).await
    }

    /// The runs of the company, newest first (`GET /api/v1/imports/jobs`).
    pub async fn list_import_jobs(
        &self,
        params: &ListImportJobsParams,
    ) -> Result<ImportJobPage, ApiError> {
        self.get_json("/api/v1/imports/jobs", params).await
    }

    /// One run with its progress and first errors (`GET /api/v1/imports/jobs/{id}`).
    pub async fn get_import_job(&self, id: Uuid) -> Result<ImportJob, ApiError> {
        self.get_json(&format!("/api/v1/imports/jobs/{id}"), &())
            .await
    }

    /// Cancels a queued run (`POST /api/v1/imports/jobs/{id}/cancel`); 409 once it is picked up.
    pub async fn cancel_import_job(&self, id: Uuid) -> Result<ImportJob, ApiError> {
        self.post_json(&format!("/api/v1/imports/jobs/{id}/cancel"), &())
            .await
    }

    /// The error report of a run as CSV bytes (`GET /api/v1/imports/jobs/{id}/errors`).
    pub async fn download_import_errors(&self, id: Uuid) -> Result<Vec<u8>, ApiError> {
        self.get_bytes(&format!("/api/v1/imports/jobs/{id}/errors"))
            .await
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn encodes_job_and_decodes_preview() {
        let job = CreateJob {
            file_id: Uuid::nil(),
            entity: "customers".into(),
            sheet: None,
            columns: None,
            dry_run: true,
        };
        assert_eq!(
            serde_json::to_string(&job).unwrap(),
            r#"{"file_id":"00000000-0000-0000-0000-000000000000","entity":"customers","dry_run":true}"#
        );
        let p: ImportPreview = serde_json::from_str(
            r#"{"format":"csv","sheets":[],"sheet":null,"header_row":1,"columns":["code","name"],
            "row_count":2,"rows":[["C1","A"],["C2","B"]]}"#,
        )
        .unwrap();
        assert_eq!(p.rows[1][1], "B");
        let d: ImportDescription = serde_json::from_str(
            r#"{"key":"customers","audit_entity":"customer","key_column":"code","file_stem":"customers",
            "columns":[{"name":"code","kind":"code","required":true}]}"#,
        )
        .unwrap();
        assert_eq!(d.columns[0].kind, ColumnKind::Code);
    }
}
