//! Power grids per country (reference data) and the supply profiles of products, with the pure
//! compatibility check used by the product screens and by sales warnings. See ADR 0025.

use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::Json;
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection};
use tradocraft_core::{audit, new_id, AppError, AppResult, AppState, CurrentUser, Permission};
use utoipa::{IntoParams, ToSchema};
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

const MAX_SUPPLIES: usize = 20;

/// One grid of a country, e.g. 230 V single phase at 50 Hz.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, FromRow, ToSchema)]
pub struct PowerGrid {
    pub id: Uuid,
    /// ISO 3166 alpha-2.
    pub country_code: String,
    pub name: String,
    /// Nominal voltage as quoted: phase-to-neutral for 1 phase, line-to-line for 3 phases.
    pub voltage_v: i32,
    /// 1 or 3
    pub phases: i16,
    /// 50 or 60
    pub frequency_hz: i16,
    pub active: bool,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct PowerGridInput {
    pub country_code: String,
    /// Generated from the other fields when empty.
    #[serde(default)]
    pub name: String,
    pub voltage_v: i32,
    pub phases: i16,
    pub frequency_hz: i16,
    #[serde(default = "default_true")]
    pub active: bool,
}

fn default_true() -> bool {
    true
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct GridParams {
    /// Only the grids of this country (ISO alpha-2).
    pub country: Option<String>,
}

/// A way to power a product.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, FromRow, ToSchema)]
pub struct PowerSupply {
    pub id: Uuid,
    /// ac | dc
    pub current_type: String,
    pub voltage_v: i32,
    /// 1 or 3 for AC; null for DC.
    pub phases: Option<i16>,
    /// 50 or 60; null means the product works on both (always null for DC).
    pub frequency_hz: Option<i16>,
    /// Accepted deviation of the grid voltage from the nominal one, in percent. Ignored when
    /// explicit bounds are set.
    pub tolerance_pct: i32,
    /// Explicit lower voltage bound; set together with `voltage_max_v`, or both null. With
    /// bounds the range is `[voltage_min_v, voltage_max_v]` instead of `voltage_v` +/- tolerance.
    pub voltage_min_v: Option<i32>,
    /// Explicit upper voltage bound (see `voltage_min_v`).
    pub voltage_max_v: Option<i32>,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct PowerSupplyInput {
    pub current_type: String,
    pub voltage_v: i32,
    pub phases: Option<i16>,
    pub frequency_hz: Option<i16>,
    /// Defaults to 10.
    pub tolerance_pct: Option<i32>,
    /// Explicit voltage range; both or neither. `voltage_v` must lie within it.
    #[serde(default)]
    pub voltage_min_v: Option<i32>,
    #[serde(default)]
    pub voltage_max_v: Option<i32>,
}

/// Outcome of checking a product against the grid(s) of a country.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PowerCompatibility {
    /// The product has no supply profile: it is not an electrical product.
    NotApplicable,
    /// Only DC supplies: it needs a power supply unit, no AC grid can match it.
    NeedsExternalSupply,
    Compatible,
    Incompatible {
        supported: Vec<PowerSupply>,
        available: Vec<PowerGrid>,
    },
    /// There is no grid data for the country.
    UnknownGrid,
}

fn grid_matches(s: &PowerSupply, g: &PowerGrid) -> bool {
    if s.current_type != "ac" || s.phases != Some(g.phases) {
        return false;
    }
    if s.frequency_hz.is_some_and(|f| f != g.frequency_hz) {
        return false;
    }
    let (sv, gv) = (i64::from(s.voltage_v), i64::from(g.voltage_v));
    if let (Some(lo), Some(hi)) = (s.voltage_min_v, s.voltage_max_v) {
        return (i64::from(lo)..=i64::from(hi)).contains(&gv);
    }
    (gv - sv).abs() * 100 <= sv * i64::from(s.tolerance_pct)
}

/// Checks supplies against the grids that apply. Compatible when any AC supply fits any grid;
/// DC supplies never decide when there is an AC one. Pure; the caller decides which grids apply
/// (one chosen grid, or all active grids of a country).
pub fn check(supplies: &[PowerSupply], grids: &[PowerGrid]) -> PowerCompatibility {
    if supplies.is_empty() {
        return PowerCompatibility::NotApplicable;
    }
    let ac: Vec<&PowerSupply> = supplies.iter().filter(|s| s.current_type == "ac").collect();
    if ac.is_empty() {
        return PowerCompatibility::NeedsExternalSupply;
    }
    if grids.is_empty() {
        return PowerCompatibility::UnknownGrid;
    }
    if ac.iter().any(|s| grids.iter().any(|g| grid_matches(s, g))) {
        return PowerCompatibility::Compatible;
    }
    PowerCompatibility::Incompatible {
        supported: ac.into_iter().cloned().collect(),
        available: grids.to_vec(),
    }
}

/// Machine-readable status of a [`PowerCompatibility`].
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum PowerStatus {
    NotApplicable,
    NeedsExternalSupply,
    Compatible,
    Incompatible,
    UnknownGrid,
}

impl PowerCompatibility {
    pub fn status(&self) -> PowerStatus {
        match self {
            PowerCompatibility::NotApplicable => PowerStatus::NotApplicable,
            PowerCompatibility::NeedsExternalSupply => PowerStatus::NeedsExternalSupply,
            PowerCompatibility::Compatible => PowerStatus::Compatible,
            PowerCompatibility::Incompatible { .. } => PowerStatus::Incompatible,
            PowerCompatibility::UnknownGrid => PowerStatus::UnknownGrid,
        }
    }
}

#[derive(Debug, Serialize, ToSchema)]
pub struct PowerCompatibilityReport {
    pub status: PowerStatus,
    pub country_code: String,
    /// The supply profiles of the product (AC only when the status is incompatible).
    pub supported: Vec<PowerSupply>,
    /// The grids the product was checked against.
    pub available: Vec<PowerGrid>,
}

const GRID_SELECT: &str =
    "SELECT id, country_code::text AS country_code, name, voltage_v, phases, frequency_hz, active
     FROM products.power_grids";

const SUPPLY_SELECT: &str =
    "SELECT id, current_type, voltage_v, phases, frequency_hz, tolerance_pct,
            voltage_min_v, voltage_max_v
     FROM products.product_power_supplies";

fn country(code: &str) -> AppResult<String> {
    let code = code.trim();
    if code.len() != 2 || !code.chars().all(|c| c.is_ascii_alphabetic()) {
        return Err(AppError::Validation(
            "country_code must be a 2-letter code".into(),
        ));
    }
    Ok(code.to_uppercase())
}

fn grid_name(voltage_v: i32, phases: i16, frequency_hz: i16) -> String {
    format!("{voltage_v}V {phases}-phase {frequency_hz}Hz")
}

fn validate_grid(input: &PowerGridInput) -> AppResult<(String, String)> {
    let cc = country(&input.country_code)?;
    if !(1..=100_000).contains(&input.voltage_v) {
        return Err(AppError::Validation(
            "voltage_v must be between 1 and 100000".into(),
        ));
    }
    if ![1, 3].contains(&input.phases) {
        return Err(AppError::Validation("phases must be 1 or 3".into()));
    }
    if ![50, 60].contains(&input.frequency_hz) {
        return Err(AppError::Validation("frequency_hz must be 50 or 60".into()));
    }
    let name = match input.name.trim() {
        "" => grid_name(input.voltage_v, input.phases, input.frequency_hz),
        n => n.to_string(),
    };
    Ok((cc, name))
}

/// Explicit bounds: both or neither, positive, ordered, and around the nominal voltage.
fn validate_bounds(s: &PowerSupplyInput) -> AppResult<()> {
    let (lo, hi) = match (s.voltage_min_v, s.voltage_max_v) {
        (None, None) => return Ok(()),
        (Some(lo), Some(hi)) => (lo, hi),
        _ => {
            return Err(AppError::Validation(
                "voltage_min_v and voltage_max_v must be given together".into(),
            ))
        }
    };
    if !(1..=100_000).contains(&lo) || !(1..=100_000).contains(&hi) {
        return Err(AppError::Validation(
            "voltage_min_v and voltage_max_v must be between 1 and 100000".into(),
        ));
    }
    if lo > hi {
        return Err(AppError::Validation(
            "voltage_min_v must not exceed voltage_max_v".into(),
        ));
    }
    if !(lo..=hi).contains(&s.voltage_v) {
        return Err(AppError::Validation(
            "voltage_v must lie within voltage_min_v and voltage_max_v".into(),
        ));
    }
    Ok(())
}

/// Checks and normalises a product's supply list.
fn validate_supplies(inputs: &[PowerSupplyInput]) -> AppResult<Vec<PowerSupplyInput>> {
    if inputs.len() > MAX_SUPPLIES {
        return Err(AppError::Validation(format!(
            "at most {MAX_SUPPLIES} supplies per product"
        )));
    }
    let mut out: Vec<PowerSupplyInput> = Vec::with_capacity(inputs.len());
    for s in inputs {
        if !["ac", "dc"].contains(&s.current_type.as_str()) {
            return Err(AppError::Validation("current_type must be ac or dc".into()));
        }
        if !(1..=100_000).contains(&s.voltage_v) {
            return Err(AppError::Validation(
                "voltage_v must be between 1 and 100000".into(),
            ));
        }
        if s.current_type == "dc" {
            if s.phases.is_some() || s.frequency_hz.is_some() {
                return Err(AppError::Validation(
                    "a dc supply has no phases or frequency".into(),
                ));
            }
        } else {
            if !s.phases.is_some_and(|p| p == 1 || p == 3) {
                return Err(AppError::Validation(
                    "an ac supply needs phases 1 or 3".into(),
                ));
            }
            if s.frequency_hz.is_some_and(|f| f != 50 && f != 60) {
                return Err(AppError::Validation(
                    "frequency_hz must be 50, 60 or empty (both)".into(),
                ));
            }
        }
        let tol = s.tolerance_pct.unwrap_or(10);
        if !(0..=50).contains(&tol) {
            return Err(AppError::Validation(
                "tolerance_pct must be between 0 and 50".into(),
            ));
        }
        validate_bounds(s)?;
        let n = PowerSupplyInput {
            tolerance_pct: Some(tol),
            ..s.clone()
        };
        if out.iter().any(|o| {
            (&o.current_type, o.voltage_v, o.phases, o.frequency_hz)
                == (&n.current_type, n.voltage_v, n.phases, n.frequency_hz)
        }) {
            return Err(AppError::Validation(
                "duplicate supply (same type, voltage, phases and frequency)".into(),
            ));
        }
        out.push(n);
    }
    Ok(out)
}

#[utoipa::path(get, path = "/power-grids", tag = "products", params(GridParams),
    responses((status = 200, body = Vec<PowerGrid>)))]
async fn list_power_grids(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(p): Query<GridParams>,
) -> AppResult<Json<Vec<PowerGrid>>> {
    user.require(Permission::ProductsRead)?;
    let cc = p.country.as_deref().map(country).transpose()?;
    Ok(Json(
        sqlx::query_as(&format!(
            "{GRID_SELECT} WHERE ($1::text IS NULL OR country_code = $1)
             ORDER BY country_code, phases, voltage_v, frequency_hz"
        ))
        .bind(cc)
        .fetch_all(&state.db)
        .await?,
    ))
}

async fn load_grid(db: &sqlx::PgPool, id: Uuid) -> AppResult<PowerGrid> {
    sqlx::query_as(&format!("{GRID_SELECT} WHERE id = $1"))
        .bind(id)
        .fetch_optional(db)
        .await?
        .ok_or(AppError::NotFound("power grid"))
}

#[utoipa::path(post, path = "/power-grids", tag = "products", request_body = PowerGridInput,
    responses((status = 201, body = PowerGrid), (status = 409, body = tradocraft_core::error::ErrorBody),
              (status = 422, body = tradocraft_core::error::ErrorBody)))]
async fn create_power_grid(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<PowerGridInput>,
) -> AppResult<(StatusCode, Json<PowerGrid>)> {
    user.require(Permission::ProductsWrite)?;
    let (cc, name) = validate_grid(&input)?;
    let id = new_id();
    let mut tx = state.db.begin().await?;
    sqlx::query(
        "INSERT INTO products.power_grids (id, country_code, name, voltage_v, phases, frequency_hz, active)
         VALUES ($1, $2, $3, $4, $5, $6, $7)",
    )
    .bind(id)
    .bind(&cc)
    .bind(&name)
    .bind(input.voltage_v)
    .bind(input.phases)
    .bind(input.frequency_hz)
    .bind(input.active)
    .execute(&mut *tx)
    .await?;
    audit::record(
        &mut tx,
        &user,
        "power_grid",
        id,
        "created",
        serde_json::json!({ "country": cc, "name": name }),
    )
    .await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(load_grid(&state.db, id).await?)))
}

#[utoipa::path(put, path = "/power-grids/{id}", tag = "products", params(("id" = Uuid, Path)),
    request_body = PowerGridInput,
    responses((status = 200, body = PowerGrid), (status = 409, body = tradocraft_core::error::ErrorBody),
              (status = 422, body = tradocraft_core::error::ErrorBody)))]
async fn update_power_grid(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<PowerGridInput>,
) -> AppResult<Json<PowerGrid>> {
    user.require(Permission::ProductsWrite)?;
    let (cc, name) = validate_grid(&input)?;
    let mut tx = state.db.begin().await?;
    let r = sqlx::query(
        "UPDATE products.power_grids
         SET country_code = $2, name = $3, voltage_v = $4, phases = $5, frequency_hz = $6, active = $7,
             updated_at = now()
         WHERE id = $1",
    )
    .bind(id)
    .bind(&cc)
    .bind(&name)
    .bind(input.voltage_v)
    .bind(input.phases)
    .bind(input.frequency_hz)
    .bind(input.active)
    .execute(&mut *tx)
    .await?;
    if r.rows_affected() == 0 {
        return Err(AppError::NotFound("power grid"));
    }
    audit::record(
        &mut tx,
        &user,
        "power_grid",
        id,
        "updated",
        serde_json::json!({}),
    )
    .await?;
    tx.commit().await?;
    Ok(Json(load_grid(&state.db, id).await?))
}

async fn ensure_product(conn: &mut PgConnection, id: Uuid) -> AppResult<()> {
    sqlx::query("SELECT 1 FROM products.products WHERE id = $1")
        .bind(id)
        .fetch_optional(&mut *conn)
        .await?
        .ok_or(AppError::NotFound("product"))?;
    Ok(())
}

async fn load_supplies(conn: &mut PgConnection, product_id: Uuid) -> AppResult<Vec<PowerSupply>> {
    Ok(sqlx::query_as(&format!(
        "{SUPPLY_SELECT} WHERE product_id = $1 ORDER BY current_type, voltage_v, phases, frequency_hz"
    ))
    .bind(product_id)
    .fetch_all(conn)
    .await?)
}

#[utoipa::path(get, path = "/products/{id}/power-supplies", tag = "products", params(("id" = Uuid, Path)),
    responses((status = 200, body = Vec<PowerSupply>), (status = 404, body = tradocraft_core::error::ErrorBody)))]
async fn get_product_power_supplies(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<Vec<PowerSupply>>> {
    user.require(Permission::ProductsRead)?;
    let mut conn = state.db.acquire().await?;
    ensure_product(&mut conn, id).await?;
    Ok(Json(load_supplies(&mut conn, id).await?))
}

/// Replaces the whole supply list of a product (an empty list marks it as non-electrical).
#[utoipa::path(put, path = "/products/{id}/power-supplies", tag = "products", params(("id" = Uuid, Path)),
    request_body = Vec<PowerSupplyInput>,
    responses((status = 200, body = Vec<PowerSupply>), (status = 404, body = tradocraft_core::error::ErrorBody),
              (status = 422, body = tradocraft_core::error::ErrorBody)))]
async fn replace_product_power_supplies(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<Vec<PowerSupplyInput>>,
) -> AppResult<Json<Vec<PowerSupply>>> {
    user.require(Permission::ProductsWrite)?;
    let supplies = validate_supplies(&input)?;
    let mut tx = state.db.begin().await?;
    // Serialises concurrent replacements of the same product (the unique index would otherwise
    // fail the loser); NO KEY UPDATE does not block FK inserts that only take FOR KEY SHARE.
    sqlx::query("SELECT 1 FROM products.products WHERE id = $1 FOR NO KEY UPDATE")
        .bind(id)
        .fetch_optional(&mut *tx)
        .await?
        .ok_or(AppError::NotFound("product"))?;
    sqlx::query("DELETE FROM products.product_power_supplies WHERE product_id = $1")
        .bind(id)
        .execute(&mut *tx)
        .await?;
    for s in &supplies {
        sqlx::query(
            "INSERT INTO products.product_power_supplies
                (id, product_id, current_type, voltage_v, phases, frequency_hz, tolerance_pct,
                 voltage_min_v, voltage_max_v)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)",
        )
        .bind(new_id())
        .bind(id)
        .bind(&s.current_type)
        .bind(s.voltage_v)
        .bind(s.phases)
        .bind(s.frequency_hz)
        .bind(s.tolerance_pct.unwrap_or(10))
        .bind(s.voltage_min_v)
        .bind(s.voltage_max_v)
        .execute(&mut *tx)
        .await?;
    }
    audit::record(
        &mut tx,
        &user,
        "product",
        id,
        "power_supplies_replaced",
        serde_json::json!({ "count": supplies.len() }),
    )
    .await?;
    let out = load_supplies(&mut tx, id).await?;
    tx.commit().await?;
    Ok(Json(out))
}

/// The grids a check runs against: one chosen grid, else the active grids of a country. Returns
/// the country too. A chosen grid must belong to the given country, when both are given.
async fn grids_for(
    conn: &mut PgConnection,
    country_code: Option<&str>,
    grid_id: Option<Uuid>,
) -> AppResult<(String, Vec<PowerGrid>)> {
    let cc = country_code.map(country).transpose()?;
    if let Some(gid) = grid_id {
        let g: PowerGrid = sqlx::query_as(&format!("{GRID_SELECT} WHERE id = $1"))
            .bind(gid)
            .fetch_optional(&mut *conn)
            .await?
            .ok_or(AppError::Validation("unknown power grid".into()))?;
        if cc.as_ref().is_some_and(|c| *c != g.country_code) {
            return Err(AppError::Validation(
                "the power grid does not belong to the country".into(),
            ));
        }
        return Ok((g.country_code.clone(), vec![g]));
    }
    let cc = cc.ok_or(AppError::Validation(
        "country or grid_id is required".into(),
    ))?;
    let grids = sqlx::query_as(&format!(
        "{GRID_SELECT} WHERE country_code = $1 AND active ORDER BY phases, voltage_v, frequency_hz"
    ))
    .bind(&cc)
    .fetch_all(&mut *conn)
    .await?;
    Ok((cc, grids))
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct CompatibilityParams {
    /// ISO alpha-2 country the product goes to.
    pub country: Option<String>,
    /// Check against this grid only (it must belong to the country when both are given).
    pub grid_id: Option<Uuid>,
}

#[utoipa::path(get, path = "/products/{id}/power-compatibility", tag = "products",
    params(("id" = Uuid, Path), CompatibilityParams),
    responses((status = 200, body = PowerCompatibilityReport), (status = 404, body = tradocraft_core::error::ErrorBody),
              (status = 422, body = tradocraft_core::error::ErrorBody)))]
async fn get_product_power_compatibility(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Query(p): Query<CompatibilityParams>,
) -> AppResult<Json<PowerCompatibilityReport>> {
    user.require(Permission::ProductsRead)?;
    let mut conn = state.db.acquire().await?;
    ensure_product(&mut conn, id).await?;
    let (cc, grids) = grids_for(&mut conn, p.country.as_deref(), p.grid_id).await?;
    let supplies = load_supplies(&mut conn, id).await?;
    let result = check(&supplies, &grids);
    Ok(Json(PowerCompatibilityReport {
        status: result.status(),
        country_code: cc,
        supported: match &result {
            PowerCompatibility::Incompatible { supported, .. } => supported.clone(),
            _ => supplies,
        },
        available: grids,
    }))
}

/// A product that does not (cleanly) fit the grid: anything but compatible or not electrical.
#[derive(Debug, Clone)]
pub struct PowerFinding {
    pub product_id: Uuid,
    pub compatibility: PowerCompatibility,
}

/// The compatibility of every given product with `grids`, in one query. Products without a supply
/// profile are included as [`PowerCompatibility::NotApplicable`].
async fn compatibility_for(
    conn: &mut PgConnection,
    product_ids: &[Uuid],
    grids: &[PowerGrid],
) -> AppResult<std::collections::BTreeMap<Uuid, PowerCompatibility>> {
    #[derive(FromRow)]
    struct Row {
        product_id: Uuid,
        #[sqlx(flatten)]
        supply: PowerSupply,
    }
    let rows: Vec<Row> = sqlx::query_as(
        "SELECT product_id, id, current_type, voltage_v, phases, frequency_hz, tolerance_pct,
                voltage_min_v, voltage_max_v
         FROM products.product_power_supplies WHERE product_id = ANY($1) ORDER BY product_id",
    )
    .bind(product_ids)
    .fetch_all(&mut *conn)
    .await?;
    let mut by_product: std::collections::BTreeMap<Uuid, Vec<PowerSupply>> =
        product_ids.iter().map(|id| (*id, Vec::new())).collect();
    for r in rows {
        by_product.entry(r.product_id).or_default().push(r.supply);
    }
    Ok(by_product
        .into_iter()
        .map(|(id, supplies)| (id, check(&supplies, grids)))
        .collect())
}

/// Checks products against one chosen grid, or, without a grid, against no grid at all: electrical
/// products then come out as `UnknownGrid`. Unlike [`check_products`] every product is reported,
/// including the compatible and the non-electrical ones. Used by the opportunity matching.
pub async fn compatibility_with_grid(
    conn: &mut PgConnection,
    product_ids: &[Uuid],
    grid_id: Option<Uuid>,
) -> AppResult<std::collections::BTreeMap<Uuid, PowerCompatibility>> {
    if product_ids.is_empty() {
        return Ok(Default::default());
    }
    let grids = match grid_id {
        Some(g) => grids_for(conn, None, Some(g)).await?.1,
        None => Vec::new(),
    };
    compatibility_for(conn, product_ids, &grids).await
}

/// Checks products against a country's active grids, or against one chosen grid. Returns only the
/// products worth a warning (incompatible, needs an external supply, unknown grid). Used by sales
/// so it does not read product tables itself.
pub async fn check_products(
    conn: &mut PgConnection,
    product_ids: &[Uuid],
    country_code: &str,
    grid_id: Option<Uuid>,
) -> AppResult<Vec<PowerFinding>> {
    if product_ids.is_empty() {
        return Ok(vec![]);
    }
    let (_, grids) = grids_for(conn, Some(country_code), grid_id).await?;
    Ok(compatibility_for(conn, product_ids, &grids)
        .await?
        .into_iter()
        .filter(|(_, compatibility)| {
            matches!(
                compatibility,
                PowerCompatibility::Incompatible { .. }
                    | PowerCompatibility::NeedsExternalSupply
                    | PowerCompatibility::UnknownGrid
            )
        })
        .map(|(product_id, compatibility)| PowerFinding {
            product_id,
            compatibility,
        })
        .collect())
}

/// Whether a grid exists and belongs to the country (for sales validation).
pub async fn grid_in_country(
    conn: &mut PgConnection,
    grid_id: Uuid,
    country_code: &str,
) -> AppResult<bool> {
    Ok(sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM products.power_grids WHERE id = $1 AND country_code = $2)",
    )
    .bind(grid_id)
    .bind(country_code.trim().to_uppercase())
    .fetch_one(conn)
    .await?)
}

/// `clear_power_grid: true` together with a `power_grid_id` contradicts itself (422). Shared by
/// quotations, orders and opportunities.
pub fn check_grid_clear(clear: Option<bool>, given: Option<Uuid>) -> AppResult<()> {
    if clear == Some(true) && given.is_some() {
        return Err(AppError::Validation(
            "clear_power_grid cannot be combined with power_grid_id".into(),
        ));
    }
    Ok(())
}

/// The grid to store next to a country (`label` names it in the error, e.g. "delivery" or
/// "customer"): a given grid must belong to the country (422 otherwise); without a given one the
/// `kept` grid stays only while it fits the country.
pub async fn resolve_power_grid(
    conn: &mut PgConnection,
    given: Option<Uuid>,
    kept: Option<Uuid>,
    country: Option<&str>,
    label: &str,
) -> AppResult<Option<Uuid>> {
    if let Some(g) = given {
        let ok = match country {
            Some(c) => grid_in_country(conn, g, c).await?,
            None => false,
        };
        if !ok {
            return Err(AppError::Validation(format!(
                "power_grid_id must be a grid of the {label} country"
            )));
        }
        return Ok(Some(g));
    }
    match (kept, country) {
        (Some(g), Some(c)) if grid_in_country(conn, g, c).await? => Ok(Some(g)),
        _ => Ok(None),
    }
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(list_power_grids, create_power_grid))
        .routes(routes!(update_power_grid))
        .routes(routes!(
            get_product_power_supplies,
            replace_product_power_supplies
        ))
        .routes(routes!(get_product_power_compatibility))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ac(v: i32, phases: i16, f: Option<i16>) -> PowerSupply {
        PowerSupply {
            id: Uuid::nil(),
            current_type: "ac".into(),
            voltage_v: v,
            phases: Some(phases),
            frequency_hz: f,
            tolerance_pct: 10,
            voltage_min_v: None,
            voltage_max_v: None,
        }
    }
    fn ranged(mut s: PowerSupply, lo: i32, hi: i32) -> PowerSupply {
        s.voltage_min_v = Some(lo);
        s.voltage_max_v = Some(hi);
        s
    }
    fn dc(v: i32) -> PowerSupply {
        PowerSupply {
            current_type: "dc".into(),
            phases: None,
            ..ac(v, 1, None)
        }
    }
    fn grid(v: i32, phases: i16, f: i16) -> PowerGrid {
        PowerGrid {
            id: Uuid::nil(),
            country_code: "BE".into(),
            name: grid_name(v, phases, f),
            voltage_v: v,
            phases,
            frequency_hz: f,
            active: true,
        }
    }

    #[test]
    fn single_phase_within_tolerance() {
        assert_eq!(
            check(&[ac(220, 1, None)], &[grid(230, 1, 50)]),
            PowerCompatibility::Compatible
        );
    }

    #[test]
    fn three_phase_380_fits_400() {
        assert_eq!(
            check(&[ac(380, 3, Some(50))], &[grid(400, 3, 50)]),
            PowerCompatibility::Compatible
        );
    }

    #[test]
    fn low_voltage_does_not_fit_220() {
        let r = check(&[ac(110, 1, None)], &[grid(230, 1, 50)]);
        assert!(matches!(r, PowerCompatibility::Incompatible { .. }));
    }

    #[test]
    fn phases_and_frequency_must_match() {
        assert!(matches!(
            check(&[ac(400, 3, None)], &[grid(230, 1, 50)]),
            PowerCompatibility::Incompatible { .. }
        ));
        assert!(matches!(
            check(&[ac(230, 1, Some(60))], &[grid(230, 1, 50)]),
            PowerCompatibility::Incompatible { .. }
        ));
        assert_eq!(
            check(&[ac(230, 1, None)], &[grid(230, 1, 60)]),
            PowerCompatibility::Compatible
        );
    }

    #[test]
    fn tolerance_boundary_and_zero() {
        // 230 vs 253 is exactly +10%.
        assert_eq!(
            check(&[ac(230, 1, None)], &[grid(253, 1, 50)]),
            PowerCompatibility::Compatible
        );
        let mut s = ac(230, 1, None);
        s.tolerance_pct = 0;
        assert!(matches!(
            check(&[s], &[grid(231, 1, 50)]),
            PowerCompatibility::Incompatible { .. }
        ));
    }

    #[test]
    fn dc_only_needs_external_supply() {
        assert_eq!(
            check(&[dc(24)], &[grid(230, 1, 50)]),
            PowerCompatibility::NeedsExternalSupply
        );
        assert_eq!(
            check(&[dc(24)], &[]),
            PowerCompatibility::NeedsExternalSupply
        );
    }

    #[test]
    fn no_supplies_is_not_applicable() {
        assert_eq!(
            check(&[], &[grid(230, 1, 50)]),
            PowerCompatibility::NotApplicable
        );
    }

    #[test]
    fn no_grids_is_unknown() {
        assert_eq!(
            check(&[ac(230, 1, None)], &[]),
            PowerCompatibility::UnknownGrid
        );
    }

    #[test]
    fn any_grid_is_enough_and_ac_decides_over_dc() {
        let grids = [grid(120, 1, 60), grid(230, 1, 50)];
        assert_eq!(
            check(&[ac(230, 1, None), dc(24)], &grids),
            PowerCompatibility::Compatible
        );
        // Only the first grid: incompatible, and only the AC supply is reported.
        match check(&[ac(230, 1, None), dc(24)], &grids[..1]) {
            PowerCompatibility::Incompatible {
                supported,
                available,
            } => {
                assert_eq!(supported.len(), 1);
                assert_eq!(available.len(), 1);
            }
            other => panic!("{other:?}"),
        }
    }

    #[test]
    fn supply_validation() {
        let s = |t: &str, p: Option<i16>, f: Option<i16>| PowerSupplyInput {
            current_type: t.into(),
            voltage_v: 24,
            phases: p,
            frequency_hz: f,
            tolerance_pct: None,
            voltage_min_v: None,
            voltage_max_v: None,
        };
        assert!(validate_supplies(&[s("dc", Some(1), None)]).is_err());
        assert!(validate_supplies(&[s("dc", None, Some(50))]).is_err());
        assert!(validate_supplies(&[s("ac", None, None)]).is_err());
        assert!(validate_supplies(&[s("ac", Some(2), None)]).is_err());
        assert!(validate_supplies(&[s("ac", Some(1), Some(55))]).is_err());
        assert!(validate_supplies(&[s("xx", None, None)]).is_err());
        assert!(validate_supplies(&[s("ac", Some(1), None), s("ac", Some(1), None)]).is_err());
        assert!(validate_supplies(&[s("dc", None, None), s("ac", Some(1), None)]).is_ok());
    }

    #[test]
    fn explicit_bounds_replace_tolerance() {
        // 230 +/- 10% would not reach 207 .. 253 wide enough for 260; the bounds do.
        let s = ranged(ac(230, 1, None), 200, 260);
        assert_eq!(
            check(std::slice::from_ref(&s), &[grid(260, 1, 50)]),
            PowerCompatibility::Compatible
        );
        assert_eq!(
            check(std::slice::from_ref(&s), &[grid(200, 1, 50)]),
            PowerCompatibility::Compatible
        );
        // Without bounds 200 V is outside 230 +/- 10%.
        assert!(matches!(
            check(&[ac(230, 1, None)], &[grid(200, 1, 50)]),
            PowerCompatibility::Incompatible { .. }
        ));
        // Bounds are strict: tolerance no longer widens them.
        assert!(matches!(
            check(&[s], &[grid(261, 1, 50)]),
            PowerCompatibility::Incompatible { .. }
        ));
    }

    #[test]
    fn bounds_still_need_phases_and_frequency() {
        let s = ranged(ac(230, 1, Some(50)), 200, 260);
        assert!(matches!(
            check(std::slice::from_ref(&s), &[grid(230, 3, 50)]),
            PowerCompatibility::Incompatible { .. }
        ));
        assert!(matches!(
            check(&[s], &[grid(230, 1, 60)]),
            PowerCompatibility::Incompatible { .. }
        ));
        let any_hz = ranged(ac(230, 1, None), 200, 260);
        assert_eq!(
            check(&[any_hz], &[grid(230, 1, 60)]),
            PowerCompatibility::Compatible
        );
    }

    #[test]
    fn dc_with_bounds_still_needs_external_supply() {
        let d = ranged(dc(24), 12, 48);
        assert_eq!(
            check(&[d], &[grid(24, 1, 50)]),
            PowerCompatibility::NeedsExternalSupply
        );
    }

    #[test]
    fn bounds_validation() {
        let s = |lo: Option<i32>, hi: Option<i32>, v: i32, t: &str| PowerSupplyInput {
            current_type: t.into(),
            voltage_v: v,
            phases: (t == "ac").then_some(1),
            frequency_hz: None,
            tolerance_pct: None,
            voltage_min_v: lo,
            voltage_max_v: hi,
        };
        assert!(validate_supplies(&[s(Some(200), Some(260), 230, "ac")]).is_ok());
        assert!(validate_supplies(&[s(Some(12), Some(48), 24, "dc")]).is_ok());
        assert!(validate_supplies(&[s(Some(230), Some(230), 230, "ac")]).is_ok());
        assert!(validate_supplies(&[s(Some(200), None, 230, "ac")]).is_err());
        assert!(validate_supplies(&[s(None, Some(260), 230, "ac")]).is_err());
        assert!(validate_supplies(&[s(Some(260), Some(200), 230, "ac")]).is_err());
        assert!(validate_supplies(&[s(Some(0), Some(260), 230, "ac")]).is_err());
        assert!(validate_supplies(&[s(Some(-5), Some(260), 230, "ac")]).is_err());
        assert!(validate_supplies(&[s(Some(200), Some(220), 230, "ac")]).is_err());
        assert!(validate_supplies(&[s(Some(240), Some(260), 230, "ac")]).is_err());
    }
}
