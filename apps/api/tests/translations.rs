//! Translation catalogues for documents, mails and the interfaces (ADR 0101).

mod common;

use axum::http::{Method, StatusCode};
use common::{call, raw, setup, Who};
use serde_json::{json, Value};
use sqlx::PgPool;

const ADMIN: &str = "admin@example.com";
const SALES: &str = "sales@example.com";
const ALPHA: &str = "00000000-0000-7000-8000-000000000401";
const PUMP: &str = "00000000-0000-7000-8000-000000000303";

async fn put(app: &axum::Router, user: &str, uri: &str, body: Value) -> (StatusCode, Value) {
    call(app, user, Method::PUT, uri, Some(body)).await
}

fn pdf_text(pdf: &[u8]) -> String {
    let path = std::env::temp_dir().join(format!("tr-{}.pdf", uuid::Uuid::now_v7()));
    std::fs::write(&path, pdf).unwrap();
    let out = std::process::Command::new("pdftotext")
        .arg(&path)
        .arg("-")
        .output()
        .expect("pdftotext (poppler-utils) must be installed to read the printed labels");
    let _ = std::fs::remove_file(&path);
    String::from_utf8_lossy(&out.stdout).into_owned()
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn shipped_catalogues_are_listed_with_their_english_source(db: PgPool) {
    let app = setup(db).await;
    let (s, list) = call(
        &app,
        SALES,
        Method::GET,
        "/api/v1/translations/documents",
        None,
    )
    .await;
    assert_eq!(s, StatusCode::OK, "{list}");
    let langs: Vec<&str> = list
        .as_array()
        .unwrap()
        .iter()
        .map(|c| c["language"].as_str().unwrap())
        .collect();
    assert_eq!(langs, ["de", "en", "es", "fr", "nl"]);
    let (s, d) = call(
        &app,
        SALES,
        Method::GET,
        "/api/v1/translations/mail/pt",
        None,
    )
    .await;
    assert_eq!(s, StatusCode::OK);
    assert_eq!(d["shipped"], json!({}));
    assert!(d["source"]["mail.outage.subject"].is_string());
    let (s, _) = call(&app, SALES, Method::GET, "/api/v1/translations/nope", None).await;
    assert_eq!(s, StatusCode::NOT_FOUND);
    let (s, _) = call(
        &app,
        SALES,
        Method::GET,
        "/api/v1/translations/app/xx",
        None,
    )
    .await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn administrators_add_and_remove_catalogues(db: PgPool) {
    let app = setup(db).await;
    let uri = "/api/v1/admin/translations/app/pt";
    let body = json!({ "entries": { "save": "Guardar", "cancel": " " } });
    let (s, _) = put(&app, SALES, uri, body.clone()).await;
    assert_eq!(s, StatusCode::FORBIDDEN);
    let (s, d) = put(&app, ADMIN, uri, body).await;
    assert_eq!(s, StatusCode::OK, "{d}");
    assert_eq!(d["entries"], json!({ "save": "Guardar" }));
    let (_, list) = call(&app, SALES, Method::GET, "/api/v1/translations/app", None).await;
    assert_eq!(list[0]["language"], "pt");
    assert_eq!(list[0]["company_entries"], 1);
    // Documents and mails only take keys of the English source.
    let (s, _) = put(
        &app,
        ADMIN,
        "/api/v1/admin/translations/documents/pt",
        json!({ "entries": { "quotation.nonsense": "x" } }),
    )
    .await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);
    let (s, _) = call(&app, ADMIN, Method::DELETE, uri, None).await;
    assert_eq!(s, StatusCode::NO_CONTENT);
    let (s, _) = call(&app, ADMIN, Method::DELETE, uri, None).await;
    assert_eq!(s, StatusCode::NOT_FOUND);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_quotation_prints_company_labels_with_english_for_the_rest(db: PgPool) {
    let app = setup(db.clone()).await;
    sqlx::query("UPDATE crm.customers SET language = 'pt' WHERE id = $1::uuid")
        .bind(ALPHA)
        .execute(&db)
        .await
        .unwrap();
    let (s, _) = put(
        &app,
        ADMIN,
        "/api/v1/admin/translations/documents/pt",
        json!({ "entries": { "quotation.title": "Orçamento" } }),
    )
    .await;
    assert_eq!(s, StatusCode::OK);
    let (s, q) = call(
        &app,
        SALES,
        Method::POST,
        "/api/v1/quotations",
        Some(json!({ "customer_id": ALPHA, "lines": [{ "product_id": PUMP, "quantity": "1" }] })),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED, "{q}");
    let id = q["id"].as_str().unwrap();
    let (s, _, pdf) = raw(
        &app,
        Who::Staff(SALES),
        Method::GET,
        &format!("/api/v1/quotations/{id}/pdf"),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::OK);
    let text = pdf_text(&pdf);
    assert!(text.contains("Orçamento"), "{text}");
    assert!(text.contains("Unit price"), "{text}");
}
