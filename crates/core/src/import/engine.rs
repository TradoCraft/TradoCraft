//! The shared import and export engine (ADR 0067 section 1). An entity supplies an
//! [`Importable`]; everything else lives here.
//!
//! [`run_import`] is callable outside an HTTP handler (a background job calls it): it takes the
//! pool, the user to run as and the bound table, and returns the [`ImportReport`] as a value.

use std::collections::HashMap;

use axum::http::{HeaderMap, StatusCode};
use axum::Json;
use serde::Deserialize;
use sqlx::{PgConnection, PgPool};
use utoipa::{IntoParams, ToSchema};
use uuid::Uuid;

use crate::auth::CurrentUser;
use crate::csv_io::{self, ImportParams, ImportReport, RowError};
use crate::error::{AppError, AppResult};
use crate::import::importable::{Importable, NoProgress, Phase, Progress};
use crate::import::{download, read_table, write, CellValue, Cells, Format, Limits, Table};
use crate::{audit, new_id};

/// How often (in rows) the progress sink is told how far an import is.
pub const PROGRESS_EVERY: usize = 500;

/// How one run of the engine is carried out.
pub struct RunOptions<'a> {
    /// The format of the file; it only decides `data.source` of the audit events.
    pub format: Format,
    /// Validate and count only; nothing is written.
    pub dry_run: bool,
    /// The import job this run belongs to; added to every audit event as `data.import_job`.
    pub import_job: Option<Uuid>,
    /// The claim (`core.import_jobs.claim_token`) the run of `import_job` was started under. When
    /// set, the run checks before it writes and before it commits that the job is still running
    /// under this claim; a run that was reclaimed meanwhile stops and writes nothing.
    pub claim: Option<Uuid>,
    /// Told how far the run is (see [`Progress`]).
    pub progress: &'a dyn Progress,
}

impl RunOptions<'static> {
    /// A run of a file of `format` that writes, belongs to no job and reports no progress.
    pub fn new(format: Format) -> Self {
        RunOptions {
            format,
            dry_run: false,
            import_job: None,
            claim: None,
            progress: &NoProgress,
        }
    }
}

impl<'a> RunOptions<'a> {
    pub fn dry_run(mut self, dry_run: bool) -> Self {
        self.dry_run = dry_run;
        self
    }

    pub fn import_job(mut self, job: Uuid) -> Self {
        self.import_job = Some(job);
        self
    }

    pub fn claim(mut self, claim: Uuid) -> Self {
        self.claim = Some(claim);
        self
    }

    pub fn progress<'b>(self, progress: &'b dyn Progress) -> RunOptions<'b> {
        RunOptions {
            format: self.format,
            dry_run: self.dry_run,
            import_job: self.import_job,
            claim: self.claim,
            progress,
        }
    }
}

/// Tells the sink after every [`PROGRESS_EVERY`] rows and when the phase is complete.
fn tick(progress: &dyn Progress, phase: Phase, done: usize, total: usize) {
    if done == total || done.is_multiple_of(PROGRESS_EVERY) {
        progress.report(phase, done);
    }
}

/// What an import does with one valid row.
enum Action<E: Importable> {
    Create { key: String, change: E::Change },
    Update { id: Uuid, change: E::Change },
}

/// The outcome of checking a whole file: what to write and what was found wrong.
struct Plan<E: Importable> {
    actions: Vec<Action<E>>,
    unchanged: usize,
    errors: Vec<RowError>,
    /// Planning stopped at [`csv_io::MAX_REPORTED_ERRORS`] errors; later rows were not checked.
    stopped: bool,
}

/// Checks every row against the database and decides what each one would do.
async fn plan<E: Importable>(
    conn: &mut PgConnection,
    user: &CurrentUser,
    table: &Table,
    progress: &dyn Progress,
) -> AppResult<Plan<E>> {
    let keys: Vec<String> = table
        .rows
        .iter()
        .filter_map(|r| r.get_trimmed(E::KEY_COLUMN))
        .map(str::to_string)
        .collect();
    let stored: HashMap<String, E::Stored> =
        E::load(conn, user, &keys).await?.into_iter().collect();
    let mut context = E::context(conn, user, table).await?;

    let mut plan = Plan {
        actions: Vec::new(),
        unchanged: 0,
        errors: Vec::new(),
        stopped: false,
    };
    let mut seen: HashMap<String, usize> = HashMap::new();
    let total = table.rows.len();
    for (n, row) in table.rows.iter().enumerate() {
        plan_one::<E>(conn, user, &mut context, &stored, &mut seen, row, &mut plan).await?;
        tick(progress, Phase::Validating, n + 1, total);
        // A file this wrong is refused whatever else is in it; do not keep collecting.
        if plan.errors.len() + table.width_errors.len() >= csv_io::MAX_REPORTED_ERRORS
            && n + 1 < total
        {
            plan.stopped = true;
            break;
        }
    }
    Ok(plan)
}

/// The shared part of one row: the key is present and unique, the rest is the entity's.
async fn plan_one<E: Importable>(
    conn: &mut PgConnection,
    user: &CurrentUser,
    context: &mut E::Context,
    stored: &HashMap<String, E::Stored>,
    seen: &mut HashMap<String, usize>,
    row: &crate::import::Row,
    plan: &mut Plan<E>,
) -> AppResult<()> {
    let mut cells = Cells::new(row, &mut plan.errors);
    let before = cells.error_count();
    let Some(key) = cells.trimmed(E::KEY_COLUMN).value() else {
        cells.error(
            Some(E::KEY_COLUMN),
            format!("{} is required", E::KEY_COLUMN),
        );
        return Ok(());
    };
    if let Some(first) = seen.insert(key.clone(), row.line) {
        cells.error(
            Some(E::KEY_COLUMN),
            format!(
                "{} {key} appears twice (first on line {first})",
                E::KEY_COLUMN
            ),
        );
        return Ok(());
    }
    let current = stored.get(&key);
    let change = E::plan_row(conn, user, context, &key, current, row, &mut cells).await?;
    if cells.error_count() > before {
        return Ok(());
    }
    match current {
        Some(c) if E::unchanged(c, &change) => plan.unchanged += 1,
        Some(c) => plan.actions.push(Action::Update {
            id: E::stored_id(c),
            change,
        }),
        None => plan.actions.push(Action::Create { key, change }),
    }
    Ok(())
}

/// The `data` of an audit event: `extra` fields, the source of the file and the job, if any.
fn audit_data(options: &RunOptions<'_>, extra: Option<(&str, &str)>) -> serde_json::Value {
    let mut data = serde_json::Map::new();
    if let Some((k, v)) = extra {
        data.insert(k.to_string(), v.into());
    }
    data.insert("source".into(), options.format.audit_source().into());
    if let Some(job) = options.import_job {
        data.insert("import_job".into(), job.to_string().into());
    }
    data.into()
}

/// Fails when the run belongs to a job that is no longer running under its claim.
async fn still_claimed(conn: &mut PgConnection, options: &RunOptions<'_>) -> AppResult<()> {
    let (Some(job), Some(claim)) = (options.import_job, options.claim) else {
        return Ok(());
    };
    let held: bool = sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM core.import_jobs
                        WHERE id = $1 AND status = 'running' AND claim_token = $2)",
    )
    .bind(job)
    .bind(claim)
    .fetch_one(conn)
    .await?;
    if held {
        Ok(())
    } else {
        Err(AppError::ConflictCode(
            "import_claim_lost",
            "the import was taken over by another run; nothing was written".into(),
        ))
    }
}

/// One attempt: plan in a transaction and, when the plan is clean and this is no dry run, write
/// it. A unique-key conflict at write time (a concurrent creation of the same key or barcode)
/// fails the attempt; [`csv_io::with_replan`] then plans again against the committed data.
async fn attempt<E: Importable>(
    pool: &PgPool,
    user: &CurrentUser,
    table: &Table,
    options: &RunOptions<'_>,
) -> AppResult<ImportReport> {
    let mut tx = pool.begin().await?;
    let plan = plan::<E>(&mut tx, user, table, options.progress).await?;
    let more = plan.stopped || table.errors_truncated;
    let mut report = ImportReport::planned(plan.unchanged, &table.width_errors, plan.errors, more);
    for a in &plan.actions {
        match a {
            Action::Create { .. } => report.created += 1,
            Action::Update { .. } => report.updated += 1,
        }
    }
    if !report.errors.is_empty() || options.dry_run {
        return Ok(report);
    }
    still_claimed(&mut tx, options).await?;
    let total = plan.actions.len();
    for (n, a) in plan.actions.into_iter().enumerate() {
        match a {
            Action::Create { key, change } => {
                let id = new_id();
                E::create(&mut tx, user, id, &change).await?;
                let data = audit_data(options, Some((E::KEY_COLUMN, &key)));
                audit::record(&mut tx, user, E::AUDIT_ENTITY, id, "created", data).await?;
            }
            Action::Update { id, change } => {
                E::update(&mut tx, user, id, &change).await?;
                let data = audit_data(options, None);
                audit::record(&mut tx, user, E::AUDIT_ENTITY, id, "updated", data).await?;
            }
        }
        tick(options.progress, Phase::Writing, n + 1, total);
    }
    still_claimed(&mut tx, options).await?;
    tx.commit().await?;
    Ok(report)
}

/// Runs an import of the bound `table` as `user`: checks every row, and unless there are errors or
/// `options.dry_run`, writes everything in one transaction with one audit event per created or
/// updated record. A concurrent unique-key conflict makes it plan again, at most
/// [`csv_io::MAX_PLAN_ATTEMPTS`] times. The report holds the counts, or the errors with nothing
/// written; turning it into a response is up to the caller ([`ImportReport::into_response`]).
///
/// The permission is the caller's to check (the HTTP helper [`import_request`] and a job do).
pub async fn run_import<E: Importable>(
    pool: &PgPool,
    user: &CurrentUser,
    table: &Table,
    options: &RunOptions<'_>,
) -> AppResult<ImportReport> {
    csv_io::with_replan(|| attempt::<E>(pool, user, table, options)).await
}

/// The names of the columns of an entity, in export order.
pub fn column_names<E: Importable>() -> Vec<&'static str> {
    E::COLUMNS.iter().map(|c| c.name).collect()
}

/// The HTTP side of an import: checks the write permission, reads `body` (any of the three
/// formats, detected from the bytes) with the limits of one request, runs the import and returns
/// the report.
pub async fn import_request<E: Importable>(
    pool: &PgPool,
    user: &CurrentUser,
    params: &ImportParams,
    body: &[u8],
) -> AppResult<(StatusCode, Json<ImportReport>)> {
    user.require(E::WRITE)?;
    let (bytes, sheet) = (body.to_vec(), params.sheet.clone());
    // Parsing is CPU work on up to a request's worth of file: keep it off the async threads.
    let read = tokio::task::spawn_blocking(move || {
        read_table(
            &bytes,
            sheet.as_deref(),
            &Limits::request(),
            &column_names::<E>(),
            &[E::KEY_COLUMN],
            None,
        )
    })
    .await
    .map_err(|e| AppError::Internal(e.into()))?;
    let (format, table) = match read {
        Ok(read) => read,
        Err(errors) => return Ok(ImportReport::failed(errors).into_response()),
    };
    let options = RunOptions::new(format).dry_run(params.dry_run);
    Ok(run_import::<E>(pool, user, &table, &options)
        .await?
        .into_response())
}

/// The formats an export can be asked for.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Deserialize, ToSchema)]
#[serde(rename_all = "lowercase")]
pub enum ExportFormat {
    #[default]
    Csv,
    Xlsx,
    Ods,
}

impl From<ExportFormat> for Format {
    fn from(f: ExportFormat) -> Self {
        match f {
            ExportFormat::Csv => Format::Csv,
            ExportFormat::Xlsx => Format::Xlsx,
            ExportFormat::Ods => Format::Ods,
        }
    }
}

/// Query parameters of the export endpoints.
#[derive(Debug, Default, Deserialize, IntoParams)]
pub struct ExportParams {
    /// `csv` (default), `xlsx` or `ods`.
    #[param(inline)]
    pub format: Option<ExportFormat>,
}

/// The typed rows of an export as `user` (checks the read permission).
pub async fn export_rows<E: Importable>(
    pool: &PgPool,
    user: &CurrentUser,
) -> AppResult<Vec<Vec<CellValue>>> {
    user.require(E::READ)?;
    E::export(pool, user).await
}

/// An export as a download in `format`: one sheet named after the entity for the spreadsheet
/// formats, the CSV of ADR 0029 for `csv`.
pub async fn export_request<E: Importable>(
    pool: &PgPool,
    user: &CurrentUser,
    params: &ExportParams,
) -> AppResult<(HeaderMap, Vec<u8>)> {
    let format = Format::from(params.format.unwrap_or_default());
    let rows = export_rows::<E>(pool, user).await?;
    let body = tokio::task::spawn_blocking(move || {
        write(format, E::FILE_STEM, &column_names::<E>(), rows)
    })
    .await
    .map_err(|e| AppError::Internal(e.into()))??;
    Ok(download(format, E::FILE_STEM, body))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;

    #[derive(Default)]
    struct Recorder(Mutex<Vec<(Phase, usize)>>);

    impl Progress for Recorder {
        fn report(&self, phase: Phase, processed: usize) {
            if let Ok(mut v) = self.0.lock() {
                v.push((phase, processed));
            }
        }
    }

    #[test]
    fn progress_is_reported_every_so_often_and_at_the_end() {
        let r = Recorder::default();
        let total = PROGRESS_EVERY * 2 + 3;
        for done in 1..=total {
            tick(&r, Phase::Validating, done, total);
        }
        let got = r.0.lock().map(|v| v.clone()).unwrap_or_default();
        let counts: Vec<usize> = got.iter().map(|(_, n)| *n).collect();
        assert_eq!(counts, [PROGRESS_EVERY, PROGRESS_EVERY * 2, total]);
        assert!(got.iter().all(|(p, _)| *p == Phase::Validating));
        assert_eq!(Phase::Writing.as_str(), "writing");
    }

    #[test]
    fn options_builder_and_audit_data() {
        let job = Uuid::nil();
        let options = RunOptions::new(Format::Xlsx).dry_run(true).import_job(job);
        assert!(options.dry_run);
        assert_eq!(
            audit_data(&options, Some(("code", "C1"))),
            serde_json::json!({
                "code": "C1",
                "source": "xlsx_import",
                "import_job": job.to_string(),
            })
        );
        let plain = RunOptions::new(Format::Csv);
        assert_eq!(
            audit_data(&plain, None),
            serde_json::json!({ "source": "csv_import" })
        );
        assert_eq!(
            audit_data(&RunOptions::new(Format::Ods), None)["source"],
            "ods_import"
        );
    }

    #[test]
    fn export_formats_are_lowercase_and_default_to_csv() {
        let p: ExportParams = serde_json::from_str(r#"{"format":"ods"}"#).unwrap();
        assert_eq!(Format::from(p.format.unwrap()), Format::Ods);
        assert!(serde_json::from_str::<ExportParams>(r#"{"format":"xls"}"#).is_err());
        assert_eq!(ExportFormat::default(), ExportFormat::Csv);
        assert!(ExportParams::default().format.is_none());
    }
}
