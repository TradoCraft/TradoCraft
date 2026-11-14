//! Customers as an importable entity (ADR 0029, ADR 0067): an export and an all-or-nothing
//! upsert-by-`code` import in CSV, XLSX or ODS. The commercial terms (price zone, discount, payment
//! terms) are those of the active company. Everything shared lives in `tradocraft_core::import`;
//! this file holds only what is the customers'.

use std::collections::HashMap;

use axum::body::Bytes;
use axum::extract::{DefaultBodyLimit, Query, State};
use axum::http::{HeaderMap, StatusCode};
use axum::Json;
use rust_decimal::Decimal;
use sqlx::{PgConnection, PgPool};
use tradocraft_core::csv_io::{self, ImportParams, ImportReport};
use tradocraft_core::error::ErrorBody;
use tradocraft_core::import::{
    self, Cell, CellValue, Cells, Column, ColumnKind, ExportParams, ImportEntity, Importable, Row,
    Table,
};
use tradocraft_core::{AppResult, AppState, CurrentUser, Permission};
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::{
    insert_customer, update_customer_row, upsert_terms, Customer, CustomerInput, SELECT_CUSTOMER,
};

/// The columns, in export order. `code` is the key; the others are optional in an import file.
/// `required` means a new customer needs a value.
const COLUMNS: [Column; 15] = [
    Column::new("code", ColumnKind::Code, true),
    Column::new("name", ColumnKind::Text, true),
    Column::new("vat_number", ColumnKind::Text, false),
    Column::new("email", ColumnKind::Text, false),
    Column::new("phone", ColumnKind::Text, false),
    Column::new("street", ColumnKind::Text, false),
    Column::new("postal_code", ColumnKind::Text, false),
    Column::new("city", ColumnKind::Text, false),
    Column::new("country_code", ColumnKind::Code, false),
    Column::new("language", ColumnKind::Code, false),
    Column::new("active", ColumnKind::Boolean, false),
    Column::new("price_zone_code", ColumnKind::Code, true),
    Column::new("discount_percent", ColumnKind::Decimal, false),
    Column::new("payment_terms_days", ColumnKind::Integer, false),
    Column::new("vat_regime", ColumnKind::Code, false),
];

/// One customer as the cells of an export row, in [`COLUMNS`] order.
fn export_row(c: &Customer) -> Vec<CellValue> {
    let opt = |v: &Option<String>| CellValue::text(v.clone().unwrap_or_default());
    vec![
        CellValue::text(&c.code),
        CellValue::text(&c.name),
        opt(&c.vat_number),
        opt(&c.email),
        opt(&c.phone),
        CellValue::text(&c.street),
        CellValue::text(&c.postal_code),
        CellValue::text(&c.city),
        CellValue::text(&c.country_code),
        CellValue::text(&c.language),
        CellValue::Bool(c.active),
        opt(&c.price_zone_code),
        c.discount_percent
            .map_or(CellValue::Empty, |d| CellValue::Number(d.normalize())),
        c.payment_terms_days
            .map_or(CellValue::Empty, |d| CellValue::int(d.into())),
        CellValue::text(&c.vat_regime),
    ]
}

/// What a valid row would write: the customer and the zone its terms belong to.
pub struct CustomerChange {
    input: CustomerInput,
    /// The price zone of the terms; none means the customer has no terms here.
    zone: Option<Uuid>,
}

/// Whether the stored customer already equals what the row would write (so nothing is written).
fn same(existing: &Customer, i: &CustomerInput, zone: Option<Uuid>) -> bool {
    existing.name == i.name
        && existing.vat_number == i.vat_number
        && existing.vat_regime == i.vat_regime
        && existing.email == i.email
        && existing.phone == i.phone
        && existing.street == i.street
        && existing.postal_code == i.postal_code
        && existing.city == i.city
        && existing.country_code == i.country_code
        && existing.language == i.language
        && existing.active == i.active
        && existing.price_zone_id == zone
        && (zone.is_none()
            || (existing.discount_percent == Some(i.discount_percent)
                && existing.payment_terms_days == Some(i.payment_terms_days)))
}

/// The customers as an importable entity.
pub struct Customers;

impl Importable for Customers {
    type Stored = Customer;
    type Change = CustomerChange;
    /// The price zones of the active company, by code.
    type Context = HashMap<String, Uuid>;

    const KEY: &'static str = "customers";
    const AUDIT_ENTITY: &'static str = "customer";
    const READ: Permission = Permission::CustomersRead;
    const WRITE: Permission = Permission::CustomersWrite;
    const FILE_STEM: &'static str = "customers";
    const COLUMNS: &'static [Column] = &COLUMNS;

    async fn context(
        conn: &mut PgConnection,
        user: &CurrentUser,
        _table: &Table,
    ) -> AppResult<Self::Context> {
        Ok(sqlx::query_as::<_, (String, Uuid)>(
            "SELECT code, id FROM pricing.price_zones WHERE company_id = $1",
        )
        .bind(user.company_id)
        .fetch_all(conn)
        .await?
        .into_iter()
        .collect())
    }

    async fn load(
        conn: &mut PgConnection,
        user: &CurrentUser,
        keys: &[String],
    ) -> AppResult<Vec<(String, Customer)>> {
        // Read and lock the rows we are going to change in one statement, so a concurrent edit
        // cannot slip in between the read and the lock (a row changed meanwhile is returned as
        // committed).
        Ok(sqlx::query_as::<_, Customer>(&format!(
            "{SELECT_CUSTOMER} WHERE c.code = ANY($2) ORDER BY c.id FOR UPDATE OF c"
        ))
        .bind(user.company_id)
        .bind(keys)
        .fetch_all(conn)
        .await?
        .into_iter()
        .map(|c| (c.code.clone(), c))
        .collect())
    }

    fn stored_id(stored: &Customer) -> Uuid {
        stored.id
    }

    async fn plan_row(
        _conn: &mut PgConnection,
        _user: &CurrentUser,
        zones: &mut Self::Context,
        key: &str,
        current: Option<&Customer>,
        _row: &Row,
        cells: &mut Cells<'_>,
    ) -> AppResult<CustomerChange> {
        // Start from the stored values (or the API defaults) and overlay the columns of the file.
        let mut input = match current {
            Some(c) => CustomerInput {
                code: c.code.clone(),
                name: c.name.clone(),
                vat_number: c.vat_number.clone(),
                vat_regime: c.vat_regime.clone(),
                email: c.email.clone(),
                phone: c.phone.clone(),
                street: c.street.clone(),
                postal_code: c.postal_code.clone(),
                city: c.city.clone(),
                country_code: c.country_code.clone(),
                language: c.language.clone(),
                active: c.active,
                price_zone_id: c.price_zone_id.unwrap_or_default(),
                discount_percent: c.discount_percent.unwrap_or_default(),
                payment_terms_days: c.payment_terms_days.unwrap_or(30),
            },
            None => CustomerInput {
                code: key.to_string(),
                name: String::new(),
                vat_number: None,
                vat_regime: "domestic".to_string(),
                email: None,
                phone: None,
                street: String::new(),
                postal_code: String::new(),
                city: String::new(),
                country_code: "BE".into(),
                language: "nl".into(),
                active: true,
                price_zone_id: Uuid::nil(),
                discount_percent: Decimal::ZERO,
                payment_terms_days: 30,
            },
        };
        cells.text("name").apply(&mut input.name);
        cells.text("vat_number").apply_opt(&mut input.vat_number);
        cells.trimmed("vat_regime").apply(&mut input.vat_regime);
        cells.text("email").apply_opt(&mut input.email);
        cells.text("phone").apply_opt(&mut input.phone);
        cells.text("street").apply(&mut input.street);
        cells.text("postal_code").apply(&mut input.postal_code);
        cells.text("city").apply(&mut input.city);
        cells.trimmed("country_code").apply(&mut input.country_code);
        cells.trimmed("language").apply(&mut input.language);
        cells.boolean("active").apply(&mut input.active);
        let terms = cells.int("payment_terms_days");
        // Normalised first (7,500 is 7.5), so that only real excess decimals are an error.
        let discount = match cells.decimal("discount_percent") {
            Cell::Value(d) if d.normalize().scale() > 2 => {
                cells.error(Some("discount_percent"), "at most 2 decimals are allowed");
                Cell::Absent
            }
            Cell::Value(d) => Cell::Value(d.normalize()),
            other => other,
        };
        let mut zone = current.and_then(|c| c.price_zone_id);
        if let Cell::Value(z) = cells.trimmed("price_zone_code") {
            match zones.get(&z) {
                Some(id) => zone = Some(*id),
                None => cells.error(
                    Some("price_zone_code"),
                    format!("unknown price zone {z:?} in the active company"),
                ),
            }
        }
        // Terms live with a price zone: a value for them needs one (blank is fine without).
        if zone.is_none() {
            for (column, given) in [
                ("discount_percent", matches!(discount, Cell::Value(_))),
                ("payment_terms_days", matches!(terms, Cell::Value(_))),
            ] {
                if given {
                    cells.error(
                        Some(column),
                        format!("{column} needs a price zone: the customer has none, give price_zone_code"),
                    );
                }
            }
        }
        discount.apply(&mut input.discount_percent);
        terms.apply(&mut input.payment_terms_days);
        // Normalise like the API does before storing, so that "unchanged" is exact.
        input.code = input.code.trim().to_string();
        input.name = input.name.trim().to_string();
        input.country_code = input.country_code.to_uppercase();
        input.language = input.language.to_lowercase();
        input.price_zone_id = zone.unwrap_or_default();

        if input.name.is_empty() {
            let message = if current.is_none() {
                "name is required for a new customer"
            } else {
                "name cannot be empty"
            };
            cells.error(Some("name"), message);
        }
        if current.is_none() && zone.is_none() {
            cells.error(
                Some("price_zone_code"),
                "price_zone_code is required for a new customer",
            );
        }
        // Same rules as the API, all of them; each message names the field it is about.
        let name_missing = input.name.is_empty();
        cells.problems(
            input
                .problems()
                .into_iter()
                .filter(|m| !(name_missing && m.starts_with("code and name"))),
            &import::column_names::<Self>(),
        );
        // The VAT rule (ADR 0058) applies to a number the file adds or changes, so that an
        // untouched legacy number does not stop a re-import of an export.
        if let Some(m) = input.vat_problem(current.and_then(|c| c.vat_number.as_deref())) {
            cells.error(Some("vat_number"), m);
        }
        Ok(CustomerChange { input, zone })
    }

    fn unchanged(stored: &Customer, change: &CustomerChange) -> bool {
        same(stored, &change.input, change.zone)
    }

    async fn create(
        conn: &mut PgConnection,
        user: &CurrentUser,
        id: Uuid,
        change: &CustomerChange,
    ) -> AppResult<()> {
        insert_customer(conn, id, &change.input).await?;
        upsert_terms(conn, user.company_id, id, &change.input).await
    }

    async fn update(
        conn: &mut PgConnection,
        user: &CurrentUser,
        id: Uuid,
        change: &CustomerChange,
    ) -> AppResult<()> {
        update_customer_row(conn, id, &change.input).await?;
        // Terms are written only when the customer has a zone (the file gave one or it had one).
        if change.zone.is_some() {
            upsert_terms(conn, user.company_id, id, &change.input).await?;
        }
        Ok(())
    }

    async fn export(pool: &PgPool, user: &CurrentUser) -> AppResult<Vec<Vec<CellValue>>> {
        let customers: Vec<Customer> =
            sqlx::query_as(&format!("{SELECT_CUSTOMER} ORDER BY c.code"))
                .bind(user.company_id)
                .fetch_all(pool)
                .await?;
        Ok(customers.iter().map(export_row).collect())
    }
}

/// The customers' handle for the import registry and the background worker.
pub fn customers_import() -> ImportEntity {
    ImportEntity::of::<Customers>()
}

/// All customers (with the terms in the active company) as CSV, XLSX or ODS, ordered by code.
#[utoipa::path(get, path = "/customers/export", tag = "crm", operation_id = "export_customers",
    params(ExportParams),
    responses((status = 200, content(
            (String = "text/csv"),
            (String = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"),
            (String = "application/vnd.oasis.opendocument.spreadsheet"))),
        (status = 403, body = ErrorBody)))]
async fn export_customers(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(p): Query<ExportParams>,
) -> AppResult<(HeaderMap, Vec<u8>)> {
    import::export_request::<Customers>(&state.db, &user, &p).await
}

/// Creates or updates customers from a CSV, XLSX or ODS file (detected from the content), keyed by
/// `code`. All-or-nothing: with any row error nothing is written (422 with every error);
/// `dry_run=true` only reports. `sheet` picks the sheet of a spreadsheet.
#[utoipa::path(post, path = "/customers/import", tag = "crm", operation_id = "import_customers",
    params(ImportParams),
    request_body(content(
        (String = "application/octet-stream"),
        (String = "text/csv"))),
    responses((status = 200, body = ImportReport), (status = 403, body = ErrorBody),
        (status = 413, description = "Body larger than 5 MB"), (status = 422, body = ImportReport)))]
async fn import_customers(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(p): Query<ImportParams>,
    body: Bytes,
) -> AppResult<(StatusCode, Json<ImportReport>)> {
    import::import_request::<Customers>(&state.db, &user, &p, &body).await
}

/// The routes of the customer export and import (the import with its own body limit).
pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(export_customers))
        .merge(
            OpenApiRouter::new()
                .routes(routes!(import_customers))
                .layer(DefaultBodyLimit::max(csv_io::MAX_BODY_BYTES)),
        )
}
