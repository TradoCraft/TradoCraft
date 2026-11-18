//! Order lifecycle: draft, revisions, order confirmation by e-mail, confirmation by staff or by
//! the customer in the portal, priority with history and customer requests.

mod common;

use axum::http::{Method, StatusCode};
use common::{call, call_portal, portal_login, raw, setup, Who};
use serde_json::{json, Value};
use sqlx::PgPool;
use tradocraft_helpdesk::mailer::{process_system_mail, Mailer};

const ALPHA: &str = "00000000-0000-7000-8000-000000000401"; // info@alpha.example, nl
const GAMMA: &str = "00000000-0000-7000-8000-000000000403"; // office@gamma.example, en
const UNIT_100: &str = "00000000-0000-7000-8000-000000000301";
const SALES: &str = "sales@example.com";
const SUPPORT: &str = "support@example.com";
const JAN: &str = "jan.peeters@alpha.example"; // Alpha, scope customer
const SOFIE: &str = "sofie.maes@alpha.example"; // Alpha, scope own
const MARIE: &str = "marie.dupont@beta.example"; // Beta
const JAN_ID: &str = "00000000-0000-7000-8000-000000000601";

async fn staff(
    app: &axum::Router,
    method: Method,
    uri: &str,
    body: Option<Value>,
) -> (StatusCode, Value) {
    call(app, SALES, method, &format!("/api/v1{uri}"), body).await
}

/// A draft order for the customer (quotation sent, then converted).
async fn draft_order(app: &axum::Router, customer: &str, quantity: &str) -> Value {
    let (status, q) = staff(
        app,
        Method::POST,
        "/quotations",
        Some(json!({ "customer_id": customer, "lines": [{ "product_id": UNIT_100, "quantity": quantity }] })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{q}");
    let qid = q["id"].as_str().unwrap();
    let (status, _) = staff(app, Method::POST, &format!("/quotations/{qid}/send"), None).await;
    assert_eq!(status, StatusCode::OK);
    let (status, o) = staff(
        app,
        Method::POST,
        &format!("/quotations/{qid}/convert"),
        Some(json!({ "customer_reference": "PO-1" })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{o}");
    o
}

fn id(o: &Value) -> String {
    o["order"]["id"].as_str().unwrap().to_string()
}

async fn send(app: &axum::Router, order: &str) -> Value {
    let (status, o) = staff(app, Method::POST, &format!("/orders/{order}/send"), None).await;
    assert_eq!(status, StatusCode::OK, "{o}");
    o
}

async fn portal(
    app: &axum::Router,
    token: &str,
    method: Method,
    uri: &str,
    body: Option<Value>,
) -> (StatusCode, Value) {
    call_portal(
        app,
        Some(token),
        method,
        &format!("/api/v1/portal{uri}"),
        body,
    )
    .await
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn converting_creates_a_draft_revision_one_that_can_be_edited(db: PgPool) {
    let app = setup(db).await;
    let o = draft_order(&app, ALPHA, "2").await;
    assert_eq!(o["order"]["status"], "draft");
    assert_eq!(o["order"]["current_revision"], 1);
    assert_eq!(o["order"]["priority"], "normal");
    assert_eq!(o["revision"], 1);
    assert_eq!(o["revision_status"], "draft");
    let line = &o["lines"][0];
    let before = common::dec(&o["order"]["total"]);

    // Doubling the quantity doubles the total; the server does the sums.
    let (status, e) = staff(
        &app,
        Method::PUT,
        &format!("/orders/{}", id(&o)),
        Some(
            json!({ "customer_reference": "PO-2", "notes": "internal", "lines": [
            { "position": 1, "quantity": "4", "description": "Pump, blue" } ] }),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{e}");
    assert_eq!(
        common::dec(&e["order"]["total"]),
        before * rust_decimal::Decimal::TWO
    );
    assert_eq!(e["lines"][0]["description"], "Pump, blue");
    assert_eq!(
        e["lines"][0]["list_unit_price"], line["list_unit_price"],
        "agreed prices stay"
    );
    assert_eq!(e["order"]["customer_reference"], "PO-2");
    assert_eq!(e["notes"], "internal");
    assert_eq!(e["revisions"].as_array().unwrap().len(), 1);

    // Unknown lines, empty orders and bad quantities are refused.
    for lines in [
        json!([{ "position": 9, "quantity": "1" }]),
        json!([]),
        json!([{ "position": 1, "quantity": "0" }]),
    ] {
        let (status, _) = staff(
            &app,
            Method::PUT,
            &format!("/orders/{}", id(&o)),
            Some(json!({ "lines": lines })),
        )
        .await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    }
    // The list shows the order and can filter on status.
    let (_, page) = staff(&app, Method::GET, "/orders?status=draft", None).await;
    assert_eq!(page["total"], 1);
    let (_, page) = staff(&app, Method::GET, "/orders?status=confirmed", None).await;
    assert_eq!(page["total"], 0);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn sending_queues_a_mail_with_the_pdf_and_freezes_the_draft(db: PgPool) {
    let (app, blobs) = common::setup_with_blobs(db.clone()).await;
    let o = draft_order(&app, ALPHA, "1").await;
    let oid = id(&o);
    let s = send(&app, &oid).await;
    assert_eq!(s["order"]["status"], "sent");
    assert_eq!(s["revision_status"], "sent");
    assert_eq!(s["revisions"][0]["sent_to"], "info@alpha.example");

    let (to, subject, body, name, kind, storage_key): (
        String,
        String,
        String,
        String,
        String,
        String,
    ) = sqlx::query_as(
        "SELECT to_address, subject, body, attachment_name, attachment_type, attachment_storage_key
         FROM core.mail_outbox WHERE attachment_name IS NOT NULL",
    )
    .fetch_one(&db)
    .await
    .unwrap();
    let number = o["order"]["number"].as_str().unwrap();
    assert_eq!(to, "info@alpha.example");
    assert!(
        subject.starts_with("Orderbevestiging SO"),
        "customer language: {subject}"
    );
    assert!(body.contains(number));
    assert_eq!(name, format!("{number}-r1.pdf"));
    assert_eq!(kind, "application/pdf");
    let pdf_bytes = blobs.get(&storage_key).await.unwrap();
    assert!(pdf_bytes.len() > 1000);
    assert_eq!(&pdf_bytes[..4], b"%PDF");

    // The worker sends it as a multipart message with the attachment.
    let dir = tempfile::tempdir().unwrap();
    let sent = process_system_mail(&db, &blobs, &Mailer::Files(dir.path().to_path_buf()), 10)
        .await
        .unwrap();
    assert_eq!(sent, 1);
    let eml = std::fs::read_to_string(
        std::fs::read_dir(dir.path())
            .unwrap()
            .next()
            .unwrap()
            .unwrap()
            .path(),
    )
    .unwrap();
    assert!(
        eml.contains("multipart/mixed")
            && eml.contains("application/pdf")
            && eml.contains(&format!("{number}-r1.pdf"))
    );

    // A sent revision cannot be edited or sent again.
    let (status, _) = staff(
        &app,
        Method::PUT,
        &format!("/orders/{oid}"),
        Some(json!({ "lines": [{ "position": 1, "quantity": "3" }] })),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
    let (status, _) = staff(&app, Method::POST, &format!("/orders/{oid}/send"), None).await;
    assert_eq!(status, StatusCode::CONFLICT);

    // The PDF can be downloaded.
    let (status, headers, bytes) = raw(
        &app,
        Who::Staff(SALES),
        Method::GET,
        &format!("/api/v1/orders/{oid}/revisions/1/pdf"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(headers["content-type"], "application/pdf");
    assert_eq!(&bytes[..4], b"%PDF");
    let (status, ..) = raw(
        &app,
        Who::Staff(SALES),
        Method::GET,
        &format!("/api/v1/orders/{oid}/revisions/7/pdf"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_recipient_is_the_ticket_contact_and_without_an_address_sending_is_refused(db: PgPool) {
    let app = setup(db.clone()).await;
    // No address at all.
    sqlx::query("UPDATE crm.customers SET email = NULL WHERE id = $1::uuid")
        .bind(GAMMA)
        .execute(&db)
        .await
        .unwrap();
    let o = draft_order(&app, GAMMA, "1").await;
    let (status, e) = staff(
        &app,
        Method::POST,
        &format!("/orders/{}/send", id(&o)),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT, "{e}");
    assert!(e["message"].as_str().unwrap().contains("e-mail address"));
    let (_, again) = staff(&app, Method::GET, &format!("/orders/{}", id(&o)), None).await;
    assert_eq!(again["order"]["status"], "draft", "nothing changed");

    // A ticket with a contact on the order: the mail goes to that person, in their language.
    let o = draft_order(&app, ALPHA, "1").await;
    let (status, t) = call(&app, SUPPORT, Method::POST, "/api/v1/tickets", Some(json!({
        "subject": "Order", "language": "nl", "customer_id": ALPHA, "contact_id": JAN_ID, "body": "Please confirm",
        "category": "order_confirmation" }))).await;
    assert_eq!(status, StatusCode::CREATED, "{t}");
    sqlx::query("UPDATE helpdesk.tickets SET order_id = $1::uuid WHERE id = $2::uuid")
        .bind(id(&o))
        .bind(t["ticket"]["id"].as_str().unwrap())
        .execute(&db)
        .await
        .unwrap();
    let s = send(&app, &id(&o)).await;
    assert_eq!(s["revisions"][0]["sent_to"], JAN);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_new_revision_supersedes_the_sent_one_and_only_the_latest_can_be_confirmed(db: PgPool) {
    let app = setup(db.clone()).await;
    let o = draft_order(&app, ALPHA, "1").await;
    let oid = id(&o);

    // A draft cannot be revised or confirmed.
    let (status, _) = staff(
        &app,
        Method::POST,
        &format!("/orders/{oid}/revisions"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
    let (status, _) = staff(
        &app,
        Method::POST,
        &format!("/orders/{oid}/confirm"),
        Some(json!({})),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);

    send(&app, &oid).await;
    let (status, r2) = staff(
        &app,
        Method::POST,
        &format!("/orders/{oid}/revisions"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{r2}");
    assert_eq!(r2["revision"], 2);
    assert_eq!(r2["revision_status"], "draft");
    assert_eq!(r2["order"]["status"], "draft");
    assert_eq!(r2["revisions"][0]["status"], "superseded");
    assert_eq!(r2["lines"].as_array().unwrap().len(), 1);

    // Revision 1 is kept and readable.
    let (_, old) = staff(
        &app,
        Method::GET,
        &format!("/orders/{oid}/revisions/1"),
        None,
    )
    .await;
    assert_eq!(old["revision_status"], "superseded");

    let (status, _) = staff(
        &app,
        Method::PUT,
        &format!("/orders/{oid}"),
        Some(json!({ "lines": [{ "position": 1, "quantity": "5" }] })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (_, old) = staff(
        &app,
        Method::GET,
        &format!("/orders/{oid}/revisions/1"),
        None,
    )
    .await;
    assert_eq!(
        old["lines"][0]["quantity"], o["lines"][0]["quantity"],
        "the old revision is untouched"
    );

    // Confirming the old revision is refused, also once revision 2 is sent.
    let (status, e) = staff(
        &app,
        Method::POST,
        &format!("/orders/{oid}/confirm"),
        Some(json!({ "revision": 1 })),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT, "{e}");
    send(&app, &oid).await;
    let (status, _) = staff(
        &app,
        Method::POST,
        &format!("/orders/{oid}/confirm"),
        Some(json!({ "revision": 1 })),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);

    // Staff confirm on the customer's behalf.
    let (status, c) = staff(
        &app,
        Method::POST,
        &format!("/orders/{oid}/confirm"),
        Some(json!({ "revision": 2, "note": "By phone" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{c}");
    assert_eq!(c["order"]["status"], "confirmed");
    assert_eq!(c["confirmed_via"], "staff");
    assert_eq!(c["confirmed_revision"], 2);
    assert_eq!(c["confirmation_note"], "By phone");
    assert!(c["confirmed_at"].is_string() && c["confirmed_by"].is_string());

    // A confirmed order is frozen.
    for (method, uri, body) in [
        (Method::POST, format!("/orders/{oid}/revisions"), None),
        (
            Method::PUT,
            format!("/orders/{oid}"),
            Some(json!({ "lines": [{ "position": 1, "quantity": "1" }] })),
        ),
        (Method::POST, format!("/orders/{oid}/send"), None),
        (
            Method::POST,
            format!("/orders/{oid}/confirm"),
            Some(json!({})),
        ),
    ] {
        let (status, _) = staff(&app, method, &uri, body).await;
        assert_eq!(status, StatusCode::CONFLICT, "{uri}");
    }
    let n: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM audit.events WHERE entity = 'order' AND action = 'confirmed'",
    )
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(n, 1);

    // Cancelling needs a reason and works until shipping.
    let (status, _) = staff(
        &app,
        Method::POST,
        &format!("/orders/{oid}/cancel"),
        Some(json!({ "reason": " " })),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    let (status, x) = staff(
        &app,
        Method::POST,
        &format!("/orders/{oid}/cancel"),
        Some(json!({ "reason": "Customer withdrew" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{x}");
    assert_eq!(x["order"]["status"], "cancelled");
    let (status, _) = staff(
        &app,
        Method::POST,
        &format!("/orders/{oid}/cancel"),
        Some(json!({ "reason": "again" })),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_portal_shows_sent_orders_of_the_own_customer_and_lets_the_customer_confirm(
    db: PgPool,
) {
    let app = setup(db.clone()).await;
    let jan = portal_login(&app, &db, JAN).await;
    let sofie = portal_login(&app, &db, SOFIE).await;
    let marie = portal_login(&app, &db, MARIE).await;
    let o = draft_order(&app, ALPHA, "1").await;
    let oid = id(&o);

    // Drafts are invisible.
    let (_, list) = portal(&app, &jan, Method::GET, "/orders", None).await;
    assert_eq!(list, json!([]));
    let (status, _) = portal(&app, &jan, Method::GET, &format!("/orders/{oid}"), None).await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    send(&app, &oid).await;
    let (_, list) = portal(&app, &jan, Method::GET, "/orders", None).await;
    assert_eq!(list.as_array().unwrap().len(), 1);
    assert_eq!(list[0]["status"], "sent");
    assert_eq!(list[0]["can_confirm"], true);
    let (status, d) = portal(&app, &jan, Method::GET, &format!("/orders/{oid}"), None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(d["lines"].as_array().unwrap().len(), 1);
    assert!(
        d.get("notes").is_none() && d["order"].get("notes").is_none(),
        "no internal notes"
    );

    // Another customer's order is "not found" for everything; so is it for a colleague who was
    // not sent the order when their scope is `own`.
    for token in [&marie, &sofie] {
        let (status, _) = portal(&app, token, Method::GET, &format!("/orders/{oid}"), None).await;
        assert_eq!(status, StatusCode::NOT_FOUND);
        let (status, _) = portal(
            &app,
            token,
            Method::POST,
            &format!("/orders/{oid}/confirm"),
            Some(json!({ "revision": 1 })),
        )
        .await;
        assert_eq!(status, StatusCode::NOT_FOUND);
        let (status, _) = portal(
            &app,
            token,
            Method::POST,
            &format!("/orders/{oid}/priority-requests"),
            Some(json!({ "priority": "expedite", "message": "x" })),
        )
        .await;
        assert_eq!(status, StatusCode::NOT_FOUND);
    }
    let (_, list) = portal(&app, &marie, Method::GET, "/orders", None).await;
    assert_eq!(list, json!([]));
    let (status, _) = call_portal(&app, None, Method::GET, "/api/v1/portal/orders", None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);

    // A newer draft revision is not shown; the customer still sees revision 1, which can no
    // longer be confirmed.
    staff(
        &app,
        Method::POST,
        &format!("/orders/{oid}/revisions"),
        None,
    )
    .await;
    let (_, d) = portal(&app, &jan, Method::GET, &format!("/orders/{oid}"), None).await;
    assert_eq!(d["order"]["revision"], 1);
    let (status, e) = portal(
        &app,
        &jan,
        Method::POST,
        &format!("/orders/{oid}/confirm"),
        Some(json!({ "revision": 1 })),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT, "{e}");

    staff(
        &app,
        Method::PUT,
        &format!("/orders/{oid}"),
        Some(json!({ "lines": [{ "position": 1, "quantity": "3" }] })),
    )
    .await;
    send(&app, &oid).await;
    let (_, d) = portal(&app, &jan, Method::GET, &format!("/orders/{oid}"), None).await;
    assert_eq!(d["order"]["revision"], 2);
    // The stale revision is still refused, the current one is accepted.
    let (status, _) = portal(
        &app,
        &jan,
        Method::POST,
        &format!("/orders/{oid}/confirm"),
        Some(json!({ "revision": 1 })),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
    let (status, c) = portal(
        &app,
        &jan,
        Method::POST,
        &format!("/orders/{oid}/confirm"),
        Some(json!({ "revision": 2, "note": "Thanks" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{c}");
    assert_eq!(c["order"]["status"], "confirmed");
    assert_eq!(c["order"]["can_confirm"], false);
    let (_, full) = staff(&app, Method::GET, &format!("/orders/{oid}"), None).await;
    assert_eq!(full["confirmed_via"], "portal");
    assert_eq!(full["confirmed_by"], JAN_ID);
    assert_eq!(full["confirmed_revision"], 2);
    let (status, _) = portal(
        &app,
        &jan,
        Method::POST,
        &format!("/orders/{oid}/confirm"),
        Some(json!({ "revision": 2 })),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT, "confirmed only once");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn changing_the_priority_needs_a_reason_and_is_kept_in_a_history(db: PgPool) {
    let app = setup(db.clone()).await;
    let o = draft_order(&app, ALPHA, "1").await;
    let oid = id(&o);
    for body in [
        json!({ "priority": "expedite" }),
        json!({ "priority": "expedite", "reason": "  " }),
    ] {
        let (status, _) = staff(
            &app,
            Method::PUT,
            &format!("/orders/{oid}/priority"),
            Some(body),
        )
        .await;
        assert!(
            status == StatusCode::UNPROCESSABLE_ENTITY || status == StatusCode::BAD_REQUEST,
            "{status}"
        );
    }
    let (status, _) = staff(
        &app,
        Method::PUT,
        &format!("/orders/{oid}/priority"),
        Some(json!({ "priority": "urgent", "reason": "x" })),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    let (status, _) = staff(
        &app,
        Method::PUT,
        &format!("/orders/{oid}/priority"),
        Some(json!({ "priority": "normal", "reason": "same" })),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    let (status, p) = staff(
        &app,
        Method::PUT,
        &format!("/orders/{oid}/priority"),
        Some(json!({ "priority": "expedite", "reason": "Customer line is down" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{p}");
    assert_eq!(p["order"]["priority"], "expedite");
    staff(
        &app,
        Method::PUT,
        &format!("/orders/{oid}/priority"),
        Some(json!({ "priority": "low", "reason": "Customer can wait" })),
    )
    .await;

    let (status, h) = staff(
        &app,
        Method::GET,
        &format!("/orders/{oid}/priority-history"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(h.as_array().unwrap().len(), 2);
    assert_eq!(h[0]["old_priority"], "normal");
    assert_eq!(h[0]["new_priority"], "expedite");
    assert_eq!(h[0]["reason"], "Customer line is down");
    assert_eq!(h[0]["changed_by_name"], "Sales User");
    assert_eq!(h[1]["new_priority"], "low");
    let n: i64 = sqlx::query_scalar("SELECT count(*) FROM audit.events WHERE action = 'priority_changed' AND entity_id = $1::uuid")
        .bind(&oid)
        .fetch_one(&db)
        .await
        .unwrap();
    assert_eq!(n, 2);

    // Without the right permission nothing changes (the technician has no orders rights).
    let (status, _) = call(
        &app,
        "technician@example.com",
        Method::PUT,
        &format!("/api/v1/orders/{oid}/priority"),
        Some(json!({ "priority": "normal", "reason": "x" })),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    // Other companies' orders do not exist.
    let (status, _) = staff(
        &app,
        Method::GET,
        "/orders/00000000-0000-7000-8000-0000000fffff/priority-history",
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn customers_request_a_priority_change_and_staff_apply_or_dismiss_it(db: PgPool) {
    let app = setup(db.clone()).await;
    let jan = portal_login(&app, &db, JAN).await;
    let o = draft_order(&app, ALPHA, "1").await;
    let oid = id(&o);
    send(&app, &oid).await;

    for body in [
        json!({ "priority": "normal", "message": "x" }),
        json!({ "priority": "expedite", "message": " " }),
    ] {
        let (status, _) = portal(
            &app,
            &jan,
            Method::POST,
            &format!("/orders/{oid}/priority-requests"),
            Some(body),
        )
        .await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    }
    let (status, r1) = portal(
        &app,
        &jan,
        Method::POST,
        &format!("/orders/{oid}/priority-requests"),
        Some(json!({ "priority": "expedite", "message": "We need it by Friday" })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{r1}");
    assert_eq!(r1["status"], "open");
    assert_eq!(r1["requested_by_name"], "Jan Peeters");
    let (_, r2) = portal(
        &app,
        &jan,
        Method::POST,
        &format!("/orders/{oid}/priority-requests"),
        Some(json!({ "priority": "low", "message": "No rush after all" })),
    )
    .await;

    let (_, d) = portal(&app, &jan, Method::GET, &format!("/orders/{oid}"), None).await;
    assert_eq!(d["order"]["open_priority_requests"], 2);

    // Staff see them, apply one through the priority endpoint and dismiss the other.
    let (_, list) = staff(
        &app,
        Method::GET,
        &format!("/orders/{oid}/priority-requests"),
        None,
    )
    .await;
    assert_eq!(list.as_array().unwrap().len(), 2);
    assert_eq!(list[0]["message"], "No rush after all", "newest first");
    let (status, p) = staff(
        &app,
        Method::PUT,
        &format!("/orders/{oid}/priority"),
        Some(json!({
        "priority": "expedite", "reason": "Agreed with the customer", "request_id": r1["id"] })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{p}");
    // The same request cannot be applied twice.
    let (status, _) = staff(
        &app,
        Method::PUT,
        &format!("/orders/{oid}/priority"),
        Some(json!({
        "priority": "low", "reason": "again", "request_id": r1["id"] })),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
    let (status, dm) = staff(
        &app,
        Method::POST,
        &format!(
            "/orders/{oid}/priority-requests/{}/dismiss",
            r2["id"].as_str().unwrap()
        ),
        Some(json!({ "note": "Keep expedite" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{dm}");
    assert_eq!(dm["status"], "dismissed");
    let (status, _) = staff(
        &app,
        Method::POST,
        &format!(
            "/orders/{oid}/priority-requests/{}/dismiss",
            r2["id"].as_str().unwrap()
        ),
        Some(json!({})),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
    let (_, list) = staff(
        &app,
        Method::GET,
        &format!("/orders/{oid}/priority-requests"),
        None,
    )
    .await;
    let statuses: Vec<&str> = list
        .as_array()
        .unwrap()
        .iter()
        .map(|r| r["status"].as_str().unwrap())
        .collect();
    assert_eq!(statuses, ["dismissed", "applied"]);
    let (_, d) = portal(&app, &jan, Method::GET, &format!("/orders/{oid}"), None).await;
    assert_eq!(d["order"]["open_priority_requests"], 0);
}
