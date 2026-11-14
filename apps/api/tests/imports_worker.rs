//! What the worker does for imports (ADR 0064 section 6): reclaiming stale jobs, running the
//! queued ones, removing old files, and two workers at once.

mod common;

use common::setup;
use sqlx::PgPool;
use tradocraft_imports::{run_pending, MAX_ATTEMPTS};
use uuid::Uuid;

const ADMIN_ID: &str = "00000000-0000-7000-8000-000000000101";
const SALES_ID: &str = "00000000-0000-7000-8000-000000000102";
const COMPANY: &str = "00000000-0000-7000-8000-000000000001";

fn uuid(s: &str) -> Uuid {
    s.parse().unwrap()
}

fn csv(prefix: &str, rows: usize) -> Vec<u8> {
    let mut s = String::from("code,name,price_zone_code\n");
    for i in 0..rows {
        s.push_str(&format!("{prefix}{i},Name {i},Z1\n"));
    }
    s.into_bytes()
}

async fn file(db: &PgPool, data: Vec<u8>, age_days: i32) -> Uuid {
    let id = Uuid::now_v7();
    sqlx::query(
        "INSERT INTO core.import_files (id, company_id, filename, format, size_bytes, data,
                                        uploaded_by, created_at)
         VALUES ($1, $2, 'f.csv', 'csv', $3, $4, $5, now() - make_interval(days => $6))",
    )
    .bind(id)
    .bind(uuid(COMPANY))
    .bind(data.len() as i64)
    .bind(data)
    .bind(uuid(ADMIN_ID))
    .bind(age_days)
    .execute(db)
    .await
    .unwrap();
    id
}

async fn job(db: &PgPool, file_id: Option<Uuid>, user: &str, dry_run: bool) -> Uuid {
    let id = Uuid::now_v7();
    sqlx::query(
        "INSERT INTO core.import_jobs (id, company_id, entity, file_id, filename, format, dry_run,
                                       requested_by)
         VALUES ($1, $2, 'customers', $3, 'f.csv', 'csv', $4, $5)",
    )
    .bind(id)
    .bind(uuid(COMPANY))
    .bind(file_id)
    .bind(dry_run)
    .bind(uuid(user))
    .execute(db)
    .await
    .unwrap();
    id
}

/// Makes a job look like it is running since `minutes_ago`, on its `attempts`-th attempt.
async fn make_running(db: &PgPool, id: Uuid, attempts: i32, minutes_ago: i32) {
    sqlx::query(
        "UPDATE core.import_jobs
         SET status = 'running', phase = 'writing', attempts = $2, processed_rows = 5,
             started_at = now() - make_interval(mins => $3 + 1),
             heartbeat_at = now() - make_interval(mins => $3)
         WHERE id = $1",
    )
    .bind(id)
    .bind(attempts)
    .bind(minutes_ago)
    .execute(db)
    .await
    .unwrap();
}

async fn state(db: &PgPool, id: Uuid) -> (String, i32, Option<String>) {
    sqlx::query_as("SELECT status, attempts, message FROM core.import_jobs WHERE id = $1")
        .bind(id)
        .fetch_one(db)
        .await
        .unwrap()
}

async fn customers(db: &PgPool) -> i64 {
    sqlx::query_scalar("SELECT count(*) FROM crm.customers")
        .fetch_one(db)
        .await
        .unwrap()
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_stale_running_job_is_queued_again_and_a_fresh_one_is_left_alone(db: PgPool) {
    let _ = setup(db.clone()).await;
    let stale = job(&db, None, ADMIN_ID, false).await;
    let fresh = job(&db, None, ADMIN_ID, false).await;
    make_running(&db, stale, 1, 6).await;
    make_running(&db, fresh, 1, 1).await;

    let (requeued, abandoned) = tradocraft_imports::reclaim_stale(&db).await.unwrap();
    assert_eq!((requeued, abandoned), (1, 0));
    // The attempt is counted at the claim, so reclaiming changes nothing there.
    assert_eq!(state(&db, stale).await, ("queued".into(), 1, None));
    let (status, attempts, _) = state(&db, fresh).await;
    assert_eq!((status.as_str(), attempts), ("running", 1));
    let (started, beat): (
        Option<chrono::DateTime<chrono::Utc>>,
        Option<chrono::DateTime<chrono::Utc>>,
    ) = sqlx::query_as("SELECT started_at, heartbeat_at FROM core.import_jobs WHERE id = $1")
        .bind(stale)
        .fetch_one(&db)
        .await
        .unwrap();
    assert!(started.is_none() && beat.is_none());
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_third_stale_attempt_fails_the_job(db: PgPool) {
    let _ = setup(db.clone()).await;
    let id = job(&db, None, ADMIN_ID, false).await;
    make_running(&db, id, MAX_ATTEMPTS, 10).await;
    let report = run_pending(&db).await;
    assert_eq!((report.requeued, report.abandoned, report.ran), (0, 1, 0));
    let (status, attempts, message) = state(&db, id).await;
    assert_eq!(status, "failed");
    assert_eq!(attempts, MAX_ATTEMPTS);
    assert!(message.unwrap().contains("three times"));
    let finished: Option<chrono::DateTime<chrono::Utc>> =
        sqlx::query_scalar("SELECT finished_at FROM core.import_jobs WHERE id = $1")
            .bind(id)
            .fetch_one(&db)
            .await
            .unwrap();
    assert!(finished.is_some());
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_pass_runs_a_queued_job_to_done_with_its_counts_and_progress(db: PgPool) {
    let _ = setup(db.clone()).await;
    let f = file(&db, csv("W", 20_001), 0).await;
    let id = job(&db, Some(f), ADMIN_ID, false).await;
    let before = customers(&db).await;

    let report = run_pending(&db).await;
    assert_eq!(report.ran, 1);
    let (status, attempts, _) = state(&db, id).await;
    assert_eq!((status.as_str(), attempts), ("done", 1));
    let row: (i32, i32, Option<String>, i32, i32, i32) = sqlx::query_as(
        "SELECT total_rows, processed_rows, phase, created_count, updated_count, unchanged_count
         FROM core.import_jobs WHERE id = $1",
    )
    .bind(id)
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(row, (20_001, 20_001, None, 20_001, 0, 0));
    assert_eq!(customers(&db).await, before + 20_001);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_queued_dry_run_writes_nothing(db: PgPool) {
    let _ = setup(db.clone()).await;
    let f = file(&db, csv("D", 50), 0).await;
    let id = job(&db, Some(f), ADMIN_ID, true).await;
    let before = customers(&db).await;
    run_pending(&db).await;
    assert_eq!(state(&db, id).await.0, "done");
    let created: i32 =
        sqlx::query_scalar("SELECT created_count FROM core.import_jobs WHERE id = $1")
            .bind(id)
            .fetch_one(&db)
            .await
            .unwrap();
    assert_eq!(created, 50);
    assert_eq!(customers(&db).await, before);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_job_of_a_requester_without_imports_admin_fails(db: PgPool) {
    let _ = setup(db.clone()).await;
    let f = file(&db, csv("L", 3), 0).await;
    let id = job(&db, Some(f), SALES_ID, false).await;
    let before = customers(&db).await;
    run_pending(&db).await;
    let (status, _, message) = state(&db, id).await;
    assert_eq!(status, "failed");
    assert!(message.unwrap().contains("imports.admin"));
    assert_eq!(customers(&db).await, before);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_job_cancelled_while_queued_is_never_claimed(db: PgPool) {
    let _ = setup(db.clone()).await;
    let f = file(&db, csv("C", 3), 0).await;
    let id = job(&db, Some(f), ADMIN_ID, false).await;
    sqlx::query("UPDATE core.import_jobs SET status = 'cancelled' WHERE id = $1")
        .bind(id)
        .execute(&db)
        .await
        .unwrap();
    let before = customers(&db).await;
    assert!(tradocraft_imports::claim_next(&db).await.unwrap().is_none());
    let report = run_pending(&db).await;
    assert_eq!(report.ran, 0);
    assert_eq!(state(&db, id).await, ("cancelled".into(), 0, None));
    assert_eq!(customers(&db).await, before);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn old_files_are_removed_unless_a_queued_or_running_job_needs_them(db: PgPool) {
    let _ = setup(db.clone()).await;
    let old_done = file(&db, csv("O", 1), 8).await;
    let old_free = file(&db, csv("P", 1), 8).await;
    let old_queued = file(&db, csv("Q", 1), 30).await;
    let old_running = file(&db, csv("R", 1), 30).await;
    let young = file(&db, csv("Y", 1), 6).await;
    let done_job = job(&db, Some(old_done), ADMIN_ID, true).await;
    sqlx::query("UPDATE core.import_jobs SET status = 'done' WHERE id = $1")
        .bind(done_job)
        .execute(&db)
        .await
        .unwrap();
    let running_job = job(&db, Some(old_running), ADMIN_ID, true).await;
    make_running(&db, running_job, 1, 1).await;
    let queued_job = job(&db, Some(old_queued), ADMIN_ID, true).await;

    let removed = tradocraft_imports::remove_old_files(&db).await.unwrap();
    assert_eq!(removed, 2);
    let left: Vec<Uuid> = sqlx::query_scalar("SELECT id FROM core.import_files")
        .fetch_all(&db)
        .await
        .unwrap();
    assert!(!left.contains(&old_done) && !left.contains(&old_free));
    assert!(left.contains(&old_queued) && left.contains(&old_running) && left.contains(&young));
    // The history of the job whose file went stays.
    let kept: Option<Uuid> =
        sqlx::query_scalar("SELECT file_id FROM core.import_jobs WHERE id = $1")
            .bind(done_job)
            .fetch_one(&db)
            .await
            .unwrap();
    assert_eq!(kept, None);

    // A pass runs the old queued job before it cleans up; afterwards its file may go.
    let report = run_pending(&db).await;
    assert_eq!(report.ran, 1);
    assert_eq!(state(&db, queued_job).await.0, "done");
    assert_eq!(report.files_removed, 1, "the finished job's old file goes");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn two_workers_run_each_queued_job_exactly_once(db: PgPool) {
    let _ = setup(db.clone()).await;
    let mut ids = Vec::new();
    for i in 0..6 {
        let f = file(&db, csv(&format!("T{i}_"), 200), 0).await;
        ids.push(job(&db, Some(f), ADMIN_ID, false).await);
    }
    let (a, b) = tokio::join!(run_pending(&db), run_pending(&db));
    assert_eq!(a.ran + b.ran, 6);
    for id in ids {
        assert_eq!(state(&db, id).await.0, "done");
        assert_eq!(state(&db, id).await.1, 1);
    }
    assert_eq!(customers(&db).await, 6 * 200 + seeded(&db).await);
}

/// Customers that were not created by the jobs.
async fn seeded(db: &PgPool) -> i64 {
    sqlx::query_scalar("SELECT count(*) FROM crm.customers WHERE code !~ '^T[0-9]_'")
        .fetch_one(db)
        .await
        .unwrap()
}

async fn set_inline(db: &PgPool, id: Uuid) {
    sqlx::query(
        "UPDATE core.import_jobs SET inline = true, claim_token = gen_random_uuid() WHERE id = $1",
    )
    .bind(id)
    .execute(db)
    .await
    .unwrap();
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_stale_inline_job_is_failed_and_never_run_unattended(db: PgPool) {
    let _ = setup(db.clone()).await;
    let f = file(&db, csv("I", 5), 0).await;
    let id = job(&db, Some(f), ADMIN_ID, false).await;
    make_running(&db, id, 1, 6).await;
    set_inline(&db, id).await;
    let before = customers(&db).await;

    let report = run_pending(&db).await;
    assert_eq!((report.requeued, report.abandoned, report.ran), (0, 1, 0));
    let (status, attempts, message) = state(&db, id).await;
    assert_eq!((status.as_str(), attempts), ("failed", 1));
    assert!(message.unwrap().contains("interrupted"));
    assert_eq!(customers(&db).await, before);
    // A second pass does not pick it up either.
    assert_eq!(run_pending(&db).await.ran, 0);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_run_that_lost_its_claim_cannot_write_the_job(db: PgPool) {
    let _ = setup(db.clone()).await;
    let f = file(&db, csv("K", 5), 0).await;
    let id = job(&db, Some(f), ADMIN_ID, false).await;
    let first = tradocraft_imports::claim_next(&db).await.unwrap().unwrap();
    assert_eq!(first.id, id);
    // It goes quiet, is reclaimed and claimed again by another worker.
    sqlx::query(
        "UPDATE core.import_jobs SET heartbeat_at = now() - interval '10 minutes' WHERE id = $1",
    )
    .bind(id)
    .execute(&db)
    .await
    .unwrap();
    assert_eq!(
        tradocraft_imports::reclaim_stale(&db).await.unwrap(),
        (1, 0)
    );
    let second = tradocraft_imports::claim_next(&db).await.unwrap().unwrap();
    assert_ne!(first.claim, second.claim);

    // The first run wakes up: it neither fails the job, nor runs it, nor stores an outcome.
    tradocraft_imports::fail_job(&db, id, first.claim, "late")
        .await
        .unwrap();
    let before = customers(&db).await;
    let late =
        tradocraft_imports::run_claimed(&db, &first, &tradocraft_core::import::Limits::job()).await;
    assert!(
        late.is_err(),
        "a run under an old claim finds no running job"
    );
    assert_eq!(customers(&db).await, before);
    assert_eq!(state(&db, id).await.0, "running");

    // The second one finishes normally.
    tradocraft_imports::run_claimed(&db, &second, &tradocraft_core::import::Limits::job())
        .await
        .unwrap();
    assert_eq!(state(&db, id).await.0, "done");
    assert_eq!(customers(&db).await, before + 5);
}
