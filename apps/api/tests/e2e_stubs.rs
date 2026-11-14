//! Boundaries of modules that do not exist yet: quality, finance and profitability reporting (and
//! the automatic purchase of shortfalls). Production exists (ADR 0036, 0062) but has no endpoint called
//! a work order. Each stub asserts only what is honestly observable today (the
//! endpoints are absent, state does not advance, no such data appears) and says what concrete
//! step replaces it when the module ships.

mod common;

use axum::http::{Method, StatusCode};
use common::e2e::*;
use common::{call, setup};
use serde_json::{json, Value};
use sqlx::PgPool;

const SALES: &str = "sales@example.com";
const ADMIN: &str = "admin@example.com";
const ALPHA: &str = "00000000-0000-7000-8000-000000000401";
const FRAME: &str = "00000000-0000-7000-8000-000000000307";

async fn api(
    app: &axum::Router,
    user: &str,
    method: Method,
    uri: &str,
    body: Option<Value>,
) -> (StatusCode, Value) {
    call(app, user, method, &format!("/api/v1{uri}"), body).await
}

/// A confirmed order for 5 frames, none of which are in stock.
async fn confirmed_order(app: &axum::Router) -> (E2eFlow, Value) {
    let mut flow = E2eFlow::new();
    let (status, q) = api(
        app,
        SALES,
        Method::POST,
        "/quotations",
        Some(json!({ "customer_id": ALPHA, "lines": [{ "product_id": FRAME, "quantity": "5" }] })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{q}");
    let qid = q["id"].as_str().unwrap();
    api(
        app,
        SALES,
        Method::POST,
        &format!("/quotations/{qid}/send"),
        None,
    )
    .await;
    let (_, o) = api(
        app,
        SALES,
        Method::POST,
        &format!("/quotations/{qid}/convert"),
        Some(json!({})),
    )
    .await;
    let oid = o["order"]["id"].as_str().unwrap().to_string();
    api(
        app,
        SALES,
        Method::POST,
        &format!("/orders/{oid}/send"),
        None,
    )
    .await;
    let (status, c) = api(
        app,
        SALES,
        Method::POST,
        &format!("/orders/{oid}/confirm"),
        Some(json!({})),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{c}");
    flow.order_id = Some(oid);
    (flow, c)
}

async fn absent(app: &axum::Router, paths: &[&str]) {
    for p in paths {
        for method in [Method::GET, Method::POST] {
            let body = (method == Method::POST).then(|| json!({}));
            let (status, _) = api(app, ADMIN, method.clone(), p, body).await;
            assert_eq!(
                status,
                StatusCode::NOT_FOUND,
                "{method} {p} exists now: replace this stub"
            );
        }
    }
}

/// Every key of a JSON document, recursively, lower-cased.
fn keys(v: &Value, out: &mut Vec<String>) {
    match v {
        Value::Object(m) => {
            for (k, x) in m {
                out.push(k.to_lowercase());
                keys(x, out);
            }
        }
        Value::Array(a) => a.iter().for_each(|x| keys(x, out)),
        _ => {}
    }
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn purchasing_stub_a_shortfall_creates_no_purchase(db: PgPool) {
    let app = setup(db.clone()).await;
    let (flow, _) = confirmed_order(&app).await;
    let oid = flow.order_id.unwrap();

    // Stub: nothing buys on a shortfall yet. When it does, this becomes a step that
    // purchases the unavailable components (Requirement 10.4). Today the shortfall is only
    // reported by the inventory availability, and nothing is bought or booked.
    let (status, a) = api(
        &app,
        SALES,
        Method::GET,
        &format!("/inventory/orders/{oid}/availability"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{a}");
    assert_eq!(a["lines"][0]["state"], "short", "{a}");
    assert_eq!(
        common::dec(&a["lines"][0]["shortfall"]),
        "5".parse().unwrap()
    );
    let moves: i64 = sqlx::query_scalar("SELECT count(*) FROM inventory.stock_moves")
        .fetch_one(&db)
        .await
        .unwrap();
    assert_eq!(moves, 0, "nothing was received or booked");
    // Purchasing ships purchase orders and suppliers (ADR 0031, tests/purchasing.rs); only the
    // automatic purchase of a shortfall is still missing.
    absent(&app, &["/purchasing/orders", "/purchasing/shortfalls"]).await;
}

/// Production ships (ADR 0036, tests/production.rs): a confirmed order does not advance by itself,
/// a planner releases it, and building it makes it ready for shipping. Routings and operations
/// (C1b, ADR 0062, tests/production_routing.rs) are optional on top of that and live under other paths:
/// there is still no `/work-orders` or `/production/orders`.
#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn production_a_confirmed_order_is_built_before_it_is_ready_for_shipping(db: PgPool) {
    const PLANNER: &str = "production@example.com";
    const PROFILE: &str = "00000000-0000-7000-8000-000000000308";
    const BOLT: &str = "00000000-0000-7000-8000-000000000309";
    let app = setup(db).await;
    let (flow, confirmed) = confirmed_order(&app).await;
    let order = flow.order_id.clone().unwrap();
    let line = confirmed["lines"][0]["id"].as_str().unwrap().to_string();
    assert_eq!(confirmed["order"]["status"], "confirmed");

    // Nothing happens by itself: the planner sees the line and releases it.
    let (_, queue) = api(&app, PLANNER, Method::GET, "/production-orders", None).await;
    assert_eq!(queue["total"], 0);
    let (_, todo) = api(&app, PLANNER, Method::GET, "/production/to-release", None).await;
    assert!(todo
        .as_array()
        .unwrap()
        .iter()
        .any(|t| t["order_line_id"] == line.as_str()
            && common::dec(&t["to_build"]) == rust_decimal::Decimal::from(5)));
    let (status, po) = api(
        &app,
        PLANNER,
        Method::POST,
        "/production-orders",
        Some(json!({ "order_id": order, "order_line_id": line })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{po}");
    assert_eq!(po["short_components"], 2, "none of the parts are in stock");
    let status_of = |o: Value| o["order"]["status"].as_str().unwrap().to_string();
    let order_uri = format!("/orders/{order}");
    let get_order = || api(&app, SALES, Method::GET, &order_uri, None);
    assert_eq!(status_of(get_order().await.1), "in_planning");

    // The parts arrive, the components are reserved, a date makes it planned.
    let (status, w) = api(
        &app,
        ADMIN,
        Method::POST,
        "/inventory/warehouses",
        Some(json!({ "code": "WH1", "name": "Main" })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{w}");
    let location = w["locations"][0]["id"].as_str().unwrap().to_string();
    for (product, quantity) in [(PROFILE, "50"), (BOLT, "200")] {
        let (status, r) = api(
            &app,
            ADMIN,
            Method::POST,
            "/inventory/receipts",
            Some(json!({ "id": uuid::Uuid::now_v7(), "product_id": product, "location_id": location, "quantity": quantity })),
        )
        .await;
        assert_eq!(status, StatusCode::CREATED, "{r}");
    }
    let n = po["id"].as_str().unwrap().to_string();
    let (_, again) = api(
        &app,
        PLANNER,
        Method::POST,
        &format!("/production-orders/{n}/reserve"),
        Some(json!({})),
    )
    .await;
    assert_eq!(again["short_components"], 0, "{again}");
    api(
        &app,
        PLANNER,
        Method::PUT,
        &format!("/production-orders/{n}"),
        Some(json!({ "planned_ready_date": "2099-07-01" })),
    )
    .await;
    let ordered = get_order().await.1;
    assert_eq!(ordered["order"]["promised_date"], "2099-07-01");
    assert_eq!(status_of(ordered), "planned");

    // Building it makes the order ready for shipping.
    let (status, done) = api(
        &app,
        PLANNER,
        Method::POST,
        &format!("/production-orders/{n}/complete"),
        Some(json!({ "output": { "quantity": "5", "location_id": location } })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{done}");
    assert_eq!(status_of(get_order().await.1), "ready_for_shipping");
    absent(&app, &["/work-orders", "/production/orders"]).await;
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn quality_stub_no_inspection_endpoints_exist(db: PgPool) {
    let app = setup(db).await;
    // Stub: the quality module does not exist. When it ships, record at least one inspection
    // result with a pass/fail outcome (Requirement 10.6). A serial unit shows no quality data.
    absent(
        &app,
        &["/inspections", "/quality/inspections", "/non-conformances"],
    )
    .await;
    let (_, d) = api(
        &app,
        ADMIN,
        Method::GET,
        "/serials/00000000-0000-7000-8000-000000000601",
        None,
    )
    .await;
    let mut k = Vec::new();
    keys(&d, &mut k);
    assert!(
        k.iter()
            .all(|k| !k.contains("inspection") && !k.contains("quality")),
        "{k:?}"
    );
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn finance_stub_a_confirmed_order_produces_no_invoice(db: PgPool) {
    let app = setup(db).await;
    let (flow, confirmed) = confirmed_order(&app).await;

    // Stub: the finance module does not exist. When it ships, generate at least one invoice in
    // each of at least two currencies (Requirement 10.7). Today the order carries only its own
    // currency and totals, and no invoice endpoint exists.
    let mut k = Vec::new();
    keys(&confirmed, &mut k);
    assert!(k.iter().all(|k| !k.contains("invoice")), "{k:?}");
    assert_eq!(confirmed["order"]["currency"], "EUR");
    let (_, list) = api(
        &app,
        SALES,
        Method::GET,
        &format!(
            "/orders?q={}",
            confirmed["order"]["number"].as_str().unwrap()
        ),
        None,
    )
    .await;
    assert_eq!(list["total"], 1);
    assert_eq!(flow.order_id.as_deref(), confirmed["order"]["id"].as_str());
    absent(&app, &["/invoices", "/finance/invoices", "/payments"]).await;
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn profitability_stub_no_report_is_produced(db: PgPool) {
    let app = setup(db).await;
    let (_, confirmed) = confirmed_order(&app).await;

    // Stub: profitability reporting does not exist; a report is produced only once it does.
    // Orders carry no cost or margin figures and no report route is served.
    let mut k = Vec::new();
    keys(&confirmed, &mut k);
    assert!(
        k.iter()
            .all(|k| !k.contains("margin") && !k.contains("profit") && !k.contains("cost")),
        "{k:?}"
    );
    absent(
        &app,
        &[
            "/reports/profitability",
            "/profitability",
            "/reports/margins",
        ],
    )
    .await;
}
