//! Read-only helpdesk reporting: volume, backlog, response and resolution times, SLA compliance,
//! satisfaction, top categories and tags, and logged time. Counts are SQL aggregates, always
//! filtered by company; durations are measured in Rust so they can use the business calendar.
//! Every table can also be exported as CSV.

use std::collections::HashMap;

use axum::extract::{Query, State};
use axum::http::{header, HeaderMap, HeaderValue};
use axum::Json;
use chrono::{DateTime, Datelike, Duration, NaiveDate, Utc};
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection};
use tradocraft_core::{AppError, AppResult, AppState, CurrentUser, Permission};
use utoipa::{IntoParams, ToSchema};
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::sla;

type ErrorBody = tradocraft_core::error::ErrorBody;

/// Longest period a report covers (days).
pub const MAX_DAYS: i64 = 731;

#[derive(Debug, Clone, Deserialize, IntoParams)]
pub struct ReportParams {
    /// First day (inclusive), `YYYY-MM-DD`. Default: 29 days before `to`.
    #[serde(default, deserialize_with = "tradocraft_core::serde_util::opt_date")]
    pub from: Option<NaiveDate>,
    /// Last day (inclusive). Default: today.
    #[serde(default, deserialize_with = "tradocraft_core::serde_util::opt_date")]
    pub to: Option<NaiveDate>,
    pub team_id: Option<Uuid>,
    pub owner_id: Option<Uuid>,
    pub category: Option<String>,
    /// `day` (default) or `week` (weeks start on Monday).
    pub group: Option<String>,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct VolumePoint {
    /// The day, or the Monday of the week.
    pub period: NaiveDate,
    pub created: i64,
    pub closed: i64,
}

#[derive(Debug, Serialize, FromRow, ToSchema)]
pub struct CountRow {
    /// The value (status, priority, category, tag) or an id for teams and owners; empty = none.
    pub key: String,
    pub label: String,
    pub count: i64,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct DurationStats {
    pub count: i64,
    pub average_minutes: Option<f64>,
    pub p90_minutes: Option<f64>,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct SlaStats {
    /// Tickets with a service level that were created in the period.
    pub tickets: i64,
    pub breached: i64,
    pub compliant: i64,
    /// Share of tickets that did not breach, 0-100.
    pub compliance_percent: Option<f64>,
}

#[derive(Debug, Serialize, FromRow, ToSchema)]
pub struct TeamBreaches {
    pub team_id: Option<Uuid>,
    pub team: String,
    pub tickets: i64,
    pub breached: i64,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct CsatStats {
    pub responses: i64,
    pub good: i64,
    pub bad: i64,
    /// Average satisfaction: share of "good" ratings, 0-100.
    pub average_percent: Option<f64>,
}

#[derive(Debug, Serialize, FromRow, ToSchema)]
pub struct TimeRow {
    pub user_id: Uuid,
    pub name: String,
    pub total_minutes: i64,
    pub billable_minutes: i64,
    pub non_billable_minutes: i64,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct Report {
    pub from: NaiveDate,
    pub to: NaiveDate,
    /// day | week
    pub group: String,
    /// How response and resolution times are measured: `business` (every ticket's calendar is
    /// on), `elapsed`, or `mixed` (some teams have a calendar and others do not).
    pub basis: String,
    pub volume: Vec<VolumePoint>,
    pub backlog_by_status: Vec<CountRow>,
    pub backlog_by_priority: Vec<CountRow>,
    pub backlog_by_team: Vec<CountRow>,
    pub backlog_by_owner: Vec<CountRow>,
    pub first_response: DurationStats,
    pub resolution: DurationStats,
    pub sla: SlaStats,
    pub breaches_by_team: Vec<TeamBreaches>,
    pub csat: CsatStats,
    pub top_categories: Vec<CountRow>,
    pub top_tags: Vec<CountRow>,
    pub time_by_user: Vec<TimeRow>,
    pub time_billable_minutes: i64,
    pub time_non_billable_minutes: i64,
}

// ---------------------------------------------------------------------------------------------
// Pure helpers
// ---------------------------------------------------------------------------------------------

/// Average and 90th percentile (nearest rank) of durations in seconds, as minutes.
pub fn duration_stats(seconds: &[i64]) -> DurationStats {
    if seconds.is_empty() {
        return DurationStats {
            count: 0,
            average_minutes: None,
            p90_minutes: None,
        };
    }
    let mut v = seconds.to_vec();
    v.sort_unstable();
    let n = v.len();
    let sum: i64 = v.iter().sum();
    let rank = (n * 9).div_ceil(10).max(1);
    let minutes = |s: f64| (s / 60.0 * 10.0).round() / 10.0;
    DurationStats {
        count: n as i64,
        average_minutes: Some(minutes(sum as f64 / n as f64)),
        p90_minutes: Some(minutes(v[rank - 1] as f64)),
    }
}

/// Percentage with one decimal; `None` without a denominator.
pub fn percent(part: i64, whole: i64) -> Option<f64> {
    (whole > 0).then(|| (part as f64 * 1000.0 / whole as f64).round() / 10.0)
}

/// The first day of the bucket a date belongs to.
pub fn bucket(day: NaiveDate, group: &str) -> NaiveDate {
    if group == "week" {
        day - Duration::days(i64::from(day.weekday().num_days_from_monday()))
    } else {
        day
    }
}

/// Every bucket from `from` to `to`, so quiet days show as zero.
pub fn buckets(from: NaiveDate, to: NaiveDate, group: &str) -> Vec<NaiveDate> {
    let step = if group == "week" { 7 } else { 1 };
    let mut out = Vec::new();
    let mut d = bucket(from, group);
    while d <= to {
        out.push(d);
        d += Duration::days(step);
    }
    out
}

use tradocraft_core::csv_io::quote_cell as csv_cell;

/// One table of the report: a header and its rows.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Table {
    pub header: Vec<String>,
    pub rows: Vec<Vec<String>>,
}

impl Table {
    /// Comma separated, CRLF lines, cells that start with `= + - @` quoted so a spreadsheet does not
    /// run them.
    pub fn to_csv(&self) -> String {
        let mut out = self.header.join(",");
        out.push_str("\r\n");
        for r in &self.rows {
            out.push_str(&r.iter().map(|c| csv_cell(c)).collect::<Vec<_>>().join(","));
            out.push_str("\r\n");
        }
        out
    }
}

fn csv(header: &[&str], rows: Vec<Vec<String>>) -> Table {
    Table {
        header: header.iter().map(|h| h.to_string()).collect(),
        rows,
    }
}

/// The names of the exportable tables.
pub const TABLES: [&str; 11] = [
    "volume",
    "backlog_status",
    "backlog_priority",
    "backlog_team",
    "backlog_owner",
    "times",
    "sla",
    "breaches_by_team",
    "top_categories",
    "top_tags",
    "time_by_user",
];

fn count_rows(rows: &[CountRow]) -> Vec<Vec<String>> {
    rows.iter()
        .map(|r| vec![r.key.clone(), r.label.clone(), r.count.to_string()])
        .collect()
}

fn opt(v: Option<f64>) -> String {
    v.map(|v| v.to_string()).unwrap_or_default()
}

/// One table of the report as CSV (comma separated, CRLF lines, header row first).
pub fn csv_table(r: &Report, table: &str) -> Option<String> {
    self::table(r, table).map(|t| t.to_csv())
}

/// One table of the report by name (see [`TABLES`]).
pub fn table(r: &Report, table: &str) -> Option<Table> {
    Some(match table {
        "volume" => csv(
            &["period", "created", "closed"],
            r.volume
                .iter()
                .map(|p| {
                    vec![
                        p.period.to_string(),
                        p.created.to_string(),
                        p.closed.to_string(),
                    ]
                })
                .collect(),
        ),
        "backlog_status" => csv(&["key", "label", "count"], count_rows(&r.backlog_by_status)),
        "backlog_priority" => csv(
            &["key", "label", "count"],
            count_rows(&r.backlog_by_priority),
        ),
        "backlog_team" => csv(&["key", "label", "count"], count_rows(&r.backlog_by_team)),
        "backlog_owner" => csv(&["key", "label", "count"], count_rows(&r.backlog_by_owner)),
        "times" => csv(
            &[
                "measure",
                "basis",
                "count",
                "average_minutes",
                "p90_minutes",
            ],
            [
                ("first_response", &r.first_response),
                ("resolution", &r.resolution),
            ]
            .into_iter()
            .map(|(m, s)| {
                vec![
                    m.to_string(),
                    r.basis.clone(),
                    s.count.to_string(),
                    opt(s.average_minutes),
                    opt(s.p90_minutes),
                ]
            })
            .collect(),
        ),
        "sla" => csv(
            &[
                "tickets",
                "breached",
                "compliant",
                "compliance_percent",
                "csat_responses",
                "csat_good",
                "csat_bad",
                "csat_average_percent",
            ],
            vec![vec![
                r.sla.tickets.to_string(),
                r.sla.breached.to_string(),
                r.sla.compliant.to_string(),
                opt(r.sla.compliance_percent),
                r.csat.responses.to_string(),
                r.csat.good.to_string(),
                r.csat.bad.to_string(),
                opt(r.csat.average_percent),
            ]],
        ),
        "breaches_by_team" => csv(
            &["team", "tickets", "breached"],
            r.breaches_by_team
                .iter()
                .map(|t| {
                    vec![
                        t.team.clone(),
                        t.tickets.to_string(),
                        t.breached.to_string(),
                    ]
                })
                .collect(),
        ),
        "top_categories" => csv(&["key", "label", "count"], count_rows(&r.top_categories)),
        "top_tags" => csv(&["key", "label", "count"], count_rows(&r.top_tags)),
        "time_by_user" => csv(
            &[
                "user",
                "total_minutes",
                "billable_minutes",
                "non_billable_minutes",
            ],
            r.time_by_user
                .iter()
                .map(|t| {
                    vec![
                        t.name.clone(),
                        t.total_minutes.to_string(),
                        t.billable_minutes.to_string(),
                        t.non_billable_minutes.to_string(),
                    ]
                })
                .collect(),
        ),
        _ => return None,
    })
}

// ---------------------------------------------------------------------------------------------
// Queries
// ---------------------------------------------------------------------------------------------

struct Scope {
    company_id: Uuid,
    from: NaiveDate,
    to: NaiveDate,
    tz: String,
    team_id: Option<Uuid>,
    owner_id: Option<Uuid>,
    category: Option<String>,
}

/// Ticket filter shared by every query: `$1` company, `$2` team, `$3` owner, `$4` category,
/// `$5` first day, `$6` last day, `$7` time zone. Merged tickets are left out.
const FILTER: &str = "t.company_id = $1 AND t.merged_into_id IS NULL
    AND ($2::uuid IS NULL OR t.team_id = $2) AND ($3::uuid IS NULL OR t.owner_user_id = $3)
    AND ($4::text IS NULL OR t.category = $4)";

fn local_day(column: &str) -> String {
    format!("(({column}) AT TIME ZONE $7)::date BETWEEN $5 AND $6")
}

macro_rules! bind_scope {
    ($q:expr, $s:expr) => {
        $q.bind($s.company_id)
            .bind($s.team_id)
            .bind($s.owner_id)
            .bind(&$s.category)
            .bind($s.from)
            .bind($s.to)
            .bind(&$s.tz)
    };
}

async fn per_day(
    conn: &mut PgConnection,
    s: &Scope,
    column: &str,
    only_closed: bool,
) -> AppResult<HashMap<NaiveDate, i64>> {
    let rows: Vec<(NaiveDate, i64)> =
        bind_scope!(
            sqlx::query_as(&format!(
            "SELECT ((t.{column}) AT TIME ZONE $7)::date AS day, count(*) FROM helpdesk.tickets t
             WHERE {FILTER} AND {} {} GROUP BY day",
            local_day(&format!("t.{column}")),
            if only_closed { "AND t.closed_at IS NOT NULL" } else { "" }
        )),
            s
        )
        .fetch_all(conn)
        .await?;
    Ok(rows.into_iter().collect())
}

async fn backlog(
    conn: &mut PgConnection,
    s: &Scope,
    key: &str,
    label: &str,
    join: &str,
) -> AppResult<Vec<CountRow>> {
    Ok(bind_scope!(
        sqlx::query_as(&format!(
            "SELECT coalesce({key}::text, '') AS key, coalesce({label}, '') AS label, count(*) AS count
             FROM helpdesk.tickets t {join}
             WHERE {FILTER} AND t.closed_at IS NULL GROUP BY 1, 2 ORDER BY count DESC, 2"
        )),
        s
    )
    .fetch_all(conn)
    .await?)
}

async fn top(conn: &mut PgConnection, s: &Scope, tags: bool) -> AppResult<Vec<CountRow>> {
    let (key, join) = if tags {
        ("g.tag", "JOIN helpdesk.ticket_tags g ON g.ticket_id = t.id")
    } else {
        ("t.category", "")
    };
    Ok(bind_scope!(
        sqlx::query_as(&format!(
            "SELECT {key} AS key, {key} AS label, count(*) AS count FROM helpdesk.tickets t {join}
             WHERE {FILTER} AND {} GROUP BY 1 ORDER BY count DESC, 1 LIMIT 10",
            local_day("t.created_at")
        )),
        s
    )
    .fetch_all(conn)
    .await?)
}

#[derive(FromRow)]
struct TimedTicket {
    id: Uuid,
    team_id: Option<Uuid>,
    created_at: DateTime<Utc>,
    first_response_at: Option<DateTime<Utc>>,
    closed_at: Option<DateTime<Utc>>,
    sla_paused_seconds: i64,
}

pub async fn build(
    conn: &mut PgConnection,
    company_id: Uuid,
    p: &ReportParams,
    today: NaiveDate,
) -> AppResult<Report> {
    build_in_zone(conn, company_id, p, today, None).await
}

/// Like [`build`], with the time zone for date filtering and grouping given. `None` uses the
/// company business calendar's time zone (UTC when there is none).
pub async fn build_in_zone(
    conn: &mut PgConnection,
    company_id: Uuid,
    p: &ReportParams,
    today: NaiveDate,
    time_zone: Option<&str>,
) -> AppResult<Report> {
    let to = p.to.unwrap_or(today);
    let from = p.from.unwrap_or(to - Duration::days(29));
    if from > to {
        return Err(AppError::Validation("from must not be after to".into()));
    }
    if (to - from).num_days() >= MAX_DAYS {
        return Err(AppError::Validation(format!(
            "a report covers at most {MAX_DAYS} days"
        )));
    }
    let group = match p.group.as_deref() {
        None | Some("day") => "day",
        Some("week") => "week",
        Some(_) => return Err(AppError::Validation("group must be day or week".into())),
    };
    if let Some(c) = &p.category {
        if !crate::tickets::CATEGORIES.contains(&c.as_str()) {
            return Err(AppError::Validation("unknown category".into()));
        }
    }
    let zone: Option<String> = match time_zone {
        Some(z) => Some(z.to_string()),
        None => {
            sqlx::query_scalar(
                "SELECT time_zone FROM helpdesk.business_calendars WHERE company_id = $1 AND team_id IS NULL",
            )
            .bind(company_id)
            .fetch_optional(&mut *conn)
            .await?
        }
    };
    let mut cache = crate::calendar::CalendarCache::default();
    let company_cal = cache.get(conn, company_id, None).await?.is_some();
    let s = Scope {
        company_id,
        from,
        to,
        tz: zone.unwrap_or_else(|| "UTC".into()),
        team_id: p.team_id,
        owner_id: p.owner_id,
        category: p.category.clone(),
    };

    let created = per_day(conn, &s, "created_at", false).await?;
    let closed = per_day(conn, &s, "closed_at", true).await?;
    let mut volume: Vec<VolumePoint> = buckets(from, to, group)
        .into_iter()
        .map(|period| VolumePoint {
            period,
            created: 0,
            closed: 0,
        })
        .collect();
    for (day, n) in created {
        if let Some(v) = volume.iter_mut().find(|v| v.period == bucket(day, group)) {
            v.created += n;
        }
    }
    for (day, n) in closed {
        if let Some(v) = volume.iter_mut().find(|v| v.period == bucket(day, group)) {
            v.closed += n;
        }
    }

    let backlog_by_status = backlog(conn, &s, "t.status", "t.status", "").await?;
    let backlog_by_priority = backlog(conn, &s, "t.priority", "t.priority", "").await?;
    let backlog_by_team = backlog(
        conn,
        &s,
        "t.team_id",
        "tm.name",
        "LEFT JOIN helpdesk.teams tm ON tm.id = t.team_id",
    )
    .await?;
    let backlog_by_owner = backlog(
        conn,
        &s,
        "t.owner_user_id",
        "u.display_name",
        "LEFT JOIN core.users u ON u.id = t.owner_user_id",
    )
    .await?;

    // Response and resolution times of tickets created in the period.
    let timed: Vec<TimedTicket> = bind_scope!(
        sqlx::query_as(&format!(
            "SELECT t.id, t.team_id, t.created_at, t.first_response_at, t.closed_at, t.sla_paused_seconds
             FROM helpdesk.tickets t WHERE {FILTER} AND NOT t.internal AND {}",
            local_day("t.created_at")
        )),
        s
    )
    .fetch_all(&mut *conn)
    .await?;
    let ids: Vec<Uuid> = timed.iter().map(|t| t.id).collect();
    let pause_rows: Vec<(Uuid, DateTime<Utc>, DateTime<Utc>)> = sqlx::query_as(
        "SELECT ticket_id, started_at, ended_at FROM helpdesk.sla_pauses
         WHERE company_id = $1 AND ticket_id = ANY($2) AND ended_at IS NOT NULL",
    )
    .bind(company_id)
    .bind(&ids)
    .fetch_all(&mut *conn)
    .await?;
    let mut pauses: HashMap<Uuid, Vec<sla::Pause>> = HashMap::new();
    for (id, a, b) in pause_rows {
        pauses.entry(id).or_default().push((a, b));
    }
    let (mut first, mut resolved) = (Vec::new(), Vec::new());
    let mut measured_with_calendar = 0usize;
    for t in &timed {
        let cal = cache.get(conn, company_id, t.team_id).await?.cloned();
        measured_with_calendar += usize::from(cal.is_some());
        let own = pauses.get(&t.id).map(Vec::as_slice).unwrap_or(&[]);
        if let Some(at) = t.first_response_at {
            first.push(sla::worked_seconds(cal.as_ref(), t.created_at, at, own, 0));
        }
        if let Some(at) = t.closed_at {
            let recorded: i64 = own.iter().map(|(a, b)| (*b - *a).num_seconds()).sum();
            let legacy = (t.sla_paused_seconds - recorded).max(0);
            resolved.push(sla::worked_seconds(
                cal.as_ref(),
                t.created_at,
                at,
                own,
                legacy,
            ));
        }
    }

    let (with_sla, breached): (i64, i64) = bind_scope!(
        sqlx::query_as(&format!(
            "SELECT count(*), count(*) FILTER (WHERE {}) FROM helpdesk.tickets t
             WHERE {FILTER} AND NOT t.internal AND t.first_response_due_at IS NOT NULL AND {}",
            sla::sql::breached(),
            local_day("t.created_at")
        )),
        s
    )
    .fetch_one(&mut *conn)
    .await?;
    let breaches_by_team: Vec<TeamBreaches> = bind_scope!(
        sqlx::query_as(&format!(
            "SELECT t.team_id, coalesce(tm.name, '') AS team, count(*) AS tickets,
                    count(*) FILTER (WHERE {}) AS breached
             FROM helpdesk.tickets t LEFT JOIN helpdesk.teams tm ON tm.id = t.team_id
             WHERE {FILTER} AND NOT t.internal AND t.first_response_due_at IS NOT NULL AND {}
             GROUP BY t.team_id, tm.name ORDER BY breached DESC, team",
            sla::sql::breached(),
            local_day("t.created_at")
        )),
        s
    )
    .fetch_all(&mut *conn)
    .await?;

    let (good, bad): (i64, i64) = bind_scope!(
        sqlx::query_as(&format!(
            "SELECT count(*) FILTER (WHERE c.rating = 'good'), count(*) FILTER (WHERE c.rating = 'bad')
             FROM helpdesk.csat_surveys c JOIN helpdesk.tickets t ON t.id = c.ticket_id
             WHERE {FILTER} AND c.rated_at IS NOT NULL AND {}",
            local_day("c.rated_at")
        )),
        s
    )
    .fetch_one(&mut *conn)
    .await?;

    let top_categories = top(conn, &s, false).await?;
    let top_tags = top(conn, &s, true).await?;

    let time_by_user: Vec<TimeRow> = bind_scope!(
        sqlx::query_as(&format!(
            "SELECT e.user_id, u.display_name AS name, sum(e.minutes)::bigint AS total_minutes,
                    coalesce(sum(e.minutes) FILTER (WHERE e.billable), 0)::bigint AS billable_minutes,
                    coalesce(sum(e.minutes) FILTER (WHERE NOT e.billable), 0)::bigint AS non_billable_minutes
             FROM helpdesk.time_entries e JOIN helpdesk.tickets t ON t.id = e.ticket_id
             JOIN core.users u ON u.id = e.user_id
             WHERE {FILTER} AND {} GROUP BY e.user_id, u.display_name ORDER BY total_minutes DESC, name",
            local_day("e.created_at")
        )),
        s
    )
    .fetch_all(&mut *conn)
    .await?;
    let time_billable_minutes = time_by_user.iter().map(|t| t.billable_minutes).sum();
    let time_non_billable_minutes = time_by_user.iter().map(|t| t.non_billable_minutes).sum();

    Ok(Report {
        from,
        to,
        group: group.into(),
        basis: match (timed.len(), measured_with_calendar) {
            (0, _) if company_cal => "business",
            (0, _) | (_, 0) => "elapsed",
            (n, m) if n == m => "business",
            _ => "mixed",
        }
        .into(),
        volume,
        backlog_by_status,
        backlog_by_priority,
        backlog_by_team,
        backlog_by_owner,
        first_response: duration_stats(&first),
        resolution: duration_stats(&resolved),
        sla: SlaStats {
            tickets: with_sla,
            breached,
            compliant: with_sla - breached,
            compliance_percent: percent(with_sla - breached, with_sla),
        },
        breaches_by_team,
        csat: CsatStats {
            responses: good + bad,
            good,
            bad,
            average_percent: percent(good, good + bad),
        },
        top_categories,
        top_tags,
        time_by_user,
        time_billable_minutes,
        time_non_billable_minutes,
    })
}

/// The helpdesk report for a period. Response and resolution times are in business time when the
/// ticket's own calendar (its team's, else the company's) is on (see `basis`). Days are the
/// company's local days.
#[utoipa::path(get, path = "/helpdesk/reports", tag = "helpdesk", operation_id = "get_report", params(ReportParams),
    responses((status = 200, body = Report), (status = 403, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn get_report(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(p): Query<ReportParams>,
) -> AppResult<Json<Report>> {
    user.require(Permission::HelpdeskRead)?;
    let mut conn = state.db.acquire().await?;
    Ok(Json(
        build(&mut conn, user.company_id, &p, tradocraft_core::today()).await?,
    ))
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct ExportParams {
    /// volume | backlog_status | backlog_priority | backlog_team | backlog_owner | times | sla |
    /// breaches_by_team | top_categories | top_tags | time_by_user
    pub table: String,
    #[serde(default, deserialize_with = "tradocraft_core::serde_util::opt_date")]
    pub from: Option<NaiveDate>,
    #[serde(default, deserialize_with = "tradocraft_core::serde_util::opt_date")]
    pub to: Option<NaiveDate>,
    pub team_id: Option<Uuid>,
    pub owner_id: Option<Uuid>,
    pub category: Option<String>,
    pub group: Option<String>,
}

/// One table of the report as a CSV file.
#[utoipa::path(get, path = "/helpdesk/reports/export", tag = "helpdesk", operation_id = "export_report", params(ExportParams),
    responses((status = 200, body = String, content_type = "text/csv"), (status = 403, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn export(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(p): Query<ExportParams>,
) -> AppResult<(HeaderMap, String)> {
    user.require(Permission::HelpdeskRead)?;
    if !TABLES.contains(&p.table.as_str()) {
        return Err(AppError::Validation(format!(
            "table must be one of {}",
            TABLES.join(", ")
        )));
    }
    let params = ReportParams {
        from: p.from,
        to: p.to,
        team_id: p.team_id,
        owner_id: p.owner_id,
        category: p.category.clone(),
        group: p.group.clone(),
    };
    let mut conn = state.db.acquire().await?;
    let report = build(
        &mut conn,
        user.company_id,
        &params,
        tradocraft_core::today(),
    )
    .await?;
    let body =
        csv_table(&report, &p.table).ok_or_else(|| AppError::Validation("unknown table".into()))?;
    let mut headers = HeaderMap::new();
    headers.insert(
        header::CONTENT_TYPE,
        HeaderValue::from_static("text/csv; charset=utf-8"),
    );
    headers.insert(
        header::CONTENT_DISPOSITION,
        HeaderValue::from_str(&format!(
            "attachment; filename=\"helpdesk-{}-{}-{}.csv\"",
            p.table, report.from, report.to
        ))
        .unwrap_or_else(|_| HeaderValue::from_static("attachment")),
    );
    Ok((headers, body))
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(get_report))
        .routes(routes!(export))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn d(y: i32, m: u32, day: u32) -> NaiveDate {
        NaiveDate::from_ymd_opt(y, m, day).unwrap()
    }

    #[test]
    fn average_and_p90_are_in_minutes() {
        let s = duration_stats(&[]);
        assert_eq!((s.count, s.average_minutes, s.p90_minutes), (0, None, None));
        let s = duration_stats(&[600, 1200, 1800]);
        assert_eq!(s.count, 3);
        assert_eq!(s.average_minutes, Some(20.0));
        assert_eq!(s.p90_minutes, Some(30.0));
        // 10 values: the 9th smallest is the 90th percentile (nearest rank).
        let v: Vec<i64> = (1..=10).map(|m| m * 60).collect();
        assert_eq!(duration_stats(&v).p90_minutes, Some(9.0));
        assert_eq!(duration_stats(&v).average_minutes, Some(5.5));
        // One value is its own p90.
        assert_eq!(duration_stats(&[90]).p90_minutes, Some(1.5));
    }

    #[test]
    fn percentages_have_one_decimal_and_need_a_denominator() {
        assert_eq!(percent(0, 0), None);
        assert_eq!(percent(2, 3), Some(66.7));
        assert_eq!(percent(3, 3), Some(100.0));
        assert_eq!(percent(0, 4), Some(0.0));
    }

    #[test]
    fn weeks_start_on_monday_and_quiet_periods_are_listed() {
        // 11 November 2026 is a Wednesday.
        assert_eq!(bucket(d(2026, 11, 11), "week"), d(2026, 11, 9));
        assert_eq!(bucket(d(2026, 11, 15), "week"), d(2026, 11, 9));
        assert_eq!(bucket(d(2026, 11, 16), "week"), d(2026, 11, 16));
        assert_eq!(bucket(d(2026, 11, 11), "day"), d(2026, 11, 11));
        assert_eq!(
            buckets(d(2026, 11, 11), d(2026, 11, 24), "week"),
            vec![d(2026, 11, 9), d(2026, 11, 16), d(2026, 11, 23)]
        );
        assert_eq!(buckets(d(2026, 11, 1), d(2026, 11, 3), "day").len(), 3);
    }

    #[test]
    fn csv_cells_are_quoted_and_cannot_run_as_formulas() {
        assert_eq!(csv_cell("plain"), "plain");
        assert_eq!(csv_cell("a,b"), "\"a,b\"");
        assert_eq!(csv_cell("say \"hi\""), "\"say \"\"hi\"\"\"");
        assert_eq!(csv_cell("=1+1"), "'=1+1");
        assert_eq!(csv_cell("@x"), "'@x");
        assert_eq!(
            csv(
                "a,b".split(',').collect::<Vec<_>>().as_slice(),
                vec![vec!["1".into(), "x,y".into()]]
            )
            .to_csv(),
            "a,b\r\n1,\"x,y\"\r\n"
        );
    }
}
