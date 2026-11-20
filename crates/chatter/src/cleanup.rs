//! Removes chatter rows whose record no longer exists, and uploads that were never put on a note
//! (ADR 0086). The address has no foreign key by design, so the worker does this.

use sqlx::PgPool;
use uuid::Uuid;

use crate::RecordKind;

/// Pending uploads older than this are dropped.
const PENDING_UPLOAD_DAYS: i32 = 1;

/// Deletes the rows of deleted records and stale pending uploads, and the stored file of an
/// upload that nothing else uses any more. Returns how many chatter rows went; the blob of a
/// deleted file is removed by the blob sweep.
pub async fn remove_orphans(db: &PgPool) -> Result<u64, sqlx::Error> {
    let mut removed = 0;
    let mut released: Vec<Uuid> = Vec::new();
    for kind in RecordKind::ALL {
        let table = kind.table();
        // The links first, so the files they held can be released.
        let sql = format!(
            "DELETE FROM chatter.message_files c
             WHERE c.record_kind = $1
               AND NOT EXISTS (SELECT 1 FROM {table} r WHERE r.id = c.record_id)
             RETURNING c.file_id"
        );
        let ids: Vec<Uuid> = sqlx::query_scalar(&sql)
            .bind(kind.as_str())
            .fetch_all(db)
            .await?;
        removed += ids.len() as u64;
        released.extend(ids);
        for chatter_table in ["messages", "activities", "followers"] {
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
    let stale: Vec<Uuid> = sqlx::query_scalar(
        "DELETE FROM chatter.message_files
         WHERE message_id IS NULL AND created_at < now() - make_interval(days => $1)
         RETURNING file_id",
    )
    .bind(PENDING_UPLOAD_DAYS)
    .fetch_all(db)
    .await?;
    removed += stale.len() as u64;
    released.extend(stale);
    release_files(db, &released).await?;
    Ok(removed)
}

/// Deletes the `core.files` rows among `ids` that no table references any more. The referencing
/// tables are read from the catalog, so a module that starts to keep files is respected without
/// this list being touched.
async fn release_files(db: &PgPool, ids: &[Uuid]) -> Result<(), sqlx::Error> {
    if ids.is_empty() {
        return Ok(());
    }
    let refs: Vec<(String, String)> = sqlx::query_as(
        "SELECT c.conrelid::regclass::text, a.attname::text
         FROM pg_constraint c
         JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY(c.conkey)
         WHERE c.contype = 'f' AND c.confrelid = 'core.files'::regclass",
    )
    .fetch_all(db)
    .await?;
    let unused: String = refs
        .iter()
        .map(|(table, col)| {
            format!(
                " AND NOT EXISTS (SELECT 1 FROM {table} t WHERE t.\"{}\" = f.id)",
                col.replace('"', "\"\"")
            )
        })
        .collect();
    sqlx::query(&format!(
        "DELETE FROM core.files f WHERE f.id = ANY($1){unused}"
    ))
    .bind(ids)
    .execute(db)
    .await?;
    Ok(())
}
