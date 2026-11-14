//! Accent-insensitive search (ADR 0057, roadmap D5): customers, contacts, products and suppliers.
//! "Liege" finds "Liège", whatever the case, and the trigram indexes serve the very same query.

mod common;

use axum::http::{Method, StatusCode};
use common::{call, setup};
use serde_json::{json, Value};
use sqlx::PgPool;
use uuid::Uuid;

const ADMIN: &str = "admin@example.com";
const SALES: &str = "sales@example.com";
const SUPPORT: &str = "support@example.com";
const BETA: &str = "00000000-0000-7000-8000-000000000402";
const ZONE: &str = "00000000-0000-7000-8000-000000000202";
const COMPANY: &str = "00000000-0000-7000-8000-000000000001";

async fn get(app: &axum::Router, user: &str, uri: &str) -> (StatusCode, Value) {
    call(app, user, Method::GET, &format!("/api/v1{uri}"), None).await
}

/// The codes of the items of a customer or product page, sorted.
fn codes(page: &Value) -> Vec<String> {
    let mut v: Vec<String> = page["items"]
        .as_array()
        .unwrap()
        .iter()
        .map(|i| i["code"].as_str().unwrap().to_string())
        .collect();
    v.sort();
    v
}

/// The search of a list endpoint, URL-encoded by hand for the few characters tests use.
fn enc(q: &str) -> String {
    q.bytes()
        .map(|b| match b {
            b'a'..=b'z' | b'A'..=b'Z' | b'0'..=b'9' | b'-' | b'.' | b'~' => (b as char).to_string(),
            _ => format!("%{b:02X}"),
        })
        .collect()
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_fold_covers_the_accents_of_the_five_languages(db: PgPool) {
    // Dutch, French, English, German and Spanish: what staff and customers actually type.
    let cases = [
        ("Liège", "liege"),
        ("Bêta Industrie", "beta industrie"),
        ("Köln", "koln"),
        ("Werkstraße", "werkstrasse"),
        ("Müller", "muller"),
        ("Ärger Öl Über", "arger ol uber"),
        ("François Çelik", "francois celik"),
        ("Zoë Reünie Ïris", "zoe reunie iris"),
        ("España Peña Niño", "espana pena nino"),
        (
            "José Ángel Íñigo Óscar Úrsula",
            "jose angel inigo oscar ursula",
        ),
        ("œuvre Æther", "oeuvre aether"),
        ("Ångström", "angstrom"),
        ("Łódź", "lodz"),
        // Already plain, in any case, stays plain.
        ("ABC def 123 - x/y", "abc def 123 - x/y"),
    ];
    for (typed, folded) in cases {
        let got: String = sqlx::query_scalar("SELECT core.search_fold($1)")
            .bind(typed)
            .fetch_one(&db)
            .await
            .unwrap();
        assert_eq!(got, folded, "{typed}");
    }
    // NULL stays NULL, so a missing value never matches.
    let none: Option<String> = sqlx::query_scalar("SELECT core.search_fold(NULL)")
        .fetch_one(&db)
        .await
        .unwrap();
    assert_eq!(none, None);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn customers_are_found_without_regard_to_accents_and_case(db: PgPool) {
    let app = setup(db).await;
    // The seed: "Bêta Industrie SA" in "Liège" (C0002) and "Gamma Trading GmbH" in "Köln" (C0003).
    for q in [
        "Liege",
        "liège",
        "LIEGE",
        "  liege  ",
        "Beta",
        "bêta",
        "BETA industrie",
        "Bêta Ind",
    ] {
        let (status, page) = get(&app, SALES, &format!("/customers?q={}", enc(q))).await;
        assert_eq!(status, StatusCode::OK, "{q}");
        assert_eq!(codes(&page), ["C0002"], "{q}: {page}");
        assert_eq!(page["total"], 1, "{q}");
    }
    for q in ["Koln", "köln", "KÖLN"] {
        let (_, page) = get(&app, SALES, &format!("/customers?q={}", enc(q))).await;
        assert_eq!(codes(&page), ["C0003"], "{q}");
    }
    // Code and VAT number still work, and a search matches nothing it should not.
    let (_, page) = get(&app, SALES, "/customers?q=C0001").await;
    assert_eq!(codes(&page), ["C0001"]);
    let (_, page) = get(&app, SALES, "/customers?q=BE0000000196").await;
    assert_eq!(codes(&page), ["C0002"]);
    let (_, page) = get(&app, SALES, "/customers?q=nowhere").await;
    assert_eq!((codes(&page).len(), page["total"].as_i64()), (0, Some(0)));
    // No search text, or blanks: everything.
    for q in ["", "%20%20"] {
        let (_, page) = get(&app, SALES, &format!("/customers?q={q}")).await;
        assert_eq!(page["total"], 3, "{q:?}");
    }
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn a_percent_or_underscore_in_the_search_is_just_a_character(db: PgPool) {
    let app = setup(db).await;
    for (code, name) in [
        ("W1", "Rabat 100% BV"),
        ("W2", "snake_case NV"),
        ("W3", "Plain NV"),
    ] {
        let (status, c) = call(
            &app,
            SALES,
            Method::POST,
            "/api/v1/customers",
            Some(json!({"code": code, "name": name, "country_code": "BE", "price_zone_id": ZONE})),
        )
        .await;
        assert_eq!(status, StatusCode::CREATED, "{c}");
    }
    let (_, page) = get(&app, SALES, "/customers?q=%25").await;
    assert_eq!(codes(&page), ["W1"], "% is a percent sign, not 'anything'");
    let (_, page) = get(&app, SALES, "/customers?q=_").await;
    assert_eq!(
        codes(&page),
        ["W2"],
        "_ is an underscore, not 'any character'"
    );
    let (_, page) = get(&app, SALES, &format!("/customers?q={}", enc("e_c"))).await;
    assert_eq!(codes(&page), ["W2"]);
    let (_, page) = get(&app, SALES, &format!("/customers?q={}", enc("\\"))).await;
    assert_eq!(
        page["total"], 0,
        "a backslash is a character too, and nothing has one"
    );
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn products_are_found_without_regard_to_accents(db: PgPool) {
    let app = setup(db.clone()).await;
    for (code, name) in [
        ("ACC-1", "Crème de pompe"),
        ("ACC-2", "Strömungssensor"),
        ("ÉTÉ-3", "Ventilador"),
    ] {
        sqlx::query("INSERT INTO products.products (id, code, name) VALUES ($1, $2, $3)")
            .bind(Uuid::now_v7())
            .bind(code)
            .bind(name)
            .execute(&db)
            .await
            .unwrap();
    }
    for (q, expect) in [
        ("creme", vec!["ACC-1"]),
        ("CRÈME", vec!["ACC-1"]),
        ("stromungssensor", vec!["ACC-2"]),
        ("Strömung", vec!["ACC-2"]),
        // The code is searched the same way.
        ("ete", vec!["ÉTÉ-3"]),
        ("été-3", vec!["ÉTÉ-3"]),
        ("acc-", vec!["ACC-1", "ACC-2"]),
    ] {
        let (status, page) = get(&app, SALES, &format!("/products?q={}", enc(q))).await;
        assert_eq!(status, StatusCode::OK, "{q}");
        assert_eq!(codes(&page), expect, "{q}: {page}");
        assert_eq!(page["total"], expect.len() as i64, "{q}");
    }
    // Combined with the other filters.
    let (_, page) = get(&app, SALES, "/products?q=acc&active=false").await;
    assert_eq!(page["total"], 0);
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn contacts_are_found_by_name_in_either_order_and_by_customer(db: PgPool) {
    let app = setup(db).await;
    let (status, c) = call(
        &app,
        SUPPORT,
        Method::POST,
        &format!("/api/v1/customers/{BETA}/contacts"),
        Some(json!({"first_name": "Renée", "last_name": "Lefèvre"})),
    )
    .await;
    assert_eq!(status, StatusCode::CREATED, "{c}");
    let id = c["id"].as_str().unwrap().to_string();

    for q in [
        "renee",
        "Lefevre",
        "renee lefevre",
        "lefevre renee",
        "RENÉE LEFÈVRE",
        "efev",
    ] {
        let (status, r) = get(&app, SUPPORT, &format!("/contacts/lookup?q={}", enc(q))).await;
        assert_eq!(status, StatusCode::OK, "{q}");
        let ids: Vec<&str> = r["contacts"]
            .as_array()
            .unwrap()
            .iter()
            .map(|c| c["id"].as_str().unwrap())
            .collect();
        assert_eq!(ids, [id.as_str()], "{q}: {r}");
    }
    // The customer's name finds its contacts too, accents or not.
    let (_, r) = get(&app, SUPPORT, "/contacts/lookup?q=beta").await;
    assert!(
        r["contacts"]
            .as_array()
            .unwrap()
            .iter()
            .any(|c| c["id"] == id.as_str()),
        "{r}"
    );
    let (_, r) = get(&app, SUPPORT, "/contacts/lookup?q=gamma").await;
    assert!(r["contacts"]
        .as_array()
        .unwrap()
        .iter()
        .all(|c| c["id"] != id.as_str()));
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn suppliers_have_a_search_with_the_same_rules(db: PgPool) {
    let app = setup(db.clone()).await;
    for (name, code, contact) in [
        ("Müller Elektronik", "MUL", "José Núñez"),
        ("Plain Parts", "PLN", "Ann"),
        ("Société Générale des Vis", "SGV", ""),
    ] {
        let (status, s) = call(
            &app,
            ADMIN,
            Method::POST,
            "/api/v1/suppliers",
            Some(
                json!({"name": name, "code": code, "country": "BE", "contact_person": contact,
                        "email": format!("{}@example.com", code.to_lowercase())}),
            ),
        )
        .await;
        assert_eq!(status, StatusCode::CREATED, "{s}");
    }
    let names = |v: &Value| -> Vec<String> {
        v.as_array()
            .unwrap()
            .iter()
            .map(|s| s["name"].as_str().unwrap().to_string())
            .collect()
    };
    for (q, expect) in [
        ("muller", vec!["Müller Elektronik"]),
        ("MÜLLER", vec!["Müller Elektronik"]),
        ("jose nunez", vec!["Müller Elektronik"]),
        ("societe generale", vec!["Société Générale des Vis"]),
        // Code and e-mail address are searched as well.
        ("pln", vec!["Plain Parts"]),
        ("sgv@example", vec!["Société Générale des Vis"]),
    ] {
        let (status, list) = get(&app, ADMIN, &format!("/suppliers?q={}", enc(q))).await;
        assert_eq!(status, StatusCode::OK, "{q}");
        assert_eq!(names(&list), expect, "{q}");
    }
    // No search: all, ordered by name. Blank: all.
    let (_, all) = get(&app, ADMIN, "/suppliers").await;
    assert_eq!(
        names(&all),
        [
            "Müller Elektronik",
            "Plain Parts",
            "Société Générale des Vis"
        ]
    );
    let (_, blank) = get(&app, ADMIN, "/suppliers?q=%20").await;
    assert_eq!(names(&blank).len(), 3);

    // The active filter combines with it, and another company's suppliers are never found.
    sqlx::query("UPDATE purchasing.suppliers SET active = false WHERE code = 'MUL'")
        .execute(&db)
        .await
        .unwrap();
    let (_, list) = get(&app, ADMIN, "/suppliers?q=muller&active_only=true").await;
    assert_eq!(names(&list).len(), 0);
    let (_, list) = get(&app, ADMIN, "/suppliers?q=muller").await;
    assert_eq!(names(&list).len(), 1);
    let other = Uuid::now_v7();
    sqlx::query("INSERT INTO core.companies (id, name) VALUES ($1, 'Other BV')")
        .bind(other)
        .execute(&db)
        .await
        .unwrap();
    sqlx::query("INSERT INTO purchasing.suppliers (id, company_id, name, country) VALUES ($1, $2, 'Müller Elsewhere', 'BE')")
        .bind(Uuid::now_v7())
        .bind(other)
        .execute(&db)
        .await
        .unwrap();
    let (_, list) = get(&app, ADMIN, "/suppliers?q=muller").await;
    assert_eq!(names(&list), ["Müller Elektronik"]);
    // The company id is only in the seed users' memberships, not needed here.
    let _ = (SALES, COMPANY);
}

/// The indexes of the migration serve the query the lists run: with sequential scans forbidden
/// the planner must still answer, and it can only do that through the trigram indexes if the
/// expressions match the ones in the queries.
#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn the_trigram_indexes_match_the_queries(db: PgPool) {
    use tradocraft_core::search::matches;
    let mut conn = db.acquire().await.unwrap();
    sqlx::query("SET enable_seqscan = off")
        .execute(&mut *conn)
        .await
        .unwrap();

    let ors = |cols: &[&str]| {
        cols.iter()
            .map(|c| matches(c, "'%x%'"))
            .collect::<Vec<_>>()
            .join(" OR ")
    };
    let cases = [
        (
            format!(
                "SELECT 1 FROM crm.customers c WHERE {}",
                ors(&["c.code", "c.name", "c.vat_number", "c.city"])
            ),
            vec![
                "customers_code_fold_idx",
                "customers_name_fold_idx",
                "customers_vat_fold_idx",
                "customers_city_fold_idx",
            ],
        ),
        (
            format!(
                "SELECT 1 FROM products.products WHERE {}",
                ors(&["code", "name"])
            ),
            vec!["products_code_fold_idx", "products_name_fold_idx"],
        ),
        (
            format!(
                "SELECT 1 FROM crm.contacts c WHERE {}",
                ors(&[
                    "c.first_name || ' ' || c.last_name",
                    "c.last_name || ' ' || c.first_name"
                ])
            ),
            vec!["contacts_name_fold_idx", "contacts_name_reversed_fold_idx"],
        ),
    ];
    for (sql, indexes) in cases {
        let plan: Vec<String> = sqlx::query_scalar(&format!("EXPLAIN {sql}"))
            .fetch_all(&mut *conn)
            .await
            .unwrap();
        let plan = plan.join("\n");
        for idx in indexes {
            assert!(plan.contains(idx), "{idx} is not used by:\n{sql}\n{plan}");
        }
    }
}
