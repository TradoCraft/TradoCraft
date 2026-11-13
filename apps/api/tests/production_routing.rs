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
const STORES: &str = "stores@example.com"; // role warehouse
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
    /// A stock location of the warehouse WH1.
    main: String,
}

async fn env(db: PgPool) -> Env {
    let app = setup(db.clone()).await;
    add_user(&db, PLANNER, "production").await;
    add_user(&db, PM, "product_manager").await;
    add_user(&db, STORES, "warehouse").await;
    let (status, w) = post(
        &app,
        ADMIN,
        "/inventory/warehouses",
        json!({ "code": "WH1", "name": "Main warehouse" }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{w}");
    Env {
        app,
        db,
        main: w["locations"][0]["id"].as_str().unwrap().into(),
    }
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

// ---- Operations on production orders (ADR 0060) ----

const ALPHA: &str = "00000000-0000-7000-8000-000000000401";
const PROFILE: &str = "00000000-0000-7000-8000-000000000308";
const BOLT: &str = "00000000-0000-7000-8000-000000000309";

fn uid() -> String {
    Uuid::now_v7().to_string()
}

/// Opens the closure of a work centre (or, without one, the whole plant) for the planner.
async fn close(e: &Env, work_centre: Option<&str>, from: &str, to: &str) {
    let (status, c) = post(
        &e.app,
        PLANNER,
        "/production/closures",
        json!({ "work_centre_id": work_centre, "from_date": from, "to_date": to, "kind": "maintenance" }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{c}");
}

impl Env {
    async fn receive(&self, product: &str, quantity: &str) {
        let (status, m) = post(
            &self.app,
            STORES,
            "/inventory/receipts",
            json!({ "id": uid(), "location_id": self.main, "product_id": product, "quantity": quantity }),
        )
        .await;
        assert_eq!(status, StatusCode::CREATED, "{m}");
    }

    /// Parts for two frames: 14.3 m of profile and 48.96 bolts are needed, so this is plenty.
    async fn frame_parts(&self) {
        self.receive(PROFILE, "20").await;
        self.receive(BOLT, "100").await;
    }

    /// A confirmed order of one line; returns (order id, line id).
    async fn order(&self, product: &str, quantity: &str) -> (String, String) {
        let (status, qn) = post(&self.app, SALES, "/quotations", json!({ "customer_id": ALPHA, "lines": [{ "product_id": product, "quantity": quantity }] })).await;
        assert_eq!(status, StatusCode::CREATED, "{qn}");
        let qid = id(&qn);
        post(
            &self.app,
            SALES,
            &format!("/quotations/{qid}/send"),
            json!({}),
        )
        .await;
        let (status, o) = post(
            &self.app,
            SALES,
            &format!("/quotations/{qid}/convert"),
            json!({ "customer_reference": "PO" }),
        )
        .await;
        assert_eq!(status, StatusCode::CREATED, "{o}");
        let order = id(&o["order"]);
        post(
            &self.app,
            SALES,
            &format!("/orders/{order}/send"),
            json!({}),
        )
        .await;
        let (status, o) = post(
            &self.app,
            SALES,
            &format!("/orders/{order}/confirm"),
            json!({}),
        )
        .await;
        assert_eq!(status, StatusCode::OK, "{o}");
        (order, o["lines"][0]["id"].as_str().unwrap().into())
    }

    async fn release(&self, order: &str, line: &str, body: Value) -> (StatusCode, Value) {
        let mut b = body;
        b["order_id"] = json!(order);
        b["order_line_id"] = json!(line);
        post(&self.app, PLANNER, "/production-orders", b).await
    }

    async fn build_for_stock(&self, product: &str, quantity: &str, extra: Value) -> Value {
        let mut b = json!({ "product_id": product, "quantity": quantity });
        for (k, v) in extra.as_object().unwrap() {
            b[k] = v.clone();
        }
        let (status, po) = post(&self.app, PLANNER, "/production-orders", b).await;
        assert_eq!(status, StatusCode::CREATED, "{po}");
        po
    }

    async fn production_order(&self, who: &str, po: &str) -> Value {
        let (status, o) = get(&self.app, who, &format!("/production-orders/{po}")).await;
        assert_eq!(status, StatusCode::OK, "{o}");
        o
    }

    async fn order_status(&self, order: &str) -> String {
        sqlx::query_scalar("SELECT status FROM sales.orders WHERE id = $1::uuid")
            .bind(order)
            .fetch_one(&self.db)
            .await
            .unwrap()
    }

    /// Gives the frame a routing (Cut on SAW: 30 min + 10 per frame; Weld on WELD: 60 per frame)
    /// as the active BOM revision. Returns (SAW id, WELD id).
    async fn frame_routing(&self) -> (String, String) {
        let saw = id(&self
            .work_centre("SAW", json!({ "cost_per_hour": "30" }))
            .await);
        let weld = id(&self
            .work_centre("WELD", json!({ "cost_per_hour": "60" }))
            .await);
        let draft = self.draft_bom(FRAME, json!({})).await;
        self.set_routing(
            &draft,
            vec![op("Cut", &saw, 30, "10"), op("Weld", &weld, 0, "60")],
        )
        .await;
        let (status, a) = post(&self.app, PM, &format!("/boms/{draft}/activate"), json!({})).await;
        assert_eq!(status, StatusCode::OK, "{a}");
        (saw, weld)
    }
}

fn operation<'a>(po: &'a Value, name: &str) -> &'a Value {
    po["operations"]
        .as_array()
        .unwrap()
        .iter()
        .find(|o| o["name"] == name)
        .unwrap_or_else(|| panic!("no operation {name} in {po}"))
}

fn minutes(po: &Value, name: &str) -> i64 {
    operation(po, name)["planned_minutes"].as_i64().unwrap()
}

fn dates(po: &Value, name: &str) -> (String, String) {
    let o = operation(po, name);
    (
        o["planned_start"].as_str().unwrap().into(),
        o["planned_end"].as_str().unwrap().into(),
    )
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn releasing_snapshots_the_routing_and_schedules_it_on_the_calendars(db: PgPool) {
    let e = env(db).await;
    e.frame_parts().await;
    let (_, weld) = e.frame_routing().await;
    // WELD is down on Monday 1 March 2027.
    close(&e, Some(&weld), "2027-03-01", "2027-03-01").await;
    let (order, line) = e.order(FRAME, "2").await;

    let (status, po) = e
        .release(
            &order,
            &line,
            json!({ "start_date": "2027-03-01T00:00:00.000" }),
        )
        .await;
    assert_eq!(status, StatusCode::CREATED, "{po}");
    let ops = po["operations"].as_array().unwrap();
    assert_eq!(ops.len(), 2);
    assert_eq!(ops[0]["name"], "Cut");
    assert_eq!(ops[0]["position"], 1);
    assert_eq!(ops[0]["status"], "pending");
    assert_eq!(ops[0]["work_centre_code"], "SAW");
    assert_eq!(ops[0]["setup_minutes"], 30);
    // 30 setup + 10 per frame x 2; 60 x 2.
    assert_eq!(minutes(&po, "Cut"), 50);
    assert_eq!(minutes(&po, "Weld"), 120);
    // Cut works on Monday; Weld cannot (maintenance), so it starts on Tuesday.
    assert_eq!(
        dates(&po, "Cut"),
        ("2027-03-01".into(), "2027-03-01".into())
    );
    assert_eq!(
        dates(&po, "Weld"),
        ("2027-03-02".into(), "2027-03-02".into())
    );
    assert_eq!(po["scheduled_end"], "2027-03-02");
    assert_eq!(po["operation_count"], 2);
    assert_eq!(po["operations_done"], 0);
    // The schedule is a suggestion: the planned-ready date and so the sales order are untouched.
    assert!(po["planned_ready_date"].is_null());
    assert_eq!(po["behind_schedule"], false);
    assert_eq!(e.order_status(&order).await, "in_planning");

    // The rate is a cost: the administrator sees it, production does not.
    let id = id(&po);
    let admin = e.production_order(ADMIN, &id).await;
    assert_eq!(dec(&operation(&admin, "Weld")["cost_rate"]), q("60"));
    let planner = e.production_order(PLANNER, &id).await;
    assert!(operation(&planner, "Weld")["cost_rate"].is_null());

    // The planned-ready date is the planner's call; behind_schedule compares with it.
    for (date, behind) in [
        ("2027-03-01", true),
        ("2027-03-02", false),
        ("2027-03-05", false),
    ] {
        let (status, u) = put(
            &e.app,
            PLANNER,
            &format!("/production-orders/{id}"),
            json!({ "planned_ready_date": date }),
        )
        .await;
        assert_eq!(status, StatusCode::OK, "{u}");
        assert_eq!(u["behind_schedule"], behind, "ready {date}: {u}");
        let (_, queue) = get(&e.app, PLANNER, "/production-orders").await;
        assert_eq!(queue["items"][0]["behind_schedule"], behind, "{date}");
        assert_eq!(queue["items"][0]["operation_count"], 2);
    }

    // The snapshot is frozen: a later revision with another routing does not change the order.
    let draft = e.draft_bom(FRAME, json!({})).await;
    let weld_op = &e.routing(PM, &draft).await["operations"][1]["work_centre_id"];
    e.set_routing(
        &draft,
        vec![op("Just weld", weld_op.as_str().unwrap(), 0, "5")],
    )
    .await;
    post(&e.app, PM, &format!("/boms/{draft}/activate"), json!({})).await;
    let again = e.production_order(PLANNER, &id).await;
    assert_eq!(again["operations"].as_array().unwrap().len(), 2);
    assert_eq!(minutes(&again, "Weld"), 120);
    // ... while a new order gets the new routing.
    let fresh = e.build_for_stock(FRAME, "1", json!({})).await;
    assert_eq!(fresh["operations"].as_array().unwrap().len(), 1);
    assert_eq!(fresh["operations"][0]["name"], "Just weld");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_long_operation_runs_over_several_working_days_from_today_by_default(db: PgPool) {
    let e = env(db).await;
    e.frame_parts().await;
    e.frame_routing().await;
    let po = e.build_for_stock(FRAME, "2", json!({})).await;
    let today = chrono::Utc::now().date_naive().to_string();
    let (start, end) = dates(&po, "Cut");
    assert!(
        start >= today,
        "work starts today or the next working day: {start}"
    );
    assert!(end >= start);

    // 20 frames: Weld takes 1200 minutes, 2.5 working days of 480.
    let big = e
        .build_for_stock(FRAME, "20", json!({ "start_date": "2027-03-01" }))
        .await;
    assert_eq!(minutes(&big, "Weld"), 1200);
    let (cut_start, cut_end) = dates(&big, "Cut");
    assert_eq!(
        (cut_start.as_str(), cut_end.as_str()),
        ("2027-03-01", "2027-03-01")
    );
    // Cut 230 on Monday leaves 250 for Weld on Monday; 1200 - 250 = 950 = 480 + 470: Tuesday and Wednesday.
    assert_eq!(
        dates(&big, "Weld"),
        ("2027-03-01".into(), "2027-03-03".into())
    );
    assert_eq!(big["scheduled_end"], "2027-03-03");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn an_order_without_a_routing_has_no_operations_and_works_as_before(db: PgPool) {
    let e = env(db).await;
    e.frame_parts().await;
    let po = e.build_for_stock(FRAME, "1", json!({})).await;
    assert_eq!(po["operations"], json!([]));
    assert!(po["scheduled_end"].is_null());
    assert_eq!(po["operation_count"], 0);
    assert_eq!(po["behind_schedule"], false);
    let id = id(&po);
    let (status, done) = post(
        &e.app,
        STORES,
        &format!("/production-orders/{id}/complete"),
        json!({ "output": { "quantity": "1", "location_id": e.main } }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{done}");
    assert_eq!(done["operations"], json!([]));
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_release_is_refused_when_a_work_centre_has_no_working_time(db: PgPool) {
    let e = env(db).await;
    e.frame_parts().await;
    e.frame_routing().await;
    // The whole plant is closed for years.
    close(&e, None, "2027-01-01", "2031-12-31").await;
    let (status, r) = post(
        &e.app,
        PLANNER,
        "/production-orders",
        json!({ "product_id": FRAME, "quantity": "1", "start_date": "2027-03-01" }),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{r}");
    assert!(
        r["message"].as_str().unwrap().contains("no working time"),
        "{r}"
    );
    // Nothing was created: not the order, not its reservations.
    let orders: i64 = sqlx::query_scalar("SELECT count(*) FROM production.production_orders")
        .fetch_one(&e.db)
        .await
        .unwrap();
    assert_eq!(orders, 0);
    let held: i64 = sqlx::query_scalar("SELECT count(*) FROM inventory.reservations")
        .fetch_one(&e.db)
        .await
        .unwrap();
    assert_eq!(held, 0);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_shop_floor_starts_and_finishes_operations_with_the_minutes_worked(db: PgPool) {
    let e = env(db).await;
    e.frame_parts().await;
    e.frame_routing().await;
    let (order, line) = e.order(FRAME, "2").await;
    let (_, po) = e
        .release(&order, &line, json!({ "start_date": "2027-03-01" }))
        .await;
    let n = id(&po);
    let cut = id(operation(&po, "Cut"));
    let weld = id(operation(&po, "Weld"));
    let uri = |op: &str, action: &str| format!("/production-orders/{n}/operations/{op}/{action}");

    // Production and the warehouse run operations; sales and viewers do not.
    for who in [SALES, VIEWER, TECHNICIAN] {
        assert_eq!(
            post(&e.app, who, &uri(&cut, "start"), json!({})).await.0,
            StatusCode::FORBIDDEN,
            "{who}"
        );
    }
    assert_eq!(e.order_status(&order).await, "in_planning");

    // Starting the first operation starts the order, and the sales order follows.
    let (status, started) = post(&e.app, STORES, &uri(&cut, "start"), json!({})).await;
    assert_eq!(status, StatusCode::OK, "{started}");
    assert_eq!(operation(&started, "Cut")["status"], "in_progress");
    assert!(!operation(&started, "Cut")["started_at"].is_null());
    assert_eq!(started["status"], "in_progress");
    assert!(!started["started_at"].is_null());
    assert_eq!(e.order_status(&order).await, "in_production");
    let (status, _) = post(&e.app, STORES, &uri(&cut, "start"), json!({})).await;
    assert_eq!(status, StatusCode::CONFLICT, "already started");

    // Finishing records the minutes and who finished it.
    for (what, body) in [
        ("negative", json!({ "actual_minutes": -1 })),
        ("silly", json!({ "actual_minutes": 5_000_000 })),
    ] {
        let (status, r) = post(&e.app, STORES, &uri(&cut, "finish"), body).await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{what}: {r}");
    }
    let (status, fin) = post(
        &e.app,
        STORES,
        &uri(&cut, "finish"),
        json!({ "actual_minutes": 65, "note": "  a burr on the first one  " }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{fin}");
    let cut_op = operation(&fin, "Cut");
    assert_eq!(cut_op["status"], "done");
    assert_eq!(cut_op["actual_minutes"], 65);
    assert_eq!(cut_op["completed_by_name"], STORES);
    assert!(!cut_op["completed_at"].is_null());
    assert_eq!(cut_op["notes"], "a burr on the first one");
    assert_eq!(fin["operations_done"], 1);
    assert_eq!(
        fin["status"], "in_progress",
        "finishing operations does not complete the order"
    );
    assert_eq!(
        post(&e.app, STORES, &uri(&cut, "finish"), json!({}))
            .await
            .0,
        StatusCode::CONFLICT,
        "already finished"
    );

    // An operation that was never started is started and finished at once, with the planned
    // minutes unless told otherwise. Reopening takes it back to work.
    let (status, fin) = post(&e.app, PLANNER, &uri(&weld, "finish"), json!({})).await;
    assert_eq!(status, StatusCode::OK, "{fin}");
    assert_eq!(operation(&fin, "Weld")["actual_minutes"], 120);
    assert!(!operation(&fin, "Weld")["started_at"].is_null());
    let (status, re) = post(&e.app, PLANNER, &uri(&weld, "reopen"), json!({})).await;
    assert_eq!(status, StatusCode::OK, "{re}");
    let weld_op = operation(&re, "Weld");
    assert_eq!(weld_op["status"], "in_progress");
    assert!(weld_op["actual_minutes"].is_null());
    assert!(weld_op["completed_by"].is_null());
    assert_eq!(re["operations_done"], 1);
    assert_eq!(
        post(&e.app, PLANNER, &uri(&weld, "reopen"), json!({}))
            .await
            .0,
        StatusCode::CONFLICT,
        "only a finished operation can be reopened"
    );
    let (status, _) = post(
        &e.app,
        PLANNER,
        &uri(&weld, "finish"),
        json!({ "actual_minutes": 140 }),
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    // Unknown operations and operations of another order are 404.
    other_order_is_not_found(&e, &uri(&weld, "start")).await;
    for action in ["start", "finish", "reopen"] {
        assert_eq!(
            post(&e.app, STORES, &uri(&uid(), action), json!({}))
                .await
                .0,
            StatusCode::NOT_FOUND,
            "{action}"
        );
    }

    // Every step is in the history of the order.
    let actions: Vec<String> = sqlx::query_scalar(
        "SELECT action FROM audit.events WHERE entity = 'production_order' AND entity_id = $1::uuid ORDER BY id",
    )
    .bind(&n)
    .fetch_all(&e.db)
    .await
    .unwrap();
    assert!(
        actions.contains(&"operation_started".to_string()),
        "{actions:?}"
    );
    assert_eq!(
        actions
            .iter()
            .filter(|a| *a == "operation_finished")
            .count(),
        3,
        "{actions:?}"
    );
    assert!(
        actions.contains(&"operation_reopened".to_string()),
        "{actions:?}"
    );
}

/// The operation `uri` belongs to one order; another order's id in the same place is 404.
async fn other_order_is_not_found(e: &Env, uri: &str) {
    let po = e.build_for_stock(FRAME, "1", json!({})).await;
    let other = uri.replacen(uri.split('/').nth(2).unwrap(), &id(&po), 1);
    assert_eq!(
        post(&e.app, STORES, &other, json!({})).await.0,
        StatusCode::NOT_FOUND,
        "{other}"
    );
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn operations_can_only_be_worked_on_while_the_order_is_open(db: PgPool) {
    let e = env(db).await;
    e.frame_parts().await;
    e.frame_routing().await;
    let po = e.build_for_stock(FRAME, "1", json!({})).await;
    let n = id(&po);
    let cut = id(operation(&po, "Cut"));
    let (status, c) = post(
        &e.app,
        PLANNER,
        &format!("/production-orders/{n}/cancel"),
        json!({ "reason": "not needed" }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{c}");
    for (method, action, body) in [
        (Method::POST, "start", json!({})),
        (Method::POST, "finish", json!({})),
        (Method::POST, "reopen", json!({})),
    ] {
        let (status, r) = api(
            &e.app,
            STORES,
            method,
            &format!("/production-orders/{n}/operations/{cut}/{action}"),
            Some(body),
        )
        .await;
        assert_eq!(status, StatusCode::CONFLICT, "{action}: {r}");
    }
    let (status, _) = put(
        &e.app,
        PLANNER,
        &format!("/production-orders/{n}/operations/{cut}"),
        json!({ "planned_start": "2027-03-01" }),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
    let (status, _) = post(
        &e.app,
        PLANNER,
        &format!("/production-orders/{n}/schedule"),
        json!({}),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
}

/// Completes a production order of two frames with `extra` merged into the body.
async fn complete_two(e: &Env, n: &str, extra: Value) -> (StatusCode, Value) {
    let mut body = json!({ "output": { "quantity": "2", "location_id": e.main } });
    for (k, v) in extra.as_object().unwrap() {
        body[k] = v.clone();
    }
    post(
        &e.app,
        STORES,
        &format!("/production-orders/{n}/complete"),
        body,
    )
    .await
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn completing_an_order_finishes_the_named_operations_and_skips_the_rest(db: PgPool) {
    let e = env(db).await;
    e.frame_parts().await;
    e.frame_routing().await;
    let po = e
        .build_for_stock(FRAME, "2", json!({ "start_date": "2027-03-01" }))
        .await;
    let n = id(&po);
    let cut = id(operation(&po, "Cut"));
    let weld = id(operation(&po, "Weld"));
    let complete = |extra: Value| complete_two(&e, &n, extra);

    // Refused: another order's operation, twice the same one, silly minutes. Nothing changes.
    let stranger = e.build_for_stock(FRAME, "1", json!({})).await;
    for (what, ops) in [
        (
            "an operation of another order",
            json!([{ "operation_id": id(&stranger["operations"][0]) }]),
        ),
        ("unknown", json!([{ "operation_id": uid() }])),
        (
            "twice",
            json!([{ "operation_id": cut }, { "operation_id": cut, "actual_minutes": 5 }]),
        ),
        (
            "negative",
            json!([{ "operation_id": cut, "actual_minutes": -5 }]),
        ),
    ] {
        let (status, r) = complete(json!({ "operations": ops })).await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{what}: {r}");
    }
    assert_eq!(e.production_order(PLANNER, &n).await["status"], "released");

    // Weld was finished on the floor already; the dialog names Cut (65 min) and leaves out Weld.
    let (status, _) = post(
        &e.app,
        STORES,
        &format!("/production-orders/{n}/operations/{weld}/finish"),
        json!({ "actual_minutes": 130 }),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (status, done) = complete(json!({ "operations": [
        { "operation_id": cut, "actual_minutes": 65 },
        { "operation_id": weld, "actual_minutes": 1 },
    ] }))
    .await;
    assert_eq!(status, StatusCode::OK, "{done}");
    assert_eq!(done["status"], "completed");
    assert_eq!(operation(&done, "Cut")["status"], "done");
    assert_eq!(operation(&done, "Cut")["actual_minutes"], 65);
    assert_eq!(
        operation(&done, "Weld")["actual_minutes"],
        130,
        "a finished operation is left alone"
    );
    assert!(done["scheduled_end"].is_null(), "nothing is open any more");
    assert_eq!(done["operations_done"], 2);
    let data: Value = sqlx::query_scalar(
        "SELECT data FROM audit.events WHERE entity = 'production_order' AND action = 'completed' AND entity_id = $1::uuid",
    )
    .bind(&n)
    .fetch_one(&e.db)
    .await
    .unwrap();
    assert_eq!(data["operations_finished"], 1);
    assert_eq!(data["operations_skipped"], 0);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn open_operations_never_stop_an_order_from_being_completed(db: PgPool) {
    let e = env(db).await;
    e.frame_parts().await;
    e.frame_routing().await;
    let po = e.build_for_stock(FRAME, "2", json!({})).await;
    let n = id(&po);
    let cut = id(operation(&po, "Cut"));
    // Cut is running when the order is completed without naming any operation (an older client
    // sends none): both open operations are skipped, with nothing recorded for them.
    post(
        &e.app,
        STORES,
        &format!("/production-orders/{n}/operations/{cut}/start"),
        json!({}),
    )
    .await;
    let (status, done) = post(
        &e.app,
        STORES,
        &format!("/production-orders/{n}/complete"),
        json!({ "output": { "quantity": "2", "location_id": e.main } }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{done}");
    for name in ["Cut", "Weld"] {
        let o = operation(&done, name);
        assert_eq!(o["status"], "skipped", "{name}");
        assert!(o["actual_minutes"].is_null());
        assert_eq!(o["completed_by_name"], STORES);
    }
    assert_eq!(done["operations_done"], 0);
    assert!(done["scheduled_end"].is_null());
    assert_eq!(done["behind_schedule"], false);
    // A skipped operation can be reopened for a correction only while the order is open: it is not.
    let (status, _) = post(
        &e.app,
        STORES,
        &format!("/production-orders/{n}/operations/{cut}/reopen"),
        json!({}),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
    let data: Value = sqlx::query_scalar(
        "SELECT data FROM audit.events WHERE entity = 'production_order' AND action = 'completed' AND entity_id = $1::uuid",
    )
    .bind(&n)
    .fetch_one(&e.db)
    .await
    .unwrap();
    assert_eq!(data["operations_skipped"], 2);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn planners_move_operations_and_schedule_the_rest_again(db: PgPool) {
    let e = env(db).await;
    e.frame_parts().await;
    let (saw, _weld) = e.frame_routing().await;
    let spare = e
        .work_centre("SPARE", json!({ "cost_per_hour": "99" }))
        .await;
    let retired = e.work_centre("OLD", json!({})).await;
    put(
        &e.app,
        ADMIN,
        &format!("/production/work-centres/{}", id(&retired)),
        json!({ "code": "OLD", "name": "Old", "active": false }),
    )
    .await;
    let (order, line) = e.order(FRAME, "2").await;
    let (_, po) = e
        .release(&order, &line, json!({ "start_date": "2027-03-01" }))
        .await;
    let n = id(&po);
    let cut = id(operation(&po, "Cut"));
    let weld_op = id(operation(&po, "Weld"));
    let edit = |op: &str| format!("/production-orders/{n}/operations/{op}");

    // Move Cut to another work centre and other dates: the rate is taken again.
    let (status, moved) = put(
        &e.app,
        PLANNER,
        &edit(&cut),
        json!({ "work_centre_id": id(&spare), "planned_start": "2027-03-08", "planned_end": "2027-03-09T00:00:00.000" }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{moved}");
    assert_eq!(operation(&moved, "Cut")["work_centre_code"], "SPARE");
    assert_eq!(
        dates(&moved, "Cut"),
        ("2027-03-08".into(), "2027-03-09".into())
    );
    let as_admin = e.production_order(ADMIN, &n).await;
    assert_eq!(dec(&operation(&as_admin, "Cut")["cost_rate"]), q("99"));
    assert_eq!(moved["scheduled_end"], "2027-03-09");
    // What is left out stays.
    let (status, moved) = put(
        &e.app,
        PLANNER,
        &edit(&cut),
        json!({ "planned_end": "2027-03-10" }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{moved}");
    assert_eq!(operation(&moved, "Cut")["work_centre_code"], "SPARE");
    assert_eq!(
        dates(&moved, "Cut"),
        ("2027-03-08".into(), "2027-03-10".into())
    );

    for (what, body) in [
        (
            "ends before it starts",
            json!({ "planned_start": "2027-03-20", "planned_end": "2027-03-19" }),
        ),
        (
            "only the end, before the start",
            json!({ "planned_end": "2027-03-01" }),
        ),
        (
            "an inactive work centre",
            json!({ "work_centre_id": id(&retired) }),
        ),
        ("an unknown work centre", json!({ "work_centre_id": uid() })),
    ] {
        let (status, r) = put(&e.app, PLANNER, &edit(&cut), body).await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{what}: {r}");
    }
    // Planners change plans; the floor and sales do not.
    for who in [STORES, SALES, VIEWER] {
        let (status, _) = put(
            &e.app,
            who,
            &edit(&cut),
            json!({ "planned_end": "2027-03-11" }),
        )
        .await;
        assert_eq!(status, StatusCode::FORBIDDEN, "{who}");
    }

    // Weld is running; scheduling again places only what has not started, after the running one.
    post(
        &e.app,
        STORES,
        &format!("{}/start", edit(&weld_op)),
        json!({}),
    )
    .await;
    let (status, ready) = put(
        &e.app,
        PLANNER,
        &format!("/production-orders/{n}"),
        json!({ "planned_ready_date": "2027-06-30" }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{ready}");
    let (status, again) = post(
        &e.app,
        PLANNER,
        &format!("/production-orders/{n}/schedule"),
        json!({ "start_date": "2027-04-05" }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{again}");
    // SPARE has the default week: Cut takes 50 minutes on Monday 5 April.
    assert_eq!(
        dates(&again, "Cut"),
        ("2027-04-05".into(), "2027-04-05".into())
    );
    assert_eq!(
        dates(&again, "Weld"),
        dates(&ready, "Weld"),
        "the running operation is not moved"
    );
    assert_eq!(
        again["planned_ready_date"], "2027-06-30",
        "the promise stays the planner's"
    );
    assert_eq!(again["scheduled_end"], "2027-04-05");
    // Nothing pending: scheduling again is fine and changes nothing.
    post(&e.app, STORES, &format!("{}/finish", edit(&cut)), json!({})).await;
    let (status, same) = post(
        &e.app,
        PLANNER,
        &format!("/production-orders/{n}/schedule"),
        json!({}),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{same}");
    assert_eq!(
        dates(&same, "Cut"),
        ("2027-04-05".into(), "2027-04-05".into())
    );
    for who in [STORES, SALES] {
        assert_eq!(
            post(
                &e.app,
                who,
                &format!("/production-orders/{n}/schedule"),
                json!({})
            )
            .await
            .0,
            StatusCode::FORBIDDEN,
            "{who}"
        );
    }
    // Scheduling is refused when a work centre has no working time at all.
    close(&e, Some(&saw), "2027-01-01", "2031-12-31").await;
    let (status, r) = put(
        &e.app,
        PLANNER,
        &edit(&weld_op),
        json!({ "work_centre_id": saw }),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "moving does not schedule: {r}");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn operations_stay_within_their_company(db: PgPool) {
    let e = env(db).await;
    e.frame_parts().await;
    e.frame_routing().await;
    let po = e.build_for_stock(FRAME, "1", json!({})).await;
    let n = id(&po);
    let cut = id(operation(&po, "Cut"));

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
    for action in ["start", "finish", "reopen"] {
        assert_eq!(
            post(
                &e.app,
                theirs,
                &format!("/production-orders/{n}/operations/{cut}/{action}"),
                json!({})
            )
            .await
            .0,
            StatusCode::NOT_FOUND,
            "{action}"
        );
    }
    assert_eq!(
        put(
            &e.app,
            theirs,
            &format!("/production-orders/{n}/operations/{cut}"),
            json!({})
        )
        .await
        .0,
        StatusCode::NOT_FOUND
    );
    assert_eq!(
        post(
            &e.app,
            theirs,
            &format!("/production-orders/{n}/schedule"),
            json!({})
        )
        .await
        .0,
        StatusCode::NOT_FOUND
    );
    assert_eq!(
        e.production_order(PLANNER, &n).await["operations"][0]["status"],
        "pending"
    );
}
