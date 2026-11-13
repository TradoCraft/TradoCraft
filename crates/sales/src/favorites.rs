//! Company-wide favorites for sales lines (ADR 0062): one main product with its option lines and
//! comments, stored once and loaded into a quotation. A favorite stores no prices: loading one
//! prices it with the normal pricing of the quotation.
//!
//! Every query is scoped by the caller's company; an unknown or foreign id answers 404. Reading
//! needs `quotations.read`, every change `quotations.write`.

use std::collections::{HashMap, HashSet};

use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::Json;
use chrono::{DateTime, Utc};
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection};
use tradocraft_core::audit::{self, Changes};
use tradocraft_core::{
    is_language, new_id, search, AppError, AppResult, AppState, CurrentUser, Permission, LANGUAGES,
};
use utoipa::{IntoParams, ToSchema};
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::model::PercentBase;
use crate::service::{MAX_REMARK_LEN, MAX_SECTION_LEN};

type ErrorBody = tradocraft_core::error::ErrorBody;

/// Most items (the main product and its option lines together) in one favorite.
pub const MAX_ITEMS: usize = 40;
/// Longest favorite name.
pub const MAX_NAME_LEN: usize = 120;
/// Largest accepted quantity.
const MAX_QUANTITY: i64 = 1_000_000;
const NOT_FOUND: &str = "favorite";

/// One row of the list.
#[derive(Debug, Serialize, ToSchema)]
pub struct FavoriteSummary {
    pub id: Uuid,
    pub name: String,
    pub main_product_id: Uuid,
    pub main_product_code: String,
    pub main_product_name: String,
    /// Whether the main product is still active.
    pub main_product_active: bool,
    /// The number of lines below the main item.
    pub option_count: i64,
    /// The languages (nl, fr, en, de, es) in which at least one customer remark exists.
    pub languages: Vec<String>,
    pub updated_at: DateTime<Utc>,
}

/// The customer remark of an item in one language.
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct FavoriteRemark {
    /// nl | fr | en | de | es
    pub language: String,
    pub text: String,
}

/// An item of a favorite as stored.
#[derive(Debug, Serialize, ToSchema)]
pub struct FavoriteItem {
    /// Stable across edits that send it back; quotation lines loaded from this item point at it.
    pub id: Uuid,
    /// 1-based, in the order the lines are loaded.
    pub position: i32,
    /// Position of the parent item; absent for the single main item.
    pub parent_position: Option<i32>,
    pub product_id: Uuid,
    pub product_code: String,
    /// The product's base name (the app shows the translated name when it has one).
    pub product_name: String,
    pub unit: String,
    /// `false` when the product was deactivated after the favorite was saved: the item is kept,
    /// the app flags it and does not load it.
    pub product_active: bool,
    /// Main item: the default quantity. Other items: the quantity per ONE unit of the main item.
    #[schema(value_type = String, example = "1")]
    pub quantity: Decimal,
    pub section: Option<String>,
    /// The small printed comment under the line (one text, no language).
    pub comment: Option<String>,
    /// Internal remark for production (one text, no language).
    pub production_remark: String,
    #[schema(value_type = Option<String>, example = "20")]
    pub percent_of_parent: Option<Decimal>,
    pub percent_base: Option<PercentBase>,
    /// The customer remark per language, in the order nl, fr, en, de, es.
    pub remarks: Vec<FavoriteRemark>,
}

/// A favorite with its items.
#[derive(Debug, Serialize, ToSchema)]
pub struct Favorite {
    pub id: Uuid,
    pub name: String,
    pub created_by: Uuid,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    /// In loading order; the first item is the main item.
    pub items: Vec<FavoriteItem>,
}

/// An item as sent when creating or replacing a favorite. No prices.
#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct FavoriteItemInput {
    /// On `PUT`: the id of an existing item of this favorite, to keep it (and the lines that point
    /// at it). Omitted: a new item. `POST` takes no ids.
    pub id: Option<Uuid>,
    pub product_id: Uuid,
    #[schema(value_type = String, example = "1")]
    pub quantity: Decimal,
    /// Position (1-based, in this list) of an earlier item this one belongs to. Omitted: the main
    /// item, which must be exactly one and first.
    #[serde(default)]
    pub parent_position: Option<i32>,
    #[serde(default)]
    pub section: Option<String>,
    #[serde(default)]
    pub comment: Option<String>,
    #[serde(default)]
    pub production_remark: String,
    #[serde(default)]
    #[schema(value_type = Option<String>, example = "20")]
    pub percent_of_parent: Option<Decimal>,
    #[serde(default)]
    pub percent_base: Option<PercentBase>,
    /// Customer remarks, at most one per language; blank texts are dropped.
    #[serde(default)]
    pub remarks: Vec<FavoriteRemark>,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct FavoriteInput {
    /// Unique in the company, ignoring case; at most 120 characters.
    pub name: String,
    /// The main item first, then its option lines; 1 to 40 items.
    pub items: Vec<FavoriteItemInput>,
}

/// The body of the call that adds a customer remark in one language.
#[derive(Debug, Deserialize, ToSchema)]
pub struct FavoriteRemarkInput {
    /// The remark; not blank, at most 2000 characters.
    pub text: String,
    /// Replace a text that already exists in that language. Default `false`: answer 409 instead.
    #[serde(default)]
    pub overwrite: bool,
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct FavoriteListParams {
    /// Searches the name and the code and name of the main product, ignoring case and accents.
    pub q: Option<String>,
    /// Default 50, at most 200.
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}

#[derive(FromRow)]
struct SummaryRow {
    id: Uuid,
    name: String,
    main_product_id: Uuid,
    main_product_code: String,
    main_product_name: String,
    main_product_active: bool,
    option_count: i64,
    languages: Vec<String>,
    updated_at: DateTime<Utc>,
}

#[derive(FromRow)]
struct ItemRow {
    id: Uuid,
    position: i32,
    parent_position: Option<i32>,
    product_id: Uuid,
    product_code: String,
    product_name: String,
    unit: String,
    product_active: bool,
    quantity: Decimal,
    section: Option<String>,
    comment: Option<String>,
    production_remark: String,
    percent_of_parent: Option<Decimal>,
    percent_base: Option<String>,
}

#[derive(FromRow)]
struct RemarkRow {
    item_id: Uuid,
    language: String,
    text: String,
}

#[derive(FromRow)]
struct HeaderRow {
    id: Uuid,
    name: String,
    created_by: Uuid,
    created_at: DateTime<Utc>,
    updated_at: DateTime<Utc>,
}

/// The trimmed text, or `None` when it is absent or blank.
fn clean(s: &Option<String>) -> Option<String> {
    s.as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_string)
}

fn too_long(s: &str, max: usize) -> bool {
    s.trim().chars().count() > max
}

fn invalid(msg: String) -> AppError {
    AppError::Validation(msg)
}

/// The favorite's header, locked when `lock`; 404 for an unknown or foreign id.
async fn header(
    conn: &mut PgConnection,
    company_id: Uuid,
    id: Uuid,
    lock: bool,
) -> AppResult<HeaderRow> {
    let sql = format!(
        "SELECT id, name, created_by, created_at, updated_at FROM sales.favorites
         WHERE id = $1 AND company_id = $2{}",
        if lock { " FOR UPDATE" } else { "" }
    );
    sqlx::query_as(&sql)
        .bind(id)
        .bind(company_id)
        .fetch_optional(&mut *conn)
        .await?
        .ok_or(AppError::NotFound(NOT_FOUND))
}

/// A favorite with its items and remarks.
async fn load(conn: &mut PgConnection, company_id: Uuid, id: Uuid) -> AppResult<Favorite> {
    let h = header(conn, company_id, id, false).await?;
    let items = load_items(conn, id).await?;
    Ok(Favorite {
        id: h.id,
        name: h.name,
        created_by: h.created_by,
        created_at: h.created_at,
        updated_at: h.updated_at,
        items,
    })
}

async fn load_items(conn: &mut PgConnection, favorite_id: Uuid) -> AppResult<Vec<FavoriteItem>> {
    let rows: Vec<ItemRow> = sqlx::query_as(
        "SELECT i.id, i.position, i.parent_position, i.product_id, p.code AS product_code,
                p.name AS product_name, p.unit, p.active AS product_active, i.quantity, i.section,
                i.comment, i.production_remark, i.percent_of_parent, i.percent_base
         FROM sales.favorite_items i
         JOIN products.products p ON p.id = i.product_id
         WHERE i.favorite_id = $1 ORDER BY i.position",
    )
    .bind(favorite_id)
    .fetch_all(&mut *conn)
    .await?;
    let ids: Vec<Uuid> = rows.iter().map(|r| r.id).collect();
    let remarks: Vec<RemarkRow> = sqlx::query_as(
        "SELECT item_id, language::text AS language, text FROM sales.favorite_item_remarks
         WHERE item_id = ANY($1)
         ORDER BY array_position(ARRAY['nl','fr','en','de','es'], language::text)",
    )
    .bind(&ids)
    .fetch_all(&mut *conn)
    .await?;
    let mut by_item: HashMap<Uuid, Vec<FavoriteRemark>> = HashMap::new();
    for r in remarks {
        by_item.entry(r.item_id).or_default().push(FavoriteRemark {
            language: r.language,
            text: r.text,
        });
    }
    Ok(rows
        .into_iter()
        .map(|r| FavoriteItem {
            remarks: by_item.remove(&r.id).unwrap_or_default(),
            id: r.id,
            position: r.position,
            parent_position: r.parent_position,
            product_id: r.product_id,
            product_code: r.product_code,
            product_name: r.product_name,
            unit: r.unit,
            product_active: r.product_active,
            quantity: r.quantity,
            section: r.section,
            comment: r.comment,
            production_remark: r.production_remark,
            percent_of_parent: r.percent_of_parent,
            percent_base: r.percent_base.as_deref().and_then(PercentBase::parse),
        })
        .collect())
}

/// Checks the payload on its own (no database): name, item count, one main item, parents, limits,
/// percentages and remarks. Returns the payload's cleaned remarks per item index.
fn validate(input: &FavoriteInput) -> AppResult<Vec<Vec<FavoriteRemark>>> {
    let name = input.name.trim();
    if name.is_empty() {
        return Err(invalid("name is required".into()));
    }
    if name.chars().count() > MAX_NAME_LEN {
        return Err(invalid(format!(
            "name is longer than {MAX_NAME_LEN} characters"
        )));
    }
    let n = input.items.len();
    if n == 0 {
        return Err(invalid("a favorite needs a main item".into()));
    }
    if n > MAX_ITEMS {
        return Err(invalid(format!(
            "a favorite holds at most {MAX_ITEMS} items"
        )));
    }
    if input
        .items
        .iter()
        .filter(|i| i.parent_position.is_none())
        .count()
        != 1
    {
        return Err(invalid(
            "a favorite has exactly one main item (an item without parent_position)".into(),
        ));
    }
    let mut ids = HashSet::new();
    let mut out = Vec::with_capacity(n);
    for (idx, it) in input.items.iter().enumerate() {
        let pos = idx + 1;
        if let Some(id) = it.id {
            if !ids.insert(id) {
                return Err(invalid(format!("item {pos}: id appears twice")));
            }
        }
        match it.parent_position {
            Some(p) if p < 1 || p as usize >= pos => {
                return Err(invalid(format!(
                    "item {pos}: parent_position must refer to an earlier item"
                )))
            }
            None if pos != 1 => {
                return Err(invalid("the main item must come first".into()));
            }
            _ => {}
        }
        if it.quantity <= Decimal::ZERO || it.quantity > Decimal::from(MAX_QUANTITY) {
            return Err(invalid(format!(
                "item {pos}: quantity must be greater than 0 and at most {MAX_QUANTITY}"
            )));
        }
        if it
            .section
            .as_deref()
            .is_some_and(|s| too_long(s, MAX_SECTION_LEN))
        {
            return Err(invalid(format!(
                "item {pos}: section is longer than {MAX_SECTION_LEN} characters"
            )));
        }
        if it
            .comment
            .as_deref()
            .is_some_and(|s| too_long(s, MAX_REMARK_LEN))
            || too_long(&it.production_remark, MAX_REMARK_LEN)
        {
            return Err(invalid(format!(
                "item {pos}: comment and production_remark are at most {MAX_REMARK_LEN} characters"
            )));
        }
        match it.percent_of_parent {
            Some(_) if it.parent_position.is_none() => {
                return Err(invalid(format!(
                    "item {pos}: percent_of_parent needs a parent_position"
                )))
            }
            Some(p) if p < Decimal::ZERO || p > Decimal::from(1000) => {
                return Err(invalid(format!(
                    "item {pos}: percent_of_parent must be between 0 and 1000"
                )))
            }
            None if it.percent_base.is_some() => {
                return Err(invalid(format!(
                    "item {pos}: percent_base needs percent_of_parent"
                )))
            }
            _ => {}
        }
        let mut remarks: Vec<FavoriteRemark> = Vec::new();
        for r in &it.remarks {
            if !is_language(&r.language) {
                return Err(invalid(format!(
                    "item {pos}: language must be one of {}",
                    LANGUAGES.join(", ")
                )));
            }
            if r.text.trim().is_empty() {
                continue;
            }
            if too_long(&r.text, MAX_REMARK_LEN) {
                return Err(invalid(format!(
                    "item {pos}: a remark is longer than {MAX_REMARK_LEN} characters"
                )));
            }
            if remarks.iter().any(|x| x.language == r.language) {
                return Err(invalid(format!(
                    "item {pos}: language {} appears twice",
                    r.language
                )));
            }
            remarks.push(FavoriteRemark {
                language: r.language.clone(),
                text: r.text.trim().to_string(),
            });
        }
        out.push(remarks);
    }
    Ok(out)
}

/// The products must exist and be active. A product that became inactive stays allowed on an item
/// that already has it, so renaming such a favorite is not blocked.
async fn check_products(
    conn: &mut PgConnection,
    input: &FavoriteInput,
    existing: &HashMap<Uuid, Uuid>,
) -> AppResult<()> {
    let ids: Vec<Uuid> = input.items.iter().map(|i| i.product_id).collect();
    let rows: Vec<(Uuid, String, bool)> =
        sqlx::query_as("SELECT id, code, active FROM products.products WHERE id = ANY($1)")
            .bind(&ids)
            .fetch_all(&mut *conn)
            .await?;
    let found: HashMap<Uuid, (String, bool)> =
        rows.into_iter().map(|(i, c, a)| (i, (c, a))).collect();
    for (idx, it) in input.items.iter().enumerate() {
        let pos = idx + 1;
        match found.get(&it.product_id) {
            None => return Err(invalid(format!("item {pos}: the product does not exist"))),
            Some((code, false))
                if it
                    .id
                    .and_then(|id| existing.get(&id))
                    .is_none_or(|p| *p != it.product_id) =>
            {
                return Err(invalid(format!("item {pos}: product {code} is inactive")))
            }
            _ => {}
        }
    }
    Ok(())
}

async fn check_name(
    conn: &mut PgConnection,
    company_id: Uuid,
    name: &str,
    except: Option<Uuid>,
) -> AppResult<()> {
    let taken: bool = sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM sales.favorites
         WHERE company_id = $1 AND lower(name) = lower($2) AND id IS DISTINCT FROM $3)",
    )
    .bind(company_id)
    .bind(name)
    .bind(except)
    .fetch_one(&mut *conn)
    .await?;
    if taken {
        return Err(AppError::Conflict(format!(
            "a favorite named \"{name}\" already exists"
        )));
    }
    Ok(())
}

/// Writes one item (insert, or update when it exists) and replaces its remarks.
async fn write_item(
    conn: &mut PgConnection,
    favorite_id: Uuid,
    id: Uuid,
    exists: bool,
    position: i32,
    it: &FavoriteItemInput,
    remarks: &[FavoriteRemark],
) -> AppResult<()> {
    let percent = it.percent_of_parent.map(|p| p.round_dp(3));
    let base = percent.map(|_| {
        it.percent_base
            .unwrap_or(PercentBase::ParentListUnitPrice)
            .to_pricing()
            .as_str()
            .to_string()
    });
    let sql = if exists {
        "UPDATE sales.favorite_items SET position = $3, parent_position = $4, product_id = $5,
            quantity = $6, section = $7, comment = $8, production_remark = $9,
            percent_of_parent = $10, percent_base = $11
         WHERE id = $1 AND favorite_id = $2"
    } else {
        "INSERT INTO sales.favorite_items (id, favorite_id, position, parent_position, product_id,
            quantity, section, comment, production_remark, percent_of_parent, percent_base)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)"
    };
    sqlx::query(sql)
        .bind(id)
        .bind(favorite_id)
        .bind(position)
        .bind(it.parent_position)
        .bind(it.product_id)
        .bind(it.quantity.round_dp(4))
        .bind(clean(&it.section))
        .bind(clean(&it.comment))
        .bind(it.production_remark.trim())
        .bind(percent)
        .bind(base)
        .execute(&mut *conn)
        .await?;
    sqlx::query("DELETE FROM sales.favorite_item_remarks WHERE item_id = $1")
        .bind(id)
        .execute(&mut *conn)
        .await?;
    for r in remarks {
        sqlx::query(
            "INSERT INTO sales.favorite_item_remarks (item_id, language, text) VALUES ($1, $2, $3)",
        )
        .bind(id)
        .bind(&r.language)
        .bind(&r.text)
        .execute(&mut *conn)
        .await?;
    }
    Ok(())
}

/// The texts of an item as one comparable value, so the audit trail can say that a text changed
/// without recording it.
type TextSig = (Option<String>, String, Vec<(String, String)>);

fn sig_of_stored(i: &FavoriteItem) -> TextSig {
    (
        i.comment.clone(),
        i.production_remark.clone(),
        i.remarks
            .iter()
            .map(|r| (r.language.clone(), r.text.clone()))
            .collect(),
    )
}

fn sig_of_input(it: &FavoriteItemInput, remarks: &[FavoriteRemark]) -> TextSig {
    let mut r: Vec<(String, String)> = remarks
        .iter()
        .map(|r| (r.language.clone(), r.text.clone()))
        .collect();
    r.sort_by_key(|(l, _)| LANGUAGES.iter().position(|x| *x == l).unwrap_or(99));
    (
        clean(&it.comment),
        it.production_remark.trim().to_string(),
        r,
    )
}

fn has_text(sig: &TextSig) -> bool {
    sig.0.is_some() || !sig.1.is_empty() || !sig.2.is_empty()
}

#[utoipa::path(get, path = "/favorites", tag = "favorites", params(FavoriteListParams),
    responses((status = 200, body = Vec<FavoriteSummary>), (status = 403, body = ErrorBody)))]
async fn list_favorites(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(params): Query<FavoriteListParams>,
) -> AppResult<Json<Vec<FavoriteSummary>>> {
    user.require(Permission::QuotationsRead)?;
    let pattern = search::pattern(params.q.as_deref());
    let sql = format!(
        "SELECT f.id, f.name, m.product_id AS main_product_id, p.code AS main_product_code,
                p.name AS main_product_name, p.active AS main_product_active,
                (SELECT count(*) FROM sales.favorite_items o
                  WHERE o.favorite_id = f.id AND o.parent_position IS NOT NULL) AS option_count,
                COALESCE((SELECT array_agg(DISTINCT r.language::text)
                  FROM sales.favorite_items i
                  JOIN sales.favorite_item_remarks r ON r.item_id = i.id
                  WHERE i.favorite_id = f.id), '{{}}') AS languages,
                f.updated_at
         FROM sales.favorites f
         JOIN sales.favorite_items m ON m.favorite_id = f.id AND m.parent_position IS NULL
         JOIN products.products p ON p.id = m.product_id
         WHERE f.company_id = $1 AND ($2::text IS NULL OR {} OR {} OR {})
         ORDER BY lower(f.name), f.id
         LIMIT $3 OFFSET $4",
        search::matches("f.name", "$2"),
        search::matches("p.code", "$2"),
        search::matches("p.name", "$2"),
    );
    let rows: Vec<SummaryRow> = sqlx::query_as(&sql)
        .bind(user.company_id)
        .bind(pattern)
        .bind(params.limit.unwrap_or(50).clamp(1, 200))
        .bind(params.offset.unwrap_or(0).max(0))
        .fetch_all(&state.db)
        .await?;
    Ok(Json(
        rows.into_iter()
            .map(|r| {
                let mut languages = r.languages;
                languages.sort_by_key(|l| LANGUAGES.iter().position(|x| x == l).unwrap_or(99));
                FavoriteSummary {
                    id: r.id,
                    name: r.name,
                    main_product_id: r.main_product_id,
                    main_product_code: r.main_product_code,
                    main_product_name: r.main_product_name,
                    main_product_active: r.main_product_active,
                    option_count: r.option_count,
                    languages,
                    updated_at: r.updated_at,
                }
            })
            .collect(),
    ))
}

#[utoipa::path(get, path = "/favorites/{id}", tag = "favorites", params(("id" = Uuid, Path)),
    responses((status = 200, body = Favorite), (status = 404, body = ErrorBody)))]
async fn get_favorite(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<Favorite>> {
    user.require(Permission::QuotationsRead)?;
    let mut conn = state.db.acquire().await?;
    Ok(Json(load(&mut conn, user.company_id, id).await?))
}

fn product_ids(items: &[FavoriteItemInput]) -> Vec<Uuid> {
    items.iter().map(|i| i.product_id).collect()
}

#[utoipa::path(post, path = "/favorites", tag = "favorites", request_body = FavoriteInput,
    responses((status = 201, body = Favorite), (status = 403, body = ErrorBody),
        (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn create_favorite(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<FavoriteInput>,
) -> AppResult<(StatusCode, Json<Favorite>)> {
    user.require(Permission::QuotationsWrite)?;
    let remarks = validate(&input)?;
    if input.items.iter().any(|i| i.id.is_some()) {
        return Err(invalid("a new favorite has no item ids".into()));
    }
    let name = input.name.trim().to_string();
    let mut tx = state.db.begin().await?;
    check_name(&mut tx, user.company_id, &name, None).await?;
    check_products(&mut tx, &input, &HashMap::new()).await?;
    let id = new_id();
    sqlx::query(
        "INSERT INTO sales.favorites (id, company_id, name, created_by) VALUES ($1, $2, $3, $4)",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(&name)
    .bind(user.user_id)
    .execute(&mut *tx)
    .await?;
    let mut with_text = false;
    for (idx, it) in input.items.iter().enumerate() {
        with_text |= has_text(&sig_of_input(it, &remarks[idx]));
        write_item(
            &mut tx,
            id,
            new_id(),
            false,
            idx as i32 + 1,
            it,
            &remarks[idx],
        )
        .await?;
    }
    audit::record(
        &mut tx,
        &user,
        "favorite",
        id,
        "created",
        serde_json::json!({
            "name": name,
            "product_ids": product_ids(&input.items),
            "item_count": input.items.len(),
            "text_changed": with_text,
        }),
    )
    .await?;
    let f = load(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(f)))
}

/// Renames the favorite and replaces its content. Items whose `id` is sent keep it (and the lines
/// that point at it); items without an id are new; stored items that are not sent are deleted.
#[utoipa::path(put, path = "/favorites/{id}", tag = "favorites", params(("id" = Uuid, Path)),
    request_body = FavoriteInput,
    responses((status = 200, body = Favorite), (status = 403, body = ErrorBody),
        (status = 404, body = ErrorBody), (status = 409, body = ErrorBody),
        (status = 422, body = ErrorBody)))]
async fn update_favorite(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<FavoriteInput>,
) -> AppResult<Json<Favorite>> {
    user.require(Permission::QuotationsWrite)?;
    let remarks = validate(&input)?;
    let name = input.name.trim().to_string();
    let mut tx = state.db.begin().await?;
    let before_header = header(&mut tx, user.company_id, id, true).await?;
    let before = load_items(&mut tx, id).await?;
    let existing: HashMap<Uuid, Uuid> = before.iter().map(|i| (i.id, i.product_id)).collect();
    for (idx, it) in input.items.iter().enumerate() {
        if it.id.is_some_and(|i| !existing.contains_key(&i)) {
            return Err(invalid(format!(
                "item {}: id is not an item of this favorite",
                idx + 1
            )));
        }
    }
    check_name(&mut tx, user.company_id, &name, Some(id)).await?;
    check_products(&mut tx, &input, &existing).await?;

    let kept: Vec<Uuid> = input.items.iter().filter_map(|i| i.id).collect();
    let removed: Vec<Uuid> = before
        .iter()
        .map(|i| i.id)
        .filter(|i| !kept.contains(i))
        .collect();
    // Lines loaded from a removed item keep working: the foreign key sets their link to NULL.
    sqlx::query("DELETE FROM sales.favorite_items WHERE favorite_id = $1 AND id <> ALL($2)")
        .bind(id)
        .bind(&kept)
        .execute(&mut *tx)
        .await?;
    // Park every kept item under a placeholder parent so that no intermediate state has two main
    // items (positions are unique per favorite only at commit).
    sqlx::query("UPDATE sales.favorite_items SET parent_position = 0 WHERE favorite_id = $1")
        .bind(id)
        .execute(&mut *tx)
        .await?;
    let mut ids: Vec<Uuid> = Vec::with_capacity(input.items.len());
    let mut after_sigs: HashMap<Uuid, TextSig> = HashMap::new();
    for (idx, it) in input.items.iter().enumerate() {
        let item_id = it.id.unwrap_or_else(new_id);
        write_item(
            &mut tx,
            id,
            item_id,
            it.id.is_some(),
            idx as i32 + 1,
            it,
            &remarks[idx],
        )
        .await?;
        after_sigs.insert(item_id, sig_of_input(it, &remarks[idx]));
        ids.push(item_id);
    }
    sqlx::query("UPDATE sales.favorites SET name = $2, updated_at = now() WHERE id = $1")
        .bind(id)
        .bind(&name)
        .execute(&mut *tx)
        .await?;

    let before_sigs: HashMap<Uuid, TextSig> =
        before.iter().map(|i| (i.id, sig_of_stored(i))).collect();
    let text_changed = before_sigs
        .iter()
        .any(|(k, v)| !after_sigs.contains_key(k) && has_text(v))
        || after_sigs
            .iter()
            .any(|(k, v)| before_sigs.get(k).map_or(has_text(v), |b| b != v));
    let added: Vec<Uuid> = ids
        .iter()
        .copied()
        .filter(|i| !existing.contains_key(i))
        .collect();
    audit::record(
        &mut tx,
        &user,
        "favorite",
        id,
        "updated",
        Changes::new()
            .field("name", &before_header.name, &name)
            .into_data_with(serde_json::json!({
                "product_ids": product_ids(&input.items),
                "item_count": input.items.len(),
                "added_items": added,
                "removed_items": removed,
                "text_changed": text_changed,
            })),
    )
    .await?;
    let f = load(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok(Json(f))
}

/// Deletes the favorite. Quotation lines loaded from it stay as they are and lose the link.
#[utoipa::path(delete, path = "/favorites/{id}", tag = "favorites", params(("id" = Uuid, Path)),
    responses((status = 204), (status = 403, body = ErrorBody), (status = 404, body = ErrorBody)))]
async fn delete_favorite(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<StatusCode> {
    user.require(Permission::QuotationsWrite)?;
    let mut tx = state.db.begin().await?;
    let h = header(&mut tx, user.company_id, id, true).await?;
    let products: Vec<Uuid> = sqlx::query_scalar(
        "SELECT product_id FROM sales.favorite_items WHERE favorite_id = $1 ORDER BY position",
    )
    .bind(id)
    .fetch_all(&mut *tx)
    .await?;
    sqlx::query("DELETE FROM sales.favorites WHERE id = $1")
        .bind(id)
        .execute(&mut *tx)
        .await?;
    audit::record(
        &mut tx,
        &user,
        "favorite",
        id,
        "deleted",
        serde_json::json!({ "name": h.name, "product_ids": products }),
    )
    .await?;
    tx.commit().await?;
    Ok(StatusCode::NO_CONTENT)
}

/// Adds the customer remark of an item in one language (the typed translation of a remark that
/// came from a favorite). A language that already has a text answers 409 unless `overwrite`.
#[utoipa::path(put, path = "/favorites/items/{item_id}/remarks/{language}",
    tag = "favorites", params(("item_id" = Uuid, Path), ("language" = String, Path)),
    request_body = FavoriteRemarkInput,
    responses((status = 200, body = Favorite), (status = 403, body = ErrorBody),
        (status = 404, body = ErrorBody), (status = 409, body = ErrorBody),
        (status = 422, body = ErrorBody)))]
async fn put_remark(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((item_id, language)): Path<(Uuid, String)>,
    Json(input): Json<FavoriteRemarkInput>,
) -> AppResult<Json<Favorite>> {
    user.require(Permission::QuotationsWrite)?;
    if !is_language(&language) {
        return Err(invalid(format!(
            "language must be one of {}",
            LANGUAGES.join(", ")
        )));
    }
    let text = input.text.trim();
    if text.is_empty() {
        return Err(invalid("text is required".into()));
    }
    if text.chars().count() > MAX_REMARK_LEN {
        return Err(invalid(format!(
            "text is longer than {MAX_REMARK_LEN} characters"
        )));
    }
    let mut tx = state.db.begin().await?;
    let row: Option<(Uuid, Uuid)> = sqlx::query_as(
        "SELECT i.favorite_id, i.product_id FROM sales.favorite_items i
         JOIN sales.favorites f ON f.id = i.favorite_id
         WHERE i.id = $1 AND f.company_id = $2
         FOR UPDATE OF f",
    )
    .bind(item_id)
    .bind(user.company_id)
    .fetch_optional(&mut *tx)
    .await?;
    let (favorite_id, product_id) = row.ok_or(AppError::NotFound(NOT_FOUND))?;
    let present: bool = sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM sales.favorite_item_remarks WHERE item_id = $1 AND language = $2)",
    )
    .bind(item_id)
    .bind(&language)
    .fetch_one(&mut *tx)
    .await?;
    if present && !input.overwrite {
        return Err(AppError::Conflict(format!(
            "this item already has a remark in {language}; send overwrite=true to replace it"
        )));
    }
    sqlx::query(
        "INSERT INTO sales.favorite_item_remarks (item_id, language, text) VALUES ($1, $2, $3)
         ON CONFLICT (item_id, language) DO UPDATE SET text = EXCLUDED.text",
    )
    .bind(item_id)
    .bind(&language)
    .bind(text)
    .execute(&mut *tx)
    .await?;
    sqlx::query("UPDATE sales.favorites SET updated_at = now() WHERE id = $1")
        .bind(favorite_id)
        .execute(&mut *tx)
        .await?;
    audit::record(
        &mut tx,
        &user,
        "favorite",
        favorite_id,
        if present {
            "remark_replaced"
        } else {
            "remark_added"
        },
        serde_json::json!({
            "item_id": item_id,
            "product_id": product_id,
            "language": language,
            "text_changed": true,
        }),
    )
    .await?;
    let f = load(&mut tx, user.company_id, favorite_id).await?;
    tx.commit().await?;
    Ok(Json(f))
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(list_favorites, create_favorite))
        .routes(routes!(get_favorite, update_favorite, delete_favorite))
        .routes(routes!(put_remark))
}
