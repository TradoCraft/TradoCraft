//! Contacts (people at customers): language and address form, lookup by e-mail and phone,
//! tickets that know their person, and phone calls.

mod common;

use axum::http::{Method, StatusCode};
use common::{call, call_raw, setup};
use serde_json::{json, Value};
use sqlx::PgPool;

const ALPHA: &str = "00000000-0000-7000-8000-000000000401"; // nl
const BETA: &str = "00000000-0000-7000-8000-000000000402"; // fr
const JAN: &str = "00000000-0000-7000-8000-000000000601"; // Alpha, formal, language of the customer
const SOFIE: &str = "00000000-0000-7000-8000-000000000602"; // Alpha, informal
const LUC: &str = "00000000-0000-7000-8000-000000000604"; // Beta (fr) but speaks Dutch
const SALES: &str = "sales@example.com";
const SUPPORT: &str = "support@example.com";
const VIEWER: &str = "viewer@example.com";
const PRODUCTION: &str = "production@example.com";

async fn get(app: &axum::Router, user: &str, uri: &str) -> (StatusCode, Value) {
    call(app, user, Method::GET, uri, None).await
}

async fn post(app: &axum::Router, user: &str, uri: &str, body: Value) -> (StatusCode, Value) {
    call(app, user, Method::POST, uri, Some(body)).await
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_customer_lists_its_people_with_language_and_greeting(db: PgPool) {
    let app = setup(db).await;
    let (status, list) = get(&app, SALES, &format!("/api/v1/customers/{BETA}/contacts")).await;
    assert_eq!(status, StatusCode::OK, "{list}");
    let list = list.as_array().unwrap();
    assert_eq!(list.len(), 2);

    let marie = list.iter().find(|c| c["last_name"] == "Dupont").unwrap();
    assert_eq!(marie["language"], Value::Null, "same as the customer");
    assert_eq!(marie["effective_language"], "fr");
    assert_eq!(marie["greeting"], "Bonjour Madame Dupont,");
    assert_eq!(marie["roles"], json!(["purchasing", "sales_contact"]));

    // Luc speaks Dutch although the customer is French-speaking, and is addressed informally.
    let luc = list.iter().find(|c| c["last_name"] == "Claes").unwrap();
    assert_eq!(luc["customer_language"], "fr");
    assert_eq!(luc["language"], "nl");
    assert_eq!(luc["effective_language"], "nl");
    assert_eq!(luc["greeting"], "Dag Luc,");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn contacts_are_validated_and_permissions_enforced(db: PgPool) {
    let app = setup(db).await;
    let uri = format!("/api/v1/customers/{ALPHA}/contacts");
    let base = json!({
        "first_name": "Eva", "last_name": "Willems", "title": "none", "address_form": "formal",
        "roles": ["technical", "technical", "quality"],
        "emails": ["Eva.Willems@Alpha.example", "eva@alpha.example"],
        "phones": [{ "label": "mobile", "number": "0472 11 22 33" }, { "number": "+32 (0)472/11.22.33" }]
    });

    // Support and sales maintain contacts; a viewer reads, production does neither.
    assert_eq!(
        post(&app, VIEWER, &uri, base.clone()).await.0,
        StatusCode::FORBIDDEN
    );
    assert_eq!(
        post(&app, PRODUCTION, &uri, base.clone()).await.0,
        StatusCode::FORBIDDEN
    );
    assert_eq!(get(&app, VIEWER, &uri).await.0, StatusCode::OK);
    let (status, c) = post(&app, SUPPORT, &uri, base.clone()).await;
    assert_eq!(status, StatusCode::CREATED, "{c}");

    // Addresses are lower-cased, the first is primary; roles and the same number twice are folded.
    assert_eq!(
        c["emails"][0],
        json!({ "email": "eva.willems@alpha.example", "is_primary": true })
    );
    assert_eq!(c["emails"][1]["is_primary"], false);
    assert_eq!(c["roles"], json!(["quality", "technical"]));
    assert_eq!(c["phones"].as_array().unwrap().len(), 1);
    assert_eq!(c["phones"][0]["normalized"], "32472112233");
    assert_eq!(c["effective_language"], "nl");
    assert_eq!(
        c["greeting"], "Geachte Eva Willems,",
        "no mr/ms given: full name"
    );

    // An address identifies one person.
    let (status, e) = post(
        &app,
        SALES,
        &format!("/api/v1/customers/{BETA}/contacts"),
        json!({ "last_name": "Other", "emails": ["jan.peeters@alpha.example"] }),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT, "{e}");
    assert!(
        e["message"].as_str().unwrap().contains("Jan Peeters"),
        "{e}"
    );

    for (patch, what) in [
        (json!({ "last_name": " " }), "last name"),
        (json!({ "language": "xx" }), "language"),
        (json!({ "title": "dr" }), "title"),
        (json!({ "address_form": "casual" }), "address form"),
        (json!({ "roles": ["boss"] }), "role"),
        (json!({ "emails": ["not-an-address"] }), "e-mail"),
        (json!({ "phones": [{ "number": "12" }] }), "phone"),
        (json!({ "portal_scope": "all" }), "scope"),
        (
            json!({ "portal_access": true, "emails": [] }),
            "portal without e-mail",
        ),
    ] {
        let mut body = json!({ "last_name": "Test" });
        body.as_object_mut()
            .unwrap()
            .extend(patch.as_object().unwrap().clone());
        let (status, r) = post(&app, SALES, &uri, body).await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{what}: {r}");
    }

    // Update: own language, informal; a person who left is kept (history) but inactive.
    let id = c["id"].as_str().unwrap();
    let mut update = base.clone();
    update["language"] = json!("fr");
    update["address_form"] = json!("informal");
    update["first_name"] = json!("Eva");
    update["active"] = json!(false);
    let (status, u) = call(
        &app,
        SALES,
        Method::PUT,
        &format!("/api/v1/contacts/{id}"),
        Some(update),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{u}");
    assert_eq!(u["effective_language"], "fr");
    assert_eq!(u["greeting"], "Bonjour Eva,");
    let (_, active_only) = get(&app, SALES, &uri).await;
    assert_eq!(active_only.as_array().unwrap().len(), 2);
    let (_, all) = get(&app, SALES, &format!("{uri}?include_inactive=true")).await;
    assert_eq!(all.as_array().unwrap().len(), 3);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_caller_is_found_by_phone_number_in_any_format(db: PgPool) {
    let app = setup(db).await;
    // Sofie's mobile was entered as "0475 00 00 22".
    for number in [
        "+32 475 00 00 22",
        "0032475000022",
        "0475/00.00.22",
        "+32 (0)475 00 00 22",
    ] {
        let (status, r) = get(
            &app,
            SUPPORT,
            &format!(
                "/api/v1/contacts/lookup?phone={}",
                number
                    .replace('+', "%2B")
                    .replace(' ', "%20")
                    .replace('/', "%2F")
            ),
        )
        .await;
        assert_eq!(status, StatusCode::OK, "{number}: {r}");
        let contacts = r["contacts"].as_array().unwrap();
        assert_eq!(contacts.len(), 1, "{number}: {r}");
        assert_eq!(contacts[0]["id"], SOFIE);
        assert_eq!(contacts[0]["customer_name"], "Alpha Installaties NV");
        assert_eq!(contacts[0]["greeting"], "Dag Sofie,");
    }

    // A number that nobody has, and one we cannot read.
    let (_, r) = get(
        &app,
        SUPPORT,
        "/api/v1/contacts/lookup?phone=%2B32%20475%2099%2099%2099",
    )
    .await;
    assert_eq!(r["contacts"], json!([]));
    assert_eq!(
        get(&app, SUPPORT, "/api/v1/contacts/lookup?phone=12")
            .await
            .0,
        StatusCode::UNPROCESSABLE_ENTITY
    );
    assert_eq!(
        get(&app, SUPPORT, "/api/v1/contacts/lookup").await.0,
        StatusCode::UNPROCESSABLE_ENTITY
    );

    // The customer's main number identifies the company when the person is not known.
    let (_, r) = get(
        &app,
        SUPPORT,
        "/api/v1/contacts/lookup?phone=%2B32%203%20000%2000%2001",
    )
    .await;
    assert_eq!(r["contacts"], json!([]));
    assert_eq!(r["customers"][0]["name"], "Alpha Installaties NV");
    assert_eq!(r["customers"][0]["matched_on"], "phone");

    // By e-mail address and by name.
    let (_, r) = get(
        &app,
        SUPPORT,
        "/api/v1/contacts/lookup?email=Luc.Claes@beta.example",
    )
    .await;
    assert_eq!(r["contacts"][0]["id"], LUC);
    let (_, r) = get(&app, SUPPORT, "/api/v1/contacts/lookup?q=peet").await;
    assert_eq!(r["contacts"][0]["id"], JAN);
    let (_, r) = get(&app, SUPPORT, "/api/v1/contacts/lookup?q=b%C3%AAta").await;
    assert_eq!(
        r["contacts"].as_array().unwrap().len(),
        2,
        "by customer name"
    );
}

fn mail(from: &str, subject: &str, body: &str) -> Vec<u8> {
    format!("From: {from}\r\nTo: sales@example.com\r\nSubject: {subject}\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n{body}\r\n").into_bytes()
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

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn an_email_ticket_knows_who_wrote_and_in_which_language_to_answer(db: PgPool) {
    let app = setup(db).await;
    // The sender is a technician who writes from a name the mail client made up.
    let r = import(
        &app,
        mail(
            "LC <luc.claes@beta.example>",
            "Pomp",
            "Bonjour, la pompe fait du bruit. Pouvez-vous venir? Merci",
        ),
    )
    .await;
    let id = r["ticket_id"].as_str().unwrap();
    let (_, t) = get(&app, SUPPORT, &format!("/api/v1/tickets/{id}")).await;
    let ticket = &t["ticket"];
    assert_eq!(ticket["contact_id"], LUC);
    assert_eq!(
        ticket["contact_name"], "Luc Claes",
        "the name on file, not the one in the mail"
    );
    assert_eq!(ticket["customer_id"], BETA);
    assert_eq!(
        ticket["language"], "nl",
        "the person's language wins over the customer's, and over the text"
    );
    assert_eq!(t["articles"][0]["contact_name"], "Luc Claes");

    // An unknown address at the same company still falls back to customer matching, without a person.
    let r = import(
        &app,
        mail(
            "Someone <someone@gmail.com>",
            "Question",
            "Hello, do you have a catalogue? Thanks",
        ),
    )
    .await;
    let (_, t) = get(
        &app,
        SUPPORT,
        &format!("/api/v1/tickets/{}", r["ticket_id"].as_str().unwrap()),
    )
    .await;
    assert_eq!(t["ticket"]["contact_id"], Value::Null);

    // A second mail on the thread keeps the person.
    let r2 = import(
        &app,
        mail(
            "luc.claes@beta.example",
            &format!("Re: Pomp [Ticket#{}]", t_number(&app, id).await),
            "Dringend alstublieft, dank",
        ),
    )
    .await;
    assert_eq!(r2["ticket_id"], id);
    assert_eq!(r2["new_ticket"], false);
}

async fn t_number(app: &axum::Router, id: &str) -> String {
    let (_, t) = get(app, SUPPORT, &format!("/api/v1/tickets/{id}")).await;
    t["ticket"]["number"].as_str().unwrap().to_string()
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_ticket_opened_by_hand_takes_customer_name_and_language_from_the_person(db: PgPool) {
    let app = setup(db).await;
    let (status, t) = post(
        &app,
        SUPPORT,
        "/api/v1/tickets",
        json!({
            "subject": "Visit", "contact_id": LUC, "body": "Asked for a visit"
        }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{t}");
    let ticket = &t["ticket"];
    assert_eq!(ticket["customer_id"], BETA);
    assert_eq!(ticket["contact_name"], "Luc Claes");
    assert_eq!(ticket["contact_email"], "luc.claes@beta.example");
    assert_eq!(ticket["language"], "nl");

    // A person of another customer cannot be combined with this customer.
    let (status, _) = post(
        &app,
        SUPPORT,
        "/api/v1/tickets",
        json!({
            "subject": "x", "contact_id": LUC, "customer_id": ALPHA, "body": "x"
        }),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    // Updating the ticket keeps or changes the person; the customer follows.
    let id = ticket["id"].as_str().unwrap();
    let mut update = json!({
        "subject": "Visit", "status": "open", "priority": "normal", "category": "question",
        "language": "fr", "owner_user_id": null, "customer_id": null, "contact_id": JAN,
        "contact_name": "Jan Peeters", "contact_email": "jan.peeters@alpha.example"
    });
    let (status, u) = call(
        &app,
        SUPPORT,
        Method::PUT,
        &format!("/api/v1/tickets/{id}"),
        Some(update.clone()),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{u}");
    assert_eq!(u["ticket"]["customer_id"], ALPHA);
    assert_eq!(u["ticket"]["contact_id"], JAN);
    update["customer_id"] = json!(BETA);
    let (status, _) = call(
        &app,
        SUPPORT,
        Method::PUT,
        &format!("/api/v1/tickets/{id}"),
        Some(update),
    )
    .await;
    assert_eq!(
        status,
        StatusCode::UNPROCESSABLE_ENTITY,
        "Jan does not work for Beta"
    );
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn an_incoming_call_is_looked_up_and_logged_on_a_new_ticket(db: PgPool) {
    let app = setup(db).await;
    let (status, t) = post(
        &app,
        SUPPORT,
        "/api/v1/helpdesk/calls",
        json!({
            "direction": "in", "phone_number": "+32 478 00 00 44", "duration_seconds": 240,
            "summary": "Pump is noisy.\nWants a technician this week.", "category": "service"
        }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{t}");
    let ticket = &t["ticket"];
    assert_eq!(ticket["contact_id"], LUC, "found by the caller's number");
    assert_eq!(ticket["customer_name"], "Bêta Industrie SA");
    assert_eq!(ticket["subject"], "Pump is noisy.");
    assert_eq!(ticket["category"], "service");
    assert_eq!(ticket["language"], "nl");
    assert_eq!(ticket["status"], "open");
    assert_eq!(ticket["owner_name"], "Support Agent");
    let a = &t["articles"][0];
    assert_eq!(a["kind"], "call_in");
    assert_eq!(a["phone_number"], "+32 478 00 00 44");
    assert_eq!(a["duration_seconds"], 240);
    assert_eq!(a["contact_name"], "Luc Claes");
    assert_eq!(a["author_name"], "Support Agent");
    assert_eq!(a["delivery"], Value::Null, "nothing is sent for a call");

    // Calling back is a response; the call is added to the same ticket.
    let id = ticket["id"].as_str().unwrap();
    let (status, t) = post(&app, SALES, "/api/v1/helpdesk/calls", json!({
        "ticket_id": id, "direction": "out", "phone_number": "+32 478 00 00 44", "summary": "Technician comes Thursday."
    })).await;
    assert_eq!(status, StatusCode::CREATED, "{t}");
    assert_eq!(t["articles"].as_array().unwrap().len(), 2);
    assert_eq!(t["articles"][1]["kind"], "call_out");
    assert!(t["ticket"]["first_response_at"].is_string());

    // The customer calls again after we asked a question: that reopens the ticket.
    let mut update = json!({
        "subject": "Pump", "status": "pending_customer", "priority": "normal", "category": "service",
        "language": "nl", "owner_user_id": null, "customer_id": BETA, "contact_id": LUC,
        "contact_name": "Luc Claes", "contact_email": "luc.claes@beta.example"
    });
    update["status"] = json!("pending_customer");
    call(
        &app,
        SUPPORT,
        Method::PUT,
        &format!("/api/v1/tickets/{id}"),
        Some(update),
    )
    .await;
    let (_, t) = post(&app, SUPPORT, "/api/v1/helpdesk/calls", json!({
        "ticket_id": id, "direction": "in", "phone_number": "0478 00 00 44", "summary": "Thursday is fine."
    })).await;
    assert_eq!(t["ticket"]["status"], "open");

    // Validation.
    for body in [
        json!({ "direction": "sideways", "summary": "x" }),
        json!({ "direction": "in", "summary": "  " }),
        json!({ "direction": "in", "summary": "x", "duration_seconds": -5 }),
        json!({ "direction": "in", "summary": "x", "contact_id": LUC, "customer_id": ALPHA }),
    ] {
        assert_eq!(
            post(&app, SUPPORT, "/api/v1/helpdesk/calls", body).await.0,
            StatusCode::UNPROCESSABLE_ENTITY
        );
    }
    assert_eq!(
        post(
            &app,
            VIEWER,
            "/api/v1/helpdesk/calls",
            json!({ "direction": "in", "summary": "x" })
        )
        .await
        .0,
        StatusCode::FORBIDDEN
    );
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn an_unknown_or_ambiguous_caller_is_not_guessed(db: PgPool) {
    let app = setup(db).await;
    // Unknown number: the agent picks the customer; no person is linked.
    let (status, t) = post(
        &app,
        SUPPORT,
        "/api/v1/helpdesk/calls",
        json!({
            "direction": "in", "phone_number": "+32 499 99 99 99", "customer_id": ALPHA,
            "subject": "Unknown caller", "summary": "Asked about prices."
        }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{t}");
    assert_eq!(t["ticket"]["contact_id"], Value::Null);
    assert_eq!(t["ticket"]["customer_id"], ALPHA);
    assert_eq!(t["ticket"]["language"], "nl");

    // Two people share a switchboard number: nobody is picked automatically ...
    for last in ["Switch One", "Switch Two"] {
        let (s, c) = post(
            &app,
            SALES,
            &format!("/api/v1/customers/{ALPHA}/contacts"),
            json!({
                "last_name": last, "phones": [{ "number": "+32 3 123 45 67" }]
            }),
        )
        .await;
        assert_eq!(s, StatusCode::CREATED, "{c}");
    }
    let (_, r) = get(
        &app,
        SUPPORT,
        "/api/v1/contacts/lookup?phone=%2B32%203%20123%2045%2067",
    )
    .await;
    assert_eq!(r["contacts"].as_array().unwrap().len(), 2);
    let (_, t) = post(
        &app,
        SUPPORT,
        "/api/v1/helpdesk/calls",
        json!({
            "direction": "in", "phone_number": "03 123 45 67", "summary": "From the switchboard."
        }),
    )
    .await;
    assert_eq!(t["ticket"]["contact_id"], Value::Null);
    // ... but the agent can choose, and the first identified call completes the ticket.
    let id = t["ticket"]["id"].as_str().unwrap();
    let who = r["contacts"][0]["id"].as_str().unwrap();
    let (_, t) = post(
        &app,
        SUPPORT,
        "/api/v1/helpdesk/calls",
        json!({
            "ticket_id": id, "direction": "in", "contact_id": who, "summary": "It was Switch One."
        }),
    )
    .await;
    assert_eq!(t["ticket"]["contact_id"], who);
    assert_eq!(t["ticket"]["customer_id"], ALPHA);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn prepared_answers_greet_the_person_the_way_they_want(db: PgPool) {
    let app = setup(db).await;
    let (_, a) = post(
        &app,
        SUPPORT,
        "/api/v1/prepared-answers",
        json!({
            "code": "hi", "name": "Hi",
            "texts": [{ "language": "nl", "subject": "Bedankt", "body": "{{contact.salutation}}\n\nBedankt." },
                      { "language": "fr", "subject": "Merci", "body": "{{contact.salutation}}\n\nMerci." }]
        }),
    )
    .await;
    let answer = a["id"].as_str().unwrap();
    let render = |ticket: String| {
        let app = app.clone();
        let uri = format!("/api/v1/tickets/{ticket}/prepared-answers/{answer}/render");
        async move { post(&app, SUPPORT, &uri, json!({})).await.1 }
    };
    // Luc: Dutch and informal although his company is French-speaking.
    let (_, t) = post(
        &app,
        SUPPORT,
        "/api/v1/tickets",
        json!({ "subject": "a", "contact_id": LUC, "body": "x" }),
    )
    .await;
    let r = render(t["ticket"]["id"].as_str().unwrap().to_string()).await;
    assert_eq!(r["language"], "nl");
    assert_eq!(r["body"], "Dag Luc,\n\nBedankt.");
    // Marie: French and formal.
    let (_, t) = post(
        &app,
        SUPPORT,
        "/api/v1/tickets",
        json!({
            "subject": "b", "contact_id": "00000000-0000-7000-8000-000000000603", "body": "x"
        }),
    )
    .await;
    let r = render(t["ticket"]["id"].as_str().unwrap().to_string()).await;
    assert_eq!(r["body"], "Bonjour Madame Dupont,\n\nMerci.");
    // Without a person the placeholder stays visible for the agent to fill in.
    let (_, t) = post(
        &app,
        SUPPORT,
        "/api/v1/tickets",
        json!({ "subject": "c", "customer_id": ALPHA, "body": "x" }),
    )
    .await;
    let r = render(t["ticket"]["id"].as_str().unwrap().to_string()).await;
    assert_eq!(r["body"], "{{contact.salutation}}\n\nBedankt.");
}
