//! Finance (ADR 0046): supplier invoices, the three-way match against purchase orders and goods
//! receipts, approval with override, dispute, payment status, settings, permissions and isolation.

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
const BUYER: &str = "buyer@example.com"; // role purchaser: reads invoices only
const STORES: &str = "stores@example.com"; // role warehouse: receives goods
const FIN: &str = "fin@example.com"; // role finance
const OTHER_FIN: &str = "fin@other.example"; // role finance in another company
const COMPANY: &str = "00000000-0000-7000-8000-000000000001";
const OTHER_COMPANY: &str = "00000000-0000-7000-8000-0000000fff01";
const FRAME: &str = "00000000-0000-7000-8000-000000000307";
const PROFILE: &str = "00000000-0000-7000-8000-000000000308";

async fn add_user(db: &PgPool, email: &str, role: &str, company: &str) {
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
        .bind(company)
        .bind(vec![role.to_string()])
        .execute(db)
        .await
        .unwrap();
}

async fn send(
    app: &axum::Router,
    user: &str,
    method: Method,
    uri: &str,
    body: Option<Value>,
) -> (StatusCode, Value) {
    call(app, user, method, &format!("/api/v1{uri}"), body).await
}
async fn post(app: &axum::Router, user: &str, uri: &str, body: Value) -> (StatusCode, Value) {
    send(app, user, Method::POST, uri, Some(body)).await
}
async fn put(app: &axum::Router, user: &str, uri: &str, body: Value) -> (StatusCode, Value) {
    send(app, user, Method::PUT, uri, Some(body)).await
}
async fn get(app: &axum::Router, user: &str, uri: &str) -> (StatusCode, Value) {
    send(app, user, Method::GET, uri, None).await
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
    add_user(&db, BUYER, "purchaser", COMPANY).await;
    add_user(&db, STORES, "warehouse", COMPANY).await;
    add_user(&db, FIN, "finance", COMPANY).await;
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
    async fn supplier(&self, code: &str) -> String {
        let (status, s) = post(
            &self.app,
            BUYER,
            "/suppliers",
            json!({ "name": format!("Supplier {code}"), "code": code, "country": "de",
                    "payment_terms_days": 45 }),
        )
        .await;
        assert_eq!(status, StatusCode::CREATED, "{s}");
        s["id"].as_str().unwrap().into()
    }

    /// An approved order of 10 frames at 12.50 and 4.5 metres of profile at 3.333.
    async fn po(&self, supplier: &str) -> Value {
        let (status, po) = post(
            &self.app,
            BUYER,
            "/purchase-orders",
            json!({ "supplier_id": supplier, "lines": [
                { "product_id": FRAME, "quantity": "10", "unit_price": "12.50" },
                { "product_id": PROFILE, "quantity": "4.5", "unit_price": "3.333" } ] }),
        )
        .await;
        assert_eq!(status, StatusCode::CREATED, "{po}");
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

    async fn receive(&self, po: &Value, frames: &str, profile: &str) {
        let mut lines = vec![];
        for (idx, qty) in [(0, frames), (1, profile)] {
            if qty != "0" {
                lines.push(json!({ "po_line_id": po["lines"][idx]["id"], "quantity": qty }));
            }
        }
        let (status, gr) = post(
            &self.app,
            STORES,
            &format!("/purchase-orders/{}/receipts", po["id"].as_str().unwrap()),
            json!({ "warehouse_id": self.wh, "location_id": self.main, "lines": lines }),
        )
        .await;
        assert_eq!(status, StatusCode::CREATED, "{gr}");
    }

    /// An invoice from explicit lines against the order: (order line index, quantity, price).
    async fn invoice(&self, po: &Value, number: &str, lines: &[(usize, &str, &str)]) -> Value {
        let (status, inv) = post(
            &self.app,
            FIN,
            "/supplier-invoices",
            json!({
                "purchase_order_id": po["id"],
                "invoice_number": number,
                "invoice_date": "2027-02-01",
                "lines": lines.iter().map(|(i, qty, price)| json!({
                    "purchase_order_line_id": po["lines"][*i]["id"],
                    "quantity": qty, "unit_price": price })).collect::<Vec<_>>(),
            }),
        )
        .await;
        assert_eq!(status, StatusCode::CREATED, "{inv}");
        inv
    }

    async fn act(&self, user: &str, id: &Value, what: &str, body: Value) -> (StatusCode, Value) {
        post(
            &self.app,
            user,
            &format!("/supplier-invoices/{}/{what}", id.as_str().unwrap()),
            body,
        )
        .await
    }

    async fn audit_count(&self, entity_id: &Value, action: &str) -> i64 {
        sqlx::query_scalar(
            "SELECT count(*) FROM audit.events WHERE entity = 'supplier_invoice'
             AND entity_id = $1::uuid AND action = $2",
        )
        .bind(entity_id.as_str().unwrap())
        .bind(action)
        .fetch_one(&self.db)
        .await
        .unwrap()
    }
}

fn line_status(inv: &Value, i: usize) -> &str {
    inv["match_report"]["lines"][i]["status"].as_str().unwrap()
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_perfect_match_is_prefilled_matched_approved_and_audited(db: PgPool) {
    let e = env(db).await;
    let s = e.supplier("S1").await;
    let po = e.po(&s).await;
    e.receive(&po, "10", "4.5").await;

    // No lines given: prefilled from received and not yet invoiced.
    let (status, inv) = post(
        &e.app,
        FIN,
        "/supplier-invoices",
        json!({ "purchase_order_id": po["id"], "invoice_number": " INV-1 ",
                "invoice_date": "2027-02-01" }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{inv}");
    assert_eq!(inv["status"], "draft");
    assert_eq!(inv["invoice_number"], "INV-1");
    assert_eq!(inv["supplier_id"], s.as_str());
    assert_eq!(inv["supplier_name"], "Supplier S1");
    assert_eq!(inv["purchase_order_number"], po["number"]);
    assert_eq!(inv["currency"], "EUR");
    assert!(inv["number"].as_str().unwrap().starts_with("SI"));
    // Due date: invoice date plus the supplier's 45 days.
    assert_eq!(inv["due_date"], "2027-03-18");
    let lines = inv["lines"].as_array().unwrap();
    assert_eq!(lines.len(), 2);
    assert_eq!(dec(&lines[0]["quantity"]), q("10"));
    assert_eq!(dec(&lines[0]["unit_price"]), q("12.50"));
    assert_eq!(dec(&lines[1]["quantity"]), q("4.5"));
    // 125.00 + round(4.5 * 3.333 = 14.9985) = 140.00, no VAT.
    assert_eq!(dec(&inv["net_total"]), q("140.00"));
    assert_eq!(dec(&inv["gross_total"]), q("140.00"));
    assert_eq!(inv["match_report"]["matched"], true);
    assert_eq!(line_status(&inv, 0), "ok");

    let id = &inv["id"];
    let (status, m) = e.act(FIN, id, "submit-match", json!({})).await;
    assert_eq!(status, StatusCode::OK, "{m}");
    assert_eq!(m["status"], "matched");

    let (status, a) = e.act(FIN, id, "approve", json!({})).await;
    assert_eq!(status, StatusCode::OK, "{a}");
    assert_eq!(a["status"], "approved");
    assert!(a["approved_at"].is_string());
    assert_eq!(a["override_reason"], "");
    assert_eq!(e.audit_count(id, "created").await, 1);
    assert_eq!(e.audit_count(id, "match_evaluated").await, 1);
    assert_eq!(e.audit_count(id, "approved").await, 1);

    // Everything is invoiced now: a second prefill has nothing left.
    let (status, none) = post(
        &e.app,
        FIN,
        "/supplier-invoices",
        json!({ "purchase_order_id": po["id"], "invoice_number": "INV-2",
                "invoice_date": "2027-02-02" }),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{none}");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn invoicing_what_is_not_received_blocks_approval_until_overridden(db: PgPool) {
    let e = env(db).await;
    let s = e.supplier("S1").await;
    let po = e.po(&s).await;
    e.receive(&po, "4", "0").await;
    let inv = e.invoice(&po, "INV-1", &[(0, "10", "12.50")]).await;
    assert_eq!(line_status(&inv, 0), "not_received");
    let l = &inv["match_report"]["lines"][0];
    assert_eq!(dec(&l["ordered_quantity"]), q("10"));
    assert_eq!(dec(&l["received_quantity"]), q("4"));
    assert_eq!(dec(&l["invoiced_quantity"]), q("10"));
    assert_eq!(inv["match_report"]["matched"], false);
    let id = &inv["id"];

    // submit-match leaves the draft; approve is blocked.
    let (_, m) = e.act(FIN, id, "submit-match", json!({})).await;
    assert_eq!(m["status"], "draft");
    let (status, b) = e.act(FIN, id, "approve", json!({})).await;
    assert_eq!(status, StatusCode::CONFLICT, "{b}");
    let (status, b) = e
        .act(FIN, id, "approve", json!({ "override_reason": "  " }))
        .await;
    assert_eq!(status, StatusCode::CONFLICT, "{b}");

    let (status, a) = e
        .act(
            FIN,
            id,
            "approve",
            json!({ "override_reason": "Rest arrives Monday, supplier is reliable" }),
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{a}");
    assert_eq!(a["status"], "approved");
    assert_eq!(
        a["override_reason"],
        "Rest arrives Monday, supplier is reliable"
    );
    let data: Value = sqlx::query_scalar(
        "SELECT data FROM audit.events WHERE entity_id = $1::uuid AND action = 'approved'",
    )
    .bind(id.as_str().unwrap())
    .fetch_one(&e.db)
    .await
    .unwrap();
    assert_eq!(data["override"], true);
    assert_eq!(
        data["override_reason"],
        "Rest arrives Monday, supplier is reliable"
    );

    // Only an approver may override.
    let inv2 = e.invoice(&po, "INV-2", &[(0, "1", "12.50")]).await;
    let (status, _) = e
        .act(
            BUYER,
            &inv2["id"],
            "approve",
            json!({ "override_reason": "x" }),
        )
        .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn over_invoiced_follows_the_quantity_tolerance(db: PgPool) {
    let e = env(db).await;
    let s = e.supplier("S1").await;
    let po = e.po(&s).await;
    // Receipts cannot exceed the order, so the eleventh frame is also not received.
    e.receive(&po, "10", "0").await;
    e.invoice(&po, "INV-1", &[(0, "10", "12.50")]).await;
    let inv = e.invoice(&po, "INV-2", &[(0, "1", "12.50")]).await;
    assert_eq!(
        inv["match_report"]["lines"][0]["issues"],
        json!(["not_received", "over_invoiced"])
    );

    // 10 % extra is allowed once the tolerance says so: only the receipt problem is left.
    let (status, st) = put(
        &e.app,
        FIN,
        "/finance/settings",
        json!({ "quantity_tolerance_pct": "10" }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{st}");
    let uri = format!("/supplier-invoices/{}", inv["id"].as_str().unwrap());
    let (_, inv) = get(&e.app, FIN, &uri).await;
    assert_eq!(
        inv["match_report"]["lines"][0]["issues"],
        json!(["not_received"])
    );
    assert_eq!(inv["match_report"]["matched"], false);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn price_variance_inside_and_outside_the_tolerance(db: PgPool) {
    let e = env(db).await;
    let s = e.supplier("S1").await;
    let po = e.po(&s).await;
    e.receive(&po, "10", "4.5").await;
    // Default tolerance 2 %: 12.70 is +1.6 %, 13.00 is +4 %.
    let a = e.invoice(&po, "INV-A", &[(0, "10", "12.70")]).await;
    assert_eq!(line_status(&a, 0), "ok");
    let b = e.invoice(&po, "INV-B", &[(1, "4.5", "3.600")]).await;
    assert_eq!(line_status(&b, 0), "price_variance"); // +8 %
    let c = e.invoice(&po, "INV-C", &[(0, "0.5", "13.00")]).await;
    // Lines 0 now has 10 + 0.5 invoiced of 10 received: also not received.
    assert_eq!(
        c["match_report"]["lines"][0]["issues"],
        json!(["not_received", "over_invoiced", "price_variance"])
    );
    assert_eq!(
        dec(&c["match_report"]["lines"][0]["price_variance_pct"]),
        q("4")
    );
    // Wider price tolerance accepts the +8 % line.
    put(
        &e.app,
        ADMIN,
        "/finance/settings",
        json!({ "price_tolerance_pct": "10" }),
    )
    .await;
    let (_, b) = get(
        &e.app,
        FIN,
        &format!("/supplier-invoices/{}", b["id"].as_str().unwrap()),
    )
    .await;
    assert_eq!(line_status(&b, 0), "ok");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn partial_invoicing_counts_other_invoices_but_not_disputed_ones(db: PgPool) {
    let e = env(db).await;
    let s = e.supplier("S1").await;
    let po = e.po(&s).await;
    e.receive(&po, "6", "0").await;
    let first = e.invoice(&po, "INV-1", &[(0, "6", "12.50")]).await;
    assert_eq!(first["match_report"]["matched"], true);

    e.receive(&po, "4", "0").await;
    // Prefill offers only the 4 that are not invoiced yet.
    let (status, second) = post(
        &e.app,
        FIN,
        "/supplier-invoices",
        json!({ "purchase_order_id": po["id"], "invoice_number": "INV-2",
                "invoice_date": "2027-02-02" }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{second}");
    assert_eq!(second["lines"].as_array().unwrap().len(), 1);
    assert_eq!(dec(&second["lines"][0]["quantity"]), q("4"));
    assert_eq!(second["match_report"]["matched"], true);
    // The first invoice still matches with the second one counted.
    let (_, f) = get(
        &e.app,
        FIN,
        &format!("/supplier-invoices/{}", first["id"].as_str().unwrap()),
    )
    .await;
    assert_eq!(
        dec(&f["match_report"]["lines"][0]["invoiced_quantity"]),
        q("10")
    );
    assert_eq!(line_status(&f, 0), "ok");

    // One more frame is neither received nor ordered.
    let third = e.invoice(&po, "INV-3", &[(0, "1", "12.50")]).await;
    assert_eq!(line_status(&third, 0), "not_received");

    // Two lines of one invoice for the same order line add up as well.
    let (status, dual) = post(
        &e.app,
        FIN,
        "/supplier-invoices",
        json!({ "purchase_order_id": po["id"], "invoice_number": "INV-4", "invoice_date": "2027-02-03",
                "lines": [
                  { "purchase_order_line_id": po["lines"][1]["id"], "quantity": "1", "unit_price": "3.333" },
                  { "purchase_order_line_id": po["lines"][1]["id"], "quantity": "1", "unit_price": "3.333" } ] }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{dual}");
    assert_eq!(
        dec(&dual["match_report"]["lines"][1]["invoiced_quantity"]),
        q("2")
    );

    // Disputing the first invoice frees its 6 frames again.
    let (status, _) = e
        .act(FIN, &first["id"], "dispute", json!({ "reason": "wrong" }))
        .await;
    assert_eq!(status, StatusCode::OK);
    let (_, third) = get(
        &e.app,
        FIN,
        &format!("/supplier-invoices/{}", third["id"].as_str().unwrap()),
    )
    .await;
    assert_eq!(
        dec(&third["match_report"]["lines"][0]["invoiced_quantity"]),
        q("5")
    );
    assert_eq!(line_status(&third, 0), "ok");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn invoice_number_is_unique_per_supplier_and_input_is_validated(db: PgPool) {
    let e = env(db).await;
    let s1 = e.supplier("S1").await;
    let s2 = e.supplier("S2").await;
    let body = |supplier: &str, number: &str| {
        json!({ "supplier_id": supplier, "invoice_number": number, "invoice_date": "2027-02-01",
                "lines": [{ "description": "Freight", "quantity": "1", "unit_price": "50", "vat_rate": "21" }] })
    };
    let (status, a) = post(&e.app, FIN, "/supplier-invoices", body(&s1, "INV-1")).await;
    assert_eq!(status, StatusCode::CREATED, "{a}");
    // Free text line: flagged, not matched; VAT is computed.
    assert_eq!(line_status(&a, 0), "no_po_line");
    assert_eq!(a["match_report"]["matched"], false);
    assert_eq!(dec(&a["vat_total"]), q("10.50"));
    assert_eq!(dec(&a["gross_total"]), q("60.50"));
    let (status, dup) = post(&e.app, FIN, "/supplier-invoices", body(&s1, "INV-1")).await;
    assert_eq!(status, StatusCode::CONFLICT, "{dup}");
    let (status, _) = post(&e.app, FIN, "/supplier-invoices", body(&s2, "INV-1")).await;
    assert_eq!(status, StatusCode::CREATED);
    // Changing a draft to an existing number conflicts too.
    let (_, b) = post(&e.app, FIN, "/supplier-invoices", body(&s1, "INV-2")).await;
    let (status, _) = put(
        &e.app,
        FIN,
        &format!("/supplier-invoices/{}", b["id"].as_str().unwrap()),
        json!({ "invoice_number": "INV-1" }),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);

    // Validation.
    for bad in [
        json!({ "invoice_number": "", "supplier_id": s1, "invoice_date": "2027-02-01",
                "lines": [{ "description": "x", "quantity": "1", "unit_price": "1" }] }),
        json!({ "invoice_number": "X", "invoice_date": "2027-02-01",
                "lines": [{ "description": "x", "quantity": "1", "unit_price": "1" }] }),
        json!({ "invoice_number": "X", "supplier_id": s1, "invoice_date": "2027-02-01", "lines": [] }),
        json!({ "invoice_number": "X", "supplier_id": s1, "invoice_date": "2027-02-01",
                "lines": [{ "description": "x", "quantity": "0", "unit_price": "1" }] }),
        json!({ "invoice_number": "X", "supplier_id": s1, "invoice_date": "2027-02-01",
                "lines": [{ "quantity": "1", "unit_price": "1" }] }),
        json!({ "invoice_number": "X", "supplier_id": s1, "invoice_date": "2027-02-01",
                "lines": [{ "purchase_order_line_id": Uuid::now_v7(), "quantity": "1", "unit_price": "1" }] }),
    ] {
        let (status, r) = post(&e.app, FIN, "/supplier-invoices", bad).await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{r}");
    }
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn an_invoice_must_use_the_currency_and_supplier_of_its_order(db: PgPool) {
    let e = env(db).await;
    let s1 = e.supplier("S1").await;
    let s2 = e.supplier("S2").await;
    let po = e.po(&s1).await;
    e.receive(&po, "10", "4.5").await;
    let (status, r) = post(
        &e.app,
        FIN,
        "/supplier-invoices",
        json!({ "purchase_order_id": po["id"], "invoice_number": "X", "invoice_date": "2027-02-01",
                "currency": "usd" }),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{r}");
    let (status, r) = post(
        &e.app,
        FIN,
        "/supplier-invoices",
        json!({ "purchase_order_id": po["id"], "supplier_id": s2, "invoice_number": "X",
                "invoice_date": "2027-02-01" }),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{r}");
    // A line of some other order is not on this order.
    let other = e.po(&s1).await;
    let (status, r) = post(
        &e.app,
        FIN,
        "/supplier-invoices",
        json!({ "purchase_order_id": po["id"], "invoice_number": "X", "invoice_date": "2027-02-01",
                "lines": [{ "purchase_order_line_id": other["lines"][0]["id"],
                            "quantity": "1", "unit_price": "12.50" }] }),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{r}");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn dispute_reopen_and_payment_lifecycle(db: PgPool) {
    let e = env(db).await;
    let s = e.supplier("S1").await;
    let po = e.po(&s).await;
    e.receive(&po, "10", "4.5").await;
    let inv = e.invoice(&po, "INV-1", &[(0, "10", "12.50")]).await;
    let id = &inv["id"];

    // Paying needs an approved invoice.
    let (status, _) = e.act(FIN, id, "mark-paid", json!({})).await;
    assert_eq!(status, StatusCode::CONFLICT);
    // A dispute needs a reason.
    let (status, _) = e.act(FIN, id, "dispute", json!({ "reason": " " })).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    let (status, d) = e
        .act(FIN, id, "dispute", json!({ "reason": "Wrong quantity" }))
        .await;
    assert_eq!(status, StatusCode::OK, "{d}");
    assert_eq!(d["status"], "disputed");
    assert_eq!(d["dispute_reason"], "Wrong quantity");
    // Disputed: not editable, not approvable, not matchable; reopen makes it a draft again.
    for what in ["approve", "submit-match", "mark-paid"] {
        let (status, _) = e.act(FIN, id, what, json!({})).await;
        assert_eq!(status, StatusCode::CONFLICT, "{what}");
    }
    let (status, r) = e.act(FIN, id, "reopen", json!({})).await;
    assert_eq!(status, StatusCode::OK, "{r}");
    assert_eq!(r["status"], "draft");
    assert_eq!(r["dispute_reason"], "");

    let (_, _) = e.act(FIN, id, "submit-match", json!({})).await;
    let (status, a) = e.act(FIN, id, "approve", json!({})).await;
    assert_eq!(status, StatusCode::OK, "{a}");
    // An approved invoice can still be disputed (the approval is withdrawn)...
    let (status, d) = e
        .act(FIN, id, "dispute", json!({ "reason": "Credit note due" }))
        .await;
    assert_eq!(status, StatusCode::OK, "{d}");
    assert!(d["approved_at"].is_null());
    e.act(FIN, id, "reopen", json!({})).await;
    e.act(FIN, id, "approve", json!({})).await;

    let (status, p) = e
        .act(
            FIN,
            id,
            "mark-paid",
            json!({ "paid_at": "2027-03-10", "payment_reference": " BANK-77 " }),
        )
        .await;
    assert_eq!(status, StatusCode::OK, "{p}");
    assert_eq!(p["status"], "paid");
    assert_eq!(p["paid_at"], "2027-03-10");
    assert_eq!(p["payment_reference"], "BANK-77");
    // Paid is final.
    for what in ["approve", "dispute", "reopen", "mark-paid", "submit-match"] {
        let (status, _) = e.act(FIN, id, what, json!({ "reason": "x" })).await;
        assert_eq!(status, StatusCode::CONFLICT, "{what}");
    }
    for action in ["disputed", "reopened", "paid"] {
        assert!(e.audit_count(id, action).await >= 1, "{action}");
    }
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn only_drafts_can_be_edited_or_deleted(db: PgPool) {
    let e = env(db).await;
    let s = e.supplier("S1").await;
    let po = e.po(&s).await;
    e.receive(&po, "10", "4.5").await;
    let inv = e.invoice(&po, "INV-1", &[(0, "5", "12.50")]).await;
    let uri = format!("/supplier-invoices/{}", inv["id"].as_str().unwrap());

    // Replace the lines of the draft; the totals follow.
    let (status, u) = put(
        &e.app,
        FIN,
        &uri,
        json!({ "notes": " checked ", "lines": [
            { "purchase_order_line_id": po["lines"][0]["id"], "quantity": "10", "unit_price": "12.50", "vat_rate": "21" } ] }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{u}");
    assert_eq!(u["notes"], "checked");
    assert_eq!(u["lines"].as_array().unwrap().len(), 1);
    assert_eq!(dec(&u["gross_total"]), q("151.25"));
    assert_eq!(u["match_report"]["matched"], true);

    e.act(FIN, &inv["id"], "submit-match", json!({})).await;
    let (status, _) = put(&e.app, FIN, &uri, json!({ "notes": "late" })).await;
    assert_eq!(status, StatusCode::CONFLICT);
    let (status, _) = send(&e.app, FIN, Method::DELETE, &uri, None).await;
    assert_eq!(status, StatusCode::CONFLICT);

    let draft = e.invoice(&po, "INV-2", &[(1, "1", "3.333")]).await;
    let uri2 = format!("/supplier-invoices/{}", draft["id"].as_str().unwrap());
    let (status, _) = send(&e.app, FIN, Method::DELETE, &uri2, None).await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    let (status, _) = get(&e.app, FIN, &uri2).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    assert_eq!(e.audit_count(&draft["id"], "deleted").await, 1);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn permissions_follow_the_roles(db: PgPool) {
    let e = env(db).await;
    let s = e.supplier("S1").await;
    let po = e.po(&s).await;
    e.receive(&po, "10", "4.5").await;
    let inv = e.invoice(&po, "INV-1", &[(0, "10", "12.50")]).await;
    let id = inv["id"].as_str().unwrap();
    let new = json!({ "purchase_order_id": po["id"], "invoice_number": "N", "invoice_date": "2027-02-01" });

    // Admin and finance can do everything; the purchaser and the viewer can only read.
    for user in [ADMIN, FIN, BUYER, VIEWER] {
        let (status, _) = get(&e.app, user, "/supplier-invoices").await;
        assert_eq!(status, StatusCode::OK, "{user}");
        let (status, _) = get(&e.app, user, &format!("/supplier-invoices/{id}")).await;
        assert_eq!(status, StatusCode::OK, "{user}");
        let (status, _) = get(&e.app, user, "/finance/settings").await;
        assert_eq!(status, StatusCode::OK, "{user}");
    }
    for user in [SALES, STORES] {
        let (status, _) = get(&e.app, user, "/supplier-invoices").await;
        assert_eq!(status, StatusCode::FORBIDDEN, "{user}");
        let (status, _) = get(&e.app, user, &format!("/supplier-invoices/{id}")).await;
        assert_eq!(status, StatusCode::FORBIDDEN, "{user}");
        let (status, _) = get(&e.app, user, "/finance/settings").await;
        assert_eq!(status, StatusCode::FORBIDDEN, "{user}");
    }
    for user in [BUYER, SALES, VIEWER, STORES] {
        let (status, _) = post(&e.app, user, "/supplier-invoices", new.clone()).await;
        assert_eq!(status, StatusCode::FORBIDDEN, "{user}");
        let (status, _) = put(&e.app, user, &format!("/supplier-invoices/{id}"), json!({})).await;
        assert_eq!(status, StatusCode::FORBIDDEN, "{user}");
        let (status, _) = send(
            &e.app,
            user,
            Method::DELETE,
            &format!("/supplier-invoices/{id}"),
            None,
        )
        .await;
        assert_eq!(status, StatusCode::FORBIDDEN, "{user}");
        for what in ["submit-match", "approve", "dispute", "reopen", "mark-paid"] {
            let (status, _) = post(
                &e.app,
                user,
                &format!("/supplier-invoices/{id}/{what}"),
                json!({ "reason": "x" }),
            )
            .await;
            assert_eq!(status, StatusCode::FORBIDDEN, "{user} {what}");
        }
        let (status, _) = put(
            &e.app,
            user,
            "/finance/settings",
            json!({ "price_tolerance_pct": "3" }),
        )
        .await;
        assert_eq!(status, StatusCode::FORBIDDEN, "{user}");
    }
    let (status, _) = post(&e.app, ADMIN, "/supplier-invoices", new).await;
    assert_eq!(status, StatusCode::CREATED);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn invoices_and_settings_are_isolated_per_company(db: PgPool) {
    let e = env(db).await;
    let s = e.supplier("S1").await;
    let po = e.po(&s).await;
    e.receive(&po, "10", "4.5").await;
    let inv = e.invoice(&po, "INV-1", &[(0, "10", "12.50")]).await;
    let uri = format!("/supplier-invoices/{}", inv["id"].as_str().unwrap());
    put(
        &e.app,
        FIN,
        "/finance/settings",
        json!({ "price_tolerance_pct": "7" }),
    )
    .await;

    sqlx::query("INSERT INTO core.companies (id, name) VALUES ($1::uuid, 'Other BV')")
        .bind(OTHER_COMPANY)
        .execute(&e.db)
        .await
        .unwrap();
    add_user(&e.db, OTHER_FIN, "finance", OTHER_COMPANY).await;

    let (status, list) = get(&e.app, OTHER_FIN, "/supplier-invoices").await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(list["total"], 0);
    let (status, _) = get(&e.app, OTHER_FIN, &uri).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, _) = e
        .act(
            OTHER_FIN,
            &inv["id"],
            "approve",
            json!({ "override_reason": "x" }),
        )
        .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, _) = post(
        &e.app,
        OTHER_FIN,
        "/supplier-invoices",
        json!({ "purchase_order_id": po["id"], "invoice_number": "Z", "invoice_date": "2027-02-01" }),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    // Their settings are the defaults, not ours.
    let (_, st) = get(&e.app, OTHER_FIN, "/finance/settings").await;
    assert_eq!(dec(&st["price_tolerance_pct"]), q("2"));
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn settings_have_defaults_validation_and_audit(db: PgPool) {
    let e = env(db).await;
    let (status, s) = get(&e.app, FIN, "/finance/settings").await;
    assert_eq!(status, StatusCode::OK, "{s}");
    assert_eq!(dec(&s["quantity_tolerance_pct"]), q("0"));
    assert_eq!(dec(&s["price_tolerance_pct"]), q("2"));
    assert!(s["updated_at"].is_null());

    let (status, s) = put(
        &e.app,
        FIN,
        "/finance/settings",
        json!({ "price_tolerance_pct": "3.5" }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{s}");
    assert_eq!(dec(&s["price_tolerance_pct"]), q("3.5"));
    assert_eq!(dec(&s["quantity_tolerance_pct"]), q("0"));
    assert!(s["updated_at"].is_string());
    // Each update only touches what it sets.
    let qty = json!({ "quantity_tolerance_pct": "5" });
    put(&e.app, FIN, "/finance/settings", qty).await;
    let price = json!({ "price_tolerance_pct": "4" });
    let (_, s) = put(&e.app, FIN, "/finance/settings", price).await;
    assert_eq!(dec(&s["quantity_tolerance_pct"]), q("5"));
    assert_eq!(dec(&s["price_tolerance_pct"]), q("4"));
    let (_, s) = put(&e.app, FIN, "/finance/settings", json!({})).await;
    assert_eq!(dec(&s["quantity_tolerance_pct"]), q("5"));
    assert_eq!(dec(&s["price_tolerance_pct"]), q("4"));
    for bad in [
        json!({ "price_tolerance_pct": "-1" }),
        json!({ "quantity_tolerance_pct": "101" }),
    ] {
        let (status, _) = put(&e.app, FIN, "/finance/settings", bad).await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    }
    let n: i64 =
        sqlx::query_scalar("SELECT count(*) FROM audit.events WHERE entity = 'finance_settings'")
            .fetch_one(&e.db)
            .await
            .unwrap();
    assert_eq!(n, 4);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn invoices_are_listed_with_filters_and_paging(db: PgPool) {
    let e = env(db).await;
    let s1 = e.supplier("S1").await;
    let s2 = e.supplier("S2").await;
    let po = e.po(&s1).await;
    e.receive(&po, "10", "4.5").await;
    let a = e.invoice(&po, "ALPHA-1", &[(0, "10", "12.50")]).await;
    e.act(FIN, &a["id"], "submit-match", json!({})).await;
    for n in ["BETA-1", "BETA-2"] {
        let (status, r) = post(
            &e.app,
            FIN,
            "/supplier-invoices",
            json!({ "supplier_id": s2, "invoice_number": n, "invoice_date": "2027-02-01",
                    "lines": [{ "description": "Service", "quantity": "1", "unit_price": "10" }] }),
        )
        .await;
        assert_eq!(status, StatusCode::CREATED, "{r}");
    }
    let total = |v: &Value| v["total"].as_i64().unwrap();
    let (_, all) = get(&e.app, BUYER, "/supplier-invoices").await;
    assert_eq!(total(&all), 3);
    assert_eq!(all["items"][0]["supplier_name"], "Supplier S2"); // newest first
    let (_, by_status) = get(&e.app, FIN, "/supplier-invoices?status=matched").await;
    assert_eq!(total(&by_status), 1);
    let (_, by_supplier) = get(&e.app, FIN, &format!("/supplier-invoices?supplier_id={s2}")).await;
    assert_eq!(total(&by_supplier), 2);
    let po_id = po["id"].as_str().unwrap();
    let (_, by_po) = get(
        &e.app,
        FIN,
        &format!("/supplier-invoices?purchase_order_id={po_id}"),
    )
    .await;
    assert_eq!(total(&by_po), 1);
    assert_eq!(by_po["items"][0]["purchase_order_number"], po["number"]);
    let (_, by_q) = get(&e.app, FIN, "/supplier-invoices?q=beta").await;
    assert_eq!(total(&by_q), 2);
    let (_, by_q) = get(&e.app, FIN, "/supplier-invoices?q=%25").await;
    assert_eq!(total(&by_q), 0, "wildcards are escaped");
    let (_, page) = get(&e.app, FIN, "/supplier-invoices?limit=1&offset=1").await;
    assert_eq!(total(&page), 3);
    assert_eq!(page["items"].as_array().unwrap().len(), 1);
    let (status, _) = get(&e.app, FIN, "/supplier-invoices?status=bogus").await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
}

/// The app sends dates as `DateTime.toIso8601String()` (`2027-02-01T00:00:00.000`); the invoice
/// inputs must accept that like the purchasing ones do (create, update and mark paid).
#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn dates_accept_the_date_time_format_the_app_sends(db: PgPool) {
    let e = env(db).await;
    let s1 = e.supplier("S1").await;
    let (status, inv) = post(
        &e.app,
        FIN,
        "/supplier-invoices",
        json!({ "supplier_id": s1, "invoice_number": "INV-D",
                "invoice_date": "2027-02-01T00:00:00.000", "due_date": "2027-03-01T00:00:00.000",
                "lines": [{ "description": "Freight", "quantity": "1", "unit_price": "50", "vat_rate": "21" }] }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{inv}");
    assert_eq!(inv["invoice_date"], "2027-02-01");
    assert_eq!(inv["due_date"], "2027-03-01");
    let id = inv["id"].as_str().unwrap().to_string();

    let (status, updated) = put(
        &e.app,
        FIN,
        &format!("/supplier-invoices/{id}"),
        json!({ "invoice_date": "2027-02-02T00:00:00.000", "due_date": "2027-03-02T00:00:00.000" }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{updated}");
    assert_eq!(updated["invoice_date"], "2027-02-02");
    assert_eq!(updated["due_date"], "2027-03-02");

    let (status, approved) = post(
        &e.app,
        FIN,
        &format!("/supplier-invoices/{id}/approve"),
        json!({ "override_reason": "free text freight line" }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{approved}");
    let (status, paid) = post(
        &e.app,
        FIN,
        &format!("/supplier-invoices/{id}/mark-paid"),
        json!({ "paid_at": "2027-03-05T00:00:00.000", "payment_reference": "BANK-1" }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{paid}");
    assert_eq!(paid["status"], "paid");
}
