//! Power grids, product supply profiles, the compatibility check and the sales warnings.

mod common;

use axum::http::{Method, StatusCode};
use common::{call, setup};
use serde_json::{json, Value};
use sqlx::PgPool;

const ALPHA: &str = "00000000-0000-7000-8000-000000000401"; // BE
const UNIT_100: &str = "00000000-0000-7000-8000-000000000301"; // seeded 3x400V 50Hz
const UNIT_200: &str = "00000000-0000-7000-8000-000000000302"; // seeded 120V 60Hz
const PUMP: &str = "00000000-0000-7000-8000-000000000303"; // seeded 230V 1-phase
const CTRL: &str = "00000000-0000-7000-8000-000000000310"; // seeded 24V DC
const BOLT: &str = "00000000-0000-7000-8000-000000000309"; // no supplies
const SALES: &str = "sales@example.com";
const ADMIN: &str = "admin@example.com";

async fn api(
    app: &axum::Router,
    user: &str,
    method: Method,
    uri: &str,
    body: Option<Value>,
) -> (StatusCode, Value) {
    call(app, user, method, &format!("/api/v1{uri}"), body).await
}

async fn grid_id(app: &axum::Router, country: &str, voltage: i64, phases: i64) -> String {
    let (status, list) = api(
        app,
        SALES,
        Method::GET,
        &format!("/power-grids?country={country}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    list.as_array()
        .unwrap()
        .iter()
        .find(|g| g["voltage_v"] == voltage && g["phases"] == phases)
        .unwrap_or_else(|| panic!("no {country} grid {voltage}V/{phases}"))["id"]
        .as_str()
        .unwrap()
        .to_string()
}

async fn put_supplies(app: &axum::Router, product: &str, body: Value) -> (StatusCode, Value) {
    api(
        app,
        ADMIN,
        Method::PUT,
        &format!("/products/{product}/power-supplies"),
        Some(body),
    )
    .await
}

async fn compat(app: &axum::Router, product: &str, query: &str) -> Value {
    let (status, r) = api(
        app,
        SALES,
        Method::GET,
        &format!("/products/{product}/power-compatibility?{query}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{r}");
    r
}

async fn quote(app: &axum::Router, products: &[&str], extra: Value) -> (StatusCode, Value) {
    let lines: Vec<Value> = products
        .iter()
        .map(|p| json!({ "product_id": p, "quantity": "1" }))
        .collect();
    let mut body = json!({ "customer_id": ALPHA, "lines": lines });
    for (k, v) in extra.as_object().unwrap() {
        body[k] = v.clone();
    }
    api(app, SALES, Method::POST, "/quotations", Some(body)).await
}

fn warning_codes(v: &Value) -> Vec<String> {
    v["warnings"]
        .as_array()
        .expect("warnings array")
        .iter()
        .map(|w| w["product_code"].as_str().unwrap().to_string())
        .collect()
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn seeded_grid_data_is_loaded(db: PgPool) {
    let n: i64 = sqlx::query_scalar("SELECT count(*) FROM products.power_grids")
        .fetch_one(&db)
        .await
        .unwrap();
    assert_eq!(n, 496);
    let countries: i64 =
        sqlx::query_scalar("SELECT count(DISTINCT country_code) FROM products.power_grids")
            .fetch_one(&db)
            .await
            .unwrap();
    assert_eq!(countries, 228);
    for (cc, v, p, f) in [
        ("BE", 230, 1, 50),
        ("BE", 400, 3, 50),
        ("US", 120, 1, 60),
        ("US", 208, 3, 60),
    ] {
        let found: bool = sqlx::query_scalar(
            "SELECT EXISTS (SELECT 1 FROM products.power_grids
             WHERE country_code = $1 AND voltage_v = $2 AND phases = $3 AND frequency_hz = $4)",
        )
        .bind(cc)
        .bind(v)
        .bind(p)
        .bind(f)
        .fetch_one(&db)
        .await
        .unwrap();
        assert!(found, "{cc} {v}V {p} {f}Hz");
    }
    let name: String = sqlx::query_scalar(
        "SELECT name FROM products.power_grids WHERE country_code = 'BE' AND phases = 3",
    )
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(name, "400V 3-phase 50Hz");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn grid_crud_and_permissions(db: PgPool) {
    let app = setup(db).await;
    let (status, list) = api(&app, SALES, Method::GET, "/power-grids?country=be", None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(list.as_array().unwrap().len(), 2);
    let (status, _) = api(&app, SALES, Method::GET, "/power-grids?country=BEL", None).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    let body = json!({ "country_code": "be", "voltage_v": 690, "phases": 3, "frequency_hz": 50 });
    let (status, _) = api(
        &app,
        SALES,
        Method::POST,
        "/power-grids",
        Some(body.clone()),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, g) = api(
        &app,
        ADMIN,
        Method::POST,
        "/power-grids",
        Some(body.clone()),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{g}");
    assert_eq!(g["country_code"], "BE");
    assert_eq!(g["name"], "690V 3-phase 50Hz");
    assert_eq!(g["active"], true);
    let (status, _) = api(&app, ADMIN, Method::POST, "/power-grids", Some(body)).await;
    assert_eq!(status, StatusCode::CONFLICT);
    for bad in [
        json!({ "country_code": "BE", "voltage_v": 230, "phases": 2, "frequency_hz": 50 }),
        json!({ "country_code": "BE", "voltage_v": 230, "phases": 1, "frequency_hz": 55 }),
        json!({ "country_code": "BE", "voltage_v": 0, "phases": 1, "frequency_hz": 50 }),
        json!({ "country_code": "B", "voltage_v": 230, "phases": 1, "frequency_hz": 50 }),
    ] {
        let (status, r) = api(&app, ADMIN, Method::POST, "/power-grids", Some(bad)).await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{r}");
    }

    let uri = format!("/power-grids/{}", g["id"].as_str().unwrap());
    let update = json!({ "country_code": "BE", "name": "Industrial", "voltage_v": 690, "phases": 3,
                         "frequency_hz": 50, "active": false });
    let (status, _) = api(&app, SALES, Method::PUT, &uri, Some(update.clone())).await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, u) = api(&app, ADMIN, Method::PUT, &uri, Some(update.clone())).await;
    assert_eq!(status, StatusCode::OK, "{u}");
    assert_eq!(u["name"], "Industrial");
    assert_eq!(u["active"], false);
    let (status, _) = api(
        &app,
        ADMIN,
        Method::PUT,
        "/power-grids/00000000-0000-7000-8000-0000000000ff",
        Some(update),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn supplies_are_replaced_and_validated(db: PgPool) {
    let app = setup(db).await;
    let uri = format!("/products/{UNIT_100}/power-supplies");
    let (status, list) = api(&app, SALES, Method::GET, &uri, None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(list.as_array().unwrap().len(), 1, "seeded profile");

    let (status, _) = put_supplies(&app, BOLT, json!([])).await;
    assert_eq!(status, StatusCode::OK);
    let (status, _) = api(&app, SALES, Method::PUT, &uri, Some(json!([]))).await;
    assert_eq!(status, StatusCode::FORBIDDEN);

    let (status, r) = put_supplies(
        &app,
        UNIT_100,
        json!([
            { "current_type": "ac", "voltage_v": 230, "phases": 1 },
            { "current_type": "dc", "voltage_v": 24, "tolerance_pct": 5 },
        ]),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{r}");
    let r = r.as_array().unwrap();
    assert_eq!(r.len(), 2, "the seeded profile is replaced");
    let ac = r.iter().find(|s| s["current_type"] == "ac").unwrap();
    assert_eq!(ac["tolerance_pct"], 10);
    assert!(ac["frequency_hz"].is_null());
    let dc = r.iter().find(|s| s["current_type"] == "dc").unwrap();
    assert_eq!(dc["tolerance_pct"], 5);
    assert!(dc["phases"].is_null());

    let ok = json!({ "current_type": "ac", "voltage_v": 230, "phases": 1 });
    for bad in [
        json!([{ "current_type": "dc", "voltage_v": 24, "phases": 1 }]),
        json!([{ "current_type": "dc", "voltage_v": 24, "frequency_hz": 50 }]),
        json!([{ "current_type": "ac", "voltage_v": 230 }]),
        json!([{ "current_type": "ac", "voltage_v": 230, "phases": 2 }]),
        json!([{ "current_type": "ac", "voltage_v": 230, "phases": 1, "frequency_hz": 55 }]),
        json!([{ "current_type": "ac", "voltage_v": 0, "phases": 1 }]),
        json!([{ "current_type": "ac", "voltage_v": 230, "phases": 1, "tolerance_pct": 51 }]),
        json!([{ "current_type": "ac", "voltage_v": 230, "phases": 1, "tolerance_pct": -1 }]),
        json!([{ "current_type": "xx", "voltage_v": 230, "phases": 1 }]),
        json!([ok.clone(), ok]),
    ] {
        let (status, r) = put_supplies(&app, UNIT_100, bad.clone()).await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{bad} -> {r}");
    }
    // A rejected replace leaves the list as it was.
    let (_, list) = api(&app, SALES, Method::GET, &uri, None).await;
    assert_eq!(list.as_array().unwrap().len(), 2);

    let (status, _) = put_supplies(&app, "00000000-0000-7000-8000-0000000000ff", json!([])).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    // Empty list = not electrical.
    let (status, r) = put_supplies(&app, UNIT_100, json!([])).await;
    assert_eq!(status, StatusCode::OK);
    assert!(r.as_array().unwrap().is_empty());
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn compatibility_endpoint_cases(db: PgPool) {
    let app = setup(db).await;

    // 220V product on a 230V country.
    put_supplies(
        &app,
        PUMP,
        json!([{ "current_type": "ac", "voltage_v": 220, "phases": 1 }]),
    )
    .await;
    assert_eq!(
        compat(&app, PUMP, "country=BE").await["status"],
        "compatible"
    );

    // 3x380 against 3x400.
    put_supplies(
        &app,
        UNIT_100,
        json!([{ "current_type": "ac", "voltage_v": 380, "phases": 3, "frequency_hz": 50 }]),
    )
    .await;
    assert_eq!(
        compat(&app, UNIT_100, "country=BE").await["status"],
        "compatible"
    );

    // 110V in Belgium.
    put_supplies(
        &app,
        UNIT_200,
        json!([{ "current_type": "ac", "voltage_v": 110, "phases": 1 }]),
    )
    .await;
    let r = compat(&app, UNIT_200, "country=be").await;
    assert_eq!(r["status"], "incompatible");
    assert_eq!(r["country_code"], "BE");
    assert_eq!(r["supported"].as_array().unwrap().len(), 1);
    assert_eq!(r["available"].as_array().unwrap().len(), 2);
    // ... but fine in the US (120V).
    assert_eq!(
        compat(&app, UNIT_200, "country=US").await["status"],
        "compatible"
    );

    // DC only, no supplies, unknown country.
    assert_eq!(
        compat(&app, CTRL, "country=BE").await["status"],
        "needs_external_supply"
    );
    assert_eq!(
        compat(&app, BOLT, "country=BE").await["status"],
        "not_applicable"
    );
    assert_eq!(
        compat(&app, PUMP, "country=ZZ").await["status"],
        "unknown_grid"
    );

    // Specific grid versus any grid: the pump (230V 1-phase) fits BE as a whole but not its 400V grid.
    let g400 = grid_id(&app, "BE", 400, 3).await;
    let g230 = grid_id(&app, "BE", 230, 1).await;
    assert_eq!(
        compat(&app, PUMP, &format!("country=BE&grid_id={g400}")).await["status"],
        "incompatible"
    );
    assert_eq!(
        compat(&app, PUMP, &format!("grid_id={g230}")).await["status"],
        "compatible"
    );
    // Inactive grids drop out of the "any grid" check.
    let (status, _) = api(
        &app,
        ADMIN,
        Method::PUT,
        &format!("/power-grids/{g230}"),
        Some(json!({ "country_code": "BE", "voltage_v": 230, "phases": 1, "frequency_hz": 50, "active": false })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(
        compat(&app, PUMP, "country=BE").await["status"],
        "incompatible"
    );

    // Input errors.
    let uri = format!("/products/{PUMP}/power-compatibility");
    let (status, _) = api(&app, SALES, Method::GET, &uri, None).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    let (status, _) = api(
        &app,
        SALES,
        Method::GET,
        &format!("{uri}?country=US&grid_id={g400}"),
        None,
    )
    .await;
    assert_eq!(
        status,
        StatusCode::UNPROCESSABLE_ENTITY,
        "grid of another country"
    );
    let (status, _) = api(
        &app,
        SALES,
        Method::GET,
        "/products/00000000-0000-7000-8000-0000000000ff/power-compatibility?country=BE",
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn quotation_warnings_for_mismatch_and_none_for_match(db: PgPool) {
    let app = setup(db).await;
    // Alpha is Belgian: UNIT-100 (3x400) and PUMP-05 (230V) fit, CTRL-01 is DC, UNIT-200 is 120V/60Hz.
    let (status, q) = quote(&app, &[UNIT_100, PUMP, BOLT], json!({})).await;
    assert_eq!(status, StatusCode::CREATED, "{q}");
    assert!(warning_codes(&q).is_empty(), "{q}");

    let (status, q) = quote(&app, &[UNIT_100, UNIT_200, CTRL], json!({})).await;
    assert_eq!(status, StatusCode::CREATED, "{q}");
    let mut codes = warning_codes(&q);
    codes.sort();
    assert_eq!(codes, ["CTRL-01", "UNIT-200"]);
    let w = q["warnings"]
        .as_array()
        .unwrap()
        .iter()
        .find(|w| w["product_code"] == "UNIT-200")
        .unwrap();
    assert_eq!(w["kind"], "power_grid");
    assert_eq!(w["details"]["status"], "incompatible");
    assert_eq!(w["details"]["country_code"], "BE");
    assert!(w["message"].as_str().unwrap().contains("UNIT-200"));
    let w = q["warnings"]
        .as_array()
        .unwrap()
        .iter()
        .find(|w| w["product_code"] == "CTRL-01")
        .unwrap();
    assert_eq!(w["details"]["status"], "needs_external_supply");

    // Delivery country overrides the customer's: UNIT-200 fits the US.
    let (_, q) = quote(&app, &[UNIT_200], json!({ "delivery_country_code": "US" })).await;
    assert!(warning_codes(&q).is_empty(), "{q}");
    // A country without data is reported as unknown.
    let (_, q) = quote(&app, &[UNIT_200], json!({ "delivery_country_code": "ZZ" })).await;
    assert_eq!(q["warnings"][0]["details"]["status"], "unknown_grid");

    // Update recomputes; GET returns no warnings.
    let qid = q["id"].as_str().unwrap();
    let (status, u) = api(
        &app,
        SALES,
        Method::PUT,
        &format!("/quotations/{qid}"),
        Some(json!({ "customer_id": ALPHA, "delivery_country_code": "BE",
                     "lines": [{ "product_id": UNIT_200, "quantity": "1" }] })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{u}");
    assert_eq!(u["warnings"][0]["details"]["status"], "incompatible");
    let (_, g) = api(
        &app,
        SALES,
        Method::GET,
        &format!("/quotations/{qid}"),
        None,
    )
    .await;
    assert!(g["warnings"].as_array().unwrap().is_empty());

    // Pricing preview.
    let preview = |extra: Value| {
        let mut body =
            json!({ "customer_id": ALPHA, "lines": [{ "product_id": UNIT_200, "quantity": "1" }] });
        for (k, v) in extra.as_object().unwrap() {
            body[k] = v.clone();
        }
        body
    };
    let (status, p) = api(
        &app,
        SALES,
        Method::POST,
        "/pricing/preview",
        Some(preview(json!({}))),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{p}");
    assert_eq!(warning_codes(&p), ["UNIT-200"]);
    let (_, p) = api(
        &app,
        SALES,
        Method::POST,
        "/pricing/preview",
        Some(preview(json!({ "purpose": "stock" }))),
    )
    .await;
    assert!(warning_codes(&p).is_empty());
    let (_, p) = api(
        &app,
        SALES,
        Method::POST,
        "/pricing/preview",
        Some(preview(json!({ "delivery_country_code": "US" }))),
    )
    .await;
    assert!(warning_codes(&p).is_empty());
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn stock_purpose_has_no_warnings(db: PgPool) {
    let app = setup(db).await;
    let (status, q) = quote(
        &app,
        &[UNIT_200, CTRL],
        json!({ "purpose": "stock", "delivery_country_code": "BE" }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{q}");
    assert!(warning_codes(&q).is_empty(), "{q}");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn power_grid_must_belong_to_the_delivery_country(db: PgPool) {
    let app = setup(db).await;
    let us = grid_id(&app, "US", 120, 1).await;
    let be = grid_id(&app, "BE", 230, 1).await;

    // The customer is Belgian, so the default delivery country is BE.
    let (status, r) = quote(&app, &[PUMP], json!({ "power_grid_id": us })).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{r}");
    let (status, r) = quote(
        &app,
        &[PUMP],
        json!({ "power_grid_id": "00000000-0000-7000-8000-0000000000ff" }),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{r}");
    let (status, q) = quote(&app, &[PUMP], json!({ "power_grid_id": be })).await;
    assert_eq!(status, StatusCode::CREATED, "{q}");
    assert_eq!(q["power_grid_id"], be);

    // Update: a wrong grid is rejected, a kept grid stays, a new country drops it.
    let qid = q["id"].as_str().unwrap();
    let uri = format!("/quotations/{qid}");
    let line = json!([{ "product_id": PUMP, "quantity": "1" }]);
    let (status, _) = api(
        &app,
        SALES,
        Method::PUT,
        &uri,
        Some(json!({ "customer_id": ALPHA, "power_grid_id": us, "lines": line })),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    let (_, u) = api(
        &app,
        SALES,
        Method::PUT,
        &uri,
        Some(json!({ "customer_id": ALPHA, "lines": line })),
    )
    .await;
    assert_eq!(u["power_grid_id"], be);
    let (_, u) = api(
        &app,
        SALES,
        Method::PUT,
        &uri,
        Some(json!({ "customer_id": ALPHA, "delivery_country_code": "US", "lines": line })),
    )
    .await;
    assert!(u["power_grid_id"].is_null());

    // With a chosen grid the check runs against that grid only: the pump does not fit BE 400V.
    let be400 = grid_id(&app, "BE", 400, 3).await;
    let (_, q) = quote(&app, &[PUMP], json!({ "power_grid_id": be400 })).await;
    assert_eq!(warning_codes(&q), ["PUMP-05"]);
}

async fn sent_quote(app: &axum::Router, grid: &str) -> String {
    let (_, q) = quote(app, &[PUMP], json!({ "power_grid_id": grid })).await;
    let qid = q["id"].as_str().unwrap().to_string();
    let (status, _) = api(
        app,
        SALES,
        Method::POST,
        &format!("/quotations/{qid}/send"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    qid
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn grid_is_copied_to_revisions_and_orders_and_confirm_warns(db: PgPool) {
    let app = setup(db).await;
    let be = grid_id(&app, "BE", 400, 3).await;

    for pricing in ["keep", "current"] {
        let qid = sent_quote(&app, &be).await;
        let (status, r) = api(
            &app,
            SALES,
            Method::POST,
            &format!("/quotations/{qid}/revise"),
            Some(json!({ "pricing": pricing })),
        )
        .await;
        assert_eq!(status, StatusCode::CREATED, "{r}");
        assert_eq!(r["power_grid_id"], be, "{pricing}");
    }

    let qid = sent_quote(&app, &be).await;
    let (status, o) = api(
        &app,
        SALES,
        Method::POST,
        &format!("/quotations/{qid}/convert"),
        Some(json!({ "customer_reference": "PO-1" })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{o}");
    assert_eq!(o["order"]["power_grid_id"], be);
    assert!(o["warnings"].as_array().unwrap().is_empty());

    let oid = o["order"]["id"].as_str().unwrap();
    let (status, _) = api(
        &app,
        SALES,
        Method::POST,
        &format!("/orders/{oid}/send"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (status, c) = api(
        &app,
        SALES,
        Method::POST,
        &format!("/orders/{oid}/confirm"),
        Some(json!({})),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{c}");
    assert_eq!(
        warning_codes(&c),
        ["PUMP-05"],
        "the pump does not fit the chosen 400V grid"
    );
    assert_eq!(c["warnings"][0]["kind"], "power_grid");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn voltage_bounds_roundtrip_validate_and_decide_compatibility(db: PgPool) {
    let app = setup(db.clone()).await;
    // Without bounds the fields are returned as null (backwards compatible).
    let (_, list) = api(
        &app,
        SALES,
        Method::GET,
        &format!("/products/{UNIT_100}/power-supplies"),
        None,
    )
    .await;
    assert!(list[0]["voltage_min_v"].is_null() && list[0]["voltage_max_v"].is_null());

    let (status, r) = put_supplies(
        &app,
        PUMP,
        json!([
            { "current_type": "ac", "voltage_v": 230, "phases": 1, "voltage_min_v": 200, "voltage_max_v": 260 },
            { "current_type": "dc", "voltage_v": 24, "voltage_min_v": 12, "voltage_max_v": 48 },
        ]),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{r}");
    let ac = r
        .as_array()
        .unwrap()
        .iter()
        .find(|s| s["current_type"] == "ac")
        .unwrap();
    assert_eq!(
        (&ac["voltage_min_v"], &ac["voltage_max_v"]),
        (&json!(200), &json!(260))
    );
    let dc = r
        .as_array()
        .unwrap()
        .iter()
        .find(|s| s["current_type"] == "dc")
        .unwrap();
    assert_eq!(
        (&dc["voltage_min_v"], &dc["voltage_max_v"]),
        (&json!(12), &json!(48))
    );

    // A 200 V grid is outside 230 +/- 10% but inside the explicit range.
    let (status, g) = api(
        &app,
        ADMIN,
        Method::POST,
        "/power-grids",
        Some(json!({ "country_code": "BE", "voltage_v": 200, "phases": 1, "frequency_hz": 50 })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{g}");
    let g200 = g["id"].as_str().unwrap().to_string();
    assert_eq!(
        compat(&app, PUMP, &format!("grid_id={g200}")).await["status"],
        "compatible"
    );
    // Same product without the bounds is incompatible with that grid.
    put_supplies(
        &app,
        PUMP,
        json!([{ "current_type": "ac", "voltage_v": 230, "phases": 1 }]),
    )
    .await;
    assert_eq!(
        compat(&app, PUMP, &format!("grid_id={g200}")).await["status"],
        "incompatible"
    );

    let base = json!({ "current_type": "ac", "voltage_v": 230, "phases": 1 });
    for (lo, hi) in [
        (json!(200), json!(null)),
        (json!(null), json!(260)),
        (json!(260), json!(200)),
        (json!(0), json!(260)),
        (json!(240), json!(260)),
        (json!(200), json!(220)),
    ] {
        let mut s = base.clone();
        s["voltage_min_v"] = lo.clone();
        s["voltage_max_v"] = hi.clone();
        let (status, r) = put_supplies(&app, PUMP, json!([s])).await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{lo} {hi} -> {r}");
    }

    // The database enforces the same rules.
    for (lo, hi) in [
        ("200", "NULL"),
        ("NULL", "260"),
        ("260", "200"),
        ("0", "260"),
        ("240", "260"),
    ] {
        let r = sqlx::query(&format!(
            "INSERT INTO products.product_power_supplies
                (id, product_id, current_type, voltage_v, phases, voltage_min_v, voltage_max_v)
             VALUES (gen_random_uuid(), '{BOLT}', 'ac', 230, 1, {lo}, {hi})"
        ))
        .execute(&db)
        .await;
        assert!(r.is_err(), "{lo}..{hi} should violate the check constraint");
    }
}
