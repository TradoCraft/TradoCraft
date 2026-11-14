//! SLA notices to the customer (ADR 0067).

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

// ---------------------------------------------------------------------------------------------
// Review fixes: serialised rules, eligibility, paging, per-address limit, calendar at claim time
// ---------------------------------------------------------------------------------------------

async fn make_late(db: &PgPool, id: &str, hours: i32) {
    sqlx::query("UPDATE helpdesk.tickets SET first_response_due_at = now() - make_interval(hours => $2) WHERE id = $1::uuid")
        .bind(id)
        .bind(hours)
        .execute(db)
        .await
        .unwrap();
}

async fn breach_run(db: &PgPool) -> usize {
    tradocraft_helpdesk::sla_notice::send_breach_notices(db)
        .await
        .unwrap()
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn concurrent_rule_replacements_leave_exactly_one_consistent_set(db: PgPool) {
    let app = setup(db.clone()).await;
    let set_a = json!([
        { "team_id": null, "priority": null, "ack_enabled": true, "breach_enabled": false },
        { "team_id": null, "priority": "high", "ack_enabled": false, "breach_enabled": true },
        { "team_id": null, "priority": "low", "ack_enabled": true, "breach_enabled": true },
    ]);
    let set_b = json!([
        { "team_id": null, "priority": null, "ack_enabled": false, "breach_enabled": true },
        { "team_id": null, "priority": "urgent", "ack_enabled": true, "breach_enabled": false },
    ]);
    // The race itself is not reproducible deterministically: several rounds of concurrent
    // replacements (tokio::join!) check the invariant instead.
    for _ in 0..5 {
        let (a, b, c, d) = tokio::join!(
            notices(&app, set_a.clone()),
            notices(&app, set_b.clone()),
            notices(&app, set_a.clone()),
            notices(&app, set_b.clone()),
        );
        for (status, r) in [a, b, c, d] {
            assert_eq!(status, StatusCode::OK, "{r}");
        }
        let mut stored: Vec<(Option<String>, bool, bool)> = sqlx::query_as(
            "SELECT priority, ack_enabled, breach_enabled FROM helpdesk.sla_notice_settings ORDER BY priority NULLS FIRST",
        )
        .fetch_all(&db)
        .await
        .unwrap();
        let mut a_rows = vec![
            (None, true, false),
            (Some("high".to_string()), false, true),
            (Some("low".to_string()), true, true),
        ];
        let mut b_rows = vec![
            (None, false, true),
            (Some("urgent".to_string()), true, false),
        ];
        stored.sort();
        a_rows.sort();
        b_rows.sort();
        assert!(stored == a_rows || stored == b_rows, "{stored:?}");
        let (_, got) = api(&app, ADMIN, Method::GET, "/helpdesk/sla-notices", None).await;
        assert_eq!(got["rules"].as_array().unwrap().len(), stored.len());
    }
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_breach_worker_skips_internal_merged_split_and_paused_tickets(db: PgPool) {
    let app = setup(db.clone()).await;
    all_priorities(&app, false, true).await;
    let (target, _) = receive(&app, "target@alpha.example", "Target").await;
    let mut ids = Vec::new();
    for (i, column) in ["internal", "merged", "split", "paused"].iter().enumerate() {
        let (id, _) = receive(&app, &format!("c{i}@alpha.example"), &format!("Case {i}")).await;
        let sql = match *column {
            "internal" => "UPDATE helpdesk.tickets SET internal = true WHERE id = $1::uuid",
            "merged" => "UPDATE helpdesk.tickets SET merged_into_id = $2::uuid WHERE id = $1::uuid",
            "split" => "UPDATE helpdesk.tickets SET split_from_id = $2::uuid WHERE id = $1::uuid",
            _ => "UPDATE helpdesk.tickets SET sla_paused_at = now() WHERE id = $1::uuid",
        };
        let mut q = sqlx::query(sql).bind(&id);
        if sql.contains("$2") {
            q = q.bind(&target);
        }
        q.execute(&db).await.unwrap();
        make_late(&db, &id, 2).await;
        ids.push(id);
    }
    assert_eq!(breach_run(&db).await, 0);
    assert!(outbox(&db).await.is_empty());
    // The state at lock time decides, not the scan: a row that is locked (a concurrent writer) is
    // skipped and picked up on the next pass. The window between the scan and the lock cannot be
    // held open from outside, so the re-read predicates are covered by the eligible/ineligible
    // split above and the paging test below.
    make_late(&db, &target, 1).await;
    assert_eq!(breach_run(&db).await, 1);
    let mails = outbox(&db).await;
    assert_eq!(mails.len(), 1);
    assert_eq!(mails[0].0, "target@alpha.example");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn ineligible_candidates_do_not_starve_an_eligible_ticket(db: PgPool) {
    let app = setup(db.clone()).await;
    all_priorities(&app, false, true).await;
    // More than one page (100) of candidates that pass the scan but get no notice (an automated
    // sender), all due before the eligible ticket.
    for i in 0..105 {
        let (id, _) = receive(
            &app,
            &format!("noreply+{i}@alpha.example"),
            &format!("Auto {i}"),
        )
        .await;
        make_late(&db, &id, 5).await;
    }
    let (eligible, _) = receive(&app, "anna@alpha.example", "Real").await;
    make_late(&db, &eligible, 1).await;
    assert_eq!(breach_run(&db).await, 1);
    let mails = outbox(&db).await;
    assert_eq!(mails.len(), 1);
    assert_eq!(mails[0].0, "anna@alpha.example");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn concurrent_notices_to_one_address_stay_within_five_per_hour(db: PgPool) {
    let app = setup(db.clone()).await;
    // Acknowledgements: eight tickets for one address created at the same time. The race is not
    // deterministic, so the invariant is checked with concurrent tasks (tokio::join!).
    all_priorities(&app, true, false).await;
    let (a, b, c, d, e, f, g, h) = tokio::join!(
        receive(&app, "anna@alpha.example", "One"),
        receive(&app, "anna@alpha.example", "Two"),
        receive(&app, "anna@alpha.example", "Three"),
        receive(&app, "anna@alpha.example", "Four"),
        receive(&app, "anna@alpha.example", "Five"),
        receive(&app, "anna@alpha.example", "Six"),
        receive(&app, "anna@alpha.example", "Seven"),
        receive(&app, "anna@alpha.example", "Eight"),
    );
    assert_eq!(outbox(&db).await.len(), 5, "acknowledgements");
    // Breach notices: the log of the hour is full, so nothing more goes to that address.
    all_priorities(&app, false, true).await;
    for (id, _) in [a, b, c, d, e, f, g, h] {
        make_late(&db, &id, 1).await;
    }
    let (x, y, z) = tokio::join!(breach_run(&db), breach_run(&db), breach_run(&db));
    assert_eq!(x + y + z, 0);
    assert_eq!(outbox(&db).await.len(), 5);
    // With an empty log, concurrent workers together queue at most five.
    sqlx::query("DELETE FROM helpdesk.sla_notice_log")
        .execute(&db)
        .await
        .unwrap();
    sqlx::query("DELETE FROM core.mail_outbox")
        .execute(&db)
        .await
        .unwrap();
    let (x, y, z) = tokio::join!(breach_run(&db), breach_run(&db), breach_run(&db));
    assert_eq!(x + y + z, 5);
    assert_eq!(outbox(&db).await.len(), 5);
    let logged: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM helpdesk.sla_notice_log WHERE address = 'anna@alpha.example'",
    )
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(logged, 5);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_breach_notice_is_not_queued_when_the_calendar_closed_while_waiting_for_the_lock(
    db: PgPool,
) {
    let app = setup(db.clone()).await;
    all_priorities(&app, true, true).await;
    let today: i32 =
        sqlx::query_scalar("SELECT extract(isodow FROM now() AT TIME ZONE 'Europe/Brussels')::int")
            .fetch_one(&db)
            .await
            .unwrap();
    let local_minutes: i32 = sqlx::query_scalar(
        "SELECT (extract(hour FROM now() AT TIME ZONE 'Europe/Brussels') * 60 + extract(minute FROM now() AT TIME ZONE 'Europe/Brussels'))::int",
    )
    .fetch_one(&db)
    .await
    .unwrap();
    if local_minutes >= 24 * 60 - 2 {
        return; // too close to the end of the open window of today
    }
    let (status, r) = put(
        &app,
        ADMIN,
        "/helpdesk/calendar",
        json!({ "enabled": true, "time_zone": "Europe/Brussels",
            "hours": [{ "weekday": today, "start_time": "00:00", "end_time": "23:59" }] }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{r}");
    // The acknowledgement does not depend on the opening hours.
    let (id, _) = receive(&app, "anna@alpha.example", "Pump noise").await;
    assert_eq!(outbox(&db).await.len(), 1, "ack while open");
    sqlx::query("DELETE FROM core.mail_outbox")
        .execute(&db)
        .await
        .unwrap();
    sqlx::query("DELETE FROM helpdesk.sla_notice_log")
        .execute(&db)
        .await
        .unwrap();
    make_late(&db, &id, 1).await;
    let company: String =
        sqlx::query_scalar("SELECT company_id::text FROM helpdesk.tickets WHERE id = $1::uuid")
            .bind(&id)
            .fetch_one(&db)
            .await
            .unwrap();
    // Hold the address lock so the worker passes the open check and then waits for it.
    let mut holder = db.begin().await.unwrap();
    sqlx::query("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))")
        .bind(format!("sla-notice:{company}:anna@alpha.example"))
        .execute(&mut *holder)
        .await
        .unwrap();
    let worker = {
        let db = db.clone();
        tokio::spawn(async move { breach_run(&db).await })
    };
    let mut waiting = false;
    for _ in 0..200 {
        let n: i64 = sqlx::query_scalar(
            "SELECT count(*) FROM pg_locks WHERE locktype = 'advisory' AND NOT granted
               AND database = (SELECT oid FROM pg_database WHERE datname = current_database())",
        )
        .fetch_one(&db)
        .await
        .unwrap();
        if n > 0 {
            waiting = true;
            break;
        }
        tokio::time::sleep(std::time::Duration::from_millis(50)).await;
    }
    assert!(waiting, "the worker should be waiting for the address lock");
    // The business closes while it waits (hours moved to another weekday, tickets untouched).
    let other = if today == 1 { 2 } else { 1 };
    sqlx::query("UPDATE helpdesk.business_hours SET weekday = $1::smallint")
        .bind(other)
        .execute(&db)
        .await
        .unwrap();
    holder.commit().await.unwrap();
    assert_eq!(worker.await.unwrap(), 0);
    assert!(outbox(&db).await.is_empty(), "{:?}", outbox(&db).await);
    let logged: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM helpdesk.sla_notice_log WHERE ticket_id = $1::uuid AND kind = 'breach'",
    )
    .bind(&id)
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(logged, 0);
    // Closed, a new ticket is still acknowledged at once.
    receive(&app, "bob@alpha.example", "Valve").await;
    let mails = outbox(&db).await;
    assert_eq!(mails.len(), 1);
    assert_eq!(mails[0].0, "bob@alpha.example");
}
