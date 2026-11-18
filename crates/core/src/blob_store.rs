//! Filesystem blob storage for uploaded files, import spreadsheets, mail attachments and raw
//! incoming e-mails.
//!
//! Blobs are stored under `FILE_STORAGE_DIR` (default `data/files`) in a two-level sharded
//! directory layout (`<aa>/<bb>/<uuid>`), written atomically via `.tmp/<uuid>.part` and `rename`.
//! Storage keys are always UUIDv7 strings validated on every read/delete, so user-supplied paths
//! can never escape the root directory.
//! Durable writes require a Unix filesystem supporting file and directory fsync. Unsupported
//! directory synchronization fails the write; it is never silently treated as durable.

use std::collections::HashSet;
use std::io::ErrorKind;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime};

use anyhow::Context;
use sqlx::PgPool;
use uuid::Uuid;

use crate::{new_id, AppError, AppResult};

#[derive(Debug, Clone)]
pub struct BlobStore {
    root: PathBuf,
}

impl BlobStore {
    pub fn new(root: impl Into<PathBuf>) -> Self {
        Self { root: root.into() }
    }

    /// Reads `FILE_STORAGE_DIR` from the environment, falling back to `data/files`.
    pub fn from_env() -> Self {
        let root = std::env::var("FILE_STORAGE_DIR")
            .ok()
            .filter(|v| !v.trim().is_empty())
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from("data/files"));
        Self::new(root)
    }

    /// Isolated temporary directory for unit and integration tests.
    pub fn temp_for_tests() -> Self {
        Self::new(std::env::temp_dir().join(format!("tradocraft-blobs-{}", new_id())))
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    fn path_for(&self, key: &str) -> AppResult<PathBuf> {
        let id = Uuid::parse_str(key)
            .map_err(|_| AppError::Internal(anyhow::anyhow!("invalid blob storage key")))?;
        let hex = id.simple().to_string();
        Ok(self
            .root
            .join(&hex[0..2])
            .join(&hex[2..4])
            .join(id.to_string()))
    }

    /// Writes `bytes` atomically and returns the generated `storage_key`.
    pub async fn put(&self, bytes: &[u8]) -> AppResult<String> {
        let id = new_id();
        let key = id.to_string();
        let dest = self.path_for(&key)?;
        let tmp_dir = self.root.join(".tmp");
        let tmp_path = tmp_dir.join(format!("{key}.part"));

        let parent =
            std::path::absolute(dest.parent().unwrap()).context("resolve blob directory")?;
        let root = std::path::absolute(&self.root).context("resolve blob root")?;
        let temp = std::path::absolute(&tmp_dir).context("resolve temporary directory")?;
        let sync_parent = parent.clone();
        tokio::task::spawn_blocking(move || -> anyhow::Result<()> {
            // All local backend processes use this persistent lock, including independent
            // BlobStore instances. Never unlink it: that would split the lock domain.
            // A blocking task keeps both the lock and initialization alive across cancellation.
            let lock_path = Path::new("/tmp/tradocraft-blob-directories.lock");
            match std::fs::OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(lock_path)
            {
                Ok(file) => file.set_permissions(std::fs::Permissions::from_mode(0o644))?,
                Err(e) if e.kind() == ErrorKind::AlreadyExists => (),
                Err(e) => return Err(e.into()),
            }
            let lock = std::fs::File::open(lock_path)?;
            lock.lock()?;
            let mut dirs = vec![
                sync_parent.clone(),
                sync_parent.parent().unwrap().to_path_buf(),
                root,
            ];
            let mut cursor = sync_parent.as_path();
            while !cursor.try_exists()? {
                cursor = cursor.parent().context("blob directory has no parent")?;
                dirs.push(cursor.to_path_buf());
            }
            std::fs::create_dir_all(&sync_parent)?;
            std::fs::create_dir_all(&temp)?;
            // Both shard levels are always synchronized. Root ancestors created under
            // the lock are durable before another writer can observe them as existing.
            for dir in dirs {
                std::fs::File::open(dir)?.sync_all()?;
            }
            std::fs::File::open(temp)?.sync_all()?;
            Ok(())
        })
        .await
        .context("initialize blob directories task")??;

        if let Err(e) = tokio::fs::write(&tmp_path, bytes).await {
            let _ = tokio::fs::remove_file(&tmp_path).await;
            return Err(anyhow::Error::from(e)
                .context(format!("write blob temp file {}", tmp_path.display()))
                .into());
        }
        if let Err(e) = async {
            tokio::fs::OpenOptions::new()
                .write(true)
                .open(&tmp_path)
                .await?
                .sync_all()
                .await
        }
        .await
        {
            let _ = tokio::fs::remove_file(&tmp_path).await;
            return Err(anyhow::Error::from(e).context("sync blob payload").into());
        }
        if let Err(e) = tokio::fs::rename(&tmp_path, &dest).await {
            let _ = tokio::fs::remove_file(&tmp_path).await;
            return Err(anyhow::Error::from(e)
                .context(format!("rename blob into {}", dest.display()))
                .into());
        }
        // Persist the rename; directory creation was synchronized under the lock above.
        tokio::fs::File::open(&parent)
            .await
            .context("open blob directory")?
            .sync_all()
            .await
            .context("sync blob directory")?;
        tokio::fs::File::open(&tmp_dir)
            .await
            .context("open temporary directory")?
            .sync_all()
            .await
            .context("sync temporary directory")?;
        Ok(key)
    }

    /// Reads the blob for `key`, returning `AppError::NotFound("file")` if missing.
    pub async fn get(&self, key: &str) -> AppResult<Vec<u8>> {
        let path = self.path_for(key)?;
        match tokio::fs::read(&path).await {
            Ok(bytes) => Ok(bytes),
            Err(e) if e.kind() == ErrorKind::NotFound => Err(AppError::NotFound("file")),
            Err(e) => Err(anyhow::Error::from(e)
                .context(format!("read blob {}", path.display()))
                .into()),
        }
    }

    /// Deletes the blob for `key` if it exists (idempotent).
    pub async fn delete(&self, key: &str) -> AppResult<()> {
        let path = self.path_for(key)?;
        match tokio::fs::remove_file(&path).await {
            Ok(()) => Ok(()),
            Err(e) if e.kind() == ErrorKind::NotFound => Ok(()),
            Err(e) => Err(anyhow::Error::from(e)
                .context(format!("delete blob {}", path.display()))
                .into()),
        }
    }

    /// Removes unreferenced files (and stale `.tmp` files) older than `min_age`.
    pub async fn sweep_orphans(&self, db: &PgPool, min_age: Duration) -> anyhow::Result<usize> {
        // Ingest holds the shared transaction lock until its references commit or roll back.
        let mut tx = db.begin().await?;
        let locked: bool = sqlx::query_scalar("SELECT pg_try_advisory_xact_lock(743902104)")
            .fetch_one(&mut *tx)
            .await?;
        if !locked {
            return Ok(0);
        }
        let exists = tokio::fs::try_exists(&self.root).await?;
        if !exists {
            return Ok(0);
        }

        let cutoff = SystemTime::now()
            .checked_sub(min_age)
            .unwrap_or(SystemTime::UNIX_EPOCH);

        // Clean stale .tmp/*.part files first.
        let tmp_dir = self.root.join(".tmp");
        if tokio::fs::try_exists(&tmp_dir).await? {
            let mut rd = tokio::fs::read_dir(&tmp_dir).await?;
            while let Some(entry) = rd.next_entry().await? {
                if let Ok(meta) = entry.metadata().await {
                    if meta.is_file() && meta.modified().map(|m| m < cutoff).unwrap_or(false) {
                        let _ = tokio::fs::remove_file(entry.path()).await;
                    }
                }
            }
        }

        // Collect candidate keys older than `cutoff`.
        let mut candidates: Vec<(String, PathBuf)> = Vec::new();
        let mut l1 = tokio::fs::read_dir(&self.root).await?;
        while let Some(e1) = l1.next_entry().await? {
            if e1.file_name() == ".tmp" {
                continue;
            }
            if !e1.file_type().await?.is_dir() {
                continue;
            }
            let mut l2 = tokio::fs::read_dir(e1.path()).await?;
            while let Some(e2) = l2.next_entry().await? {
                if !e2.file_type().await?.is_dir() {
                    continue;
                }
                let mut l3 = tokio::fs::read_dir(e2.path()).await?;
                while let Some(e3) = l3.next_entry().await? {
                    let meta = match e3.metadata().await {
                        Ok(m) if m.is_file() => m,
                        _ => continue,
                    };
                    if !meta.modified().map(|m| m < cutoff).unwrap_or(false) {
                        continue;
                    }
                    let name = e3.file_name().to_string_lossy().into_owned();
                    if Uuid::parse_str(&name).is_ok() {
                        candidates.push((name, e3.path()));
                    }
                }
            }
        }

        if candidates.is_empty() {
            return Ok(0);
        }

        let keys: Vec<String> = candidates.iter().map(|(k, _)| k.clone()).collect();
        let live: HashSet<String> = sqlx::query_scalar(
            "SELECT storage_key FROM core.files WHERE storage_key = ANY($1)
             UNION
             SELECT storage_key FROM core.import_files WHERE storage_key = ANY($1)
             UNION
             SELECT attachment_storage_key FROM core.mail_outbox WHERE attachment_storage_key = ANY($1)
             UNION
             SELECT raw_message_storage_key FROM helpdesk.articles WHERE raw_message_storage_key = ANY($1)",
        )
        .bind(&keys)
        .fetch_all(&mut *tx)
        .await?
        .into_iter()
        .collect();

        let mut removed = 0usize;
        for (key, path) in candidates {
            if !live.contains(&key) && tokio::fs::remove_file(&path).await.is_ok() {
                removed += 1;
            }
        }
        Ok(removed)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn put_get_delete_roundtrip() {
        let store = BlobStore::temp_for_tests();
        let key = store.put(b"hello world").await.unwrap();
        assert_eq!(store.get(&key).await.unwrap(), b"hello world");
        store.delete(&key).await.unwrap();
        assert!(matches!(
            store.get(&key).await,
            Err(AppError::NotFound("file"))
        ));
        // Idempotent delete
        store.delete(&key).await.unwrap();
        let _ = std::fs::remove_dir_all(store.root());
    }

    #[tokio::test]
    async fn independent_writers_initialize_nested_root() {
        let base = BlobStore::temp_for_tests();
        let root = base.root().join("new/ancestors/files");
        let mut tasks = Vec::new();
        for _ in 0..16 {
            let store = BlobStore::new(root.clone());
            tasks.push(tokio::spawn(async move {
                store.put(b"concurrent").await.unwrap()
            }));
        }
        let store = BlobStore::new(root);
        for task in tasks {
            assert_eq!(
                store.get(&task.await.unwrap()).await.unwrap(),
                b"concurrent"
            );
        }
        std::fs::remove_dir_all(base.root()).unwrap();
    }

    #[tokio::test]
    async fn rejects_traversal_key() {
        let store = BlobStore::temp_for_tests();
        let err = store.get("../etc/passwd").await.unwrap_err();
        assert!(matches!(err, AppError::Internal(_)));
        let _ = std::fs::remove_dir_all(store.root());
    }
}
