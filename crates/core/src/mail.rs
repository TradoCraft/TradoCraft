//! System e-mail that is not part of a ticket (e.g. portal login links). Rows are queued in the
//! same transaction as the business operation and sent by the worker.

use sqlx::PgConnection;
use uuid::Uuid;

use crate::{AppResult, BlobStore};

/// Queues a plain-text e-mail from the company's address.
pub async fn enqueue(
    conn: &mut PgConnection,
    company_id: Uuid,
    to_address: &str,
    subject: &str,
    body: &str,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        "INSERT INTO core.mail_outbox (id, company_id, to_address, subject, body) VALUES ($1, $2, $3, $4, $5)",
    )
    .bind(crate::new_id())
    .bind(company_id)
    .bind(to_address)
    .bind(subject)
    .bind(body)
    .execute(conn)
    .await?;
    Ok(())
}

/// Queues a plain-text e-mail with one attachment (e.g. a PDF document).
pub async fn enqueue_with_attachment(
    conn: &mut PgConnection,
    blobs: &BlobStore,
    company_id: Uuid,
    to_address: &str,
    subject: &str,
    body: &str,
    attachment: Attachment<'_>,
) -> AppResult<()> {
    let storage_key = blobs.put(attachment.data).await?;
    let res = sqlx::query(
        "INSERT INTO core.mail_outbox (id, company_id, to_address, subject, body,
                                       attachment_name, attachment_type, attachment_storage_key)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)",
    )
    .bind(crate::new_id())
    .bind(company_id)
    .bind(to_address)
    .bind(subject)
    .bind(body)
    .bind(attachment.filename)
    .bind(attachment.content_type)
    .bind(&storage_key)
    .execute(conn)
    .await;
    if let Err(e) = res {
        let _ = blobs.delete(&storage_key).await;
        return Err(e.into());
    }
    Ok(())
}

/// A file sent along with a system e-mail.
pub struct Attachment<'a> {
    pub filename: &'a str,
    pub content_type: &'a str,
    pub data: &'a [u8],
}
