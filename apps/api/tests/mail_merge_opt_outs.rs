//! Marketing opt-outs for the customer mail merge (ADR 0099): the per-company register, the
//! unsubscribe link in every mailing and how both keep addresses out of the audience.
mod common;

use axum::{
    body::Body,
    http::{Method, Request, StatusCode},
};
use http_body_util::BodyExt;
use serde_json::{json, Value};
use sqlx::PgPool;
use tower::ServiceExt;

use common::{call, call_portal, setup};

const ADMIN: &str = "admin@example.com";
const MERGE: &str = "/api/v1/customers/mail-merge";
const OPT_OUTS: &str = "/api/v1/customers/mail-merge/opt-outs";
const ONE: &str = "opt-one@example.test";
const TWO: &str = "opt-two@example.test";
const SECOND_COMPANY: &str = "00000000-0000-7000-8000-0000000000c2";

/// A published memo with a Dutch and an English PDF, two customers of the company that can
/// receive it, and the draft that mails it.
async fn prepare(app: &axum::Router, db: &PgPool) -> Value {
    let (status, doc) = call(
        app,
        ADMIN,
        Method::POST,
        "/api/v1/kb/documents",
        Some(json!({"title":"Opt-out memo", "kind":"technical_memo"})),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{doc}");
    let id = doc["id"].as_str().unwrap();
    for lang in ["nl", "en"] {
        let request = Request::builder()
            .method(Method::PUT)
            .uri(format!(
                "/api/v1/kb/documents/{id}/draft/{lang}?filename=memo-{lang}.pdf"
            ))
            .header("x-dev-user", ADMIN)
            .header("content-type", "application/pdf")
            .body(Body::from("%PDF-1.7 opt-out"))
            .unwrap();
        let response = app.clone().oneshot(request).await.unwrap();
        assert_eq!(response.status(), StatusCode::NO_CONTENT);
    }
    let (status, _) = call(
        app,
        ADMIN,
        Method::POST,
        &format!("/api/v1/kb/documents/{id}/publish"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    sqlx::raw_sql(
        "INSERT INTO crm.customers (id,code,name,email,language,active) VALUES
            ('00000000-0000-7000-8000-000000000c01','OPT-1','Opt One','opt-one@example.test','nl',true),
            ('00000000-0000-7000-8000-000000000c02','OPT-2','Opt Two',' Opt-Two@Example.test ','en',true);
         INSERT INTO crm.customer_terms (customer_id,company_id,price_zone_id)
         SELECT c.id,z.company_id,z.id FROM crm.customers c CROSS JOIN LATERAL
             (SELECT id,company_id FROM pricing.price_zones WHERE code='Z1' ORDER BY id LIMIT 1) z
         WHERE c.code LIKE 'OPT-%';",
    )
    .execute(db)
    .await
    .unwrap();
    json!({
        "document_id": id, "revision": 1,
        "messages": {
            "nl": {"subject":"Nieuwe brochure","body":"Beste {{customer.name}}"},
            "en": {"subject":"New brochure","body":"Dear {{customer.name}}"}
        }
    })
}

fn row<'a>(preview: &'a Value, email: &str) -> &'a Value {
    preview["audience"]
        .as_array()
        .unwrap()
        .iter()
        .find(|r| r["email"] == email)
        .unwrap_or_else(|| panic!("{email} not in {preview}"))
}

async fn queued(db: &PgPool) -> Vec<(String, String)> {
    sqlx::query_as("SELECT to_address, body FROM core.mail_outbox ORDER BY to_address")
        .fetch_all(db)
        .await
        .unwrap()
}

/// The unsubscribe token in a queued mail body.
fn token_in(body: &str) -> String {
    let start = body
        .find("/unsubscribe#token=")
        .expect("an unsubscribe link")
        + "/unsubscribe#token=".len();
    body[start..]
        .chars()
        .take_while(|c| c.is_ascii_alphanumeric() || *c == '_')
        .collect()
}

async fn opt_out_emails(app: &axum::Router) -> Vec<String> {
    let (status, list) = call(app, ADMIN, Method::GET, OPT_OUTS, None).await;
    assert_eq!(status, StatusCode::OK, "{list}");
    list.as_array()
        .unwrap()
        .iter()
        .map(|r| r["email"].as_str().unwrap().to_string())
        .collect()
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn opted_out_addresses_are_left_out_and_a_late_opt_out_blocks_confirm(db: PgPool) {
    let app = setup(db.clone()).await;
    let draft = prepare(&app, &db).await;
    let (status, _) = call(
        &app,
        ADMIN,
        Method::POST,
        OPT_OUTS,
        Some(json!({"email":"  OPT-ONE@example.test "})),
    )
    .await;
    assert_eq!(status, StatusCode::NO_CONTENT);

    let (status, preview) = call(&app, ADMIN, Method::PUT, MERGE, Some(draft.clone())).await;
    assert_eq!(status, StatusCode::OK, "{preview}");
    assert_eq!(row(&preview, ONE)["issues"], json!(["opted_out"]));
    let two = row(&preview, TWO);
    assert_eq!(two["issues"], json!([]));
    // The preview tells the sender a footer with a per-recipient link is added.
    let footer = two["footer"].as_str().unwrap();
    assert!(
        footer.contains("Demo Manufacturing BV")
            && footer.contains("http://localhost:8081/unsubscribe#token="),
        "{footer}"
    );
    assert_eq!(two["body"], "Dear Opt Two");

    // An opt-out between review and confirmation changes the recipients: nothing is sent.
    let approval = preview["approval_id"].as_str().unwrap();
    let confirm = format!("{MERGE}/{approval}/confirm");
    let (status, _) = call(
        &app,
        ADMIN,
        Method::POST,
        OPT_OUTS,
        Some(json!({"email": TWO})),
    )
    .await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    let (status, body) = call(&app, ADMIN, Method::POST, &confirm, None).await;
    assert_eq!(status, StatusCode::CONFLICT, "{body}");
    assert!(queued(&db).await.is_empty());

    // Re-subscribed, the reviewed recipients are current again and the mailing goes out, still
    // without the opted-out address.
    let (status, _) = call(
        &app,
        ADMIN,
        Method::DELETE,
        &format!("{OPT_OUTS}/{TWO}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    let (status, body) = call(&app, ADMIN, Method::POST, &confirm, None).await;
    assert_eq!(status, StatusCode::NO_CONTENT, "{body}");
    let mails = queued(&db).await;
    assert!(mails.iter().any(|(to, _)| to == TWO));
    assert!(!mails.iter().any(|(to, _)| to == ONE));
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn confirm_needs_the_portal_address_for_the_unsubscribe_link(db: PgPool) {
    let app = setup(db.clone()).await;
    let draft = prepare(&app, &db).await;
    sqlx::query("UPDATE core.companies SET portal_url = '  ' WHERE id = '00000000-0000-7000-8000-000000000001'")
        .execute(&db)
        .await
        .unwrap();
    let (status, preview) = call(&app, ADMIN, Method::PUT, MERGE, Some(draft)).await;
    assert_eq!(status, StatusCode::OK, "{preview}");
    let approval = preview["approval_id"].as_str().unwrap();
    let (status, body) = call(
        &app,
        ADMIN,
        Method::POST,
        &format!("{MERGE}/{approval}/confirm"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{body}");
    assert!(
        body["message"].as_str().unwrap().contains("portal address"),
        "{body}"
    );
    assert!(queued(&db).await.is_empty());
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn every_mail_has_its_own_unsubscribe_link_that_opts_the_address_out(db: PgPool) {
    let app = setup(db.clone()).await;
    let draft = prepare(&app, &db).await;
    let (_, preview) = call(&app, ADMIN, Method::PUT, MERGE, Some(draft.clone())).await;
    let approval = preview["approval_id"].as_str().unwrap();
    let (status, body) = call(
        &app,
        ADMIN,
        Method::POST,
        &format!("{MERGE}/{approval}/confirm"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NO_CONTENT, "{body}");

    let mails = queued(&db).await;
    let one = &mails.iter().find(|(to, _)| to == ONE).unwrap().1;
    let two = &mails.iter().find(|(to, _)| to == TWO).unwrap().1;
    // In the recipient's language, below the message.
    assert!(one.starts_with("Beste Opt One\n\n"), "{one}");
    assert!(one.contains("Schrijf u hier uit: http://localhost:8081/unsubscribe#token=tcu_"));
    assert!(two.contains("Unsubscribe here: http://localhost:8081/unsubscribe#token=tcu_"));
    let token = token_in(one);
    assert_eq!(token.len(), 4 + 64);
    assert_ne!(token, token_in(two));
    // Only the hash is stored.
    let (stored, leaked): (i64, i64) = sqlx::query_as(
        "SELECT count(unsubscribe_token_hash),
                count(*) FILTER (WHERE encode(unsubscribe_token_hash,'escape') LIKE '%tcu_%')
         FROM crm.mailing_deliveries",
    )
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!((stored, leaked), (mails.len() as i64, 0));
    assert_eq!(
        sqlx::query_scalar::<_, Vec<u8>>(
            "SELECT a.unsubscribe_token_hash FROM crm.mailing_deliveries a
             JOIN core.mail_outbox o ON o.id = a.outbox_id WHERE o.to_address = $1"
        )
        .bind(ONE)
        .fetch_one(&db)
        .await
        .unwrap(),
        tradocraft_kb::unsubscribe::hash_token(&token)
    );

    // The link page: reading changes nothing.
    let uri = format!("/api/v1/mailing-unsubscribe/{token}");
    for _ in 0..2 {
        let (status, info) = call_portal(&app, None, Method::GET, &uri, None).await;
        assert_eq!(status, StatusCode::OK, "{info}");
        assert_eq!(
            info,
            json!({
                "company_name": "Demo Manufacturing BV",
                "email": "o***@example.test",
                "language": "nl",
                "unsubscribed": false
            })
        );
    }
    assert!(opt_out_emails(&app).await.is_empty());
    let (status, info) = call_portal(
        &app,
        None,
        Method::GET,
        "/api/v1/mailing-unsubscribe/tcu_unknown",
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    assert!(!info.to_string().contains("example.test"), "{info}");
    assert_eq!(
        call_portal(
            &app,
            None,
            Method::POST,
            "/api/v1/mailing-unsubscribe/tcu_unknown",
            None
        )
        .await
        .0,
        StatusCode::NOT_FOUND
    );

    // Unsubscribing is idempotent and audited once.
    for _ in 0..2 {
        let (status, body) = call_portal(&app, None, Method::POST, &uri, None).await;
        assert_eq!(status, StatusCode::NO_CONTENT, "{body}");
    }
    let (_, info) = call_portal(&app, None, Method::GET, &uri, None).await;
    assert_eq!(info["unsubscribed"], true);
    let (status, list) = call(&app, ADMIN, Method::GET, OPT_OUTS, None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(list.as_array().unwrap().len(), 1);
    assert_eq!(list[0]["email"], ONE);
    assert_eq!(list[0]["source"], "unsubscribe_link");
    assert_eq!(list[0]["recorded_by"], Value::Null);
    let audited: Vec<(Option<uuid::Uuid>, Value)> = sqlx::query_as(
        "SELECT user_id, data FROM audit.events WHERE entity = 'mailing_opt_out' AND action = 'added'",
    )
    .fetch_all(&db)
    .await
    .unwrap();
    assert_eq!(audited.len(), 1);
    assert_eq!(audited[0].0, None);
    assert_eq!(audited[0].1["email"], ONE);
    assert_eq!(audited[0].1["source"], "unsubscribe_link");

    // The next mailing leaves the address out.
    let (_, next) = call(&app, ADMIN, Method::PUT, MERGE, Some(draft)).await;
    assert_eq!(row(&next, ONE)["issues"], json!(["opted_out"]));
    assert_eq!(row(&next, TWO)["issues"], json!([]));
}

/// A staff call in another company the admin also works for.
async fn call_in(
    app: &axum::Router,
    company: &str,
    method: Method,
    uri: &str,
    body: Option<Value>,
) -> (StatusCode, Value) {
    let mut req = Request::builder()
        .method(method)
        .uri(uri)
        .header("x-dev-user", ADMIN)
        .header("x-company-id", company);
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

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn staff_manage_the_register_per_company(db: PgPool) {
    let app = setup(db.clone()).await;
    // Permission: the same as the mail merge.
    assert_eq!(
        call(&app, "viewer@example.com", Method::GET, OPT_OUTS, None)
            .await
            .0,
        StatusCode::FORBIDDEN
    );
    for bad in ["", "no-at-sign", "a@b@c", "two words@example.test", "a@"] {
        let (status, body) = call(
            &app,
            ADMIN,
            Method::POST,
            OPT_OUTS,
            Some(json!({ "email": bad })),
        )
        .await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{bad}: {body}");
    }
    for email in [
        " First@Example.test",
        "second@example.test",
        "first@example.test",
    ] {
        let (status, body) = call(
            &app,
            ADMIN,
            Method::POST,
            OPT_OUTS,
            Some(json!({ "email": email })),
        )
        .await;
        assert_eq!(status, StatusCode::NO_CONTENT, "{email}: {body}");
    }
    let (_, list) = call(&app, ADMIN, Method::GET, OPT_OUTS, None).await;
    let list = list.as_array().unwrap();
    // Newest first, stored normalised, once.
    assert_eq!(
        list.iter().map(|r| r["email"].clone()).collect::<Vec<_>>(),
        [json!("second@example.test"), json!("first@example.test")]
    );
    assert_eq!(list[0]["source"], "staff");
    assert_eq!(list[0]["recorded_by_name"], "Admin User");

    // Another company of the same user has its own register.
    sqlx::raw_sql(
        "INSERT INTO core.companies (id, name) VALUES ('00000000-0000-7000-8000-0000000000c2', 'Second BV');
         INSERT INTO core.user_companies (user_id, company_id, roles, is_default)
         VALUES ('00000000-0000-7000-8000-000000000101', '00000000-0000-7000-8000-0000000000c2', '{admin}', false);",
    )
    .execute(&db)
    .await
    .unwrap();
    let (status, other) = call_in(&app, SECOND_COMPANY, Method::GET, OPT_OUTS, None).await;
    assert_eq!(status, StatusCode::OK, "{other}");
    assert_eq!(other, json!([]));
    assert_eq!(
        call_in(
            &app,
            SECOND_COMPANY,
            Method::DELETE,
            &format!("{OPT_OUTS}/first@example.test"),
            None
        )
        .await
        .0,
        StatusCode::NOT_FOUND
    );
    let (status, _) = call_in(
        &app,
        SECOND_COMPANY,
        Method::POST,
        OPT_OUTS,
        Some(json!({ "email": "third@example.test" })),
    )
    .await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    assert_eq!(
        opt_out_emails(&app).await,
        ["second@example.test", "first@example.test"]
    );

    // Re-subscribing takes the address off this company's register only; the path is
    // normalised like the input.
    assert_eq!(
        call(
            &app,
            ADMIN,
            Method::DELETE,
            &format!("{OPT_OUTS}/FIRST@example.test"),
            None
        )
        .await
        .0,
        StatusCode::NO_CONTENT
    );
    assert_eq!(
        call(
            &app,
            ADMIN,
            Method::DELETE,
            &format!("{OPT_OUTS}/first@example.test"),
            None
        )
        .await
        .0,
        StatusCode::NOT_FOUND
    );
    assert_eq!(opt_out_emails(&app).await, ["second@example.test"]);
    let actions: Vec<(String, Option<uuid::Uuid>)> = sqlx::query_as(
        "SELECT action, user_id FROM audit.events WHERE entity = 'mailing_opt_out'
         AND company_id = '00000000-0000-7000-8000-000000000001' ORDER BY id",
    )
    .fetch_all(&db)
    .await
    .unwrap();
    let admin = uuid::Uuid::parse_str("00000000-0000-7000-8000-000000000101").unwrap();
    assert_eq!(
        actions,
        [
            ("added".to_string(), Some(admin)),
            ("added".to_string(), Some(admin)),
            ("removed".to_string(), Some(admin)),
        ]
    );
}

const COMPANY: &str = "00000000-0000-7000-8000-000000000001";

/// An opt-out that commits while the mailing is being confirmed: confirmation waits for the
/// register lock, re-reads the register and refuses, so nothing is queued.
#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn an_opt_out_committed_during_confirmation_refuses_the_mailing(db: PgPool) {
    let app = setup(db.clone()).await;
    let draft = prepare(&app, &db).await;
    let (status, preview) = call(&app, ADMIN, Method::PUT, MERGE, Some(draft)).await;
    assert_eq!(status, StatusCode::OK, "{preview}");
    assert_eq!(row(&preview, TWO)["issues"], json!([]));
    let confirm = format!(
        "{MERGE}/{}/confirm",
        preview["approval_id"].as_str().unwrap()
    );

    // Another transaction is recording an opt-out and holds the register lock.
    let company: uuid::Uuid = COMPANY.parse().unwrap();
    let mut other = db.begin().await.unwrap();
    tradocraft_kb::unsubscribe::lock_register(&mut other, company)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO crm.mailing_opt_outs (company_id,email,source) VALUES ($1,$2,'unsubscribe_link')",
    )
    .bind(company)
    .bind(TWO)
    .execute(&mut *other)
    .await
    .unwrap();

    let confirming = {
        let app = app.clone();
        tokio::spawn(async move { call(&app, ADMIN, Method::POST, &confirm, None).await })
    };
    // Wait until the confirmation is blocked on the lock, then let the opt-out commit.
    for attempt in 0.. {
        let waiting: i64 = sqlx::query_scalar(
            "SELECT count(*) FROM pg_locks WHERE locktype = 'advisory' AND NOT granted",
        )
        .fetch_one(&db)
        .await
        .unwrap();
        if waiting > 0 {
            break;
        }
        assert!(
            attempt < 500,
            "confirmation never waited for the register lock"
        );
        tokio::time::sleep(std::time::Duration::from_millis(10)).await;
    }
    other.commit().await.unwrap();

    let (status, body) = confirming.await.unwrap();
    assert_eq!(status, StatusCode::CONFLICT, "{body}");
    assert!(queued(&db).await.is_empty());
}

/// An opt-out stops that address's mailings still waiting in the outbox; the rest of the mailing
/// and other system mail to the same address go out.
#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn an_opt_out_stops_queued_mailings_to_that_address(db: PgPool) {
    let app = setup(db.clone()).await;
    let draft = prepare(&app, &db).await;
    let (_, preview) = call(&app, ADMIN, Method::PUT, MERGE, Some(draft)).await;
    let approval = preview["approval_id"].as_str().unwrap();
    let (status, body) = call(
        &app,
        ADMIN,
        Method::POST,
        &format!("{MERGE}/{approval}/confirm"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NO_CONTENT, "{body}");
    sqlx::query(
        "INSERT INTO core.mail_outbox (id,company_id,to_address,subject,body)
         VALUES (gen_random_uuid(),$1,$2,'Your login link','x')",
    )
    .bind(COMPANY.parse::<uuid::Uuid>().unwrap())
    .bind(ONE)
    .execute(&db)
    .await
    .unwrap();

    let (status, _) = call(
        &app,
        ADMIN,
        Method::POST,
        OPT_OUTS,
        Some(json!({"email": ONE})),
    )
    .await;
    assert_eq!(status, StatusCode::NO_CONTENT);

    let rows: Vec<(String, String, String, Option<String>)> = sqlx::query_as(
        "SELECT to_address, subject, delivery, delivery_error FROM core.mail_outbox
         WHERE to_address LIKE 'opt-%' ORDER BY to_address, subject",
    )
    .fetch_all(&db)
    .await
    .unwrap();
    let cancelled = tradocraft_kb::unsubscribe::CANCELLED.to_string();
    assert_eq!(
        rows,
        vec![
            (
                ONE.to_string(),
                "Nieuwe brochure".to_string(),
                "failed".to_string(),
                Some(cancelled.clone())
            ),
            (
                ONE.to_string(),
                "Your login link".to_string(),
                "queued".to_string(),
                None
            ),
            (
                TWO.to_string(),
                "New brochure".to_string(),
                "queued".to_string(),
                None
            ),
        ]
    );
    // The mailing history keeps the delivery, with the reason.
    let (_, history) = call(&app, ADMIN, Method::GET, &format!("{MERGE}/history"), None).await;
    let one = history
        .as_array()
        .unwrap()
        .iter()
        .find(|r| r["email"] == ONE)
        .unwrap();
    assert_eq!(one["delivery"], "failed");
    assert_eq!(one["delivery_error"], cancelled);
    let audited: Value = sqlx::query_scalar(
        "SELECT data FROM audit.events WHERE entity = 'mailing_opt_out' AND action = 'added'",
    )
    .fetch_one(&db)
    .await
    .unwrap();
    assert_eq!(audited["cancelled_mails"], 1);
}
