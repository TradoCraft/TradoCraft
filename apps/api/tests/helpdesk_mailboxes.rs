//! Helpdesk mailboxes (ADR 0054): the settings API, routing of incoming mail to the mailbox's
//! team, replies through the ticket's mailbox, and the clone scrub. The Microsoft Graph client has
//! its own tests (`helpdesk_graph.rs`).

mod common;

use std::collections::HashMap;

use axum::http::{Method, StatusCode};
use common::graph::mail;
use common::{call, setup};
use serde_json::{json, Value};
use sqlx::PgPool;
use tradocraft_helpdesk::ingest::{ingest_from, Source};
use tradocraft_helpdesk::mailboxes::{self, load_active};
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
                json!({ "imap_tls": false }),
            ),
            "without TLS",
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
