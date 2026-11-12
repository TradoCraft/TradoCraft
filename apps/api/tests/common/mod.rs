//! Shared helpers for API integration tests.
#![allow(dead_code)]

pub mod e2e;
pub mod idp;

use std::path::PathBuf;
use std::sync::Arc;

use axum::body::Body;
use axum::http::{Method, Request, StatusCode};
use http_body_util::BodyExt;
use rust_decimal::Decimal;
use serde_json::Value;
use sqlx::PgPool;
use tower::ServiceExt;
use tradocraft_core::auth::AuthConfig;
use tradocraft_core::{AppState, DocumentConfig};

pub async fn setup(db: PgPool) -> axum::Router {
    let _ = tracing_subscriber::fmt()
        .with_test_writer()
        .with_env_filter("error")
        .try_init();
    sqlx::raw_sql(tradocraft_api::DEV_SEED_SQL)
        .execute(&db)
        .await
        .unwrap();
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..");
    tradocraft_api::app(AppState {
        db,
        auth: Arc::new(AuthConfig::Dev {
            default_email: None,
        }),
        documents: Arc::new(DocumentConfig {
            typst_bin: std::env::var("TYPST_BIN")
                .unwrap_or_else(|_| "typst".into())
                .into(),
            template_dir: root.join("templates"),
        }),
    })
}

pub async fn call(
    app: &axum::Router,
    user: &str,
    method: Method,
    uri: &str,
    body: Option<Value>,
) -> (StatusCode, Value) {
    let mut req = Request::builder()
        .method(method)
        .uri(uri)
        .header("x-dev-user", user);
    let body = match body {
        Some(b) => {
            req = req.header("content-type", "application/json");
            Body::from(b.to_string())
        }
        None => Body::empty(),
    };
    let res = app.clone().oneshot(req.body(body).unwrap()).await.unwrap();
    let status = res.status();
    let bytes = res.into_body().collect().await.unwrap().to_bytes();
    (
        status,
        serde_json::from_slice(&bytes).unwrap_or(Value::Null),
    )
}

pub fn dec(v: &Value) -> Decimal {
    v.as_str().expect("decimal as string").parse().unwrap()
}

/// Sends a raw (non-JSON) body, e.g. an e-mail to the import endpoint.
pub async fn call_raw(
    app: &axum::Router,
    user: &str,
    uri: &str,
    content_type: &str,
    body: Vec<u8>,
) -> (StatusCode, Value) {
    let req = Request::builder()
        .method(Method::POST)
        .uri(uri)
        .header("x-dev-user", user)
        .header("content-type", content_type)
        .body(Body::from(body))
        .unwrap();
    let res = app.clone().oneshot(req).await.unwrap();
    let status = res.status();
    let bytes = res.into_body().collect().await.unwrap().to_bytes();
    (
        status,
        serde_json::from_slice(&bytes).unwrap_or(Value::Null),
    )
}

/// A request without the staff header, optionally with a bearer token (the customer portal).
pub async fn call_portal(
    app: &axum::Router,
    token: Option<&str>,
    method: Method,
    uri: &str,
    body: Option<Value>,
) -> (StatusCode, Value) {
    let mut req = Request::builder().method(method).uri(uri);
    if let Some(t) = token {
        req = req.header("authorization", format!("Bearer {t}"));
    }
    let body = match body {
        Some(b) => {
            req = req.header("content-type", "application/json");
            Body::from(b.to_string())
        }
        None => Body::empty(),
    };
    let res = app.clone().oneshot(req.body(body).unwrap()).await.unwrap();
    let status = res.status();
    let bytes = res.into_body().collect().await.unwrap().to_bytes();
    (
        status,
        serde_json::from_slice(&bytes).unwrap_or(Value::Null),
    )
}

/// Who makes a request: a staff user (dev header) or a portal session (bearer token).
pub enum Who<'a> {
    Staff(&'a str),
    Portal(&'a str),
}

/// A request with a raw body (e.g. a photo) that returns the raw response too.
pub async fn raw(
    app: &axum::Router,
    who: Who<'_>,
    method: Method,
    uri: &str,
    body: Option<(&str, Vec<u8>)>,
) -> (StatusCode, axum::http::HeaderMap, Vec<u8>) {
    let mut req = Request::builder().method(method).uri(uri);
    req = match who {
        Who::Staff(u) => req.header("x-dev-user", u),
        Who::Portal(t) => req.header("authorization", format!("Bearer {t}")),
    };
    let body = match body {
        Some((ct, b)) => {
            req = req.header("content-type", ct);
            Body::from(b)
        }
        None => Body::empty(),
    };
    let res = app.clone().oneshot(req.body(body).unwrap()).await.unwrap();
    let status = res.status();
    let headers = res.headers().clone();
    let bytes = res.into_body().collect().await.unwrap().to_bytes().to_vec();
    (status, headers, bytes)
}

/// A tiny but valid-looking JPEG (the API checks the signature, not the picture).
pub fn jpeg(tag: u8) -> Vec<u8> {
    let mut v = vec![
        0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, b'J', b'F', b'I', b'F', 0x00, tag,
    ];
    v.extend((0..64).map(|i| i as u8));
    v.extend([0xFF, 0xD9]);
    v
}

/// Signs a portal user in through the real login-link flow; returns the session token.
pub async fn portal_login(app: &axum::Router, db: &PgPool, email: &str) -> String {
    let company = "00000000-0000-7000-8000-000000000001";
    let (status, _) = call_portal(
        app,
        None,
        Method::POST,
        "/api/v1/portal/login-links",
        Some(serde_json::json!({ "company_id": company, "email": email })),
    )
    .await;
    assert_eq!(status, StatusCode::ACCEPTED);
    let body: String = sqlx::query_scalar(
        "SELECT body FROM core.mail_outbox WHERE to_address = $1 ORDER BY created_at DESC LIMIT 1",
    )
    .bind(email)
    .fetch_one(db)
    .await
    .unwrap();
    let start = body.find("#token=").unwrap() + "#token=".len();
    let link: String = body[start..]
        .chars()
        .take_while(|c| c.is_ascii_alphanumeric() || *c == '_')
        .collect();
    let (status, s) = call_portal(
        app,
        None,
        Method::POST,
        "/api/v1/portal/sessions",
        Some(serde_json::json!({ "token": link })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{s}");
    s["token"].as_str().unwrap().to_string()
}
