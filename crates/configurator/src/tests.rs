//! Tests of definition validation, dependency ordering and the evaluator, mostly on the public
//! demo definition (`seed/configurators/conveyor_line.json`).

use std::collections::BTreeMap;

use rust_decimal::Decimal;
use rust_decimal_macros::dec;
use serde_json::{json, Value as J};

use crate::compile::compile;
use crate::definition::{validate, Definition, Severity};
use crate::engine::{evaluate, Catalog, CatalogProduct, Evaluation, Inputs, Line, ValueSource};
use crate::expr::Value;

pub const DEMO: &str = include_str!("../../../seed/configurators/conveyor_line.json");

fn demo() -> Definition {
    let v: J = serde_json::from_str(DEMO).unwrap();
    serde_json::from_value(v["definition"].clone()).unwrap()
}

fn catalog() -> Catalog {
    let mut c = Catalog::default();
    let mut add = |code: &str, attrs: &[(&str, Value)]| {
        c.add(CatalogProduct {
            id: None,
            code: code.into(),
            name: code.into(),
            family: Some("CONVEYOR".into()),
            unit: "pcs".into(),
            active: true,
            attributes: attrs
                .iter()
                .map(|(k, v)| (k.to_string(), v.clone()))
                .collect(),
        })
    };
    for (code, kw, size) in [
        ("MOT-055", "0.55", "05"),
        ("MOT-110", "1.1", "11"),
        ("MOT-220", "2.2", "22"),
        ("MOT-400", "4", "40"),
    ] {
        add(
            code,
            &[
                ("kw", Value::Dec(kw.parse().unwrap())),
                ("size", Value::Str(size.into())),
            ],
        );
    }
    for code in [
        "DRV-05T",
        "DRV-11T",
        "DRV-22T",
        "DRV-40T",
        "DRV-05M",
        "DRV-11M",
        "BELT-M",
        "CTRL-B4",
        "ESTOP-01",
        "TENS-ST",
        "COAT-PROT",
        "INSTALL",
    ] {
        add(code, &[]);
    }
    c
}

fn inputs(v: J) -> Inputs {
    serde_json::from_value(v).unwrap()
}

fn sample() -> J {
    json!({
        "project": { "phases": 3, "voltage": 400, "coating": true },
        "groups": { "Hall 2": { "voltage": 230 } },
        "items": { "segments": [
            { "hall": "Hall 1", "length_m": 12, "load_kg": 200, "speed": 0.5 },
            { "hall": "Hall 1", "length_m": 45, "load_kg": 800, "speed": 1.0 },
            { "hall": "Hall 2", "length_m": 8, "load_kg": 300, "speed": 2.0, "emergency_stop": true }
        ] }
    })
}

fn run(v: J) -> Evaluation {
    let c = compile(&demo()).unwrap_or_else(|e| panic!("{e:#?}"));
    evaluate(&c, &inputs(v), &catalog())
}

fn summary(lines: &[Line]) -> Vec<String> {
    lines
        .iter()
        .map(|l| {
            let mut s = format!(
                "{} x{} [{}]",
                l.code,
                l.quantity.normalize(),
                l.section.clone().unwrap_or_default()
            );
            if let Some(c) = &l.comment {
                s.push_str(&format!(" \"{c}\""));
            }
            for ch in &l.children {
                s.push_str(&format!(
                    " > {} x{} {}%",
                    ch.code,
                    ch.quantity.normalize(),
                    ch.percent_of_parent.unwrap_or_default()
                ));
            }
            s
        })
        .collect()
}

fn item_value<'a>(e: &'a Evaluation, row: usize, name: &str) -> &'a crate::engine::ValueResult {
    e.items[0].rows[row]
        .values
        .iter()
        .find(|v| v.name == name)
        .unwrap()
}

#[test]
fn the_demo_definition_is_valid() {
    let errs = validate(&demo());
    assert!(errs.is_empty(), "{errs:#?}");
}

#[test]
fn the_demo_produces_the_expected_lines() {
    let e = run(sample());
    assert_eq!(
        summary(&e.lines),
        [
            "BELT-M x116 [Hall 1] \"Hall 1 / segment 1, Hall 1 / segment 2\"",
            "BELT-M x17 [Hall 2] \"Hall 2 / segment 3\"",
            "MOT-055 x1 [Hall 1] \"Hall 1 / segment 1\" > COAT-PROT x1 20%",
            "MOT-110 x1 [Hall 1] \"Hall 1 / segment 2\" > COAT-PROT x1 20%",
            "MOT-110 x1 [Hall 2] \"Hall 2 / segment 3\" > COAT-PROT x1 20%",
            "DRV-05T x1 [Hall 1] \"Hall 1 / segment 1\"",
            "DRV-11T x1 [Hall 1] \"Hall 1 / segment 2\"",
            "DRV-11T x1 [Hall 2] \"Hall 2 / segment 3\"",
            "ESTOP-01 x1 [Hall 2] \"Hall 2 / segment 3\"",
            "TENS-ST x1 [Hall 1] \"Segment longer than 40 m (Hall 1 / segment 2)\"",
            "CTRL-B4 x1 [Hall 1] \"2 of 4 channels used\"",
            "CTRL-B4 x1 [Hall 2] \"1 of 4 channels used\"",
            "INSTALL x32 [Installation] \"65 m of conveyor\"",
        ]
    );
    // The child's comment comes from its own template.
    assert_eq!(
        e.lines[2].children[0].comment.as_deref(),
        Some("Corrosivity class C4")
    );
    // Power, the offset rule (fast belt: next row up) and the group override of the voltage.
    assert_eq!(item_value(&e, 0, "power_kw").value, json!("0.178"));
    assert_eq!(item_value(&e, 2, "power_kw").value, json!("0.426"));
    assert_eq!(item_value(&e, 2, "motor_code").value, json!("MOT-110"));
    assert_eq!(
        item_value(&e, 2, "motor_code").source,
        ValueSource::Calculated
    );
    assert_eq!(e.groups[1].name, "Hall 2");
    assert_eq!(e.groups[1].values[0].value, json!("230"));
    assert_eq!(e.groups[0].values[0].value, json!("400"));
    assert_eq!(e.groups[0].values[0].source, ValueSource::Default);
    // Issues: the hall at 230 V, the fast belt.
    let issues: Vec<(Severity, &str, &str)> = e
        .issues
        .iter()
        .map(|i| (i.severity, i.code.as_str(), i.scope.as_str()))
        .collect();
    assert_eq!(
        issues,
        [
            (Severity::Warning, "three_phase_voltage", "groups[Hall 2]"),
            (Severity::Info, "fast_belt", "segments[2]"),
        ],
        "{:#?}",
        e.issues
    );
    assert!(e.issues[0]
        .message
        .starts_with("Hall 2: three-phase motors need at least 380 V, but 230 V"));
    assert!(!e.has_errors());
    // Hidden field: the corrosivity class is visible only with a coating.
    let p = run(
        json!({"project": {"coating": false}, "items": {"segments": [{"length_m": 5, "load_kg": 10}]}}),
    );
    let cc = p
        .project
        .iter()
        .find(|v| v.name == "coating_class")
        .unwrap();
    assert!(!cc.visible);
    assert_eq!(cc.source, ValueSource::Hidden);
    assert!(p.lines.iter().all(|l| l.children.is_empty()));
}

#[test]
fn trace_records_rule_scope_and_values() {
    let e = run(sample());
    let drive = &e.lines[5];
    assert_eq!(drive.trace.rule, "drive");
    assert_eq!(drive.trace.rule_path, "$.outputs[2]");
    let src = &drive.trace.sources[0];
    assert_eq!(src.scope, "segments[0]");
    assert_eq!(src.label.as_deref(), Some("Hall 1 / segment 1"));
    assert_eq!(src.values["motor_size"], json!("05"));
    assert_eq!(src.values["phases"], json!(3));
    // A merged line keeps every source.
    assert_eq!(e.lines[0].trace.sources.len(), 2);
    let boards = &e.lines[10];
    assert_eq!(boards.trace.sources[0].each, Some(json!(2)));
}

#[test]
fn pinned_overrides_are_calculated_pinned_or_stale() {
    let mut v = sample();
    v["pins"] = json!([
        { "name": "motor_code", "table": "segments", "row": 0, "value": "MOT-220", "calculated": "MOT-055" },
        { "name": "motor_code", "table": "segments", "row": 1, "value": "MOT-055" },
        { "name": "motor_code", "table": "segments", "row": 2, "value": "MOT-400", "calculated": "MOT-055" },
        { "name": "power_kw", "table": "segments", "row": 0, "value": "9" }
    ]);
    let e = run(v);
    let m0 = item_value(&e, 0, "motor_code");
    assert_eq!(m0.source, ValueSource::Pinned);
    assert_eq!(m0.value, json!("MOT-220"));
    assert_eq!(m0.calculated, Some(json!("MOT-055")));
    assert_eq!(m0.options.as_ref().unwrap().len(), 4);
    // The drive follows the pinned motor (through its size attribute).
    assert!(summary(&e.lines)
        .iter()
        .any(|l| l.starts_with("DRV-22T x1 [Hall 1]")));
    assert_eq!(item_value(&e, 1, "motor_code").source, ValueSource::Pinned);
    // Calculated differently now than when pinned: stale, with a warning.
    assert_eq!(item_value(&e, 2, "motor_code").source, ValueSource::Stale);
    let codes: Vec<&str> = e.issues.iter().map(|i| i.code.as_str()).collect();
    assert!(codes.contains(&"pin_stale"), "{codes:?}");
    // The smaller motor on row 1 triggers the warning validation.
    let small = e
        .issues
        .iter()
        .find(|i| i.code == "motor_too_small")
        .unwrap();
    assert_eq!(small.scope, "segments[1]");
    assert_eq!(small.field.as_deref(), Some("motor_code"));
    assert!(
        small
            .message
            .contains("MOT-055 (0.55 kW) is smaller than the required 0.912 kW"),
        "{}",
        small.message
    );
    // A value that is not overridable ignores its pin.
    assert_eq!(
        item_value(&e, 0, "power_kw").source,
        ValueSource::Calculated
    );
    assert!(codes.contains(&"pin_ignored"));
}

#[test]
fn input_errors_and_lookup_failures_become_issues() {
    let e = run(json!({
        "project": { "phases": 1, "voltage": 2000 },
        "items": { "segments": [
            { "hall": "A", "length_m": 90, "load_kg": 4000, "speed": 2.5 },
            { "hall": "A", "load_kg": "heavy" }
        ] }
    }));
    let codes: Vec<(&str, &str)> = e
        .issues
        .iter()
        .map(|i| (i.code.as_str(), i.scope.as_str()))
        .collect();
    assert!(codes.contains(&("out_of_range", "project")), "{codes:?}");
    // Single phase motors stop at 1.1 kW: the table refuses.
    let lookup = e
        .issues
        .iter()
        .find(|i| i.code == "evaluation_error" && i.scope == "segments[0]")
        .unwrap();
    assert!(
        lookup
            .message
            .contains("outside the ranges of table motors"),
        "{}",
        lookup.message
    );
    assert!(codes.contains(&("invalid_value", "segments[1]")));
    assert!(codes.contains(&("required", "segments[1]")));
    assert!(e.has_errors());
    // No rows at all.
    let e = run(json!({}));
    assert!(e.issues.iter().any(|i| i.code == "rows"));
    assert!(e.lines.is_empty() || e.lines.iter().all(|l| l.code == "INSTALL"));
}

#[test]
fn unknown_codes_are_warned_about() {
    let c = compile(&demo()).unwrap();
    let mut cat = catalog();
    cat.products.remove("ESTOP-01");
    let e = evaluate(&c, &inputs(sample()), &cat);
    let w = e
        .issues
        .iter()
        .find(|i| i.code == "unknown_product")
        .unwrap();
    assert!(w.message.contains("ESTOP-01"));
    assert_eq!(w.rule.as_deref(), Some("emergency_stop"));
}

#[test]
fn lines_carry_their_product_and_can_be_localized() {
    let c = compile(&demo()).unwrap();
    let mut cat = catalog();
    let id = uuid::Uuid::from_u128(7);
    cat.products.get_mut("BELT-M").unwrap().id = Some(id);
    cat.products.get_mut("BELT-M").unwrap().name = "Belt".into();
    cat.products.remove("ESTOP-01");
    let mut e = evaluate(&c, &inputs(sample()), &cat);
    let belt = e.lines.iter().find(|l| l.code == "BELT-M").unwrap();
    assert_eq!(belt.product_id, Some(id));
    assert_eq!(belt.product_name.as_deref(), Some("Belt"));
    let estop = e.lines.iter().find(|l| l.code == "ESTOP-01").unwrap();
    assert_eq!(
        (estop.product_id, estop.product_name.as_deref()),
        (None, None)
    );
    assert_eq!(e.product_ids(), vec![id]);
    e.localize(&[(id, "Band".to_string())].into_iter().collect());
    assert!(e
        .lines
        .iter()
        .filter(|l| l.code == "BELT-M")
        .all(|l| l.product_name.as_deref() == Some("Band")));
}

fn def(v: J) -> Definition {
    serde_json::from_value(v).unwrap()
}

fn errors(v: J) -> Vec<(String, String)> {
    validate(&def(v))
        .into_iter()
        .map(|e| (e.path, e.message))
        .collect()
}

fn has(errs: &[(String, String)], path: &str, msg: &str) -> bool {
    errs.iter().any(|(p, m)| p == path && m.contains(msg))
}

#[test]
fn validation_reports_paths() {
    let errs = errors(json!({
        "name": "",
        "project": {
            "fields": [
                { "name": "a", "type": "number", "min": 5, "max": 1, "options": [{"value": 1}] },
                { "name": "a", "type": "integer" },
                { "name": "c", "type": "choice", "options": [{"value": "x"}], "default": "y" },
                { "name": "d", "type": "number", "dimension": "mass", "unit": "V" },
                { "name": "items", "type": "text" },
                { "name": "e", "type": "boolean", "visible_if": "a +" }
            ],
            "computed": [ { "name": "f", "expr": "nope * 2" }, { "name": "g", "expr": "1", "options_from": "[1]" } ]
        },
        "item_tables": [ { "name": "rows_", "group_field": "zz", "fields": [ { "name": "q", "type": "number" } ] } ],
        "tables": [ { "name": "t", "keys": ["k"], "columns": [{ "name": "k", "type": "text" }], "rows": [{ "k": 1 }] } ],
        "outputs": [
            { "id": "r1", "code": "'A'", "code_template": "B" },
            { "id": "r1", "scope": "item", "code": "q", "percent_of_parent": "5",
              "children": [ { "id": "c1", "scope": "group", "code": "lookup('t', {k: 'x'}).missing", "quantity": "'two'" } ] },
            { "id": "r3", "scope": "group", "table": "rows_", "code": "'A'", "when": "1" }
        ],
        "validations": [ { "id": "v", "when": "c == 'x'", "severity": "error", "message": "{oops", "field": "nope" } ]
    }));
    let expect = [
        ("$.name", "needs a name"),
        ("$.project.fields[0].options", "only for choice"),
        ("$.project.fields[0].min", "larger than max"),
        (
            "$.project.fields[1].name",
            "already defined at $.project.fields[0]",
        ),
        ("$.project.fields[2].default", "not one of the options"),
        ("$.project.fields[3].unit", "not a unit of this dimension"),
        ("$.project.fields[4].name", "reserved"),
        (
            "$.project.fields[5].visible_if",
            "unexpected end of formula",
        ),
        ("$.project.computed[0].expr", "unknown name nope"),
        ("$.project.computed[1].options_from", "only for overridable"),
        ("$.item_tables[0].group_field", "zz is not a field"),
        ("$.tables[0].rows[0].k", "not a valid text value"),
        ("$.outputs[0].code", "either code or code_template"),
        ("$.outputs[1].id", "already used at $.outputs[0]"),
        ("$.outputs[1].percent_of_parent", "only child rules"),
        ("$.outputs[1].children[0].scope", "parent's scope"),
        ("$.outputs[2].table", "only for item scope"),
        ("$.outputs[2].when", "expected a yes/no value"),
        ("$.validations[0].message", "unclosed"),
        ("$.validations[0].field", "unknown field nope"),
    ];
    for (p, m) in expect {
        assert!(has(&errs, p, m), "missing {p}: {m}\n{errs:#?}");
    }
    // The table has an error, so the child rule's lookup reports the unknown table.
    assert!(
        has(&errs, "$.outputs[1].children[0].code", "unknown table t"),
        "{errs:#?}"
    );
    assert!(
        has(
            &errs,
            "$.outputs[1].children[0].quantity",
            "expected a number"
        ),
        "{errs:#?}"
    );
    // Positions inside the formula are kept.
    let e = validate(&def(
        json!({"name": "x", "project": {"computed": [{"name": "f", "expr": "1 + nope"}]}}),
    ));
    assert_eq!((e[0].start, e[0].end), (Some(4), Some(8)));
}

#[test]
fn cycles_are_reported_and_order_follows_dependencies() {
    let errs = errors(json!({
        "name": "x",
        "project": {
            "fields": [ { "name": "a", "type": "number", "default_expr": "c + 1" } ],
            "computed": [
                { "name": "b", "expr": "a * 2" },
                { "name": "c", "expr": "b - 1" },
                { "name": "s", "expr": "s" }
            ]
        }
    }));
    assert!(
        has(
            &errs,
            "$.project.fields[0]",
            "circular dependency: a → c → b → a"
        ),
        "{errs:#?}"
    );
    assert!(
        has(&errs, "$.project.computed[2]", "circular dependency: s → s"),
        "{errs:#?}"
    );

    // Across scopes: project → items → group → project is fine without a loop ...
    let ok = def(json!({
        "name": "x",
        "project": { "fields": [ { "name": "k", "type": "number", "default": 2 } ],
                     "computed": [ { "name": "total", "expr": "sum(rows, r => r.v)" } ] },
        "group": { "computed": [ { "name": "gk", "expr": "k * 10" } ] },
        "item_tables": [ { "name": "rows", "fields": [ { "name": "n", "type": "number" } ],
                           "computed": [ { "name": "v", "expr": "n * gk" } ] } ]
    }));
    let c = compile(&ok).unwrap();
    let order: Vec<&str> = c.order.iter().map(|i| c.nodes[*i].name.as_str()).collect();
    assert_eq!(order, ["k", "gk", "n", "v", "total"]);
    let e = evaluate(
        &c,
        &inputs(json!({"items": {"rows": [{"n": 1}, {"n": 2.5}]}})),
        &Catalog::default(),
    );
    assert_eq!(e.project[1].value, json!("70"));
    // ... but a project value read by the items that sums the items is a cycle.
    let errs = errors(json!({
        "name": "x",
        "project": { "computed": [ { "name": "total", "expr": "sum(rows, r => r.v)" } ] },
        "item_tables": [ { "name": "rows", "computed": [ { "name": "v", "expr": "total / 2" } ] } ]
    }));
    assert!(
        errs.iter()
            .any(|(_, m)| m.contains("circular dependency: total → rows.v → total")),
        "{errs:#?}"
    );
}

#[test]
fn the_product_of_a_product_filter_is_not_a_dependency() {
    // `p` in the filter is the product being filtered, not the computed value named `p` (which
    // itself reads the field): no cycle.
    let errs = errors(json!({
        "name": "x",
        "project": {
            "fields": [ { "name": "motor", "type": "product", "product_filter": "p.family == 'motors'" } ],
            "computed": [ { "name": "p", "expr": "motor" } ]
        }
    }));
    assert!(
        !errs.iter().any(|(_, m)| m.contains("circular dependency")),
        "{errs:#?}"
    );
}

fn mini(outputs: J) -> Definition {
    def(json!({
        "name": "mini",
        "project": { "fields": [ { "name": "n", "type": "integer", "default": 9 } ] },
        "item_tables": [ { "name": "rows", "item_label": "R{index}", "fields": [
            { "name": "code", "type": "text" }, { "name": "q", "type": "number", "default": 1 } ] } ],
        "outputs": outputs
    }))
}

fn mini_lines(outputs: J, items: J) -> Vec<Line> {
    let c = compile(&mini(outputs)).unwrap_or_else(|e| panic!("{e:#?}"));
    let e = evaluate(
        &c,
        &inputs(json!({"items": {"rows": items}})),
        &Catalog::default(),
    );
    e.lines
}

#[test]
fn output_rules_for_each_merge_children_and_percent() {
    // for_each over chunks: one line per board.
    let lines = mini_lines(
        json!([{ "id": "b", "for_each": "chunks(n, 4)", "code": "'B'", "quantity": "each", "comment": "board {each_index}" }]),
        json!([]),
    );
    let got: Vec<(Decimal, Option<String>)> = lines
        .iter()
        .map(|l| (l.quantity, l.comment.clone()))
        .collect();
    assert_eq!(
        got,
        [
            (dec!(4), Some("board 1".into())),
            (dec!(4), Some("board 2".into())),
            (dec!(1), Some("board 3".into()))
        ]
    );

    // merge_identical: same code and children merge, quantities add, labels listed; children
    // with percent of parent and a parent reference.
    let rules = json!([{ "id": "m", "scope": "item", "code": "code", "quantity": "q", "merge_identical": true,
        "children": [ { "id": "opt", "code": "'OPT-' + parent.code", "quantity": "parent.quantity",
                        "percent_of_parent": "12.5", "percent_base": "parent_net_unit_price" } ] }]);
    let items = json!([{ "code": "A", "q": 2 }, { "code": "B", "q": 1 }, { "code": "A", "q": 3 }]);
    let lines = mini_lines(rules.clone(), items.clone());
    assert_eq!(lines.len(), 2);
    assert_eq!(lines[0].code, "A");
    assert_eq!(lines[0].quantity, dec!(5));
    assert_eq!(lines[0].comment.as_deref(), Some("R1, R3"));
    assert_eq!(lines[0].children[0].code, "OPT-A");
    assert_eq!(lines[0].children[0].quantity, dec!(5));
    assert_eq!(lines[0].children[0].percent_of_parent, Some(dec!(12.5)));
    assert_eq!(
        lines[0].children[0].percent_base.as_deref(),
        Some("parent_net_unit_price")
    );
    assert_eq!(lines[1].comment.as_deref(), Some("R2"));

    // Without merging every item has its own line and no label comment; a zero quantity drops it.
    let mut no_merge = rules;
    no_merge[0]["merge_identical"] = json!(false);
    let lines = mini_lines(
        no_merge,
        json!([{ "code": "A", "q": 2 }, { "code": "A", "q": 0 }, { "code": "A", "q": 1 }]),
    );
    assert_eq!(lines.len(), 2);
    assert_eq!(lines[0].comment, None);

    // An empty code is reported, not quoted.
    let c = compile(&mini(
        json!([{ "id": "e", "scope": "item", "code": "code" }]),
    ))
    .unwrap();
    let e = evaluate(
        &c,
        &inputs(json!({"items": {"rows": [{}]}})),
        &Catalog::default(),
    );
    assert!(e.lines.is_empty());
    assert_eq!(e.issues[0].code, "no_code");

    // A percentage that gives no number is an error, and the child is not priced at its own
    // list price instead.
    let c = compile(&mini(json!([{ "id": "p", "code": "'P'",
        "children": [ { "id": "c", "code": "'C'", "percent_of_parent": "null" } ] }])))
    .unwrap_or_else(|e| panic!("{e:#?}"));
    let e = evaluate(&c, &inputs(json!({})), &Catalog::default());
    assert!(e.lines[0].children.is_empty(), "{:?}", e.lines);
    assert!(
        e.issues.iter().any(|i| i.code == "evaluation_error"
            && i.severity == Severity::Error
            && i.message.contains("percent_of_parent")),
        "{:?}",
        e.issues
    );
}

#[test]
fn group_overrides_and_sections() {
    let d = def(json!({
        "name": "g",
        "project": { "fields": [ { "name": "v", "type": "integer", "default": 1 } ] },
        "group": { "fields": [ { "name": "v", "type": "integer" } ] },
        "item_tables": [ { "name": "rows", "group_field": "g", "fields": [ { "name": "g", "type": "text" } ] } ],
        "outputs": [ { "id": "x", "scope": "item", "code_template": "X{v}" } ]
    }));
    let c = compile(&d).unwrap();
    let e = evaluate(
        &c,
        &inputs(
            json!({"groups": {"B": {"v": 7}}, "items": {"rows": [{"g": "A"}, {"g": "B"}, {}]}}),
        ),
        &Catalog::default(),
    );
    let got: Vec<(String, Option<String>)> = e
        .lines
        .iter()
        .map(|l| (l.code.clone(), l.section.clone()))
        .collect();
    assert_eq!(
        got,
        [
            ("X1".into(), Some("A".into())),
            ("X7".into(), Some("B".into())),
            ("X1".into(), None)
        ]
    );
    let _ = BTreeMap::<String, String>::new();
}

#[test]
fn plc_conveyor_line_licensing_and_buses() {
    let raw: J =
        serde_json::from_str(include_str!("../../../seed/configurators/plc_conveyor_line.json"))
            .unwrap();
    let d: Definition = serde_json::from_value(raw["definition"].clone()).unwrap();
    assert!(validate(&d).is_empty(), "{:?}", validate(&d));
    let c = compile(&d).unwrap();

    // 4 segments x (1 motor + 1 pusher + 1 stamper) = 12 outputs > default 10 license -> error.
    let seg = json!({
        "length_m": 2,
        "ir_sensor": true,
        "analog_4_20ma": true,
        "reject_pusher": true,
        "label_stamper": true
    });
    let over = evaluate(
        &c,
        &inputs(json!({
            "project": { "phases": 3, "plc_licensed_outputs": 10 },
            "items": { "segments": [seg.clone(), seg.clone(), seg.clone(), seg.clone()] }
        })),
        &Catalog::default(),
    );
    assert!(over.has_errors());
    assert!(over
        .issues
        .iter()
        .any(|i| i.code == "plc_license_insufficient" && i.severity == Severity::Error));

    // Upgrading license to 30 outputs clears error, emits PLC-LIC-30, PLC-EXP-RS485,
    // PLC-MASTER, DISP-RS485, MOD-I2C-SWIPE, SENS-I2C-TEMP, MOT-3P-055, VFD-3P-055, and solenoids.
    let upgraded = evaluate(
        &c,
        &inputs(json!({
            "project": {
                "phases": 3,
                "plc_licensed_outputs": 30,
                "networked_master": true,
                "rs485_displays": 2,
                "i2c_swipe_card": true,
                "i2c_temp_sensor": true
            },
            "items": { "segments": [seg.clone(), seg.clone(), seg.clone(), seg] }
        })),
        &Catalog::default(),
    );
    assert!(!upgraded.has_errors(), "{:?}", upgraded.issues);
    assert!(upgraded
        .issues
        .iter()
        .any(|i| i.code == "rs485_expansion_needed" && i.severity == Severity::Info));
    let codes: Vec<(&str, Decimal)> = upgraded
        .lines
        .iter()
        .map(|l| (l.code.as_str(), l.quantity.normalize()))
        .collect();
    for expected in [
        ("CONV-BELT-1M", dec!(8)),
        ("MOT-3P-055", dec!(4)),
        ("VFD-3P-055", dec!(4)),
        ("SENS-IR-24V", dec!(4)),
        ("SENS-420MA", dec!(4)),
        ("SOL-PUSH", dec!(4)),
        ("SOL-LABEL", dec!(4)),
        ("PLC-BASE", dec!(1)),
        ("PLC-LIC-30", dec!(1)),
        ("PLC-EXP-RS485", dec!(1)),
        ("PLC-MASTER", dec!(1)),
        ("DISP-RS485", dec!(2)),
        ("MOD-I2C-SWIPE", dec!(2)),
        ("SENS-I2C-TEMP", dec!(2)),
    ] {
        assert!(codes.contains(&expected), "missing {expected:?} in {codes:?}");
    }
}
