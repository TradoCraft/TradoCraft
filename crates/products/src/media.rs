//! Pictures and videos of a product. A product has any number of them and at most one is the
//! default, the one shown first. The first upload becomes the default; deleting the default
//! promotes the oldest remaining one, so a product with media always has a default.

use axum::body::Body;
use axum::extract::{DefaultBodyLimit, Path, Query, State};
use axum::http::StatusCode;
use axum::response::Response;
use axum::Json;
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection};
use tradocraft_core::files::{self, MAX_VIDEO_BYTES};
use tradocraft_core::{audit, AppError, AppResult, AppState, CurrentUser, Permission};
use utoipa::{IntoParams, ToSchema};
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct ProductMedia {
    /// The id of the stored file; also the id in the URLs.
    pub id: Uuid,
    /// image | video
    pub kind: String,
    pub content_type: String,
    pub filename: String,
    pub size_bytes: i32,
    pub caption: String,
    /// Shown first. Exactly one item of a product has it.
    pub is_default: bool,
    pub created_at: chrono::DateTime<chrono::Utc>,
}

const SELECT: &str = "SELECT m.file_id AS id, m.kind, f.content_type, f.filename, f.size_bytes,
        m.caption, m.is_default, m.created_at
     FROM products.media m JOIN core.files f ON f.id = m.file_id";

/// The default pictures of products, for documents: product id to `(file name, bytes)`. JPEG, PNG
/// and SVG pictures are returned; products whose default is a video or has another format are left
/// out, and so are products without media.
pub async fn default_images(
    conn: &mut PgConnection,
    blobs: &tradocraft_core::BlobStore,
    product_ids: &[Uuid],
) -> AppResult<std::collections::HashMap<Uuid, (String, Vec<u8>)>> {
    let rows: Vec<(Uuid, Uuid, Uuid, String)> = sqlx::query_as(
        "SELECT m.product_id, m.file_id, m.company_id, f.content_type
         FROM products.media m JOIN core.files f ON f.id = m.file_id
         WHERE m.is_default AND m.product_id = ANY($1)
           AND f.content_type IN ('image/jpeg', 'image/png', 'image/svg+xml')",
    )
    .bind(product_ids)
    .fetch_all(&mut *conn)
    .await?;
    let mut out = std::collections::HashMap::new();
    for (product_id, file_id, owner, content_type) in rows {
        // a picture that cannot be read must not stop the document
        let Ok((_, bytes)) = files::load(conn, blobs, owner, file_id).await else {
            continue;
        };
        if content_type == "image/svg+xml" && tradocraft_core::logo::svg_problem(&bytes).is_some() {
            continue;
        }
        let ext = match content_type.as_str() {
            "image/png" => "png",
            "image/svg+xml" => "svg",
            _ => "jpg",
        };
        out.insert(product_id, (format!("p-{product_id}.{ext}"), bytes));
    }
    Ok(out)
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct UploadParams {
    pub caption: Option<String>,
    /// The original file name.
    pub filename: Option<String>,
    /// A client-chosen id: uploading the same id again returns the first upload (safe retries).
    pub client_id: Option<Uuid>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct MediaUpdate {
    pub caption: Option<String>,
    /// `true` makes this the default (the previous default loses it); `false` is refused, pick
    /// another item as the default instead.
    pub is_default: Option<bool>,
}

/// Products are shared by all companies; media belong to the company that uploaded them (which
/// owns the stored file) but are visible wherever the product is.
async fn ensure_product(conn: &mut PgConnection, id: Uuid) -> AppResult<()> {
    let ok: bool =
        sqlx::query_scalar("SELECT EXISTS (SELECT 1 FROM products.products WHERE id = $1)")
            .bind(id)
            .fetch_one(conn)
            .await?;
    if ok {
        Ok(())
    } else {
        Err(AppError::NotFound("product"))
    }
}

async fn load_one(
    conn: &mut PgConnection,
    product_id: Uuid,
    file_id: Uuid,
) -> AppResult<ProductMedia> {
    sqlx::query_as(sqlx::AssertSqlSafe(format!(
        "{SELECT} WHERE m.product_id = $1 AND m.file_id = $2"
    )))
    .bind(product_id)
    .bind(file_id)
    .fetch_optional(conn)
    .await?
    .ok_or(AppError::NotFound("media"))
}

#[utoipa::path(get, path = "/products/{id}/media", tag = "products", params(("id" = Uuid, Path)),
    responses((status = 200, body = Vec<ProductMedia>)))]
async fn list_media(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<Vec<ProductMedia>>> {
    user.require(Permission::ProductsRead)?;
    let mut conn = state.db.acquire().await?;
    ensure_product(&mut conn, id).await?;
    // default first, then in the order they were added
    let rows = sqlx::query_as(sqlx::AssertSqlSafe(format!(
        "{SELECT} WHERE m.product_id = $1
         ORDER BY m.is_default DESC, m.created_at, m.file_id"
    )))
    .bind(id)
    .fetch_all(&mut *conn)
    .await?;
    Ok(Json(rows))
}

/// Verifies that a client-chosen file id is either unused or already media of this product.
/// Rejects file ids created by other modules (repairs, tickets, chatter) or for other products.
async fn verify_client_id(
    conn: &mut PgConnection,
    product_id: Uuid,
    client_id: Option<Uuid>,
) -> AppResult<()> {
    let Some(client_id) = client_id else {
        return Ok(());
    };
    let owner_product: Option<Uuid> =
        sqlx::query_scalar("SELECT product_id FROM products.media WHERE file_id = $1")
            .bind(client_id)
            .fetch_optional(&mut *conn)
            .await?;
    match owner_product {
        Some(p_id) if p_id == product_id => Ok(()),
        Some(_) => Err(AppError::Conflict(
            "this file id belongs to another record".into(),
        )),
        None => {
            let used: bool =
                sqlx::query_scalar("SELECT EXISTS (SELECT 1 FROM core.files WHERE id = $1)")
                    .bind(client_id)
                    .fetch_one(&mut *conn)
                    .await?;
            if used {
                Err(AppError::Conflict(
                    "this file id belongs to another record".into(),
                ))
            } else {
                Ok(())
            }
        }
    }
}

/// Adds a picture or video: the request body is the file itself (JPEG, PNG, WebP or SVG up to
/// 12 MB, MP4 or WebM up to 64 MB). The first item of a product becomes its default.
#[utoipa::path(post, path = "/products/{id}/media", tag = "products", operation_id = "upload_product_media",
    params(("id" = Uuid, Path), UploadParams),
    request_body(content = Vec<u8>, content_type = "application/octet-stream"),
    responses((status = 201, body = ProductMedia), (status = 422, body = tradocraft_core::error::ErrorBody)))]
async fn upload_media(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Query(p): Query<UploadParams>,
    body: Body,
) -> AppResult<(StatusCode, Json<ProductMedia>)> {
    user.require(Permission::ProductsWrite)?;
    {
        let mut conn = state.db.acquire().await?;
        ensure_product(&mut conn, id).await?;
        verify_client_id(&mut conn, id, p.client_id).await?;
    }
    // Stream and validate the upload to disk before acquiring the product row lock.
    let staged = files::stage_media_stream(&state.blobs, body).await?;
    let staged_key = staged.storage_key.clone();
    let mut tx = match state.db.begin().await {
        Ok(tx) => tx,
        Err(e) => {
            let _ = state.blobs.delete(&staged_key).await;
            return Err(e.into());
        }
    };
    let pre_commit: AppResult<ProductMedia> = async {
        ensure_product(&mut tx, id).await?;
        // serialise uploads to one product so "the first one is the default" holds
        sqlx::query("SELECT id FROM products.products WHERE id = $1 FOR UPDATE")
            .bind(id)
            .execute(&mut *tx)
            .await?;
        verify_client_id(&mut tx, id, p.client_id).await?;
        let (file, created) = files::record_staged_media(
            &mut tx,
            &state.blobs,
            user.company_id,
            p.client_id,
            p.filename.as_deref().unwrap_or(""),
            staged,
            Some(user.user_id),
            &user.display_name,
        )
        .await?;
        if !created {
            let same: bool = sqlx::query_scalar(
                "SELECT EXISTS (SELECT 1 FROM products.media WHERE file_id = $1 AND product_id = $2)",
            )
            .bind(file.id)
            .bind(id)
            .fetch_one(&mut *tx)
            .await?;
            if !same {
                return Err(AppError::Conflict(
                    "this file id belongs to another record".into(),
                ));
            }
        } else {
            let kind = if file.content_type.starts_with("video/") {
                "video"
            } else {
                "image"
            };
            sqlx::query(
                "INSERT INTO products.media (file_id, company_id, product_id, kind, caption, is_default)
                 VALUES ($1, $2, $3, $4, $5,
                         NOT EXISTS (SELECT 1 FROM products.media WHERE product_id = $3 AND is_default))",
            )
            .bind(file.id)
            .bind(user.company_id)
            .bind(id)
            .bind(kind)
            .bind(p.caption.as_deref().unwrap_or("").trim())
            .execute(&mut *tx)
            .await?;
            audit::record(
                &mut tx,
                &user,
                "product",
                id,
                "media_added",
                serde_json::json!({ "file_id": file.id, "kind": kind }),
            )
            .await?;
        }
        load_one(&mut tx, id, file.id).await
    }
    .await;
    let media = match pre_commit {
        Ok(media) => media,
        Err(e) => {
            let _ = tx.rollback().await;
            let _ = state.blobs.delete(&staged_key).await;
            return Err(e);
        }
    };
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(media)))
}

/// The file itself.
#[utoipa::path(get, path = "/products/{id}/media/{media_id}", tag = "products", operation_id = "get_product_media",
    params(("id" = Uuid, Path), ("media_id" = Uuid, Path)),
    responses(
        (status = 200, content(
            (Vec<u8> = "image/jpeg"),
            (Vec<u8> = "image/png"),
            (Vec<u8> = "image/webp"),
            (Vec<u8> = "image/svg+xml"),
            (Vec<u8> = "video/mp4"),
            (Vec<u8> = "video/webm"),
        )),
        (status = 404, body = tradocraft_core::error::ErrorBody)
    ))]
async fn get_media(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((id, media_id)): Path<(Uuid, Uuid)>,
) -> AppResult<Response> {
    user.require(Permission::ProductsRead)?;
    let mut conn = state.db.acquire().await?;
    let owner: Uuid = sqlx::query_scalar(
        "SELECT company_id FROM products.media WHERE product_id = $1 AND file_id = $2",
    )
    .bind(id)
    .bind(media_id)
    .fetch_optional(&mut *conn)
    .await?
    .ok_or(AppError::NotFound("media"))?;
    let (content_type, data) = files::load(&mut conn, &state.blobs, owner, media_id).await?;
    Ok(files::image_response(&content_type, data))
}

/// The default picture or video of the product, or 404 when it has none.
#[utoipa::path(get, path = "/products/{id}/media/default", tag = "products", operation_id = "get_product_default_media",
    params(("id" = Uuid, Path)),
    responses(
        (status = 200, content(
            (Vec<u8> = "image/jpeg"),
            (Vec<u8> = "image/png"),
            (Vec<u8> = "image/webp"),
            (Vec<u8> = "image/svg+xml"),
            (Vec<u8> = "video/mp4"),
            (Vec<u8> = "video/webm"),
        )),
        (status = 404, body = tradocraft_core::error::ErrorBody)
    ))]
async fn get_default_media(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Response> {
    user.require(Permission::ProductsRead)?;
    let mut conn = state.db.acquire().await?;
    let (file_id, owner): (Uuid, Uuid) = sqlx::query_as(
        "SELECT file_id, company_id FROM products.media WHERE product_id = $1 AND is_default",
    )
    .bind(id)
    .fetch_optional(&mut *conn)
    .await?
    .ok_or(AppError::NotFound("media"))?;
    let (content_type, data) = files::load(&mut conn, &state.blobs, owner, file_id).await?;
    Ok(files::image_response(&content_type, data))
}

#[utoipa::path(patch, path = "/products/{id}/media/{media_id}", tag = "products", operation_id = "update_product_media",
    params(("id" = Uuid, Path), ("media_id" = Uuid, Path)), request_body = MediaUpdate,
    responses((status = 200, body = ProductMedia), (status = 422, body = tradocraft_core::error::ErrorBody)))]
async fn update_media(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((id, media_id)): Path<(Uuid, Uuid)>,
    Json(input): Json<MediaUpdate>,
) -> AppResult<Json<ProductMedia>> {
    user.require(Permission::ProductsWrite)?;
    let mut tx = state.db.begin().await?;
    ensure_product(&mut tx, id).await?;
    sqlx::query("SELECT id FROM products.products WHERE id = $1 FOR UPDATE")
        .bind(id)
        .execute(&mut *tx)
        .await?;
    let current = load_one(&mut tx, id, media_id).await?;
    if input.is_default == Some(false) && current.is_default {
        return Err(AppError::Validation(
            "choose another item as the default instead".into(),
        ));
    }
    if let Some(caption) = &input.caption {
        sqlx::query(
            "UPDATE products.media SET caption = $1 WHERE product_id = $2 AND file_id = $3",
        )
        .bind(caption.trim())
        .bind(id)
        .bind(media_id)
        .execute(&mut *tx)
        .await?;
    }
    if input.is_default == Some(true) && !current.is_default {
        sqlx::query(
            "UPDATE products.media SET is_default = false WHERE product_id = $1 AND is_default",
        )
        .bind(id)
        .execute(&mut *tx)
        .await?;
        sqlx::query(
            "UPDATE products.media SET is_default = true WHERE product_id = $1 AND file_id = $2",
        )
        .bind(id)
        .bind(media_id)
        .execute(&mut *tx)
        .await?;
        audit::record(
            &mut tx,
            &user,
            "product",
            id,
            "media_default_set",
            serde_json::json!({ "file_id": media_id }),
        )
        .await?;
    }
    let media = load_one(&mut tx, id, media_id).await?;
    tx.commit().await?;
    Ok(Json(media))
}

/// Removes the item from the product. If it was the default, the oldest remaining item becomes
/// the default.
#[utoipa::path(delete, path = "/products/{id}/media/{media_id}", tag = "products", operation_id = "delete_product_media",
    params(("id" = Uuid, Path), ("media_id" = Uuid, Path)),
    responses((status = 204), (status = 404, body = tradocraft_core::error::ErrorBody)))]
async fn delete_media(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((id, media_id)): Path<(Uuid, Uuid)>,
) -> AppResult<StatusCode> {
    user.require(Permission::ProductsWrite)?;
    let mut tx = state.db.begin().await?;
    ensure_product(&mut tx, id).await?;
    sqlx::query("SELECT id FROM products.products WHERE id = $1 FOR UPDATE")
        .bind(id)
        .execute(&mut *tx)
        .await?;
    let current = load_one(&mut tx, id, media_id).await?;
    sqlx::query("DELETE FROM products.media WHERE product_id = $1 AND file_id = $2")
        .bind(id)
        .bind(media_id)
        .execute(&mut *tx)
        .await?;
    if current.is_default {
        sqlx::query(
            "UPDATE products.media SET is_default = true WHERE file_id = (
                 SELECT file_id FROM products.media WHERE product_id = $1
                 ORDER BY created_at, file_id LIMIT 1)",
        )
        .bind(id)
        .execute(&mut *tx)
        .await?;
    }
    audit::record(
        &mut tx,
        &user,
        "product",
        id,
        "media_removed",
        serde_json::json!({ "file_id": media_id }),
    )
    .await?;
    tx.commit().await?;
    Ok(StatusCode::NO_CONTENT)
}

pub fn router() -> OpenApiRouter<AppState> {
    // Uploads carry whole videos: raise the default body limit for them only.
    let uploads = OpenApiRouter::new()
        .routes(routes!(upload_media))
        .layer(DefaultBodyLimit::max(MAX_VIDEO_BYTES + 64 * 1024));
    OpenApiRouter::new()
        .routes(routes!(list_media))
        .routes(routes!(get_default_media))
        .routes(routes!(get_media, update_media, delete_media))
        .merge(uploads)
}

#[cfg(test)]
mod tests {
    use tradocraft_core::files::sniff_media;

    #[test]
    fn recognises_images_and_videos_by_signature() {
        assert_eq!(
            sniff_media(&[0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
            Some("image/jpeg")
        );
        assert_eq!(
            sniff_media(b"\0\0\0\x18ftypmp42\0\0\0\0"),
            Some("video/mp4")
        );
        assert_eq!(
            sniff_media(&[0x1A, 0x45, 0xDF, 0xA3, 1, 2, 3]),
            Some("video/webm")
        );
        assert_eq!(sniff_media(b"%PDF-1.7 not media"), None);
        assert_eq!(sniff_media(b"<svg></svg>"), None);
    }
}
