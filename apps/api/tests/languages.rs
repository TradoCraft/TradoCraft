//! Company content languages and the ISO 639-1 language list (ADR 0101).

mod common;

use axum::http::{Method, StatusCode};
use common::{call, setup};
use serde_json::{json, Value};
use sqlx::PgPool;

const ADMIN: &str = "admin@example.com";
const SALES: &str = "sales@example.com";

async fn me_company(app: &axum::Router) -> Value {
    let (s, me) = call(app, ADMIN, Method::GET, "/api/v1/me", None).await;
    assert_eq!(s, StatusCode::OK, "{me}");
    me["company"].clone()
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_demo_company_keeps_its_five_languages(db: PgPool) {
    let app = setup(db).await;
    let company = me_company(&app).await;
    assert_eq!(company["languages"], json!(["nl", "fr", "en", "de", "es"]));
    assert_eq!(company["default_language"], "nl");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn every_iso_language_is_listed_with_its_names(db: PgPool) {
    let app = setup(db).await;
    let (s, list) = call(&app, SALES, Method::GET, "/api/v1/languages", None).await;
    assert_eq!(s, StatusCode::OK);
    let list = list.as_array().unwrap();
    assert_eq!(list.len(), 184);
    let pt = list.iter().find(|l| l["code"] == "pt").unwrap();
    assert_eq!(pt["name"], "Português");
    assert_eq!(pt["english_name"], "Portuguese");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn an_administrator_sets_any_iso_languages_and_the_default(db: PgPool) {
    let app = setup(db.clone()).await;
    let (s, company) = call(
        &app,
        ADMIN,
        Method::PUT,
        "/api/v1/admin/company/languages",
        Some(json!({ "languages": ["pt", "en", "SV"], "default_language": "pt" })),
    )
    .await;
    assert_eq!(s, StatusCode::OK, "{company}");
    assert_eq!(company["languages"], json!(["pt", "en", "sv"]));
    assert_eq!(company["default_language"], "pt");
    assert_eq!(
        me_company(&app).await["languages"],
        json!(["pt", "en", "sv"])
    );
    let audited: i64 =
        sqlx::query_scalar("SELECT count(*) FROM audit.events WHERE action = 'languages_updated'")
            .fetch_one(&db)
            .await
            .unwrap();
    assert_eq!(audited, 1);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn bad_language_lists_are_refused(db: PgPool) {
    let app = setup(db).await;
    for body in [
        json!({ "languages": [], "default_language": "en" }),
        json!({ "languages": ["en", "xx"], "default_language": "en" }),
        json!({ "languages": ["en", "en"], "default_language": "en" }),
        json!({ "languages": ["en", "fr"], "default_language": "de" }),
    ] {
        let (s, e) = call(
            &app,
            ADMIN,
            Method::PUT,
            "/api/v1/admin/company/languages",
            Some(body.clone()),
        )
        .await;
        assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY, "{body} {e}");
    }
    assert_eq!(
        me_company(&app).await["languages"],
        json!(["nl", "fr", "en", "de", "es"])
    );
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn only_administrators_change_the_languages(db: PgPool) {
    let app = setup(db).await;
    let (s, _) = call(
        &app,
        SALES,
        Method::PUT,
        "/api/v1/admin/company/languages",
        Some(json!({ "languages": ["en"], "default_language": "en" })),
    )
    .await;
    assert_eq!(s, StatusCode::FORBIDDEN);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_company_inserted_directly_has_its_default_language(db: PgPool) {
    let _app = setup(db.clone()).await;
    sqlx::query(
        "INSERT INTO core.companies (id, name, default_language)
         VALUES ('00000000-0000-7000-8000-0000000000c2', 'Second BV', 'fr')",
    )
    .execute(&db)
    .await
    .unwrap();
    let langs: Vec<String> = sqlx::query_scalar(
        "SELECT language FROM core.company_languages
         WHERE company_id = '00000000-0000-7000-8000-0000000000c2'",
    )
    .fetch_all(&db)
    .await
    .unwrap();
    assert_eq!(langs, ["fr"]);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn stored_content_takes_any_iso_language(db: PgPool) {
    let _app = setup(db.clone()).await;
    // The checks of the database only want two lower-case letters now.
    let customer: uuid::Uuid = sqlx::query_scalar("SELECT id FROM crm.customers LIMIT 1")
        .fetch_one(&db)
        .await
        .unwrap();
    sqlx::query("UPDATE crm.customers SET language = 'pt' WHERE id = $1")
        .bind(customer)
        .execute(&db)
        .await
        .unwrap();
    let refused = sqlx::query("UPDATE crm.customers SET language = 'PT' WHERE id = $1")
        .bind(customer)
        .execute(&db)
        .await;
    assert!(refused.is_err());
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn price_list_zones_publish_only_company_languages(db: PgPool) {
    let app = setup(db).await;
    let (s, list) = call(
        &app,
        ADMIN,
        Method::POST,
        "/api/v1/price-lists",
        Some(json!({ "code": "LANG", "name": "Languages", "valid_from": "2027-01-01" })),
    )
    .await;
    assert!(s.is_success(), "{list}");
    let zones = format!("/api/v1/price-lists/{}/zones", list["id"].as_str().unwrap());
    let z1 = "00000000-0000-7000-8000-000000000201";
    let body = json!([{ "price_zone_id": z1, "languages": ["nl", "pt"] }]);
    let (s, e) = call(&app, ADMIN, Method::PUT, &zones, Some(body.clone())).await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY, "{e}");
    assert!(e["message"].as_str().unwrap().contains("\"pt\""), "{e}");

    let (s, _) = call(
        &app,
        ADMIN,
        Method::PUT,
        "/api/v1/admin/company/languages",
        Some(json!({ "languages": ["nl", "pt"], "default_language": "nl" })),
    )
    .await;
    assert_eq!(s, StatusCode::OK);
    let (s, e) = call(&app, ADMIN, Method::PUT, &zones, Some(body.clone())).await;
    assert_eq!(s, StatusCode::OK, "{e}");

    // Portuguese leaves the company: the zone that publishes it can still be saved.
    let (s, _) = call(
        &app,
        ADMIN,
        Method::PUT,
        "/api/v1/admin/company/languages",
        Some(json!({ "languages": ["nl"], "default_language": "nl" })),
    )
    .await;
    assert_eq!(s, StatusCode::OK);
    let (s, e) = call(&app, ADMIN, Method::PUT, &zones, Some(body)).await;
    assert_eq!(s, StatusCode::OK, "{e}");
}
