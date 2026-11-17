//! HTTP API of the configurator module (ADR 0034).
//!
//! * Models and revisions (`configurator.design` to change; `design` or `use` to read).
//! * `POST /configurator/expressions/check` for the formula editor.
//! * `POST /configurator/revisions/{id}/evaluate`: the only engine; the app calls it while the
//!   user types.
//! * Saved configurations and `POST /configurator/configurations/{id}/quote`
//!   (`configurator.use`; quoting also needs `quotations.write`).

use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::Json;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use tradocraft_core::{audit, new_id, AppError, AppResult, AppState, CurrentUser, Permission};
use tradocraft_sales::configured::{
    import, ConfiguredImportResult, ConfiguredLineInput, ConfiguredQuotationInput,
};
use tradocraft_sales::PercentBase;
use utoipa::{IntoParams, ToSchema};
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::compile::{compile, Compiled, ScopeKey};
use crate::definition::{self, Definition, DefinitionError, RuleScope};
use crate::engine::{evaluate, Evaluation, Inputs, Line};
use crate::expr::functions::{Signature, FUNCTIONS};
use crate::expr::{self, ExprError, OpenEnv, Template, Type, TypeEnv};
use crate::store::{self, Model, ModelExport, ModelSummary, Revision, EXPORT_FORMAT};

type ErrorBody = tradocraft_core::error::ErrorBody;

/// The `source` of quotations made from saved configurations.
pub const QUOTE_SOURCE: &str = "configurator";

fn require_read(user: &CurrentUser) -> AppResult<()> {
    if user.can(Permission::ConfiguratorDesign) {
        return Ok(());
    }
    user.require(Permission::ConfiguratorUse)
}

fn definition_errors(errors: &[DefinitionError]) -> AppError {
    let shown: Vec<String> = errors
        .iter()
        .take(10)
        .map(|e| format!("{}: {}", e.path, e.message))
        .collect();
    AppError::Validation(format!(
        "the definition has {} problem(s): {}",
        errors.len(),
        shown.join("; ")
    ))
}

fn compiled(def: &Definition) -> AppResult<Compiled> {
    compile(def).map_err(|e| definition_errors(&e))
}

// ---------------------------------------------------------------------------------------------
// Models and revisions
// ---------------------------------------------------------------------------------------------

#[derive(Debug, Deserialize, ToSchema)]
pub struct NewModelInput {
    pub code: String,
    pub name: String,
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    #[schema(value_type = Object)]
    pub translations: serde_json::Value,
    pub product_id: Option<Uuid>,
    /// The first draft's definition; an empty one when left out.
    #[serde(default)]
    #[schema(value_type = Option<Object>)]
    pub definition: Option<serde_json::Value>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct ModelUpdate {
    pub name: String,
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    #[schema(value_type = Object)]
    pub translations: serde_json::Value,
    pub product_id: Option<Uuid>,
    pub active: bool,
}

#[derive(Debug, Default, Deserialize, ToSchema)]
pub struct NewRevisionInput {
    /// A revision of the same model to copy; the active one when left out.
    pub copy_from: Option<Uuid>,
    #[serde(default)]
    pub notes: String,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct RevisionUpdate {
    #[schema(value_type = Object)]
    pub definition: serde_json::Value,
    pub notes: Option<String>,
}

fn parse_definition(v: &serde_json::Value) -> AppResult<Definition> {
    definition::from_json(v).map_err(|e| AppError::Validation(format!("{}: {}", e.path, e.message)))
}

/// The configurators of the company, with their active and draft revision.
#[utoipa::path(get, path = "/configurator/models", tag = "configurator",
    responses((status = 200, body = Vec<ModelSummary>), (status = 403, body = ErrorBody)))]
async fn list_models(
    State(state): State<AppState>,
    user: CurrentUser,
) -> AppResult<Json<Vec<ModelSummary>>> {
    require_read(&user)?;
    Ok(Json(store::list_models(&state.db, user.company_id).await?))
}

/// Creates a configurator with a first draft revision.
#[utoipa::path(post, path = "/configurator/models", tag = "configurator", request_body = NewModelInput,
    responses((status = 201, body = Model), (status = 403, body = ErrorBody), (status = 409, body = ErrorBody),
        (status = 422, body = ErrorBody)))]
async fn create_model(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<NewModelInput>,
) -> AppResult<(StatusCode, Json<Model>)> {
    user.require(Permission::ConfiguratorDesign)?;
    let def = match &input.definition {
        Some(v) => parse_definition(v)?,
        None => Definition {
            schema_version: definition::SCHEMA_VERSION,
            name: input.name.clone(),
            ..Default::default()
        },
    };
    let mut tx = state.db.begin().await?;
    let id = store::insert_model(
        &mut tx,
        user.company_id,
        Some(user.user_id),
        &input.code,
        &input.name,
        &input.description,
        &input.translations,
        input.product_id,
    )
    .await?;
    let (rev, _) = store::insert_draft(&mut tx, id, Some(user.user_id), &def, "").await?;
    audit::record(
        &mut tx,
        &user,
        "configurator_model",
        id,
        "created",
        serde_json::json!({ "code": input.code.trim(), "draft_revision_id": rev }),
    )
    .await?;
    let m = store::load_model(&mut tx, user.company_id, id, false).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(m)))
}

#[utoipa::path(get, path = "/configurator/models/{id}", tag = "configurator", params(("id" = Uuid, Path)),
    responses((status = 200, body = Model), (status = 404, body = ErrorBody)))]
async fn get_model(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<Model>> {
    require_read(&user)?;
    let mut conn = state.db.acquire().await?;
    Ok(Json(
        store::load_model(&mut conn, user.company_id, id, false).await?,
    ))
}

/// Changes the name, description, translations, product and active flag of a configurator.
#[utoipa::path(put, path = "/configurator/models/{id}", tag = "configurator", params(("id" = Uuid, Path)),
    request_body = ModelUpdate,
    responses((status = 200, body = Model), (status = 404, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn update_model(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<ModelUpdate>,
) -> AppResult<Json<Model>> {
    user.require(Permission::ConfiguratorDesign)?;
    if input.name.trim().is_empty() {
        return Err(AppError::Validation("name is required".into()));
    }
    let mut tx = state.db.begin().await?;
    store::load_model(&mut tx, user.company_id, id, true).await?;
    sqlx::query(
        "UPDATE configurator.models SET name = $2, description = $3, translations = $4, product_id = $5,
                active = $6, updated_at = now() WHERE id = $1",
    )
    .bind(id)
    .bind(input.name.trim())
    .bind(input.description.trim())
    .bind(if input.translations.is_null() { serde_json::json!({}) } else { input.translations.clone() })
    .bind(input.product_id)
    .bind(input.active)
    .execute(&mut *tx)
    .await?;
    audit::record(
        &mut tx,
        &user,
        "configurator_model",
        id,
        "updated",
        serde_json::json!({ "name": input.name.trim(), "active": input.active }),
    )
    .await?;
    let m = store::load_model(&mut tx, user.company_id, id, false).await?;
    tx.commit().await?;
    Ok(Json(m))
}

/// Starts a new draft revision, copied from `copy_from` or from the active revision.
#[utoipa::path(post, path = "/configurator/models/{id}/revisions", tag = "configurator", params(("id" = Uuid, Path)),
    request_body = NewRevisionInput,
    responses((status = 201, body = Revision), (status = 404, body = ErrorBody), (status = 409, body = ErrorBody),
        (status = 422, body = ErrorBody)))]
async fn create_revision(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<NewRevisionInput>,
) -> AppResult<(StatusCode, Json<Revision>)> {
    user.require(Permission::ConfiguratorDesign)?;
    let mut tx = state.db.begin().await?;
    let model = store::load_model(&mut tx, user.company_id, id, true).await?;
    let source = match input.copy_from {
        Some(src) => model
            .revisions
            .iter()
            .find(|r| r.id == src)
            .map(|r| r.id)
            .ok_or_else(|| {
                AppError::Validation("copy_from must be a revision of the same configurator".into())
            })?,
        None => model
            .revisions
            .iter()
            .find(|r| r.status == "active")
            .or(model.revisions.first())
            .map(|r| r.id)
            .ok_or_else(|| AppError::Validation("there is no revision to copy".into()))?,
    };
    let def = store::load_revision(&mut tx, user.company_id, source, false)
        .await?
        .definition()?;
    let (rev, n) = store::insert_draft(&mut tx, id, Some(user.user_id), &def, &input.notes).await?;
    audit::record(
        &mut tx,
        &user,
        "configurator_revision",
        rev,
        "created",
        serde_json::json!({ "model_id": id, "revision": n, "copied_from": source }),
    )
    .await?;
    let r = store::load_revision(&mut tx, user.company_id, rev, false).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(r.into_api())))
}

/// A revision with its definition and the problems that block its activation.
#[utoipa::path(get, path = "/configurator/revisions/{id}", tag = "configurator", params(("id" = Uuid, Path)),
    responses((status = 200, body = Revision), (status = 404, body = ErrorBody)))]
async fn get_revision(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<Revision>> {
    require_read(&user)?;
    let mut conn = state.db.acquire().await?;
    Ok(Json(
        store::load_revision(&mut conn, user.company_id, id, false)
            .await?
            .into_api(),
    ))
}

/// Replaces the definition of a draft. A definition with problems is saved (they are listed in
/// `errors`) so work in progress is never lost; it only cannot be activated. It must be a
/// well-formed definition document, though (422 otherwise).
#[utoipa::path(put, path = "/configurator/revisions/{id}", tag = "configurator", params(("id" = Uuid, Path)),
    request_body = RevisionUpdate,
    responses((status = 200, body = Revision), (status = 404, body = ErrorBody), (status = 409, body = ErrorBody),
        (status = 422, body = ErrorBody)))]
async fn update_revision(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<RevisionUpdate>,
) -> AppResult<Json<Revision>> {
    user.require(Permission::ConfiguratorDesign)?;
    let def = parse_definition(&input.definition)?;
    let mut tx = state.db.begin().await?;
    let r = store::load_revision(&mut tx, user.company_id, id, true).await?;
    if r.status != "draft" {
        return Err(AppError::Conflict(format!(
            "revision {} is {}; create a new revision to change it",
            r.revision, r.status
        )));
    }
    sqlx::query(
        "UPDATE configurator.model_revisions SET definition = $2, notes = coalesce($3, notes), updated_at = now()
         WHERE id = $1",
    )
    .bind(id)
    .bind(serde_json::to_value(&def).map_err(|e| AppError::Internal(e.into()))?)
    .bind(input.notes.as_deref().map(str::trim))
    .execute(&mut *tx)
    .await?;
    let errors = definition::validate(&def).len();
    audit::record(
        &mut tx,
        &user,
        "configurator_revision",
        id,
        "updated",
        serde_json::json!({ "revision": r.revision, "errors": errors }),
    )
    .await?;
    let r = store::load_revision(&mut tx, user.company_id, id, false).await?;
    tx.commit().await?;
    Ok(Json(r.into_api()))
}

/// Makes a draft the active revision (refused while the definition has problems). The previous
/// active revision becomes obsolete; saved configurations stay on the revision they were made with.
#[utoipa::path(post, path = "/configurator/revisions/{id}/activate", tag = "configurator", params(("id" = Uuid, Path)),
    responses((status = 200, body = Revision), (status = 404, body = ErrorBody), (status = 409, body = ErrorBody),
        (status = 422, body = ErrorBody)))]
async fn activate_revision(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<Revision>> {
    user.require(Permission::ConfiguratorDesign)?;
    let mut tx = state.db.begin().await?;
    let r = store::load_revision(&mut tx, user.company_id, id, true).await?;
    // Serialise per model.
    store::load_model(&mut tx, user.company_id, r.model_id, true).await?;
    if r.status != "draft" {
        return Err(AppError::Conflict(format!(
            "revision {} is already {}",
            r.revision, r.status
        )));
    }
    compiled(&r.definition()?)?;
    store::activate(&mut tx, r.model_id, id).await?;
    audit::record(
        &mut tx,
        &user,
        "configurator_revision",
        id,
        "activated",
        serde_json::json!({ "model_id": r.model_id, "revision": r.revision }),
    )
    .await?;
    let r = store::load_revision(&mut tx, user.company_id, id, false).await?;
    tx.commit().await?;
    Ok(Json(r.into_api()))
}

/// A revision as a JSON file for another installation or the private repository.
#[utoipa::path(get, path = "/configurator/revisions/{id}/export", tag = "configurator", params(("id" = Uuid, Path)),
    responses((status = 200, body = ModelExport), (status = 404, body = ErrorBody)))]
async fn export_revision(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<ModelExport>> {
    require_read(&user)?;
    let mut conn = state.db.acquire().await?;
    let r = store::load_revision(&mut conn, user.company_id, id, false).await?;
    let m = store::load_model(&mut conn, user.company_id, r.model_id, false).await?;
    Ok(Json(ModelExport {
        format: EXPORT_FORMAT.into(),
        format_version: 1,
        model: store::ExportedModel {
            code: m.code,
            name: m.name,
            description: m.description,
            translations: m.translations,
        },
        definition: r.definition,
    }))
}

/// Imports an export as a new draft: of the configurator with the same code (409 if it already
/// has a draft), or of a new configurator.
#[utoipa::path(post, path = "/configurator/models/import", tag = "configurator", request_body = ModelExport,
    responses((status = 201, body = Revision), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn import_model(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<ModelExport>,
) -> AppResult<(StatusCode, Json<Revision>)> {
    user.require(Permission::ConfiguratorDesign)?;
    let def = store::parse_export(&input)?;
    let m = &input.model;
    let mut tx = state.db.begin().await?;
    let existing: Option<Uuid> = sqlx::query_scalar(
        "SELECT id FROM configurator.models WHERE company_id = $1 AND code = $2 FOR UPDATE",
    )
    .bind(user.company_id)
    .bind(m.code.trim())
    .fetch_optional(&mut *tx)
    .await?;
    let (model_id, created) = match existing {
        Some(id) => (id, false),
        None => (
            store::insert_model(
                &mut tx,
                user.company_id,
                Some(user.user_id),
                &m.code,
                &m.name,
                &m.description,
                &m.translations,
                None,
            )
            .await?,
            true,
        ),
    };
    let (rev, n) =
        store::insert_draft(&mut tx, model_id, Some(user.user_id), &def, "imported").await?;
    audit::record(&mut tx, &user, "configurator_revision", rev, "imported",
        serde_json::json!({ "model_id": model_id, "code": m.code.trim(), "revision": n, "new_model": created })).await?;
    let r = store::load_revision(&mut tx, user.company_id, rev, false).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(r.into_api())))
}

// ---------------------------------------------------------------------------------------------
// Formula editor
// ---------------------------------------------------------------------------------------------

#[derive(Debug, Deserialize, ToSchema)]
pub struct ExpressionCheckInput {
    pub source: String,
    /// Check as a template (`text {formula} text`) instead of a formula.
    #[serde(default)]
    pub template: bool,
    /// The definition the formula belongs to; without it names are not checked.
    #[serde(default)]
    #[schema(value_type = Option<Object>)]
    pub definition: Option<serde_json::Value>,
    /// The scope the formula is written in (default `project`).
    pub scope: Option<RuleScope>,
    /// The item table, for item scope.
    pub table: Option<String>,
    /// Extra local names the formula may use (of any type), e.g. `p` in a product filter or
    /// `each`, `each_index` and `parent` in an output rule.
    #[serde(default)]
    pub locals: Vec<String>,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct ExpressionCheckResult {
    pub ok: bool,
    /// The inferred type, e.g. `decimal`, `list of text`, `any`.
    #[serde(rename = "type")]
    pub value_type: String,
    pub errors: Vec<ExprError>,
}

/// Names a lone formula can see: those of a scope of a definition, checked loosely when the
/// definition itself has problems.
struct CheckEnv {
    names: std::collections::BTreeMap<String, Type>,
    tables: std::collections::BTreeMap<String, expr::TableInfo>,
}

impl TypeEnv for CheckEnv {
    fn name(&self, n: &str) -> Option<Type> {
        self.names.get(n).cloned()
    }
    fn table(&self, n: &str) -> Option<expr::TableInfo> {
        self.tables.get(n).cloned()
    }
}

/// The fields and computed values of a scope with their types: from the compiled definition, or,
/// when it does not compile (a draft being edited), read loosely from the document (computed
/// values are then of any type).
fn scope_names(
    def: &Definition,
    compiled: Option<&Compiled>,
    tables: &std::collections::BTreeMap<String, crate::tables::CompiledTable>,
    scope: ScopeKey,
) -> Vec<(String, Type)> {
    if let Some(c) = compiled {
        return c
            .names_in(scope)
            .map(|n| (n.name.clone(), n.ty.clone()))
            .collect();
    }
    let (fields, computed) = match scope {
        ScopeKey::Project => (&def.project.fields, &def.project.computed),
        ScopeKey::Group => (&def.group.fields, &def.group.computed),
        ScopeKey::Item(t) => match def.item_tables.get(t) {
            Some(t) => (&t.fields, &t.computed),
            None => return Vec::new(),
        },
    };
    fields
        .iter()
        .map(|f| (f.name.clone(), crate::compile::field_type(f, tables)))
        .chain(computed.iter().map(|c| (c.name.clone(), Type::Any)))
        .filter(|(n, _)| !n.is_empty())
        .collect()
}

fn check_env(
    def: &Definition,
    scope: Option<RuleScope>,
    table: Option<&str>,
) -> AppResult<CheckEnv> {
    let c = compile(def).ok();
    let tables: std::collections::BTreeMap<String, crate::tables::CompiledTable> = match &c {
        Some(c) => c.tables.clone(),
        None => def
            .tables
            .iter()
            .enumerate()
            .filter_map(|(i, t)| {
                crate::tables::CompiledTable::compile(t, &format!("$.tables[{i}]"))
                    .ok()
                    .map(|ct| (t.name.clone(), ct))
            })
            .collect(),
    };
    let key = match scope.unwrap_or(RuleScope::Project) {
        RuleScope::Project => ScopeKey::Project,
        RuleScope::Group => ScopeKey::Group,
        RuleScope::Item => {
            let t = match table {
                Some(t) => def.item_tables.iter().position(|x| x.name == t),
                None if def.item_tables.len() == 1 => Some(0),
                None => None,
            };
            ScopeKey::Item(t.ok_or_else(|| AppError::Validation("unknown item table".into()))?)
        }
    };
    let mut names = std::collections::BTreeMap::new();
    let chain: Vec<ScopeKey> = match key {
        ScopeKey::Item(t) => vec![ScopeKey::Project, ScopeKey::Group, ScopeKey::Item(t)],
        ScopeKey::Group => vec![ScopeKey::Project, ScopeKey::Group],
        ScopeKey::Project => vec![ScopeKey::Project],
    };
    for s in chain {
        for (n, ty) in scope_names(def, c.as_ref(), &tables, s) {
            names.insert(n, ty);
        }
    }
    match key {
        ScopeKey::Item(_) => {
            names.insert("index".into(), Type::Int);
            names.insert("group_name".into(), Type::Str);
            names.insert("label".into(), Type::Str);
        }
        _ => {
            for (t, tab) in def.item_tables.iter().enumerate() {
                let rec: std::collections::BTreeMap<String, Type> =
                    scope_names(def, c.as_ref(), &tables, ScopeKey::Item(t))
                        .into_iter()
                        .collect();
                names.insert(
                    tab.name.clone(),
                    Type::List(Box::new(Type::Record(Some(rec)))),
                );
            }
            names.insert("group_name".into(), Type::Str);
            names.insert("groups".into(), Type::List(Box::new(Type::Record(None))));
            if def.item_tables.len() == 1 {
                if let Some(t) = names.get(&def.item_tables[0].name).cloned() {
                    names.insert("items".into(), t);
                }
            }
        }
    }
    // Locals of output rules (`each`, `each_index`, `parent`) come in `locals`, only for rules.
    Ok(CheckEnv {
        names,
        tables: tables.iter().map(|(k, v)| (k.clone(), v.info())).collect(),
    })
}

/// Parses and type-checks one formula or template, for the editor.
#[utoipa::path(post, path = "/configurator/expressions/check", tag = "configurator", request_body = ExpressionCheckInput,
    responses((status = 200, body = ExpressionCheckResult), (status = 422, body = ErrorBody)))]
async fn check_expression(
    user: CurrentUser,
    Json(input): Json<ExpressionCheckInput>,
) -> AppResult<Json<ExpressionCheckResult>> {
    user.require(Permission::ConfiguratorDesign)?;
    let env: Box<dyn TypeEnv> = match &input.definition {
        Some(d) => {
            let mut env = check_env(&parse_definition(d)?, input.scope, input.table.as_deref())?;
            for l in &input.locals {
                env.names.insert(l.clone(), Type::Any);
            }
            Box::new(env)
        }
        None => Box::new(OpenEnv),
    };
    let (t, errors) = if input.template {
        match Template::parse(&input.source) {
            Ok(tpl) => (Type::Str, tpl.check(&[], env.as_ref())),
            Err(e) => (Type::Any, vec![e]),
        }
    } else {
        match expr::parse(&input.source) {
            Ok(e) => expr::check(&e, env.as_ref()),
            Err(e) => (Type::Any, vec![e]),
        }
    };
    Ok(Json(ExpressionCheckResult {
        ok: errors.is_empty(),
        value_type: t.to_string(),
        errors,
    }))
}

/// The functions of the formula language (for autocompletion).
#[utoipa::path(get, path = "/configurator/functions", tag = "configurator",
    responses((status = 200, body = Vec<Signature>)))]
async fn list_functions(user: CurrentUser) -> AppResult<Json<Vec<Signature>>> {
    require_read(&user)?;
    Ok(Json(FUNCTIONS.to_vec()))
}

#[derive(Debug, Default, Deserialize, IntoParams)]
pub struct EvaluateParams {
    /// ISO 639-1 language for the product names of the lines (base names when absent or
    /// untranslated).
    pub language: Option<String>,
}

/// Puts the product names of the lines in `language`, where translations exist.
async fn localize(db: &sqlx::PgPool, e: &mut Evaluation, language: Option<&str>) -> AppResult<()> {
    let Some(lang) = language.map(str::trim).filter(|l| !l.is_empty()) else {
        return Ok(());
    };
    let ids = e.product_ids();
    if ids.is_empty() {
        return Ok(());
    }
    let names = tradocraft_products::translations::names_in(db, &ids, lang).await?;
    e.localize(&names);
    Ok(())
}

/// Evaluates a revision with the given inputs: values, visibility, lines (with their products),
/// issues and traces. Drafts can only be evaluated by designers (the builder's test panel).
#[utoipa::path(post, path = "/configurator/revisions/{id}/evaluate", tag = "configurator", params(("id" = Uuid, Path), EvaluateParams),
    request_body = Inputs,
    responses((status = 200, body = Evaluation), (status = 404, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn evaluate_revision(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Query(params): Query<EvaluateParams>,
    Json(inputs): Json<Inputs>,
) -> AppResult<Json<Evaluation>> {
    require_read(&user)?;
    let mut conn = state.db.acquire().await?;
    let r = store::load_revision(&mut conn, user.company_id, id, false).await?;
    if r.status == "draft" {
        user.require(Permission::ConfiguratorDesign)?;
    }
    let c = compiled(&r.definition()?)?;
    let catalog = store::load_catalog(&mut conn).await?;
    drop(conn);
    let mut e = evaluate(&c, &inputs, &catalog);
    localize(&state.db, &mut e, params.language.as_deref()).await?;
    Ok(Json(e))
}

// ---------------------------------------------------------------------------------------------
// Saved configurations
// ---------------------------------------------------------------------------------------------

#[derive(Debug, Serialize, ToSchema)]
pub struct Configuration {
    pub id: Uuid,
    pub model_id: Uuid,
    pub model_code: String,
    pub model_name: String,
    pub revision_id: Uuid,
    pub revision: i32,
    /// draft | active | obsolete (of the revision it was made with)
    pub revision_status: String,
    /// The model's active revision when it is newer than this configuration's (offer an upgrade).
    pub newer_revision_id: Option<Uuid>,
    pub customer_id: Option<Uuid>,
    pub customer_name: Option<String>,
    pub name: String,
    pub inputs: Inputs,
    /// The evaluation when last saved or quoted.
    #[schema(value_type = Option<Object>)]
    pub result: Option<serde_json::Value>,
    pub quotation_id: Option<Uuid>,
    pub quotation_number: Option<String>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Serialize, FromRow, ToSchema)]
pub struct ConfigurationSummary {
    pub id: Uuid,
    pub model_id: Uuid,
    pub model_code: String,
    pub model_name: String,
    pub name: String,
    /// The revision it was made with.
    pub revision: i32,
    /// The number of the model's active revision when it is newer (an upgrade is available).
    pub newer_revision: Option<i32>,
    pub customer_id: Option<Uuid>,
    pub customer_name: Option<String>,
    pub quotation_id: Option<Uuid>,
    pub quotation_number: Option<String>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct ConfigurationInput {
    /// The model; the configuration is made with its active revision ...
    pub model_id: Option<Uuid>,
    /// ... or this active revision. On an update: moves the configuration to this (active)
    /// revision; left out, it stays on its own.
    pub revision_id: Option<Uuid>,
    pub customer_id: Option<Uuid>,
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub inputs: Inputs,
}

#[derive(Debug, Default, Deserialize, ToSchema)]
pub struct QuoteInput {
    /// Notes on the quotation.
    pub notes: Option<String>,
    pub valid_days: Option<i64>,
    /// `installation` (default) or `stock`.
    pub purpose: Option<String>,
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct ConfigurationFilter {
    pub model_id: Option<Uuid>,
    pub customer_id: Option<Uuid>,
}

#[derive(FromRow)]
struct ConfigRow {
    id: Uuid,
    model_id: Uuid,
    model_code: String,
    model_name: String,
    revision_id: Uuid,
    revision: i32,
    revision_status: String,
    newer_revision_id: Option<Uuid>,
    customer_id: Option<Uuid>,
    customer_name: Option<String>,
    name: String,
    inputs: serde_json::Value,
    result: Option<serde_json::Value>,
    quotation_id: Option<Uuid>,
    quotation_number: Option<String>,
    created_at: DateTime<Utc>,
    updated_at: DateTime<Utc>,
}

async fn load_configuration(
    conn: &mut sqlx::PgConnection,
    company_id: Uuid,
    id: Uuid,
    lock: bool,
) -> AppResult<Configuration> {
    let sql = format!(
        "SELECT c.id, c.model_id, m.code AS model_code, m.name AS model_name, c.revision_id, r.revision,
                r.status AS revision_status,
                (SELECT a.id FROM configurator.model_revisions a
                  WHERE a.model_id = c.model_id AND a.status = 'active' AND a.revision > r.revision) AS newer_revision_id,
                c.customer_id, cu.name AS customer_name, c.name, c.inputs, c.result, c.quotation_id,
                q.number AS quotation_number, c.created_at, c.updated_at
         FROM configurator.configurations c
         JOIN configurator.models m ON m.id = c.model_id
         JOIN configurator.model_revisions r ON r.id = c.revision_id
         LEFT JOIN crm.customers cu ON cu.id = c.customer_id
         LEFT JOIN sales.quotations q ON q.id = c.quotation_id
         WHERE c.id = $1 AND c.company_id = $2{}",
        if lock { " FOR UPDATE OF c" } else { "" }
    );
    let r: ConfigRow = sqlx::query_as(&sql)
        .bind(id)
        .bind(company_id)
        .fetch_optional(conn)
        .await?
        .ok_or(AppError::NotFound("configuration"))?;
    Ok(Configuration {
        id: r.id,
        model_id: r.model_id,
        model_code: r.model_code,
        model_name: r.model_name,
        revision_id: r.revision_id,
        revision: r.revision,
        revision_status: r.revision_status,
        newer_revision_id: r.newer_revision_id,
        customer_id: r.customer_id,
        customer_name: r.customer_name,
        name: r.name,
        inputs: serde_json::from_value(r.inputs).unwrap_or_default(),
        result: r.result,
        quotation_id: r.quotation_id,
        quotation_number: r.quotation_number,
        created_at: r.created_at,
        updated_at: r.updated_at,
    })
}

/// The active revision of a model, or the given revision if it is active.
async fn active_revision(
    conn: &mut sqlx::PgConnection,
    company_id: Uuid,
    model_id: Option<Uuid>,
    revision_id: Option<Uuid>,
) -> AppResult<store::RevisionRow> {
    let rev_id = match (revision_id, model_id) {
        (Some(r), _) => r,
        (None, Some(m)) => {
            store::load_model(&mut *conn, company_id, m, false).await?;
            sqlx::query_scalar("SELECT id FROM configurator.model_revisions WHERE model_id = $1 AND status = 'active'")
                .bind(m)
                .fetch_optional(&mut *conn)
                .await?
                .ok_or_else(|| AppError::Validation("this configurator has no active revision".into()))?
        }
        (None, None) => {
            return Err(AppError::Validation(
                "model_id or revision_id is required".into(),
            ))
        }
    };
    let r = store::load_revision(&mut *conn, company_id, rev_id, false).await?;
    if r.status != "active" {
        return Err(AppError::Validation(format!(
            "revision {} is {}; configurations are made with the active revision",
            r.revision, r.status
        )));
    }
    if model_id.is_some_and(|m| m != r.model_id) {
        return Err(AppError::Validation(
            "the revision belongs to another configurator".into(),
        ));
    }
    Ok(r)
}

async fn check_customer(
    db: &sqlx::PgPool,
    company_id: Uuid,
    customer_id: Option<Uuid>,
) -> AppResult<()> {
    if let Some(c) = customer_id {
        tradocraft_crm::get_customer_for_quoting(db, company_id, c).await?;
    }
    Ok(())
}

/// Evaluates inputs with a revision; the catalogue is read on the caller's connection (inside its
/// transaction, if any, so that it does not wait for a second pool connection).
async fn evaluate_row(
    conn: &mut sqlx::PgConnection,
    r: &store::RevisionRow,
    inputs: &Inputs,
) -> AppResult<Evaluation> {
    let c = compiled(&r.definition()?)?;
    let catalog = store::load_catalog(conn).await?;
    Ok(evaluate(&c, inputs, &catalog))
}

fn to_json<T: Serialize>(v: &T) -> AppResult<serde_json::Value> {
    serde_json::to_value(v).map_err(|e| AppError::Internal(e.into()))
}

#[utoipa::path(get, path = "/configurator/configurations", tag = "configurator", params(ConfigurationFilter),
    responses((status = 200, body = Vec<ConfigurationSummary>)))]
async fn list_configurations(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(f): Query<ConfigurationFilter>,
) -> AppResult<Json<Vec<ConfigurationSummary>>> {
    user.require(Permission::ConfiguratorUse)?;
    Ok(Json(
        sqlx::query_as(
            "SELECT c.id, c.model_id, m.code AS model_code, m.name AS model_name, c.name, r.revision,
                    (SELECT a.revision FROM configurator.model_revisions a
                      WHERE a.model_id = c.model_id AND a.status = 'active' AND a.revision > r.revision) AS newer_revision,
                    c.customer_id, cu.name AS customer_name, c.quotation_id, q.number AS quotation_number,
                    c.updated_at
             FROM configurator.configurations c
             JOIN configurator.models m ON m.id = c.model_id
             JOIN configurator.model_revisions r ON r.id = c.revision_id
             LEFT JOIN crm.customers cu ON cu.id = c.customer_id
             LEFT JOIN sales.quotations q ON q.id = c.quotation_id
             WHERE c.company_id = $1 AND ($2::uuid IS NULL OR c.model_id = $2)
               AND ($3::uuid IS NULL OR c.customer_id = $3)
             ORDER BY c.updated_at DESC LIMIT 500",
        )
        .bind(user.company_id)
        .bind(f.model_id)
        .bind(f.customer_id)
        .fetch_all(&state.db)
        .await?,
    ))
}

/// Saves a configuration (with the active revision) and its evaluation.
#[utoipa::path(post, path = "/configurator/configurations", tag = "configurator", request_body = ConfigurationInput,
    responses((status = 201, body = Configuration), (status = 404, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn create_configuration(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<ConfigurationInput>,
) -> AppResult<(StatusCode, Json<Configuration>)> {
    user.require(Permission::ConfiguratorUse)?;
    check_customer(&state.db, user.company_id, input.customer_id).await?;
    let mut conn = state.db.acquire().await?;
    let r = active_revision(
        &mut conn,
        user.company_id,
        input.model_id,
        input.revision_id,
    )
    .await?;
    // A withdrawn configurator keeps its configurations, but no new ones are made with it.
    let active: bool = sqlx::query_scalar("SELECT active FROM configurator.models WHERE id = $1")
        .bind(r.model_id)
        .fetch_one(&mut *conn)
        .await?;
    if !active {
        return Err(AppError::Validation(
            "this configurator is not active; no new configurations can be made with it".into(),
        ));
    }
    let result = evaluate_row(&mut conn, &r, &input.inputs).await?;
    drop(conn);
    let id = new_id();
    let mut tx = state.db.begin().await?;
    sqlx::query(
        "INSERT INTO configurator.configurations (id, company_id, model_id, revision_id, customer_id, name, inputs, result, created_by)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(r.model_id)
    .bind(r.id)
    .bind(input.customer_id)
    .bind(input.name.trim())
    .bind(to_json(&input.inputs)?)
    .bind(to_json(&result)?)
    .bind(user.user_id)
    .execute(&mut *tx)
    .await?;
    audit::record(
        &mut tx,
        &user,
        "configuration",
        id,
        "created",
        serde_json::json!({ "model_id": r.model_id, "revision_id": r.id }),
    )
    .await?;
    let c = load_configuration(&mut tx, user.company_id, id, false).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(c)))
}

#[utoipa::path(get, path = "/configurator/configurations/{id}", tag = "configurator", params(("id" = Uuid, Path)),
    responses((status = 200, body = Configuration), (status = 404, body = ErrorBody)))]
async fn get_configuration(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<Configuration>> {
    user.require(Permission::ConfiguratorUse)?;
    let mut conn = state.db.acquire().await?;
    Ok(Json(
        load_configuration(&mut conn, user.company_id, id, false).await?,
    ))
}

/// Saves new inputs (and name and customer). The configuration stays on its revision unless
/// `revision_id` names the model's active revision (the upgrade).
#[utoipa::path(put, path = "/configurator/configurations/{id}", tag = "configurator", params(("id" = Uuid, Path)),
    request_body = ConfigurationInput,
    responses((status = 200, body = Configuration), (status = 404, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn update_configuration(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<ConfigurationInput>,
) -> AppResult<Json<Configuration>> {
    user.require(Permission::ConfiguratorUse)?;
    check_customer(&state.db, user.company_id, input.customer_id).await?;
    let mut tx = state.db.begin().await?;
    let current = load_configuration(&mut tx, user.company_id, id, true).await?;
    let r = match input.revision_id {
        Some(rid) if rid != current.revision_id => {
            active_revision(&mut tx, user.company_id, Some(current.model_id), Some(rid)).await?
        }
        _ => store::load_revision(&mut tx, user.company_id, current.revision_id, false).await?,
    };
    let result = evaluate_row(&mut tx, &r, &input.inputs).await?;
    sqlx::query(
        "UPDATE configurator.configurations SET revision_id = $2, customer_id = $3, name = $4, inputs = $5,
                result = $6, updated_at = now() WHERE id = $1",
    )
    .bind(id)
    .bind(r.id)
    .bind(input.customer_id)
    .bind(input.name.trim())
    .bind(to_json(&input.inputs)?)
    .bind(to_json(&result)?)
    .execute(&mut *tx)
    .await?;
    audit::record(
        &mut tx,
        &user,
        "configuration",
        id,
        "updated",
        serde_json::json!({ "revision_id": r.id, "upgraded": r.id != current.revision_id }),
    )
    .await?;
    let c = load_configuration(&mut tx, user.company_id, id, false).await?;
    tx.commit().await?;
    Ok(Json(c))
}

/// Deletes a saved configuration. Quotations made from it stay.
#[utoipa::path(delete, path = "/configurator/configurations/{id}", tag = "configurator", params(("id" = Uuid, Path)),
    responses((status = 204), (status = 404, body = ErrorBody)))]
async fn delete_configuration(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<StatusCode> {
    user.require(Permission::ConfiguratorUse)?;
    let mut tx = state.db.begin().await?;
    load_configuration(&mut tx, user.company_id, id, true).await?;
    sqlx::query("DELETE FROM configurator.configurations WHERE id = $1")
        .bind(id)
        .execute(&mut *tx)
        .await?;
    audit::record(
        &mut tx,
        &user,
        "configuration",
        id,
        "deleted",
        serde_json::json!({}),
    )
    .await?;
    tx.commit().await?;
    Ok(StatusCode::NO_CONTENT)
}

/// The line tree as the quotation import takes it.
pub fn to_quote_lines(lines: &[Line]) -> Vec<ConfiguredLineInput> {
    lines
        .iter()
        .map(|l| ConfiguredLineInput {
            code: l.code.clone(),
            quantity: l.quantity,
            section: l.section.clone(),
            comment: l.comment.clone(),
            description: l.description.clone(),
            unit_price: None,
            percent_of_parent: l.percent_of_parent,
            percent_base: l.percent_base.as_deref().and_then(PercentBase::parse),
            children: to_quote_lines(&l.children),
        })
        .collect()
}

/// Creates or updates the quotation of a configuration: evaluates it on its own revision
/// (refused while it has errors) and imports the lines with source `configurator` and the
/// configuration id as reference. Quoting again updates the draft quotation, or creates its next
/// revision once it was sent (ADR 0033).
#[utoipa::path(post, path = "/configurator/configurations/{id}/quote", tag = "configurator", params(("id" = Uuid, Path)),
    request_body = QuoteInput,
    responses((status = 201, body = ConfiguredImportResult), (status = 200, body = ConfiguredImportResult),
        (status = 404, body = ErrorBody), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn quote_configuration(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<QuoteInput>,
) -> AppResult<(StatusCode, Json<ConfiguredImportResult>)> {
    user.require(Permission::ConfiguratorUse)?;
    user.require(Permission::QuotationsWrite)?;
    let mut conn = state.db.acquire().await?;
    let c = load_configuration(&mut conn, user.company_id, id, false).await?;
    let r = store::load_revision(&mut conn, user.company_id, c.revision_id, false).await?;
    let Some(customer_id) = c.customer_id else {
        return Err(AppError::Validation(
            "choose a customer before making a quotation".into(),
        ));
    };
    let result = evaluate_row(&mut conn, &r, &c.inputs).await?;
    drop(conn);
    let errors: Vec<&str> = result
        .issues
        .iter()
        .filter(|i| i.severity == definition::Severity::Error)
        .map(|i| i.message.as_str())
        .collect();
    if !errors.is_empty() {
        return Err(AppError::Validation(format!(
            "the configuration has errors: {}",
            errors.join("; ")
        )));
    }
    if result.lines.is_empty() {
        return Err(AppError::Validation(
            "the configuration produces no lines".into(),
        ));
    }
    let import_input = ConfiguredQuotationInput {
        source: QUOTE_SOURCE.into(),
        external_ref: id.to_string(),
        customer_id,
        price_zone_code: None,
        purpose: input.purpose,
        delivery_country_code: None,
        power_grid_id: None,
        vat_regime_override: None,
        building_construction_year: None,
        valid_days: input.valid_days,
        notes: input.notes.unwrap_or_else(|| {
            format!(
                "{} ({})",
                c.model_name,
                if c.name.is_empty() {
                    &c.model_code
                } else {
                    &c.name
                }
            )
        }),
        configuration: serde_json::json!({
            "configuration_id": id,
            "model": c.model_code,
            "model_id": c.model_id,
            "revision_id": c.revision_id,
            "revision": c.revision,
            "inputs": c.inputs,
        }),
        // A line without an active product would be dropped with its children: refuse instead.
        strict: true,
        lines: to_quote_lines(&result.lines),
    };
    let imported = import(&state.db, &user, import_input).await?;
    state.live_events.publish_record_change(
        &user,
        "quotation",
        imported.quotation.id,
        imported.quotation.version,
        "updated",
        None,
    );
    let mut tx = state.db.begin().await?;
    sqlx::query("UPDATE configurator.configurations SET quotation_id = $2, result = $3, updated_at = now() WHERE id = $1")
        .bind(id)
        .bind(imported.quotation.id)
        .bind(to_json(&result)?)
        .execute(&mut *tx)
        .await?;
    audit::record(
        &mut tx,
        &user,
        "configuration",
        id,
        "quoted",
        serde_json::json!({ "quotation_id": imported.quotation.id, "action": imported.action }),
    )
    .await?;
    tx.commit().await?;
    let status = if imported.action == "updated" {
        StatusCode::OK
    } else {
        StatusCode::CREATED
    };
    Ok((status, Json(imported)))
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(list_models, create_model))
        .routes(routes!(get_model, update_model))
        .routes(routes!(import_model))
        .routes(routes!(create_revision))
        .routes(routes!(get_revision, update_revision))
        .routes(routes!(activate_revision))
        .routes(routes!(export_revision))
        .routes(routes!(evaluate_revision))
        .routes(routes!(check_expression))
        .routes(routes!(list_functions))
        .routes(routes!(list_configurations, create_configuration))
        .routes(routes!(
            get_configuration,
            update_configuration,
            delete_configuration
        ))
        .routes(routes!(quote_configuration))
}
