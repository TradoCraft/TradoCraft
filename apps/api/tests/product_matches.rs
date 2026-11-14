//! Advisory product matching for opportunities (ADR 0068, Phase 5a): the admin-editable match
//! rules and `GET /opportunities/{id}/product-matches`.

mod common;

use axum::http::{Method, StatusCode};
use common::{call, setup};
use serde_json::{json, Value};
use sqlx::PgPool;

const ADMIN: &str = "admin@example.com";
const SALES: &str = "sales@example.com";
const VIEWER: &str = "viewer@example.com";
const COMPANY: &str = "00000000-0000-7000-8000-000000000001";
const OPP: &str = "00000000-0000-7000-8000-000000000701"; // customer Alpha (BE)
const OPP2: &str = "00000000-0000-7000-8000-000000000702";
const BETA: &str = "00000000-0000-7000-8000-000000000402"; // BE
const UNIT_100: &str = "00000000-0000-7000-8000-000000000301"; // seeded 3x400V 50Hz
const UNIT_200: &str = "00000000-0000-7000-8000-000000000302"; // seeded 120V 60Hz
const PUMP: &str = "00000000-0000-7000-8000-000000000303"; // seeded 230V 1-phase
const BOLT: &str = "00000000-0000-7000-8000-000000000309"; // no supplies
const CTRL: &str = "00000000-0000-7000-8000-000000000310"; // seeded 24V DC
const OTHER_COMPANY: &str = "00000000-0000-7000-8000-0000000fff01";
const OTHER_OPP: &str = "00000000-0000-7000-8000-0000000fff02";
const RULE_NAME: &str = "Dial size fits product";

async fn api(
    app: &axum::Router,
    user: &str,
    method: Method,
    uri: &str,
    body: Option<Value>,
) -> (StatusCode, Value) {
    call(app, user, method, &format!("/api/v1{uri}"), body).await
}

async fn seeded(db: &PgPool) -> axum::Router {
    let app = setup(db.clone()).await;
    sqlx::query("SELECT crm.seed_baseline_defaults($1::uuid)")
        .bind(COMPANY)
        .execute(db)
        .await
        .unwrap();
    app
}

async fn rules(app: &axum::Router) -> Vec<Value> {
    let (status, list) = api(app, SALES, Method::GET, "/match-rules", None).await;
    assert_eq!(status, StatusCode::OK, "{list}");
    list.as_array().unwrap().clone()
}

async fn rule_id(app: &axum::Router, name: &str) -> String {
    rules(app)
        .await
        .iter()
        .find(|r| r["name"] == name)
        .unwrap_or_else(|| panic!("no rule {name}"))["id"]
        .as_str()
        .unwrap()
        .to_string()
}

fn rule_body(extra: Value) -> Value {
    let mut body = json!({
        "name": "Bell weight fits product",
        "baseline_type_code": "bell",
        "baseline_attribute_key": "weight_kg",
        "product_attribute_key": "max_bell_kg",
        "operator": "at_most",
    });
    for (k, v) in extra.as_object().unwrap() {
        body[k] = v.clone();
    }
    body
}

async fn define_product_number(app: &axum::Router, key: &str) {
    let (status, d) = api(
        app,
        ADMIN,
        Method::POST,
        "/attribute-definitions",
        Some(json!({ "key": key, "label": key, "kind": "number", "scope": "product" })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{d}");
}

async fn grid_id(app: &axum::Router, country: &str, voltage: i64, phases: i64) -> String {
    let (_, list) = api(
        app,
        SALES,
        Method::GET,
        &format!("/power-grids?country={country}"),
        None,
    )
    .await;
    list.as_array()
        .unwrap()
        .iter()
        .find(|g| g["voltage_v"] == voltage && g["phases"] == phases)
        .unwrap_or_else(|| panic!("no {country} grid {voltage}V/{phases}"))["id"]
        .as_str()
        .unwrap()
        .to_string()
}

async fn set_grid(app: &axum::Router, opp: &str, grid: &str) {
    let (status, o) = api(
        app,
        SALES,
        Method::PUT,
        &format!("/opportunities/{opp}"),
        Some(
            json!({ "customer_id": "00000000-0000-7000-8000-000000000401",
                     "title": "Tower", "power_grid_id": grid }),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{o}");
}

async fn add_item(app: &axum::Router, opp: &str, body: Value) -> String {
    let (status, r) = api(
        app,
        SALES,
        Method::POST,
        &format!("/opportunities/{opp}/baseline/items"),
        Some(body),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{r}");
    r["id"].as_str().unwrap().to_string()
}

async fn dial_size(app: &axum::Router, product: &str, min: &str, max: &str) {
    let (status, r) = api(
        app,
        ADMIN,
        Method::PUT,
        &format!("/products/{product}/attributes"),
        Some(
            json!([{ "key": "dial_size_mm", "kind": "range", "value": "",
                      "value_min": min, "value_max": max, "unit": "mm" }]),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{r}");
}

async fn matches(app: &axum::Router, opp: &str, query: &str) -> Value {
    let (status, m) = api(
        app,
        SALES,
        Method::GET,
        &format!("/opportunities/{opp}/product-matches?{query}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{m}");
    m
}

fn of<'a>(m: &'a Value, product: &str) -> &'a Value {
    m["items"]
        .as_array()
        .unwrap()
        .iter()
        .find(|p| p["id"] == product)
        .unwrap_or_else(|| panic!("product {product} not in {m}"))
}

fn reasons(p: &Value) -> Vec<(String, String, String)> {
    p["reasons"]
        .as_array()
        .unwrap()
        .iter()
        .map(|r| {
            (
                r["check"].as_str().unwrap().to_string(),
                r["status"].as_str().unwrap().to_string(),
                r["message"].as_str().unwrap().to_string(),
            )
        })
        .collect()
}

// ---------------------------------------------------------------------------------------------
// Rules
// ---------------------------------------------------------------------------------------------

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_dial_rule_is_seeded_once(db: PgPool) {
    let app = seeded(&db).await;
    sqlx::query("SELECT crm.seed_baseline_defaults($1::uuid)")
        .bind(COMPANY)
        .execute(&db)
        .await
        .unwrap();
    let list = rules(&app).await;
    assert_eq!(list.len(), 1, "{list:?}");
    let r = &list[0];
    assert_eq!(r["name"], RULE_NAME);
    assert_eq!(r["baseline_type_code"], "clock_dial");
    assert_eq!(r["baseline_attribute_key"], "dial_diameter_mm");
    assert_eq!(r["product_attribute_key"], "dial_size_mm");
    assert_eq!(r["operator"], "within_range");
    assert_eq!(r["active"], true);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn seed_keeps_what_an_admin_changed_and_a_provisioned_company_gets_the_rule(db: PgPool) {
    let app = seeded(&db).await;
    let id = rule_id(&app, RULE_NAME).await;
    let (status, _) = api(
        &app,
        ADMIN,
        Method::PUT,
        &format!("/match-rules/{id}"),
        Some(json!({
            "name": RULE_NAME, "baseline_type_code": "clock_dial",
            "baseline_attribute_key": "dial_diameter_mm", "product_attribute_key": "dial_size_mm",
            "operator": "within_range", "active": false })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    sqlx::query("SELECT crm.seed_baseline_defaults($1::uuid)")
        .bind(COMPANY)
        .execute(&db)
        .await
        .unwrap();
    let active: bool = sqlx::query_scalar("SELECT active FROM crm.match_rules WHERE name = $1")
        .bind(RULE_NAME)
        .fetch_one(&db)
        .await
        .unwrap();
    assert!(
        !active,
        "the seed must not reactivate an administrator's choice"
    );

    let mut tx = db.begin().await.unwrap();
    let spec: tradocraft_core::companies::ProvisionSpec = serde_json::from_value(
        json!({ "name": "Prov BV", "country_code": "BE", "currency": "EUR", "default_language": "en",
                "admin_email": "prov@example.com", "admin_display_name": "Prov" }),
    )
    .unwrap();
    let p = tradocraft_core::companies::provision(&mut tx, &spec)
        .await
        .unwrap();
    tx.commit().await.unwrap();
    let n: i64 = sqlx::query_scalar("SELECT count(*) FROM crm.match_rules WHERE company_id = $1")
        .bind(p.company.id)
        .fetch_one(&db)
        .await
        .unwrap();
    assert_eq!(n, 1);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn rule_crud_validation_permissions_and_audit(db: PgPool) {
    let app = seeded(&db).await;
    define_product_number(&app, "max_bell_kg").await;

    let post = |body: Value| api(&app, ADMIN, Method::POST, "/match-rules", Some(body));
    let (status, r) = post(rule_body(json!({ "name": "  Bell weight fits product " }))).await;
    assert_eq!(status, StatusCode::CREATED, "{r}");
    assert_eq!(r["name"], "Bell weight fits product");
    assert_eq!(r["active"], true);
    assert_eq!(r["sort_order"], 0);
    let id = r["id"].as_str().unwrap().to_string();
    let url = format!("/match-rules/{id}");

    // Everyone with opportunities.read reads; writing needs products.write.
    for user in [SALES, VIEWER] {
        let (status, got) = api(&app, user, Method::GET, &url, None).await;
        assert_eq!(status, StatusCode::OK, "{user}");
        assert_eq!(got["id"], id.as_str());
    }
    assert_eq!(
        api(
            &app,
            SALES,
            Method::POST,
            "/match-rules",
            Some(rule_body(json!({ "name": "x" })))
        )
        .await
        .0,
        StatusCode::FORBIDDEN
    );
    assert_eq!(
        api(&app, SALES, Method::DELETE, &url, None).await.0,
        StatusCode::FORBIDDEN
    );

    // Duplicate name: 409.
    assert_eq!(post(rule_body(json!({}))).await.0, StatusCode::CONFLICT);

    // Invalid references: 422, nothing stored.
    let bad = [
        json!({ "name": " " }),
        json!({ "name": "a", "baseline_type_code": "nope" }),
        json!({ "name": "b", "baseline_attribute_key": "nope" }),
        // a key of another scope (a clock dial key on a bell rule)
        json!({ "name": "c", "baseline_attribute_key": "dial_diameter_mm" }),
        json!({ "name": "d", "product_attribute_key": "nope" }),
        // a baseline key used as the product key
        json!({ "name": "e", "product_attribute_key": "weight_kg" }),
        // operator against the wrong kind: within_range needs a range, at_most a number
        json!({ "name": "f", "operator": "within_range" }),
        json!({ "name": "g", "product_attribute_key": "dial_size_mm", "operator": "at_most" }),
        json!({ "name": "h", "product_attribute_key": "dial_size_mm", "operator": "at_least" }),
        // a select cannot be compared
        json!({ "name": "i", "baseline_attribute_key": "motion" }),
    ];
    for extra in bad {
        let (status, r) = post(rule_body(extra.clone())).await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{extra} {r}");
    }
    let (status, _) = post(rule_body(json!({ "name": "j", "operator": "sideways" }))).await;
    assert!(status.is_client_error(), "{status}");
    assert_eq!(
        rules(&app).await.len(),
        2,
        "only the seed and the valid rule"
    );

    // An inactive definition no longer counts.
    let (_, defs) = api(&app, ADMIN, Method::GET, "/attribute-definitions", None).await;
    let weight = defs
        .as_array()
        .unwrap()
        .iter()
        .find(|d| d["key"] == "weight_kg")
        .unwrap()
        .clone();
    let (status, r) = api(
        &app,
        ADMIN,
        Method::PUT,
        &format!("/attribute-definitions/{}", weight["id"].as_str().unwrap()),
        Some(
            json!({ "label": "Weight", "kind": "number", "unit": "kg", "scope": "bell",
                     "key": "weight_kg", "active": false }),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{r}");
    let (status, r) = post(rule_body(json!({ "name": "k" }))).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{r}");

    // Update replaces the rule and validates the same way.
    let update = |body: Value| api(&app, ADMIN, Method::PUT, &url, Some(body));
    let (status, u) = update(rule_body(json!({ "active": false, "sort_order": 5,
        "baseline_attribute_key": "diameter_mm", "name": "Bell size fits" })))
    .await;
    assert_eq!(status, StatusCode::OK, "{u}");
    assert_eq!(u["name"], "Bell size fits");
    assert_eq!(u["active"], false);
    assert_eq!(u["sort_order"], 5);
    let (status, _) = update(rule_body(json!({ "baseline_type_code": "nope" }))).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    let (status, _) = update(rule_body(
        json!({ "name": RULE_NAME, "baseline_attribute_key": "diameter_mm" }),
    ))
    .await;
    assert_eq!(status, StatusCode::CONFLICT, "name of the seed rule");

    // Delete, then 404; the actions are audited.
    assert_eq!(
        api(&app, ADMIN, Method::DELETE, &url, None).await.0,
        StatusCode::NO_CONTENT
    );
    assert_eq!(
        api(&app, ADMIN, Method::GET, &url, None).await.0,
        StatusCode::NOT_FOUND
    );
    assert_eq!(
        api(&app, ADMIN, Method::DELETE, &url, None).await.0,
        StatusCode::NOT_FOUND
    );
    let actions: Vec<String> = sqlx::query_scalar(
        "SELECT action FROM audit.events WHERE entity = 'match_rule' AND entity_id = $1::uuid ORDER BY id",
    )
    .bind(&id)
    .fetch_all(&db)
    .await
    .unwrap();
    assert_eq!(actions, ["created", "updated", "deleted"]);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn another_companys_rules_are_invisible(db: PgPool) {
    let app = seeded(&db).await;
    sqlx::query("INSERT INTO core.companies (id, name) VALUES ($1::uuid, 'Other BV')")
        .bind(OTHER_COMPANY)
        .execute(&db)
        .await
        .unwrap();
    sqlx::query("SELECT crm.seed_baseline_defaults($1::uuid)")
        .bind(OTHER_COMPANY)
        .execute(&db)
        .await
        .unwrap();
    let other: String =
        sqlx::query_scalar("SELECT id::text FROM crm.match_rules WHERE company_id = $1::uuid")
            .bind(OTHER_COMPANY)
            .fetch_one(&db)
            .await
            .unwrap();
    assert_eq!(rules(&app).await.len(), 1);
    let url = format!("/match-rules/{other}");
    assert_eq!(
        api(&app, ADMIN, Method::GET, &url, None).await.0,
        StatusCode::NOT_FOUND
    );
    let body = rule_body(json!({ "baseline_type_code": "clock_dial",
        "baseline_attribute_key": "dial_diameter_mm", "product_attribute_key": "dial_size_mm",
        "operator": "within_range" }));
    assert_eq!(
        api(&app, ADMIN, Method::PUT, &url, Some(body)).await.0,
        StatusCode::NOT_FOUND
    );
    assert_eq!(
        api(&app, ADMIN, Method::DELETE, &url, None).await.0,
        StatusCode::NOT_FOUND
    );
    let n: i64 =
        sqlx::query_scalar("SELECT count(*) FROM crm.match_rules WHERE company_id = $1::uuid")
            .bind(OTHER_COMPANY)
            .fetch_one(&db)
            .await
            .unwrap();
    assert_eq!(n, 1, "untouched");
}

// ---------------------------------------------------------------------------------------------
// Matching
// ---------------------------------------------------------------------------------------------

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn another_companys_opportunity_and_unknown_ids_are_404(db: PgPool) {
    let app = seeded(&db).await;
    sqlx::query("INSERT INTO core.companies (id, name) VALUES ($1::uuid, 'Other BV')")
        .bind(OTHER_COMPANY)
        .execute(&db)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO crm.opportunities (id, company_id, number, title, customer_id, owner_user_id)
         VALUES ($1::uuid, $2::uuid, 'X-1', 'Theirs', $3::uuid, '00000000-0000-7000-8000-000000000101')",
    )
    .bind(OTHER_OPP)
    .bind(OTHER_COMPANY)
    .bind(BETA)
    .execute(&db)
    .await
    .unwrap();
    for id in [OTHER_OPP, "00000000-0000-7000-8000-0000000000ff"] {
        let (status, r) = api(
            &app,
            ADMIN,
            Method::GET,
            &format!("/opportunities/{id}/product-matches"),
            None,
        )
        .await;
        assert_eq!(status, StatusCode::NOT_FOUND, "{id} {r}");
    }
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_bad_filter_is_a_422_and_the_viewer_may_read(db: PgPool) {
    let app = seeded(&db).await;
    let uri = format!("/opportunities/{OPP}/product-matches?status=maybe");
    assert_eq!(
        api(&app, SALES, Method::GET, &uri, None).await.0,
        StatusCode::UNPROCESSABLE_ENTITY
    );
    let uri = format!("/opportunities/{OPP}/product-matches");
    assert_eq!(
        api(&app, VIEWER, Method::GET, &uri, None).await.0,
        StatusCode::OK
    );
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn an_empty_baseline_without_a_grid_leaves_every_product_unknown(db: PgPool) {
    let app = seeded(&db).await;
    let m = matches(&app, OPP2, "limit=500").await;
    let items = m["items"].as_array().unwrap();
    assert!(!items.is_empty());
    for p in items {
        assert_eq!(p["status"], "unknown", "{p}");
        assert_eq!(
            reasons(p),
            [(
                "baseline".into(),
                "unknown".into(),
                "no baseline data".into()
            )]
        );
    }
    assert_eq!(m["counts"]["unknown"], m["total"]);
    assert_eq!(m["counts"]["suitable"], 0);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn full_scenario_grid_two_dials_and_products(db: PgPool) {
    let app = seeded(&db).await;
    let be3 = grid_id(&app, "BE", 400, 3).await;
    set_grid(&app, OPP, &be3).await;
    add_item(
        &app,
        OPP,
        json!({ "type_code": "clock_dial", "name": "south",
        "values": { "dial_diameter_mm": 800 } }),
    )
    .await;
    add_item(
        &app,
        OPP,
        json!({ "type_code": "clock_dial", "name": "east",
        "values": { "dial_diameter_mm": 1400 } }),
    )
    .await;

    dial_size(&app, UNIT_100, "600", "1500").await; // 3x400V: fits both dials
    dial_size(&app, PUMP, "600", "1500").await; // 230V 1-phase: wrong grid
    dial_size(&app, BOLT, "600", "1000").await; // no supplies: 1400 does not fit
    dial_size(&app, UNIT_200, "800", "1400").await; // bounds are inclusive, but 120V 60Hz
    let m = matches(&app, OPP, "limit=500").await;

    let ok = of(&m, UNIT_100);
    assert_eq!(ok["status"], "suitable");
    assert_eq!(
        reasons(ok),
        [
            (
                "power".to_string(),
                "ok".to_string(),
                "runs on the power grid of the site".to_string()
            ),
            (
                format!("rule:{RULE_NAME}"),
                "ok".into(),
                "clock_dial \"south\": dial_diameter_mm 800 is within dial_size_mm 600..1500"
                    .into()
            ),
            (
                format!("rule:{RULE_NAME}"),
                "ok".into(),
                "clock_dial \"east\": dial_diameter_mm 1400 is within dial_size_mm 600..1500"
                    .into()
            ),
        ]
    );
    assert!(ok["code"].is_string() && ok["name"].is_string());

    let pump = of(&m, PUMP);
    assert_eq!(pump["status"], "unsuitable");
    let r = reasons(pump);
    assert_eq!((r[0].0.as_str(), r[0].1.as_str()), ("power", "fail"));
    assert!(
        r[0].2.contains("230V") && r[0].2.contains("400V 3-phase 50Hz"),
        "{}",
        r[0].2
    );
    assert_eq!(r[1].1, "ok");
    assert_eq!(r[2].1, "ok");

    let bolt = of(&m, BOLT);
    assert_eq!(bolt["status"], "unsuitable");
    assert_eq!(
        reasons(bolt),
        [
            (
                format!("rule:{RULE_NAME}"),
                "ok".to_string(),
                "clock_dial \"south\": dial_diameter_mm 800 is within dial_size_mm 600..1000"
                    .to_string()
            ),
            (
                format!("rule:{RULE_NAME}"),
                "fail".into(),
                "clock_dial \"east\": dial_diameter_mm 1400 is outside dial_size_mm 600..1000"
                    .into()
            ),
        ]
    );

    let u200 = of(&m, UNIT_200);
    assert_eq!(u200["status"], "unsuitable");
    assert_eq!(reasons(u200)[0].1, "fail");
    assert_eq!(reasons(u200)[1].1, "ok", "800 is on the lower bound");
    assert_eq!(reasons(u200)[2].1, "ok", "1400 is on the upper bound");

    // A DC product without a dial size: only the external supply note, still suitable.
    let ctrl = of(&m, CTRL);
    assert_eq!(ctrl["status"], "suitable");
    assert_eq!(
        reasons(ctrl),
        [(
            "power".to_string(),
            "ok".to_string(),
            "needs an external power supply".to_string()
        )]
    );

    // counts agree with the list; filters
    let all = m["items"].as_array().unwrap();
    for s in ["suitable", "unsuitable", "unknown"] {
        let n = all.iter().filter(|p| p["status"] == s).count();
        assert_eq!(m["counts"][s], n, "{s}");
    }
    assert_eq!(m["total"], all.len());
    let only = matches(&app, OPP, "status=unsuitable&limit=500").await;
    let ids: Vec<&str> = only["items"]
        .as_array()
        .unwrap()
        .iter()
        .map(|p| p["id"].as_str().unwrap())
        .collect();
    assert!(ids.contains(&PUMP) && ids.contains(&BOLT) && ids.contains(&UNIT_200));
    assert!(!ids.contains(&UNIT_100));
    assert_eq!(only["total"], ids.len());
    assert_eq!(
        only["counts"], m["counts"],
        "counts ignore the status filter"
    );

    // paging keeps order and total
    let page = matches(&app, OPP, "limit=2&offset=1").await;
    assert_eq!(page["items"].as_array().unwrap().len(), 2);
    assert_eq!(page["total"], m["total"]);
    assert_eq!(page["items"][0]["id"], all[1]["id"]);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn missing_data_is_unknown_and_inactive_products_and_rules_are_left_out(db: PgPool) {
    let app = seeded(&db).await;
    // A dial without a size; no grid. The product with a dial size range cannot be judged.
    add_item(
        &app,
        OPP,
        json!({ "type_code": "clock_dial", "values": {} }),
    )
    .await;
    dial_size(&app, BOLT, "600", "1000").await;
    let m = matches(&app, OPP, "limit=500").await;
    let bolt = of(&m, BOLT);
    assert_eq!(bolt["status"], "unknown");
    assert_eq!(
        reasons(bolt)[0].2,
        "clock_dial: no dial_diameter_mm recorded, the fit with dial_size_mm 600..1000 is unknown"
    );
    // An electrical product without a grid on the opportunity is unknown too.
    let unit = of(&m, UNIT_100);
    assert_eq!(unit["status"], "unknown");
    assert_eq!(reasons(unit)[0].0, "power");
    // Deactivating a product removes it; deactivating the rule removes its reasons.
    sqlx::query("UPDATE products.products SET active = false WHERE id = $1::uuid")
        .bind(BOLT)
        .execute(&db)
        .await
        .unwrap();
    let m = matches(&app, OPP, "limit=500").await;
    assert!(m["items"]
        .as_array()
        .unwrap()
        .iter()
        .all(|p| p["id"] != BOLT));
    sqlx::query("UPDATE products.products SET active = true WHERE id = $1::uuid")
        .bind(BOLT)
        .execute(&db)
        .await
        .unwrap();
    sqlx::query("UPDATE crm.match_rules SET active = false")
        .execute(&db)
        .await
        .unwrap();
    let m = matches(&app, OPP, "limit=500").await;
    let bolt = of(&m, BOLT);
    assert_eq!(bolt["status"], "suitable");
    assert!(bolt["reasons"].as_array().unwrap().is_empty());
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn items_nested_in_groups_count_and_the_family_filter_works(db: PgPool) {
    let app = seeded(&db).await;
    define_product_number(&app, "max_bell_kg").await;
    let (status, _) = api(
        &app,
        ADMIN,
        Method::POST,
        "/match-rules",
        Some(rule_body(json!({}))),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);
    let group = add_item(&app, OPP, json!({ "type_code": "bell_group" })).await;
    add_item(
        &app,
        OPP,
        json!({ "type_code": "bell", "parent_id": group,
        "values": { "weight_kg": 250 } }),
    )
    .await;
    add_item(
        &app,
        OPP,
        json!({ "type_code": "bell", "parent_id": group,
        "values": { "weight_kg": 900 } }),
    )
    .await;
    for (product, kg) in [(UNIT_100, "1000"), (PUMP, "500")] {
        let (status, r) = api(
            &app,
            ADMIN,
            Method::PUT,
            &format!("/products/{product}/attributes"),
            Some(json!([{ "key": "max_bell_kg", "kind": "number", "value": kg }])),
        )
        .await;
        assert_eq!(status, StatusCode::OK, "{r}");
    }
    let m = matches(&app, OPP, "limit=500").await;
    let fits = of(&m, UNIT_100);
    assert!(reasons(fits).iter().all(|r| r.1 != "fail"), "{fits}");
    assert!(reasons(fits)
        .iter()
        .any(|r| r.2 == "bell: weight_kg 900 is within the maximum max_bell_kg 1000"));
    let heavy = of(&m, PUMP);
    assert_eq!(heavy["status"], "unsuitable");
    assert!(reasons(heavy)
        .iter()
        .any(|r| r.0 == "rule:Bell weight fits product"
            && r.1 == "fail"
            && r.2 == "bell: weight_kg 900 is above the maximum max_bell_kg 500"));

    // Family filter: only products of that family.
    let family: Option<String> =
        sqlx::query_scalar("SELECT family_id::text FROM products.products WHERE id = $1::uuid")
            .bind(UNIT_100)
            .fetch_one(&db)
            .await
            .unwrap();
    let family = family.expect("the seeded unit has a family");
    let f = matches(&app, OPP, &format!("family_id={family}&limit=500")).await;
    assert!(f["total"].as_i64().unwrap() >= 1);
    assert!(f["total"].as_i64().unwrap() < m["total"].as_i64().unwrap());
    assert!(f["items"]
        .as_array()
        .unwrap()
        .iter()
        .all(|p| p["family_id"] == family.as_str()));
    assert!(f["items"]
        .as_array()
        .unwrap()
        .iter()
        .any(|p| p["id"] == UNIT_100));
}
