//! Filesystem blob storage for uploaded files, import spreadsheets, mail attachments and raw
//! incoming e-mails.
//!
//! Blobs are stored under `FILE_STORAGE_DIR` (default `data/files`) in a two-level sharded
//! directory layout (`<aa>/<bb>/<uuid>`), written atomically via `.tmp/<uuid>.part` and `rename`.
//! Storage keys are always UUIDv7 strings validated on every read/delete, so user-supplied paths
//! can never escape the root directory.
//! On Unix, committed writes sync the payload and directory entries. On Windows, the payload
//! is flushed and published with a write-through rename. The demo uses a private data directory.

use std::collections::HashSet;
use std::io::ErrorKind;
#[cfg(unix)]
use std::os::unix::fs::{DirBuilderExt, OpenOptionsExt};
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

pub(crate) struct StagedBlob {
    pub(crate) key: String,
    dest: PathBuf,
    #[cfg(unix)]
    parent: PathBuf,
    #[cfg(unix)]
    tmp_dir: PathBuf,
    pub(crate) tmp_path: PathBuf,
}

impl StagedBlob {
    pub(crate) async fn abort(self) {
        let _ = tokio::fs::remove_file(&self.tmp_path).await;
    }

    pub(crate) async fn commit(self) -> AppResult<String> {
        if let Err(e) = async {
            tokio::fs::OpenOptions::new()
                .write(true)
                .open(&self.tmp_path)
                .await?
                .sync_all()
                .await
        }
        .await
        {
            let _ = tokio::fs::remove_file(&self.tmp_path).await;
            return Err(anyhow::Error::from(e).context("sync blob payload").into());
        }
        if let Err(e) = publish_blob(&self.tmp_path, &self.dest).await {
            let _ = tokio::fs::remove_file(&self.tmp_path).await;
            return Err(anyhow::Error::from(e)
                .context(format!("rename blob into {}", self.dest.display()))
                .into());
        }
        #[cfg(unix)]
        for dir in [&self.parent, &self.tmp_dir] {
            tokio::fs::File::open(dir)
                .await
                .context("open blob directory")?
                .sync_all()
                .await
                .context("sync blob directory")?;
        }
        Ok(self.key)
    }
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
        let writer = self.begin_write().await?;
        if let Err(e) = tokio::fs::write(&writer.tmp_path, bytes).await {
            let _ = tokio::fs::remove_file(&writer.tmp_path).await;
            return Err(anyhow::Error::from(e)
                .context(format!(
                    "write blob temp file {}",
                    writer.tmp_path.display()
                ))
                .into());
        }
        writer.commit().await
    }

    /// Prepares the shard and temporary directories and returns a staged writer for a new blob.
    pub(crate) async fn begin_write(&self) -> AppResult<StagedBlob> {
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
            // Keep shard creation serialized, including when the root is new.
            let _lock = lock_storage_root(&root)?;
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
                sync_directory(dir)?;
            }
            sync_directory(temp)?;
            Ok(())
        })
        .await
        .context("initialize blob directories task")??;

        Ok(StagedBlob {
            key,
            dest,
            #[cfg(unix)]
            parent,
            #[cfg(unix)]
            tmp_dir,
            tmp_path,
        })
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
            if e1.file_name() == ".tmp" || e1.file_name() == ".locks" {
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

#[cfg(not(windows))]
async fn publish_blob(source: &Path, dest: &Path) -> std::io::Result<()> {
    tokio::fs::rename(source, dest).await
}

#[cfg(windows)]
async fn publish_blob(source: &Path, dest: &Path) -> std::io::Result<()> {
    use std::os::windows::ffi::OsStrExt;

    #[link(name = "kernel32")]
    extern "system" {
        fn MoveFileExW(source: *const u16, dest: *const u16, flags: u32) -> i32;
    }

    const MOVEFILE_WRITE_THROUGH: u32 = 0x8;
    let source = source.to_owned();
    let dest = dest.to_owned();
    tokio::task::spawn_blocking(move || {
        fn wide_path(path: &Path) -> std::io::Result<Vec<u16>> {
            // Canonicalizing an existing directory gives Windows' verbatim absolute
            // form. The destination file itself does not exist yet.
            let parent = path.parent().ok_or(std::io::ErrorKind::InvalidInput)?;
            let name = path.file_name().ok_or(std::io::ErrorKind::InvalidInput)?;
            Ok(parent
                .canonicalize()?
                .join(name)
                .as_os_str()
                .encode_wide()
                .chain([0])
                .collect())
        }
        let source = wide_path(&source)?;
        let dest = wide_path(&dest)?;
        // Both buffers are NUL-terminated and live until Windows returns.
        if unsafe { MoveFileExW(source.as_ptr(), dest.as_ptr(), MOVEFILE_WRITE_THROUGH) } == 0 {
            return Err(std::io::Error::last_os_error());
        }
        Ok(())
    })
    .await
    .map_err(std::io::Error::other)?
}

fn private_dir_builder() -> std::fs::DirBuilder {
    let mut builder = std::fs::DirBuilder::new();
    #[cfg(unix)]
    builder.mode(0o700);
    #[cfg(windows)]
    builder.recursive(false);
    builder
}

#[cfg(unix)]
fn sync_directory(path: impl AsRef<Path>) -> std::io::Result<()> {
    std::fs::File::open(path)?.sync_all()
}

#[cfg(windows)]
fn sync_directory(_path: impl AsRef<Path>) -> std::io::Result<()> {
    // Windows does not offer Unix directory fsync. Publication uses MoveFileExW above.
    Ok(())
}

/// Locks initialization in a private directory within the configured storage root.
fn lock_existing(root: &Path) -> anyhow::Result<std::fs::File> {
    let dir = root.join(".locks");
    match private_dir_builder().create(&dir) {
        Ok(()) => (),
        Err(e) if e.kind() == ErrorKind::AlreadyExists => (),
        Err(e) => return Err(e.into()),
    }
    let mut options = std::fs::OpenOptions::new();
    options.read(true).write(true).create(true).truncate(false);
    #[cfg(unix)]
    options.mode(0o600);
    let lock = options.open(dir.join("directories.lock"))?;
    lock.lock()?;
    sync_directory(root)?;
    Ok(lock)
}

#[cfg(windows)]
fn lock_storage_root(root: &Path) -> anyhow::Result<std::fs::File> {
    std::fs::create_dir_all(root)?;
    lock_existing(root)
}

#[cfg(unix)]
fn lock_storage_root(root: &Path) -> anyhow::Result<std::fs::File> {
    if root.try_exists()? {
        return lock_existing(root);
    }
    let mut missing = vec![root.to_path_buf()];
    let mut ancestor = root.parent().context("storage root has no parent")?;
    while !ancestor.try_exists()? {
        missing.push(ancestor.to_path_buf());
        ancestor = ancestor.parent().context("storage root has no ancestor")?;
    }
    let top = missing.last().unwrap();
    let staged = ancestor.join(format!(".blob-init-{}", new_id()));
    private_dir_builder().create(&staged)?;
    let result = (|| -> anyhow::Result<std::fs::File> {
        let staged_root = staged.join(root.strip_prefix(top)?);
        private_dir_builder().recursive(true).create(&staged_root)?;
        // The lock stays held across publication and fsync of the existing ancestor.
        let lock = lock_existing(&staged_root)?;
        let mut cursor = staged_root.as_path();
        loop {
            sync_directory(cursor)?;
            if cursor == staged {
                break;
            }
            cursor = cursor.parent().unwrap();
        }
        match std::fs::rename(&staged, top) {
            Ok(()) => {
                sync_directory(ancestor)?;
                Ok(lock)
            }
            Err(e)
                if matches!(
                    e.kind(),
                    ErrorKind::AlreadyExists | ErrorKind::DirectoryNotEmpty
                ) =>
            {
                // Another writer published a complete initialized tree first.
                drop(lock);
                std::fs::remove_dir_all(&staged)?;
                lock_storage_root(root)
            }
            Err(e) => Err(e.into()),
        }
    })();
    if result.is_err() {
        let _ = std::fs::remove_dir_all(&staged);
    }
    result
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

    #[cfg(windows)]
    #[tokio::test]
    async fn publishes_under_an_extended_length_path() {
        let base = BlobStore::temp_for_tests();
        let root = base.root().join("a".repeat(120)).join("b".repeat(120));
        let store = BlobStore::new(root);
        let key = store.put(b"long path").await.unwrap();
        assert_eq!(store.get(&key).await.unwrap(), b"long path");
        std::fs::remove_dir_all(base.root()).unwrap();
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
    async fn lock_is_private_and_scoped_to_storage_root() {
        let store = BlobStore::temp_for_tests();
        store.put(b"initialize").await.unwrap();
        let lock_dir = store.root().join(".locks");
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            assert_eq!(
                std::fs::metadata(&lock_dir).unwrap().permissions().mode() & 0o077,
                0
            );
        }
        let lock_path = lock_dir.join("directories.lock");
        let held = std::fs::OpenOptions::new()
            .read(true)
            .write(true)
            .open(&lock_path)
            .unwrap();
        held.lock().unwrap();
        let writing = {
            let same_root = BlobStore::new(store.root());
            tokio::spawn(async move { same_root.put(b"wait for lock").await })
        };
        // A different root must progress while this root is locked.
        let other = BlobStore::temp_for_tests();
        tokio::time::timeout(Duration::from_secs(5), other.put(b"independent"))
            .await
            .unwrap()
            .unwrap();
        assert!(!writing.is_finished());
        drop(held);
        tokio::time::timeout(Duration::from_secs(5), writing)
            .await
            .unwrap()
            .unwrap()
            .unwrap();
        std::fs::remove_dir_all(store.root()).unwrap();
        std::fs::remove_dir_all(other.root()).unwrap();
    }

    #[tokio::test]
    async fn rejects_traversal_key() {
        let store = BlobStore::temp_for_tests();
        let err = store.get("../etc/passwd").await.unwrap_err();
        assert!(matches!(err, AppError::Internal(_)));
        let _ = std::fs::remove_dir_all(store.root());
    }
}
