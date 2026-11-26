//! Helpdesk maturity: SLA, escalation, teams, attachments, tags, merge, time entries and CSAT.

mod common;

use axum::http::{Method, StatusCode};
use chrono::{DateTime, Duration, Utc};
use common::{call, call_portal, call_raw, jpeg, portal_login, raw, setup, Who};
use serde_json::{json, Value};
use sqlx::PgPool;
use tradocraft_helpdesk::mailer::{process_outbox, Mailer};

const ALPHA: &str = "00000000-0000-7000-8000-000000000401";
const GAMMA: &str = "00000000-0000-7000-8000-000000000403";
const JAN_ID: &str = "00000000-0000-7000-8000-000000000601";
const JAN: &str = "jan.peeters@alpha.example";
const ADMIN: &str = "admin@example.com";
const SALES: &str = "sales@example.com";
const SUPPORT: &str = "support@example.com";
const SALES_ID: &str = "00000000-0000-7000-8000-000000000102";
const SUPPORT_ID: &str = "00000000-0000-7000-8000-000000000105";
const PRODUCTION_ID: &str = "00000000-0000-7000-8000-000000000106";

const PDF: &[u8] = b"%PDF-1.4\n1 0 obj<<>>endobj\ntrailer<<>>\n%%EOF\n";

fn when(v: &Value) -> DateTime<Utc> {
    DateTime::parse_from_rfc3339(v.as_str().unwrap_or_else(|| panic!("not a date: {v}")))
        .unwrap()
        .with_timezone(&Utc)
}

async fn new_ticket_for(app: &axum::Router, customer: &str, subject: &str) -> String {
    let (status, t) = call(
        app,
        SUPPORT,
        Method::POST,
        "/api/v1/tickets",
        Some(json!({
            "subject": subject, "customer_id": customer,
            "contact_email": "anna@alpha.example", "body": "Internal first note"
        })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{t}");
    t["ticket"]["id"].as_str().unwrap().to_string()
}

async fn new_ticket(app: &axum::Router, subject: &str) -> String {
    new_ticket_for(app, ALPHA, subject).await
}

async fn get(app: &axum::Router, id: &str) -> Value {
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

/// Changes priority and/or status through the full update call.
async fn update(
    app: &axum::Router,
    id: &str,
    priority: Option<&str>,
    status: Option<&str>,
) -> Value {
    let d = get(app, id).await;
    let t = &d["ticket"];
    let (code, r) = call(
        app,
        SUPPORT,
        Method::PUT,
        &format!("/api/v1/tickets/{id}"),
        Some(json!({
            "subject": t["subject"], "status": status.unwrap_or(t["status"].as_str().unwrap()),
            "priority": priority.unwrap_or(t["priority"].as_str().unwrap()),
            "category": t["category"], "language": t["language"],
            "owner_user_id": t["owner_user_id"], "customer_id": t["customer_id"],
            "contact_id": t["contact_id"], "contact_name": t["contact_name"],
            "contact_email": t["contact_email"],
        })),
    )
    .await;
    assert_eq!(code, StatusCode::OK, "{r}");
    r
}

async fn list(app: &axum::Router, user: &str, query: &str) -> Vec<String> {
    let (status, p) = call(
        app,
        user,
        Method::GET,
        &format!("/api/v1/tickets?{query}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{p}");
    p["items"]
        .as_array()
        .unwrap()
        .iter()
        .map(|t| t["id"].as_str().unwrap().to_string())
        .collect()
}

async fn upload(
    app: &axum::Router,
    who: Who<'_>,
    uri: &str,
    bytes: Vec<u8>,
) -> (StatusCode, Value) {
    let (status, _, body) = raw(
        app,
        who,
        Method::POST,
        uri,
        Some(("application/octet-stream", bytes)),
    )
    .await;
    (status, serde_json::from_slice(&body).unwrap_or(Value::Null))
}

/// Makes a ticket older by shifting its creation and due times, as if time had passed.
async fn age(db: &PgPool, id: &str, interval: &str) {
    sqlx::query(sqlx::AssertSqlSafe(format!(
        "UPDATE helpdesk.tickets SET created_at = created_at - interval '{interval}',
                first_response_due_at = first_response_due_at - interval '{interval}',
                resolution_due_at = resolution_due_at - interval '{interval}',
                first_response_risk_at = first_response_risk_at - interval '{interval}',
                resolution_risk_at = resolution_risk_at - interval '{interval}'
         WHERE id = $1::uuid"
    )))
    .bind(id)
    .execute(db)
    .await
    .unwrap();
}

async fn assign(
    app: &axum::Router,
    id: &str,
    team: Option<&str>,
    owner: Option<&str>,
) -> (StatusCode, Value) {
    call(
        app,
        SUPPORT,
        Method::PUT,
        &format!("/api/v1/tickets/{id}/assignment"),
        Some(json!({ "team_id": team, "owner_user_id": owner })),
    )
    .await
}

async fn portal_download(
    app: &axum::Router,
    token: &str,
    ticket: &str,
    file: &str,
) -> (StatusCode, axum::http::HeaderMap, Vec<u8>) {
    raw(
        app,
        Who::Portal(token),
        Method::GET,
        &format!("/api/v1/portal/tickets/{ticket}/attachments/{file}"),
        None,
    )
    .await
}

async fn tag(app: &axum::Router, id: &str, t: &str) -> (StatusCode, Value) {
    call(
        app,
        SUPPORT,
        Method::POST,
        &format!("/api/v1/tickets/{id}/tags"),
        Some(json!({ "tag": t })),
    )
    .await
}

async fn log_time(
    app: &axum::Router,
    id: &str,
    user: &str,
    m: i64,
    billable: bool,
) -> (StatusCode, Value) {
    call(
        app,
        user,
        Method::POST,
        &format!("/api/v1/tickets/{id}/time-entries"),
        Some(json!({ "minutes": m, "note": "phone", "billable": billable })),
    )
    .await
}

async fn merge(app: &axum::Router, from: &str, into: &str) -> (StatusCode, Value) {
    call(
        app,
        SUPPORT,
        Method::POST,
        &format!("/api/v1/tickets/{from}/merge"),
        Some(json!({ "target_id": into })),
    )
    .await
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn due_times_follow_priority_and_stop_while_waiting_for_the_customer(db: PgPool) {
    let app = setup(db.clone()).await;
    let id = new_ticket(&app, "Pump noise").await;
    let t = get(&app, &id).await;
    let created = when(&t["ticket"]["created_at"]);
    let sla = &t["ticket"]["sla"];
    // Normal priority: 8 h first response, 72 h resolution.
    assert_eq!(
        when(&sla["first_response"]["due_at"]),
        created + Duration::minutes(480)
    );
    assert_eq!(
        when(&sla["resolution"]["due_at"]),
        created + Duration::minutes(4320)
    );
    assert_eq!(sla["state"], "on_time");
    assert_eq!(sla["paused"], false);
    assert!(sla["first_response"]["minutes_remaining"].as_i64().unwrap() > 470);

    // Priority change recomputes from the creation time.
    let t = update(&app, &id, Some("urgent"), None).await;
    let sla = &t["ticket"]["sla"];
    assert_eq!(
        when(&sla["first_response"]["due_at"]),
        created + Duration::minutes(60)
    );
    assert_eq!(
        when(&sla["resolution"]["due_at"]),
        created + Duration::minutes(480)
    );
    let before = when(&sla["resolution"]["due_at"]);

    // Waiting for the customer stops the clock ...
    let t = update(&app, &id, None, Some("pending_customer")).await;
    assert_eq!(t["ticket"]["sla"]["paused"], true);
    sqlx::query("UPDATE helpdesk.tickets SET sla_paused_at = sla_paused_at - interval '2 hours' WHERE id = $1::uuid")
        .bind(&id)
        .execute(&db)
        .await
        .unwrap();
    // ... and the waiting time is added to the due times when the ticket moves on.
    let t = update(&app, &id, None, Some("open")).await;
    let sla = &t["ticket"]["sla"];
    assert_eq!(sla["paused"], false);
    let shift = (when(&sla["resolution"]["due_at"]) - before).num_seconds();
    assert!((7200..7210).contains(&shift), "shifted by {shift}s");
    let fr_shift =
        (when(&sla["first_response"]["due_at"]) - (created + Duration::minutes(60))).num_seconds();
    assert!((7200..7210).contains(&fr_shift));

    // Internal tickets (production questions) have no service level.
    let (status, q) = call(
        &app,
        SALES,
        Method::POST,
        "/api/v1/tickets",
        Some(json!({ "subject": "Colleague question", "internal": true, "body": "x" })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{q}");
    assert_eq!(q["ticket"]["sla"]["state"], "none");
    assert!(q["ticket"]["sla"]["first_response"]["due_at"].is_null());
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_first_outgoing_reply_or_call_is_the_first_response(db: PgPool) {
    let app = setup(db.clone()).await;
    let a = new_ticket(&app, "Reply").await;
    let b = new_ticket(&app, "Call").await;
    let c = new_ticket(&app, "Note and incoming call").await;

    call(
        &app,
        SUPPORT,
        Method::POST,
        &format!("/api/v1/tickets/{c}/notes"),
        Some(json!({ "body": "note" })),
    )
    .await;
    call(
        &app,
        SUPPORT,
        Method::POST,
        "/api/v1/helpdesk/calls",
        Some(json!({ "ticket_id": c, "direction": "in", "summary": "they called" })),
    )
    .await;
    assert!(get(&app, &c).await["ticket"]["first_response_at"].is_null());

    let (s, _) = call(
        &app,
        SUPPORT,
        Method::POST,
        &format!("/api/v1/tickets/{a}/replies"),
        Some(json!({ "body": "Hello" })),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED);
    let (s, _) = call(
        &app,
        SUPPORT,
        Method::POST,
        "/api/v1/helpdesk/calls",
        Some(json!({ "ticket_id": b, "direction": "out", "summary": "we called" })),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED);
    for id in [&a, &b] {
        let t = get(&app, id).await;
        assert!(!t["ticket"]["first_response_at"].is_null(), "{id}");
        assert!(t["ticket"]["sla"]["first_response"]["minutes_remaining"].is_null());
        assert!(!t["ticket"]["sla"]["first_response"]["met_at"].is_null());
    }
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn breached_and_at_risk_tickets_are_flagged_and_filterable(db: PgPool) {
    let app = setup(db.clone()).await;
    let ok = new_ticket(&app, "Fine").await;
    let late = new_ticket(&app, "Late").await;
    let risky = new_ticket(&app, "Risky").await;
    let slow_close = new_ticket(&app, "Resolved too late").await;
    // late: first response due an hour ago. risky: 10 minutes left of 480 (< 25 %).
    age(&db, &late, "9 hours").await;
    age(&db, &risky, "7 hours 50 minutes").await;

    let t = get(&app, &late).await;
    assert_eq!(t["ticket"]["sla"]["state"], "breached");
    assert_eq!(t["ticket"]["sla"]["first_response_breached"], true);
    assert_eq!(t["ticket"]["sla"]["resolution_breached"], false);
    assert!(
        t["ticket"]["sla"]["first_response"]["minutes_remaining"]
            .as_i64()
            .unwrap()
            <= -59
    );
    let t = get(&app, &risky).await;
    assert_eq!(t["ticket"]["sla"]["state"], "at_risk");
    assert_eq!(get(&app, &ok).await["ticket"]["sla"]["state"], "on_time");

    assert_eq!(
        list(&app, SUPPORT, "sla=breached").await,
        vec![late.clone()]
    );
    assert_eq!(
        list(&app, SUPPORT, "sla=at_risk").await,
        vec![risky.clone()]
    );
    let (status, _) = call(
        &app,
        SUPPORT,
        Method::GET,
        "/api/v1/tickets?sla=bogus",
        None,
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    // A late answer does not undo the breach; closing within time resolves the ticket.
    call(
        &app,
        SUPPORT,
        Method::POST,
        &format!("/api/v1/tickets/{late}/replies"),
        Some(json!({ "body": "Sorry" })),
    )
    .await;
    assert_eq!(
        get(&app, &late).await["ticket"]["sla"]["first_response_breached"],
        true
    );
    assert_eq!(
        list(&app, SUPPORT, "sla=breached").await,
        vec![late.clone()]
    );

    // Resolution due in the past, but closed before that: not breached. Closed after: breached.
    age(&db, &slow_close, "73 hours").await;
    let t = update(&app, &slow_close, None, Some("closed")).await;
    assert_eq!(t["ticket"]["sla"]["resolution_breached"], true);
    assert_eq!(t["ticket"]["sla"]["state"], "breached");
    let mut found = list(&app, SUPPORT, "sla=breached").await;
    found.sort();
    let mut expect = vec![late.clone(), slow_close.clone()];
    expect.sort();
    assert_eq!(found, expect);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn sla_policies_are_admin_only_validated_and_applied_to_open_tickets(db: PgPool) {
    let app = setup(db.clone()).await;
    let (s, _) = call(
        &app,
        SUPPORT,
        Method::GET,
        "/api/v1/helpdesk/sla-policies",
        None,
    )
    .await;
    assert_eq!(s, StatusCode::FORBIDDEN);
    let (s, p) = call(
        &app,
        ADMIN,
        Method::GET,
        "/api/v1/helpdesk/sla-policies",
        None,
    )
    .await;
    assert_eq!(s, StatusCode::OK, "{p}");
    assert_eq!(p.as_array().unwrap().len(), 4);
    assert_eq!(p[0]["priority"], "urgent");
    assert_eq!(p[0]["first_response_minutes"], 60);
    assert_eq!(p[3]["priority"], "low");
    assert_eq!(p[3]["resolution_minutes"], 7200);

    let id = new_ticket(&app, "Policy").await;
    let created = when(&get(&app, &id).await["ticket"]["created_at"]);
    let put = |body: Value| {
        call(
            &app,
            ADMIN,
            Method::PUT,
            "/api/v1/helpdesk/sla-policies",
            Some(body),
        )
    };
    for bad in [
        json!({ "policies": [{ "priority": "normal", "first_response_minutes": 0, "resolution_minutes": 10 }] }),
        json!({ "policies": [{ "priority": "normal", "first_response_minutes": 60, "resolution_minutes": 30 }] }),
        json!({ "policies": [{ "priority": "weird", "first_response_minutes": 60, "resolution_minutes": 90 }] }),
    ] {
        assert_eq!(put(bad).await.0, StatusCode::UNPROCESSABLE_ENTITY);
    }
    let (s, _) = call(
        &app,
        SUPPORT,
        Method::PUT,
        "/api/v1/helpdesk/sla-policies",
        Some(json!({ "policies": [] })),
    )
    .await;
    assert_eq!(s, StatusCode::FORBIDDEN);
    let (s, p) = put(json!({ "policies": [{ "priority": "normal", "first_response_minutes": 30, "resolution_minutes": 120 }] })).await;
    assert_eq!(s, StatusCode::OK, "{p}");
    assert_eq!(p[2]["first_response_minutes"], 30);
    let t = get(&app, &id).await;
    assert_eq!(
        when(&t["ticket"]["sla"]["first_response"]["due_at"]),
        created + Duration::minutes(30)
    );
    assert_eq!(
        when(&t["ticket"]["sla"]["resolution"]["due_at"]),
        created + Duration::minutes(120)
    );
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn breaches_are_escalated_once_to_the_people_responsible(db: PgPool) {
    let app = setup(db.clone()).await;
    // A team with a lead and a member.
    let (s, team) = call(
        &app,
        ADMIN,
        Method::POST,
        "/api/v1/helpdesk/teams",
        Some(json!({ "name": "Escalations", "members": [
            { "user_id": SALES_ID, "is_lead": true }, { "user_id": PRODUCTION_ID } ] })),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED, "{team}");
    let team_id = team["id"].as_str().unwrap();

    let owned = new_ticket(&app, "Owned").await; // owner: support
    let queued = new_ticket(&app, "In the queue").await;
    call(
        &app,
        SUPPORT,
        Method::PUT,
        &format!("/api/v1/tickets/{owned}/assignment"),
        Some(json!({ "team_id": team_id, "owner_user_id": SUPPORT_ID })),
    )
    .await;
    call(
        &app,
        SUPPORT,
        Method::PUT,
        &format!("/api/v1/tickets/{queued}/assignment"),
        Some(json!({ "team_id": team_id, "owner_user_id": null })),
    )
    .await;
    for id in [&owned, &queued] {
        age(&db, id, "9 hours").await;
    }
    // A closed ticket is never escalated.
    let closed = new_ticket(&app, "Closed").await;
    age(&db, &closed, "9 hours").await;
    update(&app, &closed, None, Some("closed")).await;
    sqlx::query("DELETE FROM core.mail_outbox")
        .execute(&db)
        .await
        .unwrap();

    assert_eq!(tradocraft_helpdesk::sla::escalate(&db).await.unwrap(), 2);
    let number = |t: Value| t["ticket"]["number"].as_str().unwrap().to_string();
    let owned_number = number(get(&app, &owned).await);
    let queued_number = number(get(&app, &queued).await);
    // The owner and the lead of the team.
    let for_owned: Vec<String> = sqlx::query_scalar(
        "SELECT to_address FROM core.mail_outbox WHERE subject LIKE $1 ORDER BY 1",
    )
    .bind(format!("%{owned_number}%"))
    .fetch_all(&db)
    .await
    .unwrap();
    assert_eq!(for_owned, vec!["sales@example.com", "support@example.com"]);
    // Nobody owns it: all members of the team.
    let for_queued: Vec<String> = sqlx::query_scalar(
        "SELECT to_address FROM core.mail_outbox WHERE subject LIKE $1 ORDER BY 1",
    )
    .bind(format!("%{queued_number}%"))
    .fetch_all(&db)
    .await
    .unwrap();
    assert_eq!(
        for_queued,
        vec!["production@example.com", "sales@example.com"]
    );
    let events: i64 =
        sqlx::query_scalar("SELECT count(*) FROM audit.events WHERE action = 'sla_breached'")
            .fetch_one(&db)
            .await
            .unwrap();
    assert_eq!(events, 2);

    // Idempotent: nothing is sent again, even after the first answer and a later resolution breach.
    assert_eq!(tradocraft_helpdesk::sla::escalate(&db).await.unwrap(), 0);
    sqlx::query("UPDATE helpdesk.tickets SET resolution_due_at = now() - interval '1 minute' WHERE id = $1::uuid")
        .bind(&owned).execute(&db).await.unwrap();
    assert_eq!(
        tradocraft_helpdesk::sla::escalate(&db).await.unwrap(),
        1,
        "a resolution breach is a new kind"
    );
    assert_eq!(tradocraft_helpdesk::sla::escalate(&db).await.unwrap(), 0);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn teams_assignment_and_list_filters(db: PgPool) {
    let app = setup(db.clone()).await;
    // Only admins manage teams; everyone with helpdesk access can read them.
    let team_body =
        json!({ "name": "Support NL", "members": [{ "user_id": SUPPORT_ID, "is_lead": true }] });
    assert_eq!(
        call(
            &app,
            SUPPORT,
            Method::POST,
            "/api/v1/helpdesk/teams",
            Some(team_body.clone())
        )
        .await
        .0,
        StatusCode::FORBIDDEN
    );
    let (s, team) = call(
        &app,
        ADMIN,
        Method::POST,
        "/api/v1/helpdesk/teams",
        Some(team_body.clone()),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED, "{team}");
    assert_eq!(team["members"][0]["display_name"], "Support Agent");
    assert_eq!(team["members"][0]["is_lead"], true);
    assert_eq!(
        call(
            &app,
            ADMIN,
            Method::POST,
            "/api/v1/helpdesk/teams",
            Some(team_body)
        )
        .await
        .0,
        StatusCode::CONFLICT
    );
    let team_id = team["id"].as_str().unwrap().to_string();
    let (s, teams) = call(&app, SALES, Method::GET, "/api/v1/helpdesk/teams", None).await;
    assert_eq!(s, StatusCode::OK);
    assert_eq!(teams.as_array().unwrap().len(), 1);
    let (_, other) = call(
        &app,
        ADMIN,
        Method::POST,
        "/api/v1/helpdesk/teams",
        Some(json!({ "name": "Sales desk" })),
    )
    .await;
    let other_id = other["id"].as_str().unwrap().to_string();

    let mine = new_ticket(&app, "Mine").await; // owner: support
    let queue = new_ticket(&app, "In my team's queue").await;
    let elsewhere = new_ticket(&app, "Other team").await;
    let nobody = new_ticket(&app, "Nobody").await;
    assert_eq!(
        assign(&app, &queue, Some(&team_id), None).await.0,
        StatusCode::OK
    );
    let (s, d) = assign(&app, &elsewhere, Some(&other_id), Some(SALES_ID)).await;
    assert_eq!(s, StatusCode::OK, "{d}");
    assert_eq!(d["ticket"]["team_name"], "Sales desk");
    assert_eq!(d["ticket"]["owner_name"], "Sales User");
    assert_eq!(assign(&app, &nobody, None, None).await.0, StatusCode::OK);
    // Unknown team or user: rejected.
    assert_eq!(
        assign(
            &app,
            &nobody,
            Some("00000000-0000-7000-8000-0000000fffff"),
            None
        )
        .await
        .0,
        StatusCode::UNPROCESSABLE_ENTITY
    );
    assert_eq!(
        assign(
            &app,
            &nobody,
            None,
            Some("00000000-0000-7000-8000-0000000fffff")
        )
        .await
        .0,
        StatusCode::UNPROCESSABLE_ENTITY
    );

    assert_eq!(
        list(&app, SUPPORT, &format!("team_id={team_id}")).await,
        vec![queue.clone()]
    );
    let mut m = list(&app, SUPPORT, "mine=true").await;
    m.sort();
    let mut expect = vec![mine.clone(), queue.clone()];
    expect.sort();
    assert_eq!(m, expect, "owned by me, or unowned in a team I belong to");
    assert_eq!(
        list(&app, SUPPORT, "unassigned=true").await,
        vec![nobody.clone()]
    );
    assert_eq!(
        list(&app, SALES, "mine=true").await,
        vec![elsewhere.clone()]
    );

    // A retired team cannot be the default; the default team receives new e-mail tickets.
    assert_eq!(call(&app, ADMIN, Method::PUT, "/api/v1/helpdesk/settings",
        Some(json!({ "default_team_id": "00000000-0000-7000-8000-0000000fffff", "csat_enabled": false }))).await.0,
        StatusCode::UNPROCESSABLE_ENTITY);
    let (s, st) = call(
        &app,
        ADMIN,
        Method::PUT,
        "/api/v1/helpdesk/settings",
        Some(json!({ "default_team_id": team_id, "csat_enabled": false })),
    )
    .await;
    assert_eq!(s, StatusCode::OK, "{st}");
    assert_eq!(
        call(
            &app,
            SUPPORT,
            Method::PUT,
            "/api/v1/helpdesk/settings",
            Some(json!({ "default_team_id": null, "csat_enabled": true }))
        )
        .await
        .0,
        StatusCode::FORBIDDEN
    );
    let mail = b"From: Anna <anna@alpha.example>\r\nTo: sales@example.com\r\nSubject: Hello\r\nMessage-ID: <t1@alpha.example>\r\nContent-Type: text/plain\r\n\r\nPlease help\r\n".to_vec();
    let (s, r) = call_raw(
        &app,
        SUPPORT,
        "/api/v1/helpdesk/inbound",
        "message/rfc822",
        mail,
    )
    .await;
    assert_eq!(s, StatusCode::OK, "{r}");
    let t = get(&app, r["ticket_id"].as_str().unwrap()).await;
    assert_eq!(t["ticket"]["team_name"], "Support NL");
    assert!(
        t["ticket"]["owner_user_id"].is_null(),
        "incoming tickets stay unowned"
    );
    assert_eq!(
        t["ticket"]["sla"]["state"], "on_time",
        "incoming mail gets a service level too"
    );
    // Retiring the team clears the default.
    call(
        &app,
        ADMIN,
        Method::PUT,
        &format!("/api/v1/helpdesk/teams/{team_id}"),
        Some(json!({ "name": "Support NL", "active": false })),
    )
    .await;
    let (_, st) = call(
        &app,
        SUPPORT,
        Method::GET,
        "/api/v1/helpdesk/settings",
        None,
    )
    .await;
    assert!(st["default_team_id"].is_null());
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn attachments_are_checked_linked_downloaded_and_hidden_on_internal_notes(db: PgPool) {
    let (app, blobs) = common::setup_with_blobs(db.clone()).await;
    let id = new_ticket(&app, "With files").await;
    let up = |name: &str| format!("/api/v1/tickets/{id}/attachments?filename={name}");

    // Only JPEG, PNG, WebP and PDF by signature; the name does not matter.
    for bad in [
        &b"MZ\x90\x00 pretend.pdf"[..],
        b"plain text",
        b"<svg xmlns='x'/>",
        b"",
    ] {
        let (s, e) = upload(&app, Who::Staff(SUPPORT), &up("plan.pdf"), bad.to_vec()).await;
        assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY, "{e}");
    }
    let mut big = b"%PDF-1.4\n".to_vec();
    big.resize(12 * 1024 * 1024 + 1, b'x');
    assert_eq!(
        upload(&app, Who::Staff(SUPPORT), &up("big.pdf"), big)
            .await
            .0,
        StatusCode::UNPROCESSABLE_ENTITY
    );
    // Viewers cannot upload.
    assert_eq!(
        upload(
            &app,
            Who::Staff("viewer@example.com"),
            &up("a.pdf"),
            PDF.to_vec()
        )
        .await
        .0,
        StatusCode::FORBIDDEN
    );

    let client = "00000000-0000-7000-8000-00000000ab01";
    let (s, pdf) = upload(
        &app,
        Who::Staff(SUPPORT),
        &format!("{}&client_id={client}", up("../../etc/Plan.pdf")),
        PDF.to_vec(),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED, "{pdf}");
    assert_eq!(pdf["content_type"], "application/pdf");
    assert_eq!(pdf["filename"], "Plan.pdf", "path stripped");
    // A retry with the same client id returns the same file.
    let (s, again) = upload(
        &app,
        Who::Staff(SUPPORT),
        &format!("{}&client_id={client}", up("Plan.pdf")),
        PDF.to_vec(),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED);
    assert_eq!(again["id"], pdf["id"]);
    let n: i64 = sqlx::query_scalar("SELECT count(*) FROM helpdesk.ticket_attachments")
        .fetch_one(&db)
        .await
        .unwrap();
    assert_eq!(n, 1);
    let (_, photo) = upload(&app, Who::Staff(SUPPORT), &up("photo.jpg"), jpeg(1)).await;
    assert_eq!(photo["content_type"], "image/jpeg");

    // Not yet attached files are not part of any article.
    assert_eq!(
        get(&app, &id).await["articles"][0]["attachments"],
        json!([])
    );
    // Staff can fetch them already; download is an attachment that browsers must not sniff.
    let (s, h, body) = raw(
        &app,
        Who::Staff(SUPPORT),
        Method::GET,
        &format!(
            "/api/v1/tickets/{id}/attachments/{}",
            pdf["id"].as_str().unwrap()
        ),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::OK);
    assert_eq!(body, PDF);
    assert_eq!(h["content-type"], "application/pdf");
    assert_eq!(h["x-content-type-options"], "nosniff");
    assert!(h["content-disposition"]
        .to_str()
        .unwrap()
        .starts_with("attachment; filename=\"Plan.pdf\""));

    // Attach the PDF to a reply and the photo to an internal note.
    let (s, t) = call(
        &app,
        SUPPORT,
        Method::POST,
        &format!("/api/v1/tickets/{id}/notes"),
        Some(json!({ "body": "Internal photo", "attachment_ids": [photo["id"]] })),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED, "{t}");
    let (s, t) = call(
        &app,
        SUPPORT,
        Method::POST,
        &format!("/api/v1/tickets/{id}/replies"),
        Some(json!({ "body": "See the plan", "attachment_ids": [pdf["id"]] })),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED, "{t}");
    let articles = t["articles"].as_array().unwrap();
    assert_eq!(
        articles[1]["attachments"][0]["filename"],
        "Plan.pdf".replace("Plan", "photo").replace("pdf", "jpg")
    );
    assert_eq!(articles[2]["attachments"][0]["filename"], "Plan.pdf");
    // A file can be used once, and only on its own ticket.
    let other = new_ticket(&app, "Other").await;
    let (s, _) = call(
        &app,
        SUPPORT,
        Method::POST,
        &format!("/api/v1/tickets/{id}/notes"),
        Some(json!({ "body": "again", "attachment_ids": [pdf["id"]] })),
    )
    .await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);
    let (_, fresh) = upload(&app, Who::Staff(SUPPORT), &up("x.pdf"), PDF.to_vec()).await;
    let (s, _) = call(
        &app,
        SUPPORT,
        Method::POST,
        &format!("/api/v1/tickets/{other}/notes"),
        Some(json!({ "body": "stolen", "attachment_ids": [fresh["id"]] })),
    )
    .await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);
    // Production may attach to notes but not to e-mail replies.
    // (Reply permission is checked before anything is linked.)
    let (s, _) = call(
        &app,
        "production@example.com",
        Method::POST,
        &format!("/api/v1/tickets/{id}/replies"),
        Some(json!({ "body": "x", "attachment_ids": [fresh["id"]] })),
    )
    .await;
    assert_eq!(s, StatusCode::FORBIDDEN);

    // The e-mail to the customer carries the PDF.
    let dir = tempfile::tempdir().unwrap();
    assert_eq!(
        process_outbox(&db, &blobs, &Mailer::Files(dir.path().to_path_buf()), 10)
            .await
            .unwrap(),
        1
    );
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
            && eml.contains("Plan.pdf")
            && eml.contains("application/pdf"),
        "{eml}"
    );
    assert!(
        !eml.contains("photo.jpg"),
        "internal attachments are never e-mailed"
    );
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn customers_attach_files_in_the_portal_and_never_see_internal_ones(db: PgPool) {
    let app = setup(db.clone()).await;
    let (s, t) = call(
        &app,
        SUPPORT,
        Method::POST,
        "/api/v1/tickets",
        Some(json!({ "subject": "Portal files", "contact_id": JAN_ID, "body": "INTERNAL" })),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED, "{t}");
    let id = t["ticket"]["id"].as_str().unwrap().to_string();
    // Staff: an internal note with a PDF, and a reply with another.
    let (_, secret) = upload(
        &app,
        Who::Staff(SUPPORT),
        &format!("/api/v1/tickets/{id}/attachments?filename=secret.pdf"),
        PDF.to_vec(),
    )
    .await;
    call(
        &app,
        SUPPORT,
        Method::POST,
        &format!("/api/v1/tickets/{id}/notes"),
        Some(json!({ "body": "note", "attachment_ids": [secret["id"]] })),
    )
    .await;
    let (_, shared) = upload(
        &app,
        Who::Staff(SUPPORT),
        &format!("/api/v1/tickets/{id}/attachments?filename=quote.pdf"),
        PDF.to_vec(),
    )
    .await;
    call(
        &app,
        SUPPORT,
        Method::POST,
        &format!("/api/v1/tickets/{id}/replies"),
        Some(json!({ "body": "Here is the quote", "attachment_ids": [shared["id"]] })),
    )
    .await;

    let jan = portal_login(&app, &db, JAN).await;
    let (s, d) = call_portal(
        &app,
        Some(&jan),
        Method::GET,
        &format!("/api/v1/portal/tickets/{id}"),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::OK, "{d}");
    let text = d.to_string();
    assert!(!text.contains("secret.pdf"), "{text}");
    assert_eq!(d["messages"][0]["attachments"][0]["filename"], "quote.pdf");
    let (s, h, body) = portal_download(&app, &jan, &id, shared["id"].as_str().unwrap()).await;
    assert_eq!((s, body.as_slice()), (StatusCode::OK, PDF));
    assert_eq!(h["x-content-type-options"], "nosniff");
    assert_eq!(
        portal_download(&app, &jan, &id, secret["id"].as_str().unwrap())
            .await
            .0,
        StatusCode::NOT_FOUND,
        "internal note attachment"
    );

    // The customer attaches a photo to a message; type rules apply here too.
    let up = format!("/api/v1/portal/tickets/{id}/attachments?filename=damage.jpg");
    assert_eq!(
        upload(&app, Who::Portal(&jan), &up, b"MZ not an image".to_vec())
            .await
            .0,
        StatusCode::UNPROCESSABLE_ENTITY
    );
    assert_eq!(
        upload(&app, Who::Portal("nope"), &up, jpeg(2)).await.0,
        StatusCode::UNAUTHORIZED
    );
    let (s, f) = upload(&app, Who::Portal(&jan), &up, jpeg(2)).await;
    assert_eq!(s, StatusCode::CREATED, "{f}");
    // Not attached yet: not downloadable by anyone via the portal's visible kinds.
    assert_eq!(
        portal_download(&app, &jan, &id, f["id"].as_str().unwrap())
            .await
            .0,
        StatusCode::OK
    );
    // A file uploaded by staff cannot be claimed by the customer.
    let (_, staff_file) = upload(
        &app,
        Who::Staff(SUPPORT),
        &format!("/api/v1/tickets/{id}/attachments?filename=s.pdf"),
        PDF.to_vec(),
    )
    .await;
    let (s, _) = call_portal(
        &app,
        Some(&jan),
        Method::POST,
        &format!("/api/v1/portal/tickets/{id}/messages"),
        Some(json!({ "body": "mine now", "attachment_ids": [staff_file["id"]] })),
    )
    .await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);
    let (s, d) = call_portal(
        &app,
        Some(&jan),
        Method::POST,
        &format!("/api/v1/portal/tickets/{id}/messages"),
        Some(json!({ "body": "Here is the damage", "attachment_ids": [f["id"]] })),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED, "{d}");
    assert_eq!(d["messages"][1]["attachments"][0]["filename"], "damage.jpg");
    assert_eq!(
        portal_download(&app, &jan, &id, f["id"].as_str().unwrap())
            .await
            .0,
        StatusCode::OK
    );

    // Staff sees it on the portal article.
    let t = get(&app, &id).await;
    let last = t["articles"].as_array().unwrap().last().unwrap().clone();
    assert_eq!(last["kind"], "portal_in");
    assert_eq!(last["attachments"][0]["filename"], "damage.jpg");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn incoming_mail_attachments_are_stored_when_acceptable(db: PgPool) {
    let app = setup(db.clone()).await;
    let mail = "From: Anna <anna@alpha.example>\r\nTo: sales@example.com\r\nSubject: Drawing\r\nMessage-ID: <att1@alpha.example>\r\nMIME-Version: 1.0\r\n\
Content-Type: multipart/mixed; boundary=\"b1\"\r\n\r\n\
--b1\r\nContent-Type: text/plain\r\n\r\nSee attached\r\n\
--b1\r\nContent-Type: application/pdf; name=\"drawing.pdf\"\r\nContent-Disposition: attachment; filename=\"drawing.pdf\"\r\nContent-Transfer-Encoding: base64\r\n\r\nJVBERi0xLjQK\r\n\
--b1\r\nContent-Type: application/octet-stream; name=\"run.exe\"\r\nContent-Disposition: attachment; filename=\"run.exe\"\r\nContent-Transfer-Encoding: base64\r\n\r\nTVqQAAMAAAAEAAAA\r\n\
--b1--\r\n";
    let (s, r) = call_raw(
        &app,
        SUPPORT,
        "/api/v1/helpdesk/inbound",
        "message/rfc822",
        mail.as_bytes().to_vec(),
    )
    .await;
    assert_eq!(s, StatusCode::OK, "{r}");
    let t = get(&app, r["ticket_id"].as_str().unwrap()).await;
    let files = t["articles"][0]["attachments"].as_array().unwrap();
    assert_eq!(files.len(), 1, "{files:?}");
    assert_eq!(files[0]["filename"], "drawing.pdf");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn tags_time_entries_and_merge(db: PgPool) {
    let app = setup(db.clone()).await;
    let a = new_ticket(&app, "Duplicate").await;
    let b = new_ticket(&app, "Original").await;
    let other_customer = new_ticket_for(&app, GAMMA, "Someone else").await;

    // Tags: normalised, unique, filterable.
    let (s, d) = tag(&app, &a, "  Warranty ").await;
    assert_eq!(s, StatusCode::OK, "{d}");
    tag(&app, &a, "warranty").await;
    tag(&app, &a, "urgent-customer").await;
    tag(&app, &b, "pumps").await;
    assert_eq!(
        get(&app, &a).await["ticket"]["tags"],
        json!(["urgent-customer", "warranty"])
    );
    assert_eq!(
        tag(&app, &a, "a,b").await.0,
        StatusCode::UNPROCESSABLE_ENTITY
    );
    assert_eq!(list(&app, SUPPORT, "tag=Warranty").await, vec![a.clone()]);
    let (_, all) = call(&app, SUPPORT, Method::GET, "/api/v1/helpdesk/tags", None).await;
    assert_eq!(all.as_array().unwrap().len(), 3);
    let (s, d) = call(
        &app,
        SUPPORT,
        Method::DELETE,
        &format!("/api/v1/tickets/{a}/tags/urgent-customer"),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::OK);
    assert_eq!(d["ticket"]["tags"], json!(["warranty"]));

    // Time entries with totals; others' entries can only be removed by an admin.
    assert_eq!(
        log_time(&app, &a, SUPPORT, 0, false).await.0,
        StatusCode::UNPROCESSABLE_ENTITY
    );
    assert_eq!(
        log_time(&app, &a, SUPPORT, 1441, false).await.0,
        StatusCode::UNPROCESSABLE_ENTITY
    );
    assert_eq!(
        log_time(&app, &a, "viewer@example.com", 5, false).await.0,
        StatusCode::FORBIDDEN
    );
    let (s, t) = log_time(&app, &a, SUPPORT, 15, true).await;
    assert_eq!(s, StatusCode::CREATED, "{t}");
    log_time(&app, &a, SALES, 30, false).await;
    let (_, t) = log_time(&app, &b, SUPPORT, 10, false).await;
    assert_eq!(t["total_minutes"], 10);
    let (_, t) = call(
        &app,
        SUPPORT,
        Method::GET,
        &format!("/api/v1/tickets/{a}/time-entries"),
        None,
    )
    .await;
    assert_eq!(
        (t["total_minutes"].as_i64(), t["billable_minutes"].as_i64()),
        (Some(45), Some(15))
    );
    assert_eq!(get(&app, &a).await["ticket"]["time_minutes"], 45);
    let sales_entry = t["items"]
        .as_array()
        .unwrap()
        .iter()
        .find(|e| e["user_name"] == "Sales User")
        .unwrap()["id"]
        .as_str()
        .unwrap()
        .to_string();
    assert_eq!(
        call(
            &app,
            SUPPORT,
            Method::DELETE,
            &format!("/api/v1/tickets/{a}/time-entries/{sales_entry}"),
            None
        )
        .await
        .0,
        StatusCode::FORBIDDEN
    );
    let (s, t) = call(
        &app,
        ADMIN,
        Method::DELETE,
        &format!("/api/v1/tickets/{a}/time-entries/{sales_entry}"),
        None,
    )
    .await;
    assert_eq!((s, t["total_minutes"].as_i64()), (StatusCode::OK, Some(15)));

    // An attachment on the duplicate moves along.
    let (_, f) = upload(
        &app,
        Who::Staff(SUPPORT),
        &format!("/api/v1/tickets/{a}/attachments?filename=moved.pdf"),
        PDF.to_vec(),
    )
    .await;
    call(
        &app,
        SUPPORT,
        Method::POST,
        &format!("/api/v1/tickets/{a}/notes"),
        Some(json!({ "body": "with file", "attachment_ids": [f["id"]] })),
    )
    .await;

    // Merge rules.
    assert_eq!(
        merge(&app, &a, &a).await.0,
        StatusCode::UNPROCESSABLE_ENTITY
    );
    assert_eq!(
        merge(&app, &a, &other_customer).await.0,
        StatusCode::UNPROCESSABLE_ENTITY,
        "different customer"
    );
    assert_eq!(
        merge(&app, &a, "00000000-0000-7000-8000-0000000fffff")
            .await
            .0,
        StatusCode::NOT_FOUND
    );
    let a_number = get(&app, &a).await["ticket"]["number"]
        .as_str()
        .unwrap()
        .to_string();

    let (s, d) = merge(&app, &a, &b).await;
    assert_eq!(s, StatusCode::OK, "{d}");
    assert_eq!(d["ticket"]["id"], b.as_str());
    assert_eq!(d["ticket"]["tags"], json!(["pumps", "warranty"]));
    assert_eq!(d["ticket"]["time_minutes"], 25);
    let bodies: Vec<&str> = d["articles"]
        .as_array()
        .unwrap()
        .iter()
        .map(|x| x["body"].as_str().unwrap())
        .collect();
    assert!(
        bodies.contains(&"with file") && bodies.contains(&"Internal first note"),
        "{bodies:?}"
    );
    assert!(
        bodies
            .iter()
            .any(|b| b.contains(&a_number) && b.contains("merged")),
        "{bodies:?}"
    );
    let moved = d["articles"]
        .as_array()
        .unwrap()
        .iter()
        .find(|x| x["body"] == "with file")
        .unwrap();
    assert_eq!(moved["attachments"][0]["filename"], "moved.pdf");
    let (s, _, body) = raw(
        &app,
        Who::Staff(SUPPORT),
        Method::GET,
        &format!(
            "/api/v1/tickets/{b}/attachments/{}",
            f["id"].as_str().unwrap()
        ),
        None,
    )
    .await;
    assert_eq!((s, body.as_slice()), (StatusCode::OK, PDF));

    let src = get(&app, &a).await;
    assert_eq!(src["ticket"]["status"], "closed");
    assert_eq!(src["ticket"]["merged_into_id"], b.as_str());
    assert!(src["ticket"]["tags"].as_array().unwrap().is_empty());
    assert_eq!(
        src["articles"].as_array().unwrap().len(),
        1,
        "only the system note stays"
    );
    let audited: i64 =
        sqlx::query_scalar("SELECT count(*) FROM audit.events WHERE action = 'merged'")
            .fetch_one(&db)
            .await
            .unwrap();
    assert_eq!(audited, 2);
    // Not reversible, not repeatable; mail with the old number lands on the target.
    assert_eq!(merge(&app, &a, &b).await.0, StatusCode::CONFLICT);
    assert_eq!(merge(&app, &b, &a).await.0, StatusCode::CONFLICT);
    let mail = format!("From: anna@alpha.example\r\nSubject: Re: [Ticket#{a_number}] x\r\nMessage-ID: <m1@alpha.example>\r\nContent-Type: text/plain\r\n\r\nStill broken\r\n");
    let (_, r) = call_raw(
        &app,
        SUPPORT,
        "/api/v1/helpdesk/inbound",
        "message/rfc822",
        mail.into_bytes(),
    )
    .await;
    assert_eq!(r["ticket_id"], b.as_str());
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn satisfaction_survey_is_optional_single_use_and_expires(db: PgPool) {
    let app = setup(db.clone()).await;
    let survey_mails = |db: PgPool| async move {
        sqlx::query_as::<_, (String, String, String)>(
            "SELECT to_address, subject, body FROM core.mail_outbox WHERE subject LIKE '%T20%' ORDER BY created_at",
        )
        .fetch_all(&db)
        .await
        .unwrap()
    };
    let token_of = |body: &str, rating: &str| {
        let start = body.find("#token=").unwrap() + "#token=".len();
        let token: String = body[start..]
            .chars()
            .take_while(|c| c.is_ascii_alphanumeric() || *c == '_')
            .collect();
        assert!(body.contains(&format!("&rating={rating}")));
        token
    };

    // Off by default: closing sends nothing.
    let quiet = new_ticket(&app, "No survey").await;
    update(&app, &quiet, None, Some("closed")).await;
    assert!(survey_mails(db.clone()).await.is_empty());

    call(
        &app,
        ADMIN,
        Method::PUT,
        "/api/v1/helpdesk/settings",
        Some(json!({ "default_team_id": null, "csat_enabled": true })),
    )
    .await;
    // Dutch customer: the mail is in Dutch and goes to the contact's address.
    let (_, t) = call(
        &app,
        SUPPORT,
        Method::POST,
        "/api/v1/tickets",
        Some(json!({ "subject": "Pomp lekt", "contact_id": JAN_ID, "body": "x" })),
    )
    .await;
    let id = t["ticket"]["id"].as_str().unwrap().to_string();
    update(&app, &id, None, Some("closed")).await;
    let mails = survey_mails(db.clone()).await;
    assert_eq!(mails.len(), 1, "{mails:?}");
    assert_eq!(mails[0].0, JAN);
    assert!(mails[0].1.contains("Hoe tevreden"), "{}", mails[0].1);
    let token = token_of(&mails[0].2, "good");
    assert!(mails[0].2.contains("http://localhost:8081/csat#token="));
    // Only the hash is stored.
    let leaked: i64 = sqlx::query_scalar("SELECT count(*) FROM helpdesk.csat_surveys WHERE encode(token_hash, 'escape') LIKE '%tcq_%'")
        .fetch_one(&db).await.unwrap();
    assert_eq!(leaked, 0);
    // Reclosing the same ticket does not ask again.
    update(&app, &id, None, Some("open")).await;
    update(&app, &id, None, Some("closed")).await;
    assert_eq!(survey_mails(db.clone()).await.len(), 1);

    // The link page: reading does not use up the token.
    let uri = format!("/api/v1/csat/{token}");
    for _ in 0..2 {
        let (s, i) = call_portal(&app, None, Method::GET, &uri, None).await;
        assert_eq!(s, StatusCode::OK, "{i}");
        assert_eq!(i["state"], "open");
        assert_eq!(i["language"], "nl");
    }
    assert_eq!(
        call_portal(&app, None, Method::GET, "/api/v1/csat/tcq_unknown", None)
            .await
            .0,
        StatusCode::NOT_FOUND
    );
    assert_eq!(
        call_portal(
            &app,
            None,
            Method::POST,
            &uri,
            Some(json!({ "rating": "meh" }))
        )
        .await
        .0,
        StatusCode::UNPROCESSABLE_ENTITY
    );
    let (s, i) = call_portal(
        &app,
        None,
        Method::POST,
        &uri,
        Some(json!({ "rating": "bad", "comment": "Too slow" })),
    )
    .await;
    assert_eq!(s, StatusCode::OK, "{i}");
    assert_eq!(i["state"], "rated");
    // Single use.
    let (s, _) = call_portal(
        &app,
        None,
        Method::POST,
        &uri,
        Some(json!({ "rating": "good" })),
    )
    .await;
    assert_eq!(s, StatusCode::CONFLICT);
    let t = get(&app, &id).await;
    assert_eq!(t["ticket"]["csat_rating"], "bad");
    assert_eq!(t["ticket"]["csat_comment"], "Too slow");
    assert!(!t["ticket"]["csat_rated_at"].is_null());

    // Expiry after 30 days.
    let id2 = new_ticket(&app, "Expires").await;
    update(&app, &id2, None, Some("closed")).await;
    let mails = survey_mails(db.clone()).await;
    assert_eq!(mails.len(), 2);
    let token2 = token_of(&mails[1].2, "bad");
    let days: f64 = sqlx::query_scalar("SELECT (extract(epoch FROM (expires_at - created_at)) / 86400)::float8 FROM helpdesk.csat_surveys ORDER BY created_at DESC LIMIT 1")
        .fetch_one(&db).await.unwrap();
    assert!((days - 30.0).abs() < 0.01, "{days}");
    sqlx::query("UPDATE helpdesk.csat_surveys SET expires_at = now() - interval '1 second' WHERE rated_at IS NULL")
        .execute(&db).await.unwrap();
    let uri2 = format!("/api/v1/csat/{token2}");
    let (_, i) = call_portal(&app, None, Method::GET, &uri2, None).await;
    assert_eq!(i["state"], "expired");
    assert_eq!(
        call_portal(
            &app,
            None,
            Method::POST,
            &uri2,
            Some(json!({ "rating": "good" }))
        )
        .await
        .0,
        StatusCode::CONFLICT
    );
    assert!(get(&app, &id2).await["ticket"]["csat_rating"].is_null());
}

/// A customer's client id is never used as a file id as such: naming the id of an existing file
/// (staff's, on a ticket the customer cannot see) neither links that file to the customer's
/// ticket nor answers differently from a fresh id. Retries still find the first upload.
#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_portal_client_id_cannot_claim_or_probe_an_existing_file(db: PgPool) {
    let app = setup(db.clone()).await;
    let (s, t) = call(
        &app,
        SUPPORT,
        Method::POST,
        "/api/v1/tickets",
        Some(json!({ "subject": "Jan's files", "contact_id": JAN_ID, "body": "x" })),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED, "{t}");
    let mine = t["ticket"]["id"].as_str().unwrap().to_string();
    // Staff stores a document on a ticket of another customer, under a known id.
    let other = new_ticket_for(&app, GAMMA, "Gamma's contract").await;
    let taken = "00000000-0000-7000-8000-00000000cc01";
    let (s, staff_file) = upload(
        &app,
        Who::Staff(SUPPORT),
        &format!("/api/v1/tickets/{other}/attachments?filename=contract.pdf&client_id={taken}"),
        PDF.to_vec(),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED, "{staff_file}");
    assert_eq!(staff_file["id"], taken);

    let jan = portal_login(&app, &db, JAN).await;
    let up = |client: &str| {
        format!("/api/v1/portal/tickets/{mine}/attachments?filename=a.jpg&client_id={client}")
    };
    // The taken id and a fresh one are answered the same way, and neither returns staff's file.
    let (s1, f1) = upload(&app, Who::Portal(&jan), &up(taken), jpeg(1)).await;
    let fresh = "00000000-0000-7000-8000-00000000cc02";
    let (s2, f2) = upload(&app, Who::Portal(&jan), &up(fresh), jpeg(2)).await;
    assert_eq!(
        (s1, s2),
        (StatusCode::CREATED, StatusCode::CREATED),
        "{f1} {f2}"
    );
    assert_ne!(f1["id"], taken);
    assert_ne!(f2["id"], fresh);
    assert_eq!(f1["filename"], "a.jpg");
    assert_eq!(f1["content_type"], "image/jpeg");
    // A retry with the same client id finds the first upload.
    let (s, again) = upload(&app, Who::Portal(&jan), &up(taken), jpeg(1)).await;
    assert_eq!(s, StatusCode::CREATED);
    assert_eq!(again["id"], f1["id"]);

    // Staff's file is not reachable through the customer's ticket: same answer as a missing id.
    let (s_taken, _, body_taken) = portal_download(&app, &jan, &mine, taken).await;
    let (s_missing, _, body_missing) =
        portal_download(&app, &jan, &mine, "00000000-0000-7000-8000-00000000cc99").await;
    assert_eq!(s_taken, StatusCode::NOT_FOUND);
    assert_eq!((s_taken, body_taken), (s_missing, body_missing));
    // Staff's file stays on its own ticket only.
    let linked: Vec<String> = sqlx::query_scalar(
        "SELECT ticket_id::text FROM helpdesk.ticket_attachments WHERE file_id = $1::uuid",
    )
    .bind(taken)
    .fetch_all(&db)
    .await
    .unwrap();
    assert_eq!(linked, vec![other]);
}
