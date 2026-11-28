//! The importable entities of ADR 0100: product translations in the products file, zone prices,
//! price list items, and fixed values in a column mapping.

mod common;

use axum::http::{Method, StatusCode};
use common::{call, raw, setup, Who};
use serde_json::{json, Value};
use sqlx::PgPool;

const ADMIN: &str = "admin@example.com";
const UNIT_200: &str = "00000000-0000-7000-8000-000000000302";

async fn upload(app: &axum::Router, name: &str, body: &str) -> String {
    let (status, _, body) = raw(
        app,
        Who::Staff(ADMIN),
        Method::POST,
        &format!("/api/v1/imports/files?filename={name}"),
        Some(("application/octet-stream", body.as_bytes().to_vec())),
    )
    .await;
    let f: Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(status, StatusCode::CREATED, "{f}");
    f["id"].as_str().unwrap().to_string()
}

/// Uploads `csv` and runs it inline as `entity` with the mapping `columns` (null: header names).
async fn run(app: &axum::Router, entity: &str, csv: &str, columns: Value, dry_run: bool) -> Value {
    let file = upload(app, "f.csv", csv).await;
    let (status, job) = call(
        app,
        ADMIN,
        Method::POST,
        "/api/v1/imports/jobs",
        Some(json!({"file_id": file, "entity": entity, "columns": columns, "dry_run": dry_run})),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{job}");
    assert_eq!(job["status"], "done", "{job}");
    job
}

fn counts(job: &Value) -> (i64, i64, i64) {
    (
        job["created"].as_i64().unwrap(),
        job["updated"].as_i64().unwrap(),
        job["unchanged"].as_i64().unwrap(),
    )
}

/// `(row, column, message)` of the errors of a job.
fn errors(job: &Value) -> Vec<(i64, String, String)> {
    job["errors"]
        .as_array()
        .unwrap()
        .iter()
        .map(|e| {
            (
                e["row"].as_i64().unwrap(),
                e["column"].as_str().unwrap_or("").to_string(),
                e["message"].as_str().unwrap().to_string(),
            )
        })
        .collect()
}

fn has_error(job: &Value, row: i64, column: &str, part: &str) -> bool {
    errors(job)
        .iter()
        .any(|(r, c, m)| *r == row && c == column && m.contains(part))
}

async fn export(app: &axum::Router, entity: &str) -> String {
    let (status, _, body) = raw(
        app,
        Who::Staff(ADMIN),
        Method::GET,
        &format!("/api/v1/imports/entities/{entity}/export"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    String::from_utf8(body).unwrap()
}

async fn translations(db: &PgPool, product: &str) -> Vec<(String, String, String)> {
    sqlx::query_as(
        "SELECT language::text, t.name, t.description FROM products.product_translations t
         JOIN products.products p ON p.id = t.product_id WHERE p.code = $1 ORDER BY language",
    )
    .bind(product)
    .fetch_all(db)
    .await
    .unwrap()
}

fn tr(l: &str, n: &str, d: &str) -> (String, String, String) {
    (l.into(), n.into(), d.into())
}

// ---------------------------------------------------------------------------------------------
// Product translations
// ---------------------------------------------------------------------------------------------

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn product_translations_are_upserted_per_language(db: PgPool) {
    let app = setup(db.clone()).await;
    let before = translations(&db, "UNIT-200").await;
    assert!(before.iter().any(|t| t.0 == "nl"));
    let nl_name = before.iter().find(|t| t.0 == "nl").unwrap().1.clone();

    // fr: a new name; nl: only a description (the stored name stays); it: a new language;
    // de: both cells empty (unchanged, never deleted). P-100 is new: its pl translation has only
    // a description and takes the product's own name.
    let csv = "code,name,vat_rate,name_fr,description_fr,description_nl,name_it,name_de,description_de,description_pl\n\
               UNIT-200,,,Unité 200 bis,,Nieuwe tekst,Unità 200,,,\n\
               P-100,Spare parts,21,,,,,,,Części\n";
    let job = run(&app, "products", csv, Value::Null, false).await;
    assert_eq!(errors(&job), vec![]);
    assert_eq!(counts(&job), (1, 1, 0));
    let after = translations(&db, "UNIT-200").await;
    assert!(after.contains(&tr("fr", "Unité 200 bis", "")));
    assert!(after.contains(&tr("nl", &nl_name, "Nieuwe tekst")));
    assert!(after.contains(&tr("it", "Unità 200", "")));
    assert_eq!(
        after.iter().find(|t| t.0 == "de"),
        before.iter().find(|t| t.0 == "de")
    );
    assert_eq!(
        translations(&db, "P-100").await,
        [tr("pl", "Spare parts", "Części")]
    );

    // The same file again changes nothing; so does the export.
    let job = run(&app, "products", csv, Value::Null, false).await;
    assert_eq!(counts(&job), (0, 0, 2));
    let exported = export(&app, "products").await;
    let header = exported.lines().next().unwrap();
    assert!(header.ends_with(
        "name_de,description_de,name_fr,description_fr,name_it,description_it,\
         name_nl,description_nl,name_pl,description_pl"
    ));
    let job = run(&app, "products", &exported, Value::Null, false).await;
    assert_eq!(errors(&job), vec![]);
    assert_eq!(job["created"], 0);
    assert_eq!(job["updated"], 0);

    // A column for a code that is not ISO 639-1 is unknown.
    let job = run(
        &app,
        "products",
        "code,name_xx\nUNIT-200,x\n",
        Value::Null,
        true,
    )
    .await;
    assert!(has_error(&job, 1, "name_xx", "unknown column"), "{job}");
}

// ---------------------------------------------------------------------------------------------
// Zone prices
// ---------------------------------------------------------------------------------------------

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn zone_prices_create_update_and_keep_history(db: PgPool) {
    let app = setup(db.clone()).await;
    let future = (tradocraft_core::today() + chrono::Days::new(30)).to_string();
    let csv = format!(
        "product_code,zone,valid_from,unit_price\n\
         UNIT-200,Z1,{future},1200.50\n\
         UNIT-200,Z2,{future},1300\n"
    );
    let job = run(&app, "zone_prices", &csv, Value::Null, false).await;
    assert_eq!(errors(&job), vec![]);
    assert_eq!(counts(&job), (2, 0, 0));
    let price: rust_decimal::Decimal = sqlx::query_scalar(
        "SELECT unit_price FROM pricing.zone_prices zp JOIN pricing.price_zones z ON z.id = zp.zone_id
         WHERE zp.product_id = $1 AND z.code = 'Z1' AND valid_from = $2::date",
    )
    .bind(uuid::Uuid::parse_str(UNIT_200).unwrap())
    .bind(&future)
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(price.to_string(), "1200.5000");
    // The audit events are those of the price endpoints, on the product.
    let actions: Vec<String> = sqlx::query_scalar(
        "SELECT action FROM audit.events WHERE entity = 'product' AND entity_id = $1
         AND data->>'source' = 'csv_import' ORDER BY action",
    )
    .bind(uuid::Uuid::parse_str(UNIT_200).unwrap())
    .fetch_all(&db)
    .await
    .unwrap();
    assert_eq!(actions, ["price_added", "price_added"]);

    // A planned price can be corrected; the export imports back unchanged.
    let csv = format!("product_code,zone,valid_from,unit_price\nUNIT-200,Z1,{future},1250\n");
    let job = run(&app, "zone_prices", &csv, Value::Null, false).await;
    assert_eq!(counts(&job), (0, 1, 0));
    let exported = export(&app, "zone_prices").await;
    assert_eq!(
        exported.lines().next().unwrap(),
        "product_code,zone,valid_from,unit_price"
    );
    assert!(exported.contains(&format!("UNIT-200,Z1,{future},1250")));
    let job = run(&app, "zone_prices", &exported, Value::Null, false).await;
    assert_eq!(errors(&job), vec![]);
    assert_eq!(
        (job["created"].as_i64(), job["updated"].as_i64()),
        (Some(0), Some(0))
    );

    // A price in effect is history; unknown codes and bad dates are row errors.
    let (code, zone, from, old): (String, String, chrono::NaiveDate, rust_decimal::Decimal) =
        sqlx::query_as(
            "SELECT p.code, z.code, zp.valid_from, zp.unit_price FROM pricing.zone_prices zp
             JOIN products.products p ON p.id = zp.product_id
             JOIN pricing.price_zones z ON z.id = zp.zone_id
             WHERE zp.valid_from <= current_date LIMIT 1",
        )
        .fetch_one(&db)
        .await
        .unwrap();
    let csv = format!(
        "product_code,zone,valid_from,unit_price\n\
         {code},{zone},{from},{}\n\
         NOPE,Z1,{future},1\n\
         UNIT-200,ZX,{future},1\n\
         UNIT-200,Z3,2027-1-1,1\n\
         UNIT-200,Z3,{future},\n",
        old + rust_decimal::Decimal::ONE
    );
    let job = run(&app, "zone_prices", &csv, Value::Null, false).await;
    assert!(has_error(&job, 2, "unit_price", "in effect since"), "{job}");
    assert!(has_error(&job, 3, "product_code", "unknown product"));
    assert!(has_error(&job, 4, "zone", "unknown price zone"));
    assert!(has_error(&job, 5, "valid_from", "YYYY-MM-DD"));
    assert!(has_error(&job, 6, "unit_price", "required"));
    assert_eq!(counts(&job), (0, 0, 0));
}

// ---------------------------------------------------------------------------------------------
// Fixed values
// ---------------------------------------------------------------------------------------------

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_mapping_can_give_a_field_a_fixed_value(db: PgPool) {
    let app = setup(db.clone()).await;
    let future = (tradocraft_core::today() + chrono::Days::new(60)).to_string();
    let csv = "Article;Price\nUNIT-200;10,5\nPUMP-05;20\n";
    let columns = json!([
        {"column": "Article", "field": "product_code"},
        {"column": "Price", "field": "unit_price"},
        {"value": "Z2", "field": "zone"},
        {"value": future, "field": "valid_from"},
    ]);
    let job = run(&app, "zone_prices", csv, columns.clone(), false).await;
    assert_eq!(errors(&job), vec![]);
    assert_eq!(counts(&job), (2, 0, 0));
    let n: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM pricing.zone_prices zp JOIN pricing.price_zones z ON z.id = zp.zone_id
         WHERE z.code = 'Z2' AND zp.valid_from = $1::date",
    )
    .bind(&future)
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(n, 2);

    // A saved mapping keeps its fixed values; the old shape is unchanged.
    let (status, saved) = call(
        &app,
        ADMIN,
        Method::PUT,
        "/api/v1/imports/mappings",
        Some(json!({"entity": "zone_prices", "name": "Planned", "columns": columns})),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{saved}");
    assert_eq!(saved["columns"][2], json!({"value": "Z2", "field": "zone"}));
    assert_eq!(
        saved["columns"][0],
        json!({"column": "Article", "field": "product_code"})
    );

    // Exactly one of column and value; a fixed field may not also be a file column.
    for bad in [
        json!([{"field": "zone"}]),
        json!([{"column": "A", "value": "Z1", "field": "zone"}]),
        json!([{"value": " ", "field": "zone"}]),
        json!([{"column": "Zone", "field": "zone"}, {"value": "Z1", "field": "zone"}]),
    ] {
        let file = upload(&app, "f.csv", csv).await;
        let (status, body) = call(
            &app,
            ADMIN,
            Method::POST,
            "/api/v1/imports/jobs",
            Some(
                json!({"file_id": file, "entity": "zone_prices", "columns": bad, "dry_run": true}),
            ),
        )
        .await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{bad}: {body}");
    }
    // A fixed value that does not parse is a row error on every row, like a bad cell.
    let columns = json!([
        {"column": "Article", "field": "product_code"},
        {"value": "ten", "field": "unit_price"},
        {"value": "Z2", "field": "zone"},
        {"value": future, "field": "valid_from"},
    ]);
    let job = run(&app, "zone_prices", csv, columns, true).await;
    assert!(has_error(&job, 2, "unit_price", "not a number"), "{job}");
    assert!(has_error(&job, 3, "unit_price", "not a number"));
}

// ---------------------------------------------------------------------------------------------
// Price list items
// ---------------------------------------------------------------------------------------------

async fn create_list(app: &axum::Router, code: &str, settings: Value) -> String {
    let (status, list) = call(
        app,
        ADMIN,
        Method::POST,
        "/api/v1/price-lists",
        Some(
            json!({"code": code, "name": "Import test", "valid_from": "2027-01-01",
                    "settings": settings}),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{list}");
    list["id"].as_str().unwrap().to_string()
}

async fn groups(app: &axum::Router, list: &str) -> Vec<Value> {
    let (status, groups) = call(
        app,
        ADMIN,
        Method::GET,
        &format!("/api/v1/price-lists/{list}/groups"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    groups.as_array().unwrap().clone()
}

async fn items(app: &axum::Router, list: &str) -> Vec<Value> {
    let (status, items) = call(
        app,
        ADMIN,
        Method::GET,
        &format!("/api/v1/price-lists/{list}/items"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    items.as_array().unwrap().clone()
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn price_list_items_build_the_group_tree_from_positions(db: PgPool) {
    let app = setup(db.clone()).await;
    let list = create_list(&app, "PL-A", json!({})).await;

    // Two group levels (the default). Group 1.1 has two titles in nl: the lower position wins.
    // Group 2 is named by a short position. Group 1.2 has no title at all.
    let csv = "price_list,product_code,position,group_title_nl,group_title_fr,net,hidden\n\
               PL-A,UNIT-100,1.1.10,Late title,,false,\n\
               PL-A,UNIT-200,1.1.2.,Early title,Titre,,\n\
               PL-A,PUMP-05,1.2.1,,,true,\n\
               PL-A,BOLT-M8,2,Position,,,true\n";
    let job = run(&app, "price_list_items", csv, Value::Null, false).await;
    assert_eq!(errors(&job), vec![]);
    assert_eq!(counts(&job), (4, 0, 0));
    let g = groups(&app, &list).await;
    assert_eq!(g.len(), 4, "groups 1, 1.1, 1.2 and 2: {g:?}");
    let top1 = g
        .iter()
        .find(|g| g["parent_id"].is_null() && g["sort_order"] == 1)
        .unwrap();
    let g11 = g
        .iter()
        .find(|x| x["parent_id"] == top1["id"] && x["sort_order"] == 1)
        .unwrap();
    assert_eq!(g11["title"], json!({"nl": "Early title", "fr": "Titre"}));
    assert_eq!(g11["show_title"], true);
    let g12 = g
        .iter()
        .find(|x| x["parent_id"] == top1["id"] && x["sort_order"] == 2)
        .unwrap();
    assert_eq!(g12["title"], json!({}));
    assert_eq!(
        g12["show_title"], false,
        "an untitled new group prints no title"
    );
    assert_eq!(top1["show_title"], false);
    let top2 = g
        .iter()
        .find(|g| g["parent_id"].is_null() && g["sort_order"] == 2)
        .unwrap();
    assert_eq!(top2["title"], json!({"nl": "Position"}));
    let it = items(&app, &list).await;
    let item = |code: &str| {
        it.iter()
            .find(|i| i["product_code"] == code)
            .unwrap()
            .clone()
    };
    assert_eq!(item("UNIT-200")["sort_key"], "2");
    assert_eq!(item("UNIT-200")["group_id"], g11["id"]);
    assert_eq!(item("PUMP-05")["net"], true);
    assert_eq!(item("BOLT-M8")["sort_key"], "");
    assert_eq!(item("BOLT-M8")["hidden"], true);
    assert_eq!(item("BOLT-M8")["group_id"], top2["id"]);

    // Its own export imports back unchanged; the same file too.
    let exported = export(&app, "price_list_items").await;
    assert_eq!(
        exported.lines().next().unwrap(),
        "price_list,product_code,position,group_title_fr,group_title_nl,price_on_request,net,indicative,hidden"
    );
    assert!(exported.contains("PL-A,UNIT-200,1.1.2,Titre,Early title,false,false,false,false"));
    let job = run(&app, "price_list_items", &exported, Value::Null, false).await;
    assert_eq!(errors(&job), vec![]);
    assert_eq!(counts(&job), (0, 0, 4));
    let job = run(&app, "price_list_items", csv, Value::Null, false).await;
    assert_eq!(counts(&job), (0, 0, 4));

    // Moving an item and retitling a group are updates; nothing is deleted.
    let csv = "price_list,product_code,position,group_title_nl\n\
               PL-A,UNIT-100,1.2.5,Second\n";
    let job = run(&app, "price_list_items", csv, Value::Null, false).await;
    assert_eq!(counts(&job), (0, 1, 0));
    assert_eq!(items(&app, &list).await.len(), 4);
    let g = groups(&app, &list).await;
    assert_eq!(g.len(), 4);
    assert!(g.iter().any(|x| x["title"] == json!({"nl": "Second"})));

    // Unknown list or product, bad positions, a new item without a position.
    let csv = "price_list,product_code,position\n\
               NOPE,UNIT-100,1.1\n\
               PL-A,NOPE,1.1\n\
               PL-A,PUMP-05,A.1\n\
               PL-A,FRAME-A,\n\
               PL-A,PROFILE-40,1..2\n";
    let job = run(&app, "price_list_items", csv, Value::Null, true).await;
    assert!(
        has_error(&job, 2, "price_list", "unknown price list"),
        "{job}"
    );
    assert!(has_error(&job, 3, "product_code", "unknown product"));
    assert!(has_error(&job, 4, "position", "not a whole number"));
    assert!(has_error(&job, 5, "position", "required for a new item"));
    assert!(has_error(&job, 6, "position", "empty segment"));
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_list_settings_decide_how_positions_and_titles_are_read(db: PgPool) {
    let app = setup(db.clone()).await;
    // The settings are validated by the API.
    let (status, _) = call(
        &app,
        ADMIN,
        Method::POST,
        "/api/v1/price-lists",
        Some(
            json!({"code": "BAD", "name": "x", "valid_from": "2027-01-01",
                    "settings": {"import_group_levels": 5}}),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    let list = create_list(
        &app,
        "PL-B",
        json!({"import_group_levels": 1, "import_title_conflict": "first_row",
               "import_short_position": "error"}),
    )
    .await;
    let csv = "price_list,product_code,position,group_title_en\n\
               PL-B,UNIT-100,3.10,First\n\
               PL-B,UNIT-200,3.2,Second\n";
    let job = run(&app, "price_list_items", csv, Value::Null, false).await;
    assert_eq!(errors(&job), vec![]);
    let g = groups(&app, &list).await;
    assert_eq!(g.len(), 1);
    assert_eq!(g[0]["title"], json!({"en": "First"}));
    let it = items(&app, &list).await;
    assert!(it.iter().any(|i| i["sort_key"] == "10"));

    create_list(
        &app,
        "PL-C",
        json!({"import_group_levels": 2, "import_title_conflict": "error",
               "import_short_position": "error"}),
    )
    .await;
    let csv = "price_list,product_code,position,group_title_en\n\
               PL-C,UNIT-100,1.1.1,One\n\
               PL-C,UNIT-200,1.1.2,Two\n\
               PL-C,PUMP-05,4,Short\n";
    let job = run(&app, "price_list_items", csv, Value::Null, true).await;
    assert!(
        has_error(&job, 3, "position", "differs from line 2"),
        "{job}"
    );
    assert!(has_error(&job, 4, "position", "at least 2 segments"));
}
