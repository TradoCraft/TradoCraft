//! Stock counts: a snapshot of what is expected, counted quantities, and posting the differences
//! as adjustment moves.

use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::Json;
use chrono::{DateTime, Datelike, NaiveDate, Utc};
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection};
use tradocraft_core::numbering::next_number;
use tradocraft_core::{audit, new_id, AppError, AppResult, AppState, CurrentUser, Permission};
use tradocraft_products::get_product;
use utoipa::{IntoParams, ToSchema};
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::ledger::{get_or_create_lot, lock_balance, post_move, virtual_location, NewMove};

type ErrorBody = tradocraft_core::error::ErrorBody;

#[derive(Debug, Serialize, FromRow, ToSchema)]
pub struct Count {
    pub id: Uuid,
    pub number: String,
    pub warehouse_id: Uuid,
    pub warehouse_code: String,
    pub location_id: Option<Uuid>,
    pub location_code: Option<String>,
    pub product_id: Option<Uuid>,
    /// counting | posted | cancelled
    pub status: String,
    pub note: String,
    pub created_by_name: String,
    pub created_at: DateTime<Utc>,
    pub closed_at: Option<DateTime<Utc>>,
    pub line_count: i64,
    /// Lines with a counted quantity.
    pub counted_count: i64,
}

#[derive(Debug, Serialize, FromRow, ToSchema)]
pub struct CountLine {
    pub id: Uuid,
    pub product_id: Uuid,
    pub product_code: String,
    pub product_name: String,
    pub unit: String,
    pub location_id: Uuid,
    pub location: String,
    pub lot_id: Option<Uuid>,
    pub lot_number: Option<String>,
    /// What the system expected when the count was created.
    #[schema(value_type = String)]
    pub expected_quantity: Decimal,
    #[schema(value_type = Option<String>)]
    pub counted_quantity: Option<Decimal>,
    /// The adjustment posted for this line.
    pub adjustment_move_id: Option<Uuid>,
    /// The stock at the moment the count was posted (the adjustment is counted minus this).
    #[schema(value_type = Option<String>)]
    pub quantity_at_post: Option<Decimal>,
    /// Counted minus expected: what the count found against what the system expected when it
    /// started. Differs from the adjustment when stock moved during the count.
    #[schema(value_type = Option<String>)]
    pub difference_to_expected: Option<Decimal>,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct CountDetail {
    pub count: Count,
    pub lines: Vec<CountLine>,
    /// Posted lines where the stock at posting differed from what was expected when the count
    /// started: movements made during the count, which the count overwrote with what was counted.
    pub moved_during_count: i64,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct CountInput {
    pub warehouse_id: Uuid,
    /// Count only this location.
    pub location_id: Option<Uuid>,
    /// Count only this product.
    pub product_id: Option<Uuid>,
    #[serde(default)]
    pub note: String,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct CountEntry {
    /// An existing line...
    pub line_id: Option<Uuid>,
    /// ...or stock that was not expected: product, location and lot.
    pub product_id: Option<Uuid>,
    pub location_id: Option<Uuid>,
    pub lot_id: Option<Uuid>,
    pub lot_number: Option<String>,
    #[serde(default, deserialize_with = "tradocraft_core::serde_util::opt_date")]
    pub expiry_date: Option<NaiveDate>,
    /// The counted quantity; null clears it (the line is left alone when posting).
    #[schema(value_type = Option<String>, example = "12")]
    pub counted_quantity: Option<Decimal>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct CountEntries {
    pub entries: Vec<CountEntry>,
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct CountParams {
    /// counting | posted | cancelled
    pub status: Option<String>,
    pub warehouse_id: Option<Uuid>,
    /// Part of the count number or of the warehouse code.
    pub q: Option<String>,
    /// Page size (default 50, at most 200).
    pub limit: Option<i64>,
    /// Rows to skip, newest first.
    pub offset: Option<i64>,
}

const SELECT_COUNT: &str = "SELECT c.id, c.number, c.warehouse_id, w.code AS warehouse_code, c.location_id,
        l.code AS location_code, c.product_id, c.status, c.note, u.display_name AS created_by_name, c.created_at,
        c.closed_at,
        (SELECT count(*) FROM inventory.count_lines x WHERE x.count_id = c.id) AS line_count,
        (SELECT count(*) FROM inventory.count_lines x WHERE x.count_id = c.id AND x.counted_quantity IS NOT NULL) AS counted_count
     FROM inventory.counts c
     JOIN inventory.warehouses w ON w.id = c.warehouse_id
     LEFT JOIN inventory.locations l ON l.id = c.location_id
     JOIN core.users u ON u.id = c.created_by";

async fn load_count(conn: &mut PgConnection, company_id: Uuid, id: Uuid) -> AppResult<Count> {
    sqlx::query_as(sqlx::AssertSqlSafe(format!(
        "{SELECT_COUNT} WHERE c.id = $1 AND c.company_id = $2"
    )))
    .bind(id)
    .bind(company_id)
    .fetch_optional(conn)
    .await?
    .ok_or(AppError::NotFound("count"))
}

async fn detail(conn: &mut PgConnection, company_id: Uuid, id: Uuid) -> AppResult<CountDetail> {
    let count = load_count(conn, company_id, id).await?;
    let lines: Vec<CountLine> = sqlx::query_as(
        "SELECT cl.id, cl.product_id, p.code AS product_code, p.name AS product_name, p.unit, cl.location_id,
                w.code || '/' || l.code AS location, cl.lot_id, lot.lot_number, cl.expected_quantity,
                cl.counted_quantity, cl.adjustment_move_id, cl.quantity_at_post,
                CASE WHEN cl.counted_quantity IS NULL THEN NULL ELSE cl.counted_quantity - cl.expected_quantity END
                    AS difference_to_expected
         FROM inventory.count_lines cl
         JOIN products.products p ON p.id = cl.product_id
         JOIN inventory.locations l ON l.id = cl.location_id
         JOIN inventory.warehouses w ON w.id = l.warehouse_id
         LEFT JOIN inventory.lots lot ON lot.id = cl.lot_id
         WHERE cl.count_id = $1 AND cl.company_id = $2
         ORDER BY w.code, l.code, p.code, lot.lot_number NULLS FIRST",
    )
    .bind(id)
    .bind(company_id)
    .fetch_all(conn)
    .await?;
    let moved_during_count = lines
        .iter()
        .filter(|l| l.quantity_at_post.is_some_and(|q| q != l.expected_quantity))
        .count() as i64;
    Ok(CountDetail {
        count,
        lines,
        moved_during_count,
    })
}

/// A page of counts, newest first, with the number of counts that match.
#[derive(Debug, Serialize, ToSchema)]
pub struct CountPage {
    pub items: Vec<Count>,
    pub total: i64,
}

#[utoipa::path(get, path = "/inventory/counts", tag = "inventory", params(CountParams),
    responses((status = 200, body = CountPage)))]
async fn list_counts(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(p): Query<CountParams>,
) -> AppResult<Json<CountPage>> {
    user.require(Permission::InventoryRead)?;
    let filter = "WHERE c.company_id = $1 AND ($2::text IS NULL OR c.status = $2)
             AND ($3::uuid IS NULL OR c.warehouse_id = $3)
             AND ($4::text IS NULL OR strpos(lower(c.number), lower($4)) > 0
                  OR strpos(lower(w.code), lower($4)) > 0)";
    let needle = p.q.as_deref().map(str::trim).filter(|q| !q.is_empty());
    let items = sqlx::query_as(sqlx::AssertSqlSafe(format!(
        "{SELECT_COUNT} {filter} ORDER BY c.created_at DESC, c.id DESC LIMIT $5 OFFSET $6"
    )))
    .bind(user.company_id)
    .bind(&p.status)
    .bind(p.warehouse_id)
    .bind(needle)
    .bind(p.limit.unwrap_or(50).clamp(1, 200))
    .bind(p.offset.unwrap_or(0).max(0))
    .fetch_all(&state.db)
    .await?;
    let total = sqlx::query_scalar(sqlx::AssertSqlSafe(format!(
        "SELECT count(*) FROM inventory.counts c JOIN inventory.warehouses w ON w.id = c.warehouse_id {filter}"
    )))
    .bind(user.company_id)
    .bind(&p.status)
    .bind(p.warehouse_id)
    .bind(needle)
    .fetch_one(&state.db)
    .await?;
    Ok(Json(CountPage { items, total }))
}

#[utoipa::path(get, path = "/inventory/counts/{id}", tag = "inventory", params(("id" = Uuid, Path)),
    responses((status = 200, body = CountDetail), (status = 404, body = ErrorBody)))]
async fn get_count(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<CountDetail>> {
    user.require(Permission::InventoryRead)?;
    let mut conn = state.db.acquire().await?;
    Ok(Json(detail(&mut conn, user.company_id, id).await?))
}

/// Starts a count of a warehouse (or a location, or a product in it) and snapshots what the system
/// expects. Serial-tracked products are not counted.
#[utoipa::path(post, path = "/inventory/counts", tag = "inventory", request_body = CountInput,
    responses((status = 201, body = CountDetail), (status = 404, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn create_count(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<CountInput>,
) -> AppResult<(StatusCode, Json<CountDetail>)> {
    user.require(Permission::InventoryWrite)?;
    let mut tx = state.db.begin().await?;
    let wh_ok: bool = sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM inventory.warehouses WHERE id = $1 AND company_id = $2 AND active)",
    )
    .bind(input.warehouse_id)
    .bind(user.company_id)
    .fetch_one(&mut *tx)
    .await?;
    if !wh_ok {
        return Err(AppError::NotFound("warehouse"));
    }
    if let Some(loc) = input.location_id {
        let ok: bool = sqlx::query_scalar(
            "SELECT EXISTS (SELECT 1 FROM inventory.locations WHERE id = $1 AND company_id = $2 AND warehouse_id = $3)",
        )
        .bind(loc)
        .bind(user.company_id)
        .bind(input.warehouse_id)
        .fetch_one(&mut *tx)
        .await?;
        if !ok {
            return Err(AppError::Validation(
                "the location is not in this warehouse".into(),
            ));
        }
    }
    if let Some(pid) = input.product_id {
        let p = get_product(&mut *tx, pid).await?;
        if p.tracking == "serial" {
            return Err(AppError::Validation(
                "serial-tracked products are not counted".into(),
            ));
        }
    }
    let id = new_id();
    let year = tradocraft_core::today().year();
    let n = next_number(&mut tx, user.company_id, "CNT", year).await?;
    let number = format!("CNT-{year}-{n:05}");
    sqlx::query(
        "INSERT INTO inventory.counts (id, company_id, number, warehouse_id, location_id, product_id, note, created_by)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(&number)
    .bind(input.warehouse_id)
    .bind(input.location_id)
    .bind(input.product_id)
    .bind(input.note.trim())
    .bind(user.user_id)
    .execute(&mut *tx)
    .await?;
    sqlx::query(
        "INSERT INTO inventory.count_lines (id, company_id, count_id, product_id, location_id, lot_id, expected_quantity)
         SELECT gen_random_uuid(), $1, $2, b.product_id, b.location_id, b.lot_id, b.quantity
         FROM inventory.stock_balances b
         JOIN inventory.locations l ON l.id = b.location_id AND l.kind = 'internal'
         JOIN products.products p ON p.id = b.product_id AND p.tracking <> 'serial'
         WHERE b.company_id = $1 AND l.warehouse_id = $3 AND ($4::uuid IS NULL OR l.id = $4)
           AND ($5::uuid IS NULL OR b.product_id = $5) AND b.quantity > 0",
    )
    .bind(user.company_id)
    .bind(id)
    .bind(input.warehouse_id)
    .bind(input.location_id)
    .bind(input.product_id)
    .execute(&mut *tx)
    .await?;
    audit::record(
        &mut tx,
        &user,
        "stock_count",
        id,
        "created",
        serde_json::json!({ "number": number }),
    )
    .await?;
    let d = detail(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(d)))
}

async fn lock_open(conn: &mut PgConnection, company_id: Uuid, id: Uuid) -> AppResult<Count> {
    sqlx::query("SELECT id FROM inventory.counts WHERE id = $1 AND company_id = $2 FOR UPDATE")
        .bind(id)
        .bind(company_id)
        .fetch_optional(&mut *conn)
        .await?
        .ok_or(AppError::NotFound("count"))?;
    let c = load_count(conn, company_id, id).await?;
    if c.status != "counting" {
        return Err(AppError::Conflict(format!(
            "count {} is {}",
            c.number, c.status
        )));
    }
    Ok(c)
}

/// Enters counted quantities, and adds lines for stock that was not expected.
#[utoipa::path(put, path = "/inventory/counts/{id}/lines", tag = "inventory", params(("id" = Uuid, Path)),
    request_body = CountEntries,
    responses((status = 200, body = CountDetail), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn enter_counts(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<CountEntries>,
) -> AppResult<Json<CountDetail>> {
    user.require(Permission::InventoryWrite)?;
    let mut tx = state.db.begin().await?;
    let count = lock_open(&mut tx, user.company_id, id).await?;
    for e in &input.entries {
        if let Some(q) = e.counted_quantity {
            if q < Decimal::ZERO || q.round_dp(4) != q {
                return Err(AppError::Validation(
                    "counted_quantity must be 0 or more, with at most 4 decimals".into(),
                ));
            }
        }
        if let Some(line_id) = e.line_id {
            let n = sqlx::query(
                "UPDATE inventory.count_lines SET counted_quantity = $3 WHERE id = $1 AND count_id = $2",
            )
            .bind(line_id)
            .bind(id)
            .bind(e.counted_quantity)
            .execute(&mut *tx)
            .await?;
            if n.rows_affected() == 0 {
                return Err(AppError::NotFound("count line"));
            }
            continue;
        }
        let (product_id, location_id) = match (e.product_id, e.location_id) {
            (Some(p), Some(l)) => (p, l),
            _ => {
                return Err(AppError::Validation(
                    "give line_id, or product_id and location_id".into(),
                ))
            }
        };
        let product = get_product(&mut *tx, product_id).await?;
        if product.tracking == "serial" || product.product_type == "service" {
            return Err(AppError::Validation(format!(
                "{} cannot be counted",
                product.code
            )));
        }
        if count.product_id.is_some_and(|p| p != product_id) {
            return Err(AppError::Validation(
                "this count is for one product only".into(),
            ));
        }
        let in_scope: bool = sqlx::query_scalar(
            "SELECT EXISTS (SELECT 1 FROM inventory.locations WHERE id = $1 AND company_id = $2 AND kind = 'internal'
                            AND warehouse_id = $3 AND ($4::uuid IS NULL OR id = $4))",
        )
        .bind(location_id)
        .bind(user.company_id)
        .bind(count.warehouse_id)
        .bind(count.location_id)
        .fetch_one(&mut *tx)
        .await?;
        if !in_scope {
            return Err(AppError::Validation(
                "the location is not part of this count".into(),
            ));
        }
        let lot_id = match (product.tracking.as_str(), e.lot_id, e.lot_number.as_deref()) {
            ("lot", Some(l), _) => {
                // A lot id from the request must be a lot of this product in this company, for
                // zero counts as well: otherwise its number would be exposed in the count.
                let ok: bool = sqlx::query_scalar(
                    "SELECT EXISTS (SELECT 1 FROM inventory.lots
                                    WHERE id = $1 AND company_id = $2 AND product_id = $3)",
                )
                .bind(l)
                .bind(user.company_id)
                .bind(product_id)
                .fetch_one(&mut *tx)
                .await?;
                if !ok {
                    return Err(AppError::NotFound("lot"));
                }
                Some(l)
            }
            ("lot", None, Some(n)) => Some(
                get_or_create_lot(&mut tx, user.company_id, product_id, n, e.expiry_date).await?,
            ),
            ("lot", None, None) => {
                return Err(AppError::Validation(format!(
                    "{} needs a lot",
                    product.code
                )))
            }
            _ => None,
        };
        let expected: Decimal = sqlx::query_scalar(
            "SELECT quantity FROM inventory.stock_balances
             WHERE company_id = $1 AND product_id = $2 AND location_id = $3 AND lot_id IS NOT DISTINCT FROM $4",
        )
        .bind(user.company_id)
        .bind(product_id)
        .bind(location_id)
        .bind(lot_id)
        .fetch_optional(&mut *tx)
        .await?
        .unwrap_or(Decimal::ZERO);
        sqlx::query(
            "INSERT INTO inventory.count_lines (id, company_id, count_id, product_id, location_id, lot_id, expected_quantity, counted_quantity)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
             ON CONFLICT (count_id, product_id, location_id, (COALESCE(lot_id, '00000000-0000-0000-0000-000000000000'::uuid)))
             DO UPDATE SET counted_quantity = EXCLUDED.counted_quantity",
        )
        .bind(new_id())
        .bind(user.company_id)
        .bind(id)
        .bind(product_id)
        .bind(location_id)
        .bind(lot_id)
        .bind(expected)
        .bind(e.counted_quantity)
        .execute(&mut *tx)
        .await?;
    }
    let d = detail(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok(Json(d))
}

/// Posts the count: one adjustment move for every counted line whose quantity differs from the
/// stock at this moment. Lines without a counted quantity are left alone.
#[utoipa::path(post, path = "/inventory/counts/{id}/post", tag = "inventory", params(("id" = Uuid, Path)),
    responses((status = 200, body = CountDetail), (status = 409, body = ErrorBody)))]
async fn post_count(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<CountDetail>> {
    user.require(Permission::InventoryAdmin)?;
    let mut tx = state.db.begin().await?;
    let count = lock_open(&mut tx, user.company_id, id).await?;
    let lines: Vec<(Uuid, Uuid, Uuid, Option<Uuid>, Decimal)> = sqlx::query_as(
        "SELECT id, product_id, location_id, lot_id, counted_quantity FROM inventory.count_lines
         WHERE company_id = $2 AND count_id = $1 AND counted_quantity IS NOT NULL ORDER BY id",
    )
    .bind(id)
    .bind(user.company_id)
    .fetch_all(&mut *tx)
    .await?;
    let adj = virtual_location(&mut tx, user.company_id, "adjustment").await?;
    let mut posted = 0;
    for (line_id, product_id, location_id, lot_id, counted) in lines {
        // Lock the place (creating its balance row when there is none) before reading it.
        let have = lock_balance(&mut tx, user.company_id, product_id, location_id, lot_id).await?;
        sqlx::query("UPDATE inventory.count_lines SET quantity_at_post = $2 WHERE id = $1")
            .bind(line_id)
            .bind(have)
            .execute(&mut *tx)
            .await?;
        let delta = counted - have;
        if delta.is_zero() {
            continue;
        }
        let (from, to) = if delta > Decimal::ZERO {
            (adj, location_id)
        } else {
            (location_id, adj)
        };
        let mut m = NewMove::new(
            new_id(),
            &user,
            product_id,
            delta.abs(),
            from,
            to,
            "adjustment",
            "count",
        );
        m.lot_id = lot_id;
        m.reference = Some(("stock_count".into(), id));
        m.note = count.number.clone();
        let mv = post_move(&mut tx, &m).await?.into_move();
        sqlx::query("UPDATE inventory.count_lines SET adjustment_move_id = $2 WHERE id = $1")
            .bind(line_id)
            .bind(mv.id)
            .execute(&mut *tx)
            .await?;
        posted += 1;
    }
    sqlx::query("UPDATE inventory.counts SET status = 'posted', closed_by = $2, closed_at = now() WHERE id = $1")
        .bind(id)
        .bind(user.user_id)
        .execute(&mut *tx)
        .await?;
    audit::record(
        &mut tx,
        &user,
        "stock_count",
        id,
        "posted",
        serde_json::json!({ "adjustments": posted }),
    )
    .await?;
    let d = detail(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok(Json(d))
}

#[utoipa::path(post, path = "/inventory/counts/{id}/cancel", tag = "inventory", params(("id" = Uuid, Path)),
    responses((status = 200, body = CountDetail), (status = 409, body = ErrorBody)))]
async fn cancel_count(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<CountDetail>> {
    user.require(Permission::InventoryWrite)?;
    let mut tx = state.db.begin().await?;
    lock_open(&mut tx, user.company_id, id).await?;
    sqlx::query("UPDATE inventory.counts SET status = 'cancelled', closed_by = $2, closed_at = now() WHERE id = $1")
        .bind(id)
        .bind(user.user_id)
        .execute(&mut *tx)
        .await?;
    audit::record(
        &mut tx,
        &user,
        "stock_count",
        id,
        "cancelled",
        serde_json::json!({}),
    )
    .await?;
    let d = detail(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok(Json(d))
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(list_counts, create_count))
        .routes(routes!(get_count))
        .routes(routes!(enter_counts))
        .routes(routes!(post_count))
        .routes(routes!(cancel_count))
}
