//! Types of the knowledge base and the loading of an entry for staff.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection};
use tradocraft_core::files::FileInfo;
use tradocraft_core::{is_language, AppError, AppResult};
use utoipa::ToSchema;
use uuid::Uuid;

pub const VISIBILITIES: [&str; 3] = ["internal", "portal", "public"];
pub const STATUSES: [&str; 3] = ["draft", "published", "archived"];
pub const TICKET_CATEGORIES: [&str; 8] = [
    "question",
    "lead",
    "quote_change",
    "order_confirmation",
    "production_question",
    "service",
    "complaint",
    "other",
];
pub const MAX_TITLE: usize = 200;
pub const MAX_SUMMARY: usize = 600;
pub const MAX_BODY: usize = 60_000;
pub const MAX_TAGS: usize = 20;
pub const MAX_RELATED: usize = 20;
pub const MAX_IMAGES: i64 = 30;

/// SQL fragment that orders a `language` column in the configured order of the company given by
/// the SQL expression `company` (ADR 0101).
pub fn language_order(company: &str) -> String {
    format!("core.language_order({company}, language::text), language")
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, FromRow, ToSchema)]
pub struct EntryText {
    /// nl | fr | en | de | es
    pub language: String,
    pub title: String,
    #[serde(default)]
    pub summary: String,
    /// Simple Markdown: headings, bold, italics, lists, links and images (`image:<file id>`).
    #[serde(default)]
    pub body: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, FromRow, ToSchema)]
pub struct CategoryName {
    pub language: String,
    pub name: String,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct Category {
    pub id: Uuid,
    /// Only one level of nesting: the parent has no parent itself.
    pub parent_id: Option<Uuid>,
    pub sort_order: i32,
    pub active: bool,
    pub names: Vec<CategoryName>,
    /// Entries in this category (not counting its sub-categories).
    pub entry_count: i64,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct CategoryInput {
    pub parent_id: Option<Uuid>,
    #[serde(default)]
    pub sort_order: i32,
    #[serde(default = "yes")]
    pub active: bool,
    /// At least one language; the others fall back to English.
    pub names: Vec<CategoryName>,
}

fn yes() -> bool {
    true
}

impl CategoryInput {
    pub fn validate(&self) -> AppResult<Vec<CategoryName>> {
        let names: Vec<CategoryName> = self
            .names
            .iter()
            .filter(|n| !n.name.trim().is_empty())
            .map(|n| CategoryName {
                language: n.language.clone(),
                name: n.name.trim().to_string(),
            })
            .collect();
        if names.is_empty() {
            return Err(AppError::Validation(
                "name the category in at least one language".into(),
            ));
        }
        check_languages(names.iter().map(|n| n.language.as_str()))?;
        if names.iter().any(|n| n.name.chars().count() > 100) {
            return Err(AppError::Validation(
                "a category name is at most 100 characters".into(),
            ));
        }
        Ok(names)
    }
}

pub fn check_languages<'a>(langs: impl Iterator<Item = &'a str>) -> AppResult<()> {
    let mut seen: Vec<&str> = Vec::new();
    for l in langs {
        if !is_language(l) {
            return Err(AppError::Validation(
                "language must be an ISO 639-1 language code".to_string(),
            ));
        }
        if seen.contains(&l) {
            return Err(AppError::Validation(format!("language {l} appears twice")));
        }
        seen.push(l);
    }
    Ok(())
}

#[derive(Debug, Serialize, ToSchema)]
pub struct RelatedEntry {
    pub id: Uuid,
    pub number: String,
    pub status: String,
    pub title: String,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct Entry {
    pub id: Uuid,
    pub number: String,
    pub slug: String,
    pub category_id: Option<Uuid>,
    /// internal | portal | public
    pub visibility: String,
    /// draft | published | archived
    pub status: String,
    pub author_id: Option<Uuid>,
    pub author_name: Option<String>,
    pub published_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub view_count: i64,
    pub helpful_yes: i32,
    pub helpful_no: i32,
    /// Number of the latest saved version (0 when never published).
    pub version: i32,
    pub texts: Vec<EntryText>,
    pub tags: Vec<String>,
    pub related: Vec<RelatedEntry>,
    pub product_ids: Vec<Uuid>,
    /// Ticket categories this entry helps with (shown first in suggestions).
    pub ticket_categories: Vec<String>,
    pub images: Vec<FileInfo>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct EntryInput {
    pub category_id: Option<Uuid>,
    /// internal | portal | public
    pub visibility: String,
    /// At least one language with a title; others fall back to English.
    pub texts: Vec<EntryText>,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default)]
    pub related_ids: Vec<Uuid>,
    #[serde(default)]
    pub product_ids: Vec<Uuid>,
    #[serde(default)]
    pub ticket_categories: Vec<String>,
}

impl EntryInput {
    /// Checks the input and returns the texts that are filled in (trimmed).
    pub fn validate(&self) -> AppResult<Vec<EntryText>> {
        if !VISIBILITIES.contains(&self.visibility.as_str()) {
            return Err(AppError::Validation(format!(
                "visibility must be one of {}",
                VISIBILITIES.join(", ")
            )));
        }
        let texts: Vec<EntryText> = self
            .texts
            .iter()
            .filter(|t| {
                !(t.title.trim().is_empty()
                    && t.body.trim().is_empty()
                    && t.summary.trim().is_empty())
            })
            .map(|t| EntryText {
                language: t.language.clone(),
                title: t.title.trim().to_string(),
                summary: t.summary.trim().to_string(),
                body: t.body.trim().to_string(),
            })
            .collect();
        if texts.is_empty() {
            return Err(AppError::Validation(
                "write the entry in at least one language".into(),
            ));
        }
        check_languages(texts.iter().map(|t| t.language.as_str()))?;
        for t in &texts {
            if t.title.is_empty() {
                return Err(AppError::Validation(format!(
                    "the title is required ({})",
                    t.language
                )));
            }
            if t.title.chars().count() > MAX_TITLE
                || t.summary.chars().count() > MAX_SUMMARY
                || t.body.chars().count() > MAX_BODY
            {
                return Err(AppError::Validation(format!(
                    "text too long ({}): title {MAX_TITLE}, summary {MAX_SUMMARY}, body {MAX_BODY} characters",
                    t.language
                )));
            }
        }
        if self.tags.len() > MAX_TAGS * 2 || self.related_ids.len() > MAX_RELATED {
            return Err(AppError::Validation(format!(
                "at most {MAX_TAGS} tags and {MAX_RELATED} related entries"
            )));
        }
        for c in &self.ticket_categories {
            if !TICKET_CATEGORIES.contains(&c.as_str()) {
                return Err(AppError::Validation(format!("unknown ticket category {c}")));
            }
        }
        Ok(texts)
    }
}

#[derive(FromRow)]
struct EntryRow {
    id: Uuid,
    number: String,
    slug: String,
    category_id: Option<Uuid>,
    visibility: String,
    status: String,
    author_id: Option<Uuid>,
    author_name: Option<String>,
    published_at: Option<DateTime<Utc>>,
    created_at: DateTime<Utc>,
    updated_at: DateTime<Utc>,
    view_count: i64,
    helpful_yes: i32,
    helpful_no: i32,
}

pub async fn texts_of(conn: &mut PgConnection, entry_id: Uuid) -> AppResult<Vec<EntryText>> {
    Ok(sqlx::query_as(sqlx::AssertSqlSafe(format!(
        "SELECT language::text AS language, title, summary, body FROM kb.entry_texts
         WHERE entry_id = $1 ORDER BY {}",
        language_order("(SELECT e.company_id FROM kb.entries e WHERE e.id = entry_id)")
    )))
    .bind(entry_id)
    .fetch_all(conn)
    .await?)
}

/// The entry for staff: every status and visibility, of this company only.
pub async fn load_entry(conn: &mut PgConnection, company_id: Uuid, id: Uuid) -> AppResult<Entry> {
    let r: EntryRow = sqlx::query_as(
        "SELECT e.id, e.number, e.slug, e.category_id, e.visibility, e.status, e.author_id,
                u.display_name AS author_name, e.published_at, e.created_at, e.updated_at,
                e.view_count, e.helpful_yes, e.helpful_no
         FROM kb.entries e LEFT JOIN core.users u ON u.id = e.author_id
         WHERE e.id = $1 AND e.company_id = $2",
    )
    .bind(id)
    .bind(company_id)
    .fetch_optional(&mut *conn)
    .await?
    .ok_or(AppError::NotFound("knowledge base entry"))?;
    let texts = texts_of(conn, id).await?;
    let tags: Vec<String> =
        sqlx::query_scalar("SELECT tag FROM kb.entry_tags WHERE entry_id = $1 ORDER BY tag")
            .bind(id)
            .fetch_all(&mut *conn)
            .await?;
    #[derive(FromRow)]
    struct Rel {
        id: Uuid,
        number: String,
        status: String,
        title: String,
    }
    let related: Vec<Rel> = sqlx::query_as(
        "SELECT r.id, r.number, r.status,
                coalesce((SELECT t.title FROM kb.entry_texts t WHERE t.entry_id = r.id
                          ORDER BY (t.language = 'en') DESC, t.language LIMIT 1), '') AS title
         FROM kb.entry_links l JOIN kb.entries r ON r.id = l.related_id
         WHERE l.entry_id = $1 AND r.company_id = $2 ORDER BY r.number",
    )
    .bind(id)
    .bind(company_id)
    .fetch_all(&mut *conn)
    .await?;
    let product_ids: Vec<Uuid> = sqlx::query_scalar(
        "SELECT product_id FROM kb.entry_products WHERE entry_id = $1 ORDER BY product_id",
    )
    .bind(id)
    .fetch_all(&mut *conn)
    .await?;
    let ticket_categories: Vec<String> = sqlx::query_scalar(
        "SELECT ticket_category FROM kb.entry_ticket_categories WHERE entry_id = $1 ORDER BY 1",
    )
    .bind(id)
    .fetch_all(&mut *conn)
    .await?;
    let images: Vec<FileInfo> = sqlx::query_as(
        "SELECT f.id, f.filename, f.content_type, f.size_bytes, f.uploader_name, f.created_at
         FROM kb.entry_images i JOIN core.files f ON f.id = i.file_id
         WHERE i.entry_id = $1 ORDER BY i.created_at, f.id",
    )
    .bind(id)
    .fetch_all(&mut *conn)
    .await?;
    let version: Option<i32> =
        sqlx::query_scalar("SELECT max(version) FROM kb.entry_versions WHERE entry_id = $1")
            .bind(id)
            .fetch_one(conn)
            .await?;
    Ok(Entry {
        id: r.id,
        number: r.number,
        slug: r.slug,
        category_id: r.category_id,
        visibility: r.visibility,
        status: r.status,
        author_id: r.author_id,
        author_name: r.author_name,
        published_at: r.published_at,
        created_at: r.created_at,
        updated_at: r.updated_at,
        view_count: r.view_count,
        helpful_yes: r.helpful_yes,
        helpful_no: r.helpful_no,
        version: version.unwrap_or(0),
        texts,
        tags,
        related: related
            .into_iter()
            .map(|x| RelatedEntry {
                id: x.id,
                number: x.number,
                status: x.status,
                title: x.title,
            })
            .collect(),
        product_ids,
        ticket_categories,
        images,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn text(l: &str, title: &str) -> EntryText {
        EntryText {
            language: l.into(),
            title: title.into(),
            summary: String::new(),
            body: "x".into(),
        }
    }

    fn input(texts: Vec<EntryText>) -> EntryInput {
        EntryInput {
            category_id: None,
            visibility: "internal".into(),
            texts,
            tags: vec![],
            related_ids: vec![],
            product_ids: vec![],
            ticket_categories: vec![],
        }
    }

    #[test]
    fn needs_one_titled_text_in_a_known_language_once() {
        assert!(input(vec![text("en", "A")]).validate().is_ok());
        assert!(input(vec![]).validate().is_err());
        assert!(input(vec![text("xx", "A")]).validate().is_err());
        assert!(input(vec![text("en", "A"), text("en", "B")])
            .validate()
            .is_err());
        assert!(input(vec![text("en", " ")]).validate().is_err());
        let mut i = input(vec![text("en", "A")]);
        i.visibility = "secret".into();
        assert!(i.validate().is_err());
        i.visibility = "public".into();
        i.ticket_categories = vec!["nonsense".into()];
        assert!(i.validate().is_err());
    }

    #[test]
    fn empty_language_tabs_are_dropped() {
        let i = input(vec![
            text("en", "A"),
            EntryText {
                language: "nl".into(),
                title: "".into(),
                summary: "".into(),
                body: "".into(),
            },
        ]);
        assert_eq!(i.validate().unwrap().len(), 1);
    }
}
