//! Country VAT rate rules (`/api/v1/vat-rates`, `/api/v1/admin/vat-rates`): rates per country and
//! category with an effective date range and an optional building-age threshold.

use chrono::{DateTime, NaiveDate, Utc};
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::client::Client;
use crate::error::ApiError;

/// A country VAT rate rule (OpenAPI schema `CountryVatRate`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CountryVatRate {
    pub id: Uuid,
    pub country_code: String,
    pub category: String,
    pub rate: Decimal,
    #[serde(default)]
    pub min_building_age_years: Option<i32>,
    pub start_date: NaiveDate,
    #[serde(default)]
    pub end_date: Option<NaiveDate>,
    pub notes: String,
    pub updated_at: DateTime<Utc>,
}

/// Request payload for creating or updating a rule (OpenAPI schema `CountryVatRateInput`).
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct CountryVatRateInput {
    pub country_code: String,
    pub category: String,
    pub rate: Decimal,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub min_building_age_years: Option<i32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub start_date: Option<NaiveDate>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub end_date: Option<NaiveDate>,
    #[serde(default)]
    pub notes: String,
    /// On create: end any earlier open rule of the same country, category and age threshold.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub close_previous: Option<bool>,
}

impl Client {
    /// Every VAT rate rule (`GET /api/v1/vat-rates`).
    pub async fn list_vat_rates(&self) -> Result<Vec<CountryVatRate>, ApiError> {
        self.get_json("/api/v1/vat-rates", &()).await
    }

    /// Adds a rule (`POST /api/v1/admin/vat-rates`).
    pub async fn create_vat_rate(
        &self,
        req: &CountryVatRateInput,
    ) -> Result<CountryVatRate, ApiError> {
        self.post_json("/api/v1/admin/vat-rates", req).await
    }

    /// Changes a rule (`PUT /api/v1/admin/vat-rates/{id}`).
    pub async fn update_vat_rate(
        &self,
        id: Uuid,
        req: &CountryVatRateInput,
    ) -> Result<CountryVatRate, ApiError> {
        self.put_json(&format!("/api/v1/admin/vat-rates/{id}"), req)
            .await
    }

    /// Deletes a rule (`DELETE /api/v1/admin/vat-rates/{id}`).
    pub async fn delete_vat_rate(&self, id: Uuid) -> Result<(), ApiError> {
        self.delete_empty(&format!("/api/v1/admin/vat-rates/{id}"))
            .await
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decodes_rate_and_encodes_input() {
        let r: CountryVatRate = serde_json::from_str(
            r#"{"id":"00000000-0000-0000-0000-000000000001","country_code":"BE","category":"standard",
            "rate":"21.00","start_date":"2020-01-01","end_date":null,"notes":"",
            "updated_at":"2026-01-01T00:00:00Z"}"#,
        )
        .unwrap();
        assert_eq!(r.rate.to_string(), "21.00");
        let input = CountryVatRateInput {
            country_code: "BE".into(),
            category: "reduced".into(),
            rate: "6".parse().unwrap(),
            start_date: NaiveDate::from_ymd_opt(2026, 1, 1),
            close_previous: Some(true),
            ..CountryVatRateInput::default()
        };
        assert_eq!(
            serde_json::to_string(&input).unwrap(),
            r#"{"country_code":"BE","category":"reduced","rate":"6","start_date":"2026-01-01","notes":"","close_previous":true}"#
        );
    }
}
