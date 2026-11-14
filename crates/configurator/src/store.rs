//! Storage of models, revisions and saved configurations (schema `configurator`), the catalogue
//! snapshot for the evaluator and the development demo.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection, PgExecutor};
use tradocraft_core::{new_id, AppError, AppResult};
use tradocraft_products::attributes::{catalog_snapshot, AttributeValue};
use utoipa::ToSchema;
use uuid::Uuid;

use crate::definition::{self, Definition, DefinitionError};
use crate::engine::{Catalog, CatalogProduct};
use crate::expr::Value;

/// The public demo definition, loaded by the development seed.
pub const DEMO_CONVEYOR_LINE: &str = include_str!("../../../seed/configurators/conveyor_line.json");

/// The `format` of an exported model.
pub const EXPORT_FORMAT: &str = "tradocraft.configurator";

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct ModelSummary {
    pub id: Uuid,
    pub code: String,
    pub name: String,
    pub description: String,
    pub product_id: Option<Uuid>,
    pub active: bool,
    /// Revision number of the active revision, if any.
    pub active_revision: Option<i32>,
    pub active_revision_id: Option<Uuid>,
    /// Revision number of the draft, if any.
    pub draft_revision: Option<i32>,
    pub draft_revision_id: Option<Uuid>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct RevisionSummary {
    pub id: Uuid,
    pub model_id: Uuid,
    pub revision: i32,
    /// draft | active | obsolete
    pub status: String,
    pub notes: String,
    pub created_at: DateTime<Utc>,
    pub activated_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct Model {
    pub id: Uuid,
    pub code: String,
    pub name: String,
    pub description: String,
    /// Names per language: `{"nl": {"label": "..."}}`.
    #[schema(value_type = Object)]
    pub translations: serde_json::Value,
    pub product_id: Option<Uuid>,
    pub active: bool,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    /// Newest first.
    pub revisions: Vec<RevisionSummary>,
}

#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct Revision {
    pub id: Uuid,
    pub model_id: Uuid,
    pub model_code: String,
    pub model_name: String,
    pub revision: i32,
    /// draft | active | obsolete
    pub status: String,
    pub notes: String,
    /// The definition document (ADR 0034).
    #[schema(value_type = Object)]
    pub definition: serde_json::Value,
    /// Problems that block activation; empty when the definition is valid.
    pub errors: Vec<DefinitionError>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub activated_at: Option<DateTime<Utc>>,
}

/// The model part of an export.
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct ExportedModel {
    pub code: String,
    pub name: String,
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    #[schema(value_type = Object)]
    pub translations: serde_json::Value,
}

/// A model with one revision's definition, as exported and imported (JSON file).
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct ModelExport {
    /// Always `tradocraft.configurator`.
    pub format: String,
    pub format_version: u32,
    pub model: ExportedModel,
    #[schema(value_type = Object)]
    pub definition: serde_json::Value,
}

#[derive(FromRow)]
struct ModelRow {
    id: Uuid,
    code: String,
    name: String,
    description: String,
    translations: serde_json::Value,
    product_id: Option<Uuid>,
    active: bool,
    created_at: DateTime<Utc>,
    updated_at: DateTime<Utc>,
}

#[derive(FromRow)]
pub(crate) struct RevisionRow {
    pub id: Uuid,
    pub model_id: Uuid,
    pub model_code: String,
    pub model_name: String,
    pub revision: i32,
    pub status: String,
    pub notes: String,
    pub definition: serde_json::Value,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub activated_at: Option<DateTime<Utc>>,
}

impl RevisionRow {
    /// The typed definition (stored revisions always parse; they were checked when saved).
    pub fn definition(&self) -> AppResult<Definition> {
        definition::from_json(&self.definition)
            .map_err(|e| AppError::Validation(format!("{}: {}", e.path, e.message)))
    }

    pub fn into_api(self) -> Revision {
        let errors = match definition::from_json(&self.definition) {
            Ok(d) => definition::validate(&d),
            Err(e) => vec![e],
        };
        Revision {
            id: self.id,
            model_id: self.model_id,
            model_code: self.model_code,
            model_name: self.model_name,
            revision: self.revision,
            status: self.status,
            notes: self.notes,
            definition: self.definition,
            errors,
            created_at: self.created_at,
            updated_at: self.updated_at,
            activated_at: self.activated_at,
        }
    }
}

pub async fn list_models<'e>(
    db: impl PgExecutor<'e>,
    company_id: Uuid,
) -> AppResult<Vec<ModelSummary>> {
    Ok(sqlx::query_as(
        "SELECT m.id, m.code, m.name, m.description, m.product_id, m.active,
                a.revision AS active_revision, a.id AS active_revision_id,
                d.revision AS draft_revision, d.id AS draft_revision_id, m.updated_at
         FROM configurator.models m
         LEFT JOIN configurator.model_revisions a ON a.model_id = m.id AND a.status = 'active'
         LEFT JOIN configurator.model_revisions d ON d.model_id = m.id AND d.status = 'draft'
         WHERE m.company_id = $1 ORDER BY m.code",
    )
    .bind(company_id)
    .fetch_all(db)
    .await?)
}

pub async fn load_model(
    conn: &mut PgConnection,
    company_id: Uuid,
    id: Uuid,
    lock: bool,
) -> AppResult<Model> {
    let sql = format!(
        "SELECT id, code, name, description, translations, product_id, active, created_at, updated_at
         FROM configurator.models WHERE id = $1 AND company_id = $2{}",
        if lock { " FOR UPDATE" } else { "" }
    );
    let m: ModelRow = sqlx::query_as(&sql)
        .bind(id)
        .bind(company_id)
        .fetch_optional(&mut *conn)
        .await?
        .ok_or(AppError::NotFound("configurator model"))?;
    let revisions: Vec<RevisionSummary> = sqlx::query_as(
        "SELECT id, model_id, revision, status, notes, created_at, activated_at
         FROM configurator.model_revisions WHERE model_id = $1 ORDER BY revision DESC",
    )
    .bind(id)
    .fetch_all(&mut *conn)
    .await?;
    Ok(Model {
        id: m.id,
        code: m.code,
        name: m.name,
        description: m.description,
        translations: m.translations,
        product_id: m.product_id,
        active: m.active,
        created_at: m.created_at,
        updated_at: m.updated_at,
        revisions,
    })
}

pub(crate) async fn load_revision(
    conn: &mut PgConnection,
    company_id: Uuid,
    id: Uuid,
    lock: bool,
) -> AppResult<RevisionRow> {
    let sql = format!(
        "SELECT r.id, r.model_id, m.code AS model_code, m.name AS model_name, r.revision, r.status,
                r.notes, r.definition, r.created_at, r.updated_at, r.activated_at
         FROM configurator.model_revisions r JOIN configurator.models m ON m.id = r.model_id
         WHERE r.id = $1 AND m.company_id = $2{}",
        if lock { " FOR UPDATE OF r" } else { "" }
    );
    sqlx::query_as(&sql)
        .bind(id)
        .bind(company_id)
        .fetch_optional(conn)
        .await?
        .ok_or(AppError::NotFound("configurator revision"))
}

/// Inserts a model (no revisions).
#[allow(clippy::too_many_arguments)]
pub async fn insert_model(
    conn: &mut PgConnection,
    company_id: Uuid,
    user_id: Option<Uuid>,
    code: &str,
    name: &str,
    description: &str,
    translations: &serde_json::Value,
    product_id: Option<Uuid>,
) -> AppResult<Uuid> {
    let code = code.trim();
    if code.is_empty() || code.chars().count() > 60 {
        return Err(AppError::Validation(
            "code is required (at most 60 characters)".into(),
        ));
    }
    if name.trim().is_empty() {
        return Err(AppError::Validation("name is required".into()));
    }
    let id = new_id();
    sqlx::query(
        "INSERT INTO configurator.models (id, company_id, code, name, description, translations, product_id, created_by)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)",
    )
    .bind(id)
    .bind(company_id)
    .bind(code)
    .bind(name.trim())
    .bind(description.trim())
    .bind(if translations.is_null() { serde_json::json!({}) } else { translations.clone() })
    .bind(product_id)
    .bind(user_id)
    .execute(conn)
    .await
    .map_err(|e| match AppError::from(e) {
        AppError::Conflict(_) => AppError::Conflict(format!("a configurator with code {code} already exists")),
        other => other,
    })?;
    Ok(id)
}

/// Inserts the next revision of a model as a draft. 409 if the model already has a draft.
pub async fn insert_draft(
    conn: &mut PgConnection,
    model_id: Uuid,
    user_id: Option<Uuid>,
    definition: &Definition,
    notes: &str,
) -> AppResult<(Uuid, i32)> {
    let has_draft: bool = sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM configurator.model_revisions WHERE model_id = $1 AND status = 'draft')",
    )
    .bind(model_id)
    .fetch_one(&mut *conn)
    .await?;
    if has_draft {
        return Err(AppError::Conflict(
            "this configurator already has a draft revision; edit or activate it first".into(),
        ));
    }
    let revision: i32 = sqlx::query_scalar(
        "SELECT coalesce(max(revision), 0) + 1 FROM configurator.model_revisions WHERE model_id = $1",
    )
    .bind(model_id)
    .fetch_one(&mut *conn)
    .await?;
    let id = new_id();
    sqlx::query(
        "INSERT INTO configurator.model_revisions (id, model_id, revision, definition, notes, created_by)
         VALUES ($1, $2, $3, $4, $5, $6)",
    )
    .bind(id)
    .bind(model_id)
    .bind(revision)
    .bind(serde_json::to_value(definition).map_err(|e| AppError::Internal(e.into()))?)
    .bind(notes.trim())
    .bind(user_id)
    .execute(&mut *conn)
    .await?;
    Ok((id, revision))
}

/// Makes a draft the active revision; the previous active one becomes obsolete.
pub async fn activate(conn: &mut PgConnection, model_id: Uuid, revision_id: Uuid) -> AppResult<()> {
    sqlx::query("UPDATE configurator.model_revisions SET status = 'obsolete' WHERE model_id = $1 AND status = 'active'")
        .bind(model_id)
        .execute(&mut *conn)
        .await?;
    sqlx::query(
        "UPDATE configurator.model_revisions SET status = 'active', activated_at = now(), updated_at = now() WHERE id = $1",
    )
    .bind(revision_id)
    .execute(&mut *conn)
    .await?;
    sqlx::query("UPDATE configurator.models SET updated_at = now() WHERE id = $1")
        .bind(model_id)
        .execute(&mut *conn)
        .await?;
    Ok(())
}

/// The catalogue snapshot the evaluator works with.
pub async fn load_catalog(conn: &mut sqlx::PgConnection) -> AppResult<Catalog> {
    let mut c = Catalog::default();
    for p in catalog_snapshot(conn).await? {
        c.add(CatalogProduct {
            id: Some(p.id),
            code: p.code,
            name: p.name,
            family: p.family_code,
            unit: p.unit,
            active: p.active,
            // Suitability ranges (ADR 0068) are not formula values: the evaluator ignores them.
            attributes: p
                .attributes
                .into_iter()
                .filter_map(|(k, v)| {
                    let value = match v {
                        AttributeValue::Number(d) => Value::Dec(d),
                        AttributeValue::Text(t) => Value::Str(t),
                        AttributeValue::Boolean(b) => Value::Bool(b),
                        AttributeValue::Range { .. } => return None,
                    };
                    Some((k, value))
                })
                .collect(),
        });
    }
    Ok(c)
}

/// Reads an export, checking the format; the definition must parse (it may still have errors).
pub fn parse_export(e: &ModelExport) -> AppResult<Definition> {
    if e.format != EXPORT_FORMAT {
        return Err(AppError::Validation(format!(
            "format must be {EXPORT_FORMAT}"
        )));
    }
    if e.format_version != 1 {
        return Err(AppError::Validation(format!(
            "unsupported format_version {}",
            e.format_version
        )));
    }
    definition::from_json(&e.definition)
        .map_err(|e| AppError::Validation(format!("{}: {}", e.path, e.message)))
}

/// Loads the demo configurator into a company as an active revision, unless a model with its
/// code exists. Used by the development seed.
pub async fn seed_demo(db: &sqlx::PgPool, company_id: Uuid) -> AppResult<bool> {
    let export: ModelExport =
        serde_json::from_str(DEMO_CONVEYOR_LINE).map_err(|e| AppError::Internal(e.into()))?;
    let def = parse_export(&export)?;
    let errors = definition::validate(&def);
    if !errors.is_empty() {
        return Err(AppError::Validation(format!(
            "the demo configurator is invalid: {errors:?}"
        )));
    }
    let mut tx = db.begin().await?;
    let exists: bool = sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM configurator.models WHERE company_id = $1 AND code = $2)",
    )
    .bind(company_id)
    .bind(&export.model.code)
    .fetch_one(&mut *tx)
    .await?;
    if exists {
        return Ok(false);
    }
    let m = &export.model;
    let model_id = insert_model(
        &mut tx,
        company_id,
        None,
        &m.code,
        &m.name,
        &m.description,
        &m.translations,
        None,
    )
    .await?;
    let (rev, _) = insert_draft(&mut tx, model_id, None, &def, "demo").await?;
    activate(&mut tx, model_id, rev).await?;
    tx.commit().await?;
    Ok(true)
}
