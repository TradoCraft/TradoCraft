//! The customer-facing HTTP server (ADR 0050).
//!
//! It mounts only what a customer may reach without a staff account: the customer portal
//! (`/api/v1/portal/*`), the public knowledge base (`/api/v1/public/kb/*`) and the satisfaction
//! survey (`/api/v1/csat/*`). Staff routes, the setup wizard, the environment endpoint and the API
//! documentation do not exist in this process, so they cannot be reached through it whatever a
//! reverse proxy in front of it forwards.
//!
//! It is the server that faces the internet, so it also limits requests per client address,
//! gives every request a deadline and answers only the portal's own browser origin.

pub mod limit;

use std::net::{IpAddr, Ipv4Addr, SocketAddr};
use std::sync::Arc;
use std::time::{Duration, Instant};

use axum::extract::{ConnectInfo, Request, State};
use axum::http::header::{HeaderName, HeaderValue, RETRY_AFTER};
use axum::http::{Method, StatusCode};
use axum::middleware::Next;
use axum::response::{IntoResponse, Response};
use axum::{Json, Router};
use limit::{client_ip, IpNet, Limiter};
use tower_http::trace::TraceLayer;
use tradocraft_core::cors::CorsConfig;
use tradocraft_core::error::ErrorBody;
use tradocraft_core::AppState;
use utoipa_axum::router::OpenApiRouter;

/// How this server protects itself.
#[derive(Debug, Clone)]
pub struct PortalConfig {
    /// Browser origins that are answered: where the portal is hosted.
    pub cors: CorsConfig,
    /// Requests a minute per client address, all routes together; 0 = no limit.
    pub per_minute: u32,
    /// Login attempts a minute per client address (asking for a link, exchanging one); 0 = no limit.
    pub login_per_minute: u32,
    /// Our own reverse proxies: only from these is `X-Forwarded-For` believed.
    pub trusted_proxies: Vec<IpNet>,
    /// A request that takes longer is answered 503.
    pub request_timeout: Duration,
}

impl Default for PortalConfig {
    fn default() -> Self {
        PortalConfig {
            cors: CorsConfig::Origins(Vec::new()),
            per_minute: 300,
            login_per_minute: 10,
            trusted_proxies: Vec::new(),
            request_timeout: Duration::from_secs(30),
        }
    }
}

struct Guard {
    all: Limiter,
    login: Limiter,
    trusted_proxies: Vec<IpNet>,
    request_timeout: Duration,
}

/// The customer-facing routes, and nothing else.
fn routes() -> Router<AppState> {
    let v1 = OpenApiRouter::new()
        .merge(tradocraft_portal::router())
        .merge(tradocraft_kb::public::router())
        .merge(tradocraft_helpdesk::csat::router());
    // The OpenAPI document is dropped on purpose: this server publishes no API description.
    let (router, _doc) = OpenApiRouter::new().nest("/api/v1", v1).split_for_parts();
    router
}

/// Serve it with `into_make_service_with_connect_info::<SocketAddr>()`: the limits are per client
/// address. Without connection info every request counts as one and the same client.
pub fn app(state: AppState, config: PortalConfig) -> Router {
    let guard = Arc::new(Guard {
        all: Limiter::new(config.per_minute),
        login: Limiter::new(config.login_per_minute),
        trusted_proxies: config.trusted_proxies,
        request_timeout: config.request_timeout,
    });
    routes()
        .route("/health", axum::routing::get(|| async { "ok" }))
        .layer(axum::middleware::from_fn_with_state(guard, protect))
        .layer(TraceLayer::new_for_http())
        // Outermost: a refused request still carries the CORS headers (so the portal can show
        // "too many requests"), and a preflight is answered without counting against a limit.
        .layer(config.cors.layer())
        .with_state(state)
}

/// The routes an anonymous visitor uses to get in; they send e-mail and check secrets.
fn is_login(method: &Method, path: &str) -> bool {
    method == Method::POST
        && matches!(
            path.trim_end_matches('/'),
            "/api/v1/portal/login-links" | "/api/v1/portal/sessions"
        )
}

async fn protect(State(guard): State<Arc<Guard>>, request: Request, next: Next) -> Response {
    let peer = request
        .extensions()
        .get::<ConnectInfo<SocketAddr>>()
        .map(|c| c.0.ip())
        .unwrap_or(IpAddr::V4(Ipv4Addr::UNSPECIFIED));
    let forwarded: Vec<&str> = request
        .headers()
        .get_all("x-forwarded-for")
        .iter()
        .filter_map(|v| v.to_str().ok())
        .collect();
    let ip = client_ip(peer, &forwarded, &guard.trusted_proxies);
    let now = Instant::now();

    let mut refused = guard.all.check(ip, now).err();
    if refused.is_none() && is_login(request.method(), request.uri().path()) {
        refused = guard.login.check(ip, now).err();
    }
    let mut response = match refused {
        Some(wait) => {
            // No path here: survey links carry their secret in it.
            tracing::warn!(client = %ip, "rate limit reached");
            too_many_requests(wait)
        }
        None => match tokio::time::timeout(guard.request_timeout, next.run(request)).await {
            Ok(response) => response,
            Err(_) => error(
                StatusCode::SERVICE_UNAVAILABLE,
                "timeout",
                "the request took too long",
            ),
        },
    };
    let headers = response.headers_mut();
    headers
        .entry(HeaderName::from_static("x-content-type-options"))
        .or_insert(HeaderValue::from_static("nosniff"));
    headers
        .entry(HeaderName::from_static("referrer-policy"))
        .or_insert(HeaderValue::from_static("no-referrer"));
    response
}

fn too_many_requests(wait: Duration) -> Response {
    let seconds = wait.as_secs_f64().ceil().max(1.0) as u64;
    let mut response = error(
        StatusCode::TOO_MANY_REQUESTS,
        "rate_limited",
        "too many requests; try again in a moment",
    );
    response
        .headers_mut()
        .insert(RETRY_AFTER, HeaderValue::from(seconds));
    response
}

fn error(status: StatusCode, error: &'static str, message: &str) -> Response {
    (
        status,
        Json(ErrorBody {
            error,
            code: None,
            message: message.to_string(),
        }),
    )
        .into_response()
}
