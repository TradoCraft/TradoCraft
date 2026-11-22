//! Remark history (ADR 0037): the texts used earlier on quotation lines of one product, so a
//! salesperson can reuse a production or customer remark instead of retyping it.

use axum::extract::{Path, Query, State};
use axum::Json;
use chrono::NaiveDate;
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use tradocraft_core::{AppError, AppResult, AppState, CurrentUser, Permission};
use utoipa::{IntoParams, ToSchema};
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

type ErrorBody = tradocraft_core::error::ErrorBody;

#[derive(Debug, Deserialize, IntoParams)]
struct HistoryParams {
    /// `production` or `customer`.
    kind: String,
    /// `customer` (quotes of `customer_id`), `language` (quotes in `language`) or `all`.
    scope: String,
    /// Needed for scope `customer`.
    customer_id: Option<Uuid>,
    /// Needed for scope `language`: the language of the quotation being edited (ISO 639-1).
    language: Option<String>,
}

/// One remark text that was used before.
#[derive(Debug, Serialize, FromRow, ToSchema)]
pub struct RemarkHistoryEntry {
    pub text: String,
    /// Quote date of the latest quotation that used the text.
    pub last_used: NaiveDate,
    /// Number of quotation lines that carry the text.
    pub use_count: i64,
    /// Number of the latest quotation that used the text.
    pub last_quotation_number: String,
}

/// The distinct production or customer remarks used on earlier quotation lines of a product, newest
/// first, limited to the caller's company. Scope `customer` looks at the given customer, `language`
/// at quotations whose customer language equals `language`, `all` at everything. Empty remarks are
/// left out.
#[utoipa::path(get, path = "/products/{id}/remark-history", tag = "sales",
    params(("id" = Uuid, Path), HistoryParams),
    responses((status = 200, body = Vec<RemarkHistoryEntry>), (status = 403, body = ErrorBody),
        (status = 422, body = ErrorBody)))]
async fn remark_history(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(product_id): Path<Uuid>,
    Query(p): Query<HistoryParams>,
) -> AppResult<Json<Vec<RemarkHistoryEntry>>> {
    user.require(Permission::QuotationsRead)?;
    // The column name is chosen from a fixed list, never from the request.
    let column = match p.kind.as_str() {
        "production" => "production_remark",
        "customer" => "customer_remark",
        _ => {
            return Err(AppError::Validation(
                "kind must be production or customer".into(),
            ))
        }
    };
    let (customer, language) = match p.scope.as_str() {
        "customer" => {
            (
                Some(p.customer_id.ok_or_else(|| {
                    AppError::Validation("scope customer needs customer_id".into())
                })?),
                None,
            )
        }
        "language" => {
            let l = p.language.as_deref().map(|l| l.trim().to_lowercase());
            match l.filter(|l| !l.is_empty()) {
                Some(l) => (None, Some(l)),
                None => return Err(AppError::Validation("scope language needs language".into())),
            }
        }
        "all" => (None, None),
        _ => {
            return Err(AppError::Validation(
                "scope must be customer, language or all".into(),
            ))
        }
    };
    let sql = format!(
        "SELECT btrim(l.{column}) AS text, max(q.quote_date) AS last_used, count(*) AS use_count,
                (array_agg(q.number ORDER BY q.quote_date DESC, q.created_at DESC))[1] AS last_quotation_number
         FROM sales.quotation_lines l
         JOIN sales.quotations q ON q.id = l.quotation_id
         WHERE l.product_id = $1 AND q.company_id = $2 AND btrim(l.{column}) <> ''
           AND ($3::uuid IS NULL OR q.customer_id = $3)
           AND ($4::text IS NULL OR q.customer_language::text = $4)
         GROUP BY btrim(l.{column})
         ORDER BY max(q.quote_date) DESC, max(q.created_at) DESC, btrim(l.{column})
         LIMIT 50"
    );
    let rows: Vec<RemarkHistoryEntry> = sqlx::query_as(sqlx::AssertSqlSafe(sql))
        .bind(product_id)
        .bind(user.company_id)
        .bind(customer)
        .bind(language)
        .fetch_all(&state.db)
        .await?;
    Ok(Json(rows))
}

/// The route for the remark history of a product.
pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new().routes(routes!(remark_history))
}
