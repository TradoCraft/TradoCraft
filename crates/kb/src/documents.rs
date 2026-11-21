//! Staff-only document library. Published revisions keep their original file references.
use axum::{
    body::Bytes,
    extract::{DefaultBodyLimit, Path, Query, State},
    http::{header, StatusCode},
    response::IntoResponse,
    Json,
};
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection};
use tradocraft_core::{
    files::{load, store_document, MAX_FILE_BYTES},
    new_id, AppError, AppResult, AppState, CurrentUser, Permission,
};
use utoipa::{IntoParams, ToSchema};
use utoipa_axum::{
    router::{OpenApiRouter, UtoipaMethodRouterExt},
    routes,
};
use uuid::Uuid;

#[derive(Deserialize, ToSchema)]
struct DocumentInput {
    title: String,
    kind: String,
    #[serde(default)]
    keywords: Vec<String>,
    #[serde(default)]
    product_codes: Vec<String>,
}

#[derive(Serialize, FromRow, ToSchema)]
struct Document {
    id: Uuid,
    title: String,
    kind: String,
    keywords: Vec<String>,
    product_codes: Vec<String>,
}

#[derive(Serialize, FromRow, ToSchema)]
struct Pdf {
    revision: i32,
    published: bool,
    language: String,
    filename: String,
}

#[derive(Serialize, ToSchema)]
struct DocumentDetail {
    document: Document,
    pdfs: Vec<Pdf>,
}

#[derive(Deserialize, IntoParams)]
struct Search {
    q: Option<String>,
}

#[utoipa::path(get, path = "/kb/documents", tag = "kb", operation_id = "list_kb_documents", params(Search), responses((status = 200, body = Vec<Document>)))]
async fn list(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(search): Query<Search>,
) -> AppResult<Json<Vec<Document>>> {
    user.require(Permission::KbRead)?;
    Ok(Json(sqlx::query_as(
        "SELECT d.id, d.title, d.kind, d.keywords, d.product_codes
         FROM kb.documents d WHERE company_id = $1
           AND ($2 OR EXISTS (SELECT 1 FROM kb.document_revisions r WHERE r.document_id = d.id AND r.published_at IS NOT NULL))
           AND strpos(lower(concat_ws(' ', title, array_to_string(keywords, ' '), array_to_string(product_codes, ' '))), lower($3)) > 0
         ORDER BY lower(title), id LIMIT 100",
    )
    .bind(user.company_id).bind(user.can(Permission::KbAdmin))
    .bind(search.q.as_deref().unwrap_or_default().trim())
    .fetch_all(&state.db).await?))
}

#[utoipa::path(post, path = "/kb/documents", tag = "kb", operation_id = "create_kb_document", request_body = DocumentInput, responses((status = 201, body = Document)))]
async fn create(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<DocumentInput>,
) -> AppResult<(StatusCode, Json<Document>)> {
    user.require(Permission::KbAdmin)?;
    let title = input.title.trim();
    if title.is_empty()
        || !matches!(
            input.kind.as_str(),
            "technical_memo" | "product_presentation"
        )
    {
        return Err(AppError::Validation(
            "a title and a supported document kind are required".into(),
        ));
    }
    let found: Vec<String> =
        sqlx::query_scalar("SELECT code FROM products.products WHERE code = ANY($1)")
            .bind(&input.product_codes)
            .fetch_all(&state.db)
            .await?;
    if input.product_codes.iter().any(|code| !found.contains(code)) {
        return Err(AppError::Validation("unknown product code".into()));
    }
    let document = sqlx::query_as(
        "INSERT INTO kb.documents (id, company_id, title, kind, keywords, product_codes)
         VALUES ($1, $2, $3, $4, $5, $6) RETURNING id, title, kind, keywords, product_codes",
    )
    .bind(new_id())
    .bind(user.company_id)
    .bind(title)
    .bind(input.kind)
    .bind(input.keywords)
    .bind(input.product_codes)
    .fetch_one(&state.db)
    .await?;
    Ok((StatusCode::CREATED, Json(document)))
}

#[utoipa::path(get, path = "/kb/documents/{id}", tag = "kb", operation_id = "get_kb_document", params(("id" = Uuid, Path)), responses((status = 200, body = DocumentDetail)))]
async fn detail(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<DocumentDetail>> {
    user.require(Permission::KbRead)?;
    let document = sqlx::query_as(
        "SELECT id, title, kind, keywords, product_codes FROM kb.documents WHERE company_id = $1 AND id = $2",
    ).bind(user.company_id).bind(id).fetch_optional(&state.db).await?.ok_or(AppError::NotFound("document"))?;
    let publisher = user.can(Permission::KbAdmin);
    let pdfs: Vec<Pdf> = sqlx::query_as(
        "SELECT p.revision, r.published_at IS NOT NULL AS published, p.language, f.filename
         FROM kb.document_pdfs p JOIN kb.document_revisions r USING (document_id, revision)
         JOIN core.files f ON f.id = p.file_id AND f.company_id = $2
         WHERE p.document_id = $1 AND ($3 OR r.published_at IS NOT NULL)
         ORDER BY p.revision DESC, p.language",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(publisher)
    .fetch_all(&state.db)
    .await?;
    if !publisher && pdfs.is_empty() {
        return Err(AppError::NotFound("document"));
    }
    Ok(Json(DocumentDetail { document, pdfs }))
}

async fn lock_document(conn: &mut PgConnection, company: Uuid, id: Uuid) -> AppResult<()> {
    sqlx::query_scalar::<_, Uuid>(
        "SELECT id FROM kb.documents WHERE company_id = $1 AND id = $2 FOR UPDATE",
    )
    .bind(company)
    .bind(id)
    .fetch_optional(conn)
    .await?
    .ok_or(AppError::NotFound("document"))?;
    Ok(())
}

#[derive(Deserialize, IntoParams)]
struct Upload {
    filename: String,
}

#[utoipa::path(put, path = "/kb/documents/{id}/draft/{language}", tag = "kb", operation_id = "upload_kb_document_pdf",
    params(("id" = Uuid, Path), ("language" = String, Path), Upload),
    request_body(content = Vec<u8>, content_type = "application/pdf"), responses((status = 204)))]
async fn upload(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((id, language)): Path<(Uuid, String)>,
    Query(input): Query<Upload>,
    body: Bytes,
) -> AppResult<StatusCode> {
    user.require(Permission::KbAdmin)?;
    if !matches!(language.as_str(), "en" | "nl" | "fr" | "de" | "es") || !body.starts_with(b"%PDF-")
    {
        return Err(AppError::Validation(
            "a PDF in a supported language is required".into(),
        ));
    }
    let mut tx = state.db.begin().await?;
    lock_document(&mut tx, user.company_id, id).await?;
    let published: i32 = sqlx::query_scalar(
        "SELECT coalesce(max(revision), 0) FROM kb.document_revisions WHERE document_id = $1 AND published_at IS NOT NULL",
    ).bind(id).fetch_one(&mut *tx).await?;
    let draft = published + 1;
    let inserted = sqlx::query("INSERT INTO kb.document_revisions (document_id, revision) VALUES ($1, $2) ON CONFLICT DO NOTHING")
        .bind(id).bind(draft).execute(&mut *tx).await?;
    if inserted.rows_affected() > 0 && published > 0 {
        sqlx::query(
            "INSERT INTO kb.document_pdfs (document_id, revision, language, file_id)
             SELECT document_id, $2, language, file_id FROM kb.document_pdfs WHERE document_id = $1 AND revision = $3",
        ).bind(id).bind(draft).bind(published).execute(&mut *tx).await?;
    }
    sqlx::query("SELECT pg_advisory_xact_lock_shared(743902104)")
        .execute(&mut *tx)
        .await?;
    let previous: Option<Uuid> = sqlx::query_scalar(
        "SELECT file_id FROM kb.document_pdfs WHERE document_id = $1 AND revision = $2 AND language = $3",
    ).bind(id).bind(draft).bind(&language).fetch_optional(&mut *tx).await?;
    if let Some(file) = previous {
        let (kind, previous_bytes) = load(&mut tx, &state.blobs, user.company_id, file).await?;
        if previous_bytes.as_slice() == body.as_ref()
            && tradocraft_core::files::get_info(&mut tx, user.company_id, file)
                .await?
                .is_some_and(|f| {
                    f.filename == tradocraft_core::files::clean_filename(&input.filename, &kind)
                })
        {
            tx.commit().await?;
            return Ok(StatusCode::NO_CONTENT);
        }
    }
    let file = store_document(
        &mut tx,
        &state.blobs,
        user.company_id,
        None,
        &input.filename,
        &body,
        Some(user.user_id),
        &user.display_name,
    )
    .await?;
    sqlx::query(
        "INSERT INTO kb.document_pdfs (document_id, revision, language, file_id) VALUES ($1, $2, $3, $4)
         ON CONFLICT (document_id, revision, language) DO UPDATE SET file_id = excluded.file_id",
    ).bind(id).bind(draft).bind(language).bind(file.id).execute(&mut *tx).await?;
    if let Some(file) = previous {
        sqlx::query("DELETE FROM core.files WHERE id = $1 AND company_id = $2 AND NOT EXISTS (SELECT 1 FROM kb.document_pdfs WHERE file_id = $1)")
            .bind(file).bind(user.company_id).execute(&mut *tx).await?;
    }
    tx.commit().await?;
    Ok(StatusCode::NO_CONTENT)
}

#[utoipa::path(post, path = "/kb/documents/{id}/publish", tag = "kb", operation_id = "publish_kb_document", params(("id" = Uuid, Path)), responses((status = 204)))]
async fn publish(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<StatusCode> {
    user.require(Permission::KbAdmin)?;
    let mut tx = state.db.begin().await?;
    lock_document(&mut tx, user.company_id, id).await?;
    let result = sqlx::query("UPDATE kb.document_revisions SET published_at = now() WHERE document_id = $1 AND published_at IS NULL")
        .bind(id).execute(&mut *tx).await?;
    if result.rows_affected() == 0 {
        return Err(AppError::Validation(
            "upload at least one PDF before publishing".into(),
        ));
    }
    tx.commit().await?;
    Ok(StatusCode::NO_CONTENT)
}

#[utoipa::path(get, path = "/kb/documents/{id}/revisions/{revision}/{language}", tag = "kb", operation_id = "download_kb_document_pdf",
    params(("id" = Uuid, Path), ("revision" = i32, Path), ("language" = String, Path)),
    responses((status = 200, content_type = "application/pdf")))]
async fn download(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((id, revision, language)): Path<(Uuid, i32, String)>,
) -> AppResult<impl IntoResponse> {
    user.require(Permission::KbRead)?;
    let mut conn = state.db.acquire().await?;
    let file_id = sqlx::query_scalar::<_, Uuid>(
        "SELECT p.file_id FROM kb.document_pdfs p JOIN kb.documents d ON d.id = p.document_id
         JOIN kb.document_revisions r ON r.document_id = p.document_id AND r.revision = p.revision
         WHERE d.company_id = $1 AND d.id = $2 AND p.revision = $3 AND p.language = $4
           AND ($5 OR r.published_at IS NOT NULL)",
    )
    .bind(user.company_id)
    .bind(id)
    .bind(revision)
    .bind(language)
    .bind(user.can(Permission::KbAdmin))
    .fetch_optional(&mut *conn)
    .await?
    .ok_or(AppError::NotFound("document PDF"))?;
    let (_, bytes) = load(&mut conn, &state.blobs, user.company_id, file_id).await?;
    Ok((
        [
            (header::CONTENT_TYPE, "application/pdf"),
            (header::CONTENT_DISPOSITION, "attachment"),
            (header::CACHE_CONTROL, "private, no-store"),
            (header::X_CONTENT_TYPE_OPTIONS, "nosniff"),
        ],
        bytes,
    ))
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(list, create))
        .routes(routes!(detail))
        .routes(routes!(upload).layer(DefaultBodyLimit::max(MAX_FILE_BYTES)))
        .routes(routes!(publish))
        .routes(routes!(download))
}
