//! First-company bootstrap setup DTOs and unauthenticated endpoints (`/api/v1/setup/...`, ADR 0047).

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::auth::Company;
use crate::client::Client;
use crate::error::ApiError;

/// Answer from `GET /api/v1/setup/status` (no sign-in needed).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SetupStatus {
    /// True while no company exists and bootstrapping is enabled on this server.
    pub needs_setup: bool,
    /// True when `POST /api/v1/setup/bootstrap` must carry the `BOOTSTRAP_TOKEN`.
    pub token_required: bool,
    /// `dev` (the admin e-mail becomes the dev user) or `oidc` (sign in through the identity provider).
    pub auth_mode: String,
}

impl SetupStatus {
    /// True when the administrator can be signed in directly using development authentication.
    pub fn is_dev(&self) -> bool {
        self.auth_mode == "dev"
    }
}

/// Everything needed to create a company and its first administrator (OpenAPI schema `ProvisionSpec`).
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProvisionSpec {
    pub name: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub legal_name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub vat_number: Option<String>,
    pub country_code: String,
    pub currency: String,
    pub default_language: String,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub languages: Vec<String>,
    pub admin_email: String,
    pub admin_display_name: String,
}

/// Body of `POST /api/v1/setup/bootstrap` (OpenAPI schema `BootstrapRequest`).
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct BootstrapRequest {
    pub name: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub legal_name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub vat_number: Option<String>,
    pub country_code: String,
    pub currency: String,
    pub default_language: String,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub languages: Vec<String>,
    pub admin_email: String,
    pub admin_display_name: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub token: Option<String>,
}

/// The first administrator, as created (OpenAPI schema `AdminSummary`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AdminSummary {
    pub user_id: Uuid,
    pub email: String,
    pub display_name: String,
    pub roles: Vec<String>,
}

/// Result of a successful bootstrap (OpenAPI schema `BootstrapResult`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct BootstrapResult {
    pub company: Company,
    pub admin: AdminSummary,
    /// `dev` or `oidc`: how the administrator signs in.
    pub auth_mode: String,
}

impl BootstrapResult {
    /// True when the administrator can sign in directly using development authentication.
    pub fn is_dev(&self) -> bool {
        self.auth_mode == "dev"
    }
}

impl Client {
    /// Asks whether this server needs first-company setup (`GET /api/v1/setup/status`).
    pub async fn setup_status(&self) -> Result<SetupStatus, ApiError> {
        self.get_json_unauthenticated("/api/v1/setup/status", &())
            .await
    }

    /// Creates the first company and its administrator (`POST /api/v1/setup/bootstrap`).
    ///
    /// Refuses to transmit a non-empty setup token over plain HTTP to non-loopback hosts.
    pub async fn bootstrap_company(
        &self,
        req: &BootstrapRequest,
    ) -> Result<BootstrapResult, ApiError> {
        if req.token.as_deref().is_some_and(|t| !t.trim().is_empty()) {
            self.validate_secret_base_url("setup token")?;
            return self
                .post_json_without_redirect("/api/v1/setup/bootstrap", req)
                .await;
        }
        self.post_json_unauthenticated("/api/v1/setup/bootstrap", req)
            .await
    }
}

#[cfg(test)]
mod tests {
    use std::future::Future;
    use std::pin::Pin;
    use std::task::{Context, Poll, RawWaker, RawWakerVTable, Waker};

    use super::*;

    fn poll_once<F: Future>(fut: F) -> F::Output {
        fn no_op(_: *const ()) {}
        fn clone(ptr: *const ()) -> RawWaker {
            RawWaker::new(ptr, &VTABLE)
        }
        static VTABLE: RawWakerVTable = RawWakerVTable::new(clone, no_op, no_op, no_op);
        let waker = unsafe { Waker::from_raw(RawWaker::new(std::ptr::null(), &VTABLE)) };
        let mut cx = Context::from_waker(&waker);
        let mut pinned: Pin<Box<F>> = Box::pin(fut);
        match pinned.as_mut().poll(&mut cx) {
            Poll::Ready(val) => val,
            Poll::Pending => panic!("expected future to resolve immediately"),
        }
    }

    #[test]
    fn setup_status_and_bootstrap_serde_roundtrip() {
        let status: SetupStatus =
            serde_json::from_str(r#"{"needs_setup":true,"token_required":true,"auth_mode":"dev"}"#)
                .unwrap();
        assert!(status.needs_setup);
        assert!(status.token_required);
        assert!(status.is_dev());

        let req = BootstrapRequest {
            name: "Acme BV".into(),
            legal_name: None,
            vat_number: None,
            country_code: "BE".into(),
            currency: "EUR".into(),
            default_language: "en".into(),
            languages: vec![],
            admin_email: "admin@acme.test".into(),
            admin_display_name: "Admin".into(),
            token: None,
        };
        let encoded = serde_json::to_value(&req).unwrap();
        assert_eq!(encoded["name"], "Acme BV");
        assert!(encoded.get("legal_name").is_none());
        assert!(encoded.get("vat_number").is_none());
        assert!(encoded.get("languages").is_none());
        assert!(encoded.get("token").is_none());

        let result: BootstrapResult = serde_json::from_str(
            r#"{
                "company": {
                    "id": "01900000-0000-7000-8000-000000000020",
                    "name": "Acme BV",
                    "vat_number": null,
                    "street": "",
                    "postal_code": "",
                    "city": "",
                    "country_code": "BE",
                    "currency": "EUR",
                    "email": null,
                    "phone": null,
                    "iban": null,
                    "default_language": "en",
                    "languages": ["en"],
                    "is_primary": true,
                    "quotation_single_line_items": true,
                    "autosave_minutes": 5
                },
                "admin": {
                    "user_id": "01900000-0000-7000-8000-000000000010",
                    "email": "admin@acme.test",
                    "display_name": "Admin",
                    "roles": ["admin"]
                },
                "auth_mode": "oidc"
            }"#,
        )
        .unwrap();
        assert_eq!(result.company.name, "Acme BV");
        assert_eq!(result.admin.roles, vec!["admin"]);
        assert!(!result.is_dev());
    }

    #[test]
    fn refuses_setup_token_over_plain_http_to_remote_host() {
        let client = Client::new("http://example.com");
        let req = BootstrapRequest {
            name: "Acme BV".into(),
            country_code: "BE".into(),
            currency: "EUR".into(),
            default_language: "en".into(),
            admin_email: "admin@acme.test".into(),
            admin_display_name: "Admin".into(),
            token: Some("secret-token".into()),
            ..BootstrapRequest::default()
        };
        let err = poll_once(client.bootstrap_company(&req)).unwrap_err();
        assert!(matches!(err, ApiError::InvalidConfig(_)));
    }
}
