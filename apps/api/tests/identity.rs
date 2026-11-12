//! Configurable identity providers (ADR 0052): the registry and hardened verifier against a mock
//! identity provider, the e-mail policies, and the admin API.

mod common;

use std::sync::Arc;
use std::time::Duration;

use axum::body::Body;
use axum::http::{Method, Request, StatusCode};
use base64::Engine;
use common::call;
use common::idp::{self, MockIdp};
use http_body_util::BodyExt;
use jsonwebtoken::{Algorithm, EncodingKey};
use serde_json::{json, Map, Value};
use sqlx::PgPool;
use tower::ServiceExt;
use tradocraft_core::auth::{bind_oidc_user, AuthConfig};
use tradocraft_core::companies::BootstrapConfig;
use tradocraft_core::environment::EnvironmentConfig;
use tradocraft_core::identity::{
    Claims, EmailPolicy, IdentityProviders, IdpSettings, ProviderConfig, ProviderSource,
};
use tradocraft_core::{AppState, DocumentConfig};

const BASE: &str = "/api/v1/admin/identity-providers";

fn settings() -> IdpSettings {
    IdpSettings {
        allow_insecure_urls: true,
        jwks_ttl: Duration::from_secs(3600),
        refresh_throttle: Duration::from_millis(300),
    }
}

fn state_with(db: PgPool, auth: AuthConfig) -> AppState {
    AppState {
        db,
        auth: Arc::new(auth),
        documents: Arc::new(DocumentConfig {
            typst_bin: "typst".into(),
            template_dir: "templates".into(),
        }),
    }
}

/// An OIDC-mode app on the dev seed with the given registry settings and environment provider.
async fn oidc_app(
    db: PgPool,
    settings: IdpSettings,
    env: Option<ProviderConfig>,
) -> (axum::Router, AppState) {
    sqlx::raw_sql(tradocraft_api::DEV_SEED_SQL)
        .execute(&db)
        .await
        .unwrap();
    let providers = IdentityProviders::new(settings.clone(), env);
    providers.reload(&db).await.unwrap();
    let state = state_with(db, AuthConfig::Oidc(providers));
    let app = tradocraft_api::app_with_identity(
        state.clone(),
        EnvironmentConfig::default(),
        BootstrapConfig::default(),
        &tradocraft_core::cors::CorsConfig::Any,
        settings,
    );
    (app, state)
}

async fn reload(state: &AppState) {
    if let AuthConfig::Oidc(p) = state.auth.as_ref() {
        p.reload(&state.db).await.unwrap();
    }
}

async fn bcall(
    app: &axum::Router,
    token: Option<&str>,
    method: Method,
    uri: &str,
    body: Option<Value>,
) -> (StatusCode, Value) {
    let mut req = Request::builder().method(method).uri(uri);
    if let Some(t) = token {
        req = req.header("authorization", format!("Bearer {t}"));
    }
    let body = match body {
        Some(b) => {
            req = req.header("content-type", "application/json");
            Body::from(b.to_string())
        }
        None => Body::empty(),
    };
    let res = app.clone().oneshot(req.body(body).unwrap()).await.unwrap();
    let status = res.status();
    let bytes = res.into_body().collect().await.unwrap().to_bytes();
    (
        status,
        serde_json::from_slice(&bytes).unwrap_or(Value::Null),
    )
}

async fn me(app: &axum::Router, token: &str) -> (StatusCode, Value) {
    bcall(app, Some(token), Method::GET, "/api/v1/me", None).await
}

async fn insert_provider(db: &PgPool, idp: &MockIdp, name: &str, aud: &str) -> uuid::Uuid {
    let id = uuid::Uuid::now_v7();
    sqlx::query(
        "INSERT INTO core.identity_providers (id, name, issuer, audience) VALUES ($1,$2,$3,$4)",
    )
    .bind(id)
    .bind(name)
    .bind(&idp.issuer)
    .bind(aud)
    .execute(db)
    .await
    .unwrap();
    id
}

/// Valid claims of `idp` for a user with a verified e-mail address.
fn user_claims(idp: &MockIdp, aud: &str, sub: &str, email: &str) -> Value {
    let mut c = idp.claims(aud, sub);
    c["email"] = json!(email);
    c["email_verified"] = json!(true);
    c
}

fn b64(v: &Value) -> String {
    base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(v.to_string())
}

async fn subject_of(db: &PgPool, email: &str) -> Option<String> {
    sqlx::query_scalar("SELECT oidc_subject FROM core.users WHERE email = $1")
        .bind(email)
        .fetch_one(db)
        .await
        .unwrap()
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn picks_the_provider_by_issuer_and_rejects_bad_tokens(db: PgPool) {
    let a = MockIdp::start("a", "ka", 0).await;
    let b = MockIdp::start("b", "kb", 1).await;
    let (app, state) = oidc_app(db.clone(), settings(), None).await;
    insert_provider(&db, &a, "A", "aud-a").await;
    insert_provider(&db, &b, "B", "aud-b").await;
    reload(&state).await;

    // Two providers at once; the same `sub` at two issuers is two identities.
    let ta = a.token(
        "ka",
        0,
        &user_claims(&a, "aud-a", "same", "admin@example.com"),
    );
    let tb = b.token(
        "kb",
        1,
        &user_claims(&b, "aud-b", "same", "sales@example.com"),
    );
    assert_eq!(me(&app, &ta).await.0, StatusCode::OK);
    let (st, who) = me(&app, &tb).await;
    assert_eq!(st, StatusCode::OK);
    assert_eq!(who["email"], "sales@example.com");
    assert_eq!(
        subject_of(&db, "admin@example.com").await,
        Some(format!("{}|same", a.issuer))
    );
    assert_eq!(
        subject_of(&db, "sales@example.com").await,
        Some(format!("{}|same", b.issuer))
    );
    // B's "same" is not A's "same": it never resolves to the admin, whatever e-mail it claims.
    let tb2 = b.token(
        "kb",
        1,
        &user_claims(&b, "aud-b", "same", "admin@example.com"),
    );
    assert_eq!(me(&app, &tb2).await.1["email"], "sales@example.com");

    // Rejections.
    let good = user_claims(&a, "aud-a", "same", "admin@example.com");
    let with = |k: &str, v: Value| {
        let mut c = good.clone();
        c[k] = v;
        c
    };
    let key0 = EncodingKey::from_rsa_pem(include_bytes!("common/keys/test_rsa_1.pem")).unwrap();
    let mut bad: Vec<(&str, String)> = vec![
        (
            "wrong audience",
            a.token("ka", 0, &with("aud", json!("aud-b"))),
        ),
        (
            "expired",
            a.token("ka", 0, &with("exp", json!(idp::now() - 3600))),
        ),
        (
            "not yet valid",
            a.token("ka", 0, &with("nbf", json!(idp::now() + 3600))),
        ),
        (
            "no exp",
            a.token("ka", 0, &{
                let mut c = good.clone();
                c.as_object_mut().unwrap().remove("exp");
                c
            }),
        ),
        (
            "unknown issuer",
            a.token("ka", 0, &with("iss", json!("http://127.0.0.1:1/x"))),
        ),
        ("wrong key", a.token("ka", 1, &good)),
        (
            "hs256",
            idp::sign(
                Algorithm::HS256,
                Some("ka"),
                &EncodingKey::from_secret(b"secret"),
                &good,
            ),
        ),
        (
            "alg none",
            format!(
                "{}.{}.",
                b64(&json!({"alg": "none", "typ": "JWT", "kid": "ka"})),
                b64(&good)
            ),
        ),
        ("no kid", idp::sign(Algorithm::RS256, None, &key0, &good)),
        ("garbage", "not.a.token".to_string()),
    ];
    // An algorithm the provider does not list is refused even with a valid signature.
    sqlx::query("UPDATE core.identity_providers SET algorithms = ARRAY['ES256'] WHERE issuer = $1")
        .bind(&a.issuer)
        .execute(&db)
        .await
        .unwrap();
    reload(&state).await;
    bad.push(("algorithm not listed", ta.clone()));
    for (what, t) in &bad {
        assert_eq!(me(&app, t).await.0, StatusCode::UNAUTHORIZED, "{what}");
    }
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn unknown_kid_refreshes_once_and_throttled_and_keys_expire(db: PgPool) {
    let a = MockIdp::start("a", "k1", 0).await;
    let (app, state) = oidc_app(db.clone(), settings(), None).await;
    insert_provider(&db, &a, "A", "aud-a").await;
    reload(&state).await;
    let claims = user_claims(&a, "aud-a", "s", "admin@example.com");

    assert_eq!(me(&app, &a.token("k1", 0, &claims)).await.0, StatusCode::OK);
    assert_eq!(a.jwks_hits(), 1);
    assert_eq!(me(&app, &a.token("k1", 0, &claims)).await.0, StatusCode::OK);
    assert_eq!(a.jwks_hits(), 1, "known keys are cached");

    // The provider rotates; an unknown kid inside the throttle window does not fetch.
    a.set_keys(vec![("k1", 0), ("k2", 1)]);
    let t2 = a.token("k2", 1, &claims);
    for _ in 0..3 {
        assert_eq!(me(&app, &t2).await.0, StatusCode::UNAUTHORIZED);
    }
    assert_eq!(a.jwks_hits(), 1);
    // After the window exactly one refresh happens, however many bad kids arrive.
    tokio::time::sleep(Duration::from_millis(350)).await;
    assert_eq!(me(&app, &t2).await.0, StatusCode::OK);
    assert_eq!(a.jwks_hits(), 2);
    for _ in 0..3 {
        assert_eq!(
            me(&app, &a.token("zz", 0, &claims)).await.0,
            StatusCode::UNAUTHORIZED
        );
    }
    assert_eq!(a.jwks_hits(), 2);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn cached_keys_expire_after_the_ttl(db: PgPool) {
    let a = MockIdp::start("a", "k1", 0).await;
    let s = IdpSettings {
        jwks_ttl: Duration::from_millis(250),
        refresh_throttle: Duration::from_millis(10),
        ..settings()
    };
    let (app, state) = oidc_app(db.clone(), s, None).await;
    insert_provider(&db, &a, "A", "aud-a").await;
    reload(&state).await;
    let t = a.token("k1", 0, &user_claims(&a, "aud-a", "s", "admin@example.com"));
    assert_eq!(me(&app, &t).await.0, StatusCode::OK);
    assert_eq!(me(&app, &t).await.0, StatusCode::OK);
    assert_eq!(a.jwks_hits(), 1);
    tokio::time::sleep(Duration::from_millis(300)).await;
    assert_eq!(me(&app, &t).await.0, StatusCode::OK);
    assert_eq!(a.jwks_hits(), 2);
    // A key the provider withdrew stops working once the cache expired.
    a.set_keys(vec![("other", 1)]);
    tokio::time::sleep(Duration::from_millis(300)).await;
    assert_eq!(me(&app, &t).await.0, StatusCode::UNAUTHORIZED);
}

fn provider(policy: EmailPolicy) -> ProviderConfig {
    let mut p = ProviderConfig::from_env("https://idp.example", "aud");
    p.source = ProviderSource::Database;
    p.email_policy = policy;
    p
}

fn claims(sub: &str, email_claim: &str, email: &str, extra: Option<(&str, Value)>) -> Claims {
    let mut raw = Map::new();
    raw.insert("sub".into(), json!(sub));
    raw.insert(email_claim.into(), json!(email));
    if let Some((k, v)) = extra {
        raw.insert(k.into(), v);
    }
    Claims::from_map(raw).unwrap()
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn email_policies(db: PgPool) {
    sqlx::raw_sql(tradocraft_api::DEV_SEED_SQL)
        .execute(&db)
        .await
        .unwrap();
    for e in [
        "a@corp.example",
        "b@corp.example",
        "c@elsewhere.example",
        "d@corp.example",
    ] {
        sqlx::query("INSERT INTO core.users (id, email, display_name) VALUES ($1, $2, $2)")
            .bind(uuid::Uuid::now_v7())
            .bind(e)
            .execute(&db)
            .await
            .unwrap();
    }
    let state = state_with(
        db.clone(),
        AuthConfig::Dev {
            default_email: None,
        },
    );
    let try_bind = |p: &ProviderConfig, c: Claims| {
        let state = state.clone();
        let p = p.clone();
        async move { bind_oidc_user(&state, &p, &c).await.is_ok() }
    };

    // require_verified_claim with a custom claim name (Entra: xms_edov), in every accepted form.
    let mut v = provider(EmailPolicy::RequireVerifiedClaim);
    v.verified_claim = "xms_edov".into();
    let em = "sales@example.com";
    assert!(
        !try_bind(
            &v,
            claims("s1", "email", em, Some(("xms_edov", json!(false))))
        )
        .await
    );
    assert!(!try_bind(&v, claims("s1", "email", em, None)).await);
    assert!(
        !try_bind(
            &v,
            claims("s1", "email", em, Some(("email_verified", json!(true))))
        )
        .await
    );
    assert!(
        !try_bind(
            &v,
            claims("s1", "email", em, Some(("xms_edov", json!("no"))))
        )
        .await
    );
    assert_eq!(subject_of(&db, em).await, None);
    assert!(
        try_bind(
            &v,
            claims(
                "s-bool",
                "email",
                "admin@example.com",
                Some(("xms_edov", json!(true)))
            )
        )
        .await
    );
    assert!(
        try_bind(
            &v,
            claims("s-str", "email", em, Some(("xms_edov", json!("1"))))
        )
        .await
    );
    assert!(
        try_bind(
            &v,
            claims(
                "s-num",
                "email",
                "viewer@example.com",
                Some(("xms_edov", json!(1)))
            )
        )
        .await
    );
    assert_eq!(
        subject_of(&db, em).await.as_deref(),
        Some("https://idp.example|s-str")
    );
    // Bound to another identity: refused.
    assert!(
        !try_bind(
            &v,
            claims("other", "email", em, Some(("xms_edov", json!(true))))
        )
        .await
    );

    // trust_provider_email: no verification claim; a custom e-mail claim; the domain list.
    let mut t = provider(EmailPolicy::TrustProviderEmail);
    t.email_claim = "preferred_username".into();
    assert!(
        try_bind(
            &t,
            claims("t1", "preferred_username", "A@Corp.example", None)
        )
        .await
    );
    t.allowed_email_domains = vec!["corp.example".into()];
    assert!(
        !try_bind(
            &t,
            claims("t2", "preferred_username", "c@elsewhere.example", None)
        )
        .await
    );
    assert!(!try_bind(&t, claims("t2", "email", "b@corp.example", None)).await);
    assert!(
        try_bind(
            &t,
            claims("t2", "preferred_username", "b@corp.example", None)
        )
        .await
    );

    // subject_only never binds by e-mail; a pre-set subject signs in.
    let so = provider(EmailPolicy::SubjectOnly);
    let mut c = claims(
        "so1",
        "email",
        "d@corp.example",
        Some(("email_verified", json!(true))),
    );
    assert!(!try_bind(&so, c.clone()).await);
    assert_eq!(subject_of(&db, "d@corp.example").await, None);
    sqlx::query("UPDATE core.users SET oidc_subject = 'https://idp.example|so1' WHERE email = 'd@corp.example'")
        .execute(&db)
        .await
        .unwrap();
    c.raw.remove("email");
    assert!(try_bind(&so, c).await);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn legacy_env_provider_keeps_unqualified_subjects_and_is_read_only(db: PgPool) {
    let env_idp = MockIdp::start("env", "ke", 2).await;
    let env = ProviderConfig::from_env(&format!("{}/", env_idp.issuer), "aud-env");
    let (app, _state) = oidc_app(db.clone(), settings(), Some(env)).await;
    let t = env_idp.token(
        "ke",
        2,
        &user_claims(&env_idp, "aud-env", "legacy-sub", "admin@example.com"),
    );
    assert_eq!(me(&app, &t).await.0, StatusCode::OK);
    assert_eq!(
        subject_of(&db, "admin@example.com").await.as_deref(),
        Some("legacy-sub")
    );

    // Listed read-only; it has no id, so it cannot be deleted.
    let (st, list) = bcall(&app, Some(&t), Method::GET, BASE, None).await;
    assert_eq!(st, StatusCode::OK);
    assert_eq!(list.as_array().unwrap().len(), 1);
    assert_eq!(list[0]["source"], "env");
    assert_eq!(list[0]["read_only"], true);
    assert!(list[0]["id"].is_null());
    let uri = format!("{BASE}/{}", uuid::Uuid::now_v7());
    assert_eq!(
        bcall(&app, Some(&t), Method::DELETE, &uri, None).await.0,
        StatusCode::NOT_FOUND
    );
    // The environment's issuer cannot be added as a second provider.
    let (st, _) = bcall(
        &app,
        Some(&t),
        Method::POST,
        BASE,
        Some(json!({"name": "dup", "issuer": env_idp.issuer, "audience": "x"})),
    )
    .await;
    assert_eq!(st, StatusCode::CONFLICT);

    // With the fallback present the last database provider can be disabled without confirmation;
    // a subject_only provider signs in people whose subject the administrator set.
    let b = MockIdp::start("b", "kb", 1).await;
    let (st, created) = bcall(
        &app,
        Some(&t),
        Method::POST,
        BASE,
        Some(json!({
            "name": "B", "issuer": b.issuer, "audience": "aud-b", "email_policy": "subject_only"
        })),
    )
    .await;
    assert_eq!(st, StatusCode::CREATED, "{created}");
    let sales: uuid::Uuid =
        sqlx::query_scalar("SELECT id FROM core.users WHERE email = 'sales@example.com'")
            .fetch_one(&db)
            .await
            .unwrap();
    let tb = b.token(
        "kb",
        1,
        &user_claims(&b, "aud-b", "s1", "sales@example.com"),
    );
    assert_eq!(
        me(&app, &tb).await.0,
        StatusCode::UNAUTHORIZED,
        "nothing bound by e-mail"
    );
    let uri = format!("/api/v1/admin/users/{sales}/oidc-subject");
    let (st, _) = bcall(
        &app,
        Some(&t),
        Method::PUT,
        &uri,
        Some(json!({"issuer": b.issuer, "subject": "s1"})),
    )
    .await;
    assert_eq!(st, StatusCode::NO_CONTENT);
    assert_eq!(me(&app, &tb).await.1["email"], "sales@example.com");
    let (st, _) = bcall(
        &app,
        Some(&t),
        Method::PUT,
        &uri,
        Some(json!({"issuer": "https://nope.example", "subject": "s1"})),
    )
    .await;
    assert_eq!(st, StatusCode::UNPROCESSABLE_ENTITY);
    let (st, _) = bcall(&app, Some(&t), Method::PUT, &uri, Some(json!({}))).await;
    assert_eq!(st, StatusCode::NO_CONTENT);
    assert_eq!(subject_of(&db, "sales@example.com").await, None);
    let n: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM audit.events WHERE entity = 'user' AND action LIKE 'oidc_subject_%'",
    )
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(n, 2);

    let id = created["id"].as_str().unwrap();
    let mut body = json!({"name": "B", "issuer": b.issuer, "audience": "aud-b", "enabled": false});
    let (st, _) = bcall(
        &app,
        Some(&t),
        Method::PUT,
        &format!("{BASE}/{id}"),
        Some(body.clone()),
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    body["enabled"] = json!(true);
    let (st, _) = bcall(
        &app,
        Some(&t),
        Method::PUT,
        &format!("{BASE}/{id}"),
        Some(body),
    )
    .await;
    assert_eq!(st, StatusCode::OK);
    let (st, _) = bcall(
        &app,
        Some(&t),
        Method::DELETE,
        &format!("{BASE}/{id}"),
        None,
    )
    .await;
    assert_eq!(st, StatusCode::NO_CONTENT);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn only_the_first_companys_admin_manages_providers_and_input_is_validated(db: PgPool) {
    let app = common::setup(db.clone()).await;
    // A later company with its own administrator.
    let (co, boss) = (uuid::Uuid::now_v7(), uuid::Uuid::now_v7());
    sqlx::query("INSERT INTO core.companies (id, name) VALUES ($1, 'Second BV')")
        .bind(co)
        .execute(&db)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO core.users (id, email, display_name) VALUES ($1, 'boss2@example.com', 'Boss')",
    )
    .bind(boss)
    .execute(&db)
    .await
    .unwrap();
    sqlx::query("INSERT INTO core.user_companies (user_id, company_id, roles, is_default) VALUES ($1, $2, '{admin}', true)")
        .bind(boss).bind(co).execute(&db).await.unwrap();

    for u in [
        "sales@example.com",
        "viewer@example.com",
        "boss2@example.com",
    ] {
        let (st, _) = call(&app, u, Method::GET, BASE, None).await;
        assert_eq!(st, StatusCode::FORBIDDEN, "{u}");
        let (st, _) = call(
            &app,
            u,
            Method::POST,
            BASE,
            Some(json!({"name": "x", "issuer": "https://x.example", "audience": "a"})),
        )
        .await;
        assert_eq!(st, StatusCode::FORBIDDEN, "{u}");
    }
    let (st, list) = call(&app, "admin@example.com", Method::GET, BASE, None).await;
    assert_eq!(st, StatusCode::OK);
    assert_eq!(list, json!([]));
    // Public list: empty in dev mode, no sign-in needed.
    let (st, p) =
        common::call_portal(&app, None, Method::GET, "/api/v1/auth/providers", None).await;
    assert_eq!((st, p), (StatusCode::OK, json!([])));

    let base = json!({"name": "X", "issuer": "https://login.example.com", "audience": "a"});
    let with = |k: &str, v: Value| {
        let mut b = base.clone();
        b[k] = v;
        b
    };
    for (what, body) in [
        (
            "http issuer",
            with("issuer", json!("http://login.example.com")),
        ),
        ("loopback", with("issuer", json!("https://127.0.0.1/realm"))),
        (
            "metadata address",
            with("issuer", json!("https://169.254.169.254")),
        ),
        ("private", with("issuer", json!("https://10.0.0.5"))),
        (
            "credentials",
            with("issuer", json!("https://u:p@login.example.com")),
        ),
        ("empty audience", with("audience", json!("  "))),
        ("empty name", with("name", json!(""))),
        ("HS256", with("algorithms", json!(["HS256"]))),
        ("none", with("algorithms", json!(["none"]))),
        ("policy", with("email_policy", json!("always"))),
        ("domain", with("allowed_email_domains", json!(["a b"]))),
    ] {
        let (st, res) = call(&app, "admin@example.com", Method::POST, BASE, Some(body)).await;
        assert_eq!(st, StatusCode::UNPROCESSABLE_ENTITY, "{what}: {res}");
    }
    let n: i64 = sqlx::query_scalar("SELECT count(*) FROM core.identity_providers")
        .fetch_one(&db)
        .await
        .unwrap();
    assert_eq!(n, 0);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn admin_api_hot_reload_test_endpoint_and_lockout_guards(db: PgPool) {
    let a = MockIdp::start("a", "ka", 0).await;
    let b = MockIdp::start("b", "kb", 1).await;
    let (app, state) = oidc_app(db.clone(), settings(), None).await;
    let a_id = insert_provider(&db, &a, "A", "aud-a").await;
    reload(&state).await;
    let admin = a.token(
        "ka",
        0,
        &user_claims(&a, "aud-a", "root", "admin@example.com"),
    );

    // Public list: only the four fields, no sign-in.
    sqlx::query("UPDATE core.identity_providers SET client_id = 'cid-a'")
        .execute(&db)
        .await
        .unwrap();
    reload(&state).await;
    let (st, p) = bcall(&app, None, Method::GET, "/api/v1/auth/providers", None).await;
    assert_eq!(st, StatusCode::OK);
    let mut keys: Vec<&String> = p[0].as_object().unwrap().keys().collect();
    keys.sort();
    assert_eq!(keys, ["client_id", "issuer", "name", "scopes", "source"]);
    assert_eq!(p[0]["source"], "database");
    assert_eq!(p[0]["client_id"], "cid-a");

    // A token for a provider that does not exist yet is refused; create it through the API.
    let tb = b.token(
        "kb",
        1,
        &user_claims(&b, "aud-b", "bee", "sales@example.com"),
    );
    assert_eq!(me(&app, &tb).await.0, StatusCode::UNAUTHORIZED);
    let draft = json!({"name": "B", "issuer": format!("{}/", b.issuer), "audience": "aud-b",
                       "client_id": "cid-b", "email_policy": "trust_provider_email"});
    b.set_discovery_issuer("https://somewhere.else");
    let (st, res) = bcall(&app, Some(&admin), Method::POST, BASE, Some(draft.clone())).await;
    assert_eq!(
        st,
        StatusCode::UNPROCESSABLE_ENTITY,
        "mismatching discovery issuer: {res}"
    );
    b.set_discovery_issuer(&b.issuer);
    let (st, created) = bcall(&app, Some(&admin), Method::POST, BASE, Some(draft.clone())).await;
    assert_eq!(st, StatusCode::CREATED, "{created}");
    assert_eq!(created["issuer"], b.issuer, "stored normalised");
    let b_id = created["id"].as_str().unwrap().to_string();
    // Hot reload: no restart needed.
    assert_eq!(me(&app, &tb).await.0, StatusCode::OK);

    // The test endpoint binds and stores nothing.
    let tv = b.token(
        "kb",
        1,
        &user_claims(&b, "aud-b", "vee", "viewer@example.com"),
    );
    let (st, r) = bcall(
        &app,
        Some(&admin),
        Method::POST,
        &format!("{BASE}/test"),
        Some(json!({
        "config": draft, "sample_token": tv })),
    )
    .await;
    assert_eq!(st, StatusCode::OK, "{r}");
    assert_eq!(r["discovery_reachable"], true);
    assert_eq!(r["issuer_match"], true);
    assert_eq!(r["key_count"], 1);
    assert_eq!(r["key_algorithms"], json!(["RS256"]));
    assert!(r["claims_supported"]
        .as_array()
        .unwrap()
        .contains(&json!("email")));
    assert_eq!(r["token"]["valid"], true);
    assert_eq!(r["token"]["binding"]["outcome"], "would_bind");
    assert_eq!(r["token"]["binding"]["user_email"], "viewer@example.com");
    assert_eq!(r["token"]["email"], "viewer@example.com");
    assert_eq!(subject_of(&db, "viewer@example.com").await, None);
    // Test an existing provider by id with a wrong-audience token.
    let tw = b.token(
        "kb",
        1,
        &user_claims(&b, "wrong", "vee", "viewer@example.com"),
    );
    let (_, r) = bcall(
        &app,
        Some(&admin),
        Method::POST,
        &format!("{BASE}/test"),
        Some(json!({
        "id": b_id, "sample_token": tw })),
    )
    .await;
    assert_eq!(r["token"]["valid"], false);
    assert_eq!(r["token"]["signature_ok"], true);
    assert_eq!(r["token"]["audience_ok"], false);
    assert!(r["token"]["binding"].is_null());
    // An unreachable or mismatching provider is reported, not an error.
    b.set_discovery_issuer("https://somewhere.else");
    let (st, r) = bcall(
        &app,
        Some(&admin),
        Method::POST,
        &format!("{BASE}/test"),
        Some(json!({"id": b_id})),
    )
    .await;
    assert_eq!((st, &r["issuer_match"]), (StatusCode::OK, &json!(false)));
    b.set_discovery_issuer(&b.issuer);

    // Disabling B (not the last, not the caller's) takes effect at once; enabling too.
    let mut body = json!({"name": "B", "issuer": b.issuer, "audience": "aud-b", "enabled": false});
    let put = format!("{BASE}/{b_id}");
    assert_eq!(
        bcall(&app, Some(&admin), Method::PUT, &put, Some(body.clone()))
            .await
            .0,
        StatusCode::OK
    );
    assert_eq!(me(&app, &tb).await.0, StatusCode::UNAUTHORIZED);
    body["enabled"] = json!(true);
    assert_eq!(
        bcall(&app, Some(&admin), Method::PUT, &put, Some(body.clone()))
            .await
            .0,
        StatusCode::OK
    );
    assert_eq!(me(&app, &tb).await.0, StatusCode::OK);

    // Guards: A is the caller's own provider.
    let del_a = format!("{BASE}/{a_id}");
    let (st, r) = bcall(&app, Some(&admin), Method::DELETE, &del_a, None).await;
    assert_eq!(
        (st, &r["code"]),
        (StatusCode::CONFLICT, &json!("own_identity_provider"))
    );
    let mut off = json!({"name": "A", "issuer": a.issuer, "audience": "aud-a", "enabled": false});
    let (st, _) = bcall(&app, Some(&admin), Method::PUT, &del_a, Some(off.clone())).await;
    assert_eq!(st, StatusCode::CONFLICT);
    // Disabling B leaves A as the only one; disabling A too would be the last.
    body["enabled"] = json!(false);
    let (st, _) = bcall(&app, Some(&admin), Method::PUT, &put, Some(body.clone())).await;
    assert_eq!(st, StatusCode::OK);
    let (st, r) = bcall(&app, Some(&admin), Method::PUT, &del_a, Some(off.clone())).await;
    assert_eq!(
        (st, &r["code"]),
        (StatusCode::CONFLICT, &json!("last_identity_provider"))
    );
    // The last provider cannot be deleted by a caller of another provider either.
    off["confirm_lockout"] = json!(true);
    body["enabled"] = json!(true);
    assert_eq!(
        bcall(&app, Some(&admin), Method::PUT, &put, Some(body))
            .await
            .0,
        StatusCode::OK
    );
    // With confirmation the caller's own provider goes; the caller is locked out at once.
    let (st, _) = bcall(
        &app,
        Some(&admin),
        Method::DELETE,
        &format!("{del_a}?confirm_lockout=true"),
        None,
    )
    .await;
    assert_eq!(st, StatusCode::NO_CONTENT);
    assert_eq!(me(&app, &admin).await.0, StatusCode::UNAUTHORIZED);

    // Everything was audited.
    let actions: Vec<(String, String)> = sqlx::query_as(
        "SELECT action, entity FROM audit.events WHERE entity = 'identity_provider' ORDER BY id",
    )
    .fetch_all(&db)
    .await
    .unwrap();
    let names: Vec<&str> = actions.iter().map(|a| a.0.as_str()).collect();
    assert_eq!(
        names,
        ["created", "updated", "updated", "updated", "updated", "deleted"]
    );
}

async fn add_company_with_admin(db: &PgPool, name: &str, email: &str) -> (uuid::Uuid, uuid::Uuid) {
    let (co, boss) = (uuid::Uuid::now_v7(), uuid::Uuid::now_v7());
    sqlx::query("INSERT INTO core.companies (id, name) VALUES ($1, $2)")
        .bind(co)
        .bind(name)
        .execute(db)
        .await
        .unwrap();
    sqlx::query("INSERT INTO core.users (id, email, display_name) VALUES ($1, $2, 'Boss')")
        .bind(boss)
        .bind(email)
        .execute(db)
        .await
        .unwrap();
    sqlx::query("INSERT INTO core.user_companies (user_id, company_id, roles, is_default) VALUES ($1, $2, '{admin}', true)")
        .bind(boss).bind(co).execute(db).await.unwrap();
    (co, boss)
}

async fn primary_ids(db: &PgPool) -> Vec<uuid::Uuid> {
    sqlx::query_scalar("SELECT id FROM core.companies WHERE is_primary")
        .fetch_all(db)
        .await
        .unwrap()
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_migration_backfill_flags_the_oldest_company(db: PgPool) {
    // Re-run the backfill on data as an older installation would have it: two companies, none flagged.
    sqlx::query("DROP INDEX core.companies_one_primary")
        .execute(&db)
        .await
        .unwrap();
    let (old, new) = (uuid::Uuid::now_v7(), uuid::Uuid::now_v7());
    for (id, name, ts) in [(new, "Newer", "2026-02-01"), (old, "Older", "2026-01-01")] {
        sqlx::query(
            "INSERT INTO core.companies (id, name, created_at) VALUES ($1, $2, $3::timestamptz)",
        )
        .bind(id)
        .bind(name)
        .bind(ts)
        .execute(&db)
        .await
        .unwrap();
    }
    let sql = std::fs::read_to_string(
        std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../migrations/20270127000001_primary_company.sql"),
    )
    .unwrap();
    let backfill = sql.split("-- Existing installations").nth(1).unwrap();
    let update = &backfill[backfill.find("UPDATE").unwrap()..];
    sqlx::raw_sql(update).execute(&db).await.unwrap();
    assert_eq!(primary_ids(&db).await, vec![old]);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn only_an_admin_of_the_primary_company_uses_the_identity_api(db: PgPool) {
    let app = common::setup(db.clone()).await;
    add_company_with_admin(&db, "Second BV", "boss2@example.com").await;
    // The seed company is primary: its admin may, the other company's admin may not.
    let (st, _) = call(&app, "admin@example.com", Method::GET, BASE, None).await;
    assert_eq!(st, StatusCode::OK);
    let (st, body) = call(&app, "boss2@example.com", Method::GET, BASE, None).await;
    assert_eq!(st, StatusCode::FORBIDDEN);
    assert!(body.to_string().contains("primary company"), "{body}");
    // If no company is flagged the oldest one is used.
    sqlx::query("UPDATE core.companies SET is_primary = false")
        .execute(&db)
        .await
        .unwrap();
    let (st, _) = call(&app, "admin@example.com", Method::GET, BASE, None).await;
    assert_eq!(st, StatusCode::OK);
    let (st, _) = call(&app, "boss2@example.com", Method::GET, BASE, None).await;
    assert_eq!(st, StatusCode::FORBIDDEN);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn make_primary_swaps_the_flag_and_is_guarded(db: PgPool) {
    let app = common::setup(db.clone()).await;
    let seed: uuid::Uuid = "00000000-0000-7000-8000-000000000001".parse().unwrap();
    let (second, _) = add_company_with_admin(&db, "Second BV", "boss2@example.com").await;
    let url = |id: uuid::Uuid| format!("/api/v1/admin/companies/{id}/make-primary");
    let (_, me) = call(&app, "admin@example.com", Method::GET, "/api/v1/me", None).await;
    assert_eq!(me["company"]["is_primary"], true);

    // Not an administrator of the primary company, or not an administrator at all.
    for u in ["boss2@example.com", "sales@example.com"] {
        let (st, _) = call(&app, u, Method::POST, &url(second), None).await;
        assert_eq!(st, StatusCode::FORBIDDEN, "{u}");
    }
    assert_eq!(primary_ids(&db).await, vec![seed]);
    // Unknown target is 404; the current primary company is 409.
    let (st, _) = call(
        &app,
        "admin@example.com",
        Method::POST,
        &url(uuid::Uuid::now_v7()),
        None,
    )
    .await;
    assert_eq!(st, StatusCode::NOT_FOUND);
    let (st, _) = call(&app, "admin@example.com", Method::POST, &url(seed), None).await;
    assert_eq!(st, StatusCode::CONFLICT);

    let (st, res) = call(&app, "admin@example.com", Method::POST, &url(second), None).await;
    assert_eq!(st, StatusCode::OK, "{res}");
    assert_eq!(res["name"], "Second BV");
    assert_eq!(primary_ids(&db).await, vec![second]);
    let audited: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM audit.events WHERE entity = 'company' AND action = 'made_primary' AND entity_id = $1",
    )
    .bind(second)
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(audited, 1);

    // The roles swapped: the former admin is refused, the new primary admin works.
    let (st, _) = call(&app, "admin@example.com", Method::GET, BASE, None).await;
    assert_eq!(st, StatusCode::FORBIDDEN);
    let (st, _) = call(&app, "boss2@example.com", Method::GET, BASE, None).await;
    assert_eq!(st, StatusCode::OK);
    let (st, _) = call(&app, "admin@example.com", Method::POST, &url(seed), None).await;
    assert_eq!(st, StatusCode::FORBIDDEN);

    // The database refuses a second primary company.
    let err = sqlx::query("UPDATE core.companies SET is_primary = true WHERE id = $1")
        .bind(seed)
        .execute(&db)
        .await
        .unwrap_err();
    assert!(err.to_string().contains("companies_one_primary"), "{err}");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_public_list_shows_the_env_provider_with_client_settings(db: PgPool) {
    let env = ProviderConfig::from_env("https://env.example/", "aud-env")
        .with_client(Some(" env-client "), Some("openid email offline_access"));
    let (app, _state) = oidc_app(db.clone(), settings(), Some(env)).await;
    let (st, p) = bcall(&app, None, Method::GET, "/api/v1/auth/providers", None).await;
    assert_eq!(st, StatusCode::OK);
    assert_eq!(p.as_array().unwrap().len(), 1);
    assert_eq!(p[0]["source"], "env");
    assert_eq!(p[0]["client_id"], "env-client");
    assert_eq!(p[0]["scopes"], "openid email offline_access");
    assert_eq!(p[0]["issuer"], "https://env.example");

    // Blank settings keep the defaults.
    let blank =
        ProviderConfig::from_env("https://env.example", "a").with_client(Some(" "), Some(""));
    assert_eq!(blank.client_id, None);
    assert_eq!(blank.scopes, "openid profile email");
}
