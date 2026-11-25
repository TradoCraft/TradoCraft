use std::future::Future;
use std::pin::Pin;
use std::str::FromStr;

use rust_decimal::Decimal;
pub use tradocraft_api_client::{
    ApiError, Auth, Client, Company, Customer, CustomerPage, ListCustomersParams,
    ListProductsParams, Me, MeModule, Membership, Product, ProductPage, Session,
};
use uuid::Uuid;

/// Local boxed future alias so `ApiClient` compiles uniformly on both wasm32 and native.
pub type ApiFuture<'a, T> = Pin<Box<dyn Future<Output = Result<T, ApiError>> + 'a>>;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ConnectionMode {
    /// Live API via `tradocraft_api_client::Client` (`X-Dev-User` or `Authorization: Bearer`).
    Live(Session),
    /// Local mock mode for previewing the UI without a running API server.
    MockDemo,
}

impl Default for ConnectionMode {
    fn default() -> Self {
        Self::Live(Session::dev("", "sales@example.com"))
    }
}

/// Resolves an empty base URL to the browser's current origin so `reqwest` on `wasm32`
/// works seamlessly with Trunk's `/api` dev proxy.
pub fn resolve_base_url(raw: &str) -> String {
    let trimmed = raw.trim().trim_end_matches('/');
    if !trimmed.is_empty() {
        return trimmed.to_string();
    }
    #[cfg(target_arch = "wasm32")]
    {
        if let Some(origin) = web_sys::window().and_then(|w| w.location().origin().ok()) {
            return origin;
        }
    }
    String::new()
}

/// Thin client abstraction over `tradocraft_api_client::Client` and the offline `MockApiClient`.
pub trait ApiClient {
    fn sign_in<'a>(&'a self, base_url: &'a str, auth: Auth) -> ApiFuture<'a, (ConnectionMode, Me)>;
    fn get_me<'a>(&'a self, mode: &'a ConnectionMode) -> ApiFuture<'a, Me>;
    fn list_products<'a>(
        &'a self,
        mode: &'a ConnectionMode,
        params: &'a ListProductsParams,
    ) -> ApiFuture<'a, ProductPage>;
    fn list_customers<'a>(
        &'a self,
        mode: &'a ConnectionMode,
        params: &'a ListCustomersParams,
    ) -> ApiFuture<'a, CustomerPage>;
}

/// Live client delegating to `tradocraft_api_client::Client`, with offline `MockDemo` fallback.
#[derive(Debug, Default, Clone, Copy)]
pub struct WebApiClient;

impl ApiClient for WebApiClient {
    fn sign_in<'a>(&'a self, base_url: &'a str, auth: Auth) -> ApiFuture<'a, (ConnectionMode, Me)> {
        let raw_base = base_url.trim().trim_end_matches('/').to_string();
        Box::pin(async move {
            let mut client = Client::new(resolve_base_url(&raw_base));
            let me = client.sign_in(auth).await?;
            let mut stored = client.session().clone();
            stored.base_url = raw_base;
            Ok((ConnectionMode::Live(stored), me))
        })
    }

    fn get_me<'a>(&'a self, mode: &'a ConnectionMode) -> ApiFuture<'a, Me> {
        Box::pin(async move {
            match mode {
                ConnectionMode::MockDemo => MockApiClient.get_me(mode).await,
                ConnectionMode::Live(session) => {
                    Client::from_session(resolved_session(session)).me().await
                }
            }
        })
    }

    fn list_products<'a>(
        &'a self,
        mode: &'a ConnectionMode,
        params: &'a ListProductsParams,
    ) -> ApiFuture<'a, ProductPage> {
        Box::pin(async move {
            match mode {
                ConnectionMode::MockDemo => MockApiClient.list_products(mode, params).await,
                ConnectionMode::Live(session) => {
                    Client::from_session(resolved_session(session))
                        .list_products(params)
                        .await
                }
            }
        })
    }

    fn list_customers<'a>(
        &'a self,
        mode: &'a ConnectionMode,
        params: &'a ListCustomersParams,
    ) -> ApiFuture<'a, CustomerPage> {
        Box::pin(async move {
            match mode {
                ConnectionMode::MockDemo => MockApiClient.list_customers(mode, params).await,
                ConnectionMode::Live(session) => {
                    Client::from_session(resolved_session(session))
                        .list_customers(params)
                        .await
                }
            }
        })
    }
}

fn resolved_session(session: &Session) -> Session {
    let mut out = session.clone();
    out.base_url = resolve_base_url(&session.base_url);
    out
}

/// Offline demo client seeded with records matching `seed/dev_seed.sql`.
#[derive(Debug, Default, Clone, Copy)]
pub struct MockApiClient;

impl ApiClient for MockApiClient {
    fn sign_in<'a>(
        &'a self,
        _base_url: &'a str,
        _auth: Auth,
    ) -> ApiFuture<'a, (ConnectionMode, Me)> {
        Box::pin(async move {
            let me = self.get_me(&ConnectionMode::MockDemo).await?;
            Ok((ConnectionMode::MockDemo, me))
        })
    }

    fn get_me<'a>(&'a self, _mode: &'a ConnectionMode) -> ApiFuture<'a, Me> {
        Box::pin(async move {
            let company_id = Uuid::nil();
            Ok(Me {
                user_id: Uuid::nil(),
                email: "sales@example.com".to_string(),
                display_name: "Sales User (Demo)".to_string(),
                company: Company {
                    id: company_id,
                    name: "Demo Manufacturing BV".to_string(),
                    vat_number: Some("BE0123456749".to_string()),
                    street: "Industrieweg 1".to_string(),
                    postal_code: "9000".to_string(),
                    city: "Gent".to_string(),
                    country_code: "BE".to_string(),
                    currency: "EUR".to_string(),
                    email: Some("sales@example.com".to_string()),
                    phone: None,
                    iban: None,
                    default_language: "en".to_string(),
                    is_primary: true,
                    quotation_single_line_items: false,
                    autosave_minutes: 5,
                },
                roles: vec!["sales".to_string()],
                permissions: vec!["products.read".to_string(), "customers.read".to_string()],
                modules: vec![
                    MeModule {
                        code: "products".to_string(),
                        enabled: true,
                    },
                    MeModule {
                        code: "customers".to_string(),
                        enabled: true,
                    },
                    MeModule {
                        code: "sales".to_string(),
                        enabled: true,
                    },
                ],
                memberships: vec![Membership {
                    company_id,
                    company_name: "Demo Manufacturing BV".to_string(),
                    roles: vec!["sales".to_string()],
                    is_default: true,
                }],
            })
        })
    }

    fn list_products<'a>(
        &'a self,
        _mode: &'a ConnectionMode,
        params: &'a ListProductsParams,
    ) -> ApiFuture<'a, ProductPage> {
        Box::pin(async move {
            let mut items = demo_products();
            if let Some(q) = params.q.as_deref().map(str::trim).filter(|s| !s.is_empty()) {
                let needle = q.to_ascii_lowercase();
                items.retain(|p| {
                    p.code.to_ascii_lowercase().contains(&needle)
                        || p.name.to_ascii_lowercase().contains(&needle)
                });
            }
            if let Some(active) = params.active {
                items.retain(|p| p.active == active);
            }
            if let Some(pt) = params
                .product_type
                .as_deref()
                .map(str::trim)
                .filter(|s| !s.is_empty())
            {
                items.retain(|p| p.product_type == pt);
            }
            let total = items.len() as i64;
            let offset = params.offset.unwrap_or(0).max(0) as usize;
            let limit = params.limit.unwrap_or(50).clamp(1, 500) as usize;
            let page = items.into_iter().skip(offset).take(limit).collect();
            Ok(ProductPage { items: page, total })
        })
    }

    fn list_customers<'a>(
        &'a self,
        _mode: &'a ConnectionMode,
        params: &'a ListCustomersParams,
    ) -> ApiFuture<'a, CustomerPage> {
        Box::pin(async move {
            let mut items = demo_customers();
            if let Some(q) = params.q.as_deref().map(str::trim).filter(|s| !s.is_empty()) {
                let needle = q.to_ascii_lowercase();
                items.retain(|c| {
                    c.code.to_ascii_lowercase().contains(&needle)
                        || c.name.to_ascii_lowercase().contains(&needle)
                        || c.city.to_ascii_lowercase().contains(&needle)
                });
            }
            if let Some(active) = params.active {
                items.retain(|c| c.active == active);
            }
            let total = items.len() as i64;
            let offset = params.offset.unwrap_or(0).max(0) as usize;
            let limit = params.limit.unwrap_or(50).clamp(1, 500) as usize;
            let page = items.into_iter().skip(offset).take(limit).collect();
            Ok(CustomerPage { items: page, total })
        })
    }
}

fn demo_products() -> Vec<Product> {
    let vat = Decimal::from_str("21").unwrap_or_default();
    let rows = [
        (
            "00000000-0000-7000-8000-000000000301",
            "UNIT-100",
            "Process unit 100",
            "Standard process unit",
            "pcs",
            "manufactured",
            "serial",
            Some("UNITS"),
            true,
        ),
        (
            "00000000-0000-7000-8000-000000000302",
            "UNIT-200",
            "Process unit 200",
            "Configurable process unit",
            "pcs",
            "configurable",
            "none",
            Some("UNITS"),
            true,
        ),
        (
            "00000000-0000-7000-8000-000000000303",
            "PUMP-05",
            "Pump 0.5 kW",
            "Purchased pump",
            "pcs",
            "purchased",
            "serial",
            Some("COMP"),
            true,
        ),
        (
            "00000000-0000-7000-8000-000000000307",
            "FRAME-A",
            "Frame assembly",
            "Welded frame, made in house",
            "pcs",
            "manufactured",
            "none",
            Some("SUB"),
            true,
        ),
        (
            "00000000-0000-7000-8000-000000000308",
            "PROFILE-40",
            "Steel profile 40x40",
            "Sold and consumed per metre",
            "m",
            "purchased",
            "lot",
            Some("RAW"),
            true,
        ),
        (
            "00000000-0000-7000-8000-000000000305",
            "INSTALL",
            "Installation",
            "Installation on site, per hour",
            "h",
            "service",
            "none",
            Some("SVC"),
            true,
        ),
    ];

    rows.into_iter()
        .map(
            |(id, code, name, description, unit, product_type, tracking, family, active)| Product {
                id: Uuid::parse_str(id).unwrap_or_else(|_| Uuid::nil()),
                code: code.to_string(),
                name: name.to_string(),
                description: description.to_string(),
                unit: unit.to_string(),
                product_type: product_type.to_string(),
                vat_rate: vat,
                vat_category: "standard".to_string(),
                vat_rate_override: None,
                tracking: tracking.to_string(),
                family_id: None,
                family_code: family.map(str::to_string),
                non_discountable: false,
                price_on_request: false,
                price_is_indicative: false,
                included_in_turnover: None,
                active,
                default_media_id: None,
                default_media_kind: None,
                standard_cost: None,
                reorder_min: None,
                reorder_max: None,
                lead_time_days: None,
                barcode: None,
                packaging_category_id: None,
                packaging_category_code: None,
                length_mm: None,
                width_mm: None,
                height_mm: None,
                weight_g: None,
                default_production_remark: String::new(),
            },
        )
        .collect()
}

fn demo_customers() -> Vec<Customer> {
    let rows = [
        (
            "00000000-0000-7000-8000-000000000401",
            "C0001",
            "Alpha Installaties NV",
            Some("BE0000000097"),
            "domestic",
            "Antwerpen",
            "BE",
            "nl",
            Some("Z2"),
            Some(30),
        ),
        (
            "00000000-0000-7000-8000-000000000402",
            "C0002",
            "Bêta Industrie SA",
            Some("BE0000000196"),
            "domestic",
            "Liège",
            "BE",
            "fr",
            Some("Z3"),
            Some(60),
        ),
        (
            "00000000-0000-7000-8000-000000000403",
            "C0003",
            "Gamma Trading GmbH",
            Some("DE000000000"),
            "intra_eu",
            "Köln",
            "DE",
            "en",
            Some("Z1"),
            Some(30),
        ),
    ];

    rows.into_iter()
        .map(
            |(id, code, name, vat, regime, city, country, lang, zone, terms)| Customer {
                id: Uuid::parse_str(id).unwrap_or_else(|_| Uuid::nil()),
                version: 1,
                code: code.to_string(),
                name: name.to_string(),
                vat_number: vat.map(str::to_string),
                vat_regime: regime.to_string(),
                email: None,
                phone: None,
                street: String::new(),
                postal_code: String::new(),
                city: city.to_string(),
                country_code: country.to_string(),
                language: lang.to_string(),
                active: true,
                price_zone_id: None,
                price_zone_code: zone.map(str::to_string),
                discount_percent: None,
                payment_terms_days: terms,
            },
        )
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn resolves_base_url_cleanly() {
        assert_eq!(
            resolve_base_url(" http://127.0.0.1:8080/ "),
            "http://127.0.0.1:8080"
        );
        assert_eq!(resolve_base_url(""), "");
    }

    #[test]
    fn parses_product_page_json_with_shared_dto() {
        let json = r#"{
            "items": [{
                "id": "00000000-0000-7000-8000-000000000301",
                "code": "UNIT-100",
                "name": "Process unit 100",
                "description": "Standard process unit",
                "unit": "pcs",
                "product_type": "manufactured",
                "vat_rate": "21",
                "vat_category": "standard",
                "tracking": "serial",
                "family_code": null,
                "non_discountable": false,
                "price_on_request": false,
                "price_is_indicative": false,
                "active": true,
                "standard_cost": null,
                "barcode": null
            }],
            "total": 1
        }"#;
        let page: ProductPage = serde_json::from_str(json).expect("valid ProductPage JSON");
        assert_eq!(page.total, 1);
        assert_eq!(page.items[0].code, "UNIT-100");
        assert_eq!(page.items[0].vat_rate, Decimal::from(21));
    }
}
