//! Photo and document storage. Files are checked by their signature (not their name or declared type), size
//! limited, and kept on disk in [`BlobStore`] next to a PostgreSQL metadata row. Modules link files to
//! their own records and decide who may see them; this module only stores and loads.

use sqlx::{FromRow, PgConnection};
use uuid::Uuid;

use crate::{new_id, AppError, AppResult, BlobStore};

/// Largest accepted upload (a phone photo is typically 2–6 MB).
pub const MAX_FILE_BYTES: usize = 12 * 1024 * 1024;

#[derive(Debug, Clone, serde::Serialize, FromRow, utoipa::ToSchema)]
pub struct FileInfo {
    pub id: Uuid,
    pub filename: String,
    /// image/jpeg | image/png | image/webp | application/pdf
    pub content_type: String,
    pub size_bytes: i32,
    pub uploader_name: String,
    pub created_at: chrono::DateTime<chrono::Utc>,
}

/// The content type of an image, from its first bytes. Only JPEG, PNG and WebP are accepted.
pub fn sniff_image(bytes: &[u8]) -> Option<&'static str> {
    if bytes.starts_with(&[0xFF, 0xD8, 0xFF]) {
        Some("image/jpeg")
    } else if bytes.starts_with(&[0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A]) {
        Some("image/png")
    } else if bytes.len() > 12 && &bytes[0..4] == b"RIFF" && &bytes[8..12] == b"WEBP" {
        Some("image/webp")
    } else {
        None
    }
}

/// The content type of a ticket attachment: an image (see [`sniff_image`]) or a PDF document.
pub fn sniff_document(bytes: &[u8]) -> Option<&'static str> {
    sniff_image(bytes).or_else(|| bytes.starts_with(b"%PDF-").then_some("application/pdf"))
}

/// A file name that is safe to show and to put in a header: no path, no control characters.
pub fn clean_filename(name: &str, content_type: &str) -> String {
    let base = name.rsplit(['/', '\\']).next().unwrap_or("");
    let cleaned: String = base
        .chars()
        .filter(|c| !c.is_control() && !matches!(c, '"' | '<' | '>' | ':' | '|' | '?' | '*'))
        .take(120)
        .collect();
    let cleaned = cleaned.trim().to_string();
    if cleaned.is_empty() {
        let ext = match content_type {
            "image/png" => "png",
            "image/webp" => "webp",
            "application/pdf" => return "document.pdf".to_string(),
            _ => "jpg",
        };
        format!("photo.{ext}")
    } else {
        cleaned
    }
}

/// Stores an image. `id` lets a client choose the id (a retried upload from a phone that was
/// offline must not create a second copy); the existing file is returned if it is already there
/// for this company.
#[allow(clippy::too_many_arguments)]
pub async fn store_image(
    conn: &mut PgConnection,
    blobs: &BlobStore,
    company_id: Uuid,
    id: Option<Uuid>,
    filename: &str,
    bytes: &[u8],
    uploaded_by: Option<Uuid>,
    uploader_name: &str,
) -> AppResult<FileInfo> {
    store(
        conn,
        blobs,
        company_id,
        id,
        filename,
        bytes,
        uploaded_by,
        uploader_name,
        sniff_image,
        "only JPEG, PNG and WebP images are accepted",
    )
    .await
}

/// Stores a ticket attachment: a JPEG, PNG or WebP image or a PDF document. Same rules as
/// [`store_image`].
#[allow(clippy::too_many_arguments)]
pub async fn store_document(
    conn: &mut PgConnection,
    blobs: &BlobStore,
    company_id: Uuid,
    id: Option<Uuid>,
    filename: &str,
    bytes: &[u8],
    uploaded_by: Option<Uuid>,
    uploader_name: &str,
) -> AppResult<FileInfo> {
    store(
        conn,
        blobs,
        company_id,
        id,
        filename,
        bytes,
        uploaded_by,
        uploader_name,
        sniff_document,
        "only JPEG, PNG and WebP images and PDF documents are accepted",
    )
    .await
}

#[allow(clippy::too_many_arguments)]
async fn store(
    conn: &mut PgConnection,
    blobs: &BlobStore,
    company_id: Uuid,
    id: Option<Uuid>,
    filename: &str,
    bytes: &[u8],
    uploaded_by: Option<Uuid>,
    uploader_name: &str,
    sniff: fn(&[u8]) -> Option<&'static str>,
    refusal: &str,
) -> AppResult<FileInfo> {
    if bytes.is_empty() {
        return Err(AppError::Validation("the file is empty".into()));
    }
    if bytes.len() > MAX_FILE_BYTES {
        return Err(AppError::Validation(format!(
            "the file is too large (at most {} MB)",
            MAX_FILE_BYTES / 1024 / 1024
        )));
    }
    let content_type = sniff(bytes).ok_or_else(|| AppError::Validation(refusal.into()))?;
    let id = id.unwrap_or_else(new_id);
    if let Some(existing) = get_info(conn, company_id, id).await? {
        return Ok(existing);
    }
    let storage_key = blobs.put(bytes).await?;
    let res = sqlx::query_as::<_, FileInfo>(
        "INSERT INTO core.files (id, company_id, filename, content_type, size_bytes, uploaded_by, uploader_name, storage_key)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
         RETURNING id, filename, content_type, size_bytes, uploader_name, created_at",
    )
    .bind(id)
    .bind(company_id)
    .bind(clean_filename(filename, content_type))
    .bind(content_type)
    .bind(bytes.len() as i32)
    .bind(uploaded_by)
    .bind(uploader_name)
    .bind(&storage_key)
    .fetch_one(conn)
    .await;
    match res {
        Ok(info) => Ok(info),
        Err(e) => {
            let _ = blobs.delete(&storage_key).await;
            Err(e.into())
        }
    }
}

pub async fn get_info(
    conn: &mut PgConnection,
    company_id: Uuid,
    id: Uuid,
) -> AppResult<Option<FileInfo>> {
    Ok(sqlx::query_as(
        "SELECT id, filename, content_type, size_bytes, uploader_name, created_at
         FROM core.files WHERE id = $1 AND company_id = $2",
    )
    .bind(id)
    .bind(company_id)
    .fetch_optional(conn)
    .await?)
}

/// The bytes and content type of a file of this company.
pub async fn load(
    conn: &mut PgConnection,
    blobs: &BlobStore,
    company_id: Uuid,
    id: Uuid,
) -> AppResult<(String, Vec<u8>)> {
    let (content_type, storage_key): (String, String) = sqlx::query_as(
        "SELECT content_type, storage_key FROM core.files WHERE id = $1 AND company_id = $2",
    )
    .bind(id)
    .bind(company_id)
    .fetch_optional(conn)
    .await?
    .ok_or(AppError::NotFound("file"))?;
    let bytes = blobs.get(&storage_key).await?;
    Ok((content_type, bytes))
}

/// A response for a stored image. Photos never change, so browsers may cache them; they are
/// private (they are behind a login) and must not be sniffed as anything but an image.
pub fn image_response(content_type: &str, data: Vec<u8>) -> axum::response::Response {
    use axum::response::IntoResponse;
    (
        [
            (axum::http::header::CONTENT_TYPE, content_type.to_string()),
            (
                axum::http::header::CACHE_CONTROL,
                "private, max-age=86400".to_string(),
            ),
            (
                axum::http::header::X_CONTENT_TYPE_OPTIONS,
                "nosniff".to_string(),
            ),
        ],
        data,
    )
        .into_response()
}

/// A download of a stored file: always an attachment (never rendered by the browser), with a
/// cleaned file name and no content sniffing.
pub fn attachment_response(
    content_type: &str,
    filename: &str,
    data: Vec<u8>,
) -> axum::response::Response {
    use axum::response::IntoResponse;
    let ascii: String = filename
        .chars()
        .map(|c| if c.is_ascii() { c } else { '_' })
        .collect();
    let encoded: String = filename
        .bytes()
        .map(|b| {
            if b.is_ascii_alphanumeric() || b"-_.".contains(&b) {
                (b as char).to_string()
            } else {
                format!("%{b:02X}")
            }
        })
        .collect();
    (
        [
            (axum::http::header::CONTENT_TYPE, content_type.to_string()),
            (
                axum::http::header::CONTENT_DISPOSITION,
                format!("attachment; filename=\"{ascii}\"; filename*=UTF-8''{encoded}"),
            ),
            (
                axum::http::header::CACHE_CONTROL,
                "private, max-age=86400".to_string(),
            ),
            (
                axum::http::header::X_CONTENT_TYPE_OPTIONS,
                "nosniff".to_string(),
            ),
        ],
        data,
    )
        .into_response()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn images_are_recognised_by_signature_only() {
        assert_eq!(
            sniff_image(&[0xFF, 0xD8, 0xFF, 0xE0, 0, 0]),
            Some("image/jpeg")
        );
        assert_eq!(
            sniff_image(&[0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A, 0, 0]),
            Some("image/png")
        );
        assert_eq!(sniff_image(b"RIFF\0\0\0\0WEBPVP8 "), Some("image/webp"));
        // A renamed executable, a PDF, an SVG (can carry script) and text are all refused.
        assert_eq!(sniff_image(b"MZ\x90\x00\x03"), None);
        assert_eq!(sniff_image(b"%PDF-1.7"), None);
        assert_eq!(
            sniff_image(b"<svg xmlns='http://www.w3.org/2000/svg'/>"),
            None
        );
        assert_eq!(sniff_image(b"RIFF\0\0\0\0WAVEfmt "), None);
        assert_eq!(sniff_image(b""), None);
    }

    #[test]
    fn documents_are_images_or_pdf_only() {
        assert_eq!(sniff_document(b"%PDF-1.7\n"), Some("application/pdf"));
        assert_eq!(
            sniff_document(&[0xFF, 0xD8, 0xFF, 0xE0]),
            Some("image/jpeg")
        );
        assert_eq!(sniff_document(b"MZ\x90\x00"), None);
        assert_eq!(sniff_document(b"plain text"), None);
        assert_eq!(sniff_document(b"<svg/>"), None);
        assert_eq!(clean_filename("", "application/pdf"), "document.pdf");
    }

    #[test]
    fn file_names_lose_paths_and_odd_characters() {
        assert_eq!(clean_filename("../../etc/passwd", "image/jpeg"), "passwd");
        assert_eq!(
            clean_filename("C:\\Users\\a\\IMG_001.jpg", "image/jpeg"),
            "IMG_001.jpg"
        );
        assert_eq!(clean_filename("a\"<b>.png", "image/png"), "ab.png");
        assert_eq!(clean_filename("  ", "image/png"), "photo.png");
        assert_eq!(clean_filename("", "image/webp"), "photo.webp");
    }
}
