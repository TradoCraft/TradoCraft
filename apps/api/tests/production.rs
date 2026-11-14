//! Production (ADR 0036): releasing orders to production, the frozen BOM and its reservations,
//! completion with backflush, output and genealogy, the order status that follows, divisions and rights.

mod common;

use axum::http::{Method, StatusCode};
use common::{call, dec, setup};
use rust_decimal::Decimal;
use serde_json::{json, Value};
use sqlx::PgPool;
use uuid::Uuid;

const ADMIN: &str = "admin@example.com";
const SALES: &str = "sales@example.com";
const MANAGER: &str = "manager@example.com"; // sales_manager
const VIEWER: &str = "viewer@example.com";
const SUPPORT: &str = "support@example.com";
const LOGISTICS: &str = "logistics@example.com";
const PLANNER: &str = "planner@example.com"; // role production
const STORES: &str = "stores@example.com"; // role warehouse
const COMPANY: &str = "00000000-0000-7000-8000-000000000001";
const ALPHA: &str = "00000000-0000-7000-8000-000000000401";
const FRAME: &str = "00000000-0000-7000-8000-000000000307"; // built: 6.5 m profile (10 % scrap) + 24 bolts (2 %)
const PROFILE: &str = "00000000-0000-7000-8000-000000000308"; // metres
const BOLT: &str = "00000000-0000-7000-8000-000000000309";
const UNIT_100: &str = "00000000-0000-7000-8000-000000000301"; // serial; frame, 2 pumps, controller, 8 bolts
const PUMP: &str = "00000000-0000-7000-8000-000000000303"; // serial
const CTRL: &str = "00000000-0000-7000-8000-000000000310"; // serial

fn uid() -> String {
    Uuid::now_v7().to_string()
}

fn q(s: &str) -> Decimal {
    s.parse().unwrap()
}

fn id(v: &Value) -> String {
    v["id"].as_str().unwrap().to_string()
}

async fn add_user(db: &PgPool, email: &str, role: &str) {
    let uid = Uuid::now_v7();
    sqlx::query("INSERT INTO core.users (id, email, display_name) VALUES ($1, $2, $3)")
        .bind(uid)
        .bind(email)
        .bind(email)
        .execute(db)
        .await
        .unwrap();
    sqlx::query("INSERT INTO core.user_companies (user_id, company_id, roles, is_default) VALUES ($1, $2::uuid, $3, true)")
        .bind(uid)
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
    main: String,
}

async fn env(db: PgPool) -> Env {
    let app = setup(db.clone()).await;
    add_user(&db, STORES, "warehouse").await;
    add_user(&db, PLANNER, "production").await;
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

    /// Stock for two frames: 14.3 m of profile and 48.96 bolts are needed, so this is plenty.
    async fn frame_parts(&self) {
        self.stock(PROFILE, "20").await;
        self.stock(BOLT, "100").await;
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
        let order = id(&o["order"]);
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
        (order, o["lines"][0]["id"].as_str().unwrap().into())
    }

    async fn release(&self, order: &str, line: &str, body: Value) -> (StatusCode, Value) {
        let mut b = body;
        b["order_id"] = json!(order);
        b["order_line_id"] = json!(line);
        post(&self.app, PLANNER, "/production-orders", b).await
    }

    async fn build_for_stock(&self, product: &str, quantity: &str) -> Value {
        let (status, po) = post(
            &self.app,
            PLANNER,
            "/production-orders",
            json!({ "product_id": product, "quantity": quantity }),
        )
        .await;
        assert_eq!(status, StatusCode::CREATED, "{po}");
        po
    }

    async fn complete(&self, po: &str, body: Value) -> (StatusCode, Value) {
        post(
            &self.app,
            STORES,
            &format!("/production-orders/{po}/complete"),
            body,
        )
        .await
    }

    async fn order_status(&self, order: &str) -> String {
        sqlx::query_scalar("SELECT status FROM sales.orders WHERE id = $1::uuid")
            .bind(order)
            .fetch_one(&self.db)
            .await
            .unwrap()
    }

    async fn promised(&self, order: &str) -> Option<String> {
        sqlx::query_scalar("SELECT promised_date::text FROM sales.orders WHERE id = $1::uuid")
            .bind(order)
            .fetch_one(&self.db)
            .await
            .unwrap()
    }

    /// (on hand, reserved) of a product in the warehouses.
    async fn stock_of(&self, product: &str) -> (Decimal, Decimal) {
        let (status, p) = get(
            &self.app,
            ADMIN,
            &format!("/inventory/stock/products?product_id={product}"),
        )
        .await;
        assert_eq!(status, StatusCode::OK, "{p}");
        match p["items"].as_array().unwrap().first() {
            Some(i) => (dec(&i["on_hand"]), dec(&i["reserved"])),
            None => (Decimal::ZERO, Decimal::ZERO),
        }
    }

    async fn integrity_ok(&self) {
        let (status, i) = get(&self.app, ADMIN, "/inventory/integrity").await;
        assert_eq!(status, StatusCode::OK, "{i}");
        assert_eq!(i["ok"], true, "{i}");
    }
}

fn component<'a>(po: &'a Value, code: &str) -> &'a Value {
    po["components"]
        .as_array()
        .unwrap()
        .iter()
        .find(|c| c["component_code"] == code)
        .unwrap_or_else(|| panic!("no component {code} in {po}"))
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn releasing_freezes_the_bom_and_reserves_the_components(db: PgPool) {
    let e = env(db).await;
    e.frame_parts().await;
    let (order, line) = e.order(FRAME, "2").await;

    // The planner sees the line as something to release.
    let (status, todo) = get(&e.app, PLANNER, "/production/to-release").await;
    assert_eq!(status, StatusCode::OK, "{todo}");
    let item = todo
        .as_array()
        .unwrap()
        .iter()
        .find(|t| t["order_line_id"] == line.as_str())
        .unwrap();
    assert_eq!(dec(&item["to_build"]), q("2"));

    let (status, po) = e.release(&order, &line, json!({})).await;
    assert_eq!(status, StatusCode::CREATED, "{po}");
    assert!(po["number"].as_str().unwrap().starts_with("MO"), "{po}");
    assert_eq!(po["status"], "released");
    assert_eq!(po["bom_revision"], 1);
    assert_eq!(dec(&po["quantity"]), q("2"));
    // 6.5 m + 10 % per frame, 24 bolts + 2 %: required is rounded up, and fully reserved.
    let profile = component(&po, "PROFILE-40");
    assert_eq!(dec(&profile["required_quantity"]), q("14.3"));
    assert_eq!(dec(&profile["reserved_quantity"]), q("14.3"));
    assert_eq!(component(&po, "BOLT-M8")["required_quantity"], "48.9600");
    assert_eq!(po["short_components"], 0);
    assert_eq!(e.stock_of(PROFILE).await, (q("20"), q("14.3")));
    assert_eq!(e.order_status(&order).await, "in_planning");

    // What is released no longer shows as to do, and the BOM as it was stays on the order.
    let (_, todo) = get(&e.app, PLANNER, "/production/to-release").await;
    assert!(todo
        .as_array()
        .unwrap()
        .iter()
        .all(|t| t["order_line_id"] != line.as_str()));
    sqlx::query(
        "UPDATE engineering.bom_lines SET quantity = 100 WHERE component_product_id = $1::uuid",
    )
    .bind(PROFILE)
    .execute(&e.db)
    .await
    .unwrap();
    let (_, again) = get(&e.app, PLANNER, &format!("/production-orders/{}", id(&po))).await;
    assert_eq!(
        dec(&component(&again, "PROFILE-40")["required_quantity"]),
        q("14.3")
    );

    // The line is covered: a second release is refused unless a quantity is given.
    let (status, r) = e.release(&order, &line, json!({})).await;
    assert_eq!(status, StatusCode::CONFLICT, "{r}");
    e.integrity_ok().await;
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_short_component_is_flagged_and_reserved_when_stock_arrives(db: PgPool) {
    let e = env(db).await;
    e.stock(PROFILE, "20").await;
    e.stock(BOLT, "10").await; // 48.96 are needed
    let (order, line) = e.order(FRAME, "2").await;
    let (status, po) = e.release(&order, &line, json!({})).await;
    assert_eq!(status, StatusCode::CREATED, "{po}");
    assert_eq!(po["short_components"], 1);
    let bolt = component(&po, "BOLT-M8");
    assert_eq!(bolt["short"], true);
    assert_eq!(dec(&bolt["reserved_quantity"]), q("0"));
    assert_eq!(component(&po, "PROFILE-40")["short"], false);
    let n = id(&po);

    e.stock(BOLT, "100").await;
    let (status, ok) = post(
        &e.app,
        PLANNER,
        &format!("/production-orders/{n}/reserve"),
        json!({}),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{ok}");
    assert_eq!(ok["short_components"], 0);
    assert_eq!(
        dec(&component(&ok, "BOLT-M8")["reserved_quantity"]),
        q("48.96")
    );
    e.integrity_ok().await;
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_order_follows_its_production_orders_and_is_promised_a_date(db: PgPool) {
    let e = env(db).await;
    e.frame_parts().await;
    let (order, line) = e.order(FRAME, "2").await;
    let (_, po) = e.release(&order, &line, json!({})).await;
    let n = id(&po);
    assert_eq!(e.order_status(&order).await, "in_planning");
    assert_eq!(e.promised(&order).await, None);

    // A planned-ready date makes the order planned and sets its promised date.
    let (status, p) = put(
        &e.app,
        PLANNER,
        &format!("/production-orders/{n}"),
        json!({ "planned_ready_date": "2099-07-01", "notes": "after the holidays" }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{p}");
    assert_eq!(p["planned_ready_date"], "2099-07-01");
    assert_eq!(e.order_status(&order).await, "planned");
    assert_eq!(e.promised(&order).await.as_deref(), Some("2099-07-01"));
    let (_, ord) = get(&e.app, SALES, &format!("/orders/{order}")).await;
    assert_eq!(ord["order"]["promised_date"], "2099-07-01");

    // Starting makes it in production, and a sales order in production can no longer be cancelled.
    let (status, s) = post(
        &e.app,
        STORES,
        &format!("/production-orders/{n}/start"),
        json!({}),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{s}");
    assert_eq!(s["status"], "in_progress");
    assert_eq!(e.order_status(&order).await, "in_production");
    let (status, _) = post(
        &e.app,
        SALES,
        &format!("/orders/{order}/cancel"),
        json!({ "reason": "x" }),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
    let (status, _) = post(
        &e.app,
        STORES,
        &format!("/production-orders/{n}/start"),
        json!({}),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT, "only a released order starts");

    // A second production order without a date does not take the order back: it never moves backwards.
    let (_, other) = e.release(&order, &line, json!({ "quantity": "1" })).await;
    assert_eq!(other["status"], "released");
    assert_eq!(e.order_status(&order).await, "in_production");

    // Completing all of them makes the order ready for shipping.
    let (status, done) = e
        .complete(
            &n,
            json!({ "output": { "quantity": "2", "location_id": e.main } }),
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{done}");
    assert_eq!(done["status"], "completed");
    assert_eq!(
        e.order_status(&order).await,
        "in_production",
        "one is still open"
    );
    let (status, _) = post(
        &e.app,
        PLANNER,
        &format!("/production-orders/{}/cancel", id(&other)),
        json!({ "reason": "not needed" }),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(e.order_status(&order).await, "ready_for_shipping");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn completion_consumes_the_reservation_and_puts_the_output_into_stock(db: PgPool) {
    let e = env(db).await;
    e.frame_parts().await;
    let (order, line) = e.order(FRAME, "2").await;
    let (_, po) = e.release(&order, &line, json!({})).await;
    let n = id(&po);

    let (status, done) = e
        .complete(
            &n,
            json!({ "output": { "quantity": "2", "location_id": e.main }, "note": "first batch" }),
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{done}");
    assert_eq!(done["status"], "completed");
    assert_eq!(dec(&done["completed_quantity"]), q("2"));
    assert_eq!(done["notes"], "first batch");
    assert_eq!(done["outputs"].as_array().unwrap().len(), 1);
    assert_eq!(
        dec(&component(&done, "PROFILE-40")["consumed_quantity"]),
        q("14.3")
    );
    assert_eq!(e.stock_of(FRAME).await.0, q("2"));
    assert_eq!(e.stock_of(PROFILE).await, (q("5.7"), q("0")));
    assert_eq!(e.stock_of(BOLT).await, (q("51.04"), q("0")));
    assert_eq!(e.order_status(&order).await, "ready_for_shipping");
    e.integrity_ok().await;

    // A finished order cannot be completed, changed or cancelled again.
    let (status, _) = e
        .complete(
            &n,
            json!({ "output": { "quantity": "1", "location_id": e.main } }),
        )
        .await;
    assert_eq!(status, StatusCode::CONFLICT);
    let (status, _) = put(
        &e.app,
        PLANNER,
        &format!("/production-orders/{n}"),
        json!({}),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
    let (status, _) = post(
        &e.app,
        PLANNER,
        &format!("/production-orders/{n}/cancel"),
        json!({ "reason": "x" }),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn actual_consumption_scrap_and_extra_stock_are_booked(db: PgPool) {
    let e = env(db).await;
    e.frame_parts().await;
    let po = e.build_for_stock(FRAME, "1").await; // reserves 7.15 m and 24.48 bolts
    let n = id(&po);
    let profile = id(component(&po, "PROFILE-40"));
    assert_eq!(po["order_id"], Value::Null);

    // More was used than reserved: the planner must say where the extra comes from.
    let plan = json!({ "output": { "quantity": "1", "location_id": e.main },
        "components": [{ "component_id": profile, "consumed_quantity": "8", "scrap_quantity": "1" }] });
    let (status, r) = e.complete(&n, plan).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{r}");
    assert_eq!(
        e.stock_of(PROFILE).await,
        (q("20"), q("7.15")),
        "nothing was booked"
    );

    let plan = json!({ "output": { "quantity": "1", "location_id": e.main },
        "components": [{ "component_id": profile, "consumed_quantity": "8", "scrap_quantity": "1",
                         "extra_location_id": e.main }] });
    let (status, done) = e.complete(&n, plan).await;
    assert_eq!(status, StatusCode::OK, "{done}");
    let c = component(&done, "PROFILE-40");
    assert_eq!(
        (dec(&c["consumed_quantity"]), dec(&c["scrap_quantity"])),
        (q("8"), q("1"))
    );
    // 20 - 8 consumed - 1 scrapped; the bolts follow the BOM.
    assert_eq!(e.stock_of(PROFILE).await, (q("11"), q("0")));
    assert_eq!(e.stock_of(BOLT).await, (q("75.52"), q("0")));
    assert_eq!(e.stock_of(FRAME).await.0, q("1"));
    e.integrity_ok().await;
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn lot_output_needs_a_lot_and_a_short_run_closes_the_order(db: PgPool) {
    let e = env(db).await;
    e.frame_parts().await;
    sqlx::query("UPDATE products.products SET tracking = 'lot' WHERE id = $1::uuid")
        .bind(FRAME)
        .execute(&e.db)
        .await
        .unwrap();
    e.stock(PROFILE, "20").await; // four frames need 28.6 m
    let po = e.build_for_stock(FRAME, "4").await;
    let n = id(&po);
    let (status, r) = e
        .complete(
            &n,
            json!({ "output": { "quantity": "3", "location_id": e.main } }),
        )
        .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{r}");
    let (status, done) = e
        .complete(
            &n,
            json!({ "output": { "quantity": "3", "location_id": e.main, "lot_number": "F-001", "expiry_date": "2099-01-01" } }),
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{done}");
    // Three of four were built: the order is closed with the shortfall visible.
    assert_eq!(dec(&done["completed_quantity"]), q("3"));
    assert_eq!(dec(&done["quantity"]), q("4"));
    assert_eq!(done["outputs"][0]["lot_number"], "F-001");
    assert_eq!(e.stock_of(FRAME).await.0, q("3"));
    e.integrity_ok().await;
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn serial_output_records_the_as_built_components(db: PgPool) {
    let e = env(db).await;
    // A frame, two pumps, a controller and eight bolts make a unit.
    e.stock(FRAME, "1").await;
    e.stock(BOLT, "8").await;
    let mut pumps = Vec::new();
    for s in ["P-X1", "P-X2"] {
        let m = e
            .receive(json!({ "product_id": PUMP, "quantity": "1", "serial_number": s }))
            .await;
        pumps.push(m["serial_unit_id"].as_str().unwrap().to_string());
    }
    let m = e
        .receive(json!({ "product_id": CTRL, "quantity": "1", "serial_number": "C-X1" }))
        .await;
    let ctrl = m["serial_unit_id"].as_str().unwrap().to_string();

    let po = e.build_for_stock(UNIT_100, "1").await;
    let n = id(&po);
    let pump_c = id(component(&po, "PUMP-05"));
    let ctrl_c = id(component(&po, "CTRL-01"));
    assert_eq!(po["short_components"], 0, "{po}");

    // Serial numbers for the output and the units built in are needed.
    let bare = json!({ "output": { "quantity": "1", "location_id": e.main } });
    assert_eq!(
        e.complete(&n, bare).await.0,
        StatusCode::UNPROCESSABLE_ENTITY
    );
    let one_pump = json!({ "output": { "quantity": "1", "location_id": e.main, "serial_numbers": ["U-NEW-1"] },
        "components": [{ "component_id": pump_c, "serial_unit_ids": [pumps[0]] },
                       { "component_id": ctrl_c, "serial_unit_ids": [ctrl] }] });
    assert_eq!(
        e.complete(&n, one_pump).await.0,
        StatusCode::UNPROCESSABLE_ENTITY
    );

    // The candidates are the units in stock.
    let (status, cands) = get(
        &e.app,
        STORES,
        &format!("/production-orders/{n}/components/{pump_c}/serial-units"),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{cands}");
    assert_eq!(cands.as_array().unwrap().len(), 2);

    let full = json!({ "output": { "quantity": "1", "location_id": e.main, "serial_numbers": ["U-NEW-1"] },
        "components": [{ "component_id": pump_c, "serial_unit_ids": pumps },
                       { "component_id": ctrl_c, "serial_unit_ids": [ctrl] }] });
    let (status, done) = e.complete(&n, full).await;
    assert_eq!(status, StatusCode::OK, "{done}");
    let unit = done["outputs"][0]["serial_number"].as_str().unwrap();
    assert_eq!(unit, "U-NEW-1");

    // The new unit is in stock, as built to the frozen BOM, with its components attached.
    let (_, list) = get(&e.app, ADMIN, "/serials?q=U-NEW-1").await;
    let unit_id = id(&list["items"][0]);
    let (_, detail) = get(&e.app, ADMIN, &format!("/serials/{unit_id}")).await;
    assert_eq!(detail["unit"]["status"], "in_stock");
    assert_eq!(detail["unit"]["bom_revision"], 1);
    let attached: Vec<&str> = detail["components"]
        .as_array()
        .unwrap()
        .iter()
        .map(|c| c["serial_number"].as_str().unwrap())
        .collect();
    assert_eq!(attached.len(), 3, "{detail}");
    for s in ["P-X1", "P-X2", "C-X1"] {
        assert!(attached.contains(&s), "{s} in {detail}");
    }
    let (_, pump) = get(&e.app, ADMIN, &format!("/serials/{}", pumps[0])).await;
    assert_eq!(pump["unit"]["status"], "built_in");
    assert_eq!(e.stock_of(UNIT_100).await.0, q("1"));
    e.integrity_ok().await;
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn cancelling_releases_the_reservations(db: PgPool) {
    let e = env(db).await;
    e.frame_parts().await;
    let (order, line) = e.order(FRAME, "2").await;
    let (_, po) = e.release(&order, &line, json!({})).await;
    let n = id(&po);
    assert_eq!(e.stock_of(PROFILE).await, (q("20"), q("14.3")));

    let (status, _) = post(
        &e.app,
        PLANNER,
        &format!("/production-orders/{n}/cancel"),
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
        PLANNER,
        &format!("/production-orders/{n}/cancel"),
        json!({ "reason": "customer changed the order" }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{c}");
    assert_eq!(c["status"], "cancelled");
    assert_eq!(e.stock_of(PROFILE).await, (q("20"), q("0")));
    for uri in [
        format!("/production-orders/{n}/start"),
        format!("/production-orders/{n}/reserve"),
    ] {
        let (status, _) = post(&e.app, ADMIN, &uri, json!({})).await;
        assert_eq!(status, StatusCode::CONFLICT, "{uri}");
    }
    let (status, _) = e
        .complete(
            &n,
            json!({ "output": { "quantity": "1", "location_id": e.main } }),
        )
        .await;
    assert_eq!(status, StatusCode::CONFLICT);
    // The line is open again: it can be released once more.
    let (status, again) = e.release(&order, &line, json!({})).await;
    assert_eq!(status, StatusCode::CREATED, "{again}");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn an_order_in_production_can_be_cancelled_once_no_production_order_is_open(db: PgPool) {
    let e = env(db).await;
    e.frame_parts().await;
    let (order, line) = e.order(FRAME, "2").await;
    let (_, po) = e.release(&order, &line, json!({})).await;
    let n = id(&po);
    let (status, _) = post(
        &e.app,
        STORES,
        &format!("/production-orders/{n}/start"),
        json!({}),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(e.order_status(&order).await, "in_production");
    let cancel_uri = format!("/orders/{order}/cancel");
    let (status, _) = post(&e.app, SALES, &cancel_uri, json!({ "reason": "lost" })).await;
    assert_eq!(status, StatusCode::CONFLICT, "a production order is open");

    let (status, _) = post(
        &e.app,
        PLANNER,
        &format!("/production-orders/{n}/cancel"),
        json!({ "reason": "stopped" }),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    // The status never goes back, but nothing is open any more: the order is not stuck.
    assert_eq!(e.order_status(&order).await, "in_production");
    let (status, c) = post(&e.app, SALES, &cancel_uri, json!({ "reason": "lost" })).await;
    assert_eq!(status, StatusCode::OK, "{c}");
    assert_eq!(e.order_status(&order).await, "cancelled");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_cancelled_sales_order_is_flagged_on_its_production_order(db: PgPool) {
    let e = env(db).await;
    e.frame_parts().await;
    let (order, line) = e.order(FRAME, "2").await;
    let (_, po) = e.release(&order, &line, json!({})).await;
    let n = id(&po);
    let (status, _) = post(
        &e.app,
        SALES,
        &format!("/orders/{order}/cancel"),
        json!({ "reason": "lost" }),
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    let (_, flagged) = get(&e.app, PLANNER, &format!("/production-orders/{n}")).await;
    assert_eq!(flagged["order_cancelled"], true);
    assert_eq!(flagged["status"], "released");
    // It cannot be completed, only cancelled, which frees its components.
    let (status, r) = e
        .complete(
            &n,
            json!({ "output": { "quantity": "2", "location_id": e.main } }),
        )
        .await;
    assert_eq!(status, StatusCode::CONFLICT, "{r}");
    let (status, c) = post(
        &e.app,
        PLANNER,
        &format!("/production-orders/{n}/cancel"),
        json!({ "reason": "order cancelled" }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{c}");
    assert_eq!(e.order_status(&order).await, "cancelled");
    assert_eq!(e.stock_of(PROFILE).await, (q("20"), q("0")));
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_finished_order_is_delivered_through_the_delivery_module(db: PgPool) {
    let e = env(db).await;
    e.frame_parts().await;
    let (order, line) = e.order(FRAME, "2").await;
    let (_, po) = e.release(&order, &line, json!({})).await;
    let (status, done) = e
        .complete(
            &id(&po),
            json!({ "output": { "quantity": "2", "location_id": e.main } }),
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{done}");
    assert_eq!(e.order_status(&order).await, "ready_for_shipping");

    // The built frames are reserved for the order line, planned and shipped.
    let (status, r) = put(
        &e.app,
        STORES,
        &format!("/inventory/order-lines/{line}/reservation"),
        json!({ "quantity": "2" }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{r}");
    let (status, note) = post(
        &e.app,
        LOGISTICS,
        &format!("/orders/{order}/deliveries"),
        json!({}),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{note}");
    let (status, shipped) = post(
        &e.app,
        STORES,
        &format!("/deliveries/{}/ship", id(&note)),
        json!({}),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{shipped}");
    assert_eq!(e.order_status(&order).await, "shipped");
    assert_eq!(e.stock_of(FRAME).await, (q("0"), q("0")));
    e.integrity_ok().await;
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn divisions_are_kept_by_the_administrator_and_default_per_product(db: PgPool) {
    let e = env(db).await;
    e.frame_parts().await;
    // Only the administrator maintains divisions; planners read them.
    let d = json!({ "code": "WELD", "name": "Welding", "sort_order": 1 });
    for user in [PLANNER, SALES, MANAGER] {
        let (status, _) = post(&e.app, user, "/production/divisions", d.clone()).await;
        assert_eq!(status, StatusCode::FORBIDDEN, "{user}");
    }
    let (status, weld) = post(&e.app, ADMIN, "/production/divisions", d.clone()).await;
    assert_eq!(status, StatusCode::CREATED, "{weld}");
    let (status, _) = post(&e.app, ADMIN, "/production/divisions", d).await;
    assert_eq!(status, StatusCode::CONFLICT, "codes are unique");
    let (status, bad) = post(
        &e.app,
        ADMIN,
        "/production/divisions",
        json!({ "code": " ", "name": "x" }),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{bad}");
    let (_, asm) = post(
        &e.app,
        ADMIN,
        "/production/divisions",
        json!({ "code": "ASM", "name": "Assembly", "sort_order": 2 }),
    )
    .await;
    let (status, list) = get(&e.app, PLANNER, "/production/divisions").await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(list.as_array().unwrap().len(), 2);
    assert_eq!(list[0]["code"], "WELD");

    // A product has a default division; a production order starts there unless another is given.
    let (status, _) = put(
        &e.app,
        PLANNER,
        &format!("/production/products/{FRAME}/division"),
        json!({ "division_id": id(&weld) }),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, set) = put(
        &e.app,
        ADMIN,
        &format!("/production/products/{FRAME}/division"),
        json!({ "division_id": id(&weld) }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{set}");
    let (_, shown) = get(
        &e.app,
        PLANNER,
        &format!("/production/products/{FRAME}/division"),
    )
    .await;
    assert_eq!(shown["division_id"], id(&weld).as_str());
    let po = e.build_for_stock(FRAME, "1").await;
    assert_eq!(po["division_name"], "Welding");
    let (status, other) = post(
        &e.app,
        PLANNER,
        "/production-orders",
        json!({ "product_id": FRAME, "quantity": "1", "division_id": id(&asm) }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{other}");
    assert_eq!(other["division_name"], "Assembly");
    let (status, moved) = put(
        &e.app,
        PLANNER,
        &format!("/production-orders/{}", id(&other)),
        json!({ "division_id": id(&weld) }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{moved}");
    assert_eq!(moved["division_name"], "Welding");

    // The queue can be read per division; a used division is deactivated, not deleted.
    let (_, queue) = get(
        &e.app,
        VIEWER_OR(&e),
        &format!("/production-orders?division_id={}", id(&weld)),
    )
    .await;
    assert_eq!(queue["total"], 2);
    let (status, _) = api(
        &e.app,
        ADMIN,
        Method::DELETE,
        &format!("/production/divisions/{}", id(&weld)),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
    let (status, _) = api(
        &e.app,
        ADMIN,
        Method::DELETE,
        &format!("/production/divisions/{}", id(&asm)),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    let (status, off) = put(
        &e.app,
        ADMIN,
        &format!("/production/divisions/{}", id(&weld)),
        json!({ "code": "WELD", "name": "Welding", "active": false }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{off}");
    let (status, r) = post(
        &e.app,
        PLANNER,
        "/production-orders",
        json!({ "product_id": FRAME, "quantity": "1", "division_id": id(&weld) }),
    )
    .await;
    assert_eq!(
        status,
        StatusCode::UNPROCESSABLE_ENTITY,
        "an inactive division: {r}"
    );
}

#[allow(non_snake_case)]
fn VIEWER_OR(_: &Env) -> &'static str {
    VIEWER
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn rights_separate_reading_planning_and_running(db: PgPool) {
    let e = env(db).await;
    e.frame_parts().await;
    let (order, line) = e.order(FRAME, "2").await;

    // Release: the production planner and the sales manager, nobody else.
    for user in [
        VIEWER,
        SUPPORT,
        SALES,
        STORES,
        LOGISTICS,
        "technician@example.com",
    ] {
        let (status, _) = post(
            &e.app,
            user,
            "/production-orders",
            json!({ "order_id": order, "order_line_id": line }),
        )
        .await;
        assert_eq!(status, StatusCode::FORBIDDEN, "{user}");
    }
    let (status, po) = post(
        &e.app,
        MANAGER,
        "/production-orders",
        json!({ "order_id": order, "order_line_id": line }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{po}");
    let n = id(&po);

    // Reading: customer service, sales, the warehouse and viewers.
    for user in [VIEWER, SUPPORT, SALES, STORES, PLANNER] {
        let (status, _) = get(&e.app, user, &format!("/production-orders/{n}")).await;
        assert_eq!(status, StatusCode::OK, "{user}");
        assert_eq!(
            get(&e.app, user, "/production-orders").await.0,
            StatusCode::OK,
            "{user}"
        );
    }
    for user in ["technician@example.com", LOGISTICS] {
        assert_eq!(
            get(&e.app, user, "/production-orders").await.0,
            StatusCode::FORBIDDEN,
            "{user}"
        );
    }

    // Running: the planner and the warehouse; planning changes need write.
    for user in [VIEWER, SALES, MANAGER] {
        let (status, _) = post(
            &e.app,
            user,
            &format!("/production-orders/{n}/start"),
            json!({}),
        )
        .await;
        assert_eq!(status, StatusCode::FORBIDDEN, "{user}");
    }
    let (status, _) = put(
        &e.app,
        STORES,
        &format!("/production-orders/{n}"),
        json!({}),
    )
    .await;
    assert_eq!(
        status,
        StatusCode::FORBIDDEN,
        "the warehouse runs, it does not plan"
    );
    let (status, _) = post(
        &e.app,
        STORES,
        &format!("/production-orders/{n}/start"),
        json!({}),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn production_orders_stay_within_their_company(db: PgPool) {
    let e = env(db).await;
    e.frame_parts().await;
    let po = e.build_for_stock(FRAME, "1").await;
    let n = id(&po);

    let other = Uuid::now_v7();
    sqlx::query("INSERT INTO core.companies (id, name, country_code, currency) VALUES ($1, 'Other BV', 'BE', 'EUR')")
        .bind(other)
        .execute(&e.db)
        .await
        .unwrap();
    let user = Uuid::now_v7();
    sqlx::query("INSERT INTO core.users (id, email, display_name) VALUES ($1, 'other@example.com', 'Other')")
        .bind(user)
        .execute(&e.db)
        .await
        .unwrap();
    sqlx::query("INSERT INTO core.user_companies (user_id, company_id, roles, is_default) VALUES ($1, $2, '{admin}', true)")
        .bind(user)
        .bind(other)
        .execute(&e.db)
        .await
        .unwrap();
    let theirs = "other@example.com";
    assert_eq!(
        get(&e.app, theirs, &format!("/production-orders/{n}"))
            .await
            .0,
        StatusCode::NOT_FOUND
    );
    let (_, list) = get(&e.app, theirs, "/production-orders").await;
    assert_eq!(list["total"], 0);
    for action in ["start", "reserve"] {
        let (status, _) = post(
            &e.app,
            theirs,
            &format!("/production-orders/{n}/{action}"),
            json!({}),
        )
        .await;
        assert_eq!(status, StatusCode::NOT_FOUND, "{action}");
    }
    let (status, _) = post(
        &e.app,
        theirs,
        &format!("/production-orders/{n}/cancel"),
        json!({ "reason": "x" }),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (_, divisions) = get(&e.app, theirs, "/production/divisions").await;
    assert_eq!(divisions.as_array().unwrap().len(), 0);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn only_what_can_be_built_is_released(db: PgPool) {
    let e = env(db).await;
    e.frame_parts().await;
    // A purchased product has no BOM to build from; a draft order cannot be released at all.
    let (status, r) = post(
        &e.app,
        PLANNER,
        "/production-orders",
        json!({ "product_id": PROFILE, "quantity": "1" }),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{r}");
    for body in [
        json!({}),
        json!({ "product_id": FRAME }),
        json!({ "product_id": FRAME, "quantity": "0" }),
        json!({ "product_id": FRAME, "quantity": "1.00001" }),
        json!({ "order_id": uid() }),
    ] {
        let (status, r) = post(&e.app, PLANNER, "/production-orders", body.clone()).await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{body} {r}");
    }
    let (status, qn) = post(
        &e.app,
        SALES,
        "/quotations",
        json!({ "customer_id": ALPHA, "lines": [{ "product_id": FRAME, "quantity": "1" }] }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{qn}");
    post(
        &e.app,
        SALES,
        &format!("/quotations/{}/send", id(&qn)),
        json!({}),
    )
    .await;
    let (_, o) = post(
        &e.app,
        SALES,
        &format!("/quotations/{}/convert", id(&qn)),
        json!({}),
    )
    .await;
    let (status, r) = e
        .release(
            &id(&o["order"]),
            o["lines"][0]["id"].as_str().unwrap(),
            json!({}),
        )
        .await;
    assert_eq!(status, StatusCode::CONFLICT, "a draft order: {r}");
}

#[test]
fn the_production_request_bodies_are_in_the_api_contract() {
    // Schema names are global in the OpenAPI document: a clash silently replaces one schema with
    // the other, and the generated clients then send the wrong body (it happened with
    // `CompleteInput`, which the field service already has).
    let doc = serde_json::to_value(tradocraft_api::openapi()).unwrap();
    let schemas = &doc["components"]["schemas"];
    for (name, field) in [
        ("CompleteProductionInput", "output"),
        ("ReleaseProductionInput", "product_id"),
        ("ProductionOutputInput", "location_id"),
        ("ProductionComponentActual", "component_id"),
    ] {
        assert!(
            schemas[name]["properties"].get(field).is_some(),
            "{name} lacks {field}"
        );
    }
    assert!(schemas["CompleteInput"]["properties"]
        .get("notes")
        .is_some());
    let body = &doc["paths"]["/api/v1/production-orders/{id}/complete"]["post"]["requestBody"]
        ["content"]["application/json"]["schema"]["$ref"];
    assert!(
        body.as_str().unwrap().ends_with("/CompleteProductionInput"),
        "{body}"
    );
}

/// The user id of a test user, by e-mail.
async fn user_id(db: &PgPool, email: &str) -> String {
    sqlx::query_scalar::<_, Uuid>("SELECT id FROM core.users WHERE email = $1")
        .bind(email)
        .fetch_one(db)
        .await
        .unwrap()
        .to_string()
}

fn member_ids(division: &Value) -> Vec<String> {
    division["members"]
        .as_array()
        .unwrap()
        .iter()
        .map(|m| m["user_id"].as_str().unwrap().to_string())
        .collect()
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn division_members_replace_all_and_report_membership_per_caller(db: PgPool) {
    let e = env(db).await;
    let planner = user_id(&e.db, PLANNER).await;
    let stores = user_id(&e.db, STORES).await;
    let admin = user_id(&e.db, ADMIN).await;

    // Created with members; the response lists them and tells each caller whether they are in it.
    let (status, elec) = post(
        &e.app,
        ADMIN,
        "/production/divisions",
        json!({ "code": "ELEC", "name": "Electronics", "member_user_ids": [planner, stores, planner] }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{elec}");
    assert_eq!(member_ids(&elec).len(), 2, "duplicates collapse");
    assert_eq!(elec["is_member"], false, "the admin is not in it");
    // A user can be in several divisions.
    let (_, mech) = post(
        &e.app,
        ADMIN,
        "/production/divisions",
        json!({ "code": "MECH", "name": "Mechanics", "sort_order": 1, "member_user_ids": [planner, admin] }),
    )
    .await;
    let (_, list) = get(&e.app, PLANNER, "/production/divisions").await;
    assert_eq!(list[0]["is_member"], true);
    assert_eq!(list[1]["is_member"], true);
    let (_, list) = get(&e.app, STORES, "/production/divisions").await;
    assert_eq!(list[0]["is_member"], true);
    assert_eq!(list[1]["is_member"], false);
    let (_, list) = get(&e.app, SALES, "/production/divisions").await;
    assert!(list
        .as_array()
        .unwrap()
        .iter()
        .all(|d| d["is_member"] == false));

    // A field left out keeps the members; a list replaces all of them; an empty list clears them.
    let uri = format!("/production/divisions/{}", id(&elec));
    let (status, same) = put(
        &e.app,
        ADMIN,
        &uri,
        json!({ "code": "ELEC", "name": "Electronics and control" }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{same}");
    assert_eq!(member_ids(&same).len(), 2);
    let (_, replaced) = put(
        &e.app,
        ADMIN,
        &uri,
        json!({ "code": "ELEC", "name": "Electronics", "member_user_ids": [stores] }),
    )
    .await;
    assert_eq!(member_ids(&replaced), vec![stores.clone()]);
    let (_, still) = get(&e.app, ADMIN, "/production/divisions").await;
    assert_eq!(
        member_ids(&still[1]).len(),
        2,
        "the other division is untouched"
    );
    assert_eq!(id(&still[1]), id(&mech));
    let (_, cleared) = put(
        &e.app,
        ADMIN,
        &uri,
        json!({ "code": "ELEC", "name": "Electronics", "member_user_ids": [] }),
    )
    .await;
    assert!(member_ids(&cleared).is_empty());

    // Member changes are audited.
    let audited: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM audit.events WHERE entity = 'production_division' AND action = 'updated'
         AND jsonb_typeof(data->'member_user_ids') = 'array'",
    )
    .fetch_one(&e.db)
    .await
    .unwrap();
    assert_eq!(audited, 2);

    // Only the administrator changes members.
    for user in [PLANNER, SALES, MANAGER] {
        let (status, _) = put(
            &e.app,
            user,
            &uri,
            json!({ "code": "ELEC", "name": "Electronics", "member_user_ids": [planner] }),
        )
        .await;
        assert_eq!(status, StatusCode::FORBIDDEN, "{user}");
    }
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn division_members_must_be_active_colleagues_of_the_company(db: PgPool) {
    let e = env(db).await;
    let planner = user_id(&e.db, PLANNER).await;
    // A user of another company only, and an inactive user.
    let other_company = Uuid::now_v7();
    sqlx::query("INSERT INTO core.companies (id, name) VALUES ($1, 'Other')")
        .bind(other_company)
        .execute(&e.db)
        .await
        .unwrap();
    let foreign = Uuid::now_v7();
    sqlx::query("INSERT INTO core.users (id, email, display_name) VALUES ($1, 'foreign@example.com', 'Foreign')")
        .bind(foreign)
        .execute(&e.db)
        .await
        .unwrap();
    sqlx::query("INSERT INTO core.user_companies (user_id, company_id, roles, is_default) VALUES ($1, $2, $3, true)")
        .bind(foreign)
        .bind(other_company)
        .bind(vec!["admin".to_string()])
        .execute(&e.db)
        .await
        .unwrap();
    let gone = user_id(&e.db, STORES).await;
    sqlx::query("UPDATE core.users SET active = false WHERE id = $1::uuid")
        .bind(&gone)
        .execute(&e.db)
        .await
        .unwrap();

    for bad in [foreign.to_string(), gone, Uuid::now_v7().to_string()] {
        let (status, body) = post(
            &e.app,
            ADMIN,
            "/production/divisions",
            json!({ "code": "X", "name": "X", "member_user_ids": [planner, bad] }),
        )
        .await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{body}");
    }
    // Nothing was created by the refused requests.
    let (_, list) = get(&e.app, ADMIN, "/production/divisions").await;
    assert!(list.as_array().unwrap().is_empty());

    // The other company sees none of this company's divisions or members.
    let (_, weld) = post(
        &e.app,
        ADMIN,
        "/production/divisions",
        json!({ "code": "WELD", "name": "Welding", "member_user_ids": [planner] }),
    )
    .await;
    let (status, theirs) = get(&e.app, "foreign@example.com", "/production/divisions").await;
    assert_eq!(status, StatusCode::OK, "{theirs}");
    assert!(theirs.as_array().unwrap().is_empty());
    let (status, _) = put(
        &e.app,
        "foreign@example.com",
        &format!("/production/divisions/{}", id(&weld)),
        json!({ "code": "WELD", "name": "Welding", "member_user_ids": [foreign.to_string()] }),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    // The database refuses a membership across companies too.
    let cross = sqlx::query(
        "INSERT INTO production.division_members (company_id, division_id, user_id) VALUES ($1, $2::uuid, $3)",
    )
    .bind(other_company)
    .bind(id(&weld))
    .bind(foreign)
    .execute(&e.db)
    .await;
    assert!(cross.is_err());
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn mine_filter_returns_own_divisions_and_unassigned_orders(db: PgPool) {
    let e = env(db).await;
    e.stock(PROFILE, "60").await;
    e.stock(BOLT, "300").await;
    let planner = user_id(&e.db, PLANNER).await;
    let (_, elec) = post(
        &e.app,
        ADMIN,
        "/production/divisions",
        json!({ "code": "ELEC", "name": "Electronics", "member_user_ids": [planner] }),
    )
    .await;
    let (_, mech) = post(
        &e.app,
        ADMIN,
        "/production/divisions",
        json!({ "code": "MECH", "name": "Mechanics", "member_user_ids": [planner] }),
    )
    .await;
    let (_, weld) = post(
        &e.app,
        ADMIN,
        "/production/divisions",
        json!({ "code": "WELD", "name": "Welding" }),
    )
    .await;
    for d in [Some(id(&elec)), Some(id(&mech)), Some(id(&weld)), None] {
        let (status, po) = post(
            &e.app,
            ADMIN,
            "/production-orders",
            json!({ "product_id": FRAME, "quantity": "1", "division_id": d }),
        )
        .await;
        assert_eq!(status, StatusCode::CREATED, "{po}");
    }
    let names = |q: &Value| -> Vec<String> {
        let mut v: Vec<String> = q["items"]
            .as_array()
            .unwrap()
            .iter()
            .map(|i| i["division_name"].as_str().unwrap_or("-").to_string())
            .collect();
        v.sort();
        v
    };
    let (_, all) = get(&e.app, PLANNER, "/production-orders").await;
    assert_eq!(all["total"], 4);
    let (_, all) = get(&e.app, PLANNER, "/production-orders?mine=false").await;
    assert_eq!(all["total"], 4);
    // Own divisions plus unassigned; the other division's order is left out.
    let (status, mine) = get(&e.app, PLANNER, "/production-orders?mine=true").await;
    assert_eq!(status, StatusCode::OK, "{mine}");
    assert_eq!(mine["total"], 3);
    assert_eq!(names(&mine), vec!["-", "Electronics", "Mechanics"]);
    // It combines with the division filter.
    let (_, one) = get(
        &e.app,
        PLANNER,
        &format!("/production-orders?mine=true&division_id={}", id(&mech)),
    )
    .await;
    assert_eq!(names(&one), vec!["Mechanics"]);
    let (_, none) = get(
        &e.app,
        PLANNER,
        &format!("/production-orders?mine=true&division_id={}", id(&weld)),
    )
    .await;
    assert_eq!(none["total"], 0);
    // Someone with no division sees only the unassigned orders with mine=true, and all otherwise.
    let (_, admin_mine) = get(&e.app, ADMIN, "/production-orders?mine=true").await;
    assert_eq!(names(&admin_mine), vec!["-"]);
    let (_, admin_all) = get(&e.app, ADMIN, "/production-orders").await;
    assert_eq!(admin_all["total"], 4);

    // Deactivation is unchanged: a used division is refused on delete and can be deactivated, and
    // the members stay.
    let (status, _) = api(
        &e.app,
        ADMIN,
        Method::DELETE,
        &format!("/production/divisions/{}", id(&elec)),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
    let (status, off) = put(
        &e.app,
        ADMIN,
        &format!("/production/divisions/{}", id(&elec)),
        json!({ "code": "ELEC", "name": "Electronics", "active": false }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{off}");
    assert_eq!(off["active"], false);
    assert_eq!(member_ids(&off), vec![planner]);
    // An unused division is deleted together with its members.
    let (_, tmp) = post(
        &e.app,
        ADMIN,
        "/production/divisions",
        json!({ "code": "TMP", "name": "Tmp", "member_user_ids": [user_id(&e.db, STORES).await] }),
    )
    .await;
    let (status, _) = api(
        &e.app,
        ADMIN,
        Method::DELETE,
        &format!("/production/divisions/{}", id(&tmp)),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NO_CONTENT);
}
