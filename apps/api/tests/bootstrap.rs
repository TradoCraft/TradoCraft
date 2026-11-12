//! `GET /api/v1/setup/status` and `POST /api/v1/setup/bootstrap` (ADR 0047). These tests start
//! from an empty database: they do not use `common::setup`, which loads the dev seed.

mod common;

use axum::http::{Method, StatusCode};
use common::{call, call_portal};
use serde_json::{json, Value};
use sqlx::PgPool;
use std::sync::Arc;
use tradocraft_core::auth::{bind_oidc_user, AuthConfig};
use tradocraft_core::companies::BootstrapConfig;
use tradocraft_core::environment::EnvironmentConfig;
use tradocraft_core::identity::{Claims, IdentityProviders, IdpSettings, ProviderConfig};
use tradocraft_core::{AppState, DocumentConfig};

fn app(db: PgPool, oidc: bool, token: Option<&str>) -> axum::Router {
    let auth = if oidc {
        AuthConfig::Oidc(IdentityProviders::new(
            IdpSettings::default(),
            Some(ProviderConfig::from_env(
                "https://issuer.invalid",
                "tradocraft",
            )),
        ))
    } else {
        AuthConfig::Dev {
            default_email: None,
        }
    };
    tradocraft_api::app_with_options(
        AppState {
            db,
            auth: Arc::new(auth),
            documents: Arc::new(DocumentConfig {
                typst_bin: "typst".into(),
                template_dir: "templates".into(),
            }),
        },
        EnvironmentConfig::default(),
        BootstrapConfig::new(token.map(str::to_string)),
    )
}

fn body(token: Option<&str>) -> Value {
    let mut b = json!({
        "name": "Fresh Co",
        "legal_name": "Fresh Company BV",
        "vat_number": "BE0123456749",
        "country_code": "BE",
        "currency": "EUR",
        "default_language": "en",
        "admin_email": "Boss@Fresh.example",
        "admin_display_name": "The Boss",
    });
    if let Some(t) = token {
        b["token"] = json!(t);
    }
    b
}

async fn post(app: &axum::Router, b: Value) -> (StatusCode, Value) {
    call_portal(app, None, Method::POST, "/api/v1/setup/bootstrap", Some(b)).await
}

async fn status(app: &axum::Router) -> Value {
    let (s, b) = call_portal(app, None, Method::GET, "/api/v1/setup/status", None).await;
    assert_eq!(s, StatusCode::OK);
    b
}

async fn count(db: &PgPool, sql: &str) -> i64 {
    sqlx::query_scalar(sql).fetch_one(db).await.unwrap()
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn bootstraps_an_empty_database_once(db: PgPool) {
    let app = app(db.clone(), false, None);
    let s = status(&app).await;
    assert_eq!(s["needs_setup"], true);
    assert_eq!(s["token_required"], false);
    assert_eq!(s["auth_mode"], "dev");

    let (st, res) = post(&app, body(None)).await;
    assert_eq!(st, StatusCode::CREATED, "{res}");
    assert_eq!(res["company"]["name"], "Fresh Co");
    assert_eq!(res["company"]["vat_number"], "BE0123456749");
    assert_eq!(res["company"]["default_language"], "en");
    assert_eq!(res["admin"]["email"], "boss@fresh.example");
    assert_eq!(res["admin"]["roles"], json!(["admin"]));
    assert!(!res.to_string().contains("token"));

    // What the company got.
    let cid = res["company"]["id"].as_str().unwrap();
    let q = |t: &str| format!("SELECT count(*) FROM {t} WHERE company_id = '{cid}'");
    assert_eq!(count(&db, &q("pricing.price_zones")).await, 5);
    let codes: Vec<String> = sqlx::query_scalar(&format!(
        "SELECT code FROM pricing.price_zones WHERE company_id = '{cid}' ORDER BY sort_order"
    ))
    .fetch_all(&db)
    .await
    .unwrap();
    assert_eq!(codes, ["Z1", "Z2", "Z3", "Z4", "Z5"]);
    assert!(count(&db, &q("core.number_sequences")).await >= 10);
    assert_eq!(count(&db, &q("inventory.warehouses")).await, 1);
    assert_eq!(
        count(
            &db,
            &format!("SELECT count(*) FROM inventory.locations WHERE company_id = '{cid}' AND kind = 'internal'")
        )
        .await,
        1
    );
    assert_eq!(
        count(
            &db,
            &format!("SELECT count(*) FROM inventory.locations WHERE company_id = '{cid}' AND warehouse_id IS NULL")
        )
        .await,
        7
    );
    // Units of measure are global and come with the migrations.
    assert!(count(&db, "SELECT count(*) FROM inventory.uoms").await >= 15);
    let (roles, default): (Vec<String>, bool) = sqlx::query_as(
        "SELECT uc.roles, uc.is_default FROM core.user_companies uc
         JOIN core.users u ON u.id = uc.user_id WHERE u.email = 'boss@fresh.example'",
    )
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(roles, ["admin"]);
    assert!(default);
    let legal: String = sqlx::query_scalar("SELECT legal_name FROM core.companies")
        .fetch_one(&db)
        .await
        .unwrap();
    assert_eq!(legal, "Fresh Company BV");

    // Audited.
    assert_eq!(
        count(
            &db,
            "SELECT count(*) FROM audit.events WHERE entity = 'company' AND action = 'bootstrapped'"
        )
        .await,
        1
    );

    // The second call is refused and the status no longer asks for setup.
    let (st, _) = post(&app, body(None)).await;
    assert_eq!(st, StatusCode::CONFLICT);
    assert_eq!(status(&app).await["needs_setup"], false);
    assert_eq!(count(&db, "SELECT count(*) FROM core.companies").await, 1);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_new_admin_can_work(db: PgPool) {
    let app = app(db, false, None);
    let (st, _) = post(&app, body(None)).await;
    assert_eq!(st, StatusCode::CREATED);
    let (st, me) = call(&app, "boss@fresh.example", Method::GET, "/api/v1/me", None).await;
    assert_eq!(st, StatusCode::OK, "{me}");
    assert_eq!(me["company"]["name"], "Fresh Co");
    assert_eq!(me["roles"], json!(["admin"]));
    let (st, p) = call(
        &app,
        "boss@fresh.example",
        Method::POST,
        "/api/v1/products",
        Some(json!({"code": "P-1", "name": "First product", "unit": "pcs", "product_type": "purchased", "vat_rate": "21"})),
    )
    .await;
    assert!(st.is_success(), "{st} {p}");
    // Numbering and the warehouse are usable: a quotation number can be allocated later; the
    // stock setup lists the warehouse.
    let (st, w) = call(
        &app,
        "boss@fresh.example",
        Method::GET,
        "/api/v1/inventory/warehouses",
        None,
    )
    .await;
    assert_eq!(st, StatusCode::OK, "{w}");
    assert_eq!(w.as_array().unwrap().len(), 1);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_token_is_enforced_when_configured(db: PgPool) {
    let app = app(db.clone(), false, Some("s3cret-token"));
    let s = status(&app).await;
    assert_eq!(s["token_required"], true);
    assert_eq!(s["needs_setup"], true);
    let (st, _) = post(&app, body(None)).await;
    assert_eq!(st, StatusCode::FORBIDDEN);
    let (st, _) = post(&app, body(Some("wrong"))).await;
    assert_eq!(st, StatusCode::FORBIDDEN);
    assert_eq!(count(&db, "SELECT count(*) FROM core.companies").await, 0);
    let (st, res) = post(&app, body(Some("s3cret-token"))).await;
    assert_eq!(st, StatusCode::CREATED, "{res}");
    assert!(!res.to_string().contains("s3cret-token"));
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn outside_dev_mode_the_endpoint_needs_a_token(db: PgPool) {
    // No BOOTSTRAP_TOKEN with OIDC: disabled.
    let disabled = app(db.clone(), true, None);
    let s = status(&disabled).await;
    assert_eq!(s["needs_setup"], false);
    assert_eq!(s["token_required"], false);
    assert_eq!(s["auth_mode"], "oidc");
    let (st, _) = post(&disabled, body(None)).await;
    assert_eq!(st, StatusCode::NOT_FOUND);

    // With the token: works, and the admin is pre-provisioned for sign-in through the IdP.
    let enabled = app(db.clone(), true, Some("tok"));
    assert_eq!(status(&enabled).await["needs_setup"], true);
    let (st, _) = post(&enabled, body(Some("nope"))).await;
    assert_eq!(st, StatusCode::FORBIDDEN);
    let (st, res) = post(&enabled, body(Some("tok"))).await;
    assert_eq!(st, StatusCode::CREATED, "{res}");
    assert_eq!(res["auth_mode"], "oidc");
    let subject: Option<String> = sqlx::query_scalar(
        "SELECT oidc_subject FROM core.users WHERE email = 'boss@fresh.example'",
    )
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(subject, None, "bound at the first sign-in");

    // First sign-in through the identity provider. The token signature is checked by the
    // verifier before this point; the binding step takes the verified claims.
    let state = AppState {
        db: db.clone(),
        auth: Arc::new(AuthConfig::Dev {
            default_email: None,
        }),
        documents: Arc::new(DocumentConfig {
            typst_bin: "typst".into(),
            template_dir: "templates".into(),
        }),
    };
    let provider = ProviderConfig::from_env("https://issuer.invalid", "tradocraft");
    let claims =
        |email: Option<&str>, verified: Option<bool>| Claims::simple("idp|boss", email, verified);
    for (email, verified) in [
        (Some("boss@fresh.example"), Some(false)),
        (Some("boss@fresh.example"), None),
        (None, Some(true)),
    ] {
        assert!(
            bind_oidc_user(&state, &provider, &claims(email, verified))
                .await
                .is_err(),
            "{email:?} {verified:?}"
        );
    }
    let subject: Option<String> = sqlx::query_scalar(
        "SELECT oidc_subject FROM core.users WHERE email = 'boss@fresh.example'",
    )
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(subject, None, "nothing bound for unverified identities");

    let uid = bind_oidc_user(
        &state,
        &provider,
        &claims(Some("Boss@Fresh.example"), Some(true)),
    )
    .await
    .unwrap();
    assert_eq!(uid.to_string(), res["admin"]["user_id"].as_str().unwrap());
    let (subject, roles, company): (String, Vec<String>, uuid::Uuid) = sqlx::query_as(
        "SELECT u.oidc_subject, uc.roles, uc.company_id FROM core.users u
         JOIN core.user_companies uc ON uc.user_id = u.id WHERE u.id = $1 AND uc.is_default",
    )
    .bind(uid)
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(subject, "idp|boss");
    assert_eq!(roles, ["admin"]);
    assert_eq!(company.to_string(), res["company"]["id"].as_str().unwrap());
    // The bound subject now signs in without the e-mail claim.
    let again = Claims::simple("idp|boss", None, None);
    assert_eq!(
        bind_oidc_user(&state, &provider, &again).await.unwrap(),
        uid
    );
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn refuses_invalid_input_and_creates_nothing(db: PgPool) {
    let app = app(db.clone(), false, None);
    let mut b = body(None);
    b["currency"] = json!("EURO");
    let (st, _) = post(&app, b).await;
    assert_eq!(st, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(count(&db, "SELECT count(*) FROM core.companies").await, 0);
    assert_eq!(count(&db, "SELECT count(*) FROM core.users").await, 0);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn concurrent_calls_create_one_company(db: PgPool) {
    let app = app(db.clone(), false, None);
    let (a, b) = tokio::join!(post(&app, body(None)), post(&app, body(None)));
    let mut codes = [a.0.as_u16(), b.0.as_u16()];
    codes.sort();
    assert_eq!(codes, [201, 409]);
    assert_eq!(count(&db, "SELECT count(*) FROM core.companies").await, 1);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn provision_refuses_a_name_clash(db: PgPool) {
    let spec: tradocraft_core::companies::ProvisionSpec =
        serde_json::from_value(body(None)).unwrap();
    let mut tx = db.begin().await.unwrap();
    tradocraft_core::companies::provision(&mut tx, &spec)
        .await
        .unwrap();
    let mut other = spec.clone();
    other.name = "FRESH CO".into();
    other.admin_email = "other@fresh.example".into();
    let err = tradocraft_core::companies::provision(&mut tx, &other)
        .await
        .unwrap_err();
    assert!(
        matches!(err, tradocraft_core::AppError::Conflict(_)),
        "{err}"
    );
}
