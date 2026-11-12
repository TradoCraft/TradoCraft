use axum::extract::State;
use axum::Json;
use serde::Serialize;
use sqlx::{FromRow, PgExecutor};
use utoipa::ToSchema;
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::modules::Module;
use crate::{AppResult, AppState, CurrentUser};

/// A legal entity (own VAT number, own numbering, own stock and books).
#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct Company {
    pub id: Uuid,
    pub name: String,
    pub vat_number: Option<String>,
    pub street: String,
    pub postal_code: String,
    pub city: String,
    pub country_code: String,
    pub currency: String,
    pub email: Option<String>,
    pub phone: Option<String>,
    pub iban: Option<String>,
    pub default_language: String,
}

pub async fn get_company<'e>(db: impl PgExecutor<'e>, id: Uuid) -> Result<Company, sqlx::Error> {
    sqlx::query_as(
        "SELECT id, name, vat_number, street, postal_code, city, country_code::text AS country_code,
                currency::text AS currency, email, phone, iban,
                default_language::text AS default_language
         FROM core.companies WHERE id = $1",
    )
    .bind(id)
    .fetch_one(db)
    .await
}

#[derive(Debug, Serialize, FromRow, ToSchema)]
pub struct Membership {
    pub company_id: Uuid,
    pub company_name: String,
    pub roles: Vec<String>,
    pub is_default: bool,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct MeModule {
    pub code: String,
    pub enabled: bool,
}

/// The authenticated user, the active company and all companies they can switch to.
#[derive(Debug, Serialize, ToSchema)]
pub struct Me {
    pub user_id: Uuid,
    pub email: String,
    pub display_name: String,
    pub company: Company,
    pub roles: Vec<String>,
    /// Permissions after roles and disabled modules are applied.
    pub permissions: Vec<String>,
    /// Every module with whether it is on for this user in the active company.
    pub modules: Vec<MeModule>,
    pub memberships: Vec<Membership>,
}

#[utoipa::path(get, path = "/me", tag = "core",
    responses((status = 200, body = Me), (status = 401, body = crate::error::ErrorBody)))]
async fn me(State(state): State<AppState>, user: CurrentUser) -> AppResult<Json<Me>> {
    let company = get_company(&state.db, user.company_id).await?;
    let memberships = sqlx::query_as(
        "SELECT uc.company_id, c.name AS company_name, uc.roles, uc.is_default
         FROM core.user_companies uc JOIN core.companies c ON c.id = uc.company_id
         WHERE uc.user_id = $1 AND uc.active ORDER BY c.name",
    )
    .bind(user.user_id)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(Me {
        user_id: user.user_id,
        email: user.email.clone(),
        display_name: user.display_name.clone(),
        company,
        permissions: user
            .permissions()
            .iter()
            .map(|p| p.as_str().to_string())
            .collect(),
        modules: Module::ALL
            .into_iter()
            .map(|m| MeModule {
                code: m.code().to_string(),
                enabled: user.module_enabled(m),
            })
            .collect(),
        roles: user.roles,
        memberships,
    }))
}

/// A colleague in the active company (for assigning tickets, owners, ...).
#[derive(Debug, Serialize, FromRow, ToSchema)]
pub struct CompanyUser {
    pub id: Uuid,
    pub display_name: String,
    pub email: String,
    pub roles: Vec<String>,
}

#[utoipa::path(get, path = "/users", tag = "core", responses((status = 200, body = Vec<CompanyUser>)))]
async fn list_users(
    State(state): State<AppState>,
    user: CurrentUser,
) -> AppResult<Json<Vec<CompanyUser>>> {
    Ok(Json(
        sqlx::query_as(
            "SELECT u.id, u.display_name, u.email, uc.roles FROM core.users u
             JOIN core.user_companies uc ON uc.user_id = u.id
             WHERE uc.company_id = $1 AND u.active AND uc.active ORDER BY u.display_name",
        )
        .bind(user.company_id)
        .fetch_all(&state.db)
        .await?,
    ))
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(me))
        .routes(routes!(list_users))
        .merge(crate::admin::router())
        .merge(crate::worker::router())
}
