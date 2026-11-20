//! Removes chatter rows whose record no longer exists, and uploads that were never put on a note
//! (ADR 0086). The address has no foreign key by design, so the worker does this.

use sqlx::PgPool;

use crate::RecordKind;

/// Pending uploads older than this are dropped.
const PENDING_UPLOAD_DAYS: i32 = 1;

/// Deletes the rows of deleted records and stale pending uploads; returns how many rows went.
pub async fn remove_orphans(db: &PgPool) -> Result<u64, sqlx::Error> {
    let mut removed = 0;
    for kind in RecordKind::ALL {
        let table = kind.table();
        for chatter_table in ["messages", "activities", "followers", "message_files"] {
            let sql = format!(
                "DELETE FROM chatter.{chatter_table} c
                 WHERE c.record_kind = $1
                   AND NOT EXISTS (SELECT 1 FROM {table} r WHERE r.id = c.record_id)"
            );
            removed += sqlx::query(&sql)
                .bind(kind.as_str())
                .execute(db)
                .await?
                .rows_affected();
        }
    }
    removed += sqlx::query(
        "DELETE FROM chatter.message_files
         WHERE message_id IS NULL AND created_at < now() - make_interval(days => $1)",
    )
    .bind(PENDING_UPLOAD_DAYS)
    .execute(db)
    .await?
    .rows_affected();
    Ok(removed)
}
