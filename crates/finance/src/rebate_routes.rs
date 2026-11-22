use axum::extract::{Path, State};
use axum::Json;
use tradocraft_core::{AppResult, AppState, CurrentUser, Permission};
use utoipa_axum::{router::OpenApiRouter, routes};
use uuid::Uuid;

use crate::customer_rebates::{
    self as rebates, RebateAssignment, RebateAssignmentInput, RebateHistoricalInput,
    RebateHistoricalTotal, RebateRateApprovalInput, RebateRateReview, RebateSchedule,
    RebateScheduleInput, RebateSettings,
};

#[utoipa::path(
    get, path = "/customer-rebates/settings", tag = "customer_billing",
    responses((status = 200, body = RebateSettings), (status = 403), (status = 404), (status = 409), (status = 422))
)]
async fn get_customer_rebate_settings(
    State(state): State<AppState>,
    user: CurrentUser,
) -> AppResult<Json<RebateSettings>> {
    user.require(Permission::CustomerRebateAdmin)?;
    Ok(Json(
        rebates::get_settings(&state.db, user.company_id).await?,
    ))
}

#[utoipa::path(
    put, path = "/customer-rebates/settings", tag = "customer_billing",
    request_body = RebateSettings,
    responses((status = 200, body = RebateSettings), (status = 403), (status = 404), (status = 409), (status = 422))
)]
async fn update_customer_rebate_settings(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<RebateSettings>,
) -> AppResult<Json<RebateSettings>> {
    user.require(Permission::CustomerRebateAdmin)?;
    Ok(Json(
        rebates::update_settings(&state.db, user.company_id, user.user_id, input).await?,
    ))
}

#[utoipa::path(
    get, path = "/customer-rebates/schedules", tag = "customer_billing",
    responses((status = 200, body = Vec<RebateSchedule>), (status = 403), (status = 404), (status = 409), (status = 422))
)]
async fn list_customer_rebate_schedules(
    State(state): State<AppState>,
    user: CurrentUser,
) -> AppResult<Json<Vec<RebateSchedule>>> {
    user.require(Permission::CustomerRebateAdmin)?;
    Ok(Json(
        rebates::list_schedules(&state.db, user.company_id).await?,
    ))
}

#[utoipa::path(
    post, path = "/customer-rebates/schedules", tag = "customer_billing",
    request_body = RebateScheduleInput,
    responses((status = 200, body = RebateSchedule), (status = 403), (status = 404), (status = 409), (status = 422))
)]
async fn create_customer_rebate_schedule(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<RebateScheduleInput>,
) -> AppResult<Json<RebateSchedule>> {
    user.require(Permission::CustomerRebateAdmin)?;
    Ok(Json(
        rebates::create_schedule(&state.db, user.company_id, user.user_id, input).await?,
    ))
}

#[utoipa::path(
    put, path = "/customer-rebates/schedules/{schedule}", tag = "customer_billing",
    params(("schedule" = Uuid, Path)),
    request_body = RebateScheduleInput,
    responses((status = 200, body = RebateSchedule), (status = 403), (status = 404), (status = 409), (status = 422))
)]
async fn update_customer_rebate_schedule(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(schedule): Path<Uuid>,
    Json(input): Json<RebateScheduleInput>,
) -> AppResult<Json<RebateSchedule>> {
    user.require(Permission::CustomerRebateAdmin)?;
    Ok(Json(
        rebates::update_schedule(&state.db, user.company_id, schedule, user.user_id, input).await?,
    ))
}

#[utoipa::path(
    get, path = "/customer-rebates/customers/{customer}/assignment", tag = "customer_billing",
    params(("customer" = Uuid, Path)),
    responses((status = 200, body = RebateAssignment), (status = 403), (status = 404), (status = 409), (status = 422))
)]
async fn get_customer_rebate_assignment(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(customer): Path<Uuid>,
) -> AppResult<Json<RebateAssignment>> {
    user.require(Permission::CustomerRebateAdmin)?;
    Ok(Json(
        rebates::get_assignment(&state.db, user.company_id, customer).await?,
    ))
}

#[utoipa::path(
    put, path = "/customer-rebates/customers/{customer}/assignment", tag = "customer_billing",
    params(("customer" = Uuid, Path)),
    request_body = RebateAssignmentInput,
    responses((status = 200, body = RebateAssignment), (status = 403), (status = 404), (status = 409), (status = 422))
)]
async fn set_customer_rebate_assignment(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(customer): Path<Uuid>,
    Json(input): Json<RebateAssignmentInput>,
) -> AppResult<Json<RebateAssignment>> {
    user.require(Permission::CustomerRebateAdmin)?;
    Ok(Json(
        rebates::set_assignment(&state.db, user.company_id, customer, user.user_id, input).await?,
    ))
}

#[utoipa::path(
    get, path = "/customer-rebates/customers/{customer}/history", tag = "customer_billing",
    params(("customer" = Uuid, Path)),
    responses((status = 200, body = Vec<RebateHistoricalTotal>), (status = 403), (status = 404), (status = 409), (status = 422))
)]
async fn list_customer_rebate_history(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(customer): Path<Uuid>,
) -> AppResult<Json<Vec<RebateHistoricalTotal>>> {
    user.require(Permission::CustomerRebateAdmin)?;
    Ok(Json(
        rebates::list_historical_totals(&state.db, user.company_id, customer).await?,
    ))
}

#[utoipa::path(
    put, path = "/customer-rebates/customers/{customer}/history", tag = "customer_billing",
    params(("customer" = Uuid, Path)),
    request_body = RebateHistoricalInput,
    responses((status = 200, body = RebateHistoricalTotal), (status = 403), (status = 404), (status = 409), (status = 422))
)]
async fn upsert_customer_rebate_history(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(customer): Path<Uuid>,
    Json(input): Json<RebateHistoricalInput>,
) -> AppResult<Json<RebateHistoricalTotal>> {
    user.require(Permission::CustomerRebateAdmin)?;
    Ok(Json(
        rebates::upsert_historical_total(&state.db, user.company_id, customer, user.user_id, input)
            .await?,
    ))
}

#[utoipa::path(
    get, path = "/customer-rebates/customers/{customer}/rates/{year}", tag = "customer_billing",
    params(("customer" = Uuid, Path), ("year" = i32, Path)),
    responses((status = 200, body = RebateRateReview), (status = 403), (status = 404), (status = 409), (status = 422))
)]
async fn review_customer_rebate_rate(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((customer, year)): Path<(Uuid, i32)>,
) -> AppResult<Json<RebateRateReview>> {
    user.require(Permission::CustomerRebateAdmin)?;
    Ok(Json(
        rebates::review_rate(&state.db, user.company_id, customer, year).await?,
    ))
}

#[utoipa::path(
    post, path = "/customer-rebates/customers/{customer}/rates", tag = "customer_billing",
    params(("customer" = Uuid, Path)),
    request_body = RebateRateApprovalInput,
    responses((status = 200, body = RebateRateReview), (status = 403), (status = 404), (status = 409), (status = 422))
)]
async fn approve_customer_rebate_rate(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(customer): Path<Uuid>,
    Json(input): Json<RebateRateApprovalInput>,
) -> AppResult<Json<RebateRateReview>> {
    user.require(Permission::CustomerRebateAdmin)?;
    Ok(Json(
        rebates::approve_rate(&state.db, user.company_id, customer, user.user_id, input).await?,
    ))
}

pub(super) fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(
            get_customer_rebate_settings,
            update_customer_rebate_settings
        ))
        .routes(routes!(
            list_customer_rebate_schedules,
            create_customer_rebate_schedule
        ))
        .routes(routes!(update_customer_rebate_schedule))
        .routes(routes!(
            get_customer_rebate_assignment,
            set_customer_rebate_assignment
        ))
        .routes(routes!(
            list_customer_rebate_history,
            upsert_customer_rebate_history
        ))
        .routes(routes!(review_customer_rebate_rate))
        .routes(routes!(approve_customer_rebate_rate))
}
