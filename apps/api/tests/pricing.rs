//! Rebates, pricing types, price dates, revisions and bulk price changes.

mod common;

use axum::http::{Method, StatusCode};
use common::{call, dec, setup};
use serde_json::{json, Value};
use sqlx::PgPool;

const ALPHA: &str = "00000000-0000-7000-8000-000000000401"; // zone Z2, general rebate 5 %
const UNIT_100: &str = "00000000-0000-7000-8000-000000000301"; // Z2 3880.00
const UNIT_200: &str = "00000000-0000-7000-8000-000000000302"; // price on request (its Z2 price 5760.00 is never used)
const PUMP: &str = "00000000-0000-7000-8000-000000000303"; // family PUMPS, Z2 512.00
const HOSE: &str = "00000000-0000-7000-8000-000000000304"; // Z2 9.92
const INSTALL: &str = "00000000-0000-7000-8000-000000000305"; // non-discountable, Z2 62.40
const CTRL: &str = "00000000-0000-7000-8000-000000000310"; // Z2 712.00
const PUMPS: &str = "00000000-0000-7000-8000-000000000802";
const ZONE_Z2: &str = "00000000-0000-7000-8000-000000000202";
const SALES: &str = "sales@example.com";
const MANAGER: &str = "manager@example.com";
const ADMIN: &str = "admin@example.com";

fn line(product: &str, qty: &str) -> Value {
    json!({ "product_id": product, "quantity": qty })
}

fn d(v: &Value) -> String {
    dec(v).normalize().to_string()
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn most_specific_rebate_applies_and_net_prices_are_never_discounted(db: PgPool) {
    let app = setup(db).await;
    let body = json!({ "customer_id": ALPHA, "lines": [
        line(PUMP, "1"), line(CTRL, "1"), line(HOSE, "10"), line(INSTALL, "4")
    ]});
    let (status, p) = call(
        &app,
        SALES,
        Method::POST,
        "/api/v1/pricing/preview",
        Some(body),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{p}");
    let got: Vec<(String, String, String)> = p["lines"]
        .as_array()
        .unwrap()
        .iter()
        .map(|l| {
            (
                d(&l["rebate_percent"]),
                l["rebate_source"].as_str().unwrap().into(),
                d(&l["line_total"]),
            )
        })
        .collect();
    let expected = [
        ("12", "family", "450.56"), // 512 × 0.88
        ("15", "product", "605.2"), // 712 × 0.85
        ("5", "general", "94.24"),  // 9.92 × 0.95 × 10
        ("0", "net", "249.6"),      // 62.40 × 4, no rebate
    ];
    assert_eq!(
        got,
        expected.map(|(a, b, c)| (a.to_string(), b.to_string(), c.to_string()))
    );

    // Non-discountable products accept no manual discount either.
    let body = json!({ "customer_id": ALPHA, "lines": [
        { "product_id": INSTALL, "quantity": "1", "line_discount_percent": "10" }
    ]});
    let (status, e) = call(
        &app,
        SALES,
        Method::POST,
        "/api/v1/pricing/preview",
        Some(body),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    assert!(
        e["message"].as_str().unwrap().contains("not discountable"),
        "{e}"
    );

    // Only price-on-request prices can be entered by hand.
    let body = json!({ "customer_id": ALPHA, "lines": [
        { "product_id": UNIT_100, "quantity": "1", "unit_price": "1" }
    ]});
    let (status, _) = call(
        &app,
        SALES,
        Method::POST,
        "/api/v1/pricing/preview",
        Some(body),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn price_on_request_lines_need_a_price_before_sending(db: PgPool) {
    let app = setup(db).await;
    let (status, q) = call(
        &app,
        SALES,
        Method::POST,
        "/api/v1/quotations",
        Some(json!({ "customer_id": ALPHA, "lines": [line(UNIT_200, "1")] })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{q}");
    assert_eq!(q["lines"][0]["price_confirmed"], false);
    assert_eq!(q["lines"][0]["price_on_request"], true);
    assert_eq!(
        d(&q["lines"][0]["list_unit_price"]),
        "0",
        "the zone price of a price-on-request product is never used"
    );
    let id = q["id"].as_str().unwrap();

    let (status, e) = call(
        &app,
        SALES,
        Method::POST,
        &format!("/api/v1/quotations/{id}/send"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    assert!(e["message"].as_str().unwrap().contains("UNIT-200"), "{e}");

    let body = json!({ "customer_id": ALPHA, "lines": [
        { "product_id": UNIT_200, "quantity": "1", "unit_price": "6000" }
    ]});
    let (status, q) = call(
        &app,
        SALES,
        Method::PUT,
        &format!("/api/v1/quotations/{id}"),
        Some(body),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{q}");
    assert_eq!(q["lines"][0]["price_confirmed"], true);
    assert_eq!(
        d(&q["lines"][0]["line_total"]),
        "5700",
        "rebates still apply to an entered price"
    );

    let (status, _) = call(
        &app,
        SALES,
        Method::POST,
        &format!("/api/v1/quotations/{id}/send"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_three_price_flags_combine(db: PgPool) {
    let app = setup(db.clone()).await;
    // The hose: price on request and never discounted, and without any zone price at all. The
    // pump: an indicative list price, which is only a marker.
    sqlx::query(
        "UPDATE products.products SET price_on_request = true, non_discountable = true WHERE id = $1",
    )
    .bind(uuid::Uuid::parse_str(HOSE).unwrap())
    .execute(&db)
    .await
    .unwrap();
    sqlx::query("DELETE FROM pricing.zone_prices WHERE product_id = $1")
        .bind(uuid::Uuid::parse_str(HOSE).unwrap())
        .execute(&db)
        .await
        .unwrap();
    sqlx::query("UPDATE products.products SET price_is_indicative = true WHERE id = $1")
        .bind(uuid::Uuid::parse_str(PUMP).unwrap())
        .execute(&db)
        .await
        .unwrap();
    let preview = |lines: Value| {
        let app = app.clone();
        async move {
            call(
                &app,
                SALES,
                Method::POST,
                "/api/v1/pricing/preview",
                Some(json!({ "customer_id": ALPHA, "lines": lines })),
            )
            .await
        }
    };

    let (status, p) = preview(json!([line(HOSE, "10"), line(PUMP, "1")])).await;
    assert_eq!(status, StatusCode::OK, "{p}");
    let hose = &p["lines"][0];
    assert_eq!(hose["price_on_request"], true);
    assert_eq!(hose["non_discountable"], true);
    assert_eq!(hose["price_confirmed"], false);
    assert_eq!(d(&hose["list_unit_price"]), "0");
    assert_eq!(hose["rebate_source"], "net");
    let pump = &p["lines"][1];
    assert_eq!(pump["price_is_indicative"], true);
    assert_eq!(
        pump["price_confirmed"], true,
        "an indicative price needs no input"
    );
    assert_eq!(d(&pump["list_unit_price"]), "512");
    assert_eq!(
        d(&pump["rebate_percent"]),
        "12",
        "rebates apply to indicative prices"
    );
    assert_eq!(p["unconfirmed_lines"], 1);

    // The entered price is not discounted: no rebate, and no line discount either.
    let (status, p) = preview(json!([
        { "product_id": HOSE, "quantity": "10", "unit_price": "11.5" }
    ]))
    .await;
    assert_eq!(status, StatusCode::OK, "{p}");
    assert_eq!(p["lines"][0]["price_confirmed"], true);
    assert_eq!(d(&p["lines"][0]["line_total"]), "115");
    assert_eq!(p["unconfirmed_lines"], 0);
    let (status, e) = preview(json!([
        { "product_id": HOSE, "quantity": "1", "unit_price": "11.5", "line_discount_percent": "5" }
    ]))
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    assert!(
        e["message"].as_str().unwrap().contains("not discountable"),
        "{e}"
    );
    let (status, _) = preview(json!([
        { "product_id": HOSE, "quantity": "1", "unit_price": "-1" }
    ]))
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    // An indicative price is the list price: it cannot be overridden on the line.
    let (status, _) = preview(json!([
        { "product_id": PUMP, "quantity": "1", "unit_price": "400" }
    ]))
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn quoting_on_the_previous_price_list_needs_permission(db: PgPool) {
    let app = setup(db.clone()).await;
    let body =
        json!({ "customer_id": ALPHA, "price_date": "2025-06-01", "lines": [line(UNIT_100, "1")] });
    let (status, _) = call(
        &app,
        SALES,
        Method::POST,
        "/api/v1/quotations",
        Some(body.clone()),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);

    let (status, q) = call(
        &app,
        MANAGER,
        Method::POST,
        "/api/v1/quotations",
        Some(body),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{q}");
    assert_eq!(q["price_date"], "2025-06-01");
    assert_eq!(
        d(&q["lines"][0]["list_unit_price"]),
        "3724.8",
        "2025 price list (3880 × 0.96)"
    );
    let audited: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM audit.events WHERE action = 'price_date_backdated'",
    )
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(audited, 1);

    // A salesperson may keep editing the draft: its price date does not change.
    let id = q["id"].as_str().unwrap();
    let body = json!({ "customer_id": ALPHA, "lines": [line(UNIT_100, "2")] });
    let (status, q) = call(
        &app,
        SALES,
        Method::PUT,
        &format!("/api/v1/quotations/{id}"),
        Some(body),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{q}");
    assert_eq!(q["price_date"], "2025-06-01");
    assert_eq!(d(&q["lines"][0]["list_unit_price"]), "3724.8");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn revisions_keep_or_update_prices_after_comparing(db: PgPool) {
    let app = setup(db).await;
    let (_, q) = call(
        &app,
        SALES,
        Method::POST,
        "/api/v1/quotations",
        Some(json!({ "customer_id": ALPHA, "lines": [line(UNIT_100, "2"), line(HOSE, "10")] })),
    )
    .await;
    let id = q["id"].as_str().unwrap().to_string();
    call(
        &app,
        SALES,
        Method::POST,
        &format!("/api/v1/quotations/{id}/send"),
        None,
    )
    .await;

    // Prices go up today.
    let today = tradocraft_core::today().to_string();
    let (status, _) = call(
        &app,
        ADMIN,
        Method::POST,
        &format!("/api/v1/products/{UNIT_100}/prices"),
        Some(json!({ "zone_id": ZONE_Z2, "unit_price": "4000", "valid_from": today })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);

    let (status, c) = call(
        &app,
        SALES,
        Method::GET,
        &format!("/api/v1/quotations/{id}/repricing"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{c}");
    assert_eq!(d(&c["lines"][0]["old_list_unit_price"]), "3880");
    assert_eq!(d(&c["lines"][0]["new_list_unit_price"]), "4000");
    assert_eq!(d(&c["lines"][0]["difference"]), "228"); // (4000 - 3880) × 0.95 × 2
    assert_eq!(d(&c["lines"][1]["difference"]), "0");
    assert_eq!(d(&c["difference"]), "228");

    // Keep the agreed prices.
    let (status, r2) = call(
        &app,
        SALES,
        Method::POST,
        &format!("/api/v1/quotations/{id}/revise"),
        Some(json!({ "pricing": "keep" })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{r2}");
    assert_eq!(r2["revision"], 2);
    assert_eq!(d(&r2["lines"][0]["list_unit_price"]), "3880");
    assert_eq!(r2["subtotal"], q["subtotal"]);
    assert_eq!(r2["price_date"], q["price_date"]);

    // Next round: update to current prices.
    let r2_id = r2["id"].as_str().unwrap();
    call(
        &app,
        SALES,
        Method::POST,
        &format!("/api/v1/quotations/{r2_id}/send"),
        None,
    )
    .await;
    let (status, r3) = call(
        &app,
        SALES,
        Method::POST,
        &format!("/api/v1/quotations/{r2_id}/revise"),
        Some(json!({ "pricing": "current" })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{r3}");
    assert_eq!(r3["revision"], 3);
    assert_eq!(d(&r3["lines"][0]["list_unit_price"]), "4000");
    assert_eq!(r3["price_date"], today);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn rebates_are_managed_by_sales_managers_without_overlaps(db: PgPool) {
    let app = setup(db).await;
    let url = format!("/api/v1/customers/{ALPHA}/rebates");
    let (_, list) = call(&app, SALES, Method::GET, &url, None).await;
    assert_eq!(list.as_array().unwrap().len(), 2);

    let rule = json!({ "scope": "product", "product_id": HOSE, "percent": "20", "valid_from": "2027-01-01" });
    let (status, _) = call(&app, SALES, Method::POST, &url, Some(rule.clone())).await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, r) = call(&app, MANAGER, Method::POST, &url, Some(rule)).await;
    assert_eq!(status, StatusCode::CREATED, "{r}");
    assert_eq!(r["product_code"], "HOSE-25");

    // Overlapping rule for the same product is refused; a period before it is fine.
    let overlap = json!({ "scope": "product", "product_id": HOSE, "percent": "18", "valid_from": "2027-06-01" });
    let (status, _) = call(&app, MANAGER, Method::POST, &url, Some(overlap)).await;
    assert_eq!(status, StatusCode::CONFLICT);
    let before = json!({ "scope": "product", "product_id": HOSE, "percent": "10", "valid_to": "2026-12-31" });
    let (status, _) = call(&app, MANAGER, Method::POST, &url, Some(before)).await;
    assert_eq!(status, StatusCode::CREATED);

    // The dated rules apply by price date.
    let preview = |date: &str| json!({ "customer_id": ALPHA, "quote_date": date, "lines": [line(HOSE, "1")] });
    let (_, p) = call(
        &app,
        MANAGER,
        Method::POST,
        "/api/v1/pricing/preview",
        Some(preview("2026-11-05")),
    )
    .await;
    assert_eq!(d(&p["lines"][0]["rebate_percent"]), "10");
    let (_, p) = call(
        &app,
        MANAGER,
        Method::POST,
        "/api/v1/pricing/preview",
        Some(preview("2027-02-01")),
    )
    .await;
    assert_eq!(d(&p["lines"][0]["rebate_percent"]), "20");

    let id = r["id"].as_str().unwrap();
    let (status, _) = call(&app, MANAGER, Method::DELETE, &format!("{url}/{id}"), None).await;
    assert_eq!(status, StatusCode::NO_CONTENT);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn bulk_price_change_is_previewed_then_applied(db: PgPool) {
    let app = setup(db).await;
    let from = (tradocraft_core::today() + chrono::Duration::days(30)).to_string();
    let body = json!({ "family_id": PUMPS, "kind": "percent", "value": "5", "rounding": "0.05", "valid_from": from });

    let (status, _) = call(
        &app,
        SALES,
        Method::POST,
        "/api/v1/prices/bulk/preview",
        Some(body.clone()),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);

    let (status, p) = call(
        &app,
        ADMIN,
        Method::POST,
        "/api/v1/prices/bulk/preview",
        Some(body.clone()),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{p}");
    let lines = p["lines"].as_array().unwrap();
    assert_eq!(lines.len(), 5, "one pump in five zones");
    assert!(lines.iter().all(|l| l["product_code"] == "PUMP-05"));
    let z1 = lines.iter().find(|l| l["zone_code"] == "Z1").unwrap();
    assert_eq!(d(&z1["current_price"]), "448");
    assert_eq!(d(&z1["new_price"]), "470.4");
    let z5 = lines.iter().find(|l| l["zone_code"] == "Z5").unwrap();
    assert_eq!(d(&z5["new_price"]), "672");

    let (status, a) = call(
        &app,
        ADMIN,
        Method::POST,
        "/api/v1/prices/bulk/apply",
        Some(body.clone()),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{a}");
    assert_eq!(a["applied"], 5);

    // The new prices start on their date; quotes before that keep the current price.
    let (_, prices) = call(
        &app,
        ADMIN,
        Method::GET,
        &format!("/api/v1/products/{PUMP}/prices"),
        None,
    )
    .await;
    assert!(prices
        .as_array()
        .unwrap()
        .iter()
        .any(|p| p["valid_from"] == from.as_str()));
    let (_, p) = call(
        &app,
        SALES,
        Method::POST,
        "/api/v1/pricing/preview",
        Some(json!({ "customer_id": ALPHA, "lines": [line(PUMP, "1")] })),
    )
    .await;
    assert_eq!(d(&p["lines"][0]["list_unit_price"]), "512");

    // Applying twice for the same date is refused; past dates are refused.
    let (status, _) = call(
        &app,
        ADMIN,
        Method::POST,
        "/api/v1/prices/bulk/apply",
        Some(body),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
    let past = json!({ "kind": "percent", "value": "5", "valid_from": "2026-01-01" });
    let (status, _) = call(
        &app,
        ADMIN,
        Method::POST,
        "/api/v1/prices/bulk/preview",
        Some(past),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn products_belong_to_families(db: PgPool) {
    let app = setup(db).await;
    let (status, f) = call(
        &app,
        ADMIN,
        Method::POST,
        "/api/v1/product-families",
        Some(json!({ "code": "VALVES", "name": "Valves" })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{f}");
    let (status, p) = call(
        &app,
        ADMIN,
        Method::POST,
        "/api/v1/products",
        Some(json!({ "code": "VALVE-1", "name": "Valve", "vat_rate": "21", "family_id": f["id"], "non_discountable": true, "price_is_indicative": true })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{p}");
    assert_eq!(p["family_code"], "VALVES");
    assert_eq!(p["non_discountable"], true);
    assert_eq!(p["price_on_request"], false);
    assert_eq!(p["price_is_indicative"], true);
    let (_, page) = call(
        &app,
        SALES,
        Method::GET,
        &format!("/api/v1/products?family_id={PUMPS}"),
        None,
    )
    .await;
    assert_eq!(page["total"], 1);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn planned_prices_can_be_corrected_or_replaced_but_prices_in_effect_cannot(db: PgPool) {
    let app = setup(db).await;
    let today = tradocraft_core::today();
    let from = (today + chrono::Duration::days(30)).to_string();
    let later = (today + chrono::Duration::days(40)).to_string();

    // A planned price with a typo.
    let (status, wrong) = call(
        &app,
        ADMIN,
        Method::POST,
        &format!("/api/v1/products/{PUMP}/prices"),
        Some(json!({ "zone_id": ZONE_Z2, "unit_price": "5320", "valid_from": from })),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{wrong}");
    let wrong_id = wrong["id"].as_str().unwrap();

    // Sales cannot correct it; a price manager can, also its date.
    let fix = json!({ "unit_price": "532", "valid_from": later });
    let url = format!("/api/v1/products/{PUMP}/prices/{wrong_id}");
    let (status, _) = call(&app, SALES, Method::PUT, &url, Some(fix.clone())).await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, fixed) = call(&app, ADMIN, Method::PUT, &url, Some(fix)).await;
    assert_eq!(status, StatusCode::OK, "{fixed}");
    assert_eq!(d(&fixed["unit_price"]), "532");
    assert_eq!(fixed["valid_from"], later.as_str());
    // ...but not to today or into the past.
    let (status, _) = call(
        &app,
        ADMIN,
        Method::PUT,
        &url,
        Some(json!({ "unit_price": "532", "valid_from": today.to_string() })),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    // The price in effect (512 since the seed) is history: no correction, no delete.
    let (_, prices) = call(
        &app,
        ADMIN,
        Method::GET,
        &format!("/api/v1/products/{PUMP}/prices"),
        None,
    )
    .await;
    let current = prices
        .as_array()
        .unwrap()
        .iter()
        .find(|p| p["zone_code"] == "Z2" && p["id"] != wrong_id)
        .unwrap();
    let current_url = format!(
        "/api/v1/products/{PUMP}/prices/{}",
        current["id"].as_str().unwrap()
    );
    let (status, _) = call(
        &app,
        ADMIN,
        Method::PUT,
        &current_url,
        Some(json!({ "unit_price": "1", "valid_from": later })),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
    let (status, _) = call(&app, ADMIN, Method::DELETE, &current_url, None).await;
    assert_eq!(status, StatusCode::CONFLICT);

    // A bulk change onto the planned date is refused, unless the planned prices are replaced;
    // the change is then computed from the price before them.
    let body = |replace: bool| {
        json!({ "product_ids": [PUMP], "zone_ids": [ZONE_Z2], "kind": "percent", "value": "10",
                "valid_from": later, "replace_planned": replace })
    };
    let (status, _) = call(
        &app,
        ADMIN,
        Method::POST,
        "/api/v1/prices/bulk/apply",
        Some(body(false)),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
    let (status, a) = call(
        &app,
        ADMIN,
        Method::POST,
        "/api/v1/prices/bulk/apply",
        Some(body(true)),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{a}");
    assert_eq!(a["applied"], 1);
    assert_eq!(a["conflicts"], 0);
    let l = &a["lines"][0];
    assert_eq!(d(&l["current_price"]), "512");
    assert_eq!(d(&l["replaced_price"]), "532");
    assert_eq!(d(&l["new_price"]), "563.2");
    let (_, prices) = call(
        &app,
        ADMIN,
        Method::GET,
        &format!("/api/v1/products/{PUMP}/prices"),
        None,
    )
    .await;
    let planned: Vec<&Value> = prices
        .as_array()
        .unwrap()
        .iter()
        .filter(|p| p["valid_from"] == later.as_str())
        .collect();
    assert_eq!(planned.len(), 1);
    assert_eq!(d(&planned[0]["unit_price"]), "563.2");

    // Replacing is only for planned dates: not for today.
    let (status, _) = call(
        &app,
        ADMIN,
        Method::POST,
        "/api/v1/prices/bulk/preview",
        Some(
            json!({ "product_ids": [PUMP], "kind": "percent", "value": "1",
                     "valid_from": today.to_string(), "replace_planned": true }),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    // A planned price can be deleted.
    let id = planned[0]["id"].as_str().unwrap();
    let (status, _) = call(
        &app,
        ADMIN,
        Method::DELETE,
        &format!("/api/v1/products/{PUMP}/prices/{id}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NO_CONTENT);
}
