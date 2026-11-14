//! Creating a company from nothing (ADR 0047): [`provision`] and the unauthenticated
//! `GET /setup/status` and `POST /setup/bootstrap` endpoints.
//!
//! `provision` writes everything a new company needs to be usable (the company, its first
//! administrator, numbering, a warehouse with locations and the five price zones) inside the
//! caller's transaction. The bootstrap endpoint only works while the database holds no company at
//! all; outside dev authentication it also needs the `BOOTSTRAP_TOKEN` secret.

use axum::extract::State;
use axum::{Extension, Json};
use chrono::Datelike;
use serde::{Deserialize, Serialize};
use sqlx::PgConnection;
use utoipa::ToSchema;
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::auth::{AuthConfig, CurrentUser};
use crate::company::{get_company, Company};
use crate::{audit, is_language, new_id, AppError, AppResult, AppState};

/// Advisory-lock key that serialises provisioning (`pg_advisory_xact_lock`).
const PROVISION_LOCK: i64 = 0x7472_6164_6f63_7266;

/// Per-year document number sequences created for a new company (`KB` is not per year).
const SEQUENCES: [&str; 13] = [
    "opportunity",
    "quotation",
    "order",
    "ticket",
    "repair",
    "job",
    "package",
    "DN",
    "GR",
    "PO",
    "CNT",
    "MO",
    "SC",
];

/// The five price zones every company starts with.
const ZONES: [(&str, &str); 5] = [
    ("Z1", "Zone 1"),
    ("Z2", "Zone 2"),
    ("Z3", "Zone 3"),
    ("Z4", "Zone 4"),
    ("Z5", "Zone 5"),
];

/// Virtual stock locations (the other side of a move), created up front.
const VIRTUAL_LOCATIONS: [&str; 7] = [
    "supplier",
    "customer",
    "production_consumption",
    "production_output",
    "transit",
    "adjustment",
    "scrap",
];

/// The bootstrap secret, read once at start-up.
#[derive(Clone, Default)]
pub struct BootstrapConfig {
    /// `BOOTSTRAP_TOKEN`; `None` when unset or blank.
    pub token: Option<String>,
}

impl std::fmt::Debug for BootstrapConfig {
    /// Never prints the token.
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("BootstrapConfig")
            .field("token", &self.token.as_ref().map(|_| "<set>"))
            .finish()
    }
}

impl BootstrapConfig {
    /// Reads `BOOTSTRAP_TOKEN`; a blank value counts as unset.
    pub fn from_env() -> Self {
        Self::new(std::env::var("BOOTSTRAP_TOKEN").ok())
    }

    /// A config with the given token; blank counts as none.
    pub fn new(token: Option<String>) -> Self {
        Self {
            token: token.filter(|t| !t.trim().is_empty()),
        }
    }
}

/// Everything needed to create a company and its first administrator.
#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct ProvisionSpec {
    /// Trading name; must be unique (case-insensitive).
    pub name: String,
    /// Registered name when it differs from `name`.
    #[serde(default)]
    pub legal_name: Option<String>,
    /// VAT number, for example `BE0123456749`.
    #[serde(default)]
    pub vat_number: Option<String>,
    /// ISO 3166 alpha-2 country code.
    pub country_code: String,
    /// ISO 4217 currency code.
    pub currency: String,
    /// One of nl, fr, en, de, es.
    pub default_language: String,
    /// E-mail of the first administrator (created when no such user exists).
    pub admin_email: String,
    /// Display name of the first administrator.
    pub admin_display_name: String,
}

fn blank(v: &Option<String>) -> Option<String> {
    v.as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_string)
}

/// A plausible e-mail address: one `@`, no spaces, and a domain of non-empty dot-separated labels.
fn valid_email(e: &str) -> bool {
    let Some((local, domain)) = e.split_once('@') else {
        return false;
    };
    e.len() <= 254
        && !e.contains(char::is_whitespace)
        && !local.is_empty()
        && !domain.contains('@')
        && domain.contains('.')
        && domain.split('.').all(|label| !label.is_empty())
}

impl ProvisionSpec {
    /// Checks and normalises the spec: trims text, upper-cases country, currency and VAT number,
    /// lower-cases the e-mail. Errors name the offending field.
    pub fn validate(&self) -> AppResult<ProvisionSpec> {
        let bad = |m: &str| Err(AppError::Validation(m.to_string()));
        let name = self.name.trim().to_string();
        if name.is_empty() || name.chars().count() > 200 {
            return bad("name is required (at most 200 characters)");
        }
        let legal_name = blank(&self.legal_name);
        if legal_name.as_ref().is_some_and(|l| l.chars().count() > 200) {
            return bad("legal_name is at most 200 characters");
        }
        let vat_number =
            blank(&self.vat_number).map(|v| v.replace([' ', '.', '-'], "").to_ascii_uppercase());
        if let Some(v) = &vat_number {
            if !(4..=20).contains(&v.len()) || !v.chars().all(|c| c.is_ascii_alphanumeric()) {
                return bad("vat_number must be 4 to 20 letters and digits");
            }
        }
        let country_code = self.country_code.trim().to_ascii_uppercase();
        if country_code.len() != 2 || !country_code.chars().all(|c| c.is_ascii_alphabetic()) {
            return bad("country_code must be two letters");
        }
        let currency = self.currency.trim().to_ascii_uppercase();
        if currency.len() != 3 || !currency.chars().all(|c| c.is_ascii_alphabetic()) {
            return bad("currency must be three letters");
        }
        let default_language = self.default_language.trim().to_ascii_lowercase();
        if !is_language(&default_language) {
            return bad("default_language must be one of nl, fr, en, de, es");
        }
        let admin_email = self.admin_email.trim().to_ascii_lowercase();
        if !valid_email(&admin_email) {
            return bad("admin_email is not a valid e-mail address");
        }
        let admin_display_name = self.admin_display_name.trim().to_string();
        if admin_display_name.is_empty() || admin_display_name.chars().count() > 200 {
            return bad("admin_display_name is required (at most 200 characters)");
        }
        Ok(ProvisionSpec {
            name,
            legal_name,
            vat_number,
            country_code,
            currency,
            default_language,
            admin_email,
            admin_display_name,
        })
    }
}

/// What [`provision`] created.
#[derive(Debug, Clone)]
pub struct Provisioned {
    /// The new company.
    pub company: Company,
    /// The administrator, acting in the new company.
    pub admin: CurrentUser,
    /// Whether the administrator already existed as a user.
    pub admin_existed: bool,
}

/// Creates a company with everything it needs, using the caller's transaction (the caller
/// commits): the company; the administrator (an existing active user with that e-mail is reused)
/// with a membership holding the role `admin`, the default one when the user has none yet; the
/// numbering sequences of the current year; the warehouse `MAIN` with its location and the
/// virtual locations; price zones Z1-Z5; the baseline item types and attribute definitions of ADR 0068. The first company of an empty database becomes the
/// primary company. Units of measure are global (created by migrations) and
/// VAT is a rate per product, so neither needs rows. Refuses a name another company already has
/// (409).
pub async fn provision(conn: &mut PgConnection, spec: &ProvisionSpec) -> AppResult<Provisioned> {
    let spec = spec.validate()?;
    sqlx::query("SELECT pg_advisory_xact_lock($1)")
        .bind(PROVISION_LOCK)
        .execute(&mut *conn)
        .await?;
    let clash: bool = sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM core.companies WHERE lower(name) = lower($1))",
    )
    .bind(&spec.name)
    .fetch_one(&mut *conn)
    .await?;
    if clash {
        return Err(AppError::Conflict(format!(
            "a company named {:?} already exists",
            spec.name
        )));
    }

    let company_id = new_id();
    // The first company of an empty database is the primary one (the lock above serialises this).
    sqlx::query(
        "INSERT INTO core.companies (id, name, legal_name, vat_number, country_code, currency, default_language, is_primary)
         VALUES ($1, $2, $3, $4, $5, $6, $7, NOT EXISTS (SELECT 1 FROM core.companies))",
    )
    .bind(company_id)
    .bind(&spec.name)
    .bind(spec.legal_name.as_deref().unwrap_or(""))
    .bind(&spec.vat_number)
    .bind(&spec.country_code)
    .bind(&spec.currency)
    .bind(&spec.default_language)
    .execute(&mut *conn)
    .await?;

    let existing: Option<(Uuid, String, String, bool)> = sqlx::query_as(
        "SELECT id, email, display_name, active FROM core.users WHERE lower(email) = lower($1)",
    )
    .bind(&spec.admin_email)
    .fetch_optional(&mut *conn)
    .await?;
    let (user_id, email, display_name, admin_existed) = match existing {
        Some((_, _, _, false)) => {
            return Err(AppError::Conflict(format!(
                "the user {} exists but is deactivated",
                spec.admin_email
            )))
        }
        Some((id, email, name, true)) => (id, email, name, true),
        None => {
            let id = new_id();
            sqlx::query("INSERT INTO core.users (id, email, display_name) VALUES ($1, $2, $3)")
                .bind(id)
                .bind(&spec.admin_email)
                .bind(&spec.admin_display_name)
                .execute(&mut *conn)
                .await?;
            (
                id,
                spec.admin_email.clone(),
                spec.admin_display_name.clone(),
                false,
            )
        }
    };
    sqlx::query(
        "INSERT INTO core.user_companies (user_id, company_id, roles, is_default)
         VALUES ($1, $2, '{admin}',
                 NOT EXISTS (SELECT 1 FROM core.user_companies WHERE user_id = $1 AND is_default))",
    )
    .bind(user_id)
    .bind(company_id)
    .execute(&mut *conn)
    .await?;

    let year = crate::today().year();
    for code in SEQUENCES {
        sqlx::query(
            "INSERT INTO core.number_sequences (company_id, code, year, next_value) VALUES ($1, $2, $3, 1)",
        )
        .bind(company_id)
        .bind(code)
        .bind(year)
        .execute(&mut *conn)
        .await?;
    }
    sqlx::query(
        "INSERT INTO core.number_sequences (company_id, code, year, next_value) VALUES ($1, 'KB', 0, 1)",
    )
    .bind(company_id)
    .execute(&mut *conn)
    .await?;

    let warehouse_id = new_id();
    sqlx::query(
        "INSERT INTO inventory.warehouses (id, company_id, code, name, kind)
         VALUES ($1, $2, 'MAIN', 'Main warehouse', 'warehouse')",
    )
    .bind(warehouse_id)
    .bind(company_id)
    .execute(&mut *conn)
    .await?;
    sqlx::query(
        "INSERT INTO inventory.locations (id, company_id, warehouse_id, code, name)
         VALUES ($1, $2, $3, 'MAIN', 'Main warehouse')",
    )
    .bind(new_id())
    .bind(company_id)
    .bind(warehouse_id)
    .execute(&mut *conn)
    .await?;
    for kind in VIRTUAL_LOCATIONS {
        sqlx::query(
            "INSERT INTO inventory.locations (id, company_id, warehouse_id, code, name, kind)
             VALUES ($1, $2, NULL, $3, $3, $3)",
        )
        .bind(new_id())
        .bind(company_id)
        .bind(kind)
        .execute(&mut *conn)
        .await?;
    }

    for (i, (code, name)) in ZONES.iter().enumerate() {
        sqlx::query(
            "INSERT INTO pricing.price_zones (id, company_id, code, name, sort_order)
             VALUES ($1, $2, $3, $4, $5)",
        )
        .bind(new_id())
        .bind(company_id)
        .bind(code)
        .bind(name)
        .bind(i as i32 + 1)
        .execute(&mut *conn)
        .await?;
    }

    // The baseline item types and attribute definitions every company starts with (ADR 0068); the
    // function is idempotent and defined by migration 20270211000001.
    sqlx::query("SELECT crm.seed_baseline_defaults($1)")
        .bind(company_id)
        .execute(&mut *conn)
        .await?;

    let company = get_company(&mut *conn, company_id).await?;
    Ok(Provisioned {
        company,
        admin: CurrentUser {
            user_id,
            email,
            display_name,
            company_id,
            roles: vec!["admin".to_string()],
            disabled_modules: Vec::new(),
        },
        admin_existed,
    })
}

/// Equality in time that does not depend on where the inputs differ.
fn constant_time_eq(a: &[u8], b: &[u8]) -> bool {
    let mut diff = a.len() ^ b.len();
    for i in 0..a.len().max(b.len()) {
        diff |= usize::from(a.get(i).copied().unwrap_or(0) ^ b.get(i).copied().unwrap_or(0));
    }
    diff == 0
}

fn auth_mode(state: &AppState) -> &'static str {
    match state.auth.as_ref() {
        AuthConfig::Dev { .. } => "dev",
        AuthConfig::Oidc(_) => "oidc",
        AuthConfig::Disabled => "disabled",
    }
}

/// Bootstrapping is always possible in dev mode and, outside it, only with a configured token.
fn enabled(state: &AppState, cfg: &BootstrapConfig) -> bool {
    matches!(state.auth.as_ref(), AuthConfig::Dev { .. }) || cfg.token.is_some()
}

/// Whether this server can be set up, and what the wizard has to ask for.
#[derive(Debug, Serialize, ToSchema)]
pub struct SetupStatus {
    /// True while no company exists and bootstrapping is enabled on this server.
    pub needs_setup: bool,
    /// True when `POST /setup/bootstrap` must carry the `BOOTSTRAP_TOKEN`.
    pub token_required: bool,
    /// `dev` (the admin e-mail becomes the dev user) or `oidc` (sign in through the identity provider).
    pub auth_mode: String,
}

/// `GET /setup/status`: no sign-in needed.
#[utoipa::path(get, path = "/setup/status", tag = "core", security(()),
    responses((status = 200, body = SetupStatus)))]
async fn setup_status(
    State(state): State<AppState>,
    Extension(cfg): Extension<BootstrapConfig>,
) -> AppResult<Json<SetupStatus>> {
    let empty: bool = sqlx::query_scalar("SELECT NOT EXISTS (SELECT 1 FROM core.companies)")
        .fetch_one(&state.db)
        .await?;
    Ok(Json(SetupStatus {
        needs_setup: empty && enabled(&state, &cfg),
        token_required: cfg.token.is_some(),
        auth_mode: auth_mode(&state).to_string(),
    }))
}

/// Body of `POST /setup/bootstrap`: the company spec plus the token, when the server has one.
#[derive(Debug, Deserialize, ToSchema)]
pub struct BootstrapRequest {
    /// The company and its administrator.
    #[serde(flatten)]
    pub spec: ProvisionSpec,
    /// The `BOOTSTRAP_TOKEN`; required whenever the server has one.
    #[serde(default)]
    pub token: Option<String>,
}

/// The first administrator, as created.
#[derive(Debug, Serialize, ToSchema)]
pub struct AdminSummary {
    pub user_id: Uuid,
    pub email: String,
    pub display_name: String,
    pub roles: Vec<String>,
}

/// Result of a successful bootstrap. Contains no secrets.
#[derive(Debug, Serialize, ToSchema)]
pub struct BootstrapResult {
    /// The new company.
    pub company: Company,
    /// Its first administrator.
    pub admin: AdminSummary,
    /// `dev` or `oidc`: how the administrator signs in.
    pub auth_mode: String,
}

/// `POST /setup/bootstrap`: creates the first company of an empty database.
#[utoipa::path(post, path = "/setup/bootstrap", tag = "core", security(()),
    request_body = BootstrapRequest,
    responses(
        (status = 201, body = BootstrapResult),
        (status = 403, description = "token missing or wrong", body = crate::error::ErrorBody),
        (status = 404, description = "bootstrapping is disabled on this server", body = crate::error::ErrorBody),
        (status = 409, description = "a company already exists", body = crate::error::ErrorBody),
        (status = 422, description = "invalid company spec", body = crate::error::ErrorBody),
    ))]
async fn bootstrap(
    State(state): State<AppState>,
    Extension(cfg): Extension<BootstrapConfig>,
    Json(req): Json<BootstrapRequest>,
) -> AppResult<(axum::http::StatusCode, Json<BootstrapResult>)> {
    if !enabled(&state, &cfg) {
        return Err(AppError::NotFound("setup endpoint"));
    }
    if let Some(expected) = &cfg.token {
        let given = req.token.as_deref().unwrap_or("");
        if !constant_time_eq(expected.as_bytes(), given.as_bytes()) {
            return Err(AppError::Forbidden("invalid bootstrap token".into()));
        }
    }
    let spec = req.spec.validate()?;
    let mut tx = state.db.begin().await?;
    // Serialises concurrent calls: the second waits, then sees the first one's company.
    sqlx::query("SELECT pg_advisory_xact_lock($1)")
        .bind(PROVISION_LOCK)
        .execute(&mut *tx)
        .await?;
    let empty: bool = sqlx::query_scalar("SELECT NOT EXISTS (SELECT 1 FROM core.companies)")
        .fetch_one(&mut *tx)
        .await?;
    if !empty {
        return Err(AppError::Conflict(
            "this server is already set up: a company exists".into(),
        ));
    }
    let done = provision(&mut tx, &spec).await?;
    audit::record(
        &mut tx,
        &done.admin,
        "company",
        done.company.id,
        "bootstrapped",
        serde_json::json!({ "name": done.company.name, "admin_email": done.admin.email }),
    )
    .await?;
    tx.commit().await?;
    tracing::info!(company = %done.company.id, "company bootstrapped");
    Ok((
        axum::http::StatusCode::CREATED,
        Json(BootstrapResult {
            company: done.company,
            admin: AdminSummary {
                user_id: done.admin.user_id,
                email: done.admin.email,
                display_name: done.admin.display_name,
                roles: done.admin.roles,
            },
            auth_mode: auth_mode(&state).to_string(),
        }),
    ))
}

/// `GET /setup/status` and `POST /setup/bootstrap`: no sign-in, no company.
pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(setup_status))
        .routes(routes!(bootstrap))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn spec() -> ProvisionSpec {
        ProvisionSpec {
            name: "  Acme BV ".into(),
            legal_name: Some("  ".into()),
            vat_number: Some("be 0123.456.749".into()),
            country_code: "be".into(),
            currency: "eur".into(),
            default_language: "NL".into(),
            admin_email: " Admin@Example.COM ".into(),
            admin_display_name: " Ada ".into(),
        }
    }

    #[test]
    fn normalises_the_spec() {
        let s = spec().validate().unwrap();
        assert_eq!(s.name, "Acme BV");
        assert_eq!(s.legal_name, None);
        assert_eq!(s.vat_number.as_deref(), Some("BE0123456749"));
        assert_eq!(
            (s.country_code.as_str(), s.currency.as_str()),
            ("BE", "EUR")
        );
        assert_eq!(s.default_language, "nl");
        assert_eq!(s.admin_email, "admin@example.com");
        assert_eq!(s.admin_display_name, "Ada");
    }

    #[test]
    fn rejects_bad_fields() {
        type Mutation = Box<dyn Fn(&mut ProvisionSpec)>;
        let cases: Vec<Mutation> = vec![
            Box::new(|s| s.name = "  ".into()),
            Box::new(|s| s.country_code = "BEL".into()),
            Box::new(|s| s.country_code = "B1".into()),
            Box::new(|s| s.currency = "EU".into()),
            Box::new(|s| s.default_language = "xx".into()),
            Box::new(|s| s.vat_number = Some("!!".into())),
            Box::new(|s| s.admin_email = "nobody".into()),
            Box::new(|s| s.admin_email = "a@b".into()),
            Box::new(|s| s.admin_email = "a b@c.de".into()),
            Box::new(|s| s.admin_email = "a@b..de".into()),
            Box::new(|s| s.admin_email = "a@.b.de".into()),
            Box::new(|s| s.admin_email = "a@b.de.".into()),
            Box::new(|s| s.admin_display_name = "".into()),
        ];
        for (i, f) in cases.iter().enumerate() {
            let mut s = spec();
            f(&mut s);
            assert!(
                matches!(s.validate(), Err(AppError::Validation(_))),
                "case {i}"
            );
        }
    }

    #[test]
    fn constant_time_compare() {
        assert!(constant_time_eq(b"secret", b"secret"));
        assert!(!constant_time_eq(b"secret", b"secreT"));
        assert!(!constant_time_eq(b"secret", b"secret2"));
        assert!(!constant_time_eq(b"", b"x"));
    }

    #[test]
    fn config_hides_the_token() {
        let c = BootstrapConfig::new(Some("hunter2".into()));
        assert!(!format!("{c:?}").contains("hunter2"));
        assert!(BootstrapConfig::new(Some("  ".into())).token.is_none());
    }
}
