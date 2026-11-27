//! Administration, section "Import" (`imports.admin`): a new import in five numbered steps on one
//! page (file, what and where, columns, check, import) and the history of the runs. Mirrors
//! `app/lib/features/admin/imports/` (wizard state, mapping rules, job widgets and history).
//! Leaving the page stops the polling of a job; the job goes on and shows in the history.

use std::time::Duration;

use leptos::ev::SubmitEvent;
use leptos::prelude::*;
use tradocraft_api_client::imports::{
    ColumnPair, CreateJob, ImportColumn, ImportDescription, ImportFile, ImportJob, ImportMapping,
    ImportPreview, ListImportJobsParams, MappingInput,
};
use uuid::Uuid;

use super::{
    begin_file_read, bump, file_size, is_current, save_file, spawn_api, Feedback, FeedbackView,
    PickedFile,
};
use crate::pages::set_alive;
use crate::state::AppContext;

/// The server's upload limit (50 MiB).
const MAX_FILE_BYTES: usize = 50 * 1024 * 1024;
const TOO_LARGE: &str = "The file is larger than the limit of 50 MiB.";
/// How often a queued or running job of the wizard is asked for its progress.
const POLL: Duration = Duration::from_secs(2);
/// How often the history and a job's detail refresh while a job is queued or running.
const HISTORY_REFRESH: Duration = Duration::from_secs(3);
/// Runs per request of the history (the API allows at most 200).
const PAGE_SIZE: i64 = 50;

// ---------------------------------------------------------------------------------------------
// Pure rules of the column mapping step (mapping_logic.dart).

/// File column names are compared trimmed and case-insensitively, as the server does.
pub(crate) fn normalize_name(s: &str) -> String {
    s.trim().to_lowercase()
}

/// The saved mapping whose file columns all occur in `header`; the one covering most columns when
/// several do. None when none fits.
pub(crate) fn best_saved_mapping<'a>(
    header: &[String],
    saved: &'a [ImportMapping],
) -> Option<&'a ImportMapping> {
    let present: Vec<String> = header.iter().map(|h| normalize_name(h)).collect();
    let mut best: Option<&ImportMapping> = None;
    for m in saved {
        if m.columns.is_empty()
            || !m.columns.iter().all(|p| {
                p.column
                    .as_deref()
                    .is_none_or(|c| present.contains(&normalize_name(c)))
            })
        {
            continue;
        }
        if best.is_none_or(|b| m.columns.len() > b.columns.len()) {
            best = Some(m);
        }
    }
    best
}

/// The field of a per-language family (`name` for `name_fr`) that the file column `header` names:
/// the prefix, `_` and a two-letter code (the server checks the code against ISO 639-1).
pub(crate) fn family_field(column: &ImportColumn, header: &str) -> Option<String> {
    if !column.per_language {
        return None;
    }
    let h = normalize_name(header);
    let code = h.strip_prefix(&column.name)?.strip_prefix('_')?;
    (code.len() == 2 && code.chars().all(|c| c.is_ascii_lowercase())).then_some(h)
}

/// Whether `field` is a field of the entity: a column name or a member of a family.
fn is_field(entity: &ImportDescription, field: &str) -> bool {
    entity
        .columns
        .iter()
        .any(|c| c.name == field || family_field(c, field).is_some())
}

/// File columns paired with the field of the same name; a repeated header name is paired once.
pub(crate) fn same_name_fields(
    header: &[String],
    entity: &ImportDescription,
) -> Vec<Option<String>> {
    let mut used: Vec<String> = Vec::new();
    header
        .iter()
        .map(|h| {
            let field = entity
                .columns
                .iter()
                .find(|c| !c.per_language && normalize_name(&c.name) == normalize_name(h))
                .map(|c| c.name.clone())
                .or_else(|| entity.columns.iter().find_map(|c| family_field(c, h)))?;
            if used.contains(&field) {
                return None;
            }
            used.push(field.clone());
            Some(field)
        })
        .collect()
}

/// The fields a saved mapping gives to the file columns in `header`; a column it does not name is
/// ignored, and so is a pair whose field the entity no longer has.
pub(crate) fn fields_from_mapping(
    header: &[String],
    entity: &ImportDescription,
    m: &ImportMapping,
) -> Vec<Option<String>> {
    let mut by_column: Vec<(String, String)> = Vec::new();
    for p in &m.columns {
        let Some(column) = p.column.as_deref() else {
            continue; // a fixed value: not shown on this screen
        };
        if is_field(entity, &p.field) {
            let key = normalize_name(column);
            if !by_column.iter().any(|(k, _)| *k == key) {
                by_column.push((key, p.field.clone()));
            }
        }
    }
    let mut used: Vec<String> = Vec::new();
    header
        .iter()
        .map(|h| {
            let key = normalize_name(h);
            let field = by_column
                .iter()
                .find(|(k, _)| *k == key)
                .map(|(_, f)| f.clone())?;
            if used.contains(&field) {
                return None;
            }
            used.push(field.clone());
            Some(field)
        })
        .collect()
}

/// The first proposal: a fitting saved mapping, else pairing by name. Returns the fields and the
/// name of the saved mapping used.
pub(crate) fn propose_mapping(
    header: &[String],
    entity: &ImportDescription,
    saved: &[ImportMapping],
) -> (Vec<Option<String>>, Option<String>) {
    match best_saved_mapping(header, saved) {
        Some(m) => (fields_from_mapping(header, entity, m), Some(m.name.clone())),
        None => (same_name_fields(header, entity), None),
    }
}

/// The fixed values of a saved mapping (pairs without a file column) whose fields the entity still
/// has. This screen keeps them as they are: they are shown, sent with a run and saved again, but
/// not edited here.
pub(crate) fn fixed_from_mapping(entity: &ImportDescription, m: &ImportMapping) -> Vec<ColumnPair> {
    m.columns
        .iter()
        .filter(|p| p.column.is_none() && p.value.is_some() && is_field(entity, &p.field))
        .cloned()
        .collect()
}

/// What is wrong with, or missing from, a mapping.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct MappingCheck {
    /// Key columns without a file column or fixed value.
    pub missing_keys: Vec<String>,
    /// Fields chosen for more than one file column.
    pub duplicates: Vec<String>,
    /// Fields without a file column.
    pub unmapped: Vec<String>,
    /// Fields without a file column that a new record needs.
    pub unmapped_required: Vec<String>,
}

impl MappingCheck {
    pub fn blocked(&self) -> bool {
        !self.missing_keys.is_empty() || !self.duplicates.is_empty()
    }
}

/// Checks the fields chosen for the file columns together with the `fixed` values.
pub(crate) fn check_mapping(
    fields: &[Option<String>],
    fixed: &[ColumnPair],
    entity: &ImportDescription,
) -> MappingCheck {
    let mut seen: Vec<&str> = Vec::new();
    let mut dup: Vec<String> = Vec::new();
    for f in fields
        .iter()
        .flatten()
        .chain(fixed.iter().map(|p| &p.field))
    {
        if seen.contains(&f.as_str()) {
            if !dup.contains(f) {
                dup.push(f.clone());
            }
        } else {
            seen.push(f);
        }
    }
    MappingCheck {
        // A legacy description names only `key_column`.
        missing_keys: if entity.key_columns.is_empty() {
            std::slice::from_ref(&entity.key_column)
        } else {
            entity.key_columns.as_slice()
        }
        .iter()
        .filter(|k| !seen.contains(&k.as_str()))
        .cloned()
        .collect(),
        duplicates: dup,
        unmapped: entity
            .columns
            .iter()
            .filter(|c| !c.per_language && !seen.contains(&c.name.as_str()))
            .map(|c| c.name.clone())
            .collect(),
        unmapped_required: entity
            .columns
            .iter()
            .filter(|c| c.required && !seen.contains(&c.name.as_str()))
            .map(|c| c.name.clone())
            .collect(),
    }
}

/// The pairs to send with a job: none when every file column is the field of the same name and
/// nothing is ignored (the strict header of the server is exact too); the non-ignored pairs
/// otherwise, followed by the `fixed` values.
pub(crate) fn columns_to_send(
    header: &[String],
    fields: &[Option<String>],
    fixed: &[ColumnPair],
) -> Option<Vec<ColumnPair>> {
    let identity = fixed.is_empty()
        && header
            .iter()
            .zip(fields)
            .all(|(h, f)| f.as_deref() == Some(h.as_str()));
    if identity {
        return None;
    }
    Some(
        header
            .iter()
            .zip(fields)
            .filter_map(|(h, f)| f.as_ref().map(|f| ColumnPair::column(h.clone(), f.clone())))
            .chain(fixed.iter().cloned())
            .collect(),
    )
}

/// Identifies what a check was run for; Import is possible only when it equals the current one.
pub(crate) fn run_signature(
    file_id: Uuid,
    entity: &str,
    sheet: Option<&str>,
    columns: Option<&[ColumnPair]>,
) -> String {
    let cols = columns.map(|c| {
        c.iter()
            .map(|p| vec![p.column.clone(), p.value.clone(), Some(p.field.clone())])
            .collect::<Vec<_>>()
    });
    serde_json::json!([file_id, entity, sheet, cols]).to_string()
}

// ---------------------------------------------------------------------------------------------
// Labels (job_widgets.dart, imports_api.dart).

pub(crate) fn entity_label(key: &str) -> &str {
    match key {
        "customers" => "Customers",
        "products" => "Products",
        other => other,
    }
}

fn format_name(format: &str) -> &str {
    match format {
        "csv" => "CSV",
        "xlsx" => "Excel (XLSX)",
        "ods" => "OpenDocument (ODS)",
        other => other,
    }
}

/// The label of a job's status; "done with N errors" is told apart from a clean "done".
pub(crate) fn job_status_label(j: &ImportJob) -> String {
    match j.status.as_str() {
        "queued" => "Queued".into(),
        "running" => "Running".into(),
        "done" if j.error_count == 1 => "Done with 1 error".into(),
        "done" if j.error_count > 0 => format!("Done with {} errors", j.error_count),
        "done" => "Done".into(),
        "failed" => "Failed".into(),
        "cancelled" => "Cancelled".into(),
        other => other.into(),
    }
}

fn status_badge(j: &ImportJob) -> &'static str {
    match j.status.as_str() {
        "done" if j.error_count > 0 => "tc-badge tc-badge-warning",
        "done" => "tc-badge tc-badge-success",
        "failed" => "tc-badge tc-badge-error",
        "running" => "tc-badge tc-badge-primary",
        _ => "tc-badge",
    }
}

fn phase_label(j: &ImportJob) -> String {
    match j.phase.as_deref() {
        Some("reading") => "Reading the file".into(),
        Some("validating") => "Validating the rows".into(),
        Some("writing") => "Writing the records".into(),
        _ => job_status_label(j),
    }
}

fn rows_text(n: u64) -> String {
    if n == 1 {
        "1 data row".into()
    } else {
        format!("{n} data rows")
    }
}

fn problems_text(n: i32) -> String {
    if n == 1 {
        "1 problem found. Nothing has been imported.".into()
    } else {
        format!("{n} problems found. Nothing has been imported.")
    }
}

#[cfg(target_arch = "wasm32")]
fn format_when(t: chrono::DateTime<chrono::Utc>) -> String {
    let d = js_sys::Date::new(&wasm_bindgen::JsValue::from_f64(t.timestamp_millis() as f64));
    format!(
        "{:02}/{:02}/{:04} {:02}:{:02}",
        d.get_date(),
        d.get_month() + 1,
        d.get_full_year(),
        d.get_hours(),
        d.get_minutes()
    )
}

#[cfg(not(target_arch = "wasm32"))]
fn format_when(t: chrono::DateTime<chrono::Utc>) -> String {
    t.timestamp().to_string()
}

// ---------------------------------------------------------------------------------------------
// The wizard state (import_wizard.dart).

/// One run (the check or the import): the job as last seen, whether the request is under way and
/// what it was run for.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
struct RunState {
    job: Option<ImportJob>,
    starting: bool,
    error: Option<String>,
    signature: Option<String>,
}

/// Every signal of the import screen; all fields are `Copy`.
#[derive(Clone, Copy)]
struct Wizard {
    ctx: AppContext,
    fb: Feedback,
    file: RwSignal<Option<ImportFile>>,
    uploading: RwSignal<bool>,
    upload_error: RwSignal<Option<String>>,
    entities: RwSignal<Option<Result<Vec<ImportDescription>, String>>>,
    entity: RwSignal<Option<ImportDescription>>,
    sheet: RwSignal<Option<String>>,
    preview: RwSignal<Option<ImportPreview>>,
    preview_loading: RwSignal<bool>,
    preview_error: RwSignal<Option<String>>,
    saved: RwSignal<Vec<ImportMapping>>,
    saved_error: RwSignal<Option<String>>,
    fields: RwSignal<Vec<Option<String>>>,
    /// Fixed values taken from a saved mapping (read-only here).
    fixed: RwSignal<Vec<ColumnPair>>,
    proposed_from: RwSignal<Option<String>>,
    proposed_fields: StoredValue<Option<Vec<Option<String>>>>,
    dry: RwSignal<RunState>,
    apply: RwSignal<RunState>,
    /// One generation per run slot (check, import): a response is accepted only while its
    /// generation is current and the slot still holds the job it asked about.
    gen_dry: StoredValue<u64>,
    gen_apply: StoredValue<u64>,
    preview_seq: StoredValue<u64>,
    entity_seq: StoredValue<u64>,
    /// The newest saved-mappings request.
    saved_seq: StoredValue<u64>,
    /// The newest file choice: a slower read or upload of an earlier choice is ignored.
    upload_seq: StoredValue<u64>,
}

impl Wizard {
    fn new(ctx: AppContext, fb: Feedback) -> Self {
        Self {
            ctx,
            fb,
            file: RwSignal::new(None),
            uploading: RwSignal::new(false),
            upload_error: RwSignal::new(None),
            entities: RwSignal::new(None),
            entity: RwSignal::new(None),
            sheet: RwSignal::new(None),
            preview: RwSignal::new(None),
            preview_loading: RwSignal::new(false),
            preview_error: RwSignal::new(None),
            saved: RwSignal::new(Vec::new()),
            saved_error: RwSignal::new(None),
            fields: RwSignal::new(Vec::new()),
            fixed: RwSignal::new(Vec::new()),
            proposed_from: RwSignal::new(None),
            proposed_fields: StoredValue::new(None),
            dry: RwSignal::new(RunState::default()),
            apply: RwSignal::new(RunState::default()),
            gen_dry: StoredValue::new(0),
            gen_apply: StoredValue::new(0),
            preview_seq: StoredValue::new(0),
            entity_seq: StoredValue::new(0),
            saved_seq: StoredValue::new(0),
            upload_seq: StoredValue::new(0),
        }
    }

    fn slot(self, dry: bool) -> RwSignal<RunState> {
        if dry {
            self.dry
        } else {
            self.apply
        }
    }

    fn generation(self, dry: bool) -> StoredValue<u64> {
        if dry {
            self.gen_dry
        } else {
            self.gen_apply
        }
    }

    /// Drops every response still on its way for the slot (and stops its polling).
    fn restart(self, dry: bool) -> u64 {
        bump(self.generation(dry))
    }

    fn restart_all(self) {
        self.restart(true);
        self.restart(false);
    }

    /// A response for job `id` asked for in generation `gen` still belongs to the slot (and the
    /// page is still there).
    fn owns(self, dry: bool, gen: u64, id: Uuid) -> bool {
        self.generation(dry).try_get_value() == Some(gen)
            && self
                .slot(dry)
                .try_with_untracked(|r| r.job.as_ref().map(|j| j.id) == Some(id))
                .unwrap_or(false)
    }

    fn header(self) -> Vec<String> {
        self.preview
            .with(|p| p.as_ref().map(|p| p.columns.clone()).unwrap_or_default())
    }

    fn mappable(self) -> bool {
        self.file.with(Option::is_some)
            && self.entity.with(Option::is_some)
            && self.preview.with(|p| {
                p.as_ref()
                    .is_some_and(|p| self.fields.with(|f| f.len() == p.columns.len()))
            })
    }

    fn check(self) -> Option<MappingCheck> {
        if !self.mappable() {
            return None;
        }
        self.entity.with(|e| {
            e.as_ref().map(|e| {
                self.fields
                    .with(|f| self.fixed.with(|x| check_mapping(f, x, e)))
            })
        })
    }

    fn mapping_ok(self) -> bool {
        self.check().is_some_and(|c| !c.blocked())
    }

    fn columns(self) -> Option<Vec<ColumnPair>> {
        let header = self.header();
        self.fields
            .with(|f| self.fixed.with(|x| columns_to_send(&header, f, x)))
    }

    /// What a run started now would be for.
    fn signature(self) -> Option<String> {
        if !self.mappable() {
            return None;
        }
        let file = self.file.with(|f| f.as_ref().map(|f| f.id))?;
        let entity = self.entity.with(|e| e.as_ref().map(|e| e.key.clone()))?;
        let cols = self.columns();
        Some(run_signature(
            file,
            &entity,
            self.sheet.get().as_deref(),
            cols.as_deref(),
        ))
    }

    /// The check ended `done` without errors for exactly what is chosen now.
    fn checked_clean(self) -> bool {
        self.mapping_ok()
            && self.dry.with(|r| {
                r.job
                    .as_ref()
                    .is_some_and(|j| j.status == "done" && j.error_count == 0)
                    && r.signature == self.signature()
            })
    }

    /// A check exists but was run for other settings.
    fn check_outdated(self) -> bool {
        self.dry
            .with(|r| r.job.is_some() && r.signature != self.signature())
    }

    fn load_entities(self) {
        self.entities.set(None);
        spawn_api(
            self.ctx,
            |c| async move { c.list_import_entities().await },
            move |res| {
                set_alive(self.entities, Some(res.map_err(|e| e.user_message())));
            },
        );
    }

    /// Back to the first step; the chosen entity and its saved mappings stay.
    fn reset(self) {
        self.restart_all();
        bump(self.preview_seq);
        bump(self.entity_seq);
        self.proposed_fields.set_value(None);
        self.file.set(None);
        self.uploading.set(false);
        self.upload_error.set(None);
        self.sheet.set(None);
        self.preview.set(None);
        self.preview_loading.set(false);
        self.preview_error.set(None);
        self.fields.set(Vec::new());
        self.fixed.set(Vec::new());
        self.proposed_from.set(None);
        self.dry.set(RunState::default());
        self.apply.set(RunState::default());
    }

    /// Uploads the file of the choice `gen` (from [`Self::upload_seq`]), unless a newer file was
    /// chosen meanwhile.
    fn upload(self, picked: PickedFile, gen: u64) {
        if !is_current(self.upload_seq, gen) {
            return;
        }
        if picked.bytes.is_empty() {
            self.upload_error.set(Some("The file is empty.".into()));
            return;
        }
        self.reset();
        self.uploading.set(true);
        let name = picked.name;
        let bytes = picked.bytes;
        spawn_api(
            self.ctx,
            move |c| async move { c.upload_import_file(&name, bytes).await },
            move |res| {
                if !is_current(self.upload_seq, gen) || !set_alive(self.uploading, false) {
                    return;
                }
                match res {
                    Ok(file) => {
                        self.sheet.set(file.sheets.first().cloned());
                        self.file.set(Some(file));
                        self.load_preview();
                    }
                    Err(err) if err.status() == Some(413) => {
                        self.upload_error.set(Some(TOO_LARGE.into()));
                    }
                    Err(err) => self.upload_error.set(Some(err.user_message())),
                }
            },
        );
    }

    fn load_preview(self) {
        let Some(file_id) = self.file.with_untracked(|f| f.as_ref().map(|f| f.id)) else {
            return;
        };
        let seq = bump(self.preview_seq);
        self.preview.set(None);
        self.preview_loading.set(true);
        self.preview_error.set(None);
        self.fields.set(Vec::new());
        let sheet = self.sheet.get_untracked();
        spawn_api(
            self.ctx,
            move |c| async move { c.preview_import_file(file_id, sheet.as_deref()).await },
            move |res| {
                if self.preview_seq.try_get_value() != Some(seq) {
                    return;
                }
                self.preview_loading.set(false);
                match res {
                    Ok(p) => {
                        self.preview.set(Some(p));
                        self.propose();
                    }
                    Err(err) => self.preview_error.set(Some(err.user_message())),
                }
            },
        );
    }

    /// The person changed the columns since the last proposal.
    fn edited(self) -> bool {
        let f = self.fields.get_untracked();
        if f.is_empty() {
            return false;
        }
        self.proposed_fields.with_value(|p| p.as_ref() != Some(&f))
    }

    fn propose(self) {
        let (Some(e), Some(p)) = (self.entity.get_untracked(), self.preview.get_untracked()) else {
            return;
        };
        let (fields, fixed, from) = self.saved.with_untracked(|s| {
            let (fields, from) = propose_mapping(&p.columns, &e, s);
            let fixed = best_saved_mapping(&p.columns, s)
                .map(|m| fixed_from_mapping(&e, m))
                .unwrap_or_default();
            (fields, fixed, from)
        });
        self.proposed_fields.set_value(Some(fields.clone()));
        self.fields.set(fields);
        self.fixed.set(fixed);
        self.proposed_from.set(from);
    }

    fn select_entity(self, key: &str) {
        let Some(e) = self.entities.with_untracked(|l| {
            l.as_ref()
                .and_then(|r| r.as_ref().ok())
                .and_then(|l| l.iter().find(|e| e.key == key).cloned())
        }) else {
            return;
        };
        if self
            .entity
            .with_untracked(|cur| cur.as_ref().map(|c| c.key.clone()))
            == Some(e.key.clone())
        {
            return;
        }
        let seq = bump(self.entity_seq);
        self.restart_all();
        self.proposed_fields.set_value(None);
        self.entity.set(Some(e));
        self.saved.set(Vec::new());
        self.saved_error.set(None);
        self.fields.set(Vec::new());
        self.fixed.set(Vec::new());
        self.proposed_from.set(None);
        self.dry.set(RunState::default());
        self.apply.set(RunState::default());
        self.refresh_saved(move |w| {
            // Another entity was chosen meanwhile, or the person already changed the columns.
            if w.entity_seq.try_get_value() == Some(seq) && !w.edited() {
                w.propose();
            }
        });
    }

    fn select_sheet(self, sheet: String) {
        if self.sheet.get_untracked().as_deref() == Some(sheet.as_str()) {
            return;
        }
        self.restart_all();
        self.sheet.set(Some(sheet));
        self.dry.set(RunState::default());
        self.apply.set(RunState::default());
        self.load_preview();
    }

    /// Reloads the saved mappings of the chosen entity, then calls `then`.
    fn refresh_saved(self, then: impl FnOnce(Wizard) + 'static) {
        let Some(key) = self
            .entity
            .with_untracked(|e| e.as_ref().map(|e| e.key.clone()))
        else {
            return;
        };
        self.saved_error.set(None);
        let key_check = key.clone();
        let gen = bump(self.saved_seq);
        spawn_api(
            self.ctx,
            move |c| async move { c.list_import_mappings(&key).await },
            move |res| {
                // A newer request (another entity, a save or a delete) answers instead.
                if !is_current(self.saved_seq, gen) {
                    return;
                }
                let current = self
                    .entity
                    .try_with_untracked(|e| e.as_ref().map(|e| e.key.clone()));
                if current != Some(Some(key_check)) {
                    return;
                }
                match res {
                    Ok(list) => self.saved.set(list),
                    Err(err) => self.saved_error.set(Some(err.user_message())),
                }
                then(self);
            },
        );
    }

    /// Takes the columns of a saved mapping that the file has; the others are ignored.
    fn use_mapping(self, m: &ImportMapping) {
        let (Some(e), Some(p)) = (self.entity.get_untracked(), self.preview.get_untracked()) else {
            return;
        };
        self.fields.set(fields_from_mapping(&p.columns, &e, m));
        self.fixed.set(fixed_from_mapping(&e, m));
        self.proposed_from.set(Some(m.name.clone()));
    }

    fn set_field(self, index: usize, field: Option<String>) {
        self.fields.update(|f| {
            if let Some(slot) = f.get_mut(index) {
                *slot = field;
            }
        });
        self.proposed_from.set(None);
    }

    /// Saves the current pairs under `name` (an existing mapping with that name is replaced).
    fn save_mapping(self, name: String) {
        let Some(entity) = self
            .entity
            .with_untracked(|e| e.as_ref().map(|e| e.key.clone()))
        else {
            return;
        };
        let header = self.header();
        let columns = self.fields.with_untracked(|f| {
            header
                .iter()
                .zip(f)
                .filter_map(|(h, f)| f.as_ref().map(|f| ColumnPair::column(h.clone(), f.clone())))
                .chain(self.fixed.get_untracked())
                .collect::<Vec<_>>()
        });
        let body = MappingInput {
            entity,
            name: name.clone(),
            columns,
        };
        spawn_api(
            self.ctx,
            move |c| async move { c.save_import_mapping(&body).await },
            move |res| match res {
                Ok(_) => {
                    if self.fb.ok(format!("Mapping {name} saved")) {
                        self.refresh_saved(|_| {});
                    }
                }
                Err(err) => {
                    self.fb.fail(err.user_message());
                }
            },
        );
    }

    fn delete_mapping(self, m: ImportMapping) {
        spawn_api(
            self.ctx,
            move |c| async move { c.delete_import_mapping(m.id).await },
            move |res| match res {
                Ok(()) => {
                    if self.fb.ok(format!("Mapping {} deleted", m.name)) {
                        self.refresh_saved(|_| {});
                    }
                }
                Err(err) => {
                    self.fb.fail(err.user_message());
                }
            },
        );
    }

    /// Runs the file through the importer: a check (`dry`) or the real import. A finished job
    /// comes back at once; a queued one is polled until it ends.
    fn run(self, dry: bool) {
        let Some(sig) = self.signature() else {
            return;
        };
        if !self.mapping_ok() {
            return;
        }
        // The real import only for exactly what was checked without problems.
        if !dry && !self.checked_clean() {
            return;
        }
        let (Some(file_id), Some(entity)) = (
            self.file.with_untracked(|f| f.as_ref().map(|f| f.id)),
            self.entity
                .with_untracked(|e| e.as_ref().map(|e| e.key.clone())),
        ) else {
            return;
        };
        let body = CreateJob {
            file_id,
            entity,
            sheet: self.sheet.get_untracked(),
            columns: self.columns(),
            dry_run: dry,
        };
        let gen = self.restart(dry);
        self.slot(dry).set(RunState {
            starting: true,
            ..RunState::default()
        });
        spawn_api(
            self.ctx,
            move |c| async move { c.create_import_job(&body).await },
            move |res| {
                // The settings changed or another run was started meanwhile.
                if self.generation(dry).try_get_value() != Some(gen) {
                    return;
                }
                match res {
                    Ok(job) => {
                        let id = job.id;
                        let active = job.is_active();
                        self.slot(dry).set(RunState {
                            job: Some(job),
                            starting: false,
                            error: None,
                            signature: Some(sig),
                        });
                        if active {
                            self.schedule_poll(dry, id);
                        }
                    }
                    Err(err) => self.slot(dry).update(|r| {
                        r.starting = false;
                        r.error = Some(err.user_message());
                    }),
                }
            },
        );
    }

    fn schedule_poll(self, dry: bool, id: Uuid) {
        let Some(gen) = self.generation(dry).try_get_value() else {
            return;
        };
        set_timeout(move || self.poll(dry, id, gen), POLL);
    }

    fn poll(self, dry: bool, id: Uuid, gen: u64) {
        if !self.owns(dry, gen, id) {
            return;
        }
        spawn_api(
            self.ctx,
            move |c| async move { c.get_import_job(id).await },
            move |res| {
                if !self.owns(dry, gen, id) {
                    return;
                }
                match res {
                    Ok(job) => {
                        let active = job.is_active();
                        self.slot(dry).update(|r| {
                            r.job = Some(job);
                            r.error = None;
                        });
                        if active {
                            self.schedule_poll(dry, id);
                        }
                    }
                    Err(err) => {
                        // A failed poll (a network blip) is shown and tried again.
                        self.slot(dry)
                            .update(|r| r.error = Some(err.user_message()));
                        self.schedule_poll(dry, id);
                    }
                }
            },
        );
    }

    /// Cancels the job of a run that is still queued.
    fn cancel(self, dry: bool) {
        let Some(id) = self
            .slot(dry)
            .with_untracked(|r| r.job.as_ref().map(|j| j.id))
        else {
            return;
        };
        // A poll still on its way would bring back the job as it was before the cancellation.
        let gen = self.restart(dry);
        spawn_api(
            self.ctx,
            move |c| async move { c.cancel_import_job(id).await },
            move |res| {
                if !self.owns(dry, gen, id) {
                    return;
                }
                match res {
                    Ok(job) => self.slot(dry).update(|r| {
                        r.job = Some(job);
                        r.error = None;
                    }),
                    Err(err) => {
                        // 409: the worker picked it up meanwhile. Show why and look again.
                        self.slot(dry)
                            .update(|r| r.error = Some(err.user_message()));
                        self.schedule_poll(dry, id);
                    }
                }
            },
        );
    }
}

/// Saves the error report of a job as CSV.
fn download_errors(ctx: AppContext, fb: Feedback, job_id: Uuid) {
    let first = job_id.to_string();
    let name = format!(
        "import-errors-{}.csv",
        first.split('-').next().unwrap_or("job")
    );
    spawn_api(
        ctx,
        move |c| async move { c.download_import_errors(job_id).await },
        move |res| match res {
            Ok(bytes) => match save_file(&name, "text/csv", &bytes) {
                Ok(()) => {
                    fb.ok(format!("Saved {name}"));
                }
                Err(msg) => {
                    fb.fail(format!("Export failed: {msg}"));
                }
            },
            Err(err) => {
                fb.fail(format!("Export failed: {}", err.user_message()));
            }
        },
    );
}

// ---------------------------------------------------------------------------------------------
// Views.

/// What a job shows by status: progress while it runs, the failure message, the errors of a
/// finished run, or its counts. `planned` = a check (nothing was written).
#[component]
fn JobOutcome(
    job: ImportJob,
    planned: bool,
    #[prop(optional)] on_cancel: Option<Callback<()>>,
    prefix: &'static str,
) -> impl IntoView {
    let ctx = expect_context::<AppContext>();
    let fb = expect_context::<Feedback>();
    let status = job_status_label(&job);
    let badge = status_badge(&job);
    let body = if job.is_active() {
        let known = job.total_rows > 0;
        let mut text = phase_label(&job);
        if known {
            text.push_str(&format!(
                ", {} of {} rows",
                job.processed_rows, job.total_rows
            ));
        }
        let cancel = (job.status == "queued")
            .then_some(on_cancel)
            .flatten()
            .map(|cb| {
                view! {
                    <button type="button" class="tc-btn tc-btn-sm" data-target=format!("{prefix}-cancel-job")
                        on:click=move |_| cb.run(())>
                        "Cancel job"
                    </button>
                }
            });
        view! {
            <div role="status" aria-live="polite">
                <p style="margin: var(--space-xs) 0;">{text}</p>
                {known.then(|| view! {
                    <progress max=job.total_rows.to_string() value=job.processed_rows.to_string() style="width: 100%;"></progress>
                })}
            </div>
            {cancel}
        }
        .into_any()
    } else if job.status == "failed" {
        view! {
            <p role="alert" style="color: var(--error);">{job.message.clone().unwrap_or_else(|| "Failed".into())}</p>
        }
        .into_any()
    } else if job.status == "done" && job.error_count > 0 {
        let shown = job.errors.len().min(100);
        let total = job.error_count;
        let id = job.id;
        view! {
            <div data-target=format!("{prefix}-errors")>
                <p role="alert" style="font-weight: 600;">{problems_text(total)}</p>
                <ul style="max-height: 280px; overflow: auto; margin: 0; padding-left: var(--space-lg);">
                    {job.errors.iter().take(100).map(|e| {
                        let place = match &e.column {
                            Some(c) => format!("Row {}, column {}", e.row, c),
                            None => format!("Row {}", e.row),
                        };
                        view! {
                            <li data-target=format!("{prefix}-error-row")>
                                <span>{e.message.clone()}</span>
                                <span class="tc-label" style="display: block;">{place}</span>
                            </li>
                        }
                    }).collect_view()}
                </ul>
                {((total as usize) > shown).then(|| view! {
                    <p class="tc-label">{format!("Showing the first {shown} of {total} problems. The error report lists the same problems. A file with very many problems lists only the first ones: fix these and check again.")}</p>
                })}
                <button type="button" class="tc-btn tc-btn-sm" data-target=format!("{prefix}-download-errors")
                    on:click=move |_| download_errors(ctx, fb, id)>
                    "Download error report"
                </button>
            </div>
        }
        .into_any()
    } else if job.status == "done" {
        let rows = [
            (
                if planned { "To create" } else { "Created" },
                job.created,
                "created",
            ),
            (
                if planned { "To update" } else { "Updated" },
                job.updated,
                "updated",
            ),
            ("Unchanged", job.unchanged, "unchanged"),
        ];
        view! {
            <p data-target=format!("{prefix}-done")>
                {if planned { "No problems found. Nothing has been imported yet." } else { "Import complete" }}
            </p>
            <dl class="tc-form-grid" style="max-width: 360px; margin: 0;">
                {rows.into_iter().map(|(label, n, key)| view! {
                    <dt>{label}</dt>
                    <dd style="margin: 0; font-weight: 600; text-align: right;" data-target=format!("{prefix}-count-{key}")>{n}</dd>
                }).collect_view()}
            </dl>
        }
        .into_any()
    } else {
        view! { <span></span> }.into_any()
    };
    view! {
        <div data-target=format!("{prefix}-outcome")>
            <span class=badge data-target=format!("{prefix}-status")>{status}</span>
            {body}
        </div>
    }
}

/// A numbered step; without content (an earlier step is not finished) only the title shows.
#[component]
fn Step(
    number: u8,
    title: &'static str,
    done: Signal<bool>,
    active: Signal<bool>,
    children: ChildrenFn,
) -> impl IntoView {
    let heading = format!("{number}. {title}");
    view! {
        <section class="tc-card" style="margin-bottom: var(--space-md);" data-target=format!("admin-import-step-{number}")
            aria-labelledby=format!("admin-import-step-{number}-title")>
            <h3 id=format!("admin-import-step-{number}-title") style=move || if active.get() { "margin: 0;" } else { "margin: 0; color: var(--on-surface-variant);" }>
                {heading}
                {move || done.get().then(|| view! { " " <span class="tc-badge tc-badge-success">"Done"</span> })}
            </h3>
            <Show when=move || active.get()>
                <div style="margin-top: var(--space-md);">{children()}</div>
            </Show>
        </section>
    }
}

#[component]
fn FileStep(w: Wizard) -> impl IntoView {
    let on_choose = move |ev: leptos::ev::Event| {
        let gen = bump(w.upload_seq);
        begin_file_read(ev, MAX_FILE_BYTES, TOO_LARGE, move |res| {
            if !is_current(w.upload_seq, gen) {
                return;
            }
            match res {
                Ok(picked) => w.upload(picked, gen),
                Err(msg) if msg.is_empty() => {}
                Err(msg) => {
                    set_alive(w.upload_error, Some(msg));
                }
            }
        });
    };
    view! {
        <p>"CSV, Excel (XLSX) or OpenDocument (ODS) file, up to 50 MiB. The file is stored for a week."</p>
        <div class="tc-field">
            <label class="tc-label" for="admin-import-file">
                {move || if w.file.with(Option::is_some) { "Choose another file" } else { "Choose file" }}
            </label>
            <input id="admin-import-file" data-target="admin-import-file" type="file" class="tc-input"
                accept=".csv,.xlsx,.xlsm,.ods,text/csv"
                disabled=move || w.uploading.get()
                on:change=on_choose />
        </div>
        <Show when=move || w.uploading.get()>
            <p role="status">"Uploading..."</p>
        </Show>
        {move || w.upload_error.get().map(|msg| view! {
            <div class="tc-alert-error" role="alert" data-target="admin-import-upload-error">{msg}</div>
        })}
        {move || w.file.get().map(|f| view! {
            <p data-target="admin-import-file-info">
                <strong>{f.filename.clone()}</strong>
                <span class="tc-label" style="display: block;">
                    {format!("Format: {}, size: {}", format_name(&f.format), file_size(f.size_bytes))}
                </span>
            </p>
        })}
    }
}

#[component]
fn WhatStep(w: Wizard) -> impl IntoView {
    view! {
        {move || match w.entities.get() {
            None => view! { <p class="tc-label">"Loading..."</p> }.into_any(),
            Some(Err(msg)) => view! {
                <div class="tc-alert-error" role="alert">
                    {msg}
                    " "
                    <button type="button" class="tc-btn tc-btn-sm" on:click=move |_| w.load_entities()>"Retry"</button>
                </div>
            }.into_any(),
            Some(Ok(list)) if list.is_empty() => view! {
                <p role="status" data-target="admin-import-no-entities">
                    "You need the permission to write an entity, for example customers or products, to import it here."
                </p>
            }.into_any(),
            Some(Ok(list)) => view! {
                <div class="tc-field">
                    <label class="tc-label" for="admin-import-entity">"What do you import?"</label>
                    <select id="admin-import-entity" data-target="admin-import-entity" class="tc-select"
                        on:change=move |ev| w.select_entity(&event_target_value(&ev))>
                        <option value="" disabled=true selected=move || w.entity.with(Option::is_none)>"Choose..."</option>
                        {list.into_iter().map(|e| {
                            let key = e.key.clone();
                            let key_sel = key.clone();
                            view! {
                                <option value=key.clone() selected=move || w.entity.with(|c| c.as_ref().map(|c| c.key == key_sel).unwrap_or(false))>
                                    {entity_label(&key).to_string()}
                                </option>
                            }
                        }).collect_view()}
                    </select>
                </div>
            }.into_any(),
        }}
        {move || w.file.get().filter(|f| !f.sheets.is_empty()).map(|f| view! {
            <div class="tc-field" style="margin-top: var(--space-sm);">
                <label class="tc-label" for="admin-import-sheet">"Sheet"</label>
                <select id="admin-import-sheet" data-target="admin-import-sheet" class="tc-select"
                    on:change=move |ev| w.select_sheet(event_target_value(&ev))>
                    {f.sheets.into_iter().map(|s| {
                        let s_sel = s.clone();
                        let s_val = s.clone();
                        view! { <option value=s_val selected=move || w.sheet.get().as_deref() == Some(s_sel.as_str())>{s}</option> }
                    }).collect_view()}
                </select>
            </div>
        })}
        <h4 style="margin-bottom: var(--space-xs);">"Preview"</h4>
        <Show when=move || w.preview_loading.get()>
            <p class="tc-label" role="status">"Loading preview..."</p>
        </Show>
        {move || w.preview_error.get().map(|msg| view! {
            <div class="tc-alert-error" role="alert">
                {msg}
                " "
                <button type="button" class="tc-btn tc-btn-sm" on:click=move |_| w.load_preview()>"Retry"</button>
            </div>
        })}
        {move || w.preview.get().map(|p| {
            if p.columns.is_empty() {
                return view! { <p>"The file has no header row."</p> }.into_any();
            }
            let mut summary = rows_text(p.row_count);
            if (p.rows.len() as u64) < p.row_count {
                summary.push_str(&format!(". The first {} rows are shown.", p.rows.len()));
            }
            let width = p.columns.len();
            view! {
                <p data-target="admin-import-row-count">{summary}</p>
                <div class="tc-table-wrap" style="max-height: 320px; overflow: auto;">
                    <table class="tc-table" data-target="admin-import-preview">
                        <thead>
                            <tr>{p.columns.iter().map(|c| view! { <th scope="col">{c.clone()}</th> }).collect_view()}</tr>
                        </thead>
                        <tbody>
                            {p.rows.iter().map(|r| view! {
                                <tr>{(0..width).map(|i| view! { <td>{r.get(i).cloned().unwrap_or_default()}</td> }).collect_view()}</tr>
                            }).collect_view()}
                        </tbody>
                    </table>
                </div>
            }.into_any()
        })}
    }
}

#[component]
fn MappingStep(w: Wizard) -> impl IntoView {
    let show_saved = RwSignal::new(false);
    let naming = RwSignal::new(Option::<String>::None);
    let overwrite = RwSignal::new(Option::<String>::None);
    let confirm_delete = RwSignal::new(Option::<Uuid>::None);
    let check = Memo::new(move |_| w.check());

    let on_name = move |ev: SubmitEvent| {
        ev.prevent_default();
        let name = naming
            .get_untracked()
            .unwrap_or_default()
            .trim()
            .to_string();
        if name.is_empty() {
            return;
        }
        if w.saved.with_untracked(|s| s.iter().any(|m| m.name == name)) {
            overwrite.set(Some(name));
        } else {
            naming.set(None);
            w.save_mapping(name);
        }
    };

    view! {
        <div class="tc-toolbar">
            <button type="button" class="tc-btn" data-target="admin-import-saved-mappings"
                aria-expanded=move || show_saved.get().to_string()
                on:click=move |_| show_saved.update(|s| *s = !*s)>
                "Saved mappings"
            </button>
            <button type="button" class="tc-btn" data-target="admin-import-save-mapping"
                on:click=move |_| {
                    overwrite.set(None);
                    naming.set(Some(w.proposed_from.get_untracked().unwrap_or_default()));
                }>
                "Save mapping"
            </button>
        </div>
        {move || w.saved_error.get().map(|msg| view! { <div class="tc-alert-error" role="alert">{msg}</div> })}
        <Show when=move || show_saved.get()>
            <div class="tc-card" data-target="admin-import-mappings" style="margin: var(--space-sm) 0;">
                {move || {
                    let list = w.saved.get();
                    if list.is_empty() {
                        return view! { <p style="margin: 0;">"No saved mappings for this entity yet."</p> }.into_any();
                    }
                    view! {
                        <ul style="list-style: none; margin: 0; padding: 0;">
                            {list.into_iter().map(|m| {
                                let id = m.id;
                                let name = m.name.clone();
                                let use_m = m.clone();
                                let del_m = m.clone();
                                view! {
                                    <li class="tc-toolbar" data-target=format!("admin-import-mapping-{name}")>
                                        <span style="flex: 1;">{name.clone()}</span>
                                        <button type="button" class="tc-btn tc-btn-sm" data-target=format!("admin-import-mapping-use-{name}")
                                            on:click=move |_| {
                                                w.use_mapping(&use_m);
                                                show_saved.set(false);
                                            }>
                                            "Use"
                                        </button>
                                        <button type="button" class="tc-btn tc-btn-sm" aria-label=format!("Delete mapping {name}")
                                            on:click=move |_| confirm_delete.set(Some(id))>
                                            "Delete"
                                        </button>
                                        <Show when=move || confirm_delete.get() == Some(id)>
                                            {
                                                let del_m = del_m.clone();
                                                let question = format!("Delete the saved mapping {}?", del_m.name);
                                                view! {
                                                    <span role="alert">{question}</span>
                                                    <button type="button" class="tc-btn tc-btn-primary tc-btn-sm"
                                                        on:click=move |_| {
                                                            confirm_delete.set(None);
                                                            w.delete_mapping(del_m.clone());
                                                        }>
                                                        "Delete"
                                                    </button>
                                                    <button type="button" class="tc-btn tc-btn-sm" on:click=move |_| confirm_delete.set(None)>"Cancel"</button>
                                                }
                                            }
                                        </Show>
                                    </li>
                                }
                            }).collect_view()}
                        </ul>
                    }.into_any()
                }}
            </div>
        </Show>
        {move || naming.get().map(|_| view! {
            <form class="tc-toolbar" data-target="admin-import-mapping-form" on:submit=on_name style="margin: var(--space-sm) 0;">
                <label class="tc-label" for="admin-import-mapping-name">"Name of the mapping"</label>
                <input id="admin-import-mapping-name" data-target="admin-import-mapping-name" class="tc-input" type="text"
                    prop:value=move || naming.get().unwrap_or_default()
                    on:input=move |ev| naming.set(Some(event_target_value(&ev))) />
                <button type="submit" class="tc-btn tc-btn-primary tc-btn-sm" data-target="admin-import-mapping-name-ok">"Save"</button>
                <button type="button" class="tc-btn tc-btn-sm" on:click=move |_| naming.set(None)>"Cancel"</button>
            </form>
        })}
        {move || overwrite.get().map(|name| {
            let name_ok = name.clone();
            view! {
                <div class="tc-toolbar" role="alert" data-target="admin-import-overwrite">
                    <span>{format!("A mapping named {name} already exists. Replace it with the current one?")}</span>
                    <button type="button" class="tc-btn tc-btn-primary tc-btn-sm" data-target="admin-import-overwrite-confirm"
                        on:click=move |_| {
                            overwrite.set(None);
                            naming.set(None);
                            w.save_mapping(name_ok.clone());
                        }>
                        "Replace"
                    </button>
                    <button type="button" class="tc-btn tc-btn-sm" on:click=move |_| overwrite.set(None)>"Cancel"</button>
                </div>
            }
        })}
        <p class="tc-label" data-target="admin-import-proposal">
            {move || match w.proposed_from.get() {
                Some(name) => format!("Columns taken from the saved mapping {name}."),
                None => "Columns paired with fields of the same name. Check them before you continue.".into(),
            }}
        </p>
        <div data-target="admin-import-columns">
            {move || {
                let Some(entity) = w.entity.get() else { return view! { <span></span> }.into_any() };
                let Some(preview) = w.preview.get() else { return view! { <span></span> }.into_any() };
                preview.columns.iter().enumerate().map(|(i, col)| {
                    let sample = preview
                        .rows
                        .iter()
                        .filter_map(|r| r.get(i))
                        .find(|v| !v.trim().is_empty())
                        .cloned();
                    let select_id = format!("admin-import-field-{i}");
                    // A per-language family is offered as the member the file column names.
                    let options: Vec<ImportColumn> = entity
                        .columns
                        .iter()
                        .filter_map(|c| {
                            if !c.per_language {
                                return Some(c.clone());
                            }
                            family_field(c, col).map(|name| ImportColumn {
                                name,
                                ..c.clone()
                            })
                        })
                        .collect();
                    let key_column = entity.key_column.clone();
                    let dup = move || {
                        let f = w.fields.with(|f| f.get(i).cloned().flatten());
                        f.filter(|f| check.with(|c| c.as_ref().is_some_and(|c| c.duplicates.contains(f))))
                    };
                    view! {
                        <div class="tc-form-grid" style="align-items: start; margin-bottom: var(--space-sm);" data-target=format!("admin-import-row-{i}")>
                            <div>
                                <strong>{col.clone()}</strong>
                                <span class="tc-label" style="display: block;">
                                    {sample.map(|s| format!("Example: {s}")).unwrap_or_else(|| "\u{2014}".into())}
                                </span>
                            </div>
                            <div class="tc-field">
                                <label class="tc-label" for=select_id.clone()>{format!("Field for {col}")}</label>
                                <select id=select_id.clone() data-target=select_id class="tc-select"
                                    aria-invalid=move || dup().is_some().to_string()
                                    prop:value=move || w.fields.with(|f| f.get(i).cloned().flatten().unwrap_or_default())
                                    on:change=move |ev| {
                                        let v = event_target_value(&ev);
                                        w.set_field(i, (!v.is_empty()).then_some(v));
                                    }>
                                    <option value="" selected=move || w.fields.with(|f| f.get(i).cloned().flatten().is_none())>"Ignore"</option>
                                    {options.into_iter().map(|c| {
                                        let name = c.name.clone();
                                        let name_sel = name.clone();
                                        let mut label = name.clone();
                                        if name == key_column {
                                            label.push_str(" (Key)");
                                        }
                                        if c.required {
                                            label.push_str(" *");
                                        }
                                        view! {
                                            <option value=name selected=move || w.fields.with(|f| f.get(i).cloned().flatten().as_deref() == Some(name_sel.as_str()))>
                                                {label}
                                            </option>
                                        }
                                    }).collect_view()}
                                </select>
                                {move || dup().map(|f| view! {
                                    <span class="tc-label" style="color: var(--error);">{format!("The field {f} is chosen for more than one column.")}</span>
                                })}
                            </div>
                        </div>
                    }
                }).collect_view().into_any()
            }}
        </div>
        <p class="tc-label">"* Required for new records"</p>
        <div role="status" aria-live="polite" data-target="admin-import-mapping-notes">
            {move || check.get().map(|c| {
                let keys = c.missing_keys.join(", ");
                let fixed = w.fixed.get();
                view! {
                    {(!c.missing_keys.is_empty()).then(|| view! {
                        <p style="color: var(--error);" data-target="admin-import-key-missing">
                            {format!("Choose a file column for the key field(s) {keys}: rows are matched on them.")}
                        </p>
                    })}
                    {(!fixed.is_empty()).then(|| view! {
                        <p data-target="admin-import-fixed">
                            {format!(
                                "Fixed values from the saved mapping: {}",
                                fixed
                                    .iter()
                                    .map(|p| format!("{} = {}", p.field, p.value.clone().unwrap_or_default()))
                                    .collect::<Vec<_>>()
                                    .join(", ")
                            )}
                        </p>
                    })}
                    {c.duplicates.iter().map(|f| view! {
                        <p style="color: var(--error);">{format!("The field {f} is chosen for more than one column.")}</p>
                    }).collect_view()}
                    {(!c.unmapped_required.is_empty()).then(|| view! {
                        <p>{format!("Needed to create new records: {}", c.unmapped_required.join(", "))}</p>
                    })}
                    {if c.unmapped.is_empty() {
                        view! { <p data-target="admin-import-all-mapped">"Every field has a column."</p> }.into_any()
                    } else {
                        view! { <p class="tc-label">{format!("Fields without a column: {}", c.unmapped.join(", "))}</p> }.into_any()
                    }}
                }
            })}
        </div>
    }
}

#[component]
fn CheckStep(w: Wizard) -> impl IntoView {
    let busy = move || {
        w.dry
            .with(|r| r.starting || r.job.as_ref().is_some_and(ImportJob::is_active))
    };
    view! {
        <p>"Large files run in the background. You can leave this page: the job appears in the history."</p>
        <div class="tc-toolbar">
            <button type="button" class="tc-btn tc-btn-primary" data-target="admin-import-run-check"
                disabled=move || busy() || !w.mapping_ok()
                on:click=move |_| w.run(true)>
                "Check the file"
            </button>
            <Show when=move || w.dry.with(|r| r.starting)>
                <span role="status">"Checking the file..."</span>
            </Show>
        </div>
        {move || w.dry.with(|r| r.error.clone()).map(|msg| view! {
            <div class="tc-alert-error" role="alert" data-target="admin-import-check-error">{msg}</div>
        })}
        <Show when=move || w.check_outdated()>
            <p role="status" style="color: var(--warning, var(--error));" data-target="admin-import-outdated">
                "The file, entity, sheet or columns changed after this check. Run the check again."
            </p>
        </Show>
        {move || w.dry.with(|r| r.job.clone()).map(|job| view! {
            <JobOutcome job planned=true on_cancel=Callback::new(move |_| w.cancel(true)) prefix="admin-import-check" />
        })}
    }
}

#[component]
fn ApplyStep(w: Wizard) -> impl IntoView {
    let confirming = RwSignal::new(false);
    let started = move || w.apply.with(|r| r.job.is_some() || r.starting);
    let busy = move || {
        w.apply
            .with(|r| r.starting || r.job.as_ref().is_some_and(ImportJob::is_active))
    };
    view! {
        <Show when=move || !started()>
            <Show when=move || !w.checked_clean()>
                <p>"Importing is possible after a check without problems."</p>
            </Show>
            <button type="button" class="tc-btn tc-btn-primary" data-target="admin-import-apply"
                disabled=move || !w.checked_clean()
                on:click=move |_| confirming.set(true)>
                "Import now"
            </button>
        </Show>
        {move || (confirming.get() && !started()).then(|| {
            let entity = w.entity.with(|e| e.as_ref().map(|e| entity_label(&e.key).to_string()).unwrap_or_default());
            let (created, updated) = w.dry.with(|r| r.job.as_ref().map(|j| (j.created, j.updated)).unwrap_or((0, 0)));
            view! {
                <div class="tc-card" role="alertdialog" aria-labelledby="admin-import-confirm-title" data-target="admin-import-apply-confirm-box" style="margin-top: var(--space-sm);">
                    <h4 id="admin-import-confirm-title" style="margin-top: 0;">{format!("Import {entity}?")}</h4>
                    <p>{format!("{created} will be created and {updated} updated. This changes data.")}</p>
                    <Show when=move || !w.checked_clean()>
                        <p role="status" style="color: var(--error);" data-target="admin-import-apply-confirm-stale">
                            "The settings changed after the check. Run the check again before importing."
                        </p>
                    </Show>
                    <div class="tc-toolbar">
                        <button type="button" class="tc-btn tc-btn-primary" data-target="admin-import-apply-confirm"
                            disabled=move || !w.checked_clean()
                            on:click=move |_| {
                                if !w.checked_clean() {
                                    return;
                                }
                                confirming.set(false);
                                w.run(false);
                            }>
                            "Import"
                        </button>
                        <button type="button" class="tc-btn" on:click=move |_| confirming.set(false)>"Cancel"</button>
                    </div>
                </div>
            }
        })}
        <Show when=move || w.apply.with(|r| r.starting)>
            <p role="status">"Importing..."</p>
        </Show>
        {move || w.apply.with(|r| r.error.clone()).map(|msg| view! {
            <div class="tc-alert-error" role="alert" data-target="admin-import-apply-error">{msg}</div>
        })}
        {move || w.apply.with(|r| r.job.clone()).map(|job| view! {
            <JobOutcome job planned=false on_cancel=Callback::new(move |_| w.cancel(false)) prefix="admin-import-apply" />
        })}
        <Show when=move || w.apply.with(|r| r.job.is_some()) && !busy()>
            <button type="button" class="tc-btn" style="margin-top: var(--space-sm);" data-target="admin-import-another"
                on:click=move |_| w.reset()>
                "Import another file"
            </button>
        </Show>
    }
}

/// The most runs one history request may ask for (the API's cap).
const MAX_JOBS_PER_REQUEST: i64 = 200;

/// Appends the runs of `page` that `list` does not hold yet: the offsets of the history shift
/// when runs are added meanwhile, so a later page can repeat earlier runs.
pub(crate) fn push_unique(list: &mut Vec<ImportJob>, page: Vec<ImportJob>) {
    for job in page {
        if !list.iter().any(|j| j.id == job.id) {
            list.push(job);
        }
    }
}

/// The `(offset, limit)` requests that cover the newest `want` runs within the API's cap.
pub(crate) fn history_batches(want: i64) -> Vec<(i64, i64)> {
    let mut out = Vec::new();
    let mut offset = 0;
    while offset < want {
        let limit = (want - offset).min(MAX_JOBS_PER_REQUEST);
        out.push((offset, limit));
        offset += limit;
    }
    out
}

/// The newest `want` runs (fewer when there are not that many) and the total. The API has no
/// stable cursor, only offsets: the whole range is read again in batches, and read once more when
/// the total changed between batches (runs added or removed meanwhile).
async fn fetch_history(
    c: tradocraft_api_client::Client,
    want: i64,
) -> Result<(Vec<ImportJob>, i64), tradocraft_api_client::ApiError> {
    let mut attempt = 0;
    'attempt: loop {
        attempt += 1;
        let mut items = Vec::new();
        let mut total = None;
        for (offset, limit) in history_batches(want) {
            let page = c
                .list_import_jobs(&ListImportJobsParams {
                    limit: Some(limit),
                    offset: Some(offset),
                    ..ListImportJobsParams::default()
                })
                .await?;
            if attempt < 3 && total.is_some_and(|t| t != page.total) {
                continue 'attempt;
            }
            total = Some(page.total);
            let short = (page.items.len() as i64) < limit;
            push_unique(&mut items, page.items);
            if short {
                break;
            }
        }
        return Ok((items, total.unwrap_or(0)));
    }
}

/// The runs of the company, newest first, refreshed while one is queued or running.
#[component]
fn JobHistory() -> impl IntoView {
    let ctx = expect_context::<AppContext>();
    let jobs = RwSignal::new(Option::<Vec<ImportJob>>::None);
    let total = RwSignal::new(0_i64);
    let error = RwSignal::new(Option::<String>::None);
    let loading = RwSignal::new(false);
    let seq = StoredValue::new(0_u64);
    // How many runs the last request asked for: Retry repeats exactly that request, so a failed
    // "Load more" is not lost.
    let wanted = StoredValue::new(PAGE_SIZE);
    let selected = RwSignal::new(Option::<Uuid>::None);

    #[derive(Clone, Copy)]
    struct History {
        ctx: AppContext,
        jobs: RwSignal<Option<Vec<ImportJob>>>,
        total: RwSignal<i64>,
        error: RwSignal<Option<String>>,
        loading: RwSignal<bool>,
        seq: StoredValue<u64>,
        wanted: StoredValue<i64>,
    }

    impl History {
        fn shown(self) -> i64 {
            self.jobs
                .with_untracked(|j| j.as_ref().map(Vec::len).unwrap_or(0)) as i64
        }

        fn has_active(self) -> bool {
            self.jobs.with_untracked(|j| {
                j.as_ref()
                    .is_some_and(|j| j.iter().any(ImportJob::is_active))
            })
        }

        /// Loads the newest `want` runs (the whole range on screen, in batches), replacing the
        /// list, and follows active jobs; a failed refresh while a job is active is tried again
        /// after a while. Every start drops the answers and timers of earlier ones.
        fn load(self, want: i64) {
            let want = want.max(PAGE_SIZE);
            let my = bump(self.seq);
            self.wanted.set_value(want);
            self.loading.set(true);
            spawn_api(
                self.ctx,
                move |c| fetch_history(c, want),
                move |res| {
                    if !is_current(self.seq, my) || !set_alive(self.loading, false) {
                        return;
                    }
                    let follow = match res {
                        Ok((items, total)) => {
                            let active = items.iter().any(ImportJob::is_active);
                            self.error.set(None);
                            self.total.set(total);
                            self.jobs.set(Some(items));
                            active
                        }
                        Err(err) => {
                            self.error.set(Some(err.user_message()));
                            self.has_active()
                        }
                    };
                    if follow {
                        set_timeout(
                            move || {
                                if is_current(self.seq, my) {
                                    self.load(self.shown().max(want));
                                }
                            },
                            HISTORY_REFRESH,
                        );
                    }
                },
            );
        }
    }

    let h = History {
        ctx,
        jobs,
        total,
        error,
        loading,
        seq,
        wanted,
    };
    let reload = move || h.load(h.shown());
    let retry = move || h.load(wanted.try_get_value().unwrap_or(PAGE_SIZE));
    reload();

    // The next page is read together with the pages on screen, so runs added meanwhile neither
    // repeat nor push older ones out of reach.
    let load_more = move |_| h.load(h.shown() + PAGE_SIZE);

    view! {
        <div data-target="admin-import-history">
            <div class="tc-page-header" style="margin-bottom: var(--space-sm);">
                <h3 style="margin: 0;">"History"</h3>
                <button type="button" class="tc-btn" data-target="admin-import-history-refresh"
                    disabled=move || loading.get() on:click=move |_| reload()>
                    "Refresh"
                </button>
            </div>
            {move || error.get().map(|msg| view! {
                <div class="tc-alert-error" role="alert">
                    {msg}
                    " "
                    <button type="button" class="tc-btn tc-btn-sm" data-target="admin-import-history-retry" disabled=move || loading.get() on:click=move |_| retry()>"Retry"</button>
                </div>
            })}
            {move || selected.get().map(|id| view! { <JobDetail id on_close=Callback::new(move |_| selected.set(None)) on_changed=Callback::new(move |_| reload()) /> })}
            {move || match jobs.get() {
                None => view! { <p class="tc-label">"Loading..."</p> }.into_any(),
                Some(list) if list.is_empty() => view! { <p data-target="admin-import-history-empty">"No imports yet."</p> }.into_any(),
                Some(list) => view! {
                    <ul style="list-style: none; margin: 0; padding: 0;" data-target="admin-import-jobs">
                        {list.into_iter().map(|j| {
                            let id = j.id;
                            let mut meta = vec![
                                entity_label(&j.entity).to_string(),
                                if j.dry_run { "Check only".to_string() } else { "Imported".to_string() },
                                format_when(j.created_at),
                            ];
                            if let Some(n) = &j.requested_by_name {
                                meta.push(format!("By {n}"));
                            }
                            let counts = (j.status == "done" && j.error_count == 0).then(|| if j.dry_run {
                                format!("{} to create, {} to update, {} unchanged", j.created, j.updated, j.unchanged)
                            } else {
                                format!("{} created, {} updated, {} unchanged", j.created, j.updated, j.unchanged)
                            });
                            view! {
                                <li class="tc-card" style="margin-bottom: var(--space-sm);" data-target=format!("admin-import-job-{id}")>
                                    <button type="button" class="tc-btn tc-btn-ghost" style="width: 100%; text-align: left; display: block;"
                                        data-target="admin-import-history-open"
                                        aria-label=format!("Details of the import of {}", j.filename)
                                        on:click=move |_| selected.set(Some(id))>
                                        <strong>{j.filename.clone()}</strong>
                                        <span class="tc-label" style="display: block;">{meta.join(" \u{b7} ")}</span>
                                        <span class=status_badge(&j) data-target="admin-import-history-status">{job_status_label(&j)}</span>
                                        {counts.map(|c| view! { <span class="tc-label" style="display: block;" data-target="admin-import-history-counts">{c}</span> })}
                                    </button>
                                </li>
                            }
                        }).collect_view()}
                    </ul>
                }.into_any(),
            }}
            <Show when=move || jobs.with(|j| j.as_ref().is_some_and(|j| (j.len() as i64) < total.get()))>
                <button type="button" class="tc-btn" data-target="admin-import-history-more" disabled=move || loading.get() on:click=load_more>
                    "Load more"
                </button>
            </Show>
        </div>
    }
}

/// One run in full, followed while it is queued or running, with Cancel while it is queued.
#[component]
fn JobDetail(id: Uuid, on_close: Callback<()>, on_changed: Callback<()>) -> impl IntoView {
    let ctx = expect_context::<AppContext>();
    let job = RwSignal::new(Option::<ImportJob>::None);
    let error = RwSignal::new(Option::<String>::None);
    let seq = StoredValue::new(0_u64);

    fn load(
        ctx: AppContext,
        id: Uuid,
        job: RwSignal<Option<ImportJob>>,
        error: RwSignal<Option<String>>,
        seq: StoredValue<u64>,
    ) {
        let my = bump(seq);
        spawn_api(
            ctx,
            move |c| async move { c.get_import_job(id).await },
            move |res| {
                if seq.try_get_value() != Some(my) {
                    return;
                }
                let follow = match res {
                    Ok(j) => {
                        let active = j.is_active();
                        error.set(None);
                        job.set(Some(j));
                        active
                    }
                    // A failed refresh of an active job (a network blip) is tried again.
                    Err(err) => {
                        error.set(Some(err.user_message()));
                        job.with_untracked(|j| j.as_ref().is_some_and(ImportJob::is_active))
                    }
                };
                if follow {
                    set_timeout(
                        move || {
                            if is_current(seq, my) {
                                load(ctx, id, job, error, seq);
                            }
                        },
                        HISTORY_REFRESH,
                    );
                }
            },
        );
    }
    load(ctx, id, job, error, seq);

    let cancel = Callback::new(move |_| {
        spawn_api(
            ctx,
            move |c| async move { c.cancel_import_job(id).await },
            move |res| {
                // A 409 means the worker took it meanwhile; either way show what the job is now.
                if let Err(err) = &res {
                    if !set_alive(error, Some(err.user_message())) {
                        return;
                    }
                }
                if seq.try_get_value().is_some() {
                    load(ctx, id, job, error, seq);
                    if res.is_ok() {
                        on_changed.run(());
                    }
                }
            },
        );
    });

    view! {
        <div class="tc-card" role="region" aria-labelledby="admin-import-detail-title" data-target="admin-import-detail" style="margin-bottom: var(--space-md);">
            <div class="tc-page-header" style="margin-bottom: var(--space-sm);">
                <h4 id="admin-import-detail-title" style="margin: 0;">"Import details"</h4>
                <button type="button" class="tc-btn tc-btn-sm" data-target="admin-import-detail-close" on:click=move |_| on_close.run(())>"Close"</button>
            </div>
            {move || error.get().map(|msg| view! {
                <div class="tc-alert-error" role="alert">
                    {msg}
                    " "
                    <button type="button" class="tc-btn tc-btn-sm" on:click=move |_| load(ctx, id, job, error, seq)>"Retry"</button>
                </div>
            })}
            {move || match job.get() {
                None => view! { <p class="tc-label">"Loading..."</p> }.into_any(),
                Some(j) => {
                    let rows = [
                        ("What do you import?", Some(entity_label(&j.entity).to_string())),
                        ("Sheet", j.sheet.clone()),
                        ("Status", Some(if j.dry_run { "Check only".to_string() } else { "Imported".to_string() })),
                        ("By", j.requested_by_name.clone()),
                        ("Date", Some(format_when(j.created_at))),
                    ];
                    let planned = j.dry_run;
                    view! {
                        <p><strong>{j.filename.clone()}</strong></p>
                        <dl style="margin: 0 0 var(--space-sm);">
                            {rows.into_iter().filter_map(|(label, value)| value.map(|v| view! {
                                <div><dt style="display: inline; font-weight: 600;">{format!("{label}: ")}</dt><dd style="display: inline; margin: 0;">{v}</dd></div>
                            })).collect_view()}
                        </dl>
                        <JobOutcome job=j planned on_cancel=cancel prefix="admin-import-detail" />
                    }.into_any()
                }
            }}
        </div>
    }
}

#[component]
pub fn ImportsSection() -> impl IntoView {
    let ctx = expect_context::<AppContext>();
    let fb = Feedback::new();
    provide_context(fb);
    let w = Wizard::new(ctx, fb);
    w.load_entities();
    let history = RwSignal::new(false);

    let file_done = Signal::derive(move || w.file.with(Option::is_some));
    let columns_ready = Signal::derive(move || w.mappable());
    let check_ready = Signal::derive(move || w.mapping_ok());
    let checked_clean = Signal::derive(move || w.checked_clean());
    // A valid mapping with a check opens the step for a new import; a running import keeps it
    // open (progress and Cancel) whatever happens to the mapping.
    let apply_active = Signal::derive(move || {
        (w.mapping_ok() && w.dry.with(|r| r.job.is_some()))
            || w.apply
                .with(|r| r.starting || r.job.as_ref().is_some_and(ImportJob::is_active))
    });
    let applied = Signal::derive(move || {
        w.apply
            .with(|r| r.job.as_ref().is_some_and(|j| j.status == "done"))
    });

    view! {
        <section data-target="admin-import" aria-labelledby="admin-import-title">
            <h2 id="admin-import-title" class="tc-page-title" style="font-size: 18px;">"Import"</h2>
            <div class="tc-inline-tabs" role="group" aria-label="Import view" data-target="admin-import-view" style="margin-bottom: var(--space-md);">
                <button type="button" data-target="admin-import-view-new"
                    class=move || if history.get() { "tc-inline-tab-btn" } else { "tc-inline-tab-btn tc-inline-tab-active" }
                    aria-pressed=move || (!history.get()).to_string()
                    on:click=move |_| history.set(false)>
                    "New import"
                </button>
                <button type="button" data-target="admin-import-view-history"
                    class=move || if history.get() { "tc-inline-tab-btn tc-inline-tab-active" } else { "tc-inline-tab-btn" }
                    aria-pressed=move || history.get().to_string()
                    on:click=move |_| history.set(true)>
                    "History"
                </button>
            </div>
            <FeedbackView fb prefix="admin-import" />
            <Show when=move || history.get()>
                <JobHistory />
            </Show>
            // The wizard stays mounted while the history is shown, so its state and polling survive.
            <div style:display=move || if history.get() { "none" } else { "block" } style="max-width: 960px;">
                <Step number=1 title="File" done=file_done active=Signal::derive(|| true)>
                    <FileStep w />
                </Step>
                <Step number=2 title="What and where" done=columns_ready active=file_done>
                    <WhatStep w />
                </Step>
                <Step number=3 title="Columns" done=check_ready active=columns_ready>
                    <MappingStep w />
                </Step>
                <Step number=4 title="Check" done=checked_clean active=check_ready>
                    <CheckStep w />
                </Step>
                <Step number=5 title="Import" done=applied active=apply_active>
                    <ApplyStep w />
                </Step>
            </div>
        </section>
    }
}

#[cfg(test)]
mod tests {
    use chrono::DateTime;
    use tradocraft_api_client::imports::{ColumnKind, ImportColumn};

    use super::*;

    fn entity() -> ImportDescription {
        let col = |name: &str, required: bool| ImportColumn {
            name: name.into(),
            kind: ColumnKind::Text,
            required,
            per_language: false,
        };
        ImportDescription {
            key: "customers".into(),
            audit_entity: "customer".into(),
            key_column: "code".into(),
            key_columns: vec!["code".into()],
            file_stem: "customers".into(),
            columns: vec![col("code", true), col("name", true), col("city", false)],
        }
    }

    fn mapping(name: &str, pairs: &[(&str, &str)]) -> ImportMapping {
        ImportMapping {
            id: Uuid::new_v4(),
            entity: "customers".into(),
            name: name.into(),
            columns: pairs
                .iter()
                .map(|(c, f)| ColumnPair::column(c.to_string(), f.to_string()))
                .collect(),
            created_at: DateTime::UNIX_EPOCH,
            updated_at: DateTime::UNIX_EPOCH,
        }
    }

    fn header(cols: &[&str]) -> Vec<String> {
        cols.iter().map(|c| c.to_string()).collect()
    }

    fn some(f: &str) -> Option<String> {
        Some(f.to_string())
    }

    #[test]
    fn pairs_by_name_case_insensitively_and_once() {
        let fields = same_name_fields(&header(&[" Code ", "NAME", "name", "extra"]), &entity());
        assert_eq!(fields, vec![some("code"), some("name"), None, None]);
    }

    #[test]
    fn prefers_the_saved_mapping_covering_most_columns() {
        let h = header(&["Klantnr", "Naam", "Stad"]);
        let small = mapping("small", &[("klantnr", "code")]);
        let big = mapping("big", &[("Klantnr", "code"), ("naam", "name")]);
        let misfit = mapping("misfit", &[("Klantnr", "code"), ("Land", "country")]);
        let saved = [small, big, misfit];
        assert_eq!(best_saved_mapping(&h, &saved).unwrap().name, "big");
        let (fields, from) = propose_mapping(&h, &entity(), &saved);
        assert_eq!(fields, vec![some("code"), some("name"), None]);
        assert_eq!(from.as_deref(), Some("big"));
        let (fields, from) = propose_mapping(&header(&["code", "name"]), &entity(), &[]);
        assert_eq!(fields, vec![some("code"), some("name")]);
        assert_eq!(from, None);
    }

    #[test]
    fn saved_mapping_skips_vanished_fields() {
        let m = mapping("m", &[("A", "code"), ("B", "gone"), ("a", "name")]);
        assert_eq!(
            fields_from_mapping(&header(&["a", "b"]), &entity(), &m),
            vec![some("code"), None]
        );
    }

    #[test]
    fn check_finds_missing_key_duplicates_and_unmapped() {
        let c = check_mapping(&[some("name"), some("name"), None], &[], &entity());
        assert_eq!(c.missing_keys, ["code"]);
        assert_eq!(c.duplicates, vec!["name"]);
        assert_eq!(c.unmapped, vec!["code", "city"]);
        assert_eq!(c.unmapped_required, vec!["code"]);
        assert!(c.blocked());
        let ok = check_mapping(&[some("code"), some("name"), some("city")], &[], &entity());
        assert!(!ok.blocked() && ok.unmapped.is_empty());
    }

    #[test]
    fn identity_header_sends_no_columns() {
        let h = header(&["code", "name"]);
        assert_eq!(
            columns_to_send(&h, &[some("code"), some("name")], &[]),
            None
        );
        let pairs =
            columns_to_send(&header(&["Klantnr", "x"]), &[some("code"), None], &[]).unwrap();
        assert_eq!(pairs.len(), 1);
        assert_eq!(pairs[0].column.as_deref(), Some("Klantnr"));
        // Ignoring a column is not the identity either.
        assert!(columns_to_send(&h, &[some("code"), None], &[]).is_some());
    }

    #[test]
    fn signature_changes_with_every_setting() {
        let id = Uuid::nil();
        let a = run_signature(id, "customers", None, None);
        assert_ne!(a, run_signature(id, "products", None, None));
        assert_ne!(a, run_signature(id, "customers", Some("Sheet1"), None));
        let pairs = [ColumnPair::column("A", "code")];
        assert_ne!(a, run_signature(id, "customers", None, Some(&pairs)));
        assert_eq!(a, run_signature(id, "customers", None, None));
    }

    fn job(n: u8) -> ImportJob {
        serde_json::from_str(&format!(
            r#"{{"id":"00000000-0000-0000-0000-0000000000{n:02}","entity":"customers","filename":"c.csv",
            "format":"csv","dry_run":true,"status":"done","total_rows":0,"processed_rows":0,
            "created":0,"updated":0,"unchanged":0,"error_count":0,"errors":[],
            "created_at":"2026-11-26T10:00:00Z"}}"#
        ))
        .unwrap()
    }

    #[test]
    fn history_batches_stay_within_the_cap() {
        assert_eq!(history_batches(50), vec![(0, 50)]);
        assert_eq!(history_batches(200), vec![(0, 200)]);
        assert_eq!(history_batches(450), vec![(0, 200), (200, 200), (400, 50)]);
        assert!(history_batches(0).is_empty());
    }

    #[test]
    fn shifted_pages_do_not_repeat_runs() {
        let mut list = vec![job(1), job(2)];
        push_unique(&mut list, vec![job(2), job(3)]);
        let ids: Vec<_> = list.iter().map(|j| j.id.as_u128()).collect();
        assert_eq!(ids, vec![1, 2, 3]);
    }

    #[test]
    fn status_labels_tell_errors_apart() {
        let mut j: ImportJob = serde_json::from_str(
            r#"{"id":"00000000-0000-0000-0000-000000000001","entity":"customers","filename":"c.csv",
            "format":"csv","dry_run":true,"status":"done","total_rows":2,"processed_rows":2,
            "created":1,"updated":1,"unchanged":0,"error_count":0,"errors":[],
            "created_at":"2026-11-26T10:00:00Z"}"#,
        )
        .unwrap();
        assert_eq!(job_status_label(&j), "Done");
        j.error_count = 3;
        assert_eq!(job_status_label(&j), "Done with 3 errors");
        j.status = "queued".into();
        assert!(j.is_active());
        assert_eq!(job_status_label(&j), "Queued");
    }

    #[test]
    fn a_per_language_family_takes_the_member_the_file_names() {
        let mut e = entity();
        e.columns.push(ImportColumn {
            name: "name".into(),
            kind: ColumnKind::Text,
            required: false,
            per_language: true,
        });
        let family = e.columns.last().unwrap().clone();
        assert_eq!(family_field(&family, " Name_FR "), Some("name_fr".into()));
        assert_eq!(family_field(&family, "name"), None);
        assert_eq!(family_field(&family, "name_fra"), None);
        let header = [
            "code".to_string(),
            "name_it".to_string(),
            "name".to_string(),
        ];
        assert_eq!(
            same_name_fields(&header, &e),
            [
                Some("code".into()),
                Some("name_it".into()),
                Some("name".into())
            ]
        );
        let check = check_mapping(&[Some("code".into())], &[], &e);
        assert!(check.missing_keys.is_empty());
        // The family is never "unmapped": a file has any number of its members.
        assert_eq!(check.unmapped, ["name", "city"]);
    }

    fn value(value: &str, field: &str) -> ColumnPair {
        ColumnPair {
            column: None,
            value: Some(value.into()),
            field: field.into(),
        }
    }

    #[test]
    fn fixed_values_of_a_saved_mapping_are_kept_and_sent() {
        let mut m = mapping("with fixed", &[("Nr", "code")]);
        m.columns.push(value("Gent", "city"));
        m.columns.push(value("x", "gone"));
        let e = entity();
        let fixed = fixed_from_mapping(&e, &m);
        assert_eq!(fixed, [value("Gent", "city")]);
        // A mapping of only fixed values and covered columns is still proposed.
        assert!(best_saved_mapping(&header(&["nr"]), std::slice::from_ref(&m)).is_some());
        let sent = columns_to_send(&header(&["code"]), &[some("code")], &fixed).unwrap();
        assert_eq!(
            sent,
            [ColumnPair::column("code", "code"), value("Gent", "city")]
        );
        let id = Uuid::nil();
        assert_ne!(
            run_signature(id, "customers", None, Some(&sent)),
            run_signature(id, "customers", None, Some(&sent[..1]))
        );
        // A fixed key counts as mapped; a field with both a column and a value is doubled.
        let c = check_mapping(&[some("name")], &[value("C1", "code")], &e);
        assert!(c.missing_keys.is_empty());
        let c = check_mapping(&[some("city")], &fixed, &e);
        assert_eq!(c.duplicates, ["city"]);
    }

    #[test]
    fn the_missing_key_parts_are_named() {
        let mut e = entity();
        e.key_columns = vec!["code".into(), "zone".into(), "valid_from".into()];
        let c = check_mapping(&[some("code"), some("zone")], &[], &e);
        assert_eq!(c.missing_keys, ["valid_from"]);
        e.key_columns.clear();
        let c = check_mapping(&[some("name")], &[], &e);
        assert_eq!(c.missing_keys, ["code"], "falls back to key_column");
    }
}
