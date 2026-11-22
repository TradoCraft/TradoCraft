//! What a technician records besides tasks and time: the equipment worked on (installed base),
//! parts used, and the customer's signature. Also the equipment list of a customer.

use axum::body::Bytes;
use axum::extract::{DefaultBodyLimit, Path, Query, State};
use axum::http::StatusCode;
use axum::response::Response;
use axum::Json;
use chrono::{DateTime, NaiveDate, Utc};
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection};
use tradocraft_core::files;
use tradocraft_core::{audit, new_id, AppError, AppResult, AppState, CurrentUser, Permission};
use utoipa::{IntoParams, ToSchema};
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use super::{ensure_can_work, load_job, sees_all, ErrorBody, Job, JobDetail};

/// Largest accepted signature image.
const MAX_SIGNATURE_BYTES: usize = 2 * 1024 * 1024;

/// SQL for the warranty status of a unit aliased `s`.
pub const WARRANTY_STATUS_SQL: &str = "CASE WHEN s.warranty_until IS NULL THEN 'unknown'
        WHEN s.warranty_until >= current_date THEN 'in_warranty' ELSE 'expired' END";

// ---------------------------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct JobEquipment {
    pub serial_unit_id: Uuid,
    pub product_code: String,
    pub product_name: String,
    pub serial_number: String,
    pub status: String,
    pub warranty_until: Option<NaiveDate>,
    pub warranty_note: String,
    /// in_warranty | expired | unknown
    pub warranty_status: String,
}

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct JobPart {
    /// Chosen by the client.
    pub id: Uuid,
    pub product_id: Option<Uuid>,
    pub product_code: Option<String>,
    pub description: String,
    #[schema(value_type = String, example = "2.000")]
    pub quantity: Decimal,
    pub unit: String,
    pub serial_unit_id: Option<Uuid>,
    pub serial_number: Option<String>,
    pub billable: bool,
    pub added_by_name: Option<String>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct JobSignature {
    pub signer_name: String,
    /// The customer declined to sign.
    pub declined: bool,
    pub decline_reason: String,
    /// A signature image is stored: fetch it from `/field/jobs/{id}/signature`.
    pub has_image: bool,
    pub captured_by_name: Option<String>,
    pub signed_at: DateTime<Utc>,
}

// ---------------------------------------------------------------------------------------------
// Loaders (used by the job detail)
// ---------------------------------------------------------------------------------------------

pub(crate) async fn equipment_of(
    conn: &mut PgConnection,
    job_id: Uuid,
) -> AppResult<Vec<JobEquipment>> {
    Ok(sqlx::query_as(sqlx::AssertSqlSafe(format!(
        "SELECT s.id AS serial_unit_id, p.code AS product_code, p.name AS product_name, s.serial_number, s.status,
                s.warranty_until, s.warranty_note, {WARRANTY_STATUS_SQL} AS warranty_status
         FROM field.job_equipment e JOIN engineering.serial_units s ON s.id = e.serial_unit_id
         JOIN products.products p ON p.id = s.product_id
         WHERE e.job_id = $1 ORDER BY p.code, s.serial_number"
    )))
    .bind(job_id)
    .fetch_all(conn)
    .await?)
}

pub(crate) async fn parts_of(conn: &mut PgConnection, job_id: Uuid) -> AppResult<Vec<JobPart>> {
    Ok(sqlx::query_as(
        "SELECT jp.id, jp.product_id, p.code AS product_code, jp.description, jp.quantity, jp.unit,
                jp.serial_unit_id, s.serial_number, jp.billable, u.display_name AS added_by_name, jp.created_at
         FROM field.job_parts jp LEFT JOIN products.products p ON p.id = jp.product_id
         LEFT JOIN engineering.serial_units s ON s.id = jp.serial_unit_id
         LEFT JOIN core.users u ON u.id = jp.added_by
         WHERE jp.job_id = $1 ORDER BY jp.created_at, jp.id",
    )
    .bind(job_id)
    .fetch_all(conn)
    .await?)
}

pub(crate) async fn signature_of(
    conn: &mut PgConnection,
    job_id: Uuid,
) -> AppResult<Option<JobSignature>> {
    Ok(sqlx::query_as(
        "SELECT g.signer_name, g.declined, g.decline_reason, g.file_id IS NOT NULL AS has_image,
                u.display_name AS captured_by_name, g.signed_at
         FROM field.job_signatures g LEFT JOIN core.users u ON u.id = g.captured_by WHERE g.job_id = $1",
    )
    .bind(job_id)
    .fetch_optional(conn)
    .await?)
}

/// Equipment and parts may be changed on an open job; on a completed one only by planners.
fn ensure_editable(job: &Job, user: &CurrentUser) -> AppResult<()> {
    match job.status.as_str() {
        "cancelled" => Err(AppError::Conflict("the job is cancelled".into())),
        "completed" if !user.can(Permission::FieldPlan) => {
            Err(AppError::Conflict("the job is completed".into()))
        }
        _ => Ok(()),
    }
}

// ---------------------------------------------------------------------------------------------
// Equipment
// ---------------------------------------------------------------------------------------------

#[derive(Debug, Deserialize, ToSchema)]
pub struct EquipmentInput {
    pub serial_unit_id: Uuid,
}

/// Checks that the unit exists in the company and belongs to the customer.
pub(crate) async fn check_unit_of_customer(
    conn: &mut PgConnection,
    company_id: Uuid,
    unit_id: Uuid,
    customer_id: Uuid,
) -> AppResult<()> {
    let owner: Option<Option<Uuid>> = sqlx::query_scalar(
        "SELECT customer_id FROM engineering.serial_units WHERE id = $1 AND company_id = $2",
    )
    .bind(unit_id)
    .bind(company_id)
    .fetch_optional(conn)
    .await?;
    match owner {
        None => Err(AppError::NotFound("serial unit")),
        Some(Some(c)) if c == customer_id => Ok(()),
        Some(_) => Err(AppError::Conflict(
            "the unit does not belong to the customer of this job".into(),
        )),
    }
}

/// Links a unit of the job's customer to the job. Linking it twice changes nothing.
#[utoipa::path(post, path = "/field/jobs/{id}/equipment", tag = "field", operation_id = "add_job_equipment",
    params(("id" = Uuid, Path)), request_body = EquipmentInput,
    responses((status = 201, body = JobDetail), (status = 404, body = ErrorBody), (status = 409, body = ErrorBody)))]
async fn add_equipment(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<EquipmentInput>,
) -> AppResult<(StatusCode, Json<JobDetail>)> {
    let mut tx = state.db.begin().await?;
    ensure_can_work(&mut tx, &user, id).await?;
    let job = load_job(&mut tx, &user, id).await?;
    ensure_editable(&job, &user)?;
    check_unit_of_customer(
        &mut tx,
        user.company_id,
        input.serial_unit_id,
        job.customer_id,
    )
    .await?;
    let added = sqlx::query(
        "INSERT INTO field.job_equipment (job_id, serial_unit_id, added_by) VALUES ($1, $2, $3)
         ON CONFLICT DO NOTHING",
    )
    .bind(id)
    .bind(input.serial_unit_id)
    .bind(user.user_id)
    .execute(&mut *tx)
    .await?;
    if added.rows_affected() > 0 {
        audit::record(
            &mut tx,
            &user,
            "job",
            id,
            "equipment_added",
            serde_json::json!({ "serial_unit_id": input.serial_unit_id }),
        )
        .await?;
    }
    let d = super::load_detail(&mut tx, &user, id).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(d)))
}

#[utoipa::path(delete, path = "/field/jobs/{id}/equipment/{serial_unit_id}", tag = "field",
    operation_id = "remove_job_equipment", params(("id" = Uuid, Path), ("serial_unit_id" = Uuid, Path)),
    responses((status = 200, body = JobDetail), (status = 409, body = ErrorBody)))]
async fn remove_equipment(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((id, unit_id)): Path<(Uuid, Uuid)>,
) -> AppResult<Json<JobDetail>> {
    let mut tx = state.db.begin().await?;
    ensure_can_work(&mut tx, &user, id).await?;
    ensure_editable(&load_job(&mut tx, &user, id).await?, &user)?;
    let gone =
        sqlx::query("DELETE FROM field.job_equipment WHERE job_id = $1 AND serial_unit_id = $2")
            .bind(id)
            .bind(unit_id)
            .execute(&mut *tx)
            .await?;
    if gone.rows_affected() > 0 {
        audit::record(
            &mut tx,
            &user,
            "job",
            id,
            "equipment_removed",
            serde_json::json!({ "serial_unit_id": unit_id }),
        )
        .await?;
    }
    let d = super::load_detail(&mut tx, &user, id).await?;
    tx.commit().await?;
    Ok(Json(d))
}

// ---------------------------------------------------------------------------------------------
// Parts used
// ---------------------------------------------------------------------------------------------

#[derive(Debug, Deserialize, ToSchema)]
pub struct PartInput {
    /// Chosen by the client: sending the same id again changes nothing (offline retries).
    pub id: Option<Uuid>,
    /// A product from the catalogue; leave empty for free text.
    pub product_id: Option<Uuid>,
    /// Required for free text; defaults to the product's name.
    #[serde(default)]
    pub description: String,
    #[schema(value_type = String, example = "2")]
    pub quantity: Decimal,
    /// Defaults to the product's unit, or `pcs`.
    pub unit: Option<String>,
    /// The unit (serial number) the part went into.
    pub serial_unit_id: Option<Uuid>,
    /// Is the part charged to the customer? Default yes.
    pub billable: Option<bool>,
}

/// Records a part used on a job. No stock is deducted.
#[utoipa::path(post, path = "/field/jobs/{id}/parts", tag = "field", operation_id = "add_job_part",
    params(("id" = Uuid, Path)), request_body = PartInput,
    responses((status = 201, body = JobDetail), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn add_part(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<PartInput>,
) -> AppResult<(StatusCode, Json<JobDetail>)> {
    if input.quantity <= Decimal::ZERO || input.quantity > Decimal::from(1_000_000) {
        return Err(AppError::Validation(
            "the quantity must be more than zero".into(),
        ));
    }
    let mut tx = state.db.begin().await?;
    ensure_can_work(&mut tx, &user, id).await?;
    ensure_editable(&load_job(&mut tx, &user, id).await?, &user)?;
    let product: Option<(String, String)> = match input.product_id {
        Some(p) => Some(
            sqlx::query_as("SELECT name, unit FROM products.products WHERE id = $1")
                .bind(p)
                .fetch_optional(&mut *tx)
                .await?
                .ok_or_else(|| AppError::Validation("unknown product".into()))?,
        ),
        None => None,
    };
    let description = if input.description.trim().is_empty() {
        product.as_ref().map(|p| p.0.clone()).unwrap_or_default()
    } else {
        input.description.trim().to_string()
    };
    if description.is_empty() {
        return Err(AppError::Validation("describe the part".into()));
    }
    let unit = input
        .unit
        .as_deref()
        .map(str::trim)
        .filter(|u| !u.is_empty())
        .map(str::to_string)
        .or_else(|| product.map(|p| p.1))
        .unwrap_or_else(|| "pcs".into());
    if let Some(u) = input.serial_unit_id {
        let ok: bool = sqlx::query_scalar(
            "SELECT EXISTS (SELECT 1 FROM engineering.serial_units WHERE id = $1 AND company_id = $2)",
        )
        .bind(u)
        .bind(user.company_id)
        .fetch_one(&mut *tx)
        .await?;
        if !ok {
            return Err(AppError::Validation("unknown serial unit".into()));
        }
    }
    let part_id = input.id.unwrap_or_else(new_id);
    let inserted = sqlx::query(
        "INSERT INTO field.job_parts (id, job_id, product_id, description, quantity, unit, serial_unit_id, billable, added_by)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9) ON CONFLICT (id) DO NOTHING",
    )
    .bind(part_id)
    .bind(id)
    .bind(input.product_id)
    .bind(&description)
    .bind(input.quantity)
    .bind(&unit)
    .bind(input.serial_unit_id)
    .bind(input.billable.unwrap_or(true))
    .bind(user.user_id)
    .execute(&mut *tx)
    .await?;
    if inserted.rows_affected() == 0 {
        let same: bool = sqlx::query_scalar(
            "SELECT EXISTS (SELECT 1 FROM field.job_parts WHERE id = $1 AND job_id = $2
                 AND product_id IS NOT DISTINCT FROM $3 AND description = $4 AND quantity = $5 AND unit = $6
                 AND serial_unit_id IS NOT DISTINCT FROM $7 AND billable = $8)",
        )
        .bind(part_id)
        .bind(id)
        .bind(input.product_id)
        .bind(&description)
        .bind(input.quantity)
        .bind(&unit)
        .bind(input.serial_unit_id)
        .bind(input.billable.unwrap_or(true))
        .fetch_one(&mut *tx)
        .await?;
        if !same {
            return Err(AppError::Conflict(
                "this id belongs to another record".into(),
            ));
        }
    } else {
        audit::record(
            &mut tx,
            &user,
            "job",
            id,
            "part_added",
            serde_json::json!({ "part_id": part_id, "description": description, "quantity": input.quantity.to_string() }),
        )
        .await?;
    }
    let d = super::load_detail(&mut tx, &user, id).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(d)))
}

/// Removes a part. Removing one that is already gone changes nothing.
#[utoipa::path(delete, path = "/field/jobs/{id}/parts/{part_id}", tag = "field", operation_id = "remove_job_part",
    params(("id" = Uuid, Path), ("part_id" = Uuid, Path)),
    responses((status = 200, body = JobDetail), (status = 409, body = ErrorBody)))]
async fn remove_part(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((id, part_id)): Path<(Uuid, Uuid)>,
) -> AppResult<Json<JobDetail>> {
    let mut tx = state.db.begin().await?;
    ensure_can_work(&mut tx, &user, id).await?;
    ensure_editable(&load_job(&mut tx, &user, id).await?, &user)?;
    let gone = sqlx::query("DELETE FROM field.job_parts WHERE id = $1 AND job_id = $2")
        .bind(part_id)
        .bind(id)
        .execute(&mut *tx)
        .await?;
    if gone.rows_affected() > 0 {
        audit::record(
            &mut tx,
            &user,
            "job",
            id,
            "part_removed",
            serde_json::json!({ "part_id": part_id }),
        )
        .await?;
    }
    let d = super::load_detail(&mut tx, &user, id).await?;
    tx.commit().await?;
    Ok(Json(d))
}

// ---------------------------------------------------------------------------------------------
// Customer signature
// ---------------------------------------------------------------------------------------------

#[derive(Debug, Deserialize, IntoParams)]
pub struct SignatureParams {
    /// Who signed, as they wrote it.
    pub signer_name: String,
    /// A client-chosen id: uploading the same id again changes nothing.
    pub client_id: Option<Uuid>,
}

/// The job must be underway or done, and the report must not have been sent yet.
async fn ensure_signable(conn: &mut PgConnection, user: &CurrentUser, id: Uuid) -> AppResult<()> {
    ensure_can_work(conn, user, id).await?;
    let job = load_job(conn, user, id).await?;
    if !matches!(job.status.as_str(), "in_progress" | "completed") {
        return Err(AppError::Conflict(
            "the job must be started before the customer signs".into(),
        ));
    }
    if job.report_sent_at.is_some() {
        return Err(AppError::Conflict(
            "the service report has been sent; the signature can no longer be replaced".into(),
        ));
    }
    Ok(())
}

/// Stores the customer's signature: the request body is a PNG image. A job has one signature;
/// a new one replaces the old one until the service report is sent.
#[utoipa::path(post, path = "/field/jobs/{id}/signature", tag = "field", operation_id = "sign_job",
    params(("id" = Uuid, Path), SignatureParams), request_body(content = String, content_type = "image/png"),
    responses((status = 201, body = JobDetail), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn sign_job(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Query(p): Query<SignatureParams>,
    body: Bytes,
) -> AppResult<(StatusCode, Json<JobDetail>)> {
    let name = p.signer_name.trim();
    if name.is_empty() {
        return Err(AppError::Validation(
            "the name of the signer is required".into(),
        ));
    }
    if body.len() > MAX_SIGNATURE_BYTES {
        return Err(AppError::Validation(
            "the signature image is too large".into(),
        ));
    }
    if files::sniff_image(&body) != Some("image/png") {
        return Err(AppError::Validation(
            "the signature must be a PNG image".into(),
        ));
    }
    let mut tx = state.db.begin().await?;
    ensure_signable(&mut tx, &user, id).await?;
    let old: Option<Option<Uuid>> =
        sqlx::query_scalar("SELECT file_id FROM field.job_signatures WHERE job_id = $1")
            .bind(id)
            .fetch_optional(&mut *tx)
            .await?;
    let file = files::store_document(
        &mut tx,
        &state.blobs,
        user.company_id,
        p.client_id,
        "signature.png",
        &body,
        Some(user.user_id),
        &user.display_name,
    )
    .await?;
    if file.size_bytes as usize != body.len() {
        return Err(AppError::Conflict(
            "this id belongs to another signature".into(),
        ));
    }
    let linked_elsewhere: bool = sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM field.job_signatures WHERE file_id = $1 AND job_id <> $2)",
    )
    .bind(file.id)
    .bind(id)
    .fetch_one(&mut *tx)
    .await?;
    if linked_elsewhere {
        return Err(AppError::Conflict(
            "this id belongs to another record".into(),
        ));
    }
    sqlx::query(
        "INSERT INTO field.job_signatures (job_id, file_id, signer_name, declined, decline_reason, captured_by, signed_at)
         VALUES ($1, $2, $3, false, '', $4, now())
         ON CONFLICT (job_id) DO UPDATE SET file_id = EXCLUDED.file_id, signer_name = EXCLUDED.signer_name,
             declined = false, decline_reason = '', captured_by = EXCLUDED.captured_by,
             signed_at = CASE WHEN field.job_signatures.file_id = EXCLUDED.file_id THEN field.job_signatures.signed_at ELSE now() END",
    )
    .bind(id)
    .bind(file.id)
    .bind(name)
    .bind(user.user_id)
    .execute(&mut *tx)
    .await?;
    if let Some(Some(old_file)) = old {
        if old_file != file.id {
            sqlx::query("DELETE FROM core.files WHERE id = $1")
                .bind(old_file)
                .execute(&mut *tx)
                .await?;
        }
    }
    // A replay of the same upload (same file id) changes nothing, so it is not audited twice.
    if old != Some(Some(file.id)) {
        audit::record(
            &mut tx,
            &user,
            "job",
            id,
            "signed",
            serde_json::json!({ "signer": name }),
        )
        .await?;
    }
    let d = super::load_detail(&mut tx, &user, id).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(d)))
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct DeclinedInput {
    /// Who was asked, if known.
    #[serde(default)]
    pub signer_name: String,
    /// Why the customer did not sign.
    pub reason: String,
}

/// Records that the customer declined to sign. Replaces an earlier signature.
#[utoipa::path(post, path = "/field/jobs/{id}/signature/declined", tag = "field", operation_id = "decline_job_signature",
    params(("id" = Uuid, Path)), request_body = DeclinedInput,
    responses((status = 201, body = JobDetail), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn decline_signature(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<DeclinedInput>,
) -> AppResult<(StatusCode, Json<JobDetail>)> {
    if input.reason.trim().is_empty() {
        return Err(AppError::Validation(
            "say why the customer did not sign".into(),
        ));
    }
    let mut tx = state.db.begin().await?;
    ensure_signable(&mut tx, &user, id).await?;
    // Declining again with the same name and reason (a retry) changes nothing.
    let same: bool = sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM field.job_signatures WHERE job_id = $1 AND declined
             AND signer_name = $2 AND decline_reason = $3)",
    )
    .bind(id)
    .bind(input.signer_name.trim())
    .bind(input.reason.trim())
    .fetch_one(&mut *tx)
    .await?;
    if same {
        let d = super::load_detail(&mut tx, &user, id).await?;
        return Ok((StatusCode::CREATED, Json(d)));
    }
    let old: Option<Option<Uuid>> =
        sqlx::query_scalar("SELECT file_id FROM field.job_signatures WHERE job_id = $1")
            .bind(id)
            .fetch_optional(&mut *tx)
            .await?;
    sqlx::query(
        "INSERT INTO field.job_signatures (job_id, file_id, signer_name, declined, decline_reason, captured_by, signed_at)
         VALUES ($1, NULL, $2, true, $3, $4, now())
         ON CONFLICT (job_id) DO UPDATE SET file_id = NULL, signer_name = EXCLUDED.signer_name, declined = true,
             decline_reason = EXCLUDED.decline_reason, captured_by = EXCLUDED.captured_by, signed_at = now()",
    )
    .bind(id)
    .bind(input.signer_name.trim())
    .bind(input.reason.trim())
    .bind(user.user_id)
    .execute(&mut *tx)
    .await?;
    if let Some(Some(old_file)) = old {
        sqlx::query("DELETE FROM core.files WHERE id = $1")
            .bind(old_file)
            .execute(&mut *tx)
            .await?;
    }
    audit::record(
        &mut tx,
        &user,
        "job",
        id,
        "signature_declined",
        serde_json::json!({ "reason": input.reason.trim() }),
    )
    .await?;
    let d = super::load_detail(&mut tx, &user, id).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(d)))
}

/// The signature image (PNG).
#[utoipa::path(get, path = "/field/jobs/{id}/signature", tag = "field", operation_id = "get_job_signature",
    params(("id" = Uuid, Path)),
    responses((status = 200, content_type = "image/png", body = String), (status = 404, body = ErrorBody)))]
async fn get_signature(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Response> {
    user.require(Permission::FieldRead)?;
    let mut conn = state.db.acquire().await?;
    load_job(&mut conn, &user, id).await?;
    let file: Option<Uuid> =
        sqlx::query_scalar("SELECT file_id FROM field.job_signatures WHERE job_id = $1")
            .bind(id)
            .fetch_optional(&mut *conn)
            .await?
            .flatten();
    let file = file.ok_or(AppError::NotFound("signature"))?;
    let (content_type, data) = files::load(&mut conn, &state.blobs, user.company_id, file).await?;
    Ok(files::image_response(&content_type, data))
}

// ---------------------------------------------------------------------------------------------
// Equipment of a customer (installed base) with its job history
// ---------------------------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct EquipmentJob {
    pub id: Uuid,
    pub number: String,
    pub title: String,
    pub kind: String,
    pub status: String,
    pub scheduled_start: Option<DateTime<Utc>>,
    pub completed_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct CustomerEquipment {
    #[serde(flatten)]
    pub unit: JobEquipment,
    /// The jobs this unit was worked on in, newest first (only those the user may see).
    pub jobs: Vec<EquipmentJob>,
}

/// The installed units of a customer (delivered or installed, not scrapped) with their job history.
#[utoipa::path(get, path = "/field/customers/{id}/equipment", tag = "field", operation_id = "list_customer_equipment",
    params(("id" = Uuid, Path)),
    responses((status = 200, body = Vec<CustomerEquipment>), (status = 404, body = ErrorBody)))]
async fn customer_equipment(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<Vec<CustomerEquipment>>> {
    user.require(Permission::FieldRead)?;
    let mut conn = state.db.acquire().await?;
    tradocraft_crm::get_customer(&mut *conn, user.company_id, id).await?;
    let units: Vec<JobEquipment> = sqlx::query_as(sqlx::AssertSqlSafe(format!(
        "SELECT s.id AS serial_unit_id, p.code AS product_code, p.name AS product_name, s.serial_number, s.status,
                s.warranty_until, s.warranty_note, {WARRANTY_STATUS_SQL} AS warranty_status
         FROM engineering.serial_units s JOIN products.products p ON p.id = s.product_id
         WHERE s.company_id = $1 AND s.customer_id = $2 AND s.status IN ('delivered', 'installed')
         ORDER BY p.code, s.serial_number"
    )))
    .bind(user.company_id)
    .bind(id)
    .fetch_all(&mut *conn)
    .await?;
    let ids: Vec<Uuid> = units.iter().map(|u| u.serial_unit_id).collect();
    #[derive(FromRow)]
    struct Row {
        serial_unit_id: Uuid,
        #[sqlx(flatten)]
        job: EquipmentJob,
    }
    let rows: Vec<Row> = sqlx::query_as(
        "SELECT e.serial_unit_id, j.id, j.number, j.title, j.kind, j.status, j.scheduled_start, j.completed_at
         FROM field.job_equipment e JOIN field.jobs j ON j.id = e.job_id
         WHERE e.serial_unit_id = ANY($1) AND j.company_id = $2
           AND ($3 OR EXISTS (SELECT 1 FROM field.job_technicians x WHERE x.job_id = j.id AND x.user_id = $4))
         ORDER BY coalesce(j.completed_at, j.scheduled_start, j.created_at) DESC, j.number DESC",
    )
    .bind(&ids)
    .bind(user.company_id)
    .bind(sees_all(&user))
    .bind(user.user_id)
    .fetch_all(&mut *conn)
    .await?;
    Ok(Json(
        units
            .into_iter()
            .map(|unit| CustomerEquipment {
                jobs: rows
                    .iter()
                    .filter(|r| r.serial_unit_id == unit.serial_unit_id)
                    .map(|r| r.job.clone())
                    .collect(),
                unit,
            })
            .collect(),
    ))
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(add_equipment))
        .routes(routes!(remove_equipment))
        .routes(routes!(add_part))
        .routes(routes!(remove_part))
        .routes(routes!(decline_signature))
        .routes(routes!(customer_equipment))
        .merge(
            OpenApiRouter::new()
                .routes(routes!(sign_job, get_signature))
                .layer(DefaultBodyLimit::max(MAX_SIGNATURE_BYTES + 64 * 1024)),
        )
}
