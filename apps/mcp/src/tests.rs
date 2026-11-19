#[path = "../../api/tests/common/idp.rs"]
mod idp;

use axum::{
    body::{to_bytes, Body},
    http::{header, Request, StatusCode},
};
use jsonwebtoken::{Algorithm, EncodingKey, Header};
use serde_json::Value;
use sqlx::PgPool;
use tower::ServiceExt;

use super::*;

const RESOURCE: &str = "https://mcp.example.com/mcp";
const COMPANY: &str = "00000000-0000-7000-8000-000000000001";
const OTHER_COMPANY: &str = "00000000-0000-7000-8000-000000000002";
const SALES: &str = "00000000-0000-7000-8000-000000000102";
const ORDER: &str = "00000000-0000-7000-8000-000000000701";
const OTHER_ORDER: &str = "00000000-0000-7000-8000-000000000702";

static MIGRATOR: sqlx::migrate::Migrator = sqlx::migrate!("../../migrations");

fn sign(claims: &Value, typ: &str) -> String {
    let mut header = Header::new(Algorithm::RS256);
    header.kid = Some("test".into());
    header.typ = Some(typ.into());
    let key =
        EncodingKey::from_rsa_pem(include_bytes!("../../api/tests/common/keys/test_rsa_1.pem"))
            .unwrap();
    jsonwebtoken::encode(&header, claims, &key).unwrap()
}

async fn rpc(
    app: &Router,
    token: Option<&str>,
    method: &str,
    params: Value,
) -> axum::response::Response {
    let mut request = Request::post("/mcp")
        .header(header::HOST, "127.0.0.1")
        .header(header::CONTENT_TYPE, "application/json")
        .header(header::ACCEPT, "application/json, text/event-stream")
        .header("mcp-protocol-version", "2025-11-25")
        .header("x-company-id", OTHER_COMPANY);
    if let Some(token) = token {
        request = request.header(header::AUTHORIZATION, format!("Bearer {token}"));
    }
    let body = json!({"jsonrpc":"2.0","id":1,"method":method,"params":params});
    app.clone()
        .oneshot(request.body(Body::from(body.to_string())).unwrap())
        .await
        .unwrap()
}

async fn json_body(response: axum::response::Response) -> Value {
    let body = to_bytes(response.into_body(), 32 * 1024).await.unwrap();
    serde_json::from_slice(&body).unwrap_or_else(|_| panic!("{}", String::from_utf8_lossy(&body)))
}

#[sqlx::test(migrator = "MIGRATOR")]
async fn delegated_order_reads_recheck_audience_scope_company_and_permissions(db: PgPool) {
    sqlx::raw_sql(include_str!("../../../seed/dev_seed.sql"))
        .execute(&db)
        .await
        .unwrap();
    sqlx::query("INSERT INTO core.companies (id, name) VALUES ($1::uuid, 'Other company')")
        .bind(OTHER_COMPANY)
        .execute(&db)
        .await
        .unwrap();
    sqlx::query("INSERT INTO core.user_companies (user_id, company_id, roles) VALUES ($1::uuid, $2::uuid, '{sales}')")
        .bind(SALES).bind(OTHER_COMPANY).execute(&db).await.unwrap();
    for (company, order) in [(COMPANY, ORDER), (OTHER_COMPANY, OTHER_ORDER)] {
        sqlx::query(
            "WITH quotation AS (
                 INSERT INTO sales.quotations (id, company_id, number, customer_id, customer_name,
                     customer_street, customer_postal_code, customer_city, customer_country_code,
                     customer_language, price_zone_code, customer_discount_percent, currency,
                     quote_date, valid_until, price_date, created_by)
                 VALUES (gen_random_uuid(), $1::uuid, 'Q-1', '00000000-0000-7000-8000-000000000401',
                     'Alpha', '', '', '', 'BE', 'en', 'Z1', 0, 'EUR', CURRENT_DATE, CURRENT_DATE, CURRENT_DATE, $3::uuid)
                 RETURNING id, customer_id
             ), placed AS (
                 INSERT INTO sales.orders (id, company_id, number, quotation_id, customer_id, customer_name,
                     order_date, currency, subtotal, vat_total, total, salesperson_id, created_by)
                 SELECT $2::uuid, $1::uuid, 'O-1', id, customer_id, 'Alpha', CURRENT_DATE, 'EUR',
                     100, 21, 121, $3::uuid, $3::uuid FROM quotation
                 RETURNING id
             )
             INSERT INTO sales.order_revisions (id, order_id, revision, subtotal, vat_total, total, created_by)
             SELECT gen_random_uuid(), id, 1, 100, 21, 121, $3::uuid FROM placed",
        ).bind(company).bind(order).bind(SALES).execute(&db).await.unwrap();
    }

    let idp = idp::MockIdp::start("mcp", "test", 0).await;
    let issuer = idp.issuer.clone();
    sqlx::query("INSERT INTO core.mcp_order_read_grants VALUES ($1, $2, 'sales-user', 'ai-client', $3::uuid, $4::uuid)")
        .bind(&issuer).bind(RESOURCE).bind(SALES).bind(COMPANY).execute(&db).await.unwrap();

    let verifier = IdentityProviders::new(
        IdpSettings {
            allow_insecure_urls: true,
            ..IdpSettings::default()
        },
        Some(ProviderConfig::from_env(&issuer, RESOURCE)),
    );
    let url = Url::parse(RESOURCE).unwrap();
    let app = router(
        Arc::new(OAuth::new(
            db.clone(),
            verifier,
            issuer,
            RESOURCE.into(),
            url.join(METADATA).unwrap(),
        )),
        StreamableHttpServerConfig::default()
            .with_legacy_session_mode(false)
            .with_json_response(true),
    );
    let call = |order| json!({"name":"get_order", "arguments":{"order_id":order}});

    let response = rpc(&app, None, "tools/call", call(ORDER)).await;
    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
    assert_eq!(response.headers()[header::WWW_AUTHENTICATE],
        "Bearer resource_metadata=\"https://mcp.example.com/.well-known/oauth-protected-resource/mcp\"");

    let metadata = app
        .clone()
        .oneshot(Request::get(METADATA).body(Body::empty()).unwrap())
        .await
        .unwrap();
    assert_eq!(metadata.status(), StatusCode::OK);
    let metadata = json_body(metadata).await;
    assert_eq!(metadata["resource"], RESOURCE);
    assert_eq!(metadata["authorization_servers"][0], idp.issuer);

    let mut claims = idp.claims(RESOURCE, "sales-user");
    claims["client_id"] = json!("ai-client");
    claims["scope"] = json!(SCOPE);
    let token = sign(&claims, "at+jwt");
    let mut wrong_audience = claims.clone();
    wrong_audience["aud"] = json!("staff-api");
    let mut missing_scope = claims.clone();
    missing_scope["scope"] = json!("customers:read");
    let mut wrong_client = claims.clone();
    wrong_client["client_id"] = json!("another-client");
    for (token, status) in [
        (sign(&wrong_audience, "at+jwt"), StatusCode::UNAUTHORIZED),
        (sign(&claims, "JWT"), StatusCode::UNAUTHORIZED),
        (sign(&missing_scope, "at+jwt"), StatusCode::FORBIDDEN),
        (sign(&wrong_client, "at+jwt"), StatusCode::FORBIDDEN),
    ] {
        assert_eq!(
            rpc(&app, Some(&token), "tools/call", call(ORDER))
                .await
                .status(),
            status
        );
    }

    let initialized = json_body(
        rpc(
            &app,
            Some(&token),
            "initialize",
            json!({
                "protocolVersion": "2025-11-25",
                "capabilities": {},
                "clientInfo": {"name": "test-client", "version": "1.0"}
            }),
        )
        .await,
    )
    .await;
    assert_eq!(
        initialized["result"]["protocolVersion"], "2025-11-25",
        "{initialized}"
    );
    let listed = json_body(rpc(&app, Some(&token), "tools/list", json!({})).await).await;
    assert_eq!(
        listed["result"]["tools"][0]["name"], "get_order",
        "{listed}"
    );
    let result = json_body(rpc(&app, Some(&token), "tools/call", call(ORDER)).await).await;
    assert_eq!(
        result["result"]["structuredContent"]["id"], ORDER,
        "{result}"
    );

    let other = json_body(rpc(&app, Some(&token), "tools/call", call(OTHER_ORDER)).await).await;
    assert_eq!(other["result"]["isError"], true, "{other}");

    sqlx::query("UPDATE core.user_companies SET roles = '{}' WHERE user_id = $1::uuid AND company_id = $2::uuid")
        .bind(SALES).bind(COMPANY).execute(&db).await.unwrap();
    let denied = json_body(rpc(&app, Some(&token), "tools/call", call(ORDER)).await).await;
    assert_eq!(denied["result"]["isError"], true, "{denied}");

    sqlx::query("DELETE FROM core.mcp_order_read_grants")
        .execute(&db)
        .await
        .unwrap();
    assert_eq!(
        rpc(&app, Some(&token), "tools/call", call(ORDER))
            .await
            .status(),
        StatusCode::FORBIDDEN
    );
}
