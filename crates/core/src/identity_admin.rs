//! Administration of the identity providers (ADR 0052) and the public provider list for the
//! sign-in page. Changing providers is changing who may sign in to the whole installation, so it
//! needs `identity.admin` and the admin role in the primary company.

use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::{Extension, Json};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use utoipa::{IntoParams, ToSchema};
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::auth::{preview_binding, CallerIssuer};
use crate::identity::{
    accepted_algorithm, check_token, fetch_provider, normalize_issuer, now_secs, validate_idp_url,
    EmailPolicy, IdpSettings, ProviderConfig, ProviderRow, ProviderSource, ALLOWED_ALGORITHMS,
    PROVIDER_COLUMNS,
};
use crate::{audit, new_id, AppError, AppResult, AppState, CurrentUser, Permission};

type ErrorBody = crate::error::ErrorBody;

/// An identity provider as the admin screen shows it.
#[derive(Debug, Serialize, ToSchema)]
pub struct IdentityProviderInfo {
    /// Database id; absent for the environment provider.
    pub id: Option<Uuid>,
    /// `database` or `env` (read-only emergency fallback from `OIDC_ISSUER`).
    pub source: String,
    /// True for the environment provider: it cannot be changed or deleted here.
    pub read_only: bool,
    /// Display name.
    pub name: String,
    /// Issuer URL (no trailing slash); the token's `iss` selects the provider.
    pub issuer: String,
    /// The audience tokens must carry.
    pub audience: String,
    /// Public client id for the interactive sign-in.
    pub client_id: Option<String>,
    /// Scopes the interactive sign-in asks for.
    pub scopes: String,
    /// Accepted JWS algorithms.
    pub algorithms: Vec<String>,
    /// Claim holding the e-mail address.
    pub email_claim: String,
    /// `require_verified_claim`, `trust_provider_email` or `subject_only`.
    pub email_policy: String,
    /// Boolean claim used by `require_verified_claim`.
    pub verified_claim: String,
    /// When not empty, only these e-mail domains can be bound by e-mail.
    pub allowed_email_domains: Vec<String>,
    /// Whether tokens of this provider are accepted.
    pub enabled: bool,
    /// When the provider was created.
    pub created_at: Option<DateTime<Utc>>,
    /// When it was last changed.
    pub updated_at: Option<DateTime<Utc>>,
}

fn info(cfg: &ProviderConfig, at: Option<(DateTime<Utc>, DateTime<Utc>)>) -> IdentityProviderInfo {
    IdentityProviderInfo {
        id: cfg.id,
        source: cfg.source.as_str().into(),
        read_only: cfg.source == ProviderSource::Env,
        name: cfg.name.clone(),
        issuer: cfg.issuer.clone(),
        audience: cfg.audience.clone(),
        client_id: cfg.client_id.clone(),
        scopes: cfg.scopes.clone(),
        algorithms: cfg.algorithms.clone(),
        email_claim: cfg.email_claim.clone(),
        email_policy: cfg.email_policy.as_str().into(),
        verified_claim: cfg.verified_claim.clone(),
        allowed_email_domains: cfg.allowed_email_domains.clone(),
        enabled: cfg.enabled,
        created_at: at.map(|a| a.0),
        updated_at: at.map(|a| a.1),
    }
}

fn row_info(r: &ProviderRow) -> IdentityProviderInfo {
    info(&r.config(), Some((r.created_at, r.updated_at)))
}

/// The settings of an identity provider. Optional fields take the defaults of the table.
#[derive(Debug, Deserialize, ToSchema)]
pub struct IdentityProviderInput {
    /// Display name.
    pub name: String,
    /// `https://` issuer URL; must serve `/.well-known/openid-configuration`.
    pub issuer: String,
    /// The audience tokens must carry (usually the API's application id).
    pub audience: String,
    /// Public client id for the interactive sign-in; none for a provider used with bearer
    /// tokens only.
    #[serde(default)]
    pub client_id: Option<String>,
    /// Default `openid profile email`.
    #[serde(default)]
    pub scopes: Option<String>,
    /// Subset of RS256, RS384, RS512, ES256, ES384, PS256, PS384, PS512; default all of them.
    #[serde(default)]
    pub algorithms: Option<Vec<String>>,
    /// Default `email`.
    #[serde(default)]
    pub email_claim: Option<String>,
    /// Default `require_verified_claim`.
    #[serde(default)]
    pub email_policy: Option<String>,
    /// Default `email_verified` (Microsoft Entra ID: `xms_edov`).
    #[serde(default)]
    pub verified_claim: Option<String>,
    /// When not empty, only these e-mail domains can be bound by e-mail.
    #[serde(default)]
    pub allowed_email_domains: Option<Vec<String>>,
    /// Default true.
    #[serde(default)]
    pub enabled: Option<bool>,
    /// Acknowledge that this change can lock people out (see the 409 answers).
    #[serde(default)]
    pub confirm_lockout: Option<bool>,
}

fn clean(v: &Option<String>, default: &str) -> String {
    v.as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .unwrap_or(default)
        .to_string()
}

/// Validates the shape of an input (no network) and turns it into a configuration.
fn normalise_input(settings: &IdpSettings, i: &IdentityProviderInput) -> AppResult<ProviderConfig> {
    let bad = |m: String| AppError::Validation(m);
    let name = i.name.trim().to_string();
    if name.is_empty() {
        return Err(bad("name is required".into()));
    }
    let issuer = normalize_issuer(&i.issuer);
    validate_idp_url(settings, &issuer).map_err(|e| bad(format!("issuer: {e}")))?;
    let audience = i.audience.trim().to_string();
    if audience.is_empty() {
        return Err(bad("audience is required".into()));
    }
    let algorithms: Vec<String> = match &i.algorithms {
        Some(a) if !a.is_empty() => {
            let mut out: Vec<String> = vec![];
            for x in a {
                let x = x.trim().to_string();
                if !ALLOWED_ALGORITHMS.contains(&x.as_str()) {
                    return Err(bad(format!(
                        "algorithm {x} is not allowed (use {})",
                        ALLOWED_ALGORITHMS.join(", ")
                    )));
                }
                if !out.contains(&x) {
                    out.push(x);
                }
            }
            out
        }
        _ => ALLOWED_ALGORITHMS.iter().map(|s| s.to_string()).collect(),
    };
    let policy = clean(&i.email_policy, "require_verified_claim");
    let email_policy = EmailPolicy::parse(&policy).ok_or_else(|| {
        bad(format!(
            "email_policy must be one of {}",
            EmailPolicy::ALL.join(", ")
        ))
    })?;
    let mut domains: Vec<String> = vec![];
    for d in i.allowed_email_domains.iter().flatten() {
        let d = d.trim().trim_start_matches('@').to_lowercase();
        if d.is_empty() || d.contains(|c: char| c.is_whitespace() || c == '@') {
            return Err(bad(format!("{d:?} is not a domain")));
        }
        if !domains.contains(&d) {
            domains.push(d);
        }
    }
    Ok(ProviderConfig {
        id: None,
        source: ProviderSource::Database,
        name,
        issuer,
        audience,
        client_id: i
            .client_id
            .as_deref()
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .map(str::to_string),
        scopes: clean(&i.scopes, "openid profile email"),
        algorithms,
        email_claim: clean(&i.email_claim, "email"),
        email_policy,
        verified_claim: clean(&i.verified_claim, "email_verified"),
        allowed_email_domains: domains,
        enabled: i.enabled.unwrap_or(true),
    })
}

/// Whether the user is an active administrator of the installation's primary company (the one
/// flagged `is_primary`; the oldest company when none is, which a migration prevents).
async fn is_primary_admin(state: &AppState, user: &CurrentUser) -> AppResult<bool> {
    Ok(sqlx::query_scalar(
        "SELECT EXISTS (
            SELECT 1 FROM core.user_companies uc
            WHERE uc.user_id = $1 AND uc.active AND 'admin' = ANY(uc.roles)
              AND uc.company_id = (SELECT id FROM core.companies
                                   ORDER BY is_primary DESC, created_at, id LIMIT 1))",
    )
    .bind(user.user_id)
    .fetch_one(&state.db)
    .await?)
}

const NOT_PRIMARY_ADMIN: &str =
    "identity providers are managed by an administrator of the installation's primary company";

/// `identity.admin` plus the admin role in the primary company: an administrator of any company
/// would otherwise be a global administrator of the installation.
async fn guard(state: &AppState, user: &CurrentUser) -> AppResult<()> {
    user.require(Permission::IdentityAdmin)?;
    if is_primary_admin(state, user).await? {
        Ok(())
    } else {
        Err(AppError::Forbidden(NOT_PRIMARY_ADMIN.into()))
    }
}

fn env_provider(state: &AppState) -> Option<&ProviderConfig> {
    match state.auth.as_ref() {
        crate::auth::AuthConfig::Oidc(p) => p.env_provider(),
        _ => None,
    }
}

async fn reload(state: &AppState) {
    if let crate::auth::AuthConfig::Oidc(p) = state.auth.as_ref() {
        if let Err(e) = p.reload(&state.db).await {
            tracing::warn!(error = %e, "reloading identity providers failed");
        }
    }
}

/// Fetches discovery and keys of a configuration and turns every failure into a 422 reason.
async fn probe(settings: &IdpSettings, cfg: &ProviderConfig) -> AppResult<()> {
    let f = fetch_provider(settings, &cfg.issuer)
        .await
        .map_err(|e| AppError::Validation(format!("cannot read the identity provider: {e}")))?;
    if !f.issuer_match {
        return Err(AppError::Validation(format!(
            "the discovery document names the issuer {:?}, not {:?}",
            f.discovery_issuer, cfg.issuer
        )));
    }
    if f.keys.is_empty() {
        return Err(AppError::Validation(
            "the identity provider publishes no usable signing keys".into(),
        ));
    }
    Ok(())
}

/// The identity providers: the database ones and, read-only, the one from the environment.
#[utoipa::path(get, path = "/admin/identity-providers", tag = "admin",
    responses((status = 200, body = Vec<IdentityProviderInfo>), (status = 403, body = ErrorBody)))]
async fn list_providers(
    State(state): State<AppState>,
    user: CurrentUser,
) -> AppResult<Json<Vec<IdentityProviderInfo>>> {
    guard(&state, &user).await?;
    let rows: Vec<ProviderRow> = sqlx::query_as(&format!(
        "SELECT {PROVIDER_COLUMNS} FROM core.identity_providers ORDER BY created_at, id"
    ))
    .fetch_all(&state.db)
    .await?;
    let mut out: Vec<IdentityProviderInfo> = env_provider(&state)
        .map(|c| info(c, None))
        .into_iter()
        .collect();
    out.extend(rows.iter().map(row_info));
    Ok(Json(out))
}

/// Adds an identity provider. Discovery and signing keys must be readable and the discovery
/// issuer must match, or the answer is 422 with the reason.
#[utoipa::path(post, path = "/admin/identity-providers", tag = "admin",
    request_body = IdentityProviderInput,
    responses((status = 201, body = IdentityProviderInfo), (status = 403, body = ErrorBody),
              (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn create_provider(
    State(state): State<AppState>,
    Extension(settings): Extension<IdpSettings>,
    user: CurrentUser,
    Json(input): Json<IdentityProviderInput>,
) -> AppResult<(StatusCode, Json<IdentityProviderInfo>)> {
    guard(&state, &user).await?;
    let cfg = normalise_input(&settings, &input)?;
    if env_provider(&state).is_some_and(|e| e.issuer == cfg.issuer) {
        return Err(AppError::Conflict(
            "this issuer is already configured through OIDC_ISSUER".into(),
        ));
    }
    probe(&settings, &cfg).await?;
    let id = new_id();
    let mut tx = state.db.begin().await?;
    let row: ProviderRow = sqlx::query_as(&format!(
        "INSERT INTO core.identity_providers (id, name, issuer, audience, client_id, scopes, algorithms,
             email_claim, email_policy, verified_claim, allowed_email_domains, enabled, created_by)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13) RETURNING {PROVIDER_COLUMNS}"
    ))
    .bind(id)
    .bind(&cfg.name)
    .bind(&cfg.issuer)
    .bind(&cfg.audience)
    .bind(&cfg.client_id)
    .bind(&cfg.scopes)
    .bind(&cfg.algorithms)
    .bind(&cfg.email_claim)
    .bind(cfg.email_policy.as_str())
    .bind(&cfg.verified_claim)
    .bind(&cfg.allowed_email_domains)
    .bind(cfg.enabled)
    .bind(user.user_id)
    .fetch_one(&mut *tx)
    .await?;
    audit::record(
        &mut tx,
        &user,
        "identity_provider",
        id,
        "created",
        serde_json::to_value(row_info(&row)).unwrap_or_default(),
    )
    .await?;
    tx.commit().await?;
    reload(&state).await;
    Ok((StatusCode::CREATED, Json(row_info(&row))))
}

/// Serialises changes that can take an enabled provider out of use (held until the transaction ends).
async fn lock_providers(conn: &mut sqlx::PgConnection) -> AppResult<()> {
    sqlx::query("SELECT pg_advisory_xact_lock($1)")
        .bind(IDENTITY_PROVIDERS_LOCK)
        .execute(conn)
        .await?;
    Ok(())
}

/// Advisory-lock key of identity provider lock-out checks.
const IDENTITY_PROVIDERS_LOCK: i64 = 0x1D3_0052;

async fn load(state: &AppState, id: Uuid) -> AppResult<ProviderRow> {
    sqlx::query_as(&format!(
        "SELECT {PROVIDER_COLUMNS} FROM core.identity_providers WHERE id = $1"
    ))
    .bind(id)
    .fetch_optional(&state.db)
    .await?
    .ok_or(AppError::NotFound("identity provider"))
}

/// Refuses a change that takes an enabled issuer out of use when that could lock everybody out
/// (the last provider, with no environment fallback) or the caller out (their own provider),
/// unless `confirm` is set. `new_enabled` is none for a delete. Must run in the transaction that
/// holds [`lock_providers`] and makes the change, so concurrent changes cannot both pass on stale counts.
async fn lockout_guard(
    conn: &mut sqlx::PgConnection,
    state: &AppState,
    caller: &CallerIssuer,
    existing: &ProviderRow,
    new_enabled: Option<bool>,
    new_issuer: Option<&str>,
    confirm: bool,
) -> AppResult<()> {
    let still = new_enabled == Some(true);
    let loses_issuer =
        existing.enabled && (!still || new_issuer.is_some_and(|i| i != existing.issuer));
    if !loses_issuer || confirm {
        return Ok(());
    }
    let others: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM core.identity_providers WHERE enabled AND id <> $1",
    )
    .bind(existing.id)
    .fetch_one(&mut *conn)
    .await?;
    let remaining = others + i64::from(still);
    if remaining == 0 && env_provider(state).is_none() {
        return Err(AppError::ConflictCode(
            "last_identity_provider",
            "this is the last enabled identity provider and there is no OIDC_ISSUER fallback: nobody could sign in. Repeat with confirm_lockout to proceed".into(),
        ));
    }
    if caller.0.as_deref() == Some(existing.issuer.as_str()) {
        return Err(AppError::ConflictCode(
            "own_identity_provider",
            "you are signed in through this provider. Repeat with confirm_lockout to proceed"
                .into(),
        ));
    }
    Ok(())
}

/// Replaces the settings of an identity provider. Enabled providers are probed like on create.
/// Disabling it or changing its issuer is refused (409) when it is the last provider or the
/// caller's own, unless `confirm_lockout` is true.
#[utoipa::path(put, path = "/admin/identity-providers/{id}", tag = "admin",
    params(("id" = Uuid, Path)), request_body = IdentityProviderInput,
    responses((status = 200, body = IdentityProviderInfo), (status = 403, body = ErrorBody),
              (status = 404, body = ErrorBody), (status = 409, body = ErrorBody),
              (status = 422, body = ErrorBody)))]
async fn update_provider(
    State(state): State<AppState>,
    Extension(settings): Extension<IdpSettings>,
    user: CurrentUser,
    caller: CallerIssuer,
    Path(id): Path<Uuid>,
    Json(input): Json<IdentityProviderInput>,
) -> AppResult<Json<IdentityProviderInfo>> {
    guard(&state, &user).await?;
    let cfg = normalise_input(&settings, &input)?;
    if env_provider(&state).is_some_and(|e| e.issuer == cfg.issuer) {
        return Err(AppError::Conflict(
            "this issuer is already configured through OIDC_ISSUER".into(),
        ));
    }
    if cfg.enabled {
        probe(&settings, &cfg).await?;
    }
    let mut tx = state.db.begin().await?;
    lock_providers(&mut tx).await?;
    // Re-read under the lock: the guard must see the committed state.
    let existing: ProviderRow = sqlx::query_as(&format!(
        "SELECT {PROVIDER_COLUMNS} FROM core.identity_providers WHERE id = $1"
    ))
    .bind(id)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or(AppError::NotFound("identity provider"))?;
    lockout_guard(
        &mut tx,
        &state,
        &caller,
        &existing,
        Some(cfg.enabled),
        Some(&cfg.issuer),
        input.confirm_lockout.unwrap_or(false),
    )
    .await?;
    let row: ProviderRow = sqlx::query_as(&format!(
        "UPDATE core.identity_providers SET name=$2, issuer=$3, audience=$4, client_id=$5, scopes=$6,
             algorithms=$7, email_claim=$8, email_policy=$9, verified_claim=$10,
             allowed_email_domains=$11, enabled=$12, updated_at=now()
         WHERE id=$1 RETURNING {PROVIDER_COLUMNS}"
    ))
    .bind(id)
    .bind(&cfg.name)
    .bind(&cfg.issuer)
    .bind(&cfg.audience)
    .bind(&cfg.client_id)
    .bind(&cfg.scopes)
    .bind(&cfg.algorithms)
    .bind(&cfg.email_claim)
    .bind(cfg.email_policy.as_str())
    .bind(&cfg.verified_claim)
    .bind(&cfg.allowed_email_domains)
    .bind(cfg.enabled)
    .fetch_one(&mut *tx)
    .await?;
    audit::record(
        &mut tx,
        &user,
        "identity_provider",
        id,
        "updated",
        serde_json::json!({
            "before": serde_json::to_value(row_info(&existing)).unwrap_or_default(),
            "after": serde_json::to_value(row_info(&row)).unwrap_or_default(),
            "confirm_lockout": input.confirm_lockout.unwrap_or(false),
        }),
    )
    .await?;
    tx.commit().await?;
    reload(&state).await;
    Ok(Json(row_info(&row)))
}

/// Query of a delete.
#[derive(Debug, Deserialize, IntoParams)]
pub struct DeleteQuery {
    /// Acknowledge that deleting can lock people out.
    #[serde(default)]
    pub confirm_lockout: Option<bool>,
}

/// Deletes an identity provider; refused (409) for the last provider without an environment
/// fallback and for the caller's own provider, unless `confirm_lockout=true`. The environment
/// provider cannot be deleted (it is not a database row: 404).
#[utoipa::path(delete, path = "/admin/identity-providers/{id}", tag = "admin",
    params(("id" = Uuid, Path), DeleteQuery),
    responses((status = 204), (status = 403, body = ErrorBody), (status = 404, body = ErrorBody),
              (status = 409, body = ErrorBody)))]
async fn delete_provider(
    State(state): State<AppState>,
    user: CurrentUser,
    caller: CallerIssuer,
    Path(id): Path<Uuid>,
    Query(q): Query<DeleteQuery>,
) -> AppResult<StatusCode> {
    guard(&state, &user).await?;
    let mut tx = state.db.begin().await?;
    lock_providers(&mut tx).await?;
    let existing: ProviderRow = sqlx::query_as(&format!(
        "SELECT {PROVIDER_COLUMNS} FROM core.identity_providers WHERE id = $1"
    ))
    .bind(id)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or(AppError::NotFound("identity provider"))?;
    lockout_guard(
        &mut tx,
        &state,
        &caller,
        &existing,
        None,
        None,
        q.confirm_lockout.unwrap_or(false),
    )
    .await?;
    sqlx::query("DELETE FROM core.identity_providers WHERE id = $1")
        .bind(id)
        .execute(&mut *tx)
        .await?;
    audit::record(
        &mut tx,
        &user,
        "identity_provider",
        id,
        "deleted",
        serde_json::json!({
            "before": serde_json::to_value(row_info(&existing)).unwrap_or_default(),
            "confirm_lockout": q.confirm_lockout.unwrap_or(false),
        }),
    )
    .await?;
    tx.commit().await?;
    reload(&state).await;
    Ok(StatusCode::NO_CONTENT)
}

/// A draft configuration (or an existing provider) and optionally a token to try it with.
#[derive(Debug, Deserialize, ToSchema)]
pub struct IdentityProviderTest {
    /// An existing provider to test; ignored when `config` is given.
    #[serde(default)]
    pub id: Option<Uuid>,
    /// A draft configuration to test.
    #[serde(default)]
    pub config: Option<IdentityProviderInput>,
    /// An access token of this provider. It is checked and discarded: never stored or logged.
    #[serde(default)]
    pub sample_token: Option<String>,
}

/// What signing in with the sample token would do.
#[derive(Debug, Serialize, ToSchema)]
pub struct BindingResult {
    /// `existing_subject`, `would_bind` or `refused`.
    pub outcome: String,
    /// The user it resolves to.
    pub user_id: Option<Uuid>,
    /// That user's e-mail address.
    pub user_email: Option<String>,
    /// Why it is refused.
    pub reason: Option<String>,
}

/// The result of checking a sample token.
#[derive(Debug, Serialize, ToSchema)]
pub struct TokenTestResult {
    /// All checks passed.
    pub valid: bool,
    /// The signature verified with a published key.
    pub signature_ok: bool,
    /// `iss` equals the configured issuer.
    pub issuer_ok: Option<bool>,
    /// `aud` contains the configured audience.
    pub audience_ok: Option<bool>,
    /// `exp` is in the future.
    pub expiry_ok: Option<bool>,
    /// `nbf` is not in the future.
    pub not_before_ok: Option<bool>,
    /// Why the token is not valid.
    pub reason: Option<String>,
    /// The token's subject.
    pub subject: Option<String>,
    /// The e-mail address found in the configured e-mail claim.
    pub email: Option<String>,
    /// The value of the configured verification claim, read as a boolean.
    pub email_verified: Option<bool>,
    /// What a sign-in would do; only for a valid token.
    pub binding: Option<BindingResult>,
}

/// The outcome of testing a provider configuration.
#[derive(Debug, Serialize, ToSchema)]
pub struct IdentityProviderTestResult {
    /// Discovery document and keys could be read.
    pub discovery_reachable: bool,
    /// The discovery `issuer` equals the configured issuer.
    pub issuer_match: bool,
    /// The issuer the discovery document names.
    pub discovery_issuer: Option<String>,
    /// Number of keys in the JWKS.
    pub key_count: i64,
    /// Algorithms (or key types) of the published keys.
    pub key_algorithms: Vec<String>,
    /// `claims_supported` if the provider advertises it.
    pub claims_supported: Option<Vec<String>>,
    /// Why the provider could not be read.
    pub error: Option<String>,
    /// The result for the sample token, if one was given.
    pub token: Option<TokenTestResult>,
}

/// Tries a configuration without saving anything: reads discovery and keys and, with a sample
/// token, checks it and shows how its claims map to a user, without binding or storing anything.
#[utoipa::path(post, path = "/admin/identity-providers/test", tag = "admin",
    request_body = IdentityProviderTest,
    responses((status = 200, body = IdentityProviderTestResult), (status = 403, body = ErrorBody),
              (status = 404, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn test_provider(
    State(state): State<AppState>,
    Extension(settings): Extension<IdpSettings>,
    user: CurrentUser,
    Json(input): Json<IdentityProviderTest>,
) -> AppResult<Json<IdentityProviderTestResult>> {
    guard(&state, &user).await?;
    let cfg = match (&input.config, input.id) {
        (Some(c), _) => normalise_input(&settings, c)?,
        (None, Some(id)) => load(&state, id).await?.config(),
        (None, None) => {
            return Err(AppError::Validation("give an id or a config".into()));
        }
    };
    let mut out = IdentityProviderTestResult {
        discovery_reachable: false,
        issuer_match: false,
        discovery_issuer: None,
        key_count: 0,
        key_algorithms: vec![],
        claims_supported: None,
        error: None,
        token: None,
    };
    let fetched = match fetch_provider(&settings, &cfg.issuer).await {
        Ok(f) => f,
        Err(e) => {
            out.error = Some(e);
            return Ok(Json(out));
        }
    };
    out.discovery_reachable = true;
    out.issuer_match = fetched.issuer_match;
    out.discovery_issuer = Some(fetched.discovery_issuer.clone());
    out.claims_supported = fetched.claims_supported.clone();
    out.key_count = fetched.key_infos.len() as i64;
    let mut algs: Vec<String> = fetched
        .key_infos
        .iter()
        .map(|k| k.alg.clone().unwrap_or_else(|| k.kty.clone()))
        .collect();
    algs.sort();
    algs.dedup();
    out.key_algorithms = algs;
    if !fetched.issuer_match {
        out.error = Some(format!(
            "the discovery document names the issuer {:?}, not {:?}",
            fetched.discovery_issuer, cfg.issuer
        ));
        return Ok(Json(out));
    }
    if let Some(token) = input
        .sample_token
        .as_deref()
        .map(str::trim)
        .filter(|t| !t.is_empty())
    {
        let mut t = TokenTestResult {
            valid: false,
            signature_ok: false,
            issuer_ok: None,
            audience_ok: None,
            expiry_ok: None,
            not_before_ok: None,
            reason: None,
            subject: None,
            email: None,
            email_verified: None,
            binding: None,
        };
        match accepted_algorithm(&cfg, token) {
            None => {
                t.reason = Some("the token's algorithm is not accepted by this provider".into())
            }
            Some((_, None)) => t.reason = Some("the token has no kid".into()),
            Some((alg, Some(kid))) => match fetched.keys.get(&kid) {
                None => t.reason = Some(format!("the provider publishes no key {kid:?}")),
                Some(key) => {
                    let c = check_token(&cfg, key, alg, token, now_secs());
                    t.valid = c.is_valid();
                    t.signature_ok = c.signature_ok;
                    t.issuer_ok = c.issuer_ok;
                    t.audience_ok = c.audience_ok;
                    t.expiry_ok = c.expiry_ok;
                    t.not_before_ok = c.not_before_ok;
                    t.reason = c.reason.clone();
                    if let Some(claims) = &c.claims {
                        t.subject = Some(claims.sub.clone());
                        t.email = claims.email(&cfg);
                        t.email_verified = claims.verified(&cfg);
                        if c.is_valid() {
                            let b = preview_binding(&state, &cfg, claims).await?;
                            t.binding = Some(BindingResult {
                                outcome: b.outcome.into(),
                                user_id: b.user_id,
                                user_email: b.user_email,
                                reason: b.reason,
                            });
                        }
                    }
                }
            },
        }
        out.token = Some(t);
    }
    Ok(Json(out))
}

/// The settings of the user's identity: the issuer-qualified subject to set, or none to clear it.
#[derive(Debug, Deserialize, ToSchema)]
pub struct OidcSubjectInput {
    /// Issuer of a configured database provider.
    #[serde(default)]
    pub issuer: Option<String>,
    /// The `sub` the provider uses for this person; none clears the binding.
    #[serde(default)]
    pub subject: Option<String>,
}

/// Sets or clears the identity a user signs in with, for providers with the `subject_only`
/// policy. The value stored is `<issuer>|<subject>`.
#[utoipa::path(put, path = "/admin/users/{id}/oidc-subject", tag = "admin",
    params(("id" = Uuid, Path)), request_body = OidcSubjectInput,
    responses((status = 204), (status = 403, body = ErrorBody), (status = 404, body = ErrorBody),
              (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn set_oidc_subject(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<OidcSubjectInput>,
) -> AppResult<StatusCode> {
    guard(&state, &user).await?;
    let value = match input
        .subject
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
    {
        None => None,
        Some(sub) => {
            let issuer = normalize_issuer(input.issuer.as_deref().unwrap_or_default());
            let known: bool = sqlx::query_scalar(
                "SELECT EXISTS (SELECT 1 FROM core.identity_providers WHERE issuer = $1)",
            )
            .bind(&issuer)
            .fetch_one(&state.db)
            .await?;
            if !known {
                return Err(AppError::Validation(
                    "issuer is not a configured identity provider".into(),
                ));
            }
            Some(format!("{issuer}|{sub}"))
        }
    };
    let mut tx = state.db.begin().await?;
    let done = sqlx::query("UPDATE core.users SET oidc_subject = $2 WHERE id = $1")
        .bind(id)
        .bind(&value)
        .execute(&mut *tx)
        .await?;
    if done.rows_affected() == 0 {
        return Err(AppError::NotFound("user"));
    }
    audit::record(
        &mut tx,
        &user,
        "user",
        id,
        if value.is_some() {
            "oidc_subject_set"
        } else {
            "oidc_subject_cleared"
        },
        serde_json::json!({ "oidc_subject": value }),
    )
    .await?;
    tx.commit().await?;
    Ok(StatusCode::NO_CONTENT)
}

/// What the sign-in page needs to know about an enabled provider.
#[derive(Debug, Serialize, ToSchema)]
pub struct PublicProvider {
    /// Display name.
    pub name: String,
    /// Issuer URL.
    pub issuer: String,
    /// Public client id of the interactive sign-in.
    pub client_id: Option<String>,
    /// Scopes to ask for.
    pub scopes: String,
    /// `database` or `env` (the read-only fallback from `OIDC_ISSUER`), so the page can label it.
    pub source: String,
}

/// The enabled identity providers, for the sign-in page. No sign-in needed; only these five
/// fields are exposed. Empty in dev mode.
#[utoipa::path(get, path = "/auth/providers", tag = "core", security(()),
    responses((status = 200, body = Vec<PublicProvider>)))]
async fn public_providers(State(state): State<AppState>) -> Json<Vec<PublicProvider>> {
    let list = match state.auth.as_ref() {
        crate::auth::AuthConfig::Oidc(p) => p
            .enabled()
            .iter()
            .map(|c| PublicProvider {
                name: c.name.clone(),
                issuer: c.issuer.clone(),
                client_id: c.client_id.clone(),
                scopes: c.scopes.clone(),
                source: c.source.as_str().to_string(),
            })
            .collect(),
        _ => vec![],
    };
    Json(list)
}

/// The company that was made primary.
#[derive(Debug, Serialize, ToSchema)]
pub struct MakePrimaryResult {
    /// The new primary company.
    pub company_id: Uuid,
    /// Its name.
    pub name: String,
}

/// Makes a company the installation's primary company (the one whose administrators manage the
/// identity providers). Only an active administrator of the current primary company may do this;
/// the flag moves in one transaction, so there is always exactly one primary company.
#[utoipa::path(post, path = "/admin/companies/{id}/make-primary", tag = "admin",
    params(("id" = Uuid, Path)),
    responses((status = 200, body = MakePrimaryResult), (status = 403, body = ErrorBody),
              (status = 404, body = ErrorBody), (status = 409, body = ErrorBody)))]
async fn make_primary(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<MakePrimaryResult>> {
    guard(&state, &user).await?;
    let mut tx = state.db.begin().await?;
    // Serialise swaps by locking the current primary row first.
    let current: Option<Uuid> =
        sqlx::query_scalar("SELECT id FROM core.companies WHERE is_primary FOR UPDATE")
            .fetch_optional(&mut *tx)
            .await?;
    // The guard above read the flag before the lock; a concurrent swap may have committed since.
    // This statement runs after the lock and reads the committed flag through the transaction.
    let still: bool = sqlx::query_scalar(
        "SELECT EXISTS (
            SELECT 1 FROM core.user_companies uc
            JOIN core.companies c ON c.id = uc.company_id
            WHERE uc.user_id = $1 AND uc.active AND 'admin' = ANY(uc.roles) AND c.is_primary)",
    )
    .bind(user.user_id)
    .fetch_one(&mut *tx)
    .await?;
    if !still {
        return Err(AppError::Forbidden(NOT_PRIMARY_ADMIN.into()));
    }
    let target: Option<(Uuid, String)> =
        sqlx::query_as("SELECT id, name FROM core.companies WHERE id = $1 FOR UPDATE")
            .bind(id)
            .fetch_optional(&mut *tx)
            .await?;
    let (_, name) = target.ok_or(AppError::NotFound("company"))?;
    if current == Some(id) {
        return Err(AppError::Conflict(
            "this company is already the primary company".into(),
        ));
    }
    sqlx::query("UPDATE core.companies SET is_primary = false WHERE is_primary")
        .execute(&mut *tx)
        .await?;
    sqlx::query("UPDATE core.companies SET is_primary = true WHERE id = $1")
        .bind(id)
        .execute(&mut *tx)
        .await?;
    audit::record(
        &mut tx,
        &user,
        "company",
        id,
        "made_primary",
        serde_json::json!({ "previous": current, "name": name }),
    )
    .await?;
    tx.commit().await?;
    Ok(Json(MakePrimaryResult {
        company_id: id,
        name,
    }))
}

/// Routes of the identity provider administration and the public provider list.
pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(list_providers, create_provider))
        .routes(routes!(update_provider, delete_provider))
        .routes(routes!(test_provider))
        .routes(routes!(set_oidc_subject))
        .routes(routes!(public_providers))
        .routes(routes!(make_primary))
}
