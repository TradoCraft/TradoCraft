//! Bell motor derivation in product matching (ADR 0068, Phase 5b): the admin lookup tables, the
//! motor check of `GET /opportunities/{id}/product-matches` and its reasons.

mod common;

use axum::http::{Method, StatusCode};
use common::{call, setup};
use serde_json::{json, Value};
use sqlx::PgPool;

const ADMIN: &str = "admin@example.com";
const SALES: &str = "sales@example.com";
const COMPANY: &str = "00000000-0000-7000-8000-000000000001";
const OPP: &str = "00000000-0000-7000-8000-000000000701"; // customer Alpha (BE)
const OPP2: &str = "00000000-0000-7000-8000-000000000702";
const UNIT_100: &str = "00000000-0000-7000-8000-000000000301"; // seeded 3x400V 50Hz
const PUMP: &str = "00000000-0000-7000-8000-000000000303"; // seeded 230V 1-phase
const BOLT: &str = "00000000-0000-7000-8000-000000000309"; // no supplies
const CTRL: &str = "00000000-0000-7000-8000-000000000310"; // seeded 24V DC

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

async fn motor_kw(app: &axum::Router, product: &str, kw: &str) {
    let (status, r) = api(
        app,
        ADMIN,
        Method::PUT,
        &format!("/products/{product}/attributes"),
        Some(json!([{ "key": "motor_kw", "kind": "number", "value": kw, "unit": "kW" }])),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{r}");
}

async fn bell(app: &axum::Router, opp: &str, parent: &str, name: &str, values: Value) {
    add_item(
        app,
        opp,
        json!({ "type_code": "bell", "parent_id": parent, "name": name, "values": values }),
    )
    .await;
}

async fn group(app: &axum::Router, opp: &str) -> String {
    add_item(
        app,
        opp,
        json!({ "type_code": "bell_group", "name": "Tower" }),
    )
    .await
}

fn motor_reasons(p: &Value) -> Vec<(String, String)> {
    reasons(p)
        .into_iter()
        .filter(|(check, ..)| check == "motor")
        .map(|(_, status, message)| (status, message))
        .collect()
}

async fn products_with_motors(app: &axum::Router) {
    motor_kw(app, UNIT_100, "0.12").await;
    motor_kw(app, PUMP, "0.25").await;
    motor_kw(app, BOLT, "0.55").await;
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn falling_and_volteo_bells_on_a_three_phase_grid(db: PgPool) {
    let app = seeded(&db).await;
    products_with_motors(&app).await;
    set_grid(&app, OPP, &grid_id(&app, "BE", 400, 3).await).await;
    let g = group(&app, OPP).await;
    bell(
        &app,
        OPP,
        &g,
        "Alpha",
        json!({ "weight_kg": 450, "motion": "falling" }),
    )
    .await;
    bell(
        &app,
        OPP,
        &g,
        "Beta",
        json!({ "weight_kg": 450, "motion": "volteo" }),
    )
    .await;
    let m = matches(&app, OPP, "limit=500").await;

    // 450 kg falling needs 0.12 kW (the boundary), volteo moves it one class up to 0.18 kW.
    let weak = of(&m, UNIT_100);
    assert_eq!(weak["status"], "unsuitable");
    assert_eq!(
        motor_reasons(weak),
        [
            (
                "ok".to_string(),
                "bell \"Alpha\": needs a motor of at least 0.12 kW (size 63, mez_1000), the product's 0.12 kW is enough".to_string()
            ),
            (
                "fail".to_string(),
                "bell \"Beta\": needs a motor of at least 0.18 kW (size 71, mez_1000), the product's 0.12 kW is too small".to_string()
            ),
        ]
    );

    // 0.25 kW is enough for both bells; the product is unsuitable only because of its supply.
    let pump = of(&m, PUMP);
    assert_eq!(pump["status"], "unsuitable");
    assert!(motor_reasons(pump).iter().all(|(s, _)| s == "ok"));
    assert_eq!(reasons(pump)[0].0, "power");

    // 0.55 kW without a supply is suitable.
    let bolt = of(&m, BOLT);
    assert_eq!(bolt["status"], "suitable");
    assert_eq!(motor_reasons(bolt).len(), 2);

    // A product that declares no motor is not judged by the bells.
    let ctrl = of(&m, CTRL);
    assert!(motor_reasons(ctrl).is_empty());
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_balanced_bell_on_a_single_phase_mez_motor_moves_one_class_up(db: PgPool) {
    let app = seeded(&db).await;
    products_with_motors(&app).await;
    set_grid(&app, OPP, &grid_id(&app, "BE", 230, 1).await).await;
    let g = group(&app, OPP).await;
    bell(
        &app,
        OPP,
        &g,
        "Yoke",
        json!({ "weight_kg": 100, "motion": "balanced", "motor_brand": "mez_1000" }),
    )
    .await;
    let m = matches(&app, OPP, "limit=500").await;
    // 100 kg is the 0.12 kW class of 1-phase MEZ; balanced takes 0.18 kW (size 71).
    let weak = of(&m, UNIT_100);
    assert_eq!(
        motor_reasons(weak),
        [(
            "fail".to_string(),
            "bell \"Yoke\": needs a motor of at least 0.18 kW (size 71, mez_1000), the product's 0.12 kW is too small".to_string()
        )]
    );
    let pump = of(&m, PUMP);
    assert_eq!(pump["status"], "suitable", "{pump}");
    assert_eq!(motor_reasons(pump)[0].0, "ok");
    assert_eq!(of(&m, BOLT)["status"], "suitable");

    // The same bell falling instead: 0.12 kW is enough.
    sqlx::query("UPDATE crm.opportunity_baseline_items SET values = jsonb_set(values, '{motion}', '\"falling\"') WHERE name = 'Yoke'")
        .execute(&db)
        .await
        .unwrap();
    let m = matches(&app, OPP, "limit=500").await;
    assert_eq!(motor_reasons(of(&m, UNIT_100))[0].0, "ok");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn too_large_bells_fail_every_motor_product_and_missing_data_is_unknown(db: PgPool) {
    let app = seeded(&db).await;
    products_with_motors(&app).await;
    set_grid(&app, OPP, &grid_id(&app, "BE", 230, 1).await).await;
    let g = group(&app, OPP).await;
    bell(
        &app,
        OPP,
        &g,
        "Bourdon",
        json!({ "weight_kg": 1200, "motion": "falling", "motor_brand": "mez_1000" }),
    )
    .await;
    bell(&app, OPP, &g, "Unweighed", json!({ "motion": "falling" })).await;
    let m = matches(&app, OPP, "limit=500").await;
    for id in [UNIT_100, PUMP, BOLT] {
        let p = of(&m, id);
        assert_eq!(p["status"], "unsuitable", "{p}");
        assert_eq!(
            motor_reasons(p),
            [
                (
                    "fail".to_string(),
                    "bell \"Bourdon\": 1200 kg per wheel is above the largest 1-phase mez_1000 motor class (1100 kg); more wheels may help".to_string()
                ),
                (
                    "unknown".to_string(),
                    "bell \"Unweighed\": no weight recorded".to_string()
                ),
            ]
        );
    }
    // Two wheels share the weight: 600 kg per wheel is the 0.37 kW class.
    sqlx::query("UPDATE crm.opportunity_baseline_items SET values = values || '{\"num_wheels\": 2}' WHERE name = 'Bourdon'")
        .execute(&db)
        .await
        .unwrap();
    let m = matches(&app, OPP, "limit=500").await;
    let bolt = of(&m, BOLT);
    assert_eq!(motor_reasons(bolt)[0].0, "ok");
    assert_eq!(motor_reasons(of(&m, PUMP))[0].0, "fail");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn without_a_grid_the_motor_is_unknown_and_edited_tables_take_effect(db: PgPool) {
    let app = seeded(&db).await;
    products_with_motors(&app).await;
    let g = group(&app, OPP2).await;
    bell(
        &app,
        OPP2,
        &g,
        "Alpha",
        json!({ "weight_kg": 450, "motion": "falling" }),
    )
    .await;
    let m = matches(&app, OPP2, "limit=500").await;
    let bolt = of(&m, BOLT);
    assert_eq!(bolt["status"], "unknown");
    assert_eq!(
        motor_reasons(bolt),
        [(
            "unknown".to_string(),
            "bell \"Alpha\": the power grid has no known phases".to_string()
        )]
    );

    // The tables are data: raise the first 3-phase MEZ falling class limit and the need changes.
    let be3 = grid_id(&app, "BE", 400, 3).await;
    sqlx::query("UPDATE crm.opportunities SET power_grid_id = $1::uuid WHERE id = $2::uuid")
        .bind(&be3)
        .bind(OPP2)
        .execute(&db)
        .await
        .unwrap();
    sqlx::query(
        "UPDATE configurator.model_revisions SET definition = jsonb_set(definition, '{tables,3,rows}',
           (SELECT jsonb_agg(CASE WHEN r->>'brand' = 'mez_1000' AND r->>'phases' = '3'
                                   AND r->>'motion' = 'falling' AND r->>'kw' = '0.12'
                                  THEN r || '{\"kw\": 0.2}' ELSE r END)
            FROM jsonb_array_elements(definition #> '{tables,3,rows}') r))
         WHERE status = 'active'",
    )
    .execute(&db)
    .await
    .unwrap();
    sqlx::query("UPDATE crm.opportunity_baseline_items SET \"values\" = \"values\" || '{\"motor_brand\": \"mez_1000\"}'")
        .execute(&db)
        .await
        .unwrap();
    let m = matches(&app, OPP2, "limit=500").await;
    assert_eq!(
        motor_reasons(of(&m, UNIT_100))[0],
        (
            "fail".to_string(),
            "bell \"Alpha\": needs a motor of at least 0.2 kW (size 63, mez_1000), the product's 0.12 kW is too small".to_string()
        )
    );

    // Without the tables nothing can be derived: unknown, never a failure.
    sqlx::query("DELETE FROM configurator.models WHERE code = 'bell_motors'")
        .execute(&db)
        .await
        .unwrap();
    let m = matches(&app, OPP2, "limit=500").await;
    let r = motor_reasons(of(&m, UNIT_100));
    assert_eq!(r[0].0, "unknown");
    assert!(r[0].1.contains("bell_motors"), "{r:?}");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_seed_is_idempotent_and_keeps_edited_tables(db: PgPool) {
    let app = seeded(&db).await;
    let _ = app;
    let count = |db: &PgPool| {
        let db = db.clone();
        async move {
            sqlx::query_scalar::<_, i64>(
                "SELECT count(*) FROM configurator.model_revisions r
                 JOIN configurator.models m ON m.id = r.model_id
                 WHERE m.code = 'bell_motors' AND m.company_id = $1::uuid",
            )
            .bind(COMPANY)
            .fetch_one(&db)
            .await
            .unwrap()
        }
    };
    assert_eq!(count(&db).await, 1);
    sqlx::query("SELECT crm.seed_baseline_defaults($1::uuid)")
        .bind(COMPANY)
        .execute(&db)
        .await
        .unwrap();
    assert_eq!(count(&db).await, 1);
    for key in ["num_wheels", "motor_brand", "motor_kw"] {
        let n: i64 = sqlx::query_scalar(
            "SELECT count(*) FROM products.attribute_definitions WHERE company_id = $1::uuid AND key = $2",
        )
        .bind(COMPANY)
        .bind(key)
        .fetch_one(&db)
        .await
        .unwrap();
        assert_eq!(n, 1, "{key}");
    }
}
