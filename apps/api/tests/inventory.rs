//! Inventory: the stock ledger and its invariants, units of measure, lots, serial units,
//! transfers, counts, reservations and availability, cost visibility and company isolation.

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
const STORES: &str = "stores@example.com"; // role warehouse
const PM: &str = "pm@example.com"; // role product_manager
const TECH: &str = "technician@example.com";
const COMPANY: &str = "00000000-0000-7000-8000-000000000001";
const ALPHA: &str = "00000000-0000-7000-8000-000000000401";
const FRAME: &str = "00000000-0000-7000-8000-000000000307"; // pcs, no tracking
const PROFILE: &str = "00000000-0000-7000-8000-000000000308"; // metres
const BOLT: &str = "00000000-0000-7000-8000-000000000309"; // pcs, made lot-tracked in tests
const PUMP: &str = "00000000-0000-7000-8000-000000000303"; // serial
const CTRL: &str = "00000000-0000-7000-8000-000000000310"; // serial
const UNIT_100: &str = "00000000-0000-7000-8000-000000000301"; // serial
const SERVICE: &str = "00000000-0000-7000-8000-000000000305";

fn uid() -> String {
    Uuid::now_v7().to_string()
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
async fn get(app: &axum::Router, user: &str, uri: &str) -> (StatusCode, Value) {
    api(app, user, Method::GET, uri, None).await
}

struct Env {
    app: axum::Router,
    db: PgPool,
    /// Main warehouse WH1 and its default location MAIN.
    wh: String,
    main: String,
}

async fn env(db: PgPool) -> Env {
    let app = setup(db.clone()).await;
    add_user(&db, STORES, "warehouse").await;
    add_user(&db, PM, "product_manager").await;
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
    async fn location(&self, code: &str) -> String {
        let (status, l) = post(
            &self.app,
            ADMIN,
            "/inventory/locations",
            json!({ "warehouse_id": self.wh, "code": code }),
        )
        .await;
        assert_eq!(status, StatusCode::CREATED, "{l}");
        l["id"].as_str().unwrap().into()
    }

    async fn receive(&self, product: &str, location: &str, quantity: &str) -> Value {
        let (status, m) = post(
            &self.app,
            STORES,
            "/inventory/receipts",
            json!({ "id": uid(), "product_id": product, "location_id": location, "quantity": quantity }),
        )
        .await;
        assert_eq!(status, StatusCode::CREATED, "{m}");
        m
    }

    async fn issue(&self, product: &str, location: &str, quantity: &str) -> (StatusCode, Value) {
        post(
            &self.app,
            STORES,
            "/inventory/issues",
            json!({ "id": uid(), "product_id": product, "location_id": location, "quantity": quantity }),
        )
        .await
    }

    /// (on hand, reserved, available) of a product in the warehouses.
    async fn totals(&self, product: &str) -> (Decimal, Decimal, Decimal) {
        let (status, p) = get(
            &self.app,
            ADMIN,
            &format!("/inventory/stock/products?product_id={product}"),
        )
        .await;
        assert_eq!(status, StatusCode::OK, "{p}");
        let i = &p["items"][0];
        (
            dec(&i["on_hand"]),
            dec(&i["reserved"]),
            dec(&i["available"]),
        )
    }

    async fn integrity_ok(&self) {
        let (status, i) = get(&self.app, ADMIN, "/inventory/integrity").await;
        assert_eq!(status, StatusCode::OK, "{i}");
        assert_eq!(i["ok"], true, "balances differ from the ledger: {i}");
    }
}

fn q(s: &str) -> Decimal {
    s.parse().unwrap()
}

// ---------------------------------------------------------------------------------------------
// Setup
// ---------------------------------------------------------------------------------------------

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn warehouses_locations_and_vans_are_maintained_by_the_admin(db: PgPool) {
    let e = env(db).await;
    // A van belongs to a technician and has its own location.
    let tech: Uuid = sqlx::query_scalar("SELECT id FROM core.users WHERE email = $1")
        .bind(TECH)
        .fetch_one(&e.db)
        .await
        .unwrap();
    let (status, van) = post(
        &e.app,
        ADMIN,
        "/inventory/warehouses",
        json!({ "code": "VAN-TOM", "name": "Van of Tom", "kind": "van", "assigned_user_id": tech }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{van}");
    assert_eq!(van["kind"], "van");
    assert_eq!(van["locations"][0]["code"], "VAN");
    let (status, _) = post(
        &e.app,
        ADMIN,
        "/inventory/warehouses",
        json!({ "code": "WH1", "name": "again" }),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
    let (status, _) = post(
        &e.app,
        ADMIN,
        "/inventory/warehouses",
        json!({ "code": "X", "name": "x", "assigned_user_id": tech }),
    )
    .await;
    assert_eq!(
        status,
        StatusCode::UNPROCESSABLE_ENTITY,
        "only a van has an assignee"
    );

    let shelf = e.location("A-01").await;
    let (_, list) = get(&e.app, SALES, "/inventory/warehouses").await;
    assert_eq!(list.as_array().unwrap().len(), 2);
    assert_eq!(list[1]["code"], "WH1");
    assert_eq!(list[1]["locations"].as_array().unwrap().len(), 2);

    // Only the admin changes the structure.
    for who in [STORES, SALES, VIEWER, PM] {
        let (status, _) = post(
            &e.app,
            who,
            "/inventory/locations",
            json!({ "warehouse_id": e.wh, "code": "Z" }),
        )
        .await;
        assert_eq!(status, StatusCode::FORBIDDEN, "{who}");
    }
    let (status, _) = get(&e.app, TECH, "/inventory/warehouses").await;
    assert_eq!(
        status,
        StatusCode::FORBIDDEN,
        "technicians have no inventory access yet"
    );

    // A location or warehouse with stock cannot be deactivated.
    e.receive(FRAME, &shelf, "3").await;
    let (status, r) = api(
        &e.app,
        ADMIN,
        Method::PUT,
        &format!("/inventory/locations/{shelf}"),
        Some(json!({ "code": "A-01", "active": false })),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT, "{r}");
    let (status, _) = api(
        &e.app,
        ADMIN,
        Method::PUT,
        &format!("/inventory/warehouses/{}", e.wh),
        Some(json!({ "code": "WH1", "name": "Main", "active": false })),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
    e.issue(FRAME, &shelf, "3").await;
    let (status, r) = api(
        &e.app,
        ADMIN,
        Method::PUT,
        &format!("/inventory/locations/{shelf}"),
        Some(json!({ "code": "A-01", "active": false })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{r}");
    // ...and an inactive location takes no more stock.
    let (status, _) = post(
        &e.app,
        STORES,
        "/inventory/receipts",
        json!({ "id": uid(), "product_id": FRAME, "location_id": shelf, "quantity": "1" }),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
}

// ---------------------------------------------------------------------------------------------
// Ledger invariants
// ---------------------------------------------------------------------------------------------

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn balance_equals_the_sum_of_moves_and_every_product_nets_to_zero(db: PgPool) {
    let e = env(db).await;
    let b = e.location("B-01").await;
    e.receive(FRAME, &e.main, "10").await;
    e.issue(FRAME, &e.main, "4").await;
    let (status, t) = post(&e.app, STORES, "/inventory/transfers", json!({ "id": uid(), "product_id": FRAME, "from_location_id": e.main, "to_location_id": b, "quantity": "2.5" })).await;
    assert_eq!(status, StatusCode::CREATED, "{t}");
    assert_eq!(t["kind"], "transfer");

    assert_eq!(e.totals(FRAME).await.0, q("6"));
    let (_, rows) = get(
        &e.app,
        SALES,
        &format!("/inventory/stock?product_id={FRAME}"),
    )
    .await;
    let by_loc: Vec<(String, Decimal)> = rows["items"]
        .as_array()
        .unwrap()
        .iter()
        .map(|r| {
            (
                r["location"].as_str().unwrap().to_string(),
                dec(&r["on_hand"]),
            )
        })
        .collect();
    assert_eq!(
        by_loc,
        vec![
            ("WH1/B-01".to_string(), q("2.5")),
            ("WH1/MAIN".to_string(), q("3.5"))
        ]
    );

    // The projection equals the ledger, row by row...
    let mismatches: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM inventory.stock_balances b WHERE b.quantity <> (
             SELECT COALESCE(sum(CASE WHEN m.to_location_id = b.location_id THEN m.quantity ELSE -m.quantity END), 0)
             FROM inventory.stock_moves m WHERE m.product_id = b.product_id
               AND (m.to_location_id = b.location_id OR m.from_location_id = b.location_id)
               AND m.lot_id IS NOT DISTINCT FROM b.lot_id)",
    )
    .fetch_one(&e.db)
    .await
    .unwrap();
    assert_eq!(mismatches, 0);
    // ...and with the virtual locations every product nets to zero (double entry).
    let net: Decimal = sqlx::query_scalar("SELECT COALESCE(sum(quantity), 0) FROM inventory.stock_balances WHERE product_id = $1::uuid")
        .bind(FRAME)
        .fetch_one(&e.db)
        .await
        .unwrap();
    assert_eq!(net, Decimal::ZERO);
    e.integrity_ok().await;
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_ledger_is_append_only(db: PgPool) {
    let e = env(db).await;
    e.receive(FRAME, &e.main, "5").await;
    let update = sqlx::query("UPDATE inventory.stock_moves SET quantity = 99")
        .execute(&e.db)
        .await;
    assert!(update.is_err(), "UPDATE must be refused");
    let delete = sqlx::query("DELETE FROM inventory.stock_moves")
        .execute(&e.db)
        .await;
    assert!(delete.is_err(), "DELETE must be refused");
    let truncate = sqlx::query("TRUNCATE inventory.stock_moves CASCADE")
        .execute(&e.db)
        .await;
    assert!(truncate.is_err(), "TRUNCATE must be refused");
    assert_eq!(e.totals(FRAME).await.0, q("5"));
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn stock_cannot_go_negative(db: PgPool) {
    let e = env(db).await;
    e.receive(FRAME, &e.main, "2").await;
    let (status, r) = e.issue(FRAME, &e.main, "3").await;
    assert_eq!(status, StatusCode::CONFLICT, "{r}");
    assert!(
        r["message"].as_str().unwrap().contains("not enough stock"),
        "{r}"
    );
    let (status, _) = e.issue(FRAME, &e.main, "0").await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    let (status, _) = e.issue(FRAME, &e.main, "1.00001").await;
    assert_eq!(
        status,
        StatusCode::UNPROCESSABLE_ENTITY,
        "four decimals at most"
    );
    let (status, _) = post(
        &e.app,
        STORES,
        "/inventory/receipts",
        json!({ "id": uid(), "product_id": SERVICE, "location_id": e.main, "quantity": "1" }),
    )
    .await;
    assert_eq!(
        status,
        StatusCode::UNPROCESSABLE_ENTITY,
        "services are not stocked"
    );
    assert_eq!(e.totals(FRAME).await.0, q("2"));
    e.integrity_ok().await;
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_retry_with_the_same_id_changes_nothing_and_a_clash_is_refused(db: PgPool) {
    let e = env(db).await;
    let id = uid();
    let body = json!({ "id": id, "product_id": FRAME, "location_id": e.main, "quantity": "7" });
    let (s1, m1) = post(&e.app, STORES, "/inventory/receipts", body.clone()).await;
    let (s2, m2) = post(&e.app, STORES, "/inventory/receipts", body.clone()).await;
    assert_eq!((s1, s2), (StatusCode::CREATED, StatusCode::OK));
    assert_eq!(m1["id"], m2["id"]);
    assert_eq!(m1["seq"], m2["seq"]);
    assert_eq!(e.totals(FRAME).await.0, q("7"));
    let n: i64 = sqlx::query_scalar("SELECT count(*) FROM inventory.stock_moves")
        .fetch_one(&e.db)
        .await
        .unwrap();
    assert_eq!(n, 1);

    // Same id, different content.
    let (status, r) = post(
        &e.app,
        STORES,
        "/inventory/receipts",
        json!({ "id": id, "product_id": FRAME, "location_id": e.main, "quantity": "8" }),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT, "{r}");
    // Same id used for another kind of move.
    let (status, _) = post(
        &e.app,
        STORES,
        "/inventory/issues",
        json!({ "id": id, "product_id": FRAME, "location_id": e.main, "quantity": "7" }),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!(e.totals(FRAME).await.0, q("7"));
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_correction_is_a_reversal_move_and_the_original_stays(db: PgPool) {
    let e = env(db).await;
    e.receive(FRAME, &e.main, "10").await;
    let (_, issued) = e.issue(FRAME, &e.main, "4").await;
    let issued_id = issued["id"].as_str().unwrap();
    assert_eq!(e.totals(FRAME).await.0, q("6"));

    let rid = uid();
    let (status, r) = post(
        &e.app,
        ADMIN,
        &format!("/inventory/moves/{issued_id}/reverse"),
        json!({ "id": rid, "note": "wrong product picked" }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{r}");
    assert_eq!(r["reversed_of"], issued_id);
    assert_eq!(r["reason"], "reversal");
    assert_eq!(r["from_location_id"], issued["to_location_id"]);
    assert_eq!(r["to_location_id"], issued["from_location_id"]);
    assert_eq!(e.totals(FRAME).await.0, q("10"));
    // The original is still there, marked as reversed.
    let (_, original) = get(&e.app, ADMIN, &format!("/inventory/moves/{issued_id}")).await;
    assert_eq!(original["reversed_by"], r["id"]);
    assert_eq!(original["quantity"], issued["quantity"]);

    // A retry returns the same reversal; a second reversal is refused; a reversal cannot be reversed.
    let (status, again) = post(
        &e.app,
        ADMIN,
        &format!("/inventory/moves/{issued_id}/reverse"),
        json!({ "id": rid, "note": "wrong product picked" }),
    )
    .await;
    assert_eq!(
        (status, again["id"].clone()),
        (StatusCode::OK, r["id"].clone())
    );
    let (status, _) = post(
        &e.app,
        ADMIN,
        &format!("/inventory/moves/{issued_id}/reverse"),
        json!({ "id": uid() }),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
    let rev_id = r["id"].as_str().unwrap();
    let (status, _) = post(
        &e.app,
        ADMIN,
        &format!("/inventory/moves/{rev_id}/reverse"),
        json!({ "id": uid() }),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
    // Only the inventory admin reverses.
    let (status, _) = post(
        &e.app,
        STORES,
        &format!("/inventory/moves/{issued_id}/reverse"),
        json!({ "id": uid() }),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);

    // Reversing a receipt fails when the stock has been used since.
    let receipt = e.receive(FRAME, &e.main, "5").await;
    e.issue(FRAME, &e.main, "12").await;
    let rid = receipt["id"].as_str().unwrap();
    let (status, r) = post(
        &e.app,
        ADMIN,
        &format!("/inventory/moves/{rid}/reverse"),
        json!({ "id": uid() }),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT, "{r}");
    // History: newest first, with both sides of the correction.
    let (_, h) = get(
        &e.app,
        SALES,
        &format!("/inventory/moves?product_id={FRAME}&limit=2"),
    )
    .await;
    assert_eq!(h["total"], 5);
    assert_eq!(h["items"].as_array().unwrap().len(), 2);
    assert!(h["items"][0]["seq"].as_i64() > h["items"][1]["seq"].as_i64());
    e.integrity_ok().await;
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn balances_can_be_rebuilt_from_the_ledger(db: PgPool) {
    let e = env(db).await;
    e.receive(FRAME, &e.main, "10").await;
    e.issue(FRAME, &e.main, "3").await;
    sqlx::query("UPDATE inventory.stock_balances SET quantity = quantity + 5 WHERE quantity = 7")
        .execute(&e.db)
        .await
        .unwrap();
    sqlx::query("DELETE FROM inventory.stock_balances WHERE allow_negative")
        .execute(&e.db)
        .await
        .unwrap();
    let (_, i) = get(&e.app, ADMIN, "/inventory/integrity").await;
    assert_eq!(i["ok"], false);
    assert!(!i["differences"].as_array().unwrap().is_empty());
    let (status, r) = post(&e.app, ADMIN, "/inventory/balances/rebuild", json!({})).await;
    assert_eq!(status, StatusCode::OK, "{r}");
    e.integrity_ok().await;
    assert_eq!(e.totals(FRAME).await.0, q("7"));
    let (status, _) = post(&e.app, STORES, "/inventory/balances/rebuild", json!({})).await;
    assert_eq!(status, StatusCode::FORBIDDEN);
}

// ---------------------------------------------------------------------------------------------
// Units of measure
// ---------------------------------------------------------------------------------------------

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn quantities_are_entered_in_other_units_and_stored_in_the_stock_unit(db: PgPool) {
    let e = env(db).await;
    // A box of 12 pieces, for this product only.
    let (status, u) = api(
        &e.app,
        ADMIN,
        Method::PUT,
        &format!("/inventory/products/{FRAME}/uoms"),
        Some(json!({ "uoms": [{ "uom_code": "set", "factor": "12" }] })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{u}");
    let (status, m) = post(&e.app, STORES, "/inventory/receipts", json!({ "id": uid(), "product_id": FRAME, "location_id": e.main, "quantity": "2", "uom": "set" })).await;
    assert_eq!(status, StatusCode::CREATED, "{m}");
    assert_eq!(dec(&m["quantity"]), q("24"));
    assert_eq!(dec(&m["entered_quantity"]), q("2"));
    assert_eq!(m["entered_uom"], "set");
    assert_eq!(m["unit"], "pcs");

    // Metres from centimetres (same category), rounded to four decimals.
    let (status, m) = post(&e.app, STORES, "/inventory/receipts", json!({ "id": uid(), "product_id": PROFILE, "location_id": e.main, "quantity": "250", "uom": "cm" })).await;
    assert_eq!(status, StatusCode::CREATED, "{m}");
    assert_eq!(dec(&m["quantity"]), q("2.5"));
    let (status, m) = post(&e.app, STORES, "/inventory/issues", json!({ "id": uid(), "product_id": PROFILE, "location_id": e.main, "quantity": "5", "uom": "mm" })).await;
    assert_eq!(status, StatusCode::CREATED, "{m}");
    assert_eq!(dec(&m["quantity"]), q("0.005"));

    // No conversion between a length and pieces; an unknown unit is refused.
    let (status, _) = post(&e.app, STORES, "/inventory/receipts", json!({ "id": uid(), "product_id": PROFILE, "location_id": e.main, "quantity": "1", "uom": "kg" })).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    let (status, _) = post(&e.app, STORES, "/inventory/receipts", json!({ "id": uid(), "product_id": PROFILE, "location_id": e.main, "quantity": "1", "uom": "furlong" })).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    // Too small to be a stock quantity.
    let (status, _) = post(&e.app, STORES, "/inventory/receipts", json!({ "id": uid(), "product_id": PROFILE, "location_id": e.main, "quantity": "0.0001", "uom": "mm" })).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    // The stock unit of a product with moves cannot change.
    let (_, p) = get(&e.app, ADMIN, &format!("/products/{PROFILE}")).await;
    let mut input = p.clone();
    input["unit"] = json!("kg");
    let (status, _) = api(
        &e.app,
        ADMIN,
        Method::PUT,
        &format!("/products/{PROFILE}"),
        Some(input),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    e.integrity_ok().await;
}

// ---------------------------------------------------------------------------------------------
// Lots
// ---------------------------------------------------------------------------------------------

async fn make_lot_tracked(db: &PgPool, product: &str) {
    sqlx::query("UPDATE products.products SET tracking = 'lot' WHERE id = $1::uuid")
        .bind(product)
        .execute(db)
        .await
        .unwrap();
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn lot_tracked_stock_is_kept_per_lot(db: PgPool) {
    let e = env(db).await;
    make_lot_tracked(&e.db, BOLT).await;
    let (status, _) = post(
        &e.app,
        STORES,
        "/inventory/receipts",
        json!({ "id": uid(), "product_id": BOLT, "location_id": e.main, "quantity": "100" }),
    )
    .await;
    assert_eq!(
        status,
        StatusCode::UNPROCESSABLE_ENTITY,
        "a lot is required"
    );
    let (status, a) = post(&e.app, STORES, "/inventory/receipts", json!({ "id": uid(), "product_id": BOLT, "location_id": e.main, "quantity": "100", "lot_number": "L-A", "expiry_date": "2027-03-01" })).await;
    assert_eq!(status, StatusCode::CREATED, "{a}");
    let (_, b) = {
        let (s, v) = post(&e.app, STORES, "/inventory/receipts", json!({ "id": uid(), "product_id": BOLT, "location_id": e.main, "quantity": "50", "lot_number": "L-B", "expiry_date": "2026-12-01" })).await;
        assert_eq!(s, StatusCode::CREATED);
        (s, v)
    };
    // The generated Dart client sends dates as date-times.
    let (status, d) = post(&e.app, STORES, "/inventory/receipts", json!({ "id": uid(), "product_id": BOLT, "location_id": e.main, "quantity": "1", "lot_number": "L-C", "expiry_date": "2027-05-01T00:00:00.000" })).await;
    assert_eq!(status, StatusCode::CREATED, "{d}");
    let (_, lots) = get(&e.app, SALES, &format!("/inventory/lots?product_id={BOLT}")).await;
    assert!(lots
        .as_array()
        .unwrap()
        .iter()
        .any(|l| l["lot_number"] == "L-C" && l["expiry_date"] == "2027-05-01"));
    // More of an existing lot adds to it; a different expiry date for it is refused.
    let (status, _) = post(&e.app, STORES, "/inventory/receipts", json!({ "id": uid(), "product_id": BOLT, "location_id": e.main, "quantity": "10", "lot_number": "L-A" })).await;
    assert_eq!(status, StatusCode::CREATED);
    let (status, _) = post(&e.app, STORES, "/inventory/receipts", json!({ "id": uid(), "product_id": BOLT, "location_id": e.main, "quantity": "10", "lot_number": "L-A", "expiry_date": "2030-01-01" })).await;
    assert_eq!(status, StatusCode::CONFLICT);

    let (_, rows) = get(
        &e.app,
        SALES,
        &format!("/inventory/stock?product_id={BOLT}"),
    )
    .await;
    let per_lot: Vec<(String, Decimal)> = rows["items"]
        .as_array()
        .unwrap()
        .iter()
        .map(|r| {
            (
                r["lot_number"].as_str().unwrap().to_string(),
                dec(&r["on_hand"]),
            )
        })
        .collect();
    assert_eq!(
        per_lot,
        vec![
            ("L-A".to_string(), q("110")),
            ("L-B".to_string(), q("50")),
            ("L-C".to_string(), q("1"))
        ]
    );
    let (_, lots) = get(
        &e.app,
        SALES,
        &format!("/inventory/lots?product_id={BOLT}&in_stock=true"),
    )
    .await;
    assert_eq!(lots.as_array().unwrap().len(), 3);
    assert_eq!(lots[0]["lot_number"], "L-B", "earliest expiry first");

    // Issues name the lot, and one lot cannot be drawn below its own quantity.
    let lot_b = b["lot_id"].as_str().unwrap();
    let (status, _) = post(
        &e.app,
        STORES,
        "/inventory/issues",
        json!({ "id": uid(), "product_id": BOLT, "location_id": e.main, "quantity": "5" }),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    let (status, r) = post(&e.app, STORES, "/inventory/issues", json!({ "id": uid(), "product_id": BOLT, "location_id": e.main, "quantity": "60", "lot_id": lot_b })).await;
    assert_eq!(status, StatusCode::CONFLICT, "{r}");
    let (status, _) = post(&e.app, STORES, "/inventory/issues", json!({ "id": uid(), "product_id": BOLT, "location_id": e.main, "quantity": "20", "lot_id": lot_b })).await;
    assert_eq!(status, StatusCode::CREATED);
    // A lot of another product cannot be used, nor a lot on an untracked product.
    let (status, _) = post(&e.app, STORES, "/inventory/receipts", json!({ "id": uid(), "product_id": FRAME, "location_id": e.main, "quantity": "1", "lot_number": "X" })).await;
    assert_eq!(
        status,
        StatusCode::CREATED,
        "a lot number is ignored for untracked products"
    );
    let (status, _) = post(&e.app, STORES, "/inventory/issues", json!({ "id": uid(), "product_id": FRAME, "location_id": e.main, "quantity": "1", "lot_id": lot_b })).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    // Tracking cannot be switched once there are moves.
    let (_, p) = get(&e.app, ADMIN, &format!("/products/{BOLT}")).await;
    let mut input = p.clone();
    input["tracking"] = json!("none");
    let (status, _) = api(
        &e.app,
        ADMIN,
        Method::PUT,
        &format!("/products/{BOLT}"),
        Some(input),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    e.integrity_ok().await;
}

// ---------------------------------------------------------------------------------------------
// Transfers
// ---------------------------------------------------------------------------------------------

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn transfers_move_stock_between_locations_and_to_a_van(db: PgPool) {
    let e = env(db).await;
    let (_, van) = post(
        &e.app,
        ADMIN,
        "/inventory/warehouses",
        json!({ "code": "VAN-1", "name": "Van 1", "kind": "van" }),
    )
    .await;
    let van_loc = van["locations"][0]["id"].as_str().unwrap().to_string();
    e.receive(FRAME, &e.main, "10").await;
    let (status, t) = post(&e.app, STORES, "/inventory/transfers", json!({ "id": uid(), "product_id": FRAME, "from_location_id": e.main, "to_location_id": van_loc, "quantity": "4", "reason": "van_replenishment" })).await;
    assert_eq!(status, StatusCode::CREATED, "{t}");
    assert_eq!(t["reason"], "van_replenishment");
    // Van stock is shown separately and is not available for orders.
    let (_, p) = get(
        &e.app,
        SALES,
        &format!("/inventory/stock/products?product_id={FRAME}"),
    )
    .await;
    assert_eq!(
        (
            dec(&p["items"][0]["on_hand"]),
            dec(&p["items"][0]["in_vans"])
        ),
        (q("6"), q("4"))
    );
    let (_, p) = get(
        &e.app,
        SALES,
        &format!(
            "/inventory/stock/products?product_id={FRAME}&warehouse_id={}",
            van["id"].as_str().unwrap()
        ),
    )
    .await;
    assert_eq!(dec(&p["items"][0]["on_hand"]), q("4"));

    let (status, _) = post(&e.app, STORES, "/inventory/transfers", json!({ "id": uid(), "product_id": FRAME, "from_location_id": van_loc, "to_location_id": e.main, "quantity": "5" })).await;
    assert_eq!(status, StatusCode::CONFLICT, "the van has 4");
    let (status, _) = post(&e.app, STORES, "/inventory/transfers", json!({ "id": uid(), "product_id": FRAME, "from_location_id": e.main, "to_location_id": e.main, "quantity": "1" })).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    let (status, _) = post(&e.app, STORES, "/inventory/transfers", json!({ "id": uid(), "product_id": FRAME, "from_location_id": e.main, "to_location_id": van_loc, "quantity": "1", "reason": "gift" })).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    // Sales may look, not move.
    let (status, _) = post(&e.app, SALES, "/inventory/transfers", json!({ "id": uid(), "product_id": FRAME, "from_location_id": e.main, "to_location_id": van_loc, "quantity": "1" })).await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    e.integrity_ok().await;
}

// ---------------------------------------------------------------------------------------------
// Adjustments and counts
// ---------------------------------------------------------------------------------------------

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn adjustments_set_or_change_the_quantity_with_a_reason(db: PgPool) {
    let e = env(db).await;
    e.receive(FRAME, &e.main, "10").await;
    let id = uid();
    let body = json!({ "id": id, "product_id": FRAME, "location_id": e.main, "new_quantity": "8", "note": "broken in transit" });
    let (status, m) = post(&e.app, ADMIN, "/inventory/adjustments", body.clone()).await;
    assert_eq!(status, StatusCode::CREATED, "{m}");
    assert_eq!(
        (m["kind"].as_str(), m["to_location"].as_str()),
        (Some("adjustment"), Some("adjustment"))
    );
    assert_eq!(dec(&m["quantity"]), q("2"));
    // The retry returns the same move although the stock is now already 8.
    let (status, again) = post(&e.app, ADMIN, "/inventory/adjustments", body).await;
    assert_eq!(
        (status, again["id"].clone()),
        (StatusCode::OK, m["id"].clone())
    );
    assert_eq!(e.totals(FRAME).await.0, q("8"));
    let (status, m) = post(&e.app, ADMIN, "/inventory/adjustments", json!({ "id": uid(), "product_id": FRAME, "location_id": e.main, "delta": "1.5", "note": "found" })).await;
    assert_eq!(status, StatusCode::CREATED, "{m}");
    assert_eq!(m["from_location"], "adjustment");
    assert_eq!(e.totals(FRAME).await.0, q("9.5"));
    for body in [
        json!({ "id": uid(), "product_id": FRAME, "location_id": e.main, "new_quantity": "9.5", "note": "same" }),
        json!({ "id": uid(), "product_id": FRAME, "location_id": e.main, "new_quantity": "1", "delta": "1", "note": "both" }),
        json!({ "id": uid(), "product_id": FRAME, "location_id": e.main, "delta": "1", "note": " " }),
        json!({ "id": uid(), "product_id": FRAME, "location_id": e.main, "delta": "-20", "note": "too much" }),
        json!({ "id": uid(), "product_id": PUMP, "location_id": e.main, "delta": "1", "note": "serial" }),
    ] {
        let (status, r) = post(&e.app, ADMIN, "/inventory/adjustments", body.clone()).await;
        assert!(
            status == StatusCode::UNPROCESSABLE_ENTITY || status == StatusCode::CONFLICT,
            "{body} -> {status} {r}"
        );
    }
    let (status, _) = post(&e.app, STORES, "/inventory/adjustments", json!({ "id": uid(), "product_id": FRAME, "location_id": e.main, "delta": "1", "note": "x" })).await;
    assert_eq!(
        status,
        StatusCode::FORBIDDEN,
        "adjustments need inventory.admin"
    );
    e.integrity_ok().await;
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_count_posts_the_difference_between_counted_and_current_stock(db: PgPool) {
    let e = env(db).await;
    let shelf = e.location("A-01").await;
    e.receive(FRAME, &e.main, "10").await;
    e.receive(BOLT, &shelf, "100").await;
    e.receive(PROFILE, &e.main, "20").await;
    let (status, c) = post(
        &e.app,
        STORES,
        "/inventory/counts",
        json!({ "warehouse_id": e.wh, "note": "year end" }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{c}");
    let cid = c["count"]["id"].as_str().unwrap().to_string();
    assert!(
        c["count"]["number"].as_str().unwrap().starts_with("CNT-"),
        "{c}"
    );
    assert_eq!(c["lines"].as_array().unwrap().len(), 3);
    let line_of = |code: &str| {
        c["lines"]
            .as_array()
            .unwrap()
            .iter()
            .find(|l| l["product_code"] == code)
            .unwrap()["id"]
            .as_str()
            .unwrap()
            .to_string()
    };
    let (frame, bolt) = (line_of("FRAME-A"), line_of("BOLT-M8"));

    // Stock moves while counting: the count compares with the stock at posting time.
    e.issue(FRAME, &e.main, "1").await;
    let (status, d) = api(
        &e.app,
        STORES,
        Method::PUT,
        &format!("/inventory/counts/{cid}/lines"),
        Some(json!({ "entries": [
            { "line_id": frame, "counted_quantity": "7" },
            { "line_id": bolt, "counted_quantity": "100" },
            { "product_id": PUMP, "location_id": e.main, "counted_quantity": "1" },
        ] })),
    )
    .await;
    assert_eq!(
        status,
        StatusCode::UNPROCESSABLE_ENTITY,
        "serial products are not counted: {d}"
    );
    // Stock that was not expected can be added as a line.
    let (status, d) = api(
        &e.app,
        STORES,
        Method::PUT,
        &format!("/inventory/counts/{cid}/lines"),
        Some(json!({ "entries": [
        { "line_id": frame, "counted_quantity": "7" },
        { "line_id": bolt, "counted_quantity": "100" },
        { "product_id": FRAME, "location_id": shelf, "counted_quantity": "2" },
    ] })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{d}");
    assert_eq!(d["lines"].as_array().unwrap().len(), 4);
    assert_eq!(d["count"]["counted_count"], 3);

    // The warehouse team counts; the admin posts.
    let (status, _) = post(
        &e.app,
        STORES,
        &format!("/inventory/counts/{cid}/post"),
        json!({}),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, d) = post(
        &e.app,
        ADMIN,
        &format!("/inventory/counts/{cid}/post"),
        json!({}),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{d}");
    assert_eq!(d["count"]["status"], "posted");
    // FRAME: 9 on hand at posting, counted 7 -> -2; shelf found 2 -> +2; BOLT unchanged; profile not counted.
    let (_, rows) = get(
        &e.app,
        ADMIN,
        &format!("/inventory/stock?product_id={FRAME}"),
    )
    .await;
    let on_hand: Vec<Decimal> = rows["items"]
        .as_array()
        .unwrap()
        .iter()
        .map(|r| dec(&r["on_hand"]))
        .collect();
    assert_eq!(on_hand, vec![q("2"), q("7")]);
    assert_eq!(e.totals(BOLT).await.0, q("100"));
    assert_eq!(e.totals(PROFILE).await.0, q("20"));
    let (_, h) = get(
        &e.app,
        ADMIN,
        &format!("/inventory/moves?reference_type=stock_count&reference_id={cid}"),
    )
    .await;
    assert_eq!(h["total"], 2, "only differences become moves");
    assert!(h["items"]
        .as_array()
        .unwrap()
        .iter()
        .all(|m| m["reason"] == "count" && m["kind"] == "adjustment"));
    let posted_lines = d["lines"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|l| !l["adjustment_move_id"].is_null())
        .count();
    assert_eq!(posted_lines, 2);

    // A posted count is closed.
    let (status, _) = post(
        &e.app,
        ADMIN,
        &format!("/inventory/counts/{cid}/post"),
        json!({}),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
    let (status, _) = api(
        &e.app,
        STORES,
        Method::PUT,
        &format!("/inventory/counts/{cid}/lines"),
        Some(json!({ "entries": [] })),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
    let (status, _) = post(
        &e.app,
        STORES,
        &format!("/inventory/counts/{cid}/cancel"),
        json!({}),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);

    // A cancelled count posts nothing.
    let (_, c2) = post(
        &e.app,
        STORES,
        "/inventory/counts",
        json!({ "warehouse_id": e.wh, "product_id": FRAME }),
    )
    .await;
    let c2id = c2["count"]["id"].as_str().unwrap();
    assert_ne!(c2["count"]["number"], c["count"]["number"]);
    let (status, d) = post(
        &e.app,
        STORES,
        &format!("/inventory/counts/{c2id}/cancel"),
        json!({}),
    )
    .await;
    assert_eq!(
        (status, d["count"]["status"].as_str()),
        (StatusCode::OK, Some("cancelled"))
    );
    let (_, list) = get(&e.app, SALES, "/inventory/counts?status=posted").await;
    assert_eq!(list["items"].as_array().unwrap().len(), 1);
    assert_eq!(list["total"], 1);
    e.integrity_ok().await;
}

// ---------------------------------------------------------------------------------------------
// Serial units
// ---------------------------------------------------------------------------------------------

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn serial_units_keep_their_status_consistent_with_the_moves(db: PgPool) {
    let e = env(db).await;
    // Receiving registers the unit; the ledger puts it at the location.
    let (status, m) = post(&e.app, STORES, "/inventory/receipts", json!({ "id": uid(), "product_id": PUMP, "location_id": e.main, "quantity": "1", "serial_number": "P-NEW-1" })).await;
    assert_eq!(status, StatusCode::CREATED, "{m}");
    let unit = m["serial_unit_id"].as_str().unwrap().to_string();
    assert_eq!(m["serial_number"], "P-NEW-1");
    assert_eq!(e.totals(PUMP).await.0, q("1"));
    let (_, d) = get(&e.app, ADMIN, &format!("/serials/{unit}")).await;
    assert_eq!(d["unit"]["status"], "in_stock");

    for (body, expect) in [
        (
            json!({ "id": uid(), "product_id": PUMP, "location_id": e.main, "quantity": "2", "serial_number": "P-NEW-2" }),
            StatusCode::UNPROCESSABLE_ENTITY,
        ),
        (
            json!({ "id": uid(), "product_id": PUMP, "location_id": e.main, "quantity": "1" }),
            StatusCode::UNPROCESSABLE_ENTITY,
        ),
        (
            json!({ "id": uid(), "product_id": PUMP, "location_id": e.main, "quantity": "1", "serial_number": "P-NEW-1" }),
            StatusCode::CONFLICT,
        ),
    ] {
        let (status, r) = post(&e.app, STORES, "/inventory/receipts", body).await;
        assert_eq!(status, expect, "{r}");
    }

    // While it has a location, engineering cannot change its status or build it into a unit.
    let (status, r) = api(
        &e.app,
        ADMIN,
        Method::PUT,
        &format!("/serials/{unit}/status"),
        Some(json!({ "status": "scrapped" })),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT, "{r}");
    let (status, r) = post(
        &e.app,
        ADMIN,
        "/serials/00000000-0000-7000-8000-000000000601/components",
        json!({ "child_id": unit }),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT, "{r}");

    // Shipping needs a customer, then the unit is delivered and leaves the stock.
    let ship = json!({ "id": uid(), "product_id": PUMP, "location_id": e.main, "quantity": "1", "serial_unit_id": unit, "reason": "shipment" });
    let (status, _) = post(&e.app, STORES, "/inventory/issues", ship.clone()).await;
    assert_eq!(
        status,
        StatusCode::UNPROCESSABLE_ENTITY,
        "customer required"
    );
    let mut with_customer = ship.clone();
    with_customer["customer_id"] = json!(ALPHA);
    let (status, shipped) = post(&e.app, STORES, "/inventory/issues", with_customer).await;
    assert_eq!(status, StatusCode::CREATED, "{shipped}");
    assert_eq!(e.totals(PUMP).await.0, q("0"));
    let (_, d) = get(&e.app, ADMIN, &format!("/serials/{unit}")).await;
    assert_eq!(
        (
            d["unit"]["status"].as_str(),
            d["unit"]["customer_id"].as_str()
        ),
        (Some("delivered"), Some(ALPHA))
    );
    let (status, _) = post(&e.app, STORES, "/inventory/issues", json!({ "id": uid(), "product_id": PUMP, "location_id": e.main, "quantity": "1", "serial_unit_id": unit, "reason": "scrap" })).await;
    assert_eq!(
        status,
        StatusCode::CONFLICT,
        "a delivered unit is not in stock"
    );

    // Reversing the shipment puts it back in stock at the same location.
    let sid = shipped["id"].as_str().unwrap();
    let (status, r) = post(
        &e.app,
        ADMIN,
        &format!("/inventory/moves/{sid}/reverse"),
        json!({ "id": uid() }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{r}");
    let (_, d) = get(&e.app, ADMIN, &format!("/serials/{unit}")).await;
    assert_eq!(
        (
            d["unit"]["status"].as_str(),
            d["unit"]["customer_id"].is_null()
        ),
        (Some("in_stock"), true)
    );
    assert_eq!(e.totals(PUMP).await.0, q("1"));

    // Consumption takes it out of stock without a status change; now it can be built in (ADR 0011).
    let (status, _) = post(&e.app, STORES, "/inventory/issues", json!({ "id": uid(), "product_id": PUMP, "location_id": e.main, "quantity": "1", "serial_unit_id": unit, "reason": "consumption" })).await;
    assert_eq!(status, StatusCode::CREATED);
    assert_eq!(e.totals(PUMP).await.0, q("0"));
    let (_, d) = get(&e.app, ADMIN, &format!("/serials/{unit}")).await;
    assert_eq!(d["unit"]["status"], "in_stock");
    // Scrapping another unit.
    let (_, m2) = post(&e.app, STORES, "/inventory/receipts", json!({ "id": uid(), "product_id": CTRL, "location_id": e.main, "quantity": "1", "serial_number": "C-NEW-1" })).await;
    let u2 = m2["serial_unit_id"].as_str().unwrap();
    let (status, _) = post(&e.app, STORES, "/inventory/issues", json!({ "id": uid(), "product_id": CTRL, "location_id": e.main, "quantity": "1", "serial_unit_id": u2, "reason": "scrap" })).await;
    assert_eq!(status, StatusCode::CREATED);
    let (_, d) = get(&e.app, ADMIN, &format!("/serials/{u2}")).await;
    assert_eq!(d["unit"]["status"], "scrapped");
    // Another product's unit cannot be moved as this one.
    let (status, _) = post(&e.app, STORES, "/inventory/transfers", json!({ "id": uid(), "product_id": CTRL, "from_location_id": e.main, "to_location_id": e.main, "quantity": "1", "serial_unit_id": unit })).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    e.integrity_ok().await;

    // A seed unit registered before inventory is in stock without a location; it can be received.
    let (status, m) = post(&e.app, STORES, "/inventory/receipts", json!({ "id": uid(), "product_id": PUMP, "location_id": e.main, "quantity": "1", "serial_unit_id": "00000000-0000-7000-8000-000000000605" })).await;
    assert_eq!(status, StatusCode::CREATED, "{m}");
    // A unit built into another one cannot be received.
    let (status, _) = post(&e.app, STORES, "/inventory/receipts", json!({ "id": uid(), "product_id": PUMP, "location_id": e.main, "quantity": "1", "serial_unit_id": "00000000-0000-7000-8000-000000000602" })).await;
    assert_eq!(status, StatusCode::CONFLICT);
    // And the finished unit can be tracked the same way.
    let (status, _) = post(&e.app, STORES, "/inventory/receipts", json!({ "id": uid(), "product_id": UNIT_100, "location_id": e.main, "quantity": "1", "serial_unit_id": "00000000-0000-7000-8000-000000000601" })).await;
    assert_eq!(status, StatusCode::CREATED);
    e.integrity_ok().await;
}

// ---------------------------------------------------------------------------------------------
// Reservations and availability
// ---------------------------------------------------------------------------------------------

async fn order_with(app: &axum::Router, product: &str, quantity: &str) -> (String, String) {
    let (status, qn) = api(app, SALES, Method::POST, "/quotations", Some(json!({ "customer_id": ALPHA, "lines": [{ "product_id": product, "quantity": quantity }] }))).await;
    assert_eq!(status, StatusCode::CREATED, "{qn}");
    let qid = qn["id"].as_str().unwrap();
    api(
        app,
        SALES,
        Method::POST,
        &format!("/quotations/{qid}/send"),
        None,
    )
    .await;
    let (status, o) = api(
        app,
        SALES,
        Method::POST,
        &format!("/quotations/{qid}/convert"),
        Some(json!({ "customer_reference": "PO" })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{o}");
    (
        o["order"]["id"].as_str().unwrap().into(),
        o["lines"][0]["id"].as_str().unwrap().into(),
    )
}

async fn confirm(app: &axum::Router, order: &str) {
    let (status, o) = api(
        app,
        SALES,
        Method::POST,
        &format!("/orders/{order}/send"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{o}");
    let (status, o) = api(
        app,
        SALES,
        Method::POST,
        &format!("/orders/{order}/confirm"),
        Some(json!({})),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{o}");
}

async fn reserve(app: &axum::Router, line: &str, quantity: &str) -> (StatusCode, Value) {
    api(
        app,
        STORES,
        Method::PUT,
        &format!("/inventory/order-lines/{line}/reservation"),
        Some(json!({ "quantity": quantity })),
    )
    .await
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn reserving_stock_for_a_confirmed_order_reduces_what_is_available(db: PgPool) {
    let e = env(db).await;
    e.receive(FRAME, &e.main, "8").await;
    let (order, line) = order_with(&e.app, FRAME, "5").await;

    // Before confirmation: availability is shown, but nothing can be reserved.
    let (_, a) = get(
        &e.app,
        SALES,
        &format!("/inventory/orders/{order}/availability"),
    )
    .await;
    assert_eq!(a["reservable"], false);
    assert_eq!(
        (
            dec(&a["lines"][0]["on_hand"]),
            dec(&a["lines"][0]["available"]),
            a["lines"][0]["state"].as_str()
        ),
        (q("8"), q("8"), Some("available"))
    );
    let (status, r) = reserve(&e.app, &line, "5").await;
    assert_eq!(status, StatusCode::CONFLICT, "{r}");

    confirm(&e.app, &order).await;
    let (status, r) = reserve(&e.app, &line, "5").await;
    assert_eq!(status, StatusCode::OK, "{r}");
    assert_eq!(dec(&r["reserved"]), q("5"));
    assert_eq!(e.totals(FRAME).await, (q("8"), q("5"), q("3")));
    // Doing it again changes nothing.
    let (_, r2) = reserve(&e.app, &line, "5").await;
    assert_eq!(dec(&r2["reserved"]), q("5"));
    assert_eq!(r2["allocations"].as_array().unwrap().len(), 1);
    let (_, a) = get(
        &e.app,
        SALES,
        &format!("/inventory/orders/{order}/availability"),
    )
    .await;
    assert_eq!(a["reservable"], true);
    assert_eq!(
        (
            dec(&a["lines"][0]["reserved"]),
            dec(&a["lines"][0]["available"]),
            a["lines"][0]["state"].as_str()
        ),
        (q("5"), q("3"), Some("reserved"))
    );
    // Stock overview per location shows reserved and available too.
    let (_, rows) = get(
        &e.app,
        SALES,
        &format!("/inventory/stock?product_id={FRAME}"),
    )
    .await;
    assert_eq!(
        (
            dec(&rows["items"][0]["reserved"]),
            dec(&rows["items"][0]["available"])
        ),
        (q("5"), q("3"))
    );

    // More than the line asks for, and more than is free, are refused.
    let (status, _) = reserve(&e.app, &line, "6").await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    let (order2, line2) = order_with(&e.app, FRAME, "5").await;
    confirm(&e.app, &order2).await;
    let (status, r) = reserve(&e.app, &line2, "5").await;
    assert_eq!(status, StatusCode::CONFLICT, "only 3 are free: {r}");
    assert!(r["message"].as_str().unwrap().contains("only 3"), "{r}");
    let (_, a2) = get(
        &e.app,
        SALES,
        &format!("/inventory/orders/{order2}/availability"),
    )
    .await;
    assert_eq!(
        (
            dec(&a2["lines"][0]["shortfall"]),
            a2["lines"][0]["state"].as_str()
        ),
        (q("2"), Some("partial"))
    );
    let (status, r) = reserve(&e.app, &line2, "3").await;
    assert_eq!(status, StatusCode::OK, "{r}");
    let (_, a2) = get(
        &e.app,
        SALES,
        &format!("/inventory/orders/{order2}/availability"),
    )
    .await;
    assert_eq!(
        (
            dec(&a2["lines"][0]["shortfall"]),
            dec(&a2["lines"][0]["available"])
        ),
        (q("2"), q("0"))
    );
    let (_, list) = get(
        &e.app,
        SALES,
        &format!("/inventory/reservations?product_id={FRAME}"),
    )
    .await;
    assert_eq!(list.as_array().unwrap().len(), 2);

    // Reserved stock cannot be issued or transferred away.
    let (status, r) = e.issue(FRAME, &e.main, "1").await;
    assert_eq!(status, StatusCode::CONFLICT, "everything is reserved: {r}");
    assert!(r["message"].as_str().unwrap().contains("reserved"), "{r}");
    let (status, _) = post(&e.app, STORES, "/inventory/transfers", json!({ "id": uid(), "product_id": FRAME, "from_location_id": e.main, "to_location_id": e.location("B-01").await, "quantity": "1" })).await;
    assert_eq!(status, StatusCode::CONFLICT);

    // Lowering the reservation frees stock again; partial release keeps the rest.
    let (_, r) = reserve(&e.app, &line, "2").await;
    assert_eq!(dec(&r["reserved"]), q("2"));
    assert_eq!(e.totals(FRAME).await, (q("8"), q("5"), q("3")));
    let (status, _) = e.issue(FRAME, &e.main, "3").await;
    assert_eq!(status, StatusCode::CREATED);
    // Cancelling the order releases its reservations.
    let (status, o) = api(
        &e.app,
        SALES,
        Method::POST,
        &format!("/orders/{order2}/cancel"),
        Some(json!({ "reason": "customer withdrew" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{o}");
    assert_eq!(e.totals(FRAME).await, (q("5"), q("2"), q("3")));
    // Releasing all.
    let (_, r) = reserve(&e.app, &line, "0").await;
    assert_eq!(dec(&r["reserved"]), q("0"));
    assert_eq!(e.totals(FRAME).await, (q("5"), q("0"), q("5")));
    // A cancelled order cannot be reserved for, and the lifecycle is untouched by all this.
    let (status, _) = reserve(&e.app, &line2, "1").await;
    assert_eq!(status, StatusCode::CONFLICT);
    let (_, o) = api(
        &e.app,
        SALES,
        Method::GET,
        &format!("/orders/{order}"),
        None,
    )
    .await;
    assert_eq!(o["order"]["status"], "confirmed");
    e.integrity_ok().await;
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn reservations_take_lots_with_the_earliest_expiry_first_and_skip_vans(db: PgPool) {
    let e = env(db).await;
    make_lot_tracked(&e.db, BOLT).await;
    let shelf = e.location("A-01").await;
    for (lot, loc, qty, exp) in [
        ("LATE", &e.main, "10", "2027-06-01"),
        ("EARLY", &shelf, "4", "2026-12-31"),
    ] {
        let (s, r) = post(&e.app, STORES, "/inventory/receipts", json!({ "id": uid(), "product_id": BOLT, "location_id": loc, "quantity": qty, "lot_number": lot, "expiry_date": exp })).await;
        assert_eq!(s, StatusCode::CREATED, "{r}");
    }
    let (_, van) = post(
        &e.app,
        ADMIN,
        "/inventory/warehouses",
        json!({ "code": "VAN-1", "name": "Van", "kind": "van" }),
    )
    .await;
    post(&e.app, STORES, "/inventory/receipts", json!({ "id": uid(), "product_id": BOLT, "location_id": van["locations"][0]["id"], "quantity": "50", "lot_number": "VANLOT" })).await;
    let (order, line) = order_with(&e.app, BOLT, "6").await;
    confirm(&e.app, &order).await;
    let (status, r) = reserve(&e.app, &line, "6").await;
    assert_eq!(status, StatusCode::OK, "{r}");
    let allocs: Vec<(String, Decimal)> = r["allocations"]
        .as_array()
        .unwrap()
        .iter()
        .map(|a| {
            (
                a["lot_number"].as_str().unwrap().to_string(),
                dec(&a["quantity"]),
            )
        })
        .collect();
    assert_eq!(
        allocs,
        vec![("EARLY".to_string(), q("4")), ("LATE".to_string(), q("2"))]
    );
    // The van's 50 are not available for orders.
    assert_eq!(e.totals(BOLT).await, (q("14"), q("6"), q("8")));
    let (_, rows) = get(
        &e.app,
        SALES,
        &format!("/inventory/stock?product_id={BOLT}&warehouse_id={}", e.wh),
    )
    .await;
    let reserved: Vec<(String, Decimal)> = rows["items"]
        .as_array()
        .unwrap()
        .iter()
        .map(|r| {
            (
                r["lot_number"].as_str().unwrap().to_string(),
                dec(&r["reserved"]),
            )
        })
        .collect();
    assert_eq!(
        reserved,
        vec![("EARLY".to_string(), q("4")), ("LATE".to_string(), q("2"))]
    );
    // Lowering releases the newest allocation first.
    let (_, r) = reserve(&e.app, &line, "4").await;
    assert_eq!(r["allocations"].as_array().unwrap().len(), 1);
    assert_eq!(r["allocations"][0]["lot_number"], "EARLY");
    e.integrity_ok().await;
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn services_and_lines_without_stock_are_reported_as_not_stocked(db: PgPool) {
    let e = env(db).await;
    let (order, line) = order_with(&e.app, SERVICE, "2").await;
    confirm(&e.app, &order).await;
    let (_, a) = get(
        &e.app,
        SALES,
        &format!("/inventory/orders/{order}/availability"),
    )
    .await;
    assert_eq!(a["lines"][0]["state"], "not_stocked");
    let (status, _) = reserve(&e.app, &line, "1").await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    let (status, _) = get(
        &e.app,
        SALES,
        &format!("/inventory/orders/{}/availability", uid()),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

// ---------------------------------------------------------------------------------------------
// Permissions, cost and company isolation
// ---------------------------------------------------------------------------------------------

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn cost_is_only_visible_to_roles_with_the_cost_permission(db: PgPool) {
    let e = env(db).await;
    let (_, p) = get(&e.app, PM, &format!("/products/{FRAME}")).await;
    let mut input = p.clone();
    input["standard_cost"] = json!("812.5");
    input["reorder_min"] = json!("4");
    input["reorder_max"] = json!("12");
    input["lead_time_days"] = json!(14);
    input["barcode"] = json!("5412345678901");
    let (status, saved) = api(
        &e.app,
        PM,
        Method::PUT,
        &format!("/products/{FRAME}"),
        Some(input.clone()),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{saved}");
    assert_eq!(dec(&saved["standard_cost"]), q("812.5"));
    assert_eq!(saved["barcode"], "5412345678901");
    // Sales sees the product, not the cost.
    let (_, seen) = get(&e.app, SALES, &format!("/products/{FRAME}")).await;
    assert!(seen["standard_cost"].is_null(), "{seen}");
    assert_eq!(
        (dec(&seen["reorder_min"]), seen["lead_time_days"].as_i64()),
        (q("4"), Some(14))
    );
    let (_, list) = get(&e.app, SALES, "/products?q=FRAME").await;
    assert!(list["items"][0]["standard_cost"].is_null());
    // Saving the product without the permission keeps the stored cost, and cannot set one.
    let mut by_admin_less = seen.clone();
    by_admin_less["standard_cost"] = json!("1");
    let (status, _) = api(
        &e.app,
        ADMIN,
        Method::PUT,
        &format!("/products/{FRAME}"),
        Some(by_admin_less.clone()),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (_, back) = get(&e.app, PM, &format!("/products/{FRAME}")).await;
    assert_eq!(
        dec(&back["standard_cost"]),
        q("1"),
        "admin holds the permission"
    );
    let (_, pm_bolt) = get(&e.app, PM, &format!("/products/{BOLT}")).await;
    assert!(pm_bolt["standard_cost"].is_null());
    let mut forged = seen.clone();
    forged["standard_cost"] = json!("0.01");
    let (status, _) = api(
        &e.app,
        SALES,
        Method::PUT,
        &format!("/products/{FRAME}"),
        Some(forged),
    )
    .await;
    assert_eq!(
        status,
        StatusCode::FORBIDDEN,
        "sales may not edit products at all"
    );

    // The cost at the time of a move is kept and equally hidden.
    api(
        &e.app,
        ADMIN,
        Method::PUT,
        &format!("/products/{FRAME}"),
        Some({
            let mut i = back.clone();
            i["standard_cost"] = json!("812.5");
            i
        }),
    )
    .await;
    let (_, m) = post(
        &e.app,
        ADMIN,
        "/inventory/receipts",
        json!({ "id": uid(), "product_id": FRAME, "location_id": e.main, "quantity": "1" }),
    )
    .await;
    assert_eq!(dec(&m["unit_cost"]), q("812.5"));
    let (_, h) = get(
        &e.app,
        SALES,
        &format!("/inventory/moves?product_id={FRAME}"),
    )
    .await;
    assert!(h["items"][0]["unit_cost"].is_null());
    let (_, h) = get(&e.app, PM, &format!("/inventory/moves?product_id={FRAME}")).await;
    assert_eq!(dec(&h["items"][0]["unit_cost"]), q("812.5"));
    // Barcodes are unique; negative values and a max below the min are refused.
    let mut dup = pm_bolt.clone();
    dup["barcode"] = json!("5412345678901");
    let (status, _) = api(
        &e.app,
        PM,
        Method::PUT,
        &format!("/products/{BOLT}"),
        Some(dup),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
    let mut bad = pm_bolt.clone();
    bad["reorder_min"] = json!("5");
    bad["reorder_max"] = json!("2");
    let (status, _) = api(
        &e.app,
        PM,
        Method::PUT,
        &format!("/products/{BOLT}"),
        Some(bad),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_product_with_stock_moves_cannot_become_a_service(db: PgPool) {
    let e = env(db).await;
    let (_, p) = get(&e.app, PM, &format!("/products/{FRAME}")).await;
    let mut input = p.clone();
    input["product_type"] = json!("service");
    // Once a receipt exists, the product can no longer become a service.
    e.receive(FRAME, &e.main, "3").await;
    let (status, body) = api(
        &e.app,
        PM,
        Method::PUT,
        &format!("/products/{FRAME}"),
        Some(input),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT, "{body}");
    let (_, after) = get(&e.app, PM, &format!("/products/{FRAME}")).await;
    assert_eq!(after["product_type"], p["product_type"]);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn stock_moves_of_another_company_also_block_the_conversion(db: PgPool) {
    let e = env(db).await;
    let other = second_company(&e.db).await;
    // The move belongs to the first company; the user changing the product to another one.
    e.receive(FRAME, &e.main, "3").await;
    let (_, p) = get(&e.app, "other@example.com", &format!("/products/{FRAME}")).await;
    let mut input = p.clone();
    input["product_type"] = json!("service");
    let (status, body) = api(
        &e.app,
        "other@example.com",
        Method::PUT,
        &format!("/products/{FRAME}"),
        Some(input),
    )
    .await;
    let _ = other;
    assert_eq!(status, StatusCode::CONFLICT, "{body}");
    let (_, after) = get(&e.app, PM, &format!("/products/{FRAME}")).await;
    assert_eq!(after["product_type"], p["product_type"]);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn an_existing_service_with_old_moves_can_still_be_edited(db: PgPool) {
    let e = env(db).await;
    e.receive(FRAME, &e.main, "3").await;
    // Made a service behind the API's back, as data from before the guard may be.
    sqlx::query("UPDATE products.products SET product_type = 'service', tracking = 'none' WHERE id = $1::uuid")
        .bind(FRAME)
        .execute(&e.db)
        .await
        .unwrap();
    let (_, p) = get(&e.app, PM, &format!("/products/{FRAME}")).await;
    assert_eq!(p["product_type"], "service");
    let mut input = p.clone();
    input["name"] = json!("Renamed service");
    let (status, body) = api(
        &e.app,
        PM,
        Method::PUT,
        &format!("/products/{FRAME}"),
        Some(input),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body["name"], "Renamed service");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_conversion_waits_for_a_posting_in_flight_and_then_sees_its_move(db: PgPool) {
    let e = env(db).await;
    let other_loc = e.location("B").await;
    let (_, p) = get(&e.app, PM, &format!("/products/{FRAME}")).await;
    // A posting holds the product row FOR SHARE and inserts its move, not yet committed.
    let mut tx = e.db.begin().await.unwrap();
    sqlx::query("SELECT 1 FROM products.products WHERE id = $1::uuid FOR SHARE")
        .bind(FRAME)
        .execute(&mut *tx)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO inventory.stock_moves (id, company_id, product_id, quantity, from_location_id,
            to_location_id, kind, reason, created_by)
         VALUES ($1, $2::uuid, $3::uuid, 1, $4::uuid, $5::uuid, 'transfer', 'test',
                 (SELECT id FROM core.users LIMIT 1))",
    )
    .bind(Uuid::now_v7())
    .bind(COMPANY)
    .bind(FRAME)
    .bind(&e.main)
    .bind(&other_loc)
    .execute(&mut *tx)
    .await
    .unwrap();
    let mut input = p.clone();
    input["product_type"] = json!("service");
    let (app, uri) = (e.app.clone(), format!("/products/{FRAME}"));
    let mut update =
        tokio::spawn(async move { api(&app, PM, Method::PUT, &uri, Some(input)).await });
    // The update cannot get past the row lock while the posting is open.
    let early = tokio::time::timeout(std::time::Duration::from_millis(500), &mut update).await;
    assert!(early.is_err(), "the update should be waiting");
    tx.commit().await.unwrap();
    let (status, body) = update.await.unwrap();
    assert_eq!(status, StatusCode::CONFLICT, "{body}");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn reorder_levels_flag_products_below_their_minimum(db: PgPool) {
    let e = env(db).await;
    let (_, p) = get(&e.app, PM, &format!("/products/{FRAME}")).await;
    let mut input = p.clone();
    input["reorder_min"] = json!("5");
    api(
        &e.app,
        PM,
        Method::PUT,
        &format!("/products/{FRAME}"),
        Some(input),
    )
    .await;
    e.receive(FRAME, &e.main, "6").await;
    let (_, low) = get(
        &e.app,
        SALES,
        "/inventory/stock/products?below_reorder=true",
    )
    .await;
    assert_eq!(low["total"], 0);
    e.issue(FRAME, &e.main, "2").await;
    let (_, low) = get(
        &e.app,
        SALES,
        "/inventory/stock/products?below_reorder=true",
    )
    .await;
    assert_eq!(low["total"], 1);
    assert_eq!(low["items"][0]["below_reorder"], true);
    let (_, held) = get(&e.app, SALES, "/inventory/stock/products?in_stock=true").await;
    assert_eq!(held["total"], 1);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn permissions_separate_reading_moving_and_administering(db: PgPool) {
    let e = env(db).await;
    e.receive(FRAME, &e.main, "5").await;
    for who in [ADMIN, SALES, VIEWER, STORES, PM] {
        let (status, _) = get(&e.app, who, "/inventory/stock").await;
        assert_eq!(status, StatusCode::OK, "{who} reads stock");
    }
    for uri in [
        "/inventory/stock",
        "/inventory/moves",
        "/inventory/warehouses",
        "/inventory/counts",
        "/inventory/integrity",
    ] {
        let (status, _) = get(&e.app, TECH, uri).await;
        assert_eq!(status, StatusCode::FORBIDDEN, "{uri}");
    }
    for who in [SALES, VIEWER, PM] {
        let (status, _) = post(
            &e.app,
            who,
            "/inventory/receipts",
            json!({ "id": uid(), "product_id": FRAME, "location_id": e.main, "quantity": "1" }),
        )
        .await;
        assert_eq!(status, StatusCode::FORBIDDEN, "{who}");
        let (status, _) = post(
            &e.app,
            who,
            "/inventory/counts",
            json!({ "warehouse_id": e.wh }),
        )
        .await;
        assert_eq!(status, StatusCode::FORBIDDEN, "{who}");
    }
    let (status, _) = get(&e.app, STORES, "/inventory/integrity").await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, _) = post(
        &e.app,
        STORES,
        "/inventory/uoms",
        json!({ "code": "box", "name": "Box", "category": "unit", "factor": "1" }),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, u) = post(
        &e.app,
        ADMIN,
        "/inventory/uoms",
        json!({ "code": "dz", "name": "Dozen", "category": "unit", "factor": "12" }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{u}");
    // Nothing was written by the refused calls.
    let n: i64 = sqlx::query_scalar("SELECT count(*) FROM inventory.stock_moves")
        .fetch_one(&e.db)
        .await
        .unwrap();
    assert_eq!(n, 1);
    // The audit trail records configuration and corrections.
    let audited: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM audit.events WHERE entity IN ('warehouse', 'uom')",
    )
    .fetch_one(&e.db)
    .await
    .unwrap();
    assert!(audited >= 2);
}

async fn second_company(db: &PgPool) -> String {
    let company = Uuid::now_v7();
    sqlx::query("INSERT INTO core.companies (id, name, country_code, currency) VALUES ($1, 'Other BV', 'BE', 'EUR')")
        .bind(company)
        .execute(db)
        .await
        .unwrap();
    let id = Uuid::now_v7();
    sqlx::query("INSERT INTO core.users (id, email, display_name) VALUES ($1, 'other@example.com', 'Other')").bind(id).execute(db).await.unwrap();
    sqlx::query("INSERT INTO core.user_companies (user_id, company_id, roles, is_default) VALUES ($1, $2, '{admin}', true)").bind(id).bind(company).execute(db).await.unwrap();
    company.to_string()
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn another_company_sees_and_touches_nothing(db: PgPool) {
    let e = env(db).await;
    let other = second_company(&e.db).await;
    let _ = other;
    let (_, m) = {
        e.receive(FRAME, &e.main, "5").await;
        let (s, m) = post(
            &e.app,
            STORES,
            "/inventory/receipts",
            json!({ "id": uid(), "product_id": FRAME, "location_id": e.main, "quantity": "1" }),
        )
        .await;
        (s, m)
    };
    let (_, ow) = post(
        &e.app,
        "other@example.com",
        "/inventory/warehouses",
        json!({ "code": "WH1", "name": "Their warehouse" }),
    )
    .await;
    let their_loc = ow["locations"][0]["id"].as_str().unwrap().to_string();
    assert_eq!(ow["code"], "WH1", "codes are per company");

    let (_, w) = get(&e.app, "other@example.com", "/inventory/warehouses").await;
    assert_eq!(w.as_array().unwrap().len(), 1);
    let (_, s) = get(&e.app, "other@example.com", "/inventory/stock").await;
    assert_eq!(s["total"], 0);
    let (_, h) = get(&e.app, "other@example.com", "/inventory/moves").await;
    assert_eq!(h["total"], 0);
    let mid = m["id"].as_str().unwrap();
    let (status, _) = get(
        &e.app,
        "other@example.com",
        &format!("/inventory/moves/{mid}"),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    // Our locations are not theirs to receive into, nor can they reuse our move ids.
    let (status, _) = post(
        &e.app,
        "other@example.com",
        "/inventory/receipts",
        json!({ "id": uid(), "product_id": FRAME, "location_id": e.main, "quantity": "1" }),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, _) = post(
        &e.app,
        "other@example.com",
        "/inventory/receipts",
        json!({ "id": mid, "product_id": FRAME, "location_id": their_loc, "quantity": "1" }),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
    let (status, _) = post(
        &e.app,
        "other@example.com",
        &format!("/inventory/moves/{mid}/reverse"),
        json!({ "id": uid() }),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    // Locations cannot be moved between companies either.
    let (status, _) = post(&e.app, "other@example.com", "/inventory/transfers", json!({ "id": uid(), "product_id": FRAME, "from_location_id": e.main, "to_location_id": their_loc, "quantity": "1" })).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, _) = api(
        &e.app,
        "other@example.com",
        Method::PUT,
        &format!("/inventory/warehouses/{}", e.wh),
        Some(json!({ "code": "X", "name": "x" })),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, _) = post(
        &e.app,
        "other@example.com",
        "/inventory/counts",
        json!({ "warehouse_id": e.wh }),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    // An order line of ours cannot be reserved for by them.
    let (_, line) = order_with(&e.app, FRAME, "1").await;
    let (status, _) = api(
        &e.app,
        "other@example.com",
        Method::PUT,
        &format!("/inventory/order-lines/{line}/reservation"),
        Some(json!({ "quantity": "1" })),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    // Their own ledger is independent and consistent.
    let (status, _) = post(
        &e.app,
        "other@example.com",
        "/inventory/receipts",
        json!({ "id": uid(), "product_id": FRAME, "location_id": their_loc, "quantity": "3" }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);
    let (_, i) = get(&e.app, "other@example.com", "/inventory/integrity").await;
    assert_eq!(i["ok"], true);
    assert_eq!(e.totals(FRAME).await.0, q("6"), "ours is unchanged");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn every_inventory_query_filters_on_the_company(_db: PgPool) {
    // A static check, as the roadmap asks: statements in the crate that read a transactional
    // table must mention company_id.
    let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../crates/inventory/src");
    let tables = [
        "stock_moves",
        "stock_balances",
        "reservations",
        "counts",
        "count_lines",
        "lots",
        "warehouses",
        "locations",
    ];
    let mut missing = Vec::new();
    for entry in std::fs::read_dir(dir).unwrap() {
        let path = entry.unwrap().path();
        let text = std::fs::read_to_string(&path).unwrap();
        // String literals that look like SQL. Fragments declared as `const X: &str = "SELECT ..."`
        // are completed by a WHERE clause where they are used, and that literal is checked.
        let mut offset = 0;
        for (i, lit) in text.split('"').enumerate() {
            let start = offset;
            offset += lit.len() + 1;
            if i % 2 == 0 {
                continue;
            }
            let before = &text[start.saturating_sub(70)..start];
            if before.contains("const ") || lit.contains("{filter}") {
                continue;
            }
            let sql = lit.to_lowercase();
            let is_query = sql.contains("select")
                || sql.contains("update inventory.")
                || sql.contains("delete from");
            let touches = tables
                .iter()
                .any(|t| sql.contains(&format!("inventory.{t}")));
            if is_query && touches && !sql.contains("company_id") && !sql.contains("where id = $1")
            {
                missing.push(format!(
                    "{}: {}",
                    path.file_name().unwrap().to_string_lossy(),
                    lit.chars().take(90).collect::<String>()
                ));
            }
        }
    }
    assert!(
        missing.is_empty(),
        "queries without company_id:\n{}",
        missing.join("\n")
    );
}

// ---------------------------------------------------------------------------------------------
// Review fixes: units, consumption, generic references, cost, concurrency, returns, expiry
// ---------------------------------------------------------------------------------------------

fn ok_or_conflict(status: StatusCode) -> bool {
    matches!(
        status,
        StatusCode::OK
            | StatusCode::CREATED
            | StatusCode::CONFLICT
            | StatusCode::UNPROCESSABLE_ENTITY
    )
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn units_of_the_category_unit_never_convert_by_themselves(db: PgPool) {
    let e = env(db).await;
    // "5 set" on a product kept in pieces is refused for receipts and issues, and the message names
    // both units.
    let (status, r) = post(&e.app, STORES, "/inventory/receipts", json!({ "id": uid(), "product_id": FRAME, "location_id": e.main, "quantity": "5", "uom": "set" })).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{r}");
    let message = r["message"].as_str().unwrap();
    assert!(
        message.contains("set") && message.contains("pcs"),
        "{message}"
    );
    e.receive(FRAME, &e.main, "10").await;
    let (status, r) = post(&e.app, STORES, "/inventory/issues", json!({ "id": uid(), "product_id": FRAME, "location_id": e.main, "quantity": "1", "uom": "set" })).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{r}");
    // A unit that was typed into some product (a legacy "box") does not convert either.
    sqlx::query("INSERT INTO inventory.uoms (code, name, category, factor) VALUES ('box', 'box', 'unit', 1)").execute(&e.db).await.unwrap();
    let (status, _) = post(&e.app, STORES, "/inventory/receipts", json!({ "id": uid(), "product_id": FRAME, "location_id": e.main, "quantity": "1", "uom": "box" })).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(e.totals(FRAME).await.0, q("10"), "nothing was booked");

    // Reservations and availability refuse an order line in such a unit instead of guessing.
    let (order, line) = order_with(&e.app, FRAME, "5").await;
    confirm(&e.app, &order).await;
    sqlx::query("UPDATE sales.order_lines SET unit = 'set' WHERE id = $1::uuid")
        .bind(&line)
        .execute(&e.db)
        .await
        .unwrap();
    let (status, r) = reserve(&e.app, &line, "2").await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{r}");
    assert!(r["message"].as_str().unwrap().contains("set"));
    let (status, r) = get(
        &e.app,
        SALES,
        &format!("/inventory/orders/{order}/availability"),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{r}");
    let (status, _) = get(
        &e.app,
        SALES,
        &format!("/inventory/order-lines/{line}/reservation"),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    // With an explicit conversion for the product, a set is 12 pieces.
    let (status, _) = api(
        &e.app,
        ADMIN,
        Method::PUT,
        &format!("/inventory/products/{FRAME}/uoms"),
        Some(json!({ "uoms": [{ "uom_code": "set", "factor": "12" }] })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (status, m) = post(&e.app, STORES, "/inventory/receipts", json!({ "id": uid(), "product_id": FRAME, "location_id": e.main, "quantity": "1", "uom": "set" })).await;
    assert_eq!(status, StatusCode::CREATED, "{m}");
    assert_eq!(dec(&m["quantity"]), q("12"));
    // Measurable categories still convert by their factors.
    let (status, _) = post(&e.app, STORES, "/inventory/receipts", json!({ "id": uid(), "product_id": PROFILE, "location_id": e.main, "quantity": "100", "uom": "cm" })).await;
    assert_eq!(status, StatusCode::CREATED);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn only_one_tracking_check_remains_and_the_new_virtual_kinds_exist(db: PgPool) {
    let e = env(db).await;
    let checks: Vec<String> = sqlx::query_scalar(
        "SELECT pg_get_constraintdef(oid) FROM pg_constraint
         WHERE conrelid = 'products.products'::regclass AND contype = 'c' AND pg_get_constraintdef(oid) LIKE '%tracking%'",
    )
    .fetch_all(&e.db)
    .await
    .unwrap();
    assert_eq!(checks.len(), 1, "{checks:?}");
    assert!(checks[0].contains("lot"), "{checks:?}");
    // transit, production output and production consumption are kinds; the old production is not.
    for kind in ["transit", "production_output", "production_consumption"] {
        sqlx::query("INSERT INTO inventory.locations (id, company_id, kind, code) VALUES (gen_random_uuid(), $1::uuid, $2, $2)")
            .bind(COMPANY).bind(kind).execute(&e.db).await.unwrap_or_else(|err| panic!("{kind}: {err}"));
    }
    let old = sqlx::query("INSERT INTO inventory.locations (id, company_id, kind, code) VALUES (gen_random_uuid(), $1::uuid, 'production', 'production')")
        .bind(COMPANY).execute(&e.db).await;
    assert!(old.is_err());
    // Consumption lands in its own virtual location.
    e.receive(FRAME, &e.main, "3").await;
    let (_, m) = e.issue(FRAME, &e.main, "1").await;
    assert_eq!(m["to_location"], "production_consumption");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn concurrent_issues_cannot_make_a_location_negative(db: PgPool) {
    let e = env(db).await;
    e.receive(FRAME, &e.main, "10").await;
    let mut tasks = Vec::new();
    for _ in 0..8 {
        let (app, main) = (e.app.clone(), e.main.clone());
        tasks.push(tokio::spawn(async move {
            post(
                &app,
                STORES,
                "/inventory/issues",
                json!({ "id": uid(), "product_id": FRAME, "location_id": main, "quantity": "3" }),
            )
            .await
            .0
        }));
    }
    let mut statuses = Vec::new();
    for t in tasks {
        statuses.push(t.await.unwrap());
    }
    assert_eq!(
        statuses
            .iter()
            .filter(|s| **s == StatusCode::CREATED)
            .count(),
        3,
        "{statuses:?}"
    );
    assert!(statuses.iter().all(|s| ok_or_conflict(*s)), "{statuses:?}");
    assert_eq!(e.totals(FRAME).await.0, q("1"));
    let negative: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM inventory.stock_balances WHERE quantity < 0 AND NOT allow_negative",
    )
    .fetch_one(&e.db)
    .await
    .unwrap();
    assert_eq!(negative, 0);
    e.integrity_ok().await;
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn concurrent_set_to_calls_end_with_the_intended_quantity(db: PgPool) {
    let e = env(db).await;
    // No balance row exists at this place yet: both calls must queue up on it.
    let shelf = e.location("A-01").await;
    let mut tasks = Vec::new();
    for _ in 0..4 {
        let (app, shelf) = (e.app.clone(), shelf.clone());
        tasks.push(tokio::spawn(async move {
            post(&app, ADMIN, "/inventory/adjustments", json!({ "id": uid(), "product_id": FRAME, "location_id": shelf, "new_quantity": "5", "note": "found" })).await.0
        }));
    }
    let mut statuses = Vec::new();
    for t in tasks {
        statuses.push(t.await.unwrap());
    }
    assert_eq!(
        statuses
            .iter()
            .filter(|s| **s == StatusCode::CREATED)
            .count(),
        1,
        "{statuses:?}"
    );
    assert_eq!(
        statuses
            .iter()
            .filter(|s| **s == StatusCode::UNPROCESSABLE_ENTITY)
            .count(),
        3,
        "already 5: {statuses:?}"
    );
    assert_eq!(e.totals(FRAME).await.0, q("5"), "not 10 or 20");
    e.integrity_ok().await;

    // The same for a count that is posted twice at once for a place without stock.
    let other = e.location("B-01").await;
    let (_, c) = post(
        &e.app,
        STORES,
        "/inventory/counts",
        json!({ "warehouse_id": e.wh, "location_id": other }),
    )
    .await;
    let cid = c["count"]["id"].as_str().unwrap().to_string();
    let (status, d) = api(&e.app, STORES, Method::PUT, &format!("/inventory/counts/{cid}/lines"), Some(json!({ "entries": [{ "product_id": FRAME, "location_id": other, "counted_quantity": "7" }] }))).await;
    assert_eq!(status, StatusCode::OK, "{d}");
    let mut tasks = Vec::new();
    for _ in 0..3 {
        let (app, cid) = (e.app.clone(), cid.clone());
        tasks.push(tokio::spawn(async move {
            post(
                &app,
                ADMIN,
                &format!("/inventory/counts/{cid}/post"),
                json!({}),
            )
            .await
            .0
        }));
    }
    let mut statuses = Vec::new();
    for t in tasks {
        statuses.push(t.await.unwrap());
    }
    assert_eq!(
        statuses.iter().filter(|s| **s == StatusCode::OK).count(),
        1,
        "{statuses:?}"
    );
    assert_eq!(e.totals(FRAME).await.0, q("12"));
    e.integrity_ok().await;
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_concurrent_retry_with_the_same_id_is_replayed_not_a_primary_key_error(db: PgPool) {
    let e = env(db).await;
    let id = uid();
    let mut tasks = Vec::new();
    for _ in 0..4 {
        let (app, main, id) = (e.app.clone(), e.main.clone(), id.clone());
        tasks.push(tokio::spawn(async move {
            post(
                &app,
                STORES,
                "/inventory/receipts",
                json!({ "id": id, "product_id": FRAME, "location_id": main, "quantity": "2" }),
            )
            .await
        }));
    }
    let mut created = 0;
    for t in tasks {
        let (status, body) = t.await.unwrap();
        assert!(
            status == StatusCode::CREATED || status == StatusCode::OK,
            "{status} {body}"
        );
        created += usize::from(status == StatusCode::CREATED);
        assert_eq!(body["id"], id.as_str());
    }
    assert_eq!(created, 1);
    assert_eq!(e.totals(FRAME).await.0, q("2"));
    // The same id with another note, entered unit or cost is a conflict that names the id.
    for body in [
        json!({ "id": id, "product_id": FRAME, "location_id": e.main, "quantity": "2", "note": "other note" }),
        json!({ "id": id, "product_id": FRAME, "location_id": e.main, "quantity": "2", "unit_cost": "3" }),
    ] {
        let (status, r) = post(&e.app, ADMIN, "/inventory/receipts", body).await;
        assert_eq!(status, StatusCode::CONFLICT, "{r}");
        assert!(r["message"].as_str().unwrap().contains(&id), "{r}");
    }
    e.integrity_ok().await;
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn moves_reservations_and_a_rebuild_running_together_do_not_deadlock_or_corrupt(db: PgPool) {
    let e = env(db).await;
    e.receive(FRAME, &e.main, "50").await;
    let mut orders = Vec::new();
    for _ in 0..3 {
        let (order, line) = order_with(&e.app, FRAME, "5").await;
        confirm(&e.app, &order).await;
        orders.push(line);
    }
    let mut tasks = Vec::new();
    for i in 0..9 {
        let (app, main) = (e.app.clone(), e.main.clone());
        let line = orders[i % 3].clone();
        tasks.push(tokio::spawn(async move {
            match i % 3 {
                0 => post(&app, STORES, "/inventory/receipts", json!({ "id": uid(), "product_id": FRAME, "location_id": main, "quantity": "1" })).await.0,
                1 => api(&app, STORES, Method::PUT, &format!("/inventory/order-lines/{line}/reservation"), Some(json!({ "quantity": "3" }))).await.0,
                _ => post(&app, STORES, "/inventory/issues", json!({ "id": uid(), "product_id": FRAME, "location_id": main, "quantity": "1" })).await.0,
            }
        }));
    }
    let rebuild = {
        let app = e.app.clone();
        tokio::spawn(async move {
            post(&app, ADMIN, "/inventory/balances/rebuild", json!({}))
                .await
                .0
        })
    };
    for t in tasks {
        let status = t.await.unwrap();
        assert!(ok_or_conflict(status), "{status}");
    }
    assert_eq!(rebuild.await.unwrap(), StatusCode::OK);
    e.integrity_ok().await;
}

async fn confirmed_order_with_stock(
    e: &Env,
    product: &str,
    in_stock: &str,
    ordered: &str,
) -> (String, String) {
    e.receive(product, &e.main, in_stock).await;
    let (order, line) = order_with(&e.app, product, ordered).await;
    confirm(&e.app, &order).await;
    (order, line)
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn shipping_the_reserved_stock_consumes_the_reservation(db: PgPool) {
    let e = env(db).await;
    let (_, line_a) = confirmed_order_with_stock(&e, FRAME, "8", "5").await;
    let (order_b, line_b) = order_with(&e.app, FRAME, "3").await;
    confirm(&e.app, &order_b).await;
    assert_eq!(reserve(&e.app, &line_a, "5").await.0, StatusCode::OK);
    assert_eq!(reserve(&e.app, &line_b, "3").await.0, StatusCode::OK);
    assert_eq!(e.totals(FRAME).await, (q("8"), q("8"), q("0")));

    // Without naming the reservation the stock cannot be touched; with it, only its own part.
    let (status, _) = e.issue(FRAME, &e.main, "1").await;
    assert_eq!(status, StatusCode::CONFLICT);
    let ship = |line: &str, quantity: &str| {
        post(
            &e.app,
            STORES,
            "/inventory/issues",
            json!({ "id": uid(), "product_id": FRAME, "location_id": e.main, "quantity": quantity, "reason": "shipment", "consume_reservation_line": line }),
        )
    };
    let (status, m) = ship(&line_a, "2").await;
    assert_eq!(status, StatusCode::CREATED, "{m}");
    assert_eq!(
        (m["reference_type"].as_str(), m["reference_id"].as_str()),
        (Some("sales_order_line"), Some(line_a.as_str()))
    );
    let (_, r) = get(
        &e.app,
        SALES,
        &format!("/inventory/order-lines/{line_a}/reservation"),
    )
    .await;
    assert_eq!(dec(&r["reserved"]), q("3"), "the reservation shrank");
    assert_eq!(e.totals(FRAME).await, (q("6"), q("6"), q("0")));
    // The other order still holds its 3.
    let (_, rb) = get(
        &e.app,
        SALES,
        &format!("/inventory/order-lines/{line_b}/reservation"),
    )
    .await;
    assert_eq!(dec(&rb["reserved"]), q("3"));

    // More than the reservation holds is refused, also when it is the other order's stock.
    let (status, r) = ship(&line_a, "4").await;
    assert_eq!(status, StatusCode::CONFLICT, "{r}");
    assert!(r["message"].as_str().unwrap().contains("holds 3"), "{r}");
    // The rest closes it as consumed.
    let (status, m) = ship(&line_a, "3").await;
    assert_eq!(status, StatusCode::CREATED, "{m}");
    let (status, _) = ship(&line_a, "1").await;
    assert_eq!(status, StatusCode::CONFLICT, "nothing is held any more");
    let row: (String, Decimal, Option<Uuid>) = sqlx::query_as("SELECT status, consumed_quantity, closed_move_id FROM inventory.reservations WHERE reference_id = $1::uuid")
        .bind(&line_a).fetch_one(&e.db).await.unwrap();
    assert_eq!(row.0, "consumed");
    assert_eq!(row.1, q("5"));
    assert_eq!(
        row.2.map(|u| u.to_string()),
        m["id"].as_str().map(str::to_string)
    );
    assert_eq!(e.totals(FRAME).await, (q("3"), q("3"), q("0")));
    // Order B can ship its own; its reservation is not available to anyone else meanwhile.
    let (status, _) = ship(&line_b, "3").await;
    assert_eq!(status, StatusCode::CREATED);
    assert_eq!(e.totals(FRAME).await, (q("0"), q("0"), q("0")));
    e.integrity_ok().await;
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_reservation_can_be_reduced_in_part_and_cancelling_the_order_releases_it(db: PgPool) {
    let e = env(db).await;
    let (order, line) = confirmed_order_with_stock(&e, FRAME, "10", "6").await;
    reserve(&e.app, &line, "6").await;
    let (_, r) = reserve(&e.app, &line, "4").await;
    assert_eq!(dec(&r["reserved"]), q("4"));
    let active: i64 = sqlx::query_scalar("SELECT count(*) FROM inventory.reservations WHERE reference_id = $1::uuid AND status = 'active'").bind(&line).fetch_one(&e.db).await.unwrap();
    assert_eq!(active, 1, "one active row per place");
    let (_, r) = reserve(&e.app, &line, "6").await;
    assert_eq!(dec(&r["reserved"]), q("6"));
    let active: i64 = sqlx::query_scalar("SELECT count(*) FROM inventory.reservations WHERE reference_id = $1::uuid AND status = 'active'").bind(&line).fetch_one(&e.db).await.unwrap();
    assert_eq!(active, 1, "adding at the same place adds to the row");
    let (status, o) = api(
        &e.app,
        SALES,
        Method::POST,
        &format!("/orders/{order}/cancel"),
        Some(json!({ "reason": "withdrawn" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{o}");
    assert_eq!(e.totals(FRAME).await, (q("10"), q("0"), q("10")));
    let statuses: Vec<String> = sqlx::query_scalar(
        "SELECT status FROM inventory.reservations WHERE reference_id = $1::uuid",
    )
    .bind(&line)
    .fetch_all(&e.db)
    .await
    .unwrap();
    assert!(statuses.iter().all(|s| s == "released"), "{statuses:?}");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn other_modules_can_reserve_for_their_own_reference_types(db: PgPool) {
    use tradocraft_inventory::reservations::{
        release_reference, set_reserved, ReservePin, ReserveTarget, PRODUCTION_COMPONENT,
    };
    use tradocraft_inventory::{post_move, virtual_location, NewMove};
    let e = env(db).await;
    e.receive(FRAME, &e.main, "5").await;
    let user = tradocraft_core::CurrentUser {
        user_id: Uuid::parse_str("00000000-0000-7000-8000-000000000101").unwrap(),
        email: ADMIN.into(),
        display_name: "Admin".into(),
        company_id: Uuid::parse_str(COMPANY).unwrap(),
        roles: vec!["admin".into()],
        disabled_modules: Vec::new(),
    };
    let component = Uuid::now_v7();
    let product = Uuid::parse_str(FRAME).unwrap();
    let target = ReserveTarget {
        reference_type: PRODUCTION_COMPONENT,
        reference_id: component,
        product_id: product,
    };
    let mut tx = e.db.begin().await.unwrap();
    assert_eq!(
        set_reserved(&mut tx, &user, &target, q("3"), &ReservePin::default())
            .await
            .unwrap(),
        Decimal::ZERO
    );
    assert_eq!(
        set_reserved(&mut tx, &user, &target, q("4"), &ReservePin::default())
            .await
            .unwrap(),
        q("3")
    );
    let too_much = set_reserved(&mut tx, &user, &target, q("6"), &ReservePin::default()).await;
    assert!(too_much.is_err(), "only 5 exist");
    tx.commit().await.unwrap();
    assert_eq!(e.totals(FRAME).await, (q("5"), q("4"), q("1")));
    let (_, list) = get(
        &e.app,
        SALES,
        &format!("/inventory/reservations?product_id={FRAME}"),
    )
    .await;
    assert_eq!(list[0]["reference_type"], "production_component");
    assert_eq!(list[0]["reference_id"], component.to_string().as_str());
    assert!(list[0]["order_number"].is_null());
    // Unknown reference types are refused by the function and by the database.
    let mut tx = e.db.begin().await.unwrap();
    let bad = ReserveTarget {
        reference_type: "wishful",
        reference_id: component,
        product_id: product,
    };
    assert!(
        set_reserved(&mut tx, &user, &bad, q("1"), &ReservePin::default())
            .await
            .is_err()
    );
    tx.rollback().await.unwrap();
    let raw = sqlx::query("INSERT INTO inventory.reservations (id, company_id, reference_type, reference_id, product_id, location_id, quantity)
                           SELECT gen_random_uuid(), company_id, 'wishful', gen_random_uuid(), product_id, location_id, 1 FROM inventory.reservations LIMIT 1")
        .execute(&e.db).await;
    assert!(raw.is_err());
    // A production move consumes its own component reservation; the stock is exempt only for it.
    let to = {
        let mut conn = e.db.acquire().await.unwrap();
        virtual_location(&mut conn, user.company_id, "production_consumption")
            .await
            .unwrap()
    };
    let mut tx = e.db.begin().await.unwrap();
    let from = Uuid::parse_str(&e.main).unwrap();
    let mut m = NewMove::new(
        Uuid::now_v7(),
        &user,
        product,
        q("1"),
        from,
        to,
        "issue",
        "consumption",
    );
    m.respect_reservations = true;
    assert!(post_move(&mut tx, &m).await.is_ok(), "1 is free");
    let mut m = NewMove::new(
        Uuid::now_v7(),
        &user,
        product,
        q("2"),
        from,
        to,
        "issue",
        "consumption",
    );
    m.respect_reservations = true;
    assert!(
        post_move(&mut tx, &m).await.is_err(),
        "the rest is reserved for the component"
    );
    tx.rollback().await.unwrap();
    let mut tx = e.db.begin().await.unwrap();
    let mut m = NewMove::new(
        Uuid::now_v7(),
        &user,
        product,
        q("2"),
        from,
        to,
        "issue",
        "consumption",
    );
    m.respect_reservations = true;
    m.consume_reservation = Some((PRODUCTION_COMPONENT.into(), component));
    post_move(&mut tx, &m).await.unwrap();
    assert_eq!(
        release_reference(
            &mut tx,
            user.company_id,
            PRODUCTION_COMPONENT,
            component,
            None
        )
        .await
        .unwrap(),
        1
    );
    tx.commit().await.unwrap();
    assert_eq!(e.totals(FRAME).await, (q("3"), q("0"), q("3")));
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_reversal_that_would_take_reserved_stock_is_refused_unless_forced(db: PgPool) {
    let e = env(db).await;
    let receipt = e.receive(FRAME, &e.main, "5").await;
    let rid = receipt["id"].as_str().unwrap();
    let (order, line) = order_with(&e.app, FRAME, "4").await;
    confirm(&e.app, &order).await;
    reserve(&e.app, &line, "4").await;
    let (status, r) = post(
        &e.app,
        ADMIN,
        &format!("/inventory/moves/{rid}/reverse"),
        json!({ "id": uid() }),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT, "{r}");
    assert!(r["message"].as_str().unwrap().contains("reserved"), "{r}");
    assert_eq!(e.totals(FRAME).await.0, q("5"));
    // Forced by an inventory administrator: the stock goes, the order lacks it (negative available).
    let (status, f) = post(
        &e.app,
        ADMIN,
        &format!("/inventory/moves/{rid}/reverse"),
        json!({ "id": uid(), "force": true, "note": "supplier error" }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{f}");
    assert_eq!(e.totals(FRAME).await, (q("0"), q("4"), q("-4")));
    let forced: i64 = sqlx::query_scalar("SELECT count(*) FROM audit.events WHERE action = 'reversed' AND (data->>'forced')::boolean").fetch_one(&e.db).await.unwrap();
    assert_eq!(forced, 1);
    // Warehouse staff cannot reverse at all, forced or not.
    let (status, _) = post(
        &e.app,
        STORES,
        &format!("/inventory/moves/{rid}/reverse"),
        json!({ "id": uid(), "force": true }),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    e.integrity_ok().await;
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_delivered_serial_unit_comes_back_through_a_return_receipt(db: PgPool) {
    let e = env(db).await;
    let (_, m) = post(&e.app, STORES, "/inventory/receipts", json!({ "id": uid(), "product_id": PUMP, "location_id": e.main, "quantity": "1", "serial_number": "P-RET-1" })).await;
    let unit = m["serial_unit_id"].as_str().unwrap().to_string();
    let ship = |customer: Value| {
        post(
            &e.app,
            STORES,
            "/inventory/issues",
            json!({ "id": uid(), "product_id": PUMP, "location_id": e.main, "quantity": "1", "serial_unit_id": unit, "reason": "shipment", "customer_id": customer }),
        )
    };
    assert_eq!(ship(json!(ALPHA)).await.0, StatusCode::CREATED);
    // A normal receipt of a delivered unit is still refused; a return takes it back.
    let (status, _) = post(&e.app, STORES, "/inventory/receipts", json!({ "id": uid(), "product_id": PUMP, "location_id": e.main, "quantity": "1", "serial_unit_id": unit })).await;
    assert_eq!(status, StatusCode::CONFLICT);
    let (status, r) = post(&e.app, STORES, "/inventory/receipts", json!({ "id": uid(), "product_id": PUMP, "location_id": e.main, "quantity": "1", "serial_number": "P-RET-1", "reason": "return" })).await;
    assert_eq!(status, StatusCode::CREATED, "{r}");
    assert_eq!(r["from_location"], "customer");
    assert_eq!(r["reason"], "return");
    let (_, d) = get(&e.app, ADMIN, &format!("/serials/{unit}")).await;
    assert_eq!(
        (
            d["unit"]["status"].as_str(),
            d["unit"]["customer_id"].is_null()
        ),
        (Some("in_stock"), true)
    );
    assert_eq!(e.totals(PUMP).await.0, q("1"));
    // Back in stock: it can be returned only once, and not when it was never delivered.
    let (status, _) = post(&e.app, STORES, "/inventory/receipts", json!({ "id": uid(), "product_id": PUMP, "location_id": e.main, "quantity": "1", "serial_unit_id": unit, "reason": "return" })).await;
    assert_eq!(status, StatusCode::CONFLICT);
    let (status, _) = post(&e.app, STORES, "/inventory/receipts", json!({ "id": uid(), "product_id": PUMP, "location_id": e.main, "quantity": "1", "serial_number": "NEVER-SEEN", "reason": "return" })).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    // A unit built into another one (genealogy, ADR 0011) cannot be returned, a scrapped one neither.
    let (status, _) = post(&e.app, STORES, "/inventory/receipts", json!({ "id": uid(), "product_id": PUMP, "location_id": e.main, "quantity": "1", "serial_unit_id": "00000000-0000-7000-8000-000000000602", "reason": "return" })).await;
    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!(ship(json!(ALPHA)).await.0, StatusCode::CREATED);
    sqlx::query("UPDATE engineering.serial_units SET status = 'scrapped' WHERE id = $1::uuid")
        .bind(&unit)
        .execute(&e.db)
        .await
        .unwrap();
    let (status, _) = post(&e.app, STORES, "/inventory/receipts", json!({ "id": uid(), "product_id": PUMP, "location_id": e.main, "quantity": "1", "serial_unit_id": unit, "reason": "return" })).await;
    assert_eq!(status, StatusCode::CONFLICT);
    let links: i64 = sqlx::query_scalar("SELECT count(*) FROM engineering.serial_unit_components WHERE parent_id = '00000000-0000-7000-8000-000000000601'::uuid AND removed_at IS NULL").fetch_one(&e.db).await.unwrap();
    assert_eq!(links, 3, "the as-built links are untouched");
    e.integrity_ok().await;
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn expired_lots_count_as_on_hand_but_not_as_available(db: PgPool) {
    let e = env(db).await;
    make_lot_tracked(&e.db, BOLT).await;
    for (lot, qty, exp) in [("GOOD", "5", "2099-01-01"), ("OLD", "10", "2020-01-01")] {
        let (s, r) = post(&e.app, STORES, "/inventory/receipts", json!({ "id": uid(), "product_id": BOLT, "location_id": e.main, "quantity": qty, "lot_number": lot, "expiry_date": exp })).await;
        assert_eq!(s, StatusCode::CREATED, "{r}");
    }
    let (order, line) = order_with(&e.app, BOLT, "8").await;
    confirm(&e.app, &order).await;
    let (_, a) = get(
        &e.app,
        SALES,
        &format!("/inventory/orders/{order}/availability"),
    )
    .await;
    let l = &a["lines"][0];
    assert_eq!(
        (dec(&l["on_hand"]), dec(&l["expired"]), dec(&l["available"])),
        (q("15"), q("10"), q("5"))
    );
    assert_eq!(l["state"], "partial");
    assert_eq!(dec(&l["shortfall"]), q("3"));
    // Reserving takes the good lot only, and no more than it has.
    let (status, r) = reserve(&e.app, &line, "6").await;
    assert_eq!(status, StatusCode::CONFLICT, "{r}");
    let (status, r) = reserve(&e.app, &line, "5").await;
    assert_eq!(status, StatusCode::OK, "{r}");
    assert_eq!(r["allocations"][0]["lot_number"], "GOOD");
    let (_, a) = get(
        &e.app,
        SALES,
        &format!("/inventory/orders/{order}/availability"),
    )
    .await;
    assert_eq!(dec(&a["lines"][0]["available"]), q("0"));
    assert_eq!(dec(&a["lines"][0]["on_hand"]), q("15"));
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn search_wildcards_are_taken_literally(db: PgPool) {
    let e = env(db).await;
    sqlx::query("INSERT INTO products.products (id, code, name, unit, product_type, vat_rate) VALUES (gen_random_uuid(), 'AB_CD', 'Underscore part', 'pcs', 'purchased', 21), (gen_random_uuid(), 'ABXCD', 'Plain part', 'pcs', 'purchased', 21), (gen_random_uuid(), '50%OFF', 'Percent part', 'pcs', 'purchased', 21)")
        .execute(&e.db).await.unwrap();
    for code in ["AB_CD", "ABXCD", "50%OFF"] {
        let id: Uuid = sqlx::query_scalar("SELECT id FROM products.products WHERE code = $1")
            .bind(code)
            .fetch_one(&e.db)
            .await
            .unwrap();
        e.receive(&id.to_string(), &e.main, "1").await;
    }
    let codes = |v: &Value| -> Vec<String> {
        v["items"]
            .as_array()
            .unwrap()
            .iter()
            .map(|i| {
                i["product_code"]
                    .as_str()
                    .or(i["code"].as_str())
                    .unwrap()
                    .to_string()
            })
            .collect()
    };
    let (_, r) = get(&e.app, SALES, "/inventory/stock?q=ab_cd").await;
    assert_eq!(
        codes(&r),
        vec!["AB_CD"],
        "an underscore is not 'any character'"
    );
    let (_, r) = get(&e.app, SALES, "/inventory/stock?q=%25").await;
    assert_eq!(
        codes(&r),
        vec!["50%OFF"],
        "a percent sign is not 'anything'"
    );
    let (_, r) = get(&e.app, SALES, "/inventory/stock?q=_").await;
    assert_eq!(codes(&r), vec!["AB_CD"]);
    let (_, r) = get(&e.app, SALES, "/inventory/stock/products?q=ab_cd").await;
    assert_eq!(codes(&r), vec!["AB_CD"]);
    let (_, r) = get(&e.app, SALES, "/inventory/stock?q=%5C").await;
    assert_eq!(r["total"], 0, "a backslash matches nothing here");
    let (_, r) = get(&e.app, SALES, "/inventory/stock?q=abxcd").await;
    assert_eq!(codes(&r), vec!["ABXCD"]);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn cost_is_stored_copied_by_a_reversal_and_hidden_without_permission(db: PgPool) {
    let e = env(db).await;
    let (_, p) = get(&e.app, PM, &format!("/products/{FRAME}")).await;
    let set_cost = |cost: &'static str, p: Value| {
        let app = e.app.clone();
        async move {
            let mut i = p;
            i["standard_cost"] = json!(cost);
            let (s, _) = api(
                &app,
                PM,
                Method::PUT,
                &format!("/products/{FRAME}"),
                Some(i),
            )
            .await;
            assert_eq!(s, StatusCode::OK);
        }
    };
    set_cost("812.5", p.clone()).await;
    let receipt = e.receive(FRAME, &e.main, "5").await;
    // The receipt response is the warehouse's: no cost for them.
    assert!(receipt["unit_cost"].is_null() && receipt["currency"].is_null());
    let rid = receipt["id"].as_str().unwrap();
    let (_, m) = get(&e.app, PM, &format!("/inventory/moves/{rid}")).await;
    assert_eq!(
        (dec(&m["unit_cost"]), m["currency"].as_str()),
        (q("812.5"), Some("EUR"))
    );
    // The standard cost changes; the reversal still carries the cost of the original.
    set_cost("900", p).await;
    let (status, rev) = post(
        &e.app,
        ADMIN,
        &format!("/inventory/moves/{rid}/reverse"),
        json!({ "id": uid() }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);
    assert_eq!(
        (dec(&rev["unit_cost"]), rev["currency"].as_str()),
        (q("812.5"), Some("EUR")),
        "{rev}"
    );
    // A booked cost wins over the standard cost; a currency can be given; purchasing-style.
    let (status, r) = post(&e.app, ADMIN, "/inventory/receipts", json!({ "id": uid(), "product_id": FRAME, "location_id": e.main, "quantity": "2", "unit_cost": "10.25", "currency": "usd" })).await;
    assert_eq!(status, StatusCode::CREATED, "{r}");
    assert_eq!(
        (dec(&r["unit_cost"]), r["currency"].as_str()),
        (q("10.25"), Some("USD"))
    );
    let (_, back) = post(
        &e.app,
        ADMIN,
        &format!("/inventory/moves/{}/reverse", r["id"].as_str().unwrap()),
        json!({ "id": uid() }),
    )
    .await;
    assert_eq!(
        (dec(&back["unit_cost"]), back["currency"].as_str()),
        (q("10.25"), Some("USD"))
    );
    // Only people with the cost permission can book a cost.
    let (status, _) = post(&e.app, STORES, "/inventory/receipts", json!({ "id": uid(), "product_id": FRAME, "location_id": e.main, "quantity": "1", "unit_cost": "1" })).await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, _) = post(&e.app, ADMIN, "/inventory/receipts", json!({ "id": uid(), "product_id": FRAME, "location_id": e.main, "quantity": "1", "currency": "EUR" })).await;
    assert_eq!(
        status,
        StatusCode::UNPROCESSABLE_ENTITY,
        "a currency without a cost"
    );
    let (status, _) = post(&e.app, ADMIN, "/inventory/receipts", json!({ "id": uid(), "product_id": FRAME, "location_id": e.main, "quantity": "1", "unit_cost": "1", "currency": "EURO" })).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    // Hidden from everyone without inventory.cost, in lists, single moves and reversals.
    for who in [SALES, STORES, VIEWER] {
        let (_, h) = get(&e.app, who, &format!("/inventory/moves?product_id={FRAME}")).await;
        assert!(
            h["items"]
                .as_array()
                .unwrap()
                .iter()
                .all(|m| m["unit_cost"].is_null() && m["currency"].is_null()),
            "{who}"
        );
        let (_, one) = get(&e.app, who, &format!("/inventory/moves/{rid}")).await;
        assert!(
            one["unit_cost"].is_null() && one["currency"].is_null(),
            "{who}"
        );
    }
    assert!(
        rev["unit_cost"].is_string(),
        "the admin holds the permission"
    );
    // A product without a standard cost books no cost.
    let (_, other) = post(
        &e.app,
        ADMIN,
        "/inventory/receipts",
        json!({ "id": uid(), "product_id": PROFILE, "location_id": e.main, "quantity": "1" }),
    )
    .await;
    assert!(other["unit_cost"].is_null() && other["currency"].is_null());
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn foreign_locations_lots_and_serial_units_are_rejected_on_receipts_and_issues(db: PgPool) {
    let e = env(db).await;
    second_company(&e.db).await;
    make_lot_tracked(&e.db, BOLT).await;
    let (_, ours) = post(&e.app, STORES, "/inventory/receipts", json!({ "id": uid(), "product_id": BOLT, "location_id": e.main, "quantity": "5", "lot_number": "OURS" })).await;
    let our_lot = ours["lot_id"].as_str().unwrap().to_string();
    let (_, w) = post(
        &e.app,
        "other@example.com",
        "/inventory/warehouses",
        json!({ "code": "W", "name": "Theirs" }),
    )
    .await;
    let theirs = w["locations"][0]["id"].as_str().unwrap().to_string();
    let other = "other@example.com";
    // Our location.
    for uri in ["/inventory/receipts", "/inventory/issues"] {
        let (status, _) = post(
            &e.app,
            other,
            uri,
            json!({ "id": uid(), "product_id": FRAME, "location_id": e.main, "quantity": "1" }),
        )
        .await;
        assert_eq!(status, StatusCode::NOT_FOUND, "{uri}");
    }
    // Our lot, on their location.
    let (status, _) = post(&e.app, other, "/inventory/issues", json!({ "id": uid(), "product_id": BOLT, "location_id": theirs, "quantity": "1", "lot_id": our_lot })).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    // Our serial unit, on their location, for both operations.
    let unit = "00000000-0000-7000-8000-000000000605";
    let (status, _) = post(&e.app, other, "/inventory/receipts", json!({ "id": uid(), "product_id": PUMP, "location_id": theirs, "quantity": "1", "serial_unit_id": unit })).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, _) = post(&e.app, other, "/inventory/receipts", json!({ "id": uid(), "product_id": PUMP, "location_id": theirs, "quantity": "1", "serial_unit_id": unit, "reason": "return" })).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, _) = post(&e.app, other, "/inventory/issues", json!({ "id": uid(), "product_id": PUMP, "location_id": theirs, "quantity": "1", "serial_unit_id": unit, "reason": "scrap" })).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    // Their consume_reservation_line cannot reach our order lines either.
    let (order, line) = order_with(&e.app, FRAME, "1").await;
    confirm(&e.app, &order).await;
    e.receive(FRAME, &e.main, "2").await;
    reserve(&e.app, &line, "1").await;
    post(
        &e.app,
        other,
        "/inventory/receipts",
        json!({ "id": uid(), "product_id": FRAME, "location_id": theirs, "quantity": "5" }),
    )
    .await;
    let (status, r) = post(&e.app, other, "/inventory/issues", json!({ "id": uid(), "product_id": FRAME, "location_id": theirs, "quantity": "1", "consume_reservation_line": line })).await;
    assert_eq!(status, StatusCode::CONFLICT, "{r}");
    assert_eq!(
        e.totals(FRAME).await.1,
        q("1"),
        "our reservation is untouched"
    );
    e.integrity_ok().await;
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_count_reports_what_moved_while_it_was_open(db: PgPool) {
    let e = env(db).await;
    e.receive(FRAME, &e.main, "10").await;
    let (_, c) = post(
        &e.app,
        STORES,
        "/inventory/counts",
        json!({ "warehouse_id": e.wh }),
    )
    .await;
    let cid = c["count"]["id"].as_str().unwrap().to_string();
    let line = c["lines"][0]["id"].as_str().unwrap().to_string();
    // One unit leaves during the count; the counters find 9 (they counted the same shelf).
    e.issue(FRAME, &e.main, "1").await;
    api(
        &e.app,
        STORES,
        Method::PUT,
        &format!("/inventory/counts/{cid}/lines"),
        Some(json!({ "entries": [{ "line_id": line, "counted_quantity": "9" }] })),
    )
    .await;
    let (status, d) = post(
        &e.app,
        ADMIN,
        &format!("/inventory/counts/{cid}/post"),
        json!({}),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{d}");
    let l = &d["lines"][0];
    assert_eq!(dec(&l["expected_quantity"]), q("10"));
    assert_eq!(dec(&l["quantity_at_post"]), q("9"));
    assert_eq!(dec(&l["difference_to_expected"]), q("-1"));
    assert!(
        l["adjustment_move_id"].is_null(),
        "9 counted, 9 in stock: nothing to adjust"
    );
    assert_eq!(d["moved_during_count"], 1);
    assert_eq!(e.totals(FRAME).await.0, q("9"));
}

// ---------------------------------------------------------------------------------------------
// Review round: consumed demand, releases, serial quantities, expired cover, cumulative lines,
// paging, replays and lots
// ---------------------------------------------------------------------------------------------

/// A quotation with several lines of one product, converted to an order. Returns the order and its
/// line ids in position order.
async fn order_with_lines(
    app: &axum::Router,
    product: &str,
    quantities: &[&str],
) -> (String, Vec<String>) {
    let lines: Vec<Value> = quantities
        .iter()
        .map(|quantity| json!({ "product_id": product, "quantity": quantity }))
        .collect();
    let (status, qn) = api(
        app,
        SALES,
        Method::POST,
        "/quotations",
        Some(json!({ "customer_id": ALPHA, "lines": lines })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{qn}");
    let qid = qn["id"].as_str().unwrap();
    api(
        app,
        SALES,
        Method::POST,
        &format!("/quotations/{qid}/send"),
        None,
    )
    .await;
    let (status, o) = api(
        app,
        SALES,
        Method::POST,
        &format!("/quotations/{qid}/convert"),
        Some(json!({ "customer_reference": "PO" })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{o}");
    let ids = o["lines"]
        .as_array()
        .unwrap()
        .iter()
        .map(|l| l["id"].as_str().unwrap().to_string())
        .collect();
    (o["order"]["id"].as_str().unwrap().into(), ids)
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn what_was_shipped_is_no_longer_demand(db: PgPool) {
    let e = env(db).await;
    let (order, line) = confirmed_order_with_stock(&e, FRAME, "10", "5").await;
    assert_eq!(reserve(&e.app, &line, "5").await.0, StatusCode::OK);
    let (status, m) = post(
        &e.app,
        STORES,
        "/inventory/issues",
        json!({ "id": uid(), "product_id": FRAME, "location_id": e.main, "quantity": "2", "reason": "shipment", "consume_reservation_line": line }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{m}");

    // The line still needs 3: the 3 it holds cover it, there is no shortage.
    let (_, a) = get(
        &e.app,
        SALES,
        &format!("/inventory/orders/{order}/availability"),
    )
    .await;
    let l = &a["lines"][0];
    assert_eq!(
        (
            dec(&l["ordered_stock"]),
            dec(&l["consumed"]),
            dec(&l["reserved"])
        ),
        (q("5"), q("2"), q("3"))
    );
    assert_eq!(l["state"], "reserved", "{l}");
    assert_eq!(dec(&l["shortfall"]), q("0"));
    let (_, r) = get(
        &e.app,
        SALES,
        &format!("/inventory/order-lines/{line}/reservation"),
    )
    .await;
    assert_eq!((dec(&r["ordered"]), dec(&r["consumed"])), (q("5"), q("2")));

    // Reserving the shipped quantity again is refused; what is left is allowed.
    let (status, r) = reserve(&e.app, &line, "5").await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{r}");
    assert!(
        r["message"].as_str().unwrap().contains("already shipped"),
        "{r}"
    );
    assert_eq!(reserve(&e.app, &line, "3").await.0, StatusCode::OK);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_reservation_can_be_released_after_its_unit_lost_the_conversion(db: PgPool) {
    let e = env(db).await;
    e.receive(FRAME, &e.main, "30").await;
    let (order, line) = order_with(&e.app, FRAME, "1").await;
    confirm(&e.app, &order).await;
    api(
        &e.app,
        ADMIN,
        Method::PUT,
        &format!("/inventory/products/{FRAME}/uoms"),
        Some(json!({ "uoms": [{ "uom_code": "set", "factor": "12" }] })),
    )
    .await;
    sqlx::query("UPDATE sales.order_lines SET unit = 'set' WHERE id = $1::uuid")
        .bind(&line)
        .execute(&e.db)
        .await
        .unwrap();
    let (status, r) = reserve(&e.app, &line, "12").await;
    assert_eq!(status, StatusCode::OK, "{r}");
    assert_eq!(dec(&r["ordered"]), q("12"));

    // The conversion is removed. Raising or reading fails, lowering and releasing work.
    api(
        &e.app,
        ADMIN,
        Method::PUT,
        &format!("/inventory/products/{FRAME}/uoms"),
        Some(json!({ "uoms": [] })),
    )
    .await;
    let (status, _) = reserve(&e.app, &line, "13").await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    let (status, r) = reserve(&e.app, &line, "4").await;
    assert_eq!(status, StatusCode::OK, "{r}");
    assert_eq!(dec(&r["reserved"]), q("4"));
    assert_eq!(dec(&r["ordered"]), q("0"), "unknown without the conversion");
    let (status, r) = reserve(&e.app, &line, "0").await;
    assert_eq!(status, StatusCode::OK, "{r}");
    assert_eq!(e.totals(FRAME).await, (q("30"), q("0"), q("30")));
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn serial_products_are_reserved_in_whole_units(db: PgPool) {
    let e = env(db).await;
    let (order, line) = order_with(&e.app, PUMP, "2").await;
    confirm(&e.app, &order).await;
    let (status, r) = reserve(&e.app, &line, "0.5").await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{r}");
    assert!(
        r["message"].as_str().unwrap().contains("whole units"),
        "{r}"
    );
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn later_lines_of_the_same_product_only_get_what_is_left(db: PgPool) {
    let e = env(db).await;
    e.receive(FRAME, &e.main, "5").await;
    let (order, _) = order_with_lines(&e.app, FRAME, &["4", "4"]).await;
    confirm(&e.app, &order).await;
    let (_, a) = get(
        &e.app,
        SALES,
        &format!("/inventory/orders/{order}/availability"),
    )
    .await;
    let lines = a["lines"].as_array().unwrap();
    assert_eq!(
        (dec(&lines[0]["shortfall"]), lines[0]["state"].as_str()),
        (q("0"), Some("available"))
    );
    assert_eq!(
        (dec(&lines[1]["shortfall"]), lines[1]["state"].as_str()),
        (q("3"), Some("partial")),
        "{a}"
    );
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_reservation_in_an_expired_lot_does_not_cover_the_line(db: PgPool) {
    let e = env(db).await;
    make_lot_tracked(&e.db, BOLT).await;
    post(&e.app, STORES, "/inventory/receipts", json!({ "id": uid(), "product_id": BOLT, "location_id": e.main, "quantity": "5", "lot_number": "L1", "expiry_date": "2099-01-01" })).await;
    let (order, line) = order_with(&e.app, BOLT, "5").await;
    confirm(&e.app, &order).await;
    assert_eq!(reserve(&e.app, &line, "5").await.0, StatusCode::OK);
    sqlx::query("UPDATE inventory.lots SET expiry_date = '2020-01-01' WHERE lot_number = 'L1'")
        .execute(&e.db)
        .await
        .unwrap();
    let (_, a) = get(
        &e.app,
        SALES,
        &format!("/inventory/orders/{order}/availability"),
    )
    .await;
    let l = &a["lines"][0];
    assert_eq!(
        dec(&l["reserved"]),
        q("5"),
        "the allocation is still held and can be released"
    );
    assert_eq!(dec(&l["shortfall"]), q("5"), "{l}");
    assert_eq!(l["state"], "short", "{l}");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn reservations_are_listed_in_pages(db: PgPool) {
    let e = env(db).await;
    e.receive(FRAME, &e.main, "10").await;
    for _ in 0..3 {
        let (order, line) = order_with(&e.app, FRAME, "1").await;
        confirm(&e.app, &order).await;
        assert_eq!(reserve(&e.app, &line, "1").await.0, StatusCode::OK);
    }
    let page = |query: &'static str| {
        let app = e.app.clone();
        async move {
            let (status, rows) = get(
                &app,
                SALES,
                &format!("/inventory/reservations?product_id={FRAME}{query}"),
            )
            .await;
            assert_eq!(status, StatusCode::OK, "{rows}");
            rows.as_array()
                .unwrap()
                .iter()
                .map(|r| r["id"].as_str().unwrap().to_string())
                .collect::<Vec<_>>()
        }
    };
    let all = page("").await;
    assert_eq!(all.len(), 3);
    assert_eq!(page("&limit=2").await, all[..2]);
    assert_eq!(page("&limit=2&offset=2").await, all[2..]);
    assert!(page("&offset=3").await.is_empty());
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn lots_with_stock_are_found_even_behind_many_empty_lots(db: PgPool) {
    let e = env(db).await;
    make_lot_tracked(&e.db, BOLT).await;
    // 501 lots that expire earlier and hold nothing, then one with stock.
    sqlx::query(
        "INSERT INTO inventory.lots (id, company_id, product_id, lot_number, expiry_date)
         SELECT gen_random_uuid(), $1::uuid, $2::uuid, 'E' || n, DATE '2030-01-01' + n FROM generate_series(1, 501) n",
    )
    .bind(COMPANY)
    .bind(BOLT)
    .execute(&e.db)
    .await
    .unwrap();
    post(&e.app, STORES, "/inventory/receipts", json!({ "id": uid(), "product_id": BOLT, "location_id": e.main, "quantity": "3", "lot_number": "FULL", "expiry_date": "2099-01-01" })).await;
    let (status, lots) = get(
        &e.app,
        STORES,
        &format!("/inventory/lots?product_id={BOLT}&in_stock=true"),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{lots}");
    let lots = lots.as_array().unwrap();
    assert_eq!(lots.len(), 1, "{lots:?}");
    assert_eq!(lots[0]["lot_number"], "FULL");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_retry_keeps_working_after_the_conversion_changed(db: PgPool) {
    let e = env(db).await;
    api(
        &e.app,
        ADMIN,
        Method::PUT,
        &format!("/inventory/products/{FRAME}/uoms"),
        Some(json!({ "uoms": [{ "uom_code": "set", "factor": "12" }] })),
    )
    .await;
    let body = json!({ "id": uid(), "product_id": FRAME, "location_id": e.main, "quantity": "1", "uom": "set" });
    let (status, m) = post(&e.app, STORES, "/inventory/receipts", body.clone()).await;
    assert_eq!(status, StatusCode::CREATED, "{m}");
    // The response was lost and the conversion changed meanwhile: the retry replays the move.
    api(
        &e.app,
        ADMIN,
        Method::PUT,
        &format!("/inventory/products/{FRAME}/uoms"),
        Some(json!({ "uoms": [{ "uom_code": "set", "factor": "10" }] })),
    )
    .await;
    let (status, again) = post(&e.app, STORES, "/inventory/receipts", body).await;
    assert_eq!(status, StatusCode::OK, "{again}");
    assert_eq!(again["id"], m["id"]);
    assert_eq!(e.totals(FRAME).await.0, q("12"));
    // A different quantity under the same id is still a clash.
    let (status, _) = post(&e.app, STORES, "/inventory/receipts", json!({ "id": m["id"], "product_id": FRAME, "location_id": e.main, "quantity": "2", "uom": "set" })).await;
    assert_eq!(status, StatusCode::CONFLICT);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn concurrent_receipts_of_a_new_serial_register_it_once(db: PgPool) {
    let e = env(db).await;
    let id = uid();
    let body = json!({ "id": id, "product_id": PUMP, "location_id": e.main, "quantity": "1", "serial_number": "RACE-1" });
    let (a, b) = tokio::join!(
        post(&e.app, STORES, "/inventory/receipts", body.clone()),
        post(&e.app, STORES, "/inventory/receipts", body.clone())
    );
    let mut codes = [a.0.as_u16(), b.0.as_u16()];
    codes.sort();
    assert_eq!(codes, [200, 201], "{a:?} {b:?}");
    let units: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM engineering.serial_units WHERE serial_number = 'RACE-1'",
    )
    .fetch_one(&e.db)
    .await
    .unwrap();
    assert_eq!(units, 1);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn counts_are_searched_and_paged_and_a_foreign_lot_is_refused(db: PgPool) {
    let e = env(db).await;
    make_lot_tracked(&e.db, BOLT).await;
    make_lot_tracked(&e.db, FRAME).await;
    // Cancelled counts do not block new ones.
    let mut numbers = Vec::new();
    for _ in 0..3 {
        let (status, c) = post(
            &e.app,
            STORES,
            "/inventory/counts",
            json!({ "warehouse_id": e.wh, "product_id": FRAME }),
        )
        .await;
        assert_eq!(status, StatusCode::CREATED, "{c}");
        numbers.push(c["count"]["number"].as_str().unwrap().to_string());
        let cid = c["count"]["id"].as_str().unwrap();
        post(
            &e.app,
            STORES,
            &format!("/inventory/counts/{cid}/cancel"),
            json!({}),
        )
        .await;
    }
    let list = |query: String| {
        let app = e.app.clone();
        async move {
            let (status, rows) = get(&app, STORES, &format!("/inventory/counts{query}")).await;
            assert_eq!(status, StatusCode::OK, "{rows}");
            rows["items"]
                .as_array()
                .unwrap()
                .iter()
                .map(|c| c["number"].as_str().unwrap().to_string())
                .collect::<Vec<_>>()
        }
    };
    let all = list(String::new()).await;
    assert_eq!(all.len(), 3);
    let (_, page) = get(&e.app, STORES, "/inventory/counts?limit=2").await;
    assert_eq!(
        page["total"], 3,
        "the total counts the matches, not the page"
    );
    assert_eq!(list("?limit=2".into()).await, all[..2]);
    assert_eq!(list("?limit=2&offset=2".into()).await, all[2..]);
    assert_eq!(
        list(format!("?q={}", numbers[0].to_lowercase())).await,
        vec![numbers[0].clone()]
    );
    assert!(list("?q=zzz".into()).await.is_empty());

    // A lot of another product cannot be put on a count line, not even with a zero count.
    let (_, c) = post(
        &e.app,
        STORES,
        "/inventory/counts",
        json!({ "warehouse_id": e.wh, "product_id": FRAME }),
    )
    .await;
    let cid = c["count"]["id"].as_str().unwrap();
    post(&e.app, STORES, "/inventory/receipts", json!({ "id": uid(), "product_id": BOLT, "location_id": e.main, "quantity": "1", "lot_number": "B1" })).await;
    let lot: String =
        sqlx::query_scalar("SELECT id::text FROM inventory.lots WHERE lot_number = 'B1'")
            .fetch_one(&e.db)
            .await
            .unwrap();
    let (status, r) = api(
        &e.app,
        STORES,
        Method::PUT,
        &format!("/inventory/counts/{cid}/lines"),
        Some(json!({ "entries": [{ "product_id": FRAME, "location_id": e.main, "lot_id": lot, "counted_quantity": "0" }] })),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND, "{r}");
}

/// The development seed (the tutorial environment) has no warehouse: the tutorial teaches creating
/// one. Creating a warehouse brings its location MAIN, which goods are received into.
#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn dev_seed_has_no_warehouse_and_a_new_one_brings_location_main(db: PgPool) {
    let app = setup(db).await;
    let (st, list) = get(&app, ADMIN, "/inventory/warehouses").await;
    assert_eq!(st, StatusCode::OK, "{list}");
    assert_eq!(list, json!([]), "the tutorial creates the warehouse itself");
    let (st, w) = post(
        &app,
        ADMIN,
        "/inventory/warehouses",
        json!({ "code": "MAIN", "name": "Main warehouse" }),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED, "{w}");
    assert_eq!(w["locations"].as_array().unwrap().len(), 1);
    assert_eq!(w["locations"][0]["code"], "MAIN");
    let (st, _) = post(
        &app,
        ADMIN,
        "/inventory/warehouses",
        json!({ "code": "MAIN", "name": "again" }),
    )
    .await;
    assert_eq!(st, StatusCode::CONFLICT, "the code is unique per company");
}
