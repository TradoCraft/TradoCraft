//! BOM revisions: draft → active → obsolete. Only drafts can be edited.

use std::collections::HashMap;

use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::Json;
use chrono::{DateTime, Utc};
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection, PgExecutor};
use tradocraft_core::{audit, new_id, AppError, AppResult, AppState, CurrentUser, Permission};
use tradocraft_products::get_product;
use utoipa::{IntoParams, ToSchema};
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::explode::{self, Cycle, LineSpec, Structure};

type ErrorBody = tradocraft_core::error::ErrorBody;

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct BomSummary {
    pub id: Uuid,
    pub product_id: Uuid,
    pub revision: i32,
    /// draft | active | obsolete
    pub status: String,
    pub line_count: i64,
    pub notes: String,
    pub created_at: DateTime<Utc>,
    pub activated_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct BomLine {
    pub position: i32,
    pub component_product_id: Uuid,
    pub component_code: String,
    pub component_name: String,
    pub component_unit: String,
    pub component_type: String,
    pub component_tracking: String,
    /// True if the component has an active BOM itself (a subassembly).
    pub component_has_bom: bool,
    #[schema(value_type = String)]
    pub quantity: Decimal,
    #[schema(value_type = String)]
    pub scrap_percent: Decimal,
    pub notes: String,
}

#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct Bom {
    pub id: Uuid,
    pub product_id: Uuid,
    pub product_code: String,
    pub product_name: String,
    pub revision: i32,
    /// draft | active | obsolete
    pub status: String,
    pub notes: String,
    pub created_at: DateTime<Utc>,
    pub activated_at: Option<DateTime<Utc>>,
    pub lines: Vec<BomLine>,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct BomLineInput {
    pub component_product_id: Uuid,
    #[schema(value_type = String, example = "2")]
    pub quantity: Decimal,
    #[serde(default)]
    #[schema(value_type = String, example = "0")]
    pub scrap_percent: Decimal,
    #[serde(default)]
    pub notes: String,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct BomInput {
    #[serde(default)]
    pub notes: String,
    pub lines: Vec<BomLineInput>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct NewBomInput {
    /// Copies the lines of this BOM (any revision of the same product). Default: the active BOM, if any.
    pub copy_from: Option<Uuid>,
    #[serde(default)]
    pub notes: String,
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct ExplodeParams {
    /// Quantity of the product to explode. Default 1.
    pub quantity: Option<Decimal>,
}

/// One row of an exploded structure, depth-first. `parent_index` points into the same list.
#[derive(Debug, Serialize, ToSchema)]
pub struct ExplosionNode {
    pub parent_index: Option<i32>,
    pub level: i32,
    pub product_id: Uuid,
    pub code: String,
    pub name: String,
    pub unit: String,
    pub product_type: String,
    #[schema(value_type = String)]
    pub quantity_per_parent: Decimal,
    #[schema(value_type = String)]
    pub scrap_percent: Decimal,
    /// Needed for the requested quantity, scrap included (rounded to 4 decimals).
    #[schema(value_type = String)]
    pub required_quantity: Decimal,
    pub is_leaf: bool,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct Requirement {
    pub product_id: Uuid,
    pub code: String,
    pub name: String,
    pub unit: String,
    pub product_type: String,
    #[schema(value_type = String)]
    pub quantity: Decimal,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct Explosion {
    pub product_id: Uuid,
    pub bom_revision: i32,
    #[schema(value_type = String)]
    pub quantity: Decimal,
    pub nodes: Vec<ExplosionNode>,
    /// Totals of leaf components (to buy, or to make without a BOM).
    pub requirements: Vec<Requirement>,
}

const SELECT_LINES: &str = "SELECT l.position, l.component_product_id, p.code AS component_code,
        p.name AS component_name, p.unit AS component_unit, p.product_type AS component_type,
        p.tracking AS component_tracking,
        EXISTS (SELECT 1 FROM engineering.boms b2 WHERE b2.product_id = p.id AND b2.status = 'active')
            AS component_has_bom,
        l.quantity, l.scrap_percent, l.notes
     FROM engineering.bom_lines l JOIN products.products p ON p.id = l.component_product_id
     WHERE l.bom_id = $1 ORDER BY l.position";

#[derive(FromRow)]
struct BomRow {
    id: Uuid,
    product_id: Uuid,
    product_code: String,
    product_name: String,
    revision: i32,
    status: String,
    notes: String,
    created_at: DateTime<Utc>,
    activated_at: Option<DateTime<Utc>>,
}

pub async fn load_bom(conn: &mut PgConnection, id: Uuid, lock: bool) -> AppResult<Bom> {
    let r: BomRow = sqlx::query_as(&format!(
        "SELECT b.id, b.product_id, p.code AS product_code, p.name AS product_name, b.revision, b.status, b.notes,
                b.created_at, b.activated_at
         FROM engineering.boms b JOIN products.products p ON p.id = b.product_id WHERE b.id = $1{}",
        if lock { " FOR UPDATE OF b" } else { "" }
    ))
    .bind(id)
    .fetch_optional(&mut *conn)
    .await?
    .ok_or(AppError::NotFound("BOM"))?;
    let lines = sqlx::query_as(SELECT_LINES)
        .bind(id)
        .fetch_all(&mut *conn)
        .await?;
    Ok(Bom {
        id: r.id,
        product_id: r.product_id,
        product_code: r.product_code,
        product_name: r.product_name,
        revision: r.revision,
        status: r.status,
        notes: r.notes,
        created_at: r.created_at,
        activated_at: r.activated_at,
        lines,
    })
}

/// Active BOM lines of every product.
async fn active_structure<'e>(db: impl PgExecutor<'e>) -> AppResult<Structure> {
    #[derive(FromRow)]
    struct Row {
        product_id: Uuid,
        component_product_id: Uuid,
        quantity: Decimal,
        scrap_percent: Decimal,
    }
    let rows: Vec<Row> = sqlx::query_as(
        "SELECT b.product_id, l.component_product_id, l.quantity, l.scrap_percent
         FROM engineering.boms b JOIN engineering.bom_lines l ON l.bom_id = b.id
         WHERE b.status = 'active' ORDER BY b.product_id, l.position",
    )
    .fetch_all(db)
    .await?;
    let mut s: Structure = HashMap::new();
    for r in rows {
        s.entry(r.product_id).or_default().push(LineSpec {
            component_id: r.component_product_id,
            quantity: r.quantity,
            scrap_percent: r.scrap_percent,
        });
    }
    Ok(s)
}

/// A line of the active BOM of a product: one unit of the product needs `quantity` of the component
/// plus `scrap_percent` allowance.
#[derive(Debug, Clone, FromRow)]
pub struct ActiveBomLine {
    pub component_product_id: Uuid,
    pub quantity: Decimal,
    pub scrap_percent: Decimal,
    pub position: i32,
}

/// The active BOM revision of a product with its first-level lines, for production (ADR 0036),
/// which freezes the revision on the production order. `None` when the product has no active BOM.
pub async fn active_bom_lines(
    conn: &mut PgConnection,
    product_id: Uuid,
) -> AppResult<Option<(Uuid, i32, Vec<ActiveBomLine>)>> {
    let head: Option<(Uuid, i32)> = sqlx::query_as(
        "SELECT id, revision FROM engineering.boms WHERE product_id = $1 AND status = 'active'",
    )
    .bind(product_id)
    .fetch_optional(&mut *conn)
    .await?;
    let Some((bom_id, revision)) = head else {
        return Ok(None);
    };
    let lines = sqlx::query_as(
        "SELECT component_product_id, quantity, scrap_percent, position
         FROM engineering.bom_lines WHERE bom_id = $1 ORDER BY position",
    )
    .bind(bom_id)
    .fetch_all(conn)
    .await?;
    Ok(Some((bom_id, revision, lines)))
}

/// Whether a product has an active BOM, i.e. is something that is built (a subassembly when it is
/// a component of another BOM).
pub async fn has_active_bom(conn: &mut PgConnection, product_id: Uuid) -> AppResult<bool> {
    Ok(sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM engineering.boms WHERE product_id = $1 AND status = 'active')",
    )
    .bind(product_id)
    .fetch_one(conn)
    .await?)
}

async fn describe_cycle(conn: &mut PgConnection, Cycle(path): Cycle) -> AppResult<String> {
    let codes: Vec<(Uuid, String)> =
        sqlx::query_as("SELECT id, code FROM products.products WHERE id = ANY($1)")
            .bind(&path)
            .fetch_all(conn)
            .await?;
    Ok(path
        .iter()
        .map(|id| {
            codes
                .iter()
                .find(|(i, _)| i == id)
                .map_or("?", |(_, c)| c.as_str())
        })
        .collect::<Vec<_>>()
        .join(" → "))
}

fn validate_lines(product_id: Uuid, lines: &[BomLineInput]) -> AppResult<()> {
    for (i, l) in lines.iter().enumerate() {
        let n = i + 1;
        if l.component_product_id == product_id {
            return Err(AppError::Validation(format!(
                "line {n}: a product cannot contain itself"
            )));
        }
        if l.quantity <= Decimal::ZERO {
            return Err(AppError::Validation(format!(
                "line {n}: quantity must be greater than zero"
            )));
        }
        if l.scrap_percent < Decimal::ZERO || l.scrap_percent >= Decimal::ONE_HUNDRED {
            return Err(AppError::Validation(format!(
                "line {n}: scrap must be between 0 and 100 %"
            )));
        }
    }
    Ok(())
}

async fn replace_lines(
    conn: &mut PgConnection,
    bom_id: Uuid,
    lines: &[BomLineInput],
) -> AppResult<()> {
    sqlx::query("DELETE FROM engineering.bom_lines WHERE bom_id = $1")
        .bind(bom_id)
        .execute(&mut *conn)
        .await?;
    for (i, l) in lines.iter().enumerate() {
        sqlx::query(
            "INSERT INTO engineering.bom_lines (id, bom_id, position, component_product_id, quantity, scrap_percent, notes)
             VALUES ($1, $2, $3, $4, $5, $6, $7)",
        )
        .bind(new_id())
        .bind(bom_id)
        .bind((i + 1) as i32)
        .bind(l.component_product_id)
        .bind(l.quantity)
        .bind(l.scrap_percent)
        .bind(&l.notes)
        .execute(&mut *conn)
        .await?;
    }
    Ok(())
}

fn ensure_buildable(product_type: &str, code: &str) -> AppResult<()> {
    if matches!(product_type, "manufactured" | "configurable") {
        Ok(())
    } else {
        Err(AppError::Validation(format!(
            "{code} is a {product_type} product; only manufactured and configurable products have a BOM"
        )))
    }
}

#[utoipa::path(get, path = "/products/{id}/boms", tag = "engineering", params(("id" = Uuid, Path)),
    responses((status = 200, body = Vec<BomSummary>)))]
async fn list_boms(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(product_id): Path<Uuid>,
) -> AppResult<Json<Vec<BomSummary>>> {
    user.require(Permission::BomRead)?;
    Ok(Json(
        sqlx::query_as(
            "SELECT b.id, b.product_id, b.revision, b.status,
                    (SELECT count(*) FROM engineering.bom_lines l WHERE l.bom_id = b.id) AS line_count,
                    b.notes, b.created_at, b.activated_at
             FROM engineering.boms b WHERE b.product_id = $1 ORDER BY b.revision DESC",
        )
        .bind(product_id)
        .fetch_all(&state.db)
        .await?,
    ))
}

/// Starts a new draft revision, copied from `copy_from` or from the active BOM.
#[utoipa::path(post, path = "/products/{id}/boms", tag = "engineering", params(("id" = Uuid, Path)),
    request_body = NewBomInput,
    responses((status = 201, body = Bom), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn create_bom(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(product_id): Path<Uuid>,
    Json(input): Json<NewBomInput>,
) -> AppResult<(StatusCode, Json<Bom>)> {
    user.require(Permission::BomWrite)?;
    let mut tx = state.db.begin().await?;
    let product = get_product(&mut *tx, product_id).await?;
    ensure_buildable(&product.product_type, &product.code)?;
    // Serialise revision numbering per product.
    sqlx::query("SELECT id FROM products.products WHERE id = $1 FOR UPDATE")
        .bind(product_id)
        .execute(&mut *tx)
        .await?;
    let has_draft: bool = sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM engineering.boms WHERE product_id = $1 AND status = 'draft')",
    )
    .bind(product_id)
    .fetch_one(&mut *tx)
    .await?;
    if has_draft {
        return Err(AppError::Conflict(format!(
            "{} already has a draft BOM; edit or activate it first",
            product.code
        )));
    }
    let source: Option<Uuid> = match input.copy_from {
        Some(id) => {
            let owner: Option<Uuid> =
                sqlx::query_scalar("SELECT product_id FROM engineering.boms WHERE id = $1")
                    .bind(id)
                    .fetch_optional(&mut *tx)
                    .await?;
            if owner != Some(product_id) {
                return Err(AppError::Validation(
                    "copy_from must be a BOM of the same product".into(),
                ));
            }
            Some(id)
        }
        None => {
            sqlx::query_scalar(
                "SELECT id FROM engineering.boms WHERE product_id = $1 AND status = 'active'",
            )
            .bind(product_id)
            .fetch_optional(&mut *tx)
            .await?
        }
    };
    let revision: i32 = sqlx::query_scalar(
        "SELECT coalesce(max(revision), 0) + 1 FROM engineering.boms WHERE product_id = $1",
    )
    .bind(product_id)
    .fetch_one(&mut *tx)
    .await?;
    let id = new_id();
    sqlx::query("INSERT INTO engineering.boms (id, product_id, revision, notes, created_by) VALUES ($1, $2, $3, $4, $5)")
        .bind(id)
        .bind(product_id)
        .bind(revision)
        .bind(&input.notes)
        .bind(user.user_id)
        .execute(&mut *tx)
        .await?;
    if let Some(src) = source {
        sqlx::query(
            "INSERT INTO engineering.bom_lines (id, bom_id, position, component_product_id, quantity, scrap_percent, notes)
             SELECT gen_random_uuid(), $1, position, component_product_id, quantity, scrap_percent, notes
             FROM engineering.bom_lines WHERE bom_id = $2",
        )
        .bind(id)
        .bind(src)
        .execute(&mut *tx)
        .await?;
        // The routing (ADR 0063) is part of a revision just as the lines are, so the new draft
        // starts with the one of the revision it was copied from, in the same transaction.
        // This is a deliberate exception to the layering: production depends on engineering, so
        // engineering cannot call it, and a revision that silently lost its routing when it was
        // activated would be worse than one write into production's table (the reverse of the
        // sales cancel guard that reads `production.production_orders`, ADR 0036). BOMs have no
        // company, so the rows of every company are copied.
        sqlx::query(
            "INSERT INTO production.routing_operations
                 (id, company_id, bom_id, position, name, work_centre_id, setup_minutes,
                  run_minutes_per_unit, notes)
             SELECT gen_random_uuid(), company_id, $1, position, name, work_centre_id,
                    setup_minutes, run_minutes_per_unit, notes
             FROM production.routing_operations WHERE bom_id = $2",
        )
        .bind(id)
        .bind(src)
        .execute(&mut *tx)
        .await?;
    }
    audit::record(
        &mut tx,
        &user,
        "bom",
        id,
        "created",
        serde_json::json!({ "revision": revision, "copied_from": source }),
    )
    .await?;
    let bom = load_bom(&mut tx, id, false).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(bom)))
}

#[utoipa::path(get, path = "/boms/{id}", tag = "engineering", params(("id" = Uuid, Path)),
    responses((status = 200, body = Bom), (status = 404, body = ErrorBody)))]
async fn get_bom(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<Bom>> {
    user.require(Permission::BomRead)?;
    let mut conn = state.db.acquire().await?;
    Ok(Json(load_bom(&mut conn, id, false).await?))
}

/// Replaces the notes and lines of a draft BOM.
#[utoipa::path(put, path = "/boms/{id}", tag = "engineering", params(("id" = Uuid, Path)), request_body = BomInput,
    responses((status = 200, body = Bom), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn update_bom(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<BomInput>,
) -> AppResult<Json<Bom>> {
    user.require(Permission::BomWrite)?;
    let mut tx = state.db.begin().await?;
    let bom = load_bom(&mut tx, id, true).await?;
    if bom.status != "draft" {
        return Err(AppError::Conflict(format!(
            "revision {} of {} is {}; create a new revision to change it",
            bom.revision, bom.product_code, bom.status
        )));
    }
    validate_lines(bom.product_id, &input.lines)?;
    sqlx::query("UPDATE engineering.boms SET notes = $2 WHERE id = $1")
        .bind(id)
        .bind(&input.notes)
        .execute(&mut *tx)
        .await?;
    replace_lines(&mut tx, id, &input.lines).await?;
    audit::record(
        &mut tx,
        &user,
        "bom",
        id,
        "updated",
        serde_json::json!({ "lines": input.lines.len() }),
    )
    .await?;
    let bom = load_bom(&mut tx, id, false).await?;
    tx.commit().await?;
    Ok(Json(bom))
}

/// Makes a draft the active revision. The previous active revision becomes obsolete.
/// Refused if it would create a cycle anywhere in the product structure.
#[utoipa::path(post, path = "/boms/{id}/activate", tag = "engineering", params(("id" = Uuid, Path)),
    responses((status = 200, body = Bom), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn activate_bom(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<Bom>> {
    user.require(Permission::BomWrite)?;
    let mut tx = state.db.begin().await?;
    // Serialise activations, so two concurrent activations cannot together form a cycle.
    sqlx::query("SELECT pg_advisory_xact_lock(hashtext('engineering.bom_activation'))")
        .execute(&mut *tx)
        .await?;
    let bom = load_bom(&mut tx, id, true).await?;
    if bom.status != "draft" {
        return Err(AppError::Conflict(format!(
            "revision {} is already {}",
            bom.revision, bom.status
        )));
    }
    if bom.lines.is_empty() {
        return Err(AppError::Validation("a BOM needs at least one line".into()));
    }
    let product = get_product(&mut *tx, bom.product_id).await?;
    ensure_buildable(&product.product_type, &product.code)?;
    let inactive: Vec<String> = sqlx::query_scalar(
        "SELECT p.code FROM engineering.bom_lines l JOIN products.products p ON p.id = l.component_product_id
         WHERE l.bom_id = $1 AND NOT p.active",
    )
    .bind(id)
    .fetch_all(&mut *tx)
    .await?;
    if !inactive.is_empty() {
        return Err(AppError::Validation(format!(
            "inactive components: {}",
            inactive.join(", ")
        )));
    }

    let mut structure = active_structure(&mut *tx).await?;
    structure.insert(
        bom.product_id,
        bom.lines
            .iter()
            .map(|l| LineSpec {
                component_id: l.component_product_id,
                quantity: l.quantity,
                scrap_percent: l.scrap_percent,
            })
            .collect(),
    );
    if let Some(cycle) = explode::find_cycle(&structure, bom.product_id) {
        let path = describe_cycle(&mut tx, cycle).await?;
        return Err(AppError::Validation(format!(
            "this BOM would create a cycle: {path}"
        )));
    }

    sqlx::query("UPDATE engineering.boms SET status = 'obsolete' WHERE product_id = $1 AND status = 'active'")
        .bind(bom.product_id)
        .execute(&mut *tx)
        .await?;
    sqlx::query(
        "UPDATE engineering.boms SET status = 'active', activated_at = now() WHERE id = $1",
    )
    .bind(id)
    .execute(&mut *tx)
    .await?;
    audit::record(
        &mut tx,
        &user,
        "bom",
        id,
        "activated",
        serde_json::json!({ "revision": bom.revision }),
    )
    .await?;
    let bom = load_bom(&mut tx, id, false).await?;
    tx.commit().await?;
    Ok(Json(bom))
}

/// Explodes the active BOM of a product through all levels.
#[utoipa::path(get, path = "/products/{id}/bom/explode", tag = "engineering", params(("id" = Uuid, Path), ExplodeParams),
    responses((status = 200, body = Explosion), (status = 404, body = ErrorBody)))]
async fn explode_bom(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(product_id): Path<Uuid>,
    Query(p): Query<ExplodeParams>,
) -> AppResult<Json<Explosion>> {
    user.require(Permission::BomRead)?;
    let quantity = p.quantity.unwrap_or(Decimal::ONE);
    if quantity <= Decimal::ZERO {
        return Err(AppError::Validation(
            "quantity must be greater than zero".into(),
        ));
    }
    let mut conn = state.db.acquire().await?;
    let revision: i32 = sqlx::query_scalar(
        "SELECT revision FROM engineering.boms WHERE product_id = $1 AND status = 'active'",
    )
    .bind(product_id)
    .fetch_optional(&mut *conn)
    .await?
    .ok_or(AppError::NotFound("active BOM"))?;
    let structure = active_structure(&mut *conn).await?;
    let nodes = match explode::explode(&structure, product_id, quantity) {
        Ok(n) => n,
        Err(cycle) => {
            // Activation prevents this; report rather than loop if data was changed outside the API.
            let path = describe_cycle(&mut conn, cycle).await?;
            return Err(AppError::Internal(anyhow::anyhow!(
                "cycle in active BOMs: {path}"
            )));
        }
    };
    let ids: Vec<Uuid> = nodes.iter().map(|n| n.product_id).collect();
    #[derive(FromRow)]
    struct P {
        id: Uuid,
        code: String,
        name: String,
        unit: String,
        product_type: String,
    }
    let products: Vec<P> = sqlx::query_as(
        "SELECT id, code, name, unit, product_type FROM products.products WHERE id = ANY($1)",
    )
    .bind(&ids)
    .fetch_all(&mut *conn)
    .await?;
    let info = |id: Uuid| {
        products
            .iter()
            .find(|p| p.id == id)
            .expect("component exists")
    };
    let round = |d: Decimal| d.round_dp(4).normalize();
    Ok(Json(Explosion {
        product_id,
        bom_revision: revision,
        quantity,
        requirements: explode::leaf_requirements(&nodes)
            .into_iter()
            .map(|(id, q)| {
                let p = info(id);
                Requirement {
                    product_id: id,
                    code: p.code.clone(),
                    name: p.name.clone(),
                    unit: p.unit.clone(),
                    product_type: p.product_type.clone(),
                    quantity: round(q),
                }
            })
            .collect(),
        nodes: nodes
            .iter()
            .map(|n| {
                let p = info(n.product_id);
                ExplosionNode {
                    parent_index: n.parent.map(|i| i as i32),
                    level: n.level as i32,
                    product_id: n.product_id,
                    code: p.code.clone(),
                    name: p.name.clone(),
                    unit: p.unit.clone(),
                    product_type: p.product_type.clone(),
                    quantity_per_parent: n.quantity_per_parent,
                    scrap_percent: n.scrap_percent,
                    required_quantity: round(n.required_quantity),
                    is_leaf: n.is_leaf,
                }
            })
            .collect(),
    }))
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(list_boms, create_bom))
        .routes(routes!(get_bom, update_bom))
        .routes(routes!(activate_bom))
        .routes(routes!(explode_bom))
}
