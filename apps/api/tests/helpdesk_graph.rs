//! The Microsoft Graph client of the helpdesk mailboxes (ADR 0054) against a stand-in that keeps
//! a mailbox and holds it to Graph's contract (`common/graph.rs`): the round trip, a send that may
//! have gone, a message that cannot be fetched, answers that must not be trusted, ids, tokens,
//! threading whatever Message-ID Exchange assigns, and the live self-check.

mod common;

use std::time::Duration;

use axum::http::{Method, StatusCode};
use common::graph::{
    mail, Evil, Fault, Folder, Hostile, MessageIds, SendOutcome, Standin, CLIENT_SECRET, MAILBOX,
    TENANT,
};
use common::{call, setup};
use serde_json::{json, Value};
use sqlx::PgPool;
use tradocraft_helpdesk::graph::{CheckOptions, GraphClient, MessageIdVerdict};
use tradocraft_helpdesk::ingest::{ingest_from, Source};
use tradocraft_helpdesk::mailboxes::{
    check_graph_mailbox, load_active, poll_all, transports, SecretRequest,
};
use tradocraft_helpdesk::mailer::{process_outbox_with, Mailer, Transports};
use uuid::Uuid;

const COMPANY: &str = "00000000-0000-7000-8000-000000000001";
const ADMIN: &str = "admin@example.com";
const SUPPORT: &str = "support@example.com";
const ANNA: &str = "anna@alpha.example";

fn secrets(req: &SecretRequest<'_>) -> Option<String> {
    (req.reference == "SUPPORT").then(|| CLIENT_SECRET.to_string())
}

fn wrong_secret(req: &SecretRequest<'_>) -> Option<String> {
    (req.reference == "SUPPORT").then(|| "wrong".to_string())
}

fn no_secrets(_: &SecretRequest<'_>) -> Option<String> {
    None
}

struct World {
    app: axum::Router,
    db: PgPool,
    standin: Standin,
    graph: GraphClient,
    mailbox_id: Uuid,
    fallback: tempfile::TempDir,
}

/// A company with one Microsoft 365 mailbox (the default one) that talks to the stand-in.
async fn world(db: PgPool, timeout: Option<Duration>) -> World {
    let app = setup(db.clone()).await;
    let standin = Standin::start().await;
    let (status, m) = call(
        &app,
        ADMIN,
        Method::POST,
        "/api/v1/helpdesk/mailboxes",
        Some(json!({
            "name": "Support", "address": MAILBOX, "kind": "graph", "secret_ref": "SUPPORT",
            "is_default": true, "tenant_id": TENANT,
            "client_id": "11111111-2222-3333-4444-555555555555",
        })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{m}");
    let mut graph = standin.client();
    if let Some(t) = timeout {
        graph = graph.with_timeout(t);
    }
    World {
        app,
        db,
        standin,
        graph,
        mailbox_id: Uuid::parse_str(m["id"].as_str().unwrap()).unwrap(),
        fallback: tempfile::tempdir().unwrap(),
    }
}

impl World {
    /// An unread e-mail from a customer, waiting in the mailbox.
    fn unread(&self, key: &str, subject: &str, message_id: &str) {
        self.standin.state().add_unread(
            key,
            mail(
                ANNA,
                MAILBOX,
                subject,
                &format!("Message-ID: <{message_id}>\r\n"),
            ),
        );
    }

    /// One pass of the worker over the mailboxes; the number of e-mails ingested.
    async fn pass(&self) -> usize {
        let active = load_active(&self.db).await.unwrap();
        poll_all(&self.db, &active, &self.graph, &secrets).await
    }

    /// One pass of the worker over the outbox; the number of e-mails sent.
    async fn outbox(&self) -> usize {
        self.outbox_with(&self.graph).await
    }

    async fn outbox_with(&self, graph: &GraphClient) -> usize {
        let active = load_active(&self.db).await.unwrap();
        let map = transports(&active, graph, &secrets);
        let fallback = Mailer::Files(self.fallback.path().to_path_buf());
        let t = Transports {
            fallback: &fallback,
            mailboxes: Some(&map),
        };
        process_outbox_with(&self.db, &t, 10).await.unwrap()
    }

    async fn status(&self) -> Value {
        let (status, l) = call(
            &self.app,
            ADMIN,
            Method::GET,
            "/api/v1/helpdesk/mailboxes",
            None,
        )
        .await;
        assert_eq!(status, StatusCode::OK, "{l}");
        l[0].clone()
    }

    async fn error(&self) -> String {
        self.status().await["last_error"]
            .as_str()
            .unwrap_or_default()
            .to_string()
    }

    /// A ticket that came in on the mailbox, with a reply queued on it.
    async fn queue_reply(&self, subject: &str, message_id: &str) -> Uuid {
        let r = ingest_from(
            &self.db,
            Uuid::parse_str(COMPANY).unwrap(),
            &mail(
                ANNA,
                MAILBOX,
                subject,
                &format!("Message-ID: <{message_id}>\r\n"),
            ),
            Some(Source {
                mailbox_id: self.mailbox_id,
                team_id: None,
            }),
        )
        .await
        .unwrap();
        let (status, t) = call(
            &self.app,
            SUPPORT,
            Method::POST,
            &format!("/api/v1/tickets/{}/replies", r.ticket_id),
            Some(json!({ "body": "We send a new seal." })),
        )
        .await;
        assert_eq!(status, StatusCode::CREATED, "{t}");
        r.ticket_id
    }

    /// Delivery state, attempts, reason and Message-ID of the reply of a ticket.
    async fn reply_state(&self, ticket: Uuid) -> (String, i32, Option<String>, Option<String>) {
        sqlx::query_as(
            "SELECT delivery, attempts, delivery_error, message_id FROM helpdesk.articles
             WHERE ticket_id = $1 AND kind = 'email_out'",
        )
        .bind(ticket)
        .fetch_one(&self.db)
        .await
        .unwrap()
    }

    async fn count(&self, sql: &str) -> i64 {
        sqlx::query_scalar(sql).fetch_one(&self.db).await.unwrap()
    }
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn graph_mailbox_fetches_and_sends(db: PgPool) {
    let w = world(db, None).await;
    w.standin.state().page_size = 1;
    w.unread("m1", "Pump leaks", "g1@alpha.example");
    w.standin.state().add_unread("broken", Vec::new());
    w.unread("m3", "Invoice copy", "g3@alpha.example");

    // Without the secret nothing is fetched, and the mailbox says why.
    let active = load_active(&w.db).await.unwrap();
    assert_eq!(poll_all(&w.db, &active, &w.graph, &no_secrets).await, 0);
    let status = w.status().await;
    assert!(status["last_error"]
        .as_str()
        .unwrap()
        .contains("MAILBOX_SECRET_SUPPORT"));
    assert!(status["last_poll_at"].is_string());
    assert_eq!(status["last_ok_at"], Value::Null);
    assert_eq!(w.standin.state().token_requests, 0);

    // With it: every page is read, the two good mails become tickets and are marked read; the one
    // that cannot be ingested stays unread and is reported.
    assert_eq!(w.pass().await, 2);
    assert_eq!(w.standin.state().read_marks, vec!["m1", "m3"]);
    {
        let s = w.standin.state();
        assert!(s.last_token_form.contains("grant_type=client_credentials"));
        assert!(s
            .last_token_form
            .contains("scope=https%3A%2F%2Fgraph.microsoft.com%2F.default"));
    }
    let status = w.status().await;
    assert!(status["last_error"]
        .as_str()
        .unwrap()
        .contains("could not be turned into a ticket"));
    assert!(status["last_ok_at"].is_string(), "the pass reached its end");
    let (ticket_id, ticket_mailbox): (Uuid, Option<Uuid>) =
        sqlx::query_as("SELECT id, mailbox_id FROM helpdesk.tickets WHERE subject = 'Pump leaks'")
            .fetch_one(&w.db)
            .await
            .unwrap();
    assert_eq!(ticket_mailbox, Some(w.mailbox_id));

    // The next pass fetches nothing new: the broken one is tried again and stays.
    assert_eq!(w.pass().await, 0);
    assert_eq!(w.standin.state().read_marks.len(), 2);

    // Reply: Exchange refuses at first, so the draft is removed and the e-mail stays queued with
    // the reason; then it goes.
    let (status, t) = call(
        &w.app,
        SUPPORT,
        Method::POST,
        &format!("/api/v1/tickets/{ticket_id}/replies"),
        Some(json!({ "body": "We send a new seal." })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{t}");
    w.standin
        .state()
        .fail_next
        .push(("send".into(), 403, "ErrorAccessDenied".into()));
    assert_eq!(w.outbox().await, 0);
    {
        let s = w.standin.state();
        assert_eq!(s.sent_count(), 0);
        assert!(
            s.in_folder(Folder::Drafts).is_empty(),
            "the refused draft was removed"
        );
    }
    let (delivery, attempts, error, _) = w.reply_state(ticket_id).await;
    assert_eq!((delivery.as_str(), attempts), ("queued", 1));
    let error = error.unwrap();
    assert!(
        error.contains("HTTP 403") && error.contains("Access is denied"),
        "{error}"
    );
    assert!(!error.contains("token-") && !error.contains(CLIENT_SECRET));

    assert_eq!(w.outbox().await, 1);
    assert!(std::fs::read_dir(w.fallback.path())
        .unwrap()
        .next()
        .is_none());
    let (delivery, _, _, message_id) = w.reply_state(ticket_id).await;
    assert_eq!(delivery, "sent");
    let sent_id = {
        let s = w.standin.state();
        let mime = String::from_utf8_lossy(&s.sent_mimes[0]).to_string();
        assert!(mime.contains(&format!("<{MAILBOX}>")), "{mime}");
        assert!(mime.contains("In-Reply-To: <g1@alpha.example>"), "{mime}");
        assert!(mime.contains("We send a new seal."), "{mime}");
        s.in_folder(Folder::SentItems)[0].internet_id.clone()
    };
    // The Message-ID Exchange gave the draft replaces ours: it is what replies will cite.
    let message_id = message_id.unwrap();
    assert!(message_id.starts_with("EXCH-") && message_id.ends_with("@prod.outlook.com"));
    assert_eq!(format!("<{message_id}>"), sent_id);

    // The customer's answer cites it and lands on the same ticket, whatever its subject says.
    w.standin.state().add_unread(
        "m4",
        mail(
            ANNA,
            MAILBOX,
            "RE: something else entirely",
            &format!("Message-ID: <g4@alpha.example>\r\nIn-Reply-To: {sent_id}\r\nReferences: {sent_id}\r\n"),
        ),
    );
    assert_eq!(w.pass().await, 1);
    assert_eq!(
        w.count(&format!(
            "SELECT count(*) FROM helpdesk.articles WHERE ticket_id = '{ticket_id}'"
        ))
        .await,
        3
    );

    // A busy answer is reported in plain words with when to come back, and the pass stops.
    w.standin
        .state()
        .fail_next
        .push(("list".into(), 429, "TooManyRequests".into()));
    assert_eq!(w.pass().await, 0);
    let e = w.error().await;
    assert!(
        e.contains("HTTP 429") && e.contains("retry after 30"),
        "{e}"
    );

    // A refused sign-in says so, without the secret or Microsoft's trace id.
    let active = load_active(&w.db).await.unwrap();
    let fresh = w.standin.client();
    assert_eq!(poll_all(&w.db, &active, &fresh, &wrong_secret).await, 0);
    let e = w.error().await;
    assert!(
        e.contains("signing in to Microsoft 365") && e.contains("Invalid client secret"),
        "{e}"
    );
    assert!(!e.contains("wrong") && !e.contains("Trace ID"), "{e}");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_send_that_may_have_gone_is_never_repeated(db: PgPool) {
    let w = world(db, None).await;

    // The gateway gives up after the message went: the draft is gone, so it was sent. Once.
    w.standin.state().send_outcome = SendOutcome::GatewayTimeoutAfter;
    let a = w.queue_reply("Pump leaks", "a1@alpha.example").await;
    assert_eq!(w.outbox().await, 1);
    assert_eq!(w.standin.state().sent_count(), 1);
    assert_eq!(w.reply_state(a).await.0, "sent");
    assert_eq!(w.outbox().await, 0);
    assert_eq!(w.standin.state().sent_count(), 1);

    // The answer comes after the client gave up waiting: the same. Only this step uses a short
    // timeout, so a busy machine cannot make the other requests of the test time out.
    w.standin.state().send_outcome = SendOutcome::SlowAfter(Duration::from_secs(5));
    let b = w.queue_reply("Seal kit", "b1@alpha.example").await;
    let impatient = w
        .standin
        .client()
        .with_timeout(Duration::from_millis(1_500));
    assert_eq!(w.outbox_with(&impatient).await, 1);
    assert_eq!(w.standin.state().sent_count(), 2);
    assert_eq!(w.reply_state(b).await.0, "sent");

    // The gateway gives up and the draft is still there. That does not show the message was not
    // sent (transport may pick it up after the look), so it is not tried again: the draft is
    // removed so it cannot go out later, and the e-mail is marked failed with the reason.
    w.standin.state().send_outcome = SendOutcome::GatewayTimeoutBefore;
    let c = w.queue_reply("Invoice copy", "c1@alpha.example").await;
    assert_eq!(w.outbox().await, 0);
    {
        let s = w.standin.state();
        assert_eq!(s.sent_count(), 2);
        assert!(s.in_folder(Folder::Drafts).is_empty());
    }
    let (delivery, attempts, error, _) = w.reply_state(c).await;
    assert_eq!((delivery.as_str(), attempts), ("failed", 1), "{error:?}");
    assert!(error.unwrap().contains("HTTP 504"));
    w.standin.state().send_outcome = SendOutcome::Normal;
    assert_eq!(w.outbox().await, 0);
    assert_eq!(w.standin.state().sent_count(), 2);

    // Nobody can tell: the message went, the answer was lost, and the draft cannot be looked up
    // either. The e-mail is marked failed with a reason, not tried again (that could send it twice).
    w.standin.state().send_outcome = SendOutcome::GatewayTimeoutAfter;
    w.standin
        .state()
        .fail_next
        .push(("get".into(), 500, "ErrorInternalServerError".into()));
    let d = w.queue_reply("Warranty", "d1@alpha.example").await;
    assert_eq!(w.outbox().await, 0);
    assert_eq!(w.standin.state().sent_count(), 3);
    let (delivery, attempts, error, _) = w.reply_state(d).await;
    assert_eq!((delivery.as_str(), attempts), ("failed", 1), "{error:?}");
    assert!(error.unwrap().contains("Sent Items"));
    assert_eq!(w.outbox().await, 0);
    assert_eq!(w.standin.state().sent_count(), 3);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn one_message_that_cannot_be_fetched_does_not_stop_the_others(db: PgPool) {
    let w = world(db, None).await;
    for (key, n) in [("m1", 1), ("m2", 2), ("m3", 3), ("m4", 4), ("m5", 5)] {
        w.unread(
            key,
            &format!("Question {n}"),
            &format!("g{n}@alpha.example"),
        );
    }
    {
        let mut s = w.standin.state();
        s.faults.insert("m2".into(), Fault::Gone);
        s.faults.insert("m3".into(), Fault::Denied);
        s.faults.insert("m4".into(), Fault::Invalid);
    }
    // Gone, forbidden and invalid are about the message: the others are fetched.
    assert_eq!(w.pass().await, 2);
    assert_eq!(w.standin.state().read_marks, vec!["m1", "m5"]);
    let e = w.error().await;
    assert!(e.contains("could not be downloaded"), "{e}");
    assert!(e.contains("HTTP 404") && e.contains("HTTP 403"), "{e}");
    let ok_before = w.status().await["last_ok_at"].clone();
    assert!(ok_before.is_string(), "a pass that reached its end is ok");

    // Once the server lets them through, the next pass has them; the error is gone.
    w.standin.state().faults.clear();
    assert_eq!(w.pass().await, 3);
    assert_eq!(w.error().await, "");

    // Busy: the pass stops where it is, says when to come back, and picks up from there.
    for (key, n) in [("m6", 6), ("m7", 7), ("m8", 8)] {
        w.unread(
            key,
            &format!("Question {n}"),
            &format!("g{n}@alpha.example"),
        );
    }
    w.standin
        .state()
        .faults
        .insert("m7".into(), Fault::Throttled(1));
    let ok_before = w.status().await["last_ok_at"].clone();
    assert_eq!(w.pass().await, 1);
    let e = w.error().await;
    assert!(
        e.contains("HTTP 429") && e.contains("retry after 30"),
        "{e}"
    );
    assert_eq!(
        w.status().await["last_ok_at"],
        ok_before,
        "a stopped pass is not ok"
    );
    assert!(
        !w.standin.state().is_read("m8"),
        "m8 waits for the next pass"
    );
    assert_eq!(w.pass().await, 2);
    assert_eq!(w.error().await, "");

    // A refused token stops the pass and is forgotten: the next pass signs in again.
    w.unread("m9", "Question 9", "g9@alpha.example");
    w.unread("m10", "Question 10", "g10@alpha.example");
    let signed_in = w.standin.state().token_requests;
    w.standin
        .state()
        .fail_next
        .push(("value".into(), 401, "InvalidAuthenticationToken".into()));
    assert_eq!(w.pass().await, 0);
    assert!(w.error().await.contains("HTTP 401"));
    assert_eq!(w.pass().await, 2);
    assert_eq!(w.standin.state().token_requests, signed_in + 1);

    // A server error stops the pass too: it says nothing about the message.
    w.unread("m11", "Question 11", "g11@alpha.example");
    w.unread("m12", "Question 12", "g12@alpha.example");
    w.standin
        .state()
        .fail_next
        .push(("value".into(), 500, "ErrorInternalServerError".into()));
    assert_eq!(w.pass().await, 0);
    assert!(w.error().await.contains("HTTP 500"));
    assert_eq!(w.pass().await, 2);
    assert_eq!(w.error().await, "");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn answers_from_graph_are_not_trusted(db: PgPool) {
    let w = world(db, None).await;
    let evil = Evil::start().await;

    // A message over the limit stays unread and is reported; the one after it is fetched.
    let mut big = mail(ANNA, MAILBOX, "Huge", "Message-ID: <big@alpha.example>\r\n");
    big.extend(std::iter::repeat_n(b'A', 36 * 1024 * 1024));
    w.standin.state().add_unread("big", big);
    w.unread("ok1", "Normal", "ok1@alpha.example");
    assert_eq!(w.pass().await, 1);
    assert!(w.error().await.contains("larger than 35 MB"));
    {
        let s = w.standin.state();
        assert!(s.is_read("ok1") && !s.is_read("big"));
    }
    w.standin.state().messages.retain(|m| m.key != "big");

    // An id of 5,000 characters is not used.
    w.unread("long", "Long id", "long@alpha.example");
    w.unread("ok2", "Normal 2", "ok2@alpha.example");
    w.standin.state().hostile = Hostile::HugeId("long".into());
    assert_eq!(w.pass().await, 1);
    assert!(w.error().await.contains("id that is too long"));
    w.standin.state().hostile = Hostile::None;
    w.standin.state().messages.retain(|m| m.key != "long");

    // A next page at another address is not followed: nothing, and no token, reaches it.
    w.standin.state().page_size = 1;
    w.unread("n1", "Next 1", "n1@alpha.example");
    w.unread("n2", "Next 2", "n2@alpha.example");
    w.standin.state().hostile = Hostile::NextLink(format!(
        "{}/v1.0/users/{MAILBOX}/mailFolders/inbox/messages?$skiptoken=1",
        evil.base
    ));
    assert_eq!(w.pass().await, 1, "the first page is still taken");
    assert!(w.error().await.contains("another address"));
    assert_eq!(evil.count(), 0);
    w.standin.state().hostile = Hostile::None;
    assert_eq!(w.pass().await, 1, "the rest comes on the next pass");

    // A redirect is not followed.
    w.unread("r1", "Redirected", "r1@alpha.example");
    w.standin.state().hostile = Hostile::Redirect(format!("{}/steal", evil.base));
    assert_eq!(w.pass().await, 0);
    assert!(w.error().await.contains("HTTP 302"));
    assert_eq!(evil.count(), 0, "{:?}", evil.hits.lock().unwrap());
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn ids_are_written_into_addresses_as_one_piece(db: PgPool) {
    let w = world(db, None).await;
    let key = "AAMk/ab+c?d=1#e f";
    w.unread(key, "Odd id", "odd@alpha.example");
    assert_eq!(w.pass().await, 1);
    assert_eq!(w.error().await, "");
    let encoded = "AAMk%2Fab%2Bc%3Fd%3D1%23e%20f";
    let s = w.standin.state();
    assert!(s.is_read(key));
    assert!(s
        .requests
        .iter()
        .any(|r| r.method == "GET" && r.path.ends_with(&format!("/messages/{encoded}/$value"))));
    assert!(s
        .requests
        .iter()
        .any(|r| r.method == "PATCH" && r.path.ends_with(&format!("/messages/{encoded}"))));
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn immutable_ids_survive_a_move_between_listing_and_fetching(db: PgPool) {
    let w = world(db, None).await;
    w.unread("m1", "One", "i1@alpha.example");
    w.unread("m2", "Two", "i2@alpha.example");
    // Every listing renames the messages, as moving them to another folder would.
    w.standin.state().rotate_ids_after_list = true;
    assert_eq!(w.pass().await, 2);
    assert_eq!(w.error().await, "");
    let s = w.standin.state();
    let graph: Vec<_> = s
        .requests
        .iter()
        .filter(|r| r.path.starts_with("/v1.0/"))
        .collect();
    assert!(graph.len() >= 5);
    assert!(
        graph.iter().all(|r| r
            .prefer
            .as_deref()
            .is_some_and(|p| p.contains("IdType=\"ImmutableId\""))),
        "{graph:?}"
    );
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn tokens_are_reused_renewed_and_replaced(db: PgPool) {
    let w = world(db, None).await;
    // A token that lives 121 s is renewed 120 s before it expires: it is good for one second.
    w.standin.state().expires_in = 121;
    w.unread("m1", "One", "t1@alpha.example");
    assert_eq!(w.pass().await, 1);
    w.unread("m2", "Two", "t2@alpha.example");
    assert_eq!(w.pass().await, 1);
    assert_eq!(w.standin.state().token_requests, 1, "the token is reused");
    tokio::time::sleep(Duration::from_millis(1_200)).await;
    w.unread("m3", "Three", "t3@alpha.example");
    assert_eq!(w.pass().await, 1);
    assert_eq!(
        w.standin.state().token_requests,
        2,
        "and renewed when it runs out"
    );

    // A token Graph stops accepting (revoked, or the secret was rotated) is replaced.
    w.standin.state().expires_in = 3599;
    w.standin.state().revoke_tokens();
    w.unread("m4", "Four", "t4@alpha.example");
    assert_eq!(w.pass().await, 0);
    assert!(w.error().await.contains("HTTP 401"));
    assert_eq!(w.pass().await, 1);
    assert_eq!(w.standin.state().token_requests, 3);
    assert_eq!(w.error().await, "");

    // A busy sign-in service is reported as that.
    w.standin.state().revoke_tokens();
    w.standin.state().token_failures.push((
        429,
        json!({ "error": "temporarily_unavailable", "error_description": "AADSTS90033: busy" }),
    ));
    w.unread("m5", "Five", "t5@alpha.example");
    assert_eq!(w.pass().await, 0);
    // (The first call finds the old token refused, the second asks for a new one and is told to wait.)
    assert_eq!(w.pass().await, 0);
    assert!(w
        .error()
        .await
        .contains("signing in to Microsoft 365: HTTP 429"));
    assert_eq!(w.pass().await, 1);
}

/// A customer's answer to a reply after it has been through the stand-in with `mode`. Returns the
/// number of tickets afterwards.
async fn answer_after(db: PgPool, mode: MessageIds, keep_ticket_number: bool) -> i64 {
    let w = world(db, None).await;
    w.standin.state().ids = mode;
    w.unread("c1", "Pump leaks", "c1@alpha.example");
    assert_eq!(w.pass().await, 1);
    let ticket: Uuid = sqlx::query_scalar("SELECT id FROM helpdesk.tickets")
        .fetch_one(&w.db)
        .await
        .unwrap();
    let (status, t) = call(
        &w.app,
        SUPPORT,
        Method::POST,
        &format!("/api/v1/tickets/{ticket}/replies"),
        Some(json!({ "body": "We send a new seal." })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{t}");
    assert_eq!(w.outbox().await, 1);
    // What the customer receives is what is in Sent Items: its Message-ID and its subject.
    let (cited, sent_subject) = {
        let s = w.standin.state();
        let copy = s.in_folder(Folder::SentItems)[0];
        (copy.internet_id.clone(), copy.subject.clone())
    };
    let subject = if keep_ticket_number {
        format!("Re: {sent_subject}")
    } else {
        "Another question".to_string()
    };
    w.standin.state().add_unread(
        "c2",
        mail(
            ANNA,
            MAILBOX,
            &subject,
            &format!(
                "Message-ID: <c2@alpha.example>\r\nIn-Reply-To: {cited}\r\nReferences: {cited}\r\n"
            ),
        ),
    );
    assert_eq!(w.pass().await, 1);
    w.count("SELECT count(*) FROM helpdesk.tickets").await
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn an_answer_threads_when_exchange_keeps_the_message_id(db: PgPool) {
    assert_eq!(answer_after(db, MessageIds::Kept, false).await, 1);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn an_answer_threads_when_exchange_assigns_one_to_the_draft(db: PgPool) {
    assert_eq!(
        answer_after(db, MessageIds::AssignedAtDraft, false).await,
        1
    );
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn an_answer_threads_by_ticket_number_when_the_id_changes_at_send(db: PgPool) {
    assert_eq!(answer_after(db, MessageIds::ChangedAtSend, true).await, 1);
}

/// The one case the helpdesk cannot thread: Exchange changes the Message-ID when the message is
/// sent AND the customer's answer loses the ticket number from the subject. `check-mailbox` tells
/// an administrator whether their tenant does this.
#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_changed_id_and_a_lost_ticket_number_start_a_new_ticket(db: PgPool) {
    assert_eq!(answer_after(db, MessageIds::ChangedAtSend, false).await, 2);
}

fn quick() -> CheckOptions {
    CheckOptions {
        tries: 3,
        delay: Duration::ZERO,
    }
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_check_reports_what_exchange_does_with_the_message_id(db: PgPool) {
    let w = world(db, None).await;
    for (mode, verdict) in [
        (MessageIds::Kept, MessageIdVerdict::Kept),
        (
            MessageIds::AssignedAtDraft,
            MessageIdVerdict::ReplacedAtDraft,
        ),
        (MessageIds::ChangedAtSend, MessageIdVerdict::ReplacedAtSend),
    ] {
        w.standin.state().ids = mode;
        let report = check_graph_mailbox(&w.db, "support", &w.graph, &secrets, &quick())
            .await
            .unwrap();
        assert!(report.ok(), "{mode:?}: {:#?}", report.lines());
        assert_eq!(report.verdict, Some(verdict), "{mode:?}");
        let lines = report.lines().join("\n");
        assert!(lines.contains("ok   sign in"), "{lines}");
        assert!(
            lines.contains("the query the worker uses for unread mail"),
            "{lines}"
        );
        assert!(
            lines.contains("find the delivered copy in the inbox"),
            "{lines}"
        );
        assert!(lines.contains("Message-ID: "), "{lines}");
        assert!(!lines.contains(CLIENT_SECRET) && !lines.contains("token-"));
        if verdict == MessageIdVerdict::ReplacedAtSend {
            assert!(lines.contains("WARNING"), "{lines}");
        }
    }
    // The test mail is gone again: copies moved to Deleted Items, no draft left.
    let s = w.standin.state();
    assert!(s.in_folder(Folder::Inbox).is_empty());
    assert!(s.in_folder(Folder::SentItems).is_empty());
    assert!(s.in_folder(Folder::Drafts).is_empty());
    assert_eq!(s.in_folder(Folder::Deleted).len(), 6);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_check_says_where_it_fails_and_cleans_up(db: PgPool) {
    let w = world(db, None).await;

    // A wrong secret stops at the sign-in.
    let report = check_graph_mailbox(&w.db, "Support", &w.graph, &wrong_secret, &quick())
        .await
        .unwrap();
    assert!(!report.ok());
    assert_eq!(report.steps.len(), 1);
    let lines = report.lines().join("\n");
    assert!(
        lines.contains("FAIL sign in") && lines.contains("Invalid client secret"),
        "{lines}"
    );
    assert!(!lines.contains("wrong"));

    // A refusal to send is reported at that step, and the draft is removed.
    w.standin
        .state()
        .fail_next
        .push(("send".into(), 403, "ErrorSendAsDenied".into()));
    let report = check_graph_mailbox(&w.db, "Support", &w.graph, &secrets, &quick())
        .await
        .unwrap();
    assert!(!report.ok());
    let last = report.steps.last().unwrap();
    assert_eq!(last.name, "send the draft");
    assert!(last.detail.contains("HTTP 403"), "{}", last.detail);
    assert!(w.standin.state().in_folder(Folder::Drafts).is_empty());

    // A query the tenant would refuse is reported at that step.
    w.standin
        .state()
        .fail_next
        .push(("list".into(), 400, "BadRequest".into()));
    let report = check_graph_mailbox(&w.db, "Support", &w.graph, &secrets, &quick())
        .await
        .unwrap();
    assert!(!report.ok());
    assert_eq!(
        report.steps.last().unwrap().name,
        "the query the worker uses for unread mail"
    );

    // Names that are not Microsoft 365 mailboxes are refused before anything is sent.
    let e = check_graph_mailbox(&w.db, "Nobody", &w.graph, &secrets, &quick())
        .await
        .unwrap_err();
    assert!(
        e.to_string().contains("no active mailbox") && e.to_string().contains("Support"),
        "{e}"
    );
    let (status, m) = call(
        &w.app,
        ADMIN,
        Method::POST,
        "/api/v1/helpdesk/mailboxes",
        Some(json!({ "name": "On-premises", "address": "service@example.com", "kind": "imap_smtp",
                     "secret_ref": "ONPREM", "username": "helpdesk", "imap_host": "mail.example.com",
                     "smtp_host": "mail.example.com" })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{m}");
    let e = check_graph_mailbox(&w.db, "On-premises", &w.graph, &secrets, &quick())
        .await
        .unwrap_err();
    assert!(e.to_string().contains("IMAP/SMTP"), "{e}");
    assert_eq!(w.standin.state().sent_count(), 0);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_check_cleans_up_after_a_send_whose_answer_was_lost(db: PgPool) {
    let w = world(db, None).await;
    // The message went, the answer did not come: the step fails, but the copies are found and
    // removed all the same.
    w.standin.state().send_outcome = SendOutcome::GatewayTimeoutAfter;
    let report = check_graph_mailbox(&w.db, "Support", &w.graph, &secrets, &quick())
        .await
        .unwrap();
    assert!(!report.ok());
    assert!(
        report
            .steps
            .iter()
            .any(|s| s.name == "send the draft" && !s.ok),
        "{:#?}",
        report.lines()
    );
    let s = w.standin.state();
    assert!(s.in_folder(Folder::Inbox).is_empty());
    assert!(s.in_folder(Folder::SentItems).is_empty());
    assert!(s.in_folder(Folder::Drafts).is_empty());
    assert_eq!(s.in_folder(Folder::Deleted).len(), 2);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_check_fails_when_exchange_gives_the_draft_no_message_id(db: PgPool) {
    let w = world(db, None).await;
    w.standin.state().ids = MessageIds::MissingAtDraft;
    let report = check_graph_mailbox(&w.db, "Support", &w.graph, &secrets, &quick())
        .await
        .unwrap();
    assert!(!report.ok(), "{:#?}", report.lines());
    assert_eq!(report.verdict, None);
    assert!(
        report.steps.iter().any(|s| s.name == "Message-ID" && !s.ok),
        "{:#?}",
        report.lines()
    );
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_check_refuses_a_name_two_companies_share(db: PgPool) {
    let w = world(db, None).await;
    let other = Uuid::now_v7();
    sqlx::query("INSERT INTO core.companies (id, name, country_code, currency) VALUES ($1, 'Other BV', 'BE', 'EUR')")
        .bind(other)
        .execute(&w.db)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO helpdesk.mailboxes (id, company_id, name, address, kind, secret_ref, tenant_id, client_id, is_default)
         SELECT gen_random_uuid(), $1, name, 'support@other.example', kind, 'OTHER', tenant_id, client_id, true
         FROM helpdesk.mailboxes",
    )
    .bind(other)
    .execute(&w.db)
    .await
    .unwrap();
    let e = check_graph_mailbox(&w.db, "support", &w.graph, &secrets, &quick())
        .await
        .unwrap_err();
    assert!(e.to_string().contains("more than one"), "{e}");
    assert_eq!(w.standin.state().sent_count(), 0);
}
