//! Field service: jobs at a customer's site, done by technicians.
//!
//! A planner (`field.plan`) creates a job, says where to go, what to do (instructions and a task
//! checklist) and who goes. A technician (`field.work`) sees only the jobs assigned to them, starts
//! a job, ticks tasks, logs work and travel time, adds photos and completes it. Facts recorded by
//! the technician take a client-generated id, so an upload retried from a phone that was offline
//! cannot create duplicates (ADR 0006).

use axum::body::Bytes;
use axum::extract::{DefaultBodyLimit, Path, Query, State};
use axum::http::StatusCode;
use axum::response::Response;
use axum::Json;
use chrono::{DateTime, Datelike, Duration, NaiveDate, Utc};
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection};
use tradocraft_core::files::{self, MAX_FILE_BYTES};
use tradocraft_core::{audit, new_id, AppError, AppResult, AppState, CurrentUser, Permission};
use utoipa::{IntoParams, ToSchema};
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

pub mod contracts;
pub mod extras;
pub mod recurrence;
pub mod report;

use extras::{JobEquipment, JobPart, JobSignature};

type ErrorBody = tradocraft_core::error::ErrorBody;

pub const KINDS: [&str; 5] = [
    "installation",
    "maintenance",
    "repair",
    "inspection",
    "other",
];
pub const PRIORITIES: [&str; 4] = ["low", "normal", "high", "urgent"];

/// Percent-encodes for a URL query value.
fn url_encode(s: &str) -> String {
    let mut out = String::new();
    for b in s.bytes() {
        if b.is_ascii_alphanumeric() || matches!(b, b'-' | b'_' | b'.' | b'~') {
            out.push(b as char);
        } else {
            out.push_str(&format!("%{b:02X}"));
        }
    }
    out
}

/// A link that opens navigation to the site: exact coordinates when known, else the address.
pub fn maps_url(lat: Option<f64>, lon: Option<f64>, address: &str) -> Option<String> {
    let query = match (lat, lon) {
        (Some(la), Some(lo)) => format!("{la},{lo}"),
        _ if address.trim().is_empty() => return None,
        _ => address.to_string(),
    };
    Some(format!(
        "https://www.google.com/maps/search/?api=1&query={}",
        url_encode(&query)
    ))
}

#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct Technician {
    pub user_id: Uuid,
    pub display_name: String,
}

#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct Job {
    pub id: Uuid,
    pub number: String,
    /// installation | maintenance | repair | inspection | other
    pub kind: String,
    /// planned | in_progress | completed | cancelled
    pub status: String,
    pub priority: String,
    pub title: String,
    /// What has to be done there.
    pub instructions: String,
    pub customer_id: Uuid,
    pub customer_name: String,
    /// The person to meet on site.
    pub contact_id: Option<Uuid>,
    pub contact_name: Option<String>,
    pub ticket_id: Option<Uuid>,
    pub repair_id: Option<Uuid>,
    pub site_name: String,
    pub street: String,
    pub postal_code: String,
    pub city: String,
    pub country_code: String,
    /// The address on one line.
    pub address: String,
    pub latitude: Option<f64>,
    pub longitude: Option<f64>,
    /// Opens navigation to the site.
    pub maps_url: Option<String>,
    pub scheduled_start: Option<DateTime<Utc>>,
    pub scheduled_end: Option<DateTime<Utc>>,
    pub started_at: Option<DateTime<Utc>>,
    pub completed_at: Option<DateTime<Utc>>,
    pub completion_notes: String,
    pub technicians: Vec<Technician>,
    pub tasks_total: i64,
    pub tasks_done: i64,
    /// The maintenance contract this job was generated for.
    pub contract_id: Option<Uuid>,
    pub contract_number: Option<String>,
    /// The day a contract visit is due.
    pub due_date: Option<NaiveDate>,
    /// When the service report was last e-mailed to the customer.
    pub report_sent_at: Option<DateTime<Utc>>,
    pub report_sent_to: String,
}

#[derive(FromRow)]
struct JobRow {
    id: Uuid,
    number: String,
    kind: String,
    status: String,
    priority: String,
    title: String,
    instructions: String,
    customer_id: Uuid,
    customer_name: String,
    contact_id: Option<Uuid>,
    contact_name: Option<String>,
    ticket_id: Option<Uuid>,
    repair_id: Option<Uuid>,
    site_name: String,
    street: String,
    postal_code: String,
    city: String,
    country_code: String,
    latitude: Option<f64>,
    longitude: Option<f64>,
    scheduled_start: Option<DateTime<Utc>>,
    scheduled_end: Option<DateTime<Utc>>,
    started_at: Option<DateTime<Utc>>,
    completed_at: Option<DateTime<Utc>>,
    completion_notes: String,
    tasks_total: i64,
    tasks_done: i64,
    contract_id: Option<Uuid>,
    contract_number: Option<String>,
    due_date: Option<NaiveDate>,
    report_sent_at: Option<DateTime<Utc>>,
    report_sent_to: String,
}

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct Task {
    pub id: Uuid,
    pub position: i32,
    pub description: String,
    pub done: bool,
    pub done_by_name: Option<String>,
    pub done_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct WorkLog {
    pub id: Uuid,
    pub user_id: Uuid,
    pub user_name: String,
    /// work | travel
    pub kind: String,
    pub started_at: DateTime<Utc>,
    pub ended_at: DateTime<Utc>,
    pub minutes: i32,
    pub notes: String,
}

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct JobPhoto {
    /// The id of the file; fetch it from `/field/jobs/{id}/photos/{photo_id}`.
    pub id: Uuid,
    pub caption: String,
    pub filename: String,
    pub uploader_name: String,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct SitePhone {
    pub label: String,
    pub number: String,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct JobDetail {
    pub job: Job,
    /// Phone numbers of the person to meet, to call when arriving.
    pub contact_phones: Vec<SitePhone>,
    pub tasks: Vec<Task>,
    pub work_logs: Vec<WorkLog>,
    pub photos: Vec<JobPhoto>,
    /// Equipment (installed units of the customer) worked on.
    pub equipment: Vec<JobEquipment>,
    /// Parts used (record only; stock is not deducted).
    pub parts: Vec<JobPart>,
    /// The customer's signature, or that they declined to sign.
    pub signature: Option<JobSignature>,
    /// Total minutes of work and of travel logged so far.
    pub work_minutes: i64,
    pub travel_minutes: i64,
}

const SELECT: &str = "SELECT j.id, j.number, j.kind, j.status, j.priority, j.title, j.instructions, j.customer_id,
        c.name AS customer_name, j.contact_id, nullif(btrim(ct.first_name || ' ' || ct.last_name), '') AS contact_name,
        j.ticket_id, j.repair_id, j.site_name, j.street, j.postal_code, j.city, j.country_code::text AS country_code,
        j.latitude, j.longitude, j.scheduled_start, j.scheduled_end, j.started_at, j.completed_at, j.completion_notes,
        (SELECT count(*) FROM field.job_tasks t WHERE t.job_id = j.id) AS tasks_total,
        (SELECT count(*) FROM field.job_tasks t WHERE t.job_id = j.id AND t.done) AS tasks_done,
        j.contract_id, (SELECT k.number FROM field.contracts k WHERE k.id = j.contract_id) AS contract_number,
        j.due_date, j.report_sent_at, j.report_sent_to
     FROM field.jobs j JOIN crm.customers c ON c.id = j.customer_id LEFT JOIN crm.contacts ct ON ct.id = j.contact_id";

fn one_line(r: &JobRow) -> String {
    let town = [r.postal_code.trim(), r.city.trim()]
        .iter()
        .filter(|p| !p.is_empty())
        .copied()
        .collect::<Vec<_>>()
        .join(" ");
    [r.street.trim(), town.as_str()]
        .iter()
        .filter(|p| !p.is_empty())
        .copied()
        .collect::<Vec<_>>()
        .join(", ")
}

async fn techs_of(conn: &mut PgConnection, ids: &[Uuid]) -> AppResult<Vec<(Uuid, Uuid, String)>> {
    Ok(sqlx::query_as(
        "SELECT jt.job_id, u.id, u.display_name FROM field.job_technicians jt JOIN core.users u ON u.id = jt.user_id
         WHERE jt.job_id = ANY($1) ORDER BY u.display_name",
    )
    .bind(ids)
    .fetch_all(conn)
    .await?)
}

async fn assemble(conn: &mut PgConnection, rows: Vec<JobRow>) -> AppResult<Vec<Job>> {
    let ids: Vec<Uuid> = rows.iter().map(|r| r.id).collect();
    let techs = techs_of(conn, &ids).await?;
    Ok(rows
        .into_iter()
        .map(|r| {
            let address = one_line(&r);
            Job {
                maps_url: maps_url(r.latitude, r.longitude, &address),
                technicians: techs
                    .iter()
                    .filter(|(j, _, _)| *j == r.id)
                    .map(|(_, u, n)| Technician {
                        user_id: *u,
                        display_name: n.clone(),
                    })
                    .collect(),
                address,
                id: r.id,
                number: r.number,
                kind: r.kind,
                status: r.status,
                priority: r.priority,
                title: r.title,
                instructions: r.instructions,
                customer_id: r.customer_id,
                customer_name: r.customer_name,
                contact_id: r.contact_id,
                contact_name: r.contact_name,
                ticket_id: r.ticket_id,
                repair_id: r.repair_id,
                site_name: r.site_name,
                street: r.street,
                postal_code: r.postal_code,
                city: r.city,
                country_code: r.country_code,
                latitude: r.latitude,
                longitude: r.longitude,
                scheduled_start: r.scheduled_start,
                scheduled_end: r.scheduled_end,
                started_at: r.started_at,
                completed_at: r.completed_at,
                completion_notes: r.completion_notes,
                tasks_total: r.tasks_total,
                tasks_done: r.tasks_done,
                contract_id: r.contract_id,
                contract_number: r.contract_number,
                due_date: r.due_date,
                report_sent_at: r.report_sent_at,
                report_sent_to: r.report_sent_to,
            }
        })
        .collect())
}

/// Planners and read-only roles see every job; a technician only the jobs they are assigned to.
pub fn sees_all(user: &CurrentUser) -> bool {
    user.can(Permission::FieldPlan) || !user.can(Permission::FieldWork)
}

async fn load_job(conn: &mut PgConnection, user: &CurrentUser, id: Uuid) -> AppResult<Job> {
    let rows: Vec<JobRow> = sqlx::query_as(&format!(
        "{SELECT} WHERE j.id = $1 AND j.company_id = $2
           AND ($3 OR EXISTS (SELECT 1 FROM field.job_technicians x WHERE x.job_id = j.id AND x.user_id = $4))"
    ))
    .bind(id)
    .bind(user.company_id)
    .bind(sees_all(user))
    .bind(user.user_id)
    .fetch_all(&mut *conn)
    .await?;
    assemble(conn, rows)
        .await?
        .into_iter()
        .next()
        .ok_or(AppError::NotFound("job"))
}

async fn load_detail(
    conn: &mut PgConnection,
    user: &CurrentUser,
    id: Uuid,
) -> AppResult<JobDetail> {
    let job = load_job(conn, user, id).await?;
    let contact_phones = match job.contact_id {
        Some(c) => tradocraft_crm::contacts::get_contact(conn, c)
            .await?
            .phones
            .into_iter()
            .map(|p| SitePhone {
                label: p.label,
                number: p.number,
            })
            .collect(),
        None => vec![],
    };
    let tasks: Vec<Task> = sqlx::query_as(
        "SELECT t.id, t.position, t.description, t.done, u.display_name AS done_by_name, t.done_at
         FROM field.job_tasks t LEFT JOIN core.users u ON u.id = t.done_by WHERE t.job_id = $1 ORDER BY t.position",
    )
    .bind(id)
    .fetch_all(&mut *conn)
    .await?;
    let work_logs: Vec<WorkLog> = sqlx::query_as(
        "SELECT w.id, w.user_id, u.display_name AS user_name, w.kind, w.started_at, w.ended_at,
                (extract(epoch FROM (w.ended_at - w.started_at)) / 60)::int AS minutes, w.notes
         FROM field.work_logs w JOIN core.users u ON u.id = w.user_id WHERE w.job_id = $1 ORDER BY w.started_at, w.id",
    )
    .bind(id)
    .fetch_all(&mut *conn)
    .await?;
    let photos: Vec<JobPhoto> = sqlx::query_as(
        "SELECT f.id, p.caption, f.filename, f.uploader_name, p.created_at
         FROM field.job_photos p JOIN core.files f ON f.id = p.file_id WHERE p.job_id = $1 ORDER BY p.created_at, p.id",
    )
    .bind(id)
    .fetch_all(&mut *conn)
    .await?;
    let equipment = extras::equipment_of(&mut *conn, id).await?;
    let parts = extras::parts_of(&mut *conn, id).await?;
    let signature = extras::signature_of(conn, id).await?;
    let sum = |kind: &str| {
        work_logs
            .iter()
            .filter(|w| w.kind == kind)
            .map(|w| w.minutes as i64)
            .sum()
    };
    Ok(JobDetail {
        work_minutes: sum("work"),
        travel_minutes: sum("travel"),
        job,
        contact_phones,
        tasks,
        work_logs,
        photos,
        equipment,
        parts,
        signature,
    })
}

/// Planners may do anything on a job; a technician only on jobs they are assigned to.
async fn ensure_can_work(
    conn: &mut PgConnection,
    user: &CurrentUser,
    job_id: Uuid,
) -> AppResult<()> {
    if user.can(Permission::FieldPlan) {
        return Ok(());
    }
    user.require(Permission::FieldWork)?;
    // `load_job` hides jobs of others as not found.
    load_job(conn, user, job_id).await.map(|_| ())
}

fn check_one_of(field: &str, value: &str, allowed: &[&str]) -> AppResult<()> {
    if allowed.contains(&value) {
        Ok(())
    } else {
        Err(AppError::Validation(format!(
            "{field} must be one of {}",
            allowed.join(", ")
        )))
    }
}

fn ensure_open(job: &Job) -> AppResult<()> {
    if matches!(job.status.as_str(), "completed" | "cancelled") {
        Err(AppError::Conflict(format!("the job is {}", job.status)))
    } else {
        Ok(())
    }
}

// ---------------------------------------------------------------------------------------------
// Listing
// ---------------------------------------------------------------------------------------------

#[derive(Debug, Deserialize, IntoParams)]
pub struct ListParams {
    /// Searches number, title, customer and city.
    pub q: Option<String>,
    /// A status, or `active` for planned and in progress.
    pub status: Option<String>,
    /// `me`, `none` (unassigned) or a user id.
    pub technician: Option<String>,
    pub customer_id: Option<Uuid>,
    /// Jobs generated for this maintenance contract.
    pub contract_id: Option<Uuid>,
    /// Jobs scheduled from this moment on.
    pub from: Option<DateTime<Utc>>,
    /// Jobs scheduled before this moment.
    pub to: Option<DateTime<Utc>>,
}

async fn list_jobs_inner(
    conn: &mut PgConnection,
    user: &CurrentUser,
    p: &ListParams,
    only_mine: bool,
    include_recent_done: bool,
) -> AppResult<Vec<Job>> {
    let pattern =
        p.q.as_deref()
            .map(str::trim)
            .filter(|q| !q.is_empty())
            .map(|q| format!("%{}%", q.to_lowercase()));
    let (none, tech) = match (only_mine, p.technician.as_deref()) {
        (true, _) | (_, Some("me")) => (false, Some(user.user_id)),
        (_, Some("none")) => (true, None),
        (_, Some(u)) => (
            false,
            Some(
                Uuid::parse_str(u)
                    .map_err(|_| AppError::Validation("invalid technician".into()))?,
            ),
        ),
        _ => (false, None),
    };
    let status = p.status.as_deref().filter(|s| *s != "all");
    let rows: Vec<JobRow> = sqlx::query_as(&format!(
        "{SELECT} WHERE j.company_id = $1
           AND ($2 OR EXISTS (SELECT 1 FROM field.job_technicians x WHERE x.job_id = j.id AND x.user_id = $3))
           AND ($4::text IS NULL OR lower(j.number) LIKE $4 OR lower(j.title) LIKE $4 OR lower(c.name) LIKE $4 OR lower(j.city) LIKE $4)
           AND ($5::text IS NULL OR ($5 = 'active' AND j.status IN ('planned', 'in_progress')) OR j.status = $5)
           AND (NOT $6 OR NOT EXISTS (SELECT 1 FROM field.job_technicians x WHERE x.job_id = j.id))
           AND ($7::uuid IS NULL OR EXISTS (SELECT 1 FROM field.job_technicians x WHERE x.job_id = j.id AND x.user_id = $7))
           AND ($8::uuid IS NULL OR j.customer_id = $8)
           AND ($9::timestamptz IS NULL OR j.scheduled_start >= $9)
           AND ($10::timestamptz IS NULL OR j.scheduled_start < $10)
           AND ($11 OR j.status <> 'completed' OR j.completed_at > now() - interval '7 days')
           AND ($12::uuid IS NULL OR j.contract_id = $12)
         ORDER BY (j.status IN ('completed', 'cancelled')), j.scheduled_start NULLS LAST, j.number LIMIT 300"
    ))
    .bind(user.company_id)
    .bind(sees_all(user))
    .bind(user.user_id)
    .bind(&pattern)
    .bind(status)
    .bind(none)
    .bind(tech)
    .bind(p.customer_id)
    .bind(p.from)
    .bind(p.to)
    .bind(!include_recent_done)
    .bind(p.contract_id)
    .fetch_all(&mut *conn)
    .await?;
    assemble(conn, rows).await
}

/// All jobs the user may see, for planning.
#[utoipa::path(get, path = "/field/jobs", tag = "field", operation_id = "list_jobs", params(ListParams),
    responses((status = 200, body = Vec<Job>)))]
async fn list_jobs(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(p): Query<ListParams>,
) -> AppResult<Json<Vec<Job>>> {
    user.require(Permission::FieldRead)?;
    let mut conn = state.db.acquire().await?;
    Ok(Json(
        list_jobs_inner(&mut conn, &user, &p, false, true).await?,
    ))
}

/// The jobs assigned to me that still have to be done (plus those finished in the last week),
/// in the order of their appointment.
#[utoipa::path(get, path = "/field/my-jobs", tag = "field", operation_id = "list_my_jobs",
    responses((status = 200, body = Vec<Job>)))]
async fn my_jobs(State(state): State<AppState>, user: CurrentUser) -> AppResult<Json<Vec<Job>>> {
    user.require(Permission::FieldRead)?;
    let mut conn = state.db.acquire().await?;
    let p = ListParams {
        q: None,
        status: None,
        technician: None,
        customer_id: None,
        contract_id: None,
        from: None,
        to: None,
    };
    Ok(Json(
        list_jobs_inner(&mut conn, &user, &p, true, true).await?,
    ))
}

#[utoipa::path(get, path = "/field/jobs/{id}", tag = "field", operation_id = "get_job", params(("id" = Uuid, Path)),
    responses((status = 200, body = JobDetail), (status = 404, body = ErrorBody)))]
async fn get_job(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<JobDetail>> {
    user.require(Permission::FieldRead)?;
    let mut conn = state.db.acquire().await?;
    Ok(Json(load_detail(&mut conn, &user, id).await?))
}

// ---------------------------------------------------------------------------------------------
// Planning
// ---------------------------------------------------------------------------------------------

#[derive(Debug, Deserialize, ToSchema)]
pub struct JobInput {
    #[serde(default = "default_kind")]
    pub kind: String,
    #[serde(default = "default_priority")]
    pub priority: String,
    pub title: String,
    #[serde(default)]
    pub instructions: String,
    pub customer_id: Uuid,
    pub contact_id: Option<Uuid>,
    pub ticket_id: Option<Uuid>,
    pub repair_id: Option<Uuid>,
    /// Where to go. Left empty, the customer's address is used.
    #[serde(default)]
    pub site_name: String,
    #[serde(default)]
    pub street: String,
    #[serde(default)]
    pub postal_code: String,
    #[serde(default)]
    pub city: String,
    pub country_code: Option<String>,
    pub latitude: Option<f64>,
    pub longitude: Option<f64>,
    pub scheduled_start: Option<DateTime<Utc>>,
    pub scheduled_end: Option<DateTime<Utc>>,
    #[serde(default)]
    pub technician_ids: Vec<Uuid>,
    /// The checklist; only used when creating (change it with the task endpoints).
    #[serde(default)]
    pub tasks: Vec<String>,
}

fn default_kind() -> String {
    "maintenance".into()
}
fn default_priority() -> String {
    "normal".into()
}

struct Site {
    site_name: String,
    street: String,
    postal_code: String,
    city: String,
    country_code: String,
}

impl JobInput {
    fn check(&self) -> AppResult<()> {
        check_one_of("kind", &self.kind, &KINDS)?;
        check_one_of("priority", &self.priority, &PRIORITIES)?;
        if self.title.trim().is_empty() {
            return Err(AppError::Validation("a title is required".into()));
        }
        if self.latitude.is_some() != self.longitude.is_some() {
            return Err(AppError::Validation(
                "give both latitude and longitude".into(),
            ));
        }
        if let (Some(a), Some(b)) = (self.scheduled_start, self.scheduled_end) {
            if b < a {
                return Err(AppError::Validation("the job ends before it starts".into()));
            }
        }
        Ok(())
    }
}

/// Validates the links and the technicians, and fills the site from the customer when empty.
async fn prepare(conn: &mut PgConnection, user: &CurrentUser, input: &JobInput) -> AppResult<Site> {
    let customer =
        tradocraft_crm::get_customer(&mut *conn, user.company_id, input.customer_id).await?;
    if let Some(c) = input.contact_id {
        let contact = tradocraft_crm::contacts::get_contact(conn, c).await?;
        if contact.customer_id != input.customer_id {
            return Err(AppError::Validation(
                "the contact does not work for this customer".into(),
            ));
        }
    }
    if let Some(t) = input.ticket_id {
        let ok: bool = sqlx::query_scalar(
            "SELECT EXISTS (SELECT 1 FROM helpdesk.tickets WHERE id = $1 AND company_id = $2)",
        )
        .bind(t)
        .bind(user.company_id)
        .fetch_one(&mut *conn)
        .await?;
        if !ok {
            return Err(AppError::Validation("unknown ticket".into()));
        }
    }
    if let Some(r) = input.repair_id {
        let ok: bool = sqlx::query_scalar(
            "SELECT EXISTS (SELECT 1 FROM repairs.repairs WHERE id = $1 AND company_id = $2)",
        )
        .bind(r)
        .bind(user.company_id)
        .fetch_one(&mut *conn)
        .await?;
        if !ok {
            return Err(AppError::Validation("unknown repair".into()));
        }
    }
    let mut unique = input.technician_ids.clone();
    unique.sort();
    unique.dedup();
    let valid: i64 = sqlx::query_scalar("SELECT count(DISTINCT user_id) FROM core.user_companies WHERE company_id = $1 AND user_id = ANY($2)")
        .bind(user.company_id)
        .bind(&unique)
        .fetch_one(&mut *conn)
        .await?;
    if valid as usize != unique.len() {
        return Err(AppError::Validation(
            "a technician is not a colleague in this company".into(),
        ));
    }
    let own_address = !input.street.trim().is_empty() || !input.city.trim().is_empty();
    Ok(if own_address {
        Site {
            site_name: input.site_name.trim().to_string(),
            street: input.street.trim().to_string(),
            postal_code: input.postal_code.trim().to_string(),
            city: input.city.trim().to_string(),
            country_code: input
                .country_code
                .clone()
                .unwrap_or_else(|| customer.country_code.clone())
                .to_uppercase(),
        }
    } else {
        Site {
            site_name: input.site_name.trim().to_string(),
            street: customer.street,
            postal_code: customer.postal_code,
            city: customer.city,
            country_code: customer.country_code,
        }
    })
}

/// The next job number of the company (`J2026-00001`).
async fn next_job_number(conn: &mut PgConnection, company_id: Uuid) -> AppResult<String> {
    let year = Utc::now().year();
    let n = tradocraft_core::numbering::next_number(conn, company_id, "job", year).await?;
    Ok(format!("J{year}-{n:05}"))
}

pub async fn set_technicians(conn: &mut PgConnection, job_id: Uuid, ids: &[Uuid]) -> AppResult<()> {
    sqlx::query("DELETE FROM field.job_technicians WHERE job_id = $1")
        .bind(job_id)
        .execute(&mut *conn)
        .await?;
    let mut unique = ids.to_vec();
    unique.sort();
    unique.dedup();
    for u in unique {
        sqlx::query("INSERT INTO field.job_technicians (job_id, user_id) VALUES ($1, $2)")
            .bind(job_id)
            .bind(u)
            .execute(&mut *conn)
            .await?;
    }
    Ok(())
}

#[utoipa::path(post, path = "/field/jobs", tag = "field", operation_id = "create_job", request_body = JobInput,
    responses((status = 201, body = JobDetail), (status = 403, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn create_job(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<JobInput>,
) -> AppResult<(StatusCode, Json<JobDetail>)> {
    user.require(Permission::FieldPlan)?;
    input.check()?;
    let mut tx = state.db.begin().await?;
    let site = prepare(&mut tx, &user, &input).await?;
    let number = next_job_number(&mut tx, user.company_id).await?;
    let id = new_id();
    sqlx::query(
        "INSERT INTO field.jobs (id, company_id, number, kind, priority, title, instructions, customer_id, contact_id,
                                 ticket_id, repair_id, site_name, street, postal_code, city, country_code, latitude, longitude,
                                 scheduled_start, scheduled_end, created_by)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20, $21)",
    )
    .bind(id).bind(user.company_id).bind(&number).bind(&input.kind).bind(&input.priority)
    .bind(input.title.trim()).bind(input.instructions.trim()).bind(input.customer_id).bind(input.contact_id)
    .bind(input.ticket_id).bind(input.repair_id).bind(&site.site_name).bind(&site.street).bind(&site.postal_code)
    .bind(&site.city).bind(&site.country_code).bind(input.latitude).bind(input.longitude)
    .bind(input.scheduled_start).bind(input.scheduled_end).bind(user.user_id)
    .execute(&mut *tx)
    .await?;
    set_technicians(&mut tx, id, &input.technician_ids).await?;
    for (i, t) in input
        .tasks
        .iter()
        .filter(|t| !t.trim().is_empty())
        .enumerate()
    {
        sqlx::query("INSERT INTO field.job_tasks (id, job_id, position, description) VALUES ($1, $2, $3, $4)")
            .bind(new_id()).bind(id).bind(i as i32 + 1).bind(t.trim()).execute(&mut *tx).await?;
    }
    audit::record(
        &mut tx,
        &user,
        "job",
        id,
        "created",
        serde_json::json!({ "number": number }),
    )
    .await?;
    let d = load_detail(&mut tx, &user, id).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(d)))
}

#[utoipa::path(put, path = "/field/jobs/{id}", tag = "field", operation_id = "update_job", params(("id" = Uuid, Path)),
    request_body = JobInput, responses((status = 200, body = JobDetail), (status = 403, body = ErrorBody)))]
async fn update_job(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<JobInput>,
) -> AppResult<Json<JobDetail>> {
    user.require(Permission::FieldPlan)?;
    input.check()?;
    let mut tx = state.db.begin().await?;
    load_job(&mut tx, &user, id).await?;
    let site = prepare(&mut tx, &user, &input).await?;
    sqlx::query(
        "UPDATE field.jobs SET kind = $2, priority = $3, title = $4, instructions = $5, customer_id = $6, contact_id = $7,
                ticket_id = $8, repair_id = $9, site_name = $10, street = $11, postal_code = $12, city = $13,
                country_code = $14, latitude = $15, longitude = $16, scheduled_start = $17, scheduled_end = $18, updated_at = now()
         WHERE id = $1",
    )
    .bind(id).bind(&input.kind).bind(&input.priority).bind(input.title.trim()).bind(input.instructions.trim())
    .bind(input.customer_id).bind(input.contact_id).bind(input.ticket_id).bind(input.repair_id)
    .bind(&site.site_name).bind(&site.street).bind(&site.postal_code).bind(&site.city).bind(&site.country_code)
    .bind(input.latitude).bind(input.longitude).bind(input.scheduled_start).bind(input.scheduled_end)
    .execute(&mut *tx)
    .await?;
    set_technicians(&mut tx, id, &input.technician_ids).await?;
    audit::record(&mut tx, &user, "job", id, "updated", serde_json::json!({})).await?;
    let d = load_detail(&mut tx, &user, id).await?;
    tx.commit().await?;
    Ok(Json(d))
}

// ---------------------------------------------------------------------------------------------
// Doing the work
// ---------------------------------------------------------------------------------------------

#[derive(Debug, Deserialize, ToSchema)]
pub struct TaskInput {
    pub description: String,
    /// Chosen by the client: sending the same id again returns the first task instead of adding a
    /// second one (offline retries). The same id with another description is a 409.
    pub client_id: Option<Uuid>,
}

#[utoipa::path(post, path = "/field/jobs/{id}/tasks", tag = "field", operation_id = "add_job_task", params(("id" = Uuid, Path)),
    request_body = TaskInput, responses((status = 201, body = JobDetail), (status = 403, body = ErrorBody), (status = 409, body = ErrorBody)))]
async fn add_task(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<TaskInput>,
) -> AppResult<(StatusCode, Json<JobDetail>)> {
    if input.description.trim().is_empty() {
        return Err(AppError::Validation("describe the task".into()));
    }
    let mut tx = state.db.begin().await?;
    ensure_can_work(&mut tx, &user, id).await?;
    ensure_open(&load_job(&mut tx, &user, id).await?)?;
    let description = input.description.trim();
    let inserted = sqlx::query(
        "INSERT INTO field.job_tasks (id, job_id, position, description, client_id)
         VALUES ($1, $2, (SELECT coalesce(max(position), 0) + 1 FROM field.job_tasks WHERE job_id = $2), $3, $4)
         ON CONFLICT (job_id, client_id) WHERE client_id IS NOT NULL DO NOTHING",
    )
    .bind(new_id()).bind(id).bind(description).bind(input.client_id).execute(&mut *tx).await?;
    if inserted.rows_affected() == 0 {
        let same: bool = sqlx::query_scalar(
            "SELECT EXISTS (SELECT 1 FROM field.job_tasks WHERE job_id = $1 AND client_id = $2 AND description = $3)",
        )
        .bind(id).bind(input.client_id).bind(description).fetch_one(&mut *tx).await?;
        if !same {
            return Err(AppError::Conflict(
                "this id belongs to another record".into(),
            ));
        }
    }
    let d = load_detail(&mut tx, &user, id).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(d)))
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct DoneInput {
    pub done: bool,
}

/// Ticks or unticks a task. Setting the state it already has changes nothing, so retries are safe.
#[utoipa::path(post, path = "/field/jobs/{id}/tasks/{task_id}/done", tag = "field", operation_id = "set_job_task_done",
    params(("id" = Uuid, Path), ("task_id" = Uuid, Path)), request_body = DoneInput,
    responses((status = 200, body = JobDetail), (status = 403, body = ErrorBody), (status = 404, body = ErrorBody)))]
async fn set_task_done(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((id, task_id)): Path<(Uuid, Uuid)>,
    Json(input): Json<DoneInput>,
) -> AppResult<Json<JobDetail>> {
    let mut tx = state.db.begin().await?;
    ensure_can_work(&mut tx, &user, id).await?;
    ensure_open(&load_job(&mut tx, &user, id).await?)?;
    let res = sqlx::query(
        "UPDATE field.job_tasks SET done = $3,
                done_by = CASE WHEN $3 THEN coalesce(done_by, $4) END,
                done_at = CASE WHEN $3 THEN coalesce(done_at, now()) END
         WHERE id = $2 AND job_id = $1",
    )
    .bind(id)
    .bind(task_id)
    .bind(input.done)
    .bind(user.user_id)
    .execute(&mut *tx)
    .await?;
    if res.rows_affected() == 0 {
        return Err(AppError::NotFound("task"));
    }
    let d = load_detail(&mut tx, &user, id).await?;
    tx.commit().await?;
    Ok(Json(d))
}

/// Starts the job: the technician has arrived and begins. Starting twice changes nothing.
#[utoipa::path(post, path = "/field/jobs/{id}/start", tag = "field", operation_id = "start_job", params(("id" = Uuid, Path)),
    responses((status = 200, body = JobDetail), (status = 409, body = ErrorBody)))]
async fn start_job(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<JobDetail>> {
    let mut tx = state.db.begin().await?;
    ensure_can_work(&mut tx, &user, id).await?;
    let job = load_job(&mut tx, &user, id).await?;
    if job.status == "planned" {
        sqlx::query("UPDATE field.jobs SET status = 'in_progress', started_at = coalesce(started_at, now()), updated_at = now() WHERE id = $1")
            .bind(id).execute(&mut *tx).await?;
        audit::record(&mut tx, &user, "job", id, "started", serde_json::json!({})).await?;
    } else if job.status != "in_progress" {
        return Err(AppError::Conflict(format!("the job is {}", job.status)));
    }
    let d = load_detail(&mut tx, &user, id).await?;
    tx.commit().await?;
    Ok(Json(d))
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct CompleteInput {
    /// What was done, and anything left open.
    pub notes: String,
}

/// Completing a job that is already completed with the same text changes nothing (safe to retry);
/// with other text it is a 409.
#[utoipa::path(post, path = "/field/jobs/{id}/complete", tag = "field", operation_id = "complete_job", params(("id" = Uuid, Path)),
    request_body = CompleteInput, responses((status = 200, body = JobDetail), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn complete_job(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<CompleteInput>,
) -> AppResult<Json<JobDetail>> {
    if input.notes.trim().is_empty() {
        return Err(AppError::Validation("say what was done".into()));
    }
    let mut tx = state.db.begin().await?;
    ensure_can_work(&mut tx, &user, id).await?;
    let job = load_job(&mut tx, &user, id).await?;
    if job.status == "completed" && job.completion_notes == input.notes.trim() {
        // A retry of the same completion (the answer was lost): nothing to do.
        let d = load_detail(&mut tx, &user, id).await?;
        return Ok(Json(d));
    }
    ensure_open(&job)?;
    sqlx::query(
        "UPDATE field.jobs SET status = 'completed', completed_at = now(), started_at = coalesce(started_at, now()),
                completion_notes = $2, updated_at = now() WHERE id = $1",
    )
    .bind(id).bind(input.notes.trim()).execute(&mut *tx).await?;
    audit::record(
        &mut tx,
        &user,
        "job",
        id,
        "completed",
        serde_json::json!({}),
    )
    .await?;
    let d = load_detail(&mut tx, &user, id).await?;
    tx.commit().await?;
    Ok(Json(d))
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct ReasonInput {
    #[serde(default)]
    pub reason: String,
}

/// Cancels a job (planners only).
#[utoipa::path(post, path = "/field/jobs/{id}/cancel", tag = "field", operation_id = "cancel_job", params(("id" = Uuid, Path)),
    request_body = ReasonInput, responses((status = 200, body = JobDetail), (status = 409, body = ErrorBody)))]
async fn cancel_job(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<ReasonInput>,
) -> AppResult<Json<JobDetail>> {
    user.require(Permission::FieldPlan)?;
    let mut tx = state.db.begin().await?;
    ensure_open(&load_job(&mut tx, &user, id).await?)?;
    sqlx::query("UPDATE field.jobs SET status = 'cancelled', completion_notes = $2, updated_at = now() WHERE id = $1")
        .bind(id).bind(input.reason.trim()).execute(&mut *tx).await?;
    audit::record(
        &mut tx,
        &user,
        "job",
        id,
        "cancelled",
        serde_json::json!({ "reason": input.reason }),
    )
    .await?;
    let d = load_detail(&mut tx, &user, id).await?;
    tx.commit().await?;
    Ok(Json(d))
}

/// Takes a completed or cancelled job back into work (planners only).
#[utoipa::path(post, path = "/field/jobs/{id}/reopen", tag = "field", operation_id = "reopen_job", params(("id" = Uuid, Path)),
    responses((status = 200, body = JobDetail), (status = 409, body = ErrorBody)))]
async fn reopen_job(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<JobDetail>> {
    user.require(Permission::FieldPlan)?;
    let mut tx = state.db.begin().await?;
    let job = load_job(&mut tx, &user, id).await?;
    if !matches!(job.status.as_str(), "completed" | "cancelled") {
        return Err(AppError::Conflict("the job is not finished".into()));
    }
    sqlx::query(
        "UPDATE field.jobs SET status = CASE WHEN started_at IS NULL THEN 'planned' ELSE 'in_progress' END,
                completed_at = NULL, updated_at = now() WHERE id = $1",
    )
    .bind(id).execute(&mut *tx).await?;
    audit::record(&mut tx, &user, "job", id, "reopened", serde_json::json!({})).await?;
    let d = load_detail(&mut tx, &user, id).await?;
    tx.commit().await?;
    Ok(Json(d))
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct WorkLogInput {
    /// Chosen by the client: sending the same id again changes nothing (offline retries).
    pub id: Option<Uuid>,
    /// work | travel
    #[serde(default = "default_log_kind")]
    pub kind: String,
    pub started_at: DateTime<Utc>,
    pub ended_at: DateTime<Utc>,
    #[serde(default)]
    pub notes: String,
}

fn default_log_kind() -> String {
    "work".into()
}

/// Logs time and notes of work (or travel) on a job, for the logged-in technician.
#[utoipa::path(post, path = "/field/jobs/{id}/work-logs", tag = "field", operation_id = "add_work_log", params(("id" = Uuid, Path)),
    request_body = WorkLogInput, responses((status = 201, body = JobDetail), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn add_work_log(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<WorkLogInput>,
) -> AppResult<(StatusCode, Json<JobDetail>)> {
    check_one_of("kind", &input.kind, &["work", "travel"])?;
    if input.ended_at < input.started_at {
        return Err(AppError::Validation(
            "the work ends before it starts".into(),
        ));
    }
    if input.ended_at - input.started_at > Duration::hours(24) {
        return Err(AppError::Validation(
            "a single entry cannot be longer than 24 hours".into(),
        ));
    }
    if input.ended_at > Utc::now() + Duration::minutes(5) {
        return Err(AppError::Validation(
            "the work cannot end in the future".into(),
        ));
    }
    let mut tx = state.db.begin().await?;
    ensure_can_work(&mut tx, &user, id).await?;
    ensure_open(&load_job(&mut tx, &user, id).await?)?;
    let log_id = input.id.unwrap_or_else(new_id);
    let inserted = sqlx::query(
        "INSERT INTO field.work_logs (id, job_id, user_id, kind, started_at, ended_at, notes)
         VALUES ($1, $2, $3, $4, $5, $6, $7) ON CONFLICT (id) DO NOTHING",
    )
    .bind(log_id)
    .bind(id)
    .bind(user.user_id)
    .bind(&input.kind)
    .bind(input.started_at)
    .bind(input.ended_at)
    .bind(input.notes.trim())
    .execute(&mut *tx)
    .await?;
    if inserted.rows_affected() == 0 {
        // The same id again: fine if it is the same entry, an error if the id belongs to another job.
        let same: bool = sqlx::query_scalar("SELECT EXISTS (SELECT 1 FROM field.work_logs WHERE id = $1 AND job_id = $2 AND user_id = $3
                 AND kind = $4 AND started_at = $5 AND ended_at = $6 AND notes = $7)")
            .bind(log_id).bind(id).bind(user.user_id).bind(&input.kind).bind(input.started_at).bind(input.ended_at).bind(input.notes.trim())
            .fetch_one(&mut *tx).await?;
        if !same {
            return Err(AppError::Conflict(
                "this id belongs to another record".into(),
            ));
        }
    }
    let d = load_detail(&mut tx, &user, id).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(d)))
}

// ---------------------------------------------------------------------------------------------
// Photos
// ---------------------------------------------------------------------------------------------

#[derive(Debug, Deserialize, IntoParams)]
pub struct UploadParams {
    pub caption: Option<String>,
    pub filename: Option<String>,
    /// A client-chosen id: uploading the same id again returns the first upload.
    pub client_id: Option<Uuid>,
}

/// Adds a photo: the request body is the image (JPEG, PNG or WebP, at most 12 MB).
#[utoipa::path(post, path = "/field/jobs/{id}/photos", tag = "field", operation_id = "upload_job_photo",
    params(("id" = Uuid, Path), UploadParams), request_body(content = String, content_type = "application/octet-stream"),
    responses((status = 201, body = JobDetail), (status = 403, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn upload_photo(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Query(p): Query<UploadParams>,
    body: Bytes,
) -> AppResult<(StatusCode, Json<JobDetail>)> {
    let mut tx = state.db.begin().await?;
    ensure_can_work(&mut tx, &user, id).await?;
    // Photos may still be added to a completed job (taken on site, uploaded when back online),
    // but not to a cancelled one.
    if load_job(&mut tx, &user, id).await?.status == "cancelled" {
        return Err(AppError::Conflict("the job is cancelled".into()));
    }
    let file = files::store_image(
        &mut tx,
        user.company_id,
        p.client_id,
        p.filename.as_deref().unwrap_or(""),
        &body,
        Some(user.user_id),
        &user.display_name,
    )
    .await?;
    if file.size_bytes as usize != body.len() {
        return Err(AppError::Conflict(
            "this photo id belongs to another picture".into(),
        ));
    }
    let inserted = sqlx::query("INSERT INTO field.job_photos (id, job_id, file_id, caption) VALUES ($1, $2, $3, $4) ON CONFLICT (file_id) DO NOTHING")
        .bind(new_id()).bind(id).bind(file.id).bind(p.caption.as_deref().unwrap_or("").trim())
        .execute(&mut *tx)
        .await?;
    if inserted.rows_affected() == 0 {
        let same: bool = sqlx::query_scalar(
            "SELECT EXISTS (SELECT 1 FROM field.job_photos WHERE file_id = $1 AND job_id = $2)",
        )
        .bind(file.id)
        .bind(id)
        .fetch_one(&mut *tx)
        .await?;
        if !same {
            return Err(AppError::Conflict(
                "this photo id belongs to another record".into(),
            ));
        }
    }
    let d = load_detail(&mut tx, &user, id).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(d)))
}

#[utoipa::path(get, path = "/field/jobs/{id}/photos/{photo_id}", tag = "field", operation_id = "get_job_photo",
    params(("id" = Uuid, Path), ("photo_id" = Uuid, Path)),
    responses((status = 200, content_type = "image/*", body = String), (status = 404, body = ErrorBody)))]
async fn get_photo(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((id, photo_id)): Path<(Uuid, Uuid)>,
) -> AppResult<Response> {
    user.require(Permission::FieldRead)?;
    let mut conn = state.db.acquire().await?;
    load_job(&mut conn, &user, id).await?;
    let linked: bool = sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM field.job_photos WHERE job_id = $1 AND file_id = $2)",
    )
    .bind(id)
    .bind(photo_id)
    .fetch_one(&mut *conn)
    .await?;
    if !linked {
        return Err(AppError::NotFound("photo"));
    }
    let (content_type, data) = files::load(&mut conn, user.company_id, photo_id).await?;
    Ok(files::image_response(&content_type, data))
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(list_jobs, create_job))
        .routes(routes!(my_jobs))
        .routes(routes!(get_job, update_job))
        .routes(routes!(add_task))
        .routes(routes!(set_task_done))
        .routes(routes!(start_job))
        .routes(routes!(complete_job))
        .routes(routes!(cancel_job))
        .routes(routes!(reopen_job))
        .routes(routes!(add_work_log))
        .routes(routes!(get_photo))
        .merge(extras::router())
        .merge(contracts::router())
        .merge(report::router())
        .merge(
            OpenApiRouter::new()
                .routes(routes!(upload_photo))
                .layer(DefaultBodyLimit::max(MAX_FILE_BYTES + 64 * 1024)),
        )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn navigation_uses_coordinates_when_known_else_the_address() {
        assert_eq!(
            maps_url(Some(51.05), Some(3.72), "ignored").unwrap(),
            "https://www.google.com/maps/search/?api=1&query=51.05%2C3.72"
        );
        assert_eq!(
            maps_url(None, None, "Havenlaan 10, 2000 Antwerpen").unwrap(),
            "https://www.google.com/maps/search/?api=1&query=Havenlaan%2010%2C%202000%20Antwerpen"
        );
        assert_eq!(maps_url(None, None, "  "), None);
        assert!(url_encode("Rue de l'Usine & Co/é").contains("%26"));
        assert!(!url_encode("a b&c").contains(' '));
    }
}
