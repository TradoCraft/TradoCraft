//! Chatter on records (ADR 0086): notes, change messages, followers, activities, inbox,
//! permissions and company boundaries.

mod common;

use axum::http::{Method, StatusCode};
use common::{call, setup};
use serde_json::{json, Value};
use sqlx::PgPool;
use uuid::Uuid;

const ADMIN: &str = "admin@example.com";
const SALES: &str = "sales@example.com";
const VIEWER: &str = "viewer@example.com"; // read-only
const TECH: &str = "technician@example.com"; // no customers.read
const OTHER: &str = "sales@other.example"; // sales in another company
const SALES_ID: &str = "00000000-0000-7000-8000-000000000102";
const VIEWER_ID: &str = "00000000-0000-7000-8000-000000000103";
const OTHER_COMPANY: &str = "00000000-0000-7000-8000-0000000fff01";
const ZONE: &str = "00000000-0000-7000-8000-000000000202";

async fn send(
    app: &axum::Router,
    user: &str,
    method: Method,
    uri: &str,
    body: Option<Value>,
) -> (StatusCode, Value) {
    call(app, user, method, &format!("/api/v1{uri}"), body).await
}

/// A second company with one sales user; returns the user id.
async fn add_other_company_user(db: &PgPool) -> Uuid {
    sqlx::query("INSERT INTO core.companies (id, name) VALUES ($1::uuid, 'Other BV')")
        .bind(OTHER_COMPANY)
        .execute(db)
        .await
        .unwrap();
    let id = Uuid::now_v7();
    sqlx::query("INSERT INTO core.users (id, email, display_name) VALUES ($1, $2, 'Other')")
        .bind(id)
        .bind(OTHER)
        .execute(db)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO core.user_companies (user_id, company_id, roles, is_default)
         VALUES ($1, $2::uuid, '{sales}', true)",
    )
    .bind(id)
    .bind(OTHER_COMPANY)
    .execute(db)
    .await
    .unwrap();
    id
}

async fn customer(app: &axum::Router, code: &str) -> String {
    let (s, c) = send(
        app,
        ADMIN,
        Method::POST,
        "/customers",
        Some(
            json!({"code": code, "name": format!("Customer {code}"), "country_code": "BE",
                    "city": "Gent", "price_zone_id": ZONE, "discount_percent": "0"}),
        ),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED, "{c}");
    c["id"].as_str().unwrap().to_string()
}

fn items(v: &Value) -> &Vec<Value> {
    v["items"].as_array().unwrap()
}

#[sqlx::test(migrations = "../../migrations")]
async fn notes_are_posted_listed_edited_and_deleted(db: PgPool) {
    let app = setup(db).await;
    let c = customer(&app, "CH-1").await;
    let base = format!("/chatter/customer/{c}");

    let (s, n) = send(
        &app,
        SALES,
        Method::POST,
        &format!("{base}/notes"),
        Some(json!({"body": "  Called, will confirm Friday  "})),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED, "{n}");
    assert_eq!(n["body"], "Called, will confirm Friday");
    assert_eq!(n["kind"], "note");
    assert_eq!(n["editable"], true);
    let id = n["id"].as_str().unwrap().to_string();

    // A colleague sees it, but cannot change it.
    let (s, page) = send(&app, ADMIN, Method::GET, &format!("{base}/thread"), None).await;
    assert_eq!(s, StatusCode::OK);
    assert_eq!(items(&page).len(), 1);
    assert_eq!(items(&page)[0]["editable"], false);
    let (s, _) = send(
        &app,
        ADMIN,
        Method::PATCH,
        &format!("/chatter/notes/{id}"),
        Some(json!({"body": "x"})),
    )
    .await;
    assert_eq!(s, StatusCode::FORBIDDEN);

    let (s, e) = send(
        &app,
        SALES,
        Method::PATCH,
        &format!("/chatter/notes/{id}"),
        Some(json!({"body": "Confirmed"})),
    )
    .await;
    assert_eq!(s, StatusCode::OK, "{e}");
    assert_eq!(e["body"], "Confirmed");
    assert!(e["edited_at"].is_string());

    let (s, _) = send(
        &app,
        SALES,
        Method::DELETE,
        &format!("/chatter/notes/{id}"),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::NO_CONTENT);
    let (_, page) = send(&app, ADMIN, Method::GET, &format!("{base}/thread"), None).await;
    assert!(items(&page).is_empty());
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_note_cannot_be_changed_after_the_window(db: PgPool) {
    let app = setup(db.clone()).await;
    let c = customer(&app, "CH-2").await;
    let (_, n) = send(
        &app,
        SALES,
        Method::POST,
        &format!("/chatter/customer/{c}/notes"),
        Some(json!({"body": "old"})),
    )
    .await;
    let id = n["id"].as_str().unwrap();
    sqlx::query("UPDATE chatter.messages SET created_at = now() - interval '20 minutes'")
        .execute(&db)
        .await
        .unwrap();
    let (s, _) = send(
        &app,
        SALES,
        Method::PATCH,
        &format!("/chatter/notes/{id}"),
        Some(json!({"body": "new"})),
    )
    .await;
    assert_eq!(s, StatusCode::FORBIDDEN);
}

#[sqlx::test(migrations = "../../migrations")]
async fn posting_is_idempotent_and_validated(db: PgPool) {
    let app = setup(db).await;
    let c = customer(&app, "CH-3").await;
    let uri = format!("/chatter/customer/{c}/notes");
    let cid = Uuid::now_v7().to_string();
    let (s1, a) = send(
        &app,
        SALES,
        Method::POST,
        &uri,
        Some(json!({"body": "once", "client_id": cid})),
    )
    .await;
    let (s2, b) = send(
        &app,
        SALES,
        Method::POST,
        &uri,
        Some(json!({"body": "once", "client_id": cid})),
    )
    .await;
    assert_eq!((s1, s2), (StatusCode::CREATED, StatusCode::OK));
    assert_eq!(a["id"], b["id"]);
    let (_, page) = send(
        &app,
        SALES,
        Method::GET,
        &format!("/chatter/customer/{c}/thread"),
        None,
    )
    .await;
    assert_eq!(items(&page).len(), 1);

    for body in ["", "   "] {
        let (s, _) = send(&app, SALES, Method::POST, &uri, Some(json!({"body": body}))).await;
        assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);
    }
    let (s, _) = send(
        &app,
        SALES,
        Method::POST,
        &uri,
        Some(json!({"body": "x".repeat(10_001)})),
    )
    .await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);
    let (s, _) = send(
        &app,
        SALES,
        Method::POST,
        &format!("/chatter/ticket/{c}/notes"),
        Some(json!({"body": "x"})),
    )
    .await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_thread_pages_newest_first(db: PgPool) {
    let app = setup(db).await;
    let c = customer(&app, "CH-4").await;
    for i in 1..=5 {
        send(
            &app,
            SALES,
            Method::POST,
            &format!("/chatter/customer/{c}/notes"),
            Some(json!({"body": format!("n{i}")})),
        )
        .await;
    }
    let (_, p1) = send(
        &app,
        SALES,
        Method::GET,
        &format!("/chatter/customer/{c}/thread?limit=2"),
        None,
    )
    .await;
    assert_eq!(items(&p1)[0]["body"], "n5");
    assert_eq!(items(&p1)[1]["body"], "n4");
    let next = p1["next_before_id"].as_str().unwrap();
    let (_, p2) = send(
        &app,
        SALES,
        Method::GET,
        &format!("/chatter/customer/{c}/thread?limit=10&before_id={next}"),
        None,
    )
    .await;
    let bodies: Vec<_> = items(&p2)
        .iter()
        .map(|i| i["body"].as_str().unwrap())
        .collect();
    assert_eq!(bodies, ["n3", "n2", "n1"]);
    assert!(p2["next_before_id"].is_null());
}

#[sqlx::test(migrations = "../../migrations")]
async fn permissions_and_company_boundaries(db: PgPool) {
    add_other_company_user(&db).await;
    let app = setup(db).await;
    let c = customer(&app, "CH-5").await;
    let base = format!("/chatter/customer/{c}");
    // read-only viewer reads but cannot post, schedule or add followers
    let (s, _) = send(&app, VIEWER, Method::GET, &format!("{base}/thread"), None).await;
    assert_eq!(s, StatusCode::OK);
    let (s, _) = send(
        &app,
        VIEWER,
        Method::POST,
        &format!("{base}/notes"),
        Some(json!({"body": "x"})),
    )
    .await;
    assert_eq!(s, StatusCode::FORBIDDEN);
    let (s, _) = send(&app, VIEWER, Method::POST, &format!("{base}/activities"),
        Some(json!({"kind": "call", "summary": "x", "assignee_id": VIEWER_ID, "due_date": "2030-01-01"}))).await;
    assert_eq!(s, StatusCode::FORBIDDEN);
    let (s, _) = send(
        &app,
        VIEWER,
        Method::POST,
        &format!("{base}/followers"),
        Some(json!({"user_id": SALES_ID})),
    )
    .await;
    assert_eq!(s, StatusCode::FORBIDDEN);
    // but may follow herself
    let (s, f) = send(&app, VIEWER, Method::PUT, &format!("{base}/follow"), None).await;
    assert_eq!(s, StatusCode::OK, "{f}");
    assert_eq!(f["following"], true);
    // no customers.read: nothing
    let (s, _) = send(&app, TECH, Method::GET, &format!("{base}/thread"), None).await;
    assert_eq!(s, StatusCode::FORBIDDEN);
    // unknown record: 404
    let (s, _) = send(
        &app,
        ADMIN,
        Method::GET,
        &format!("/chatter/quotation/{}/thread", Uuid::now_v7()),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::NOT_FOUND);

    // another company sees an empty thread of the shared customer, and cannot read our notes
    send(
        &app,
        SALES,
        Method::POST,
        &format!("{base}/notes"),
        Some(json!({"body": "ours"})),
    )
    .await;
    let (s, page) = send(&app, OTHER, Method::GET, &format!("{base}/thread"), None).await;
    assert_eq!(s, StatusCode::OK);
    assert!(items(&page).is_empty());
    let (_, ours) = send(&app, SALES, Method::GET, &format!("{base}/thread"), None).await;
    let nid = items(&ours)[0]["id"].as_str().unwrap();
    let (s, _) = send(
        &app,
        OTHER,
        Method::DELETE,
        &format!("/chatter/notes/{nid}"),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::NOT_FOUND);
}

#[sqlx::test(migrations = "../../migrations")]
async fn followers_follow_and_unfollow(db: PgPool) {
    let other_id = add_other_company_user(&db).await;
    let app = setup(db).await;
    let c = customer(&app, "CH-6").await;
    let base = format!("/chatter/customer/{c}");
    // posting follows automatically
    send(
        &app,
        SALES,
        Method::POST,
        &format!("{base}/notes"),
        Some(json!({"body": "hi"})),
    )
    .await;
    let (_, f) = send(&app, SALES, Method::GET, &format!("{base}/followers"), None).await;
    assert_eq!(f["following"], true);
    assert_eq!(items(&f)[0]["reason"], "author");
    // unfollow, then posting again resumes
    let (_, f) = send(&app, SALES, Method::DELETE, &format!("{base}/follow"), None).await;
    assert_eq!(f["following"], false);
    send(
        &app,
        SALES,
        Method::POST,
        &format!("{base}/notes"),
        Some(json!({"body": "again"})),
    )
    .await;
    let (_, f) = send(&app, SALES, Method::GET, &format!("{base}/followers"), None).await;
    assert_eq!(f["following"], true);
    // add a colleague; a stranger from another company is refused
    let (s, f) = send(
        &app,
        SALES,
        Method::POST,
        &format!("{base}/followers"),
        Some(json!({"user_id": VIEWER_ID})),
    )
    .await;
    assert_eq!(s, StatusCode::OK, "{f}");
    assert_eq!(items(&f).len(), 2);
    let (s, _) = send(
        &app,
        SALES,
        Method::POST,
        &format!("{base}/followers"),
        Some(json!({"user_id": other_id})),
    )
    .await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);
    let (_, f) = send(
        &app,
        SALES,
        Method::DELETE,
        &format!("{base}/followers/{VIEWER_ID}"),
        None,
    )
    .await;
    assert_eq!(items(&f).len(), 1);
}

#[sqlx::test(migrations = "../../migrations")]
async fn activities_are_scheduled_completed_and_logged(db: PgPool) {
    let app = setup(db).await;
    let c = customer(&app, "CH-7").await;
    let base = format!("/chatter/customer/{c}");
    let (s, a) = send(
        &app,
        ADMIN,
        Method::POST,
        &format!("{base}/activities"),
        Some(
            json!({"kind": "call", "summary": "Call back", "assignee_id": SALES_ID,
                    "due_date": "2020-01-01"}),
        ),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED, "{a}");
    assert_eq!(a["overdue"], true);
    assert_eq!(a["assignee_name"].is_string(), true);
    let aid = a["id"].as_str().unwrap().to_string();
    let (s, _) = send(&app, ADMIN, Method::POST, &format!("{base}/activities"),
        Some(json!({"kind": "call", "summary": " ", "assignee_id": SALES_ID, "due_date": "2030-01-01"}))).await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);

    let (_, list) = send(
        &app,
        VIEWER,
        Method::GET,
        &format!("{base}/activities"),
        None,
    )
    .await;
    assert_eq!(list.as_array().unwrap().len(), 1);

    // the assignee follows and finds it in the inbox
    let (_, inbox) = send(&app, SALES, Method::GET, "/chatter/inbox", None).await;
    assert_eq!(inbox["activities"].as_array().unwrap().len(), 1);
    assert_eq!(inbox["activities"][0]["label"], "Customer CH-7");

    // a third person cannot delete it; the creator can complete it
    let (s, _) = send(
        &app,
        VIEWER,
        Method::DELETE,
        &format!("/chatter/activities/{aid}"),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::FORBIDDEN);
    let (s, _) = send(
        &app,
        SALES,
        Method::POST,
        &format!("/chatter/activities/{aid}/done"),
        Some(json!({"note": "spoke to them"})),
    )
    .await;
    assert_eq!(s, StatusCode::NO_CONTENT);
    let (_, list) = send(
        &app,
        SALES,
        Method::GET,
        &format!("{base}/activities"),
        None,
    )
    .await;
    assert!(list.as_array().unwrap().is_empty());
    let (_, page) = send(&app, ADMIN, Method::GET, &format!("{base}/thread"), None).await;
    let m = &items(&page)[0];
    assert_eq!(m["kind"], "system");
    assert_eq!(m["body"], "spoke to them");
    assert_eq!(m["changes"][0]["field"], "activity_done");
    // already done: gone
    let (s, _) = send(
        &app,
        SALES,
        Method::POST,
        &format!("/chatter/activities/{aid}/done"),
        Some(json!({})),
    )
    .await;
    assert_eq!(s, StatusCode::NOT_FOUND);
}

#[sqlx::test(migrations = "../../migrations")]
async fn saving_a_customer_logs_tracked_fields_only(db: PgPool) {
    let app = setup(db).await;
    let c = customer(&app, "CH-8").await;
    let (_, cur) = send(&app, ADMIN, Method::GET, &format!("/customers/{c}"), None).await;
    let mut body = json!({"code": "CH-8", "name": "Renamed", "country_code": "BE", "city": "Brugge",
        "price_zone_id": ZONE, "discount_percent": "0", "expected_version": cur["version"]});
    body["language"] = cur["language"].clone();
    let (s, r) = send(
        &app,
        ADMIN,
        Method::PUT,
        &format!("/customers/{c}"),
        Some(body),
    )
    .await;
    assert_eq!(s, StatusCode::OK, "{r}");
    let (_, page) = send(
        &app,
        VIEWER,
        Method::GET,
        &format!("/chatter/customer/{c}/thread"),
        None,
    )
    .await;
    assert_eq!(items(&page).len(), 1);
    let fields: Vec<_> = items(&page)[0]["changes"]
        .as_array()
        .unwrap()
        .iter()
        .map(|c| c["field"].as_str().unwrap())
        .collect();
    assert_eq!(fields, ["name"]); // the city change is audited, not shown
                                  // saving without a tracked change adds nothing
    let (_, cur) = send(&app, ADMIN, Method::GET, &format!("/customers/{c}"), None).await;
    let body = json!({"code": "CH-8", "name": "Renamed", "country_code": "BE", "city": "Gent",
        "price_zone_id": ZONE, "discount_percent": "0", "expected_version": cur["version"],
        "language": cur["language"]});
    send(
        &app,
        ADMIN,
        Method::PUT,
        &format!("/customers/{c}"),
        Some(body),
    )
    .await;
    let (_, page) = send(
        &app,
        VIEWER,
        Method::GET,
        &format!("/chatter/customer/{c}/thread"),
        None,
    )
    .await;
    assert_eq!(items(&page).len(), 1);
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_inbox_lists_unread_threads_of_followed_records(db: PgPool) {
    let app = setup(db).await;
    let c = customer(&app, "CH-9").await;
    let base = format!("/chatter/customer/{c}");
    send(&app, VIEWER, Method::PUT, &format!("{base}/follow"), None).await;
    send(
        &app,
        SALES,
        Method::POST,
        &format!("{base}/notes"),
        Some(json!({"body": "news"})),
    )
    .await;
    let (_, inbox) = send(&app, VIEWER, Method::GET, "/chatter/inbox", None).await;
    assert_eq!(inbox["unread"][0]["unread"], 1);
    assert_eq!(inbox["unread"][0]["label"], "Customer CH-9");
    // the author's own note is never unread for the author
    let (_, mine) = send(&app, SALES, Method::GET, "/chatter/inbox", None).await;
    assert!(mine["unread"].as_array().unwrap().is_empty());
    let (s, _) = send(&app, VIEWER, Method::POST, &format!("{base}/read"), None).await;
    assert_eq!(s, StatusCode::NO_CONTENT);
    let (_, inbox) = send(&app, VIEWER, Method::GET, "/chatter/inbox", None).await;
    assert!(inbox["unread"].as_array().unwrap().is_empty());
}
