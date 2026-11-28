//! Products as an importable entity (ADR 0029, ADR 0067): an export and an all-or-nothing
//! upsert-by-`code` import in CSV, XLSX or ODS. Everything shared lives in
//! `tradocraft_core::import`; this file holds only what is the products'.
//!
//! The name and description of a product per language (`name_<code>`, `description_<code>` for
//! any ISO 639-1 code) are part of the file (ADR 0100): they read and write
//! `products.product_translations`.
//!
//! Not part of the file: the standard cost (permissioned, set in the product form). The zone
//! prices are an entity of their own (`zone_prices`, ADR 0100).

use std::collections::{BTreeMap, HashMap};

use axum::body::Bytes;
use axum::extract::{DefaultBodyLimit, Query, State};
use axum::http::{HeaderMap, StatusCode};
use axum::Json;
use rust_decimal::Decimal;
use sqlx::{PgConnection, PgPool};
use tradocraft_core::csv_io::{self, ImportParams, ImportReport};
use tradocraft_core::error::ErrorBody;
use tradocraft_core::import::{
    self, BinaryFile, Cell, CellValue, Cells, Column, ColumnKind, ExportParams, ExportTable,
    ImportEntity, Importable, Row, Table,
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
const COLUMNS: [Column; 27] = [
    Column::new("code", ColumnKind::Code, true),
    Column::new("name", ColumnKind::Text, true),
    Column::new("description", ColumnKind::Text, false),
    Column::new("unit", ColumnKind::Text, false),
    Column::new("product_type", ColumnKind::Code, false),
    Column::new("vat_rate", ColumnKind::Decimal, false),
    Column::new("tracking", ColumnKind::Code, false),
    Column::new("family_code", ColumnKind::Code, false),
    Column::new("non_discountable", ColumnKind::Boolean, false),
    Column::new("price_on_request", ColumnKind::Boolean, false),
    Column::new("price_is_indicative", ColumnKind::Boolean, false),
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
    Column::new("vat_category", ColumnKind::Code, false),
    Column::new("vat_rate_override", ColumnKind::Decimal, false),
    Column::new("included_in_turnover", ColumnKind::Boolean, false),
    Column::per_language(NAME, ColumnKind::Text),
    Column::per_language(DESCRIPTION, ColumnKind::Text),
];

/// The prefixes of the translation columns `name_<code>` and `description_<code>`.
const NAME: &str = "name";
const DESCRIPTION: &str = "description";

/// The languages of the translation columns among the bound `columns`, sorted.
fn file_languages(columns: &[String]) -> Vec<String> {
    let mut languages = import::family_languages(columns, NAME);
    languages.extend(import::family_languages(columns, DESCRIPTION));
    languages.sort();
    languages.dedup();
    languages
}

/// The name and description of a product in one language.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Translation {
    pub name: String,
    pub description: String,
}

/// A stored product with its translations in the languages of the file.
pub struct StoredProduct {
    product: Product,
    translations: BTreeMap<String, Translation>,
}

/// What one row writes: the product, and the translations of the languages the row sets (the
/// other languages are left as they are).
pub struct ProductChange {
    input: ProductInput,
    translations: BTreeMap<String, Translation>,
}

/// The translation a row asks for in one language, or None when the row leaves it as it is.
///
/// * A name (not blank) sets the name; the description is the description cell, or the stored
///   one when the column is not in the file (empty for a new translation).
/// * No name but a description: the stored translation gets the description; without a stored
///   translation the product's own name becomes the translation's name, since a translation
///   needs one.
/// * Neither (blank or absent cells): unchanged. An import never deletes a translation.
fn translation_target(
    name: Cell<String>,
    description: Cell<String>,
    stored: Option<&Translation>,
    base_name: &str,
) -> Option<Translation> {
    let name = match name {
        Cell::Value(v) if !v.trim().is_empty() => Some(v.trim().to_string()),
        _ => None,
    };
    let description = match description {
        Cell::Absent => None,
        Cell::Blank => Some(String::new()),
        Cell::Value(v) => Some(v.trim().to_string()),
    };
    match (name, description) {
        (Some(name), description) => Some(Translation {
            name,
            description: description
                .or_else(|| stored.map(|t| t.description.clone()))
                .unwrap_or_default(),
        }),
        (None, Some(description)) if !description.is_empty() => Some(Translation {
            name: stored.map_or_else(|| base_name.to_string(), |t| t.name.clone()),
            description,
        }),
        (None, _) => None,
    }
}

/// The translations of `ids`, per product.
async fn load_translations(
    conn: &mut PgConnection,
    ids: &[Uuid],
) -> AppResult<HashMap<Uuid, BTreeMap<String, Translation>>> {
    let rows: Vec<(Uuid, String, String, String)> = sqlx::query_as(
        "SELECT product_id, language::text, name, description FROM products.product_translations
         WHERE product_id = ANY($1)",
    )
    .bind(ids)
    .fetch_all(conn)
    .await?;
    let mut out: HashMap<Uuid, BTreeMap<String, Translation>> = HashMap::new();
    for (id, language, name, description) in rows {
        out.entry(id)
            .or_default()
            .insert(language, Translation { name, description });
    }
    Ok(out)
}

/// Writes the translations of a change that differ from what is stored.
async fn write_translations(
    conn: &mut PgConnection,
    id: Uuid,
    translations: &BTreeMap<String, Translation>,
) -> AppResult<()> {
    for (language, t) in translations {
        sqlx::query(
            "INSERT INTO products.product_translations (product_id, language, name, description)
             VALUES ($1, $2, $3, $4)
             ON CONFLICT (product_id, language) DO UPDATE
                SET name = EXCLUDED.name, description = EXCLUDED.description, updated_at = now()
                WHERE product_translations.name <> EXCLUDED.name
                   OR product_translations.description <> EXCLUDED.description",
        )
        .bind(id)
        .bind(language)
        .bind(&t.name)
        .bind(&t.description)
        .execute(&mut *conn)
        .await?;
    }
    Ok(())
}

/// One product as the cells of an export row, in [`COLUMNS`] order.
/// The translation cells follow for each of `languages`.
fn export_row(
    p: &Product,
    translations: Option<&BTreeMap<String, Translation>>,
    languages: &[String],
) -> Vec<CellValue> {
    let opt = |v: &Option<String>| CellValue::text(v.clone().unwrap_or_default());
    let dec = |v: Option<Decimal>| v.map_or(CellValue::Empty, |d| CellValue::Number(d.normalize()));
    let int = |v: Option<i32>| v.map_or(CellValue::Empty, |v| CellValue::int(v.into()));
    let mut row = vec![
        CellValue::text(&p.code),
        CellValue::text(&p.name),
        CellValue::text(&p.description),
        CellValue::text(&p.unit),
        CellValue::text(&p.product_type),
        CellValue::Number(p.vat_rate.normalize()),
        CellValue::text(&p.tracking),
        opt(&p.family_code),
        CellValue::Bool(p.non_discountable),
        CellValue::Bool(p.price_on_request),
        CellValue::Bool(p.price_is_indicative),
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
        CellValue::text(&p.vat_category),
        dec(p.vat_rate_override),
        p.included_in_turnover
            .map_or(CellValue::Empty, CellValue::Bool),
    ];
    for language in languages {
        match translations.and_then(|t| t.get(language)) {
            Some(t) => {
                row.push(CellValue::text(&t.name));
                row.push(CellValue::text(&t.description));
            }
            None => row.extend([CellValue::Empty, CellValue::Empty]),
        }
    }
    row
}

/// Whether the stored product already equals what the row would write (so nothing is written).
fn same(p: &Product, i: &ProductInput) -> bool {
    let target_cat = i.vat_category.as_deref().unwrap_or(&p.vat_category);
    p.name == i.name
        && p.description == i.description
        && p.unit == i.unit
        && p.product_type == i.product_type
        && i.vat_rate.is_none_or(|r| p.vat_rate == r)
        && p.vat_category == target_cat
        && p.vat_rate_override == i.vat_rate_override
        && p.tracking == i.tracking
        && p.family_id == i.family_id
        && p.non_discountable == i.non_discountable
        && p.price_on_request == i.price_on_request
        && p.price_is_indicative == i.price_is_indicative
        && i.included_in_turnover
            .is_none_or(|value| p.included_in_turnover == value)
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
async fn code_map(
    conn: &mut sqlx::PgConnection,
    sql: impl sqlx::SqlSafeStr,
) -> AppResult<HashMap<String, Uuid>> {
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
    company_country: String,
    vat_rules: Vec<tradocraft_core::vat_rates::CountryVatRate>,
    /// The languages with a name or description column in the file.
    languages: Vec<String>,
}

/// The products as an importable entity.
pub struct Products;

impl Importable for Products {
    type Stored = StoredProduct;
    type Change = ProductChange;
    type Context = ProductContext;

    const KEY: &'static str = "products";
    const AUDIT_ENTITY: &'static str = "product";
    const READ: Permission = Permission::ProductsRead;
    const WRITE: Permission = Permission::ProductsWrite;
    const FILE_STEM: &'static str = "products";
    const COLUMNS: &'static [Column] = &COLUMNS;

    async fn context(
        conn: &mut PgConnection,
        user: &CurrentUser,
        table: &Table,
    ) -> AppResult<ProductContext> {
        let families = code_map(conn, "SELECT code, id FROM products.product_families").await?;
        let categories =
            code_map(conn, "SELECT code, id FROM products.packaging_categories").await?;
        let company = tradocraft_core::company::get_company(&mut *conn, user.company_id).await?;
        let vat_rules =
            tradocraft_core::vat_rates::load_country_rules(&mut *conn, &company.country_code)
                .await?;
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
            company_country: company.country_code,
            vat_rules,
            languages: file_languages(&table.columns),
        })
    }

    async fn load(
        conn: &mut PgConnection,
        user: &CurrentUser,
        keys: &[String],
    ) -> AppResult<Vec<(String, StoredProduct)>> {
        // Read and lock the rows we are going to change (as a manual edit does) in one statement,
        // so a concurrent edit cannot slip in between the read and the lock.
        let company = tradocraft_core::company::get_company(&mut *conn, user.company_id).await?;
        let vat_rules =
            tradocraft_core::vat_rates::load_country_rules(&mut *conn, &company.country_code)
                .await?;
        let mut products = sqlx::query_as::<_, Product>(sqlx::AssertSqlSafe(format!(
            "{SELECT_PRODUCT_LOCKABLE} WHERE p.code = ANY($1) ORDER BY p.id FOR UPDATE OF p"
        )))
        .bind(keys)
        .fetch_all(&mut *conn)
        .await?;
        crate::apply_resolved_vat(
            &mut products,
            &company.country_code,
            &vat_rules,
            tradocraft_core::today(),
        );
        let ids: Vec<Uuid> = products.iter().map(|p| p.id).collect();
        let mut translations = load_translations(conn, &ids).await?;
        Ok(products
            .into_iter()
            .map(|p| {
                let t = translations.remove(&p.id).unwrap_or_default();
                (
                    p.code.clone(),
                    StoredProduct {
                        product: p,
                        translations: t,
                    },
                )
            })
            .collect())
    }

    fn stored_id(stored: &StoredProduct) -> Uuid {
        stored.product.id
    }

    async fn plan_row(
        conn: &mut PgConnection,
        _user: &CurrentUser,
        context: &mut ProductContext,
        key: &str,
        current: Option<&StoredProduct>,
        row: &Row,
        cells: &mut Cells<'_>,
    ) -> AppResult<ProductChange> {
        let stored_translations = current.map(|c| &c.translations);
        let current = current.map(|c| &c.product);
        let ProductContext {
            families,
            categories,
            barcode_owner,
            seen_barcodes,
            company_country,
            vat_rules,
            languages,
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
                vat_rate: Some(p.vat_rate),
                vat_category: Some(p.vat_category.clone()),
                vat_rate_override: p.vat_rate_override,
                tracking: p.tracking.clone(),
                family_id: p.family_id,
                non_discountable: p.non_discountable,
                price_on_request: p.price_on_request,
                price_is_indicative: p.price_is_indicative,
                included_in_turnover: None,
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
                safety_stock: p.safety_stock,
                order_multiple: p.order_multiple,
            },
            None => ProductInput {
                code: key.to_string(),
                name: String::new(),
                description: String::new(),
                unit: "pcs".into(),
                product_type: "purchased".into(),
                vat_rate: None,
                vat_category: None,
                vat_rate_override: None,
                tracking: "none".into(),
                family_id: None,
                non_discountable: false,
                price_on_request: false,
                price_is_indicative: false,
                included_in_turnover: None,
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
                safety_stock: None,
                order_multiple: None,
            },
        };
        cells.text("name").apply(&mut input.name);
        cells.text("description").apply(&mut input.description);
        cells.text("unit").apply(&mut input.unit);
        cells.trimmed("product_type").apply(&mut input.product_type);
        cells.trimmed("tracking").apply(&mut input.tracking);
        cells
            .boolean("non_discountable")
            .apply(&mut input.non_discountable);
        cells
            .boolean("price_on_request")
            .apply(&mut input.price_on_request);
        cells
            .boolean("price_is_indicative")
            .apply(&mut input.price_is_indicative);
        input.included_in_turnover = match cells.boolean("included_in_turnover") {
            Cell::Absent => None,
            Cell::Blank => Some(None),
            Cell::Value(value) => Some(Some(value)),
        };
        cells.boolean("active").apply(&mut input.active);

        let cat_cell = cells.trimmed("vat_category");
        let cat_given = !matches!(cat_cell, Cell::Absent);
        cat_cell.apply_opt(&mut input.vat_category);
        if let Some(ref mut c) = input.vat_category {
            *c = c.to_ascii_lowercase();
        }
        let ov_cell = bounded(cells, "vat_rate_override", 2, Decimal::new(99999, 2));
        let ov_given = !matches!(ov_cell, Cell::Absent);
        ov_cell.apply_opt(&mut input.vat_rate_override);
        let vat_cell = bounded(cells, "vat_rate", 2, Decimal::new(99999, 2));
        if let Cell::Value(v) = vat_cell {
            input.vat_rate = Some(v);
            // When CSV updates only `vat_rate` without `vat_category` or `vat_rate_override`,
            // infer category/override from the company country rules if the rate changed.
            if !cat_given && !ov_given && current.is_none_or(|p| p.vat_rate != v) {
                let today = tradocraft_core::today();
                if let Some(inferred) = tradocraft_core::vat_rates::infer_category_for_rate(
                    vat_rules,
                    company_country,
                    v,
                    today,
                ) {
                    input.vat_category = Some(inferred.to_string());
                    input.vat_rate_override = None;
                } else {
                    input.vat_category = Some("standard".to_string());
                    input.vat_rate_override = Some(v);
                }
            }
        } else if (cat_given || ov_given) && input.vat_rate_override.is_some() {
            input.vat_rate = input.vat_rate_override;
        } else if cat_given && input.vat_rate_override.is_none() {
            let cat = input.vat_category.as_deref().unwrap_or("standard");
            input.vat_rate = Some(tradocraft_core::vat_rates::resolve_rate_from_rules(
                vat_rules,
                &tradocraft_core::vat_rates::VatResolutionContext {
                    country_code: company_country,
                    category: cat,
                    product_override: None,
                    vat_regime: None,
                    purpose: None,
                    building_construction_year: None,
                    as_of: tradocraft_core::today(),
                },
            ));
        }

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
        if current.is_none()
            && row.get_trimmed("vat_rate").is_none()
            && row.get_trimmed("vat_category").is_none()
            && row.get_trimmed("vat_rate_override").is_none()
        {
            cells.error(Some("vat_rate"), "vat_rate is required for a new product");
        }
        // Same rules as the API, all of them; each message names the field it is about.
        let name_missing = input.name.is_empty();
        cells.problems(
            input
                .problems()
                .into_iter()
                .filter(|m| !(name_missing && m.starts_with("code and name"))),
            &Self::COLUMNS.iter().map(|c| c.name).collect::<Vec<_>>(),
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
        let mut translations = BTreeMap::new();
        for language in languages.iter() {
            let stored = stored_translations.and_then(|t| t.get(language));
            let name = cells.text(&format!("{NAME}_{language}"));
            let description = cells.text(&format!("{DESCRIPTION}_{language}"));
            if let Some(t) = translation_target(name, description, stored, &input.name) {
                translations.insert(language.clone(), t);
            }
        }
        Ok(ProductChange {
            input,
            translations,
        })
    }

    fn unchanged(stored: &StoredProduct, change: &ProductChange) -> bool {
        same(&stored.product, &change.input)
            && change
                .translations
                .iter()
                .all(|(language, t)| stored.translations.get(language) == Some(t))
    }

    async fn create(
        conn: &mut PgConnection,
        user: &CurrentUser,
        id: Uuid,
        change: &ProductChange,
    ) -> AppResult<()> {
        insert_product(conn, id, user.company_id, &change.input, false).await?;
        write_translations(conn, id, &change.translations).await
    }

    async fn update(
        conn: &mut PgConnection,
        user: &CurrentUser,
        id: Uuid,
        change: &ProductChange,
    ) -> AppResult<()> {
        update_product_row(conn, id, user.company_id, &change.input, false).await?;
        write_translations(conn, id, &change.translations).await
    }

    async fn export(pool: &PgPool, user: &CurrentUser) -> AppResult<ExportTable> {
        let mut products: Vec<Product> = sqlx::query_as(sqlx::AssertSqlSafe(format!(
            "{SELECT_PRODUCT} ORDER BY code"
        )))
        .fetch_all(pool)
        .await?;
        crate::resolve_products_for_company(
            pool,
            user.company_id,
            tradocraft_core::today(),
            &mut products,
        )
        .await?;
        let ids: Vec<Uuid> = products.iter().map(|p| p.id).collect();
        let mut conn = pool.acquire().await?;
        let translations = load_translations(&mut conn, &ids).await?;
        // One name and one description column per language that occurs, sorted by code. Only
        // ISO 639-1 codes, the ones an import accepts: a translation stored under another code
        // is left out of the export (and an import never touches it).
        let mut languages: Vec<String> = translations
            .values()
            .flat_map(|t| t.keys().cloned())
            .filter(|l| tradocraft_core::language::is_iso_639_1(l))
            .collect();
        languages.sort();
        languages.dedup();
        let mut header: Vec<String> = COLUMNS
            .iter()
            .filter(|c| !c.per_language)
            .map(|c| c.name.to_string())
            .collect();
        for language in &languages {
            header.push(format!("{NAME}_{language}"));
            header.push(format!("{DESCRIPTION}_{language}"));
        }
        let rows = products
            .iter()
            .map(|p| export_row(p, translations.get(&p.id), &languages))
            .collect();
        Ok(ExportTable { header, rows })
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
            (inline(BinaryFile) = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"),
            (inline(BinaryFile) = "application/vnd.oasis.opendocument.spreadsheet"))),
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
        (inline(BinaryFile) = "application/octet-stream"),
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

#[cfg(test)]
mod tests {
    use super::*;

    fn t(name: &str, description: &str) -> Translation {
        Translation {
            name: name.into(),
            description: description.into(),
        }
    }

    fn v(s: &str) -> Cell<String> {
        Cell::Value(s.into())
    }

    #[test]
    fn a_translation_is_only_set_by_a_name_or_a_description() {
        let stored = t("Pompe", "Ancienne");
        // Nothing given, or only empty cells: unchanged, never deleted.
        assert_eq!(
            translation_target(Cell::Absent, Cell::Absent, Some(&stored), "Pump"),
            None
        );
        assert_eq!(
            translation_target(Cell::Blank, Cell::Blank, Some(&stored), "Pump"),
            None
        );
        assert_eq!(
            translation_target(v("  "), Cell::Absent, None, "Pump"),
            None
        );
        // A name sets the name; an absent description keeps the stored one, a blank clears it.
        assert_eq!(
            translation_target(v(" Pompe 2 "), Cell::Absent, Some(&stored), "Pump"),
            Some(t("Pompe 2", "Ancienne"))
        );
        assert_eq!(
            translation_target(v("Pompe"), Cell::Blank, Some(&stored), "Pump"),
            Some(t("Pompe", ""))
        );
        assert_eq!(
            translation_target(v("Pompe"), Cell::Absent, None, "Pump"),
            Some(t("Pompe", ""))
        );
        // A description alone keeps the stored name, or takes the product's name.
        assert_eq!(
            translation_target(Cell::Blank, v("Nouvelle"), Some(&stored), "Pump"),
            Some(t("Pompe", "Nouvelle"))
        );
        assert_eq!(
            translation_target(Cell::Absent, v("Nouvelle "), None, "Pump"),
            Some(t("Pump", "Nouvelle"))
        );
    }

    #[test]
    fn translation_columns_are_families_of_any_iso_language() {
        let columns = |c: &[&str]| c.iter().map(|c| c.to_string()).collect::<Vec<_>>();
        assert_eq!(
            file_languages(&columns(&[
                "code",
                "name",
                "description",
                "name_it",
                "description_nl",
                "name_nl",
                "name_xx",
            ])),
            ["it", "nl"]
        );
        let known = import::column_names::<Products>();
        let known: Vec<&str> = known.iter().map(String::as_str).collect();
        assert!(import::is_known_field(&known, "name_pl"));
        assert!(import::is_known_field(&known, "description_ja"));
        assert!(!import::is_known_field(&known, "name_xx"));
        assert!(import::is_known_field(&known, "name"));
        assert!(!import::is_known_field(&known, "name_"));
    }
}
