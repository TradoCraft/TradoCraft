//! `POST /tickets/{id}/status`: a status change and nothing else, as the kanban board makes it.

mod common;

use axum::http::{Method, StatusCode};
use common::{call, setup};
use serde_json::{json, Value};
use sqlx::PgPool;
use uuid::Uuid;

const ALPHA: &str = "00000000-0000-7000-8000-000000000401";
const SUPPORT: &str = "support@example.com";
const VIEWER: &str = "viewer@example.com";
const COMPANY: &str = "00000000-0000-7000-8000-000000000001";

async fn send(
    app: &axum::Router,
    user: &str,
    method: Method,
    uri: &str,
    body: Option<Value>,
) -> (StatusCode, Value) {
    call(app, user, method, &format!("/api/v1{uri}"), body).await
}

async fn new_ticket(app: &axum::Router, subject: &str) -> Value {
    let (s, t) = send(
        app,
        SUPPORT,
        Method::POST,
        "/tickets",
        Some(json!({ "subject": subject, "customer_id": ALPHA,
                     "contact_email": "anna@alpha.example", "body": "First note" })),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED, "{t}");
    t["ticket"].clone()
}

async fn set(app: &axum::Router, id: &str, body: Value) -> (StatusCode, Value) {
    send(
        app,
        SUPPORT,
        Method::POST,
        &format!("/tickets/{id}/status"),
        Some(body),
    )
    .await
}

fn kinds(events: &Value) -> Vec<(String, Option<String>, Option<String>)> {
    events
        .as_array()
        .unwrap()
        .iter()
        .filter(|e| e["kind"] == "status")
        .map(|e| {
            (
                e["kind"].as_str().unwrap().to_string(),
                e["from_value"].as_str().map(str::to_string),
                e["to_value"].as_str().map(str::to_string),
            )
        })
        .collect()
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_status_change_changes_only_the_status(db: PgPool) {
    let app = setup(db.clone()).await;
    let t = new_ticket(&app, "Water in the unit").await;
    let id = t["id"].as_str().unwrap();
    let before_status = t["status"].as_str().unwrap().to_string();
    let (s, d) = set(&app, id, json!({"status": "pending_customer"})).await;
    assert_eq!(s, StatusCode::OK, "{d}");
    let after = &d["ticket"];
    assert_eq!(after["status"], "pending_customer");
    // everything else stays as it was
    for field in [
        "subject",
        "priority",
        "category",
        "language",
        "customer_id",
        "contact_email",
    ] {
        assert_eq!(after[field], t[field], "{field}");
    }
    assert!(after["version"].as_i64() > t["version"].as_i64());
    // the timeline says who moved it from where
    let (_, events) = send(
        &app,
        SUPPORT,
        Method::GET,
        &format!("/tickets/{id}/events"),
        None,
    )
    .await;
    assert_eq!(
        kinds(&events).last().unwrap(),
        &(
            "status".to_string(),
            Some(before_status),
            Some("pending_customer".to_string())
        )
    );
    // and the audit trail has it
    let audited: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM audit.events WHERE entity = 'ticket' AND entity_id = $1::uuid
           AND action = 'status_changed' AND data->>'to' = 'pending_customer'",
    )
    .bind(id)
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(audited, 1);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn closing_and_reopening_keep_the_closing_time_right(db: PgPool) {
    let app = setup(db.clone()).await;
    let t = new_ticket(&app, "Done").await;
    let id = t["id"].as_str().unwrap();
    let (s, d) = set(&app, id, json!({"status": "closed"})).await;
    assert_eq!(s, StatusCode::OK, "{d}");
    assert!(d["ticket"]["closed_at"].is_string());
    let (s, d) = set(&app, id, json!({"status": "open"})).await;
    assert_eq!(s, StatusCode::OK, "{d}");
    assert_eq!(d["ticket"]["status"], "open");
    assert!(
        d["ticket"]["closed_at"].is_null(),
        "reopening clears the closing time"
    );
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_same_status_changes_nothing(db: PgPool) {
    let app = setup(db).await;
    let t = new_ticket(&app, "Same").await;
    let id = t["id"].as_str().unwrap();
    let current = t["status"].as_str().unwrap();
    let (s, d) = set(&app, id, json!({"status": current})).await;
    assert_eq!(s, StatusCode::OK, "{d}");
    assert_eq!(
        d["ticket"]["version"], t["version"],
        "no write, no new version"
    );
    let (_, events) = send(
        &app,
        SUPPORT,
        Method::GET,
        &format!("/tickets/{id}/events"),
        None,
    )
    .await;
    assert!(kinds(&events).is_empty(), "no status event: {events}");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn an_unknown_status_a_stale_version_and_missing_rights_are_refused(db: PgPool) {
    let app = setup(db).await;
    let t = new_ticket(&app, "Refusals").await;
    let id = t["id"].as_str().unwrap();
    let (s, _) = set(&app, id, json!({"status": "done"})).await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);
    // a read-only user cannot change it
    let (s, _) = send(
        &app,
        VIEWER,
        Method::POST,
        &format!("/tickets/{id}/status"),
        Some(json!({"status": "open"})),
    )
    .await;
    assert_eq!(s, StatusCode::FORBIDDEN);
    // an unknown ticket
    let (s, _) = set(&app, &Uuid::now_v7().to_string(), json!({"status": "open"})).await;
    assert_eq!(s, StatusCode::NOT_FOUND);
    // the version the caller last saw: a ticket that moved on is refused, the current one passes
    let (s, first) = set(
        &app,
        id,
        json!({"status": "pending_internal", "expected_version": t["version"]}),
    )
    .await;
    assert_eq!(s, StatusCode::OK, "{first}");
    let (s, r) = set(
        &app,
        id,
        json!({"status": "open", "expected_version": t["version"]}),
    )
    .await;
    assert_eq!(s, StatusCode::CONFLICT, "{r}");
    assert_eq!(r["code"], "record_changed");
    let (s, _) = set(
        &app,
        id,
        json!({"status": "open", "expected_version": first["ticket"]["version"]}),
    )
    .await;
    assert_eq!(s, StatusCode::OK);
    // and nothing was applied by the refused one
    let (_, now) = send(&app, SUPPORT, Method::GET, &format!("/tickets/{id}"), None).await;
    assert_eq!(now["ticket"]["status"], "open");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn closing_is_refused_while_the_team_needs_its_checklist_done(db: PgPool) {
    let app = setup(db.clone()).await;
    let t = new_ticket(&app, "Needs a checklist").await;
    let id = t["id"].as_str().unwrap();
    let team = Uuid::now_v7();
    sqlx::query("INSERT INTO helpdesk.teams (id, company_id, name, require_checklist_done) VALUES ($1, $2::uuid, 'Service', true)")
        .bind(team).bind(COMPANY).execute(&db).await.unwrap();
    sqlx::query("UPDATE helpdesk.tickets SET team_id = $2 WHERE id = $1::uuid")
        .bind(id)
        .bind(team)
        .execute(&db)
        .await
        .unwrap();
    sqlx::query("INSERT INTO helpdesk.ticket_checklist_items (id, ticket_id, position, description) VALUES ($1, $2::uuid, 1, 'Check the filter')")
        .bind(Uuid::now_v7()).bind(id).execute(&db).await.unwrap();
    let before = t["status"].clone();
    let (s, r) = set(&app, id, json!({"status": "closed"})).await;
    assert_eq!(s, StatusCode::CONFLICT, "{r}");
    assert_eq!(r["code"], "checklist_incomplete");
    // the refused change left the ticket as it was, timeline included
    let (_, now) = send(&app, SUPPORT, Method::GET, &format!("/tickets/{id}"), None).await;
    assert_eq!(now["ticket"]["status"], before);
    let (_, events) = send(
        &app,
        SUPPORT,
        Method::GET,
        &format!("/tickets/{id}/events"),
        None,
    )
    .await;
    assert!(kinds(&events).is_empty());
    // done items let it close
    sqlx::query(
        "UPDATE helpdesk.ticket_checklist_items SET done = true WHERE ticket_id = $1::uuid",
    )
    .bind(id)
    .execute(&db)
    .await
    .unwrap();
    let (s, d) = set(&app, id, json!({"status": "closed"})).await;
    assert_eq!(s, StatusCode::OK, "{d}");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn closing_queues_the_satisfaction_survey_once(db: PgPool) {
    let app = setup(db.clone()).await;
    sqlx::query("INSERT INTO helpdesk.settings (company_id, csat_enabled) VALUES ($1::uuid, true) ON CONFLICT (company_id) DO UPDATE SET csat_enabled = true")
        .bind(COMPANY).execute(&db).await.unwrap();
    let t = new_ticket(&app, "Survey").await;
    let id = t["id"].as_str().unwrap();
    // an internal ticket is never surveyed; this one has an outside contact
    let (s, d) = set(&app, id, json!({"status": "closed"})).await;
    assert_eq!(s, StatusCode::OK, "{d}");
    let (s, d) = set(&app, id, json!({"status": "open"})).await;
    assert_eq!(s, StatusCode::OK, "{d}");
    assert_eq!(d["ticket"]["status"], "open");
    let (s, d) = set(&app, id, json!({"status": "closed"})).await;
    assert_eq!(s, StatusCode::OK, "{d}");
    assert_eq!(d["ticket"]["status"], "closed");
    let surveys: i64 =
        sqlx::query_scalar("SELECT count(*) FROM helpdesk.csat_surveys WHERE ticket_id = $1::uuid")
            .bind(id)
            .fetch_one(&db)
            .await
            .unwrap();
    assert_eq!(surveys, 1, "closing twice still asks the customer once");
}
