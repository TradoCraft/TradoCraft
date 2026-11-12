use std::net::SocketAddr;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;

use anyhow::Context;
use sqlx::postgres::PgPoolOptions;
use tracing_subscriber::EnvFilter;
use tradocraft_core::auth::AuthConfig;
use tradocraft_core::cors::{origin_of, CorsConfig};
use tradocraft_core::{AppState, DocumentConfig};
use tradocraft_portal_api::limit::IpNet;
use tradocraft_portal_api::PortalConfig;

fn env(name: &str) -> Option<String> {
    std::env::var(name).ok().filter(|v| !v.trim().is_empty())
}

fn env_number<T: std::str::FromStr>(name: &str, default: T) -> anyhow::Result<T> {
    match env(name) {
        Some(v) => v
            .trim()
            .parse()
            .map_err(|_| anyhow::anyhow!("{name} must be a whole number, got {v}")),
        None => Ok(default),
    }
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| "info,sqlx=warn".into()),
        )
        .init();

    // Its own connection string, so this server can use a database role with fewer rights than
    // the staff API; and its own small pool, so a flood here cannot take the office's connections.
    let database_url = env("PORTAL_DATABASE_URL")
        .or_else(|| env("DATABASE_URL"))
        .context("PORTAL_DATABASE_URL or DATABASE_URL is required")?;
    let db = PgPoolOptions::new()
        .max_connections(env_number("PORTAL_DB_MAX_CONNECTIONS", 5)?)
        .acquire_timeout(Duration::from_secs(5))
        .connect(&database_url)
        .await?;
    // No migrations here: the staff API owns the schema and must have started first.

    let addr: SocketAddr = env("PORTAL_BIND_ADDR")
        .unwrap_or_else(|| "127.0.0.1:8090".into())
        .parse()
        .context("PORTAL_BIND_ADDR must look like 127.0.0.1:8090")?;

    // The portal's own origin(s): as configured, else where the companies say their portal is
    // (the address the login e-mail links to).
    let cors = match env("PORTAL_ALLOWED_ORIGINS") {
        Some(list) => {
            CorsConfig::parse(&list).map_err(|e| anyhow::anyhow!("PORTAL_ALLOWED_ORIGINS: {e}"))?
        }
        None => {
            let urls: Vec<String> = sqlx::query_scalar(
                "SELECT portal_url FROM core.companies WHERE coalesce(portal_url, '') <> ''",
            )
            .fetch_all(&db)
            .await
            .context(
                "reading the companies' portal_url (has the staff API migrated this database?)",
            )?;
            let mut origins: Vec<String> = Vec::new();
            for url in &urls {
                match origin_of(url) {
                    Some(o) if !origins.contains(&o) => origins.push(o),
                    Some(_) => {}
                    None => tracing::warn!("ignoring portal_url {url}: not an http(s) address"),
                }
            }
            CorsConfig::Origins(origins)
        }
    };
    match &cors {
        CorsConfig::Any => tracing::warn!("CORS: any browser origin is answered"),
        CorsConfig::Origins(o) if o.is_empty() => anyhow::bail!(
            "no portal origin is known: set portal_url on the company (Settings) or \
             PORTAL_ALLOWED_ORIGINS, e.g. https://portal.example.com"
        ),
        CorsConfig::Origins(o) => tracing::info!(origins = ?o, "CORS: allowed browser origins"),
    }

    let trusted_proxies = env("PORTAL_TRUSTED_PROXIES")
        .unwrap_or_default()
        .split(',')
        .filter(|s| !s.trim().is_empty())
        .map(IpNet::parse)
        .collect::<Result<Vec<_>, _>>()
        .map_err(|e| anyhow::anyhow!("PORTAL_TRUSTED_PROXIES: {e}"))?;
    if trusted_proxies.is_empty() {
        tracing::info!(
            "no PORTAL_TRUSTED_PROXIES: X-Forwarded-For is ignored and limits count per \
             connecting address (behind a reverse proxy that is the proxy itself)"
        );
    }

    let config = PortalConfig {
        cors,
        per_minute: env_number("PORTAL_RATE_PER_MINUTE", 300)?,
        login_per_minute: env_number("PORTAL_LOGIN_RATE_PER_MINUTE", 10)?,
        trusted_proxies,
        request_timeout: Duration::from_secs(env_number("PORTAL_REQUEST_TIMEOUT_SECONDS", 30)?),
    };

    let state = AppState {
        db,
        // Staff cannot sign in through this server, however it is configured.
        auth: Arc::new(AuthConfig::Disabled),
        documents: Arc::new(DocumentConfig {
            typst_bin: PathBuf::from(env("TYPST_BIN").unwrap_or_else(|| "typst".into())),
            template_dir: PathBuf::from(env("TEMPLATE_DIR").unwrap_or_else(|| "templates".into())),
        }),
    };
    let listener = tokio::net::TcpListener::bind(addr).await?;
    tracing::info!(
        per_minute = config.per_minute,
        login_per_minute = config.login_per_minute,
        "customer portal server listening on http://{addr}"
    );
    axum::serve(
        listener,
        tradocraft_portal_api::app(state, config)
            .into_make_service_with_connect_info::<SocketAddr>(),
    )
    .with_graceful_shutdown(async {
        let _ = tokio::signal::ctrl_c().await;
    })
    .await?;
    Ok(())
}
