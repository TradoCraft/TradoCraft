//! Planning board for field jobs: who can do which job when.
//!
//! Planners (`planning.write`) schedule and assign jobs on a board of technicians. Technicians
//! have working hours (their own, else the company default), absences and skills; jobs may require
//! skills. Placing a job yields typed conflicts (double booking including a travel buffer, absence,
//! outside working hours, missing skill, crossing days), see [`conflicts`]. The calendar tables are
//! shaped so that work centres can reuse them later (ADR 0024).
//!
//! Working hours and absences are local to the company's time zone; job times are instants. All
//! conversions happen in the database (`AT TIME ZONE`), so the pure functions only see local times.

use std::collections::HashMap;

use axum::extract::{Path, Query, State};
use axum::Json;
use chrono::{DateTime, Duration, NaiveDate, NaiveDateTime, NaiveTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection};
use tradocraft_core::serde_util::{date, opt_date};
use tradocraft_core::{audit, AppError, AppResult, AppState, CurrentUser, Permission};
use utoipa::{IntoParams, ToSchema};
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

pub mod calendar;
pub mod conflicts;
pub mod notify;
pub mod skills;
pub mod suggest;

use calendar::{load_settings, Absence, Settings, TechnicianHours};
use conflicts::{detect, has_errors, BookedJob, Candidate, Conflict, HoursSlot, ResourceCalendar};
use skills::{list_skills_inner, Skill, UserSkill};
use suggest::SuggestionOut;

type ErrorBody = tradocraft_core::error::ErrorBody;

/// The longest period one board request may cover.
const MAX_DAYS: i64 = 62;

// ---------------------------------------------------------------------------------------------
// Time zone conversions (done by the database, which knows the zone rules)
// ---------------------------------------------------------------------------------------------

async fn local_of(
    conn: &mut PgConnection,
    tz: &str,
    at: DateTime<Utc>,
) -> AppResult<NaiveDateTime> {
    Ok(sqlx::query_scalar("SELECT $1::timestamptz AT TIME ZONE $2")
        .bind(at)
        .bind(tz)
        .fetch_one(conn)
        .await?)
}

async fn utc_of(
    conn: &mut PgConnection,
    tz: &str,
    local: NaiveDateTime,
) -> AppResult<DateTime<Utc>> {
    Ok(sqlx::query_scalar("SELECT $1::timestamp AT TIME ZONE $2")
        .bind(local)
        .bind(tz)
        .fetch_one(conn)
        .await?)
}

async fn midnight_utc(
    conn: &mut PgConnection,
    tz: &str,
    day: NaiveDate,
) -> AppResult<DateTime<Utc>> {
    utc_of(conn, tz, day.and_time(NaiveTime::MIN)).await
}

// ---------------------------------------------------------------------------------------------
// Technicians and their calendars
// ---------------------------------------------------------------------------------------------

#[derive(FromRow)]
struct TechRow {
    id: Uuid,
    display_name: String,
}

/// Active users of the company with the technician role, by name.
async fn technicians(conn: &mut PgConnection, company_id: Uuid) -> AppResult<Vec<TechRow>> {
    Ok(sqlx::query_as(
        "SELECT u.id, u.display_name FROM core.users u
         JOIN core.user_companies uc ON uc.user_id = u.id AND uc.company_id = $1
         WHERE u.active AND 'technician' = ANY(uc.roles) ORDER BY u.display_name, u.id",
    )
    .bind(company_id)
    .fetch_all(conn)
    .await?)
}

#[derive(FromRow)]
struct HoursRow {
    user_id: Option<Uuid>,
    weekday: i16,
    start_time: NaiveTime,
    end_time: NaiveTime,
}

#[derive(FromRow)]
struct BookedRow {
    user_id: Uuid,
    id: Uuid,
    start: NaiveDateTime,
    end: NaiveDateTime,
}

/// The calendars of `users` for placing a job around `[from, to)`: effective hours, absences,
/// skills and the jobs they already have (not counting `exclude_job`).
async fn load_calendars(
    conn: &mut PgConnection,
    company_id: Uuid,
    settings: &Settings,
    users: &[Uuid],
    from: DateTime<Utc>,
    to: DateTime<Utc>,
    exclude_job: Option<Uuid>,
) -> AppResult<Vec<ResourceCalendar>> {
    let tz = settings.timezone.as_str();
    let hours: Vec<HoursRow> = sqlx::query_as(
        "SELECT user_id, weekday, start_time, end_time FROM planning.working_hours
         WHERE company_id = $1 AND (user_id = ANY($2) OR user_id IS NULL)",
    )
    .bind(company_id)
    .bind(users)
    .fetch_all(&mut *conn)
    .await?;
    let slot = |h: &HoursRow| HoursSlot {
        weekday: h.weekday as u32,
        start: h.start_time,
        end: h.end_time,
    };
    let defaults: Vec<HoursSlot> = hours
        .iter()
        .filter(|h| h.user_id.is_none())
        .map(slot)
        .collect();

    let (from_day, to_day) = (
        local_of(conn, tz, from).await?.date(),
        local_of(conn, tz, to).await?.date(),
    );
    let absences: Vec<(Uuid, NaiveDate, NaiveDate)> = sqlx::query_as(
        "SELECT user_id, from_date, to_date FROM planning.absences
         WHERE company_id = $1 AND user_id = ANY($2) AND to_date >= $3 AND from_date <= $4",
    )
    .bind(company_id)
    .bind(users)
    .bind(from_day)
    .bind(to_day)
    .fetch_all(&mut *conn)
    .await?;
    let skills: Vec<(Uuid, Uuid)> =
        sqlx::query_as("SELECT user_id, skill_id FROM planning.user_skills WHERE company_id = $1 AND user_id = ANY($2)")
            .bind(company_id)
            .bind(users)
            .fetch_all(&mut *conn)
            .await?;
    let booked: Vec<BookedRow> = sqlx::query_as(
        "SELECT jt.user_id, j.id, (j.scheduled_start AT TIME ZONE $3) AS start,
                (coalesce(j.scheduled_end, j.scheduled_start + make_interval(mins => $4)) AT TIME ZONE $3) AS \"end\"
         FROM field.job_technicians jt JOIN field.jobs j ON j.id = jt.job_id
         WHERE j.company_id = $1 AND jt.user_id = ANY($2) AND j.status IN ('planned', 'in_progress')
           AND j.scheduled_start IS NOT NULL AND ($5::uuid IS NULL OR j.id <> $5)
           AND j.scheduled_start < $7 AND coalesce(j.scheduled_end, j.scheduled_start + make_interval(mins => $4)) > $6",
    )
    .bind(company_id)
    .bind(users)
    .bind(tz)
    .bind(settings.default_job_minutes)
    .bind(exclude_job)
    .bind(from - Duration::days(1))
    .bind(to + Duration::days(1))
    .fetch_all(&mut *conn)
    .await?;

    Ok(users
        .iter()
        .map(|u| {
            let own: Vec<HoursSlot> = hours
                .iter()
                .filter(|h| h.user_id == Some(*u))
                .map(slot)
                .collect();
            ResourceCalendar {
                id: *u,
                hours: if own.is_empty() {
                    defaults.clone()
                } else {
                    own
                },
                absences: absences
                    .iter()
                    .filter(|a| a.0 == *u)
                    .map(|a| (a.1, a.2))
                    .collect(),
                skills: skills.iter().filter(|s| s.0 == *u).map(|s| s.1).collect(),
                booked: booked
                    .iter()
                    .filter(|b| b.user_id == *u)
                    .map(|b| BookedJob {
                        id: b.id,
                        start: b.start,
                        end: b.end,
                    })
                    .collect(),
            }
        })
        .collect())
}

// ---------------------------------------------------------------------------------------------
// The board
// ---------------------------------------------------------------------------------------------

/// A job as the board shows it.
#[derive(Debug, Clone, Serialize, ToSchema, FromRow)]
pub struct BoardJob {
    pub id: Uuid,
    pub number: String,
    pub title: String,
    /// installation | maintenance | repair | inspection | other
    pub kind: String,
    /// planned | in_progress | completed | cancelled
    pub status: String,
    /// low | normal | high | urgent
    pub priority: String,
    pub customer_id: Uuid,
    pub customer_name: String,
    pub city: String,
    pub due_date: Option<NaiveDate>,
    pub scheduled_start: Option<DateTime<Utc>>,
    pub scheduled_end: Option<DateTime<Utc>>,
    pub technician_ids: Vec<Uuid>,
    pub required_skill_ids: Vec<Uuid>,
}

const BOARD_SELECT: &str = "SELECT j.id, j.number, j.title, j.kind, j.status, j.priority, j.customer_id,
        c.name AS customer_name, j.city, j.due_date, j.scheduled_start, j.scheduled_end,
        coalesce((SELECT array_agg(t.user_id ORDER BY t.user_id) FROM field.job_technicians t WHERE t.job_id = j.id), '{}') AS technician_ids,
        coalesce((SELECT array_agg(r.skill_id ORDER BY r.skill_id) FROM field.job_required_skills r WHERE r.job_id = j.id), '{}') AS required_skill_ids
     FROM field.jobs j JOIN crm.customers c ON c.id = j.customer_id";

#[derive(Debug, Serialize, ToSchema)]
pub struct BoardTechnician {
    pub user_id: Uuid,
    pub display_name: String,
    pub skills: Vec<UserSkill>,
    /// The hours that apply: their own, else the company default.
    pub working_hours: Vec<TechnicianHours>,
    /// True when `working_hours` are the company default.
    pub hours_are_default: bool,
    /// Absences touching the requested period.
    pub absences: Vec<Absence>,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct Board {
    pub from: NaiveDate,
    pub to: NaiveDate,
    pub settings: Settings,
    pub technicians: Vec<BoardTechnician>,
    /// The skills catalogue (for filters).
    pub skills: Vec<Skill>,
    /// Assigned jobs scheduled in the period.
    pub jobs: Vec<BoardJob>,
    /// Open jobs without a schedule or without a technician, most urgent first.
    pub backlog: Vec<BoardJob>,
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct BoardParams {
    /// First day (in the company's time zone).
    #[serde(deserialize_with = "date")]
    pub from: NaiveDate,
    /// Last day, inclusive.
    #[serde(deserialize_with = "date")]
    pub to: NaiveDate,
}

/// Technicians with skills, working hours and absences, the jobs scheduled in the period, and the
/// backlog of jobs still to plan.
#[utoipa::path(get, path = "/planning/board", tag = "planning", operation_id = "get_planning_board",
    params(BoardParams),
    responses((status = 200, body = Board), (status = 403, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn get_board(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(p): Query<BoardParams>,
) -> AppResult<Json<Board>> {
    user.require(Permission::PlanningRead)?;
    if p.to < p.from || (p.to - p.from).num_days() >= MAX_DAYS {
        return Err(AppError::Validation(format!(
            "choose a period of 1 to {MAX_DAYS} days"
        )));
    }
    let cid = user.company_id;
    let mut conn = state.db.acquire().await?;
    let settings = load_settings(&mut conn, cid).await?;
    let tz = settings.timezone.clone();
    let from = midnight_utc(&mut conn, &tz, p.from).await?;
    let to = midnight_utc(&mut conn, &tz, p.to + Duration::days(1)).await?;

    let techs = technicians(&mut conn, cid).await?;
    let hours: Vec<TechnicianHours> = sqlx::query_as(
        "SELECT id, user_id, weekday, start_time, end_time FROM planning.working_hours
         WHERE company_id = $1 ORDER BY weekday, start_time",
    )
    .bind(cid)
    .fetch_all(&mut *conn)
    .await?;
    let skill_rows: Vec<(Uuid, UserSkill)> = {
        #[derive(FromRow)]
        struct Row {
            user_id: Uuid,
            skill_id: Uuid,
            code: String,
            name: String,
            level: i16,
        }
        let rows: Vec<Row> = sqlx::query_as(
            "SELECT us.user_id, s.id AS skill_id, s.code, s.name, us.level FROM planning.user_skills us
             JOIN planning.skills s ON s.id = us.skill_id WHERE us.company_id = $1 ORDER BY s.name, s.code",
        )
        .bind(cid)
        .fetch_all(&mut *conn)
        .await?;
        rows.into_iter()
            .map(|r| {
                (
                    r.user_id,
                    UserSkill {
                        skill_id: r.skill_id,
                        code: r.code,
                        name: r.name,
                        level: r.level,
                    },
                )
            })
            .collect()
    };
    let absences: Vec<(Absence, Uuid)> = {
        let rows: Vec<Absence> = sqlx::query_as(
            "SELECT a.id, a.user_id, u.display_name AS user_name, a.from_date, a.to_date, a.kind, a.note
             FROM planning.absences a JOIN core.users u ON u.id = a.user_id
             WHERE a.company_id = $1 AND a.to_date >= $2 AND a.from_date <= $3 ORDER BY a.from_date",
        )
        .bind(cid)
        .bind(p.from)
        .bind(p.to)
        .fetch_all(&mut *conn)
        .await?;
        rows.into_iter()
            .map(|a| {
                let u = a.user_id;
                (a, u)
            })
            .collect()
    };
    let defaults: Vec<TechnicianHours> = hours
        .iter()
        .filter(|h| h.user_id.is_none())
        .cloned()
        .collect();
    let technicians = techs
        .into_iter()
        .map(|t| {
            let own: Vec<TechnicianHours> = hours
                .iter()
                .filter(|h| h.user_id == Some(t.id))
                .cloned()
                .collect();
            let hours_are_default = own.is_empty();
            BoardTechnician {
                user_id: t.id,
                display_name: t.display_name,
                skills: skill_rows
                    .iter()
                    .filter(|s| s.0 == t.id)
                    .map(|s| s.1.clone())
                    .collect(),
                working_hours: if hours_are_default {
                    defaults.clone()
                } else {
                    own
                },
                hours_are_default,
                absences: absences
                    .iter()
                    .filter(|a| a.1 == t.id)
                    .map(|a| a.0.clone())
                    .collect(),
            }
        })
        .collect();

    let jobs: Vec<BoardJob> = sqlx::query_as(sqlx::AssertSqlSafe(format!(
        "{BOARD_SELECT} WHERE j.company_id = $1 AND j.status <> 'cancelled' AND j.scheduled_start IS NOT NULL
           AND j.scheduled_start < $3 AND coalesce(j.scheduled_end, j.scheduled_start + make_interval(mins => $4)) > $2
           AND EXISTS (SELECT 1 FROM field.job_technicians t WHERE t.job_id = j.id)
         ORDER BY j.scheduled_start, j.number"
    )))
    .bind(cid)
    .bind(from)
    .bind(to)
    .bind(settings.default_job_minutes)
    .fetch_all(&mut *conn)
    .await?;
    let backlog: Vec<BoardJob> = sqlx::query_as(sqlx::AssertSqlSafe(format!(
        "{BOARD_SELECT} WHERE j.company_id = $1 AND j.status = 'planned'
           AND (j.scheduled_start IS NULL OR NOT EXISTS (SELECT 1 FROM field.job_technicians t WHERE t.job_id = j.id))
         ORDER BY CASE j.priority WHEN 'urgent' THEN 0 WHEN 'high' THEN 1 WHEN 'normal' THEN 2 ELSE 3 END,
                  j.due_date NULLS LAST, j.created_at LIMIT 200"
    )))
    .bind(cid)
    .fetch_all(&mut *conn)
    .await?;
    let skills = list_skills_inner(&mut conn, cid).await?;
    Ok(Json(Board {
        from: p.from,
        to: p.to,
        settings,
        technicians,
        skills,
        jobs,
        backlog,
    }))
}

// ---------------------------------------------------------------------------------------------
// Scheduling
// ---------------------------------------------------------------------------------------------

#[derive(Debug, Deserialize, ToSchema)]
pub struct ScheduleInput {
    pub scheduled_start: DateTime<Utc>,
    pub scheduled_end: DateTime<Utc>,
    /// Replaces the technicians of the job.
    pub technician_ids: Vec<Uuid>,
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct ScheduleParams {
    /// Only report the conflicts; change nothing (used while dragging).
    #[serde(default)]
    pub dry_run: bool,
    /// Schedule although there are errors (e.g. a technician on holiday).
    #[serde(default)]
    pub force: bool,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct ScheduleResult {
    /// False for a dry run.
    pub applied: bool,
    pub conflicts: Vec<Conflict>,
    /// The job after the change.
    pub job: Option<BoardJob>,
}

/// A job's current appointment (start, end).
type Appointment = (Option<DateTime<Utc>>, Option<DateTime<Utc>>);

#[derive(FromRow)]
struct JobState {
    number: String,
    title: String,
    status: String,
    city: String,
    customer_name: String,
    scheduled_start: Option<DateTime<Utc>>,
    scheduled_end: Option<DateTime<Utc>>,
}

/// Schedules a job and assigns its technicians in one step. Completed and cancelled jobs are
/// refused (409). Errors among the conflicts (a double booking, an absence) refuse the change
/// (409) unless `force=true`; warnings never do. The conflicts are returned either way.
/// The assigned technicians are told by mail (not the planner).
#[utoipa::path(put, path = "/planning/jobs/{id}/schedule", tag = "planning", operation_id = "schedule_job",
    params(("id" = Uuid, Path), ScheduleParams), request_body = ScheduleInput,
    responses((status = 200, body = ScheduleResult), (status = 403, body = ErrorBody), (status = 404, body = ErrorBody),
        (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn schedule_job(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Query(p): Query<ScheduleParams>,
    Json(input): Json<ScheduleInput>,
) -> AppResult<Json<ScheduleResult>> {
    user.require(Permission::PlanningWrite)?;
    if input.scheduled_end <= input.scheduled_start {
        return Err(AppError::Validation(
            "the job must end after it starts".into(),
        ));
    }
    let cid = user.company_id;
    let mut tx = state.db.begin().await?;
    let job: JobState = sqlx::query_as(
        "SELECT j.number, j.title, j.status, j.city, c.name AS customer_name, j.scheduled_start, j.scheduled_end
         FROM field.jobs j JOIN crm.customers c ON c.id = j.customer_id
         WHERE j.id = $1 AND j.company_id = $2 FOR UPDATE OF j",
    )
    .bind(id)
    .bind(cid)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or(AppError::NotFound("job"))?;
    if matches!(job.status.as_str(), "completed" | "cancelled") {
        return Err(AppError::Conflict(format!("the job is {}", job.status)));
    }
    let mut techs = input.technician_ids.clone();
    techs.sort();
    techs.dedup();
    for t in &techs {
        calendar::ensure_member(&mut tx, cid, *t).await?;
    }

    let settings = load_settings(&mut tx, cid).await?;
    let tz = settings.timezone.clone();
    let start = local_of(&mut tx, &tz, input.scheduled_start).await?;
    let end = local_of(&mut tx, &tz, input.scheduled_end).await?;
    let required: Vec<Uuid> = sqlx::query_scalar(
        "SELECT skill_id FROM field.job_required_skills WHERE job_id = $1 ORDER BY skill_id",
    )
    .bind(id)
    .fetch_all(&mut *tx)
    .await?;
    let calendars = load_calendars(
        &mut tx,
        cid,
        &settings,
        &techs,
        input.scheduled_start,
        input.scheduled_end,
        Some(id),
    )
    .await?;
    let found = detect(
        &Candidate {
            start,
            end,
            required_skills: &required,
        },
        i64::from(settings.travel_buffer_minutes),
        &calendars,
    );
    if p.dry_run {
        return Ok(Json(ScheduleResult {
            applied: false,
            conflicts: found,
            job: None,
        }));
    }
    if has_errors(&found) && !p.force {
        let keys: Vec<&str> = found
            .iter()
            .filter(|c| c.severity == conflicts::Severity::Error)
            .map(|c| c.message_key.as_str())
            .collect();
        return Err(AppError::Conflict(format!(
            "scheduling conflicts: {}; confirm with force",
            keys.join(", ")
        )));
    }

    let before: Vec<Uuid> =
        sqlx::query_scalar("SELECT user_id FROM field.job_technicians WHERE job_id = $1")
            .bind(id)
            .fetch_all(&mut *tx)
            .await?;
    tradocraft_fieldservice::set_technicians(&mut tx, id, &techs).await?;
    sqlx::query("UPDATE field.jobs SET scheduled_start = $2, scheduled_end = $3, updated_at = now() WHERE id = $1")
        .bind(id)
        .bind(input.scheduled_start)
        .bind(input.scheduled_end)
        .execute(&mut *tx)
        .await?;
    audit::record(
        &mut tx,
        &user,
        "job",
        id,
        "scheduled",
        serde_json::json!({
            "scheduled_start": input.scheduled_start, "scheduled_end": input.scheduled_end,
            "technician_ids": techs, "forced": p.force && has_errors(&found),
            "conflicts": found.iter().map(|c| c.message_key.as_str()).collect::<Vec<_>>(),
        }),
    )
    .await?;

    let moved = job.scheduled_start != Some(input.scheduled_start)
        || job.scheduled_end != Some(input.scheduled_end);
    let me = user.user_id;
    let added: Vec<Uuid> = techs
        .iter()
        .copied()
        .filter(|t| *t != me && !before.contains(t))
        .collect();
    let kept: Vec<Uuid> = techs
        .iter()
        .copied()
        .filter(|t| *t != me && before.contains(t))
        .collect();
    let mail = notify::JobMail {
        number: &job.number,
        title: &job.title,
        customer: &job.customer_name,
        city: &job.city,
        start,
        end,
    };
    notify::send(&mut tx, cid, &added, notify::Kind::Assigned, &mail).await?;
    if moved {
        notify::send(&mut tx, cid, &kept, notify::Kind::Rescheduled, &mail).await?;
    }
    let out: BoardJob = sqlx::query_as(sqlx::AssertSqlSafe(format!("{BOARD_SELECT} WHERE j.id = $1")))
        .bind(id)
        .fetch_one(&mut *tx)
        .await?;
    tx.commit().await?;
    Ok(Json(ScheduleResult {
        applied: true,
        conflicts: found,
        job: Some(out),
    }))
}

// ---------------------------------------------------------------------------------------------
// Suggestions
// ---------------------------------------------------------------------------------------------

#[derive(Debug, Deserialize, IntoParams)]
pub struct SuggestParams {
    /// First day to look at (default today).
    #[serde(default, deserialize_with = "opt_date")]
    pub from: Option<NaiveDate>,
    /// Last day, inclusive (default six days after `from`).
    #[serde(default, deserialize_with = "opt_date")]
    pub to: Option<NaiveDate>,
}

/// Ranked technician and slot suggestions for a job: technicians with the required skills first,
/// then the earliest day, then the slot that leaves the least unused time in its gap. Slots lie
/// inside working hours, outside absences and keep the travel buffer to other jobs.
#[utoipa::path(get, path = "/planning/suggestions/{job_id}", tag = "planning", operation_id = "suggest_slots",
    params(("job_id" = Uuid, Path), SuggestParams),
    responses((status = 200, body = Vec<SuggestionOut>), (status = 403, body = ErrorBody), (status = 404, body = ErrorBody)))]
async fn suggestions(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(job_id): Path<Uuid>,
    Query(p): Query<SuggestParams>,
) -> AppResult<Json<Vec<SuggestionOut>>> {
    user.require(Permission::PlanningRead)?;
    let from = p.from.unwrap_or_else(tradocraft_core::today);
    let to = p.to.unwrap_or(from + Duration::days(6));
    if to < from || (to - from).num_days() >= 31 {
        return Err(AppError::Validation(
            "choose a period of 1 to 31 days".into(),
        ));
    }
    let cid = user.company_id;
    let mut conn = state.db.acquire().await?;
    let job: Option<Appointment> = sqlx::query_as(
        "SELECT scheduled_start, scheduled_end FROM field.jobs WHERE id = $1 AND company_id = $2",
    )
    .bind(job_id)
    .bind(cid)
    .fetch_optional(&mut *conn)
    .await?;
    let (js, je) = job.ok_or(AppError::NotFound("job"))?;
    let settings = load_settings(&mut conn, cid).await?;
    let tz = settings.timezone.clone();
    let duration = match (js, je) {
        (Some(s), Some(e)) if e > s => (e - s).num_minutes(),
        _ => i64::from(settings.default_job_minutes),
    };
    let required: Vec<Uuid> = sqlx::query_scalar(
        "SELECT skill_id FROM field.job_required_skills WHERE job_id = $1 ORDER BY skill_id",
    )
    .bind(job_id)
    .fetch_all(&mut *conn)
    .await?;
    let techs = technicians(&mut conn, cid).await?;
    let ids: Vec<Uuid> = techs.iter().map(|t| t.id).collect();
    let (win_from, win_to) = (
        midnight_utc(&mut conn, &tz, from).await?,
        midnight_utc(&mut conn, &tz, to + Duration::days(1)).await?,
    );
    let calendars = load_calendars(
        &mut conn,
        cid,
        &settings,
        &ids,
        win_from,
        win_to,
        Some(job_id),
    )
    .await?;
    let found = suggest::suggest(
        duration,
        i64::from(settings.travel_buffer_minutes),
        &required,
        from,
        to,
        &calendars,
        10,
    );
    let names: HashMap<Uuid, String> = techs.into_iter().map(|t| (t.id, t.display_name)).collect();
    let mut out = Vec::new();
    for s in found {
        out.push(SuggestionOut {
            technician_id: s.technician_id,
            technician_name: names.get(&s.technician_id).cloned().unwrap_or_default(),
            scheduled_start: utc_of(&mut conn, &tz, s.start).await?,
            scheduled_end: utc_of(&mut conn, &tz, s.end).await?,
            missing_skill_ids: s.missing_skills,
            slack_minutes: s.slack_minutes,
        });
    }
    Ok(Json(out))
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(get_board))
        .routes(routes!(schedule_job))
        .routes(routes!(suggestions))
        .merge(calendar::router())
        .merge(skills::router())
}
