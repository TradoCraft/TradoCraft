//! What an entity supplies to the shared import engine (ADR 0064 section 1).
//!
//! The engine ([`super::engine`]) does everything that is the same for every entity: header
//! binding, the key column, duplicate keys, locking the named records, classifying rows as create,
//! update or unchanged, the dry run, the write loop with its audit events, replanning and the
//! report. An entity implements [`Importable`] with only what is its own.

use std::future::Future;

use serde::Serialize;
use sqlx::PgConnection;
use utoipa::ToSchema;
use uuid::Uuid;

use crate::auth::{CurrentUser, Permission};
use crate::error::AppResult;
use crate::import::{CellValue, Cells, Row, Table};
use sqlx::PgPool;

/// What kind of value a column holds. It tells a person (and a mapping screen) how a cell is read
/// and tells an export how to type the cell: text columns are always text cells, so `00123` and
/// `=x` survive a spreadsheet.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum ColumnKind {
    /// Free text, kept exactly as written.
    Text,
    /// A code or keyword: surrounding spaces are removed.
    Code,
    /// A decimal number (`.` or `,` as decimal mark in text cells).
    Decimal,
    /// A whole number.
    Integer,
    /// `true`/`false` (also `1`/`0`, `yes`/`no`).
    Boolean,
}

/// One column of an entity's import file and export, in export order.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, ToSchema)]
pub struct Column {
    pub name: &'static str,
    pub kind: ColumnKind,
    /// Must have a value when the row creates a record (the key column is always required in the
    /// file itself).
    pub required: bool,
}

impl Column {
    pub const fn new(name: &'static str, kind: ColumnKind, required: bool) -> Self {
        Column {
            name,
            kind,
            required,
        }
    }
}

/// The serialisable description of an importable entity: what a later admin endpoint lists.
#[derive(Debug, Clone, Serialize, ToSchema, PartialEq, Eq)]
pub struct ImportDescription {
    /// Stable key of the entity (`customers`, `products`).
    pub key: String,
    /// Name of the entity in audit events (`customer`, `product`).
    pub audit_entity: String,
    /// The column that identifies a record; upserts match on it.
    pub key_column: String,
    /// File stem of an export and name of its sheet.
    pub file_stem: String,
    pub columns: Vec<Column>,
}

/// A step of an import that a progress sink is told about.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Phase {
    /// Rows are being checked.
    Validating,
    /// The checked changes are being written.
    Writing,
}

impl Phase {
    /// The name a job stores.
    pub fn as_str(self) -> &'static str {
        match self {
            Phase::Validating => "validating",
            Phase::Writing => "writing",
        }
    }
}

/// Receives the progress of an import: the phase and how many rows of it are done. It is called
/// from inside the import and must be quick and must not use the import's transaction (a job
/// writes it on a separate connection, e.g. by sending it on a channel).
pub trait Progress: Send + Sync {
    fn report(&self, phase: Phase, processed: usize);
}

/// The progress sink that ignores everything.
#[derive(Debug, Default, Clone, Copy)]
pub struct NoProgress;

impl Progress for NoProgress {
    fn report(&self, _phase: Phase, _processed: usize) {}
}

/// An entity that can be imported and exported through the shared engine.
///
/// The futures are `Send` so that a background worker can run an import. The engine calls the
/// methods in this order for one attempt: [`load`](Importable::load) (locks the named records),
/// [`context`](Importable::context), [`plan_row`](Importable::plan_row) per row, and, when the
/// plan is clean and no dry run, [`create`](Importable::create) / [`update`](Importable::update).
pub trait Importable: Send + Sync + 'static {
    /// A stored record, as loaded for comparison.
    type Stored: Send + Sync;
    /// What one valid row would write.
    type Change: Send + Sync;
    /// Per-run state: lookups loaded once and cross-row state (for example barcodes seen so far).
    type Context: Send;

    /// Stable key of the entity.
    const KEY: &'static str;
    /// Entity name in audit events.
    const AUDIT_ENTITY: &'static str;
    /// Needed to export.
    const READ: Permission;
    /// Needed to import.
    const WRITE: Permission;
    /// File stem of an export and name of its sheet.
    const FILE_STEM: &'static str;
    /// The columns, in export order.
    const COLUMNS: &'static [Column];
    /// The column that identifies a record.
    const KEY_COLUMN: &'static str = "code";

    /// Loads the lookups the rows need (and the state shared between rows) once per attempt.
    fn context(
        conn: &mut PgConnection,
        user: &CurrentUser,
        table: &Table,
    ) -> impl Future<Output = AppResult<Self::Context>> + Send;

    /// Reads and locks (`FOR UPDATE`) the stored records named by `keys` in one statement, so a
    /// concurrent edit cannot slip in between the read and the lock. Returns them with their key.
    fn load(
        conn: &mut PgConnection,
        user: &CurrentUser,
        keys: &[String],
    ) -> impl Future<Output = AppResult<Vec<(String, Self::Stored)>>> + Send;

    /// The primary key of a stored record.
    fn stored_id(stored: &Self::Stored) -> Uuid;

    /// Turns one row into the change it would write: start from the stored record (or the
    /// defaults), overlay the cells, run the entity's checks. Problems are recorded on `cells`;
    /// the engine drops the row when any were added. `key` is the trimmed key and is not
    /// duplicated in the file.
    fn plan_row(
        conn: &mut PgConnection,
        user: &CurrentUser,
        context: &mut Self::Context,
        key: &str,
        current: Option<&Self::Stored>,
        row: &Row,
        cells: &mut Cells<'_>,
    ) -> impl Future<Output = AppResult<Self::Change>> + Send;

    /// Whether the stored record already equals what the change would write.
    fn unchanged(stored: &Self::Stored, change: &Self::Change) -> bool;

    /// Creates the record with id `id`.
    fn create(
        conn: &mut PgConnection,
        user: &CurrentUser,
        id: Uuid,
        change: &Self::Change,
    ) -> impl Future<Output = AppResult<()>> + Send;

    /// Updates the stored record `id`.
    fn update(
        conn: &mut PgConnection,
        user: &CurrentUser,
        id: Uuid,
        change: &Self::Change,
    ) -> impl Future<Output = AppResult<()>> + Send;

    /// All records of the active company, ordered by key, as typed cells in [`Self::COLUMNS`]
    /// order.
    fn export(
        pool: &PgPool,
        user: &CurrentUser,
    ) -> impl Future<Output = AppResult<Vec<Vec<CellValue>>>> + Send;

    /// The description of the entity.
    fn describe() -> ImportDescription {
        ImportDescription {
            key: Self::KEY.to_string(),
            audit_entity: Self::AUDIT_ENTITY.to_string(),
            key_column: Self::KEY_COLUMN.to_string(),
            file_stem: Self::FILE_STEM.to_string(),
            columns: Self::COLUMNS.to_vec(),
        }
    }
}
