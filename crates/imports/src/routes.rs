//! HTTP endpoints of the import admin screen (ADR 0067 section 5). All need `imports.admin`;
//! running a job also needs the write permission of the entity. Everything is scoped to the
//! caller's company: another company's file, mapping or job is a 404.

use axum::body::Bytes;
use axum::extract::{DefaultBodyLimit, Path, Query, State};
use axum::http::{HeaderMap, StatusCode};
use axum::Json;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgPool};
use tradocraft_core::audit;
use tradocraft_core::csv_io::{self, RowError};
use tradocraft_core::files::clean_filename;
use tradocraft_core::import::{
    read_raw, sheet_names, BinaryFile, Format, ImportDescription, Limits,
};
use tradocraft_core::{new_id, AppError, AppResult, AppState, CurrentUser, Permission};
use utoipa::{IntoParams, ToSchema};
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::mapping::{self, ColumnPair};
use crate::registry;
use crate::run::{self, StoredError};

type ErrorBody = tradocraft_core::error::ErrorBody;

const PREVIEW_ROWS: usize = 20;
const JOB_ERRORS_SHOWN: i64 = 100;
const STATUSES: [&str; 5] = ["queued", "running", "done", "failed", "cancelled"];

// ---------------------------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------------------------

/// An uploaded file.
#[derive(Debug, Serialize, ToSchema)]
pub struct ImportFile {
    pub id: Uuid,
    pub filename: String,
    /// `csv`, `xlsx` or `ods`, detected from the content.
    pub format: String,
    pub size_bytes: i64,
    /// The sheets of a workbook in order; empty for CSV.
    pub sheets: Vec<String>,
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct UploadParams {
    /// The original file name.
    pub filename: Option<String>,
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct PreviewParams {
    /// The sheet to read; the first one when absent. Ignored for CSV.
    pub sheet: Option<String>,
}

/// The start of a file as the person will see it.
#[derive(Debug, Serialize, ToSchema)]
pub struct ImportPreview {
    pub format: String,
    pub sheets: Vec<String>,
    /// The sheet that was read; null for CSV.
    pub sheet: Option<String>,
    /// The row of the header in the file.
    pub header_row: usize,
    /// The header cells as written.
    pub columns: Vec<String>,
    /// Data rows in the file.
    pub row_count: usize,
    /// The first 20 data rows as text, in header order.
    pub rows: Vec<Vec<String>>,
}

/// A saved column mapping.
#[derive(Debug, Serialize, FromRow, ToSchema)]
pub struct ImportMapping {
    pub id: Uuid,
    pub entity: String,
    pub name: String,
    #[sqlx(json)]
    pub columns: Vec<ColumnPair>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct MappingQuery {
    /// Only the mappings of this entity.
    pub entity: Option<String>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct MappingInput {
    pub entity: String,
    /// Saving under an existing name replaces that mapping.
    pub name: String,
    pub columns: Vec<ColumnPair>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct CreateJob {
    pub file_id: Uuid,
    pub entity: String,
    /// The sheet of a workbook; the first one when absent.
    pub sheet: Option<String>,
    /// `file column -> field` pairs; absent or empty means the header names our columns exactly.
    pub columns: Option<Vec<ColumnPair>>,
    /// Validate and count only.
    pub dry_run: bool,
}

/// One import run.
#[derive(Debug, Serialize, FromRow, ToSchema)]
pub struct ImportJob {
    pub id: Uuid,
    pub entity: String,
    pub filename: String,
    pub format: String,
    pub sheet: Option<String>,
    pub dry_run: bool,
    /// `queued`, `running`, `done`, `failed` or `cancelled`.
    pub status: String,
    /// While running: `reading`, `validating` or `writing`.
    pub phase: Option<String>,
    pub total_rows: i32,
    pub processed_rows: i32,
    pub created: i32,
    pub updated: i32,
    pub unchanged: i32,
    /// All errors found; `errors` holds the first 100 (the list endpoint none), the CSV all that
    /// were kept (at most 10 000).
    pub error_count: i32,
    #[sqlx(json)]
    pub errors: Vec<StoredError>,
    /// Why a `failed` job could not be carried out.
    pub message: Option<String>,
    pub requested_by: Option<Uuid>,
    pub requested_by_name: Option<String>,
    pub created_at: DateTime<Utc>,
    pub started_at: Option<DateTime<Utc>>,
    pub finished_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct ImportJobPage {
    pub items: Vec<ImportJob>,
    pub total: i64,
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct JobListParams {
    /// Only jobs in this status.
    pub status: Option<String>,
    /// Page size, 50 by default, at most 200.
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}

// ---------------------------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------------------------

fn admin(user: &CurrentUser) -> AppResult<()> {
    user.require(Permission::ImportsAdmin)
}

fn messages(errors: &[RowError]) -> String {
    errors
        .iter()
        .map(|e| e.message.as_str())
        .collect::<Vec<_>>()
        .join("; ")
}

fn refused(errors: Vec<RowError>) -> AppError {
    AppError::Validation(messages(&errors))
}

fn blocking_failed(e: tokio::task::JoinError) -> AppError {
    AppError::Internal(e.into())
}

fn trim_sheet(sheet: Option<String>) -> Option<String> {
    sheet
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
}

/// A name safe to show: no path, no control characters; a default when nothing is left.
fn file_name(raw: Option<&str>, format: Format) -> String {
    let default = format!("import.{}", format.extension());
    let raw = raw.unwrap_or("").trim();
    let cleaned = clean_filename(raw, "");
    // `clean_filename` answers an empty name with a photo name; this is not a photo.
    if raw.is_empty() || (cleaned == "photo.jpg" && raw != "photo.jpg") {
        default
    } else {
        cleaned
    }
}

struct StoredFile {
    filename: String,
    format: String,
    size_bytes: i64,
}

async fn file_meta(db: &PgPool, company_id: Uuid, id: Uuid) -> AppResult<StoredFile> {
    let row: Option<(String, String, i64)> = sqlx::query_as(
        "SELECT filename, format, size_bytes FROM core.import_files
         WHERE id = $1 AND company_id = $2",
    )
    .bind(id)
    .bind(company_id)
    .fetch_optional(db)
    .await?;
    let (filename, format, size_bytes) = row.ok_or(AppError::NotFound("import file"))?;
    Ok(StoredFile {
        filename,
        format,
        size_bytes,
    })
}

async fn file_bytes(db: &PgPool, company_id: Uuid, id: Uuid) -> AppResult<Vec<u8>> {
    sqlx::query_scalar("SELECT data FROM core.import_files WHERE id = $1 AND company_id = $2")
        .bind(id)
        .bind(company_id)
        .fetch_optional(db)
        .await?
        .ok_or(AppError::NotFound("import file"))
}

const SELECT_JOB: &str =
    "SELECT j.id, j.entity, j.filename, j.format, j.sheet, j.dry_run, j.status,
        j.phase, j.total_rows, j.processed_rows, j.created_count AS created,
        j.updated_count AS updated, j.unchanged_count AS unchanged, j.error_count,
        {errors} AS errors, j.message, j.requested_by, u.display_name AS requested_by_name,
        j.created_at, j.started_at, j.finished_at
     FROM core.import_jobs j LEFT JOIN core.users u ON u.id = j.requested_by";

fn select_job(with_errors: bool) -> String {
    let errors = if with_errors {
        format!(
            "jsonb_path_query_array(j.errors, '$[0 to {}]')",
            JOB_ERRORS_SHOWN - 1
        )
    } else {
        "'[]'::jsonb".to_string()
    };
    SELECT_JOB.replace("{errors}", &errors)
}

async fn fetch_job(db: &PgPool, company_id: Uuid, id: Uuid) -> AppResult<ImportJob> {
    sqlx::query_as(&format!(
        "{} WHERE j.id = $1 AND j.company_id = $2",
        select_job(true)
    ))
    .bind(id)
    .bind(company_id)
    .fetch_optional(db)
    .await?
    .ok_or(AppError::NotFound("import job"))
}

// ---------------------------------------------------------------------------------------------
// Entities and files
// ---------------------------------------------------------------------------------------------

/// The entities the caller may import, with their columns.
#[utoipa::path(get, path = "/imports/entities", tag = "imports", operation_id = "list_import_entities",
    responses((status = 200, body = Vec<ImportDescription>), (status = 403, body = ErrorBody)))]
async fn list_entities(user: CurrentUser) -> AppResult<Json<Vec<ImportDescription>>> {
    admin(&user)?;
    Ok(Json(
        registry::entities()
            .into_iter()
            .filter(|e| user.can(e.write_permission()))
            .map(|e| e.describe().clone())
            .collect(),
    ))
}

/// Uploads a file (CSV, XLSX or ODS, at most 50 MiB): the request body is the file itself. A file
/// of another type, or one that exceeds the archive limits, is refused and not stored.
#[utoipa::path(post, path = "/imports/files", tag = "imports", operation_id = "upload_import_file",
    params(UploadParams),
    request_body(content = inline(BinaryFile), content_type = "application/octet-stream"),
    responses((status = 201, body = ImportFile), (status = 403, body = ErrorBody),
              (status = 413, description = "The file is larger than 50 MiB"),
              (status = 422, body = ErrorBody)))]
async fn upload_file(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(p): Query<UploadParams>,
    body: Bytes,
) -> AppResult<(StatusCode, Json<ImportFile>)> {
    admin(&user)?;
    let bytes = body.clone();
    let (format, sheets) = tokio::task::spawn_blocking(move || sheet_names(&bytes, &Limits::job()))
        .await
        .map_err(blocking_failed)?
        .map_err(refused)?;
    let id = new_id();
    let filename = file_name(p.filename.as_deref(), format);
    sqlx::query(
        "INSERT INTO core.import_files (id, company_id, filename, format, size_bytes, data, uploaded_by)
         VALUES ($1, $2, $3, $4, $5, $6, $7)",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(&filename)
    .bind(format.extension())
    .bind(body.len() as i64)
    .bind(body.as_ref())
    .bind(user.user_id)
    .execute(&state.db)
    .await?;
    Ok((
        StatusCode::CREATED,
        Json(ImportFile {
            id,
            filename,
            format: format.extension().to_string(),
            size_bytes: body.len() as i64,
            sheets,
        }),
    ))
}

/// The header, the number of rows and the first 20 rows of an uploaded file.
#[utoipa::path(get, path = "/imports/files/{id}/preview", tag = "imports", operation_id = "preview_import_file",
    params(("id" = Uuid, Path), PreviewParams),
    responses((status = 200, body = ImportPreview), (status = 403, body = ErrorBody),
              (status = 404, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn preview_file(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Query(q): Query<PreviewParams>,
) -> AppResult<Json<ImportPreview>> {
    admin(&user)?;
    let bytes = file_bytes(&state.db, user.company_id, id).await?;
    let wanted = trim_sheet(q.sheet);
    let asked = wanted.clone();
    let (format, raw) = tokio::task::spawn_blocking(move || {
        // Twenty rows are shown; the others are only counted, not held.
        read_raw(
            &bytes,
            wanted.as_deref(),
            &Limits::job().preview(PREVIEW_ROWS),
        )
    })
    .await
    .map_err(blocking_failed)?
    .map_err(refused)?;
    let sheet = match format {
        Format::Csv => None,
        _ => asked.or_else(|| raw.sheets.first().cloned()),
    };
    Ok(Json(ImportPreview {
        format: format.extension().to_string(),
        sheets: raw.sheets,
        sheet,
        header_row: raw.header_row,
        columns: raw.header,
        row_count: raw.rows.len() + raw.failed_rows + raw.dropped_rows,
        rows: raw
            .rows
            .iter()
            .take(PREVIEW_ROWS)
            .map(|r| {
                r.cells
                    .iter()
                    .map(|c| c.render().unwrap_or_default())
                    .collect()
            })
            .collect(),
    }))
}

// ---------------------------------------------------------------------------------------------
// Mappings
// ---------------------------------------------------------------------------------------------

/// The saved mappings of the company, by name.
#[utoipa::path(get, path = "/imports/mappings", tag = "imports", operation_id = "list_import_mappings",
    params(MappingQuery),
    responses((status = 200, body = Vec<ImportMapping>), (status = 403, body = ErrorBody)))]
async fn list_mappings(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(q): Query<MappingQuery>,
) -> AppResult<Json<Vec<ImportMapping>>> {
    admin(&user)?;
    Ok(Json(
        sqlx::query_as(
            "SELECT id, entity, name, columns, created_at, updated_at FROM core.import_mappings
             WHERE company_id = $1 AND ($2::text IS NULL OR entity = $2)
             ORDER BY entity, lower(name), name",
        )
        .bind(user.company_id)
        .bind(q.entity.as_deref().map(str::trim).filter(|e| !e.is_empty()))
        .fetch_all(&state.db)
        .await?,
    ))
}

/// Saves a mapping; an existing one with the same entity and name is replaced.
#[utoipa::path(put, path = "/imports/mappings", tag = "imports", operation_id = "save_import_mapping",
    request_body = MappingInput,
    responses((status = 200, body = ImportMapping), (status = 403, body = ErrorBody),
              (status = 422, body = ErrorBody)))]
async fn save_mapping(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<MappingInput>,
) -> AppResult<Json<ImportMapping>> {
    admin(&user)?;
    let entity = registry::entity(input.entity.trim()).ok_or_else(|| {
        AppError::Validation(format!("'{}' is not an importable entity", input.entity))
    })?;
    let key = entity.describe().key.clone();
    let name = mapping::clean_name(&input.name)?;
    let columns = mapping::validate(&entity, &input.columns)?;
    let mut tx = state.db.begin().await?;
    let (saved, inserted): (ImportMapping, bool) = {
        #[derive(FromRow)]
        struct Row {
            #[sqlx(flatten)]
            mapping: ImportMapping,
            inserted: bool,
        }
        let row: Row = sqlx::query_as(
            "INSERT INTO core.import_mappings (id, company_id, entity, name, columns, created_by)
             VALUES ($1, $2, $3, $4, $5, $6)
             ON CONFLICT (company_id, entity, name)
             DO UPDATE SET columns = EXCLUDED.columns, updated_at = now()
             RETURNING id, entity, name, columns, created_at, updated_at, (xmax = 0) AS inserted",
        )
        .bind(new_id())
        .bind(user.company_id)
        .bind(&key)
        .bind(&name)
        .bind(sqlx::types::Json(&columns))
        .bind(user.user_id)
        .fetch_one(&mut *tx)
        .await?;
        (row.mapping, row.inserted)
    };
    audit::record(
        &mut tx,
        &user,
        "import_mapping",
        saved.id,
        if inserted { "created" } else { "updated" },
        serde_json::json!({ "entity": key, "name": name, "columns": columns }),
    )
    .await?;
    tx.commit().await?;
    Ok(Json(saved))
}

/// Deletes a saved mapping.
#[utoipa::path(delete, path = "/imports/mappings/{id}", tag = "imports", operation_id = "delete_import_mapping",
    params(("id" = Uuid, Path)),
    responses((status = 204), (status = 403, body = ErrorBody), (status = 404, body = ErrorBody)))]
async fn delete_mapping(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<StatusCode> {
    admin(&user)?;
    let mut tx = state.db.begin().await?;
    let gone: Option<(String, String)> = sqlx::query_as(
        "DELETE FROM core.import_mappings WHERE id = $1 AND company_id = $2 RETURNING entity, name",
    )
    .bind(id)
    .bind(user.company_id)
    .fetch_optional(&mut *tx)
    .await?;
    let (entity, name) = gone.ok_or(AppError::NotFound("import mapping"))?;
    audit::record(
        &mut tx,
        &user,
        "import_mapping",
        id,
        "deleted",
        serde_json::json!({ "entity": entity, "name": name }),
    )
    .await?;
    tx.commit().await?;
    Ok(StatusCode::NO_CONTENT)
}

// ---------------------------------------------------------------------------------------------
// Jobs
// ---------------------------------------------------------------------------------------------

/// Starts an import. A file within the limits of one request runs now and the finished job is
/// returned (200); a larger one is queued for the worker (202).
#[utoipa::path(post, path = "/imports/jobs", tag = "imports", operation_id = "create_import_job",
    request_body = CreateJob,
    responses((status = 200, body = ImportJob), (status = 202, body = ImportJob),
              (status = 403, body = ErrorBody), (status = 404, body = ErrorBody),
              (status = 422, body = ErrorBody)))]
async fn create_job(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<CreateJob>,
) -> AppResult<(StatusCode, Json<ImportJob>)> {
    admin(&user)?;
    let entity = registry::entity(input.entity.trim()).ok_or_else(|| {
        AppError::Validation(format!("'{}' is not an importable entity", input.entity))
    })?;
    user.require(entity.write_permission())?;
    let file = file_meta(&state.db, user.company_id, input.file_id).await?;
    let sheet = trim_sheet(input.sheet);
    let columns = match input.columns.as_deref() {
        None | Some([]) => None,
        Some(c) => Some(mapping::validate(&entity, c)?),
    };
    let inline = if file.size_bytes as usize > Limits::request().file_bytes {
        false
    } else {
        let bytes = file_bytes(&state.db, user.company_id, input.file_id).await?;
        run::fits_one_request(bytes, sheet.clone()).await?
    };
    let id = new_id();
    let claim = new_id();
    sqlx::query(
        "INSERT INTO core.import_jobs
            (id, company_id, entity, file_id, filename, format, sheet, columns, dry_run, status,
             requested_by, started_at, heartbeat_at, attempts, phase, inline, claim_token)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9,
                 CASE WHEN $10 THEN 'running' ELSE 'queued' END, $11,
                 CASE WHEN $10 THEN now() END, CASE WHEN $10 THEN now() END,
                 CASE WHEN $10 THEN 1 ELSE 0 END, CASE WHEN $10 THEN 'reading' END,
                 $10, CASE WHEN $10 THEN $12 END)",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(&entity.describe().key)
    .bind(input.file_id)
    .bind(&file.filename)
    .bind(&file.format)
    .bind(&sheet)
    .bind(columns.as_ref().map(sqlx::types::Json))
    .bind(input.dry_run)
    .bind(inline)
    .bind(user.user_id)
    .bind(claim)
    .execute(&state.db)
    .await?;
    if !inline {
        let job = fetch_job(&state.db, user.company_id, id).await?;
        return Ok((StatusCode::ACCEPTED, Json(job)));
    }
    // The run is a task of its own: a client that gives up (a closed tab, a timeout in front of
    // the API) drops this request, and a run that stopped half way would leave the job `running`
    // until the worker finds it. The task finishes and writes the outcome either way.
    let (pool, runner) = (state.db.clone(), user.clone());
    tokio::spawn(async move { run::run_job(&pool, id, claim, &runner, &Limits::request()).await })
        .await
        .map_err(blocking_failed)??;
    Ok((
        StatusCode::OK,
        Json(fetch_job(&state.db, user.company_id, id).await?),
    ))
}

/// The runs of the company, newest first.
#[utoipa::path(get, path = "/imports/jobs", tag = "imports", operation_id = "list_import_jobs",
    params(JobListParams),
    responses((status = 200, body = ImportJobPage), (status = 403, body = ErrorBody),
              (status = 422, body = ErrorBody)))]
async fn list_jobs(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(p): Query<JobListParams>,
) -> AppResult<Json<ImportJobPage>> {
    admin(&user)?;
    let status = p.status.as_deref().map(str::trim).filter(|s| !s.is_empty());
    if let Some(s) = status {
        if !STATUSES.contains(&s) {
            return Err(AppError::Validation(format!("unknown status '{s}'")));
        }
    }
    let items = sqlx::query_as(&format!(
        "{} WHERE j.company_id = $1 AND ($2::text IS NULL OR j.status = $2)
         ORDER BY j.created_at DESC, j.id DESC LIMIT $3 OFFSET $4",
        select_job(false)
    ))
    .bind(user.company_id)
    .bind(status)
    .bind(p.limit.unwrap_or(50).clamp(1, 200))
    .bind(p.offset.unwrap_or(0).max(0))
    .fetch_all(&state.db)
    .await?;
    let total = sqlx::query_scalar(
        "SELECT count(*) FROM core.import_jobs WHERE company_id = $1 AND ($2::text IS NULL OR status = $2)",
    )
    .bind(user.company_id)
    .bind(status)
    .fetch_one(&state.db)
    .await?;
    Ok(Json(ImportJobPage { items, total }))
}

/// One run with its progress and the first 100 errors.
#[utoipa::path(get, path = "/imports/jobs/{id}", tag = "imports", operation_id = "get_import_job",
    params(("id" = Uuid, Path)),
    responses((status = 200, body = ImportJob), (status = 403, body = ErrorBody),
              (status = 404, body = ErrorBody)))]
async fn get_job(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<ImportJob>> {
    admin(&user)?;
    Ok(Json(fetch_job(&state.db, user.company_id, id).await?))
}

/// The errors of a run as CSV (`row`, `column`, `message`).
#[utoipa::path(get, path = "/imports/jobs/{id}/errors", tag = "imports", operation_id = "download_import_errors",
    params(("id" = Uuid, Path)),
    responses((status = 200, content_type = "text/csv", body = String), (status = 403, body = ErrorBody),
              (status = 404, body = ErrorBody)))]
async fn job_errors(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<(HeaderMap, String)> {
    admin(&user)?;
    let stored: Option<sqlx::types::Json<Vec<StoredError>>> =
        sqlx::query_scalar("SELECT errors FROM core.import_jobs WHERE id = $1 AND company_id = $2")
            .bind(id)
            .bind(user.company_id)
            .fetch_optional(&state.db)
            .await?;
    let errors = stored.ok_or(AppError::NotFound("import job"))?.0;
    let body = csv_io::write_csv(
        &["row", "column", "message"],
        errors
            .into_iter()
            .map(|e| vec![e.row.to_string(), e.column.unwrap_or_default(), e.message]),
    );
    let short = &id.simple().to_string()[..8];
    Ok(csv_io::download(
        &format!("import-errors-{short}.csv"),
        body,
    ))
}

/// Cancels a job that is still queued.
#[utoipa::path(post, path = "/imports/jobs/{id}/cancel", tag = "imports", operation_id = "cancel_import_job",
    params(("id" = Uuid, Path)),
    responses((status = 200, body = ImportJob), (status = 403, body = ErrorBody),
              (status = 404, body = ErrorBody), (status = 409, body = ErrorBody)))]
async fn cancel_job(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<ImportJob>> {
    admin(&user)?;
    let done = sqlx::query(
        "UPDATE core.import_jobs SET status = 'cancelled', finished_at = now()
         WHERE id = $1 AND company_id = $2 AND status = 'queued'",
    )
    .bind(id)
    .bind(user.company_id)
    .execute(&state.db)
    .await?;
    let job = fetch_job(&state.db, user.company_id, id).await?;
    if done.rows_affected() == 0 {
        return Err(AppError::Conflict(format!(
            "only a queued import can be cancelled; this one is {}",
            job.status
        )));
    }
    Ok(Json(job))
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(list_entities))
        .routes(routes!(preview_file))
        .routes(routes!(list_mappings, save_mapping))
        .routes(routes!(delete_mapping))
        .routes(routes!(create_job, list_jobs))
        .routes(routes!(get_job))
        .routes(routes!(job_errors))
        .routes(routes!(cancel_job))
        .merge(
            OpenApiRouter::new()
                .routes(routes!(upload_file))
                .layer(DefaultBodyLimit::max(Limits::job().file_bytes)),
        )
}
