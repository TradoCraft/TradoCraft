//! Inventory: receive stock and explode a multi-level BOM.

mod common;

use axum::http::{Method, StatusCode};
use common::{call, dec, setup};
use rust_decimal::Decimal;
use serde_json::{json, Value};
use sqlx::PgPool;
use uuid::Uuid;

const ADMIN: &str = "admin@example.com";
const SALES: &str = "sales@example.com";
const STORES: &str = "stores@example.com";
const COMPANY: &str = "00000000-0000-7000-8000-000000000001";
const UNIT_100: &str = "00000000-0000-7000-8000-000000000301";
const FRAME: &str = "00000000-0000-7000-8000-000000000307";

fn q(s: &str) -> Decimal {
    s.parse().unwrap()
}

async fn api(
    app: &axum::Router,
    user: &str,
    method: Method,
    uri: &str,
    body: Option<Value>,
) -> (StatusCode, Value) {
    call(app, user, method, &format!("/api/v1{uri}"), body).await
}

/// Setup: a warehouse (admin) with its default location, and a stores user.
async fn warehouse(app: &axum::Router, db: &PgPool) -> String {
    let id = Uuid::now_v7();
    sqlx::query("INSERT INTO core.users (id, email, display_name) VALUES ($1, $2, $2)")
        .bind(id)
        .bind(STORES)
        .execute(db)
        .await
        .unwrap();
    sqlx::query("INSERT INTO core.user_companies (user_id, company_id, roles, is_default) VALUES ($1, $2::uuid, $3, true)")
        .bind(id)
        .bind(COMPANY)
        .bind(vec!["warehouse".to_string()])
        .execute(db)
        .await
        .unwrap();
    let (status, w) = api(
        app,
        ADMIN,
        Method::POST,
        "/inventory/warehouses",
        Some(json!({ "code": "WH1", "name": "Main warehouse" })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{w}");
    w["locations"][0]["id"].as_str().unwrap().to_string()
}

async fn receive(app: &axum::Router, location: &str, quantity: &str) -> Value {
    let (status, m) = api(
        app,
        STORES,
        Method::POST,
        "/inventory/receipts",
        Some(json!({ "id": Uuid::now_v7(), "product_id": FRAME, "location_id": location, "quantity": quantity })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{m}");
    m
}

async fn totals(app: &axum::Router) -> (Decimal, Decimal, Decimal) {
    let (status, p) = api(
        app,
        ADMIN,
        Method::GET,
        &format!("/inventory/stock/products?product_id={FRAME}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{p}");
    let i = &p["items"][0];
    (
        dec(&i["on_hand"]),
        dec(&i["reserved"]),
        dec(&i["available"]),
    )
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn receiving_stock_updates_the_balance_and_the_ledger(db: PgPool) {
    let app = setup(db.clone()).await;
    let main = warehouse(&app, &db).await;

    let m = receive(&app, &main, "12").await;
    assert_eq!(m["kind"], "receipt");
    assert_eq!(dec(&m["quantity"]), q("12"));
    assert_eq!(totals(&app).await.0, q("12"), "on hand equals the receipt");

    let (status, ledger) = api(
        &app,
        ADMIN,
        Method::GET,
        &format!("/inventory/moves?product_id={FRAME}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{ledger}");
    assert_eq!(ledger["total"], 1);
    let entry = &ledger["items"][0];
    assert_eq!(entry["kind"], "receipt");
    assert_eq!(entry["product_id"], FRAME);
    assert_eq!(dec(&entry["quantity"]), q("12"));

    // A receipt must be positive.
    let (status, _) = api(
        &app,
        STORES,
        Method::POST,
        "/inventory/receipts",
        Some(json!({ "id": Uuid::now_v7(), "product_id": FRAME, "location_id": main, "quantity": "0" })),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    let (_, i) = api(&app, ADMIN, Method::GET, "/inventory/integrity", None).await;
    assert_eq!(i["ok"], true, "{i}");
}

/// (code, level, required quantity) per node, in the order of the explosion.
fn nodes(e: &Value) -> Vec<(String, i64, Decimal)> {
    e["nodes"]
        .as_array()
        .unwrap()
        .iter()
        .map(|n| {
            (
                n["code"].as_str().unwrap().to_string(),
                n["level"].as_i64().unwrap(),
                dec(&n["required_quantity"]).normalize(),
            )
        })
        .collect()
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn bom_explosion_covers_every_level_and_is_repeatable(db: PgPool) {
    let app = setup(db).await;
    let uri = format!("/products/{UNIT_100}/bom/explode?quantity=3");
    let (status, first) = api(&app, SALES, Method::GET, &uri, None).await;
    assert_eq!(status, StatusCode::OK, "{first}");

    let n = nodes(&first);
    let levels: Vec<i64> = n.iter().map(|x| x.1).collect();
    assert!(
        levels.contains(&1) && levels.contains(&2),
        "two levels: {levels:?}"
    );
    // Every component of both BOM levels, including the leaves, has a node.
    for code in ["FRAME-A", "PUMP-05", "CTRL-01", "BOLT-M8", "PROFILE-40"] {
        assert!(n.iter().any(|x| x.0 == code), "{code} missing in {n:?}");
    }
    // 3 units: 6 pumps (level 1), 3 frames, 3 x 6.5 m x 1.10 scrap = 21.45 m profile (level 2).
    assert!(n.contains(&("PUMP-05".into(), 1, q("6"))));
    assert!(n.contains(&("FRAME-A".into(), 1, q("3"))));
    assert!(n.contains(&("PROFILE-40".into(), 2, q("21.45"))));

    // Exploding the same BOM again gives the same components and quantities.
    let (_, second) = api(&app, SALES, Method::GET, &uri, None).await;
    assert_eq!(nodes(&second), n);
    assert_eq!(first["requirements"], second["requirements"]);
}
