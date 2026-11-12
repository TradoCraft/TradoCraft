//! Worker heartbeat: `GET /api/v1/admin/worker` and the "worker was down" mail (ADR 0052).

mod common;

use axum::http::{Method, StatusCode};
use chrono::Utc;
use common::{call, setup};
use sqlx::PgPool;
use tradocraft_core::worker::{beat, WorkerInfo};

const ADMIN: &str = "admin@example.com";
const URI: &str = "/api/v1/admin/worker";

fn info() -> WorkerInfo {
    WorkerInfo {
        started_at: Utc::now(),
        interval_seconds: 30,
        version: "1.2.3".into(),
        host: "worker-1".into(),
    }
}

/// Moves the last beat `minutes` into the past, as if the worker stopped then.
async fn stop_for(db: &PgPool, minutes: i32) {
    sqlx::query(
        "UPDATE core.worker_heartbeat SET last_beat_at = now() - make_interval(mins => $1)",
    )
    .bind(minutes)
    .execute(db)
    .await
    .unwrap();
}

// Sort by byte order ("C"), not by the database's collation: under en_US (the postgres Docker
// image's default) punctuation is ignored, so "admin@example.com" sorts before
// "admin.nl@example.com", and the other way round under "C".
async fn outage_mails(db: &PgPool) -> Vec<(String, String)> {
    sqlx::query_as(
        "SELECT to_address, body FROM core.mail_outbox
         WHERE subject = 'The background worker was down' ORDER BY to_address COLLATE \"C\"",
    )
    .fetch_all(db)
    .await
    .unwrap()
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn only_administrators_see_the_worker(db: PgPool) {
    let app = setup(db).await;
    for user in ["sales@example.com", "viewer@example.com"] {
        let (status, _) = call(&app, user, Method::GET, URI, None).await;
        assert_eq!(status, StatusCode::FORBIDDEN, "{user}");
    }
    let (status, body) = call(&app, ADMIN, Method::GET, URI, None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["state"], "never_seen");
    assert!(body["last_beat_at"].is_null());
    assert!(body["last_outage"].is_null());
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_recent_beat_is_running_an_old_one_is_down(db: PgPool) {
    let app = setup(db.clone()).await;
    assert_eq!(beat(&db, &info()).await.unwrap(), None);
    let (_, body) = call(&app, ADMIN, Method::GET, URI, None).await;
    assert_eq!(body["state"], "running");
    assert_eq!(body["interval_seconds"], 30);
    assert_eq!(body["late_after_seconds"], 150);
    assert_eq!(body["version"], "1.2.3");
    assert_eq!(body["host"], "worker-1");
    assert!(body["age_seconds"].as_i64().unwrap() < 10);

    // Just within the threshold (2.5 minutes for a 30-second interval) is still running.
    stop_for(&db, 2).await;
    let (_, body) = call(&app, ADMIN, Method::GET, URI, None).await;
    assert_eq!(body["state"], "running");

    stop_for(&db, 3).await;
    let (_, body) = call(&app, ADMIN, Method::GET, URI, None).await;
    assert_eq!(body["state"], "down");
    assert!(body["age_seconds"].as_i64().unwrap() >= 180);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn coming_back_after_a_gap_records_it_and_mails_the_administrators(db: PgPool) {
    let app = setup(db.clone()).await;
    // A user's own language wins over the company's; an inactive admin gets nothing.
    sqlx::raw_sql(
        "INSERT INTO core.users (id, email, display_name, language, active) VALUES
             ('00000000-0000-7000-8000-00000000f001', 'admin.nl@example.com', 'NL admin', 'nl', true),
             ('00000000-0000-7000-8000-00000000f002', 'gone@example.com', 'Former admin', NULL, false);
         INSERT INTO core.user_companies (user_id, company_id, roles, is_default) VALUES
             ('00000000-0000-7000-8000-00000000f001', '00000000-0000-7000-8000-000000000001', '{admin}', true),
             ('00000000-0000-7000-8000-00000000f002', '00000000-0000-7000-8000-000000000001', '{admin}', true);",
    )
    .execute(&db)
    .await
    .unwrap();
    sqlx::query("UPDATE core.companies SET default_language = 'en'")
        .execute(&db)
        .await
        .unwrap();

    beat(&db, &info()).await.unwrap();
    // A short restart is not an outage.
    stop_for(&db, 1).await;
    assert_eq!(beat(&db, &info()).await.unwrap(), None);

    stop_for(&db, 45).await;
    let outage = beat(&db, &info()).await.unwrap().expect("an outage");
    let minutes = (outage.down_until - outage.down_from).num_minutes();
    assert_eq!(minutes, 45);

    let mails: Vec<(String, String)> = sqlx::query_as(
        "SELECT to_address, subject FROM core.mail_outbox
         WHERE subject IN ('The background worker was down', 'De achtergrondverwerking lag stil')
         ORDER BY to_address COLLATE \"C\"",
    )
    .fetch_all(&db)
    .await
    .unwrap();
    assert_eq!(
        mails,
        vec![
            (
                "admin.nl@example.com".to_string(),
                "De achtergrondverwerking lag stil".to_string()
            ),
            (
                ADMIN.to_string(),
                "The background worker was down".to_string()
            ),
        ]
    );
    let english = outage_mails(&db).await;
    assert!(
        english[0].1.contains("about 45 minutes"),
        "{}",
        english[0].1
    );

    // The next beat is on time: no second mail.
    assert_eq!(beat(&db, &info()).await.unwrap(), None);
    assert_eq!(outage_mails(&db).await.len(), 1);

    let (_, body) = call(&app, ADMIN, Method::GET, URI, None).await;
    assert_eq!(body["state"], "running");
    assert!(body["last_outage"]["down_from"].is_string());
    assert!(body["last_outage"]["down_until"].is_string());
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn two_workers_coming_back_at_once_count_the_gap_once(db: PgPool) {
    beat(&db, &info()).await.unwrap();
    stop_for(&db, 30).await;
    let (one, two) = (info(), info());
    let (a, b) = tokio::join!(beat(&db, &one), beat(&db, &two));
    let outages = [a.unwrap(), b.unwrap()]
        .into_iter()
        .filter(Option::is_some)
        .count();
    assert_eq!(outages, 1);
    let rows: i64 = sqlx::query_scalar("SELECT count(*) FROM core.worker_outages")
        .fetch_one(&db)
        .await
        .unwrap();
    assert_eq!(rows, 1);
}
