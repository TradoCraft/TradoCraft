//! Site baseline on opportunities (ADR 0068): item types, the item tree, value validation, delete
//! rules, the opportunity power grid, seed data, permissions and company isolation.

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
const GAMMA: &str = "00000000-0000-7000-8000-000000000403"; // DE
const OTHER_COMPANY: &str = "00000000-0000-7000-8000-0000000fff01";
const OTHER_OPP: &str = "00000000-0000-7000-8000-0000000fff02";

async fn api(
    app: &axum::Router,
    user: &str,
    method: Method,
    uri: &str,
    body: Option<Value>,
) -> (StatusCode, Value) {
    call(app, user, method, &format!("/api/v1{uri}"), body).await
}

/// The app with the dev data and the baseline defaults of the dev company.
async fn seeded(db: &PgPool) -> axum::Router {
    let app = setup(db.clone()).await;
    sqlx::query("SELECT crm.seed_baseline_defaults($1::uuid)")
        .bind(COMPANY)
        .execute(db)
        .await
        .unwrap();
    app
}

async fn add(app: &axum::Router, opp: &str, body: Value) -> (StatusCode, Value) {
    api(
        app,
        SALES,
        Method::POST,
        &format!("/opportunities/{opp}/baseline/items"),
        Some(body),
    )
    .await
}

async fn add_ok(app: &axum::Router, opp: &str, body: Value) -> String {
    let (status, r) = add(app, opp, body).await;
    assert_eq!(status, StatusCode::CREATED, "{r}");
    r["id"].as_str().unwrap().to_string()
}

async fn tree(app: &axum::Router, opp: &str) -> Value {
    let (status, t) = api(
        app,
        SALES,
        Method::GET,
        &format!("/opportunities/{opp}/baseline"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{t}");
    t
}

fn item_url(opp: &str, id: &str) -> String {
    format!("/opportunities/{opp}/baseline/items/{id}")
}

async fn type_id(app: &axum::Router, code: &str) -> String {
    let (_, list) = api(app, ADMIN, Method::GET, "/baseline-item-types", None).await;
    list.as_array()
        .unwrap()
        .iter()
        .find(|t| t["code"] == code)
        .unwrap_or_else(|| panic!("no type {code}"))["id"]
        .as_str()
        .unwrap()
        .to_string()
}

async fn definition_id(app: &axum::Router, key: &str) -> String {
    let (_, list) = api(app, ADMIN, Method::GET, "/attribute-definitions", None).await;
    list.as_array()
        .unwrap()
        .iter()
        .find(|d| d["key"] == key)
        .unwrap_or_else(|| panic!("no definition {key}"))["id"]
        .as_str()
        .unwrap()
        .to_string()
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

async fn count(db: &PgPool, sql: &str) -> i64 {
    sqlx::query_scalar(sql).fetch_one(db).await.unwrap()
}

// ---------------------------------------------------------------------------------------------
// Seed data
// ---------------------------------------------------------------------------------------------

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn seed_creates_the_tower_setup_and_is_idempotent(db: PgPool) {
    let app = seeded(&db).await;
    // Running it again (as a second migration run or a re-provision would) changes nothing.
    sqlx::query("SELECT crm.seed_baseline_defaults($1::uuid)")
        .bind(COMPANY)
        .execute(&db)
        .await
        .unwrap();
    let (status, types) = api(&app, SALES, Method::GET, "/baseline-item-types", None).await;
    assert_eq!(status, StatusCode::OK, "{types}");
    let codes: Vec<&str> = types
        .as_array()
        .unwrap()
        .iter()
        .map(|t| t["code"].as_str().unwrap())
        .collect();
    assert_eq!(codes, ["clock_dial", "bell_group", "bell"]);
    let bell = &types[2];
    assert_eq!(bell["allowed_parent_codes"], json!(["bell_group"]));
    assert_eq!(bell["allow_top_level"], true);
    assert_eq!(types[0]["allowed_parent_codes"], json!([]));

    let (_, defs) = api(&app, ADMIN, Method::GET, "/attribute-definitions", None).await;
    let by = |scope: &str| -> Vec<String> {
        defs.as_array()
            .unwrap()
            .iter()
            .filter(|d| d["scope"] == scope)
            .map(|d| d["key"].as_str().unwrap().to_string())
            .collect()
    };
    assert_eq!(by("clock_dial"), ["dial_diameter_mm"]);
    assert_eq!(
        by("bell"),
        [
            "weight_kg",
            "diameter_mm",
            "height_mm",
            "motion",
            "note",
            "num_wheels",
            "motor_brand"
        ]
    );
    assert_eq!(by("product"), ["dial_size_mm", "motor_kw"]);
    let motion = defs
        .as_array()
        .unwrap()
        .iter()
        .find(|d| d["key"] == "motion")
        .unwrap();
    let options: Vec<&str> = motion["options"]
        .as_array()
        .unwrap()
        .iter()
        .map(|o| o["value"].as_str().unwrap())
        .collect();
    assert_eq!(
        options,
        [
            "flying",
            "falling",
            "balanced",
            "volteo",
            "ambrosiano",
            "veronese",
            "synchro_falling",
            "synchro_flying"
        ]
    );
    let dial = defs
        .as_array()
        .unwrap()
        .iter()
        .find(|d| d["key"] == "dial_size_mm")
        .unwrap();
    assert_eq!(
        (dial["kind"].as_str(), dial["unit"].as_str()),
        (Some("range"), Some("mm"))
    );
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn seed_keeps_what_an_admin_already_changed(db: PgPool) {
    let app = seeded(&db).await;
    let id = type_id(&app, "bell").await;
    let (status, _) = api(
        &app,
        ADMIN,
        Method::PUT,
        &format!("/baseline-item-types/{id}"),
        Some(json!({ "name": "Church bell", "allowed_parent_codes": [], "allow_top_level": true })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    sqlx::query("SELECT crm.seed_baseline_defaults($1::uuid)")
        .bind(COMPANY)
        .execute(&db)
        .await
        .unwrap();
    let name: String =
        sqlx::query_scalar("SELECT name FROM crm.baseline_item_types WHERE code = 'bell'")
            .fetch_one(&db)
            .await
            .unwrap();
    assert_eq!(name, "Church bell");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_provisioned_company_gets_the_defaults(db: PgPool) {
    let _app = setup(db.clone()).await;
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
    let n: i64 =
        sqlx::query_scalar("SELECT count(*) FROM crm.baseline_item_types WHERE company_id = $1")
            .bind(p.company.id)
            .fetch_one(&db)
            .await
            .unwrap();
    assert_eq!(n, 3);
    let d: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM products.attribute_definitions WHERE company_id = $1",
    )
    .bind(p.company.id)
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(d, 10);
}

// ---------------------------------------------------------------------------------------------
// Item types
// ---------------------------------------------------------------------------------------------

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn type_crud_validation_and_audit(db: PgPool) {
    let app = seeded(&db).await;
    let (status, t) = api(
        &app,
        ADMIN,
        Method::POST,
        "/baseline-item-types",
        Some(json!({ "code": "chime", "name": " Chime ", "allowed_parent_codes": ["bell_group"], "allow_top_level": false, "sort_order": 9 })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{t}");
    assert_eq!(t["name"], "Chime");
    assert_eq!(t["allow_top_level"], false);
    assert_eq!(t["active"], true);
    let id = t["id"].as_str().unwrap().to_string();

    // Defaults: top level only.
    let (status, d) = api(
        &app,
        ADMIN,
        Method::POST,
        "/baseline-item-types",
        Some(json!({ "code": "clapper", "name": "Clapper" })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{d}");
    assert_eq!(d["allowed_parent_codes"], json!([]));
    assert_eq!(d["allow_top_level"], true);

    // Duplicate code 409; bad code, blank name, unknown parent code, no place at all: 422.
    let post = |body: Value| {
        api(
            &app,
            ADMIN,
            Method::POST,
            "/baseline-item-types",
            Some(body),
        )
    };
    assert_eq!(
        post(json!({ "code": "chime", "name": "x" })).await.0,
        StatusCode::CONFLICT
    );
    for body in [
        json!({ "code": "Chime2", "name": "x" }),
        json!({ "code": "1chime", "name": "x" }),
        json!({ "code": "ok_code", "name": " " }),
        json!({ "code": "ok_code", "name": "x", "allowed_parent_codes": ["nope"] }),
        json!({ "code": "ok_code", "name": "x", "allowed_parent_codes": [], "allow_top_level": false }),
    ] {
        let (status, r) = post(body.clone()).await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{body} {r}");
    }
    // A type may allow itself as parent (nesting of the same kind).
    let (status, r) = post(
        json!({ "code": "assembly", "name": "Assembly", "allowed_parent_codes": ["assembly"] }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{r}");

    // Update: the code is fixed, the rest changes.
    let (status, u) = api(
        &app,
        ADMIN,
        Method::PUT,
        &format!("/baseline-item-types/{id}"),
        Some(json!({ "name": "Chime set", "allowed_parent_codes": [], "allow_top_level": true, "active": false })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{u}");
    assert_eq!(u["code"], "chime");
    assert_eq!(u["name"], "Chime set");
    assert_eq!(u["active"], false);
    let (status, g) = api(
        &app,
        SALES,
        Method::GET,
        &format!("/baseline-item-types/{id}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{g}");
    let (status, _) = api(
        &app,
        ADMIN,
        Method::PUT,
        &format!("/baseline-item-types/{id}"),
        Some(json!({ "name": "x", "allowed_parent_codes": ["nope"] })),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    let (status, _) = api(
        &app,
        ADMIN,
        Method::DELETE,
        &format!("/baseline-item-types/{id}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    let (status, _) = api(
        &app,
        ADMIN,
        Method::GET,
        &format!("/baseline-item-types/{id}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let n = count(
        &db,
        &format!("SELECT count(*) FROM audit.events WHERE entity = 'baseline_item_type' AND entity_id = '{id}'"),
    )
    .await;
    assert_eq!(n, 3, "created, updated, deleted");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn type_admin_needs_product_write_but_reading_needs_opportunity_read(db: PgPool) {
    let app = seeded(&db).await;
    let body = json!({ "code": "chime", "name": "Chime" });
    let (status, _) = api(
        &app,
        SALES,
        Method::POST,
        "/baseline-item-types",
        Some(body.clone()),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let id = type_id(&app, "bell").await;
    let (status, _) = api(
        &app,
        SALES,
        Method::PUT,
        &format!("/baseline-item-types/{id}"),
        Some(json!({ "name": "x" })),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, _) = api(
        &app,
        SALES,
        Method::DELETE,
        &format!("/baseline-item-types/{id}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, _) = api(&app, SALES, Method::GET, "/baseline-item-types", None).await;
    assert_eq!(status, StatusCode::OK);
    let (status, _) = api(
        &app,
        ADMIN,
        Method::POST,
        "/baseline-item-types",
        Some(body),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn deleting_a_type_that_is_referenced_is_refused(db: PgPool) {
    let app = seeded(&db).await;
    let del = |id: String| {
        let app = app.clone();
        async move {
            api(
                &app,
                ADMIN,
                Method::DELETE,
                &format!("/baseline-item-types/{id}"),
                None,
            )
            .await
        }
    };
    // Referenced as an allowed parent by bell.
    let group = type_id(&app, "bell_group").await;
    let (status, r) = del(group.clone()).await;
    assert_eq!(status, StatusCode::CONFLICT, "{r}");
    assert!(r.to_string().contains("deactivate"), "{r}");

    // Has attribute definitions (seeded) but no items.
    let dial = type_id(&app, "clock_dial").await;
    let (status, r) = del(dial.clone()).await;
    assert_eq!(status, StatusCode::CONFLICT, "{r}");

    // Without definitions but with items.
    let (_, t) = api(
        &app,
        ADMIN,
        Method::POST,
        "/baseline-item-types",
        Some(json!({ "code": "chime", "name": "Chime" })),
    )
    .await;
    let chime = t["id"].as_str().unwrap().to_string();
    add_ok(&app, OPP, json!({ "type_code": "chime" })).await;
    let (status, r) = del(chime).await;
    assert_eq!(status, StatusCode::CONFLICT, "{r}");

    // Nothing references it: deleted.
    let (_, t) = api(
        &app,
        ADMIN,
        Method::POST,
        "/baseline-item-types",
        Some(json!({ "code": "spare", "name": "Spare" })),
    )
    .await;
    let (status, _) = del(t["id"].as_str().unwrap().to_string()).await;
    assert_eq!(status, StatusCode::NO_CONTENT);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_type_update_cannot_strand_existing_items(db: PgPool) {
    let app = seeded(&db).await;
    let group = add_ok(&app, OPP, json!({ "type_code": "bell_group" })).await;
    add_ok(
        &app,
        OPP,
        json!({ "type_code": "bell", "parent_id": group }),
    )
    .await;
    let bell = type_id(&app, "bell").await;
    let (status, r) = api(
        &app,
        ADMIN,
        Method::PUT,
        &format!("/baseline-item-types/{bell}"),
        Some(json!({ "name": "Bell", "allowed_parent_codes": [], "allow_top_level": true })),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT, "{r}");
    // Making it more permissive is fine.
    let (status, _) = api(
        &app,
        ADMIN,
        Method::PUT,
        &format!("/baseline-item-types/{bell}"),
        Some(json!({ "name": "Bell", "allowed_parent_codes": ["bell_group", "clock_dial"], "allow_top_level": true })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn types_of_another_company_are_invisible(db: PgPool) {
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
    let other_bell: String = sqlx::query_scalar(
        "SELECT id::text FROM crm.baseline_item_types WHERE company_id = $1::uuid AND code = 'bell'",
    )
    .bind(OTHER_COMPANY)
    .fetch_one(&db)
    .await
    .unwrap();
    let (_, list) = api(&app, ADMIN, Method::GET, "/baseline-item-types", None).await;
    assert_eq!(list.as_array().unwrap().len(), 3);
    let url = format!("/baseline-item-types/{other_bell}");
    assert_eq!(
        api(&app, ADMIN, Method::GET, &url, None).await.0,
        StatusCode::NOT_FOUND
    );
    assert_eq!(
        api(
            &app,
            ADMIN,
            Method::PUT,
            &url,
            Some(json!({ "name": "Mine" }))
        )
        .await
        .0,
        StatusCode::NOT_FOUND
    );
    assert_eq!(
        api(&app, ADMIN, Method::DELETE, &url, None).await.0,
        StatusCode::NOT_FOUND
    );
}

// ---------------------------------------------------------------------------------------------
// The item tree
// ---------------------------------------------------------------------------------------------

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_baseline_is_returned_as_a_nested_tree(db: PgPool) {
    let app = seeded(&db).await;
    assert_eq!(tree(&app, OPP).await, json!([]));
    let (status, dial) = add(
        &app,
        OPP,
        json!({ "type_code": "clock_dial", "values": { "dial_diameter_mm": 1250 }, "sort_order": 2 }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{dial}");
    assert_eq!(dial["quantity"], 1);
    assert!(dial["parent_id"].is_null());
    assert!(dial["name"].is_null());
    let group = add_ok(
        &app,
        OPP,
        json!({ "type_code": "bell_group", "name": "Carillon", "sort_order": 1 }),
    )
    .await;
    add_ok(&app, OPP, json!({ "type_code": "bell", "parent_id": group, "name": "Maria", "quantity": 2,
        "values": { "weight_kg": 450, "motion": "flying", "note": " c ", "diameter_mm": 900 }, "sort_order": 2 })).await;
    add_ok(
        &app,
        OPP,
        json!({ "type_code": "bell", "parent_id": group, "name": "Anna", "sort_order": 1 }),
    )
    .await;
    // A bell may also stand alone.
    add_ok(
        &app,
        OPP,
        json!({ "type_code": "bell", "name": "Solo", "sort_order": 3 }),
    )
    .await;
    // Another opportunity is unaffected.
    assert_eq!(tree(&app, OPP2).await, json!([]));

    let t = tree(&app, OPP).await;
    let top: Vec<&str> = t
        .as_array()
        .unwrap()
        .iter()
        .map(|i| i["type_code"].as_str().unwrap())
        .collect();
    assert_eq!(
        top,
        ["bell_group", "clock_dial", "bell"],
        "ordered by sort_order"
    );
    let kids: Vec<&str> = t[0]["children"]
        .as_array()
        .unwrap()
        .iter()
        .map(|i| i["name"].as_str().unwrap())
        .collect();
    assert_eq!(kids, ["Anna", "Maria"]);
    let maria = &t[0]["children"][1];
    assert_eq!(maria["quantity"], 2);
    assert_eq!(
        maria["values"],
        json!({ "weight_kg": 450, "motion": "flying", "note": "c", "diameter_mm": 900 })
    );
    assert_eq!(t[1]["children"], json!([]));
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn parent_type_and_placement_rules_are_enforced(db: PgPool) {
    let app = seeded(&db).await;
    let dial = add_ok(&app, OPP, json!({ "type_code": "clock_dial" })).await;
    let group = add_ok(&app, OPP, json!({ "type_code": "bell_group" })).await;
    let other_opp_group = add_ok(&app, OPP2, json!({ "type_code": "bell_group" })).await;

    for (label, body) in [
        (
            "bell under a dial",
            json!({ "type_code": "bell", "parent_id": dial }),
        ),
        (
            "dial under a group",
            json!({ "type_code": "clock_dial", "parent_id": group }),
        ),
        (
            "group under a group",
            json!({ "type_code": "bell_group", "parent_id": group }),
        ),
        (
            "parent of another opportunity",
            json!({ "type_code": "bell", "parent_id": other_opp_group }),
        ),
        (
            "unknown parent",
            json!({ "type_code": "bell", "parent_id": "00000000-0000-7000-8000-0000000000ff" }),
        ),
        ("unknown type", json!({ "type_code": "gargoyle" })),
    ] {
        let (status, r) = add(&app, OPP, body).await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{label}: {r}");
    }

    // A type that must be nested cannot be top level.
    let (status, _) = api(&app, ADMIN, Method::POST, "/baseline-item-types",
        Some(json!({ "code": "clapper", "name": "Clapper", "allowed_parent_codes": ["bell"], "allow_top_level": false }))).await;
    assert_eq!(status, StatusCode::CREATED);
    let (status, r) = add(&app, OPP, json!({ "type_code": "clapper" })).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{r}");

    // Inactive types take no new items.
    let id = type_id(&app, "clock_dial").await;
    api(
        &app,
        ADMIN,
        Method::PUT,
        &format!("/baseline-item-types/{id}"),
        Some(json!({ "name": "Clock dial", "active": false })),
    )
    .await;
    let (status, r) = add(&app, OPP, json!({ "type_code": "clock_dial" })).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{r}");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn moving_items_rejects_cycles_and_wrong_parent_types(db: PgPool) {
    let app = seeded(&db).await;
    api(
        &app,
        ADMIN,
        Method::POST,
        "/baseline-item-types",
        Some(
            json!({ "code": "assembly", "name": "Assembly", "allowed_parent_codes": ["assembly"] }),
        ),
    )
    .await;
    let a = add_ok(&app, OPP, json!({ "type_code": "assembly", "name": "a" })).await;
    let b = add_ok(
        &app,
        OPP,
        json!({ "type_code": "assembly", "name": "b", "parent_id": a }),
    )
    .await;
    let c = add_ok(
        &app,
        OPP,
        json!({ "type_code": "assembly", "name": "c", "parent_id": b }),
    )
    .await;

    let put = |id: String, parent: Option<String>| {
        let app = app.clone();
        async move {
            api(
                &app,
                SALES,
                Method::PUT,
                &item_url(OPP, &id),
                Some(json!({ "parent_id": parent, "quantity": 1 })),
            )
            .await
        }
    };
    for target in [&a, &b, &c] {
        let (status, r) = put(a.clone(), Some(target.clone())).await;
        assert_eq!(
            status,
            StatusCode::UNPROCESSABLE_ENTITY,
            "a under {target}: {r}"
        );
        assert!(r.to_string().contains("cycle"), "{r}");
    }
    // Moving c to the top level and b under c is fine (no cycle left).
    let (status, r) = put(c.clone(), None).await;
    assert_eq!(status, StatusCode::OK, "{r}");
    let (status, r) = put(b.clone(), Some(c.clone())).await;
    assert_eq!(status, StatusCode::OK, "{r}");
    assert_eq!(r["parent_id"], c.as_str());

    // A bell cannot be moved under a dial.
    let dial = add_ok(&app, OPP, json!({ "type_code": "clock_dial" })).await;
    let bell = add_ok(&app, OPP, json!({ "type_code": "bell" })).await;
    let (status, r) = put(bell.clone(), Some(dial)).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{r}");
    // The failed moves changed nothing.
    let n = count(&db, &format!("SELECT count(*) FROM crm.opportunity_baseline_items WHERE id = '{bell}' AND parent_id IS NULL")).await;
    assert_eq!(n, 1);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_database_refuses_a_parent_from_another_opportunity(db: PgPool) {
    let app = seeded(&db).await;
    let g = add_ok(&app, OPP2, json!({ "type_code": "bell_group" })).await;
    let r = sqlx::query(
        "INSERT INTO crm.opportunity_baseline_items (id, company_id, opportunity_id, parent_id, type_code)
         VALUES (gen_random_uuid(), $1::uuid, $2::uuid, $3::uuid, 'bell')",
    )
    .bind(COMPANY)
    .bind(OPP)
    .bind(g)
    .execute(&db)
    .await;
    assert!(r.is_err(), "composite foreign key must refuse it");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn values_are_validated_against_the_type_definitions(db: PgPool) {
    let app = seeded(&db).await;
    for (label, body) in [
        (
            "number as text",
            json!({ "type_code": "bell", "values": { "weight_kg": "heavy" } }),
        ),
        (
            "unknown key",
            json!({ "type_code": "bell", "values": { "colour": "red" } }),
        ),
        (
            "key of another type",
            json!({ "type_code": "bell", "values": { "dial_diameter_mm": 1000 } }),
        ),
        (
            "product-scope key",
            json!({ "type_code": "bell", "values": { "dial_size_mm": { "min": 1, "max": 2 } } }),
        ),
        (
            "bad select",
            json!({ "type_code": "bell", "values": { "motion": "hovering" } }),
        ),
        (
            "note not text",
            json!({ "type_code": "bell", "values": { "note": 5 } }),
        ),
        (
            "values not an object",
            json!({ "type_code": "bell", "values": [1] }),
        ),
        (
            "quantity zero",
            json!({ "type_code": "bell", "quantity": 0 }),
        ),
        (
            "quantity negative",
            json!({ "type_code": "bell", "quantity": -1 }),
        ),
    ] {
        let (status, r) = add(&app, OPP, body).await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{label}: {r}");
    }
    assert_eq!(
        count(&db, "SELECT count(*) FROM crm.opportunity_baseline_items").await,
        0
    );

    // Incomplete data is fine; null clears.
    let id = add_ok(
        &app,
        OPP,
        json!({ "type_code": "bell", "values": { "weight_kg": 300 } }),
    )
    .await;
    let (status, u) = api(&app, SALES, Method::PUT, &item_url(OPP, &id),
        Some(json!({ "quantity": 3, "name": "  Big  ", "values": { "motion": "volteo", "weight_kg": null } }))).await;
    assert_eq!(status, StatusCode::OK, "{u}");
    assert_eq!(u["values"], json!({ "motion": "volteo" }));
    assert_eq!(u["name"], "Big");
    assert_eq!(u["quantity"], 3);
    let (status, r) = api(
        &app,
        SALES,
        Method::PUT,
        &item_url(OPP, &id),
        Some(json!({ "quantity": 1, "values": { "motion": "nope" } })),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{r}");

    // Range values come from an admin-defined range attribute.
    api(
        &app,
        ADMIN,
        Method::POST,
        "/attribute-definitions",
        Some(json!({ "key": "pitch_range", "label": "Pitch", "kind": "range", "scope": "bell" })),
    )
    .await;
    let (status, r) = add(
        &app,
        OPP,
        json!({ "type_code": "bell", "values": { "pitch_range": { "min": 9, "max": 3 } } }),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{r}");
    let (status, r) = add(
        &app,
        OPP,
        json!({ "type_code": "bell", "values": { "pitch_range": { "min": 3, "max": 9 } } }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{r}");

    // An inactive definition no longer accepts values.
    let def = definition_id(&app, "note").await;
    api(&app, ADMIN, Method::PUT, &format!("/attribute-definitions/{def}"),
        Some(json!({ "key": "note", "label": "Note", "kind": "text", "scope": "bell", "active": false }))).await;
    let (status, r) = add(
        &app,
        OPP,
        json!({ "type_code": "bell", "values": { "note": "c" } }),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{r}");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn an_item_with_children_cannot_be_deleted(db: PgPool) {
    let app = seeded(&db).await;
    let group = add_ok(&app, OPP, json!({ "type_code": "bell_group" })).await;
    let bell = add_ok(
        &app,
        OPP,
        json!({ "type_code": "bell", "parent_id": group }),
    )
    .await;
    let (status, r) = api(&app, SALES, Method::DELETE, &item_url(OPP, &group), None).await;
    assert_eq!(status, StatusCode::CONFLICT, "{r}");
    assert_eq!(
        count(&db, "SELECT count(*) FROM crm.opportunity_baseline_items").await,
        2
    );
    let (status, _) = api(&app, SALES, Method::DELETE, &item_url(OPP, &bell), None).await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    let (status, _) = api(&app, SALES, Method::DELETE, &item_url(OPP, &group), None).await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    // Gone, and a second delete is a 404; a wrong opportunity in the path is a 404 too.
    let (status, _) = api(&app, SALES, Method::DELETE, &item_url(OPP, &group), None).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let kept = add_ok(&app, OPP, json!({ "type_code": "clock_dial" })).await;
    let (status, _) = api(&app, SALES, Method::DELETE, &item_url(OPP2, &kept), None).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, _) = api(
        &app,
        SALES,
        Method::PUT,
        &item_url(OPP2, &kept),
        Some(json!({ "quantity": 1 })),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let n = count(
        &db,
        "SELECT count(*) FROM audit.events WHERE entity = 'baseline_item' AND action = 'deleted'",
    )
    .await;
    assert_eq!(n, 2, "the refused delete of the group is not audited");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn baseline_changes_are_audited(db: PgPool) {
    let app = seeded(&db).await;
    let id = add_ok(&app, OPP, json!({ "type_code": "bell" })).await;
    api(
        &app,
        SALES,
        Method::PUT,
        &item_url(OPP, &id),
        Some(json!({ "quantity": 2 })),
    )
    .await;
    api(&app, SALES, Method::DELETE, &item_url(OPP, &id), None).await;
    let actions: Vec<String> = sqlx::query_scalar(
        "SELECT action FROM audit.events WHERE entity = 'baseline_item' AND entity_id = $1::uuid ORDER BY id",
    )
    .bind(&id)
    .fetch_all(&db)
    .await
    .unwrap();
    assert_eq!(actions, ["created", "updated", "deleted"]);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn baseline_of_another_companys_opportunity_is_a_404(db: PgPool) {
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
    let other_item = "00000000-0000-7000-8000-0000000fff03";
    sqlx::query(
        "INSERT INTO crm.opportunity_baseline_items (id, company_id, opportunity_id, type_code)
         VALUES ($1::uuid, $2::uuid, $3::uuid, 'bell')",
    )
    .bind(other_item)
    .bind(OTHER_COMPANY)
    .bind(OTHER_OPP)
    .execute(&db)
    .await
    .unwrap();

    let base = format!("/opportunities/{OTHER_OPP}/baseline");
    assert_eq!(
        api(&app, ADMIN, Method::GET, &base, None).await.0,
        StatusCode::NOT_FOUND
    );
    assert_eq!(
        add(&app, OTHER_OPP, json!({ "type_code": "bell" })).await.0,
        StatusCode::NOT_FOUND
    );
    let url = item_url(OTHER_OPP, other_item);
    assert_eq!(
        api(
            &app,
            ADMIN,
            Method::PUT,
            &url,
            Some(json!({ "quantity": 5 }))
        )
        .await
        .0,
        StatusCode::NOT_FOUND
    );
    assert_eq!(
        api(&app, ADMIN, Method::DELETE, &url, None).await.0,
        StatusCode::NOT_FOUND
    );
    // Even through one of our own opportunities' paths.
    let url = item_url(OPP, other_item);
    assert_eq!(
        api(&app, ADMIN, Method::DELETE, &url, None).await.0,
        StatusCode::NOT_FOUND
    );
    // Using the other company's item as a parent is refused.
    let (status, _) = add(
        &app,
        OPP,
        json!({ "type_code": "bell", "parent_id": other_item }),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        count(&db, "SELECT count(*) FROM crm.opportunity_baseline_items").await,
        1
    );
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn editing_needs_opportunity_write_and_reading_needs_read(db: PgPool) {
    let app = seeded(&db).await;
    let id = add_ok(&app, OPP, json!({ "type_code": "bell" })).await;
    let (status, _) = api(
        &app,
        VIEWER,
        Method::GET,
        &format!("/opportunities/{OPP}/baseline"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (status, _) = api(
        &app,
        VIEWER,
        Method::POST,
        &format!("/opportunities/{OPP}/baseline/items"),
        Some(json!({ "type_code": "bell" })),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, _) = api(
        &app,
        VIEWER,
        Method::PUT,
        &item_url(OPP, &id),
        Some(json!({ "quantity": 2 })),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, _) = api(&app, VIEWER, Method::DELETE, &item_url(OPP, &id), None).await;
    assert_eq!(status, StatusCode::FORBIDDEN);
}

// ---------------------------------------------------------------------------------------------
// Attribute definition delete rule (Phase 1 follow-up)
// ---------------------------------------------------------------------------------------------

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_baseline_definition_in_use_cannot_be_deleted(db: PgPool) {
    let app = seeded(&db).await;
    let item = add_ok(
        &app,
        OPP,
        json!({ "type_code": "bell", "values": { "weight_kg": 300 } }),
    )
    .await;
    let weight = definition_id(&app, "weight_kg").await;
    let note = definition_id(&app, "note").await;
    let url = |id: &str| format!("/attribute-definitions/{id}");

    let (status, r) = api(&app, ADMIN, Method::DELETE, &url(&weight), None).await;
    assert_eq!(status, StatusCode::CONFLICT, "{r}");
    assert!(r.to_string().contains("deactivate"), "{r}");
    // A key no item stores can go, a product-scope one is judged by products as before.
    let (status, _) = api(&app, ADMIN, Method::DELETE, &url(&note), None).await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    let dial_size = definition_id(&app, "dial_size_mm").await;
    let (status, _) = api(&app, ADMIN, Method::DELETE, &url(&dial_size), None).await;
    assert_eq!(status, StatusCode::NO_CONTENT);

    // Once the value is cleared from the item, the definition can be deleted.
    api(
        &app,
        SALES,
        Method::PUT,
        &item_url(OPP, &item),
        Some(json!({ "quantity": 1, "values": { "weight_kg": null } })),
    )
    .await;
    let (status, r) = api(&app, ADMIN, Method::DELETE, &url(&weight), None).await;
    assert_eq!(status, StatusCode::NO_CONTENT, "{r}");
}

// ---------------------------------------------------------------------------------------------
// Power grid on the opportunity
// ---------------------------------------------------------------------------------------------

fn opp_body(customer: &str, extra: Value) -> Value {
    let mut b = json!({ "title": "Tower", "customer_id": customer });
    for (k, v) in extra.as_object().unwrap() {
        b[k] = v.clone();
    }
    b
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn opportunity_power_grid_must_belong_to_the_customers_country(db: PgPool) {
    let app = setup(db).await;
    let be = grid_id(&app, "BE", 230, 1).await;
    let be3 = grid_id(&app, "BE", 400, 3).await;
    let us = grid_id(&app, "US", 120, 1).await;
    let de = grid_id(&app, "DE", 400, 3).await;
    let post = |body: Value| api(&app, SALES, Method::POST, "/opportunities", Some(body));

    // Backwards compatible: no grid at all.
    let (status, o) = post(opp_body(BETA, json!({}))).await;
    assert_eq!(status, StatusCode::CREATED, "{o}");
    assert!(o["power_grid_id"].is_null());
    let plain = o["id"].as_str().unwrap().to_string();

    // A grid of another country, and one that does not exist: 422.
    for g in [us.as_str(), "00000000-0000-7000-8000-0000000000ff"] {
        let (status, r) = post(opp_body(BETA, json!({ "power_grid_id": g }))).await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{g}: {r}");
    }
    // The customer's own country (Gamma is German; Beta is Belgian).
    let (status, o) = post(opp_body(BETA, json!({ "power_grid_id": be }))).await;
    assert_eq!(status, StatusCode::CREATED, "{o}");
    assert_eq!(o["power_grid_id"], be.as_str());
    let (status, r) = post(opp_body(GAMMA, json!({ "power_grid_id": be }))).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{r}");
    let (status, o) = post(opp_body(GAMMA, json!({ "power_grid_id": de }))).await;
    assert_eq!(status, StatusCode::CREATED, "{o}");
    // Nothing was stored for the refused ones.
    let (_, page) = api(&app, SALES, Method::GET, "/opportunities?limit=500", None).await;
    assert_eq!(page["total"], 3 + 3, "three seeded, plus the three created");

    // Update: kept when omitted, replaced by another grid of the country, cleared on request.
    let id = o["id"].as_str().unwrap().to_string();
    let put = |id: String, body: Value| {
        let app = app.clone();
        async move {
            api(
                &app,
                SALES,
                Method::PUT,
                &format!("/opportunities/{id}"),
                Some(body),
            )
            .await
        }
    };
    let (status, u) = put(id.clone(), opp_body(GAMMA, json!({ "title": "Renamed" }))).await;
    assert_eq!(status, StatusCode::OK, "{u}");
    assert_eq!(u["power_grid_id"], de.as_str(), "omitted keeps the grid");
    let (status, r) = put(id.clone(), opp_body(GAMMA, json!({ "power_grid_id": us }))).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{r}");
    let (status, r) = put(
        id.clone(),
        opp_body(
            GAMMA,
            json!({ "power_grid_id": de, "clear_power_grid": true }),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{r}");
    let (_, g) = api(
        &app,
        SALES,
        Method::GET,
        &format!("/opportunities/{id}"),
        None,
    )
    .await;
    assert_eq!(
        g["power_grid_id"],
        de.as_str(),
        "refused updates change nothing"
    );
    let (status, u) = put(
        id.clone(),
        opp_body(GAMMA, json!({ "clear_power_grid": true })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{u}");
    assert!(u["power_grid_id"].is_null());
    // `clear_power_grid: false` is the same as omitting it.
    let (status, u) = put(
        plain.clone(),
        opp_body(
            BETA,
            json!({ "power_grid_id": be3, "clear_power_grid": false }),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{u}");
    assert_eq!(u["power_grid_id"], be3.as_str());
    let (_, list) = api(&app, SALES, Method::GET, "/opportunities", None).await;
    assert!(list["items"]
        .as_array()
        .unwrap()
        .iter()
        .any(|o| o["power_grid_id"] == be3.as_str()));
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_stored_grid_that_no_longer_fits_the_customer_is_dropped_on_update(db: PgPool) {
    let app = setup(db.clone()).await;
    let be = grid_id(&app, "BE", 230, 1).await;
    let (_, o) = api(
        &app,
        SALES,
        Method::POST,
        "/opportunities",
        Some(opp_body(BETA, json!({ "power_grid_id": be }))),
    )
    .await;
    assert_eq!(o["power_grid_id"], be.as_str());
    let id = o["id"].as_str().unwrap().to_string();
    // The customer moves abroad.
    sqlx::query("UPDATE crm.customers SET country_code = 'DE' WHERE id = $1::uuid")
        .bind(BETA)
        .execute(&db)
        .await
        .unwrap();
    let (status, u) = api(
        &app,
        SALES,
        Method::PUT,
        &format!("/opportunities/{id}"),
        Some(opp_body(BETA, json!({ "title": "Moved" }))),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{u}");
    assert!(
        u["power_grid_id"].is_null(),
        "same rule as quotations: kept only while it fits"
    );
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn opportunity_baseline_audit_of_power_grid_and_unrelated_opportunities_still_work(
    db: PgPool,
) {
    // The existing opportunity endpoints keep working untouched by the new optional fields.
    let app = setup(db).await;
    let (status, o) = api(
        &app,
        SALES,
        Method::GET,
        &format!("/opportunities/{OPP}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{o}");
    assert!(o.as_object().unwrap().contains_key("power_grid_id"));
    assert!(o["power_grid_id"].is_null());
}
