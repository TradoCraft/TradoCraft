//! Site baseline of an opportunity (ADR 0068): a tree of items (clock dials, bell groups, bells ...)
//! whose attribute values are validated against the admin-defined attribute definitions of the
//! item's type.

use chrono::{DateTime, Utc};
use serde::Serialize;
use serde_json::{Map, Value};
use sqlx::FromRow;
use std::collections::HashMap;
use tradocraft_products::attribute_definitions::{AttributeDefinition, DefinitionKind};
use utoipa::ToSchema;
use uuid::Uuid;

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
