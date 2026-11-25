//! Material requirements planning (ADR 0091): a run nets what confirmed orders and production still
//! need against stock and what is on order, and proposes what to buy or build; a proposal becomes
//! a draft purchase order or a released production order, or is dismissed.

mod common;

use axum::http::{Method, StatusCode};
use common::{call, dec, setup};
use rust_decimal::Decimal;
use serde_json::{json, Value};
use sqlx::PgPool;
use uuid::Uuid;

const ADMIN: &str = "admin@example.com";
const SALES: &str = "sales@example.com";
const VIEWER: &str = "viewer@example.com";
const TECHNICIAN: &str = "technician@example.com"; // no production rights
const PLANNER: &str = "planner@example.com"; // role production
const BUYER: &str = "buyer@example.com"; // role purchaser
const STORES: &str = "stores@example.com"; // role warehouse
const COMPANY: &str = "00000000-0000-7000-8000-000000000001";
const ALPHA: &str = "00000000-0000-7000-8000-000000000401";
// Manufactured: per frame 6.5 m of profile (+10 % scrap) and 24 bolts (+2 %).
const FRAME: &str = "00000000-0000-7000-8000-000000000307";
const PROFILE: &str = "00000000-0000-7000-8000-000000000308";
const BOLT: &str = "00000000-0000-7000-8000-000000000309";

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

fn id(v: &Value) -> String {
    v["id"].as_str().unwrap().to_string()
}

struct Env {
    app: axum::Router,
    db: PgPool,
    main: String,
}

async fn env(db: PgPool) -> Env {
    let app = setup(db.clone()).await;
    add_user(&db, PLANNER, "production").await;
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
        main: w["locations"][0]["id"].as_str().unwrap().into(),
    }
}

impl Env {
    async fn today(&self) -> String {
        sqlx::query_scalar("SELECT current_date::text")
            .fetch_one(&self.db)
            .await
            .unwrap()
    }

    async fn receive(&self, product: &str, quantity: &str) {
        let (status, m) = post(
            &self.app,
            STORES,
            "/inventory/receipts",
            json!({ "id": Uuid::now_v7().to_string(), "location_id": self.main, "product_id": product, "quantity": quantity }),
        )
        .await;
        assert_eq!(status, StatusCode::CREATED, "{m}");
    }

    /// A confirmed order of one line.
    async fn order(&self, product: &str, quantity: &str) -> String {
        let (status, qn) = post(
            &self.app,
            SALES,
            "/quotations",
            json!({ "customer_id": ALPHA, "lines": [{ "product_id": product, "quantity": quantity }] }),
        )
        .await;
        assert_eq!(status, StatusCode::CREATED, "{qn}");
        let qid = id(&qn);
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
        post(
            &self.app,
            SALES,
            &format!("/orders/{order}/send"),
            json!({}),
        )
        .await;
        let (status, o) = post(
            &self.app,
            SALES,
            &format!("/orders/{order}/confirm"),
            json!({}),
        )
        .await;
        assert_eq!(status, StatusCode::OK, "{o}");
        let (status, o) = get(&self.app, SALES, &format!("/orders/{order}")).await;
        assert_eq!(status, StatusCode::OK, "{o}");
        o["order"]["number"].as_str().unwrap().into()
    }

    async fn run(&self, who: &str, body: Value) -> (StatusCode, Value) {
        post(&self.app, who, "/mrp/runs", body).await
    }

    async fn proposals(&self, who: &str, query: &str) -> Vec<Value> {
        let (status, p) = get(&self.app, who, &format!("/mrp/proposals?{query}")).await;
        assert_eq!(status, StatusCode::OK, "{who}: {p}");
        p.as_array().unwrap().clone()
    }
}

fn of<'a>(list: &'a [Value], product: &str) -> &'a Value {
    list.iter()
        .find(|p| p["product_id"] == product)
        .unwrap_or_else(|| panic!("no proposal for {product} in {list:?}"))
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_run_proposes_what_the_orders_still_need_and_replaces_the_open_proposals(db: PgPool) {
    let e = env(db).await;
    let number = e.order(FRAME, "2").await;
    let today = e.today().await;

    let (status, run) = e.run(PLANNER, json!({})).await;
    assert_eq!(status, StatusCode::CREATED, "{run}");
    assert!(run["number"].as_str().unwrap().starts_with("MRP"), "{run}");
    assert_eq!(run["horizon_days"], 90);
    assert_eq!(run["proposals"], 3);
    assert_eq!(run["planned_on"], today.as_str());

    let open = e.proposals(PLANNER, "").await;
    assert_eq!(open.len(), 3);
    // The frames are built, from the order.
    let frame = of(&open, FRAME);
    assert_eq!(frame["kind"], "production");
    assert_eq!(dec(&frame["quantity"]), Decimal::from(2));
    assert_eq!(frame["reason"], "demand");
    assert_eq!(frame["need_date"], today.as_str());
    assert_eq!(frame["pegging"][0]["kind"], "sales_order");
    assert_eq!(frame["pegging"][0]["number"], number.as_str());
    assert_eq!(frame["supplier_id"], Value::Null);
    assert_eq!(frame["status"], "open");
    // The components are bought for the day the build starts: 2 x 6.5 x 1.10 and 2 x 24 x 1.02.
    let profile = of(&open, PROFILE);
    assert_eq!(profile["kind"], "purchase");
    assert_eq!(
        dec(&profile["quantity"]),
        "14.3".parse::<Decimal>().unwrap()
    );
    assert_eq!(profile["pegging"][0]["kind"], "planned");
    assert_eq!(profile["pegging"][0]["number"], "FRAME-A");
    assert_eq!(
        dec(&of(&open, BOLT)["quantity"]),
        "48.96".parse::<Decimal>().unwrap()
    );

    // With the parts in stock only the frames are left to build.
    e.receive(PROFILE, "20").await;
    e.receive(BOLT, "100").await;
    let (_, run2) = e.run(PLANNER, json!({ "horizon_days": 30 })).await;
    assert_eq!(run2["proposals"], 1);
    assert_eq!(run2["horizon_days"], 30);
    let open = e.proposals(PLANNER, "").await;
    assert_eq!(open.len(), 1);
    assert_eq!(open[0]["product_id"], FRAME);
    assert_eq!(open[0]["run_number"], run2["number"]);
    // The first run's proposals were replaced, not deleted.
    let old = e.proposals(PLANNER, "status=superseded").await;
    assert_eq!(old.len(), 3);
    assert_eq!(e.proposals(PLANNER, "status=all").await.len(), 4);
    let (_, runs) = get(&e.app, PLANNER, "/mrp/runs").await;
    assert_eq!(runs.as_array().unwrap().len(), 2);
    assert_eq!(runs[0]["number"], run2["number"], "newest first");

    // Frames in stock cover the order: nothing to do.
    e.receive(FRAME, "2").await;
    let (_, run3) = e.run(PLANNER, json!({})).await;
    assert_eq!(run3["proposals"], 0);
    assert!(e.proposals(PLANNER, "").await.is_empty());

    // The filters.
    assert_eq!(
        e.proposals(PLANNER, &format!("product_id={FRAME}&status=all"))
            .await
            .len(),
        2
    );
    assert_eq!(
        e.proposals(PLANNER, &format!("run_id={}&status=all", id(&run2)))
            .await
            .len(),
        1
    );
    assert_eq!(
        e.proposals(PLANNER, "kind=purchase&status=all").await.len(),
        2
    );
    for bad in ["status=nope", "kind=nope"] {
        let (status, _) = get(&e.app, PLANNER, &format!("/mrp/proposals?{bad}")).await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{bad}");
    }
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn planning_parameters_and_the_preferred_supplier_shape_a_proposal(db: PgPool) {
    let e = env(db).await;
    e.order(FRAME, "2").await;
    let (status, supplier) = post(
        &e.app,
        BUYER,
        "/suppliers",
        json!({ "name": "Steel NV", "code": "STEEL", "country": "be" }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{supplier}");
    let supplier = id(&supplier);
    // Preferred for the profile: at least 50 at a time, four days of lead time.
    let (status, sp) = post(
        &e.app,
        BUYER,
        &format!("/suppliers/{supplier}/products/{PROFILE}"),
        json!({ "unit_price": "3.20", "moq": "50", "lead_time_days": 4, "is_preferred": true }),
    )
    .await;
    assert!(status.is_success(), "{status}: {sp}");
    // Packs of 12, and 5 to keep in stock.
    let (_, product) = get(&e.app, ADMIN, &format!("/products/{PROFILE}")).await;
    let mut body = product.clone();
    body["order_multiple"] = json!("12");
    body["safety_stock"] = json!("5");
    let (status, saved) = put(&e.app, ADMIN, &format!("/products/{PROFILE}"), body.clone()).await;
    assert_eq!(status, StatusCode::OK, "{saved}");
    assert_eq!(dec(&saved["order_multiple"]), Decimal::from(12));
    assert_eq!(dec(&saved["safety_stock"]), Decimal::from(5));
    for (field, value) in [("order_multiple", "0"), ("safety_stock", "-1")] {
        let mut bad = body.clone();
        bad[field] = json!(value);
        let (status, _) = put(&e.app, ADMIN, &format!("/products/{PROFILE}"), bad).await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{field}");
    }

    e.run(PLANNER, json!({})).await;
    let open = e.proposals(PLANNER, "").await;
    let profile = of(&open, PROFILE);
    // 14.3 to build, plus 5 safety stock = 19.3; the supplier wants 50; packs of 12 make 60.
    assert_eq!(dec(&profile["quantity"]), Decimal::from(60));
    assert_eq!(profile["supplier_id"], supplier.as_str());
    assert_eq!(profile["supplier_name"], "Steel NV");
    // The build starts today, so the four days of lead time reach past the day it is needed.
    assert_eq!(profile["order_date"], e.today().await.as_str());
    assert_eq!(profile["late"], true);

    // The safety stock alone makes a proposal for a product nothing needs.
    sqlx::query("UPDATE products.products SET safety_stock = 3 WHERE id = $1::uuid")
        .bind(BOLT)
        .execute(&e.db)
        .await
        .unwrap();
    e.receive(PROFILE, "100").await;
    e.receive(BOLT, "50").await;
    e.run(PLANNER, json!({})).await;
    let open = e.proposals(PLANNER, "").await;
    let bolt = of(&open, BOLT);
    // 50 - 48.96 = 1.04 is left, which is above zero but below the 3 to keep: not a shortage of
    // what the build needs, only of the safety stock.
    assert_eq!(bolt["reason"], "safety_stock", "{bolt}");
    assert_eq!(dec(&bolt["quantity"]), "1.96".parse::<Decimal>().unwrap());
    assert!(
        open.iter().all(|p| p["product_id"] != PROFILE),
        "100 m cover it"
    );
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn proposals_become_draft_purchase_orders_and_released_production_orders(db: PgPool) {
    let e = env(db).await;
    e.order(FRAME, "2").await;
    let (_, supplier) = post(
        &e.app,
        BUYER,
        "/suppliers",
        json!({ "name": "Steel NV", "code": "STEEL", "country": "be" }),
    )
    .await;
    let supplier = id(&supplier);
    e.run(PLANNER, json!({})).await;
    let open = e.proposals(PLANNER, "").await;
    let profile = id(of(&open, PROFILE));
    let frame = id(of(&open, FRAME));
    let bolt = id(of(&open, BOLT));

    // A purchase needs a supplier: the product has no preferred one.
    let (status, r) = post(
        &e.app,
        BUYER,
        &format!("/mrp/proposals/{profile}/convert"),
        json!({}),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{r}");
    let (status, r) = post(
        &e.app,
        BUYER,
        &format!("/mrp/proposals/{profile}/convert"),
        json!({ "supplier_id": supplier }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{r}");
    assert_eq!(r["proposal"]["status"], "converted");
    let po = r["converted_to"].as_str().unwrap();
    assert_eq!(r["proposal"]["converted_to"], po);
    let (status, order) = get(&e.app, BUYER, &format!("/purchase-orders/{po}")).await;
    assert_eq!(status, StatusCode::OK, "{order}");
    assert_eq!(order["number"], r["number"]);
    assert_eq!(order["status"], "draft");
    assert_eq!(order["supplier_id"], supplier.as_str());
    assert_eq!(order["expected_delivery_date"], e.today().await.as_str());
    assert_eq!(order["lines"][0]["product_id"], PROFILE);
    assert_eq!(
        dec(&order["lines"][0]["quantity"]),
        "14.3".parse::<Decimal>().unwrap()
    );
    // It is acted on once.
    let (status, _) = post(
        &e.app,
        BUYER,
        &format!("/mrp/proposals/{profile}/convert"),
        json!({ "supplier_id": supplier }),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);

    // Who may do what: a buyer does not build, a planner does not buy.
    let (status, _) = post(
        &e.app,
        BUYER,
        &format!("/mrp/proposals/{frame}/convert"),
        json!({}),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, _) = post(
        &e.app,
        PLANNER,
        &format!("/mrp/proposals/{bolt}/convert"),
        json!({ "supplier_id": supplier }),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, _) = post(
        &e.app,
        TECHNICIAN,
        &format!("/mrp/proposals/{frame}/dismiss"),
        json!({}),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);

    // The frames are released to production for stock, ready on the need date.
    e.receive(PROFILE, "20").await;
    e.receive(BOLT, "100").await;
    let (status, r) = post(
        &e.app,
        PLANNER,
        &format!("/mrp/proposals/{frame}/convert"),
        json!({}),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{r}");
    let mo = r["converted_to"].as_str().unwrap();
    let (status, order) = get(&e.app, PLANNER, &format!("/production-orders/{mo}")).await;
    assert_eq!(status, StatusCode::OK, "{order}");
    assert_eq!(order["number"], r["number"]);
    assert_eq!(order["status"], "released");
    assert_eq!(order["product_id"], FRAME);
    assert_eq!(dec(&order["quantity"]), Decimal::from(2));
    assert_eq!(order["planned_ready_date"], e.today().await.as_str());
    let actions: Vec<String> = sqlx::query_scalar(
        "SELECT action FROM audit.events WHERE entity = 'mrp_proposal' ORDER BY id",
    )
    .fetch_all(&e.db)
    .await
    .unwrap();
    assert_eq!(actions, ["converted", "converted"]);

    // A proposal can also be dismissed, once.
    let (status, r) = post(
        &e.app,
        BUYER,
        &format!("/mrp/proposals/{bolt}/dismiss"),
        json!({}),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{r}");
    assert_eq!(r["status"], "dismissed");
    let (status, _) = post(
        &e.app,
        BUYER,
        &format!("/mrp/proposals/{bolt}/dismiss"),
        json!({}),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!(e.proposals(PLANNER, "status=dismissed").await.len(), 1);
    assert!(
        e.proposals(PLANNER, "").await.is_empty(),
        "nothing is open any more"
    );
    let (status, _) = post(
        &e.app,
        PLANNER,
        &format!("/mrp/proposals/{}/dismiss", Uuid::now_v7()),
        json!({}),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn running_needs_production_rights_and_reading_follows_what_one_may_see(db: PgPool) {
    let e = env(db).await;
    e.order(FRAME, "2").await;
    for who in [SALES, VIEWER, BUYER, STORES, TECHNICIAN] {
        let (status, _) = e.run(who, json!({})).await;
        assert_eq!(status, StatusCode::FORBIDDEN, "{who} cannot run");
    }
    for horizon in [0, -5, 731] {
        let (status, _) = e.run(PLANNER, json!({ "horizon_days": horizon })).await;
        assert_eq!(
            status,
            StatusCode::UNPROCESSABLE_ENTITY,
            "horizon {horizon}"
        );
    }
    let (status, _) = e.run(ADMIN, json!({})).await;
    assert_eq!(status, StatusCode::CREATED);

    // The planner sees everything; the buyer only what is bought; others nothing.
    assert_eq!(e.proposals(PLANNER, "").await.len(), 3);
    let buyer = e.proposals(BUYER, "").await;
    assert_eq!(buyer.len(), 2);
    assert!(buyer.iter().all(|p| p["kind"] == "purchase"));
    // Sales follows production, so it sees what is built, and nothing that is bought.
    let sales = e.proposals(SALES, "").await;
    assert_eq!(sales.len(), 1);
    assert_eq!(sales[0]["kind"], "production");
    let (status, _) = get(&e.app, TECHNICIAN, "/mrp/proposals").await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, _) = get(&e.app, TECHNICIAN, "/mrp/runs").await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, runs) = get(&e.app, BUYER, "/mrp/runs").await;
    assert_eq!(status, StatusCode::OK, "{runs}");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn what_is_on_order_and_in_production_counts(db: PgPool) {
    let e = env(db).await;
    e.order(FRAME, "2").await;
    let (_, supplier) = post(
        &e.app,
        BUYER,
        "/suppliers",
        json!({ "name": "Steel NV", "code": "STEEL", "country": "be" }),
    )
    .await;
    let supplier = id(&supplier);
    // 20 m of profile and 100 bolts are on a purchase order that is approved.
    let (status, po) = post(
        &e.app,
        BUYER,
        "/purchase-orders",
        json!({ "supplier_id": supplier, "lines": [
            { "product_id": PROFILE, "quantity": "20", "unit_price": "3" },
            { "product_id": BOLT, "quantity": "100", "unit_price": "0.1" } ] }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{po}");
    // A draft is only an intention: it does not count yet.
    e.run(PLANNER, json!({})).await;
    assert_eq!(e.proposals(PLANNER, "").await.len(), 3);
    let (status, a) = post(
        &e.app,
        ADMIN,
        &format!("/purchase-orders/{}/approve", id(&po)),
        json!({}),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{a}");
    e.run(PLANNER, json!({})).await;
    let open = e.proposals(PLANNER, "").await;
    assert_eq!(open.len(), 1, "only the frames are left: {open:?}");
    assert_eq!(open[0]["product_id"], FRAME);

    // A production order that is released counts as supply, and its components as demand.
    let (status, mo) = post(
        &e.app,
        PLANNER,
        "/production-orders",
        json!({ "product_id": FRAME, "quantity": "2" }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{mo}");
    let (_, run) = e.run(PLANNER, json!({})).await;
    // The frames are covered by it; the parts it needs were reserved from a stock that is not
    // there yet (the purchase order has not arrived), so they are asked for again... or not: the
    // purchase order still covers them.
    assert_eq!(run["proposals"], 0, "{run}");
    let (_, runs) = get(&e.app, PLANNER, "/mrp/runs").await;
    assert_eq!(runs.as_array().unwrap().len(), 3);
}
