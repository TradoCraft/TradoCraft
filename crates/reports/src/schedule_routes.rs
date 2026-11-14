//! HTTP endpoints for scheduled report mails (ADR 0065).

use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::Json;
use chrono::{DateTime, NaiveTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection};
use tradocraft_core::{audit, new_id, AppError, AppResult, AppState, CurrentUser, Permission};
use utoipa::ToSchema;
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::definition::plan;
use crate::schedule::{
    self, next_run, HelpdeskReportSpec, ScheduleRow, Timing, FORMATS, FREQUENCIES, MAX_RECIPIENTS,
    PERIODS,
};

type ErrorBody = tradocraft_core::error::ErrorBody;

const MAX_NAME: usize = 120;

#[derive(Debug, Serialize, ToSchema)]
pub struct ReportSchedule {
    pub id: Uuid,
    pub name: String,
    /// `custom` (a saved report of the report builder) or `helpdesk` (a table of the helpdesk report).
    pub source: String,
    pub report_id: Option<Uuid>,
    pub report_name: Option<String>,
    pub helpdesk: Option<HelpdeskReportSpec>,
    /// daily | weekly | monthly
    pub frequency: String,
    /// 1 (Monday) to 7, for weekly.
    pub weekday: Option<i16>,
    /// 1 to 28, for monthly.
    pub day_of_month: Option<i16>,
    /// Local time, `HH:MM`.
    pub send_time: String,
    pub time_zone: String,
    /// csv | pdf
    pub format: String,
    /// Colleagues who receive it (active members of the company at the time it is sent).
    pub user_ids: Vec<Uuid>,
    /// Other recipients.
    pub addresses: Vec<String>,
    pub active: bool,
    pub owner_id: Uuid,
    pub owner_name: String,
    pub next_run_at: DateTime<Utc>,
    pub last_run_at: Option<DateTime<Utc>>,
    /// sent | failed
    pub last_status: Option<String>,
    pub last_error: Option<String>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct ReportScheduleInput {
    pub name: String,
    pub source: String,
    /// For `custom`.
    pub report_id: Option<Uuid>,
    /// For `helpdesk`.
    pub helpdesk: Option<HelpdeskReportSpec>,
    pub frequency: String,
    pub weekday: Option<i16>,
    pub day_of_month: Option<i16>,
    /// Local time, `HH:MM`. Default 07:00.
    pub send_time: Option<String>,
    /// An IANA zone, default `Europe/Brussels`.
    pub time_zone: Option<String>,
    pub format: String,
    #[serde(default)]
    pub user_ids: Vec<Uuid>,
    #[serde(default)]
    pub addresses: Vec<String>,
    #[serde(default = "yes")]
    pub active: bool,
}

fn yes() -> bool {
    true
}

#[derive(Debug, Serialize, ToSchema)]
pub struct SendNowResult {
    /// Mails queued.
    pub mails: i64,
}

#[derive(FromRow)]
struct Row {
    id: Uuid,
    name: String,
    source: String,
    report_id: Option<Uuid>,
    report_name: Option<String>,
    helpdesk: Option<serde_json::Value>,
    frequency: String,
    weekday: Option<i16>,
    day_of_month: Option<i16>,
    send_time: NaiveTime,
    time_zone: String,
    format: String,
    user_ids: Vec<Uuid>,
    addresses: Vec<String>,
    active: bool,
    owner_id: Uuid,
    owner_name: String,
    next_run_at: DateTime<Utc>,
    last_run_at: Option<DateTime<Utc>>,
    last_status: Option<String>,
    last_error: Option<String>,
    created_at: DateTime<Utc>,
    updated_at: DateTime<Utc>,
}

const SELECT: &str =
    "SELECT s.id, s.name, s.source, s.report_id, r.name AS report_name, s.helpdesk,
        s.frequency, s.weekday, s.day_of_month, s.send_time, s.time_zone, s.format, s.user_ids,
        s.addresses, s.active, s.owner_id, u.display_name AS owner_name, s.next_run_at,
        s.last_run_at, s.last_status, s.last_error, s.created_at, s.updated_at
    FROM reports.schedules s
    JOIN core.users u ON u.id = s.owner_id
    LEFT JOIN reports.reports r ON r.id = s.report_id";

impl From<Row> for ReportSchedule {
    fn from(r: Row) -> Self {
        ReportSchedule {
            id: r.id,
            name: r.name,
            source: r.source,
            report_id: r.report_id,
            report_name: r.report_name,
            helpdesk: r.helpdesk.and_then(|v| serde_json::from_value(v).ok()),
            frequency: r.frequency,
            weekday: r.weekday,
            day_of_month: r.day_of_month,
            send_time: r.send_time.format("%H:%M").to_string(),
            time_zone: r.time_zone,
            format: r.format,
            user_ids: r.user_ids,
            addresses: r.addresses,
            active: r.active,
            owner_id: r.owner_id,
            owner_name: r.owner_name,
            next_run_at: r.next_run_at,
            last_run_at: r.last_run_at,
            last_status: r.last_status,
            last_error: r.last_error,
            created_at: r.created_at,
            updated_at: r.updated_at,
        }
    }
}

async fn load(conn: &mut PgConnection, company_id: Uuid, id: Uuid) -> AppResult<ReportSchedule> {
    let row: Row = sqlx::query_as(&format!("{SELECT} WHERE s.id = $1 AND s.company_id = $2"))
        .bind(id)
        .bind(company_id)
        .fetch_optional(conn)
        .await?
        .ok_or(AppError::NotFound("report schedule"))?;
    Ok(row.into())
}

fn is_admin(user: &CurrentUser) -> bool {
    user.roles.iter().any(|r| r == "admin")
}

/// A validated input, ready to store.
struct Prepared {
    name: String,
    send_time: NaiveTime,
    time_zone: String,
    addresses: Vec<String>,
    helpdesk: Option<serde_json::Value>,
    next_run_at: DateTime<Utc>,
}

async fn prepare(
    conn: &mut PgConnection,
    user: &CurrentUser,
    input: &ReportScheduleInput,
) -> AppResult<Prepared> {
    let name = input.name.trim().to_string();
    if name.is_empty() || name.chars().count() > MAX_NAME {
        return Err(AppError::Validation(format!(
            "the name must be 1 to {MAX_NAME} characters"
        )));
    }
    if !FREQUENCIES.contains(&input.frequency.as_str()) {
        return Err(AppError::Validation(format!(
            "frequency must be one of {}",
            FREQUENCIES.join(", ")
        )));
    }
    match (input.frequency.as_str(), input.weekday, input.day_of_month) {
        ("weekly", Some(1..=7), None) | ("monthly", None, Some(1..=28)) | ("daily", None, None) => {
        }
        ("weekly", _, _) => {
            return Err(AppError::Validation(
                "a weekly schedule needs weekday 1 (Monday) to 7 and no day_of_month".into(),
            ))
        }
        ("monthly", _, _) => {
            return Err(AppError::Validation(
                "a monthly schedule needs day_of_month 1 to 28 and no weekday".into(),
            ))
        }
        _ => {
            return Err(AppError::Validation(
                "a daily schedule has neither weekday nor day_of_month".into(),
            ))
        }
    }
    let send_time =
        NaiveTime::parse_from_str(input.send_time.as_deref().unwrap_or("07:00"), "%H:%M")
            .map_err(|_| AppError::Validation("send_time must be HH:MM".into()))?;
    let time_zone = input
        .time_zone
        .clone()
        .unwrap_or_else(|| "Europe/Brussels".into());
    let tz = time_zone
        .parse()
        .map_err(|_| AppError::Validation("time_zone must be an IANA name".into()))?;
    if !FORMATS.contains(&input.format.as_str()) {
        return Err(AppError::Validation("format must be csv or pdf".into()));
    }
    // Recipients: active members of this company, and plausible addresses.
    let mut addresses: Vec<String> = Vec::new();
    for a in &input.addresses {
        let a = a.trim().to_lowercase();
        if !tradocraft_helpdesk::automail::valid_address(&a) {
            return Err(AppError::Validation(format!(
                "{a:?} is not an e-mail address"
            )));
        }
        if !addresses.contains(&a) {
            addresses.push(a);
        }
    }
    let mut user_ids = input.user_ids.clone();
    user_ids.sort();
    user_ids.dedup();
    if user_ids.len() + addresses.len() > MAX_RECIPIENTS {
        return Err(AppError::Validation(format!(
            "at most {MAX_RECIPIENTS} recipients"
        )));
    }
    if user_ids.is_empty() && addresses.is_empty() {
        return Err(AppError::Validation("choose at least one recipient".into()));
    }
    let members: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM core.user_companies WHERE company_id = $1 AND active AND user_id = ANY($2)",
    )
    .bind(user.company_id)
    .bind(&user_ids)
    .fetch_one(&mut *conn)
    .await?;
    if members != user_ids.len() as i64 {
        return Err(AppError::Validation(
            "a recipient is not a member of this company".into(),
        ));
    }
    // The source: the person who sets it up must be able to run it themselves.
    let helpdesk = match input.source.as_str() {
        "custom" => {
            let id = input
                .report_id
                .ok_or_else(|| AppError::Validation("a custom schedule needs report_id".into()))?;
            if input.helpdesk.is_some() {
                return Err(AppError::Validation(
                    "a custom schedule has no helpdesk part".into(),
                ));
            }
            user.require(Permission::ReportsRead)?;
            let found: Option<(serde_json::Value, Uuid, bool)> = sqlx::query_as(
                "SELECT definition, owner_id, shared FROM reports.reports WHERE id = $1 AND company_id = $2",
            )
            .bind(id)
            .bind(user.company_id)
            .fetch_optional(&mut *conn)
            .await?;
            let (def, owner_id, shared) = found.ok_or(AppError::NotFound("report"))?;
            if owner_id != user.user_id && !shared {
                return Err(AppError::NotFound("report"));
            }
            let def: crate::definition::ReportDefinition =
                serde_json::from_value(def).map_err(|e| {
                    AppError::Validation(format!("the stored report is not valid: {e}"))
                })?;
            let planned = plan(&def, tradocraft_core::today()).map_err(AppError::Validation)?;
            for p in planned.permissions() {
                user.require(p)?;
            }
            None
        }
        "helpdesk" => {
            if input.report_id.is_some() {
                return Err(AppError::Validation(
                    "a helpdesk schedule has no report_id".into(),
                ));
            }
            user.require(Permission::HelpdeskRead)?;
            let spec = input
                .helpdesk
                .clone()
                .ok_or_else(|| AppError::Validation("a helpdesk schedule needs helpdesk".into()))?;
            if !tradocraft_helpdesk::reports::TABLES.contains(&spec.table.as_str()) {
                return Err(AppError::Validation(format!(
                    "table must be one of {}",
                    tradocraft_helpdesk::reports::TABLES.join(", ")
                )));
            }
            if !PERIODS.contains(&spec.period.as_str()) {
                return Err(AppError::Validation(format!(
                    "period must be one of {}",
                    PERIODS.join(", ")
                )));
            }
            if !matches!(spec.group.as_deref(), None | Some("day") | Some("week")) {
                return Err(AppError::Validation("group must be day or week".into()));
            }
            if let Some(c) = &spec.category {
                if !tradocraft_helpdesk::tickets::CATEGORIES.contains(&c.as_str()) {
                    return Err(AppError::Validation("unknown category".into()));
                }
            }
            if let Some(team) = spec.team_id {
                let ok: bool = sqlx::query_scalar(
                    "SELECT EXISTS (SELECT 1 FROM helpdesk.teams WHERE id = $1 AND company_id = $2)",
                )
                .bind(team)
                .bind(user.company_id)
                .fetch_one(&mut *conn)
                .await?;
                if !ok {
                    return Err(AppError::NotFound("team"));
                }
            }
            if let Some(owner) = spec.owner_id {
                let ok: bool = sqlx::query_scalar(
                    "SELECT EXISTS (SELECT 1 FROM core.user_companies WHERE user_id = $1 AND company_id = $2)",
                )
                .bind(owner)
                .bind(user.company_id)
                .fetch_one(&mut *conn)
                .await?;
                if !ok {
                    return Err(AppError::NotFound("user"));
                }
            }
            Some(serde_json::to_value(&spec).unwrap_or_default())
        }
        _ => {
            return Err(AppError::Validation(
                "source must be custom or helpdesk".into(),
            ))
        }
    };
    let timing = Timing {
        frequency: input.frequency.clone(),
        weekday: input.weekday,
        day_of_month: input.day_of_month,
        send_time,
        tz,
    };
    Ok(Prepared {
        name,
        send_time,
        time_zone,
        addresses,
        helpdesk,
        next_run_at: next_run(&timing, Utc::now()),
    })
}

fn sorted_ids(input: &ReportScheduleInput) -> Vec<Uuid> {
    let mut ids = input.user_ids.clone();
    ids.sort();
    ids.dedup();
    ids
}

#[utoipa::path(get, path = "/report-schedules", tag = "reports", operation_id = "report_schedules_list",
    responses((status = 200, body = Vec<ReportSchedule>), (status = 403, body = ErrorBody)))]
async fn list_schedules(
    State(state): State<AppState>,
    user: CurrentUser,
) -> AppResult<Json<Vec<ReportSchedule>>> {
    user.require(Permission::ReportsSchedule)?;
    let rows: Vec<Row> = sqlx::query_as(&format!(
        "{SELECT} WHERE s.company_id = $1 ORDER BY lower(s.name), s.id"
    ))
    .bind(user.company_id)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows.into_iter().map(Into::into).collect()))
}

#[utoipa::path(post, path = "/report-schedules", tag = "reports", operation_id = "report_schedules_create",
    request_body = ReportScheduleInput,
    responses((status = 201, body = ReportSchedule), (status = 403, body = ErrorBody), (status = 404, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn create_schedule(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<ReportScheduleInput>,
) -> AppResult<(StatusCode, Json<ReportSchedule>)> {
    user.require(Permission::ReportsSchedule)?;
    let mut tx = state.db.begin().await?;
    let p = prepare(&mut tx, &user, &input).await?;
    let id = new_id();
    sqlx::query(
        "INSERT INTO reports.schedules (id, company_id, owner_id, name, source, report_id, helpdesk,
                frequency, weekday, day_of_month, send_time, time_zone, format, user_ids, addresses,
                active, next_run_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17)",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(user.user_id)
    .bind(&p.name)
    .bind(&input.source)
    .bind(input.report_id)
    .bind(&p.helpdesk)
    .bind(&input.frequency)
    .bind(input.weekday)
    .bind(input.day_of_month)
    .bind(p.send_time)
    .bind(&p.time_zone)
    .bind(&input.format)
    .bind(sorted_ids(&input))
    .bind(&p.addresses)
    .bind(input.active)
    .bind(p.next_run_at)
    .execute(&mut *tx)
    .await?;
    audit::record(
        &mut tx,
        &user,
        "report_schedule",
        id,
        "created",
        serde_json::json!({ "name": p.name, "source": input.source, "frequency": input.frequency,
            "format": input.format, "recipients": input.user_ids.len() + p.addresses.len() }),
    )
    .await?;
    let schedule = load(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(schedule)))
}

#[utoipa::path(put, path = "/report-schedules/{id}", tag = "reports", operation_id = "report_schedules_update",
    params(("id" = Uuid, Path)), request_body = ReportScheduleInput,
    responses((status = 200, body = ReportSchedule), (status = 403, body = ErrorBody), (status = 404, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn update_schedule(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<ReportScheduleInput>,
) -> AppResult<Json<ReportSchedule>> {
    user.require(Permission::ReportsSchedule)?;
    let mut tx = state.db.begin().await?;
    let existing = load(&mut tx, user.company_id, id).await?;
    if existing.owner_id != user.user_id && !is_admin(&user) {
        return Err(AppError::Forbidden(
            "only the owner or an admin can change a schedule".into(),
        ));
    }
    // The owner pausing a schedule, with the source and recipients as stored, is only a pause: they
    // are not validated again (the owner may have lost access since), and stay as they are.
    let same_access = input.source == existing.source
        && input.report_id == existing.report_id
        && serde_json::to_value(&input.helpdesk).ok()
            == serde_json::to_value(&existing.helpdesk).ok()
        && sorted_ids(&input) == existing.user_ids
        && {
            let mut a: Vec<String> = input
                .addresses
                .iter()
                .map(|a| a.trim().to_lowercase())
                .collect();
            a.sort();
            a.dedup();
            let mut b = existing.addresses.clone();
            b.sort();
            a == b
        };
    if !input.active && existing.owner_id == user.user_id && same_access {
        sqlx::query(
            "UPDATE reports.schedules SET active = false, updated_at = now()
             WHERE id = $1 AND company_id = $2",
        )
        .bind(id)
        .bind(user.company_id)
        .execute(&mut *tx)
        .await?;
        audit::record(
            &mut tx,
            &user,
            "report_schedule",
            id,
            "updated",
            serde_json::json!({ "name": existing.name, "active": false }),
        )
        .await?;
        let schedule = load(&mut tx, user.company_id, id).await?;
        tx.commit().await?;
        return Ok(Json(schedule));
    }
    // An admin who edits somebody else's schedule makes it their own: from now on it runs with
    // their permissions, which are the ones that were just checked.
    let p = prepare(&mut tx, &user, &input).await?;
    sqlx::query(
        "UPDATE reports.schedules SET owner_id = $3, name = $4, source = $5, report_id = $6, helpdesk = $7,
                frequency = $8, weekday = $9, day_of_month = $10, send_time = $11, time_zone = $12,
                format = $13, user_ids = $14, addresses = $15, active = $16, next_run_at = $17,
                updated_at = now()
         WHERE id = $1 AND company_id = $2",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(user.user_id)
    .bind(&p.name)
    .bind(&input.source)
    .bind(input.report_id)
    .bind(&p.helpdesk)
    .bind(&input.frequency)
    .bind(input.weekday)
    .bind(input.day_of_month)
    .bind(p.send_time)
    .bind(&p.time_zone)
    .bind(&input.format)
    .bind(sorted_ids(&input))
    .bind(&p.addresses)
    .bind(input.active)
    .bind(p.next_run_at)
    .execute(&mut *tx)
    .await?;
    audit::record(
        &mut tx,
        &user,
        "report_schedule",
        id,
        "updated",
        serde_json::json!({ "name": p.name, "source": input.source, "frequency": input.frequency,
            "format": input.format, "active": input.active,
            "recipients": input.user_ids.len() + p.addresses.len() }),
    )
    .await?;
    let schedule = load(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok(Json(schedule))
}

#[utoipa::path(delete, path = "/report-schedules/{id}", tag = "reports", operation_id = "report_schedules_delete",
    params(("id" = Uuid, Path)),
    responses((status = 204), (status = 403, body = ErrorBody), (status = 404, body = ErrorBody)))]
async fn delete_schedule(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<StatusCode> {
    user.require(Permission::ReportsSchedule)?;
    let mut tx = state.db.begin().await?;
    let existing = load(&mut tx, user.company_id, id).await?;
    if existing.owner_id != user.user_id && !is_admin(&user) {
        return Err(AppError::Forbidden(
            "only the owner or an admin can delete a schedule".into(),
        ));
    }
    sqlx::query("DELETE FROM reports.schedules WHERE id = $1 AND company_id = $2")
        .bind(id)
        .bind(user.company_id)
        .execute(&mut *tx)
        .await?;
    audit::record(
        &mut tx,
        &user,
        "report_schedule",
        id,
        "deleted",
        serde_json::json!({ "name": existing.name }),
    )
    .await?;
    tx.commit().await?;
    Ok(StatusCode::NO_CONTENT)
}

/// Builds the report now and queues the mail, as the schedule's owner would get it. The next
/// scheduled run does not change. A refusal (the owner lost access, too many rows) is a 422 with
/// the reason.
#[utoipa::path(post, path = "/report-schedules/{id}/send", tag = "reports", operation_id = "report_schedules_send",
    params(("id" = Uuid, Path)),
    responses((status = 200, body = SendNowResult), (status = 403, body = ErrorBody), (status = 404, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn send_schedule(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<SendNowResult>> {
    user.require(Permission::ReportsSchedule)?;
    let mut tx = state.db.begin().await?;
    let existing = load(&mut tx, user.company_id, id).await?;
    if existing.owner_id != user.user_id && !is_admin(&user) {
        return Err(AppError::Forbidden(
            "only the owner or an admin can send a schedule".into(),
        ));
    }
    let row: ScheduleRow = sqlx::query_as(&format!(
        "{} WHERE id = $1 AND company_id = $2 FOR UPDATE",
        schedule::SELECT_ROW
    ))
    .bind(id)
    .bind(user.company_id)
    .fetch_one(&mut *tx)
    .await?;
    let now = Utc::now();
    let mails = schedule::deliver(&mut tx, &state.documents, &row, now).await?;
    schedule::record_outcome(&mut tx, &row, now, false, &Ok(mails)).await?;
    tx.commit().await?;
    Ok(Json(SendNowResult {
        mails: mails as i64,
    }))
}

/// The routes of the scheduled report mails.
pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(list_schedules, create_schedule))
        .routes(routes!(update_schedule, delete_schedule))
        .routes(routes!(send_schedule))
}
