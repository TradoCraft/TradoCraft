//! The customer's view of repairs, for the portal: announce a repair, follow it, add photos.
//! A customer sees only repairs of their own customer record (their own, unless their portal
//! scope is `customer`), a simplified status, and their photos — never notes or departments.

use chrono::{DateTime, Utc};
use serde::Serialize;
use sqlx::{FromRow, PgConnection};
use tradocraft_core::files;
use tradocraft_core::{audit, new_id, AppError, AppResult};
use tradocraft_helpdesk::portal::Viewer;
use utoipa::ToSchema;
use uuid::Uuid;

use crate::workflow::portal_status;
use crate::{add_event, attach_photo, next_number, Event};

#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct PortalRepair {
    pub id: Uuid,
    pub number: String,
    /// announced | in_repair | waiting_customer | ready | shipped | cancelled
    pub status: String,
    pub product_description: String,
    pub serial_number: String,
    pub fault_description: String,
    pub customer_reference: String,
    /// Who registered it (colleagues' repairs are visible with the `customer` scope).
    pub contact_name: String,
    pub photo_count: i64,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct PortalPhoto {
    pub id: Uuid,
    pub caption: String,
    pub filename: String,
    pub uploader_name: String,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct PortalRepairDetail {
    pub repair: PortalRepair,
    pub photos: Vec<PortalPhoto>,
}

#[derive(FromRow)]
struct Row {
    id: Uuid,
    number: String,
    status: String,
    product_description: String,
    serial_number: String,
    fault_description: String,
    customer_reference: String,
    contact_name: String,
    photo_count: i64,
    created_at: DateTime<Utc>,
    updated_at: DateTime<Utc>,
}

impl From<Row> for PortalRepair {
    fn from(r: Row) -> Self {
        PortalRepair {
            status: portal_status(&r.status).to_string(),
            id: r.id,
            number: r.number,
            product_description: r.product_description,
            serial_number: r.serial_number,
            fault_description: r.fault_description,
            customer_reference: r.customer_reference,
            contact_name: r.contact_name,
            photo_count: r.photo_count,
            created_at: r.created_at,
            updated_at: r.updated_at,
        }
    }
}

const SELECT: &str = "SELECT r.id, r.number, r.status, r.product_description, r.serial_number, r.fault_description,
        r.customer_reference, coalesce(nullif(btrim(ct.first_name || ' ' || ct.last_name), ''), '') AS contact_name,
        (SELECT count(*) FROM repairs.photos ph WHERE ph.repair_id = r.id) AS photo_count, r.created_at, r.updated_at
     FROM repairs.repairs r LEFT JOIN crm.contacts ct ON ct.id = r.contact_id";
const VISIBLE: &str =
    "r.company_id = $1 AND r.customer_id = $2 AND ($3 = 'customer' OR r.contact_id = $4)";

pub async fn list(conn: &mut PgConnection, v: &Viewer) -> AppResult<Vec<PortalRepair>> {
    let rows: Vec<Row> = sqlx::query_as(&format!(
        "{SELECT} WHERE {VISIBLE} ORDER BY (r.status IN ('shipped', 'cancelled')), r.updated_at DESC LIMIT 200"
    ))
    .bind(v.company_id)
    .bind(v.customer_id)
    .bind(&v.scope)
    .bind(v.contact_id)
    .fetch_all(conn)
    .await?;
    Ok(rows.into_iter().map(Into::into).collect())
}

/// Visible to this viewer, or not found. Returns the raw status too (for the rules on photos).
async fn visible(
    conn: &mut PgConnection,
    v: &Viewer,
    id: Uuid,
) -> AppResult<(PortalRepair, String)> {
    let row: Row = sqlx::query_as(&format!("{SELECT} WHERE r.id = $5 AND {VISIBLE}"))
        .bind(v.company_id)
        .bind(v.customer_id)
        .bind(&v.scope)
        .bind(v.contact_id)
        .bind(id)
        .fetch_optional(&mut *conn)
        .await?
        .ok_or(AppError::NotFound("repair"))?;
    let raw = row.status.clone();
    Ok((row.into(), raw))
}

pub async fn get(conn: &mut PgConnection, v: &Viewer, id: Uuid) -> AppResult<PortalRepairDetail> {
    let (repair, _) = visible(conn, v, id).await?;
    let photos = sqlx::query_as(
        "SELECT f.id, p.caption, f.filename, f.uploader_name, p.created_at
         FROM repairs.photos p JOIN core.files f ON f.id = p.file_id WHERE p.repair_id = $1 ORDER BY p.created_at, p.id",
    )
    .bind(id)
    .fetch_all(conn)
    .await?;
    Ok(PortalRepairDetail { repair, photos })
}

pub struct Announcement<'a> {
    pub product_description: &'a str,
    pub serial_number: &'a str,
    pub fault_description: &'a str,
    pub customer_reference: &'a str,
}

/// A customer announces a repair: it starts as `announced`, until staff receive the parcel.
pub async fn announce(
    conn: &mut PgConnection,
    v: &Viewer,
    a: Announcement<'_>,
) -> AppResult<PortalRepairDetail> {
    if a.fault_description.trim().is_empty() {
        return Err(AppError::Validation("describe what is wrong".into()));
    }
    if a.product_description.trim().is_empty() && a.serial_number.trim().is_empty() {
        return Err(AppError::Validation("say which product it is".into()));
    }
    if a.fault_description.chars().count() > 5000
        || a.product_description.chars().count() > 300
        || a.serial_number.chars().count() > 100
        || a.customer_reference.chars().count() > 100
    {
        return Err(AppError::Validation("a text is too long".into()));
    }
    let contact = tradocraft_crm::contacts::get_contact(conn, v.contact_id).await?;
    let number = next_number(conn, v.company_id).await?;
    let id = new_id();
    sqlx::query(
        "INSERT INTO repairs.repairs (id, company_id, number, status, customer_id, contact_id, product_description,
                                      serial_number, fault_description, customer_reference, source)
         VALUES ($1, $2, $3, 'announced', $4, $5, $6, $7, $8, $9, 'portal')",
    )
    .bind(id)
    .bind(v.company_id)
    .bind(&number)
    .bind(v.customer_id)
    .bind(v.contact_id)
    .bind(a.product_description.trim())
    .bind(a.serial_number.trim())
    .bind(a.fault_description.trim())
    .bind(a.customer_reference.trim())
    .execute(&mut *conn)
    .await?;
    add_event(
        conn,
        id,
        None,
        &contact.full_name,
        Event {
            kind: "created",
            from_status: None,
            to_status: Some("announced"),
            from_department: None,
            to_department: None,
            note: "",
        },
    )
    .await?;
    audit::record_system(
        conn,
        v.company_id,
        "repair",
        id,
        "announced_in_portal",
        serde_json::json!({ "number": number, "contact_id": contact.id }),
    )
    .await?;
    get(conn, v, id).await
}

/// A customer adds a photo to a repair that is not finished. The bytes are validated as an image.
#[allow(clippy::too_many_arguments)]
pub async fn add_photo(
    conn: &mut PgConnection,
    blobs: &tradocraft_core::BlobStore,
    v: &Viewer,
    id: Uuid,
    filename: &str,
    caption: &str,
    client_id: Option<Uuid>,
    bytes: &[u8],
) -> AppResult<PortalRepairDetail> {
    let (_, raw_status) = visible(conn, v, id).await?;
    if matches!(raw_status.as_str(), "shipped" | "cancelled") {
        return Err(AppError::Conflict(
            "this repair is finished: no photos can be added".into(),
        ));
    }
    let contact = tradocraft_crm::contacts::get_contact(conn, v.contact_id).await?;
    let file = files::store_image(
        conn,
        blobs,
        v.company_id,
        client_id,
        filename,
        bytes,
        None,
        &contact.full_name,
    )
    .await?;
    attach_photo(conn, v.company_id, id, &file, caption).await?;
    add_event(
        conn,
        id,
        None,
        &contact.full_name,
        Event {
            kind: "photo",
            from_status: None,
            to_status: None,
            from_department: None,
            to_department: None,
            note: caption.trim(),
        },
    )
    .await?;
    get(conn, v, id).await
}

/// The bytes of a photo of a repair the viewer may see.
pub async fn photo_data(
    conn: &mut PgConnection,
    blobs: &tradocraft_core::BlobStore,
    v: &Viewer,
    id: Uuid,
    photo_id: Uuid,
) -> AppResult<(String, Vec<u8>)> {
    visible(conn, v, id).await?;
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
    files::load(conn, blobs, v.company_id, photo_id).await
}
