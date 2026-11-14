//! What the worker does for imports on each pass (ADR 0064 section 6): put the jobs of dead workers
//! back, run the queued jobs, remove old uploads. [`run_pending`] is the one entry point.

use std::time::Duration;

use sqlx::PgPool;
use tradocraft_core::import::Limits;
use tradocraft_core::AppResult;

use crate::run::{claim_next, run_claimed};

/// A running job whose heartbeat is older than this has lost its worker.
pub const STALE_AFTER: Duration = Duration::from_secs(5 * 60);
/// A job is claimed at most this many times; the next stale one fails.
pub const MAX_ATTEMPTS: i32 = 3;
/// An uploaded file is kept this many days (unless a queued or running job still needs it).
pub const FILE_KEEP_DAYS: i32 = 7;
/// Most jobs one pass runs, so the clean-up and the reclaiming of the next pass are never starved
/// by a long queue; the rest waits for the next pass.
pub const MAX_JOBS_PER_PASS: usize = 10;

const STOPPED_THREE_TIMES: &str = "the import stopped three times without finishing";
const INLINE_INTERRUPTED: &str =
    "the import was interrupted before it finished; check the data and run it again";

/// What one pass did.
#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct PassReport {
    /// Stale running jobs put back in the queue.
    pub requeued: u64,
    /// Stale running jobs that had used all their attempts and now are failed.
    pub abandoned: u64,
    /// Jobs claimed and run to an outcome.
    pub ran: usize,
    /// Old uploads removed.
    pub files_removed: u64,
}

/// Reclaims stale jobs, runs the queued ones and removes old files, in that order. A step that
/// fails is logged and does not stop the next. Safe with several workers: every step is one atomic
/// statement or a claim with `SKIP LOCKED`.
pub async fn run_pending(pool: &PgPool) -> PassReport {
    let mut report = PassReport::default();
    match reclaim_stale(pool).await {
        Ok((requeued, abandoned)) => {
            report.requeued = requeued;
            report.abandoned = abandoned;
        }
        Err(e) => tracing::error!(error = ?e, "reclaiming stale import jobs failed"),
    }
    report.ran = run_queued(pool, MAX_JOBS_PER_PASS).await;
    match remove_old_files(pool).await {
        Ok(n) => report.files_removed = n,
        Err(e) => tracing::error!(error = ?e, "removing old import files failed"),
    }
    report
}

/// Puts running jobs with a stale heartbeat back in the queue, or fails them after
/// [`MAX_ATTEMPTS`] attempts (the count is made at the claim). A job that was run inside a
/// request (`inline`) is always failed: nobody is waiting for it any more and it must not be
/// applied unattended later. The claim token is cleared, so the run that went quiet cannot write
/// to the job again. Returns (requeued, failed).
pub async fn reclaim_stale(pool: &PgPool) -> AppResult<(u64, u64)> {
    let secs = STALE_AFTER.as_secs_f64();
    let requeued = sqlx::query(
        "UPDATE core.import_jobs
         SET status = 'queued', phase = NULL, started_at = NULL, heartbeat_at = NULL,
             processed_rows = 0, claim_token = NULL
         WHERE status = 'running' AND attempts < $1 AND NOT inline
           AND coalesce(heartbeat_at, started_at, created_at) < now() - make_interval(secs => $2)",
    )
    .bind(MAX_ATTEMPTS)
    .bind(secs)
    .execute(pool)
    .await?
    .rows_affected();
    let abandoned = sqlx::query(
        "UPDATE core.import_jobs
         SET status = 'failed', phase = NULL, finished_at = now(), heartbeat_at = now(),
             claim_token = NULL,
             message = CASE WHEN inline THEN $4 ELSE $3 END
         WHERE status = 'running' AND (attempts >= $1 OR inline)
           AND coalesce(heartbeat_at, started_at, created_at) < now() - make_interval(secs => $2)",
    )
    .bind(MAX_ATTEMPTS)
    .bind(secs)
    .bind(STOPPED_THREE_TIMES)
    .bind(INLINE_INTERRUPTED)
    .execute(pool)
    .await?
    .rows_affected();
    if requeued + abandoned > 0 {
        tracing::warn!(requeued, abandoned, "stale import jobs reclaimed");
    }
    Ok((requeued, abandoned))
}

/// Runs queued jobs one after the other, at most `max`. Each job runs in a task of its own, so a
/// panic ends that job's run (it stays `running`, its heartbeat stops, and [`reclaim_stale`] takes
/// it) and not the worker. Returns how many jobs were run.
async fn run_queued(pool: &PgPool, max: usize) -> usize {
    let mut ran = 0;
    while ran < max {
        let job = match claim_next(pool).await {
            Ok(Some(job)) => job,
            Ok(None) => break,
            Err(e) => {
                tracing::error!(error = ?e, "claiming an import job failed");
                break;
            }
        };
        ran += 1;
        let id = job.id;
        let task_pool = pool.clone();
        let outcome =
            tokio::spawn(async move { run_claimed(&task_pool, &job, &Limits::job()).await }).await;
        match outcome {
            Ok(Ok(())) => tracing::info!(job = %id, "import job finished"),
            Ok(Err(e)) => {
                tracing::error!(job = %id, error = ?e, "running an import job failed; it is queued again once its heartbeat is stale")
            }
            Err(e) => {
                tracing::error!(job = %id, error = ?e, "an import job panicked; it is queued again once its heartbeat is stale")
            }
        }
    }
    ran
}

/// Deletes uploads older than [`FILE_KEEP_DAYS`] days, except those a queued or running job still
/// reads: a job that waited for a worker never loses its file. A job of an old file that was
/// removed keeps its row (`file_id` becomes null).
pub async fn remove_old_files(pool: &PgPool) -> AppResult<u64> {
    let n = sqlx::query(
        "DELETE FROM core.import_files f
         WHERE f.created_at < now() - make_interval(days => $1)
           AND NOT EXISTS (SELECT 1 FROM core.import_jobs j
                           WHERE j.file_id = f.id AND j.status IN ('queued', 'running'))",
    )
    .bind(FILE_KEEP_DAYS)
    .execute(pool)
    .await?
    .rows_affected();
    if n > 0 {
        tracing::info!(files = n, "old import files removed");
    }
    Ok(n)
}
