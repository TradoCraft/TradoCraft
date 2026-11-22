//! Customer closures: the periods in which a customer is closed and cannot receive parcels or
//! shipments. Staff (a secretary) enters them first; a customer portal can later add its own,
//! which is why every row records its `source`.
//!
//! A closure describes the customer, not one of our companies, so it is shared across companies
//! like the customer itself. Dates are inclusive. Delivery planning uses [`closure_on`] and
//! [`next_open_day`] instead of reading the table.

use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::Json;
use chrono::{DateTime, Days, NaiveDate, Utc};
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection, PgExecutor};
use tradocraft_core::{audit, new_id, AppError, AppResult, AppState, CurrentUser, Permission};
use utoipa::{IntoParams, ToSchema};
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

type ErrorBody = tradocraft_core::error::ErrorBody;

pub const KINDS: [&str; 5] = ["holiday", "collective_leave", "inventory", "works", "other"];

/// A closure is never longer than this; a longer one is almost certainly a typo in the year.
const MAX_DAYS: i64 = 366;

/// How many touching closures [`next_open_day`] follows before giving up.
const MAX_CHAIN: usize = 1000;

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct Closure {
    pub id: Uuid,
    pub customer_id: Uuid,
    pub customer_code: String,
    pub customer_name: String,
    /// First closed day.
    pub starts_on: NaiveDate,
    /// Last closed day (inclusive).
    pub ends_on: NaiveDate,
    /// holiday | collective_leave | inventory | works | other
    pub kind: String,
    pub notes: String,
    /// staff | portal
    pub source: String,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct ClosureInput {
    #[serde(deserialize_with = "tradocraft_core::serde_util::date")]
    pub starts_on: NaiveDate,
    /// Last closed day; defaults to `starts_on` (a single day).
    #[serde(default, deserialize_with = "tradocraft_core::serde_util::opt_date")]
    pub ends_on: Option<NaiveDate>,
    /// holiday | collective_leave | inventory | works | other (default other)
    #[serde(default = "default_kind")]
    pub kind: String,
    #[serde(default)]
    pub notes: String,
}

/// Closures are `other` unless said otherwise.
fn default_kind() -> String {
    "other".into()
}

impl ClosureInput {
    /// Checks the input and returns the inclusive end date.
    fn check(&self) -> AppResult<NaiveDate> {
        if !KINDS.contains(&self.kind.as_str()) {
            return Err(AppError::Validation(format!(
                "kind must be one of {}",
                KINDS.join(", ")
            )));
        }
        let ends_on = self.ends_on.unwrap_or(self.starts_on);
        if ends_on < self.starts_on {
            return Err(AppError::Validation("ends_on is before starts_on".into()));
        }
        if (ends_on - self.starts_on).num_days() >= MAX_DAYS {
            return Err(AppError::Validation(format!(
                "a closure cannot last longer than {MAX_DAYS} days"
            )));
        }
        Ok(ends_on)
    }
}

const SELECT: &str =
    "SELECT cl.id, cl.customer_id, c.code AS customer_code, c.name AS customer_name,
        cl.starts_on, cl.ends_on, cl.kind, cl.notes, cl.source, cl.created_at
     FROM crm.customer_closures cl
     JOIN crm.customers c ON c.id = cl.customer_id";

/// The closure that covers `day`, if the customer is closed then (the one that ends last when
/// several overlap).
pub async fn closure_on<'e>(
    db: impl PgExecutor<'e>,
    customer_id: Uuid,
    day: NaiveDate,
) -> AppResult<Option<Closure>> {
    Ok(sqlx::query_as(sqlx::AssertSqlSafe(format!(
        "{SELECT} WHERE cl.customer_id = $1 AND $2 BETWEEN cl.starts_on AND cl.ends_on
         ORDER BY cl.ends_on DESC LIMIT 1"
    )))
    .bind(customer_id)
    .bind(day)
    .fetch_optional(db)
    .await?)
}

/// The first day on or after `day` on which the customer is not closed by a recorded closure.
/// Weekends and public holidays are not considered; only what was entered for the customer.
/// Fails rather than return a day that is still closed when the chain is implausibly long.
pub async fn next_open_day(
    conn: &mut PgConnection,
    customer_id: Uuid,
    day: NaiveDate,
) -> AppResult<NaiveDate> {
    let mut day = day;
    // Overlapping and adjacent closures chain, so follow them; bounded as a safety net.
    for _ in 0..MAX_CHAIN {
        match closure_on(&mut *conn, customer_id, day).await? {
            Some(c) => {
                day = c
                    .ends_on
                    .checked_add_days(Days::new(1))
                    .ok_or_else(|| AppError::Validation("date out of range".into()))?
            }
            None => return Ok(day),
        }
    }
    Err(AppError::Conflict(format!(
        "no open day found within {MAX_CHAIN} consecutive closures"
    )))
}

/// Fails with 404 when the customer does not exist.
async fn customer_exists(conn: &mut PgConnection, customer_id: Uuid) -> AppResult<()> {
    let found: bool =
        sqlx::query_scalar("SELECT EXISTS (SELECT 1 FROM crm.customers WHERE id = $1)")
            .bind(customer_id)
            .fetch_one(conn)
            .await?;
    if found {
        Ok(())
    } else {
        Err(AppError::NotFound("customer"))
    }
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct PeriodParams {
    /// Closures that end on or after this day. Defaults to today, so past closures drop off.
    #[serde(default, deserialize_with = "tradocraft_core::serde_util::opt_date")]
    pub from: Option<NaiveDate>,
    /// Closures that start on or before this day. Defaults to no upper limit.
    #[serde(default, deserialize_with = "tradocraft_core::serde_util::opt_date")]
    pub to: Option<NaiveDate>,
}

/// Closures that end on or after `p.from` (default today) and start on or before `p.to`, of one
/// customer or of all.
async fn list(
    db: &sqlx::PgPool,
    customer_id: Option<Uuid>,
    p: &PeriodParams,
) -> AppResult<Vec<Closure>> {
    let from = p.from.unwrap_or_else(|| Utc::now().date_naive());
    Ok(sqlx::query_as(sqlx::AssertSqlSafe(format!(
        "{SELECT} WHERE ($1::uuid IS NULL OR cl.customer_id = $1)
           AND cl.ends_on >= $2 AND ($3::date IS NULL OR cl.starts_on <= $3)
         ORDER BY cl.starts_on, c.name, cl.id"
    )))
    .bind(customer_id)
    .bind(from)
    .bind(p.to)
    .fetch_all(db)
    .await?)
}

/// Closures of one customer, upcoming and current by default.
#[utoipa::path(get, path = "/customers/{id}/closures", tag = "crm",
    params(("id" = Uuid, Path), PeriodParams), responses((status = 200, body = Vec<Closure>)))]
async fn list_customer_closures(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(customer_id): Path<Uuid>,
    Query(p): Query<PeriodParams>,
) -> AppResult<Json<Vec<Closure>>> {
    user.require(Permission::CustomersRead)?;
    Ok(Json(list(&state.db, Some(customer_id), &p).await?))
}

/// Closures of all customers, e.g. to plan deliveries.
#[utoipa::path(get, path = "/closures", tag = "crm",
    params(PeriodParams), responses((status = 200, body = Vec<Closure>)))]
async fn list_all_closures(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(p): Query<PeriodParams>,
) -> AppResult<Json<Vec<Closure>>> {
    user.require(Permission::CustomersRead)?;
    Ok(Json(list(&state.db, None, &p).await?))
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct CheckParams {
    /// The day the shipment would be delivered (YYYY-MM-DD).
    #[serde(deserialize_with = "tradocraft_core::serde_util::date")]
    pub date: NaiveDate,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct DeliveryCheck {
    pub date: NaiveDate,
    /// True when the customer cannot receive a delivery on `date`.
    pub closed: bool,
    /// The closure that covers `date`, when closed.
    pub closure: Option<Closure>,
    /// `date` itself when open, otherwise the first day after the closure(s).
    pub next_open_day: NaiveDate,
}

/// Can the customer receive a delivery on this day? Shipment planning calls this before it
/// promises a date; only recorded closures count, not weekends or public holidays.
#[utoipa::path(get, path = "/customers/{id}/closures/check", tag = "crm",
    params(("id" = Uuid, Path), CheckParams),
    responses((status = 200, body = DeliveryCheck), (status = 404, body = ErrorBody)))]
async fn check_delivery_day(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(customer_id): Path<Uuid>,
    Query(p): Query<CheckParams>,
) -> AppResult<Json<DeliveryCheck>> {
    user.require(Permission::CustomersRead)?;
    // One snapshot, so `closed` and `next_open_day` cannot disagree when a closure changes.
    let mut tx = state.db.begin().await?;
    sqlx::query("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ")
        .execute(&mut *tx)
        .await?;
    customer_exists(&mut tx, customer_id).await?;
    let closure = closure_on(&mut *tx, customer_id, p.date).await?;
    let next_open_day = next_open_day(&mut tx, customer_id, p.date).await?;
    tx.rollback().await?;
    Ok(Json(DeliveryCheck {
        date: p.date,
        closed: closure.is_some(),
        closure,
        next_open_day,
    }))
}

/// Records a closure of the customer.
#[utoipa::path(post, path = "/customers/{id}/closures", tag = "crm", params(("id" = Uuid, Path)),
    request_body = ClosureInput,
    responses((status = 201, body = Closure), (status = 404, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn create_closure(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(customer_id): Path<Uuid>,
    Json(input): Json<ClosureInput>,
) -> AppResult<(StatusCode, Json<Closure>)> {
    user.require(Permission::ClosuresWrite)?;
    let ends_on = input.check()?;
    let mut tx = state.db.begin().await?;
    customer_exists(&mut tx, customer_id).await?;
    let id = new_id();
    sqlx::query(
        "INSERT INTO crm.customer_closures (id, customer_id, starts_on, ends_on, kind, notes, source, created_by)
         VALUES ($1, $2, $3, $4, $5, $6, 'staff', $7)",
    )
    .bind(id)
    .bind(customer_id)
    .bind(input.starts_on)
    .bind(ends_on)
    .bind(&input.kind)
    .bind(input.notes.trim())
    .bind(user.user_id)
    .execute(&mut *tx)
    .await?;
    audit::record(
        &mut tx,
        &user,
        "customer",
        customer_id,
        "closure_created",
        serde_json::json!({
            "closure_id": id, "starts_on": input.starts_on, "ends_on": ends_on, "kind": input.kind,
        }),
    )
    .await?;
    let c = sqlx::query_as(sqlx::AssertSqlSafe(format!("{SELECT} WHERE cl.id = $1")))
        .bind(id)
        .fetch_one(&mut *tx)
        .await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(c)))
}

/// Changes a closure of the customer.
#[utoipa::path(put, path = "/customers/{id}/closures/{closure_id}", tag = "crm",
    params(("id" = Uuid, Path), ("closure_id" = Uuid, Path)), request_body = ClosureInput,
    responses((status = 200, body = Closure), (status = 404, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn update_closure(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((customer_id, closure_id)): Path<(Uuid, Uuid)>,
    Json(input): Json<ClosureInput>,
) -> AppResult<Json<Closure>> {
    user.require(Permission::ClosuresWrite)?;
    let ends_on = input.check()?;
    let mut tx = state.db.begin().await?;
    let r = sqlx::query(
        "UPDATE crm.customer_closures
         SET starts_on = $3, ends_on = $4, kind = $5, notes = $6, updated_at = now()
         WHERE id = $1 AND customer_id = $2",
    )
    .bind(closure_id)
    .bind(customer_id)
    .bind(input.starts_on)
    .bind(ends_on)
    .bind(&input.kind)
    .bind(input.notes.trim())
    .execute(&mut *tx)
    .await?;
    if r.rows_affected() == 0 {
        return Err(AppError::NotFound("closure"));
    }
    audit::record(&mut tx, &user, "customer", customer_id, "closure_updated", serde_json::json!({
        "closure_id": closure_id, "starts_on": input.starts_on, "ends_on": ends_on, "kind": input.kind,
    }))
    .await?;
    let c = sqlx::query_as(sqlx::AssertSqlSafe(format!("{SELECT} WHERE cl.id = $1")))
        .bind(closure_id)
        .fetch_one(&mut *tx)
        .await?;
    tx.commit().await?;
    Ok(Json(c))
}

/// Removes a closure of the customer.
#[utoipa::path(delete, path = "/customers/{id}/closures/{closure_id}", tag = "crm",
    params(("id" = Uuid, Path), ("closure_id" = Uuid, Path)),
    responses((status = 204), (status = 404, body = ErrorBody)))]
async fn delete_closure(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((customer_id, closure_id)): Path<(Uuid, Uuid)>,
) -> AppResult<StatusCode> {
    user.require(Permission::ClosuresWrite)?;
    let mut tx = state.db.begin().await?;
    let removed: Option<Closure> = sqlx::query_as(sqlx::AssertSqlSafe(format!(
        "{SELECT} WHERE cl.id = $1 AND cl.customer_id = $2"
    )))
    .bind(closure_id)
    .bind(customer_id)
    .fetch_optional(&mut *tx)
    .await?;
    let removed = removed.ok_or(AppError::NotFound("closure"))?;
    let deleted =
        sqlx::query("DELETE FROM crm.customer_closures WHERE id = $1 AND customer_id = $2")
            .bind(closure_id)
            .bind(customer_id)
            .execute(&mut *tx)
            .await?;
    if deleted.rows_affected() == 0 {
        // Removed by someone else since it was read.
        return Err(AppError::NotFound("closure"));
    }
    audit::record(
        &mut tx,
        &user,
        "customer",
        customer_id,
        "closure_deleted",
        serde_json::json!({
            "closure_id": closure_id, "starts_on": removed.starts_on, "ends_on": removed.ends_on,
            "kind": removed.kind,
        }),
    )
    .await?;
    tx.commit().await?;
    Ok(StatusCode::NO_CONTENT)
}

/// The closure routes.
pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(list_customer_closures, create_closure))
        .routes(routes!(update_closure, delete_closure))
        .routes(routes!(list_all_closures))
        .routes(routes!(check_delivery_day))
}
