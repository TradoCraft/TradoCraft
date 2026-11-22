//! Delivery (ADR 0035): delivery notes for sales orders, picking from the reservations, partial
//! and full shipping, the closure policy and the permissions around it.

mod common;

use axum::http::{Method, StatusCode};
use common::{call, dec, raw, setup, Who};
use rust_decimal::Decimal;
use serde_json::{json, Value};
use sqlx::PgPool;
use uuid::Uuid;

const ADMIN: &str = "admin@example.com";
const SALES: &str = "sales@example.com";
const VIEWER: &str = "viewer@example.com";
const SUPPORT: &str = "support@example.com";
const LOGISTICS: &str = "logistics@example.com";
const STORES: &str = "stores@example.com"; // role warehouse
const COMPANY: &str = "00000000-0000-7000-8000-000000000001";
const ALPHA: &str = "00000000-0000-7000-8000-000000000401";
const FRAME: &str = "00000000-0000-7000-8000-000000000307"; // pcs, no tracking
const BOLT: &str = "00000000-0000-7000-8000-000000000309"; // pcs, made lot-tracked in tests
const PUMP: &str = "00000000-0000-7000-8000-000000000303"; // serial

fn uid() -> String {
    Uuid::now_v7().to_string()
}

fn q(s: &str) -> Decimal {
    s.parse().unwrap()
}

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

struct Env {
    app: axum::Router,
    db: PgPool,
    wh: String,
    main: String,
}

async fn env(db: PgPool) -> Env {
    let app = setup(db.clone()).await;
    env_with_app(db, app).await
}

async fn test_env(db: PgPool) -> Env {
    let app = common::setup_test_environment(db.clone()).await;
    env_with_app(db, app).await
}

async fn env_with_app(db: PgPool, app: axum::Router) -> Env {
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
        wh: id(&w),
        main: w["locations"][0]["id"].as_str().unwrap().into(),
    }
}

impl Env {
    async fn receive(&self, body: Value) -> Value {
        let mut body = body;
        body["id"] = json!(uid());
        body["location_id"] = json!(self.main);
        let (status, m) = post(&self.app, STORES, "/inventory/receipts", body).await;
        assert_eq!(status, StatusCode::CREATED, "{m}");
        m
    }

    async fn stock(&self, product: &str, quantity: &str) {
        self.receive(json!({ "product_id": product, "quantity": quantity }))
            .await;
    }

    /// A confirmed order of one line; returns (order id, line id).
    async fn order(&self, product: &str, quantity: &str) -> (String, String) {
        let (status, qn) = post(&self.app, SALES, "/quotations", json!({ "customer_id": ALPHA, "lines": [{ "product_id": product, "quantity": quantity }] })).await;
        assert_eq!(status, StatusCode::CREATED, "{qn}");
        let qid = qn["id"].as_str().unwrap();
        post(
            &self.app,
            SALES,
            &format!("/quotations/{qid}/send"),
            json!({}),
        )
        .await;
        let (status, o) = post(
            &self.app,
            SALES,
            &format!("/quotations/{qid}/convert"),
            json!({ "customer_reference": "PO" }),
        )
        .await;
        assert_eq!(status, StatusCode::CREATED, "{o}");
        (
            o["order"]["id"].as_str().unwrap().into(),
            o["lines"][0]["id"].as_str().unwrap().into(),
        )
    }

    async fn confirm(&self, order: &str) {
        let (status, o) = post(
            &self.app,
            SALES,
            &format!("/orders/{order}/send"),
            json!({}),
        )
        .await;
        assert_eq!(status, StatusCode::OK, "{o}");
        let (status, o) = post(
            &self.app,
            SALES,
            &format!("/orders/{order}/confirm"),
            json!({}),
        )
        .await;
        assert_eq!(status, StatusCode::OK, "{o}");
    }

    async fn reserve(&self, line: &str, quantity: &str) {
        let (status, r) = put(
            &self.app,
            STORES,
            &format!("/inventory/order-lines/{line}/reservation"),
            json!({ "quantity": quantity }),
        )
        .await;
        assert_eq!(status, StatusCode::OK, "{r}");
    }

    /// A confirmed order with stock on hand and reserved for it.
    async fn reserved_order(
        &self,
        product: &str,
        in_stock: &str,
        ordered: &str,
    ) -> (String, String) {
        self.stock(product, in_stock).await;
        let (order, line) = self.order(product, ordered).await;
        self.confirm(&order).await;
        self.reserve(&line, ordered).await;
        (order, line)
    }

    async fn order_status(&self, order: &str) -> String {
        sqlx::query_scalar("SELECT status FROM sales.orders WHERE id = $1::uuid")
            .bind(order)
            .fetch_one(&self.db)
            .await
            .unwrap()
    }

    async fn on_hand_and_reserved(&self, product: &str) -> (Decimal, Decimal) {
        let (status, p) = get(
            &self.app,
            ADMIN,
            &format!("/inventory/stock/products?product_id={product}"),
        )
        .await;
        assert_eq!(status, StatusCode::OK, "{p}");
        (
            dec(&p["items"][0]["on_hand"]),
            dec(&p["items"][0]["reserved"]),
        )
    }

    async fn integrity_ok(&self) {
        let (status, i) = get(&self.app, ADMIN, "/inventory/integrity").await;
        assert_eq!(status, StatusCode::OK, "{i}");
        assert_eq!(i["ok"], true, "{i}");
    }

    async fn plan(&self, order: &str, body: Value) -> (StatusCode, Value) {
        post(
            &self.app,
            LOGISTICS,
            &format!("/orders/{order}/deliveries"),
            body,
        )
        .await
    }

    async fn ship(&self, note: &str, body: Value) -> (StatusCode, Value) {
        post(&self.app, STORES, &format!("/deliveries/{note}/ship"), body).await
    }

    async fn set_policy(&self, policy: &str) {
        let (status, s) = put(
            &self.app,
            ADMIN,
            "/delivery/settings",
            json!({ "closure_policy": policy }),
        )
        .await;
        assert_eq!(status, StatusCode::OK, "{s}");
    }

    async fn close_alpha(&self, from: &str, to: &str) {
        let (status, c) = post(
            &self.app,
            SALES,
            &format!("/customers/{ALPHA}/closures"),
            json!({ "starts_on": from, "ends_on": to }),
        )
        .await;
        assert_eq!(status, StatusCode::CREATED, "{c}");
    }
}

fn id(v: &Value) -> String {
    v["id"].as_str().unwrap().to_string()
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn an_order_is_delivered_in_parts_from_its_reservations(db: PgPool) {
    let e = env(db).await;
    let (order, line) = e.reserved_order(FRAME, "10", "5").await;

    // The note starts with the reserved stock as its picking list.
    let (status, note) = e.plan(&order, json!({ "carrier": "DHL" })).await;
    assert_eq!(status, StatusCode::CREATED, "{note}");
    assert!(note["number"].as_str().unwrap().starts_with("DN"), "{note}");
    assert_eq!(note["status"], "planned");
    assert_eq!(note["carrier"], "DHL");
    assert_eq!(note["ship_to"]["name"], "Alpha Installaties NV");
    let lines = note["lines"].as_array().unwrap();
    assert_eq!(lines.len(), 1);
    assert_eq!(dec(&lines[0]["quantity"]), q("5"));
    assert_eq!(lines[0]["order_line_id"], line.as_str());
    assert_eq!(lines[0]["location_id"], e.main.as_str());
    let first = id(&note);

    // Ship part of it: the line is reduced, the rest stays reserved for the next delivery.
    let (status, n) = put(
        &e.app,
        LOGISTICS,
        &format!("/deliveries/{first}"),
        json!({ "carrier": "DHL", "lines": [{ "order_line_id": line, "quantity": "2", "location_id": e.main }] }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{n}");
    let (status, shipped) = e
        .ship(&first, json!({ "tracking_number": "JVGL0001" }))
        .await;
    assert_eq!(status, StatusCode::OK, "{shipped}");
    assert_eq!(shipped["status"], "shipped");
    assert_eq!(shipped["tracking_number"], "JVGL0001");
    assert!(shipped["lines"][0]["stock_move_id"].is_string());
    assert_eq!(e.order_status(&order).await, "partially_shipped");
    assert_eq!(e.on_hand_and_reserved(FRAME).await, (q("8"), q("3")));

    // The move names the delivery note and consumed the reservation.
    let (_, mv) = get(
        &e.app,
        ADMIN,
        &format!(
            "/inventory/moves/{}",
            shipped["lines"][0]["stock_move_id"].as_str().unwrap()
        ),
    )
    .await;
    assert_eq!(mv["reason"], "shipment");
    assert_eq!(mv["reference_type"], "delivery_note");

    // A partly shipped order cannot be cancelled; the second delivery proposes the remaining 3.
    let (status, _) = post(
        &e.app,
        SALES,
        &format!("/orders/{order}/cancel"),
        json!({ "reason": "x" }),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
    let (status, second) = e.plan(&order, json!({})).await;
    assert_eq!(status, StatusCode::CREATED, "{second}");
    assert_eq!(dec(&second["lines"][0]["quantity"]), q("3"));
    let (status, done) = e.ship(&id(&second), json!({})).await;
    assert_eq!(status, StatusCode::OK, "{done}");
    assert_eq!(e.order_status(&order).await, "shipped");
    assert_eq!(e.on_hand_and_reserved(FRAME).await, (q("5"), q("0")));

    // Nothing is left: no further delivery, no changes to shipped notes.
    let (status, _) = e.plan(&order, json!({})).await;
    assert_eq!(status, StatusCode::CONFLICT);
    for (method, uri, body) in [
        (Method::PUT, format!("/deliveries/{first}"), json!({})),
        (
            Method::POST,
            format!("/deliveries/{first}/cancel"),
            json!({ "reason": "x" }),
        ),
        (Method::POST, format!("/deliveries/{first}/ship"), json!({})),
    ] {
        let (status, r) = api(&e.app, ADMIN, method, &uri, Some(body)).await;
        assert_eq!(status, StatusCode::CONFLICT, "{uri} {r}");
    }
    let (status, list) = get(&e.app, VIEWER, &format!("/orders/{order}/deliveries")).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(list.as_array().unwrap().len(), 2);
    e.integrity_ok().await;
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn lines_stay_within_the_order_and_a_cancelled_note_frees_its_quantity(db: PgPool) {
    let e = env(db).await;
    e.stock(FRAME, "20").await;
    let (order, line) = e.order(FRAME, "5").await;

    // Only a confirmed order can be delivered.
    let (status, r) = e.plan(&order, json!({})).await;
    assert_eq!(status, StatusCode::CONFLICT, "{r}");
    e.confirm(&order).await;
    e.reserve(&line, "5").await;

    let (_, note) = e.plan(&order, json!({})).await;
    let n = id(&note);
    // More than ordered is refused; unreserved stock can be picked by naming the location.
    let (status, r) = put(
        &e.app,
        LOGISTICS,
        &format!("/deliveries/{n}"),
        json!({ "lines": [{ "order_line_id": line, "quantity": "6", "location_id": e.main }] }),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT, "{r}");
    for lines in [
        json!([{ "order_line_id": line, "quantity": "0", "location_id": e.main }]),
        json!([{ "order_line_id": line, "quantity": "1", "location_id": uid() }]),
        json!([{ "order_line_id": uid(), "quantity": "1", "location_id": e.main }]),
    ] {
        let (status, r) = put(
            &e.app,
            LOGISTICS,
            &format!("/deliveries/{n}"),
            json!({ "lines": lines }),
        )
        .await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{r}");
    }

    // The quantity of a planned note is not available to another one; cancelling frees it.
    let (status, again) = e.plan(&order, json!({})).await;
    assert_eq!(
        status,
        StatusCode::CONFLICT,
        "everything is on the planned note: {again}"
    );
    let (status, _) = post(
        &e.app,
        LOGISTICS,
        &format!("/deliveries/{n}/cancel"),
        json!({}),
    )
    .await;
    assert_eq!(
        status,
        StatusCode::UNPROCESSABLE_ENTITY,
        "a reason is required"
    );
    let (status, c) = post(
        &e.app,
        LOGISTICS,
        &format!("/deliveries/{n}/cancel"),
        json!({ "reason": "customer asked" }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{c}");
    assert_eq!(c["status"], "cancelled");
    let (status, _) = e.ship(&n, json!({})).await;
    assert_eq!(status, StatusCode::CONFLICT, "a cancelled note cannot ship");
    let (status, fresh) = e.plan(&order, json!({})).await;
    assert_eq!(status, StatusCode::CREATED, "{fresh}");
    assert_eq!(dec(&fresh["lines"][0]["quantity"]), q("5"));

    // An empty note cannot ship.
    let (status, empty) = put(
        &e.app,
        LOGISTICS,
        &format!("/deliveries/{}", id(&fresh)),
        json!({ "lines": [] }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{empty}");
    let (status, r) = e.ship(&id(&fresh), json!({})).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{r}");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_closure_follows_the_policy_of_the_company(db: PgPool) {
    let e = env(db).await;
    let (order, _) = e.reserved_order(FRAME, "10", "4").await;
    e.close_alpha("2099-06-10", "2099-06-12").await;

    // Default: warn only. The date is kept, the warning says when the customer is open again.
    let (status, s) = get(&e.app, VIEWER, "/delivery/settings").await;
    assert_eq!(
        (status, s["closure_policy"].as_str()),
        (StatusCode::OK, Some("warn"))
    );
    let (status, note) = e
        .plan(&order, json!({ "planned_date": "2099-06-11" }))
        .await;
    assert_eq!(status, StatusCode::CREATED, "{note}");
    assert_eq!(note["planned_on_closure"], true);
    assert_eq!(note["closure_warning"]["next_open_day"], "2099-06-13");
    assert_eq!(
        note["closure_warning"]["closure"]["starts_on"],
        "2099-06-10"
    );
    let n = id(&note);

    // Moving to an open day clears it; a closure added later shows up live.
    let (status, moved) = put(
        &e.app,
        LOGISTICS,
        &format!("/deliveries/{n}"),
        json!({ "planned_date": "2099-06-13" }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{moved}");
    assert_eq!(moved["planned_on_closure"], false);
    assert_eq!(moved["closure_warning"], Value::Null);
    e.close_alpha("2099-06-13", "2099-06-14").await;
    let (_, live) = get(&e.app, VIEWER, &format!("/deliveries/{n}")).await;
    assert_eq!(
        live["closure_warning"]["next_open_day"], "2099-06-15",
        "chained closures"
    );

    // Override: a reason and the permission are needed.
    e.set_policy("override").await;
    let day = json!({ "planned_date": "2099-06-11" });
    let (status, r) = put(&e.app, LOGISTICS, &format!("/deliveries/{n}"), day.clone()).await;
    assert_eq!(status, StatusCode::CONFLICT, "{r}");
    assert_eq!(r["code"], "closure_override_required");
    let with_reason = json!({ "planned_date": "2099-06-11", "closure_override_reason": "they receive on request" });
    let (status, r) = put(
        &e.app,
        SALES,
        &format!("/deliveries/{n}"),
        with_reason.clone(),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN, "{r}");
    let (status, ok) = put(&e.app, LOGISTICS, &format!("/deliveries/{n}"), with_reason).await;
    assert_eq!(status, StatusCode::OK, "{ok}");
    assert_eq!(ok["planned_on_closure"], true);
    assert_eq!(ok["closure_override_reason"], "they receive on request");

    // Block: always refused, but editing something else on a date that was already accepted is fine.
    e.set_policy("block").await;
    let (status, r) = put(
        &e.app,
        ADMIN,
        &format!("/deliveries/{n}"),
        json!({ "planned_date": "2099-06-12" }),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT, "{r}");
    assert_eq!(r["code"], "customer_closed");
    assert!(r["message"].as_str().unwrap().contains("2099-06-15"), "{r}");
    let (status, r) = e
        .plan(&order, json!({ "planned_date": "2099-06-10" }))
        .await;
    assert_eq!(status, StatusCode::CONFLICT, "{r}");
    let (status, ok) = put(
        &e.app,
        LOGISTICS,
        &format!("/deliveries/{n}"),
        json!({ "planned_date": "2099-06-11", "carrier": "UPS" }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{ok}");
    assert_eq!(ok["carrier"], "UPS");

    // A note without a date is never held up.
    let (status, none) = put(&e.app, LOGISTICS, &format!("/deliveries/{n}"), json!({})).await;
    assert_eq!(status, StatusCode::OK, "{none}");
    assert_eq!(none["planned_date"], Value::Null);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn settings_are_validated_audited_and_for_the_administrator(db: PgPool) {
    let e = env(db).await;
    for user in [SALES, LOGISTICS, STORES, VIEWER] {
        let (status, _) = put(
            &e.app,
            user,
            "/delivery/settings",
            json!({ "closure_policy": "block" }),
        )
        .await;
        assert_eq!(status, StatusCode::FORBIDDEN, "{user}");
    }
    let (status, r) = put(
        &e.app,
        ADMIN,
        "/delivery/settings",
        json!({ "closure_policy": "ignore" }),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{r}");
    e.set_policy("block").await;
    let (_, s) = get(&e.app, SALES, "/delivery/settings").await;
    assert_eq!(s["closure_policy"], "block");
    let audited: i64 = sqlx::query_scalar("SELECT count(*) FROM audit.events WHERE entity = 'delivery_settings' AND action = 'settings_updated'")
        .fetch_one(&e.db).await.unwrap();
    assert_eq!(audited, 1);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn lot_and_serial_tracked_goods_are_picked_by_lot_and_unit(db: PgPool) {
    let e = env(db).await;
    // Lot-tracked: the line carries the reserved lot.
    sqlx::query("UPDATE products.products SET tracking = 'lot' WHERE id = $1::uuid")
        .bind(BOLT)
        .execute(&e.db)
        .await
        .unwrap();
    e.receive(json!({ "product_id": BOLT, "quantity": "10", "lot_number": "L-A" }))
        .await;
    let (order, line) = e.order(BOLT, "4").await;
    e.confirm(&order).await;
    e.reserve(&line, "4").await;
    let (status, note) = e.plan(&order, json!({})).await;
    assert_eq!(status, StatusCode::CREATED, "{note}");
    assert_eq!(note["lines"][0]["lot_number"], "L-A");
    let (status, done) = e.ship(&id(&note), json!({})).await;
    assert_eq!(status, StatusCode::OK, "{done}");
    assert_eq!(e.on_hand_and_reserved(BOLT).await, (q("6"), q("0")));

    // Serial-tracked: one line per unit; the serial number is chosen before shipping.
    let m = e
        .receive(json!({ "product_id": PUMP, "quantity": "1", "serial_number": "P-D-2" }))
        .await;
    let unit = m["serial_unit_id"].as_str().unwrap().to_string();
    let (order, line) = e.order(PUMP, "1").await;
    e.confirm(&order).await;
    e.reserve(&line, "1").await;
    let (status, note) = e.plan(&order, json!({})).await;
    assert_eq!(status, StatusCode::CREATED, "{note}");
    assert_eq!(note["lines"].as_array().unwrap().len(), 1);
    assert_eq!(note["lines"][0]["serial_unit_id"], Value::Null);
    let n = id(&note);
    let (status, r) = e.ship(&n, json!({})).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{r}");
    assert!(
        r["message"].as_str().unwrap().contains("serial number"),
        "{r}"
    );
    let (status, r) = put(&e.app, LOGISTICS, &format!("/deliveries/{n}"), json!({ "lines": [{ "order_line_id": line, "quantity": "2", "location_id": e.main, "serial_unit_id": unit }] })).await;
    assert_eq!(
        status,
        StatusCode::UNPROCESSABLE_ENTITY,
        "one unit per line: {r}"
    );
    let (status, r) = put(&e.app, LOGISTICS, &format!("/deliveries/{n}"), json!({ "lines": [{ "order_line_id": line, "quantity": "1", "location_id": e.main, "serial_unit_id": unit }] })).await;
    assert_eq!(status, StatusCode::OK, "{r}");
    assert_eq!(r["lines"][0]["serial_number"], "P-D-2");
    let (status, done) = e.ship(&n, json!({})).await;
    assert_eq!(status, StatusCode::OK, "{done}");
    let (_, d) = get(&e.app, ADMIN, &format!("/serials/{unit}")).await;
    assert_eq!(d["unit"]["status"], "delivered");
    assert_eq!(d["unit"]["customer_id"], ALPHA);
    e.integrity_ok().await;
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn permissions_separate_reading_planning_and_shipping(db: PgPool) {
    let e = env(db).await;
    let (order, _) = e.reserved_order(FRAME, "10", "2").await;

    // Planning: sales, logistics and the warehouse; not support or a viewer.
    for user in [SUPPORT, VIEWER] {
        let (status, _) = post(
            &e.app,
            user,
            &format!("/orders/{order}/deliveries"),
            json!({}),
        )
        .await;
        assert_eq!(status, StatusCode::FORBIDDEN, "{user}");
    }
    let (status, note) = post(
        &e.app,
        SALES,
        &format!("/orders/{order}/deliveries"),
        json!({}),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{note}");
    let n = id(&note);

    // Shipping: logistics and the warehouse; not sales.
    let (status, _) = post(&e.app, SALES, &format!("/deliveries/{n}/ship"), json!({})).await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, _) = post(&e.app, SUPPORT, &format!("/deliveries/{n}/ship"), json!({})).await;
    assert_eq!(status, StatusCode::FORBIDDEN);

    // Reading: customer service and viewers can follow a delivery.
    for user in [SUPPORT, VIEWER, "dispatcher@example.com"] {
        let (status, _) = get(&e.app, user, &format!("/deliveries/{n}")).await;
        assert_eq!(status, StatusCode::OK, "{user}");
    }
    let (status, _) = get(
        &e.app,
        "technician@example.com",
        &format!("/deliveries/{n}"),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, _) = get(&e.app, "technician@example.com", "/deliveries").await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, _) = post(
        &e.app,
        LOGISTICS,
        &format!("/deliveries/{n}/ship"),
        json!({}),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn notes_are_listed_with_filters(db: PgPool) {
    let e = env(db).await;
    let (a, _) = e.reserved_order(FRAME, "10", "2").await;
    let (b, _) = e.reserved_order(FRAME, "10", "3").await;
    let (_, na) = e.plan(&a, json!({ "planned_date": "2099-03-01" })).await;
    let (_, nb) = e
        .plan(
            &b,
            json!({ "planned_date": "2099-04-01", "carrier": "UPS" }),
        )
        .await;
    e.ship(&id(&nb), json!({ "tracking_number": "TRK-777" }))
        .await;

    let (status, all) = get(&e.app, VIEWER, "/deliveries").await;
    assert_eq!(status, StatusCode::OK, "{all}");
    assert_eq!(all["total"], 2);
    assert_eq!(
        all["items"][0]["id"],
        id(&nb).as_str(),
        "latest planned date first"
    );
    assert_eq!(all["items"][0]["line_count"], 1);
    let (_, planned) = get(&e.app, VIEWER, "/deliveries?status=planned").await;
    assert_eq!(planned["total"], 1);
    assert_eq!(planned["items"][0]["id"], id(&na).as_str());
    let (_, found) = get(&e.app, VIEWER, "/deliveries?q=TRK-777").await;
    assert_eq!(found["total"], 1);
    let (_, ranged) = get(
        &e.app,
        VIEWER,
        "/deliveries?planned_from=2099-03-15&planned_to=2099-04-30",
    )
    .await;
    assert_eq!(ranged["total"], 1);
    let (status, _) = get(&e.app, VIEWER, "/deliveries?status=nope").await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_delivery_note_is_a_pdf_in_the_language_of_the_customer(db: PgPool) {
    let e = env(db).await;
    let (order, _) = e.reserved_order(FRAME, "10", "2").await;
    let (_, note) = e
        .plan(
            &order,
            json!({ "planned_date": "2099-05-04", "carrier": "DHL" }),
        )
        .await;
    let n = id(&note);
    let pdf = |user: &'static str, query: String| {
        let app = e.app.clone();
        let n = n.clone();
        async move {
            raw(
                &app,
                Who::Staff(user),
                Method::GET,
                &format!("/api/v1/deliveries/{n}/pdf{query}"),
                None,
            )
            .await
        }
    };

    // A planned note is a preview; every language renders; readers can open it.
    let (status, headers, bytes) = pdf(VIEWER, String::new()).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(headers["content-type"], "application/pdf");
    assert!(bytes.starts_with(b"%PDF"));
    for lang in ["nl", "fr", "en", "de", "es"] {
        let (status, _, bytes) = pdf(SUPPORT, format!("?lang={lang}")).await;
        assert_eq!(status, StatusCode::OK, "{lang}");
        assert!(bytes.starts_with(b"%PDF"), "{lang}");
    }
    let (status, _, _) = pdf(VIEWER, "?lang=xx".into()).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    let (status, _, _) = pdf("technician@example.com", String::new()).await;
    assert_eq!(status, StatusCode::FORBIDDEN);

    // The shipped note is the final document.
    let (status, _) = e.ship(&n, json!({ "tracking_number": "TRK-1" })).await;
    assert_eq!(status, StatusCode::OK);
    let (status, headers, bytes) = pdf(SALES, String::new()).await;
    assert_eq!(status, StatusCode::OK);
    assert!(bytes.starts_with(b"%PDF"));
    assert!(headers["content-disposition"]
        .to_str()
        .unwrap()
        .contains(".pdf"));
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_pick_takes_the_reserved_part_from_the_reservation_and_the_rest_from_free_stock(
    db: PgPool,
) {
    let e = env(db).await;
    e.stock(FRAME, "10").await;
    let (order, line) = e.order(FRAME, "5").await;
    e.confirm(&order).await;
    e.reserve(&line, "3").await;

    // The note proposes what is reserved; the planner picks all five (two are free stock).
    let (_, note) = e.plan(&order, json!({})).await;
    assert_eq!(dec(&note["lines"][0]["quantity"]), q("3"));
    let n = id(&note);
    let (status, r) = put(
        &e.app,
        LOGISTICS,
        &format!("/deliveries/{n}"),
        json!({ "lines": [{ "order_line_id": line, "quantity": "5", "location_id": e.main }] }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{r}");
    let (status, done) = e.ship(&n, json!({})).await;
    assert_eq!(status, StatusCode::OK, "{done}");
    assert_eq!(e.order_status(&order).await, "shipped");
    assert_eq!(e.on_hand_and_reserved(FRAME).await, (q("5"), q("0")));
    e.integrity_ok().await;

    // Stock that was never reserved can be delivered too: the note starts empty, the planner
    // names the location.
    let (order, line) = e.order(FRAME, "2").await;
    e.confirm(&order).await;
    let (status, note) = e.plan(&order, json!({})).await;
    assert_eq!(status, StatusCode::CREATED, "{note}");
    assert_eq!(note["lines"].as_array().unwrap().len(), 0);
    let n = id(&note);
    let (status, r) = put(
        &e.app,
        LOGISTICS,
        &format!("/deliveries/{n}"),
        json!({ "lines": [{ "order_line_id": line, "quantity": "2", "location_id": e.main }] }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{r}");
    let (status, done) = e.ship(&n, json!({})).await;
    assert_eq!(status, StatusCode::OK, "{done}");
    assert_eq!(e.order_status(&order).await, "shipped");
    assert_eq!(e.on_hand_and_reserved(FRAME).await, (q("3"), q("0")));
    e.integrity_ok().await;
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn goods_shipped_outside_a_delivery_note_count_as_delivered(db: PgPool) {
    let e = env(db).await;
    let (order, line) = e.reserved_order(FRAME, "10", "5").await;
    // Two pieces leave through a plain shipment issue that names the order line.
    let (status, m) = post(
        &e.app,
        STORES,
        "/inventory/issues",
        json!({ "id": uid(), "product_id": FRAME, "location_id": e.main, "quantity": "2",
                "reason": "shipment", "consume_reservation_line": line }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{m}");

    // The note asks for the three that are left, and shipping them completes the order.
    let (_, note) = e.plan(&order, json!({})).await;
    assert_eq!(dec(&note["lines"][0]["quantity"]), q("3"));
    let n = id(&note);
    let (status, r) = put(
        &e.app,
        LOGISTICS,
        &format!("/deliveries/{n}"),
        json!({ "lines": [{ "order_line_id": line, "quantity": "4", "location_id": e.main }] }),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT, "four is too much: {r}");
    let (status, done) = e.ship(&n, json!({})).await;
    assert_eq!(status, StatusCode::OK, "{done}");
    assert_eq!(e.order_status(&order).await, "shipped");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn expired_lots_are_neither_proposed_nor_shipped(db: PgPool) {
    let e = env(db).await;
    sqlx::query("UPDATE products.products SET tracking = 'lot' WHERE id = $1::uuid")
        .bind(BOLT)
        .execute(&e.db)
        .await
        .unwrap();
    e.receive(json!({ "product_id": BOLT, "quantity": "10", "lot_number": "L-OLD", "expiry_date": "2099-01-01" }))
        .await;
    let (order, line) = e.order(BOLT, "4").await;
    e.confirm(&order).await;
    e.reserve(&line, "4").await;
    // The lot expires after the stock was reserved.
    sqlx::query(
        "UPDATE inventory.lots SET expiry_date = current_date - 1 WHERE lot_number = 'L-OLD'",
    )
    .execute(&e.db)
    .await
    .unwrap();
    let (status, note) = e.plan(&order, json!({})).await;
    assert_eq!(status, StatusCode::CREATED, "{note}");
    assert_eq!(note["lines"].as_array().unwrap().len(), 0, "{note}");
    let lot: String =
        sqlx::query_scalar("SELECT id::text FROM inventory.lots WHERE lot_number = 'L-OLD'")
            .fetch_one(&e.db)
            .await
            .unwrap();
    let n = id(&note);
    let (status, r) = put(
        &e.app,
        LOGISTICS,
        &format!("/deliveries/{n}"),
        json!({ "lines": [{ "order_line_id": line, "quantity": "4", "location_id": e.main, "lot_id": lot }] }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{r}");
    let (status, r) = e.ship(&n, json!({})).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{r}");
    assert!(r["message"].as_str().unwrap().contains("expiry"), "{r}");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_shipped_delivery_cannot_be_reversed_as_a_plain_stock_move(db: PgPool) {
    let e = env(db).await;
    let (order, _) = e.reserved_order(FRAME, "10", "2").await;
    let (_, note) = e.plan(&order, json!({})).await;
    let (status, shipped) = e.ship(&id(&note), json!({})).await;
    assert_eq!(status, StatusCode::OK, "{shipped}");
    let mv = shipped["lines"][0]["stock_move_id"].as_str().unwrap();
    let (status, r) = post(
        &e.app,
        ADMIN,
        &format!("/inventory/moves/{mv}/reverse"),
        json!({ "id": uid(), "note": "oops" }),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT, "{r}");
    assert_eq!(e.on_hand_and_reserved(FRAME).await.0, q("8"));
    e.integrity_ok().await;
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_cancelled_order_cancels_its_planned_notes_and_a_stale_edit_is_refused(db: PgPool) {
    let e = env(db).await;
    let (order, _) = e.reserved_order(FRAME, "10", "2").await;
    let (_, note) = e
        .plan(&order, json!({ "planned_date": "2099-05-04" }))
        .await;
    let n = id(&note);

    // Someone else saved the note since it was loaded.
    let loaded = note["updated_at"].clone();
    let (status, _) = put(
        &e.app,
        LOGISTICS,
        &format!("/deliveries/{n}"),
        json!({ "carrier": "UPS", "expected_updated_at": loaded }),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (status, r) = put(
        &e.app,
        LOGISTICS,
        &format!("/deliveries/{n}"),
        json!({ "carrier": "DHL", "expected_updated_at": loaded }),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT, "{r}");
    assert_eq!(r["code"], "delivery_note_changed");

    // Cancelling the order cancels what was planned for it.
    let (status, _) = post(
        &e.app,
        SALES,
        &format!("/orders/{order}/cancel"),
        json!({ "reason": "customer withdrew" }),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (_, n_after) = get(&e.app, VIEWER, &format!("/deliveries/{n}")).await;
    assert_eq!(n_after["status"], "cancelled");
    assert_eq!(n_after["closure_warning"], Value::Null);
    let (_, planned) = get(&e.app, VIEWER, "/deliveries?status=planned").await;
    assert_eq!(planned["total"], 0);
    let (_, cancelled) = get(&e.app, VIEWER, "/deliveries?status=cancelled").await;
    assert_eq!(cancelled["total"], 1);
    let (status, _) = put(&e.app, LOGISTICS, &format!("/deliveries/{n}"), json!({})).await;
    assert_eq!(status, StatusCode::CONFLICT, "no changes");
    let (status, _) = e.ship(&n, json!({})).await;
    assert_eq!(status, StatusCode::CONFLICT, "no shipping");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn serial_numbers_are_offered_from_the_location_of_the_pick(db: PgPool) {
    let e = env(db).await;
    // Two units at the main location, one at another.
    let other: String = {
        let (status, l) = post(
            &e.app,
            ADMIN,
            "/inventory/locations",
            json!({ "warehouse_id": e.wh, "code": "B2" }),
        )
        .await;
        assert_eq!(status, StatusCode::CREATED, "{l}");
        id(&l)
    };
    e.receive(json!({ "product_id": PUMP, "quantity": "1", "serial_number": "P-A" }))
        .await;
    e.receive(json!({ "product_id": PUMP, "quantity": "1", "serial_number": "P-B" }))
        .await;
    let (status, m) = post(
        &e.app,
        STORES,
        "/inventory/receipts",
        json!({ "id": uid(), "product_id": PUMP, "location_id": other, "quantity": "1", "serial_number": "P-C" }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{m}");
    let (order, line) = e.order(PUMP, "1").await;
    e.confirm(&order).await;
    e.reserve(&line, "1").await;
    let (_, note) = e.plan(&order, json!({})).await;
    let n = id(&note);
    let l = id(&note["lines"][0]);
    let uri = format!("/deliveries/{n}/lines/{l}/serial-units");

    // Logistics may choose without being allowed to read serial numbers in general.
    let (status, units) = get(&e.app, LOGISTICS, &uri).await;
    assert_eq!(status, StatusCode::OK, "{units}");
    let numbers: Vec<&str> = units
        .as_array()
        .unwrap()
        .iter()
        .map(|u| u["serial_number"].as_str().unwrap())
        .collect();
    let here = note["lines"][0]["location_id"].as_str().unwrap();
    if here == e.main {
        assert_eq!(numbers, ["P-A", "P-B"]);
    } else {
        assert_eq!(numbers, ["P-C"]);
    }
    let (_, found) = get(&e.app, LOGISTICS, &format!("{uri}?q=-B")).await;
    assert!(found.as_array().unwrap().len() <= 1);
    let (status, _) = get(&e.app, VIEWER, &uri).await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, _) = get(
        &e.app,
        LOGISTICS,
        &format!("/deliveries/{n}/lines/{}/serial-units", uid()),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_shipped_note_keeps_the_product_as_it_was_shipped(db: PgPool) {
    let e = env(db).await;
    let (order, _) = e.reserved_order(FRAME, "10", "2").await;
    let (_, note) = e.plan(&order, json!({})).await;
    let n = id(&note);
    let before = note["lines"][0]["product_name"]
        .as_str()
        .unwrap()
        .to_string();
    let (status, _) = e.ship(&n, json!({})).await;
    assert_eq!(status, StatusCode::OK);
    sqlx::query("UPDATE products.products SET name = 'Renamed later' WHERE id = $1::uuid")
        .bind(FRAME)
        .execute(&e.db)
        .await
        .unwrap();
    let (_, shipped) = get(&e.app, VIEWER, &format!("/deliveries/{n}")).await;
    assert_eq!(shipped["lines"][0]["product_name"], before.as_str());
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn customer_billing_posts_a_shipment_once_and_credits_its_frozen_eligibility(db: PgPool) {
    let e = test_env(db).await;
    let (order, _) = e.reserved_order(FRAME, "3", "3").await;
    let (status, note) = e.plan(&order, json!({})).await;
    assert_eq!(status, StatusCode::CREATED, "{note}");
    let (status, shipped) = e.ship(&id(&note), json!({})).await;
    assert_eq!(status, StatusCode::OK, "{shipped}");

    sqlx::query("UPDATE products.products SET included_in_turnover = NULL WHERE id = $1::uuid")
        .bind(FRAME)
        .execute(&e.db)
        .await
        .unwrap();
    let today = chrono::Utc::now().date_naive();
    let request = json!({
        "request_id": uid(),
        "delivery_note_id": id(&shipped),
        "document_date": today,
        "lines": [{ "delivery_line_id": id(&shipped["lines"][0]), "quantity": "2" }]
    });
    let (status, draft) = post(&e.app, ADMIN, "/customer-invoices", request.clone()).await;
    assert_eq!(status, StatusCode::OK, "{draft}");
    assert_eq!(draft["document"]["status"], "draft");
    assert!(draft["document"]["number"].is_null());
    let (status, replay) = post(&e.app, ADMIN, "/customer-invoices", request.clone()).await;
    assert_eq!(status, StatusCode::OK, "{replay}");
    assert_eq!(replay["document"]["id"], draft["document"]["id"]);
    let mut changed = request.clone();
    changed["lines"][0]["quantity"] = json!("1");
    let (status, result) = post(&e.app, ADMIN, "/customer-invoices", changed).await;
    assert_eq!(status, StatusCode::CONFLICT, "{result}");
    let draft_post = format!("/customer-invoices/{}/post", id(&draft["document"]));
    let (status, response) = post(&e.app, ADMIN, &draft_post, json!({})).await;
    assert_eq!(status, StatusCode::CONFLICT, "{response}");
    assert_eq!(response["code"], "turnover_eligibility_unknown");

    sqlx::query("UPDATE products.products SET included_in_turnover = true WHERE id = $1::uuid")
        .bind(FRAME)
        .execute(&e.db)
        .await
        .unwrap();
    let mut competing_request = request.clone();
    competing_request["request_id"] = json!(uid());
    let (status, competing_draft) =
        post(&e.app, ADMIN, "/customer-invoices", competing_request).await;
    assert_eq!(status, StatusCode::OK, "{competing_draft}");
    let competing_post = format!(
        "/customer-invoices/{}/post",
        id(&competing_draft["document"])
    );
    let (first, second) = tokio::join!(
        post(&e.app, ADMIN, &draft_post, json!({})),
        post(&e.app, ADMIN, &competing_post, json!({}))
    );
    let (posted, posted_path, failed) = if first.0 == StatusCode::OK {
        (first.1, draft_post, second)
    } else {
        assert_eq!(second.0, StatusCode::OK, "{first:?} {second:?}");
        (second.1, competing_post, first)
    };
    assert_eq!(failed.0, StatusCode::CONFLICT, "{failed:?}");
    assert_eq!(posted["document"]["status"], "posted");
    assert_eq!(posted["lines"][0]["included_in_turnover"], true);
    let number = posted["document"]["number"].as_str().unwrap();
    assert!(number.ends_with("-000001"), "{number}");
    let (status, replay) = post(&e.app, ADMIN, &posted_path, json!({})).await;
    assert_eq!(status, StatusCode::OK, "{replay}");
    assert_eq!(replay["document"]["number"], number);

    let mut remainder_request = request;
    remainder_request["request_id"] = json!(uid());
    remainder_request["lines"][0]["quantity"] = json!("1");
    let (status, remainder_draft) =
        post(&e.app, ADMIN, "/customer-invoices", remainder_request).await;
    assert_eq!(status, StatusCode::OK, "{remainder_draft}");
    let (status, remainder) = post(
        &e.app,
        ADMIN,
        &format!(
            "/customer-invoices/{}/post",
            id(&remainder_draft["document"])
        ),
        json!({}),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{remainder}");
    assert_eq!(dec(&remainder["lines"][0]["quantity"]), q("1"));
    let (status, order) = get(&e.app, ADMIN, &format!("/orders/{order}")).await;
    assert_eq!(status, StatusCode::OK, "{order}");
    assert_eq!(
        dec(&posted["document"]["net_total"]) + dec(&remainder["document"]["net_total"]),
        dec(&order["order"]["subtotal"])
    );

    sqlx::query("UPDATE products.products SET included_in_turnover = false WHERE id = $1::uuid")
        .bind(FRAME)
        .execute(&e.db)
        .await
        .unwrap();
    let credit_request = json!({
        "invoice_id": id(&posted["document"]),
        "document_date": today,
        "reason": "One returned item",
        "lines": [{ "invoice_line_id": id(&posted["lines"][0]), "quantity": "1" }]
    });
    let (status, credit) = post(&e.app, ADMIN, "/customer-invoices/credits", credit_request).await;
    assert_eq!(status, StatusCode::OK, "{credit}");
    let (status, credit) = post(
        &e.app,
        ADMIN,
        &format!("/customer-invoices/{}/post", id(&credit["document"])),
        json!({}),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{credit}");
    assert_eq!(credit["document"]["source_invoice_number"], number);
    assert_eq!(credit["lines"][0]["included_in_turnover"], true);
    assert!(
        (dec(&credit["document"]["net_total"]) * q("2") - dec(&posted["document"]["net_total"]))
            .abs()
            <= q("0.01")
    );

    let (status, invoice) = get(
        &e.app,
        ADMIN,
        &format!("/customer-invoices/{}", id(&posted["document"])),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{invoice}");
    assert_eq!(dec(&invoice["lines"][0]["creditable_quantity"]), q("1"));
    assert_eq!(
        dec(&invoice["lines"][0]["creditable_net_total"]),
        dec(&posted["document"]["net_total"]) - dec(&credit["document"]["net_total"])
    );

    let (status, overcredit) = post(
        &e.app,
        ADMIN,
        "/customer-invoices/credits",
        json!({
            "invoice_id": id(&posted["document"]),
            "document_date": today,
            "reason": "More than the remaining quantity",
            "lines": [{ "invoice_line_id": id(&posted["lines"][0]), "quantity": "2" }]
        }),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT, "{overcredit}");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn posted_invoices_snapshot_localized_rebate_progress_and_net_posted_credits(db: PgPool) {
    use chrono::Datelike;

    let e = test_env(db).await;
    let today = tradocraft_core::today();
    let rate_year = today.year() + 1;
    let customer_rebates = format!("/customer-rebates/customers/{ALPHA}");
    let (status, settings) = put(
        &e.app,
        ADMIN,
        "/customer-rebates/settings",
        json!({
            "show_on_invoices": true,
            "wording": [{
                "language": "nl",
                "active": "Meetellende aankopen {eligible_sales}. Nog {amount_to_next_tier} tot {next_threshold} voor {next_rate} in {rate_year}.",
                "highest": "Hoogste niveau bereikt voor {rate_year}."
            }]
        }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{settings}");
    let (status, schedule) = post(
        &e.app,
        ADMIN,
        "/customer-rebates/schedules",
        json!({
            "name": "Annual sales",
            "effective_year": rate_year,
            "tiers": [{ "threshold": "100000", "rate": "4" }]
        }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{schedule}");
    let (status, assignment) = put(
        &e.app,
        ADMIN,
        &format!("{customer_rebates}/assignment"),
        json!({ "schedule_name": "Annual sales" }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{assignment}");
    let (status, opening) = put(
        &e.app,
        ADMIN,
        &format!("{customer_rebates}/history"),
        json!({
            "year": today.year(),
            "cutoff": chrono::NaiveDate::from_ymd_opt(today.year() - 1, 12, 31).unwrap(),
            "eligible_sales": "0"
        }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{opening}");
    sqlx::query("UPDATE products.products SET included_in_turnover = true WHERE id = $1::uuid")
        .bind(FRAME)
        .execute(&e.db)
        .await
        .unwrap();

    let (order, _) = e.reserved_order(FRAME, "2", "2").await;
    let (status, note) = e.plan(&order, json!({})).await;
    assert_eq!(status, StatusCode::CREATED, "{note}");
    let (status, shipped) = e.ship(&id(&note), json!({})).await;
    assert_eq!(status, StatusCode::OK, "{shipped}");
    let invoice_half = || async {
        let (status, draft) = post(
            &e.app,
            ADMIN,
            "/customer-invoices",
            json!({
                "request_id": uid(),
                "delivery_note_id": id(&shipped),
                "document_date": today,
                "lines": [{ "delivery_line_id": id(&shipped["lines"][0]), "quantity": "1" }]
            }),
        )
        .await;
        assert_eq!(status, StatusCode::OK, "{draft}");
        let (status, posted) = post(
            &e.app,
            ADMIN,
            &format!("/customer-invoices/{}/post", id(&draft["document"])),
            json!({}),
        )
        .await;
        assert_eq!(status, StatusCode::OK, "{posted}");
        posted
    };
    let first = invoice_half().await;
    let first_progress = &first["rebate_progress"];
    let net = dec(&first["document"]["net_total"]);
    assert_eq!(dec(&first_progress["eligible_sales"]), net);
    assert_eq!(dec(&first_progress["next_threshold"]), q("100000"));
    assert_eq!(
        dec(&first_progress["amount_to_next_tier"]),
        q("100000") - net
    );
    assert_eq!(dec(&first_progress["next_rate"]), q("4"));
    assert_eq!(first_progress["rate_year"], rate_year);
    let message = first_progress["message"].as_str().unwrap();
    assert!(message.starts_with("Meetellende aankopen"), "{message}");
    assert!(message.contains("100.000,00 EUR"), "{message}");
    assert!(!message.contains('{'), "{message}");

    let (status, credit) = post(
        &e.app,
        ADMIN,
        "/customer-invoices/credits",
        json!({
            "invoice_id": id(&first["document"]),
            "document_date": today,
            "reason": "Returned item",
            "lines": [{ "invoice_line_id": id(&first["lines"][0]), "quantity": "1" }]
        }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{credit}");
    let (status, credited) = post(
        &e.app,
        ADMIN,
        &format!("/customer-invoices/{}/post", id(&credit["document"])),
        json!({}),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{credited}");
    assert!(credited["rebate_progress"].is_null());

    let second = invoice_half().await;
    assert_eq!(dec(&second["rebate_progress"]["eligible_sales"]), net);
    let (status, settings) = put(
        &e.app,
        ADMIN,
        "/customer-rebates/settings",
        json!({ "show_on_invoices": false, "wording": [] }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{settings}");
    let (status, read_back) = get(
        &e.app,
        ADMIN,
        &format!("/customer-invoices/{}", id(&first["document"])),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{read_back}");
    assert_eq!(&read_back["rebate_progress"], first_progress);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn customer_billing_registered_legacy_credits_respect_the_opening_cutoff(db: PgPool) {
    let app = common::setup_test_environment(db.clone()).await;
    let today = chrono::Utc::now().date_naive();
    let closed =
        chrono::NaiveDate::from_ymd_opt(chrono::Datelike::year(&today) - 1, 12, 31).unwrap();
    let legacy = json!({
        "customer_id": ALPHA,
        "number": "EXT-741",
        "document_date": closed,
        "currency": "EUR",
        "vat_regime": "domestic",
        "evidence_reference": "Accounting archive EXT-741 verified",
        "lines": [{
            "product_code": "FRAME",
            "description": "Frame assembly",
            "unit": "pcs",
            "quantity": "3",
            "net_total": "150.00",
            "vat_total": "31.50",
            "vat_rate": "21",
            "included_in_turnover": true
        }]
    });
    let (status, origin) = post(&app, ADMIN, "/customer-invoices/legacy", legacy.clone()).await;
    assert_eq!(status, StatusCode::OK, "{origin}");
    assert_eq!(origin["document"]["number"], "EXT-741");
    assert_eq!(origin["document"]["is_legacy"], true);
    assert_eq!(origin["document"]["status"], "posted");
    let (status, duplicate) = post(&app, ADMIN, "/customer-invoices/legacy", legacy).await;
    assert_eq!(status, StatusCode::CONFLICT, "{duplicate}");

    sqlx::query(
        "INSERT INTO finance.customer_rebate_openings
             (company_id, customer_id, year, cutoff, eligible_sales, verified_by)
         SELECT $1::uuid, $2::uuid, $3, $4, 150, id FROM core.users WHERE email = $5",
    )
    .bind(COMPANY)
    .bind(ALPHA)
    .bind(chrono::Datelike::year(&closed))
    .bind(closed)
    .bind(ADMIN)
    .execute(&db)
    .await
    .unwrap();

    let mut request = json!({
        "invoice_id": id(&origin["document"]),
        "document_date": closed,
        "reason": "Returned frame",
        "lines": [{ "invoice_line_id": id(&origin["lines"][0]), "quantity": "1" }]
    });
    let (status, draft) = post(&app, ADMIN, "/customer-invoices/credits", request.clone()).await;
    assert_eq!(status, StatusCode::OK, "{draft}");
    let post_path = format!("/customer-invoices/{}/post", id(&draft["document"]));
    let (status, rejected) = post(&app, ADMIN, &post_path, json!({})).await;
    assert_eq!(status, StatusCode::CONFLICT, "{rejected}");
    assert_eq!(rejected["code"], "turnover_period_closed");

    request["document_date"] = json!(today);
    let (status, draft) = post(&app, ADMIN, "/customer-invoices/credits", request).await;
    assert_eq!(status, StatusCode::OK, "{draft}");
    let post_path = format!("/customer-invoices/{}/post", id(&draft["document"]));
    let (status, credit) = post(&app, ADMIN, &post_path, json!({})).await;
    assert_eq!(status, StatusCode::OK, "{credit}");
    assert_eq!(credit["document"]["source_invoice_number"], "EXT-741");
    assert_eq!(credit["lines"][0]["included_in_turnover"], true);
    assert_eq!(dec(&credit["document"]["net_total"]), q("50"));
    assert_eq!(dec(&credit["document"]["vat_total"]), q("10.50"));
    assert_eq!(credit["document"]["document_date"], json!(today));
}
