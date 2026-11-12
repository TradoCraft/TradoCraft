//! Helpdesk mailboxes (ADR 0054): the settings API, routing of incoming mail to the mailbox's
//! team, replies through the ticket's mailbox, and Microsoft Graph against a local stand-in.

mod common;

use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use axum::body::Bytes;
use axum::extract::{Path, State};
use axum::http::{HeaderMap, Method, StatusCode};
use axum::routing::{get, post};
use axum::Json;
use common::{call, setup};
use serde_json::{json, Value};
use sqlx::PgPool;
use tradocraft_helpdesk::graph::GraphClient;
use tradocraft_helpdesk::ingest::{ingest_from, Source};
use tradocraft_helpdesk::mailboxes::{self, load_active, poll_all, transports};
use tradocraft_helpdesk::mailer::{
    process_outbox, process_outbox_with, process_system_mail_with, Mailer, Transports,
};
use uuid::Uuid;

const COMPANY: &str = "00000000-0000-7000-8000-000000000001";
const ADMIN: &str = "admin@example.com";
const SUPPORT: &str = "support@example.com";

fn graph_input(name: &str, address: &str) -> Value {
    json!({
        "name": name, "address": address, "kind": "graph", "secret_ref": "SUPPORT",
        "tenant_id": "contoso.onmicrosoft.com", "client_id": "11111111-2222-3333-4444-555555555555",
    })
}

/// The input with some fields replaced.
fn with(mut input: Value, changes: Value) -> Value {
    for (k, v) in changes.as_object().unwrap() {
        input[k] = v.clone();
    }
    input
}

fn imap_input(name: &str, address: &str) -> Value {
    json!({
        "name": name, "address": address, "kind": "imap_smtp", "secret_ref": "ONPREM",
        "username": "helpdesk", "imap_host": "mail.example.com", "smtp_host": "mail.example.com",
    })
}

async fn create(app: &axum::Router, input: Value) -> Value {
    let (status, m) = call(
        app,
        ADMIN,
        Method::POST,
        "/api/v1/helpdesk/mailboxes",
        Some(input),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{m}");
    m
}

async fn list(app: &axum::Router) -> Vec<Value> {
    let (status, l) = call(app, ADMIN, Method::GET, "/api/v1/helpdesk/mailboxes", None).await;
    assert_eq!(status, StatusCode::OK, "{l}");
    l.as_array().unwrap().clone()
}

fn mail(from: &str, to: &str, subject: &str, headers: &str) -> Vec<u8> {
    format!(
        "From: {from}\r\nTo: {to}\r\nSubject: {subject}\r\n{headers}Content-Type: text/plain; charset=utf-8\r\n\r\nHello\r\n"
    )
    .into_bytes()
}

fn secrets(reference: &str) -> Option<String> {
    (reference == "SUPPORT" || reference == "ONPREM").then(|| "s3cret-value".to_string())
}

fn no_secrets(_: &str) -> Option<String> {
    None
}

fn eml_files(dir: &std::path::Path) -> Vec<String> {
    std::fs::read_dir(dir)
        .map(|d| {
            d.map(|f| std::fs::read_to_string(f.unwrap().path()).unwrap())
                .collect()
        })
        .unwrap_or_default()
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn settings_api_validates_and_keeps_one_default(db: PgPool) {
    let app = setup(db.clone()).await;

    // Only helpdesk administrators see or change mailboxes.
    for (method, uri, body) in [
        (Method::GET, "/api/v1/helpdesk/mailboxes", None),
        (
            Method::POST,
            "/api/v1/helpdesk/mailboxes",
            Some(graph_input("Support", "support@contoso.example")),
        ),
    ] {
        let (status, r) = call(&app, SUPPORT, method, uri, body).await;
        assert_eq!(status, StatusCode::FORBIDDEN, "{r}");
    }

    let m = create(
        &app,
        with(
            graph_input("Support", " Support@Contoso.Example "),
            json!({ "is_default": true }),
        ),
    )
    .await;
    assert_eq!(m["address"], "support@contoso.example");
    assert_eq!(m["kind"], "graph");
    assert_eq!(m["is_default"], true);
    assert_eq!(m["active"], true);
    assert_eq!(m["inbound_enabled"], true);
    assert_eq!(m["secret_ref"], "SUPPORT");
    assert_eq!(m["last_poll_at"], Value::Null);
    // No field can carry a secret: the input has none and the answer has none.
    assert!(!m.to_string().to_lowercase().contains("password"));
    assert!(m.get("client_secret").is_none());
    let support_id = m["id"].as_str().unwrap().to_string();

    for (bad, why) in [
        (
            with(
                graph_input("X", "x@contoso.example"),
                json!({ "kind": "ews" }),
            ),
            "kind",
        ),
        (
            with(
                graph_input("X", "x@contoso.example"),
                json!({ "secret_ref": "lower case" }),
            ),
            "secret name",
        ),
        (
            with(
                graph_input("X", "x@contoso.example"),
                json!({ "tenant_id": null }),
            ),
            "tenant",
        ),
        (
            with(
                graph_input("X", "x@contoso.example"),
                json!({ "tenant_id": "evil.example/x?" }),
            ),
            "tenant",
        ),
        (graph_input("X", "not-an-address"), "address"),
        (graph_input("X", "a/b@contoso.example/x"), "address"),
        (graph_input("X", "a/../b?x=1#@contoso.example"), "address"),
        (graph_input("  ", "x@contoso.example"), "name"),
        (
            with(
                imap_input("X", "x@contoso.example"),
                json!({ "imap_host": null }),
            ),
            "IMAP server",
        ),
        (
            with(
                imap_input("X", "x@contoso.example"),
                json!({ "smtp_security": "ssl" }),
            ),
            "SMTP security",
        ),
        (
            with(
                imap_input("X", "x@contoso.example"),
                json!({ "smtp_port": 70000 }),
            ),
            "port",
        ),
        (
            with(
                imap_input("X", "x@contoso.example"),
                json!({ "team_id": Uuid::now_v7() }),
            ),
            "team",
        ),
        (
            with(
                imap_input("X", "x@contoso.example"),
                json!({ "is_default": true, "active": false }),
            ),
            "default mailbox must be active",
        ),
    ] {
        let (status, r) = call(
            &app,
            ADMIN,
            Method::POST,
            "/api/v1/helpdesk/mailboxes",
            Some(bad.clone()),
        )
        .await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{bad} -> {r}");
        assert!(r.to_string().contains(why), "{why}: {r}");
    }

    // The same address or name twice is a conflict.
    let (status, r) = call(
        &app,
        ADMIN,
        Method::POST,
        "/api/v1/helpdesk/mailboxes",
        Some(graph_input("Other", "support@contoso.example")),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT, "{r}");

    // A send-only IMAP/SMTP mailbox needs no IMAP server. Making it the default takes the mark
    // from the first one.
    let onprem = create(
        &app,
        with(
            imap_input("On-premises", "service@example.com"),
            json!({ "is_default": true, "inbound_enabled": false, "imap_host": null,
                "smtp_security": "tls", "smtp_port": 465 }),
        ),
    )
    .await;
    assert_eq!(onprem["smtp_security"], "tls");
    assert_eq!(onprem["imap_folder"], "INBOX");
    let all = list(&app).await;
    assert_eq!(all.len(), 2);
    assert_eq!(all[0]["name"], "On-premises", "the default comes first");
    assert_eq!(all[0]["is_default"], true);
    assert_eq!(all[1]["is_default"], false);

    // Update: the kind's own fields are kept, the other kind's are cleared.
    let (status, u) = call(
        &app,
        ADMIN,
        Method::PUT,
        &format!("/api/v1/helpdesk/mailboxes/{support_id}"),
        Some(with(
            graph_input("Support NL", "support@contoso.example"),
            json!({ "active": false, "imap_host": "ignored.example.com" }),
        )),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{u}");
    assert_eq!(u["name"], "Support NL");
    assert_eq!(u["active"], false);
    assert_eq!(u["imap_host"], Value::Null);

    let (status, r) = call(
        &app,
        ADMIN,
        Method::PUT,
        &format!("/api/v1/helpdesk/mailboxes/{}", Uuid::now_v7()),
        Some(graph_input("Nobody", "nobody@contoso.example")),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND, "{r}");

    let (status, _) = call(
        &app,
        SUPPORT,
        Method::DELETE,
        &format!("/api/v1/helpdesk/mailboxes/{support_id}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, _) = call(
        &app,
        ADMIN,
        Method::DELETE,
        &format!("/api/v1/helpdesk/mailboxes/{support_id}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    assert_eq!(list(&app).await.len(), 1);

    let audited: i64 =
        sqlx::query_scalar("SELECT count(*) FROM audit.events WHERE entity = 'helpdesk_mailbox'")
            .fetch_one(&db)
            .await
            .unwrap();
    assert_eq!(audited, 4, "created twice, updated, deleted");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn mail_goes_to_the_mailbox_team_and_replies_leave_through_the_mailbox(db: PgPool) {
    let app = setup(db.clone()).await;
    let company = Uuid::parse_str(COMPANY).unwrap();
    let (status, team) = call(
        &app,
        ADMIN,
        Method::POST,
        "/api/v1/helpdesk/teams",
        Some(json!({ "name": "Spare parts" })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{team}");
    let parts = create(
        &app,
        with(
            imap_input("Parts", "parts@example.com"),
            json!({ "team_id": team["id"] }),
        ),
    )
    .await;
    let general = create(
        &app,
        with(
            graph_input("General", "info@example.com"),
            json!({ "is_default": true }),
        ),
    )
    .await;
    let parts_id = Uuid::parse_str(parts["id"].as_str().unwrap()).unwrap();
    let general_id = Uuid::parse_str(general["id"].as_str().unwrap()).unwrap();

    let active = load_active(&db).await.unwrap();
    assert_eq!(active.len(), 2);
    let source = Source {
        mailbox_id: parts_id,
        team_id: active
            .iter()
            .find(|m| m.id == parts_id)
            .and_then(|m| m.team_id),
    };
    let r = ingest_from(
        &db,
        company,
        &mail(
            "anna@alpha.example",
            "parts@example.com",
            "Seal kit",
            "Message-ID: <p1@alpha.example>\r\n",
        ),
        Some(source),
    )
    .await
    .unwrap();
    assert!(r.new_ticket);
    let (team_id, mailbox_id): (Option<Uuid>, Option<Uuid>) =
        sqlx::query_as("SELECT team_id, mailbox_id FROM helpdesk.tickets WHERE id = $1")
            .bind(r.ticket_id)
            .fetch_one(&db)
            .await
            .unwrap();
    assert_eq!(
        team_id.map(|t| t.to_string()).as_deref(),
        team["id"].as_str()
    );
    assert_eq!(mailbox_id, Some(parts_id));

    // A reply is sent from the mailbox the ticket came in on.
    let (status, t) = call(
        &app,
        SUPPORT,
        Method::POST,
        &format!("/api/v1/tickets/{}/replies", r.ticket_id),
        Some(json!({ "body": "In stock." })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{t}");
    assert_eq!(t["articles"][1]["from_address"], "parts@example.com");

    // A ticket made by hand has no mailbox: its reply leaves through the default one.
    let (status, manual) = call(
        &app,
        SUPPORT,
        Method::POST,
        "/api/v1/tickets",
        Some(
            json!({ "subject": "Call back", "contact_email": "bob@alpha.example", "body": "note" }),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{manual}");
    let manual_id = manual["ticket"]["id"].as_str().unwrap();
    let (status, t) = call(
        &app,
        SUPPORT,
        Method::POST,
        &format!("/api/v1/tickets/{manual_id}/replies"),
        Some(json!({ "body": "We will call you." })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{t}");
    let out = t["articles"]
        .as_array()
        .unwrap()
        .iter()
        .find(|a| a["kind"] == "email_out")
        .unwrap();
    assert_eq!(out["from_address"], "info@example.com");

    // Each e-mail goes to the transport of its own mailbox; nothing reaches the fallback.
    let (fallback_dir, parts_dir, general_dir) = (
        tempfile::tempdir().unwrap(),
        tempfile::tempdir().unwrap(),
        tempfile::tempdir().unwrap(),
    );
    let fallback = Mailer::Files(fallback_dir.path().to_path_buf());
    let mut map: HashMap<Uuid, Result<Mailer, String>> = HashMap::new();
    map.insert(parts_id, Ok(Mailer::Files(parts_dir.path().to_path_buf())));
    map.insert(
        general_id,
        Err("mailbox General: the worker has no MAILBOX_SECRET_SUPPORT variable".into()),
    );
    let with_mailboxes = Transports {
        fallback: &fallback,
        mailboxes: Some(&map),
    };
    // The parts reply is sent; the general one fails with the reason and stays queued.
    let mut sent = 0;
    for _ in 0..3 {
        sent += process_outbox_with(&db, &with_mailboxes, 10).await.unwrap();
    }
    assert_eq!(sent, 1);
    let parts_mail = eml_files(parts_dir.path());
    assert_eq!(parts_mail.len(), 1);
    assert!(
        parts_mail[0].contains("<parts@example.com>"),
        "{}",
        parts_mail[0]
    );
    assert!(eml_files(fallback_dir.path()).is_empty());
    let (delivery, error, attempts): (String, Option<String>, i32) = sqlx::query_as(
        "SELECT delivery, delivery_error, attempts FROM helpdesk.articles
         WHERE ticket_id = $1 AND kind = 'email_out'",
    )
    .bind(Uuid::parse_str(manual_id).unwrap())
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(delivery, "queued");
    assert_eq!(attempts, 3);
    assert!(error.unwrap().contains("MAILBOX_SECRET_SUPPORT"));

    // The mailbox was switched off after the reply was queued: the e-mail is not sent through
    // another server.
    map.remove(&general_id);
    let with_mailboxes = Transports {
        fallback: &fallback,
        mailboxes: Some(&map),
    };
    assert_eq!(
        process_outbox_with(&db, &with_mailboxes, 10).await.unwrap(),
        0
    );
    assert!(eml_files(fallback_dir.path()).is_empty());

    // Outside a live environment mailboxes are not used at all: files, whatever the mailbox.
    assert_eq!(process_outbox(&db, &fallback, 10).await.unwrap(), 1);
    let files = eml_files(fallback_dir.path());
    assert_eq!(files.len(), 1);
    assert!(files[0].contains("<info@example.com>"), "{}", files[0]);

    // System mail is sent from the default mailbox, through its transport.
    let mut conn = db.acquire().await.unwrap();
    tradocraft_core::mail::enqueue(&mut conn, company, "bob@alpha.example", "Your link", "body")
        .await
        .unwrap();
    map.insert(
        general_id,
        Ok(Mailer::Files(general_dir.path().to_path_buf())),
    );
    let with_mailboxes = Transports {
        fallback: &fallback,
        mailboxes: Some(&map),
    };
    assert_eq!(
        process_system_mail_with(&db, &with_mailboxes, 10)
            .await
            .unwrap(),
        1
    );
    let system = eml_files(general_dir.path());
    assert_eq!(system.len(), 1);
    assert!(system[0].contains("<info@example.com>"), "{}", system[0]);

    // Removing the mailbox keeps the ticket; its next reply leaves through the default.
    let (status, _) = call(
        &app,
        ADMIN,
        Method::DELETE,
        &format!("/api/v1/helpdesk/mailboxes/{parts_id}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    let (status, t) = call(
        &app,
        SUPPORT,
        Method::POST,
        &format!("/api/v1/tickets/{}/replies", r.ticket_id),
        Some(json!({ "body": "Shipped." })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{t}");
    assert_eq!(
        t["articles"].as_array().unwrap().last().unwrap()["from_address"],
        "info@example.com"
    );
}

// --- Microsoft Graph stand-in ------------------------------------------------------------------

#[derive(Default)]
struct Fake {
    /// The address the stand-in listens on, for next links.
    base: String,
    token_requests: usize,
    last_token_form: String,
    /// Unread messages: id -> raw MIME.
    inbox: Vec<(String, Vec<u8>)>,
    marked_read: Vec<String>,
    drafts: Vec<Vec<u8>>,
    sent: Vec<String>,
    deleted: Vec<String>,
    fail_send: bool,
    throttle_list: bool,
    bad_auth: bool,
}

type Shared = Arc<Mutex<Fake>>;

fn authorized(headers: &HeaderMap) -> bool {
    headers
        .get("authorization")
        .and_then(|v| v.to_str().ok())
        .is_some_and(|v| v == "Bearer token-1")
}

async fn fake_token(
    State(s): State<Shared>,
    Path(tenant): Path<String>,
    body: String,
) -> (StatusCode, Json<Value>) {
    let mut f = s.lock().unwrap();
    f.token_requests += 1;
    f.last_token_form = body.clone();
    if tenant != "contoso.onmicrosoft.com" || !body.contains("client_secret=s3cret-value") {
        return (
            StatusCode::UNAUTHORIZED,
            Json(json!({ "error": "invalid_client",
                         "error_description": "AADSTS7000215: Invalid client secret provided.\r\nTrace ID: x" })),
        );
    }
    (
        StatusCode::OK,
        Json(json!({ "token_type": "Bearer", "expires_in": 3599, "access_token": "token-1" })),
    )
}

async fn fake_list(
    State(s): State<Shared>,
    Path(user): Path<String>,
    headers: HeaderMap,
    uri: axum::http::Uri,
) -> (StatusCode, HeaderMap, Json<Value>) {
    let f = s.lock().unwrap();
    let mut out = HeaderMap::new();
    if f.throttle_list {
        out.insert("retry-after", "30".parse().unwrap());
        return (
            StatusCode::TOO_MANY_REQUESTS,
            out,
            Json(json!({ "error": { "code": "TooManyRequests", "message": "Too many requests" } })),
        );
    }
    if !authorized(&headers) || f.bad_auth {
        return (
            StatusCode::UNAUTHORIZED,
            out,
            Json(
                json!({ "error": { "code": "InvalidAuthenticationToken", "message": "Access token is empty." } }),
            ),
        );
    }
    assert_eq!(user, "support@contoso.example");
    let query = uri.query().unwrap_or_default().to_string();
    assert!(query.contains("isRead%20eq%20false"), "{query}");
    // Two pages: the first message, then the rest.
    let second = query.contains("page=2");
    let ids: Vec<Value> = f
        .inbox
        .iter()
        .filter(|(id, _)| !f.marked_read.contains(id))
        .enumerate()
        .filter(|(i, _)| (*i == 0) != second)
        .map(|(_, (id, _))| json!({ "id": id }))
        .collect();
    let mut page = json!({ "value": ids });
    if !second {
        page["@odata.nextLink"] = json!(format!(
            "{}/v1.0/users/{user}/mailFolders/inbox/messages?$filter=isRead%20eq%20false&page=2",
            f.base
        ));
    }
    (StatusCode::OK, out, Json(page))
}

async fn fake_mime(
    State(s): State<Shared>,
    Path((_, id)): Path<(String, String)>,
    headers: HeaderMap,
) -> (StatusCode, Vec<u8>) {
    assert!(authorized(&headers));
    let f = s.lock().unwrap();
    match f.inbox.iter().find(|(i, _)| *i == id) {
        Some((_, raw)) => (StatusCode::OK, raw.clone()),
        None => (StatusCode::NOT_FOUND, Vec::new()),
    }
}

async fn fake_patch(
    State(s): State<Shared>,
    Path((_, id)): Path<(String, String)>,
    Json(body): Json<Value>,
) -> Json<Value> {
    assert_eq!(body, json!({ "isRead": true }));
    s.lock().unwrap().marked_read.push(id);
    Json(json!({}))
}

async fn fake_delete(State(s): State<Shared>, Path((_, id)): Path<(String, String)>) -> StatusCode {
    s.lock().unwrap().deleted.push(id);
    StatusCode::NO_CONTENT
}

async fn fake_draft(
    State(s): State<Shared>,
    Path(user): Path<String>,
    headers: HeaderMap,
    body: Bytes,
) -> (StatusCode, Json<Value>) {
    assert!(authorized(&headers));
    assert_eq!(user, "support@contoso.example");
    assert_eq!(headers["content-type"], "text/plain");
    use base64::Engine;
    let mime = base64::engine::general_purpose::STANDARD
        .decode(&body)
        .expect("the body is base64 MIME");
    let mut f = s.lock().unwrap();
    f.drafts.push(mime);
    let n = f.drafts.len();
    (
        StatusCode::CREATED,
        Json(json!({ "id": format!("draft-{n}"),
                     "internetMessageId": format!("<EXCH-{n}@prod.outlook.com>") })),
    )
}

async fn fake_send(
    State(s): State<Shared>,
    Path((_, id)): Path<(String, String)>,
) -> (StatusCode, Json<Value>) {
    let mut f = s.lock().unwrap();
    if f.fail_send {
        return (
            StatusCode::FORBIDDEN,
            Json(
                json!({ "error": { "code": "ErrorAccessDenied", "message": "Access is denied. Check credentials and try again." } }),
            ),
        );
    }
    f.sent.push(id);
    (StatusCode::ACCEPTED, Json(json!({})))
}

/// Starts the stand-in for the sign-in service and Graph; returns its state and a client for it.
async fn fake_graph() -> (Shared, GraphClient) {
    let state: Shared = Arc::default();
    let app = axum::Router::new()
        .route("/login/{tenant}/oauth2/v2.0/token", post(fake_token))
        .route(
            "/v1.0/users/{user}/mailFolders/inbox/messages",
            get(fake_list),
        )
        .route("/v1.0/users/{user}/messages", post(fake_draft))
        .route(
            "/v1.0/users/{user}/messages/{id}",
            axum::routing::patch(fake_patch).delete(fake_delete),
        )
        .route("/v1.0/users/{user}/messages/{id}/$value", get(fake_mime))
        .route("/v1.0/users/{user}/messages/{id}/send", post(fake_send))
        .with_state(state.clone());
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let base = format!("http://{}", listener.local_addr().unwrap());
    state.lock().unwrap().base = base.clone();
    tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
    let client = GraphClient::with_urls(&format!("{base}/v1.0"), &format!("{base}/login"));
    (state, client)
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn graph_mailbox_fetches_and_sends(db: PgPool) {
    let app = setup(db.clone()).await;
    let (fake, graph) = fake_graph().await;
    let m = create(
        &app,
        with(
            graph_input("Support", "support@contoso.example"),
            json!({ "is_default": true }),
        ),
    )
    .await;
    let mailbox_id = Uuid::parse_str(m["id"].as_str().unwrap()).unwrap();
    fake.lock().unwrap().inbox = vec![
        (
            "m1".into(),
            mail(
                "anna@alpha.example",
                "support@contoso.example",
                "Pump leaks",
                "Message-ID: <g1@alpha.example>\r\n",
            ),
        ),
        ("broken".into(), Vec::new()),
        (
            "m3".into(),
            mail(
                "bob@alpha.example",
                "support@contoso.example",
                "Invoice copy",
                "Message-ID: <g3@alpha.example>\r\n",
            ),
        ),
    ];

    // Without the secret nothing is fetched and the mailbox shows why.
    let active = load_active(&db).await.unwrap();
    assert_eq!(poll_all(&db, &active, &graph, &no_secrets).await, 0);
    let status = &list(&app).await[0];
    assert!(status["last_error"]
        .as_str()
        .unwrap()
        .contains("MAILBOX_SECRET_SUPPORT"));
    assert!(status["last_poll_at"].is_string());
    assert_eq!(status["last_ok_at"], Value::Null);
    assert_eq!(fake.lock().unwrap().token_requests, 0);

    // With it: both pages are read, the two good mails become tickets and are marked read; the
    // one that cannot be ingested stays unread.
    assert_eq!(poll_all(&db, &active, &graph, &secrets).await, 2);
    {
        let f = fake.lock().unwrap();
        assert_eq!(f.marked_read, vec!["m1", "m3"]);
        assert!(f.last_token_form.contains("grant_type=client_credentials"));
        assert!(f
            .last_token_form
            .contains("scope=https%3A%2F%2Fgraph.microsoft.com%2F.default"));
    }
    let status = &list(&app).await[0];
    assert_eq!(status["last_error"], Value::Null);
    assert!(status["last_ok_at"].is_string());
    let (ticket_id, ticket_mailbox): (Uuid, Option<Uuid>) = sqlx::query_as(
        "SELECT t.id, t.mailbox_id FROM helpdesk.tickets t WHERE t.subject = 'Pump leaks'",
    )
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(ticket_mailbox, Some(mailbox_id));

    // The next pass fetches nothing new (the broken one is tried again and stays).
    assert_eq!(poll_all(&db, &active, &graph, &secrets).await, 0);
    assert_eq!(fake.lock().unwrap().marked_read.len(), 2);

    // Reply: the MIME message is handed over as a draft and sent; the Message-ID Exchange gave
    // it replaces ours.
    let (status, t) = call(
        &app,
        SUPPORT,
        Method::POST,
        &format!("/api/v1/tickets/{ticket_id}/replies"),
        Some(json!({ "body": "We send a new seal." })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{t}");
    let fallback_dir = tempfile::tempdir().unwrap();
    let fallback = Mailer::Files(fallback_dir.path().to_path_buf());
    let map = transports(&active, &graph, &secrets);
    let live = Transports {
        fallback: &fallback,
        mailboxes: Some(&map),
    };

    // Exchange refuses to send: the draft is removed, the e-mail stays queued with the reason.
    fake.lock().unwrap().fail_send = true;
    assert_eq!(process_outbox_with(&db, &live, 10).await.unwrap(), 0);
    {
        let mut f = fake.lock().unwrap();
        assert_eq!(f.deleted, vec!["draft-1"]);
        assert!(f.sent.is_empty());
        f.fail_send = false;
    }
    let error: Option<String> = sqlx::query_scalar(
        "SELECT delivery_error FROM helpdesk.articles WHERE ticket_id = $1 AND kind = 'email_out'",
    )
    .bind(ticket_id)
    .fetch_one(&db)
    .await
    .unwrap();
    let error = error.unwrap();
    assert!(
        error.contains("HTTP 403") && error.contains("Access is denied"),
        "{error}"
    );
    assert!(!error.contains("token-1") && !error.contains("s3cret-value"));

    assert_eq!(process_outbox_with(&db, &live, 10).await.unwrap(), 1);
    assert!(eml_files(fallback_dir.path()).is_empty());
    {
        let f = fake.lock().unwrap();
        assert_eq!(f.sent, vec!["draft-2"]);
        let mime = String::from_utf8_lossy(&f.drafts[1]).to_string();
        assert!(mime.contains("<support@contoso.example>"), "{mime}");
        assert!(mime.contains("In-Reply-To: <g1@alpha.example>"), "{mime}");
        assert!(mime.contains("We send a new seal."), "{mime}");
        // One sign-in for fetching and sending: the token is kept.
        assert_eq!(f.token_requests, 1);
    }
    let message_id: Option<String> = sqlx::query_scalar(
        "SELECT message_id FROM helpdesk.articles WHERE ticket_id = $1 AND kind = 'email_out'",
    )
    .bind(ticket_id)
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(message_id.as_deref(), Some("EXCH-2@prod.outlook.com"));

    // The customer's answer refers to Exchange's Message-ID and lands on the same ticket.
    fake.lock().unwrap().inbox.push((
        "m4".into(),
        mail(
            "anna@alpha.example",
            "support@contoso.example",
            "RE: something else entirely",
            "Message-ID: <g4@alpha.example>\r\nIn-Reply-To: <EXCH-2@prod.outlook.com>\r\nReferences: <EXCH-2@prod.outlook.com>\r\n",
        ),
    ));
    assert_eq!(poll_all(&db, &active, &graph, &secrets).await, 1);
    let articles: i64 =
        sqlx::query_scalar("SELECT count(*) FROM helpdesk.articles WHERE ticket_id = $1")
            .bind(ticket_id)
            .fetch_one(&db)
            .await
            .unwrap();
    assert_eq!(articles, 3);

    // Throttling and a refused sign-in are reported in plain words, without secrets.
    fake.lock().unwrap().throttle_list = true;
    assert_eq!(poll_all(&db, &active, &graph, &secrets).await, 0);
    let e = list(&app).await[0]["last_error"]
        .as_str()
        .unwrap()
        .to_string();
    assert!(
        e.contains("HTTP 429") && e.contains("retry after 30"),
        "{e}"
    );
    fake.lock().unwrap().throttle_list = false;

    // A rejected token is forgotten, so the next pass signs in again.
    fake.lock().unwrap().bad_auth = true;
    assert_eq!(poll_all(&db, &active, &graph, &secrets).await, 0);
    fake.lock().unwrap().bad_auth = false;
    assert_eq!(poll_all(&db, &active, &graph, &secrets).await, 0);
    assert_eq!(fake.lock().unwrap().token_requests, 2);
    assert_eq!(list(&app).await[0]["last_error"], Value::Null);

    let wrong = |r: &str| (r == "SUPPORT").then(|| "wrong".to_string());
    let fresh = GraphClient::with_urls(
        &format!("{}/v1.0", fake.lock().unwrap().base),
        &format!("{}/login", fake.lock().unwrap().base),
    );
    assert_eq!(poll_all(&db, &active, &fresh, &wrong).await, 0);
    let e = list(&app).await[0]["last_error"]
        .as_str()
        .unwrap()
        .to_string();
    assert!(
        e.contains("signing in to Microsoft 365") && e.contains("Invalid client secret"),
        "{e}"
    );
    assert!(!e.contains("wrong") && !e.contains("Trace ID"), "{e}");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_clone_switches_every_mailbox_off(db: PgPool) {
    let app = setup(db.clone()).await;
    create(
        &app,
        with(
            graph_input("Support", "support@contoso.example"),
            json!({ "is_default": true }),
        ),
    )
    .await;
    create(&app, imap_input("On-premises", "service@example.com")).await;
    assert_eq!(load_active(&db).await.unwrap().len(), 2);
    let scrub = std::fs::read_to_string(
        std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../scripts/envctl.d/scrub_credentials.sql"),
    )
    .unwrap();
    sqlx::raw_sql(&scrub).execute(&db).await.unwrap();
    assert!(load_active(&db).await.unwrap().is_empty());
    assert!(list(&app).await.iter().all(|m| m["is_default"] == false));
    // The settings stay, so the mailbox can be pointed at a test mailbox and switched on by hand.
    assert_eq!(list(&app).await.len(), 2);
    let _ = mailboxes::SECRET_ENV_PREFIX;
}
