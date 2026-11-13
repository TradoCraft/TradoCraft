//! To-do items (ADR 0061): privacy between users, hand-over to a colleague, two levels, completion
//! rules, links and their permission gating, idempotent create, reorder, audit, module switch.

mod common;

use axum::http::{Method, StatusCode};
use common::{call, setup};
use serde_json::{json, Value};
use sqlx::PgPool;
use uuid::Uuid;

const ADMIN: &str = "admin@example.com";
const SALES: &str = "sales@example.com"; // role sales: reads quotations
const VIEWER: &str = "viewer@example.com"; // read-only: no to-do list
const TECH: &str = "technician@example.com"; // role technician: no quotations.read
const OTHER: &str = "sales@other.example"; // role sales in another company
const OTHER_COMPANY: &str = "00000000-0000-7000-8000-0000000fff01";
const COMPANY: &str = "00000000-0000-7000-8000-000000000001";
const SALES_ID: &str = "00000000-0000-7000-8000-000000000102";
const TECH_ID: &str = "00000000-0000-7000-8000-000000000107";
const QUOTE: &str = "00000000-0000-7000-8000-000000000999";

async fn send(
    app: &axum::Router,
    user: &str,
    method: Method,
    uri: &str,
    body: Option<Value>,
) -> (StatusCode, Value) {
    call(app, user, method, &format!("/api/v1{uri}"), body).await
}
async fn get(app: &axum::Router, user: &str, uri: &str) -> (StatusCode, Value) {
    send(app, user, Method::GET, uri, None).await
}
async fn post(app: &axum::Router, user: &str, uri: &str, b: Value) -> (StatusCode, Value) {
    send(app, user, Method::POST, uri, Some(b)).await
}
async fn post_empty(app: &axum::Router, user: &str, uri: &str) -> (StatusCode, Value) {
    send(app, user, Method::POST, uri, None).await
}
async fn patch(app: &axum::Router, user: &str, uri: &str, b: Value) -> (StatusCode, Value) {
    send(app, user, Method::PATCH, uri, Some(b)).await
}
async fn delete(app: &axum::Router, user: &str, uri: &str) -> StatusCode {
    send(app, user, Method::DELETE, uri, None).await.0
}

async fn add_other_company_user(db: &PgPool) {
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
}

/// Creates an item and returns its id.
async fn item(app: &axum::Router, user: &str, body: Value) -> String {
    let (status, v) = post(app, user, "/todo/items", body).await;
    assert_eq!(status, StatusCode::CREATED, "{v}");
    v["id"].as_str().unwrap().to_string()
}

async fn list(app: &axum::Router, user: &str, query: &str) -> Vec<Value> {
    let (status, v) = get(app, user, &format!("/todo/items{query}")).await;
    assert_eq!(status, StatusCode::OK, "{v}");
    v.as_array().unwrap().clone()
}

fn titles(items: &[Value]) -> Vec<String> {
    items
        .iter()
        .map(|i| i["title"].as_str().unwrap().to_string())
        .collect()
}

async fn audit_actions(db: &PgPool, id: &str) -> Vec<String> {
    sqlx::query_scalar(
        "SELECT action FROM audit.events WHERE entity = 'todo' AND entity_id = $1::uuid ORDER BY id",
    )
    .bind(id)
    .fetch_all(db)
    .await
    .unwrap()
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn create_read_update_delete_with_sub_items(db: PgPool) {
    let app = setup(db.clone()).await;
    let (status, a) = post(
        &app,
        SALES,
        "/todo/items",
        json!({ "title": "  Call Peeters  ", "notes": "about the offer", "due_date": "2030-01-31" }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{a}");
    assert_eq!(a["title"], "Call Peeters");
    assert_eq!(a["notes"], "about the offer");
    assert_eq!(a["due_date"], "2030-01-31");
    assert_eq!(a["done"], false);
    assert_eq!(a["mine"], true);
    assert_eq!(a["owner_id"], SALES_ID);
    assert!(a["assignee_id"].is_null() && a["parent_id"].is_null());
    let a_id = a["id"].as_str().unwrap().to_string();
    let b_id = item(&app, SALES, json!({ "title": "Second" })).await;
    let sub = item(&app, SALES, json!({ "title": "Sub", "parent_id": a_id })).await;

    // Flat list: roots first (by position), then sub-items.
    let all = list(&app, SALES, "").await;
    assert_eq!(titles(&all), ["Call Peeters", "Second", "Sub"]);
    assert_eq!(all[2]["parent_id"], a_id.as_str());
    assert_eq!(all[2]["owner_id"], SALES_ID);

    let (status, updated) = patch(
        &app,
        SALES,
        &format!("/todo/items/{a_id}"),
        json!({ "title": "Call Mr Peeters", "clear_due_date": true, "notes": "" }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{updated}");
    assert_eq!(updated["title"], "Call Mr Peeters");
    assert!(updated["due_date"].is_null());
    assert_eq!(updated["notes"], "");

    // Validation.
    for body in [
        json!({ "title": "  " }),
        json!({ "title": "x".repeat(201) }),
    ] {
        assert_eq!(
            post(&app, SALES, "/todo/items", body).await.0,
            StatusCode::UNPROCESSABLE_ENTITY
        );
    }
    assert_eq!(
        patch(
            &app,
            SALES,
            &format!("/todo/items/{a_id}"),
            json!({ "title": "" })
        )
        .await
        .0,
        StatusCode::UNPROCESSABLE_ENTITY
    );

    // Delete removes the sub-items with their parent (cascade).
    assert_eq!(
        delete(&app, SALES, &format!("/todo/items/{a_id}")).await,
        StatusCode::NO_CONTENT
    );
    assert_eq!(titles(&list(&app, SALES, "").await), ["Second"]);
    let gone: i64 = sqlx::query_scalar("SELECT count(*) FROM todo.items WHERE id = $1::uuid")
        .bind(&sub)
        .fetch_one(&db)
        .await
        .unwrap();
    assert_eq!(gone, 0);
    assert_eq!(
        delete(&app, SALES, &format!("/todo/items/{a_id}")).await,
        StatusCode::NOT_FOUND
    );
    let _ = b_id;

    // Every mutation is in the audit trail, without the private text.
    assert_eq!(
        audit_actions(&db, &a_id).await,
        ["created", "updated", "deleted"]
    );
    let data: Value = sqlx::query_scalar(
        "SELECT data FROM audit.events WHERE entity_id = $1::uuid AND action = 'updated'",
    )
    .bind(&a_id)
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(data["text_changed"], json!(["title", "notes"]));
    assert_eq!(data["changes"]["due_date"]["from"], "2030-01-31");
    let all_events: String = sqlx::query_scalar(
        "SELECT string_agg(data::text, ' ') FROM audit.events WHERE entity = 'todo'",
    )
    .fetch_one(&db)
    .await
    .unwrap();
    assert!(!all_events.contains("Peeters"), "{all_events}");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn items_are_private_and_isolated_per_company(db: PgPool) {
    let app = setup(db.clone()).await;
    add_other_company_user(&db).await;
    let id = item(&app, SALES, json!({ "title": "Private" })).await;

    // A colleague of the same company, even an admin, and a user of another company all get 404.
    for user in [ADMIN, TECH, OTHER] {
        assert!(
            list(&app, user, "?scope=all-mine").await.is_empty(),
            "{user}"
        );
        let uri = format!("/todo/items/{id}");
        assert_eq!(
            patch(&app, user, &uri, json!({ "title": "x" })).await.0,
            StatusCode::NOT_FOUND
        );
        assert_eq!(delete(&app, user, &uri).await, StatusCode::NOT_FOUND);
        assert_eq!(
            post_empty(&app, user, &format!("{uri}/complete")).await.0,
            StatusCode::NOT_FOUND
        );
        assert_eq!(
            post_empty(&app, user, &format!("{uri}/reopen")).await.0,
            StatusCode::NOT_FOUND
        );
        // Cannot hang a sub-item under it either.
        assert_eq!(
            post(
                &app,
                user,
                "/todo/items",
                json!({ "title": "s", "parent_id": id })
            )
            .await
            .0,
            StatusCode::NOT_FOUND
        );
        assert_eq!(
            post(&app, user, "/todo/items/reorder", json!({ "ids": [id] }))
                .await
                .0,
            StatusCode::NOT_FOUND
        );
    }
    // Counts never include other people's items.
    let (_, counts) = get(&app, ADMIN, "/todo/items/counts").await;
    assert_eq!(counts["open"], 0);
    assert_eq!(list(&app, SALES, "").await.len(), 1);

    // An assignee outside the company is refused.
    let other_id: String = sqlx::query_scalar("SELECT id::text FROM core.users WHERE email = $1")
        .bind(OTHER)
        .fetch_one(&db)
        .await
        .unwrap();
    assert_eq!(
        post(
            &app,
            SALES,
            "/todo/items",
            json!({ "title": "x", "assignee_id": other_id })
        )
        .await
        .0,
        StatusCode::UNPROCESSABLE_ENTITY
    );
    // Neither may a parent of another company be reached through the database.
    let foreign: Uuid = Uuid::now_v7();
    sqlx::query("INSERT INTO todo.items (id, company_id, title, owner_id, created_by) SELECT $1, $2::uuid, 'F', id, id FROM core.users WHERE email = $3")
        .bind(foreign)
        .bind(OTHER_COMPANY)
        .bind(OTHER)
        .execute(&db)
        .await
        .unwrap();
    let res = sqlx::query("INSERT INTO todo.items (id, company_id, parent_id, title, owner_id, created_by) VALUES ($1, $2::uuid, $3, 'C', $4::uuid, $4::uuid)")
        .bind(Uuid::now_v7())
        .bind(COMPANY)
        .bind(foreign)
        .bind(SALES_ID)
        .execute(&db)
        .await;
    assert!(res.is_err(), "a parent of another company is rejected");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_assignee_sees_and_completes_but_the_owner_keeps_control(db: PgPool) {
    let app = setup(db.clone()).await;
    let id = item(
        &app,
        SALES,
        json!({ "title": "Prepare the visit", "assignee_id": TECH_ID }),
    )
    .await;
    let sub = item(
        &app,
        SALES,
        json!({ "title": "Pack tools", "parent_id": id }),
    )
    .await;

    // On the technician's plate, delegated from the owner's.
    let mine = list(&app, TECH, "").await;
    assert_eq!(titles(&mine), ["Prepare the visit", "Pack tools"]);
    assert_eq!(mine[0]["assignee_name"], "Tom Technician");
    assert_eq!(mine[0]["mine"], false);
    assert_eq!(
        mine[1]["assignee_id"], TECH_ID,
        "sub-items follow the parent"
    );
    assert!(list(&app, SALES, "").await.is_empty());
    assert_eq!(list(&app, SALES, "?scope=assigned").await.len(), 2);
    assert_eq!(list(&app, SALES, "?scope=all-mine").await.len(), 2);
    assert_eq!(list(&app, TECH, "?scope=assigned").await.len(), 0);

    // The assignee edits and completes, reopens...
    let uri = format!("/todo/items/{sub}");
    assert_eq!(
        patch(&app, TECH, &uri, json!({ "title": "Pack all tools" }))
            .await
            .0,
        StatusCode::OK
    );
    let (status, done) = post_empty(&app, TECH, &format!("{uri}/complete")).await;
    assert_eq!(status, StatusCode::OK, "{done}");
    assert_eq!(done["done"], true);
    assert!(done["done_at"].is_string());
    assert_eq!(done["done_by"], TECH_ID);
    assert_eq!(
        post_empty(&app, TECH, &format!("{uri}/reopen")).await.1["done"],
        false
    );
    // ...but cannot hand it on, take it, or delete it.
    let root = format!("/todo/items/{id}");
    assert_eq!(
        patch(&app, TECH, &root, json!({ "clear_assignee": true }))
            .await
            .0,
        StatusCode::FORBIDDEN
    );
    assert_eq!(
        patch(&app, TECH, &root, json!({ "assignee_id": SALES_ID }))
            .await
            .0,
        StatusCode::FORBIDDEN
    );
    assert_eq!(delete(&app, TECH, &root).await, StatusCode::FORBIDDEN);

    // The owner takes it back; the sub-item follows and the technician loses sight of both.
    let (status, back) = patch(&app, SALES, &root, json!({ "clear_assignee": true })).await;
    assert_eq!(status, StatusCode::OK, "{back}");
    assert!(back["assignee_id"].is_null());
    assert!(list(&app, TECH, "?scope=all-mine").await.is_empty());
    assert_eq!(list(&app, SALES, "").await.len(), 2);
    // Assigning to oneself is no hand-over.
    let (_, same) = patch(&app, SALES, &root, json!({ "assignee_id": SALES_ID })).await;
    assert!(same["assignee_id"].is_null());
    // A sub-item cannot be handed over on its own.
    assert_eq!(
        patch(&app, SALES, &uri, json!({ "assignee_id": TECH_ID }))
            .await
            .0,
        StatusCode::UNPROCESSABLE_ENTITY
    );
    // Re-assign: the children follow.
    patch(&app, SALES, &root, json!({ "assignee_id": TECH_ID })).await;
    assert_eq!(list(&app, TECH, "").await.len(), 2);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn two_levels_and_moves(db: PgPool) {
    let app = setup(db.clone()).await;
    let a = item(&app, SALES, json!({ "title": "A" })).await;
    let b = item(&app, SALES, json!({ "title": "B" })).await;
    let a1 = item(&app, SALES, json!({ "title": "A1", "parent_id": a })).await;

    // No third level.
    let (status, _) = post(
        &app,
        SALES,
        "/todo/items",
        json!({ "title": "x", "parent_id": a1 }),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    // A sub-item takes no assignee of its own.
    let (status, _) = post(
        &app,
        SALES,
        "/todo/items",
        json!({ "title": "x", "parent_id": a, "assignee_id": TECH_ID }),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    // Moving a root with sub-items under another root would make a third level.
    let (status, _) = patch(
        &app,
        SALES,
        &format!("/todo/items/{a}"),
        json!({ "parent_id": b }),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    // Not its own parent; not under a sub-item.
    let (status, _) = patch(
        &app,
        SALES,
        &format!("/todo/items/{b}"),
        json!({ "parent_id": b }),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    let (status, _) = patch(
        &app,
        SALES,
        &format!("/todo/items/{b}"),
        json!({ "parent_id": a1 }),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    // Move a leaf under another root, then up to the top again.
    let (status, moved) = patch(
        &app,
        SALES,
        &format!("/todo/items/{a1}"),
        json!({ "parent_id": b }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{moved}");
    assert_eq!(moved["parent_id"], b.as_str());
    let (status, up) = patch(
        &app,
        SALES,
        &format!("/todo/items/{a1}"),
        json!({ "make_root": true }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{up}");
    assert!(up["parent_id"].is_null());
    // Now a plain root, B can take it as a sub-item and A can no longer be a third level.
    let (status, _) = patch(
        &app,
        SALES,
        &format!("/todo/items/{a}"),
        json!({ "parent_id": b }),
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    // The database enforces the same: a sub-item of a sub-item.
    let res = sqlx::query(
        "INSERT INTO todo.items (id, company_id, parent_id, title, owner_id, created_by)
         VALUES ($1, $2::uuid, $3::uuid, 'deep', $4::uuid, $4::uuid)",
    )
    .bind(Uuid::now_v7())
    .bind(COMPANY)
    .bind(&a)
    .bind(SALES_ID)
    .execute(&db)
    .await;
    assert!(res.is_err());

    // Under an item of another owner: refused.
    let t = item(&app, TECH, json!({ "title": "T" })).await;
    let (status, _) = patch(
        &app,
        SALES,
        &format!("/todo/items/{a1}"),
        json!({ "parent_id": t }),
    )
    .await;
    assert_eq!(
        status,
        StatusCode::NOT_FOUND,
        "the other owner's item is invisible"
    );
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn completing_a_parent_asks_and_reopening_a_child_reopens_the_parent(db: PgPool) {
    let app = setup(db.clone()).await;
    let p = item(&app, SALES, json!({ "title": "Parent" })).await;
    let c1 = item(&app, SALES, json!({ "title": "C1", "parent_id": p })).await;
    let c2 = item(&app, SALES, json!({ "title": "C2", "parent_id": p })).await;
    post_empty(&app, SALES, &format!("/todo/items/{c1}/complete")).await;

    // Open children and no flag: 409 with a stable code; nothing changed.
    for body in [
        None,
        Some(json!({})),
        Some(json!({ "complete_children": false })),
    ] {
        let (status, v) = send(
            &app,
            SALES,
            Method::POST,
            &format!("/todo/items/{p}/complete"),
            body,
        )
        .await;
        assert_eq!(status, StatusCode::CONFLICT, "{v}");
        assert_eq!(v["code"], "open_sub_items");
    }
    let open = list(&app, SALES, "?done=false").await;
    assert_eq!(titles(&open), ["Parent", "C2"]);

    // With the flag, the open children are completed too.
    let (status, v) = post(
        &app,
        SALES,
        &format!("/todo/items/{p}/complete"),
        json!({ "complete_children": true }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{v}");
    assert_eq!(v["done"], true);
    assert!(list(&app, SALES, "?done=false").await.is_empty());
    assert_eq!(list(&app, SALES, "?done=true").await.len(), 3);
    assert_eq!(audit_actions(&db, &p).await, ["created", "completed"]);
    let completed: Value = sqlx::query_scalar(
        "SELECT data FROM audit.events WHERE entity_id = $1::uuid AND action = 'completed'",
    )
    .bind(&p)
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(
        completed["completed_sub_items"].as_array().unwrap().len(),
        1
    );
    // Completing again is a no-op.
    assert_eq!(
        post_empty(&app, SALES, &format!("/todo/items/{p}/complete"))
            .await
            .0,
        StatusCode::OK
    );
    assert_eq!(audit_actions(&db, &p).await, ["created", "completed"]);

    // Reopening a child reopens its done parent, and the sibling stays done.
    let (status, v) = post_empty(&app, SALES, &format!("/todo/items/{c2}/reopen")).await;
    assert_eq!(status, StatusCode::OK, "{v}");
    assert_eq!(v["done"], false);
    let all = list(&app, SALES, "").await;
    let done: Vec<bool> = all.iter().map(|i| i["done"].as_bool().unwrap()).collect();
    assert_eq!(titles(&all), ["Parent", "C1", "C2"]);
    assert_eq!(done, [false, true, false]);
    assert_eq!(
        audit_actions(&db, &p).await,
        ["created", "completed", "reopened"]
    );
    // A leaf without children completes without a flag; reopening a root keeps children done.
    post_empty(&app, SALES, &format!("/todo/items/{c2}/complete")).await;
    post_empty(&app, SALES, &format!("/todo/items/{p}/complete")).await;
    let (_, v) = post_empty(&app, SALES, &format!("/todo/items/{p}/reopen")).await;
    assert_eq!(v["done"], false);
    assert_eq!(list(&app, SALES, "?done=true").await.len(), 2);

    // A new open sub-item under a done parent reopens it.
    post_empty(&app, SALES, &format!("/todo/items/{p}/complete")).await;
    item(&app, SALES, json!({ "title": "C3", "parent_id": p })).await;
    let root = list(&app, SALES, "?done=false").await;
    assert_eq!(titles(&root), ["Parent", "C3"]);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn links_need_the_read_permission_and_the_label_follows_it(db: PgPool) {
    let app = setup(db.clone()).await;
    // The technician may not read quotations: cannot link one.
    let (status, _) = post(
        &app,
        TECH,
        "/todo/items",
        json!({ "title": "x", "link_kind": "quotation", "link_id": QUOTE, "link_label": "Q-1" }),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    // ...but jobs, yes.
    let (status, job) = post(
        &app,
        TECH,
        "/todo/items",
        json!({ "title": "Job note", "link_kind": "job", "link_id": QUOTE,
                "link_label": "J-9 Pump", "link_location": "/field/jobs/x" }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{job}");
    assert_eq!(job["link_kind"], "job");
    assert_eq!(job["link_label"], "J-9 Pump");
    assert_eq!(job["link_location"], "/field/jobs/x");

    // Sales links a quotation and hands the item to the technician.
    let id = item(
        &app,
        SALES,
        json!({ "title": "Follow up", "assignee_id": TECH_ID, "link_kind": "quotation",
                "link_id": QUOTE, "link_label": "Q-2027-001 Acme", "link_location": "/quotations/x" }),
    )
    .await;
    let mine = list(&app, SALES, "?scope=assigned").await;
    assert_eq!(mine[0]["link_label"], "Q-2027-001 Acme");
    // The technician sees that there is a link but not what it says.
    let theirs = list(&app, TECH, "").await;
    let seen = theirs.iter().find(|i| i["id"] == id.as_str()).unwrap();
    assert_eq!(seen["link_kind"], "quotation");
    assert!(seen["link_label"].is_null());
    // ...and may not re-link it to something they may not read, but may unlink it.
    let uri = format!("/todo/items/{id}");
    assert_eq!(
        patch(
            &app,
            TECH,
            &uri,
            json!({ "link_kind": "customer", "link_id": QUOTE })
        )
        .await
        .0,
        StatusCode::FORBIDDEN
    );
    let (status, cleared) = patch(&app, TECH, &uri, json!({ "clear_link": true })).await;
    assert_eq!(status, StatusCode::OK);
    assert!(cleared["link_kind"].is_null() && cleared["link_id"].is_null());
    assert!(cleared["link_location"].is_null());

    // Filter by link.
    let (status, _) = get(
        &app,
        SALES,
        "/todo/items?link_id=00000000-0000-7000-8000-000000000999",
    )
    .await;
    assert_eq!(
        status,
        StatusCode::UNPROCESSABLE_ENTITY,
        "link_id needs link_kind"
    );
    let q = format!("?scope=all-mine&link_kind=job&link_id={QUOTE}");
    assert!(list(&app, SALES, &q).await.is_empty());
    assert_eq!(list(&app, TECH, &q).await.len(), 1);

    // Malformed links.
    for body in [
        json!({ "title": "x", "link_kind": "quotation" }),
        json!({ "title": "x", "link_id": QUOTE }),
        json!({ "title": "x", "link_label": "orphan label" }),
        json!({ "title": "x", "link_kind": "quotation", "link_id": QUOTE, "link_location": "https://evil.example" }),
        json!({ "title": "x", "link_kind": "quotation", "link_id": QUOTE, "link_location": "//evil.example" }),
        json!({ "title": "x", "link_kind": "quotation", "link_id": QUOTE, "link_label": "l".repeat(201) }),
    ] {
        assert_eq!(
            post(&app, SALES, "/todo/items", body.clone()).await.0,
            StatusCode::UNPROCESSABLE_ENTITY,
            "{body}"
        );
    }
    let (status, _) = post(
        &app,
        SALES,
        "/todo/items",
        json!({ "title": "x", "link_kind": "spaceship", "link_id": QUOTE }),
    )
    .await;
    assert!(status.is_client_error());

    // The database enforces the pair and the list of kinds as well.
    for (kind, link_id) in [
        (Some("quotation"), None::<&str>),
        (None, Some(QUOTE)),
        (Some("spaceship"), Some(QUOTE)),
    ] {
        let res = sqlx::query(
            "INSERT INTO todo.items (id, company_id, title, owner_id, created_by, link_kind, link_id)
             VALUES ($1, $2::uuid, 't', $3::uuid, $3::uuid, $4, $5::uuid)",
        )
        .bind(Uuid::now_v7())
        .bind(COMPANY)
        .bind(SALES_ID)
        .bind(kind)
        .bind(link_id)
        .execute(&db)
        .await;
        assert!(res.is_err(), "{kind:?} {link_id:?}");
    }
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_repeated_create_returns_the_existing_item(db: PgPool) {
    let app = setup(db.clone()).await;
    let client_id = Uuid::now_v7().to_string();
    let body = json!({ "title": "Once", "client_id": client_id });
    let (status, first) = post(&app, SALES, "/todo/items", body.clone()).await;
    assert_eq!(status, StatusCode::CREATED);
    let (status, again) = post(&app, SALES, "/todo/items", body.clone()).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(again["id"], first["id"]);
    assert_eq!(list(&app, SALES, "").await.len(), 1);
    assert_eq!(
        audit_actions(&db, first["id"].as_str().unwrap()).await,
        ["created"]
    );
    // Someone else's item under the same client_id is not revealed.
    let (status, _) = post(&app, TECH, "/todo/items", body).await;
    assert_eq!(status, StatusCode::CONFLICT);
    assert!(list(&app, TECH, "").await.is_empty());
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn reorder_keeps_hidden_items_in_place(db: PgPool) {
    let app = setup(db.clone()).await;
    let a = item(&app, SALES, json!({ "title": "A" })).await;
    let b = item(&app, SALES, json!({ "title": "B" })).await;
    let c = item(&app, SALES, json!({ "title": "C" })).await;
    let d = item(&app, SALES, json!({ "title": "D" })).await;
    assert_eq!(titles(&list(&app, SALES, "").await), ["A", "B", "C", "D"]);

    let (status, _) = post(
        &app,
        SALES,
        "/todo/items/reorder",
        json!({ "ids": [d, c, b, a] }),
    )
    .await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    assert_eq!(titles(&list(&app, SALES, "").await), ["D", "C", "B", "A"]);
    assert_eq!(audit_actions(&db, &a).await, ["created", "reordered"]);

    // A subset (a hidden done item B) only trades the places of the listed ones.
    post_empty(&app, SALES, &format!("/todo/items/{b}/complete")).await;
    let (status, _) = post(
        &app,
        SALES,
        "/todo/items/reorder",
        json!({ "ids": [a, c, d] }),
    )
    .await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    assert_eq!(titles(&list(&app, SALES, "").await), ["A", "C", "B", "D"]);
    assert_eq!(
        titles(&list(&app, SALES, "?done=false").await),
        ["A", "C", "D"]
    );

    // Sub-items reorder within their parent; mixing parents is refused.
    let s1 = item(&app, SALES, json!({ "title": "S1", "parent_id": a })).await;
    let s2 = item(&app, SALES, json!({ "title": "S2", "parent_id": a })).await;
    let (status, _) = post(
        &app,
        SALES,
        "/todo/items/reorder",
        json!({ "parent_id": a, "ids": [s2, s1] }),
    )
    .await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    let subs: Vec<Value> = list(&app, SALES, "")
        .await
        .into_iter()
        .filter(|i| !i["parent_id"].is_null())
        .collect();
    assert_eq!(titles(&subs), ["S2", "S1"]);
    for body in [
        json!({ "ids": [a, s1] }),
        json!({ "parent_id": a, "ids": [c] }),
        json!({ "ids": [a, a] }),
    ] {
        assert_eq!(
            post(&app, SALES, "/todo/items/reorder", body.clone())
                .await
                .0,
            StatusCode::UNPROCESSABLE_ENTITY,
            "{body}"
        );
    }
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_list_is_for_roles_and_companies_that_have_it(db: PgPool) {
    let app = setup(db.clone()).await;
    // The read-only viewer has no to-do list.
    for (method, uri, body) in [
        (Method::GET, "/todo/items", None),
        (Method::GET, "/todo/items/counts", None),
        (Method::POST, "/todo/items", Some(json!({ "title": "x" }))),
        (
            Method::POST,
            "/todo/items/reorder",
            Some(json!({ "ids": [] })),
        ),
    ] {
        let (status, _) = send(&app, VIEWER, method, uri, body).await;
        assert_eq!(status, StatusCode::FORBIDDEN, "{uri}");
    }
    // The administrator has one.
    item(&app, ADMIN, json!({ "title": "Admin's" })).await;

    // Switching the module off removes it for everyone in the company; the data stays.
    let id = item(&app, SALES, json!({ "title": "Mine" })).await;
    sqlx::query("UPDATE core.companies SET disabled_modules = '{todo}'")
        .execute(&db)
        .await
        .unwrap();
    for user in [SALES, ADMIN] {
        let (status, v) = get(&app, user, "/todo/items").await;
        assert_eq!(status, StatusCode::FORBIDDEN, "{v}");
        assert!(v["message"]
            .as_str()
            .unwrap()
            .contains("module todo is disabled"));
        assert_eq!(
            patch(
                &app,
                user,
                &format!("/todo/items/{id}"),
                json!({ "title": "y" })
            )
            .await
            .0,
            StatusCode::FORBIDDEN
        );
        assert_eq!(
            delete(&app, user, &format!("/todo/items/{id}")).await,
            StatusCode::FORBIDDEN
        );
    }
    sqlx::query("UPDATE core.companies SET disabled_modules = '{}'")
        .execute(&db)
        .await
        .unwrap();
    assert_eq!(list(&app, SALES, "").await.len(), 1);

    // A user switched off individually.
    sqlx::query(
        "UPDATE core.user_companies SET disabled_modules = '{todo}' WHERE user_id = $1::uuid",
    )
    .bind(SALES_ID)
    .execute(&db)
    .await
    .unwrap();
    assert_eq!(
        get(&app, SALES, "/todo/items").await.0,
        StatusCode::FORBIDDEN
    );
    assert_eq!(get(&app, ADMIN, "/todo/items").await.0, StatusCode::OK);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn counts_cover_what_is_on_my_plate(db: PgPool) {
    let app = setup(db.clone()).await;
    let today: String = sqlx::query_scalar("SELECT CURRENT_DATE::text")
        .fetch_one(&db)
        .await
        .unwrap();
    let yesterday: String = sqlx::query_scalar("SELECT (CURRENT_DATE - 1)::text")
        .fetch_one(&db)
        .await
        .unwrap();
    let tomorrow: String = sqlx::query_scalar("SELECT (CURRENT_DATE + 1)::text")
        .fetch_one(&db)
        .await
        .unwrap();
    item(
        &app,
        SALES,
        json!({ "title": "late", "due_date": yesterday }),
    )
    .await;
    item(&app, SALES, json!({ "title": "today", "due_date": today })).await;
    item(
        &app,
        SALES,
        json!({ "title": "later", "due_date": tomorrow }),
    )
    .await;
    item(&app, SALES, json!({ "title": "undated" })).await;
    let done = item(
        &app,
        SALES,
        json!({ "title": "done", "due_date": yesterday }),
    )
    .await;
    post_empty(&app, SALES, &format!("/todo/items/{done}/complete")).await;
    // Handed to a colleague: on theirs, not on mine.
    item(
        &app,
        SALES,
        json!({ "title": "theirs", "due_date": yesterday, "assignee_id": TECH_ID }),
    )
    .await;

    let (status, c) = get(&app, SALES, "/todo/items/counts").await;
    assert_eq!(status, StatusCode::OK, "{c}");
    assert_eq!(c, json!({ "open": 4, "overdue": 1, "due_today": 1 }));
    let (_, c) = get(&app, TECH, "/todo/items/counts").await;
    assert_eq!(c, json!({ "open": 1, "overdue": 1, "due_today": 0 }));

    // due_before is strict and the done filter works.
    let before = list(&app, SALES, &format!("?due_before={today}")).await;
    assert_eq!(titles(&before), ["late", "done"]);
    assert_eq!(list(&app, SALES, "?done=true").await.len(), 1);
}
