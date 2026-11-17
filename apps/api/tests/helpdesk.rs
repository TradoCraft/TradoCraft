//! Helpdesk: e-mail to ticket, threading, replies through the outbox, prepared answers,
//! leads, converting a confirmed quotation to an order, and production questions.

mod common;

use axum::http::{Method, StatusCode};
use common::{call, call_raw, setup};
use serde_json::{json, Value};
use sqlx::PgPool;
use tradocraft_helpdesk::mailer::{process_outbox, Mailer};

const ALPHA: &str = "00000000-0000-7000-8000-000000000401"; // info@alpha.example, language nl
const GAMMA: &str = "00000000-0000-7000-8000-000000000403"; // language de
const UNIT_100: &str = "00000000-0000-7000-8000-000000000301";
const ORDER_CONFIRMED: &str = "00000000-0000-7000-8000-000000000a01";
const SALES: &str = "sales@example.com";
const SUPPORT: &str = "support@example.com";
const PRODUCTION: &str = "production@example.com";

fn mail(from: &str, subject: &str, body: &str, extra_headers: &str) -> Vec<u8> {
    format!(
        "From: {from}\r\nTo: sales@example.com\r\nSubject: {subject}\r\n{extra_headers}Content-Type: text/plain; charset=utf-8\r\n\r\n{body}\r\n"
    )
    .into_bytes()
}

async fn import(app: &axum::Router, raw: Vec<u8>) -> Value {
    let (status, r) = call_raw(
        app,
        SUPPORT,
        "/api/v1/helpdesk/inbound",
        "message/rfc822",
        raw,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{r}");
    r
}

async fn ticket(app: &axum::Router, id: &str) -> Value {
    let (status, t) = call(
        app,
        SUPPORT,
        Method::GET,
        &format!("/api/v1/tickets/{id}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{t}");
    t
}

/// Creates and sends a quotation as the salesperson; returns it.
async fn sent_quote(app: &axum::Router) -> Value {
    let (_, q) = call(
        app,
        SALES,
        Method::POST,
        "/api/v1/quotations",
        Some(
            json!({ "customer_id": ALPHA, "lines": [{ "product_id": UNIT_100, "quantity": "1" }] }),
        ),
    )
    .await;
    let id = q["id"].as_str().unwrap();
    let (_, q) = call(
        app,
        SALES,
        Method::POST,
        &format!("/api/v1/quotations/{id}/send"),
        None,
    )
    .await;
    q
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn email_becomes_ticket_and_replies_thread_back(db: PgPool) {
    let (app, blobs) = common::setup_with_blobs(db.clone()).await;
    let r = import(
        &app,
        mail(
            "Anna Peeters <anna@alpha.example>",
            "Levertijd pompen",
            "Hallo, wat is de levertijd van de pompen? Met vriendelijke groeten, Anna",
            "Message-ID: <in-1@alpha.example>\r\n",
        ),
    )
    .await;
    assert_eq!(r["new_ticket"], true);
    let id = r["ticket_id"].as_str().unwrap().to_string();
    let t = ticket(&app, &id).await;
    assert_eq!(
        t["ticket"]["customer_name"], "Alpha Installaties NV",
        "matched on the company domain"
    );
    assert_eq!(t["ticket"]["language"], "nl");
    assert_eq!(t["ticket"]["status"], "new");
    assert_eq!(t["articles"][0]["kind"], "email_in");

    // Importing the same message again changes nothing.
    let again = import(
        &app,
        mail(
            "anna@alpha.example",
            "Levertijd pompen",
            "x",
            "Message-ID: <in-1@alpha.example>\r\n",
        ),
    )
    .await;
    assert_eq!(again["duplicate"], true);

    // Reply: queued, then sent by the outbox with threading headers.
    let (status, t) = call(
        &app,
        SUPPORT,
        Method::POST,
        &format!("/api/v1/tickets/{id}/replies"),
        Some(json!({ "body": "Beste Anna, 6 tot 8 weken." })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{t}");
    let out = &t["articles"][1];
    assert_eq!(out["kind"], "email_out");
    assert_eq!(out["delivery"], "queued");
    assert_eq!(out["to_addresses"], json!(["anna@alpha.example"]));
    let number = t["ticket"]["number"].as_str().unwrap();
    assert!(out["subject"]
        .as_str()
        .unwrap()
        .contains(&format!("[Ticket#{number}]")));
    assert_eq!(t["ticket"]["status"], "pending_customer");
    assert_eq!(t["ticket"]["owner_name"], "Support Agent");

    let dir = tempfile::tempdir().unwrap();
    let sent = process_outbox(&db, &blobs, &Mailer::Files(dir.path().to_path_buf()), 10)
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
    assert!(eml.contains("In-Reply-To: <in-1@alpha.example>"), "{eml}");
    let our_id = eml
        .lines()
        .find(|l| l.starts_with("Message-ID:"))
        .unwrap()
        .trim_start_matches("Message-ID:")
        .trim()
        .to_string();
    let t = ticket(&app, &id).await;
    assert_eq!(t["articles"][1]["delivery"], "sent");

    // The customer answers our mail (In-Reply-To): same ticket, reopened.
    let r = import(
        &app,
        mail(
            "anna@alpha.example",
            "Re: Levertijd pompen",
            "Dank u!\n\nOp di schreef Support:\n> 6 tot 8 weken",
            &format!("Message-ID: <in-2@alpha.example>\r\nIn-Reply-To: {our_id}\r\n"),
        ),
    )
    .await;
    assert_eq!(r["ticket_id"], id.as_str());
    let t = ticket(&app, &id).await;
    assert_eq!(t["ticket"]["status"], "open");
    assert_eq!(
        t["articles"][2]["body"], "Dank u!",
        "quoted history is stripped"
    );

    // Without headers, the ticket tag in the subject still threads.
    let r = import(
        &app,
        mail(
            "anna@alpha.example",
            &format!("Nog iets [Ticket#{number}]"),
            "En de prijs?",
            "",
        ),
    )
    .await;
    assert_eq!(r["ticket_id"], id.as_str());
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn confirmed_quote_becomes_an_order(db: PgPool) {
    let app = setup(db).await;
    let q = sent_quote(&app).await;
    let number = q["number"].as_str().unwrap();
    let r = import(
        &app,
        mail(
            "info@alpha.example",
            &format!("RE: offerte {number}"),
            "Akkoord, u mag de bestelling plaatsen. Onze referentie PO-778.",
            "",
        ),
    )
    .await;
    let id = r["ticket_id"].as_str().unwrap().to_string();
    let t = ticket(&app, &id).await;
    assert_eq!(t["ticket"]["quotation_number"], number);
    assert_eq!(t["ticket"]["category"], "order_confirmation");
    assert_eq!(
        t["ticket"]["owner_name"], "Sales User",
        "routed to the salesperson of the quote"
    );

    let (status, t) = call(
        &app,
        SALES,
        Method::POST,
        &format!("/api/v1/tickets/{id}/convert"),
        Some(json!({ "customer_reference": "PO-778" })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{t}");
    let order_number = t["ticket"]["order_number"].as_str().unwrap();
    assert!(order_number.starts_with("SO"));
    let (_, quote) = call(
        &app,
        SALES,
        Method::GET,
        &format!("/api/v1/quotations/{}", q["id"].as_str().unwrap()),
        None,
    )
    .await;
    assert_eq!(quote["status"], "accepted");

    // Converting twice is refused.
    let (status, _) = call(
        &app,
        SALES,
        Method::POST,
        &format!("/api/v1/tickets/{id}/convert"),
        Some(json!({})),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);

    // The order confirmation answer is filled in for this ticket.
    let (status, a) = call(
        &app,
        SALES,
        Method::POST,
        &format!("/api/v1/tickets/{id}/prepared-answers/{ORDER_CONFIRMED}/render"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{a}");
    assert_eq!(a["language"], "nl");
    assert_eq!(a["fallback"], false);
    let body = a["body"].as_str().unwrap();
    assert!(
        body.contains(order_number) && body.contains("PO-778") && body.contains(number),
        "{body}"
    );
    assert!(body.contains("Sales User"));
    assert!(!body.contains("{{"), "{body}");

    let (_, orders) = call(&app, SALES, Method::GET, "/api/v1/orders?q=PO-778", None).await;
    assert_eq!(orders["total"], 1);
    assert_eq!(orders["items"][0]["salesperson_name"], "Sales User");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn changes_requested_at_confirmation_go_through_a_new_revision(db: PgPool) {
    let app = setup(db).await;
    let q = sent_quote(&app).await;
    let qid = q["id"].as_str().unwrap();
    let r = import(
        &app,
        mail(
            "info@alpha.example",
            &format!("Re: {}", q["number"].as_str().unwrap()),
            "OK voor bestelling, maar kunnen jullie het aantal aanpassen naar 2?",
            "",
        ),
    )
    .await;
    let id = r["ticket_id"].as_str().unwrap().to_string();
    let t = ticket(&app, &id).await;
    assert_eq!(t["ticket"]["category"], "quote_change");

    // Sales revises the quote, changes the quantity, sends it and links the new revision.
    let (_, rev) = call(
        &app,
        SALES,
        Method::POST,
        &format!("/api/v1/quotations/{qid}/revise"),
        Some(json!({ "pricing": "keep" })),
    )
    .await;
    let rid = rev["id"].as_str().unwrap();
    call(
        &app,
        SALES,
        Method::PUT,
        &format!("/api/v1/quotations/{rid}"),
        Some(
            json!({ "customer_id": ALPHA, "lines": [{ "product_id": UNIT_100, "quantity": "2" }] }),
        ),
    )
    .await;
    call(
        &app,
        SALES,
        Method::POST,
        &format!("/api/v1/quotations/{rid}/send"),
        None,
    )
    .await;

    // The old revision cannot become an order any more.
    let (status, _) = call(
        &app,
        SALES,
        Method::POST,
        &format!("/api/v1/tickets/{id}/convert"),
        Some(json!({})),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);

    let mut input = t["ticket"].clone();
    input["quotation_id"] = json!(rid);
    let (status, _) = call(
        &app,
        SALES,
        Method::PUT,
        &format!("/api/v1/tickets/{id}"),
        Some(input),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (status, t) = call(
        &app,
        SALES,
        Method::POST,
        &format!("/api/v1/tickets/{id}/convert"),
        Some(json!({})),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{t}");
    assert_eq!(t["ticket"]["quotation_revision"], 2);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn production_questions_go_to_the_salesperson_in_the_customers_language(db: PgPool) {
    let app = setup(db).await;
    // An order for the German customer.
    let (_, q) = call(
        &app,
        SALES,
        Method::POST,
        "/api/v1/quotations",
        Some(
            json!({ "customer_id": GAMMA, "lines": [{ "product_id": UNIT_100, "quantity": "1" }] }),
        ),
    )
    .await;
    let qid = q["id"].as_str().unwrap();
    call(
        &app,
        SALES,
        Method::POST,
        &format!("/api/v1/quotations/{qid}/send"),
        None,
    )
    .await;
    let (_, order) = call(
        &app,
        SALES,
        Method::POST,
        &format!("/api/v1/quotations/{qid}/convert"),
        Some(json!({})),
    )
    .await;
    let order_id = order["order"]["id"].as_str().unwrap();

    let (status, t) = call(
        &app,
        PRODUCTION,
        Method::POST,
        "/api/v1/tickets/production-question",
        Some(json!({ "order_id": order_id, "subject": "Kleur frame", "body": "Welke RAL-kleur moet het frame krijgen?" })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{t}");
    assert_eq!(t["ticket"]["owner_name"], "Sales User");
    assert_eq!(t["ticket"]["language"], "de");
    assert_eq!(t["ticket"]["internal"], true);
    assert_eq!(t["ticket"]["category"], "production_question");
    assert_eq!(t["articles"][0]["kind"], "note");
    let id = t["ticket"]["id"].as_str().unwrap();

    // Production cannot e-mail the customer; the salesperson can, in German.
    let reply = json!({ "body": "Welche RAL-Farbe soll der Rahmen haben?" });
    let (status, _) = call(
        &app,
        PRODUCTION,
        Method::POST,
        &format!("/api/v1/tickets/{id}/replies"),
        Some(reply.clone()),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, t) = call(
        &app,
        SALES,
        Method::POST,
        &format!("/api/v1/tickets/{id}/replies"),
        Some(reply),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{t}");
    assert_eq!(
        t["articles"][1]["to_addresses"],
        json!(["office@gamma.example"])
    );
    assert_eq!(t["articles"][1]["language"], "de");

    // The German prepared answer is used for this ticket.
    let (_, a) = call(
        &app,
        SALES,
        Method::POST,
        &format!(
            "/api/v1/tickets/{id}/prepared-answers/00000000-0000-7000-8000-000000000a03/render"
        ),
        None,
    )
    .await;
    assert_eq!(a["language"], "de");
    assert!(a["subject"]
        .as_str()
        .unwrap()
        .starts_with("Rückfrage zu Ihrem Auftrag SO"));
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn unknown_senders_become_leads_once_linked_to_a_customer(db: PgPool) {
    let app = setup(db).await;
    let r = import(
        &app,
        mail(
            "juan@gmail.com",
            "Presupuesto",
            "Hola, necesitamos un presupuesto para tres bombas. Gracias y saludos",
            "",
        ),
    )
    .await;
    let id = r["ticket_id"].as_str().unwrap().to_string();
    let t = ticket(&app, &id).await;
    assert!(
        t["ticket"]["customer_id"].is_null(),
        "public mail domains are not matched"
    );
    assert_eq!(t["ticket"]["language"], "es", "detected from the text");
    assert_eq!(t["ticket"]["category"], "lead");

    let (status, _) = call(
        &app,
        SALES,
        Method::POST,
        &format!("/api/v1/tickets/{id}/lead"),
        Some(json!({})),
    )
    .await;
    assert_eq!(
        status,
        StatusCode::UNPROCESSABLE_ENTITY,
        "needs a customer first"
    );

    let (_, c) = call(
        &app,
        SALES,
        Method::POST,
        "/api/v1/customers",
        Some(json!({ "code": "C0100", "name": "Bombas Juan SL", "email": "juan@gmail.com", "language": "es", "country_code": "ES",
                     "price_zone_id": "00000000-0000-7000-8000-000000000204" })),
    )
    .await;
    let mut input = t["ticket"].clone();
    input["customer_id"] = c["id"].clone();
    call(
        &app,
        SALES,
        Method::PUT,
        &format!("/api/v1/tickets/{id}"),
        Some(input),
    )
    .await;
    let (status, t) = call(
        &app,
        SALES,
        Method::POST,
        &format!("/api/v1/tickets/{id}/lead"),
        Some(json!({ "expected_value": "2500" })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{t}");
    assert!(t["ticket"]["opportunity_number"]
        .as_str()
        .unwrap()
        .starts_with('O'));
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn prepared_answers_fall_back_and_are_managed_with_permission(db: PgPool) {
    let app = setup(db).await;
    let body = json!({ "code": "hello", "name": "Hello", "texts": [{ "language": "en", "subject": "Hello", "body": "Hello {{contact.name}}" }] });
    let (status, _) = call(
        &app,
        SALES,
        Method::POST,
        "/api/v1/prepared-answers",
        Some(body.clone()),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, a) = call(
        &app,
        SUPPORT,
        Method::POST,
        "/api/v1/prepared-answers",
        Some(body),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{a}");

    let r = import(
        &app,
        mail(
            "Pedro <pedro@beta-es.example>",
            "Hola",
            "Hola, una pregunta por favor sobre el pedido y la entrega. Gracias",
            "",
        ),
    )
    .await;
    let id = r["ticket_id"].as_str().unwrap();
    let (_, rendered) = call(
        &app,
        SUPPORT,
        Method::POST,
        &format!(
            "/api/v1/tickets/{id}/prepared-answers/{}/render",
            a["id"].as_str().unwrap()
        ),
        None,
    )
    .await;
    assert_eq!(rendered["language"], "en");
    assert_eq!(rendered["fallback"], true, "no Spanish text yet");
    assert_eq!(rendered["body"], "Hello Pedro");

    let (_, list) = call(
        &app,
        SUPPORT,
        Method::GET,
        "/api/v1/prepared-answers?q=order",
        None,
    )
    .await;
    assert!(list
        .as_array()
        .unwrap()
        .iter()
        .any(|a| a["code"] == "order-confirmed"));
    let (status, _) = call(
        &app,
        "viewer@example.com",
        Method::POST,
        &format!("/api/v1/tickets/{id}/notes"),
        Some(json!({ "body": "x" })),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
}
