//! Sales favorites (ADR 0062): CRUD, company isolation, permissions, validation, stable item ids,
//! the add-only remark endpoint, and the two new quotation line fields through every path that
//! copies or rebuilds lines.

mod common;

use axum::http::{Method, StatusCode};
use common::{call, setup};
use serde_json::{json, Value};
use sqlx::PgPool;
use uuid::Uuid;

const SALES: &str = "sales@example.com";
const VIEWER: &str = "viewer@example.com"; // reads quotations, cannot write
const TECH: &str = "technician@example.com"; // no quotation rights
const OTHER: &str = "sales@other.example"; // role sales in another company
const OTHER_COMPANY: &str = "00000000-0000-7000-8000-0000000fff01";
const ALPHA: &str = "00000000-0000-7000-8000-000000000401"; // nl
const UNIT: &str = "00000000-0000-7000-8000-000000000301";
const PUMP: &str = "00000000-0000-7000-8000-000000000303";
const HOSE: &str = "00000000-0000-7000-8000-000000000304";
const INSTALL: &str = "00000000-0000-7000-8000-000000000305";

async fn send(
    app: &axum::Router,
    user: &str,
    method: Method,
    uri: &str,
    body: Option<Value>,
) -> (StatusCode, Value) {
    call(app, user, method, &format!("/api/v1{uri}"), body).await
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

/// A favorite payload: a main unit with a pump (per unit) and a hose option.
fn payload(name: &str) -> Value {
    json!({
        "name": name,
        "items": [
            { "product_id": UNIT, "quantity": "1", "comment": "Standard unit",
              "production_remark": "Weld first",
              "remarks": [{ "language": "nl", "text": "Inclusief montage" }] },
            { "product_id": PUMP, "quantity": "2", "parent_position": 1 },
            { "product_id": HOSE, "quantity": "10", "parent_position": 1, "section": "Piping" },
        ]
    })
}

async fn create(app: &axum::Router, name: &str) -> Value {
    let (status, f) = send(app, SALES, Method::POST, "/favorites", Some(payload(name))).await;
    assert_eq!(status, StatusCode::CREATED, "{f}");
    f
}

async fn audit_texts(db: &PgPool) -> String {
    sqlx::query_scalar::<_, Option<String>>(
        "SELECT string_agg(action || ' ' || data::text, ' | ') FROM audit.events WHERE entity = 'favorite'",
    )
    .fetch_one(db)
    .await
    .unwrap()
    .unwrap_or_default()
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn crud_and_list(db: PgPool) {
    let app = setup(db).await;
    let f = create(&app, "Standard unit set").await;
    let id = f["id"].as_str().unwrap();
    assert_eq!(f["items"].as_array().unwrap().len(), 3);
    assert_eq!(f["items"][0]["parent_position"], Value::Null);
    assert_eq!(f["items"][0]["product_code"], "UNIT-100");
    assert_eq!(f["items"][0]["product_active"], true);
    assert_eq!(f["items"][0]["remarks"][0]["language"], "nl");
    assert_eq!(f["items"][1]["parent_position"], 1);
    assert_eq!(f["items"][2]["section"], "Piping");
    assert!(f["items"][1].get("list_unit_price").is_none());

    let (status, g) = send(&app, SALES, Method::GET, &format!("/favorites/{id}"), None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(g, f);

    // A colleague with quotation rights sees the same favorite (company-wide).
    let (status, l) = send(&app, "manager@example.com", Method::GET, "/favorites", None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(l.as_array().unwrap().len(), 1);
    let s = &l[0];
    assert_eq!(s["name"], "Standard unit set");
    assert_eq!(s["main_product_code"], "UNIT-100");
    assert_eq!(s["option_count"], 2);
    assert_eq!(s["languages"], json!(["nl"]));

    create(&app, "Another").await;
    let (_, l) = send(&app, SALES, Method::GET, "/favorites?q=ANOTHER", None).await;
    assert_eq!(l.as_array().unwrap().len(), 1);
    let (_, l) = send(&app, SALES, Method::GET, "/favorites?q=unit-100", None).await;
    assert_eq!(l.as_array().unwrap().len(), 2);
    let (_, l) = send(
        &app,
        SALES,
        Method::GET,
        "/favorites?limit=1&offset=1",
        None,
    )
    .await;
    assert_eq!(l.as_array().unwrap().len(), 1);
    assert_eq!(l[0]["name"], "Standard unit set");

    // Rename and replace.
    let mut body = payload("Renamed");
    body["items"].as_array_mut().unwrap().pop();
    let (status, u) = send(
        &app,
        SALES,
        Method::PUT,
        &format!("/favorites/{id}"),
        Some(body),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{u}");
    assert_eq!(u["name"], "Renamed");
    assert_eq!(u["items"].as_array().unwrap().len(), 2);

    let (status, _) = send(
        &app,
        SALES,
        Method::DELETE,
        &format!("/favorites/{id}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    let (status, _) = send(&app, SALES, Method::GET, &format!("/favorites/{id}"), None).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn company_isolation(db: PgPool) {
    add_other_company_user(&db).await;
    let app = setup(db).await;
    let f = create(&app, "Mine").await;
    let id = f["id"].as_str().unwrap();
    let item = f["items"][0]["id"].as_str().unwrap();
    let (status, l) = send(&app, OTHER, Method::GET, "/favorites", None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(l, json!([]));
    for (m, uri, body) in [
        (Method::GET, format!("/favorites/{id}"), None),
        (Method::PUT, format!("/favorites/{id}"), Some(payload("X"))),
        (Method::DELETE, format!("/favorites/{id}"), None),
        (
            Method::PUT,
            format!("/favorites/items/{item}/remarks/fr"),
            Some(json!({ "text": "Montage inclus" })),
        ),
    ] {
        let (status, v) = send(&app, OTHER, m.clone(), &uri, body).await;
        assert_eq!(status, StatusCode::NOT_FOUND, "{m} {uri} {v}");
    }
    // The same name is free in the other company.
    let (status, _) = send(
        &app,
        OTHER,
        Method::POST,
        "/favorites",
        Some(payload("Mine")),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);
    // Still intact.
    let (_, g) = send(&app, SALES, Method::GET, &format!("/favorites/{id}"), None).await;
    assert_eq!(g, f);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn permissions(db: PgPool) {
    let app = setup(db).await;
    let f = create(&app, "Shared").await;
    let id = f["id"].as_str().unwrap();
    let item = f["items"][0]["id"].as_str().unwrap();
    let (status, _) = send(&app, VIEWER, Method::GET, "/favorites", None).await;
    assert_eq!(status, StatusCode::OK);
    let (status, _) = send(&app, VIEWER, Method::GET, &format!("/favorites/{id}"), None).await;
    assert_eq!(status, StatusCode::OK);
    for (m, uri, body) in [
        (Method::POST, "/favorites".to_string(), Some(payload("V"))),
        (Method::PUT, format!("/favorites/{id}"), Some(payload("V"))),
        (Method::DELETE, format!("/favorites/{id}"), None),
        (
            Method::PUT,
            format!("/favorites/items/{item}/remarks/fr"),
            Some(json!({ "text": "x" })),
        ),
    ] {
        let (status, _) = send(&app, VIEWER, m.clone(), &uri, body.clone()).await;
        assert_eq!(status, StatusCode::FORBIDDEN, "viewer {m} {uri}");
        let (status, _) = send(&app, TECH, m.clone(), &uri, body).await;
        assert_eq!(status, StatusCode::FORBIDDEN, "technician {m} {uri}");
    }
    for uri in ["/favorites".to_string(), format!("/favorites/{id}")] {
        let (status, _) = send(&app, TECH, Method::GET, &uri, None).await;
        assert_eq!(status, StatusCode::FORBIDDEN, "technician {uri}");
    }
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn names_are_unique_per_company_ignoring_case(db: PgPool) {
    let app = setup(db).await;
    let f = create(&app, "Pump Set").await;
    let (status, e) = send(
        &app,
        SALES,
        Method::POST,
        "/favorites",
        Some(payload("  pump SET ")),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT, "{e}");
    let other = create(&app, "Other").await;
    let oid = other["id"].as_str().unwrap();
    let (status, _) = send(
        &app,
        SALES,
        Method::PUT,
        &format!("/favorites/{oid}"),
        Some(payload("PUMP SET")),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
    // Renaming to its own name in another case is fine.
    let fid = f["id"].as_str().unwrap();
    let (status, u) = send(
        &app,
        SALES,
        Method::PUT,
        &format!("/favorites/{fid}"),
        Some(payload("PUMP SET")),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{u}");
}

async fn post_status(app: &axum::Router, body: Value) -> StatusCode {
    let (status, v) = send(app, SALES, Method::POST, "/favorites", Some(body)).await;
    if status != StatusCode::CREATED {
        assert!(
            v["error"].is_object() || v["code"].is_string() || v.is_object(),
            "{v}"
        );
    }
    status
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn validation_and_limits(db: PgPool) {
    let app = setup(db.clone()).await;
    sqlx::query("UPDATE products.products SET active = false WHERE id = $1::uuid")
        .bind(INSTALL)
        .execute(&db)
        .await
        .unwrap();
    let bad = StatusCode::UNPROCESSABLE_ENTITY;
    let mut cases: Vec<(&str, Value)> = Vec::new();
    let with = |f: &dyn Fn(&mut Value)| {
        let mut p = payload("V");
        f(&mut p);
        p
    };
    cases.push((
        "inactive product",
        with(&|p| p["items"][1]["product_id"] = json!(INSTALL)),
    ));
    cases.push((
        "unknown product",
        with(&|p| p["items"][1]["product_id"] = json!(Uuid::now_v7().to_string())),
    ));
    cases.push((
        "two main items",
        with(&|p| {
            p["items"][1]
                .as_object_mut()
                .unwrap()
                .remove("parent_position");
        }),
    ));
    cases.push(("no items", with(&|p| p["items"] = json!([]))));
    cases.push((
        "only options",
        with(&|p| {
            p["items"].as_array_mut().unwrap().remove(0);
        }),
    ));
    cases.push((
        "parent not earlier",
        with(&|p| p["items"][1]["parent_position"] = json!(2)),
    ));
    cases.push((
        "bad language",
        with(&|p| p["items"][0]["remarks"] = json!([{ "language": "it", "text": "x" }])),
    ));
    cases.push((
        "duplicate language",
        with(&|p| {
            p["items"][0]["remarks"] =
                json!([{ "language": "nl", "text": "a" }, { "language": "nl", "text": "b" }])
        }),
    ));
    cases.push((
        "long remark",
        with(&|p| {
            p["items"][0]["remarks"] = json!([{ "language": "nl", "text": "x".repeat(2001) }])
        }),
    ));
    cases.push((
        "long comment",
        with(&|p| p["items"][0]["comment"] = json!("x".repeat(2001))),
    ));
    cases.push((
        "long production remark",
        with(&|p| p["items"][0]["production_remark"] = json!("x".repeat(2001))),
    ));
    cases.push(("long name", with(&|p| p["name"] = json!("n".repeat(121)))));
    cases.push(("blank name", with(&|p| p["name"] = json!("  "))));
    cases.push((
        "zero quantity",
        with(&|p| p["items"][1]["quantity"] = json!("0")),
    ));
    cases.push((
        "percent on main",
        with(&|p| p["items"][0]["percent_of_parent"] = json!("10")),
    ));
    cases.push((
        "base without percent",
        with(&|p| p["items"][1]["percent_base"] = json!("parent_list_unit_price")),
    ));
    cases.push((
        "item id on create",
        with(&|p| p["items"][0]["id"] = json!(Uuid::now_v7().to_string())),
    ));
    for (what, body) in cases {
        assert_eq!(post_status(&app, body).await, bad, "{what}");
    }

    // The limit: 40 items are fine, 41 are not.
    let many = |n: usize| {
        let mut items = vec![json!({ "product_id": UNIT, "quantity": "1" })];
        for _ in 1..n {
            items.push(json!({ "product_id": PUMP, "quantity": "1", "parent_position": 1 }));
        }
        json!({ "name": format!("many {n}"), "items": items })
    };
    assert_eq!(post_status(&app, many(40)).await, StatusCode::CREATED);
    assert_eq!(post_status(&app, many(41)).await, bad);

    // Blank remark texts are dropped; a percent line stores its base.
    let (status, f) = send(
        &app,
        SALES,
        Method::POST,
        "/favorites",
        Some(json!({ "name": "Percent", "items": [
            { "product_id": UNIT, "quantity": "1", "remarks": [{ "language": "fr", "text": "  " }] },
            { "product_id": INSTALL.replace("305", "304"), "quantity": "1", "parent_position": 1,
              "percent_of_parent": "5", "percent_base": "parent_net_unit_price" }] })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{f}");
    assert_eq!(f["items"][0]["remarks"], json!([]));
    assert_eq!(f["items"][1]["percent_base"], "parent_net_unit_price");
    assert_eq!(f["items"][1]["percent_of_parent"], "5.000");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn inactive_product_is_flagged_and_does_not_block_a_rename(db: PgPool) {
    let app = setup(db.clone()).await;
    let f = create(&app, "Old").await;
    let id = f["id"].as_str().unwrap();
    sqlx::query("UPDATE products.products SET active = false WHERE id = $1::uuid")
        .bind(HOSE)
        .execute(&db)
        .await
        .unwrap();
    let (_, g) = send(&app, SALES, Method::GET, &format!("/favorites/{id}"), None).await;
    assert_eq!(g["items"][2]["product_active"], false);
    assert_eq!(g["items"][1]["product_active"], true);
    // Rename, sending the items with their ids: the inactive product on an existing item is kept.
    let mut body = payload("Older");
    for (i, it) in body["items"].as_array_mut().unwrap().iter_mut().enumerate() {
        it["id"] = g["items"][i]["id"].clone();
    }
    let (status, u) = send(
        &app,
        SALES,
        Method::PUT,
        &format!("/favorites/{id}"),
        Some(body),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{u}");
    assert_eq!(u["items"][2]["product_active"], false);
    // A new item cannot use it.
    let mut body = payload("Older");
    body["items"]
        .as_array_mut()
        .unwrap()
        .push(json!({ "product_id": HOSE, "quantity": "1", "parent_position": 1 }));
    let (status, _) = send(
        &app,
        SALES,
        Method::PUT,
        &format!("/favorites/{id}"),
        Some(body),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn put_keeps_item_ids_stable(db: PgPool) {
    let app = setup(db).await;
    let f = create(&app, "Stable").await;
    let id = f["id"].as_str().unwrap();
    let ids: Vec<String> = f["items"]
        .as_array()
        .unwrap()
        .iter()
        .map(|i| i["id"].as_str().unwrap().to_string())
        .collect();
    // Keep main and hose (moved up), drop the pump, add the installation.
    let body = json!({ "name": "Stable", "items": [
        { "id": ids[0], "product_id": UNIT, "quantity": "1", "remarks": [{ "language": "nl", "text": "Inclusief montage" }] },
        { "id": ids[2], "product_id": HOSE, "quantity": "12", "parent_position": 1 },
        { "product_id": INSTALL, "quantity": "3", "parent_position": 1 },
    ]});
    let (status, u) = send(
        &app,
        SALES,
        Method::PUT,
        &format!("/favorites/{id}"),
        Some(body),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{u}");
    assert_eq!(u["items"][0]["id"], ids[0]);
    assert_eq!(u["items"][1]["id"], ids[2]);
    assert_eq!(u["items"][1]["position"], 2);
    assert_eq!(u["items"][1]["quantity"], "12.0000");
    assert_ne!(u["items"][2]["id"], ids[1]);
    assert_eq!(u["items"][2]["product_code"], "INSTALL");

    // The main item can move to another existing item (ids swap roles) without a conflict.
    let main2 = u["items"][1]["id"].clone();
    let main1 = u["items"][0]["id"].clone();
    let body = json!({ "name": "Stable", "items": [
        { "id": main2, "product_id": HOSE, "quantity": "1" },
        { "id": main1, "product_id": UNIT, "quantity": "1", "parent_position": 1 },
    ]});
    let (status, u2) = send(
        &app,
        SALES,
        Method::PUT,
        &format!("/favorites/{id}"),
        Some(body),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{u2}");
    assert_eq!(u2["items"][0]["id"], main2);
    assert_eq!(u2["items"][1]["id"], main1);

    // An item id of another favorite is refused.
    let other = create(&app, "Other").await;
    let body = json!({ "name": "Stable", "items": [
        { "id": other["items"][0]["id"], "product_id": UNIT, "quantity": "1" }] });
    let (status, _) = send(
        &app,
        SALES,
        Method::PUT,
        &format!("/favorites/{id}"),
        Some(body),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn remarks_endpoint_is_add_only_by_default(db: PgPool) {
    let app = setup(db.clone()).await;
    let f = create(&app, "Texts").await;
    let id = f["id"].as_str().unwrap();
    let item = f["items"][0]["id"].as_str().unwrap();
    let uri = |l: &str| format!("/favorites/items/{item}/remarks/{l}");

    let (status, r) = send(
        &app,
        SALES,
        Method::PUT,
        &uri("fr"),
        Some(json!({ "text": " Montage inclus " })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{r}");
    assert_eq!(
        r["items"][0]["remarks"],
        json!([
        { "language": "nl", "text": "Inclusief montage" },
        { "language": "fr", "text": "Montage inclus" }])
    );
    let (_, l) = send(&app, SALES, Method::GET, "/favorites", None).await;
    assert_eq!(l[0]["languages"], json!(["nl", "fr"]));

    // An existing language is never silently replaced.
    let (status, e) = send(
        &app,
        SALES,
        Method::PUT,
        &uri("fr"),
        Some(json!({ "text": "Autre" })),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT, "{e}");
    let (status, e) = send(
        &app,
        SALES,
        Method::PUT,
        &uri("fr"),
        Some(json!({ "text": "Autre", "overwrite": false })),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT, "{e}");
    let (status, r) = send(
        &app,
        SALES,
        Method::PUT,
        &uri("fr"),
        Some(json!({ "text": "Autre", "overwrite": true })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{r}");
    assert_eq!(r["items"][0]["remarks"][1]["text"], "Autre");

    // Validation and 404.
    let (status, _) = send(
        &app,
        SALES,
        Method::PUT,
        &uri("it"),
        Some(json!({ "text": "x" })),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    let (status, _) = send(
        &app,
        SALES,
        Method::PUT,
        &uri("de"),
        Some(json!({ "text": "  " })),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    let (status, _) = send(
        &app,
        SALES,
        Method::PUT,
        &uri("de"),
        Some(json!({ "text": "x".repeat(2001) })),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    let (status, _) = send(
        &app,
        SALES,
        Method::PUT,
        &format!("/favorites/items/{}/remarks/de", Uuid::now_v7()),
        Some(json!({ "text": "x" })),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (_, g) = send(&app, SALES, Method::GET, &format!("/favorites/{id}"), None).await;
    assert_eq!(g["items"][0]["remarks"].as_array().unwrap().len(), 2);

    // Audit: the actions, ids and languages, never the text.
    let audit = audit_texts(&db).await;
    assert!(
        audit.contains("remark_added") && audit.contains("remark_replaced"),
        "{audit}"
    );
    for text in [
        "Montage inclus",
        "Autre",
        "Inclusief montage",
        "Standard unit",
        "Weld first",
    ] {
        assert!(
            !audit.contains(text),
            "{text} leaked into the audit trail: {audit}"
        );
    }
    assert!(audit.contains("text_changed"));
}

/// A quotation draft body with a favorite line and its option.
fn quote_body(item_main: &str, item_option: &str) -> Value {
    json!({ "customer_id": ALPHA, "lines": [
        { "product_id": UNIT, "quantity": "1", "customer_remark": "Inclusief montage",
          "customer_remark_language": "nl", "favorite_item_id": item_main },
        { "product_id": PUMP, "quantity": "2", "parent_position": 1,
          "customer_remark": "Pompe incluse", "customer_remark_language": "fr",
          "favorite_item_id": item_option },
        { "product_id": HOSE, "quantity": "3", "parent_position": 1 },
    ]})
}

fn assert_link(q: &Value, main: &str, option: &str, what: &str) {
    assert_eq!(q["lines"][0]["customer_remark_language"], "nl", "{what}");
    assert_eq!(q["lines"][0]["favorite_item_id"], main, "{what}");
    assert_eq!(q["lines"][1]["customer_remark_language"], "fr", "{what}");
    assert_eq!(q["lines"][1]["favorite_item_id"], option, "{what}");
    assert!(
        q["lines"][2]["customer_remark_language"].is_null(),
        "{what}"
    );
    assert!(q["lines"][2]["favorite_item_id"].is_null(), "{what}");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn line_fields_round_trip_and_survive_revisions(db: PgPool) {
    let app = setup(db.clone()).await;
    let f = create(&app, "Lines").await;
    let main = f["items"][0]["id"].as_str().unwrap().to_string();
    let option = f["items"][1]["id"].as_str().unwrap().to_string();

    let (status, q) = send(
        &app,
        SALES,
        Method::POST,
        "/quotations",
        Some(quote_body(&main, &option)),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{q}");
    assert_link(&q, &main, &option, "create");
    let id = q["id"].as_str().unwrap().to_string();
    let (_, got) = send(&app, SALES, Method::GET, &format!("/quotations/{id}"), None).await;
    assert_link(&got, &main, &option, "get");

    // update_draft: the client sends the fields again; left out they are cleared.
    let (status, u) = send(
        &app,
        SALES,
        Method::PUT,
        &format!("/quotations/{id}"),
        Some(quote_body(&main, &option)),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{u}");
    assert_link(&u, &main, &option, "update");
    let (status, u) = send(&app, SALES, Method::PUT, &format!("/quotations/{id}"),
        Some(json!({ "customer_id": ALPHA, "lines": [{ "product_id": UNIT, "quantity": "1", "customer_remark": "x" }] }))).await;
    assert_eq!(status, StatusCode::OK, "{u}");
    assert!(u["lines"][0]["favorite_item_id"].is_null());
    assert!(u["lines"][0]["customer_remark_language"].is_null());
    let (status, u) = send(
        &app,
        SALES,
        Method::PUT,
        &format!("/quotations/{id}"),
        Some(quote_body(&main, &option)),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{u}");

    // An empty remark stores no language.
    let (status, e) = send(
        &app,
        SALES,
        Method::POST,
        "/quotations",
        Some(json!({ "customer_id": ALPHA, "lines": [
        { "product_id": UNIT, "quantity": "1", "customer_remark_language": "de" }] })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{e}");
    assert!(e["lines"][0]["customer_remark_language"].is_null());

    // Revisions: Keep copies the stored lines, Current rebuilds them through the inputs.
    let (status, _) = send(
        &app,
        SALES,
        Method::POST,
        &format!("/quotations/{id}/send"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let mut current = id.clone();
    for pricing in ["keep", "current"] {
        let (status, r) = send(
            &app,
            SALES,
            Method::POST,
            &format!("/quotations/{current}/revise"),
            Some(json!({ "pricing": pricing })),
        )
        .await;
        assert_eq!(status, StatusCode::CREATED, "{r}");
        assert_link(&r, &main, &option, pricing);
        current = r["id"].as_str().unwrap().to_string();
        let (status, _) = send(
            &app,
            SALES,
            Method::POST,
            &format!("/quotations/{current}/send"),
            None,
        )
        .await;
        assert_eq!(status, StatusCode::OK);
    }

    // Pricing preview accepts them too, and validates them.
    let (status, p) = send(
        &app,
        SALES,
        Method::POST,
        "/pricing/preview",
        Some(quote_body(&main, &option)),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{p}");

    // The order does not take them: order lines have no such columns.
    let (status, o) = send(
        &app,
        SALES,
        Method::POST,
        &format!("/quotations/{current}/convert"),
        Some(json!({})),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{o}");
    assert!(o["lines"][0].get("favorite_item_id").is_none());
    assert!(o["lines"][0].get("customer_remark_language").is_none());
    let cols: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM information_schema.columns WHERE table_schema = 'sales'
         AND table_name = 'order_lines' AND column_name IN ('favorite_item_id', 'customer_remark_language')",
    )
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(cols, 0);
    let (_, still) = send(
        &app,
        SALES,
        Method::GET,
        &format!("/quotations/{current}"),
        None,
    )
    .await;
    assert_link(&still, &main, &option, "quotation after conversion");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn line_fields_are_validated(db: PgPool) {
    add_other_company_user(&db).await;
    let app = setup(db).await;
    let (status, theirs) = send(
        &app,
        OTHER,
        Method::POST,
        "/favorites",
        Some(payload("Theirs")),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{theirs}");
    let foreign = theirs["items"][0]["id"].as_str().unwrap();
    let bad = StatusCode::UNPROCESSABLE_ENTITY;
    for body in [
        quote_body(foreign, foreign),
        quote_body(&Uuid::now_v7().to_string(), &Uuid::now_v7().to_string()),
    ] {
        let (status, e) = send(&app, SALES, Method::POST, "/quotations", Some(body.clone())).await;
        assert_eq!(status, bad, "{e}");
        let (status, _) = send(&app, SALES, Method::POST, "/pricing/preview", Some(body)).await;
        assert_eq!(status, bad);
    }
    let (status, e) = send(&app, SALES, Method::POST, "/quotations", Some(json!({ "customer_id": ALPHA, "lines": [
        { "product_id": UNIT, "quantity": "1", "customer_remark": "x", "customer_remark_language": "it" }] }))).await;
    assert_eq!(status, bad, "{e}");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn deleting_a_favorite_leaves_the_lines_with_a_null_link(db: PgPool) {
    let app = setup(db.clone()).await;
    let f = create(&app, "Gone").await;
    let id = f["id"].as_str().unwrap();
    let main = f["items"][0]["id"].as_str().unwrap().to_string();
    let option = f["items"][1]["id"].as_str().unwrap().to_string();
    let (_, q) = send(
        &app,
        SALES,
        Method::POST,
        "/quotations",
        Some(quote_body(&main, &option)),
    )
    .await;
    let qid = q["id"].as_str().unwrap();

    // Dropping an item through PUT unlinks only that item's lines.
    let body =
        json!({ "name": "Gone", "items": [{ "id": main, "product_id": UNIT, "quantity": "1" }] });
    let (status, _) = send(
        &app,
        SALES,
        Method::PUT,
        &format!("/favorites/{id}"),
        Some(body),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (_, g) = send(
        &app,
        SALES,
        Method::GET,
        &format!("/quotations/{qid}"),
        None,
    )
    .await;
    assert_eq!(g["lines"][0]["favorite_item_id"], main.as_str());
    assert!(g["lines"][1]["favorite_item_id"].is_null());
    assert_eq!(g["lines"][1]["customer_remark"], "Pompe incluse");

    let (status, _) = send(
        &app,
        SALES,
        Method::DELETE,
        &format!("/favorites/{id}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    let (_, g) = send(
        &app,
        SALES,
        Method::GET,
        &format!("/quotations/{qid}"),
        None,
    )
    .await;
    assert!(g["lines"][0]["favorite_item_id"].is_null());
    assert_eq!(g["lines"][0]["customer_remark"], "Inclusief montage");
    assert_eq!(g["lines"][0]["customer_remark_language"], "nl");
    let left: i64 = sqlx::query_scalar("SELECT count(*) FROM sales.favorite_items")
        .fetch_one(&db)
        .await
        .unwrap();
    assert_eq!(left, 0);
    // The stale id is refused on the next save.
    let (status, _) = send(
        &app,
        SALES,
        Method::PUT,
        &format!("/quotations/{qid}"),
        Some(quote_body(&main, &option)),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn audit_has_ids_and_names_but_no_text(db: PgPool) {
    let app = setup(db.clone()).await;
    let f = create(&app, "Audited").await;
    let id = f["id"].as_str().unwrap();
    let mut body = payload("Audited 2");
    body["items"][0]["comment"] = json!("Secret comment");
    body["items"][0]["remarks"] = json!([{ "language": "de", "text": "Geheimer Text" }]);
    let (status, _) = send(
        &app,
        SALES,
        Method::PUT,
        &format!("/favorites/{id}"),
        Some(body),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (status, _) = send(
        &app,
        SALES,
        Method::DELETE,
        &format!("/favorites/{id}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    let audit = audit_texts(&db).await;
    for action in ["created", "updated", "deleted"] {
        assert!(audit.contains(&format!("{action} ")), "{action}: {audit}");
    }
    assert!(audit.contains("Audited 2") && audit.contains(UNIT));
    for text in [
        "Secret comment",
        "Geheimer Text",
        "Inclusief montage",
        "Standard unit",
        "Weld first",
    ] {
        assert!(!audit.contains(text), "{text} leaked: {audit}");
    }
    assert!(audit.contains("\"text_changed\": true"), "{audit}");
}
