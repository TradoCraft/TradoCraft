//! Resource calendars: planning settings, working hours and absences.

use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::Json;
use chrono::{NaiveDate, NaiveTime};
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection};
use tradocraft_core::serde_util::{date, opt_date};
use tradocraft_core::{new_id, AppError, AppResult, AppState, CurrentUser, Permission};
use utoipa::{IntoParams, ToSchema};
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

type ErrorBody = tradocraft_core::error::ErrorBody;

pub const ABSENCE_KINDS: [&str; 4] = ["vacation", "sick", "training", "other"];

// ---------------------------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema, FromRow)]
pub struct Settings {
    /// Minutes kept free between two consecutive jobs of a technician on the same day.
    pub travel_buffer_minutes: i32,
    /// Length assumed for a job without an end time.
    pub default_job_minutes: i32,
    /// Time zone of working hours and absences, e.g. `Europe/Brussels`.
    pub timezone: String,
}

impl Default for Settings {
    fn default() -> Self {
        Settings {
            travel_buffer_minutes: 15,
            default_job_minutes: 120,
            timezone: "Europe/Brussels".into(),
        }
    }
}

pub async fn load_settings(conn: &mut PgConnection, company_id: Uuid) -> AppResult<Settings> {
    let s: Option<Settings> = sqlx::query_as(
        "SELECT travel_buffer_minutes, default_job_minutes, timezone FROM planning.settings WHERE company_id = $1",
    )
    .bind(company_id)
    .fetch_optional(conn)
    .await?;
    Ok(s.unwrap_or_default())
}

/// The planning settings of the company (defaults until an administrator saves them).
#[utoipa::path(get, path = "/planning/settings", tag = "planning", operation_id = "get_planning_settings",
    responses((status = 200, body = Settings), (status = 403, body = ErrorBody)))]
async fn get_settings(
    State(state): State<AppState>,
    user: CurrentUser,
) -> AppResult<Json<Settings>> {
    user.require(Permission::PlanningRead)?;
    let mut conn = state.db.acquire().await?;
    Ok(Json(load_settings(&mut conn, user.company_id).await?))
}

#[utoipa::path(put, path = "/planning/settings", tag = "planning", operation_id = "update_planning_settings",
    request_body = Settings,
    responses((status = 200, body = Settings), (status = 403, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn update_settings(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<Settings>,
) -> AppResult<Json<Settings>> {
    user.require(Permission::PlanningAdmin)?;
    if !(0..=480).contains(&input.travel_buffer_minutes) {
        return Err(AppError::Validation(
            "the travel buffer must be 0 to 480 minutes".into(),
        ));
    }
    if !(15..=1440).contains(&input.default_job_minutes) {
        return Err(AppError::Validation(
            "the default job length must be 15 to 1440 minutes".into(),
        ));
    }
    let timezone = input.timezone.trim().to_string();
    let mut conn = state.db.acquire().await?;
    let known: bool =
        sqlx::query_scalar("SELECT EXISTS (SELECT 1 FROM pg_timezone_names WHERE name = $1)")
            .bind(&timezone)
            .fetch_one(&mut *conn)
            .await?;
    if !known {
        return Err(AppError::Validation("unknown time zone".into()));
    }
    sqlx::query(
        "INSERT INTO planning.settings (company_id, travel_buffer_minutes, default_job_minutes, timezone)
         VALUES ($1, $2, $3, $4)
         ON CONFLICT (company_id) DO UPDATE SET travel_buffer_minutes = $2, default_job_minutes = $3,
                timezone = $4, updated_at = now()",
    )
    .bind(user.company_id)
    .bind(input.travel_buffer_minutes)
    .bind(input.default_job_minutes)
    .bind(&timezone)
    .execute(&mut *conn)
    .await?;
    Ok(Json(load_settings(&mut conn, user.company_id).await?))
}

// ---------------------------------------------------------------------------------------------
// Working hours
// ---------------------------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, ToSchema, FromRow)]
pub struct TechnicianHours {
    pub id: Uuid,
    /// Empty for the company default.
    pub user_id: Option<Uuid>,
    /// 1 = Monday ... 7 = Sunday.
    pub weekday: i16,
    pub start_time: NaiveTime,
    pub end_time: NaiveTime,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct HoursSlotInput {
    pub weekday: i16,
    pub start_time: NaiveTime,
    pub end_time: NaiveTime,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct WorkingHoursInput {
    /// The user the hours are for; empty sets the company default.
    pub user_id: Option<Uuid>,
    /// Replaces all rows of that user (or of the default). No rows: the default applies again.
    pub slots: Vec<HoursSlotInput>,
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct HoursParams {
    /// Rows of this user only.
    pub user_id: Option<Uuid>,
    /// The company default rows.
    #[serde(default)]
    pub defaults: bool,
}

/// Members of the company, for the checks on the person a row is for.
pub async fn ensure_member(
    conn: &mut PgConnection,
    company_id: Uuid,
    user_id: Uuid,
) -> AppResult<()> {
    let ok: bool = sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM core.user_companies uc JOIN core.users u ON u.id = uc.user_id
                        WHERE uc.company_id = $1 AND uc.user_id = $2 AND u.active)",
    )
    .bind(company_id)
    .bind(user_id)
    .fetch_one(conn)
    .await?;
    if ok {
        Ok(())
    } else {
        Err(AppError::Validation(
            "the user is not an active member of the company".into(),
        ))
    }
}

/// Working hours: the rows of one user (themselves, or a planner), the company default rows
/// (`defaults=true`, anyone), or every row (planners).
#[utoipa::path(get, path = "/planning/working-hours", tag = "planning", operation_id = "list_working_hours",
    params(HoursParams), responses((status = 200, body = Vec<TechnicianHours>), (status = 403, body = ErrorBody)))]
async fn list_hours(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(p): Query<HoursParams>,
) -> AppResult<Json<Vec<TechnicianHours>>> {
    if !p.defaults && p.user_id != Some(user.user_id) {
        user.require(Permission::PlanningRead)?;
    }
    let rows = sqlx::query_as(
        "SELECT id, user_id, weekday, start_time, end_time FROM planning.working_hours
         WHERE company_id = $1 AND (NOT $3 OR user_id IS NULL) AND ($2::uuid IS NULL OR user_id = $2)
         ORDER BY user_id NULLS FIRST, weekday, start_time",
    )
    .bind(user.company_id)
    .bind(p.user_id)
    .bind(p.defaults)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows))
}

#[utoipa::path(put, path = "/planning/working-hours", tag = "planning", operation_id = "set_working_hours",
    request_body = WorkingHoursInput,
    responses((status = 200, body = Vec<TechnicianHours>), (status = 403, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn set_hours(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<WorkingHoursInput>,
) -> AppResult<Json<Vec<TechnicianHours>>> {
    user.require(Permission::PlanningAdmin)?;
    let mut slots = input.slots.clone();
    slots.sort_by_key(|s| (s.weekday, s.start_time));
    for s in &slots {
        if !(1..=7).contains(&s.weekday) {
            return Err(AppError::Validation(
                "the weekday must be 1 (Monday) to 7 (Sunday)".into(),
            ));
        }
        if s.end_time <= s.start_time {
            return Err(AppError::Validation(
                "a block must end after it starts".into(),
            ));
        }
    }
    if slots
        .windows(2)
        .any(|w| w[0].weekday == w[1].weekday && w[1].start_time < w[0].end_time)
    {
        return Err(AppError::Validation(
            "blocks on the same day must not overlap".into(),
        ));
    }
    let mut tx = state.db.begin().await?;
    if let Some(u) = input.user_id {
        ensure_member(&mut tx, user.company_id, u).await?;
    }
    sqlx::query("DELETE FROM planning.working_hours WHERE company_id = $1 AND user_id IS NOT DISTINCT FROM $2")
        .bind(user.company_id)
        .bind(input.user_id)
        .execute(&mut *tx)
        .await?;
    for s in &slots {
        sqlx::query(
            "INSERT INTO planning.working_hours (id, company_id, user_id, weekday, start_time, end_time)
             VALUES ($1, $2, $3, $4, $5, $6)",
        )
        .bind(new_id())
        .bind(user.company_id)
        .bind(input.user_id)
        .bind(s.weekday)
        .bind(s.start_time)
        .bind(s.end_time)
        .execute(&mut *tx)
        .await?;
    }
    let rows = sqlx::query_as(
        "SELECT id, user_id, weekday, start_time, end_time FROM planning.working_hours
         WHERE company_id = $1 AND user_id IS NOT DISTINCT FROM $2 ORDER BY weekday, start_time",
    )
    .bind(user.company_id)
    .bind(input.user_id)
    .fetch_all(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(Json(rows))
}

// ---------------------------------------------------------------------------------------------
// Absences
// ---------------------------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, ToSchema, FromRow)]
pub struct Absence {
    pub id: Uuid,
    pub user_id: Uuid,
    pub user_name: String,
    pub from_date: NaiveDate,
    /// Inclusive.
    pub to_date: NaiveDate,
    /// vacation | sick | training | other
    pub kind: String,
    pub note: String,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct AbsenceInput {
    pub user_id: Uuid,
    #[serde(deserialize_with = "date")]
    pub from_date: NaiveDate,
    #[serde(deserialize_with = "date")]
    pub to_date: NaiveDate,
    pub kind: String,
    #[serde(default)]
    pub note: String,
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct AbsenceParams {
    pub user_id: Option<Uuid>,
    /// Absences ending on or after this day.
    #[serde(default, deserialize_with = "opt_date")]
    pub from: Option<NaiveDate>,
    /// Absences starting on or before this day.
    #[serde(default, deserialize_with = "opt_date")]
    pub to: Option<NaiveDate>,
}

const ABSENCE_SELECT: &str =
    "SELECT a.id, a.user_id, u.display_name AS user_name, a.from_date, a.to_date, a.kind, a.note
     FROM planning.absences a JOIN core.users u ON u.id = a.user_id";

/// Absences of the company in a period (planners), or of oneself.
#[utoipa::path(get, path = "/planning/absences", tag = "planning", operation_id = "list_absences",
    params(AbsenceParams), responses((status = 200, body = Vec<Absence>), (status = 403, body = ErrorBody)))]
async fn list_absences(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(p): Query<AbsenceParams>,
) -> AppResult<Json<Vec<Absence>>> {
    if p.user_id != Some(user.user_id) {
        user.require(Permission::PlanningRead)?;
    }
    let rows = sqlx::query_as(sqlx::AssertSqlSafe(format!(
        "{ABSENCE_SELECT} WHERE a.company_id = $1 AND ($2::uuid IS NULL OR a.user_id = $2)
           AND ($3::date IS NULL OR a.to_date >= $3) AND ($4::date IS NULL OR a.from_date <= $4)
         ORDER BY a.from_date, u.display_name LIMIT 500"
    )))
    .bind(user.company_id)
    .bind(p.user_id)
    .bind(p.from)
    .bind(p.to)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows))
}

fn check_absence(input: &AbsenceInput) -> AppResult<()> {
    if !ABSENCE_KINDS.contains(&input.kind.as_str()) {
        return Err(AppError::Validation(format!(
            "kind must be one of {}",
            ABSENCE_KINDS.join(", ")
        )));
    }
    if input.to_date < input.from_date {
        return Err(AppError::Validation(
            "the absence must not end before it starts".into(),
        ));
    }
    Ok(())
}

async fn load_absence(conn: &mut PgConnection, company_id: Uuid, id: Uuid) -> AppResult<Absence> {
    sqlx::query_as(sqlx::AssertSqlSafe(format!(
        "{ABSENCE_SELECT} WHERE a.id = $1 AND a.company_id = $2"
    )))
    .bind(id)
    .bind(company_id)
    .fetch_optional(conn)
    .await?
    .ok_or(AppError::NotFound("absence"))
}

#[utoipa::path(post, path = "/planning/absences", tag = "planning", operation_id = "create_absence",
    request_body = AbsenceInput,
    responses((status = 201, body = Absence), (status = 403, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn create_absence(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<AbsenceInput>,
) -> AppResult<(StatusCode, Json<Absence>)> {
    user.require(Permission::PlanningWrite)?;
    check_absence(&input)?;
    let mut tx = state.db.begin().await?;
    ensure_member(&mut tx, user.company_id, input.user_id).await?;
    let id = new_id();
    sqlx::query(
        "INSERT INTO planning.absences (id, company_id, user_id, from_date, to_date, kind, note, created_by)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(input.user_id)
    .bind(input.from_date)
    .bind(input.to_date)
    .bind(&input.kind)
    .bind(input.note.trim())
    .bind(user.user_id)
    .execute(&mut *tx)
    .await?;
    let a = load_absence(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(a)))
}

#[utoipa::path(put, path = "/planning/absences/{id}", tag = "planning", operation_id = "update_absence",
    params(("id" = Uuid, Path)), request_body = AbsenceInput,
    responses((status = 200, body = Absence), (status = 403, body = ErrorBody), (status = 404, body = ErrorBody)))]
async fn update_absence(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<AbsenceInput>,
) -> AppResult<Json<Absence>> {
    user.require(Permission::PlanningWrite)?;
    check_absence(&input)?;
    let mut tx = state.db.begin().await?;
    load_absence(&mut tx, user.company_id, id).await?;
    ensure_member(&mut tx, user.company_id, input.user_id).await?;
    sqlx::query(
        "UPDATE planning.absences SET user_id = $2, from_date = $3, to_date = $4, kind = $5, note = $6 WHERE id = $1",
    )
    .bind(id)
    .bind(input.user_id)
    .bind(input.from_date)
    .bind(input.to_date)
    .bind(&input.kind)
    .bind(input.note.trim())
    .execute(&mut *tx)
    .await?;
    let a = load_absence(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok(Json(a))
}

#[utoipa::path(delete, path = "/planning/absences/{id}", tag = "planning", operation_id = "delete_absence",
    params(("id" = Uuid, Path)),
    responses((status = 204), (status = 403, body = ErrorBody), (status = 404, body = ErrorBody)))]
async fn delete_absence(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<StatusCode> {
    user.require(Permission::PlanningWrite)?;
    let n = sqlx::query("DELETE FROM planning.absences WHERE id = $1 AND company_id = $2")
        .bind(id)
        .bind(user.company_id)
        .execute(&state.db)
        .await?
        .rows_affected();
    if n == 0 {
        return Err(AppError::NotFound("absence"));
    }
    Ok(StatusCode::NO_CONTENT)
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(get_settings, update_settings))
        .routes(routes!(list_hours, set_hours))
        .routes(routes!(list_absences, create_absence))
        .routes(routes!(update_absence, delete_absence))
}
