//! The API of the material requirements planning (ADR 0091): run the planning, read the proposals
//! and turn one into a purchase order or a production order, or dismiss it.
//!
//! No permission of its own: running and dismissing are for those who may write production (and
//! purchasing, for a purchase proposal); reading is for those who may read either.

use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::Json;
use chrono::{DateTime, NaiveDate, Utc};
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection};
use tradocraft_core::{audit, AppError, AppResult, AppState, CurrentUser, Permission};
use utoipa::{IntoParams, ToSchema};
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::run::{run, DEFAULT_HORIZON_DAYS, MAX_HORIZON_DAYS};

type ErrorBody = tradocraft_core::error::ErrorBody;

/// A planning run.
#[derive(Debug, Serialize, FromRow, ToSchema)]
pub struct MrpRun {
    pub id: Uuid,
    pub number: String,
    /// The day the plan started from.
    pub planned_on: NaiveDate,
    pub horizon_days: i32,
    /// How many proposals it made.
    pub proposals: i32,
    pub created_at: DateTime<Utc>,
}

/// A proposal to buy or build.
#[derive(Debug, Serialize, FromRow, ToSchema)]
pub struct MrpProposal {
    pub id: Uuid,
    pub run_id: Uuid,
    pub run_number: String,
    pub product_id: Uuid,
    pub product_code: String,
    pub product_name: String,
    /// `purchase` or `production`.
    pub kind: String,
    #[schema(value_type = String)]
    pub quantity: Decimal,
    /// When the stock is needed.
    pub need_date: NaiveDate,
    /// When to order, or to start the build.
    pub order_date: NaiveDate,
    /// The lead time reaches past the need date: the goods will be late.
    pub late: bool,
    pub supplier_id: Option<Uuid>,
    pub supplier_name: Option<String>,
    /// `demand` (a requirement is not covered) or `safety_stock`.
    pub reason: String,
    /// What the quantity is for: `[{kind, id, number, quantity}]`, kind `sales_order`,
    /// `production_order`, `purchase_order` or `planned` (a component of a proposed build).
    #[schema(value_type = Object)]
    pub pegging: serde_json::Value,
    /// `open`, `converted`, `dismissed` or `superseded` (a later run replaced it).
    pub status: String,
    /// The purchase order or production order made from it.
    pub converted_to: Option<Uuid>,
    pub converted_at: Option<DateTime<Utc>>,
}

const SELECT_PROPOSAL: &str = "SELECT p.id, p.run_id, r.number AS run_number, p.product_id,
        pr.code AS product_code, pr.name AS product_name, p.kind, p.quantity, p.need_date,
        p.order_date, p.late, p.supplier_id, s.name AS supplier_name, p.reason, p.pegging,
        p.status, p.converted_to, p.converted_at
    FROM mrp.proposals p
    JOIN mrp.runs r ON r.id = p.run_id
    JOIN products.products pr ON pr.id = p.product_id
    LEFT JOIN purchasing.suppliers s ON s.id = p.supplier_id";

/// Who may see proposals: the kinds they may read. Production sees what is built, purchasing what
/// is bought.
fn readable_kinds(user: &CurrentUser) -> AppResult<Vec<String>> {
    let mut kinds = Vec::new();
    if user.can(Permission::PurchasingRead) {
        kinds.push("purchase".to_string());
    }
    if user.can(Permission::ProductionRead) {
        kinds.push("production".to_string());
    }
    if kinds.is_empty() {
        user.require(Permission::ProductionRead)?;
    }
    Ok(kinds)
}

#[derive(Debug, Default, Deserialize, ToSchema)]
pub struct MrpRunInput {
    /// How many days ahead to plan; default 90, at most 730.
    pub horizon_days: Option<i32>,
}

/// Plans the requirements of the company: what customers wait for and what production uses, against
/// stock and what is on order, and proposes what to buy or build. The open proposals of earlier runs
/// are replaced. Nothing is ordered until a proposal is converted.
#[utoipa::path(post, path = "/mrp/runs", tag = "mrp", request_body = MrpRunInput,
    responses((status = 201, body = MrpRun), (status = 403, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn start_run(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<MrpRunInput>,
) -> AppResult<(StatusCode, Json<MrpRun>)> {
    user.require(Permission::ProductionWrite)?;
    let mut tx = state.db.begin().await?;
    let outcome = run(
        &mut tx,
        &user,
        input.horizon_days.unwrap_or(DEFAULT_HORIZON_DAYS),
    )
    .await?;
    let out = load_run(&mut tx, user.company_id, outcome.id).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(out)))
}

async fn load_run(conn: &mut PgConnection, company: Uuid, id: Uuid) -> AppResult<MrpRun> {
    sqlx::query_as(
        "SELECT id, number, planned_on, horizon_days, proposals, created_at
         FROM mrp.runs WHERE id = $1 AND company_id = $2",
    )
    .bind(id)
    .bind(company)
    .fetch_optional(conn)
    .await?
    .ok_or(AppError::NotFound("run"))
}

/// The latest runs, newest first (at most 20).
#[utoipa::path(get, path = "/mrp/runs", tag = "mrp",
    responses((status = 200, body = Vec<MrpRun>), (status = 403, body = ErrorBody)))]
async fn list_runs(
    State(state): State<AppState>,
    user: CurrentUser,
) -> AppResult<Json<Vec<MrpRun>>> {
    readable_kinds(&user)?;
    Ok(Json(
        sqlx::query_as(
            "SELECT id, number, planned_on, horizon_days, proposals, created_at
             FROM mrp.runs WHERE company_id = $1 ORDER BY created_at DESC LIMIT 20",
        )
        .bind(user.company_id)
        .fetch_all(&state.db)
        .await?,
    ))
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct ProposalParams {
    /// `open` (default), `converted`, `dismissed`, `superseded` or `all`.
    pub status: Option<String>,
    /// `purchase` or `production`.
    pub kind: Option<String>,
    pub product_id: Option<Uuid>,
    pub run_id: Option<Uuid>,
}

/// The proposals, by the day to order. What the user may not read (production or purchasing) is
/// left out.
#[utoipa::path(get, path = "/mrp/proposals", tag = "mrp", params(ProposalParams),
    responses((status = 200, body = Vec<MrpProposal>), (status = 403, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn list_proposals(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(p): Query<ProposalParams>,
) -> AppResult<Json<Vec<MrpProposal>>> {
    let kinds = readable_kinds(&user)?;
    let status = match p.status.as_deref().unwrap_or("open") {
        "all" => None,
        s @ ("open" | "converted" | "dismissed" | "superseded") => Some(s.to_string()),
        other => {
            return Err(AppError::Validation(format!("unknown status {other}")));
        }
    };
    if let Some(k) = p.kind.as_deref() {
        if !matches!(k, "purchase" | "production") {
            return Err(AppError::Validation(format!("unknown kind {k}")));
        }
    }
    Ok(Json(
        sqlx::query_as(sqlx::AssertSqlSafe(format!(
            "{SELECT_PROPOSAL}
             WHERE p.company_id = $1 AND ($2::text IS NULL OR p.status = $2)
               AND ($3::text IS NULL OR p.kind = $3) AND ($4::uuid IS NULL OR p.product_id = $4)
               AND ($5::uuid IS NULL OR p.run_id = $5) AND p.kind = ANY($6)
             ORDER BY p.order_date, p.need_date, pr.code LIMIT 500"
        )))
        .bind(user.company_id)
        .bind(status)
        .bind(p.kind)
        .bind(p.product_id)
        .bind(p.run_id)
        .bind(kinds)
        .fetch_all(&state.db)
        .await?,
    ))
}

async fn load_proposal(conn: &mut PgConnection, company: Uuid, id: Uuid) -> AppResult<MrpProposal> {
    sqlx::query_as(sqlx::AssertSqlSafe(format!(
        "{SELECT_PROPOSAL} WHERE p.id = $1 AND p.company_id = $2"
    )))
    .bind(id)
    .bind(company)
    .fetch_optional(conn)
    .await?
    .ok_or(AppError::NotFound("proposal"))
}

#[derive(FromRow)]
struct Locked {
    kind: String,
    product_id: Uuid,
    quantity: Decimal,
    need_date: NaiveDate,
    order_date: NaiveDate,
    supplier_id: Option<Uuid>,
    status: String,
    run_number: String,
}

/// Locks an open proposal and checks who may act on it: a purchase proposal needs purchasing
/// rights, a production proposal production rights.
async fn lock_open(conn: &mut PgConnection, user: &CurrentUser, id: Uuid) -> AppResult<Locked> {
    let p: Locked = sqlx::query_as(
        "SELECT p.kind, p.product_id, p.quantity, p.need_date, p.order_date, p.supplier_id,
                p.status, r.number AS run_number
         FROM mrp.proposals p JOIN mrp.runs r ON r.id = p.run_id
         WHERE p.id = $1 AND p.company_id = $2 FOR UPDATE OF p",
    )
    .bind(id)
    .bind(user.company_id)
    .fetch_optional(&mut *conn)
    .await?
    .ok_or(AppError::NotFound("proposal"))?;
    user.require(if p.kind == "purchase" {
        Permission::PurchasingWrite
    } else {
        Permission::ProductionWrite
    })?;
    if p.status != "open" {
        return Err(AppError::Conflict(format!(
            "the proposal is {}; only an open proposal can be acted on",
            p.status
        )));
    }
    Ok(p)
}

#[derive(Debug, Default, Deserialize, ToSchema)]
pub struct MrpConvertInput {
    /// For a purchase: the supplier, when the proposal has none (the product has no preferred one).
    pub supplier_id: Option<Uuid>,
    /// For a production order: the division that builds it; defaults to the one that normally does.
    pub division_id: Option<Uuid>,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct MrpConversion {
    pub proposal: MrpProposal,
    /// The purchase order (draft) or the production order made.
    pub converted_to: Uuid,
    /// Its number.
    pub number: String,
}

/// Turns an open proposal into a draft purchase order (for the supplier of the proposal, at the
/// price of its supplier product, or the standard cost) or a released production order (for stock,
/// ready on the need date). Nothing is approved or sent.
#[utoipa::path(post, path = "/mrp/proposals/{id}/convert", tag = "mrp", params(("id" = Uuid, Path)),
    request_body = MrpConvertInput,
    responses((status = 200, body = MrpConversion), (status = 403, body = ErrorBody), (status = 404, body = ErrorBody),
        (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn convert_proposal(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<MrpConvertInput>,
) -> AppResult<Json<MrpConversion>> {
    let mut tx = state.db.begin().await?;
    let p = lock_open(&mut tx, &user, id).await?;
    let note = format!("From the planning run {}", p.run_number);
    let (to, number) = if p.kind == "purchase" {
        let supplier = input.supplier_id.or(p.supplier_id).ok_or_else(|| {
            AppError::Validation("the product has no preferred supplier: choose one".into())
        })?;
        let price: Option<(Decimal, String)> = sqlx::query_as(
            "SELECT unit_price, supplier_product_code FROM purchasing.supplier_products
             WHERE company_id = $1 AND supplier_id = $2 AND product_id = $3",
        )
        .bind(user.company_id)
        .bind(supplier)
        .bind(p.product_id)
        .fetch_optional(&mut *tx)
        .await?;
        let unit_price = match &price {
            Some((price, _)) => *price,
            None => sqlx::query_scalar::<_, Option<Decimal>>(
                "SELECT standard_cost FROM products.products WHERE id = $1",
            )
            .bind(p.product_id)
            .fetch_one(&mut *tx)
            .await?
            .unwrap_or(Decimal::ZERO),
        };
        let po = tradocraft_purchasing::orders::create(
            &mut tx,
            &user,
            tradocraft_purchasing::orders::NewPurchaseOrderInput {
                supplier_id: supplier,
                order_date: Some(tradocraft_core::today()),
                expected_delivery_date: Some(p.need_date),
                currency: None,
                notes: Some(note),
                lines: vec![tradocraft_purchasing::orders::NewPoLineInput {
                    product_id: p.product_id,
                    supplier_product_code: price.map(|(_, c)| c).filter(|c| !c.is_empty()),
                    description: None,
                    quantity: p.quantity,
                    unit_price,
                    vat_rate: None,
                }],
            },
        )
        .await?;
        (po.summary.id, po.summary.number)
    } else {
        tradocraft_production::orders::release_for_stock(
            &mut tx,
            &user,
            p.product_id,
            p.quantity,
            input.division_id,
            Some(p.need_date),
            Some(p.order_date),
            note,
        )
        .await?
    };
    sqlx::query(
        "UPDATE mrp.proposals SET status = 'converted', converted_to = $2, converted_at = now(),
                converted_by = $3 WHERE id = $1",
    )
    .bind(id)
    .bind(to)
    .bind(user.user_id)
    .execute(&mut *tx)
    .await?;
    audit::record(
        &mut tx,
        &user,
        "mrp_proposal",
        id,
        "converted",
        serde_json::json!({ "kind": p.kind, "to": to, "number": number }),
    )
    .await?;
    let proposal = load_proposal(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok(Json(MrpConversion {
        proposal,
        converted_to: to,
        number,
    }))
}

/// Dismisses an open proposal: it stays in the list of dismissed ones and is not proposed again
/// by itself (a later run looks at the requirements afresh).
#[utoipa::path(post, path = "/mrp/proposals/{id}/dismiss", tag = "mrp", params(("id" = Uuid, Path)),
    responses((status = 200, body = MrpProposal), (status = 403, body = ErrorBody), (status = 404, body = ErrorBody),
        (status = 409, body = ErrorBody)))]
async fn dismiss_proposal(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<MrpProposal>> {
    let mut tx = state.db.begin().await?;
    let p = lock_open(&mut tx, &user, id).await?;
    sqlx::query("UPDATE mrp.proposals SET status = 'dismissed' WHERE id = $1")
        .bind(id)
        .execute(&mut *tx)
        .await?;
    audit::record(
        &mut tx,
        &user,
        "mrp_proposal",
        id,
        "dismissed",
        serde_json::json!({ "kind": p.kind, "product_id": p.product_id }),
    )
    .await?;
    let out = load_proposal(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok(Json(out))
}

/// The routes of the planning.
pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(start_run, list_runs))
        .routes(routes!(list_proposals))
        .routes(routes!(convert_proposal))
        .routes(routes!(dismiss_proposal))
}

/// The longest horizon, for the documentation of the input.
pub const _MAX_HORIZON_DAYS: i32 = MAX_HORIZON_DAYS;
