//! Repairs: products customers send in. A customer may announce a repair first (often in a ticket
//! or in the portal); when the parcel arrives it is registered as received, routed to the right
//! department by someone who triages, worked there, and shipped back. Photos can be added at every
//! step, by staff and by the customer.
//!
//! Rights: reading needs `repairs.read`; changing a repair needs `repairs.write` *and* to belong
//! to its department (or to be allowed to route, or to have registered it); routing needs
//! `repairs.route`.

pub mod departments;
pub mod packages;
pub mod portal;
pub mod warranty;
pub mod workflow;

use axum::body::Bytes;
use axum::extract::{DefaultBodyLimit, Path, Query, State};
use axum::http::StatusCode;
use axum::response::Response;
use axum::Json;
use chrono::{DateTime, Datelike, Utc};
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection};
use tradocraft_core::files::{self, FileInfo, MAX_FILE_BYTES};
use tradocraft_core::{audit, new_id, AppError, AppResult, AppState, CurrentUser, Permission};
use utoipa::{IntoParams, ToSchema};
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

type ErrorBody = tradocraft_core::error::ErrorBody;

pub const PRIORITIES: [&str; 4] = ["low", "normal", "high", "urgent"];
pub const WARRANTIES: [&str; 3] = ["unknown", "in_warranty", "out_of_warranty"];

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct Repair {
    pub id: Uuid,
    pub number: String,
    /// announced | received | routed | in_progress | waiting_customer | waiting_parts | completed | shipped | cancelled
    pub status: String,
    pub priority: String,
    pub customer_id: Uuid,
    pub customer_name: String,
    pub contact_id: Option<Uuid>,
    pub contact_name: Option<String>,
    /// The ticket where the repair was announced or discussed.
    pub ticket_id: Option<Uuid>,
    pub ticket_number: Option<String>,
    pub product_id: Option<Uuid>,
    pub product_code: Option<String>,
    /// The product as the customer describes it.
    pub product_description: String,
    pub serial_number: String,
    pub fault_description: String,
    pub customer_reference: String,
    /// The final warranty status: unknown | in_warranty | out_of_warranty | void. See `/repairs/{id}/warranty`
    /// for the automatic result and the override behind it.
    pub warranty: String,
    /// The automatic result of the lookup: unknown | in_warranty | out_of_warranty
    pub warranty_auto: String,
    /// True when the workshop declared the warranty void (misuse).
    pub warranty_overridden: bool,
    /// The serial unit (engineering) the warranty was looked up from.
    pub serial_unit_id: Option<Uuid>,
    /// What was found when the product was looked at.
    pub findings: String,
    /// The department's conclusion.
    pub diagnosis: String,
    pub department_id: Option<Uuid>,
    pub department_name: Option<String>,
    pub assigned_user_id: Option<Uuid>,
    pub assigned_name: Option<String>,
    /// staff | portal | package
    pub source: String,
    pub photo_count: i64,
    pub received_at: Option<DateTime<Utc>>,
    pub completed_at: Option<DateTime<Utc>>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct RepairEvent {
    pub id: Uuid,
    /// created | status | routed | note | photo | package_linked | package_unlinked | findings | serial_unit |
    /// warranty_auto | warranty_manual | warranty_void | warranty_void_removed
    pub kind: String,
    pub from_status: Option<String>,
    pub to_status: Option<String>,
    pub from_department: Option<String>,
    pub to_department: Option<String>,
    pub note: String,
    pub actor_name: String,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct Photo {
    /// The id of the file; fetch it from `/repairs/{id}/photos/{photo_id}`.
    pub id: Uuid,
    pub caption: String,
    pub filename: String,
    pub content_type: String,
    pub size_bytes: i32,
    pub uploader_name: String,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct RepairDetail {
    pub repair: Repair,
    pub events: Vec<RepairEvent>,
    pub photos: Vec<Photo>,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct RepairPage {
    pub items: Vec<Repair>,
    pub total: i64,
}

pub(crate) const SELECT: &str = "SELECT r.id, r.number, r.status, r.priority, r.customer_id, c.name AS customer_name,
        r.contact_id, nullif(btrim(ct.first_name || ' ' || ct.last_name), '') AS contact_name,
        r.ticket_id, t.number AS ticket_number, r.product_id, p.code AS product_code,
        r.product_description, r.serial_number, r.fault_description, r.customer_reference, r.warranty,
        r.warranty_auto, r.warranty_overridden, r.serial_unit_id, r.findings, r.diagnosis,
        r.department_id, d.name AS department_name, r.assigned_user_id, u.display_name AS assigned_name, r.source,
        (SELECT count(*) FROM repairs.photos ph WHERE ph.repair_id = r.id) AS photo_count,
        r.received_at, r.completed_at, r.created_at, r.updated_at
     FROM repairs.repairs r
     JOIN crm.customers c ON c.id = r.customer_id
     LEFT JOIN crm.contacts ct ON ct.id = r.contact_id
     LEFT JOIN helpdesk.tickets t ON t.id = r.ticket_id
     LEFT JOIN products.products p ON p.id = r.product_id
     LEFT JOIN repairs.departments d ON d.id = r.department_id
     LEFT JOIN core.users u ON u.id = r.assigned_user_id";

pub async fn load_repair(conn: &mut PgConnection, company_id: Uuid, id: Uuid) -> AppResult<Repair> {
    sqlx::query_as(&format!("{SELECT} WHERE r.id = $1 AND r.company_id = $2"))
        .bind(id)
        .bind(company_id)
        .fetch_optional(conn)
        .await?
        .ok_or(AppError::NotFound("repair"))
}

pub(crate) async fn load_events(conn: &mut PgConnection, id: Uuid) -> AppResult<Vec<RepairEvent>> {
    Ok(sqlx::query_as(
        "SELECT e.id, e.kind, e.from_status, e.to_status, fd.name AS from_department, td.name AS to_department,
                e.note, coalesce(u.display_name, e.actor_name) AS actor_name, e.created_at
         FROM repairs.events e
         LEFT JOIN repairs.departments fd ON fd.id = e.from_department
         LEFT JOIN repairs.departments td ON td.id = e.to_department
         LEFT JOIN core.users u ON u.id = e.user_id
         WHERE e.repair_id = $1 ORDER BY e.created_at, e.id",
    )
    .bind(id)
    .fetch_all(conn)
    .await?)
}

pub(crate) async fn load_photos(conn: &mut PgConnection, id: Uuid) -> AppResult<Vec<Photo>> {
    Ok(sqlx::query_as(
        "SELECT f.id, p.caption, f.filename, f.content_type, f.size_bytes, f.uploader_name, p.created_at
         FROM repairs.photos p JOIN core.files f ON f.id = p.file_id WHERE p.repair_id = $1 ORDER BY p.created_at, p.id",
    )
    .bind(id)
    .fetch_all(conn)
    .await?)
}

pub(crate) async fn load_detail(
    conn: &mut PgConnection,
    company_id: Uuid,
    id: Uuid,
) -> AppResult<RepairDetail> {
    let repair = load_repair(conn, company_id, id).await?;
    let events = load_events(conn, id).await?;
    let photos = load_photos(conn, id).await?;
    Ok(RepairDetail {
        repair,
        events,
        photos,
    })
}

pub(crate) struct Event<'a> {
    pub kind: &'a str,
    pub from_status: Option<&'a str>,
    pub to_status: Option<&'a str>,
    pub from_department: Option<Uuid>,
    pub to_department: Option<Uuid>,
    pub note: &'a str,
}

pub(crate) async fn add_event(
    conn: &mut PgConnection,
    repair_id: Uuid,
    user_id: Option<Uuid>,
    actor_name: &str,
    e: Event<'_>,
) -> AppResult<()> {
    sqlx::query(
        "INSERT INTO repairs.events (id, repair_id, kind, from_status, to_status, from_department, to_department,
                                     note, user_id, actor_name)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)",
    )
    .bind(new_id())
    .bind(repair_id)
    .bind(e.kind)
    .bind(e.from_status)
    .bind(e.to_status)
    .bind(e.from_department)
    .bind(e.to_department)
    .bind(e.note)
    .bind(user_id)
    .bind(actor_name)
    .execute(conn)
    .await?;
    Ok(())
}

pub(crate) async fn next_number(conn: &mut PgConnection, company_id: Uuid) -> AppResult<String> {
    let year = Utc::now().year();
    let n = tradocraft_core::numbering::next_number(conn, company_id, "repair", year).await?;
    Ok(format!("R{year}-{n:05}"))
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

/// Changing a repair: whoever may route can; otherwise one must work in its department or have
/// registered it. (A repair nobody has routed yet is for the people who triage.)
async fn ensure_can_work(
    conn: &mut PgConnection,
    user: &CurrentUser,
    repair_id: Uuid,
) -> AppResult<()> {
    user.require(Permission::RepairsWrite)?;
    if user.can(Permission::RepairsRoute) {
        return Ok(());
    }
    let ok: bool = sqlx::query_scalar(
        "SELECT coalesce(r.created_by = $2, false)
                OR EXISTS (SELECT 1 FROM repairs.department_members m WHERE m.department_id = r.department_id AND m.user_id = $2)
         FROM repairs.repairs r WHERE r.id = $1",
    )
    .bind(repair_id)
    .bind(user.user_id)
    .fetch_one(conn)
    .await?;
    if ok {
        Ok(())
    } else {
        Err(AppError::Forbidden(
            "this repair is not in one of your departments".into(),
        ))
    }
}

// ---------------------------------------------------------------------------------------------
// List, create, read, update
// ---------------------------------------------------------------------------------------------

#[derive(Debug, Deserialize, IntoParams)]
pub struct ListParams {
    /// Searches number, customer, serial number, product and fault.
    pub q: Option<String>,
    /// A status, or `open` for everything not yet shipped or cancelled.
    pub status: Option<String>,
    /// A department id, or `none` for repairs not routed yet.
    pub department: Option<String>,
    /// `me` for repairs assigned to me, or a user id.
    pub assigned: Option<String>,
    pub customer_id: Option<Uuid>,
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}

#[utoipa::path(get, path = "/repairs", tag = "repairs", operation_id = "list_repairs", params(ListParams),
    responses((status = 200, body = RepairPage)))]
async fn list_repairs(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(p): Query<ListParams>,
) -> AppResult<Json<RepairPage>> {
    user.require(Permission::RepairsRead)?;
    let pattern =
        p.q.as_deref()
            .map(str::trim)
            .filter(|q| !q.is_empty())
            .map(|q| format!("%{}%", q.to_lowercase()));
    let (dept_none, dept_id) = match p.department.as_deref() {
        Some("none") => (true, None),
        Some(d) => (
            false,
            Some(
                Uuid::parse_str(d)
                    .map_err(|_| AppError::Validation("invalid department".into()))?,
            ),
        ),
        None => (false, None),
    };
    let assigned = match p.assigned.as_deref() {
        Some("me") => Some(user.user_id),
        Some(u) => {
            Some(Uuid::parse_str(u).map_err(|_| AppError::Validation("invalid user".into()))?)
        }
        None => None,
    };
    let status = p.status.as_deref().filter(|s| *s != "all");
    if let Some(s) = status {
        if s != "open" {
            check_one_of("status", s, &workflow::STATUSES)?;
        }
    }
    let filter = "WHERE r.company_id = $1
        AND ($2::text IS NULL OR lower(r.number) LIKE $2 OR lower(c.name) LIKE $2 OR lower(r.serial_number) LIKE $2
             OR lower(r.product_description) LIKE $2 OR lower(r.fault_description) LIKE $2
             OR lower(coalesce(p.code, '')) LIKE $2)
        AND ($3::text IS NULL OR ($3 = 'open' AND r.status NOT IN ('shipped', 'cancelled')) OR r.status = $3)
        AND (NOT $4 OR r.department_id IS NULL)
        AND ($5::uuid IS NULL OR r.department_id = $5)
        AND ($6::uuid IS NULL OR r.assigned_user_id = $6)
        AND ($7::uuid IS NULL OR r.customer_id = $7)";
    let items: Vec<Repair> = sqlx::query_as(&format!(
        "{SELECT} {filter} ORDER BY (r.status IN ('shipped', 'cancelled')), r.priority = 'urgent' DESC, r.updated_at DESC LIMIT $8 OFFSET $9"
    ))
    .bind(user.company_id)
    .bind(&pattern)
    .bind(status)
    .bind(dept_none)
    .bind(dept_id)
    .bind(assigned)
    .bind(p.customer_id)
    .bind(p.limit.unwrap_or(50).clamp(1, 500))
    .bind(p.offset.unwrap_or(0).max(0))
    .fetch_all(&state.db)
    .await?;
    let total: i64 = sqlx::query_scalar(&format!(
        "SELECT count(*) FROM repairs.repairs r JOIN crm.customers c ON c.id = r.customer_id
         LEFT JOIN products.products p ON p.id = r.product_id {filter}"
    ))
    .bind(user.company_id)
    .bind(&pattern)
    .bind(status)
    .bind(dept_none)
    .bind(dept_id)
    .bind(assigned)
    .bind(p.customer_id)
    .fetch_one(&state.db)
    .await?;
    Ok(Json(RepairPage { items, total }))
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct NewRepairInput {
    /// Optional when `ticket_id` is given and the ticket has a customer.
    pub customer_id: Option<Uuid>,
    pub contact_id: Option<Uuid>,
    /// The ticket where the customer announced the repair.
    pub ticket_id: Option<Uuid>,
    pub product_id: Option<Uuid>,
    #[serde(default)]
    pub product_description: String,
    #[serde(default)]
    pub serial_number: String,
    /// What is wrong. Defaults to the subject of the ticket.
    #[serde(default)]
    pub fault_description: String,
    #[serde(default)]
    pub customer_reference: String,
    #[serde(default = "default_warranty")]
    pub warranty: String,
    #[serde(default = "default_priority")]
    pub priority: String,
    /// True when the customer announced it but it has not arrived yet.
    #[serde(default)]
    pub announced: bool,
}

fn default_warranty() -> String {
    "unknown".into()
}
fn default_priority() -> String {
    "normal".into()
}

/// Registers a repair. Give a `ticket_id` to create it from the ticket where it was announced.
#[utoipa::path(post, path = "/repairs", tag = "repairs", operation_id = "create_repair", request_body = NewRepairInput,
    responses((status = 201, body = RepairDetail), (status = 422, body = ErrorBody)))]
async fn create_repair(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<NewRepairInput>,
) -> AppResult<(StatusCode, Json<RepairDetail>)> {
    user.require(Permission::RepairsWrite)?;
    let mut tx = state.db.begin().await?;
    let id = insert_repair(&mut tx, &user, &input, "staff", None).await?;
    let d = load_detail(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(d)))
}

/// Validates and inserts a repair with its `created` event, the note on its ticket and the audit
/// record, in the caller's transaction. The caller checks the permission. Shared by `POST /repairs`
/// and "create a repair from a package". `source_client_id` is the app's idempotency key, if any.
pub(crate) async fn insert_repair(
    tx: &mut PgConnection,
    user: &CurrentUser,
    input: &NewRepairInput,
    source: &str,
    source_client_id: Option<Uuid>,
) -> AppResult<Uuid> {
    check_one_of("priority", &input.priority, &PRIORITIES)?;
    check_one_of("warranty", &input.warranty, &WARRANTIES)?;
    let ticket = match input.ticket_id {
        Some(t) => {
            Some(tradocraft_helpdesk::tickets::load_ticket(&mut *tx, user.company_id, t).await?)
        }
        None => None,
    };
    let contact = match input
        .contact_id
        .or(ticket.as_ref().and_then(|t| t.contact_id))
    {
        Some(c) => Some(tradocraft_crm::contacts::get_contact(&mut *tx, c).await?),
        None => None,
    };
    let customer_id = input
        .customer_id
        .or(contact.as_ref().map(|c| c.customer_id))
        .or(ticket.as_ref().and_then(|t| t.customer_id))
        .ok_or_else(|| AppError::Validation("a customer is required".into()))?;
    if contact
        .as_ref()
        .is_some_and(|c| c.customer_id != customer_id)
        || ticket
            .as_ref()
            .and_then(|t| t.customer_id)
            .is_some_and(|c| c != customer_id)
    {
        return Err(AppError::Validation(
            "the contact or ticket belongs to another customer".into(),
        ));
    }
    let fault = if input.fault_description.trim().is_empty() {
        ticket
            .as_ref()
            .map(|t| t.subject.clone())
            .unwrap_or_default()
    } else {
        input.fault_description.trim().to_string()
    };
    if fault.trim().is_empty() {
        return Err(AppError::Validation("describe the fault".into()));
    }
    if let Some(p) = input.product_id {
        let known: bool =
            sqlx::query_scalar("SELECT EXISTS (SELECT 1 FROM products.products WHERE id = $1)")
                .bind(p)
                .fetch_one(&mut *tx)
                .await?;
        if !known {
            return Err(AppError::Validation("unknown product".into()));
        }
    }
    let number = next_number(&mut *tx, user.company_id).await?;
    let id = new_id();
    let status = if input.announced {
        "announced"
    } else {
        "received"
    };
    sqlx::query(
        "INSERT INTO repairs.repairs (id, company_id, number, status, priority, customer_id, contact_id, ticket_id, product_id,
                                      product_description, serial_number, fault_description, customer_reference, warranty,
                                      source, source_client_id, created_by, received_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17,
                 CASE WHEN $4 = 'received' THEN now() END)",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(&number)
    .bind(status)
    .bind(&input.priority)
    .bind(customer_id)
    .bind(contact.as_ref().map(|c| c.id))
    .bind(input.ticket_id)
    .bind(input.product_id)
    .bind(input.product_description.trim())
    .bind(input.serial_number.trim())
    .bind(&fault)
    .bind(input.customer_reference.trim())
    .bind(&input.warranty)
    .bind(source)
    .bind(source_client_id)
    .bind(user.user_id)
    .execute(&mut *tx)
    .await?;
    add_event(
        &mut *tx,
        id,
        Some(user.user_id),
        &user.display_name,
        Event {
            kind: "created",
            from_status: None,
            to_status: Some(status),
            from_department: None,
            to_department: None,
            note: "",
        },
    )
    .await?;
    warranty::refresh(&mut *tx, user.company_id, Some(user), id).await?;
    if let Some(t) = input.ticket_id {
        tradocraft_helpdesk::tickets::add_linked_note(
            &mut *tx,
            user,
            t,
            &format!("Repair {number} registered ({status})."),
        )
        .await?;
    }
    audit::record(
        &mut *tx,
        user,
        "repair",
        id,
        "created",
        serde_json::json!({ "number": number, "source": source }),
    )
    .await?;
    Ok(id)
}

#[utoipa::path(get, path = "/repairs/{id}", tag = "repairs", operation_id = "get_repair", params(("id" = Uuid, Path)),
    responses((status = 200, body = RepairDetail), (status = 404, body = ErrorBody)))]
async fn get_repair(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<RepairDetail>> {
    user.require(Permission::RepairsRead)?;
    let mut conn = state.db.acquire().await?;
    Ok(Json(load_detail(&mut conn, user.company_id, id).await?))
}

/// The repairs registered for a ticket (the ticket may announce several).
#[utoipa::path(get, path = "/tickets/{id}/repairs", tag = "repairs", operation_id = "list_ticket_repairs", params(("id" = Uuid, Path)),
    responses((status = 200, body = Vec<Repair>)))]
async fn list_ticket_repairs(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<Vec<Repair>>> {
    user.require(Permission::RepairsRead)?;
    Ok(Json(
        sqlx::query_as(&format!(
            "{SELECT} WHERE r.ticket_id = $1 AND r.company_id = $2 ORDER BY r.created_at"
        ))
        .bind(id)
        .bind(user.company_id)
        .fetch_all(&state.db)
        .await?,
    ))
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct RepairInput {
    pub contact_id: Option<Uuid>,
    pub product_id: Option<Uuid>,
    #[serde(default)]
    pub product_description: String,
    #[serde(default)]
    pub serial_number: String,
    pub fault_description: String,
    #[serde(default)]
    pub customer_reference: String,
    pub warranty: String,
    pub priority: String,
}

/// Changes the descriptive fields of a repair (not its status or department).
#[utoipa::path(put, path = "/repairs/{id}", tag = "repairs", operation_id = "update_repair", params(("id" = Uuid, Path)),
    request_body = RepairInput, responses((status = 200, body = RepairDetail), (status = 403, body = ErrorBody)))]
async fn update_repair(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<RepairInput>,
) -> AppResult<Json<RepairDetail>> {
    check_one_of("priority", &input.priority, &PRIORITIES)?;
    if input.fault_description.trim().is_empty() {
        return Err(AppError::Validation("describe the fault".into()));
    }
    let mut tx = state.db.begin().await?;
    let current = load_repair(&mut tx, user.company_id, id).await?;
    ensure_can_work(&mut tx, &user, id).await?;
    if let Some(c) = input.contact_id {
        let contact = tradocraft_crm::contacts::get_contact(&mut tx, c).await?;
        if contact.customer_id != current.customer_id {
            return Err(AppError::Validation(
                "the contact does not work for this customer".into(),
            ));
        }
    }
    // The warranty is typed by hand only while the lookup does not know it; the form sends the
    // stored value back unchanged otherwise.
    let warranty_changed = input.warranty != current.warranty;
    if warranty_changed {
        check_one_of("warranty", &input.warranty, &WARRANTIES)?;
        if current.warranty_overridden || current.warranty_auto != "unknown" {
            return Err(AppError::Validation(
                "the warranty follows the serial unit lookup; mark it void to override it".into(),
            ));
        }
    }
    let basis_changed = input.product_id != current.product_id
        || input.serial_number.trim() != current.serial_number;
    sqlx::query(
        "UPDATE repairs.repairs SET contact_id = $2, product_id = $3, product_description = $4, serial_number = $5,
                fault_description = $6, customer_reference = $7, warranty = $8, priority = $9, updated_at = now(),
                serial_unit_id = CASE WHEN $10 THEN NULL ELSE serial_unit_id END
         WHERE id = $1",
    )
    .bind(id)
    .bind(input.contact_id)
    .bind(input.product_id)
    .bind(input.product_description.trim())
    .bind(input.serial_number.trim())
    .bind(input.fault_description.trim())
    .bind(input.customer_reference.trim())
    .bind(&input.warranty)
    .bind(&input.priority)
    .bind(basis_changed)
    .execute(&mut *tx)
    .await?;
    if warranty_changed {
        add_event(
            &mut tx,
            id,
            Some(user.user_id),
            &user.display_name,
            Event {
                kind: "warranty_manual",
                from_status: None,
                to_status: None,
                from_department: None,
                to_department: None,
                note: &format!("{} -> {}", current.warranty, input.warranty),
            },
        )
        .await?;
    }
    // A changed serial number or product is looked up again.
    warranty::refresh(&mut tx, user.company_id, Some(&user), id).await?;
    audit::record(
        &mut tx,
        &user,
        "repair",
        id,
        "updated",
        serde_json::json!({}),
    )
    .await?;
    let d = load_detail(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok(Json(d))
}

// ---------------------------------------------------------------------------------------------
// Workflow: status, routing, notes
// ---------------------------------------------------------------------------------------------

#[derive(Debug, Deserialize, ToSchema)]
pub struct StatusInput {
    pub status: String,
    #[serde(default)]
    pub note: String,
}

/// Moves a repair along its workflow (everything except routing, see `/route`).
#[utoipa::path(post, path = "/repairs/{id}/status", tag = "repairs", operation_id = "set_repair_status",
    params(("id" = Uuid, Path)), request_body = StatusInput,
    responses((status = 200, body = RepairDetail), (status = 409, body = ErrorBody), (status = 403, body = ErrorBody)))]
async fn set_status(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<StatusInput>,
) -> AppResult<Json<RepairDetail>> {
    check_one_of("status", &input.status, &workflow::STATUSES)?;
    let mut tx = state.db.begin().await?;
    let current = load_repair(&mut tx, user.company_id, id).await?;
    ensure_can_work(&mut tx, &user, id).await?;
    if input.status == "routed" {
        return Err(AppError::Validation(
            "route the repair to a department instead".into(),
        ));
    }
    if !workflow::can_change(&current.status, &input.status) {
        return Err(AppError::Conflict(format!(
            "a repair that is {} cannot become {}",
            current.status, input.status
        )));
    }
    // Back to triage leaves the department; taking a repair in hand makes it yours.
    sqlx::query(
        "UPDATE repairs.repairs SET status = $2, updated_at = now(),
                department_id = CASE WHEN $2 = 'received' THEN NULL ELSE department_id END,
                assigned_user_id = CASE WHEN $2 = 'received' THEN NULL
                                        WHEN $2 = 'in_progress' THEN coalesce(assigned_user_id, $3)
                                        ELSE assigned_user_id END,
                received_at = CASE WHEN $2 = 'received' THEN coalesce(received_at, now()) ELSE received_at END,
                completed_at = CASE WHEN $2 = 'completed' THEN now() WHEN $2 = 'in_progress' THEN NULL ELSE completed_at END
         WHERE id = $1",
    )
    .bind(id)
    .bind(&input.status)
    .bind(user.user_id)
    .execute(&mut *tx)
    .await?;
    add_event(
        &mut tx,
        id,
        Some(user.user_id),
        &user.display_name,
        Event {
            kind: "status",
            from_status: Some(&current.status),
            to_status: Some(&input.status),
            from_department: current.department_id,
            to_department: None,
            note: input.note.trim(),
        },
    )
    .await?;
    if input.status == "received" && current.status == "announced" {
        // The product arrived: the warranty is compared with this date.
        warranty::refresh(&mut tx, user.company_id, Some(&user), id).await?;
    }
    audit::record(
        &mut tx,
        &user,
        "repair",
        id,
        "status",
        serde_json::json!({ "from": current.status, "to": input.status }),
    )
    .await?;
    let d = load_detail(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok(Json(d))
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct RouteInput {
    pub department_id: Uuid,
    /// A member of the department who should do it; leave empty to let the department pick it up.
    pub assigned_user_id: Option<Uuid>,
    #[serde(default)]
    pub note: String,
}

/// Routes a repair to a department (or on to another one). It waits there as `routed`.
#[utoipa::path(post, path = "/repairs/{id}/route", tag = "repairs", operation_id = "route_repair",
    params(("id" = Uuid, Path)), request_body = RouteInput,
    responses((status = 200, body = RepairDetail), (status = 409, body = ErrorBody), (status = 403, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn route_repair(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<RouteInput>,
) -> AppResult<Json<RepairDetail>> {
    user.require(Permission::RepairsRoute)?;
    let mut tx = state.db.begin().await?;
    let current = load_repair(&mut tx, user.company_id, id).await?;
    if !workflow::can_route_from(&current.status) {
        return Err(AppError::Conflict(format!(
            "a repair that is {} cannot be routed",
            current.status
        )));
    }
    let active: Option<bool> = sqlx::query_scalar(
        "SELECT active FROM repairs.departments WHERE id = $1 AND company_id = $2",
    )
    .bind(input.department_id)
    .bind(user.company_id)
    .fetch_optional(&mut *tx)
    .await?;
    match active {
        None => return Err(AppError::Validation("unknown department".into())),
        Some(false) => return Err(AppError::Validation("this department is not active".into())),
        Some(true) => {}
    }
    if let Some(u) = input.assigned_user_id {
        if !departments::is_member(&mut tx, input.department_id, u).await? {
            return Err(AppError::Validation(
                "that colleague does not work in this department".into(),
            ));
        }
    }
    sqlx::query(
        "UPDATE repairs.repairs SET status = 'routed', department_id = $2, assigned_user_id = $3, updated_at = now() WHERE id = $1",
    )
    .bind(id)
    .bind(input.department_id)
    .bind(input.assigned_user_id)
    .execute(&mut *tx)
    .await?;
    add_event(
        &mut tx,
        id,
        Some(user.user_id),
        &user.display_name,
        Event {
            kind: "routed",
            from_status: Some(&current.status),
            to_status: Some("routed"),
            from_department: current.department_id,
            to_department: Some(input.department_id),
            note: input.note.trim(),
        },
    )
    .await?;
    audit::record(
        &mut tx,
        &user,
        "repair",
        id,
        "routed",
        serde_json::json!({ "department_id": input.department_id }),
    )
    .await?;
    let d = load_detail(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok(Json(d))
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct RepairNoteInput {
    pub note: String,
}

/// An internal note on the repair (diagnosis, parts used, test results). The customer never sees it.
#[utoipa::path(post, path = "/repairs/{id}/notes", tag = "repairs", operation_id = "add_repair_note",
    params(("id" = Uuid, Path)), request_body = RepairNoteInput,
    responses((status = 201, body = RepairDetail), (status = 403, body = ErrorBody)))]
async fn add_note(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<RepairNoteInput>,
) -> AppResult<(StatusCode, Json<RepairDetail>)> {
    if input.note.trim().is_empty() {
        return Err(AppError::Validation("the note is empty".into()));
    }
    let mut tx = state.db.begin().await?;
    load_repair(&mut tx, user.company_id, id).await?;
    ensure_can_work(&mut tx, &user, id).await?;
    add_event(
        &mut tx,
        id,
        Some(user.user_id),
        &user.display_name,
        Event {
            kind: "note",
            from_status: None,
            to_status: None,
            from_department: None,
            to_department: None,
            note: input.note.trim(),
        },
    )
    .await?;
    sqlx::query("UPDATE repairs.repairs SET updated_at = now() WHERE id = $1")
        .bind(id)
        .execute(&mut *tx)
        .await?;
    let d = load_detail(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(d)))
}

// ---------------------------------------------------------------------------------------------
// Photos
// ---------------------------------------------------------------------------------------------

#[derive(Debug, Deserialize, IntoParams)]
pub struct UploadParams {
    pub caption: Option<String>,
    /// The original file name.
    pub filename: Option<String>,
    /// A client-chosen id: uploading the same id again returns the first upload (safe retries).
    pub client_id: Option<Uuid>,
}

/// Links an uploaded image to a repair (idempotent on the file id). Shared with the portal.
pub(crate) async fn attach_photo(
    conn: &mut PgConnection,
    company_id: Uuid,
    repair_id: Uuid,
    file: &FileInfo,
    caption: &str,
) -> AppResult<()> {
    let inserted = sqlx::query(
        "INSERT INTO repairs.photos (id, repair_id, file_id, caption) VALUES ($1, $2, $3, $4) ON CONFLICT (file_id) DO NOTHING",
    )
    .bind(new_id())
    .bind(repair_id)
    .bind(file.id)
    .bind(caption.trim())
    .execute(&mut *conn)
    .await?;
    if inserted.rows_affected() == 0 {
        let same: bool = sqlx::query_scalar(
            "SELECT EXISTS (SELECT 1 FROM repairs.photos WHERE file_id = $1 AND repair_id = $2)",
        )
        .bind(file.id)
        .bind(repair_id)
        .fetch_one(&mut *conn)
        .await?;
        if !same {
            return Err(AppError::Conflict(
                "this photo id belongs to another record".into(),
            ));
        }
    } else {
        sqlx::query(
            "UPDATE repairs.repairs SET updated_at = now() WHERE id = $1 AND company_id = $2",
        )
        .bind(repair_id)
        .bind(company_id)
        .execute(conn)
        .await?;
    }
    Ok(())
}

/// Adds a photo: the request body is the image itself (JPEG, PNG or WebP, at most 12 MB).
#[utoipa::path(post, path = "/repairs/{id}/photos", tag = "repairs", operation_id = "upload_repair_photo",
    params(("id" = Uuid, Path), UploadParams),
    request_body(content = String, content_type = "application/octet-stream"),
    responses((status = 201, body = RepairDetail), (status = 403, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn upload_photo(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Query(p): Query<UploadParams>,
    body: Bytes,
) -> AppResult<(StatusCode, Json<RepairDetail>)> {
    let mut tx = state.db.begin().await?;
    load_repair(&mut tx, user.company_id, id).await?;
    ensure_can_work(&mut tx, &user, id).await?;
    let file = files::store_image(
        &mut tx,
        &state.blobs,
        user.company_id,
        p.client_id,
        p.filename.as_deref().unwrap_or(""),
        &body,
        Some(user.user_id),
        &user.display_name,
    )
    .await?;
    attach_photo(
        &mut tx,
        user.company_id,
        id,
        &file,
        p.caption.as_deref().unwrap_or(""),
    )
    .await?;
    add_event(
        &mut tx,
        id,
        Some(user.user_id),
        &user.display_name,
        Event {
            kind: "photo",
            from_status: None,
            to_status: None,
            from_department: None,
            to_department: None,
            note: p.caption.as_deref().unwrap_or("").trim(),
        },
    )
    .await?;
    let d = load_detail(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(d)))
}

/// The image itself.
#[utoipa::path(get, path = "/repairs/{id}/photos/{photo_id}", tag = "repairs", operation_id = "get_repair_photo",
    params(("id" = Uuid, Path), ("photo_id" = Uuid, Path)),
    responses((status = 200, content_type = "image/*", body = String), (status = 404, body = ErrorBody)))]
async fn get_photo(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((id, photo_id)): Path<(Uuid, Uuid)>,
) -> AppResult<Response> {
    user.require(Permission::RepairsRead)?;
    let mut conn = state.db.acquire().await?;
    load_repair(&mut conn, user.company_id, id).await?;
    let linked: bool = sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM repairs.photos WHERE repair_id = $1 AND file_id = $2)",
    )
    .bind(id)
    .bind(photo_id)
    .fetch_one(&mut *conn)
    .await?;
    if !linked {
        return Err(AppError::NotFound("photo"));
    }
    let (content_type, data) =
        files::load(&mut conn, &state.blobs, user.company_id, photo_id).await?;
    Ok(files::image_response(&content_type, data))
}

pub fn router() -> OpenApiRouter<AppState> {
    // Uploads carry whole photos: raise the default body limit for them only.
    let uploads = OpenApiRouter::new()
        .routes(routes!(upload_photo))
        .layer(DefaultBodyLimit::max(MAX_FILE_BYTES + 64 * 1024));
    OpenApiRouter::new()
        .merge(departments::router())
        .merge(packages::router())
        .merge(warranty::router())
        .routes(routes!(list_repairs, create_repair))
        .routes(routes!(get_repair, update_repair))
        .routes(routes!(list_ticket_repairs))
        .routes(routes!(set_status))
        .routes(routes!(route_repair))
        .routes(routes!(add_note))
        .routes(routes!(get_photo))
        .merge(uploads)
}
