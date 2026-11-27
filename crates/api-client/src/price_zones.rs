//! Price zones (`/api/v1/price-zones`): the sales price levels customers are put in.

use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::client::Client;
use crate::error::ApiError;

/// A price zone (OpenAPI schema `PriceZone`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PriceZone {
    pub id: Uuid,
    pub code: String,
    pub name: String,
    pub sort_order: i32,
    /// Relative to the first zone (e.g. 1.15 = +15%).
    #[serde(default)]
    pub default_multiplier: Option<Decimal>,
    /// A rounding step such as `0.05`; none or `none` for no rounding.
    #[serde(default)]
    pub default_rounding: Option<String>,
}

/// Create/update body of a price zone (OpenAPI schema `PriceZoneInput`).
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct PriceZoneInput {
    pub code: String,
    pub name: String,
    #[serde(default)]
    pub sort_order: i32,
    #[serde(default)]
    pub default_multiplier: Option<Decimal>,
    #[serde(default)]
    pub default_rounding: Option<String>,
}

impl Client {
    /// The price zones in sort order (`GET /api/v1/price-zones`).
    pub async fn list_price_zones(&self) -> Result<Vec<PriceZone>, ApiError> {
        self.get_json("/api/v1/price-zones", &()).await
    }

    /// Adds a zone (`POST /api/v1/price-zones`).
    pub async fn create_price_zone(&self, req: &PriceZoneInput) -> Result<PriceZone, ApiError> {
        self.post_json("/api/v1/price-zones", req).await
    }

    /// Changes a zone (`PUT /api/v1/price-zones/{id}`).
    pub async fn update_price_zone(
        &self,
        id: Uuid,
        req: &PriceZoneInput,
    ) -> Result<PriceZone, ApiError> {
        self.put_json(&format!("/api/v1/price-zones/{id}"), req)
            .await
    }

    /// Deletes a zone (`DELETE /api/v1/price-zones/{id}`); refused while prices or customers use it.
    pub async fn delete_price_zone(&self, id: Uuid) -> Result<(), ApiError> {
        self.delete_empty(&format!("/api/v1/price-zones/{id}"))
            .await
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn encodes_input_with_null_multiplier() {
        let input = PriceZoneInput {
            code: "B".into(),
            name: "Export".into(),
            sort_order: 2,
            ..PriceZoneInput::default()
        };
        assert_eq!(
            serde_json::to_string(&input).unwrap(),
            r#"{"code":"B","name":"Export","sort_order":2,"default_multiplier":null,"default_rounding":null}"#
        );
        let z: PriceZone = serde_json::from_str(
            r#"{"id":"00000000-0000-0000-0000-000000000001","code":"A","name":"Home",
            "sort_order":0,"default_multiplier":"1.1500","default_rounding":"0.05"}"#,
        )
        .unwrap();
        assert_eq!(
            z.default_multiplier.unwrap().normalize().to_string(),
            "1.15"
        );
    }
}
