//! Cross-module lifecycle: a new customer sends an enquiry, it is split, checked against the
//! power grid, clarified, quoted, revised, converted to an order and confirmed.
//!
//! Deviations from the Kiro plan (verified against the real code):
//! - a ticket can only be split when it holds at least two messages, so the customer sends a
//!   second question in the same thread before the split; the new ticket keeps the same owner;
//! - sending a quotation only changes its status; no e-mail is queued (the PDF is fetched with
//!   `GET /quotations/{id}/pdf`). The cover mail goes out as a ticket reply;
//! - the order confirmation PDF mail is queued by `POST /orders/{id}/send`, not by `confirm`;
//! - revising creates a new draft revision (same number) that is edited with `PUT`.

mod common;

use axum::http::{Method, StatusCode};
use common::e2e::*;
use common::{call, dec, raw, setup, Who};
use rust_decimal::Decimal;
use serde_json::{json, Value};
use sqlx::PgPool;
use tradocraft_helpdesk::mailer::{process_outbox, Mailer};

const SALES: &str = "sales@example.com";
const SUPPORT: &str = "support@example.com";
const ZONE_INDUSTRY: &str = "00000000-0000-7000-8000-000000000203"; // Z3, 10 % below list
const UNIT_100: &str = "00000000-0000-7000-8000-000000000301";
const UNIT_200: &str = "00000000-0000-7000-8000-000000000302";
const PUMP: &str = "00000000-0000-7000-8000-000000000303";
const CTRL: &str = "00000000-0000-7000-8000-000000000310";
const ORDER_CONFIRMED: &str = "00000000-0000-7000-8000-000000000a01";
const QUOTE_SENT: &str = "00000000-0000-7000-8000-000000000a02";

fn dm(s: &str) -> Decimal {
    s.parse().unwrap()
}

async fn step_register_customer(app: &axum::Router, flow: &mut E2eFlow) {
    let (status, c) = call(
        app,
        SALES,
        Method::POST,
        "/api/v1/customers",
        Some(json!({
            "code": "C0900",
            "name": TEST_CUSTOMER_NAME,
            "email": TEST_CUSTOMER_EMAIL,
            "street": "Storgata 1",
            "postal_code": "0155",
            "city": "Oslo",
            "country_code": TEST_CUSTOMER_COUNTRY,
            "language": TEST_CUSTOMER_LANGUAGE,
            "price_zone_id": ZONE_INDUSTRY,
        })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{c}");
    assert_eq!(c["name"], TEST_CUSTOMER_NAME);
    flow.customer_id = c["id"].as_str().unwrap().to_string();
    flow.customer_name = TEST_CUSTOMER_NAME.to_string();
    flow.customer_email = TEST_CUSTOMER_EMAIL.to_string();
    flow.customer_language = TEST_CUSTOMER_LANGUAGE.to_string();
    flow.customer_country = TEST_CUSTOMER_COUNTRY.to_string();
}

fn enquiry() -> Vec<u8> {
    build_email(
        "Kari Nordmann <info@nordic.example>",
        "Enquiry: process unit with pump",
        "Hello, we would like a quotation for one process unit, two pumps and a controller \
         for our plant in Oslo. Kind regards, Kari",
        "Message-ID: <enq-1@nordic.example>\r\n",
    )
}

async fn step_import_enquiry_email(app: &axum::Router, flow: &mut E2eFlow) {
    let r = import_email(app, SUPPORT, enquiry()).await;
    assert_eq!(r["new_ticket"], true, "{r}");
    assert_eq!(r["duplicate"], false, "{r}");
    let id = r["ticket_id"].as_str().unwrap().to_string();
    let t = get_ticket(app, SUPPORT, &id).await;
    assert_eq!(
        t["ticket"]["customer_id"], flow.customer_id,
        "matched to the registered customer by the e-mail domain"
    );
    assert_eq!(t["ticket"]["customer_name"], TEST_CUSTOMER_NAME);
    assert_eq!(t["ticket"]["status"], "new");
    assert_eq!(t["articles"][0]["kind"], "email_in");
    flow.ticket_number = Some(r["ticket_number"].as_str().unwrap().to_string());
    flow.ticket_id = Some(id);
}

async fn step_duplicate_import_is_idempotent(app: &axum::Router, flow: &mut E2eFlow) {
    let id = flow.ticket_id.clone().unwrap();
    let before = get_ticket(app, SUPPORT, &id).await;
    let again = import_email(app, SUPPORT, enquiry()).await;
    assert_eq!(again["duplicate"], true, "{again}");
    assert_eq!(again["ticket_id"], id.as_str());
    let after = get_ticket(app, SUPPORT, &id).await;
    assert_eq!(after["ticket"]["status"], before["ticket"]["status"]);
    assert_eq!(
        after["articles"].as_array().unwrap().len(),
        before["articles"].as_array().unwrap().len()
    );
    assert_eq!(after["articles"][0]["body"], before["articles"][0]["body"]);
    assert_eq!(after["ticket"]["article_count"], 1);
}

async fn step_split_ticket(app: &axum::Router, flow: &mut E2eFlow) {
    let id = flow.ticket_id.clone().unwrap();
    // A single message cannot be split off (it would leave the ticket empty).
    let only = get_ticket(app, SUPPORT, &id).await;
    let first = only["articles"][0]["id"].as_str().unwrap().to_string();
    let (status, e) = call(
        app,
        SUPPORT,
        Method::POST,
        &format!("/api/v1/tickets/{id}/split"),
        Some(json!({ "article_ids": [first] })),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT, "{e}");

    // The customer adds an unrelated question in the same thread.
    let r = import_email(
        app,
        SUPPORT,
        build_email(
            "info@nordic.example",
            "Re: Enquiry: process unit with pump",
            "Separate question: do you also offer an operator training course?",
            "Message-ID: <enq-2@nordic.example>\r\nIn-Reply-To: <enq-1@nordic.example>\r\n",
        ),
    )
    .await;
    assert_eq!(r["ticket_id"], id.as_str(), "threaded onto the same ticket");
    assert_eq!(r["new_ticket"], false);
    let t = get_ticket(app, SUPPORT, &id).await;
    let articles = t["articles"].as_array().unwrap();
    assert_eq!(articles.len(), 2);
    let moved = articles[1]["id"].as_str().unwrap().to_string();

    let (status, n) = call(
        app,
        SUPPORT,
        Method::POST,
        &format!("/api/v1/tickets/{id}/split"),
        Some(json!({ "article_ids": [moved], "subject": "Operator training" })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{n}");
    let new_id = n["ticket"]["id"].as_str().unwrap().to_string();
    assert_ne!(new_id, id);
    assert_eq!(n["ticket"]["subject"], "Operator training");
    assert_eq!(n["ticket"]["customer_id"], flow.customer_id);
    assert_eq!(n["ticket"]["status"], "open");
    // Real behaviour: the new ticket keeps the owner of the source (the plan assumed another one).
    let source = get_ticket(app, SUPPORT, &id).await;
    assert_eq!(
        n["ticket"]["owner_user_id"],
        source["ticket"]["owner_user_id"]
    );

    // Cross-module invariant: the moved message lives only on the new ticket.
    let has = |t: &Value, article: &str| {
        t["articles"]
            .as_array()
            .unwrap()
            .iter()
            .any(|a| a["id"] == article)
    };
    assert!(has(&n, &moved));
    assert!(!has(&source, &moved));
    assert!(has(&source, &first));
    assert!(!has(&n, &first));
    flow.split_ticket_id = Some(new_id);
}

async fn step_check_power_grid_compatibility(app: &axum::Router, flow: &mut E2eFlow) {
    let country = &flow.customer_country;
    let status_of = |product: &'static str| async move {
        let (status, r) = call(
            app,
            SALES,
            Method::GET,
            &format!("/api/v1/products/{product}/power-compatibility?country={country}"),
            None,
        )
        .await;
        assert_eq!(status, StatusCode::OK, "{r}");
        assert_eq!(r["country_code"], "NO");
        r["status"].as_str().unwrap().to_string()
    };
    assert_eq!(status_of(UNIT_100).await, "compatible", "400V 3-phase 50Hz");
    assert_eq!(status_of(PUMP).await, "compatible", "230V 1-phase");
    assert_eq!(status_of(CTRL).await, "needs_external_supply", "24V DC");
    assert_eq!(status_of(UNIT_200).await, "incompatible", "120V 60Hz");
}

/// Our reply mail, sent by the outbox worker; returns the Message-ID it went out with.
async fn deliver_outbox(db: &PgPool) -> String {
    let dir = tempfile::tempdir().unwrap();
    let sent = process_outbox(db, &Mailer::Files(dir.path().to_path_buf()), 10)
        .await
        .unwrap();
    assert_eq!(sent, 1);
    let file = std::fs::read_dir(dir.path())
        .unwrap()
        .next()
        .unwrap()
        .unwrap()
        .path();
    let eml = std::fs::read_to_string(file).unwrap();
    eml.lines()
        .find(|l| l.starts_with("Message-ID:"))
        .unwrap()
        .trim_start_matches("Message-ID:")
        .trim()
        .to_string()
}

async fn step_ask_clarifying_question(app: &axum::Router, flow: &mut E2eFlow) {
    let id = flow.ticket_id.clone().unwrap();
    let (status, t) = call(
        app,
        SUPPORT,
        Method::POST,
        &format!("/api/v1/tickets/{id}/replies"),
        Some(json!({ "body": "Dear Kari, which supply voltage is available at the plant?" })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{t}");
    let out = t["articles"].as_array().unwrap().last().unwrap().clone();
    assert_eq!(out["kind"], "email_out");
    assert_eq!(out["delivery"], "queued");
    assert_eq!(out["to_addresses"], json!([flow.customer_email]));
    assert_eq!(out["language"], flow.customer_language.as_str());
    assert_eq!(t["ticket"]["status"], "pending_customer");
}

async fn step_customer_replies(app: &axum::Router, db: &PgPool, flow: &mut E2eFlow) {
    let id = flow.ticket_id.clone().unwrap();
    let our_id = deliver_outbox(db).await;
    let before = get_ticket(app, SUPPORT, &id).await;
    assert_eq!(
        before["articles"].as_array().unwrap().last().unwrap()["delivery"],
        "sent"
    );
    let r = import_email(
        app,
        SUPPORT,
        build_email(
            "info@nordic.example",
            "Re: Enquiry: process unit with pump",
            "We have 400V three-phase, 50Hz.\n\nOn Monday, Support wrote:\n> which supply voltage",
            &format!("Message-ID: <enq-3@nordic.example>\r\nIn-Reply-To: {our_id}\r\n"),
        ),
    )
    .await;
    assert_eq!(r["ticket_id"], id.as_str(), "threaded by In-Reply-To");
    assert_eq!(r["new_ticket"], false);
    let t = get_ticket(app, SUPPORT, &id).await;
    assert_eq!(
        t["ticket"]["status"], "open",
        "the customer's answer reopens it"
    );
    assert_eq!(
        t["articles"].as_array().unwrap().last().unwrap()["body"],
        "We have 400V three-phase, 50Hz.",
        "quoted history is stripped"
    );
}

async fn step_create_and_send_quotation(app: &axum::Router, db: &PgPool, flow: &mut E2eFlow) {
    // No prices are sent: the server takes them from the customer's price zone.
    let (status, q) = call(
        app,
        SALES,
        Method::POST,
        "/api/v1/quotations",
        Some(json!({ "customer_id": flow.customer_id, "lines": [
            { "product_id": UNIT_100, "quantity": "1" },
            { "product_id": PUMP, "quantity": "2" },
            { "product_id": CTRL, "quantity": "1" } ] })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{q}");
    assert_eq!(q["status"], "draft");
    assert_eq!(q["revision"], 1);
    assert_eq!(q["price_zone_code"], "Z3");
    assert_eq!(q["delivery_country_code"], "NO");
    assert_eq!(q["currency"], "EUR");
    let price = |i: usize| dec(&q["lines"][i]["net_unit_price"]);
    assert_eq!(price(0), dm("4365.00"), "4850 less 10 %");
    assert_eq!(price(1), dm("576.00"), "640 less 10 %");
    assert_eq!(price(2), dm("801.00"), "890 less 10 %");
    assert_eq!(dec(&q["subtotal"]), dm("6318.00"));
    assert_eq!(dec(&q["total"]), dm("7644.78"), "21 % VAT on top");
    // The power-grid check is part of the quotation: the pump/unit fit Norway, the controller needs a supply.
    let kinds: Vec<&str> = q["warnings"]
        .as_array()
        .unwrap()
        .iter()
        .map(|w| w["kind"].as_str().unwrap())
        .collect();
    assert!(!kinds.contains(&"incompatible_products"), "{kinds:?}");

    let qid = q["id"].as_str().unwrap().to_string();
    // Link the quotation to the ticket so that the conversation and the document belong together.
    link_ticket_to_quotation(app, flow, &qid).await;

    let (status, s) = call(
        app,
        SALES,
        Method::POST,
        &format!("/api/v1/quotations/{qid}/send"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{s}");
    assert_eq!(s["status"], "sent");
    assert!(s["sent_at"].is_string());

    // Real behaviour: sending queues no mail; the PDF is rendered on request.
    let queued: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM core.mail_outbox WHERE attachment_name IS NOT NULL",
    )
    .fetch_one(db)
    .await
    .unwrap();
    assert_eq!(
        queued, 0,
        "sending a quotation does not queue an attachment mail"
    );
    let (status, _, pdf) = raw(
        app,
        Who::Staff(SALES),
        Method::GET,
        &format!("/api/v1/quotations/{qid}/pdf"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(&pdf[..4], b"%PDF");

    // The cover mail goes to the customer as a reply on the ticket, from the prepared answer.
    let tid = flow.ticket_id.clone().unwrap();
    let (status, a) = call(
        app,
        SALES,
        Method::POST,
        &format!("/api/v1/tickets/{tid}/prepared-answers/{QUOTE_SENT}/render"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{a}");
    assert_eq!(a["language"], "en");
    let number = s["number"].as_str().unwrap();
    assert!(a["body"].as_str().unwrap().contains(number), "{a}");
    let (status, t) = call(
        app,
        SALES,
        Method::POST,
        &format!("/api/v1/tickets/{tid}/replies"),
        Some(json!({ "subject": a["subject"], "body": a["body"] })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{t}");
    let out = t["articles"].as_array().unwrap().last().unwrap().clone();
    assert_eq!(out["to_addresses"], json!([flow.customer_email]));
    assert_eq!(out["delivery"], "queued");

    flow.quotation_id = Some(qid);
    flow.quotation_number = Some(number.to_string());
    flow.quotation_revision = Some(1);
    flow.quotation_total = Some(dec(&s["total"]));
}

async fn link_ticket_to_quotation(app: &axum::Router, flow: &E2eFlow, quotation_id: &str) {
    let tid = flow.ticket_id.clone().unwrap();
    let t = get_ticket(app, SALES, &tid).await;
    let mut input = t["ticket"].clone();
    input["quotation_id"] = json!(quotation_id);
    let (status, u) = call(
        app,
        SALES,
        Method::PUT,
        &format!("/api/v1/tickets/{tid}"),
        Some(input),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{u}");
}

async fn step_stub_second_person_review(app: &axum::Router, flow: &mut E2eFlow) {
    // Stub: a second-person approval gate for quotations does not exist yet. When it ships,
    // replace this body with the review steps. The current boundary: the quotation was sent
    // by the person who wrote it, and there is no approval route to call.
    let qid = flow.quotation_id.clone().unwrap();
    let (_, q) = call(
        app,
        SALES,
        Method::GET,
        &format!("/api/v1/quotations/{qid}"),
        None,
    )
    .await;
    assert_eq!(q["status"], "sent");
    let (status, _) = call(
        app,
        "manager@example.com",
        Method::POST,
        &format!("/api/v1/quotations/{qid}/approve"),
        None,
    )
    .await;
    assert_eq!(
        status,
        StatusCode::NOT_FOUND,
        "no review/approval route yet"
    );
}

async fn step_revise_quotation_remove_products(app: &axum::Router, flow: &mut E2eFlow) {
    let old = flow.quotation_id.clone().unwrap();
    // The customer accepts but wants no controller and only one pump.
    let (status, rev) = call(
        app,
        SALES,
        Method::POST,
        &format!("/api/v1/quotations/{old}/revise"),
        Some(json!({ "pricing": "keep" })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{rev}");
    assert_eq!(rev["revision"], 2);
    assert_eq!(
        rev["number"],
        flow.quotation_number.clone().unwrap().as_str()
    );
    assert_eq!(rev["status"], "draft");
    assert_eq!(rev["supersedes_id"], old.as_str());
    assert_eq!(rev["lines"].as_array().unwrap().len(), 3);
    let rid = rev["id"].as_str().unwrap().to_string();

    let (_, o) = call(
        app,
        SALES,
        Method::GET,
        &format!("/api/v1/quotations/{old}"),
        None,
    )
    .await;
    assert_eq!(o["status"], "superseded");

    let (status, e) = call(
        app,
        SALES,
        Method::PUT,
        &format!("/api/v1/quotations/{rid}"),
        Some(json!({ "customer_id": flow.customer_id, "lines": [
            { "product_id": UNIT_100, "quantity": "1" },
            { "product_id": PUMP, "quantity": "1" } ] })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{e}");
    let lines = e["lines"].as_array().unwrap();
    assert_eq!(lines.len(), 2);
    assert!(lines.iter().any(|l| l["product_code"] == "UNIT-100"));
    assert!(lines.iter().all(|l| l["product_code"] != "CTRL-01"));
    assert_eq!(dec(&e["subtotal"]), dm("4941.00"), "4365 + 576");
    assert!(dec(&e["total"]) < flow.quotation_total.unwrap());

    let (status, s) = call(
        app,
        SALES,
        Method::POST,
        &format!("/api/v1/quotations/{rid}/send"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{s}");
    assert_eq!(s["status"], "sent");
    link_ticket_to_quotation(app, flow, &rid).await;

    // The superseded revision can no longer become an order.
    let (status, _) = call(
        app,
        SALES,
        Method::POST,
        &format!("/api/v1/quotations/{old}/convert"),
        Some(json!({})),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);

    flow.quotation_id = Some(rid);
    flow.quotation_revision = Some(2);
    flow.quotation_total = Some(dec(&s["total"]));
}

async fn step_convert_to_order(app: &axum::Router, flow: &mut E2eFlow) {
    // Converted from the ticket (the helpdesk -> sales path), so that the order is linked to the
    // conversation. `POST /quotations/{id}/convert` does the same without linking the ticket.
    let original_total = dm("7644.78");
    let qid = flow.quotation_id.clone().unwrap();
    let tid = flow.ticket_id.clone().unwrap();
    let (status, t) = call(
        app,
        SALES,
        Method::POST,
        &format!("/api/v1/tickets/{tid}/convert"),
        Some(json!({ "customer_reference": "PO-NIS-001" })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{t}");
    assert_eq!(t["ticket"]["quotation_revision"], 2);
    let order_id = t["ticket"]["order_id"].as_str().unwrap().to_string();
    let (status, o) = call(
        app,
        SALES,
        Method::GET,
        &format!("/api/v1/orders/{order_id}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{o}");
    assert_eq!(o["order"]["status"], "draft");
    assert_eq!(o["order"]["customer_reference"], "PO-NIS-001");
    assert_eq!(o["lines"].as_array().unwrap().len(), 2);
    let total = dec(&o["order"]["total"]);
    assert_eq!(
        total,
        flow.quotation_total.unwrap(),
        "order carries the revision's total"
    );
    assert!(total < original_total, "removing lines lowers the total");

    let (_, q) = call(
        app,
        SALES,
        Method::GET,
        &format!("/api/v1/quotations/{qid}"),
        None,
    )
    .await;
    assert_eq!(q["status"], "accepted");
    flow.order_id = Some(order_id);
    flow.order_number = Some(o["order"]["number"].as_str().unwrap().to_string());
    flow.order_total = Some(total);
}

async fn step_send_and_confirm_order(app: &axum::Router, flow: &mut E2eFlow) {
    let oid = flow.order_id.clone().unwrap();
    let (status, s) = call(
        app,
        SALES,
        Method::POST,
        &format!("/api/v1/orders/{oid}/send"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{s}");
    assert_eq!(s["order"]["status"], "sent");
    assert_eq!(s["revisions"][0]["sent_to"], flow.customer_email.as_str());
    let (status, c) = call(
        app,
        SALES,
        Method::POST,
        &format!("/api/v1/orders/{oid}/confirm"),
        Some(json!({ "note": "Confirmed by phone" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{c}");
    assert_eq!(c["order"]["status"], "confirmed");
    assert_eq!(dec(&c["order"]["total"]), flow.order_total.unwrap());
}

async fn step_assert_confirmation_email(app: &axum::Router, db: &PgPool, flow: &mut E2eFlow) {
    // Queued when the order was sent, in the customer's language, with the PDF attached.
    let (to, subject, name, kind, magic): (String, String, String, String, Vec<u8>) =
        sqlx::query_as(
            "SELECT to_address, subject, attachment_name, attachment_type,
                    substring(attachment_data from 1 for 4)
             FROM core.mail_outbox WHERE attachment_name IS NOT NULL",
        )
        .fetch_one(db)
        .await
        .unwrap();
    let number = flow.order_number.clone().unwrap();
    assert_eq!(to, flow.customer_email);
    assert_eq!(subject, format!("Order confirmation {number}"), "English");
    assert_eq!(name, format!("{number}-r1.pdf"));
    assert_eq!(kind, "application/pdf");
    assert_eq!(magic, b"%PDF");

    // The prepared answer for the ticket is filled in in English as well.
    let tid = flow.ticket_id.clone().unwrap();
    let (status, a) = call(
        app,
        SALES,
        Method::POST,
        &format!("/api/v1/tickets/{tid}/prepared-answers/{ORDER_CONFIRMED}/render"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{a}");
    assert_eq!(a["language"], "en");
    assert_eq!(a["fallback"], false);
    let body = a["body"].as_str().unwrap();
    assert!(!body.contains("{{"), "{a}");
    assert!(body.contains(&number) && body.contains("PO-NIS-001"), "{a}");
}

async fn step_stub_production_planning(app: &axum::Router, flow: &E2eFlow) {
    // Boundary: production exists (ADR 0036, 0060, driven in tests/production.rs and
    // tests/production_routing.rs) but is manual: a planner releases a confirmed order. Nobody
    // does in this flow, so the order stays confirmed.
    let (status, o) = call(
        app,
        SALES,
        Method::GET,
        &format!("/api/v1/orders/{}", flow.order_id.as_ref().unwrap()),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{o}");
    assert_eq!(
        o["order"]["status"], "confirmed",
        "the order stays confirmed until a planner releases it to production"
    );
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn primary_e2e_lifecycle(db: PgPool) {
    let app = setup(db.clone()).await;
    let mut flow = E2eFlow::new();

    step_register_customer(&app, &mut flow).await;
    step_import_enquiry_email(&app, &mut flow).await;
    step_duplicate_import_is_idempotent(&app, &mut flow).await;
    step_split_ticket(&app, &mut flow).await;
    step_check_power_grid_compatibility(&app, &mut flow).await;
    step_ask_clarifying_question(&app, &mut flow).await;
    step_customer_replies(&app, &db, &mut flow).await;
    step_create_and_send_quotation(&app, &db, &mut flow).await;
    step_stub_second_person_review(&app, &mut flow).await;
    step_revise_quotation_remove_products(&app, &mut flow).await;
    step_convert_to_order(&app, &mut flow).await;
    step_send_and_confirm_order(&app, &mut flow).await;
    step_assert_confirmation_email(&app, &db, &mut flow).await;
    step_stub_production_planning(&app, &flow).await;
}
