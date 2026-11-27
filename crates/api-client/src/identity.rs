//! Identity provider administration (`/api/v1/admin/identity-providers`, ADR 0052): the providers
//! of the installation, their test, and nothing else. Only administrators of the primary company
//! may read them (403 otherwise).

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::client::Client;
use crate::error::ApiError;

/// An identity provider as the admin screen shows it (OpenAPI schema `IdentityProviderInfo`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct IdentityProviderInfo {
    /// Database id; absent for the environment provider.
    #[serde(default)]
    pub id: Option<Uuid>,
    /// `database` or `env`.
    pub source: String,
    /// True for the environment provider: it cannot be changed or deleted here.
    pub read_only: bool,
    pub name: String,
    pub issuer: String,
    pub audience: String,
    #[serde(default)]
    pub client_id: Option<String>,
    pub scopes: String,
    /// `id_token` or `access_token`.
    pub token_use: String,
    pub algorithms: Vec<String>,
    pub email_claim: String,
    /// `require_verified_claim`, `trust_provider_email` or `subject_only`.
    pub email_policy: String,
    pub verified_claim: String,
    pub allowed_email_domains: Vec<String>,
    pub enabled: bool,
    #[serde(default)]
    pub created_at: Option<DateTime<Utc>>,
    #[serde(default)]
    pub updated_at: Option<DateTime<Utc>>,
}

/// The settings of an identity provider (OpenAPI schema `IdentityProviderInput`).
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct IdentityProviderInput {
    pub name: String,
    pub issuer: String,
    pub audience: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub client_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub scopes: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub token_use: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub email_claim: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub email_policy: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub verified_claim: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub allowed_email_domains: Option<Vec<String>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub algorithms: Option<Vec<String>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub enabled: Option<bool>,
    /// Acknowledges that the change can lock people out (see the 409 answers).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub confirm_lockout: Option<bool>,
}

/// A draft configuration (or an existing provider) and optionally a token to try it with
/// (OpenAPI schema `IdentityProviderTest`).
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct IdentityProviderTest {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub config: Option<IdentityProviderInput>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub id: Option<Uuid>,
    /// Checked and discarded: never stored or logged.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sample_token: Option<String>,
}

/// What signing in with the sample token would do (OpenAPI schema `BindingResult`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct BindingResult {
    /// `existing_subject`, `would_bind` or `refused`.
    pub outcome: String,
    #[serde(default)]
    pub reason: Option<String>,
    #[serde(default)]
    pub user_email: Option<String>,
    #[serde(default)]
    pub user_id: Option<Uuid>,
}

/// The result of checking a sample token (OpenAPI schema `TokenTestResult`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TokenTestResult {
    pub valid: bool,
    pub signature_ok: bool,
    #[serde(default)]
    pub audience_ok: Option<bool>,
    #[serde(default)]
    pub expiry_ok: Option<bool>,
    #[serde(default)]
    pub issuer_ok: Option<bool>,
    #[serde(default)]
    pub not_before_ok: Option<bool>,
    #[serde(default)]
    pub reason: Option<String>,
    #[serde(default)]
    pub email: Option<String>,
    #[serde(default)]
    pub email_verified: Option<bool>,
    #[serde(default)]
    pub subject: Option<String>,
    #[serde(default)]
    pub binding: Option<BindingResult>,
}

/// The outcome of testing a provider configuration (OpenAPI schema `IdentityProviderTestResult`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct IdentityProviderTestResult {
    pub discovery_reachable: bool,
    pub issuer_match: bool,
    pub key_count: i64,
    pub key_algorithms: Vec<String>,
    #[serde(default)]
    pub discovery_issuer: Option<String>,
    #[serde(default)]
    pub claims_supported: Option<Vec<String>>,
    #[serde(default)]
    pub error: Option<String>,
    #[serde(default)]
    pub token: Option<TokenTestResult>,
}

#[derive(Debug, Serialize)]
struct ConfirmLockoutQuery {
    #[serde(skip_serializing_if = "Option::is_none")]
    confirm_lockout: Option<bool>,
}

impl Client {
    /// The identity providers of the installation (`GET /api/v1/admin/identity-providers`).
    pub async fn list_identity_providers(&self) -> Result<Vec<IdentityProviderInfo>, ApiError> {
        self.get_json("/api/v1/admin/identity-providers", &()).await
    }

    /// Adds a provider (`POST /api/v1/admin/identity-providers`).
    pub async fn create_identity_provider(
        &self,
        req: &IdentityProviderInput,
    ) -> Result<IdentityProviderInfo, ApiError> {
        self.post_json("/api/v1/admin/identity-providers", req)
            .await
    }

    /// Changes a provider (`PUT /api/v1/admin/identity-providers/{id}`).
    pub async fn update_identity_provider(
        &self,
        id: Uuid,
        req: &IdentityProviderInput,
    ) -> Result<IdentityProviderInfo, ApiError> {
        self.put_json(&format!("/api/v1/admin/identity-providers/{id}"), req)
            .await
    }

    /// Deletes a provider (`DELETE /api/v1/admin/identity-providers/{id}`). Without
    /// `confirm_lockout` the server answers 409 when the deletion could lock people out.
    pub async fn delete_identity_provider(
        &self,
        id: Uuid,
        confirm_lockout: bool,
    ) -> Result<(), ApiError> {
        self.delete_empty_with_query(
            &format!("/api/v1/admin/identity-providers/{id}"),
            &ConfirmLockoutQuery {
                confirm_lockout: confirm_lockout.then_some(true),
            },
        )
        .await
    }

    /// Tests a draft or saved provider (`POST /api/v1/admin/identity-providers/test`).
    pub async fn test_identity_provider(
        &self,
        req: &IdentityProviderTest,
    ) -> Result<IdentityProviderTestResult, ApiError> {
        self.post_json("/api/v1/admin/identity-providers/test", req)
            .await
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn encodes_input_without_unset_fields_and_decodes_env_provider() {
        let input = IdentityProviderInput {
            name: "Google".into(),
            issuer: "https://accounts.google.com".into(),
            audience: "app".into(),
            ..IdentityProviderInput::default()
        };
        assert_eq!(
            serde_json::to_string(&input).unwrap(),
            r#"{"name":"Google","issuer":"https://accounts.google.com","audience":"app"}"#
        );
        let env: IdentityProviderInfo = serde_json::from_str(
            r#"{"source":"env","read_only":true,"name":"Env","issuer":"https://id.example",
            "audience":"api","scopes":"openid","token_use":"id_token","algorithms":["RS256"],
            "email_claim":"email","email_policy":"require_verified_claim",
            "verified_claim":"email_verified","allowed_email_domains":[],"enabled":true}"#,
        )
        .unwrap();
        assert!(env.id.is_none());
        assert!(env.read_only);
    }
}
