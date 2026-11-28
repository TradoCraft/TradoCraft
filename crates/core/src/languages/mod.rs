//! Content languages (ADR 0101): which languages a company writes and publishes in, the fallback
//! chain for content that is missing in a language, and the display names of every ISO 639-1
//! code.
//!
//! The rule for checking a language code:
//! - stored content (a customer's language, a text per language, a ticket's language, ...) takes
//!   any ISO 639-1 code ([`crate::is_language`]), so imports, inbound mail and records written
//!   before a language was removed from the company stay valid;
//! - where the company publishes in a chosen set of languages (its default language, the
//!   languages of a price list zone) the code must be one of the company's configured languages
//!   ([`require_company_language`]);
//! - language pickers in the clients offer the company's configured languages, in their order.

pub mod names;

use std::collections::HashSet;

use axum::extract::State;
use axum::Json;
use serde::{Deserialize, Serialize};
use sqlx::{PgConnection, PgExecutor};
use utoipa::ToSchema;
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::auth::Permission;
use crate::company::{get_company, Company};
use crate::language::is_iso_639_1;
use crate::{audit, AppError, AppResult, AppState, CurrentUser};

/// The last resort of every fallback chain: the language the application itself is written in.
pub const SOURCE_LANGUAGE: &str = "en";

/// At most this many content languages per company.
pub const MAX_COMPANY_LANGUAGES: usize = 50;

/// The company's content languages in their configured order (the default is one of them).
pub async fn company_languages<'e>(
    db: impl PgExecutor<'e>,
    company_id: Uuid,
) -> Result<Vec<String>, sqlx::Error> {
    sqlx::query_scalar(
        "SELECT language FROM core.company_languages WHERE company_id = $1 ORDER BY sort_order",
    )
    .bind(company_id)
    .fetch_all(db)
    .await
}

/// Fails with a validation error naming `field` unless `code` is one of the company's languages.
pub async fn require_company_language<'e>(
    db: impl PgExecutor<'e>,
    company_id: Uuid,
    field: &str,
    code: &str,
) -> AppResult<()> {
    let ok: bool = sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM core.company_languages WHERE company_id = $1 AND language = $2)",
    )
    .bind(company_id)
    .bind(code)
    .fetch_one(db)
    .await?;
    if ok {
        Ok(())
    } else {
        Err(AppError::Validation(format!(
            "{field}: {code:?} is not one of the company's languages"
        )))
    }
}

/// The order in which languages are tried for content missing in `requested`: the requested
/// language, English (the most widely read second language of a customer, and what the
/// knowledge base and prepared answers always fell back to), the company's default, then the
/// company's other languages in their order. Without duplicates.
pub fn fallback_chain(requested: &str, company_default: &str, company: &[String]) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    for l in [requested, SOURCE_LANGUAGE, company_default]
        .into_iter()
        .chain(company.iter().map(String::as_str))
    {
        if !l.is_empty() && !out.iter().any(|o| o == l) {
            out.push(l.to_string());
        }
    }
    out
}

/// Index of the text to show among `available` languages: the first of `chain` that is
/// available, else the first available one. The flag tells that it is not `chain[0]`.
pub fn pick<S: AsRef<str>>(available: &[S], chain: &[String]) -> Option<(usize, bool)> {
    for (n, wanted) in chain.iter().enumerate() {
        if let Some(i) = available.iter().position(|a| a.as_ref() == wanted) {
            return Some((i, n > 0));
        }
    }
    (!available.is_empty()).then_some((0, true))
}

/// Normalises and checks a company's language list: trimmed, lower-case, ISO 639-1, no
/// duplicates, 1 to [`MAX_COMPANY_LANGUAGES`] entries, and containing `default_language`.
pub fn validate_company_languages(
    languages: &[String],
    default_language: &str,
) -> AppResult<(Vec<String>, String)> {
    let languages: Vec<String> = languages.iter().map(|l| l.trim().to_lowercase()).collect();
    let default_language = default_language.trim().to_lowercase();
    if languages.is_empty() || languages.len() > MAX_COMPANY_LANGUAGES {
        return Err(AppError::Validation(format!(
            "languages must hold 1 to {MAX_COMPANY_LANGUAGES} languages"
        )));
    }
    if let Some(bad) = languages.iter().find(|l| !is_iso_639_1(l)) {
        return Err(AppError::Validation(format!(
            "languages: {bad:?} is not an ISO 639-1 language code"
        )));
    }
    if languages.iter().collect::<HashSet<_>>().len() != languages.len() {
        return Err(AppError::Validation(
            "languages must not repeat a language".into(),
        ));
    }
    if !languages.contains(&default_language) {
        return Err(AppError::Validation(
            "default_language must be one of languages".into(),
        ));
    }
    Ok((languages, default_language))
}

/// Replaces the company's languages and default (inside the caller's transaction).
pub async fn set_company_languages(
    conn: &mut PgConnection,
    company_id: Uuid,
    languages: &[String],
    default_language: &str,
) -> AppResult<()> {
    let (languages, default_language) = validate_company_languages(languages, default_language)?;
    sqlx::query("DELETE FROM core.company_languages WHERE company_id = $1")
        .bind(company_id)
        .execute(&mut *conn)
        .await?;
    sqlx::query(
        "INSERT INTO core.company_languages (company_id, language, sort_order)
         SELECT $1, l, (o - 1)::int FROM unnest($2::text[]) WITH ORDINALITY AS t (l, o)",
    )
    .bind(company_id)
    .bind(&languages)
    .execute(&mut *conn)
    .await?;
    sqlx::query("UPDATE core.companies SET default_language = $2 WHERE id = $1")
        .bind(company_id)
        .bind(&default_language)
        .execute(&mut *conn)
        .await?;
    Ok(())
}

/// An ISO 639-1 language with its display names.
#[derive(Debug, Serialize, ToSchema)]
pub struct LanguageInfo {
    /// ISO 639-1 code, e.g. `pt`.
    pub code: String,
    /// English name, e.g. `Portuguese`.
    pub english_name: String,
    /// The language's own name, e.g. `Português`.
    pub name: String,
}

/// Every ISO 639-1 language with its names: what an administrator chooses company languages from.
#[utoipa::path(get, path = "/languages", tag = "core",
    responses((status = 200, body = Vec<LanguageInfo>), (status = 401, body = crate::error::ErrorBody)))]
async fn list_languages(_user: CurrentUser) -> Json<Vec<LanguageInfo>> {
    Json(
        names::LANGUAGE_NAMES
            .iter()
            .map(|(code, english, own)| LanguageInfo {
                code: code.to_string(),
                english_name: english.to_string(),
                name: own.to_string(),
            })
            .collect(),
    )
}

/// The company's content languages, in the order pickers show them.
#[derive(Debug, Deserialize, ToSchema)]
pub struct CompanyLanguagesInput {
    /// ISO 639-1 codes in display order, 1 to 50, without duplicates.
    pub languages: Vec<String>,
    /// The default language; must be one of `languages`.
    pub default_language: String,
}

/// Replaces the company's content languages and default language (administrators).
#[utoipa::path(put, path = "/admin/company/languages", tag = "core",
    request_body = CompanyLanguagesInput,
    responses((status = 200, body = Company), (status = 403, body = crate::error::ErrorBody),
        (status = 422, body = crate::error::ErrorBody)))]
async fn put_company_languages(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<CompanyLanguagesInput>,
) -> AppResult<Json<Company>> {
    user.require(Permission::UsersAdmin)?;
    let (languages, default_language) =
        validate_company_languages(&input.languages, &input.default_language)?;
    let mut tx = state.db.begin().await?;
    set_company_languages(&mut tx, user.company_id, &languages, &default_language).await?;
    audit::record(
        &mut tx,
        &user,
        "company",
        user.company_id,
        "languages_updated",
        serde_json::json!({ "languages": languages, "default_language": default_language }),
    )
    .await?;
    tx.commit().await?;
    Ok(Json(get_company(&state.db, user.company_id).await?))
}

/// `GET /languages` and `PUT /admin/company/languages`.
pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(list_languages))
        .routes(routes!(put_company_languages))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn v(l: &[&str]) -> Vec<String> {
        l.iter().map(|s| s.to_string()).collect()
    }

    #[test]
    fn chain_is_requested_english_default_then_company_order() {
        assert_eq!(
            fallback_chain("pt", "nl", &v(&["nl", "fr", "en", "pt", "it"])),
            v(&["pt", "en", "nl", "fr", "it"])
        );
        assert_eq!(fallback_chain("en", "en", &[]), v(&["en"]));
    }

    #[test]
    fn pick_follows_the_chain_then_takes_anything() {
        let chain = v(&["pt", "en", "nl"]);
        assert_eq!(pick(&["fr", "nl", "pt"], &chain), Some((2, false)));
        assert_eq!(pick(&["fr", "en", "nl"], &chain), Some((1, true)));
        assert_eq!(pick(&["fr", "nl"], &chain), Some((1, true)));
        assert_eq!(pick(&["fr", "de"], &chain), Some((0, true)));
        assert_eq!(pick::<&str>(&[], &chain), None);
    }

    #[test]
    fn company_languages_are_checked() {
        let (l, d) = validate_company_languages(&v(&[" NL", "pt", "sv "]), "PT").unwrap();
        assert_eq!((l, d.as_str()), (v(&["nl", "pt", "sv"]), "pt"));
        for (langs, default) in [
            (v(&[]), "en"),
            (v(&["nl", "xx"]), "nl"),
            (v(&["nl", "nl"]), "nl"),
            (v(&["nl", "fr"]), "de"),
            (v(&["dut"]), "dut"),
        ] {
            assert!(
                validate_company_languages(&langs, default).is_err(),
                "{langs:?} {default}"
            );
        }
    }
}
