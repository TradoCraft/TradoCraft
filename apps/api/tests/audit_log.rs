//! The audit trail viewer (ADR 0059, roadmap D6): the history of a record and the company-wide
//! trail with filters, for administrators only, always within the active company.

mod common;

use axum::http::{Method, StatusCode};
use common::{call, setup};
use serde_json::{json, Value};
use sqlx::PgPool;
use uuid::Uuid;

const ADMIN: &str = "admin@example.com";
const SALES: &str = "sales@example.com";
const SUPPORT: &str = "support@example.com";
const MANAGER: &str = "manager@example.com";
const VIEWER: &str = "viewer@example.com";
const COMPANY: &str = "00000000-0000-7000-8000-000000000001";
const ZONE: &str = "00000000-0000-7000-8000-000000000202";
const SALES_ID: &str = "00000000-0000-7000-8000-000000000102";

async fn get(app: &axum::Router, user: &str, uri: &str) -> (StatusCode, Value) {
    call(app, user, Method::GET, &format!("/api/v1{uri}"), None).await
}

async fn send(
    app: &axum::Router,
    user: &str,
    method: Method,
    uri: &str,
    b: Value,
) -> (StatusCode, Value) {
    call(app, user, method, &format!("/api/v1{uri}"), Some(b)).await
}

fn items(page: &Value) -> &Vec<Value> {
    page["items"].as_array().unwrap()
}

fn actions(page: &Value) -> Vec<String> {
    items(page)
        .iter()
        .map(|e| e["action"].as_str().unwrap().to_string())
        .collect()
}

fn customer(code: &str, city: &str, discount: &str) -> Value {
    json!({"code": code, "name": format!("Customer {code}"), "country_code": "BE", "city": city,
           "price_zone_id": ZONE, "discount_percent": discount})
}

/// An event written straight into the table, as a module would through `audit::record`.
async fn insert_event(
    db: &PgPool,
    company: Option<&str>,
    user: Option<&str>,
    entity: &str,
    entity_id: Uuid,
    action: &str,
    data: Value,
) {
    sqlx::query(
        "INSERT INTO audit.events (company_id, user_id, entity, entity_id, action, data)
         VALUES ($1::uuid, $2::uuid, $3, $4, $5, $6)",
    )
    .bind(company)
    .bind(user)
    .bind(entity)
    .bind(entity_id)
    .bind(action)
    .bind(data)
    .execute(db)
    .await
    .unwrap();
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn only_administrators_may_read_the_trail(db: PgPool) {
    let app = setup(db).await;
    let id = Uuid::now_v7();
    let uris = [
        "/audit/events".to_string(),
        format!("/audit/records/customer/{id}"),
        "/audit/facets".to_string(),
    ];
    for user in [SALES, SUPPORT, VIEWER] {
        for uri in &uris {
            let (status, e) = get(&app, user, uri).await;
            assert_eq!(status, StatusCode::FORBIDDEN, "{user} {uri}: {e}");
        }
    }
    for uri in &uris {
        assert_eq!(get(&app, ADMIN, uri).await.0, StatusCode::OK, "{uri}");
    }
    // Without a user at all.
    let (status, _) = call(&app, "", Method::GET, "/api/v1/audit/events", None).await;
    assert_ne!(status, StatusCode::OK);

    // The app learns of the right from the list of permissions.
    let (_, me) = get(&app, ADMIN, "/me").await;
    assert!(me["permissions"]
        .as_array()
        .unwrap()
        .iter()
        .any(|p| p == "audit.view"));
    let (_, me) = get(&app, SALES, "/me").await;
    assert!(!me["permissions"]
        .as_array()
        .unwrap()
        .iter()
        .any(|p| p == "audit.view"));
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_record_shows_who_changed_what_and_when(db: PgPool) {
    let app = setup(db).await;
    let (status, c) = send(
        &app,
        SALES,
        Method::POST,
        "/customers",
        customer("H1", "Gent", "5"),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{c}");
    let id = c["id"].as_str().unwrap().to_string();

    // One edit changes the city and the discount; the next changes nothing.
    let mut body = customer("H1", "Brugge", "7.5");
    let (status, _) = send(
        &app,
        SALES,
        Method::PUT,
        &format!("/customers/{id}"),
        body.clone(),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (status, _) = send(
        &app,
        SALES,
        Method::PUT,
        &format!("/customers/{id}"),
        body.clone(),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    // A later one, by someone else, renames it and clears the e-mail it never had.
    body["name"] = json!("Renamed NV");
    body["vat_number"] = json!("BE0428759497");
    let (status, _) = send(&app, ADMIN, Method::PUT, &format!("/customers/{id}"), body).await;
    assert_eq!(status, StatusCode::OK);

    let (status, h) = get(&app, ADMIN, &format!("/audit/records/customer/{id}")).await;
    assert_eq!(status, StatusCode::OK, "{h}");
    assert_eq!(
        actions(&h),
        ["updated", "updated", "updated", "created"],
        "newest first: {h}"
    );
    assert!(h["next_before_id"].is_null());
    let e = items(&h);

    // The newest: by the administrator, with exactly the two fields that changed.
    assert_eq!(e[0]["user_email"], ADMIN);
    assert_eq!(e[0]["user_name"], "Admin User");
    assert_eq!(e[0]["entity"], "customer");
    assert_eq!(e[0]["entity_id"], id.as_str());
    assert_eq!(
        e[0]["data"]["changes"],
        json!({
            "name": {"from": "Customer H1", "to": "Renamed NV"},
            "vat_number": {"from": null, "to": "BE0428759497"},
        })
    );
    // A save that changed nothing records no fields.
    assert_eq!(e[1]["data"], json!({}));
    // The first edit: the city, and the discount (5 -> 7.5 whichever way it is written).
    assert_eq!(e[2]["user_email"], SALES);
    assert_eq!(
        e[2]["data"]["changes"]["city"],
        json!({"from": "Gent", "to": "Brugge"})
    );
    let discount = &e[2]["data"]["changes"]["discount_percent"];
    assert_eq!(discount["from"], "5");
    assert_eq!(discount["to"], "7.5");
    assert_eq!(
        e[2]["data"]["changes"].as_object().unwrap().len(),
        2,
        "{}",
        e[2]
    );
    // The creation.
    assert_eq!(e[3]["action"], "created");
    assert_eq!(e[3]["data"]["code"], "H1");
    // Times are real and ordered.
    let times: Vec<&str> = e
        .iter()
        .map(|x| x["occurred_at"].as_str().unwrap())
        .collect();
    assert!(times.windows(2).all(|w| w[0] >= w[1]), "{times:?}");
    // ids only grow with time, which is what the cursor relies on.
    let ids: Vec<i64> = e.iter().map(|x| x["id"].as_i64().unwrap()).collect();
    assert!(ids.windows(2).all(|w| w[0] > w[1]), "{ids:?}");

    // Another kind of record with the same id has its own, empty history.
    let (_, other) = get(&app, ADMIN, &format!("/audit/records/quotation/{id}")).await;
    assert!(items(&other).is_empty());
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_supplier_update_records_its_changes_next_to_the_old_keys(db: PgPool) {
    let app = setup(db).await;
    let (_, s) = send(
        &app,
        ADMIN,
        Method::POST,
        "/suppliers",
        json!({"name": "Acme", "country": "BE", "code": "ac"}),
    )
    .await;
    let id = s["id"].as_str().unwrap();
    let (status, _) = send(
        &app,
        ADMIN,
        Method::PUT,
        &format!("/suppliers/{id}"),
        json!({"name": "Acme NV", "payment_terms_days": 45}),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (_, h) = get(&app, ADMIN, &format!("/audit/records/supplier/{id}")).await;
    let d = &items(&h)[0]["data"];
    assert_eq!(items(&h)[0]["action"], "updated");
    assert_eq!(d["name"], "Acme NV");
    assert_eq!(d["code"], "AC");
    assert_eq!(d["active"], true);
    assert_eq!(
        d["changes"],
        json!({"name": {"from": "Acme", "to": "Acme NV"}, "payment_terms_days": {"from": 30, "to": 45}})
    );
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_company_wide_trail_filters_and_pages(db: PgPool) {
    let app = setup(db.clone()).await;
    // Some history: sales makes two customers, a sales manager edits one, admin makes a supplier.
    let mut ids = vec![];
    for code in ["P1", "P2"] {
        let (_, c) = send(
            &app,
            SALES,
            Method::POST,
            "/customers",
            customer(code, "Gent", "0"),
        )
        .await;
        ids.push(c["id"].as_str().unwrap().to_string());
    }
    let (status, _) = send(
        &app,
        MANAGER,
        Method::PUT,
        &format!("/customers/{}", ids[0]),
        customer("P1", "Namur", "0"),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (_, s) = send(
        &app,
        ADMIN,
        Method::POST,
        "/suppliers",
        json!({"name": "Sup", "country": "BE"}),
    )
    .await;
    let supplier = s["id"].as_str().unwrap().to_string();

    let (_, all) = get(&app, ADMIN, "/audit/events?limit=200").await;
    let total = items(&all).len();
    assert!(total >= 4, "{all}");
    // Newest first: the supplier was last.
    assert_eq!(items(&all)[0]["entity"], "supplier");
    assert_eq!(items(&all)[0]["entity_id"], supplier.as_str());

    // Filters, alone and together.
    let (_, r) = get(&app, ADMIN, "/audit/events?entity=customer&limit=200").await;
    assert!(items(&r).iter().all(|e| e["entity"] == "customer"));
    assert_eq!(items(&r).len(), 3, "two created, one updated: {r}");
    let (_, r) = get(&app, ADMIN, "/audit/events?entity=customer&action=updated").await;
    assert_eq!(items(&r).len(), 1);
    assert_eq!(items(&r)[0]["user_email"], MANAGER);
    let (_, r) = get(
        &app,
        ADMIN,
        &format!("/audit/events?user_id={SALES_ID}&limit=200"),
    )
    .await;
    assert_eq!(items(&r).len(), 2);
    assert!(items(&r).iter().all(|e| e["user_email"] == SALES));
    let (_, r) = get(&app, ADMIN, &format!("/audit/events?entity_id={}", ids[0])).await;
    assert_eq!(actions(&r), ["updated", "created"]);
    let (_, r) = get(
        &app,
        ADMIN,
        &format!("/audit/events?entity_id={}&user_id={SALES_ID}", ids[0]),
    )
    .await;
    assert_eq!(actions(&r), ["created"]);
    // Whitespace-only filters are no filters.
    let (_, r) = get(&app, ADMIN, "/audit/events?entity=%20&action=&limit=200").await;
    assert_eq!(items(&r).len(), total);

    // Time: events written now are after an hour ago and before an hour from now.
    let hour = |d: i64| {
        (chrono::Utc::now() + chrono::Duration::hours(d))
            .to_rfc3339_opts(chrono::SecondsFormat::Secs, true)
    };
    let q = |from: String, to: String| {
        format!(
            "/audit/events?limit=200&from={}&to={}",
            from.replace('+', "%2B"),
            to.replace('+', "%2B")
        )
    };
    let (status, r) = get(&app, ADMIN, &q(hour(-1), hour(1))).await;
    assert_eq!(status, StatusCode::OK, "{r}");
    assert_eq!(items(&r).len(), total);
    let (_, r) = get(&app, ADMIN, &q(hour(1), hour(2))).await;
    assert_eq!(items(&r).len(), 0, "all of it is in the past");
    let (_, r) = get(&app, ADMIN, &q(hour(-3), hour(-2))).await;
    assert_eq!(items(&r).len(), 0, "and none of it older than that");
    // `to` is exclusive and `from` inclusive: the exact moment of the newest event.
    let newest = items(&all)[0]["occurred_at"]
        .as_str()
        .unwrap()
        .replace('+', "%2B");
    let (_, r) = get(
        &app,
        ADMIN,
        &format!("/audit/events?from={newest}&limit=200"),
    )
    .await;
    assert_eq!(items(&r).len(), 1);
    let (_, r) = get(&app, ADMIN, &format!("/audit/events?to={newest}&limit=200")).await;
    assert_eq!(items(&r).len(), total - 1);

    // Paging by cursor: two at a time visits every event once, newest to oldest.
    let mut seen: Vec<i64> = vec![];
    let mut cursor: Option<i64> = None;
    let mut pages = 0;
    loop {
        let uri = match cursor {
            Some(c) => format!("/audit/events?limit=2&before_id={c}"),
            None => "/audit/events?limit=2".to_string(),
        };
        let (status, p) = get(&app, ADMIN, &uri).await;
        assert_eq!(status, StatusCode::OK, "{p}");
        assert!(items(&p).len() <= 2);
        seen.extend(items(&p).iter().map(|e| e["id"].as_i64().unwrap()));
        pages += 1;
        match p["next_before_id"].as_i64() {
            Some(next) => {
                assert_eq!(
                    next,
                    *seen.last().unwrap(),
                    "the cursor is the last id of the page"
                );
                cursor = Some(next);
            }
            None => break,
        }
        assert!(pages < 100, "paging does not end");
    }
    assert_eq!(seen.len(), total);
    assert_eq!(pages, total.div_ceil(2));
    assert!(seen.windows(2).all(|w| w[0] > w[1]), "{seen:?}");
    // A page that ends exactly at the end has no cursor.
    let (_, p) = get(&app, ADMIN, &format!("/audit/events?limit={total}")).await;
    assert_eq!(items(&p).len(), total);
    assert!(p["next_before_id"].is_null());

    // The page size is kept within bounds, the default is 50.
    let (_, p) = get(&app, ADMIN, "/audit/events?limit=0").await;
    assert_eq!(items(&p).len(), 1);
    let (_, p) = get(&app, ADMIN, "/audit/events?limit=-5").await;
    assert_eq!(items(&p).len(), 1);
    for i in 0..60 {
        insert_event(
            &db,
            Some(COMPANY),
            None,
            "bulk",
            Uuid::now_v7(),
            "tick",
            json!({"i": i}),
        )
        .await;
    }
    let (_, p) = get(&app, ADMIN, "/audit/events").await;
    assert_eq!(items(&p).len(), 50);
    assert!(p["next_before_id"].is_i64());
    let (_, p) = get(&app, ADMIN, "/audit/events?limit=100000&entity=bulk").await;
    assert_eq!(items(&p).len(), 60, "the cap is 200, there are 60");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_trail_never_crosses_companies_and_shows_system_events(db: PgPool) {
    let app = setup(db.clone()).await;
    let shared = Uuid::now_v7();
    // Another company's event on the very same record id, and one that belongs to no company.
    let other = Uuid::now_v7();
    sqlx::query("INSERT INTO core.companies (id, name) VALUES ($1, 'Other BV')")
        .bind(other)
        .execute(&db)
        .await
        .unwrap();
    insert_event(
        &db,
        Some(&other.to_string()),
        None,
        "customer",
        shared,
        "created",
        json!({"secret": "other"}),
    )
    .await;
    insert_event(
        &db,
        None,
        None,
        "customer",
        shared,
        "created",
        json!({"secret": "nobody"}),
    )
    .await;
    // Ours, from a system actor (a customer in the portal): no user, the actor is in `data`.
    insert_event(
        &db,
        Some(COMPANY),
        None,
        "ticket",
        shared,
        "portal_reply",
        json!({"contact_id": "c1"}),
    )
    .await;

    let (_, h) = get(&app, ADMIN, &format!("/audit/records/customer/{shared}")).await;
    assert!(items(&h).is_empty(), "{h}");
    let (_, all) = get(&app, ADMIN, "/audit/events?limit=200").await;
    let text = all.to_string();
    assert!(
        !text.contains("other") && !text.contains("nobody"),
        "{text}"
    );

    let (_, h) = get(&app, ADMIN, &format!("/audit/records/ticket/{shared}")).await;
    let e = &items(&h)[0];
    assert_eq!(e["action"], "portal_reply");
    assert!(e["user_id"].is_null() && e["user_name"].is_null() && e["user_email"].is_null());
    assert_eq!(e["data"]["contact_id"], "c1");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_kinds_of_record_are_listed_for_the_filter(db: PgPool) {
    let app = setup(db.clone()).await;
    let (_, f) = get(&app, ADMIN, "/audit/facets").await;
    assert_eq!(
        f["entities"],
        json!([]),
        "a fresh database has nothing to filter by"
    );

    let (_, c) = send(
        &app,
        SALES,
        Method::POST,
        "/customers",
        customer("F1", "Gent", "0"),
    )
    .await;
    send(
        &app,
        ADMIN,
        Method::POST,
        "/suppliers",
        json!({"name": "S", "country": "BE"}),
    )
    .await;
    send(
        &app,
        SALES,
        Method::PUT,
        &format!("/customers/{}", c["id"].as_str().unwrap()),
        customer("F1", "Brugge", "0"),
    )
    .await;
    // Another company's kind of record must not leak in, nor an event of no company.
    let other = Uuid::now_v7();
    sqlx::query("INSERT INTO core.companies (id, name) VALUES ($1, 'Other BV')")
        .bind(other)
        .execute(&db)
        .await
        .unwrap();
    insert_event(
        &db,
        Some(&other.to_string()),
        None,
        "zzz_other",
        Uuid::now_v7(),
        "x",
        json!({}),
    )
    .await;
    insert_event(&db, None, None, "zzz_none", Uuid::now_v7(), "x", json!({})).await;
    insert_event(
        &db,
        Some(COMPANY),
        None,
        "aaa_first",
        Uuid::now_v7(),
        "x",
        json!({}),
    )
    .await;

    let (status, f) = get(&app, ADMIN, "/audit/facets").await;
    assert_eq!(status, StatusCode::OK, "{f}");
    assert_eq!(f["entities"], json!(["aaa_first", "customer", "supplier"]));
}

/// An update records what it changed from the latest committed row. A concurrent update holds the
/// row; the one behind it waits and then reads what the first one wrote, not what was there before.
#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn an_update_waits_for_a_concurrent_one_and_records_the_latest_before(db: PgPool) {
    let app = setup(db.clone()).await;
    let (_, c) = send(
        &app,
        SALES,
        Method::POST,
        "/customers",
        customer("L1", "Gent", "0"),
    )
    .await;
    let id = c["id"].as_str().unwrap().to_string();

    // Another transaction takes the customer row, as a concurrent update would.
    let mut holder = db.begin().await.unwrap();
    sqlx::query("SELECT id FROM crm.customers WHERE id = $1::uuid FOR UPDATE")
        .bind(&id)
        .fetch_one(&mut *holder)
        .await
        .unwrap();

    let second = {
        let (app, id) = (app.clone(), id.clone());
        tokio::spawn(async move {
            send(
                &app,
                SALES,
                Method::PUT,
                &format!("/customers/{id}"),
                customer("L1", "Brugge", "0"),
            )
            .await
        })
    };
    tokio::time::sleep(std::time::Duration::from_millis(400)).await;
    assert!(
        !second.is_finished(),
        "the update must wait for the row it is going to change"
    );

    // The first update commits its change; only then may the second one read the row.
    sqlx::query("UPDATE crm.customers SET city = 'Namur' WHERE id = $1::uuid")
        .bind(&id)
        .execute(&mut *holder)
        .await
        .unwrap();
    holder.commit().await.unwrap();
    let (status, body) = second.await.unwrap();
    assert_eq!(status, StatusCode::OK, "{body}");

    let (_, h) = get(&app, ADMIN, &format!("/audit/records/customer/{id}")).await;
    assert_eq!(
        items(&h)[0]["data"]["changes"]["city"],
        json!({"from": "Namur", "to": "Brugge"}),
        "the baseline is the committed row, not the one the update started from: {h}"
    );
}
