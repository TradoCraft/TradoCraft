//! HTTP endpoints for reports (ADR 0042).

use axum::extract::{Path, Query, State};
use axum::http::{header, HeaderMap, HeaderValue, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::Extension;
use axum::Json;
use chrono::{DateTime, NaiveDate, Utc};
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection};
use std::sync::Arc;
use tradocraft_core::company::get_company;
use tradocraft_core::csv_io;
use tradocraft_core::{audit, new_id, AppError, AppResult, AppState, CurrentUser, Permission};
use utoipa::{IntoParams, ToSchema};
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::catalog::{self, ReportFieldType};
use crate::definition::{plan, Plan, ReportDefinition};
use crate::engine::{self, ReportRunResult, MAX_PAGE};
use crate::pdf;

type ErrorBody = tradocraft_core::error::ErrorBody;

pub const MAX_NAME: usize = 120;
pub const MAX_DESCRIPTION: usize = 1000;
const DEFAULT_PAGE: i64 = 100;

// ---------------------------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------------------------

#[derive(Debug, Serialize, ToSchema)]
pub struct ReportCatalogField {
    /// Qualified name to use in a definition, e.g. `quotation.total`.
    pub name: String,
    pub label: String,
    #[serde(rename = "type")]
    pub ty: ReportFieldType,
    /// Only the number of records can be shown for this field.
    pub count_only: bool,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct ReportCatalogObject {
    pub name: String,
    pub label: String,
    pub fields: Vec<ReportCatalogField>,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct ReportCatalogLink {
    pub a: String,
    pub b: String,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct ReportCatalog {
    /// The objects the user may read.
    pub objects: Vec<ReportCatalogObject>,
    /// Pairs of objects that can be joined in one report.
    pub links: Vec<ReportCatalogLink>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct SavedReportInput {
    pub name: String,
    #[serde(default)]
    pub description: String,
    pub definition: ReportDefinition,
    /// Share with everyone in the company who may run reports.
    #[serde(default)]
    pub shared: bool,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct SavedReport {
    pub id: Uuid,
    pub name: String,
    pub description: String,
    pub object: String,
    pub definition: ReportDefinition,
    pub shared: bool,
    pub owner_id: Uuid,
    pub owner_name: String,
    /// The caller owns the report.
    pub mine: bool,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct ReportRunRequest {
    pub definition: ReportDefinition,
    pub limit: Option<i64>,
    pub offset: Option<i64>,
    /// Resolve relative dates as of this day (`YYYY-MM-DD`), see [`resolve_as_of`]. Default today.
    pub as_of: Option<String>,
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct PageParams {
    /// Rows per page (default 100, at most 500).
    pub limit: Option<i64>,
    pub offset: Option<i64>,
    /// Resolve relative dates as of this day (`YYYY-MM-DD`): send the `as_of` of the first page
    /// back for later pages. Not older than 366 days, not more than 1 day ahead. Default today.
    pub as_of: Option<String>,
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct ExportParams {
    /// `csv` (default) or `pdf`.
    pub format: Option<String>,
    /// Resolve relative dates as of this day (`YYYY-MM-DD`), same bounds as for running.
    /// Default today.
    pub as_of: Option<String>,
}

#[derive(FromRow)]
struct Row {
    id: Uuid,
    name: String,
    description: String,
    object: String,
    definition: serde_json::Value,
    shared: bool,
    owner_id: Uuid,
    owner_name: String,
    created_at: DateTime<Utc>,
    updated_at: DateTime<Utc>,
}

const SELECT: &str =
    "SELECT r.id, r.name, r.description, r.object, r.definition, r.shared, r.owner_id,
        u.display_name AS owner_name, r.created_at, r.updated_at
    FROM reports.reports r JOIN core.users u ON u.id = r.owner_id";

fn to_report(row: Row, user: &CurrentUser) -> AppResult<SavedReport> {
    let definition: ReportDefinition = serde_json::from_value(row.definition)
        .map_err(|e| AppError::Internal(anyhow::anyhow!("stored report definition: {e}")))?;
    Ok(SavedReport {
        id: row.id,
        name: row.name,
        description: row.description,
        object: row.object,
        definition,
        shared: row.shared,
        mine: row.owner_id == user.user_id,
        owner_id: row.owner_id,
        owner_name: row.owner_name,
        created_at: row.created_at,
        updated_at: row.updated_at,
    })
}

/// A report of the company by id, with no visibility check: callers must have authorised
/// access themselves (see [`load`] and `update_report`).
async fn load_unchecked(
    conn: &mut PgConnection,
    user: &CurrentUser,
    id: Uuid,
) -> AppResult<SavedReport> {
    let row: Row = sqlx::query_as(&format!("{SELECT} WHERE r.id = $1 AND r.company_id = $2"))
        .bind(id)
        .bind(user.company_id)
        .fetch_optional(&mut *conn)
        .await?
        .ok_or(AppError::NotFound("report"))?;
    to_report(row, user)
}

/// A report the caller may see: their own, or shared in the company.
async fn load(conn: &mut PgConnection, user: &CurrentUser, id: Uuid) -> AppResult<SavedReport> {
    let report = load_unchecked(conn, user, id).await?;
    if report.mine || report.shared {
        Ok(report)
    } else {
        Err(AppError::NotFound("report"))
    }
}

fn is_admin(user: &CurrentUser) -> bool {
    user.roles.iter().any(|r| r == "admin")
}

/// The caller may run the report only if they may read every object in it.
fn require_plan(user: &CurrentUser, plan: &Plan) -> AppResult<()> {
    for p in plan.permissions() {
        user.require(p)?;
    }
    Ok(())
}

/// Oldest `as_of` accepted, in days before today.
pub const AS_OF_MAX_PAST_DAYS: i64 = 366;
/// Furthest `as_of` accepted ahead of today, in days (clients ahead of UTC).
pub const AS_OF_MAX_FUTURE_DAYS: i64 = 1;

/// The day relative dates resolve against: the optional `as_of` (`YYYY-MM-DD`), else `today`.
/// An unparsable date, one older than [`AS_OF_MAX_PAST_DAYS`] or more than
/// [`AS_OF_MAX_FUTURE_DAYS`] ahead of `today` is a validation error (422).
pub fn resolve_as_of(raw: Option<&str>, today: NaiveDate) -> AppResult<NaiveDate> {
    let Some(raw) = raw else { return Ok(today) };
    let day = NaiveDate::parse_from_str(raw, "%Y-%m-%d")
        .map_err(|_| AppError::Validation("as_of must be a date as YYYY-MM-DD".into()))?;
    let days = (day - today).num_days();
    if !(-AS_OF_MAX_PAST_DAYS..=AS_OF_MAX_FUTURE_DAYS).contains(&days) {
        return Err(AppError::Validation(format!(
            "as_of must be within {AS_OF_MAX_PAST_DAYS} days before and {AS_OF_MAX_FUTURE_DAYS} day after today"
        )));
    }
    Ok(day)
}

/// Source of "today" for the report routes. Production uses the UTC date; a test installs its own
/// with `Router::layer(Extension(ReportClock::new(..)))`, so a midnight rollover can be exercised
/// without global state. Without the extension the routes use [`tradocraft_core::today`].
#[derive(Clone)]
pub struct ReportClock(Arc<dyn Fn() -> NaiveDate + Send + Sync>);

impl ReportClock {
    /// A clock that calls `now` for every request.
    pub fn new(now: impl Fn() -> NaiveDate + Send + Sync + 'static) -> Self {
        Self(Arc::new(now))
    }

    /// The date this clock currently reports.
    pub fn today(&self) -> NaiveDate {
        (self.0)()
    }
}

/// Plans a definition as of `as_of` (default today): relative dates are resolved at every run,
/// never stored.
fn make_plan(
    def: &ReportDefinition,
    as_of: Option<&str>,
    clock: &Option<Extension<ReportClock>>,
) -> AppResult<Plan> {
    let today = clock
        .as_ref()
        .map_or_else(tradocraft_core::today, |c| c.0.today());
    let day = resolve_as_of(as_of, today)?;
    plan(def, day).map_err(AppError::Validation)
}

fn check_input(input: &SavedReportInput) -> AppResult<String> {
    let name = input.name.trim();
    if name.is_empty() || name.chars().count() > MAX_NAME {
        return Err(AppError::Validation(format!(
            "the name must be 1 to {MAX_NAME} characters"
        )));
    }
    if input.description.chars().count() > MAX_DESCRIPTION {
        return Err(AppError::Validation(format!(
            "the description is limited to {MAX_DESCRIPTION} characters"
        )));
    }
    Ok(name.to_string())
}

fn page(limit: Option<i64>, offset: Option<i64>) -> (i64, i64) {
    (
        limit.unwrap_or(DEFAULT_PAGE).clamp(1, MAX_PAGE),
        offset.unwrap_or(0).max(0),
    )
}

// ---------------------------------------------------------------------------------------------
// Endpoints
// ---------------------------------------------------------------------------------------------

#[utoipa::path(get, path = "/custom-reports/catalog", tag = "reports", operation_id = "reports_catalog",
    responses((status = 200, body = ReportCatalog), (status = 403, body = ErrorBody)))]
async fn get_catalog(user: CurrentUser) -> AppResult<Json<ReportCatalog>> {
    user.require(Permission::ReportsRead)?;
    let readable = |name: &str| catalog::object(name).is_some_and(|o| user.can(o.permission));
    let objects = catalog::OBJECTS
        .iter()
        .filter(|o| user.can(o.permission))
        .map(|o| ReportCatalogObject {
            name: o.name.to_string(),
            label: o.label.to_string(),
            fields: o
                .fields
                .iter()
                .map(|f| ReportCatalogField {
                    name: format!("{}.{}", o.name, f.name),
                    label: f.label.to_string(),
                    ty: f.ty,
                    count_only: f.count_only,
                })
                .collect(),
        })
        .collect();
    let links = catalog::links()
        .into_iter()
        .filter(|(a, b)| readable(a) && readable(b))
        .map(|(a, b)| ReportCatalogLink {
            a: a.to_string(),
            b: b.to_string(),
        })
        .collect();
    Ok(Json(ReportCatalog { objects, links }))
}

#[utoipa::path(get, path = "/custom-reports", tag = "reports", operation_id = "reports_list",
    responses((status = 200, body = Vec<SavedReport>), (status = 403, body = ErrorBody)))]
async fn list_reports(
    State(state): State<AppState>,
    user: CurrentUser,
) -> AppResult<Json<Vec<SavedReport>>> {
    user.require(Permission::ReportsRead)?;
    let rows: Vec<Row> = sqlx::query_as(&format!(
        "{SELECT} WHERE r.company_id = $1 AND (r.owner_id = $2 OR r.shared)
         ORDER BY lower(r.name), r.id"
    ))
    .bind(user.company_id)
    .bind(user.user_id)
    .fetch_all(&state.db)
    .await?;
    let reports = rows
        .into_iter()
        .map(|r| to_report(r, &user))
        .collect::<AppResult<Vec<_>>>()?;
    Ok(Json(reports))
}

#[utoipa::path(post, path = "/custom-reports", tag = "reports", operation_id = "reports_create",
    request_body = SavedReportInput,
    responses((status = 201, body = SavedReport), (status = 403, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn create_report(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<SavedReportInput>,
) -> AppResult<(StatusCode, Json<SavedReport>)> {
    user.require(Permission::ReportsWrite)?;
    let name = check_input(&input)?;
    let plan = make_plan(&input.definition, None, &None)?;
    require_plan(&user, &plan)?;
    let mut tx = state.db.begin().await?;
    let id = new_id();
    sqlx::query(
        "INSERT INTO reports.reports (id, company_id, owner_id, name, description, object, definition, shared)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(user.user_id)
    .bind(&name)
    .bind(&input.description)
    .bind(&input.definition.object)
    .bind(serde_json::to_value(&input.definition).unwrap_or_default())
    .bind(input.shared)
    .execute(&mut *tx)
    .await?;
    audit::record(
        &mut tx,
        &user,
        "report",
        id,
        "created",
        serde_json::json!({ "name": name, "object": input.definition.object, "shared": input.shared }),
    )
    .await?;
    let report = load(&mut tx, &user, id).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(report)))
}

#[utoipa::path(get, path = "/custom-reports/{id}", tag = "reports", operation_id = "reports_get",
    params(("id" = Uuid, Path)),
    responses((status = 200, body = SavedReport), (status = 404, body = ErrorBody)))]
async fn get_report(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<SavedReport>> {
    user.require(Permission::ReportsRead)?;
    let mut conn = state.db.acquire().await?;
    Ok(Json(load(&mut conn, &user, id).await?))
}

#[utoipa::path(put, path = "/custom-reports/{id}", tag = "reports", operation_id = "reports_update",
    params(("id" = Uuid, Path)), request_body = SavedReportInput,
    responses((status = 200, body = SavedReport), (status = 403, body = ErrorBody),
              (status = 404, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn update_report(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<SavedReportInput>,
) -> AppResult<Json<SavedReport>> {
    user.require(Permission::ReportsWrite)?;
    let name = check_input(&input)?;
    let plan = make_plan(&input.definition, None, &None)?;
    require_plan(&user, &plan)?;
    let mut tx = state.db.begin().await?;
    let existing = load(&mut tx, &user, id).await?;
    if !existing.mine && !is_admin(&user) {
        return Err(AppError::Forbidden(
            "only the owner or an admin can change a report".into(),
        ));
    }
    sqlx::query(
        "UPDATE reports.reports SET name = $3, description = $4, object = $5, definition = $6,
                shared = $7, updated_at = now()
         WHERE id = $1 AND company_id = $2",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(&name)
    .bind(&input.description)
    .bind(&input.definition.object)
    .bind(serde_json::to_value(&input.definition).unwrap_or_default())
    .bind(input.shared)
    .execute(&mut *tx)
    .await?;
    audit::record(
        &mut tx,
        &user,
        "report",
        id,
        "updated",
        serde_json::json!({ "name": name, "shared": input.shared }),
    )
    .await?;
    // Authorised above; the update may have made it private to its owner, so do not re-apply
    // read visibility to the admin who changed it.
    let report = load_unchecked(&mut tx, &user, id).await?;
    tx.commit().await?;
    Ok(Json(report))
}

#[utoipa::path(delete, path = "/custom-reports/{id}", tag = "reports", operation_id = "reports_delete",
    params(("id" = Uuid, Path)),
    responses((status = 204), (status = 403, body = ErrorBody), (status = 404, body = ErrorBody)))]
async fn delete_report(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<StatusCode> {
    user.require(Permission::ReportsWrite)?;
    let mut tx = state.db.begin().await?;
    let existing = load(&mut tx, &user, id).await?;
    if !existing.mine && !is_admin(&user) {
        return Err(AppError::Forbidden(
            "only the owner or an admin can delete a report".into(),
        ));
    }
    sqlx::query("DELETE FROM reports.reports WHERE id = $1 AND company_id = $2")
        .bind(id)
        .bind(user.company_id)
        .execute(&mut *tx)
        .await?;
    audit::record(
        &mut tx,
        &user,
        "report",
        id,
        "deleted",
        serde_json::json!({ "name": existing.name }),
    )
    .await?;
    tx.commit().await?;
    Ok(StatusCode::NO_CONTENT)
}

#[utoipa::path(post, path = "/custom-reports/run", tag = "reports", operation_id = "reports_run_definition",
    request_body = ReportRunRequest,
    responses((status = 200, body = ReportRunResult), (status = 403, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn run_definition(
    State(state): State<AppState>,
    clock: Option<Extension<ReportClock>>,
    user: CurrentUser,
    Json(req): Json<ReportRunRequest>,
) -> AppResult<Json<ReportRunResult>> {
    user.require(Permission::ReportsRead)?;
    let plan = make_plan(&req.definition, req.as_of.as_deref(), &clock)?;
    require_plan(&user, &plan)?;
    let (limit, offset) = page(req.limit, req.offset);
    let mut conn = state.db.acquire().await?;
    Ok(Json(
        engine::run(&mut conn, user.company_id, &plan, limit, offset).await?,
    ))
}

#[utoipa::path(get, path = "/custom-reports/{id}/run", tag = "reports", operation_id = "reports_run",
    params(("id" = Uuid, Path), PageParams),
    responses((status = 200, body = ReportRunResult), (status = 403, body = ErrorBody), (status = 404, body = ErrorBody)))]
async fn run_report(
    State(state): State<AppState>,
    user: CurrentUser,
    clock: Option<Extension<ReportClock>>,
    Path(id): Path<Uuid>,
    Query(p): Query<PageParams>,
) -> AppResult<Json<ReportRunResult>> {
    user.require(Permission::ReportsRead)?;
    let mut conn = state.db.acquire().await?;
    let report = load(&mut conn, &user, id).await?;
    let plan = make_plan(&report.definition, p.as_of.as_deref(), &clock)?;
    require_plan(&user, &plan)?;
    let (limit, offset) = page(p.limit, p.offset);
    Ok(Json(
        engine::run(&mut conn, user.company_id, &plan, limit, offset).await?,
    ))
}

fn cell(v: &serde_json::Value) -> String {
    match v {
        serde_json::Value::Null => String::new(),
        serde_json::Value::String(s) => s.clone(),
        // Numbers are written like in the other CSV exports (ADR 0029): no trailing zeros.
        serde_json::Value::Number(n) => n
            .to_string()
            .parse::<rust_decimal::Decimal>()
            .map(csv_io::format_decimal)
            .unwrap_or_else(|_| n.to_string()),
        other => other.to_string(),
    }
}

pub(crate) fn slug(name: &str) -> String {
    let s: String = name
        .chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() {
                c.to_ascii_lowercase()
            } else {
                '-'
            }
        })
        .collect();
    let s = s
        .split('-')
        .filter(|p| !p.is_empty())
        .collect::<Vec<_>>()
        .join("-");
    if s.is_empty() {
        "report".into()
    } else {
        s.chars().take(60).collect()
    }
}

pub(crate) fn csv_of(result: &ReportRunResult) -> String {
    let header: Vec<&str> = result.columns.iter().map(|c| c.label.as_str()).collect();
    let mut rows: Vec<Vec<String>> = result
        .rows
        .iter()
        .map(|r| r.iter().map(cell).collect())
        .collect();
    if let Some(t) = &result.totals {
        rows.push(t.iter().map(cell).collect());
    }
    csv_io::write_csv(&header, rows)
}

#[utoipa::path(get, path = "/custom-reports/{id}/export", tag = "reports", operation_id = "reports_export",
    params(("id" = Uuid, Path), ExportParams),
    responses((status = 200, description = "The report as a CSV or PDF file"),
              (status = 403, body = ErrorBody), (status = 404, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn export_report(
    State(state): State<AppState>,
    user: CurrentUser,
    clock: Option<Extension<ReportClock>>,
    Path(id): Path<Uuid>,
    Query(p): Query<ExportParams>,
) -> AppResult<Response> {
    user.require(Permission::ReportsRead)?;
    let mut conn = state.db.acquire().await?;
    let report = load(&mut conn, &user, id).await?;
    // One day for the filters and the page, even across midnight.
    let plan = make_plan(&report.definition, p.as_of.as_deref(), &clock)?;
    let today = plan.as_of;
    require_plan(&user, &plan)?;
    match p.format.as_deref().unwrap_or("csv") {
        "csv" => {
            let result = engine::run_all(&mut conn, user.company_id, &plan).await?;
            let file = format!("report-{}-{}.csv", slug(&report.name), today);
            Ok(csv_io::download(&file, csv_of(&result)).into_response())
        }
        "pdf" => {
            let result =
                engine::run(&mut conn, user.company_id, &plan, pdf::MAX_PDF_ROWS + 1, 0).await?;
            if result.rows.len() as i64 > pdf::MAX_PDF_ROWS {
                return Err(AppError::Validation(format!(
                    "the report has more than {} rows; add filters, group it, or export it as CSV",
                    pdf::MAX_PDF_ROWS
                )));
            }
            let company = get_company(&mut *conn, user.company_id).await?;
            let data = pdf::build(
                &report.name,
                &report.description,
                &report.definition,
                &result,
                &company.name,
                &company.default_language,
                today,
            );
            let bytes = tradocraft_documents::render_pdf(&state.documents, "report", &data)
                .await
                .map_err(AppError::Internal)?;
            let file = format!("report-{}-{}.pdf", slug(&report.name), today);
            let mut headers = HeaderMap::new();
            headers.insert(
                header::CONTENT_TYPE,
                HeaderValue::from_static("application/pdf"),
            );
            headers.insert(
                header::CONTENT_DISPOSITION,
                HeaderValue::from_str(&format!("attachment; filename=\"{file}\""))
                    .unwrap_or_else(|_| HeaderValue::from_static("attachment")),
            );
            Ok((headers, bytes).into_response())
        }
        other => Err(AppError::Validation(format!("unknown format '{other}'"))),
    }
}

/// The routes of the reports module.
pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(get_catalog))
        .routes(routes!(list_reports, create_report))
        .routes(routes!(run_definition))
        .routes(routes!(get_report, update_report, delete_report))
        .routes(routes!(run_report))
        .routes(routes!(export_report))
        .merge(crate::schedule_routes::router())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn file_names_are_safe() {
        assert_eq!(slug("Q3 Sales: EUR/USD!"), "q3-sales-eur-usd");
        assert_eq!(slug("../../etc"), "etc");
        assert_eq!(slug("日本語"), "report");
    }

    #[test]
    fn as_of_defaults_to_today_and_is_bounded() {
        let today = NaiveDate::from_ymd_opt(2026, 11, 11).unwrap();
        assert_eq!(resolve_as_of(None, today).unwrap(), today);
        let d = |s| resolve_as_of(Some(s), today);
        assert_eq!(
            d("2026-11-01").unwrap(),
            NaiveDate::from_ymd_opt(2026, 11, 1).unwrap()
        );
        assert!(d("2026-11-12").is_ok());
        assert!(d("2025-11-10").is_ok()); // 366 days back
        assert!(d("2025-11-09").is_err());
        assert!(d("2026-11-13").is_err());
        for bad in [
            "",
            "tomorrow",
            "2026-13-01",
            "11/11/2026",
            "2026-11-01T00:00:00",
        ] {
            assert!(d(bad).is_err(), "{bad}");
        }
    }

    #[test]
    fn paging_is_clamped() {
        assert_eq!(page(None, None), (100, 0));
        assert_eq!(page(Some(0), Some(-5)), (1, 0));
        assert_eq!(page(Some(100_000), Some(10)), (500, 10));
    }

    #[test]
    fn csv_has_labels_rows_and_totals_and_neutralises_formulas() {
        let result = ReportRunResult {
            columns: vec![],
            rows: vec![],
            total: 0,
            totals: None,
            chart: None,
            as_of: chrono::NaiveDate::from_ymd_opt(2026, 11, 11).unwrap(),
        };
        assert_eq!(csv_of(&result), "\r\n");
        assert_eq!(cell(&json!(null)), "");
        assert_eq!(cell(&json!(12.5)), "12.5");
        assert_eq!(cell(&json!(500.0)), "500");
        assert_eq!(cell(&json!(0.3)), "0.3");
        assert_eq!(cell(&json!(42)), "42");
        assert_eq!(cell(&json!(true)), "true");
        assert_eq!(csv_io::quote_cell(&cell(&json!("=SUM(A1)"))), "'=SUM(A1)");
    }
}
