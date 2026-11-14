//! Import and export of customers and products as XLSX and ODS (ADR 0064): typed cells, sheet
//! selection, real sheet row numbers, refused files, audit sources and permissions.

mod common;

use std::io::{Cursor, Write};

use axum::http::{Method, StatusCode};
use common::{raw, setup, Who};
use rust_xlsxwriter::{Formula, Workbook};
use serde_json::Value;
use sqlx::PgPool;
use tradocraft_core::import::{read_raw, write, CellValue, Format, Limits};
use zip::write::SimpleFileOptions;
use zip::ZipWriter;

const ADMIN: &str = "admin@example.com";
const VIEWER: &str = "viewer@example.com";
const SPREADSHEETS: [Format; 2] = [Format::Xlsx, Format::Ods];

fn t(s: &str) -> CellValue {
    CellValue::text(s)
}

fn n(s: &str) -> CellValue {
    CellValue::Number(s.parse().unwrap())
}

/// A one-sheet workbook of `format` built with the shared writer.
fn sheet(format: Format, header: &[&str], rows: Vec<Vec<CellValue>>) -> Vec<u8> {
    write(format, "Sheet1", header, rows).unwrap()
}

/// POSTs `body` to the import of `entity` and returns the status and the report.
async fn import_bytes(
    app: &axum::Router,
    user: &str,
    entity: &str,
    query: &str,
    body: Vec<u8>,
) -> (StatusCode, Value) {
    let (status, _, body) = raw(
        app,
        Who::Staff(user),
        Method::POST,
        &format!("/api/v1/{entity}/import?{query}"),
        Some(("application/octet-stream", body)),
    )
    .await;
    (status, serde_json::from_slice(&body).unwrap_or(Value::Null))
}

/// GETs an export in `format` (None: the default) and returns status, headers and body.
async fn export_as(
    app: &axum::Router,
    user: &str,
    entity: &str,
    format: Option<&str>,
) -> (StatusCode, axum::http::HeaderMap, Vec<u8>) {
    let query = format.map(|f| format!("?format={f}")).unwrap_or_default();
    raw(
        app,
        Who::Staff(user),
        Method::GET,
        &format!("/api/v1/{entity}/export{query}"),
        None,
    )
    .await
}

/// A fingerprint of the tables an import may change.
async fn snapshot(db: &PgPool, entity: &str) -> String {
    let sql = match entity {
        "customers" => {
            "SELECT coalesce(md5(string_agg(c::text || coalesce(t::text, ''), '|' ORDER BY c.code)), '') || count(*)
             FROM crm.customers c LEFT JOIN crm.customer_terms t ON t.customer_id = c.id"
        }
        _ => "SELECT coalesce(md5(string_agg(p::text, '|' ORDER BY p.code)), '') || count(*) FROM products.products p",
    };
    sqlx::query_scalar(sql).fetch_one(db).await.unwrap()
}

fn counts(v: &Value) -> (u64, u64, u64) {
    (
        v["created"].as_u64().unwrap(),
        v["updated"].as_u64().unwrap(),
        v["unchanged"].as_u64().unwrap(),
    )
}

fn errors(v: &Value) -> Vec<(u64, String, String)> {
    v["errors"]
        .as_array()
        .unwrap()
        .iter()
        .map(|e| {
            (
                e["row"].as_u64().unwrap(),
                e["column"].as_str().unwrap_or("").to_string(),
                e["message"].as_str().unwrap().to_string(),
            )
        })
        .collect()
}

async fn customer(app: &axum::Router, q: &str) -> Value {
    let (status, got) = common::call(
        app,
        ADMIN,
        Method::GET,
        &format!("/api/v1/customers?q={q}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    got["items"][0].clone()
}

async fn audited(db: &PgPool, entity: &str, source: &str) -> i64 {
    sqlx::query_scalar(
        "SELECT count(*) FROM audit.events WHERE entity = $1 AND data->>'source' = $2",
    )
    .bind(entity)
    .bind(source)
    .fetch_one(db)
    .await
    .unwrap()
}

/// An exported spreadsheet imports again as all unchanged and leaves the tables untouched.
#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn export_round_trip_is_unchanged(db: PgPool) {
    let app = setup(db.clone()).await;
    for format in SPREADSHEETS {
        for entity in ["customers", "products"] {
            let (status, headers, body) =
                export_as(&app, VIEWER, entity, Some(format.extension())).await;
            assert_eq!(status, StatusCode::OK);
            assert_eq!(headers["content-type"], format.content_type());
            assert!(headers["content-disposition"]
                .to_str()
                .unwrap()
                .contains(&format!("{entity}.{}", format.extension())));
            let before = snapshot(&db, entity).await;
            let (status, r) = import_bytes(&app, ADMIN, entity, "", body).await;
            assert_eq!(status, StatusCode::OK, "{entity} {format:?}: {r}");
            let (c, u, same) = counts(&r);
            assert_eq!((c, u), (0, 0), "{entity} {format:?}: {r}");
            assert!(same >= 3);
            assert_eq!(snapshot(&db, entity).await, before, "{entity} untouched");
        }
    }
}

/// The spreadsheet export has one sheet named after the entity and typed cells.
#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn export_cells_are_typed(db: PgPool) {
    let app = setup(db.clone()).await;
    sqlx::query(
        "UPDATE crm.customers SET postal_code = '00123', street = '=cmd' WHERE code = 'C0001'",
    )
    .execute(&db)
    .await
    .unwrap();
    for format in SPREADSHEETS {
        let (_, _, body) = export_as(&app, VIEWER, "customers", Some(format.extension())).await;
        let (detected, table) = read_raw(&body, None, &Limits::request()).unwrap();
        assert_eq!(detected, format);
        assert_eq!(table.sheets, ["customers"]);
        let col = |name: &str| table.header.iter().position(|h| h == name).unwrap();
        let row = table
            .rows
            .iter()
            .find(|r| r.cells[col("code")] == t("C0001"))
            .unwrap();
        assert_eq!(row.cells[col("postal_code")], t("00123"));
        assert_eq!(row.cells[col("street")], t("=cmd"));
        assert!(matches!(row.cells[col("active")], CellValue::Bool(_)));
        assert!(matches!(
            row.cells[col("discount_percent")],
            CellValue::Number(_)
        ));
        assert!(matches!(
            row.cells[col("payment_terms_days")],
            CellValue::Number(_)
        ));
        // And they come back unchanged.
        let (status, r) = import_bytes(&app, ADMIN, "customers", "", body).await;
        assert_eq!(status, StatusCode::OK, "{r}");
        assert_eq!((counts(&r).0, counts(&r).1), (0, 0), "{r}");
    }
    let c = customer(&app, "C0001").await;
    assert_eq!(c["postal_code"], "00123");
    assert_eq!(c["street"], "=cmd");
}

/// Create, update and dry run through a spreadsheet; the audit events carry the format.
#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn customers_create_update_and_dry_run(db: PgPool) {
    let app = setup(db.clone()).await;
    for (format, source) in [(Format::Xlsx, "xlsx_import"), (Format::Ods, "ods_import")] {
        let city = format!("Gent {source}");
        let file = sheet(
            format,
            &[
                "price_zone_code",
                "code",
                "name",
                "discount_percent",
                "city",
                "payment_terms_days",
            ],
            vec![
                vec![
                    t("Z2"),
                    t("C0001"),
                    t("Alpha Installaties NV"),
                    n("7.5"),
                    t(&city),
                    CellValue::int(45),
                ],
                vec![
                    t("Z3"),
                    t(&format!("NEW-{source}")),
                    t("New Customer"),
                    n("2"),
                    t("Brugge"),
                    CellValue::Empty,
                ],
                vec![
                    t("Z1"),
                    t("C0002"),
                    t("Bêta Industrie SA"),
                    n("0"),
                    t(&format!("Liège {source}")),
                    CellValue::int(30),
                ],
            ],
        );
        let before = snapshot(&db, "customers").await;
        let (status, r) =
            import_bytes(&app, ADMIN, "customers", "dry_run=true", file.clone()).await;
        assert_eq!(status, StatusCode::OK, "{r}");
        assert_eq!(counts(&r), (1, 2, 0), "{format:?}");
        assert_eq!(
            snapshot(&db, "customers").await,
            before,
            "dry run writes nothing"
        );
        assert_eq!(audited(&db, "customer", source).await, 0);

        let (status, r) = import_bytes(&app, ADMIN, "customers", "", file.clone()).await;
        assert_eq!(status, StatusCode::OK, "{r}");
        assert_eq!(counts(&r), (1, 2, 0));
        assert_eq!(audited(&db, "customer", source).await, 3);
        let created: Value = sqlx::query_scalar(
            "SELECT data FROM audit.events WHERE entity = 'customer' AND action = 'created' AND data->>'source' = $1",
        )
        .bind(source)
        .fetch_one(&db)
        .await
        .unwrap();
        assert_eq!(created["code"], format!("NEW-{source}"));
        assert!(created.get("import_job").is_none());

        let c = customer(&app, "C0001").await;
        assert_eq!(c["city"], city);
        assert_eq!(c["price_zone_code"], "Z2");
        assert_eq!(common::dec(&c["discount_percent"]).to_string(), "7.50");
        assert_eq!(c["payment_terms_days"], 45);
        assert_eq!(c["street"], "Havenlaan 10", "no column, kept");

        let (_, r) = import_bytes(&app, ADMIN, "customers", "", file).await;
        assert_eq!(counts(&r), (0, 0, 3), "{r}");
    }
    assert_eq!(audited(&db, "customer", "csv_import").await, 0);
}

/// Products through a spreadsheet, with their own audit source.
#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn products_create_update_and_dry_run(db: PgPool) {
    let app = setup(db.clone()).await;
    for (format, source) in [(Format::Xlsx, "xlsx_import"), (Format::Ods, "ods_import")] {
        let new_code = format!("NEW-{source}");
        let file = sheet(
            format,
            &[
                "vat_rate",
                "name",
                "code",
                "family_code",
                "reorder_min",
                "length_mm",
                "barcode",
                "active",
            ],
            vec![
                vec![
                    CellValue::int(6),
                    t(&format!("Pump five {source}")),
                    t("PUMP-05"),
                    t("PUMPS"),
                    n("2.5"),
                    CellValue::int(310),
                    CellValue::Empty,
                    CellValue::Bool(true),
                ],
                vec![
                    CellValue::int(21),
                    t("Brand new"),
                    t(&new_code),
                    t("MATERIALS"),
                    CellValue::Empty,
                    CellValue::Empty,
                    t(&format!("871{}", source.len())),
                    CellValue::Bool(false),
                ],
            ],
        );
        let before = snapshot(&db, "products").await;
        let (status, r) = import_bytes(&app, ADMIN, "products", "dry_run=true", file.clone()).await;
        assert_eq!(status, StatusCode::OK, "{r}");
        assert_eq!(counts(&r), (1, 1, 0));
        assert_eq!(snapshot(&db, "products").await, before);
        let (status, r) = import_bytes(&app, ADMIN, "products", "", file.clone()).await;
        assert_eq!(status, StatusCode::OK, "{r}");
        assert_eq!(counts(&r), (1, 1, 0));
        assert_eq!(audited(&db, "product", source).await, 2);
        let (_, p) =
            common::call(&app, ADMIN, Method::GET, "/api/v1/products?q=PUMP-05", None).await;
        let p = &p["items"][0];
        assert_eq!(common::dec(&p["reorder_min"]).to_string(), "2.5000");
        assert_eq!(p["length_mm"], 310);
        let (_, r) = import_bytes(&app, ADMIN, "products", "", file).await;
        assert_eq!(counts(&r), (0, 0, 2), "{r}");
    }
}

/// Typed cells: a numeric code, a numeric decimal, a boolean, and a text decimal with a comma.
#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn typed_cells_are_read_by_their_type(db: PgPool) {
    let app = setup(db.clone()).await;
    for (format, text_code) in [(Format::Xlsx, "T-X"), (Format::Ods, "T-O")] {
        let (num_code, num_text) = if format == Format::Xlsx {
            (1000, "1000")
        } else {
            (1001, "1001")
        };
        let file = sheet(
            format,
            &[
                "code",
                "name",
                "price_zone_code",
                "discount_percent",
                "active",
                "postal_code",
            ],
            vec![
                vec![
                    CellValue::int(num_code),
                    t("Numeric code"),
                    t("Z1"),
                    n("7.5"),
                    CellValue::Bool(false),
                    CellValue::int(9000),
                ],
                vec![
                    t(text_code),
                    t("Text decimal"),
                    t("Z1"),
                    t("7,5"),
                    CellValue::Number(1.into()),
                    t("0123"),
                ],
            ],
        );
        let (status, r) = import_bytes(&app, ADMIN, "customers", "", file).await;
        assert_eq!(status, StatusCode::OK, "{r}");
        assert_eq!(counts(&r), (2, 0, 0));
        let c = customer(&app, num_text).await;
        assert_eq!(c["code"], num_text);
        assert_eq!(common::dec(&c["discount_percent"]).to_string(), "7.50");
        assert_eq!(c["active"], false);
        assert_eq!(
            c["postal_code"], "9000",
            "a number in a text column is its text"
        );
        let c = customer(&app, text_code).await;
        assert_eq!(common::dec(&c["discount_percent"]).to_string(), "7.50");
        assert_eq!(c["active"], true, "the number 1 is true");
        assert_eq!(c["postal_code"], "0123");
    }
}

/// Row errors carry the sheet row numbers (also below leading empty rows) and nothing is written.
#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn row_errors_use_sheet_rows_and_nothing_is_written(db: PgPool) {
    let app = setup(db.clone()).await;
    let header = ["code", "name", "price_zone_code", "discount_percent"];
    for format in SPREADSHEETS {
        let file = sheet(
            format,
            &header,
            vec![
                vec![t("OK-1"), t("Fine"), t("Z1"), n("1")],
                vec![t("BAD-1"), CellValue::Empty, t("Z1"), n("1")],
                vec![t("BAD-2"), t("Two"), t("ZZ"), n("150")],
            ],
        );
        let before = snapshot(&db, "customers").await;
        let (status, r) = import_bytes(&app, ADMIN, "customers", "", file).await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{r}");
        assert_eq!(counts(&r), (0, 0, 0));
        let e = errors(&r);
        assert!(
            e.iter().any(|(row, c, _)| *row == 3 && c == "name"),
            "{e:?}"
        );
        assert!(
            e.iter()
                .any(|(row, c, _)| *row == 4 && c == "price_zone_code"),
            "{e:?}"
        );
        assert!(!e.iter().any(|(row, ..)| *row == 2), "{e:?}");
        assert_eq!(snapshot(&db, "customers").await, before);
    }

    // The header is the first row that is not empty: errors count from the real sheet row.
    let before = snapshot(&db, "customers").await;
    let mut book = Workbook::new();
    let ws = book.add_worksheet();
    for (c, h) in header.iter().enumerate() {
        ws.write_string(2, c as u16, *h).unwrap();
    }
    for (r, (code, name)) in [(3u32, ("OK-2", "Fine")), (4, ("BAD-3", ""))] {
        ws.write_string(r, 0, code).unwrap();
        if !name.is_empty() {
            ws.write_string(r, 1, name).unwrap();
        }
        ws.write_string(r, 2, "Z1").unwrap();
    }
    let (status, r) =
        import_bytes(&app, ADMIN, "customers", "", book.save_to_buffer().unwrap()).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{r}");
    let e = errors(&r);
    assert!(
        e.iter().any(|(row, c, _)| *row == 5 && c == "name"),
        "{e:?}"
    );
    assert_eq!(snapshot(&db, "customers").await, before);
}

/// `sheet` selects another sheet; an unknown sheet is a 422 on line 1 that lists the sheets.
#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn sheet_parameter_selects_a_sheet(db: PgPool) {
    let app = setup(db.clone()).await;
    let mut book = Workbook::new();
    let first = book.add_worksheet();
    first.set_name("Ignored").unwrap();
    first.write_string(0, 0, "code").unwrap();
    first.write_string(1, 0, "FIRST-SHEET").unwrap();
    let second = book.add_worksheet();
    second.set_name("Wanted").unwrap();
    for (c, h) in ["code", "name", "price_zone_code"].iter().enumerate() {
        second.write_string(0, c as u16, *h).unwrap();
    }
    second.write_string(1, 0, "SECOND-SHEET").unwrap();
    second.write_string(1, 1, "From the second").unwrap();
    second.write_string(1, 2, "Z1").unwrap();
    let file = book.save_to_buffer().unwrap();

    let before = snapshot(&db, "customers").await;
    let (status, r) = import_bytes(&app, ADMIN, "customers", "sheet=Nope", file.clone()).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{r}");
    let e = errors(&r);
    assert_eq!(e.len(), 1);
    assert_eq!(e[0].0, 1);
    assert!(
        e[0].2.contains("Ignored") && e[0].2.contains("Wanted"),
        "{e:?}"
    );
    assert_eq!(snapshot(&db, "customers").await, before);

    let (status, r) = import_bytes(&app, ADMIN, "customers", "sheet=Wanted", file.clone()).await;
    assert_eq!(status, StatusCode::OK, "{r}");
    assert_eq!(counts(&r), (1, 0, 0));
    assert_eq!(
        customer(&app, "SECOND-SHEET").await["name"],
        "From the second"
    );

    // Without `sheet` the first sheet is read (it has no name column, so a new code fails).
    let (status, r) = import_bytes(&app, ADMIN, "customers", "dry_run=true", file).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{r}");

    // The same for ODS, and a sheet name is ignored for CSV.
    let ods = sheet(Format::Ods, &["code"], vec![vec![t("X")]]);
    let (status, r) = import_bytes(&app, ADMIN, "products", "sheet=Nope", ods).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{r}");
    assert!(errors(&r)[0].2.contains("Sheet1"));
    let (status, _) = import_bytes(
        &app,
        ADMIN,
        "products",
        "sheet=Nope&dry_run=true",
        b"code\nP-1\n".to_vec(),
    )
    .await;
    assert_eq!(
        status,
        StatusCode::UNPROCESSABLE_ENTITY,
        "P-1 is new and has no name or vat_rate"
    );
}

/// A formula contributes its cached result; a cell that holds an error is a row error.
#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn formulas_use_the_cached_value_and_error_cells_are_row_errors(db: PgPool) {
    let app = setup(db.clone()).await;
    let build = |discount_result: &str| {
        let mut book = Workbook::new();
        let ws = book.add_worksheet();
        for (c, h) in ["code", "name", "price_zone_code", "discount_percent"]
            .iter()
            .enumerate()
        {
            ws.write_string(0, c as u16, *h).unwrap();
        }
        ws.write_string(1, 0, "FORMULA-1").unwrap();
        ws.write_formula(
            1,
            1,
            Formula::new("=\"Alpha \"&\"Beta\"").set_result("Alpha Beta"),
        )
        .unwrap();
        ws.write_string(1, 2, "Z1").unwrap();
        ws.write_formula(1, 3, Formula::new("=2+3").set_result("5"))
            .unwrap();
        ws.write_string(2, 0, "FORMULA-2").unwrap();
        ws.write_string(2, 1, "Has an error").unwrap();
        ws.write_string(2, 2, "Z1").unwrap();
        ws.write_formula(2, 3, Formula::new("=1/0").set_result(discount_result))
            .unwrap();
        book.save_to_buffer().unwrap()
    };
    let before = snapshot(&db, "customers").await;
    let (status, r) = import_bytes(&app, ADMIN, "customers", "", build("#DIV/0!")).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{r}");
    assert!(
        errors(&r)
            .iter()
            .any(|(row, _, m)| *row == 3 && m.contains("#DIV/0!")),
        "{r}"
    );
    assert_eq!(snapshot(&db, "customers").await, before);

    let (status, r) = import_bytes(&app, ADMIN, "customers", "dry_run=true", build("4")).await;
    assert_eq!(status, StatusCode::OK, "{r}");
    // Only the formula row differs from the first build; both rows are valid now.
    assert_eq!(counts(&r), (2, 0, 0));
    let book = {
        let mut book = Workbook::new();
        let ws = book.add_worksheet();
        for (c, h) in ["code", "name", "price_zone_code", "discount_percent"]
            .iter()
            .enumerate()
        {
            ws.write_string(0, c as u16, *h).unwrap();
        }
        ws.write_string(1, 0, "FORMULA-1").unwrap();
        ws.write_formula(
            1,
            1,
            Formula::new("=\"Alpha \"&\"Beta\"").set_result("Alpha Beta"),
        )
        .unwrap();
        ws.write_string(1, 2, "Z1").unwrap();
        ws.write_formula(1, 3, Formula::new("=2+3").set_result("5"))
            .unwrap();
        book.save_to_buffer().unwrap()
    };
    let (status, r) = import_bytes(&app, ADMIN, "customers", "", book).await;
    assert_eq!(status, StatusCode::OK, "{r}");
    let c = customer(&app, "FORMULA-1").await;
    assert_eq!(c["name"], "Alpha Beta");
    assert_eq!(common::dec(&c["discount_percent"]).to_string(), "5.00");
}

fn zip_of(entries: &[(&str, &[u8])]) -> Vec<u8> {
    let mut zip = ZipWriter::new(Cursor::new(Vec::new()));
    for (name, body) in entries {
        zip.start_file(*name, SimpleFileOptions::default()).unwrap();
        zip.write_all(body).unwrap();
    }
    zip.finish().unwrap().into_inner()
}

/// A zip that declares too much unpacked data, a zip that is no spreadsheet and the legacy `.xls`
/// are refused with one 422 error and nothing is written.
#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn refused_files_write_nothing(db: PgPool) {
    let app = setup(db.clone()).await;
    let zeros = vec![0u8; 70 * 1024 * 1024];
    let bomb = zip_of(&[("xl/workbook.xml", b"<workbook/>"), ("xl/big.bin", &zeros)]);
    assert!(bomb.len() < 1024 * 1024, "it compresses to almost nothing");
    let not_a_sheet = zip_of(&[("hello.txt", b"hello")]);
    let mut xls = vec![0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1];
    xls.extend([0u8; 64]);
    for (what, file) in [("bomb", bomb), ("zip", not_a_sheet), ("xls", xls)] {
        for entity in ["customers", "products"] {
            let before = snapshot(&db, entity).await;
            let (status, r) = import_bytes(&app, ADMIN, entity, "", file.clone()).await;
            assert_eq!(
                status,
                StatusCode::UNPROCESSABLE_ENTITY,
                "{what} {entity}: {r}"
            );
            let e = errors(&r);
            assert_eq!(e.len(), 1, "{what}: {e:?}");
            assert_eq!(e[0].0, 1);
            assert_eq!(counts(&r), (0, 0, 0));
            assert_eq!(snapshot(&db, entity).await, before);
        }
    }
}

/// `format=` sets the content type and the file name; an unknown format is refused; CSV stays the
/// default.
#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn export_format_parameter(db: PgPool) {
    let app = setup(db.clone()).await;
    for entity in ["customers", "products"] {
        for (format, ct, ext) in [
            (None, "text/csv; charset=utf-8", "csv"),
            (Some("csv"), "text/csv; charset=utf-8", "csv"),
            (Some("xlsx"), Format::Xlsx.content_type(), "xlsx"),
            (Some("ods"), Format::Ods.content_type(), "ods"),
        ] {
            let (status, headers, body) = export_as(&app, VIEWER, entity, format).await;
            assert_eq!(status, StatusCode::OK, "{entity} {format:?}");
            assert_eq!(headers["content-type"], ct);
            assert_eq!(
                headers["content-disposition"],
                format!("attachment; filename=\"{entity}.{ext}\"")
            );
            if ext == "csv" {
                assert!(String::from_utf8(body).unwrap().starts_with("code,name,"));
            }
        }
        for bad in ["xls", "pdf", "XLSX", ""] {
            let (status, ..) = export_as(&app, VIEWER, entity, Some(bad)).await;
            assert!(
                status.is_client_error(),
                "{entity} format={bad:?}: {status}"
            );
        }
    }
}

/// Permissions are those of the CSV endpoints, whatever the format.
#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn permissions_are_unchanged(db: PgPool) {
    let app = setup(db.clone()).await;
    for entity in ["customers", "products"] {
        for format in SPREADSHEETS {
            let file = sheet(format, &["code"], vec![vec![t("X")]]);
            let (status, _) = import_bytes(&app, VIEWER, entity, "dry_run=true", file).await;
            assert_eq!(status, StatusCode::FORBIDDEN, "{entity}");
            let (status, ..) = export_as(
                &app,
                "technician@example.com",
                entity,
                Some(format.extension()),
            )
            .await;
            assert_eq!(status, StatusCode::FORBIDDEN, "{entity}");
        }
    }
}

/// The type-erased handle runs an import outside HTTP: as a given user, with a job id that every
/// audit event carries, progress reported, and the typed rows of an export.
#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_erased_handle_runs_a_job(db: PgPool) {
    use std::sync::Mutex;
    use tradocraft_core::import::{read_table, Phase, Progress, RunOptions};

    struct Recorder(Mutex<Vec<(Phase, usize)>>);
    impl Progress for Recorder {
        fn report(&self, phase: Phase, processed: usize) {
            self.0.lock().unwrap().push((phase, processed));
        }
    }

    let app = setup(db.clone()).await; // seeds
    let user = tradocraft_core::CurrentUser {
        user_id: "00000000-0000-7000-8000-000000000101".parse().unwrap(),
        email: ADMIN.into(),
        display_name: "Admin User".into(),
        company_id: "00000000-0000-7000-8000-000000000001".parse().unwrap(),
        roles: vec!["admin".into()],
        disabled_modules: vec![],
    };
    for entity in [
        tradocraft_crm::customers_import(),
        tradocraft_products::products_import(),
    ] {
        let description = entity.describe();
        assert!(description
            .columns
            .iter()
            .any(|c| c.name == description.key_column));
        assert_eq!(entity.header().len(), description.columns.len());
        let rows = entity.export(&db, &user).await.unwrap();
        assert!(rows.len() >= 3);
        assert!(rows.iter().all(|r| r.len() == entity.header().len()));
        let file = write(Format::Ods, &description.file_stem, &entity.header(), rows).unwrap();
        let (format, table) = read_table(
            &file,
            None,
            &Limits::job(),
            &entity.header(),
            &[description.key_column.as_str()],
            None,
        )
        .unwrap();
        let progress = Recorder(Mutex::new(Vec::new()));
        let job = uuid::Uuid::now_v7();
        let options = RunOptions::new(format).import_job(job).progress(&progress);
        let report = entity.run(&db, &user, &table, &options).await.unwrap();
        assert!(report.errors.is_empty());
        assert_eq!((report.created, report.updated), (0, 0));
        assert_eq!(report.unchanged, table.rows.len());
        let seen = progress.0.lock().unwrap().clone();
        assert_eq!(seen.last(), Some(&(Phase::Validating, table.rows.len())));
    }

    // A change through the handle is audited with the job id and the source of the format.
    let entity = tradocraft_crm::customers_import();
    let file = write(
        Format::Xlsx,
        "customers",
        &["code", "city"],
        vec![vec![t("C0001"), t("Job City")]],
    )
    .unwrap();
    let (format, table) = read_table(
        &file,
        None,
        &Limits::job(),
        &entity.header(),
        &["code"],
        None,
    )
    .unwrap();
    let job = uuid::Uuid::now_v7();
    let progress = Recorder(Mutex::new(Vec::new()));
    let options = RunOptions::new(format).import_job(job).progress(&progress);
    let report = entity.run(&db, &user, &table, &options).await.unwrap();
    assert_eq!(
        (report.created, report.updated, report.unchanged),
        (0, 1, 0)
    );
    let data: Value = sqlx::query_scalar(
        "SELECT data FROM audit.events WHERE entity = 'customer' AND data->>'import_job' = $1",
    )
    .bind(job.to_string())
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(
        data,
        serde_json::json!({"source": "xlsx_import", "import_job": job.to_string()})
    );
    let phases: Vec<Phase> = progress.0.lock().unwrap().iter().map(|(p, _)| *p).collect();
    assert_eq!(phases, [Phase::Validating, Phase::Writing]);

    // A dry run through the handle writes nothing.
    let options = RunOptions::new(format).dry_run(true);
    let file = write(
        Format::Xlsx,
        "customers",
        &["code", "city"],
        vec![vec![t("C0001"), t("Other")]],
    )
    .unwrap();
    let (_, table) = read_table(
        &file,
        None,
        &Limits::job(),
        &entity.header(),
        &["code"],
        None,
    )
    .unwrap();
    let report = entity.run(&db, &user, &table, &options).await.unwrap();
    assert_eq!(report.updated, 1);
    assert_eq!(customer(&app, "C0001").await["city"], "Job City");
}
