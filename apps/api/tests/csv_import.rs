//! CSV export and all-or-nothing import of customers and products.

mod common;

use axum::http::{Method, StatusCode};
use common::{raw, setup, Who};
use serde_json::Value;
use sqlx::PgPool;

const ADMIN: &str = "admin@example.com";
const VIEWER: &str = "viewer@example.com";

/// GETs an export as `user`; for a 200 also checks the download headers and the missing BOM.
async fn export(app: &axum::Router, user: &str, entity: &str) -> (StatusCode, String) {
    let (status, headers, body) = raw(
        app,
        Who::Staff(user),
        Method::GET,
        &format!("/api/v1/{entity}/export"),
        None,
    )
    .await;
    if status == StatusCode::OK {
        assert!(headers["content-type"]
            .to_str()
            .unwrap()
            .starts_with("text/csv"));
        assert!(headers["content-disposition"]
            .to_str()
            .unwrap()
            .contains(&format!("{entity}.csv")));
        assert!(!body.starts_with(&[0xEF, 0xBB, 0xBF]), "no BOM");
    }
    (status, String::from_utf8_lossy(&body).into_owned())
}

/// POSTs `csv` to the import of `entity` (optionally as dry run) and returns status and report.
async fn import(
    app: &axum::Router,
    user: &str,
    entity: &str,
    dry_run: bool,
    csv: &str,
) -> (StatusCode, Value) {
    let (status, _, body) = raw(
        app,
        Who::Staff(user),
        Method::POST,
        &format!("/api/v1/{entity}/import?dry_run={dry_run}"),
        Some(("text/csv", csv.as_bytes().to_vec())),
    )
    .await;
    (status, serde_json::from_slice(&body).unwrap_or(Value::Null))
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

/// The `(created, updated, unchanged)` counts of a report.
fn counts(v: &Value) -> (u64, u64, u64) {
    (
        v["created"].as_u64().unwrap(),
        v["updated"].as_u64().unwrap(),
        v["unchanged"].as_u64().unwrap(),
    )
}

/// The `(row, column, message)` triples of a report (column empty for whole-row problems).
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

/// An exported file imports again as all unchanged and leaves the tables untouched.
#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn export_round_trip_is_unchanged(db: PgPool) {
    let app = setup(db.clone()).await;
    for (entity, header) in [
        ("customers", "code,name,vat_number,email,phone,street,postal_code,city,country_code,language,active,price_zone_code,discount_percent,payment_terms_days,vat_regime"),
        ("products", "code,name,description,unit,product_type,vat_rate,tracking,family_code,pricing_type,active,reorder_min,reorder_max,lead_time_days,barcode,packaging_category_code,length_mm,width_mm,height_mm,weight_g,default_production_remark,vat_category,vat_rate_override"),
    ] {
        let (status, csv) = export(&app, VIEWER, entity).await;
        assert_eq!(status, StatusCode::OK);
        assert_eq!(csv.lines().next().unwrap(), header);
        assert!(csv.contains("\r\n"));
        let before = snapshot(&db, entity).await;
        let (status, r) = import(&app, ADMIN, entity, false, &csv).await;
        assert_eq!(status, StatusCode::OK, "{r}");
        let (c, u, same) = counts(&r);
        assert_eq!((c, u), (0, 0), "{entity}: {r}");
        assert!(same >= 3);
        assert_eq!(snapshot(&db, entity).await, before, "{entity} untouched");
    }
}

/// Customer import: any column order, `;`, decimal comma, BOM; dry run writes nothing; kept fields.
#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn customers_create_update_and_dry_run(db: PgPool) {
    let app = setup(db.clone()).await;
    // Columns in another order, `;` delimiter, decimal comma, BOM, fewer columns than the export.
    let csv = "\u{feff}price_zone_code;code;name;discount_percent;city;payment_terms_days\r\n\
               Z2;C0001;Alpha Installaties NV;7,5;Gent;45\r\n\
               Z3;NEW1;\"New; Customer\";2;Brugge;\r\n\
               Z1;C0002;Bêta Industrie SA;0;Liège;30\r\n";
    let before = snapshot(&db, "customers").await;
    let (status, r) = import(&app, ADMIN, "customers", true, csv).await;
    assert_eq!(status, StatusCode::OK, "{r}");
    assert_eq!(counts(&r), (1, 2, 0));
    assert_eq!(
        snapshot(&db, "customers").await,
        before,
        "dry run writes nothing"
    );

    let (status, r) = import(&app, ADMIN, "customers", false, csv).await;
    assert_eq!(status, StatusCode::OK, "{r}");
    assert_eq!(counts(&r), (1, 2, 0));

    // Fields without a column are kept; terms and fields changed as given.
    let (status, got) =
        common::call(&app, ADMIN, Method::GET, "/api/v1/customers?q=C0001", None).await;
    assert_eq!(status, StatusCode::OK);
    let c = &got["items"][0];
    assert_eq!(c["city"], "Gent");
    assert_eq!(c["street"], "Havenlaan 10");
    assert_eq!(c["email"], "info@alpha.example");
    assert_eq!(c["price_zone_code"], "Z2");
    assert_eq!(common::dec(&c["discount_percent"]).to_string(), "7.50");
    assert_eq!(c["payment_terms_days"], 45);
    assert_eq!(c["id"], "00000000-0000-7000-8000-000000000401", "id kept");
    let (_, got) = common::call(&app, ADMIN, Method::GET, "/api/v1/customers?q=NEW1", None).await;
    let c = &got["items"][0];
    assert_eq!(c["name"], "New; Customer");
    assert_eq!(c["country_code"], "BE");
    assert_eq!(c["payment_terms_days"], 30, "blank = default on create");

    // Both writes are in the audit trail.
    let audited: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM audit.events WHERE entity = 'customer' AND data->>'source' = 'csv_import'",
    )
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(audited, 3);

    // Same file again: nothing left to do.
    let (_, r) = import(&app, ADMIN, "customers", false, csv).await;
    assert_eq!(counts(&r), (0, 0, 3), "{r}");
}

/// Row errors of a customer file are all reported (dry run too) and nothing is written.
#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn customer_row_errors_are_reported_together_and_nothing_is_written(db: PgPool) {
    let app = setup(db.clone()).await;
    let csv = "code,name,country_code,language,discount_percent,price_zone_code,active\n\
               C0001,Renamed,BE,nl,5,Z1,true\n\
               NEW1,,BE,nl,0,Z1,true\n\
               NEW2,Two,BEL,xx,150,Z1,maybe\n\
               NEW3,Three,BE,nl,abc,ZZ,true\n\
               NEW4,Four,BE,nl,0,,true\n\
               NEW1,Dup,BE,nl,0,Z1,true\n\
               ,NoCode,BE,nl,0,Z1,true\n";
    let before = snapshot(&db, "customers").await;
    let (status, r) = import(&app, ADMIN, "customers", false, csv).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{r}");
    assert_eq!(counts(&r), (0, 0, 0));
    let e = errors(&r);
    let has = |row: u64, col: &str| e.iter().any(|(r, c, _)| *r == row && c == col);
    assert!(has(3, "name"), "{e:?}");
    assert!(has(4, "country_code"), "{e:?}");
    assert!(has(4, "language"), "{e:?}");
    assert!(has(4, "discount_percent"), "{e:?}");
    assert!(has(4, "active"), "{e:?}");
    assert!(has(5, "discount_percent"), "{e:?}");
    assert!(has(5, "price_zone_code"), "{e:?}");
    assert!(has(6, "price_zone_code"), "{e:?}");
    assert!(has(7, "code"), "{e:?}");
    assert!(has(8, "code"), "{e:?}");
    assert!(
        !e.iter().any(|(r, ..)| *r == 2),
        "the valid row has no error"
    );
    assert_eq!(snapshot(&db, "customers").await, before);

    // The same errors in a dry run.
    let (status, r2) = import(&app, ADMIN, "customers", true, csv).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(errors(&r2), e);
}

/// Header problems are a 422 on line 1 naming the column.
#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn header_problems_are_422(db: PgPool) {
    let app = setup(db.clone()).await;
    for (entity, csv, column, text) in [
        ("customers", "code,nope\nC1,x\n", "nope", "unknown column"),
        (
            "customers",
            "name\nx\n",
            "code",
            "required column is missing",
        ),
        ("customers", "code,code\nx,y\n", "code", "twice"),
        (
            "products",
            "code,standard_cost\nx,1\n",
            "standard_cost",
            "unknown column",
        ),
        ("products", "", "", "empty"),
    ] {
        let (status, r) = import(&app, ADMIN, entity, false, csv).await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{csv}");
        let e = errors(&r);
        assert!(
            e.iter().any(|(_, c, m)| c == column && m.contains(text)),
            "{csv}: {e:?}"
        );
    }
}

/// Importing needs the write permission.
#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn import_needs_the_write_permission(db: PgPool) {
    let app = setup(db.clone()).await;
    for entity in ["customers", "products"] {
        let (status, _) = import(&app, VIEWER, entity, true, "code\nX\n").await;
        assert_eq!(status, StatusCode::FORBIDDEN, "{entity}");
    }
}

/// Exports need the read permission: a user without it (the technician) and an unknown user are
/// refused.
#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn export_needs_the_read_permission(db: PgPool) {
    let app = setup(db.clone()).await;
    for entity in ["customers", "products"] {
        let (status, _) = export(&app, "technician@example.com", entity).await;
        assert_eq!(status, StatusCode::FORBIDDEN, "{entity}");
    }
    let (status, _) = export(&app, "nobody@example.com", "customers").await;
    assert_ne!(status, StatusCode::OK);
}

/// Product import: create/update/dry run; the standard cost is never touched.
#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn products_create_update_dry_run_and_cost_is_kept(db: PgPool) {
    let app = setup(db.clone()).await;
    sqlx::query("UPDATE products.products SET standard_cost = 12.3456 WHERE code = 'PUMP-05'")
        .execute(&db)
        .await
        .unwrap();
    let csv = "vat_rate;name;code;family_code;reorder_min;length_mm;barcode\r\n\
               6;Pump five;PUMP-05;PUMPS;2,5;310;\r\n\
               21;Brand new;NEW-1;MATERIALS;;;  8710000000001 \r\n";
    let before = snapshot(&db, "products").await;
    let (status, r) = import(&app, ADMIN, "products", true, csv).await;
    assert_eq!(status, StatusCode::OK, "{r}");
    assert_eq!(counts(&r), (1, 1, 0));
    assert_eq!(snapshot(&db, "products").await, before);

    let (status, r) = import(&app, ADMIN, "products", false, csv).await;
    assert_eq!(status, StatusCode::OK, "{r}");
    let (_, p) = common::call(&app, ADMIN, Method::GET, "/api/v1/products?q=PUMP-05", None).await;
    let p = &p["items"][0];
    assert_eq!(p["name"], "Pump five");
    assert_eq!(common::dec(&p["vat_rate"]).to_string(), "6.00");
    assert_eq!(common::dec(&p["reorder_min"]).to_string(), "2.5000");
    assert_eq!(p["length_mm"], 310);
    assert_eq!(p["width_mm"], 200, "no column, kept");
    assert_eq!(p["barcode"], Value::Null, "blank clears");
    assert_eq!(p["packaging_category_code"], "PARCEL", "no column, kept");
    let cost: String = sqlx::query_scalar(
        "SELECT standard_cost::text FROM products.products WHERE code = 'PUMP-05'",
    )
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(cost, "12.3456", "cost is never imported");
    let (_, n) = common::call(&app, ADMIN, Method::GET, "/api/v1/products?q=NEW-1", None).await;
    assert_eq!(n["items"][0]["barcode"], "8710000000001");
    assert_eq!(n["items"][0]["product_type"], "purchased");
    assert_eq!(n["items"][0]["unit"], "pcs");

    let (_, r) = import(&app, ADMIN, "products", false, csv).await;
    assert_eq!(counts(&r), (0, 0, 2), "{r}");
}

/// Row errors of a product file are all reported and nothing is written.
#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn product_row_errors_are_reported_together_and_nothing_is_written(db: PgPool) {
    let app = setup(db.clone()).await;
    sqlx::query("UPDATE products.products SET barcode = '123' WHERE code = 'PUMP-05'")
        .execute(&db)
        .await
        .unwrap();
    let csv = "code,name,product_type,vat_rate,tracking,pricing_type,family_code,packaging_category_code,length_mm,barcode,reorder_min,reorder_max\n\
               OK-1,Fine,purchased,21,none,list,,,,,,\n\
               E-1,A,gadget,21,none,list,,,,,,\n\
               E-2,B,service,21,serial,list,,,,,,\n\
               E-3,C,purchased,21,none,wrong,NOPE,NOPE,,,,\n\
               E-3a,C,purchased,-1,none,list,,,,,,\n\
               E-3b,C,purchased,21,none,list,,,0,,,\n\
               E-3c,C,purchased,21,none,list,,,,,5,1\n\
               E-4,D,purchased,,none,list,,,,,,\n\
               E-5,E,purchased,21.123,none,list,,,,123,,\n\
               E-6,F,purchased,21,none,list,,,,,,\n\
               E-6,G,purchased,21,none,list,,,,,,\n";
    let before = snapshot(&db, "products").await;
    let (status, r) = import(&app, ADMIN, "products", false, csv).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{r}");
    let e = errors(&r);
    let has = |row: u64, col: &str| e.iter().any(|(r, c, _)| *r == row && c == col);
    assert!(has(3, "product_type"), "{e:?}");
    assert!(
        e.iter()
            .any(|(r, _, m)| *r == 4 && m.contains("services cannot be tracked")),
        "{e:?}"
    );
    for col in ["pricing_type", "family_code", "packaging_category_code"] {
        assert!(has(5, col), "{col}: {e:?}");
    }
    assert!(has(6, "vat_rate"), "{e:?}");
    assert!(has(7, "length_mm"), "{e:?}");
    assert!(
        e.iter()
            .any(|(r, _, m)| *r == 8 && m.contains("reorder_max")),
        "{e:?}"
    );
    assert!(has(9, "vat_rate"), "{e:?}");
    assert!(has(10, "vat_rate"), "{e:?}");
    assert!(has(10, "barcode"), "{e:?}");
    assert!(has(12, "code"), "{e:?}");
    assert!(!e.iter().any(|(r, ..)| *r == 2 || *r == 11));
    assert_eq!(snapshot(&db, "products").await, before);
}

/// A product with stock moves cannot become a service through an import either.
#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn product_with_stock_moves_cannot_become_a_service(db: PgPool) {
    let app = setup(db.clone()).await;
    sqlx::query(
        "INSERT INTO inventory.locations (id, company_id, code, kind)
         VALUES (gen_random_uuid(), '00000000-0000-7000-8000-000000000001', 'TST', 'supplier'),
                (gen_random_uuid(), '00000000-0000-7000-8000-000000000001', 'TST2', 'adjustment')",
    )
    .execute(&db)
    .await
    .unwrap();
    let moved = sqlx::query(
        "INSERT INTO inventory.stock_moves (id, company_id, product_id, quantity, from_location_id,
                                            to_location_id, kind, reason, created_by)
         SELECT gen_random_uuid(), a.company_id, p.id, 1, a.id, b.id, 'adjustment', 'test',
                '00000000-0000-7000-8000-000000000101'
         FROM products.products p, inventory.locations a, inventory.locations b
         WHERE p.code = 'PUMP-05' AND a.kind = 'supplier' AND b.kind = 'adjustment' AND a.company_id = b.company_id",
    )
    .execute(&db)
    .await
    .unwrap();
    assert_eq!(moved.rows_affected(), 1);
    let (status, r) = import(
        &app,
        ADMIN,
        "products",
        true,
        "code,product_type,tracking\nPUMP-05,service,none\n",
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{r}");
    assert!(
        errors(&r).iter().any(|e| e.2.contains("stock moves")),
        "{r}"
    );
}

/// The row limit is a 422, the body limit a 413.
#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn too_many_rows_and_oversized_bodies_are_rejected(db: PgPool) {
    let app = setup(db.clone()).await;
    let mut csv = String::from("code\n");
    for i in 0..20_001 {
        csv.push_str(&format!("X{i}\n"));
    }
    let (status, r) = import(&app, ADMIN, "products", true, &csv).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    assert!(errors(&r)[0].2.contains("too many rows"));
    let big = format!("code\n{}", "x".repeat(5 * 1024 * 1024 + 10));
    let (status, _) = import(&app, ADMIN, "customers", true, &big).await;
    assert_eq!(status, StatusCode::PAYLOAD_TOO_LARGE);
}

/// Surrounding spaces and literal apostrophes survive an export and an unchanged re-import, and a
/// protected formula is unprotected again.
#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn odd_text_values_round_trip_unchanged(db: PgPool) {
    let app = setup(db.clone()).await;
    sqlx::query(
        "UPDATE crm.customers SET name = '''=Literal', street = '  Havenlaan 10  ', city = ' ',
                phone = '+32 3 000 00 01' WHERE code = 'C0001'",
    )
    .execute(&db)
    .await
    .unwrap();
    sqlx::query(
        "UPDATE products.products SET description = '  padded  ', name = '''''-two' WHERE code = 'PUMP-05'",
    )
    .execute(&db)
    .await
    .unwrap();
    for entity in ["customers", "products"] {
        let (_, csv) = export(&app, ADMIN, entity).await;
        let before = snapshot(&db, entity).await;
        let (status, r) = import(&app, ADMIN, entity, false, &csv).await;
        assert_eq!(status, StatusCode::OK, "{entity}: {r}");
        let (c, u, _) = counts(&r);
        assert_eq!((c, u), (0, 0), "{entity}: {r}");
        assert_eq!(snapshot(&db, entity).await, before, "{entity} untouched");
        if entity == "customers" {
            assert!(csv.contains("''=Literal"), "{csv}");
            assert!(csv.contains("  Havenlaan 10  "), "{csv}");
        } else {
            assert!(csv.contains("'''-two"), "{csv}");
        }
    }
    // A single protecting apostrophe is a formula that was protected: it is removed.
    let (status, r) = import(
        &app,
        ADMIN,
        "customers",
        false,
        "code,name,street\nC0001,'=Formula, ' padded\n",
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{r}");
    let (_, got) = common::call(&app, ADMIN, Method::GET, "/api/v1/customers?q=C0001", None).await;
    assert_eq!(got["items"][0]["name"], "=Formula");
    assert_eq!(got["items"][0]["street"], " ' padded");
}

/// Rows with fewer or more cells than the header are row errors; the other rows are still checked
/// and their errors reported in the same response; nothing is written.
#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn rows_of_the_wrong_width_are_reported_with_the_other_errors(db: PgPool) {
    let app = setup(db.clone()).await;
    for (entity, csv, semantic) in [
        (
            "customers",
            "code,name,country_code,price_zone_code\n\
             NEW1,One,BEL,Z1\n\
             NEW2,Short\n\
             NEW3,Three,BE,Z1,extra\n\
             NEW4,,BE,Z1\n\
             NEW5,Five,BE,Z1,\n",
            [(2, "country_code"), (5, "name")],
        ),
        (
            "products",
            "code,name,vat_rate,tracking\n\
             N1,One,21,wrong\n\
             N2,Short\n\
             N3,Three,21,none,extra\n\
             N4,Four,-1,none\n\
             N5,Five,21,none,\n",
            [(2, "tracking"), (5, "vat_rate")],
        ),
    ] {
        let before = snapshot(&db, entity).await;
        for dry_run in [true, false] {
            let (status, r) = import(&app, ADMIN, entity, dry_run, csv).await;
            assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{entity}: {r}");
            assert_eq!(counts(&r), (0, 0, 0));
            let e = errors(&r);
            let rows: Vec<u64> = e.iter().map(|e| e.0).collect();
            assert_eq!(rows, [2, 3, 4, 5], "{entity}, in file order: {e:?}");
            assert!(e[1].2.contains("2 values"), "{e:?}");
            assert!(e[2].2.contains("5 values"), "{e:?}");
            for (row, col) in semantic {
                assert!(e.iter().any(|(r, c, _)| *r == row && c == col), "{e:?}");
            }
        }
        assert_eq!(snapshot(&db, entity).await, before);
    }
}

/// Quotes inside unquoted values and text after a closing quote are format errors.
#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn malformed_quoting_is_rejected_before_planning(db: PgPool) {
    let app = setup(db.clone()).await;
    for csv in [
        "code,name\nC0001,ab\"cd\n",
        "code,name\nC0001,\"ab\"cd\n",
        "code,name\nC0001,\"ab\" \n",
        "code,name\nC0001, \"ab\"\n",
    ] {
        for entity in ["customers", "products"] {
            let before = snapshot(&db, entity).await;
            let (status, r) = import(&app, ADMIN, entity, false, csv).await;
            assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{csv:?}");
            let e = errors(&r);
            assert_eq!(e.len(), 1, "{csv:?}: {e:?}");
            assert_eq!(e[0].0, 2);
            assert_eq!(snapshot(&db, entity).await, before);
        }
    }
    // Quoted values with delimiters, doubled quotes and line breaks still work.
    let (status, r) = import(
        &app,
        ADMIN,
        "customers",
        true,
        "code,name\nC0001,\"A \"\"b\"\", c\nd\"\n",
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{r}");
    assert_eq!(counts(&r), (0, 1, 0));
}

/// A discount is normalised before the decimals check, needs a price zone, and blank terms of a
/// customer without a zone stay as they are.
#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn customer_terms_discount_normalisation_and_price_zone(db: PgPool) {
    let app = setup(db.clone()).await;
    let (status, r) = import(
        &app,
        ADMIN,
        "customers",
        false,
        "code,discount_percent\nC0001,\"7,500\"\n",
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{r}");
    let (_, got) = common::call(&app, ADMIN, Method::GET, "/api/v1/customers?q=C0001", None).await;
    assert_eq!(
        common::dec(&got["items"][0]["discount_percent"]).to_string(),
        "7.50"
    );
    let (status, r) = import(
        &app,
        ADMIN,
        "customers",
        true,
        "code,discount_percent\nC0001,7.555\n",
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{r}");
    assert!(errors(&r)[0].2.contains("2 decimals"));

    sqlx::query(
        "INSERT INTO crm.customers (id, code, name, street, postal_code, city, country_code, language)
         VALUES (gen_random_uuid(), 'NOZONE', 'No Zone', '', '', '', 'BE', 'nl')",
    )
    .execute(&db)
    .await
    .unwrap();
    let (status, r) = import(
        &app,
        ADMIN,
        "customers",
        false,
        "code,discount_percent,payment_terms_days\nNOZONE,,\n",
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{r}");
    assert_eq!(counts(&r), (0, 0, 1), "blank terms round-trip");
    for csv in [
        "code,discount_percent\nNOZONE,5\n",
        "code,payment_terms_days\nNOZONE,45\n",
    ] {
        let (status, r) = import(&app, ADMIN, "customers", false, csv).await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{csv}: {r}");
        assert!(errors(&r)[0].2.contains("price zone"), "{r}");
    }
    let (status, r) = import(
        &app,
        ADMIN,
        "customers",
        false,
        "code,price_zone_code,discount_percent\nNOZONE,Z1,5\n",
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{r}");
    assert_eq!(counts(&r), (0, 1, 0));
}

/// A blank address or description cell keeps the stored value, like the other required fields.
#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn blank_address_and_description_cells_keep_the_current_value(db: PgPool) {
    let app = setup(db.clone()).await;
    let (status, r) = import(
        &app,
        ADMIN,
        "customers",
        false,
        "code,street,postal_code,city\nC0001,,,\n",
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{r}");
    assert_eq!(counts(&r), (0, 0, 1), "{r}");
    sqlx::query("UPDATE products.products SET description = 'Kept' WHERE code = 'PUMP-05'")
        .execute(&db)
        .await
        .unwrap();
    let (status, r) = import(
        &app,
        ADMIN,
        "products",
        false,
        "code,description\nPUMP-05,\n",
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{r}");
    assert_eq!(counts(&r), (0, 0, 1), "{r}");
}

/// A change to only the default production remark is planned as an update and applied (trimmed).
#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn default_production_remark_only_change_is_imported(db: PgPool) {
    let app = setup(db.clone()).await;
    let (status, r) = import(
        &app,
        ADMIN,
        "products",
        false,
        "code,default_production_remark\nPUMP-05,  Mount left  \n",
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{r}");
    assert_eq!(counts(&r), (0, 1, 0), "{r}");
    let remark: String = sqlx::query_scalar(
        "SELECT default_production_remark FROM products.products WHERE code = 'PUMP-05'",
    )
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(remark, "Mount left");
    let (_, r) = import(
        &app,
        ADMIN,
        "products",
        false,
        "code,default_production_remark\nPUMP-05,Mount left\n",
    )
    .await;
    assert_eq!(counts(&r), (0, 0, 1), "{r}");
}

/// A VAT rate that would be rounded while parsing is reported, never stored.
#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn vat_rate_with_excess_precision_is_rejected(db: PgPool) {
    let app = setup(db.clone()).await;
    let before = snapshot(&db, "products").await;
    let (status, r) = import(
        &app,
        ADMIN,
        "products",
        false,
        "code,name,vat_rate\nV-1,Rounded,21.0000000000000000000000000000001\nV-2,Exact,21.50\n",
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{r}");
    let e = errors(&r);
    assert_eq!(e.len(), 1, "{e:?}");
    assert!((e[0].0, e[0].1.as_str()) == (2, "vat_rate"), "{e:?}");
    assert!(e[0].2.contains("more digits"), "{e:?}");
    assert_eq!(snapshot(&db, "products").await, before);
}

/// All independent problems of a row are reported, also when the name is empty, and the database
/// checks run next to the format checks.
#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn independent_row_errors_are_all_reported(db: PgPool) {
    let app = setup(db.clone()).await;
    sqlx::query("UPDATE products.packaging_categories SET active = false WHERE code = 'PALLET'")
        .execute(&db)
        .await
        .unwrap();
    let (status, r) = import(
        &app,
        ADMIN,
        "customers",
        true,
        "code,name,country_code,language,discount_percent,payment_terms_days,price_zone_code\n\
         NEW1,,BEL,xx,150,-1,Z1\n",
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{r}");
    let e = errors(&r);
    for col in [
        "name",
        "country_code",
        "language",
        "discount_percent",
        "payment_terms_days",
    ] {
        assert!(e.iter().any(|(_, c, _)| c == col), "{col}: {e:?}");
    }
    assert_eq!(
        e.iter().filter(|(_, c, _)| c == "name").count(),
        1,
        "no duplicate name error: {e:?}"
    );

    let (status, r) = import(
        &app,
        ADMIN,
        "products",
        true,
        "code,name,product_type,tracking,pricing_type,vat_rate,packaging_category_code,length_mm\n\
         N1,,gadget,wrong,wrong,-1,PALLET,0\n\
         PUMP-05,Pump,service,serial,list,21,PALLET,\n",
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{r}");
    let e = errors(&r);
    for col in [
        "name",
        "product_type",
        "tracking",
        "pricing_type",
        "vat_rate",
        "packaging_category_code",
        "length_mm",
    ] {
        assert!(
            e.iter().any(|(r, c, _)| *r == 2 && c == col),
            "{col}: {e:?}"
        );
    }
    assert!(
        e.iter()
            .any(|(r, c, m)| *r == 3 && c == "packaging_category_code" && m.contains("inactive")),
        "{e:?}"
    );
    assert!(
        e.iter()
            .any(|(r, _, m)| *r == 3 && m.contains("services cannot be tracked")),
        "{e:?}"
    );
}

/// A barcode taken by a concurrent writer between the plan and the write becomes a row error in
/// the report (422), not a generic 409.
#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn barcode_taken_during_the_import_is_a_row_error(db: PgPool) {
    let app = setup(db.clone()).await;
    let mut other = db.begin().await.unwrap();
    sqlx::query("UPDATE products.products SET barcode = 'RACE-1' WHERE code = 'PUMP-05'")
        .execute(&mut *other)
        .await
        .unwrap();
    let task = {
        let app = app.clone();
        tokio::spawn(async move {
            import(
                &app,
                ADMIN,
                "products",
                false,
                "code,name,vat_rate,barcode\nRACE-NEW,Racer,21,RACE-1\n",
            )
            .await
        })
    };
    tokio::time::sleep(std::time::Duration::from_millis(500)).await;
    other.commit().await.unwrap();
    let (status, r) = task.await.unwrap();
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{r}");
    let e = errors(&r);
    assert!(
        e.iter()
            .any(|(row, c, m)| *row == 2 && c == "barcode" && m.contains("PUMP-05")),
        "{e:?}"
    );
    let created: i64 =
        sqlx::query_scalar("SELECT count(*) FROM products.products WHERE code = 'RACE-NEW'")
            .fetch_one(&db)
            .await
            .unwrap();
    assert_eq!(created, 0);
}

/// A customer created concurrently under the same code makes the import update it instead of
/// failing with a 409.
#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn customer_code_created_during_the_import_is_updated(db: PgPool) {
    let app = setup(db.clone()).await;
    let mut other = db.begin().await.unwrap();
    sqlx::query(
        "INSERT INTO crm.customers (id, code, name, street, postal_code, city, country_code, language)
         VALUES (gen_random_uuid(), 'NEWC', 'First', '', '', '', 'BE', 'nl')",
    )
    .execute(&mut *other)
    .await
    .unwrap();
    let task = {
        let app = app.clone();
        tokio::spawn(async move {
            import(
                &app,
                ADMIN,
                "customers",
                false,
                "code,name,price_zone_code\nNEWC,Racer,Z1\n",
            )
            .await
        })
    };
    tokio::time::sleep(std::time::Duration::from_millis(500)).await;
    other.commit().await.unwrap();
    let (status, r) = task.await.unwrap();
    assert_eq!(status, StatusCode::OK, "{r}");
    assert_eq!(counts(&r), (0, 1, 0), "{r}");
    let names: Vec<String> =
        sqlx::query_scalar("SELECT name FROM crm.customers WHERE code = 'NEWC'")
            .fetch_all(&db)
            .await
            .unwrap();
    assert_eq!(names, ["Racer"]);
}
