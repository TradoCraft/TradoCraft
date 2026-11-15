//! Price lists (ADR 0069): CRUD with tree validation, permissions, audit and the PDF/Excel render.

mod common;

use axum::http::{Method, StatusCode};
use common::{call, raw, setup, Who};
use serde_json::{json, Value};
use sqlx::PgPool;

const ADMIN: &str = "admin@example.com";
const SALES: &str = "sales@example.com";
const URL: &str = "/api/v1/price-lists";
const Z1: &str = "00000000-0000-7000-8000-000000000201";
const Z2: &str = "00000000-0000-7000-8000-000000000202";
const Z3: &str = "00000000-0000-7000-8000-000000000203";
const UNIT_100: &str = "00000000-0000-7000-8000-000000000301";
const PUMP: &str = "00000000-0000-7000-8000-000000000303";
const HOSE: &str = "00000000-0000-7000-8000-000000000304";
const TRAVEL: &str = "00000000-0000-7000-8000-000000000306";

fn text(pdf: &[u8]) -> Option<String> {
    use std::io::Write;
    use std::process::{Command, Stdio};
    let mut child = Command::new("pdftotext")
        .args(["-layout", "-", "-"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .ok()?;
    child.stdin.take().unwrap().write_all(pdf).ok()?;
    let out = child.wait_with_output().ok()?;
    Some(String::from_utf8_lossy(&out.stdout).into_owned())
}

/// Number of raster images embedded in the PDF, or `None` when pdfimages is not installed.
fn image_count(pdf: &[u8]) -> Option<usize> {
    use std::process::Command;
    let path = std::env::temp_dir().join(format!("pl-{}.pdf", uuid::Uuid::now_v7()));
    std::fs::write(&path, pdf).ok()?;
    let out = Command::new("pdfimages").arg("-list").arg(&path).output();
    let _ = std::fs::remove_file(&path);
    let out = out.ok()?;
    out.status.success().then(|| {
        String::from_utf8_lossy(&out.stdout)
            .lines()
            .filter(|l| l.contains(" image "))
            .count()
    })
}

/// A valid 1x1 PNG.
const PNG: [u8; 69] = [
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53,
    0xde, 0x00, 0x00, 0x00, 0x0c, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0xf8, 0xcf, 0xc0, 0x00,
    0x00, 0x03, 0x01, 0x01, 0x00, 0xc9, 0xfe, 0x92, 0xef, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4e,
    0x44, 0xae, 0x42, 0x60, 0x82,
];
const LOGO_URL: &str = "/api/v1/admin/company/logo";
const BINARY: &str = "application/octet-stream";

async fn post(app: &axum::Router, user: &str, uri: &str, body: Value) -> (StatusCode, Value) {
    call(app, user, Method::POST, uri, Some(body)).await
}

async fn put_zones(app: &axum::Router, base: &str, body: Value) -> (StatusCode, Value) {
    call(
        app,
        ADMIN,
        Method::PUT,
        &format!("{base}/zones"),
        Some(body),
    )
    .await
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn build_a_list_and_render_it(db: PgPool) {
    let app = setup(db.clone()).await;
    let (status, list) = post(
        &app,
        ADMIN,
        URL,
        json!({ "code": "PL-2027", "name": "Prijslijst 2027", "valid_from": "2027-01-01",
                "settings": { "footer_text": "Alle prijzen excl. BTW" } }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{list}");
    assert_eq!(list["zones"], json!([]));
    assert_eq!(list["settings"]["show_unit"], true);
    let id = list["id"].as_str().unwrap().to_string();
    let base = format!("{URL}/{id}");
    let (status, list) = put_zones(
        &app,
        &base,
        json!([{ "price_zone_id": Z1, "languages": ["nl", "en"] }]),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{list}");
    assert_eq!(list["zones"][0]["price_zone_code"], "Z1");
    assert_eq!(list["zones"][0]["languages"], json!(["nl", "en"]));

    let (status, dup) = post(
        &app,
        ADMIN,
        URL,
        json!({ "code": "PL-2027", "name": "x", "valid_from": "2027-01-01" }),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT, "{dup}");

    // Groups: "Eerste" (first, page break) with a sub-group, then "Tweede".
    let (status, second) = post(
        &app,
        ADMIN,
        &format!("{base}/groups"),
        json!({ "sort_order": 2, "title": { "nl": "Tweede", "en": "Second" } }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{second}");
    let (_, first) = post(
        &app,
        ADMIN,
        &format!("{base}/groups"),
        json!({ "sort_order": 1, "title": { "nl": "Eerste", "en": "First" }, "page_break": true }),
    )
    .await;
    let first_id = first["id"].as_str().unwrap().to_string();
    let (status, sub) = post(
        &app,
        ADMIN,
        &format!("{base}/groups"),
        json!({ "parent_id": first_id, "title": { "nl": "Onder eerste" } }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{sub}");
    let sub_id = sub["id"].as_str().unwrap().to_string();
    let (_, empty) = post(
        &app,
        ADMIN,
        &format!("{base}/groups"),
        json!({ "sort_order": 3, "title": { "nl": "Lege groep" } }),
    )
    .await;

    // A group cannot move below its own descendant; a title is required.
    let (status, e) = call(
        &app,
        ADMIN,
        Method::PUT,
        &format!("{base}/groups/{first_id}"),
        Some(json!({ "parent_id": sub_id, "title": { "nl": "Eerste" } })),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{e}");
    let (status, _) = post(
        &app,
        ADMIN,
        &format!("{base}/groups"),
        json!({ "title": {} }),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    let item = |product: &str, group: &str, key: &str, extra: Value| {
        let mut v = json!({ "product_id": product, "group_id": group, "sort_key": key });
        v.as_object_mut()
            .unwrap()
            .extend(extra.as_object().unwrap().clone());
        v
    };
    let second_id = second["id"].as_str().unwrap();
    for body in [
        item(UNIT_100, &first_id, "2", json!({})),
        item(HOSE, &first_id, "10", json!({ "price_on_request": true })),
        item(PUMP, &sub_id, "1", json!({ "net": true })),
        item(
            TRAVEL,
            second_id,
            "",
            json!({ "description": { "nl": "Verplaatsing", "en": "Travel" } }),
        ),
    ] {
        let (status, i) = post(&app, ADMIN, &format!("{base}/items"), body).await;
        assert_eq!(status, StatusCode::CREATED, "{i}");
    }
    let (status, _) = post(
        &app,
        ADMIN,
        &format!("{base}/items"),
        item(PUMP, &sub_id, "1", json!({})),
    )
    .await;
    assert_eq!(
        status,
        StatusCode::CONFLICT,
        "a product appears once per list"
    );
    let (status, _) = post(
        &app,
        ADMIN,
        &format!("{base}/items"),
        item(
            UNIT_100,
            "00000000-0000-7000-8000-0000000000ff",
            "",
            json!({}),
        ),
    )
    .await;
    assert_eq!(
        status,
        StatusCode::UNPROCESSABLE_ENTITY,
        "group of another list"
    );

    let (_, items) = call(&app, SALES, Method::GET, &format!("{base}/items"), None).await;
    assert_eq!(items.as_array().unwrap().len(), 4);
    let (_, got) = call(&app, SALES, Method::GET, &base, None).await;
    assert_eq!(got["item_count"], 4);

    // Deleting a group that still holds items or sub-groups is refused; an empty one goes.
    let (status, _) = call(
        &app,
        ADMIN,
        Method::DELETE,
        &format!("{base}/groups/{first_id}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
    let empty_id = empty["id"].as_str().unwrap();
    let (status, _) = call(
        &app,
        ADMIN,
        Method::DELETE,
        &format!("{base}/groups/{empty_id}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NO_CONTENT);

    // Sales may read and render but not change.
    let (status, _) = post(
        &app,
        SALES,
        URL,
        json!({ "code": "S1", "name": "Sales", "valid_from": "2027-01-01" }),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, _) = call(&app, SALES, Method::DELETE, &base, None).await;
    assert_eq!(status, StatusCode::FORBIDDEN);

    let (status, headers, pdf) = raw(
        &app,
        Who::Staff(SALES),
        Method::POST,
        &format!("{base}/render?lang=nl&format=pdf"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert!(pdf.starts_with(b"%PDF"));
    assert!(headers["content-disposition"]
        .to_str()
        .unwrap()
        .contains("PL-2027-Z1-nl.pdf"));
    if let Some(t) = text(&pdf) {
        let at = |s: &str| t.find(s).unwrap_or_else(|| panic!("{s} missing in:\n{t}"));
        assert!(at("Eerste") < at("Onder eerste") && at("Onder eerste") < at("Tweede"));
        assert!(at("UNIT-100") < at("HOSE-25"), "sort key 2 before 10");
        assert!(t.contains("OP AANVRAAG"));
        assert!(t.contains("3.395,00"), "zone 1 price 4850 x 0.70:\n{t}");
        assert!(t.contains("Verplaatsing"));
        assert!(!t.contains("Lege groep"));
        assert!(t.contains("Alle prijzen excl. BTW"));
    }
    let (status, _, pdf) = raw(
        &app,
        Who::Staff(SALES),
        Method::POST,
        &format!("{base}/render?lang=en"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    if let Some(t) = text(&pdf) {
        assert!(
            t.contains("ON REQUEST") && t.contains("Second") && t.contains("Travel"),
            "{t}"
        );
    }
    let (status, _, xlsx) = raw(
        &app,
        Who::Staff(ADMIN),
        Method::POST,
        &format!("{base}/render?format=xlsx"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(&xlsx[..2], b"PK");
    let (status, _, _) = raw(
        &app,
        Who::Staff(ADMIN),
        Method::POST,
        &format!("{base}/render?lang=fr"),
        None,
    )
    .await;
    assert_eq!(
        status,
        StatusCode::UNPROCESSABLE_ENTITY,
        "fr is not a language of the list"
    );

    let audited: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM audit.events WHERE entity = 'price_list' AND entity_id = $1::uuid",
    )
    .bind(&id)
    .fetch_one(&db)
    .await
    .unwrap();
    assert!(audited >= 8, "{audited}");

    // Deleting the list takes its groups and items along.
    let (status, _) = call(&app, ADMIN, Method::DELETE, &base, None).await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    let left: i64 = sqlx::query_scalar("SELECT (SELECT count(*) FROM pricing.price_list_groups) + (SELECT count(*) FROM pricing.price_list_items)")
        .fetch_one(&db)
        .await
        .unwrap();
    assert_eq!(left, 0);
    let (status, _) = call(&app, ADMIN, Method::GET, &base, None).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn validation_of_lists(db: PgPool) {
    let app = setup(db).await;
    for body in [
        json!({ "code": " ", "name": "x", "valid_from": "2027-01-01" }),
        json!({ "code": "A", "name": "x", "valid_from": "2027-01-01", "settings": { "accent_color": "red" } }),
    ] {
        let (status, e) = post(&app, ADMIN, URL, body.clone()).await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{body} -> {e}");
    }
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn untitled_groups_print_items_without_title(db: PgPool) {
    let app = setup(db).await;
    let (_, list) = post(
        &app,
        ADMIN,
        URL,
        json!({ "code": "U1", "name": "Lijst", "valid_from": "2027-01-01" }),
    )
    .await;
    let base = format!("{URL}/{}", list["id"].as_str().unwrap());
    put_zones(
        &app,
        &base,
        json!([{ "price_zone_id": Z1, "languages": ["nl"] }]),
    )
    .await;
    let (_, first) = post(
        &app,
        ADMIN,
        &format!("{base}/groups"),
        json!({ "sort_order": 1, "title": { "nl": "Zichtbaar" } }),
    )
    .await;
    assert_eq!(first["show_title"], true, "titles print by default");
    assert_eq!(first["gap_mm"], "0.00");
    let (status, hidden) = post(
        &app,
        ADMIN,
        &format!("{base}/groups"),
        json!({ "sort_order": 2, "title": { "nl": "Verborgen titel" }, "show_title": false, "gap_mm": "8.5" }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{hidden}");
    assert_eq!(hidden["show_title"], false);
    assert_eq!(hidden["gap_mm"], "8.50");
    let (_, empty) = post(
        &app,
        ADMIN,
        &format!("{base}/groups"),
        json!({ "sort_order": 3, "title": { "nl": "Lege verborgen" }, "show_title": false }),
    )
    .await;
    assert!(empty["id"].is_string());

    for gap in ["-1", "50.01", "60", "1.234"] {
        let (status, e) = post(
            &app,
            ADMIN,
            &format!("{base}/groups"),
            json!({ "title": { "nl": "x" }, "show_title": false, "gap_mm": gap }),
        )
        .await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{gap}: {e}");
    }
    let hid = hidden["id"].as_str().unwrap();
    let (status, upd) = call(
        &app,
        ADMIN,
        Method::PUT,
        &format!("{base}/groups/{hid}"),
        Some(json!({ "sort_order": 2, "title": { "nl": "Verborgen titel" }, "show_title": false, "gap_mm": "50" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{upd}");
    assert_eq!(upd["gap_mm"], "50.00");

    for (product, group) in [(UNIT_100, first["id"].as_str().unwrap()), (PUMP, hid)] {
        let (status, i) = post(
            &app,
            ADMIN,
            &format!("{base}/items"),
            json!({ "product_id": product, "group_id": group }),
        )
        .await;
        assert_eq!(status, StatusCode::CREATED, "{i}");
    }
    let (_, groups) = call(&app, SALES, Method::GET, &format!("{base}/groups"), None).await;
    assert!(groups
        .as_array()
        .unwrap()
        .iter()
        .any(|g| g["show_title"] == false));

    let (status, _, pdf) = raw(
        &app,
        Who::Staff(SALES),
        Method::POST,
        &format!("{base}/render?lang=nl"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    if let Some(t) = text(&pdf) {
        assert!(t.contains("Zichtbaar"), "{t}");
        assert!(!t.contains("Verborgen titel"), "title must not print:\n{t}");
        assert!(!t.contains("Lege verborgen"));
        assert!(t.contains("UNIT-100"), "{t}");
        assert!(
            t.matches("€").count() >= 2,
            "both groups print their item:\n{t}"
        );
    }
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn company_logo_is_validated_and_printed_on_the_pdf(db: PgPool) {
    let app = setup(db.clone()).await;
    let who = |u| Who::Staff(u);

    // No logo yet.
    let (status, _, _) = raw(&app, who(ADMIN), Method::GET, LOGO_URL, None).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, _, _) = raw(&app, who(ADMIN), Method::DELETE, LOGO_URL, None).await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    // Only the administrator manages it.
    for method in [Method::PUT, Method::GET, Method::DELETE] {
        let (status, _, _) = raw(
            &app,
            who(SALES),
            method,
            LOGO_URL,
            Some((BINARY, PNG.to_vec())),
        )
        .await;
        assert_eq!(status, StatusCode::FORBIDDEN);
    }

    // Wrong types, active SVG and oversized files are refused; the declared type does not count.
    let too_big = {
        let mut v = PNG.to_vec();
        v.resize(512 * 1024 + 1, 0);
        v
    };
    for bad in [
        PNG[..PNG.len() - 12].to_vec(),
        PNG[..30].to_vec(),
        vec![0xFF, 0xD8, 0xFF, 0xE0, 1, 2],
        b"<svg xmlns='http://www.w3.org/2000/svg'><rect/>".to_vec(),
        b"GIF89a......".to_vec(),
        b"%PDF-1.7".to_vec(),
        b"<svg xmlns='http://www.w3.org/2000/svg'><script>alert(1)</script></svg>".to_vec(),
        b"<svg xmlns='http://www.w3.org/2000/svg'><foreignObject/></svg>".to_vec(),
        Vec::new(),
        too_big,
    ] {
        let (status, _, body) = raw(
            &app,
            who(ADMIN),
            Method::PUT,
            LOGO_URL,
            Some(("image/png", bad)),
        )
        .await;
        assert_eq!(
            status,
            StatusCode::UNPROCESSABLE_ENTITY,
            "{}",
            String::from_utf8_lossy(&body)
        );
    }

    // A price list to render.
    let (_, list) = post(
        &app,
        ADMIN,
        URL,
        json!({ "code": "L1", "name": "Lijst", "valid_from": "2027-01-01" }),
    )
    .await;
    let id = list["id"].as_str().unwrap().to_string();
    let base = format!("{URL}/{id}");
    put_zones(
        &app,
        &base,
        json!([{ "price_zone_id": Z1, "languages": ["nl"] }]),
    )
    .await;
    let (_, g) = post(
        &app,
        ADMIN,
        &format!("{base}/groups"),
        json!({ "title": { "nl": "Groep" } }),
    )
    .await;
    post(
        &app,
        ADMIN,
        &format!("{base}/items"),
        json!({ "product_id": UNIT_100, "group_id": g["id"] }),
    )
    .await;
    let render = |format: &'static str| {
        let app = app.clone();
        let uri = format!("{base}/render?format={format}");
        async move { raw(&app, Who::Staff(SALES), Method::POST, &uri, None).await }
    };
    let (status, _, pdf) = render("pdf").await;
    assert_eq!(status, StatusCode::OK);
    if let Some(n) = image_count(&pdf) {
        assert_eq!(n, 0, "no logo uploaded");
    }

    // Upload, read back, replace.
    let (status, _, body) = raw(
        &app,
        who(ADMIN),
        Method::PUT,
        LOGO_URL,
        Some(("application/json", PNG.to_vec())),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{}", String::from_utf8_lossy(&body));
    let info: Value = serde_json::from_slice(&body).unwrap();
    assert_eq!(info["content_type"], "image/png");
    assert_eq!(info["size_bytes"], PNG.len());
    let (status, headers, got) = raw(&app, who(ADMIN), Method::GET, LOGO_URL, None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(headers["content-type"], "image/png");
    assert_eq!(headers["x-content-type-options"], "nosniff");
    assert_eq!(got, PNG);

    let (status, _, pdf) = render("pdf").await;
    assert_eq!(status, StatusCode::OK);
    assert!(pdf.starts_with(b"%PDF"));
    if let Some(n) = image_count(&pdf) {
        assert_eq!(n, 1, "the logo is in the header");
    }
    let (status, _, xlsx) = render("xlsx").await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(&xlsx[..2], b"PK");

    // show_logo = false leaves it out.
    let (status, upd) = call(
        &app,
        ADMIN,
        Method::PUT,
        &base,
        Some(
            json!({ "code": "L1", "name": "Lijst", "valid_from": "2027-01-01",
                      "settings": { "show_logo": false } }),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{upd}");
    assert_eq!(upd["settings"]["show_logo"], false);
    let (_, _, pdf) = render("pdf").await;
    if let Some(n) = image_count(&pdf) {
        assert_eq!(n, 0);
    }

    // An SVG replaces the PNG.
    let svg = b"<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 10 10\"><rect width=\"10\" height=\"10\"/></svg>";
    let (status, _, body) = raw(
        &app,
        who(ADMIN),
        Method::PUT,
        LOGO_URL,
        Some((BINARY, svg.to_vec())),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{}", String::from_utf8_lossy(&body));
    let (_, headers, _) = raw(&app, who(ADMIN), Method::GET, LOGO_URL, None).await;
    assert_eq!(headers["content-type"], "image/svg+xml");
    assert!(headers.contains_key("content-security-policy"));

    // Delete; the list prints without it.
    let (status, _, _) = raw(&app, who(ADMIN), Method::DELETE, LOGO_URL, None).await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    let (status, _, _) = raw(&app, who(ADMIN), Method::GET, LOGO_URL, None).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, _, pdf) = render("pdf").await;
    assert_eq!(status, StatusCode::OK);
    assert!(pdf.starts_with(b"%PDF"));

    let actions: Vec<String> = sqlx::query_scalar(
        "SELECT action FROM audit.events WHERE entity = 'company' AND action LIKE 'logo_%' ORDER BY id",
    )
    .fetch_all(&db)
    .await
    .unwrap();
    assert_eq!(actions, ["logo_set", "logo_set", "logo_removed"]);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn zones_export_profiles_render_and_plan(db: PgPool) {
    let app = setup(db).await;
    let (_, list) = post(
        &app,
        ADMIN,
        URL,
        json!({ "code": "MZ", "name": "Multi", "valid_from": "2027-01-01" }),
    )
    .await;
    let base = format!("{URL}/{}", list["id"].as_str().unwrap());

    // No zones: nothing to render.
    let (status, _, _) = raw(
        &app,
        Who::Staff(ADMIN),
        Method::POST,
        &format!("{base}/render"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);

    // Zone validation: duplicate zone, unknown zone, bad language, no language.
    for body in [
        json!([{ "price_zone_id": Z1, "languages": ["nl"] }, { "price_zone_id": Z1, "languages": ["en"] }]),
        json!([{ "price_zone_id": "00000000-0000-7000-8000-0000000009ff", "languages": ["nl"] }]),
        json!([{ "price_zone_id": Z1, "languages": ["xx"] }]),
        json!([{ "price_zone_id": Z1, "languages": [] }]),
        json!([{ "price_zone_id": Z1, "languages": ["nl", "nl"] }]),
    ] {
        let (status, e) = put_zones(&app, &base, body.clone()).await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{body} -> {e}");
    }
    let (status, _) = call(
        &app,
        SALES,
        Method::PUT,
        &format!("{base}/zones"),
        Some(json!([])),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);

    let (status, l) = put_zones(
        &app,
        &base,
        json!([
            { "price_zone_id": Z2, "languages": ["nl"] },
            { "price_zone_id": Z1, "languages": ["en", "fr"] },
        ]),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{l}");
    // Request order is print order.
    assert_eq!(l["zones"][0]["price_zone_code"], "Z2");
    assert_eq!(l["zones"][1]["price_zone_code"], "Z1");

    // Groups and items: Pompen (A) with a sub-group, Slangen (B).
    let mk = |body: Value| {
        let app = app.clone();
        let url = format!("{base}/groups");
        async move { post(&app, ADMIN, &url, body).await.1 }
    };
    let a = mk(json!({ "sort_order": 1, "title": { "nl": "Pompen", "en": "Pumps" } })).await;
    let a_id = a["id"].as_str().unwrap().to_string();
    let a_sub = mk(json!({ "parent_id": a_id, "title": { "nl": "Kleine pompen" } })).await;
    let a_sub_id = a_sub["id"].as_str().unwrap().to_string();
    let b = mk(json!({ "sort_order": 2, "title": { "nl": "Slangen", "en": "Hoses" } })).await;
    let b_id = b["id"].as_str().unwrap().to_string();
    let c = mk(json!({ "sort_order": 3, "title": { "nl": "Leeg" } })).await;
    let c_id = c["id"].as_str().unwrap().to_string();
    for (product, group) in [(PUMP, &a_sub_id), (UNIT_100, &a_id), (HOSE, &b_id)] {
        let (status, i) = post(
            &app,
            ADMIN,
            &format!("{base}/items"),
            json!({ "product_id": product, "group_id": group }),
        )
        .await;
        assert_eq!(status, StatusCode::CREATED, "{i}");
    }

    // Several zones: zone_id is required, and the language must belong to that zone.
    let render = |q: String| {
        let app = app.clone();
        let uri = format!("{base}/render{q}");
        async move { raw(&app, Who::Staff(ADMIN), Method::POST, &uri, None).await }
    };
    assert_eq!(
        render(String::new()).await.0,
        StatusCode::UNPROCESSABLE_ENTITY
    );
    assert_eq!(
        render(format!("?zone_id={Z3}")).await.0,
        StatusCode::UNPROCESSABLE_ENTITY
    );
    assert_eq!(
        render(format!("?zone_id={Z2}&lang=en")).await.0,
        StatusCode::UNPROCESSABLE_ENTITY
    );
    let (status, headers, pdf) = render(format!("?zone_id={Z1}&lang=fr")).await;
    assert_eq!(status, StatusCode::OK);
    assert!(pdf.starts_with(b"%PDF"));
    assert!(headers["content-disposition"]
        .to_str()
        .unwrap()
        .contains("MZ-Z1-fr.pdf"));
    let (status, _, x) = render(format!("?zone_id={Z2}&format=xlsx")).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(&x[..2], b"PK");

    // Export profiles: a chapter, a combination; only top-level groups of this list.
    let ex = format!("{base}/exports");
    let (status, e) = post(
        &app,
        ADMIN,
        &ex,
        json!({ "code": "PUMPS", "name": "Pompen", "group_ids": [a_id] }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{e}");
    let pumps_id = e["id"].as_str().unwrap().to_string();
    for (body, expected) in [
        (
            json!({ "code": "PUMPS", "name": "Dup", "group_ids": [] }),
            StatusCode::CONFLICT,
        ),
        (
            json!({ "code": "SUB", "name": "Sub", "group_ids": [a_sub_id] }),
            StatusCode::UNPROCESSABLE_ENTITY,
        ),
        (
            json!({ "code": "TWICE", "name": "Twice", "group_ids": [a_id, a_id] }),
            StatusCode::UNPROCESSABLE_ENTITY,
        ),
        (
            json!({ "code": "FOREIGN", "name": "F", "group_ids": ["00000000-0000-7000-8000-0000000000ff"] }),
            StatusCode::UNPROCESSABLE_ENTITY,
        ),
        (
            json!({ "code": " ", "name": "Blank" }),
            StatusCode::UNPROCESSABLE_ENTITY,
        ),
    ] {
        let (status, e) = post(&app, ADMIN, &ex, body.clone()).await;
        assert_eq!(status, expected, "{body} -> {e}");
    }
    let (status, _) = post(&app, SALES, &ex, json!({ "code": "S", "name": "S" })).await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, e) = post(&app, ADMIN, &ex, json!({ "code": "BOTH", "name": "Pompen en slangen", "sort_order": 5, "group_ids": [b_id, a_id] })).await;
    assert_eq!(status, StatusCode::CREATED, "{e}");

    // A chapter's file has its chapters only, with everything below; the other chapter is absent.
    let (status, _, pdf) = render(format!("?zone_id={Z2}&export_id={pumps_id}")).await;
    assert_eq!(status, StatusCode::OK);
    if let Some(t) = text(&pdf) {
        assert!(t.contains("Pompen") && t.contains("Kleine pompen"), "{t}");
        assert!(!t.contains("Slangen"), "{t}");
    }
    let (_, _, pdf) = render(format!("?zone_id={Z2}")).await;
    if let Some(t) = text(&pdf) {
        assert!(t.contains("Pompen") && t.contains("Slangen"), "{t}");
    }
    // A profile of another list does not exist here.
    let (status, _, _) = render(format!(
        "?zone_id={Z2}&export_id=00000000-0000-7000-8000-0000000000ff"
    ))
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    // Per chapter: B gets one (A already has PUMPS), C (empty) too; a second call adds nothing.
    let (status, all) = post(&app, ADMIN, &format!("{ex}/per-chapter"), json!({})).await;
    assert_eq!(status, StatusCode::OK, "{all}");
    assert_eq!(all.as_array().unwrap().len(), 4, "{all}");
    let (_, again) = post(&app, ADMIN, &format!("{ex}/per-chapter"), json!({})).await;
    assert_eq!(again, all, "idempotent");
    let b_profile = all
        .as_array()
        .unwrap()
        .iter()
        .find(|e| e["group_ids"] == json!([b_id]))
        .unwrap();
    assert_eq!(b_profile["name"], "Slangen");

    // Plan: Z2 x nl, Z1 x (en, fr); whole list + 4 profiles each.
    let (status, plan) = call(
        &app,
        SALES,
        Method::GET,
        &format!("{base}/export-plan?format=xlsx"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let plan = plan.as_array().unwrap();
    assert_eq!(plan.len(), 3 * 5);
    assert_eq!(
        plan[0]["relative_path"],
        "Multi/Zone 2 – Installers/nl/Multi.xlsx"
    );
    assert_eq!(plan[0]["export_id"], Value::Null);
    assert_eq!(plan[0]["zone_code"], "Z2");
    assert_eq!(plan[0]["format"], "xlsx");
    assert!(plan.iter().any(
        |e| e["relative_path"] == "Multi/Zone 1 – Retail/fr/Pompen.xlsx"
            || e["relative_path"]
                .as_str()
                .unwrap()
                .ends_with("/fr/Pompen.xlsx")
    ));
    let (_, pdf_plan) = call(
        &app,
        ADMIN,
        Method::GET,
        &format!("{base}/export-plan"),
        None,
    )
    .await;
    assert!(pdf_plan[0]["relative_path"]
        .as_str()
        .unwrap()
        .ends_with(".pdf"));

    // A hostile list name never leaves the plan's folder structure.
    let (status, _) = call(
        &app,
        ADMIN,
        Method::PUT,
        &base,
        Some(json!({ "code": "MZ", "name": "../../etc/CON", "valid_from": "2027-01-01" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (_, plan) = call(
        &app,
        ADMIN,
        Method::GET,
        &format!("{base}/export-plan"),
        None,
    )
    .await;
    for e in plan.as_array().unwrap() {
        let path = e["relative_path"].as_str().unwrap();
        assert!(
            !path.contains("..") && !path.starts_with('/') && !path.contains('\\'),
            "{path}"
        );
        assert_eq!(path.split('/').count(), 4, "{path}");
    }

    // A group a profile uses cannot be deleted or moved below another group.
    let (status, e) = call(
        &app,
        ADMIN,
        Method::DELETE,
        &format!("{base}/groups/{c_id}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT, "{e}");
    assert!(e.to_string().contains("ch-"), "names the profile: {e}");
    let (status, _) = call(
        &app,
        ADMIN,
        Method::PUT,
        &format!("{base}/groups/{c_id}"),
        Some(json!({ "parent_id": b_id, "title": { "nl": "Leeg" } })),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
    // Plain edits of the group are fine; after the profile goes the group can go.
    let (status, _) = call(
        &app,
        ADMIN,
        Method::PUT,
        &format!("{base}/groups/{c_id}"),
        Some(json!({ "sort_order": 9, "title": { "nl": "Leeg" } })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let c_profile = all
        .as_array()
        .unwrap()
        .iter()
        .find(|e| e["group_ids"] == json!([c_id]))
        .unwrap()["id"]
        .as_str()
        .unwrap();
    let (status, _) = call(
        &app,
        ADMIN,
        Method::DELETE,
        &format!("{ex}/{c_profile}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    let (status, _) = call(
        &app,
        ADMIN,
        Method::DELETE,
        &format!("{base}/groups/{c_id}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NO_CONTENT);

    // A zone a list is published for cannot be deleted.
    let (status, e) = call(
        &app,
        ADMIN,
        Method::DELETE,
        &format!("/api/v1/price-zones/{Z1}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT, "{e}");
}

// ---------------------------------------------------------------------------------------------
// Normalised persistence (ADR 0069): constraints that hold below the API
// ---------------------------------------------------------------------------------------------

async fn new_list(app: &axum::Router, code: &str) -> String {
    let (status, list) = post(
        app,
        ADMIN,
        URL,
        json!({ "code": code, "name": code, "valid_from": "2027-01-01" }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{list}");
    format!("{URL}/{}", list["id"].as_str().unwrap())
}

async fn new_group(app: &axum::Router, base: &str, body: Value) -> String {
    let (status, g) = post(app, ADMIN, &format!("{base}/groups"), body).await;
    assert_eq!(status, StatusCode::CREATED, "{g}");
    g["id"].as_str().unwrap().to_string()
}

fn db_code(e: &sqlx::Error) -> Option<String> {
    e.as_database_error()
        .and_then(|d| d.code())
        .map(|c| c.into_owned())
}

const NORMALISED_TABLES: [&str; 8] = [
    "price_list_zones",
    "price_list_zone_languages",
    "price_list_groups",
    "price_list_group_titles",
    "price_list_items",
    "price_list_item_descriptions",
    "price_list_exports",
    "price_list_export_groups",
];

async fn rows(db: &PgPool, table: &str) -> i64 {
    sqlx::query_scalar(&format!("SELECT count(*) FROM pricing.{table}"))
        .fetch_one(db)
        .await
        .unwrap()
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn deleting_a_list_removes_every_normalised_row(db: PgPool) {
    let app = setup(db.clone()).await;
    let base = new_list(&app, "CAS").await;
    let (status, _) = put_zones(
        &app,
        &base,
        json!([{ "price_zone_id": Z1, "languages": ["nl", "en"] }]),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let chapter = new_group(&app, &base, json!({ "title": { "nl": "A", "en": "B" } })).await;
    let (status, item) = post(
        &app,
        ADMIN,
        &format!("{base}/items"),
        json!({ "product_id": PUMP, "group_id": chapter, "description": { "nl": "Eigen tekst" } }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{item}");
    let (status, e) = post(
        &app,
        ADMIN,
        &format!("{base}/exports"),
        json!({ "code": "E1", "name": "E1", "group_ids": [chapter] }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{e}");
    for t in NORMALISED_TABLES {
        assert!(rows(&db, t).await > 0, "{t} should have rows");
    }
    let (status, _) = call(&app, ADMIN, Method::DELETE, &base, None).await;
    assert_eq!(status, StatusCode::NO_CONTENT);
    for t in NORMALISED_TABLES {
        assert_eq!(rows(&db, t).await, 0, "{t} should be empty");
    }
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn an_export_cannot_link_a_group_of_another_list(db: PgPool) {
    let app = setup(db.clone()).await;
    let a = new_list(&app, "LA").await;
    let b = new_list(&app, "LB").await;
    let group_b = new_group(&app, &b, json!({ "title": { "nl": "B" } })).await;
    let (status, e) = post(
        &app,
        ADMIN,
        &format!("{a}/exports"),
        json!({ "code": "X", "name": "X", "group_ids": [group_b] }),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{e}");

    // The same attempt straight at the table is stopped by the composite foreign key.
    let (status, e) = post(
        &app,
        ADMIN,
        &format!("{a}/exports"),
        json!({ "code": "OK", "name": "OK" }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{e}");
    let err = sqlx::query(
        "INSERT INTO pricing.price_list_export_groups (export_id, group_id, price_list_id, company_id, sort_order)
         SELECT e.id, $2, e.price_list_id, e.company_id, 0 FROM pricing.price_list_exports e WHERE e.id = $1",
    )
    .bind(uuid::Uuid::parse_str(e["id"].as_str().unwrap()).unwrap())
    .bind(uuid::Uuid::parse_str(&group_b).unwrap())
    .execute(&db)
    .await
    .unwrap_err();
    assert_eq!(db_code(&err).as_deref(), Some("23503"), "{err}");
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn export_links_only_top_level_groups_and_block_group_changes(db: PgPool) {
    let app = setup(db.clone()).await;
    let base = new_list(&app, "TOP").await;
    let top = new_group(&app, &base, json!({ "title": { "nl": "Top" } })).await;
    let other = new_group(&app, &base, json!({ "title": { "nl": "Other" } })).await;
    let sub = new_group(
        &app,
        &base,
        json!({ "parent_id": top, "title": { "nl": "Sub" } }),
    )
    .await;
    let (status, e) = post(
        &app,
        ADMIN,
        &format!("{base}/exports"),
        json!({ "code": "S", "name": "S", "group_ids": [sub] }),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{e}");
    let (status, e) = post(
        &app,
        ADMIN,
        &format!("{base}/exports"),
        json!({ "code": "T", "name": "T", "group_ids": [other, top] }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{e}");
    assert_eq!(e["group_ids"], json!([other, top]), "profile order is kept");

    // The database refuses a sub-group in a profile, whatever the API says.
    let err = sqlx::query(
        "INSERT INTO pricing.price_list_export_groups (export_id, group_id, price_list_id, company_id, sort_order)
         SELECT e.id, $2, e.price_list_id, e.company_id, 9 FROM pricing.price_list_exports e WHERE e.id = $1",
    )
    .bind(uuid::Uuid::parse_str(e["id"].as_str().unwrap()).unwrap())
    .bind(uuid::Uuid::parse_str(&sub).unwrap())
    .execute(&db)
    .await
    .unwrap_err();
    assert_eq!(db_code(&err).as_deref(), Some("23514"), "{err}");

    // ... and refuses to move a used group below another one.
    let err = sqlx::query("UPDATE pricing.price_list_groups SET parent_id = $2 WHERE id = $1")
        .bind(uuid::Uuid::parse_str(&other).unwrap())
        .bind(uuid::Uuid::parse_str(&top).unwrap())
        .execute(&db)
        .await
        .unwrap_err();
    assert_eq!(db_code(&err).as_deref(), Some("23514"), "{err}");

    // API: moving it is a 409, so is deleting it, and the message names the profile.
    let (status, m) = call(
        &app,
        ADMIN,
        Method::PUT,
        &format!("{base}/groups/{other}"),
        Some(json!({ "parent_id": top, "title": { "nl": "Other" } })),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT, "{m}");
    let (status, m) = call(
        &app,
        ADMIN,
        Method::DELETE,
        &format!("{base}/groups/{other}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT, "{m}");
    assert!(m.to_string().contains('T'), "{m}");
    // The database alone also refuses the delete (foreign key from the link).
    let err = sqlx::query("DELETE FROM pricing.price_list_groups WHERE id = $1")
        .bind(uuid::Uuid::parse_str(&other).unwrap())
        .execute(&db)
        .await
        .unwrap_err();
    assert_eq!(db_code(&err).as_deref(), Some("23503"), "{err}");

    // Replace-all: dropping the group from the profile frees it.
    let (status, _) = call(
        &app,
        ADMIN,
        Method::PUT,
        &format!("{base}/exports/{}", e["id"].as_str().unwrap()),
        Some(json!({ "code": "T", "name": "T", "group_ids": [top] })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (status, _) = call(
        &app,
        ADMIN,
        Method::DELETE,
        &format!("{base}/groups/{other}"),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NO_CONTENT);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn group_title_falls_back_through_the_language_chain(db: PgPool) {
    let app = setup(db.clone()).await;
    let base = new_list(&app, "FB").await;
    let (status, _) = put_zones(
        &app,
        &base,
        json!([{ "price_zone_id": Z1, "languages": ["nl", "en"] }]),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let g = new_group(
        &app,
        &base,
        json!({ "title": { "nl": "Alleen Nederlands", "de": "Nur Deutsch" } }),
    )
    .await;
    let (status, _) = post(
        &app,
        ADMIN,
        &format!("{base}/items"),
        json!({ "product_id": UNIT_100, "group_id": g }),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED);
    // Titles come back as a map, updated as a whole.
    let (_, groups) = call(&app, ADMIN, Method::GET, &format!("{base}/groups"), None).await;
    assert_eq!(
        groups[0]["title"],
        json!({ "de": "Nur Deutsch", "nl": "Alleen Nederlands" })
    );
    let (_, _, pdf) = raw(
        &app,
        Who::Staff(ADMIN),
        Method::POST,
        &format!("{base}/render?lang=en&format=pdf"),
        None,
    )
    .await;
    if let Some(t) = text(&pdf) {
        assert!(
            t.contains("Alleen Nederlands"),
            "en -> company default nl:\n{t}"
        );
    }
    let (status, g2) = call(
        &app,
        ADMIN,
        Method::PUT,
        &format!("{base}/groups/{g}"),
        Some(json!({ "title": { "en": "Only English" } })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{g2}");
    assert_eq!(g2["title"], json!({ "en": "Only English" }));
    assert_eq!(rows(&db, "price_list_group_titles").await, 1);
    let (_, _, pdf) = raw(
        &app,
        Who::Staff(ADMIN),
        Method::POST,
        &format!("{base}/render?lang=en&format=pdf"),
        None,
    )
    .await;
    if let Some(t) = text(&pdf) {
        assert!(t.contains("Only English"), "{t}");
    }
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_zone_always_keeps_at_least_one_language(db: PgPool) {
    let app = setup(db.clone()).await;
    let base = new_list(&app, "ZL").await;
    let (status, l) = put_zones(
        &app,
        &base,
        json!([{ "price_zone_id": Z1, "languages": ["fr", "nl", "en"] }]),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{l}");
    assert_eq!(l["zones"][0]["languages"], json!(["fr", "nl", "en"]));
    // The API rejects an empty list and keeps the old zone.
    let (status, _) = put_zones(
        &app,
        &base,
        json!([{ "price_zone_id": Z1, "languages": [] }]),
    )
    .await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
    assert_eq!(rows(&db, "price_list_zone_languages").await, 3);

    // The database enforces it at commit: removing every language of a zone fails ...
    let mut tx = db.begin().await.unwrap();
    sqlx::query("DELETE FROM pricing.price_list_zone_languages")
        .execute(&mut *tx)
        .await
        .unwrap();
    let err = tx.commit().await.unwrap_err();
    assert_eq!(db_code(&err).as_deref(), Some("23514"), "{err}");
    // ... replacing them inside one transaction is fine, and so is a zone without rows
    // being removed together with its languages.
    let mut tx = db.begin().await.unwrap();
    sqlx::query("DELETE FROM pricing.price_list_zone_languages WHERE language <> 'nl'")
        .execute(&mut *tx)
        .await
        .unwrap();
    tx.commit().await.unwrap();
    let mut tx = db.begin().await.unwrap();
    sqlx::query("DELETE FROM pricing.price_list_zones")
        .execute(&mut *tx)
        .await
        .unwrap();
    tx.commit().await.unwrap();
    assert_eq!(rows(&db, "price_list_zone_languages").await, 0);

    // A new zone row without language is refused at commit as well.
    let mut tx = db.begin().await.unwrap();
    sqlx::query(
        "INSERT INTO pricing.price_list_zones (id, company_id, price_list_id, price_zone_id)
         SELECT gen_random_uuid(), company_id, id, $2 FROM pricing.price_lists WHERE id = $1",
    )
    .bind(uuid::Uuid::parse_str(base.rsplit('/').next().unwrap()).unwrap())
    .bind(uuid::Uuid::parse_str(Z1).unwrap())
    .execute(&mut *tx)
    .await
    .unwrap();
    let err = tx.commit().await.unwrap_err();
    assert_eq!(db_code(&err).as_deref(), Some("23514"), "{err}");
}
