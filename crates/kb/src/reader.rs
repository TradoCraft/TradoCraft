//! Searching and reading entries on behalf of staff, a logged-in customer or the public.
//! One implementation, so the rules cannot drift apart: customers and the public only ever see
//! published entries of their own company whose visibility allows it.

use std::collections::HashMap;

use chrono::{DateTime, Utc};
use serde::Serialize;
use sqlx::{FromRow, PgConnection};
use tradocraft_core::{AppError, AppResult};
use utoipa::ToSchema;
use uuid::Uuid;

use crate::model::{CategoryName, LANGUAGE_ORDER};
use crate::text::{excerpt, pick_language, plain_text};

/// Marks the start and end of a matched word in a snippet (private-use characters, so they
/// cannot clash with real text). Clients split on them to highlight.
pub const MARK_START: char = '\u{E000}';
pub const MARK_END: char = '\u{E001}';

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Audience {
    /// Employees with the right to read the knowledge base: everything.
    Staff,
    /// A logged-in customer contact: published entries visible in the portal or to everyone.
    Portal,
    /// Anyone: published entries marked public.
    Public,
}

impl Audience {
    pub fn visibilities(self) -> Vec<String> {
        let v: &[&str] = match self {
            Audience::Staff => &["internal", "portal", "public"],
            Audience::Portal => &["portal", "public"],
            Audience::Public => &["public"],
        };
        v.iter().map(|s| s.to_string()).collect()
    }

    pub fn statuses(self) -> Vec<String> {
        let v: &[&str] = match self {
            Audience::Staff => &["draft", "published", "archived"],
            _ => &["published"],
        };
        v.iter().map(|s| s.to_string()).collect()
    }
}

pub struct Search<'a> {
    pub audience: Audience,
    pub company_id: Uuid,
    /// Search terms (web-search syntax) or, with `any_word`, a ready `a | b` query.
    pub q: Option<&'a str>,
    pub any_word: bool,
    /// The language to read and search in; entries without it use English, then another.
    pub language: &'a str,
    pub category_id: Option<Uuid>,
    pub tag: Option<&'a str>,
    pub visibility: Option<&'a str>,
    pub status: Option<&'a str>,
    /// Entries linked to this ticket category rank higher.
    pub ticket_category: Option<&'a str>,
    pub limit: i64,
    pub offset: i64,
}

#[derive(Debug, FromRow)]
struct HitRow {
    id: Uuid,
    number: String,
    slug: String,
    category_id: Option<Uuid>,
    visibility: String,
    status: String,
    language: String,
    fallback: bool,
    title: String,
    summary: String,
    body: String,
    updated_at: DateTime<Utc>,
    published_at: Option<DateTime<Utc>>,
    view_count: i64,
    helpful_yes: i32,
    helpful_no: i32,
    rank: Option<f32>,
    tags: Vec<String>,
}

#[derive(Debug)]
pub struct Hit {
    pub id: Uuid,
    pub number: String,
    pub slug: String,
    pub category_id: Option<Uuid>,
    pub visibility: String,
    pub status: String,
    pub language: String,
    pub fallback: bool,
    pub title: String,
    pub snippet: String,
    pub tags: Vec<String>,
    pub updated_at: DateTime<Utc>,
    pub published_at: Option<DateTime<Utc>>,
    pub view_count: i64,
    pub helpful_yes: i32,
    pub helpful_no: i32,
    pub rank: Option<f32>,
}

const SEARCH_SQL: &str = "
WITH eff AS (
    SELECT DISTINCT ON (e.id) e.id, t.language::text AS language, t.title, t.summary, t.body, t.search
    FROM kb.entries e JOIN kb.entry_texts t ON t.entry_id = e.id
    WHERE e.company_id = $1 AND e.visibility = ANY($2) AND e.status = ANY($3)
      AND ($5::uuid IS NULL OR e.category_id = $5
           OR e.category_id IN (SELECT c.id FROM kb.categories c WHERE c.parent_id = $5 AND c.company_id = $1))
      AND ($6::text IS NULL OR EXISTS (SELECT 1 FROM kb.entry_tags g WHERE g.entry_id = e.id AND g.tag = $6))
    ORDER BY e.id, (t.language::text = $4) DESC, (t.language::text = 'en') DESC,
             array_position(ARRAY['nl','fr','en','de','es'], t.language::text)
), ranked AS (
    SELECT eff.*, CASE WHEN $7::text IS NULL THEN NULL
                       ELSE ts_rank_cd(eff.search, kb.query(eff.language, $7, $8)) END AS rank
    FROM eff
    WHERE $7::text IS NULL OR eff.search @@ kb.query(eff.language, $7, $8)
)
SELECT e.id, e.number, e.slug, e.category_id, e.visibility, e.status, r.language,
       (r.language <> $4) AS fallback, r.title, r.summary, r.body, e.updated_at, e.published_at,
       e.view_count, e.helpful_yes, e.helpful_no, r.rank,
       ARRAY(SELECT g.tag FROM kb.entry_tags g WHERE g.entry_id = e.id ORDER BY g.tag) AS tags
FROM ranked r JOIN kb.entries e ON e.id = r.id
ORDER BY (coalesce(r.rank, 0)::float8 * CASE WHEN $9::text IS NOT NULL AND EXISTS (
              SELECT 1 FROM kb.entry_ticket_categories x WHERE x.entry_id = e.id AND x.ticket_category = $9)
              THEN 1.5 ELSE 1.0 END) DESC,
         lower(r.title), e.id
LIMIT $10 OFFSET $11";

/// Entries matching the filters and the search terms, best first, with a snippet each.
pub async fn search(conn: &mut PgConnection, s: &Search<'_>) -> AppResult<Vec<Hit>> {
    let q = s.q.map(str::trim).filter(|q| !q.is_empty());
    let mut visibilities = s.audience.visibilities();
    if let Some(v) = s.visibility {
        visibilities.retain(|x| x == v);
    }
    let mut statuses = s.audience.statuses();
    if let Some(v) = s.status {
        statuses.retain(|x| x == v);
    }
    let rows: Vec<HitRow> = sqlx::query_as(SEARCH_SQL)
        .bind(s.company_id)
        .bind(&visibilities)
        .bind(&statuses)
        .bind(s.language)
        .bind(s.category_id)
        .bind(s.tag.map(str::to_lowercase))
        .bind(q)
        .bind(s.any_word)
        .bind(s.ticket_category)
        .bind(s.limit.clamp(1, 200))
        .bind(s.offset.max(0))
        .fetch_all(&mut *conn)
        .await?;
    let snippets = match q {
        Some(q) if !rows.is_empty() => headlines(conn, &rows, q, s.any_word).await?,
        _ => rows
            .iter()
            .map(|r| excerpt(&r.summary, &r.body, 180))
            .collect(),
    };
    Ok(rows
        .into_iter()
        .zip(snippets)
        .map(|(r, snippet)| Hit {
            id: r.id,
            number: r.number,
            slug: r.slug,
            category_id: r.category_id,
            visibility: r.visibility,
            status: r.status,
            language: r.language,
            fallback: r.fallback,
            title: r.title,
            snippet,
            tags: r.tags,
            updated_at: r.updated_at,
            published_at: r.published_at,
            view_count: r.view_count,
            helpful_yes: r.helpful_yes,
            helpful_no: r.helpful_no,
            rank: r.rank,
        })
        .collect())
}

async fn headlines(
    conn: &mut PgConnection,
    rows: &[HitRow],
    q: &str,
    any_word: bool,
) -> AppResult<Vec<String>> {
    let langs: Vec<&str> = rows.iter().map(|r| r.language.as_str()).collect();
    let plains: Vec<String> = rows
        .iter()
        .map(|r| format!("{} {}", plain_text(&r.summary), plain_text(&r.body)))
        .collect();
    let options = format!(
        "StartSel={MARK_START}, StopSel={MARK_END}, MaxWords=28, MinWords=12, MaxFragments=1"
    );
    let out: Vec<String> = sqlx::query_scalar(
        "SELECT ts_headline(kb.config(x.l), x.p, kb.query(x.l, $3, $4), $5)
         FROM unnest($1::text[], $2::text[]) WITH ORDINALITY AS x(l, p, n) ORDER BY x.n",
    )
    .bind(&langs)
    .bind(&plains)
    .bind(q)
    .bind(any_word)
    .bind(options)
    .fetch_all(conn)
    .await?;
    Ok(out
        .into_iter()
        .map(|s| s.split_whitespace().collect::<Vec<_>>().join(" "))
        .collect())
}

// ---------------------------------------------------------------------------------------------
// Reading one entry
// ---------------------------------------------------------------------------------------------

#[derive(Debug, Serialize, ToSchema)]
pub struct ReaderLink {
    pub id: Uuid,
    pub number: String,
    pub title: String,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct ReaderImage {
    pub id: Uuid,
    pub filename: String,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct ReaderEntry {
    pub id: Uuid,
    pub number: String,
    pub slug: String,
    pub category_id: Option<Uuid>,
    /// The language of the text shown.
    pub language: String,
    /// True when the text is not in the language asked for.
    pub fallback: bool,
    pub available_languages: Vec<String>,
    pub title: String,
    pub summary: String,
    /// Simple Markdown. Images are written as `image:<id>` and listed in `images`.
    pub body: String,
    pub tags: Vec<String>,
    pub related: Vec<ReaderLink>,
    pub images: Vec<ReaderImage>,
    pub updated_at: DateTime<Utc>,
    /// The vote of the logged-in contact (portal only): true = helpful.
    pub my_vote: Option<bool>,
}

/// The title of each entry in the wanted language (else English, else any).
async fn titles(
    conn: &mut PgConnection,
    ids: &[Uuid],
    language: &str,
) -> AppResult<HashMap<Uuid, String>> {
    let rows: Vec<(Uuid, String)> = sqlx::query_as(
        "SELECT DISTINCT ON (entry_id) entry_id, title FROM kb.entry_texts WHERE entry_id = ANY($1)
         ORDER BY entry_id, (language::text = $2) DESC, (language::text = 'en') DESC, array_position(ARRAY['nl','fr','en','de','es'], language::text)",
    )
    .bind(ids)
    .bind(language)
    .fetch_all(conn)
    .await?;
    Ok(rows.into_iter().collect())
}

/// One entry for a reader. `NotFound` for anything the audience may not see (another company,
/// a draft, an archived entry, an internal one), so existence is not revealed. `count_view`
/// adds one to the view counter.
pub async fn read(
    conn: &mut PgConnection,
    audience: Audience,
    company_id: Uuid,
    id: Uuid,
    language: &str,
    contact_id: Option<Uuid>,
    count_view: bool,
) -> AppResult<ReaderEntry> {
    #[derive(FromRow)]
    struct E {
        number: String,
        slug: String,
        category_id: Option<Uuid>,
        updated_at: DateTime<Utc>,
    }
    let e: E = sqlx::query_as(
        "SELECT number, slug, category_id, updated_at FROM kb.entries
         WHERE id = $1 AND company_id = $2 AND visibility = ANY($3) AND status = ANY($4)",
    )
    .bind(id)
    .bind(company_id)
    .bind(audience.visibilities())
    .bind(audience.statuses())
    .fetch_optional(&mut *conn)
    .await?
    .ok_or(AppError::NotFound("knowledge base entry"))?;
    let texts = crate::model::texts_of(conn, id).await?;
    let langs: Vec<&str> = texts.iter().map(|t| t.language.as_str()).collect();
    let (i, fallback) = pick_language(&langs, language)
        .ok_or_else(|| AppError::NotFound("knowledge base entry"))?;
    let text = &texts[i];
    let tags: Vec<String> =
        sqlx::query_scalar("SELECT tag FROM kb.entry_tags WHERE entry_id = $1 ORDER BY tag")
            .bind(id)
            .fetch_all(&mut *conn)
            .await?;
    let related_ids: Vec<(Uuid, String)> = sqlx::query_as(
        "SELECT r.id, r.number FROM kb.entry_links l JOIN kb.entries r ON r.id = l.related_id
         WHERE l.entry_id = $1 AND r.company_id = $2 AND r.visibility = ANY($3) AND r.status = ANY($4)
         ORDER BY r.number",
    )
    .bind(id)
    .bind(company_id)
    .bind(audience.visibilities())
    .bind(audience.statuses())
    .fetch_all(&mut *conn)
    .await?;
    let ids: Vec<Uuid> = related_ids.iter().map(|(i, _)| *i).collect();
    let titles = titles(conn, &ids, language).await?;
    let related = related_ids
        .into_iter()
        .map(|(id, number)| ReaderLink {
            title: titles.get(&id).cloned().unwrap_or_default(),
            id,
            number,
        })
        .collect();
    let images: Vec<(Uuid, String)> = sqlx::query_as(
        "SELECT f.id, f.filename FROM kb.entry_images i JOIN core.files f ON f.id = i.file_id
         WHERE i.entry_id = $1 ORDER BY i.created_at, f.id",
    )
    .bind(id)
    .fetch_all(&mut *conn)
    .await?;
    let my_vote = match contact_id {
        Some(c) => {
            sqlx::query_scalar(
                "SELECT helpful FROM kb.votes WHERE entry_id = $1 AND contact_id = $2",
            )
            .bind(id)
            .bind(c)
            .fetch_optional(&mut *conn)
            .await?
        }
        None => None,
    };
    if count_view {
        sqlx::query("UPDATE kb.entries SET view_count = view_count + 1 WHERE id = $1")
            .bind(id)
            .execute(&mut *conn)
            .await?;
    }
    Ok(ReaderEntry {
        id,
        number: e.number,
        slug: e.slug,
        category_id: e.category_id,
        language: text.language.clone(),
        fallback,
        available_languages: texts.iter().map(|t| t.language.clone()).collect(),
        title: text.title.clone(),
        summary: text.summary.clone(),
        body: text.body.clone(),
        tags,
        related,
        images: images
            .into_iter()
            .map(|(id, filename)| ReaderImage { id, filename })
            .collect(),
        updated_at: e.updated_at,
        my_vote,
    })
}

// ---------------------------------------------------------------------------------------------
// Categories for readers
// ---------------------------------------------------------------------------------------------

#[derive(Debug, Serialize, ToSchema)]
pub struct ReaderCategory {
    pub id: Uuid,
    pub parent_id: Option<Uuid>,
    pub name: String,
    pub sort_order: i32,
    /// Entries the reader can open in this category, sub-categories included.
    pub entry_count: i64,
}

/// Active categories with at least one entry the audience can read, in sort order.
pub async fn categories(
    conn: &mut PgConnection,
    audience: Audience,
    company_id: Uuid,
    language: &str,
) -> AppResult<Vec<ReaderCategory>> {
    #[derive(FromRow)]
    struct C {
        id: Uuid,
        parent_id: Option<Uuid>,
        sort_order: i32,
        own: i64,
    }
    let rows: Vec<C> = sqlx::query_as(
        "SELECT c.id, c.parent_id, c.sort_order,
                (SELECT count(*) FROM kb.entries e WHERE e.category_id = c.id AND e.company_id = $1
                   AND e.visibility = ANY($2) AND e.status = ANY($3)) AS own
         FROM kb.categories c WHERE c.company_id = $1 AND c.active
         ORDER BY c.sort_order, c.id",
    )
    .bind(company_id)
    .bind(audience.visibilities())
    .bind(audience.statuses())
    .fetch_all(&mut *conn)
    .await?;
    let ids: Vec<Uuid> = rows.iter().map(|r| r.id).collect();
    let names: Vec<(Uuid, CategoryName)> = names_of(conn, &ids).await?;
    let name_of = |id: Uuid| -> String {
        let mine: Vec<&CategoryName> = names
            .iter()
            .filter(|(c, _)| *c == id)
            .map(|(_, n)| n)
            .collect();
        let langs: Vec<&str> = mine.iter().map(|n| n.language.as_str()).collect();
        pick_language(&langs, language)
            .map(|(i, _)| mine[i].name.clone())
            .unwrap_or_default()
    };
    let total = |r: &C| -> i64 {
        r.own
            + rows
                .iter()
                .filter(|c| c.parent_id == Some(r.id))
                .map(|c| c.own)
                .sum::<i64>()
    };
    Ok(rows
        .iter()
        .filter(|r| total(r) > 0)
        .map(|r| ReaderCategory {
            id: r.id,
            parent_id: r.parent_id,
            name: name_of(r.id),
            sort_order: r.sort_order,
            entry_count: total(r),
        })
        .collect())
}

pub async fn names_of(
    conn: &mut PgConnection,
    ids: &[Uuid],
) -> AppResult<Vec<(Uuid, CategoryName)>> {
    #[derive(FromRow)]
    struct N {
        category_id: Uuid,
        language: String,
        name: String,
    }
    let rows: Vec<N> = sqlx::query_as(sqlx::AssertSqlSafe(format!(
        "SELECT category_id, language::text AS language, name FROM kb.category_names
         WHERE category_id = ANY($1) ORDER BY category_id, {LANGUAGE_ORDER}"
    )))
    .bind(ids)
    .fetch_all(conn)
    .await?;
    Ok(rows
        .into_iter()
        .map(|n| {
            (
                n.category_id,
                CategoryName {
                    language: n.language,
                    name: n.name,
                },
            )
        })
        .collect())
}

// ---------------------------------------------------------------------------------------------
// Votes and images
// ---------------------------------------------------------------------------------------------

/// Records (or changes) the vote of a contact. One vote per contact and entry; the counters on
/// the entry are recounted from the votes, so a changed vote never double counts.
pub async fn vote(
    conn: &mut PgConnection,
    company_id: Uuid,
    contact_id: Uuid,
    entry_id: Uuid,
    helpful: bool,
) -> AppResult<()> {
    let visible: Option<Uuid> = sqlx::query_scalar(
        "SELECT id FROM kb.entries WHERE id = $1 AND company_id = $2 AND status = 'published'
           AND visibility IN ('portal', 'public') FOR UPDATE",
    )
    .bind(entry_id)
    .bind(company_id)
    .fetch_optional(&mut *conn)
    .await?;
    visible.ok_or(AppError::NotFound("knowledge base entry"))?;
    sqlx::query(
        "INSERT INTO kb.votes (entry_id, contact_id, helpful) VALUES ($1, $2, $3)
         ON CONFLICT (entry_id, contact_id) DO UPDATE SET helpful = EXCLUDED.helpful, updated_at = now()",
    )
    .bind(entry_id)
    .bind(contact_id)
    .bind(helpful)
    .execute(&mut *conn)
    .await?;
    sqlx::query(
        "UPDATE kb.entries SET
            helpful_yes = (SELECT count(*) FROM kb.votes WHERE entry_id = $1 AND helpful),
            helpful_no = (SELECT count(*) FROM kb.votes WHERE entry_id = $1 AND NOT helpful)
         WHERE id = $1",
    )
    .bind(entry_id)
    .execute(conn)
    .await?;
    Ok(())
}

/// An image of an entry the audience may read: content type and bytes.
pub async fn image(
    conn: &mut PgConnection,
    blobs: &tradocraft_core::BlobStore,
    audience: Audience,
    company_id: Uuid,
    entry_id: Uuid,
    file_id: Uuid,
) -> AppResult<(String, Vec<u8>)> {
    let ok: Option<Uuid> = sqlx::query_scalar(
        "SELECT i.file_id FROM kb.entry_images i JOIN kb.entries e ON e.id = i.entry_id
         WHERE i.file_id = $1 AND e.id = $2 AND e.company_id = $3
           AND e.visibility = ANY($4) AND e.status = ANY($5)",
    )
    .bind(file_id)
    .bind(entry_id)
    .bind(company_id)
    .bind(audience.visibilities())
    .bind(audience.statuses())
    .fetch_optional(&mut *conn)
    .await?;
    ok.ok_or(AppError::NotFound("image"))?;
    tradocraft_core::files::load(conn, blobs, company_id, file_id).await
}

/// Public summary of a hit: nothing about counters or status.
#[derive(Debug, Serialize, ToSchema)]
pub struct ReaderSummary {
    pub id: Uuid,
    pub number: String,
    pub slug: String,
    pub category_id: Option<Uuid>,
    pub language: String,
    pub fallback: bool,
    pub title: String,
    /// Plain text; matched words are wrapped in U+E000 / U+E001 when searching.
    pub snippet: String,
    pub tags: Vec<String>,
    pub updated_at: DateTime<Utc>,
}

impl From<Hit> for ReaderSummary {
    fn from(h: Hit) -> Self {
        ReaderSummary {
            id: h.id,
            number: h.number,
            slug: h.slug,
            category_id: h.category_id,
            language: h.language,
            fallback: h.fallback,
            title: h.title,
            snippet: h.snippet,
            tags: h.tags,
            updated_at: h.updated_at,
        }
    }
}
