//! Opportunities: the sales pipeline before (and around) quotations.

use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::Json;
use chrono::{DateTime, Datelike, NaiveDate, Utc};
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection};
use tradocraft_core::{
    audit, new_id, numbering, AppError, AppResult, AppState, CurrentUser, Permission,
};
use utoipa::{IntoParams, ToSchema};
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

type ErrorBody = tradocraft_core::error::ErrorBody;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum OpportunityStage {
    Lead,
    Qualified,
    Proposal,
    Negotiation,
    Won,
    Lost,
}

impl OpportunityStage {
    pub const ALL: [OpportunityStage; 6] = [
        OpportunityStage::Lead,
        OpportunityStage::Qualified,
        OpportunityStage::Proposal,
        OpportunityStage::Negotiation,
        OpportunityStage::Won,
        OpportunityStage::Lost,
    ];

    pub fn as_str(self) -> &'static str {
        match self {
            OpportunityStage::Lead => "lead",
            OpportunityStage::Qualified => "qualified",
            OpportunityStage::Proposal => "proposal",
            OpportunityStage::Negotiation => "negotiation",
            OpportunityStage::Won => "won",
            OpportunityStage::Lost => "lost",
        }
    }

    pub fn parse(s: &str) -> Option<Self> {
        Self::ALL.into_iter().find(|st| st.as_str() == s)
    }

    pub fn is_closed(self) -> bool {
        matches!(self, OpportunityStage::Won | OpportunityStage::Lost)
    }

    /// Default win probability when entering a stage.
    pub fn default_probability(self) -> i16 {
        match self {
            OpportunityStage::Lead => 10,
            OpportunityStage::Qualified => 25,
            OpportunityStage::Proposal => 50,
            OpportunityStage::Negotiation => 75,
            OpportunityStage::Won => 100,
            OpportunityStage::Lost => 0,
        }
    }
}

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct Opportunity {
    pub id: Uuid,
    pub number: String,
    pub title: String,
    pub customer_id: Uuid,
    pub customer_name: String,
    pub owner_user_id: Uuid,
    pub owner_name: String,
    #[schema(value_type = OpportunityStage)]
    pub stage: String,
    #[schema(value_type = String)]
    pub expected_value: Decimal,
    pub probability: i16,
    pub expected_close: Option<NaiveDate>,
    pub lost_reason: Option<String>,
    pub notes: String,
    /// The power grid of the site; belongs to the customer's country (ADR 0068).
    pub power_grid_id: Option<Uuid>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub closed_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct OpportunityInput {
    pub title: String,
    pub customer_id: Uuid,
    /// Defaults to the current user.
    pub owner_user_id: Option<Uuid>,
    #[serde(default)]
    #[schema(value_type = String, example = "25000")]
    pub expected_value: Decimal,
    /// Defaults to the stage's default probability.
    pub probability: Option<i16>,
    #[serde(default, deserialize_with = "tradocraft_core::serde_util::opt_date")]
    pub expected_close: Option<NaiveDate>,
    #[serde(default)]
    pub notes: String,
    /// A grid of the customer's country (422 otherwise). On update it is kept when omitted.
    #[serde(default)]
    pub power_grid_id: Option<Uuid>,
    /// `true` clears the stored grid on update; combined with `power_grid_id` it is a 422.
    #[serde(default)]
    pub clear_power_grid: Option<bool>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct StageInput {
    pub stage: OpportunityStage,
    /// Required when the stage is `lost`.
    pub lost_reason: Option<String>,
    /// Defaults to the stage's default probability.
    pub probability: Option<i16>,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct OpportunityPage {
    pub items: Vec<Opportunity>,
    pub total: i64,
}

#[derive(Debug, Serialize, FromRow, ToSchema)]
pub struct PipelineStage {
    #[schema(value_type = OpportunityStage)]
    pub stage: String,
    pub count: i64,
    #[schema(value_type = String)]
    pub total_value: Decimal,
    /// Sum of expected value × probability.
    #[schema(value_type = String)]
    pub weighted_value: Decimal,
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct ListParams {
    /// Searches number, title and customer name.
    pub q: Option<String>,
    pub stage: Option<String>,
    pub customer_id: Option<Uuid>,
    /// Only open (not won or lost) opportunities.
    pub open: Option<bool>,
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}

const SELECT: &str =
    "SELECT o.id, o.number, o.title, o.customer_id, c.name AS customer_name, o.owner_user_id,
        u.display_name AS owner_name, o.stage, o.expected_value, o.probability, o.expected_close,
        o.lost_reason, o.notes, o.power_grid_id, o.created_at, o.updated_at, o.closed_at
     FROM crm.opportunities o
     JOIN crm.customers c ON c.id = o.customer_id
     JOIN core.users u ON u.id = o.owner_user_id";

async fn load(conn: &mut PgConnection, company_id: Uuid, id: Uuid) -> AppResult<Opportunity> {
    sqlx::query_as(&format!("{SELECT} WHERE o.id = $1 AND o.company_id = $2"))
        .bind(id)
        .bind(company_id)
        .fetch_optional(conn)
        .await?
        .ok_or(AppError::NotFound("opportunity"))
}

fn validate_probability(p: Option<i16>) -> AppResult<()> {
    match p {
        Some(p) if !(0..=100).contains(&p) => Err(AppError::Validation(
            "probability must be between 0 and 100".into(),
        )),
        _ => Ok(()),
    }
}

impl OpportunityInput {
    fn validate(&self) -> AppResult<()> {
        if self.title.trim().is_empty() {
            return Err(AppError::Validation("title is required".into()));
        }
        if self.expected_value < Decimal::ZERO {
            return Err(AppError::Validation(
                "expected_value cannot be negative".into(),
            ));
        }
        validate_probability(self.probability)
    }
}

/// The grid to store: validated against the customer's country (422), see
/// [`tradocraft_products::power::resolve_power_grid`]. `kept` is the stored grid on update.
async fn resolve_grid(
    conn: &mut PgConnection,
    input: &OpportunityInput,
    kept: Option<Uuid>,
) -> AppResult<Option<Uuid>> {
    tradocraft_products::power::check_grid_clear(input.clear_power_grid, input.power_grid_id)?;
    if input.clear_power_grid == Some(true) {
        return Ok(None);
    }
    if input.power_grid_id.is_none() && kept.is_none() {
        return Ok(None);
    }
    let country: Option<String> =
        sqlx::query_scalar("SELECT country_code::text FROM crm.customers WHERE id = $1")
            .bind(input.customer_id)
            .fetch_optional(&mut *conn)
            .await?;
    tradocraft_products::power::resolve_power_grid(
        conn,
        input.power_grid_id,
        kept,
        country.as_deref(),
        "customer",
    )
    .await
}

async fn ensure_owner_in_company(
    conn: &mut PgConnection,
    company_id: Uuid,
    user_id: Uuid,
) -> AppResult<()> {
    let ok: bool = sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM core.user_companies WHERE user_id = $1 AND company_id = $2)",
    )
    .bind(user_id)
    .bind(company_id)
    .fetch_one(conn)
    .await?;
    if ok {
        Ok(())
    } else {
        Err(AppError::Validation(
            "owner is not a member of the active company".into(),
        ))
    }
}

/// Checks that a quotation may be linked to this opportunity: same company, same customer, still open.
/// Moves an early-stage opportunity to `proposal`, since a quotation now exists.
pub async fn link_quotation(
    conn: &mut PgConnection,
    user: &CurrentUser,
    opportunity_id: Uuid,
    customer_id: Uuid,
) -> AppResult<()> {
    let opp = load(conn, user.company_id, opportunity_id).await?;
    let stage = OpportunityStage::parse(&opp.stage).unwrap_or(OpportunityStage::Lead);
    if stage.is_closed() {
        return Err(AppError::Conflict(format!(
            "opportunity {} is {}",
            opp.number, opp.stage
        )));
    }
    if opp.customer_id != customer_id {
        return Err(AppError::Validation(format!(
            "opportunity {} belongs to another customer",
            opp.number
        )));
    }
    if matches!(stage, OpportunityStage::Lead | OpportunityStage::Qualified) {
        set_stage(conn, user, &opp, OpportunityStage::Proposal, None, None).await?;
    }
    Ok(())
}

/// Called when a linked quotation is accepted.
pub async fn mark_won(
    conn: &mut PgConnection,
    user: &CurrentUser,
    opportunity_id: Uuid,
) -> AppResult<()> {
    let opp = load(conn, user.company_id, opportunity_id).await?;
    if opp.stage != "won" {
        set_stage(conn, user, &opp, OpportunityStage::Won, None, None).await?;
    }
    Ok(())
}

async fn set_stage(
    conn: &mut PgConnection,
    user: &CurrentUser,
    opp: &Opportunity,
    stage: OpportunityStage,
    lost_reason: Option<String>,
    probability: Option<i16>,
) -> AppResult<()> {
    let lost_reason = lost_reason
        .map(|r| r.trim().to_string())
        .filter(|r| !r.is_empty());
    if stage == OpportunityStage::Lost && lost_reason.is_none() {
        return Err(AppError::Validation(
            "a reason is required to mark an opportunity as lost".into(),
        ));
    }
    validate_probability(probability)?;
    sqlx::query(
        "UPDATE crm.opportunities SET stage = $2, probability = $3, lost_reason = $4, updated_at = now(),
                closed_at = CASE WHEN $5 THEN coalesce(closed_at, now()) ELSE NULL END
         WHERE id = $1",
    )
    .bind(opp.id)
    .bind(stage.as_str())
    .bind(probability.unwrap_or(stage.default_probability()))
    .bind(if stage == OpportunityStage::Lost { lost_reason.clone() } else { None })
    .bind(stage.is_closed())
    .execute(&mut *conn)
    .await?;
    audit::record(
        conn,
        user,
        "opportunity",
        opp.id,
        "stage_changed",
        serde_json::json!({ "from": opp.stage, "to": stage.as_str(), "lost_reason": lost_reason }),
    )
    .await?;
    Ok(())
}

#[utoipa::path(get, path = "/opportunities", tag = "crm", params(ListParams),
    responses((status = 200, body = OpportunityPage)))]
async fn list_opportunities(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(p): Query<ListParams>,
) -> AppResult<Json<OpportunityPage>> {
    user.require(Permission::OpportunitiesRead)?;
    if let Some(s) = &p.stage {
        OpportunityStage::parse(s)
            .ok_or_else(|| AppError::Validation(format!("unknown stage {s}")))?;
    }
    let pattern =
        p.q.as_deref()
            .map(|q| format!("%{}%", q.trim().to_lowercase()));
    let filter = "WHERE o.company_id = $1
          AND ($2::text IS NULL OR lower(o.number) LIKE $2 OR lower(o.title) LIKE $2 OR lower(c.name) LIKE $2)
          AND ($3::text IS NULL OR o.stage = $3)
          AND ($4::uuid IS NULL OR o.customer_id = $4)
          AND ($5::boolean IS NULL OR (o.stage NOT IN ('won', 'lost')) = $5)";
    let items = sqlx::query_as(&format!(
        "{SELECT} {filter} ORDER BY o.expected_close NULLS LAST, o.number DESC LIMIT $6 OFFSET $7"
    ))
    .bind(user.company_id)
    .bind(&pattern)
    .bind(&p.stage)
    .bind(p.customer_id)
    .bind(p.open)
    .bind(p.limit.unwrap_or(50).clamp(1, 500))
    .bind(p.offset.unwrap_or(0).max(0))
    .fetch_all(&state.db)
    .await?;
    let total = sqlx::query_scalar(&format!(
        "SELECT count(*) FROM crm.opportunities o JOIN crm.customers c ON c.id = o.customer_id {filter}"
    ))
    .bind(user.company_id)
    .bind(&pattern)
    .bind(&p.stage)
    .bind(p.customer_id)
    .bind(p.open)
    .fetch_one(&state.db)
    .await?;
    Ok(Json(OpportunityPage { items, total }))
}

/// Count, value and probability-weighted value per stage.
#[utoipa::path(get, path = "/opportunities/pipeline", tag = "crm",
    responses((status = 200, body = Vec<PipelineStage>)))]
async fn pipeline(
    State(state): State<AppState>,
    user: CurrentUser,
) -> AppResult<Json<Vec<PipelineStage>>> {
    user.require(Permission::OpportunitiesRead)?;
    let rows: Vec<PipelineStage> = sqlx::query_as(
        "SELECT stage, count(*) AS count, coalesce(sum(expected_value), 0) AS total_value,
                round(coalesce(sum(expected_value * probability / 100), 0), 2) AS weighted_value
         FROM crm.opportunities WHERE company_id = $1 GROUP BY stage",
    )
    .bind(user.company_id)
    .fetch_all(&state.db)
    .await?;
    // Always return every stage, in pipeline order.
    Ok(Json(
        OpportunityStage::ALL
            .iter()
            .map(|s| {
                rows.iter().find(|r| r.stage == s.as_str()).map_or_else(
                    || PipelineStage {
                        stage: s.as_str().to_string(),
                        count: 0,
                        total_value: Decimal::ZERO,
                        weighted_value: Decimal::ZERO,
                    },
                    |r| PipelineStage {
                        stage: r.stage.clone(),
                        count: r.count,
                        total_value: r.total_value,
                        weighted_value: r.weighted_value,
                    },
                )
            })
            .collect(),
    ))
}

#[utoipa::path(get, path = "/opportunities/{id}", tag = "crm", params(("id" = Uuid, Path)),
    responses((status = 200, body = Opportunity), (status = 404, body = ErrorBody)))]
async fn get_opportunity(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<Opportunity>> {
    user.require(Permission::OpportunitiesRead)?;
    let mut conn = state.db.acquire().await?;
    Ok(Json(load(&mut conn, user.company_id, id).await?))
}

/// Creates an opportunity in the caller's transaction (also used when a ticket becomes a lead).
pub async fn create(
    conn: &mut PgConnection,
    user: &CurrentUser,
    input: &OpportunityInput,
) -> AppResult<Opportunity> {
    user.require(Permission::OpportunitiesWrite)?;
    input.validate()?;
    let owner = input.owner_user_id.unwrap_or(user.user_id);
    ensure_owner_in_company(conn, user.company_id, owner).await?;
    let power_grid_id = resolve_grid(conn, input, None).await?;
    let year = Utc::now().year();
    let n = numbering::next_number(conn, user.company_id, "opportunity", year).await?;
    let number = format!("O{year}-{n:05}");
    let id = new_id();
    sqlx::query(
        "INSERT INTO crm.opportunities (id, company_id, number, title, customer_id, owner_user_id, expected_value,
                                        probability, expected_close, notes, power_grid_id)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(&number)
    .bind(input.title.trim())
    .bind(input.customer_id)
    .bind(owner)
    .bind(input.expected_value)
    .bind(input.probability.unwrap_or(OpportunityStage::Lead.default_probability()))
    .bind(input.expected_close)
    .bind(&input.notes)
    .bind(power_grid_id)
    .execute(&mut *conn)
    .await?;
    audit::record(
        conn,
        user,
        "opportunity",
        id,
        "created",
        serde_json::json!({ "number": number }),
    )
    .await?;
    load(conn, user.company_id, id).await
}

#[utoipa::path(post, path = "/opportunities", tag = "crm", request_body = OpportunityInput,
    responses((status = 201, body = Opportunity), (status = 422, body = ErrorBody)))]
async fn create_opportunity(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<OpportunityInput>,
) -> AppResult<(StatusCode, Json<Opportunity>)> {
    let mut tx = state.db.begin().await?;
    let opp = create(&mut tx, &user, &input).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(opp)))
}

#[utoipa::path(put, path = "/opportunities/{id}", tag = "crm", params(("id" = Uuid, Path)),
    request_body = OpportunityInput, responses((status = 200, body = Opportunity), (status = 409, body = ErrorBody)))]
async fn update_opportunity(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<OpportunityInput>,
) -> AppResult<Json<Opportunity>> {
    user.require(Permission::OpportunitiesWrite)?;
    input.validate()?;
    let mut tx = state.db.begin().await?;
    let current = load(&mut tx, user.company_id, id).await?;
    if current.customer_id != input.customer_id {
        // Quotations are linked by customer; changing it would orphan them.
        return Err(AppError::Conflict(
            "the customer of an opportunity cannot change; create a new opportunity".into(),
        ));
    }
    let owner = input.owner_user_id.unwrap_or(current.owner_user_id);
    ensure_owner_in_company(&mut tx, user.company_id, owner).await?;
    let power_grid_id = resolve_grid(&mut tx, &input, current.power_grid_id).await?;
    sqlx::query(
        "UPDATE crm.opportunities SET title = $2, customer_id = $3, owner_user_id = $4, expected_value = $5,
                probability = $6, expected_close = $7, notes = $8, power_grid_id = $9, updated_at = now()
         WHERE id = $1",
    )
    .bind(id)
    .bind(input.title.trim())
    .bind(input.customer_id)
    .bind(owner)
    .bind(input.expected_value)
    .bind(input.probability.unwrap_or(current.probability))
    .bind(input.expected_close)
    .bind(&input.notes)
    .bind(power_grid_id)
    .execute(&mut *tx)
    .await?;
    audit::record(
        &mut tx,
        &user,
        "opportunity",
        id,
        "updated",
        serde_json::json!({}),
    )
    .await?;
    let opp = load(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok(Json(opp))
}

/// Moves an opportunity through the pipeline. `won`/`lost` close it; any other stage reopens it.
#[utoipa::path(post, path = "/opportunities/{id}/stage", tag = "crm", params(("id" = Uuid, Path)),
    request_body = StageInput, responses((status = 200, body = Opportunity), (status = 422, body = ErrorBody)))]
async fn change_stage(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<StageInput>,
) -> AppResult<Json<Opportunity>> {
    user.require(Permission::OpportunitiesWrite)?;
    let mut tx = state.db.begin().await?;
    let current = load(&mut tx, user.company_id, id).await?;
    set_stage(
        &mut tx,
        &user,
        &current,
        input.stage,
        input.lost_reason,
        input.probability,
    )
    .await?;
    let opp = load(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok(Json(opp))
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(list_opportunities, create_opportunity))
        .routes(routes!(pipeline))
        .routes(routes!(get_opportunity, update_opportunity))
        .routes(routes!(change_stage))
}
