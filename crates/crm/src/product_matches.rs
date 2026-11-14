//! `GET /opportunities/{id}/product-matches` (ADR 0068, decision 7): every active product judged
//! against the baseline, the match rules and the power grid of the opportunity. Thin loading
//! layer around the pure [`crate::matching`] module; advisory, nothing is hidden.

use axum::extract::{Path, Query, State};
use axum::{Extension, Json};
use rust_decimal::prelude::ToPrimitive;
use serde::{Deserialize, Serialize};
use sqlx::PgConnection;
use std::collections::HashMap;
use std::future::Future;
use std::pin::Pin;
use std::sync::Arc;
use tradocraft_core::{AppError, AppResult, AppState, CurrentUser, Permission};
use tradocraft_products::attributes::{active_products_with, AttributeValue};
use tradocraft_products::power::{compatibility_with_grid, PowerCompatibility};
use utoipa::{IntoParams, ToSchema};
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::baseline::BaselineItem;
use crate::match_rules::list_rules;
use crate::matching::{
    evaluate, flatten, node_label, BaselineNode, BellMotor, MatchStatus, MotorError, ProductFacts,
    ProductValue, Reason, RequiredMotor, Site,
};

type ErrorBody = tradocraft_core::error::ErrorBody;

/// The baseline item type whose items get a motor derived.
pub const BELL_TYPE_CODE: &str = "bell";

/// A boxed future, so the provider can be a trait object.
pub type BoxFuture<'a, T> = Pin<Box<dyn Future<Output = T> + Send + 'a>>;

/// Derives the motor of bells. Implemented by the configurator crate (its admin lookup tables,
/// ADR 0068 decision 6), which depends on this crate, hence the inversion; the API installs it as
/// an [`Extension`]. Returns one result per bell, in order.
pub trait BellMotorProvider: Send + Sync {
    fn derive<'a>(
        &'a self,
        conn: &'a mut PgConnection,
        company_id: Uuid,
        phases: Option<i64>,
        bells: &'a [BaselineNode],
    ) -> BoxFuture<'a, AppResult<Vec<Result<RequiredMotor, MotorError>>>>;
}

/// The installed provider.
pub type BellMotors = Arc<dyn BellMotorProvider>;

const DEFAULT_LIMIT: i64 = 100;
const MAX_LIMIT: i64 = 500;

#[derive(Debug, Deserialize, IntoParams)]
pub struct MatchParams {
    /// Only products with this status: `suitable`, `unsuitable` or `unknown`.
    pub status: Option<String>,
    /// Only products of this family.
    pub family_id: Option<Uuid>,
    /// Default 100, at most 500.
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct ProductMatch {
    pub id: Uuid,
    pub code: String,
    pub name: String,
    pub family_id: Option<Uuid>,
    pub family_code: Option<String>,
    pub status: MatchStatus,
    pub reasons: Vec<Reason>,
}

#[derive(Debug, Default, Serialize, ToSchema)]
pub struct StatusCounts {
    pub suitable: i64,
    pub unsuitable: i64,
    pub unknown: i64,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct ProductMatchPage {
    /// The requested page of the products with the asked status, in product code order.
    pub items: Vec<ProductMatch>,
    /// Number of products with the asked status (all statuses without a filter).
    pub total: i64,
    /// Products per status within the family filter, ignoring the status filter.
    pub counts: StatusCounts,
}

fn parse_status(s: &str) -> Result<MatchStatus, AppError> {
    match s {
        "suitable" => Ok(MatchStatus::Suitable),
        "unsuitable" => Ok(MatchStatus::Unsuitable),
        "unknown" => Ok(MatchStatus::Unknown),
        other => Err(AppError::Validation(format!(
            "status must be suitable, unsuitable or unknown, not {other}"
        ))),
    }
}

fn product_value(v: &AttributeValue) -> Option<ProductValue> {
    match v {
        AttributeValue::Number(d) => d.to_f64().map(ProductValue::Number),
        AttributeValue::Range { min, max } => Some(ProductValue::Range {
            min: min.to_f64()?,
            max: max.to_f64()?,
        }),
        AttributeValue::Text(_) | AttributeValue::Boolean(_) => None,
    }
}

/// (power grid, its phases, baseline items) of an opportunity of the company; 404 otherwise.
async fn load_site(
    conn: &mut PgConnection,
    company_id: Uuid,
    opportunity_id: Uuid,
) -> AppResult<(Option<Uuid>, Option<i64>, Vec<BaselineItem>)> {
    let found: Option<(Option<Uuid>, Option<i16>)> = sqlx::query_as(
        "SELECT o.power_grid_id, g.phases
         FROM crm.opportunities o
         LEFT JOIN products.power_grids g ON g.id = o.power_grid_id
         WHERE o.id = $1 AND o.company_id = $2",
    )
    .bind(opportunity_id)
    .bind(company_id)
    .fetch_optional(&mut *conn)
    .await?;
    let (grid_id, phases) = found.ok_or(AppError::NotFound("opportunity"))?;
    let items = crate::baseline::load_tree(conn, opportunity_id).await?;
    Ok((grid_id, phases.map(i64::from), items))
}

#[utoipa::path(get, path = "/opportunities/{id}/product-matches", tag = "crm",
    params(("id" = Uuid, Path), MatchParams),
    responses((status = 200, body = ProductMatchPage), (status = 404, body = ErrorBody),
        (status = 422, body = ErrorBody)))]
async fn product_matches(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Query(p): Query<MatchParams>,
    motors: Option<Extension<BellMotors>>,
) -> AppResult<Json<ProductMatchPage>> {
    user.require(Permission::OpportunitiesRead)?;
    user.require(Permission::ProductsRead)?;
    let wanted = p.status.as_deref().map(parse_status).transpose()?;
    let mut conn = state.db.acquire().await?;
    let (grid_id, phases, tree) = load_site(&mut conn, user.company_id, id).await?;
    let baseline = flatten(&tree);
    let bells: Vec<BaselineNode> = baseline
        .iter()
        .filter(|n| n.type_code == BELL_TYPE_CODE)
        .cloned()
        .collect();
    let derived = match (&motors, bells.is_empty()) {
        (_, true) => Vec::new(),
        (Some(Extension(m)), false) => m.derive(&mut conn, user.company_id, phases, &bells).await?,
        (None, false) => bells
            .iter()
            .map(|_| {
                Err(MotorError::MissingData(
                    "motor tables are not available".into(),
                ))
            })
            .collect(),
    };
    let bell_motors: Vec<BellMotor> = bells
        .iter()
        .zip(derived)
        .map(|(n, result)| BellMotor {
            label: node_label(n),
            result,
        })
        .collect();
    let rules: Vec<_> = list_rules(&mut conn, user.company_id)
        .await?
        .iter()
        .filter(|r| r.active)
        .map(|r| r.to_rule())
        .collect();
    let mut keys: Vec<String> = rules
        .iter()
        .map(|r| r.product_attribute_key.clone())
        .chain([crate::matching::MOTOR_KW_KEY.to_string()])
        .collect();
    keys.sort();
    keys.dedup();
    let products = active_products_with(&mut conn, &keys, p.family_id).await?;
    let ids: Vec<Uuid> = products.iter().map(|x| x.id).collect();
    let mut power = compatibility_with_grid(&mut conn, &ids, grid_id).await?;
    let site = Site {
        baseline: &baseline,
        rules: &rules,
        has_grid: grid_id.is_some(),
        bell_motors: &bell_motors,
    };
    let mut counts = StatusCounts::default();
    let mut all = Vec::with_capacity(products.len());
    for prod in products {
        let facts = ProductFacts {
            attributes: prod
                .attributes
                .iter()
                .filter_map(|(k, v)| Some((k.clone(), product_value(v)?)))
                .collect::<HashMap<_, _>>(),
            power: power
                .remove(&prod.id)
                .unwrap_or(PowerCompatibility::NotApplicable),
        };
        let e = evaluate(&site, &facts);
        match e.status {
            MatchStatus::Suitable => counts.suitable += 1,
            MatchStatus::Unsuitable => counts.unsuitable += 1,
            MatchStatus::Unknown => counts.unknown += 1,
        }
        if wanted.is_none_or(|w| w == e.status) {
            all.push(ProductMatch {
                id: prod.id,
                code: prod.code,
                name: prod.name,
                family_id: prod.family_id,
                family_code: prod.family_code,
                status: e.status,
                reasons: e.reasons,
            });
        }
    }
    let total = all.len() as i64;
    let limit = p.limit.unwrap_or(DEFAULT_LIMIT).clamp(1, MAX_LIMIT) as usize;
    let offset = p.offset.unwrap_or(0).max(0) as usize;
    let items = all.into_iter().skip(offset).take(limit).collect();
    Ok(Json(ProductMatchPage {
        items,
        total,
        counts,
    }))
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new().routes(routes!(product_matches))
}
