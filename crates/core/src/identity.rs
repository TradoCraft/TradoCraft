//! Identity providers (ADR 0055): the registry of OpenID Connect providers, the hardened token
//! verifier and the rules for URLs an administrator supplies.
//!
//! A token is verified before the company is known, so providers belong to the installation. The
//! provider is chosen by the token's (still unverified) `iss`; the signature is then checked with
//! that provider's keys only.

use std::collections::HashMap;
use std::net::{IpAddr, Ipv4Addr, Ipv6Addr};
use std::sync::{Arc, RwLock};
use std::time::{Duration, Instant};

use base64::Engine;
use jsonwebtoken::{decode, decode_header, Algorithm, DecodingKey, Validation};
use serde_json::{Map, Value};
use sqlx::PgPool;
use uuid::Uuid;

use crate::AppError;

/// The JWS algorithms a provider may accept. HS* (shared secrets) and `none` never are.
pub const ALLOWED_ALGORITHMS: [&str; 8] = [
    "RS256", "RS384", "RS512", "ES256", "ES384", "PS256", "PS384", "PS512",
];

/// Largest discovery document or JWKS the API reads.
pub const MAX_RESPONSE_BYTES: usize = 1024 * 1024;

/// Clock skew allowed when checking `exp` and `nbf`.
pub const LEEWAY_SECS: i64 = 60;

/// Tunables of the identity provider machinery.
#[derive(Debug, Clone)]
pub struct IdpSettings {
    /// Allow `http` URLs and private, loopback or link-local addresses (`ALLOW_INSECURE_IDP_URLS`).
    /// For local development and tests only; the API refuses it on a reachable server.
    pub allow_insecure_urls: bool,
    /// How long fetched signing keys are used before they are fetched again.
    pub jwks_ttl: Duration,
    /// Minimum time between two fetches of one provider's keys.
    pub refresh_throttle: Duration,
}

impl Default for IdpSettings {
    fn default() -> Self {
        Self {
            allow_insecure_urls: false,
            jwks_ttl: Duration::from_secs(3600),
            refresh_throttle: Duration::from_secs(30),
        }
    }
}

/// How the e-mail address of a token may be used to bind it to an existing user.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EmailPolicy {
    /// The token must carry the provider's "e-mail verified" claim as true.
    RequireVerifiedClaim,
    /// The provider's e-mail is trusted without a verification claim.
    TrustProviderEmail,
    /// Never bind by e-mail: only users whose subject is already set can sign in.
    SubjectOnly,
}

impl EmailPolicy {
    /// All policy codes, as stored in the database.
    pub const ALL: [&'static str; 3] = [
        "require_verified_claim",
        "trust_provider_email",
        "subject_only",
    ];

    /// The stored code.
    pub fn as_str(self) -> &'static str {
        match self {
            EmailPolicy::RequireVerifiedClaim => "require_verified_claim",
            EmailPolicy::TrustProviderEmail => "trust_provider_email",
            EmailPolicy::SubjectOnly => "subject_only",
        }
    }

    /// Parses a stored code.
    pub fn parse(s: &str) -> Option<Self> {
        match s {
            "require_verified_claim" => Some(EmailPolicy::RequireVerifiedClaim),
            "trust_provider_email" => Some(EmailPolicy::TrustProviderEmail),
            "subject_only" => Some(EmailPolicy::SubjectOnly),
            _ => None,
        }
    }
}

/// Which token the interactive sign-in sends as the bearer token. The server verifies both the
/// same way (signature, issuer, audience); this only tells the client what to send.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TokenUse {
    /// The OpenID Connect ID token (`aud` = client id).
    IdToken,
    /// The access token (`aud` = the API, e.g. Microsoft Entra ID).
    AccessToken,
}

impl TokenUse {
    /// All codes, as stored in the database.
    pub const ALL: [&'static str; 2] = ["id_token", "access_token"];

    /// The stored code.
    pub fn as_str(self) -> &'static str {
        match self {
            TokenUse::IdToken => "id_token",
            TokenUse::AccessToken => "access_token",
        }
    }

    /// Parses a stored code.
    pub fn parse(s: &str) -> Option<Self> {
        match s {
            "id_token" => Some(TokenUse::IdToken),
            "access_token" => Some(TokenUse::AccessToken),
            _ => None,
        }
    }
}

/// Where a provider's configuration comes from.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProviderSource {
    /// `OIDC_ISSUER` / `OIDC_AUDIENCE`: read-only emergency fallback.
    Env,
    /// A row of `core.identity_providers`.
    Database,
}

impl ProviderSource {
    /// `env` or `database`.
    pub fn as_str(self) -> &'static str {
        match self {
            ProviderSource::Env => "env",
            ProviderSource::Database => "database",
        }
    }
}

/// One identity provider's settings.
#[derive(Debug, Clone, PartialEq)]
pub struct ProviderConfig {
    /// Database id; none for the environment provider.
    pub id: Option<Uuid>,
    /// Where this configuration comes from.
    pub source: ProviderSource,
    /// Display name.
    pub name: String,
    /// Normalised issuer URL (no trailing slash).
    pub issuer: String,
    /// The `aud` the API requires.
    pub audience: String,
    /// Public client id for the interactive sign-in.
    pub client_id: Option<String>,
    /// Scopes the interactive sign-in asks for.
    pub scopes: String,
    /// Which token the interactive sign-in sends.
    pub token_use: TokenUse,
    /// Accepted JWS algorithms.
    pub algorithms: Vec<String>,
    /// Claim holding the e-mail address.
    pub email_claim: String,
    /// How the e-mail may be used for binding.
    pub email_policy: EmailPolicy,
    /// Boolean claim used by `require_verified_claim`.
    pub verified_claim: String,
    /// When not empty, only these e-mail domains can be bound by e-mail.
    pub allowed_email_domains: Vec<String>,
    /// Whether tokens of this provider are accepted.
    pub enabled: bool,
}

impl ProviderConfig {
    /// The read-only provider built from `OIDC_ISSUER` and `OIDC_AUDIENCE`.
    pub fn from_env(issuer: &str, audience: &str) -> Self {
        Self {
            id: None,
            source: ProviderSource::Env,
            name: "Environment (OIDC_ISSUER)".into(),
            issuer: normalize_issuer(issuer),
            audience: audience.trim().to_string(),
            client_id: None,
            scopes: "openid profile email".into(),
            token_use: TokenUse::IdToken,
            algorithms: ALLOWED_ALGORITHMS.iter().map(|s| s.to_string()).collect(),
            email_claim: "email".into(),
            email_policy: EmailPolicy::RequireVerifiedClaim,
            verified_claim: "email_verified".into(),
            allowed_email_domains: vec![],
            enabled: true,
        }
    }

    /// Sets the public client id and the scopes the interactive sign-in uses for this provider
    /// (`OIDC_CLIENT_ID`, `OIDC_SCOPES` of the environment provider). Blank values keep the
    /// defaults (no client id, `openid profile email`).
    pub fn with_client(mut self, client_id: Option<&str>, scopes: Option<&str>) -> Self {
        self.client_id = client_id
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .map(String::from);
        if let Some(s) = scopes.map(str::trim).filter(|s| !s.is_empty()) {
            self.scopes = s.to_string();
        }
        self
    }
}

#[derive(sqlx::FromRow)]
pub(crate) struct ProviderRow {
    pub id: Uuid,
    pub name: String,
    pub issuer: String,
    pub audience: String,
    pub client_id: Option<String>,
    pub scopes: String,
    pub token_use: String,
    pub algorithms: Vec<String>,
    pub email_claim: String,
    pub email_policy: String,
    pub verified_claim: String,
    pub allowed_email_domains: Vec<String>,
    pub enabled: bool,
    pub created_at: chrono::DateTime<chrono::Utc>,
    pub updated_at: chrono::DateTime<chrono::Utc>,
}

pub(crate) const PROVIDER_COLUMNS: &str = "id, name, issuer, audience, client_id, scopes, token_use, algorithms, \
     email_claim, email_policy, verified_claim, allowed_email_domains, enabled, created_at, updated_at";

impl ProviderRow {
    pub(crate) fn config(&self) -> ProviderConfig {
        ProviderConfig {
            id: Some(self.id),
            source: ProviderSource::Database,
            name: self.name.clone(),
            issuer: self.issuer.clone(),
            audience: self.audience.clone(),
            client_id: self.client_id.clone(),
            scopes: self.scopes.clone(),
            token_use: TokenUse::parse(&self.token_use).unwrap_or(TokenUse::IdToken),
            algorithms: self.algorithms.clone(),
            email_claim: self.email_claim.clone(),
            email_policy: EmailPolicy::parse(&self.email_policy)
                .unwrap_or(EmailPolicy::RequireVerifiedClaim),
            verified_claim: self.verified_claim.clone(),
            allowed_email_domains: self.allowed_email_domains.clone(),
            enabled: self.enabled,
        }
    }
}

/// Strips whitespace and the trailing slash so `https://x/` and `https://x` are one issuer.
pub fn normalize_issuer(s: &str) -> String {
    s.trim().trim_end_matches('/').to_string()
}

// ---------------------------------------------------------------------------------------------
// URL rules (SSRF)
// ---------------------------------------------------------------------------------------------

/// Whether an address must never be fetched on behalf of an administrator: loopback, private,
/// link-local (including the cloud metadata address 169.254.169.254), CGNAT, unique-local,
/// multicast, unspecified and reserved ranges, also when embedded in an IPv6 address.
pub fn is_blocked_ip(ip: IpAddr) -> bool {
    match ip {
        IpAddr::V4(v4) => blocked_v4(v4),
        IpAddr::V6(v6) => blocked_v6(v6),
    }
}

fn blocked_v4(ip: Ipv4Addr) -> bool {
    let o = ip.octets();
    ip.is_loopback()
        || ip.is_private()
        || ip.is_link_local()
        || ip.is_unspecified()
        || ip.is_broadcast()
        || ip.is_multicast()
        || ip.is_documentation()
        || o[0] == 0
        || (o[0] == 100 && (o[1] & 0xC0) == 64) // 100.64.0.0/10 CGNAT
        || (o[0] == 192 && o[1] == 0 && o[2] == 0) // 192.0.0.0/24
        || (o[0] == 198 && (o[1] & 0xFE) == 18) // 198.18.0.0/15 benchmarking
        || o[0] >= 240 // reserved
}

fn blocked_v6(ip: Ipv6Addr) -> bool {
    if let Some(v4) = ip.to_ipv4_mapped() {
        return blocked_v4(v4);
    }
    let s = ip.segments();
    // 64:ff9b::/96 (NAT64) and ::/96 (deprecated IPv4-compatible) embed an IPv4 address.
    if (s[0] == 0x64 && s[1] == 0xff9b && s[2..6].iter().all(|x| *x == 0))
        || s[..6].iter().all(|x| *x == 0)
    {
        let v4 = Ipv4Addr::new((s[6] >> 8) as u8, s[6] as u8, (s[7] >> 8) as u8, s[7] as u8);
        return blocked_v4(v4) || ip.is_unspecified() || ip.is_loopback();
    }
    ip.is_loopback()
        || ip.is_unspecified()
        || ip.is_multicast()
        || (s[0] & 0xFE00) == 0xFC00 // unique local fc00::/7
        || (s[0] & 0xFFC0) == 0xFE80 // link local fe80::/10
        || (s[0] & 0xFFC0) == 0xFEC0 // deprecated site local
        || (s[0] == 0x2001 && s[1] == 0x0db8) // documentation
}

/// Checks the shape of an administrator-supplied URL: https only (unless insecure URLs are
/// allowed), a host, no credentials, and for an IP literal the address rules. Host names are
/// checked after resolution, when the connection is made.
pub fn validate_idp_url(settings: &IdpSettings, raw: &str) -> Result<reqwest::Url, String> {
    let url = reqwest::Url::parse(raw.trim()).map_err(|_| format!("{raw:?} is not a valid URL"))?;
    match url.scheme() {
        "https" => {}
        "http" if settings.allow_insecure_urls => {}
        _ => return Err("only https URLs are allowed".into()),
    }
    if !url.username().is_empty() || url.password().is_some() {
        return Err("URLs with credentials are not allowed".into());
    }
    let host = url.host().ok_or("the URL has no host")?;
    if !settings.allow_insecure_urls {
        let literal = match host {
            url::Host::Ipv4(a) => Some(IpAddr::V4(a)),
            url::Host::Ipv6(a) => Some(IpAddr::V6(a)),
            url::Host::Domain(_) => None,
        };
        if literal.is_some_and(is_blocked_ip) {
            return Err(
                "the host is a loopback, private, link-local or otherwise internal address".into(),
            );
        }
    }
    Ok(url)
}

/// GET with the rules of ADR 0055: validated URL, every resolved address checked and then pinned
/// for the connection, 5 s connect and 10 s total timeout, no redirects, 1 MiB body limit.
async fn guarded_get(settings: &IdpSettings, raw: &str) -> Result<Vec<u8>, String> {
    let url = validate_idp_url(settings, raw)?;
    let host = url.host_str().ok_or("the URL has no host")?.to_string();
    let port = url.port_or_known_default().ok_or("the URL has no port")?;
    let addrs: Vec<std::net::SocketAddr> =
        tokio::net::lookup_host((host.trim_matches(['[', ']']), port))
            .await
            .map_err(|e| format!("cannot resolve {host}: {e}"))?
            .collect();
    if addrs.is_empty() {
        return Err(format!("{host} does not resolve"));
    }
    if !settings.allow_insecure_urls && addrs.iter().any(|a| is_blocked_ip(a.ip())) {
        return Err(format!(
            "{host} resolves to a loopback, private, link-local or otherwise internal address"
        ));
    }
    let client = reqwest::Client::builder()
        .no_proxy()
        .connect_timeout(Duration::from_secs(5))
        .timeout(Duration::from_secs(10))
        .redirect(reqwest::redirect::Policy::none())
        .resolve_to_addrs(&host, &addrs)
        .build()
        .map_err(|e| e.to_string())?;
    let mut res = client
        .get(url)
        .send()
        .await
        .map_err(|e| format!("request failed: {}", short_error(&e)))?;
    if !res.status().is_success() {
        return Err(format!("the server answered {}", res.status()));
    }
    let mut body = Vec::new();
    while let Some(chunk) = res
        .chunk()
        .await
        .map_err(|e| format!("reading the response failed: {}", short_error(&e)))?
    {
        if body.len() + chunk.len() > MAX_RESPONSE_BYTES {
            return Err("the response is larger than 1 MiB".into());
        }
        body.extend_from_slice(&chunk);
    }
    Ok(body)
}

fn short_error(e: &reqwest::Error) -> &'static str {
    if e.is_timeout() {
        "timeout"
    } else if e.is_connect() {
        "connection failed"
    } else {
        "error"
    }
}

// ---------------------------------------------------------------------------------------------
// Discovery and keys
// ---------------------------------------------------------------------------------------------

/// A signing key as advertised by the provider.
#[derive(Debug, Clone)]
pub struct KeyInfo {
    /// Key id.
    pub kid: Option<String>,
    /// Key type (`RSA`, `EC`, ...).
    pub kty: String,
    /// Algorithm the key declares, if any.
    pub alg: Option<String>,
}

/// What a fetch of a provider's discovery document and keys produced.
pub struct Fetched {
    /// Whether the discovery issuer equals the configured issuer.
    pub issuer_match: bool,
    /// The issuer the discovery document claims.
    pub discovery_issuer: String,
    /// Usable keys by key id.
    pub keys: HashMap<String, DecodingKey>,
    /// Every key of the JWKS.
    pub key_infos: Vec<KeyInfo>,
    /// `claims_supported` of the discovery document, if advertised.
    pub claims_supported: Option<Vec<String>>,
}

/// Fetches the discovery document and, when its issuer matches, the JWKS. `Err` means the
/// provider could not be reached or answered nonsense.
pub async fn fetch_provider(settings: &IdpSettings, issuer: &str) -> Result<Fetched, String> {
    let url = format!(
        "{}/.well-known/openid-configuration",
        normalize_issuer(issuer)
    );
    let body = guarded_get(settings, &url).await?;
    let doc: Value = serde_json::from_slice(&body)
        .map_err(|_| "the discovery document is not valid JSON".to_string())?;
    let discovery_issuer = doc
        .get("issuer")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string();
    let claims_supported = doc.get("claims_supported").and_then(|v| {
        v.as_array().map(|a| {
            a.iter()
                .filter_map(|x| x.as_str().map(str::to_string))
                .collect()
        })
    });
    let issuer_match = normalize_issuer(&discovery_issuer) == normalize_issuer(issuer);
    let mut fetched = Fetched {
        issuer_match,
        discovery_issuer,
        keys: HashMap::new(),
        key_infos: vec![],
        claims_supported,
    };
    if !issuer_match {
        return Ok(fetched);
    }
    let jwks_uri = doc
        .get("jwks_uri")
        .and_then(Value::as_str)
        .ok_or("the discovery document has no jwks_uri")?;
    let body = guarded_get(settings, jwks_uri).await?;
    let jwks: Value =
        serde_json::from_slice(&body).map_err(|_| "the JWKS is not valid JSON".to_string())?;
    let keys = jwks
        .get("keys")
        .and_then(Value::as_array)
        .ok_or("the JWKS has no keys")?;
    for k in keys {
        let kid = k.get("kid").and_then(Value::as_str).map(str::to_string);
        fetched.key_infos.push(KeyInfo {
            kid: kid.clone(),
            kty: k
                .get("kty")
                .and_then(Value::as_str)
                .unwrap_or("?")
                .to_string(),
            alg: k.get("alg").and_then(Value::as_str).map(str::to_string),
        });
        if let (Some(kid), Ok(jwk)) = (
            kid,
            serde_json::from_value::<jsonwebtoken::jwk::Jwk>(k.clone()),
        ) {
            if let Ok(key) = DecodingKey::from_jwk(&jwk) {
                fetched.keys.insert(kid, key);
            }
        }
    }
    Ok(fetched)
}

// ---------------------------------------------------------------------------------------------
// Claims and token checks
// ---------------------------------------------------------------------------------------------

/// The claims of a verified token, as a JSON map so configured claim names work.
#[derive(Debug, Clone)]
pub struct Claims {
    /// The identity provider's stable subject id.
    pub sub: String,
    /// All claims.
    pub raw: Map<String, Value>,
}

impl Claims {
    /// Builds claims from a JSON map; needs a non-empty string `sub`.
    pub fn from_map(raw: Map<String, Value>) -> Option<Self> {
        let sub = raw.get("sub")?.as_str()?.trim().to_string();
        (!sub.is_empty()).then_some(Self { sub, raw })
    }

    /// Claims with just a subject and optionally an e-mail and its verification flag, using the
    /// claim names `email` and `email_verified`.
    pub fn simple(sub: &str, email: Option<&str>, verified: Option<bool>) -> Self {
        let mut raw = Map::new();
        raw.insert("sub".into(), Value::String(sub.into()));
        if let Some(e) = email {
            raw.insert("email".into(), Value::String(e.into()));
        }
        if let Some(v) = verified {
            raw.insert("email_verified".into(), Value::Bool(v));
        }
        Self {
            sub: sub.into(),
            raw,
        }
    }

    /// The e-mail address in the provider's e-mail claim.
    pub fn email(&self, cfg: &ProviderConfig) -> Option<String> {
        self.raw
            .get(&cfg.email_claim)?
            .as_str()
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
    }

    /// The verification flag in the provider's verified claim: a bool, the strings "true" or
    /// "1", or the number 1 count as true; anything else present counts as false; absent is none.
    pub fn verified(&self, cfg: &ProviderConfig) -> Option<bool> {
        self.raw.get(&cfg.verified_claim).map(truthy)
    }
}

fn truthy(v: &Value) -> bool {
    match v {
        Value::Bool(b) => *b,
        Value::String(s) => {
            let s = s.trim();
            s.eq_ignore_ascii_case("true") || s == "1"
        }
        Value::Number(n) => n.as_i64() == Some(1) || n.as_f64() == Some(1.0),
        _ => false,
    }
}

/// The outcome of checking a token against a provider, stage by stage.
#[derive(Debug, Clone, Default)]
pub struct TokenCheck {
    /// The signature verified with one of the provider's keys.
    pub signature_ok: bool,
    /// `iss` equals the provider's issuer.
    pub issuer_ok: Option<bool>,
    /// `aud` contains the provider's audience.
    pub audience_ok: Option<bool>,
    /// `exp` is present and in the future (60 s leeway).
    pub expiry_ok: Option<bool>,
    /// `nbf` is absent or in the past (60 s leeway).
    pub not_before_ok: Option<bool>,
    /// The claims, when the signature verified and a subject is present.
    pub claims: Option<Claims>,
    /// Why the token is not valid.
    pub reason: Option<String>,
}

impl TokenCheck {
    /// Whether every stage passed.
    pub fn is_valid(&self) -> bool {
        self.signature_ok
            && self.claims.is_some()
            && self.issuer_ok == Some(true)
            && self.audience_ok == Some(true)
            && self.expiry_ok == Some(true)
            && self.not_before_ok != Some(false)
    }
}

fn algorithm_name(a: Algorithm) -> Option<&'static str> {
    Some(match a {
        Algorithm::RS256 => "RS256",
        Algorithm::RS384 => "RS384",
        Algorithm::RS512 => "RS512",
        Algorithm::ES256 => "ES256",
        Algorithm::ES384 => "ES384",
        Algorithm::PS256 => "PS256",
        Algorithm::PS384 => "PS384",
        Algorithm::PS512 => "PS512",
        // HS*, EdDSA: never accepted.
        _ => return None,
    })
}

/// Reads the unverified `iss` of a token. Only used to choose which provider's configuration to
/// verify with; nothing read here is trusted.
pub fn peek_issuer(token: &str) -> Option<String> {
    let payload = token.split('.').nth(1)?;
    let bytes = base64::engine::general_purpose::URL_SAFE_NO_PAD
        .decode(payload.trim_end_matches('='))
        .ok()?;
    let v: Value = serde_json::from_slice(&bytes).ok()?;
    v.get("iss")?.as_str().map(str::to_string)
}

/// Checks the signature with `key` and then issuer, audience, `exp` and `nbf` by hand.
pub fn check_token(
    cfg: &ProviderConfig,
    key: &DecodingKey,
    alg: Algorithm,
    token: &str,
    now: i64,
) -> TokenCheck {
    let mut v = Validation::new(alg);
    v.validate_exp = false;
    v.validate_nbf = false;
    v.validate_aud = false;
    v.required_spec_claims.clear();
    let mut out = TokenCheck::default();
    let map = match decode::<Map<String, Value>>(token, key, &v) {
        Ok(d) => d.claims,
        Err(_) => {
            out.reason = Some("the signature does not verify".into());
            return out;
        }
    };
    out.signature_ok = true;
    let iss = map.get("iss").and_then(Value::as_str);
    out.issuer_ok = Some(iss.is_some_and(|i| normalize_issuer(i) == cfg.issuer));
    out.audience_ok = Some(match map.get("aud") {
        Some(Value::String(s)) => *s == cfg.audience,
        Some(Value::Array(a)) => a.iter().any(|x| x.as_str() == Some(&cfg.audience)),
        _ => false,
    });
    out.expiry_ok = Some(
        map.get("exp")
            .and_then(Value::as_f64)
            .is_some_and(|exp| exp + LEEWAY_SECS as f64 > now as f64),
    );
    out.not_before_ok = map.get("nbf").map(|n| {
        n.as_f64()
            .is_some_and(|nbf| nbf - (LEEWAY_SECS as f64) <= now as f64)
    });
    out.claims = Claims::from_map(map);
    out.reason = if out.claims.is_none() {
        Some("the token has no subject".into())
    } else if out.issuer_ok != Some(true) {
        Some("wrong issuer".into())
    } else if out.audience_ok != Some(true) {
        Some("wrong audience".into())
    } else if out.expiry_ok != Some(true) {
        Some("the token has expired".into())
    } else if out.not_before_ok == Some(false) {
        Some("the token is not valid yet".into())
    } else {
        None
    };
    out
}

/// The algorithm of a token header if the provider accepts it.
pub fn accepted_algorithm(
    cfg: &ProviderConfig,
    token: &str,
) -> Option<(Algorithm, Option<String>)> {
    let header = decode_header(token).ok()?;
    let name = algorithm_name(header.alg)?;
    cfg.algorithms
        .iter()
        .any(|a| a == name)
        .then_some((header.alg, header.kid))
}

/// Seconds since the epoch.
pub fn now_secs() -> i64 {
    chrono::Utc::now().timestamp()
}

// ---------------------------------------------------------------------------------------------
// Registry
// ---------------------------------------------------------------------------------------------

#[derive(Default)]
struct KeyCache {
    keys: HashMap<String, DecodingKey>,
    fetched_at: Option<Instant>,
    last_attempt: Option<Instant>,
}

struct Runtime {
    cfg: Arc<ProviderConfig>,
    cache: tokio::sync::Mutex<KeyCache>,
}

/// A verified token and the provider that vouched for it.
pub struct Verified {
    /// The token's claims.
    pub claims: Claims,
    /// The provider whose keys verified the token.
    pub provider: Arc<ProviderConfig>,
}

/// The enabled identity providers, reloadable while the API runs.
pub struct IdentityProviders {
    settings: IdpSettings,
    env: Option<ProviderConfig>,
    runtimes: RwLock<Arc<Vec<Arc<Runtime>>>>,
}

impl IdentityProviders {
    /// A registry with the optional environment provider; call [`IdentityProviders::reload`] to
    /// add the database providers.
    pub fn new(settings: IdpSettings, env: Option<ProviderConfig>) -> Self {
        let reg = Self {
            settings,
            env,
            runtimes: RwLock::new(Arc::new(vec![])),
        };
        reg.set_database_providers(vec![]);
        reg
    }

    /// The settings the registry runs with.
    pub fn settings(&self) -> &IdpSettings {
        &self.settings
    }

    /// The read-only provider from `OIDC_ISSUER`/`OIDC_AUDIENCE`, if configured.
    pub fn env_provider(&self) -> Option<&ProviderConfig> {
        self.env.as_ref()
    }

    /// The enabled providers, environment provider first.
    pub fn enabled(&self) -> Vec<Arc<ProviderConfig>> {
        self.runtimes
            .read()
            .unwrap_or_else(|e| e.into_inner())
            .iter()
            .map(|r| r.cfg.clone())
            .collect()
    }

    /// Replaces the database providers (disabled ones are dropped). Caches of providers whose
    /// configuration did not change are kept.
    pub fn set_database_providers(&self, db: Vec<ProviderConfig>) {
        let old = self
            .runtimes
            .read()
            .unwrap_or_else(|e| e.into_inner())
            .clone();
        let all = self.env.iter().cloned().chain(db).filter(|c| c.enabled);
        let next: Vec<Arc<Runtime>> = all
            .map(|cfg| {
                old.iter()
                    .find(|r| *r.cfg == cfg)
                    .cloned()
                    .unwrap_or_else(|| {
                        Arc::new(Runtime {
                            cfg: Arc::new(cfg),
                            cache: Default::default(),
                        })
                    })
            })
            .collect();
        *self.runtimes.write().unwrap_or_else(|e| e.into_inner()) = Arc::new(next);
    }

    /// Loads the enabled providers from the database. On error the previous set stays.
    pub async fn reload(&self, db: &PgPool) -> Result<(), sqlx::Error> {
        let rows: Vec<ProviderRow> = sqlx::query_as(&format!(
            "SELECT {PROVIDER_COLUMNS} FROM core.identity_providers WHERE enabled ORDER BY created_at, id"
        ))
        .fetch_all(db)
        .await?;
        self.set_database_providers(rows.iter().map(ProviderRow::config).collect());
        Ok(())
    }

    async fn key_for(&self, rt: &Runtime, kid: &str) -> Result<Option<DecodingKey>, AppError> {
        let mut c = rt.cache.lock().await;
        let now = Instant::now();
        let expired = c
            .fetched_at
            .is_none_or(|t| now.duration_since(t) >= self.settings.jwks_ttl);
        let unknown = !c.keys.contains_key(kid);
        let may = c
            .last_attempt
            .is_none_or(|t| now.duration_since(t) >= self.settings.refresh_throttle);
        if (expired || unknown) && may {
            c.last_attempt = Some(now);
            match fetch_provider(&self.settings, &rt.cfg.issuer).await {
                Ok(f) if f.issuer_match => {
                    c.keys = f.keys;
                    c.fetched_at = Some(Instant::now());
                }
                Ok(_) => {
                    tracing::warn!(issuer = %rt.cfg.issuer, "discovery issuer mismatch");
                    c.keys.clear();
                    c.fetched_at = None;
                    return Ok(None);
                }
                Err(e) => {
                    tracing::warn!(issuer = %rt.cfg.issuer, error = %e, "fetching signing keys failed");
                    if expired || !c.keys.contains_key(kid) {
                        return Err(AppError::Internal(anyhow::anyhow!(
                            "identity provider unreachable"
                        )));
                    }
                }
            }
        }
        Ok(c.keys.get(kid).cloned())
    }

    /// Verifies an access token: picks the provider by the unverified `iss`, requires an
    /// accepted algorithm and a known `kid`, verifies the signature with that provider's keys and
    /// checks issuer, audience, `exp` and `nbf`. Unknown or disabled issuer is 401.
    pub async fn verify(&self, token: &str) -> Result<Verified, AppError> {
        let iss = normalize_issuer(&peek_issuer(token).ok_or(AppError::Unauthorized)?);
        let rt = self
            .runtimes
            .read()
            .unwrap_or_else(|e| e.into_inner())
            .iter()
            .find(|r| r.cfg.issuer == iss)
            .cloned()
            .ok_or(AppError::Unauthorized)?;
        let (alg, kid) = accepted_algorithm(&rt.cfg, token).ok_or(AppError::Unauthorized)?;
        let kid = kid.ok_or(AppError::Unauthorized)?;
        let key = self
            .key_for(&rt, &kid)
            .await?
            .ok_or(AppError::Unauthorized)?;
        let check = check_token(&rt.cfg, &key, alg, token, now_secs());
        if !check.is_valid() {
            tracing::debug!(reason = ?check.reason, "token rejected");
            return Err(AppError::Unauthorized);
        }
        Ok(Verified {
            claims: check.claims.ok_or(AppError::Unauthorized)?,
            provider: rt.cfg.clone(),
        })
    }
}

/// Reloads the providers every `every` so other instances follow admin changes.
pub fn spawn_reload(auth: Arc<crate::auth::AuthConfig>, db: PgPool, every: Duration) {
    tokio::spawn(async move {
        loop {
            tokio::time::sleep(every).await;
            if let crate::auth::AuthConfig::Oidc(p) = auth.as_ref() {
                if let Err(e) = p.reload(&db).await {
                    tracing::warn!(error = %e, "reloading identity providers failed");
                }
            }
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ip(s: &str) -> IpAddr {
        s.parse().unwrap()
    }

    #[test]
    fn internal_addresses_are_blocked() {
        for a in [
            "127.0.0.1",
            "10.1.2.3",
            "172.16.0.1",
            "192.168.1.1",
            "169.254.169.254",
            "169.254.0.1",
            "100.64.0.1",
            "100.127.255.255",
            "0.0.0.0",
            "224.0.0.1",
            "255.255.255.255",
            "::1",
            "::",
            "fc00::1",
            "fd12::1",
            "fe80::1",
            "ff02::1",
            "::ffff:127.0.0.1",
            "::ffff:169.254.169.254",
            "64:ff9b::a00:1",
        ] {
            assert!(is_blocked_ip(ip(a)), "{a}");
        }
        for a in [
            "8.8.8.8",
            "1.1.1.1",
            "100.63.0.1",
            "172.32.0.1",
            "2606:4700::1111",
        ] {
            assert!(!is_blocked_ip(ip(a)), "{a}");
        }
    }

    #[test]
    fn url_rules() {
        let s = IdpSettings::default();
        assert!(validate_idp_url(&s, "https://login.example.com/x").is_ok());
        for bad in [
            "http://login.example.com",
            "ftp://x.example",
            "https://user:pw@login.example.com",
            "https://127.0.0.1/",
            "https://169.254.169.254/latest",
            "https://[::1]/",
            "https://10.0.0.5/",
            "nonsense",
        ] {
            assert!(validate_idp_url(&s, bad).is_err(), "{bad}");
        }
        let lax = IdpSettings {
            allow_insecure_urls: true,
            ..IdpSettings::default()
        };
        assert!(validate_idp_url(&lax, "http://127.0.0.1:9/").is_ok());
    }

    #[test]
    fn verification_flag_forms() {
        let cfg = ProviderConfig::from_env("https://i.example", "a");
        let with = |v: Value| {
            let mut c = Claims::simple("s", None, None);
            c.raw.insert("email_verified".into(), v);
            c.verified(&cfg)
        };
        assert_eq!(with(Value::Bool(true)), Some(true));
        assert_eq!(with(Value::Bool(false)), Some(false));
        assert_eq!(with("true".into()), Some(true));
        assert_eq!(with("TRUE".into()), Some(true));
        assert_eq!(with("1".into()), Some(true));
        assert_eq!(with(1.into()), Some(true));
        assert_eq!(with(0.into()), Some(false));
        assert_eq!(with("yes".into()), Some(false));
        assert_eq!(Claims::simple("s", None, None).verified(&cfg), None);
    }

    #[test]
    fn issuers_are_normalised() {
        assert_eq!(
            normalize_issuer(" https://a.example/ "),
            "https://a.example"
        );
    }
}
