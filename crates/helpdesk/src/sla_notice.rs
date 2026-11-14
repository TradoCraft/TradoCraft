//! SLA notices to the customer (ADR 0064): an acknowledgement when a ticket is created and an
//! optional notice when the first response time has run out.
//!
//! Which tickets get which notice is configured per team and priority
//! (`helpdesk.sla_notice_settings`); nothing is sent until an administrator switches it on. The
//! mail is queued in `core.mail_outbox`, so the outbound policy of ADR 0048 applies where the outbox
//! is emptied. Each notice is sent at most once per ticket (`helpdesk.sla_notice_log`).

use axum::extract::State;
use axum::Json;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection, PgPool};
use tradocraft_core::{
    audit, mail, new_id, AppError, AppResult, AppState, CurrentUser, Permission,
};
use utoipa::ToSchema;
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::automail::valid_address;
use crate::sla::Calendar;

type ErrorBody = tradocraft_core::error::ErrorBody;

/// Channels where the customer started the conversation themselves. Staff-made tickets (phone,
/// manual) are left out: the agent is already talking to the customer.
const CHANNELS: [&str; 2] = ["email", "portal"];
/// At most this many notices to one address within an hour, so a mail loop cannot become a storm.
const PER_ADDRESS_PER_HOUR: i64 = 5;
/// The zone used to show a deadline when the company has no business calendar.
const DEFAULT_ZONE: &str = "Europe/Brussels";

// ---------------------------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------------------------

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, FromRow, ToSchema)]
pub struct SlaNoticeRule {
    /// Absent: every team.
    pub team_id: Option<Uuid>,
    /// low | normal | high | urgent. Absent: every priority.
    pub priority: Option<String>,
    /// Send an acknowledgement (ticket number and target response time) on creation.
    pub ack_enabled: bool,
    /// Send a notice when the first response time has run out without an answer.
    pub breach_enabled: bool,
}

#[derive(Debug, Serialize, Deserialize, ToSchema)]
pub struct SlaNoticeSettings {
    /// The most specific rule wins: team and priority, then team, then priority, then neither.
    /// A ticket that matches no rule gets no notice.
    pub rules: Vec<SlaNoticeRule>,
}

async fn load_rules(
    conn: &mut PgConnection,
    company_id: Uuid,
) -> Result<Vec<SlaNoticeRule>, sqlx::Error> {
    sqlx::query_as(
        "SELECT team_id, priority, ack_enabled, breach_enabled FROM helpdesk.sla_notice_settings
         WHERE company_id = $1 ORDER BY (team_id IS NULL), team_id, priority NULLS FIRST",
    )
    .bind(company_id)
    .fetch_all(conn)
    .await
}

/// The rule that applies to a ticket: team and priority, else team, else priority, else neither.
pub fn pick<'a>(
    rules: &'a [SlaNoticeRule],
    team: Option<Uuid>,
    priority: &str,
) -> Option<&'a SlaNoticeRule> {
    let find = |t: Option<Uuid>, p: Option<&str>| {
        rules
            .iter()
            .find(|r| r.team_id == t && r.priority.as_deref() == p)
    };
    find(team, Some(priority))
        .or_else(|| team.and_then(|t| find(Some(t), None)))
        .or_else(|| find(None, Some(priority)))
        .or_else(|| find(None, None))
}

#[utoipa::path(get, path = "/helpdesk/sla-notices", tag = "helpdesk",
    responses((status = 200, body = SlaNoticeSettings), (status = 403, body = ErrorBody)))]
async fn get_sla_notices(
    State(state): State<AppState>,
    user: CurrentUser,
) -> AppResult<Json<SlaNoticeSettings>> {
    user.require(Permission::HelpdeskAdmin)?;
    let mut conn = state.db.acquire().await?;
    Ok(Json(SlaNoticeSettings {
        rules: load_rules(&mut conn, user.company_id).await?,
    }))
}

/// Replaces the rules. Tickets that were created earlier are not acknowledged afterwards; a breach
/// notice can still go out for an open ticket that is late when its rule is switched on.
#[utoipa::path(put, path = "/helpdesk/sla-notices", tag = "helpdesk", request_body = SlaNoticeSettings,
    responses((status = 200, body = SlaNoticeSettings), (status = 403, body = ErrorBody), (status = 404, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn put_sla_notices(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<SlaNoticeSettings>,
) -> AppResult<Json<SlaNoticeSettings>> {
    user.require(Permission::HelpdeskAdmin)?;
    let mut seen = std::collections::HashSet::new();
    for r in &input.rules {
        if let Some(p) = &r.priority {
            if !crate::tickets::PRIORITIES.contains(&p.as_str()) {
                return Err(AppError::Validation(format!(
                    "priority must be one of {}",
                    crate::tickets::PRIORITIES.join(", ")
                )));
            }
        }
        if !seen.insert((r.team_id, r.priority.clone())) {
            return Err(AppError::Validation(
                "each team and priority combination can be listed once".into(),
            ));
        }
    }
    let mut tx = state.db.begin().await?;
    for r in &input.rules {
        if let Some(team) = r.team_id {
            let ok: bool = sqlx::query_scalar(
                "SELECT EXISTS (SELECT 1 FROM helpdesk.teams WHERE id = $1 AND company_id = $2)",
            )
            .bind(team)
            .bind(user.company_id)
            .fetch_one(&mut *tx)
            .await?;
            if !ok {
                return Err(AppError::NotFound("team"));
            }
        }
    }
    // Serialises concurrent replacements for the company until this transaction ends.
    sqlx::query("SELECT id FROM core.companies WHERE id = $1 FOR UPDATE")
        .bind(user.company_id)
        .fetch_optional(&mut *tx)
        .await?;
    sqlx::query("DELETE FROM helpdesk.sla_notice_settings WHERE company_id = $1")
        .bind(user.company_id)
        .execute(&mut *tx)
        .await?;
    for r in &input.rules {
        sqlx::query(
            "INSERT INTO helpdesk.sla_notice_settings (id, company_id, team_id, priority, ack_enabled, breach_enabled)
             VALUES ($1, $2, $3, $4, $5, $6)",
        )
        .bind(new_id())
        .bind(user.company_id)
        .bind(r.team_id)
        .bind(&r.priority)
        .bind(r.ack_enabled)
        .bind(r.breach_enabled)
        .execute(&mut *tx)
        .await?;
    }
    audit::record(
        &mut tx,
        &user,
        "helpdesk_settings",
        user.company_id,
        "sla_notices_updated",
        serde_json::json!({ "rules": input.rules }),
    )
    .await?;
    let rules = load_rules(&mut tx, user.company_id).await?;
    tx.commit().await?;
    Ok(Json(SlaNoticeSettings { rules }))
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new().routes(routes!(get_sla_notices, put_sla_notices))
}

// ---------------------------------------------------------------------------------------------
// Texts
// ---------------------------------------------------------------------------------------------

/// The words of one language. (The language is the ticket's: the contact's, else the customer's,
/// else the one detected in the mail, else the company default, as set when the ticket was made.)
/// `{n}` style placeholders are replaced with `str::replace`.
struct Text {
    ack_subject: &'static str,
    breach_subject: &'static str,
    hello: &'static str,
    ack_intro: &'static str,
    subject_label: &'static str,
    target: &'static str,
    business_note: &'static str,
    expected: &'static str,
    breach_intro: &'static str,
    breach_target: &'static str,
    keep_number: &'static str,
    minute: (&'static str, &'static str),
    hour: (&'static str, &'static str),
    day: (&'static str, &'static str),
}

fn text(lang: &str) -> Text {
    match lang {
        "nl" => Text {
            ack_subject: "We hebben uw aanvraag ontvangen",
            breach_subject: "Uw aanvraag is nog niet beantwoord",
            hello: "Beste {name},",
            ack_intro: "Wij hebben uw aanvraag ontvangen en geregistreerd als ticket {number}.",
            subject_label: "Onderwerp",
            target: "Wij streven ernaar u binnen {duration} te antwoorden.",
            business_note: "Dit telt in onze openingsuren.",
            expected: "Verwacht uiterlijk: {when} ({zone})",
            breach_intro: "Wij hebben uw aanvraag (ticket {number}) nog niet kunnen beantwoorden en onze streeftermijn is verstreken. Onze excuses voor het wachten; een collega neemt zo snel mogelijk contact met u op.",
            breach_target: "Onze streeftermijn voor een eerste antwoord was {duration}.",
            keep_number: "Laat het ticketnummer in het onderwerp staan wanneer u antwoordt.",
            minute: ("minuut", "minuten"),
            hour: ("uur", "uur"),
            day: ("dag", "dagen"),
        },
        "fr" => Text {
            ack_subject: "Nous avons bien reçu votre demande",
            breach_subject: "Votre demande n'a pas encore reçu de réponse",
            hello: "Bonjour {name},",
            ack_intro: "Nous avons bien reçu votre demande et l'avons enregistrée sous le ticket {number}.",
            subject_label: "Sujet",
            target: "Nous visons à vous répondre dans un délai de {duration}.",
            business_note: "Ce délai est compté en heures d'ouverture.",
            expected: "Réponse attendue au plus tard : {when} ({zone})",
            breach_intro: "Nous n'avons pas encore pu répondre à votre demande (ticket {number}) et notre délai cible est dépassé. Nous nous excusons de l'attente ; un collègue vous contactera dès que possible.",
            breach_target: "Notre délai cible pour une première réponse était de {duration}.",
            keep_number: "Veuillez conserver le numéro du ticket dans l'objet de vos réponses.",
            minute: ("minute", "minutes"),
            hour: ("heure", "heures"),
            day: ("jour", "jours"),
        },
        "de" => Text {
            ack_subject: "Wir haben Ihre Anfrage erhalten",
            breach_subject: "Ihre Anfrage ist noch nicht beantwortet",
            hello: "Guten Tag {name},",
            ack_intro: "Wir haben Ihre Anfrage erhalten und als Ticket {number} erfasst.",
            subject_label: "Betreff",
            target: "Wir bemühen uns, Ihnen innerhalb von {duration} zu antworten.",
            business_note: "Die Frist wird in unseren Geschäftszeiten gerechnet.",
            expected: "Antwort spätestens: {when} ({zone})",
            breach_intro: "Wir konnten Ihre Anfrage (Ticket {number}) noch nicht beantworten und unsere Zielzeit ist überschritten. Wir bitten um Entschuldigung; ein Kollege meldet sich so schnell wie möglich bei Ihnen.",
            breach_target: "Unsere Zielzeit für eine erste Antwort war {duration}.",
            keep_number: "Bitte lassen Sie die Ticketnummer im Betreff stehen, wenn Sie antworten.",
            minute: ("Minute", "Minuten"),
            hour: ("Stunde", "Stunden"),
            day: ("Tag", "Tage"),
        },
        "es" => Text {
            ack_subject: "Hemos recibido su solicitud",
            breach_subject: "Su solicitud aún no ha sido respondida",
            hello: "Estimado/a {name}:",
            ack_intro: "Hemos recibido su solicitud y la hemos registrado como ticket {number}.",
            subject_label: "Asunto",
            target: "Nos proponemos responderle en un plazo de {duration}.",
            business_note: "El plazo se cuenta en nuestro horario de atención.",
            expected: "Respuesta prevista como máximo: {when} ({zone})",
            breach_intro: "Todavía no hemos podido responder a su solicitud (ticket {number}) y nuestro plazo objetivo ha vencido. Disculpe la espera; un compañero se pondrá en contacto con usted lo antes posible.",
            breach_target: "Nuestro plazo objetivo para una primera respuesta era de {duration}.",
            keep_number: "Mantenga el número de ticket en el asunto cuando responda.",
            minute: ("minuto", "minutos"),
            hour: ("hora", "horas"),
            day: ("día", "días"),
        },
        _ => Text {
            ack_subject: "We have received your request",
            breach_subject: "Your request has not been answered yet",
            hello: "Dear {name},",
            ack_intro: "We have received your request and registered it as ticket {number}.",
            subject_label: "Subject",
            target: "We aim to reply within {duration}.",
            business_note: "This is counted in our opening hours.",
            expected: "Expected at the latest: {when} ({zone})",
            breach_intro: "We have not yet been able to answer your request (ticket {number}) and our target time has passed. We apologise for the wait; a colleague will contact you as soon as possible.",
            breach_target: "Our target for a first reply was {duration}.",
            keep_number: "Please keep the ticket number in the subject when you reply.",
            minute: ("minute", "minutes"),
            hour: ("hour", "hours"),
            day: ("day", "days"),
        },
    }
}

/// "30 minutes", "4 hours", "1 hour 30 minutes", "3 days": days from 48 hours on, and only when it
/// is a whole number of days.
pub fn duration_text(lang: &str, minutes: i32) -> String {
    let t = text(lang);
    let unit = |n: i32, u: (&str, &str)| format!("{n} {}", if n == 1 { u.0 } else { u.1 });
    if minutes >= 48 * 60 && minutes % (24 * 60) == 0 {
        unit(minutes / (24 * 60), t.day)
    } else if minutes < 60 {
        unit(minutes, t.minute)
    } else if minutes % 60 == 0 {
        unit(minutes / 60, t.hour)
    } else {
        format!(
            "{} {}",
            unit(minutes / 60, t.hour),
            unit(minutes % 60, t.minute)
        )
    }
}

pub struct Notice<'a> {
    pub lang: &'a str,
    pub number: &'a str,
    pub subject: &'a str,
    pub name: &'a str,
    pub target_minutes: i32,
    /// The deadline, when known, already in the zone to show.
    pub due_local: Option<(String, String)>,
    /// The deadline is counted in business hours.
    pub business: bool,
}

/// Subject and body of the acknowledgement. The ticket tag keeps a reply with the ticket.
pub fn ack_mail(n: &Notice) -> (String, String) {
    let t = text(n.lang);
    let duration = duration_text(n.lang, n.target_minutes);
    let mut body = vec![
        t.hello.replace("{name}", n.name),
        String::new(),
        t.ack_intro.replace("{number}", n.number),
        format!("{}: {}", t.subject_label, n.subject),
        String::new(),
        t.target.replace("{duration}", &duration),
    ];
    if n.business {
        body.push(t.business_note.to_string());
    }
    if let Some((when, zone)) = &n.due_local {
        body.push(t.expected.replace("{when}", when).replace("{zone}", zone));
    }
    body.push(String::new());
    body.push(t.keep_number.to_string());
    (
        format!("{} [Ticket#{}]", t.ack_subject, n.number),
        body.join("\n") + "\n",
    )
}

/// Subject and body of the notice that the first response time has run out.
pub fn breach_mail(n: &Notice) -> (String, String) {
    let t = text(n.lang);
    let duration = duration_text(n.lang, n.target_minutes);
    let mut body = vec![
        t.hello.replace("{name}", n.name),
        String::new(),
        t.breach_intro.replace("{number}", n.number),
        format!("{}: {}", t.subject_label, n.subject),
        String::new(),
        t.breach_target.replace("{duration}", &duration),
    ];
    if n.business {
        body.push(t.business_note.to_string());
    }
    body.push(String::new());
    body.push(t.keep_number.to_string());
    (
        format!("{} [Ticket#{}]", t.breach_subject, n.number),
        body.join("\n") + "\n",
    )
}

// ---------------------------------------------------------------------------------------------
// Sending
// ---------------------------------------------------------------------------------------------

#[derive(FromRow)]
struct T {
    id: Uuid,
    company_id: Uuid,
    number: String,
    subject: String,
    priority: String,
    team_id: Option<Uuid>,
    contact_name: String,
    contact_email: String,
    customer_name: Option<String>,
    language: String,
    first_response_due_at: Option<DateTime<Utc>>,
    sla_first_response_minutes: Option<i32>,
}

const SELECT: &str = "SELECT t.id, t.company_id, t.number, t.subject, t.priority, t.team_id,
        t.contact_name, t.contact_email, c.name AS customer_name,
        t.language::text AS language,
        t.first_response_due_at, t.sla_first_response_minutes
 FROM helpdesk.tickets t
 LEFT JOIN crm.customers c ON c.id = t.customer_id";

/// Senders that never read mail: a notice to them is at best wasted and at worst starts a loop.
fn automated(address: &str) -> bool {
    let local = address.split('@').next().unwrap_or("").to_lowercase();
    [
        "noreply",
        "no-reply",
        "donotreply",
        "do-not-reply",
        "mailer-daemon",
        "postmaster",
    ]
    .iter()
    .any(|p| local == *p || local.starts_with(&format!("{p}+")))
}

/// Queues a notice of `kind` for the ticket, once. Returns false when nothing was queued.
async fn queue(
    conn: &mut PgConnection,
    t: &T,
    kind: &str,
    calendar: Option<&Calendar>,
) -> AppResult<bool> {
    let address = t.contact_email.trim().to_lowercase();
    if !valid_address(&address) || automated(&address) {
        return Ok(false);
    }
    // Held until the transaction ends, so the count, the claim and the enqueue of concurrent
    // notices to the same address run one after another.
    sqlx::query("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))")
        .bind(format!("sla-notice:{}:{address}", t.company_id))
        .execute(&mut *conn)
        .await?;
    let recent: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM helpdesk.sla_notice_log
         WHERE company_id = $1 AND address = $2 AND sent_at > now() - interval '1 hour'",
    )
    .bind(t.company_id)
    .bind(&address)
    .fetch_one(&mut *conn)
    .await?;
    if recent >= PER_ADDRESS_PER_HOUR {
        return Ok(false);
    }
    let claimed: Option<i32> = sqlx::query_scalar(
        "INSERT INTO helpdesk.sla_notice_log (ticket_id, kind, company_id, address)
         VALUES ($1, $2, $3, $4) ON CONFLICT DO NOTHING RETURNING 1",
    )
    .bind(t.id)
    .bind(kind)
    .bind(t.company_id)
    .bind(&address)
    .fetch_optional(&mut *conn)
    .await?;
    if claimed.is_none() {
        return Ok(false);
    }
    let name = t
        .customer_name
        .as_deref()
        .filter(|n| !n.trim().is_empty())
        .unwrap_or(&t.contact_name);
    let zone = calendar
        .map(|c| c.tz)
        .unwrap_or_else(|| DEFAULT_ZONE.parse().unwrap_or(chrono_tz::Europe::Brussels));
    let notice = Notice {
        lang: &t.language,
        number: &t.number,
        subject: &crate::automail::one_line(&t.subject),
        name,
        target_minutes: t.sla_first_response_minutes.unwrap_or(0),
        due_local: t.first_response_due_at.map(|d| {
            (
                d.with_timezone(&zone).format("%Y-%m-%d %H:%M").to_string(),
                zone.name().to_string(),
            )
        }),
        business: calendar.is_some(),
    };
    let (subject, body) = if kind == "ack" {
        ack_mail(&notice)
    } else {
        breach_mail(&notice)
    };
    mail::enqueue(conn, t.company_id, &address, &subject, &body).await?;
    audit::record_system(
        conn,
        t.company_id,
        "ticket",
        t.id,
        if kind == "ack" {
            "sla_ack_sent"
        } else {
            "sla_breach_notice_sent"
        },
        serde_json::json!({ "language": t.language, "priority": t.priority }),
    )
    .await?;
    Ok(true)
}

/// Acknowledges a new ticket to its customer when the settings ask for it. Called in the
/// transaction that creates the ticket, after the SLA and the automation rules ran. The mail is
/// not held back outside business hours: an acknowledgement is useful at once, and the deadline in
/// it is counted in business time.
pub async fn acknowledge(
    conn: &mut PgConnection,
    company_id: Uuid,
    ticket_id: Uuid,
) -> AppResult<bool> {
    #[derive(FromRow)]
    struct Gate {
        internal: bool,
        channel: String,
        split: bool,
        merged: bool,
    }
    let Some(gate): Option<Gate> = sqlx::query_as(
        "SELECT internal, channel, split_from_id IS NOT NULL AS split, merged_into_id IS NOT NULL AS merged
         FROM helpdesk.tickets WHERE id = $1 AND company_id = $2",
    )
    .bind(ticket_id)
    .bind(company_id)
    .fetch_optional(&mut *conn)
    .await?
    else {
        return Ok(false);
    };
    // A split ticket continues a conversation the customer already has a ticket for.
    if gate.internal || gate.split || gate.merged || !CHANNELS.contains(&gate.channel.as_str()) {
        return Ok(false);
    }
    let rules = load_rules(conn, company_id).await?;
    if rules.is_empty() {
        return Ok(false);
    }
    let t: T = sqlx::query_as(&format!("{SELECT} WHERE t.id = $1 AND t.company_id = $2"))
        .bind(ticket_id)
        .bind(company_id)
        .fetch_one(&mut *conn)
        .await?;
    if !pick(&rules, t.team_id, &t.priority).is_some_and(|r| r.ack_enabled) {
        return Ok(false);
    }
    let calendar = crate::calendar::load_calendar(conn, company_id, t.team_id).await?;
    queue(conn, &t, "ack", calendar.as_ref()).await
}

/// Worker pass: tells customers whose first response time has run out that they are not forgotten,
/// once per ticket and only while the business is open (outside the opening hours the notice
/// waits for the next opening). Returns the number of notices queued.
pub async fn send_breach_notices(db: &PgPool) -> anyhow::Result<usize> {
    let mut sent = 0;
    // Eligibility (the applicable rule, the address) is decided per ticket below, so the candidates
    // are paged forward: tickets that are not eligible must not occupy the batch.
    let mut after: Option<(DateTime<Utc>, Uuid)> = None;
    loop {
        let candidates: Vec<(Uuid, Uuid, DateTime<Utc>)> = sqlx::query_as(
            "SELECT t.id, t.company_id, t.first_response_due_at FROM helpdesk.tickets t
             WHERE t.closed_at IS NULL AND NOT t.internal AND t.merged_into_id IS NULL
               AND t.split_from_id IS NULL AND t.sla_paused_at IS NULL
               AND t.channel = ANY($1) AND t.first_response_at IS NULL AND t.first_response_due_at < now()
               AND EXISTS (SELECT 1 FROM helpdesk.sla_notice_settings s
                           WHERE s.company_id = t.company_id AND s.breach_enabled)
               AND NOT EXISTS (SELECT 1 FROM helpdesk.sla_notice_log l
                               WHERE l.ticket_id = t.id AND l.kind = 'breach')
               AND ($2::timestamptz IS NULL OR (t.first_response_due_at, t.id) > ($2, $3))
             ORDER BY t.first_response_due_at, t.id LIMIT 100",
        )
        .bind(CHANNELS.map(String::from).to_vec())
        .bind(after.map(|a| a.0))
        .bind(after.map(|a| a.1))
        .fetch_all(db)
        .await?;
        let Some(last) = candidates.last() else { break };
        after = Some((last.2, last.0));
        sent += notify_page(db, candidates.iter().map(|c| (c.0, c.1))).await?;
    }
    Ok(sent)
}

async fn notify_page(
    db: &PgPool,
    candidates: impl Iterator<Item = (Uuid, Uuid)>,
) -> anyhow::Result<usize> {
    let mut sent = 0;
    for (id, company_id) in candidates {
        let mut tx = db.begin().await?;
        // Re-read under the lock: the ticket may have been answered since.
        let t: Option<T> = sqlx::query_as(&format!(
            "{SELECT} WHERE t.id = $1 AND t.closed_at IS NULL AND t.first_response_at IS NULL
               AND t.first_response_due_at < now() AND NOT t.internal
               AND t.merged_into_id IS NULL AND t.split_from_id IS NULL
               AND t.sla_paused_at IS NULL FOR UPDATE OF t SKIP LOCKED"
        ))
        .bind(id)
        .fetch_optional(&mut *tx)
        .await?;
        let Some(t) = t else { continue };
        let rules = load_rules(&mut tx, company_id).await?;
        if !pick(&rules, t.team_id, &t.priority).is_some_and(|r| r.breach_enabled) {
            continue;
        }
        let calendar = crate::calendar::load_calendar(&mut tx, company_id, t.team_id).await?;
        if calendar.as_ref().is_some_and(|c| !c.is_open_at(Utc::now())) {
            continue;
        }
        if queue(&mut tx, &t, "breach", calendar.as_ref()).await? {
            sent += 1;
        }
        tx.commit().await?;
    }
    Ok(sent)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn r(team: Option<u128>, p: Option<&str>, ack: bool) -> SlaNoticeRule {
        SlaNoticeRule {
            team_id: team.map(Uuid::from_u128),
            priority: p.map(String::from),
            ack_enabled: ack,
            breach_enabled: false,
        }
    }

    #[test]
    fn the_most_specific_rule_wins() {
        let rules = vec![
            r(None, None, true),
            r(None, Some("urgent"), false),
            r(Some(1), None, false),
            r(Some(1), Some("urgent"), true),
        ];
        let team = Some(Uuid::from_u128(1));
        assert!(pick(&rules, team, "urgent").unwrap().ack_enabled); // team + priority
        assert!(!pick(&rules, team, "low").unwrap().ack_enabled); // team
        assert!(!pick(&rules, None, "urgent").unwrap().ack_enabled); // priority
        assert!(
            pick(&rules, Some(Uuid::from_u128(2)), "low")
                .unwrap()
                .ack_enabled
        ); // neither
        assert!(pick(&[], None, "low").is_none());
    }

    #[test]
    fn durations_read_naturally_in_every_language() {
        assert_eq!(duration_text("en", 30), "30 minutes");
        assert_eq!(duration_text("en", 60), "1 hour");
        assert_eq!(duration_text("en", 240), "4 hours");
        assert_eq!(duration_text("en", 90), "1 hour 30 minutes");
        assert_eq!(duration_text("en", 60 * 24), "24 hours");
        assert_eq!(duration_text("en", 60 * 24 * 3), "3 days");
        assert_eq!(duration_text("nl", 480), "8 uur");
        assert_eq!(duration_text("fr", 120), "2 heures");
        assert_eq!(duration_text("de", 1), "1 Minute");
        assert_eq!(duration_text("es", 60 * 24 * 2), "2 días");
    }

    #[test]
    fn the_acknowledgement_names_the_ticket_and_the_target() {
        for lang in ["nl", "fr", "en", "de", "es"] {
            let (subject, body) = ack_mail(&Notice {
                lang,
                number: "T2026-00007",
                subject: "Pump noise",
                name: "Anna",
                target_minutes: 240,
                due_local: Some(("2026-11-05 13:00".into(), "Europe/Brussels".into())),
                business: true,
            });
            assert!(subject.contains("[Ticket#T2026-00007]"), "{lang}");
            assert!(body.contains("T2026-00007"), "{lang}");
            assert!(body.contains("Pump noise"), "{lang}");
            assert!(body.contains("Anna"), "{lang}");
            assert!(body.contains("2026-11-05 13:00"), "{lang}");
            assert!(!body.contains('{'), "{lang}: {body}");
        }
    }

    #[test]
    fn automated_senders_get_nothing() {
        assert!(automated("noreply@x.example"));
        assert!(automated("No-Reply@x.example"));
        assert!(automated("mailer-daemon@x.example"));
        assert!(automated("noreply+abc@x.example"));
        assert!(!automated("anna@x.example"));
    }
}
