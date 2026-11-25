use std::cell::RefCell;
use std::future::Future;
use std::pin::Pin;
use std::str::FromStr;

use rust_decimal::Decimal;
pub use tradocraft_api_client::{
    ApiError, Auth, Client, Company, CreateCustomerRequest, CreateProductRequest, Customer,
    CustomerInput, CustomerPage, ErrorBody, ListCustomersParams, ListProductsParams, Me, MeModule,
    Membership, Product, ProductInput, ProductPage, Session, UpdateCustomerRequest,
    UpdateProductRequest,
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
    fn get_product<'a>(&'a self, mode: &'a ConnectionMode, id: Uuid) -> ApiFuture<'a, Product>;
    fn create_product<'a>(
        &'a self,
        mode: &'a ConnectionMode,
        req: &'a CreateProductRequest,
    ) -> ApiFuture<'a, Product>;
    fn update_product<'a>(
        &'a self,
        mode: &'a ConnectionMode,
        id: Uuid,
        req: &'a UpdateProductRequest,
    ) -> ApiFuture<'a, Product>;
    fn list_customers<'a>(
        &'a self,
        mode: &'a ConnectionMode,
        params: &'a ListCustomersParams,
    ) -> ApiFuture<'a, CustomerPage>;
    fn get_customer<'a>(&'a self, mode: &'a ConnectionMode, id: Uuid) -> ApiFuture<'a, Customer>;
    fn create_customer<'a>(
        &'a self,
        mode: &'a ConnectionMode,
        req: &'a CreateCustomerRequest,
    ) -> ApiFuture<'a, Customer>;
    fn update_customer<'a>(
        &'a self,
        mode: &'a ConnectionMode,
        id: Uuid,
        req: &'a UpdateCustomerRequest,
    ) -> ApiFuture<'a, Customer>;
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

    fn get_product<'a>(&'a self, mode: &'a ConnectionMode, id: Uuid) -> ApiFuture<'a, Product> {
        Box::pin(async move {
            match mode {
                ConnectionMode::MockDemo => MockApiClient.get_product(mode, id).await,
                ConnectionMode::Live(session) => {
                    Client::from_session(resolved_session(session))
                        .get_product(id)
                        .await
                }
            }
        })
    }

    fn create_product<'a>(
        &'a self,
        mode: &'a ConnectionMode,
        req: &'a CreateProductRequest,
    ) -> ApiFuture<'a, Product> {
        Box::pin(async move {
            match mode {
                ConnectionMode::MockDemo => MockApiClient.create_product(mode, req).await,
                ConnectionMode::Live(session) => {
                    Client::from_session(resolved_session(session))
                        .create_product(req)
                        .await
                }
            }
        })
    }

    fn update_product<'a>(
        &'a self,
        mode: &'a ConnectionMode,
        id: Uuid,
        req: &'a UpdateProductRequest,
    ) -> ApiFuture<'a, Product> {
        Box::pin(async move {
            match mode {
                ConnectionMode::MockDemo => MockApiClient.update_product(mode, id, req).await,
                ConnectionMode::Live(session) => {
                    Client::from_session(resolved_session(session))
                        .update_product(id, req)
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

    fn get_customer<'a>(&'a self, mode: &'a ConnectionMode, id: Uuid) -> ApiFuture<'a, Customer> {
        Box::pin(async move {
            match mode {
                ConnectionMode::MockDemo => MockApiClient.get_customer(mode, id).await,
                ConnectionMode::Live(session) => {
                    Client::from_session(resolved_session(session))
                        .get_customer(id)
                        .await
                }
            }
        })
    }

    fn create_customer<'a>(
        &'a self,
        mode: &'a ConnectionMode,
        req: &'a CreateCustomerRequest,
    ) -> ApiFuture<'a, Customer> {
        Box::pin(async move {
            match mode {
                ConnectionMode::MockDemo => MockApiClient.create_customer(mode, req).await,
                ConnectionMode::Live(session) => {
                    Client::from_session(resolved_session(session))
                        .create_customer(req)
                        .await
                }
            }
        })
    }

    fn update_customer<'a>(
        &'a self,
        mode: &'a ConnectionMode,
        id: Uuid,
        req: &'a UpdateCustomerRequest,
    ) -> ApiFuture<'a, Customer> {
        Box::pin(async move {
            match mode {
                ConnectionMode::MockDemo => MockApiClient.update_customer(mode, id, req).await,
                ConnectionMode::Live(session) => {
                    Client::from_session(resolved_session(session))
                        .update_customer(id, req)
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

struct MockStore {
    products: Vec<Product>,
    customers: Vec<Customer>,
    next_id: u128,
}

impl MockStore {
    fn seeded() -> Self {
        Self {
            products: demo_products(),
            customers: demo_customers(),
            next_id: 0x0000_0000_0000_7000_8000_0000_0000_1000,
        }
    }

    fn alloc_id(&mut self) -> Uuid {
        let id = Uuid::from_u128(self.next_id);
        self.next_id += 1;
        id
    }
}

thread_local! {
    static MOCK_STORE: RefCell<MockStore> = RefCell::new(MockStore::seeded());
}

fn mock_http_error(status: u16, error: &str, code: Option<&str>, message: &str) -> ApiError {
    ApiError::Http {
        status,
        body: Some(ErrorBody {
            error: error.to_string(),
            code: code.map(str::to_string),
            message: message.to_string(),
        }),
        raw_body: message.to_string(),
    }
}

fn validate_product_input(req: &ProductInput) -> Result<(), ApiError> {
    if req.code.trim().is_empty() || req.name.trim().is_empty() {
        return Err(mock_http_error(
            400,
            "validation",
            None,
            "code and name are required",
        ));
    }
    if req.product_type == "service" && req.tracking != "none" {
        return Err(mock_http_error(
            400,
            "validation",
            None,
            "services cannot be tracked",
        ));
    }
    Ok(())
}

fn apply_product_input(id: Uuid, req: &ProductInput, existing: Option<&Product>) -> Product {
    let vat_category = req
        .vat_category
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .unwrap_or("standard")
        .to_string();
    let vat_rate =
        req.vat_rate_override
            .or(req.vat_rate)
            .unwrap_or_else(|| match vat_category.as_str() {
                "intermediate" => Decimal::from(12),
                "reduced" => Decimal::from(6),
                "zero" => Decimal::ZERO,
                _ => Decimal::from(21),
            });
    let included_in_turnover = match req.included_in_turnover {
        Some(v) => v,
        None => existing.and_then(|p| p.included_in_turnover),
    };
    Product {
        id,
        code: req.code.trim().to_string(),
        name: req.name.trim().to_string(),
        description: req.description.clone(),
        unit: req.unit.clone(),
        product_type: req.product_type.clone(),
        vat_rate,
        vat_category,
        vat_rate_override: req.vat_rate_override,
        tracking: req.tracking.clone(),
        family_id: req.family_id,
        family_code: existing.and_then(|p| p.family_code.clone()),
        non_discountable: req.non_discountable,
        price_on_request: req.price_on_request,
        price_is_indicative: req.price_is_indicative,
        included_in_turnover,
        active: req.active,
        default_media_id: existing.and_then(|p| p.default_media_id),
        default_media_kind: existing.and_then(|p| p.default_media_kind.clone()),
        standard_cost: req.standard_cost,
        reorder_min: req.reorder_min,
        reorder_max: req.reorder_max,
        lead_time_days: req.lead_time_days,
        barcode: req
            .barcode
            .as_deref()
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .map(str::to_string),
        packaging_category_id: req.packaging_category_id,
        packaging_category_code: existing.and_then(|p| p.packaging_category_code.clone()),
        length_mm: req.length_mm,
        width_mm: req.width_mm,
        height_mm: req.height_mm,
        weight_g: req.weight_g,
        default_production_remark: req.default_production_remark.trim().to_string(),
    }
}

fn validate_customer_input(req: &CustomerInput) -> Result<(), ApiError> {
    if req.code.trim().is_empty() || req.name.trim().is_empty() {
        return Err(mock_http_error(
            400,
            "validation",
            None,
            "code and name are required",
        ));
    }
    if req.country_code.trim().len() != 2 {
        return Err(mock_http_error(
            400,
            "validation",
            None,
            "country_code must be a 2-letter code",
        ));
    }
    if req.payment_terms_days < 0 {
        return Err(mock_http_error(
            400,
            "validation",
            None,
            "payment_terms_days cannot be negative",
        ));
    }
    Ok(())
}

fn mock_zone_code(zone_id: Uuid) -> Option<String> {
    match zone_id.to_string().as_str() {
        "00000000-0000-7000-8000-000000000201" => Some("Z1".to_string()),
        "00000000-0000-7000-8000-000000000202" => Some("Z2".to_string()),
        "00000000-0000-7000-8000-000000000203" => Some("Z3".to_string()),
        _ => None,
    }
}

fn apply_customer_input(id: Uuid, version: i64, req: &CustomerInput) -> Customer {
    let vat_regime = req
        .vat_regime
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_string)
        .unwrap_or_else(|| {
            if req.country_code.eq_ignore_ascii_case("BE") {
                "domestic".to_string()
            } else {
                "intra_eu".to_string()
            }
        });
    Customer {
        id,
        version,
        code: req.code.trim().to_string(),
        name: req.name.trim().to_string(),
        vat_number: req
            .vat_number
            .as_deref()
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .map(str::to_string),
        vat_regime,
        email: req
            .email
            .as_deref()
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .map(str::to_string),
        phone: req
            .phone
            .as_deref()
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .map(str::to_string),
        street: req.street.trim().to_string(),
        postal_code: req.postal_code.trim().to_string(),
        city: req.city.trim().to_string(),
        country_code: req.country_code.trim().to_ascii_uppercase(),
        language: req.language.trim().to_ascii_lowercase(),
        active: req.active,
        price_zone_id: Some(req.price_zone_id),
        price_zone_code: mock_zone_code(req.price_zone_id),
        discount_percent: Some(req.discount_percent),
        payment_terms_days: Some(req.payment_terms_days),
    }
}

fn is_combining_mark(ch: char) -> bool {
    matches!(
        ch as u32,
        0x0300..=0x036F
            | 0x1AB0..=0x1AFF
            | 0x1DC0..=0x1DFF
            | 0x20D0..=0x20FF
            | 0xFE20..=0xFE2F
    )
}

fn fold_latin_base(ch: char) -> &'static str {
    match ch {
        'á' | 'à' | 'â' | 'ä' | 'ã' | 'å' | 'ā' | 'ă' | 'ą' | 'ǎ' | 'ǻ' => "a",
        'æ' | 'ǽ' => "ae",
        'ç' | 'ć' | 'ĉ' | 'ċ' | 'č' => "c",
        'ď' | 'đ' | 'ð' => "d",
        'é' | 'è' | 'ê' | 'ë' | 'ē' | 'ĕ' | 'ė' | 'ę' | 'ě' => "e",
        'ĝ' | 'ğ' | 'ġ' | 'ģ' => "g",
        'ĥ' | 'ħ' => "h",
        'í' | 'ì' | 'î' | 'ï' | 'ĩ' | 'ī' | 'ĭ' | 'į' | 'ı' | 'ǐ' => "i",
        'ĳ' => "ij",
        'ĵ' => "j",
        'ķ' | 'ĸ' => "k",
        'ĺ' | 'ļ' | 'ľ' | 'ŀ' | 'ł' => "l",
        'ñ' | 'ń' | 'ņ' | 'ň' | 'ŉ' => "n",
        'ó' | 'ò' | 'ô' | 'ö' | 'õ' | 'ø' | 'ō' | 'ŏ' | 'ő' | 'ǒ' | 'ǿ' => "o",
        'œ' => "oe",
        'ŕ' | 'ŗ' | 'ř' => "r",
        'ś' | 'ŝ' | 'ş' | 'š' | 'ſ' => "s",
        'ß' => "ss",
        'ţ' | 'ť' | 'ŧ' => "t",
        'ú' | 'ù' | 'û' | 'ü' | 'ũ' | 'ū' | 'ŭ' | 'ů' | 'ű' | 'ų' | 'ǔ' | 'ǖ' | 'ǘ' | 'ǚ' | 'ǜ' => {
            "u"
        }
        'ŵ' => "w",
        'ý' | 'ÿ' | 'ŷ' => "y",
        'ź' | 'ż' | 'ž' => "z",
        _ => "",
    }
}

/// Normalizes text for accent- and case-insensitive substring matching (`MockApiClient`).
fn fold_search_text(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    for ch in input.chars() {
        for lower in ch.to_lowercase() {
            if is_combining_mark(lower) {
                continue;
            }
            let folded = fold_latin_base(lower);
            if folded.is_empty() {
                out.push(lower);
            } else {
                out.push_str(folded);
            }
        }
    }
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
                permissions: vec![
                    "products.read".to_string(),
                    "products.write".to_string(),
                    "customers.read".to_string(),
                    "customers.write".to_string(),
                ],
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
            let mut items = MOCK_STORE.with(|store| store.borrow().products.clone());
            if let Some(q) = params.q.as_deref().map(str::trim).filter(|s| !s.is_empty()) {
                let needle = fold_search_text(q);
                if !needle.is_empty() {
                    items.retain(|p| {
                        fold_search_text(&p.code).contains(&needle)
                            || fold_search_text(&p.name).contains(&needle)
                    });
                }
            }
            if let Some(active) = params.active {
                items.retain(|p| p.active == active);
            }
            if let Some(raw_types) = params.product_type.as_deref() {
                let types: Vec<&str> = raw_types
                    .split(',')
                    .map(str::trim)
                    .filter(|s| !s.is_empty())
                    .collect();
                if !types.is_empty() {
                    items.retain(|p| types.contains(&p.product_type.as_str()));
                }
            }
            let total = items.len() as i64;
            let offset = params.offset.unwrap_or(0).max(0) as usize;
            let limit = params.limit.unwrap_or(50).clamp(1, 500) as usize;
            let page = items.into_iter().skip(offset).take(limit).collect();
            Ok(ProductPage { items: page, total })
        })
    }

    fn get_product<'a>(&'a self, _mode: &'a ConnectionMode, id: Uuid) -> ApiFuture<'a, Product> {
        Box::pin(async move {
            MOCK_STORE.with(|store| {
                store
                    .borrow()
                    .products
                    .iter()
                    .find(|p| p.id == id)
                    .cloned()
                    .ok_or_else(|| mock_http_error(404, "not_found", None, "Product not found."))
            })
        })
    }

    fn create_product<'a>(
        &'a self,
        _mode: &'a ConnectionMode,
        req: &'a CreateProductRequest,
    ) -> ApiFuture<'a, Product> {
        let req = req.clone();
        Box::pin(async move {
            validate_product_input(&req)?;
            let code_trimmed = req.code.trim();
            MOCK_STORE.with(|store| {
                let mut store = store.borrow_mut();
                if store
                    .products
                    .iter()
                    .any(|p| p.code.eq_ignore_ascii_case(code_trimmed))
                {
                    return Err(mock_http_error(
                        409,
                        "conflict",
                        None,
                        &format!("Product code '{code_trimmed}' already exists."),
                    ));
                }
                let id = store.alloc_id();
                let created = apply_product_input(id, &req, None);
                store.products.push(created.clone());
                Ok(created)
            })
        })
    }

    fn update_product<'a>(
        &'a self,
        _mode: &'a ConnectionMode,
        id: Uuid,
        req: &'a UpdateProductRequest,
    ) -> ApiFuture<'a, Product> {
        let req = req.clone();
        Box::pin(async move {
            validate_product_input(&req)?;
            let code_trimmed = req.code.trim();
            MOCK_STORE.with(|store| {
                let mut store = store.borrow_mut();
                if store
                    .products
                    .iter()
                    .any(|p| p.id != id && p.code.eq_ignore_ascii_case(code_trimmed))
                {
                    return Err(mock_http_error(
                        409,
                        "conflict",
                        None,
                        &format!("Product code '{code_trimmed}' already exists."),
                    ));
                }
                let Some(idx) = store.products.iter().position(|p| p.id == id) else {
                    return Err(mock_http_error(
                        404,
                        "not_found",
                        None,
                        "Product not found.",
                    ));
                };
                let updated = apply_product_input(id, &req, Some(&store.products[idx]));
                store.products[idx] = updated.clone();
                Ok(updated)
            })
        })
    }

    fn list_customers<'a>(
        &'a self,
        _mode: &'a ConnectionMode,
        params: &'a ListCustomersParams,
    ) -> ApiFuture<'a, CustomerPage> {
        Box::pin(async move {
            let mut items = MOCK_STORE.with(|store| store.borrow().customers.clone());
            if let Some(q) = params.q.as_deref().map(str::trim).filter(|s| !s.is_empty()) {
                let needle = fold_search_text(q);
                if !needle.is_empty() {
                    items.retain(|c| {
                        fold_search_text(&c.code).contains(&needle)
                            || fold_search_text(&c.name).contains(&needle)
                            || fold_search_text(&c.city).contains(&needle)
                    });
                }
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

    fn get_customer<'a>(&'a self, _mode: &'a ConnectionMode, id: Uuid) -> ApiFuture<'a, Customer> {
        Box::pin(async move {
            MOCK_STORE.with(|store| {
                store
                    .borrow()
                    .customers
                    .iter()
                    .find(|c| c.id == id)
                    .cloned()
                    .ok_or_else(|| mock_http_error(404, "not_found", None, "Customer not found."))
            })
        })
    }

    fn create_customer<'a>(
        &'a self,
        _mode: &'a ConnectionMode,
        req: &'a CreateCustomerRequest,
    ) -> ApiFuture<'a, Customer> {
        let req = req.clone();
        Box::pin(async move {
            validate_customer_input(&req)?;
            let code_trimmed = req.code.trim();
            MOCK_STORE.with(|store| {
                let mut store = store.borrow_mut();
                if store
                    .customers
                    .iter()
                    .any(|c| c.code.eq_ignore_ascii_case(code_trimmed))
                {
                    return Err(mock_http_error(
                        409,
                        "conflict",
                        None,
                        &format!("Customer code '{code_trimmed}' already exists."),
                    ));
                }
                let id = store.alloc_id();
                let created = apply_customer_input(id, 1, &req);
                store.customers.push(created.clone());
                Ok(created)
            })
        })
    }

    fn update_customer<'a>(
        &'a self,
        _mode: &'a ConnectionMode,
        id: Uuid,
        req: &'a UpdateCustomerRequest,
    ) -> ApiFuture<'a, Customer> {
        let req = req.clone();
        Box::pin(async move {
            validate_customer_input(&req)?;
            let code_trimmed = req.code.trim();
            MOCK_STORE.with(|store| {
                let mut store = store.borrow_mut();
                if store
                    .customers
                    .iter()
                    .any(|c| c.id != id && c.code.eq_ignore_ascii_case(code_trimmed))
                {
                    return Err(mock_http_error(
                        409,
                        "conflict",
                        None,
                        &format!("Customer code '{code_trimmed}' already exists."),
                    ));
                }
                let Some(idx) = store.customers.iter().position(|c| c.id == id) else {
                    return Err(mock_http_error(
                        404,
                        "not_found",
                        None,
                        "Customer not found.",
                    ));
                };
                let current_version = store.customers[idx].version;
                if let Some(expected) = req.expected_version {
                    if expected != current_version {
                        return Err(mock_http_error(
                            409,
                            "conflict",
                            Some("record_changed"),
                            "Customer was modified by someone else.",
                        ));
                    }
                }
                let updated = apply_customer_input(id, current_version + 1, &req);
                store.customers[idx] = updated.clone();
                Ok(updated)
            })
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
            Some("info@alpha.example"),
            Some("+32 3 000 00 01"),
            "Havenlaan 10",
            "2000",
            "Antwerpen",
            "BE",
            "nl",
            "00000000-0000-7000-8000-000000000202",
            Some("Z2"),
            Some("5"),
            Some(30),
        ),
        (
            "00000000-0000-7000-8000-000000000402",
            "C0002",
            "Bêta Industrie SA",
            Some("BE0000000196"),
            "domestic",
            Some("contact@beta.example"),
            Some("+32 4 000 00 02"),
            "Rue de l'Usine 5",
            "4000",
            "Liège",
            "BE",
            "fr",
            "00000000-0000-7000-8000-000000000203",
            Some("Z3"),
            Some("0"),
            Some(60),
        ),
        (
            "00000000-0000-7000-8000-000000000403",
            "C0003",
            "Gamma Trading GmbH",
            Some("DE000000000"),
            "intra_eu",
            Some("office@gamma.example"),
            Some("+49 221 000 003"),
            "Werkstraße 3",
            "50667",
            "Köln",
            "DE",
            "en",
            "00000000-0000-7000-8000-000000000201",
            Some("Z1"),
            Some("2.5"),
            Some(30),
        ),
    ];

    rows.into_iter()
        .map(
            |(
                id,
                code,
                name,
                vat,
                regime,
                email,
                phone,
                street,
                postal_code,
                city,
                country,
                lang,
                zone_id,
                zone,
                discount,
                terms,
            )| Customer {
                id: Uuid::parse_str(id).unwrap_or_else(|_| Uuid::nil()),
                version: 1,
                code: code.to_string(),
                name: name.to_string(),
                vat_number: vat.map(str::to_string),
                vat_regime: regime.to_string(),
                email: email.map(str::to_string),
                phone: phone.map(str::to_string),
                street: street.to_string(),
                postal_code: postal_code.to_string(),
                city: city.to_string(),
                country_code: country.to_string(),
                language: lang.to_string(),
                active: true,
                price_zone_id: Uuid::parse_str(zone_id).ok(),
                price_zone_code: zone.map(str::to_string),
                discount_percent: discount.and_then(|d| Decimal::from_str(d).ok()),
                payment_terms_days: terms,
            },
        )
        .collect()
}

#[cfg(test)]
mod tests {
    use std::task::{Context, Poll, RawWaker, RawWakerVTable, Waker};

    use super::*;

    fn block_on_ready<F: Future>(fut: F) -> F::Output {
        fn no_op(_: *const ()) {}
        fn clone(ptr: *const ()) -> RawWaker {
            RawWaker::new(ptr, &VTABLE)
        }
        static VTABLE: RawWakerVTable = RawWakerVTable::new(clone, no_op, no_op, no_op);
        let waker = unsafe { Waker::from_raw(RawWaker::new(std::ptr::null(), &VTABLE)) };
        let mut cx = Context::from_waker(&waker);
        let mut pinned = Box::pin(fut);
        match pinned.as_mut().poll(&mut cx) {
            Poll::Ready(out) => out,
            Poll::Pending => panic!("MockApiClient future unexpectedly yielded Pending"),
        }
    }

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

    #[test]
    fn mock_client_product_crud_roundtrip() {
        let mode = ConnectionMode::MockDemo;
        let created = block_on_ready(MockApiClient.create_product(
            &mode,
            &CreateProductRequest {
                code: "TEST-PROD-1".to_string(),
                name: "Test Valve".to_string(),
                description: "Brass valve".to_string(),
                ..CreateProductRequest::default()
            },
        ))
        .expect("create_product succeeds");
        assert_eq!(created.code, "TEST-PROD-1");

        let fetched = block_on_ready(MockApiClient.get_product(&mode, created.id))
            .expect("get_product finds created item");
        assert_eq!(fetched.name, "Test Valve");

        let mut update_req = UpdateProductRequest::from(&fetched);
        update_req.name = "Updated Brass Valve".to_string();
        let updated = block_on_ready(MockApiClient.update_product(&mode, created.id, &update_req))
            .expect("update_product succeeds");
        assert_eq!(updated.name, "Updated Brass Valve");
    }

    #[test]
    fn mock_client_customer_crud_and_optimistic_lock() {
        let mode = ConnectionMode::MockDemo;
        let zone_id = Uuid::parse_str("00000000-0000-7000-8000-000000000201").unwrap();
        let created = block_on_ready(MockApiClient.create_customer(
            &mode,
            &CreateCustomerRequest {
                code: "C9001".to_string(),
                name: "Test Customer BV".to_string(),
                city: "Gent".to_string(),
                price_zone_id: zone_id,
                ..CreateCustomerRequest::default()
            },
        ))
        .expect("create_customer succeeds");
        assert_eq!(created.version, 1);

        let mut update_req = UpdateCustomerRequest::from_customer(&created, zone_id);
        update_req.city = "Brugge".to_string();
        let updated = block_on_ready(MockApiClient.update_customer(&mode, created.id, &update_req))
            .expect("update_customer succeeds");
        assert_eq!(updated.version, 2);
        assert_eq!(updated.city, "Brugge");

        let conflict =
            block_on_ready(MockApiClient.update_customer(&mode, created.id, &update_req))
                .expect_err("stale expected_version returns conflict");
        assert_eq!(conflict.status(), Some(409));
        assert_eq!(conflict.code(), Some("record_changed"));
    }

    #[test]
    fn mock_client_search_strips_diacritics_and_ignores_case() {
        let mode = ConnectionMode::MockDemo;

        let by_name = block_on_ready(MockApiClient.list_customers(
            &mode,
            &ListCustomersParams {
                q: Some("beta".to_string()),
                ..ListCustomersParams::default()
            },
        ))
        .expect("list_customers by unaccented name succeeds");
        assert!(by_name.items.iter().any(|c| c.code == "C0002"));

        let by_city_upper = block_on_ready(MockApiClient.list_customers(
            &mode,
            &ListCustomersParams {
                q: Some("LIEGE".to_string()),
                ..ListCustomersParams::default()
            },
        ))
        .expect("list_customers by unaccented uppercase city succeeds");
        assert!(by_city_upper.items.iter().any(|c| c.code == "C0002"));

        let by_city_nfd = block_on_ready(MockApiClient.list_customers(
            &mode,
            &ListCustomersParams {
                q: Some("Lie\u{0300}ge".to_string()),
                ..ListCustomersParams::default()
            },
        ))
        .expect("list_customers by NFD city succeeds");
        assert!(by_city_nfd.items.iter().any(|c| c.code == "C0002"));

        let by_umlaut = block_on_ready(MockApiClient.list_customers(
            &mode,
            &ListCustomersParams {
                q: Some("KÖLN".to_string()),
                ..ListCustomersParams::default()
            },
        ))
        .expect("list_customers by uppercase umlaut city succeeds");
        assert!(by_umlaut.items.iter().any(|c| c.code == "C0003"));

        let by_plain_umlaut = block_on_ready(MockApiClient.list_customers(
            &mode,
            &ListCustomersParams {
                q: Some("koln".to_string()),
                ..ListCustomersParams::default()
            },
        ))
        .expect("list_customers by ascii koln succeeds");
        assert!(by_plain_umlaut.items.iter().any(|c| c.code == "C0003"));

        block_on_ready(MockApiClient.create_product(
            &mode,
            &CreateProductRequest {
                code: "CAFÉ-01".to_string(),
                name: "Éclairage LED".to_string(),
                ..CreateProductRequest::default()
            },
        ))
        .expect("create accented product succeeds");

        let by_prod_code = block_on_ready(MockApiClient.list_products(
            &mode,
            &ListProductsParams {
                q: Some("cafe".to_string()),
                ..ListProductsParams::default()
            },
        ))
        .expect("list_products by unaccented code succeeds");
        assert!(by_prod_code.items.iter().any(|p| p.code == "CAFÉ-01"));

        let by_prod_name = block_on_ready(MockApiClient.list_products(
            &mode,
            &ListProductsParams {
                q: Some("eclairage".to_string()),
                ..ListProductsParams::default()
            },
        ))
        .expect("list_products by unaccented name succeeds");
        assert!(by_prod_name.items.iter().any(|p| p.code == "CAFÉ-01"));
    }

    #[test]
    fn mock_client_list_products_supports_comma_separated_product_types() {
        let mode = ConnectionMode::MockDemo;

        let single = block_on_ready(MockApiClient.list_products(
            &mode,
            &ListProductsParams {
                product_type: Some("service".to_string()),
                ..ListProductsParams::default()
            },
        ))
        .expect("single product_type filter succeeds");
        assert!(!single.items.is_empty());
        assert!(single.items.iter().all(|p| p.product_type == "service"));

        let multi = block_on_ready(MockApiClient.list_products(
            &mode,
            &ListProductsParams {
                product_type: Some("manufactured, configurable , ".to_string()),
                ..ListProductsParams::default()
            },
        ))
        .expect("comma-separated product_type filter succeeds");
        assert!(multi.items.iter().any(|p| p.code == "UNIT-100"));
        assert!(multi.items.iter().any(|p| p.code == "UNIT-200"));
        assert!(multi
            .items
            .iter()
            .all(|p| p.product_type == "manufactured" || p.product_type == "configurable"));

        let blank_commas = block_on_ready(MockApiClient.list_products(
            &mode,
            &ListProductsParams {
                product_type: Some(" , , ".to_string()),
                ..ListProductsParams::default()
            },
        ))
        .expect("blank comma-only product_type filter succeeds");
        assert!(blank_commas.items.iter().any(|p| p.code == "INSTALL"));
        assert!(blank_commas.items.iter().any(|p| p.code == "PUMP-05"));
        assert!(blank_commas.items.iter().any(|p| p.code == "UNIT-100"));
    }
}
