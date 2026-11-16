//! Prepared answers as templates: kinds, team scope, keywords, suggestions, mail rules (ADR 0071).

mod common;

use axum::http::{Method, StatusCode};
#[allow(unused_imports)]
use common::{call, call_raw, setup};
use serde_json::{json, Value};
use sqlx::PgPool;

const ADMIN: &str = "admin@example.com";
const SUPPORT: &str = "support@example.com";

async fn api(
    app: &axum::Router,
    user: &str,
    method: Method,
    uri: &str,
    body: Option<Value>,
) -> (StatusCode, Value) {
    call(app, user, method, &format!("/api/v1{uri}"), body).await
}
async fn get(app: &axum::Router, user: &str, uri: &str) -> (StatusCode, Value) {
    api(app, user, Method::GET, uri, None).await
}
async fn post(app: &axum::Router, user: &str, uri: &str, body: Value) -> (StatusCode, Value) {
    api(app, user, Method::POST, uri, Some(body)).await
}
async fn put(app: &axum::Router, user: &str, uri: &str, body: Value) -> (StatusCode, Value) {
    api(app, user, Method::PUT, uri, Some(body)).await
}

async fn team(app: &axum::Router, name: &str) -> String {
    let (status, t) = post(app, ADMIN, "/helpdesk/teams", json!({ "name": name })).await;
    assert_eq!(status, StatusCode::CREATED, "{t}");
    t["id"].as_str().unwrap().to_string()
}

fn answer(code: &str, extra: Value) -> Value {
    let mut a = json!({
        "code": code, "name": code,
        "texts": [{ "language": "en", "subject": "Re: {{ticket.subject}}", "body": "Hello {{contact.name}}" }]
    });
    for (k, v) in extra.as_object().unwrap() {
        a[k] = v.clone();
    }
    a
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn an_answer_has_a_kind_a_team_and_clean_keywords(db: PgPool) {
    let app = setup(db).await;
    let rd = team(&app, "R&D").await;
    let (status, a) = post(
        &app,
        SUPPORT,
        "/prepared-answers",
        answer(
            "firmware",
            json!({ "kind": "internal_note", "team_id": rd, "keywords": [" Firmware ", "firmware", "UPDATE", ""] }),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{a}");
    assert_eq!(a["kind"], "internal_note");
    assert_eq!(a["team_id"], rd.as_str());
    assert_eq!(a["keywords"], json!(["firmware", "update"]));
    // Default kind is a reply, company-wide.
    let (_, plain) = post(&app, SUPPORT, "/prepared-answers", answer("plain", json!({}))).await;
    assert_eq!(plain["kind"], "reply");
    assert!(plain["team_id"].is_null());
    assert_eq!(plain["keywords"], json!([]));
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn kind_team_and_keywords_are_validated(db: PgPool) {
    let app = setup(db).await;
    let (status, _) = post(&app, SUPPORT, "/prepared-answers", answer("a", json!({ "kind": "shout" }))).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    let (status, _) = post(
        &app,
        SUPPORT,
        "/prepared-answers",
        answer("b", json!({ "team_id": "00000000-0000-7000-8000-00000000dead" })),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let long = "x".repeat(41);
    let (status, _) = post(&app, SUPPORT, "/prepared-answers", answer("c", json!({ "keywords": [long] }))).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_list_filters_by_kind_and_by_the_team_that_can_use_the_answer(db: PgPool) {
    let app = setup(db.clone()).await;
    sqlx::query("DELETE FROM helpdesk.prepared_answers")
        .execute(&db)
        .await
        .unwrap();
    let rd = team(&app, "R&D").await;
    let net = team(&app, "Network").await;
    post(&app, SUPPORT, "/prepared-answers", answer("everyone", json!({}))).await;
    post(&app, SUPPORT, "/prepared-answers", answer("rd-note", json!({ "kind": "internal_note", "team_id": rd }))).await;
    post(&app, SUPPORT, "/prepared-answers", answer("net-reply", json!({ "team_id": net }))).await;
    let codes = |v: &Value| -> Vec<String> {
        let mut c: Vec<String> = v.as_array().unwrap().iter().map(|a| a["code"].as_str().unwrap().to_string()).collect();
        c.sort();
        c
    };
    let (_, all) = get(&app, SUPPORT, "/prepared-answers").await;
    assert_eq!(codes(&all), ["everyone", "net-reply", "rd-note"]);
    let (_, notes) = get(&app, SUPPORT, "/prepared-answers?kind=internal_note").await;
    assert_eq!(codes(&notes), ["rd-note"]);
    // A network ticket sees company-wide answers and the network's own.
    let (_, for_net) = get(&app, SUPPORT, &format!("/prepared-answers?team_id={net}")).await;
    assert_eq!(codes(&for_net), ["everyone", "net-reply"]);
    // Update keeps working and can move an answer to another team.
    let id = all.as_array().unwrap().iter().find(|a| a["code"] == "net-reply").unwrap()["id"].as_str().unwrap().to_string();
    let (status, moved) = put(&app, SUPPORT, &format!("/prepared-answers/{id}"), answer("net-reply", json!({ "team_id": rd }))).await;
    assert_eq!(status, StatusCode::OK, "{moved}");
    assert_eq!(moved["team_id"], rd.as_str());
}

/// A ticket made by hand; its id is read back from the database.
async fn manual_ticket(app: &axum::Router, db: &PgPool, user: &str, subject: &str, extra: Value) -> String {
    let mut body = json!({ "subject": subject, "body": "asked", "category": "question" });
    for (k, v) in extra.as_object().unwrap() {
        body[k] = v.clone();
    }
    let (status, r) = post(app, user, "/tickets", body).await;
    assert_eq!(status, StatusCode::CREATED, "{r}");
    sqlx::query_scalar("SELECT id::text FROM helpdesk.tickets WHERE subject = $1")
        .bind(subject)
        .fetch_one(db)
        .await
        .unwrap()
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_team_name_is_filled_in_for_a_ticket_of_that_team(db: PgPool) {
    let app = setup(db.clone()).await;
    let rd = team(&app, "R&D").await;
    let (_, a) = post(
        &app,
        SUPPORT,
        "/prepared-answers",
        answer("who", json!({ "texts": [{ "language": "en", "body": "Team: {{team.name}}" }] })),
    )
    .await;
    let ticket = manual_ticket(&app, &db, SUPPORT, "Needs R&D", json!({})).await;
    sqlx::query("UPDATE helpdesk.tickets SET team_id = $2::uuid WHERE id = $1::uuid")
        .bind(&ticket)
        .bind(&rd)
        .execute(&db)
        .await
        .unwrap();
    let uri = format!("/tickets/{ticket}/prepared-answers/{}/render", a["id"].as_str().unwrap());
    let (status, r) = post(&app, SUPPORT, &uri, json!({})).await;
    assert_eq!(status, StatusCode::OK, "{r}");
    assert_eq!(r["body"], "Team: R&D");
}

async fn language_of(db: &PgPool, subject: &str) -> (String, String) {
    sqlx::query_as(
        "SELECT language::text, language_source FROM helpdesk.tickets WHERE subject = $1",
    )
    .bind(subject)
    .fetch_one(db)
    .await
    .unwrap()
}

fn mail(from: &str, subject: &str, body: &str) -> Vec<u8> {
    format!("From: {from}\r\nTo: sales@example.com\r\nSubject: {subject}\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n{body}\r\n").into_bytes()
}

async fn receive(app: &axum::Router, from: &str, subject: &str, body: &str) -> String {
    let (status, r) = call_raw(app, SUPPORT, "/api/v1/helpdesk/inbound", "message/rfc822", mail(from, subject, body)).await;
    assert_eq!(status, StatusCode::OK, "{r}");
    r["ticket_id"].as_str().unwrap().to_string()
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn an_internal_ticket_takes_the_creators_language(db: PgPool) {
    let app = setup(db.clone()).await;
    sqlx::query("UPDATE core.companies SET default_language = 'en'").execute(&db).await.unwrap();
    sqlx::query("UPDATE core.users SET language = 'fr' WHERE email = $1")
        .bind(SUPPORT)
        .execute(&db)
        .await
        .unwrap();
    manual_ticket(&app, &db, SUPPORT, "Switch config", json!({ "internal": true })).await;
    assert_eq!(language_of(&db, "Switch config").await, ("fr".into(), "record".into()));
    // Without a language on the creator the company default applies.
    sqlx::query("UPDATE core.users SET language = NULL WHERE email = $1").bind(SUPPORT).execute(&db).await.unwrap();
    manual_ticket(&app, &db, SUPPORT, "Switch config 2", json!({ "internal": true })).await;
    assert_eq!(language_of(&db, "Switch config 2").await, ("en".into(), "record".into()));
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_language_given_or_changed_by_an_agent_is_marked_as_theirs(db: PgPool) {
    let app = setup(db.clone()).await;
    let id = manual_ticket(&app, &db, SUPPORT, "Given", json!({ "language": "de" })).await;
    assert_eq!(language_of(&db, "Given").await, ("de".into(), "agent".into()));
    let other = manual_ticket(&app, &db, SUPPORT, "Not given", json!({})).await;
    assert_eq!(language_of(&db, "Not given").await.1, "record");
    // Saving the ticket with the same language keeps the source; another language makes it the agent's.
    let body = |lang: &str| json!({ "subject": "Not given", "status": "open", "priority": "normal", "category": "question", "language": lang });
    let current = language_of(&db, "Not given").await.0;
    let (status, r) = put(&app, SUPPORT, &format!("/tickets/{other}"), body(&current)).await;
    assert_eq!(status, StatusCode::OK, "{r}");
    assert_eq!(language_of(&db, "Not given").await.1, "record");
    let changed = if current == "es" { "nl" } else { "es" };
    let (status, r) = put(&app, SUPPORT, &format!("/tickets/{other}"), body(changed)).await;
    assert_eq!(status, StatusCode::OK, "{r}");
    assert_eq!(language_of(&db, "Not given").await, (changed.into(), "agent".into()));
    let _ = id;
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_detected_language_is_marked_as_detected_and_a_known_customer_is_not(db: PgPool) {
    let app = setup(db.clone()).await;
    // Unknown sender, French text: the detector decides.
    receive(
        &app,
        "inconnu@nowhere.example",
        "Commande",
        "Bonjour, nous avons bien reçu le devis et nous voudrions passer la commande. Merci et cordialement",
    )
    .await;
    assert_eq!(language_of(&db, "Commande").await, ("fr".into(), "detected".into()));
    // Unknown sender, no usable text: the company default, not marked as detected.
    receive(&app, "other@nowhere.example", "OK", "OK").await;
    assert_eq!(language_of(&db, "OK").await.1, "record");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn suggestions_are_ranked_rendered_in_the_ticket_language_and_scoped_to_the_team(db: PgPool) {
    let app = setup(db.clone()).await;
    let rd = team(&app, "R&D").await;
    let net = team(&app, "Network").await;
    post(&app, SUPPORT, "/prepared-answers", answer("firmware", json!({ "keywords": ["firmware"] }))).await;
    post(&app, SUPPORT, "/prepared-answers", answer("generic", json!({}))).await;
    post(&app, SUPPORT, "/prepared-answers", answer("rd-only", json!({ "team_id": rd, "keywords": ["firmware"] }))).await;
    post(&app, SUPPORT, "/prepared-answers", answer("net-only", json!({ "team_id": net, "keywords": ["firmware"] }))).await;
    post(&app, SUPPORT, "/prepared-answers", answer("note", json!({ "kind": "internal_note" }))).await;
    let ticket = manual_ticket(&app, &db, SUPPORT, "Firmware update fails", json!({})).await;
    sqlx::query("UPDATE helpdesk.tickets SET team_id = $2::uuid, language = 'en' WHERE id = $1::uuid")
        .bind(&ticket)
        .bind(&rd)
        .execute(&db)
        .await
        .unwrap();
    let (status, r) = get(&app, SUPPORT, &format!("/tickets/{ticket}/prepared-answers/suggest?kind=reply")).await;
    assert_eq!(status, StatusCode::OK, "{r}");
    let codes: Vec<&str> = r.as_array().unwrap().iter().map(|s| s["code"].as_str().unwrap()).collect();
    // The R&D answer ranks first (keyword and team), the network's and the note are left out.
    assert_eq!(codes.first(), Some(&"rd-only"), "{codes:?}");
    assert!(codes.contains(&"firmware") && codes.contains(&"generic"));
    assert!(!codes.contains(&"net-only") && !codes.contains(&"note"), "{codes:?}");
    let first = &r[0];
    assert_eq!(first["language"], "en");
    assert_eq!(first["subject"], "Re: Firmware update fails");
    // A query narrows the list; nothing matches a nonsense query.
    let (_, q) = get(&app, SUPPORT, &format!("/tickets/{ticket}/prepared-answers/suggest?kind=reply&q=gener")).await;
    assert_eq!(q.as_array().unwrap().len(), 1);
    let (_, none) = get(&app, SUPPORT, &format!("/tickets/{ticket}/prepared-answers/suggest?q=zzzz")).await;
    assert!(none.as_array().unwrap().is_empty());
}


async fn outbox(db: &PgPool) -> Vec<(String, String, String)> {
    sqlx::query_as(
        "SELECT to_address, subject, body FROM core.mail_outbox WHERE delivery = 'queued' ORDER BY created_at, id",
    )
    .fetch_all(db)
    .await
    .unwrap()
}

fn mail_rule(answer: Option<&str>) -> Value {
    let mut action = json!({ "kind": "send_email", "recipient": "address", "address": "ops@example.com" });
    match answer {
        Some(id) => action["answer_id"] = json!(id),
        None => {
            action["subject"] = json!("Inline {ticket_number}");
            action["body"] = json!("Inline body");
        }
    }
    json!({ "name": "Mail ops", "trigger": "created", "actions": [action] })
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_send_email_rule_uses_the_template_in_the_ticket_language(db: PgPool) {
    let app = setup(db.clone()).await;
    let (_, a) = post(
        &app,
        SUPPORT,
        "/prepared-answers",
        json!({ "code": "ops", "name": "Ops", "texts": [
            { "language": "en", "subject": "New {{ticket.number}}", "body": "English for {{ticket.subject}}" },
            { "language": "fr", "subject": "Nouveau {{ticket.number}}", "body": "Français pour {{ticket.subject}}" }
        ] }),
    )
    .await;
    let id = a["id"].as_str().unwrap();
    let (status, r) = post(&app, ADMIN, "/helpdesk/automation/rules", mail_rule(Some(id))).await;
    assert_eq!(status, StatusCode::CREATED, "{r}");
    receive(
        &app,
        "inconnu@nowhere.example",
        "Commande",
        "Bonjour, nous avons bien reçu le devis et nous voudrions passer la commande. Merci et cordialement",
    )
    .await;
    let mails = outbox(&db).await;
    assert_eq!(mails.len(), 1, "{mails:?}");
    let (to, subject, body) = &mails[0];
    assert_eq!(to, "ops@example.com");
    assert!(subject.starts_with("Nouveau T"), "{subject}");
    assert_eq!(body, "Français pour Commande");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_rule_with_a_template_is_validated_when_saved(db: PgPool) {
    let app = setup(db).await;
    // Unknown template.
    let (status, _) = post(&app, ADMIN, "/helpdesk/automation/rules", mail_rule(Some("00000000-0000-7000-8000-00000000dead"))).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    // A typo in a placeholder would reach the customer: refused.
    let (_, typo) = post(&app, SUPPORT, "/prepared-answers", json!({ "code": "typo", "name": "Typo",
        "texts": [{ "language": "en", "subject": "Hi", "body": "Dear {{contact.nme}}" }] })).await;
    let (status, r) = post(&app, ADMIN, "/helpdesk/automation/rules", mail_rule(Some(typo["id"].as_str().unwrap()))).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{r}");
    assert!(r["message"].as_str().unwrap().contains("contact.nme"), "{r}");
    // Every language needs a subject.
    let (_, nosub) = post(&app, SUPPORT, "/prepared-answers", json!({ "code": "nosub", "name": "No subject",
        "texts": [{ "language": "en", "body": "Hi" }] })).await;
    let (status, _) = post(&app, ADMIN, "/helpdesk/automation/rules", mail_rule(Some(nosub["id"].as_str().unwrap()))).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn inline_mail_rules_keep_working_and_internal_tickets_get_no_customer_mail(db: PgPool) {
    let app = setup(db.clone()).await;
    let (status, r) = post(&app, ADMIN, "/helpdesk/automation/rules", mail_rule(None)).await;
    assert_eq!(status, StatusCode::CREATED, "{r}");
    receive(&app, "anna@nowhere.example", "Hello", "Hello there").await;
    let mails = outbox(&db).await;
    assert_eq!(mails.len(), 1);
    assert!(mails[0].1.starts_with("Inline T"), "{:?}", mails[0]);
    // A rule that mails the customer does nothing for an internal ticket.
    let to_customer = json!({ "name": "To customer", "trigger": "created", "actions": [
        { "kind": "send_email", "recipient": "customer", "subject": "Hi", "body": "Hi" }] });
    post(&app, ADMIN, "/helpdesk/automation/rules", to_customer).await;
    let before = outbox(&db).await.len();
    manual_ticket(&app, &db, SUPPORT, "Colleague question", json!({ "internal": true })).await;
    let after: Vec<_> = outbox(&db).await;
    assert!(after.iter().skip(before).all(|m| m.0 != "customer@example.com"), "{after:?}");
    assert_eq!(after.len(), before + 1, "only the inline ops mail: {after:?}");
}
