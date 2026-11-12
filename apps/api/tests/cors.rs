//! Which browser origins the API answers (`CORS_ALLOWED_ORIGINS`, ADR 0050).

use axum::body::Body;
use axum::http::{Request, StatusCode};
use sqlx::PgPool;
use std::sync::Arc;
use tower::ServiceExt;
use tradocraft_core::auth::AuthConfig;
use tradocraft_core::companies::BootstrapConfig;
use tradocraft_core::cors::CorsConfig;
use tradocraft_core::environment::EnvironmentConfig;
use tradocraft_core::{AppState, DocumentConfig};

fn app(db: PgPool, cors: &CorsConfig) -> axum::Router {
    tradocraft_api::app_with_cors(
        AppState {
            db,
            auth: Arc::new(AuthConfig::Dev {
                default_email: None,
            }),
            documents: Arc::new(DocumentConfig {
                typst_bin: "typst".into(),
                template_dir: "templates".into(),
            }),
        },
        EnvironmentConfig::default(),
        BootstrapConfig::default(),
        cors,
    )
}

/// The `Access-Control-Allow-Origin` header the API answers a request from `origin` with.
async fn allowed(app: &axum::Router, origin: &str) -> Option<String> {
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .uri("/api/v1/meta/environment")
                .header("origin", origin)
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::OK);
    res.headers()
        .get("access-control-allow-origin")
        .map(|v| v.to_str().unwrap().to_string())
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn only_listed_origins_are_answered(db: PgPool) {
    let listed = CorsConfig::parse("https://app.example.com, http://localhost:8081").unwrap();
    let app = app(db, &listed);
    assert_eq!(
        allowed(&app, "https://app.example.com").await.as_deref(),
        Some("https://app.example.com")
    );
    assert_eq!(
        allowed(&app, "http://localhost:8081").await.as_deref(),
        Some("http://localhost:8081")
    );
    assert_eq!(allowed(&app, "https://evil.example").await, None);
    // A look-alike is another origin.
    assert_eq!(
        allowed(&app, "https://app.example.com.evil.example").await,
        None
    );
    assert_eq!(allowed(&app, "http://app.example.com").await, None);
}

/// The headers a preflight from `origin` is told it may send.
async fn preflight_headers(app: &axum::Router, origin: &str) -> Option<String> {
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("OPTIONS")
                .uri("/api/v1/customers")
                .header("origin", origin)
                .header("access-control-request-method", "PUT")
                .header(
                    "access-control-request-headers",
                    "authorization, content-type, x-company-id",
                )
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::OK);
    res.headers()
        .get("access-control-allow-headers")
        .map(|v| v.to_str().unwrap().to_ascii_lowercase())
}

/// `Access-Control-Allow-Headers: *` does not cover Authorization, so the headers are named.
#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_preflight_allows_authorization_and_content_type_by_name(db: PgPool) {
    for cors in [
        CorsConfig::parse("https://app.example.com").unwrap(),
        CorsConfig::Any,
    ] {
        let app = app(db.clone(), &cors);
        let allowed = preflight_headers(&app, "https://app.example.com")
            .await
            .expect("allowed headers");
        for name in ["authorization", "content-type", "x-company-id"] {
            assert!(allowed.contains(name), "{name} in {allowed}");
        }
        assert!(!allowed.contains('*'), "{allowed}");
    }
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn an_empty_list_answers_no_origin_and_any_answers_all(db: PgPool) {
    let none = app(db.clone(), &CorsConfig::Origins(Vec::new()));
    assert_eq!(allowed(&none, "https://app.example.com").await, None);
    let any = app(db, &CorsConfig::Any);
    assert_eq!(
        allowed(&any, "https://anything.example").await.as_deref(),
        Some("*")
    );
}
