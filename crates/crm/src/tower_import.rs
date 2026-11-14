//! Import of a tower configurator export into an opportunity's baseline (ADR 0068).
//!
//! The tower configurator is a separate application that already holds the bell data of a
//! project. We only read its JSON export and map it onto the generic baseline mechanism. This
//! module is the one place that knows that format; the pure part (`plan`) maps a document to a
//! plan without touching the database, the handlers further down write or preview the plan.

use axum::body::Bytes;
use axum::extract::{Path, Query, State};
use axum::Json;
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use std::collections::BTreeMap;
use tradocraft_core::{audit, new_id, AppError, AppResult, AppState, CurrentUser, Permission};
use tradocraft_products::attribute_definitions::{active_for_scope, AttributeDefinition};
use utoipa::{IntoParams, ToSchema};
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::baseline::{check_opportunity, check_parent_type, validate_values, MAX_ITEMS};
use crate::baseline_types;

type ErrorBody = tradocraft_core::error::ErrorBody;

const DEFAULT_SOURCE_ID: &str = "tower_configurator";
const MAX_SOURCE_ID: usize = 100;
/// A tower configurator export with a few hundred bells is well below this.
const MAX_BODY_BYTES: usize = 4 * 1024 * 1024;

/// Something in the source that could not be used as is. The import carries on.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, ToSchema)]
pub struct ImportWarning {
    /// Identifier of the bell, `None` for a warning about the document.
    pub bell: Option<String>,
    /// Source field the warning is about.
    pub field: String,
    pub message: String,
}

/// A source field that has no baseline attribute. It is kept in the item's `source_data`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, ToSchema)]
pub struct UnmappedField {
    /// `bells[].properties.<name>`, `bells[].<name>` or a top-level section name.
    pub field: String,
    /// How many bells carry it (1 for a top-level section).
    pub count: usize,
}

#[derive(Debug, Clone, PartialEq)]
pub struct PlannedBell {
    pub name: String,
    pub values: Map<String, Value>,
    /// The bell object as received.
    pub source: Value,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ImportPlan {
    pub group_name: String,
    /// The document without `bells`.
    pub group_source: Value,
    pub bells: Vec<PlannedBell>,
    pub warnings: Vec<ImportWarning>,
    pub unmapped: Vec<UnmappedField>,
}

/// Properties that are mapped (read by `plan`); everything else is reported as unmapped.
const MAPPED_PROPERTIES: [&str; 11] = [
    "note",
    "weight",
    "weight_g",
    "weight_unit",
    "diameter",
    "diameter_mm",
    "diameter_unit",
    "height",
    "height_mm",
    "height_unit",
    "motion",
];
const DEFAULT_GROUP_NAME: &str = "Tower configurator import";
const MAX_NAME: usize = 200;

/// A text value of the source; `None` for absent, non-text, blank and `NOT_SET`.
fn set_text(v: Option<&Value>) -> Option<String> {
    let s = match v? {
        Value::String(s) => s.trim().to_string(),
        Value::Number(n) => n.to_string(),
        _ => return None,
    };
    (!s.is_empty() && s != "NOT_SET").then_some(s)
}

/// Splits "220.0 kg" into the number and the unit text (which may be empty). `Err` when there is
/// no number in front.
fn split_quantity(text: &str) -> Result<(f64, String), ()> {
    let text = text.trim();
    let end = text
        .char_indices()
        .find(|(_, c)| !(c.is_ascii_digit() || matches!(c, '.' | '-' | '+' | 'e' | 'E' | ',')))
        .map_or(text.len(), |(i, _)| i);
    // "1.5e" would take the unit's first letter; back off when the number does not parse.
    let mut end = end;
    loop {
        let number = text[..end].replace(',', ".");
        if let Ok(n) = number.parse::<f64>() {
            return Ok((n, text[end..].trim().to_lowercase()));
        }
        if end == 0 {
            return Err(());
        }
        end -= 1;
    }
}

fn round3(n: f64) -> f64 {
    (n * 1000.0).round() / 1000.0
}

/// Factor to the target unit, `None` when the unit is not known.
fn factor(unit: &str, table: &[(&str, f64)]) -> Option<f64> {
    table.iter().find(|(u, _)| *u == unit).map(|(_, f)| *f)
}

const WEIGHT_TO_KG: [(&str, f64); 4] = [
    ("kg", 1.0),
    ("g", 0.001),
    ("t", 1000.0),
    ("lb", 0.453_592_37),
];
const LENGTH_TO_MM: [(&str, f64); 3] = [("mm", 1.0), ("cm", 10.0), ("m", 1000.0)];

/// Reads a quantity of the source in the target unit: the exact `<name>_<suffix>` field when it is
/// there, else the text field `<name>` ("220.0 kg") with its own unit or `<name>_unit`.
/// `Ok(None)` is "not set", `Err` carries the message and the source field that was read.
fn quantity(
    props: &Map<String, Value>,
    name: &str,
    exact: &str,
    exact_factor: f64,
    table: &[(&str, f64)],
    default_unit: &str,
) -> Result<Option<f64>, (String, String)> {
    let bad = |field: &str, v: &str| {
        (
            field.to_string(),
            format!("{field} \"{v}\" is not a positive number in a known unit"),
        )
    };
    if let Some(text) = set_text(props.get(exact)) {
        match text.replace(',', ".").parse::<f64>() {
            Ok(n) if n.is_finite() && n > 0.0 => return Ok(Some(round3(n * exact_factor))),
            _ => return Err(bad(name, &text)),
        }
    }
    let Some(text) = set_text(props.get(name)) else {
        return Ok(None);
    };
    let (n, unit) = split_quantity(&text).map_err(|()| bad(name, &text))?;
    let unit = if unit.is_empty() {
        set_text(props.get(&format!("{name}_unit")))
            .map(|u| u.to_lowercase())
            .unwrap_or_else(|| default_unit.to_string())
    } else {
        unit
    };
    match factor(&unit, table) {
        Some(f) if n.is_finite() && n > 0.0 => Ok(Some(round3(n * f))),
        _ => Err(bad(name, &text)),
    }
}

/// Lowercase letters and digits only, without a trailing "rpm".
fn normalise_name(s: &str) -> String {
    let n: String = s
        .to_lowercase()
        .chars()
        .filter(|c| c.is_alphanumeric())
        .collect();
    n.strip_suffix("rpm").map_or(n.clone(), str::to_string)
}

/// The option of a select definition whose value or label equals `source` (see `normalise_name`).
fn match_option(def: &AttributeDefinition, source: &str) -> Option<String> {
    let want = normalise_name(source);
    def.options
        .iter()
        .find(|o| normalise_name(&o.value) == want || normalise_name(&o.label) == want)
        .map(|o| o.value.clone())
}

/// Counts of the keys of every bell's object (`prefix.<key>`) that are not mapped.
fn count_unmapped(
    counts: &mut BTreeMap<String, usize>,
    prefix: &str,
    obj: &Map<String, Value>,
    mapped: &[&str],
) {
    for k in obj.keys().filter(|k| !mapped.contains(&k.as_str())) {
        *counts.entry(format!("{prefix}.{k}")).or_default() += 1;
    }
}

pub fn plan(doc: &Value, defs: &[AttributeDefinition]) -> Result<ImportPlan, String> {
    let root = doc
        .as_object()
        .ok_or("the file must contain a JSON object (a tower configurator export)")?;
    let source_bells = root
        .get("bells")
        .and_then(Value::as_array)
        .ok_or("the file has no \"bells\" list; it is not a tower configurator export")?;

    let mut group_source = root.clone();
    group_source.remove("bells");
    let text_of = |section: &str| set_text(root.get(section).and_then(|s| s.get("name")));
    let group_name = text_of("location")
        .or_else(|| text_of("customer"))
        .unwrap_or_else(|| DEFAULT_GROUP_NAME.to_string());
    let group_name: String = group_name.chars().take(MAX_NAME).collect();

    let brand_text = set_text(root.get("customer").and_then(|c| c.get("rotary_motor")));
    let mut warnings = Vec::new();
    let mut unmapped_props: BTreeMap<String, usize> = BTreeMap::new();
    let mut other_bell_fields: BTreeMap<String, usize> = BTreeMap::new();
    let mut bells = Vec::with_capacity(source_bells.len());

    for (index, sb) in source_bells.iter().enumerate() {
        let obj = sb.as_object();
        let identifier = obj.and_then(|o| set_text(o.get("identifier")));
        let name: String = identifier
            .clone()
            .unwrap_or_else(|| format!("Bell {}", index + 1))
            .chars()
            .take(MAX_NAME)
            .collect();
        let label = Some(name.clone());
        let mut warn = |field: &str, message: String| {
            warnings.push(ImportWarning {
                bell: label.clone(),
                field: field.to_string(),
                message,
            });
        };

        let mut candidates: Vec<(&str, Value)> = Vec::new();
        match obj
            .and_then(|o| o.get("properties"))
            .and_then(Value::as_object)
        {
            None => warn("properties", "the bell has no properties object".into()),
            Some(props) => {
                count_unmapped(
                    &mut unmapped_props,
                    "bells[].properties",
                    props,
                    &MAPPED_PROPERTIES,
                );
                if let Some(note) = set_text(props.get("note")) {
                    candidates.push(("note", Value::String(note)));
                }
                for (key, name_in_source, exact, exact_factor, table, default_unit) in [
                    (
                        "weight_kg",
                        "weight",
                        "weight_g",
                        0.001,
                        &WEIGHT_TO_KG[..],
                        "kg",
                    ),
                    (
                        "diameter_mm",
                        "diameter",
                        "diameter_mm",
                        1.0,
                        &LENGTH_TO_MM[..],
                        "mm",
                    ),
                    (
                        "height_mm",
                        "height",
                        "height_mm",
                        1.0,
                        &LENGTH_TO_MM[..],
                        "mm",
                    ),
                ] {
                    match quantity(
                        props,
                        name_in_source,
                        exact,
                        exact_factor,
                        table,
                        default_unit,
                    ) {
                        Ok(Some(n)) => candidates.push((key, Value::from(n))),
                        Ok(None) => {}
                        Err((field, message)) => warn(&field, message),
                    }
                }
                if let Some(motion) = set_text(props.get("motion")) {
                    let value = defs
                        .iter()
                        .find(|d| d.key == "motion")
                        .and_then(|d| match_option(d, &motion))
                        .unwrap_or_else(|| motion.to_lowercase());
                    candidates.push(("motion", Value::String(value)));
                }
                match set_text(props.get("motor")).as_deref() {
                    Some("linear") => warn(
                        "motor",
                        "linear motor: the motor brand is not set, rotating-motor rules do not apply".into(),
                    ),
                    Some("rotating") => {
                        if let Some(brand) = &brand_text {
                            // Without a definition the raw text is offered, so the missing
                            // definition is reported like for every other attribute.
                            match defs.iter().find(|d| d.key == "motor_brand") {
                                None => candidates.push(("motor_brand", Value::String(brand.clone()))),
                                Some(d) => match match_option(d, brand) {
                                    Some(v) => candidates.push(("motor_brand", Value::String(v))),
                                    None => warn(
                                        "customer.rotary_motor",
                                        format!("motor brand \"{brand}\" is not one of the known brands"),
                                    ),
                                },
                            }
                        }
                    }
                    _ => {}
                }
            }
        }
        if let Some(o) = obj {
            count_unmapped(
                &mut other_bell_fields,
                "bells[]",
                o,
                &["identifier", "properties"],
            );
        }

        let mut values = Map::new();
        for (key, v) in candidates {
            let one = serde_json::json!({ key: v });
            match validate_values(defs, &one) {
                Ok(mut ok) => values.extend(std::mem::take(&mut ok)),
                Err(e) => {
                    let field = if key == "weight_kg" {
                        "weight"
                    } else {
                        key.trim_end_matches("_kg").trim_end_matches("_mm")
                    };
                    warn(field, e)
                }
            }
        }
        bells.push(PlannedBell {
            name,
            values,
            source: sb.clone(),
        });
    }

    let mut unmapped: Vec<UnmappedField> = group_source
        .keys()
        .map(|k| UnmappedField {
            field: k.clone(),
            count: 1,
        })
        .collect();
    unmapped.extend(
        other_bell_fields
            .into_iter()
            .chain(unmapped_props)
            .map(|(field, count)| UnmappedField { field, count }),
    );
    Ok(ImportPlan {
        group_name,
        group_source: Value::Object(group_source),
        bells,
        warnings,
        unmapped,
    })
}

#[derive(Debug, Deserialize, IntoParams)]
struct ImportQuery {
    /// `true` returns the preview and writes nothing.
    #[serde(default)]
    dry_run: bool,
    /// Identifies the source; an import replaces the items of the same source in the
    /// opportunity. Default `tower_configurator`, at most 100 characters.
    source_id: Option<String>,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct ImportCounts {
    pub bell_group: usize,
    pub bell: usize,
    pub clock_dial: usize,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct ImportPreviewItem {
    pub type_code: String,
    pub name: String,
    /// Mapped attribute values keyed by definition key.
    #[schema(value_type = Object)]
    pub values: Value,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct BaselineImportReport {
    pub dry_run: bool,
    pub source_id: String,
    /// Items of the same source that are (dry run) or were replaced.
    pub replaced: usize,
    pub created: ImportCounts,
    /// The group first, then its bells.
    pub items: Vec<ImportPreviewItem>,
    pub warnings: Vec<ImportWarning>,
    pub unmapped_fields: Vec<UnmappedField>,
}

fn source_id(q: &Option<String>) -> AppResult<String> {
    let Some(raw) = q else {
        return Ok(DEFAULT_SOURCE_ID.to_string());
    };
    let id = raw.trim();
    if id.is_empty() || id.chars().count() > MAX_SOURCE_ID {
        return Err(AppError::Validation(format!(
            "source_id must be 1 to {MAX_SOURCE_ID} characters"
        )));
    }
    Ok(id.to_string())
}

async fn active_type(
    conn: &mut sqlx::PgConnection,
    company_id: Uuid,
    code: &str,
) -> AppResult<baseline_types::BaselineItemType> {
    let ty = baseline_types::find_by_code_shared(conn, company_id, code)
        .await?
        .filter(|t| t.active)
        .ok_or_else(|| {
            AppError::Validation(format!("baseline item type {code} is missing or inactive"))
        })?;
    Ok(ty)
}

/// Previews (`dry_run=true`) or runs the import of a tower configurator export (the JSON as the
/// body) into the baseline: one bell group named from the source holding one bell per source
/// bell. Items of the same source that an earlier import created are replaced; items entered by
/// hand are never removed (those inside a replaced group move to the top level).
#[utoipa::path(post, path = "/opportunities/{id}/baseline/import", tag = "crm",
    params(("id" = Uuid, Path), ImportQuery),
    request_body(content = Value, content_type = "application/json"),
    responses((status = 200, body = BaselineImportReport), (status = 404, body = ErrorBody),
        (status = 422, body = ErrorBody)))]
async fn import_baseline(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(opportunity_id): Path<Uuid>,
    Query(q): Query<ImportQuery>,
    body: Bytes,
) -> AppResult<Json<BaselineImportReport>> {
    user.require(Permission::OpportunitiesWrite)?;
    let source = source_id(&q.source_id)?;
    let doc: Value = serde_json::from_slice(&body)
        .map_err(|e| AppError::Validation(format!("the file is not valid JSON: {e}")))?;

    let mut tx = state.db.begin().await?;
    check_opportunity(&mut tx, user.company_id, opportunity_id, !q.dry_run).await?;
    let group_type = active_type(&mut tx, user.company_id, "bell_group").await?;
    let bell_type = active_type(&mut tx, user.company_id, "bell").await?;
    check_parent_type(&[], group_type.allow_top_level, None).map_err(AppError::Validation)?;
    check_parent_type(
        &bell_type.allowed_parent_codes,
        bell_type.allow_top_level,
        Some("bell_group"),
    )
    .map_err(AppError::Validation)?;
    let defs = active_for_scope(&mut tx, user.company_id, "bell").await?;
    let plan = plan(&doc, &defs).map_err(AppError::Validation)?;

    let (total, replaced): (i64, i64) = sqlx::query_as(
        "SELECT count(*), count(*) FILTER (WHERE import_source = $2)
         FROM crm.opportunity_baseline_items WHERE opportunity_id = $1",
    )
    .bind(opportunity_id)
    .bind(&source)
    .fetch_one(&mut *tx)
    .await?;
    let (total, replaced) = (total as usize, replaced as usize);
    if total - replaced + 1 + plan.bells.len() > MAX_ITEMS {
        return Err(AppError::Validation(format!(
            "an opportunity holds at most {MAX_ITEMS} baseline items; the import would exceed it"
        )));
    }

    let mut items = vec![ImportPreviewItem {
        type_code: group_type.code.clone(),
        name: plan.group_name.clone(),
        values: Value::Object(Map::new()),
    }];
    items.extend(plan.bells.iter().map(|b| ImportPreviewItem {
        type_code: bell_type.code.clone(),
        name: b.name.clone(),
        values: Value::Object(b.values.clone()),
    }));
    let report = BaselineImportReport {
        dry_run: q.dry_run,
        source_id: source.clone(),
        replaced,
        created: ImportCounts {
            bell_group: 1,
            bell: plan.bells.len(),
            clock_dial: 0,
        },
        items,
        warnings: plan.warnings.clone(),
        unmapped_fields: plan.unmapped.clone(),
    };
    if q.dry_run {
        return Ok(Json(report));
    }

    // Hand-entered items inside a replaced item move to the top level; they are never deleted.
    let stuck: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM crm.opportunity_baseline_items c
         JOIN crm.opportunity_baseline_items p ON p.opportunity_id = c.opportunity_id AND p.id = c.parent_id
         JOIN crm.baseline_item_types t ON t.company_id = c.company_id AND t.code = c.type_code
         WHERE c.opportunity_id = $1 AND p.import_source = $2 AND c.import_source IS DISTINCT FROM $2
           AND NOT t.allow_top_level",
    )
    .bind(opportunity_id)
    .bind(&source)
    .fetch_one(&mut *tx)
    .await?;
    if stuck > 0 {
        return Err(AppError::Validation(
            "items entered by hand inside the imported items cannot move to the top level; \
             move or delete them first"
                .into(),
        ));
    }
    sqlx::query(
        "UPDATE crm.opportunity_baseline_items c SET parent_id = NULL, updated_at = now()
         FROM crm.opportunity_baseline_items p
         WHERE c.opportunity_id = $1 AND p.opportunity_id = c.opportunity_id AND p.id = c.parent_id
           AND p.import_source = $2 AND c.import_source IS DISTINCT FROM $2",
    )
    .bind(opportunity_id)
    .bind(&source)
    .execute(&mut *tx)
    .await?;
    sqlx::query(
        "DELETE FROM crm.opportunity_baseline_items WHERE opportunity_id = $1 AND import_source = $2",
    )
    .bind(opportunity_id)
    .bind(&source)
    .execute(&mut *tx)
    .await?;

    let insert = "INSERT INTO crm.opportunity_baseline_items
            (id, company_id, opportunity_id, parent_id, type_code, name, quantity, \"values\",
             sort_order, import_source, source_data)
         VALUES ($1, $2, $3, $4, $5, $6, 1, $7, $8, $9, $10)";
    let group_id = new_id();
    sqlx::query(insert)
        .bind(group_id)
        .bind(user.company_id)
        .bind(opportunity_id)
        .bind(None::<Uuid>)
        .bind(&group_type.code)
        .bind(&plan.group_name)
        .bind(Value::Object(Map::new()))
        .bind(0)
        .bind(&source)
        .bind(&plan.group_source)
        .execute(&mut *tx)
        .await?;
    for (i, bell) in plan.bells.iter().enumerate() {
        sqlx::query(insert)
            .bind(new_id())
            .bind(user.company_id)
            .bind(opportunity_id)
            .bind(Some(group_id))
            .bind(&bell_type.code)
            .bind(&bell.name)
            .bind(Value::Object(bell.values.clone()))
            .bind(i as i32)
            .bind(&source)
            .bind(&bell.source)
            .execute(&mut *tx)
            .await?;
    }
    audit::record(
        &mut tx,
        &user,
        "opportunity",
        opportunity_id,
        "baseline_imported",
        serde_json::json!({ "source_id": source, "replaced": replaced,
            "bells": plan.bells.len(), "warnings": plan.warnings.len() }),
    )
    .await?;
    tx.commit().await?;
    Ok(Json(report))
}

/// The source of an imported item as it was received (the whole bell, or the document without
/// its bells for the group). 404 for an item entered by hand.
#[utoipa::path(get, path = "/opportunities/{id}/baseline/items/{item_id}/source", tag = "crm",
    params(("id" = Uuid, Path), ("item_id" = Uuid, Path)),
    responses((status = 200, body = Object), (status = 404, body = ErrorBody)))]
async fn get_source(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((opportunity_id, item_id)): Path<(Uuid, Uuid)>,
) -> AppResult<Json<Value>> {
    user.require(Permission::OpportunitiesRead)?;
    let mut conn = state.db.acquire().await?;
    check_opportunity(&mut conn, user.company_id, opportunity_id, false).await?;
    let data: Option<Option<Value>> = sqlx::query_scalar(
        "SELECT source_data FROM crm.opportunity_baseline_items WHERE id = $1 AND opportunity_id = $2",
    )
    .bind(item_id)
    .bind(opportunity_id)
    .fetch_optional(&mut *conn)
    .await?;
    data.flatten()
        .map(Json)
        .ok_or(AppError::NotFound("imported source"))
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(import_baseline))
        .layer(axum::extract::DefaultBodyLimit::max(MAX_BODY_BYTES))
        .routes(routes!(get_source))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use tradocraft_products::attribute_definitions::{DefinitionKind, SelectOption};
    use uuid::Uuid;

    fn def(key: &str, kind: DefinitionKind, options: &[(&str, &str)]) -> AttributeDefinition {
        AttributeDefinition {
            id: Uuid::nil(),
            key: key.into(),
            label: key.into(),
            kind,
            unit: None,
            options: options
                .iter()
                .map(|(v, l)| SelectOption {
                    value: (*v).into(),
                    label: (*l).into(),
                })
                .collect(),
            scope: "bell".into(),
            sort_order: 0,
            active: true,
        }
    }

    fn defs() -> Vec<AttributeDefinition> {
        use DefinitionKind::*;
        vec![
            def("weight_kg", Number, &[]),
            def("diameter_mm", Number, &[]),
            def("height_mm", Number, &[]),
            def("note", Text, &[]),
            def(
                "motion",
                Select,
                &[
                    ("flying", "Flying"),
                    ("falling", "Falling"),
                    ("balanced", "Balanced"),
                ],
            ),
            def(
                "motor_brand",
                Select,
                &[
                    ("mez_1000", "MEZ 1000"),
                    ("adda_750", "ADDA 750"),
                    ("de_coster_1000", "DE COSTER 1000"),
                ],
            ),
        ]
    }

    fn bell(id: &str, props: Value) -> Value {
        json!({"identifier": id, "properties": props, "field_states": {}, "subdivision": "Tower"})
    }

    fn doc(bells: Vec<Value>) -> Value {
        json!({"customer": {"name": "Parish", "rotary_motor": "ADDA 750"},
               "location": {"name": "St Mary", "country": "BE"},
               "bells": bells, "topology": {"nodes": []}})
    }

    fn plan_ok(d: &Value) -> ImportPlan {
        plan(d, &defs()).unwrap()
    }

    #[test]
    fn a_bell_maps_name_and_attributes() {
        let d = doc(vec![bell(
            "bell_1",
            json!({"note": "B1", "weight": "320.0 kg", "weight_g": "320000", "diameter_mm": "824",
                   "height_mm": "646", "motion": "flying", "motor": "rotating"}),
        )]);
        let p = plan_ok(&d);
        assert_eq!(p.group_name, "St Mary");
        assert_eq!(p.bells.len(), 1);
        let b = &p.bells[0];
        assert_eq!(b.name, "bell_1");
        assert_eq!(
            Value::Object(b.values.clone()),
            json!({"note": "B1", "weight_kg": 320.0, "diameter_mm": 824.0, "height_mm": 646.0,
                   "motion": "flying", "motor_brand": "adda_750"})
        );
        assert!(p.warnings.is_empty(), "{:?}", p.warnings);
        assert_eq!(b.source["properties"]["weight"], "320.0 kg");
        assert!(p.group_source.get("bells").is_none());
        assert_eq!(p.group_source["customer"]["name"], "Parish");
    }

    #[test]
    fn weight_falls_back_to_the_text_with_its_unit() {
        let d = doc(vec![
            bell("a", json!({"weight": "1.5 t"})),
            bell("b", json!({"weight": "500", "weight_unit": "g"})),
            bell("c", json!({"weight": "100 lb"})),
        ]);
        let p = plan_ok(&d);
        assert_eq!(p.bells[0].values["weight_kg"], json!(1500.0));
        assert_eq!(p.bells[1].values["weight_kg"], json!(0.5));
        assert_eq!(p.bells[2].values["weight_kg"], json!(45.359));
    }

    #[test]
    fn sizes_convert_from_their_unit() {
        let d = doc(vec![bell(
            "a",
            json!({"diameter": "0.8 m", "height": "64.6 cm"}),
        )]);
        let p = plan_ok(&d);
        assert_eq!(p.bells[0].values["diameter_mm"], json!(800.0));
        assert_eq!(p.bells[0].values["height_mm"], json!(646.0));
    }

    #[test]
    fn unset_values_are_unknown_without_a_warning() {
        let d = doc(vec![bell(
            "a",
            json!({"motion": "NOT_SET", "motor": "NOT_SET", "weight_g": "", "diameter_mm": null}),
        )]);
        let p = plan_ok(&d);
        assert_eq!(Value::Object(p.bells[0].values.clone()), json!({}));
        assert!(p.warnings.is_empty(), "{:?}", p.warnings);
    }

    #[test]
    fn an_unknown_motion_is_kept_raw_left_empty_and_warned() {
        let d = doc(vec![bell(
            "a",
            json!({"motion": "swirling", "weight_g": "100000"}),
        )]);
        let p = plan_ok(&d);
        assert!(p.bells[0].values.get("motion").is_none());
        assert_eq!(p.bells[0].values["weight_kg"], json!(100.0));
        assert_eq!(p.bells[0].source["properties"]["motion"], "swirling");
        assert_eq!(p.warnings.len(), 1);
        assert_eq!(p.warnings[0].bell.as_deref(), Some("a"));
        assert_eq!(p.warnings[0].field, "motion");
    }

    #[test]
    fn a_bad_number_only_loses_that_attribute() {
        let d = doc(vec![bell(
            "a",
            json!({"weight_g": "heavy", "diameter_mm": "-5", "height_mm": "646"}),
        )]);
        let p = plan_ok(&d);
        assert_eq!(
            Value::Object(p.bells[0].values.clone()),
            json!({"height_mm": 646.0})
        );
        let fields: Vec<_> = p.warnings.iter().map(|w| w.field.as_str()).collect();
        assert_eq!(fields, ["weight", "diameter"]);
    }

    #[test]
    fn a_linear_motor_gets_no_brand_and_a_warning() {
        let d = doc(vec![bell(
            "a",
            json!({"motor": "linear", "motor_ref": "IV714C"}),
        )]);
        let p = plan_ok(&d);
        assert!(p.bells[0].values.get("motor_brand").is_none());
        assert_eq!(p.warnings.len(), 1);
        assert_eq!(p.warnings[0].field, "motor");
        assert_eq!(p.bells[0].source["properties"]["motor_ref"], "IV714C");
    }

    #[test]
    fn the_brand_is_matched_ignoring_case_spaces_and_rpm() {
        for (src, want) in [
            ("MEZ 1000", Some("mez_1000")),
            ("mez1000rpm", Some("mez_1000")),
            ("De Coster 1000", Some("de_coster_1000")),
            ("adda_750", Some("adda_750")),
            ("", None),
            ("Siemens", None),
        ] {
            let mut d = doc(vec![bell("a", json!({"motor": "rotating"}))]);
            d["customer"]["rotary_motor"] = json!(src);
            let p = plan_ok(&d);
            assert_eq!(
                p.bells[0].values.get("motor_brand").and_then(Value::as_str),
                want,
                "{src}"
            );
            assert_eq!(p.warnings.len(), usize::from(src == "Siemens"), "{src}");
        }
    }

    #[test]
    fn a_missing_definition_skips_the_attribute_with_a_warning() {
        let only_weight: Vec<_> = defs()
            .into_iter()
            .filter(|d| d.key == "weight_kg")
            .collect();
        let d = doc(vec![bell("a", json!({"weight_g": "1000", "note": "C1"}))]);
        let p = plan(&d, &only_weight).unwrap();
        assert_eq!(
            Value::Object(p.bells[0].values.clone()),
            json!({"weight_kg": 1.0})
        );
        assert_eq!(p.warnings.len(), 1);
        assert_eq!(p.warnings[0].field, "note");
    }

    #[test]
    fn unmapped_fields_are_counted() {
        let d = doc(vec![
            bell(
                "a",
                json!({"weight_g": "1", "striker": "swinging", "pkz_trip_a": "1"}),
            ),
            bell("b", json!({"striker": "inside"})),
        ]);
        let p = plan_ok(&d);
        let m: BTreeMap<_, _> = p
            .unmapped
            .iter()
            .map(|u| (u.field.as_str(), u.count))
            .collect();
        assert_eq!(m["bells[].properties.striker"], 2);
        assert_eq!(m["bells[].properties.pkz_trip_a"], 1);
        assert_eq!(m["bells[].field_states"], 2);
        assert_eq!(m["bells[].subdivision"], 2);
        assert_eq!(m["topology"], 1);
        assert_eq!(m["customer"], 1);
        assert!(!m.contains_key("bells[].properties.weight_g"));
        assert!(!m.contains_key("bells"));
    }

    #[test]
    fn names_fall_back_and_are_trimmed() {
        let d = json!({"bells": [
            {"identifier": "  x  ", "properties": {}},
            {"properties": {}},
            {"identifier": "", "properties": {}}]});
        let p = plan_ok(&d);
        assert_eq!(p.group_name, "Tower configurator import");
        let names: Vec<_> = p.bells.iter().map(|b| b.name.as_str()).collect();
        assert_eq!(names, ["x", "Bell 2", "Bell 3"]);
    }

    #[test]
    fn a_bell_without_properties_is_imported_with_a_warning() {
        let d = json!({"bells": [{"identifier": "a"}, 5]});
        let p = plan_ok(&d);
        assert_eq!(p.bells.len(), 2);
        assert_eq!(p.warnings.len(), 2);
        assert_eq!(p.bells[1].name, "Bell 2");
    }

    #[test]
    fn the_group_is_named_from_location_then_customer() {
        let mut d = doc(vec![]);
        d["location"]["name"] = json!("");
        assert_eq!(plan_ok(&d).group_name, "Parish");
        d["customer"]["name"] = json!("  ");
        assert_eq!(plan_ok(&d).group_name, "Tower configurator import");
    }

    #[test]
    fn documents_that_are_not_an_export_are_refused() {
        for bad in [
            json!([]),
            json!("x"),
            json!({}),
            json!({"bells": "no"}),
            json!({"bells": {}}),
        ] {
            assert!(plan(&bad, &defs()).is_err(), "{bad}");
        }
        assert_eq!(plan(&json!({"bells": []}), &defs()).unwrap().bells.len(), 0);
    }

    #[test]
    fn a_long_note_is_dropped_with_a_warning_not_the_bell() {
        let d = doc(vec![bell(
            "a",
            json!({"note": "n".repeat(600), "weight_g": "1000"}),
        )]);
        let p = plan_ok(&d);
        assert!(p.bells[0].values.get("note").is_none());
        assert_eq!(p.bells[0].values["weight_kg"], json!(1.0));
        assert_eq!(p.warnings[0].field, "note");
    }
}
