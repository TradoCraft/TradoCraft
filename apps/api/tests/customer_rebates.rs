//! Annual rebate cutoffs and approval.

mod common;

use axum::http::{Method, StatusCode};
use chrono::{Datelike, NaiveDate};
use common::{call, dec, setup_test_environment};
use rust_decimal::Decimal;
use serde_json::json;
use sqlx::PgPool;

const ADMIN: &str = "admin@example.com";
const SALES: &str = "sales@example.com";
const ALPHA: &str = "00000000-0000-7000-8000-000000000401";
const PUMP: &str = "00000000-0000-7000-8000-000000000303";
const HOSE: &str = "00000000-0000-7000-8000-000000000304";

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn approval_uses_verified_sales_net_of_credits_after_cutoff(db: PgPool) {
    let app = setup_test_environment(db.clone()).await;
    let year = tradocraft_core::today().year();
    let prior_year = year - 1;
    let cutoff = NaiveDate::from_ymd_opt(prior_year, 12, 1).unwrap();
    let credit_date = NaiveDate::from_ymd_opt(prior_year, 12, 15).unwrap();
    let base = format!("/api/v1/customer-rebates/customers/{ALPHA}");
    let history = format!("{base}/history");
    let review = format!("{base}/rates/{year}");
    let approve = format!("{base}/rates");
    let (status, settings) = call(
        &app,
        ADMIN,
        Method::GET,
        "/api/v1/customer-rebates/settings",
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{settings}");
    assert_eq!(settings["show_on_invoices"], false);
    let (status, _) = call(&app, SALES, Method::GET, &review, None).await;
    assert_eq!(status, StatusCode::FORBIDDEN);

    let (status, schedule) = call(
        &app,
        ADMIN,
        Method::POST,
        "/api/v1/customer-rebates/schedules",
        Some(json!({
            "name": "Annual sales",
            "effective_year": year,
            "tiers": [
                { "threshold": "8000", "rate": "4" },
                { "threshold": "10000", "rate": "8" }
            ]
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{schedule}");
    let (status, assignment) = call(
        &app,
        ADMIN,
        Method::PUT,
        &format!("{base}/assignment"),
        Some(json!({ "schedule_name": "Annual sales" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{assignment}");

    let (status, unresolved) = call(&app, ADMIN, Method::GET, &review, None).await;
    assert_eq!(status, StatusCode::OK, "{unresolved}");
    assert!(unresolved["eligible_sales"].is_null());
    assert!(unresolved["proposed_rate"].is_null());
    let (status, _) = call(
        &app,
        ADMIN,
        Method::POST,
        &approve,
        Some(json!({ "rate_year": year })),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    let opening = json!({ "year": prior_year, "cutoff": cutoff, "eligible_sales": "10100" });
    for _ in 0..2 {
        let (status, saved) = call(&app, ADMIN, Method::PUT, &history, Some(opening.clone())).await;
        assert_eq!(status, StatusCode::OK, "{saved}");
    }
    let audit_count: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM audit.events WHERE entity = 'customer_rebate_opening' AND action = 'verified'",
    ).fetch_one(&db).await.unwrap();
    assert_eq!(audit_count, 1);

    let (status, original) = call(
        &app,
        ADMIN,
        Method::POST,
        "/api/v1/customer-invoices/legacy",
        Some(json!({
            "customer_id": ALPHA,
            "number": "EXTERNAL-001",
            "document_date": cutoff,
            "currency": "EUR",
            "vat_regime": "domestic",
            "evidence_reference": "Verified external invoice",
            "lines": [{
                "product_code": "SKU",
                "description": "External sale",
                "unit": "pcs",
                "quantity": "1",
                "net_total": "200",
                "vat_total": "42",
                "vat_rate": "21",
                "included_in_turnover": true
            }]
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{original}");
    let (status, draft) = call(
        &app,
        ADMIN,
        Method::POST,
        "/api/v1/customer-invoices/credits",
        Some(json!({
            "invoice_id": original["document"]["id"],
            "document_date": credit_date,
            "reason": "Returned item",
            "lines": [{ "invoice_line_id": original["lines"][0]["id"], "quantity": "1" }]
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{draft}");
    let (status, posted) = call(
        &app,
        ADMIN,
        Method::POST,
        &format!(
            "/api/v1/customer-invoices/{}/post",
            draft["document"]["id"].as_str().unwrap()
        ),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{posted}");

    let (status, reviewed) = call(&app, ADMIN, Method::GET, &review, None).await;
    assert_eq!(status, StatusCode::OK, "{reviewed}");
    assert_eq!(dec(&reviewed["eligible_sales"]), Decimal::from(9900));
    assert_eq!(dec(&reviewed["proposed_rate"]), Decimal::from(4));
    assert!(reviewed["approved_rate"].is_null());

    let pricing_input = json!({ "customer_id": ALPHA, "lines": [
        { "product_id": HOSE, "quantity": "1" },
        { "product_id": PUMP, "quantity": "1" }
    ] });
    let (status, existing_quote) = call(
        &app,
        SALES,
        Method::POST,
        "/api/v1/quotations",
        Some(pricing_input.clone()),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{existing_quote}");
    assert_eq!(
        dec(&existing_quote["lines"][0]["rebate_percent"]),
        Decimal::from(5)
    );

    let (status, approved) = call(
        &app,
        ADMIN,
        Method::POST,
        &approve,
        Some(json!({ "rate_year": year })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{approved}");
    assert_eq!(dec(&approved["approved_rate"]), Decimal::from(4));

    let mut first_day_input = pricing_input.clone();
    first_day_input["quote_date"] = json!(NaiveDate::from_ymd_opt(year, 1, 1).unwrap());
    let (status, price_preview) = call(
        &app,
        SALES,
        Method::POST,
        "/api/v1/pricing/preview",
        Some(first_day_input),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{price_preview}");
    assert_eq!(
        dec(&price_preview["lines"][0]["rebate_percent"]),
        Decimal::from(4)
    );
    assert_eq!(
        dec(&price_preview["lines"][1]["rebate_percent"]),
        Decimal::from(12)
    );
    let mut following_year_input = pricing_input;
    following_year_input["quote_date"] = json!(NaiveDate::from_ymd_opt(year + 1, 1, 1).unwrap());
    let (status, following_year_preview) = call(
        &app,
        SALES,
        Method::POST,
        "/api/v1/pricing/preview",
        Some(following_year_input),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{following_year_preview}");
    assert_eq!(
        dec(&following_year_preview["lines"][0]["rebate_percent"]),
        Decimal::from(5)
    );
    let (status, unchanged_quote) = call(
        &app,
        SALES,
        Method::GET,
        &format!(
            "/api/v1/quotations/{}",
            existing_quote["id"].as_str().unwrap()
        ),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{unchanged_quote}");
    assert_eq!(
        dec(&unchanged_quote["lines"][0]["rebate_percent"]),
        Decimal::from(5)
    );

    let (status, post_approval_correction) = call(
        &app,
        ADMIN,
        Method::PUT,
        &history,
        Some(json!({ "year": prior_year, "cutoff": cutoff, "eligible_sales": "11100" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{post_approval_correction}");
    let (status, review_after_correction) = call(&app, ADMIN, Method::GET, &review, None).await;
    assert_eq!(status, StatusCode::OK, "{review_after_correction}");
    assert_eq!(
        dec(&review_after_correction["proposed_rate"]),
        Decimal::from(8)
    );
    assert_eq!(
        dec(&review_after_correction["approved_rate"]),
        Decimal::from(4)
    );
}
