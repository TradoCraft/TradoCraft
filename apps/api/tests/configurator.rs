//! Admin-defined configurators (ADR 0034): importing and activating the public demo, evaluating
//! inputs (lines, pins, warnings), saving a configuration, quoting it, re-quoting after edits and
//! after sending, revisions, product attributes and permissions.

mod common;

use axum::http::{Method, StatusCode};
use common::{call, dec, setup};
use rust_decimal_macros::dec;
use serde_json::{json, Value};
use sqlx::PgPool;

const ADMIN: &str = "admin@example.com";
const SALES: &str = "sales@example.com";
const VIEWER: &str = "viewer@example.com";
const ALPHA: &str = "00000000-0000-7000-8000-000000000401";
const MOT_055: &str = "00000000-0000-7000-8000-0000000003d1";

fn demo() -> Value {
    serde_json::from_str(include_str!(
        "../../../seed/configurators/conveyor_line.json"
    ))
    .unwrap()
}

fn sample() -> Value {
    json!({
        "project": { "phases": 3, "voltage": 400, "coating": true },
        "groups": { "Hall 2": { "voltage": 230 } },
        "items": { "segments": [
            { "hall": "Hall 1", "length_m": 12, "load_kg": 200, "speed": 0.5 },
            { "hall": "Hall 1", "length_m": 45, "load_kg": 800, "speed": 1.0 },
            { "hall": "Hall 2", "length_m": 8, "load_kg": 300, "speed": 2.0, "emergency_stop": true }
        ] }
    })
}

async fn post(app: &axum::Router, user: &str, uri: &str, body: Value) -> (StatusCode, Value) {
    call(app, user, Method::POST, uri, Some(body)).await
}

async fn get(app: &axum::Router, user: &str, uri: &str) -> (StatusCode, Value) {
    call(app, user, Method::GET, uri, None).await
}

/// Imports the demo as a draft and activates it; returns (model id, revision id).
async fn import_and_activate(app: &axum::Router) -> (String, String) {
    let (status, rev) = post(app, ADMIN, "/api/v1/configurator/models/import", demo()).await;
    assert_eq!(status, StatusCode::CREATED, "{rev}");
    assert_eq!(rev["status"], "draft");
    assert_eq!(rev["revision"], 1);
    assert_eq!(rev["errors"], json!([]), "{rev}");
    let id = rev["id"].as_str().unwrap().to_string();
    let (status, act) = post(
        app,
        ADMIN,
        &format!("/api/v1/configurator/revisions/{id}/activate"),
        json!({}),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{act}");
    assert_eq!(act["status"], "active");
    (rev["model_id"].as_str().unwrap().to_string(), id)
}

fn codes(lines: &Value) -> Vec<String> {
    lines
        .as_array()
        .unwrap()
        .iter()
        .map(|l| {
            format!(
                "{} x{}",
                l["code"].as_str().unwrap(),
                l["quantity"].as_str().unwrap()
            )
        })
        .collect()
}

fn qline<'a>(q: &'a Value, code: &str, section: &str) -> &'a Value {
    q["lines"]
        .as_array()
        .unwrap()
        .iter()
        .find(|l| l["product_code"] == code && l["section"] == section)
        .unwrap_or_else(|| panic!("no line {code} in {section}: {q}"))
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn import_activate_and_evaluate_the_demo(db: PgPool) {
    let app = setup(db).await;
    let (model, rev) = import_and_activate(&app).await;

    let (status, models) = get(&app, SALES, "/api/v1/configurator/models").await;
    assert_eq!(status, StatusCode::OK, "{models}");
    assert_eq!(models[0]["code"], "CONVEYOR-LINE");
    assert_eq!(models[0]["active_revision"], 1);
    assert_eq!(models[0]["active_revision_id"], rev.as_str());

    let mut inputs = sample();
    inputs["pins"] = json!([
        { "name": "motor_code", "table": "segments", "row": 1, "value": "MOT-055", "calculated": "MOT-110" }
    ]);
    let (status, ev) = post(
        &app,
        SALES,
        &format!("/api/v1/configurator/revisions/{rev}/evaluate"),
        inputs,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{ev}");
    assert_eq!(
        codes(&ev["lines"]),
        [
            "BELT-M x116",
            "BELT-M x17",
            "MOT-055 x2",
            "MOT-110 x1",
            "DRV-05T x2",
            "DRV-11T x1",
            "ESTOP-01 x1",
            "TENS-ST x1",
            "CTRL-B4 x1",
            "CTRL-B4 x1",
            "INSTALL x32"
        ],
        "{}",
        ev["lines"]
    );
    // The pinned smaller motor merges with the first one; both carry the coating at 20 %.
    let motor = &ev["lines"][2];
    assert_eq!(motor["comment"], "Hall 1 / segment 1, Hall 1 / segment 2");
    assert_eq!(motor["children"][0]["code"], "COAT-PROT");
    assert_eq!(motor["children"][0]["percent_of_parent"], "20");
    assert_eq!(motor["children"][0]["quantity"], "2");
    assert_eq!(motor["trace"]["rule"], "motor");
    assert_eq!(motor["trace"]["sources"].as_array().unwrap().len(), 2);
    // Lines carry their catalogue product (id and base name without a language).
    assert_eq!(motor["product_id"], MOT_055);
    assert!(motor["product_name"]
        .as_str()
        .is_some_and(|n| !n.is_empty()));
    assert!(motor["children"][0]["product_id"].is_string());
    // Values, sources and options; the pin is recorded as such.
    let row1 = &ev["items"][0]["rows"][1];
    let mc = row1["values"]
        .as_array()
        .unwrap()
        .iter()
        .find(|v| v["name"] == "motor_code")
        .unwrap();
    assert_eq!(mc["source"], "pinned");
    assert_eq!(mc["value"], "MOT-055");
    assert_eq!(mc["calculated"], "MOT-110");
    assert_eq!(
        mc["options"],
        json!(["MOT-055", "MOT-110", "MOT-220", "MOT-400"])
    );
    // Warnings: the 230 V hall and the motor smaller than required (from the product attributes).
    let issues: Vec<(&str, &str)> = ev["issues"]
        .as_array()
        .unwrap()
        .iter()
        .map(|i| (i["code"].as_str().unwrap(), i["severity"].as_str().unwrap()))
        .collect();
    assert_eq!(
        issues,
        [
            ("three_phase_voltage", "warning"),
            ("motor_too_small", "warning"),
            ("fast_belt", "info")
        ],
        "{}",
        ev["issues"]
    );

    // Export gives back the definition in the import format.
    let (status, ex) = get(
        &app,
        SALES,
        &format!("/api/v1/configurator/revisions/{rev}/export"),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(ex["format"], "tradocraft.configurator");
    assert_eq!(ex["model"]["code"], "CONVEYOR-LINE");
    assert_eq!(ex["definition"]["tables"][0]["name"], "motors");

    // Importing the same code again makes a second draft; a third import is refused.
    let (status, r2) = post(&app, ADMIN, "/api/v1/configurator/models/import", demo()).await;
    assert_eq!(status, StatusCode::CREATED, "{r2}");
    assert_eq!(r2["revision"], 2);
    assert_eq!(r2["model_id"], model.as_str());
    let (status, _) = post(&app, ADMIN, "/api/v1/configurator/models/import", demo()).await;
    assert_eq!(status, StatusCode::CONFLICT);

    // A draft with problems is saved, but cannot be activated.
    let r2id = r2["id"].as_str().unwrap();
    let mut broken = demo()["definition"].clone();
    broken["outputs"][0]["quantity"] = json!("ceil(length_m * )");
    broken["project"]["computed"][0]["expr"] = json!("total_length + 1");
    let (status, saved) = call(
        &app,
        ADMIN,
        Method::PUT,
        &format!("/api/v1/configurator/revisions/{r2id}"),
        Some(json!({ "definition": broken, "notes": "work in progress" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{saved}");
    let paths: Vec<&str> = saved["errors"]
        .as_array()
        .unwrap()
        .iter()
        .map(|e| e["path"].as_str().unwrap())
        .collect();
    assert!(paths.contains(&"$.outputs[0].quantity"), "{paths:?}");
    assert!(paths.contains(&"$.project.computed[0]"), "{paths:?}");
    let (status, err) = post(
        &app,
        ADMIN,
        &format!("/api/v1/configurator/revisions/{r2id}/activate"),
        json!({}),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{err}");
    assert!(
        err["message"]
            .as_str()
            .unwrap()
            .contains("circular dependency"),
        "{err}"
    );
    // Not a definition at all: refused outright.
    let (status, _) = call(
        &app,
        ADMIN,
        Method::PUT,
        &format!("/api/v1/configurator/revisions/{r2id}"),
        Some(json!({ "definition": { "name": "x", "bogus": 1 } })),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    // An active revision cannot be edited.
    let (status, _) = call(
        &app,
        ADMIN,
        Method::PUT,
        &format!("/api/v1/configurator/revisions/{rev}"),
        Some(json!({ "definition": demo()["definition"] })),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn expressions_are_checked_for_the_editor(db: PgPool) {
    let app = setup(db).await;
    let uri = "/api/v1/configurator/expressions/check";
    let (status, r) = post(&app, ADMIN, uri, json!({ "source": "round(x * 2, 1)" })).await;
    assert_eq!(status, StatusCode::OK, "{r}");
    assert_eq!(r["ok"], true);
    assert_eq!(r["type"], "decimal");
    let (_, r) = post(&app, ADMIN, uri, json!({ "source": "1 +" })).await;
    assert_eq!(r["ok"], false);
    assert_eq!(r["errors"][0]["start"], 3);
    // With the definition: names of the item scope and table columns are known.
    let def = demo()["definition"].clone();
    let (_, r) = post(&app, ADMIN, uri, json!({ "source": "lookup('motors', {phases: phases, kw: power_kw}).size", "definition": def, "scope": "item" })).await;
    assert_eq!(r["ok"], true, "{r}");
    assert_eq!(r["type"], "text");
    let (_, r) = post(&app, ADMIN, uri, json!({ "source": "DRV-{motor.sise}", "template": true, "definition": def, "scope": "item" })).await;
    assert_eq!(r["ok"], false, "{r}");
    assert!(r["errors"][0]["message"]
        .as_str()
        .unwrap()
        .contains("no field sise"));
    assert_eq!(r["errors"][0]["start"], 5);
    let (_, r) = post(
        &app,
        ADMIN,
        uri,
        json!({ "source": "power_kw", "definition": def }),
    )
    .await;
    assert!(
        r["errors"][0]["message"]
            .as_str()
            .unwrap()
            .contains("unknown name power_kw"),
        "{r}"
    );
    // A draft with problems elsewhere (here a broken output rule) still checks names loosely.
    let mut broken = def.clone();
    broken["outputs"][0]["quantity"] = json!("ceil(length_m * )");
    let (status, r) = post(
        &app,
        ADMIN,
        uri,
        json!({ "source": "length_m * 2 > 1 and lookup('motors', {phases: phases, kw: 1}).size == '05'", "definition": broken, "scope": "item" }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{r}");
    assert_eq!(r["ok"], true, "{r}");
    let (_, r) = post(
        &app,
        ADMIN,
        uri,
        json!({ "source": "lenght_m", "definition": broken, "scope": "item" }),
    )
    .await;
    assert_eq!(r["ok"], false, "{r}");
    // A product filter sees `p` when the editor names it as a local.
    let (_, r) = post(
        &app,
        ADMIN,
        uri,
        json!({ "source": "p.attr('kw') >= 1", "definition": def, "locals": ["p"] }),
    )
    .await;
    assert_eq!(r["ok"], true, "{r}");
    let (status, f) = get(&app, SALES, "/api/v1/configurator/functions").await;
    assert_eq!(status, StatusCode::OK);
    assert!(f.as_array().unwrap().iter().any(|x| x["name"] == "chunks"));
    // Sales may use configurators but not check formulas.
    assert_eq!(
        post(&app, SALES, uri, json!({ "source": "1" })).await.0,
        StatusCode::FORBIDDEN
    );
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_saved_configuration_becomes_a_quotation(db: PgPool) {
    let app = setup(db.clone()).await;
    let (model, rev) = import_and_activate(&app).await;

    // Saved without a customer it cannot be quoted yet.
    let (status, cfg) = post(
        &app,
        SALES,
        "/api/v1/configurator/configurations",
        json!({ "model_id": model, "name": "Line A", "inputs": sample() }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{cfg}");
    assert_eq!(cfg["revision_id"], rev.as_str());
    assert_eq!(cfg["result"]["lines"].as_array().unwrap().len(), 13);
    let id = cfg["id"].as_str().unwrap().to_string();
    let uri = format!("/api/v1/configurator/configurations/{id}");
    let (status, e) = post(&app, SALES, &format!("{uri}/quote"), json!({})).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{e}");

    let mut body = json!({ "customer_id": ALPHA, "name": "Line A", "inputs": sample() });
    let (status, cfg) = call(&app, SALES, Method::PUT, &uri, Some(body.clone())).await;
    assert_eq!(status, StatusCode::OK, "{cfg}");
    assert_eq!(cfg["customer_name"], "Alpha Installaties NV");

    let (status, r) = post(&app, SALES, &format!("{uri}/quote"), json!({})).await;
    assert_eq!(status, StatusCode::CREATED, "{r}");
    assert_eq!(r["action"], "created");
    let q = &r["quotation"];
    assert_eq!(q["price_zone_code"], "Z2");
    assert_eq!(q["status"], "draft");
    // Sections from the halls, the installation in its own section.
    let sections: Vec<&str> = q["lines"]
        .as_array()
        .unwrap()
        .iter()
        .filter_map(|l| l["section"].as_str())
        .collect();
    assert!(
        sections.contains(&"Hall 1")
            && sections.contains(&"Hall 2")
            && sections.contains(&"Installation"),
        "{sections:?}"
    );
    // Zone 2 (80 %) prices with Alpha's 5 % general rebate; the coating is 20 % of the motor's
    // list price, as an option line below it.
    let motor = qline(q, "MOT-055", "Hall 1");
    assert_eq!(dec(&motor["list_unit_price"]), dec!(248));
    assert_eq!(dec(&motor["net_unit_price"]), dec!(235.6));
    let pos = motor["position"].as_i64().unwrap();
    let coat = q["lines"]
        .as_array()
        .unwrap()
        .iter()
        .find(|l| l["product_code"] == "COAT-PROT" && l["parent_position"] == pos)
        .unwrap();
    assert_eq!(dec(&coat["percent_of_parent"]), dec!(20));
    assert_eq!(dec(&coat["list_unit_price"]), dec!(49.6));
    assert_eq!(coat["comment"], "Corrosivity class C4");
    let belt = qline(q, "BELT-M", "Hall 1");
    assert_eq!(dec(&belt["quantity"]), dec!(116));
    assert_eq!(belt["comment"], "Hall 1 / segment 1, Hall 1 / segment 2");
    assert_eq!(
        dec(&qline(q, "INSTALL", "Installation")["quantity"]),
        dec!(32)
    );
    let qid = q["id"].as_str().unwrap().to_string();

    // Traceability on the quotation.
    let (source, reference, conf): (String, String, Value) = sqlx::query_as(
        "SELECT import_source, import_external_ref, configuration FROM sales.quotations WHERE id = $1::uuid",
    )
    .bind(&qid)
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(source, "configurator");
    assert_eq!(reference, id);
    assert_eq!(conf["revision_id"], rev.as_str());
    assert_eq!(conf["inputs"]["project"]["phases"], 3);

    // Edited and quoted again: the draft quotation is updated.
    body["inputs"]["items"]["segments"][2]["length_m"] = json!(20);
    let (status, _) = call(&app, SALES, Method::PUT, &uri, Some(body.clone())).await;
    assert_eq!(status, StatusCode::OK);
    let (status, r) = post(&app, SALES, &format!("{uri}/quote"), json!({})).await;
    assert_eq!(status, StatusCode::OK, "{r}");
    assert_eq!(r["action"], "updated");
    assert_eq!(r["quotation"]["id"], qid.as_str());
    assert_eq!(
        dec(&qline(&r["quotation"], "BELT-M", "Hall 2")["quantity"]),
        dec!(41)
    );
    let (_, cfg) = get(&app, SALES, &uri).await;
    assert_eq!(cfg["quotation_id"], qid.as_str());

    // After sending, quoting again creates the next revision of the same quotation.
    let (status, sent) = post(
        &app,
        SALES,
        &format!("/api/v1/quotations/{qid}/send"),
        json!({}),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{sent}");
    body["inputs"]["project"]["coating"] = json!(false);
    call(&app, SALES, Method::PUT, &uri, Some(body.clone())).await;
    let (status, r) = post(&app, SALES, &format!("{uri}/quote"), json!({})).await;
    assert_eq!(status, StatusCode::CREATED, "{r}");
    assert_eq!(r["action"], "revised");
    assert_eq!(r["quotation"]["revision"], 2);
    assert_eq!(r["quotation"]["supersedes_id"], qid.as_str());
    assert!(!r["quotation"]["lines"]
        .as_array()
        .unwrap()
        .iter()
        .any(|l| l["product_code"] == "COAT-PROT"));

    // A configuration with errors is not quoted.
    body["inputs"]["items"]["segments"][0]["length_m"] = json!(500);
    call(&app, SALES, Method::PUT, &uri, Some(body.clone())).await;
    let (status, e) = post(&app, SALES, &format!("{uri}/quote"), json!({})).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    assert!(
        e["message"]
            .as_str()
            .unwrap()
            .contains("Length must be within 0.5..100 m"),
        "{e}"
    );

    let (_, list) = get(
        &app,
        SALES,
        &format!("/api/v1/configurator/configurations?model_id={model}"),
    )
    .await;
    assert_eq!(list.as_array().unwrap().len(), 1);
    assert_eq!(list[0]["model_name"], "Conveyor line");
    assert_eq!(list[0]["revision"], 1);
    assert_eq!(list[0]["newer_revision"], Value::Null);
    // The configuration now points at the quotation's second revision (same number).
    assert_ne!(list[0]["quotation_id"], qid.as_str());
    let (_, q1) = get(&app, SALES, &format!("/api/v1/quotations/{qid}")).await;
    assert_eq!(list[0]["quotation_number"], q1["number"], "{list}");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn evaluated_lines_name_their_products_in_the_requested_language(db: PgPool) {
    let app = setup(db).await;
    let (_, rev) = import_and_activate(&app).await;
    let (status, _) = call(
        &app,
        ADMIN,
        Method::PUT,
        &format!("/api/v1/products/{MOT_055}/translations"),
        Some(json!([{ "language": "nl", "name": "Motor 0,55 kW (nl)" }])),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let mut inputs = sample();
    inputs["pins"] = json!([
        { "name": "motor_code", "table": "segments", "row": 1, "value": "MOT-055", "calculated": "MOT-110" }
    ]);
    let uri = format!("/api/v1/configurator/revisions/{rev}/evaluate");
    let (status, nl) = post(&app, SALES, &format!("{uri}?language=nl"), inputs.clone()).await;
    assert_eq!(status, StatusCode::OK, "{nl}");
    assert_eq!(nl["lines"][2]["product_name"], "Motor 0,55 kW (nl)");
    // No translation in German: the base name.
    let (_, de) = post(&app, SALES, &format!("{uri}?language=de"), inputs).await;
    let base = de["lines"][2]["product_name"].as_str().unwrap();
    assert_ne!(base, "Motor 0,55 kW (nl)");
    assert_eq!(de["lines"][2]["product_id"], MOT_055);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn configured_quotation_lines_preview_with_their_structure(db: PgPool) {
    // What the quotation screen sends back while editing a configured draft: parent positions,
    // percent-of-parent and sections, as loaded from the quotation.
    let app = setup(db).await;
    let (model, _) = import_and_activate(&app).await;
    let (_, cfg) = post(
        &app,
        SALES,
        "/api/v1/configurator/configurations",
        json!({ "model_id": model, "customer_id": ALPHA, "inputs": sample() }),
    )
    .await;
    let (status, r) = post(
        &app,
        SALES,
        &format!(
            "/api/v1/configurator/configurations/{}/quote",
            cfg["id"].as_str().unwrap()
        ),
        json!({}),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{r}");
    let q = &r["quotation"];
    let lines: Vec<Value> = q["lines"]
        .as_array()
        .unwrap()
        .iter()
        .filter(|l| l["product_id"].is_string())
        .map(|l| {
            let mut v = json!({
                "product_id": l["product_id"],
                "quantity": l["quantity"],
                "line_discount_percent": l["line_discount_percent"],
                "description": l["description"],
                "section": l["section"],
                "comment": l["comment"],
            });
            if !l["parent_position"].is_null() {
                v["parent_position"] = l["parent_position"].clone();
                v["percent_of_parent"] = l["percent_of_parent"].clone();
                v["percent_base"] = l["percent_base"].clone();
            }
            v
        })
        .collect();
    assert!(lines.iter().any(|l| !l["percent_of_parent"].is_null()));
    let (status, p) = post(
        &app,
        SALES,
        "/api/v1/pricing/preview",
        json!({ "customer_id": ALPHA, "quotation_id": q["id"], "lines": lines }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{p}");
    assert_eq!(p["total"], q["total"]);
    // Without the structure the percentage product has no price of its own (the old bug).
    let flat: Vec<Value> = lines
        .iter()
        .map(|l| json!({ "product_id": l["product_id"], "quantity": l["quantity"] }))
        .collect();
    let (status, _) = post(
        &app,
        SALES,
        "/api/v1/pricing/preview",
        json!({ "customer_id": ALPHA, "lines": flat }),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn configurations_stay_on_their_revision(db: PgPool) {
    let app = setup(db).await;
    let (model, rev1) = import_and_activate(&app).await;
    let (_, cfg) = post(
        &app,
        SALES,
        "/api/v1/configurator/configurations",
        json!({ "model_id": model, "customer_id": ALPHA, "inputs": sample() }),
    )
    .await;
    let uri = format!(
        "/api/v1/configurator/configurations/{}",
        cfg["id"].as_str().unwrap()
    );

    // Revision 2: belts get 10 % extra.
    let (status, r2) = post(
        &app,
        ADMIN,
        &format!("/api/v1/configurator/models/{model}/revisions"),
        json!({}),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{r2}");
    let rev2 = r2["id"].as_str().unwrap().to_string();
    let mut def = r2["definition"].clone();
    def["outputs"][0]["quantity"] = json!("ceil((length_m * 2 + 1) * 1.1)");
    let (status, _) = call(
        &app,
        ADMIN,
        Method::PUT,
        &format!("/api/v1/configurator/revisions/{rev2}"),
        Some(json!({ "definition": def })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    // Sales cannot evaluate a draft, designers can.
    assert_eq!(
        post(
            &app,
            SALES,
            &format!("/api/v1/configurator/revisions/{rev2}/evaluate"),
            sample()
        )
        .await
        .0,
        StatusCode::FORBIDDEN
    );
    assert_eq!(
        post(
            &app,
            ADMIN,
            &format!("/api/v1/configurator/revisions/{rev2}/evaluate"),
            sample()
        )
        .await
        .0,
        StatusCode::OK
    );
    let (status, _) = post(
        &app,
        ADMIN,
        &format!("/api/v1/configurator/revisions/{rev2}/activate"),
        json!({}),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (_, m) = get(&app, SALES, &format!("/api/v1/configurator/models/{model}")).await;
    let statuses: Vec<&str> = m["revisions"]
        .as_array()
        .unwrap()
        .iter()
        .map(|r| r["status"].as_str().unwrap())
        .collect();
    assert_eq!(statuses, ["active", "obsolete"]);

    // The saved configuration stays on revision 1 and is offered the upgrade.
    let (_, c) = get(&app, SALES, &uri).await;
    assert_eq!(c["revision_id"], rev1.as_str());
    assert_eq!(c["revision_status"], "obsolete");
    assert_eq!(c["newer_revision_id"], rev2.as_str());
    let (status, r) = post(&app, SALES, &format!("{uri}/quote"), json!({})).await;
    assert_eq!(status, StatusCode::CREATED, "{r}");
    assert_eq!(
        dec(&qline(&r["quotation"], "BELT-M", "Hall 1")["quantity"]),
        dec!(116)
    );
    // Upgrading moves it to revision 2; an obsolete revision cannot be chosen.
    let (status, _) = call(
        &app,
        SALES,
        Method::PUT,
        &uri,
        Some(json!({ "customer_id": ALPHA, "inputs": sample(), "revision_id": rev1 })),
    )
    .await;
    assert_eq!(
        status,
        StatusCode::OK,
        "staying on its own revision is allowed"
    );
    let (status, c) = call(
        &app,
        SALES,
        Method::PUT,
        &uri,
        Some(json!({ "customer_id": ALPHA, "inputs": sample(), "revision_id": rev2 })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{c}");
    assert_eq!(c["revision"], 2);
    assert_eq!(c["newer_revision_id"], Value::Null);
    let (_, r) = post(&app, SALES, &format!("{uri}/quote"), json!({})).await;
    assert_eq!(r["action"], "updated");
    assert_eq!(
        dec(&qline(&r["quotation"], "BELT-M", "Hall 1")["quantity"]),
        dec!(129)
    );
    // A new configuration cannot be made with an obsolete revision.
    let (status, _) = post(
        &app,
        SALES,
        "/api/v1/configurator/configurations",
        json!({ "revision_id": rev1, "inputs": sample() }),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    // A withdrawn configurator makes no new configurations, by model or by revision; the saved
    // one stays usable.
    let (status, m) = call(
        &app,
        ADMIN,
        Method::PUT,
        &format!("/api/v1/configurator/models/{model}"),
        Some(json!({ "name": m["name"], "active": false })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{m}");
    for body in [
        json!({ "model_id": model, "inputs": sample() }),
        json!({ "revision_id": rev2, "inputs": sample() }),
    ] {
        let (status, e) = post(&app, SALES, "/api/v1/configurator/configurations", body).await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{e}");
    }
    let (status, c) = call(
        &app,
        SALES,
        Method::PUT,
        &uri,
        Some(json!({ "customer_id": ALPHA, "inputs": sample() })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{c}");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn permissions_and_product_attributes(db: PgPool) {
    let app = setup(db.clone()).await;
    // Sales cannot design.
    for (m, uri, body) in [
        (
            Method::POST,
            "/api/v1/configurator/models/import",
            Some(demo()),
        ),
        (
            Method::POST,
            "/api/v1/configurator/models",
            Some(json!({ "code": "X", "name": "X" })),
        ),
    ] {
        assert_eq!(
            call(&app, SALES, m, uri, body).await.0,
            StatusCode::FORBIDDEN,
            "{uri}"
        );
    }
    let (model, rev) = import_and_activate(&app).await;
    let (status, _) = post(
        &app,
        SALES,
        &format!("/api/v1/configurator/models/{model}/revisions"),
        json!({}),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    // A viewer can neither use nor read configurators.
    for (m, uri, body) in [
        (Method::GET, "/api/v1/configurator/models".to_string(), None),
        (
            Method::POST,
            format!("/api/v1/configurator/revisions/{rev}/evaluate"),
            Some(sample()),
        ),
        (
            Method::GET,
            "/api/v1/configurator/configurations".to_string(),
            None,
        ),
        (
            Method::POST,
            "/api/v1/configurator/configurations".to_string(),
            Some(json!({ "model_id": model })),
        ),
    ] {
        assert_eq!(
            call(&app, VIEWER, m, &uri, body).await.0,
            StatusCode::FORBIDDEN,
            "{uri}"
        );
    }
    // Switching the module off closes it for everyone.
    sqlx::query("UPDATE core.companies SET disabled_modules = '{configurator}'")
        .execute(&db)
        .await
        .unwrap();
    let (status, body) = get(&app, SALES, "/api/v1/configurator/models").await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    assert!(
        body["message"]
            .as_str()
            .unwrap()
            .contains("module configurator is disabled"),
        "{body}"
    );
    sqlx::query("UPDATE core.companies SET disabled_modules = '{}'")
        .execute(&db)
        .await
        .unwrap();

    // Product attributes: read by everyone with products.read, replaced (and audited) by
    // product writers.
    let uri = format!("/api/v1/products/{MOT_055}/attributes");
    let (status, attrs) = get(&app, SALES, &uri).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(
        attrs,
        json!([
            { "key": "kw", "kind": "number", "value": "0.55", "unit": "kW" },
            { "key": "size", "kind": "text", "value": "05", "unit": null }
        ])
    );
    let new = json!([
        { "key": "kw", "kind": "number", "value": "0.10", "unit": "kW" },
        { "key": "size", "kind": "text", "value": "05" },
        { "key": "ip66", "kind": "boolean", "value": "true" }
    ]);
    assert_eq!(
        call(&app, SALES, Method::PUT, &uri, Some(new.clone()))
            .await
            .0,
        StatusCode::FORBIDDEN
    );
    let (status, saved) = call(&app, ADMIN, Method::PUT, &uri, Some(new)).await;
    assert_eq!(status, StatusCode::OK, "{saved}");
    assert_eq!(saved.as_array().unwrap().len(), 3);
    assert_eq!(saved[0]["key"], "ip66");
    for bad in [
        json!([{ "key": "kw", "kind": "number", "value": "fast" }]),
        json!([{ "key": "kw", "kind": "number", "value": "1" }, { "key": "kw", "kind": "number", "value": "2" }]),
        json!([{ "key": "9x", "kind": "text", "value": "a" }]),
    ] {
        assert_eq!(
            call(&app, ADMIN, Method::PUT, &uri, Some(bad.clone()))
                .await
                .0,
            StatusCode::UNPROCESSABLE_ENTITY,
            "{bad}"
        );
    }
    let audited: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM audit.events WHERE action = 'attributes_replaced'",
    )
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(audited, 1);
    // The evaluator sees the new attribute at once: 0.10 kW is below the 0.178 kW segment.
    let (_, ev) = post(
        &app,
        SALES,
        &format!("/api/v1/configurator/revisions/{rev}/evaluate"),
        sample(),
    )
    .await;
    assert!(ev["issues"]
        .as_array()
        .unwrap()
        .iter()
        .any(|i| i["code"] == "motor_too_small"));
    assert_eq!(
        get(
            &app,
            SALES,
            "/api/v1/products/00000000-0000-0000-0000-000000000000/attributes"
        )
        .await
        .0,
        StatusCode::NOT_FOUND
    );
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_dev_seed_loads_the_demo_configurator(db: PgPool) {
    assert!(tradocraft_api::seed_if_empty(&db).await.unwrap());
    let (code, status): (String, String) = sqlx::query_as(
        "SELECT m.code, r.status FROM configurator.models m JOIN configurator.model_revisions r ON r.model_id = m.id WHERE m.code = 'CONVEYOR-LINE'",
    )
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(
        (code.as_str(), status.as_str()),
        ("CONVEYOR-LINE", "active")
    );
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn range_attributes_do_not_change_evaluation(db: PgPool) {
    let app = setup(db.clone()).await;
    let (_, rev) = import_and_activate(&app).await;
    let uri = format!("/api/v1/configurator/revisions/{rev}/evaluate");
    let (status, before) = post(&app, SALES, &uri, sample()).await;
    assert_eq!(status, StatusCode::OK, "{before}");

    // Add a suitability range next to the existing attributes of the motor.
    let attrs = format!("/api/v1/products/{MOT_055}/attributes");
    let (_, current) = get(&app, SALES, &attrs).await;
    let mut all = current.as_array().unwrap().clone();
    all.push(json!({ "key": "dial_size", "kind": "range", "value": "",
                     "value_min": "600", "value_max": "1250", "unit": "mm" }));
    let (status, saved) = call(&app, ADMIN, Method::PUT, &attrs, Some(json!(all))).await;
    assert_eq!(status, StatusCode::OK, "{saved}");
    assert!(saved
        .as_array()
        .unwrap()
        .iter()
        .any(|a| a["kind"] == "range"));

    let (status, after) = post(&app, SALES, &uri, sample()).await;
    assert_eq!(status, StatusCode::OK, "{after}");
    assert_eq!(before, after, "a range row must not change the evaluation");

    // Formulas see the other attributes of the product but never the range key.
    let mut conn = db.acquire().await.unwrap();
    let catalog = tradocraft_configurator::store::load_catalog(&mut conn)
        .await
        .unwrap();
    let product = &catalog.products["MOT-055"];
    assert!(product.attributes.contains_key("kw"));
    assert!(!product.attributes.contains_key("dial_size"));
}
