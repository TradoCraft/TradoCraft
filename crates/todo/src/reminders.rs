//! The reminder pass of the background worker (ADR 0061, PR 3).
//!
//! One pass claims every open item that is due today or overdue and has not been reminded
//! (`reminded_at IS NULL`), and queues one digest mail per recipient and company in the recipient's
//! language. The recipient is the assignee when the item is handed on, else the owner. Claiming and
//! queuing happen in one transaction, so a crash neither sends twice nor loses a reminder, and an
//! advisory lock plus `FOR UPDATE SKIP LOCKED` let several workers run side by side.
//!
//! Only the outbox is written here. Whether the mail leaves the building is decided where the outbox
//! is emptied (ADR 0048): outside a live environment it is written to files, never sent.

use chrono::NaiveDate;
use sqlx::{FromRow, PgPool};
use std::collections::HashSet;
use tradocraft_core::{mail, modules, AppResult, CurrentUser, Permission};
use uuid::Uuid;

use crate::link::TodoLinkKind;
use crate::routes::{link_readable, readable_job_ids};

#[derive(FromRow)]
struct Due {
    id: Uuid,
    company_id: Uuid,
    recipient_id: Uuid,
    recipient_name: String,
    title: String,
    due_date: NaiveDate,
    today: NaiveDate,
    link_kind: Option<String>,
    link_id: Option<Uuid>,
    link_label: Option<String>,
    email: String,
    language: String,
    roles: Vec<String>,
    user_disabled: Vec<String>,
    company_disabled: Vec<String>,
}

struct Text {
    subject_one: &'static str,
    subject_many: &'static str,
    intro: &'static str,
    due_today: &'static str,
    overdue: &'static str,
    about: &'static str,
    footer: &'static str,
}

/// `{n}` in the subject is the number of items.
fn text(lang: &str) -> Text {
    match lang {
        "de" => Text {
            subject_one: "To-do-Erinnerung: 1 Aufgabe ist fällig",
            subject_many: "To-do-Erinnerung: {n} Aufgaben sind fällig",
            intro: "Diese Aufgaben auf Ihrer To-do-Liste sind heute fällig oder überfällig:",
            due_today: "heute fällig",
            overdue: "überfällig seit",
            about: "betrifft",
            footer: "Sie erhalten diese Erinnerung einmal pro Aufgabe. Zum Abschalten öffnen Sie in der App die To-dos und schalten \"E-Mail-Erinnerungen\" aus.",
        },
        "es" => Text {
            subject_one: "Recordatorio de tareas: 1 tarea vence",
            subject_many: "Recordatorio de tareas: {n} tareas vencen",
            intro: "Estas tareas de su lista vencen hoy o están vencidas:",
            due_today: "vence hoy",
            overdue: "vencida desde",
            about: "sobre",
            footer: "Recibe este recordatorio una vez por tarea. Para desactivarlo, abra las tareas en la aplicación y desactive \"Recordatorios por correo\".",
        },
        "fr" => Text {
            subject_one: "Rappel de tâches : 1 tâche arrive à échéance",
            subject_many: "Rappel de tâches : {n} tâches arrivent à échéance",
            intro: "Ces tâches de votre liste sont à faire aujourd'hui ou en retard :",
            due_today: "échéance aujourd'hui",
            overdue: "en retard depuis le",
            about: "concerne",
            footer: "Vous recevez ce rappel une fois par tâche. Pour le désactiver, ouvrez les tâches dans l'application et désactivez \"Rappels par e-mail\".",
        },
        "nl" => Text {
            subject_one: "Herinnering taken: 1 taak is aan de beurt",
            subject_many: "Herinnering taken: {n} taken zijn aan de beurt",
            intro: "Deze taken op uw lijst zijn vandaag of al eerder verschuldigd:",
            due_today: "vandaag",
            overdue: "te laat sinds",
            about: "over",
            footer: "U krijgt deze herinnering één keer per taak. Zet in de app bij de taken \"E-mailherinneringen\" uit om ze te stoppen.",
        },
        _ => Text {
            subject_one: "To-do reminder: 1 item is due",
            subject_many: "To-do reminder: {n} items are due",
            intro: "These items on your to-do list are due today or overdue:",
            due_today: "due today",
            overdue: "overdue since",
            about: "about",
            footer: "You get this reminder once per item. To switch it off, open To-dos in the app and turn off \"E-mail reminders\".",
        },
    }
}

/// Runs one pass and returns the number of digest mails queued. Safe to call from several workers
/// and repeatedly: an item is claimed once.
pub async fn send_due_reminders(db: &PgPool) -> AppResult<usize> {
    let mut tx = db.begin().await?;
    // One pass at a time across workers: a recipient's items are then claimed by one worker and make
    // one digest. A worker that does not get the lock simply skips this pass.
    let locked: bool =
        sqlx::query_scalar("SELECT pg_try_advisory_xact_lock(hashtext('todo.reminders'))")
            .fetch_one(&mut *tx)
            .await?;
    if !locked {
        return Ok(0);
    }
    // Done items and the sub-items of a done parent are never reminded. A recipient who opted out
    // keeps their items unreminded: they are reminded, in one digest, once reminders are on again.
    let due: Vec<Due> = sqlx::query_as(
        "SELECT i.id, i.company_id, r.id AS recipient_id, r.display_name AS recipient_name,
                i.title, i.due_date, CURRENT_DATE AS today, i.link_kind, i.link_id, i.link_label,
                r.email, coalesce(r.language, c.default_language)::text AS language,
                uc.roles, uc.disabled_modules AS user_disabled,
                c.disabled_modules AS company_disabled
         FROM todo.items i
         JOIN core.companies c ON c.id = i.company_id
         JOIN core.users r ON r.id = coalesce(i.assignee_id, i.owner_id) AND r.active
         JOIN core.user_companies uc
              ON uc.user_id = r.id AND uc.company_id = i.company_id AND uc.active
         LEFT JOIN todo.user_settings s ON s.user_id = r.id AND s.company_id = i.company_id
         LEFT JOIN todo.items p ON p.id = i.parent_id
         WHERE NOT i.done AND i.reminded_at IS NULL AND i.due_date <= CURRENT_DATE
           AND coalesce(s.email_reminders, true)
           AND (p.id IS NULL OR NOT p.done)
         ORDER BY i.company_id, r.id, i.due_date, i.position, i.id
         FOR UPDATE OF i SKIP LOCKED",
    )
    .fetch_all(&mut *tx)
    .await?;

    let mut groups: Vec<Vec<Due>> = Vec::new();
    for d in due {
        match groups.last_mut() {
            Some(g) if g[0].company_id == d.company_id && g[0].recipient_id == d.recipient_id => {
                g.push(d)
            }
            _ => groups.push(vec![d]),
        }
    }

    let mut claimed: Vec<Uuid> = Vec::new();
    let mut mails = 0;
    for group in groups {
        let first = &group[0];
        let user = CurrentUser {
            user_id: first.recipient_id,
            email: first.email.clone(),
            display_name: first.recipient_name.clone(),
            company_id: first.company_id,
            roles: first.roles.clone(),
            disabled_modules: modules::effective_disabled(
                &first.company_disabled,
                &first.user_disabled,
            ),
        };
        // No to-do list for this person (role or module): nothing to remind, nothing to claim.
        if !user.can(Permission::TodoUse) {
            continue;
        }
        let job_ids: Vec<Uuid> = group
            .iter()
            .filter(|d| d.link_kind.as_deref() == Some(TodoLinkKind::Job.as_str()))
            .filter_map(|d| d.link_id)
            .collect();
        let jobs: HashSet<Uuid> = readable_job_ids(&mut tx, &user, &job_ids).await?;
        let t = text(&first.language);
        let mut body = format!("{}\n\n", t.intro);
        for d in &group {
            let when = if d.due_date < d.today {
                format!("{} {}", t.overdue, d.due_date)
            } else {
                format!("{} ({})", t.due_today, d.due_date)
            };
            body.push_str(&format!("- {} ({when})", d.title));
            let kind = d.link_kind.as_deref().and_then(TodoLinkKind::parse);
            if link_readable(&user, kind, d.link_id, &jobs) {
                if let Some(label) = d.link_label.as_deref().filter(|l| !l.is_empty()) {
                    body.push_str(&format!(" - {}: {label}", t.about));
                }
            }
            body.push('\n');
        }
        body.push_str(&format!("\n{}\n", t.footer));
        let n = group.len();
        let subject = if n == 1 {
            t.subject_one.to_string()
        } else {
            t.subject_many.replace("{n}", &n.to_string())
        };
        mail::enqueue(&mut tx, first.company_id, &first.email, &subject, &body).await?;
        claimed.extend(group.iter().map(|d| d.id));
        mails += 1;
    }
    if !claimed.is_empty() {
        sqlx::query("UPDATE todo.items SET reminded_at = now() WHERE id = ANY($1)")
            .bind(&claimed)
            .execute(&mut *tx)
            .await?;
    }
    tx.commit().await?;
    Ok(mails)
}
