//! Customer portal: passwordless login, what a customer may see, and revocation.

mod common;

use axum::http::{Method, StatusCode};
use common::{call, call_portal, setup};
use serde_json::{json, Value};
use sqlx::PgPool;
use tradocraft_helpdesk::mailer::{process_system_mail, Mailer};

const COMPANY: &str = "00000000-0000-7000-8000-000000000001";
const JAN: &str = "jan.peeters@alpha.example"; // Alpha, nl, formal, scope customer
const SOFIE: &str = "sofie.maes@alpha.example"; // Alpha, nl, informal, scope own
const MARIE: &str = "marie.dupont@beta.example"; // Beta, fr
const HANS: &str = "hans.mueller@gamma.example"; // no portal access
const JAN_ID: &str = "00000000-0000-7000-8000-000000000601";
const SOFIE_ID: &str = "00000000-0000-7000-8000-000000000602";
const ALPHA: &str = "00000000-0000-7000-8000-000000000401";
const SUPPORT: &str = "support@example.com";

async fn request_link(app: &axum::Router, email: &str) -> StatusCode {
    call_portal(
        app,
        None,
        Method::POST,
        "/api/v1/portal/login-links",
        Some(json!({ "company_id": COMPANY, "email": email })),
    )
    .await
    .0
}

/// The newest login mail to this address: (subject, body, token).
async fn login_mail(db: &PgPool, email: &str) -> Option<(String, String, String)> {
    let row: Option<(String, String)> = sqlx::query_as(
        "SELECT subject, body FROM core.mail_outbox WHERE to_address = $1 ORDER BY created_at DESC LIMIT 1",
    )
    .bind(email)
    .fetch_optional(db)
    .await
    .unwrap();
    row.map(|(subject, body)| {
        let start = body.find("#token=").expect("a link with a token") + "#token=".len();
        let token: String = body[start..]
            .chars()
            .take_while(|c| c.is_ascii_alphanumeric() || *c == '_')
            .collect();
        (subject, body, token)
    })
}

async fn exchange(app: &axum::Router, token: &str) -> (StatusCode, Value) {
    call_portal(
        app,
        None,
        Method::POST,
        "/api/v1/portal/sessions",
        Some(json!({ "token": token })),
    )
    .await
}

/// Full login; returns the session token.
async fn login(app: &axum::Router, db: &PgPool, email: &str) -> String {
    assert_eq!(request_link(app, email).await, StatusCode::ACCEPTED);
    let (_, _, link) = login_mail(db, email).await.expect("login mail queued");
    let (status, s) = exchange(app, &link).await;
    assert_eq!(status, StatusCode::CREATED, "{s}");
    s["token"].as_str().unwrap().to_string()
}

async fn portal(
    app: &axum::Router,
    token: &str,
    method: Method,
    uri: &str,
    body: Option<Value>,
) -> (StatusCode, Value) {
    call_portal(
        app,
        Some(token),
        method,
        &format!("/api/v1/portal{uri}"),
        body,
    )
    .await
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_contact_logs_in_with_a_link_that_works_once(db: PgPool) {
    let app = setup(db.clone()).await;
    assert_eq!(
        request_link(&app, "Jan.Peeters@Alpha.example").await,
        StatusCode::ACCEPTED
    );

    // The mail is in the customer's language and greets the person the way they want.
    let (subject, body, token) = login_mail(&db, JAN).await.unwrap();
    assert!(subject.contains("klantenportaal"), "{subject}");
    assert!(body.starts_with("Geachte heer Peeters,"), "{body}");
    assert!(
        body.contains("http://localhost:8081/login#token=tcl_"),
        "{body}"
    );

    // The worker sends it from the company address.
    let dir = tempfile::tempdir().unwrap();
    let sent = process_system_mail(
        &db,
        &tradocraft_core::BlobStore::temp_for_tests(),
        &Mailer::Files(dir.path().to_path_buf()),
        10,
    )
    .await
    .unwrap();
    assert_eq!(sent, 1);
    let eml = std::fs::read_to_string(
        std::fs::read_dir(dir.path())
            .unwrap()
            .next()
            .unwrap()
            .unwrap()
            .path(),
    )
    .unwrap();
    assert!(eml.contains("To: jan.peeters@alpha.example"), "{eml}");
    assert!(eml.contains("sales@example.com"), "{eml}");

    // Only a hash is stored.
    let leaked: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM portal.login_links WHERE encode(token_hash, 'escape') LIKE '%tcl_%'",
    )
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(leaked, 0);

    let (status, s) = exchange(&app, &token).await;
    assert_eq!(status, StatusCode::CREATED, "{s}");
    assert!(s["token"].as_str().unwrap().starts_with("tcs_"));
    assert_eq!(s["profile"]["full_name"], "Jan Peeters");
    assert_eq!(s["profile"]["customer_name"], "Alpha Installaties NV");
    assert_eq!(s["profile"]["effective_language"], "nl");

    // The same link cannot be used again.
    assert_eq!(exchange(&app, &token).await.0, StatusCode::UNAUTHORIZED);
    // The session works; garbage and staff credentials do not.
    let session = s["token"].as_str().unwrap();
    let (status, me) = portal(&app, session, Method::GET, "/me", None).await;
    assert_eq!(status, StatusCode::OK, "{me}");
    assert_eq!(me["email"], JAN);
    assert_eq!(
        call_portal(&app, None, Method::GET, "/api/v1/portal/me", None)
            .await
            .0,
        StatusCode::UNAUTHORIZED
    );
    assert_eq!(
        portal(&app, "tcs_nonsense", Method::GET, "/me", None)
            .await
            .0,
        StatusCode::UNAUTHORIZED
    );
    let (status, _) = call(&app, SUPPORT, Method::GET, "/api/v1/portal/me", None).await;
    assert_eq!(
        status,
        StatusCode::UNAUTHORIZED,
        "a staff login is not a portal session"
    );
    // A login link is not a session.
    assert_eq!(
        portal(&app, &token, Method::GET, "/me", None).await.0,
        StatusCode::UNAUTHORIZED
    );

    // Logging out ends the session.
    assert_eq!(
        portal(&app, session, Method::DELETE, "/session", None)
            .await
            .0,
        StatusCode::NO_CONTENT
    );
    assert_eq!(
        portal(&app, session, Method::GET, "/me", None).await.0,
        StatusCode::UNAUTHORIZED
    );
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_login_form_does_not_reveal_who_is_a_customer(db: PgPool) {
    let app = setup(db.clone()).await;
    // Everyone gets the same answer ...
    for email in ["nobody@nowhere.example", HANS, "not-an-address", ""] {
        assert_eq!(
            request_link(&app, email).await,
            StatusCode::ACCEPTED,
            "{email}"
        );
    }
    // ... also for another company, and a deactivated person.
    let (status, _) = call_portal(
        &app,
        None,
        Method::POST,
        "/api/v1/portal/login-links",
        Some(json!({ "company_id": "00000000-0000-7000-8000-0000000000ff", "email": JAN })),
    )
    .await;
    assert_eq!(status, StatusCode::ACCEPTED);
    sqlx::query("UPDATE crm.contacts SET active = false WHERE id = $1::uuid")
        .bind(SOFIE_ID)
        .execute(&db)
        .await
        .unwrap();
    assert_eq!(request_link(&app, SOFIE).await, StatusCode::ACCEPTED);
    // ... but no mail is sent to them.
    let mails: i64 = sqlx::query_scalar("SELECT count(*) FROM core.mail_outbox")
        .fetch_one(&db)
        .await
        .unwrap();
    assert_eq!(mails, 0);
    let links: i64 = sqlx::query_scalar("SELECT count(*) FROM portal.login_links")
        .fetch_one(&db)
        .await
        .unwrap();
    assert_eq!(links, 0);

    // Requesting again right away does not send a second mail.
    assert_eq!(request_link(&app, JAN).await, StatusCode::ACCEPTED);
    assert_eq!(request_link(&app, JAN).await, StatusCode::ACCEPTED);
    let mails: i64 = sqlx::query_scalar("SELECT count(*) FROM core.mail_outbox")
        .fetch_one(&db)
        .await
        .unwrap();
    assert_eq!(mails, 1);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn expired_links_and_links_for_former_contacts_are_refused(db: PgPool) {
    let app = setup(db.clone()).await;
    assert_eq!(request_link(&app, JAN).await, StatusCode::ACCEPTED);
    let (_, _, token) = login_mail(&db, JAN).await.unwrap();
    sqlx::query("UPDATE portal.login_links SET expires_at = now() - interval '1 second'")
        .execute(&db)
        .await
        .unwrap();
    assert_eq!(exchange(&app, &token).await.0, StatusCode::UNAUTHORIZED);

    // Access is withdrawn between asking for the link and using it.
    assert_eq!(request_link(&app, MARIE).await, StatusCode::ACCEPTED);
    let (_, _, token) = login_mail(&db, MARIE).await.unwrap();
    sqlx::query("UPDATE crm.contacts SET portal_access = false WHERE id = '00000000-0000-7000-8000-000000000603'").execute(&db).await.unwrap();
    assert_eq!(exchange(&app, &token).await.0, StatusCode::UNAUTHORIZED);
    assert_eq!(exchange(&app, "tcl_0000").await.0, StatusCode::UNAUTHORIZED);
    assert_eq!(exchange(&app, "").await.0, StatusCode::UNAUTHORIZED);
}

async fn staff_ticket(app: &axum::Router, contact: &str, subject: &str, internal: bool) -> Value {
    let (status, t) = call(app, SUPPORT, Method::POST, "/api/v1/tickets",
        Some(json!({ "subject": subject, "contact_id": contact, "internal": internal, "body": "INTERNAL: do not show" }))).await;
    assert_eq!(status, StatusCode::CREATED, "{t}");
    t
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_customer_sees_only_what_their_scope_allows_and_nothing_internal(db: PgPool) {
    let app = setup(db.clone()).await;
    let jans = staff_ticket(&app, JAN_ID, "Jan's question", false).await;
    let sofies = staff_ticket(&app, SOFIE_ID, "Sofie's pump", false).await;
    let hidden = staff_ticket(&app, JAN_ID, "Internal matter", true).await;
    let beta = staff_ticket(
        &app,
        "00000000-0000-7000-8000-000000000603",
        "Beta's ticket",
        false,
    )
    .await;
    let sofies_id = sofies["ticket"]["id"].as_str().unwrap();

    // Staff answers by e-mail, writes a note and logs a call on Sofie's ticket.
    call(
        &app,
        SUPPORT,
        Method::POST,
        &format!("/api/v1/tickets/{sofies_id}/notes"),
        Some(json!({ "body": "Customer is difficult" })),
    )
    .await;
    call(
        &app,
        SUPPORT,
        Method::POST,
        "/api/v1/helpdesk/calls",
        Some(json!({ "ticket_id": sofies_id, "direction": "in", "summary": "Called, angry" })),
    )
    .await;
    let (status, _) = call(
        &app,
        SUPPORT,
        Method::POST,
        &format!("/api/v1/tickets/{sofies_id}/replies"),
        Some(json!({ "body": "We will come by." })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);

    // Jan (scope customer) sees both tickets of his company, not the internal or Beta's.
    let jan = login(&app, &db, JAN).await;
    let (_, list) = portal(&app, &jan, Method::GET, "/tickets", None).await;
    let subjects: Vec<&str> = list
        .as_array()
        .unwrap()
        .iter()
        .map(|t| t["subject"].as_str().unwrap())
        .collect();
    assert_eq!(subjects.len(), 2, "{list}");
    assert!(subjects.contains(&"Jan's question") && subjects.contains(&"Sofie's pump"));
    // Sofie (scope own) sees only hers.
    let sofie = login(&app, &db, SOFIE).await;
    let (_, list) = portal(&app, &sofie, Method::GET, "/tickets", None).await;
    assert_eq!(list.as_array().unwrap().len(), 1);
    assert_eq!(list[0]["subject"], "Sofie's pump");
    // After our reply the ticket waits for the customer.
    assert_eq!(list[0]["status"], "pending_customer");

    // The conversation shows what the customer got, never notes or calls.
    let (status, d) = portal(
        &app,
        &sofie,
        Method::GET,
        &format!("/tickets/{sofies_id}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{d}");
    let messages = d["messages"].as_array().unwrap();
    assert_eq!(messages.len(), 1, "{d}");
    assert_eq!(messages[0]["direction"], "outgoing");
    assert_eq!(messages[0]["author_name"], "Support Agent");
    assert_eq!(messages[0]["body"], "We will come by.");
    let all = d.to_string();
    assert!(
        !all.contains("INTERNAL") && !all.contains("difficult") && !all.contains("angry"),
        "{all}"
    );

    // Not visible: a colleague's ticket (scope own), internal, another customer's. All 404.
    for t in [&jans, &hidden, &beta] {
        let id = t["ticket"]["id"].as_str().unwrap();
        assert_eq!(
            portal(&app, &sofie, Method::GET, &format!("/tickets/{id}"), None)
                .await
                .0,
            StatusCode::NOT_FOUND
        );
        assert_eq!(
            portal(
                &app,
                &sofie,
                Method::POST,
                &format!("/tickets/{id}/messages"),
                Some(json!({ "body": "hi" }))
            )
            .await
            .0,
            StatusCode::NOT_FOUND
        );
    }
    let hidden_id = hidden["ticket"]["id"].as_str().unwrap();
    assert_eq!(
        portal(
            &app,
            &jan,
            Method::GET,
            &format!("/tickets/{hidden_id}"),
            None
        )
        .await
        .0,
        StatusCode::NOT_FOUND,
        "internal stays internal for every scope"
    );
    let beta_id = beta["ticket"]["id"].as_str().unwrap();
    assert_eq!(
        portal(
            &app,
            &jan,
            Method::GET,
            &format!("/tickets/{beta_id}"),
            None
        )
        .await
        .0,
        StatusCode::NOT_FOUND
    );
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_customer_opens_tickets_and_replies_which_staff_sees(db: PgPool) {
    let app = setup(db.clone()).await;
    let sofie = login(&app, &db, SOFIE).await;

    let (status, t) = portal(
        &app,
        &sofie,
        Method::POST,
        "/tickets",
        Some(json!({
            "subject": "  Pomp lekt ", "category": "service", "body": "De pomp lekt sinds gisteren."
        })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{t}");
    assert_eq!(t["ticket"]["status"], "open");
    assert_eq!(t["ticket"]["subject"], "Pomp lekt");
    assert_eq!(t["ticket"]["contact_name"], "Sofie Maes");
    assert_eq!(t["messages"][0]["direction"], "incoming");
    assert_eq!(t["messages"][0]["author_name"], "Sofie Maes");
    let id = t["ticket"]["id"].as_str().unwrap();

    // Staff sees a new ticket from this person, unassigned, in her language.
    let (_, st) = call(
        &app,
        SUPPORT,
        Method::GET,
        &format!("/api/v1/tickets/{id}"),
        None,
    )
    .await;
    assert_eq!(st["ticket"]["status"], "new");
    assert_eq!(st["ticket"]["contact_id"], SOFIE_ID);
    assert_eq!(st["ticket"]["customer_id"], ALPHA);
    assert_eq!(st["ticket"]["language"], "nl");
    assert_eq!(st["ticket"]["category"], "service");
    assert_eq!(st["ticket"]["owner_user_id"], Value::Null);
    assert_eq!(st["articles"][0]["kind"], "portal_in");

    // Staff closes it; her reply reopens it.
    let mut update = json!({
        "subject": "Pomp lekt", "status": "closed", "priority": "normal", "category": "service", "language": "nl",
        "owner_user_id": null, "customer_id": ALPHA, "contact_id": SOFIE_ID,
        "contact_name": "Sofie Maes", "contact_email": SOFIE
    });
    call(
        &app,
        SUPPORT,
        Method::PUT,
        &format!("/api/v1/tickets/{id}"),
        Some(update.clone()),
    )
    .await;
    let (_, closed) = portal(&app, &sofie, Method::GET, &format!("/tickets/{id}"), None).await;
    assert_eq!(closed["ticket"]["status"], "closed");
    let (status, d) = portal(
        &app,
        &sofie,
        Method::POST,
        &format!("/tickets/{id}/messages"),
        Some(json!({ "body": "Het lekt nog steeds." })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{d}");
    assert_eq!(d["ticket"]["status"], "open");
    assert_eq!(d["messages"].as_array().unwrap().len(), 2);
    update["status"] = json!("pending_internal");
    call(
        &app,
        SUPPORT,
        Method::PUT,
        &format!("/api/v1/tickets/{id}"),
        Some(update),
    )
    .await;
    let (_, d) = portal(&app, &sofie, Method::GET, &format!("/tickets/{id}"), None).await;
    assert_eq!(
        d["ticket"]["status"], "open",
        "'waiting for production' is not shown"
    );

    // The audit trail records who acted, without a staff user.
    let events: i64 = sqlx::query_scalar("SELECT count(*) FROM audit.events WHERE user_id IS NULL AND action IN ('created_in_portal', 'portal_message', 'portal_login')")
        .fetch_one(&db).await.unwrap();
    assert_eq!(events, 3);

    for (body, what) in [
        (json!({ "subject": "", "body": "x" }), "empty subject"),
        (json!({ "subject": "x", "body": "   " }), "empty body"),
        (
            json!({ "subject": "x", "body": "x", "category": "lead" }),
            "category staff only",
        ),
        (
            json!({ "subject": "x".repeat(201), "body": "x" }),
            "long subject",
        ),
        (
            json!({ "subject": "x", "body": "x".repeat(20_001) }),
            "long body",
        ),
    ] {
        assert_eq!(
            portal(&app, &sofie, Method::POST, "/tickets", Some(body))
                .await
                .0,
            StatusCode::UNPROCESSABLE_ENTITY,
            "{what}"
        );
    }
    assert_eq!(
        portal(
            &app,
            &sofie,
            Method::POST,
            &format!("/tickets/{id}/messages"),
            Some(json!({ "body": "" }))
        )
        .await
        .0,
        StatusCode::UNPROCESSABLE_ENTITY
    );
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn customers_set_how_they_are_addressed_and_staff_can_cut_access(db: PgPool) {
    let app = setup(db.clone()).await;
    let sofie = login(&app, &db, SOFIE).await;
    let (_, me) = portal(&app, &sofie, Method::GET, "/me", None).await;
    assert_eq!(me["greeting"], "Dag Sofie,");

    let (status, me) = portal(
        &app,
        &sofie,
        Method::PUT,
        "/me",
        Some(json!({ "language": "fr", "address_form": "formal", "title": "ms" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{me}");
    assert_eq!(me["effective_language"], "fr");
    assert_eq!(me["customer_language"], "nl");
    assert_eq!(me["greeting"], "Bonjour Madame Maes,");
    // Staff sees the same person data.
    let (_, c) = call(
        &app,
        SUPPORT,
        Method::GET,
        &format!("/api/v1/contacts/{SOFIE_ID}"),
        None,
    )
    .await;
    assert_eq!(c["language"], "fr");
    // Back to "same as the company".
    let (_, me) = portal(
        &app,
        &sofie,
        Method::PUT,
        "/me",
        Some(json!({ "language": null, "address_form": "informal", "title": "ms" })),
    )
    .await;
    assert_eq!(me["language"], Value::Null);
    assert_eq!(me["effective_language"], "nl");
    for body in [
        json!({ "language": "xx", "address_form": "formal", "title": "ms" }),
        json!({ "language": "nl", "address_form": "rude", "title": "ms" }),
        json!({ "language": "nl", "address_form": "formal", "title": "dr" }),
    ] {
        assert_eq!(
            portal(&app, &sofie, Method::PUT, "/me", Some(body)).await.0,
            StatusCode::UNPROCESSABLE_ENTITY
        );
    }

    // Switching off portal access ends the session straight away ...
    let (_, full) = call(
        &app,
        SUPPORT,
        Method::GET,
        &format!("/api/v1/contacts/{SOFIE_ID}"),
        None,
    )
    .await;
    let mut update = json!({
        "first_name": "Sofie", "last_name": "Maes", "title": "ms", "address_form": "informal", "roles": ["technical"],
        "emails": [SOFIE], "phones": [], "portal_access": false, "portal_scope": "own", "active": true
    });
    assert_eq!(full["portal_access"], true);
    let (status, u) = call(
        &app,
        SUPPORT,
        Method::PUT,
        &format!("/api/v1/contacts/{SOFIE_ID}"),
        Some(update.clone()),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{u}");
    assert_eq!(
        portal(&app, &sofie, Method::GET, "/me", None).await.0,
        StatusCode::UNAUTHORIZED
    );
    // ... and no new link is sent.
    sqlx::query("DELETE FROM core.mail_outbox")
        .execute(&db)
        .await
        .unwrap();
    sqlx::query("DELETE FROM portal.login_links")
        .execute(&db)
        .await
        .unwrap();
    assert_eq!(request_link(&app, SOFIE).await, StatusCode::ACCEPTED);
    assert!(login_mail(&db, SOFIE).await.is_none());

    // Granting it again and deactivating the customer also closes the portal.
    update["portal_access"] = json!(true);
    call(
        &app,
        SUPPORT,
        Method::PUT,
        &format!("/api/v1/contacts/{SOFIE_ID}"),
        Some(update),
    )
    .await;
    let jan = login(&app, &db, JAN).await;
    sqlx::query("UPDATE crm.customers SET active = false WHERE id = $1::uuid")
        .bind(ALPHA)
        .execute(&db)
        .await
        .unwrap();
    assert_eq!(
        portal(&app, &jan, Method::GET, "/me", None).await.0,
        StatusCode::UNAUTHORIZED
    );
}

/// ADR 0101: the portal app loads the interface languages the company installed.
#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_portal_serves_installed_interface_languages(db: PgPool) {
    let app = setup(db.clone()).await;
    let token = login(&app, &db, JAN).await;
    let (s, langs) = call_portal(
        &app,
        Some(&token),
        Method::GET,
        "/api/v1/portal/translations/app",
        None,
    )
    .await;
    assert_eq!(s, StatusCode::OK);
    assert_eq!(langs, json!([]));
    let (s, _) = call(
        &app,
        "admin@example.com",
        Method::PUT,
        "/api/v1/admin/translations/app/pt",
        Some(json!({ "entries": { "portalTitle": "Portal do cliente" } })),
    )
    .await;
    assert_eq!(s, StatusCode::OK);
    let (_, langs) = call_portal(
        &app,
        Some(&token),
        Method::GET,
        "/api/v1/portal/translations/app",
        None,
    )
    .await;
    assert_eq!(langs, json!(["pt"]));
    let (s, texts) = call_portal(
        &app,
        Some(&token),
        Method::GET,
        "/api/v1/portal/translations/app/pt",
        None,
    )
    .await;
    assert_eq!(s, StatusCode::OK);
    assert_eq!(texts, json!({ "portalTitle": "Portal do cliente" }));
    let (s, _) = call_portal(
        &app,
        None,
        Method::GET,
        "/api/v1/portal/translations/app",
        None,
    )
    .await;
    assert_eq!(s, StatusCode::UNAUTHORIZED);
}
