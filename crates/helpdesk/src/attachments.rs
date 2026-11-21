//! Files on tickets. A file is uploaded to the ticket first (JPEG, PNG, WebP or PDF, at most
//! 12 MB, checked by signature) and linked to the note, reply or portal message it belongs to
//! when that is written. Until then it is only visible to staff. Customers only ever see files
//! of articles they can see, so attachments of internal notes stay internal.

use std::collections::HashMap;

use axum::body::Bytes;
use axum::extract::{DefaultBodyLimit, Path, Query, State};
use axum::http::StatusCode;
use axum::response::Response;
use axum::Json;
use serde::Deserialize;
use sqlx::{FromRow, PgConnection};
use tradocraft_core::files::{self, FileInfo, MAX_FILE_BYTES};
use tradocraft_core::{AppError, AppResult, AppState, CurrentUser, Permission};
use utoipa::IntoParams;
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

type ErrorBody = tradocraft_core::error::ErrorBody;

/// Most files on one message.
pub const MAX_PER_ARTICLE: usize = 10;

#[derive(Debug, Deserialize, IntoParams)]
pub struct UploadParams {
    /// The original file name.
    pub filename: Option<String>,
    /// A client-chosen id: uploading the same id again returns the first upload (safe retries).
    pub client_id: Option<Uuid>,
}

#[derive(FromRow)]
struct Linked {
    article_id: Uuid,
    #[sqlx(flatten)]
    file: FileInfo,
}

/// The files of the given articles, oldest first.
pub async fn for_articles(
    conn: &mut PgConnection,
    article_ids: &[Uuid],
) -> AppResult<HashMap<Uuid, Vec<FileInfo>>> {
    let rows: Vec<Linked> = sqlx::query_as(
        "SELECT ta.article_id, f.id, f.filename, f.content_type, f.size_bytes, f.uploader_name, f.created_at
         FROM helpdesk.ticket_attachments ta JOIN core.files f ON f.id = ta.file_id
         WHERE ta.article_id = ANY($1) ORDER BY ta.created_at, f.id",
    )
    .bind(article_ids)
    .fetch_all(conn)
    .await?;
    let mut map: HashMap<Uuid, Vec<FileInfo>> = HashMap::new();
    for r in rows {
        map.entry(r.article_id).or_default().push(r.file);
    }
    Ok(map)
}

/// Who uploads: a staff user, or a customer's contact (portal).
pub struct Uploader<'a> {
    pub user_id: Option<Uuid>,
    pub contact_id: Option<Uuid>,
    pub name: &'a str,
}

/// Stores an upload on the ticket, not yet linked to an article. Idempotent on `client_id`.
#[allow(clippy::too_many_arguments)]
pub async fn upload(
    conn: &mut PgConnection,
    blobs: &tradocraft_core::BlobStore,
    company_id: Uuid,
    ticket_id: Uuid,
    p: &UploadParams,
    bytes: &[u8],
    by: Uploader<'_>,
) -> AppResult<FileInfo> {
    let file = files::store_document(
        conn,
        blobs,
        company_id,
        p.client_id,
        p.filename.as_deref().unwrap_or(""),
        bytes,
        by.user_id,
        by.name,
    )
    .await?;
    sqlx::query(
        "INSERT INTO helpdesk.ticket_attachments (file_id, ticket_id, contact_id) VALUES ($1, $2, $3)
         ON CONFLICT (file_id) DO NOTHING",
    )
    .bind(file.id)
    .bind(ticket_id)
    .bind(by.contact_id)
    .execute(&mut *conn)
    .await?;
    let same: bool = sqlx::query_scalar(
        "SELECT ticket_id = $2 AND contact_id IS NOT DISTINCT FROM $3
         FROM helpdesk.ticket_attachments WHERE file_id = $1",
    )
    .bind(file.id)
    .bind(ticket_id)
    .bind(by.contact_id)
    .fetch_one(conn)
    .await?;
    if !same {
        return Err(AppError::Conflict(
            "this file id belongs to another record".into(),
        ));
    }
    Ok(file)
}

/// Links uploaded files to the article that was just written. The files must have been uploaded
/// to this ticket by the same side (staff or the same contact) and not be used yet.
pub async fn link(
    conn: &mut PgConnection,
    ticket_id: Uuid,
    article_id: Uuid,
    file_ids: &[Uuid],
    contact_id: Option<Uuid>,
) -> AppResult<()> {
    let mut ids = file_ids.to_vec();
    ids.sort();
    ids.dedup();
    if ids.is_empty() {
        return Ok(());
    }
    if ids.len() > MAX_PER_ARTICLE {
        return Err(AppError::Validation(format!(
            "at most {MAX_PER_ARTICLE} files per message"
        )));
    }
    let updated = sqlx::query(
        "UPDATE helpdesk.ticket_attachments SET article_id = $2
         WHERE file_id = ANY($3) AND ticket_id = $1 AND article_id IS NULL
           AND contact_id IS NOT DISTINCT FROM $4",
    )
    .bind(ticket_id)
    .bind(article_id)
    .bind(&ids)
    .bind(contact_id)
    .execute(conn)
    .await?;
    if updated.rows_affected() as usize != ids.len() {
        return Err(AppError::Validation(
            "an attachment was not found on this ticket or is already used".into(),
        ));
    }
    Ok(())
}

/// Bytes of a file of this ticket. `article_kinds` limits it to files linked to an article of
/// one of those kinds (what a customer may see); `None` also allows files not sent yet (staff).
pub async fn data(
    conn: &mut PgConnection,
    blobs: &tradocraft_core::BlobStore,
    company_id: Uuid,
    ticket_id: Uuid,
    file_id: Uuid,
    article_kinds: Option<&[&str]>,
    contact_id: Option<Uuid>,
) -> AppResult<(String, String, Vec<u8>)> {
    let kinds: Option<Vec<String>> =
        article_kinds.map(|k| k.iter().map(|s| s.to_string()).collect());
    let visible: bool = sqlx::query_scalar(
        "SELECT EXISTS (
            SELECT 1 FROM helpdesk.ticket_attachments ta
            LEFT JOIN helpdesk.articles a ON a.id = ta.article_id
            WHERE ta.file_id = $1 AND ta.ticket_id = $2
              AND ($3::text[] IS NULL OR a.kind = ANY($3)
                   OR (ta.article_id IS NULL AND ta.contact_id IS NOT DISTINCT FROM $4 AND $4 IS NOT NULL)))",
    )
    .bind(file_id)
    .bind(ticket_id)
    .bind(&kinds)
    .bind(contact_id)
    .fetch_one(&mut *conn)
    .await?;
    if !visible {
        return Err(AppError::NotFound("attachment"));
    }
    let info = files::get_info(conn, company_id, file_id)
        .await?
        .ok_or(AppError::NotFound("attachment"))?;
    let (content_type, bytes) = files::load(conn, blobs, company_id, file_id).await?;
    Ok((info.filename, content_type, bytes))
}

/// Uploads a file to the ticket: the request body is the file itself (JPEG, PNG, WebP or PDF,
/// at most 12 MB). Attach it to a note or reply by passing its id in `attachment_ids`.
#[utoipa::path(post, path = "/tickets/{id}/attachments", tag = "helpdesk", operation_id = "upload_ticket_attachment",
    params(("id" = Uuid, Path), UploadParams),
    request_body(content = String, content_type = "application/octet-stream"),
    responses((status = 201, body = FileInfo), (status = 403, body = ErrorBody), (status = 404, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn upload_attachment(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Query(p): Query<UploadParams>,
    body: Bytes,
) -> AppResult<(StatusCode, Json<FileInfo>)> {
    user.require(Permission::HelpdeskWrite)?;
    let mut tx = state.db.begin().await?;
    crate::tickets::load_ticket(&mut tx, user.company_id, id).await?;
    let file = upload(
        &mut tx,
        &state.blobs,
        user.company_id,
        id,
        &p,
        &body,
        Uploader {
            user_id: Some(user.user_id),
            contact_id: None,
            name: &user.display_name,
        },
    )
    .await?;
    tx.commit().await?;
    crate::tickets::notify_change(&state, &user, id, "attachment", None).await;
    Ok((StatusCode::CREATED, Json(file)))
}

/// The file itself, as a download.
#[utoipa::path(get, path = "/tickets/{id}/attachments/{file_id}", tag = "helpdesk", operation_id = "get_ticket_attachment",
    params(("id" = Uuid, Path), ("file_id" = Uuid, Path)),
    responses((status = 200, content_type = "application/octet-stream", body = String), (status = 404, body = ErrorBody)))]
async fn get_attachment(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((id, file_id)): Path<(Uuid, Uuid)>,
) -> AppResult<Response> {
    user.require(Permission::HelpdeskRead)?;
    let mut conn = state.db.acquire().await?;
    crate::tickets::load_ticket(&mut conn, user.company_id, id).await?;
    let (filename, content_type, bytes) = data(
        &mut conn,
        &state.blobs,
        user.company_id,
        id,
        file_id,
        None,
        None,
    )
    .await?;
    Ok(files::attachment_response(&content_type, &filename, bytes))
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new().routes(routes!(get_attachment)).merge(
        OpenApiRouter::new()
            .routes(routes!(upload_attachment))
            .layer(DefaultBodyLimit::max(MAX_FILE_BYTES + 64 * 1024)),
    )
}

/// The exact published library variant selected by the agent.
#[derive(Debug, Deserialize, utoipa::ToSchema, PartialEq, Eq, Hash)]
pub struct LibraryPdf {
    pub document_id: Uuid,
    pub revision: i32,
    pub language: String,
}

pub(crate) fn check_reply_limit(ids: &[Uuid], library: &[LibraryPdf]) -> AppResult<()> {
    use std::collections::HashSet;
    let uploads = ids.iter().collect::<HashSet<_>>();
    if uploads.len() + library.len() > MAX_PER_ARTICLE {
        return Err(AppError::Validation(format!(
            "at most {MAX_PER_ARTICLE} files per message"
        )));
    }
    if library.iter().collect::<HashSet<_>>().len() != library.len() {
        return Err(AppError::Validation(
            "duplicate library PDF in the reply".into(),
        ));
    }
    Ok(())
}

/// Creates a ticket attachment identity with its own filename metadata, sharing the immutable
/// blob. The normal article and worker paths can read it without needing library permissions.
pub(crate) async fn link_library_pdfs(
    conn: &mut PgConnection,
    user: &CurrentUser,
    ticket_id: Uuid,
    article_id: Uuid,
    variants: &[LibraryPdf],
) -> AppResult<()> {
    if variants.is_empty() {
        return Ok(());
    }
    user.require(Permission::KbRead)?;
    for variant in variants {
        let result = sqlx::query(
            "WITH attachment_file AS (
                INSERT INTO core.files (id, company_id, filename, content_type, size_bytes,
                                        uploaded_by, uploader_name, storage_key)
                SELECT $1, f.company_id, f.filename, f.content_type, f.size_bytes, $6, $7, f.storage_key
                FROM kb.document_pdfs p
                JOIN kb.document_revisions r USING (document_id, revision)
                JOIN kb.documents d ON d.id = p.document_id
                JOIN core.files f ON f.id = p.file_id AND f.company_id = d.company_id
                WHERE d.company_id = $2 AND p.document_id = $3 AND p.revision = $4
                  AND p.language = $5 AND r.published_at IS NOT NULL AND f.content_type = 'application/pdf'
                RETURNING id
            )
            INSERT INTO helpdesk.ticket_attachments
                (file_id, ticket_id, article_id, document_id, document_revision, document_language)
            SELECT id, $8, $9, $3, $4, $5 FROM attachment_file",
        )
        .bind(tradocraft_core::new_id())
        .bind(user.company_id)
        .bind(variant.document_id)
        .bind(variant.revision)
        .bind(&variant.language)
        .bind(user.user_id)
        .bind(&user.display_name)
        .bind(ticket_id)
        .bind(article_id)
        .execute(&mut *conn)
        .await?;
        if result.rows_affected() == 0 {
            return Err(AppError::NotFound("published document PDF"));
        }
    }
    Ok(())
}
