//! Helpdesk ticket links and bundles (A9): bundle, related and duplicate links, visible from both
//! tickets, the rules that keep a bundle one level deep, and the bundle mass update with its
//! preview.

mod common;

use axum::http::{Method, StatusCode};
use common::{call, call_raw, setup};
use serde_json::{json, Value};
use sqlx::PgPool;

const SUPPORT: &str = "support@example.com";
const VIEWER: &str = "viewer@example.com";

/// A new ticket from a customer's e-mail; returns its id.
async fn ticket_from(app: &axum::Router, from: &str, subject: &str, n: u32) -> String {
    let raw = format!(
        "From: {from}\r\nTo: sales@example.com\r\nSubject: {subject}\r\nMessage-ID: <link-{n}@test.example>\r\nContent-Type: text/plain; charset=utf-8\r\n\r\nPlease help.\r\n"
    )
    .into_bytes();
    let (status, r) = call_raw(
        app,
        SUPPORT,
        "/api/v1/helpdesk/inbound",
        "message/rfc822",
        raw,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{r}");
    r["ticket_id"].as_str().unwrap().to_string()
}

async fn api(
    app: &axum::Router,
    method: Method,
    uri: &str,
    body: Option<Value>,
) -> (StatusCode, Value) {
    call(app, SUPPORT, method, &format!("/api/v1{uri}"), body).await
}

async fn link(app: &axum::Router, id: &str, other: &str, relation: &str) -> (StatusCode, Value) {
    api(
        app,
        Method::POST,
        &format!("/tickets/{id}/links"),
        Some(json!({ "target_id": other, "relation": relation })),
    )
    .await
}

async fn links(app: &axum::Router, id: &str) -> Value {
    let (status, l) = api(app, Method::GET, &format!("/tickets/{id}/links"), None).await;
    assert_eq!(status, StatusCode::OK, "{l}");
    l
}

fn numbers(list: &Value) -> Vec<String> {
    list.as_array()
        .unwrap()
        .iter()
        .map(|t| t["number"].as_str().unwrap().to_string())
        .collect()
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_link_shows_on_both_tickets_and_can_be_removed(db: PgPool) {
    let app = setup(db).await;
    let a = ticket_from(&app, "anna@alpha.example", "Outage", 1).await;
    let b = ticket_from(&app, "bob@beta.example", "No water", 2).await;
    let c = ticket_from(&app, "cy@gamma.example", "Pump noise", 3).await;

    let (status, from_a) = link(&app, &a, &b, "child").await;
    assert_eq!(status, StatusCode::CREATED, "{from_a}");
    assert_eq!(from_a["children"].as_array().unwrap().len(), 1);
    assert_eq!(from_a["children"][0]["ticket_id"], b.as_str());
    assert_eq!(from_a["children"][0]["status"], "new");

    let from_b = links(&app, &b).await;
    assert_eq!(from_b["parent"]["ticket_id"], a.as_str());
    assert!(from_b["children"].as_array().unwrap().is_empty());

    // Related is symmetric whichever ticket made it.
    assert_eq!(link(&app, &c, &a, "related").await.0, StatusCode::CREATED);
    assert_eq!(numbers(&links(&app, &a).await["related"]).len(), 1);
    assert_eq!(numbers(&links(&app, &c).await["related"]).len(), 1);

    // Both tickets got a note about the link.
    let (_, detail) = api(&app, Method::GET, &format!("/tickets/{b}"), None).await;
    let notes: Vec<&str> = detail["articles"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|x| x["kind"] == "note")
        .map(|x| x["body"].as_str().unwrap())
        .collect();
    assert!(
        notes.iter().any(|n| n.contains("joined the bundle")),
        "{notes:?}"
    );

    // Removing it from the child's side clears both.
    let link_id = from_b["parent"]["link_id"].as_str().unwrap();
    let (status, after) = api(
        &app,
        Method::DELETE,
        &format!("/tickets/{b}/links/{link_id}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{after}");
    assert!(after["parent"].is_null());
    assert!(links(&app, &a).await["children"]
        .as_array()
        .unwrap()
        .is_empty());
    // The link is gone for the other ticket too: a second delete is a 404.
    let (status, _) = api(
        &app,
        Method::DELETE,
        &format!("/tickets/{a}/links/{link_id}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_bundle_stays_one_level_deep_and_duplicates_have_one_original(db: PgPool) {
    let app = setup(db).await;
    let p = ticket_from(&app, "anna@alpha.example", "Parent", 1).await;
    let c1 = ticket_from(&app, "bob@beta.example", "Child one", 2).await;
    let c2 = ticket_from(&app, "cy@gamma.example", "Child two", 3).await;
    let x = ticket_from(&app, "dee@delta.example", "Other", 4).await;

    assert_eq!(link(&app, &p, &c1, "child").await.0, StatusCode::CREATED);
    // Itself, an already linked pair (any kind), a second parent, a child as parent and a parent as child.
    assert_eq!(
        link(&app, &p, &p, "related").await.0,
        StatusCode::UNPROCESSABLE_ENTITY
    );
    assert_eq!(link(&app, &p, &c1, "related").await.0, StatusCode::CONFLICT);
    assert_eq!(
        link(&app, &x, &c1, "child").await.0,
        StatusCode::CONFLICT,
        "one parent only"
    );
    assert_eq!(
        link(&app, &c2, &c1, "child").await.0,
        StatusCode::CONFLICT,
        "a child is not a parent"
    );
    assert_eq!(
        link(&app, &x, &p, "child").await.0,
        StatusCode::CONFLICT,
        "a parent is not a child"
    );
    assert_eq!(link(&app, &c1, &x, "child").await.0, StatusCode::CONFLICT);
    // Parent seen from the other side works the same.
    assert_eq!(link(&app, &c2, &p, "parent").await.0, StatusCode::CREATED);
    assert_eq!(numbers(&links(&app, &p).await["children"]).len(), 2);

    // Duplicates: one original; an original is never a duplicate.
    assert_eq!(
        link(&app, &x, &p, "duplicate_of").await.0,
        StatusCode::CREATED
    );
    let from_p = links(&app, &p).await;
    assert_eq!(from_p["duplicates"][0]["ticket_id"], x.as_str());
    assert_eq!(
        links(&app, &x).await["duplicate_of"]["ticket_id"],
        p.as_str()
    );
    let y = ticket_from(&app, "eve@eps.example", "Third", 5).await;
    assert_eq!(
        link(&app, &x, &y, "duplicate_of").await.0,
        StatusCode::CONFLICT,
        "already a duplicate"
    );
    assert_eq!(
        link(&app, &y, &x, "duplicate_of").await.0,
        StatusCode::CONFLICT,
        "x is a duplicate itself"
    );
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn links_need_the_helpdesk_write_permission(db: PgPool) {
    let app = setup(db).await;
    let a = ticket_from(&app, "anna@alpha.example", "A", 1).await;
    let b = ticket_from(&app, "bob@beta.example", "B", 2).await;
    let (status, _) = call(
        &app,
        VIEWER,
        Method::POST,
        &format!("/api/v1/tickets/{a}/links"),
        Some(json!({ "target_id": b, "relation": "related" })),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn merging_a_ticket_drops_its_links(db: PgPool) {
    let app = setup(db).await;
    // Same customer (same company domain), as a merge requires.
    let a = ticket_from(&app, "anna@alpha.example", "First", 1).await;
    let b = ticket_from(&app, "anna@alpha.example", "Second", 2).await;
    let c = ticket_from(&app, "bob@beta.example", "Elsewhere", 3).await;
    assert_eq!(link(&app, &c, &a, "child").await.0, StatusCode::CREATED);
    let (status, merged) = api(
        &app,
        Method::POST,
        &format!("/tickets/{a}/merge"),
        Some(json!({ "target_id": b })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{merged}");
    assert!(links(&app, &c).await["children"]
        .as_array()
        .unwrap()
        .is_empty());
    assert!(links(&app, &a).await["parent"].is_null());
}

fn update(action: &str, extra: Value) -> Value {
    let mut b = json!({ "action": action });
    for (k, v) in extra.as_object().unwrap() {
        b[k] = v.clone();
    }
    b
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_bundle_status_update_is_previewed_then_applied(db: PgPool) {
    let app = setup(db).await;
    let p = ticket_from(&app, "anna@alpha.example", "Outage", 1).await;
    let c1 = ticket_from(&app, "bob@beta.example", "No water", 2).await;
    let c2 = ticket_from(&app, "cy@gamma.example", "No power", 3).await;
    for c in [&c1, &c2] {
        assert_eq!(link(&app, &p, c, "child").await.0, StatusCode::CREATED);
    }
    // c2 is already in the target status: it is left out, not an error.
    let (_, d) = api(&app, Method::GET, &format!("/tickets/{c2}"), None).await;
    let body = json!({
        "subject": d["ticket"]["subject"], "status": "pending_internal", "priority": d["ticket"]["priority"],
        "category": d["ticket"]["category"], "language": d["ticket"]["language"],
        "contact_name": d["ticket"]["contact_name"], "contact_email": d["ticket"]["contact_email"],
        "customer_id": d["ticket"]["customer_id"],
    });
    let (status, saved) = api(&app, Method::PUT, &format!("/tickets/{c2}"), Some(body)).await;
    assert_eq!(status, StatusCode::OK, "{saved}");

    let (status, preview) = api(
        &app,
        Method::POST,
        &format!("/tickets/{p}/bundle/update"),
        Some(update(
            "status",
            json!({ "status": "pending_internal", "dry_run": true }),
        )),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{preview}");
    assert_eq!(preview["dry_run"], true);
    assert_eq!(preview["updated"], 1);
    let outcomes: Vec<&str> = preview["items"]
        .as_array()
        .unwrap()
        .iter()
        .map(|i| i["outcome"].as_str().unwrap())
        .collect();
    assert_eq!(outcomes, ["would_apply", "skipped"]);
    // The preview changed nothing.
    let (_, still) = api(&app, Method::GET, &format!("/tickets/{c1}"), None).await;
    assert_eq!(still["ticket"]["status"], "new");

    let (status, done) = api(
        &app,
        Method::POST,
        &format!("/tickets/{p}/bundle/update"),
        Some(update("status", json!({ "status": "pending_internal" }))),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{done}");
    assert_eq!(done["items"][0]["outcome"], "applied");
    let (_, now) = api(&app, Method::GET, &format!("/tickets/{c1}"), None).await;
    assert_eq!(now["ticket"]["status"], "pending_internal");
    // The parent records what was done.
    let (_, parent) = api(&app, Method::GET, &format!("/tickets/{p}"), None).await;
    let last = parent["articles"]
        .as_array()
        .unwrap()
        .last()
        .unwrap()
        .clone();
    assert!(
        last["body"].as_str().unwrap().contains("Bundle update"),
        "{last}"
    );
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_bundle_reply_goes_to_each_customer_and_a_refusal_stops_only_that_child(db: PgPool) {
    let app = setup(db.clone()).await;
    let p = ticket_from(&app, "anna@alpha.example", "Outage", 1).await;
    let c1 = ticket_from(&app, "bob@beta.example", "No water", 2).await;
    let c2 = ticket_from(&app, "cy@gamma.example", "No power", 3).await;
    for c in [&c1, &c2] {
        assert_eq!(link(&app, &p, c, "child").await.0, StatusCode::CREATED);
    }
    // Take away c2's recipient (no contact address, no customer to fall back on).
    sqlx::query(
        "UPDATE helpdesk.tickets SET contact_email = '', customer_id = NULL WHERE id = $1::uuid",
    )
    .bind(&c2)
    .execute(&db)
    .await
    .unwrap();

    let (_, c1_now) = api(&app, Method::GET, &format!("/tickets/{c1}"), None).await;
    let articles_before = c1_now["articles"].as_array().unwrap().len();
    let (status, preview) = api(
        &app,
        Method::POST,
        &format!("/tickets/{p}/bundle/update"),
        Some(update(
            "reply",
            json!({ "body": "We are on it.", "dry_run": true }),
        )),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{preview}");
    let first = &preview["items"][0];
    assert_eq!(first["outcome"], "would_apply");
    assert_eq!(preview["items"][1]["outcome"], "failed");
    assert!(
        preview["items"][1]["reason"]
            .as_str()
            .unwrap()
            .contains("recipient"),
        "{preview}"
    );
    assert_eq!(preview["updated"], 1);
    assert!(
        first["recipient"].as_str().unwrap().contains('@'),
        "{first}"
    );
    let (_, after_preview) = api(&app, Method::GET, &format!("/tickets/{c1}"), None).await;
    assert_eq!(
        after_preview["articles"].as_array().unwrap().len(),
        articles_before,
        "a preview sends nothing"
    );
    assert_eq!(after_preview["ticket"]["status"], "new");

    let (status, done) = api(
        &app,
        Method::POST,
        &format!("/tickets/{p}/bundle/update"),
        Some(update("reply", json!({ "body": "We are on it." }))),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{done}");
    assert_eq!(done["items"][0]["outcome"], "applied");
    assert_eq!(done["items"][1]["outcome"], "failed", "{done}");
    let (_, after) = api(&app, Method::GET, &format!("/tickets/{c1}"), None).await;
    let out = after["articles"]
        .as_array()
        .unwrap()
        .iter()
        .find(|a| a["kind"] == "email_out")
        .expect("queued reply")
        .clone();
    assert_eq!(out["delivery"], "queued");
    assert_eq!(after["ticket"]["status"], "pending_customer");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_bundle_update_is_validated(db: PgPool) {
    let app = setup(db).await;
    let p = ticket_from(&app, "anna@alpha.example", "Lonely", 1).await;
    let c = ticket_from(&app, "bob@beta.example", "Child", 2).await;
    let stranger = ticket_from(&app, "cy@gamma.example", "Stranger", 3).await;
    let url = format!("/tickets/{p}/bundle/update");
    // No bundle yet.
    let (status, _) = api(
        &app,
        Method::POST,
        &url,
        Some(update("note", json!({ "body": "x" }))),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(link(&app, &p, &c, "child").await.0, StatusCode::CREATED);
    for bad in [
        update("note", json!({ "body": "  " })),
        update("reply", json!({})),
        update("status", json!({})),
        update("status", json!({ "status": "bogus" })),
        update("note", json!({ "body": "x", "child_ids": [stranger] })),
    ] {
        let (status, r) = api(&app, Method::POST, &url, Some(bad.clone())).await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{bad}: {r}");
    }
    // Without the helpdesk write permission nothing goes out.
    let (status, _) = call(
        &app,
        VIEWER,
        Method::POST,
        &format!("/api/v1{url}"),
        Some(update("reply", json!({ "body": "x" }))),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
}
