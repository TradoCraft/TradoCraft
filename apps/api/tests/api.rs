//! End-to-end API tests against a real PostgreSQL database.
//! `sqlx::test` creates a fresh database per test (needs DATABASE_URL pointing at a server
//! where the user may create databases).

mod common;

use axum::body::Body;
use axum::http::{Method, Request, StatusCode};
use common::{call, dec, setup};
use http_body_util::BodyExt;
use serde_json::{json, Value};
use sqlx::PgPool;
use tower::ServiceExt;

const ALPHA: &str = "00000000-0000-7000-8000-000000000401"; // zone Z2, 5 % discount
const UNIT_100: &str = "00000000-0000-7000-8000-000000000301"; // Z2 price 3880.00
const HOSE_25: &str = "00000000-0000-7000-8000-000000000304"; // Z2 price 9.92
const ZONE_Z2: &str = "00000000-0000-7000-8000-000000000202";

fn quote_body() -> Value {
    json!({
        "customer_id": ALPHA,
        "quote_date": "2026-11-05",
        "vat_regime_override": "domestic",
        "lines": [
            { "product_id": UNIT_100, "quantity": "2", "line_discount_percent": "3" },
            { "product_id": HOSE_25, "quantity": "12.5" }
        ]
    })
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn unauthenticated_requests_are_rejected(db: PgPool) {
    let app = setup(db).await;
    let (status, _) = call(&app, "nobody@example.com", Method::GET, "/api/v1/me", None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn quotation_is_priced_from_zone_with_cascading_discounts(db: PgPool) {
    let app = setup(db).await;
    let (status, q) = call(
        &app,
        "sales@example.com",
        Method::POST,
        "/api/v1/quotations",
        Some(quote_body()),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{q}");
    assert_eq!(q["number"], "Q2026-00001");
    assert_eq!(q["price_zone_code"], "Z2");
    // 3880 * 0.95 * 0.97 * 2 = 7150.84 ; 9.92 * 0.95 * 12.5 = 117.80
    assert_eq!(
        dec(&q["lines"][0]["line_total"]),
        "7150.84".parse().unwrap()
    );
    assert_eq!(dec(&q["lines"][1]["line_total"]), "117.80".parse().unwrap());
    assert_eq!(dec(&q["subtotal"]), "7268.64".parse().unwrap());
    assert_eq!(dec(&q["vat_total"]), "1526.41".parse().unwrap());
    assert_eq!(dec(&q["total"]), "8795.05".parse().unwrap());

    // Numbering continues per company and year.
    let (_, q2) = call(
        &app,
        "sales@example.com",
        Method::POST,
        "/api/v1/quotations",
        Some(quote_body()),
    )
    .await;
    assert_eq!(q2["number"], "Q2026-00002");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn sent_quotation_is_a_frozen_snapshot(db: PgPool) {
    let app = setup(db).await;
    let (_, q) = call(
        &app,
        "sales@example.com",
        Method::POST,
        "/api/v1/quotations",
        Some(quote_body()),
    )
    .await;
    let id = q["id"].as_str().unwrap();

    let (status, sent) = call(
        &app,
        "sales@example.com",
        Method::POST,
        &format!("/api/v1/quotations/{id}/send"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(sent["status"], "sent");

    // Editing a sent quotation is refused.
    let (status, _) = call(
        &app,
        "sales@example.com",
        Method::PUT,
        &format!("/api/v1/quotations/{id}"),
        Some(quote_body()),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);

    // A price increase does not change the sent quotation.
    let (status, _) = call(
        &app,
        "admin@example.com",
        Method::POST,
        &format!("/api/v1/products/{UNIT_100}/prices"),
        Some(json!({ "zone_id": ZONE_Z2, "unit_price": "4000.00", "valid_from": "2026-11-01" })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);
    let (_, again) = call(
        &app,
        "sales@example.com",
        Method::GET,
        &format!("/api/v1/quotations/{id}"),
        None,
    )
    .await;
    assert_eq!(again["total"], sent["total"]);
    assert_eq!(
        dec(&again["lines"][0]["list_unit_price"]),
        "3880".parse().unwrap()
    );

    // A revision at current prices keeps the number, reprices and supersedes the original.
    let (status, rev) = call(
        &app,
        "sales@example.com",
        Method::POST,
        &format!("/api/v1/quotations/{id}/revise"),
        Some(json!({ "pricing": "current" })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{rev}");
    assert_eq!(rev["number"], q["number"]);
    assert_eq!(rev["revision"], 2);
    assert_eq!(rev["status"], "draft");
    assert_eq!(
        dec(&rev["lines"][0]["list_unit_price"]),
        "4000".parse().unwrap()
    );
    let (_, old) = call(
        &app,
        "sales@example.com",
        Method::GET,
        &format!("/api/v1/quotations/{id}"),
        None,
    )
    .await;
    assert_eq!(old["status"], "superseded");

    // Accepting a superseded quotation is refused.
    let (status, _) = call(
        &app,
        "sales@example.com",
        Method::POST,
        &format!("/api/v1/quotations/{id}/accept"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn permissions_are_enforced(db: PgPool) {
    let app = setup(db).await;
    let (status, _) = call(
        &app,
        "viewer@example.com",
        Method::POST,
        "/api/v1/quotations",
        Some(quote_body()),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, _) = call(
        &app,
        "sales@example.com",
        Method::POST,
        &format!("/api/v1/products/{UNIT_100}/prices"),
        Some(json!({ "zone_id": ZONE_Z2, "unit_price": "1.00", "valid_from": "2026-11-01" })),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN, "sales may not change prices");
    let (status, _) = call(
        &app,
        "viewer@example.com",
        Method::GET,
        "/api/v1/quotations",
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn quoting_without_a_price_is_a_validation_error(db: PgPool) {
    let app = setup(db).await;
    let (status, p) = call(
        &app,
        "admin@example.com",
        Method::POST,
        "/api/v1/products",
        Some(json!({ "code": "NEW-1", "name": "Unpriced", "vat_rate": "21" })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);
    let (status, err) = call(
        &app,
        "sales@example.com",
        Method::POST,
        "/api/v1/pricing/preview",
        Some(
            json!({ "customer_id": ALPHA, "lines": [{ "product_id": p["id"], "quantity": "1" }] }),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    assert!(
        err["message"]
            .as_str()
            .unwrap()
            .contains("no price in price zone Z2"),
        "{err}"
    );
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn duplicate_customer_code_is_a_conflict(db: PgPool) {
    let app = setup(db).await;
    let body = json!({ "code": "C0001", "name": "Duplicate", "price_zone_id": ZONE_Z2 });
    let (status, _) = call(
        &app,
        "sales@example.com",
        Method::POST,
        "/api/v1/customers",
        Some(body),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn quotation_pdf_is_rendered(db: PgPool) {
    if std::process::Command::new(std::env::var("TYPST_BIN").unwrap_or_else(|_| "typst".into()))
        .arg("--version")
        .output()
        .is_err()
    {
        eprintln!("typst not installed; skipping PDF test");
        return;
    }
    let app = setup(db).await;
    let (_, q) = call(
        &app,
        "sales@example.com",
        Method::POST,
        "/api/v1/quotations",
        Some(quote_body()),
    )
    .await;
    let req = Request::builder()
        .uri(format!(
            "/api/v1/quotations/{}/pdf",
            q["id"].as_str().unwrap()
        ))
        .header("x-dev-user", "sales@example.com")
        .body(Body::empty())
        .unwrap();
    let res = app.oneshot(req).await.unwrap();
    assert_eq!(res.status(), StatusCode::OK);
    let bytes = res.into_body().collect().await.unwrap().to_bytes();
    assert!(bytes.starts_with(b"%PDF"));
}

#[test]
fn openapi_document_lists_all_endpoints() {
    let doc = serde_json::to_value(tradocraft_api::openapi()).unwrap();
    let paths = doc["paths"].as_object().unwrap();
    for p in [
        "/api/v1/me",
        "/api/v1/customers",
        "/api/v1/products/{id}/prices",
        "/api/v1/quotations/{id}/revise",
        "/api/v1/quotations/configured",
        "/api/v1/products/{id}/translations",
        "/api/v1/products/{id}/remark-history",
        "/api/v1/products/{id}/options",
        "/api/v1/products/{id}/attributes",
        "/api/v1/configurator/models/import",
        "/api/v1/configurator/revisions/{id}/evaluate",
        "/api/v1/configurator/configurations/{id}/quote",
        "/api/v1/pricing/preview",
    ] {
        assert!(paths.contains_key(p), "missing {p}");
    }
}
