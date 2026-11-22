//! Regression tests for review findings: power supply replacement locking, stale grids, preview
//! purpose/country, send-time shipping reconciliation, repricing totals and
//! invalid customer default countries.

mod common;

use axum::http::{Method, StatusCode};
use common::{call, dec, setup};
use serde_json::{json, Value};
use sqlx::PgPool;

const ALPHA: &str = "00000000-0000-7000-8000-000000000401"; // BE
const UNIT_100: &str = "00000000-0000-7000-8000-000000000301";
const PUMP: &str = "00000000-0000-7000-8000-000000000303"; // seeded 230V 1-phase, PARCEL
const PANEL: &str = "00000000-0000-7000-8000-00000000030b"; // LARGE-FLAT, needs a shipping quote
const PARCEL: &str = "00000000-0000-7000-8000-000000000b01";
const SALES: &str = "sales@example.com";
const ADMIN: &str = "admin@example.com";
const LOGISTICS: &str = "logistics@example.com";

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
        .unwrap()["id"]
        .as_str()
        .unwrap()
        .to_string()
}

fn codes(v: &Value) -> Vec<String> {
    v["warnings"]
        .as_array()
        .unwrap()
        .iter()
        .map(|w| w["product_code"].as_str().unwrap().to_string())
        .collect()
}

async fn create(app: &axum::Router, product: &str, extra: Value) -> (StatusCode, Value) {
    let mut body =
        json!({ "customer_id": ALPHA, "lines": [{ "product_id": product, "quantity": "1" }] });
    for (k, v) in extra.as_object().unwrap() {
        body[k] = v.clone();
    }
    api(app, SALES, Method::POST, "/quotations", Some(body)).await
}

// 1 ------------------------------------------------------------------------------------------

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn replacements_of_one_product_serialize_and_other_products_are_independent(db: PgPool) {
    let pool = db.clone();
    let app = setup(db).await;
    let uri = format!("/products/{UNIT_100}/power-supplies");
    let body = json!([{ "current_type": "ac", "voltage_v": 230, "phases": 1 }]);

    let mut tx = pool.begin().await.unwrap();
    sqlx::query("SELECT 1 FROM products.products WHERE id = $1::uuid FOR NO KEY UPDATE")
        .bind(UNIT_100)
        .execute(&mut *tx)
        .await
        .unwrap();
    let (a, u, b) = (app.clone(), uri.clone(), body.clone());
    let mut first = tokio::spawn(async move { api(&a, ADMIN, Method::PUT, &u, Some(b)).await });
    let early = tokio::time::timeout(std::time::Duration::from_millis(500), &mut first).await;
    assert!(early.is_err(), "the replacement should wait for the lock");
    // Another product is not held up.
    let (status, _) = api(
        &app,
        ADMIN,
        Method::PUT,
        &format!("/products/{PUMP}/power-supplies"),
        Some(body.clone()),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    tx.commit().await.unwrap();
    let (status, r) = first.await.unwrap();
    assert_eq!(status, StatusCode::OK, "{r}");

    // Racing replacements all succeed and leave one consistent list.
    let mut handles = vec![];
    for _ in 0..6 {
        let (a, u, b) = (app.clone(), uri.clone(), body.clone());
        handles.push(tokio::spawn(async move {
            api(&a, ADMIN, Method::PUT, &u, Some(b)).await
        }));
    }
    for h in handles {
        let (status, r) = h.await.unwrap();
        assert_eq!(status, StatusCode::OK, "{r}");
    }
    let (_, list) = api(&app, ADMIN, Method::GET, &uri, None).await;
    assert_eq!(list.as_array().unwrap().len(), 1);

    let (status, _) = api(
        &app,
        ADMIN,
        Method::PUT,
        "/products/00000000-0000-7000-8000-0000000000ff/power-supplies",
        Some(body),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

// 2 ------------------------------------------------------------------------------------------

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_stale_grid_never_blocks_confirm_or_reads(db: PgPool) {
    let app = setup(db).await;
    let be = grid_id(&app, "BE", 400, 3).await;
    let (status, q) = create(&app, PUMP, json!({ "power_grid_id": be })).await;
    assert_eq!(status, StatusCode::CREATED, "{q}");
    let qid = q["id"].as_str().unwrap().to_string();
    let (status, _) = api(
        &app,
        SALES,
        Method::POST,
        &format!("/quotations/{qid}/send"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (status, o) = api(
        &app,
        SALES,
        Method::POST,
        &format!("/quotations/{qid}/convert"),
        Some(json!({ "customer_reference": "PO" })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{o}");
    let oid = o["order"]["id"].as_str().unwrap().to_string();
    let (_, d) = create(&app, PUMP, json!({ "power_grid_id": be })).await;
    let did = d["id"].as_str().unwrap().to_string();

    // The grid moves to another country after it was referenced.
    let (status, g) = api(
        &app,
        ADMIN,
        Method::PUT,
        &format!("/power-grids/{be}"),
        Some(
            json!({ "country_code": "US", "name": "Moved", "voltage_v": 400, "phases": 3,
                     "frequency_hz": 50, "active": true }),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{g}");

    let (status, q) = api(
        &app,
        SALES,
        Method::GET,
        &format!("/quotations/{qid}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{q}");
    assert!(q["warnings"].is_array());

    api(
        &app,
        SALES,
        Method::POST,
        &format!("/orders/{oid}/send"),
        None,
    )
    .await;
    let (status, c) = api(
        &app,
        SALES,
        Method::POST,
        &format!("/orders/{oid}/confirm"),
        Some(json!({})),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{c}");
    // Checked against the BE grids instead: the 230V pump fits there.
    assert!(codes(&c).is_empty(), "{c}");

    // A draft with a stale grid can still be read and saved (the grid is dropped).
    let (status, d) = api(
        &app,
        SALES,
        Method::GET,
        &format!("/quotations/{did}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{d}");
    assert!(codes(&d).is_empty(), "{d}");
    let (status, u) = api(
        &app,
        SALES,
        Method::PUT,
        &format!("/quotations/{did}"),
        Some(json!({ "customer_id": ALPHA, "lines": [{ "product_id": PUMP, "quantity": "2" }] })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{u}");
    assert!(u["power_grid_id"].is_null());
    // An explicit wrong grid is still a 422.
    let (status, _) = create(&app, PUMP, json!({ "power_grid_id": be })).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_stale_grid_with_an_incompatible_product_warns_against_the_remaining_grids(db: PgPool) {
    let app = setup(db).await;
    let be = grid_id(&app, "BE", 400, 3).await;
    // UNIT-200 (120V 60Hz) needs confirmed indicative prices, so give the pump a 120V 60Hz supply:
    // no Belgian grid offers that.
    let (status, r) = api(
        &app,
        ADMIN,
        Method::PUT,
        &format!("/products/{PUMP}/power-supplies"),
        Some(json!([{ "current_type": "ac", "voltage_v": 120, "phases": 1, "frequency_hz": 60 }])),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{r}");
    let (status, q) = create(&app, PUMP, json!({ "power_grid_id": be })).await;
    assert_eq!(status, StatusCode::CREATED, "{q}");
    let qid = q["id"].as_str().unwrap().to_string();
    let (status, _) = api(
        &app,
        SALES,
        Method::POST,
        &format!("/quotations/{qid}/send"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (status, o) = api(
        &app,
        SALES,
        Method::POST,
        &format!("/quotations/{qid}/convert"),
        Some(json!({ "customer_reference": "PO" })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{o}");
    let oid = o["order"]["id"].as_str().unwrap().to_string();

    // The grid moves to another country after it was referenced.
    let (status, g) = api(
        &app,
        ADMIN,
        Method::PUT,
        &format!("/power-grids/{be}"),
        Some(
            json!({ "country_code": "US", "name": "Moved", "voltage_v": 400, "phases": 3,
                     "frequency_hz": 50, "active": true }),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{g}");

    api(
        &app,
        SALES,
        Method::POST,
        &format!("/orders/{oid}/send"),
        None,
    )
    .await;
    let (status, c) = api(
        &app,
        SALES,
        Method::POST,
        &format!("/orders/{oid}/confirm"),
        Some(json!({})),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{c}");
    let warnings = c["warnings"].as_array().unwrap();
    let w = warnings
        .iter()
        .find(|w| w["kind"] == "power_grid" && w["product_code"] == "PUMP-05")
        .unwrap_or_else(|| panic!("no power_grid warning for the pump: {c}"));
    assert_eq!(w["details"]["status"], "incompatible", "{w}");
    // The warning lists the Belgian grids that remain, not the moved one.
    let (_, list) = api(&app, SALES, Method::GET, "/power-grids?country=BE", None).await;
    let mut expected: Vec<&Value> = list.as_array().unwrap().iter().collect();
    expected.retain(|g| g["id"] != be.as_str());
    assert!(!expected.is_empty());
    let available = w["details"]["available"].as_array().unwrap();
    assert!(!available.is_empty(), "{w}");
    let key = |g: &Value| (g["voltage_v"].as_i64(), g["phases"].as_i64());
    let mut got: Vec<_> = available.iter().map(key).collect();
    let mut want: Vec<_> = expected.iter().map(|g| key(g)).collect();
    got.sort();
    want.sort();
    assert_eq!(got, want, "{w}");
    assert!(!available.contains(&json!(be)), "{w}");
    assert_eq!(w["details"]["country_code"], "BE", "{w}");
}

// 3 + 7 --------------------------------------------------------------------------------------

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn preview_uses_the_purpose_for_the_country(db: PgPool) {
    let app = setup(db).await;
    let be = grid_id(&app, "BE", 400, 3).await;
    let preview = |extra: Value| {
        let app = app.clone();
        async move {
            let mut body = json!({ "customer_id": ALPHA,
                "lines": [{ "product_id": PUMP, "quantity": "1" }] });
            for (k, v) in extra.as_object().unwrap() {
                body[k] = v.clone();
            }
            api(&app, SALES, Method::POST, "/pricing/preview", Some(body)).await
        }
    };
    // Stock without a country: no warnings, and a grid is refused like on create.
    let (status, p) = preview(json!({ "purpose": "stock" })).await;
    assert_eq!(status, StatusCode::OK, "{p}");
    assert!(codes(&p).is_empty());
    let (status, _) = preview(json!({ "purpose": "stock", "power_grid_id": be })).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    // Stock with an explicit country and grid is accepted (stock has no power warnings).
    let (status, p) =
        preview(json!({ "purpose": "stock", "delivery_country_code": "be", "power_grid_id": be }))
            .await;
    assert_eq!(status, StatusCode::OK, "{p}");
    assert!(codes(&p).is_empty());
    // Installation is unchanged: customer country, warnings against the chosen grid.
    let (status, p) = preview(json!({ "power_grid_id": be })).await;
    assert_eq!(status, StatusCode::OK, "{p}");
    assert_eq!(codes(&p), ["PUMP-05"]);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn an_invalid_customer_country_does_not_block_anything(db: PgPool) {
    let pool = db.clone();
    let app = setup(db).await;
    sqlx::query("UPDATE crm.customers SET country_code = 'B1' WHERE id = $1::uuid")
        .bind(ALPHA)
        .execute(&pool)
        .await
        .unwrap();
    let (status, q) = create(&app, PUMP, json!({})).await;
    assert_eq!(status, StatusCode::CREATED, "{q}");
    assert!(q["delivery_country_code"].is_null());
    assert!(codes(&q).is_empty());
    let qid = q["id"].as_str().unwrap().to_string();
    let (status, u) = api(
        &app,
        SALES,
        Method::PUT,
        &format!("/quotations/{qid}"),
        Some(json!({ "customer_id": ALPHA, "lines": [{ "product_id": PUMP, "quantity": "2" }] })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{u}");
    let (status, p) = api(
        &app,
        SALES,
        Method::POST,
        "/pricing/preview",
        Some(json!({ "customer_id": ALPHA, "lines": [{ "product_id": PUMP, "quantity": "1" }] })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{p}");
    // An explicit invalid delivery country is still refused.
    let (status, _) = create(&app, PUMP, json!({ "delivery_country_code": "B1" })).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    api(
        &app,
        SALES,
        Method::POST,
        &format!("/quotations/{qid}/send"),
        None,
    )
    .await;
    let (status, o) = api(
        &app,
        SALES,
        Method::POST,
        &format!("/quotations/{qid}/convert"),
        Some(json!({ "customer_reference": "PO" })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{o}");
    let oid = o["order"]["id"].as_str().unwrap();
    api(
        &app,
        SALES,
        Method::POST,
        &format!("/orders/{oid}/send"),
        None,
    )
    .await;
    let (status, c) = api(
        &app,
        SALES,
        Method::POST,
        &format!("/orders/{oid}/confirm"),
        Some(json!({})),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{c}");
    assert!(codes(&c).is_empty());
}

// 4 + 5 --------------------------------------------------------------------------------------

async fn set_parcel_requires_quote(app: &axum::Router, requires: bool) {
    let (status, r) = api(
        app,
        ADMIN,
        Method::PUT,
        &format!("/packaging-categories/{PARCEL}"),
        Some(
            json!({ "code": "PARCEL", "name": "Parcel", "requires_shipping_quote": requires,
                     "active": true }),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{r}");
}

async fn queue(app: &axum::Router) -> Vec<Value> {
    let (_, list) = api(app, LOGISTICS, Method::GET, "/shipping-requests", None).await;
    list.as_array().unwrap().clone()
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn sending_reconciles_shipping_first(db: PgPool) {
    let app = setup(db).await;
    let (_, q) = create(&app, PUMP, json!({})).await;
    assert_eq!(q["shipping_status"], "not_required");
    let qid = q["id"].as_str().unwrap().to_string();
    let send = format!("/quotations/{qid}/send");
    set_parcel_requires_quote(&app, true).await;

    let (status, e) = api(&app, SALES, Method::POST, &send, None).await;
    assert_eq!(status, StatusCode::CONFLICT, "{e}");
    let reqs = queue(&app).await;
    assert_eq!(reqs.len(), 1, "the request survived the refused send");
    assert_eq!(reqs[0]["status"], "open");
    let (_, now) = api(
        &app,
        SALES,
        Method::GET,
        &format!("/quotations/{qid}"),
        None,
    )
    .await;
    assert_eq!(now["shipping_status"], "pending");
    assert_eq!(now["status"], "draft");

    // A second refused send does not open a second request.
    let (status, _) = api(&app, SALES, Method::POST, &send, None).await;
    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!(queue(&app).await.len(), 1);

    let rid = reqs[0]["id"].as_str().unwrap();
    let (status, r) = api(
        &app,
        LOGISTICS,
        Method::POST,
        &format!("/shipping-requests/{rid}/quote"),
        Some(json!({ "amount": "40" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{r}");
    let (status, sent) = api(&app, SALES, Method::POST, &send, None).await;
    assert_eq!(status, StatusCode::OK, "{sent}");
    assert_eq!(sent["shipping_status"], "quoted");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_request_that_is_no_longer_needed_is_cancelled_on_send(db: PgPool) {
    let pool = db.clone();
    let app = setup(db).await;
    let (_, q) = create(&app, PANEL, json!({})).await;
    assert_eq!(q["shipping_status"], "pending");
    let qid = q["id"].as_str().unwrap().to_string();
    sqlx::query(
        "UPDATE products.packaging_categories SET requires_shipping_quote = false WHERE code = 'LARGE-FLAT'",
    )
    .execute(&pool)
    .await
    .unwrap();
    let (status, sent) = api(
        &app,
        SALES,
        Method::POST,
        &format!("/quotations/{qid}/send"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{sent}");
    assert_eq!(sent["shipping_status"], "not_required");
    let open: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM sales.shipping_requests WHERE quotation_id = $1::uuid AND status <> 'cancelled'",
    )
    .bind(&qid)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(open, 0);
}

// 6 ------------------------------------------------------------------------------------------

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn repricing_compares_product_lines_only(db: PgPool) {
    let app = setup(db).await;
    let (_, q) = create(&app, PANEL, json!({})).await;
    let qid = q["id"].as_str().unwrap().to_string();
    let rid = queue(&app).await[0]["id"].as_str().unwrap().to_string();
    let (status, _) = api(
        &app,
        LOGISTICS,
        Method::POST,
        &format!("/shipping-requests/{rid}/quote"),
        Some(json!({ "amount": "90" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (_, q) = api(
        &app,
        SALES,
        Method::GET,
        &format!("/quotations/{qid}"),
        None,
    )
    .await;
    assert_eq!(
        q["lines"].as_array().unwrap().len(),
        2,
        "product + shipping"
    );
    api(
        &app,
        SALES,
        Method::POST,
        &format!("/quotations/{qid}/send"),
        None,
    )
    .await;

    let (status, r) = api(
        &app,
        SALES,
        Method::GET,
        &format!("/quotations/{qid}/repricing"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{r}");
    assert_eq!(dec(&r["difference"]), dec(&json!("0")), "{r}");
    assert_eq!(dec(&r["old_shipping_total"]), dec(&json!("90")), "{r}");
    assert_eq!(r["shipping_requote_needed"], true);

    let (_, plain) = create(&app, UNIT_100, json!({})).await;
    let pid = plain["id"].as_str().unwrap();
    let (status, r) = api(
        &app,
        SALES,
        Method::GET,
        &format!("/quotations/{pid}/repricing"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{r}");
    assert_eq!(dec(&r["difference"]), dec(&json!("0")));
    assert_eq!(r["shipping_requote_needed"], false);
}
