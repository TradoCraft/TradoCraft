//! A type-erased handle on an [`Importable`]: a registry and a background worker call entities
//! without knowing their types.
//!
//! ```ignore
//! let entity = tradocraft_crm::customers_import();
//! entity.require_write(&user)?;
//! let report = entity.run(&pool, &user, &table, &RunOptions::new(format)).await?;
//! let (header, rows) = (entity.header(), entity.export(&pool, &user).await?);
//! ```

use std::future::Future;
use std::pin::Pin;

use sqlx::PgPool;

use crate::auth::{CurrentUser, Permission};
use crate::csv_io::ImportReport;
use crate::error::AppResult;
use crate::import::engine::{self, RunOptions};
use crate::import::importable::{ImportDescription, Importable};
use crate::import::{CellValue, Table};

/// A boxed, sendable future.
pub type BoxFuture<'a, T> = Pin<Box<dyn Future<Output = T> + Send + 'a>>;

type RunFn = for<'a> fn(
    &'a PgPool,
    &'a CurrentUser,
    &'a Table,
    &'a RunOptions<'a>,
) -> BoxFuture<'a, AppResult<ImportReport>>;

type ExportFn =
    for<'a> fn(&'a PgPool, &'a CurrentUser) -> BoxFuture<'a, AppResult<Vec<Vec<CellValue>>>>;

fn run_erased<'a, E: Importable>(
    pool: &'a PgPool,
    user: &'a CurrentUser,
    table: &'a Table,
    options: &'a RunOptions<'a>,
) -> BoxFuture<'a, AppResult<ImportReport>> {
    Box::pin(engine::run_import::<E>(pool, user, table, options))
}

fn export_erased<'a, E: Importable>(
    pool: &'a PgPool,
    user: &'a CurrentUser,
) -> BoxFuture<'a, AppResult<Vec<Vec<CellValue>>>> {
    Box::pin(engine::export_rows::<E>(pool, user))
}

/// One importable entity, whatever its type: its description, its permissions and function
/// pointers to the engine instantiated for it. Build it with [`ImportEntity::of`].
#[derive(Clone)]
pub struct ImportEntity {
    description: ImportDescription,
    read: Permission,
    write: Permission,
    run: RunFn,
    export: ExportFn,
}

impl ImportEntity {
    /// The handle of the entity `E`.
    pub fn of<E: Importable>() -> Self {
        ImportEntity {
            description: E::describe(),
            read: E::READ,
            write: E::WRITE,
            run: run_erased::<E>,
            export: export_erased::<E>,
        }
    }

    /// The entity's key, columns and names.
    pub fn describe(&self) -> &ImportDescription {
        &self.description
    }

    /// The column names, in export order.
    pub fn header(&self) -> Vec<&str> {
        self.description.columns.iter().map(|c| c.name).collect()
    }

    /// Needed to export the entity.
    pub fn read_permission(&self) -> Permission {
        self.read
    }

    /// Needed to import the entity.
    pub fn write_permission(&self) -> Permission {
        self.write
    }

    /// Runs an import of the bound `table` as `user` ([`engine::run_import`]). The caller checks
    /// the permission first (see [`ImportEntity::write_permission`]).
    pub async fn run(
        &self,
        pool: &PgPool,
        user: &CurrentUser,
        table: &Table,
        options: &RunOptions<'_>,
    ) -> AppResult<ImportReport> {
        (self.run)(pool, user, table, options).await
    }

    /// The rows of an export as typed cells in [`ImportEntity::header`] order. Checks the read
    /// permission of `user`.
    pub async fn export(
        &self,
        pool: &PgPool,
        user: &CurrentUser,
    ) -> AppResult<Vec<Vec<CellValue>>> {
        (self.export)(pool, user).await
    }
}

impl std::fmt::Debug for ImportEntity {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ImportEntity")
            .field("key", &self.description.key)
            .finish()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::error::AppError;
    use crate::import::{Cells, Column, ColumnKind, Row};
    use sqlx::PgConnection;
    use uuid::Uuid;

    /// An entity that never touches a database: enough to check the description and the handle.
    struct Dummy;

    fn unsupported<T>() -> AppResult<T> {
        Err(AppError::Validation("not used".into()))
    }

    impl Importable for Dummy {
        type Stored = ();
        type Change = ();
        type Context = ();
        const KEY: &'static str = "dummies";
        const AUDIT_ENTITY: &'static str = "dummy";
        const READ: Permission = Permission::CustomersRead;
        const WRITE: Permission = Permission::CustomersWrite;
        const FILE_STEM: &'static str = "dummies";
        const COLUMNS: &'static [Column] = &[
            Column::new("code", ColumnKind::Code, true),
            Column::new("price", ColumnKind::Decimal, false),
        ];

        async fn context(_: &mut PgConnection, _: &CurrentUser, _: &Table) -> AppResult<()> {
            unsupported()
        }
        async fn load(
            _: &mut PgConnection,
            _: &CurrentUser,
            _: &[String],
        ) -> AppResult<Vec<(String, ())>> {
            unsupported()
        }
        fn stored_id(_: &()) -> Uuid {
            Uuid::nil()
        }
        async fn plan_row(
            _: &mut PgConnection,
            _: &CurrentUser,
            _: &mut (),
            _: &str,
            _: Option<&()>,
            _: &Row,
            _: &mut Cells<'_>,
        ) -> AppResult<()> {
            unsupported()
        }
        fn unchanged(_: &(), _: &()) -> bool {
            false
        }
        async fn create(_: &mut PgConnection, _: &CurrentUser, _: Uuid, _: &()) -> AppResult<()> {
            unsupported()
        }
        async fn update(_: &mut PgConnection, _: &CurrentUser, _: Uuid, _: &()) -> AppResult<()> {
            unsupported()
        }
        async fn export(_: &PgPool, _: &CurrentUser) -> AppResult<Vec<Vec<CellValue>>> {
            unsupported()
        }
    }

    #[test]
    fn the_handle_describes_the_entity() {
        let entity = ImportEntity::of::<Dummy>();
        assert_eq!(entity.header(), ["code", "price"]);
        assert_eq!(entity.read_permission(), Permission::CustomersRead);
        assert_eq!(entity.write_permission(), Permission::CustomersWrite);
        assert_eq!(
            serde_json::to_value(entity.describe()).unwrap(),
            serde_json::json!({
                "key": "dummies",
                "audit_entity": "dummy",
                "key_column": "code",
                "file_stem": "dummies",
                "columns": [
                    {"name": "code", "kind": "code", "required": true},
                    {"name": "price", "kind": "decimal", "required": false},
                ],
            })
        );
        assert_eq!(format!("{entity:?}"), "ImportEntity { key: \"dummies\" }");
    }
}
