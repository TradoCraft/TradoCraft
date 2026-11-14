//! Scheduled report mails (ADR 0065): the model, the pure timing, building and queuing one mail run,
//! and the worker pass that runs what is due.
//!
//! One scheduler serves two kinds of report: a saved user-defined report (ADR 0042) and a table of
//! the fixed helpdesk report (ADR 0021). A run is made with the permissions the schedule's owner
//! has *at that moment*, so a person who loses access also stops the mail. The mail itself is queued
//! in `core.mail_outbox`; the worker's outbox loop applies the outbound policy of ADR 0048.

use chrono::{DateTime, Datelike, Duration, LocalResult, NaiveDate, NaiveTime, TimeZone, Utc};
use chrono_tz::Tz;
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection, PgPool};
use tradocraft_core::company::get_company;
use tradocraft_core::mail::{self, Attachment};
use tradocraft_core::{
    audit, modules, AppError, AppResult, CurrentUser, DocumentConfig, Permission,
};
use utoipa::ToSchema;
use uuid::Uuid;

use crate::definition::plan;
use crate::engine;
use crate::pdf;

pub const FREQUENCIES: [&str; 3] = ["daily", "weekly", "monthly"];
pub const FORMATS: [&str; 2] = ["csv", "pdf"];
pub const PERIODS: [&str; 5] = [
    "yesterday",
    "last_7_days",
    "last_week",
    "last_30_days",
    "last_month",
];
/// Recipients of one schedule (colleagues and addresses together).
pub const MAX_RECIPIENTS: usize = 50;
/// Schedules run in this pass at most, so one pass cannot starve the rest of the worker loop.
const BATCH: usize = 20;

// ---------------------------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------------------------

/// Which helpdesk table to mail and for which period.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
pub struct HelpdeskReportSpec {
    /// One of the tables of `GET /helpdesk/reports/export` (volume, backlog_status, times, sla, ...).
    pub table: String,
    /// yesterday | last_7_days | last_week (Monday to Sunday before today) | last_30_days |
    /// last_month (the calendar month before this one), counted in the schedule's time zone.
    pub period: String,
    pub team_id: Option<Uuid>,
    pub owner_id: Option<Uuid>,
    pub category: Option<String>,
    /// `day` (default) or `week`.
    pub group: Option<String>,
}

#[derive(Debug, FromRow)]
pub struct ScheduleRow {
    pub id: Uuid,
    pub company_id: Uuid,
    pub owner_id: Uuid,
    pub name: String,
    pub source: String,
    pub report_id: Option<Uuid>,
    pub helpdesk: Option<serde_json::Value>,
    pub frequency: String,
    pub weekday: Option<i16>,
    pub day_of_month: Option<i16>,
    pub send_time: NaiveTime,
    pub time_zone: String,
    pub format: String,
    pub user_ids: Vec<Uuid>,
    pub addresses: Vec<String>,
    pub active: bool,
}

pub const SELECT_ROW: &str =
    "SELECT id, company_id, owner_id, name, source, report_id, helpdesk, frequency,
        weekday, day_of_month, send_time, time_zone, format, user_ids, addresses, active
    FROM reports.schedules";

impl ScheduleRow {
    fn timing(&self) -> AppResult<Timing> {
        Ok(Timing {
            frequency: self.frequency.clone(),
            weekday: self.weekday,
            day_of_month: self.day_of_month,
            send_time: self.send_time,
            tz: self
                .time_zone
                .parse()
                .map_err(|_| AppError::Validation("unknown time zone".into()))?,
        })
    }
}

// ---------------------------------------------------------------------------------------------
// Timing (pure)
// ---------------------------------------------------------------------------------------------

/// When a schedule fires: every day, one weekday (1 = Monday) or one day of the month (1 to 28, so
/// every month has it), at a local wall-clock time in a time zone.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Timing {
    pub frequency: String,
    pub weekday: Option<i16>,
    pub day_of_month: Option<i16>,
    pub send_time: NaiveTime,
    pub tz: Tz,
}

/// The local wall-clock time as an instant. A time that does not exist (the clock jumped forward)
/// is read as an hour later; of two possible instants the first is used.
fn local_instant(tz: Tz, day: NaiveDate, time: NaiveTime) -> DateTime<Utc> {
    let naive = day.and_time(time);
    match tz.from_local_datetime(&naive) {
        LocalResult::Single(t) => t.with_timezone(&Utc),
        LocalResult::Ambiguous(a, _) => a.with_timezone(&Utc),
        LocalResult::None => tz
            .from_local_datetime(&(naive + Duration::hours(1)))
            .earliest()
            .map(|t| t.with_timezone(&Utc))
            .unwrap_or_else(|| Utc.from_utc_datetime(&naive)),
    }
}

/// The first run strictly after `after`. A schedule that was down for a while runs once when the
/// worker is back, not once per missed day, because the next run is computed from the moment of the
/// run and not from the previous due time.
pub fn next_run(t: &Timing, after: DateTime<Utc>) -> DateTime<Utc> {
    let first = after.with_timezone(&t.tz).date_naive();
    for i in 0..=400 {
        let day = first + Duration::days(i);
        let hit = match t.frequency.as_str() {
            "weekly" => {
                i64::from(t.weekday.unwrap_or(1)) == i64::from(day.weekday().number_from_monday())
            }
            "monthly" => i64::from(t.day_of_month.unwrap_or(1)) == i64::from(day.day()),
            _ => true,
        };
        if !hit {
            continue;
        }
        let at = local_instant(t.tz, day, t.send_time);
        if at > after {
            return at;
        }
    }
    after + Duration::days(1)
}

/// The first and last day (inclusive) of a helpdesk period, as seen on `today`.
pub fn period_days(period: &str, today: NaiveDate) -> Option<(NaiveDate, NaiveDate)> {
    let yesterday = today - Duration::days(1);
    Some(match period {
        "yesterday" => (yesterday, yesterday),
        "last_7_days" => (today - Duration::days(7), yesterday),
        "last_30_days" => (today - Duration::days(30), yesterday),
        "last_week" => {
            let monday = today - Duration::days(i64::from(today.weekday().num_days_from_monday()));
            (monday - Duration::days(7), monday - Duration::days(1))
        }
        "last_month" => {
            let first_this = today.with_day(1)?;
            let last = first_this - Duration::days(1);
            (last.with_day(1)?, last)
        }
        _ => return None,
    })
}

// ---------------------------------------------------------------------------------------------
// Texts
// ---------------------------------------------------------------------------------------------

fn mail_text(lang: &str, name: &str, day: NaiveDate, frequency: &str) -> (String, String) {
    let freq = match (lang, frequency) {
        ("nl", "daily") => "dagelijks",
        ("nl", "weekly") => "wekelijks",
        ("nl", _) => "maandelijks",
        ("fr", "daily") => "chaque jour",
        ("fr", "weekly") => "chaque semaine",
        ("fr", _) => "chaque mois",
        ("de", "daily") => "täglich",
        ("de", "weekly") => "wöchentlich",
        ("de", _) => "monatlich",
        ("es", "daily") => "cada día",
        ("es", "weekly") => "cada semana",
        ("es", _) => "cada mes",
        (_, "daily") => "daily",
        (_, "weekly") => "weekly",
        (_, _) => "monthly",
    };
    let (prefix, line, foot) = match lang {
        "nl" => (
            "Gepland rapport",
            "In bijlage vindt u het rapport",
            "U ontvangt dit rapport automatisch, {freq}. Vraag een beheerder om het aan te passen of te stoppen.",
        ),
        "fr" => (
            "Rapport planifié",
            "Vous trouverez en pièce jointe le rapport",
            "Vous recevez ce rapport automatiquement, {freq}. Demandez à un administrateur de le modifier ou de l'arrêter.",
        ),
        "de" => (
            "Geplanter Bericht",
            "Im Anhang finden Sie den Bericht",
            "Sie erhalten diesen Bericht automatisch, {freq}. Bitten Sie einen Administrator, ihn zu ändern oder zu beenden.",
        ),
        "es" => (
            "Informe programado",
            "Adjunto encontrará el informe",
            "Recibe este informe automáticamente, {freq}. Pida a un administrador que lo cambie o lo detenga.",
        ),
        _ => (
            "Scheduled report",
            "Attached is the report",
            "You receive this report automatically, {freq}. Ask an administrator to change or stop it.",
        ),
    };
    let day = day.format("%Y-%m-%d");
    (
        format!("{prefix}: {} ({day})", one_line(name)),
        format!(
            "{line} \"{}\" ({day}).\n\n{}\n",
            one_line(name),
            foot.replace("{freq}", freq)
        ),
    )
}

/// A name on one line (subjects must not contain line breaks).
pub fn one_line(s: &str) -> String {
    s.split_whitespace().collect::<Vec<_>>().join(" ")
}

fn helpdesk_title(table: &str) -> String {
    format!("Helpdesk: {}", table.replace('_', " "))
}

// ---------------------------------------------------------------------------------------------
// Running one schedule
// ---------------------------------------------------------------------------------------------

/// The schedule owner as the permission checks see them, or `None` when they left the company or
/// were deactivated.
async fn load_owner(
    conn: &mut PgConnection,
    company_id: Uuid,
    user_id: Uuid,
) -> AppResult<Option<CurrentUser>> {
    #[derive(FromRow)]
    struct Owner {
        email: String,
        display_name: String,
        roles: Vec<String>,
        user_disabled: Vec<String>,
        company_disabled: Vec<String>,
    }
    let r: Option<Owner> = sqlx::query_as(
        "SELECT u.email, u.display_name, uc.roles, uc.disabled_modules AS user_disabled,
                c.disabled_modules AS company_disabled
         FROM core.users u
         JOIN core.user_companies uc ON uc.user_id = u.id AND uc.company_id = $2 AND uc.active
         JOIN core.companies c ON c.id = uc.company_id
         WHERE u.id = $1 AND u.active",
    )
    .bind(user_id)
    .bind(company_id)
    .fetch_optional(conn)
    .await?;
    Ok(r.map(|r| CurrentUser {
        user_id,
        email: r.email,
        display_name: r.display_name,
        company_id,
        roles: r.roles,
        disabled_modules: modules::effective_disabled(&r.company_disabled, &r.user_disabled),
    }))
}

/// The file of a run.
struct Built {
    filename: String,
    content_type: &'static str,
    data: Vec<u8>,
}

/// Builds the report file for a schedule as of `now`, with the owner's permissions.
async fn build_file(
    conn: &mut PgConnection,
    docs: &DocumentConfig,
    s: &ScheduleRow,
    owner: &CurrentUser,
    today: NaiveDate,
) -> AppResult<Built> {
    let company = get_company(&mut *conn, s.company_id).await?;
    let lang = company.default_language.as_str();
    let pdf_file = |name: &str| format!("{}-{today}.pdf", crate::routes::slug(name));
    let csv_file = |name: &str| format!("{}-{today}.csv", crate::routes::slug(name));
    let render = |data| async move {
        tradocraft_documents::render_pdf(docs, "report", &data)
            .await
            .map_err(|e| AppError::Validation(format!("the PDF could not be made: {e}")))
    };
    if s.source == "custom" {
        owner.require(Permission::ReportsRead)?;
        #[derive(FromRow)]
        struct Rep {
            name: String,
            description: String,
            definition: serde_json::Value,
            owner_id: Uuid,
            shared: bool,
        }
        let r: Rep = sqlx::query_as(
            "SELECT name, description, definition, owner_id, shared FROM reports.reports
             WHERE id = $1 AND company_id = $2",
        )
        .bind(s.report_id)
        .bind(s.company_id)
        .fetch_optional(&mut *conn)
        .await?
        .ok_or(AppError::NotFound("report"))?;
        if r.owner_id != owner.user_id && !r.shared {
            return Err(AppError::NotFound("report"));
        }
        let def: crate::definition::ReportDefinition = serde_json::from_value(r.definition)
            .map_err(|e| AppError::Validation(format!("the stored report is not valid: {e}")))?;
        let planned = plan(&def, today).map_err(AppError::Validation)?;
        for p in planned.permissions() {
            owner.require(p)?;
        }
        if s.format == "pdf" {
            let result =
                engine::run(&mut *conn, s.company_id, &planned, pdf::MAX_PDF_ROWS + 1, 0).await?;
            if result.rows.len() as i64 > pdf::MAX_PDF_ROWS {
                return Err(AppError::Validation(format!(
                    "the report has more than {} rows; use CSV or add filters",
                    pdf::MAX_PDF_ROWS
                )));
            }
            let data = pdf::build(
                &r.name,
                &r.description,
                &def,
                &result,
                &company.name,
                lang,
                today,
            );
            Ok(Built {
                filename: pdf_file(&r.name),
                content_type: "application/pdf",
                data: render(data).await?,
            })
        } else {
            let result = engine::run_all(&mut *conn, s.company_id, &planned).await?;
            Ok(Built {
                filename: csv_file(&r.name),
                content_type: "text/csv",
                data: crate::routes::csv_of(&result).into_bytes(),
            })
        }
    } else {
        owner.require(Permission::HelpdeskRead)?;
        let spec: HelpdeskReportSpec =
            serde_json::from_value(s.helpdesk.clone().unwrap_or_default()).map_err(|e| {
                AppError::Validation(format!("the stored helpdesk report is not valid: {e}"))
            })?;
        let (from, to) = period_days(&spec.period, today)
            .ok_or_else(|| AppError::Validation("unknown period".into()))?;
        let params = tradocraft_helpdesk::reports::ReportParams {
            from: Some(from),
            to: Some(to),
            team_id: spec.team_id,
            owner_id: spec.owner_id,
            category: spec.category.clone(),
            group: spec.group.clone(),
        };
        let report = tradocraft_helpdesk::reports::build_in_zone(
            &mut *conn,
            s.company_id,
            &params,
            today,
            Some(&s.time_zone),
        )
        .await?;
        let table = tradocraft_helpdesk::reports::table(&report, &spec.table)
            .ok_or_else(|| AppError::Validation("unknown table".into()))?;
        let name = format!("helpdesk-{}-{from}-{to}", spec.table);
        if s.format == "pdf" {
            let data = pdf::from_table(
                &helpdesk_title(&spec.table),
                vec![format!("{from} - {to}")],
                &table.header,
                &table.rows,
                &company.name,
                lang,
                today,
            );
            Ok(Built {
                filename: format!("{name}.pdf"),
                content_type: "application/pdf",
                data: render(data).await?,
            })
        } else {
            Ok(Built {
                filename: format!("{name}.csv"),
                content_type: "text/csv",
                data: table.to_csv().into_bytes(),
            })
        }
    }
}

/// Builds the report and queues one mail per recipient. Returns the number of mails. A refusal
/// (the owner lost access, the report is gone, too many rows) is a validation, not-found or
/// forbidden error and queues nothing; other errors are database trouble.
pub async fn deliver(
    conn: &mut PgConnection,
    docs: &DocumentConfig,
    s: &ScheduleRow,
    now: DateTime<Utc>,
) -> AppResult<usize> {
    let timing = s.timing()?;
    let today = now.with_timezone(&timing.tz).date_naive();
    let owner = load_owner(conn, s.company_id, s.owner_id)
        .await?
        .ok_or_else(|| {
            AppError::Forbidden("the owner of the schedule is no longer active".into())
        })?;
    owner.require(Permission::ReportsSchedule)?;
    let built = build_file(conn, docs, s, &owner, today).await?;
    let company_lang: String =
        sqlx::query_scalar("SELECT default_language::text FROM core.companies WHERE id = $1")
            .bind(s.company_id)
            .fetch_one(&mut *conn)
            .await?;
    // Colleagues who are still active members of the company, in their own language, and the
    // fixed addresses in the company's.
    let users: Vec<(String, Option<String>)> = sqlx::query_as(
        "SELECT u.email, u.language::text FROM core.users u
         JOIN core.user_companies uc ON uc.user_id = u.id AND uc.company_id = $2 AND uc.active
         WHERE u.id = ANY($1) AND u.active ORDER BY u.email",
    )
    .bind(&s.user_ids)
    .bind(s.company_id)
    .fetch_all(&mut *conn)
    .await?;
    let mut to: Vec<(String, String)> = users
        .into_iter()
        .map(|(e, l)| (e, l.unwrap_or_else(|| company_lang.clone())))
        .collect();
    for a in &s.addresses {
        if !to.iter().any(|(e, _)| e.eq_ignore_ascii_case(a)) {
            to.push((a.clone(), company_lang.clone()));
        }
    }
    if to.is_empty() {
        return Err(AppError::Validation(
            "the schedule has no recipient left".into(),
        ));
    }
    for (address, lang) in &to {
        let (subject, body) = mail_text(lang, &s.name, today, &s.frequency);
        mail::enqueue_with_attachment(
            conn,
            s.company_id,
            address,
            &subject,
            &body,
            Attachment {
                filename: &built.filename,
                content_type: built.content_type,
                data: &built.data,
            },
        )
        .await?;
    }
    Ok(to.len())
}

/// Records the outcome of a run on the schedule and in the audit trail (no addresses in it).
pub async fn record_outcome(
    conn: &mut PgConnection,
    s: &ScheduleRow,
    now: DateTime<Utc>,
    advance: bool,
    outcome: &Result<usize, String>,
) -> AppResult<()> {
    let next = if advance {
        Some(next_run(&s.timing()?, now))
    } else {
        None
    };
    sqlx::query(
        "UPDATE reports.schedules SET last_run_at = $2, last_status = $3, last_error = $4,
                next_run_at = coalesce($5, next_run_at)
         WHERE id = $1",
    )
    .bind(s.id)
    .bind(now)
    .bind(if outcome.is_ok() { "sent" } else { "failed" })
    .bind(outcome.as_ref().err())
    .bind(next)
    .execute(&mut *conn)
    .await?;
    audit::record_system(
        conn,
        s.company_id,
        "report_schedule",
        s.id,
        "run",
        serde_json::json!({
            "name": s.name, "source": s.source, "format": s.format,
            "status": if outcome.is_ok() { "sent" } else { "failed" },
            "mails": outcome.as_ref().ok(), "error": outcome.as_ref().err(),
        }),
    )
    .await?;
    Ok(())
}

/// Worker pass: runs the schedules that are due. Each one is claimed with `FOR UPDATE SKIP LOCKED`
/// in its own transaction, so several workers never run the same schedule, and the next run is set
/// in the same transaction as the queued mails. A refused run is recorded (`last_status = failed`,
/// with the reason) and the schedule moves on to its next time. Returns the number of runs.
pub async fn run_due(db: &PgPool, docs: &DocumentConfig) -> anyhow::Result<usize> {
    let mut done = 0;
    for _ in 0..BATCH {
        let mut tx = db.begin().await?;
        let row: Option<ScheduleRow> = sqlx::query_as(&format!(
            "{SELECT_ROW} WHERE active AND next_run_at <= now()
             ORDER BY next_run_at LIMIT 1 FOR UPDATE SKIP LOCKED"
        ))
        .fetch_optional(&mut *tx)
        .await?;
        let Some(s) = row else { break };
        let now = Utc::now();
        let outcome = match deliver(&mut tx, docs, &s, now).await {
            Ok(n) => Ok(n),
            Err(e @ (AppError::Validation(_) | AppError::NotFound(_) | AppError::Forbidden(_))) => {
                Err(e.to_string())
            }
            Err(e) => return Err(anyhow::anyhow!("running schedule {}: {e}", s.id)),
        };
        if let Err(reason) = &outcome {
            tracing::warn!(schedule = %s.id, reason, "scheduled report not sent");
        }
        record_outcome(&mut tx, &s, now, true, &outcome)
            .await
            .map_err(|e| anyhow::anyhow!("recording schedule {}: {e}", s.id))?;
        tx.commit().await?;
        done += 1;
    }
    Ok(done)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn utc(y: i32, m: u32, d: u32, h: u32, mi: u32) -> DateTime<Utc> {
        Utc.with_ymd_and_hms(y, m, d, h, mi, 0).unwrap()
    }

    fn t(freq: &str, weekday: Option<i16>, dom: Option<i16>) -> Timing {
        Timing {
            frequency: freq.into(),
            weekday,
            day_of_month: dom,
            send_time: NaiveTime::from_hms_opt(7, 0, 0).unwrap(),
            tz: chrono_tz::Europe::Brussels,
        }
    }

    #[test]
    fn a_daily_schedule_runs_at_the_local_time_each_day() {
        // 07:00 in Brussels is 06:00 UTC in winter and 05:00 UTC in summer.
        let s = t("daily", None, None);
        assert_eq!(
            next_run(&s, utc(2026, 11, 13, 5, 0)),
            utc(2026, 11, 13, 6, 0)
        );
        assert_eq!(
            next_run(&s, utc(2026, 11, 13, 6, 0)),
            utc(2026, 11, 14, 6, 0)
        );
        assert_eq!(next_run(&s, utc(2026, 7, 1, 4, 0)), utc(2026, 7, 1, 5, 0));
    }

    #[test]
    fn a_weekly_schedule_waits_for_its_weekday() {
        // 2026-11-13 is a Friday; Monday is 1.
        let s = t("weekly", Some(1), None);
        assert_eq!(
            next_run(&s, utc(2026, 11, 13, 12, 0)),
            utc(2026, 11, 16, 6, 0)
        );
        let friday = t("weekly", Some(5), None);
        assert_eq!(
            next_run(&friday, utc(2026, 11, 13, 12, 0)),
            utc(2026, 11, 20, 6, 0)
        );
        assert_eq!(
            next_run(&friday, utc(2026, 11, 13, 5, 0)),
            utc(2026, 11, 13, 6, 0)
        );
    }

    #[test]
    fn a_monthly_schedule_uses_a_day_every_month_has() {
        let s = t("monthly", None, Some(28));
        assert_eq!(
            next_run(&s, utc(2027, 2, 28, 12, 0)),
            utc(2027, 3, 28, 5, 0)
        );
        let first = t("monthly", None, Some(1));
        assert_eq!(
            next_run(&first, utc(2026, 12, 31, 12, 0)),
            utc(2027, 1, 1, 6, 0)
        );
    }

    #[test]
    fn the_clock_change_does_not_move_the_local_time() {
        // The clocks go forward on 2027-03-28: 07:00 is 06:00 UTC before and 05:00 UTC after.
        let s = t("daily", None, None);
        assert_eq!(next_run(&s, utc(2027, 3, 27, 7, 0)), utc(2027, 3, 28, 5, 0));
        assert_eq!(next_run(&s, utc(2027, 3, 26, 7, 0)), utc(2027, 3, 27, 6, 0));
    }

    #[test]
    fn a_missed_run_is_not_repeated() {
        // The worker was down for three days: the next run is computed from now.
        let s = t("daily", None, None);
        assert_eq!(
            next_run(&s, utc(2026, 11, 16, 9, 0)),
            utc(2026, 11, 17, 6, 0)
        );
    }

    #[test]
    fn helpdesk_periods_end_yesterday_or_at_a_week_or_month_boundary() {
        let d = |y, m, day| NaiveDate::from_ymd_opt(y, m, day).unwrap();
        let today = d(2026, 11, 13); // a Friday
        assert_eq!(
            period_days("yesterday", today),
            Some((d(2026, 11, 12), d(2026, 11, 12)))
        );
        assert_eq!(
            period_days("last_7_days", today),
            Some((d(2026, 11, 6), d(2026, 11, 12)))
        );
        assert_eq!(
            period_days("last_30_days", today),
            Some((d(2026, 10, 14), d(2026, 11, 12)))
        );
        assert_eq!(
            period_days("last_week", today),
            Some((d(2026, 11, 2), d(2026, 11, 8)))
        );
        assert_eq!(
            period_days("last_month", today),
            Some((d(2026, 10, 1), d(2026, 10, 31)))
        );
        assert_eq!(
            period_days("last_month", d(2027, 1, 5)),
            Some((d(2026, 12, 1), d(2026, 12, 31)))
        );
        assert_eq!(period_days("nonsense", today), None);
    }

    #[test]
    fn the_mail_is_in_the_recipients_language() {
        let day = NaiveDate::from_ymd_opt(2026, 11, 13).unwrap();
        for lang in ["nl", "fr", "en", "de", "es"] {
            let (subject, body) = mail_text(lang, "Open\nquotations", day, "weekly");
            assert!(subject.contains("Open quotations (2026-11-13)"), "{lang}");
            assert!(!subject.contains('\n'));
            assert!(body.contains("Open quotations"), "{lang}");
            assert!(!body.contains('{'), "{lang}");
        }
        assert!(mail_text("nl", "x", day, "daily")
            .0
            .starts_with("Gepland rapport"));
    }
}
