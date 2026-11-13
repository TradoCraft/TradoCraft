//! Concurrent-edit protection (ADR 0060): customers, quotations and orders carry a row version;
//! a save made from an older version is refused with 409 `record_changed`, a save without one
//! behaves as before, and two saves that start from the same version cannot both succeed.

mod common;

use axum::http::{Method, StatusCode};
use common::{call, setup};
use serde_json::{json, Value};
use sqlx::PgPool;

const SALES: &str = "sales@example.com";
const ALPHA: &str = "00000000-0000-7000-8000-000000000401";
const UNIT: &str = "00000000-0000-7000-8000-000000000301";
const ZONE_Z2: &str = "00000000-0000-7000-8000-000000000202";

async fn api(
    app: &axum::Router,
    method: Method,
    uri: &str,
    body: Option<Value>,
) -> (StatusCode, Value) {
    call(app, SALES, method, &format!("/api/v1{uri}"), body).await
}

fn version(v: &Value) -> i64 {
    v["version"].as_i64().expect("a version")
}

fn customer_body(name: &str, expected: Option<i64>) -> Value {
    let mut b = json!({ "code": "C0001", "name": name, "price_zone_id": ZONE_Z2 });
    if let Some(e) = expected {
        b["expected_version"] = json!(e);
    }
    b
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_stale_customer_save_is_refused_and_a_fresh_one_goes_through(db: PgPool) {
    let app = setup(db).await;
    let (status, loaded) = api(&app, Method::GET, &format!("/customers/{ALPHA}"), None).await;
    assert_eq!(status, StatusCode::OK, "{loaded}");
    let v0 = version(&loaded);

    // The first save from this version wins and raises the version.
    let (status, saved) = api(
        &app,
        Method::PUT,
        &format!("/customers/{ALPHA}"),
        Some(customer_body("Alpha One", Some(v0))),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{saved}");
    assert!(version(&saved) > v0);

    // A second save from the same (now stale) version is refused and changes nothing.
    let (status, refused) = api(
        &app,
        Method::PUT,
        &format!("/customers/{ALPHA}"),
        Some(customer_body("Alpha Two", Some(v0))),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT, "{refused}");
    assert_eq!(refused["code"], "record_changed");
    let (_, now) = api(&app, Method::GET, &format!("/customers/{ALPHA}"), None).await;
    assert_eq!(now["name"], "Alpha One");
    assert_eq!(
        version(&now),
        version(&saved),
        "a refused save is not a change"
    );

    // Reloading and saving again works.
    let (status, again) = api(
        &app,
        Method::PUT,
        &format!("/customers/{ALPHA}"),
        Some(customer_body("Alpha Two", Some(version(&now)))),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{again}");
    assert_eq!(again["name"], "Alpha Two");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_save_without_a_version_is_not_checked(db: PgPool) {
    let app = setup(db).await;
    for name in ["Alpha One", "Alpha Two"] {
        let (status, saved) = api(
            &app,
            Method::PUT,
            &format!("/customers/{ALPHA}"),
            Some(customer_body(name, None)),
        )
        .await;
        assert_eq!(status, StatusCode::OK, "{saved}");
    }
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn two_simultaneous_customer_saves_give_one_success_and_one_conflict(db: PgPool) {
    let app = setup(db).await;
    let (_, loaded) = api(&app, Method::GET, &format!("/customers/{ALPHA}"), None).await;
    let v0 = version(&loaded);
    let save = |name: &'static str| {
        let app = app.clone();
        async move {
            api(
                &app,
                Method::PUT,
                &format!("/customers/{ALPHA}"),
                Some(customer_body(name, Some(v0))),
            )
            .await
            .0
        }
    };
    let (a, b) = tokio::join!(save("Left"), save("Right"));
    let mut statuses = [a, b];
    statuses.sort();
    assert_eq!(statuses, [StatusCode::OK, StatusCode::CONFLICT]);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_version_moves_on_every_kind_of_update(db: PgPool) {
    // The trigger raises it for any UPDATE, also one that does not set `updated_at`.
    let app = setup(db.clone()).await;
    let (_, before) = api(&app, Method::GET, &format!("/customers/{ALPHA}"), None).await;
    sqlx::query("UPDATE crm.customers SET phone = '+32 1' WHERE id = $1")
        .bind(uuid::Uuid::parse_str(ALPHA).unwrap())
        .execute(&db)
        .await
        .unwrap();
    let (_, after) = api(&app, Method::GET, &format!("/customers/{ALPHA}"), None).await;
    assert_eq!(version(&after), version(&before) + 1);
}

fn quotation_body(notes: &str, expected: Option<i64>) -> Value {
    let mut b = json!({
        "customer_id": ALPHA,
        "notes": notes,
        "lines": [{ "product_id": UNIT, "quantity": "1" }],
    });
    if let Some(e) = expected {
        b["expected_version"] = json!(e);
    }
    b
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_stale_quotation_save_is_refused(db: PgPool) {
    let app = setup(db).await;
    let (status, q) = api(
        &app,
        Method::POST,
        "/quotations",
        Some(quotation_body("first", None)),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{q}");
    let id = q["id"].as_str().unwrap().to_string();
    let v0 = version(&q);

    let (status, saved) = api(
        &app,
        Method::PUT,
        &format!("/quotations/{id}"),
        Some(quotation_body("by Anna", Some(v0))),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{saved}");
    assert!(version(&saved) > v0);

    let (status, refused) = api(
        &app,
        Method::PUT,
        &format!("/quotations/{id}"),
        Some(quotation_body("by Ben", Some(v0))),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT, "{refused}");
    assert_eq!(refused["code"], "record_changed");

    let (_, now) = api(&app, Method::GET, &format!("/quotations/{id}"), None).await;
    assert_eq!(now["notes"], "by Anna");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_stale_order_save_is_refused(db: PgPool) {
    let app = setup(db).await;
    let (_, q) = api(
        &app,
        Method::POST,
        "/quotations",
        Some(quotation_body("", None)),
    )
    .await;
    let qid = q["id"].as_str().unwrap().to_string();
    let (status, _) = api(&app, Method::POST, &format!("/quotations/{qid}/send"), None).await;
    assert_eq!(status, StatusCode::OK);
    let (status, order) = api(
        &app,
        Method::POST,
        &format!("/quotations/{qid}/convert"),
        Some(json!({ "customer_reference": "PO-1" })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{order}");
    let id = order["order"]["id"].as_str().unwrap().to_string();
    let v0 = version(&order);

    let edit = |notes: &str, expected: Option<i64>| {
        let mut b = json!({ "notes": notes, "lines": [{ "position": 1, "quantity": "2" }] });
        if let Some(e) = expected {
            b["expected_version"] = json!(e);
        }
        b
    };
    let (status, saved) = api(
        &app,
        Method::PUT,
        &format!("/orders/{id}"),
        Some(edit("by Anna", Some(v0))),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{saved}");
    assert!(version(&saved) > v0);

    let (status, refused) = api(
        &app,
        Method::PUT,
        &format!("/orders/{id}"),
        Some(edit("by Ben", Some(v0))),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT, "{refused}");
    assert_eq!(refused["code"], "record_changed");

    // Without a version the save still goes through.
    let (status, _) = api(
        &app,
        Method::PUT,
        &format!("/orders/{id}"),
        Some(edit("by a script", None)),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
}
