//! Running an import job (ADR 0064 section 6). One function does the work for both callers: the
//! HTTP handler runs a small job inline, the worker runs a queued one. A job row is in `running`
//! when it gets here and leaves as `done` or `failed`.
//!
//! What a worker does:
//!
//! 1. [`claim_next`] a queued job (or any claim of its own that sets `status = 'running'`),
//! 2. [`run_claimed`] it: builds the requester as [`CurrentUser::for_member`] and calls
//!    [`run_job`] with the limits of a background job.
//!
//! A run with errors in the file is `done` with the errors listed and nothing written; `failed`
//! is only for a run that could not be carried out.

use std::time::Duration;

use serde::{Deserialize, Serialize};
use sqlx::PgPool;
use tokio::sync::watch;
use tokio::task::JoinHandle;
use tradocraft_core::csv_io::{ImportReport, RowError};
use tradocraft_core::import::{
    exceeds_limits, read_raw, read_table, Limits, Phase, Progress, RunOptions,
};
use tradocraft_core::{AppError, AppResult, CurrentUser, Permission};
use utoipa::ToSchema;
use uuid::Uuid;

use crate::mapping::{self, ColumnPair};
use crate::registry;

/// Most errors a job keeps; `error_count` holds the full number.
pub const MAX_STORED_ERRORS: usize = 10_000;

/// The least time between two progress writes.
const PROGRESS_THROTTLE: Duration = Duration::from_millis(500);
/// How often a running job proves it is alive even when no rows are reported.
const HEARTBEAT_EVERY: Duration = Duration::from_secs(30);

const FILE_GONE: &str = "the uploaded file is no longer available";

/// One problem of an import, as stored with the job and shown to the person.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
pub struct StoredError {
    /// Line (CSV) or sheet row where the problem is; the header is at its own row.
    pub row: usize,
    /// The column the problem concerns; null for the row as a whole.
    pub column: Option<String>,
    pub message: String,
}

impl From<&RowError> for StoredError {
    fn from(e: &RowError) -> Self {
        StoredError {
            row: e.row,
            column: e.column.clone(),
            message: e.message.clone(),
        }
    }
}

/// The errors to store (at most `max`) and the full number of errors.
pub fn cap_errors(errors: &[RowError], max: usize) -> (usize, Vec<StoredError>) {
    (
        errors.len(),
        errors.iter().take(max).map(StoredError::from).collect(),
    )
}

/// A job a worker has claimed.
#[derive(Debug, Clone, sqlx::FromRow)]
pub struct ClaimedJob {
    pub id: Uuid,
    pub company_id: Uuid,
    pub requested_by: Option<Uuid>,
}

/// Takes the oldest queued job and marks it running (`FOR UPDATE SKIP LOCKED`, so several workers
/// never take the same one). Counts the attempt.
pub async fn claim_next(pool: &PgPool) -> AppResult<Option<ClaimedJob>> {
    Ok(sqlx::query_as(
        "UPDATE core.import_jobs
         SET status = 'running', phase = 'reading', started_at = now(), heartbeat_at = now(),
             attempts = attempts + 1, processed_rows = 0
         WHERE id = (SELECT id FROM core.import_jobs WHERE status = 'queued'
                     ORDER BY created_at LIMIT 1 FOR UPDATE SKIP LOCKED)
         RETURNING id, company_id, requested_by",
    )
    .fetch_optional(pool)
    .await?)
}

/// Runs a claimed job as its requester with the limits of a background job. A requester who is
/// gone, deactivated or no longer a member of the company fails the job.
pub async fn run_claimed(pool: &PgPool, job: &ClaimedJob, limits: &Limits) -> AppResult<()> {
    let Some(requested_by) = job.requested_by else {
        return fail_job(
            pool,
            job.id,
            "the user who started the import no longer exists",
        )
        .await;
    };
    match CurrentUser::for_member(pool, requested_by, job.company_id).await {
        Ok(user) => run_job(pool, job.id, &user, limits).await,
        Err(AppError::Forbidden(message)) => fail_job(pool, job.id, &message).await,
        // The database is unreachable: leave the job running; its heartbeat goes stale and it is
        // queued again.
        Err(e) => Err(e),
    }
}

/// What a job needs to run.
#[derive(sqlx::FromRow)]
struct JobToRun {
    entity: String,
    file_id: Option<Uuid>,
    sheet: Option<String>,
    #[sqlx(json(nullable))]
    columns: Option<Vec<ColumnPair>>,
    dry_run: bool,
    requested_by: Option<Uuid>,
}

/// Why a job could not be carried out: the text stored as its `message`.
struct Failure(String);

impl From<AppError> for Failure {
    fn from(e: AppError) -> Self {
        match e {
            AppError::Forbidden(m) => Failure(format!("not allowed: {m}")),
            AppError::Internal(e) => {
                tracing::error!(error = ?e, "import job failed");
                Failure("internal error while importing".into())
            }
            other => Failure(other.to_string()),
        }
    }
}

impl From<sqlx::Error> for Failure {
    fn from(e: sqlx::Error) -> Self {
        AppError::from(e).into()
    }
}

struct Finished {
    total_rows: usize,
    report: ImportReport,
}

/// Runs the job `job_id` (status `running`, in `user`'s company) as `user` and writes its outcome:
/// `done` with the counts or the errors, or `failed` with a message. `Err` only when the job row
/// could not be read or written at all (database trouble, no such running job, a user who is not
/// the requester); the job then stays as it is and is picked up again by the heartbeat rule.
///
/// The file is read and bound with `limits`; the permission to write the entity and `imports.admin`
/// are checked for `user` here, so a role changed since the job was queued counts.
pub async fn run_job(
    pool: &PgPool,
    job_id: Uuid,
    user: &CurrentUser,
    limits: &Limits,
) -> AppResult<()> {
    let job: JobToRun = sqlx::query_as(
        "SELECT entity, file_id, sheet, columns, dry_run, requested_by
         FROM core.import_jobs WHERE id = $1 AND company_id = $2 AND status = 'running'",
    )
    .bind(job_id)
    .bind(user.company_id)
    .fetch_optional(pool)
    .await?
    .ok_or(AppError::NotFound("running import job"))?;
    if job.requested_by.is_some_and(|r| r != user.user_id) {
        return Err(AppError::Forbidden(
            "an import job runs as the user who requested it".into(),
        ));
    }
    match execute(pool, job_id, &job, user, limits).await {
        Ok(finished) => finish_done(pool, job_id, finished).await,
        Err(Failure(message)) => fail_job(pool, job_id, &message).await,
    }
}

async fn execute(
    pool: &PgPool,
    job_id: Uuid,
    job: &JobToRun,
    user: &CurrentUser,
    limits: &Limits,
) -> Result<Finished, Failure> {
    let entity = registry::entity(&job.entity)
        .ok_or_else(|| Failure(format!("'{}' is not an importable entity", job.entity)))?;
    user.require(Permission::ImportsAdmin)?;
    user.require(entity.write_permission())?;

    sqlx::query(
        "UPDATE core.import_jobs SET phase = 'reading', heartbeat_at = now() WHERE id = $1",
    )
    .bind(job_id)
    .execute(pool)
    .await?;
    let file_id = job.file_id.ok_or_else(|| Failure(FILE_GONE.into()))?;
    let bytes: Vec<u8> =
        sqlx::query_scalar("SELECT data FROM core.import_files WHERE id = $1 AND company_id = $2")
            .bind(file_id)
            .bind(user.company_id)
            .fetch_optional(pool)
            .await?
            .ok_or_else(|| Failure(FILE_GONE.into()))?;

    // Reading is CPU work on up to 50 MiB: keep it off the async threads.
    let pairs = job.columns.as_deref().map(mapping::to_pairs);
    let sheet = job.sheet.clone();
    let limits = *limits;
    let reader = entity.clone();
    let read = tokio::task::spawn_blocking(move || {
        let known = reader.header();
        read_table(
            &bytes,
            sheet.as_deref(),
            &limits,
            &known,
            &[reader.describe().key_column.as_str()],
            pairs.as_deref(),
        )
    })
    .await
    .map_err(|e| {
        tracing::error!(error = ?e, "reading an import file panicked");
        Failure("internal error while reading the file".into())
    })?;
    // Problems of the header or the file as a whole are the result of the run, not a failure.
    let (format, table) = match read {
        Ok(read) => read,
        Err(errors) => {
            return Ok(Finished {
                total_rows: 0,
                report: ImportReport::failed(errors),
            })
        }
    };

    let total_rows = table.rows.len() + table.width_errors.len();
    sqlx::query(
        "UPDATE core.import_jobs SET phase = 'validating', total_rows = $2, processed_rows = 0,
                heartbeat_at = now() WHERE id = $1",
    )
    .bind(job_id)
    .bind(clamp(total_rows))
    .execute(pool)
    .await?;

    let (sink, writer) = progress_writer(pool.clone(), job_id);
    let options = RunOptions::new(format)
        .dry_run(job.dry_run)
        .import_job(job_id)
        .progress(&sink);
    let result = entity.run(pool, user, &table, &options).await;
    // Nothing may write the row after the outcome has been written.
    writer.abort();
    let _ = writer.await;
    Ok(Finished {
        total_rows,
        report: result?,
    })
}

fn clamp(n: usize) -> i32 {
    i32::try_from(n).unwrap_or(i32::MAX)
}

/// Hands the progress of the import, a synchronous callback inside its transaction, to a task that
/// writes it on a connection of its own. Only the latest state is kept, so the import never waits
/// and the writes are throttled; the task also keeps the heartbeat alive.
struct JobProgress {
    tx: watch::Sender<(Phase, usize)>,
}

impl Progress for JobProgress {
    fn report(&self, phase: Phase, processed: usize) {
        self.tx.send_replace((phase, processed));
    }
}

fn progress_writer(pool: PgPool, job_id: Uuid) -> (JobProgress, JoinHandle<()>) {
    let (tx, mut rx) = watch::channel((Phase::Validating, 0usize));
    let task = tokio::spawn(async move {
        let mut beat = tokio::time::interval_at(
            tokio::time::Instant::now() + HEARTBEAT_EVERY,
            HEARTBEAT_EVERY,
        );
        loop {
            tokio::select! {
                changed = rx.changed() => {
                    if changed.is_err() {
                        break;
                    }
                    let (phase, processed) = *rx.borrow_and_update();
                    let written = sqlx::query(
                        "UPDATE core.import_jobs SET phase = $2, processed_rows = $3,
                                heartbeat_at = now()
                         WHERE id = $1 AND status = 'running'",
                    )
                    .bind(job_id)
                    .bind(phase.as_str())
                    .bind(clamp(processed))
                    .execute(&pool)
                    .await;
                    if let Err(e) = written {
                        tracing::warn!(job = %job_id, error = %e, "writing import progress failed");
                    }
                    tokio::time::sleep(PROGRESS_THROTTLE).await;
                }
                _ = beat.tick() => {
                    let _ = sqlx::query(
                        "UPDATE core.import_jobs SET heartbeat_at = now()
                         WHERE id = $1 AND status = 'running'",
                    )
                    .bind(job_id)
                    .execute(&pool)
                    .await;
                }
            }
        }
    });
    (JobProgress { tx }, task)
}

async fn finish_done(pool: &PgPool, job_id: Uuid, finished: Finished) -> AppResult<()> {
    let Finished { total_rows, report } = finished;
    let (error_count, errors) = cap_errors(&report.errors, MAX_STORED_ERRORS);
    // A run with errors wrote nothing, whatever the engine counted on the way.
    let (created, updated, unchanged) = if error_count > 0 {
        (0, 0, 0)
    } else {
        (report.created, report.updated, report.unchanged)
    };
    sqlx::query(
        "UPDATE core.import_jobs
         SET status = 'done', phase = NULL, total_rows = $2, processed_rows = $2,
             created_count = $3, updated_count = $4, unchanged_count = $5,
             error_count = $6, errors = $7, message = NULL,
             finished_at = now(), heartbeat_at = now()
         WHERE id = $1 AND status = 'running'",
    )
    .bind(job_id)
    .bind(clamp(total_rows))
    .bind(clamp(created))
    .bind(clamp(updated))
    .bind(clamp(unchanged))
    .bind(clamp(error_count))
    .bind(sqlx::types::Json(errors))
    .execute(pool)
    .await?;
    Ok(())
}

/// Ends a running job as `failed` with `message`.
pub async fn fail_job(pool: &PgPool, job_id: Uuid, message: &str) -> AppResult<()> {
    sqlx::query(
        "UPDATE core.import_jobs
         SET status = 'failed', phase = NULL, message = $2, finished_at = now(), heartbeat_at = now()
         WHERE id = $1 AND status = 'running'",
    )
    .bind(job_id)
    .bind(message)
    .execute(pool)
    .await?;
    Ok(())
}

/// Whether a file can be run within one request: it is within the request limits. A file that is
/// refused for any other reason also counts, so the inline run reports that problem as the result
/// of the job instead of queueing something that can never succeed.
pub async fn fits_one_request(bytes: Vec<u8>, sheet: Option<String>) -> AppResult<bool> {
    let limits = Limits::request();
    if bytes.len() > limits.file_bytes {
        return Ok(false);
    }
    let read = tokio::task::spawn_blocking(move || {
        read_raw(&bytes, sheet.as_deref(), &limits).map(|_| ())
    })
    .await
    .map_err(|e| AppError::Internal(e.into()))?;
    Ok(match read {
        Ok(()) => true,
        Err(errors) => !exceeds_limits(&errors),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn error(row: usize) -> RowError {
        RowError {
            row,
            column: Some("code".into()),
            message: format!("problem {row}"),
            limit: false,
        }
    }

    #[test]
    fn stored_errors_are_capped_but_the_full_count_is_kept() {
        let errors: Vec<RowError> = (2..2 + MAX_STORED_ERRORS + 5).map(error).collect();
        let (count, stored) = cap_errors(&errors, MAX_STORED_ERRORS);
        assert_eq!(count, MAX_STORED_ERRORS + 5);
        assert_eq!(stored.len(), MAX_STORED_ERRORS);
        assert_eq!(stored[0].row, 2);
        assert_eq!(stored[MAX_STORED_ERRORS - 1].row, MAX_STORED_ERRORS + 1);
        let (count, stored) = cap_errors(&errors[..3], MAX_STORED_ERRORS);
        assert_eq!((count, stored.len()), (3, 3));
        assert_eq!(cap_errors(&[], MAX_STORED_ERRORS), (0, vec![]));
    }
}
