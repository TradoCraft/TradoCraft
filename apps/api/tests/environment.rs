//! `GET /api/v1/meta/environment` (ADR 0043).

mod common;

use axum::http::{Method, StatusCode};
use common::{call, call_portal, setup};
use sqlx::PgPool;
use std::sync::Arc;
use tradocraft_core::auth::AuthConfig;
use tradocraft_core::environment::EnvironmentConfig;
use tradocraft_core::{AppState, DocumentConfig};

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn defaults_to_live_and_the_database_name(db: PgPool) {
    let expected_db: String = sqlx::query_scalar("SELECT current_database()")
        .fetch_one(&db)
        .await
        .unwrap();
    let app = setup(db).await;
    // No sign-in needed: the login screen shows the environment too.
    let (status, body) =
        call_portal(&app, None, Method::GET, "/api/v1/meta/environment", None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["kind"], "live");
    assert_eq!(body["name"], expected_db.as_str());
    assert_eq!(body["db_name"], expected_db.as_str());
    assert_eq!(body["version"], env!("CARGO_PKG_VERSION"));
    // Nothing but these four fields: no host, user or password.
    assert_eq!(body.as_object().unwrap().len(), 4);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn reports_the_configured_name_and_kind(db: PgPool) {
    let app = tradocraft_api::app_with_environment(
        AppState {
            db,
            auth: Arc::new(AuthConfig::Dev {
                default_email: None,
            }),
            documents: Arc::new(DocumentConfig {
                typst_bin: "typst".into(),
                template_dir: "templates".into(),
            }),
            live_events: tradocraft_core::live_events::LiveEvents::new(),
        },
        EnvironmentConfig::from_values(Some("Tutorial A"), Some("tutorial")).unwrap(),
    );
    let (status, body) = call(
        &app,
        "anyone@example.com",
        Method::GET,
        "/api/v1/meta/environment",
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["name"], "Tutorial A");
    assert_eq!(body["kind"], "tutorial");
}

#[test]
fn an_invalid_kind_is_refused() {
    assert!(EnvironmentConfig::from_values(None, Some("prod")).is_err());
}
