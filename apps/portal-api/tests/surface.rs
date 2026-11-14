//! The customer-facing server: what it serves, what it does not, and how it protects itself.

use std::net::SocketAddr;

use axum::body::Body;
use axum::extract::ConnectInfo;
use axum::http::{HeaderMap, Method, Request, StatusCode};
use http_body_util::BodyExt;
use serde_json::{json, Value};
use sqlx::PgPool;
use std::path::PathBuf;
use std::sync::Arc;
use tower::ServiceExt;
use tradocraft_core::auth::AuthConfig;
use tradocraft_core::cors::CorsConfig;
use tradocraft_core::{AppState, DocumentConfig};
use tradocraft_portal_api::limit::IpNet;
use tradocraft_portal_api::PortalConfig;

const DEV_SEED_SQL: &str = include_str!("../../../seed/dev_seed.sql");
const COMPANY: &str = "00000000-0000-7000-8000-000000000001";
const JAN: &str = "jan.peeters@alpha.example";
const SOFIE: &str = "sofie.maes@alpha.example";
const PORTAL_ORIGIN: &str = "http://localhost:8081";

async fn setup(db: PgPool, config: PortalConfig) -> axum::Router {
    sqlx::raw_sql(DEV_SEED_SQL).execute(&db).await.unwrap();
    tradocraft_portal_api::app(
        AppState {
            db,
            auth: Arc::new(AuthConfig::Disabled),
            documents: Arc::new(DocumentConfig {
                typst_bin: PathBuf::from("typst"),
                template_dir: PathBuf::from("templates"),
            }),
        },
        config,
    )
}

fn config() -> PortalConfig {
    PortalConfig {
        cors: CorsConfig::Origins(vec![PORTAL_ORIGIN.into()]),
        ..PortalConfig::default()
    }
}

struct Call<'a> {
    method: Method,
    uri: &'a str,
    /// The other end of the connection.
    peer: &'a str,
    headers: Vec<(&'a str, &'a str)>,
    body: Option<Value>,
}

impl<'a> Call<'a> {
    fn new(method: Method, uri: &'a str) -> Self {
        Call {
            method,
            uri,
            peer: "203.0.113.7",
            headers: Vec::new(),
            body: None,
        }
    }
    fn peer(mut self, peer: &'a str) -> Self {
        self.peer = peer;
        self
    }
    fn header(mut self, name: &'a str, value: &'a str) -> Self {
        self.headers.push((name, value));
        self
    }
    fn json(mut self, body: Value) -> Self {
        self.body = Some(body);
        self
    }
    async fn send(self, app: &axum::Router) -> (StatusCode, HeaderMap, Value) {
        let mut req = Request::builder().method(self.method).uri(self.uri);
        for (n, v) in &self.headers {
            req = req.header(*n, *v);
        }
        let body = match self.body {
            Some(b) => {
                req = req.header("content-type", "application/json");
                Body::from(b.to_string())
            }
            None => Body::empty(),
        };
        let mut req = req.body(body).unwrap();
        let peer: SocketAddr = format!("{}:40000", self.peer).parse().unwrap();
        req.extensions_mut().insert(ConnectInfo(peer));
        let res = app.clone().oneshot(req).await.unwrap();
        let status = res.status();
        let headers = res.headers().clone();
        let bytes = res.into_body().collect().await.unwrap().to_bytes();
        (
            status,
            headers,
            serde_json::from_slice(&bytes).unwrap_or(Value::Null),
        )
    }
}

fn login_link(email: &str) -> Value {
    json!({ "company_id": COMPANY, "email": email })
}

/// The token of the newest login mail to this address.
async fn mailed_token(db: &PgPool, email: &str) -> String {
    let body: String = sqlx::query_scalar(
        "SELECT body FROM core.mail_outbox WHERE to_address = $1 ORDER BY created_at DESC LIMIT 1",
    )
    .bind(email)
    .fetch_one(db)
    .await
    .unwrap();
    let start = body.find("#token=").expect("a link with a token") + "#token=".len();
    body[start..]
        .chars()
        .take_while(|c| c.is_ascii_alphanumeric() || *c == '_')
        .collect()
}

/// Whether a path of the staff API's contract belongs to the customer-facing surface.
fn customer_facing(path: &str) -> bool {
    ["/api/v1/portal/", "/api/v1/public/kb/", "/api/v1/csat/"]
        .iter()
        .any(|p| path.starts_with(p))
}

/// Every operation of the full API contract that is not customer-facing must be absent here: not
/// refused, absent. A new staff module can therefore never leak onto this server by accident.
#[sqlx::test(migrations = "../../migrations")]
async fn no_staff_route_exists_on_the_portal_server(db: PgPool) {
    let app = setup(
        db,
        PortalConfig {
            per_minute: 0,
            login_per_minute: 0,
            ..config()
        },
    )
    .await;
    let contract: Value = serde_json::from_str(include_str!("../../../api/openapi.json")).unwrap();
    let paths = contract["paths"].as_object().unwrap();
    let (mut staff, mut customer) = (0, 0);
    for (path, operations) in paths {
        // Fill path parameters with something of the right shape.
        let mut uri = String::new();
        for segment in path.split('/').skip(1) {
            uri.push('/');
            if segment.starts_with('{') {
                uri.push_str("00000000-0000-7000-8000-000000000001");
            } else {
                uri.push_str(segment);
            }
        }
        for method in operations.as_object().unwrap().keys() {
            let Ok(method) = Method::from_bytes(method.to_uppercase().as_bytes()) else {
                continue;
            };
            let (status, _, _) = Call::new(method.clone(), &uri)
                .header("x-dev-user", "admin@example.com")
                .header("authorization", "Bearer not-a-token")
                .send(&app)
                .await;
            if customer_facing(path) {
                customer += 1;
                assert_ne!(
                    status,
                    StatusCode::METHOD_NOT_ALLOWED,
                    "{method} {path} should be served here"
                );
            } else {
                staff += 1;
                assert_eq!(
                    status,
                    StatusCode::NOT_FOUND,
                    "{method} {path} must not exist on the portal server"
                );
            }
        }
    }
    assert!(staff > 200, "the contract lists the staff API ({staff})");
    assert!(customer > 20, "the contract lists the portal ({customer})");

    // Neither does anything that describes the system or sets it up.
    for uri in ["/docs", "/api-docs/openapi.json", "/api/v1", "/"] {
        let (status, _, _) = Call::new(Method::GET, uri).send(&app).await;
        assert_eq!(status, StatusCode::NOT_FOUND, "{uri}");
    }
    let (status, _, _) = Call::new(Method::GET, "/health").send(&app).await;
    assert_eq!(status, StatusCode::OK);
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_customer_signs_in_and_reads_their_tickets(db: PgPool) {
    let app = setup(db.clone(), config()).await;

    // Not signed in.
    let (status, headers, _) = Call::new(Method::GET, "/api/v1/portal/tickets")
        .send(&app)
        .await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    assert_eq!(headers["x-content-type-options"], "nosniff");
    // A staff identity means nothing here.
    let (status, _, _) = Call::new(Method::GET, "/api/v1/portal/tickets")
        .header("x-dev-user", "admin@example.com")
        .send(&app)
        .await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);

    let (status, _, _) = Call::new(Method::POST, "/api/v1/portal/login-links")
        .json(login_link(JAN))
        .send(&app)
        .await;
    assert_eq!(status, StatusCode::ACCEPTED);
    let token = mailed_token(&db, JAN).await;
    let (status, _, session) = Call::new(Method::POST, "/api/v1/portal/sessions")
        .json(json!({ "token": token }))
        .send(&app)
        .await;
    assert_eq!(status, StatusCode::CREATED, "{session}");
    let bearer = format!("Bearer {}", session["token"].as_str().unwrap());

    let (status, _, tickets) = Call::new(Method::GET, "/api/v1/portal/tickets")
        .header("authorization", &bearer)
        .send(&app)
        .await;
    assert_eq!(status, StatusCode::OK, "{tickets}");
    assert!(tickets.is_array());

    // The public knowledge base needs no sign-in.
    let uri = format!("/api/v1/public/kb/{COMPANY}/entries?language=en");
    let (status, _, entries) = Call::new(Method::GET, &uri).send(&app).await;
    assert_eq!(status, StatusCode::OK, "{entries}");
}

#[sqlx::test(migrations = "../../migrations")]
async fn only_the_portal_origin_is_answered(db: PgPool) {
    let app = setup(db, config()).await;
    let uri = format!("/api/v1/public/kb/{COMPANY}/entries?language=en");

    let (status, headers, _) = Call::new(Method::GET, &uri)
        .header("origin", PORTAL_ORIGIN)
        .send(&app)
        .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(headers["access-control-allow-origin"], PORTAL_ORIGIN);

    let (status, headers, _) = Call::new(Method::GET, &uri)
        .header("origin", "https://evil.example")
        .send(&app)
        .await;
    // The request itself is served (CORS is enforced by the browser), but without the header the
    // browser keeps the answer from the other site's script.
    assert_eq!(status, StatusCode::OK);
    assert!(!headers.contains_key("access-control-allow-origin"));

    // The portal's preflight: the headers it will send are allowed by name (`*` would not cover
    // Authorization).
    let (status, headers, _) = Call::new(Method::OPTIONS, "/api/v1/portal/tickets")
        .header("origin", PORTAL_ORIGIN)
        .header("access-control-request-method", "POST")
        .header(
            "access-control-request-headers",
            "authorization, content-type",
        )
        .send(&app)
        .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(headers["access-control-allow-origin"], PORTAL_ORIGIN);
    let allowed = headers["access-control-allow-headers"]
        .to_str()
        .unwrap()
        .to_ascii_lowercase();
    assert!(allowed.contains("authorization"), "{allowed}");
    assert!(allowed.contains("content-type"), "{allowed}");
    assert!(!allowed.contains('*'), "{allowed}");

    let (_, headers, _) = Call::new(Method::OPTIONS, "/api/v1/portal/tickets")
        .header("origin", "https://evil.example")
        .header("access-control-request-method", "GET")
        .header("access-control-request-headers", "authorization")
        .send(&app)
        .await;
    assert!(!headers.contains_key("access-control-allow-origin"));
}

#[sqlx::test(migrations = "../../migrations")]
async fn login_attempts_are_limited_per_client_address(db: PgPool) {
    let app = setup(
        db,
        PortalConfig {
            login_per_minute: 3,
            ..config()
        },
    )
    .await;
    let ask = |peer: &'static str, email: &'static str| {
        Call::new(Method::POST, "/api/v1/portal/login-links")
            .peer(peer)
            .json(login_link(email))
    };

    // Preflights do not use up the allowance.
    for _ in 0..10 {
        let (status, _, _) = Call::new(Method::OPTIONS, "/api/v1/portal/login-links")
            .header("origin", PORTAL_ORIGIN)
            .header("access-control-request-method", "POST")
            .send(&app)
            .await;
        assert_eq!(status, StatusCode::OK);
    }
    // Whoever the links are asked for: three a minute from one address.
    for email in [JAN, SOFIE, "nobody@nowhere.example"] {
        assert_eq!(
            ask("203.0.113.7", email).send(&app).await.0,
            StatusCode::ACCEPTED
        );
    }
    let (status, headers, body) = ask("203.0.113.7", JAN)
        .header("origin", PORTAL_ORIGIN)
        .send(&app)
        .await;
    assert_eq!(status, StatusCode::TOO_MANY_REQUESTS);
    assert_eq!(body["error"], "rate_limited");
    let wait: u64 = headers["retry-after"].to_str().unwrap().parse().unwrap();
    assert!((1..=20).contains(&wait), "{wait}");
    // The portal's script can read the refusal.
    assert_eq!(headers["access-control-allow-origin"], PORTAL_ORIGIN);

    // Exchanging a link counts as a login attempt too (guessing tokens).
    let (status, _, _) = Call::new(Method::POST, "/api/v1/portal/sessions")
        .json(json!({ "token": "tcl_guess" }))
        .send(&app)
        .await;
    assert_eq!(status, StatusCode::TOO_MANY_REQUESTS);

    // Claiming another address in a header does not help: nobody here is a trusted proxy.
    let (status, _, _) = ask("203.0.113.7", JAN)
        .header("x-forwarded-for", "198.51.100.99")
        .send(&app)
        .await;
    assert_eq!(status, StatusCode::TOO_MANY_REQUESTS);

    // Other routes and other clients are not affected.
    let uri = format!("/api/v1/public/kb/{COMPANY}/entries?language=en");
    assert_eq!(
        Call::new(Method::GET, &uri).send(&app).await.0,
        StatusCode::OK
    );
    assert_eq!(
        ask("203.0.113.8", JAN).send(&app).await.0,
        StatusCode::ACCEPTED
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn behind_a_trusted_proxy_the_limit_follows_the_real_client(db: PgPool) {
    let app = setup(
        db,
        PortalConfig {
            login_per_minute: 1,
            trusted_proxies: vec![IpNet::parse("10.0.0.0/8").unwrap()],
            ..config()
        },
    )
    .await;
    let ask = |client: &'static str| {
        Call::new(Method::POST, "/api/v1/portal/login-links")
            .peer("10.0.0.2")
            .header("x-forwarded-for", client)
            .json(login_link(JAN))
    };
    assert_eq!(ask("203.0.113.7").send(&app).await.0, StatusCode::ACCEPTED);
    // A second customer through the same proxy is a different client.
    assert_eq!(ask("203.0.113.8").send(&app).await.0, StatusCode::ACCEPTED);
    assert_eq!(
        ask("203.0.113.7").send(&app).await.0,
        StatusCode::TOO_MANY_REQUESTS
    );
    // The first client lies about where it comes from; the proxy appends the truth.
    assert_eq!(
        ask("198.51.100.1, 203.0.113.7").send(&app).await.0,
        StatusCode::TOO_MANY_REQUESTS
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn every_client_has_an_overall_allowance(db: PgPool) {
    let app = setup(
        db,
        PortalConfig {
            per_minute: 5,
            ..config()
        },
    )
    .await;
    let uri = format!("/api/v1/public/kb/{COMPANY}/entries?language=en");
    for _ in 0..5 {
        assert_eq!(
            Call::new(Method::GET, &uri).send(&app).await.0,
            StatusCode::OK
        );
    }
    assert_eq!(
        Call::new(Method::GET, &uri).send(&app).await.0,
        StatusCode::TOO_MANY_REQUESTS
    );
    assert_eq!(
        Call::new(Method::GET, &uri)
            .peer("203.0.113.8")
            .send(&app)
            .await
            .0,
        StatusCode::OK
    );
}
