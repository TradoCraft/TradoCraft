//! Worker heartbeat (ADR 0052, roadmap D1).
//!
//! The background worker (`apps/worker`) is one polling loop. Each pass it calls [`beat`], which
//! updates the single row of `core.worker_heartbeat`. When the previous beat is older than
//! [`late_after`], the worker was down: [`beat`] records the gap in `core.worker_outages` and
//! queues a system mail to the administrators of every company, in the same transaction.
//!
//! `GET /admin/worker` reports the state to administrators, so the app can warn them while the
//! worker is down rather than after it comes back.

use axum::extract::State;
use axum::Json;
use chrono::{DateTime, Utc};
use serde::Serialize;
use sqlx::{FromRow, PgConnection, PgPool};
use utoipa::ToSchema;
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::{mail, new_id, AppResult, AppState, CurrentUser, Permission};

type ErrorBody = crate::error::ErrorBody;

/// Grace on top of the missed passes, for a slow pass (a large outbox, a slow IMAP server).
const GRACE_SECONDS: i64 = 60;
/// Passes that may be missed before the worker counts as down.
const MISSED_PASSES: i64 = 3;

/// How old the last beat may be, in seconds, before the worker counts as down: three missed passes
/// plus a minute of grace. With the default `POLL_SECONDS=30` that is two and a half minutes.
pub fn late_after(interval_seconds: i32) -> i64 {
    MISSED_PASSES * i64::from(interval_seconds.max(1)) + GRACE_SECONDS
}

/// Who and what is beating; fixed for the life of a worker process.
#[derive(Debug, Clone)]
pub struct WorkerInfo {
    pub started_at: DateTime<Utc>,
    pub interval_seconds: i32,
    pub version: String,
    pub host: String,
}

/// A period without any beat.
#[derive(Debug, Clone, PartialEq, Serialize, FromRow, ToSchema)]
pub struct Outage {
    pub down_from: DateTime<Utc>,
    pub down_until: DateTime<Utc>,
}

/// Writes a beat. Returns the outage that just ended when the previous beat was late; the
/// administrators' mails for it are queued in the same transaction. Several workers may beat at
/// once: the row lock makes the gap count once.
pub async fn beat(db: &PgPool, info: &WorkerInfo) -> Result<Option<Outage>, sqlx::Error> {
    let mut tx = db.begin().await?;
    let previous: Option<(DateTime<Utc>, i32, DateTime<Utc>)> = sqlx::query_as(
        "SELECT last_beat_at, interval_seconds, now() FROM core.worker_heartbeat FOR UPDATE",
    )
    .fetch_optional(&mut *tx)
    .await?;
    sqlx::query(
        "INSERT INTO core.worker_heartbeat (id, last_beat_at, started_at, interval_seconds, version, host)
         VALUES (true, now(), $1, $2, $3, $4)
         ON CONFLICT (id) DO UPDATE SET last_beat_at = now(), started_at = $1,
             interval_seconds = $2, version = $3, host = $4",
    )
    .bind(info.started_at)
    .bind(info.interval_seconds)
    .bind(&info.version)
    .bind(&info.host)
    .execute(&mut *tx)
    .await?;
    let outage = match previous {
        Some((last, interval, now)) if (now - last).num_seconds() > late_after(interval) => {
            let outage = Outage {
                down_from: last,
                down_until: now,
            };
            sqlx::query(
                "INSERT INTO core.worker_outages (id, down_from, down_until) VALUES ($1, $2, $3)",
            )
            .bind(new_id())
            .bind(outage.down_from)
            .bind(outage.down_until)
            .execute(&mut *tx)
            .await?;
            notify_admins(&mut tx, &outage).await?;
            Some(outage)
        }
        _ => None,
    };
    tx.commit().await?;
    Ok(outage)
}

#[derive(FromRow)]
struct Recipient {
    company_id: Uuid,
    email: String,
    language: String,
}

/// Queues one mail per active administrator per company, from that company's address.
async fn notify_admins(conn: &mut PgConnection, outage: &Outage) -> Result<(), sqlx::Error> {
    let recipients: Vec<Recipient> = sqlx::query_as(
        "SELECT uc.company_id, u.email, coalesce(u.language, c.default_language)::text AS language
         FROM core.users u
         JOIN core.user_companies uc ON uc.user_id = u.id
         JOIN core.companies c ON c.id = uc.company_id
         WHERE u.active AND 'admin' = ANY(uc.roles)
         ORDER BY uc.company_id, u.email",
    )
    .fetch_all(&mut *conn)
    .await?;
    for r in recipients {
        let (subject, body) = outage_mail(&r.language, outage);
        mail::enqueue(conn, r.company_id, &r.email, subject, &body).await?;
    }
    Ok(())
}

/// Subject and body of the "worker was down" mail. Times are in UTC: the worker serves every
/// company and has no time zone of its own.
fn outage_mail(lang: &str, o: &Outage) -> (&'static str, String) {
    let from = o.down_from.format("%Y-%m-%d %H:%M UTC").to_string();
    let until = o.down_until.format("%Y-%m-%d %H:%M UTC").to_string();
    let minutes = (o.down_until - o.down_from)
        .num_minutes()
        .max(1)
        .to_string();
    let (subject, body) = match lang {
        "nl" => (
            "De achtergrondverwerking lag stil",
            "De achtergrondverwerking van TradoCraft heeft van {from} tot {until} niet gedraaid (ongeveer {min} minuten). Ze draait weer.\n\nIn die periode werden geen e-mails verstuurd of opgehaald, geen SLA-escalaties gedaan en geen onderhoudsbezoeken gepland. Wat bleef liggen, wordt nu verwerkt; controleer of er tijdskritische zaken tussen zaten.\n",
        ),
        "fr" => (
            "Le traitement en arrière-plan était arrêté",
            "Le traitement en arrière-plan de TradoCraft ne fonctionnait pas du {from} au {until} (environ {min} minutes). Il fonctionne à nouveau.\n\nPendant cette période, aucun e-mail n'a été envoyé ni relevé, aucune escalade SLA n'a eu lieu et aucune visite de maintenance n'a été planifiée. Ce qui était en attente est traité maintenant ; vérifiez si des points urgents s'y trouvaient.\n",
        ),
        "de" => (
            "Die Hintergrundverarbeitung war ausgefallen",
            "Die Hintergrundverarbeitung von TradoCraft lief von {from} bis {until} nicht (etwa {min} Minuten). Sie läuft wieder.\n\nIn dieser Zeit wurden keine E-Mails gesendet oder abgerufen, keine SLA-Eskalationen ausgelöst und keine Wartungsbesuche geplant. Liegengebliebenes wird jetzt verarbeitet; prüfen Sie, ob Zeitkritisches dabei war.\n",
        ),
        "es" => (
            "El procesamiento en segundo plano estuvo detenido",
            "El procesamiento en segundo plano de TradoCraft no funcionó desde {from} hasta {until} (unos {min} minutos). Vuelve a funcionar.\n\nDurante ese tiempo no se enviaron ni recibieron correos, no se hicieron escalados de SLA y no se planificaron visitas de mantenimiento. Lo pendiente se procesa ahora; compruebe si había algo urgente.\n",
        ),
        _ => (
            "The background worker was down",
            "The TradoCraft background worker did not run from {from} to {until} (about {min} minutes). It is running again.\n\nDuring that time no e-mail was sent or fetched, no SLA breaches were escalated and no maintenance visits were planned. What was waiting is being processed now; check whether anything urgent was among it.\n",
        ),
    };
    (
        subject,
        body.replace("{from}", &from)
            .replace("{until}", &until)
            .replace("{min}", &minutes),
    )
}

/// Whether the worker is running, as far as its heartbeat tells.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum WorkerState {
    /// The last beat is recent.
    Running,
    /// The last beat is older than `late_after_seconds`: the worker is down or stuck.
    Down,
    /// No worker has ever beaten against this database.
    NeverSeen,
}

/// The worker's heartbeat as administrators see it.
#[derive(Debug, Serialize, ToSchema)]
pub struct WorkerStatus {
    pub state: WorkerState,
    pub last_beat_at: Option<DateTime<Utc>>,
    /// Seconds since the last beat, by the database clock.
    pub age_seconds: Option<i64>,
    /// After how many seconds without a beat the worker counts as down.
    pub late_after_seconds: Option<i64>,
    pub interval_seconds: Option<i32>,
    /// When the worker process that wrote the last beat started.
    pub started_at: Option<DateTime<Utc>>,
    pub version: Option<String>,
    pub host: Option<String>,
    /// The most recent period without beats that has ended.
    pub last_outage: Option<Outage>,
}

#[derive(FromRow)]
struct HeartbeatRow {
    last_beat_at: DateTime<Utc>,
    age_seconds: i64,
    interval_seconds: i32,
    started_at: DateTime<Utc>,
    version: String,
    host: String,
}

/// Reads the heartbeat and the last outage.
pub async fn status(db: &PgPool) -> Result<WorkerStatus, sqlx::Error> {
    let row: Option<HeartbeatRow> = sqlx::query_as(
        "SELECT last_beat_at, floor(extract(epoch FROM now() - last_beat_at))::bigint AS age_seconds,
                interval_seconds, started_at, version, host
         FROM core.worker_heartbeat",
    )
    .fetch_optional(db)
    .await?;
    let last_outage: Option<Outage> = sqlx::query_as(
        "SELECT down_from, down_until FROM core.worker_outages ORDER BY down_until DESC LIMIT 1",
    )
    .fetch_optional(db)
    .await?;
    Ok(match row {
        None => WorkerStatus {
            state: WorkerState::NeverSeen,
            last_beat_at: None,
            age_seconds: None,
            late_after_seconds: None,
            interval_seconds: None,
            started_at: None,
            version: None,
            host: None,
            last_outage,
        },
        Some(r) => {
            let late = late_after(r.interval_seconds);
            WorkerStatus {
                state: if r.age_seconds > late {
                    WorkerState::Down
                } else {
                    WorkerState::Running
                },
                last_beat_at: Some(r.last_beat_at),
                age_seconds: Some(r.age_seconds.max(0)),
                late_after_seconds: Some(late),
                interval_seconds: Some(r.interval_seconds),
                started_at: Some(r.started_at),
                version: Some(r.version),
                host: Some(r.host),
                last_outage,
            }
        }
    })
}

/// The background worker's heartbeat: whether it is running, and its last outage.
#[utoipa::path(get, path = "/admin/worker", tag = "core",
    responses((status = 200, body = WorkerStatus), (status = 403, body = ErrorBody)))]
async fn get_worker(
    State(state): State<AppState>,
    user: CurrentUser,
) -> AppResult<Json<WorkerStatus>> {
    user.require(Permission::UsersAdmin)?;
    Ok(Json(status(&state.db).await?))
}

/// `GET /admin/worker`, for administrators (`users.admin`).
pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new().routes(routes!(get_worker))
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;

    #[test]
    fn late_after_three_passes_and_a_minute() {
        assert_eq!(late_after(30), 150);
        assert_eq!(late_after(5), 75);
        // A nonsense interval still gives a sane threshold.
        assert_eq!(late_after(0), 63);
    }

    #[test]
    fn outage_mail_in_every_language() {
        let o = Outage {
            down_from: Utc.with_ymd_and_hms(2027, 1, 26, 8, 0, 0).unwrap(),
            down_until: Utc.with_ymd_and_hms(2027, 1, 26, 9, 30, 0).unwrap(),
        };
        let mut subjects = std::collections::HashSet::new();
        for lang in crate::LANGUAGES {
            let (subject, body) = outage_mail(lang, &o);
            assert!(subjects.insert(subject), "{lang} reuses a subject");
            assert!(body.contains("2027-01-26 08:00 UTC"), "{lang}: {body}");
            assert!(body.contains("2027-01-26 09:30 UTC"), "{lang}: {body}");
            assert!(body.contains("90"), "{lang}: {body}");
            assert!(
                !body.contains('{'),
                "{lang}: unfilled placeholder in {body}"
            );
        }
        assert_eq!(outage_mail("xx", &o).0, outage_mail("en", &o).0);
    }
}
