//! Filesystem blob store orphan sweep test against PostgreSQL.

mod common;

use std::time::Duration;

use sqlx::PgPool;

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn sweep_orphans_removes_only_unreferenced_files(db: PgPool) {
    let (_app, blobs) = common::setup_with_blobs(db.clone()).await;

    // 1. Live file referenced by core.files
    let live_key = blobs.put(b"live photo").await.unwrap();
    let company_id: uuid::Uuid = sqlx::query_scalar("SELECT id FROM core.companies LIMIT 1")
        .fetch_one(&db)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO core.files (id, company_id, filename, content_type, size_bytes, storage_key)
         VALUES ($1, $2, 'photo.jpg', 'image/jpeg', 10, $3)",
    )
    .bind(tradocraft_core::new_id())
    .bind(company_id)
    .bind(&live_key)
    .execute(&db)
    .await
    .unwrap();

    // 2. Orphan file not referenced anywhere
    let orphan_key = blobs.put(b"orphan bytes").await.unwrap();

    // With a 24h min_age, neither is removed.
    assert_eq!(
        blobs
            .sweep_orphans(&db, Duration::from_secs(24 * 3600))
            .await
            .unwrap(),
        0
    );
    assert_eq!(blobs.get(&live_key).await.unwrap(), b"live photo");
    assert_eq!(blobs.get(&orphan_key).await.unwrap(), b"orphan bytes");

    // With min_age = 0, only the orphan is removed.
    assert_eq!(blobs.sweep_orphans(&db, Duration::ZERO).await.unwrap(), 1);
    assert_eq!(blobs.get(&live_key).await.unwrap(), b"live photo");
    assert!(blobs.get(&orphan_key).await.is_err());

    let _ = std::fs::remove_dir_all(blobs.root());
}

#[sqlx::test(migrator = "tradocraft_api::MIGRATOR")]
async fn pending_reference_blocks_sweep_until_rollback(db: PgPool) {
    let (_, blobs) = common::setup_with_blobs(db.clone()).await;
    let mut tx = db.begin().await.unwrap();
    sqlx::query("SELECT pg_advisory_xact_lock_shared(743902104)")
        .execute(&mut *tx)
        .await
        .unwrap();
    let key = blobs.put(b"pending message").await.unwrap();
    assert_eq!(blobs.sweep_orphans(&db, Duration::ZERO).await.unwrap(), 0);
    assert_eq!(blobs.get(&key).await.unwrap(), b"pending message");
    tx.rollback().await.unwrap();
    assert_eq!(blobs.sweep_orphans(&db, Duration::ZERO).await.unwrap(), 1);
    assert!(blobs.get(&key).await.is_err());
    std::fs::remove_dir_all(blobs.root()).unwrap();
}
