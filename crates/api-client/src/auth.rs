//! Authentication, session, and user-profile DTOs and endpoints.
//!
//! Matches the authentication model used by the backend (`crates/core/src/auth.rs`)
//! and the Flutter app (`app/lib/app/session.dart`):
//! - Development mode (`AUTH_MODE=dev`): `X-Dev-User: <email>`
//! - Production OIDC mode: `Authorization: Bearer <token>`
//! - Optional legal entity selection: `X-Company-Id: <uuid>`

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::client::Client;
use crate::error::ApiError;

/// Header used in development mode (`AUTH_MODE=dev`) to identify the user by email.
pub const DEV_USER_HEADER: &str = "X-Dev-User";
/// Header used to select the active legal entity (company) for the request.
pub const COMPANY_HEADER: &str = "X-Company-Id";

/// Authentication credentials sent on API requests.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "value", rename_all = "snake_case")]
pub enum Auth {
    /// Development-mode identity passed via `X-Dev-User`.
    DevUser(String),
    /// OpenID Connect token passed via `Authorization: Bearer <token>`.
    BearerToken(String),
}

impl Auth {
    fn is_non_empty(&self) -> bool {
        match self {
            Self::DevUser(email) => !email.trim().is_empty(),
            Self::BearerToken(token) => !token.trim().is_empty(),
        }
    }
}

/// Connection and identity state of a client session.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Session {
    pub base_url: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub auth: Option<Auth>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub company_id: Option<Uuid>,
}

impl Session {
    /// Creates an unauthenticated session pointing at `base_url`.
    pub fn anonymous(base_url: impl Into<String>) -> Self {
        Self {
            base_url: normalize_base_url(base_url.into()),
            auth: None,
            company_id: None,
        }
    }

    /// Creates a dev-mode session using `X-Dev-User`.
    pub fn dev(base_url: impl Into<String>, email: impl Into<String>) -> Self {
        Self {
            base_url: normalize_base_url(base_url.into()),
            auth: Some(Auth::DevUser(email.into().trim().to_string())),
            company_id: None,
        }
    }

    /// Creates a token-authenticated session using `Authorization: Bearer`.
    pub fn bearer(base_url: impl Into<String>, token: impl Into<String>) -> Self {
        Self {
            base_url: normalize_base_url(base_url.into()),
            auth: Some(Auth::BearerToken(token.into().trim().to_string())),
            company_id: None,
        }
    }

    /// Sets or clears the active `X-Company-Id` header value.
    pub fn with_company_id(mut self, company_id: Option<Uuid>) -> Self {
        self.company_id = company_id;
        self
    }

    /// Returns `true` when non-empty credentials are present.
    pub fn is_signed_in(&self) -> bool {
        self.auth.as_ref().is_some_and(Auth::is_non_empty)
    }

    /// Returns a signed-out copy keeping the same `base_url`.
    pub fn signed_out(&self) -> Self {
        Self::anonymous(self.base_url.clone())
    }
}

pub(crate) fn normalize_base_url(raw: String) -> String {
    raw.trim().trim_end_matches('/').to_string()
}

/// What the sign-in page needs to know about an enabled identity provider.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PublicProvider {
    /// Display name.
    pub name: String,
    /// Issuer URL.
    pub issuer: String,
    /// Public client id of the interactive sign-in.
    #[serde(default)]
    pub client_id: Option<String>,
    /// Scopes to ask for.
    pub scopes: String,
    /// Token to send as the bearer token: `id_token` or `access_token`.
    pub token_use: String,
    /// `database` or `env` (the read-only fallback from `OIDC_ISSUER`).
    pub source: String,
}

/// What an environment is for.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EnvKind {
    #[default]
    Live,
    Test,
    Tutorial,
}

/// The environment this API instance serves (`GET /api/v1/meta/environment`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct EnvironmentInfo {
    /// Display name (`APP_ENV_NAME`, default: the database name).
    pub name: String,
    pub kind: EnvKind,
    /// Name of the database only; never host, user or password.
    pub db_name: String,
    /// Version of the API.
    pub version: String,
    /// Unique ID of this database instance.
    pub instance_id: String,
}

/// A legal entity (own VAT number, own numbering, own stock and books).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Company {
    pub id: Uuid,
    pub name: String,
    #[serde(default)]
    pub vat_number: Option<String>,
    pub street: String,
    pub postal_code: String,
    pub city: String,
    pub country_code: String,
    pub currency: String,
    #[serde(default)]
    pub email: Option<String>,
    #[serde(default)]
    pub phone: Option<String>,
    #[serde(default)]
    pub iban: Option<String>,
    pub default_language: String,
    pub is_primary: bool,
    pub quotation_single_line_items: bool,
    pub autosave_minutes: i32,
}

/// Company membership returned as part of [`Me`].
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Membership {
    pub company_id: Uuid,
    pub company_name: String,
    pub roles: Vec<String>,
    pub is_default: bool,
}

/// Module availability flag returned as part of [`Me`].
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct MeModule {
    pub code: String,
    pub enabled: bool,
}

/// The authenticated user, the active company, and all companies they can switch to.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Me {
    pub user_id: Uuid,
    pub email: String,
    pub display_name: String,
    pub company: Company,
    pub roles: Vec<String>,
    /// Permissions after roles and disabled modules are applied.
    pub permissions: Vec<String>,
    /// Every module with whether it is on for this user in the active company.
    pub modules: Vec<MeModule>,
    pub memberships: Vec<Membership>,
}

impl Me {
    /// Returns `true` if the user holds the given permission string (e.g. `"products.read"`).
    pub fn has_permission(&self, permission: &str) -> bool {
        self.permissions.iter().any(|p| p == permission)
    }

    /// Returns `true` if the given module code is enabled for the user.
    pub fn is_module_enabled(&self, code: &str) -> bool {
        self.modules.iter().any(|m| m.code == code && m.enabled)
    }
}

/// A single keyboard shortcut chord override.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ShortcutBinding {
    /// Logical key name (e.g. `"keyB"`, `"digit1"`, `"enter"`, `"escape"`, `"slash"`).
    pub key: String,
    /// Modifier group: `"primary"`, `"standard"`, or `"none"`.
    #[serde(rename = "mod")]
    pub modifier: String,
    /// Whether Shift must also be held.
    #[serde(default)]
    pub shift: bool,
}

/// Per-user preferences stored across sessions and devices.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct UserPreferences {
    /// Custom shortcut bindings keyed by `ShortcutAction.name`.
    #[serde(default)]
    pub shortcuts: BTreeMap<String, ShortcutBinding>,
    /// Per-user override for draft autosave interval in minutes (`None` = use company default, `0` = off).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub autosave_minutes: Option<i32>,
}

impl Client {
    /// Lists enabled OIDC identity providers for the sign-in page (`GET /api/v1/auth/providers`).
    ///
    /// Returns an empty list when the server runs in dev mode. Does not require authentication.
    pub async fn auth_providers(&self) -> Result<Vec<PublicProvider>, ApiError> {
        self.get_json("/api/v1/auth/providers", &()).await
    }

    /// Fetches server environment metadata (`GET /api/v1/meta/environment`).
    ///
    /// Does not require authentication.
    pub async fn environment(&self) -> Result<EnvironmentInfo, ApiError> {
        self.get_json("/api/v1/meta/environment", &()).await
    }

    /// Fetches the authenticated user, active company, and permissions (`GET /api/v1/me`).
    pub async fn me(&self) -> Result<Me, ApiError> {
        self.get_json("/api/v1/me", &()).await
    }

    /// Verifies `auth` by calling `GET /api/v1/me` and, on success, activates the session.
    ///
    /// Mirrors the Flutter app's login verification flow (`LoginPage._signIn`).
    pub async fn sign_in(&mut self, auth: Auth) -> Result<Me, ApiError> {
        let candidate = Session {
            base_url: self.session().base_url.clone(),
            auth: Some(auth),
            company_id: self.session().company_id,
        };
        let probe = self.with_session(candidate.clone());
        let me = probe.me().await?;
        self.set_session(candidate);
        Ok(me)
    }

    /// Clears credentials and company selection while retaining the configured server URL.
    pub fn sign_out(&mut self) {
        let signed_out = self.session().signed_out();
        self.set_session(signed_out);
    }

    /// Fetches the authenticated user's preferences (`GET /api/v1/me/preferences`).
    pub async fn get_preferences(&self) -> Result<UserPreferences, ApiError> {
        self.get_json("/api/v1/me/preferences", &()).await
    }

    /// Replaces the authenticated user's preferences (`PUT /api/v1/me/preferences`).
    pub async fn put_preferences(
        &self,
        prefs: &UserPreferences,
    ) -> Result<UserPreferences, ApiError> {
        self.put_json("/api/v1/me/preferences", prefs).await
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn deserialize_public_providers() {
        let json = r#"[
            {
                "name": "Entra ID",
                "issuer": "https://login.microsoftonline.com/tenant/v2.0",
                "client_id": "11111111-2222-3333-4444-555555555555",
                "scopes": "openid profile email",
                "token_use": "id_token",
                "source": "database"
            },
            {
                "name": "Keycloak",
                "issuer": "https://sso.example.com/realms/tradocraft",
                "client_id": null,
                "scopes": "openid",
                "token_use": "access_token",
                "source": "env"
            }
        ]"#;
        let providers: Vec<PublicProvider> = serde_json::from_str(json).unwrap();
        assert_eq!(providers.len(), 2);
        assert_eq!(providers[0].name, "Entra ID");
        assert!(providers[0].client_id.is_some());
        assert_eq!(providers[1].client_id, None);
        assert_eq!(providers[1].token_use, "access_token");
    }

    #[test]
    fn deserialize_environment_info() {
        let json = r#"{
            "name": "Local Dev",
            "kind": "test",
            "db_name": "tradocraft_dev",
            "version": "0.3.0",
            "instance_id": "01900000-0000-7000-8000-000000000001"
        }"#;
        let env: EnvironmentInfo = serde_json::from_str(json).unwrap();
        assert_eq!(env.kind, EnvKind::Test);
        assert_eq!(env.db_name, "tradocraft_dev");
    }

    #[test]
    fn deserialize_me() {
        let json = r#"{
            "user_id": "01900000-0000-7000-8000-000000000010",
            "email": "sales@example.com",
            "display_name": "Sarah Sales",
            "company": {
                "id": "01900000-0000-7000-8000-000000000020",
                "name": "TradoCraft BV",
                "vat_number": "BE0123456789",
                "street": "Kerkstraat 1",
                "postal_code": "1000",
                "city": "Brussel",
                "country_code": "BE",
                "currency": "EUR",
                "email": null,
                "phone": "+32 2 555 01 00",
                "iban": null,
                "default_language": "nl",
                "is_primary": true,
                "quotation_single_line_items": false,
                "autosave_minutes": 5
            },
            "roles": ["sales"],
            "permissions": ["customers.read", "products.read"],
            "modules": [
                {"code": "crm", "enabled": true},
                {"code": "production", "enabled": false}
            ],
            "memberships": [
                {
                    "company_id": "01900000-0000-7000-8000-000000000020",
                    "company_name": "TradoCraft BV",
                    "roles": ["sales"],
                    "is_default": true
                }
            ]
        }"#;
        let me: Me = serde_json::from_str(json).unwrap();
        assert_eq!(me.email, "sales@example.com");
        assert!(me.has_permission("products.read"));
        assert!(!me.has_permission("users.admin"));
        assert!(me.is_module_enabled("crm"));
        assert!(!me.is_module_enabled("production"));
        assert_eq!(me.company.autosave_minutes, 5);
    }

    #[test]
    fn deserialize_user_preferences() {
        let json = r#"{
            "autosave_minutes": 2,
            "shortcuts": {
                "save": {
                    "key": "keyS",
                    "mod": "standard",
                    "shift": false
                }
            }
        }"#;
        let prefs: UserPreferences = serde_json::from_str(json).unwrap();
        assert_eq!(prefs.autosave_minutes, Some(2));
        assert_eq!(
            prefs.shortcuts.get("save"),
            Some(&ShortcutBinding {
                key: "keyS".into(),
                modifier: "standard".into(),
                shift: false,
            })
        );

        let empty: UserPreferences = serde_json::from_str("{}").unwrap();
        assert_eq!(empty.autosave_minutes, None);
        assert!(empty.shortcuts.is_empty());
    }

    #[test]
    fn session_helpers() {
        let anon = Session::anonymous("http://localhost:8080/");
        assert_eq!(anon.base_url, "http://localhost:8080");
        assert!(!anon.is_signed_in());

        let dev = Session::dev("http://localhost:8080", " admin@example.com ");
        assert!(dev.is_signed_in());
        assert_eq!(dev.auth, Some(Auth::DevUser("admin@example.com".into())));
        assert!(!dev.signed_out().is_signed_in());
    }

    #[test]
    fn session_serde_roundtrip() {
        let dev = Session::dev("http://localhost:8080/", "sales@example.com")
            .with_company_id(Some(Uuid::nil()));
        let dev_json = serde_json::to_string(&dev).unwrap();
        let dev_roundtrip: Session = serde_json::from_str(&dev_json).unwrap();
        assert_eq!(dev_roundtrip, dev);

        let bearer = Session::bearer("https://api.tradocraft.example", "tok_secret_123");
        let bearer_json = serde_json::to_string(&bearer).unwrap();
        let bearer_roundtrip: Session = serde_json::from_str(&bearer_json).unwrap();
        assert_eq!(bearer_roundtrip, bearer);

        let anon = Session::anonymous("https://api.tradocraft.example");
        let anon_json = serde_json::to_string(&anon).unwrap();
        let anon_roundtrip: Session = serde_json::from_str(&anon_json).unwrap();
        assert_eq!(anon_roundtrip, anon);
    }
}
