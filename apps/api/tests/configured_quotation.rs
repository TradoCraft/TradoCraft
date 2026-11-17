//! Configured quotations imported from an external configurator (ADR 0033): line tree by product
//! code, sections, options, percent-of-parent pricing, unknown codes, idempotent re-import and
//! revisions, strict mode, permissions and the PDF.

mod common;

use axum::http::{Method, StatusCode};
use common::{call, dec, raw, setup, Who};
use rust_decimal_macros::dec;
use serde_json::{json, Value};
use sqlx::PgPool;

const INTEGRATION: &str = "integration@example.com";
const SALES: &str = "sales@example.com";
const ADMIN: &str = "admin@example.com";
const URI: &str = "/api/v1/quotations/configured";

/// The sample configuration shipped with the seed, plus an unknown code under the unit.
fn payload() -> Value {
    let mut p: Value = serde_json::from_str(include_str!(
        "../../../seed/configured_quotation_example.json"
    ))
    .unwrap();
    p["vat_regime_override"] = json!("domestic");
    p["lines"][0]["children"]
        .as_array_mut()
        .unwrap()
        .push(json!({ "code": "NO-SUCH-CODE", "quantity": "1",
                      "children": [{ "code": "BOLT-M8", "quantity": "4" }] }));
    p
}

fn line<'a>(q: &'a Value, code: &str) -> &'a Value {
    q["lines"]
        .as_array()
        .unwrap()
        .iter()
        .find(|l| l["product_code"] == code)
        .unwrap_or_else(|| panic!("no line {code} in {q}"))
}

async fn import(app: &axum::Router, user: &str, body: Value) -> (StatusCode, Value) {
    call(app, user, Method::POST, URI, Some(body)).await
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn import_prices_the_tree_and_warns_about_unknown_codes(db: PgPool) {
    let app = setup(db.clone()).await;
    let (status, r) = import(&app, INTEGRATION, payload()).await;
    assert_eq!(status, StatusCode::CREATED, "{r}");
    assert_eq!(r["action"], "created");
    let q = &r["quotation"];
    assert_eq!(q["status"], "draft");
    assert_eq!(q["revision"], 1);
    assert_eq!(q["price_zone_code"], "Z2");

    // Unknown code: skipped with its sub-line, one warning, listed first.
    let w = &q["warnings"][0];
    assert_eq!(w["kind"], "unknown_product", "{q}");
    assert_eq!(w["product_code"], "NO-SUCH-CODE");
    assert_eq!(w["details"]["path"], "1.4");
    assert_eq!(w["details"]["skipped_children"], 1);
    assert!(!q["lines"]
        .as_array()
        .unwrap()
        .iter()
        .any(|l| l["product_code"] == "BOLT-M8"));

    // Lines in tree order: the unit, its three options, then the installation.
    let codes: Vec<&str> = q["lines"]
        .as_array()
        .unwrap()
        .iter()
        .map(|l| l["product_code"].as_str().unwrap())
        .collect();
    assert_eq!(
        codes,
        ["UNIT-200", "FRAME-A", "CTRL-01", "COAT-PROT", "INSTALL"]
    );

    // Zone 2 prices for Alpha (5 % general rebate, 15 % on the controller), the unit's agreed
    // indicative price, and the coating at 20 % of the unit's list price.
    let unit = line(q, "UNIT-200");
    assert_eq!(unit["section"], "Process unit");
    assert_eq!(unit["parent_position"], Value::Null);
    assert_eq!(dec(&unit["list_unit_price"]), dec!(6500));
    assert_eq!(unit["price_confirmed"], true);
    assert_eq!(dec(&unit["line_total"]), dec!(6175.00));
    // Alpha's language is Dutch: the product name comes from the translation.
    assert_eq!(unit["description"], "Procesunit 200");
    assert_eq!(unit["comment"], "Configured for 400 V, stainless frame");

    let frame = line(q, "FRAME-A");
    assert_eq!(frame["parent_position"], 1);
    assert_eq!(frame["section"], Value::Null);
    assert_eq!(dec(&frame["list_unit_price"]), dec!(1160.00));
    assert_eq!(dec(&frame["line_total"]), dec!(1102.00));

    let ctrl = line(q, "CTRL-01");
    assert_eq!(ctrl["parent_position"], 1);
    assert_eq!(dec(&ctrl["list_unit_price"]), dec!(712.00));
    assert_eq!(ctrl["rebate_source"], "product");
    assert_eq!(dec(&ctrl["line_total"]), dec!(605.20));

    let coat = line(q, "COAT-PROT");
    assert_eq!(coat["parent_position"], 1);
    assert_eq!(dec(&coat["percent_of_parent"]), dec!(20));
    assert_eq!(coat["percent_base"], "parent_list_unit_price");
    assert_eq!(dec(&coat["list_unit_price"]), dec!(1300));
    assert_eq!(coat["rebate_source"], "general");
    assert_eq!(dec(&coat["line_total"]), dec!(1235.00));
    assert_eq!(coat["description"], "Corrosiebescherming");

    let install = line(q, "INSTALL");
    assert_eq!(install["section"], "Installation");
    assert_eq!(dec(&install["line_total"]), dec!(499.20));

    assert_eq!(dec(&q["subtotal"]), dec!(9616.40));
    assert_eq!(dec(&q["vat_total"]), dec!(2019.44));

    // The configuration is stored verbatim with the source reference.
    let (src, ext, conf): (String, String, Value) = sqlx::query_as(
        "SELECT import_source, import_external_ref, configuration FROM sales.quotations WHERE id = $1::uuid",
    )
    .bind(q["id"].as_str().unwrap())
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(
        (src.as_str(), ext.as_str()),
        ("configurator", "CFG-2026-0001")
    );
    assert_eq!(conf["choices"]["coating"], "C4");
    let parent_ok: bool = sqlx::query_scalar(
        "SELECT bool_and(c.quotation_id = p.quotation_id) FROM sales.quotation_lines c
         JOIN sales.quotation_lines p ON p.id = c.parent_line_id WHERE c.quotation_id = $1::uuid",
    )
    .bind(q["id"].as_str().unwrap())
    .fetch_one(&db)
    .await
    .unwrap();
    assert!(parent_ok);

    // The import is audited.
    let audited: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM audit.events WHERE entity_id = $1::uuid AND action = 'imported'",
    )
    .bind(q["id"].as_str().unwrap())
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(audited, 1);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn reimport_updates_the_draft_then_revises_after_sending(db: PgPool) {
    let app = setup(db).await;
    let (status, first) = import(&app, INTEGRATION, payload()).await;
    assert_eq!(status, StatusCode::CREATED, "{first}");
    let id = first["quotation"]["id"].as_str().unwrap().to_string();
    let number = first["quotation"]["number"].as_str().unwrap().to_string();

    // Same source and reference: the draft is replaced (two controllers now).
    let mut p = payload();
    p["lines"][0]["children"][1]["quantity"] = json!("2");
    let (status, second) = import(&app, INTEGRATION, p.clone()).await;
    assert_eq!(status, StatusCode::OK, "{second}");
    assert_eq!(second["action"], "updated");
    assert_eq!(second["quotation"]["id"], id.as_str());
    assert_eq!(second["quotation"]["revision"], 1);
    assert_eq!(
        dec(&line(&second["quotation"], "CTRL-01")["line_total"]),
        dec!(1210.40)
    );
    assert_eq!(dec(&second["quotation"]["subtotal"]), dec!(10221.60));

    // A different reference is a different quotation.
    let mut other = payload();
    other["external_ref"] = json!("CFG-2026-0002");
    let (status, o) = import(&app, INTEGRATION, other).await;
    assert_eq!(status, StatusCode::CREATED);
    assert_ne!(o["quotation"]["number"], number.as_str());

    // The integration account cannot send; a salesperson does.
    let (status, _) = call(
        &app,
        INTEGRATION,
        Method::POST,
        &format!("/api/v1/quotations/{id}/send"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, sent) = call(
        &app,
        SALES,
        Method::POST,
        &format!("/api/v1/quotations/{id}/send"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{sent}");

    // Re-import after sending: revision 2 of the same number, the sent one is superseded.
    p["lines"][1]["quantity"] = json!("10");
    let (status, third) = import(&app, INTEGRATION, p).await;
    assert_eq!(status, StatusCode::CREATED, "{third}");
    assert_eq!(third["action"], "revised");
    let q = &third["quotation"];
    assert_eq!(q["number"], number.as_str());
    assert_eq!(q["revision"], 2);
    assert_eq!(q["status"], "draft");
    assert_eq!(q["supersedes_id"], id.as_str());
    assert_eq!(dec(&line(q, "INSTALL")["quantity"]), dec!(10));
    assert_eq!(line(q, "COAT-PROT")["parent_position"], 1);
    let (_, old) = call(
        &app,
        SALES,
        Method::GET,
        &format!("/api/v1/quotations/{id}"),
        None,
    )
    .await;
    assert_eq!(old["status"], "superseded");

    // And again: the new draft (revision 2) is updated, no revision 3.
    let (status, fourth) = import(&app, INTEGRATION, payload()).await;
    assert_eq!(status, StatusCode::OK, "{fourth}");
    assert_eq!(fourth["quotation"]["id"], q["id"]);
    assert_eq!(fourth["quotation"]["revision"], 2);

    // A manual revision (keep prices) of a sent imported quotation stays traceable.
    let rev2 = q["id"].as_str().unwrap();
    let (status, _) = call(
        &app,
        SALES,
        Method::POST,
        &format!("/api/v1/quotations/{rev2}/send"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (status, manual) = call(
        &app,
        SALES,
        Method::POST,
        &format!("/api/v1/quotations/{rev2}/revise"),
        Some(json!({ "pricing": "current" })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{manual}");
    assert_eq!(manual["revision"], 3);
    // Structure survives repricing: parents, sections and the percentage.
    assert_eq!(line(&manual, "COAT-PROT")["parent_position"], 1);
    assert_eq!(
        dec(&line(&manual, "COAT-PROT")["percent_of_parent"]),
        dec!(20)
    );
    assert_eq!(line(&manual, "UNIT-200")["section"], "Process unit");
    let (status, fifth) = import(&app, INTEGRATION, payload()).await;
    assert_eq!(status, StatusCode::OK, "{fifth}");
    assert_eq!(fifth["quotation"]["id"], manual["id"]);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn strict_mode_refuses_unknown_codes(db: PgPool) {
    let app = setup(db.clone()).await;
    let mut p = payload();
    p["strict"] = json!(true);
    let (status, e) = import(&app, INTEGRATION, p.clone()).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{e}");
    assert!(
        e["message"].as_str().unwrap().contains("NO-SUCH-CODE"),
        "{e}"
    );
    // A zone the customer is not priced in is refused in strict mode, a warning otherwise.
    let mut p = json!(p);
    p["lines"][0]["children"].as_array_mut().unwrap().pop();
    p["price_zone_code"] = json!("Z5");
    let (status, e) = import(&app, INTEGRATION, p.clone()).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{e}");
    p["strict"] = json!(false);
    let (status, r) = import(&app, INTEGRATION, p.clone()).await;
    assert_eq!(status, StatusCode::CREATED, "{r}");
    assert_eq!(r["quotation"]["warnings"][0]["kind"], "price_zone_mismatch");
    // Nothing was stored by the refused imports.
    let n: i64 =
        sqlx::query_scalar("SELECT count(*) FROM sales.quotations WHERE import_source IS NOT NULL")
            .fetch_one(&db)
            .await
            .unwrap();
    assert_eq!(n, 1);

    // Invalid structure: a percentage on a top-level line.
    let mut bad = payload();
    bad["external_ref"] = json!("CFG-BAD");
    bad["lines"][1]["percent_of_parent"] = json!("10");
    let (status, e) = import(&app, INTEGRATION, bad).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{e}");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn import_needs_the_permission(db: PgPool) {
    let app = setup(db).await;
    let (status, _) = import(&app, SALES, payload()).await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, r) = import(&app, ADMIN, payload()).await;
    assert_eq!(status, StatusCode::CREATED, "{r}");
    // The integration account reads what it created but cannot change it by hand.
    let id = r["quotation"]["id"].as_str().unwrap();
    let (status, _) = call(
        &app,
        INTEGRATION,
        Method::GET,
        &format!("/api/v1/quotations/{id}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (status, _) = call(
        &app,
        INTEGRATION,
        Method::POST,
        "/api/v1/quotations",
        Some(json!({ "customer_id": "00000000-0000-7000-8000-000000000401", "lines": [] })),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn structured_lines_through_the_normal_api(db: PgPool) {
    // The structure fields are optional on POST /quotations and the preview.
    let app = setup(db).await;
    let unit = "00000000-0000-7000-8000-000000000301";
    let coat = "00000000-0000-7000-8000-0000000003c1";
    let body = json!({
        "customer_id": "00000000-0000-7000-8000-000000000402",
        "lines": [
            { "product_id": unit, "quantity": "2", "line_discount_percent": "10", "section": "Main" },
            { "product_id": coat, "quantity": "2", "parent_position": 1, "percent_of_parent": "15",
              "percent_base": "parent_net_unit_price" },
        ]
    });
    let (status, p) = call(
        &app,
        SALES,
        Method::POST,
        "/api/v1/pricing/preview",
        Some(body.clone()),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{p}");
    // Bêta: zone 3 (4365.00), no rebate; 10 % line discount: net 3928.50; 15 % of that = 589.275.
    assert_eq!(dec(&p["lines"][0]["net_unit_price"]), dec!(3928.5000));
    assert_eq!(dec(&p["lines"][1]["list_unit_price"]), dec!(589.2750));
    assert_eq!(p["lines"][1]["rebate_source"], "net");
    assert_eq!(dec(&p["lines"][1]["line_total"]), dec!(1178.55));
    let (status, q) = call(&app, SALES, Method::POST, "/api/v1/quotations", Some(body)).await;
    assert_eq!(status, StatusCode::CREATED, "{q}");
    assert_eq!(q["lines"][1]["parent_position"], 1);
    assert_eq!(q["lines"][1]["description"], "Protection anticorrosion");

    // A parent must come first; a net-based percentage cannot be discounted.
    for lines in [
        json!([{ "product_id": unit, "quantity": "1", "parent_position": 1 }]),
        json!([{ "product_id": unit, "quantity": "1" },
               { "product_id": coat, "quantity": "1", "parent_position": 1, "percent_of_parent": "5",
                 "percent_base": "parent_net_unit_price", "line_discount_percent": "3" }]),
        json!([{ "product_id": unit, "quantity": "1" },
               { "product_id": coat, "quantity": "1", "percent_of_parent": "5" }]),
    ] {
        let (status, e) = call(
            &app,
            SALES,
            Method::POST,
            "/api/v1/quotations",
            Some(json!({ "customer_id": "00000000-0000-7000-8000-000000000402", "lines": lines })),
        )
        .await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{e}");
    }
    // Without a parent, the percentage product has no price of its own.
    let (status, _) = call(
        &app,
        SALES,
        Method::POST,
        "/api/v1/quotations",
        Some(
            json!({ "customer_id": "00000000-0000-7000-8000-000000000402",
                     "lines": [{ "product_id": coat, "quantity": "1" }] }),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn product_translations_can_be_managed(db: PgPool) {
    let app = setup(db).await;
    let pump = "00000000-0000-7000-8000-000000000303";
    let uri = format!("/api/v1/products/{pump}/translations");
    let (status, t) = call(&app, SALES, Method::GET, &uri, None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(t, json!([]));
    let (status, _) = call(&app, SALES, Method::PUT, &uri, Some(json!([]))).await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let body = json!([{ "language": "nl", "name": "Pomp 0,5 kW" }, { "language": "FR", "name": "Pompe 0,5 kW" }]);
    let (status, t) = call(&app, ADMIN, Method::PUT, &uri, Some(body)).await;
    assert_eq!(status, StatusCode::OK, "{t}");
    assert_eq!(t[1]["language"], "nl");
    assert_eq!(t[0]["language"], "fr");
    let (status, _) = call(
        &app,
        ADMIN,
        Method::PUT,
        &uri,
        Some(json!([{ "language": "nl", "name": " " }])),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    // The German customer gets the base name (no German translation of the pump).
    let (_, q) = call(
        &app,
        SALES,
        Method::POST,
        "/api/v1/pricing/preview",
        Some(
            json!({ "customer_id": "00000000-0000-7000-8000-000000000403",
                     "lines": [{ "product_id": pump, "quantity": "1" }] }),
        ),
    )
    .await;
    assert_eq!(q["lines"][0]["description"], "Pump 0.5 kW");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn configured_quotation_pdf_renders(db: PgPool) {
    let app = setup(db).await;
    // The unit without an agreed price: an indicative (price on request) draft.
    let mut p = payload();
    p["lines"][0].as_object_mut().unwrap().remove("unit_price");
    let (status, r) = import(&app, INTEGRATION, p).await;
    assert_eq!(status, StatusCode::CREATED, "{r}");
    let q = &r["quotation"];
    assert_eq!(line(q, "UNIT-200")["price_confirmed"], false);
    // The coating follows its parent: unconfirmed as well.
    assert_eq!(line(q, "COAT-PROT")["price_confirmed"], false);
    let id = q["id"].as_str().unwrap();
    // Sending is refused while the indicative price is unconfirmed.
    let (status, _) = call(
        &app,
        SALES,
        Method::POST,
        &format!("/api/v1/quotations/{id}/send"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    if std::process::Command::new(std::env::var("TYPST_BIN").unwrap_or_else(|_| "typst".into()))
        .arg("--version")
        .output()
        .is_err()
    {
        eprintln!("typst not installed; skipping the PDF part");
        return;
    }
    let (status, _, pdf) = raw(
        &app,
        Who::Staff(INTEGRATION),
        Method::GET,
        &format!("/api/v1/quotations/{id}/pdf"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert!(pdf.starts_with(b"%PDF"));
    if let Ok(path) = std::env::var("CONFIGURED_PDF_OUT") {
        std::fs::write(path, &pdf).unwrap();
    }
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn extra_seed_files_run_in_name_order(db: PgPool) {
    let _app = setup(db.clone()).await;
    let dir = tempfile::tempdir().unwrap();
    // 20 runs after 10 and relies on it; other extensions are ignored.
    std::fs::write(
        dir.path().join("20_rename.sql"),
        "UPDATE products.products SET name = name || ' (demo)' WHERE code = 'EXTRA-1';",
    )
    .unwrap();
    std::fs::write(
        dir.path().join("10_product.sql"),
        "INSERT INTO products.products (id, code, name, unit, product_type, vat_rate)
         VALUES ('00000000-0000-7000-8000-0000000003f1', 'EXTRA-1', 'Extra product', 'pcs', 'purchased', 21);",
    )
    .unwrap();
    std::fs::write(dir.path().join("notes.txt"), "not SQL").unwrap();
    let ran = tradocraft_api::load_extra_seed(&db, dir.path())
        .await
        .unwrap();
    assert_eq!(ran, ["10_product.sql", "20_rename.sql"]);
    let name: String =
        sqlx::query_scalar("SELECT name FROM products.products WHERE code = 'EXTRA-1'")
            .fetch_one(&db)
            .await
            .unwrap();
    assert_eq!(name, "Extra product (demo)");
    // A failing file is reported as an error.
    let bad = tempfile::tempdir().unwrap();
    std::fs::write(bad.path().join("bad.sql"), "SELECT * FROM no_such_table;").unwrap();
    assert!(tradocraft_api::load_extra_seed(&db, bad.path())
        .await
        .is_err());
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn reimport_publishes_the_final_committed_version(db: PgPool) {
    use axum::body::Body;
    use axum::http::Request;
    use http_body_util::BodyExt;
    use tower::ServiceExt;
    let app = setup(db.clone()).await;
    let (status, first) = import(&app, INTEGRATION, payload()).await;
    assert_eq!(status, StatusCode::CREATED);
    let id = first["quotation"]["id"].as_str().unwrap();
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .uri(format!(
                    "/api/v1/events/records?entity_type=quotation&record_id={id}"
                ))
                .header("x-dev-user", SALES)
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::OK);
    let mut body = res.into_body();
    let (status, saved) = import(&app, INTEGRATION, payload()).await;
    assert_eq!(status, StatusCode::OK);
    let frame = tokio::time::timeout(std::time::Duration::from_secs(3), body.frame())
        .await
        .unwrap()
        .unwrap()
        .unwrap()
        .into_data()
        .unwrap();
    let text = String::from_utf8(frame.to_vec()).unwrap();
    let data = text
        .lines()
        .find_map(|line| line.strip_prefix("data: "))
        .unwrap();
    let event: Value = serde_json::from_str(data).unwrap();
    let committed: i64 =
        sqlx::query_scalar("SELECT version FROM sales.quotations WHERE id = $1::text::uuid")
            .bind(id)
            .fetch_one(&db)
            .await
            .unwrap();
    assert_eq!(event["version"], committed);
    assert_eq!(event["version"], saved["quotation"]["version"]);
}
