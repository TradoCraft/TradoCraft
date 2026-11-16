//! Order edit with a power grid, clearing a chosen grid, and shipping in the pricing preview.

mod common;

use axum::http::{Method, StatusCode};
use common::{call, dec, setup};
use serde_json::{json, Value};
use sqlx::PgPool;
use uuid::Uuid;

const ALPHA: &str = "00000000-0000-7000-8000-000000000401"; // BE
const UNIT_100: &str = "00000000-0000-7000-8000-000000000301";
const PUMP: &str = "00000000-0000-7000-8000-000000000303";
const PANEL: &str = "00000000-0000-7000-8000-00000000030b"; // needs a shipping quote
const SALES: &str = "sales@example.com";
const LOGISTICS: &str = "logistics@example.com";
const OTHER: &str = "other-sales@example.com";

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
        .unwrap_or_else(|| panic!("no {country} grid {voltage}V/{phases}"))["id"]
        .as_str()
        .unwrap()
        .to_string()
}

fn lines(product: &str) -> Value {
    json!([{ "product_id": product, "quantity": "1" }])
}

async fn quote(app: &axum::Router, product: &str, extra: Value) -> Value {
    let mut body = json!({
        "customer_id": ALPHA,
        "vat_regime_override": "domestic",
        "lines": lines(product)
    });
    for (k, v) in extra.as_object().unwrap() {
        body[k] = v.clone();
    }
    let (status, q) = api(app, SALES, Method::POST, "/quotations", Some(body)).await;
    assert_eq!(status, StatusCode::CREATED, "{q}");
    q
}

/// The preview computes in memory and the saved quotation is read back from NUMERIC columns, so
/// decimals can differ in scale ("1" and "1.0000"): compare them by value.
fn same_lines(a: &Value, b: &Value) {
    let (a, b) = (a.as_array().unwrap(), b.as_array().unwrap());
    assert_eq!(a.len(), b.len(), "{a:?} vs {b:?}");
    for (x, y) in a.iter().zip(b) {
        for (k, v) in x.as_object().unwrap() {
            let w = &y[k];
            if v.is_string() && v.as_str().unwrap().parse::<rust_decimal::Decimal>().is_ok() {
                assert_eq!(dec(v), dec(w), "{k}");
            } else {
                assert_eq!(v, w, "{k}");
            }
        }
    }
}

fn same_groups(a: &Value, b: &Value) {
    same_lines(a, b);
}

fn id(v: &Value) -> String {
    v["id"].as_str().unwrap().to_string()
}

/// A draft order converted from a sent quotation with the given extra quotation fields.
async fn draft_order(app: &axum::Router, extra: Value) -> String {
    let q = quote(app, UNIT_100, extra).await;
    let qid = id(&q);
    let (status, _) = api(
        app,
        SALES,
        Method::POST,
        &format!("/quotations/{qid}/send"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (status, o) = api(
        app,
        SALES,
        Method::POST,
        &format!("/quotations/{qid}/convert"),
        Some(json!({})),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{o}");
    id(&o["order"])
}

async fn edit_order(app: &axum::Router, oid: &str, extra: Value) -> (StatusCode, Value) {
    let mut body = json!({ "lines": [{ "position": 1, "quantity": "1" }] });
    for (k, v) in extra.as_object().unwrap() {
        body[k] = v.clone();
    }
    api(
        app,
        SALES,
        Method::PUT,
        &format!("/orders/{oid}"),
        Some(body),
    )
    .await
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn order_edit_sets_validates_and_clears_the_grid(db: PgPool) {
    let app = setup(db).await;
    let be = grid_id(&app, "BE", 230, 1).await;
    let be400 = grid_id(&app, "BE", 400, 3).await;
    let us = grid_id(&app, "US", 120, 1).await;
    let oid = draft_order(&app, json!({})).await;

    // Another country's grid is refused; so is an unknown one.
    let (status, e) = edit_order(&app, &oid, json!({ "power_grid_id": us })).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{e}");
    let (status, _) = edit_order(
        &app,
        &oid,
        json!({ "power_grid_id": "00000000-0000-7000-8000-0000000000ff" }),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    // Set, change, keep when omitted.
    let (status, o) = edit_order(&app, &oid, json!({ "power_grid_id": be })).await;
    assert_eq!(status, StatusCode::OK, "{o}");
    assert_eq!(o["order"]["power_grid_id"], be);
    let (_, o) = edit_order(&app, &oid, json!({ "power_grid_id": be400 })).await;
    assert_eq!(o["order"]["power_grid_id"], be400);
    let (_, o) = edit_order(&app, &oid, json!({})).await;
    assert_eq!(o["order"]["power_grid_id"], be400, "kept when omitted");
    // clear_power_grid: false has no effect.
    let (_, o) = edit_order(&app, &oid, json!({ "clear_power_grid": false })).await;
    assert_eq!(o["order"]["power_grid_id"], be400);

    // Clear; together with an id it is a 422 and nothing changes.
    let (status, e) = edit_order(
        &app,
        &oid,
        json!({ "clear_power_grid": true, "power_grid_id": be }),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{e}");
    let (_, o) = edit_order(&app, &oid, json!({})).await;
    assert_eq!(o["order"]["power_grid_id"], be400);
    let (status, o) = edit_order(&app, &oid, json!({ "clear_power_grid": true })).await;
    assert_eq!(status, StatusCode::OK, "{o}");
    assert!(o["order"]["power_grid_id"].is_null());

    // A new country is the one the grid is validated against, in the same request.
    let (status, o) = edit_order(
        &app,
        &oid,
        json!({ "delivery_country_code": "us", "power_grid_id": us }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{o}");
    assert_eq!(o["order"]["power_grid_id"], us);
    let (status, _) = edit_order(
        &app,
        &oid,
        json!({ "delivery_country_code": "US", "power_grid_id": be }),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    // A country change without a grid drops a grid the new country does not have.
    let (_, o) = edit_order(&app, &oid, json!({ "delivery_country_code": "BE" })).await;
    assert_eq!(o["order"]["delivery_country_code"], "BE");
    assert!(o["order"]["power_grid_id"].is_null());
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn order_grid_survives_a_same_country_edit_and_is_locked_after_draft(db: PgPool) {
    let app = setup(db).await;
    let be = grid_id(&app, "BE", 230, 1).await;
    let oid = draft_order(&app, json!({ "power_grid_id": be })).await;
    let (_, o) = edit_order(&app, &oid, json!({ "delivery_country_code": "BE" })).await;
    assert_eq!(o["order"]["power_grid_id"], be, "country unchanged");

    let (status, _) = api(
        &app,
        SALES,
        Method::POST,
        &format!("/orders/{oid}/send"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (status, e) = edit_order(&app, &oid, json!({ "clear_power_grid": true })).await;
    assert_eq!(status, StatusCode::CONFLICT, "{e}");
    let be400 = grid_id(&app, "BE", 400, 3).await;
    let (status, _) = edit_order(&app, &oid, json!({ "power_grid_id": be400 })).await;
    assert_eq!(status, StatusCode::CONFLICT);
    let (_, o) = api(&app, SALES, Method::GET, &format!("/orders/{oid}"), None).await;
    assert_eq!(o["order"]["power_grid_id"], be);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn quotation_update_clears_the_grid_explicitly(db: PgPool) {
    let app = setup(db).await;
    let be = grid_id(&app, "BE", 230, 1).await;
    let q = quote(&app, PUMP, json!({ "power_grid_id": be })).await;
    let uri = format!("/quotations/{}", id(&q));
    let put = |extra: Value| {
        let mut b = json!({ "customer_id": ALPHA, "lines": lines(PUMP) });
        for (k, v) in extra.as_object().unwrap() {
            b[k] = v.clone();
        }
        b
    };

    // Omitted keeps, false keeps, true clears.
    let (_, u) = api(&app, SALES, Method::PUT, &uri, Some(put(json!({})))).await;
    assert_eq!(u["power_grid_id"], be);
    let (_, u) = api(
        &app,
        SALES,
        Method::PUT,
        &uri,
        Some(put(json!({ "clear_power_grid": false }))),
    )
    .await;
    assert_eq!(u["power_grid_id"], be);
    // Clear and id together: 422, stored grid untouched.
    let (status, e) = api(
        &app,
        SALES,
        Method::PUT,
        &uri,
        Some(put(
            json!({ "clear_power_grid": true, "power_grid_id": be }),
        )),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{e}");
    let (_, g) = api(&app, SALES, Method::GET, &uri, None).await;
    assert_eq!(g["power_grid_id"], be);
    let (status, u) = api(
        &app,
        SALES,
        Method::PUT,
        &uri,
        Some(put(json!({ "clear_power_grid": true }))),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{u}");
    assert!(u["power_grid_id"].is_null());
    // After clearing, the warnings use any grid of the country again (the pump fits BE 230V).
    assert!(u["warnings"].as_array().unwrap().is_empty());
    // Create with the flag and an id is refused too.
    let (status, _) = api(
        &app,
        SALES,
        Method::POST,
        "/quotations",
        Some(put(
            json!({ "clear_power_grid": true, "power_grid_id": be }),
        )),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
}

// ---------------------------------------------------------------------------------------------
// Preview with the shipping line
// ---------------------------------------------------------------------------------------------

async fn preview(app: &axum::Router, user: &str, extra: Value) -> (StatusCode, Value) {
    let mut body = json!({
        "customer_id": ALPHA,
        "vat_regime_override": "domestic",
        "lines": lines(PANEL)
    });
    for (k, v) in extra.as_object().unwrap() {
        body[k] = v.clone();
    }
    api(app, user, Method::POST, "/pricing/preview", Some(body)).await
}

async fn quote_shipping(app: &axum::Router, qid: &str, amount: &str) {
    let (_, list) = api(app, LOGISTICS, Method::GET, "/shipping-requests", None).await;
    let rid = list
        .as_array()
        .unwrap()
        .iter()
        .find(|r| r["quotation_id"] == qid)
        .map(|r| r["id"].as_str().unwrap().to_string())
        .expect("open request");
    let (status, r) = api(
        app,
        LOGISTICS,
        Method::POST,
        &format!("/shipping-requests/{rid}/quote"),
        Some(json!({ "amount": amount })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{r}");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn preview_includes_the_shipping_line_only_when_quoted(db: PgPool) {
    let app = setup(db).await;
    let q = quote(&app, PANEL, json!({})).await;
    let qid = id(&q);
    let (_, plain) = preview(&app, SALES, json!({})).await;
    assert_eq!(plain["lines"].as_array().unwrap().len(), 1);

    // Pending: same as without the id.
    let (status, pending) = preview(&app, SALES, json!({ "quotation_id": qid })).await;
    assert_eq!(status, StatusCode::OK, "{pending}");
    assert_eq!(pending["lines"], plain["lines"]);
    assert_eq!(pending["total"], plain["total"]);
    assert_eq!(pending["vat_groups"], plain["vat_groups"]);

    quote_shipping(&app, &qid, "180").await;
    // Without the id nothing changes.
    let (_, still_plain) = preview(&app, SALES, json!({})).await;
    assert_eq!(still_plain, plain);

    let (status, p) = preview(&app, SALES, json!({ "quotation_id": qid })).await;
    assert_eq!(status, StatusCode::OK, "{p}");
    let l = p["lines"].as_array().unwrap();
    assert_eq!(l.len(), 2);
    assert_eq!(l[1]["product_code"], "SHIPPING");
    assert!(l[1]["product_id"].is_null());
    assert_eq!(l[1]["position"], 2);
    assert_eq!(dec(&l[1]["line_total"]).to_string(), "180.00");
    assert_eq!(
        dec(&p["subtotal"]) - dec(&plain["subtotal"]),
        dec(&json!("180"))
    );
    assert_eq!(
        dec(&p["total"]) - dec(&plain["total"]),
        dec(&json!("217.80"))
    );
    assert_eq!(p["unconfirmed_lines"], plain["unconfirmed_lines"]);

    // It is exactly what the saved draft shows.
    let (_, saved) = api(
        &app,
        SALES,
        Method::GET,
        &format!("/quotations/{qid}"),
        None,
    )
    .await;
    same_lines(&p["lines"], &saved["lines"]);
    assert_eq!(dec(&p["subtotal"]), dec(&saved["subtotal"]));
    assert_eq!(dec(&p["vat_total"]), dec(&saved["vat_total"]));
    assert_eq!(dec(&p["total"]), dec(&saved["total"]));
    same_groups(&p["vat_groups"], &saved["vat_groups"]);

    // Products that no longer need a quote (unsaved edit): no shipping line, as saving would drop it.
    let (_, p) = preview(
        &app,
        SALES,
        json!({ "quotation_id": qid, "lines": lines(UNIT_100) }),
    )
    .await;
    assert_eq!(p["lines"].as_array().unwrap().len(), 1);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn preview_shipping_vat_follows_the_highest_product_rate(db: PgPool) {
    let app = setup(db.clone()).await;
    let q = quote(&app, PANEL, json!({})).await;
    let qid = id(&q);
    quote_shipping(&app, &qid, "100").await;
    sqlx::query("UPDATE products.products SET vat_rate = 6 WHERE id = $1::uuid")
        .bind(PANEL)
        .execute(&db)
        .await
        .unwrap();
    sqlx::query("UPDATE products.products SET vat_rate = 12 WHERE id = $1::uuid")
        .bind(UNIT_100)
        .execute(&db)
        .await
        .unwrap();

    let two = json!([
        { "product_id": PANEL, "quantity": "1" },
        { "product_id": UNIT_100, "quantity": "1" }
    ]);
    let (status, p) = preview(&app, SALES, json!({ "quotation_id": qid, "lines": two })).await;
    assert_eq!(status, StatusCode::OK, "{p}");
    let ship = &p["lines"][2];
    assert_eq!(ship["product_code"], "SHIPPING");
    assert_eq!(dec(&ship["vat_rate"]), dec(&json!("12")));
    let rates: Vec<String> = p["vat_groups"]
        .as_array()
        .unwrap()
        .iter()
        .map(|g| dec(&g["vat_rate"]).to_string())
        .collect();
    assert_eq!(
        rates.len(),
        2,
        "6% on the panel, 12% on unit and shipping: {rates:?}"
    );

    // Saving yields the same lines and totals.
    let (status, saved) = api(
        &app,
        SALES,
        Method::PUT,
        &format!("/quotations/{qid}"),
        Some(json!({ "customer_id": ALPHA, "lines": two })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{saved}");
    same_lines(&p["lines"], &saved["lines"]);
    assert_eq!(dec(&p["total"]), dec(&saved["total"]));
    same_groups(&p["vat_groups"], &saved["vat_groups"]);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn preview_ignores_non_drafts_and_rejects_foreign_or_unknown_quotations(db: PgPool) {
    let app = setup(db.clone()).await;
    let q = quote(&app, PANEL, json!({})).await;
    let qid = id(&q);
    quote_shipping(&app, &qid, "180").await;
    let (_, plain) = preview(&app, SALES, json!({})).await;

    // Unknown id: 404.
    let (status, _) = preview(&app, SALES, json!({ "quotation_id": Uuid::now_v7() })).await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    // Another company's user cannot use this quotation's id (404, whatever the customer).
    let company = Uuid::now_v7();
    sqlx::query("INSERT INTO core.companies (id, name, country_code, currency) VALUES ($1, 'Other BV', 'BE', 'EUR')")
        .bind(company)
        .execute(&db)
        .await
        .unwrap();
    let user = Uuid::now_v7();
    sqlx::query("INSERT INTO core.users (id, email, display_name) VALUES ($1, $2, 'Other Sales')")
        .bind(user)
        .bind(OTHER)
        .execute(&db)
        .await
        .unwrap();
    sqlx::query("INSERT INTO core.user_companies (user_id, company_id, roles, is_default) VALUES ($1, $2, '{admin}', true)")
        .bind(user)
        .bind(company)
        .execute(&db)
        .await
        .unwrap();
    let (status, e) = preview(&app, OTHER, json!({ "quotation_id": qid })).await;
    assert_eq!(status, StatusCode::NOT_FOUND, "{e}");
    assert!(e.to_string().contains("quotation"), "{e}");

    // Sent: the preview is the plain product preview.
    let (status, _) = api(
        &app,
        SALES,
        Method::POST,
        &format!("/quotations/{qid}/send"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (status, p) = preview(&app, SALES, json!({ "quotation_id": qid })).await;
    assert_eq!(status, StatusCode::OK, "{p}");
    assert_eq!(p["lines"], plain["lines"]);
    assert_eq!(p["total"], plain["total"]);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn preview_without_a_shipping_request_is_unchanged(db: PgPool) {
    let app = setup(db).await;
    let q = quote(&app, UNIT_100, json!({})).await;
    let (_, plain) = preview(&app, SALES, json!({ "lines": lines(UNIT_100) })).await;
    let (status, p) = preview(
        &app,
        SALES,
        json!({ "quotation_id": id(&q), "lines": lines(UNIT_100) }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{p}");
    assert_eq!(p, plain);
}
