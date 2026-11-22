//! Price zone management: create, update, guarded delete, permissions, company isolation.

mod common;

use axum::http::{Method, StatusCode};
use common::{call, setup};
use serde_json::json;
use sqlx::PgPool;

const ZONE_Z2: &str = "00000000-0000-7000-8000-000000000202"; // used by zone prices and customers
const ADMIN: &str = "admin@example.com";
const SALES: &str = "sales@example.com";

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn create_update_and_delete_an_unused_zone(db: PgPool) {
    let app = setup(db.clone()).await;
    let (status, z) = call(
        &app,
        ADMIN,
        Method::POST,
        "/api/v1/price-zones",
        Some(json!({ "code": " ZX ", "name": "Export", "sort_order": 9 })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{z}");
    assert_eq!(z["code"], "ZX");
    let id = z["id"].as_str().unwrap().to_string();

    let (status, z) = call(
        &app,
        ADMIN,
        Method::PUT,
        &format!("/api/v1/price-zones/{id}"),
        Some(json!({
            "code": "ZX",
            "name": "Export EU",
            "sort_order": 10,
            "default_multiplier": "1.1500",
            "default_rounding": "0.05"
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{z}");
    assert_eq!(z["name"], "Export EU");
    assert_eq!(z["sort_order"], 10);
    assert_eq!(z["default_multiplier"], "1.1500");
    assert_eq!(z["default_rounding"], "0.05");

    let (_, list) = call(&app, ADMIN, Method::GET, "/api/v1/price-zones", None).await;
    assert!(list.as_array().unwrap().iter().any(|z| z["code"] == "ZX"));

    let (status, body) = call(
        &app,
        ADMIN,
        Method::DELETE,
        &format!("/api/v1/price-zones/{id}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NO_CONTENT, "{body}");
    let (_, list) = call(&app, ADMIN, Method::GET, "/api/v1/price-zones", None).await;
    assert!(!list.as_array().unwrap().iter().any(|z| z["code"] == "ZX"));

    let n: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM audit.events WHERE entity = 'price_zone' AND entity_id = $1::uuid",
    )
    .bind(&id)
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(n, 3, "created, updated, deleted");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn duplicate_code_is_a_conflict_and_blank_fields_are_rejected(db: PgPool) {
    let app = setup(db).await;
    let (status, _) = call(
        &app,
        ADMIN,
        Method::POST,
        "/api/v1/price-zones",
        Some(json!({ "code": "Z2", "name": "Again" })),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);

    let (status, z) = call(
        &app,
        ADMIN,
        Method::POST,
        "/api/v1/price-zones",
        Some(json!({ "code": "ZY", "name": "Other" })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);
    // Renaming onto an existing code is refused as well.
    let (status, _) = call(
        &app,
        ADMIN,
        Method::PUT,
        &format!("/api/v1/price-zones/{}", z["id"].as_str().unwrap()),
        Some(json!({ "code": "Z2", "name": "Other" })),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);

    let (status, _) = call(
        &app,
        ADMIN,
        Method::POST,
        "/api/v1/price-zones",
        Some(json!({ "code": "  ", "name": "x" })),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    // Negative/zero multiplier or invalid rounding is rejected.
    let (status, _) = call(
        &app,
        ADMIN,
        Method::POST,
        "/api/v1/price-zones",
        Some(json!({ "code": "ZNEG", "name": "Neg", "default_multiplier": "0" })),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    let (status, _) = call(
        &app,
        ADMIN,
        Method::POST,
        "/api/v1/price-zones",
        Some(json!({ "code": "ZBADR", "name": "BadR", "default_rounding": "0.33" })),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    // Excess fractional precision or magnitude beyond NUMERIC(10, 4) is rejected.
    let (status, _) = call(
        &app,
        ADMIN,
        Method::POST,
        "/api/v1/price-zones",
        Some(json!({ "code": "ZPREC", "name": "Prec", "default_multiplier": "1.12345" })),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    let (status, _) = call(
        &app,
        ADMIN,
        Method::POST,
        "/api/v1/price-zones",
        Some(json!({ "code": "ZBIG", "name": "Big", "default_multiplier": "1000000.0000" })),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn user_preferences_round_trip(db: PgPool) {
    let app = setup(db).await;
    let (status, prefs) = call(&app, SALES, Method::GET, "/api/v1/me/preferences", None).await;
    assert_eq!(status, StatusCode::OK, "{prefs}");
    assert_eq!(prefs["shortcuts"], json!({}));

    let (status, saved) = call(
        &app,
        SALES,
        Method::PUT,
        "/api/v1/me/preferences",
        Some(json!({
            "shortcuts": {
                "save": { "key": "keyS", "mod": "standard", "shift": true }
            }
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{saved}");
    assert_eq!(saved["shortcuts"]["save"]["shift"], true);

    let (status, fetched) = call(&app, SALES, Method::GET, "/api/v1/me/preferences", None).await;
    assert_eq!(status, StatusCode::OK, "{fetched}");
    assert_eq!(fetched["shortcuts"]["save"]["key"], "keyS");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_zone_in_use_cannot_be_deleted(db: PgPool) {
    let app = setup(db.clone()).await;
    // Z2 has zone prices and customers.
    let (status, body) = call(
        &app,
        ADMIN,
        Method::DELETE,
        &format!("/api/v1/price-zones/{ZONE_Z2}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT, "{body}");

    // A zone with only customer terms is protected too.
    let (_, z) = call(
        &app,
        ADMIN,
        Method::POST,
        "/api/v1/price-zones",
        Some(json!({ "code": "ZT", "name": "Terms only" })),
    )
    .await;
    let id = z["id"].as_str().unwrap();
    sqlx::query("UPDATE crm.customer_terms SET price_zone_id = $1::uuid WHERE ctid = (SELECT ctid FROM crm.customer_terms LIMIT 1)")
        .bind(id)
        .execute(&db)
        .await
        .unwrap();
    let (status, _) = call(
        &app,
        ADMIN,
        Method::DELETE,
        &format!("/api/v1/price-zones/{id}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_role_without_prices_write_is_refused(db: PgPool) {
    let app = setup(db).await;
    let (status, _) = call(
        &app,
        SALES,
        Method::POST,
        "/api/v1/price-zones",
        Some(json!({ "code": "ZS", "name": "Nope" })),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, _) = call(
        &app,
        SALES,
        Method::PUT,
        &format!("/api/v1/price-zones/{ZONE_Z2}"),
        Some(json!({ "code": "Z2", "name": "Nope" })),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, _) = call(
        &app,
        SALES,
        Method::DELETE,
        &format!("/api/v1/price-zones/{ZONE_Z2}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    // Reading stays allowed.
    let (status, _) = call(&app, SALES, Method::GET, "/api/v1/price-zones", None).await;
    assert_eq!(status, StatusCode::OK);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn zones_of_another_company_are_invisible_and_untouchable(db: PgPool) {
    let app = setup(db.clone()).await;
    let other = "00000000-0000-7000-8000-0000000fff01";
    let zone = "00000000-0000-7000-8000-0000000fff02";
    sqlx::query("INSERT INTO core.companies (id, name) VALUES ($1::uuid, 'Other BV')")
        .bind(other)
        .execute(&db)
        .await
        .unwrap();
    sqlx::query("INSERT INTO pricing.price_zones (id, company_id, code, name) VALUES ($1::uuid, $2::uuid, 'ZO', 'Theirs')")
        .bind(zone)
        .bind(other)
        .execute(&db)
        .await
        .unwrap();
    let (_, list) = call(&app, ADMIN, Method::GET, "/api/v1/price-zones", None).await;
    assert!(!list.as_array().unwrap().iter().any(|z| z["code"] == "ZO"));
    let (status, _) = call(
        &app,
        ADMIN,
        Method::PUT,
        &format!("/api/v1/price-zones/{zone}"),
        Some(json!({ "code": "ZO", "name": "Mine now" })),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, _) = call(
        &app,
        ADMIN,
        Method::DELETE,
        &format!("/api/v1/price-zones/{zone}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    // The same code is free in this company.
    let (status, _) = call(
        &app,
        ADMIN,
        Method::POST,
        "/api/v1/price-zones",
        Some(json!({ "code": "ZO", "name": "Mine" })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn code_length_counts_characters_not_bytes(db: PgPool) {
    let app = setup(db).await;
    // 32 two-byte characters are allowed, 33 are not.
    let (status, _) = call(
        &app,
        ADMIN,
        Method::POST,
        "/api/v1/price-zones",
        Some(json!({ "code": "é".repeat(32), "name": "Long" })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);
    let (status, _) = call(
        &app,
        ADMIN,
        Method::POST,
        "/api/v1/price-zones",
        Some(json!({ "code": "é".repeat(33), "name": "Too long" })),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn updating_another_companys_zone_is_not_found_even_when_the_code_clashes(db: PgPool) {
    let app = setup(db.clone()).await;
    let other = "00000000-0000-7000-8000-0000000fff01";
    let zone = "00000000-0000-7000-8000-0000000fff02";
    sqlx::query("INSERT INTO core.companies (id, name) VALUES ($1::uuid, 'Other BV')")
        .bind(other)
        .execute(&db)
        .await
        .unwrap();
    sqlx::query("INSERT INTO pricing.price_zones (id, company_id, code, name) VALUES ($1::uuid, $2::uuid, 'ZO', 'Theirs')")
        .bind(zone)
        .bind(other)
        .execute(&db)
        .await
        .unwrap();
    // Z2 exists in the admin's company: the clash must not leak through a 409.
    let (status, _) = call(
        &app,
        ADMIN,
        Method::PUT,
        &format!("/api/v1/price-zones/{zone}"),
        Some(json!({ "code": "Z2", "name": "Mine now" })),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}
