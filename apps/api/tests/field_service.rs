//! Field service completion: customer signature, parts used, installed base and warranty, the
//! service report, and maintenance contracts that generate planned jobs.

mod common;

use axum::http::{Method, StatusCode};
use chrono::NaiveDate;
use common::{call, jpeg, raw, setup, Who};
use serde_json::{json, Value};
use sqlx::PgPool;
use tradocraft_fieldservice::contracts::generate_due_visits;

const ALPHA: &str = "00000000-0000-7000-8000-000000000401";
const BETA: &str = "00000000-0000-7000-8000-000000000402";
const SOFIE: &str = "00000000-0000-7000-8000-000000000602";
const TOM: &str = "00000000-0000-7000-8000-000000000107";
const PUMP: &str = "00000000-0000-7000-8000-000000000303";
const COMPANY: &str = "00000000-0000-7000-8000-000000000001";
const DISPATCHER: &str = "dispatcher@example.com";
const TECH: &str = "technician@example.com";
const TECH2: &str = "tech2@example.com";
const ADMIN: &str = "admin@example.com";
const VIEWER: &str = "viewer@example.com";

const PNG: [u8; 70] = [
    0x89, 0x50, 0x4e, 0x47, 0xd, 0xa, 0x1a, 0xa, 0x0, 0x0, 0x0, 0xd, 0x49, 0x48, 0x44, 0x52, 0x0,
    0x0, 0x0, 0x1, 0x0, 0x0, 0x0, 0x1, 0x8, 0x6, 0x0, 0x0, 0x0, 0x1f, 0x15, 0xc4, 0x89, 0x0, 0x0,
    0x0, 0xd, 0x49, 0x44, 0x41, 0x54, 0x78, 0xda, 0x63, 0x64, 0x60, 0xf8, 0x5f, 0xf, 0x0, 0x2,
    0x87, 0x1, 0x80, 0xeb, 0x47, 0xba, 0x92, 0x0, 0x0, 0x0, 0x0, 0x49, 0x45, 0x4e, 0x44, 0xae,
    0x42, 0x60, 0x82,
];

fn png_variant(tag: u8) -> Vec<u8> {
    let mut v = PNG.to_vec();
    v.extend([tag; 4]);
    v
}

async fn post(app: &axum::Router, user: &str, uri: &str, body: Value) -> (StatusCode, Value) {
    call(app, user, Method::POST, uri, Some(body)).await
}
async fn put(app: &axum::Router, user: &str, uri: &str, body: Value) -> (StatusCode, Value) {
    call(app, user, Method::PUT, uri, Some(body)).await
}
async fn get(app: &axum::Router, user: &str, uri: &str) -> (StatusCode, Value) {
    call(app, user, Method::GET, uri, None).await
}
async fn delete(app: &axum::Router, user: &str, uri: &str) -> (StatusCode, Value) {
    call(app, user, Method::DELETE, uri, None).await
}

async fn second_technician(db: &PgPool) {
    let id = uuid::Uuid::now_v7();
    sqlx::query(
        "INSERT INTO core.users (id, email, display_name) VALUES ($1, $2, 'Tina Technician')",
    )
    .bind(id)
    .bind(TECH2)
    .execute(db)
    .await
    .unwrap();
    sqlx::query("INSERT INTO core.user_companies (user_id, company_id, roles, is_default) VALUES ($1, $2::uuid, '{technician}', true)")
        .bind(id)
        .bind(COMPANY)
        .execute(db)
        .await
        .unwrap();
}

async fn plan(app: &axum::Router, extra: Value) -> Value {
    let mut body = json!({
        "title": "Service pump station", "kind": "maintenance", "customer_id": ALPHA, "contact_id": SOFIE,
        "instructions": "INTERNAL-INSTRUCTION do not print", "technician_ids": [TOM],
        "tasks": ["Isolate the pump", "Replace seals"]
    });
    body.as_object().unwrap();
    body.as_object_mut()
        .unwrap()
        .extend(extra.as_object().unwrap().clone());
    let (status, j) = post(app, DISPATCHER, "/api/v1/field/jobs", body).await;
    assert_eq!(status, StatusCode::CREATED, "{j}");
    j
}

fn jid(j: &Value) -> String {
    j["job"]["id"].as_str().unwrap().to_string()
}

/// Plans a job and starts it as Tom.
async fn started(app: &axum::Router) -> String {
    let id = jid(&plan(app, json!({})).await);
    let (s, _) = post(
        app,
        TECH,
        &format!("/api/v1/field/jobs/{id}/start"),
        json!({}),
    )
    .await;
    assert_eq!(s, StatusCode::OK);
    id
}

async fn unit(db: &PgPool, serial: &str, customer: Option<&str>, status: &str) -> String {
    let id = uuid::Uuid::now_v7();
    sqlx::query(
        "INSERT INTO engineering.serial_units (id, company_id, product_id, serial_number, status, customer_id, created_by)
         VALUES ($1, $2::uuid, $3::uuid, $4, $5, $6::uuid, '00000000-0000-7000-8000-000000000101')",
    )
    .bind(id)
    .bind(COMPANY)
    .bind(uuid::Uuid::parse_str(PUMP).unwrap())
    .bind(serial)
    .bind(status)
    .bind(customer)
    .execute(db)
    .await
    .unwrap();
    id.to_string()
}

async fn sign(app: &axum::Router, user: &str, id: &str, name: &str, png: Vec<u8>) -> StatusCode {
    raw(
        app,
        Who::Staff(user),
        Method::POST,
        &format!("/api/v1/field/jobs/{id}/signature?signer_name={name}"),
        Some(("image/png", png)),
    )
    .await
    .0
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_customer_signs_declines_or_replaces_until_the_report_is_sent(db: PgPool) {
    let app = setup(db.clone()).await;
    second_technician(&db).await;
    let id = jid(&plan(&app, json!({})).await);
    assert_eq!(
        sign(&app, TECH, &id, "Sofie", PNG.to_vec()).await,
        StatusCode::CONFLICT,
        "not started"
    );
    post(
        &app,
        TECH,
        &format!("/api/v1/field/jobs/{id}/start"),
        json!({}),
    )
    .await;

    // Validation: a name, a PNG.
    assert_eq!(
        sign(&app, TECH, &id, "%20", PNG.to_vec()).await,
        StatusCode::UNPROCESSABLE_ENTITY
    );
    assert_eq!(
        sign(&app, TECH, &id, "Sofie", jpeg(1)).await,
        StatusCode::UNPROCESSABLE_ENTITY
    );
    assert_eq!(
        sign(&app, TECH2, &id, "Sofie", PNG.to_vec()).await,
        StatusCode::NOT_FOUND,
        "not their job"
    );
    assert_eq!(
        sign(&app, VIEWER, &id, "Sofie", PNG.to_vec()).await,
        StatusCode::FORBIDDEN
    );

    assert_eq!(
        sign(&app, TECH, &id, "Sofie%20Maes", PNG.to_vec()).await,
        StatusCode::CREATED
    );
    let (_, d) = get(&app, TECH, &format!("/api/v1/field/jobs/{id}")).await;
    assert_eq!(d["signature"]["signer_name"], "Sofie Maes");
    assert_eq!(d["signature"]["has_image"], true);
    assert_eq!(d["signature"]["declined"], false);
    let (s, _, bytes) = raw(
        &app,
        Who::Staff(TECH),
        Method::GET,
        &format!("/api/v1/field/jobs/{id}/signature"),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::OK);
    assert_eq!(bytes, PNG.to_vec());

    // Completing keeps it; replacing swaps the image and removes the old file.
    post(
        &app,
        TECH,
        &format!("/api/v1/field/jobs/{id}/complete"),
        json!({ "notes": "Done" }),
    )
    .await;
    assert_eq!(
        sign(&app, TECH, &id, "Sofie%20Maes", png_variant(7)).await,
        StatusCode::CREATED
    );
    let files: i64 =
        sqlx::query_scalar("SELECT count(*) FROM core.files WHERE filename = 'signature.png'")
            .fetch_one(&db)
            .await
            .unwrap();
    assert_eq!(files, 1, "one signature per job");
    let sigs: i64 = sqlx::query_scalar("SELECT count(*) FROM field.job_signatures")
        .fetch_one(&db)
        .await
        .unwrap();
    assert_eq!(sigs, 1);

    // Declined: needs a reason, replaces the image.
    let (s, _) = post(
        &app,
        TECH,
        &format!("/api/v1/field/jobs/{id}/signature/declined"),
        json!({ "reason": " " }),
    )
    .await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);
    let (s, d) = post(
        &app,
        TECH,
        &format!("/api/v1/field/jobs/{id}/signature/declined"),
        json!({ "reason": "No time", "signer_name": "Sofie" }),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED, "{d}");
    assert_eq!(d["signature"]["declined"], true);
    assert_eq!(d["signature"]["has_image"], false);
    assert_eq!(d["signature"]["decline_reason"], "No time");
    let (s, _, _) = raw(
        &app,
        Who::Staff(TECH),
        Method::GET,
        &format!("/api/v1/field/jobs/{id}/signature"),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::NOT_FOUND);
    let files: i64 =
        sqlx::query_scalar("SELECT count(*) FROM core.files WHERE filename = 'signature.png'")
            .fetch_one(&db)
            .await
            .unwrap();
    assert_eq!(files, 0);

    // Signing after all, then sending the report locks the signature.
    assert_eq!(
        sign(&app, TECH, &id, "Sofie%20Maes", PNG.to_vec()).await,
        StatusCode::CREATED
    );
    let (s, d) = post(
        &app,
        TECH,
        &format!("/api/v1/field/jobs/{id}/report/send"),
        json!({}),
    )
    .await;
    assert_eq!(s, StatusCode::OK, "{d}");
    assert_eq!(
        sign(&app, TECH, &id, "Sofie%20Maes", png_variant(9)).await,
        StatusCode::CONFLICT
    );
    let (s, _) = post(
        &app,
        DISPATCHER,
        &format!("/api/v1/field/jobs/{id}/signature/declined"),
        json!({ "reason": "x" }),
    )
    .await;
    assert_eq!(s, StatusCode::CONFLICT);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn parts_are_recorded_once_and_only_by_the_technician_of_the_job(db: PgPool) {
    let app = setup(db.clone()).await;
    second_technician(&db).await;
    let id = started(&app).await;
    let uri = format!("/api/v1/field/jobs/{id}/parts");
    let part_id = "00000000-0000-7000-8000-00000000aaa1";

    let body = json!({ "id": part_id, "product_id": PUMP, "quantity": "2", "billable": false });
    let (s, d) = post(&app, TECH, &uri, body.clone()).await;
    assert_eq!(s, StatusCode::CREATED, "{d}");
    let (s, d) = post(&app, TECH, &uri, body.clone()).await;
    assert_eq!(s, StatusCode::CREATED, "a retry is fine");
    assert_eq!(d["parts"].as_array().unwrap().len(), 1, "no duplicate");
    let part = &d["parts"][0];
    assert_eq!(part["unit"], "pcs");
    assert_eq!(part["billable"], false);
    assert!(
        !part["description"].as_str().unwrap().is_empty(),
        "defaults to the product name"
    );
    assert_eq!(part["added_by_name"], "Tom Technician");

    // Free text with a serial unit; validation.
    let su = unit(&db, "P-9001", Some(ALPHA), "installed").await;
    let (s, d) = post(&app, TECH, &uri, json!({ "description": "Gasket 40 mm", "quantity": "1.5", "unit": "m", "serial_unit_id": su })).await;
    assert_eq!(s, StatusCode::CREATED, "{d}");
    assert_eq!(d["parts"].as_array().unwrap().len(), 2);
    for bad in [
        json!({ "description": "x", "quantity": "0" }),
        json!({ "description": "x", "quantity": "-1" }),
        json!({ "description": " ", "quantity": "1" }),
        json!({ "quantity": "1", "product_id": "00000000-0000-7000-8000-0000000000aa" }),
    ] {
        assert_eq!(
            post(&app, TECH, &uri, bad).await.0,
            StatusCode::UNPROCESSABLE_ENTITY
        );
    }
    // The same id on another job is refused.
    let other = jid(&plan(&app, json!({})).await);
    post(
        &app,
        TECH,
        &format!("/api/v1/field/jobs/{other}/start"),
        json!({}),
    )
    .await;
    assert_eq!(
        post(
            &app,
            TECH,
            &format!("/api/v1/field/jobs/{other}/parts"),
            body
        )
        .await
        .0,
        StatusCode::CONFLICT
    );

    // Permissions.
    let ok = json!({ "description": "x", "quantity": "1" });
    assert_eq!(
        post(&app, TECH2, &uri, ok.clone()).await.0,
        StatusCode::NOT_FOUND,
        "not their job"
    );
    assert_eq!(
        post(&app, VIEWER, &uri, ok.clone()).await.0,
        StatusCode::FORBIDDEN
    );
    assert_eq!(
        delete(&app, TECH2, &format!("{uri}/{part_id}")).await.0,
        StatusCode::NOT_FOUND
    );

    // Removing, twice is harmless.
    let (s, d) = delete(&app, TECH, &format!("{uri}/{part_id}")).await;
    assert_eq!(s, StatusCode::OK);
    assert_eq!(d["parts"].as_array().unwrap().len(), 1);
    assert_eq!(
        delete(&app, TECH, &format!("{uri}/{part_id}")).await.0,
        StatusCode::OK
    );

    // After completion only a planner may change parts.
    post(
        &app,
        TECH,
        &format!("/api/v1/field/jobs/{id}/complete"),
        json!({ "notes": "Done" }),
    )
    .await;
    assert_eq!(
        post(&app, TECH, &uri, ok.clone()).await.0,
        StatusCode::CONFLICT
    );
    assert_eq!(
        post(&app, DISPATCHER, &uri, ok.clone()).await.0,
        StatusCode::CREATED
    );
    post(
        &app,
        DISPATCHER,
        &format!("/api/v1/field/jobs/{id}/cancel"),
        json!({}),
    )
    .await;
    // (a completed job cannot be cancelled: still completed)
    let (_, d) = get(&app, DISPATCHER, &format!("/api/v1/field/jobs/{id}")).await;
    assert_eq!(d["job"]["status"], "completed");
    // No stock is touched: nothing outside field.job_parts changes.
    let moves: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM information_schema.schemata WHERE schema_name = 'inventory'",
    )
    .fetch_one(&db)
    .await
    .unwrap();
    assert!(moves == 0 || moves == 1);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn equipment_must_belong_to_the_customer_and_shows_its_warranty(db: PgPool) {
    let app = setup(db.clone()).await;
    let id = started(&app).await;
    let uri = format!("/api/v1/field/jobs/{id}/equipment");
    let mine = unit(&db, "P-8001", Some(ALPHA), "installed").await;
    let old = unit(&db, "P-8002", Some(ALPHA), "delivered").await;
    let theirs = unit(&db, "P-8003", Some(BETA), "installed").await;
    let nobody = unit(&db, "P-8004", None, "in_stock").await;

    assert_eq!(
        post(&app, TECH, &uri, json!({ "serial_unit_id": theirs }))
            .await
            .0,
        StatusCode::CONFLICT
    );
    assert_eq!(
        post(&app, TECH, &uri, json!({ "serial_unit_id": nobody }))
            .await
            .0,
        StatusCode::CONFLICT
    );
    assert_eq!(
        post(
            &app,
            TECH,
            &uri,
            json!({ "serial_unit_id": "00000000-0000-7000-8000-0000000000aa" })
        )
        .await
        .0,
        StatusCode::NOT_FOUND
    );

    // Warranty: set by someone who may edit serial units.
    assert_eq!(
        put(
            &app,
            TECH,
            &format!("/api/v1/serials/{mine}/warranty"),
            json!({ "warranty_until": "2099-01-01" })
        )
        .await
        .0,
        StatusCode::FORBIDDEN
    );
    let (s, d) = put(
        &app,
        ADMIN,
        &format!("/api/v1/serials/{mine}/warranty"),
        json!({ "warranty_until": "2099-01-01T00:00:00.000", "warranty_note": "5 years" }),
    )
    .await;
    assert_eq!(s, StatusCode::OK, "{d}");
    assert_eq!(d["unit"]["warranty_status"], "in_warranty");
    put(
        &app,
        ADMIN,
        &format!("/api/v1/serials/{old}/warranty"),
        json!({ "warranty_until": "2020-01-01" }),
    )
    .await;

    assert_eq!(
        post(&app, TECH, &uri, json!({ "serial_unit_id": mine }))
            .await
            .0,
        StatusCode::CREATED
    );
    let (s, d) = post(&app, TECH, &uri, json!({ "serial_unit_id": mine })).await;
    assert_eq!(s, StatusCode::CREATED);
    assert_eq!(
        d["equipment"].as_array().unwrap().len(),
        1,
        "linking twice changes nothing"
    );
    let (_, d) = post(&app, TECH, &uri, json!({ "serial_unit_id": old })).await;
    let eq = d["equipment"].as_array().unwrap();
    let status_of = |serial: &str| {
        eq.iter().find(|e| e["serial_number"] == serial).unwrap()["warranty_status"].clone()
    };
    assert_eq!(status_of("P-8001"), "in_warranty");
    assert_eq!(status_of("P-8002"), "expired");

    // Unknown warranty.
    let (_, d) = get(&app, ADMIN, &format!("/api/v1/serials/{nobody}")).await;
    assert_eq!(d["unit"]["warranty_status"], "unknown");

    // The customer's installed units with their job history.
    post(
        &app,
        TECH,
        &format!("/api/v1/field/jobs/{id}/complete"),
        json!({ "notes": "Done" }),
    )
    .await;
    let (s, list) = get(
        &app,
        DISPATCHER,
        &format!("/api/v1/field/customers/{ALPHA}/equipment"),
    )
    .await;
    assert_eq!(s, StatusCode::OK, "{list}");
    let list = list.as_array().unwrap();
    assert!(
        list.iter().all(|u| u["serial_number"] != "P-8004"),
        "in stock units are not installed"
    );
    let u = list
        .iter()
        .find(|u| u["serial_number"] == "P-8001")
        .unwrap();
    assert_eq!(u["warranty_status"], "in_warranty");
    assert_eq!(u["jobs"][0]["id"], id.as_str());
    let (_, beta) = get(
        &app,
        DISPATCHER,
        &format!("/api/v1/field/customers/{BETA}/equipment"),
    )
    .await;
    assert_eq!(beta.as_array().unwrap().len(), 1);
    assert_eq!(beta[0]["jobs"].as_array().unwrap().len(), 0);

    // Completed: only planners change the equipment; removing works.
    assert_eq!(
        delete(&app, TECH, &format!("{uri}/{old}")).await.0,
        StatusCode::CONFLICT
    );
    let (s, d) = delete(&app, DISPATCHER, &format!("{uri}/{old}")).await;
    assert_eq!(s, StatusCode::OK);
    assert_eq!(d["equipment"].as_array().unwrap().len(), 1);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_service_report_is_a_pdf_in_five_languages_and_can_be_mailed(db: PgPool) {
    let (app, blobs) = common::setup_with_blobs(db.clone()).await;
    let id = started(&app).await;
    let base = format!("/api/v1/field/jobs/{id}");
    let su = unit(&db, "P-7001", Some(ALPHA), "installed").await;
    post(
        &app,
        TECH,
        &format!("{base}/equipment"),
        json!({ "serial_unit_id": su }),
    )
    .await;
    post(
        &app,
        TECH,
        &format!("{base}/parts"),
        json!({ "description": "Seal kit", "quantity": "1" }),
    )
    .await;
    raw(
        &app,
        Who::Staff(TECH),
        Method::POST,
        &format!("{base}/photos?caption=Before"),
        Some(("image/jpeg", jpeg(1))),
    )
    .await;
    sign(&app, TECH, &id, "Sofie%20Maes", PNG.to_vec()).await;

    // Not completed yet: a draft is available, mailing is not.
    assert_eq!(
        post(&app, TECH, &format!("{base}/report/send"), json!({}))
            .await
            .0,
        StatusCode::CONFLICT
    );
    for lang in ["nl", "fr", "en", "de", "es"] {
        let (s, h, bytes) = raw(
            &app,
            Who::Staff(DISPATCHER),
            Method::GET,
            &format!("{base}/report?language={lang}"),
            None,
        )
        .await;
        assert_eq!(
            s,
            StatusCode::OK,
            "{lang}: {}",
            String::from_utf8_lossy(&bytes)
        );
        assert!(bytes.starts_with(b"%PDF"), "{lang}");
        assert_eq!(h["content-type"], "application/pdf");
    }
    let (s, _, _) = raw(
        &app,
        Who::Staff(DISPATCHER),
        Method::GET,
        &format!("{base}/report?language=xx"),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);
    let (s, _, _) = raw(
        &app,
        Who::Staff("tech2@example.com"),
        Method::GET,
        &format!("{base}/report"),
        None,
    )
    .await;
    assert_ne!(s, StatusCode::OK);

    post(
        &app,
        TECH,
        &format!("{base}/complete"),
        json!({ "notes": "Seals replaced" }),
    )
    .await;
    let (s, d) = post(&app, TECH, &format!("{base}/report/send"), json!({})).await;
    assert_eq!(s, StatusCode::OK, "{d}");
    assert_eq!(d["job"]["report_sent_to"], "sofie.maes@alpha.example");
    assert!(d["job"]["report_sent_at"].is_string());
    let (to, subject, name, kind, storage_key): (String, String, Option<String>, Option<String>, Option<String>) = sqlx::query_as(
        "SELECT to_address, subject, attachment_name, attachment_type, attachment_storage_key FROM core.mail_outbox ORDER BY created_at DESC LIMIT 1",
    )
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(to, "sofie.maes@alpha.example");
    assert!(subject.contains("Werkbon"), "{subject}");
    assert_eq!(kind.as_deref(), Some("application/pdf"));
    assert!(name.unwrap().ends_with("-service-report.pdf"));
    let pdf_bytes = blobs.get(&storage_key.unwrap()).await.unwrap();
    assert!(pdf_bytes.len() > 1000);

    // No address: no contact, and the customer has none.
    sqlx::query("UPDATE crm.customers SET email = NULL WHERE id = $1::uuid")
        .bind(BETA)
        .execute(&db)
        .await
        .unwrap();
    let j = plan(&app, json!({ "customer_id": BETA, "contact_id": null })).await;
    let other = jid(&j);
    post(
        &app,
        DISPATCHER,
        &format!("/api/v1/field/jobs/{other}/start"),
        json!({}),
    )
    .await;
    post(
        &app,
        DISPATCHER,
        &format!("/api/v1/field/jobs/{other}/complete"),
        json!({ "notes": "Done" }),
    )
    .await;
    let (s, e) = post(
        &app,
        DISPATCHER,
        &format!("/api/v1/field/jobs/{other}/report/send"),
        json!({}),
    )
    .await;
    assert_eq!(s, StatusCode::CONFLICT, "{e}");
    let (s, _, bytes) = raw(
        &app,
        Who::Staff(DISPATCHER),
        Method::GET,
        &format!("/api/v1/field/jobs/{other}/report"),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::OK);
    assert!(bytes.starts_with(b"%PDF"));
}

fn date(y: i32, m: u32, d: u32) -> NaiveDate {
    NaiveDate::from_ymd_opt(y, m, d).unwrap()
}

fn contract_body(extra: Value) -> Value {
    let mut b = json!({
        "customer_id": ALPHA, "title": "Pump maintenance", "start_date": "2027-01-01", "end_date": "2027-12-31",
        "response_hours": 4, "resolution_hours": 48,
        "visit_templates": [{
            "title": "Quarterly service", "kind": "maintenance", "instructions": "Check seals",
            "tasks": ["Isolate", "Inspect", " "], "recurrence": "months", "interval_n": 3,
            "anchor_date": "2027-03-31T00:00:00.000", "lead_days": 14, "technician_ids": [TOM], "estimated_minutes": 90
        }]
    });
    b.as_object_mut()
        .unwrap()
        .extend(extra.as_object().unwrap().clone());
    b
}

async fn new_contract(app: &axum::Router, extra: Value) -> Value {
    let (s, c) = post(
        app,
        DISPATCHER,
        "/api/v1/field/contracts",
        contract_body(extra),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED, "{c}");
    c
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_contract_goes_from_draft_to_active_suspended_and_ended(db: PgPool) {
    let app = setup(db.clone()).await;
    let su = unit(&db, "P-6001", Some(ALPHA), "installed").await;
    let c = new_contract(&app, json!({ "equipment_ids": [su] })).await;
    let id = c["id"].as_str().unwrap();
    assert!(c["number"].as_str().unwrap().starts_with("SC"));
    assert_eq!(c["status"], "draft");
    assert_eq!(c["customer_name"], "Alpha Installaties NV");
    assert_eq!(c["equipment"][0]["serial_number"], "P-6001");
    assert_eq!(
        c["visit_templates"][0]["tasks"],
        json!(["Isolate", "Inspect"])
    );
    assert_eq!(
        c["visit_templates"][0]["technicians"][0]["display_name"],
        "Tom Technician"
    );

    // Validation and permissions.
    for (patch, what) in [
        (json!({ "title": " " }), "title"),
        (json!({ "end_date": "2026-01-01" }), "ends before start"),
        (json!({ "response_hours": 0 }), "hours"),
        (
            json!({ "equipment_ids": [unit(&db, "B-1", Some(BETA), "installed").await] }),
            "other customer's unit",
        ),
        (
            json!({ "visit_templates": [{ "title": "x", "recurrence": "months_list", "months": [] }] }),
            "no months",
        ),
        (
            json!({ "visit_templates": [{ "title": "x", "recurrence": "months", "interval_n": 0 }] }),
            "interval",
        ),
        (
            json!({ "visit_templates": [{ "title": "x", "recurrence": "daily" }] }),
            "recurrence",
        ),
    ] {
        let (s, e) = post(
            &app,
            DISPATCHER,
            "/api/v1/field/contracts",
            contract_body(patch),
        )
        .await;
        assert!(
            s == StatusCode::UNPROCESSABLE_ENTITY || s == StatusCode::CONFLICT,
            "{what}: {s} {e}"
        );
    }
    assert_eq!(
        post(
            &app,
            TECH,
            "/api/v1/field/contracts",
            contract_body(json!({}))
        )
        .await
        .0,
        StatusCode::FORBIDDEN
    );
    assert_eq!(
        get(&app, VIEWER, "/api/v1/field/contracts").await.0,
        StatusCode::OK
    );

    // Change it: the template keeps its id, a second one appears.
    let tpl = c["visit_templates"][0]["id"].clone();
    let mut body = contract_body(json!({ "notes": "Gate code 1234", "equipment_ids": [su] }));
    body["visit_templates"] = json!([
        { "id": tpl, "title": "Quarterly service", "recurrence": "months", "interval_n": 3, "anchor_date": "2027-03-31" },
        { "title": "Yearly inspection", "kind": "inspection", "recurrence": "months_list", "months": [9, 3], "anchor_date": "2027-03-15" }
    ]);
    let (s, c2) = put(
        &app,
        DISPATCHER,
        &format!("/api/v1/field/contracts/{id}"),
        body,
    )
    .await;
    assert_eq!(s, StatusCode::OK, "{c2}");
    assert_eq!(c2["visit_templates"][0]["id"], tpl);
    assert_eq!(c2["visit_templates"].as_array().unwrap().len(), 2);
    assert_eq!(c2["notes"], "Gate code 1234");

    // Upcoming visits: month-end clamping, from the start date on.
    let (s, up) = get(
        &app,
        DISPATCHER,
        &format!("/api/v1/field/contracts/{id}/upcoming?until=2027-12-31"),
    )
    .await;
    assert_eq!(s, StatusCode::OK, "{up}");
    let dates: Vec<&str> = up
        .as_array()
        .unwrap()
        .iter()
        .map(|v| v["due_date"].as_str().unwrap())
        .collect();
    assert_eq!(
        dates,
        [
            "2027-03-15",
            "2027-03-31",
            "2027-06-30",
            "2027-09-15",
            "2027-09-30",
            "2027-12-31"
        ]
    );
    assert_eq!(up[1]["generate_on"], "2027-03-17");
    assert!(up[0]["job_id"].is_null());

    // Lifecycle.
    let act = |what: &'static str| format!("/api/v1/field/contracts/{id}/{what}");
    assert_eq!(
        post(&app, DISPATCHER, &act("suspend"), json!({})).await.0,
        StatusCode::CONFLICT,
        "draft"
    );
    assert_eq!(
        post(&app, TECH, &act("activate"), json!({})).await.0,
        StatusCode::FORBIDDEN
    );
    let (s, a) = post(&app, DISPATCHER, &act("activate"), json!({})).await;
    assert_eq!((s, a["status"].as_str()), (StatusCode::OK, Some("active")));
    assert_eq!(
        post(&app, DISPATCHER, &act("activate"), json!({})).await.0,
        StatusCode::CONFLICT
    );
    let (_, a) = post(&app, DISPATCHER, &act("suspend"), json!({})).await;
    assert_eq!(a["status"], "suspended");
    let (_, a) = post(&app, DISPATCHER, &act("activate"), json!({})).await;
    assert_eq!(a["status"], "active");
    let (_, a) = post(&app, DISPATCHER, &act("end"), json!({})).await;
    assert_eq!(a["status"], "ended");
    assert_eq!(
        put(
            &app,
            DISPATCHER,
            &format!("/api/v1/field/contracts/{id}"),
            contract_body(json!({}))
        )
        .await
        .0,
        StatusCode::CONFLICT
    );
    assert_eq!(
        post(&app, DISPATCHER, &act("activate"), json!({})).await.0,
        StatusCode::CONFLICT
    );

    let (_, list) = get(&app, DISPATCHER, "/api/v1/field/contracts?status=ended").await;
    assert_eq!(list.as_array().unwrap().len(), 1);
    let (_, list) = get(&app, DISPATCHER, "/api/v1/field/contracts?status=active").await;
    assert_eq!(list.as_array().unwrap().len(), 0);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_worker_generates_each_visit_once_and_only_for_active_contracts(db: PgPool) {
    let app = setup(db.clone()).await;
    let su = unit(&db, "P-5001", Some(ALPHA), "installed").await;
    let c = new_contract(&app, json!({ "equipment_ids": [su] })).await;
    let id = c["id"].as_str().unwrap().to_string();
    let jobs = |app: &axum::Router| {
        let app = app.clone();
        let id = id.clone();
        async move {
            let (_, j) = get(
                &app,
                DISPATCHER,
                &format!("/api/v1/field/contracts/{id}/jobs"),
            )
            .await;
            j
        }
    };

    // A draft generates nothing.
    assert_eq!(
        generate_due_visits(&db, date(2027, 3, 20))
            .await
            .unwrap()
            .jobs,
        0
    );
    post(
        &app,
        DISPATCHER,
        &format!("/api/v1/field/contracts/{id}/activate"),
        json!({}),
    )
    .await;

    // Due on 31 March, generated 14 days ahead: not on 16 March, yes on 17 March.
    assert_eq!(
        generate_due_visits(&db, date(2027, 3, 16))
            .await
            .unwrap()
            .jobs,
        0
    );
    assert_eq!(
        generate_due_visits(&db, date(2027, 3, 17))
            .await
            .unwrap()
            .jobs,
        1
    );
    assert_eq!(
        generate_due_visits(&db, date(2027, 3, 17))
            .await
            .unwrap()
            .jobs,
        0,
        "idempotent"
    );
    assert_eq!(
        generate_due_visits(&db, date(2027, 3, 25))
            .await
            .unwrap()
            .jobs,
        0
    );
    let j = jobs(&app).await;
    assert_eq!(j.as_array().unwrap().len(), 1);
    let job = &j[0];
    assert_eq!(job["status"], "planned");
    assert_eq!(job["title"], "Quarterly service");
    assert_eq!(job["priority"], "urgent", "response target of 4 hours");
    assert_eq!(job["due_date"], "2027-03-31");
    assert_eq!(job["contract_id"], id.as_str());
    assert!(job["contract_number"].as_str().unwrap().starts_with("SC"));
    assert_eq!(job["address"], "Havenlaan 10, 2000 Antwerpen");
    assert_eq!(job["technicians"][0]["display_name"], "Tom Technician");
    let (_, d) = get(
        &app,
        DISPATCHER,
        &format!("/api/v1/field/jobs/{}", job["id"].as_str().unwrap()),
    )
    .await;
    assert_eq!(d["tasks"].as_array().unwrap().len(), 2);
    assert_eq!(d["equipment"][0]["serial_number"], "P-5001");
    assert!(d["job"]["instructions"]
        .as_str()
        .unwrap()
        .contains("Check seals"));
    let audited: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM audit.events WHERE entity = 'job' AND action = 'generated'",
    )
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(audited, 1);
    // The preview shows it as generated.
    let (_, up) = get(
        &app,
        DISPATCHER,
        &format!("/api/v1/field/contracts/{id}/upcoming?until=2027-04-30"),
    )
    .await;
    assert_eq!(up[0]["job_number"], job["number"]);

    // Suspended: nothing, even when due. Resumed shortly after: the late visit is caught up.
    post(
        &app,
        DISPATCHER,
        &format!("/api/v1/field/contracts/{id}/suspend"),
        json!({}),
    )
    .await;
    assert_eq!(
        generate_due_visits(&db, date(2027, 6, 20))
            .await
            .unwrap()
            .jobs,
        0
    );
    post(
        &app,
        DISPATCHER,
        &format!("/api/v1/field/contracts/{id}/activate"),
        json!({}),
    )
    .await;
    assert_eq!(
        generate_due_visits(&db, date(2027, 7, 2))
            .await
            .unwrap()
            .jobs,
        1,
        "due 30 June, a week of grace"
    );
    // Long overdue visits are not conjured up.
    assert_eq!(
        generate_due_visits(&db, date(2027, 7, 20))
            .await
            .unwrap()
            .jobs,
        0
    );

    // Never after the end date: the last visit of the year is 31 December, ended on 15 December.
    sqlx::query("UPDATE field.contracts SET end_date = '2027-12-15' WHERE id = $1::uuid")
        .bind(&id)
        .execute(&db)
        .await
        .unwrap();
    assert_eq!(
        generate_due_visits(&db, date(2027, 12, 20))
            .await
            .unwrap()
            .jobs,
        0
    );
    // Ended: nothing either.
    sqlx::query("UPDATE field.contracts SET end_date = '2027-12-31' WHERE id = $1::uuid")
        .bind(&id)
        .execute(&db)
        .await
        .unwrap();
    post(
        &app,
        DISPATCHER,
        &format!("/api/v1/field/contracts/{id}/end"),
        json!({}),
    )
    .await;
    assert_eq!(
        generate_due_visits(&db, date(2027, 12, 20))
            .await
            .unwrap()
            .jobs,
        0
    );
    assert_eq!(jobs(&app).await.as_array().unwrap().len(), 2);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn an_auto_renewing_contract_is_extended_before_it_ends(db: PgPool) {
    let app = setup(db.clone()).await;
    let c = new_contract(
        &app,
        json!({ "auto_renew": true, "end_date": "2027-03-01", "visit_templates": [] }),
    )
    .await;
    let id = c["id"].as_str().unwrap();
    post(
        &app,
        DISPATCHER,
        &format!("/api/v1/field/contracts/{id}/activate"),
        json!({}),
    )
    .await;
    assert_eq!(
        generate_due_visits(&db, date(2026, 12, 1))
            .await
            .unwrap()
            .renewed,
        0
    );
    assert_eq!(
        generate_due_visits(&db, date(2027, 2, 15))
            .await
            .unwrap()
            .renewed,
        1
    );
    let (_, c) = get(&app, DISPATCHER, &format!("/api/v1/field/contracts/{id}")).await;
    assert_eq!(c["end_date"], "2028-03-01");
    assert_eq!(
        generate_due_visits(&db, date(2027, 2, 16))
            .await
            .unwrap()
            .renewed,
        0
    );
}

// ---------------------------------------------------------------------------------------------
// Offline queue replays (ADR 0022): every technician write can be sent twice.
// ---------------------------------------------------------------------------------------------

async fn upload(app: &axum::Router, id: &str, client: &str, bytes: Vec<u8>) -> (StatusCode, Value) {
    let (s, _, body) = raw(
        app,
        Who::Staff(TECH),
        Method::POST,
        &format!("/api/v1/field/jobs/{id}/photos?client_id={client}&filename=a.jpg"),
        Some(("application/octet-stream", bytes)),
    )
    .await;
    (s, serde_json::from_slice(&body).unwrap_or(Value::Null))
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_replayed_task_is_added_once_and_another_description_is_a_conflict(db: PgPool) {
    let app = setup(db.clone()).await;
    let id = started(&app).await;
    let uri = format!("/api/v1/field/jobs/{id}/tasks");
    let cid = "00000000-0000-7000-8000-00000000bbb1";
    let body = json!({ "description": "Check the filter", "client_id": cid });
    let (s, first) = post(&app, TECH, &uri, body.clone()).await;
    assert_eq!(s, StatusCode::CREATED, "{first}");
    let (s, again) = post(&app, TECH, &uri, body).await;
    assert_eq!(s, StatusCode::CREATED);
    assert_eq!(again["tasks"], first["tasks"], "same result");
    assert_eq!(again["tasks"].as_array().unwrap().len(), 3, "2 planned + 1");
    let (s, e) = post(
        &app,
        TECH,
        &uri,
        json!({ "description": "Something else", "client_id": cid }),
    )
    .await;
    assert_eq!(s, StatusCode::CONFLICT, "{e}");
    // Without a client id nothing changes: every call adds a task.
    post(&app, TECH, &uri, json!({ "description": "Plain" })).await;
    let (_, d) = post(&app, TECH, &uri, json!({ "description": "Plain" })).await;
    assert_eq!(d["tasks"].as_array().unwrap().len(), 5);
    let n: i64 =
        sqlx::query_scalar("SELECT count(*) FROM field.job_tasks WHERE client_id = $1::uuid")
            .bind(cid)
            .fetch_one(&db)
            .await
            .unwrap();
    assert_eq!(n, 1);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_replayed_work_log_is_stored_once_and_other_content_is_a_conflict(db: PgPool) {
    let app = setup(db.clone()).await;
    let id = started(&app).await;
    let uri = format!("/api/v1/field/jobs/{id}/work-logs");
    let lid = "00000000-0000-7000-8000-00000000ccc1";
    let end = chrono::Utc::now() - chrono::Duration::minutes(10);
    let start = end - chrono::Duration::minutes(45);
    let body = json!({ "id": lid, "kind": "travel", "started_at": start, "ended_at": end, "notes": "Drive" });
    let (s, first) = post(&app, TECH, &uri, body.clone()).await;
    assert_eq!(s, StatusCode::CREATED, "{first}");
    let (s, again) = post(&app, TECH, &uri, body).await;
    assert_eq!(s, StatusCode::CREATED);
    assert_eq!(again["work_logs"], first["work_logs"]);
    assert_eq!(again["work_logs"].as_array().unwrap().len(), 1);
    assert_eq!(again["travel_minutes"], 45);
    let changed = json!({ "id": lid, "kind": "travel", "started_at": start, "ended_at": end, "notes": "Other" });
    assert_eq!(
        post(&app, TECH, &uri, changed).await.0,
        StatusCode::CONFLICT
    );
    let longer = json!({ "id": lid, "kind": "travel", "started_at": start - chrono::Duration::minutes(5), "ended_at": end, "notes": "Drive" });
    assert_eq!(post(&app, TECH, &uri, longer).await.0, StatusCode::CONFLICT);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_replayed_part_is_stored_once_and_other_content_is_a_conflict(db: PgPool) {
    let app = setup(db.clone()).await;
    let id = started(&app).await;
    let uri = format!("/api/v1/field/jobs/{id}/parts");
    let body = json!({ "id": "00000000-0000-7000-8000-00000000ddd1", "description": "Gasket", "quantity": "2" });
    let (s, first) = post(&app, TECH, &uri, body.clone()).await;
    assert_eq!(s, StatusCode::CREATED, "{first}");
    let (s, again) = post(&app, TECH, &uri, body.clone()).await;
    assert_eq!(s, StatusCode::CREATED);
    assert_eq!(again["parts"], first["parts"]);
    assert_eq!(again["parts"].as_array().unwrap().len(), 1);
    let mut other = body.clone();
    other["quantity"] = json!("3");
    assert_eq!(post(&app, TECH, &uri, other).await.0, StatusCode::CONFLICT);
    let mut other = body;
    other["description"] = json!("Seal");
    assert_eq!(post(&app, TECH, &uri, other).await.0, StatusCode::CONFLICT);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_replayed_photo_is_stored_once_and_another_picture_is_a_conflict(db: PgPool) {
    let app = setup(db.clone()).await;
    let id = started(&app).await;
    let cid = "00000000-0000-7000-8000-00000000eee1";
    let (s, first) = upload(&app, &id, cid, jpeg(1)).await;
    assert_eq!(s, StatusCode::CREATED, "{first}");
    let (s, again) = upload(&app, &id, cid, jpeg(1)).await;
    assert_eq!(s, StatusCode::CREATED);
    assert_eq!(again["photos"], first["photos"]);
    assert_eq!(again["photos"].as_array().unwrap().len(), 1);
    let mut bigger = jpeg(1);
    bigger.extend([0u8; 8]);
    assert_eq!(upload(&app, &id, cid, bigger).await.0, StatusCode::CONFLICT);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_replayed_signature_or_refusal_changes_nothing(db: PgPool) {
    let app = setup(db.clone()).await;
    let id = started(&app).await;
    let uri = format!("/api/v1/field/jobs/{id}/signature?signer_name=Sofie&client_id=00000000-0000-7000-8000-00000000fff1");
    let up = |png: Vec<u8>| {
        raw(
            &app,
            Who::Staff(TECH),
            Method::POST,
            &uri,
            Some(("image/png", png)),
        )
    };
    assert_eq!(up(PNG.to_vec()).await.0, StatusCode::CREATED);
    let at: chrono::DateTime<chrono::Utc> =
        sqlx::query_scalar("SELECT signed_at FROM field.job_signatures WHERE job_id = $1::uuid")
            .bind(&id)
            .fetch_one(&db)
            .await
            .unwrap();
    assert_eq!(up(PNG.to_vec()).await.0, StatusCode::CREATED, "replay");
    let at2: chrono::DateTime<chrono::Utc> =
        sqlx::query_scalar("SELECT signed_at FROM field.job_signatures WHERE job_id = $1::uuid")
            .bind(&id)
            .fetch_one(&db)
            .await
            .unwrap();
    assert_eq!(at, at2);
    assert_eq!(
        up(png_variant(7)).await.0,
        StatusCode::CONFLICT,
        "same id, other image"
    );
    let events: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM audit.events WHERE entity_id = $1::uuid AND action = 'signed'",
    )
    .bind(&id)
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(events, 1);

    // Declined: the same refusal twice is one record; a different reason replaces it.
    let uri = format!("/api/v1/field/jobs/{id}/signature/declined");
    let body = json!({ "signer_name": "Sofie", "reason": "No time" });
    let (s, first) = post(&app, TECH, &uri, body.clone()).await;
    assert_eq!(s, StatusCode::CREATED, "{first}");
    let (s, again) = post(&app, TECH, &uri, body).await;
    assert_eq!(s, StatusCode::CREATED);
    assert_eq!(
        again["signature"], first["signature"],
        "signed_at untouched"
    );
    let rows: i64 =
        sqlx::query_scalar("SELECT count(*) FROM field.job_signatures WHERE job_id = $1::uuid")
            .bind(&id)
            .fetch_one(&db)
            .await
            .unwrap();
    assert_eq!(rows, 1);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn start_tick_and_complete_can_be_replayed(db: PgPool) {
    let app = setup(db.clone()).await;
    let j = plan(&app, json!({})).await;
    let id = jid(&j);
    let task = j["tasks"][0]["id"].as_str().unwrap().to_string();
    let base = format!("/api/v1/field/jobs/{id}");
    for _ in 0..2 {
        assert_eq!(
            post(&app, TECH, &format!("{base}/start"), json!({}))
                .await
                .0,
            StatusCode::OK
        );
        let (s, d) = post(
            &app,
            TECH,
            &format!("{base}/tasks/{task}/done"),
            json!({ "done": true }),
        )
        .await;
        assert_eq!(s, StatusCode::OK);
        assert_eq!(d["job"]["tasks_done"], 1);
    }
    let body = json!({ "notes": "Seals replaced" });
    let (s, first) = post(&app, TECH, &format!("{base}/complete"), body.clone()).await;
    assert_eq!(s, StatusCode::OK, "{first}");
    let (s, again) = post(&app, TECH, &format!("{base}/complete"), body).await;
    assert_eq!(s, StatusCode::OK, "{again}");
    assert_eq!(again["job"]["completed_at"], first["job"]["completed_at"]);
    let (s, e) = post(
        &app,
        TECH,
        &format!("{base}/complete"),
        json!({ "notes": "Different" }),
    )
    .await;
    assert_eq!(s, StatusCode::CONFLICT, "{e}");
    let events: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM audit.events WHERE entity_id = $1::uuid AND action = 'completed'",
    )
    .bind(&id)
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(events, 1);
}
