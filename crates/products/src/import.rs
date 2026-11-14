//! Products as an importable entity (ADR 0029, ADR 0064): an export and an all-or-nothing
//! upsert-by-`code` import in CSV, XLSX or ODS. Everything shared lives in
//! `tradocraft_core::import`; this file holds only what is the products'.
//!
//! Not part of the file: the standard cost (permissioned, set in the product form) and the zone
//! prices (dated history, see the price endpoints).

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
use tradocraft_core::{AppError, AppResult, AppState, CurrentUser, Permission};
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::{
    barcode, check_packaging, check_service_conversion, insert_product, update_product_row,
    Product, ProductInput, SELECT_PRODUCT, SELECT_PRODUCT_LOCKABLE,
};

/// The columns, in export order. `code` is the key; the others are optional in an import file.
/// `required` means a new product needs a value.
const COLUMNS: [Column; 20] = [
    Column::new("code", ColumnKind::Code, true),
    Column::new("name", ColumnKind::Text, true),
    Column::new("description", ColumnKind::Text, false),
    Column::new("unit", ColumnKind::Text, false),
    Column::new("product_type", ColumnKind::Code, false),
    Column::new("vat_rate", ColumnKind::Decimal, true),
    Column::new("tracking", ColumnKind::Code, false),
    Column::new("family_code", ColumnKind::Code, false),
    Column::new("pricing_type", ColumnKind::Code, false),
    Column::new("active", ColumnKind::Boolean, false),
    Column::new("reorder_min", ColumnKind::Decimal, false),
    Column::new("reorder_max", ColumnKind::Decimal, false),
    Column::new("lead_time_days", ColumnKind::Integer, false),
    Column::new("barcode", ColumnKind::Code, false),
    Column::new("packaging_category_code", ColumnKind::Code, false),
    Column::new("length_mm", ColumnKind::Integer, false),
    Column::new("width_mm", ColumnKind::Integer, false),
    Column::new("height_mm", ColumnKind::Integer, false),
    Column::new("weight_g", ColumnKind::Integer, false),
    Column::new("default_production_remark", ColumnKind::Text, false),
];

/// One product as the cells of an export row, in [`COLUMNS`] order.
fn export_row(p: &Product) -> Vec<CellValue> {
    let opt = |v: &Option<String>| CellValue::text(v.clone().unwrap_or_default());
    let dec = |v: Option<Decimal>| v.map_or(CellValue::Empty, |d| CellValue::Number(d.normalize()));
    let int = |v: Option<i32>| v.map_or(CellValue::Empty, |v| CellValue::int(v.into()));
    vec![
        CellValue::text(&p.code),
        CellValue::text(&p.name),
        CellValue::text(&p.description),
        CellValue::text(&p.unit),
        CellValue::text(&p.product_type),
        CellValue::Number(p.vat_rate.normalize()),
        CellValue::text(&p.tracking),
        opt(&p.family_code),
        CellValue::text(&p.pricing_type),
        CellValue::Bool(p.active),
        dec(p.reorder_min),
        dec(p.reorder_max),
        int(p.lead_time_days),
        opt(&p.barcode),
        opt(&p.packaging_category_code),
        int(p.length_mm),
        int(p.width_mm),
        int(p.height_mm),
        int(p.weight_g),
        CellValue::text(&p.default_production_remark),
    ]
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

/// What the rows of one run are checked against.
pub struct ProductContext {
    families: HashMap<String, Uuid>,
    categories: HashMap<String, Uuid>,
    /// Barcodes of the file that already belong to a product: barcode -> product code.
    barcode_owner: HashMap<String, String>,
    /// Barcodes seen so far in the file: barcode -> first line.
    seen_barcodes: HashMap<String, usize>,
}

/// The products as an importable entity.
pub struct Products;

impl Importable for Products {
    type Stored = Product;
    type Change = ProductInput;
    type Context = ProductContext;

    const KEY: &'static str = "products";
    const AUDIT_ENTITY: &'static str = "product";
    const READ: Permission = Permission::ProductsRead;
    const WRITE: Permission = Permission::ProductsWrite;
    const FILE_STEM: &'static str = "products";
    const COLUMNS: &'static [Column] = &COLUMNS;

    async fn context(
        conn: &mut PgConnection,
        _user: &CurrentUser,
        table: &Table,
    ) -> AppResult<ProductContext> {
        let families = code_map(conn, "SELECT code, id FROM products.product_families").await?;
        let categories =
            code_map(conn, "SELECT code, id FROM products.packaging_categories").await?;
        let barcodes: Vec<String> = table
            .rows
            .iter()
            .filter_map(|r| r.get_trimmed("barcode"))
            .map(str::to_string)
            .collect();
        let barcode_owner = sqlx::query_as::<_, (String, String)>(
            "SELECT barcode, code FROM products.products WHERE barcode = ANY($1)",
        )
        .bind(&barcodes)
        .fetch_all(conn)
        .await?
        .into_iter()
        .collect();
        Ok(ProductContext {
            families,
            categories,
            barcode_owner,
            seen_barcodes: HashMap::new(),
        })
    }

    async fn load(
        conn: &mut PgConnection,
        _user: &CurrentUser,
        keys: &[String],
    ) -> AppResult<Vec<(String, Product)>> {
        // Read and lock the rows we are going to change (as a manual edit does) in one statement,
        // so a concurrent edit cannot slip in between the read and the lock.
        Ok(sqlx::query_as::<_, Product>(&format!(
            "{SELECT_PRODUCT_LOCKABLE} WHERE p.code = ANY($1) ORDER BY p.id FOR UPDATE OF p"
        ))
        .bind(keys)
        .fetch_all(conn)
        .await?
        .into_iter()
        .map(|p| (p.code.clone(), p))
        .collect())
    }

    fn stored_id(stored: &Product) -> Uuid {
        stored.id
    }

    async fn plan_row(
        conn: &mut PgConnection,
        _user: &CurrentUser,
        context: &mut ProductContext,
        key: &str,
        current: Option<&Product>,
        row: &Row,
        cells: &mut Cells<'_>,
    ) -> AppResult<ProductInput> {
        let ProductContext {
            families,
            categories,
            barcode_owner,
            seen_barcodes,
        } = context;
        let before = cells.error_count();
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
                code: key.to_string(),
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
        let vat = bounded(cells, "vat_rate", 2, Decimal::new(99999, 2));
        vat.apply(&mut input.vat_rate);
        bounded(cells, "reorder_min", 4, Decimal::new(99_999_999_999_999, 4))
            .apply_opt(&mut input.reorder_min);
        bounded(cells, "reorder_max", 4, Decimal::new(99_999_999_999_999, 4))
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
        reference(cells, "family_code", families, &mut input.family_id);
        reference(
            cells,
            "packaging_category_code",
            categories,
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
            &import::column_names::<Self>(),
        );
        if let Some(b) = barcode(&input) {
            if let Some(first) = seen_barcodes.insert(b.to_string(), row.line) {
                cells.error(
                    Some("barcode"),
                    format!("barcode {b} appears twice (first on line {first})"),
                );
            } else if barcode_owner.get(b).is_some_and(|owner| *owner != key) {
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
        Ok(input)
    }

    fn unchanged(stored: &Product, change: &ProductInput) -> bool {
        same(stored, change)
    }

    async fn create(
        conn: &mut PgConnection,
        _user: &CurrentUser,
        id: Uuid,
        change: &ProductInput,
    ) -> AppResult<()> {
        insert_product(conn, id, change, false).await
    }

    async fn update(
        conn: &mut PgConnection,
        _user: &CurrentUser,
        id: Uuid,
        change: &ProductInput,
    ) -> AppResult<()> {
        update_product_row(conn, id, change, false).await
    }

    async fn export(pool: &PgPool, _user: &CurrentUser) -> AppResult<Vec<Vec<CellValue>>> {
        let products: Vec<Product> = sqlx::query_as(&format!("{SELECT_PRODUCT} ORDER BY code"))
            .fetch_all(pool)
            .await?;
        Ok(products.iter().map(export_row).collect())
    }
}

/// The products' handle for the import registry and the background worker.
pub fn products_import() -> ImportEntity {
    ImportEntity::of::<Products>()
}

/// All products as CSV, XLSX or ODS, ordered by code.
#[utoipa::path(get, path = "/products/export", tag = "products", operation_id = "export_products",
    params(ExportParams),
    responses((status = 200, content(
            (String = "text/csv"),
            (String = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"),
            (String = "application/vnd.oasis.opendocument.spreadsheet"))),
        (status = 403, body = ErrorBody)))]
async fn export_products(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(p): Query<ExportParams>,
) -> AppResult<(HeaderMap, Vec<u8>)> {
    import::export_request::<Products>(&state.db, &user, &p).await
}

/// Creates or updates products from a CSV, XLSX or ODS file (detected from the content), keyed by
/// `code`. All-or-nothing: with any row error nothing is written (422 with every error);
/// `dry_run=true` only reports. `sheet` picks the sheet of a spreadsheet.
#[utoipa::path(post, path = "/products/import", tag = "products", operation_id = "import_products",
    params(ImportParams),
    request_body(content(
        (String = "application/octet-stream"),
        (String = "text/csv"))),
    responses((status = 200, body = ImportReport), (status = 403, body = ErrorBody),
        (status = 413, description = "Body larger than 5 MB"), (status = 422, body = ImportReport)))]
async fn import_products(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(p): Query<ImportParams>,
    body: Bytes,
) -> AppResult<(StatusCode, Json<ImportReport>)> {
    import::import_request::<Products>(&state.db, &user, &p, &body).await
}

/// The routes of the product export and import (the import with its own body limit).
pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new().routes(routes!(export_products)).merge(
        OpenApiRouter::new()
            .routes(routes!(import_products))
            .layer(DefaultBodyLimit::max(csv_io::MAX_BODY_BYTES)),
    )
}
