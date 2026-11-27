//! What an entity supplies to the shared import engine (ADR 0067 section 1).
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
#[schema(as = ImportColumn)]
pub struct Column {
    /// The column name; for a per-language family the prefix (`name` for `name_nl`, `name_fr`).
    pub name: &'static str,
    pub kind: ColumnKind,
    /// Must have a value when the row creates a record (the key column is always required in the
    /// file itself).
    pub required: bool,
    /// A family of columns `<name>_<language>`, one per ISO 639-1 language code (`name_nl`,
    /// `name_fr`); a file has any number of them.
    pub per_language: bool,
}

impl Column {
    pub const fn new(name: &'static str, kind: ColumnKind, required: bool) -> Self {
        Column {
            name,
            kind,
            required,
            per_language: false,
        }
    }

    /// A per-language family `<prefix>_<language>`; never required.
    pub const fn per_language(prefix: &'static str, kind: ColumnKind) -> Self {
        Column {
            name: prefix,
            kind,
            required: false,
            per_language: true,
        }
    }

    /// The name a file is bound against: the name, or `<prefix>_*` for a family.
    pub fn field(&self) -> String {
        if self.per_language {
            format!("{}{FAMILY_SUFFIX}", self.name)
        } else {
            self.name.to_string()
        }
    }
}

/// The suffix that marks a per-language column family in the list of known fields a file is
/// bound against: `name_*` stands for `name_nl`, `name_fr`, ... (see [`Column::per_language`]).
pub const FAMILY_SUFFIX: &str = "_*";

/// The language code of `field` when it belongs to the family `prefix`: `name_fr` -> `fr` for
/// `name`. The code must be an ISO 639-1 code ([`crate::language::is_iso_639_1`]).
pub fn family_language<'a>(field: &'a str, prefix: &str) -> Option<&'a str> {
    let code = field.strip_prefix(prefix)?.strip_prefix('_')?;
    crate::language::is_iso_639_1(code).then_some(code)
}

/// Whether `field` is one of `known`: equal to a name, or a member of a family `prefix_*`.
pub fn is_known_field(known: &[&str], field: &str) -> bool {
    known.iter().any(|k| match k.strip_suffix(FAMILY_SUFFIX) {
        Some(prefix) => family_language(field, prefix).is_some(),
        None => *k == field,
    })
}

/// The languages of the family `prefix` among `columns` (bound field names), sorted.
pub fn family_languages(columns: &[String], prefix: &str) -> Vec<String> {
    let mut languages: Vec<String> = columns
        .iter()
        .filter_map(|c| family_language(c, prefix))
        .map(str::to_string)
        .collect();
    languages.sort();
    languages.dedup();
    languages
}

impl ExportTable {
    /// The rows of an entity whose columns are all fixed: the header is [`Importable::COLUMNS`].
    pub fn fixed<E: Importable>(rows: Vec<Vec<CellValue>>) -> Self {
        ExportTable {
            header: E::COLUMNS.iter().map(|c| c.name.to_string()).collect(),
            rows,
        }
    }
}

/// What an export writes: the header (fixed columns and, for a per-language family, one column
/// per language that occurs in the data) and the rows as typed cells in header order.
#[derive(Debug, Clone, PartialEq)]
pub struct ExportTable {
    pub header: Vec<String>,
    pub rows: Vec<Vec<CellValue>>,
}

/// One audit event of an imported record: by default `created`/`updated` of the entity itself,
/// see [`Importable::audit_event`].
#[derive(Debug, Clone, PartialEq)]
pub struct AuditEvent {
    pub entity: &'static str,
    pub id: Uuid,
    pub action: &'static str,
    /// Fields of `data`; the engine adds `source` and `import_job`.
    pub data: serde_json::Map<String, serde_json::Value>,
}

/// The serialisable description of an importable entity: what a later admin endpoint lists.
#[derive(Debug, Clone, Serialize, ToSchema, PartialEq, Eq)]
pub struct ImportDescription {
    /// Stable key of the entity (`customers`, `products`).
    pub key: String,
    /// Name of the entity in audit events (`customer`, `product`).
    pub audit_entity: String,
    /// The first (for most entities the only) column of the key; upserts match on the key.
    pub key_column: String,
    /// The columns that together identify a record, e.g. `product_code`, `zone`, `valid_from`.
    pub key_columns: Vec<String>,
    /// File stem of an export and name of its sheet.
    pub file_stem: String,
    pub columns: Vec<Column>,
}

/// Joins the parts of a key of several columns (see [`Importable::KEY_COLUMNS`]); a unit
/// separator, which no trimmed cell value of a key holds in practice.
pub const KEY_SEPARATOR: char = '\u{1f}';

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
    /// The columns, in export order (a per-language family stands for its columns).
    const COLUMNS: &'static [Column];
    /// The column that identifies a record.
    const KEY_COLUMN: &'static str = "code";
    /// The columns that together identify a record; the engine joins their trimmed values with
    /// [`KEY_SEPARATOR`] into the key passed to [`Importable::load`] and
    /// [`Importable::plan_row`]. One column ([`Importable::KEY_COLUMN`]) unless an entity says
    /// otherwise.
    const KEY_COLUMNS: &'static [&'static str] = &[Self::KEY_COLUMN];

    /// The audit event of a written record (`id` is the record's id, `key` its key). By default
    /// `created` (with the key column) or `updated` of [`Importable::AUDIT_ENTITY`]; an entity whose
    /// manual edits are audited on another record (a price on its product) says so here.
    fn audit_event(id: Uuid, key: &str, _change: &Self::Change, created: bool) -> AuditEvent {
        let mut data = serde_json::Map::new();
        if created {
            data.insert(Self::KEY_COLUMN.to_string(), key.into());
        }
        AuditEvent {
            entity: Self::AUDIT_ENTITY,
            id,
            action: if created { "created" } else { "updated" },
            data,
        }
    }

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

    /// All records of the active company, ordered by key: the header and the typed cells
    /// ([`ExportTable::fixed`] for an entity without per-language columns).
    fn export(
        pool: &PgPool,
        user: &CurrentUser,
    ) -> impl Future<Output = AppResult<ExportTable>> + Send;

    /// The description of the entity.
    fn describe() -> ImportDescription {
        ImportDescription {
            key: Self::KEY.to_string(),
            audit_entity: Self::AUDIT_ENTITY.to_string(),
            key_column: Self::KEY_COLUMNS[0].to_string(),
            key_columns: Self::KEY_COLUMNS.iter().map(|c| c.to_string()).collect(),
            file_stem: Self::FILE_STEM.to_string(),
            columns: Self::COLUMNS.to_vec(),
        }
    }
}
