mod common;

use axum::{
    body::Body,
    http::{Method, Request, StatusCode},
};
use http_body_util::BodyExt;
use serde_json::json;
use sqlx::PgPool;
use tower::ServiceExt;

use common::{call, setup};

const ADMIN: &str = "admin@example.com";
const SALES: &str = "sales@example.com";
const DOCUMENTS: &str = "/api/v1/kb/documents";

async fn pdf(
    app: &axum::Router,
    method: Method,
    path: &str,
    user: &str,
    body: &'static str,
) -> (StatusCode, Vec<u8>) {
    let request = Request::builder()
        .method(method)
        .uri(path)
        .header("x-dev-user", user)
        .header("content-type", "application/pdf")
        .body(Body::from(body))
        .unwrap();
    let response = app.clone().oneshot(request).await.unwrap();
    let status = response.status();
    (
        status,
        response
            .into_body()
            .collect()
            .await
            .unwrap()
            .to_bytes()
            .to_vec(),
    )
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn publish_language_variants_and_keep_old_revisions(db: PgPool) {
    let app = setup(db.clone()).await;
    let input = json!({"title":"Motor clearance", "kind":"technical_memo", "keywords":["service"]});
    let (status, _) = call(&app, SALES, Method::POST, DOCUMENTS, Some(input.clone())).await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, doc) = call(&app, ADMIN, Method::POST, DOCUMENTS, Some(input)).await;
    assert_eq!(status, StatusCode::CREATED, "{doc}");
    let path = format!("{DOCUMENTS}/{}", doc["id"].as_str().unwrap());
    let (status, _) = pdf(
        &app,
        Method::PUT,
        &format!("{path}/draft/en?filename=invalid.pdf"),
        ADMIN,
        "not a PDF",
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    for (lang, bytes) in [("nl", "%PDF-1.7 Dutch"), ("fr", "%PDF-1.7 French")] {
        let (status, _) = pdf(
            &app,
            Method::PUT,
            &format!("{path}/draft/{lang}?filename=memo-{lang}.pdf"),
            ADMIN,
            bytes,
        )
        .await;
        assert_eq!(status, StatusCode::NO_CONTENT);
    }
    let (status, _) = pdf(
        &app,
        Method::GET,
        &format!("{path}/revisions/1/fr"),
        SALES,
        "",
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    for revision in 1..=2 {
        if revision == 2 {
            let (status, _) = pdf(
                &app,
                Method::PUT,
                &format!("{path}/draft/fr?filename=memo-fr.pdf"),
                ADMIN,
                "%PDF-1.7 Revised French",
            )
            .await;
            assert_eq!(status, StatusCode::NO_CONTENT);
        }
        let (status, _) = call(&app, ADMIN, Method::POST, &format!("{path}/publish"), None).await;
        assert_eq!(status, StatusCode::NO_CONTENT);
    }
    let (status, results) = call(
        &app,
        SALES,
        Method::GET,
        &format!("{DOCUMENTS}?q=service"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(results[0]["id"], doc["id"]);
    let (status, detail) = call(&app, SALES, Method::GET, &path, None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(detail["pdfs"].as_array().unwrap().len(), 4);
    for (revision, lang, expected) in [
        (1, "fr", "%PDF-1.7 French"),
        (2, "fr", "%PDF-1.7 Revised French"),
        (2, "nl", "%PDF-1.7 Dutch"),
    ] {
        let (status, body) = pdf(
            &app,
            Method::GET,
            &format!("{path}/revisions/{revision}/{lang}"),
            SALES,
            "",
        )
        .await;
        assert_eq!(status, StatusCode::OK);
        assert_eq!(body, expected.as_bytes());
    }
    let refs: i64 = sqlx::query_scalar("SELECT count(DISTINCT file_id) FROM kb.document_pdfs")
        .fetch_one(&db)
        .await
        .unwrap();
    assert_eq!(refs, 3);

    let other = uuid::Uuid::now_v7();
    sqlx::query("INSERT INTO core.companies (id, name) VALUES ($1, 'Other company')")
        .bind(other)
        .execute(&db)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO core.user_companies (user_id, company_id, roles)
         SELECT id, $1, ARRAY['admin'] FROM core.users WHERE email = $2",
    )
    .bind(other)
    .bind(ADMIN)
    .execute(&db)
    .await
    .unwrap();
    for uri in [path.clone(), format!("{path}/revisions/1/fr")] {
        let request = Request::builder()
            .uri(uri)
            .header("x-dev-user", ADMIN)
            .header("x-company-id", other.to_string())
            .body(Body::empty())
            .unwrap();
        assert_eq!(
            app.clone().oneshot(request).await.unwrap().status(),
            StatusCode::NOT_FOUND
        );
    }
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn reply_keeps_the_selected_library_pdf_in_the_worker_mail(db: PgPool) {
    use base64::{engine::general_purpose::STANDARD, Engine};
    use tradocraft_helpdesk::mailer::{process_outbox, Mailer};

    const OLD: &str = "%PDF-1.7 French original";
    const NEW: &str = "%PDF-1.7 French replacement";
    let (app, blobs) = common::setup_with_blobs(db.clone()).await;
    let (status, doc) = call(
        &app,
        ADMIN,
        Method::POST,
        DOCUMENTS,
        Some(json!({"title":"French technical memo", "kind":"technical_memo"})),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{doc}");
    let id = doc["id"].as_str().unwrap();
    let path = format!("{DOCUMENTS}/{id}");
    let draft = format!("{path}/draft/fr?filename=memo-fr.pdf");
    let publish = format!("{path}/publish");

    assert_eq!(
        pdf(&app, Method::PUT, &draft, ADMIN, OLD).await.0,
        StatusCode::NO_CONTENT
    );
    let (status, inbound) = common::call_raw(
        &app, ADMIN, "/api/v1/helpdesk/inbound", "message/rfc822",
        b"From: Claire <claire@example.test>\r\nTo: support@example.test\r\nSubject: Memo requested\r\nMessage-ID: <memo-request@example.test>\r\nContent-Type: text/plain; charset=utf-8\r\n\r\nBonjour, merci pour la documentation.\r\n".to_vec(),
    ).await;
    assert_eq!(status, StatusCode::OK, "{inbound}");
    let ticket = inbound["ticket_id"].as_str().unwrap();
    let endpoint = format!("/api/v1/tickets/{ticket}/replies");
    let reply = json!({"body":"Voici la note technique.", "library_pdfs":[{"document_id":id,"revision":1,"language":"fr"}]});
    let (status, _) = call(&app, ADMIN, Method::POST, &endpoint, Some(reply.clone())).await;
    assert_eq!(status, StatusCode::NOT_FOUND, "a draft must stay private");
    assert_eq!(
        call(&app, ADMIN, Method::POST, &publish, None).await.0,
        StatusCode::NO_CONTENT
    );
    let (status, detail) = call(&app, ADMIN, Method::POST, &endpoint, Some(reply)).await;
    assert_eq!(status, StatusCode::CREATED, "{detail}");
    let attachment = &detail["articles"][1]["attachments"][0];
    assert_eq!(attachment["filename"], "memo-fr.pdf");
    let file = attachment["id"].as_str().unwrap();
    let metadata: (i32, String, bool) = sqlx::query_as(
        "SELECT a.document_revision, a.document_language, reply_file.storage_key = library_file.storage_key
         FROM helpdesk.ticket_attachments a
         JOIN kb.document_pdfs p ON (p.document_id, p.revision, p.language) =
                                    (a.document_id, a.document_revision, a.document_language)
         JOIN core.files reply_file ON reply_file.id = a.file_id
         JOIN core.files library_file ON library_file.id = p.file_id
         WHERE a.file_id = $1::uuid",
    ).bind(file).fetch_one(&db).await.unwrap();
    assert_eq!(metadata, (1, "fr".into(), true));

    assert_eq!(
        pdf(&app, Method::PUT, &draft, ADMIN, NEW).await.0,
        StatusCode::NO_CONTENT
    );
    assert_eq!(
        call(&app, ADMIN, Method::POST, &publish, None).await.0,
        StatusCode::NO_CONTENT
    );
    let dir = tempfile::tempdir().unwrap();
    assert_eq!(
        process_outbox(&db, &blobs, &Mailer::Files(dir.path().to_path_buf()), 10)
            .await
            .unwrap(),
        1
    );
    let mail_path = std::fs::read_dir(dir.path())
        .unwrap()
        .next()
        .unwrap()
        .unwrap()
        .path();
    let mail = std::fs::read_to_string(mail_path).unwrap();
    assert!(mail.contains("memo-fr.pdf"));
    assert!(
        mail.contains(OLD) || mail.contains(&STANDARD.encode(OLD)),
        "{mail}"
    );
    assert!(!mail.contains(NEW) && !mail.contains(&STANDARD.encode(NEW)));
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn mailing_preview_resolves_languages_and_flags_exclusions(db: PgPool) {
    const PREVIEW: &str = "/api/v1/customers/mail-merge";
    let app = setup(db.clone()).await;
    let (status, doc) = call(
        &app,
        ADMIN,
        Method::POST,
        DOCUMENTS,
        Some(json!({"title":"Preview memo", "kind":"technical_memo"})),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);
    let id = doc["id"].as_str().unwrap();
    let path = format!("{DOCUMENTS}/{id}");
    for lang in ["fr", "nl"] {
        assert_eq!(
            pdf(
                &app,
                Method::PUT,
                &format!("{path}/draft/{lang}?filename=memo-{lang}.pdf"),
                ADMIN,
                "%PDF-1.7 preview"
            )
            .await
            .0,
            StatusCode::NO_CONTENT
        );
    }
    let draft = json!({
        "document_id":id, "revision":1,
        "messages":{
            "fr":{"subject":"Notice pour {{customer.name}}","body":"Bonjour {{contact.name}}"},
            "nl":{"subject":"Nota","body":"Beste {{contact.name}}"}
        }
    });
    assert_eq!(
        call(&app, ADMIN, Method::PUT, PREVIEW, Some(draft.clone()))
            .await
            .0,
        StatusCode::NOT_FOUND
    );
    assert_eq!(
        call(&app, ADMIN, Method::POST, &format!("{path}/publish"), None)
            .await
            .0,
        StatusCode::NO_CONTENT
    );
    sqlx::raw_sql(
        "INSERT INTO crm.customers (id,code,name,email,language,active) VALUES
            ('00000000-0000-7000-8000-000000000a01','MERGE-1','Merge French',null,'nl',true),
            ('00000000-0000-7000-8000-000000000a02','MERGE-2','Merge Dutch',null,'nl',true),
            ('00000000-0000-7000-8000-000000000a03','MERGE-3','Merge Duplicate A','merge-duplicate@example.test','de',true),
            ('00000000-0000-7000-8000-000000000a04','MERGE-4','Merge Duplicate B',' merge-duplicate@EXAMPLE.TEST ','nl',true),
            ('00000000-0000-7000-8000-000000000a05','MERGE-5','Merge Missing',null,'nl',true),
            ('00000000-0000-7000-8000-000000000a06','MERGE-6','Merge Unlinked','unlinked@example.test','nl',true),
            ('00000000-0000-7000-8000-000000000a07','MERGE-7','Merge Inactive','inactive@example.test','nl',false);
         INSERT INTO crm.customer_terms (customer_id,company_id,price_zone_id)
         SELECT c.id,z.company_id,z.id FROM crm.customers c CROSS JOIN LATERAL
             (SELECT id,company_id FROM pricing.price_zones WHERE code='Z1' ORDER BY id LIMIT 1) z
         WHERE c.code LIKE 'MERGE-%' AND c.code <> 'MERGE-6';
         INSERT INTO crm.contacts (id,customer_id,first_name,last_name,language) VALUES
            ('00000000-0000-7000-8000-000000000b01','00000000-0000-7000-8000-000000000a01','Claire','Dupont','fr'),
            ('00000000-0000-7000-8000-000000000b02','00000000-0000-7000-8000-000000000a02','Jan','Janssens',null);
         INSERT INTO crm.contact_emails (id,contact_id,email,is_primary) VALUES
            (gen_random_uuid(),'00000000-0000-7000-8000-000000000b01','claire-merge@example.test',true),
            (gen_random_uuid(),'00000000-0000-7000-8000-000000000b02','jan-merge@example.test',true);",
    ).execute(&db).await.unwrap();
    let (status, preview) = call(&app, ADMIN, Method::PUT, PREVIEW, Some(draft.clone())).await;
    assert_eq!(status, StatusCode::OK, "{preview}");
    let rows = preview["audience"].as_array().unwrap();
    let find = |name: &str| rows.iter().find(|r| r["customer_name"] == name);
    let fr = find("Merge French").unwrap();
    assert_eq!(fr["language"], "fr");
    assert_eq!(fr["subject"], "Notice pour Merge French");
    assert_eq!(fr["body"], "Bonjour Claire Dupont");
    assert_eq!(fr["pdf"], "memo-fr.pdf");
    assert_eq!(fr["issues"], json!([]));
    let nl = find("Merge Dutch").unwrap();
    assert_eq!(nl["language"], "nl");
    assert_eq!(nl["email"], "jan-merge@example.test");
    assert_eq!(nl["pdf"], "memo-nl.pdf");
    assert_eq!(
        find("Merge Duplicate A").unwrap()["issues"],
        json!(["missing_translation", "missing_pdf", "duplicate_address"])
    );
    assert_eq!(
        find("Merge Duplicate B").unwrap()["issues"],
        json!(["duplicate_address"])
    );
    assert_eq!(
        find("Merge Missing").unwrap()["issues"],
        json!(["missing_address"])
    );
    assert!(find("Merge Unlinked").is_none());
    assert!(find("Merge Inactive").is_none());

    let (status, saved) = call(&app, ADMIN, Method::GET, PREVIEW, None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(saved, preview);
    let (status, other) = call(&app, SALES, Method::GET, PREVIEW, None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(other["draft"], json!(null));
    let queued: i64 = sqlx::query_scalar("SELECT count(*) FROM core.mail_outbox")
        .fetch_one(&db)
        .await
        .unwrap();
    assert_eq!(queued, 0);
    let approval = preview["approval_id"].as_str().unwrap();
    let endpoint = format!("{PREVIEW}/{approval}/confirm");
    assert_eq!(
        call(&app, SALES, Method::POST, &endpoint, None).await.0,
        StatusCode::FORBIDDEN
    );
    for (change, restore) in [
        (
            "UPDATE crm.customers SET active = false WHERE code = 'MERGE-1'",
            "UPDATE crm.customers SET active = true WHERE code = 'MERGE-1'",
        ),
        (
            "UPDATE crm.contacts SET active = false WHERE id = '00000000-0000-7000-8000-000000000b01'",
            "UPDATE crm.contacts SET active = true WHERE id = '00000000-0000-7000-8000-000000000b01'",
        ),
        (
            "UPDATE crm.contact_emails SET email = 'changed@example.test' WHERE email = 'claire-merge@example.test'",
            "UPDATE crm.contact_emails SET email = 'claire-merge@example.test' WHERE email = 'changed@example.test'",
        ),
    ] {
        sqlx::query(change).execute(&db).await.unwrap();
        assert_eq!(
            call(&app, ADMIN, Method::POST, &endpoint, None).await.0,
            StatusCode::CONFLICT,
        );
        let queued: i64 = sqlx::query_scalar("SELECT count(*) FROM core.mail_outbox")
            .fetch_one(&db)
            .await
            .unwrap();
        assert_eq!(queued, 0);
        sqlx::query(restore).execute(&db).await.unwrap();
    }
    let (a, b) = tokio::join!(
        call(&app, ADMIN, Method::POST, &endpoint, None),
        call(&app, ADMIN, Method::POST, &endpoint, None),
    );
    assert_eq!(a.0, StatusCode::NO_CONTENT, "{}", a.1);
    assert_eq!(b.0, StatusCode::NO_CONTENT, "{}", b.1);
    let ids = sqlx::query_scalar::<_, String>(
        "SELECT to_address FROM core.mail_outbox ORDER BY to_address",
    )
    .fetch_all(&db)
    .await
    .unwrap();
    assert_eq!(ids, ["claire-merge@example.test", "jan-merge@example.test"]);
    let (_, unchanged) = call(&app, ADMIN, Method::PUT, PREVIEW, Some(draft)).await;
    assert_eq!(unchanged["approval_id"], approval);
    sqlx::query("UPDATE core.mail_outbox SET delivery = 'failed',delivery_error = 'file unavailable' WHERE to_address = 'claire-merge@example.test'")
        .execute(&db).await.unwrap();
    let (status, history) = call(
        &app,
        ADMIN,
        Method::GET,
        &format!("{PREVIEW}/history"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let delivery = history
        .as_array()
        .unwrap()
        .iter()
        .find(|r| r["email"] == "claire-merge@example.test")
        .unwrap();
    assert_eq!(delivery["delivery"], "failed");
    assert_eq!(delivery["delivery_error"], "file unavailable");
    assert_eq!(delivery["revision"], 1);
}
