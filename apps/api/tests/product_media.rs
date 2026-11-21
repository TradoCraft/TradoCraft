//! Product pictures and videos: the default item, listing, documents and permissions.

mod common;

use axum::http::{Method, StatusCode};
use common::{call, jpeg, raw, setup, Who};
use serde_json::{json, Value};
use sqlx::PgPool;

const UNIT_100: &str = "00000000-0000-7000-8000-000000000301";
const HOSE_25: &str = "00000000-0000-7000-8000-000000000304";
const ALPHA: &str = "00000000-0000-7000-8000-000000000401";
const SALES: &str = "admin@example.com"; // may change products and quote
const VIEWER: &str = "viewer@example.com";

/// A valid 1x1 PNG (a document renderer has to be able to decode it).
const PNG: &[u8] = &[
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53,
    0xde, 0x00, 0x00, 0x00, 0x0c, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0xf8, 0xcf, 0xc0, 0x00,
    0x00, 0x03, 0x01, 0x01, 0x00, 0xc9, 0xfe, 0x92, 0xef, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4e,
    0x44, 0xae, 0x42, 0x60, 0x82,
];

fn mp4() -> Vec<u8> {
    let mut v = b"\0\0\0\x18ftypmp42\0\0\0\0mp42isom".to_vec();
    v.extend([0u8; 32]);
    v
}

async fn upload(
    app: &axum::Router,
    user: &str,
    product: &str,
    body: Vec<u8>,
    q: &str,
) -> (StatusCode, Value) {
    let (status, _, bytes) = raw(
        app,
        Who::Staff(user),
        Method::POST,
        &format!("/api/v1/products/{product}/media{q}"),
        Some(("application/octet-stream", body)),
    )
    .await;
    let v = serde_json::from_slice(&bytes).unwrap_or(Value::Null);
    (status, v)
}

async fn list(app: &axum::Router, product: &str) -> Vec<Value> {
    let (status, v) = call(
        app,
        SALES,
        Method::GET,
        &format!("/api/v1/products/{product}/media"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{v}");
    v.as_array().unwrap().clone()
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_first_upload_is_the_default_and_the_default_can_be_changed(db: PgPool) {
    let app = setup(db).await;
    assert!(list(&app, UNIT_100).await.is_empty());
    let (status, _, _) = raw(
        &app,
        Who::Staff(SALES),
        Method::GET,
        &format!("/api/v1/products/{UNIT_100}/media/default"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    let (s, first) = upload(
        &app,
        SALES,
        UNIT_100,
        PNG.to_vec(),
        "?filename=front.png&caption=Front",
    )
    .await;
    assert_eq!(s, StatusCode::CREATED, "{first}");
    assert_eq!(first["is_default"], true);
    assert_eq!(first["kind"], "image");
    assert_eq!(first["caption"], "Front");

    let (s, clip) = upload(&app, SALES, UNIT_100, mp4(), "?filename=demo.mp4").await;
    assert_eq!(s, StatusCode::CREATED, "{clip}");
    assert_eq!(clip["kind"], "video");
    assert_eq!(clip["content_type"], "video/mp4");
    assert_eq!(clip["is_default"], false);

    let (s, second) = upload(&app, SALES, UNIT_100, jpeg(7), "").await;
    assert_eq!(s, StatusCode::CREATED);
    assert_eq!(second["is_default"], false);

    // the default is served and shown on the product, in the list and on the detail
    let (s, headers, bytes) = raw(
        &app,
        Who::Staff(SALES),
        Method::GET,
        &format!("/api/v1/products/{UNIT_100}/media/default"),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::OK);
    assert_eq!(headers["content-type"], "image/png");
    assert_eq!(bytes, PNG);
    let (_, p) = call(
        &app,
        SALES,
        Method::GET,
        &format!("/api/v1/products/{UNIT_100}"),
        None,
    )
    .await;
    assert_eq!(p["default_media_id"], first["id"]);
    assert_eq!(p["default_media_kind"], "image");
    let (_, products) = call(&app, SALES, Method::GET, "/api/v1/products?limit=200", None).await;
    let items = products
        .as_array()
        .cloned()
        .unwrap_or_else(|| products["items"].as_array().unwrap().clone());
    let listed = items.iter().find(|p| p["id"] == UNIT_100).unwrap();
    assert_eq!(listed["default_media_id"], first["id"]);
    assert!(items.iter().find(|p| p["id"] == HOSE_25).unwrap()["default_media_id"].is_null());

    // choosing another default moves it; the default is listed first
    let (s, m) = call(
        &app,
        SALES,
        Method::PATCH,
        &format!(
            "/api/v1/products/{UNIT_100}/media/{}",
            second["id"].as_str().unwrap()
        ),
        Some(json!({ "is_default": true })),
    )
    .await;
    assert_eq!(s, StatusCode::OK, "{m}");
    assert_eq!(m["is_default"], true);
    let l = list(&app, UNIT_100).await;
    assert_eq!(l.len(), 3);
    assert_eq!(l[0]["id"], second["id"]);
    assert_eq!(l.iter().filter(|m| m["is_default"] == true).count(), 1);

    // the default cannot be unset, only replaced
    let (s, _) = call(
        &app,
        SALES,
        Method::PATCH,
        &format!(
            "/api/v1/products/{UNIT_100}/media/{}",
            second["id"].as_str().unwrap()
        ),
        Some(json!({ "is_default": false })),
    )
    .await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);

    // captions can be edited
    let (s, m) = call(
        &app,
        SALES,
        Method::PATCH,
        &format!(
            "/api/v1/products/{UNIT_100}/media/{}",
            clip["id"].as_str().unwrap()
        ),
        Some(json!({ "caption": " Demo " })),
    )
    .await;
    assert_eq!(s, StatusCode::OK);
    assert_eq!(m["caption"], "Demo");

    // deleting the default promotes the oldest remaining item
    let (s, _) = call(
        &app,
        SALES,
        Method::DELETE,
        &format!(
            "/api/v1/products/{UNIT_100}/media/{}",
            second["id"].as_str().unwrap()
        ),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::NO_CONTENT);
    let l = list(&app, UNIT_100).await;
    assert_eq!(l.len(), 2);
    assert_eq!(l[0]["id"], first["id"]);
    assert_eq!(l[0]["is_default"], true);
    // deleting the last ones leaves the product without a default
    for m in &l {
        let (s, _) = call(
            &app,
            SALES,
            Method::DELETE,
            &format!(
                "/api/v1/products/{UNIT_100}/media/{}",
                m["id"].as_str().unwrap()
            ),
            None,
        )
        .await;
        assert_eq!(s, StatusCode::NO_CONTENT);
    }
    assert!(list(&app, UNIT_100).await.is_empty());
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn uploads_are_checked_and_scoped_to_their_product(db: PgPool) {
    let app = setup(db).await;
    let (s, _) = upload(
        &app,
        SALES,
        UNIT_100,
        b"<svg onload=alert(1)></svg>".to_vec(),
        "",
    )
    .await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);
    let (s, _) = upload(&app, SALES, UNIT_100, b"%PDF-1.7 hello".to_vec(), "").await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);
    let (s, _) = upload(&app, SALES, UNIT_100, vec![], "").await;
    assert_eq!(s, StatusCode::UNPROCESSABLE_ENTITY);

    // a retried upload is the same item; the same id on another product is refused
    let id = "00000000-0000-7000-8000-0000000000e1";
    let (s, a) = upload(
        &app,
        SALES,
        UNIT_100,
        PNG.to_vec(),
        &format!("?client_id={id}"),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED);
    let (s, b) = upload(
        &app,
        SALES,
        UNIT_100,
        PNG.to_vec(),
        &format!("?client_id={id}"),
    )
    .await;
    assert_eq!(s, StatusCode::CREATED);
    assert_eq!(a["id"], b["id"]);
    assert_eq!(list(&app, UNIT_100).await.len(), 1);
    let (s, _) = upload(
        &app,
        SALES,
        HOSE_25,
        PNG.to_vec(),
        &format!("?client_id={id}"),
    )
    .await;
    assert_eq!(s, StatusCode::CONFLICT);
    // the file is not reachable through another product
    let (s, _, _) = raw(
        &app,
        Who::Staff(SALES),
        Method::GET,
        &format!("/api/v1/products/{HOSE_25}/media/{id}"),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::NOT_FOUND);
    let (s, _) = call(
        &app,
        SALES,
        Method::DELETE,
        &format!("/api/v1/products/{HOSE_25}/media/{id}"),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::NOT_FOUND);
    let (s, _, _) = raw(
        &app,
        Who::Staff(SALES),
        Method::POST,
        "/api/v1/products/00000000-0000-7000-8000-0000000000ff/media",
        Some(("application/octet-stream", PNG.to_vec())),
    )
    .await;
    assert_eq!(s, StatusCode::NOT_FOUND);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn reading_needs_read_and_changing_needs_write(db: PgPool) {
    let app = setup(db).await;
    let (s, m) = upload(&app, SALES, UNIT_100, PNG.to_vec(), "").await;
    assert_eq!(s, StatusCode::CREATED);
    let uri = format!("/api/v1/products/{UNIT_100}/media");
    let (s, _, _) = raw(
        &app,
        Who::Staff("nobody@example.com"),
        Method::GET,
        &uri,
        None,
    )
    .await;
    assert_eq!(s, StatusCode::UNAUTHORIZED);
    let (s, _) = upload(&app, VIEWER, UNIT_100, PNG.to_vec(), "").await;
    assert_eq!(s, StatusCode::FORBIDDEN);
    let (s, _) = call(
        &app,
        VIEWER,
        Method::DELETE,
        &format!("{uri}/{}", m["id"].as_str().unwrap()),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::FORBIDDEN);
    let (s, _) = call(&app, VIEWER, Method::GET, &uri, None).await;
    assert_eq!(s, StatusCode::OK);
}

/// Whether the PDF contains an image object.
fn has_image(pdf: &[u8]) -> bool {
    pdf.windows(6).any(|w| w == b"/Image")
}

async fn quotation_pdf(app: &axum::Router) -> Vec<u8> {
    let (s, q) = call(app, SALES, Method::POST, "/api/v1/quotations", Some(json!({
        "customer_id": ALPHA, "quote_date": "2026-11-05", "vat_regime_override": "domestic",
        "lines": [{ "product_id": UNIT_100, "quantity": "2" }, { "product_id": HOSE_25, "quantity": "1" }]
    }))).await;
    assert_eq!(s, StatusCode::CREATED, "{q}");
    let (s, _, pdf) = raw(
        app,
        Who::Staff(SALES),
        Method::GET,
        &format!("/api/v1/quotations/{}/pdf", q["id"].as_str().unwrap()),
        None,
    )
    .await;
    assert_eq!(s, StatusCode::OK);
    assert!(pdf.starts_with(b"%PDF"));
    pdf
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_default_picture_is_printed_on_the_quotation(db: PgPool) {
    if std::process::Command::new(std::env::var("TYPST_BIN").unwrap_or_else(|_| "typst".into()))
        .arg("--version")
        .output()
        .is_err()
    {
        eprintln!("typst not installed; skipping PDF test");
        return;
    }
    let app = setup(db).await;
    assert!(!has_image(&quotation_pdf(&app).await));
    // a video as the default prints nothing
    let (s, _) = upload(&app, SALES, UNIT_100, mp4(), "").await;
    assert_eq!(s, StatusCode::CREATED);
    assert!(!has_image(&quotation_pdf(&app).await));
    // a picture as the default is embedded
    let (s, png) = upload(&app, SALES, UNIT_100, PNG.to_vec(), "").await;
    assert_eq!(s, StatusCode::CREATED);
    let (s, _) = call(
        &app,
        SALES,
        Method::PATCH,
        &format!(
            "/api/v1/products/{UNIT_100}/media/{}",
            png["id"].as_str().unwrap()
        ),
        Some(json!({ "is_default": true })),
    )
    .await;
    assert_eq!(s, StatusCode::OK);
    assert!(has_image(&quotation_pdf(&app).await), "no image in the PDF");
}
