//! Customers as CSV: an export and an all-or-nothing upsert-by-`code` import (see
//! `docs/adr/0029-csv-export-import.md`). The commercial terms (price zone, discount, payment
//! terms) are those of the active company.

use std::collections::HashMap;

use axum::body::Bytes;
use axum::extract::{DefaultBodyLimit, Query, State};
use axum::http::{HeaderMap, StatusCode};
use axum::Json;
use rust_decimal::Decimal;
use tradocraft_core::csv_io::{
    self, format_decimal, parse_table, Cell, Cells, ImportParams, ImportReport, RowError,
};
use tradocraft_core::error::ErrorBody;
use tradocraft_core::{audit, new_id, AppResult, AppState, CurrentUser, Permission};
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::{
    insert_customer, update_customer_row, upsert_terms, Customer, CustomerInput, SELECT_CUSTOMER,
};

/// The columns, in export order. `code` is the key; the others are optional in an import file.
pub const COLUMNS: [&str; 15] = [
    "code",
    "name",
    "vat_number",
    "email",
    "phone",
    "street",
    "postal_code",
    "city",
    "country_code",
    "language",
    "active",
    "price_zone_code",
    "discount_percent",
    "payment_terms_days",
    "vat_regime",
];

/// One customer as the cells of an export row, in [`COLUMNS`] order.
fn export_row(c: &Customer) -> Vec<String> {
    let opt = |v: &Option<String>| v.clone().unwrap_or_default();
    vec![
        c.code.clone(),
        c.name.clone(),
        opt(&c.vat_number),
        opt(&c.email),
        opt(&c.phone),
        c.street.clone(),
        c.postal_code.clone(),
        c.city.clone(),
        c.country_code.clone(),
        c.language.clone(),
        c.active.to_string(),
        opt(&c.price_zone_code),
        c.discount_percent.map(format_decimal).unwrap_or_default(),
        c.payment_terms_days
            .map(|d| d.to_string())
            .unwrap_or_default(),
        c.vat_regime.clone(),
    ]
}

/// All customers (with the terms in the active company) as CSV, ordered by code.
#[utoipa::path(get, path = "/customers/export", tag = "crm", operation_id = "export_customers",
    responses((status = 200, body = String, content_type = "text/csv"), (status = 403, body = ErrorBody)))]
async fn export_customers(
    State(state): State<AppState>,
    user: CurrentUser,
) -> AppResult<(HeaderMap, String)> {
    user.require(Permission::CustomersRead)?;
    let customers: Vec<Customer> = sqlx::query_as(&format!("{SELECT_CUSTOMER} ORDER BY c.code"))
        .bind(user.company_id)
        .fetch_all(&state.db)
        .await?;
    let body = csv_io::write_csv(&COLUMNS, customers.iter().map(export_row));
    Ok(csv_io::download("customers.csv", body))
}

/// What an import does with one valid row.
enum Action {
    Create {
        input: CustomerInput,
    },
    Update {
        id: Uuid,
        input: CustomerInput,
        /// Terms are written (false: the customer has none here and the file gives none).
        terms: bool,
    },
}

/// The outcome of checking a whole file: what to write and what was found wrong.
#[derive(Default)]
struct Plan {
    actions: Vec<Action>,
    unchanged: usize,
    errors: Vec<RowError>,
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

/// Checks every row against the database and decides what each one would do.
async fn plan(
    conn: &mut sqlx::PgConnection,
    company_id: Uuid,
    table: &csv_io::CsvTable,
) -> AppResult<Plan> {
    let zones: HashMap<String, Uuid> = sqlx::query_as::<_, (String, Uuid)>(
        "SELECT code, id FROM pricing.price_zones WHERE company_id = $1",
    )
    .bind(company_id)
    .fetch_all(&mut *conn)
    .await?
    .into_iter()
    .collect();
    let codes: Vec<String> = table
        .rows
        .iter()
        .filter_map(|r| r.get_trimmed("code"))
        .map(str::to_string)
        .collect();
    // Read and lock the rows we are going to change in one statement, so a concurrent edit cannot
    // slip in between the read and the lock (a row changed meanwhile is returned as committed).
    let existing: HashMap<String, Customer> = sqlx::query_as::<_, Customer>(&format!(
        "{SELECT_CUSTOMER} WHERE c.code = ANY($2) ORDER BY c.id FOR UPDATE OF c"
    ))
    .bind(company_id)
    .bind(&codes)
    .fetch_all(&mut *conn)
    .await?
    .into_iter()
    .map(|c| (c.code.clone(), c))
    .collect();

    let mut plan = Plan::default();
    let mut seen: HashMap<String, usize> = HashMap::new();
    for row in &table.rows {
        let mut cells = Cells::new(row, &mut plan.errors);
        let before = cells.error_count();
        let Some(code) = cells.trimmed("code").value() else {
            cells.error(Some("code"), "code is required");
            continue;
        };
        if let Some(first) = seen.insert(code.clone(), row.line) {
            cells.error(
                Some("code"),
                format!("code {code} appears twice (first on line {first})"),
            );
            continue;
        }
        let current = existing.get(&code);

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
                code: code.clone(),
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
            &COLUMNS,
        );
        // The VAT rule (ADR 0058) applies to a number the file adds or changes, so that an
        // untouched legacy number does not stop a re-import of an export.
        if let Some(m) = input.vat_problem(current.and_then(|c| c.vat_number.as_deref())) {
            cells.error(Some("vat_number"), m);
        }
        if cells.error_count() > before {
            continue;
        }

        match current {
            Some(c) if same(c, &input, zone) => plan.unchanged += 1,
            Some(c) => plan.actions.push(Action::Update {
                id: c.id,
                terms: zone.is_some(),
                input,
            }),
            None => plan.actions.push(Action::Create { input }),
        }
    }
    Ok(plan)
}

/// Creates or updates customers from CSV, keyed by `code`. All-or-nothing: with any row error
/// nothing is written (422 with every error); `dry_run=true` only reports.
#[utoipa::path(post, path = "/customers/import", tag = "crm", operation_id = "import_customers",
    params(ImportParams),
    request_body(content = String, content_type = "text/csv"),
    responses((status = 200, body = ImportReport), (status = 403, body = ErrorBody),
        (status = 413, description = "Body larger than 5 MB"), (status = 422, body = ImportReport)))]
async fn import_customers(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(p): Query<ImportParams>,
    body: Bytes,
) -> AppResult<(StatusCode, Json<ImportReport>)> {
    user.require(Permission::CustomersWrite)?;
    let table = match parse_table(&body, &COLUMNS, &["code"]) {
        Ok(t) => t,
        Err(errors) => return Ok(ImportReport::failed(errors).into_response()),
    };
    csv_io::with_replan(|| run_import(&state, &user, &table, p.dry_run)).await
}

/// One attempt: plan in a transaction and, when the plan is clean and this is no dry run, write it.
/// A unique-key conflict at write time (a concurrent creation of the same code) fails the attempt;
/// [`csv_io::with_replan`] then plans again against the committed data.
async fn run_import(
    state: &AppState,
    user: &CurrentUser,
    table: &csv_io::CsvTable,
    dry_run: bool,
) -> AppResult<(StatusCode, Json<ImportReport>)> {
    let mut tx = state.db.begin().await?;
    let plan = plan(&mut tx, user.company_id, table).await?;
    let mut report = ImportReport::planned(plan.unchanged, &table.width_errors, plan.errors);
    for a in &plan.actions {
        match a {
            Action::Create { .. } => report.created += 1,
            Action::Update { .. } => report.updated += 1,
        }
    }
    if !report.errors.is_empty() || dry_run {
        return Ok(report.into_response());
    }
    for a in plan.actions {
        match a {
            Action::Create { input } => {
                let id = new_id();
                insert_customer(&mut tx, id, &input).await?;
                upsert_terms(&mut tx, user.company_id, id, &input).await?;
                audit::record(
                    &mut tx,
                    user,
                    "customer",
                    id,
                    "created",
                    serde_json::json!({ "code": input.code, "source": "csv_import" }),
                )
                .await?;
            }
            Action::Update { id, input, terms } => {
                update_customer_row(&mut tx, id, &input).await?;
                if terms {
                    upsert_terms(&mut tx, user.company_id, id, &input).await?;
                }
                audit::record(
                    &mut tx,
                    user,
                    "customer",
                    id,
                    "updated",
                    serde_json::json!({ "source": "csv_import" }),
                )
                .await?;
            }
        }
    }
    tx.commit().await?;
    Ok(report.into_response())
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
