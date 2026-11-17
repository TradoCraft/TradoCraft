//! Concurrent-edit protection (ADR 0072, D3): customers, quotations, orders and tickets carry a
//! row version; a save made from an older version is refused with 409 `record_changed`, a save
//! without one behaves as before, two saves that start from the same version cannot both succeed,
//! and updates emit a live SSE event on `GET /api/v1/events/records`.

mod common;

use axum::body::Body;
use axum::http::{Method, Request, StatusCode};
use common::{call, setup};
use http_body_util::BodyExt;
use serde_json::{json, Value};
use sqlx::PgPool;
use tower::ServiceExt;

const SALES: &str = "sales@example.com";
const SUPPORT: &str = "support@example.com";
const ALPHA: &str = "00000000-0000-7000-8000-000000000401";
const UNIT: &str = "00000000-0000-7000-8000-000000000301";
const ZONE_Z2: &str = "00000000-0000-7000-8000-000000000202";

async fn api_as(
    app: &axum::Router,
    user: &str,
    method: Method,
    uri: &str,
    body: Option<Value>,
) -> (StatusCode, Value) {
    call(app, user, method, &format!("/api/v1{uri}"), body).await
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
    let (status, loaded) = api_as(
        &app,
        SALES,
        Method::GET,
        &format!("/customers/{ALPHA}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{loaded}");
    let v0 = version(&loaded);

    // The first save from this version wins and raises the version.
    let (status, saved) = api_as(
        &app,
        SALES,
        Method::PUT,
        &format!("/customers/{ALPHA}"),
        Some(customer_body("Alpha First", Some(v0))),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{saved}");
    assert_eq!(version(&saved), v0 + 1);

    // A second save carrying the old version is refused and leaves the row alone.
    let (status, err) = api_as(
        &app,
        SALES,
        Method::PUT,
        &format!("/customers/{ALPHA}"),
        Some(customer_body("Alpha Stale", Some(v0))),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT, "{err}");
    assert_eq!(err["code"], "record_changed");

    let (_, after) = api_as(
        &app,
        SALES,
        Method::GET,
        &format!("/customers/{ALPHA}"),
        None,
    )
    .await;
    assert_eq!(after["name"], "Alpha First");
    assert_eq!(version(&after), v0 + 1);

    // Without expected_version (scripts, imports, older clients) the save still goes through.
    let (status, forced) = api_as(
        &app,
        SALES,
        Method::PUT,
        &format!("/customers/{ALPHA}"),
        Some(customer_body("Alpha Forced", None)),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{forced}");
    assert_eq!(version(&forced), v0 + 2);
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
    let (status, created) = api_as(
        &app,
        SALES,
        Method::POST,
        "/quotations",
        Some(quotation_body("draft", None)),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{created}");
    let id = created["id"].as_str().unwrap();
    let v0 = version(&created);

    let (status, saved) = api_as(
        &app,
        SALES,
        Method::PUT,
        &format!("/quotations/{id}"),
        Some(quotation_body("first edit", Some(v0))),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{saved}");
    assert_eq!(version(&saved), v0 + 1);

    let (status, err) = api_as(
        &app,
        SALES,
        Method::PUT,
        &format!("/quotations/{id}"),
        Some(quotation_body("stale edit", Some(v0))),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT, "{err}");
    assert_eq!(err["code"], "record_changed");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_stale_order_save_is_refused(db: PgPool) {
    let app = setup(db).await;
    let (status, q) = api_as(
        &app,
        SALES,
        Method::POST,
        "/quotations",
        Some(quotation_body("for order", None)),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{q}");
    let qid = q["id"].as_str().unwrap();

    let (status, o) = api_as(
        &app,
        SALES,
        Method::POST,
        &format!("/quotations/{qid}/convert"),
        Some(json!({ "customer_reference": "PO-1", "notes": "initial" })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{o}");
    let oid = o["order"]["id"].as_str().unwrap();
    let v0 = version(&o);

    let edit_body = |notes: &str, expected: Option<i64>| {
        let mut b = json!({
            "notes": notes,
            "lines": [{ "position": 1, "quantity": "2" }],
        });
        if let Some(e) = expected {
            b["expected_version"] = json!(e);
        }
        b
    };

    let (status, saved) = api_as(
        &app,
        SALES,
        Method::PUT,
        &format!("/orders/{oid}"),
        Some(edit_body("first edit", Some(v0))),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{saved}");
    assert!(version(&saved) > v0);

    let (status, err) = api_as(
        &app,
        SALES,
        Method::PUT,
        &format!("/orders/{oid}"),
        Some(edit_body("stale edit", Some(v0))),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT, "{err}");
    assert_eq!(err["code"], "record_changed");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_stale_ticket_save_is_refused(db: PgPool) {
    let app = setup(db).await;
    let (status, created) = api_as(
        &app,
        SUPPORT,
        Method::POST,
        "/tickets",
        Some(json!({
            "subject": "Initial subject",
            "priority": "normal",
            "category": "question",
            "language": "en",
            "body": "Customer needs help",
        })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{created}");
    let id = created["ticket"]["id"].as_str().unwrap();
    let v0 = created["ticket"]["version"].as_i64().unwrap();

    let ticket_body = |subject: &str, expected: Option<i64>| {
        let mut b = json!({
            "subject": subject,
            "status": "open",
            "priority": "normal",
            "category": "question",
            "language": "en",
        });
        if let Some(e) = expected {
            b["expected_version"] = json!(e);
        }
        b
    };

    let (status, saved) = api_as(
        &app,
        SUPPORT,
        Method::PUT,
        &format!("/tickets/{id}"),
        Some(ticket_body("Updated subject", Some(v0))),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{saved}");
    let v1 = saved["ticket"]["version"].as_i64().unwrap();
    assert!(v1 > v0);

    let (status, err) = api_as(
        &app,
        SUPPORT,
        Method::PUT,
        &format!("/tickets/{id}"),
        Some(ticket_body("Stale subject", Some(v0))),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT, "{err}");
    assert_eq!(err["code"], "record_changed");

    let (_, after) = api_as(&app, SUPPORT, Method::GET, &format!("/tickets/{id}"), None).await;
    assert_eq!(after["ticket"]["subject"], "Updated subject");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn two_simultaneous_saves_from_the_same_version_give_one_ok_and_one_409(db: PgPool) {
    let app = setup(db).await;
    let (_, loaded) = api_as(
        &app,
        SALES,
        Method::GET,
        &format!("/customers/{ALPHA}"),
        None,
    )
    .await;
    let v0 = version(&loaded);

    let path = format!("/customers/{ALPHA}");
    let a = api_as(
        &app,
        SALES,
        Method::PUT,
        &path,
        Some(customer_body("Race A", Some(v0))),
    );
    let b = api_as(
        &app,
        "admin@example.com",
        Method::PUT,
        &path,
        Some(customer_body("Race B", Some(v0))),
    );
    let ((sa, _), (sb, _)) = tokio::join!(a, b);
    let mut statuses = [sa, sb];
    statuses.sort_by_key(|s| s.as_u16());
    assert_eq!(statuses, [StatusCode::OK, StatusCode::CONFLICT]);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn sse_record_events_streams_updates_and_validates_entity_type(db: PgPool) {
    let app = setup(db).await;

    // Unknown entity_type is refused with 422.
    let (status, _) = api_as(
        &app,
        SALES,
        Method::GET,
        &format!("/events/records?entity_type=bogus&record_id={ALPHA}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    // Open SSE stream for customer ALPHA.
    let req = Request::builder()
        .method(Method::GET)
        .uri(format!("/api/v1/events/records?entity_type=customer&record_id={ALPHA}"))
        .header("x-dev-user", SALES)
        .body(Body::empty())
        .unwrap();
    let res = app.clone().oneshot(req).await.unwrap();
    assert_eq!(res.status(), StatusCode::OK);
    let mut body = res.into_body();

    // Trigger an update on customer ALPHA.
    let (status, saved) = api_as(
        &app,
        "admin@example.com",
        Method::PUT,
        &format!("/customers/{ALPHA}"),
        Some(customer_body("Alpha Streamed", None)),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{saved}");

    let frame = tokio::time::timeout(std::time::Duration::from_secs(3), body.frame())
        .await
        .expect("SSE frame arrives in time")
        .expect("stream open")
        .expect("valid frame");
    let data = frame.into_data().expect("data frame");
    let text = String::from_utf8(data.to_vec()).unwrap();
    assert!(text.contains("event: record_changed"), "{text}");
    assert!(text.contains("Admin User"), "{text}");
    assert!(text.contains(ALPHA), "{text}");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn sse_stops_after_membership_deactivation(db: PgPool) {
    let app = setup(db.clone()).await;
    let req = Request::builder()
        .uri(format!(
            "/api/v1/events/records?entity_type=customer&record_id={ALPHA}"
        ))
        .header("x-dev-user", SALES)
        .body(Body::empty())
        .unwrap();
    let res = app.clone().oneshot(req).await.unwrap();
    assert_eq!(res.status(), StatusCode::OK);
    let mut body = res.into_body();
    sqlx::query("UPDATE core.user_companies SET active = false WHERE user_id = (SELECT id FROM core.users WHERE email = $1)")
        .bind(SALES).execute(&db).await.unwrap();
    let (status, saved) = api_as(
        &app,
        "admin@example.com",
        Method::PUT,
        &format!("/customers/{ALPHA}"),
        Some(customer_body("After deactivation", None)),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{saved}");
    let frame = tokio::time::timeout(std::time::Duration::from_secs(3), body.frame())
        .await
        .expect("revoked stream closes promptly");
    assert!(frame.is_none(), "revoked member must not receive an event");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn order_reads_return_the_committed_version_and_revision(db: PgPool) {
    let app = setup(db.clone()).await;
    let (status, q) = api_as(
        &app,
        SALES,
        Method::POST,
        "/quotations",
        Some(quotation_body("snapshot fixture", None)),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);
    let qid = q["id"].as_str().unwrap();
    // Prepare a sent quotation without invoking the unrelated PDF renderer.
    sqlx::query("UPDATE sales.quotations SET status = 'sent' WHERE id = $1::text::uuid")
        .bind(qid)
        .execute(&db)
        .await
        .unwrap();
    let (status, created) = api_as(
        &app,
        SALES,
        Method::POST,
        &format!("/quotations/{qid}/convert"),
        Some(json!({"customer_reference":"snapshot"})),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{created}");
    let oid = created["order"]["id"].as_str().unwrap();
    for path in [
        format!("/orders/{oid}"),
        format!("/orders/{oid}/revisions/1"),
    ] {
        let (status, read) = api_as(&app, SALES, Method::GET, &path, None).await;
        assert_eq!(status, StatusCode::OK, "{read}");
        assert_eq!(read["version"], created["version"]);
        assert_eq!(read["order"], created["order"]);
        assert_eq!(read["lines"], created["lines"]);
    }
}
