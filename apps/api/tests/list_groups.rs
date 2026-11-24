//! Group counts of the list endpoints (ADR 0084): `GET /customers/groups`, `/products/groups`
//! and `/quotations/groups`. The groups follow the same search and filters as the list, their
//! counts add up to the list total, a missing or unknown `group_by` is a 422 and other companies'
//! rows are not counted.

mod common;

use axum::http::{Method, StatusCode};
use common::{call, setup};
use serde_json::{json, Value};
use sqlx::PgPool;
use uuid::Uuid;

const SALES: &str = "sales@example.com";
const ADMIN: &str = "admin@example.com";
const ZONE: &str = "00000000-0000-7000-8000-000000000202";
const ALPHA: &str = "00000000-0000-7000-8000-000000000401";
const UNIT_100: &str = "00000000-0000-7000-8000-000000000301";

async fn get(app: &axum::Router, uri: &str) -> (StatusCode, Value) {
    call(app, SALES, Method::GET, &format!("/api/v1{uri}"), None).await
}

async fn get_ok(app: &axum::Router, uri: &str) -> Value {
    let (status, body) = get(app, uri).await;
    assert_eq!(status, StatusCode::OK, "{uri}: {body}");
    body
}

async fn assert_422(app: &axum::Router, uri: &str) {
    let (status, body) = get(app, uri).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{uri}: {body}");
    assert_eq!(body["error"], "validation");
}

/// The groups as `(value, count)` pairs in response order.
fn groups(page: &Value) -> Vec<(String, i64)> {
    page["groups"]
        .as_array()
        .unwrap()
        .iter()
        .map(|g| {
            (
                g["value"].as_str().unwrap().to_string(),
                g["count"].as_i64().unwrap(),
            )
        })
        .collect()
}

fn g(v: &str, n: i64) -> (String, i64) {
    (v.to_string(), n)
}

fn sum(page: &Value) -> i64 {
    groups(page).iter().map(|(_, n)| n).sum()
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn customer_groups_count_and_follow_the_list_filters(db: PgPool) {
    let app = setup(db).await;
    for (code, name, country, active) in [
        ("ZQ1", "Zq Active BE", "BE", true),
        ("ZQ2", "Zq Inactive BE", "BE", false),
        ("ZQ3", "Zq Active NL", "NL", true),
        ("ZQ4", "Zq Inactive FR", "FR", false),
        ("ZQ5", "Zq Active BE two", "BE", true),
    ] {
        let (status, c) = call(
            &app,
            SALES,
            Method::POST,
            "/api/v1/customers",
            Some(json!({"code": code, "name": name, "country_code": country,
                        "active": active, "price_zone_id": ZONE})),
        )
        .await;
        assert_eq!(status, StatusCode::CREATED, "{c}");
    }

    let by_country = get_ok(&app, "/customers/groups?group_by=country_code&q=zq").await;
    assert_eq!(by_country["group_by"], "country_code");
    assert_eq!(groups(&by_country), [g("BE", 3), g("FR", 1), g("NL", 1)]);
    let total = get_ok(&app, "/customers?q=zq&limit=500").await["total"]
        .as_i64()
        .unwrap();
    assert_eq!(sum(&by_country), total);

    // Booleans are rendered as text, ordered by value.
    let by_active = get_ok(&app, "/customers/groups?group_by=active&q=zq").await;
    assert_eq!(groups(&by_active), [g("false", 2), g("true", 3)]);

    // The other filters and q narrow the groups exactly like the list.
    let active_only = get_ok(
        &app,
        "/customers/groups?group_by=country_code&q=zq&active=true",
    )
    .await;
    assert_eq!(groups(&active_only), [g("BE", 2), g("NL", 1)]);
    assert_eq!(
        sum(&active_only),
        get_ok(&app, "/customers?q=zq&active=true").await["total"]
    );
    let narrow = get_ok(
        &app,
        "/customers/groups?group_by=active&q=zq&country_code=be,nl",
    )
    .await;
    assert_eq!(groups(&narrow), [g("false", 1), g("true", 3)]);
    assert_eq!(
        sum(&narrow),
        get_ok(&app, "/customers?q=zq&country_code=be,nl").await["total"]
    );

    // Grouping by a filtered key only returns the selected values.
    let only_be = get_ok(
        &app,
        "/customers/groups?group_by=country_code&q=zq&country_code=BE",
    )
    .await;
    assert_eq!(groups(&only_be), [g("BE", 3)]);

    let none = get_ok(&app, "/customers/groups?group_by=active&q=nomatchatall").await;
    assert!(groups(&none).is_empty());

    for bad in [
        "/customers/groups",
        "/customers/groups?group_by=",
        "/customers/groups?group_by=city",
        "/customers/groups?group_by=active;DROP%20TABLE%20crm.customers",
        "/customers/groups?group_by=active&country_code=BEL",
    ] {
        assert_422(&app, bad).await;
    }
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn product_groups_count_and_follow_the_list_filters(db: PgPool) {
    let app = setup(db).await;
    for (code, product_type, active) in [
        ("PG-1", "service", true),
        ("PG-2", "purchased", true),
        ("PG-3", "manufactured", false),
        ("PG-4", "service", false),
        ("PG-5", "service", true),
    ] {
        let (status, p) = call(
            &app,
            ADMIN,
            Method::POST,
            "/api/v1/products",
            Some(json!({"code": code, "name": format!("Pg {code}"),
                        "product_type": product_type, "active": active, "vat_rate": "21"})),
        )
        .await;
        assert_eq!(status, StatusCode::CREATED, "{p}");
    }

    let by_type = get_ok(&app, "/products/groups?group_by=product_type&q=PG-").await;
    assert_eq!(by_type["group_by"], "product_type");
    assert_eq!(
        groups(&by_type),
        [g("manufactured", 1), g("purchased", 1), g("service", 3)]
    );
    assert_eq!(
        sum(&by_type),
        get_ok(&app, "/products?q=PG-&limit=500").await["total"]
    );

    let by_active = get_ok(&app, "/products/groups?group_by=active&q=PG-").await;
    assert_eq!(groups(&by_active), [g("false", 2), g("true", 3)]);

    let active_only = get_ok(
        &app,
        "/products/groups?group_by=product_type&q=PG-&active=true",
    )
    .await;
    assert_eq!(groups(&active_only), [g("purchased", 1), g("service", 2)]);
    assert_eq!(
        sum(&active_only),
        get_ok(&app, "/products?q=PG-&active=true").await["total"]
    );
    let typed = get_ok(
        &app,
        "/products/groups?group_by=active&q=PG-&product_type=service,purchased",
    )
    .await;
    assert_eq!(groups(&typed), [g("false", 1), g("true", 3)]);
    let only_service = get_ok(
        &app,
        "/products/groups?group_by=product_type&q=PG-&product_type=service",
    )
    .await;
    assert_eq!(groups(&only_service), [g("service", 3)]);

    for bad in [
        "/products/groups",
        "/products/groups?group_by=family_code",
        "/products/groups?group_by=product_type&product_type=nope",
    ] {
        assert_422(&app, bad).await;
    }
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn quotation_groups_count_follow_filters_and_stay_in_the_company(db: PgPool) {
    let app = setup(db.clone()).await;
    let mut ids = Vec::new();
    for qty in ["1", "5", "3", "2"] {
        let (status, q) = call(
            &app,
            SALES,
            Method::POST,
            "/api/v1/quotations",
            Some(
                json!({"customer_id": ALPHA, "lines": [{"product_id": UNIT_100, "quantity": qty}]}),
            ),
        )
        .await;
        assert_eq!(status, StatusCode::CREATED, "{q}");
        ids.push(q["id"].as_str().unwrap().to_string());
    }
    // ids[0] draft, ids[1] and ids[3] sent, ids[2] sent and rejected.
    for (id, action) in [
        (&ids[1], "send"),
        (&ids[2], "send"),
        (&ids[2], "reject"),
        (&ids[3], "send"),
    ] {
        let (status, body) = call(
            &app,
            SALES,
            Method::POST,
            &format!("/api/v1/quotations/{id}/{action}"),
            None,
        )
        .await;
        assert_eq!(status, StatusCode::OK, "{action}: {body}");
    }

    let all = get_ok(&app, "/quotations/groups?group_by=status").await;
    assert_eq!(all["group_by"], "status");
    assert_eq!(
        groups(&all),
        [g("draft", 1), g("rejected", 1), g("sent", 2)]
    );
    assert_eq!(sum(&all), get_ok(&app, "/quotations").await["total"]);

    // Filters and q narrow the groups like the list; the filtered key returns only its values.
    let two = get_ok(&app, "/quotations/groups?group_by=status&status=sent,draft").await;
    assert_eq!(groups(&two), [g("draft", 1), g("sent", 2)]);
    assert_eq!(
        sum(&two),
        get_ok(&app, "/quotations?status=sent,draft").await["total"]
    );
    let by_customer = get_ok(
        &app,
        &format!("/quotations/groups?group_by=status&customer_id={ALPHA}"),
    )
    .await;
    assert_eq!(sum(&by_customer), 4);
    let none = get_ok(&app, "/quotations/groups?group_by=status&q=zzzz").await;
    assert!(groups(&none).is_empty());

    for bad in [
        "/quotations/groups",
        "/quotations/groups?group_by=",
        "/quotations/groups?group_by=total",
        "/quotations/groups?group_by=status&status=bogus",
    ] {
        assert_422(&app, bad).await;
    }

    // Another company's quotation is not counted, and the list agrees.
    let company = Uuid::now_v7();
    sqlx::query("INSERT INTO core.companies (id, name, country_code, currency) VALUES ($1, 'Other BV', 'BE', 'EUR')")
        .bind(company)
        .execute(&db)
        .await
        .unwrap();
    sqlx::query("UPDATE sales.quotations SET company_id = $1 WHERE id = $2::uuid")
        .bind(company)
        .bind(&ids[0])
        .execute(&db)
        .await
        .unwrap();
    let after = get_ok(&app, "/quotations/groups?group_by=status").await;
    assert_eq!(groups(&after), [g("rejected", 1), g("sent", 2)]);
    assert_eq!(sum(&after), get_ok(&app, "/quotations").await["total"]);
}
