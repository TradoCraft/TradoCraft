mod auth;
mod orders;

use std::{net::SocketAddr, sync::Arc};

use anyhow::{ensure, Context};
use axum::{extract::State, middleware, routing::get, Json, Router};
use rmcp::transport::streamable_http_server::{
    session::local::LocalSessionManager, StreamableHttpServerConfig, StreamableHttpService,
};
use serde_json::json;
use sqlx::postgres::PgPoolOptions;
use tradocraft_core::identity::{validate_idp_url, IdentityProviders, IdpSettings, ProviderConfig};
use url::Url;

use auth::{authorize, OAuth};
use orders::OrderTools;

const SCOPE: &str = "orders:read";
const METADATA: &str = "/.well-known/oauth-protected-resource/mcp";

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info,sqlx=warn".into()),
        )
        .init();

    let resource = std::env::var("MCP_RESOURCE_URL").context("MCP_RESOURCE_URL is required")?;
    let url = Url::parse(&resource).context("invalid MCP_RESOURCE_URL")?;
    ensure!(
        url.scheme() == "https"
            && url.host_str().is_some()
            && url.path() == "/mcp"
            && url.username().is_empty()
            && url.password().is_none()
            && url.query().is_none()
            && url.fragment().is_none()
            && url.as_str() == resource,
        "MCP_RESOURCE_URL must be a canonical HTTPS URL ending in /mcp"
    );
    let issuer = std::env::var("MCP_ISSUER").context("MCP_ISSUER is required")?;
    let settings = IdpSettings::default();
    validate_idp_url(&settings, &issuer).map_err(anyhow::Error::msg)?;
    let verifier =
        IdentityProviders::new(settings, Some(ProviderConfig::from_env(&issuer, &resource)));
    let db = PgPoolOptions::new()
        .max_connections(10)
        .connect(&std::env::var("DATABASE_URL").context("DATABASE_URL is required")?)
        .await?;
    let metadata = url.join(METADATA)?;
    let oauth = Arc::new(OAuth::new(db.clone(), verifier, issuer, resource, metadata));

    let addr: SocketAddr = std::env::var("MCP_BIND_ADDR")
        .unwrap_or_else(|_| "127.0.0.1:8091".into())
        .parse()
        .context("invalid MCP_BIND_ADDR")?;
    ensure!(
        addr.ip().is_loopback(),
        "put the HTTPS proxy in front of a loopback listener"
    );

    let mut config = StreamableHttpServerConfig::default()
        .with_json_response(true)
        .with_legacy_session_mode(false)
        .with_max_request_body_bytes(32 * 1024)
        .enforce_origin_validation();
    config.allowed_hosts.push(url.host_str().unwrap().into());
    let app = router(oauth, config);
    let listener = tokio::net::TcpListener::bind(addr).await?;
    tracing::info!(%addr, "MCP server listening");
    axum::serve(listener, app)
        .with_graceful_shutdown(async {
            let _ = tokio::signal::ctrl_c().await;
        })
        .await?;
    Ok(())
}

fn router(oauth: Arc<OAuth>, config: StreamableHttpServerConfig) -> Router {
    let db = oauth.db.clone();
    let mcp = StreamableHttpService::new(
        move || Ok(OrderTools::new(db.clone())),
        Arc::new(LocalSessionManager::default()),
        config,
    );
    Router::new()
        .route_service("/mcp", mcp)
        .route_layer(middleware::from_fn_with_state(oauth.clone(), authorize))
        .route(METADATA, get(protected_resource))
        .with_state(oauth)
}

async fn protected_resource(State(oauth): State<Arc<OAuth>>) -> Json<serde_json::Value> {
    Json(json!({
        "resource": oauth.resource,
        "authorization_servers": [oauth.issuer],
        "scopes_supported": [SCOPE],
        "bearer_methods_supported": ["header"]
    }))
}

#[cfg(test)]
mod tests;
