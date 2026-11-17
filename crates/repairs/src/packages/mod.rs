//! Incoming packages (ADR 0030): a parcel from a customer is registered at the dock, opened by
//! someone who decides what it is, and then matched with a repair the customer announced, turned
//! into a new repair, or closed. The repair itself keeps the workflow of `crate::workflow`.
//!
//! Rights: `packages.read` to see parcels, `packages.write` to register, edit and photograph them
//! (and to refuse one unopened), `packages.open` to open one and decide what it is,
//! `repairs.intake` to link it with a repair. Routing a repair stays `POST /repairs/{id}/route`.

pub mod matching;
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

use crate::{
    add_event as add_repair_event, check_one_of, insert_repair, load_detail, load_repair, Event,
    NewRepairInput, Photo, Repair, RepairDetail, UploadParams,
};

type ErrorBody = tradocraft_core::error::ErrorBody;

/// The fault text of a repair created from a parcel before anyone has looked at the product.
pub const FAULT_TO_BE_DETERMINED: &str = "To be determined at intake";

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct Package {
    pub id: Uuid,
    /// PK-2027-00001
    pub number: String,
    /// registered | opened | linked | closed
    pub status: String,
    /// What it turned out to be: repair | other | return_to_sender. Empty until opened.
    pub kind: Option<String>,
    /// The sender, when known. Resolved at triage if the label only had a name.
    pub customer_id: Option<Uuid>,
    pub customer_name: Option<String>,
    /// The sender as written on the label.
    pub sender_name: String,
    pub carrier: String,
    pub tracking_number: String,
    pub parcel_count: i32,
    /// intact | damaged | opened | wet
    pub condition: String,
    pub condition_note: String,
    /// The customer's RMA number or the reference on their slip.
    pub customer_reference: String,
    pub received_by: Uuid,
    pub received_by_name: String,
    pub received_at: DateTime<Utc>,
    pub opened_by: Option<Uuid>,
    pub opened_by_name: Option<String>,
    pub opened_at: Option<DateTime<Utc>>,
    pub notes: String,
    pub photo_count: i64,
    /// How many repairs are linked to this parcel.
    pub repair_count: i64,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct PackageEvent {
    pub id: Uuid,
    /// registered | status | note | photo | linked | unlinked
    pub kind: String,
    pub from_status: Option<String>,
    pub to_status: Option<String>,
    pub repair_id: Option<Uuid>,
    pub repair_number: Option<String>,
    pub note: String,
    pub actor_name: String,
    pub created_at: DateTime<Utc>,
}

/// A repair linked to a parcel.
#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct PackageRepairRef {
    pub id: Uuid,
    pub number: String,
    pub status: String,
    pub customer_name: String,
    pub product_description: String,
    pub serial_number: String,
    pub linked_at: DateTime<Utc>,
    pub linked_by_name: Option<String>,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct PackageDetail {
    pub package: Package,
    /// Photos of the box and its condition. Fetch one from `/packages/{id}/photos/{photo_id}`.
    pub photos: Vec<Photo>,
    pub events: Vec<PackageEvent>,
    pub repairs: Vec<PackageRepairRef>,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct PackagePage {
    pub items: Vec<Package>,
    pub total: i64,
}

/// An announced repair that may belong to a parcel, with why.
#[derive(Debug, Serialize, ToSchema)]
pub struct RepairSuggestion {
    pub repair: Repair,
    pub score: i32,
    /// serial | customer | reference | ticket | product | recent
    pub reasons: Vec<String>,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct PackageRepairSuggestions {
    /// At most 10, best first. Never applied automatically: confirm with `POST /packages/{id}/repairs`.
    pub suggestions: Vec<RepairSuggestion>,
    /// When the parcel has no customer yet: the customer of the best suggestion.
    pub proposed_customer_id: Option<Uuid>,
    pub proposed_customer_name: Option<String>,
}

const SELECT: &str = "SELECT k.id, k.number, k.status, k.kind, k.customer_id, c.name AS customer_name, k.sender_name,
        k.carrier, k.tracking_number, k.parcel_count, k.condition, k.condition_note, k.customer_reference,
        k.received_by, rb.display_name AS received_by_name, k.received_at,
        k.opened_by, ob.display_name AS opened_by_name, k.opened_at, k.notes,
        (SELECT count(*) FROM repairs.package_photos ph WHERE ph.package_id = k.id) AS photo_count,
        (SELECT count(*) FROM repairs.package_repairs pr WHERE pr.package_id = k.id) AS repair_count,
        k.created_at, k.updated_at
     FROM repairs.packages k
     LEFT JOIN crm.customers c ON c.id = k.customer_id
     JOIN core.users rb ON rb.id = k.received_by
     LEFT JOIN core.users ob ON ob.id = k.opened_by";

/// Loads a parcel of the company, optionally locking the row.
async fn load_package(
    conn: &mut PgConnection,
    company_id: Uuid,
    id: Uuid,
    lock: bool,
) -> AppResult<Package> {
    let lock = if lock { " FOR UPDATE OF k" } else { "" };
    sqlx::query_as(&format!(
        "{SELECT} WHERE k.id = $1 AND k.company_id = $2{lock}"
    ))
    .bind(id)
    .bind(company_id)
    .fetch_optional(conn)
    .await?
    .ok_or(AppError::NotFound("package"))
}

/// Loads a parcel with its events, photos and repairs.
async fn load_detail_of(
    conn: &mut PgConnection,
    company_id: Uuid,
    id: Uuid,
) -> AppResult<PackageDetail> {
    let package = load_package(conn, company_id, id, false).await?;
    let photos = sqlx::query_as(
        "SELECT f.id, p.caption, f.filename, f.content_type, f.size_bytes, f.uploader_name, p.created_at
         FROM repairs.package_photos p JOIN core.files f ON f.id = p.file_id
         WHERE p.package_id = $1 ORDER BY p.created_at, p.id",
    )
    .bind(id)
    .fetch_all(&mut *conn)
    .await?;
    let events = sqlx::query_as(
        "SELECT e.id, e.kind, e.from_status, e.to_status, e.repair_id, r.number AS repair_number, e.note,
                coalesce(u.display_name, e.actor_name) AS actor_name, e.created_at
         FROM repairs.package_events e
         LEFT JOIN repairs.repairs r ON r.id = e.repair_id
         LEFT JOIN core.users u ON u.id = e.user_id
         WHERE e.package_id = $1 ORDER BY e.created_at, e.id",
    )
    .bind(id)
    .fetch_all(&mut *conn)
    .await?;
    let repairs = sqlx::query_as(
        "SELECT r.id, r.number, r.status, c.name AS customer_name, r.product_description, r.serial_number,
                pr.linked_at, u.display_name AS linked_by_name
         FROM repairs.package_repairs pr
         JOIN repairs.repairs r ON r.id = pr.repair_id
         JOIN crm.customers c ON c.id = r.customer_id
         LEFT JOIN core.users u ON u.id = pr.linked_by
         WHERE pr.package_id = $1 ORDER BY pr.linked_at, r.number",
    )
    .bind(id)
    .fetch_all(&mut *conn)
    .await?;
    Ok(PackageDetail {
        package,
        photos,
        events,
        repairs,
    })
}

struct PkgEvent<'a> {
    kind: &'a str,
    from_status: Option<&'a str>,
    to_status: Option<&'a str>,
    repair_id: Option<Uuid>,
    note: &'a str,
}

/// Records an event in the history of a parcel.
async fn add_event(
    conn: &mut PgConnection,
    package_id: Uuid,
    user: &CurrentUser,
    e: PkgEvent<'_>,
) -> AppResult<()> {
    sqlx::query(
        "INSERT INTO repairs.package_events (id, package_id, kind, from_status, to_status, repair_id, note, user_id, actor_name)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)",
    )
    .bind(new_id())
    .bind(package_id)
    .bind(e.kind)
    .bind(e.from_status)
    .bind(e.to_status)
    .bind(e.repair_id)
    .bind(e.note.trim())
    .bind(user.user_id)
    .bind(&user.display_name)
    .execute(conn)
    .await?;
    Ok(())
}

/// The next package number of the year (`PK-YYYY-NNNNN`).
async fn next_number(conn: &mut PgConnection, company_id: Uuid) -> AppResult<String> {
    let year = Utc::now().year();
    let n = tradocraft_core::numbering::next_number(conn, company_id, "package", year).await?;
    Ok(format!("PK-{year}-{n:05}"))
}

/// Fails when the customer does not exist.
async fn ensure_customer(conn: &mut PgConnection, id: Uuid) -> AppResult<()> {
    let known: bool =
        sqlx::query_scalar("SELECT EXISTS (SELECT 1 FROM crm.customers WHERE id = $1)")
            .bind(id)
            .fetch_one(conn)
            .await?;
    if known {
        Ok(())
    } else {
        Err(AppError::Validation("unknown customer".into()))
    }
}

// ---------------------------------------------------------------------------------------------
// Register, list, read, edit
// ---------------------------------------------------------------------------------------------

#[derive(Debug, Deserialize, ToSchema)]
pub struct PackageInput {
    /// A key chosen by the app: registering the same key again returns the first parcel.
    pub client_id: Option<Uuid>,
    pub customer_id: Option<Uuid>,
    /// The sender as written on the label.
    #[serde(default)]
    pub sender_name: String,
    #[serde(default)]
    pub carrier: String,
    #[serde(default)]
    pub tracking_number: String,
    #[serde(default = "one")]
    pub parcel_count: i32,
    /// intact | damaged | opened | wet. Defaults to intact.
    #[serde(default = "intact")]
    pub condition: String,
    #[serde(default)]
    pub condition_note: String,
    #[serde(default)]
    pub customer_reference: String,
    #[serde(default)]
    pub notes: String,
}

/// Serde default for the parcel count.
fn one() -> i32 {
    1
}
/// Serde default for the condition.
fn intact() -> String {
    "intact".into()
}

/// Validates the fields of a parcel.
async fn check_input(conn: &mut PgConnection, input: &PackageInput) -> AppResult<()> {
    check_one_of("condition", &input.condition, &workflow::CONDITIONS)?;
    if !(1..=99).contains(&input.parcel_count) {
        return Err(AppError::Validation(
            "parcel_count must be between 1 and 99".into(),
        ));
    }
    if input.customer_id.is_none()
        && input.sender_name.trim().is_empty()
        && input.tracking_number.trim().is_empty()
    {
        return Err(AppError::Validation(
            "enter the customer, the sender or a tracking number".into(),
        ));
    }
    if let Some(c) = input.customer_id {
        ensure_customer(conn, c).await?;
    }
    Ok(())
}

/// Registers a parcel at the dock. The same `client_id` again returns the first parcel (200).
#[utoipa::path(post, path = "/packages", tag = "repairs", operation_id = "create_package", request_body = PackageInput,
    responses((status = 201, body = PackageDetail), (status = 200, body = PackageDetail, description = "this client_id was registered before"),
              (status = 403, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn create_package(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<PackageInput>,
) -> AppResult<(StatusCode, Json<PackageDetail>)> {
    user.require(Permission::PackagesWrite)?;
    let mut tx = state.db.begin().await?;
    if let Some(existing) = find_by_client_id(&mut tx, user.company_id, input.client_id).await? {
        let d = load_detail_of(&mut tx, user.company_id, existing).await?;
        return Ok((StatusCode::OK, Json(d)));
    }
    check_input(&mut tx, &input).await?;
    let number = next_number(&mut tx, user.company_id).await?;
    let id = new_id();
    let inserted = sqlx::query(
        "INSERT INTO repairs.packages (id, company_id, number, customer_id, sender_name, carrier, tracking_number,
                                       parcel_count, condition, condition_note, customer_reference, received_by, notes, client_id)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
         ON CONFLICT (company_id, client_id) DO NOTHING",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(&number)
    .bind(input.customer_id)
    .bind(input.sender_name.trim())
    .bind(input.carrier.trim())
    .bind(input.tracking_number.trim())
    .bind(input.parcel_count)
    .bind(&input.condition)
    .bind(input.condition_note.trim())
    .bind(input.customer_reference.trim())
    .bind(user.user_id)
    .bind(input.notes.trim())
    .bind(input.client_id)
    .execute(&mut *tx)
    .await?;
    if inserted.rows_affected() == 0 {
        // A parallel request with the same client_id won: return its parcel.
        tx.rollback().await?;
        let mut conn = state.db.acquire().await?;
        let existing = find_by_client_id(&mut conn, user.company_id, input.client_id)
            .await?
            .ok_or_else(|| AppError::Conflict("could not register the parcel, try again".into()))?;
        let d = load_detail_of(&mut conn, user.company_id, existing).await?;
        return Ok((StatusCode::OK, Json(d)));
    }
    add_event(
        &mut tx,
        id,
        &user,
        PkgEvent {
            kind: "registered",
            from_status: None,
            to_status: Some("registered"),
            repair_id: None,
            note: "",
        },
    )
    .await?;
    audit::record(
        &mut tx,
        &user,
        "package",
        id,
        "registered",
        serde_json::json!({ "number": number }),
    )
    .await?;
    let d = load_detail_of(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(d)))
}

/// The parcel registered earlier with this client id, if any.
async fn find_by_client_id(
    conn: &mut PgConnection,
    company_id: Uuid,
    client_id: Option<Uuid>,
) -> AppResult<Option<Uuid>> {
    let Some(client_id) = client_id else {
        return Ok(None);
    };
    Ok(sqlx::query_scalar(
        "SELECT id FROM repairs.packages WHERE company_id = $1 AND client_id = $2",
    )
    .bind(company_id)
    .bind(client_id)
    .fetch_optional(conn)
    .await?)
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct PackageListParams {
    /// Searches number, tracking number, sender, customer and the customer's reference.
    pub q: Option<String>,
    /// A status, or `open` for everything not closed.
    pub status: Option<String>,
    /// repair | other | return_to_sender
    pub kind: Option<String>,
    pub customer_id: Option<Uuid>,
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}

#[utoipa::path(get, path = "/packages", tag = "repairs", operation_id = "list_packages", params(PackageListParams),
    responses((status = 200, body = PackagePage), (status = 403, body = ErrorBody)))]
async fn list_packages(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(p): Query<PackageListParams>,
) -> AppResult<Json<PackagePage>> {
    user.require(Permission::PackagesRead)?;
    let status = p.status.as_deref().filter(|s| *s != "all");
    if let Some(s) = status {
        if s != "open" {
            check_one_of("status", s, &workflow::STATUSES)?;
        }
    }
    if let Some(k) = p.kind.as_deref() {
        check_one_of("kind", k, &workflow::KINDS)?;
    }
    let pattern =
        p.q.as_deref()
            .map(str::trim)
            .filter(|q| !q.is_empty())
            .map(|q| format!("%{}%", q.to_lowercase()));
    let filter = "WHERE k.company_id = $1
        AND ($2::text IS NULL OR ($2 = 'open' AND k.status <> 'closed') OR k.status = $2)
        AND ($3::text IS NULL OR k.kind = $3)
        AND ($4::uuid IS NULL OR k.customer_id = $4)
        AND ($5::text IS NULL OR lower(k.number) LIKE $5 OR lower(k.tracking_number) LIKE $5
             OR lower(k.sender_name) LIKE $5 OR lower(coalesce(c.name, '')) LIKE $5
             OR lower(k.customer_reference) LIKE $5)";
    let items: Vec<Package> = sqlx::query_as(&format!(
        "{SELECT} {filter} ORDER BY k.received_at DESC, k.id DESC LIMIT $6 OFFSET $7"
    ))
    .bind(user.company_id)
    .bind(status)
    .bind(p.kind.as_deref())
    .bind(p.customer_id)
    .bind(&pattern)
    .bind(p.limit.unwrap_or(50).clamp(1, 500))
    .bind(p.offset.unwrap_or(0).max(0))
    .fetch_all(&state.db)
    .await?;
    let total: i64 = sqlx::query_scalar(&format!(
        "SELECT count(*) FROM repairs.packages k LEFT JOIN crm.customers c ON c.id = k.customer_id {filter}"
    ))
    .bind(user.company_id)
    .bind(status)
    .bind(p.kind.as_deref())
    .bind(p.customer_id)
    .bind(&pattern)
    .fetch_one(&state.db)
    .await?;
    Ok(Json(PackagePage { items, total }))
}

#[utoipa::path(get, path = "/packages/{id}", tag = "repairs", operation_id = "get_package", params(("id" = Uuid, Path)),
    responses((status = 200, body = PackageDetail), (status = 404, body = ErrorBody)))]
async fn get_package(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<PackageDetail>> {
    user.require(Permission::PackagesRead)?;
    let mut conn = state.db.acquire().await?;
    Ok(Json(load_detail_of(&mut conn, user.company_id, id).await?))
}

/// Corrects the details of a parcel while it is registered or opened.
#[utoipa::path(put, path = "/packages/{id}", tag = "repairs", operation_id = "update_package", params(("id" = Uuid, Path)),
    request_body = PackageInput,
    responses((status = 200, body = PackageDetail), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn update_package(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<PackageInput>,
) -> AppResult<Json<PackageDetail>> {
    user.require(Permission::PackagesWrite)?;
    let mut tx = state.db.begin().await?;
    let current = load_package(&mut tx, user.company_id, id, true).await?;
    if !workflow::is_editable(&current.status) {
        return Err(AppError::Conflict(format!(
            "a package that is {} can no longer be edited",
            current.status
        )));
    }
    check_input(&mut tx, &input).await?;
    sqlx::query(
        "UPDATE repairs.packages SET customer_id = $2, sender_name = $3, carrier = $4, tracking_number = $5,
                parcel_count = $6, condition = $7, condition_note = $8, customer_reference = $9, notes = $10,
                updated_at = now()
         WHERE id = $1",
    )
    .bind(id)
    .bind(input.customer_id)
    .bind(input.sender_name.trim())
    .bind(input.carrier.trim())
    .bind(input.tracking_number.trim())
    .bind(input.parcel_count)
    .bind(&input.condition)
    .bind(input.condition_note.trim())
    .bind(input.customer_reference.trim())
    .bind(input.notes.trim())
    .execute(&mut *tx)
    .await?;
    audit::record(
        &mut tx,
        &user,
        "package",
        id,
        "updated",
        serde_json::json!({}),
    )
    .await?;
    let d = load_detail_of(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok(Json(d))
}

// ---------------------------------------------------------------------------------------------
// Photos
// ---------------------------------------------------------------------------------------------

/// Adds a photo of the box: the request body is the image itself (JPEG, PNG or WebP, at most 12 MB).
/// The same `client_id` again does not add a second photo.
#[utoipa::path(post, path = "/packages/{id}/photos", tag = "repairs", operation_id = "upload_package_photo",
    params(("id" = Uuid, Path), UploadParams),
    request_body(content = String, content_type = "application/octet-stream"),
    responses((status = 201, body = PackageDetail), (status = 403, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn upload_photo(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Query(p): Query<UploadParams>,
    body: Bytes,
) -> AppResult<(StatusCode, Json<PackageDetail>)> {
    user.require(Permission::PackagesWrite)?;
    let mut tx = state.db.begin().await?;
    load_package(&mut tx, user.company_id, id, true).await?;
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
    let caption = p.caption.as_deref().unwrap_or("").trim();
    if attach_photo(&mut tx, id, &file, caption).await? {
        add_event(
            &mut tx,
            id,
            &user,
            PkgEvent {
                kind: "photo",
                from_status: None,
                to_status: None,
                repair_id: None,
                note: caption,
            },
        )
        .await?;
        sqlx::query("UPDATE repairs.packages SET updated_at = now() WHERE id = $1")
            .bind(id)
            .execute(&mut *tx)
            .await?;
    }
    let d = load_detail_of(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(d)))
}

/// Links an uploaded image to a parcel (idempotent on the file id). True when it was new.
async fn attach_photo(
    conn: &mut PgConnection,
    package_id: Uuid,
    file: &FileInfo,
    caption: &str,
) -> AppResult<bool> {
    let inserted = sqlx::query(
        "INSERT INTO repairs.package_photos (id, package_id, file_id, caption) VALUES ($1, $2, $3, $4)
         ON CONFLICT (file_id) DO NOTHING",
    )
    .bind(new_id())
    .bind(package_id)
    .bind(file.id)
    .bind(caption)
    .execute(&mut *conn)
    .await?;
    if inserted.rows_affected() > 0 {
        return Ok(true);
    }
    let same: bool = sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM repairs.package_photos WHERE file_id = $1 AND package_id = $2)",
    )
    .bind(file.id)
    .bind(package_id)
    .fetch_one(conn)
    .await?;
    if same {
        Ok(false)
    } else {
        Err(AppError::Conflict(
            "this photo id belongs to another record".into(),
        ))
    }
}

/// The image itself.
#[utoipa::path(get, path = "/packages/{id}/photos/{photo_id}", tag = "repairs", operation_id = "get_package_photo",
    params(("id" = Uuid, Path), ("photo_id" = Uuid, Path)),
    responses((status = 200, content_type = "image/*", body = String), (status = 404, body = ErrorBody)))]
async fn get_photo(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((id, photo_id)): Path<(Uuid, Uuid)>,
) -> AppResult<Response> {
    user.require(Permission::PackagesRead)?;
    let mut conn = state.db.acquire().await?;
    load_package(&mut conn, user.company_id, id, false).await?;
    let linked: bool = sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM repairs.package_photos WHERE package_id = $1 AND file_id = $2)",
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

// ---------------------------------------------------------------------------------------------
// Open, close
// ---------------------------------------------------------------------------------------------

#[derive(Debug, Deserialize, ToSchema)]
pub struct PackageOpenInput {
    /// What the parcel is: repair | other | return_to_sender.
    pub kind: String,
    /// Set or correct the sender now that the parcel is open.
    pub customer_id: Option<Uuid>,
    /// Required for `other` and `return_to_sender`: what it is, or why it goes back.
    #[serde(default)]
    pub note: String,
}

/// Opens a parcel and decides what it is. A `repair` parcel becomes `opened` and waits to be linked
/// with a repair; `other` and `return_to_sender` close it at once (a note is required).
#[utoipa::path(post, path = "/packages/{id}/open", tag = "repairs", operation_id = "open_package",
    params(("id" = Uuid, Path)), request_body = PackageOpenInput,
    responses((status = 200, body = PackageDetail), (status = 403, body = ErrorBody), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn open_package(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<PackageOpenInput>,
) -> AppResult<Json<PackageDetail>> {
    user.require(Permission::PackagesOpen)?;
    let to = workflow::status_after_open(&input.kind).ok_or_else(|| {
        AppError::Validation(format!(
            "kind must be one of {}",
            workflow::KINDS.join(", ")
        ))
    })?;
    if to == "closed" && input.note.trim().is_empty() {
        return Err(AppError::Validation(
            "say what the parcel is, or why it goes back".into(),
        ));
    }
    let mut tx = state.db.begin().await?;
    let current = load_package(&mut tx, user.company_id, id, true).await?;
    if current.status != "registered" || !workflow::can_change(&current.status, "opened") {
        return Err(AppError::Conflict(format!(
            "a package that is {} cannot be opened",
            current.status
        )));
    }
    if let Some(c) = input.customer_id {
        ensure_customer(&mut tx, c).await?;
    }
    sqlx::query(
        "UPDATE repairs.packages SET status = $2, kind = $3, customer_id = coalesce($4, customer_id),
                opened_by = $5, opened_at = now(), updated_at = now()
         WHERE id = $1",
    )
    .bind(id)
    .bind(to)
    .bind(&input.kind)
    .bind(input.customer_id)
    .bind(user.user_id)
    .execute(&mut *tx)
    .await?;
    add_event(
        &mut tx,
        id,
        &user,
        PkgEvent {
            kind: "status",
            from_status: Some(&current.status),
            to_status: Some(to),
            repair_id: None,
            note: &input.note,
        },
    )
    .await?;
    audit::record(
        &mut tx,
        &user,
        "package",
        id,
        "opened",
        serde_json::json!({ "kind": input.kind }),
    )
    .await?;
    let d = load_detail_of(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok(Json(d))
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct PackageCloseInput {
    /// Why: refused at the dock, sent back, nothing to repair.
    pub note: String,
}

/// Closes a parcel without a repair: refused at the dock and sent back unopened (`registered`), or
/// an opened repair parcel that turned out to hold nothing to repair (needs `packages.open` too).
#[utoipa::path(post, path = "/packages/{id}/close", tag = "repairs", operation_id = "close_package",
    params(("id" = Uuid, Path)), request_body = PackageCloseInput,
    responses((status = 200, body = PackageDetail), (status = 403, body = ErrorBody), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn close_package(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<PackageCloseInput>,
) -> AppResult<Json<PackageDetail>> {
    user.require(Permission::PackagesWrite)?;
    if input.note.trim().is_empty() {
        return Err(AppError::Validation("say why the parcel is closed".into()));
    }
    let mut tx = state.db.begin().await?;
    let current = load_package(&mut tx, user.company_id, id, true).await?;
    if !workflow::can_change(&current.status, "closed") {
        return Err(AppError::Conflict(format!(
            "a package that is {} cannot be closed",
            current.status
        )));
    }
    if current.status == "opened" {
        user.require(Permission::PackagesOpen)?;
    }
    // Refused unopened: it goes back to the sender.
    sqlx::query(
        "UPDATE repairs.packages SET status = 'closed', kind = coalesce(kind, 'return_to_sender'), updated_at = now()
         WHERE id = $1",
    )
    .bind(id)
    .execute(&mut *tx)
    .await?;
    add_event(
        &mut tx,
        id,
        &user,
        PkgEvent {
            kind: "status",
            from_status: Some(&current.status),
            to_status: Some("closed"),
            repair_id: None,
            note: &input.note,
        },
    )
    .await?;
    audit::record(
        &mut tx,
        &user,
        "package",
        id,
        "closed",
        serde_json::json!({}),
    )
    .await?;
    let d = load_detail_of(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok(Json(d))
}

// ---------------------------------------------------------------------------------------------
// Matching with repairs
// ---------------------------------------------------------------------------------------------

#[derive(Debug, Deserialize, IntoParams)]
pub struct SuggestParams {
    /// The serial number read from the product.
    pub serial: Option<String>,
    /// A ticket number the customer mentioned.
    pub ticket: Option<String>,
    /// What the product is, as far as one can tell.
    pub product: Option<String>,
}

/// Announced repairs that may belong to this parcel, best first, with the reasons. Nothing is linked:
/// confirm with `POST /packages/{id}/repairs`.
#[utoipa::path(get, path = "/packages/{id}/repair-suggestions", tag = "repairs", operation_id = "list_package_repair_suggestions",
    params(("id" = Uuid, Path), SuggestParams),
    responses((status = 200, body = PackageRepairSuggestions), (status = 403, body = ErrorBody), (status = 409, body = ErrorBody)))]
async fn repair_suggestions(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Query(p): Query<SuggestParams>,
) -> AppResult<Json<PackageRepairSuggestions>> {
    user.require(Permission::RepairsIntake)?;
    let mut conn = state.db.acquire().await?;
    let pkg = load_package(&mut conn, user.company_id, id, false).await?;
    if !workflow::can_take_repairs(&pkg.status, pkg.kind.as_deref()) {
        return Err(AppError::Conflict(
            "only an opened repair parcel can be matched".into(),
        ));
    }
    let announced: Vec<Repair> = sqlx::query_as(&format!(
        "{} WHERE r.company_id = $1 AND r.status = 'announced'
         ORDER BY (nullif(btrim($2), '') IS NOT NULL AND lower(btrim(r.serial_number)) = lower(btrim($2))) DESC,
                  (nullif(btrim($3), '') IS NOT NULL AND (lower(btrim(t.number)) = lower(btrim($3))
                      OR lower(btrim(r.customer_reference)) = lower(btrim($3)))) DESC,
                  (r.customer_id IS NOT DISTINCT FROM $4) DESC,
                  r.created_at DESC
         LIMIT 1000",
        crate::SELECT
    ))
    .bind(user.company_id)
    .bind(p.serial.as_deref().unwrap_or(""))
    .bind(p.ticket.as_deref().unwrap_or(""))
    .bind(pkg.customer_id)
    .fetch_all(&mut *conn)
    .await?;
    let wanted = matching::Wanted {
        customer_id: pkg.customer_id,
        customer_reference: &pkg.customer_reference,
        serial: p.serial.as_deref().unwrap_or(""),
        ticket_number: p.ticket.as_deref().unwrap_or(""),
        product: p.product.as_deref().unwrap_or(""),
    };
    let now = Utc::now();
    let mut scored: Vec<RepairSuggestion> = announced
        .into_iter()
        .filter_map(|r| {
            let (score, reasons) = matching::score(
                &wanted,
                &matching::Candidate {
                    customer_id: r.customer_id,
                    customer_reference: &r.customer_reference,
                    serial_number: &r.serial_number,
                    ticket_number: r.ticket_number.as_deref(),
                    product_description: &r.product_description,
                    product_code: r.product_code.as_deref(),
                    announced_at: r.created_at,
                },
                now,
            );
            matching::is_match(&reasons).then(|| RepairSuggestion {
                repair: r,
                score,
                reasons: reasons.into_iter().map(String::from).collect(),
            })
        })
        .collect();
    // Best first; among equals the most recent announcement.
    scored.sort_by(|a, b| {
        b.score
            .cmp(&a.score)
            .then(b.repair.created_at.cmp(&a.repair.created_at))
    });
    scored.truncate(matching::MAX_SUGGESTIONS);
    let proposed = pkg
        .customer_id
        .is_none()
        .then(|| {
            scored
                .first()
                .map(|s| (s.repair.customer_id, s.repair.customer_name.clone()))
        })
        .flatten();
    Ok(Json(PackageRepairSuggestions {
        suggestions: scored,
        proposed_customer_id: proposed.as_ref().map(|p| p.0),
        proposed_customer_name: proposed.map(|p| p.1),
    }))
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct PackageNewRepairInput {
    /// Defaults to the customer of the parcel.
    pub customer_id: Option<Uuid>,
    pub contact_id: Option<Uuid>,
    pub ticket_id: Option<Uuid>,
    pub product_id: Option<Uuid>,
    #[serde(default)]
    pub product_description: String,
    #[serde(default)]
    pub serial_number: String,
    /// What is wrong. Defaults to the subject of the ticket, else to "To be determined at intake".
    #[serde(default)]
    pub fault_description: String,
    /// Defaults to the customer reference of the parcel.
    #[serde(default)]
    pub customer_reference: String,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct PackageRepairLinkInput {
    /// Confirm a suggestion: link this announced (or already received) repair. Give this or `new_repair`.
    pub repair_id: Option<Uuid>,
    /// Nothing matched: create a new repair, already received, from this parcel.
    pub new_repair: Option<PackageNewRepairInput>,
    /// A key chosen by the app for `new_repair`: a retry returns the repair created the first time.
    pub client_id: Option<Uuid>,
    /// The status the app saw on `repair_id` (usually `announced`); 409 if someone else moved it meanwhile.
    pub expected_status: Option<String>,
    /// Link although the customer of the parcel is another than the customer of the repair.
    #[serde(default)]
    pub confirm_customer_mismatch: bool,
}

/// The parcel's customer and the repair's must agree, unless someone confirms they do not.
fn check_customer(pkg: Option<Uuid>, repair: Uuid, confirmed: bool) -> AppResult<()> {
    match pkg {
        Some(c) if c != repair && !confirmed => Err(AppError::ConflictCode(
            "customer_mismatch",
            "the customer of the parcel is not the customer of the repair; confirm to link anyway"
                .into(),
        )),
        _ => Ok(()),
    }
}

/// Confirms that a parcel holds a repair: either an existing repair (an announced one becomes
/// `received`) or a new one created from the parcel. The parcel becomes `linked`. One parcel can
/// hold several repairs, one repair can arrive in several parcels.
#[utoipa::path(post, path = "/packages/{id}/repairs", tag = "repairs", operation_id = "link_package_repair",
    params(("id" = Uuid, Path)), request_body = PackageRepairLinkInput,
    responses((status = 201, body = RepairDetail, description = "linked, or created"),
              (status = 200, body = RepairDetail, description = "already linked to this parcel"),
              (status = 403, body = ErrorBody), (status = 404, body = ErrorBody),
              (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn link_repair(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<PackageRepairLinkInput>,
) -> AppResult<(StatusCode, Json<RepairDetail>)> {
    user.require(Permission::RepairsIntake)?;
    if input.repair_id.is_some() == input.new_repair.is_some() {
        return Err(AppError::Validation(
            "give either repair_id or new_repair".into(),
        ));
    }
    let mut tx = state.db.begin().await?;
    let pkg = load_package(&mut tx, user.company_id, id, true).await?;
    if !workflow::can_take_repairs(&pkg.status, pkg.kind.as_deref()) {
        return Err(AppError::Conflict(
            "only an opened repair parcel can be linked to a repair".into(),
        ));
    }
    let repair_id = match (input.repair_id, &input.new_repair) {
        (Some(repair_id), _) => {
            // Lock the repair: two people confirming the same announcement take turns.
            let row: Option<(String, Uuid, Option<Uuid>, String)> = sqlx::query_as(
                "SELECT status, customer_id, ticket_id, number FROM repairs.repairs WHERE id = $1 AND company_id = $2 FOR UPDATE",
            )
            .bind(repair_id)
            .bind(user.company_id)
            .fetch_optional(&mut *tx)
            .await?;
            let (status, customer_id, ticket_id, repair_number) =
                row.ok_or(AppError::NotFound("repair"))?;
            if is_linked(&mut tx, id, repair_id).await? {
                let d = load_detail(&mut tx, user.company_id, repair_id).await?;
                return Ok((StatusCode::OK, Json(d)));
            }
            if let Some(expected) = input.expected_status.as_deref() {
                if expected != status {
                    return Err(AppError::ConflictCode(
                        "repair_status_changed",
                        format!("the repair is {status} now, not {expected}"),
                    ));
                }
            }
            if matches!(status.as_str(), "cancelled" | "shipped") {
                return Err(AppError::Conflict(format!(
                    "a repair that is {status} cannot receive a parcel"
                )));
            }
            check_customer(
                pkg.customer_id,
                customer_id,
                input.confirm_customer_mismatch,
            )?;
            if status == "announced" {
                sqlx::query(
                    "UPDATE repairs.repairs SET status = 'received', received_at = coalesce(received_at, now()), updated_at = now()
                     WHERE id = $1",
                )
                .bind(repair_id)
                .execute(&mut *tx)
                .await?;
                add_repair_event(
                    &mut tx,
                    repair_id,
                    Some(user.user_id),
                    &user.display_name,
                    Event {
                        kind: "status",
                        from_status: Some("announced"),
                        to_status: Some("received"),
                        from_department: None,
                        to_department: None,
                        note: &format!("Received in parcel {}", pkg.number),
                    },
                )
                .await?;
                crate::warranty::refresh(&mut tx, user.company_id, Some(&user), repair_id).await?;
                if let Some(t) = ticket_id {
                    tradocraft_helpdesk::tickets::add_linked_note(
                        &mut tx,
                        &user,
                        t,
                        &format!("Repair {repair_number} received in parcel {}.", pkg.number),
                    )
                    .await?;
                }
            }
            repair_id
        }
        (None, Some(n)) => {
            if let Some(key) = input.client_id {
                let earlier: Option<Uuid> = sqlx::query_scalar(
                    "SELECT id FROM repairs.repairs WHERE company_id = $1 AND source_client_id = $2",
                )
                .bind(user.company_id)
                .bind(key)
                .fetch_optional(&mut *tx)
                .await?;
                if let Some(rid) = earlier {
                    if !is_linked(&mut tx, id, rid).await? {
                        return Err(AppError::Conflict(
                            "this client_id belongs to a repair of another parcel".into(),
                        ));
                    }
                    let d = load_detail(&mut tx, user.company_id, rid).await?;
                    return Ok((StatusCode::OK, Json(d)));
                }
            }
            let new = NewRepairInput {
                customer_id: n.customer_id.or(pkg.customer_id),
                contact_id: n.contact_id,
                ticket_id: n.ticket_id,
                product_id: n.product_id,
                product_description: n.product_description.clone(),
                serial_number: n.serial_number.clone(),
                fault_description: if n.fault_description.trim().is_empty() && n.ticket_id.is_none()
                {
                    FAULT_TO_BE_DETERMINED.into()
                } else {
                    n.fault_description.clone()
                },
                customer_reference: if n.customer_reference.trim().is_empty() {
                    pkg.customer_reference.clone()
                } else {
                    n.customer_reference.clone()
                },
                warranty: "unknown".into(),
                priority: "normal".into(),
                announced: false,
            };
            let rid = insert_repair(&mut tx, &user, &new, "package", input.client_id).await?;
            let customer_id = load_repair(&mut tx, user.company_id, rid)
                .await?
                .customer_id;
            check_customer(
                pkg.customer_id,
                customer_id,
                input.confirm_customer_mismatch,
            )?;
            rid
        }
        (None, None) => unreachable!("checked above"),
    };
    link(&mut tx, &user, &pkg, repair_id).await?;
    let d = load_detail(&mut tx, user.company_id, repair_id).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(d)))
}

/// Whether the parcel is already linked to the repair.
async fn is_linked(conn: &mut PgConnection, package_id: Uuid, repair_id: Uuid) -> AppResult<bool> {
    Ok(sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM repairs.package_repairs WHERE package_id = $1 AND repair_id = $2)",
    )
    .bind(package_id)
    .bind(repair_id)
    .fetch_one(conn)
    .await?)
}

/// Records the link in both histories, sets the parcel's customer when it had none, and moves the
/// parcel to `linked` with its first repair. The caller holds the lock on the parcel.
async fn link(
    conn: &mut PgConnection,
    user: &CurrentUser,
    pkg: &Package,
    repair_id: Uuid,
) -> AppResult<()> {
    sqlx::query(
        "INSERT INTO repairs.package_repairs (package_id, repair_id, linked_by) VALUES ($1, $2, $3)
         ON CONFLICT DO NOTHING",
    )
    .bind(pkg.id)
    .bind(repair_id)
    .bind(user.user_id)
    .execute(&mut *conn)
    .await?;
    let number: String = sqlx::query_scalar("SELECT number FROM repairs.repairs WHERE id = $1")
        .bind(repair_id)
        .fetch_one(&mut *conn)
        .await?;
    add_event(
        conn,
        pkg.id,
        user,
        PkgEvent {
            kind: "linked",
            from_status: None,
            to_status: None,
            repair_id: Some(repair_id),
            note: &number,
        },
    )
    .await?;
    add_repair_event(
        conn,
        repair_id,
        Some(user.user_id),
        &user.display_name,
        Event {
            kind: "package_linked",
            from_status: None,
            to_status: None,
            from_department: None,
            to_department: None,
            note: &pkg.number,
        },
    )
    .await?;
    sqlx::query(
        "UPDATE repairs.packages SET updated_at = now(),
                customer_id = coalesce(customer_id, (SELECT customer_id FROM repairs.repairs WHERE id = $2))
         WHERE id = $1",
    )
    .bind(pkg.id)
    .bind(repair_id)
    .execute(&mut *conn)
    .await?;
    settle_status(conn, user, pkg).await?;
    audit::record(
        conn,
        user,
        "package",
        pkg.id,
        "linked",
        serde_json::json!({ "repair_id": repair_id }),
    )
    .await?;
    Ok(())
}

/// Moves the parcel to the status its number of links calls for (`opened` ⇄ `linked`).
async fn settle_status(
    conn: &mut PgConnection,
    user: &CurrentUser,
    pkg: &Package,
) -> AppResult<()> {
    let (status, links): (String, i64) = sqlx::query_as(
        "SELECT status, (SELECT count(*) FROM repairs.package_repairs WHERE package_id = $1) FROM repairs.packages WHERE id = $1",
    )
    .bind(pkg.id)
    .fetch_one(&mut *conn)
    .await?;
    if let Some(to) = workflow::after_link_change(&status, links) {
        sqlx::query("UPDATE repairs.packages SET status = $2, updated_at = now() WHERE id = $1")
            .bind(pkg.id)
            .bind(to)
            .execute(&mut *conn)
            .await?;
        add_event(
            conn,
            pkg.id,
            user,
            PkgEvent {
                kind: "status",
                from_status: Some(&status),
                to_status: Some(to),
                repair_id: None,
                note: "",
            },
        )
        .await?;
    }
    Ok(())
}

/// Removes the link between a parcel and a repair (a mistake). The repair keeps its status. The parcel
/// goes back to `opened` when its last repair is unlinked.
#[utoipa::path(delete, path = "/packages/{id}/repairs/{repair_id}", tag = "repairs", operation_id = "unlink_package_repair",
    params(("id" = Uuid, Path), ("repair_id" = Uuid, Path)),
    responses((status = 200, body = PackageDetail), (status = 403, body = ErrorBody), (status = 404, body = ErrorBody)))]
async fn unlink_repair(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((id, repair_id)): Path<(Uuid, Uuid)>,
) -> AppResult<Json<PackageDetail>> {
    user.require(Permission::RepairsIntake)?;
    let mut tx = state.db.begin().await?;
    let pkg = load_package(&mut tx, user.company_id, id, true).await?;
    let removed =
        sqlx::query("DELETE FROM repairs.package_repairs WHERE package_id = $1 AND repair_id = $2")
            .bind(id)
            .bind(repair_id)
            .execute(&mut *tx)
            .await?;
    if removed.rows_affected() == 0 {
        return Err(AppError::NotFound("link"));
    }
    let number: String = sqlx::query_scalar("SELECT number FROM repairs.repairs WHERE id = $1")
        .bind(repair_id)
        .fetch_one(&mut *tx)
        .await?;
    add_event(
        &mut tx,
        id,
        &user,
        PkgEvent {
            kind: "unlinked",
            from_status: None,
            to_status: None,
            repair_id: Some(repair_id),
            note: &number,
        },
    )
    .await?;
    add_repair_event(
        &mut tx,
        repair_id,
        Some(user.user_id),
        &user.display_name,
        Event {
            kind: "package_unlinked",
            from_status: None,
            to_status: None,
            from_department: None,
            to_department: None,
            note: &pkg.number,
        },
    )
    .await?;
    settle_status(&mut tx, &user, &pkg).await?;
    audit::record(
        &mut tx,
        &user,
        "package",
        id,
        "unlinked",
        serde_json::json!({ "repair_id": repair_id }),
    )
    .await?;
    let d = load_detail_of(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok(Json(d))
}

/// Opened repair parcels of the repair's customer that are not linked to any repair yet: the other
/// direction of matching, for an announced repair that has just arrived. Confirm with
/// `POST /packages/{id}/repairs`.
#[utoipa::path(get, path = "/repairs/{id}/package-suggestions", tag = "repairs", operation_id = "list_repair_package_suggestions",
    params(("id" = Uuid, Path)),
    responses((status = 200, body = Vec<Package>), (status = 403, body = ErrorBody), (status = 404, body = ErrorBody)))]
async fn package_suggestions(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<Vec<Package>>> {
    user.require(Permission::RepairsIntake)?;
    let mut conn = state.db.acquire().await?;
    let repair = load_repair(&mut conn, user.company_id, id).await?;
    Ok(Json(
        sqlx::query_as(&format!(
            "{SELECT} WHERE k.company_id = $1 AND k.status = 'opened' AND k.kind = 'repair' AND k.customer_id = $2
             ORDER BY k.received_at DESC LIMIT 50"
        ))
        .bind(user.company_id)
        .bind(repair.customer_id)
        .fetch_all(&mut *conn)
        .await?,
    ))
}

/// The parcels a repair arrived in.
#[utoipa::path(get, path = "/repairs/{id}/packages", tag = "repairs", operation_id = "list_repair_packages",
    params(("id" = Uuid, Path)),
    responses((status = 200, body = Vec<Package>), (status = 403, body = ErrorBody), (status = 404, body = ErrorBody)))]
async fn repair_packages(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<Vec<Package>>> {
    user.require(Permission::PackagesRead)?;
    let mut conn = state.db.acquire().await?;
    load_repair(&mut conn, user.company_id, id).await?;
    Ok(Json(
        sqlx::query_as(&format!(
            "{SELECT} WHERE k.company_id = $1 AND k.id IN (SELECT package_id FROM repairs.package_repairs WHERE repair_id = $2)
             ORDER BY k.received_at"
        ))
        .bind(user.company_id)
        .bind(id)
        .fetch_all(&mut *conn)
        .await?,
    ))
}

/// Routes of the incoming package endpoints.
pub fn router() -> OpenApiRouter<AppState> {
    // Uploads carry whole photos: raise the default body limit for them only.
    let uploads = OpenApiRouter::new()
        .routes(routes!(upload_photo))
        .layer(DefaultBodyLimit::max(MAX_FILE_BYTES + 64 * 1024));
    OpenApiRouter::new()
        .routes(routes!(list_packages, create_package))
        .routes(routes!(get_package, update_package))
        .routes(routes!(open_package))
        .routes(routes!(close_package))
        .routes(routes!(get_photo))
        .routes(routes!(repair_suggestions))
        .routes(routes!(link_repair))
        .routes(routes!(unlink_repair))
        .routes(routes!(package_suggestions))
        .routes(routes!(repair_packages))
        .merge(uploads)
}
