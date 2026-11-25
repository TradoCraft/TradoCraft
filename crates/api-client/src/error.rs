//! Error types returned by [`crate::Client`].

use serde::{Deserialize, Serialize};
use thiserror::Error;

/// Error body returned by every TradoCraft API endpoint.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ErrorBody {
    /// Machine-readable code: `unauthorized`, `forbidden`, `not_found`, `validation`,
    /// `conflict`, `internal`.
    pub error: String,
    /// Stable identifier for errors a client must tell apart (for example
    /// `repair_status_changed` or `record_changed`); absent for the rest.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub code: Option<String>,
    pub message: String,
}

/// Errors returned by TradoCraft API client operations.
#[derive(Debug, Error)]
pub enum ApiError {
    /// The server returned a non-2xx HTTP status code.
    #[error("HTTP {status}: {}", body.as_ref().map(|b| b.message.as_str()).unwrap_or(raw_body.as_str()))]
    Http {
        status: u16,
        body: Option<ErrorBody>,
        raw_body: String,
    },

    /// Transport-level failure (connection error, DNS, TLS, browser fetch failure).
    #[error("request failed: {0}")]
    Transport(#[from] reqwest::Error),

    /// Response JSON could not be deserialized into the expected DTO.
    #[error("failed to decode response JSON: {message}")]
    Decode { message: String, body: String },

    /// Invalid client configuration or header value.
    #[error("invalid client configuration: {0}")]
    InvalidConfig(String),
}

impl ApiError {
    /// HTTP status code if the server responded with an error status.
    pub fn status(&self) -> Option<u16> {
        match self {
            Self::Http { status, .. } => Some(*status),
            _ => None,
        }
    }

    /// Parsed [`ErrorBody`] when the server returned a structured error JSON payload.
    pub fn error_body(&self) -> Option<&ErrorBody> {
        match self {
            Self::Http { body, .. } => body.as_ref(),
            _ => None,
        }
    }

    /// Stable machine-readable `code` from [`ErrorBody`], if present.
    pub fn code(&self) -> Option<&str> {
        self.error_body().and_then(|b| b.code.as_deref())
    }

    /// User-facing error message, mirroring the Flutter client's `errorMessage`.
    pub fn user_message(&self) -> String {
        match self {
            Self::Http { status, body, .. } => body
                .as_ref()
                .map(|b| b.message.clone())
                .unwrap_or_else(|| format!("Server error {status}.")),
            Self::Transport(err) => format!("Cannot reach the server ({err})."),
            Self::Decode { message, .. } => format!("Invalid response from server ({message})."),
            Self::InvalidConfig(msg) => msg.clone(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn deserialize_error_body_with_and_without_code() {
        let with_code: ErrorBody = serde_json::from_str(
            r#"{"error":"conflict","code":"record_changed","message":"Record was modified."}"#,
        )
        .unwrap();
        assert_eq!(with_code.error, "conflict");
        assert_eq!(with_code.code.as_deref(), Some("record_changed"));
        assert_eq!(with_code.message, "Record was modified.");

        let without_code: ErrorBody =
            serde_json::from_str(r#"{"error":"unauthorized","message":"not authenticated"}"#)
                .unwrap();
        assert_eq!(without_code.error, "unauthorized");
        assert_eq!(without_code.code, None);
        assert_eq!(without_code.message, "not authenticated");
    }

    #[test]
    fn api_error_helpers_extract_status_and_code() {
        let err = ApiError::Http {
            status: 409,
            body: Some(ErrorBody {
                error: "conflict".into(),
                code: Some("record_changed".into()),
                message: "Customer was modified".into(),
            }),
            raw_body: String::new(),
        };
        assert_eq!(err.status(), Some(409));
        assert_eq!(err.code(), Some("record_changed"));
        assert_eq!(err.user_message(), "Customer was modified");
    }
}
