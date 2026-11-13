//! VAT numbers (ADR 0058, roadmap D4): validation of customers' and suppliers' numbers, the
//! duplicate warning and the VIES lookup, against a local stand-in for VIES.

mod common;

use std::sync::{Arc, Mutex};
use std::time::Duration;

use axum::extract::State;
use axum::http::{Method, StatusCode};
use axum::routing::post;
use axum::{Json, Router};
use common::{call, raw, setup, setup_with_vies, Who};
use serde_json::{json, Value};
use sqlx::PgPool;
use tradocraft_core::vies::ViesConfig;
use uuid::Uuid;

const ADMIN: &str = "admin@example.com";
const SALES: &str = "sales@example.com";
const VIEWER: &str = "viewer@example.com";
const COMPANY: &str = "00000000-0000-7000-8000-000000000001";
const ALPHA: &str = "00000000-0000-7000-8000-000000000401";
const GAMMA: &str = "00000000-0000-7000-8000-000000000403";
const ZONE: &str = "00000000-0000-7000-8000-000000000202";

/// Alpha's number in the seed (valid) and Gamma's (a German number with a leading zero: invalid,
/// as legacy data may be).
const ALPHA_VAT: &str = "BE0000000097";
const GAMMA_VAT: &str = "DE000000000";
/// Real numbers that pass the check digits (also in the unit tests of `core::vat`).
const GOOD_BE: &str = "BE0428759497";
const BAD_BE: &str = "BE0428759498";

async fn get(app: &Router, user: &str, uri: &str) -> (StatusCode, Value) {
    call(app, user, Method::GET, &format!("/api/v1{uri}"), None).await
}

async fn send(
    app: &Router,
    user: &str,
    method: Method,
    uri: &str,
    b: Value,
) -> (StatusCode, Value) {
    call(app, user, method, &format!("/api/v1{uri}"), Some(b)).await
}

fn customer(code: &str, vat: Option<&str>) -> Value {
    json!({
        "code": code, "name": format!("Customer {code}"), "vat_number": vat,
        "country_code": "BE", "price_zone_id": ZONE,
    })
}

// ---- customers: validation -------------------------------------------------------------------

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_customer_with_wrong_check_digits_is_refused(db: PgPool) {
    let app = setup(db).await;

    let (status, e) = send(
        &app,
        SALES,
        Method::POST,
        "/customers",
        customer("V1", Some(BAD_BE)),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{e}");
    assert!(
        e["message"].as_str().unwrap().contains("check digits"),
        "{e}"
    );

    // The shape is wrong rather than the digits: said differently.
    let (status, e) = send(
        &app,
        SALES,
        Method::POST,
        "/customers",
        customer("V2", Some("BE04287")),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{e}");
    assert!(
        e["message"]
            .as_str()
            .unwrap()
            .contains("not shaped like a BE"),
        "{e}"
    );

    // Nothing was written by the refusals.
    let (_, page) = get(&app, SALES, "/customers?q=V1").await;
    assert_eq!(page["total"], 0);

    // Good numbers in any spelling are stored as typed.
    for (code, vat) in [
        ("V3", GOOD_BE),
        ("V4", "be 0428.759.497"),
        // No prefix: the customer's country (BE) supplies it.
        ("V5", "0428.759.497"),
    ] {
        let (status, c) = send(
            &app,
            SALES,
            Method::POST,
            "/customers",
            customer(code, Some(vat)),
        )
        .await;
        assert_eq!(status, StatusCode::CREATED, "{vat}: {c}");
        assert_eq!(c["vat_number"], vat);
    }

    // Numbers that are not EU numbers are nobody's rule: a Swiss UID, a number without a country.
    for (code, vat, country) in [
        ("V6", "CHE-123.456.789 MWST", "CH"),
        ("V7", "12-3456789", "US"),
    ] {
        let mut body = customer(code, Some(vat));
        body["country_code"] = json!(country);
        body["vat_regime"] = json!("outside_eu");
        let (status, c) = send(&app, SALES, Method::POST, "/customers", body).await;
        assert_eq!(status, StatusCode::CREATED, "{vat}: {c}");
    }

    // A country without a check-digit rule here gets the shape test only.
    let mut body = customer("V8", Some("ESB12345678"));
    body["country_code"] = json!("ES");
    assert_eq!(
        send(&app, SALES, Method::POST, "/customers", body).await.0,
        StatusCode::CREATED
    );

    // And no number at all is fine.
    assert_eq!(
        send(
            &app,
            SALES,
            Method::POST,
            "/customers",
            customer("V9", None)
        )
        .await
        .0,
        StatusCode::CREATED
    );
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn an_unchanged_legacy_number_does_not_block_editing_the_rest(db: PgPool) {
    let app = setup(db).await;
    let uri = format!("/customers/{GAMMA}");
    let (_, g) = get(&app, SALES, &uri).await;
    assert_eq!(
        g["vat_number"], GAMMA_VAT,
        "the seed's invalid legacy number"
    );

    // The number is untouched while another field changes: allowed.
    let mut body = customer("C0003", Some(GAMMA_VAT));
    body["name"] = json!("Gamma Trading GmbH");
    body["country_code"] = json!("DE");
    body["city"] = json!("Bonn");
    let (status, c) = send(&app, SALES, Method::PUT, &uri, body.clone()).await;
    assert_eq!(status, StatusCode::OK, "{c}");
    assert_eq!(c["city"], "Bonn");

    // Respelled, it is still the same number.
    body["vat_number"] = json!("DE 000 000 000");
    assert_eq!(
        send(&app, SALES, Method::PUT, &uri, body.clone()).await.0,
        StatusCode::OK
    );

    // A different wrong number is refused, a right one accepted.
    body["vat_number"] = json!("DE136695977");
    let (status, e) = send(&app, SALES, Method::PUT, &uri, body.clone()).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{e}");
    body["vat_number"] = json!("DE136695976");
    assert_eq!(
        send(&app, SALES, Method::PUT, &uri, body).await.0,
        StatusCode::OK
    );
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_csv_import_applies_the_rule_to_new_and_changed_numbers_only(db: PgPool) {
    let app = setup(db).await;
    let import = |csv: &'static str| {
        let app = app.clone();
        async move {
            let (status, _, body) = raw(
                &app,
                Who::Staff(ADMIN),
                Method::POST,
                "/api/v1/customers/import?dry_run=true",
                Some(("text/csv", csv.as_bytes().to_vec())),
            )
            .await;
            (
                status,
                serde_json::from_slice::<Value>(&body).unwrap_or(Value::Null),
            )
        }
    };
    // A new row with a typo, and Gamma re-imported with its (invalid) number untouched.
    let (status, r) = import(
        "code,name,vat_number,country_code,price_zone_code\n\
         N1,New one,BE0428759498,BE,Z2\n\
         C0003,Gamma Trading GmbH,DE000000000,DE,Z3\n",
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{r}");
    let errors = r["errors"].as_array().unwrap();
    assert_eq!(errors.len(), 1, "only the new typo is an error: {r}");
    assert_eq!(errors[0]["column"], "vat_number");
    assert!(errors[0]["message"]
        .as_str()
        .unwrap()
        .contains("check digits"));

    // Changing Gamma's number to another wrong one is an error; to a right one, fine.
    let (status, r) = import("code,vat_number\nC0003,DE136695977\n").await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{r}");
    let (status, r) = import("code,vat_number\nC0003,DE136695976\n").await;
    assert_eq!(status, StatusCode::OK, "{r}");
    assert_eq!(r["updated"], 1);
}

// ---- customers: the check endpoint ------------------------------------------------------------

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_check_reports_status_and_duplicates(db: PgPool) {
    let app = setup(db).await;
    let check = |q: String| {
        let app = app.clone();
        async move { get(&app, SALES, &format!("/customers/vat-check?{q}")).await }
    };

    // A number a customer already has: valid, and that customer is named.
    let (status, c) = check("vat_number=BE0000000097".into()).await;
    assert_eq!(status, StatusCode::OK, "{c}");
    assert_eq!(c["status"], "valid");
    assert_eq!(c["normalized"], ALPHA_VAT);
    assert_eq!(c["duplicates"].as_array().unwrap().len(), 1);
    assert_eq!(c["duplicates"][0]["id"], ALPHA);
    assert_eq!(c["duplicates"][0]["code"], "C0001");
    assert!(c["vies"].is_null(), "no lookup was asked for");

    // Spelled differently, or without the prefix for a customer in that country, it is the same.
    for q in [
        "vat_number=be%200000.000.097",
        "vat_number=0000000097&country_code=BE",
        "vat_number=0000000097&country_code=be",
    ] {
        let (_, c) = check(q.into()).await;
        assert_eq!(c["duplicates"][0]["id"], ALPHA, "{q}: {c}");
    }
    // ... but the bare number of another country's record is not.
    let (_, c) = check("vat_number=0000000097&country_code=NL".into()).await;
    assert_eq!(c["duplicates"].as_array().unwrap().len(), 0, "{c}");

    // The customer being edited is not its own duplicate.
    let (_, c) = check(format!("vat_number={ALPHA_VAT}&exclude_id={ALPHA}")).await;
    assert_eq!(c["duplicates"].as_array().unwrap().len(), 0);

    // A wrong number says what is wrong and still lists whoever carries it (nobody here).
    let (_, c) = check(format!("vat_number={BAD_BE}")).await;
    assert_eq!(c["status"], "bad_checksum");
    assert!(c["message"].as_str().unwrap().contains("check digits"));
    let (_, c) = check("vat_number=BE123".into()).await;
    assert_eq!(c["status"], "bad_format");

    // Empty, and not an EU number.
    let (_, c) = check("vat_number=%20".into()).await;
    assert_eq!(c["status"], "empty");
    assert_eq!(c["duplicates"].as_array().unwrap().len(), 0);
    let (_, c) = check("vat_number=CHE-123.456.789".into()).await;
    assert_eq!(c["status"], "not_checked");
    assert!(c["normalized"].is_null());

    // A legacy number that is wrong still finds its record: the warning does not need it valid.
    let (_, c) = check(format!("vat_number={GAMMA_VAT}")).await;
    assert_eq!(c["status"], "bad_checksum");
    assert_eq!(c["duplicates"][0]["id"], GAMMA);

    // Foreign numbers are compared as compacted text.
    let (status, _) = send(
        &app,
        SALES,
        Method::POST,
        "/customers",
        json!({"code": "CH1", "name": "Swiss", "vat_number": "CHE-123.456.789 MWST",
               "country_code": "CH", "vat_regime": "outside_eu", "price_zone_id": ZONE}),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);
    let (_, c) = check("vat_number=che123456789mwst".into()).await;
    assert_eq!(c["duplicates"][0]["code"], "CH1", "{c}");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn greek_numbers_match_under_both_prefixes(db: PgPool) {
    let app = setup(db).await;
    // A valid Greek number: VIES writes EL for the number, the country code is GR.
    let mut body = customer("GR1", Some("EL094259216"));
    body["country_code"] = json!("GR");
    let (status, c) = send(&app, SALES, Method::POST, "/customers", body).await;
    assert_eq!(status, StatusCode::CREATED, "{c}");
    for q in [
        "vat_number=EL094259216",
        "vat_number=GR094259216",
        "vat_number=094259216&country_code=GR",
    ] {
        let (_, c) = get(&app, SALES, &format!("/customers/vat-check?{q}")).await;
        assert_eq!(c["status"], "valid", "{q}: {c}");
        assert_eq!(c["normalized"], "EL094259216", "{q}");
        assert_eq!(c["duplicates"][0]["code"], "GR1", "{q}: {c}");
    }
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_check_and_the_lookup_have_their_own_permissions(db: PgPool) {
    let app = setup(db).await;
    // The viewer reads customers: checking is allowed, asking VIES is not.
    let (status, _) = get(&app, VIEWER, "/customers/vat-check?vat_number=BE0428759497").await;
    assert_eq!(status, StatusCode::OK);
    let (status, e) = get(
        &app,
        VIEWER,
        "/customers/vat-check?vat_number=BE0428759497&lookup=true",
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN, "{e}");
    // Sales may. The test application has the lookup off, which is reported, not hidden.
    let (status, c) = get(
        &app,
        SALES,
        "/customers/vat-check?vat_number=BE0428759497&lookup=true",
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{c}");
    assert_eq!(c["vies"]["state"], "unavailable");
    assert_eq!(c["vies"]["reason"], "disabled");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_belgian_number_matches_with_and_without_its_leading_zero(db: PgPool) {
    let app = setup(db).await;
    // Both are accepted spellings of one number: the ten-digit form and the older nine-digit one.
    let (status, a) = send(
        &app,
        SALES,
        Method::POST,
        "/customers",
        customer("Z1", Some("BE0428759497")),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{a}");
    let (status, b) = send(
        &app,
        SALES,
        Method::POST,
        "/customers",
        customer("Z2", Some("BE 428.759.497")),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{b}");
    let (id_a, id_b) = (a["id"].as_str().unwrap(), b["id"].as_str().unwrap());

    let codes = |c: &Value| -> Vec<String> {
        let mut v: Vec<String> = c["duplicates"]
            .as_array()
            .unwrap()
            .iter()
            .map(|d| d["code"].as_str().unwrap().to_string())
            .collect();
        v.sort();
        v
    };
    // Whichever spelling is typed finds both records, whichever spelling they were stored in.
    for q in [
        "vat_number=BE0428759497",
        "vat_number=BE428759497",
        "vat_number=0428.759.497&country_code=BE",
        "vat_number=428759497&country_code=BE",
    ] {
        let (_, c) = get(&app, SALES, &format!("/customers/vat-check?{q}")).await;
        assert_eq!(c["status"], "valid", "{q}");
        assert_eq!(codes(&c), ["Z1", "Z2"], "{q}: {c}");
    }
    // Editing one of them sees the other, not itself.
    let (_, c) = get(
        &app,
        SALES,
        &format!("/customers/vat-check?vat_number=BE428759497&exclude_id={id_a}"),
    )
    .await;
    assert_eq!(codes(&c), ["Z2"]);
    let (_, c) = get(
        &app,
        SALES,
        &format!("/customers/vat-check?vat_number=BE0428759497&exclude_id={id_b}"),
    )
    .await;
    assert_eq!(codes(&c), ["Z1"]);
    // Another country's bare number is still another number.
    let (_, c) = get(
        &app,
        SALES,
        "/customers/vat-check?vat_number=428759497&country_code=NL",
    )
    .await;
    assert!(codes(&c).is_empty(), "{c}");

    // The same for suppliers.
    send(
        &app,
        ADMIN,
        Method::POST,
        "/suppliers",
        supplier("Short", "BE", Some("BE428759497")),
    )
    .await;
    let (_, c) = get(&app, ADMIN, "/suppliers/vat-check?vat_number=BE0428759497").await;
    assert_eq!(c["duplicates"].as_array().unwrap().len(), 1, "{c}");
    let (_, c) = get(
        &app,
        ADMIN,
        "/suppliers/vat-check?vat_number=0428759497&country_code=BE",
    )
    .await;
    assert_eq!(c["duplicates"].as_array().unwrap().len(), 1, "{c}");
}

/// The duplicate warning compares a number typed now with numbers stored earlier. The typed one is
/// reduced in Rust, the stored ones in SQL (`core.vat_key`): the two have to agree on every input.
#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_key_in_rust_is_the_key_in_the_database(db: PgPool) {
    for raw in [
        "BE0428759497",
        "be 0428.759.497",
        "BE (0)428.759.497",
        "BE-0428/759,497_",
        "CHE-123.456.789 (MWST)",
        "gr 094 259 216",
        "GR094259216",
        "EL094259216",
        "AGR1",
        "GRGR1",
        "US 12-3456789",
        "Ünï-1 Çé 2",
        "ß ǅ 3 ０１２",
        "tab\there\nnewline",
        "+32 (0)475 12 34 56",
        "",
        "   ",
        "---",
    ] {
        let sql: String = sqlx::query_scalar("SELECT core.vat_key($1)")
            .bind(raw)
            .fetch_one(&db)
            .await
            .unwrap();
        assert_eq!(tradocraft_core::vat::key(raw), sql, "{raw:?}");
    }
}

// ---- the lookup against a stand-in for VIES ---------------------------------------------------

struct Vies {
    url: String,
    /// Every request body the stand-in received.
    seen: Arc<Mutex<Vec<Value>>>,
}

async fn vies_stand_in() -> Vies {
    async fn handler(
        State(seen): State<Arc<Mutex<Vec<Value>>>>,
        Json(body): Json<Value>,
    ) -> (StatusCode, String) {
        seen.lock().unwrap().push(body.clone());
        let number = body["vatNumber"].as_str().unwrap_or_default().to_string();
        let reply = |v: Value| (StatusCode::OK, v.to_string());
        match number.as_str() {
            // Valid, with a name and a two-line address.
            "0428759497" => reply(json!({
                "isValid": true, "userError": "VALID", "name": "ACME NV",
                "address": "RUE DE LA LOI 16\n1000 BRUXELLES"
            })),
            // Valid but the member state does not say who it is.
            "136695976" if body["countryCode"] == "DE" => {
                reply(json!({"valid": true, "name": "---", "address": "---"}))
            }
            // Locally valid, unknown to VIES.
            "0000000196" => reply(json!({"isValid": false, "userError": "INVALID"})),
            // The member state's service is down.
            "004495445B01" => reply(json!({"isValid": false, "userError": "MS_UNAVAILABLE"})),
            // The service itself is down.
            "15027442" => (StatusCode::SERVICE_UNAVAILABLE, "maintenance".into()),
            // Too slow.
            "U13585627" => {
                tokio::time::sleep(Duration::from_secs(3)).await;
                reply(json!({"isValid": true, "name": "LATE"}))
            }
            _ => reply(json!({"isValid": false})),
        }
    }
    let seen = Arc::new(Mutex::new(Vec::new()));
    let router = Router::new()
        .route("/check-vat-number", post(handler))
        .with_state(seen.clone());
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let url = format!("http://{}", listener.local_addr().unwrap());
    tokio::spawn(async move {
        axum::serve(listener, router).await.unwrap();
    });
    Vies { url, seen }
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_lookup_prefills_and_falls_back_when_vies_cannot_answer(db: PgPool) {
    let vies = vies_stand_in().await;
    let app = setup_with_vies(
        db,
        ViesConfig::new(&vies.url).with_timeout(Duration::from_millis(500)),
    )
    .await;
    let look = |number: &'static str| {
        let app = app.clone();
        async move {
            let (status, c) = get(
                &app,
                SALES,
                &format!("/customers/vat-check?vat_number={number}&lookup=true"),
            )
            .await;
            assert_eq!(status, StatusCode::OK, "{number}: {c}");
            c
        }
    };

    // The happy path: name and address, the address cut into the form's fields.
    let c = look("BE0428759497").await;
    assert_eq!(c["status"], "valid");
    let v = &c["vies"];
    assert_eq!(v["state"], "valid", "{c}");
    assert_eq!(v["name"], "ACME NV");
    assert_eq!(v["street"], "RUE DE LA LOI 16");
    assert_eq!(v["postal_code"], "1000");
    assert_eq!(v["city"], "BRUXELLES");
    assert!(v["reason"].is_null());

    // Only the number goes out: the prefix as country code, the national part, nothing else.
    assert_eq!(
        vies.seen.lock().unwrap()[0],
        json!({"countryCode": "BE", "vatNumber": "0428759497"})
    );

    // Valid without a name: still valid, nothing to prefill.
    let v = look("DE136695976").await["vies"].clone();
    assert_eq!(v["state"], "valid");
    assert!(v["name"].is_null() && v["address"].is_null() && v["street"].is_null());

    // Unknown to VIES although the digits are right.
    let c = look("BE0000000196").await;
    assert_eq!(c["status"], "valid");
    assert_eq!(c["vies"]["state"], "invalid");

    // Everything that stops VIES from answering ends as `unavailable` with a reason: the form
    // carries on by hand and the local result stays.
    for (number, reason) in [
        ("NL004495445B01", "ms_unavailable"),
        ("LU15027442", "http_503"),
        ("ATU13585627", "timeout"),
    ] {
        let c = look(number).await;
        assert_eq!(c["status"], "valid", "{number}");
        assert_eq!(c["vies"]["state"], "unavailable", "{number}: {c}");
        assert_eq!(c["vies"]["reason"], reason, "{number}");
        assert!(c["vies"]["name"].is_null());
    }

    // A number that already fails the local rules, or is not an EU number, is not sent at all.
    let sent = vies.seen.lock().unwrap().len();
    let c = look("BE0428759498").await;
    assert_eq!(c["vies"]["state"], "not_applicable");
    let c = look("CHE-123.456.789").await;
    assert_eq!(c["vies"]["state"], "not_applicable");
    assert_eq!(vies.seen.lock().unwrap().len(), sent);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn an_unreachable_vies_is_unavailable_not_an_error(db: PgPool) {
    // A port nobody listens on.
    let closed = {
        let l = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        format!("http://{}", l.local_addr().unwrap())
    };
    let app = setup_with_vies(db, ViesConfig::new(closed)).await;
    let (status, c) = get(
        &app,
        SALES,
        "/customers/vat-check?vat_number=BE0428759497&lookup=true",
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{c}");
    assert_eq!(c["vies"]["state"], "unavailable");
    assert_eq!(c["vies"]["reason"], "network");
}

// ---- suppliers ---------------------------------------------------------------------------------

async fn add_buyer(db: &PgPool) -> &'static str {
    let id = Uuid::now_v7();
    sqlx::query("INSERT INTO core.users (id, email, display_name) VALUES ($1, 'buyer@example.com', 'Buyer')")
        .bind(id)
        .execute(db)
        .await
        .unwrap();
    sqlx::query("INSERT INTO core.user_companies (user_id, company_id, roles, is_default) VALUES ($1, $2::uuid, $3, true)")
        .bind(id)
        .bind(COMPANY)
        .bind(vec!["purchaser".to_string()])
        .execute(db)
        .await
        .unwrap();
    "buyer@example.com"
}

fn supplier(name: &str, country: &str, tax_id: Option<&str>) -> Value {
    json!({"name": name, "country": country, "tax_id": tax_id})
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_supplier_number_is_checked_when_created_or_changed(db: PgPool) {
    let app = setup(db.clone()).await;

    let (status, e) = send(
        &app,
        ADMIN,
        Method::POST,
        "/suppliers",
        supplier("S1", "BE", Some(BAD_BE)),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{e}");
    assert!(
        e["message"].as_str().unwrap().contains("check digits"),
        "{e}"
    );
    let (_, list) = get(&app, ADMIN, "/suppliers").await;
    assert_eq!(
        list.as_array().unwrap().len(),
        0,
        "the refusal wrote nothing"
    );

    let (status, s) = send(
        &app,
        ADMIN,
        Method::POST,
        "/suppliers",
        supplier("S1", "BE", Some("0428.759.497")),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{s}");
    assert_eq!(s["tax_id"], "0428.759.497", "stored as typed");
    // A supplier outside the EU keeps any tax number; no number is fine too.
    for (name, country, tax) in [("S2", "CH", Some("CHE-123.456.789")), ("S3", "NL", None)] {
        let (status, s) = send(
            &app,
            ADMIN,
            Method::POST,
            "/suppliers",
            supplier(name, country, tax),
        )
        .await;
        assert_eq!(status, StatusCode::CREATED, "{name}: {s}");
    }

    // A number entered before the check existed (straight into the table) stays editable around.
    let legacy = Uuid::now_v7();
    sqlx::query(
        "INSERT INTO purchasing.suppliers (id, company_id, name, country, tax_id) VALUES ($1, $2::uuid, 'Legacy', 'DE', 'DE000000000')",
    )
    .bind(legacy)
    .bind(COMPANY)
    .execute(&db)
    .await
    .unwrap();
    let uri = format!("/suppliers/{legacy}");
    let (status, s) = send(
        &app,
        ADMIN,
        Method::PUT,
        &uri,
        json!({"name": "Legacy GmbH"}),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{s}");
    assert_eq!(s["tax_id"], "DE000000000");
    // Changing it to another wrong number is refused; to a right one accepted. Changing only the
    // country of an unchanged number is not a new number.
    let (status, _) = send(
        &app,
        ADMIN,
        Method::PUT,
        &uri,
        json!({"tax_id": "DE136695977"}),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    let (status, _) = send(&app, ADMIN, Method::PUT, &uri, json!({"country": "AT"})).await;
    assert_eq!(status, StatusCode::OK);
    let (status, _) = send(
        &app,
        ADMIN,
        Method::PUT,
        &uri,
        json!({"tax_id": "DE136695976", "country": "DE"}),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_supplier_check_warns_within_the_company_only(db: PgPool) {
    let app = setup(db.clone()).await;
    let buyer = add_buyer(&db).await;
    let (status, s) = send(
        &app,
        ADMIN,
        Method::POST,
        "/suppliers",
        supplier("Acme Supplies", "BE", Some(GOOD_BE)),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{s}");
    let id = s["id"].as_str().unwrap().to_string();

    // Another company has a supplier with the same number: not this company's business.
    let other = Uuid::now_v7();
    sqlx::query("INSERT INTO core.companies (id, name) VALUES ($1, 'Other BV')")
        .bind(other)
        .execute(&db)
        .await
        .unwrap();
    sqlx::query("INSERT INTO purchasing.suppliers (id, company_id, name, country, tax_id) VALUES ($1, $2, 'Elsewhere', 'BE', $3)")
        .bind(Uuid::now_v7())
        .bind(other)
        .bind(GOOD_BE)
        .execute(&db)
        .await
        .unwrap();

    let (status, c) = get(
        &app,
        buyer,
        &format!("/suppliers/vat-check?vat_number={GOOD_BE}"),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{c}");
    assert_eq!(c["status"], "valid");
    assert_eq!(c["duplicates"].as_array().unwrap().len(), 1, "{c}");
    assert_eq!(c["duplicates"][0]["id"], id.as_str());
    assert_eq!(c["duplicates"][0]["name"], "Acme Supplies");

    // Spelled differently, without prefix for a supplier in that country; excluded when editing it.
    let (_, c) = get(
        &app,
        buyer,
        "/suppliers/vat-check?vat_number=0428.759.497&country_code=BE",
    )
    .await;
    assert_eq!(c["duplicates"][0]["id"], id.as_str());
    let (_, c) = get(
        &app,
        buyer,
        &format!("/suppliers/vat-check?vat_number={GOOD_BE}&exclude_id={id}"),
    )
    .await;
    assert_eq!(c["duplicates"].as_array().unwrap().len(), 0);

    // Permissions: the viewer may check, only a purchaser or admin may ask VIES; sales sees no
    // suppliers at all.
    assert_eq!(
        get(&app, VIEWER, "/suppliers/vat-check?vat_number=BE0428759497")
            .await
            .0,
        StatusCode::OK
    );
    assert_eq!(
        get(
            &app,
            VIEWER,
            "/suppliers/vat-check?vat_number=BE0428759497&lookup=true"
        )
        .await
        .0,
        StatusCode::FORBIDDEN
    );
    assert_eq!(
        get(&app, SALES, "/suppliers/vat-check?vat_number=BE0428759497")
            .await
            .0,
        StatusCode::FORBIDDEN
    );
    let (status, c) = get(
        &app,
        buyer,
        "/suppliers/vat-check?vat_number=BE0428759497&lookup=true",
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{c}");
    assert_eq!(c["vies"]["reason"], "disabled");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_supplier_lookup_uses_the_same_service(db: PgPool) {
    let vies = vies_stand_in().await;
    let app = setup_with_vies(db.clone(), ViesConfig::new(&vies.url)).await;
    let (status, c) = get(
        &app,
        ADMIN,
        "/suppliers/vat-check?vat_number=BE0428759497&lookup=true",
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{c}");
    assert_eq!(c["vies"]["state"], "valid");
    assert_eq!(c["vies"]["name"], "ACME NV");
    assert_eq!(c["vies"]["city"], "BRUXELLES");
}
