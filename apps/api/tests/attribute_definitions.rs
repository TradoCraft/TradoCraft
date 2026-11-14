//! Attribute definitions (ADR 0068): CRUD, validation, scope filter, guarded delete,
//! permissions, company isolation and audit.

mod common;

use axum::http::{Method, StatusCode};
use common::{call, setup};
use serde_json::{json, Value};
use sqlx::PgPool;

const ADMIN: &str = "admin@example.com";
const READ_ONLY: &str = "support@example.com";
const URL: &str = "/api/v1/attribute-definitions";

fn select_body(key: &str, scope: &str) -> Value {
    json!({
        "key": key, "label": "Motion", "kind": "select", "scope": scope,
        "options": [{ "value": "flying", "label": "Flying" }, { "value": "falling", "label": "Falling" }],
    })
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn create_get_update_list_and_delete(db: PgPool) {
    let app = setup(db.clone()).await;
    let (status, d) = call(
        &app,
        ADMIN,
        Method::POST,
        URL,
        Some(json!({ "key": "dial_size", "label": " Dial size ", "kind": "range", "unit": "mm" })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{d}");
    assert_eq!(d["label"], "Dial size");
    assert_eq!(d["scope"], "product");
    assert_eq!(d["unit"], "mm");
    assert_eq!(d["active"], true);
    assert_eq!(d["options"], json!([]));
    let id = d["id"].as_str().unwrap().to_string();

    let (status, g) = call(&app, ADMIN, Method::GET, &format!("{URL}/{id}"), None).await;
    assert_eq!(status, StatusCode::OK, "{g}");
    assert_eq!(g["key"], "dial_size");

    let (status, u) = call(
        &app,
        ADMIN,
        Method::PUT,
        &format!("{URL}/{id}"),
        Some(
            json!({ "key": "dial_size", "label": "Dial diameter", "kind": "number", "unit": "mm",
                     "sort_order": 3, "active": false }),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{u}");
    assert_eq!(u["label"], "Dial diameter");
    assert_eq!(u["kind"], "number");
    assert_eq!(u["active"], false);

    let (_, list) = call(&app, ADMIN, Method::GET, URL, None).await;
    assert!(list
        .as_array()
        .unwrap()
        .iter()
        .any(|d| d["id"] == id.as_str()));

    let (status, body) = call(&app, ADMIN, Method::DELETE, &format!("{URL}/{id}"), None).await;
    assert_eq!(status, StatusCode::NO_CONTENT, "{body}");
    let (status, _) = call(&app, ADMIN, Method::GET, &format!("{URL}/{id}"), None).await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    let n: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM audit.events WHERE entity = 'attribute_definition' AND entity_id = $1::uuid",
    )
    .bind(&id)
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(n, 3, "created, updated, deleted");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn list_filters_by_scope_and_orders_by_sort_order(db: PgPool) {
    let app = setup(db).await;
    for (key, scope, order) in [
        ("b_attr", "bell", 2),
        ("a_attr", "bell", 1),
        ("c_attr", "product", 0),
    ] {
        let mut body = select_body(key, scope);
        body["sort_order"] = json!(order);
        let (status, e) = call(&app, ADMIN, Method::POST, URL, Some(body)).await;
        assert_eq!(status, StatusCode::CREATED, "{e}");
    }
    let (_, list) = call(&app, ADMIN, Method::GET, &format!("{URL}?scope=bell"), None).await;
    let keys: Vec<_> = list
        .as_array()
        .unwrap()
        .iter()
        .map(|d| d["key"].as_str().unwrap())
        .collect();
    assert_eq!(keys, ["a_attr", "b_attr"]);
    let (_, all) = call(&app, ADMIN, Method::GET, URL, None).await;
    assert_eq!(all.as_array().unwrap().len(), 3);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn invalid_input_is_unprocessable_and_duplicate_key_is_a_conflict(db: PgPool) {
    let app = setup(db).await;
    for body in [
        json!({ "key": "Bad Key", "label": "x", "kind": "text" }),
        json!({ "key": "k", "label": " ", "kind": "text" }),
        json!({ "key": "k", "label": "x", "kind": "select" }),
        json!({ "key": "k", "label": "x", "kind": "text", "options": [{ "value": "a", "label": "A" }] }),
        json!({ "key": "k", "label": "x", "kind": "text", "unit": "mm" }),
        json!({ "key": "k", "label": "x", "kind": "select", "options": [
            { "value": "a", "label": "A" }, { "value": "a", "label": "B" }] }),
    ] {
        let (status, e) = call(&app, ADMIN, Method::POST, URL, Some(body.clone())).await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{body} {e}");
    }
    let (status, d) = call(
        &app,
        ADMIN,
        Method::POST,
        URL,
        Some(select_body("motion", "bell")),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{d}");
    // The key is unique per company, whatever the scope.
    let (status, _) = call(
        &app,
        ADMIN,
        Method::POST,
        URL,
        Some(select_body("motion", "product")),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
    let (_, other) = call(
        &app,
        ADMIN,
        Method::POST,
        URL,
        Some(select_body("motion2", "bell")),
    )
    .await;
    let (status, _) = call(
        &app,
        ADMIN,
        Method::PUT,
        &format!("{URL}/{}", other["id"].as_str().unwrap()),
        Some(select_body("motion", "bell")),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_product_attribute_in_use_blocks_delete_but_not_deactivation(db: PgPool) {
    let app = setup(db.clone()).await;
    let (_, d) = call(
        &app,
        ADMIN,
        Method::POST,
        URL,
        Some(json!({ "key": "kw", "label": "Power", "kind": "number", "unit": "kW" })),
    )
    .await;
    let id = d["id"].as_str().unwrap().to_string();
    sqlx::query(
        "INSERT INTO products.product_attributes (product_id, key, kind, value_number)
         SELECT id, 'kw', 'number', 1 FROM products.products LIMIT 1",
    )
    .execute(&db)
    .await
    .unwrap();
    let (status, body) = call(&app, ADMIN, Method::DELETE, &format!("{URL}/{id}"), None).await;
    assert_eq!(status, StatusCode::CONFLICT, "{body}");
    let (status, u) = call(
        &app,
        ADMIN,
        Method::PUT,
        &format!("{URL}/{id}"),
        Some(json!({ "key": "kw", "label": "Power", "kind": "number", "unit": "kW", "active": false })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{u}");
    assert_eq!(u["active"], false);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn writes_need_products_write_and_reads_products_read(db: PgPool) {
    let app = setup(db).await;
    let (_, d) = call(
        &app,
        ADMIN,
        Method::POST,
        URL,
        Some(select_body("motion", "bell")),
    )
    .await;
    let id = d["id"].as_str().unwrap();
    let (status, _) = call(
        &app,
        READ_ONLY,
        Method::POST,
        URL,
        Some(select_body("m2", "bell")),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, _) = call(
        &app,
        READ_ONLY,
        Method::PUT,
        &format!("{URL}/{id}"),
        Some(select_body("motion", "bell")),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, _) = call(
        &app,
        READ_ONLY,
        Method::DELETE,
        &format!("{URL}/{id}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, _) = call(&app, READ_ONLY, Method::GET, URL, None).await;
    assert_eq!(status, StatusCode::OK);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn definitions_of_another_company_are_invisible_and_untouchable(db: PgPool) {
    let app = setup(db.clone()).await;
    let other = "00000000-0000-7000-8000-0000000fff01";
    let def = "00000000-0000-7000-8000-0000000fff02";
    sqlx::query("INSERT INTO core.companies (id, name) VALUES ($1::uuid, 'Other BV')")
        .bind(other)
        .execute(&db)
        .await
        .unwrap();
    sqlx::query("INSERT INTO products.attribute_definitions (id, company_id, key, label, kind) VALUES ($1::uuid, $2::uuid, 'motion', 'Theirs', 'text')")
        .bind(def)
        .bind(other)
        .execute(&db)
        .await
        .unwrap();
    let (_, list) = call(&app, ADMIN, Method::GET, URL, None).await;
    assert!(list.as_array().unwrap().is_empty());
    let (status, _) = call(&app, ADMIN, Method::GET, &format!("{URL}/{def}"), None).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, _) = call(
        &app,
        ADMIN,
        Method::PUT,
        &format!("{URL}/{def}"),
        Some(json!({ "key": "motion", "label": "Mine", "kind": "text" })),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, _) = call(&app, ADMIN, Method::DELETE, &format!("{URL}/{def}"), None).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    // The same key is free in this company.
    let (status, _) = call(
        &app,
        ADMIN,
        Method::POST,
        URL,
        Some(select_body("motion", "bell")),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);
}

async fn put(app: &axum::Router, id: &str, body: Value) -> (StatusCode, Value) {
    call(app, ADMIN, Method::PUT, &format!("{URL}/{id}"), Some(body)).await
}

async fn make(app: &axum::Router, body: Value) -> String {
    let (status, d) = call(app, ADMIN, Method::POST, URL, Some(body)).await;
    assert_eq!(status, StatusCode::CREATED, "{d}");
    d["id"].as_str().unwrap().to_string()
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn key_scope_and_kind_are_locked_while_product_values_exist(db: PgPool) {
    let app = setup(db.clone()).await;
    let id = make(
        &app,
        json!({ "key": "pw_t", "label": "Power", "kind": "number", "unit": "kW" }),
    )
    .await;
    // Unused: everything may change.
    let (status, u) = put(
        &app,
        &id,
        json!({ "key": "pw_t2", "label": "Power", "kind": "text" }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{u}");
    let (status, _) = put(
        &app,
        &id,
        json!({ "key": "pw_t", "label": "Power", "kind": "number", "unit": "kW" }),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    sqlx::query(
        "INSERT INTO products.product_attributes (product_id, key, kind, value_number)
         SELECT id, 'pw_t', 'number', 1 FROM products.products LIMIT 1",
    )
    .execute(&db)
    .await
    .unwrap();
    for body in [
        json!({ "key": "pw_t2", "label": "Power", "kind": "number", "unit": "kW" }),
        json!({ "key": "pw_t", "label": "Power", "kind": "number", "unit": "kW", "scope": "bell" }),
        json!({ "key": "pw_t", "label": "Power", "kind": "text" }),
    ] {
        let (status, r) = put(&app, &id, body.clone()).await;
        assert_eq!(status, StatusCode::CONFLICT, "{body} -> {r}");
    }
    // Label, unit, sort order and active stay editable.
    let (status, u) = put(
        &app,
        &id,
        json!({ "key": "pw_t", "label": "Motor power", "kind": "number", "unit": "W",
                "sort_order": 4, "active": false }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{u}");
    assert_eq!(u["label"], "Motor power");
    assert_eq!(u["unit"], "W");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn key_scope_and_kind_are_locked_while_baseline_values_exist(db: PgPool) {
    let app = setup(db.clone()).await;
    sqlx::query("SELECT crm.seed_baseline_defaults('00000000-0000-7000-8000-000000000001'::uuid)")
        .execute(&db)
        .await
        .unwrap();
    let id = make(
        &app,
        json!({ "key": "custom_x", "label": "X", "kind": "number", "scope": "bell" }),
    )
    .await;
    let other = make(
        &app,
        json!({ "key": "custom_y", "label": "Y", "kind": "number", "scope": "bell" }),
    )
    .await;
    sqlx::query(
        "INSERT INTO crm.opportunity_baseline_items (id, company_id, opportunity_id, type_code, \"values\")
         VALUES ('00000000-0000-7000-8000-0000000fff10', '00000000-0000-7000-8000-000000000001',
                 '00000000-0000-7000-8000-000000000701', 'bell', '{\"custom_x\": 5}')",
    )
    .execute(&db)
    .await
    .unwrap();
    for body in [
        json!({ "key": "custom_z", "label": "X", "kind": "number", "scope": "bell" }),
        json!({ "key": "custom_x", "label": "X", "kind": "number", "scope": "product" }),
        json!({ "key": "custom_x", "label": "X", "kind": "text", "scope": "bell" }),
    ] {
        let (status, r) = put(&app, &id, body.clone()).await;
        assert_eq!(status, StatusCode::CONFLICT, "{body} -> {r}");
    }
    let (status, u) = put(
        &app,
        &id,
        json!({ "key": "custom_x", "label": "Renamed", "kind": "number", "scope": "bell", "unit": "kg" }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{u}");
    // A definition whose key no item stores is still free to change.
    let (status, u) = put(
        &app,
        &other,
        json!({ "key": "custom_w", "label": "Y", "kind": "text", "scope": "bell" }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{u}");
}
