//! Range attributes on products and validation against attribute definitions (ADR 0068).

mod common;

use axum::http::{Method, StatusCode};
use common::{call, setup};
use serde_json::{json, Value};
use sqlx::PgPool;

const ADMIN: &str = "admin@example.com";
const SALES: &str = "sales@example.com";
const PRODUCT: &str = "00000000-0000-7000-8000-0000000003d1";

fn uri() -> String {
    format!("/api/v1/products/{PRODUCT}/attributes")
}

async fn put(app: &axum::Router, body: Value) -> (StatusCode, Value) {
    call(app, ADMIN, Method::PUT, &uri(), Some(body)).await
}

fn range(key: &str, min: &str, max: &str) -> Value {
    json!({ "key": key, "kind": "range", "value": "", "value_min": min, "value_max": max, "unit": "mm" })
}

async fn define(app: &axum::Router, body: Value) {
    let (status, d) = call(
        app,
        ADMIN,
        Method::POST,
        "/api/v1/attribute-definitions",
        Some(body),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{d}");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn range_roundtrip_and_replace_all(db: PgPool) {
    let app = setup(db).await;
    let (status, saved) = put(
        &app,
        json!([
            range("dial_size", "600", "1250.50"),
            { "key": "kw", "kind": "number", "value": "0.55", "unit": "kW" },
        ]),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{saved}");
    assert_eq!(
        saved[0],
        json!({ "key": "dial_size", "kind": "range", "value": "600..1250.5",
                "value_min": "600", "value_max": "1250.5", "unit": "mm" })
    );
    // Other kinds do not show bounds at all.
    assert_eq!(
        saved[1],
        json!({ "key": "kw", "kind": "number", "value": "0.55", "unit": "kW" })
    );
    let (_, got) = call(&app, SALES, Method::GET, &uri(), None).await;
    assert_eq!(got, saved);

    // Replace-all: the range is gone when left out, and a key can change kind.
    let (status, saved) = put(
        &app,
        json!([{ "key": "dial_size", "kind": "number", "value": "700" }]),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{saved}");
    assert_eq!(saved.as_array().unwrap().len(), 1);
    assert_eq!(saved[0]["kind"], "number");
    let (status, saved) = put(&app, json!([])).await;
    assert_eq!(status, StatusCode::OK);
    assert!(saved.as_array().unwrap().is_empty());
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn invalid_ranges_are_rejected_and_leave_data_untouched(db: PgPool) {
    let app = setup(db.clone()).await;
    put(&app, json!([range("dial_size", "1", "2")])).await;
    for bad in [
        json!([{ "key": "d", "kind": "range", "value": "", "value_min": "1" }]),
        json!([{ "key": "d", "kind": "range", "value": "", "value_max": "1" }]),
        json!([{ "key": "d", "kind": "range", "value": "1" }]),
        json!([range("d", "5", "4")]),
        json!([range("d", "a", "4")]),
        json!([{ "key": "d", "kind": "number", "value": "1", "value_min": "1" }]),
        json!([{ "key": "d", "kind": "text", "value": "x", "value_max": "1" }]),
    ] {
        let (status, r) = put(&app, bad.clone()).await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{bad} -> {r}");
    }
    let (_, got) = call(&app, SALES, Method::GET, &uri(), None).await;
    assert_eq!(got[0]["key"], "dial_size");

    // The database refuses inconsistent rows too.
    for (kind, cols) in [
        (
            "range",
            "value_min, value_max) VALUES ($1, 'x', 'range', 5, 4",
        ),
        ("range", "value_min) VALUES ($1, 'x', 'range', 5"),
        (
            "number",
            "value_number, value_min) VALUES ($1, 'x', 'number', 1, 1",
        ),
    ] {
        let r = sqlx::query(&format!(
            "INSERT INTO products.product_attributes (product_id, key, kind, {cols})"
        ))
        .bind(uuid::Uuid::parse_str(PRODUCT).unwrap())
        .execute(&db)
        .await;
        assert!(r.is_err(), "{kind}: {cols}");
    }
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn definitions_decide_the_kind_but_undefined_keys_stay_free(db: PgPool) {
    let app = setup(db).await;
    define(
        &app,
        json!({ "key": "dial_size", "label": "Dial size", "kind": "range", "unit": "mm" }),
    )
    .await;
    define(
        &app,
        json!({ "key": "motion", "label": "Motion", "kind": "select",
                "options": [{ "value": "flying", "label": "Flying" }] }),
    )
    .await;
    define(
        &app,
        json!({ "key": "weight", "label": "Weight", "kind": "number", "scope": "bell" }),
    )
    .await;

    // A matching kind passes; a key without a definition is unrestricted; a definition of
    // another scope (a baseline item type) does not apply to products.
    let (status, r) = put(
        &app,
        json!([
            range("dial_size", "600", "1250"),
            { "key": "motion", "kind": "text", "value": "flying" },
            { "key": "legacy_note", "kind": "boolean", "value": "true" },
            { "key": "weight", "kind": "text", "value": "heavy" },
        ]),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{r}");

    for bad in [
        json!([{ "key": "dial_size", "kind": "number", "value": "700" }]),
        json!([{ "key": "dial_size", "kind": "text", "value": "big" }]),
        json!([{ "key": "motion", "kind": "text", "value": "falling" }]),
        json!([{ "key": "motion", "kind": "number", "value": "1" }]),
        json!([{ "key": "motion", "kind": "boolean", "value": "true" }]),
    ] {
        let (status, r) = put(&app, bad.clone()).await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{bad} -> {r}");
    }
}
