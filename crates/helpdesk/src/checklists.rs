//! Ticket checklists and reusable checklist templates.
//! Templates can be scoped to a team and/or ticket category, and applied manually
//! or by automation rules (idempotently per `(ticket_id, template_id)`).

use std::collections::HashMap;

use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::Json;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection};
use tradocraft_core::{audit, new_id, AppError, AppResult, AppState, CurrentUser, Permission};
use utoipa::{IntoParams, ToSchema};
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::tickets::CATEGORIES;

type ErrorBody = tradocraft_core::error::ErrorBody;

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct ChecklistTemplateItem {
    pub id: Uuid,
    pub position: i32,
    pub description: String,
}

#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct ChecklistTemplate {
    pub id: Uuid,
    pub name: String,
    pub team_id: Option<Uuid>,
    pub team_name: Option<String>,
    pub category: Option<String>,
    pub active: bool,
    pub items: Vec<ChecklistTemplateItem>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct ChecklistTemplateItemInput {
    pub description: String,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct ChecklistTemplateInput {
    pub name: String,
    pub team_id: Option<Uuid>,
    pub category: Option<String>,
    #[serde(default = "default_true")]
    pub active: bool,
    #[serde(default)]
    pub items: Vec<ChecklistTemplateItemInput>,
}

fn default_true() -> bool {
    true
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct ListTemplatesParams {
    pub team_id: Option<Uuid>,
    pub category: Option<String>,
    pub active: Option<bool>,
}

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct ChecklistItem {
    pub id: Uuid,
    pub ticket_id: Uuid,
    pub template_id: Option<Uuid>,
    pub position: i32,
    pub description: String,
    pub done: bool,
    pub done_by: Option<Uuid>,
    pub done_by_name: Option<String>,
    pub done_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct AddChecklistItemInput {
    pub description: String,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct UpdateChecklistItemInput {
    pub done: Option<bool>,
    pub description: Option<String>,
    pub position: Option<i32>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct ApplyTemplateInput {
    pub template_id: Uuid,
}

#[derive(Debug, PartialEq, Eq)]
pub struct ValidatedTemplateInput {
    pub name: String,
    pub team_id: Option<Uuid>,
    pub category: Option<String>,
    pub active: bool,
    pub items: Vec<String>,
}

/// Validates and trims a `ChecklistTemplateInput`.
pub fn validate_template_input(
    input: &ChecklistTemplateInput,
) -> AppResult<ValidatedTemplateInput> {
    let name = input.name.trim().to_string();
    if name.is_empty() {
        return Err(AppError::Validation("template name is required".into()));
    }

    let category = match &input.category {
        Some(raw) => {
            let trimmed = raw.trim();
            if !CATEGORIES.contains(&trimmed) {
                return Err(AppError::Validation(format!(
                    "category must be one of {}",
                    CATEGORIES.join(", ")
                )));
            }
            Some(trimmed.to_string())
        }
        None => None,
    };

    let mut items = Vec::with_capacity(input.items.len());
    for item in &input.items {
        let desc = item.description.trim();
        if desc.is_empty() {
            return Err(AppError::Validation(
                "checklist item description cannot be empty".into(),
            ));
        }
        items.push(desc.to_string());
    }

    Ok(ValidatedTemplateInput {
        name,
        team_id: input.team_id,
        category,
        active: input.active,
        items,
    })
}

/// Reorders `ids` by moving `target_id` to the 1-based `new_position` (clamped to bounds).
/// Preserves the relative order of all other items.
pub fn reorder_items(ids: &[Uuid], target_id: Uuid, new_position: i32) -> Vec<Uuid> {
    if !ids.contains(&target_id) {
        return ids.to_vec();
    }
    let mut rest: Vec<Uuid> = ids.iter().copied().filter(|id| *id != target_id).collect();
    let idx = (new_position.max(1) as usize - 1).min(rest.len());
    rest.insert(idx, target_id);
    rest
}

#[derive(FromRow)]
struct TemplateRow {
    id: Uuid,
    name: String,
    team_id: Option<Uuid>,
    team_name: Option<String>,
    category: Option<String>,
    active: bool,
    created_at: DateTime<Utc>,
    updated_at: DateTime<Utc>,
}

#[derive(FromRow)]
struct TemplateItemRow {
    id: Uuid,
    template_id: Uuid,
    position: i32,
    description: String,
}

async fn load_template_items(
    conn: &mut PgConnection,
    template_ids: &[Uuid],
) -> AppResult<HashMap<Uuid, Vec<ChecklistTemplateItem>>> {
    if template_ids.is_empty() {
        return Ok(HashMap::new());
    }
    let rows: Vec<TemplateItemRow> = sqlx::query_as(
        "SELECT id, template_id, position, description
         FROM helpdesk.checklist_template_items
         WHERE template_id = ANY($1)
         ORDER BY position ASC",
    )
    .bind(template_ids)
    .fetch_all(conn)
    .await?;

    let mut map: HashMap<Uuid, Vec<ChecklistTemplateItem>> = HashMap::new();
    for r in rows {
        map.entry(r.template_id)
            .or_default()
            .push(ChecklistTemplateItem {
                id: r.id,
                position: r.position,
                description: r.description,
            });
    }
    Ok(map)
}

async fn load_template(
    conn: &mut PgConnection,
    company_id: Uuid,
    id: Uuid,
) -> AppResult<ChecklistTemplate> {
    let row: TemplateRow = sqlx::query_as(
        "SELECT t.id, t.name, t.team_id, tm.name AS team_name, t.category, t.active,
                t.created_at, t.updated_at
         FROM helpdesk.checklist_templates t
         LEFT JOIN helpdesk.teams tm ON tm.id = t.team_id
         WHERE t.id = $1 AND t.company_id = $2",
    )
    .bind(id)
    .bind(company_id)
    .fetch_optional(&mut *conn)
    .await?
    .ok_or(AppError::NotFound("checklist template"))?;

    let mut items_map = load_template_items(conn, &[row.id]).await?;
    Ok(ChecklistTemplate {
        id: row.id,
        name: row.name,
        team_id: row.team_id,
        team_name: row.team_name,
        category: row.category,
        active: row.active,
        items: items_map.remove(&row.id).unwrap_or_default(),
        created_at: row.created_at,
        updated_at: row.updated_at,
    })
}

async fn check_company_team(
    conn: &mut PgConnection,
    company_id: Uuid,
    team_id: Option<Uuid>,
) -> AppResult<()> {
    let Some(tid) = team_id else {
        return Ok(());
    };
    let ok: bool = sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM helpdesk.teams WHERE id = $1 AND company_id = $2)",
    )
    .bind(tid)
    .bind(company_id)
    .fetch_one(conn)
    .await?;
    if ok {
        Ok(())
    } else {
        Err(AppError::Validation(
            "team does not belong to this company".into(),
        ))
    }
}

async fn save_template_items(
    conn: &mut PgConnection,
    template_id: Uuid,
    items: &[String],
) -> AppResult<()> {
    sqlx::query("DELETE FROM helpdesk.checklist_template_items WHERE template_id = $1")
        .bind(template_id)
        .execute(&mut *conn)
        .await?;
    for (idx, desc) in items.iter().enumerate() {
        sqlx::query(
            "INSERT INTO helpdesk.checklist_template_items (id, template_id, position, description)
             VALUES ($1, $2, $3, $4)",
        )
        .bind(new_id())
        .bind(template_id)
        .bind(idx as i32 + 1)
        .bind(desc)
        .execute(&mut *conn)
        .await?;
    }
    Ok(())
}

async fn ensure_ticket(
    conn: &mut PgConnection,
    company_id: Uuid,
    ticket_id: Uuid,
) -> AppResult<()> {
    let ok: bool = sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM helpdesk.tickets WHERE id = $1 AND company_id = $2)",
    )
    .bind(ticket_id)
    .bind(company_id)
    .fetch_one(conn)
    .await?;
    if ok {
        Ok(())
    } else {
        Err(AppError::NotFound("ticket"))
    }
}

/// Serialize checklist writes and close checks on the scoped parent row.
/// Call within a transaction and retain the lock through commit.
pub(crate) async fn lock_ticket(
    conn: &mut PgConnection,
    company_id: Uuid,
    ticket_id: Uuid,
) -> AppResult<()> {
    sqlx::query_scalar::<_, Uuid>(
        "SELECT id FROM helpdesk.tickets WHERE id = $1 AND company_id = $2 FOR UPDATE",
    )
    .bind(ticket_id)
    .bind(company_id)
    .fetch_optional(conn)
    .await?
    .ok_or(AppError::NotFound("ticket"))?;
    Ok(())
}

async fn load_ticket_checklist(
    conn: &mut PgConnection,
    ticket_id: Uuid,
) -> AppResult<Vec<ChecklistItem>> {
    let items: Vec<ChecklistItem> = sqlx::query_as(
        "SELECT i.id, i.ticket_id, i.template_id, i.position, i.description, i.done,
                i.done_by, u.display_name AS done_by_name, i.done_at
         FROM helpdesk.ticket_checklist_items i
         LEFT JOIN core.users u ON u.id = i.done_by
         WHERE i.ticket_id = $1
         ORDER BY i.position ASC",
    )
    .bind(ticket_id)
    .fetch_all(conn)
    .await?;
    Ok(items)
}

async fn load_ticket_checklist_item(
    conn: &mut PgConnection,
    ticket_id: Uuid,
    item_id: Uuid,
) -> AppResult<ChecklistItem> {
    sqlx::query_as(
        "SELECT i.id, i.ticket_id, i.template_id, i.position, i.description, i.done,
                i.done_by, u.display_name AS done_by_name, i.done_at
         FROM helpdesk.ticket_checklist_items i
         LEFT JOIN core.users u ON u.id = i.done_by
         WHERE i.id = $1 AND i.ticket_id = $2",
    )
    .bind(item_id)
    .bind(ticket_id)
    .fetch_optional(conn)
    .await?
    .ok_or(AppError::NotFound("checklist item"))
}

/// Idempotently applies a checklist template to a ticket, appending its items in order.
/// Used both by the manual apply-template endpoint and by helpdesk automation rules.
pub async fn apply_template_to_ticket(
    conn: &mut PgConnection,
    company_id: Uuid,
    ticket_id: Uuid,
    template_id: Uuid,
    require_active: bool,
) -> AppResult<(Vec<ChecklistItem>, bool)> {
    lock_ticket(conn, company_id, ticket_id).await?;
    let active: Option<bool> = sqlx::query_scalar(
        "SELECT active FROM helpdesk.checklist_templates WHERE id = $1 AND company_id = $2 FOR SHARE",
    )
    .bind(template_id)
    .bind(company_id)
    .fetch_optional(&mut *conn)
    .await?;

    let is_active = active.ok_or(AppError::NotFound("checklist template"))?;
    if require_active && !is_active {
        return Err(AppError::Validation(
            "checklist template is not active".into(),
        ));
    }

    let inserted = sqlx::query(
        "INSERT INTO helpdesk.ticket_applied_templates (ticket_id, template_id)
         VALUES ($1, $2)
         ON CONFLICT (ticket_id, template_id) DO NOTHING",
    )
    .bind(ticket_id)
    .bind(template_id)
    .execute(&mut *conn)
    .await?;

    if inserted.rows_affected() > 0 {
        let tpl_items: Vec<String> = sqlx::query_scalar(
            "SELECT description FROM helpdesk.checklist_template_items
             WHERE template_id = $1
             ORDER BY position ASC",
        )
        .bind(template_id)
        .fetch_all(&mut *conn)
        .await?;

        let max_pos: i32 = sqlx::query_scalar(
            "SELECT COALESCE(MAX(position), 0)
             FROM helpdesk.ticket_checklist_items
             WHERE ticket_id = $1",
        )
        .bind(ticket_id)
        .fetch_one(&mut *conn)
        .await?;

        for (idx, desc) in tpl_items.into_iter().enumerate() {
            sqlx::query(
                "INSERT INTO helpdesk.ticket_checklist_items
                    (id, ticket_id, template_id, position, description)
                 VALUES ($1, $2, $3, $4, $5)",
            )
            .bind(new_id())
            .bind(ticket_id)
            .bind(template_id)
            .bind(max_pos + idx as i32 + 1)
            .bind(desc)
            .execute(&mut *conn)
            .await?;
        }
    }

    Ok((
        load_ticket_checklist(conn, ticket_id).await?,
        inserted.rows_affected() > 0,
    ))
}

#[utoipa::path(
    get,
    path = "/helpdesk/checklist-templates",
    tag = "helpdesk",
    params(ListTemplatesParams),
    responses((status = 200, body = Vec<ChecklistTemplate>))
)]
async fn list_templates(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(p): Query<ListTemplatesParams>,
) -> AppResult<Json<Vec<ChecklistTemplate>>> {
    user.require(Permission::HelpdeskRead)?;
    let rows: Vec<TemplateRow> = sqlx::query_as(
        "SELECT t.id, t.name, t.team_id, tm.name AS team_name, t.category, t.active,
                t.created_at, t.updated_at
         FROM helpdesk.checklist_templates t
         LEFT JOIN helpdesk.teams tm ON tm.id = t.team_id
         WHERE t.company_id = $1
           AND ($2::uuid IS NULL OR t.team_id = $2)
           AND ($3::text IS NULL OR t.category = $3)
           AND ($4::boolean IS NULL OR t.active = $4)
         ORDER BY lower(t.name)",
    )
    .bind(user.company_id)
    .bind(p.team_id)
    .bind(
        p.category
            .as_deref()
            .map(str::trim)
            .filter(|c| !c.is_empty()),
    )
    .bind(p.active)
    .fetch_all(&state.db)
    .await?;

    let mut conn = state.db.acquire().await?;
    let ids: Vec<Uuid> = rows.iter().map(|r| r.id).collect();
    let mut items_map = load_template_items(&mut conn, &ids).await?;

    Ok(Json(
        rows.into_iter()
            .map(|r| ChecklistTemplate {
                items: items_map.remove(&r.id).unwrap_or_default(),
                id: r.id,
                name: r.name,
                team_id: r.team_id,
                team_name: r.team_name,
                category: r.category,
                active: r.active,
                created_at: r.created_at,
                updated_at: r.updated_at,
            })
            .collect(),
    ))
}

#[utoipa::path(
    post,
    path = "/helpdesk/checklist-templates",
    tag = "helpdesk",
    request_body = ChecklistTemplateInput,
    responses(
        (status = 201, body = ChecklistTemplate),
        (status = 403, body = ErrorBody),
        (status = 422, body = ErrorBody)
    )
)]
async fn create_template(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<ChecklistTemplateInput>,
) -> AppResult<(StatusCode, Json<ChecklistTemplate>)> {
    user.require(Permission::HelpdeskAdmin)?;
    let validated = validate_template_input(&input)?;
    let mut tx = state.db.begin().await?;
    check_company_team(&mut tx, user.company_id, validated.team_id).await?;

    let id = new_id();
    sqlx::query(
        "INSERT INTO helpdesk.checklist_templates (id, company_id, name, team_id, category, active)
         VALUES ($1, $2, $3, $4, $5, $6)",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(&validated.name)
    .bind(validated.team_id)
    .bind(&validated.category)
    .bind(validated.active)
    .execute(&mut *tx)
    .await?;

    save_template_items(&mut tx, id, &validated.items).await?;
    audit::record(
        &mut tx,
        &user,
        "checklist_template",
        id,
        "created",
        serde_json::json!({ "name": validated.name }),
    )
    .await?;

    let tpl = load_template(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(tpl)))
}

#[utoipa::path(
    put,
    path = "/helpdesk/checklist-templates/{id}",
    tag = "helpdesk",
    params(("id" = Uuid, Path)),
    request_body = ChecklistTemplateInput,
    responses(
        (status = 200, body = ChecklistTemplate),
        (status = 403, body = ErrorBody),
        (status = 404, body = ErrorBody),
        (status = 422, body = ErrorBody)
    )
)]
async fn update_template(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<ChecklistTemplateInput>,
) -> AppResult<Json<ChecklistTemplate>> {
    user.require(Permission::HelpdeskAdmin)?;
    let validated = validate_template_input(&input)?;
    let mut tx = state.db.begin().await?;
    check_company_team(&mut tx, user.company_id, validated.team_id).await?;

    let res = sqlx::query(
        "UPDATE helpdesk.checklist_templates
         SET name = $3, team_id = $4, category = $5, active = $6, updated_at = now()
         WHERE id = $1 AND company_id = $2",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(&validated.name)
    .bind(validated.team_id)
    .bind(&validated.category)
    .bind(validated.active)
    .execute(&mut *tx)
    .await?;

    if res.rows_affected() == 0 {
        return Err(AppError::NotFound("checklist template"));
    }

    save_template_items(&mut tx, id, &validated.items).await?;
    audit::record(
        &mut tx,
        &user,
        "checklist_template",
        id,
        "updated",
        serde_json::json!({ "name": validated.name, "active": validated.active }),
    )
    .await?;

    let tpl = load_template(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok(Json(tpl))
}

#[utoipa::path(
    delete,
    path = "/helpdesk/checklist-templates/{id}",
    tag = "helpdesk",
    params(("id" = Uuid, Path)),
    responses(
        (status = 204),
        (status = 403, body = ErrorBody),
        (status = 404, body = ErrorBody)
    )
)]
async fn delete_template(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<StatusCode> {
    user.require(Permission::HelpdeskAdmin)?;
    let mut tx = state.db.begin().await?;
    let res =
        sqlx::query("DELETE FROM helpdesk.checklist_templates WHERE id = $1 AND company_id = $2")
            .bind(id)
            .bind(user.company_id)
            .execute(&mut *tx)
            .await?;

    if res.rows_affected() == 0 {
        return Err(AppError::NotFound("checklist template"));
    }

    audit::record(
        &mut tx,
        &user,
        "checklist_template",
        id,
        "deleted",
        serde_json::json!({}),
    )
    .await?;
    tx.commit().await?;
    Ok(StatusCode::NO_CONTENT)
}

#[utoipa::path(
    get,
    path = "/helpdesk/tickets/{id}/checklist",
    tag = "helpdesk",
    params(("id" = Uuid, Path)),
    responses(
        (status = 200, body = Vec<ChecklistItem>),
        (status = 404, body = ErrorBody)
    )
)]
async fn list_ticket_checklist(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(ticket_id): Path<Uuid>,
) -> AppResult<Json<Vec<ChecklistItem>>> {
    user.require(Permission::HelpdeskRead)?;
    let mut conn = state.db.acquire().await?;
    ensure_ticket(&mut conn, user.company_id, ticket_id).await?;
    Ok(Json(load_ticket_checklist(&mut conn, ticket_id).await?))
}

#[utoipa::path(
    post,
    path = "/helpdesk/tickets/{id}/checklist",
    tag = "helpdesk",
    params(("id" = Uuid, Path)),
    request_body = AddChecklistItemInput,
    responses(
        (status = 201, body = ChecklistItem),
        (status = 404, body = ErrorBody),
        (status = 422, body = ErrorBody)
    )
)]
async fn add_ticket_checklist_item(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(ticket_id): Path<Uuid>,
    Json(input): Json<AddChecklistItemInput>,
) -> AppResult<(StatusCode, Json<ChecklistItem>)> {
    user.require(Permission::HelpdeskWrite)?;
    let desc = input.description.trim();
    if desc.is_empty() {
        return Err(AppError::Validation(
            "checklist item description cannot be empty".into(),
        ));
    }

    let mut tx = state.db.begin().await?;
    lock_ticket(&mut tx, user.company_id, ticket_id).await?;

    let item_id = new_id();
    sqlx::query(
        "INSERT INTO helpdesk.ticket_checklist_items (id, ticket_id, position, description)
         VALUES (
             $1,
             $2,
             (SELECT COALESCE(MAX(position), 0) + 1 FROM helpdesk.ticket_checklist_items WHERE ticket_id = $2),
             $3
         )",
    )
    .bind(item_id)
    .bind(ticket_id)
    .bind(desc)
    .execute(&mut *tx)
    .await?;

    let item = load_ticket_checklist_item(&mut tx, ticket_id, item_id).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(item)))
}

#[utoipa::path(
    patch,
    path = "/helpdesk/tickets/{id}/checklist/{item_id}",
    tag = "helpdesk",
    params(("id" = Uuid, Path), ("item_id" = Uuid, Path)),
    request_body = UpdateChecklistItemInput,
    responses(
        (status = 200, body = ChecklistItem),
        (status = 404, body = ErrorBody),
        (status = 422, body = ErrorBody)
    )
)]
async fn update_ticket_checklist_item(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((ticket_id, item_id)): Path<(Uuid, Uuid)>,
    Json(input): Json<UpdateChecklistItemInput>,
) -> AppResult<Json<ChecklistItem>> {
    user.require(Permission::HelpdeskWrite)?;

    let trimmed_desc = match &input.description {
        Some(d) => {
            let t = d.trim();
            if t.is_empty() {
                return Err(AppError::Validation(
                    "checklist item description cannot be empty".into(),
                ));
            }
            Some(t.to_string())
        }
        None => None,
    };

    let mut tx = state.db.begin().await?;
    lock_ticket(&mut tx, user.company_id, ticket_id).await?;

    let exists: bool = sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM helpdesk.ticket_checklist_items WHERE id = $1 AND ticket_id = $2)",
    )
    .bind(item_id)
    .bind(ticket_id)
    .fetch_one(&mut *tx)
    .await?;
    if !exists {
        return Err(AppError::NotFound("checklist item"));
    }

    if let Some(desc) = trimmed_desc {
        sqlx::query(
            "UPDATE helpdesk.ticket_checklist_items SET description = $3 WHERE id = $1 AND ticket_id = $2",
        )
        .bind(item_id)
        .bind(ticket_id)
        .bind(desc)
        .execute(&mut *tx)
        .await?;
    }

    if let Some(done) = input.done {
        if done {
            sqlx::query(
                "UPDATE helpdesk.ticket_checklist_items
                 SET done = true, done_by = $3, done_at = now()
                 WHERE id = $1 AND ticket_id = $2 AND NOT done",
            )
            .bind(item_id)
            .bind(ticket_id)
            .bind(user.user_id)
            .execute(&mut *tx)
            .await?;
        } else {
            sqlx::query(
                "UPDATE helpdesk.ticket_checklist_items
                 SET done = false, done_by = NULL, done_at = NULL
                 WHERE id = $1 AND ticket_id = $2",
            )
            .bind(item_id)
            .bind(ticket_id)
            .execute(&mut *tx)
            .await?;
        }
    }

    if let Some(new_pos) = input.position {
        let ids: Vec<Uuid> = sqlx::query_scalar(
            "SELECT id FROM helpdesk.ticket_checklist_items
             WHERE ticket_id = $1
             ORDER BY position ASC",
        )
        .bind(ticket_id)
        .fetch_all(&mut *tx)
        .await?;

        let reordered = reorder_items(&ids, item_id, new_pos);
        // Two-pass update via negative temporary positions so UNIQUE (ticket_id, position) never collides.
        for (idx, &iid) in reordered.iter().enumerate() {
            sqlx::query("UPDATE helpdesk.ticket_checklist_items SET position = $1 WHERE id = $2")
                .bind(-(idx as i32 + 1))
                .bind(iid)
                .execute(&mut *tx)
                .await?;
        }
        for (idx, &iid) in reordered.iter().enumerate() {
            sqlx::query("UPDATE helpdesk.ticket_checklist_items SET position = $1 WHERE id = $2")
                .bind(idx as i32 + 1)
                .bind(iid)
                .execute(&mut *tx)
                .await?;
        }
    }

    let item = load_ticket_checklist_item(&mut tx, ticket_id, item_id).await?;
    tx.commit().await?;
    Ok(Json(item))
}

#[utoipa::path(
    delete,
    path = "/helpdesk/tickets/{id}/checklist/{item_id}",
    tag = "helpdesk",
    params(("id" = Uuid, Path), ("item_id" = Uuid, Path)),
    responses(
        (status = 204),
        (status = 404, body = ErrorBody)
    )
)]
async fn delete_ticket_checklist_item(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((ticket_id, item_id)): Path<(Uuid, Uuid)>,
) -> AppResult<StatusCode> {
    user.require(Permission::HelpdeskWrite)?;
    let mut tx = state.db.begin().await?;
    lock_ticket(&mut tx, user.company_id, ticket_id).await?;

    let res =
        sqlx::query("DELETE FROM helpdesk.ticket_checklist_items WHERE id = $1 AND ticket_id = $2")
            .bind(item_id)
            .bind(ticket_id)
            .execute(&mut *tx)
            .await?;

    if res.rows_affected() == 0 {
        return Err(AppError::NotFound("checklist item"));
    }

    tx.commit().await?;
    Ok(StatusCode::NO_CONTENT)
}

#[utoipa::path(
    post,
    path = "/helpdesk/tickets/{id}/checklist/apply-template",
    tag = "helpdesk",
    params(("id" = Uuid, Path)),
    request_body = ApplyTemplateInput,
    responses(
        (status = 200, body = Vec<ChecklistItem>),
        (status = 404, body = ErrorBody),
        (status = 422, body = ErrorBody)
    )
)]
async fn apply_template(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(ticket_id): Path<Uuid>,
    Json(input): Json<ApplyTemplateInput>,
) -> AppResult<Json<Vec<ChecklistItem>>> {
    user.require(Permission::HelpdeskWrite)?;
    let mut tx = state.db.begin().await?;
    lock_ticket(&mut tx, user.company_id, ticket_id).await?;
    let (items, _) =
        apply_template_to_ticket(&mut tx, user.company_id, ticket_id, input.template_id, true)
            .await?;
    tx.commit().await?;
    Ok(Json(items))
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(list_templates, create_template))
        .routes(routes!(update_template, delete_template))
        .routes(routes!(list_ticket_checklist, add_ticket_checklist_item))
        .routes(routes!(
            update_ticket_checklist_item,
            delete_ticket_checklist_item
        ))
        .routes(routes!(apply_template))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn id(n: u128) -> Uuid {
        Uuid::from_u128(n)
    }

    #[test]
    fn reorder_items_moves_up_down_and_clamps_bounds() {
        let a = id(1);
        let b = id(2);
        let c = id(3);
        let d = id(4);
        let items = vec![a, b, c, d];

        // Move up: c (pos 3) -> pos 1
        assert_eq!(reorder_items(&items, c, 1), vec![c, a, b, d]);

        // Move down: a (pos 1) -> pos 3
        assert_eq!(reorder_items(&items, a, 3), vec![b, c, a, d]);

        // Clamp above length: a -> pos 99
        assert_eq!(reorder_items(&items, a, 99), vec![b, c, d, a]);

        // Clamp below 1: d -> pos 0 and negative
        assert_eq!(reorder_items(&items, d, 0), vec![d, a, b, c]);
        assert_eq!(reorder_items(&items, d, -5), vec![d, a, b, c]);

        // Unknown target leaves order unchanged
        assert_eq!(reorder_items(&items, id(99), 1), items);
    }

    #[test]
    fn validate_template_input_trims_and_rejects_invalid() {
        let valid = ChecklistTemplateInput {
            name: "  Onboarding  ".into(),
            team_id: Some(id(10)),
            category: Some(" service ".into()),
            active: true,
            items: vec![
                ChecklistTemplateItemInput {
                    description: "  Verify serial number  ".into(),
                },
                ChecklistTemplateItemInput {
                    description: "Send confirmation".into(),
                },
            ],
        };
        let out = validate_template_input(&valid).expect("valid input should pass");
        assert_eq!(
            out,
            ValidatedTemplateInput {
                name: "Onboarding".into(),
                team_id: Some(id(10)),
                category: Some("service".into()),
                active: true,
                items: vec!["Verify serial number".into(), "Send confirmation".into(),],
            }
        );

        // Empty / whitespace name
        let empty_name = ChecklistTemplateInput {
            name: "   ".into(),
            team_id: None,
            category: None,
            active: true,
            items: vec![],
        };
        assert!(matches!(
            validate_template_input(&empty_name),
            Err(AppError::Validation(_))
        ));

        // Empty item description
        let empty_item = ChecklistTemplateInput {
            name: "Valid".into(),
            team_id: None,
            category: None,
            active: true,
            items: vec![ChecklistTemplateItemInput {
                description: " \t ".into(),
            }],
        };
        assert!(matches!(
            validate_template_input(&empty_item),
            Err(AppError::Validation(_))
        ));

        // Invalid category
        let bad_cat = ChecklistTemplateInput {
            name: "Valid".into(),
            team_id: None,
            category: Some("nonexistent".into()),
            active: true,
            items: vec![],
        };
        assert!(matches!(
            validate_template_input(&bad_cat),
            Err(AppError::Validation(_))
        ));
    }
}
