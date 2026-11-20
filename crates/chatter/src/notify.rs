//! The mail to the assignee of an activity (ADR 0086): plain system mail in the user's language,
//! at most one per assignee and record per ten minutes, never to the person who scheduled it.

use chrono::NaiveDate;
use sqlx::PgConnection;
use tradocraft_core::{mail, CurrentUser};
use uuid::Uuid;

use crate::RecordKind;

struct Texts {
    subject: &'static str,
    line: &'static str,
    record: &'static str,
    due: &'static str,
    kinds: [&'static str; 4], // todo, call, email, meeting
}

fn texts(lang: &str) -> Texts {
    match lang {
        "nl" => Texts {
            subject: "Nieuwe activiteit bij {label}: {summary}",
            line: "{who} heeft een activiteit voor je gepland.",
            record: "Dossier",
            due: "Vervalt",
            kinds: ["Taak", "Bellen", "E-mail", "Vergadering"],
        },
        "fr" => Texts {
            subject: "Nouvelle activité pour {label} : {summary}",
            line: "{who} a planifié une activité pour vous.",
            record: "Dossier",
            due: "Échéance",
            kinds: ["Tâche", "Appel", "E-mail", "Réunion"],
        },
        "de" => Texts {
            subject: "Neue Aktivität zu {label}: {summary}",
            line: "{who} hat eine Aktivität für Sie geplant.",
            record: "Vorgang",
            due: "Fällig",
            kinds: ["Aufgabe", "Anruf", "E-Mail", "Besprechung"],
        },
        "es" => Texts {
            subject: "Nueva actividad en {label}: {summary}",
            line: "{who} ha programado una actividad para usted.",
            record: "Registro",
            due: "Vence",
            kinds: ["Tarea", "Llamada", "Correo electrónico", "Reunión"],
        },
        _ => Texts {
            subject: "New activity on {label}: {summary}",
            line: "{who} scheduled an activity for you.",
            record: "Record",
            due: "Due",
            kinds: ["To do", "Call", "E-mail", "Meeting"],
        },
    }
}

/// Queues the mail when `assignee` is somebody else and has not been mailed about this record in
/// the last ten minutes. `activity_kind` is `todo` | `call` | `email` | `meeting`.
#[allow(clippy::too_many_arguments)]
pub(crate) async fn assigned(
    conn: &mut PgConnection,
    user: &CurrentUser,
    kind: RecordKind,
    record_id: Uuid,
    assignee: Uuid,
    activity_kind: &str,
    summary: &str,
    due: NaiveDate,
) -> Result<(), sqlx::Error> {
    if assignee == user.user_id {
        return Ok(());
    }
    let claimed: Option<(String, String)> = sqlx::query_as(
        "UPDATE chatter.followers f SET last_notified_at = now()
         FROM core.users u, core.companies c
         WHERE f.company_id = $1 AND f.record_kind = $2 AND f.record_id = $3 AND f.user_id = $4
           AND u.id = f.user_id AND u.active AND c.id = f.company_id
           AND (f.last_notified_at IS NULL OR f.last_notified_at < now() - interval '10 minutes')
         RETURNING u.email, coalesce(u.language, c.default_language)::text",
    )
    .bind(user.company_id)
    .bind(kind.as_str())
    .bind(record_id)
    .bind(assignee)
    .fetch_optional(&mut *conn)
    .await?;
    let Some((email, lang)) = claimed else {
        return Ok(());
    };
    let label: String = kind
        .label(conn, user.company_id, record_id)
        .await
        .ok()
        .flatten()
        .unwrap_or_default();
    let t = texts(&lang);
    let kind_name = match activity_kind {
        "call" => t.kinds[1],
        "email" => t.kinds[2],
        "meeting" => t.kinds[3],
        _ => t.kinds[0],
    };
    let subject = t
        .subject
        .replace("{label}", &label)
        .replace("{summary}", summary);
    let body = format!(
        "{}\n\n{kind_name}: {summary}\n{}: {label}\n{}: {}\n",
        t.line.replace("{who}", &user.display_name),
        t.record,
        t.due,
        due.format("%d/%m/%Y"),
    );
    mail::enqueue(conn, user.company_id, &email, &subject, &body).await
}
