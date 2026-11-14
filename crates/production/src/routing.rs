//! The routing of a BOM revision: the operations that build the product, in order, each on a
//! work centre (ADR 0062). It is edited while the BOM revision is a draft and frozen with it; a
//! new revision starts from a copy (`engineering::bom::create_bom`). A production order
//! snapshots it at release.

use std::collections::HashSet;

use axum::extract::{Path, State};
use axum::Json;
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection};
use tradocraft_core::{audit, new_id, AppError, AppResult, AppState, CurrentUser, Permission};
use utoipa::ToSchema;
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

type ErrorBody = tradocraft_core::error::ErrorBody;

/// Most operations one routing may have.
const MAX_OPERATIONS: usize = 100;

/// Longest setup time of one operation: about a year of working days, far beyond any real routing.
const MAX_MINUTES: i32 = 1_000_000;

/// One operation of a routing.
#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct RoutingOperation {
    pub id: Uuid,
    pub position: i32,
    pub name: String,
    pub work_centre_id: Uuid,
    pub work_centre_code: String,
    pub work_centre_name: String,
    /// Minutes once per production order, whatever its quantity.
    pub setup_minutes: i32,
    /// Minutes for each unit built, in the stock unit of the product.
    #[schema(value_type = String, example = "2.5")]
    pub run_minutes_per_unit: Decimal,
    pub notes: String,
}

/// The routing of one BOM revision.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct BomRouting {
    pub bom_id: Uuid,
    pub product_id: Uuid,
    pub bom_revision: i32,
    /// draft | active | obsolete. Only a draft can be changed.
    pub bom_status: String,
    pub operations: Vec<RoutingOperation>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct RoutingOperationInput {
    pub name: String,
    pub work_centre_id: Uuid,
    #[serde(default)]
    pub setup_minutes: i32,
    #[serde(default)]
    #[schema(value_type = String, example = "2.5")]
    pub run_minutes_per_unit: Decimal,
    #[serde(default)]
    pub notes: String,
}

/// Replaces the whole routing of a draft BOM revision. The order of the list is the order of the
/// operations.
#[derive(Debug, Deserialize, ToSchema)]
pub struct BomRoutingInput {
    pub operations: Vec<RoutingOperationInput>,
}

const SELECT: &str =
    "SELECT r.id, r.position, r.name, r.work_centre_id, w.code AS work_centre_code,
        w.name AS work_centre_name, r.setup_minutes, r.run_minutes_per_unit, r.notes
     FROM production.routing_operations r
     JOIN production.work_centres w ON w.id = r.work_centre_id";

/// The operations of a BOM revision for the company, in order. Empty when it has no routing.
pub(crate) async fn load_routing(
    conn: &mut PgConnection,
    company_id: Uuid,
    bom_id: Uuid,
) -> AppResult<Vec<RoutingOperation>> {
    Ok(sqlx::query_as(&format!(
        "{SELECT} WHERE r.company_id = $1 AND r.bom_id = $2 ORDER BY r.position"
    ))
    .bind(company_id)
    .bind(bom_id)
    .fetch_all(conn)
    .await?)
}

#[derive(FromRow)]
struct BomHead {
    product_id: Uuid,
    revision: i32,
    status: String,
}

async fn load_head(conn: &mut PgConnection, bom_id: Uuid, lock: bool) -> AppResult<BomHead> {
    // BOMs are shared master data: no company filter, as in `engineering::bom`.
    sqlx::query_as(&format!(
        "SELECT product_id, revision, status FROM engineering.boms WHERE id = $1{}",
        if lock { " FOR UPDATE" } else { "" }
    ))
    .bind(bom_id)
    .fetch_optional(conn)
    .await?
    .ok_or(AppError::NotFound("BOM"))
}

async fn routing_of(
    conn: &mut PgConnection,
    company_id: Uuid,
    bom_id: Uuid,
    head: BomHead,
) -> AppResult<BomRouting> {
    Ok(BomRouting {
        bom_id,
        product_id: head.product_id,
        bom_revision: head.revision,
        bom_status: head.status,
        operations: load_routing(conn, company_id, bom_id).await?,
    })
}

/// The routing of a BOM revision: empty operations when it has none.
#[utoipa::path(get, path = "/boms/{id}/routing", tag = "production", params(("id" = Uuid, Path)),
    responses((status = 200, body = BomRouting), (status = 404, body = ErrorBody)))]
async fn get_routing(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(bom_id): Path<Uuid>,
) -> AppResult<Json<BomRouting>> {
    user.require(Permission::ProductionRead)?;
    let mut conn = state.db.acquire().await?;
    let head = load_head(&mut conn, bom_id, false).await?;
    Ok(Json(
        routing_of(&mut conn, user.company_id, bom_id, head).await?,
    ))
}

fn check_operations(ops: &[RoutingOperationInput]) -> AppResult<()> {
    if ops.len() > MAX_OPERATIONS {
        return Err(AppError::Validation(format!(
            "a routing has at most {MAX_OPERATIONS} operations"
        )));
    }
    for (i, o) in ops.iter().enumerate() {
        let n = i + 1;
        if o.name.trim().is_empty() {
            return Err(AppError::Validation(format!(
                "operation {n}: a name is required"
            )));
        }
        if !(0..=MAX_MINUTES).contains(&o.setup_minutes) {
            return Err(AppError::Validation(format!(
                "operation {n}: the setup time must be between 0 and {MAX_MINUTES} minutes"
            )));
        }
        if o.run_minutes_per_unit < Decimal::ZERO
            || o.run_minutes_per_unit > Decimal::from(MAX_MINUTES)
            || o.run_minutes_per_unit.round_dp(4) != o.run_minutes_per_unit
        {
            return Err(AppError::Validation(format!(
                "operation {n}: the run time per unit must be between 0 and {MAX_MINUTES} minutes, with at most 4 decimals"
            )));
        }
    }
    Ok(())
}

/// Replaces the routing of a draft BOM revision. Work centres must belong to the company and be
/// active, except ones the routing already uses (deactivating a work centre does not break the
/// routings that have it).
#[utoipa::path(put, path = "/boms/{id}/routing", tag = "production", params(("id" = Uuid, Path)),
    request_body = BomRoutingInput,
    responses((status = 200, body = BomRouting), (status = 404, body = ErrorBody), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn set_routing(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(bom_id): Path<Uuid>,
    Json(input): Json<BomRoutingInput>,
) -> AppResult<Json<BomRouting>> {
    // The routing is part of the BOM (bom.write); production.read keeps it off where the
    // Production module is off.
    user.require(Permission::BomWrite)?;
    user.require(Permission::ProductionRead)?;
    check_operations(&input.operations)?;
    let mut tx = state.db.begin().await?;
    let head = load_head(&mut tx, bom_id, true).await?;
    if head.status != "draft" {
        return Err(AppError::Conflict(format!(
            "revision {} of the BOM is {}; create a new revision to change its routing",
            head.revision, head.status
        )));
    }
    let wanted: Vec<Uuid> = input.operations.iter().map(|o| o.work_centre_id).collect();
    let centres: Vec<(Uuid, bool)> = sqlx::query_as(
        "SELECT id, active FROM production.work_centres WHERE company_id = $1 AND id = ANY($2)",
    )
    .bind(user.company_id)
    .bind(&wanted)
    .fetch_all(&mut *tx)
    .await?;
    let used_now: HashSet<Uuid> = sqlx::query_scalar(
        "SELECT work_centre_id FROM production.routing_operations WHERE company_id = $1 AND bom_id = $2",
    )
    .bind(user.company_id)
    .bind(bom_id)
    .fetch_all(&mut *tx)
    .await?
    .into_iter()
    .collect();
    for (i, o) in input.operations.iter().enumerate() {
        match centres.iter().find(|(id, _)| *id == o.work_centre_id) {
            None => {
                return Err(AppError::Validation(format!(
                    "operation {}: the work centre does not exist",
                    i + 1
                )))
            }
            Some((_, false)) if !used_now.contains(&o.work_centre_id) => {
                return Err(AppError::Validation(format!(
                    "operation {}: the work centre is not active",
                    i + 1
                )))
            }
            Some(_) => {}
        }
    }
    sqlx::query("DELETE FROM production.routing_operations WHERE company_id = $1 AND bom_id = $2")
        .bind(user.company_id)
        .bind(bom_id)
        .execute(&mut *tx)
        .await?;
    for (i, o) in input.operations.iter().enumerate() {
        sqlx::query(
            "INSERT INTO production.routing_operations
                 (id, company_id, bom_id, position, name, work_centre_id, setup_minutes,
                  run_minutes_per_unit, notes)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)",
        )
        .bind(new_id())
        .bind(user.company_id)
        .bind(bom_id)
        .bind(i as i32 + 1)
        .bind(o.name.trim())
        .bind(o.work_centre_id)
        .bind(o.setup_minutes)
        .bind(o.run_minutes_per_unit)
        .bind(o.notes.trim())
        .execute(&mut *tx)
        .await?;
    }
    audit::record(
        &mut tx,
        &user,
        "bom",
        bom_id,
        "routing_updated",
        serde_json::json!({ "revision": head.revision, "operations": input.operations.len() }),
    )
    .await?;
    let out = routing_of(&mut tx, user.company_id, bom_id, head).await?;
    tx.commit().await?;
    Ok(Json(out))
}

/// The routing routes.
pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new().routes(routes!(get_routing, set_routing))
}
