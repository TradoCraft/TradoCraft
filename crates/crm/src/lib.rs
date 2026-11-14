//! CRM: customers and their per-company commercial terms.
//!
//! Other modules use the public service functions here (e.g. [`get_customer_for_quoting`])
//! and never query `crm.*` tables directly.

pub mod baseline;
pub mod baseline_types;
pub mod closures;
pub mod contacts;
pub mod import;
pub mod match_rules;
pub mod matching;
pub mod product_matches;
pub use import::{customers_import, Customers};
pub mod opportunities;
pub mod rebates;

use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::{Extension, Json};
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgExecutor};
use tradocraft_core::vat_check::{self, VatCheck, VatCheckParams, VatDuplicate};
use tradocraft_core::vies::ViesConfig;
use tradocraft_core::{
    audit, new_id, search, vat, AppError, AppResult, AppState, CurrentUser, Permission,
};
use utoipa::{IntoParams, ToSchema};
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

/// The VAT regimes of a customer: VAT charged, reverse charge inside the EU, or export.
pub const VAT_REGIMES: [&str; 3] = ["domestic", "intra_eu", "outside_eu"];

fn default_vat_regime() -> String {
    "domestic".to_string()
}

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct Customer {
    pub id: Uuid,
    pub code: String,
    pub name: String,
    pub vat_number: Option<String>,
    /// `domestic` (VAT charged), `intra_eu` (reverse charge) or `outside_eu`.
    pub vat_regime: String,
    pub email: Option<String>,
    pub phone: Option<String>,
    pub street: String,
    pub postal_code: String,
    pub city: String,
    pub country_code: String,
    pub language: String,
    pub active: bool,
    // Commercial terms in the active company (null if the customer has none there).
    pub price_zone_id: Option<Uuid>,
    pub price_zone_code: Option<String>,
    #[schema(value_type = Option<String>, example = "5.00")]
    pub discount_percent: Option<Decimal>,
    pub payment_terms_days: Option<i32>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct CustomerInput {
    pub code: String,
    pub name: String,
    pub vat_number: Option<String>,
    /// `domestic` (default), `intra_eu` or `outside_eu`.
    #[serde(default = "default_vat_regime")]
    pub vat_regime: String,
    pub email: Option<String>,
    pub phone: Option<String>,
    #[serde(default)]
    pub street: String,
    #[serde(default)]
    pub postal_code: String,
    #[serde(default)]
    pub city: String,
    #[serde(default = "default_country")]
    pub country_code: String,
    #[serde(default = "default_language")]
    pub language: String,
    #[serde(default = "default_true")]
    pub active: bool,
    pub price_zone_id: Uuid,
    #[serde(default)]
    #[schema(value_type = String, example = "0")]
    pub discount_percent: Decimal,
    #[serde(default = "default_payment_terms")]
    pub payment_terms_days: i32,
}

fn default_country() -> String {
    "BE".into()
}
fn default_language() -> String {
    "nl".into()
}
fn default_true() -> bool {
    true
}
fn default_payment_terms() -> i32 {
    30
}

impl CustomerInput {
    /// Every rule the input breaks, each as the message of a validation error.
    pub(crate) fn problems(&self) -> Vec<String> {
        let mut out = Vec::new();
        if self.code.trim().is_empty() || self.name.trim().is_empty() {
            out.push("code and name are required".to_string());
        }
        if self.country_code.len() != 2 {
            out.push("country_code must be a 2-letter code".to_string());
        }
        if !tradocraft_core::is_language(&self.language.to_lowercase()) {
            out.push(format!(
                "language must be one of {}",
                tradocraft_core::LANGUAGES.join(", ")
            ));
        }
        if self.discount_percent < -Decimal::ONE_HUNDRED
            || self.discount_percent > Decimal::ONE_HUNDRED
        {
            out.push("discount_percent must be between -100 and 100".to_string());
        }
        if !VAT_REGIMES.contains(&self.vat_regime.as_str()) {
            out.push(format!(
                "vat_regime must be one of {}",
                VAT_REGIMES.join(", ")
            ));
        }
        if self.payment_terms_days < 0 {
            out.push("payment_terms_days cannot be negative".to_string());
        }
        out
    }

    /// The VAT rule the number breaks, when it is new or changed (ADR 0058). `current` is the
    /// stored number: one entered before numbers were checked must not block editing the rest of
    /// the customer, so an unchanged number is left alone.
    pub(crate) fn vat_problem(&self, current: Option<&str>) -> Option<String> {
        let number = self.vat_number.as_deref()?;
        let country = Some(self.country_code.as_str());
        if current.is_some_and(|c| vat::same_number(number, c, country)) {
            return None;
        }
        vat::problem(number, country)
    }

    /// The first broken rule as a validation error.
    pub(crate) fn validate(&self) -> AppResult<()> {
        match self.problems().into_iter().next() {
            Some(m) => Err(AppError::Validation(m)),
            None => Ok(()),
        }
    }
}

#[derive(Debug, Serialize, ToSchema)]
pub struct CustomerPage {
    pub items: Vec<Customer>,
    pub total: i64,
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct ListParams {
    /// Searches code, name, VAT number and city, ignoring case and accents ("Liege" finds "Liège").
    pub q: Option<String>,
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}

pub(crate) const SELECT_CUSTOMER: &str = r#"
    SELECT c.id, c.code, c.name, c.vat_number, c.vat_regime, c.email, c.phone, c.street, c.postal_code, c.city,
           c.country_code::text AS country_code, c.language::text AS language, c.active,
           t.price_zone_id, z.code AS price_zone_code, t.discount_percent, t.payment_terms_days
    FROM crm.customers c
    LEFT JOIN crm.customer_terms t ON t.customer_id = c.id AND t.company_id = $1
    LEFT JOIN pricing.price_zones z ON z.id = t.price_zone_id
"#;

pub async fn get_customer<'e>(
    db: impl PgExecutor<'e>,
    company_id: Uuid,
    id: Uuid,
) -> AppResult<Customer> {
    sqlx::query_as(&format!("{SELECT_CUSTOMER} WHERE c.id = $2"))
        .bind(company_id)
        .bind(id)
        .fetch_optional(db)
        .await?
        .ok_or(AppError::NotFound("customer"))
}

/// Like [`get_customer`], for the row an update is about to change: locks it until the transaction
/// ends, so that what an update records as "before" (the audit trail, ADR 0059) is the latest
/// committed state and not one that a concurrent update is replacing.
///
/// Two statements, on purpose. A single `SELECT ... FOR UPDATE OF c` over the joins would re-read
/// the locked customer after waiting, but keep the terms and price zone rows of the snapshot it
/// started with, so a concurrent change of the discount would be reported as it was before that
/// change. The lock is taken first; the read that follows sees everything committed up to then.
async fn get_customer_for_update(
    conn: &mut sqlx::PgConnection,
    company_id: Uuid,
    id: Uuid,
) -> AppResult<Customer> {
    sqlx::query_scalar::<_, Uuid>("SELECT id FROM crm.customers WHERE id = $1 FOR UPDATE")
        .bind(id)
        .fetch_optional(&mut *conn)
        .await?
        .ok_or(AppError::NotFound("customer"))?;
    get_customer(&mut *conn, company_id, id).await
}

/// Everything sales needs to quote a customer in a company.
#[derive(Debug, Clone)]
pub struct QuotingCustomer {
    pub customer: Customer,
    pub price_zone_id: Uuid,
    pub price_zone_code: String,
    pub discount_percent: Decimal,
}

pub async fn get_customer_for_quoting<'e>(
    db: impl PgExecutor<'e>,
    company_id: Uuid,
    id: Uuid,
) -> AppResult<QuotingCustomer> {
    let customer = get_customer(db, company_id, id).await?;
    if !customer.active {
        return Err(AppError::Validation(format!(
            "customer {} is inactive",
            customer.code
        )));
    }
    match (
        customer.price_zone_id,
        customer.price_zone_code.clone(),
        customer.discount_percent,
    ) {
        (Some(zone_id), Some(zone_code), Some(discount)) => Ok(QuotingCustomer {
            price_zone_id: zone_id,
            price_zone_code: zone_code,
            discount_percent: discount,
            customer,
        }),
        _ => Err(AppError::Validation(format!(
            "customer {} has no commercial terms (price zone) in this company",
            customer.code
        ))),
    }
}

#[utoipa::path(get, path = "/customers", tag = "crm", params(ListParams),
    responses((status = 200, body = CustomerPage)))]
async fn list_customers(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(p): Query<ListParams>,
) -> AppResult<Json<CustomerPage>> {
    user.require(Permission::CustomersRead)?;
    let pattern = search::pattern(p.q.as_deref());
    let filter = format!(
        "WHERE ($2::text IS NULL OR {} OR {} OR {} OR {})",
        search::matches("c.code", "$2"),
        search::matches("c.name", "$2"),
        search::matches("c.vat_number", "$2"),
        search::matches("c.city", "$2"),
    );
    let items = sqlx::query_as(&format!(
        "{SELECT_CUSTOMER} {filter} ORDER BY c.name LIMIT $3 OFFSET $4"
    ))
    .bind(user.company_id)
    .bind(&pattern)
    .bind(p.limit.unwrap_or(50).clamp(1, 500))
    .bind(p.offset.unwrap_or(0).max(0))
    .fetch_all(&state.db)
    .await?;
    let total = sqlx::query_scalar(&format!(
        "SELECT count(*) FROM crm.customers c {}",
        filter.replace("$2", "$1")
    ))
    .bind(&pattern)
    .fetch_one(&state.db)
    .await?;
    Ok(Json(CustomerPage { items, total }))
}

#[utoipa::path(get, path = "/customers/{id}", tag = "crm", operation_id = "get_customer", params(("id" = Uuid, Path)),
    responses((status = 200, body = Customer), (status = 404, body = tradocraft_core::error::ErrorBody)))]
async fn get_customer_handler(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<Customer>> {
    user.require(Permission::CustomersRead)?;
    Ok(Json(get_customer(&state.db, user.company_id, id).await?))
}

async fn ensure_zone_in_company(
    conn: &mut sqlx::PgConnection,
    company_id: Uuid,
    zone_id: Uuid,
) -> AppResult<()> {
    let ok: bool = sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM pricing.price_zones WHERE id = $1 AND company_id = $2)",
    )
    .bind(zone_id)
    .bind(company_id)
    .fetch_one(conn)
    .await?;
    if ok {
        Ok(())
    } else {
        Err(AppError::Validation(
            "price zone does not belong to the active company".into(),
        ))
    }
}

pub(crate) async fn upsert_terms(
    conn: &mut sqlx::PgConnection,
    company_id: Uuid,
    id: Uuid,
    input: &CustomerInput,
) -> AppResult<()> {
    ensure_zone_in_company(conn, company_id, input.price_zone_id).await?;
    sqlx::query(
        "INSERT INTO crm.customer_terms (customer_id, company_id, price_zone_id, discount_percent, payment_terms_days)
         VALUES ($1, $2, $3, $4, $5)
         ON CONFLICT (customer_id, company_id) DO UPDATE
         SET price_zone_id = EXCLUDED.price_zone_id, discount_percent = EXCLUDED.discount_percent,
             payment_terms_days = EXCLUDED.payment_terms_days",
    )
    .bind(id)
    .bind(company_id)
    .bind(input.price_zone_id)
    .bind(input.discount_percent)
    .bind(input.payment_terms_days)
    .execute(conn)
    .await?;
    Ok(())
}

/// Inserts a customer row (validation and the commercial terms are the caller's job).
pub(crate) async fn insert_customer(
    conn: &mut sqlx::PgConnection,
    id: Uuid,
    input: &CustomerInput,
) -> AppResult<()> {
    sqlx::query(
        "INSERT INTO crm.customers (id, code, name, vat_number, email, phone, street, postal_code, city,
                                    country_code, language, active, vat_regime)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)",
    )
    .bind(id)
    .bind(input.code.trim())
    .bind(input.name.trim())
    .bind(&input.vat_number)
    .bind(&input.email)
    .bind(&input.phone)
    .bind(&input.street)
    .bind(&input.postal_code)
    .bind(&input.city)
    .bind(input.country_code.to_uppercase())
    .bind(input.language.to_lowercase())
    .bind(input.active)
    .bind(&input.vat_regime)
    .execute(conn)
    .await?;
    Ok(())
}

/// Updates a customer row (not its terms); `NotFound` if the id is unknown.
pub(crate) async fn update_customer_row(
    conn: &mut sqlx::PgConnection,
    id: Uuid,
    input: &CustomerInput,
) -> AppResult<()> {
    let updated = sqlx::query(
        "UPDATE crm.customers SET code = $2, name = $3, vat_number = $4, email = $5, phone = $6, street = $7,
                postal_code = $8, city = $9, country_code = $10, language = $11, active = $12, vat_regime = $13, updated_at = now()
         WHERE id = $1",
    )
    .bind(id)
    .bind(input.code.trim())
    .bind(input.name.trim())
    .bind(&input.vat_number)
    .bind(&input.email)
    .bind(&input.phone)
    .bind(&input.street)
    .bind(&input.postal_code)
    .bind(&input.city)
    .bind(input.country_code.to_uppercase())
    .bind(input.language.to_lowercase())
    .bind(input.active)
    .bind(&input.vat_regime)
    .execute(&mut *conn)
    .await?;
    if updated.rows_affected() == 0 {
        return Err(AppError::NotFound("customer"));
    }
    Ok(())
}

#[utoipa::path(post, path = "/customers", tag = "crm", request_body = CustomerInput,
    responses((status = 201, body = Customer), (status = 409, body = tradocraft_core::error::ErrorBody)))]
async fn create_customer(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<CustomerInput>,
) -> AppResult<(StatusCode, Json<Customer>)> {
    user.require(Permission::CustomersWrite)?;
    input.validate()?;
    if let Some(m) = input.vat_problem(None) {
        return Err(AppError::Validation(m));
    }
    let id = new_id();
    let mut tx = state.db.begin().await?;
    insert_customer(&mut tx, id, &input).await?;
    upsert_terms(&mut tx, user.company_id, id, &input).await?;
    audit::record(
        &mut tx,
        &user,
        "customer",
        id,
        "created",
        serde_json::json!({ "code": input.code }),
    )
    .await?;
    tx.commit().await?;
    Ok((
        StatusCode::CREATED,
        Json(get_customer(&state.db, user.company_id, id).await?),
    ))
}

#[utoipa::path(put, path = "/customers/{id}", tag = "crm", params(("id" = Uuid, Path)),
    request_body = CustomerInput, responses((status = 200, body = Customer)))]
async fn update_customer(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<CustomerInput>,
) -> AppResult<Json<Customer>> {
    user.require(Permission::CustomersWrite)?;
    input.validate()?;
    let mut tx = state.db.begin().await?;
    let before = get_customer_for_update(&mut tx, user.company_id, id).await?;
    if let Some(m) = input.vat_problem(before.vat_number.as_deref()) {
        return Err(AppError::Validation(m));
    }
    update_customer_row(&mut tx, id, &input).await?;
    upsert_terms(&mut tx, user.company_id, id, &input).await?;
    // What changed, field by field, for the audit viewer (ADR 0059).
    let changes = audit::Changes::new()
        .field("code", before.code.as_str(), input.code.trim())
        .field("name", before.name.as_str(), input.name.trim())
        .field("vat_number", &before.vat_number, &input.vat_number)
        .field("vat_regime", &before.vat_regime, &input.vat_regime)
        .field("email", &before.email, &input.email)
        .field("phone", &before.phone, &input.phone)
        .field("street", &before.street, &input.street)
        .field("postal_code", &before.postal_code, &input.postal_code)
        .field("city", &before.city, &input.city)
        .field(
            "country_code",
            before.country_code.as_str(),
            input.country_code.to_uppercase().as_str(),
        )
        .field(
            "language",
            before.language.as_str(),
            input.language.to_lowercase().as_str(),
        )
        .field("active", &before.active, &input.active)
        .field(
            "price_zone_id",
            &before.price_zone_id,
            &Some(input.price_zone_id),
        )
        .field(
            "discount_percent",
            &before.discount_percent.map(|d| d.normalize()),
            &Some(input.discount_percent.normalize()),
        )
        .field(
            "payment_terms_days",
            &before.payment_terms_days,
            &Some(input.payment_terms_days),
        );
    audit::record(
        &mut tx,
        &user,
        "customer",
        id,
        "updated",
        changes.into_data(),
    )
    .await?;
    tx.commit().await?;
    Ok(Json(get_customer(&state.db, user.company_id, id).await?))
}

/// Customers that carry the same VAT number (ADR 0058). Customers are shared master data
/// (ADR 0003), so this looks across the whole table, which is also what the customer list shows.
async fn vat_duplicates(
    db: &sqlx::PgPool,
    a: &vat_check::Assessment,
    exclude: Option<Uuid>,
) -> AppResult<Vec<VatDuplicate>> {
    let (bare, countries) = a.bare.clone().unwrap_or_default();
    Ok(sqlx::query_as(
        "SELECT id, code, name, active FROM crm.customers
         WHERE vat_number IS NOT NULL AND vat_number <> ''
           AND (core.vat_key(vat_number) = ANY($1)
                OR (core.vat_key(vat_number) = ANY($2) AND upper(country_code::text) = ANY($3)))
           AND ($4::uuid IS NULL OR id <> $4)
         ORDER BY active DESC, name LIMIT 10",
    )
    .bind(&a.keys)
    .bind(bare)
    .bind(countries)
    .bind(exclude)
    .fetch_all(db)
    .await?)
}

/// Checks a VAT number for the customer form: the format and check digits, other customers with
/// the same number, and with `lookup=true` the name and address VIES has for it. Advice only;
/// nothing is stored. The lookup needs `customers.write`: it makes the server call VIES.
#[utoipa::path(get, path = "/customers/vat-check", tag = "crm", operation_id = "check_customer_vat",
    params(VatCheckParams), responses((status = 200, body = VatCheck),
    (status = 403, body = tradocraft_core::error::ErrorBody)))]
async fn check_vat(
    State(state): State<AppState>,
    user: CurrentUser,
    Extension(vies): Extension<ViesConfig>,
    Query(p): Query<VatCheckParams>,
) -> AppResult<Json<VatCheck>> {
    user.require(Permission::CustomersRead)?;
    let lookup = p.lookup.unwrap_or(false);
    if lookup {
        user.require(Permission::CustomersWrite)?;
    }
    let a = vat_check::assess(&p.vat_number, p.country_code.as_deref());
    let duplicates = if a.has_number() {
        vat_duplicates(&state.db, &a, p.exclude_id).await?
    } else {
        Vec::new()
    };
    Ok(Json(a.build(duplicates, lookup.then_some(&vies)).await))
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(check_vat))
        .routes(routes!(list_customers, create_customer))
        .routes(routes!(get_customer_handler, update_customer))
        .merge(import::router())
        .merge(contacts::router())
        .merge(opportunities::router())
        .merge(baseline::router())
        .merge(baseline_types::router())
        .merge(match_rules::router())
        .merge(product_matches::router())
        .merge(rebates::router())
        .merge(closures::router())
}
