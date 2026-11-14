//! Products as CSV: an export and an all-or-nothing upsert-by-`code` import (see
//! `docs/adr/0029-csv-export-import.md`).
//!
//! Not part of the file: the standard cost (permissioned, set in the product form) and the zone
//! prices (dated history, see the price endpoints).

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
use tradocraft_core::{audit, new_id, AppError, AppResult, AppState, CurrentUser, Permission};
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::{
    barcode, check_packaging, check_service_conversion, insert_product, update_product_row,
    Product, ProductInput, SELECT_PRODUCT, SELECT_PRODUCT_LOCKABLE,
};

/// The columns, in export order. `code` is the key; the others are optional in an import file.
pub const COLUMNS: [&str; 20] = [
    "code",
    "name",
    "description",
    "unit",
    "product_type",
    "vat_rate",
    "tracking",
    "family_code",
    "pricing_type",
    "active",
    "reorder_min",
    "reorder_max",
    "lead_time_days",
    "barcode",
    "packaging_category_code",
    "length_mm",
    "width_mm",
    "height_mm",
    "weight_g",
    "default_production_remark",
];

/// One product as the cells of an export row, in [`COLUMNS`] order.
fn export_row(p: &Product) -> Vec<String> {
    let opt = |v: &Option<String>| v.clone().unwrap_or_default();
    let dec = |v: Option<Decimal>| v.map(format_decimal).unwrap_or_default();
    let int = |v: Option<i32>| v.map(|v| v.to_string()).unwrap_or_default();
    vec![
        p.code.clone(),
        p.name.clone(),
        p.description.clone(),
        p.unit.clone(),
        p.product_type.clone(),
        format_decimal(p.vat_rate),
        p.tracking.clone(),
        opt(&p.family_code),
        p.pricing_type.clone(),
        p.active.to_string(),
        dec(p.reorder_min),
        dec(p.reorder_max),
        int(p.lead_time_days),
        opt(&p.barcode),
        opt(&p.packaging_category_code),
        int(p.length_mm),
        int(p.width_mm),
        int(p.height_mm),
        int(p.weight_g),
        p.default_production_remark.clone(),
    ]
}

/// All products as CSV, ordered by code.
#[utoipa::path(get, path = "/products/export", tag = "products", operation_id = "export_products",
    responses((status = 200, body = String, content_type = "text/csv"), (status = 403, body = ErrorBody)))]
async fn export_products(
    State(state): State<AppState>,
    user: CurrentUser,
) -> AppResult<(HeaderMap, String)> {
    user.require(Permission::ProductsRead)?;
    let products: Vec<Product> = sqlx::query_as(&format!("{SELECT_PRODUCT} ORDER BY code"))
        .fetch_all(&state.db)
        .await?;
    let body = csv_io::write_csv(&COLUMNS, products.iter().map(export_row));
    Ok(csv_io::download("products.csv", body))
}

/// What an import does with one valid row.
enum Action {
    Create(ProductInput),
    Update(Uuid, ProductInput),
}

/// The outcome of checking a whole file: what to write and what was found wrong.
#[derive(Default)]
struct Plan {
    actions: Vec<Action>,
    unchanged: usize,
    errors: Vec<RowError>,
}

/// Whether the stored product already equals what the row would write (so nothing is written).
fn same(p: &Product, i: &ProductInput) -> bool {
    p.name == i.name
        && p.description == i.description
        && p.unit == i.unit
        && p.product_type == i.product_type
        && p.vat_rate == i.vat_rate
        && p.tracking == i.tracking
        && p.family_id == i.family_id
        && p.pricing_type == i.pricing_type
        && p.active == i.active
        && p.reorder_min == i.reorder_min
        && p.reorder_max == i.reorder_max
        && p.lead_time_days == i.lead_time_days
        && p.barcode.as_deref() == barcode(i)
        && p.packaging_category_id == i.packaging_category_id
        && p.length_mm == i.length_mm
        && p.width_mm == i.width_mm
        && p.height_mm == i.height_mm
        && p.weight_g == i.weight_g
        && p.default_production_remark == i.default_production_remark.trim()
}

/// A reference column holding a code of another table: a value looks it up, blank clears it.
fn reference(
    cells: &mut Cells<'_>,
    column: &str,
    lookup: &HashMap<String, Uuid>,
    target: &mut Option<Uuid>,
) {
    match cells.trimmed(column) {
        Cell::Value(code) => match lookup.get(&code) {
            Some(id) => *target = Some(*id),
            None => cells.error(Some(column), format!("unknown code {code:?}")),
        },
        Cell::Blank => *target = None,
        Cell::Absent => {}
    }
}

/// A decimal that must fit `numeric(precision, scale)` of its column.
fn bounded(cells: &mut Cells<'_>, column: &str, scale: u32, max: Decimal) -> Cell<Decimal> {
    match cells.decimal(column) {
        Cell::Value(d) if d.normalize().scale() > scale => {
            cells.error(
                Some(column),
                format!("at most {scale} decimals are allowed"),
            );
            Cell::Absent
        }
        Cell::Value(d) if d.abs() > max => {
            cells.error(Some(column), format!("must be at most {max}"));
            Cell::Absent
        }
        other => other,
    }
}

/// A `(code, id)` query as a lookup table.
async fn code_map(conn: &mut sqlx::PgConnection, sql: &str) -> AppResult<HashMap<String, Uuid>> {
    Ok(sqlx::query_as::<_, (String, Uuid)>(sql)
        .fetch_all(conn)
        .await?
        .into_iter()
        .collect())
}

/// Checks every row against the database and decides what each one would do.
async fn plan(conn: &mut sqlx::PgConnection, table: &csv_io::CsvTable) -> AppResult<Plan> {
    let families = code_map(conn, "SELECT code, id FROM products.product_families").await?;
    let categories = code_map(conn, "SELECT code, id FROM products.packaging_categories").await?;
    let codes: Vec<String> = table
        .rows
        .iter()
        .filter_map(|r| r.get_trimmed("code"))
        .map(str::to_string)
        .collect();
    // Read and lock the rows we are going to change (as a manual edit does) in one statement, so a
    // concurrent edit cannot slip in between the read and the lock.
    let existing: HashMap<String, Product> = sqlx::query_as::<_, Product>(&format!(
        "{SELECT_PRODUCT_LOCKABLE} WHERE p.code = ANY($1) ORDER BY p.id FOR UPDATE OF p"
    ))
    .bind(&codes)
    .fetch_all(&mut *conn)
    .await?
    .into_iter()
    .map(|p| (p.code.clone(), p))
    .collect();
    let barcodes: Vec<String> = table
        .rows
        .iter()
        .filter_map(|r| r.get_trimmed("barcode"))
        .map(str::to_string)
        .collect();
    let barcode_owner: HashMap<String, String> = sqlx::query_as::<_, (String, String)>(
        "SELECT barcode, code FROM products.products WHERE barcode = ANY($1)",
    )
    .bind(&barcodes)
    .fetch_all(&mut *conn)
    .await?
    .into_iter()
    .collect();

    let mut plan = Plan::default();
    let mut seen_codes: HashMap<String, usize> = HashMap::new();
    let mut seen_barcodes: HashMap<String, usize> = HashMap::new();
    for row in &table.rows {
        let mut cells = Cells::new(row, &mut plan.errors);
        let before = cells.error_count();
        let Some(code) = cells.trimmed("code").value() else {
            cells.error(Some("code"), "code is required");
            continue;
        };
        if let Some(first) = seen_codes.insert(code.clone(), row.line) {
            cells.error(
                Some("code"),
                format!("code {code} appears twice (first on line {first})"),
            );
            continue;
        }
        let current = existing.get(&code);

        // Start from the stored values (or the API defaults) and overlay the columns of the file.
        let mut input = match current {
            Some(p) => ProductInput {
                code: p.code.clone(),
                name: p.name.clone(),
                description: p.description.clone(),
                unit: p.unit.clone(),
                product_type: p.product_type.clone(),
                vat_rate: p.vat_rate,
                tracking: p.tracking.clone(),
                family_id: p.family_id,
                pricing_type: p.pricing_type.clone(),
                active: p.active,
                standard_cost: None,
                reorder_min: p.reorder_min,
                reorder_max: p.reorder_max,
                lead_time_days: p.lead_time_days,
                barcode: p.barcode.clone(),
                packaging_category_id: p.packaging_category_id,
                length_mm: p.length_mm,
                width_mm: p.width_mm,
                height_mm: p.height_mm,
                weight_g: p.weight_g,
                default_production_remark: p.default_production_remark.clone(),
            },
            None => ProductInput {
                code: code.clone(),
                name: String::new(),
                description: String::new(),
                unit: "pcs".into(),
                product_type: "purchased".into(),
                vat_rate: Decimal::ZERO,
                tracking: "none".into(),
                family_id: None,
                pricing_type: "list".into(),
                active: true,
                standard_cost: None,
                reorder_min: None,
                reorder_max: None,
                lead_time_days: None,
                barcode: None,
                packaging_category_id: None,
                length_mm: None,
                width_mm: None,
                height_mm: None,
                weight_g: None,
                default_production_remark: String::new(),
            },
        };
        cells.text("name").apply(&mut input.name);
        cells.text("description").apply(&mut input.description);
        cells.text("unit").apply(&mut input.unit);
        cells.trimmed("product_type").apply(&mut input.product_type);
        cells.trimmed("tracking").apply(&mut input.tracking);
        cells.trimmed("pricing_type").apply(&mut input.pricing_type);
        cells.boolean("active").apply(&mut input.active);
        let vat = bounded(&mut cells, "vat_rate", 2, Decimal::new(99999, 2));
        vat.apply(&mut input.vat_rate);
        bounded(
            &mut cells,
            "reorder_min",
            4,
            Decimal::new(99_999_999_999_999, 4),
        )
        .apply_opt(&mut input.reorder_min);
        bounded(
            &mut cells,
            "reorder_max",
            4,
            Decimal::new(99_999_999_999_999, 4),
        )
        .apply_opt(&mut input.reorder_max);
        cells
            .int("lead_time_days")
            .apply_opt(&mut input.lead_time_days);
        cells.trimmed("barcode").apply_opt(&mut input.barcode);
        cells.int("length_mm").apply_opt(&mut input.length_mm);
        cells.int("width_mm").apply_opt(&mut input.width_mm);
        cells.int("height_mm").apply_opt(&mut input.height_mm);
        cells.int("weight_g").apply_opt(&mut input.weight_g);
        cells
            .text("default_production_remark")
            .apply(&mut input.default_production_remark);
        reference(&mut cells, "family_code", &families, &mut input.family_id);
        reference(
            &mut cells,
            "packaging_category_code",
            &categories,
            &mut input.packaging_category_id,
        );
        input.name = input.name.trim().to_string();

        if input.name.is_empty() {
            let message = if current.is_none() {
                "name is required for a new product"
            } else {
                "name cannot be empty"
            };
            cells.error(Some("name"), message);
        }
        if current.is_none() && row.get_trimmed("vat_rate").is_none() {
            cells.error(Some("vat_rate"), "vat_rate is required for a new product");
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
        if let Some(b) = barcode(&input) {
            if let Some(first) = seen_barcodes.insert(b.to_string(), row.line) {
                cells.error(
                    Some("barcode"),
                    format!("barcode {b} appears twice (first on line {first})"),
                );
            } else if barcode_owner.get(b).is_some_and(|owner| *owner != code) {
                cells.error(
                    Some("barcode"),
                    format!("barcode {b} is used by product {}", barcode_owner[b]),
                );
            }
        }
        // Database-backed rules of the API (packaging category, stock moves vs. service). Each runs
        // whenever its own input is usable, whatever else is wrong with the row.
        let (stored_type, stored_packaging) = current
            .map(|p| (p.product_type.as_str(), p.packaging_category_id))
            .unwrap_or(("", None));
        let mut checks: Vec<AppResult<()>> = Vec::new();
        if !cells.failed_since(before, "packaging_category_code") {
            checks.push(check_packaging(conn, input.packaging_category_id, stored_packaging).await);
        }
        if let Some(p) = current {
            checks
                .push(check_service_conversion(conn, p.id, stored_type, &input.product_type).await);
        }
        for check in checks {
            match check {
                Ok(()) => {}
                Err(AppError::Validation(m) | AppError::Conflict(m)) => {
                    let column = m
                        .contains("packaging")
                        .then_some("packaging_category_code")
                        .or(m.contains("service").then_some("product_type"));
                    cells.error(column, m)
                }
                Err(e) => return Err(e),
            }
        }
        if cells.error_count() > before {
            continue;
        }

        match current {
            Some(p) if same(p, &input) => plan.unchanged += 1,
            Some(p) => plan.actions.push(Action::Update(p.id, input)),
            None => plan.actions.push(Action::Create(input)),
        }
    }
    Ok(plan)
}

/// Creates or updates products from CSV, keyed by `code`. All-or-nothing: with any row error
/// nothing is written (422 with every error); `dry_run=true` only reports.
#[utoipa::path(post, path = "/products/import", tag = "products", operation_id = "import_products",
    params(ImportParams),
    request_body(content = String, content_type = "text/csv"),
    responses((status = 200, body = ImportReport), (status = 403, body = ErrorBody),
        (status = 413, description = "Body larger than 5 MB"), (status = 422, body = ImportReport)))]
async fn import_products(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(p): Query<ImportParams>,
    body: Bytes,
) -> AppResult<(StatusCode, Json<ImportReport>)> {
    user.require(Permission::ProductsWrite)?;
    let table = match parse_table(&body, &COLUMNS, &["code"]) {
        Ok(t) => t,
        Err(errors) => return Ok(ImportReport::failed(errors).into_response()),
    };
    csv_io::with_replan(|| run_import(&state, &user, &table, p.dry_run)).await
}

/// One attempt: plan in a transaction and, when the plan is clean and this is no dry run, write it.
/// A unique-key conflict at write time (a barcode or code taken by a concurrent writer) fails the
/// attempt; [`csv_io::with_replan`] then plans again, and the new plan reports a taken barcode as
/// a row error and turns a create of a code that now exists into an update.
async fn run_import(
    state: &AppState,
    user: &CurrentUser,
    table: &csv_io::CsvTable,
    dry_run: bool,
) -> AppResult<(StatusCode, Json<ImportReport>)> {
    let mut tx = state.db.begin().await?;
    let plan = plan(&mut tx, table).await?;
    let mut report = ImportReport::planned(plan.unchanged, &table.width_errors, plan.errors);
    for a in &plan.actions {
        match a {
            Action::Create(_) => report.created += 1,
            Action::Update(..) => report.updated += 1,
        }
    }
    if !report.errors.is_empty() || dry_run {
        return Ok(report.into_response());
    }
    for a in plan.actions {
        match a {
            Action::Create(input) => {
                let id = new_id();
                insert_product(&mut tx, id, &input, false).await?;
                audit::record(
                    &mut tx,
                    user,
                    "product",
                    id,
                    "created",
                    serde_json::json!({ "code": input.code, "source": "csv_import" }),
                )
                .await?;
            }
            Action::Update(id, input) => {
                update_product_row(&mut tx, id, &input, false).await?;
                audit::record(
                    &mut tx,
                    user,
                    "product",
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

/// The routes of the product export and import (the import with its own body limit).
pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new().routes(routes!(export_products)).merge(
        OpenApiRouter::new()
            .routes(routes!(import_products))
            .layer(DefaultBodyLimit::max(csv_io::MAX_BODY_BYTES)),
    )
}
