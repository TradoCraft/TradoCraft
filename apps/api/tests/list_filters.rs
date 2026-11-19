//! Server-side list filters (ADR 0083): `active` and `country_code` on customers, `product_type`
//! on products and a multi-value `status` on quotations. Each filter narrows the list and its
//! total, values of one filter combine with OR, filters combine with AND (also with `q` and
//! `sort`), unknown values are a 422 and an absent filter changes nothing.

mod common;

use axum::http::{Method, StatusCode};
use common::{call, setup};
use serde_json::{json, Value};
use sqlx::PgPool;

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

fn strings(page: &Value, key: &str) -> Vec<String> {
    page["items"]
        .as_array()
        .unwrap()
        .iter()
        .map(|i| i[key].as_str().unwrap().to_string())
        .collect()
}

fn sorted(mut v: Vec<String>) -> Vec<String> {
    v.sort();
    v
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn customers_filter_by_active_and_country(db: PgPool) {
    let app = setup(db).await;
    for (code, name, country, active) in [
        ("F1", "Fa Active BE", "BE", true),
        ("F2", "Fb Inactive BE", "BE", false),
        ("F3", "Fc Active NL", "NL", true),
        ("F4", "Fd Inactive FR", "FR", false),
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
    let q = "q=Fa&limit=500";
    assert_eq!(get_ok(&app, "/customers?q=F&limit=500").await["total"], 4);

    // Boolean filter.
    let active = get_ok(&app, "/customers?q=F&active=true").await;
    assert_eq!(strings(&active, "code"), ["F1", "F3"]);
    assert_eq!(active["total"], 2);
    let inactive = get_ok(&app, "/customers?q=F&active=false").await;
    assert_eq!(strings(&inactive, "code"), ["F2", "F4"]);
    assert_eq!(inactive["total"], 2);

    // Country: one value, several values (OR), lower case accepted, duplicates harmless.
    let be = get_ok(&app, "/customers?q=F&country_code=BE").await;
    assert_eq!(strings(&be, "code"), ["F1", "F2"]);
    let multi = get_ok(&app, "/customers?q=F&country_code=nl,%20fr,NL").await;
    assert_eq!(strings(&multi, "code"), ["F3", "F4"]);
    assert_eq!(multi["total"], 2);

    // AND between filters, q and sort; the total follows the filters, not the page.
    let both = get_ok(
        &app,
        "/customers?q=F&country_code=BE,NL&active=true&sort=-code",
    )
    .await;
    assert_eq!(strings(&both, "code"), ["F3", "F1"]);
    assert_eq!(both["total"], 2);
    let paged = get_ok(&app, "/customers?q=F&country_code=BE,NL&sort=code&limit=1").await;
    assert_eq!(strings(&paged, "code"), ["F1"]);
    assert_eq!(paged["total"], 3);
    let with_q = get_ok(&app, &format!("/customers?{q}&country_code=NL")).await;
    assert_eq!(with_q["total"], 0, "q and filter combine with AND");

    // Absent or blank filters change nothing.
    let blank = get_ok(&app, "/customers?q=F&country_code=").await;
    assert_eq!(blank["total"], 4);

    for bad in ["BEL", "B", "BE,", "BE;DROP%20TABLE%20crm.customers", "B1"] {
        assert_422(&app, &format!("/customers?country_code={bad}")).await;
    }
    let many = (0..21)
        .map(|i| format!("A{}", (b'A' + i) as char))
        .collect::<Vec<_>>();
    assert_422(&app, &format!("/customers?country_code={}", many.join(","))).await;
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn products_filter_by_product_type(db: PgPool) {
    let app = setup(db).await;
    for (code, name, product_type, active) in [
        ("PF-1", "Pa", "service", true),
        ("PF-2", "Pb", "purchased", true),
        ("PF-3", "Pc", "manufactured", false),
        ("PF-4", "Pd", "service", false),
    ] {
        let (status, p) = call(
            &app,
            ADMIN,
            Method::POST,
            "/api/v1/products",
            Some(
                json!({"code": code, "name": name, "product_type": product_type,
                        "active": active, "vat_rate": "21"}),
            ),
        )
        .await;
        assert_eq!(status, StatusCode::CREATED, "{p}");
    }
    let base = "/products?q=PF-&limit=500";
    assert_eq!(get_ok(&app, base).await["total"], 4);

    let service = get_ok(&app, &format!("{base}&product_type=service")).await;
    assert_eq!(sorted(strings(&service, "code")), ["PF-1", "PF-4"]);
    assert_eq!(service["total"], 2);

    let multi = get_ok(&app, &format!("{base}&product_type=service,purchased")).await;
    assert_eq!(sorted(strings(&multi, "code")), ["PF-1", "PF-2", "PF-4"]);
    assert_eq!(multi["total"], 3);

    // AND with active, q and sort; paging keeps the filtered total.
    let and = get_ok(
        &app,
        &format!("{base}&product_type=service,manufactured&active=false&sort=-code"),
    )
    .await;
    assert_eq!(strings(&and, "code"), ["PF-4", "PF-3"]);
    let paged = get_ok(
        &app,
        "/products?q=PF-&product_type=service,purchased&sort=code&limit=1&offset=1",
    )
    .await;
    assert_eq!(strings(&paged, "code"), ["PF-2"]);
    assert_eq!(paged["total"], 3);
    let narrow = get_ok(&app, "/products?q=PF-1&product_type=purchased").await;
    assert_eq!(narrow["total"], 0);

    let blank = get_ok(&app, &format!("{base}&product_type=")).await;
    assert_eq!(blank["total"], 4);

    for bad in [
        "service,nope",
        "Service",
        "service,",
        "service;DROP%20TABLE%20products.products",
    ] {
        assert_422(&app, &format!("/products?product_type={bad}")).await;
    }
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn quotations_filter_by_status_list(db: PgPool) {
    let app = setup(db).await;
    let mut ids = Vec::new();
    for qty in ["1", "5", "3"] {
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
    // ids[0] stays draft, ids[1] is sent, ids[2] is sent and rejected.
    for (id, action) in [(&ids[1], "send"), (&ids[2], "send"), (&ids[2], "reject")] {
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
    let id_set = |page: &Value| sorted(strings(page, "id"));

    // Single value keeps working.
    let draft = get_ok(&app, "/quotations?status=draft").await;
    assert_eq!(id_set(&draft), [ids[0].clone()]);
    assert_eq!(draft["total"], 1);

    // OR across values.
    let multi = get_ok(&app, "/quotations?status=draft,rejected").await;
    assert_eq!(id_set(&multi), sorted(vec![ids[0].clone(), ids[2].clone()]));
    assert_eq!(multi["total"], 2);

    // AND with q, sort and paging; total ignores the page size.
    let paged = get_ok(
        &app,
        "/quotations?status=draft,sent,rejected&sort=-total&limit=1",
    )
    .await;
    assert_eq!(paged["items"].as_array().unwrap().len(), 1);
    assert_eq!(paged["total"], 3);
    let (_, none) = get(&app, "/quotations?status=draft,sent&q=zzzz").await;
    assert_eq!(none["total"], 0);
    let sent_and_draft = get_ok(&app, "/quotations?status=sent,draft&sort=number").await;
    assert_eq!(sent_and_draft["total"], 2);

    // Absent or blank: unchanged.
    assert_eq!(get_ok(&app, "/quotations").await["total"], 3);
    assert_eq!(get_ok(&app, "/quotations?status=").await["total"], 3);

    for bad in ["bogus", "draft,bogus", "draft,", "Draft"] {
        assert_422(&app, &format!("/quotations?status={bad}")).await;
    }
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn customer_country_code_must_be_two_letters_like_the_filter(db: PgPool) {
    let app = setup(db).await;
    let create = |code: &'static str, country: &'static str| {
        let app = app.clone();
        async move {
            call(
                &app,
                SALES,
                Method::POST,
                "/api/v1/customers",
                Some(json!({"code": code, "name": "Cc", "country_code": country,
                            "price_zone_id": ZONE})),
            )
            .await
        }
    };
    for (i, bad) in ["1A", " ", "", "B-", "BEL", "é1"].into_iter().enumerate() {
        let (status, body) = create(["X1", "X2", "X3", "X4", "X5", "X6"][i], bad).await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{bad:?}: {body}");
        assert_eq!(body["error"], "validation");
    }
    let (status, body) = create("X9", "be").await;
    assert_eq!(status, StatusCode::CREATED, "{body}");
    assert_eq!(body["country_code"], "BE");
    let filtered = get_ok(&app, "/customers?q=X9&country_code=BE").await;
    assert_eq!(strings(&filtered, "code"), ["X9"]);
}
