//! Administration DTOs and endpoints: company members, roles, modules, the company logo and
//! company-wide settings (`/api/v1/admin/...`, `/api/v1/roles`).

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::auth::Company;
use crate::client::Client;
use crate::error::ApiError;

/// A member of the active company, including deactivated ones (OpenAPI schema `AdminUser`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AdminUser {
    pub user_id: Uuid,
    pub email: String,
    pub display_name: String,
    pub roles: Vec<String>,
    /// Modules switched off for this user (on top of the company's).
    pub disabled_modules: Vec<String>,
    /// False when the membership in this company is deactivated.
    pub active: bool,
    /// Whether the person has signed in with the identity provider yet.
    pub has_signed_in: bool,
}

/// Request payload for `POST /api/v1/admin/users` (OpenAPI schema `AdminUserCreate`).
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct AdminUserCreate {
    pub email: String,
    pub display_name: String,
    pub roles: Vec<String>,
    #[serde(default)]
    pub disabled_modules: Vec<String>,
}

/// Request payload for `PUT /api/v1/admin/users/{id}` (OpenAPI schema `AdminUserUpdate`).
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct AdminUserUpdate {
    pub display_name: String,
    pub roles: Vec<String>,
    pub disabled_modules: Vec<String>,
    pub active: bool,
}

/// A role and the permissions it grants (OpenAPI schema `RoleInfo`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RoleInfo {
    pub role: String,
    pub permissions: Vec<String>,
}

/// A module of the catalogue and whether the company has it on (OpenAPI schema `ModuleInfo`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ModuleInfo {
    pub code: String,
    /// Modules that must stay on for this one.
    pub requires: Vec<String>,
    /// The permissions this module owns.
    pub permissions: Vec<String>,
    pub enabled: bool,
}

/// Request payload for `PUT /api/v1/admin/modules` (OpenAPI schema `ModulesInput`).
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ModulesInput {
    /// The modules to switch off for the whole company; all others are on.
    pub disabled_modules: Vec<String>,
}

/// The identity a user signs in with (OpenAPI schema `OidcSubjectInput`); no subject clears it.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct OidcSubjectInput {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub issuer: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub subject: Option<String>,
}

/// The stored company logo without the image (OpenAPI schema `CompanyLogoInfo`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CompanyLogoInfo {
    /// `image/png`, `image/jpeg` or `image/svg+xml`.
    pub content_type: String,
    pub size_bytes: i64,
    pub updated_at: DateTime<Utc>,
}

/// Company-wide presentation settings (OpenAPI schema `CompanySettingsInput`).
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct CompanySettingsInput {
    pub quotation_single_line_items: bool,
    /// Draft autosave interval in minutes (0 = disabled, 1..=120).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub autosave_minutes: Option<i32>,
}

/// The company's content languages (OpenAPI schema `CompanyLanguagesInput`).
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct CompanyLanguagesInput {
    /// ISO 639-1 codes in display order.
    pub languages: Vec<String>,
    /// One of `languages`.
    pub default_language: String,
}

/// An ISO 639-1 language with its names (OpenAPI schema `LanguageInfo`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LanguageInfo {
    pub code: String,
    pub english_name: String,
    /// The language's own name.
    pub name: String,
}

impl Client {
    /// Lists every member of the active company (`GET /api/v1/admin/users`).
    pub async fn list_admin_users(&self) -> Result<Vec<AdminUser>, ApiError> {
        self.get_json("/api/v1/admin/users", &()).await
    }

    /// Adds a member (`POST /api/v1/admin/users`); the server sends the invitation.
    pub async fn create_admin_user(&self, req: &AdminUserCreate) -> Result<AdminUser, ApiError> {
        self.post_json("/api/v1/admin/users", req).await
    }

    /// Changes a member's name, roles, module switches and status (`PUT /api/v1/admin/users/{id}`).
    pub async fn update_admin_user(
        &self,
        id: Uuid,
        req: &AdminUserUpdate,
    ) -> Result<AdminUser, ApiError> {
        self.put_json(&format!("/api/v1/admin/users/{id}"), req)
            .await
    }

    /// Sends the invitation again (`POST /api/v1/admin/users/{id}/invite`).
    pub async fn invite_admin_user(&self, id: Uuid) -> Result<(), ApiError> {
        self.post_empty(&format!("/api/v1/admin/users/{id}/invite"))
            .await
    }

    /// Sets or clears the identity a user signs in with (`PUT /api/v1/admin/users/{id}/oidc-subject`).
    pub async fn set_oidc_subject(&self, id: Uuid, req: &OidcSubjectInput) -> Result<(), ApiError> {
        self.put_json_empty(&format!("/api/v1/admin/users/{id}/oidc-subject"), req)
            .await
    }

    /// The role catalogue with the permissions of each role (`GET /api/v1/roles`).
    pub async fn list_roles(&self) -> Result<Vec<RoleInfo>, ApiError> {
        self.get_json("/api/v1/roles", &()).await
    }

    /// The module catalogue with the company's switches (`GET /api/v1/admin/modules`).
    pub async fn list_modules(&self) -> Result<Vec<ModuleInfo>, ApiError> {
        self.get_json("/api/v1/admin/modules", &()).await
    }

    /// Sets the company's module switches (`PUT /api/v1/admin/modules`); the server checks the
    /// dependencies and answers 422 with a message.
    pub async fn set_modules(&self, req: &ModulesInput) -> Result<Vec<ModuleInfo>, ApiError> {
        self.put_json("/api/v1/admin/modules", req).await
    }

    /// The company logo image (`GET /api/v1/admin/company/logo`); `None` when there is none (404).
    pub async fn company_logo(&self) -> Result<Option<Vec<u8>>, ApiError> {
        match self.get_bytes("/api/v1/admin/company/logo").await {
            Ok(bytes) => Ok(Some(bytes)),
            Err(err) if err.status() == Some(404) => Ok(None),
            Err(err) => Err(err),
        }
    }

    /// Uploads the company logo (`PUT /api/v1/admin/company/logo`, the body is the image).
    pub async fn upload_company_logo(&self, bytes: Vec<u8>) -> Result<CompanyLogoInfo, ApiError> {
        self.put_bytes("/api/v1/admin/company/logo", bytes).await
    }

    /// Removes the company logo (`DELETE /api/v1/admin/company/logo`).
    pub async fn delete_company_logo(&self) -> Result<(), ApiError> {
        self.delete_empty("/api/v1/admin/company/logo").await
    }

    /// Saves the company-wide settings (`PUT /api/v1/admin/company/settings`).
    pub async fn update_company_settings(
        &self,
        req: &CompanySettingsInput,
    ) -> Result<Company, ApiError> {
        self.put_json("/api/v1/admin/company/settings", req).await
    }

    /// Every ISO 639-1 language with its names (`GET /api/v1/languages`).
    pub async fn list_languages(&self) -> Result<Vec<LanguageInfo>, ApiError> {
        self.get_json("/api/v1/languages", &()).await
    }

    /// Replaces the company's content languages (`PUT /api/v1/admin/company/languages`).
    pub async fn set_company_languages(
        &self,
        req: &CompanyLanguagesInput,
    ) -> Result<Company, ApiError> {
        self.put_json("/api/v1/admin/company/languages", req).await
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decodes_admin_user_and_encodes_subject_input() {
        let user: AdminUser = serde_json::from_str(
            r#"{"user_id":"00000000-0000-0000-0000-000000000001","email":"a@example.com",
            "display_name":"A","roles":["admin"],"disabled_modules":["kb"],"active":true,
            "has_signed_in":false}"#,
        )
        .unwrap();
        assert_eq!(user.disabled_modules, vec!["kb"]);
        assert_eq!(
            serde_json::to_string(&OidcSubjectInput::default()).unwrap(),
            "{}"
        );
        let settings = CompanySettingsInput {
            quotation_single_line_items: true,
            autosave_minutes: Some(5),
        };
        assert_eq!(
            serde_json::to_string(&settings).unwrap(),
            r#"{"quotation_single_line_items":true,"autosave_minutes":5}"#
        );
    }
}
