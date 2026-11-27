//! Request tracing without secrets. Unsubscribe and survey links carry their token in the path,
//! so a request span records the matched route template (`/api/v1/mailing-unsubscribe/{token}`)
//! instead of the URI, and no query string.
use axum::extract::MatchedPath;
use axum::http::Request;
use tower_http::classify::{ServerErrorsAsFailures, SharedClassifier};
use tower_http::trace::TraceLayer;
use tracing::Span;

type MakeSpan = fn(&Request<axum::body::Body>) -> Span;

/// `TraceLayer::new_for_http()` with spans that record the method, route and HTTP version.
pub fn layer() -> TraceLayer<SharedClassifier<ServerErrorsAsFailures>, MakeSpan> {
    TraceLayer::new_for_http().make_span_with(span as MakeSpan)
}

fn span(request: &Request<axum::body::Body>) -> Span {
    tracing::debug_span!(
        "request",
        method = %request.method(),
        route = %route(request),
        version = ?request.version(),
    )
}

/// The matched route template. An API path that matched no route is not recorded, because it may
/// be a link with a mistyped secret; other paths (the web app's files) are recorded as they are.
pub fn route<B>(request: &Request<B>) -> String {
    match request.extensions().get::<MatchedPath>() {
        Some(path) => path.as_str().to_string(),
        None if request.uri().path().starts_with("/api/") => "/api/<unmatched>".to_string(),
        None => request.uri().path().to_string(),
    }
}
