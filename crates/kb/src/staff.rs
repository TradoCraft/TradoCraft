//! Staff API of the knowledge base: categories, entries and their texts, publishing, versions,
//! images, search and suggestions for a ticket.

use axum::body::Bytes;
use axum::extract::{DefaultBodyLimit, Path, Query, State};
use axum::http::StatusCode;
use axum::response::Response;
use axum::Json;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection};
use tradocraft_core::files::{self, FileInfo, MAX_FILE_BYTES};
use tradocraft_core::{
    audit, is_language, new_id, numbering, AppError, AppResult, AppState, CurrentUser, Permission,
};
use utoipa::{IntoParams, ToSchema};
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::model::*;
use crate::reader::{self, Audience, Hit, Search};
use crate::text::{any_word_query, clean_tags, plain_text, slugify};

type ErrorBody = tradocraft_core::error::ErrorBody;

async fn company_language(conn: &mut PgConnection, company_id: Uuid) -> AppResult<String> {
    Ok(
        sqlx::query_scalar("SELECT default_language::text FROM core.companies WHERE id = $1")
            .bind(company_id)
            .fetch_optional(conn)
            .await?
            .unwrap_or_else(|| "en".to_string()),
    )
}

fn language_param(p: Option<&str>, default: &str) -> AppResult<String> {
    match p.map(str::trim).filter(|l| !l.is_empty()) {
        Some(l) if is_language(l) => Ok(l.to_string()),
        Some(_) => Err(AppError::Validation(
            "language must be an ISO 639-1 language code".into(),
        )),
        None => Ok(default.to_string()),
    }
}

// ---------------------------------------------------------------------------------------------
// Categories
// ---------------------------------------------------------------------------------------------

async fn load_categories(
    conn: &mut PgConnection,
    company_id: Uuid,
    only: Option<Uuid>,
) -> AppResult<Vec<Category>> {
    #[derive(FromRow)]
    struct C {
        id: Uuid,
        parent_id: Option<Uuid>,
        sort_order: i32,
        active: bool,
        entry_count: i64,
    }
    let rows: Vec<C> = sqlx::query_as(
        "SELECT c.id, c.parent_id, c.sort_order, c.active,
                (SELECT count(*) FROM kb.entries e WHERE e.category_id = c.id) AS entry_count
         FROM kb.categories c WHERE c.company_id = $1 AND ($2::uuid IS NULL OR c.id = $2)
         ORDER BY c.sort_order, c.id",
    )
    .bind(company_id)
    .bind(only)
    .fetch_all(&mut *conn)
    .await?;
    let ids: Vec<Uuid> = rows.iter().map(|r| r.id).collect();
    let names = reader::names_of(conn, &ids).await?;
    Ok(rows
        .into_iter()
        .map(|r| Category {
            names: names
                .iter()
                .filter(|(c, _)| *c == r.id)
                .map(|(_, n)| n.clone())
                .collect(),
            id: r.id,
            parent_id: r.parent_id,
            sort_order: r.sort_order,
            active: r.active,
            entry_count: r.entry_count,
        })
        .collect())
}

async fn check_parent(
    conn: &mut PgConnection,
    company_id: Uuid,
    id: Option<Uuid>,
    parent: Option<Uuid>,
) -> AppResult<()> {
    let Some(parent) = parent else { return Ok(()) };
    if Some(parent) == id {
        return Err(AppError::Validation(
            "a category cannot be its own parent".into(),
        ));
    }
    let grand: Option<Option<Uuid>> =
        sqlx::query_scalar("SELECT parent_id FROM kb.categories WHERE id = $1 AND company_id = $2")
            .bind(parent)
            .bind(company_id)
            .fetch_optional(&mut *conn)
            .await?;
    match grand {
        None => {
            return Err(AppError::Validation(
                "the parent category does not exist".into(),
            ))
        }
        Some(Some(_)) => {
            return Err(AppError::Validation(
                "categories can be nested one level deep only".into(),
            ))
        }
        Some(None) => {}
    }
    if let Some(id) = id {
        let children: i64 =
            sqlx::query_scalar("SELECT count(*) FROM kb.categories WHERE parent_id = $1")
                .bind(id)
                .fetch_one(conn)
                .await?;
        if children > 0 {
            return Err(AppError::Validation(
                "a category with sub-categories cannot become a sub-category".into(),
            ));
        }
    }
    Ok(())
}

async fn save_names(conn: &mut PgConnection, id: Uuid, names: &[CategoryName]) -> AppResult<()> {
    sqlx::query("DELETE FROM kb.category_names WHERE category_id = $1")
        .bind(id)
        .execute(&mut *conn)
        .await?;
    for n in names {
        sqlx::query(
            "INSERT INTO kb.category_names (category_id, language, name) VALUES ($1, $2, $3)",
        )
        .bind(id)
        .bind(&n.language)
        .bind(&n.name)
        .execute(&mut *conn)
        .await?;
    }
    Ok(())
}

#[utoipa::path(get, path = "/kb/categories", tag = "kb", operation_id = "list_kb_categories",
    responses((status = 200, body = Vec<Category>)))]
async fn list_categories(
    State(state): State<AppState>,
    user: CurrentUser,
) -> AppResult<Json<Vec<Category>>> {
    user.require(Permission::KbRead)?;
    let mut conn = state.db.acquire().await?;
    Ok(Json(
        load_categories(&mut conn, user.company_id, None).await?,
    ))
}

#[utoipa::path(post, path = "/kb/categories", tag = "kb", operation_id = "create_kb_category", request_body = CategoryInput,
    responses((status = 201, body = Category), (status = 422, body = ErrorBody)))]
async fn create_category(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<CategoryInput>,
) -> AppResult<(StatusCode, Json<Category>)> {
    user.require(Permission::KbAdmin)?;
    let names = input.validate()?;
    let mut tx = state.db.begin().await?;
    check_parent(&mut tx, user.company_id, None, input.parent_id).await?;
    let id = new_id();
    sqlx::query("INSERT INTO kb.categories (id, company_id, parent_id, sort_order, active) VALUES ($1, $2, $3, $4, $5)")
        .bind(id)
        .bind(user.company_id)
        .bind(input.parent_id)
        .bind(input.sort_order)
        .bind(input.active)
        .execute(&mut *tx)
        .await?;
    save_names(&mut tx, id, &names).await?;
    audit::record(
        &mut tx,
        &user,
        "kb_category",
        id,
        "created",
        serde_json::json!({}),
    )
    .await?;
    let c = load_categories(&mut tx, user.company_id, Some(id))
        .await?
        .remove(0);
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(c)))
}

#[utoipa::path(put, path = "/kb/categories/{id}", tag = "kb", operation_id = "update_kb_category", params(("id" = Uuid, Path)),
    request_body = CategoryInput,
    responses((status = 200, body = Category), (status = 404, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn update_category(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<CategoryInput>,
) -> AppResult<Json<Category>> {
    user.require(Permission::KbAdmin)?;
    let names = input.validate()?;
    let mut tx = state.db.begin().await?;
    check_parent(&mut tx, user.company_id, Some(id), input.parent_id).await?;
    let r = sqlx::query(
        "UPDATE kb.categories SET parent_id = $3, sort_order = $4, active = $5 WHERE id = $1 AND company_id = $2",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(input.parent_id)
    .bind(input.sort_order)
    .bind(input.active)
    .execute(&mut *tx)
    .await?;
    if r.rows_affected() == 0 {
        return Err(AppError::NotFound("category"));
    }
    save_names(&mut tx, id, &names).await?;
    audit::record(
        &mut tx,
        &user,
        "kb_category",
        id,
        "updated",
        serde_json::json!({}),
    )
    .await?;
    let c = load_categories(&mut tx, user.company_id, Some(id))
        .await?
        .remove(0);
    tx.commit().await?;
    Ok(Json(c))
}

/// Deletes a category that has no entries and no sub-categories; otherwise deactivate it.
#[utoipa::path(delete, path = "/kb/categories/{id}", tag = "kb", operation_id = "delete_kb_category", params(("id" = Uuid, Path)),
    responses((status = 204), (status = 404, body = ErrorBody), (status = 409, body = ErrorBody)))]
async fn delete_category(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<StatusCode> {
    user.require(Permission::KbAdmin)?;
    let mut tx = state.db.begin().await?;
    let found: Option<Uuid> = sqlx::query_scalar(
        "SELECT id FROM kb.categories WHERE id = $1 AND company_id = $2 FOR UPDATE",
    )
    .bind(id)
    .bind(user.company_id)
    .fetch_optional(&mut *tx)
    .await?;
    found.ok_or(AppError::NotFound("category"))?;
    let used: i64 = sqlx::query_scalar(
        "SELECT (SELECT count(*) FROM kb.entries WHERE category_id = $1)
              + (SELECT count(*) FROM kb.categories WHERE parent_id = $1)",
    )
    .bind(id)
    .fetch_one(&mut *tx)
    .await?;
    if used > 0 {
        return Err(AppError::Conflict(
            "the category still has entries or sub-categories; deactivate it instead".into(),
        ));
    }
    sqlx::query("DELETE FROM kb.categories WHERE id = $1")
        .bind(id)
        .execute(&mut *tx)
        .await?;
    audit::record(
        &mut tx,
        &user,
        "kb_category",
        id,
        "deleted",
        serde_json::json!({}),
    )
    .await?;
    tx.commit().await?;
    Ok(StatusCode::NO_CONTENT)
}

// ---------------------------------------------------------------------------------------------
// Listing and searching
// ---------------------------------------------------------------------------------------------

#[derive(Debug, Serialize, ToSchema)]
pub struct EntrySummary {
    pub id: Uuid,
    pub number: String,
    pub slug: String,
    pub category_id: Option<Uuid>,
    pub visibility: String,
    pub status: String,
    /// The language of the title and snippet shown.
    pub language: String,
    pub fallback: bool,
    pub title: String,
    /// Plain text; matched words are wrapped in U+E000 / U+E001 when searching.
    pub snippet: String,
    pub tags: Vec<String>,
    pub updated_at: DateTime<Utc>,
    pub published_at: Option<DateTime<Utc>>,
    pub view_count: i64,
    pub helpful_yes: i32,
    pub helpful_no: i32,
    /// Relevance of a search match (higher is better).
    pub score: Option<f32>,
}

impl From<Hit> for EntrySummary {
    fn from(h: Hit) -> Self {
        EntrySummary {
            id: h.id,
            number: h.number,
            slug: h.slug,
            category_id: h.category_id,
            visibility: h.visibility,
            status: h.status,
            language: h.language,
            fallback: h.fallback,
            title: h.title,
            snippet: h.snippet,
            tags: h.tags,
            updated_at: h.updated_at,
            published_at: h.published_at,
            view_count: h.view_count,
            helpful_yes: h.helpful_yes,
            helpful_no: h.helpful_no,
            score: h.rank,
        }
    }
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct ListParams {
    /// Search words (several words must all occur; "quoted phrases" and -excluded words work).
    pub q: Option<String>,
    /// Includes the sub-categories of this category.
    pub category_id: Option<Uuid>,
    pub tag: Option<String>,
    /// Language to search and show; entries without it show English, then another language.
    pub language: Option<String>,
    /// internal | portal | public
    pub visibility: Option<String>,
    /// draft | published | archived
    pub status: Option<String>,
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}

/// Lists or searches entries. With `q` the best match comes first and each entry has a snippet.
#[utoipa::path(get, path = "/kb/entries", tag = "kb", operation_id = "list_kb_entries", params(ListParams),
    responses((status = 200, body = Vec<EntrySummary>), (status = 422, body = ErrorBody)))]
async fn list_entries(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(p): Query<ListParams>,
) -> AppResult<Json<Vec<EntrySummary>>> {
    user.require(Permission::KbRead)?;
    for (v, allowed) in [(&p.visibility, &VISIBILITIES), (&p.status, &STATUSES)] {
        if let Some(v) = v {
            if !allowed.contains(&v.as_str()) {
                return Err(AppError::Validation(format!(
                    "filter value must be one of {}",
                    allowed.join(", ")
                )));
            }
        }
    }
    let mut conn = state.db.acquire().await?;
    let default = company_language(&mut conn, user.company_id).await?;
    let language = language_param(p.language.as_deref(), &default)?;
    let hits = reader::search(
        &mut conn,
        &Search {
            audience: Audience::Staff,
            company_id: user.company_id,
            q: p.q.as_deref(),
            any_word: false,
            language: &language,
            category_id: p.category_id,
            tag: p.tag.as_deref(),
            visibility: p.visibility.as_deref(),
            status: p.status.as_deref(),
            ticket_category: None,
            limit: p.limit.unwrap_or(50),
            offset: p.offset.unwrap_or(0),
        },
    )
    .await?;
    Ok(Json(hits.into_iter().map(Into::into).collect()))
}

/// All tags in use, for suggestions in filters and the editor.
#[utoipa::path(get, path = "/kb/tags", tag = "kb", operation_id = "list_kb_tags",
    responses((status = 200, body = Vec<String>)))]
async fn list_tags(
    State(state): State<AppState>,
    user: CurrentUser,
) -> AppResult<Json<Vec<String>>> {
    user.require(Permission::KbRead)?;
    Ok(Json(
        sqlx::query_scalar(
            "SELECT DISTINCT g.tag FROM kb.entry_tags g JOIN kb.entries e ON e.id = g.entry_id
             WHERE e.company_id = $1 ORDER BY 1",
        )
        .bind(user.company_id)
        .fetch_all(&state.db)
        .await?,
    ))
}

// ---------------------------------------------------------------------------------------------
// Entries
// ---------------------------------------------------------------------------------------------

async fn replace_texts(conn: &mut PgConnection, id: Uuid, texts: &[EntryText]) -> AppResult<()> {
    sqlx::query("DELETE FROM kb.entry_texts WHERE entry_id = $1")
        .bind(id)
        .execute(&mut *conn)
        .await?;
    for t in texts {
        sqlx::query(
            "INSERT INTO kb.entry_texts (entry_id, language, title, summary, body) VALUES ($1, $2, $3, $4, $5)",
        )
        .bind(id)
        .bind(&t.language)
        .bind(&t.title)
        .bind(&t.summary)
        .bind(&t.body)
        .execute(&mut *conn)
        .await?;
    }
    Ok(())
}

/// Category, tags, related entries, products and ticket categories (everything but the texts).
async fn save_links(
    conn: &mut PgConnection,
    company_id: Uuid,
    id: Uuid,
    input: &EntryInput,
) -> AppResult<()> {
    if let Some(c) = input.category_id {
        let ok: Option<Uuid> =
            sqlx::query_scalar("SELECT id FROM kb.categories WHERE id = $1 AND company_id = $2")
                .bind(c)
                .bind(company_id)
                .fetch_optional(&mut *conn)
                .await?;
        ok.ok_or_else(|| AppError::Validation("the category does not exist".into()))?;
    }
    let mut related = input.related_ids.clone();
    related.sort();
    related.dedup();
    related.retain(|r| *r != id);
    if !related.is_empty() {
        let found: i64 = sqlx::query_scalar(
            "SELECT count(*) FROM kb.entries WHERE company_id = $1 AND id = ANY($2)",
        )
        .bind(company_id)
        .bind(&related)
        .fetch_one(&mut *conn)
        .await?;
        if found != related.len() as i64 {
            return Err(AppError::Validation(
                "a related entry does not exist".into(),
            ));
        }
    }
    let tags = clean_tags(&input.tags);
    if tags.len() > MAX_TAGS {
        return Err(AppError::Validation(format!("at most {MAX_TAGS} tags")));
    }
    for table in [
        "kb.entry_tags",
        "kb.entry_links",
        "kb.entry_products",
        "kb.entry_ticket_categories",
    ] {
        sqlx::query(sqlx::AssertSqlSafe(format!(
            "DELETE FROM {table} WHERE entry_id = $1"
        )))
        .bind(id)
        .execute(&mut *conn)
        .await?;
    }
    for t in &tags {
        sqlx::query("INSERT INTO kb.entry_tags (entry_id, tag) VALUES ($1, $2)")
            .bind(id)
            .bind(t)
            .execute(&mut *conn)
            .await?;
    }
    for r in &related {
        sqlx::query("INSERT INTO kb.entry_links (entry_id, related_id) VALUES ($1, $2)")
            .bind(id)
            .bind(r)
            .execute(&mut *conn)
            .await?;
    }
    let mut products = input.product_ids.clone();
    products.sort();
    products.dedup();
    for p in &products {
        sqlx::query("INSERT INTO kb.entry_products (entry_id, product_id) VALUES ($1, $2)")
            .bind(id)
            .bind(p)
            .execute(&mut *conn)
            .await?;
    }
    let mut cats = input.ticket_categories.clone();
    cats.sort();
    cats.dedup();
    for c in &cats {
        sqlx::query(
            "INSERT INTO kb.entry_ticket_categories (entry_id, ticket_category) VALUES ($1, $2)",
        )
        .bind(id)
        .bind(c)
        .execute(&mut *conn)
        .await?;
    }
    Ok(())
}

async fn unique_slug(conn: &mut PgConnection, company_id: Uuid, base: &str) -> AppResult<String> {
    for n in 1..=200 {
        let candidate = if n == 1 {
            base.to_string()
        } else {
            format!("{base}-{n}")
        };
        let taken: bool = sqlx::query_scalar(
            "SELECT EXISTS (SELECT 1 FROM kb.entries WHERE company_id = $1 AND slug = $2)",
        )
        .bind(company_id)
        .bind(&candidate)
        .fetch_one(&mut *conn)
        .await?;
        if !taken {
            return Ok(candidate);
        }
    }
    Err(AppError::Conflict("no free slug".into()))
}

#[utoipa::path(post, path = "/kb/entries", tag = "kb", operation_id = "create_kb_entry", request_body = EntryInput,
    responses((status = 201, body = Entry), (status = 422, body = ErrorBody)))]
async fn create_entry(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<EntryInput>,
) -> AppResult<(StatusCode, Json<Entry>)> {
    user.require(Permission::KbWrite)?;
    let texts = input.validate()?;
    let mut tx = state.db.begin().await?;
    let id = new_id();
    let n = numbering::next_number(&mut tx, user.company_id, "KB", 0).await?;
    let number = format!("KB-{n:05}");
    let base_title = texts
        .iter()
        .find(|t| t.language == "en")
        .unwrap_or(&texts[0])
        .title
        .clone();
    let slug = unique_slug(&mut tx, user.company_id, &slugify(&base_title)).await?;
    sqlx::query(
        "INSERT INTO kb.entries (id, company_id, number, slug, category_id, visibility, author_id)
         VALUES ($1, $2, $3, $4, $5, $6, $7)",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(&number)
    .bind(&slug)
    .bind(input.category_id)
    .bind(&input.visibility)
    .bind(user.user_id)
    .execute(&mut *tx)
    .await?;
    replace_texts(&mut tx, id, &texts).await?;
    save_links(&mut tx, user.company_id, id, &input).await?;
    audit::record(
        &mut tx,
        &user,
        "kb_entry",
        id,
        "created",
        serde_json::json!({ "number": number }),
    )
    .await?;
    let e = load_entry(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(e)))
}

#[utoipa::path(get, path = "/kb/entries/{id}", tag = "kb", operation_id = "get_kb_entry", params(("id" = Uuid, Path)),
    responses((status = 200, body = Entry), (status = 404, body = ErrorBody)))]
async fn get_entry(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<Entry>> {
    user.require(Permission::KbRead)?;
    let mut conn = state.db.acquire().await?;
    Ok(Json(load_entry(&mut conn, user.company_id, id).await?))
}

/// Saves a new version when the texts differ from the last one (or `force`). Returns its number.
async fn snapshot(
    conn: &mut PgConnection,
    entry_id: Uuid,
    editor: Uuid,
    restored_from: Option<i32>,
    force: bool,
) -> AppResult<i32> {
    let texts = serde_json::to_value(texts_of(conn, entry_id).await?)
        .map_err(|e| AppError::Internal(e.into()))?;
    let last: Option<(i32, serde_json::Value)> = sqlx::query_as(
        "SELECT version, texts FROM kb.entry_versions WHERE entry_id = $1 ORDER BY version DESC LIMIT 1",
    )
    .bind(entry_id)
    .fetch_optional(&mut *conn)
    .await?;
    if let Some((v, t)) = &last {
        if !force && *t == texts {
            return Ok(*v);
        }
    }
    let next = last.map(|(v, _)| v).unwrap_or(0) + 1;
    sqlx::query(
        "INSERT INTO kb.entry_versions (id, entry_id, version, editor_id, restored_from, texts)
         VALUES ($1, $2, $3, $4, $5, $6)",
    )
    .bind(new_id())
    .bind(entry_id)
    .bind(next)
    .bind(editor)
    .bind(restored_from)
    .bind(texts)
    .execute(conn)
    .await?;
    Ok(next)
}

#[derive(FromRow)]
struct Current {
    status: String,
    visibility: String,
}

async fn lock_entry(conn: &mut PgConnection, company_id: Uuid, id: Uuid) -> AppResult<Current> {
    sqlx::query_as(
        "SELECT status, visibility FROM kb.entries WHERE id = $1 AND company_id = $2 FOR UPDATE",
    )
    .bind(id)
    .bind(company_id)
    .fetch_optional(conn)
    .await?
    .ok_or(AppError::NotFound("knowledge base entry"))
}

/// Edits an entry. Editing a published entry saves a new version when the texts changed, and
/// changing the visibility of a published entry needs the right to publish.
#[utoipa::path(put, path = "/kb/entries/{id}", tag = "kb", operation_id = "update_kb_entry", params(("id" = Uuid, Path)),
    request_body = EntryInput,
    responses((status = 200, body = Entry), (status = 403, body = ErrorBody), (status = 404, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn update_entry(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<EntryInput>,
) -> AppResult<Json<Entry>> {
    user.require(Permission::KbWrite)?;
    let texts = input.validate()?;
    let mut tx = state.db.begin().await?;
    let cur = lock_entry(&mut tx, user.company_id, id).await?;
    if cur.status == "published" && cur.visibility != input.visibility {
        user.require(Permission::KbAdmin)?;
    }
    sqlx::query(
        "UPDATE kb.entries SET category_id = $2, visibility = $3, updated_at = now() WHERE id = $1",
    )
    .bind(id)
    .bind(input.category_id)
    .bind(&input.visibility)
    .execute(&mut *tx)
    .await?;
    replace_texts(&mut tx, id, &texts).await?;
    save_links(&mut tx, user.company_id, id, &input).await?;
    if cur.status == "published" {
        snapshot(&mut tx, id, user.user_id, None, false).await?;
    }
    audit::record(
        &mut tx,
        &user,
        "kb_entry",
        id,
        "updated",
        serde_json::json!({}),
    )
    .await?;
    let e = load_entry(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok(Json(e))
}

async fn transition(
    state: &AppState,
    user: &CurrentUser,
    id: Uuid,
    action: &str,
) -> AppResult<Json<Entry>> {
    user.require(Permission::KbAdmin)?;
    let mut tx = state.db.begin().await?;
    let cur = lock_entry(&mut tx, user.company_id, id).await?;
    let (to, allowed): (&str, &[&str]) = match action {
        "publish" => ("published", &["draft", "archived"]),
        "unpublish" => ("draft", &["published"]),
        _ => ("archived", &["draft", "published"]),
    };
    if !allowed.contains(&cur.status.as_str()) {
        return Err(AppError::Conflict(format!(
            "cannot {action} an entry that is {}",
            cur.status
        )));
    }
    if to == "published" {
        let texts = texts_of(&mut tx, id).await?;
        if !texts
            .iter()
            .any(|t| !t.title.is_empty() && !t.body.trim().is_empty())
        {
            return Err(AppError::Validation(
                "write the body of the entry before publishing".into(),
            ));
        }
        snapshot(&mut tx, id, user.user_id, None, false).await?;
    }
    sqlx::query(
        "UPDATE kb.entries SET status = $2, updated_at = now(),
                published_at = CASE WHEN $2 = 'published' THEN now() ELSE published_at END
         WHERE id = $1",
    )
    .bind(id)
    .bind(to)
    .execute(&mut *tx)
    .await?;
    audit::record(&mut tx, user, "kb_entry", id, action, serde_json::json!({})).await?;
    let e = load_entry(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok(Json(e))
}

/// Makes a draft or archived entry visible to its audience; saves the first version.
#[utoipa::path(post, path = "/kb/entries/{id}/publish", tag = "kb", operation_id = "publish_kb_entry", params(("id" = Uuid, Path)),
    responses((status = 200, body = Entry), (status = 404, body = ErrorBody), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn publish(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<Entry>> {
    transition(&state, &user, id, "publish").await
}

/// Takes a published entry back to draft.
#[utoipa::path(post, path = "/kb/entries/{id}/unpublish", tag = "kb", operation_id = "unpublish_kb_entry", params(("id" = Uuid, Path)),
    responses((status = 200, body = Entry), (status = 404, body = ErrorBody), (status = 409, body = ErrorBody)))]
async fn unpublish(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<Entry>> {
    transition(&state, &user, id, "unpublish").await
}

/// Retires an entry: hidden from readers, kept for staff.
#[utoipa::path(post, path = "/kb/entries/{id}/archive", tag = "kb", operation_id = "archive_kb_entry", params(("id" = Uuid, Path)),
    responses((status = 200, body = Entry), (status = 404, body = ErrorBody), (status = 409, body = ErrorBody)))]
async fn archive(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<Entry>> {
    transition(&state, &user, id, "archive").await
}

// ---------------------------------------------------------------------------------------------
// Versions
// ---------------------------------------------------------------------------------------------

#[derive(Debug, Serialize, ToSchema)]
pub struct EntryVersion {
    pub version: i32,
    pub editor_id: Option<Uuid>,
    pub editor_name: Option<String>,
    pub edited_at: DateTime<Utc>,
    /// Set when this version was made by restoring an earlier one.
    pub restored_from: Option<i32>,
    pub texts: Vec<EntryText>,
}

#[derive(FromRow)]
struct VersionRow {
    version: i32,
    editor_id: Option<Uuid>,
    editor_name: Option<String>,
    edited_at: DateTime<Utc>,
    restored_from: Option<i32>,
    texts: serde_json::Value,
}

impl VersionRow {
    fn into_version(self) -> EntryVersion {
        EntryVersion {
            version: self.version,
            editor_id: self.editor_id,
            editor_name: self.editor_name,
            edited_at: self.edited_at,
            restored_from: self.restored_from,
            texts: serde_json::from_value(self.texts).unwrap_or_default(),
        }
    }
}

const VERSION_SQL: &str = "SELECT v.version, v.editor_id, u.display_name AS editor_name, v.edited_at,
        v.restored_from, v.texts
 FROM kb.entry_versions v JOIN kb.entries e ON e.id = v.entry_id LEFT JOIN core.users u ON u.id = v.editor_id
 WHERE v.entry_id = $1 AND e.company_id = $2";

#[utoipa::path(get, path = "/kb/entries/{id}/versions", tag = "kb", operation_id = "list_kb_versions", params(("id" = Uuid, Path)),
    responses((status = 200, body = Vec<EntryVersion>), (status = 404, body = ErrorBody)))]
async fn list_versions(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<Vec<EntryVersion>>> {
    user.require(Permission::KbRead)?;
    let mut conn = state.db.acquire().await?;
    load_entry(&mut conn, user.company_id, id).await?;
    let rows: Vec<VersionRow> = sqlx::query_as(sqlx::AssertSqlSafe(format!(
        "{VERSION_SQL} ORDER BY v.version DESC"
    )))
    .bind(id)
    .bind(user.company_id)
    .fetch_all(&mut *conn)
    .await?;
    Ok(Json(
        rows.into_iter().map(VersionRow::into_version).collect(),
    ))
}

/// Puts the texts of an earlier version back as a new version. History is never rewritten.
#[utoipa::path(post, path = "/kb/entries/{id}/versions/{version}/restore", tag = "kb", operation_id = "restore_kb_version",
    params(("id" = Uuid, Path), ("version" = i32, Path)),
    responses((status = 200, body = Entry), (status = 404, body = ErrorBody)))]
async fn restore_version(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((id, version)): Path<(Uuid, i32)>,
) -> AppResult<Json<Entry>> {
    user.require(Permission::KbWrite)?;
    let mut tx = state.db.begin().await?;
    lock_entry(&mut tx, user.company_id, id).await?;
    let row: VersionRow = sqlx::query_as(sqlx::AssertSqlSafe(format!(
        "{VERSION_SQL} AND v.version = $3"
    )))
    .bind(id)
    .bind(user.company_id)
    .bind(version)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or(AppError::NotFound("version"))?;
    let texts = row.into_version().texts;
    if texts.is_empty() {
        return Err(AppError::Validation("that version has no text".into()));
    }
    replace_texts(&mut tx, id, &texts).await?;
    sqlx::query("UPDATE kb.entries SET updated_at = now() WHERE id = $1")
        .bind(id)
        .execute(&mut *tx)
        .await?;
    snapshot(&mut tx, id, user.user_id, Some(version), true).await?;
    audit::record(
        &mut tx,
        &user,
        "kb_entry",
        id,
        "restored",
        serde_json::json!({ "version": version }),
    )
    .await?;
    let e = load_entry(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok(Json(e))
}

// ---------------------------------------------------------------------------------------------
// Images
// ---------------------------------------------------------------------------------------------

#[derive(Debug, Deserialize, IntoParams)]
pub struct ImageParams {
    /// The original file name.
    pub filename: Option<String>,
    /// A client-chosen id: uploading the same id again returns the first upload.
    pub client_id: Option<Uuid>,
}

/// Uploads an image for an entry: the request body is the file (JPEG, PNG or WebP, at most
/// 12 MB). Use it in the text as `![description](image:<id>)`.
#[utoipa::path(post, path = "/kb/entries/{id}/images", tag = "kb", operation_id = "upload_kb_image",
    params(("id" = Uuid, Path), ImageParams), request_body(content = String, content_type = "application/octet-stream"),
    responses((status = 201, body = FileInfo), (status = 404, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn upload_image(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Query(p): Query<ImageParams>,
    body: Bytes,
) -> AppResult<(StatusCode, Json<FileInfo>)> {
    user.require(Permission::KbWrite)?;
    let mut tx = state.db.begin().await?;
    lock_entry(&mut tx, user.company_id, id).await?;
    let count: i64 = sqlx::query_scalar("SELECT count(*) FROM kb.entry_images WHERE entry_id = $1")
        .bind(id)
        .fetch_one(&mut *tx)
        .await?;
    if count >= MAX_IMAGES {
        return Err(AppError::Validation(format!(
            "at most {MAX_IMAGES} images per entry"
        )));
    }
    let f = files::store_image(
        &mut tx,
        &state.blobs,
        user.company_id,
        p.client_id,
        p.filename.as_deref().unwrap_or(""),
        &body,
        Some(user.user_id),
        &user.display_name,
    )
    .await?;
    sqlx::query("INSERT INTO kb.entry_images (file_id, entry_id) VALUES ($1, $2) ON CONFLICT (file_id) DO NOTHING")
        .bind(f.id)
        .bind(id)
        .execute(&mut *tx)
        .await?;
    let owner: Uuid = sqlx::query_scalar("SELECT entry_id FROM kb.entry_images WHERE file_id = $1")
        .bind(f.id)
        .fetch_one(&mut *tx)
        .await?;
    if owner != id {
        return Err(AppError::Conflict(
            "that file belongs to another entry".into(),
        ));
    }
    audit::record(
        &mut tx,
        &user,
        "kb_entry",
        id,
        "image_added",
        serde_json::json!({ "file_id": f.id }),
    )
    .await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(f)))
}

#[utoipa::path(get, path = "/kb/entries/{id}/images/{file_id}", tag = "kb", operation_id = "get_kb_image",
    params(("id" = Uuid, Path), ("file_id" = Uuid, Path)),
    responses((status = 200, content_type = "application/octet-stream", body = String), (status = 404, body = ErrorBody)))]
async fn get_image(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((id, file_id)): Path<(Uuid, Uuid)>,
) -> AppResult<Response> {
    user.require(Permission::KbRead)?;
    let mut conn = state.db.acquire().await?;
    let (ct, data) = reader::image(
        &mut conn,
        &state.blobs,
        Audience::Staff,
        user.company_id,
        id,
        file_id,
    )
    .await?;
    Ok(files::image_response(&ct, data))
}

#[utoipa::path(delete, path = "/kb/entries/{id}/images/{file_id}", tag = "kb", operation_id = "delete_kb_image",
    params(("id" = Uuid, Path), ("file_id" = Uuid, Path)),
    responses((status = 204), (status = 404, body = ErrorBody)))]
async fn delete_image(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((id, file_id)): Path<(Uuid, Uuid)>,
) -> AppResult<StatusCode> {
    user.require(Permission::KbWrite)?;
    let mut tx = state.db.begin().await?;
    lock_entry(&mut tx, user.company_id, id).await?;
    let r = sqlx::query("DELETE FROM kb.entry_images WHERE file_id = $1 AND entry_id = $2")
        .bind(file_id)
        .bind(id)
        .execute(&mut *tx)
        .await?;
    if r.rows_affected() == 0 {
        return Err(AppError::NotFound("image"));
    }
    let storage_key: Option<String> = sqlx::query_scalar(
        "DELETE FROM core.files WHERE id = $1 AND company_id = $2 RETURNING storage_key",
    )
    .bind(file_id)
    .bind(user.company_id)
    .fetch_optional(&mut *tx)
    .await?;
    tx.commit().await?;
    if let Some(key) = storage_key {
        let _ = state.blobs.delete(&key).await;
    }
    Ok(StatusCode::NO_CONTENT)
}

// ---------------------------------------------------------------------------------------------
// Suggestions for a ticket
// ---------------------------------------------------------------------------------------------

#[derive(Debug, Deserialize, IntoParams)]
pub struct SuggestParams {
    /// At most this many entries (default 5, at most 10).
    pub limit: Option<i64>,
}

#[derive(FromRow)]
struct TicketInfo {
    subject: String,
    language: String,
    category: String,
    last_message: Option<String>,
}

async fn ticket_info(conn: &mut PgConnection, company_id: Uuid, id: Uuid) -> AppResult<TicketInfo> {
    sqlx::query_as(
        "SELECT t.subject, t.language::text AS language, t.category,
                (SELECT a.body FROM helpdesk.articles a
                 WHERE a.ticket_id = t.id AND a.kind IN ('email_in', 'portal_in', 'call_in')
                 ORDER BY a.created_at DESC LIMIT 1) AS last_message
         FROM helpdesk.tickets t WHERE t.id = $1 AND t.company_id = $2",
    )
    .bind(id)
    .bind(company_id)
    .fetch_optional(conn)
    .await?
    .ok_or(AppError::NotFound("ticket"))
}

/// Published entries that fit a ticket: the words of the subject and the latest customer
/// message, searched in the ticket's language. Internal entries are included; entries linked
/// to the ticket's category rank higher.
#[utoipa::path(get, path = "/tickets/{id}/kb-suggestions", tag = "kb", operation_id = "suggest_kb_entries",
    params(("id" = Uuid, Path), SuggestParams),
    responses((status = 200, body = Vec<EntrySummary>), (status = 404, body = ErrorBody)))]
async fn suggest_for_ticket(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Query(p): Query<SuggestParams>,
) -> AppResult<Json<Vec<EntrySummary>>> {
    user.require(Permission::KbRead)?;
    user.require(Permission::HelpdeskRead)?;
    let mut conn = state.db.acquire().await?;
    let t = ticket_info(&mut conn, user.company_id, id).await?;
    let message: String = t
        .last_message
        .unwrap_or_default()
        .chars()
        .take(1000)
        .collect();
    let Some(q) = any_word_query(&format!("{} {}", t.subject, message), 14) else {
        return Ok(Json(vec![]));
    };
    let hits = reader::search(
        &mut conn,
        &Search {
            audience: Audience::Staff,
            company_id: user.company_id,
            q: Some(&q),
            any_word: true,
            language: &t.language,
            category_id: None,
            tag: None,
            visibility: None,
            status: Some("published"),
            ticket_category: Some(&t.category),
            limit: p.limit.unwrap_or(5).clamp(1, 10),
            offset: 0,
        },
    )
    .await?;
    Ok(Json(hits.into_iter().map(Into::into).collect()))
}

#[derive(Debug, Serialize, ToSchema)]
pub struct RenderedEntry {
    pub entry_id: Uuid,
    /// Language of the text used.
    pub language: String,
    /// True when the ticket's language has no text and another was used.
    pub fallback: bool,
    pub title: String,
    pub summary: String,
    /// The text without Markdown, ready for an e-mail.
    pub text: String,
    /// Address of the entry in the customer portal; absent for internal entries or when the
    /// company has no portal address.
    pub link: Option<String>,
}

/// An entry in the ticket's language as plain text and a link, to put in a reply. Nothing is sent.
#[utoipa::path(get, path = "/tickets/{id}/kb-entries/{entry_id}/render", tag = "kb", operation_id = "render_kb_entry",
    params(("id" = Uuid, Path), ("entry_id" = Uuid, Path)),
    responses((status = 200, body = RenderedEntry), (status = 404, body = ErrorBody)))]
async fn render_for_ticket(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((id, entry_id)): Path<(Uuid, Uuid)>,
) -> AppResult<Json<RenderedEntry>> {
    user.require(Permission::KbRead)?;
    user.require(Permission::HelpdeskRead)?;
    let mut conn = state.db.acquire().await?;
    let t = ticket_info(&mut conn, user.company_id, id).await?;
    let (status, visibility): (String, String) = sqlx::query_as(
        "SELECT status, visibility FROM kb.entries WHERE id = $1 AND company_id = $2",
    )
    .bind(entry_id)
    .bind(user.company_id)
    .fetch_optional(&mut *conn)
    .await?
    .ok_or(AppError::NotFound("knowledge base entry"))?;
    if status != "published" {
        return Err(AppError::NotFound("knowledge base entry"));
    }
    let e = reader::read(
        &mut conn,
        Audience::Staff,
        user.company_id,
        entry_id,
        &t.language,
        None,
        false,
    )
    .await?;
    let portal_url: Option<String> =
        sqlx::query_scalar("SELECT portal_url FROM core.companies WHERE id = $1")
            .bind(user.company_id)
            .fetch_one(&mut *conn)
            .await?;
    let link = portal_url
        .filter(|u| !u.trim().is_empty() && visibility != "internal")
        .map(|u| format!("{}/help/{}", u.trim_end_matches('/'), entry_id));
    Ok(Json(RenderedEntry {
        entry_id,
        language: e.language,
        fallback: e.fallback,
        title: e.title,
        summary: plain_text(&e.summary),
        text: plain_text(&e.body),
        link,
    }))
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(list_categories, create_category))
        .routes(routes!(update_category, delete_category))
        .routes(routes!(list_tags))
        .routes(routes!(list_entries, create_entry))
        .routes(routes!(get_entry, update_entry))
        .routes(routes!(publish))
        .routes(routes!(unpublish))
        .routes(routes!(archive))
        .routes(routes!(list_versions))
        .routes(routes!(restore_version))
        .routes(routes!(get_image, delete_image))
        .routes(routes!(suggest_for_ticket))
        .routes(routes!(render_for_ticket))
        .merge(
            OpenApiRouter::new()
                .routes(routes!(upload_image))
                .layer(DefaultBodyLimit::max(MAX_FILE_BYTES + 64 * 1024)),
        )
}
