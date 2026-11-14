//! Import of a tower configurator export into an opportunity's baseline (ADR 0068): dry run,
//! mapping, replace-by-source, hand-entered items, permissions and isolation. The fixtures are
//! real exports of the tower configurator.

mod common;

use axum::http::{Method, StatusCode};
use common::{call, call_raw, setup};
use serde_json::{json, Value};
use sqlx::PgPool;

const ADMIN: &str = "admin@example.com";
const SALES: &str = "sales@example.com";
const VIEWER: &str = "viewer@example.com";
const COMPANY: &str = "00000000-0000-7000-8000-000000000001";
const OPP: &str = "00000000-0000-7000-8000-000000000701";
const OPP2: &str = "00000000-0000-7000-8000-000000000702";
const BETA: &str = "00000000-0000-7000-8000-000000000402";
const OTHER_COMPANY: &str = "00000000-0000-7000-8000-0000000fff01";
const OTHER_OPP: &str = "00000000-0000-7000-8000-0000000fff02";

fn fixture(name: &str) -> Value {
    let path = format!(
        "{}/tests/fixtures/tower_configurator/{name}.json",
        env!("CARGO_MANIFEST_DIR")
    );
    serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap()
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

fn import_uri(opp: &str, query: &str) -> String {
    format!("/api/v1/opportunities/{opp}/baseline/import{query}")
}

async fn import(
    app: &axum::Router,
    user: &str,
    opp: &str,
    query: &str,
    doc: Value,
) -> (StatusCode, Value) {
    call(app, user, Method::POST, &import_uri(opp, query), Some(doc)).await
}

async fn tree(app: &axum::Router, opp: &str) -> Value {
    let (status, t) = call(
        app,
        SALES,
        Method::GET,
        &format!("/api/v1/opportunities/{opp}/baseline"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{t}");
    t
}

async fn count(db: &PgPool, opp: &str) -> i64 {
    sqlx::query_scalar(
        "SELECT count(*) FROM crm.opportunity_baseline_items WHERE opportunity_id = $1::uuid",
    )
    .bind(opp)
    .fetch_one(db)
    .await
    .unwrap()
}

fn mini() -> Value {
    json!({
        "customer": {"name": "Parish", "rotary_motor": "ADDA 750"},
        "location": {"name": "St Mary", "country": "BE"},
        "bells": [
            {"identifier": "bell_1", "properties": {"note": "B1", "weight_g": "320000", "diameter_mm": "824",
                "height_mm": "646", "motion": "flying", "motor": "rotating", "striker": "swinging"}},
            {"identifier": "bell_2", "properties": {"weight_g": "200000", "motion": "swirling"}}
        ],
        "topology": {"nodes": []}
    })
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_dry_run_previews_and_writes_nothing(db: PgPool) {
    let app = seeded(&db).await;
    let (status, r) = import(&app, SALES, OPP, "?dry_run=true", mini()).await;
    assert_eq!(status, StatusCode::OK, "{r}");
    assert_eq!(r["dry_run"], true);
    assert_eq!(
        r["created"],
        json!({"bell_group": 1, "bell": 2, "clock_dial": 0})
    );
    assert_eq!(r["replaced"], 0);
    assert_eq!(r["source_id"], "tower_configurator");
    assert_eq!(r["items"].as_array().unwrap().len(), 3);
    assert_eq!(r["items"][0]["type_code"], "bell_group");
    assert_eq!(r["items"][0]["name"], "St Mary");
    assert_eq!(r["items"][1]["values"]["weight_kg"], 320.0);
    let warnings = r["warnings"].as_array().unwrap();
    assert_eq!(warnings.len(), 1, "{r}");
    assert_eq!(warnings[0]["bell"], "bell_2");
    assert_eq!(warnings[0]["field"], "motion");
    let fields: Vec<&str> = r["unmapped_fields"]
        .as_array()
        .unwrap()
        .iter()
        .map(|u| u["field"].as_str().unwrap())
        .collect();
    assert!(fields.contains(&"bells[].properties.striker"), "{fields:?}");
    assert!(fields.contains(&"topology"));
    assert_eq!(count(&db, OPP).await, 0);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_import_creates_a_group_with_bells_and_keeps_the_source(db: PgPool) {
    let app = seeded(&db).await;
    let (status, r) = import(&app, SALES, OPP, "", mini()).await;
    assert_eq!(status, StatusCode::OK, "{r}");
    assert_eq!(r["dry_run"], false);
    let t = tree(&app, OPP).await;
    let group = &t[0];
    assert_eq!(group["type_code"], "bell_group");
    assert_eq!(group["name"], "St Mary");
    assert_eq!(group["import_source"], "tower_configurator");
    let bells = group["children"].as_array().unwrap();
    assert_eq!(bells.len(), 2);
    assert_eq!(bells[0]["name"], "bell_1");
    assert_eq!(bells[0]["type_code"], "bell");
    assert_eq!(
        bells[0]["values"],
        json!({"note": "B1", "weight_kg": 320.0, "diameter_mm": 824.0, "height_mm": 646.0,
               "motion": "flying", "motor_brand": "adda_750"})
    );
    assert_eq!(bells[1]["values"], json!({"weight_kg": 200.0}));
    // The raw source is stored, also what has no attribute and what was not understood.
    let raw: Value = sqlx::query_scalar(
        "SELECT source_data FROM crm.opportunity_baseline_items WHERE name = 'bell_2'",
    )
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(raw["properties"]["motion"], "swirling");
    let raw: Value = sqlx::query_scalar(
        "SELECT source_data FROM crm.opportunity_baseline_items WHERE name = 'bell_1'",
    )
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(raw["properties"]["striker"], "swinging");
    let raw: Value = sqlx::query_scalar(
        "SELECT source_data FROM crm.opportunity_baseline_items WHERE type_code = 'bell_group'",
    )
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(raw["customer"]["rotary_motor"], "ADDA 750");
    assert!(raw.get("bells").is_none());
    let audited: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM audit.events WHERE entity = 'opportunity' AND action = 'baseline_imported'",
    )
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(audited, 1);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_second_import_replaces_the_first(db: PgPool) {
    let app = seeded(&db).await;
    import(&app, SALES, OPP, "", mini()).await;
    let mut again = mini();
    again["bells"].as_array_mut().unwrap().pop();
    let (_, preview) = import(&app, SALES, OPP, "?dry_run=true", again.clone()).await;
    assert_eq!(preview["replaced"], 3);
    let (status, r) = import(&app, SALES, OPP, "", again).await;
    assert_eq!(status, StatusCode::OK, "{r}");
    assert_eq!(r["replaced"], 3);
    assert_eq!(count(&db, OPP).await, 2);
    let t = tree(&app, OPP).await;
    assert_eq!(t.as_array().unwrap().len(), 1);
    assert_eq!(t[0]["children"].as_array().unwrap().len(), 1);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn hand_entered_items_and_other_sources_survive_a_reimport(db: PgPool) {
    let app = seeded(&db).await;
    import(&app, SALES, OPP, "", mini()).await;
    // A hand-entered dial and bell, and a hand-entered bell inside the imported group.
    let group_id = tree(&app, OPP).await[0]["id"].as_str().unwrap().to_string();
    for body in [
        json!({"type_code": "clock_dial", "name": "Dial", "values": {"dial_diameter_mm": 1500}}),
        json!({"type_code": "bell", "name": "By hand", "parent_id": group_id}),
    ] {
        let (s, r) = call(
            &app,
            SALES,
            Method::POST,
            &format!("/api/v1/opportunities/{OPP}/baseline/items"),
            Some(body),
        )
        .await;
        assert_eq!(s, StatusCode::CREATED, "{r}");
    }
    // Another source on the same opportunity, and the same source on another opportunity.
    import(&app, SALES, OPP, "?source_id=second_tower", mini()).await;
    import(&app, SALES, OPP2, "", mini()).await;

    let (status, r) = import(&app, SALES, OPP, "", mini()).await;
    assert_eq!(status, StatusCode::OK, "{r}");
    assert_eq!(r["replaced"], 3);
    let names: Vec<String> = sqlx::query_scalar(
        "SELECT name FROM crm.opportunity_baseline_items WHERE opportunity_id = $1::uuid
         AND import_source IS NULL ORDER BY name",
    )
    .bind(OPP)
    .fetch_all(&db)
    .await
    .unwrap();
    assert_eq!(names, ["By hand", "Dial"]);
    // 2 hand-entered + 3 of the second source + 3 re-imported.
    assert_eq!(count(&db, OPP).await, 8);
    assert_eq!(count(&db, OPP2).await, 3);
    // The hand-entered bell is detached (its group was replaced), not deleted.
    let parent: Option<String> = sqlx::query_scalar(
        "SELECT parent_id::text FROM crm.opportunity_baseline_items WHERE name = 'By hand'",
    )
    .fetch_one(&db)
    .await
    .unwrap();
    assert!(parent.is_none());
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_eight_bell_linear_motor_fixture_imports_with_warnings(db: PgPool) {
    let app = seeded(&db).await;
    let (status, r) = import(&app, SALES, OPP, "", fixture("8bell_linear_motor")).await;
    assert_eq!(status, StatusCode::OK, "{r}");
    assert_eq!(r["created"]["bell"], 8);
    assert_eq!(r["created"]["clock_dial"], 0);
    let warnings = r["warnings"].as_array().unwrap();
    assert!(
        warnings.iter().any(|w| w["field"] == "motor"),
        "{warnings:?}"
    );
    let t = tree(&app, OPP).await;
    let bells = t[0]["children"].as_array().unwrap();
    assert_eq!(bells.len(), 8);
    let first = bells
        .iter()
        .find(|b| b["name"] == "swinging_bell_1")
        .unwrap();
    assert_eq!(first["values"]["weight_kg"], 320.0);
    assert_eq!(first["values"]["diameter_mm"], 824.0);
    assert_eq!(first["values"]["motion"], "flying");
    assert!(first["values"].get("motor_brand").is_none());
    // motor_ref has no attribute but is kept.
    let motor_ref: String = sqlx::query_scalar(
        "SELECT source_data->'properties'->>'motor_ref' FROM crm.opportunity_baseline_items
         WHERE name = 'swinging_bell_1'",
    )
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(motor_ref, "IV714C");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_rotating_motor_fixture_maps_the_project_brand(db: PgPool) {
    let app = seeded(&db).await;
    let (status, r) = import(&app, SALES, OPP, "", fixture("email_5bell_serial_apollo3")).await;
    assert_eq!(status, StatusCode::OK, "{r}");
    let t = tree(&app, OPP).await;
    let bells = t[0]["children"].as_array().unwrap();
    assert_eq!(bells.len(), 5);
    assert!(
        bells
            .iter()
            .all(|b| b["values"]["motor_brand"] == "mez_1000"),
        "{bells:?}"
    );
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_fifty_bell_system_imports_in_one_go(db: PgPool) {
    let app = seeded(&db).await;
    let (status, r) = import(&app, SALES, OPP, "", fixture("50_bell_system")).await;
    assert_eq!(status, StatusCode::OK, "{r}");
    assert_eq!(r["created"]["bell"], 50);
    assert_eq!(count(&db, OPP).await, 51);
    let t = tree(&app, OPP).await;
    let bells = t[0]["children"].as_array().unwrap();
    assert_eq!(bells.len(), 50);
    assert!(bells
        .iter()
        .all(|b| b["values"]["weight_kg"].as_f64().unwrap() > 0.0));
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn bad_input_is_a_422_and_writes_nothing(db: PgPool) {
    let app = seeded(&db).await;
    let uri = import_uri(OPP, "");
    for body in [
        b"{not json".to_vec(),
        b"[]".to_vec(),
        b"{}".to_vec(),
        br#"{"bells": "x"}"#.to_vec(),
        Vec::new(),
    ] {
        let (status, r) = call_raw(&app, SALES, &uri, "application/json", body).await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{r}");
    }
    let (status, _) = import(&app, SALES, OPP, "?source_id=%20", mini()).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    let long = "x".repeat(101);
    let (status, _) = import(&app, SALES, OPP, &format!("?source_id={long}"), mini()).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(count(&db, OPP).await, 0);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn an_empty_bell_list_creates_only_the_group(db: PgPool) {
    let app = seeded(&db).await;
    let (status, r) = import(&app, SALES, OPP, "", json!({"bells": []})).await;
    assert_eq!(status, StatusCode::OK, "{r}");
    assert_eq!(
        r["created"],
        json!({"bell_group": 1, "bell": 0, "clock_dial": 0})
    );
    assert_eq!(count(&db, OPP).await, 1);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn too_many_bells_are_refused_without_replacing(db: PgPool) {
    let app = seeded(&db).await;
    import(&app, SALES, OPP, "", mini()).await;
    let bells: Vec<Value> = (0..1000)
        .map(|i| json!({"identifier": format!("b{i}"), "properties": {}}))
        .collect();
    let (status, _) = import(&app, SALES, OPP, "", json!({"bells": bells})).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(count(&db, OPP).await, 3);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn unknown_fields_are_kept_not_rejected(db: PgPool) {
    let app = seeded(&db).await;
    let mut doc = mini();
    doc["brand_new_section"] = json!({"a": 1});
    doc["bells"][0]["extra"] = json!(true);
    doc["bells"][0]["properties"]["future_prop"] = json!("x");
    let (status, r) = import(&app, SALES, OPP, "", doc).await;
    assert_eq!(status, StatusCode::OK, "{r}");
    let fields: Vec<&str> = r["unmapped_fields"]
        .as_array()
        .unwrap()
        .iter()
        .map(|u| u["field"].as_str().unwrap())
        .collect();
    for f in [
        "brand_new_section",
        "bells[].extra",
        "bells[].properties.future_prop",
    ] {
        assert!(fields.contains(&f), "{f} in {fields:?}");
    }
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_deleted_definition_does_not_break_the_import(db: PgPool) {
    let app = seeded(&db).await;
    sqlx::query("DELETE FROM products.attribute_definitions WHERE key = 'motor_brand'")
        .execute(&db)
        .await
        .unwrap();
    let (status, r) = import(&app, SALES, OPP, "", mini()).await;
    assert_eq!(status, StatusCode::OK, "{r}");
    assert!(
        r["warnings"]
            .as_array()
            .unwrap()
            .iter()
            .any(|w| w["field"] == "motor_brand"),
        "{r}"
    );
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn permission_and_isolation(db: PgPool) {
    let app = seeded(&db).await;
    for dry in ["", "?dry_run=true"] {
        let (status, _) = import(&app, VIEWER, OPP, dry, mini()).await;
        assert_eq!(status, StatusCode::FORBIDDEN, "viewer {dry}");
    }
    let (status, _) = import(
        &app,
        ADMIN,
        "00000000-0000-7000-8000-00000000dead",
        "",
        mini(),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

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
    for dry in ["", "?dry_run=true"] {
        let (status, _) = import(&app, ADMIN, OTHER_OPP, dry, mini()).await;
        assert_eq!(status, StatusCode::NOT_FOUND, "{dry}");
    }
    assert_eq!(count(&db, OTHER_OPP).await, 0);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_source_of_an_item_can_be_read_back(db: PgPool) {
    let app = seeded(&db).await;
    import(&app, SALES, OPP, "", mini()).await;
    let t = tree(&app, OPP).await;
    let id = t[0]["children"][0]["id"].as_str().unwrap();
    let (status, raw) = call(
        &app,
        VIEWER,
        Method::GET,
        &format!("/api/v1/opportunities/{OPP}/baseline/items/{id}/source"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{raw}");
    assert_eq!(raw["properties"]["striker"], "swinging");
    // An item entered by hand has no source.
    let (_, made) = call(
        &app,
        SALES,
        Method::POST,
        &format!("/api/v1/opportunities/{OPP}/baseline/items"),
        Some(json!({"type_code": "bell"})),
    )
    .await;
    let (status, _) = call(
        &app,
        SALES,
        Method::GET,
        &format!(
            "/api/v1/opportunities/{OPP}/baseline/items/{}/source",
            made["id"].as_str().unwrap()
        ),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}
