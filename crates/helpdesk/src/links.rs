//! Ticket links and bundles (A9): tickets that stay separate but belong together.
//!
//! A *bundle* is a parent with child tickets (one outage, many customers); *related* and
//! *duplicate of* are plain links. Links show in both tickets. A reply, a note or a status change
//! written on the parent can be offered to every child through a mass update that is previewed
//! first. The preview runs the real action in a transaction per child and rolls it back, so it
//! shows exactly what the update would do, including what would be refused.

use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::Json;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection};
use tradocraft_core::{audit, new_id, AppError, AppResult, AppState, CurrentUser, Permission};
use utoipa::ToSchema;
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::tickets::{
    add_note, change_status, load_ticket, notify_change, post_note, queue_reply, NoteInput,
    ReplyInput, STATUSES,
};

type ErrorBody = tradocraft_core::error::ErrorBody;

/// The other end of a link, with what is needed to judge the bundle at a glance.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct LinkedTicket {
    pub link_id: Uuid,
    pub ticket_id: Uuid,
    pub number: String,
    pub subject: String,
    pub status: String,
    pub priority: String,
    pub customer_name: Option<String>,
    pub owner_name: Option<String>,
    /// The ticket was merged into another one and is closed.
    pub merged: bool,
    pub updated_at: DateTime<Utc>,
}

/// All links of one ticket, grouped by how the ticket stands to the other one.
#[derive(Debug, Default, Serialize, ToSchema)]
pub struct TicketLinks {
    /// This ticket is a child of the bundle of this parent.
    pub parent: Option<LinkedTicket>,
    /// Tickets in the bundle of this ticket (it is their parent).
    pub children: Vec<LinkedTicket>,
    pub related: Vec<LinkedTicket>,
    /// This ticket is a duplicate of this one.
    pub duplicate_of: Option<LinkedTicket>,
    /// Tickets that are duplicates of this one.
    pub duplicates: Vec<LinkedTicket>,
}

/// How the other ticket relates to the one the request is made on.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum LinkRelation {
    /// The other ticket becomes a child in the bundle of this one.
    Child,
    /// The other ticket becomes the parent of the bundle this one joins.
    Parent,
    Related,
    /// This ticket is a duplicate of the other one.
    DuplicateOf,
    /// The other ticket is a duplicate of this one.
    DuplicatedBy,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct LinkInput {
    pub target_id: Uuid,
    pub relation: LinkRelation,
}

#[derive(FromRow)]
struct LinkRow {
    link_id: Uuid,
    kind: String,
    /// The ticket asked about is the source of the link.
    outgoing: bool,
    ticket_id: Uuid,
    number: String,
    subject: String,
    status: String,
    priority: String,
    customer_name: Option<String>,
    owner_name: Option<String>,
    merged: bool,
    updated_at: DateTime<Utc>,
}

impl LinkRow {
    fn ticket(&self) -> LinkedTicket {
        LinkedTicket {
            link_id: self.link_id,
            ticket_id: self.ticket_id,
            number: self.number.clone(),
            subject: self.subject.clone(),
            status: self.status.clone(),
            priority: self.priority.clone(),
            customer_name: self.customer_name.clone(),
            owner_name: self.owner_name.clone(),
            merged: self.merged,
            updated_at: self.updated_at,
        }
    }
}

pub async fn load_links(
    conn: &mut PgConnection,
    company_id: Uuid,
    id: Uuid,
) -> AppResult<TicketLinks> {
    let rows: Vec<LinkRow> = sqlx::query_as(
        "SELECT l.id AS link_id, l.kind, (l.source_id = $1) AS outgoing,
                t.id AS ticket_id, t.number, t.subject, t.status::text AS status,
                t.priority::text AS priority, c.name AS customer_name, u.display_name AS owner_name,
                t.merged_into_id IS NOT NULL AS merged, t.updated_at
         FROM helpdesk.ticket_links l
         JOIN helpdesk.tickets t ON t.id = CASE WHEN l.source_id = $1 THEN l.target_id ELSE l.source_id END
         LEFT JOIN crm.customers c ON c.id = t.customer_id
         LEFT JOIN core.users u ON u.id = t.owner_user_id
         WHERE (l.source_id = $1 OR l.target_id = $1) AND l.company_id = $2
         ORDER BY t.number",
    )
    .bind(id)
    .bind(company_id)
    .fetch_all(conn)
    .await?;
    let mut links = TicketLinks::default();
    for r in &rows {
        match (r.kind.as_str(), r.outgoing) {
            ("bundle", true) => links.children.push(r.ticket()),
            ("bundle", false) => links.parent = Some(r.ticket()),
            ("duplicate", true) => links.duplicate_of = Some(r.ticket()),
            ("duplicate", false) => links.duplicates.push(r.ticket()),
            _ => links.related.push(r.ticket()),
        }
    }
    Ok(links)
}

/// `(kind, source, target)` of the link a relation asks for, seen from ticket `id`.
fn orient(relation: LinkRelation, id: Uuid, other: Uuid) -> (&'static str, Uuid, Uuid) {
    match relation {
        LinkRelation::Child => ("bundle", id, other),
        LinkRelation::Parent => ("bundle", other, id),
        LinkRelation::Related => ("related", id.min(other), id.max(other)),
        LinkRelation::DuplicateOf => ("duplicate", id, other),
        LinkRelation::DuplicatedBy => ("duplicate", other, id),
    }
}

async fn count(conn: &mut PgConnection, sql: &str, id: Uuid) -> AppResult<i64> {
    Ok(sqlx::query_scalar(sql).bind(id).fetch_one(conn).await?)
}

async fn lock_both(conn: &mut PgConnection, company_id: Uuid, a: Uuid, b: Uuid) -> AppResult<()> {
    let found: Vec<Uuid> = sqlx::query_scalar(
        "SELECT id FROM helpdesk.tickets WHERE id = ANY($1) AND company_id = $2 ORDER BY id FOR UPDATE",
    )
    .bind([a, b])
    .bind(company_id)
    .fetch_all(conn)
    .await?;
    if found.len() != 2 {
        return Err(AppError::NotFound("ticket"));
    }
    Ok(())
}

/// Links this ticket to another one. Both tickets get a note and an audit event.
#[utoipa::path(post, path = "/tickets/{id}/links", tag = "helpdesk", params(("id" = Uuid, Path)), request_body = LinkInput,
    responses((status = 201, body = TicketLinks), (status = 403, body = ErrorBody), (status = 404, body = ErrorBody),
              (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn add_link(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<LinkInput>,
) -> AppResult<(StatusCode, Json<TicketLinks>)> {
    user.require(Permission::HelpdeskWrite)?;
    let other = input.target_id;
    if other == id {
        return Err(AppError::Validation(
            "a ticket cannot be linked to itself".into(),
        ));
    }
    let mut tx = state.db.begin().await?;
    lock_both(&mut tx, user.company_id, id, other).await?;
    let this = load_ticket(&mut tx, user.company_id, id).await?;
    let that = load_ticket(&mut tx, user.company_id, other).await?;
    if this.merged_into_id.is_some() || that.merged_into_id.is_some() {
        return Err(AppError::Conflict(
            "a ticket that was merged into another one cannot be linked".into(),
        ));
    }
    let (kind, source, target) = orient(input.relation, id, other);
    let number_of = |t: Uuid| {
        if t == id {
            this.number.clone()
        } else {
            that.number.clone()
        }
    };
    let already: bool = sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM helpdesk.ticket_links
                        WHERE LEAST(source_id, target_id) = LEAST($1, $2)
                          AND GREATEST(source_id, target_id) = GREATEST($1, $2))",
    )
    .bind(id)
    .bind(other)
    .fetch_one(&mut *tx)
    .await?;
    if already {
        return Err(AppError::Conflict(
            "these tickets are already linked; remove that link first".into(),
        ));
    }
    match kind {
        "bundle" => {
            let (parent, child) = (source, target);
            if count(
                &mut tx,
                "SELECT count(*) FROM helpdesk.ticket_links WHERE kind = 'bundle' AND target_id = $1",
                child,
            )
            .await?
                > 0
            {
                return Err(AppError::Conflict(format!(
                    "{} already belongs to a bundle",
                    number_of(child)
                )));
            }
            if count(
                &mut tx,
                "SELECT count(*) FROM helpdesk.ticket_links WHERE kind = 'bundle' AND source_id = $1",
                child,
            )
            .await?
                > 0
            {
                return Err(AppError::Conflict(format!(
                    "{} is the parent of a bundle and cannot join another one",
                    number_of(child)
                )));
            }
            if count(
                &mut tx,
                "SELECT count(*) FROM helpdesk.ticket_links WHERE kind = 'bundle' AND target_id = $1",
                parent,
            )
            .await?
                > 0
            {
                return Err(AppError::Conflict(format!(
                    "{} belongs to a bundle and cannot be the parent of another one",
                    number_of(parent)
                )));
            }
        }
        "duplicate" => {
            let (duplicate, original) = (source, target);
            if count(
                &mut tx,
                "SELECT count(*) FROM helpdesk.ticket_links WHERE kind = 'duplicate' AND source_id = $1",
                duplicate,
            )
            .await?
                > 0
            {
                return Err(AppError::Conflict(format!(
                    "{} is already marked as a duplicate",
                    number_of(duplicate)
                )));
            }
            if count(
                &mut tx,
                "SELECT count(*) FROM helpdesk.ticket_links WHERE kind = 'duplicate' AND source_id = $1",
                original,
            )
            .await?
                > 0
            {
                return Err(AppError::Conflict(format!(
                    "{} is itself a duplicate and cannot be the original",
                    number_of(original)
                )));
            }
        }
        _ => {}
    }
    let link_id = new_id();
    sqlx::query(
        "INSERT INTO helpdesk.ticket_links (id, company_id, kind, source_id, target_id, created_by)
         VALUES ($1, $2, $3, $4, $5, $6)",
    )
    .bind(link_id)
    .bind(user.company_id)
    .bind(kind)
    .bind(source)
    .bind(target)
    .bind(user.user_id)
    .execute(&mut *tx)
    .await?;
    let (note_this, note_that) = link_notes(input.relation, &this.number, &that.number);
    add_note(&mut tx, &user, id, &note_this).await?;
    add_note(&mut tx, &user, other, &note_that).await?;
    for (ticket, partner) in [(id, &that.number), (other, &this.number)] {
        audit::record(
            &mut tx,
            &user,
            "ticket",
            ticket,
            "linked",
            serde_json::json!({ "kind": kind, "other": partner, "link_id": link_id }),
        )
        .await?;
    }
    let links = load_links(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    notify_change(&state, &user, id, "links", None).await;
    notify_change(&state, &user, other, "links", None).await;
    Ok((StatusCode::CREATED, Json(links)))
}

/// The internal notes written on this ticket and on the other one when a link is made.
fn link_notes(relation: LinkRelation, this: &str, that: &str) -> (String, String) {
    match relation {
        LinkRelation::Child => (
            format!("Ticket {that} was added to the bundle of this ticket."),
            format!("This ticket joined the bundle of ticket {this}."),
        ),
        LinkRelation::Parent => (
            format!("This ticket joined the bundle of ticket {that}."),
            format!("Ticket {this} was added to the bundle of this ticket."),
        ),
        LinkRelation::Related => (
            format!("Linked as related to ticket {that}."),
            format!("Linked as related to ticket {this}."),
        ),
        LinkRelation::DuplicateOf => (
            format!("Marked as a duplicate of ticket {that}."),
            format!("Ticket {this} was marked as a duplicate of this ticket."),
        ),
        LinkRelation::DuplicatedBy => (
            format!("Ticket {that} was marked as a duplicate of this ticket."),
            format!("Marked as a duplicate of ticket {this}."),
        ),
    }
}

/// Removes a link. Both tickets get a note and an audit event.
#[utoipa::path(delete, path = "/tickets/{id}/links/{link_id}", tag = "helpdesk",
    params(("id" = Uuid, Path), ("link_id" = Uuid, Path)),
    responses((status = 200, body = TicketLinks), (status = 403, body = ErrorBody), (status = 404, body = ErrorBody)))]
async fn remove_link(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((id, link_id)): Path<(Uuid, Uuid)>,
) -> AppResult<Json<TicketLinks>> {
    user.require(Permission::HelpdeskWrite)?;
    let mut tx = state.db.begin().await?;
    let found: Option<(Uuid, Uuid, String)> = sqlx::query_as(
        "SELECT source_id, target_id, kind FROM helpdesk.ticket_links
         WHERE id = $1 AND company_id = $2 AND (source_id = $3 OR target_id = $3)",
    )
    .bind(link_id)
    .bind(user.company_id)
    .bind(id)
    .fetch_optional(&mut *tx)
    .await?;
    let (source, target, kind) = found.ok_or(AppError::NotFound("link"))?;
    let other = if source == id { target } else { source };
    lock_both(&mut tx, user.company_id, id, other).await?;
    sqlx::query("DELETE FROM helpdesk.ticket_links WHERE id = $1")
        .bind(link_id)
        .execute(&mut *tx)
        .await?;
    let this = load_ticket(&mut tx, user.company_id, id).await?;
    let that = load_ticket(&mut tx, user.company_id, other).await?;
    add_note(
        &mut tx,
        &user,
        id,
        &format!("Link with ticket {} was removed.", that.number),
    )
    .await?;
    add_note(
        &mut tx,
        &user,
        other,
        &format!("Link with ticket {} was removed.", this.number),
    )
    .await?;
    for (ticket, partner) in [(id, &that.number), (other, &this.number)] {
        audit::record(
            &mut tx,
            &user,
            "ticket",
            ticket,
            "unlinked",
            serde_json::json!({ "kind": kind, "other": partner, "link_id": link_id }),
        )
        .await?;
    }
    let links = load_links(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    notify_change(&state, &user, id, "links", None).await;
    notify_change(&state, &user, other, "links", None).await;
    Ok(Json(links))
}

/// The links of a ticket, each with the state of the other ticket.
#[utoipa::path(get, path = "/tickets/{id}/links", tag = "helpdesk", params(("id" = Uuid, Path)),
    responses((status = 200, body = TicketLinks), (status = 404, body = ErrorBody)))]
async fn list_links(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<TicketLinks>> {
    user.require(Permission::HelpdeskRead)?;
    let mut conn = state.db.acquire().await?;
    load_ticket(&mut conn, user.company_id, id).await?;
    Ok(Json(load_links(&mut conn, user.company_id, id).await?))
}

// ---------------------------------------------------------------------------------------------
// Bundle mass update
// ---------------------------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize, Serialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum MassAction {
    /// An e-mail to each child's customer, as a reply on that ticket.
    Reply,
    /// An internal note on each child.
    Note,
    /// A status change on each child.
    Status,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct MassUpdateInput {
    pub action: MassAction,
    /// The message (reply or note).
    pub body: Option<String>,
    /// The new status (`status`); for a reply, the status after sending (default pending_customer).
    pub status: Option<String>,
    /// Subject of the e-mail (`reply`); default "Re: <subject of the child>".
    pub subject: Option<String>,
    /// Only these children; default all children of the bundle.
    pub child_ids: Option<Vec<Uuid>>,
    /// Run everything and roll it back, so that the result shows what would happen.
    #[serde(default)]
    pub dry_run: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum MassOutcome {
    /// Done (a real update).
    Applied,
    /// Would be done (a dry run).
    WouldApply,
    /// Left out on purpose; `reason` says why.
    Skipped,
    /// Refused; `reason` says why, and nothing was changed on this ticket.
    Failed,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct MassUpdateItem {
    pub ticket_id: Uuid,
    pub number: String,
    pub subject: String,
    pub outcome: MassOutcome,
    pub reason: Option<String>,
    /// Where a reply goes.
    pub recipient: Option<String>,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct MassUpdateResult {
    pub dry_run: bool,
    pub items: Vec<MassUpdateItem>,
    /// How many tickets were (or would be) updated.
    pub updated: i64,
}

#[derive(FromRow)]
struct Child {
    id: Uuid,
    number: String,
    subject: String,
    status: String,
    merged: bool,
}

/// Applies one action to every child of the bundle (or the chosen ones), each in a transaction of
/// its own, so a child that refuses (a closed gate, no recipient) does not stop the others. With
/// `dry_run` every transaction is rolled back: the result is a faithful preview.
#[utoipa::path(post, path = "/tickets/{id}/bundle/update", tag = "helpdesk", params(("id" = Uuid, Path)), request_body = MassUpdateInput,
    responses((status = 200, body = MassUpdateResult), (status = 403, body = ErrorBody), (status = 404, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn bundle_update(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<MassUpdateInput>,
) -> AppResult<Json<MassUpdateResult>> {
    user.require(Permission::HelpdeskWrite)?;
    let body = input.body.as_deref().unwrap_or("").trim().to_string();
    match input.action {
        MassAction::Reply => {
            user.require(Permission::HelpdeskReply)?;
            if body.is_empty() {
                return Err(AppError::Validation("the message is empty".into()));
            }
        }
        MassAction::Note if body.is_empty() => {
            return Err(AppError::Validation("the note is empty".into()));
        }
        MassAction::Status if input.status.is_none() => {
            return Err(AppError::Validation("choose a status".into()));
        }
        _ => {}
    }
    if let Some(s) = &input.status {
        if !STATUSES.contains(&s.as_str()) {
            return Err(AppError::Validation(format!(
                "status must be one of {}",
                STATUSES.join(", ")
            )));
        }
    }
    let mut conn = state.db.acquire().await?;
    let parent = load_ticket(&mut conn, user.company_id, id).await?;
    let mut children: Vec<Child> = sqlx::query_as(
        "SELECT t.id, t.number, t.subject, t.status::text AS status,
                t.merged_into_id IS NOT NULL AS merged
         FROM helpdesk.ticket_links l JOIN helpdesk.tickets t ON t.id = l.target_id
         WHERE l.kind = 'bundle' AND l.source_id = $1 AND l.company_id = $2
         ORDER BY t.number",
    )
    .bind(id)
    .bind(user.company_id)
    .fetch_all(&mut *conn)
    .await?;
    drop(conn);
    if children.is_empty() {
        return Err(AppError::Validation(
            "this ticket has no tickets in its bundle".into(),
        ));
    }
    if let Some(chosen) = &input.child_ids {
        if chosen.iter().any(|c| !children.iter().any(|k| k.id == *c)) {
            return Err(AppError::Validation(
                "a chosen ticket is not in the bundle of this ticket".into(),
            ));
        }
        children.retain(|c| chosen.contains(&c.id));
    }

    let mut items = Vec::with_capacity(children.len());
    for child in &children {
        let mut item = MassUpdateItem {
            ticket_id: child.id,
            number: child.number.clone(),
            subject: child.subject.clone(),
            outcome: MassOutcome::Skipped,
            reason: None,
            recipient: None,
        };
        if child.merged {
            item.reason = Some("this ticket was merged into another one".into());
            items.push(item);
            continue;
        }
        if input.action == MassAction::Status && input.status.as_deref() == Some(&child.status) {
            item.reason = Some("already in this status".into());
            items.push(item);
            continue;
        }
        let mut tx = state.db.begin().await?;
        match apply_to_child(&mut tx, &user, child.id, &input, &body).await {
            Ok(recipient) => {
                item.recipient = recipient;
                if input.dry_run {
                    tx.rollback().await?;
                    item.outcome = MassOutcome::WouldApply;
                } else {
                    audit::record(
                        &mut tx,
                        &user,
                        "ticket",
                        child.id,
                        "bundle_update",
                        serde_json::json!({ "parent": parent.number, "action": input.action }),
                    )
                    .await?;
                    tx.commit().await?;
                    item.outcome = MassOutcome::Applied;
                    notify_change(&state, &user, child.id, "note", None).await;
                }
            }
            Err(AppError::Internal(e)) => return Err(AppError::Internal(e)),
            Err(e) => {
                tx.rollback().await?;
                item.outcome = MassOutcome::Failed;
                item.reason = Some(e.to_string());
            }
        }
        items.push(item);
    }
    let updated = items
        .iter()
        .filter(|i| matches!(i.outcome, MassOutcome::Applied | MassOutcome::WouldApply))
        .count() as i64;
    if !input.dry_run && updated > 0 {
        let mut tx = state.db.begin().await?;
        add_note(
            &mut tx,
            &user,
            id,
            &format!(
                "Bundle update ({}) applied to {updated} of {} ticket(s).",
                match input.action {
                    MassAction::Reply => "reply",
                    MassAction::Note => "note",
                    MassAction::Status => "status",
                },
                items.len()
            ),
        )
        .await?;
        audit::record(
            &mut tx,
            &user,
            "ticket",
            id,
            "bundle_update",
            serde_json::json!({ "action": input.action, "updated": updated, "of": items.len() }),
        )
        .await?;
        tx.commit().await?;
        notify_change(&state, &user, id, "note", None).await;
    }
    Ok(Json(MassUpdateResult {
        dry_run: input.dry_run,
        items,
        updated,
    }))
}

/// The action on one child, in the caller's transaction. Returns the recipient of a reply.
async fn apply_to_child(
    tx: &mut PgConnection,
    user: &CurrentUser,
    child: Uuid,
    input: &MassUpdateInput,
    body: &str,
) -> AppResult<Option<String>> {
    match input.action {
        MassAction::Reply => {
            let article = queue_reply(
                tx,
                user,
                child,
                &ReplyInput {
                    to: vec![],
                    cc: vec![],
                    subject: input.subject.clone(),
                    body: body.to_string(),
                    attachment_ids: vec![],
                    library_pdfs: vec![],
                    status: input.status.clone(),
                },
            )
            .await?;
            Ok(
                sqlx::query_scalar("SELECT to_addresses[1] FROM helpdesk.articles WHERE id = $1")
                    .bind(article)
                    .fetch_one(&mut *tx)
                    .await?,
            )
        }
        MassAction::Note => {
            post_note(
                tx,
                user,
                child,
                &NoteInput {
                    body: body.to_string(),
                    attachment_ids: vec![],
                    status: input.status.clone(),
                },
            )
            .await?;
            Ok(None)
        }
        MassAction::Status => {
            change_status(tx, user, child, input.status.as_deref().unwrap_or("open")).await?;
            Ok(None)
        }
    }
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(list_links, add_link))
        .routes(routes!(remove_link))
        .routes(routes!(bundle_update))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn relations_point_the_link_the_right_way() {
        let (a, b) = (Uuid::from_u128(1), Uuid::from_u128(2));
        assert_eq!(orient(LinkRelation::Child, a, b), ("bundle", a, b));
        assert_eq!(orient(LinkRelation::Parent, a, b), ("bundle", b, a));
        assert_eq!(orient(LinkRelation::DuplicateOf, a, b), ("duplicate", a, b));
        assert_eq!(
            orient(LinkRelation::DuplicatedBy, a, b),
            ("duplicate", b, a)
        );
        // Related is stored once, smaller id first, whichever ticket asks.
        assert_eq!(orient(LinkRelation::Related, a, b), ("related", a, b));
        assert_eq!(orient(LinkRelation::Related, b, a), ("related", a, b));
    }

    #[test]
    fn notes_name_the_other_ticket_on_both_sides() {
        let (here, there) = link_notes(LinkRelation::DuplicateOf, "T1", "T2");
        assert!(here.contains("duplicate of ticket T2"), "{here}");
        assert!(
            there.contains("T1") && there.contains("duplicate"),
            "{there}"
        );
    }
}
