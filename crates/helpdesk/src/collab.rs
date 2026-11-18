//! Collaboration on tickets: manual escalation, hand-over, watchers, per-user unread, the activity
//! timeline and soft presence (ADR 0023).
//!
//! **Unread rule.** A ticket is unread for a user when the user is *involved* (owner, member of
//! the ticket's team, or watcher) and there is activity after the user's `last_read_at` (never
//! read = since the beginning) that somebody else did: a message (customer or colleague, note or
//! call) or a timeline event (assignment, status, priority, escalation, tag, merge). Activity by
//! the user themselves never makes a ticket unread for them; uninvolved users never see
//! unread markers.

use std::collections::HashMap;

use axum::extract::{Path, State};
use axum::http::StatusCode;
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

use crate::sla;
use crate::tickets::{load_detail, load_ticket, TicketDetail, PRIORITIES};

type ErrorBody = tradocraft_core::error::ErrorBody;

/// Seconds after which a presence heartbeat no longer counts.
pub const PRESENCE_SECONDS: i64 = 60;

// ---------------------------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct Watcher {
    pub user_id: Uuid,
    pub user_name: String,
    pub created_at: DateTime<Utc>,
}

/// Somebody who opened the ticket, and when they last did.
#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct Reader {
    pub user_id: Uuid,
    pub user_name: String,
    pub last_read_at: DateTime<Utc>,
}

/// One line of the activity timeline: an event or a message, oldest first.
#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct TimelineItem {
    pub id: Uuid,
    /// event | message
    pub source: String,
    /// Events: created | assigned | delegated | escalated | status | priority | merged |
    /// tag_added | tag_removed. Messages: email_in | email_out | note | call_in | call_out | portal_in.
    pub kind: String,
    pub at: DateTime<Utc>,
    /// The colleague (events, notes, replies) or the customer's name (incoming messages).
    pub actor_user_id: Option<Uuid>,
    pub actor_name: Option<String>,
    /// status / priority: the old value; merged: the number of the merged ticket.
    pub from_value: Option<String>,
    /// status / priority: the new value; assigned: `owner` or `team`; tags: the tag;
    /// merged: the target ticket number.
    pub to_value: Option<String>,
    pub previous_user_id: Option<Uuid>,
    pub previous_user_name: Option<String>,
    pub target_user_id: Option<Uuid>,
    pub target_user_name: Option<String>,
    pub target_team_id: Option<Uuid>,
    pub target_team_name: Option<String>,
    /// Events: the internal reason or comment. Messages: the first 300 characters.
    pub comment: String,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct EscalateInput {
    /// Why this ticket needs more attention (required).
    pub reason: String,
    /// Escalate to a person.
    pub to_user_id: Option<Uuid>,
    /// Escalate to a team (its leads, else its members, are told). Not together with `to_user_id`.
    pub to_team_id: Option<Uuid>,
    /// Raise the priority one step (low < normal < high < urgent).
    #[serde(default)]
    pub raise_priority: bool,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct DelegateInput {
    /// The new owner.
    pub to_user_id: Uuid,
    /// Internal comment for the new owner; never sent to the customer.
    pub comment: Option<String>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct WatcherInput {
    pub user_id: Uuid,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct PresenceInput {
    /// viewing | replying
    pub mode: String,
}

/// A colleague who is looking at (or answering) the ticket right now.
#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct PresenceEntry {
    pub user_id: Uuid,
    pub user_name: String,
    /// viewing | replying
    pub mode: String,
    pub seen_at: DateTime<Utc>,
}

// ---------------------------------------------------------------------------------------------
// SQL fragments (alias `t` = helpdesk.tickets, `u` = the placeholder of the viewing user)
// ---------------------------------------------------------------------------------------------

/// True when the user follows the ticket.
pub fn watching_sql(u: &str) -> String {
    format!(
        "EXISTS (SELECT 1 FROM helpdesk.ticket_watchers w WHERE w.ticket_id = t.id AND w.user_id = {u})"
    )
}

/// True when the ticket is unread for the user (see the module documentation).
pub fn unread_sql(u: &str) -> String {
    let last_read = format!(
        "coalesce((SELECT r.last_read_at FROM helpdesk.ticket_reads r WHERE r.ticket_id = t.id AND r.user_id = {u}), '-infinity'::timestamptz)"
    );
    format!(
        "((coalesce(t.owner_user_id = {u}, false) OR {watching}
           OR (t.team_id IS NOT NULL AND EXISTS (SELECT 1 FROM helpdesk.team_members m WHERE m.team_id = t.team_id AND m.user_id = {u})))
          AND (EXISTS (SELECT 1 FROM helpdesk.articles a WHERE a.ticket_id = t.id
                         AND a.created_at > {last_read} AND a.author_user_id IS DISTINCT FROM {u})
               OR EXISTS (SELECT 1 FROM helpdesk.ticket_events e WHERE e.ticket_id = t.id
                         AND e.created_at > {last_read} AND e.actor_user_id IS DISTINCT FROM {u})))",
        watching = watching_sql(u),
    )
}

/// `unread` and `watching` of the given tickets for one user.
pub async fn viewer_flags(
    conn: &mut PgConnection,
    user_id: Uuid,
    ids: &[Uuid],
) -> Result<HashMap<Uuid, (bool, bool)>, sqlx::Error> {
    let rows: Vec<(Uuid, bool, bool)> = sqlx::query_as(&format!(
        "SELECT t.id, {}, {} FROM helpdesk.tickets t WHERE t.id = ANY($1)",
        unread_sql("$2"),
        watching_sql("$2")
    ))
    .bind(ids)
    .bind(user_id)
    .fetch_all(conn)
    .await?;
    Ok(rows.into_iter().map(|(id, u, w)| (id, (u, w))).collect())
}

// ---------------------------------------------------------------------------------------------
// Events and watchers
// ---------------------------------------------------------------------------------------------

#[derive(Default)]
pub struct EventData {
    pub from_value: Option<String>,
    pub to_value: Option<String>,
    pub previous_user_id: Option<Uuid>,
    pub target_user_id: Option<Uuid>,
    pub target_team_id: Option<Uuid>,
    pub comment: String,
}

/// Adds a line to the ticket's activity timeline. `actor` is empty for the system.
pub async fn record_event(
    conn: &mut PgConnection,
    company_id: Uuid,
    ticket_id: Uuid,
    kind: &str,
    actor: Option<Uuid>,
    d: EventData,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        "INSERT INTO helpdesk.ticket_events (id, company_id, ticket_id, kind, actor_user_id, from_value, to_value,
                                             previous_user_id, target_user_id, target_team_id, comment)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)",
    )
    .bind(new_id())
    .bind(company_id)
    .bind(ticket_id)
    .bind(kind)
    .bind(actor)
    .bind(d.from_value)
    .bind(d.to_value)
    .bind(d.previous_user_id)
    .bind(d.target_user_id)
    .bind(d.target_team_id)
    .bind(d.comment)
    .execute(conn)
    .await?;
    Ok(())
}

/// Makes a user follow the ticket (idempotent).
pub async fn add_watcher(
    conn: &mut PgConnection,
    company_id: Uuid,
    ticket_id: Uuid,
    user_id: Uuid,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        "INSERT INTO helpdesk.ticket_watchers (ticket_id, user_id, company_id) VALUES ($1, $2, $3)
         ON CONFLICT DO NOTHING",
    )
    .bind(ticket_id)
    .bind(user_id)
    .bind(company_id)
    .execute(conn)
    .await?;
    Ok(())
}

/// Records an owner change in the timeline, makes the new owner a watcher and tells the watchers.
pub async fn owner_changed(
    conn: &mut PgConnection,
    actor: &CurrentUser,
    ticket_id: Uuid,
    previous: Option<Uuid>,
    new: Option<Uuid>,
) -> AppResult<()> {
    if previous == new {
        return Ok(());
    }
    record_event(
        conn,
        actor.company_id,
        ticket_id,
        "assigned",
        Some(actor.user_id),
        EventData {
            to_value: Some("owner".into()),
            previous_user_id: previous,
            target_user_id: new,
            ..Default::default()
        },
    )
    .await?;
    if let Some(n) = new {
        add_watcher(conn, actor.company_id, ticket_id, n).await?;
    }
    let owner_name: Option<String> = match new {
        Some(n) => {
            sqlx::query_scalar("SELECT display_name FROM core.users WHERE id = $1")
                .bind(n)
                .fetch_optional(&mut *conn)
                .await?
        }
        None => None,
    };
    notify_watchers(
        conn,
        actor.company_id,
        ticket_id,
        Some(actor.user_id),
        &[],
        Change::OwnerChanged(owner_name.unwrap_or_default()),
    )
    .await?;
    Ok(())
}

// ---------------------------------------------------------------------------------------------
// Mail
// ---------------------------------------------------------------------------------------------

#[derive(Debug, FromRow)]
struct Recipient {
    email: String,
    language: String,
}

/// What happened, for the watcher mail.
pub enum Change {
    CustomerReply,
    /// The name of the new owner (empty when the ticket has no owner any more).
    OwnerChanged(String),
}

/// Texts per language. Placeholders: {n} ticket number, {s} subject, {who}, {owner}.
fn text(lang: &str, key: &str) -> &'static str {
    match (lang, key) {
        ("nl", "esc_subject") => "Geëscaleerd: {n} - {s}",
        ("nl", "esc_line") => "{who} heeft ticket {n} geëscaleerd.",
        ("nl", "reason") => "Reden",
        ("nl", "del_subject") => "Overgedragen aan u: {n} - {s}",
        ("nl", "del_line") => "{who} heeft ticket {n} aan u overgedragen.",
        ("nl", "comment") => "Opmerking",
        ("nl", "rep_subject") => "Antwoord van de klant: {n} - {s}",
        ("nl", "rep_line") => "De klant heeft gereageerd op ticket {n}.",
        ("nl", "own_subject") => "Nieuwe eigenaar: {n} - {s}",
        ("nl", "own_line") => "De eigenaar van ticket {n} is gewijzigd: {owner}.",
        ("fr", "esc_subject") => "Escaladé : {n} - {s}",
        ("fr", "esc_line") => "{who} a escaladé le ticket {n}.",
        ("fr", "reason") => "Motif",
        ("fr", "del_subject") => "Transmis à vous : {n} - {s}",
        ("fr", "del_line") => "{who} vous a transmis le ticket {n}.",
        ("fr", "comment") => "Commentaire",
        ("fr", "rep_subject") => "Réponse du client : {n} - {s}",
        ("fr", "rep_line") => "Le client a répondu au ticket {n}.",
        ("fr", "own_subject") => "Nouveau responsable : {n} - {s}",
        ("fr", "own_line") => "Le responsable du ticket {n} a changé : {owner}.",
        ("de", "esc_subject") => "Eskaliert: {n} - {s}",
        ("de", "esc_line") => "{who} hat Ticket {n} eskaliert.",
        ("de", "reason") => "Grund",
        ("de", "del_subject") => "An Sie übergeben: {n} - {s}",
        ("de", "del_line") => "{who} hat Ticket {n} an Sie übergeben.",
        ("de", "comment") => "Kommentar",
        ("de", "rep_subject") => "Antwort des Kunden: {n} - {s}",
        ("de", "rep_line") => "Der Kunde hat auf Ticket {n} geantwortet.",
        ("de", "own_subject") => "Neuer Verantwortlicher: {n} - {s}",
        ("de", "own_line") => "Der Verantwortliche für Ticket {n} hat gewechselt: {owner}.",
        ("es", "esc_subject") => "Escalado: {n} - {s}",
        ("es", "esc_line") => "{who} ha escalado el ticket {n}.",
        ("es", "reason") => "Motivo",
        ("es", "del_subject") => "Transferido a usted: {n} - {s}",
        ("es", "del_line") => "{who} le ha transferido el ticket {n}.",
        ("es", "comment") => "Comentario",
        ("es", "rep_subject") => "Respuesta del cliente: {n} - {s}",
        ("es", "rep_line") => "El cliente ha respondido al ticket {n}.",
        ("es", "own_subject") => "Nuevo responsable: {n} - {s}",
        ("es", "own_line") => "El responsable del ticket {n} ha cambiado: {owner}.",
        (_, "esc_subject") => "Escalated: {n} - {s}",
        (_, "esc_line") => "{who} escalated ticket {n}.",
        (_, "reason") => "Reason",
        (_, "del_subject") => "Handed over to you: {n} - {s}",
        (_, "del_line") => "{who} handed ticket {n} over to you.",
        (_, "comment") => "Comment",
        (_, "rep_subject") => "Customer reply: {n} - {s}",
        (_, "rep_line") => "The customer replied to ticket {n}.",
        (_, "own_subject") => "New owner: {n} - {s}",
        (_, "own_line") => "The owner of ticket {n} changed: {owner}.",
        _ => "",
    }
}

fn fill(template: &str, n: &str, s: &str, who: &str, owner: &str) -> String {
    template
        .replace("{n}", n)
        .replace("{s}", s)
        .replace("{who}", who)
        .replace("{owner}", owner)
}

struct TicketInfo {
    number: String,
    subject: String,
    priority: String,
}

async fn ticket_info(
    conn: &mut PgConnection,
    company_id: Uuid,
    ticket_id: Uuid,
) -> Result<TicketInfo, sqlx::Error> {
    let (number, subject, priority): (String, String, String) = sqlx::query_as(
        "SELECT number, subject, priority FROM helpdesk.tickets WHERE id = $1 AND company_id = $2",
    )
    .bind(ticket_id)
    .bind(company_id)
    .fetch_one(conn)
    .await?;
    Ok(TicketInfo {
        number,
        subject,
        priority,
    })
}

/// Active members of the company among `ids`, with the language to write to them in (their own,
/// else the company's default).
async fn recipients_of(
    conn: &mut PgConnection,
    company_id: Uuid,
    ids: &[Uuid],
) -> Result<Vec<Recipient>, sqlx::Error> {
    sqlx::query_as(
        "SELECT u.email, coalesce(u.language, c.default_language)::text AS language
         FROM core.users u
         JOIN core.user_companies uc ON uc.user_id = u.id AND uc.company_id = $1
         JOIN core.companies c ON c.id = uc.company_id
         WHERE u.id = ANY($2) AND u.active
         ORDER BY u.email",
    )
    .bind(company_id)
    .bind(ids)
    .fetch_all(conn)
    .await
}

/// Mails the watchers about a change, at most once per watcher and ticket per 10 minutes, and
/// never the person who made the change (`actor`) or the users in `exclude`.
pub async fn notify_watchers(
    conn: &mut PgConnection,
    company_id: Uuid,
    ticket_id: Uuid,
    actor: Option<Uuid>,
    exclude: &[Uuid],
    change: Change,
) -> Result<(), sqlx::Error> {
    // The claim and the mail are one transaction, so a watcher is only marked when mailed.
    let claimed: Vec<(String, String)> = sqlx::query_as(
        "UPDATE helpdesk.ticket_watchers w SET last_notified_at = now()
         FROM core.users u, core.companies c
         WHERE w.ticket_id = $1 AND w.company_id = $2 AND u.id = w.user_id AND u.active AND c.id = w.company_id
           AND ($3::uuid IS NULL OR w.user_id <> $3) AND NOT (w.user_id = ANY($4))
           AND (w.last_notified_at IS NULL OR w.last_notified_at < now() - interval '10 minutes')
         RETURNING u.email, coalesce(u.language, c.default_language)::text",
    )
    .bind(ticket_id)
    .bind(company_id)
    .bind(actor)
    .bind(exclude)
    .fetch_all(&mut *conn)
    .await?;
    if claimed.is_empty() {
        return Ok(());
    }
    let info = ticket_info(conn, company_id, ticket_id).await?;
    for (email, lang) in claimed {
        let (subject_key, line_key, owner) = match &change {
            Change::CustomerReply => ("rep_subject", "rep_line", ""),
            Change::OwnerChanged(o) => ("own_subject", "own_line", o.as_str()),
        };
        let subject = fill(
            text(&lang, subject_key),
            &info.number,
            &info.subject,
            "",
            owner,
        );
        let body = format!(
            "{}\n\n{} - {}\n",
            fill(
                text(&lang, line_key),
                &info.number,
                &info.subject,
                "",
                owner
            ),
            info.number,
            info.subject
        );
        mail::enqueue(conn, company_id, &email, &subject, &body).await?;
    }
    Ok(())
}

async fn mail_users(
    conn: &mut PgConnection,
    company_id: Uuid,
    ids: &[Uuid],
    info: &TicketInfo,
    who: &str,
    kind: &str,
    detail: &str,
) -> Result<Vec<String>, sqlx::Error> {
    let (subject_key, line_key, detail_key) = match kind {
        "escalate" => ("esc_subject", "esc_line", "reason"),
        _ => ("del_subject", "del_line", "comment"),
    };
    let mut sent = Vec::new();
    for r in recipients_of(conn, company_id, ids).await? {
        let subject = fill(
            text(&r.language, subject_key),
            &info.number,
            &info.subject,
            who,
            "",
        );
        let mut body = fill(
            text(&r.language, line_key),
            &info.number,
            &info.subject,
            who,
            "",
        );
        body.push_str(&format!(
            "\n\n{} - {}\n[{}]\n",
            info.number, info.subject, info.priority
        ));
        if !detail.is_empty() {
            body.push_str(&format!(
                "\n{}: {}\n",
                text(&r.language, detail_key),
                detail
            ));
        }
        mail::enqueue(conn, company_id, &r.email, &subject, &body).await?;
        sent.push(r.email);
    }
    Ok(sent)
}

// ---------------------------------------------------------------------------------------------
// Checks
// ---------------------------------------------------------------------------------------------

async fn ensure_active_member(
    conn: &mut PgConnection,
    company_id: Uuid,
    user_id: Uuid,
) -> AppResult<()> {
    let ok: bool = sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM core.user_companies uc JOIN core.users u ON u.id = uc.user_id
                        WHERE uc.user_id = $1 AND uc.company_id = $2 AND u.active)",
    )
    .bind(user_id)
    .bind(company_id)
    .fetch_one(conn)
    .await?;
    if ok {
        Ok(())
    } else {
        Err(AppError::Validation(
            "the user is not an active member of this company".into(),
        ))
    }
}

fn next_priority(p: &str) -> Option<&'static str> {
    let i = PRIORITIES.iter().position(|x| *x == p)?;
    PRIORITIES.get(i + 1).copied()
}

// ---------------------------------------------------------------------------------------------
// Escalate and delegate
// ---------------------------------------------------------------------------------------------

/// Escalates a ticket by hand: records who and why, optionally raises the priority one step and
/// tells the target (a person; or the leads of a team; or, without a target, the leads of the
/// ticket's team, else its members, else the administrators). The caller becomes a watcher.
#[utoipa::path(post, path = "/tickets/{id}/escalate", tag = "helpdesk", params(("id" = Uuid, Path)), request_body = EscalateInput,
    responses((status = 200, body = TicketDetail), (status = 403, body = ErrorBody), (status = 404, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn escalate(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<EscalateInput>,
) -> AppResult<Json<TicketDetail>> {
    user.require(Permission::HelpdeskWrite)?;
    let reason = input.reason.trim();
    if reason.is_empty() {
        return Err(AppError::Validation(
            "give a reason for the escalation".into(),
        ));
    }
    if input.to_user_id.is_some() && input.to_team_id.is_some() {
        return Err(AppError::Validation(
            "escalate to a person or to a team, not both".into(),
        ));
    }
    let mut tx = state.db.begin().await?;
    let ticket = load_ticket(&mut tx, user.company_id, id).await?;
    if ticket.closed_at.is_some() {
        return Err(AppError::Validation(
            "a closed ticket cannot be escalated".into(),
        ));
    }
    let mut recipients: Vec<Uuid> = Vec::new();
    if let Some(u) = input.to_user_id {
        ensure_active_member(&mut tx, user.company_id, u).await?;
        recipients.push(u);
    }
    let team = input.to_team_id.or(match input.to_user_id {
        Some(_) => None,
        None => ticket.team_id,
    });
    if let Some(team) = team {
        let ok: bool = sqlx::query_scalar(
            "SELECT EXISTS (SELECT 1 FROM helpdesk.teams WHERE id = $1 AND company_id = $2 AND active)",
        )
        .bind(team)
        .bind(user.company_id)
        .fetch_one(&mut *tx)
        .await?;
        if !ok && input.to_team_id.is_some() {
            return Err(AppError::Validation(
                "the team does not exist or is not active".into(),
            ));
        }
        let mut people: Vec<Uuid> = sqlx::query_scalar(
            "SELECT user_id FROM helpdesk.team_members WHERE team_id = $1 AND is_lead",
        )
        .bind(team)
        .fetch_all(&mut *tx)
        .await?;
        if people.is_empty() {
            people =
                sqlx::query_scalar("SELECT user_id FROM helpdesk.team_members WHERE team_id = $1")
                    .bind(team)
                    .fetch_all(&mut *tx)
                    .await?;
        }
        recipients.extend(people);
    }
    if recipients.is_empty() {
        // No target and no team: the company's administrators hear about it.
        recipients = sqlx::query_scalar(
            "SELECT user_id FROM core.user_companies WHERE company_id = $1 AND 'admin' = ANY(roles)",
        )
        .bind(user.company_id)
        .fetch_all(&mut *tx)
        .await?;
    }
    recipients.sort();
    recipients.dedup();
    recipients.retain(|r| *r != user.user_id);

    sqlx::query(
        "UPDATE helpdesk.tickets SET escalated_at = now(), escalated_by = $2, updated_at = now() WHERE id = $1",
    )
    .bind(id)
    .bind(user.user_id)
    .execute(&mut *tx)
    .await?;
    let raised = if input.raise_priority {
        next_priority(&ticket.priority)
    } else {
        None
    };
    if let Some(new) = raised {
        sqlx::query("UPDATE helpdesk.tickets SET priority = $2 WHERE id = $1")
            .bind(id)
            .bind(new)
            .execute(&mut *tx)
            .await?;
        sla::sync(&mut tx, id).await?;
        record_event(
            &mut tx,
            user.company_id,
            id,
            "priority",
            Some(user.user_id),
            EventData {
                from_value: Some(ticket.priority.clone()),
                to_value: Some(new.into()),
                comment: reason.into(),
                ..Default::default()
            },
        )
        .await?;
    }
    record_event(
        &mut tx,
        user.company_id,
        id,
        "escalated",
        Some(user.user_id),
        EventData {
            from_value: Some(ticket.priority.clone()),
            to_value: Some(raised.unwrap_or(&ticket.priority).into()),
            target_user_id: input.to_user_id,
            target_team_id: input.to_team_id,
            comment: reason.into(),
            ..Default::default()
        },
    )
    .await?;
    add_watcher(&mut tx, user.company_id, id, user.user_id).await?;
    if input.to_user_id.is_some() || input.to_team_id.is_some() {
        for r in &recipients {
            add_watcher(&mut tx, user.company_id, id, *r).await?;
        }
    }
    let mut info = ticket_info(&mut tx, user.company_id, id).await?;
    info.priority = raised.unwrap_or(&ticket.priority).into();
    let notified = mail_users(
        &mut tx,
        user.company_id,
        &recipients,
        &info,
        &user.display_name,
        "escalate",
        reason,
    )
    .await?;
    audit::record(
        &mut tx,
        &user,
        "ticket",
        id,
        "escalated",
        serde_json::json!({ "reason": reason, "to_user_id": input.to_user_id,
                            "to_team_id": input.to_team_id, "priority": info.priority, "notified": notified }),
    )
    .await?;
    let d = load_detail(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    crate::tickets::notify_change(&state, &user, id, "escalated", None).await;
    Ok(Json(d))
}

/// Hands the ticket over to a colleague with an optional internal comment. The previous owner
/// and the caller become watchers; the new owner is told by mail, comment included.
#[utoipa::path(post, path = "/tickets/{id}/delegate", tag = "helpdesk", params(("id" = Uuid, Path)), request_body = DelegateInput,
    responses((status = 200, body = TicketDetail), (status = 403, body = ErrorBody), (status = 404, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn delegate(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<DelegateInput>,
) -> AppResult<Json<TicketDetail>> {
    user.require(Permission::HelpdeskWrite)?;
    let comment = input.comment.as_deref().map(str::trim).unwrap_or("");
    let mut tx = state.db.begin().await?;
    let ticket = load_ticket(&mut tx, user.company_id, id).await?;
    if ticket.closed_at.is_some() {
        return Err(AppError::Validation(
            "a closed ticket cannot be handed over".into(),
        ));
    }
    ensure_active_member(&mut tx, user.company_id, input.to_user_id).await?;
    if ticket.owner_user_id == Some(input.to_user_id) {
        return Err(AppError::Validation(
            "that colleague already owns the ticket".into(),
        ));
    }
    sqlx::query("UPDATE helpdesk.tickets SET owner_user_id = $2, updated_at = now() WHERE id = $1")
        .bind(id)
        .bind(input.to_user_id)
        .execute(&mut *tx)
        .await?;
    record_event(
        &mut tx,
        user.company_id,
        id,
        "delegated",
        Some(user.user_id),
        EventData {
            previous_user_id: ticket.owner_user_id,
            target_user_id: Some(input.to_user_id),
            comment: comment.into(),
            ..Default::default()
        },
    )
    .await?;
    add_watcher(&mut tx, user.company_id, id, user.user_id).await?;
    if let Some(prev) = ticket.owner_user_id {
        add_watcher(&mut tx, user.company_id, id, prev).await?;
    }
    add_watcher(&mut tx, user.company_id, id, input.to_user_id).await?;
    let mut notified = Vec::new();
    if input.to_user_id != user.user_id {
        let info = ticket_info(&mut tx, user.company_id, id).await?;
        notified = mail_users(
            &mut tx,
            user.company_id,
            &[input.to_user_id],
            &info,
            &user.display_name,
            "delegate",
            comment,
        )
        .await?;
    }
    let new_name: String = sqlx::query_scalar("SELECT display_name FROM core.users WHERE id = $1")
        .bind(input.to_user_id)
        .fetch_one(&mut *tx)
        .await?;
    // The new owner has their own mail; the other watchers hear about the change.
    notify_watchers(
        &mut tx,
        user.company_id,
        id,
        Some(user.user_id),
        &[input.to_user_id],
        Change::OwnerChanged(new_name),
    )
    .await?;
    audit::record(
        &mut tx,
        &user,
        "ticket",
        id,
        "delegated",
        serde_json::json!({ "from": ticket.owner_user_id, "to": input.to_user_id,
                            "comment": comment, "notified": notified }),
    )
    .await?;
    let d = load_detail(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    crate::tickets::notify_change(&state, &user, id, "delegated", None).await;
    Ok(Json(d))
}

// ---------------------------------------------------------------------------------------------
// Watchers, read marks, timeline
// ---------------------------------------------------------------------------------------------

pub async fn load_watchers(
    conn: &mut PgConnection,
    ticket_id: Uuid,
) -> Result<Vec<Watcher>, sqlx::Error> {
    sqlx::query_as(
        "SELECT w.user_id, u.display_name AS user_name, w.created_at FROM helpdesk.ticket_watchers w
         JOIN core.users u ON u.id = w.user_id WHERE w.ticket_id = $1 ORDER BY lower(u.display_name)",
    )
    .bind(ticket_id)
    .fetch_all(conn)
    .await
}

pub async fn load_readers(
    conn: &mut PgConnection,
    ticket_id: Uuid,
) -> Result<Vec<Reader>, sqlx::Error> {
    sqlx::query_as(
        "SELECT r.user_id, u.display_name AS user_name, r.last_read_at FROM helpdesk.ticket_reads r
         JOIN core.users u ON u.id = r.user_id WHERE r.ticket_id = $1 ORDER BY r.last_read_at DESC",
    )
    .bind(ticket_id)
    .fetch_all(conn)
    .await
}

/// Follow the ticket yourself.
#[utoipa::path(put, path = "/tickets/{id}/watch", tag = "helpdesk", params(("id" = Uuid, Path)),
    responses((status = 200, body = Vec<Watcher>), (status = 404, body = ErrorBody)))]
async fn watch(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<Vec<Watcher>>> {
    user.require(Permission::HelpdeskRead)?;
    let mut tx = state.db.begin().await?;
    load_ticket(&mut tx, user.company_id, id).await?;
    add_watcher(&mut tx, user.company_id, id, user.user_id).await?;
    let w = load_watchers(&mut tx, id).await?;
    tx.commit().await?;
    Ok(Json(w))
}

/// Stop following the ticket. Replying to it later makes you a watcher again.
#[utoipa::path(delete, path = "/tickets/{id}/watch", tag = "helpdesk", params(("id" = Uuid, Path)),
    responses((status = 200, body = Vec<Watcher>), (status = 404, body = ErrorBody)))]
async fn unwatch(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<Vec<Watcher>>> {
    user.require(Permission::HelpdeskRead)?;
    let mut tx = state.db.begin().await?;
    load_ticket(&mut tx, user.company_id, id).await?;
    sqlx::query("DELETE FROM helpdesk.ticket_watchers WHERE ticket_id = $1 AND user_id = $2 AND company_id = $3")
        .bind(id)
        .bind(user.user_id)
        .bind(user.company_id)
        .execute(&mut *tx)
        .await?;
    let w = load_watchers(&mut tx, id).await?;
    tx.commit().await?;
    Ok(Json(w))
}

/// Adds a colleague as a watcher.
#[utoipa::path(post, path = "/tickets/{id}/watchers", tag = "helpdesk", operation_id = "add_watcher", params(("id" = Uuid, Path)), request_body = WatcherInput,
    responses((status = 200, body = Vec<Watcher>), (status = 403, body = ErrorBody), (status = 404, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn add_watcher_handler(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<WatcherInput>,
) -> AppResult<Json<Vec<Watcher>>> {
    user.require(Permission::HelpdeskWrite)?;
    let mut tx = state.db.begin().await?;
    load_ticket(&mut tx, user.company_id, id).await?;
    ensure_active_member(&mut tx, user.company_id, input.user_id).await?;
    add_watcher(&mut tx, user.company_id, id, input.user_id).await?;
    let w = load_watchers(&mut tx, id).await?;
    tx.commit().await?;
    Ok(Json(w))
}

/// Marks the ticket as read by the caller (call it when the ticket was opened and shown).
#[utoipa::path(post, path = "/tickets/{id}/read", tag = "helpdesk", params(("id" = Uuid, Path)),
    responses((status = 204), (status = 404, body = ErrorBody)))]
async fn mark_read(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<StatusCode> {
    user.require(Permission::HelpdeskRead)?;
    let mut tx = state.db.begin().await?;
    load_ticket(&mut tx, user.company_id, id).await?;
    sqlx::query(
        "INSERT INTO helpdesk.ticket_reads (ticket_id, user_id, company_id, last_read_at) VALUES ($1, $2, $3, now())
         ON CONFLICT (ticket_id, user_id) DO UPDATE SET last_read_at = now()",
    )
    .bind(id)
    .bind(user.user_id)
    .bind(user.company_id)
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(StatusCode::NO_CONTENT)
}

/// The activity timeline: events and messages (customer and colleagues, internal notes
/// included), oldest first. Internal: never shown to customers.
#[utoipa::path(get, path = "/tickets/{id}/events", tag = "helpdesk", params(("id" = Uuid, Path)),
    responses((status = 200, body = Vec<TimelineItem>), (status = 404, body = ErrorBody)))]
async fn timeline(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<Vec<TimelineItem>>> {
    user.require(Permission::HelpdeskRead)?;
    let mut conn = state.db.acquire().await?;
    load_ticket(&mut conn, user.company_id, id).await?;
    let items = sqlx::query_as(
        "SELECT e.id, 'event' AS source, e.kind, e.created_at AS at, e.actor_user_id, au.display_name AS actor_name,
                e.from_value, e.to_value, e.previous_user_id, pu.display_name AS previous_user_name,
                e.target_user_id, tu.display_name AS target_user_name,
                e.target_team_id, tm.name AS target_team_name, e.comment
         FROM helpdesk.ticket_events e
         LEFT JOIN core.users au ON au.id = e.actor_user_id
         LEFT JOIN core.users pu ON pu.id = e.previous_user_id
         LEFT JOIN core.users tu ON tu.id = e.target_user_id
         LEFT JOIN helpdesk.teams tm ON tm.id = e.target_team_id
         WHERE e.ticket_id = $1 AND e.company_id = $2
         UNION ALL
         SELECT a.id, 'message', a.kind, a.created_at, a.author_user_id,
                coalesce(u.display_name, nullif(a.from_name, '')),
                NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, left(a.body, 300)
         FROM helpdesk.articles a LEFT JOIN core.users u ON u.id = a.author_user_id
         WHERE a.ticket_id = $1
         ORDER BY at, id",
    )
    .bind(id)
    .bind(user.company_id)
    .fetch_all(&mut *conn)
    .await?;
    Ok(Json(items))
}

// ---------------------------------------------------------------------------------------------
// Presence
// ---------------------------------------------------------------------------------------------

async fn others_present(
    conn: &mut PgConnection,
    company_id: Uuid,
    ticket_id: Uuid,
    me: Uuid,
) -> Result<Vec<PresenceEntry>, sqlx::Error> {
    sqlx::query_as(
        "SELECT p.user_id, u.display_name AS user_name, p.mode, p.seen_at FROM helpdesk.ticket_presence p
         JOIN core.users u ON u.id = p.user_id
         WHERE p.ticket_id = $1 AND p.company_id = $2 AND p.user_id <> $3
           AND p.seen_at > now() - make_interval(secs => $4)
         ORDER BY p.seen_at DESC",
    )
    .bind(ticket_id)
    .bind(company_id)
    .bind(me)
    .bind(PRESENCE_SECONDS as f64)
    .fetch_all(conn)
    .await
}

/// Heartbeat: "I am viewing / replying to this ticket". Returns who else is active, so one call
/// per beat is enough. Advisory only: nothing is locked.
#[utoipa::path(post, path = "/tickets/{id}/presence", tag = "helpdesk", params(("id" = Uuid, Path)), request_body = PresenceInput,
    responses((status = 200, body = Vec<PresenceEntry>), (status = 404, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn presence_beat(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<PresenceInput>,
) -> AppResult<Json<Vec<PresenceEntry>>> {
    user.require(Permission::HelpdeskRead)?;
    if !["viewing", "replying"].contains(&input.mode.as_str()) {
        return Err(AppError::Validation(
            "mode must be viewing or replying".into(),
        ));
    }
    let mut conn = state.db.acquire().await?;
    load_ticket(&mut conn, user.company_id, id).await?;
    // Colleagues learn at once (A8) when this person arrives or starts or stops replying; a
    // plain repeat beat changes nothing for them and publishes nothing.
    let previous: Option<String> = sqlx::query_scalar(
        "SELECT mode FROM helpdesk.ticket_presence
         WHERE ticket_id = $1 AND user_id = $2 AND seen_at > now() - make_interval(secs => $3)",
    )
    .bind(id)
    .bind(user.user_id)
    .bind(PRESENCE_SECONDS as f64)
    .fetch_optional(&mut *conn)
    .await?;
    sqlx::query(
        "INSERT INTO helpdesk.ticket_presence (ticket_id, user_id, company_id, mode, seen_at) VALUES ($1, $2, $3, $4, now())
         ON CONFLICT (ticket_id, user_id) DO UPDATE SET mode = $4, seen_at = now()",
    )
    .bind(id)
    .bind(user.user_id)
    .bind(user.company_id)
    .bind(&input.mode)
    .execute(&mut *conn)
    .await?;
    let others = others_present(&mut conn, user.company_id, id, user.user_id).await?;
    // Release conn before notify_change acquires from the pool so one beat never holds two connections.
    drop(conn);
    if previous.as_deref() != Some(input.mode.as_str()) {
        crate::tickets::notify_change(&state, &user, id, "presence", Some(input.mode.clone()))
            .await;
    }
    Ok(Json(others))
}

/// Colleagues (not the caller) active on the ticket during the last 60 seconds.
#[utoipa::path(get, path = "/tickets/{id}/presence", tag = "helpdesk", params(("id" = Uuid, Path)),
    responses((status = 200, body = Vec<PresenceEntry>), (status = 404, body = ErrorBody)))]
async fn presence_list(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<Vec<PresenceEntry>>> {
    user.require(Permission::HelpdeskRead)?;
    let mut conn = state.db.acquire().await?;
    load_ticket(&mut conn, user.company_id, id).await?;
    Ok(Json(
        others_present(&mut conn, user.company_id, id, user.user_id).await?,
    ))
}

/// Removes presence rows that are long expired (called by the worker loop). Rows older than
/// [`PRESENCE_SECONDS`] are already ignored by the queries; this only keeps the table small.
pub async fn cleanup_presence(db: &PgPool) -> Result<u64, sqlx::Error> {
    Ok(sqlx::query(
        "DELETE FROM helpdesk.ticket_presence WHERE seen_at < now() - interval '5 minutes'",
    )
    .execute(db)
    .await?
    .rows_affected())
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(escalate))
        .routes(routes!(delegate))
        .routes(routes!(watch, unwatch))
        .routes(routes!(add_watcher_handler))
        .routes(routes!(mark_read))
        .routes(routes!(timeline))
        .routes(routes!(presence_beat, presence_list))
}
