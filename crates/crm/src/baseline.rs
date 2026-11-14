//! Site baseline of an opportunity (ADR 0068): a tree of items (clock dials, bell groups, bells ...)
//! whose attribute values are validated against the admin-defined attribute definitions of the
//! item's type.

use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::Json;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use sqlx::{FromRow, PgConnection};
use std::collections::HashMap;
use tradocraft_core::{audit, new_id, AppError, AppResult, AppState, CurrentUser, Permission};
use tradocraft_products::attribute_definitions::{
    active_for_scope, AttributeDefinition, DefinitionKind,
};
use utoipa::ToSchema;
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::baseline_types;

type ErrorBody = tradocraft_core::error::ErrorBody;

/// An opportunity holds at most this many baseline items.
pub const MAX_ITEMS: usize = 1000;
const MAX_QUANTITY: i32 = 100_000;
const MAX_NAME: usize = 200;

/// Items nest at most this deep (a group holding bells is depth 2).
pub const MAX_DEPTH: usize = 8;

/// One baseline item. `children` is only filled in the tree returned by `GET .../baseline`.
#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct BaselineItem {
    pub id: Uuid,
    pub parent_id: Option<Uuid>,
    pub type_code: String,
    pub name: Option<String>,
    pub quantity: i32,
    /// Attribute values keyed by attribute definition key.
    #[schema(value_type = Object)]
    pub values: Value,
    pub sort_order: i32,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    #[sqlx(skip)]
    #[schema(no_recursion)]
    pub children: Vec<BaselineItem>,
}

const MAX_TEXT: usize = 500;

fn number(v: &Value) -> Option<f64> {
    v.as_f64().filter(|n| n.is_finite())
}

/// Normalises one value of a definition: `Ok(None)` clears it (null or blank text).
fn normalise(def: &AttributeDefinition, v: &Value) -> Result<Option<Value>, String> {
    let key = &def.key;
    if v.is_null() {
        return Ok(None);
    }
    match def.kind {
        DefinitionKind::Number => match number(v) {
            Some(_) => Ok(Some(v.clone())),
            None => Err(format!("{key} must be a number")),
        },
        DefinitionKind::Range => {
            let bad =
                || format!("{key} must be {{\"min\": number, \"max\": number}} with min <= max");
            let o = v.as_object().filter(|o| o.len() == 2).ok_or_else(bad)?;
            let (min, max) = (o.get("min").and_then(number), o.get("max").and_then(number));
            match (min, max) {
                (Some(lo), Some(hi)) if lo <= hi => Ok(Some(serde_json::json!({
                    "min": o["min"], "max": o["max"]
                }))),
                _ => Err(bad()),
            }
        }
        DefinitionKind::Select => match v.as_str() {
            Some(s) if def.options.iter().any(|o| o.value == s) => Ok(Some(v.clone())),
            _ => Err(format!(
                "{key} must be one of: {}",
                def.options
                    .iter()
                    .map(|o| o.value.as_str())
                    .collect::<Vec<_>>()
                    .join(", ")
            )),
        },
        DefinitionKind::Text => match v.as_str() {
            Some(s) if s.trim().chars().count() <= MAX_TEXT => {
                let s = s.trim();
                Ok((!s.is_empty()).then(|| Value::String(s.to_string())))
            }
            _ => Err(format!(
                "{key} must be text of at most {MAX_TEXT} characters"
            )),
        },
    }
}

/// Validates `values` against the active definitions of the item's type and returns them
/// normalised. Unknown keys are errors, missing keys are fine (the data may be incomplete).
/// A null (or blank text) clears a value.
pub fn validate_values(
    defs: &[AttributeDefinition],
    values: &Value,
) -> Result<Map<String, Value>, String> {
    let Some(obj) = values.as_object() else {
        return Err("values must be an object".into());
    };
    let mut out = Map::new();
    let mut problems = Vec::new();
    for (key, v) in obj {
        let Some(def) = defs.iter().find(|d| &d.key == key) else {
            problems.push(format!("unknown attribute {key}"));
            continue;
        };
        match normalise(def, v) {
            Ok(Some(n)) => {
                out.insert(key.clone(), n);
            }
            Ok(None) => {}
            Err(e) => problems.push(e),
        }
    }
    if problems.is_empty() {
        Ok(out)
    } else {
        Err(problems.join("; "))
    }
}

/// A top-level item needs `allow_top_level`; a nested one needs its parent's type among `allowed`.
pub fn check_parent_type(
    allowed: &[String],
    allow_top_level: bool,
    parent_type: Option<&str>,
) -> Result<(), String> {
    match parent_type {
        None if allow_top_level => Ok(()),
        None => Err("this type must be placed under a parent item".into()),
        Some(p) if allowed.iter().any(|a| a == p) => Ok(()),
        Some(p) => Err(format!("this type cannot be placed under a {p}")),
    }
}

/// Levels of `root`'s subtree below it (0 for a leaf). `seen` guards against bad data.
fn height(children: &HashMap<Uuid, Vec<Uuid>>, root: Uuid, seen: &mut Vec<Uuid>) -> usize {
    if seen.contains(&root) {
        return 0;
    }
    seen.push(root);
    children.get(&root).map_or(0, |c| {
        c.iter()
            .map(|k| 1 + height(children, *k, seen))
            .max()
            .unwrap_or(0)
    })
}

/// Checks where an item may go in the tree of one opportunity. `parents` maps every existing item
/// of the opportunity to its parent; `moving` is the item being moved (None for a new item).
/// Rejects an unknown parent, a cycle and a tree deeper than [`MAX_DEPTH`].
pub fn check_placement(
    parents: &HashMap<Uuid, Option<Uuid>>,
    moving: Option<Uuid>,
    new_parent: Option<Uuid>,
) -> Result<(), String> {
    let Some(parent) = new_parent else {
        return Ok(());
    };
    if !parents.contains_key(&parent) {
        return Err("parent_id is not an item of this opportunity".into());
    }
    // Walk up from the new parent: reaching the moved item means it would become its own ancestor.
    let mut depth = 0;
    let mut at = Some(parent);
    while let Some(id) = at {
        if Some(id) == moving {
            return Err(
                "an item cannot be placed under itself or its own descendants (cycle)".into(),
            );
        }
        depth += 1;
        if depth > parents.len() {
            break; // corrupt data; stop rather than loop
        }
        at = parents.get(&id).copied().flatten();
    }
    let below = moving.map_or(0, |m| {
        let mut children: HashMap<Uuid, Vec<Uuid>> = HashMap::new();
        for (id, p) in parents {
            if let Some(p) = p {
                children.entry(*p).or_default().push(*id);
            }
        }
        height(&children, m, &mut Vec::new())
    });
    if depth + 1 + below > MAX_DEPTH {
        return Err(format!(
            "the baseline cannot be nested deeper than {MAX_DEPTH} levels"
        ));
    }
    Ok(())
}

/// Nests flat items (already in display order) under their parents.
pub fn build_tree(flat: Vec<BaselineItem>) -> Vec<BaselineItem> {
    let mut by_parent: HashMap<Option<Uuid>, Vec<BaselineItem>> = HashMap::new();
    for item in flat {
        by_parent.entry(item.parent_id).or_default().push(item);
    }
    fn attach(
        by_parent: &mut HashMap<Option<Uuid>, Vec<BaselineItem>>,
        parent: Option<Uuid>,
    ) -> Vec<BaselineItem> {
        let mut items = by_parent.remove(&parent).unwrap_or_default();
        for item in &mut items {
            item.children = attach(by_parent, Some(item.id));
        }
        items
    }
    attach(&mut by_parent, None)
}

fn default_quantity() -> i32 {
    1
}

fn empty_object() -> Value {
    Value::Object(Map::new())
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct BaselineItemInput {
    /// Code of a baseline item type of the company (it must be active).
    pub type_code: String,
    /// An item of the same opportunity; omit for the top level.
    #[serde(default)]
    pub parent_id: Option<Uuid>,
    /// Optional, e.g. the name of a bell.
    #[serde(default)]
    pub name: Option<String>,
    /// At least 1.
    #[serde(default = "default_quantity")]
    pub quantity: i32,
    /// Attribute values keyed by definition key; see the definitions of the item's type.
    #[serde(default = "empty_object")]
    #[schema(value_type = Object)]
    pub values: Value,
    #[serde(default)]
    pub sort_order: i32,
}

/// Replaces an item: what is not sent falls back to its default (no parent, no name, quantity 1,
/// no values); only `sort_order` keeps its stored value when omitted. The type cannot change.
#[derive(Debug, Deserialize, ToSchema)]
pub struct BaselineItemUpdate {
    /// Omit (null) to move the item to the top level.
    #[serde(default)]
    pub parent_id: Option<Uuid>,
    #[serde(default)]
    pub name: Option<String>,
    #[serde(default = "default_quantity")]
    pub quantity: i32,
    #[serde(default = "empty_object")]
    #[schema(value_type = Object)]
    pub values: Value,
    #[serde(default)]
    pub sort_order: Option<i32>,
}

fn clean_name(name: &Option<String>) -> AppResult<Option<String>> {
    let name = name.as_deref().map(str::trim).filter(|n| !n.is_empty());
    match name {
        Some(n) if n.chars().count() > MAX_NAME => Err(AppError::Validation(format!(
            "name is at most {MAX_NAME} characters"
        ))),
        other => Ok(other.map(str::to_string)),
    }
}

fn check_quantity(q: i32) -> AppResult<()> {
    if (1..=MAX_QUANTITY).contains(&q) {
        Ok(())
    } else {
        Err(AppError::Validation(format!(
            "quantity must be between 1 and {MAX_QUANTITY}"
        )))
    }
}

const SELECT: &str = "SELECT id, parent_id, type_code, name, quantity, \"values\", sort_order,
                             created_at, updated_at
                      FROM crm.opportunity_baseline_items";

/// 404 unless the opportunity belongs to the company; `lock` serialises concurrent tree edits.
async fn check_opportunity(
    conn: &mut PgConnection,
    company_id: Uuid,
    opportunity_id: Uuid,
    lock: bool,
) -> AppResult<()> {
    let found: Option<i32> = sqlx::query_scalar(if lock {
        "SELECT 1 FROM crm.opportunities WHERE id = $1 AND company_id = $2 FOR UPDATE"
    } else {
        "SELECT 1 FROM crm.opportunities WHERE id = $1 AND company_id = $2"
    })
    .bind(opportunity_id)
    .bind(company_id)
    .fetch_optional(conn)
    .await?;
    found.map(|_| ()).ok_or(AppError::NotFound("opportunity"))
}

/// (id, parent_id, type_code) of every item of the opportunity.
async fn placements(
    conn: &mut PgConnection,
    opportunity_id: Uuid,
) -> AppResult<Vec<(Uuid, Option<Uuid>, String)>> {
    Ok(sqlx::query_as(
        "SELECT id, parent_id, type_code FROM crm.opportunity_baseline_items WHERE opportunity_id = $1",
    )
    .bind(opportunity_id)
    .fetch_all(conn)
    .await?)
}

async fn load_item(
    conn: &mut PgConnection,
    opportunity_id: Uuid,
    id: Uuid,
) -> AppResult<BaselineItem> {
    sqlx::query_as(&format!("{SELECT} WHERE id = $1 AND opportunity_id = $2"))
        .bind(id)
        .bind(opportunity_id)
        .fetch_optional(conn)
        .await?
        .ok_or(AppError::NotFound("baseline item"))
}

/// Validates the placement and values of an item of type `type_code` and returns the normalised
/// values. `moving` is the item itself when it already exists.
async fn check_item(
    conn: &mut PgConnection,
    company_id: Uuid,
    existing: &[(Uuid, Option<Uuid>, String)],
    moving: Option<Uuid>,
    ty: &baseline_types::BaselineItemType,
    parent_id: Option<Uuid>,
    values: &Value,
) -> AppResult<Value> {
    let parents = existing.iter().map(|(i, p, _)| (*i, *p)).collect();
    check_placement(&parents, moving, parent_id).map_err(AppError::Validation)?;
    let parent_type = parent_id.and_then(|p| {
        existing
            .iter()
            .find(|(i, _, _)| *i == p)
            .map(|(_, _, t)| t.as_str())
    });
    check_parent_type(&ty.allowed_parent_codes, ty.allow_top_level, parent_type)
        .map_err(AppError::Validation)?;
    let defs = active_for_scope(conn, company_id, &ty.code).await?;
    validate_values(&defs, values)
        .map(Value::Object)
        .map_err(AppError::Validation)
}

/// The baseline of an opportunity as a tree (a group holds its bells).
#[utoipa::path(get, path = "/opportunities/{id}/baseline", tag = "crm", params(("id" = Uuid, Path)),
    responses((status = 200, body = Vec<BaselineItem>), (status = 404, body = ErrorBody)))]
async fn get_baseline(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<Vec<BaselineItem>>> {
    user.require(Permission::OpportunitiesRead)?;
    let mut conn = state.db.acquire().await?;
    check_opportunity(&mut conn, user.company_id, id, false).await?;
    Ok(Json(load_tree(&mut conn, id).await?))
}

/// The baseline of an opportunity as a tree; the caller has checked the opportunity.
pub async fn load_tree(
    conn: &mut PgConnection,
    opportunity_id: Uuid,
) -> AppResult<Vec<BaselineItem>> {
    let flat: Vec<BaselineItem> = sqlx::query_as(&format!(
        "{SELECT} WHERE opportunity_id = $1 ORDER BY sort_order, created_at, id"
    ))
    .bind(opportunity_id)
    .fetch_all(conn)
    .await?;
    Ok(build_tree(flat))
}

#[utoipa::path(post, path = "/opportunities/{id}/baseline/items", tag = "crm", params(("id" = Uuid, Path)),
    request_body = BaselineItemInput,
    responses((status = 201, body = BaselineItem), (status = 404, body = ErrorBody),
        (status = 422, body = ErrorBody)))]
async fn create_item(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(opportunity_id): Path<Uuid>,
    Json(input): Json<BaselineItemInput>,
) -> AppResult<(StatusCode, Json<BaselineItem>)> {
    user.require(Permission::OpportunitiesWrite)?;
    check_quantity(input.quantity)?;
    let name = clean_name(&input.name)?;
    let mut tx = state.db.begin().await?;
    check_opportunity(&mut tx, user.company_id, opportunity_id, true).await?;
    let type_code = input.type_code.trim();
    let ty = baseline_types::find_by_code(&mut tx, user.company_id, type_code)
        .await?
        .ok_or_else(|| AppError::Validation(format!("unknown baseline item type {type_code}")))?;
    if !ty.active {
        return Err(AppError::Validation(format!(
            "baseline item type {type_code} is inactive"
        )));
    }
    let existing = placements(&mut tx, opportunity_id).await?;
    if existing.len() >= MAX_ITEMS {
        return Err(AppError::Validation(format!(
            "an opportunity holds at most {MAX_ITEMS} baseline items"
        )));
    }
    let values = check_item(
        &mut tx,
        user.company_id,
        &existing,
        None,
        &ty,
        input.parent_id,
        &input.values,
    )
    .await?;
    let id = new_id();
    sqlx::query(
        "INSERT INTO crm.opportunity_baseline_items
            (id, company_id, opportunity_id, parent_id, type_code, name, quantity, \"values\", sort_order)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(opportunity_id)
    .bind(input.parent_id)
    .bind(&ty.code)
    .bind(&name)
    .bind(input.quantity)
    .bind(&values)
    .bind(input.sort_order)
    .execute(&mut *tx)
    .await?;
    audit::record(
        &mut tx,
        &user,
        "baseline_item",
        id,
        "created",
        serde_json::json!({ "opportunity_id": opportunity_id, "type_code": ty.code }),
    )
    .await?;
    let item = load_item(&mut tx, opportunity_id, id).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(item)))
}

#[utoipa::path(put, path = "/opportunities/{id}/baseline/items/{item_id}", tag = "crm",
    params(("id" = Uuid, Path), ("item_id" = Uuid, Path)), request_body = BaselineItemUpdate,
    responses((status = 200, body = BaselineItem), (status = 404, body = ErrorBody),
        (status = 422, body = ErrorBody)))]
async fn update_item(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((opportunity_id, item_id)): Path<(Uuid, Uuid)>,
    Json(input): Json<BaselineItemUpdate>,
) -> AppResult<Json<BaselineItem>> {
    user.require(Permission::OpportunitiesWrite)?;
    check_quantity(input.quantity)?;
    let name = clean_name(&input.name)?;
    let mut tx = state.db.begin().await?;
    check_opportunity(&mut tx, user.company_id, opportunity_id, true).await?;
    let current = load_item(&mut tx, opportunity_id, item_id).await?;
    let ty = baseline_types::find_by_code(&mut tx, user.company_id, &current.type_code)
        .await?
        .ok_or(AppError::NotFound("baseline item type"))?;
    let existing = placements(&mut tx, opportunity_id).await?;
    let values = check_item(
        &mut tx,
        user.company_id,
        &existing,
        Some(item_id),
        &ty,
        input.parent_id,
        &input.values,
    )
    .await?;
    sqlx::query(
        "UPDATE crm.opportunity_baseline_items
         SET parent_id = $2, name = $3, quantity = $4, \"values\" = $5, sort_order = $6, updated_at = now()
         WHERE id = $1",
    )
    .bind(item_id)
    .bind(input.parent_id)
    .bind(&name)
    .bind(input.quantity)
    .bind(&values)
    .bind(input.sort_order.unwrap_or(current.sort_order))
    .execute(&mut *tx)
    .await?;
    audit::record(
        &mut tx,
        &user,
        "baseline_item",
        item_id,
        "updated",
        serde_json::json!({ "opportunity_id": opportunity_id, "type_code": ty.code }),
    )
    .await?;
    let item = load_item(&mut tx, opportunity_id, item_id).await?;
    tx.commit().await?;
    Ok(Json(item))
}

/// Deletes one item. An item that still has children is refused with 409 rather than deleting the
/// whole subtree silently: remove or move the children first.
#[utoipa::path(delete, path = "/opportunities/{id}/baseline/items/{item_id}", tag = "crm",
    params(("id" = Uuid, Path), ("item_id" = Uuid, Path)),
    responses((status = 204), (status = 404, body = ErrorBody), (status = 409, body = ErrorBody)))]
async fn delete_item(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((opportunity_id, item_id)): Path<(Uuid, Uuid)>,
) -> AppResult<StatusCode> {
    user.require(Permission::OpportunitiesWrite)?;
    let mut tx = state.db.begin().await?;
    check_opportunity(&mut tx, user.company_id, opportunity_id, true).await?;
    let item = load_item(&mut tx, opportunity_id, item_id).await?;
    let children: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM crm.opportunity_baseline_items WHERE parent_id = $1",
    )
    .bind(item_id)
    .fetch_one(&mut *tx)
    .await?;
    if children > 0 {
        return Err(AppError::Conflict(format!(
            "the item has {children} child items; remove or move them first"
        )));
    }
    sqlx::query("DELETE FROM crm.opportunity_baseline_items WHERE id = $1")
        .bind(item_id)
        .execute(&mut *tx)
        .await?;
    audit::record(
        &mut tx,
        &user,
        "baseline_item",
        item_id,
        "deleted",
        serde_json::json!({ "opportunity_id": opportunity_id, "type_code": item.type_code }),
    )
    .await?;
    tx.commit().await?;
    Ok(StatusCode::NO_CONTENT)
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(get_baseline))
        .routes(routes!(create_item))
        .routes(routes!(update_item, delete_item))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use tradocraft_products::attribute_definitions::{DefinitionKind, SelectOption};

    fn def(key: &str, kind: DefinitionKind, options: &[&str]) -> AttributeDefinition {
        AttributeDefinition {
            id: Uuid::nil(),
            key: key.into(),
            label: key.into(),
            kind,
            unit: None,
            options: options
                .iter()
                .map(|o| SelectOption {
                    value: (*o).into(),
                    label: (*o).into(),
                })
                .collect(),
            scope: "bell".into(),
            sort_order: 0,
            active: true,
        }
    }

    fn defs() -> Vec<AttributeDefinition> {
        vec![
            def("weight_kg", DefinitionKind::Number, &[]),
            def("dial_size", DefinitionKind::Range, &[]),
            def("motion", DefinitionKind::Select, &["flying", "falling"]),
            def("note", DefinitionKind::Text, &[]),
        ]
    }

    fn ok(v: Value) -> Map<String, Value> {
        validate_values(&defs(), &v).unwrap_or_else(|e| panic!("{v}: {e}"))
    }

    fn err(v: Value) -> String {
        validate_values(&defs(), &v).expect_err(&format!("{v} must be rejected"))
    }

    #[test]
    fn accepts_valid_values_and_keeps_them() {
        let m = ok(json!({
            "weight_kg": 450.5, "motion": "flying", "note": "c#",
            "dial_size": { "min": 800, "max": 1200 }
        }));
        assert_eq!(m["weight_kg"], json!(450.5));
        assert_eq!(m["motion"], json!("flying"));
        assert_eq!(m["note"], json!("c#"));
        assert_eq!(m["dial_size"], json!({ "min": 800, "max": 1200 }));
    }

    #[test]
    fn empty_and_partial_values_are_allowed() {
        assert!(ok(json!({})).is_empty());
        assert_eq!(ok(json!({ "motion": "falling" })).len(), 1);
    }

    #[test]
    fn unknown_keys_are_rejected_and_named() {
        let e = err(json!({ "weight_kg": 1, "colour": "red" }));
        assert!(e.contains("colour"), "{e}");
        // Keys of inactive or other-scope definitions are not in `defs`, so they are unknown too.
        assert!(validate_values(&[], &json!({ "weight_kg": 1 })).is_err());
    }

    #[test]
    fn values_must_be_an_object() {
        for v in [json!([]), json!("x"), json!(3), json!(null), json!(true)] {
            err(v);
        }
    }

    #[test]
    fn number_must_be_numeric() {
        for v in [json!("12"), json!(true), json!({}), json!([1])] {
            let e = err(json!({ "weight_kg": v }));
            assert!(e.contains("weight_kg"), "{e}");
        }
        assert_eq!(ok(json!({ "weight_kg": 0 }))["weight_kg"], json!(0));
        assert_eq!(ok(json!({ "weight_kg": -2 }))["weight_kg"], json!(-2));
    }

    #[test]
    fn range_needs_ordered_min_and_max_only() {
        assert!(ok(json!({ "dial_size": { "min": 5, "max": 5 } })).contains_key("dial_size"));
        for v in [
            json!({ "min": 10, "max": 5 }),
            json!({ "min": 1 }),
            json!({ "max": 1 }),
            json!({ "min": "a", "max": 2 }),
            json!({ "min": 1, "max": 2, "mid": 1 }),
            json!(5),
            json!("1-2"),
            json!([1, 2]),
        ] {
            err(json!({ "dial_size": v }));
        }
    }

    #[test]
    fn select_must_be_one_of_the_options() {
        err(json!({ "motion": "volteo" }));
        err(json!({ "motion": 1 }));
        err(json!({ "motion": "Flying" }));
    }

    #[test]
    fn text_is_trimmed_and_must_be_a_string() {
        assert_eq!(ok(json!({ "note": "  a  " }))["note"], json!("a"));
        err(json!({ "note": 5 }));
        err(json!({ "note": "x".repeat(501) }));
        assert!(ok(json!({ "note": "x".repeat(500) })).contains_key("note"));
    }

    #[test]
    fn null_and_blank_text_clear_a_value() {
        let m = ok(json!({ "weight_kg": null, "note": "   ", "motion": "flying" }));
        assert_eq!(m.keys().collect::<Vec<_>>(), vec!["motion"]);
    }

    #[test]
    fn all_problems_are_reported_together() {
        let e = err(json!({ "weight_kg": "x", "motion": "nope", "zzz": 1 }));
        for needle in ["weight_kg", "motion", "zzz"] {
            assert!(e.contains(needle), "{e}");
        }
    }

    #[test]
    fn parent_type_rules() {
        let under_group = vec!["bell_group".to_string()];
        // Top level only.
        assert!(check_parent_type(&[], true, None).is_ok());
        assert!(check_parent_type(&[], true, Some("bell_group")).is_err());
        // Only nested.
        assert!(check_parent_type(&under_group, false, None).is_err());
        assert!(check_parent_type(&under_group, false, Some("bell_group")).is_ok());
        assert!(check_parent_type(&under_group, false, Some("clock_dial")).is_err());
        // Both.
        assert!(check_parent_type(&under_group, true, None).is_ok());
        assert!(check_parent_type(&under_group, true, Some("bell_group")).is_ok());
        assert!(check_parent_type(&under_group, true, Some("bell")).is_err());
    }

    fn ids(n: u128) -> Vec<Uuid> {
        (1..=n).map(Uuid::from_u128).collect()
    }

    #[test]
    fn placement_rejects_unknown_parent_self_and_descendants() {
        let i = ids(4);
        // 1 <- 2 <- 3, and 4 alone.
        let parents: HashMap<_, _> = [
            (i[0], None),
            (i[1], Some(i[0])),
            (i[2], Some(i[1])),
            (i[3], None),
        ]
        .into_iter()
        .collect();
        assert!(check_placement(&parents, None, None).is_ok());
        assert!(check_placement(&parents, None, Some(i[2])).is_ok());
        assert!(check_placement(&parents, None, Some(Uuid::from_u128(99))).is_err());
        // Moving 1 under itself, its child or its grandchild is a cycle.
        for p in [i[0], i[1], i[2]] {
            let e = check_placement(&parents, Some(i[0]), Some(p)).unwrap_err();
            assert!(e.contains("cycle"), "{e}");
        }
        // Moving to a sibling branch or to the top level is fine.
        assert!(check_placement(&parents, Some(i[1]), Some(i[3])).is_ok());
        assert!(check_placement(&parents, Some(i[1]), None).is_ok());
    }

    #[test]
    fn placement_limits_the_depth_including_the_moved_subtree() {
        let n = MAX_DEPTH as u128;
        let i = ids(n + 2);
        // A chain of MAX_DEPTH items, plus a loose pair (n+1 <- n+2).
        let mut parents: HashMap<Uuid, Option<Uuid>> = HashMap::new();
        parents.insert(i[0], None);
        for k in 1..n as usize {
            parents.insert(i[k], Some(i[k - 1]));
        }
        parents.insert(i[n as usize], None);
        parents.insert(i[n as usize + 1], Some(i[n as usize]));
        let deepest = i[n as usize - 1];
        assert!(check_placement(&parents, None, Some(deepest)).is_err());
        assert!(check_placement(&parents, None, Some(i[n as usize - 2])).is_ok());
        // Moving the pair (height 2) under the second-deepest item would make it too deep.
        let e =
            check_placement(&parents, Some(i[n as usize]), Some(i[n as usize - 2])).unwrap_err();
        assert!(e.contains("deep"), "{e}");
        assert!(check_placement(&parents, Some(i[n as usize]), Some(i[n as usize - 3])).is_ok());
    }

    fn item(id: u128, parent: Option<u128>, name: &str) -> BaselineItem {
        BaselineItem {
            id: Uuid::from_u128(id),
            parent_id: parent.map(Uuid::from_u128),
            type_code: "bell".into(),
            name: Some(name.into()),
            quantity: 1,
            values: json!({}),
            sort_order: 0,
            created_at: Utc::now(),
            updated_at: Utc::now(),
            children: vec![],
        }
    }

    #[test]
    fn tree_nests_children_and_keeps_order() {
        let tree = build_tree(vec![
            item(1, None, "group"),
            item(2, Some(1), "b1"),
            item(3, None, "dial"),
            item(4, Some(1), "b2"),
            item(5, Some(2), "clapper"),
        ]);
        let names = |v: &[BaselineItem]| -> Vec<String> {
            v.iter().map(|i| i.name.clone().unwrap()).collect()
        };
        assert_eq!(names(&tree), ["group", "dial"]);
        assert_eq!(names(&tree[0].children), ["b1", "b2"]);
        assert_eq!(names(&tree[0].children[0].children), ["clapper"]);
        assert!(tree[1].children.is_empty());
    }

    #[test]
    fn tree_of_nothing_is_empty() {
        assert!(build_tree(vec![]).is_empty());
    }
}
