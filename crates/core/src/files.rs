//! Photo and document storage. Files are checked by their signature (not their name or declared type), size
//! limited, and kept on disk in [`BlobStore`] next to a PostgreSQL metadata row. Modules link files to
//! their own records and decide who may see them; this module only stores and loads.

use sqlx::{FromRow, PgConnection};
use uuid::Uuid;

use crate::{new_id, AppError, AppResult, BlobStore};

/// Largest accepted upload (a phone photo is typically 2–6 MB).
pub const MAX_FILE_BYTES: usize = 12 * 1024 * 1024;

/// Largest accepted video (product media only).
pub const MAX_VIDEO_BYTES: usize = 64 * 1024 * 1024;

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

/// The content type of a product picture or video: an image (see [`sniff_image`]), an MP4 or a WebM.
pub fn sniff_media(bytes: &[u8]) -> Option<&'static str> {
    if let Some(t) = sniff_image(bytes) {
        Some(t)
    } else if bytes.len() > 12 && &bytes[4..8] == b"ftyp" {
        Some("video/mp4")
    } else if bytes.starts_with(&[0x1A, 0x45, 0xDF, 0xA3]) {
        Some("video/webm")
    } else {
        None
    }
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
            "video/mp4" => return "video.mp4".to_string(),
            "video/webm" => return "video.webm".to_string(),
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
        MAX_FILE_BYTES,
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
        MAX_FILE_BYTES,
    )
    .await
}

/// Stores a product picture or video: JPEG, PNG, WebP, MP4 or WebM. Images are limited to
/// [`MAX_FILE_BYTES`], videos to [`MAX_VIDEO_BYTES`]. Returns `(file, created)` where `created` is
/// `true` only when this call inserted the `core.files` row.
#[allow(clippy::too_many_arguments)]
pub async fn store_media(
    conn: &mut PgConnection,
    blobs: &BlobStore,
    company_id: Uuid,
    id: Option<Uuid>,
    filename: &str,
    bytes: &[u8],
    uploaded_by: Option<Uuid>,
    uploader_name: &str,
) -> AppResult<(FileInfo, bool)> {
    const REFUSAL: &str = "only JPEG, PNG and WebP images and MP4 or WebM videos are accepted";
    if bytes.is_empty() {
        return Err(AppError::Validation("the file is empty".into()));
    }
    let max = if sniff_image(bytes).is_some() {
        MAX_FILE_BYTES
    } else {
        MAX_VIDEO_BYTES
    };
    if bytes.len() > max {
        return Err(AppError::Validation(format!(
            "the file is too large (at most {} MB)",
            max / 1024 / 1024
        )));
    }
    let content_type = sniff_media(bytes).ok_or_else(|| AppError::Validation(REFUSAL.into()))?;
    let storage_key = blobs.put(bytes).await?;
    record_staged_media(
        conn,
        blobs,
        company_id,
        id,
        filename,
        StagedMedia {
            storage_key,
            content_type,
            size_bytes: bytes.len() as i32,
        },
        uploaded_by,
        uploader_name,
    )
    .await
}

/// A validated media payload written to [`BlobStore`], ready to be recorded in `core.files`.
pub struct StagedMedia {
    pub storage_key: String,
    pub content_type: &'static str,
    pub size_bytes: i32,
}

/// Streams a product picture or video upload to [`BlobStore`] in bounded 64 KB chunks while
/// incrementally checking its signature and size limit (`MAX_FILE_BYTES` for images,
/// `MAX_VIDEO_BYTES` for videos). No database lock is held while receiving the upload.
pub async fn stage_media_stream(
    blobs: &BlobStore,
    body: axum::body::Body,
) -> AppResult<StagedMedia> {
    use futures_core::Stream;
    use std::pin::Pin;
    use tokio::io::AsyncWriteExt;

    const REFUSAL: &str = "only JPEG, PNG and WebP images and MP4 or WebM videos are accepted";
    let staged = blobs.begin_write().await?;
    let file = match tokio::fs::File::create(&staged.tmp_path).await {
        Ok(f) => f,
        Err(e) => {
            staged.abort().await;
            return Err(anyhow::Error::from(e)
                .context("create staged media file")
                .into());
        }
    };
    let mut writer = tokio::io::BufWriter::with_capacity(64 * 1024, file);
    let mut stream = body.into_data_stream();
    let mut header = Vec::with_capacity(16);
    let mut content_type: Option<&'static str> = None;
    let mut max_bytes = MAX_VIDEO_BYTES;
    let mut total_bytes: usize = 0;

    while let Some(next) = std::future::poll_fn(|cx| Pin::new(&mut stream).poll_next(cx)).await {
        let chunk = match next {
            Ok(c) => c,
            Err(e) => {
                drop(writer);
                staged.abort().await;
                return Err(AppError::Validation(format!("upload stream failed: {e}")));
            }
        };
        if chunk.is_empty() {
            continue;
        }
        if header.len() < 16 {
            let take = (16 - header.len()).min(chunk.len());
            header.extend_from_slice(&chunk[..take]);
        }
        if content_type.is_none() && header.len() >= 13 {
            let Some(ct) = sniff_media(&header) else {
                drop(writer);
                staged.abort().await;
                return Err(AppError::Validation(REFUSAL.into()));
            };
            content_type = Some(ct);
            max_bytes = if ct.starts_with("image/") {
                MAX_FILE_BYTES
            } else {
                MAX_VIDEO_BYTES
            };
        }
        total_bytes = total_bytes.saturating_add(chunk.len());
        if total_bytes > max_bytes {
            drop(writer);
            staged.abort().await;
            return Err(AppError::Validation(format!(
                "the file is too large (at most {} MB)",
                max_bytes / 1024 / 1024
            )));
        }
        if let Err(e) = writer.write_all(&chunk).await {
            drop(writer);
            staged.abort().await;
            return Err(anyhow::Error::from(e)
                .context("write staged media chunk")
                .into());
        }
    }

    if total_bytes == 0 {
        drop(writer);
        staged.abort().await;
        return Err(AppError::Validation("the file is empty".into()));
    }
    let ct = match content_type.or_else(|| sniff_media(&header)) {
        Some(ct) => ct,
        None => {
            drop(writer);
            staged.abort().await;
            return Err(AppError::Validation(REFUSAL.into()));
        }
    };
    let final_max = if ct.starts_with("image/") {
        MAX_FILE_BYTES
    } else {
        MAX_VIDEO_BYTES
    };
    if total_bytes > final_max {
        drop(writer);
        staged.abort().await;
        return Err(AppError::Validation(format!(
            "the file is too large (at most {} MB)",
            final_max / 1024 / 1024
        )));
    }
    if let Err(e) = writer.flush().await {
        drop(writer);
        staged.abort().await;
        return Err(anyhow::Error::from(e)
            .context("flush staged media file")
            .into());
    }
    drop(writer);
    let storage_key = staged.commit().await?;
    Ok(StagedMedia {
        storage_key,
        content_type: ct,
        size_bytes: total_bytes as i32,
    })
}

/// Records a [`StagedMedia`] in `core.files`, returning `(file, created)` where `created` is
/// `true` only when this call inserted the `core.files` row. Always cleans up
/// `staged.storage_key` if an existing row is reused or if the insert fails.
#[allow(clippy::too_many_arguments)]
pub async fn record_staged_media(
    conn: &mut PgConnection,
    blobs: &BlobStore,
    company_id: Uuid,
    id: Option<Uuid>,
    filename: &str,
    staged: StagedMedia,
    uploaded_by: Option<Uuid>,
    uploader_name: &str,
) -> AppResult<(FileInfo, bool)> {
    let id = id.unwrap_or_else(new_id);
    let res = sqlx::query_as::<_, FileInfo>(
        "INSERT INTO core.files (id, company_id, filename, content_type, size_bytes, uploaded_by, uploader_name, storage_key)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
         ON CONFLICT (id) DO NOTHING
         RETURNING id, filename, content_type, size_bytes, uploader_name, created_at",
    )
    .bind(id)
    .bind(company_id)
    .bind(clean_filename(filename, staged.content_type))
    .bind(staged.content_type)
    .bind(staged.size_bytes)
    .bind(uploaded_by)
    .bind(uploader_name)
    .bind(&staged.storage_key)
    .fetch_optional(&mut *conn)
    .await;
    match res {
        Ok(Some(info)) => Ok((info, true)),
        Ok(None) => {
            let _ = blobs.delete(&staged.storage_key).await;
            let existing = get_info(conn, company_id, id).await?.ok_or_else(|| {
                AppError::Conflict("this file id belongs to another record".into())
            })?;
            Ok((existing, false))
        }
        Err(e) => {
            let _ = blobs.delete(&staged.storage_key).await;
            Err(e.into())
        }
    }
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
    max_bytes: usize,
) -> AppResult<FileInfo> {
    if bytes.is_empty() {
        return Err(AppError::Validation("the file is empty".into()));
    }
    if bytes.len() > max_bytes {
        return Err(AppError::Validation(format!(
            "the file is too large (at most {} MB)",
            max_bytes / 1024 / 1024
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
            // A document download is not kept by browsers or proxies: access can be withdrawn.
            (
                axum::http::header::CACHE_CONTROL,
                "private, no-store".to_string(),
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
