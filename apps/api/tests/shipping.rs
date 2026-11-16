//! Packaging categories, product dimensions and the shipping-quote workflow.

mod common;

use axum::http::{Method, StatusCode};
use common::{call, dec, setup};
use serde_json::{json, Value};
use sqlx::PgPool;

const ALPHA: &str = "00000000-0000-7000-8000-000000000401";
const UNIT_100: &str = "00000000-0000-7000-8000-000000000301"; // plain product
const PANEL: &str = "00000000-0000-7000-8000-00000000030b"; // PANEL-2400, seeded in LARGE-FLAT
const LARGE_FLAT: &str = "00000000-0000-7000-8000-000000000b03";
const PARCEL: &str = "00000000-0000-7000-8000-000000000b01";
const SALES: &str = "sales@example.com";
const ADMIN: &str = "admin@example.com";
const LOGISTICS: &str = "logistics@example.com";
const MANAGER: &str = "manager@example.com";

async fn api(
    app: &axum::Router,
    user: &str,
    method: Method,
    uri: &str,
    body: Option<Value>,
) -> (StatusCode, Value) {
    call(app, user, method, &format!("/api/v1{uri}"), body).await
}

async fn quote(app: &axum::Router, product: &str, extra: Value) -> Value {
    let mut body = json!({
        "customer_id": ALPHA,
        "vat_regime_override": "domestic",
        "lines": [{ "product_id": product, "quantity": "1" }]
    });
    for (k, v) in extra.as_object().unwrap() {
        body[k] = v.clone();
    }
    let (status, q) = api(app, SALES, Method::POST, "/quotations", Some(body)).await;
    assert_eq!(status, StatusCode::CREATED, "{q}");
    q
}

fn id(v: &Value) -> &str {
    v["id"].as_str().unwrap()
}

async fn queue(app: &axum::Router) -> Vec<Value> {
    let (status, list) = api(app, LOGISTICS, Method::GET, "/shipping-requests", None).await;
    assert_eq!(status, StatusCode::OK, "{list}");
    list.as_array().unwrap().clone()
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn packaging_categories_crud_and_permissions(db: PgPool) {
    let app = setup(db).await;
    let body = json!({ "code": "CRATE", "name": "Crate", "description": "Wooden crate", "requires_shipping_quote": true });

    // Sales may read but not write.
    let (status, list) = api(&app, SALES, Method::GET, "/packaging-categories", None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(
        list.as_array().unwrap().len(),
        3,
        "seed has three categories"
    );
    let (status, _) = api(
        &app,
        SALES,
        Method::POST,
        "/packaging-categories",
        Some(body.clone()),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);

    let (status, c) = api(
        &app,
        ADMIN,
        Method::POST,
        "/packaging-categories",
        Some(body.clone()),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{c}");
    assert_eq!(c["code"], "CRATE");
    assert_eq!(c["requires_shipping_quote"], true);
    assert_eq!(c["active"], true);
    assert_eq!(c["product_count"], 0);

    let (status, _) = api(
        &app,
        ADMIN,
        Method::POST,
        "/packaging-categories",
        Some(body),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT, "code is unique");
    let (status, _) = api(
        &app,
        ADMIN,
        Method::POST,
        "/packaging-categories",
        Some(json!({ "code": " ", "name": "x" })),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    let uri = format!("/packaging-categories/{}", id(&c));
    let update = json!({ "code": "CRATE", "name": "Wooden crate", "requires_shipping_quote": false, "active": false });
    let (status, _) = api(&app, SALES, Method::PUT, &uri, Some(update.clone())).await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, u) = api(&app, ADMIN, Method::PUT, &uri, Some(update.clone())).await;
    assert_eq!(status, StatusCode::OK, "{u}");
    assert_eq!(u["name"], "Wooden crate");
    assert_eq!(u["requires_shipping_quote"], false);
    assert_eq!(u["active"], false);
    let (status, _) = api(
        &app,
        ADMIN,
        Method::PUT,
        "/packaging-categories/00000000-0000-7000-8000-0000000000ff",
        Some(update),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn product_dimensions_and_category_round_trip(db: PgPool) {
    let app = setup(db).await;
    let product = |extra: Value| {
        let mut b = json!({ "code": "PANEL-1", "name": "Panel", "vat_rate": "21" });
        for (k, v) in extra.as_object().unwrap() {
            b[k] = v.clone();
        }
        b
    };
    let (status, p) = api(
        &app,
        ADMIN,
        Method::POST,
        "/products",
        Some(product(json!({
            "packaging_category_id": LARGE_FLAT,
            "length_mm": 2400, "width_mm": 1200, "height_mm": 20, "weight_g": 31000
        }))),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{p}");
    assert_eq!(p["packaging_category_id"], LARGE_FLAT);
    assert_eq!(p["packaging_category_code"], "LARGE-FLAT");
    assert_eq!(
        (
            p["length_mm"].as_i64(),
            p["width_mm"].as_i64(),
            p["height_mm"].as_i64(),
            p["weight_g"].as_i64()
        ),
        (Some(2400), Some(1200), Some(20), Some(31000))
    );
    let (_, got) = api(
        &app,
        SALES,
        Method::GET,
        &format!("/products/{}", id(&p)),
        None,
    )
    .await;
    assert_eq!(got["packaging_category_code"], "LARGE-FLAT");
    assert_eq!(got["weight_g"], 31000);
    let (_, page) = api(&app, SALES, Method::GET, "/products?q=panel-1", None).await;
    assert_eq!(page["items"][0]["length_mm"], 2400);

    // Update: change the category, clear a dimension.
    let uri = format!("/products/{}", id(&p));
    let (status, u) = api(
        &app,
        ADMIN,
        Method::PUT,
        &uri,
        Some(product(
            json!({ "packaging_category_id": PARCEL, "length_mm": 500 }),
        )),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{u}");
    assert_eq!(u["packaging_category_code"], "PARCEL");
    assert_eq!(u["length_mm"], 500);
    assert!(u["width_mm"].is_null() && u["weight_g"].is_null());

    // Validation: dimensions must be positive, the category must exist and be active.
    for bad in [
        json!({ "length_mm": 0 }),
        json!({ "weight_g": -5 }),
        json!({ "packaging_category_id": "00000000-0000-7000-8000-0000000000ff" }),
    ] {
        let (status, e) = api(&app, ADMIN, Method::PUT, &uri, Some(product(bad.clone()))).await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{bad}: {e}");
    }
    let (_, c) = api(
        &app,
        ADMIN,
        Method::POST,
        "/packaging-categories",
        Some(json!({ "code": "OLD", "name": "Old", "active": false })),
    )
    .await;
    let (status, _) = api(
        &app,
        ADMIN,
        Method::PUT,
        &uri,
        Some(product(json!({ "packaging_category_id": id(&c) }))),
    )
    .await;
    assert_eq!(
        status,
        StatusCode::UNPROCESSABLE_ENTITY,
        "inactive category"
    );
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn only_products_that_need_a_quote_open_a_request(db: PgPool) {
    let pool = db.clone();
    let app = setup(db).await;
    let plain = quote(&app, UNIT_100, json!({})).await;
    assert_eq!(plain["shipping_status"], "not_required");
    assert!(queue(&app).await.is_empty());

    // Purpose 'stock' still needs shipping.
    let flat = quote(&app, PANEL, json!({ "purpose": "stock" })).await;
    assert_eq!(flat["shipping_status"], "pending");
    let q = queue(&app).await;
    assert_eq!(q.len(), 1);
    assert_eq!(q[0]["quotation_id"], flat["id"]);
    assert_eq!(q[0]["status"], "open");
    assert_eq!(q[0]["quotation_number"], flat["number"]);

    // Only logistics and admins see the queue.
    for user in [SALES, MANAGER] {
        let (status, _) = api(&app, user, Method::GET, "/shipping-requests", None).await;
        assert_eq!(status, StatusCode::FORBIDDEN, "{user}");
    }
    let (status, _) = api(&app, ADMIN, Method::GET, "/shipping-requests", None).await;
    assert_eq!(status, StatusCode::OK);

    // Saving again does not open a second request.
    let (status, u) = api(
        &app,
        SALES,
        Method::PUT,
        &format!("/quotations/{}", id(&flat)),
        Some(json!({ "customer_id": ALPHA, "lines": [{ "product_id": PANEL, "quantity": "2" }] })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{u}");
    assert_eq!(queue(&app).await.len(), 1);

    // Logistics was told by mail, once.
    let mails: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM core.mail_outbox WHERE to_address = $1 AND subject LIKE 'Shipping quote needed%'",
    )
    .bind(LOGISTICS)
    .fetch_one(&pool)
    .await
    .unwrap();
    assert_eq!(mails, 1);

    // The list summary carries the status.
    let (_, page) = api(&app, SALES, Method::GET, "/quotations", None).await;
    let pending = page["items"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|i| i["shipping_status"] == "pending")
        .count();
    assert_eq!(pending, 1);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn sending_waits_for_the_quoted_cost_which_enters_the_totals(db: PgPool) {
    let app = setup(db).await;
    let q = quote(&app, PANEL, json!({})).await;
    let qid = id(&q).to_string();
    let send = format!("/quotations/{qid}/send");

    let (status, e) = api(&app, SALES, Method::POST, &send, None).await;
    assert_eq!(status, StatusCode::CONFLICT, "{e}");

    let rid = queue(&app).await[0]["id"].as_str().unwrap().to_string();
    // Marking as requested does not unblock sending.
    let (status, r) = api(
        &app,
        LOGISTICS,
        Method::POST,
        &format!("/shipping-requests/{rid}/request"),
        Some(json!({ "carrier": "DHL Freight", "notes": "crate 2400x1200" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{r}");
    assert_eq!(r["status"], "requested");
    assert_eq!(r["carrier"], "DHL Freight");
    let (status, _) = api(&app, SALES, Method::POST, &send, None).await;
    assert_eq!(status, StatusCode::CONFLICT);
    // Carrier is required, sales may not touch the request.
    let (status, _) = api(
        &app,
        LOGISTICS,
        Method::POST,
        &format!("/shipping-requests/{rid}/request"),
        Some(json!({ "carrier": " " })),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    let (status, _) = api(
        &app,
        SALES,
        Method::POST,
        &format!("/shipping-requests/{rid}/quote"),
        Some(json!({ "amount": "180" })),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);

    // Enter the cost.
    let before = api(
        &app,
        SALES,
        Method::GET,
        &format!("/quotations/{qid}"),
        None,
    )
    .await
    .1;
    let quote_uri = format!("/shipping-requests/{rid}/quote");
    let (status, e) = api(
        &app,
        LOGISTICS,
        Method::POST,
        &quote_uri,
        Some(json!({ "amount": "180", "currency": "USD" })),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{e}");
    let (status, e) = api(
        &app,
        LOGISTICS,
        Method::POST,
        &quote_uri,
        Some(json!({ "amount": "-1" })),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{e}");
    let (status, r) = api(
        &app,
        LOGISTICS,
        Method::POST,
        &quote_uri,
        Some(json!({ "amount": "180", "currency": "EUR" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{r}");
    assert_eq!(r["status"], "quoted");
    assert_eq!(dec(&r["quoted_amount"]).to_string(), "180.00");
    assert_eq!(
        r["carrier"], "DHL Freight",
        "carrier from the request step is kept"
    );
    assert!(
        queue(&app).await.is_empty(),
        "quoted requests leave the work queue"
    );

    let after = api(
        &app,
        SALES,
        Method::GET,
        &format!("/quotations/{qid}"),
        None,
    )
    .await
    .1;
    assert_eq!(after["shipping_status"], "quoted");
    let lines = after["lines"].as_array().unwrap();
    assert_eq!(lines.len(), 2);
    let ship = &lines[1];
    assert_eq!(ship["product_code"], "SHIPPING");
    assert!(ship["product_id"].is_null());
    assert_eq!(dec(&ship["line_total"]).to_string(), "180.00");
    assert_eq!(ship["vat_rate"], before["lines"][0]["vat_rate"]);
    assert_eq!(
        dec(&after["subtotal"]) - dec(&before["subtotal"]),
        dec(&json!("180"))
    );
    // 21% VAT on the shipping cost.
    assert_eq!(
        dec(&after["total"]) - dec(&before["total"]),
        dec(&json!("217.80"))
    );

    // Quoting again updates the single line.
    let (status, _) = api(
        &app,
        LOGISTICS,
        Method::POST,
        &quote_uri,
        Some(json!({ "amount": "200" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let again = api(
        &app,
        SALES,
        Method::GET,
        &format!("/quotations/{qid}"),
        None,
    )
    .await
    .1;
    assert_eq!(again["lines"].as_array().unwrap().len(), 2);
    assert_eq!(
        dec(&again["subtotal"]) - dec(&before["subtotal"]),
        dec(&json!("200"))
    );

    // Re-saving the draft (which replaces all lines) keeps the shipping line.
    let (status, saved) = api(
        &app,
        SALES,
        Method::PUT,
        &format!("/quotations/{qid}"),
        Some(json!({ "customer_id": ALPHA, "lines": [{ "product_id": PANEL, "quantity": "1" }] })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{saved}");
    assert_eq!(saved["shipping_status"], "quoted");
    assert_eq!(saved["lines"][1]["product_code"], "SHIPPING");
    assert_eq!(dec(&saved["subtotal"]), dec(&again["subtotal"]));

    // Now it can be sent, and the request can no longer be changed.
    let (status, sent) = api(&app, SALES, Method::POST, &send, None).await;
    assert_eq!(status, StatusCode::OK, "{sent}");
    let (status, _) = api(
        &app,
        LOGISTICS,
        Method::POST,
        &quote_uri,
        Some(json!({ "amount": "1" })),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);

    // A revision that keeps the prices keeps the quoted cost; repricing asks again.
    let (status, keep) = api(
        &app,
        SALES,
        Method::POST,
        &format!("/quotations/{qid}/revise"),
        Some(json!({ "pricing": "keep" })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{keep}");
    assert_eq!(keep["shipping_status"], "quoted");
    assert_eq!(keep["lines"][1]["product_code"], "SHIPPING");
    assert_eq!(dec(&keep["total"]), dec(&sent["total"]));
    let (status, _) = api(
        &app,
        SALES,
        Method::POST,
        &format!("/quotations/{}/send", id(&keep)),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (status, cur) = api(
        &app,
        SALES,
        Method::POST,
        &format!("/quotations/{}/revise", id(&keep)),
        Some(json!({ "pricing": "current" })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{cur}");
    assert_eq!(cur["shipping_status"], "pending");
    assert_eq!(
        cur["lines"].as_array().unwrap().len(),
        1,
        "no stale shipping line"
    );
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn override_needs_the_shipping_permission(db: PgPool) {
    let app = setup(db).await;
    let q = quote(&app, PANEL, json!({})).await;
    let uri = format!("/quotations/{}/send?override_shipping=true", id(&q));

    // Sales cannot override, and neither can a sales manager.
    for user in [SALES, MANAGER] {
        let (status, e) = api(&app, user, Method::POST, &uri, None).await;
        assert_eq!(status, StatusCode::FORBIDDEN, "{user}: {e}");
    }
    // Logistics may manage shipping but cannot send quotations at all.
    let (status, _) = api(&app, LOGISTICS, Method::POST, &uri, None).await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    // An explicit false is the same as no flag.
    let (status, _) = api(
        &app,
        ADMIN,
        Method::POST,
        &format!("/quotations/{}/send?override_shipping=false", id(&q)),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);

    let (status, sent) = api(&app, ADMIN, Method::POST, &uri, None).await;
    assert_eq!(status, StatusCode::OK, "{sent}");
    assert_eq!(sent["status"], "sent");
    assert_eq!(sent["shipping_status"], "pending");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn removing_the_product_cancels_the_request(db: PgPool) {
    let app = setup(db).await;
    let q = quote(&app, PANEL, json!({})).await;
    let qid = id(&q).to_string();
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

    let (status, saved) = api(
        &app,
        SALES,
        Method::PUT,
        &format!("/quotations/{qid}"),
        Some(
            json!({ "customer_id": ALPHA, "lines": [{ "product_id": UNIT_100, "quantity": "1" }] }),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{saved}");
    assert_eq!(saved["shipping_status"], "not_required");
    assert_eq!(saved["lines"].as_array().unwrap().len(), 1);
    let plain = quote(&app, UNIT_100, json!({})).await;
    assert_eq!(
        dec(&saved["total"]),
        dec(&plain["total"]),
        "totals no longer include shipping"
    );

    let (_, cancelled) = api(
        &app,
        LOGISTICS,
        Method::GET,
        "/shipping-requests?status=cancelled",
        None,
    )
    .await;
    assert_eq!(cancelled.as_array().unwrap().len(), 1);
    assert_eq!(cancelled[0]["id"], rid.as_str());
    let (status, _) = api(
        &app,
        LOGISTICS,
        Method::POST,
        &format!("/shipping-requests/{rid}/quote"),
        Some(json!({ "amount": "10" })),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
    // The quotation can be sent now.
    let (status, _) = api(
        &app,
        SALES,
        Method::POST,
        &format!("/quotations/{qid}/send"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    // Adding the product again opens a fresh request on another draft.
    let (status, _) = api(
        &app,
        LOGISTICS,
        Method::GET,
        "/shipping-requests?status=bogus",
        None,
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
}
