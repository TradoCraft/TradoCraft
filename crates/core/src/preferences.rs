//! Per-user preferences (custom keyboard shortcuts, etc.).

use std::collections::BTreeMap;

use axum::extract::State;
use axum::Json;
use serde::{Deserialize, Serialize};
use sqlx::types::Json as SqlJson;
use utoipa::ToSchema;
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;

use crate::{AppError, AppResult, AppState, CurrentUser};

/// A single keyboard shortcut chord override.
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema, PartialEq, Eq)]
pub struct ShortcutBinding {
    /// Logical key name (e.g. `"keyB"`, `"digit1"`, `"enter"`, `"escape"`, `"slash"`).
    pub key: String,
    /// Modifier group: `"primary"` (Alt on Win/Linux, Ctrl on macOS),
    /// `"standard"` (Ctrl on Win/Linux, Cmd on macOS), or `"none"`.
    #[serde(rename = "mod")]
    pub modifier: String,
    /// Whether Shift must also be held.
    #[serde(default)]
    pub shift: bool,
}

impl ShortcutBinding {
    fn validate(&mut self) -> AppResult<()> {
        self.key = self.key.trim().to_string();
        self.modifier = self.modifier.trim().to_string();
        if self.key.is_empty() || self.key.chars().count() > 64 {
            return Err(AppError::Validation(
                "shortcut key must be 1..64 characters".into(),
            ));
        }
        if !matches!(self.modifier.as_str(), "primary" | "standard" | "none") {
            return Err(AppError::Validation(
                "shortcut modifier must be primary, standard, or none".into(),
            ));
        }
        Ok(())
    }
}

/// Per-user preferences stored across sessions and devices.
#[derive(Debug, Clone, Serialize, Deserialize, Default, ToSchema)]
pub struct UserPreferences {
    /// Custom shortcut bindings keyed by `ShortcutAction.name`.
    #[serde(default)]
    pub shortcuts: BTreeMap<String, ShortcutBinding>,
}

/// Returns the authenticated user's preferences.
#[utoipa::path(get, path = "/me/preferences", tag = "core",
    responses((status = 200, body = UserPreferences), (status = 401, body = crate::error::ErrorBody)))]
async fn get_preferences(
    State(state): State<AppState>,
    user: CurrentUser,
) -> AppResult<Json<UserPreferences>> {
    let row: Option<SqlJson<BTreeMap<String, ShortcutBinding>>> = sqlx::query_scalar(
        "SELECT shortcuts FROM core.user_preferences WHERE user_id = $1",
    )
    .bind(user.user_id)
    .fetch_optional(&state.db)
    .await?;
    Ok(Json(UserPreferences {
        shortcuts: row.map(|r| r.0).unwrap_or_default(),
    }))
}

/// Replaces the authenticated user's preferences.
#[utoipa::path(put, path = "/me/preferences", tag = "core", request_body = UserPreferences,
    responses((status = 200, body = UserPreferences), (status = 400, body = crate::error::ErrorBody), (status = 401, body = crate::error::ErrorBody)))]
async fn put_preferences(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<UserPreferences>,
) -> AppResult<Json<UserPreferences>> {
    let mut cleaned = BTreeMap::new();
    for (action, mut binding) in input.shortcuts {
        let action = action.trim().to_string();
        if action.is_empty() || action.chars().count() > 64 {
            return Err(AppError::Validation(
                "shortcut action name must be 1..64 characters".into(),
            ));
        }
        binding.validate()?;
        cleaned.insert(action, binding);
    }
    let json = SqlJson(cleaned.clone());
    sqlx::query(
        "INSERT INTO core.user_preferences (user_id, shortcuts, updated_at)
         VALUES ($1, $2, now())
         ON CONFLICT (user_id) DO UPDATE
         SET shortcuts = EXCLUDED.shortcuts, updated_at = now()",
    )
    .bind(user.user_id)
    .bind(json)
    .execute(&state.db)
    .await?;
    Ok(Json(UserPreferences { shortcuts: cleaned }))
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new().routes(routes!(get_preferences, put_preferences))
}
