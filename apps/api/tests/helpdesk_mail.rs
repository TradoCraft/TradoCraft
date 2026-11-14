//! Helpdesk customer mail (ADR 0063): the `send_email` automation action.

mod common;

use axum::http::{Method, StatusCode};
use common::{call, setup};
use serde_json::{json, Value};
use sqlx::PgPool;

const ALPHA: &str = "00000000-0000-7000-8000-000000000401";
const ADMIN: &str = "admin@example.com";
const SALES: &str = "sales@example.com";
const SUPPORT: &str = "support@example.com";
const SUPPORT_ID: &str = "00000000-0000-7000-8000-000000000105";

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

async fn new_ticket(app: &axum::Router, subject: &str) -> String {
    let (status, t) = post(
        app,
        SALES,
        "/tickets",
        json!({ "subject": subject, "customer_id": ALPHA, "contact_email": "anna@alpha.example", "body": "First note" }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{t}");
    t["ticket"]["id"].as_str().unwrap().to_string()
}

/// Saves the ticket with another priority (the full update call).
async fn set_priority(app: &axum::Router, id: &str, priority: &str) {
    let (_, d) = api(app, SUPPORT, Method::GET, &format!("/tickets/{id}"), None).await;
    let t = &d["ticket"];
    let (code, r) = put(
        app,
        SUPPORT,
        &format!("/tickets/{id}"),
        json!({
            "subject": t["subject"], "status": t["status"], "priority": priority,
            "category": t["category"], "language": t["language"], "owner_user_id": t["owner_user_id"],
            "customer_id": t["customer_id"], "contact_id": t["contact_id"],
            "contact_name": t["contact_name"], "contact_email": t["contact_email"],
        }),
    )
    .await;
    assert_eq!(code, StatusCode::OK, "{r}");
}

async fn rule(app: &axum::Router, body: Value) -> Value {
    let (status, r) = post(app, ADMIN, "/helpdesk/automation/rules", body).await;
    assert_eq!(status, StatusCode::CREATED, "{r}");
    r
}

/// (to, subject, body) of every queued system mail, oldest first.
async fn outbox(db: &PgPool) -> Vec<(String, String, String)> {
    sqlx::query_as(
        "SELECT to_address, subject, body FROM core.mail_outbox WHERE delivery = 'queued' ORDER BY created_at, id",
    )
    .fetch_all(db)
    .await
    .unwrap()
}

fn mail_action(recipient: &str) -> Value {
    json!({ "kind": "send_email", "recipient": recipient,
        "subject": "Ticket {ticket_number}: {subject}",
        "body": "Dear {customer}, ticket {ticket_number} about {subject} is handled by {agent}." })
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_mail_has_the_placeholders_filled_in_and_goes_through_the_outbox(db: PgPool) {
    let app = setup(db.clone()).await;
    rule(
        &app,
        json!({ "name": "Tell the customer", "trigger": "created",
            "conditions": { "subject_contains": "pump" },
            "actions": [{ "kind": "set_owner", "user_id": SUPPORT_ID }, mail_action("customer")] }),
    )
    .await;
    let id = new_ticket(&app, "Pump leaks").await;
    let (_, t) = api(&app, SUPPORT, Method::GET, &format!("/tickets/{id}"), None).await;
    let number = t["ticket"]["number"].as_str().unwrap().to_string();
    let mails = outbox(&db).await;
    assert_eq!(mails.len(), 1, "{mails:?}");
    assert_eq!(mails[0].0, "anna@alpha.example");
    assert_eq!(mails[0].1, format!("Ticket {number}: Pump leaks"));
    assert!(mails[0]
        .2
        .contains(&format!("ticket {number} about Pump leaks")));
    // The agent placeholder reads the owner the earlier action set.
    assert!(!mails[0].2.contains("handled by ."), "{}", mails[0].2);
    // Audited without a user (it is the system).
    let n: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM audit.events WHERE entity_id = $1::uuid AND action = 'automation_mail_queued' AND user_id IS NULL",
    )
    .bind(&id)
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(n, 1);
    // A ticket that does not match gets nothing.
    new_ticket(&app, "Quotation").await;
    assert_eq!(outbox(&db).await.len(), 1);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_loop_guard_allows_one_mail_per_ticket_and_rule_in_the_period(db: PgPool) {
    let app = setup(db.clone()).await;
    // The address is required for that recipient.
    let (status, _) = post(
        &app,
        ADMIN,
        "/helpdesk/automation/rules",
        json!({ "name": "x", "trigger": "updated", "actions": [mail_action("address")] }),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    let mut to_ops = mail_action("address");
    to_ops["address"] = json!("ops@example.com");
    let r = rule(
        &app,
        json!({ "name": "Every change", "trigger": "updated", "conditions": {}, "actions": [to_ops] }),
    )
    .await;
    assert_eq!(r["actions"][0]["period_hours"], 24);
    let id = new_ticket(&app, "Valve").await;
    for priority in ["high", "urgent", "low"] {
        set_priority(&app, &id, priority).await;
    }
    assert_eq!(outbox(&db).await.len(), 1, "three updates, one mail");
    // Once the period has passed the rule may mail again; another ticket is independent.
    sqlx::query("UPDATE helpdesk.automation_mail_log SET sent_at = now() - interval '25 hours'")
        .execute(&db)
        .await
        .unwrap();
    set_priority(&app, &id, "normal").await;
    assert_eq!(outbox(&db).await.len(), 2);
    let other = new_ticket(&app, "Second").await;
    set_priority(&app, &other, "high").await;
    assert_eq!(outbox(&db).await.len(), 3);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn recipients_are_the_customer_the_assignee_the_team_or_a_fixed_address(db: PgPool) {
    let app = setup(db.clone()).await;
    let (_, team) = post(
        &app,
        ADMIN,
        "/helpdesk/teams",
        json!({ "name": "Sound", "members": [{ "user_id": SUPPORT_ID, "is_lead": true }] }),
    )
    .await;
    let team_id = team["id"].as_str().unwrap().to_string();
    let mut to_team = mail_action("team");
    to_team["team_id"] = json!(team_id);
    let mut fixed = mail_action("address");
    fixed["address"] = json!("  Ops@Example.com ");
    rule(
        &app,
        json!({ "name": "All", "trigger": "created",
            "actions": [{ "kind": "set_owner", "user_id": SUPPORT_ID }, mail_action("assignee"),
                        to_team, fixed, mail_action("customer")] }),
    )
    .await;
    new_ticket(&app, "Hum").await;
    let mut to: Vec<String> = outbox(&db).await.into_iter().map(|m| m.0).collect();
    to.sort();
    assert_eq!(
        to,
        vec!["anna@alpha.example", "ops@example.com", SUPPORT, SUPPORT]
    );
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn an_internal_ticket_is_never_mailed_to_the_customer(db: PgPool) {
    let app = setup(db.clone()).await;
    rule(
        &app,
        json!({ "name": "Customer", "trigger": "created", "actions": [mail_action("customer")] }),
    )
    .await;
    let (status, t) = post(
        &app,
        SALES,
        "/tickets",
        json!({ "subject": "Internal", "customer_id": ALPHA, "contact_email": "anna@alpha.example", "internal": true, "body": "x" }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{t}");
    assert!(outbox(&db).await.is_empty());
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn send_email_actions_are_validated_and_for_administrators(db: PgPool) {
    let app = setup(db.clone()).await;
    let bad = |action: Value| json!({ "name": "r", "trigger": "created", "actions": [action] });
    for action in [
        json!({ "kind": "send_email", "subject": "s", "body": "b" }),
        json!({ "kind": "send_email", "recipient": "nobody", "subject": "s", "body": "b" }),
        json!({ "kind": "send_email", "recipient": "customer", "subject": "", "body": "b" }),
        json!({ "kind": "send_email", "recipient": "customer", "subject": "s", "body": "Hi {customr}" }),
        json!({ "kind": "send_email", "recipient": "address", "address": "not-an-address", "subject": "s", "body": "b" }),
        json!({ "kind": "send_email", "recipient": "customer", "subject": "s", "body": "b", "period_hours": 0 }),
        json!({ "kind": "send_email", "recipient": "team", "subject": "s", "body": "b" }),
    ] {
        let (status, body) = post(
            &app,
            ADMIN,
            "/helpdesk/automation/rules",
            bad(action.clone()),
        )
        .await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{action} {body}");
    }
    let (status, _) = post(
        &app,
        SUPPORT,
        "/helpdesk/automation/rules",
        bad(mail_action("customer")),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    // A dry run lists the mail as a change and queues nothing.
    rule(
        &app,
        json!({ "name": "Customer", "trigger": "created", "actions": [mail_action("customer")] }),
    )
    .await;
    let id = new_ticket(&app, "Dry").await;
    sqlx::query("DELETE FROM core.mail_outbox")
        .execute(&db)
        .await
        .unwrap();
    sqlx::query("DELETE FROM helpdesk.automation_mail_log")
        .execute(&db)
        .await
        .unwrap();
    let (status, d) = post(
        &app,
        ADMIN,
        "/helpdesk/automation/dry-run",
        json!({ "ticket_id": id, "trigger": "created" }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{d}");
    assert_eq!(d["rules"][0]["changes"][0]["kind"], "send_email");
    assert!(outbox(&db).await.is_empty());
}
