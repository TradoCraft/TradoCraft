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
    assert!(a["assignee_name"].is_string());
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

#[sqlx::test(migrations = "../../migrations")]
async fn opportunities_log_stage_changes_and_carry_a_chatter(db: PgPool) {
    let app = setup(db).await;
    let c = customer(&app, "CH-10").await;
    let (s, o) = send(
        &app,
        SALES,
        Method::POST,
        "/opportunities",
        Some(json!({"title": "Tower", "customer_id": c})),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED, "{o}");
    let id = o["id"].as_str().unwrap();
    let (s, r) = send(
        &app,
        SALES,
        Method::POST,
        &format!("/opportunities/{id}/stage"),
        Some(json!({"stage": "lost", "lost_reason": "too expensive"})),
    )
    .await;
    assert_eq!(s, StatusCode::OK, "{r}");
    let base = format!("/chatter/opportunity/{id}");
    let (s, page) = send(&app, VIEWER, Method::GET, &format!("{base}/thread"), None).await;
    assert_eq!(s, StatusCode::OK, "{page}");
    let m = &items(&page)[0];
    assert_eq!(m["changes"][0]["field"], "stage");
    assert_eq!(m["changes"][0]["to"], "lost");
    assert_eq!(m["body"], "too expensive");
    let (s, _) = send(
        &app,
        SALES,
        Method::POST,
        &format!("{base}/notes"),
        Some(json!({"body": "ok"})),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED);
    // the live channel accepts the kind
    let (s, _) = send(&app, TECH, Method::GET, &format!("{base}/thread"), None).await;
    assert_eq!(s, StatusCode::FORBIDDEN);
}

fn png() -> Vec<u8> {
    let mut b = vec![0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A];
    b.extend_from_slice(&[0; 32]);
    b
}

async fn upload(app: &axum::Router, user: &str, base: &str, name: &str) -> (StatusCode, Value) {
    common::call_raw(
        app,
        user,
        &format!("/api/v1{base}/files?filename={name}"),
        "application/octet-stream",
        png(),
    )
    .await
}

#[sqlx::test(migrations = "../../migrations")]
async fn files_are_uploaded_linked_listed_and_downloaded(db: PgPool) {
    let app = setup(db).await;
    let c = customer(&app, "CH-11").await;
    let base = format!("/chatter/customer/{c}");

    let (s, f) = upload(&app, SALES, &base, "plan.png").await;
    assert_eq!(s, StatusCode::CREATED, "{f}");
    let fid = f["id"].as_str().unwrap().to_string();
    assert_eq!(f["content_type"], "image/png");

    // Until it is on a note only the uploader can fetch it.
    let get = |user: &'static str, fid: String| {
        let app = app.clone();
        let uri = format!("/api/v1{base}/files/{fid}");
        async move { common::raw(&app, common::Who::Staff(user), Method::GET, &uri, None).await }
    };
    assert_eq!(get(SALES, fid.clone()).await.0, StatusCode::OK);
    assert_eq!(get(ADMIN, fid.clone()).await.0, StatusCode::NOT_FOUND);

    // Linking: another user's pending file, an unknown file and too many files are refused.
    let (s, _) = send(
        &app,
        ADMIN,
        Method::POST,
        &format!("{base}/notes"),
        Some(json!({"body": "x", "file_ids": [fid]})),
    )
    .await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);
    let (s, _) = send(
        &app,
        SALES,
        Method::POST,
        &format!("{base}/notes"),
        Some(json!({"body": "x", "file_ids": [Uuid::now_v7()]})),
    )
    .await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);

    let (s, n) = send(
        &app,
        SALES,
        Method::POST,
        &format!("{base}/notes"),
        Some(json!({"body": "Drawing attached", "file_ids": [fid]})),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED, "{n}");
    assert_eq!(n["files"][0]["filename"], "plan.png");

    // A file is used once.
    let (s, _) = send(
        &app,
        SALES,
        Method::POST,
        &format!("{base}/notes"),
        Some(json!({"body": "again", "file_ids": [fid]})),
    )
    .await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);

    // Now every reader sees it in the thread and can download it; the bytes are the upload.
    let (_, page) = send(&app, VIEWER, Method::GET, &format!("{base}/thread"), None).await;
    assert_eq!(items(&page)[0]["files"][0]["id"], fid.as_str());
    let (s, headers, bytes) = get(VIEWER, fid.clone()).await;
    assert_eq!(s, StatusCode::OK);
    assert_eq!(bytes, png());
    assert_eq!(headers["cache-control"], "private, no-store");
    assert!(headers["content-disposition"]
        .to_str()
        .unwrap()
        .contains("plan.png"));

    // It belongs to this record only, and to this company.
    let other = customer(&app, "CH-12").await;
    let (s, ..) = common::raw(
        &app,
        common::Who::Staff(SALES),
        Method::GET,
        &format!("/api/v1/chatter/customer/{other}/files/{fid}"),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::NOT_FOUND);

    // Deleting the note takes the link with it.
    let nid = n["id"].as_str().unwrap();
    let (s, _) = send(
        &app,
        SALES,
        Method::DELETE,
        &format!("/chatter/notes/{nid}"),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::NO_CONTENT);
    assert_eq!(get(SALES, fid).await.0, StatusCode::NOT_FOUND);
}

#[sqlx::test(migrations = "../../migrations")]
async fn uploads_are_checked_and_need_write_permission(db: PgPool) {
    let app = setup(db).await;
    let c = customer(&app, "CH-13").await;
    let base = format!("/chatter/customer/{c}");
    let (s, _) = upload(&app, VIEWER, &base, "a.png").await;
    assert_eq!(s, StatusCode::FORBIDDEN);
    let (s, _) = common::call_raw(
        &app,
        SALES,
        &format!("/api/v1{base}/files?filename=a.exe"),
        "application/octet-stream",
        b"MZ not an image".to_vec(),
    )
    .await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);
    let (s, _) = common::call_raw(
        &app,
        SALES,
        &format!("/api/v1{base}/files"),
        "application/octet-stream",
        Vec::new(),
    )
    .await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);
    // a retried upload with the same client id is the same file
    let cid = Uuid::now_v7();
    let uri = format!("/api/v1{base}/files?client_id={cid}");
    let (s1, a) = common::call_raw(&app, SALES, &uri, "application/octet-stream", png()).await;
    let (s2, b) = common::call_raw(&app, SALES, &uri, "application/octet-stream", png()).await;
    assert_eq!((s1, s2), (StatusCode::CREATED, StatusCode::CREATED));
    assert_eq!(a["id"], b["id"]);
    // but not on another record
    let other = customer(&app, "CH-14").await;
    let (s, _) = common::call_raw(
        &app,
        SALES,
        &format!("/api/v1/chatter/customer/{other}/files?client_id={cid}"),
        "application/octet-stream",
        png(),
    )
    .await;
    assert_eq!(s, StatusCode::CONFLICT);
}

#[sqlx::test(migrations = "../../migrations")]
async fn an_activity_can_be_changed_and_handed_over(db: PgPool) {
    let app = setup(db).await;
    let c = customer(&app, "CH-15").await;
    let base = format!("/chatter/customer/{c}");
    let (_, a) = send(
        &app,
        ADMIN,
        Method::POST,
        &format!("{base}/activities"),
        Some(
            json!({"kind": "todo", "summary": "Prepare", "assignee_id": SALES_ID,
                    "due_date": "2030-01-01"}),
        ),
    )
    .await;
    let aid = a["id"].as_str().unwrap();
    let uri = format!("/chatter/activities/{aid}");
    // a third person cannot change it
    let (s, _) = send(
        &app,
        VIEWER,
        Method::PATCH,
        &uri,
        Some(json!({"summary": "x"})),
    )
    .await;
    assert_eq!(s, StatusCode::FORBIDDEN);
    // the assignee can
    let (s, r) = send(
        &app,
        SALES,
        Method::PATCH,
        &uri,
        Some(json!({"summary": " Prepare quote ", "kind": "meeting",
                    "due_date": "2031-02-03T00:00:00.000", "note": "bring samples"})),
    )
    .await;
    assert_eq!(s, StatusCode::OK, "{r}");
    assert_eq!(r["summary"], "Prepare quote");
    assert_eq!(r["kind"], "meeting");
    assert_eq!(r["due_date"], "2031-02-03");
    assert_eq!(r["note"], "bring samples");
    // validation
    for body in [
        json!({"summary": ""}),
        json!({"assignee_id": Uuid::now_v7()}),
    ] {
        let (s, _) = send(&app, SALES, Method::PATCH, &uri, Some(body)).await;
        assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);
    }
    // handing it to the viewer
    let (s, r) = send(
        &app,
        SALES,
        Method::PATCH,
        &uri,
        Some(json!({"assignee_id": VIEWER_ID})),
    )
    .await;
    assert_eq!(s, StatusCode::OK, "{r}");
    assert_eq!(r["assignee_id"], VIEWER_ID);
    let (_, f) = send(&app, ADMIN, Method::GET, &format!("{base}/followers"), None).await;
    assert!(items(&f).iter().any(|x| x["user_id"] == VIEWER_ID));
}

async fn mails(db: &PgPool, to: &str) -> Vec<(String, String)> {
    sqlx::query_as("SELECT subject, body FROM core.mail_outbox WHERE to_address = $1 ORDER BY id")
        .bind(to)
        .fetch_all(db)
        .await
        .unwrap()
}

#[sqlx::test(migrations = "../../migrations")]
async fn the_assignee_of_an_activity_gets_one_mail(db: PgPool) {
    let app = setup(db.clone()).await;
    let c = customer(&app, "CH-16").await;
    let base = format!("/chatter/customer/{c}");
    let body = |summary: &str, to: &str| {
        json!({"kind": "call", "summary": summary,
        "assignee_id": to, "due_date": "2030-05-06"})
    };
    // to oneself: no mail
    send(
        &app,
        SALES,
        Method::POST,
        &format!("{base}/activities"),
        Some(body("Mine", SALES_ID)),
    )
    .await;
    assert!(mails(&db, SALES).await.is_empty());
    // to a colleague: one mail with the record, kind, summary and date
    send(
        &app,
        SALES,
        Method::POST,
        &format!("{base}/activities"),
        Some(body("Ring them", VIEWER_ID)),
    )
    .await;
    let m = mails(&db, VIEWER).await;
    assert_eq!(m.len(), 1, "{m:?}");
    assert!(
        m[0].0.contains("Customer CH-16") && m[0].0.contains("Ring them"),
        "{m:?}"
    );
    assert!(m[0].1.contains("06/05/2030"), "{m:?}");
    // a second one within ten minutes is not mailed again
    let (s, a) = send(
        &app,
        SALES,
        Method::POST,
        &format!("{base}/activities"),
        Some(body("And again", VIEWER_ID)),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED, "{a}");
    assert_eq!(mails(&db, VIEWER).await.len(), 1);
    // after the window it is
    sqlx::query("UPDATE chatter.followers SET last_notified_at = now() - interval '11 minutes'")
        .execute(&db)
        .await
        .unwrap();
    send(
        &app,
        SALES,
        Method::POST,
        &format!("{base}/activities"),
        Some(body("Later", VIEWER_ID)),
    )
    .await;
    assert_eq!(mails(&db, VIEWER).await.len(), 2);
}

#[sqlx::test(migrations = "../../migrations")]
async fn rows_of_deleted_records_and_stale_uploads_are_removed(db: PgPool) {
    let app = setup(db.clone()).await;
    let c = customer(&app, "CH-17").await;
    let keep = customer(&app, "CH-18").await;
    for rec in [&c, &keep] {
        let base = format!("/chatter/customer/{rec}");
        send(
            &app,
            SALES,
            Method::POST,
            &format!("{base}/notes"),
            Some(json!({"body": "n"})),
        )
        .await;
        send(&app, SALES, Method::POST, &format!("{base}/activities"),
            Some(json!({"kind": "todo", "summary": "a", "assignee_id": SALES_ID, "due_date": "2030-01-01"}))).await;
    }
    let keep_base = format!("/chatter/customer/{keep}");
    let (s, unshared) = upload(&app, SALES, &keep_base, "old.png").await;
    assert_eq!(s, StatusCode::CREATED);
    let (s, shared) = upload(&app, SALES, &keep_base, "shared.png").await;
    assert_eq!(s, StatusCode::CREATED);
    // Another table keeps using one of the files; the pass must find that out from the catalog.
    sqlx::query("CREATE TABLE public.file_refs_test (file_id uuid REFERENCES core.files(id))")
        .execute(&db)
        .await
        .unwrap();
    sqlx::query("INSERT INTO public.file_refs_test VALUES ($1::uuid)")
        .bind(shared["id"].as_str().unwrap())
        .execute(&db)
        .await
        .unwrap();
    assert_eq!(tradocraft_chatter::remove_orphans(&db).await.unwrap(), 0);

    // age the uploads and delete one customer; the pass must remove its rows and the uploads
    sqlx::query("UPDATE chatter.message_files SET created_at = now() - interval '2 days'")
        .execute(&db)
        .await
        .unwrap();
    sqlx::query("DELETE FROM crm.customer_terms WHERE customer_id = $1::uuid")
        .bind(&c)
        .execute(&db)
        .await
        .unwrap();
    sqlx::query("DELETE FROM crm.customers WHERE id = $1::uuid")
        .bind(&c)
        .execute(&db)
        .await
        .unwrap();
    let removed = tradocraft_chatter::remove_orphans(&db).await.unwrap();
    // the note, the activity and the follower of the deleted customer, and the two stale uploads
    assert_eq!(removed, 5);
    for table in ["messages", "activities", "followers"] {
        let n: i64 = sqlx::query_scalar(sqlx::AssertSqlSafe(format!(
            "SELECT count(*) FROM chatter.{table} WHERE record_id = $1::uuid"
        )))
        .bind(&c)
        .fetch_one(&db)
        .await
        .unwrap();
        assert_eq!(n, 0, "{table} of the deleted customer");
    }
    let left: i64 = sqlx::query_scalar("SELECT count(*) FROM chatter.message_files")
        .fetch_one(&db)
        .await
        .unwrap();
    assert_eq!(left, 0, "the stale pending uploads are gone");
    let stored = |id: String| {
        let db = db.clone();
        async move {
            sqlx::query_scalar::<_, i64>("SELECT count(*) FROM core.files WHERE id = $1::uuid")
                .bind(id)
                .fetch_one(&db)
                .await
                .unwrap()
        }
    };
    assert_eq!(
        stored(unshared["id"].as_str().unwrap().to_string()).await,
        0,
        "an upload nothing else uses loses its stored file"
    );
    assert_eq!(
        stored(shared["id"].as_str().unwrap().to_string()).await,
        1,
        "a file another table references is kept"
    );
    assert_eq!(tradocraft_chatter::remove_orphans(&db).await.unwrap(), 0);
    let (_, page) = send(
        &app,
        SALES,
        Method::GET,
        &format!("/chatter/customer/{keep}/thread"),
        None,
    )
    .await;
    assert_eq!(items(&page).len(), 1, "the other record is untouched");
}

#[sqlx::test(migrations = "../../migrations")]
async fn saving_quotations_and_orders_logs_their_tracked_fields(db: PgPool) {
    let app = setup(db).await;
    const UNIT_100: &str = "00000000-0000-7000-8000-000000000301";
    const ALPHA: &str = "00000000-0000-7000-8000-000000000401";
    let (s, q) = send(
        &app,
        SALES,
        Method::POST,
        "/quotations",
        Some(json!({"customer_id": ALPHA, "lines": [{"product_id": UNIT_100, "quantity": "1"}]})),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED, "{q}");
    let qid = q["id"].as_str().unwrap();
    // doubling the quantity changes the total
    let (s, r) = send(
        &app,
        SALES,
        Method::PUT,
        &format!("/quotations/{qid}"),
        Some(
            json!({"customer_id": ALPHA, "expected_version": q["version"],
                    "lines": [{"product_id": UNIT_100, "quantity": "2"}]}),
        ),
    )
    .await;
    assert_eq!(s, StatusCode::OK, "{r}");
    let (_, page) = send(
        &app,
        VIEWER,
        Method::GET,
        &format!("/chatter/quotation/{qid}/thread"),
        None,
    )
    .await;
    let fields: Vec<String> = items(&page)
        .iter()
        .flat_map(|m| m["changes"].as_array().unwrap().iter())
        .map(|c| c["field"].as_str().unwrap().to_string())
        .collect();
    assert!(fields.contains(&"total".to_string()), "{fields:?}");
    // sending it adds a status message, converting gives an order that logs an edit
    send(
        &app,
        SALES,
        Method::POST,
        &format!("/quotations/{qid}/send"),
        None,
    )
    .await;
    let (s, o) = send(
        &app,
        SALES,
        Method::POST,
        &format!("/quotations/{qid}/convert"),
        Some(json!({"customer_reference": "PO-1"})),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED, "{o}");
    let oid = o["order"]["id"].as_str().unwrap();
    let (s, e) = send(
        &app,
        SALES,
        Method::PUT,
        &format!("/orders/{oid}"),
        Some(json!({"customer_reference": "PO-2", "lines": [{"position": 1, "quantity": "4"}]})),
    )
    .await;
    assert_eq!(s, StatusCode::OK, "{e}");
    let (_, page) = send(
        &app,
        VIEWER,
        Method::GET,
        &format!("/chatter/order/{oid}/thread"),
        None,
    )
    .await;
    let fields: Vec<String> = items(&page)
        .iter()
        .flat_map(|m| m["changes"].as_array().unwrap().iter())
        .map(|c| c["field"].as_str().unwrap().to_string())
        .collect();
    assert!(fields.contains(&"total".to_string()), "{fields:?}");
    assert!(
        fields.contains(&"customer_reference".to_string()),
        "{fields:?}"
    );
}

#[sqlx::test(migrations = "../../migrations")]
async fn an_upload_never_adopts_a_file_that_is_not_its_own(db: PgPool) {
    let app = setup(db.clone()).await;
    let c = customer(&app, "CH-19").await;
    let base = format!("/chatter/customer/{c}");
    // a stored file that belongs to something else (here: nothing in the chatter)
    let foreign = Uuid::now_v7();
    sqlx::query(
        "INSERT INTO core.files (id, company_id, filename, content_type, size_bytes, uploader_name, storage_key)
         VALUES ($1, '00000000-0000-7000-8000-000000000001', 'secret.pdf', 'application/pdf', 5, 'x', 'k')",
    )
    .bind(foreign)
    .execute(&db)
    .await
    .unwrap();
    let (s, _) = common::call_raw(
        &app,
        SALES,
        &format!("/api/v1{base}/files?client_id={foreign}"),
        "application/octet-stream",
        png(),
    )
    .await;
    assert_eq!(s, StatusCode::CONFLICT);
    let linked: i64 = sqlx::query_scalar("SELECT count(*) FROM chatter.message_files")
        .fetch_one(&db)
        .await
        .unwrap();
    assert_eq!(linked, 0, "nothing was linked to the record");
}

#[sqlx::test(migrations = "../../migrations")]
async fn an_assignee_or_follower_must_be_able_to_read_the_record(db: PgPool) {
    const TECH_ID: &str = "00000000-0000-7000-8000-000000000107"; // no customers.read
    let app = setup(db.clone()).await;
    let c = customer(&app, "CH-20").await;
    let base = format!("/chatter/customer/{c}");
    let (s, r) = send(
        &app,
        ADMIN,
        Method::POST,
        &format!("{base}/activities"),
        Some(
            json!({"kind": "call", "summary": "Secret", "assignee_id": TECH_ID,
                    "due_date": "2030-01-01"}),
        ),
    )
    .await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY, "{r}");
    let (s, _) = send(
        &app,
        ADMIN,
        Method::POST,
        &format!("{base}/followers"),
        Some(json!({"user_id": TECH_ID})),
    )
    .await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);
    let mail: i64 = sqlx::query_scalar("SELECT count(*) FROM core.mail_outbox")
        .fetch_one(&db)
        .await
        .unwrap();
    assert_eq!(mail, 0, "nothing about the record was mailed");
    // handing an existing activity to such a user is refused the same way
    let (_, a) = send(
        &app,
        ADMIN,
        Method::POST,
        &format!("{base}/activities"),
        Some(
            json!({"kind": "call", "summary": "Fine", "assignee_id": SALES_ID,
                    "due_date": "2030-01-01"}),
        ),
    )
    .await;
    let (s, _) = send(
        &app,
        ADMIN,
        Method::PATCH,
        &format!("/chatter/activities/{}", a["id"].as_str().unwrap()),
        Some(json!({"assignee_id": TECH_ID})),
    )
    .await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);
}

#[sqlx::test(migrations = "../../migrations")]
async fn a_note_is_only_editable_while_its_author_may_write(db: PgPool) {
    let app = setup(db.clone()).await;
    let c = customer(&app, "CH-21").await;
    let base = format!("/chatter/customer/{c}");
    send(
        &app,
        SALES,
        Method::POST,
        &format!("{base}/notes"),
        Some(json!({"body": "mine"})),
    )
    .await;
    let (_, page) = send(&app, SALES, Method::GET, &format!("{base}/thread"), None).await;
    assert_eq!(items(&page)[0]["editable"], true);
    // the author is demoted to the read-only role
    sqlx::query("UPDATE core.user_companies SET roles = '{viewer}' WHERE user_id = $1::uuid")
        .bind(SALES_ID)
        .execute(&db)
        .await
        .unwrap();
    let (s, page) = send(&app, SALES, Method::GET, &format!("{base}/thread"), None).await;
    assert_eq!(s, StatusCode::OK);
    assert_eq!(items(&page)[0]["editable"], false);
}

#[sqlx::test(migrations = "../../migrations")]
async fn requests_racing_with_one_client_id_make_one_row(db: PgPool) {
    let app = setup(db.clone()).await;
    let c = customer(&app, "CH-22").await;
    let base = format!("/chatter/customer/{c}");
    let cid = Uuid::now_v7().to_string();
    let note = json!({"body": "race", "client_id": cid});
    let results = futures_join(
        send(
            &app,
            SALES,
            Method::POST,
            &format!("{base}/notes"),
            Some(note.clone()),
        ),
        send(
            &app,
            SALES,
            Method::POST,
            &format!("{base}/notes"),
            Some(note),
        ),
    )
    .await;
    let mut codes = [results.0 .0.as_u16(), results.1 .0.as_u16()];
    codes.sort();
    assert_eq!(codes, [200, 201], "{results:?}");
    assert_eq!(results.0 .1["id"], results.1 .1["id"]);
    let n: i64 = sqlx::query_scalar("SELECT count(*) FROM chatter.messages WHERE kind = 'note'")
        .fetch_one(&db)
        .await
        .unwrap();
    assert_eq!(n, 1);

    let cid = Uuid::now_v7().to_string();
    let act = json!({"kind": "call", "summary": "race", "assignee_id": VIEWER_ID,
                     "due_date": "2030-01-01", "client_id": cid});
    let results = futures_join(
        send(
            &app,
            SALES,
            Method::POST,
            &format!("{base}/activities"),
            Some(act.clone()),
        ),
        send(
            &app,
            SALES,
            Method::POST,
            &format!("{base}/activities"),
            Some(act),
        ),
    )
    .await;
    let mut codes = [results.0 .0.as_u16(), results.1 .0.as_u16()];
    codes.sort();
    assert_eq!(codes, [200, 201], "{results:?}");
    let n: i64 = sqlx::query_scalar("SELECT count(*) FROM chatter.activities")
        .fetch_one(&db)
        .await
        .unwrap();
    assert_eq!(n, 1);
    assert_eq!(mails(&db, VIEWER).await.len(), 1, "one mail, not two");
}

/// Runs two futures at the same time.
async fn futures_join<A, B>(a: A, b: B) -> (A::Output, B::Output)
where
    A: std::future::Future,
    B: std::future::Future,
{
    tokio::join!(a, b)
}
