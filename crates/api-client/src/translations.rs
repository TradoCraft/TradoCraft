//! Translation catalogues (ADR 0101): `GET /translations/{domain}`, `GET` and (administrators)
//! `PUT`/`DELETE /admin/translations/{domain}/{language}`.

use std::collections::BTreeMap;

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use crate::client::Client;
use crate::error::ApiError;

/// A language with texts in a domain (OpenAPI schema `CatalogueInfo`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CatalogueInfo {
    pub language: String,
    pub shipped: bool,
    pub company_entries: i64,
    #[serde(default)]
    pub updated_at: Option<DateTime<Utc>>,
}

/// One catalogue (OpenAPI schema `CatalogueDetail`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CatalogueDetail {
    /// `documents`, `mail`, `app` or `web`.
    pub domain: String,
    pub language: String,
    pub entries: BTreeMap<String, String>,
    pub shipped: BTreeMap<String, String>,
    pub source: BTreeMap<String, String>,
}

/// The texts a company adds or overrides (OpenAPI schema `CatalogueInput`).
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct CatalogueInput {
    pub entries: BTreeMap<String, String>,
}

impl Client {
    /// The languages with texts in `domain` (`GET /api/v1/translations/{domain}`).
    pub async fn list_catalogues(&self, domain: &str) -> Result<Vec<CatalogueInfo>, ApiError> {
        self.get_json(&format!("/api/v1/translations/{domain}"), &())
            .await
    }

    /// One catalogue (`GET /api/v1/translations/{domain}/{language}`).
    pub async fn get_catalogue(
        &self,
        domain: &str,
        language: &str,
    ) -> Result<CatalogueDetail, ApiError> {
        self.get_json(&format!("/api/v1/translations/{domain}/{language}"), &())
            .await
    }

    /// Replaces the company's texts (`PUT /api/v1/admin/translations/{domain}/{language}`).
    pub async fn put_catalogue(
        &self,
        domain: &str,
        language: &str,
        req: &CatalogueInput,
    ) -> Result<CatalogueDetail, ApiError> {
        self.put_json(
            &format!("/api/v1/admin/translations/{domain}/{language}"),
            req,
        )
        .await
    }

    /// Removes the company's texts (`DELETE /api/v1/admin/translations/{domain}/{language}`).
    pub async fn delete_catalogue(&self, domain: &str, language: &str) -> Result<(), ApiError> {
        self.delete_empty(&format!("/api/v1/admin/translations/{domain}/{language}"))
            .await
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decodes_a_catalogue() {
        let d: CatalogueDetail = serde_json::from_str(
            r#"{"domain":"web","language":"pt","entries":{"nav.products":"Produtos"},
            "shipped":{},"source":{}}"#,
        )
        .unwrap();
        assert_eq!(d.entries["nav.products"], "Produtos");
        let i: CatalogueInfo =
            serde_json::from_str(r#"{"language":"pt","shipped":false,"company_entries":3}"#)
                .unwrap();
        assert_eq!(i.updated_at, None);
    }
}
