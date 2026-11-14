//! SLA notices to the customer (ADR 0064).

mod common;

use axum::http::{Method, StatusCode};
use common::{call, call_raw, setup};
use serde_json::{json, Value};
use sqlx::PgPool;

const ALPHA: &str = "00000000-0000-7000-8000-000000000401";
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
async fn put(app: &axum::Router, user: &str, uri: &str, body: Value) -> (StatusCode, Value) {
    api(app, user, Method::PUT, uri, Some(body)).await
}
async fn post(app: &axum::Router, user: &str, uri: &str, body: Value) -> (StatusCode, Value) {
    api(app, user, Method::POST, uri, Some(body)).await
}

async fn notices(app: &axum::Router, rules: Value) -> (StatusCode, Value) {
    put(
        app,
        ADMIN,
        "/helpdesk/sla-notices",
        json!({ "rules": rules }),
    )
    .await
}

fn mail(from: &str, subject: &str) -> Vec<u8> {
    format!("From: {from}\r\nTo: sales@example.com\r\nSubject: {subject}\r\nContent-Type: text/plain; charset=utf-8\r\n\r\nHello there\r\n").into_bytes()
}

/// Receives a mail and returns (ticket id, number).
async fn receive(app: &axum::Router, from: &str, subject: &str) -> (String, String) {
    let (status, r) = call_raw(
        app,
        SUPPORT,
        "/api/v1/helpdesk/inbound",
        "message/rfc822",
        mail(from, subject),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{r}");
    (
        r["ticket_id"].as_str().unwrap().to_string(),
        r["ticket_number"].as_str().unwrap().to_string(),
    )
}

/// (to, subject, body) of every queued system mail.
async fn outbox(db: &PgPool) -> Vec<(String, String, String)> {
    sqlx::query_as(
        "SELECT to_address, subject, body FROM core.mail_outbox WHERE delivery = 'queued' ORDER BY created_at, id",
    )
    .fetch_all(db)
    .await
    .unwrap()
}

async fn all_priorities(app: &axum::Router, ack: bool, breach: bool) {
    let (status, r) = notices(
        app,
        json!([{ "team_id": null, "priority": null, "ack_enabled": ack, "breach_enabled": breach }]),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{r}");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn nothing_is_sent_until_the_notices_are_switched_on(db: PgPool) {
    let app = setup(db.clone()).await;
    receive(&app, "anna@alpha.example", "Pump noise").await;
    assert!(outbox(&db).await.is_empty());
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_new_ticket_is_acknowledged_with_number_and_target_in_the_customers_language(db: PgPool) {
    let app = setup(db.clone()).await;
    all_priorities(&app, true, false).await;
    sqlx::query("UPDATE crm.customers SET language = 'fr' WHERE id = $1::uuid")
        .bind(ALPHA)
        .execute(&db)
        .await
        .unwrap();
    let (id, number) = receive(&app, "anna@alpha.example", "Pump noise").await;
    let mails = outbox(&db).await;
    assert_eq!(mails.len(), 1, "{mails:?}");
    let (to, subject, body) = &mails[0];
    assert_eq!(to, "anna@alpha.example");
    assert!(subject.contains(&format!("[Ticket#{number}]")), "{subject}");
    assert!(subject.contains("Nous avons bien reçu"), "{subject}");
    assert!(
        body.contains(&number) && body.contains("Pump noise"),
        "{body}"
    );
    // Normal priority: 480 minutes first response.
    assert!(body.contains("8 heures"), "{body}");
    assert!(body.contains("Europe/Brussels"), "{body}");
    let n: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM audit.events WHERE entity_id = $1::uuid AND action = 'sla_ack_sent' AND user_id IS NULL",
    )
    .bind(&id)
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(n, 1);
    // Staff-made tickets and automated senders are not acknowledged.
    let (status, _) = post(
        &app,
        SUPPORT,
        "/tickets",
        json!({ "subject": "Phone", "customer_id": ALPHA, "contact_email": "bob@alpha.example", "body": "x" }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);
    receive(&app, "noreply@alpha.example", "Automatic").await;
    assert_eq!(outbox(&db).await.len(), 1);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn settings_are_per_team_and_priority_and_the_most_specific_wins(db: PgPool) {
    let app = setup(db.clone()).await;
    // On for everybody, off for urgent tickets.
    let (status, r) = notices(
        &app,
        json!([
            { "team_id": null, "priority": null, "ack_enabled": true, "breach_enabled": false },
            { "team_id": null, "priority": "urgent", "ack_enabled": false, "breach_enabled": false },
        ]),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{r}");
    assert_eq!(r["rules"].as_array().unwrap().len(), 2);
    receive(&app, "a@alpha.example", "Normal").await;
    assert_eq!(outbox(&db).await.len(), 1);
    // An automation rule makes the ticket urgent before the acknowledgement is decided.
    post(
        &app,
        ADMIN,
        "/helpdesk/automation/rules",
        json!({ "name": "Urgent", "trigger": "created", "conditions": { "subject_contains": "fire" },
            "actions": [{ "kind": "set_priority", "value": "urgent" }] }),
    )
    .await;
    receive(&app, "b@alpha.example", "Fire in the hall").await;
    assert_eq!(outbox(&db).await.len(), 1, "urgent is switched off");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn settings_are_validated_audited_and_for_administrators(db: PgPool) {
    let app = setup(db.clone()).await;
    let (status, _) = put(
        &app,
        SUPPORT,
        "/helpdesk/sla-notices",
        json!({ "rules": [] }),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, _) = api(&app, SUPPORT, Method::GET, "/helpdesk/sla-notices", None).await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let bad =
        json!({ "team_id": null, "priority": "huge", "ack_enabled": true, "breach_enabled": true });
    assert_eq!(
        notices(&app, json!([bad])).await.0,
        StatusCode::UNPROCESSABLE_ENTITY
    );
    let dup =
        json!({ "team_id": null, "priority": "low", "ack_enabled": true, "breach_enabled": true });
    assert_eq!(
        notices(&app, json!([dup, dup])).await.0,
        StatusCode::UNPROCESSABLE_ENTITY
    );
    let unknown = json!({ "team_id": "00000000-0000-7000-8000-00000000dead", "priority": null, "ack_enabled": true, "breach_enabled": true });
    assert_eq!(
        notices(&app, json!([unknown])).await.0,
        StatusCode::NOT_FOUND
    );
    // Another company's team is not found either.
    let (_, team) = post(
        &app,
        ADMIN,
        "/helpdesk/teams",
        json!({ "name": "Support", "members": [] }),
    )
    .await;
    let ok = json!({ "team_id": team["id"], "priority": "high", "ack_enabled": true, "breach_enabled": true });
    let (status, r) = notices(&app, json!([ok])).await;
    assert_eq!(status, StatusCode::OK, "{r}");
    let (_, got) = api(&app, ADMIN, Method::GET, "/helpdesk/sla-notices", None).await;
    assert_eq!(got["rules"][0]["priority"], "high");
    let n: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM audit.events WHERE action = 'sla_notices_updated'",
    )
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(n, 1);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_breach_notice_is_sent_once_for_an_unanswered_ticket(db: PgPool) {
    let app = setup(db.clone()).await;
    all_priorities(&app, false, true).await;
    let (id, number) = receive(&app, "anna@alpha.example", "Pump noise").await;
    // Not late yet.
    assert_eq!(
        tradocraft_helpdesk::sla_notice::send_breach_notices(&db)
            .await
            .unwrap(),
        0
    );
    sqlx::query("UPDATE helpdesk.tickets SET first_response_due_at = now() - interval '1 hour' WHERE id = $1::uuid")
        .bind(&id)
        .execute(&db)
        .await
        .unwrap();
    assert_eq!(
        tradocraft_helpdesk::sla_notice::send_breach_notices(&db)
            .await
            .unwrap(),
        1
    );
    let mails = outbox(&db).await;
    assert_eq!(mails.len(), 1);
    assert_eq!(mails[0].0, "anna@alpha.example");
    assert!(mails[0].1.contains(&format!("[Ticket#{number}]")));
    // Once per ticket.
    assert_eq!(
        tradocraft_helpdesk::sla_notice::send_breach_notices(&db)
            .await
            .unwrap(),
        0
    );
    // An answered ticket is not reported.
    let (other, _) = receive(&app, "bob@alpha.example", "Valve").await;
    sqlx::query("UPDATE helpdesk.tickets SET first_response_due_at = now() - interval '1 hour', first_response_at = now() WHERE id = $1::uuid")
        .bind(&other)
        .execute(&db)
        .await
        .unwrap();
    assert_eq!(
        tradocraft_helpdesk::sla_notice::send_breach_notices(&db)
            .await
            .unwrap(),
        0
    );
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_breach_notice_waits_for_the_opening_hours(db: PgPool) {
    let app = setup(db.clone()).await;
    all_priorities(&app, false, true).await;
    let (id, _) = receive(&app, "anna@alpha.example", "Pump noise").await;
    sqlx::query("UPDATE helpdesk.tickets SET first_response_due_at = now() - interval '1 hour' WHERE id = $1::uuid")
        .bind(&id)
        .execute(&db)
        .await
        .unwrap();
    // A calendar that is open on no day but today's neighbours: closed all week except a weekday
    // that is not today, so the business is closed right now.
    let today: i32 =
        sqlx::query_scalar("SELECT extract(isodow FROM now() AT TIME ZONE 'Europe/Brussels')::int")
            .fetch_one(&db)
            .await
            .unwrap();
    let other = if today == 1 { 2 } else { 1 };
    let (status, r) = put(
        &app,
        ADMIN,
        "/helpdesk/calendar",
        json!({ "enabled": true, "time_zone": "Europe/Brussels",
            "hours": [{ "weekday": other, "start_time": "09:00", "end_time": "17:00" }] }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{r}");
    assert_eq!(
        tradocraft_helpdesk::sla_notice::send_breach_notices(&db)
            .await
            .unwrap(),
        0,
        "closed: wait"
    );
    // Open around the clock today: the notice goes out.
    let (status, r) = put(
        &app,
        ADMIN,
        "/helpdesk/calendar",
        json!({ "enabled": true, "time_zone": "Europe/Brussels",
            "hours": [{ "weekday": today, "start_time": "00:00", "end_time": "23:59" }] }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{r}");
    // The calendar change recomputed the due time to the business clock: make it late again.
    sqlx::query("UPDATE helpdesk.tickets SET first_response_due_at = now() - interval '1 hour' WHERE id = $1::uuid")
        .bind(&id)
        .execute(&db)
        .await
        .unwrap();
    let local_minutes: i32 = sqlx::query_scalar(
        "SELECT (extract(hour FROM now() AT TIME ZONE 'Europe/Brussels') * 60 + extract(minute FROM now() AT TIME ZONE 'Europe/Brussels'))::int",
    )
    .fetch_one(&db)
    .await
    .unwrap();
    if local_minutes < 24 * 60 - 1 {
        assert_eq!(
            tradocraft_helpdesk::sla_notice::send_breach_notices(&db)
                .await
                .unwrap(),
            1
        );
    }
}
