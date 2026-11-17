//! Reading without a staff account: the public endpoints (no login at all) and the building
//! blocks the customer portal uses for its logged-in contacts.
//!
//! The public endpoints name the company in the path, like the portal login does
//! (`company_id`), and show published entries with visibility `public` only. Responses may be
//! cached by browsers and proxies for a few minutes.

use axum::extract::{Path, Query, State};
use axum::http::header::{CACHE_CONTROL, CONTENT_TYPE, X_CONTENT_TYPE_OPTIONS};
use axum::response::{IntoResponse, Response};
use axum::Json;
use serde::Deserialize;
use sqlx::PgConnection;
use tradocraft_core::{is_language, AppError, AppResult, AppState};
use utoipa::IntoParams;
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::reader::{self, Audience, ReaderCategory, ReaderEntry, ReaderSummary, Search};
use crate::text::any_word_query;

type ErrorBody = tradocraft_core::error::ErrorBody;

const CACHE: &str = "public, max-age=300";

#[derive(Debug, Deserialize, IntoParams)]
pub struct LanguageParams {
    /// nl | fr | en | de | es (default: the company's language)
    pub language: Option<String>,
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct BrowseParams {
    /// Search words.
    pub q: Option<String>,
    /// Includes the sub-categories of this category.
    pub category_id: Option<Uuid>,
    pub tag: Option<String>,
    /// nl | fr | en | de | es (default: the company's language)
    pub language: Option<String>,
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct SuggestQuery {
    /// What the customer typed so far, e.g. the subject of a new ticket.
    pub q: Option<String>,
    pub language: Option<String>,
}

pub async fn company_language(conn: &mut PgConnection, company_id: Uuid) -> AppResult<String> {
    Ok(
        sqlx::query_scalar("SELECT default_language::text FROM core.companies WHERE id = $1")
            .bind(company_id)
            .fetch_optional(conn)
            .await?
            .unwrap_or_else(|| "en".to_string()),
    )
}

/// The language asked for, validated; the default when none was asked for.
pub fn language(p: Option<&str>, default: &str) -> AppResult<String> {
    match p.map(str::trim).filter(|l| !l.is_empty()) {
        Some(l) if is_language(l) => Ok(l.to_string()),
        Some(_) => Err(AppError::Validation(
            "language must be one of nl, fr, en, de, es".into(),
        )),
        None => Ok(default.to_string()),
    }
}

pub async fn browse(
    conn: &mut PgConnection,
    audience: Audience,
    company_id: Uuid,
    p: &BrowseParams,
    default_language: &str,
) -> AppResult<Vec<ReaderSummary>> {
    let lang = language(p.language.as_deref(), default_language)?;
    let hits = reader::search(
        conn,
        &Search {
            audience,
            company_id,
            q: p.q.as_deref(),
            any_word: false,
            language: &lang,
            category_id: p.category_id,
            tag: p.tag.as_deref(),
            visibility: None,
            status: None,
            ticket_category: None,
            limit: p.limit.unwrap_or(30),
            offset: p.offset.unwrap_or(0),
        },
    )
    .await?;
    Ok(hits.into_iter().map(Into::into).collect())
}

/// Up to three entries that fit what is being typed. Nothing is returned for fewer than three
/// letters, so a keystroke or two does not hit the database.
pub async fn suggest(
    conn: &mut PgConnection,
    audience: Audience,
    company_id: Uuid,
    p: &SuggestQuery,
    default_language: &str,
) -> AppResult<Vec<ReaderSummary>> {
    let lang = language(p.language.as_deref(), default_language)?;
    let text: String = p.q.as_deref().unwrap_or("").chars().take(300).collect();
    let Some(q) = any_word_query(&text, 8) else {
        return Ok(vec![]);
    };
    let hits = reader::search(
        conn,
        &Search {
            audience,
            company_id,
            q: Some(&q),
            any_word: true,
            language: &lang,
            category_id: None,
            tag: None,
            visibility: None,
            status: None,
            ticket_category: None,
            limit: 3,
            offset: 0,
        },
    )
    .await?;
    Ok(hits.into_iter().map(Into::into).collect())
}

/// An image for readers outside the staff app. Entries can change visibility, so the cache time
/// is short.
pub fn reader_image_response(public: bool, content_type: &str, data: Vec<u8>) -> Response {
    (
        [
            (CONTENT_TYPE, content_type.to_string()),
            (
                CACHE_CONTROL,
                if public {
                    CACHE
                } else {
                    "private, max-age=300"
                }
                .to_string(),
            ),
            (X_CONTENT_TYPE_OPTIONS, "nosniff".to_string()),
        ],
        data,
    )
        .into_response()
}

fn cached<T: serde::Serialize>(body: T) -> Response {
    ([(CACHE_CONTROL, CACHE)], Json(body)).into_response()
}

// ---------------------------------------------------------------------------------------------
// Public endpoints
// ---------------------------------------------------------------------------------------------

/// Categories that have public entries.
#[utoipa::path(get, path = "/public/kb/{company_id}/categories", tag = "kb", operation_id = "list_public_kb_categories",
    params(("company_id" = Uuid, Path), LanguageParams),
    responses((status = 200, body = Vec<ReaderCategory>), (status = 422, body = ErrorBody)))]
async fn public_categories(
    State(state): State<AppState>,
    Path(company_id): Path<Uuid>,
    Query(p): Query<LanguageParams>,
) -> AppResult<Response> {
    let mut conn = state.db.acquire().await?;
    let default = company_language(&mut conn, company_id).await?;
    let lang = language(p.language.as_deref(), &default)?;
    Ok(cached(
        reader::categories(&mut conn, Audience::Public, company_id, &lang).await?,
    ))
}

/// Public entries, or the best matches for the search words.
#[utoipa::path(get, path = "/public/kb/{company_id}/entries", tag = "kb", operation_id = "list_public_kb_entries",
    params(("company_id" = Uuid, Path), BrowseParams),
    responses((status = 200, body = Vec<ReaderSummary>), (status = 422, body = ErrorBody)))]
async fn public_entries(
    State(state): State<AppState>,
    Path(company_id): Path<Uuid>,
    Query(p): Query<BrowseParams>,
) -> AppResult<Response> {
    let mut conn = state.db.acquire().await?;
    let default = company_language(&mut conn, company_id).await?;
    Ok(cached(
        browse(&mut conn, Audience::Public, company_id, &p, &default).await?,
    ))
}

/// One public entry. Counts one view. Internal, portal-only, draft and archived entries are
/// "not found".
#[utoipa::path(get, path = "/public/kb/{company_id}/entries/{id}", tag = "kb", operation_id = "get_public_kb_entry",
    params(("company_id" = Uuid, Path), ("id" = Uuid, Path), LanguageParams),
    responses((status = 200, body = ReaderEntry), (status = 404, body = ErrorBody)))]
async fn public_entry(
    State(state): State<AppState>,
    Path((company_id, id)): Path<(Uuid, Uuid)>,
    Query(p): Query<LanguageParams>,
) -> AppResult<Response> {
    let mut conn = state.db.acquire().await?;
    let default = company_language(&mut conn, company_id).await?;
    let lang = language(p.language.as_deref(), &default)?;
    Ok(cached(
        reader::read(
            &mut conn,
            Audience::Public,
            company_id,
            id,
            &lang,
            None,
            true,
        )
        .await?,
    ))
}

#[utoipa::path(get, path = "/public/kb/{company_id}/entries/{id}/images/{file_id}", tag = "kb", operation_id = "get_public_kb_image",
    params(("company_id" = Uuid, Path), ("id" = Uuid, Path), ("file_id" = Uuid, Path)),
    responses((status = 200, content_type = "application/octet-stream", body = String), (status = 404, body = ErrorBody)))]
async fn public_image(
    State(state): State<AppState>,
    Path((company_id, id, file_id)): Path<(Uuid, Uuid, Uuid)>,
) -> AppResult<Response> {
    let mut conn = state.db.acquire().await?;
    let (ct, data) = reader::image(
        &mut conn,
        &state.blobs,
        Audience::Public,
        company_id,
        id,
        file_id,
    )
    .await?;
    Ok(reader_image_response(true, &ct, data))
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(public_categories))
        .routes(routes!(public_entries))
        .routes(routes!(public_entry))
        .routes(routes!(public_image))
}
