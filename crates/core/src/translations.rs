//! Translation catalogues (ADR 0101): flat `key → text` maps per domain and language.
//!
//! - `documents`: the fixed words of printed documents, keyed `<template>.<label>`
//!   (`delivery_note.title`); the PDF renderer hands a template its section as `labels.json`.
//! - `mail`: subjects and bodies of system mails, keyed `mail.<kind>.<part>`, with `{name}`
//!   placeholders.
//! - `app` and `web`: interface texts of the Flutter app and the web UI, loaded by the clients at
//!   runtime over their compiled-in texts.
//!
//! The application ships catalogues for `documents` and `mail` (compiled in from
//! `crates/core/i18n/<domain>/<language>.json`; English is complete). A company can add a
//! catalogue for any ISO 639-1 language, or override shipped texts, in `core.translations`.
//! [`catalogue`] layers shipped English, the company's English, the shipped language and the
//! company's language, so a key missing in a language falls back to English.

use std::collections::{BTreeMap, HashMap};
use std::sync::LazyLock;

use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::Json;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::PgExecutor;
use utoipa::ToSchema;
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::auth::Permission;
use crate::language::is_iso_639_1;
use crate::languages::SOURCE_LANGUAGE;
use crate::{audit, AppError, AppResult, AppState, CurrentUser};

type ErrorBody = crate::error::ErrorBody;

/// What a catalogue translates.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum Domain {
    /// Labels of printed documents.
    Documents,
    /// System mails.
    Mail,
    /// The Flutter app and the customer portal app.
    App,
    /// The web UI.
    Web,
}

impl Domain {
    pub const ALL: [Domain; 4] = [Domain::Documents, Domain::Mail, Domain::App, Domain::Web];

    pub fn code(self) -> &'static str {
        match self {
            Domain::Documents => "documents",
            Domain::Mail => "mail",
            Domain::App => "app",
            Domain::Web => "web",
        }
    }

    pub fn parse(code: &str) -> Option<Domain> {
        Domain::ALL.into_iter().find(|d| d.code() == code)
    }

    /// Whether the server ships the source texts of this domain (and therefore knows its keys).
    pub fn server_side(self) -> bool {
        matches!(self, Domain::Documents | Domain::Mail)
    }
}

/// The catalogues compiled into the binary: `(domain, language, json)`.
const SHIPPED_FILES: &[(Domain, &str, &str)] = &[
    (
        Domain::Documents,
        "en",
        include_str!("../i18n/documents/en.json"),
    ),
    (
        Domain::Documents,
        "nl",
        include_str!("../i18n/documents/nl.json"),
    ),
    (
        Domain::Documents,
        "fr",
        include_str!("../i18n/documents/fr.json"),
    ),
    (
        Domain::Documents,
        "de",
        include_str!("../i18n/documents/de.json"),
    ),
    (
        Domain::Documents,
        "es",
        include_str!("../i18n/documents/es.json"),
    ),
    (Domain::Mail, "en", include_str!("../i18n/mail/en.json")),
    (Domain::Mail, "nl", include_str!("../i18n/mail/nl.json")),
    (Domain::Mail, "fr", include_str!("../i18n/mail/fr.json")),
    (Domain::Mail, "de", include_str!("../i18n/mail/de.json")),
    (Domain::Mail, "es", include_str!("../i18n/mail/es.json")),
];

type Entries = BTreeMap<String, String>;

static SHIPPED: LazyLock<HashMap<(Domain, String), Entries>> = LazyLock::new(|| {
    SHIPPED_FILES
        .iter()
        .map(|(d, l, json)| {
            let entries: Entries = serde_json::from_str(json)
                .unwrap_or_else(|e| panic!("shipped catalogue {}/{l}: {e}", d.code()));
            ((*d, l.to_string()), entries)
        })
        .collect()
});

/// The shipped entries of a domain in a language (empty when none are shipped).
pub fn shipped(domain: Domain, language: &str) -> &'static Entries {
    static EMPTY: Entries = BTreeMap::new();
    SHIPPED
        .get(&(domain, language.to_string()))
        .unwrap_or(&EMPTY)
}

/// The languages with a shipped catalogue of `domain`.
pub fn shipped_languages(domain: Domain) -> Vec<&'static str> {
    let mut v: Vec<&str> = SHIPPED_FILES
        .iter()
        .filter(|(d, _, _)| *d == domain)
        .map(|(_, l, _)| *l)
        .collect();
    v.sort_unstable();
    v
}

/// Resolved texts of one domain in one language, English underneath.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Catalogue {
    language: String,
    entries: Entries,
}

impl Catalogue {
    /// The shipped texts only (no company additions): English with `language` on top.
    pub fn shipped(domain: Domain, language: &str) -> Catalogue {
        Catalogue::layered(
            language,
            [shipped(domain, SOURCE_LANGUAGE), shipped(domain, language)],
        )
    }

    fn layered<'a>(language: &str, layers: impl IntoIterator<Item = &'a Entries>) -> Catalogue {
        let mut entries = Entries::new();
        for layer in layers {
            for (k, v) in layer {
                if !v.is_empty() {
                    entries.insert(k.clone(), v.clone());
                }
            }
        }
        Catalogue {
            language: language.to_string(),
            entries,
        }
    }

    /// The language the catalogue was asked for (keys may still come from English).
    pub fn language(&self) -> &str {
        &self.language
    }

    /// The text of `key`; the key itself when no layer has it (a missing key stays visible).
    pub fn get<'a>(&'a self, key: &'a str) -> &'a str {
        self.entries.get(key).map(String::as_str).unwrap_or(key)
    }

    /// The text of `key` with `{name}` placeholders replaced by `args`.
    pub fn format(&self, key: &str, args: &[(&str, &str)]) -> String {
        fill(self.get(key), args)
    }

    /// The entries under `prefix.` with the prefix removed: what a template reads as its labels.
    pub fn section(&self, prefix: &str) -> Entries {
        let dotted = format!("{prefix}.");
        self.entries
            .iter()
            .filter_map(|(k, v)| k.strip_prefix(&dotted).map(|k| (k.to_string(), v.clone())))
            .collect()
    }
}

/// Replaces every `{name}` of `text` by its value in `args`; unknown placeholders stay.
pub fn fill(text: &str, args: &[(&str, &str)]) -> String {
    let mut out = String::with_capacity(text.len());
    let mut rest = text;
    while let Some(start) = rest.find('{') {
        out.push_str(&rest[..start]);
        let after = &rest[start + 1..];
        match after.find('}') {
            Some(end) => {
                let name = &after[..end];
                match args.iter().find(|(n, _)| *n == name) {
                    Some((_, v)) => out.push_str(v),
                    None => {
                        out.push('{');
                        out.push_str(name);
                        out.push('}');
                    }
                }
                rest = &after[end + 1..];
            }
            None => {
                out.push_str(&rest[start..]);
                rest = "";
            }
        }
    }
    out.push_str(rest);
    out
}

async fn company_entries<'e>(
    db: impl PgExecutor<'e>,
    company_id: Uuid,
    domain: Domain,
    languages: &[&str],
) -> Result<HashMap<String, Entries>, sqlx::Error> {
    let rows: Vec<(String, sqlx::types::Json<Entries>)> = sqlx::query_as(
        "SELECT language, entries FROM core.translations
         WHERE company_id = $1 AND domain = $2 AND language = ANY($3)",
    )
    .bind(company_id)
    .bind(domain.code())
    .bind(languages)
    .fetch_all(db)
    .await?;
    Ok(rows.into_iter().map(|(l, e)| (l, e.0)).collect())
}

/// The texts of `domain` in `language` for a company: shipped English, the company's English,
/// the shipped language, the company's language (later layers win; empty texts are skipped).
pub async fn catalogue<'e>(
    db: impl PgExecutor<'e>,
    company_id: Uuid,
    domain: Domain,
    language: &str,
) -> Result<Catalogue, sqlx::Error> {
    let mut company = company_entries(db, company_id, domain, &[SOURCE_LANGUAGE, language]).await?;
    let empty = Entries::new();
    let company_en = company.remove(SOURCE_LANGUAGE).unwrap_or_default();
    let company_lang = company.remove(language).unwrap_or_default();
    let (shipped_lang, company_lang) = if language == SOURCE_LANGUAGE {
        (&empty, &empty)
    } else {
        (shipped(domain, language), &company_lang)
    };
    Ok(Catalogue::layered(
        language,
        [
            shipped(domain, SOURCE_LANGUAGE),
            &company_en,
            shipped_lang,
            company_lang,
        ],
    ))
}

/// The languages in which the company has texts of `domain` (an installed interface language,
/// for `app` and `web`).
pub async fn languages_with_company_texts<'e>(
    db: impl PgExecutor<'e>,
    company_id: Uuid,
    domain: Domain,
) -> Result<Vec<String>, sqlx::Error> {
    sqlx::query_scalar(
        "SELECT language FROM core.translations
         WHERE company_id = $1 AND domain = $2 AND entries <> '{}'::jsonb ORDER BY language",
    )
    .bind(company_id)
    .bind(domain.code())
    .fetch_all(db)
    .await
}

/// The company's own texts of a domain in one language (empty when it has none).
pub async fn company_texts<'e>(
    db: impl PgExecutor<'e>,
    company_id: Uuid,
    domain: Domain,
    language: &str,
) -> Result<Entries, sqlx::Error> {
    Ok(company_entries(db, company_id, domain, &[language])
        .await?
        .remove(language)
        .unwrap_or_default())
}

/// The document labels for printing in `language` (see [`catalogue`]).
pub async fn document_labels<'e>(
    db: impl PgExecutor<'e>,
    company_id: Uuid,
    language: &str,
) -> Result<Catalogue, sqlx::Error> {
    catalogue(db, company_id, Domain::Documents, language).await
}

/// The mail texts for writing in `language` (see [`catalogue`]).
pub async fn mail_texts<'e>(
    db: impl PgExecutor<'e>,
    company_id: Uuid,
    language: &str,
) -> Result<Catalogue, sqlx::Error> {
    catalogue(db, company_id, Domain::Mail, language).await
}

// ---------------------------------------------------------------------------------------------
// Endpoints
// ---------------------------------------------------------------------------------------------

/// At most this many entries per catalogue.
pub const MAX_ENTRIES: usize = 20_000;
const MAX_KEY: usize = 200;
const MAX_TEXT: usize = 20_000;

fn parse_domain(code: &str) -> AppResult<Domain> {
    Domain::parse(code).ok_or(AppError::NotFound("translation domain"))
}

fn parse_language(code: &str) -> AppResult<String> {
    let code = code.trim().to_ascii_lowercase();
    if is_iso_639_1(&code) {
        Ok(code)
    } else {
        Err(AppError::Validation(
            "language must be an ISO 639-1 language code".into(),
        ))
    }
}

/// A language that has a catalogue in a domain.
#[derive(Debug, Serialize, ToSchema)]
pub struct CatalogueInfo {
    pub language: String,
    /// The application ships texts in this language.
    pub shipped: bool,
    /// Number of texts the company added or overrides.
    pub company_entries: i64,
    /// When the company's texts last changed; none without company texts.
    pub updated_at: Option<DateTime<Utc>>,
}

/// The languages that have shipped or company texts in a domain.
#[utoipa::path(get, path = "/translations/{domain}", tag = "core",
    params(("domain" = String, Path, description = "documents | mail | app | web")),
    responses((status = 200, body = Vec<CatalogueInfo>), (status = 404, body = ErrorBody)))]
async fn list_catalogues(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(domain): Path<String>,
) -> AppResult<Json<Vec<CatalogueInfo>>> {
    let domain = parse_domain(&domain)?;
    let rows: Vec<(String, i64, DateTime<Utc>)> = sqlx::query_as(
        "SELECT language, (SELECT count(*) FROM jsonb_object_keys(entries)), updated_at
         FROM core.translations WHERE company_id = $1 AND domain = $2",
    )
    .bind(user.company_id)
    .bind(domain.code())
    .fetch_all(&state.db)
    .await?;
    let mut out: BTreeMap<String, CatalogueInfo> = shipped_languages(domain)
        .into_iter()
        .map(|l| {
            (
                l.to_string(),
                CatalogueInfo {
                    language: l.to_string(),
                    shipped: true,
                    company_entries: 0,
                    updated_at: None,
                },
            )
        })
        .collect();
    for (language, n, at) in rows {
        let info = out.entry(language.clone()).or_insert(CatalogueInfo {
            language,
            shipped: false,
            company_entries: 0,
            updated_at: None,
        });
        info.company_entries = n;
        info.updated_at = Some(at);
    }
    Ok(Json(out.into_values().collect()))
}

/// One catalogue: the company's texts, the shipped texts and the English source.
#[derive(Debug, Serialize, ToSchema)]
pub struct CatalogueDetail {
    pub domain: Domain,
    pub language: String,
    /// Texts the company added or overrides.
    pub entries: BTreeMap<String, String>,
    /// Texts the application ships in this language (documents and mail only).
    pub shipped: BTreeMap<String, String>,
    /// The English source texts: every key there is, the template for a translator (documents
    /// and mail only; the clients ship their own source for app and web).
    pub source: BTreeMap<String, String>,
}

/// The texts of one domain and language.
#[utoipa::path(get, path = "/translations/{domain}/{language}", tag = "core",
    params(("domain" = String, Path, description = "documents | mail | app | web"),
        ("language" = String, Path, description = "ISO 639-1 code")),
    responses((status = 200, body = CatalogueDetail), (status = 404, body = ErrorBody),
        (status = 422, body = ErrorBody)))]
async fn get_catalogue(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((domain, language)): Path<(String, String)>,
) -> AppResult<Json<CatalogueDetail>> {
    let domain = parse_domain(&domain)?;
    let language = parse_language(&language)?;
    let mut company = company_entries(&state.db, user.company_id, domain, &[&language]).await?;
    Ok(Json(CatalogueDetail {
        domain,
        entries: company.remove(&language).unwrap_or_default(),
        shipped: shipped(domain, &language).clone(),
        source: shipped(domain, SOURCE_LANGUAGE).clone(),
        language,
    }))
}

/// The texts a company adds or overrides in one domain and language.
#[derive(Debug, Deserialize, ToSchema)]
pub struct CatalogueInput {
    /// `key → text`; empty texts are dropped. For documents and mail the keys must exist in the
    /// English source.
    pub entries: BTreeMap<String, String>,
}

fn valid_key(k: &str) -> bool {
    !k.is_empty()
        && k.len() <= MAX_KEY
        && k.chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '_' | '.' | '-'))
}

/// Checks and cleans a catalogue: keys well-formed (and known, for server-side domains), texts
/// at most 20 000 characters, at most [`MAX_ENTRIES`] entries; empty texts dropped.
pub fn validate_entries(domain: Domain, entries: BTreeMap<String, String>) -> AppResult<Entries> {
    if entries.len() > MAX_ENTRIES {
        return Err(AppError::Validation(format!(
            "a catalogue holds at most {MAX_ENTRIES} texts"
        )));
    }
    let source = shipped(domain, SOURCE_LANGUAGE);
    let mut out = Entries::new();
    for (k, v) in entries {
        if !valid_key(&k) {
            return Err(AppError::Validation(format!("invalid key {k:?}")));
        }
        if domain.server_side() && !source.contains_key(&k) {
            return Err(AppError::Validation(format!("unknown key {k:?}")));
        }
        if v.chars().count() > MAX_TEXT {
            return Err(AppError::Validation(format!("the text of {k} is too long")));
        }
        if !v.trim().is_empty() {
            out.insert(k, v);
        }
    }
    Ok(out)
}

/// Replaces the company's texts of one domain and language (administrators).
#[utoipa::path(put, path = "/admin/translations/{domain}/{language}", tag = "core",
    params(("domain" = String, Path, description = "documents | mail | app | web"),
        ("language" = String, Path, description = "ISO 639-1 code")),
    request_body = CatalogueInput,
    responses((status = 200, body = CatalogueDetail), (status = 403, body = ErrorBody),
        (status = 404, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn put_catalogue(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((domain, language)): Path<(String, String)>,
    Json(input): Json<CatalogueInput>,
) -> AppResult<Json<CatalogueDetail>> {
    user.require(Permission::UsersAdmin)?;
    let domain = parse_domain(&domain)?;
    let language = parse_language(&language)?;
    let entries = validate_entries(domain, input.entries)?;
    let mut tx = state.db.begin().await?;
    sqlx::query(
        "INSERT INTO core.translations (company_id, domain, language, entries, updated_at, updated_by)
         VALUES ($1, $2, $3, $4, now(), $5)
         ON CONFLICT (company_id, domain, language)
         DO UPDATE SET entries = EXCLUDED.entries, updated_at = now(), updated_by = EXCLUDED.updated_by",
    )
    .bind(user.company_id)
    .bind(domain.code())
    .bind(&language)
    .bind(sqlx::types::Json(&entries))
    .bind(user.user_id)
    .execute(&mut *tx)
    .await?;
    audit::record(
        &mut tx,
        &user,
        "translation",
        user.company_id,
        "saved",
        serde_json::json!({ "domain": domain.code(), "language": language, "entries": entries.len() }),
    )
    .await?;
    tx.commit().await?;
    Ok(Json(CatalogueDetail {
        domain,
        shipped: shipped(domain, &language).clone(),
        source: shipped(domain, SOURCE_LANGUAGE).clone(),
        entries,
        language,
    }))
}

/// Removes the company's texts of one domain and language (administrators); shipped texts stay.
#[utoipa::path(delete, path = "/admin/translations/{domain}/{language}", tag = "core",
    params(("domain" = String, Path, description = "documents | mail | app | web"),
        ("language" = String, Path, description = "ISO 639-1 code")),
    responses((status = 204), (status = 403, body = ErrorBody), (status = 404, body = ErrorBody)))]
async fn delete_catalogue(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((domain, language)): Path<(String, String)>,
) -> AppResult<StatusCode> {
    user.require(Permission::UsersAdmin)?;
    let domain = parse_domain(&domain)?;
    let language = parse_language(&language)?;
    let mut tx = state.db.begin().await?;
    let gone = sqlx::query(
        "DELETE FROM core.translations WHERE company_id = $1 AND domain = $2 AND language = $3",
    )
    .bind(user.company_id)
    .bind(domain.code())
    .bind(&language)
    .execute(&mut *tx)
    .await?
    .rows_affected();
    if gone == 0 {
        return Err(AppError::NotFound("catalogue"));
    }
    audit::record(
        &mut tx,
        &user,
        "translation",
        user.company_id,
        "deleted",
        serde_json::json!({ "domain": domain.code(), "language": language }),
    )
    .await?;
    tx.commit().await?;
    Ok(StatusCode::NO_CONTENT)
}

/// The catalogue endpoints.
pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(list_catalogues))
        .routes(routes!(get_catalogue))
        .routes(routes!(put_catalogue, delete_catalogue))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn m(pairs: &[(&str, &str)]) -> Entries {
        pairs
            .iter()
            .map(|(k, v)| (k.to_string(), v.to_string()))
            .collect()
    }

    #[test]
    fn shipped_catalogues_parse_and_have_only_english_keys() {
        for domain in [Domain::Documents, Domain::Mail] {
            let en = shipped(domain, "en");
            assert!(!en.is_empty(), "{domain:?}");
            for lang in shipped_languages(domain) {
                for (k, v) in shipped(domain, lang) {
                    assert!(
                        en.contains_key(k),
                        "{domain:?}/{lang}: {k} is not in English"
                    );
                    assert!(!v.trim().is_empty(), "{domain:?}/{lang}: {k} is empty");
                }
            }
        }
    }

    #[test]
    fn layers_fall_back_to_english() {
        let c = Catalogue::layered(
            "pt",
            [
                &m(&[("a", "A"), ("b", "B"), ("c", "C")]),
                &m(&[("b", "Bé")]),
                &m(&[("c", ""), ("a", "Á")]),
            ],
        );
        assert_eq!((c.get("a"), c.get("b"), c.get("c")), ("Á", "Bé", "C"));
        assert_eq!(c.get("missing"), "missing");
        assert_eq!(c.language(), "pt");
    }

    #[test]
    fn sections_strip_their_prefix() {
        let c = Catalogue::layered(
            "en",
            [&m(&[("dn.title", "T"), ("dn.page", "P"), ("x.y", "Z")])],
        );
        assert_eq!(c.section("dn"), m(&[("title", "T"), ("page", "P")]));
    }

    #[test]
    fn placeholders_are_filled() {
        assert_eq!(
            fill("Order {n}{rev}", &[("n", "42"), ("rev", "")]),
            "Order 42"
        );
        assert_eq!(fill("{a} {unknown} {", &[("a", "x")]), "x {unknown} {");
    }

    #[test]
    fn entries_are_checked() {
        assert!(
            validate_entries(Domain::App, m(&[("ok_key.1", "x"), ("e", " ")]))
                .is_ok_and(|e| e.len() == 1)
        );
        assert!(validate_entries(Domain::App, m(&[("bad key", "x")])).is_err());
        assert!(validate_entries(Domain::Documents, m(&[("nope.nothing", "x")])).is_err());
        assert!(validate_entries(Domain::Documents, m(&[("delivery_note.title", "x")])).is_ok());
    }
}
