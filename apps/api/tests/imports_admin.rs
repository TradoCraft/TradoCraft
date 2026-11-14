//! The import admin screen (ADR 0064 section 5): upload, preview, mappings, jobs run inline or
//! queued, and the shared job runner a worker calls.

mod common;

use axum::http::{Method, StatusCode};
use common::{call, raw, setup, Who};
use serde_json::{json, Value};
use sqlx::PgPool;
use tradocraft_core::import::{write, CellValue, Format, Limits};
use tradocraft_core::CurrentUser;
use uuid::Uuid;

const ADMIN: &str = "admin@example.com";
const ADMIN_ID: &str = "00000000-0000-7000-8000-000000000101";
const SALES: &str = "sales@example.com";
const SALES_ID: &str = "00000000-0000-7000-8000-000000000102";
const VIEWER: &str = "viewer@example.com";
const COMPANY: &str = "00000000-0000-7000-8000-000000000001";

fn t(s: &str) -> CellValue {
    CellValue::text(s)
}

fn uuid(s: &str) -> Uuid {
    s.parse().unwrap()
}

/// A workbook with the foreign headers of an old ERP plus one column we do not use.
fn erp_file(format: Format, rows: &[(&str, &str, &str)]) -> Vec<u8> {
    write(
        format,
        "Klanten",
        &["Klantnr", "Naam", "Zone", "Opmerking"],
        rows.iter()
            .map(|(c, n, z)| vec![t(c), t(n), t(z), t("ignored")]),
    )
    .unwrap()
}

fn erp_mapping() -> Value {
    json!([
        {"column": "klantnr", "field": "code"},
        {"column": " Naam ", "field": "name"},
        {"column": "Zone", "field": "price_zone_code"}
    ])
}

async fn upload(app: &axum::Router, user: &str, name: &str, body: Vec<u8>) -> (StatusCode, Value) {
    let (status, _, body) = raw(
        app,
        Who::Staff(user),
        Method::POST,
        &format!("/api/v1/imports/files?filename={name}"),
        Some(("application/octet-stream", body)),
    )
    .await;
    (status, serde_json::from_slice(&body).unwrap_or(Value::Null))
}

async fn upload_ok(app: &axum::Router, name: &str, body: Vec<u8>) -> String {
    let (status, f) = upload(app, ADMIN, name, body).await;
    assert_eq!(status, StatusCode::CREATED, "{f}");
    f["id"].as_str().unwrap().to_string()
}

async fn start(app: &axum::Router, body: Value) -> (StatusCode, Value) {
    call(app, ADMIN, Method::POST, "/api/v1/imports/jobs", Some(body)).await
}

async fn customers(db: &PgPool) -> i64 {
    sqlx::query_scalar("SELECT count(*) FROM crm.customers")
        .fetch_one(db)
        .await
        .unwrap()
}

fn counts(job: &Value) -> (i64, i64, i64) {
    (
        job["created"].as_i64().unwrap(),
        job["updated"].as_i64().unwrap(),
        job["unchanged"].as_i64().unwrap(),
    )
}

/// A job row for tests that run the shared function directly.
async fn queued_job(db: &PgPool, file_id: Option<&str>, requested_by: &str, entity: &str) -> Uuid {
    let id = Uuid::now_v7();
    sqlx::query(
        "INSERT INTO core.import_jobs (id, company_id, entity, file_id, filename, format, dry_run,
                                       requested_by, columns)
         VALUES ($1, $2, $3, $4, 'f.csv', 'csv', false, $5, NULL)",
    )
    .bind(id)
    .bind(uuid(COMPANY))
    .bind(entity)
    .bind(file_id.map(uuid))
    .bind(uuid(requested_by))
    .execute(db)
    .await
    .unwrap();
    id
}

async fn status_of(db: &PgPool, id: Uuid) -> (String, Option<String>, i32) {
    sqlx::query_as("SELECT status, message, error_count FROM core.import_jobs WHERE id = $1")
        .bind(id)
        .fetch_one(db)
        .await
        .unwrap()
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn every_endpoint_needs_imports_admin(db: PgPool) {
    let app = setup(db).await;
    let id = Uuid::nil();
    let calls: Vec<(Method, String, Option<Value>)> = vec![
        (Method::GET, "/imports/entities".into(), None),
        (Method::GET, format!("/imports/files/{id}/preview"), None),
        (Method::GET, "/imports/mappings".into(), None),
        (
            Method::PUT,
            "/imports/mappings".into(),
            Some(json!({"entity": "customers", "name": "x", "columns": []})),
        ),
        (Method::DELETE, format!("/imports/mappings/{id}"), None),
        (
            Method::POST,
            "/imports/jobs".into(),
            Some(json!({"file_id": id, "entity": "customers", "dry_run": true})),
        ),
        (Method::GET, "/imports/jobs".into(), None),
        (Method::GET, format!("/imports/jobs/{id}"), None),
        (Method::GET, format!("/imports/jobs/{id}/errors"), None),
        (Method::POST, format!("/imports/jobs/{id}/cancel"), None),
    ];
    // The sales role may write customers but is no administrator; the viewer is neither.
    for user in [SALES, VIEWER] {
        for (method, uri, body) in &calls {
            let (status, _) = call(
                &app,
                user,
                method.clone(),
                &format!("/api/v1{uri}"),
                body.clone(),
            )
            .await;
            assert_eq!(status, StatusCode::FORBIDDEN, "{user} {method} {uri}");
        }
        let (status, _) = upload(&app, user, "a.csv", b"code\n1\n".to_vec()).await;
        assert_eq!(status, StatusCode::FORBIDDEN, "{user} upload");
    }
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn running_a_job_also_needs_the_write_permission_of_the_entity(db: PgPool) {
    let app = setup(db.clone()).await;
    let file = upload_ok(
        &app,
        "c.csv",
        b"code,name,price_zone_code\nC1,One,Z1\n".to_vec(),
    )
    .await;
    let (status, list) = call(&app, ADMIN, Method::GET, "/api/v1/imports/entities", None).await;
    assert_eq!(status, StatusCode::OK);
    let keys: Vec<&str> = list
        .as_array()
        .unwrap()
        .iter()
        .map(|e| e["key"].as_str().unwrap())
        .collect();
    assert_eq!(keys, ["customers", "products"]);
    let customers_desc = &list[0];
    assert_eq!(customers_desc["key_column"], "code");
    assert_eq!(customers_desc["columns"][0]["name"], "code");
    assert_eq!(customers_desc["columns"][0]["kind"], "code");
    assert_eq!(customers_desc["columns"][0]["required"], true);

    // An administrator who has the customers module switched off keeps imports.admin.
    sqlx::query(
        "UPDATE core.user_companies SET disabled_modules = '{customers}' WHERE user_id = $1",
    )
    .bind(uuid(ADMIN_ID))
    .execute(&db)
    .await
    .unwrap();
    let (_, list) = call(&app, ADMIN, Method::GET, "/api/v1/imports/entities", None).await;
    let keys: Vec<&str> = list
        .as_array()
        .unwrap()
        .iter()
        .map(|e| e["key"].as_str().unwrap())
        .collect();
    assert_eq!(keys, ["products"]);
    let (status, body) = start(
        &app,
        json!({"file_id": file, "entity": "customers", "dry_run": false}),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN, "{body}");
    assert_eq!(customers(&db).await, 3);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn uploads_report_the_format_and_the_sheets_and_refused_files_are_not_stored(db: PgPool) {
    let app = setup(db.clone()).await;
    let (status, f) = upload(
        &app,
        ADMIN,
        "a%2Fb%2Fdata.csv",
        b"code,name\n1,a\n".to_vec(),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{f}");
    assert_eq!(f["format"], "csv");
    assert_eq!(f["filename"], "data.csv");
    assert_eq!(f["sheets"], json!([]));
    assert_eq!(f["size_bytes"], 14);
    for (format, name) in [(Format::Xlsx, "x.xlsx"), (Format::Ods, "o.ods")] {
        let (status, f) = upload(&app, ADMIN, name, erp_file(format, &[("C1", "One", "Z1")])).await;
        assert_eq!(status, StatusCode::CREATED, "{f}");
        assert_eq!(f["format"], format.extension());
        assert_eq!(f["sheets"], json!(["Klanten"]));
    }
    // No name given: a default one.
    let (_, f) = upload(&app, ADMIN, "", b"code\n1\n".to_vec()).await;
    assert_eq!(f["filename"], "import.csv");
    let stored = |db: &PgPool| {
        let db = db.clone();
        async move {
            sqlx::query_scalar::<_, i64>("SELECT count(*) FROM core.import_files")
                .fetch_one(&db)
                .await
                .unwrap()
        }
    };
    assert_eq!(stored(&db).await, 4);

    // Refused: a legacy binary file and a zip that is no spreadsheet.
    let mut xls = vec![0xD0, 0xCF, 0x11, 0xE0];
    xls.extend([0u8; 64]);
    let (status, e) = upload(&app, ADMIN, "old.xls", xls).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    assert!(e["message"].as_str().unwrap().contains(".xls"), "{e}");
    let mut zip = zip::ZipWriter::new(std::io::Cursor::new(Vec::new()));
    zip.start_file("a.txt", zip::write::SimpleFileOptions::default())
        .unwrap();
    std::io::Write::write_all(&mut zip, b"hi").unwrap();
    let zipped = zip.finish().unwrap().into_inner();
    let (status, e) = upload(&app, ADMIN, "z.zip", zipped).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    assert!(e["message"].as_str().unwrap().contains("not a spreadsheet"));
    assert_eq!(stored(&db).await, 4);

    // Larger than a background job may be: 413.
    let big = vec![b'a'; Limits::job().file_bytes + 1];
    let (status, _) = upload(&app, ADMIN, "big.csv", big).await;
    assert_eq!(status, StatusCode::PAYLOAD_TOO_LARGE);
    assert_eq!(stored(&db).await, 4);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_preview_shows_the_header_the_count_and_the_first_rows(db: PgPool) {
    let app = setup(db).await;
    let rows: Vec<(String, String, String)> = (1..=25)
        .map(|i| (format!("C{i}"), format!("Name {i}"), "Z1".to_string()))
        .collect();
    let refs: Vec<(&str, &str, &str)> = rows
        .iter()
        .map(|(a, b, c)| (a.as_str(), b.as_str(), c.as_str()))
        .collect();
    let file = upload_ok(&app, "x.xlsx", erp_file(Format::Xlsx, &refs)).await;
    let (status, p) = call(
        &app,
        ADMIN,
        Method::GET,
        &format!("/api/v1/imports/files/{file}/preview"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{p}");
    assert_eq!(p["format"], "xlsx");
    assert_eq!(p["sheet"], "Klanten");
    assert_eq!(p["sheets"], json!(["Klanten"]));
    assert_eq!(p["header_row"], 1);
    assert_eq!(
        p["columns"],
        json!(["Klantnr", "Naam", "Zone", "Opmerking"])
    );
    assert_eq!(p["row_count"], 25);
    assert_eq!(p["rows"].as_array().unwrap().len(), 20);
    assert_eq!(p["rows"][0], json!(["C1", "Name 1", "Z1", "ignored"]));

    // A second sheet is chosen by name; an unknown one is a 422 that names the sheets.
    let two = {
        let mut wb = rust_xlsxwriter::Workbook::new();
        let a = wb.add_worksheet();
        a.set_name("First").unwrap();
        a.write_string(0, 0, "code").unwrap();
        a.write_string(1, 0, "a").unwrap();
        let b = wb.add_worksheet();
        b.set_name("Second").unwrap();
        b.write_string(0, 0, "name").unwrap();
        b.write_number(1, 0, 7.5).unwrap();
        b.write_string(2, 0, "").unwrap();
        wb.save_to_buffer().unwrap()
    };
    let file = upload_ok(&app, "two.xlsx", two).await;
    let uri = |q: &str| format!("/api/v1/imports/files/{file}/preview{q}");
    let (_, p) = call(&app, ADMIN, Method::GET, &uri("?sheet=Second"), None).await;
    assert_eq!(p["sheet"], "Second");
    assert_eq!(p["columns"], json!(["name"]));
    assert_eq!(p["rows"], json!([["7.5"]]));
    let (_, p) = call(&app, ADMIN, Method::GET, &uri(""), None).await;
    assert_eq!(p["sheet"], "First");
    let (status, e) = call(&app, ADMIN, Method::GET, &uri("?sheet=Nope"), None).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    assert!(e["message"].as_str().unwrap().contains("First"), "{e}");
    let (status, _) = call(
        &app,
        ADMIN,
        Method::GET,
        &format!("/api/v1/imports/files/{}/preview", Uuid::now_v7()),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn mappings_are_saved_replaced_validated_deleted_and_audited(db: PgPool) {
    let app = setup(db.clone()).await;
    let put = |body: Value| {
        let app = app.clone();
        async move {
            call(
                &app,
                ADMIN,
                Method::PUT,
                "/api/v1/imports/mappings",
                Some(body),
            )
            .await
        }
    };
    let (status, m) =
        put(json!({"entity": "customers", "name": "  Old ERP ", "columns": erp_mapping()})).await;
    assert_eq!(status, StatusCode::OK, "{m}");
    assert_eq!(m["name"], "Old ERP");
    assert_eq!(m["columns"][1], json!({"column": "Naam", "field": "name"}));
    let id = m["id"].as_str().unwrap().to_string();

    // The same name replaces it.
    let (status, m2) = put(json!({"entity": "customers", "name": "Old ERP",
        "columns": [{"column": "A", "field": "code"}]}))
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(m2["id"], id.as_str());
    put(json!({"entity": "products", "name": "Old ERP",
        "columns": [{"column": "A", "field": "code"}]}))
    .await;
    let (_, list) = call(
        &app,
        ADMIN,
        Method::GET,
        "/api/v1/imports/mappings?entity=customers",
        None,
    )
    .await;
    assert_eq!(list.as_array().unwrap().len(), 1);
    assert_eq!(
        list[0]["columns"],
        json!([{"column": "A", "field": "code"}])
    );
    let (_, all) = call(&app, ADMIN, Method::GET, "/api/v1/imports/mappings", None).await;
    assert_eq!(all.as_array().unwrap().len(), 2);

    let bad = |name: &str, columns: Value, entity: &str| json!({"entity": entity, "name": name, "columns": columns});
    for (body, needle) in [
        (
            bad("x", json!([{"column": "A", "field": "code"}]), "nope"),
            "not an importable",
        ),
        (
            bad(
                "   ",
                json!([{"column": "A", "field": "code"}]),
                "customers",
            ),
            "needs a name",
        ),
        (
            bad(
                &"n".repeat(101),
                json!([{"column": "A", "field": "code"}]),
                "customers",
            ),
            "longer",
        ),
        (bad("x", json!([]), "customers"), "at least one"),
        (
            bad("x", json!([{"column": "A", "field": "nope"}]), "customers"),
            "not a field",
        ),
        (
            bad(
                "x",
                json!([{"column": "A", "field": "code"}, {"column": "B", "field": "code"}]),
                "customers",
            ),
            "mapped twice",
        ),
        (
            bad(
                "x",
                json!([{"column": "Name", "field": "code"}, {"column": " name ", "field": "name"}]),
                "customers",
            ),
            "mapped twice",
        ),
        (
            bad("x", json!([{"column": " ", "field": "code"}]), "customers"),
            "blank",
        ),
    ] {
        let (status, e) = put(body).await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{needle}: {e}");
        assert!(
            e["message"].as_str().unwrap().contains(needle),
            "{needle}: {e}"
        );
    }

    let (status, _) = call(
        &app,
        ADMIN,
        Method::DELETE,
        &format!("/api/v1/imports/mappings/{id}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    let (status, _) = call(
        &app,
        ADMIN,
        Method::DELETE,
        &format!("/api/v1/imports/mappings/{id}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let events: Vec<(String,)> = sqlx::query_as(
        "SELECT action FROM audit.events WHERE entity = 'import_mapping' AND entity_id = $1 ORDER BY id",
    )
    .bind(uuid(&id))
    .fetch_all(&db)
    .await
    .unwrap();
    let actions: Vec<&str> = events.iter().map(|e| e.0.as_str()).collect();
    assert_eq!(actions, ["created", "updated", "deleted"]);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_spreadsheet_with_foreign_headers_is_imported_through_a_mapping(db: PgPool) {
    let app = setup(db.clone()).await;
    let file = upload_ok(
        &app,
        "klanten.xlsx",
        erp_file(
            Format::Xlsx,
            &[("NEW1", "New One", "Z1"), ("NEW2", "New Two", "Z2")],
        ),
    )
    .await;
    let body = |dry: bool| json!({"file_id": file, "entity": "customers", "columns": erp_mapping(), "dry_run": dry});
    let before = customers(&db).await;

    let (status, job) = start(&app, body(true)).await;
    assert_eq!(status, StatusCode::OK, "{job}");
    assert_eq!(job["status"], "done");
    assert_eq!(job["dry_run"], true);
    assert_eq!(counts(&job), (2, 0, 0));
    assert_eq!(job["total_rows"], 2);
    assert_eq!(job["processed_rows"], 2);
    assert_eq!(job["error_count"], 0);
    assert_eq!(job["filename"], "klanten.xlsx");
    assert_eq!(job["format"], "xlsx");
    assert_eq!(job["requested_by_name"], "Admin User");
    assert!(job["finished_at"].is_string());
    assert_eq!(customers(&db).await, before);

    let (status, job) = start(&app, body(false)).await;
    assert_eq!(status, StatusCode::OK, "{job}");
    assert_eq!(job["status"], "done");
    assert_eq!(counts(&job), (2, 0, 0));
    assert_eq!(customers(&db).await, before + 2);
    let name: String = sqlx::query_scalar("SELECT name FROM crm.customers WHERE code = 'NEW2'")
        .fetch_one(&db)
        .await
        .unwrap();
    assert_eq!(name, "New Two");
    let job_id = job["id"].as_str().unwrap();
    let audited: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM audit.events WHERE entity = 'customer' AND action = 'created'
         AND data->>'import_job' = $1 AND data->>'source' = 'xlsx_import'",
    )
    .bind(job_id)
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(audited, 2);

    // Applying again: nothing changed.
    let (_, again) = start(&app, body(false)).await;
    assert_eq!(counts(&again), (0, 0, 2));

    // Without the mapping the header does not name our columns: the job is done, with errors.
    let (status, job) = start(
        &app,
        json!({"file_id": file, "entity": "customers", "dry_run": false}),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(job["status"], "done");
    assert!(job["error_count"].as_i64().unwrap() > 0);
    assert_eq!(counts(&job), (0, 0, 0));
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_run_with_row_errors_is_done_with_zero_counts_and_a_csv_of_the_errors(db: PgPool) {
    let app = setup(db.clone()).await;
    let csv = "code,name,price_zone_code\nA1,Fine,Z1\nA2,,Z1\nA3,Zone,NOPE\n=cmd,Formula,Z1\n";
    let file = upload_ok(&app, "bad.csv", csv.as_bytes().to_vec()).await;
    let before = customers(&db).await;
    let (status, job) = start(
        &app,
        json!({"file_id": file, "entity": "customers", "dry_run": false}),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{job}");
    assert_eq!(job["status"], "done");
    assert_eq!(counts(&job), (0, 0, 0));
    let n = job["error_count"].as_i64().unwrap();
    assert!(n >= 2, "{job}");
    assert_eq!(job["errors"].as_array().unwrap().len() as i64, n);
    assert_eq!(job["errors"][0]["row"], 3);
    assert_eq!(customers(&db).await, before);
    assert_eq!(job["message"], Value::Null);

    let id = job["id"].as_str().unwrap();
    let (status, headers, body) = raw(
        &app,
        Who::Staff(ADMIN),
        Method::GET,
        &format!("/api/v1/imports/jobs/{id}/errors"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(headers["content-type"], "text/csv; charset=utf-8");
    assert_eq!(
        headers["content-disposition"],
        format!("attachment; filename=\"import-errors-{}.csv\"", &id[..8])
    );
    let body = String::from_utf8(body).unwrap();
    let lines: Vec<&str> = body.lines().collect();
    assert_eq!(lines[0], "row,column,message");
    assert_eq!(lines.len() as i64, n + 1);
    let first = &job["errors"][0];
    assert!(lines[1].starts_with(&format!("3,{}", first["column"].as_str().unwrap_or(""))));
    assert!(body.contains(first["message"].as_str().unwrap()));
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_missing_file_fails_the_job_cleanly(db: PgPool) {
    let app = setup(db.clone()).await;
    let file = upload_ok(
        &app,
        "c.csv",
        b"code,name,price_zone_code\nC1,One,Z1\n".to_vec(),
    )
    .await;
    sqlx::query("DELETE FROM core.import_files")
        .execute(&db)
        .await
        .unwrap();
    let (status, _) = start(
        &app,
        json!({"file_id": file, "entity": "customers", "dry_run": false}),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    // A job whose file was cleaned up while it waited.
    let id = queued_job(&db, None, ADMIN_ID, "customers").await;
    let claimed = tradocraft_imports::claim_next(&db).await.unwrap().unwrap();
    assert_eq!(claimed.id, id);
    tradocraft_imports::run_claimed(&db, &claimed, &Limits::job())
        .await
        .unwrap();
    let (status, message, _) = status_of(&db, id).await;
    assert_eq!(status, "failed");
    assert!(message.unwrap().contains("no longer available"));
    let (_, job) = call(
        &app,
        ADMIN,
        Method::GET,
        &format!("/api/v1/imports/jobs/{id}"),
        None,
    )
    .await;
    assert_eq!(job["status"], "failed");
    assert!(job["message"].as_str().unwrap().contains("file"));
}

fn big_csv(rows: usize) -> Vec<u8> {
    let mut s = String::from("code,name,price_zone_code\n");
    for i in 0..rows {
        s.push_str(&format!("BIG{i},Big {i},Z1\n"));
    }
    s.into_bytes()
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_file_beyond_the_request_limits_is_queued_and_only_a_queued_job_is_cancelled(db: PgPool) {
    let app = setup(db.clone()).await;
    let file = upload_ok(&app, "big.csv", big_csv(20_001)).await;
    let before = customers(&db).await;
    let (status, job) = start(
        &app,
        json!({"file_id": file, "entity": "customers", "dry_run": false}),
    )
    .await;
    assert_eq!(status, StatusCode::ACCEPTED, "{job}");
    assert_eq!(job["status"], "queued");
    assert_eq!(job["error_count"], 0);
    assert_eq!(job["started_at"], Value::Null);
    assert_eq!(customers(&db).await, before);
    let id = job["id"].as_str().unwrap();

    let (status, c) = call(
        &app,
        ADMIN,
        Method::POST,
        &format!("/api/v1/imports/jobs/{id}/cancel"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{c}");
    assert_eq!(c["status"], "cancelled");
    let (status, _) = call(
        &app,
        ADMIN,
        Method::POST,
        &format!("/api/v1/imports/jobs/{id}/cancel"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);

    // A finished job cannot be cancelled either.
    let small = upload_ok(
        &app,
        "s.csv",
        b"code,name,price_zone_code\nS1,S,Z1\n".to_vec(),
    )
    .await;
    let (_, done) = start(
        &app,
        json!({"file_id": small, "entity": "customers", "dry_run": true}),
    )
    .await;
    assert_eq!(done["status"], "done");
    let (status, _) = call(
        &app,
        ADMIN,
        Method::POST,
        &format!(
            "/api/v1/imports/jobs/{}/cancel",
            done["id"].as_str().unwrap()
        ),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
    let (status, _) = call(
        &app,
        ADMIN,
        Method::POST,
        &format!("/api/v1/imports/jobs/{}/cancel", Uuid::now_v7()),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    assert_eq!(customers(&db).await, before);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_worker_path_claims_runs_and_finishes_a_queued_job_with_the_job_limits(db: PgPool) {
    let app = setup(db.clone()).await;
    let file = upload_ok(&app, "big.csv", big_csv(20_001)).await;
    let (status, job) = start(
        &app,
        json!({"file_id": file, "entity": "customers", "dry_run": false}),
    )
    .await;
    assert_eq!(status, StatusCode::ACCEPTED);
    let id = uuid(job["id"].as_str().unwrap());
    let before = customers(&db).await;

    let claimed = tradocraft_imports::claim_next(&db).await.unwrap().unwrap();
    assert_eq!(claimed.id, id);
    assert!(tradocraft_imports::claim_next(&db).await.unwrap().is_none());
    let (running, _, _) = status_of(&db, id).await;
    assert_eq!(running, "running");
    tradocraft_imports::run_claimed(&db, &claimed, &Limits::job())
        .await
        .unwrap();
    let (_, job) = call(
        &app,
        ADMIN,
        Method::GET,
        &format!("/api/v1/imports/jobs/{id}"),
        None,
    )
    .await;
    assert_eq!(job["status"], "done", "{job}");
    assert_eq!(counts(&job), (20_001, 0, 0));
    assert_eq!(job["total_rows"], 20_001);
    assert_eq!(job["processed_rows"], 20_001);
    assert_eq!(job["phase"], Value::Null);
    assert_eq!(customers(&db).await, before + 20_001);
    let attempts: i32 = sqlx::query_scalar("SELECT attempts FROM core.import_jobs WHERE id = $1")
        .bind(id)
        .fetch_one(&db)
        .await
        .unwrap();
    assert_eq!(attempts, 1);
    let audited: i64 =
        sqlx::query_scalar("SELECT count(*) FROM audit.events WHERE data->>'import_job' = $1")
            .bind(id.to_string())
            .fetch_one(&db)
            .await
            .unwrap();
    assert_eq!(audited, 20_001);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_job_whose_requester_lost_a_permission_or_the_account_fails_and_writes_nothing(
    db: PgPool,
) {
    let app = setup(db.clone()).await;
    let file = upload_ok(
        &app,
        "c.csv",
        b"code,name,price_zone_code\nL1,Lost,Z1\n".to_vec(),
    )
    .await;
    let before = customers(&db).await;

    // Sales may write customers but has no imports.admin.
    let id = queued_job(&db, Some(&file), SALES_ID, "customers").await;
    let claimed = tradocraft_imports::claim_next(&db).await.unwrap().unwrap();
    tradocraft_imports::run_claimed(&db, &claimed, &Limits::job())
        .await
        .unwrap();
    let (status, message, _) = status_of(&db, id).await;
    assert_eq!(status, "failed");
    assert!(message.unwrap().contains("imports.admin"));

    // The administrator with the module switched off lacks the entity's write permission.
    sqlx::query(
        "UPDATE core.user_companies SET disabled_modules = '{customers}' WHERE user_id = $1",
    )
    .bind(uuid(ADMIN_ID))
    .execute(&db)
    .await
    .unwrap();
    let id = queued_job(&db, Some(&file), ADMIN_ID, "customers").await;
    let claimed = tradocraft_imports::claim_next(&db).await.unwrap().unwrap();
    tradocraft_imports::run_claimed(&db, &claimed, &Limits::job())
        .await
        .unwrap();
    let (status, message, _) = status_of(&db, id).await;
    assert_eq!(status, "failed");
    assert!(message.unwrap().contains("customers"));

    // A deactivated requester.
    sqlx::query("UPDATE core.user_companies SET disabled_modules = '{}' WHERE user_id = $1")
        .bind(uuid(ADMIN_ID))
        .execute(&db)
        .await
        .unwrap();
    sqlx::query("UPDATE core.users SET active = false WHERE id = $1")
        .bind(uuid(ADMIN_ID))
        .execute(&db)
        .await
        .unwrap();
    let id = queued_job(&db, Some(&file), ADMIN_ID, "customers").await;
    let claimed = tradocraft_imports::claim_next(&db).await.unwrap().unwrap();
    tradocraft_imports::run_claimed(&db, &claimed, &Limits::job())
        .await
        .unwrap();
    let (status, message, _) = status_of(&db, id).await;
    assert_eq!(status, "failed");
    assert!(message.unwrap().contains("deactivated"));
    assert_eq!(customers(&db).await, before);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_current_user_is_built_for_a_stored_user_and_company(db: PgPool) {
    let _app = setup(db.clone()).await;
    let (admin, company) = (uuid(ADMIN_ID), uuid(COMPANY));
    let user = CurrentUser::for_member(&db, admin, company).await.unwrap();
    assert_eq!(user.email, ADMIN);
    assert_eq!(user.company_id, company);
    assert_eq!(user.roles, ["admin"]);
    assert!(user.can(tradocraft_core::Permission::ImportsAdmin));

    sqlx::query(
        "UPDATE core.user_companies SET disabled_modules = '{products}' WHERE user_id = $1",
    )
    .bind(admin)
    .execute(&db)
    .await
    .unwrap();
    let user = CurrentUser::for_member(&db, admin, company).await.unwrap();
    assert!(!user.can(tradocraft_core::Permission::ProductsWrite));
    assert!(user.can(tradocraft_core::Permission::ImportsAdmin));

    // Not a member of another company, nor a stranger.
    let other = Uuid::now_v7();
    sqlx::query("INSERT INTO core.companies (id, name) VALUES ($1, 'Other BV')")
        .bind(other)
        .execute(&db)
        .await
        .unwrap();
    assert!(CurrentUser::for_member(&db, admin, other).await.is_err());
    assert!(CurrentUser::for_member(&db, Uuid::now_v7(), company)
        .await
        .is_err());

    sqlx::query("UPDATE core.user_companies SET active = false WHERE user_id = $1")
        .bind(admin)
        .execute(&db)
        .await
        .unwrap();
    assert!(CurrentUser::for_member(&db, admin, company).await.is_err());
    sqlx::query("UPDATE core.user_companies SET active = true WHERE user_id = $1")
        .bind(admin)
        .execute(&db)
        .await
        .unwrap();
    sqlx::query("UPDATE core.users SET active = false WHERE id = $1")
        .bind(admin)
        .execute(&db)
        .await
        .unwrap();
    assert!(CurrentUser::for_member(&db, admin, company).await.is_err());
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_job_list_is_newest_first_filtered_and_paged(db: PgPool) {
    let app = setup(db.clone()).await;
    let file = upload_ok(
        &app,
        "c.csv",
        b"code,name,price_zone_code\nJ1,J,Z1\n".to_vec(),
    )
    .await;
    let mut ids = Vec::new();
    for dry in [true, true, false] {
        let (_, job) = start(
            &app,
            json!({"file_id": file, "entity": "customers", "dry_run": dry}),
        )
        .await;
        ids.push(job["id"].as_str().unwrap().to_string());
    }
    let big = upload_ok(&app, "big.csv", big_csv(20_001)).await;
    let (_, queued) = start(
        &app,
        json!({"file_id": big, "entity": "customers", "dry_run": true}),
    )
    .await;
    ids.push(queued["id"].as_str().unwrap().to_string());

    let (status, page) = call(&app, ADMIN, Method::GET, "/api/v1/imports/jobs", None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(page["total"], 4);
    let listed: Vec<&str> = page["items"]
        .as_array()
        .unwrap()
        .iter()
        .map(|j| j["id"].as_str().unwrap())
        .collect();
    let newest_first: Vec<&str> = ids.iter().rev().map(String::as_str).collect();
    assert_eq!(listed, newest_first);
    assert_eq!(page["items"][0]["errors"], json!([]));

    let (_, queued_only) = call(
        &app,
        ADMIN,
        Method::GET,
        "/api/v1/imports/jobs?status=queued",
        None,
    )
    .await;
    assert_eq!(queued_only["total"], 1);
    assert_eq!(queued_only["items"][0]["id"], ids[3].as_str());
    let (_, paged) = call(
        &app,
        ADMIN,
        Method::GET,
        "/api/v1/imports/jobs?limit=1&offset=1",
        None,
    )
    .await;
    assert_eq!(paged["items"].as_array().unwrap().len(), 1);
    assert_eq!(paged["items"][0]["id"], ids[2].as_str());
    assert_eq!(paged["total"], 4);
    let (status, _) = call(
        &app,
        ADMIN,
        Method::GET,
        "/api/v1/imports/jobs?status=bogus",
        None,
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn another_companys_files_mappings_and_jobs_are_not_found(db: PgPool) {
    let app = setup(db.clone()).await;
    let other = Uuid::now_v7();
    sqlx::query("INSERT INTO core.companies (id, name) VALUES ($1, 'Other BV')")
        .bind(other)
        .execute(&db)
        .await
        .unwrap();
    let file = Uuid::now_v7();
    sqlx::query(
        "INSERT INTO core.import_files (id, company_id, filename, format, size_bytes, data)
         VALUES ($1, $2, 'o.csv', 'csv', 5, 'a\nb\n')",
    )
    .bind(file)
    .bind(other)
    .execute(&db)
    .await
    .unwrap();
    let mapping = Uuid::now_v7();
    sqlx::query(
        "INSERT INTO core.import_mappings (id, company_id, entity, name, columns)
         VALUES ($1, $2, 'customers', 'theirs', '[]')",
    )
    .bind(mapping)
    .bind(other)
    .execute(&db)
    .await
    .unwrap();
    let job = Uuid::now_v7();
    sqlx::query(
        "INSERT INTO core.import_jobs (id, company_id, entity, file_id, filename, format, dry_run)
         VALUES ($1, $2, 'customers', $3, 'o.csv', 'csv', true)",
    )
    .bind(job)
    .bind(other)
    .bind(file)
    .execute(&db)
    .await
    .unwrap();

    let get = |method: Method, uri: String, body: Option<Value>| {
        let app = app.clone();
        async move {
            call(&app, ADMIN, method, &format!("/api/v1{uri}"), body)
                .await
                .0
        }
    };
    assert_eq!(
        get(Method::GET, format!("/imports/files/{file}/preview"), None).await,
        StatusCode::NOT_FOUND
    );
    assert_eq!(
        get(
            Method::POST,
            "/imports/jobs".into(),
            Some(json!({"file_id": file, "entity": "customers", "dry_run": true}))
        )
        .await,
        StatusCode::NOT_FOUND
    );
    assert_eq!(
        get(Method::DELETE, format!("/imports/mappings/{mapping}"), None).await,
        StatusCode::NOT_FOUND
    );
    assert_eq!(
        get(Method::GET, format!("/imports/jobs/{job}"), None).await,
        StatusCode::NOT_FOUND
    );
    assert_eq!(
        get(Method::GET, format!("/imports/jobs/{job}/errors"), None).await,
        StatusCode::NOT_FOUND
    );
    assert_eq!(
        get(Method::POST, format!("/imports/jobs/{job}/cancel"), None).await,
        StatusCode::NOT_FOUND
    );
    let (_, list) = call(&app, ADMIN, Method::GET, "/api/v1/imports/jobs", None).await;
    assert_eq!(list["total"], 0);
    let (_, maps) = call(&app, ADMIN, Method::GET, "/api/v1/imports/mappings", None).await;
    assert_eq!(maps, json!([]));
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn an_inline_run_finishes_when_the_client_goes_away(db: PgPool) {
    let app = setup(db.clone()).await;
    let mut csv = String::from("code,name,price_zone_code\n");
    for i in 0..5_000 {
        csv.push_str(&format!("G{i},Name {i},Z1\n"));
    }
    let file_id = upload_ok(&app, "drop.csv", csv.into_bytes()).await;
    let before = customers(&db).await;
    let request = {
        let app = app.clone();
        tokio::spawn(async move {
            start(
                &app,
                json!({"file_id": file_id, "entity": "customers", "dry_run": false}),
            )
            .await
        })
    };
    // Wait for the job to exist, then drop the request like a closed tab would.
    for _ in 0..2_000 {
        let n: i64 = sqlx::query_scalar("SELECT count(*) FROM core.import_jobs")
            .fetch_one(&db)
            .await
            .unwrap();
        if n > 0 {
            break;
        }
        tokio::time::sleep(std::time::Duration::from_millis(2)).await;
    }
    request.abort();
    for _ in 0..1_000 {
        let status: String = sqlx::query_scalar("SELECT status FROM core.import_jobs LIMIT 1")
            .fetch_one(&db)
            .await
            .unwrap();
        if status != "running" {
            assert_eq!(status, "done");
            assert_eq!(customers(&db).await, before + 5_000);
            return;
        }
        tokio::time::sleep(std::time::Duration::from_millis(20)).await;
    }
    panic!("the job stayed running");
}
