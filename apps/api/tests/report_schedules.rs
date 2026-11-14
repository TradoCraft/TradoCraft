//! Scheduled report mails (ADR 0065).

mod common;

use std::path::PathBuf;

use axum::http::{Method, StatusCode};
use common::{call, setup};
use serde_json::{json, Value};
use sqlx::PgPool;
use tradocraft_core::DocumentConfig;

const ADMIN: &str = "admin@example.com";
const ADMIN_ID: &str = "00000000-0000-7000-8000-000000000101";
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

fn docs() -> DocumentConfig {
    DocumentConfig {
        typst_bin: std::env::var("TYPST_BIN")
            .unwrap_or_else(|_| "typst".into())
            .into(),
        template_dir: PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../templates"),
    }
}

/// A saved report of the customers, shared with the company.
async fn saved_report(app: &axum::Router, user: &str, shared: bool) -> String {
    let (status, r) = post(
        app,
        user,
        "/custom-reports",
        json!({ "name": "Customers", "description": "", "shared": shared,
            "definition": { "object": "customer", "columns": [{ "field": "customer.name" }],
                            "sort": [{ "column": "customer.name", "dir": "asc" }] } }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{r}");
    r["id"].as_str().unwrap().to_string()
}

fn custom(report: &str, format: &str) -> Value {
    json!({ "name": "Customer list", "source": "custom", "report_id": report, "frequency": "weekly",
        "weekday": 1, "send_time": "07:30", "format": format,
        "user_ids": [SUPPORT_ID], "addresses": ["Boss@Example.com"] })
}

fn helpdesk(table: &str) -> Value {
    json!({ "name": "Weekly volume", "source": "helpdesk", "frequency": "daily", "format": "csv",
        "helpdesk": { "table": table, "period": "last_7_days" },
        "user_ids": [], "addresses": ["ops@example.com"] })
}

/// (to, subject, attachment name, attachment type, attachment bytes) of the queued mails.
async fn outbox(db: &PgPool) -> Vec<(String, String, String, String, Vec<u8>)> {
    sqlx::query_as(
        "SELECT to_address, subject, attachment_name, attachment_type, attachment_data
         FROM core.mail_outbox WHERE delivery = 'queued' AND attachment_name IS NOT NULL
         ORDER BY to_address",
    )
    .fetch_all(db)
    .await
    .unwrap()
}

async fn schedule(app: &axum::Router, body: Value) -> Value {
    let (status, s) = post(app, ADMIN, "/report-schedules", body).await;
    assert_eq!(status, StatusCode::CREATED, "{s}");
    s
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_saved_report_is_mailed_as_csv_to_users_and_addresses(db: PgPool) {
    let app = setup(db.clone()).await;
    let report = saved_report(&app, ADMIN, true).await;
    let s = schedule(&app, custom(&report, "csv")).await;
    assert_eq!(s["send_time"], "07:30");
    assert_eq!(s["addresses"], json!(["boss@example.com"]));
    assert_eq!(s["report_name"], "Customers");
    assert!(s["next_run_at"].is_string());
    let id = s["id"].as_str().unwrap();
    let (status, r) = post(
        &app,
        ADMIN,
        &format!("/report-schedules/{id}/send"),
        json!({}),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{r}");
    assert_eq!(r["mails"], 2);
    let mails = outbox(&db).await;
    assert_eq!(mails.len(), 2);
    assert_eq!(mails[0].0, "boss@example.com");
    assert_eq!(mails[1].0, SUPPORT);
    assert!(mails[0].1.contains("Customer list"), "{}", mails[0].1);
    assert!(mails[0].2.ends_with(".csv"), "{}", mails[0].2);
    assert_eq!(mails[0].3, "text/csv");
    let csv = String::from_utf8(mails[0].4.clone()).unwrap();
    assert!(csv.starts_with("Name\r\n"), "{csv}");
    assert!(csv.contains("Alpha Installaties NV"), "{csv}");
    // Audited, with counts only.
    let n: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM audit.events WHERE entity = 'report_schedule' AND action = 'run' AND data->>'status' = 'sent'",
    )
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(n, 1);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_saved_report_can_be_mailed_as_pdf(db: PgPool) {
    let app = setup(db.clone()).await;
    let report = saved_report(&app, ADMIN, false).await;
    let s = schedule(&app, custom(&report, "pdf")).await;
    let id = s["id"].as_str().unwrap();
    let (status, r) = post(
        &app,
        ADMIN,
        &format!("/report-schedules/{id}/send"),
        json!({}),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{r}");
    let mails = outbox(&db).await;
    assert_eq!(mails[0].3, "application/pdf");
    assert!(mails[0].4.starts_with(b"%PDF-"));
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_helpdesk_report_is_mailed_as_csv_and_as_pdf(db: PgPool) {
    let app = setup(db.clone()).await;
    let s = schedule(&app, helpdesk("volume")).await;
    let id = s["id"].as_str().unwrap();
    assert_eq!(s["helpdesk"]["period"], "last_7_days");
    let (status, r) = post(
        &app,
        ADMIN,
        &format!("/report-schedules/{id}/send"),
        json!({}),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{r}");
    let mails = outbox(&db).await;
    assert_eq!(mails.len(), 1);
    let csv = String::from_utf8(mails[0].4.clone()).unwrap();
    assert!(csv.starts_with("period,created,closed\r\n"), "{csv}");
    // Seven days, one row each (empty days are listed).
    assert_eq!(csv.lines().count(), 8, "{csv}");
    let mut as_pdf = helpdesk("sla");
    as_pdf["format"] = json!("pdf");
    let s = schedule(&app, as_pdf).await;
    let id = s["id"].as_str().unwrap();
    let (status, r) = post(
        &app,
        ADMIN,
        &format!("/report-schedules/{id}/send"),
        json!({}),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{r}");
    let pdfs: Vec<_> = outbox(&db)
        .await
        .into_iter()
        .filter(|m| m.3 == "application/pdf")
        .collect();
    assert_eq!(pdfs.len(), 1);
    assert!(pdfs[0].4.starts_with(b"%PDF-"));
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_worker_pass_runs_due_schedules_once_and_sets_the_next_run(db: PgPool) {
    let app = setup(db.clone()).await;
    let s = schedule(&app, helpdesk("volume")).await;
    let id = s["id"].as_str().unwrap().to_string();
    // Not due yet.
    assert_eq!(
        tradocraft_reports::schedule::run_due(&db, &docs())
            .await
            .unwrap(),
        0
    );
    sqlx::query("UPDATE reports.schedules SET next_run_at = now() - interval '3 days'")
        .execute(&db)
        .await
        .unwrap();
    assert_eq!(
        tradocraft_reports::schedule::run_due(&db, &docs())
            .await
            .unwrap(),
        1
    );
    assert_eq!(outbox(&db).await.len(), 1);
    // One run for the missed days, and the next one is in the future.
    assert_eq!(
        tradocraft_reports::schedule::run_due(&db, &docs())
            .await
            .unwrap(),
        0
    );
    let (next_ok, status): (bool, String) = sqlx::query_as(
        "SELECT next_run_at > now(), last_status FROM reports.schedules WHERE id = $1::uuid",
    )
    .bind(&id)
    .fetch_one(&db)
    .await
    .unwrap();
    assert!(next_ok);
    assert_eq!(status, "sent");
    // A paused schedule is left alone.
    sqlx::query(
        "UPDATE reports.schedules SET next_run_at = now() - interval '1 hour', active = false",
    )
    .execute(&db)
    .await
    .unwrap();
    assert_eq!(
        tradocraft_reports::schedule::run_due(&db, &docs())
            .await
            .unwrap(),
        0
    );
    assert_eq!(outbox(&db).await.len(), 1);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_run_is_refused_when_the_owner_lost_access_and_the_reason_is_kept(db: PgPool) {
    let app = setup(db.clone()).await;
    let s = schedule(&app, helpdesk("volume")).await;
    let id = s["id"].as_str().unwrap().to_string();
    sqlx::query("UPDATE core.user_companies SET roles = '{viewer}' WHERE user_id = $1::uuid")
        .bind(ADMIN_ID)
        .execute(&db)
        .await
        .unwrap();
    sqlx::query("UPDATE reports.schedules SET next_run_at = now() - interval '1 hour'")
        .execute(&db)
        .await
        .unwrap();
    assert_eq!(
        tradocraft_reports::schedule::run_due(&db, &docs())
            .await
            .unwrap(),
        1
    );
    assert!(outbox(&db).await.is_empty());
    let (status, error, moved): (String, String, bool) = sqlx::query_as(
        "SELECT last_status, last_error, next_run_at > now() FROM reports.schedules WHERE id = $1::uuid",
    )
    .bind(&id)
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(status, "failed");
    assert!(!error.is_empty());
    assert!(moved, "a refused schedule is not retried every pass");
    // The manager sees the reason in the list.
    sqlx::query("UPDATE core.user_companies SET roles = '{admin}' WHERE user_id = $1::uuid")
        .bind(ADMIN_ID)
        .execute(&db)
        .await
        .unwrap();
    let (_, list) = api(&app, ADMIN, Method::GET, "/report-schedules", None).await;
    assert_eq!(list[0]["last_status"], "failed");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_deleted_report_stops_its_schedule_and_a_private_one_cannot_be_scheduled_by_others(
    db: PgPool,
) {
    let app = setup(db.clone()).await;
    // A manager who may schedule but is not the author of a private report.
    let private = saved_report(&app, SALES, false).await;
    let (status, _) = post(
        &app,
        "manager@example.com",
        "/report-schedules",
        custom(&private, "csv"),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    // The author without the schedule permission cannot schedule it either.
    let (status, _) = post(&app, SALES, "/report-schedules", custom(&private, "csv")).await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    // Deleting the report removes its schedules.
    let shared = saved_report(&app, ADMIN, true).await;
    let s = schedule(&app, custom(&shared, "csv")).await;
    let (status, _) = api(
        &app,
        ADMIN,
        Method::DELETE,
        &format!("/custom-reports/{shared}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    let n: i64 = sqlx::query_scalar("SELECT count(*) FROM reports.schedules WHERE id = $1::uuid")
        .bind(s["id"].as_str().unwrap())
        .fetch_one(&db)
        .await
        .unwrap();
    assert_eq!(n, 0);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn schedules_are_validated_audited_and_for_the_people_who_may_send_data_out(db: PgPool) {
    let app = setup(db.clone()).await;
    let report = saved_report(&app, ADMIN, true).await;
    // Support may read reports but not mail them.
    let (status, _) = post(&app, SUPPORT, "/report-schedules", custom(&report, "csv")).await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, _) = api(&app, SUPPORT, Method::GET, "/report-schedules", None).await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let with = |k: &str, v: Value| {
        let mut b = custom(&report, "csv");
        b[k] = v;
        b
    };
    for (what, body) in [
        ("frequency", with("frequency", json!("hourly"))),
        ("weekday needed", with("weekday", json!(null))),
        ("weekday range", with("weekday", json!(8))),
        ("monthly needs a day", with("frequency", json!("monthly"))),
        ("time", with("send_time", json!("25:00"))),
        ("zone", with("time_zone", json!("Mars/Base"))),
        ("format", with("format", json!("xlsx"))),
        ("address", with("addresses", json!(["nobody"]))),
        ("no recipient", with("user_ids", json!([])).tap_addresses()),
        (
            "not a member",
            with("user_ids", json!(["00000000-0000-7000-8000-0000000000ff"])),
        ),
        ("name", with("name", json!("  "))),
        (
            "both sources",
            with(
                "helpdesk",
                json!({ "table": "volume", "period": "yesterday" }),
            ),
        ),
    ] {
        let (status, r) = post(&app, ADMIN, "/report-schedules", body).await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{what}: {r}");
    }
    for spec in [
        json!({ "table": "nope", "period": "yesterday" }),
        json!({ "table": "volume", "period": "forever" }),
        json!({ "table": "volume", "period": "yesterday", "group": "year" }),
        json!({ "table": "volume", "period": "yesterday", "category": "nope" }),
    ] {
        let mut b = helpdesk("volume");
        b["helpdesk"] = spec.clone();
        let (status, r) = post(&app, ADMIN, "/report-schedules", b).await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{spec}: {r}");
    }
    let mut b = helpdesk("volume");
    b["helpdesk"]["team_id"] = json!("00000000-0000-7000-8000-00000000dead");
    assert_eq!(
        post(&app, ADMIN, "/report-schedules", b).await.0,
        StatusCode::NOT_FOUND
    );

    // Update, pause and delete are audited.
    let s = schedule(&app, helpdesk("volume")).await;
    let id = s["id"].as_str().unwrap();
    let mut changed = helpdesk("times");
    changed["active"] = json!(false);
    let (status, u) = put(&app, ADMIN, &format!("/report-schedules/{id}"), changed).await;
    assert_eq!(status, StatusCode::OK, "{u}");
    assert_eq!(u["active"], false);
    assert_eq!(u["helpdesk"]["table"], "times");
    let (status, _) = api(
        &app,
        ADMIN,
        Method::DELETE,
        &format!("/report-schedules/{id}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    let actions: Vec<String> = sqlx::query_scalar(
        "SELECT action FROM audit.events WHERE entity = 'report_schedule' AND user_id IS NOT NULL ORDER BY id",
    )
    .fetch_all(&db)
    .await
    .unwrap();
    assert_eq!(actions, ["created", "updated", "deleted"]);
    let (status, _) = api(
        &app,
        ADMIN,
        Method::DELETE,
        &format!("/report-schedules/{id}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

trait TapAddresses {
    fn tap_addresses(self) -> Self;
}
impl TapAddresses for Value {
    fn tap_addresses(mut self) -> Self {
        self["addresses"] = json!([]);
        self
    }
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn schedules_of_another_company_are_invisible_and_only_the_owner_or_an_admin_changes_one(
    db: PgPool,
) {
    let app = setup(db.clone()).await;
    // The manager owns a schedule; the admin may change it, a second manager may not.
    let (status, mine) = post(
        &app,
        "manager@example.com",
        "/report-schedules",
        helpdesk("volume"),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{mine}");
    let id = mine["id"].as_str().unwrap();
    sqlx::query("INSERT INTO core.users (id, email, display_name) VALUES (gen_random_uuid(), 'manager2@example.com', 'Manager Two')")
        .execute(&db)
        .await
        .unwrap();
    sqlx::query("INSERT INTO core.user_companies (user_id, company_id, roles, is_default) SELECT id, '00000000-0000-7000-8000-000000000001', '{sales_manager}', true FROM core.users WHERE email = 'manager2@example.com'")
        .execute(&db)
        .await
        .unwrap();
    let (status, _) = put(
        &app,
        "manager2@example.com",
        &format!("/report-schedules/{id}"),
        helpdesk("times"),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, _) = post(
        &app,
        "manager2@example.com",
        &format!("/report-schedules/{id}/send"),
        json!({}),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, _) = put(
        &app,
        ADMIN,
        &format!("/report-schedules/{id}"),
        helpdesk("times"),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    // Another company sees none of them and cannot reach them by id.
    sqlx::query("INSERT INTO core.companies (id, name) VALUES ('00000000-0000-7000-8000-0000000000b1', 'Other BV')")
        .execute(&db)
        .await
        .unwrap();
    sqlx::query("INSERT INTO core.users (id, email, display_name) VALUES (gen_random_uuid(), 'other@example.com', 'Other Admin')")
        .execute(&db)
        .await
        .unwrap();
    sqlx::query("INSERT INTO core.user_companies (user_id, company_id, roles, is_default) SELECT id, '00000000-0000-7000-8000-0000000000b1', '{admin}', true FROM core.users WHERE email = 'other@example.com'")
        .execute(&db)
        .await
        .unwrap();
    let (status, list) = api(
        &app,
        "other@example.com",
        Method::GET,
        "/report-schedules",
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(list, json!([]));
    let (status, _) = api(
        &app,
        "other@example.com",
        Method::DELETE,
        &format!("/report-schedules/{id}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_owner_can_pause_a_schedule_whose_recipient_left(db: PgPool) {
    let app = setup(db.clone()).await;
    let mut body = helpdesk("volume");
    body["user_ids"] = json!([SUPPORT_ID]);
    let s = schedule(&app, body.clone()).await;
    let id = s["id"].as_str().unwrap().to_string();
    sqlx::query("UPDATE core.user_companies SET active = false WHERE user_id = $1::uuid")
        .bind(SUPPORT_ID)
        .execute(&db)
        .await
        .unwrap();
    // A full edit is still validated.
    let (status, _) = put(
        &app,
        ADMIN,
        &format!("/report-schedules/{id}"),
        body.clone(),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    body["active"] = json!(false);
    let (status, r) = put(&app, ADMIN, &format!("/report-schedules/{id}"), body).await;
    assert_eq!(status, StatusCode::OK, "{r}");
    assert_eq!(r["active"], false);
    assert_eq!(r["user_ids"], s["user_ids"]);
}
