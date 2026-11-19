use axum::extract::{Path, Query, State};
use axum::http::{header, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::Json;
use rust_decimal::Decimal;
use serde::Deserialize;
use tradocraft_core::company::get_company;
use tradocraft_core::{audit, AppError, AppResult, AppState, CurrentUser, Permission};
use utoipa::IntoParams;
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::model::*;
use crate::pdf;
use crate::service::{self, NewQuotation};
use crate::shipping;

type ErrorBody = tradocraft_core::error::ErrorBody;

fn line_refs(lines: &[QuotationLine]) -> Vec<(Option<Uuid>, &str)> {
    lines
        .iter()
        .map(|l| (l.product_id, l.product_code.as_str()))
        .collect()
}

/// Prices lines for a customer without saving. The app calls this while the user edits,
/// so every number on screen comes from the server's pricing engine.
#[utoipa::path(post, path = "/pricing/preview", tag = "sales", request_body = PricingPreviewInput,
    responses((status = 200, body = PricingPreview), (status = 403, body = ErrorBody), (status = 404, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn preview(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<PricingPreviewInput>,
) -> AppResult<Json<PricingPreview>> {
    user.require(Permission::QuotationsRead)?;
    let quote_date = input.quote_date.unwrap_or_else(service::today);
    let price_date = input.price_date.unwrap_or(quote_date);
    service::check_price_date(&user, quote_date, price_date)?;
    let mut conn = state.db.acquire().await?;
    // Checked first so that another company's quotation is a 404 whatever the rest of the input.
    let quoted_shipping = match input.quotation_id {
        Some(qid) => shipping::quoted_amount_for_preview(&mut conn, user.company_id, qid).await?,
        None => None,
    };
    let purpose = input
        .purpose
        .as_deref()
        .map_or(Ok("installation"), service::validate_purpose)?;
    let vat_regime_override =
        service::validate_vat_override(input.vat_regime_override.as_deref(), None)?;
    let mut building_year = service::validate_building_year(
        input.building_construction_year,
        input.clear_building_construction_year,
    )?;
    if building_year.is_none() && input.clear_building_construction_year != Some(true) {
        if let Some(opp_id) = input.opportunity_id {
            building_year =
                service::opportunity_building_year(&mut conn, user.company_id, opp_id).await?;
        }
    }
    let price_ctx = service::PriceContext {
        quote_date,
        price_date,
        purpose,
        vat_regime_override: vat_regime_override.as_deref(),
        building_construction_year: building_year,
    };
    let mut p = service::price_lines(
        &state.db,
        user.company_id,
        input.customer_id,
        &price_ctx,
        &input.lines,
    )
    .await?;
    let country = service::resolve_delivery_country(
        input.delivery_country_code.as_deref(),
        None,
        purpose,
        &p.customer.customer.country_code,
    )?;
    if let Some(g) = input.power_grid_id {
        service::resolve_power_grid(&mut conn, Some(g), None, country.as_deref()).await?;
    }
    // The saved shipping cost of the draft being edited belongs in the totals, as after saving.
    // Warnings and suggestions only look at product lines, so they are computed from them first.
    let country = country.unwrap_or_default();
    let warnings = service::power_warnings(
        &mut conn,
        purpose,
        &country,
        input.power_grid_id,
        &line_refs(&p.lines),
    )
    .await?;
    let mut warnings = warnings;
    let (conflicts, suggestions) =
        service::relation_checks(&mut conn, purpose, &line_refs(&p.lines)).await?;
    warnings.extend(conflicts);
    if let Some(amount) = quoted_shipping {
        let product_ids: Vec<Uuid> = p.lines.iter().filter_map(|l| l.product_id).collect();
        if shipping::needs_quote(&mut conn, &product_ids).await? {
            let line = shipping::shipping_line(&p.lines, amount)?;
            p.lines.push(line);
            p.totals = service::stored_totals(&p.lines);
        }
    }
    let unconfirmed_lines = p.unconfirmed_lines();
    Ok(Json(PricingPreview {
        warnings,
        suggestions,
        price_zone_code: p.customer.price_zone_code.clone(),
        customer_discount_percent: p.customer.discount_percent,
        quote_date,
        price_date,
        vat_regime: p.vat_regime,
        building_construction_year: p.building_construction_year,
        unconfirmed_lines,
        vat_groups: service::vat_groups(&p.totals),
        subtotal: p.totals.subtotal,
        vat_total: p.totals.vat_total,
        total: p.totals.total,
        lines: p.lines,
    }))
}

/// API sort keys of `GET /quotations` and the SQL they stand for.
const QUOTATION_SORT: &[(&str, &str)] = &[
    ("number", "number"),
    ("customer_name", "customer_name"),
    ("status", "status"),
    ("quote_date", "quote_date"),
    ("valid_until", "valid_until"),
    ("subtotal", "subtotal"),
    ("total", "total"),
];

/// The `WHERE` clause of the quotation list: $1 company, $2 search pattern, $3 statuses,
/// $4 customer, $5 opportunity.
const QUOTATION_WHERE: &str = "WHERE company_id = $1
          AND ($2::text IS NULL OR lower(number) LIKE $2 OR lower(customer_name) LIKE $2)
          AND ($3::text[] IS NULL OR status = ANY($3))
          AND ($4::uuid IS NULL OR customer_id = $4)
          AND ($5::uuid IS NULL OR opportunity_id = $5)";

/// The parsed status filter and search pattern shared by the quotation list and its groups.
fn quotation_filter_values(
    q: Option<&str>,
    status: Option<&str>,
) -> AppResult<(Option<Vec<String>>, Option<String>)> {
    let statuses = tradocraft_core::filter::values(
        status,
        "status",
        &[
            QuotationStatus::Draft,
            QuotationStatus::Sent,
            QuotationStatus::Accepted,
            QuotationStatus::Rejected,
            QuotationStatus::Superseded,
        ]
        .map(QuotationStatus::as_str),
    )?;
    let pattern = q.map(|q| format!("%{}%", q.trim().to_lowercase()));
    Ok((statuses, pattern))
}

/// API group keys of `GET /quotations/groups` and the SQL (text) they stand for. Never NULL.
const QUOTATION_GROUPS: &[(&str, &str)] = &[("status", "status")];

#[derive(Debug, Deserialize, IntoParams)]
pub struct GroupParams {
    /// What to count by: `status`.
    #[param(required = true, nullable = false)]
    pub group_by: Option<String>,
    /// Same as the list.
    pub q: Option<String>,
    /// Same as the list.
    pub status: Option<String>,
    /// Same as the list.
    pub customer_id: Option<Uuid>,
    /// Same as the list.
    pub opportunity_id: Option<Uuid>,
}

#[utoipa::path(get, path = "/quotations/groups", tag = "sales", params(GroupParams),
    responses((status = 200, body = tradocraft_core::group::GroupPage)))]
async fn quotation_groups(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(p): Query<GroupParams>,
) -> AppResult<Json<tradocraft_core::group::GroupPage>> {
    user.require(Permission::QuotationsRead)?;
    let expr = tradocraft_core::group::expr(p.group_by.as_deref(), QUOTATION_GROUPS)?;
    let (statuses, pattern) = quotation_filter_values(p.q.as_deref(), p.status.as_deref())?;
    let sql =
        tradocraft_core::group::count_sql(expr, &format!("sales.quotations {QUOTATION_WHERE}"));
    let rows: Vec<(String, i64)> = sqlx::query_as(sqlx::AssertSqlSafe(sql))
        .bind(user.company_id)
        .bind(&pattern)
        .bind(&statuses)
        .bind(p.customer_id)
        .bind(p.opportunity_id)
        .fetch_all(&state.db)
        .await?;
    Ok(Json(tradocraft_core::group::page(
        p.group_by.as_deref().unwrap_or_default(),
        rows,
    )?))
}

#[utoipa::path(get, path = "/quotations", tag = "sales", params(ListParams),
    responses((status = 200, body = QuotationPage)))]
async fn list_quotations(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(p): Query<ListParams>,
) -> AppResult<Json<QuotationPage>> {
    user.require(Permission::QuotationsRead)?;
    let (statuses, pattern) = quotation_filter_values(p.q.as_deref(), p.status.as_deref())?;
    let filter = QUOTATION_WHERE;
    let order = tradocraft_core::sort::order_by(
        p.sort.as_deref(),
        QUOTATION_SORT,
        "id",
        "quote_date DESC, number DESC, revision DESC",
    )?;
    let items = sqlx::query_as(sqlx::AssertSqlSafe(format!(
        "SELECT id, number, revision, status, customer_id, opportunity_id, customer_name, purpose, shipping_status, quote_date, valid_until,
                currency::text AS currency, subtotal, total
         FROM sales.quotations {filter}
         ORDER BY {order} LIMIT $6 OFFSET $7"
    )))
    .bind(user.company_id)
    .bind(&pattern)
    .bind(&statuses)
    .bind(p.customer_id)
    .bind(p.opportunity_id)
    .bind(p.limit.unwrap_or(50).clamp(1, 500))
    .bind(p.offset.unwrap_or(0).max(0))
    .fetch_all(&state.db)
    .await?;
    let total = sqlx::query_scalar(sqlx::AssertSqlSafe(format!(
        "SELECT count(*) FROM sales.quotations {filter}"
    )))
    .bind(user.company_id)
    .bind(&pattern)
    .bind(&statuses)
    .bind(p.customer_id)
    .bind(p.opportunity_id)
    .fetch_one(&state.db)
    .await?;
    Ok(Json(QuotationPage { items, total }))
}

#[utoipa::path(get, path = "/quotations/{id}", tag = "sales", params(("id" = Uuid, Path)),
    responses((status = 200, body = Quotation), (status = 404, body = ErrorBody)))]
async fn get_quotation(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<Quotation>> {
    user.require(Permission::QuotationsRead)?;
    let mut conn = state.db.acquire().await?;
    Ok(Json(
        service::load_quotation(&mut conn, user.company_id, id, false).await?,
    ))
}

#[utoipa::path(post, path = "/quotations", tag = "sales", request_body = QuotationInput,
    responses((status = 201, body = Quotation), (status = 403, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn create_quotation(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<QuotationInput>,
) -> AppResult<(StatusCode, Json<Quotation>)> {
    user.require(Permission::QuotationsWrite)?;
    let mut tx = state.db.begin().await?;
    let id = create_draft(&mut tx, &state.db, &user, &input).await?;
    let mut q = service::load_quotation(&mut tx, user.company_id, id, false).await?;
    quotation_hints(&mut tx, &mut q).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(q)))
}

/// Creates a draft quotation (revision 1) in the caller's transaction, with its audit events.
/// The caller checks the permission.
pub(crate) async fn create_draft(
    tx: &mut sqlx::PgConnection,
    db: &sqlx::PgPool,
    user: &CurrentUser,
    input: &QuotationInput,
) -> AppResult<Uuid> {
    service::validate_input(input)?;
    let quote_date = input.quote_date.unwrap_or_else(service::today);
    let price_date = input.price_date.unwrap_or(quote_date);
    let backdated = service::check_price_date(user, quote_date, price_date)?;
    let purpose = input
        .purpose
        .as_deref()
        .map_or(Ok("installation"), service::validate_purpose)?;
    let vat_regime_override = service::validate_vat_override(
        input.vat_regime_override.as_deref(),
        input.clear_vat_regime_override,
    )?;
    let explicit_year = service::validate_building_year(
        input.building_construction_year,
        input.clear_building_construction_year,
    )?;
    if let Some(opp) = input.opportunity_id {
        tradocraft_crm::opportunities::link_quotation(&mut *tx, user, opp, input.customer_id)
            .await?;
    }
    let building_year = match (explicit_year, input.opportunity_id) {
        (Some(y), _) => Some(y),
        (None, Some(opp)) if input.clear_building_construction_year != Some(true) => {
            service::opportunity_building_year(&mut *tx, user.company_id, opp).await?
        }
        (None, _) => None,
    };
    let price_ctx = service::PriceContext {
        quote_date,
        price_date,
        purpose,
        vat_regime_override: vat_regime_override.as_deref(),
        building_construction_year: building_year,
    };
    let priced = service::price_lines(
        db,
        user.company_id,
        input.customer_id,
        &price_ctx,
        &input.lines,
    )
    .await?;
    let company = get_company(db, user.company_id).await?;
    let delivery_country = service::resolve_delivery_country(
        input.delivery_country_code.as_deref(),
        None,
        purpose,
        &priced.customer.customer.country_code,
    )?;

    let power_grid_id = service::resolve_power_grid(
        &mut *tx,
        input.power_grid_id,
        None,
        delivery_country.as_deref(),
    )
    .await?;
    let number = service::allocate_number(&mut *tx, user.company_id, quote_date).await?;
    let id = service::insert_quotation(
        &mut *tx,
        user,
        NewQuotation {
            number: &number,
            revision: 1,
            priced: &priced,
            quote_date,
            valid_until: service::valid_until(quote_date, input.valid_days),
            notes: &input.notes,
            currency: &company.currency,
            supersedes_id: None,
            opportunity_id: input.opportunity_id,
            purpose,
            delivery_country_code: delivery_country.as_deref(),
            power_grid_id,
            vat_regime_override: vat_regime_override.as_deref(),
            building_construction_year: building_year,
        },
    )
    .await?;
    shipping::sync(&mut *tx, user, id).await?;
    audit::record(
        &mut *tx,
        user,
        "quotation",
        id,
        "created",
        serde_json::json!({ "number": number }),
    )
    .await?;
    if backdated {
        audit::record(
            &mut *tx,
            user,
            "quotation",
            id,
            "price_date_backdated",
            serde_json::json!({ "price_date": price_date }),
        )
        .await?;
    }
    Ok(id)
}

/// Fills `warnings` and `suggestions` of a stored quotation.
pub(crate) async fn quotation_hints(
    conn: &mut sqlx::PgConnection,
    q: &mut Quotation,
) -> AppResult<()> {
    q.warnings = quotation_warnings(conn, q).await?;
    let (conflicts, suggestions) =
        service::relation_checks(conn, &q.purpose, &line_refs(&q.lines)).await?;
    q.warnings.extend(conflicts);
    q.suggestions = suggestions;
    Ok(())
}

/// Grid warnings for a stored quotation: against the delivery country, else the customer's.
async fn quotation_warnings(
    conn: &mut sqlx::PgConnection,
    q: &Quotation,
) -> AppResult<Vec<SalesWarning>> {
    let country = q
        .delivery_country_code
        .as_deref()
        .unwrap_or(&q.customer_country_code);
    service::power_warnings(
        conn,
        &q.purpose,
        country,
        q.power_grid_id,
        &line_refs(&q.lines),
    )
    .await
}

/// Replaces customer, dates, notes and lines of a draft, repricing everything at its price date.
#[utoipa::path(put, path = "/quotations/{id}", tag = "sales", params(("id" = Uuid, Path)),
    request_body = QuotationInput,
    responses((status = 200, body = Quotation), (status = 403, body = ErrorBody), (status = 409, body = ErrorBody)))]
async fn update_quotation(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<QuotationInput>,
) -> AppResult<Json<Quotation>> {
    user.require(Permission::QuotationsWrite)?;
    let mut tx = state.db.begin().await?;
    update_draft(&mut tx, &state.db, &user, id, &input, true).await?;
    let mut q = service::load_quotation(&mut tx, user.company_id, id, false).await?;
    quotation_hints(&mut tx, &mut q).await?;
    tx.commit().await?;
    state
        .live_events
        .publish_record_change(&user, "quotation", id, q.version, "updated", None);
    Ok(Json(q))
}

/// Replaces customer, dates, notes and lines of a draft in the caller's transaction (409 when it is
/// not a draft), with its audit events. With `relink` false, an `opportunity_id` equal to the stored
/// one is kept without checking the opportunity again, unless the customer changes. The caller
/// checks the permission.
pub(crate) async fn update_draft(
    tx: &mut sqlx::PgConnection,
    db: &sqlx::PgPool,
    user: &CurrentUser,
    id: Uuid,
    input: &QuotationInput,
    relink: bool,
) -> AppResult<()> {
    service::validate_input(input)?;
    let current = service::load_quotation(&mut *tx, user.company_id, id, true).await?;
    tradocraft_core::concurrency::check_version(
        input.expected_version,
        current.version,
        &format!("quotation {}", current.number),
    )?;
    if service::status_of(&current) != QuotationStatus::Draft {
        return Err(AppError::Conflict(format!(
            "quotation {} is {}; only drafts can be changed (create a revision instead)",
            current.number, current.status
        )));
    }
    if let Some(opp) = input.opportunity_id.filter(|o| {
        relink || Some(*o) != current.opportunity_id || input.customer_id != current.customer_id
    }) {
        tradocraft_crm::opportunities::link_quotation(&mut *tx, user, opp, input.customer_id)
            .await?;
    }
    let quote_date = input.quote_date.unwrap_or(current.quote_date);
    let price_date = input.price_date.unwrap_or(current.price_date);
    // Only a change to an earlier price list needs the permission; keeping one is fine.
    let backdated = price_date != current.price_date
        && service::check_price_date(user, quote_date, price_date)?;
    let purpose = input
        .purpose
        .as_deref()
        .map_or(Ok(current.purpose.as_str()), service::validate_purpose)?;
    let explicit_override = service::validate_vat_override(
        input.vat_regime_override.as_deref(),
        input.clear_vat_regime_override,
    )?;
    let vat_regime_override = if input.clear_vat_regime_override == Some(true) {
        None
    } else if explicit_override.is_some() {
        explicit_override
    } else if input.customer_id == current.customer_id {
        current.vat_regime_override.clone()
    } else {
        None
    };
    let explicit_year = service::validate_building_year(
        input.building_construction_year,
        input.clear_building_construction_year,
    )?;
    let building_year = if input.clear_building_construction_year == Some(true) {
        None
    } else if let Some(y) = explicit_year {
        Some(y)
    } else if input.opportunity_id == current.opportunity_id {
        current.building_construction_year
    } else if let Some(opp) = input.opportunity_id {
        service::opportunity_building_year(&mut *tx, user.company_id, opp).await?
    } else {
        None
    };
    let price_ctx = service::PriceContext {
        quote_date,
        price_date,
        purpose,
        vat_regime_override: vat_regime_override.as_deref(),
        building_construction_year: building_year,
    };
    let priced = service::price_lines(
        db,
        user.company_id,
        input.customer_id,
        &price_ctx,
        &input.lines,
    )
    .await?;
    let c = &priced.customer;
    // A new customer means a new default country, unless one is given.
    let kept = if c.customer.id == current.customer_id {
        current.delivery_country_code.clone()
    } else {
        None
    };
    let delivery_country = service::resolve_delivery_country(
        input.delivery_country_code.as_deref(),
        kept,
        purpose,
        &c.customer.country_code,
    )?;
    let kept_grid = if delivery_country == current.delivery_country_code {
        current.power_grid_id
    } else {
        None
    };
    let power_grid_id = service::resolve_power_grid(
        &mut *tx,
        input.power_grid_id,
        // An explicit clear wins over keeping the stored grid.
        if input.clear_power_grid == Some(true) {
            None
        } else {
            kept_grid
        },
        delivery_country.as_deref(),
    )
    .await?;
    sqlx::query(
        "UPDATE sales.quotations SET customer_id = $2, customer_name = $3, customer_vat_number = $4,
            customer_street = $5, customer_postal_code = $6, customer_city = $7, customer_country_code = $8,
            customer_language = $9, price_zone_code = $10, customer_discount_percent = $11, quote_date = $12,
            valid_until = $13, notes = $14, subtotal = $15, vat_total = $16, total = $17, opportunity_id = $18,
            price_date = $19, purpose = $20, delivery_country_code = $21, power_grid_id = $22,
            vat_regime = $23, vat_regime_override = $24, building_construction_year = $25, updated_at = now()
         WHERE id = $1",
    )
    .bind(id)
    .bind(c.customer.id)
    .bind(&c.customer.name)
    .bind(&c.customer.vat_number)
    .bind(&c.customer.street)
    .bind(&c.customer.postal_code)
    .bind(&c.customer.city)
    .bind(&c.customer.country_code)
    .bind(&c.customer.language)
    .bind(&c.price_zone_code)
    .bind(c.discount_percent)
    .bind(quote_date)
    .bind(service::valid_until(quote_date, input.valid_days))
    .bind(&input.notes)
    .bind(priced.totals.subtotal)
    .bind(priced.totals.vat_total)
    .bind(priced.totals.total)
    .bind(input.opportunity_id)
    .bind(price_date)
    .bind(purpose)
    .bind(&delivery_country)
    .bind(power_grid_id)
    .bind(&priced.vat_regime)
    .bind(&vat_regime_override)
    .bind(building_year)
    .execute(&mut *tx)
    .await?;
    sqlx::query("DELETE FROM sales.quotation_lines WHERE quotation_id = $1")
        .bind(id)
        .execute(&mut *tx)
        .await?;
    service::insert_lines(&mut *tx, id, &priced.lines).await?;
    shipping::sync(&mut *tx, user, id).await?;
    // The freight line that `sync` adds or drops changes the stored total, so read it back.
    let saved_total: Decimal =
        sqlx::query_scalar("SELECT total FROM sales.quotations WHERE id = $1")
            .bind(id)
            .fetch_one(&mut *tx)
            .await?;
    // What changed, for the audit viewer and, for the tracked fields, the chatter (ADR 0086).
    let changes = audit::Changes::new()
        .field(
            "customer_name",
            current.customer_name.as_str(),
            c.customer.name.as_str(),
        )
        .field("quote_date", &current.quote_date, &quote_date)
        .field(
            "valid_until",
            &current.valid_until,
            &service::valid_until(quote_date, input.valid_days),
        )
        .field(
            "total",
            &current.total.normalize(),
            &saved_total.normalize(),
        )
        .field("purpose", current.purpose.as_str(), purpose)
        .field(
            "delivery_country_code",
            &current.delivery_country_code,
            &delivery_country,
        );
    let audit_data = changes.into_data();
    tradocraft_chatter::track(
        &mut *tx,
        user,
        tradocraft_chatter::RecordKind::Quotation,
        id,
        &audit_data,
        &[
            "customer_name",
            "quote_date",
            "valid_until",
            "total",
            "purpose",
            "delivery_country_code",
        ],
    )
    .await?;
    audit::record(&mut *tx, user, "quotation", id, "updated", audit_data).await?;
    if backdated {
        audit::record(
            &mut *tx,
            user,
            "quotation",
            id,
            "price_date_backdated",
            serde_json::json!({ "price_date": price_date }),
        )
        .await?;
    }
    Ok(())
}

async fn transition(
    state: &AppState,
    user: &CurrentUser,
    id: Uuid,
    allowed_from: &[QuotationStatus],
    to: QuotationStatus,
    override_shipping: bool,
) -> AppResult<Quotation> {
    user.require(Permission::QuotationsWrite)?;
    if to == QuotationStatus::Sent && override_shipping {
        user.require(Permission::ShippingManage)?;
    }
    let mut tx = state.db.begin().await?;
    let mut current = service::load_quotation(&mut tx, user.company_id, id, true).await?;
    let from = service::status_of(&current);
    if !allowed_from.contains(&from) {
        return Err(AppError::Conflict(format!(
            "cannot change quotation {} from {} to {}",
            current.number,
            from.as_str(),
            to.as_str()
        )));
    }
    if to == QuotationStatus::Sent {
        // Products or categories may have changed since the draft was saved: reconcile first.
        crate::shipping::sync(&mut tx, user, id).await?;
        current = service::load_quotation(&mut tx, user.company_id, id, true).await?;
        if current.shipping_status == "pending" {
            if !override_shipping {
                // Keep the request that sync just opened even though the send is refused.
                tx.commit().await?;
                return Err(AppError::Conflict(format!(
                    "the shipping cost of quotation {} has not been quoted yet",
                    current.number
                )));
            }
            audit::record(
                &mut tx,
                user,
                "quotation",
                id,
                "shipping_override",
                serde_json::json!({}),
            )
            .await?;
        }
    }
    if to == QuotationStatus::Sent {
        let unconfirmed: Vec<String> = current
            .lines
            .iter()
            .filter(|l| !l.price_confirmed)
            .map(|l| format!("line {} ({})", l.position, l.product_code))
            .collect();
        if !unconfirmed.is_empty() {
            return Err(AppError::Validation(format!(
                "enter the price of the price-on-request lines first: {}",
                unconfirmed.join(", ")
            )));
        }
    }
    sqlx::query(
        "UPDATE sales.quotations SET status = $2, updated_at = now(),
                sent_at = CASE WHEN $2 = 'sent' THEN now() ELSE sent_at END
         WHERE id = $1",
    )
    .bind(id)
    .bind(to.as_str())
    .execute(&mut *tx)
    .await?;
    audit::record(
        &mut tx,
        user,
        "quotation",
        id,
        to.as_str(),
        serde_json::json!({ "from": from.as_str() }),
    )
    .await?;
    tradocraft_chatter::log(
        &mut tx,
        user.company_id,
        Some(user.user_id),
        tradocraft_chatter::RecordKind::Quotation,
        id,
        "status",
        serde_json::json!(from.as_str()),
        serde_json::json!(to.as_str()),
        "",
    )
    .await?;
    if let (QuotationStatus::Accepted, Some(opp)) = (to, current.opportunity_id) {
        tradocraft_crm::opportunities::mark_won(&mut tx, user, opp).await?;
    }
    let q = service::load_quotation(&mut tx, user.company_id, id, false).await?;
    tx.commit().await?;
    Ok(q)
}

#[derive(Debug, Deserialize, IntoParams)]
struct SendParams {
    /// Send although the shipping cost has not been quoted yet. Needs the permission
    /// `shipping.manage`.
    override_shipping: Option<bool>,
}

/// Freezes the quotation. From now on it can only be accepted, rejected or revised.
/// Shipping is reconciled first (a request may be opened or cancelled). Refused while indicative
/// prices are unconfirmed, and (409) while its shipping cost is still to be quoted, unless the
/// caller passes `override_shipping=true`, which always needs `shipping.manage` (403 otherwise).
#[utoipa::path(post, path = "/quotations/{id}/send", tag = "sales", params(("id" = Uuid, Path), SendParams),
    responses((status = 200, body = Quotation), (status = 403, body = ErrorBody), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn send_quotation(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Query(params): Query<SendParams>,
) -> AppResult<Json<Quotation>> {
    Ok(Json(
        transition(
            &state,
            &user,
            id,
            &[QuotationStatus::Draft],
            QuotationStatus::Sent,
            params.override_shipping.unwrap_or(false),
        )
        .await?,
    ))
}

#[utoipa::path(post, path = "/quotations/{id}/accept", tag = "sales", params(("id" = Uuid, Path)),
    responses((status = 200, body = Quotation), (status = 409, body = ErrorBody)))]
async fn accept_quotation(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<Quotation>> {
    Ok(Json(
        transition(
            &state,
            &user,
            id,
            &[QuotationStatus::Sent],
            QuotationStatus::Accepted,
            false,
        )
        .await?,
    ))
}

#[utoipa::path(post, path = "/quotations/{id}/reject", tag = "sales", params(("id" = Uuid, Path)),
    responses((status = 200, body = Quotation), (status = 409, body = ErrorBody)))]
async fn reject_quotation(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<Quotation>> {
    Ok(Json(
        transition(
            &state,
            &user,
            id,
            &[QuotationStatus::Sent],
            QuotationStatus::Rejected,
            false,
        )
        .await?,
    ))
}

/// Compares a quotation with today's price list and rebates, line by line. Changes nothing.
#[utoipa::path(get, path = "/quotations/{id}/repricing", tag = "sales", params(("id" = Uuid, Path)),
    responses((status = 200, body = RepricingComparison), (status = 422, body = ErrorBody)))]
async fn repricing(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<RepricingComparison>> {
    user.require(Permission::QuotationsRead)?;
    let mut conn = state.db.acquire().await?;
    let q = service::load_quotation(&mut conn, user.company_id, id, false).await?;
    drop(conn);
    let today = service::today();
    let inputs = service::line_inputs(&q.lines, false)?;
    let price_ctx = service::PriceContext {
        quote_date: today,
        price_date: today,
        purpose: &q.purpose,
        vat_regime_override: q.vat_regime_override.as_deref(),
        building_construction_year: q.building_construction_year,
    };
    let now = service::price_lines(
        &state.db,
        user.company_id,
        q.customer_id,
        &price_ctx,
        &inputs,
    )
    .await?;
    let lines: Vec<RepricingLine> = q
        .lines
        .iter()
        .filter(|l| l.product_id.is_some())
        .zip(&now.lines)
        .map(|(old, new)| RepricingLine {
            position: old.position,
            product_code: old.product_code.clone(),
            description: old.description.clone(),
            quantity: old.quantity,
            non_discountable: new.non_discountable,
            price_on_request: new.price_on_request,
            price_is_indicative: new.price_is_indicative,
            old_list_unit_price: old.list_unit_price,
            new_list_unit_price: new.list_unit_price,
            old_rebate_percent: old.rebate_percent,
            new_rebate_percent: new.rebate_percent,
            old_line_total: old.line_total,
            new_line_total: new.line_total,
            difference: new.line_total - old.line_total,
            needs_confirmation: !new.price_confirmed,
        })
        .collect();
    let product_lines = || q.lines.iter().filter(|l| l.product_id.is_some());
    let old_subtotal: Decimal = product_lines().map(|l| l.line_total).sum();
    let old_shipping_total: Decimal = q
        .lines
        .iter()
        .filter(|l| l.product_id.is_none())
        .map(|l| l.line_total)
        .sum();
    let has_shipping_line = q.lines.iter().any(|l| l.product_id.is_none());
    let product_ids: Vec<Uuid> = product_lines().filter_map(|l| l.product_id).collect();
    let would_need_quote = !tradocraft_products::requiring_shipping_quote(&state.db, &product_ids)
        .await?
        .is_empty();
    Ok(Json(RepricingComparison {
        old_shipping_total,
        shipping_requote_needed: has_shipping_line || would_need_quote,
        old_price_date: q.price_date,
        new_price_date: today,
        lines,
        old_subtotal,
        new_subtotal: now.totals.subtotal,
        difference: now.totals.subtotal - old_subtotal,
    }))
}

/// Creates the next revision as a new draft with the same number; the revised quotation becomes
/// `superseded`. `keep` copies the agreed prices and price list date unchanged; `current` reprices
/// at today's price list and rebates (indicative prices must then be confirmed again).
#[utoipa::path(post, path = "/quotations/{id}/revise", tag = "sales", params(("id" = Uuid, Path)),
    request_body = ReviseInput,
    responses((status = 201, body = Quotation), (status = 409, body = ErrorBody)))]
async fn revise_quotation(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<ReviseInput>,
) -> AppResult<(StatusCode, Json<Quotation>)> {
    user.require(Permission::QuotationsWrite)?;
    let mut tx = state.db.begin().await?;
    let new_id = revise(&mut tx, &state.db, &user, id, input.pricing).await?;
    let q = service::load_quotation(&mut tx, user.company_id, new_id, false).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(q)))
}

/// Creates the next revision of a sent or rejected quotation in the caller's transaction (409
/// otherwise) and supersedes the old one; returns the new draft's id. The caller checks the
/// permission.
pub(crate) async fn revise(
    tx: &mut sqlx::PgConnection,
    db: &sqlx::PgPool,
    user: &CurrentUser,
    id: Uuid,
    pricing: RevisionPricing,
) -> AppResult<Uuid> {
    let old = service::load_quotation(&mut *tx, user.company_id, id, true).await?;
    let from = service::status_of(&old);
    if !matches!(from, QuotationStatus::Sent | QuotationStatus::Rejected) {
        return Err(AppError::Conflict(format!(
            "only sent or rejected quotations can be revised (this one is {})",
            from.as_str()
        )));
    }
    if let Some(opp) = old.opportunity_id {
        tradocraft_crm::opportunities::link_quotation(&mut *tx, user, opp, old.customer_id).await?;
    }
    let today = service::today();
    let validity = (old.valid_until - old.quote_date).num_days().clamp(1, 365);
    let new_id = tradocraft_core::new_id();
    match pricing {
        RevisionPricing::Keep => {
            // Copy header and lines verbatim: same prices, rebates and price list date.
            sqlx::query(
                "INSERT INTO sales.quotations (
                    id, company_id, number, revision, status, customer_id, customer_name, customer_vat_number,
                    customer_street, customer_postal_code, customer_city, customer_country_code, customer_language,
                    price_zone_code, customer_discount_percent, currency, quote_date, valid_until, notes,
                    subtotal, vat_total, total, supersedes_id, created_by, opportunity_id, price_date,
                    purpose, delivery_country_code, power_grid_id, vat_regime, vat_regime_override,
                    building_construction_year)
                 SELECT $2, company_id, number, revision + 1, 'draft', customer_id, customer_name,
                    customer_vat_number, customer_street, customer_postal_code, customer_city,
                    customer_country_code, customer_language, price_zone_code, customer_discount_percent, currency,
                    $3, $4, notes, subtotal, vat_total, total, id, $5, opportunity_id, price_date,
                    purpose, delivery_country_code, power_grid_id, vat_regime, vat_regime_override,
                    building_construction_year
                 FROM sales.quotations WHERE id = $1",
            )
            .bind(id)
            .bind(new_id)
            .bind(today)
            .bind(service::valid_until(today, Some(validity)))
            .bind(user.user_id)
            .execute(&mut *tx)
            .await?;
            service::insert_lines(&mut *tx, new_id, &old.lines).await?;
            shipping::copy_for_revision(&mut *tx, id, new_id).await?;
            shipping::sync(&mut *tx, user, new_id).await?;
        }
        RevisionPricing::Current => {
            let inputs = service::line_inputs(&old.lines, false)?;
            let price_ctx = service::PriceContext {
                quote_date: today,
                price_date: today,
                purpose: &old.purpose,
                vat_regime_override: old.vat_regime_override.as_deref(),
                building_construction_year: old.building_construction_year,
            };
            let priced =
                service::price_lines(db, user.company_id, old.customer_id, &price_ctx, &inputs)
                    .await?;
            let created = service::insert_quotation(
                &mut *tx,
                user,
                NewQuotation {
                    number: &old.number,
                    revision: old.revision + 1,
                    priced: &priced,
                    quote_date: today,
                    valid_until: service::valid_until(today, Some(validity)),
                    notes: &old.notes,
                    currency: &old.currency,
                    supersedes_id: Some(id),
                    opportunity_id: old.opportunity_id,
                    purpose: &old.purpose,
                    delivery_country_code: old.delivery_country_code.as_deref(),
                    power_grid_id: old.power_grid_id,
                    vat_regime_override: old.vat_regime_override.as_deref(),
                    building_construction_year: old.building_construction_year,
                },
            )
            .await?;
            shipping::sync(&mut *tx, user, created).await?;
            finish_revision(tx, user, id, created, "current").await?;
            return Ok(created);
        }
    }
    finish_revision(tx, user, id, new_id, "keep").await?;
    Ok(new_id)
}

async fn finish_revision(
    tx: &mut sqlx::PgConnection,
    user: &CurrentUser,
    old_id: Uuid,
    new_id: Uuid,
    pricing: &str,
) -> AppResult<()> {
    sqlx::query(
        "UPDATE sales.quotations SET status = 'superseded', updated_at = now() WHERE id = $1",
    )
    .bind(old_id)
    .execute(&mut *tx)
    .await?;
    // An imported quotation stays traceable to its source in every revision.
    sqlx::query(
        "UPDATE sales.quotations n SET import_source = o.import_source,
                import_external_ref = o.import_external_ref, configuration = o.configuration
         FROM sales.quotations o WHERE n.id = $2 AND o.id = $1",
    )
    .bind(old_id)
    .bind(new_id)
    .execute(&mut *tx)
    .await?;
    audit::record(
        &mut *tx,
        user,
        "quotation",
        old_id,
        "superseded",
        serde_json::json!({ "by": new_id }),
    )
    .await?;
    audit::record(
        &mut *tx,
        user,
        "quotation",
        new_id,
        "created",
        serde_json::json!({ "revision_of": old_id, "pricing": pricing }),
    )
    .await?;
    Ok(())
}

#[utoipa::path(get, path = "/quotations/{id}/pdf", tag = "sales", params(("id" = Uuid, Path)),
    responses((status = 200, content_type = "application/pdf", body = Vec<u8>), (status = 404, body = ErrorBody)))]
async fn quotation_pdf(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Response> {
    user.require(Permission::QuotationsRead)?;
    let mut conn = state.db.acquire().await?;
    let q = service::load_quotation(&mut conn, user.company_id, id, false).await?;
    let product_ids: Vec<Uuid> = q.lines.iter().filter_map(|l| l.product_id).collect();
    let images =
        tradocraft_products::media::default_images(&mut conn, &state.blobs, &product_ids).await?;
    drop(conn);
    let company = get_company(&state.db, user.company_id).await?;
    let doc = pdf::document_with_images(&company, &q, &images);
    let files: Vec<(String, Vec<u8>)> = images.values().cloned().collect();
    let bytes = match tradocraft_documents::render_pdf_with_files(
        &state.documents,
        "quotation",
        &doc,
        &files,
    )
    .await
    {
        Ok(bytes) => bytes,
        // a picture typst cannot read must not stop the quotation from printing; drop SVGs first
        // so valid JPEG and PNG defaults are preserved
        Err(e) if images.values().any(|(name, _)| name.ends_with(".svg")) => {
            tracing::warn!(error = ?e, "quotation with SVG pictures failed; retrying without SVGs");
            let raster_images: std::collections::HashMap<_, _> = images
                .into_iter()
                .filter(|(_, (name, _))| !name.ends_with(".svg"))
                .collect();
            let raster_doc = pdf::document_with_images(&company, &q, &raster_images);
            let raster_files: Vec<(String, Vec<u8>)> = raster_images.into_values().collect();
            match tradocraft_documents::render_pdf_with_files(
                &state.documents,
                "quotation",
                &raster_doc,
                &raster_files,
            )
            .await
            {
                Ok(bytes) => bytes,
                Err(e2) => {
                    tracing::warn!(error = ?e2, "quotation with raster pictures failed; rendering without");
                    tradocraft_documents::render_pdf(
                        &state.documents,
                        "quotation",
                        &pdf::document(&company, &q),
                    )
                    .await?
                }
            }
        }
        Err(e) if !files.is_empty() => {
            tracing::warn!(error = ?e, "quotation with pictures failed; rendering without");
            tradocraft_documents::render_pdf(
                &state.documents,
                "quotation",
                &pdf::document(&company, &q),
            )
            .await?
        }
        Err(e) => return Err(e.into()),
    };
    let filename = format!("{}-r{}.pdf", q.number, q.revision);
    Ok((
        [
            (header::CONTENT_TYPE, "application/pdf".to_string()),
            (
                header::CONTENT_DISPOSITION,
                format!("inline; filename=\"{filename}\""),
            ),
        ],
        bytes,
    )
        .into_response())
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(preview))
        .routes(routes!(list_quotations, create_quotation))
        .routes(routes!(quotation_groups))
        .routes(routes!(get_quotation, update_quotation))
        .routes(routes!(send_quotation))
        .routes(routes!(accept_quotation))
        .routes(routes!(reject_quotation))
        .routes(routes!(repricing))
        .routes(routes!(revise_quotation))
        .routes(routes!(quotation_pdf))
}
