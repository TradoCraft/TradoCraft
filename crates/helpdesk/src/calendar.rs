//! The company's business calendar for the SLA: working weekdays with opening hours, a time zone
//! and holidays. The arithmetic is in [`crate::sla`]; this file stores and serves the settings.

use std::collections::hash_map::Entry;
use std::collections::{BTreeSet, HashMap};

use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::Json;
use chrono::{NaiveDate, NaiveTime};
use chrono_tz::Tz;
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection};
use tradocraft_core::{audit, new_id, AppError, AppResult, AppState, CurrentUser, Permission};
use utoipa::{IntoParams, ToSchema};
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::sla::Calendar;

type ErrorBody = tradocraft_core::error::ErrorBody;

pub const DEFAULT_TIME_ZONE: &str = "Europe/Brussels";

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct WorkingHours {
    /// 1 = Monday ... 7 = Sunday. A weekday that is not listed is closed.
    pub weekday: i16,
    /// `HH:MM`, local time.
    pub start_time: String,
    pub end_time: String,
}

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct Holiday {
    pub id: Uuid,
    pub day: NaiveDate,
    pub name: String,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct BusinessCalendar {
    /// The team this calendar is for; absent for the company calendar.
    pub team_id: Option<Uuid>,
    /// A team that has no calendar of its own: what is shown is the company's.
    pub inherited: bool,
    /// Set for a team: the company holidays count for it as well as the holidays listed (the team's own, or the company's when the team has no calendar of its own).
    pub holidays_inherited: bool,
    /// When off, SLA times are plain elapsed time.
    pub enabled: bool,
    /// An IANA name such as `Europe/Brussels`.
    pub time_zone: String,
    pub hours: Vec<WorkingHours>,
    pub holidays: Vec<Holiday>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct CalendarInput {
    pub enabled: bool,
    pub time_zone: String,
    pub hours: Vec<WorkingHours>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct HolidayInput {
    #[serde(deserialize_with = "tradocraft_core::serde_util::date")]
    pub day: NaiveDate,
    pub name: String,
}

fn parse_time(s: &str) -> AppResult<NaiveTime> {
    NaiveTime::parse_from_str(s, "%H:%M")
        .or_else(|_| NaiveTime::parse_from_str(s, "%H:%M:%S"))
        .map_err(|_| AppError::Validation(format!("{s:?} is not a time (HH:MM)")))
}

fn fmt_time(t: NaiveTime) -> String {
    t.format("%H:%M").to_string()
}

/// The default week: Monday to Friday, 09:00-17:00.
fn default_hours() -> Vec<WorkingHours> {
    (1..=5)
        .map(|weekday| WorkingHours {
            weekday,
            start_time: "09:00".into(),
            end_time: "17:00".into(),
        })
        .collect()
}

/// The calendar row that applies to a team: its own, else the company's. Returns the scope the
/// row belongs to (`None` = company), `enabled` and the time zone.
async fn find_calendar(
    conn: &mut PgConnection,
    company_id: Uuid,
    team_id: Option<Uuid>,
) -> Result<Option<(Option<Uuid>, bool, String)>, sqlx::Error> {
    sqlx::query_as(
        "SELECT team_id, enabled, time_zone FROM helpdesk.business_calendars
         WHERE company_id = $1 AND (team_id IS NULL OR team_id = $2)
         ORDER BY team_id NULLS LAST LIMIT 1",
    )
    .bind(company_id)
    .bind(team_id)
    .fetch_optional(conn)
    .await
}

/// The holidays kept for one calendar scope: a team's own, or the company's when `scope` is
/// `None`. A team's calendar counts these and the company's.
async fn find_holidays(
    conn: &mut PgConnection,
    company_id: Uuid,
    scope: Option<Uuid>,
) -> Result<Vec<Holiday>, sqlx::Error> {
    sqlx::query_as(
        "SELECT id, day, name FROM helpdesk.holidays
         WHERE company_id = $1 AND team_id IS NOT DISTINCT FROM $2 ORDER BY day",
    )
    .bind(company_id)
    .bind(scope)
    .fetch_all(conn)
    .await
}

/// The calendar SLA times are measured with for a ticket of `team_id`, or `None` when there is
/// none or it is switched off (then plain elapsed time applies). A team without a calendar of its
/// own uses the company's; a team calendar that is off means elapsed time for that team.
pub async fn load_calendar(
    conn: &mut PgConnection,
    company_id: Uuid,
    team_id: Option<Uuid>,
) -> Result<Option<Calendar>, sqlx::Error> {
    let Some((scope, true, zone)) = find_calendar(conn, company_id, team_id).await? else {
        return Ok(None);
    };
    let Ok(tz) = zone.parse::<Tz>() else {
        return Ok(None);
    };
    let hours: Vec<(i16, NaiveTime, NaiveTime)> = sqlx::query_as(
        "SELECT weekday, start_time, end_time FROM helpdesk.business_hours
         WHERE company_id = $1 AND team_id IS NOT DISTINCT FROM $2",
    )
    .bind(company_id)
    .bind(scope)
    .fetch_all(&mut *conn)
    .await?;
    let mut holidays = find_holidays(conn, company_id, scope).await?;
    if scope.is_some() {
        holidays.extend(find_holidays(conn, company_id, None).await?);
    }
    let mut days = [None; 7];
    for (weekday, start, end) in hours {
        if (1..=7).contains(&weekday) {
            days[(weekday - 1) as usize] = Some((start, end));
        }
    }
    let cal = Calendar {
        tz,
        days,
        holidays: holidays.into_iter().map(|h| h.day).collect::<BTreeSet<_>>(),
    };
    Ok(cal.is_usable().then_some(cal))
}

/// Calendars loaded once per team, for code that measures many tickets.
#[derive(Default)]
pub struct CalendarCache(HashMap<Option<Uuid>, Option<Calendar>>);

impl CalendarCache {
    /// The calendar for `team_id`, loaded on first use and then kept.
    pub async fn get(
        &mut self,
        conn: &mut PgConnection,
        company_id: Uuid,
        team_id: Option<Uuid>,
    ) -> Result<Option<&Calendar>, sqlx::Error> {
        if let Entry::Vacant(slot) = self.0.entry(team_id) {
            slot.insert(load_calendar(conn, company_id, team_id).await?);
        }
        Ok(self.0.get(&team_id).and_then(Option::as_ref))
    }
}

/// The team of a request must belong to the company.
async fn check_team(
    conn: &mut PgConnection,
    company_id: Uuid,
    team_id: Option<Uuid>,
) -> AppResult<()> {
    if let Some(team) = team_id {
        let ok: bool = sqlx::query_scalar(
            "SELECT EXISTS (SELECT 1 FROM helpdesk.teams WHERE id = $1 AND company_id = $2)",
        )
        .bind(team)
        .bind(company_id)
        .fetch_one(conn)
        .await?;
        if !ok {
            return Err(AppError::NotFound("team"));
        }
    }
    Ok(())
}

/// The calendar settings of one scope as the admin API shows them (the company's, or a team's).
async fn load_settings(
    conn: &mut PgConnection,
    company_id: Uuid,
    team_id: Option<Uuid>,
) -> AppResult<BusinessCalendar> {
    let row = find_calendar(conn, company_id, team_id).await?;
    let scope = row.as_ref().and_then(|r| r.0);
    let hours: Vec<(i16, NaiveTime, NaiveTime)> = sqlx::query_as(
        "SELECT weekday, start_time, end_time FROM helpdesk.business_hours
         WHERE company_id = $1 AND team_id IS NOT DISTINCT FROM $2 ORDER BY weekday",
    )
    .bind(company_id)
    .bind(scope)
    .fetch_all(&mut *conn)
    .await?;
    // A team without a calendar of its own shows the company's, including its holidays.
    let holidays = find_holidays(conn, company_id, scope).await?;
    let inherited = team_id.is_some() && scope.is_none();
    let (enabled, time_zone) = row
        .map(|(_, e, z)| (e, z))
        .unwrap_or((false, DEFAULT_TIME_ZONE.into()));
    Ok(BusinessCalendar {
        team_id,
        inherited,
        holidays_inherited: team_id.is_some(),
        enabled,
        time_zone,
        hours: if hours.is_empty() && !enabled {
            default_hours()
        } else {
            hours
                .into_iter()
                .map(|(weekday, s, e)| WorkingHours {
                    weekday,
                    start_time: fmt_time(s),
                    end_time: fmt_time(e),
                })
                .collect()
        },
        holidays,
    })
}

/// Which open tickets a calendar edit can change.
enum Scope {
    /// The tickets of one team.
    Team(Uuid),
    /// The company's hours, zone and switch: tickets without a team and of teams without a
    /// calendar of their own.
    CompanyCalendar,
    /// The company's holidays count for every team: all open tickets.
    CompanyHolidays,
}

/// Gives open tickets new due times; called when the calendar changes.
async fn recompute_open(
    conn: &mut PgConnection,
    company_id: Uuid,
    scope: Scope,
) -> AppResult<usize> {
    const BASE: &str = "SELECT t.id FROM helpdesk.tickets t
        WHERE t.company_id = $1 AND t.closed_at IS NULL AND NOT t.internal AND ";
    let no_calendar =
        "(t.team_id IS NULL OR NOT EXISTS (SELECT 1 FROM helpdesk.business_calendars c
            WHERE c.company_id = t.company_id AND c.team_id = t.team_id))";
    let (sql, team) = match scope {
        Scope::Team(team) => (format!("{BASE}t.team_id = $2"), Some(team)),
        Scope::CompanyCalendar => (format!("{BASE}{no_calendar} AND $2::uuid IS NULL"), None),
        Scope::CompanyHolidays => (format!("{BASE}$2::uuid IS NULL"), None),
    };
    let open: Vec<Uuid> = sqlx::query_scalar(sqlx::AssertSqlSafe(sql))
        .bind(company_id)
        .bind(team)
        .fetch_all(&mut *conn)
        .await?;
    for id in &open {
        crate::sla::sync(conn, *id).await?;
    }
    Ok(open.len())
}

/// Which open tickets an edit of the company or team calendar (or its holidays) can change.
fn scope_for(team_id: Option<Uuid>, holidays: bool) -> Scope {
    match (team_id, holidays) {
        (Some(team), _) => Scope::Team(team),
        (None, false) => Scope::CompanyCalendar,
        (None, true) => Scope::CompanyHolidays,
    }
}

/// Query string of the calendar routes.
#[derive(Debug, Default, Deserialize, IntoParams)]
pub struct TeamQuery {
    /// The team the calendar is for; without it the company calendar.
    pub team_id: Option<Uuid>,
}

#[utoipa::path(get, path = "/helpdesk/calendar", tag = "helpdesk", params(TeamQuery),
    responses((status = 200, body = BusinessCalendar), (status = 403, body = ErrorBody), (status = 404, body = ErrorBody)))]
async fn get_calendar(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(q): Query<TeamQuery>,
) -> AppResult<Json<BusinessCalendar>> {
    user.require(Permission::HelpdeskAdmin)?;
    let mut conn = state.db.acquire().await?;
    check_team(&mut conn, user.company_id, q.team_id).await?;
    Ok(Json(
        load_settings(&mut conn, user.company_id, q.team_id).await?,
    ))
}

/// Sets the working week and time zone and switches the calendar on or off, for the company or,
/// with `team_id`, for one team (which then stops using the company's). Open tickets it applies
/// to get new due times.
#[utoipa::path(put, path = "/helpdesk/calendar", tag = "helpdesk", request_body = CalendarInput, params(TeamQuery),
    responses((status = 200, body = BusinessCalendar), (status = 403, body = ErrorBody), (status = 404, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn put_calendar(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(q): Query<TeamQuery>,
    Json(input): Json<CalendarInput>,
) -> AppResult<Json<BusinessCalendar>> {
    user.require(Permission::HelpdeskAdmin)?;
    if input.time_zone.parse::<Tz>().is_err() {
        return Err(AppError::Validation(format!(
            "{:?} is not a known time zone (for example {DEFAULT_TIME_ZONE})",
            input.time_zone
        )));
    }
    let mut seen = BTreeSet::new();
    let mut hours = Vec::new();
    for h in &input.hours {
        if !(1..=7).contains(&h.weekday) || !seen.insert(h.weekday) {
            return Err(AppError::Validation(
                "weekday must be 1 (Monday) to 7 (Sunday), once each".into(),
            ));
        }
        let (s, e) = (parse_time(&h.start_time)?, parse_time(&h.end_time)?);
        if e <= s {
            return Err(AppError::Validation(
                "the closing time must be after the opening time".into(),
            ));
        }
        hours.push((h.weekday, s, e));
    }
    if input.enabled && hours.is_empty() {
        return Err(AppError::Validation(
            "a calendar needs at least one working day".into(),
        ));
    }
    let mut tx = state.db.begin().await?;
    check_team(&mut tx, user.company_id, q.team_id).await?;
    sqlx::query(
        "INSERT INTO helpdesk.business_calendars (company_id, team_id, enabled, time_zone) VALUES ($1, $2, $3, $4)
         ON CONFLICT (company_id, team_id) DO UPDATE SET enabled = $3, time_zone = $4, updated_at = now()",
    )
    .bind(user.company_id)
    .bind(q.team_id)
    .bind(input.enabled)
    .bind(&input.time_zone)
    .execute(&mut *tx)
    .await?;
    sqlx::query(
        "DELETE FROM helpdesk.business_hours WHERE company_id = $1 AND team_id IS NOT DISTINCT FROM $2",
    )
    .bind(user.company_id)
    .bind(q.team_id)
    .execute(&mut *tx)
    .await?;
    for (weekday, s, e) in hours {
        sqlx::query(
            "INSERT INTO helpdesk.business_hours (company_id, team_id, weekday, start_time, end_time) VALUES ($1, $2, $3, $4, $5)",
        )
        .bind(user.company_id)
        .bind(q.team_id)
        .bind(weekday)
        .bind(s)
        .bind(e)
        .execute(&mut *tx)
        .await?;
    }
    let recomputed = recompute_open(&mut tx, user.company_id, scope_for(q.team_id, false)).await?;
    audit::record(
        &mut tx,
        &user,
        "helpdesk_settings",
        q.team_id.unwrap_or(user.company_id),
        "business_calendar_updated",
        serde_json::json!({ "team_id": q.team_id, "enabled": input.enabled, "time_zone": input.time_zone, "recomputed": recomputed }),
    )
    .await?;
    let out = load_settings(&mut tx, user.company_id, q.team_id).await?;
    tx.commit().await?;
    Ok(Json(out))
}

/// Removes a team's own calendar and its holidays: the team uses the company's again. Open
/// tickets of the team get new due times.
#[utoipa::path(delete, path = "/helpdesk/calendar", tag = "helpdesk", params(("team_id" = Uuid, Query)),
    responses((status = 200, body = BusinessCalendar), (status = 403, body = ErrorBody), (status = 404, body = ErrorBody)))]
async fn delete_team_calendar(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(q): Query<TeamQuery>,
) -> AppResult<Json<BusinessCalendar>> {
    user.require(Permission::HelpdeskAdmin)?;
    let team = q.team_id.ok_or(AppError::NotFound("team"))?;
    let mut tx = state.db.begin().await?;
    check_team(&mut tx, user.company_id, Some(team)).await?;
    for table in ["business_calendars", "business_hours", "holidays"] {
        sqlx::query(sqlx::AssertSqlSafe(format!(
            "DELETE FROM helpdesk.{table} WHERE company_id = $1 AND team_id = $2"
        )))
        .bind(user.company_id)
        .bind(team)
        .execute(&mut *tx)
        .await?;
    }
    let recomputed = recompute_open(&mut tx, user.company_id, Scope::Team(team)).await?;
    audit::record(
        &mut tx,
        &user,
        "helpdesk_settings",
        team,
        "business_calendar_removed",
        serde_json::json!({ "team_id": team, "recomputed": recomputed }),
    )
    .await?;
    let out = load_settings(&mut tx, user.company_id, Some(team)).await?;
    tx.commit().await?;
    Ok(Json(out))
}

#[utoipa::path(post, path = "/helpdesk/calendar/holidays", tag = "helpdesk", request_body = HolidayInput, params(TeamQuery),
    responses((status = 201, body = Holiday), (status = 404, body = ErrorBody), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn add_holiday(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(q): Query<TeamQuery>,
    Json(input): Json<HolidayInput>,
) -> AppResult<(StatusCode, Json<Holiday>)> {
    user.require(Permission::HelpdeskAdmin)?;
    if input.name.trim().is_empty() {
        return Err(AppError::Validation("a holiday needs a name".into()));
    }
    let id = new_id();
    let mut tx = state.db.begin().await?;
    check_team(&mut tx, user.company_id, q.team_id).await?;
    if let Some(team) = q.team_id {
        let own: bool = sqlx::query_scalar(
            "SELECT EXISTS (SELECT 1 FROM helpdesk.business_calendars WHERE company_id = $1 AND team_id = $2)",
        )
        .bind(user.company_id)
        .bind(team)
        .fetch_one(&mut *tx)
        .await?;
        if !own {
            return Err(AppError::Validation(
                "the team has no calendar of its own; save one first".into(),
            ));
        }
    }
    sqlx::query(
        "INSERT INTO helpdesk.holidays (id, company_id, team_id, day, name) VALUES ($1, $2, $3, $4, $5)",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(q.team_id)
    .bind(input.day)
    .bind(input.name.trim())
    .execute(&mut *tx)
    .await?;
    let recomputed = recompute_open(&mut tx, user.company_id, scope_for(q.team_id, true)).await?;
    audit::record(
        &mut tx,
        &user,
        "helpdesk_settings",
        id,
        "holiday_added",
        serde_json::json!({ "team_id": q.team_id, "day": input.day, "name": input.name.trim(), "recomputed": recomputed }),
    )
    .await?;
    tx.commit().await?;
    Ok((
        StatusCode::CREATED,
        Json(Holiday {
            id,
            day: input.day,
            name: input.name.trim().to_string(),
        }),
    ))
}

#[utoipa::path(delete, path = "/helpdesk/calendar/holidays/{id}", tag = "helpdesk", params(("id" = Uuid, Path)),
    responses((status = 204), (status = 404, body = ErrorBody)))]
async fn delete_holiday(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<StatusCode> {
    user.require(Permission::HelpdeskAdmin)?;
    let mut tx = state.db.begin().await?;
    let row: Option<(NaiveDate, Option<Uuid>)> = sqlx::query_as(
        "DELETE FROM helpdesk.holidays WHERE id = $1 AND company_id = $2 RETURNING day, team_id",
    )
    .bind(id)
    .bind(user.company_id)
    .fetch_optional(&mut *tx)
    .await?;
    let (day, team_id) = row.ok_or(AppError::NotFound("holiday"))?;
    let recomputed = recompute_open(&mut tx, user.company_id, scope_for(team_id, true)).await?;
    audit::record(
        &mut tx,
        &user,
        "helpdesk_settings",
        id,
        "holiday_removed",
        serde_json::json!({ "team_id": team_id, "day": day, "recomputed": recomputed }),
    )
    .await?;
    tx.commit().await?;
    Ok(StatusCode::NO_CONTENT)
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(get_calendar, put_calendar, delete_team_calendar))
        .routes(routes!(add_holiday))
        .routes(routes!(delete_holiday))
}
