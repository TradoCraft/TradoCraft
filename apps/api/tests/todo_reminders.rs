//! To-do counts, reminder settings and the reminder pass (ADR 0061, PR 3).

mod common;

use axum::http::{Method, StatusCode};
use common::{call, setup};
use serde_json::{json, Value};
use sqlx::PgPool;

const ADMIN: &str = "admin@example.com";
const SALES: &str = "sales@example.com"; // role sales: reads quotations
const VIEWER: &str = "viewer@example.com"; // read-only: no to-do list
const TECH: &str = "technician@example.com"; // role technician: no quotations.read
const COMPANY: &str = "00000000-0000-7000-8000-000000000001";
const SALES_ID: &str = "00000000-0000-7000-8000-000000000102";
const VIEWER_ID: &str = "00000000-0000-7000-8000-000000000103";
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
async fn patch(app: &axum::Router, user: &str, id: &str, b: Value) -> (StatusCode, Value) {
    send(
        app,
        user,
        Method::PATCH,
        &format!("/todo/items/{id}"),
        Some(b),
    )
    .await
}
async fn put_reminders(app: &axum::Router, user: &str, on: bool) -> (StatusCode, Value) {
    send(
        app,
        user,
        Method::PUT,
        "/todo/settings",
        Some(json!({ "email_reminders": on })),
    )
    .await
}

/// Creates an item and returns its id.
async fn item(app: &axum::Router, user: &str, body: Value) -> String {
    let (status, v) = send(app, user, Method::POST, "/todo/items", Some(body)).await;
    assert_eq!(status, StatusCode::CREATED, "{v}");
    v["id"].as_str().unwrap().to_string()
}

/// Moves an item's due date to `days` from the database's today (negative: overdue).
async fn due_in(db: &PgPool, id: &str, days: i32) {
    sqlx::query("UPDATE todo.items SET due_date = CURRENT_DATE + $2 WHERE id = $1::uuid")
        .bind(id)
        .bind(days)
        .execute(db)
        .await
        .unwrap();
}

async fn reminded(db: &PgPool, id: &str) -> bool {
    sqlx::query_scalar("SELECT reminded_at IS NOT NULL FROM todo.items WHERE id = $1::uuid")
        .bind(id)
        .fetch_one(db)
        .await
        .unwrap()
}

/// (to, subject, body) of every queued mail, oldest first.
async fn outbox(db: &PgPool) -> Vec<(String, String, String)> {
    sqlx::query_as("SELECT to_address, subject, body FROM core.mail_outbox ORDER BY created_at, id")
        .fetch_all(db)
        .await
        .unwrap()
}

async fn clear_outbox(db: &PgPool) {
    sqlx::query("DELETE FROM core.mail_outbox")
        .execute(db)
        .await
        .unwrap();
}

async fn remind(db: &PgPool) -> usize {
    tradocraft_todo::send_due_reminders(db).await.unwrap()
}

async fn counts(app: &axum::Router, user: &str) -> Value {
    let (status, v) = get(app, user, "/todo/items/counts").await;
    assert_eq!(status, StatusCode::OK, "{v}");
    v
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn counts_cover_root_items_on_my_plate_only(db: PgPool) {
    let app = setup(db.clone()).await;
    let overdue = item(&app, SALES, json!({ "title": "late" })).await;
    let today = item(&app, SALES, json!({ "title": "today" })).await;
    let _open = item(&app, SALES, json!({ "title": "no date" })).await;
    let sub = item(&app, SALES, json!({ "title": "sub", "parent_id": overdue })).await;
    let done = item(&app, SALES, json!({ "title": "done" })).await;
    let handed = item(&app, SALES, json!({ "title": "handed on" })).await;
    due_in(&db, &overdue, -3).await;
    due_in(&db, &sub, -3).await;
    due_in(&db, &today, 0).await;
    due_in(&db, &done, -1).await;
    due_in(&db, &handed, -1).await;
    let (status, _) = send(
        &app,
        SALES,
        Method::POST,
        &format!("/todo/items/{done}/complete"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (status, _) = patch(&app, SALES, &handed, json!({ "assignee_id": TECH_ID })).await;
    assert_eq!(status, StatusCode::OK);

    // Roots only: the sub-item, the finished item and the handed-on one do not count; the number
    // equals the open roots of the default list.
    assert_eq!(
        counts(&app, SALES).await,
        json!({ "open": 3, "overdue": 1, "due_today": 1 })
    );
    let (_, listed) = get(&app, SALES, "/todo/items?done=false").await;
    let roots = listed
        .as_array()
        .unwrap()
        .iter()
        .filter(|i| i["parent_id"].is_null())
        .count();
    assert_eq!(roots, 3);
    // It is on the plate of the colleague, who sees it as overdue.
    assert_eq!(
        counts(&app, TECH).await,
        json!({ "open": 1, "overdue": 1, "due_today": 0 })
    );
    // Nobody else's items leak in.
    assert_eq!(
        counts(&app, ADMIN).await,
        json!({ "open": 0, "overdue": 0, "due_today": 0 })
    );
    assert_eq!(
        get(&app, VIEWER, "/todo/items/counts").await.0,
        StatusCode::FORBIDDEN
    );
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn settings_default_on_belong_to_the_caller_and_are_audited(db: PgPool) {
    let app = setup(db.clone()).await;
    let (status, s) = get(&app, SALES, "/todo/settings").await;
    assert_eq!(status, StatusCode::OK, "{s}");
    assert_eq!(s["email_reminders"], true);

    let (status, s) = put_reminders(&app, SALES, false).await;
    assert_eq!(status, StatusCode::OK, "{s}");
    assert_eq!(s["email_reminders"], false);
    assert_eq!(
        get(&app, SALES, "/todo/settings").await.1["email_reminders"],
        false
    );
    // Someone else's setting is untouched.
    assert_eq!(
        get(&app, TECH, "/todo/settings").await.1["email_reminders"],
        true
    );
    assert_eq!(
        get(&app, ADMIN, "/todo/settings").await.1["email_reminders"],
        true
    );

    // Permission: the read-only viewer has no to-do list.
    assert_eq!(
        get(&app, VIEWER, "/todo/settings").await.0,
        StatusCode::FORBIDDEN
    );
    assert_eq!(
        put_reminders(&app, VIEWER, false).await.0,
        StatusCode::FORBIDDEN
    );

    // Audit: the ids and the boolean, nothing else; an unchanged value adds nothing.
    put_reminders(&app, SALES, false).await;
    put_reminders(&app, SALES, false).await;
    let rows: Vec<(String, Value, Option<uuid::Uuid>)> = sqlx::query_as(
        "SELECT action, data, user_id FROM audit.events WHERE entity = 'todo_settings'",
    )
    .fetch_all(&db)
    .await
    .unwrap();
    assert_eq!(rows.len(), 1, "{rows:?}");
    assert_eq!(rows[0].0, "updated");
    assert_eq!(rows[0].1, json!({ "email_reminders": false }));
    assert_eq!(rows[0].2.unwrap().to_string(), SALES_ID);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn changing_the_due_date_resets_the_reminder(db: PgPool) {
    let app = setup(db.clone()).await;
    let id = item(&app, SALES, json!({ "title": "pay" })).await;
    due_in(&db, &id, -1).await;
    assert_eq!(remind(&db).await, 1);
    assert!(reminded(&db, &id).await);
    // Other edits keep it, the same date keeps it, a new date resets it.
    patch(&app, SALES, &id, json!({ "title": "pay now" })).await;
    assert!(reminded(&db, &id).await);
    let (_, v) = get(&app, SALES, "/todo/items").await;
    let current = v[0]["due_date"].as_str().unwrap().to_string();
    patch(&app, SALES, &id, json!({ "due_date": current })).await;
    assert!(reminded(&db, &id).await);
    patch(&app, SALES, &id, json!({ "due_date": "2030-01-01" })).await;
    assert!(!reminded(&db, &id).await);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn one_digest_per_user_and_each_item_only_once(db: PgPool) {
    let app = setup(db.clone()).await;
    let a = item(&app, SALES, json!({ "title": "Call Peeters" })).await;
    let b = item(&app, SALES, json!({ "title": "Send the offer" })).await;
    let future = item(&app, SALES, json!({ "title": "Next month" })).await;
    let _none = item(&app, SALES, json!({ "title": "Someday" })).await;
    let other = item(&app, ADMIN, json!({ "title": "Admin's own" })).await;
    due_in(&db, &a, -2).await;
    due_in(&db, &b, 0).await;
    due_in(&db, &future, 5).await;
    due_in(&db, &other, -1).await;

    // Two people, two digests (not one mail per item).
    assert_eq!(remind(&db).await, 2);
    let mails = outbox(&db).await;
    assert_eq!(mails.len(), 2);
    let sales = mails.iter().find(|m| m.0 == SALES).unwrap();
    assert!(sales.2.contains("Call Peeters") && sales.2.contains("Send the offer"));
    assert!(!sales.2.contains("Next month") && !sales.2.contains("Someday"));
    assert!(!sales.2.contains("Admin's own"));
    let admin = mails.iter().find(|m| m.0 == ADMIN).unwrap();
    assert!(admin.2.contains("Admin's own") && !admin.2.contains("Call Peeters"));
    assert!(reminded(&db, &a).await && reminded(&db, &b).await && reminded(&db, &other).await);
    assert!(!reminded(&db, &future).await);

    // A second pass finds nothing: each item is reminded once.
    assert_eq!(remind(&db).await, 0);
    assert_eq!(outbox(&db).await.len(), 2);
    // Only what became due since goes into the next digest.
    due_in(&db, &future, 0).await;
    assert_eq!(remind(&db).await, 1);
    let mails = outbox(&db).await;
    assert_eq!(mails.len(), 3);
    assert!(mails[2].2.contains("Next month") && !mails[2].2.contains("Call Peeters"));
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn opting_out_keeps_items_unreminded_until_reminders_come_back(db: PgPool) {
    let app = setup(db.clone()).await;
    let id = item(&app, SALES, json!({ "title": "Old and overdue" })).await;
    due_in(&db, &id, -10).await;
    put_reminders(&app, SALES, false).await;
    assert_eq!(remind(&db).await, 0);
    assert!(outbox(&db).await.is_empty());
    assert!(!reminded(&db, &id).await);
    // Switching on again reminds, once and in one mail, also about what is already overdue.
    put_reminders(&app, SALES, true).await;
    assert_eq!(remind(&db).await, 1);
    assert!(outbox(&db).await[0].2.contains("Old and overdue"));
    assert_eq!(remind(&db).await, 0);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_handed_on_item_is_reminded_to_the_assignee(db: PgPool) {
    let app = setup(db.clone()).await;
    let id = item(&app, SALES, json!({ "title": "Fix the pump" })).await;
    patch(&app, SALES, &id, json!({ "assignee_id": TECH_ID })).await;
    due_in(&db, &id, -1).await;
    assert_eq!(remind(&db).await, 1);
    let mails = outbox(&db).await;
    assert_eq!(mails.len(), 1);
    assert_eq!(mails[0].0, TECH);
    assert!(mails[0].2.contains("Fix the pump"));

    // The assignee's own opt-out counts, not the owner's.
    let id2 = item(&app, SALES, json!({ "title": "Second" })).await;
    patch(&app, SALES, &id2, json!({ "assignee_id": TECH_ID })).await;
    due_in(&db, &id2, -1).await;
    put_reminders(&app, TECH, false).await;
    assert_eq!(remind(&db).await, 0);
    assert!(!reminded(&db, &id2).await);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn done_items_and_sub_items_of_done_parents_are_not_reminded(db: PgPool) {
    let app = setup(db.clone()).await;
    let done = item(&app, SALES, json!({ "title": "finished" })).await;
    let parent = item(&app, SALES, json!({ "title": "parent" })).await;
    let sub = item(
        &app,
        SALES,
        json!({ "title": "open sub", "parent_id": parent }),
    )
    .await;
    let orphan = item(
        &app,
        SALES,
        json!({ "title": "orphaned sub", "parent_id": done }),
    )
    .await;
    for id in [&done, &sub, &orphan] {
        due_in(&db, id, -1).await;
    }
    // The API never leaves an open sub-item under a done parent; force the state the rule guards.
    sqlx::query("UPDATE todo.items SET done = true, done_at = now() WHERE id = $1::uuid")
        .bind(&done)
        .execute(&db)
        .await
        .unwrap();
    assert_eq!(remind(&db).await, 1);
    let body = &outbox(&db).await[0].2;
    assert!(body.contains("open sub"), "{body}");
    assert!(
        !body.contains("finished") && !body.contains("orphaned sub"),
        "{body}"
    );
    assert!(!reminded(&db, &done).await && !reminded(&db, &orphan).await);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn people_without_a_to_do_list_are_not_mailed(db: PgPool) {
    let app = setup(db.clone()).await;
    let id = item(&app, SALES, json!({ "title": "For the viewer" })).await;
    // Handed to someone whose role has no to-do list.
    sqlx::query(
        "UPDATE todo.items SET assignee_id = $2::uuid, due_date = CURRENT_DATE WHERE id = $1::uuid",
    )
    .bind(&id)
    .bind(VIEWER_ID)
    .execute(&db)
    .await
    .unwrap();
    assert_eq!(remind(&db).await, 0);
    assert!(!reminded(&db, &id).await);

    // The module switched off for the company.
    let mine = item(&app, SALES, json!({ "title": "Mine" })).await;
    due_in(&db, &mine, -1).await;
    sqlx::query("UPDATE core.companies SET disabled_modules = '{todo}' WHERE id = $1::uuid")
        .bind(COMPANY)
        .execute(&db)
        .await
        .unwrap();
    assert_eq!(remind(&db).await, 0);
    assert!(!reminded(&db, &mine).await);
    sqlx::query("UPDATE core.companies SET disabled_modules = '{}' WHERE id = $1::uuid")
        .bind(COMPANY)
        .execute(&db)
        .await
        .unwrap();
    assert_eq!(remind(&db).await, 1);

    // An inactive recipient gets nothing either.
    let later = item(&app, SALES, json!({ "title": "Later" })).await;
    due_in(&db, &later, -1).await;
    sqlx::query("UPDATE core.user_companies SET active = false WHERE user_id = $1::uuid")
        .bind(SALES_ID)
        .execute(&db)
        .await
        .unwrap();
    assert_eq!(remind(&db).await, 0);
    assert!(!reminded(&db, &later).await);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_mail_speaks_the_language_of_the_recipient(db: PgPool) {
    let app = setup(db.clone()).await;
    item(&app, SALES, json!({ "title": "Offerte" })).await;
    let cases = [
        (
            "en",
            "To-do reminder",
            "You get this reminder once per item",
            "overdue since",
        ),
        (
            "de",
            "To-do-Erinnerung",
            "Sie erhalten diese Erinnerung",
            "überfällig seit",
        ),
        (
            "es",
            "Recordatorio de tareas",
            "Recibe este recordatorio",
            "vencida desde",
        ),
        (
            "fr",
            "Rappel de tâches",
            "Vous recevez ce rappel",
            "en retard depuis le",
        ),
        (
            "nl",
            "Herinnering taken",
            "U krijgt deze herinnering",
            "te laat sinds",
        ),
    ];
    for (lang, subject, footer, overdue) in cases {
        sqlx::query("UPDATE core.users SET language = $2 WHERE id = $1::uuid")
            .bind(SALES_ID)
            .bind(lang)
            .execute(&db)
            .await
            .unwrap();
        sqlx::query("UPDATE todo.items SET reminded_at = NULL, due_date = CURRENT_DATE - 1")
            .execute(&db)
            .await
            .unwrap();
        clear_outbox(&db).await;
        assert_eq!(remind(&db).await, 1, "{lang}");
        let (_, s, body) = outbox(&db).await.remove(0);
        assert!(s.starts_with(subject), "{lang}: {s}");
        assert!(body.contains(footer), "{lang}: {body}");
        assert!(body.contains(overdue), "{lang}: {body}");
        assert!(body.contains("Offerte"), "{lang}");
    }
    // Without a language of its own, the company's default is used (Dutch in the seed).
    sqlx::query("UPDATE core.users SET language = NULL WHERE id = $1::uuid")
        .bind(SALES_ID)
        .execute(&db)
        .await
        .unwrap();
    sqlx::query("UPDATE todo.items SET reminded_at = NULL")
        .execute(&db)
        .await
        .unwrap();
    clear_outbox(&db).await;
    remind(&db).await;
    assert!(outbox(&db).await[0].1.starts_with("Herinnering taken"));
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_link_label_is_listed_only_when_the_recipient_may_read_it(db: PgPool) {
    let app = setup(db.clone()).await;
    let id = item(
        &app,
        SALES,
        json!({ "title": "Follow up", "notes": "secret notes", "link_kind": "quotation",
                "link_id": QUOTE, "link_label": "Q-2027-001 Acme", "link_location": "/quotations/x" }),
    )
    .await;
    due_in(&db, &id, -1).await;
    assert_eq!(remind(&db).await, 1);
    let body = outbox(&db).await[0].2.clone();
    assert!(body.contains("Q-2027-001 Acme"), "{body}");
    assert!(!body.contains("secret notes"), "{body}");

    // Handed to a technician (no quotations.read): the title, not the label.
    clear_outbox(&db).await;
    patch(&app, SALES, &id, json!({ "assignee_id": TECH_ID })).await;
    sqlx::query("UPDATE todo.items SET reminded_at = NULL")
        .execute(&db)
        .await
        .unwrap();
    assert_eq!(remind(&db).await, 1);
    let (to, _, body) = outbox(&db).await.remove(0);
    assert_eq!(to, TECH);
    assert!(
        body.contains("Follow up") && !body.contains("Q-2027-001"),
        "{body}"
    );
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn passes_running_at_once_do_not_send_twice(db: PgPool) {
    let app = setup(db.clone()).await;
    for n in 0..5 {
        let id = item(&app, SALES, json!({ "title": format!("Task {n}") })).await;
        due_in(&db, &id, -1).await;
    }
    let (a, b, c) = tokio::join!(remind(&db), remind(&db), remind(&db));
    assert_eq!(a + b + c, 1, "{a} {b} {c}");
    assert_eq!(outbox(&db).await.len(), 1);
    let unreminded: i64 =
        sqlx::query_scalar("SELECT count(*) FROM todo.items WHERE reminded_at IS NULL")
            .fetch_one(&db)
            .await
            .unwrap();
    assert_eq!(unreminded, 0);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_pass_only_queues_and_the_outbox_applies_the_transport_policy(db: PgPool) {
    use tradocraft_helpdesk::mailer::{process_system_mail, Mailer};
    let app = setup(db.clone()).await;
    let id = item(&app, SALES, json!({ "title": "Call back" })).await;
    due_in(&db, &id, -1).await;
    assert_eq!(remind(&db).await, 1);
    // Queued, nothing sent yet: the reminder is a row in the outbox like any other system mail.
    let state: String = sqlx::query_scalar("SELECT delivery FROM core.mail_outbox")
        .fetch_one(&db)
        .await
        .unwrap();
    assert_eq!(state, "queued");
    // Outside a live environment the worker's transport is files (ADR 0048): the mail lands on
    // disk and nothing leaves over SMTP.
    let dir = tempfile::tempdir().unwrap();
    let sent = process_system_mail(&db, &Mailer::Files(dir.path().to_path_buf()), 10)
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
    assert!(eml.contains("Call back"), "{eml}");
    // Sending never touches the item: it was claimed when the mail was queued.
    assert!(reminded(&db, &id).await);
    assert_eq!(remind(&db).await, 0);
}
