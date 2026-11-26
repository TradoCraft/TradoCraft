//! Repairs: departments made by the admin, the workflow and who may do what, announcing a repair
//! from a ticket, photos, and the customer's side in the portal.

mod common;

use axum::http::{Method, StatusCode};
use common::{call, call_raw, jpeg, portal_login, raw, setup, Who};
use serde_json::{json, Value};
use sqlx::PgPool;

const ALPHA: &str = "00000000-0000-7000-8000-000000000401";
const BETA: &str = "00000000-0000-7000-8000-000000000402";
const ELECTRONICS: &str = "00000000-0000-7000-8000-000000000701";
const MECHANICAL: &str = "00000000-0000-7000-8000-000000000703";
const ELS: &str = "00000000-0000-7000-8000-000000000109"; // electronics@example.com, member of ELECTRONICS
const MAX: &str = "00000000-0000-7000-8000-00000000010a"; // mechanic@example.com, member of MECHANICAL
const ADMIN: &str = "admin@example.com";
const SUPPORT: &str = "support@example.com"; // receives and routes
const SALES: &str = "sales@example.com";
const ELEC_USER: &str = "electronics@example.com";
const MECH_USER: &str = "mechanic@example.com";
const VIEWER: &str = "viewer@example.com";
const JAN: &str = "jan.peeters@alpha.example"; // portal, scope customer
const SOFIE: &str = "sofie.maes@alpha.example"; // portal, scope own

async fn post(app: &axum::Router, user: &str, uri: &str, body: Value) -> (StatusCode, Value) {
    call(app, user, Method::POST, uri, Some(body)).await
}
async fn get(app: &axum::Router, user: &str, uri: &str) -> (StatusCode, Value) {
    call(app, user, Method::GET, uri, None).await
}

async fn new_repair(app: &axum::Router, extra: Value) -> Value {
    let mut body = json!({ "customer_id": ALPHA, "product_description": "Pump 5 kW", "serial_number": "SN-1", "fault_description": "Does not start" });
    body.as_object_mut()
        .unwrap()
        .extend(extra.as_object().unwrap().clone());
    let (status, r) = post(app, SUPPORT, "/api/v1/repairs", body).await;
    assert_eq!(status, StatusCode::CREATED, "{r}");
    r
}

fn id(r: &Value) -> &str {
    r["repair"]["id"].as_str().unwrap()
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn only_the_admin_creates_departments_and_they_can_be_retired_when_empty(db: PgPool) {
    let app = setup(db).await;
    let (status, list) = get(&app, SUPPORT, "/api/v1/departments").await;
    assert_eq!(status, StatusCode::OK);
    let names: Vec<&str> = list
        .as_array()
        .unwrap()
        .iter()
        .map(|d| d["name"].as_str().unwrap())
        .collect();
    assert_eq!(names, ["Electronics", "Electric", "Mechanical workshop"]);
    assert_eq!(list[0]["members"][0]["display_name"], "Els Electronics");

    let body = json!({ "code": "calibration", "name": "Calibration", "sort_order": 4, "member_user_ids": [ELS] });
    for u in [SUPPORT, SALES, ELEC_USER, VIEWER] {
        assert_eq!(
            post(&app, u, "/api/v1/departments", body.clone()).await.0,
            StatusCode::FORBIDDEN,
            "{u}"
        );
    }
    let (status, d) = post(&app, ADMIN, "/api/v1/departments", body.clone()).await;
    assert_eq!(status, StatusCode::CREATED, "{d}");
    assert_eq!(d["code"], "CALIBRATION", "codes are upper-case");
    assert_eq!(d["members"].as_array().unwrap().len(), 1);
    assert_eq!(
        post(&app, ADMIN, "/api/v1/departments", body).await.0,
        StatusCode::CONFLICT
    );
    assert_eq!(
        post(
            &app,
            ADMIN,
            "/api/v1/departments",
            json!({ "code": "", "name": "x" })
        )
        .await
        .0,
        StatusCode::UNPROCESSABLE_ENTITY
    );
    let (status, _) = post(&app, ADMIN, "/api/v1/departments", json!({ "code": "X", "name": "X", "member_user_ids": ["00000000-0000-7000-8000-0000000000aa"] })).await;
    assert_eq!(
        status,
        StatusCode::UNPROCESSABLE_ENTITY,
        "members must be colleagues"
    );

    // Members and name can change; a department with repairs cannot be switched off.
    let did = d["id"].as_str().unwrap();
    let uri = format!("/api/v1/departments/{did}");
    let update = |active: bool| json!({ "code": "CAL", "name": "Calibration lab", "active": active, "member_user_ids": [ELS, MAX] });
    let (status, u) = call(&app, ADMIN, Method::PUT, &uri, Some(update(true))).await;
    assert_eq!(status, StatusCode::OK, "{u}");
    assert_eq!(u["members"].as_array().unwrap().len(), 2);
    assert_eq!(
        call(&app, SUPPORT, Method::PUT, &uri, Some(update(true)))
            .await
            .0,
        StatusCode::FORBIDDEN
    );

    let r = new_repair(&app, json!({})).await;
    assert_eq!(
        post(
            &app,
            SUPPORT,
            &format!("/api/v1/repairs/{}/route", id(&r)),
            json!({ "department_id": did })
        )
        .await
        .0,
        StatusCode::OK
    );
    let (status, e) = call(&app, ADMIN, Method::PUT, &uri, Some(update(false))).await;
    assert_eq!(status, StatusCode::CONFLICT, "{e}");
    assert!(e["message"]
        .as_str()
        .unwrap()
        .contains("route them elsewhere"));
    // Once it has moved on, the department can be retired, and nothing can be routed to it.
    post(
        &app,
        SUPPORT,
        &format!("/api/v1/repairs/{}/route", id(&r)),
        json!({ "department_id": ELECTRONICS }),
    )
    .await;
    assert_eq!(
        call(&app, ADMIN, Method::PUT, &uri, Some(update(false)))
            .await
            .0,
        StatusCode::OK
    );
    let r2 = new_repair(&app, json!({})).await;
    assert_eq!(
        post(
            &app,
            SUPPORT,
            &format!("/api/v1/repairs/{}/route", id(&r2)),
            json!({ "department_id": did })
        )
        .await
        .0,
        StatusCode::UNPROCESSABLE_ENTITY
    );
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_repair_is_routed_worked_handed_over_and_shipped(db: PgPool) {
    let app = setup(db).await;
    let r = new_repair(
        &app,
        json!({ "priority": "high", "warranty": "in_warranty", "customer_reference": "RMA-77" }),
    )
    .await;
    let rid = id(&r);
    assert_eq!(r["repair"]["status"], "received");
    assert!(
        r["repair"]["number"]
            .as_str()
            .unwrap()
            .starts_with("R2026-")
            || r["repair"]["number"].as_str().unwrap().starts_with('R')
    );
    assert!(r["repair"]["received_at"].is_string());
    let status_uri = format!("/api/v1/repairs/{rid}/status");
    let route_uri = format!("/api/v1/repairs/{rid}/route");

    // Work cannot start before triage; only those who triage may route.
    assert_eq!(
        post(
            &app,
            SUPPORT,
            &status_uri,
            json!({ "status": "in_progress" })
        )
        .await
        .0,
        StatusCode::CONFLICT
    );
    assert_eq!(
        post(
            &app,
            ELEC_USER,
            &route_uri,
            json!({ "department_id": ELECTRONICS })
        )
        .await
        .0,
        StatusCode::FORBIDDEN
    );
    assert_eq!(
        post(&app, SUPPORT, &status_uri, json!({ "status": "routed" }))
            .await
            .0,
        StatusCode::UNPROCESSABLE_ENTITY
    );
    // A colleague from a department cannot touch a repair that nobody routed to it.
    assert_eq!(
        post(
            &app,
            ELEC_USER,
            &format!("/api/v1/repairs/{rid}/notes"),
            json!({ "note": "mine" })
        )
        .await
        .0,
        StatusCode::FORBIDDEN
    );

    let (status, routed) = post(
        &app,
        SUPPORT,
        &route_uri,
        json!({ "department_id": ELECTRONICS, "note": "Looks like the controller" }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{routed}");
    assert_eq!(routed["repair"]["status"], "routed");
    assert_eq!(routed["repair"]["department_name"], "Electronics");
    // The assignee must work in the department.
    assert_eq!(
        post(
            &app,
            SUPPORT,
            &route_uri,
            json!({ "department_id": ELECTRONICS, "assigned_user_id": MAX })
        )
        .await
        .0,
        StatusCode::UNPROCESSABLE_ENTITY
    );

    // Mechanics do not work on electronics; electronics does, and takes it in hand.
    assert_eq!(
        post(
            &app,
            MECH_USER,
            &status_uri,
            json!({ "status": "in_progress" })
        )
        .await
        .0,
        StatusCode::FORBIDDEN
    );
    let (status, w) = post(
        &app,
        ELEC_USER,
        &status_uri,
        json!({ "status": "in_progress" }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{w}");
    assert_eq!(
        w["repair"]["assigned_name"], "Els Electronics",
        "taking it in hand assigns it"
    );
    assert_eq!(
        post(
            &app,
            ELEC_USER,
            &format!("/api/v1/repairs/{rid}/notes"),
            json!({ "note": "Controller board burnt" })
        )
        .await
        .0,
        StatusCode::CREATED
    );
    assert_eq!(
        post(
            &app,
            ELEC_USER,
            &status_uri,
            json!({ "status": "waiting_parts", "note": "Ordered board" })
        )
        .await
        .0,
        StatusCode::OK
    );
    assert_eq!(
        post(
            &app,
            ELEC_USER,
            &status_uri,
            json!({ "status": "in_progress" })
        )
        .await
        .0,
        StatusCode::OK
    );

    // It turns out to be mechanical: hand it over; it waits in the other department, unassigned.
    let (status, h) = post(
        &app,
        SUPPORT,
        &route_uri,
        json!({ "department_id": MECHANICAL, "note": "Shaft is bent" }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{h}");
    assert_eq!(h["repair"]["status"], "routed");
    assert_eq!(h["repair"]["department_name"], "Mechanical workshop");
    assert_eq!(h["repair"]["assigned_user_id"], Value::Null);
    assert_eq!(
        post(
            &app,
            ELEC_USER,
            &status_uri,
            json!({ "status": "completed" })
        )
        .await
        .0,
        StatusCode::FORBIDDEN,
        "no longer theirs"
    );
    assert_eq!(
        post(
            &app,
            MECH_USER,
            &status_uri,
            json!({ "status": "in_progress" })
        )
        .await
        .0,
        StatusCode::OK
    );
    let (status, done) = post(
        &app,
        MECH_USER,
        &status_uri,
        json!({ "status": "completed", "note": "Shaft replaced, tested" }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{done}");
    assert!(done["repair"]["completed_at"].is_string());

    // Not fixed after all: back into work (completed_at is cleared); then fixed and shipped.
    assert_eq!(
        post(
            &app,
            MECH_USER,
            &status_uri,
            json!({ "status": "in_progress" })
        )
        .await
        .1["repair"]["completed_at"],
        Value::Null
    );
    post(
        &app,
        MECH_USER,
        &status_uri,
        json!({ "status": "completed" }),
    )
    .await;
    assert_eq!(
        post(&app, SUPPORT, &status_uri, json!({ "status": "cancelled" }))
            .await
            .0,
        StatusCode::CONFLICT
    );
    let (status, shipped) = post(&app, SUPPORT, &status_uri, json!({ "status": "shipped" })).await;
    assert_eq!(status, StatusCode::OK, "{shipped}");
    for to in ["in_progress", "cancelled", "received"] {
        assert_eq!(
            post(&app, SUPPORT, &status_uri, json!({ "status": to }))
                .await
                .0,
            StatusCode::CONFLICT,
            "{to}"
        );
    }
    assert_eq!(
        post(
            &app,
            SUPPORT,
            &route_uri,
            json!({ "department_id": ELECTRONICS })
        )
        .await
        .0,
        StatusCode::CONFLICT
    );

    // The history tells the story, with who did it and where it went.
    let (_, d) = get(&app, SUPPORT, &format!("/api/v1/repairs/{rid}")).await;
    let story: Vec<String> = d["events"]
        .as_array()
        .unwrap()
        .iter()
        .map(|e| {
            format!(
                "{}:{}>{}",
                e["kind"].as_str().unwrap(),
                e["from_department"].as_str().unwrap_or("-"),
                e["to_department"].as_str().unwrap_or("-")
            )
        })
        .collect();
    assert!(
        story.contains(&"routed:-&gt;Electronics".replace("&gt;", ">")),
        "{story:?}"
    );
    assert!(
        story.contains(&"routed:Electronics>Mechanical workshop".to_string()),
        "{story:?}"
    );
    assert!(d["events"]
        .as_array()
        .unwrap()
        .iter()
        .any(|e| e["note"] == "Controller board burnt" && e["actor_name"] == "Els Electronics"));

    // Lists: by department, by assignee, unrouted, and the viewer may read but not change.
    let (_, open) = get(&app, SUPPORT, "/api/v1/repairs?status=open").await;
    assert_eq!(open["total"], 0, "shipped is not open");
    let r3 = new_repair(&app, json!({})).await;
    let (_, none) = get(&app, SUPPORT, "/api/v1/repairs?department=none").await;
    assert_eq!(none["items"][0]["id"], r3["repair"]["id"]);
    post(
        &app,
        SUPPORT,
        &format!("/api/v1/repairs/{}/route", id(&r3)),
        json!({ "department_id": MECHANICAL, "assigned_user_id": MAX }),
    )
    .await;
    let (_, mine) = get(&app, MECH_USER, "/api/v1/repairs?assigned=me").await;
    assert_eq!(
        mine["total"], 2,
        "the shipped one he worked on, and the one assigned to him"
    );
    let (_, dept) = get(
        &app,
        MECH_USER,
        &format!("/api/v1/repairs?department={MECHANICAL}&status=routed"),
    )
    .await;
    assert_eq!(dept["total"], 1);
    let (_, found) = get(&app, SUPPORT, "/api/v1/repairs?q=sn-1").await;
    assert_eq!(found["total"], 2, "searches the serial number");
    assert_eq!(
        get(&app, VIEWER, &format!("/api/v1/repairs/{rid}")).await.0,
        StatusCode::OK
    );
    assert_eq!(
        post(
            &app,
            VIEWER,
            &format!("/api/v1/repairs/{}/notes", id(&r3)),
            json!({ "note": "x" })
        )
        .await
        .0,
        StatusCode::FORBIDDEN
    );
    assert_eq!(
        get(&app, "technician@example.com", "/api/v1/repairs")
            .await
            .0,
        StatusCode::FORBIDDEN,
        "technicians do not see the workshop"
    );
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_repair_announced_in_a_ticket_is_linked_and_received_later(db: PgPool) {
    let app = setup(db).await;
    // The customer writes that a pump is coming and a controller too.
    let raw_mail = b"From: Jan <jan.peeters@alpha.example>\r\nTo: sales@example.com\r\nSubject: We will send in a pump\r\nContent-Type: text/plain; charset=utf-8\r\n\r\nHello, our pump does not start. We send it tomorrow. Thanks\r\n".to_vec();
    let (_, m) = call_raw(
        &app,
        SUPPORT,
        "/api/v1/helpdesk/inbound",
        "message/rfc822",
        raw_mail,
    )
    .await;
    let ticket = m["ticket_id"].as_str().unwrap();

    // Customer and person come from the ticket; the fault defaults to its subject.
    let (status, r) = post(
        &app,
        SUPPORT,
        "/api/v1/repairs",
        json!({ "ticket_id": ticket, "announced": true, "product_description": "Pump 5 kW" }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{r}");
    let rep = &r["repair"];
    assert_eq!(rep["status"], "announced");
    assert_eq!(rep["customer_id"], ALPHA);
    assert_eq!(rep["contact_name"], "Jan Peeters");
    assert_eq!(rep["fault_description"], "We will send in a pump");
    assert_eq!(rep["ticket_id"], ticket);
    assert_eq!(rep["received_at"], Value::Null, "not here yet");

    // The ticket shows an internal note, and lists its repairs (it may announce several).
    let (_, t) = get(&app, SUPPORT, &format!("/api/v1/tickets/{ticket}")).await;
    assert!(
        t["articles"]
            .as_array()
            .unwrap()
            .iter()
            .any(|a| a["kind"] == "note"
                && a["body"]
                    .as_str()
                    .unwrap()
                    .contains("registered (announced)")),
        "{t}"
    );
    post(&app, SUPPORT, "/api/v1/repairs", json!({ "ticket_id": ticket, "announced": true, "product_description": "Controller", "fault_description": "No display" })).await;
    let (_, list) = get(&app, SUPPORT, &format!("/api/v1/tickets/{ticket}/repairs")).await;
    assert_eq!(list.as_array().unwrap().len(), 2);

    // It cannot be routed before it arrives. Receiving it stamps the date; then it can be routed.
    let rid = rep["id"].as_str().unwrap();
    assert_eq!(
        post(
            &app,
            SUPPORT,
            &format!("/api/v1/repairs/{rid}/route"),
            json!({ "department_id": ELECTRONICS })
        )
        .await
        .0,
        StatusCode::CONFLICT
    );
    let (status, got) = post(
        &app,
        SUPPORT,
        &format!("/api/v1/repairs/{rid}/status"),
        json!({ "status": "received" }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{got}");
    assert!(got["repair"]["received_at"].is_string());
    assert_eq!(
        post(
            &app,
            SUPPORT,
            &format!("/api/v1/repairs/{rid}/route"),
            json!({ "department_id": ELECTRONICS })
        )
        .await
        .0,
        StatusCode::OK
    );
    // Sent back to triage leaves the department.
    let (_, back) = post(
        &app,
        SUPPORT,
        &format!("/api/v1/repairs/{rid}/status"),
        json!({ "status": "received", "note": "wrong department" }),
    )
    .await;
    assert_eq!(back["repair"]["department_id"], Value::Null);

    // Mismatches are refused.
    let (status, _) = post(
        &app,
        SUPPORT,
        "/api/v1/repairs",
        json!({ "ticket_id": ticket, "customer_id": BETA, "fault_description": "x" }),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(
        post(
            &app,
            SUPPORT,
            "/api/v1/repairs",
            json!({ "fault_description": "x" })
        )
        .await
        .0,
        StatusCode::UNPROCESSABLE_ENTITY,
        "no customer"
    );
    assert_eq!(
        post(
            &app,
            SUPPORT,
            "/api/v1/repairs",
            json!({ "customer_id": ALPHA, "fault_description": " " })
        )
        .await
        .0,
        StatusCode::UNPROCESSABLE_ENTITY
    );
    assert_eq!(
        post(
            &app,
            SUPPORT,
            "/api/v1/repairs",
            json!({ "customer_id": ALPHA, "fault_description": "x", "priority": "asap" })
        )
        .await
        .0,
        StatusCode::UNPROCESSABLE_ENTITY
    );
    assert_eq!(
        post(
            &app,
            VIEWER,
            "/api/v1/repairs",
            json!({ "customer_id": ALPHA, "fault_description": "x" })
        )
        .await
        .0,
        StatusCode::FORBIDDEN
    );
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn photos_are_checked_stored_served_and_retries_are_harmless(db: PgPool) {
    let app = setup(db.clone()).await;
    let r = new_repair(&app, json!({})).await;
    let rid = id(&r);
    let up = |q: &str| format!("/api/v1/repairs/{rid}/photos{q}");
    let photo = jpeg(1);
    let client_id = "00000000-0000-7000-8000-0000000000f1";

    let (status, _, body) = raw(
        &app,
        Who::Staff(SUPPORT),
        Method::POST,
        &up(&format!(
            "?caption=Front%20panel&filename=IMG_1.jpg&client_id={client_id}"
        )),
        Some(("application/octet-stream", photo.clone())),
    )
    .await;
    assert_eq!(
        status,
        StatusCode::CREATED,
        "{}",
        String::from_utf8_lossy(&body)
    );
    let d: Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(d["photos"][0]["id"], client_id);
    assert_eq!(d["photos"][0]["caption"], "Front panel");
    assert_eq!(d["photos"][0]["content_type"], "image/jpeg");
    assert_eq!(d["repair"]["photo_count"], 1);

    // The same upload again (a retry) does not add a second photo.
    let (status, _, body) = raw(
        &app,
        Who::Staff(SUPPORT),
        Method::POST,
        &up(&format!("?client_id={client_id}")),
        Some(("application/octet-stream", photo.clone())),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);
    assert_eq!(
        serde_json::from_slice::<Value>(&body).unwrap()["photos"]
            .as_array()
            .unwrap()
            .len(),
        1
    );

    // The image comes back unchanged, as an image, and may not be sniffed as anything else.
    let (status, headers, bytes) = raw(
        &app,
        Who::Staff(VIEWER),
        Method::GET,
        &format!("/api/v1/repairs/{rid}/photos/{client_id}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(bytes, photo);
    assert_eq!(headers["content-type"], "image/jpeg");
    assert_eq!(headers["x-content-type-options"], "nosniff");

    // Things that are not photos are refused, whatever they claim to be.
    for (what, bytes) in [
        ("pdf", b"%PDF-1.7 ...".to_vec()),
        (
            "svg",
            b"<svg xmlns='http://www.w3.org/2000/svg'><script>alert(1)</script></svg>".to_vec(),
        ),
        ("exe", b"MZ\x90\x00".to_vec()),
        ("empty", vec![]),
    ] {
        let (status, _, _) = raw(
            &app,
            Who::Staff(SUPPORT),
            Method::POST,
            &up("?filename=evil.jpg"),
            Some(("image/jpeg", bytes)),
        )
        .await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{what}");
    }
    // Too large for the limit.
    let mut big = jpeg(2);
    big.extend(vec![0u8; 13 * 1024 * 1024]);
    let (status, _, _) = raw(
        &app,
        Who::Staff(SUPPORT),
        Method::POST,
        &up(""),
        Some(("image/jpeg", big)),
    )
    .await;
    assert_eq!(status, StatusCode::PAYLOAD_TOO_LARGE);
    // Just under it works (a big phone photo).
    let mut ok = jpeg(3);
    ok.extend(vec![7u8; 11 * 1024 * 1024]);
    let (status, _, _) = raw(
        &app,
        Who::Staff(SUPPORT),
        Method::POST,
        &up(""),
        Some(("image/jpeg", ok)),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);

    // A photo id cannot be claimed for another repair; photos of one repair are not served under another.
    let r2 = new_repair(&app, json!({})).await;
    let (status, _, _) = raw(
        &app,
        Who::Staff(SUPPORT),
        Method::POST,
        &format!("/api/v1/repairs/{}/photos?client_id={client_id}", id(&r2)),
        Some(("image/jpeg", photo.clone())),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
    let (status, _, _) = raw(
        &app,
        Who::Staff(SUPPORT),
        Method::GET,
        &format!("/api/v1/repairs/{}/photos/{client_id}", id(&r2)),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    // Only people of the right department may add photos; the creator may on their own registration.
    let (status, _, _) = raw(
        &app,
        Who::Staff(ELEC_USER),
        Method::POST,
        &up(""),
        Some(("image/jpeg", jpeg(4))),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    post(
        &app,
        SUPPORT,
        &format!("/api/v1/repairs/{rid}/route"),
        json!({ "department_id": ELECTRONICS }),
    )
    .await;
    let (status, _, _) = raw(
        &app,
        Who::Staff(ELEC_USER),
        Method::POST,
        &up("?caption=Board"),
        Some(("image/jpeg", jpeg(5))),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);
    let (status, _, _) = raw(
        &app,
        Who::Staff(MECH_USER),
        Method::POST,
        &up(""),
        Some(("image/jpeg", jpeg(6))),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, _, _) = raw(
        &app,
        Who::Staff("technician@example.com"),
        Method::GET,
        &format!("/api/v1/repairs/{rid}/photos/{client_id}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_customer_announces_a_repair_with_photos_and_follows_it(db: PgPool) {
    let app = setup(db.clone()).await;
    let jan = portal_login(&app, &db, JAN).await;
    let sofie = portal_login(&app, &db, SOFIE).await;
    let p = |m: Method, uri: &str, b: Option<Value>| {
        let app = app.clone();
        let jan = jan.clone();
        let uri = format!("/api/v1/portal{uri}");
        async move { common::call_portal(&app, Some(&jan), m, &uri, b).await }
    };

    let (status, d) = p(Method::POST, "/repairs", Some(json!({ "product_description": "Pump 5 kW", "serial_number": "SN-9", "fault_description": "Leaks", "customer_reference": "PO-1" }))).await;
    assert_eq!(status, StatusCode::CREATED, "{d}");
    assert_eq!(d["repair"]["status"], "announced");
    assert_eq!(d["repair"]["contact_name"], "Jan Peeters");
    let rid = d["repair"]["id"].as_str().unwrap().to_string();
    for bad in [
        json!({ "fault_description": "x" }),
        json!({ "product_description": "x", "fault_description": " " }),
        json!({ "product_description": "x".repeat(301), "fault_description": "x" }),
    ] {
        assert_eq!(
            p(Method::POST, "/repairs", Some(bad)).await.0,
            StatusCode::UNPROCESSABLE_ENTITY
        );
    }

    // Photos from the portal: validated like everywhere, and shown back.
    let (status, _, body) = raw(
        &app,
        Who::Portal(&jan),
        Method::POST,
        &format!("/api/v1/portal/repairs/{rid}/photos?caption=Leak&filename=leak.jpg"),
        Some(("image/jpeg", jpeg(9))),
    )
    .await;
    assert_eq!(
        status,
        StatusCode::CREATED,
        "{}",
        String::from_utf8_lossy(&body)
    );
    let detail: Value = serde_json::from_slice(&body).unwrap();
    let photo = detail["photos"][0]["id"].as_str().unwrap().to_string();
    assert_eq!(detail["photos"][0]["uploader_name"], "Jan Peeters");
    let (status, _, _) = raw(
        &app,
        Who::Portal(&jan),
        Method::POST,
        &format!("/api/v1/portal/repairs/{rid}/photos"),
        Some(("image/jpeg", b"<svg/>".to_vec())),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    let (status, headers, bytes) = raw(
        &app,
        Who::Portal(&jan),
        Method::GET,
        &format!("/api/v1/portal/repairs/{rid}/photos/{photo}"),
        None,
    )
    .await;
    assert_eq!((status, bytes), (StatusCode::OK, jpeg(9)));
    assert_eq!(headers["content-type"], "image/jpeg");

    // Staff sees it as announced from the portal, with the customer's photo.
    let (_, s) = get(&app, SUPPORT, &format!("/api/v1/repairs/{rid}")).await;
    assert_eq!(s["repair"]["source"], "portal");
    assert_eq!(s["repair"]["status"], "announced");
    assert_eq!(s["photos"][0]["uploader_name"], "Jan Peeters");
    assert_eq!(s["events"][0]["actor_name"], "Jan Peeters");
    let (_, queue) = get(&app, SUPPORT, "/api/v1/repairs?status=announced").await;
    assert_eq!(queue["total"], 1);

    // Sofie (own scope) does not see Jan's repair; Jan (customer scope) sees hers.
    let (_, mine) = common::call_portal(
        &app,
        Some(&sofie),
        Method::GET,
        "/api/v1/portal/repairs",
        None,
    )
    .await;
    assert_eq!(mine, json!([]));
    assert_eq!(
        common::call_portal(
            &app,
            Some(&sofie),
            Method::GET,
            &format!("/api/v1/portal/repairs/{rid}"),
            None
        )
        .await
        .0,
        StatusCode::NOT_FOUND
    );
    let (status, _, _) = raw(
        &app,
        Who::Portal(&sofie),
        Method::GET,
        &format!("/api/v1/portal/repairs/{rid}/photos/{photo}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, _, _) = raw(
        &app,
        Who::Portal(&sofie),
        Method::POST,
        &format!("/api/v1/portal/repairs/{rid}/photos"),
        Some(("image/jpeg", jpeg(1))),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (_, jans) = p(Method::GET, "/repairs", None).await;
    assert_eq!(jans.as_array().unwrap().len(), 1);

    // Internal steps are not shown: routed and in progress read "in repair", notes never appear.
    post(
        &app,
        SUPPORT,
        &format!("/api/v1/repairs/{rid}/status"),
        json!({ "status": "received" }),
    )
    .await;
    post(
        &app,
        SUPPORT,
        &format!("/api/v1/repairs/{rid}/route"),
        json!({ "department_id": ELECTRONICS }),
    )
    .await;
    post(
        &app,
        ELEC_USER,
        &format!("/api/v1/repairs/{rid}/notes"),
        json!({ "note": "INTERNAL customer is wrong" }),
    )
    .await;
    let (_, d) = p(Method::GET, &format!("/repairs/{rid}"), None).await;
    assert_eq!(d["repair"]["status"], "in_repair");
    let text = d.to_string();
    assert!(
        !text.contains("INTERNAL") && !text.contains("Electronics") && !text.contains("department"),
        "{text}"
    );
    post(
        &app,
        ELEC_USER,
        &format!("/api/v1/repairs/{rid}/status"),
        json!({ "status": "in_progress" }),
    )
    .await;
    post(
        &app,
        ELEC_USER,
        &format!("/api/v1/repairs/{rid}/status"),
        json!({ "status": "completed" }),
    )
    .await;
    assert_eq!(
        p(Method::GET, &format!("/repairs/{rid}"), None).await.1["repair"]["status"],
        "ready"
    );

    // A finished repair takes no more photos.
    post(
        &app,
        SUPPORT,
        &format!("/api/v1/repairs/{rid}/status"),
        json!({ "status": "shipped" }),
    )
    .await;
    let (status, _, _) = raw(
        &app,
        Who::Portal(&jan),
        Method::POST,
        &format!("/api/v1/portal/repairs/{rid}/photos"),
        Some(("image/jpeg", jpeg(2))),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
    // And staff tokens are no portal sessions.
    let (status, _) = call(&app, SUPPORT, Method::GET, "/api/v1/portal/repairs", None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

/// A customer cannot have an existing file (here a staff JPEG on a ticket) linked to their repair
/// by sending its id as the photo's client id, nor tell from the answer that it exists.
#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_portal_photo_client_id_cannot_claim_an_existing_file(db: PgPool) {
    let app = setup(db.clone()).await;
    let (s, t) = post(
        &app,
        SUPPORT,
        "/api/v1/tickets",
        json!({ "subject": "Internal", "customer_id": BETA, "contact_email": "x@beta.example", "body": "x" }),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED, "{t}");
    let ticket = t["ticket"]["id"].as_str().unwrap();
    let taken = "00000000-0000-7000-8000-00000000dd01";
    let (s, _, b) = raw(
        &app,
        Who::Staff(SUPPORT),
        Method::POST,
        &format!("/api/v1/tickets/{ticket}/attachments?filename=secret.jpg&client_id={taken}"),
        Some(("application/octet-stream", jpeg(7))),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED, "{}", String::from_utf8_lossy(&b));

    let jan = portal_login(&app, &db, JAN).await;
    let (s, d) = common::call_portal(
        &app,
        Some(&jan),
        Method::POST,
        "/api/v1/portal/repairs",
        Some(json!({ "product_description": "Pump", "fault_description": "Leaks" })),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED, "{d}");
    let rid = d["repair"]["id"].as_str().unwrap().to_string();
    let photo_uri = format!("/api/v1/portal/repairs/{rid}/photos?client_id={taken}");
    let (s, _, b) = raw(
        &app,
        Who::Portal(&jan),
        Method::POST,
        &photo_uri,
        Some(("image/jpeg", jpeg(1))),
    )
    .await;
    let d: Value = serde_json::from_slice(&b).unwrap_or(Value::Null);
    assert_eq!(s, StatusCode::CREATED, "{d}");
    let photos = d["photos"].as_array().unwrap();
    assert_eq!(photos.len(), 1);
    assert_ne!(photos[0]["id"], taken);
    assert_ne!(photos[0]["filename"], "secret.jpg");
    // The staff file is not linked to the repair: same answer as for an id that does not exist.
    let (s_taken, _, body_taken) = raw(
        &app,
        Who::Portal(&jan),
        Method::GET,
        &format!("/api/v1/portal/repairs/{rid}/photos/{taken}"),
        None,
    )
    .await;
    let (s_missing, _, body_missing) = raw(
        &app,
        Who::Portal(&jan),
        Method::GET,
        &format!("/api/v1/portal/repairs/{rid}/photos/00000000-0000-7000-8000-00000000dd99"),
        None,
    )
    .await;
    assert_eq!(s_taken, StatusCode::NOT_FOUND);
    assert_eq!((s_taken, body_taken), (s_missing, body_missing));
    // The customer's own photo downloads, and a retry adds no second copy.
    let own = photos[0]["id"].as_str().unwrap().to_string();
    let (s, _, bytes) = raw(
        &app,
        Who::Portal(&jan),
        Method::GET,
        &format!("/api/v1/portal/repairs/{rid}/photos/{own}"),
        None,
    )
    .await;
    assert_eq!((s, bytes), (StatusCode::OK, jpeg(1)));
    let (s, _, b) = raw(
        &app,
        Who::Portal(&jan),
        Method::POST,
        &photo_uri,
        Some(("image/jpeg", jpeg(1))),
    )
    .await;
    let d: Value = serde_json::from_slice(&b).unwrap_or(Value::Null);
    assert_eq!(s, StatusCode::CREATED, "{d}");
    assert_eq!(d["photos"].as_array().unwrap().len(), 1);
}
