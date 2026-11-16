//! Prepared answers as templates: kinds, team scope, keywords, suggestions, mail rules (ADR 0071).

mod common;

use axum::http::{Method, StatusCode};
#[allow(unused_imports)]
use common::{call, call_raw, setup};
use serde_json::{json, Value};
use sqlx::PgPool;

const ADMIN: &str = "admin@example.com";
const SUPPORT: &str = "support@example.com";

async fn api(
    app: &axum::Router,
    user: &str,
    method: Method,
    uri: &str,
    body: Option<Value>,
) -> (StatusCode, Value) {
    call(app, user, method, &format!("/api/v1{uri}"), body).await
}
async fn get(app: &axum::Router, user: &str, uri: &str) -> (StatusCode, Value) {
    api(app, user, Method::GET, uri, None).await
}
async fn post(app: &axum::Router, user: &str, uri: &str, body: Value) -> (StatusCode, Value) {
    api(app, user, Method::POST, uri, Some(body)).await
}
async fn put(app: &axum::Router, user: &str, uri: &str, body: Value) -> (StatusCode, Value) {
    api(app, user, Method::PUT, uri, Some(body)).await
}

async fn team(app: &axum::Router, name: &str) -> String {
    let (status, t) = post(app, ADMIN, "/helpdesk/teams", json!({ "name": name })).await;
    assert_eq!(status, StatusCode::CREATED, "{t}");
    t["id"].as_str().unwrap().to_string()
}

fn answer(code: &str, extra: Value) -> Value {
    let mut a = json!({
        "code": code, "name": code,
        "texts": [{ "language": "en", "subject": "Re: {{ticket.subject}}", "body": "Hello {{contact.name}}" }]
    });
    for (k, v) in extra.as_object().unwrap() {
        a[k] = v.clone();
    }
    a
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn an_answer_has_a_kind_a_team_and_clean_keywords(db: PgPool) {
    let app = setup(db).await;
    let rd = team(&app, "R&D").await;
    let (status, a) = post(
        &app,
        SUPPORT,
        "/prepared-answers",
        answer(
            "firmware",
            json!({ "kind": "internal_note", "team_id": rd, "keywords": [" Firmware ", "firmware", "UPDATE", ""] }),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{a}");
    assert_eq!(a["kind"], "internal_note");
    assert_eq!(a["team_id"], rd.as_str());
    assert_eq!(a["keywords"], json!(["firmware", "update"]));
    // Default kind is a reply, company-wide.
    let (_, plain) = post(&app, SUPPORT, "/prepared-answers", answer("plain", json!({}))).await;
    assert_eq!(plain["kind"], "reply");
    assert!(plain["team_id"].is_null());
    assert_eq!(plain["keywords"], json!([]));
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn kind_team_and_keywords_are_validated(db: PgPool) {
    let app = setup(db).await;
    let (status, _) = post(&app, SUPPORT, "/prepared-answers", answer("a", json!({ "kind": "shout" }))).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    let (status, _) = post(
        &app,
        SUPPORT,
        "/prepared-answers",
        answer("b", json!({ "team_id": "00000000-0000-7000-8000-00000000dead" })),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let long = "x".repeat(41);
    let (status, _) = post(&app, SUPPORT, "/prepared-answers", answer("c", json!({ "keywords": [long] }))).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_list_filters_by_kind_and_by_the_team_that_can_use_the_answer(db: PgPool) {
    let app = setup(db.clone()).await;
    sqlx::query("DELETE FROM helpdesk.prepared_answers")
        .execute(&db)
        .await
        .unwrap();
    let rd = team(&app, "R&D").await;
    let net = team(&app, "Network").await;
    post(&app, SUPPORT, "/prepared-answers", answer("everyone", json!({}))).await;
    post(&app, SUPPORT, "/prepared-answers", answer("rd-note", json!({ "kind": "internal_note", "team_id": rd }))).await;
    post(&app, SUPPORT, "/prepared-answers", answer("net-reply", json!({ "team_id": net }))).await;
    let codes = |v: &Value| -> Vec<String> {
        let mut c: Vec<String> = v.as_array().unwrap().iter().map(|a| a["code"].as_str().unwrap().to_string()).collect();
        c.sort();
        c
    };
    let (_, all) = get(&app, SUPPORT, "/prepared-answers").await;
    assert_eq!(codes(&all), ["everyone", "net-reply", "rd-note"]);
    let (_, notes) = get(&app, SUPPORT, "/prepared-answers?kind=internal_note").await;
    assert_eq!(codes(&notes), ["rd-note"]);
    // A network ticket sees company-wide answers and the network's own.
    let (_, for_net) = get(&app, SUPPORT, &format!("/prepared-answers?team_id={net}")).await;
    assert_eq!(codes(&for_net), ["everyone", "net-reply"]);
    // Update keeps working and can move an answer to another team.
    let id = all.as_array().unwrap().iter().find(|a| a["code"] == "net-reply").unwrap()["id"].as_str().unwrap().to_string();
    let (status, moved) = put(&app, SUPPORT, &format!("/prepared-answers/{id}"), answer("net-reply", json!({ "team_id": rd }))).await;
    assert_eq!(status, StatusCode::OK, "{moved}");
    assert_eq!(moved["team_id"], rd.as_str());
}

/// A ticket made by hand; its id is read back from the database.
async fn manual_ticket(app: &axum::Router, db: &PgPool, user: &str, subject: &str, extra: Value) -> String {
    let mut body = json!({ "subject": subject, "body": "asked", "category": "question" });
    for (k, v) in extra.as_object().unwrap() {
        body[k] = v.clone();
    }
    let (status, r) = post(app, user, "/tickets", body).await;
    assert_eq!(status, StatusCode::CREATED, "{r}");
    sqlx::query_scalar("SELECT id::text FROM helpdesk.tickets WHERE subject = $1")
        .bind(subject)
        .fetch_one(db)
        .await
        .unwrap()
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_team_name_is_filled_in_for_a_ticket_of_that_team(db: PgPool) {
    let app = setup(db.clone()).await;
    let rd = team(&app, "R&D").await;
    let (_, a) = post(
        &app,
        SUPPORT,
        "/prepared-answers",
        answer("who", json!({ "texts": [{ "language": "en", "body": "Team: {{team.name}}" }] })),
    )
    .await;
    let ticket = manual_ticket(&app, &db, SUPPORT, "Needs R&D", json!({})).await;
    sqlx::query("UPDATE helpdesk.tickets SET team_id = $2::uuid WHERE id = $1::uuid")
        .bind(&ticket)
        .bind(&rd)
        .execute(&db)
        .await
        .unwrap();
    let uri = format!("/tickets/{ticket}/prepared-answers/{}/render", a["id"].as_str().unwrap());
    let (status, r) = post(&app, SUPPORT, &uri, json!({})).await;
    assert_eq!(status, StatusCode::OK, "{r}");
    assert_eq!(r["body"], "Team: R&D");
}

