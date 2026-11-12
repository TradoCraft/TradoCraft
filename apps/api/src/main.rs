use std::net::SocketAddr;
use std::path::PathBuf;
use std::sync::Arc;

use anyhow::Context;
use sqlx::postgres::PgPoolOptions;
use tracing_subscriber::EnvFilter;
use tradocraft_core::auth::AuthConfig;
use tradocraft_core::cors::CorsConfig;
use tradocraft_core::identity::{IdentityProviders, IdpSettings, ProviderConfig};
use tradocraft_core::{AppState, DocumentConfig};

fn env(name: &str) -> Option<String> {
    std::env::var(name).ok().filter(|v| !v.trim().is_empty())
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // `tradocraft-api openapi` prints the OpenAPI document (used to generate the Dart client).
    if std::env::args().nth(1).as_deref() == Some("openapi") {
        println!(
            "{}",
            serde_json::to_string_pretty(&tradocraft_api::openapi())?
        );
        return Ok(());
    }

    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| "info,sqlx=warn".into()),
        )
        .init();

    // `tradocraft-api migrate` applies the pending migrations and exits (used by `envctl clone`
    // so a clone is brought to this binary's schema before it is scrubbed and before any listener
    // starts).
    if std::env::args().nth(1).as_deref() == Some("migrate") {
        let url = env("DATABASE_URL").context("DATABASE_URL is required")?;
        let db = PgPoolOptions::new()
            .max_connections(2)
            .connect(&url)
            .await?;
        tradocraft_api::MIGRATOR
            .run(&db)
            .await
            .context("running migrations")?;
        tracing::info!("migrations applied");
        return Ok(());
    }

    // Fail fast on a bad APP_ENV_KIND, before touching the database.
    let environment = tradocraft_core::environment::EnvironmentConfig::from_env()
        .map_err(|e| anyhow::anyhow!(e))?;

    // The API only queues e-mail (the worker sends it) and never polls a mailbox; the banner makes
    // the policy visible for this instance too (ADR 0048).
    let requested_transport = env("MAIL_TRANSPORT").unwrap_or_else(|| "files".into());
    environment
        .outbound_policy(&requested_transport)
        .log_warnings(&requested_transport);

    let database_url = env("DATABASE_URL").context("DATABASE_URL is required")?;
    let db = PgPoolOptions::new()
        .max_connections(20)
        .connect(&database_url)
        .await?;
    tradocraft_api::MIGRATOR
        .run(&db)
        .await
        .context("running migrations")?;

    let auth_mode = env("AUTH_MODE").unwrap_or_else(|| "oidc".into());
    let addr: SocketAddr = env("BIND_ADDR")
        .unwrap_or_else(|| "127.0.0.1:8080".into())
        .parse()
        .context("BIND_ADDR must look like 127.0.0.1:8080")?;

    // Development authentication trusts a client-supplied header, so it may only run where
    // nobody else can reach it: on loopback, or when explicitly acknowledged (e.g. a container
    // whose published port is bound to the host's loopback).
    if auth_mode == "dev" {
        let acknowledged = env("ALLOW_INSECURE_DEV_AUTH").as_deref() == Some("true");
        if !addr.ip().is_loopback() && !acknowledged {
            anyhow::bail!(
                "AUTH_MODE=dev refuses to listen on {addr}: it trusts the X-Dev-User header. \
                 Bind to 127.0.0.1, use AUTH_MODE=oidc, or set ALLOW_INSECURE_DEV_AUTH=true \
                 if the port is not reachable from other machines."
            );
        }
    }

    if env("SEED_DEV_DATA").as_deref() == Some("true") {
        anyhow::ensure!(
            auth_mode == "dev",
            "SEED_DEV_DATA=true creates well-known demo users and requires AUTH_MODE=dev"
        );
    }
    if env("SEED_DEV_DATA").as_deref() == Some("true") && tradocraft_api::seed_if_empty(&db).await?
    {
        tracing::info!("development seed data loaded");
        // Extra demo data kept outside the repository; only together with the development seed.
        if let Some(dir) = env("EXTRA_SEED_DIR") {
            let ran = tradocraft_api::load_extra_seed(&db, std::path::Path::new(&dir)).await?;
            tracing::info!(files = ?ran, "extra seed data loaded from {dir}");
        }
    }

    // Plain-http and internal identity provider URLs are for local development and tests only.
    let allow_insecure_idp = env("ALLOW_INSECURE_IDP_URLS").as_deref() == Some("true");
    if allow_insecure_idp && auth_mode != "dev" && !addr.ip().is_loopback() {
        anyhow::bail!(
            "ALLOW_INSECURE_IDP_URLS=true is only honoured with AUTH_MODE=dev or a loopback BIND_ADDR"
        );
    }
    let idp_settings = IdpSettings {
        allow_insecure_urls: allow_insecure_idp,
        ..IdpSettings::default()
    };

    let auth = match auth_mode.as_str() {
        "dev" => {
            tracing::warn!("AUTH_MODE=dev: X-Dev-User header is trusted. Never use this on a reachable server.");
            AuthConfig::Dev {
                default_email: env("DEV_DEFAULT_USER"),
            }
        }
        "oidc" => {
            // OIDC_ISSUER/OIDC_AUDIENCE are the optional read-only fallback provider (ADR 0052);
            // more providers come from the database.
            let env_provider = match (env("OIDC_ISSUER"), env("OIDC_AUDIENCE")) {
                (Some(i), Some(a)) => Some(ProviderConfig::from_env(&i, &a)),
                (None, None) => None,
                _ => anyhow::bail!("OIDC_ISSUER and OIDC_AUDIENCE must be set together"),
            };
            let providers = IdentityProviders::new(idp_settings.clone(), env_provider);
            providers
                .reload(&db)
                .await
                .context("loading identity providers")?;
            if providers.enabled().is_empty() {
                tracing::warn!(
                    "no identity provider is configured: every request answers 401 \
                     (bootstrap still works with BOOTSTRAP_TOKEN)"
                );
            }
            AuthConfig::Oidc(providers)
        }
        other => anyhow::bail!("unknown AUTH_MODE {other} (expected oidc or dev)"),
    };

    // Browser origins that may call the API (ADR 0050). Development answers any origin; with
    // real sign-in only the listed ones are answered. Native clients send no Origin header.
    let cors = match env("CORS_ALLOWED_ORIGINS") {
        Some(list) => {
            CorsConfig::parse(&list).map_err(|e| anyhow::anyhow!("CORS_ALLOWED_ORIGINS: {e}"))?
        }
        None if auth_mode == "dev" => CorsConfig::Any,
        None => CorsConfig::Origins(Vec::new()),
    };
    match &cors {
        CorsConfig::Any => tracing::warn!("CORS: any browser origin is answered"),
        CorsConfig::Origins(o) if o.is_empty() => tracing::info!(
            "CORS: no browser origin is answered; set CORS_ALLOWED_ORIGINS for the web app"
        ),
        CorsConfig::Origins(o) => tracing::info!(origins = ?o, "CORS: allowed browser origins"),
    }

    let documents = DocumentConfig {
        typst_bin: PathBuf::from(env("TYPST_BIN").unwrap_or_else(|| "typst".into())),
        template_dir: PathBuf::from(env("TEMPLATE_DIR").unwrap_or_else(|| "templates".into())),
    };

    let auth = Arc::new(auth);
    // Other instances follow admin changes of the identity providers within a minute.
    tradocraft_core::identity::spawn_reload(
        auth.clone(),
        db.clone(),
        std::time::Duration::from_secs(60),
    );
    let state = AppState {
        db,
        auth,
        documents: Arc::new(documents),
    };
    let listener = tokio::net::TcpListener::bind(addr).await?;
    tracing::info!(
        kind = environment.kind.as_str(),
        name = environment.name.as_deref().unwrap_or("(database name)"),
        "environment"
    );
    tracing::info!("listening on http://{addr} (API docs at /docs)");
    axum::serve(
        listener,
        tradocraft_api::app_with_identity(
            state,
            environment,
            tradocraft_core::companies::BootstrapConfig::from_env(),
            &cors,
            idp_settings,
        ),
    )
    .with_graceful_shutdown(async {
        let _ = tokio::signal::ctrl_c().await;
    })
    .await?;
    Ok(())
}
