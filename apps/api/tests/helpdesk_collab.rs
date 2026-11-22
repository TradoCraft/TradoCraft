//! Helpdesk collaboration: escalation, hand-over, watchers, unread, timeline and presence.

mod common;

use axum::http::{Method, StatusCode};
use chrono::{DateTime, Utc};
use common::{call, call_portal, portal_login, setup};
use serde_json::{json, Value};
use sqlx::PgPool;

const ALPHA: &str = "00000000-0000-7000-8000-000000000401";
const JAN_ID: &str = "00000000-0000-7000-8000-000000000601";
const JAN: &str = "jan.peeters@alpha.example";
const ADMIN: &str = "admin@example.com";
const SALES: &str = "sales@example.com";
const SUPPORT: &str = "support@example.com";
const PRODUCTION: &str = "production@example.com";
const VIEWER: &str = "viewer@example.com";
const ADMIN_ID: &str = "00000000-0000-7000-8000-000000000101";
const SALES_ID: &str = "00000000-0000-7000-8000-000000000102";
const SUPPORT_ID: &str = "00000000-0000-7000-8000-000000000105";
const PRODUCTION_ID: &str = "00000000-0000-7000-8000-000000000106";

async fn ticket_with(app: &axum::Router, subject: &str, contact: bool) -> String {
    let body = if contact {
        json!({ "subject": subject, "contact_id": JAN_ID, "body": "Internal first note" })
    } else {
        json!({ "subject": subject, "customer_id": ALPHA,
                "contact_email": "anna@alpha.example", "body": "Internal first note" })
    };
    let (status, t) = call(app, SUPPORT, Method::POST, "/api/v1/tickets", Some(body)).await;
    assert_eq!(status, StatusCode::CREATED, "{t}");
    t["ticket"]["id"].as_str().unwrap().to_string()
}

async fn new_ticket(app: &axum::Router, subject: &str) -> String {
    ticket_with(app, subject, false).await
}

async fn get(app: &axum::Router, user: &str, id: &str) -> Value {
    let (status, t) = call(
        app,
        user,
        Method::GET,
        &format!("/api/v1/tickets/{id}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{t}");
    t
}

async fn post(app: &axum::Router, user: &str, uri: &str, body: Value) -> (StatusCode, Value) {
    call(
        app,
        user,
        Method::POST,
        &format!("/api/v1/{uri}"),
        Some(body),
    )
    .await
}

async fn escalate(app: &axum::Router, user: &str, id: &str, body: Value) -> (StatusCode, Value) {
    post(app, user, &format!("tickets/{id}/escalate"), body).await
}

async fn delegate(app: &axum::Router, user: &str, id: &str, body: Value) -> (StatusCode, Value) {
    post(app, user, &format!("tickets/{id}/delegate"), body).await
}

async fn read(app: &axum::Router, user: &str, id: &str) {
    let (s, _) = post(app, user, &format!("tickets/{id}/read"), json!({})).await;
    assert_eq!(s, StatusCode::NO_CONTENT);
}

async fn watch(app: &axum::Router, user: &str, id: &str) -> Value {
    let (s, w) = call(
        app,
        user,
        Method::PUT,
        &format!("/api/v1/tickets/{id}/watch"),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::OK, "{w}");
    w
}

async fn list_ids(app: &axum::Router, user: &str, query: &str) -> Vec<String> {
    let (status, p) = call(
        app,
        user,
        Method::GET,
        &format!("/api/v1/tickets?{query}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{p}");
    p["items"]
        .as_array()
        .unwrap()
        .iter()
        .map(|t| t["id"].as_str().unwrap().to_string())
        .collect()
}

async fn unread(app: &axum::Router, user: &str, id: &str) -> bool {
    let (_, p) = call(app, user, Method::GET, "/api/v1/tickets?limit=500", None).await;
    let item = p["items"]
        .as_array()
        .unwrap()
        .iter()
        .find(|t| t["id"] == id)
        .unwrap_or_else(|| panic!("ticket {id} not listed"))
        .clone();
    let in_list = item["unread"].as_bool().unwrap();
    // The detail agrees with the list.
    let d = get(app, user, id).await;
    assert_eq!(d["ticket"]["unread"].as_bool().unwrap(), in_list);
    // The filter agrees too.
    assert_eq!(
        list_ids(app, user, "unread=true")
            .await
            .contains(&id.to_string()),
        in_list
    );
    in_list
}

async fn note(app: &axum::Router, user: &str, id: &str, body: &str) {
    let (s, r) = post(
        app,
        user,
        &format!("tickets/{id}/notes"),
        json!({ "body": body }),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED, "{r}");
}

async fn mails(db: &PgPool, to: &str, containing: &str) -> Vec<(String, String)> {
    sqlx::query_as(
        "SELECT subject, body FROM core.mail_outbox WHERE to_address = $1 AND subject LIKE '%' || $2 || '%' ORDER BY created_at",
    )
    .bind(to)
    .bind(containing)
    .fetch_all(db)
    .await
    .unwrap()
}

async fn customer_message(app: &axum::Router, jan: &str, id: &str, text: &str) {
    let (s, d) = call_portal(
        app,
        Some(jan),
        Method::POST,
        &format!("/api/v1/portal/tickets/{id}/messages"),
        Some(json!({ "body": text })),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED, "{d}");
}

fn number(t: &Value) -> String {
    t["ticket"]["number"].as_str().unwrap().to_string()
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn escalation_needs_a_reason_and_valid_targets(db: PgPool) {
    let app = setup(db.clone()).await;
    let id = new_ticket(&app, "Pump").await;
    for body in [
        json!({ "reason": "" }),
        json!({ "reason": "   " }),
        json!({}),
    ] {
        let (s, _) = escalate(&app, SUPPORT, &id, body).await;
        assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);
    }
    let (s, _) = escalate(
        &app,
        SUPPORT,
        &id,
        json!({ "reason": "x", "to_user_id": SALES_ID, "to_team_id": "00000000-0000-7000-8000-000000000999" }),
    )
    .await;
    assert_eq!(
        s,
        StatusCode::UNPROCESSABLE_ENTITY,
        "person or team, not both"
    );
    let (s, _) = escalate(
        &app,
        SUPPORT,
        &id,
        json!({ "reason": "x", "to_user_id": "00000000-0000-7000-8000-000000000999" }),
    )
    .await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY, "unknown user");
    let (s, _) = escalate(
        &app,
        SUPPORT,
        &id,
        json!({ "reason": "x", "to_team_id": "00000000-0000-7000-8000-000000000999" }),
    )
    .await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY, "unknown team");
    let t = get(&app, SUPPORT, &id).await;
    assert!(t["ticket"]["escalated_at"].is_null());
    // The failed attempts left no trace.
    let (_, events) = call(
        &app,
        SUPPORT,
        Method::GET,
        &format!("/api/v1/tickets/{id}/events"),
        None,
    )
    .await;
    assert!(events
        .as_array()
        .unwrap()
        .iter()
        .all(|e| e["kind"] != "escalated"));
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn escalation_marks_the_ticket_and_optionally_raises_the_priority(db: PgPool) {
    let app = setup(db.clone()).await;
    let id = new_ticket(&app, "Pump").await;
    let plain = new_ticket(&app, "Calm").await;
    assert_eq!(
        get(&app, SUPPORT, &id).await["ticket"]["priority"],
        "normal"
    );

    // Without raising: priority stays, marker is set, who/why/when recorded.
    let (s, t) = escalate(
        &app,
        SUPPORT,
        &id,
        json!({ "reason": "Customer is waiting", "to_user_id": SALES_ID }),
    )
    .await;
    assert_eq!(s, StatusCode::OK, "{t}");
    assert_eq!(t["ticket"]["priority"], "normal");
    assert!(t["ticket"]["escalated_at"].is_string());
    assert_eq!(t["ticket"]["escalated_by"], SUPPORT_ID);
    assert_eq!(t["ticket"]["escalated_by_name"], "Support Agent");

    // Raising goes one step at a time and stops at urgent.
    for expected in ["high", "urgent", "urgent"] {
        let (s, t) = escalate(
            &app,
            SALES,
            &id,
            json!({ "reason": "Still open", "raise_priority": true }),
        )
        .await;
        assert_eq!(s, StatusCode::OK, "{t}");
        assert_eq!(t["ticket"]["priority"], expected);
    }
    assert_eq!(
        get(&app, SUPPORT, &plain).await["ticket"]["priority"],
        "normal"
    );

    // Filter and list marker.
    assert_eq!(
        list_ids(&app, SUPPORT, "escalated=true").await,
        vec![id.clone()]
    );
    let (_, p) = call(
        &app,
        SUPPORT,
        Method::GET,
        "/api/v1/tickets?limit=500",
        None,
    )
    .await;
    let flags: Vec<(String, bool)> = p["items"]
        .as_array()
        .unwrap()
        .iter()
        .map(|t| {
            (
                t["id"].as_str().unwrap().to_string(),
                t["escalated_at"].is_string(),
            )
        })
        .collect();
    assert!(flags.contains(&(id.clone(), true)));
    assert!(flags.contains(&(plain.clone(), false)));

    // Timeline: the priority bump and the escalation are recorded with the reason.
    let (_, events) = call(
        &app,
        SUPPORT,
        Method::GET,
        &format!("/api/v1/tickets/{id}/events"),
        None,
    )
    .await;
    let esc: Vec<&Value> = events
        .as_array()
        .unwrap()
        .iter()
        .filter(|e| e["kind"] == "escalated")
        .collect();
    assert_eq!(esc.len(), 4);
    assert_eq!(esc[0]["comment"], "Customer is waiting");
    assert_eq!(esc[0]["actor_name"], "Support Agent");
    assert_eq!(esc[0]["target_user_name"], "Sales User");
    assert_eq!(
        events
            .as_array()
            .unwrap()
            .iter()
            .filter(|e| e["kind"] == "priority")
            .count(),
        2
    );

    // The caller and the person escalated to follow the ticket.
    let watchers: Vec<String> = get(&app, SUPPORT, &id).await["watchers"]
        .as_array()
        .unwrap()
        .iter()
        .map(|w| w["user_id"].as_str().unwrap().to_string())
        .collect();
    assert!(watchers.contains(&SUPPORT_ID.to_string()));
    assert!(watchers.contains(&SALES_ID.to_string()));

    // Priority drives the SLA: the due times follow the new priority.
    let d = get(&app, SUPPORT, &id).await;
    let created: DateTime<Utc> = d["ticket"]["created_at"].as_str().unwrap().parse().unwrap();
    let due: DateTime<Utc> = d["ticket"]["sla"]["first_response"]["due_at"]
        .as_str()
        .unwrap()
        .parse()
        .unwrap();
    assert_eq!(
        (due - created).num_minutes(),
        60,
        "urgent: first response within an hour"
    );
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn escalation_mail_goes_to_the_target_in_their_language(db: PgPool) {
    let app = setup(db.clone()).await;
    sqlx::query("UPDATE core.users SET language = 'fr' WHERE email = $1")
        .bind(SALES)
        .execute(&db)
        .await
        .unwrap();
    let id = new_ticket(&app, "Pompe").await;
    let n = number(&get(&app, SUPPORT, &id).await);

    let (s, _) = escalate(
        &app,
        SUPPORT,
        &id,
        json!({ "reason": "Urgent chez le client", "to_user_id": SALES_ID }),
    )
    .await;
    assert_eq!(s, StatusCode::OK);
    let m = mails(&db, SALES, &n).await;
    assert_eq!(m.len(), 1);
    assert!(m[0].0.starts_with("Escaladé :"), "{}", m[0].0);
    assert!(
        m[0].1.contains("Motif: Urgent chez le client"),
        "{}",
        m[0].1
    );
    // Not to the caller.
    assert!(mails(&db, SUPPORT, &n).await.is_empty());

    // A user without a language gets the company's default (nl).
    let (s, _) = escalate(
        &app,
        SUPPORT,
        &id,
        json!({ "reason": "Extra", "to_user_id": ADMIN_ID }),
    )
    .await;
    assert_eq!(s, StatusCode::OK);
    let m = mails(&db, ADMIN, &n).await;
    assert!(m[0].0.starts_with("Geëscaleerd:"), "{}", m[0].0);

    // Each of the five languages has its own text.
    for (lang, start) in [
        ("en", "Escalated:"),
        ("de", "Eskaliert:"),
        ("es", "Escalado:"),
    ] {
        sqlx::query("UPDATE core.users SET language = $1 WHERE email = $2")
            .bind(lang)
            .bind(PRODUCTION)
            .execute(&db)
            .await
            .unwrap();
        escalate(
            &app,
            SUPPORT,
            &id,
            json!({ "reason": "r", "to_user_id": PRODUCTION_ID }),
        )
        .await;
        let m = mails(&db, PRODUCTION, &n).await;
        assert!(
            m.last().unwrap().0.starts_with(start),
            "{lang}: {:?}",
            m.last()
        );
    }

    // Without a target the leads of the ticket's team are told; to a team: its leads.
    let (s, team) = post(
        &app,
        ADMIN,
        "helpdesk/teams",
        json!({ "name": "Level 2", "members": [
            { "user_id": SALES_ID, "is_lead": true }, { "user_id": PRODUCTION_ID, "is_lead": false } ] }),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED, "{team}");
    let before = mails(&db, SALES, &n).await.len();
    let (s, _) = escalate(
        &app,
        SUPPORT,
        &id,
        json!({ "reason": "To level 2", "to_team_id": team["id"] }),
    )
    .await;
    assert_eq!(s, StatusCode::OK);
    assert_eq!(
        mails(&db, SALES, &n).await.len(),
        before + 1,
        "the lead is told"
    );
    let prod_before = mails(&db, PRODUCTION, &n).await.len();
    let other = new_ticket(&app, "Other").await;
    let on = number(&get(&app, SUPPORT, &other).await);
    call(
        &app,
        SUPPORT,
        Method::PUT,
        &format!("/api/v1/tickets/{other}/assignment"),
        Some(json!({ "team_id": team["id"], "owner_user_id": SUPPORT_ID })),
    )
    .await;
    let (s, _) = escalate(&app, SUPPORT, &other, json!({ "reason": "No target" })).await;
    assert_eq!(s, StatusCode::OK);
    assert_eq!(
        mails(&db, SALES, &on).await.len(),
        1,
        "team lead of the ticket's team"
    );
    assert!(
        mails(&db, PRODUCTION, &on).await.is_empty(),
        "plain members are not told"
    );
    assert_eq!(mails(&db, PRODUCTION, &n).await.len(), prod_before);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn delegating_hands_over_with_a_comment_and_keeps_the_previous_owner_informed(db: PgPool) {
    let app = setup(db.clone()).await;
    let id = ticket_with(&app, "Pump", true).await;
    let n = number(&get(&app, SUPPORT, &id).await);
    assert_eq!(
        get(&app, SUPPORT, &id).await["ticket"]["owner_user_id"],
        SUPPORT_ID
    );

    let (s, t) = delegate(
        &app,
        SUPPORT,
        &id,
        json!({ "to_user_id": SUPPORT_ID, "comment": "me" }),
    )
    .await;
    assert_eq!(
        s,
        StatusCode::UNPROCESSABLE_ENTITY,
        "{t}: already the owner"
    );
    let (s, _) = delegate(
        &app,
        SUPPORT,
        &id,
        json!({ "to_user_id": "00000000-0000-7000-8000-000000000999" }),
    )
    .await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);
    let (s, _) = delegate(&app, VIEWER, &id, json!({ "to_user_id": SALES_ID })).await;
    assert_eq!(s, StatusCode::FORBIDDEN);

    let (s, t) = delegate(
        &app,
        SUPPORT,
        &id,
        json!({ "to_user_id": SALES_ID, "comment": "Please call the customer, he wants a discount" }),
    )
    .await;
    assert_eq!(s, StatusCode::OK, "{t}");
    assert_eq!(t["ticket"]["owner_user_id"], SALES_ID);
    let watchers: Vec<&str> = t["watchers"]
        .as_array()
        .unwrap()
        .iter()
        .map(|w| w["user_id"].as_str().unwrap())
        .collect();
    assert!(watchers.contains(&SUPPORT_ID), "previous owner watches");
    assert!(watchers.contains(&SALES_ID));

    // The new owner is mailed with the comment (company default language nl).
    let m = mails(&db, SALES, &n).await;
    assert_eq!(m.len(), 1);
    assert!(m[0].0.starts_with("Overgedragen aan u:"), "{}", m[0].0);
    assert!(m[0]
        .1
        .contains("Opmerking: Please call the customer, he wants a discount"));
    assert!(mails(&db, SUPPORT, &n).await.is_empty());

    // The event carries the comment; the customer never sees it.
    let (_, events) = call(
        &app,
        SALES,
        Method::GET,
        &format!("/api/v1/tickets/{id}/events"),
        None,
    )
    .await;
    let ev = events
        .as_array()
        .unwrap()
        .iter()
        .find(|e| e["kind"] == "delegated")
        .unwrap();
    assert_eq!(
        ev["comment"],
        "Please call the customer, he wants a discount"
    );
    assert_eq!(ev["previous_user_name"], "Support Agent");
    assert_eq!(ev["target_user_name"], "Sales User");
    let jan = portal_login(&app, &db, JAN).await;
    let (_, portal) = call_portal(
        &app,
        Some(&jan),
        Method::GET,
        &format!("/api/v1/portal/tickets/{id}"),
        None,
    )
    .await;
    assert!(!portal.to_string().contains("discount"), "{portal}");
    // No outgoing mail to the customer either.
    assert!(mails(&db, JAN, "")
        .await
        .iter()
        .all(|(_, b)| !b.contains("discount")));

    // Delegating to yourself (taking over) is allowed and sends no mail.
    let (s, _) = delegate(&app, SUPPORT, &id, json!({ "to_user_id": SUPPORT_ID })).await;
    assert_eq!(s, StatusCode::OK);
    assert!(mails(&db, SUPPORT, &n).await.is_empty());
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn watchers_are_mailed_at_most_every_ten_minutes_and_never_about_their_own_change(
    db: PgPool,
) {
    let app = setup(db.clone()).await;
    let id = ticket_with(&app, "Pump", true).await;
    let jan = portal_login(&app, &db, JAN).await;
    let n = number(&get(&app, SUPPORT, &id).await);
    // support is the owner and so a watcher; sales and admin join.
    watch(&app, SALES, &id).await;
    let (s, w) = post(
        &app,
        SUPPORT,
        &format!("tickets/{id}/watchers"),
        json!({ "user_id": ADMIN_ID }),
    )
    .await;
    assert_eq!(s, StatusCode::OK, "{w}");
    assert_eq!(w.as_array().unwrap().len(), 3);
    // Adding twice is harmless.
    let (_, w) = post(
        &app,
        SUPPORT,
        &format!("tickets/{id}/watchers"),
        json!({ "user_id": ADMIN_ID }),
    )
    .await;
    assert_eq!(w.as_array().unwrap().len(), 3);
    // Unknown users cannot be added.
    let (s, _) = post(
        &app,
        SUPPORT,
        &format!("tickets/{id}/watchers"),
        json!({ "user_id": "00000000-0000-7000-8000-000000000999" }),
    )
    .await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);

    customer_message(&app, &jan, &id, "First question").await;
    for u in [SUPPORT, SALES, ADMIN] {
        assert_eq!(mails(&db, u, &n).await.len(), 1, "{u}");
    }
    assert!(mails(&db, SUPPORT, &n).await[0]
        .0
        .starts_with("Antwoord van de klant:"));

    // A second message within ten minutes: no new mail.
    customer_message(&app, &jan, &id, "Second question").await;
    for u in [SUPPORT, SALES, ADMIN] {
        assert_eq!(mails(&db, u, &n).await.len(), 1, "{u} throttled");
    }

    // Ten minutes later only the watcher whose last mail is older is mailed again.
    sqlx::query(
        "UPDATE helpdesk.ticket_watchers SET last_notified_at = now() - interval '11 minutes'
         WHERE ticket_id = $1::uuid AND user_id = $2::uuid",
    )
    .bind(&id)
    .bind(SALES_ID)
    .execute(&db)
    .await
    .unwrap();
    customer_message(&app, &jan, &id, "Third question").await;
    assert_eq!(mails(&db, SALES, &n).await.len(), 2);
    assert_eq!(mails(&db, SUPPORT, &n).await.len(), 1);

    // An owner change is mailed to the watchers except the person who made it.
    sqlx::query(
        "UPDATE helpdesk.ticket_watchers SET last_notified_at = NULL WHERE ticket_id = $1::uuid",
    )
    .bind(&id)
    .execute(&db)
    .await
    .unwrap();
    let (s, _) = call(
        &app,
        SALES,
        Method::PUT,
        &format!("/api/v1/tickets/{id}/assignment"),
        Some(json!({ "team_id": null, "owner_user_id": SALES_ID })),
    )
    .await;
    assert_eq!(s, StatusCode::OK);
    assert_eq!(
        mails(&db, SALES, &n).await.len(),
        2,
        "the author is not told"
    );
    assert_eq!(mails(&db, SUPPORT, &n).await.len(), 2);
    assert!(mails(&db, SUPPORT, &n).await[1]
        .0
        .starts_with("Nieuwe eigenaar:"));
    assert_eq!(mails(&db, ADMIN, &n).await.len(), 2);

    // Stopping watching: no more mail.
    let (s, w) = call(
        &app,
        ADMIN,
        Method::DELETE,
        &format!("/api/v1/tickets/{id}/watch"),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::OK);
    assert!(w
        .as_array()
        .unwrap()
        .iter()
        .all(|x| x["user_id"] != ADMIN_ID));
    sqlx::query(
        "UPDATE helpdesk.ticket_watchers SET last_notified_at = NULL WHERE ticket_id = $1::uuid",
    )
    .bind(&id)
    .execute(&db)
    .await
    .unwrap();
    customer_message(&app, &jan, &id, "Fourth").await;
    assert_eq!(mails(&db, ADMIN, &n).await.len(), 2);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn replying_and_noting_make_you_a_watcher(db: PgPool) {
    let app = setup(db.clone()).await;
    let id = new_ticket(&app, "Pump").await;
    note(&app, SALES, &id, "I know this one").await;
    let (s, r) = post(
        &app,
        ADMIN,
        &format!("tickets/{id}/replies"),
        json!({ "body": "Dear customer" }),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED, "{r}");
    let names: Vec<&str> = r["watchers"]
        .as_array()
        .unwrap()
        .iter()
        .map(|w| w["user_name"].as_str().unwrap())
        .collect();
    assert_eq!(names, vec!["Admin User", "Sales User", "Support Agent"]);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn unread_follows_activity_by_others_and_the_read_mark(db: PgPool) {
    let app = setup(db.clone()).await;
    let id = new_ticket(&app, "Pump").await;

    // The creator's own actions never make it unread for them.
    assert!(!unread(&app, SUPPORT, &id).await);
    // Somebody who is not involved never sees an unread marker.
    assert!(!unread(&app, ADMIN, &id).await);

    // A watcher who never opened it has unread activity (the ticket's history).
    watch(&app, SALES, &id).await;
    assert!(unread(&app, SALES, &id).await);
    read(&app, SALES, &id).await;
    assert!(!unread(&app, SALES, &id).await);

    // A colleague's note makes it unread for the others, not for the author.
    note(&app, SUPPORT, &id, "Called the customer").await;
    assert!(unread(&app, SALES, &id).await);
    assert!(!unread(&app, SUPPORT, &id).await);
    assert!(!unread(&app, ADMIN, &id).await, "still not involved");
    read(&app, SALES, &id).await;
    assert!(!unread(&app, SALES, &id).await);

    // My own actions do not make it unread for me, theirs do.
    note(&app, SALES, &id, "Thanks").await;
    assert!(!unread(&app, SALES, &id).await);
    assert!(unread(&app, SUPPORT, &id).await);
    read(&app, SUPPORT, &id).await;

    // An event by another user (a priority change) counts as activity too; so does a tag.
    let t = get(&app, SALES, &id).await;
    let tk = &t["ticket"];
    let (s, _) = call(
        &app,
        SALES,
        Method::PUT,
        &format!("/api/v1/tickets/{id}"),
        Some(json!({
            "subject": tk["subject"], "status": tk["status"], "priority": "high",
            "category": tk["category"], "language": tk["language"],
            "owner_user_id": tk["owner_user_id"], "customer_id": tk["customer_id"],
            "contact_name": tk["contact_name"], "contact_email": tk["contact_email"],
        })),
    )
    .await;
    assert_eq!(s, StatusCode::OK);
    assert!(unread(&app, SUPPORT, &id).await);
    assert!(!unread(&app, SALES, &id).await);
    read(&app, SUPPORT, &id).await;
    assert!(!unread(&app, SUPPORT, &id).await);

    // A customer message is activity by nobody on the team.
    let jan = portal_login(&app, &db, JAN).await;
    let c = ticket_with(&app, "Customer", true).await;
    read(&app, SUPPORT, &c).await;
    customer_message(&app, &jan, &c, "Hello?").await;
    assert!(unread(&app, SUPPORT, &c).await);

    // A mail that opens a ticket in a team is unread for the team's members, not for others.
    let (_, team) = post(
        &app,
        ADMIN,
        "helpdesk/teams",
        json!({ "name": "Desk", "members": [{ "user_id": SALES_ID, "is_lead": false }] }),
    )
    .await;
    sqlx::query("UPDATE helpdesk.settings SET default_team_id = NULL")
        .execute(&db)
        .await
        .unwrap();
    let (s, _) = call(
        &app,
        ADMIN,
        Method::PUT,
        "/api/v1/helpdesk/settings",
        Some(json!({ "default_team_id": team["id"], "csat_enabled": false })),
    )
    .await;
    assert_eq!(s, StatusCode::OK);
    let (s, d) = call_portal(
        &app,
        Some(&jan),
        Method::POST,
        "/api/v1/portal/tickets",
        Some(json!({ "subject": "New from portal", "category": "question", "body": "Help" })),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED, "{d}");
    let pid = d["ticket"]["id"].as_str().unwrap().to_string();
    assert!(unread(&app, SALES, &pid).await, "team member");
    assert!(!unread(&app, SUPPORT, &pid).await, "not in the team");
    assert!(list_ids(&app, SALES, "unread=true").await.contains(&pid));
    read(&app, SALES, &pid).await;
    assert!(!list_ids(&app, SALES, "unread=true").await.contains(&pid));

    // The "watching" filter lists the tickets I follow.
    let watching = list_ids(&app, SALES, "watching=true").await;
    assert!(watching.contains(&id));
    assert!(!watching.contains(&pid));
    let t = get(&app, SALES, &id).await;
    assert_eq!(t["ticket"]["watching"], true);
    assert_eq!(get(&app, ADMIN, &id).await["ticket"]["watching"], false);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_ticket_shows_who_read_it_and_when(db: PgPool) {
    let app = setup(db.clone()).await;
    let id = new_ticket(&app, "Pump").await;
    assert!(get(&app, SUPPORT, &id).await["readers"]
        .as_array()
        .unwrap()
        .is_empty());
    read(&app, SUPPORT, &id).await;
    read(&app, SALES, &id).await;
    read(&app, SUPPORT, &id).await;
    let d = get(&app, VIEWER, &id).await;
    let readers = d["readers"].as_array().unwrap();
    assert_eq!(readers.len(), 2, "one row per person");
    assert_eq!(
        readers[0]["user_name"], "Support Agent",
        "most recent first"
    );
    assert_eq!(readers[1]["user_name"], "Sales User");
    let a: DateTime<Utc> = readers[0]["last_read_at"]
        .as_str()
        .unwrap()
        .parse()
        .unwrap();
    let b: DateTime<Utc> = readers[1]["last_read_at"]
        .as_str()
        .unwrap()
        .parse()
        .unwrap();
    assert!(a > b);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_timeline_merges_events_and_messages_in_order(db: PgPool) {
    let app = setup(db.clone()).await;
    let id = ticket_with(&app, "Pump", true).await;
    note(&app, SUPPORT, &id, "Looked at it").await;
    let (s, _) = call(
        &app,
        SUPPORT,
        Method::PUT,
        &format!("/api/v1/tickets/{id}/assignment"),
        Some(json!({ "team_id": null, "owner_user_id": SALES_ID })),
    )
    .await;
    assert_eq!(s, StatusCode::OK);
    post(
        &app,
        SALES,
        &format!("tickets/{id}/tags"),
        json!({ "tag": "urgent-visit" }),
    )
    .await;
    let (s, r) = post(
        &app,
        SALES,
        &format!("tickets/{id}/replies"),
        json!({ "body": "We will come by" }),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED, "{r}");
    let jan = portal_login(&app, &db, JAN).await;
    customer_message(&app, &jan, &id, "Thank you").await;
    escalate(
        &app,
        SALES,
        &id,
        json!({ "reason": "VIP", "raise_priority": true }),
    )
    .await;
    delegate(
        &app,
        SALES,
        &id,
        json!({ "to_user_id": SUPPORT_ID, "comment": "back to you" }),
    )
    .await;

    let (s, events) = call(
        &app,
        VIEWER,
        Method::GET,
        &format!("/api/v1/tickets/{id}/events"),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::OK, "{events}");
    let items = events.as_array().unwrap();
    let summary: Vec<String> = items
        .iter()
        .map(|e| {
            format!(
                "{}:{}",
                e["source"].as_str().unwrap(),
                e["kind"].as_str().unwrap()
            )
        })
        .collect();
    // created event and first note share their moment; the rest follows the order of the actions.
    let pos = |needle: &str| {
        summary
            .iter()
            .position(|s| s == needle)
            .unwrap_or_else(|| panic!("{needle} in {summary:?}"))
    };
    assert!(pos("event:created") < pos("event:assigned"));
    assert!(pos("message:note") < pos("event:assigned"));
    assert!(pos("event:assigned") < pos("event:tag_added"));
    assert!(pos("event:tag_added") < pos("message:email_out"));
    assert!(pos("message:email_out") < pos("event:status"));
    assert!(pos("message:email_out") < pos("message:portal_in"));
    assert!(pos("message:portal_in") < pos("event:priority"));
    assert!(pos("event:priority") < pos("event:escalated"));
    assert!(pos("event:escalated") < pos("event:delegated"));
    let times: Vec<DateTime<Utc>> = items
        .iter()
        .map(|e| e["at"].as_str().unwrap().parse().unwrap())
        .collect();
    assert!(times.windows(2).all(|w| w[0] <= w[1]), "oldest first");

    let find = |kind: &str| items.iter().find(|e| e["kind"] == kind).unwrap();
    assert_eq!(find("created")["actor_name"], "Support Agent");
    assert_eq!(find("assigned")["target_user_name"], "Sales User");
    assert_eq!(find("assigned")["previous_user_name"], "Support Agent");
    assert_eq!(find("tag_added")["to_value"], "urgent-visit");
    let status = find("status");
    assert_eq!(
        (status["from_value"].as_str(), status["to_value"].as_str()),
        (Some("open"), Some("pending_customer"))
    );
    let prio = find("priority");
    assert_eq!(
        (prio["from_value"].as_str(), prio["to_value"].as_str()),
        (Some("normal"), Some("high"))
    );
    assert_eq!(find("portal_in")["comment"], "Thank you");
    assert_eq!(find("portal_in")["actor_name"], "Jan Peeters");
    assert!(find("note")["comment"]
        .as_str()
        .unwrap()
        .starts_with("Internal first"));
    assert_eq!(find("delegated")["comment"], "back to you");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn presence_is_advisory_excludes_the_caller_and_expires(db: PgPool) {
    let app = setup(db.clone()).await;
    let id = new_ticket(&app, "Pump").await;
    let uri = format!("/api/v1/tickets/{id}/presence");

    // Alone: nobody else is listed, also not myself.
    let (s, others) = call(
        &app,
        SUPPORT,
        Method::POST,
        &uri,
        Some(json!({ "mode": "viewing" })),
    )
    .await;
    assert_eq!(s, StatusCode::OK, "{others}");
    assert_eq!(others, json!([]));
    let (_, others) = call(&app, SUPPORT, Method::GET, &uri, None).await;
    assert_eq!(others, json!([]));

    // A colleague sees me, and when I start typing, sees "replying".
    let (_, others) = call(
        &app,
        SALES,
        Method::POST,
        &uri,
        Some(json!({ "mode": "viewing" })),
    )
    .await;
    assert_eq!(others.as_array().unwrap().len(), 1);
    assert_eq!(others[0]["user_name"], "Support Agent");
    assert_eq!(others[0]["mode"], "viewing");
    call(
        &app,
        SUPPORT,
        Method::POST,
        &uri,
        Some(json!({ "mode": "replying" })),
    )
    .await;
    let (_, others) = call(&app, SALES, Method::GET, &uri, None).await;
    assert_eq!(others.as_array().unwrap().len(), 1);
    assert_eq!(others[0]["mode"], "replying");
    let (_, mine) = call(&app, SUPPORT, Method::GET, &uri, None).await;
    assert_eq!(mine.as_array().unwrap().len(), 1, "only sales, not me");
    assert_eq!(mine[0]["user_name"], "Sales User");

    // Bad mode.
    let (s, _) = call(
        &app,
        SUPPORT,
        Method::POST,
        &uri,
        Some(json!({ "mode": "sleeping" })),
    )
    .await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);

    // Nothing is locked: both can reply.
    let (s, _) = post(
        &app,
        SALES,
        &format!("tickets/{id}/replies"),
        json!({ "body": "Hello" }),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED);

    // After 60 s a row no longer counts; the worker removes old rows after 5 minutes.
    sqlx::query("UPDATE helpdesk.ticket_presence SET seen_at = now() - interval '61 seconds' WHERE user_id = $1::uuid")
        .bind(SUPPORT_ID)
        .execute(&db)
        .await
        .unwrap();
    let (_, others) = call(&app, SALES, Method::GET, &uri, None).await;
    assert_eq!(others, json!([]));
    assert_eq!(
        tradocraft_helpdesk::collab::cleanup_presence(&db)
            .await
            .unwrap(),
        0
    );
    sqlx::query("UPDATE helpdesk.ticket_presence SET seen_at = now() - interval '6 minutes' WHERE user_id = $1::uuid")
        .bind(SUPPORT_ID)
        .execute(&db)
        .await
        .unwrap();
    assert_eq!(
        tradocraft_helpdesk::collab::cleanup_presence(&db)
            .await
            .unwrap(),
        1
    );
    // The heartbeat renews an expired row.
    call(
        &app,
        SUPPORT,
        Method::POST,
        &uri,
        Some(json!({ "mode": "viewing" })),
    )
    .await;
    let (_, others) = call(&app, SALES, Method::GET, &uri, None).await;
    assert_eq!(others.as_array().unwrap().len(), 1);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn another_company_sees_and_changes_nothing(db: PgPool) {
    let app = setup(db.clone()).await;
    const OTHER: &str = "00000000-0000-7000-8000-0000000000b1";
    sqlx::query("INSERT INTO core.companies (id, name) VALUES ($1::uuid, 'Other BV')")
        .bind(OTHER)
        .execute(&db)
        .await
        .unwrap();
    sqlx::query("INSERT INTO core.users (id, email, display_name) VALUES (gen_random_uuid(), 'other@example.com', 'Other Admin')")
        .execute(&db)
        .await
        .unwrap();
    sqlx::query("INSERT INTO core.user_companies (user_id, company_id, roles, is_default) SELECT id, $1::uuid, '{admin}', true FROM core.users WHERE email = 'other@example.com'")
        .bind(OTHER)
        .execute(&db)
        .await
        .unwrap();
    let other_id: String =
        sqlx::query_scalar("SELECT id::text FROM core.users WHERE email = 'other@example.com'")
            .fetch_one(&db)
            .await
            .unwrap();
    let id = new_ticket(&app, "Pump").await;
    const O: &str = "other@example.com";
    for (method, uri, body) in [
        (Method::GET, format!("tickets/{id}/events"), None),
        (
            Method::POST,
            format!("tickets/{id}/escalate"),
            Some(json!({ "reason": "x" })),
        ),
        (
            Method::POST,
            format!("tickets/{id}/delegate"),
            Some(json!({ "to_user_id": other_id })),
        ),
        (Method::PUT, format!("tickets/{id}/watch"), None),
        (Method::DELETE, format!("tickets/{id}/watch"), None),
        (
            Method::POST,
            format!("tickets/{id}/watchers"),
            Some(json!({ "user_id": other_id })),
        ),
        (Method::POST, format!("tickets/{id}/read"), Some(json!({}))),
        (
            Method::POST,
            format!("tickets/{id}/presence"),
            Some(json!({ "mode": "viewing" })),
        ),
        (Method::GET, format!("tickets/{id}/presence"), None),
    ] {
        let (s, _) = call(&app, O, method.clone(), &format!("/api/v1/{uri}"), body).await;
        assert_eq!(s, StatusCode::NOT_FOUND, "{method} {uri}");
    }
    // Nothing leaked into the ticket's tables.
    for table in ["ticket_watchers", "ticket_reads", "ticket_presence"] {
        let n: i64 = sqlx::query_scalar(sqlx::AssertSqlSafe(format!(
            "SELECT count(*) FROM helpdesk.{table} WHERE user_id = $1::uuid"
        )))
        .bind(&other_id)
        .fetch_one(&db)
        .await
        .unwrap();
        assert_eq!(n, 0, "{table}");
    }
    // Colleagues of another company cannot be made watchers or owners.
    let (s, _) = post(
        &app,
        SUPPORT,
        &format!("tickets/{id}/watchers"),
        json!({ "user_id": other_id }),
    )
    .await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);
    let (s, _) = delegate(&app, SUPPORT, &id, json!({ "to_user_id": other_id })).await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);
    let (s, _) = escalate(
        &app,
        SUPPORT,
        &id,
        json!({ "reason": "x", "to_user_id": other_id }),
    )
    .await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);
    // The other company's list is empty and its unread/escalated filters work.
    assert!(list_ids(&app, O, "unread=true").await.is_empty());
    assert!(list_ids(&app, O, "escalated=true").await.is_empty());
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn permissions(db: PgPool) {
    let app = setup(db.clone()).await;
    let id = new_ticket(&app, "Pump").await;
    // Read-only users can read the timeline, watch and be seen, but not change anything.
    let (s, _) = call(
        &app,
        VIEWER,
        Method::GET,
        &format!("/api/v1/tickets/{id}/events"),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::OK);
    watch(&app, VIEWER, &id).await;
    read(&app, VIEWER, &id).await;
    let (s, _) = call(
        &app,
        VIEWER,
        Method::POST,
        &format!("/api/v1/tickets/{id}/presence"),
        Some(json!({ "mode": "viewing" })),
    )
    .await;
    assert_eq!(s, StatusCode::OK);
    let (s, _) = escalate(&app, VIEWER, &id, json!({ "reason": "x" })).await;
    assert_eq!(s, StatusCode::FORBIDDEN);
    let (s, _) = delegate(&app, VIEWER, &id, json!({ "to_user_id": SALES_ID })).await;
    assert_eq!(s, StatusCode::FORBIDDEN);
    let (s, _) = post(
        &app,
        VIEWER,
        &format!("tickets/{id}/watchers"),
        json!({ "user_id": SALES_ID }),
    )
    .await;
    assert_eq!(s, StatusCode::FORBIDDEN);
    // Roles without helpdesk access cannot even read.
    let (s, _) = call(
        &app,
        "technician@example.com",
        Method::GET,
        &format!("/api/v1/tickets/{id}/events"),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::FORBIDDEN);
    let (s, _) = call(
        &app,
        "technician@example.com",
        Method::GET,
        &format!("/api/v1/tickets/{id}/presence"),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::FORBIDDEN);
    let (s, _) = post(
        &app,
        "technician@example.com",
        &format!("tickets/{id}/read"),
        json!({}),
    )
    .await;
    assert_eq!(s, StatusCode::FORBIDDEN);
    // Production can escalate and delegate (helpdesk.write).
    let (s, _) = escalate(
        &app,
        PRODUCTION,
        &id,
        json!({ "reason": "Need a decision" }),
    )
    .await;
    assert_eq!(s, StatusCode::OK);
    let (s, _) = delegate(&app, PRODUCTION, &id, json!({ "to_user_id": SALES_ID })).await;
    assert_eq!(s, StatusCode::OK);
}
