//! Maintenance contracts. A contract covers a customer (a site, optionally units) and owns visit
//! templates: what to do, how often, who goes. The worker calls [`generate_due_visits`], which
//! creates a planned job `lead_days` before each due date (ADR 0020).

use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::Json;
use chrono::{DateTime, Datelike, Duration, Months, NaiveDate, Utc};
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection, PgPool};
use tradocraft_core::{audit, new_id, AppError, AppResult, AppState, CurrentUser, Permission};
use utoipa::{IntoParams, ToSchema};
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::extras::{check_unit_of_customer, JobEquipment, WARRANTY_STATUS_SQL};
use crate::recurrence::{due_dates, Recurrence};
use crate::{
    check_one_of, list_jobs_inner, ErrorBody, Job, ListParams as JobListParams, Technician, KINDS,
};

pub const STATUSES: [&str; 4] = ["draft", "active", "suspended", "ended"];
pub const RECURRENCES: [&str; 3] = ["weeks", "months", "months_list"];

/// A visit that became due while the worker was not running is still generated this many days late.
const CATCH_UP_DAYS: i64 = 7;
/// An auto-renewing contract is extended by a year when its end is this close.
const RENEW_WITHIN_DAYS: i64 = 30;

/// The priority of generated jobs follows the contract's response target.
pub fn priority_for(response_hours: Option<i32>) -> &'static str {
    match response_hours {
        Some(h) if h <= 4 => "urgent",
        Some(h) if h <= 24 => "high",
        _ => "normal",
    }
}

// ---------------------------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct ContractSummary {
    pub id: Uuid,
    pub number: String,
    pub customer_id: Uuid,
    pub customer_name: String,
    pub title: String,
    /// draft | active | suspended | ended
    pub status: String,
    pub start_date: NaiveDate,
    pub end_date: Option<NaiveDate>,
    pub auto_renew: bool,
    pub response_hours: Option<i32>,
    pub resolution_hours: Option<i32>,
    /// Generated jobs that are not finished.
    pub open_jobs: i64,
}

#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct VisitTemplate {
    pub id: Uuid,
    pub position: i32,
    pub kind: String,
    pub title: String,
    pub instructions: String,
    pub tasks: Vec<String>,
    /// weeks | months | months_list
    pub recurrence: String,
    /// Every N weeks or months.
    pub interval_n: i32,
    /// The months (1-12) of a `months_list` recurrence.
    pub months: Vec<i32>,
    /// The first due date (and the day of the month for `months_list`).
    pub anchor_date: NaiveDate,
    /// The job is generated this many days before the due date.
    pub lead_days: i32,
    pub technicians: Vec<Technician>,
    pub estimated_minutes: Option<i32>,
    pub active: bool,
    /// The next due date from today on, within the contract's term.
    pub next_due: Option<NaiveDate>,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct ContractDetail {
    #[serde(flatten)]
    pub summary: ContractSummary,
    pub contact_id: Option<Uuid>,
    pub contact_name: Option<String>,
    pub site_name: String,
    pub street: String,
    pub postal_code: String,
    pub city: String,
    pub country_code: String,
    pub notes: String,
    pub equipment: Vec<JobEquipment>,
    pub visit_templates: Vec<VisitTemplate>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct TemplateInput {
    /// Give the id of an existing template to change it; without one a new template is made.
    pub id: Option<Uuid>,
    #[serde(default = "default_kind")]
    pub kind: String,
    pub title: String,
    #[serde(default)]
    pub instructions: String,
    #[serde(default)]
    pub tasks: Vec<String>,
    pub recurrence: String,
    #[serde(default = "one")]
    pub interval_n: i32,
    #[serde(default)]
    pub months: Vec<i32>,
    /// The first due date; defaults to the start of the contract.
    #[serde(default, deserialize_with = "tradocraft_core::serde_util::opt_date")]
    pub anchor_date: Option<NaiveDate>,
    #[serde(default = "default_lead")]
    pub lead_days: i32,
    #[serde(default)]
    pub technician_ids: Vec<Uuid>,
    pub estimated_minutes: Option<i32>,
    #[serde(default = "yes")]
    pub active: bool,
}

fn default_kind() -> String {
    "maintenance".into()
}
fn one() -> i32 {
    1
}
fn default_lead() -> i32 {
    14
}
fn yes() -> bool {
    true
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct ContractInput {
    pub customer_id: Uuid,
    pub contact_id: Option<Uuid>,
    pub title: String,
    #[serde(deserialize_with = "tradocraft_core::serde_util::date")]
    pub start_date: NaiveDate,
    #[serde(default, deserialize_with = "tradocraft_core::serde_util::opt_date")]
    pub end_date: Option<NaiveDate>,
    #[serde(default)]
    pub auto_renew: bool,
    pub response_hours: Option<i32>,
    pub resolution_hours: Option<i32>,
    /// The site covered. Left empty, the customer's address is used.
    #[serde(default)]
    pub site_name: String,
    #[serde(default)]
    pub street: String,
    #[serde(default)]
    pub postal_code: String,
    #[serde(default)]
    pub city: String,
    pub country_code: Option<String>,
    #[serde(default)]
    pub notes: String,
    /// Units of the customer covered by the contract.
    #[serde(default)]
    pub equipment_ids: Vec<Uuid>,
    /// The complete set of visit templates; templates left out are removed.
    #[serde(default)]
    pub visit_templates: Vec<TemplateInput>,
}

impl ContractInput {
    fn check(&self) -> AppResult<()> {
        if self.title.trim().is_empty() {
            return Err(AppError::Validation("a title is required".into()));
        }
        if let Some(e) = self.end_date {
            if e < self.start_date {
                return Err(AppError::Validation(
                    "the contract ends before it starts".into(),
                ));
            }
        }
        for h in [self.response_hours, self.resolution_hours]
            .into_iter()
            .flatten()
        {
            if !(1..=24 * 365).contains(&h) {
                return Err(AppError::Validation(
                    "response and resolution hours must be positive".into(),
                ));
            }
        }
        for t in &self.visit_templates {
            if t.title.trim().is_empty() {
                return Err(AppError::Validation("a visit needs a title".into()));
            }
            check_one_of("kind", &t.kind, &KINDS)?;
            check_one_of("recurrence", &t.recurrence, &RECURRENCES)?;
            if !(1..=60).contains(&t.interval_n) {
                return Err(AppError::Validation(
                    "the interval must be between 1 and 60".into(),
                ));
            }
            if !(0..=180).contains(&t.lead_days) {
                return Err(AppError::Validation(
                    "lead days must be between 0 and 180".into(),
                ));
            }
            if t.recurrence == "months_list"
                && (t.months.is_empty() || t.months.iter().any(|m| !(1..=12).contains(m)))
            {
                return Err(AppError::Validation(
                    "choose one or more months (1-12)".into(),
                ));
            }
            if t.estimated_minutes.is_some_and(|m| m <= 0) {
                return Err(AppError::Validation(
                    "the estimated time must be positive".into(),
                ));
            }
        }
        Ok(())
    }
}

// ---------------------------------------------------------------------------------------------
// Loading
// ---------------------------------------------------------------------------------------------

const SELECT: &str = "SELECT k.id, k.number, k.customer_id, c.name AS customer_name, k.title, k.status, k.start_date,
        k.end_date, k.auto_renew, k.response_hours, k.resolution_hours,
        (SELECT count(*) FROM field.jobs j WHERE j.contract_id = k.id AND j.status IN ('planned', 'in_progress')) AS open_jobs
     FROM field.contracts k JOIN crm.customers c ON c.id = k.customer_id";

#[derive(FromRow)]
struct TemplateRow {
    id: Uuid,
    position: i32,
    kind: String,
    title: String,
    instructions: String,
    tasks: Vec<String>,
    recurrence: String,
    interval_n: i32,
    months: Vec<i32>,
    anchor_date: NaiveDate,
    lead_days: i32,
    technician_ids: Vec<Uuid>,
    estimated_minutes: Option<i32>,
    active: bool,
}

fn rule_of(r: &TemplateRow) -> Recurrence {
    match r.recurrence.as_str() {
        "weeks" => Recurrence::Weeks(r.interval_n.max(1) as u32),
        "months" => Recurrence::Months(r.interval_n.max(1) as u32),
        _ => Recurrence::MonthList(r.months.iter().map(|m| *m as u32).collect()),
    }
}

async fn load_templates(conn: &mut PgConnection, contract_id: Uuid) -> AppResult<Vec<TemplateRow>> {
    Ok(sqlx::query_as(
        "SELECT id, position, kind, title, instructions, tasks, recurrence, interval_n, months, anchor_date,
                lead_days, technician_ids, estimated_minutes, active
         FROM field.contract_visit_templates WHERE contract_id = $1 ORDER BY position",
    )
    .bind(contract_id)
    .fetch_all(conn)
    .await?)
}

#[derive(FromRow)]
struct ContractExtra {
    contact_id: Option<Uuid>,
    contact_name: Option<String>,
    site_name: String,
    street: String,
    postal_code: String,
    city: String,
    country_code: String,
    notes: String,
    created_at: DateTime<Utc>,
}

async fn load_contract(
    conn: &mut PgConnection,
    company_id: Uuid,
    id: Uuid,
) -> AppResult<ContractDetail> {
    let summary: ContractSummary = sqlx::query_as(sqlx::AssertSqlSafe(format!(
        "{SELECT} WHERE k.id = $1 AND k.company_id = $2"
    )))
    .bind(id)
    .bind(company_id)
    .fetch_optional(&mut *conn)
    .await?
    .ok_or(AppError::NotFound("contract"))?;
    let extra: ContractExtra = sqlx::query_as(
        "SELECT k.contact_id, nullif(btrim(ct.first_name || ' ' || ct.last_name), '') AS contact_name,
                k.site_name, k.street, k.postal_code, k.city, k.country_code::text AS country_code, k.notes, k.created_at
         FROM field.contracts k LEFT JOIN crm.contacts ct ON ct.id = k.contact_id WHERE k.id = $1",
    )
    .bind(id)
    .fetch_one(&mut *conn)
    .await?;
    let equipment: Vec<JobEquipment> = sqlx::query_as(sqlx::AssertSqlSafe(format!(
        "SELECT s.id AS serial_unit_id, p.code AS product_code, p.name AS product_name, s.serial_number, s.status,
                s.warranty_until, s.warranty_note, {WARRANTY_STATUS_SQL} AS warranty_status
         FROM field.contract_equipment e JOIN engineering.serial_units s ON s.id = e.serial_unit_id
         JOIN products.products p ON p.id = s.product_id
         WHERE e.contract_id = $1 ORDER BY p.code, s.serial_number"
    )))
    .bind(id)
    .fetch_all(&mut *conn)
    .await?;
    let rows = load_templates(conn, id).await?;
    let all_techs: Vec<Uuid> = rows.iter().flat_map(|r| r.technician_ids.clone()).collect();
    let names: Vec<(Uuid, String)> =
        sqlx::query_as("SELECT id, display_name FROM core.users WHERE id = ANY($1)")
            .bind(&all_techs)
            .fetch_all(&mut *conn)
            .await?;
    let today = Utc::now().date_naive();
    let visit_templates = rows
        .into_iter()
        .map(|r| {
            let rule = rule_of(&r);
            let next_due = if summary.status == "ended" {
                None
            } else {
                let to = summary.end_date.unwrap_or_else(|| today + Months::new(120));
                due_dates(&rule, r.anchor_date, today.max(summary.start_date), to)
                    .into_iter()
                    .next()
            };
            VisitTemplate {
                technicians: r
                    .technician_ids
                    .iter()
                    .filter_map(|u| {
                        names.iter().find(|(i, _)| i == u).map(|(i, n)| Technician {
                            user_id: *i,
                            display_name: n.clone(),
                        })
                    })
                    .collect(),
                id: r.id,
                position: r.position,
                kind: r.kind,
                title: r.title,
                instructions: r.instructions,
                tasks: r.tasks,
                recurrence: r.recurrence,
                interval_n: r.interval_n,
                months: r.months,
                anchor_date: r.anchor_date,
                lead_days: r.lead_days,
                estimated_minutes: r.estimated_minutes,
                active: r.active,
                next_due,
            }
        })
        .collect();
    Ok(ContractDetail {
        summary,
        contact_id: extra.contact_id,
        contact_name: extra.contact_name,
        site_name: extra.site_name,
        street: extra.street,
        postal_code: extra.postal_code,
        city: extra.city,
        country_code: extra.country_code,
        notes: extra.notes,
        equipment,
        visit_templates,
        created_at: extra.created_at,
    })
}

// ---------------------------------------------------------------------------------------------
// Listing and reading
// ---------------------------------------------------------------------------------------------

#[derive(Debug, Deserialize, IntoParams)]
pub struct ListParams {
    /// Searches number, title and customer.
    pub q: Option<String>,
    /// draft | active | suspended | ended
    pub status: Option<String>,
    pub customer_id: Option<Uuid>,
}

#[utoipa::path(get, path = "/field/contracts", tag = "field", operation_id = "list_contracts", params(ListParams),
    responses((status = 200, body = Vec<ContractSummary>)))]
async fn list_contracts(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(p): Query<ListParams>,
) -> AppResult<Json<Vec<ContractSummary>>> {
    user.require(Permission::FieldRead)?;
    let pattern =
        p.q.as_deref()
            .map(str::trim)
            .filter(|q| !q.is_empty())
            .map(|q| format!("%{}%", q.to_lowercase()));
    let status = p.status.as_deref().filter(|s| *s != "all");
    let rows = sqlx::query_as(sqlx::AssertSqlSafe(format!(
        "{SELECT} WHERE k.company_id = $1
           AND ($2::text IS NULL OR lower(k.number) LIKE $2 OR lower(k.title) LIKE $2 OR lower(c.name) LIKE $2)
           AND ($3::text IS NULL OR k.status = $3)
           AND ($4::uuid IS NULL OR k.customer_id = $4)
         ORDER BY (k.status = 'ended'), k.number DESC LIMIT 300"
    )))
    .bind(user.company_id)
    .bind(pattern)
    .bind(status)
    .bind(p.customer_id)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows))
}

#[utoipa::path(get, path = "/field/contracts/{id}", tag = "field", operation_id = "get_contract",
    params(("id" = Uuid, Path)), responses((status = 200, body = ContractDetail), (status = 404, body = ErrorBody)))]
async fn get_contract(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<ContractDetail>> {
    user.require(Permission::FieldRead)?;
    let mut conn = state.db.acquire().await?;
    Ok(Json(load_contract(&mut conn, user.company_id, id).await?))
}

// ---------------------------------------------------------------------------------------------
// Writing
// ---------------------------------------------------------------------------------------------

/// Validates links and returns the technicians' ids checked against the company.
async fn validate_links(
    conn: &mut PgConnection,
    user: &CurrentUser,
    input: &ContractInput,
) -> AppResult<()> {
    tradocraft_crm::get_customer(&mut *conn, user.company_id, input.customer_id).await?;
    if let Some(c) = input.contact_id {
        let contact = tradocraft_crm::contacts::get_contact(conn, c).await?;
        if contact.customer_id != input.customer_id {
            return Err(AppError::Validation(
                "the contact does not work for this customer".into(),
            ));
        }
    }
    let mut techs: Vec<Uuid> = input
        .visit_templates
        .iter()
        .flat_map(|t| t.technician_ids.clone())
        .collect();
    techs.sort();
    techs.dedup();
    let valid: i64 = sqlx::query_scalar(
        "SELECT count(DISTINCT user_id) FROM core.user_companies WHERE company_id = $1 AND user_id = ANY($2)",
    )
    .bind(user.company_id)
    .bind(&techs)
    .fetch_one(&mut *conn)
    .await?;
    if valid as usize != techs.len() {
        return Err(AppError::Validation(
            "a technician is not a colleague in this company".into(),
        ));
    }
    for u in &input.equipment_ids {
        check_unit_of_customer(conn, user.company_id, *u, input.customer_id).await?;
    }
    Ok(())
}

async fn save_children(
    conn: &mut PgConnection,
    contract_id: Uuid,
    input: &ContractInput,
) -> AppResult<()> {
    sqlx::query("DELETE FROM field.contract_equipment WHERE contract_id = $1")
        .bind(contract_id)
        .execute(&mut *conn)
        .await?;
    let mut units = input.equipment_ids.clone();
    units.sort();
    units.dedup();
    for u in units {
        sqlx::query(
            "INSERT INTO field.contract_equipment (contract_id, serial_unit_id) VALUES ($1, $2)",
        )
        .bind(contract_id)
        .bind(u)
        .execute(&mut *conn)
        .await?;
    }
    let existing: Vec<Uuid> =
        sqlx::query_scalar("SELECT id FROM field.contract_visit_templates WHERE contract_id = $1")
            .bind(contract_id)
            .fetch_all(&mut *conn)
            .await?;
    let keep: Vec<Uuid> = input
        .visit_templates
        .iter()
        .filter_map(|t| t.id)
        .filter(|i| existing.contains(i))
        .collect();
    sqlx::query(
        "DELETE FROM field.contract_visit_templates WHERE contract_id = $1 AND NOT (id = ANY($2))",
    )
    .bind(contract_id)
    .bind(&keep)
    .execute(&mut *conn)
    .await?;
    // Positions are unique: move the kept templates out of the way first.
    sqlx::query("UPDATE field.contract_visit_templates SET position = position + 1000 WHERE contract_id = $1")
        .bind(contract_id)
        .execute(&mut *conn)
        .await?;
    for (i, t) in input.visit_templates.iter().enumerate() {
        let tasks: Vec<String> = t
            .tasks
            .iter()
            .map(|x| x.trim().to_string())
            .filter(|x| !x.is_empty())
            .collect();
        let mut months = t.months.clone();
        months.sort_unstable();
        months.dedup();
        if t.recurrence != "months_list" {
            months.clear();
        }
        let mut techs = t.technician_ids.clone();
        techs.sort();
        techs.dedup();
        let anchor = t.anchor_date.unwrap_or(input.start_date);
        let id = t.id.filter(|i| existing.contains(i));
        match id {
            Some(id) => {
                sqlx::query(
                    "UPDATE field.contract_visit_templates SET position = $2, kind = $3, title = $4, instructions = $5,
                            tasks = $6, recurrence = $7, interval_n = $8, months = $9, anchor_date = $10, lead_days = $11,
                            technician_ids = $12, estimated_minutes = $13, active = $14 WHERE id = $1",
                )
                .bind(id)
                .bind(i as i32 + 1)
                .bind(&t.kind)
                .bind(t.title.trim())
                .bind(t.instructions.trim())
                .bind(&tasks)
                .bind(&t.recurrence)
                .bind(t.interval_n)
                .bind(&months)
                .bind(anchor)
                .bind(t.lead_days)
                .bind(&techs)
                .bind(t.estimated_minutes)
                .bind(t.active)
                .execute(&mut *conn)
                .await?;
            }
            None => {
                sqlx::query(
                    "INSERT INTO field.contract_visit_templates (id, contract_id, position, kind, title, instructions, tasks,
                            recurrence, interval_n, months, anchor_date, lead_days, technician_ids, estimated_minutes, active)
                     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15)",
                )
                .bind(new_id())
                .bind(contract_id)
                .bind(i as i32 + 1)
                .bind(&t.kind)
                .bind(t.title.trim())
                .bind(t.instructions.trim())
                .bind(&tasks)
                .bind(&t.recurrence)
                .bind(t.interval_n)
                .bind(&months)
                .bind(anchor)
                .bind(t.lead_days)
                .bind(&techs)
                .bind(t.estimated_minutes)
                .bind(t.active)
                .execute(&mut *conn)
                .await?;
            }
        }
    }
    Ok(())
}

#[utoipa::path(post, path = "/field/contracts", tag = "field", operation_id = "create_contract", request_body = ContractInput,
    responses((status = 201, body = ContractDetail), (status = 403, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn create_contract(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<ContractInput>,
) -> AppResult<(StatusCode, Json<ContractDetail>)> {
    user.require(Permission::FieldPlan)?;
    input.check()?;
    let mut tx = state.db.begin().await?;
    validate_links(&mut tx, &user, &input).await?;
    let year = Utc::now().year();
    let n = tradocraft_core::numbering::next_number(&mut tx, user.company_id, "SC", year).await?;
    let number = format!("SC{year}-{n:05}");
    let id = new_id();
    sqlx::query(
        "INSERT INTO field.contracts (id, company_id, number, customer_id, contact_id, title, start_date, end_date, auto_renew,
                response_hours, resolution_hours, site_name, street, postal_code, city, country_code, notes, created_by)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18)",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(&number)
    .bind(input.customer_id)
    .bind(input.contact_id)
    .bind(input.title.trim())
    .bind(input.start_date)
    .bind(input.end_date)
    .bind(input.auto_renew)
    .bind(input.response_hours)
    .bind(input.resolution_hours)
    .bind(input.site_name.trim())
    .bind(input.street.trim())
    .bind(input.postal_code.trim())
    .bind(input.city.trim())
    .bind(input.country_code.clone().unwrap_or_else(|| "BE".into()).to_uppercase())
    .bind(input.notes.trim())
    .bind(user.user_id)
    .execute(&mut *tx)
    .await?;
    save_children(&mut tx, id, &input).await?;
    audit::record(
        &mut tx,
        &user,
        "contract",
        id,
        "created",
        serde_json::json!({ "number": number }),
    )
    .await?;
    let d = load_contract(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(d)))
}

#[utoipa::path(put, path = "/field/contracts/{id}", tag = "field", operation_id = "update_contract",
    params(("id" = Uuid, Path)), request_body = ContractInput,
    responses((status = 200, body = ContractDetail), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn update_contract(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<ContractInput>,
) -> AppResult<Json<ContractDetail>> {
    user.require(Permission::FieldPlan)?;
    input.check()?;
    let mut tx = state.db.begin().await?;
    let current = lock_contract(&mut tx, user.company_id, id).await?;
    if current.status == "ended" {
        return Err(AppError::Conflict("the contract has ended".into()));
    }
    if current.status != "draft" && current.customer_id != input.customer_id {
        return Err(AppError::Conflict(
            "the customer of a started contract cannot change".into(),
        ));
    }
    validate_links(&mut tx, &user, &input).await?;
    sqlx::query(
        "UPDATE field.contracts SET customer_id = $2, contact_id = $3, title = $4, start_date = $5, end_date = $6,
                auto_renew = $7, response_hours = $8, resolution_hours = $9, site_name = $10, street = $11,
                postal_code = $12, city = $13, country_code = $14, notes = $15, updated_at = now() WHERE id = $1",
    )
    .bind(id)
    .bind(input.customer_id)
    .bind(input.contact_id)
    .bind(input.title.trim())
    .bind(input.start_date)
    .bind(input.end_date)
    .bind(input.auto_renew)
    .bind(input.response_hours)
    .bind(input.resolution_hours)
    .bind(input.site_name.trim())
    .bind(input.street.trim())
    .bind(input.postal_code.trim())
    .bind(input.city.trim())
    .bind(input.country_code.clone().unwrap_or_else(|| "BE".into()).to_uppercase())
    .bind(input.notes.trim())
    .execute(&mut *tx)
    .await?;
    save_children(&mut tx, id, &input).await?;
    audit::record(
        &mut tx,
        &user,
        "contract",
        id,
        "updated",
        serde_json::json!({}),
    )
    .await?;
    let d = load_contract(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok(Json(d))
}

#[derive(FromRow)]
struct Locked {
    status: String,
    customer_id: Uuid,
}

async fn lock_contract(conn: &mut PgConnection, company_id: Uuid, id: Uuid) -> AppResult<Locked> {
    sqlx::query_as("SELECT status, customer_id FROM field.contracts WHERE id = $1 AND company_id = $2 FOR UPDATE")
        .bind(id)
        .bind(company_id)
        .fetch_optional(conn)
        .await?
        .ok_or(AppError::NotFound("contract"))
}

async fn change_status(
    state: &AppState,
    user: &CurrentUser,
    id: Uuid,
    from: &[&str],
    to: &str,
    action: &str,
) -> AppResult<Json<ContractDetail>> {
    user.require(Permission::FieldPlan)?;
    let mut tx = state.db.begin().await?;
    let current = lock_contract(&mut tx, user.company_id, id).await?;
    if !from.contains(&current.status.as_str()) {
        return Err(AppError::Conflict(format!(
            "the contract is {}; it cannot be {action}",
            current.status
        )));
    }
    sqlx::query(
        "UPDATE field.contracts SET status = $2, updated_at = now(),
                end_date = CASE WHEN $2 = 'ended' THEN greatest(start_date, least(coalesce(end_date, current_date), current_date)) ELSE end_date END
         WHERE id = $1",
    )
    .bind(id)
    .bind(to)
    .execute(&mut *tx)
    .await?;
    audit::record(
        &mut tx,
        user,
        "contract",
        id,
        action,
        serde_json::json!({ "from": current.status }),
    )
    .await?;
    let d = load_contract(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok(Json(d))
}

/// Starts a draft contract, or resumes a suspended one: planned jobs are generated again.
#[utoipa::path(post, path = "/field/contracts/{id}/activate", tag = "field", operation_id = "activate_contract",
    params(("id" = Uuid, Path)), responses((status = 200, body = ContractDetail), (status = 409, body = ErrorBody)))]
async fn activate_contract(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<ContractDetail>> {
    change_status(
        &state,
        &user,
        id,
        &["draft", "suspended"],
        "active",
        "activated",
    )
    .await
}

/// Pauses a contract: no jobs are generated until it is activated again.
#[utoipa::path(post, path = "/field/contracts/{id}/suspend", tag = "field", operation_id = "suspend_contract",
    params(("id" = Uuid, Path)), responses((status = 200, body = ContractDetail), (status = 409, body = ErrorBody)))]
async fn suspend_contract(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<ContractDetail>> {
    change_status(&state, &user, id, &["active"], "suspended", "suspended").await
}

/// Ends a contract for good. Jobs already generated stay.
#[utoipa::path(post, path = "/field/contracts/{id}/end", tag = "field", operation_id = "end_contract",
    params(("id" = Uuid, Path)), responses((status = 200, body = ContractDetail), (status = 409, body = ErrorBody)))]
async fn end_contract(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<ContractDetail>> {
    change_status(
        &state,
        &user,
        id,
        &["draft", "active", "suspended"],
        "ended",
        "ended",
    )
    .await
}

// ---------------------------------------------------------------------------------------------
// Upcoming visits and the contract's jobs
// ---------------------------------------------------------------------------------------------

#[derive(Debug, Deserialize, IntoParams)]
pub struct UpcomingParams {
    /// Look ahead to this date (YYYY-MM-DD). Default: twelve months from today (at most 36).
    pub until: Option<String>,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct UpcomingVisit {
    pub template_id: Uuid,
    pub title: String,
    pub kind: String,
    pub due_date: NaiveDate,
    /// The day the job is (or was) generated.
    pub generate_on: NaiveDate,
    /// The job, once generated.
    pub job_id: Option<Uuid>,
    pub job_number: Option<String>,
}

/// The visits due from today on, from the active templates, and whether their job exists.
#[utoipa::path(get, path = "/field/contracts/{id}/upcoming", tag = "field", operation_id = "list_contract_upcoming",
    params(("id" = Uuid, Path), UpcomingParams), responses((status = 200, body = Vec<UpcomingVisit>)))]
async fn upcoming(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Query(p): Query<UpcomingParams>,
) -> AppResult<Json<Vec<UpcomingVisit>>> {
    user.require(Permission::FieldRead)?;
    let mut conn = state.db.acquire().await?;
    let c = load_contract(&mut conn, user.company_id, id).await?;
    let today = Utc::now().date_naive();
    let until = p
        .until
        .as_deref()
        .map(|s| {
            s.get(..10)
                .and_then(|d| NaiveDate::parse_from_str(d, "%Y-%m-%d").ok())
                .ok_or_else(|| AppError::Validation("until must be a date (YYYY-MM-DD)".into()))
        })
        .transpose()?;
    let mut to = until
        .unwrap_or_else(|| today + Months::new(12))
        .min(today + Months::new(36));
    if let Some(e) = c.summary.end_date {
        to = to.min(e);
    }
    let from = today.max(c.summary.start_date);
    let generated: Vec<(Uuid, NaiveDate, Option<Uuid>, Option<String>)> = sqlx::query_as(
        "SELECT v.template_id, v.due_date, v.job_id, j.number FROM field.contract_visits v
         LEFT JOIN field.jobs j ON j.id = v.job_id WHERE v.contract_id = $1 AND v.due_date >= $2",
    )
    .bind(id)
    .bind(from)
    .fetch_all(&mut *conn)
    .await?;
    let rows = load_templates(&mut conn, id).await?;
    let mut out = Vec::new();
    if c.summary.status != "ended" {
        for r in rows.iter().filter(|r| r.active) {
            for d in due_dates(&rule_of(r), r.anchor_date, from, to) {
                let g = generated
                    .iter()
                    .find(|(t, due, _, _)| *t == r.id && *due == d);
                out.push(UpcomingVisit {
                    template_id: r.id,
                    title: r.title.clone(),
                    kind: r.kind.clone(),
                    due_date: d,
                    generate_on: d - Duration::days(i64::from(r.lead_days)),
                    job_id: g.and_then(|x| x.2),
                    job_number: g.and_then(|x| x.3.clone()),
                });
            }
        }
    }
    out.sort_by(|a, b| a.due_date.cmp(&b.due_date).then(a.title.cmp(&b.title)));
    Ok(Json(out))
}

/// The jobs generated for (or linked to) a contract, newest first.
#[utoipa::path(get, path = "/field/contracts/{id}/jobs", tag = "field", operation_id = "list_contract_jobs",
    params(("id" = Uuid, Path)), responses((status = 200, body = Vec<Job>), (status = 404, body = ErrorBody)))]
async fn contract_jobs(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<Vec<Job>>> {
    user.require(Permission::FieldRead)?;
    let mut conn = state.db.acquire().await?;
    load_contract(&mut conn, user.company_id, id).await?;
    let p = JobListParams {
        q: None,
        status: None,
        technician: None,
        customer_id: None,
        contract_id: Some(id),
        from: None,
        to: None,
    };
    Ok(Json(
        list_jobs_inner(&mut conn, &user, &p, false, false).await?,
    ))
}

// ---------------------------------------------------------------------------------------------
// Generating the planned jobs (called by the worker)
// ---------------------------------------------------------------------------------------------

/// What one pass of the generator did.
#[derive(Debug, Default, PartialEq, Eq)]
pub struct Generated {
    pub jobs: u32,
    pub renewed: u32,
}

#[derive(FromRow)]
struct DueTemplate {
    contract_id: Uuid,
    start_date: NaiveDate,
    end_date: Option<NaiveDate>,
    #[sqlx(flatten)]
    t: TemplateRow,
}

/// Extends auto-renewing contracts that are about to end, then creates the planned job of every
/// visit that is due within its `lead_days` (or became due in the last week while nobody looked).
/// Running it again, even at the same moment from several workers, creates nothing twice: a visit
/// is unique per template and due date. Suspended and ended contracts are skipped, and no visit
/// after the end date of a contract is generated.
pub async fn generate_due_visits(db: &PgPool, today: NaiveDate) -> AppResult<Generated> {
    let mut out = Generated::default();
    let renewable: Vec<(Uuid, Uuid, NaiveDate)> = sqlx::query_as(
        "SELECT id, company_id, end_date FROM field.contracts
         WHERE status = 'active' AND auto_renew AND end_date IS NOT NULL AND end_date <= $1",
    )
    .bind(today + Duration::days(RENEW_WITHIN_DAYS))
    .fetch_all(db)
    .await?;
    for (id, company_id, end) in renewable {
        let mut new_end = end;
        while new_end <= today + Duration::days(RENEW_WITHIN_DAYS) {
            new_end = new_end + Months::new(12);
        }
        let mut tx = db.begin().await?;
        let changed = sqlx::query(
            "UPDATE field.contracts SET end_date = $2, updated_at = now() WHERE id = $1 AND status = 'active' AND end_date = $3",
        )
        .bind(id)
        .bind(new_end)
        .bind(end)
        .execute(&mut *tx)
        .await?;
        if changed.rows_affected() == 1 {
            audit::record_system(
                &mut tx,
                company_id,
                "contract",
                id,
                "renewed",
                serde_json::json!({ "end_date": new_end }),
            )
            .await?;
            out.renewed += 1;
        }
        tx.commit().await?;
    }

    let templates: Vec<DueTemplate> = sqlx::query_as(
        "SELECT t.contract_id, k.start_date, k.end_date, t.id, t.position, t.kind, t.title, t.instructions, t.tasks,
                t.recurrence, t.interval_n, t.months, t.anchor_date, t.lead_days, t.technician_ids,
                t.estimated_minutes, t.active
         FROM field.contract_visit_templates t JOIN field.contracts k ON k.id = t.contract_id
         WHERE k.status = 'active' AND t.active AND k.start_date <= $1::date + 180
         ORDER BY k.number, t.position",
    )
    .bind(today)
    .fetch_all(db)
    .await?;
    for d in templates {
        let mut to = today + Duration::days(i64::from(d.t.lead_days));
        if let Some(e) = d.end_date {
            to = to.min(e);
        }
        let from = (today - Duration::days(CATCH_UP_DAYS)).max(d.start_date);
        for due in due_dates(&rule_of(&d.t), d.t.anchor_date, from, to) {
            let mut tx = db.begin().await?;
            if generate_one(&mut tx, d.contract_id, &d.t, due).await? {
                tx.commit().await?;
                out.jobs += 1;
            } else {
                tx.rollback().await?;
            }
        }
    }
    Ok(out)
}

#[derive(FromRow)]
struct ContractForJob {
    company_id: Uuid,
    status: String,
    customer_id: Uuid,
    contact_id: Option<Uuid>,
    response_hours: Option<i32>,
    site_name: String,
    street: String,
    postal_code: String,
    city: String,
    country_code: String,
    number: String,
}

/// Creates the job of one visit in the caller's transaction. False when it exists already or the
/// contract is no longer active.
async fn generate_one(
    conn: &mut PgConnection,
    contract_id: Uuid,
    t: &TemplateRow,
    due: NaiveDate,
) -> AppResult<bool> {
    let k: ContractForJob = sqlx::query_as(
        "SELECT k.company_id, k.status, k.customer_id, k.contact_id, k.response_hours,
                k.site_name,
                CASE WHEN k.street <> '' OR k.city <> '' THEN k.street ELSE c.street END AS street,
                CASE WHEN k.street <> '' OR k.city <> '' THEN k.postal_code ELSE c.postal_code END AS postal_code,
                CASE WHEN k.street <> '' OR k.city <> '' THEN k.city ELSE c.city END AS city,
                CASE WHEN k.street <> '' OR k.city <> '' THEN k.country_code::text ELSE c.country_code::text END AS country_code,
                k.number
         FROM field.contracts k JOIN crm.customers c ON c.id = k.customer_id WHERE k.id = $1 FOR SHARE OF k",
    )
    .bind(contract_id)
    .fetch_one(&mut *conn)
    .await?;
    if k.status != "active" {
        return Ok(false);
    }
    let visit_id = new_id();
    let claimed = sqlx::query(
        "INSERT INTO field.contract_visits (id, contract_id, template_id, due_date) VALUES ($1, $2, $3, $4)
         ON CONFLICT (template_id, due_date) DO NOTHING",
    )
    .bind(visit_id)
    .bind(contract_id)
    .bind(t.id)
    .bind(due)
    .execute(&mut *conn)
    .await?;
    if claimed.rows_affected() == 0 {
        return Ok(false);
    }
    let number = crate::next_job_number(conn, k.company_id).await?;
    let job_id = new_id();
    let mut instructions = t.instructions.clone();
    if let Some(m) = t.estimated_minutes {
        if !instructions.is_empty() {
            instructions.push_str("\n\n");
        }
        instructions.push_str(&format!("Estimated time: {m} min."));
    }
    sqlx::query(
        "INSERT INTO field.jobs (id, company_id, number, kind, priority, title, instructions, customer_id, contact_id,
                                 site_name, street, postal_code, city, country_code, contract_id, due_date)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16)",
    )
    .bind(job_id)
    .bind(k.company_id)
    .bind(&number)
    .bind(&t.kind)
    .bind(priority_for(k.response_hours))
    .bind(&t.title)
    .bind(&instructions)
    .bind(k.customer_id)
    .bind(k.contact_id)
    .bind(&k.site_name)
    .bind(&k.street)
    .bind(&k.postal_code)
    .bind(&k.city)
    .bind(&k.country_code)
    .bind(contract_id)
    .bind(due)
    .execute(&mut *conn)
    .await?;
    // Only technicians who still work for the company.
    sqlx::query(
        "INSERT INTO field.job_technicians (job_id, user_id)
         SELECT $1, user_id FROM core.user_companies WHERE company_id = $2 AND user_id = ANY($3)
         ON CONFLICT DO NOTHING",
    )
    .bind(job_id)
    .bind(k.company_id)
    .bind(&t.technician_ids)
    .execute(&mut *conn)
    .await?;
    for (i, task) in t.tasks.iter().filter(|x| !x.trim().is_empty()).enumerate() {
        sqlx::query("INSERT INTO field.job_tasks (id, job_id, position, description) VALUES ($1, $2, $3, $4)")
            .bind(new_id())
            .bind(job_id)
            .bind(i as i32 + 1)
            .bind(task.trim())
            .execute(&mut *conn)
            .await?;
    }
    sqlx::query(
        "INSERT INTO field.job_equipment (job_id, serial_unit_id)
         SELECT $1, serial_unit_id FROM field.contract_equipment WHERE contract_id = $2",
    )
    .bind(job_id)
    .bind(contract_id)
    .execute(&mut *conn)
    .await?;
    sqlx::query("UPDATE field.contract_visits SET job_id = $2 WHERE id = $1")
        .bind(visit_id)
        .bind(job_id)
        .execute(&mut *conn)
        .await?;
    audit::record_system(
        conn,
        k.company_id,
        "job",
        job_id,
        "generated",
        serde_json::json!({ "contract": k.number, "contract_id": contract_id, "template_id": t.id, "due_date": due }),
    )
    .await?;
    Ok(true)
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(list_contracts, create_contract))
        .routes(routes!(get_contract, update_contract))
        .routes(routes!(activate_contract))
        .routes(routes!(suspend_contract))
        .routes(routes!(end_contract))
        .routes(routes!(upcoming))
        .routes(routes!(contract_jobs))
}

#[cfg(test)]
mod tests {
    use super::priority_for;

    #[test]
    fn the_response_target_sets_the_priority_of_generated_jobs() {
        assert_eq!(priority_for(None), "normal");
        assert_eq!(priority_for(Some(2)), "urgent");
        assert_eq!(priority_for(Some(4)), "urgent");
        assert_eq!(priority_for(Some(24)), "high");
        assert_eq!(priority_for(Some(72)), "normal");
    }
}
