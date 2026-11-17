//! Teams (queues) and the helpdesk settings of a company. A ticket has at most one team and one
//! owner; the team is the queue it waits in, the owner the person working on it.

use axum::extract::{Path, State};
use axum::Json;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection};
use tradocraft_core::{audit, new_id, AppError, AppResult, AppState, CurrentUser, Permission};
use utoipa::ToSchema;
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::tickets::{load_detail, TicketDetail};

type ErrorBody = tradocraft_core::error::ErrorBody;

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct TeamMember {
    pub user_id: Uuid,
    pub display_name: String,
    pub is_lead: bool,
}

#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct Team {
    pub id: Uuid,
    pub name: String,
    pub active: bool,
    pub require_checklist_done: bool,
    pub members: Vec<TeamMember>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct MemberInput {
    pub user_id: Uuid,
    #[serde(default)]
    pub is_lead: bool,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct TeamInput {
    pub name: String,
    #[serde(default = "yes")]
    pub active: bool,
    #[serde(default)]
    pub require_checklist_done: bool,
    /// The complete member list: members not listed are removed.
    #[serde(default)]
    pub members: Vec<MemberInput>,
}

fn yes() -> bool {
    true
}

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct HelpdeskSettings {
    /// New tickets from e-mail, the portal and the phone start in this team.
    pub default_team_id: Option<Uuid>,
    /// Send a satisfaction survey when a ticket is closed.
    pub csat_enabled: bool,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct SettingsInput {
    pub default_team_id: Option<Uuid>,
    pub csat_enabled: bool,
}

/// Where a ticket goes: both fields replace the current values (empty clears).
#[derive(Debug, Deserialize, ToSchema)]
pub struct AssignmentInput {
    pub team_id: Option<Uuid>,
    pub owner_user_id: Option<Uuid>,
}

#[derive(FromRow)]
struct TeamRow {
    id: Uuid,
    name: String,
    active: bool,
    require_checklist_done: bool,
    created_at: DateTime<Utc>,
}

async fn load_teams(
    conn: &mut PgConnection,
    company_id: Uuid,
    only: Option<Uuid>,
) -> AppResult<Vec<Team>> {
    let rows: Vec<TeamRow> = sqlx::query_as(
        "SELECT id, name, active, require_checklist_done, created_at FROM helpdesk.teams
         WHERE company_id = $1 AND ($2::uuid IS NULL OR id = $2) ORDER BY lower(name)",
    )
    .bind(company_id)
    .bind(only)
    .fetch_all(&mut *conn)
    .await?;
    let mut teams = Vec::new();
    for r in rows {
        let members = sqlx::query_as(
            "SELECT m.user_id, u.display_name, m.is_lead FROM helpdesk.team_members m
             JOIN core.users u ON u.id = m.user_id
             WHERE m.team_id = $1 ORDER BY m.is_lead DESC, lower(u.display_name)",
        )
        .bind(r.id)
        .fetch_all(&mut *conn)
        .await?;
        teams.push(Team {
            id: r.id,
            name: r.name,
            active: r.active,
            require_checklist_done: r.require_checklist_done,
            members,
            created_at: r.created_at,
        });
    }
    Ok(teams)
}

async fn check_company_user(
    conn: &mut PgConnection,
    company_id: Uuid,
    user_id: Uuid,
) -> AppResult<()> {
    let ok: bool = sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM core.user_companies WHERE user_id = $1 AND company_id = $2)",
    )
    .bind(user_id)
    .bind(company_id)
    .fetch_one(conn)
    .await?;
    if ok {
        Ok(())
    } else {
        Err(AppError::Validation(
            "the user is not a member of this company".into(),
        ))
    }
}

#[utoipa::path(get, path = "/helpdesk/teams", tag = "helpdesk", responses((status = 200, body = Vec<Team>)))]
async fn list_teams(
    State(state): State<AppState>,
    user: CurrentUser,
) -> AppResult<Json<Vec<Team>>> {
    user.require(Permission::HelpdeskRead)?;
    let mut conn = state.db.acquire().await?;
    Ok(Json(load_teams(&mut conn, user.company_id, None).await?))
}

async fn save_members(
    conn: &mut PgConnection,
    company_id: Uuid,
    team_id: Uuid,
    members: &[MemberInput],
) -> AppResult<()> {
    sqlx::query("DELETE FROM helpdesk.team_members WHERE team_id = $1")
        .bind(team_id)
        .execute(&mut *conn)
        .await?;
    for m in members {
        check_company_user(conn, company_id, m.user_id).await?;
        sqlx::query(
            "INSERT INTO helpdesk.team_members (team_id, user_id, is_lead) VALUES ($1, $2, $3)
             ON CONFLICT (team_id, user_id) DO UPDATE SET is_lead = EXCLUDED.is_lead",
        )
        .bind(team_id)
        .bind(m.user_id)
        .bind(m.is_lead)
        .execute(&mut *conn)
        .await?;
    }
    Ok(())
}

#[utoipa::path(post, path = "/helpdesk/teams", tag = "helpdesk", request_body = TeamInput,
    responses((status = 201, body = Team), (status = 403, body = ErrorBody), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn create_team(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<TeamInput>,
) -> AppResult<(axum::http::StatusCode, Json<Team>)> {
    user.require(Permission::HelpdeskAdmin)?;
    if input.name.trim().is_empty() {
        return Err(AppError::Validation("a team needs a name".into()));
    }
    let mut tx = state.db.begin().await?;
    let id = new_id();
    sqlx::query(
        "INSERT INTO helpdesk.teams (id, company_id, name, active, require_checklist_done) VALUES ($1, $2, $3, $4, $5)",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(input.name.trim())
    .bind(input.active)
    .bind(input.require_checklist_done)
    .execute(&mut *tx)
    .await?;
    save_members(&mut tx, user.company_id, id, &input.members).await?;
    audit::record(
        &mut tx,
        &user,
        "helpdesk_team",
        id,
        "created",
        serde_json::json!({
            "name": input.name.trim(),
            "require_checklist_done": input.require_checklist_done,
        }),
    )
    .await?;
    let team = load_teams(&mut tx, user.company_id, Some(id))
        .await?
        .pop()
        .ok_or(AppError::NotFound("team"))?;
    tx.commit().await?;
    Ok((axum::http::StatusCode::CREATED, Json(team)))
}

#[utoipa::path(put, path = "/helpdesk/teams/{id}", tag = "helpdesk", params(("id" = Uuid, Path)), request_body = TeamInput,
    responses((status = 200, body = Team), (status = 403, body = ErrorBody), (status = 404, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn update_team(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<TeamInput>,
) -> AppResult<Json<Team>> {
    user.require(Permission::HelpdeskAdmin)?;
    if input.name.trim().is_empty() {
        return Err(AppError::Validation("a team needs a name".into()));
    }
    let mut tx = state.db.begin().await?;
    let updated = sqlx::query(
        "UPDATE helpdesk.teams SET name = $3, active = $4, require_checklist_done = $5 WHERE id = $1 AND company_id = $2",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(input.name.trim())
    .bind(input.active)
    .bind(input.require_checklist_done)
    .execute(&mut *tx)
    .await?;
    if updated.rows_affected() == 0 {
        return Err(AppError::NotFound("team"));
    }
    save_members(&mut tx, user.company_id, id, &input.members).await?;
    if !input.active {
        // A retired team cannot stay the default.
        sqlx::query(
            "UPDATE helpdesk.settings SET default_team_id = NULL, updated_at = now()
             WHERE company_id = $1 AND default_team_id = $2",
        )
        .bind(user.company_id)
        .bind(id)
        .execute(&mut *tx)
        .await?;
    }
    audit::record(
        &mut tx,
        &user,
        "helpdesk_team",
        id,
        "updated",
        serde_json::json!({
            "name": input.name.trim(),
            "active": input.active,
            "require_checklist_done": input.require_checklist_done,
        }),
    )
    .await?;
    let team = load_teams(&mut tx, user.company_id, Some(id))
        .await?
        .pop()
        .ok_or(AppError::NotFound("team"))?;
    tx.commit().await?;
    Ok(Json(team))
}

pub async fn load_settings(
    conn: &mut PgConnection,
    company_id: Uuid,
) -> Result<HelpdeskSettings, sqlx::Error> {
    Ok(sqlx::query_as(
        "SELECT default_team_id, csat_enabled FROM helpdesk.settings WHERE company_id = $1",
    )
    .bind(company_id)
    .fetch_optional(conn)
    .await?
    .unwrap_or(HelpdeskSettings {
        default_team_id: None,
        csat_enabled: false,
    }))
}

#[utoipa::path(get, path = "/helpdesk/settings", tag = "helpdesk", responses((status = 200, body = HelpdeskSettings)))]
async fn get_settings(
    State(state): State<AppState>,
    user: CurrentUser,
) -> AppResult<Json<HelpdeskSettings>> {
    user.require(Permission::HelpdeskRead)?;
    let mut conn = state.db.acquire().await?;
    Ok(Json(load_settings(&mut conn, user.company_id).await?))
}

#[utoipa::path(put, path = "/helpdesk/settings", tag = "helpdesk", request_body = SettingsInput,
    responses((status = 200, body = HelpdeskSettings), (status = 403, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn put_settings(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<SettingsInput>,
) -> AppResult<Json<HelpdeskSettings>> {
    user.require(Permission::HelpdeskAdmin)?;
    let mut tx = state.db.begin().await?;
    if let Some(team) = input.default_team_id {
        let ok: bool = sqlx::query_scalar(
            "SELECT EXISTS (SELECT 1 FROM helpdesk.teams WHERE id = $1 AND company_id = $2 AND active)",
        )
        .bind(team)
        .bind(user.company_id)
        .fetch_one(&mut *tx)
        .await?;
        if !ok {
            return Err(AppError::Validation(
                "the default team does not exist or is not active".into(),
            ));
        }
    }
    sqlx::query(
        "INSERT INTO helpdesk.settings (company_id, default_team_id, csat_enabled) VALUES ($1, $2, $3)
         ON CONFLICT (company_id) DO UPDATE SET default_team_id = $2, csat_enabled = $3, updated_at = now()",
    )
    .bind(user.company_id)
    .bind(input.default_team_id)
    .bind(input.csat_enabled)
    .execute(&mut *tx)
    .await?;
    audit::record(
        &mut tx,
        &user,
        "helpdesk_settings",
        user.company_id,
        "settings_updated",
        serde_json::json!({ "default_team_id": input.default_team_id, "csat_enabled": input.csat_enabled }),
    )
    .await?;
    let s = load_settings(&mut tx, user.company_id).await?;
    tx.commit().await?;
    Ok(Json(s))
}

/// Puts a new ticket in the company's default team, if one is set.
pub async fn assign_default_team(
    conn: &mut PgConnection,
    company_id: Uuid,
    ticket_id: Uuid,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        "UPDATE helpdesk.tickets SET team_id = s.default_team_id
         FROM helpdesk.settings s JOIN helpdesk.teams tm ON tm.id = s.default_team_id AND tm.active
         WHERE helpdesk.tickets.id = $2 AND helpdesk.tickets.team_id IS NULL AND s.company_id = $1",
    )
    .bind(company_id)
    .bind(ticket_id)
    .execute(conn)
    .await?;
    Ok(())
}

/// Assigns a ticket to a team and/or an owner.
#[utoipa::path(put, path = "/tickets/{id}/assignment", tag = "helpdesk", params(("id" = Uuid, Path)), request_body = AssignmentInput,
    responses((status = 200, body = TicketDetail), (status = 404, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn assign(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<AssignmentInput>,
) -> AppResult<Json<TicketDetail>> {
    user.require(Permission::HelpdeskWrite)?;
    let mut tx = state.db.begin().await?;
    let old = crate::tickets::load_ticket(&mut tx, user.company_id, id).await?;
    if let Some(team) = input.team_id {
        let ok: bool = sqlx::query_scalar(
            "SELECT EXISTS (SELECT 1 FROM helpdesk.teams WHERE id = $1 AND company_id = $2 AND active)",
        )
        .bind(team)
        .bind(user.company_id)
        .fetch_one(&mut *tx)
        .await?;
        if !ok {
            return Err(AppError::Validation(
                "the team does not exist or is not active".into(),
            ));
        }
    }
    if let Some(owner) = input.owner_user_id {
        check_company_user(&mut tx, user.company_id, owner).await?;
    }
    sqlx::query(
        "UPDATE helpdesk.tickets SET team_id = $2, owner_user_id = $3, updated_at = now() WHERE id = $1",
    )
    .bind(id)
    .bind(input.team_id)
    .bind(input.owner_user_id)
    .execute(&mut *tx)
    .await?;
    if old.team_id != input.team_id {
        // The team's calendar sets the due times.
        crate::sla::sync(&mut tx, id).await?;
        crate::collab::record_event(
            &mut tx,
            user.company_id,
            id,
            "assigned",
            Some(user.user_id),
            crate::collab::EventData {
                to_value: Some("team".into()),
                target_team_id: input.team_id,
                ..Default::default()
            },
        )
        .await?;
    }
    crate::collab::owner_changed(&mut tx, &user, id, old.owner_user_id, input.owner_user_id)
        .await?;
    audit::record(
        &mut tx,
        &user,
        "ticket",
        id,
        "assigned",
        serde_json::json!({ "team_id": input.team_id, "owner_user_id": input.owner_user_id }),
    )
    .await?;
    crate::automation::run(&mut tx, user.company_id, id, "updated").await?;
    let d = load_detail(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok(Json(d))
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(list_teams, create_team))
        .routes(routes!(update_team))
        .routes(routes!(get_settings, put_settings))
        .routes(routes!(assign))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn team_input_deserializes_require_checklist_done() {
        let json_default = r#"{"name": "Support"}"#;
        let input_default: TeamInput =
            serde_json::from_str(json_default).expect("deserialize default");
        assert_eq!(input_default.name, "Support");
        assert!(input_default.active);
        assert!(!input_default.require_checklist_done);

        let json_true = r#"{"name": "Hardware", "require_checklist_done": true}"#;
        let input_true: TeamInput = serde_json::from_str(json_true).expect("deserialize true");
        assert_eq!(input_true.name, "Hardware");
        assert!(input_true.require_checklist_done);

        let json_false = r#"{"name": "Field", "require_checklist_done": false}"#;
        let input_false: TeamInput = serde_json::from_str(json_false).expect("deserialize false");
        assert_eq!(input_false.name, "Field");
        assert!(!input_false.require_checklist_done);
    }
}
