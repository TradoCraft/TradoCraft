//! Annual rebate programmes, verified turnover opening balances, and approved pricing rates.

use chrono::{Datelike, NaiveDate};
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sqlx::types::Json;
use sqlx::{FromRow, PgConnection, PgPool};
use tradocraft_core::{new_id, today, AppError, AppResult, LANGUAGES};
use tradocraft_documents::{format_amount, format_number};
use utoipa::ToSchema;
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct RebateSettings {
    pub show_on_invoices: bool,
    pub wording: Vec<RebateWording>,
}

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct RebateWording {
    pub language: String,
    pub active: String,
    pub highest: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, ToSchema)]
pub struct RebateTier {
    #[schema(value_type = String)]
    pub threshold: Decimal,
    #[schema(value_type = String)]
    pub rate: Decimal,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct RebateScheduleInput {
    pub name: String,
    /// First pricing year for this version of the schedule.
    pub effective_year: i32,
    pub tiers: Vec<RebateTier>,
}

#[derive(Debug, Serialize, ToSchema, FromRow)]
pub struct RebateSchedule {
    pub id: Uuid,
    pub name: String,
    pub effective_year: i32,
    #[sqlx(json)]
    pub tiers: Vec<RebateTier>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct RebateAssignmentInput {
    pub schedule_name: Option<String>,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct RebateAssignment {
    pub customer_id: Uuid,
    pub schedule_name: Option<String>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct RebateHistoricalInput {
    pub year: i32,
    /// Date through which the imported eligible sales have been verified, inclusive.
    pub cutoff: NaiveDate,
    #[schema(value_type = String)]
    pub eligible_sales: Decimal,
}

#[derive(Debug, Serialize, ToSchema, FromRow)]
pub struct RebateHistoricalTotal {
    pub customer_id: Uuid,
    pub year: i32,
    pub cutoff: NaiveDate,
    #[schema(value_type = String)]
    pub eligible_sales: Decimal,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct RebateRateReview {
    pub customer_id: Uuid,
    /// Calendar year in which the approved rate is used. The sales basis is the preceding year.
    pub rate_year: i32,
    #[schema(value_type = Option<String>)]
    pub eligible_sales: Option<Decimal>,
    #[schema(value_type = Option<String>)]
    pub proposed_rate: Option<Decimal>,
    #[schema(value_type = Option<String>)]
    pub approved_rate: Option<Decimal>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct RebateRateApprovalInput {
    pub rate_year: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct RebateProgress {
    #[schema(value_type = String)]
    pub eligible_sales: Decimal,
    #[schema(value_type = Option<String>)]
    pub next_threshold: Option<Decimal>,
    #[schema(value_type = Option<String>)]
    pub amount_to_next_tier: Option<Decimal>,
    #[schema(value_type = Option<String>)]
    pub next_rate: Option<Decimal>,
    /// Calendar year for which purchases are earning a rate.
    pub rate_year: i32,
    pub currency: String,
    pub message: String,
}

fn default_wording() -> Vec<RebateWording> {
    [
        (
            "nl",
            "Uw aankopen die meetellen bedragen {eligible_sales}. Nog {amount_to_next_tier} tot de drempel van {next_threshold} voor {next_rate} korting in {rate_year}.",
            "Uw aankopen die meetellen bedragen {eligible_sales}. U hebt de hoogste kortingsschijf voor {rate_year} bereikt.",
        ),
        (
            "fr",
            "Vos achats éligibles s’élèvent à {eligible_sales}. Il vous reste {amount_to_next_tier} pour atteindre le seuil de {next_threshold} et bénéficier d’une remise de {next_rate} en {rate_year}.",
            "Vos achats éligibles s’élèvent à {eligible_sales}. Vous avez atteint le dernier palier de remise pour {rate_year}.",
        ),
        (
            "en",
            "Your eligible purchases total {eligible_sales}. You need {amount_to_next_tier} more to reach {next_threshold} and earn a {next_rate} rebate for {rate_year}.",
            "Your eligible purchases total {eligible_sales}. You have reached the highest rebate tier for {rate_year}.",
        ),
        (
            "de",
            "Ihre rabattfähigen Einkäufe betragen {eligible_sales}. Es fehlen noch {amount_to_next_tier} bis zur Schwelle von {next_threshold} für {next_rate} Rabatt im Jahr {rate_year}.",
            "Ihre rabattfähigen Einkäufe betragen {eligible_sales}. Sie haben die höchste Rabattstufe für {rate_year} erreicht.",
        ),
        (
            "es",
            "Sus compras que computan suman {eligible_sales}. Le faltan {amount_to_next_tier} para alcanzar el umbral de {next_threshold} y obtener un descuento del {next_rate} en {rate_year}.",
            "Sus compras que computan suman {eligible_sales}. Ha alcanzado el tramo de descuento más alto para {rate_year}.",
        ),
    ]
    .into_iter()
    .map(|(language, active, highest)| RebateWording {
        language: language.into(),
        active: active.into(),
        highest: highest.into(),
    })
    .collect()
}

const TOKENS: [&str; 5] = [
    "eligible_sales",
    "rate_year",
    "next_threshold",
    "amount_to_next_tier",
    "next_rate",
];

/// Validates token syntax. Highest-tier wording can only use the first two tokens.
fn validate_wording(mut wording: &str, next: bool) -> AppResult<()> {
    if wording.trim().is_empty() || wording.chars().count() > 2000 {
        return Err(AppError::Validation(
            "Rebate wording must contain 1 to 2000 characters".into(),
        ));
    }
    let tokens = if next { &TOKENS[..] } else { &TOKENS[..2] };
    while let Some(index) = wording.find(['{', '}']) {
        let Some((_, remainder)) = wording[index..]
            .strip_prefix('{')
            .and_then(|value| value.split_once('}'))
            .filter(|(token, _)| tokens.contains(token))
        else {
            return Err(AppError::Validation(
                "Rebate wording contains an invalid placeholder".into(),
            ));
        };
        wording = remainder;
    }
    Ok(())
}

fn merge_wording(saved: Vec<RebateWording>) -> Vec<RebateWording> {
    default_wording()
        .into_iter()
        .map(|default| {
            saved
                .iter()
                .find(|item| item.language == default.language)
                .cloned()
                .unwrap_or(default)
        })
        .collect()
}

async fn load_settings(conn: &mut PgConnection, company_id: Uuid) -> AppResult<RebateSettings> {
    let saved: Option<(bool, Json<Vec<RebateWording>>)> = sqlx::query_as(
        "SELECT show_on_invoices, wording FROM finance.customer_rebate_settings WHERE company_id = $1",
    )
    .bind(company_id)
    .fetch_optional(conn)
    .await?;
    let (show_on_invoices, Json(wording)) = saved.unwrap_or((false, Json(Vec::new())));
    Ok(RebateSettings {
        show_on_invoices,
        wording: merge_wording(wording),
    })
}

pub async fn get_settings(db: &PgPool, company_id: Uuid) -> AppResult<RebateSettings> {
    load_settings(&mut *db.acquire().await?, company_id).await
}

pub async fn update_settings(
    db: &PgPool,
    company_id: Uuid,
    actor_id: Uuid,
    input: RebateSettings,
) -> AppResult<RebateSettings> {
    let mut seen = Vec::new();
    for wording in &input.wording {
        if !LANGUAGES.contains(&wording.language.as_str()) || seen.contains(&&wording.language) {
            return Err(AppError::Validation(
                "Provide at most one rebate wording per supported language".into(),
            ));
        }
        seen.push(&wording.language);
        validate_wording(&wording.active, true)?;
        validate_wording(&wording.highest, false)?;
    }
    let mut tx = db.begin().await?;
    sqlx::query(
        "INSERT INTO finance.customer_rebate_settings (company_id, show_on_invoices, wording)
         VALUES ($1, $2, $3)
         ON CONFLICT (company_id) DO UPDATE
         SET show_on_invoices = EXCLUDED.show_on_invoices, wording = EXCLUDED.wording",
    )
    .bind(company_id)
    .bind(input.show_on_invoices)
    .bind(Json(&input.wording))
    .execute(&mut *tx)
    .await?;
    record(
        &mut tx,
        company_id,
        actor_id,
        "customer_rebate_settings",
        company_id,
        "updated",
        json!(&input),
    )
    .await?;
    tx.commit().await?;
    Ok(RebateSettings {
        wording: merge_wording(input.wording),
        ..input
    })
}

fn validate_year(year: i32) -> AppResult<()> {
    if !(2..=9999).contains(&year) {
        return Err(AppError::Validation("Invalid rebate year".into()));
    }
    Ok(())
}

fn validate_sales(amount: Decimal) -> bool {
    amount.abs() < Decimal::from(100_000_000_000_000_000_i64) && amount.normalize().scale() <= 2
}

fn prepare_schedule(input: &mut RebateScheduleInput) -> AppResult<()> {
    input.name = input.name.trim().into();
    validate_year(input.effective_year)?;
    if input.name.is_empty() || input.name.chars().count() > 120 || input.tiers.is_empty() {
        return Err(AppError::Validation(
            "Provide a schedule name up to 120 characters and at least one tier".into(),
        ));
    }
    if input.tiers.iter().any(|tier| {
        !validate_sales(tier.threshold)
            || tier.threshold < Decimal::ZERO
            || tier.rate < Decimal::ZERO
            || tier.rate > Decimal::ONE_HUNDRED
            || tier.rate.normalize().scale() > 4
    }) {
        return Err(AppError::Validation(
            "Use nonnegative currency thresholds and rates from 0 to 100 with up to four decimals"
                .into(),
        ));
    }
    input.tiers.sort_by_key(|tier| tier.threshold);
    if input
        .tiers
        .windows(2)
        .any(|tiers| tiers[0].threshold == tiers[1].threshold || tiers[0].rate >= tiers[1].rate)
    {
        return Err(AppError::Validation(
            "Tier thresholds and rates must increase at each level".into(),
        ));
    }
    Ok(())
}

pub async fn list_schedules(db: &PgPool, company_id: Uuid) -> AppResult<Vec<RebateSchedule>> {
    Ok(sqlx::query_as(
        "SELECT id, name, effective_year, tiers FROM finance.customer_rebate_schedules
         WHERE company_id = $1 ORDER BY name, effective_year DESC",
    )
    .bind(company_id)
    .fetch_all(db)
    .await?)
}

pub async fn create_schedule(
    db: &PgPool,
    company_id: Uuid,
    actor_id: Uuid,
    mut input: RebateScheduleInput,
) -> AppResult<RebateSchedule> {
    prepare_schedule(&mut input)?;
    let mut tx = db.begin().await?;
    let schedule: RebateSchedule = sqlx::query_as(
        "INSERT INTO finance.customer_rebate_schedules (id, company_id, name, effective_year, tiers)
         VALUES ($1, $2, $3, $4, $5)
         RETURNING id, name, effective_year, tiers",
    )
    .bind(new_id())
    .bind(company_id)
    .bind(&input.name)
    .bind(input.effective_year)
    .bind(Json(&input.tiers))
    .fetch_one(&mut *tx)
    .await?;
    record(
        &mut tx,
        company_id,
        actor_id,
        "customer_rebate_schedule",
        schedule.id,
        "created",
        json!(&schedule),
    )
    .await?;
    tx.commit().await?;
    Ok(schedule)
}

pub async fn update_schedule(
    db: &PgPool,
    company_id: Uuid,
    schedule_id: Uuid,
    actor_id: Uuid,
    mut input: RebateScheduleInput,
) -> AppResult<RebateSchedule> {
    prepare_schedule(&mut input)?;
    let mut tx = db.begin().await?;
    let identity: (String, i32) = sqlx::query_as(
        "SELECT name, effective_year FROM finance.customer_rebate_schedules
         WHERE company_id = $1 AND id = $2 FOR UPDATE",
    )
    .bind(company_id)
    .bind(schedule_id)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or(AppError::NotFound("rebate schedule"))?;
    if identity != (input.name.clone(), input.effective_year) {
        return Err(AppError::Validation(
            "A schedule's name and effective year identify it. Create a new schedule to change them"
                .into(),
        ));
    }
    let schedule: RebateSchedule = sqlx::query_as(
        "UPDATE finance.customer_rebate_schedules SET tiers = $3
         WHERE company_id = $1 AND id = $2
         RETURNING id, name, effective_year, tiers",
    )
    .bind(company_id)
    .bind(schedule_id)
    .bind(Json(&input.tiers))
    .fetch_one(&mut *tx)
    .await?;
    record(
        &mut tx,
        company_id,
        actor_id,
        "customer_rebate_schedule",
        schedule.id,
        "updated",
        json!(&schedule),
    )
    .await?;
    tx.commit().await?;
    Ok(schedule)
}

/// Use the same transaction lock for posting documents and changing the turnover inputs.
pub async fn lock_customer(
    conn: &mut PgConnection,
    company_id: Uuid,
    customer_id: Uuid,
) -> AppResult<()> {
    sqlx::query("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))")
        .bind(format!("customer_rebate:{company_id}:{customer_id}"))
        .execute(conn)
        .await?;
    Ok(())
}

async fn require_customer(conn: &mut PgConnection, customer_id: Uuid) -> AppResult<()> {
    sqlx::query_scalar::<_, Uuid>("SELECT id FROM crm.customers WHERE id = $1")
        .bind(customer_id)
        .fetch_optional(conn)
        .await?
        .ok_or(AppError::NotFound("customer"))?;
    Ok(())
}

pub async fn get_assignment(
    db: &PgPool,
    company_id: Uuid,
    customer_id: Uuid,
) -> AppResult<RebateAssignment> {
    let mut conn = db.acquire().await?;
    require_customer(&mut conn, customer_id).await?;
    let schedule_name = sqlx::query_scalar(
        "SELECT schedule_name FROM finance.customer_rebate_assignments
         WHERE company_id = $1 AND customer_id = $2",
    )
    .bind(company_id)
    .bind(customer_id)
    .fetch_optional(&mut *conn)
    .await?;
    Ok(RebateAssignment {
        customer_id,
        schedule_name,
    })
}

pub async fn set_assignment(
    db: &PgPool,
    company_id: Uuid,
    customer_id: Uuid,
    actor_id: Uuid,
    input: RebateAssignmentInput,
) -> AppResult<RebateAssignment> {
    let mut tx = db.begin().await?;
    lock_customer(&mut tx, company_id, customer_id).await?;
    require_customer(&mut tx, customer_id).await?;
    let schedule_name = input.schedule_name.map(|name| name.trim().to_string());
    if let Some(name) = &schedule_name {
        sqlx::query_scalar::<_, Uuid>(
            "SELECT id FROM finance.customer_rebate_schedules WHERE company_id = $1 AND name = $2 LIMIT 1",
        )
        .bind(company_id)
        .bind(name)
        .fetch_optional(&mut *tx)
        .await?
        .ok_or(AppError::NotFound("rebate schedule"))?;
        sqlx::query(
            "INSERT INTO finance.customer_rebate_assignments (company_id, customer_id, schedule_name)
             VALUES ($1, $2, $3)
             ON CONFLICT (company_id, customer_id) DO UPDATE SET schedule_name = EXCLUDED.schedule_name",
        )
        .bind(company_id)
        .bind(customer_id)
        .bind(name)
        .execute(&mut *tx)
        .await?;
    } else {
        sqlx::query(
            "DELETE FROM finance.customer_rebate_assignments WHERE company_id = $1 AND customer_id = $2",
        )
        .bind(company_id)
        .bind(customer_id)
        .execute(&mut *tx)
        .await?;
    }
    let assignment = RebateAssignment {
        customer_id,
        schedule_name,
    };
    record(
        &mut tx,
        company_id,
        actor_id,
        "customer_rebate_assignment",
        customer_id,
        "updated",
        json!(&assignment),
    )
    .await?;
    tx.commit().await?;
    Ok(assignment)
}

pub async fn list_historical_totals(
    db: &PgPool,
    company_id: Uuid,
    customer_id: Uuid,
) -> AppResult<Vec<RebateHistoricalTotal>> {
    let mut conn = db.acquire().await?;
    require_customer(&mut conn, customer_id).await?;
    Ok(sqlx::query_as(
        "SELECT customer_id, year, cutoff, eligible_sales FROM finance.customer_rebate_openings
         WHERE company_id = $1 AND customer_id = $2 ORDER BY year DESC",
    )
    .bind(company_id)
    .bind(customer_id)
    .fetch_all(&mut *conn)
    .await?)
}

fn year_end(year: i32) -> NaiveDate {
    NaiveDate::from_ymd_opt(year, 12, 31).expect("December 31 of a supported calendar year")
}

pub async fn upsert_historical_total(
    db: &PgPool,
    company_id: Uuid,
    customer_id: Uuid,
    actor_id: Uuid,
    input: RebateHistoricalInput,
) -> AppResult<RebateHistoricalTotal> {
    validate_year(input.year)?;
    let previous_year_end = year_end(input.year - 1);
    if !(previous_year_end..=year_end(input.year)).contains(&input.cutoff)
        || input.cutoff > today()
        || (input.cutoff == previous_year_end && !input.eligible_sales.is_zero())
        || !validate_sales(input.eligible_sales)
    {
        return Err(AppError::Validation(
            "Provide a verified cutoff in the sales year and an amount with up to two decimals, or use December 31 of the previous year with a zero opening balance".into(),
        ));
    }
    let mut tx = db.begin().await?;
    lock_customer(&mut tx, company_id, customer_id).await?;
    require_customer(&mut tx, customer_id).await?;
    let changed = sqlx::query(
        "INSERT INTO finance.customer_rebate_openings
            (company_id, customer_id, year, cutoff, eligible_sales, verified_by)
         VALUES ($1, $2, $3, $4, $5, $6)
         ON CONFLICT (company_id, customer_id, year) DO UPDATE
         SET cutoff = EXCLUDED.cutoff, eligible_sales = EXCLUDED.eligible_sales,
             verified_by = EXCLUDED.verified_by, verified_at = now()
         WHERE (customer_rebate_openings.cutoff, customer_rebate_openings.eligible_sales)
             IS DISTINCT FROM (EXCLUDED.cutoff, EXCLUDED.eligible_sales)",
    )
    .bind(company_id)
    .bind(customer_id)
    .bind(input.year)
    .bind(input.cutoff)
    .bind(input.eligible_sales)
    .bind(actor_id)
    .execute(&mut *tx)
    .await?
    .rows_affected();
    let saved = RebateHistoricalTotal {
        customer_id,
        year: input.year,
        cutoff: input.cutoff,
        eligible_sales: input.eligible_sales.normalize(),
    };
    if changed != 0 {
        record(
            &mut tx,
            company_id,
            actor_id,
            "customer_rebate_opening",
            customer_id,
            "verified",
            json!(&saved),
        )
        .await?;
    }
    tx.commit().await?;
    Ok(saved)
}

async fn effective_schedule(
    conn: &mut PgConnection,
    company_id: Uuid,
    customer_id: Uuid,
    rate_year: i32,
) -> AppResult<Option<RebateSchedule>> {
    Ok(sqlx::query_as(
        "SELECT s.id, s.name, s.effective_year, s.tiers
         FROM finance.customer_rebate_assignments a
         JOIN finance.customer_rebate_schedules s ON s.company_id = a.company_id AND s.name = a.schedule_name
         WHERE a.company_id = $1 AND a.customer_id = $2 AND s.effective_year <= $3
         ORDER BY s.effective_year DESC LIMIT 1",
    )
    .bind(company_id)
    .bind(customer_id)
    .bind(rate_year)
    .fetch_optional(conn)
    .await?)
}

fn earned_rate(tiers: &[RebateTier], sales: Decimal) -> Decimal {
    tiers
        .iter()
        .rfind(|tier| sales >= tier.threshold)
        .map_or(Decimal::ZERO, |tier| tier.rate)
}

fn next_tier(tiers: &[RebateTier], sales: Decimal) -> Option<&RebateTier> {
    tiers
        .iter()
        .find(|tier| sales < tier.threshold && tier.rate > Decimal::ZERO)
}

async fn eligible_sales_through(
    conn: &mut PgConnection,
    company_id: Uuid,
    customer_id: Uuid,
    through: NaiveDate,
) -> AppResult<Option<Decimal>> {
    // The verified opening balance already contains every eligible movement through its cutoff.
    // A foreign-currency eligible movement after that cutoff makes the series incomplete.
    Ok(sqlx::query_scalar(
        "SELECT CASE WHEN native.complete THEN b.eligible_sales + native.total END
         FROM finance.customer_rebate_openings b
         JOIN core.companies c ON c.id = b.company_id
         CROSS JOIN LATERAL (
             SELECT COALESCE(SUM(CASE WHEN d.kind = 'credit_note' THEN -l.net_total ELSE l.net_total END)
                                 FILTER (WHERE l.included_in_turnover), 0) AS total,
                    COALESCE(BOOL_AND(CASE l.included_in_turnover
                         WHEN true THEN d.currency = c.currency
                         WHEN false THEN true
                         ELSE false
                    END), true) AS complete
             FROM finance.customer_documents d
             JOIN finance.customer_document_lines l ON l.document_id = d.id
             WHERE d.company_id = b.company_id AND d.customer_id = b.customer_id
                 AND d.status = 'posted' AND NOT d.is_legacy
                 AND d.document_date > b.cutoff AND d.document_date <= $4
         ) native
         WHERE b.company_id = $1 AND b.customer_id = $2 AND b.year = $3 AND b.cutoff <= $4",
    )
    .bind(company_id)
    .bind(customer_id)
    .bind(through.year())
    .bind(through)
    .fetch_optional(conn)
    .await?
    .flatten())
}

async fn build_review(
    conn: &mut PgConnection,
    company_id: Uuid,
    customer_id: Uuid,
    rate_year: i32,
) -> AppResult<(RebateRateReview, Option<RebateSchedule>)> {
    let approved_rate = sqlx::query_scalar(
        "SELECT rate FROM finance.customer_rebate_rates
         WHERE company_id = $1 AND customer_id = $2 AND rate_year = $3",
    )
    .bind(company_id)
    .bind(customer_id)
    .bind(rate_year)
    .fetch_optional(&mut *conn)
    .await?;
    let schedule = effective_schedule(conn, company_id, customer_id, rate_year).await?;
    let eligible_sales = if rate_year <= today().year() {
        eligible_sales_through(conn, company_id, customer_id, year_end(rate_year - 1)).await?
    } else {
        None
    };
    let proposed_rate = eligible_sales
        .zip(schedule.as_ref())
        .map(|(sales, schedule)| earned_rate(&schedule.tiers, sales));
    Ok((
        RebateRateReview {
            customer_id,
            rate_year,
            eligible_sales,
            proposed_rate,
            approved_rate,
        },
        schedule,
    ))
}

pub async fn review_rate(
    db: &PgPool,
    company_id: Uuid,
    customer_id: Uuid,
    rate_year: i32,
) -> AppResult<RebateRateReview> {
    validate_year(rate_year)?;
    let mut conn = db.acquire().await?;
    require_customer(&mut conn, customer_id).await?;
    Ok(build_review(&mut conn, company_id, customer_id, rate_year)
        .await?
        .0)
}

pub async fn approve_rate(
    db: &PgPool,
    company_id: Uuid,
    customer_id: Uuid,
    actor_id: Uuid,
    input: RebateRateApprovalInput,
) -> AppResult<RebateRateReview> {
    validate_year(input.rate_year)?;
    let mut tx = db.begin().await?;
    lock_customer(&mut tx, company_id, customer_id).await?;
    require_customer(&mut tx, customer_id).await?;
    let (mut review, schedule) =
        build_review(&mut tx, company_id, customer_id, input.rate_year).await?;
    if review.approved_rate.is_some() {
        return Ok(review);
    }
    let (Some(schedule), Some(sales), Some(rate)) =
        (schedule, review.eligible_sales, review.proposed_rate)
    else {
        return Err(AppError::Validation(
            "A closed year with verified eligible sales and an effective schedule are required to approve a rate".into(),
        ));
    };
    sqlx::query(
        "INSERT INTO finance.customer_rebate_rates
            (company_id, customer_id, rate_year, schedule_id, eligible_sales, rate, approved_by)
         VALUES ($1, $2, $3, $4, $5, $6, $7)",
    )
    .bind(company_id)
    .bind(customer_id)
    .bind(input.rate_year)
    .bind(schedule.id)
    .bind(sales)
    .bind(rate)
    .bind(actor_id)
    .execute(&mut *tx)
    .await?;
    review.approved_rate = Some(rate);
    record(
        &mut tx,
        company_id,
        actor_id,
        "customer_rebate_rate",
        customer_id,
        "approved",
        json!(&review),
    )
    .await?;
    tx.commit().await?;
    Ok(review)
}

pub async fn invoice_progress(
    conn: &mut PgConnection,
    company_id: Uuid,
    customer_id: Uuid,
    invoice_id: Uuid,
    document_date: NaiveDate,
    language: &str,
) -> AppResult<Option<RebateProgress>> {
    let settings = load_settings(conn, company_id).await?;
    let rate_year = document_date.year() + 1;
    if !settings.show_on_invoices || !(2..=9999).contains(&rate_year) {
        return Ok(None);
    }
    let display_currency: Option<String> = sqlx::query_scalar(
        "SELECT c.currency::text
         FROM finance.customer_documents d JOIN core.companies c ON c.id = d.company_id
         WHERE d.company_id = $1 AND d.customer_id = $2 AND d.id = $3
             AND d.status = 'posted' AND d.kind = 'invoice' AND NOT d.is_legacy
             AND d.currency = c.currency",
    )
    .bind(company_id)
    .bind(customer_id)
    .bind(invoice_id)
    .fetch_optional(&mut *conn)
    .await?;
    let Some(currency) = display_currency else {
        return Ok(None);
    };
    let Some(schedule) = effective_schedule(conn, company_id, customer_id, rate_year).await? else {
        return Ok(None);
    };
    let Some(sales) = eligible_sales_through(conn, company_id, customer_id, document_date).await?
    else {
        return Ok(None);
    };
    let tier = next_tier(&schedule.tiers, sales);
    let wording = settings
        .wording
        .iter()
        .find(|value| value.language == language)
        .or_else(|| settings.wording.iter().find(|value| value.language == "en"))
        .expect("default English rebate wording is always present");
    let amount = |value| format!("{} {currency}", format_amount(value));
    let mut message = if tier.is_some() {
        &wording.active
    } else {
        &wording.highest
    }
    .replace("{eligible_sales}", &amount(sales))
    .replace("{rate_year}", &rate_year.to_string());
    if let Some(tier) = tier {
        message = message
            .replace("{next_threshold}", &amount(tier.threshold))
            .replace("{amount_to_next_tier}", &amount(tier.threshold - sales))
            .replace("{next_rate}", &format!("{} %", format_number(tier.rate)));
    }
    Ok(Some(RebateProgress {
        eligible_sales: sales,
        next_threshold: tier.map(|tier| tier.threshold),
        amount_to_next_tier: tier.map(|tier| tier.threshold - sales),
        next_rate: tier.map(|tier| tier.rate),
        rate_year,
        currency,
        message,
    }))
}

async fn record(
    conn: &mut PgConnection,
    company_id: Uuid,
    actor_id: Uuid,
    entity: &str,
    id: Uuid,
    action: &str,
    data: Value,
) -> AppResult<()> {
    sqlx::query(
        "INSERT INTO audit.events (company_id, user_id, entity, entity_id, action, data)
         VALUES ($1, $2, $3, $4, $5, $6)",
    )
    .bind(company_id)
    .bind(actor_id)
    .bind(entity)
    .bind(id)
    .bind(action)
    .bind(data)
    .execute(conn)
    .await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use rust_decimal_macros::dec;

    #[test]
    fn sales_at_threshold_reach_that_tier() {
        let tiers = [
            RebateTier {
                threshold: dec!(100),
                rate: dec!(2),
            },
            RebateTier {
                threshold: dec!(250),
                rate: dec!(4),
            },
        ];
        assert_eq!(earned_rate(&tiers, dec!(50)), dec!(0));
        assert_eq!(earned_rate(&tiers, dec!(100)), dec!(2));
        assert_eq!(next_tier(&tiers, dec!(100)), Some(&tiers[1]));
        assert_eq!(next_tier(&tiers, dec!(250)), None);
    }

    #[test]
    fn rejects_next_tier_tokens_in_highest_tier_wording() {
        assert!(validate_wording("Sales reached {eligible_sales} for {rate_year}.", false).is_ok());
        assert!(validate_wording("Next threshold is {next_threshold}.", false).is_err());
        assert!(validate_wording("Remaining {amount_to_next_tier}.", true).is_ok());
        assert!(validate_wording("Unknown {rate}.", true).is_err());
        assert!(validate_wording("Missing {eligible_sales", true).is_err());
    }
}
