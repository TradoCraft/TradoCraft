//! Server-side list sorting (ADR 0082): `sort=field` / `sort=-field` on customers, products and
//! quotations, the unchanged default order, and the 422 for keys that are not whitelisted.

mod common;

use axum::http::{Method, StatusCode};
use common::{call, setup};
use serde_json::{json, Value};
use sqlx::PgPool;

const SALES: &str = "sales@example.com";
const ZONE: &str = "00000000-0000-7000-8000-000000000202";
const ALPHA: &str = "00000000-0000-7000-8000-000000000401";
const UNIT_100: &str = "00000000-0000-7000-8000-000000000301";

async fn get(app: &axum::Router, uri: &str) -> (StatusCode, Value) {
    call(app, SALES, Method::GET, &format!("/api/v1{uri}"), None).await
}

/// A list request that must succeed, so a rejected `sort` shows its error instead of a missing page.
async fn get_ok(app: &axum::Router, uri: &str) -> Value {
    let (status, body) = get(app, uri).await;
    assert_eq!(status, StatusCode::OK, "{uri}: {body}");
    body
}

fn field(page: &Value, key: &str) -> Vec<Value> {
    page["items"]
        .as_array()
        .unwrap()
        .iter()
        .map(|i| i[key].clone())
        .collect()
}

fn strings(page: &Value, key: &str) -> Vec<String> {
    field(page, key)
        .iter()
        .map(|v| v.as_str().unwrap().to_string())
        .collect()
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn customers_sort_by_whitelisted_keys(db: PgPool) {
    let app = setup(db).await;
    for (code, name, city) in [
        ("S1", "Bravo", Some("Gent")),
        ("S2", "Alpha", None),
        ("S3", "Charlie", Some("Aalst")),
    ] {
        let mut body =
            json!({"code": code, "name": name, "country_code": "BE", "price_zone_id": ZONE});
        if let Some(c) = city {
            body["city"] = json!(c);
        }
        let (status, c) = call(&app, SALES, Method::POST, "/api/v1/customers", Some(body)).await;
        assert_eq!(status, StatusCode::CREATED, "{c}");
    }
    let q = "q=S&limit=500";
    let default = get_ok(&app, &format!("/customers?{q}")).await;
    let by_name = strings(&default, "name");
    // Compared with the database's own `sort=name`, not Rust's byte order: the collation differs
    // for accented names such as the seeded "Bêta".
    let asc = get_ok(&app, &format!("/customers?{q}&sort=name")).await;
    assert_eq!(by_name, strings(&asc, "name"), "default order is by name");

    let all = get_ok(&app, &format!("/customers?{q}&sort=-name")).await;
    let desc = strings(&all, "name");
    let mut rev = strings(&asc, "name");
    rev.reverse();
    assert_eq!(desc, rev);

    // NULL cities come last in both directions.
    for dir in ["city", "-city"] {
        let p = get_ok(&app, &format!("/customers?{q}&sort={dir}")).await;
        let cities = field(&p, "city");
        let first_null = cities.iter().position(|c| c.is_null());
        if let Some(i) = first_null {
            assert!(cities[i..].iter().all(|c| c.is_null()), "{dir}: {cities:?}");
        }
    }

    // Paging through a sorted list is stable and loses nothing.
    let p1 = get_ok(&app, "/customers?q=S&sort=-name&limit=2&offset=0").await;
    let p2 = get_ok(&app, "/customers?q=S&sort=-name&limit=2&offset=2").await;
    let mut paged = strings(&p1, "name");
    paged.extend(strings(&p2, "name"));
    assert_eq!(paged, desc[..paged.len()]);
    assert_eq!(p1["total"], all["total"]);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn products_sort_and_reject_unknown_keys(db: PgPool) {
    let app = setup(db).await;
    let (_, asc) = get(&app, "/products?sort=code&limit=500").await;
    let (_, desc) = get(&app, "/products?sort=-code&limit=500").await;
    let (_, default) = get(&app, "/products?limit=500").await;
    let a = strings(&asc, "code");
    let mut d = strings(&desc, "code");
    d.reverse();
    assert_eq!(a, d);
    assert_eq!(a, strings(&default, "code"));

    // Two keys: the type decides first (descending), the name breaks the tie inside a type. The
    // names are chosen so that neither key alone, nor the default code order, gives this sequence.
    let mut ids = Vec::new();
    for (code, name, product_type) in [
        ("SRT-1", "Zulu", "service"),
        ("SRT-2", "Mike", "purchased"),
        ("SRT-3", "Alpha", "purchased"),
        ("SRT-4", "Bravo", "service"),
    ] {
        let (status, p) = call(
            &app,
            "admin@example.com",
            Method::POST,
            "/api/v1/products",
            Some(json!({
                "code": code, "name": name, "product_type": product_type, "vat_rate": "21"
            })),
        )
        .await;
        assert_eq!(status, StatusCode::CREATED, "{p}");
        ids.push(p["id"].clone());
    }
    let multi = get_ok(&app, "/products?q=SRT-&sort=-product_type,name&limit=500").await;
    // service (Bravo, Zulu) before purchased (Alpha, Mike).
    assert_eq!(
        field(&multi, "id"),
        vec![
            ids[3].clone(),
            ids[0].clone(),
            ids[2].clone(),
            ids[1].clone()
        ]
    );

    for bad in [
        "nope",
        "code;DROP TABLE products.products",
        "code,code",
        "code,name,unit,active",
        "p.code",
        ",",
    ] {
        let (status, body) =
            get(&app, &format!("/products?sort={}", bad.replace(' ', "%20"))).await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{bad}: {body}");
        assert_eq!(body["error"], "validation");
    }
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn quotations_sort_by_number_status_and_total(db: PgPool) {
    let app = setup(db).await;
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
    }
    let (_, default) = get(&app, "/quotations").await;
    let numbers = strings(&default, "number");
    assert_eq!(numbers.len(), 3);
    let mut newest_first = numbers.clone();
    newest_first.sort();
    newest_first.reverse();
    assert_eq!(numbers, newest_first, "default is newest first");

    let (_, asc) = get(&app, "/quotations?sort=number").await;
    let mut expect = numbers.clone();
    expect.sort();
    assert_eq!(strings(&asc, "number"), expect);

    let (_, by_total) = get(&app, "/quotations?sort=-total").await;
    let totals: Vec<_> = field(&by_total, "total").iter().map(common::dec).collect();
    assert!(totals.windows(2).all(|w| w[0] >= w[1]), "{totals:?}");

    // The list shows the subtotal, so it is a sort key of its own.
    let (_, by_subtotal) = get(&app, "/quotations?sort=subtotal").await;
    let subtotals: Vec<_> = field(&by_subtotal, "subtotal")
        .iter()
        .map(common::dec)
        .collect();
    assert!(subtotals.windows(2).all(|w| w[0] <= w[1]), "{subtotals:?}");

    let (status, body) = get(&app, "/quotations?sort=revision").await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{body}");
    let (status, _) = get(&app, "/quotations?sort=customer_name,-status").await;
    assert_eq!(status, StatusCode::OK);
}
