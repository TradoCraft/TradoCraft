//! Module switches and user administration (ADR 0028).

mod common;

use axum::http::{Method, StatusCode};
use common::{call, setup};
use serde_json::{json, Value};
use sqlx::PgPool;

const ADMIN: &str = "admin@example.com";
const SALES: &str = "sales@example.com";
const SUPPORT: &str = "support@example.com";
const VIEWER: &str = "viewer@example.com";
const ADMIN_ID: &str = "00000000-0000-7000-8000-000000000101";
const SALES_ID: &str = "00000000-0000-7000-8000-000000000102";
const COMPANY: &str = "00000000-0000-7000-8000-000000000001";

async fn get(app: &axum::Router, user: &str, uri: &str) -> (StatusCode, Value) {
    call(app, user, Method::GET, uri, None).await
}
async fn post(app: &axum::Router, user: &str, uri: &str, body: Value) -> (StatusCode, Value) {
    call(app, user, Method::POST, uri, Some(body)).await
}
async fn put(app: &axum::Router, user: &str, uri: &str, body: Value) -> (StatusCode, Value) {
    call(app, user, Method::PUT, uri, Some(body)).await
}

async fn set_modules(app: &axum::Router, disabled: Value) -> (StatusCode, Value) {
    put(
        app,
        ADMIN,
        "/api/v1/admin/modules",
        json!({ "disabled_modules": disabled }),
    )
    .await
}

fn perms(me: &Value) -> Vec<&str> {
    me["permissions"]
        .as_array()
        .unwrap()
        .iter()
        .map(|p| p.as_str().unwrap())
        .collect()
}

fn module_enabled(me: &Value, code: &str) -> bool {
    me["modules"]
        .as_array()
        .unwrap()
        .iter()
        .find(|m| m["code"] == code)
        .unwrap_or_else(|| panic!("module {code}"))["enabled"]
        .as_bool()
        .unwrap()
}

async fn mails_to(db: &PgPool, address: &str) -> i64 {
    sqlx::query_scalar("SELECT count(*) FROM core.mail_outbox WHERE lower(to_address) = $1")
        .bind(address)
        .fetch_one(db)
        .await
        .unwrap()
}

fn new_user(email: &str) -> Value {
    json!({ "email": email, "display_name": "Nina New", "roles": ["sales"], "disabled_modules": [] })
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn only_the_admin_reaches_the_administration(db: PgPool) {
    let app = setup(db).await;
    let uid = format!("/api/v1/admin/users/{SALES_ID}");
    for user in [
        SALES,
        SUPPORT,
        VIEWER,
        "manager@example.com",
        "technician@example.com",
    ] {
        for (method, uri, body) in [
            (Method::GET, "/api/v1/roles".to_string(), None),
            (Method::GET, "/api/v1/admin/modules".into(), None),
            (
                Method::PUT,
                "/api/v1/admin/modules".into(),
                Some(json!({ "disabled_modules": [] })),
            ),
            (Method::GET, "/api/v1/admin/users".into(), None),
            (
                Method::POST,
                "/api/v1/admin/users".into(),
                Some(new_user("x@example.com")),
            ),
            (
                Method::PUT,
                uid.clone(),
                Some(
                    json!({ "display_name": "X", "roles": ["sales"], "disabled_modules": [], "active": true }),
                ),
            ),
            (Method::POST, format!("{uid}/invite"), None),
        ] {
            let (status, _) = call(&app, user, method.clone(), &uri, body).await;
            assert_eq!(status, StatusCode::FORBIDDEN, "{user} {method} {uri}");
        }
    }
    let (status, roles) = get(&app, ADMIN, "/api/v1/roles").await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(roles.as_array().unwrap().len(), 17);
    let admin = &roles[0];
    assert_eq!(admin["role"], "admin");
    // The roles of the parcel hand-over come last, with their permissions.
    let role_perms = |name: &str| -> Vec<String> {
        roles
            .as_array()
            .unwrap()
            .iter()
            .find(|r| r["role"] == name)
            .unwrap_or_else(|| panic!("role {name}"))["permissions"]
            .as_array()
            .unwrap()
            .iter()
            .map(|p| p.as_str().unwrap().to_string())
            .collect()
    };
    assert_eq!(roles[14]["role"], "goods_in");
    assert_eq!(roles[15]["role"], "repair_intake");
    assert_eq!(roles[16]["role"], "integration");
    assert_eq!(
        role_perms("integration"),
        [
            "customers.read",
            "products.read",
            "quotations.import",
            "quotations.read"
        ]
    );
    let goods_in = role_perms("goods_in");
    assert!(goods_in.contains(&"packages.write".to_string()));
    assert!(!goods_in.contains(&"packages.open".to_string()));
    assert!(!goods_in.contains(&"repairs.route".to_string()));
    let intake = role_perms("repair_intake");
    for p in ["packages.open", "repairs.intake", "repairs.route"] {
        assert!(intake.contains(&p.to_string()), "{p}");
    }
    assert!(admin["permissions"]
        .as_array()
        .unwrap()
        .iter()
        .any(|p| p == "users.admin"));
    let viewer = roles
        .as_array()
        .unwrap()
        .iter()
        .find(|r| r["role"] == "viewer")
        .unwrap();
    let list: Vec<&str> = viewer["permissions"]
        .as_array()
        .unwrap()
        .iter()
        .map(|p| p.as_str().unwrap())
        .collect();
    let mut sorted = list.clone();
    sorted.sort();
    assert_eq!(list, sorted);
    assert!(!list.contains(&"users.admin"));
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn creating_a_user_queues_one_invitation_and_the_first_membership_is_the_default(db: PgPool) {
    let app = setup(db.clone()).await;
    let (status, u) = post(
        &app,
        ADMIN,
        "/api/v1/admin/users",
        new_user(" Nina@Example.com "),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{u}");
    assert_eq!(u["email"], "nina@example.com");
    assert_eq!(u["active"], true);
    assert_eq!(u["has_signed_in"], false);
    assert_eq!(mails_to(&db, "nina@example.com").await, 1);
    let (subject, body): (String, String) = sqlx::query_as(
        "SELECT subject, body FROM core.mail_outbox WHERE to_address = 'nina@example.com'",
    )
    .fetch_one(&db)
    .await
    .unwrap();
    assert!(subject.contains("Demo Manufacturing BV"), "{subject}");
    assert!(body.contains("Nina New") && body.contains("nina@example.com"));
    let default: bool = sqlx::query_scalar(
        "SELECT is_default FROM core.user_companies WHERE user_id = $1::uuid AND company_id = $2::uuid",
    )
    .bind(u["user_id"].as_str().unwrap())
    .bind(COMPANY)
    .fetch_one(&db)
    .await
    .unwrap();
    assert!(default);

    // The new person can use the dev header straight away and sees the sales permissions.
    let (status, me) = get(&app, "nina@example.com", "/api/v1/me").await;
    assert_eq!(status, StatusCode::OK);
    assert!(perms(&me).contains(&"quotations.write"));

    // Already a member (any letter case): 409, and no second mail.
    let (status, _) = post(
        &app,
        ADMIN,
        "/api/v1/admin/users",
        new_user("NINA@example.com"),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!(mails_to(&db, "nina@example.com").await, 1);

    // Validation.
    for bad in [
        json!({ "email": "nope", "display_name": "A", "roles": ["sales"] }),
        json!({ "email": "b@example.com", "display_name": " ", "roles": ["sales"] }),
        json!({ "email": "b@example.com", "display_name": "B", "roles": [] }),
        json!({ "email": "b@example.com", "display_name": "B", "roles": ["intern"] }),
        json!({ "email": "b@example.com", "display_name": "B", "roles": ["sales"], "disabled_modules": ["bogus"] }),
        json!({ "email": "b@example.com", "display_name": "B", "roles": ["sales"], "disabled_modules": ["products"] }),
    ] {
        let (status, body) = post(&app, ADMIN, "/api/v1/admin/users", bad.clone()).await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{bad} {body}");
    }
    assert_eq!(mails_to(&db, "b@example.com").await, 0);

    // Listed with everyone else, with the audit trail written.
    let (_, list) = get(&app, ADMIN, "/api/v1/admin/users").await;
    assert!(list
        .as_array()
        .unwrap()
        .iter()
        .any(|m| m["email"] == "nina@example.com"));
    let audited: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM audit.events WHERE entity = 'user' AND action = 'create_member'",
    )
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(audited, 1);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn an_existing_person_in_another_company_only_gets_a_membership(db: PgPool) {
    let app = setup(db.clone()).await;
    sqlx::query(
        "INSERT INTO core.companies (id, name) VALUES ('00000000-0000-7000-8000-0000000000c2', 'Second BV')",
    )
    .execute(&db)
    .await
    .unwrap();
    sqlx::query(
        "INSERT INTO core.user_companies (user_id, company_id, roles, is_default)
         VALUES ($1::uuid, '00000000-0000-7000-8000-0000000000c2', '{admin}', false)",
    )
    .bind(ADMIN_ID)
    .execute(&db)
    .await
    .unwrap();
    // Admin of company 2 adds the sales user (who exists in company 1) under another name.
    let r = call(
        &app,
        ADMIN,
        Method::POST,
        "/api/v1/admin/users",
        Some(json!({ "email": SALES, "display_name": "Renamed", "roles": ["viewer"] })),
    )
    .await;
    // Active company is the default one (company 1), where the person already is.
    assert_eq!(r.0, StatusCode::CONFLICT);
    // In company 2 the membership is added; the existing name is kept and it is not the default.
    let req = axum::http::Request::builder()
        .method(Method::POST)
        .uri("/api/v1/admin/users")
        .header("x-dev-user", ADMIN)
        .header("x-company-id", "00000000-0000-7000-8000-0000000000c2")
        .header("content-type", "application/json")
        .body(axum::body::Body::from(
            json!({ "email": SALES, "display_name": "Renamed", "roles": ["viewer"] }).to_string(),
        ))
        .unwrap();
    use tower::ServiceExt;
    let res = app.clone().oneshot(req).await.unwrap();
    assert_eq!(res.status(), StatusCode::CREATED);
    let name: String = sqlx::query_scalar("SELECT display_name FROM core.users WHERE email = $1")
        .bind(SALES)
        .fetch_one(&db)
        .await
        .unwrap();
    assert_eq!(name, "Sales User");
    let defaults: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM core.user_companies WHERE user_id = $1::uuid AND is_default",
    )
    .bind(SALES_ID)
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(defaults, 1);
    assert_eq!(mails_to(&db, SALES).await, 1);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn invite_resends_until_the_person_has_signed_in(db: PgPool) {
    let app = setup(db.clone()).await;
    let (_, u) = post(
        &app,
        ADMIN,
        "/api/v1/admin/users",
        new_user("nina@example.com"),
    )
    .await;
    let id = u["user_id"].as_str().unwrap();
    let uri = format!("/api/v1/admin/users/{id}/invite");
    let (status, _) = post(&app, ADMIN, &uri, json!({})).await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    assert_eq!(mails_to(&db, "nina@example.com").await, 2);

    sqlx::query("UPDATE core.users SET oidc_subject = 'sub-1' WHERE id = $1::uuid")
        .bind(id)
        .execute(&db)
        .await
        .unwrap();
    let (status, _) = post(&app, ADMIN, &uri, json!({})).await;
    assert_eq!(status, StatusCode::CONFLICT);
    assert_eq!(mails_to(&db, "nina@example.com").await, 2);
    let (_, list) = get(&app, ADMIN, "/api/v1/admin/users").await;
    let nina = list
        .as_array()
        .unwrap()
        .iter()
        .find(|m| m["email"] == "nina@example.com")
        .unwrap();
    assert_eq!(nina["has_signed_in"], true);

    let unknown = "/api/v1/admin/users/00000000-0000-7000-8000-0000000000aa/invite";
    assert_eq!(
        post(&app, ADMIN, unknown, json!({})).await.0,
        StatusCode::NOT_FOUND
    );
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn updating_and_deactivating_members_with_their_guards(db: PgPool) {
    let app = setup(db.clone()).await;
    let uri = format!("/api/v1/admin/users/{SALES_ID}");
    let body = |roles: Value, active: bool| json!({ "display_name": "Sally Sales", "roles": roles, "disabled_modules": [], "active": active });
    let (status, u) = put(&app, ADMIN, &uri, body(json!(["viewer"]), true)).await;
    assert_eq!(status, StatusCode::OK, "{u}");
    assert_eq!(u["display_name"], "Sally Sales");
    assert_eq!(u["roles"], json!(["viewer"]));
    // The new roles apply on the next request.
    let (_, me) = get(&app, SALES, "/api/v1/me").await;
    assert!(!perms(&me).contains(&"quotations.write"));
    assert_eq!(
        put(&app, ADMIN, &uri, body(json!(["intern"]), true))
            .await
            .0,
        StatusCode::UNPROCESSABLE_ENTITY
    );
    assert_eq!(
        put(
            &app,
            ADMIN,
            "/api/v1/admin/users/00000000-0000-7000-8000-0000000000aa",
            body(json!(["sales"]), true)
        )
        .await
        .0,
        StatusCode::NOT_FOUND
    );

    // Guards on oneself.
    let me_uri = format!("/api/v1/admin/users/{ADMIN_ID}");
    let (status, _) = put(&app, ADMIN, &me_uri, body(json!(["admin"]), false)).await;
    assert_eq!(status, StatusCode::CONFLICT, "cannot deactivate yourself");
    let (status, _) = put(&app, ADMIN, &me_uri, body(json!(["sales"]), true)).await;
    assert_eq!(status, StatusCode::CONFLICT, "cannot drop own admin role");
    let (status, _) = put(&app, ADMIN, &me_uri, body(json!(["admin", "sales"]), true)).await;
    assert_eq!(status, StatusCode::OK);

    // A second admin can be demoted, because the acting admin stays.
    let (status, _) = put(&app, ADMIN, &uri, body(json!(["admin"]), true)).await;
    assert_eq!(status, StatusCode::OK);
    let (status, _) = put(&app, SALES, &me_uri, body(json!(["admin"]), false)).await;
    assert_eq!(
        status,
        StatusCode::OK,
        "the other admin may deactivate the first"
    );
    // ...and then the first admin is locked out of the company, while the data stays.
    let (status, locked_out) = get(&app, ADMIN, "/api/v1/me").await;
    assert_eq!(status, StatusCode::FORBIDDEN, "{locked_out}");
    let (_, list) = get(&app, SALES, "/api/v1/admin/users").await;
    let first = list
        .as_array()
        .unwrap()
        .iter()
        .find(|m| m["email"] == ADMIN)
        .unwrap();
    assert_eq!(first["active"], false);
    // They no longer show up as colleagues to assign work to.
    let (_, users) = get(&app, SALES, "/api/v1/users").await;
    assert!(!users
        .as_array()
        .unwrap()
        .iter()
        .any(|u| u["email"] == ADMIN));
    // Reactivating restores access.
    let (status, _) = put(&app, SALES, &me_uri, body(json!(["admin"]), true)).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(get(&app, ADMIN, "/api/v1/me").await.0, StatusCode::OK);

    let audited: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM audit.events WHERE entity = 'user' AND action = 'update_member'",
    )
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(audited, 5);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_deactivated_member_is_refused_everywhere(db: PgPool) {
    let app = setup(db).await;
    let uri = format!("/api/v1/admin/users/{SALES_ID}");
    let (status, _) = put(
        &app,
        ADMIN,
        &uri,
        json!({ "display_name": "Sales User", "roles": ["sales"], "disabled_modules": [], "active": false }),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    for path in ["/api/v1/me", "/api/v1/quotations", "/api/v1/users"] {
        assert_eq!(
            get(&app, SALES, path).await.0,
            StatusCode::FORBIDDEN,
            "{path}"
        );
    }
    // The invitation is not resent to a deactivated member.
    assert_eq!(
        post(&app, ADMIN, &format!("{uri}/invite"), json!({}))
            .await
            .0,
        StatusCode::CONFLICT
    );
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_module_the_company_switches_off_is_gone_for_everyone(db: PgPool) {
    let app = setup(db).await;
    let (_, mods) = get(&app, ADMIN, "/api/v1/admin/modules").await;
    let codes: Vec<&str> = mods
        .as_array()
        .unwrap()
        .iter()
        .map(|m| m["code"].as_str().unwrap())
        .collect();
    assert_eq!(
        codes,
        [
            "customers",
            "products",
            "sales",
            "engineering",
            "inventory",
            "helpdesk",
            "kb",
            "repairs",
            "field",
            "purchasing",
            "configurator",
            "delivery",
            "production",
            "reports",
            "finance",
            "todo"
        ]
    );
    assert!(mods
        .as_array()
        .unwrap()
        .iter()
        .all(|m| m["enabled"] == true));
    let sales_mod = &mods[2];
    assert_eq!(sales_mod["requires"], json!(["customers", "products"]));

    assert_eq!(
        get(&app, SALES, "/api/v1/kb/entries").await.0,
        StatusCode::OK
    );
    assert_eq!(
        get(&app, SALES, "/api/v1/quotations").await.0,
        StatusCode::OK
    );
    let (_, me) = get(&app, SALES, "/api/v1/me").await;
    assert!(perms(&me).contains(&"kb.read"));
    assert!(module_enabled(&me, "kb"));

    let (status, mods) = set_modules(
        &app,
        json!(["kb", "sales", "configurator", "delivery", "production"]),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{mods}");
    assert_eq!(mods[6]["enabled"], false);
    assert_eq!(mods[2]["enabled"], false);

    for user in [ADMIN, SALES] {
        let (status, body) = get(&app, user, "/api/v1/kb/entries").await;
        assert_eq!(status, StatusCode::FORBIDDEN, "{user}");
        assert!(
            body["message"]
                .as_str()
                .unwrap()
                .contains("module kb is disabled"),
            "{body}"
        );
        assert_eq!(
            get(&app, user, "/api/v1/quotations").await.0,
            StatusCode::FORBIDDEN
        );
        let (_, me) = get(&app, user, "/api/v1/me").await;
        assert!(!perms(&me).iter().any(|p| p.starts_with("kb.")
            || p.starts_with("quotations.")
            || p.starts_with("orders.")));
        assert!(!module_enabled(&me, "kb") && !module_enabled(&me, "sales"));
        assert!(module_enabled(&me, "products"));
    }
    // Other modules are untouched, and the admin keeps the administration.
    assert_eq!(get(&app, SALES, "/api/v1/products").await.0, StatusCode::OK);
    let (_, me) = get(&app, ADMIN, "/api/v1/me").await;
    assert!(perms(&me).contains(&"users.admin"));

    // Switching it on again restores everything.
    assert_eq!(set_modules(&app, json!([])).await.0, StatusCode::OK);
    assert_eq!(
        get(&app, SALES, "/api/v1/kb/entries").await.0,
        StatusCode::OK
    );
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn module_dependencies_and_codes_are_validated(db: PgPool) {
    let app = setup(db.clone()).await;
    for bad in [json!(["bogus"]), json!(["customers"]), json!(["products"])] {
        let (status, body) = set_modules(&app, bad.clone()).await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{bad} {body}");
    }
    let (status, body) = set_modules(&app, json!(["customers"])).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    assert!(
        body["message"].as_str().unwrap().contains("requires"),
        "{body}"
    );
    // Nothing was stored by the refused calls.
    let stored: Vec<String> =
        sqlx::query_scalar("SELECT unnest(disabled_modules) FROM core.companies")
            .fetch_all(&db)
            .await
            .unwrap();
    assert!(stored.is_empty());
    // Taking the dependants down with it is fine.
    let (status, _) = set_modules(
        &app,
        json!([
            "customers",
            "sales",
            "repairs",
            "field",
            "configurator",
            "delivery",
            "production"
        ]),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let audited: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM audit.events WHERE entity = 'company' AND action = 'set_modules'",
    )
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(audited, 1);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_user_override_narrows_but_cannot_widen_the_company(db: PgPool) {
    let app = setup(db).await;
    let uri = format!("/api/v1/admin/users/{SALES_ID}");
    let body = |disabled: Value| json!({ "display_name": "Sales User", "roles": ["sales"], "disabled_modules": disabled, "active": true });
    // Only this user loses the helpdesk.
    let (status, u) = put(&app, ADMIN, &uri, body(json!(["helpdesk"]))).await;
    assert_eq!(status, StatusCode::OK, "{u}");
    assert_eq!(u["disabled_modules"], json!(["helpdesk"]));
    assert_eq!(
        get(&app, SALES, "/api/v1/tickets").await.0,
        StatusCode::FORBIDDEN
    );
    assert_eq!(
        get(&app, SUPPORT, "/api/v1/tickets").await.0,
        StatusCode::OK
    );
    let (_, me) = get(&app, SALES, "/api/v1/me").await;
    assert!(!module_enabled(&me, "helpdesk"));
    assert!(module_enabled(
        &get(&app, SUPPORT, "/api/v1/me").await.1,
        "helpdesk"
    ));
    assert!(!perms(&me).iter().any(|p| p.starts_with("helpdesk.")));

    // The user's dependencies are checked too: sales needs products.
    let (status, _) = put(&app, ADMIN, &uri, body(json!(["products"]))).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    let (status, _) = put(&app, ADMIN, &uri, body(json!(["bogus"]))).await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    // A module the company switched off stays off, whatever the user's own list says.
    assert_eq!(set_modules(&app, json!(["kb"])).await.0, StatusCode::OK);
    let (status, _) = put(&app, ADMIN, &uri, body(json!([]))).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(
        get(&app, SALES, "/api/v1/kb/entries").await.0,
        StatusCode::FORBIDDEN
    );
    assert_eq!(
        get(&app, SALES, "/api/v1/tickets").await.0,
        StatusCode::OK,
        "the personal switch was cleared"
    );
    let (_, mods) = get(&app, ADMIN, "/api/v1/admin/modules").await;
    assert_eq!(mods[6]["enabled"], false);
}
