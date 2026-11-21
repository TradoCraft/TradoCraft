//! Product relation rules, computed co-occurrence and the quotation conflicts and suggestions.

mod common;

use axum::http::{Method, StatusCode};
use common::{call, setup};
use serde_json::{json, Value};
use sqlx::PgPool;
use uuid::Uuid;

const ALPHA: &str = "00000000-0000-7000-8000-000000000401"; // BE
const UNIT_100: &str = "00000000-0000-7000-8000-000000000301";
const PUMP: &str = "00000000-0000-7000-8000-000000000303";
const HOSE: &str = "00000000-0000-7000-8000-000000000304";
const INSTALL: &str = "00000000-0000-7000-8000-000000000305";
const PROFILE: &str = "00000000-0000-7000-8000-000000000308";
const BOLT: &str = "00000000-0000-7000-8000-000000000309";
const CTRL: &str = "00000000-0000-7000-8000-000000000310";
const FAM_PUMPS: &str = "00000000-0000-7000-8000-000000000802";
const FAM_ELECTRONICS: &str = "00000000-0000-7000-8000-000000000804";
const FAM_SERVICES: &str = "00000000-0000-7000-8000-000000000806";
const SALES: &str = "sales@example.com";
const ADMIN: &str = "admin@example.com";
const VIEWER: &str = "viewer@example.com";

async fn api(
    app: &axum::Router,
    user: &str,
    method: Method,
    uri: &str,
    body: Option<Value>,
) -> (StatusCode, Value) {
    call(app, user, method, &format!("/api/v1{uri}"), body).await
}

async fn quote(app: &axum::Router, products: &[&str], extra: Value) -> Value {
    let lines: Vec<Value> = products
        .iter()
        .map(|p| json!({ "product_id": p, "quantity": "1" }))
        .collect();
    let mut body = json!({ "customer_id": ALPHA, "lines": lines });
    for (k, v) in extra.as_object().unwrap() {
        body[k] = v.clone();
    }
    let (status, q) = api(app, SALES, Method::POST, "/quotations", Some(body)).await;
    assert_eq!(status, StatusCode::CREATED, "{q}");
    q
}

fn incompatible(v: &Value) -> Vec<Value> {
    v["warnings"]
        .as_array()
        .expect("warnings array")
        .iter()
        .filter(|w| w["kind"] == "incompatible_products")
        .cloned()
        .collect()
}

fn suggested(v: &Value) -> Vec<(String, String)> {
    v["suggestions"]
        .as_array()
        .expect("suggestions array")
        .iter()
        .map(|s| {
            (
                s["product_code"].as_str().unwrap().to_string(),
                s["reason"].as_str().unwrap().to_string(),
            )
        })
        .collect()
}

async fn rule(app: &axum::Router, body: Value) -> Value {
    let (status, r) = api(app, ADMIN, Method::POST, "/product-relations", Some(body)).await;
    assert_eq!(status, StatusCode::CREATED, "{r}");
    r
}

/// Inserts co-occurrence rows with the pair ordered (a < b).
async fn cooccurrence(db: &PgPool, a: &str, b: &str, together: i32, with_a: i32, with_b: i32) {
    let (a, b) = (Uuid::parse_str(a).unwrap(), Uuid::parse_str(b).unwrap());
    let (a, b, wa, wb) = if a < b {
        (a, b, with_a, with_b)
    } else {
        (b, a, with_b, with_a)
    };
    sqlx::query(
        "INSERT INTO products.product_cooccurrence
            (product_a_id, product_b_id, orders_together, orders_with_a, orders_with_b)
         VALUES ($1, $2, $3, $4, $5)",
    )
    .bind(a)
    .bind(b)
    .bind(together)
    .bind(wa)
    .bind(wb)
    .execute(db)
    .await
    .unwrap();
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn relation_crud_permissions_and_validation(db: PgPool) {
    let app = setup(db.clone()).await;
    // Seeded rules are readable by anyone with products.read, filterable.
    let (status, all) = api(&app, VIEWER, Method::GET, "/product-relations", None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(all.as_array().unwrap().len(), 4);
    let (_, inc) = api(
        &app,
        SALES,
        Method::GET,
        "/product-relations?kind=incompatible",
        None,
    )
    .await;
    assert_eq!(inc.as_array().unwrap().len(), 1);
    assert_eq!(inc[0]["a_product_code"], "HOSE-25");
    assert_eq!(inc[0]["b_product_code"], "PROFILE-40");
    let (_, by_product) = api(
        &app,
        SALES,
        Method::GET,
        &format!("/product-relations?product_id={PUMP}"),
        None,
    )
    .await;
    assert_eq!(
        by_product.as_array().unwrap().len(),
        2,
        "compatible + suggested"
    );
    let (_, by_family) = api(
        &app,
        SALES,
        Method::GET,
        &format!("/product-relations?family_id={FAM_SERVICES}"),
        None,
    )
    .await;
    assert_eq!(by_family.as_array().unwrap().len(), 1);
    // A product in the SERVICES family matches the family rule through its family.
    let (_, by_install) = api(
        &app,
        SALES,
        Method::GET,
        &format!("/product-relations?product_id={INSTALL}"),
        None,
    )
    .await;
    assert_eq!(by_install.as_array().unwrap().len(), 1);
    let (status, _) = api(
        &app,
        SALES,
        Method::GET,
        "/product-relations?kind=bogus",
        None,
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    let good = json!({ "kind": "incompatible", "a_product_id": BOLT, "b_family_id": FAM_PUMPS, "note": " no " });
    // Writing needs products.write.
    for user in [SALES, VIEWER] {
        let (status, _) = api(
            &app,
            user,
            Method::POST,
            "/product-relations",
            Some(good.clone()),
        )
        .await;
        assert_eq!(status, StatusCode::FORBIDDEN, "{user}");
    }
    let r = rule(&app, good.clone()).await;
    assert_eq!(r["a_product_code"], "BOLT-M8");
    assert_eq!(r["b_family_code"], "PUMPS");
    assert_eq!(r["bidirectional"], true);
    assert_eq!(r["strength"], 50);
    assert_eq!(r["note"], "no");
    let id = r["id"].as_str().unwrap();

    // Exactly one per side.
    for bad in [
        json!({ "kind": "incompatible", "b_family_id": FAM_PUMPS }),
        json!({ "kind": "incompatible", "a_product_id": BOLT }),
        json!({ "kind": "incompatible", "a_product_id": BOLT, "a_family_id": FAM_PUMPS, "b_product_id": PUMP }),
        json!({ "kind": "incompatible", "a_product_id": BOLT, "b_product_id": PUMP, "b_family_id": FAM_PUMPS }),
        json!({ "kind": "bogus", "a_product_id": BOLT, "b_product_id": PUMP }),
        json!({ "kind": "suggested", "a_product_id": BOLT, "b_product_id": BOLT }),
        json!({ "kind": "suggested", "a_product_id": BOLT, "b_product_id": PUMP, "strength": 0 }),
        json!({ "kind": "suggested", "a_product_id": BOLT, "b_product_id": PUMP, "strength": 101 }),
        json!({ "kind": "suggested", "a_product_id": BOLT, "b_product_id": Uuid::nil() }),
        json!({ "kind": "suggested", "a_family_id": Uuid::nil(), "b_product_id": PUMP }),
    ] {
        let (status, r) = api(
            &app,
            ADMIN,
            Method::POST,
            "/product-relations",
            Some(bad.clone()),
        )
        .await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{bad}: {r}");
    }

    // Duplicates, also with swapped sides.
    let (status, _) = api(&app, ADMIN, Method::POST, "/product-relations", Some(good)).await;
    assert_eq!(status, StatusCode::CONFLICT);
    let swapped = json!({ "kind": "incompatible", "a_family_id": FAM_PUMPS, "b_product_id": BOLT });
    let (status, _) = api(
        &app,
        ADMIN,
        Method::POST,
        "/product-relations",
        Some(swapped),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);

    // Update and deactivate; unknown id is 404.
    let upd = json!({ "kind": "suggested", "a_product_id": BOLT, "b_family_id": FAM_PUMPS,
                      "strength": 90, "bidirectional": false, "active": false });
    let (status, u) = api(
        &app,
        ADMIN,
        Method::PUT,
        &format!("/product-relations/{id}"),
        Some(upd.clone()),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{u}");
    assert_eq!(
        (
            u["kind"].as_str(),
            u["strength"].as_i64(),
            u["active"].as_bool()
        ),
        (Some("suggested"), Some(90), Some(false))
    );
    assert_eq!(u["bidirectional"], false);
    let (status, _) = api(
        &app,
        SALES,
        Method::PUT,
        &format!("/product-relations/{id}"),
        Some(upd.clone()),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, _) = api(
        &app,
        ADMIN,
        Method::PUT,
        &format!("/product-relations/{}", Uuid::nil()),
        Some(upd),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, _) = api(
        &app,
        ADMIN,
        Method::PUT,
        &format!("/product-relations/{id}"),
        Some(json!({ "kind": "suggested", "a_product_id": BOLT, "b_family_id": FAM_PUMPS, "a_family_id": FAM_PUMPS })),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    let audits: i64 =
        sqlx::query_scalar("SELECT count(*) FROM audit.events WHERE entity = 'product_relation'")
            .fetch_one(&db)
            .await
            .unwrap();
    assert_eq!(audits, 2, "one created, one updated");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn quotation_warns_about_incompatible_pairs(db: PgPool) {
    let app = setup(db).await;
    // Seeded: HOSE-25 and PROFILE-40 are incompatible.
    let q = quote(&app, &[HOSE, BOLT, PROFILE], json!({})).await;
    let w = incompatible(&q);
    assert_eq!(w.len(), 1, "{q}");
    assert_eq!(
        w[0]["details"]["product_codes"],
        json!(["HOSE-25", "PROFILE-40"])
    );
    assert_eq!(
        w[0]["details"]["note"],
        "The hose clamps do not fit the 40x40 profile"
    );
    assert!(w[0]["message"].as_str().unwrap().contains("HOSE-25"));
    assert!(w[0]["message"].as_str().unwrap().contains("PROFILE-40"));
    let qid = q["id"].as_str().unwrap();

    // Update, order of lines does not matter.
    let (status, u) = api(
        &app,
        SALES,
        Method::PUT,
        &format!("/quotations/{qid}"),
        Some(json!({ "customer_id": ALPHA, "lines": [
            { "product_id": PROFILE, "quantity": "1" }, { "product_id": HOSE, "quantity": "1" }] })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{u}");
    assert_eq!(incompatible(&u).len(), 1);
    // GET returns empty hints.
    let (_, g) = api(
        &app,
        SALES,
        Method::GET,
        &format!("/quotations/{qid}"),
        None,
    )
    .await;
    assert!(g["warnings"].as_array().unwrap().is_empty());
    assert!(g["suggestions"].as_array().unwrap().is_empty());

    // The pricing preview carries it too.
    let (status, p) = api(
        &app,
        SALES,
        Method::POST,
        "/pricing/preview",
        Some(json!({ "customer_id": ALPHA, "lines": [
            { "product_id": HOSE, "quantity": "1" }, { "product_id": PROFILE, "quantity": "1" }] })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{p}");
    let warnings = incompatible(&p);
    assert_eq!(warnings.len(), 1, "{p}");
    assert_eq!(
        warnings[0]["details"]["product_codes"],
        w[0]["details"]["product_codes"]
    );
    assert_eq!(warnings[0]["details"]["note"], w[0]["details"]["note"]);
    // The warning does not prevent either line from being priced.
    assert_eq!(p["lines"].as_array().unwrap().len(), 2);
    // Stock purpose: neither on the quotation nor in the preview.
    let q = quote(&app, &[HOSE, PROFILE], json!({ "purpose": "stock" })).await;
    assert!(incompatible(&q).is_empty());
    assert!(q["suggestions"].as_array().unwrap().is_empty());
    let (_, p) = api(
        &app,
        SALES,
        Method::POST,
        "/pricing/preview",
        Some(json!({ "customer_id": ALPHA, "purpose": "stock", "lines": [
            { "product_id": HOSE, "quantity": "1" }, { "product_id": PROFILE, "quantity": "1" }] })),
    )
    .await;
    assert!(incompatible(&p).is_empty());

    // Compatible pair and pairs without a rule: no conflict.
    let q = quote(&app, &[UNIT_100, PUMP], json!({})).await;
    assert!(incompatible(&q).is_empty());
    let q = quote(&app, &[HOSE, BOLT, CTRL], json!({})).await;
    assert!(incompatible(&q).is_empty());
    // Only one side present.
    let q = quote(&app, &[PROFILE, BOLT], json!({})).await;
    assert!(incompatible(&q).is_empty());

    // Deactivated rules do not warn.
    let (_, rules) = api(
        &app,
        SALES,
        Method::GET,
        "/product-relations?kind=incompatible",
        None,
    )
    .await;
    let r = &rules[0];
    let id = r["id"].as_str().unwrap();
    let (status, _) = api(
        &app,
        ADMIN,
        Method::PUT,
        &format!("/product-relations/{id}"),
        Some(json!({ "kind": "incompatible", "a_product_id": HOSE, "b_product_id": PROFILE, "active": false })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let q = quote(&app, &[HOSE, PROFILE], json!({})).await;
    assert!(incompatible(&q).is_empty());
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn family_level_rule_warns(db: PgPool) {
    let app = setup(db).await;
    // No rule yet between pumps and electronics.
    let q = quote(&app, &[PUMP, CTRL], json!({})).await;
    assert!(incompatible(&q).is_empty());
    rule(
        &app,
        json!({ "kind": "incompatible", "a_family_id": FAM_PUMPS, "b_family_id": FAM_ELECTRONICS,
                "note": "not on one panel" }),
    )
    .await;
    let q = quote(&app, &[PUMP, CTRL], json!({})).await;
    let w = incompatible(&q);
    assert_eq!(w.len(), 1, "{q}");
    assert_eq!(w[0]["details"]["note"], "not on one panel");
    // A product against a family, one-way rule, both orders in the set.
    rule(
        &app,
        json!({ "kind": "incompatible", "a_product_id": BOLT, "b_family_id": FAM_ELECTRONICS,
                "bidirectional": false }),
    )
    .await;
    assert_eq!(
        incompatible(&quote(&app, &[CTRL, BOLT], json!({})).await).len(),
        1
    );
    // The incompatible product is no longer suggested next to what it clashes with.
    let q = quote(&app, &[BOLT, PUMP], json!({})).await;
    assert!(suggested(&q).iter().all(|(c, _)| c != "CTRL-01"), "{q}");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn suggestions_from_manual_rules(db: PgPool) {
    let app = setup(db.clone()).await;
    // Seeded: PUMP-05 -> CTRL-01 (80); UNIT-100 -> family SERVICES (40, one-way).
    let q = quote(&app, &[PUMP], json!({})).await;
    assert_eq!(
        suggested(&q),
        [("CTRL-01".to_string(), "rule".to_string())],
        "{q}"
    );
    let s = &q["suggestions"][0];
    assert_eq!(s["strength"], 80);
    assert!(s["confidence"].is_null());
    assert_eq!(s["because_of_code"], "PUMP-05");
    assert_eq!(s["note"], "A pump needs a controller");
    assert_eq!(s["product_id"], CTRL);
    // One-way: the controller does not suggest the pump.
    assert!(suggested(&quote(&app, &[CTRL], json!({})).await).is_empty());
    // Already in the set: not suggested.
    assert!(suggested(&quote(&app, &[PUMP, CTRL], json!({})).await).is_empty());
    // Family side expands to the active products of the family.
    let q = quote(&app, &[UNIT_100], json!({})).await;
    let codes: Vec<String> = suggested(&q).into_iter().map(|(c, _)| c).collect();
    assert_eq!(codes, ["INSTALL", "TRAVEL"], "{q}");
    // The compatible rule suggests nothing and the pricing preview carries suggestions.
    let (status, p) = api(
        &app,
        SALES,
        Method::POST,
        "/pricing/preview",
        Some(json!({ "customer_id": ALPHA, "lines": [{ "product_id": PUMP, "quantity": "1" }] })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{p}");
    assert_eq!(
        suggested(&p),
        [("CTRL-01".to_string(), "rule".to_string())],
        "{p}"
    );
    // Stock purpose: none.
    let q = quote(&app, &[PUMP], json!({ "purpose": "stock" })).await;
    assert!(suggested(&q).is_empty());

    // The product view of the same thing.
    let (status, r) = api(
        &app,
        SALES,
        Method::GET,
        &format!("/products/{PUMP}/related"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{r}");
    assert_eq!(r["rules"].as_array().unwrap().len(), 2);
    assert_eq!(r["suggestions"].as_array().unwrap().len(), 1);
    let (status, _) = api(
        &app,
        SALES,
        Method::GET,
        &format!("/products/{}/related", Uuid::nil()),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    // An inactive product is never suggested.
    sqlx::query("UPDATE products.products SET active = false WHERE id = $1")
        .bind(Uuid::parse_str(CTRL).unwrap())
        .execute(&db)
        .await
        .unwrap();
    assert!(suggested(&quote(&app, &[PUMP], json!({})).await).is_empty());
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn computed_suggestions_respect_thresholds_and_manual_wins(db: PgPool) {
    let app = setup(db.clone()).await;
    // PUMP is in 10 orders: 6 with BOLT (0.6), 2 with HOSE (below the minimum of 3 orders),
    // 3 with PROFILE (0.3 but that is exactly the minimum), 10 with CTRL (also a manual rule).
    // BOLT is common: from BOLT's side PUMP has a low confidence.
    cooccurrence(&db, PUMP, BOLT, 6, 10, 60).await;
    cooccurrence(&db, PUMP, HOSE, 2, 10, 2).await;
    cooccurrence(&db, PUMP, PROFILE, 3, 10, 3).await;
    cooccurrence(&db, PUMP, CTRL, 10, 10, 10).await;
    cooccurrence(&db, PUMP, INSTALL, 4, 40, 4).await; // confidence 0.1: too low

    let q = quote(&app, &[PUMP], json!({})).await;
    assert_eq!(
        suggested(&q),
        [
            ("CTRL-01".to_string(), "rule".to_string()),
            ("BOLT-M8".to_string(), "often_bought_together".to_string()),
            (
                "PROFILE-40".to_string(),
                "often_bought_together".to_string()
            ),
        ],
        "{q}"
    );
    let bolt = &q["suggestions"][1];
    assert_eq!(bolt["confidence"], 0.6);
    assert!(bolt["strength"].is_null());
    assert_eq!(bolt["because_of_code"], "PUMP-05");
    // Computed data never warns.
    assert!(incompatible(&q).is_empty());

    // From BOLT's side the pump has confidence 0.1: not suggested.
    let q = quote(&app, &[BOLT], json!({})).await;
    assert!(suggested(&q).is_empty(), "{q}");
    // Stock: none.
    assert!(suggested(&quote(&app, &[PUMP], json!({ "purpose": "stock" })).await).is_empty());
    // Already in the set: not suggested.
    let q = quote(&app, &[PUMP, BOLT], json!({})).await;
    assert_eq!(
        suggested(&q)
            .iter()
            .map(|s| s.0.as_str())
            .collect::<Vec<_>>(),
        ["CTRL-01", "PROFILE-40"]
    );
    // The same list through the product view.
    let (_, r) = api(
        &app,
        SALES,
        Method::GET,
        &format!("/products/{PUMP}/related"),
        None,
    )
    .await;
    assert_eq!(r["suggestions"].as_array().unwrap().len(), 3);
}

async fn confirmed_order(app: &axum::Router, products: &[&str], purpose: &str) -> String {
    let q = quote(app, products, json!({ "purpose": purpose })).await;
    let qid = q["id"].as_str().unwrap();
    let (status, r) = api(
        app,
        SALES,
        Method::POST,
        &format!("/quotations/{qid}/send"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{r}");
    let (status, o) = api(
        app,
        SALES,
        Method::POST,
        &format!("/quotations/{qid}/convert"),
        Some(json!({})),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{o}");
    let oid = o["order"]["id"].as_str().unwrap().to_string();
    let (status, r) = api(
        app,
        SALES,
        Method::POST,
        &format!("/orders/{oid}/send"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{r}");
    let (status, r) = api(
        app,
        SALES,
        Method::POST,
        &format!("/orders/{oid}/confirm"),
        Some(json!({})),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{r}");
    oid
}

async fn stored_pairs(db: &PgPool) -> Vec<(String, String, i32, i32, i32)> {
    sqlx::query_as(
        "SELECT pa.code, pb.code, c.orders_together, c.orders_with_a, c.orders_with_b
         FROM products.product_cooccurrence c
         JOIN products.products pa ON pa.id = c.product_a_id
         JOIN products.products pb ON pb.id = c.product_b_id ORDER BY 1, 2",
    )
    .fetch_all(db)
    .await
    .unwrap()
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn cooccurrence_job_counts_confirmed_installation_orders(db: PgPool) {
    let app = setup(db.clone()).await;
    confirmed_order(&app, &[UNIT_100, PUMP, INSTALL], "installation").await;
    confirmed_order(&app, &[UNIT_100, PUMP, BOLT, BOLT], "installation").await;
    // Stock orders do not count.
    confirmed_order(&app, &[PUMP, BOLT, CTRL], "stock").await;
    // Neither do cancelled orders or orders that are not confirmed yet.
    let cancelled = confirmed_order(&app, &[UNIT_100, BOLT], "installation").await;
    sqlx::query("UPDATE sales.orders SET status = 'cancelled' WHERE id = $1")
        .bind(Uuid::parse_str(&cancelled).unwrap())
        .execute(&db)
        .await
        .unwrap();
    let q = quote(&app, &[PUMP, CTRL], json!({})).await;
    let qid = q["id"].as_str().unwrap();
    api(
        &app,
        SALES,
        Method::POST,
        &format!("/quotations/{qid}/send"),
        None,
    )
    .await;
    let (status, _) = api(
        &app,
        SALES,
        Method::POST,
        &format!("/quotations/{qid}/convert"),
        Some(json!({})),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "a draft order");

    // A stale row is replaced.
    cooccurrence(&db, HOSE, PROFILE, 5, 5, 5).await;

    let n = tradocraft_sales::cooccurrence::recompute(&db)
        .await
        .unwrap();
    // Services (INSTALL) are ignored; BOLT twice on one order counts once.
    let expected = vec![
        ("BOLT-M8".to_string(), "PUMP-05".to_string(), 1, 1, 2),
        ("BOLT-M8".to_string(), "UNIT-100".to_string(), 1, 1, 2),
        ("PUMP-05".to_string(), "UNIT-100".to_string(), 2, 2, 2),
    ];
    let mut got = stored_pairs(&db).await;
    // The a/b side follows the uuid order: compare as unordered pairs.
    for row in &mut got {
        if row.0 > row.1 {
            *row = (row.1.clone(), row.0.clone(), row.2, row.4, row.3);
        }
    }
    got.sort();
    assert_eq!(n, 3);
    assert_eq!(got, expected);

    // Idempotent.
    let n2 = tradocraft_sales::cooccurrence::recompute(&db)
        .await
        .unwrap();
    assert_eq!(n2, 3);
    let mut again = stored_pairs(&db).await;
    for row in &mut again {
        if row.0 > row.1 {
            *row = (row.1.clone(), row.0.clone(), row.2, row.4, row.3);
        }
    }
    again.sort();
    assert_eq!(again, expected);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn cooccurrence_table_is_emptied_when_there_are_no_orders(db: PgPool) {
    let _app = setup(db.clone()).await;
    cooccurrence(&db, HOSE, PROFILE, 5, 5, 5).await;
    assert_eq!(
        tradocraft_sales::cooccurrence::recompute(&db)
            .await
            .unwrap(),
        0
    );
    assert!(stored_pairs(&db).await.is_empty());
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn order_confirmation_carries_conflicts_and_suggestions(db: PgPool) {
    let app = setup(db).await;
    for (purpose, conflicts, suggestions) in [("installation", 1, 1), ("stock", 0, 0)] {
        let q = quote(&app, &[HOSE, PROFILE, PUMP], json!({ "purpose": purpose })).await;
        let qid = q["id"].as_str().unwrap();
        api(
            &app,
            SALES,
            Method::POST,
            &format!("/quotations/{qid}/send"),
            None,
        )
        .await;
        let (_, o) = api(
            &app,
            SALES,
            Method::POST,
            &format!("/quotations/{qid}/convert"),
            Some(json!({})),
        )
        .await;
        assert!(o["warnings"].as_array().unwrap().is_empty());
        assert!(o["suggestions"].as_array().unwrap().is_empty());
        let oid = o["order"]["id"].as_str().unwrap();
        api(
            &app,
            SALES,
            Method::POST,
            &format!("/orders/{oid}/send"),
            None,
        )
        .await;
        let (status, c) = api(
            &app,
            SALES,
            Method::POST,
            &format!("/orders/{oid}/confirm"),
            Some(json!({})),
        )
        .await;
        assert_eq!(status, StatusCode::OK, "{c}");
        assert_eq!(incompatible(&c).len(), conflicts, "{purpose}: {c}");
        assert_eq!(suggested(&c).len(), suggestions, "{purpose}: {c}");
    }
}
