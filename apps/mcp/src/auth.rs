use std::sync::Arc;

use axum::{
    extract::{Request, State},
    http::{header, HeaderValue, StatusCode},
    middleware::Next,
    response::{IntoResponse, Response},
};
use serde_json::Value;
use sqlx::PgPool;
use tradocraft_core::{auth::CurrentUser, error::AppError, identity::IdentityProviders};
use url::Url;
use uuid::Uuid;

use crate::SCOPE;

pub(crate) struct OAuth {
    pub db: PgPool,
    pub issuer: String,
    pub resource: String,
    verifier: IdentityProviders,
    metadata: Url,
}

#[derive(Clone)]
pub(crate) struct DelegatedUser {
    pub user: CurrentUser,
    pub client_id: String,
}

impl OAuth {
    pub fn new(
        db: PgPool,
        verifier: IdentityProviders,
        issuer: String,
        resource: String,
        metadata: Url,
    ) -> Self {
        Self {
            db,
            issuer,
            resource,
            verifier,
            metadata,
        }
    }

    async fn authenticate(&self, token: &str) -> Result<DelegatedUser, Rejection> {
        let header = jsonwebtoken::decode_header(token).map_err(|_| Rejection::InvalidToken)?;
        if !header.typ.as_deref().is_some_and(|typ| {
            typ.eq_ignore_ascii_case("at+jwt") || typ.eq_ignore_ascii_case("application/at+jwt")
        }) {
            return Err(Rejection::InvalidToken);
        }

        let verified = self.verifier.verify(token).await?;
        let claims = &verified.claims.raw;
        let audience = claims.get("aud");
        if claims.get("iss").and_then(Value::as_str) != Some(&self.issuer)
            || !(audience.and_then(Value::as_str) == Some(&self.resource)
                || audience.and_then(Value::as_array).is_some_and(|values| {
                    values.len() == 1 && values[0].as_str() == Some(&self.resource)
                }))
        {
            return Err(Rejection::InvalidToken);
        }
        let client_id = claims
            .get("client_id")
            .and_then(Value::as_str)
            .filter(|id| !id.is_empty())
            .ok_or(Rejection::InvalidToken)?;
        let has_scope = claims
            .get("scope")
            .and_then(Value::as_str)
            .is_some_and(|scopes| scopes.split_ascii_whitespace().any(|scope| scope == SCOPE));
        if !has_scope {
            return Err(Rejection::InsufficientScope);
        }
        let (user_id, company_id): (Uuid, Uuid) = sqlx::query_as(
            "SELECT user_id, company_id FROM core.mcp_order_read_grants
             WHERE issuer = $1 AND resource = $2 AND subject = $3 AND client_id = $4",
        )
        .bind(&self.issuer)
        .bind(&self.resource)
        .bind(
            claims
                .get("sub")
                .and_then(Value::as_str)
                .ok_or(Rejection::InvalidToken)?,
        )
        .bind(client_id)
        .fetch_optional(&self.db)
        .await
        .map_err(AppError::from)?
        .ok_or(Rejection::Forbidden)?;

        let user = CurrentUser::for_member(&self.db, user_id, company_id).await?;
        Ok(DelegatedUser {
            user,
            client_id: client_id.to_owned(),
        })
    }

    fn reject(&self, rejection: Rejection) -> Response {
        let (status, detail) = match rejection {
            Rejection::MissingToken => (StatusCode::UNAUTHORIZED, String::new()),
            Rejection::InvalidToken => {
                (StatusCode::UNAUTHORIZED, ", error=\"invalid_token\"".into())
            }
            Rejection::InsufficientScope => (
                StatusCode::FORBIDDEN,
                format!(", error=\"insufficient_scope\", scope=\"{SCOPE}\""),
            ),
            Rejection::Forbidden => return StatusCode::FORBIDDEN.into_response(),
            Rejection::Internal(error) => return error.into_response(),
        };
        let mut response = status.into_response();
        if let Ok(value) = HeaderValue::from_str(&format!(
            "Bearer resource_metadata=\"{}\"{detail}",
            self.metadata
        )) {
            response
                .headers_mut()
                .insert(header::WWW_AUTHENTICATE, value);
        }
        response
    }
}

enum Rejection {
    MissingToken,
    InvalidToken,
    InsufficientScope,
    Forbidden,
    Internal(AppError),
}

impl From<AppError> for Rejection {
    fn from(error: AppError) -> Self {
        match error {
            AppError::Unauthorized => Self::InvalidToken,
            AppError::Forbidden(_) => Self::Forbidden,
            other => Self::Internal(other),
        }
    }
}

pub(crate) async fn authorize(
    State(oauth): State<Arc<OAuth>>,
    mut request: Request,
    next: Next,
) -> Response {
    let Some(value) = request.headers_mut().remove(header::AUTHORIZATION) else {
        return oauth.reject(Rejection::MissingToken);
    };
    let Some(token) = value.to_str().ok().and_then(|value| {
        let (scheme, token) = value.split_once(' ')?;
        (scheme.eq_ignore_ascii_case("Bearer") && !token.is_empty()).then_some(token)
    }) else {
        return oauth.reject(Rejection::InvalidToken);
    };
    match oauth.authenticate(token).await {
        Ok(user) => {
            request.extensions_mut().insert(user);
            next.run(request).await
        }
        Err(rejection) => oauth.reject(rejection),
    }
}
