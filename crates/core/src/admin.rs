//! Administration of the company's users and modules (ADR 0028). Everything here needs
//! `users.admin`, which only the admin role holds.

use axum::body::Bytes;
use axum::extract::{DefaultBodyLimit, Path, State};
use axum::http::{header, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::Json;
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection};
use utoipa::ToSchema;
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::auth::{role_grants, Permission, ROLES};
use crate::logo::{self, MAX_LOGO_BYTES};
use crate::modules::{self, Module};
use crate::{audit, mail, new_id, AppError, AppResult, AppState, CurrentUser};

type ErrorBody = crate::error::ErrorBody;

// ---------------------------------------------------------------------------------------------
// Roles
// ---------------------------------------------------------------------------------------------

/// A role and the permissions it grants (before modules are applied).
#[derive(Debug, Serialize, ToSchema)]
pub struct RoleInfo {
    pub role: String,
    /// Sorted permission codes, e.g. `quotations.write`.
    pub permissions: Vec<String>,
}

/// The roles that exist, with what each grants. Drives the role pickers of the user admin.
#[utoipa::path(get, path = "/roles", tag = "core",
    responses((status = 200, body = Vec<RoleInfo>), (status = 403, body = ErrorBody)))]
async fn list_roles(user: CurrentUser) -> AppResult<Json<Vec<RoleInfo>>> {
    user.require(Permission::UsersAdmin)?;
    Ok(Json(
        ROLES
            .iter()
            .map(|role| {
                let mut permissions: Vec<String> = Permission::ALL
                    .iter()
                    .filter(|p| role_grants(role, **p))
                    .map(|p| p.as_str().to_string())
                    .collect();
                permissions.sort();
                RoleInfo {
                    role: role.to_string(),
                    permissions,
                }
            })
            .collect(),
    ))
}

// ---------------------------------------------------------------------------------------------
// Modules
// ---------------------------------------------------------------------------------------------

/// A module of the catalogue and whether the company has it on.
#[derive(Debug, Serialize, ToSchema)]
pub struct ModuleInfo {
    pub code: String,
    /// Modules that must stay on for this one.
    pub requires: Vec<String>,
    /// The permissions this module owns.
    pub permissions: Vec<String>,
    pub enabled: bool,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct ModulesInput {
    /// The modules to switch off for the whole company; all others are on.
    pub disabled_modules: Vec<String>,
}

fn catalogue(disabled: &[String]) -> Vec<ModuleInfo> {
    Module::ALL
        .into_iter()
        .map(|m| ModuleInfo {
            code: m.code().to_string(),
            requires: modules::codes(m.requires()),
            permissions: m
                .permissions()
                .iter()
                .map(|p| p.as_str().to_string())
                .collect(),
            enabled: !disabled.iter().any(|d| d == m.code()),
        })
        .collect()
}

async fn company_disabled(conn: &mut PgConnection, company_id: Uuid) -> AppResult<Vec<String>> {
    Ok(
        sqlx::query_scalar("SELECT disabled_modules FROM core.companies WHERE id = $1")
            .bind(company_id)
            .fetch_one(conn)
            .await?,
    )
}

/// The module catalogue with the company's switches.
#[utoipa::path(get, path = "/admin/modules", tag = "core",
    responses((status = 200, body = Vec<ModuleInfo>), (status = 403, body = ErrorBody)))]
async fn get_modules(
    State(state): State<AppState>,
    user: CurrentUser,
) -> AppResult<Json<Vec<ModuleInfo>>> {
    user.require(Permission::UsersAdmin)?;
    let mut conn = state.db.acquire().await?;
    let disabled = company_disabled(&mut conn, user.company_id).await?;
    Ok(Json(catalogue(&disabled)))
}

/// Switches modules off (or on again) for the whole company. A module cannot stay on when one
/// it requires is switched off.
#[utoipa::path(put, path = "/admin/modules", tag = "core", request_body = ModulesInput,
    responses((status = 200, body = Vec<ModuleInfo>), (status = 403, body = ErrorBody),
              (status = 422, body = ErrorBody)))]
async fn set_modules(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<ModulesInput>,
) -> AppResult<Json<Vec<ModuleInfo>>> {
    user.require(Permission::UsersAdmin)?;
    let disabled = modules::validate_company_disabled(&input.disabled_modules)
        .map_err(AppError::Validation)?;
    let disabled = modules::codes(&disabled);
    let mut tx = state.db.begin().await?;
    sqlx::query("UPDATE core.companies SET disabled_modules = $2 WHERE id = $1")
        .bind(user.company_id)
        .bind(&disabled)
        .execute(&mut *tx)
        .await?;
    audit::record(
        &mut tx,
        &user,
        "company",
        user.company_id,
        "set_modules",
        serde_json::json!({ "disabled_modules": disabled }),
    )
    .await?;
    tx.commit().await?;
    Ok(Json(catalogue(&disabled)))
}

// ---------------------------------------------------------------------------------------------
// Logo
// ---------------------------------------------------------------------------------------------

/// The stored company logo (without the image itself).
#[derive(Debug, Serialize, ToSchema)]
pub struct CompanyLogoInfo {
    /// `image/png`, `image/jpeg` or `image/svg+xml`.
    pub content_type: String,
    pub size_bytes: i64,
    pub updated_at: chrono::DateTime<chrono::Utc>,
}

/// The company logo image. 404 when none was uploaded.
#[utoipa::path(get, path = "/admin/company/logo", tag = "core",
    responses((status = 200, content_type = "application/octet-stream", body = String),
              (status = 403, body = ErrorBody), (status = 404, body = ErrorBody)))]
async fn get_logo(State(state): State<AppState>, user: CurrentUser) -> AppResult<Response> {
    user.require(Permission::UsersAdmin)?;
    let mut conn = state.db.acquire().await?;
    let found = logo::load(&mut conn, user.company_id)
        .await?
        .ok_or(AppError::NotFound("company logo"))?;
    Ok((
        [
            (header::CONTENT_TYPE, found.content_type),
            (header::CACHE_CONTROL, "private, no-cache".to_string()),
            (header::X_CONTENT_TYPE_OPTIONS, "nosniff".to_string()),
            // An SVG opened directly may not run or load anything.
            (
                header::CONTENT_SECURITY_POLICY,
                "default-src 'none'; style-src 'unsafe-inline'; sandbox".to_string(),
            ),
        ],
        found.bytes,
    )
        .into_response())
}

/// Sets or replaces the company logo: the request body is the image file (PNG, JPEG or SVG, at
/// most 512 KB). The type is taken from the file's content, not from the request headers.
#[utoipa::path(put, path = "/admin/company/logo", tag = "core",
    request_body(content = String, content_type = "application/octet-stream"),
    responses((status = 200, body = CompanyLogoInfo), (status = 403, body = ErrorBody),
              (status = 422, body = ErrorBody)))]
async fn put_logo(
    State(state): State<AppState>,
    user: CurrentUser,
    body: Bytes,
) -> AppResult<Json<CompanyLogoInfo>> {
    user.require(Permission::UsersAdmin)?;
    let content_type = logo::validate(&body)?;
    let mut tx = state.db.begin().await?;
    let updated_at: chrono::DateTime<chrono::Utc> = sqlx::query_scalar(
        "INSERT INTO core.company_logos (company_id, content_type, bytes) VALUES ($1, $2, $3)
         ON CONFLICT (company_id) DO UPDATE
            SET content_type = EXCLUDED.content_type, bytes = EXCLUDED.bytes, updated_at = now()
         RETURNING updated_at",
    )
    .bind(user.company_id)
    .bind(content_type)
    .bind(&body[..])
    .fetch_one(&mut *tx)
    .await?;
    audit::record(
        &mut tx,
        &user,
        "company",
        user.company_id,
        "logo_set",
        serde_json::json!({ "content_type": content_type, "size_bytes": body.len() }),
    )
    .await?;
    tx.commit().await?;
    Ok(Json(CompanyLogoInfo {
        content_type: content_type.to_string(),
        size_bytes: body.len() as i64,
        updated_at,
    }))
}

/// Removes the company logo. 404 when there is none.
#[utoipa::path(delete, path = "/admin/company/logo", tag = "core",
    responses((status = 204), (status = 403, body = ErrorBody), (status = 404, body = ErrorBody)))]
async fn delete_logo(State(state): State<AppState>, user: CurrentUser) -> AppResult<StatusCode> {
    user.require(Permission::UsersAdmin)?;
    let mut tx = state.db.begin().await?;
    let deleted = sqlx::query("DELETE FROM core.company_logos WHERE company_id = $1")
        .bind(user.company_id)
        .execute(&mut *tx)
        .await?
        .rows_affected();
    if deleted == 0 {
        return Err(AppError::NotFound("company logo"));
    }
    audit::record(
        &mut tx,
        &user,
        "company",
        user.company_id,
        "logo_removed",
        serde_json::json!({}),
    )
    .await?;
    tx.commit().await?;
    Ok(StatusCode::NO_CONTENT)
}

// ---------------------------------------------------------------------------------------------
// Users
// ---------------------------------------------------------------------------------------------

/// A member of the active company, including deactivated ones.
#[derive(Debug, Serialize, FromRow, ToSchema)]
pub struct AdminUser {
    pub user_id: Uuid,
    pub email: String,
    pub display_name: String,
    pub roles: Vec<String>,
    /// Modules switched off for this user (on top of the company's).
    pub disabled_modules: Vec<String>,
    /// False when the membership in this company is deactivated.
    pub active: bool,
    /// Whether the person has signed in with the identity provider yet.
    pub has_signed_in: bool,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct AdminUserCreate {
    pub email: String,
    pub display_name: String,
    pub roles: Vec<String>,
    #[serde(default)]
    pub disabled_modules: Vec<String>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct AdminUserUpdate {
    pub display_name: String,
    pub roles: Vec<String>,
    pub disabled_modules: Vec<String>,
    pub active: bool,
}

const MEMBER_SELECT: &str = "SELECT u.id AS user_id, u.email, u.display_name, uc.roles,
        uc.disabled_modules, uc.active, (u.oidc_subject IS NOT NULL) AS has_signed_in
    FROM core.user_companies uc JOIN core.users u ON u.id = uc.user_id";

async fn load_member(
    conn: &mut PgConnection,
    company_id: Uuid,
    user_id: Uuid,
) -> AppResult<AdminUser> {
    sqlx::query_as(&format!(
        "{MEMBER_SELECT} WHERE uc.company_id = $1 AND uc.user_id = $2"
    ))
    .bind(company_id)
    .bind(user_id)
    .fetch_optional(conn)
    .await?
    .ok_or(AppError::NotFound("user"))
}

fn check_roles(roles: &[String]) -> AppResult<Vec<String>> {
    let mut out: Vec<String> = Vec::new();
    for r in roles {
        let r = r.trim();
        if !ROLES.contains(&r) {
            return Err(AppError::Validation(format!("unknown role '{r}'")));
        }
        if !out.iter().any(|x| x == r) {
            out.push(r.to_string());
        }
    }
    if out.is_empty() {
        return Err(AppError::Validation("at least one role is required".into()));
    }
    out.sort_by_key(|r| ROLES.iter().position(|x| x == r));
    Ok(out)
}

fn check_name(name: &str) -> AppResult<String> {
    let name = name.trim();
    if name.is_empty() || name.chars().count() > 100 {
        return Err(AppError::Validation(
            "display_name is required (at most 100 characters)".into(),
        ));
    }
    Ok(name.to_string())
}

fn check_email(email: &str) -> AppResult<String> {
    let email = email.trim().to_lowercase();
    let ok = email.len() <= 254
        && !email.contains(char::is_whitespace)
        && email
            .split_once('@')
            .is_some_and(|(local, domain)| !local.is_empty() && domain.contains('.'));
    if ok {
        Ok(email)
    } else {
        Err(AppError::Validation(
            "a valid e-mail address is required".into(),
        ))
    }
}

/// Queues the invitation. It carries no secret: the person signs in with the identity provider
/// and the first sign-in binds the account to this address.
async fn queue_invitation(
    conn: &mut PgConnection,
    company_id: Uuid,
    member: &AdminUser,
) -> AppResult<()> {
    let company: String = sqlx::query_scalar("SELECT name FROM core.companies WHERE id = $1")
        .bind(company_id)
        .fetch_one(&mut *conn)
        .await?;
    let subject = format!("You have been invited to {company}");
    let body = if member.has_signed_in {
        format!(
            "Hello {name},\n\nYou have been given access to {company}. \
             You can switch to it in the application.\n\nYour roles: {roles}.\n",
            name = member.display_name,
            roles = member.roles.join(", ")
        )
    } else {
        format!(
            "Hello {name},\n\nYou have been given access to {company}. \
             Sign in with your company account using this e-mail address ({email}); \
             your first sign-in links your account.\n\nYour roles: {roles}.\n",
            name = member.display_name,
            email = member.email,
            roles = member.roles.join(", ")
        )
    };
    mail::enqueue(conn, company_id, &member.email, &subject, &body).await?;
    Ok(())
}

/// All members of the active company, deactivated ones included.
#[utoipa::path(get, path = "/admin/users", tag = "core",
    responses((status = 200, body = Vec<AdminUser>), (status = 403, body = ErrorBody)))]
async fn list_admin_users(
    State(state): State<AppState>,
    user: CurrentUser,
) -> AppResult<Json<Vec<AdminUser>>> {
    user.require(Permission::UsersAdmin)?;
    Ok(Json(
        sqlx::query_as(&format!(
            "{MEMBER_SELECT} WHERE uc.company_id = $1 ORDER BY lower(u.display_name), u.email"
        ))
        .bind(user.company_id)
        .fetch_all(&state.db)
        .await?,
    ))
}

/// Gives a person access to the company and queues an invitation e-mail. A new e-mail address
/// creates the user; an address that already exists (in another company) only gets the
/// membership and keeps its name.
#[utoipa::path(post, path = "/admin/users", tag = "core", request_body = AdminUserCreate,
    responses((status = 201, body = AdminUser), (status = 403, body = ErrorBody),
              (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn create_admin_user(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<AdminUserCreate>,
) -> AppResult<(StatusCode, Json<AdminUser>)> {
    user.require(Permission::UsersAdmin)?;
    let email = check_email(&input.email)?;
    let name = check_name(&input.display_name)?;
    let roles = check_roles(&input.roles)?;
    let mut tx = state.db.begin().await?;
    let company_disabled = company_disabled(&mut tx, user.company_id).await?;
    let disabled = modules::codes(
        &modules::validate_user_disabled(&company_disabled, &input.disabled_modules)
            .map_err(AppError::Validation)?,
    );

    let existing: Option<(Uuid, bool)> =
        sqlx::query_as("SELECT id, active FROM core.users WHERE lower(email) = lower($1)")
            .bind(&email)
            .fetch_optional(&mut *tx)
            .await?;
    let user_id = match existing {
        Some((id, active)) => {
            let member: bool = sqlx::query_scalar(
                "SELECT EXISTS (SELECT 1 FROM core.user_companies WHERE user_id = $1 AND company_id = $2)",
            )
            .bind(id)
            .bind(user.company_id)
            .fetch_one(&mut *tx)
            .await?;
            if member {
                return Err(AppError::Conflict(
                    "this person is already a member of the company".into(),
                ));
            }
            if !active {
                return Err(AppError::Conflict(
                    "this account has been disabled and cannot be added".into(),
                ));
            }
            id
        }
        None => {
            let id = new_id();
            sqlx::query("INSERT INTO core.users (id, email, display_name) VALUES ($1, $2, $3)")
                .bind(id)
                .bind(&email)
                .bind(&name)
                .execute(&mut *tx)
                .await?;
            id
        }
    };
    sqlx::query(
        "INSERT INTO core.user_companies (user_id, company_id, roles, disabled_modules, is_default)
         VALUES ($1, $2, $3, $4,
                 NOT EXISTS (SELECT 1 FROM core.user_companies WHERE user_id = $1))",
    )
    .bind(user_id)
    .bind(user.company_id)
    .bind(&roles)
    .bind(&disabled)
    .execute(&mut *tx)
    .await?;
    audit::record(
        &mut tx,
        &user,
        "user",
        user_id,
        "create_member",
        serde_json::json!({ "email": email, "roles": roles, "disabled_modules": disabled }),
    )
    .await?;
    let member = load_member(&mut tx, user.company_id, user_id).await?;
    queue_invitation(&mut tx, user.company_id, &member).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(member)))
}

/// Changes a member's name, roles, module switches and whether the membership is active.
/// Deactivating only affects this company. You cannot deactivate yourself or drop your own
/// admin role, and the company always keeps an active admin.
#[utoipa::path(put, path = "/admin/users/{id}", tag = "core",
    params(("id" = Uuid, Path)), request_body = AdminUserUpdate,
    responses((status = 200, body = AdminUser), (status = 403, body = ErrorBody),
              (status = 404, body = ErrorBody), (status = 409, body = ErrorBody),
              (status = 422, body = ErrorBody)))]
async fn update_admin_user(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<AdminUserUpdate>,
) -> AppResult<Json<AdminUser>> {
    user.require(Permission::UsersAdmin)?;
    let name = check_name(&input.display_name)?;
    let roles = check_roles(&input.roles)?;
    let mut tx = state.db.begin().await?;
    let company_disabled = company_disabled(&mut tx, user.company_id).await?;
    let disabled = modules::codes(
        &modules::validate_user_disabled(&company_disabled, &input.disabled_modules)
            .map_err(AppError::Validation)?,
    );
    let locked: Option<Uuid> = sqlx::query_scalar(
        "SELECT user_id FROM core.user_companies WHERE user_id = $1 AND company_id = $2 FOR UPDATE",
    )
    .bind(id)
    .bind(user.company_id)
    .fetch_optional(&mut *tx)
    .await?;
    if locked.is_none() {
        return Err(AppError::NotFound("user"));
    }
    if id == user.user_id {
        if !input.active {
            return Err(AppError::Conflict("you cannot deactivate yourself".into()));
        }
        if !roles.iter().any(|r| r == "admin") {
            return Err(AppError::Conflict(
                "you cannot remove your own admin role".into(),
            ));
        }
    }
    sqlx::query("UPDATE core.users SET display_name = $2 WHERE id = $1")
        .bind(id)
        .bind(&name)
        .execute(&mut *tx)
        .await?;
    sqlx::query(
        "UPDATE core.user_companies SET roles = $3, disabled_modules = $4, active = $5
         WHERE user_id = $1 AND company_id = $2",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(&roles)
    .bind(&disabled)
    .bind(input.active)
    .execute(&mut *tx)
    .await?;
    // Defence in depth: the guards above already keep the acting admin in place.
    let admins: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM core.user_companies uc JOIN core.users u ON u.id = uc.user_id
         WHERE uc.company_id = $1 AND uc.active AND u.active AND 'admin' = ANY(uc.roles)",
    )
    .bind(user.company_id)
    .fetch_one(&mut *tx)
    .await?;
    if admins == 0 {
        return Err(AppError::Conflict(
            "the company needs at least one active admin".into(),
        ));
    }
    audit::record(
        &mut tx,
        &user,
        "user",
        id,
        "update_member",
        serde_json::json!({
            "display_name": name, "roles": roles, "disabled_modules": disabled, "active": input.active
        }),
    )
    .await?;
    let member = load_member(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok(Json(member))
}

/// Sends the invitation e-mail again. Refused (409) once the person has signed in, because
/// there is nothing left to invite them to, and for deactivated members.
#[utoipa::path(post, path = "/admin/users/{id}/invite", tag = "core",
    params(("id" = Uuid, Path)),
    responses((status = 204, description = "Invitation queued"), (status = 403, body = ErrorBody),
              (status = 404, body = ErrorBody), (status = 409, body = ErrorBody)))]
async fn invite_admin_user(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<StatusCode> {
    user.require(Permission::UsersAdmin)?;
    let mut tx = state.db.begin().await?;
    let member = load_member(&mut tx, user.company_id, id).await?;
    if !member.active {
        return Err(AppError::Conflict(
            "the membership is deactivated; activate it first".into(),
        ));
    }
    if member.has_signed_in {
        return Err(AppError::Conflict(
            "this person has already signed in".into(),
        ));
    }
    queue_invitation(&mut tx, user.company_id, &member).await?;
    audit::record(
        &mut tx,
        &user,
        "user",
        id,
        "invite_member",
        serde_json::json!({ "email": member.email }),
    )
    .await?;
    tx.commit().await?;
    Ok(StatusCode::NO_CONTENT)
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(list_roles))
        .routes(routes!(get_modules, set_modules))
        .merge(
            OpenApiRouter::new()
                .routes(routes!(get_logo, put_logo, delete_logo))
                .layer(DefaultBodyLimit::max(MAX_LOGO_BYTES + 64 * 1024)),
        )
        .routes(routes!(list_admin_users, create_admin_user))
        .routes(routes!(update_admin_user))
        .routes(routes!(invite_admin_user))
        .merge(crate::vat_rates::router())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn roles_are_checked_deduplicated_and_ordered() {
        let r = check_roles(&["sales".into(), "admin".into(), "sales".into()]).unwrap();
        assert_eq!(r, ["admin", "sales"]);
        assert!(check_roles(&["intern".into()]).is_err());
        assert!(check_roles(&[]).is_err());
    }

    #[test]
    fn emails_are_normalised_and_checked() {
        assert_eq!(check_email("  A@Ex.COM ").unwrap(), "a@ex.com");
        for bad in ["", "a", "a@b", "@b.com", "a b@c.com"] {
            assert!(check_email(bad).is_err(), "{bad}");
        }
    }
}
