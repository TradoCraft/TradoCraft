//! Work centres, routings and operations (ADR 0060): work centres with their hours and closures,
//! the routing on a BOM revision, the operations a production order snapshots from it, capacity,
//! auto-release of subassemblies and the cost roll-up.

mod common;

use axum::http::{Method, StatusCode};
use common::{call, dec, setup};
use rust_decimal::Decimal;
use serde_json::{json, Value};
use sqlx::PgPool;
use uuid::Uuid;

const ADMIN: &str = "admin@example.com";
const SALES: &str = "sales@example.com";
const VIEWER: &str = "viewer@example.com";
const TECHNICIAN: &str = "technician@example.com"; // no production rights
const PLANNER: &str = "planner@example.com"; // role production
const PM: &str = "pm@example.com"; // role product_manager
const COMPANY: &str = "00000000-0000-7000-8000-000000000001";

async fn add_user(db: &PgPool, email: &str, role: &str) {
    let uid = Uuid::now_v7();
    sqlx::query("INSERT INTO core.users (id, email, display_name) VALUES ($1, $2, $3)")
        .bind(uid)
        .bind(email)
        .bind(email)
        .execute(db)
        .await
        .unwrap();
    sqlx::query("INSERT INTO core.user_companies (user_id, company_id, roles, is_default) VALUES ($1, $2::uuid, $3, true)")
        .bind(uid)
        .bind(COMPANY)
        .bind(vec![role.to_string()])
        .execute(db)
        .await
        .unwrap();
}

async fn api(
    app: &axum::Router,
    user: &str,
    method: Method,
    uri: &str,
    body: Option<Value>,
) -> (StatusCode, Value) {
    call(app, user, method, &format!("/api/v1{uri}"), body).await
}
async fn post(app: &axum::Router, user: &str, uri: &str, body: Value) -> (StatusCode, Value) {
    api(app, user, Method::POST, uri, Some(body)).await
}
async fn put(app: &axum::Router, user: &str, uri: &str, body: Value) -> (StatusCode, Value) {
    api(app, user, Method::PUT, uri, Some(body)).await
}
async fn get(app: &axum::Router, user: &str, uri: &str) -> (StatusCode, Value) {
    api(app, user, Method::GET, uri, None).await
}
async fn delete(app: &axum::Router, user: &str, uri: &str) -> (StatusCode, Value) {
    api(app, user, Method::DELETE, uri, None).await
}

fn q(s: &str) -> Decimal {
    s.parse().unwrap()
}

fn id(v: &Value) -> String {
    v["id"].as_str().unwrap().to_string()
}

struct Env {
    app: axum::Router,
    db: PgPool,
}

async fn env(db: PgPool) -> Env {
    let app = setup(db.clone()).await;
    add_user(&db, PLANNER, "production").await;
    add_user(&db, PM, "product_manager").await;
    Env { app, db }
}

impl Env {
    /// A work centre made by the administrator; extra fields are merged into the body.
    async fn work_centre(&self, code: &str, extra: Value) -> Value {
        let mut body = json!({ "code": code, "name": format!("Work centre {code}") });
        for (k, v) in extra.as_object().unwrap() {
            body[k] = v.clone();
        }
        let (status, w) = post(&self.app, ADMIN, "/production/work-centres", body).await;
        assert_eq!(status, StatusCode::CREATED, "{w}");
        w
    }

    async fn division(&self, code: &str) -> String {
        let (status, d) = post(
            &self.app,
            ADMIN,
            "/production/divisions",
            json!({ "code": code, "name": format!("Division {code}") }),
        )
        .await;
        assert_eq!(status, StatusCode::CREATED, "{d}");
        id(&d)
    }
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn work_centres_are_kept_by_the_administrator_and_seen_by_production(db: PgPool) {
    let e = env(db).await;
    let w = e
        .work_centre(
            "CNC1",
            json!({ "capacity": 2, "cost_per_hour": "45.5", "notes": " lathe " }),
        )
        .await;
    assert_eq!(w["code"], "CNC1");
    assert_eq!(w["capacity"], 2);
    assert_eq!(w["notes"], "lathe", "trimmed");
    assert_eq!(w["active"], true);
    assert_eq!(w["open_operations"], 0);
    assert_eq!(w["hours"], json!([]), "no hours: the default week applies");
    let wid = id(&w);

    // Reading is for everyone who sees production; changing is for the administrator.
    for who in [PLANNER, SALES, VIEWER, PM] {
        let (status, list) = get(&e.app, who, "/production/work-centres").await;
        assert_eq!(status, StatusCode::OK, "{who}");
        assert_eq!(list.as_array().unwrap().len(), 1, "{who}");
    }
    assert_eq!(
        get(&e.app, TECHNICIAN, "/production/work-centres").await.0,
        StatusCode::FORBIDDEN
    );
    let body = json!({ "code": "X", "name": "X" });
    for who in [PLANNER, PM, SALES, VIEWER] {
        assert_eq!(
            post(&e.app, who, "/production/work-centres", body.clone())
                .await
                .0,
            StatusCode::FORBIDDEN,
            "{who} create"
        );
        assert_eq!(
            put(
                &e.app,
                who,
                &format!("/production/work-centres/{wid}"),
                body.clone()
            )
            .await
            .0,
            StatusCode::FORBIDDEN,
            "{who} update"
        );
        assert_eq!(
            delete(&e.app, who, &format!("/production/work-centres/{wid}"))
                .await
                .0,
            StatusCode::FORBIDDEN,
            "{who} delete"
        );
    }

    // The code is unique within the company.
    let (status, _) = post(
        &e.app,
        ADMIN,
        "/production/work-centres",
        json!({ "code": "CNC1", "name": "Again" }),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);

    // Update, deactivate, filter.
    let (status, u) = put(
        &e.app,
        ADMIN,
        &format!("/production/work-centres/{wid}"),
        json!({ "code": "CNC1", "name": "Lathe", "capacity": 3, "active": false, "sort_order": 5 }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{u}");
    assert_eq!(u["name"], "Lathe");
    assert_eq!(u["capacity"], 3);
    assert_eq!(u["active"], false);
    let (_, inactive) = get(&e.app, ADMIN, "/production/work-centres?active=false").await;
    assert_eq!(inactive.as_array().unwrap().len(), 1);
    let (_, active) = get(&e.app, ADMIN, "/production/work-centres?active=true").await;
    assert_eq!(active.as_array().unwrap().len(), 0);

    // Remove one that nothing uses; an unknown one is 404.
    let (status, _) = delete(&e.app, ADMIN, &format!("/production/work-centres/{wid}")).await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    let (status, _) = delete(&e.app, ADMIN, &format!("/production/work-centres/{wid}")).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, _) = put(
        &e.app,
        ADMIN,
        &format!("/production/work-centres/{}", Uuid::now_v7()),
        body,
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    // Every change is audited; the refused ones are not.
    let actions: Vec<String> = sqlx::query_scalar(
        "SELECT action FROM audit.events WHERE entity = 'production_work_centre' ORDER BY id",
    )
    .fetch_all(&e.db)
    .await
    .unwrap();
    assert_eq!(actions, ["created", "updated", "deleted"]);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_work_centre_needs_valid_values(db: PgPool) {
    let e = env(db).await;
    for (what, body) in [
        ("empty code", json!({ "code": " ", "name": "A" })),
        ("empty name", json!({ "code": "A", "name": "" })),
        (
            "no capacity",
            json!({ "code": "A", "name": "A", "capacity": 0 }),
        ),
        (
            "too much capacity",
            json!({ "code": "A", "name": "A", "capacity": 1001 }),
        ),
        (
            "negative rate",
            json!({ "code": "A", "name": "A", "cost_per_hour": "-1" }),
        ),
        (
            "fine rate",
            json!({ "code": "A", "name": "A", "cost_per_hour": "1.00001" }),
        ),
        (
            "unknown division",
            json!({ "code": "A", "name": "A", "division_id": Uuid::now_v7() }),
        ),
    ] {
        let (status, r) = post(&e.app, ADMIN, "/production/work-centres", body).await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{what}: {r}");
    }
    let (_, list) = get(&e.app, ADMIN, "/production/work-centres").await;
    assert_eq!(list.as_array().unwrap().len(), 0);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_cost_per_hour_is_only_shown_to_those_who_may_see_cost(db: PgPool) {
    let e = env(db).await;
    e.work_centre("ASM", json!({ "cost_per_hour": "60" })).await;
    for who in [ADMIN, PM] {
        let (_, list) = get(&e.app, who, "/production/work-centres").await;
        assert_eq!(
            dec(&list[0]["cost_per_hour"]),
            q("60"),
            "{who} sees the rate"
        );
    }
    for who in [PLANNER, SALES, VIEWER] {
        let (_, list) = get(&e.app, who, "/production/work-centres").await;
        assert!(
            list[0]["cost_per_hour"].is_null(),
            "{who} must not see it: {list}"
        );
    }
    // Saving without a change keeps the rate (the administrator holds the cost right, so the
    // stored value is replaced only by what they send).
    let wid = id(&get(&e.app, ADMIN, "/production/work-centres").await.1[0]);
    let (status, w) = put(
        &e.app,
        ADMIN,
        &format!("/production/work-centres/{wid}"),
        json!({ "code": "ASM", "name": "Assembly", "cost_per_hour": "62.5" }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{w}");
    assert_eq!(dec(&w["cost_per_hour"]), q("62.5"));
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn work_centres_belong_to_a_division_that_stays_while_they_use_it(db: PgPool) {
    let e = env(db).await;
    let div = e.division("ASM").await;
    let w = e.work_centre("BENCH", json!({ "division_id": div })).await;
    assert_eq!(w["division_id"], div.as_str());
    assert_eq!(w["division_name"], "Division ASM");
    let (_, by_division) = get(
        &e.app,
        PLANNER,
        &format!("/production/work-centres?division_id={div}"),
    )
    .await;
    assert_eq!(by_division.as_array().unwrap().len(), 1);
    let (_, other) = get(
        &e.app,
        PLANNER,
        &format!("/production/work-centres?division_id={}", Uuid::now_v7()),
    )
    .await;
    assert_eq!(other.as_array().unwrap().len(), 0);

    let (status, r) = delete(&e.app, ADMIN, &format!("/production/divisions/{div}")).await;
    assert_eq!(status, StatusCode::CONFLICT, "{r}");

    // A deactivated division cannot be chosen for another work centre, but the one that already
    // has it keeps it on update.
    let (status, _) = put(
        &e.app,
        ADMIN,
        &format!("/production/divisions/{div}"),
        json!({ "code": "ASM", "name": "Division ASM", "active": false }),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (status, _) = post(
        &e.app,
        ADMIN,
        "/production/work-centres",
        json!({ "code": "B2", "name": "B2", "division_id": div }),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    let (status, kept) = put(
        &e.app,
        ADMIN,
        &format!("/production/work-centres/{}", id(&w)),
        json!({ "code": "BENCH", "name": "Bench", "division_id": div }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{kept}");

    // Moved away, the division can go.
    let (status, _) = put(
        &e.app,
        ADMIN,
        &format!("/production/work-centres/{}", id(&w)),
        json!({ "code": "BENCH", "name": "Bench" }),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (status, _) = delete(&e.app, ADMIN, &format!("/production/divisions/{div}")).await;
    assert_eq!(status, StatusCode::NO_CONTENT);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn opening_hours_are_replaced_as_a_whole_and_validated(db: PgPool) {
    let e = env(db).await;
    let w = e.work_centre("CNC1", json!({})).await;
    let uri = format!("/production/work-centres/{}/hours", id(&w));
    let slot = |weekday: i64, from: &str, to: &str| json!({ "weekday": weekday, "start_time": from, "end_time": to });

    let (status, w2) = put(
        &e.app,
        ADMIN,
        &uri,
        json!({ "slots": [slot(2, "13:00:00", "17:00:00"), slot(1, "06:00:00", "14:30:00"), slot(2, "08:00:00", "12:00:00")] }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{w2}");
    let hours = w2["hours"].as_array().unwrap();
    assert_eq!(hours.len(), 3);
    assert_eq!(
        hours[0],
        slot(1, "06:00:00", "14:30:00"),
        "sorted by weekday then start"
    );
    assert_eq!(hours[1], slot(2, "08:00:00", "12:00:00"));

    // The list carries the hours too.
    let (_, list) = get(&e.app, PLANNER, "/production/work-centres").await;
    assert_eq!(list[0]["hours"].as_array().unwrap().len(), 3);

    for (what, slots) in [
        ("weekday 0", json!([slot(0, "08:00:00", "12:00:00")])),
        ("weekday 8", json!([slot(8, "08:00:00", "12:00:00")])),
        (
            "ends before it starts",
            json!([slot(1, "12:00:00", "08:00:00")]),
        ),
        ("zero length", json!([slot(1, "08:00:00", "08:00:00")])),
        (
            "overlap",
            json!([
                slot(1, "08:00:00", "12:00:00"),
                slot(1, "11:00:00", "15:00:00")
            ]),
        ),
    ] {
        let (status, r) = put(&e.app, ADMIN, &uri, json!({ "slots": slots })).await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{what}: {r}");
    }
    // A refused change leaves the hours alone.
    let (_, list) = get(&e.app, PLANNER, "/production/work-centres").await;
    assert_eq!(list[0]["hours"].as_array().unwrap().len(), 3);

    // Only the administrator; unknown work centres are 404.
    for who in [PLANNER, PM] {
        assert_eq!(
            put(&e.app, who, &uri, json!({ "slots": [] })).await.0,
            StatusCode::FORBIDDEN,
            "{who}"
        );
    }
    let (status, _) = put(
        &e.app,
        ADMIN,
        &format!("/production/work-centres/{}/hours", Uuid::now_v7()),
        json!({ "slots": [] }),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    // No blocks: the default week applies again.
    let (status, back) = put(&e.app, ADMIN, &uri, json!({ "slots": [] })).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(back["hours"], json!([]));
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn closures_are_entered_by_planners_for_a_work_centre_or_the_whole_plant(db: PgPool) {
    let e = env(db).await;
    let w = e.work_centre("CNC1", json!({})).await;
    let other = e.work_centre("CNC2", json!({})).await;
    let wid = id(&w);

    // Dates may arrive as date-times, as the generated client sends them.
    let (status, plant) = post(
        &e.app,
        PLANNER,
        "/production/closures",
        json!({ "from_date": "2027-04-05T00:00:00.000", "to_date": "2027-04-05", "kind": "holiday", "note": "Easter Monday" }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{plant}");
    assert!(plant["work_centre_id"].is_null());
    assert_eq!(plant["from_date"], "2027-04-05");
    let (status, mine) = post(
        &e.app,
        PLANNER,
        "/production/closures",
        json!({ "work_centre_id": wid, "from_date": "2027-03-01", "to_date": "2027-03-03", "kind": "maintenance" }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{mine}");
    assert_eq!(mine["work_centre_code"], "CNC1");
    let (status, _) = post(
        &e.app,
        ADMIN,
        "/production/closures",
        json!({ "work_centre_id": id(&other), "from_date": "2027-06-01", "to_date": "2027-06-01" }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "kind defaults to other");

    let (_, all) = get(&e.app, VIEWER, "/production/closures").await;
    assert_eq!(all.as_array().unwrap().len(), 3);
    assert_eq!(all[0]["from_date"], "2027-03-01", "earliest first");
    // One work centre: its own closures and the whole-plant ones.
    let (_, one) = get(
        &e.app,
        VIEWER,
        &format!("/production/closures?work_centre_id={wid}"),
    )
    .await;
    assert_eq!(one.as_array().unwrap().len(), 2);
    // A period.
    let (_, april) = get(
        &e.app,
        VIEWER,
        "/production/closures?from=2027-04-01&to=2027-04-30",
    )
    .await;
    assert_eq!(april.as_array().unwrap().len(), 1);
    assert_eq!(april[0]["kind"], "holiday");

    // Validation.
    for (what, body) in [
        (
            "ends before it starts",
            json!({ "from_date": "2027-05-02", "to_date": "2027-05-01" }),
        ),
        (
            "bad kind",
            json!({ "from_date": "2027-05-01", "to_date": "2027-05-01", "kind": "party" }),
        ),
        (
            "unknown work centre",
            json!({ "work_centre_id": Uuid::now_v7(), "from_date": "2027-05-01", "to_date": "2027-05-01" }),
        ),
    ] {
        let (status, r) = post(&e.app, PLANNER, "/production/closures", body).await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{what}: {r}");
    }

    // Reading is for production readers; writing needs production.write (not the viewer or sales).
    for who in [VIEWER, SALES, PM] {
        let (status, _) = post(
            &e.app,
            who,
            "/production/closures",
            json!({ "from_date": "2027-05-01", "to_date": "2027-05-01" }),
        )
        .await;
        assert_eq!(status, StatusCode::FORBIDDEN, "{who}");
    }
    assert_eq!(
        get(&e.app, TECHNICIAN, "/production/closures").await.0,
        StatusCode::FORBIDDEN
    );

    // Change and remove.
    let cid = id(&mine);
    let (status, u) = put(
        &e.app,
        PLANNER,
        &format!("/production/closures/{cid}"),
        json!({ "from_date": "2027-03-01", "to_date": "2027-03-10", "kind": "maintenance", "note": "overhaul" }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{u}");
    assert!(u["work_centre_id"].is_null(), "now the whole plant");
    assert_eq!(u["to_date"], "2027-03-10");
    let (status, _) = delete(&e.app, PLANNER, &format!("/production/closures/{cid}")).await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    let (status, _) = delete(&e.app, PLANNER, &format!("/production/closures/{cid}")).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, _) = put(
        &e.app,
        PLANNER,
        &format!("/production/closures/{cid}"),
        json!({ "from_date": "2027-03-01", "to_date": "2027-03-02" }),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    // Removing a work centre takes its closures along.
    let (status, _) = delete(
        &e.app,
        ADMIN,
        &format!("/production/work-centres/{}", id(&other)),
    )
    .await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    let (_, left) = get(&e.app, VIEWER, "/production/closures").await;
    assert_eq!(
        left.as_array().unwrap().len(),
        1,
        "only the whole-plant holiday is left"
    );
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn work_centres_and_closures_stay_within_their_company(db: PgPool) {
    let e = env(db).await;
    let w = e.work_centre("CNC1", json!({})).await;
    let (_, closure) = post(
        &e.app,
        PLANNER,
        "/production/closures",
        json!({ "work_centre_id": id(&w), "from_date": "2027-03-01", "to_date": "2027-03-02" }),
    )
    .await;

    let other = Uuid::now_v7();
    sqlx::query("INSERT INTO core.companies (id, name, country_code, currency) VALUES ($1, 'Other BV', 'BE', 'EUR')")
        .bind(other)
        .execute(&e.db)
        .await
        .unwrap();
    let user = Uuid::now_v7();
    sqlx::query("INSERT INTO core.users (id, email, display_name) VALUES ($1, 'other@example.com', 'Other')")
        .bind(user)
        .execute(&e.db)
        .await
        .unwrap();
    sqlx::query("INSERT INTO core.user_companies (user_id, company_id, roles, is_default) VALUES ($1, $2, '{admin}', true)")
        .bind(user)
        .bind(other)
        .execute(&e.db)
        .await
        .unwrap();
    let theirs = "other@example.com";

    let (_, list) = get(&e.app, theirs, "/production/work-centres").await;
    assert_eq!(list.as_array().unwrap().len(), 0);
    let (_, closures) = get(&e.app, theirs, "/production/closures").await;
    assert_eq!(closures.as_array().unwrap().len(), 0);
    let wid = id(&w);
    for (what, status) in [
        (
            "update",
            put(
                &e.app,
                theirs,
                &format!("/production/work-centres/{wid}"),
                json!({ "code": "Z", "name": "Z" }),
            )
            .await
            .0,
        ),
        (
            "delete",
            delete(&e.app, theirs, &format!("/production/work-centres/{wid}"))
                .await
                .0,
        ),
        (
            "hours",
            put(
                &e.app,
                theirs,
                &format!("/production/work-centres/{wid}/hours"),
                json!({ "slots": [] }),
            )
            .await
            .0,
        ),
        (
            "update closure",
            put(
                &e.app,
                theirs,
                &format!("/production/closures/{}", id(&closure)),
                json!({ "from_date": "2027-03-01", "to_date": "2027-03-02" }),
            )
            .await
            .0,
        ),
        (
            "delete closure",
            delete(
                &e.app,
                theirs,
                &format!("/production/closures/{}", id(&closure)),
            )
            .await
            .0,
        ),
    ] {
        assert_eq!(status, StatusCode::NOT_FOUND, "{what}");
    }
    // Their closure cannot point at our work centre; their code does not clash with ours.
    let (status, _) = post(
        &e.app,
        theirs,
        "/production/closures",
        json!({ "work_centre_id": wid, "from_date": "2027-03-01", "to_date": "2027-03-02" }),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    let (status, _) = post(
        &e.app,
        theirs,
        "/production/work-centres",
        json!({ "code": "CNC1", "name": "Theirs" }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);
    // Ours is untouched.
    let (_, ours) = get(&e.app, ADMIN, "/production/work-centres").await;
    assert_eq!(ours.as_array().unwrap().len(), 1);
    assert_eq!(ours[0]["name"], "Work centre CNC1");
}

// ---- Routings on the BOM (ADR 0060) ----

const FRAME: &str = "00000000-0000-7000-8000-000000000307"; // manufactured, active BOM revision 1
const FRAME_BOM: &str = "00000000-0000-7000-8000-000000000502";

fn op(name: &str, work_centre: &str, setup: i64, run: &str) -> Value {
    json!({ "name": name, "work_centre_id": work_centre, "setup_minutes": setup, "run_minutes_per_unit": run })
}

impl Env {
    /// Starts a draft revision of the product (copying the active one) and returns its id.
    async fn draft_bom(&self, product: &str, body: Value) -> String {
        let (status, b) = post(&self.app, PM, &format!("/products/{product}/boms"), body).await;
        assert_eq!(status, StatusCode::CREATED, "{b}");
        id(&b)
    }

    async fn set_routing(&self, bom: &str, ops: Vec<Value>) -> Value {
        let (status, r) = put(
            &self.app,
            PM,
            &format!("/boms/{bom}/routing"),
            json!({ "operations": ops }),
        )
        .await;
        assert_eq!(status, StatusCode::OK, "{r}");
        r
    }

    async fn routing(&self, who: &str, bom: &str) -> Value {
        let (status, r) = get(&self.app, who, &format!("/boms/{bom}/routing")).await;
        assert_eq!(status, StatusCode::OK, "{who}: {r}");
        r
    }
}

fn op_names(routing: &Value) -> Vec<String> {
    routing["operations"]
        .as_array()
        .unwrap()
        .iter()
        .map(|o| o["name"].as_str().unwrap().to_string())
        .collect()
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_routing_is_kept_on_a_draft_bom_revision_by_whoever_may_edit_boms(db: PgPool) {
    let e = env(db).await;
    let cut = e.work_centre("SAW", json!({})).await;
    let weld = e.work_centre("WELD", json!({})).await;
    let draft = e.draft_bom(FRAME, json!({})).await;

    // A new draft starts without a routing.
    let r = e.routing(PLANNER, &draft).await;
    assert_eq!(r["bom_status"], "draft");
    assert_eq!(r["bom_revision"], 2);
    assert_eq!(r["product_id"], FRAME);
    assert_eq!(r["operations"], json!([]));

    let r = e
        .set_routing(
            &draft,
            vec![
                op(" Cut profile ", &id(&cut), 15, "1.5"),
                op("Weld frame", &id(&weld), 0, "6.25"),
            ],
        )
        .await;
    let ops = r["operations"].as_array().unwrap();
    assert_eq!(ops.len(), 2);
    assert_eq!(ops[0]["position"], 1);
    assert_eq!(ops[0]["name"], "Cut profile", "trimmed");
    assert_eq!(ops[0]["work_centre_code"], "SAW");
    assert_eq!(ops[0]["setup_minutes"], 15);
    assert_eq!(dec(&ops[0]["run_minutes_per_unit"]), q("1.5"));
    assert_eq!(ops[1]["position"], 2);
    assert_eq!(dec(&ops[1]["run_minutes_per_unit"]), q("6.25"));

    // Reading is for everyone who sees production; the technician has no production rights.
    for who in [ADMIN, PM, PLANNER, SALES, VIEWER] {
        assert_eq!(
            op_names(&e.routing(who, &draft).await),
            ["Cut profile", "Weld frame"],
            "{who}"
        );
    }
    assert_eq!(
        get(&e.app, TECHNICIAN, &format!("/boms/{draft}/routing"))
            .await
            .0,
        StatusCode::FORBIDDEN
    );
    assert_eq!(
        get(&e.app, ADMIN, &format!("/boms/{}/routing", Uuid::now_v7()))
            .await
            .0,
        StatusCode::NOT_FOUND
    );

    // Replacing swaps the whole list; the order of the list is the order of the operations.
    let r = e
        .set_routing(&draft, vec![op("Weld frame", &id(&weld), 0, "6")])
        .await;
    assert_eq!(op_names(&r), ["Weld frame"]);
    assert_eq!(r["operations"][0]["position"], 1);
    let r = e.set_routing(&draft, vec![]).await;
    assert_eq!(
        r["operations"],
        json!([]),
        "an empty list removes the routing"
    );
    e.set_routing(&draft, vec![op("Cut profile", &id(&cut), 15, "1.5")])
        .await;

    // Only bom.write may change it (the administrator and the product manager); production
    // planners and the rest read.
    for who in [PLANNER, SALES, VIEWER] {
        let (status, _) = put(
            &e.app,
            who,
            &format!("/boms/{draft}/routing"),
            json!({ "operations": [] }),
        )
        .await;
        assert_eq!(status, StatusCode::FORBIDDEN, "{who}");
    }
    let (status, _) = put(
        &e.app,
        ADMIN,
        &format!("/boms/{draft}/routing"),
        json!({ "operations": [op("Cut profile", &id(&cut), 10, "1")] }),
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    // An active or obsolete revision is frozen.
    let (status, r) = put(
        &e.app,
        PM,
        &format!("/boms/{FRAME_BOM}/routing"),
        json!({ "operations": [op("Cut profile", &id(&cut), 0, "1")] }),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT, "{r}");
    let (status, _) = put(
        &e.app,
        PM,
        &format!("/boms/{}/routing", Uuid::now_v7()),
        json!({ "operations": [] }),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, a) = post(&e.app, PM, &format!("/boms/{draft}/activate"), json!({})).await;
    assert_eq!(status, StatusCode::OK, "{a}");
    let (status, _) = put(
        &e.app,
        PM,
        &format!("/boms/{draft}/routing"),
        json!({ "operations": [] }),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT, "frozen once active");
    assert_eq!(
        op_names(&e.routing(PLANNER, FRAME_BOM).await),
        Vec::<String>::new(),
        "the obsolete revision never had one"
    );
    let actions: Vec<String> = sqlx::query_scalar(
        "SELECT action FROM audit.events WHERE entity = 'bom' AND entity_id = $1::uuid ORDER BY id",
    )
    .bind(&draft)
    .fetch_all(&e.db)
    .await
    .unwrap();
    assert!(
        actions.contains(&"routing_updated".to_string()),
        "{actions:?}"
    );
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_routing_needs_valid_operations_on_usable_work_centres(db: PgPool) {
    let e = env(db).await;
    let saw = e.work_centre("SAW", json!({})).await;
    let retired = e.work_centre("OLD", json!({})).await;
    let draft = e.draft_bom(FRAME, json!({})).await;
    let uri = format!("/boms/{draft}/routing");
    let saw_id = id(&saw);

    // A second company with a work centre of its own.
    let other = Uuid::now_v7();
    sqlx::query("INSERT INTO core.companies (id, name, country_code, currency) VALUES ($1, 'Other BV', 'BE', 'EUR')")
        .bind(other)
        .execute(&e.db)
        .await
        .unwrap();
    let foreign = Uuid::now_v7();
    sqlx::query("INSERT INTO production.work_centres (id, company_id, code, name) VALUES ($1, $2, 'THEIRS', 'Theirs')")
        .bind(foreign)
        .bind(other)
        .execute(&e.db)
        .await
        .unwrap();

    let too_many: Vec<Value> = (0..101)
        .map(|i| op(&format!("op {i}"), &saw_id, 0, "1"))
        .collect();
    for (what, ops) in [
        ("no name", vec![op(" ", &saw_id, 0, "1")]),
        ("negative setup", vec![op("a", &saw_id, -1, "1")]),
        ("silly setup", vec![op("a", &saw_id, 2_000_000, "1")]),
        ("negative run", vec![op("a", &saw_id, 0, "-0.5")]),
        (
            "run with five decimals",
            vec![op("a", &saw_id, 0, "0.00001")],
        ),
        (
            "unknown work centre",
            vec![op("a", &Uuid::now_v7().to_string(), 0, "1")],
        ),
        (
            "a work centre of another company",
            vec![op("a", &foreign.to_string(), 0, "1")],
        ),
        ("too many operations", too_many),
    ] {
        let (status, r) = put(&e.app, PM, &uri, json!({ "operations": ops })).await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{what}: {r}");
    }
    assert_eq!(
        e.routing(PM, &draft).await["operations"],
        json!([]),
        "a refused change leaves the routing alone"
    );

    // A deactivated work centre cannot be put into a routing, but one the routing already has
    // stays when the routing is saved again.
    e.set_routing(&draft, vec![op("Old way", &id(&retired), 0, "2")])
        .await;
    let (status, _) = put(
        &e.app,
        ADMIN,
        &format!("/production/work-centres/{}", id(&retired)),
        json!({ "code": "OLD", "name": "Old", "active": false }),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (status, r) = put(
        &e.app,
        PM,
        &uri,
        json!({ "operations": [op("Old way", &id(&retired), 0, "3"), op("New way", &saw_id, 0, "1")] }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "kept: {r}");
    let other_draft = e
        .draft_bom("00000000-0000-7000-8000-000000000301", json!({}))
        .await;
    let (status, r) = put(
        &e.app,
        PM,
        &format!("/boms/{other_draft}/routing"),
        json!({ "operations": [op("Old way", &id(&retired), 0, "3")] }),
    )
    .await;
    assert_eq!(
        status,
        StatusCode::UNPROCESSABLE_ENTITY,
        "another BOM may not pick it: {r}"
    );

    // A work centre that a routing uses cannot be deleted, only deactivated.
    let (status, r) = delete(
        &e.app,
        ADMIN,
        &format!("/production/work-centres/{}", id(&retired)),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT, "{r}");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_new_revision_starts_with_the_routing_of_the_one_it_copies(db: PgPool) {
    let e = env(db).await;
    let saw = e.work_centre("SAW", json!({})).await;
    let weld = e.work_centre("WELD", json!({})).await;

    // Revision 2 gets a routing and is activated; revision 1 is obsolete and has none.
    let rev2 = e.draft_bom(FRAME, json!({})).await;
    e.set_routing(
        &rev2,
        vec![
            op("Cut", &id(&saw), 5, "1"),
            op("Weld", &id(&weld), 10, "4.5"),
        ],
    )
    .await;
    let (status, a) = post(&e.app, PM, &format!("/boms/{rev2}/activate"), json!({})).await;
    assert_eq!(status, StatusCode::OK, "{a}");

    // Revision 3 copies the active one: lines and routing.
    let rev3 = e.draft_bom(FRAME, json!({})).await;
    let r3 = e.routing(PLANNER, &rev3).await;
    assert_eq!(r3["bom_revision"], 3);
    assert_eq!(op_names(&r3), ["Cut", "Weld"]);
    assert_eq!(r3["operations"][1]["setup_minutes"], 10);
    assert_eq!(dec(&r3["operations"][1]["run_minutes_per_unit"]), q("4.5"));
    let r2 = e.routing(PLANNER, &rev2).await;
    assert_ne!(
        r3["operations"][0]["id"], r2["operations"][0]["id"],
        "a copy, not the same rows"
    );

    // Editing the copy leaves the original alone.
    e.set_routing(&rev3, vec![op("Weld", &id(&weld), 10, "4")])
        .await;
    assert_eq!(op_names(&e.routing(PLANNER, &rev2).await), ["Cut", "Weld"]);

    // `copy_from` picks the source: revision 1 had no routing, so the new draft has none.
    let (status, a) = post(&e.app, PM, &format!("/boms/{rev3}/activate"), json!({})).await;
    assert_eq!(status, StatusCode::OK, "{a}");
    let rev4 = e.draft_bom(FRAME, json!({ "copy_from": FRAME_BOM })).await;
    assert_eq!(e.routing(PLANNER, &rev4).await["operations"], json!([]));
    // ... and copying the (now obsolete) revision 2 brings its routing back.
    let (status, a) = post(&e.app, PM, &format!("/boms/{rev4}/activate"), json!({})).await;
    assert_eq!(status, StatusCode::OK, "{a}");
    let rev5 = e.draft_bom(FRAME, json!({ "copy_from": rev2 })).await;
    assert_eq!(op_names(&e.routing(PLANNER, &rev5).await), ["Cut", "Weld"]);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn each_company_keeps_its_own_routing_for_a_shared_bom(db: PgPool) {
    let e = env(db).await;
    let ours = e.work_centre("SAW", json!({})).await;
    let draft = e.draft_bom(FRAME, json!({})).await;
    e.set_routing(&draft, vec![op("Cut", &id(&ours), 0, "1")])
        .await;
    let (status, _) = post(&e.app, PM, &format!("/boms/{draft}/activate"), json!({})).await;
    assert_eq!(status, StatusCode::OK);

    // Another company has its own routing on the same BOM revision.
    let other = Uuid::now_v7();
    sqlx::query("INSERT INTO core.companies (id, name, country_code, currency) VALUES ($1, 'Other BV', 'BE', 'EUR')")
        .bind(other)
        .execute(&e.db)
        .await
        .unwrap();
    let user = Uuid::now_v7();
    sqlx::query("INSERT INTO core.users (id, email, display_name) VALUES ($1, 'other@example.com', 'Other')")
        .bind(user)
        .execute(&e.db)
        .await
        .unwrap();
    sqlx::query("INSERT INTO core.user_companies (user_id, company_id, roles, is_default) VALUES ($1, $2, '{admin}', true)")
        .bind(user)
        .bind(other)
        .execute(&e.db)
        .await
        .unwrap();
    let theirs = "other@example.com";
    let (_, w) = post(
        &e.app,
        theirs,
        "/production/work-centres",
        json!({ "code": "LASER", "name": "Laser" }),
    )
    .await;
    // Their BOM draft is the same shared BOM as ours once copied; give them a routing on the
    // current draft of the next revision.
    let next = e.draft_bom(FRAME, json!({})).await;
    let (status, r) = put(
        &e.app,
        theirs,
        &format!("/boms/{next}/routing"),
        json!({ "operations": [op("Laser cut", &id(&w), 0, "2")] }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{r}");
    assert_eq!(
        op_names(&e.routing(PM, &next).await),
        ["Cut"],
        "ours is untouched"
    );
    assert_eq!(op_names(&e.routing(theirs, &next).await), ["Laser cut"]);

    // A revision copied from this one carries both companies' routings, each its own.
    let (status, _) = post(&e.app, PM, &format!("/boms/{next}/activate"), json!({})).await;
    assert_eq!(status, StatusCode::OK);
    let after = e.draft_bom(FRAME, json!({})).await;
    assert_eq!(op_names(&e.routing(PM, &after).await), ["Cut"]);
    assert_eq!(op_names(&e.routing(theirs, &after).await), ["Laser cut"]);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn routings_are_off_with_the_production_module(db: PgPool) {
    let e = env(db).await;
    let saw = e.work_centre("SAW", json!({})).await;
    let draft = e.draft_bom(FRAME, json!({})).await;
    e.set_routing(&draft, vec![op("Cut", &id(&saw), 0, "1")])
        .await;

    sqlx::query("UPDATE core.companies SET disabled_modules = '{production}'")
        .execute(&e.db)
        .await
        .unwrap();
    // bom.write belongs to Engineering, which is still on, but the routing is Production's.
    let (status, r) = put(
        &e.app,
        PM,
        &format!("/boms/{draft}/routing"),
        json!({ "operations": [] }),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN, "{r}");
    assert_eq!(
        get(&e.app, PM, &format!("/boms/{draft}/routing")).await.0,
        StatusCode::FORBIDDEN
    );
    // The BOM itself still works, and a new revision still copies the routing rows along.
    let (status, _) = post(&e.app, PM, &format!("/boms/{draft}/activate"), json!({})).await;
    assert_eq!(status, StatusCode::OK);
    let rev = e.draft_bom(FRAME, json!({})).await;
    let copied: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM production.routing_operations WHERE bom_id = $1::uuid",
    )
    .bind(&rev)
    .fetch_one(&e.db)
    .await
    .unwrap();
    assert_eq!(copied, 1);
}
