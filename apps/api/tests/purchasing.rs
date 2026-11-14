//! Purchasing (ADR 0031): suppliers, supplier price lists, purchase orders with their approval
//! flow, goods receipts against an order with the stock they post, and the permission guards.

mod common;

use axum::http::{Method, StatusCode};
use common::{call, call_portal, dec, setup};
use rust_decimal::Decimal;
use serde_json::{json, Value};
use sqlx::PgPool;
use uuid::Uuid;

const ADMIN: &str = "admin@example.com";
const SALES: &str = "sales@example.com";
const VIEWER: &str = "viewer@example.com";
const BUYER: &str = "buyer@example.com"; // role purchaser
const STORES: &str = "stores@example.com"; // role warehouse: receives goods, reads orders
const COMPANY: &str = "00000000-0000-7000-8000-000000000001";
const FRAME: &str = "00000000-0000-7000-8000-000000000307"; // pcs, no tracking
const PROFILE: &str = "00000000-0000-7000-8000-000000000308"; // metres
const BOLT: &str = "00000000-0000-7000-8000-000000000309"; // pcs, made lot-tracked in tests
const PUMP: &str = "00000000-0000-7000-8000-000000000303"; // serial
const MISSING: &str = "00000000-0000-7000-8000-0000000000ff";

async fn add_user(db: &PgPool, email: &str, role: &str) {
    let id = Uuid::now_v7();
    sqlx::query("INSERT INTO core.users (id, email, display_name) VALUES ($1, $2, $3)")
        .bind(id)
        .bind(email)
        .bind(email)
        .execute(db)
        .await
        .unwrap();
    sqlx::query("INSERT INTO core.user_companies (user_id, company_id, roles, is_default) VALUES ($1, $2::uuid, $3, true)")
        .bind(id)
        .bind(COMPANY)
        .bind(vec![role.to_string()])
        .execute(db)
        .await
        .unwrap();
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
async fn post(app: &axum::Router, user: &str, uri: &str, body: Value) -> (StatusCode, Value) {
    api(app, user, Method::POST, uri, Some(body)).await
}
async fn put(app: &axum::Router, user: &str, uri: &str, body: Value) -> (StatusCode, Value) {
    api(app, user, Method::PUT, uri, Some(body)).await
}
async fn get(app: &axum::Router, user: &str, uri: &str) -> (StatusCode, Value) {
    api(app, user, Method::GET, uri, None).await
}

fn q(s: &str) -> Decimal {
    s.parse().unwrap()
}

struct Env {
    app: axum::Router,
    db: PgPool,
    wh: String,
    main: String,
}

async fn env(db: PgPool) -> Env {
    let app = setup(db.clone()).await;
    add_user(&db, BUYER, "purchaser").await;
    add_user(&db, STORES, "warehouse").await;
    let (status, w) = post(
        &app,
        ADMIN,
        "/inventory/warehouses",
        json!({ "code": "WH1", "name": "Main warehouse" }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{w}");
    Env {
        app,
        db,
        wh: w["id"].as_str().unwrap().into(),
        main: w["locations"][0]["id"].as_str().unwrap().into(),
    }
}

impl Env {
    async fn supplier(&self, name: &str, code: &str) -> String {
        let (status, s) = post(
            &self.app,
            BUYER,
            "/suppliers",
            json!({ "name": name, "code": code, "country": "de" }),
        )
        .await;
        assert_eq!(status, StatusCode::CREATED, "{s}");
        s["id"].as_str().unwrap().into()
    }

    /// A draft order of 10 frames at 12.50 and 4.5 metres of profile at 3.333.
    async fn draft(&self, supplier: &str) -> Value {
        let (status, po) = post(
            &self.app,
            BUYER,
            "/purchase-orders",
            json!({
                "supplier_id": supplier,
                "lines": [
                    { "product_id": FRAME, "quantity": "10", "unit_price": "12.50" },
                    { "product_id": PROFILE, "quantity": "4.5", "unit_price": "3.333" }
                ]
            }),
        )
        .await;
        assert_eq!(status, StatusCode::CREATED, "{po}");
        po
    }

    async fn approved(&self, supplier: &str) -> Value {
        let po = self.draft(supplier).await;
        let id = po["id"].as_str().unwrap();
        let (status, po) = post(
            &self.app,
            BUYER,
            &format!("/purchase-orders/{id}/approve"),
            json!({}),
        )
        .await;
        assert_eq!(status, StatusCode::OK, "{po}");
        po
    }

    fn receipt_body(&self, lines: Value) -> Value {
        json!({ "warehouse_id": self.wh, "location_id": self.main, "lines": lines })
    }

    async fn receive(&self, po: &str, lines: Value) -> (StatusCode, Value) {
        post(
            &self.app,
            STORES,
            &format!("/purchase-orders/{po}/receipts"),
            self.receipt_body(lines),
        )
        .await
    }

    async fn on_hand(&self, product: &str) -> Decimal {
        let (status, p) = get(
            &self.app,
            ADMIN,
            &format!("/inventory/stock/products?product_id={product}"),
        )
        .await;
        assert_eq!(status, StatusCode::OK, "{p}");
        p["items"]
            .get(0)
            .map(|i| dec(&i["on_hand"]))
            .unwrap_or(Decimal::ZERO)
    }

    async fn status_of(&self, po: &str) -> String {
        let (status, p) = get(&self.app, ADMIN, &format!("/purchase-orders/{po}")).await;
        assert_eq!(status, StatusCode::OK, "{p}");
        p["status"].as_str().unwrap().into()
    }
}

// ---------------------------------------------------------------------------------------------
// Suppliers
// ---------------------------------------------------------------------------------------------

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn suppliers_are_created_listed_updated_and_deactivated(db: PgPool) {
    let e = env(db).await;
    let (status, s) = post(
        &e.app,
        BUYER,
        "/suppliers",
        json!({ "name": "  Nordic Motors  ", "code": " sup-001 ", "country": "se", "currency": "sek",
                "email": "sales@nordic.example", "payment_terms_days": 45 }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{s}");
    assert_eq!(s["name"], "Nordic Motors");
    assert_eq!(s["code"], "SUP-001");
    assert_eq!(s["country"], "SE");
    assert_eq!(s["currency"], "SEK");
    assert_eq!(s["payment_terms_days"], 45);
    assert_eq!(s["active"], true);
    let id = s["id"].as_str().unwrap().to_string();

    // Defaults: EUR and 30 days.
    let (status, d) = post(
        &e.app,
        BUYER,
        "/suppliers",
        json!({ "name": "Alpha Parts", "country": "DE" }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{d}");
    assert_eq!(d["currency"], "EUR");
    assert_eq!(d["payment_terms_days"], 30);
    let alpha = d["id"].as_str().unwrap().to_string();

    let (status, list) = get(&e.app, BUYER, "/suppliers").await;
    assert_eq!(status, StatusCode::OK);
    let names: Vec<&str> = list
        .as_array()
        .unwrap()
        .iter()
        .map(|s| s["name"].as_str().unwrap())
        .collect();
    assert_eq!(names, ["Alpha Parts", "Nordic Motors"], "ordered by name");

    let (status, got) = get(&e.app, VIEWER, &format!("/suppliers/{id}")).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(got["code"], "SUP-001");

    // A partial update only touches what is sent.
    let (status, u) = put(
        &e.app,
        BUYER,
        &format!("/suppliers/{id}"),
        json!({ "phone": " +46 8 123 ", "payment_terms_days": 60 }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{u}");
    assert_eq!(u["phone"], "+46 8 123");
    assert_eq!(u["payment_terms_days"], 60);
    assert_eq!(u["name"], "Nordic Motors");
    assert_eq!(u["email"], "sales@nordic.example");

    // Deactivate: hidden from the active-only list, refused for new orders.
    let (status, u) = put(
        &e.app,
        BUYER,
        &format!("/suppliers/{id}"),
        json!({ "active": false }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{u}");
    assert_eq!(u["active"], false);
    let (_, all) = get(&e.app, BUYER, "/suppliers").await;
    assert_eq!(all.as_array().unwrap().len(), 2);
    let (_, active) = get(&e.app, BUYER, "/suppliers?active_only=true").await;
    assert_eq!(active.as_array().unwrap().len(), 1);
    assert_eq!(active[0]["id"], alpha);
    let (status, _) = post(
        &e.app,
        BUYER,
        "/purchase-orders",
        json!({ "supplier_id": id, "lines": [{ "product_id": FRAME, "quantity": "1", "unit_price": "1" }] }),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND, "inactive supplier");
    // Reactivate.
    let (_, u) = put(
        &e.app,
        BUYER,
        &format!("/suppliers/{id}"),
        json!({ "active": true }),
    )
    .await;
    assert_eq!(u["active"], true);

    let (status, _) = get(&e.app, BUYER, &format!("/suppliers/{MISSING}")).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, _) = put(
        &e.app,
        BUYER,
        &format!("/suppliers/{MISSING}"),
        json!({ "name": "x" }),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn supplier_validation_and_duplicate_codes(db: PgPool) {
    let e = env(db).await;
    for body in [
        json!({ "name": "   ", "country": "DE" }),
        json!({ "name": "X", "country": "DEU" }),
        json!({ "name": "X", "country": "D" }),
    ] {
        let (status, err) = post(&e.app, BUYER, "/suppliers", body.clone()).await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{body} -> {err}");
        assert_eq!(err["error"], "validation");
    }
    // Missing mandatory field is a malformed body.
    let (status, _) = post(&e.app, BUYER, "/suppliers", json!({ "name": "X" })).await;
    assert!(status.is_client_error());
    assert_ne!(status, StatusCode::CREATED);

    let first = e.supplier("First", "SUP-1").await;
    let (status, err) = post(
        &e.app,
        BUYER,
        "/suppliers",
        json!({ "name": "Second", "code": "sup-1", "country": "DE" }),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT, "{err}");

    // Update validation and code clash.
    let second = e.supplier("Second", "SUP-2").await;
    let (status, _) = put(
        &e.app,
        BUYER,
        &format!("/suppliers/{second}"),
        json!({ "code": "SUP-1" }),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
    let (status, _) = put(
        &e.app,
        BUYER,
        &format!("/suppliers/{first}"),
        json!({ "name": " " }),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    let (status, _) = put(
        &e.app,
        BUYER,
        &format!("/suppliers/{first}"),
        json!({ "country": "Germany" }),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
}

// ---------------------------------------------------------------------------------------------
// Supplier price lists
// ---------------------------------------------------------------------------------------------

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn supplier_price_lists_are_set_updated_and_removed(db: PgPool) {
    let e = env(db).await;
    let s1 = e.supplier("One", "S1").await;
    let s2 = e.supplier("Two", "S2").await;

    let (status, sp) = post(
        &e.app,
        BUYER,
        &format!("/suppliers/{s1}/products/{FRAME}"),
        json!({ "supplier_product_code": " F-1 ", "unit_price": "12.50", "currency": "eur",
                "moq": "5", "lead_time_days": 14, "is_preferred": true }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{sp}");
    assert_eq!(sp["supplier_product_code"], "F-1");
    assert_eq!(dec(&sp["unit_price"]), q("12.5"));
    assert_eq!(dec(&sp["moq"]), q("5"));
    assert_eq!(sp["lead_time_days"], 14);
    assert_eq!(sp["is_preferred"], true);
    assert_eq!(sp["supplier_name"], "One");
    let first_id = sp["id"].clone();

    // Posting again for the same pair updates the row, it does not duplicate it.
    let (status, sp) = post(
        &e.app,
        BUYER,
        &format!("/suppliers/{s1}/products/{FRAME}"),
        json!({ "unit_price": "11.90", "is_preferred": true }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{sp}");
    assert_eq!(sp["id"], first_id);
    assert_eq!(dec(&sp["unit_price"]), q("11.9"));
    assert_eq!(dec(&sp["moq"]), q("1"), "moq falls back to its default");
    let (_, list) = get(&e.app, BUYER, &format!("/suppliers/{s1}/products")).await;
    assert_eq!(list.as_array().unwrap().len(), 1);

    // The second supplier takes over the preferred flag.
    let (status, _) = post(
        &e.app,
        BUYER,
        &format!("/suppliers/{s2}/products/{FRAME}"),
        json!({ "unit_price": "13", "is_preferred": true }),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (status, by_product) = get(&e.app, VIEWER, &format!("/products/{FRAME}/suppliers")).await;
    assert_eq!(status, StatusCode::OK);
    let rows = by_product.as_array().unwrap();
    assert_eq!(rows.len(), 2);
    assert_eq!(rows[0]["supplier_name"], "Two", "preferred first");
    assert_eq!(rows[0]["is_preferred"], true);
    assert_eq!(rows[1]["is_preferred"], false);
    assert_eq!(
        rows.iter().filter(|r| r["is_preferred"] == true).count(),
        1,
        "one preferred supplier per product"
    );

    // Delete.
    let (status, _) = api(
        &e.app,
        BUYER,
        Method::DELETE,
        &format!("/suppliers/{s2}/products/{FRAME}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    let (status, _) = api(
        &e.app,
        BUYER,
        Method::DELETE,
        &format!("/suppliers/{s2}/products/{FRAME}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (_, list) = get(&e.app, BUYER, &format!("/suppliers/{s2}/products")).await;
    assert_eq!(list, json!([]));
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn supplier_price_list_guards(db: PgPool) {
    let e = env(db).await;
    let s = e.supplier("One", "S1").await;
    let uri = format!("/suppliers/{s}/products/{FRAME}");

    let (status, err) = post(&e.app, BUYER, &uri, json!({ "unit_price": "-1" })).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{err}");
    for extra in [
        json!({ "moq": "0" }),
        json!({ "moq": "-2" }),
        json!({ "lead_time_days": -1 }),
    ] {
        let mut body = json!({ "unit_price": "1" });
        body.as_object_mut()
            .unwrap()
            .extend(extra.as_object().unwrap().clone());
        let (status, err) = post(&e.app, BUYER, &uri, body.clone()).await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{body} -> {err}");
    }
    // Unknown product and unknown supplier.
    let (status, err) = post(
        &e.app,
        BUYER,
        &format!("/suppliers/{s}/products/{MISSING}"),
        json!({ "unit_price": "1" }),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND, "{err}");
    let (status, _) = post(
        &e.app,
        BUYER,
        &format!("/suppliers/{MISSING}/products/{FRAME}"),
        json!({ "unit_price": "1" }),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    // Nothing was stored.
    let (_, list) = get(&e.app, BUYER, &format!("/suppliers/{s}/products")).await;
    assert_eq!(list, json!([]));
}

// ---------------------------------------------------------------------------------------------
// Purchase orders
// ---------------------------------------------------------------------------------------------

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn purchase_order_totals_are_computed_and_rounded(db: PgPool) {
    let e = env(db).await;
    let s = e.supplier("One", "S1").await;
    let po = e.draft(&s).await;
    assert_eq!(po["status"], "draft");
    assert_eq!(po["supplier_name"], "One");
    assert_eq!(po["currency"], "EUR");
    assert!(po["number"].as_str().unwrap().starts_with("PO20"));
    assert!(po["approved_by_user_id"].is_null());
    let lines = po["lines"].as_array().unwrap();
    assert_eq!(lines.len(), 2);
    assert_eq!(lines[0]["line_number"], 1);
    assert_eq!(lines[1]["line_number"], 2);
    assert_eq!(dec(&lines[0]["quantity"]), q("10"));
    assert_eq!(dec(&lines[0]["quantity_received"]), q("0"));
    assert_eq!(dec(&lines[0]["unit_price"]), q("12.5"));
    assert_eq!(dec(&lines[0]["line_total"]), q("125"));
    // 4.5 * 3.333 = 14.9985 -> 15.00
    assert_eq!(dec(&lines[1]["line_total"]), q("15.00"));
    assert_eq!(dec(&po["subtotal"]), q("140.00"));
    assert_eq!(dec(&po["tax_total"]), q("0"));
    assert_eq!(dec(&po["total"]), q("140.00"));

    // Numbers are sequential; currency override is normalised; list filters work.
    let (status, p2) = post(
        &e.app,
        BUYER,
        "/purchase-orders",
        json!({ "supplier_id": s, "currency": " usd ", "notes": " rush ",
                "order_date": "2027-03-01", "expected_delivery_date": "2027-03-15",
                "lines": [{ "product_id": FRAME, "quantity": "1", "unit_price": "0.005",
                           "supplier_product_code": "F-9", "description": "spare" }] }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{p2}");
    assert_eq!(p2["currency"], "USD");
    assert_eq!(p2["notes"], "rush");
    assert!(p2["number"].as_str().unwrap().starts_with("PO2027-"));
    assert_ne!(p2["number"], po["number"]);
    assert_eq!(p2["expected_delivery_date"], "2027-03-15");
    assert_eq!(p2["lines"][0]["supplier_product_code"], "F-9");
    assert_eq!(p2["lines"][0]["description"], "spare");
    // 1 * 0.005 rounds to 0.01 (away from zero at 2 dp).
    assert!(dec(&p2["total"]) <= q("0.01") && dec(&p2["total"]) >= q("0"));

    let (status, list) = get(&e.app, VIEWER, "/purchase-orders").await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(list.as_array().unwrap().len(), 2);
    let (_, by_status) = get(&e.app, VIEWER, "/purchase-orders?status=approved").await;
    assert_eq!(by_status, json!([]));
    let (_, by_status) = get(&e.app, VIEWER, "/purchase-orders?status=draft").await;
    assert_eq!(by_status.as_array().unwrap().len(), 2);
    let other = e.supplier("Other", "S2").await;
    let (_, by_supplier) = get(
        &e.app,
        VIEWER,
        &format!("/purchase-orders?supplier_id={other}"),
    )
    .await;
    assert_eq!(by_supplier, json!([]));
    let (_, both) = get(
        &e.app,
        VIEWER,
        &format!("/purchase-orders?supplier_id={s}&status=draft"),
    )
    .await;
    assert_eq!(both.as_array().unwrap().len(), 2);

    let id = po["id"].as_str().unwrap();
    let (status, got) = get(&e.app, VIEWER, &format!("/purchase-orders/{id}")).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(got["number"], po["number"]);
    assert_eq!(got["lines"].as_array().unwrap().len(), 2);
    let (status, _) = get(&e.app, VIEWER, &format!("/purchase-orders/{MISSING}")).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn purchase_order_validation(db: PgPool) {
    let e = env(db).await;
    let s = e.supplier("One", "S1").await;
    let line = |product: &str, qty: &str, price: &str| json!({ "product_id": product, "quantity": qty, "unit_price": price });

    let (status, err) = post(
        &e.app,
        BUYER,
        "/purchase-orders",
        json!({ "supplier_id": s, "lines": [] }),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{err}");
    assert_eq!(err["error"], "validation");

    // The product check names the offending line.
    let (status, err) = post(
        &e.app,
        BUYER,
        "/purchase-orders",
        json!({ "supplier_id": s, "lines": [line(FRAME, "1", "1"), line(MISSING, "1", "1")] }),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{err}");
    assert_eq!(err["error"], "validation");
    assert_eq!(err["message"], "line 2: product not found");

    let (status, err) = post(
        &e.app,
        BUYER,
        "/purchase-orders",
        json!({ "supplier_id": s, "lines": [line(FRAME, "0", "1")] }),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{err}");
    assert_eq!(err["message"], "line 1: quantity must be greater than zero");
    let (status, err) = post(
        &e.app,
        BUYER,
        "/purchase-orders",
        json!({ "supplier_id": s, "lines": [line(FRAME, "-3", "1")] }),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{err}");
    let (status, err) = post(
        &e.app,
        BUYER,
        "/purchase-orders",
        json!({ "supplier_id": s, "lines": [line(FRAME, "1", "-0.01")] }),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{err}");
    assert_eq!(err["message"], "line 1: unit price cannot be negative");

    // Unknown supplier.
    let (status, _) = post(
        &e.app,
        BUYER,
        "/purchase-orders",
        json!({ "supplier_id": MISSING, "lines": [line(FRAME, "1", "1")] }),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    // A free price of zero is fine.
    let (status, po) = post(
        &e.app,
        BUYER,
        "/purchase-orders",
        json!({ "supplier_id": s, "lines": [line(FRAME, "1", "0")] }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{po}");

    // Failed attempts left no orders behind (only the free one).
    let n: i64 = sqlx::query_scalar("SELECT count(*) FROM purchasing.purchase_orders")
        .fetch_one(&e.db)
        .await
        .unwrap();
    assert_eq!(n, 1, "rejected orders must not persist");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn line_totals_round_half_away_and_reject_excess_precision(db: PgPool) {
    let e = env(db).await;
    let s = e.supplier("One", "S1").await;
    let line = |qty: &str, price: &str| json!({ "product_id": FRAME, "quantity": qty, "unit_price": price });

    let (status, po) = post(
        &e.app,
        BUYER,
        "/purchase-orders",
        json!({ "supplier_id": s, "lines": [line("1", "0.005")] }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{po}");
    assert_eq!(q(po["lines"][0]["line_total"].as_str().unwrap()), q("0.01"));
    assert_eq!(q(po["total"].as_str().unwrap()), q("0.01"));

    for (qty, price) in [("1.00001", "1"), ("1", "0.00001")] {
        let (status, err) = post(
            &e.app,
            BUYER,
            "/purchase-orders",
            json!({ "supplier_id": s, "lines": [line(qty, price)] }),
        )
        .await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{err}");
        assert!(
            err["message"].as_str().unwrap().starts_with("line 1: "),
            "{err}"
        );
    }

    let (status, err) = post(
        &e.app,
        BUYER,
        "/purchase-orders",
        json!({ "supplier_id": s, "lines": [line("79228162514264337593543950335", "2")] }),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{err}");
    assert_eq!(err["message"], "line 1: amount too large");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn currency_must_be_three_letters(db: PgPool) {
    let e = env(db).await;
    for cur in ["EURO", "E1R", "  ", "€€€"] {
        let (status, err) = post(
            &e.app,
            BUYER,
            "/suppliers",
            json!({ "name": "X", "country": "DE", "currency": cur }),
        )
        .await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{cur}: {err}");
    }
    let s = e.supplier("One", "S1").await;
    let (status, err) = put(
        &e.app,
        BUYER,
        &format!("/suppliers/{s}"),
        json!({ "currency": "EU" }),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{err}");
    let (status, err) = post(
        &e.app,
        BUYER,
        &format!("/suppliers/{s}/products/{FRAME}"),
        json!({ "unit_price": "1", "currency": "US" }),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{err}");
    let (status, err) = post(
        &e.app,
        BUYER,
        "/purchase-orders",
        json!({ "supplier_id": s, "currency": "XX1", "lines": [{ "product_id": FRAME, "quantity": "1", "unit_price": "1" }] }),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{err}");
    // Lower case is normalized.
    let (status, sp) = post(
        &e.app,
        BUYER,
        &format!("/suppliers/{s}/products/{FRAME}"),
        json!({ "unit_price": "1", "currency": "usd" }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{sp}");
    assert_eq!(sp["currency"], "USD");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn draft_purchase_order_can_be_edited_until_approved(db: PgPool) {
    let e = env(db).await;
    let s = e.supplier("One", "S1").await;
    let po = e.draft(&s).await;
    let id = po["id"].as_str().unwrap().to_string();
    let uri = format!("/purchase-orders/{id}");

    let (status, u) = put(
        &e.app,
        BUYER,
        &uri,
        json!({
            "notes": "rush",
            "expected_delivery_date": "2030-01-15T00:00:00.000",
            "lines": [{ "product_id": FRAME, "quantity": "2", "unit_price": "5" }]
        }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{u}");
    assert_eq!(u["expected_delivery_date"], "2030-01-15");
    assert_eq!(u["notes"], "rush");
    assert_eq!(u["lines"].as_array().unwrap().len(), 1);
    assert_eq!(q(u["total"].as_str().unwrap()), q("10"));

    // Header-only change keeps the lines; invalid lines are rejected.
    let (status, u) = put(&e.app, BUYER, &uri, json!({ "notes": "again" })).await;
    assert_eq!(status, StatusCode::OK, "{u}");
    assert_eq!(u["lines"].as_array().unwrap().len(), 1);
    let (status, err) = put(&e.app, BUYER, &uri, json!({ "lines": [] })).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{err}");

    // Approved orders are frozen.
    let (status, _) = post(&e.app, BUYER, &format!("{uri}/approve"), json!({})).await;
    assert_eq!(status, StatusCode::OK);
    let (status, err) = put(&e.app, BUYER, &uri, json!({ "notes": "late" })).await;
    assert_eq!(status, StatusCode::CONFLICT, "{err}");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn purchase_order_status_transitions(db: PgPool) {
    let e = env(db).await;
    let s = e.supplier("One", "S1").await;

    // draft -> approved (records the approver), only once.
    let po = e.draft(&s).await;
    let id = po["id"].as_str().unwrap().to_string();
    let (status, a) = post(
        &e.app,
        BUYER,
        &format!("/purchase-orders/{id}/approve"),
        json!({}),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{a}");
    assert_eq!(a["status"], "approved");
    assert!(a["approved_by_user_id"].is_string());
    let (status, err) = post(
        &e.app,
        BUYER,
        &format!("/purchase-orders/{id}/approve"),
        json!({}),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT, "{err}");
    assert_eq!(err["error"], "conflict");

    // approved -> sent; a sent order cannot be approved or sent again.
    let (status, sent) = post(
        &e.app,
        BUYER,
        &format!("/purchase-orders/{id}/send"),
        json!({}),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{sent}");
    assert_eq!(sent["status"], "sent");
    let (status, _) = post(
        &e.app,
        BUYER,
        &format!("/purchase-orders/{id}/send"),
        json!({}),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
    let (status, _) = post(
        &e.app,
        BUYER,
        &format!("/purchase-orders/{id}/approve"),
        json!({}),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);

    // sent -> cancelled -> terminal.
    let (status, c) = post(
        &e.app,
        BUYER,
        &format!("/purchase-orders/{id}/cancel"),
        json!({}),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{c}");
    assert_eq!(c["status"], "cancelled");
    for action in ["approve", "send", "cancel"] {
        let (status, _) = post(
            &e.app,
            BUYER,
            &format!("/purchase-orders/{id}/{action}"),
            json!({}),
        )
        .await;
        assert_eq!(
            status,
            StatusCode::CONFLICT,
            "{action} on a cancelled order"
        );
    }

    // A draft cannot be sent; only an approved order can.
    let d = e.draft(&s).await;
    let (status, err) = post(
        &e.app,
        BUYER,
        &format!("/purchase-orders/{}/send", d["id"].as_str().unwrap()),
        json!({}),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT, "{err}");
    assert_eq!(e.status_of(d["id"].as_str().unwrap()).await, "draft");
    let ap = e.approved(&s).await;
    let (status, sent) = post(
        &e.app,
        BUYER,
        &format!("/purchase-orders/{}/send", ap["id"].as_str().unwrap()),
        json!({}),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{sent}");
    assert_eq!(sent["status"], "sent");
    // A draft can be cancelled.
    let d = e.draft(&s).await;
    let (status, c) = post(
        &e.app,
        BUYER,
        &format!("/purchase-orders/{}/cancel", d["id"].as_str().unwrap()),
        json!({}),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{c}");

    // Unknown order.
    for action in ["approve", "send", "cancel"] {
        let (status, _) = post(
            &e.app,
            BUYER,
            &format!("/purchase-orders/{MISSING}/{action}"),
            json!({}),
        )
        .await;
        assert_eq!(status, StatusCode::NOT_FOUND, "{action}");
    }

    // Each transition is audited.
    let n: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM audit.events WHERE entity = 'purchase_order' AND entity_id = $1::uuid",
    )
    .bind(&id)
    .fetch_one(&e.db)
    .await
    .unwrap();
    assert_eq!(n, 4, "created, approved, sent, cancelled");
}

// ---------------------------------------------------------------------------------------------
// Goods receipts
// ---------------------------------------------------------------------------------------------

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn partial_then_full_receipt_posts_stock_and_moves_the_order_status(db: PgPool) {
    let e = env(db).await;
    let s = e.supplier("One", "S1").await;
    let po = e.approved(&s).await;
    let po_id = po["id"].as_str().unwrap().to_string();
    let frame_line = po["lines"][0]["id"].as_str().unwrap().to_string();
    let profile_line = po["lines"][1]["id"].as_str().unwrap().to_string();
    assert_eq!(e.on_hand(FRAME).await, Decimal::ZERO);

    // Partial: 4 of 10 frames.
    let (status, gr) = e
        .receive(
            &po_id,
            json!([{ "po_line_id": frame_line, "quantity": "4" }]),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{gr}");
    assert!(gr["number"].as_str().unwrap().starts_with("GR20"));
    assert_eq!(gr["purchase_order_id"], po_id);
    assert_eq!(gr["purchase_order_number"], po["number"]);
    assert_eq!(gr["supplier_name"], "One");
    assert_eq!(gr["warehouse_id"], e.wh);
    assert_eq!(gr["location_id"], e.main);
    assert_eq!(gr["lines"].as_array().unwrap().len(), 1);
    assert_eq!(dec(&gr["lines"][0]["quantity_received"]), q("4"));
    assert_eq!(gr["lines"][0]["po_line_id"], frame_line);
    assert_eq!(e.on_hand(FRAME).await, q("4"));
    assert_eq!(e.status_of(&po_id).await, "partially_received");
    let (_, p) = get(&e.app, ADMIN, &format!("/purchase-orders/{po_id}")).await;
    assert_eq!(dec(&p["lines"][0]["quantity_received"]), q("4"));
    assert_eq!(dec(&p["lines"][1]["quantity_received"]), q("0"));

    // The stock move carries the PO price and points back at the receipt.
    let gr_id = gr["id"].as_str().unwrap();
    let (cost, reason): (Decimal, String) = sqlx::query_as(
        "SELECT unit_cost, reason FROM inventory.stock_moves WHERE reference_id = $1::uuid",
    )
    .bind(gr_id)
    .fetch_one(&e.db)
    .await
    .unwrap();
    assert_eq!(cost, q("12.5"));
    assert_eq!(reason, "purchase_receipt");

    // A partially received order cannot be cancelled any more.
    let (status, _) = post(
        &e.app,
        BUYER,
        &format!("/purchase-orders/{po_id}/cancel"),
        json!({}),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);

    // Over-receipt of the rest: 7 > 6 remaining -> rejected, nothing changes.
    let (status, err) = e
        .receive(
            &po_id,
            json!([{ "po_line_id": frame_line, "quantity": "7" }]),
        )
        .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{err}");
    assert_eq!(err["error"], "validation");
    assert_eq!(e.on_hand(FRAME).await, q("4"));
    assert_eq!(e.status_of(&po_id).await, "partially_received");

    // Rest of the frames (still partial: the profile is open) ...
    let (status, gr) = e
        .receive(
            &po_id,
            json!([{ "po_line_id": frame_line, "quantity": "6" }]),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{gr}");
    assert_eq!(e.status_of(&po_id).await, "partially_received");
    // ... then the profile, with a fractional quantity, completes the order.
    let (status, gr) = e
        .receive(
            &po_id,
            json!([{ "po_line_id": profile_line, "quantity": "4.5" }]),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{gr}");
    assert_eq!(e.status_of(&po_id).await, "received");
    assert_eq!(e.on_hand(FRAME).await, q("10"));
    assert_eq!(e.on_hand(PROFILE).await, q("4.5"));

    // Receipts are listed and readable; a received order takes no more goods or cancellation.
    let (status, list) = get(
        &e.app,
        VIEWER,
        &format!("/purchase-orders/{po_id}/receipts"),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(list.as_array().unwrap().len(), 3);
    let one = list[0]["id"].as_str().unwrap();
    let (status, got) = get(&e.app, VIEWER, &format!("/goods-receipts/{one}")).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(got["lines"].as_array().unwrap().len(), 1);
    let (status, _) = get(&e.app, VIEWER, &format!("/goods-receipts/{MISSING}")).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, _) = e
        .receive(
            &po_id,
            json!([{ "po_line_id": frame_line, "quantity": "1" }]),
        )
        .await;
    assert_eq!(status, StatusCode::CONFLICT);
    let (status, _) = post(
        &e.app,
        BUYER,
        &format!("/purchase-orders/{po_id}/cancel"),
        json!({}),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);

    // The ledger still adds up.
    let (status, i) = get(&e.app, ADMIN, "/inventory/integrity").await;
    assert_eq!(status, StatusCode::OK, "{i}");
    assert_eq!(i["ok"], true, "{i}");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn one_receipt_can_complete_the_whole_order(db: PgPool) {
    let e = env(db).await;
    let s = e.supplier("One", "S1").await;
    // A sent order may receive goods as well.
    let po = e.approved(&s).await;
    let po_id = po["id"].as_str().unwrap().to_string();
    let (status, _) = post(
        &e.app,
        BUYER,
        &format!("/purchase-orders/{po_id}/send"),
        json!({}),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (status, gr) = e
        .receive(
            &po_id,
            json!([
                { "po_line_id": po["lines"][0]["id"], "quantity": "10" },
                { "po_line_id": po["lines"][1]["id"], "quantity": "4.5" }
            ]),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{gr}");
    assert_eq!(gr["lines"].as_array().unwrap().len(), 2);
    assert_eq!(e.status_of(&po_id).await, "received");
    assert_eq!(e.on_hand(FRAME).await, q("10"));
    assert_eq!(e.on_hand(PROFILE).await, q("4.5"));
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn receipt_guards(db: PgPool) {
    let e = env(db).await;
    let s = e.supplier("One", "S1").await;
    let po = e.approved(&s).await;
    let po_id = po["id"].as_str().unwrap().to_string();
    let frame_line = po["lines"][0]["id"].clone();

    // A line of another order is "not on this order".
    let other = e.approved(&s).await;
    let (status, err) = e
        .receive(
            &po_id,
            json!([{ "po_line_id": other["lines"][0]["id"], "quantity": "1" }]),
        )
        .await;
    assert_eq!(status, StatusCode::NOT_FOUND, "{err}");
    let (status, _) = e
        .receive(&po_id, json!([{ "po_line_id": MISSING, "quantity": "1" }]))
        .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    // Empty receipt and non-positive quantities.
    let (status, _) = e.receive(&po_id, json!([])).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    for qty in ["0", "-1"] {
        let (status, _) = e
            .receive(
                &po_id,
                json!([{ "po_line_id": frame_line, "quantity": qty }]),
            )
            .await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "quantity {qty}");
    }

    // Destination must be an internal location of the stated warehouse.
    let (status, w2) = post(
        &e.app,
        ADMIN,
        "/inventory/warehouses",
        json!({ "code": "WH2", "name": "Second" }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{w2}");
    let (status, err) = post(
        &e.app,
        STORES,
        &format!("/purchase-orders/{po_id}/receipts"),
        json!({ "warehouse_id": w2["id"], "location_id": e.main,
                "lines": [{ "po_line_id": frame_line, "quantity": "1" }] }),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{err}");
    let (status, _) = post(
        &e.app,
        STORES,
        &format!("/purchase-orders/{po_id}/receipts"),
        json!({ "warehouse_id": e.wh, "location_id": MISSING,
                "lines": [{ "po_line_id": frame_line, "quantity": "1" }] }),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    // A failing second line rolls the whole receipt back, including the first line.
    let (status, err) = e
        .receive(
            &po_id,
            json!([
                { "po_line_id": frame_line, "quantity": "3" },
                { "po_line_id": po["lines"][1]["id"], "quantity": "99" }
            ]),
        )
        .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{err}");
    assert_eq!(e.on_hand(FRAME).await, Decimal::ZERO);
    let (_, p) = get(&e.app, ADMIN, &format!("/purchase-orders/{po_id}")).await;
    assert_eq!(dec(&p["lines"][0]["quantity_received"]), q("0"));
    assert_eq!(p["status"], "approved");
    let n: i64 = sqlx::query_scalar("SELECT count(*) FROM purchasing.goods_receipts")
        .fetch_one(&e.db)
        .await
        .unwrap();
    assert_eq!(n, 0, "rolled-back receipts leave no header");

    // Unknown order.
    let (status, _) = e
        .receive(
            MISSING,
            json!([{ "po_line_id": frame_line, "quantity": "1" }]),
        )
        .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn goods_cannot_be_received_on_a_draft_or_cancelled_order(db: PgPool) {
    let e = env(db).await;
    let s = e.supplier("One", "S1").await;

    let draft = e.draft(&s).await;
    let id = draft["id"].as_str().unwrap().to_string();
    let (status, err) = e
        .receive(
            &id,
            json!([{ "po_line_id": draft["lines"][0]["id"], "quantity": "1" }]),
        )
        .await;
    assert_eq!(status, StatusCode::CONFLICT, "unapproved: {err}");
    assert_eq!(e.on_hand(FRAME).await, Decimal::ZERO);

    let (status, _) = post(
        &e.app,
        BUYER,
        &format!("/purchase-orders/{id}/cancel"),
        json!({}),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (status, err) = e
        .receive(
            &id,
            json!([{ "po_line_id": draft["lines"][0]["id"], "quantity": "1" }]),
        )
        .await;
    assert_eq!(status, StatusCode::CONFLICT, "cancelled: {err}");
    assert_eq!(e.on_hand(FRAME).await, Decimal::ZERO);
    let (_, list) = get(&e.app, ADMIN, &format!("/purchase-orders/{id}/receipts")).await;
    assert_eq!(list, json!([]));
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn lot_and_serial_tracked_products_need_their_identifiers(db: PgPool) {
    let e = env(db).await;
    sqlx::query("UPDATE products.products SET tracking = 'lot' WHERE id = $1::uuid")
        .bind(BOLT)
        .execute(&e.db)
        .await
        .unwrap();
    let s = e.supplier("One", "S1").await;
    let (status, po) = post(
        &e.app,
        BUYER,
        "/purchase-orders",
        json!({ "supplier_id": s, "lines": [
            { "product_id": BOLT, "quantity": "100", "unit_price": "0.10" },
            { "product_id": PUMP, "quantity": "2", "unit_price": "500" }
        ] }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{po}");
    let po_id = po["id"].as_str().unwrap().to_string();
    post(
        &e.app,
        BUYER,
        &format!("/purchase-orders/{po_id}/approve"),
        json!({}),
    )
    .await;
    let bolt = po["lines"][0]["id"].clone();
    let pump = po["lines"][1]["id"].clone();

    // Lot-tracked without lot number.
    let (status, err) = e
        .receive(&po_id, json!([{ "po_line_id": bolt, "quantity": "50" }]))
        .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{err}");
    // With one it works and the lot is on the receipt line.
    let (status, gr) = e
        .receive(
            &po_id,
            json!([{ "po_line_id": bolt, "quantity": "50", "lot_number": "L-1" }]),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{gr}");
    assert_eq!(gr["lines"][0]["lot_number"], "L-1");
    assert_eq!(e.on_hand(BOLT).await, q("50"));

    // Serial-tracked: the number of serials must match the quantity.
    let (status, err) = e
        .receive(
            &po_id,
            json!([{ "po_line_id": pump, "quantity": "2", "serial_numbers": ["P-1"] }]),
        )
        .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{err}");
    let (status, err) = e
        .receive(&po_id, json!([{ "po_line_id": pump, "quantity": "2" }]))
        .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{err}");
    assert_eq!(e.on_hand(PUMP).await, Decimal::ZERO);
    // A trailing-zero whole quantity is accepted for serial products below ("2.0000").
    let (status, gr) = e
        .receive(
            &po_id,
            json!([{ "po_line_id": pump, "quantity": "2.0000", "serial_numbers": ["P-1", "P-2"] }]),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{gr}");
    assert_eq!(e.on_hand(PUMP).await, q("2"));
    let units: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM engineering.serial_units WHERE serial_number IN ('P-1', 'P-2')",
    )
    .fetch_one(&e.db)
    .await
    .unwrap();
    assert_eq!(units, 2, "serial units registered");
    // Bolts are still open.
    assert_eq!(e.status_of(&po_id).await, "partially_received");
}

// ---------------------------------------------------------------------------------------------
// Permissions
// ---------------------------------------------------------------------------------------------

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn viewer_and_sales_cannot_write_and_sales_cannot_even_read(db: PgPool) {
    let e = env(db).await;
    let s = e.supplier("One", "S1").await;
    let po = e.approved(&s).await;
    let po_id = po["id"].as_str().unwrap().to_string();
    let line = po["lines"][0]["id"].clone();
    let draft = e.draft(&s).await;
    let draft_id = draft["id"].as_str().unwrap().to_string();

    // Viewer: reads everything, writes nothing, approves nothing, receives nothing.
    for uri in [
        "/suppliers".to_string(),
        format!("/suppliers/{s}"),
        format!("/suppliers/{s}/products"),
        format!("/products/{FRAME}/suppliers"),
        "/purchase-orders".to_string(),
        format!("/purchase-orders/{po_id}"),
        format!("/purchase-orders/{po_id}/receipts"),
    ] {
        assert_eq!(get(&e.app, VIEWER, &uri).await.0, StatusCode::OK, "{uri}");
    }
    let writes: Vec<(Method, String, Option<Value>)> = vec![
        (
            Method::POST,
            "/suppliers".into(),
            Some(json!({ "name": "X", "country": "DE" })),
        ),
        (
            Method::PUT,
            format!("/suppliers/{s}"),
            Some(json!({ "name": "Y" })),
        ),
        (
            Method::POST,
            format!("/suppliers/{s}/products/{FRAME}"),
            Some(json!({ "unit_price": "1" })),
        ),
        (
            Method::DELETE,
            format!("/suppliers/{s}/products/{FRAME}"),
            None,
        ),
        (
            Method::POST,
            "/purchase-orders".into(),
            Some(
                json!({ "supplier_id": s, "lines": [{ "product_id": FRAME, "quantity": "1", "unit_price": "1" }] }),
            ),
        ),
        (
            Method::POST,
            format!("/purchase-orders/{draft_id}/approve"),
            Some(json!({})),
        ),
        (
            Method::POST,
            format!("/purchase-orders/{draft_id}/send"),
            Some(json!({})),
        ),
        (
            Method::POST,
            format!("/purchase-orders/{draft_id}/cancel"),
            Some(json!({})),
        ),
        (
            Method::POST,
            format!("/purchase-orders/{po_id}/receipts"),
            Some(e.receipt_body(json!([{ "po_line_id": line, "quantity": "1" }]))),
        ),
    ];
    for (method, uri, body) in &writes {
        let (status, err) = api(&e.app, VIEWER, method.clone(), uri, body.clone()).await;
        assert_eq!(status, StatusCode::FORBIDDEN, "viewer {method} {uri}");
        assert_eq!(err["error"], "forbidden");
    }

    // Sales has no purchasing rights whatsoever.
    for uri in [
        "/suppliers".to_string(),
        format!("/suppliers/{s}"),
        "/purchase-orders".to_string(),
        format!("/purchase-orders/{po_id}"),
        format!("/purchase-orders/{po_id}/receipts"),
        format!("/products/{FRAME}/suppliers"),
    ] {
        assert_eq!(
            get(&e.app, SALES, &uri).await.0,
            StatusCode::FORBIDDEN,
            "sales {uri}"
        );
    }
    for (method, uri, body) in &writes {
        let (status, _) = api(&e.app, SALES, method.clone(), uri, body.clone()).await;
        assert_eq!(status, StatusCode::FORBIDDEN, "sales {method} {uri}");
    }

    // None of the refused calls changed anything.
    assert_eq!(e.status_of(&draft_id).await, "draft");
    assert_eq!(e.on_hand(FRAME).await, Decimal::ZERO);
    let n: i64 = sqlx::query_scalar("SELECT count(*) FROM purchasing.suppliers")
        .fetch_one(&e.db)
        .await
        .unwrap();
    assert_eq!(n, 1);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn warehouse_receives_but_neither_writes_nor_approves(db: PgPool) {
    let e = env(db).await;
    let s = e.supplier("One", "S1").await;
    let draft = e.draft(&s).await;
    let draft_id = draft["id"].as_str().unwrap();
    assert_eq!(
        get(&e.app, STORES, "/purchase-orders").await.0,
        StatusCode::OK
    );
    let (status, _) = post(
        &e.app,
        STORES,
        &format!("/purchase-orders/{draft_id}/approve"),
        json!({}),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, _) = post(
        &e.app,
        STORES,
        "/suppliers",
        json!({ "name": "X", "country": "DE" }),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_purchaser_and_the_admin_run_the_whole_flow(db: PgPool) {
    let e = env(db).await;
    // The purchaser does everything, incl. goods receipt (also by the admin).
    let s = e.supplier("One", "S1").await;
    let po = e.draft(&s).await;
    let id = po["id"].as_str().unwrap().to_string();
    let (status, a) = post(
        &e.app,
        ADMIN,
        &format!("/purchase-orders/{id}/approve"),
        json!({}),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{a}");
    let (status, gr) = post(
        &e.app,
        BUYER,
        &format!("/purchase-orders/{id}/receipts"),
        e.receipt_body(json!([{ "po_line_id": po["lines"][0]["id"], "quantity": "10" }])),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{gr}");
    let (status, gr) = post(
        &e.app,
        ADMIN,
        &format!("/purchase-orders/{id}/receipts"),
        e.receipt_body(json!([{ "po_line_id": po["lines"][1]["id"], "quantity": "4.5" }])),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{gr}");
    assert_eq!(e.status_of(&id).await, "received");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn unauthenticated_requests_are_rejected(db: PgPool) {
    let e = env(db).await;
    for (method, uri) in [
        (Method::GET, "/api/v1/suppliers"),
        (Method::POST, "/api/v1/suppliers"),
        (Method::GET, "/api/v1/purchase-orders"),
        (Method::POST, "/api/v1/purchase-orders"),
    ] {
        // No staff header at all.
        let (status, _) = call_portal(&e.app, None, method.clone(), uri, Some(json!({}))).await;
        assert_eq!(status, StatusCode::UNAUTHORIZED, "{method} {uri}");
        // A user the system does not know.
        let (status, _) = call(
            &e.app,
            "nobody@example.com",
            method.clone(),
            uri,
            Some(json!({})),
        )
        .await;
        assert_eq!(status, StatusCode::UNAUTHORIZED, "{method} {uri}");
    }
    let (status, _) = call_portal(
        &e.app,
        None,
        Method::POST,
        &format!("/api/v1/purchase-orders/{MISSING}/approve"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}
