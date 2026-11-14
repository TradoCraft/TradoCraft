//! Advisory product matching for an opportunity (ADR 0068, decision 7): a pure function that
//! judges one product against the site baseline, the admin-defined match rules and the result of
//! the power grid check. Missing data is `unknown`, never `unsuitable`; nothing is hidden.
//! Loading the inputs lives in [`crate::matching_api`].

use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::HashMap;
use tradocraft_products::power::{PowerCompatibility, PowerGrid, PowerSupply};
use utoipa::ToSchema;

use crate::baseline::BaselineItem;

/// How a baseline value is compared with a product attribute.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum Operator {
    /// The baseline value lies within the product's `range` (bounds included).
    WithinRange,
    /// The baseline value is at most the product's `number`.
    AtMost,
    /// The baseline value is at least the product's `number`.
    AtLeast,
}

impl Operator {
    pub fn as_str(self) -> &'static str {
        match self {
            Operator::WithinRange => "within_range",
            Operator::AtMost => "at_most",
            Operator::AtLeast => "at_least",
        }
    }

    pub fn parse(s: &str) -> Option<Self> {
        match s {
            "within_range" => Some(Operator::WithinRange),
            "at_most" => Some(Operator::AtMost),
            "at_least" => Some(Operator::AtLeast),
            _ => None,
        }
    }
}

/// One admin-defined rule: a baseline attribute that must fit a product attribute.
#[derive(Debug, Clone, PartialEq)]
pub struct Rule {
    pub name: String,
    pub baseline_type_code: String,
    pub baseline_attribute_key: String,
    pub product_attribute_key: String,
    pub operator: Operator,
    pub active: bool,
}

/// One baseline item, flattened out of the tree (nesting is irrelevant for matching).
#[derive(Debug, Clone, PartialEq)]
pub struct BaselineNode {
    pub type_code: String,
    pub name: Option<String>,
    pub values: Value,
}

/// Every item of the tree, groups included, depth first.
pub fn flatten(tree: &[BaselineItem]) -> Vec<BaselineNode> {
    let mut out = Vec::new();
    for item in tree {
        out.push(BaselineNode {
            type_code: item.type_code.clone(),
            name: item.name.clone(),
            values: item.values.clone(),
        });
        out.extend(flatten(&item.children));
    }
    out
}

/// A product attribute as the matcher sees it (text and boolean attributes are not matchable).
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum ProductValue {
    Number(f64),
    Range { min: f64, max: f64 },
}

/// What is known about one product.
#[derive(Debug, Clone)]
pub struct ProductFacts {
    pub attributes: HashMap<String, ProductValue>,
    pub power: PowerCompatibility,
}

/// The product attribute that says what motor a product is (kW, a `number` attribute).
pub const MOTOR_KW_KEY: &str = "motor_kw";

/// The motor a bell needs, derived from the admin lookup tables of the configurator
/// (`tradocraft_configurator::motor`). The derivation lives there; the matcher only compares.
#[derive(Debug, Clone, PartialEq)]
pub struct RequiredMotor {
    pub kw: f64,
    /// The motor size or class of the matching table row, e.g. `71`.
    pub size: String,
    pub brand: String,
    pub phases: i64,
    pub weight_per_wheel_kg: f64,
    /// The motion the tables were read with (`falling` or `flying`).
    pub effective_motion: String,
    /// How many weight classes the motion moved the choice up.
    pub bumped_classes: i64,
}

/// Why no motor could be derived. The payload is the message shown to the user.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MotorError {
    /// No motor in the tables is big enough.
    TooLarge(String),
    /// A needed value (weight, motion, phases, tables) is missing or unknown.
    MissingData(String),
    /// The tables have no motor for the phases (or brand), or the phases cap the power.
    NotAvailableForPhases(String),
}

impl std::fmt::Display for MotorError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let (MotorError::TooLarge(m)
        | MotorError::MissingData(m)
        | MotorError::NotAvailableForPhases(m)) = self;
        f.write_str(m)
    }
}

/// The derived motor of one bell of the baseline.
#[derive(Debug, Clone, PartialEq)]
pub struct BellMotor {
    /// How the bell is named in messages, see [`node_label`].
    pub label: String,
    pub result: Result<RequiredMotor, MotorError>,
}

/// What the opportunity offers to match against.
#[derive(Debug, Clone)]
pub struct Site<'a> {
    pub baseline: &'a [BaselineNode],
    pub rules: &'a [Rule],
    /// The derived motor per bell (empty when there are no bells).
    pub bell_motors: &'a [BellMotor],
    /// Whether the opportunity has a power grid.
    pub has_grid: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum MatchStatus {
    Suitable,
    Unsuitable,
    Unknown,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum CheckStatus {
    Ok,
    Fail,
    Unknown,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, ToSchema)]
pub struct Reason {
    /// `power`, `baseline`, `motor` or `rule:<rule name>`.
    pub check: String,
    pub status: CheckStatus,
    pub message: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, ToSchema)]
pub struct Evaluation {
    pub status: MatchStatus,
    pub reasons: Vec<Reason>,
}

/// The overall status: any failure makes the product unsuitable, otherwise any unknown makes it
/// unknown. Nothing to say at all is suitable.
pub fn overall(reasons: &[Reason]) -> MatchStatus {
    if reasons.iter().any(|r| r.status == CheckStatus::Fail) {
        MatchStatus::Unsuitable
    } else if reasons.iter().any(|r| r.status == CheckStatus::Unknown) {
        MatchStatus::Unknown
    } else {
        MatchStatus::Suitable
    }
}

fn describe_supply(s: &PowerSupply) -> String {
    if s.current_type == "dc" {
        return format!("{}V DC", s.voltage_v);
    }
    let volts = match (s.voltage_min_v, s.voltage_max_v) {
        (Some(lo), Some(hi)) => format!("{lo}-{hi}V"),
        _ => format!("{}V", s.voltage_v),
    };
    let tolerance = if s.voltage_min_v.is_some() {
        String::new()
    } else {
        format!(" (+/-{}%)", s.tolerance_pct)
    };
    format!(
        "{volts} {}-phase {}Hz{tolerance}",
        s.phases.unwrap_or(1),
        s.frequency_hz
            .map_or("50/60".to_string(), |f| f.to_string()),
    )
}

fn describe_grid(g: &PowerGrid) -> String {
    format!(
        "{} ({}V {}-phase {}Hz)",
        g.name, g.voltage_v, g.phases, g.frequency_hz
    )
}

fn join<T>(items: &[T], f: impl Fn(&T) -> String) -> String {
    items.iter().map(f).collect::<Vec<_>>().join(" / ")
}

fn power_reason(power: &PowerCompatibility, has_grid: bool) -> Option<Reason> {
    let (status, message) = match power {
        PowerCompatibility::NotApplicable => return None,
        PowerCompatibility::NeedsExternalSupply => (
            CheckStatus::Ok,
            "needs an external power supply".to_string(),
        ),
        PowerCompatibility::Compatible => (
            CheckStatus::Ok,
            "runs on the power grid of the site".to_string(),
        ),
        PowerCompatibility::Incompatible {
            supported,
            available,
        } => (
            CheckStatus::Fail,
            format!(
                "runs on {} but the site grid offers {}",
                join(supported, describe_supply),
                join(available, describe_grid)
            ),
        ),
        PowerCompatibility::UnknownGrid => (
            CheckStatus::Unknown,
            if has_grid {
                "no data for the power grid of the site; the fit is unknown".to_string()
            } else {
                "the opportunity has no power grid; the fit is unknown".to_string()
            },
        ),
    };
    Some(Reason {
        check: "power".into(),
        status,
        message,
    })
}

pub fn node_label(n: &BaselineNode) -> String {
    match &n.name {
        Some(name) => format!("{} \"{name}\"", n.type_code),
        None => n.type_code.clone(),
    }
}

/// The reason one baseline item gives for one rule, or `None` when the rule does not apply to the
/// product (it lacks the attribute, or has it in a shape the operator cannot use).
fn rule_reason(rule: &Rule, node: &BaselineNode, product: &ProductFacts) -> Option<Reason> {
    let target = product.attributes.get(&rule.product_attribute_key)?;
    let (bk, pk) = (&rule.baseline_attribute_key, &rule.product_attribute_key);
    let label = node_label(node);
    let shown = match (rule.operator, target) {
        (Operator::WithinRange, ProductValue::Range { min, max }) => format!("{min}..{max}"),
        (Operator::AtMost | Operator::AtLeast, ProductValue::Number(n)) => n.to_string(),
        _ => return None,
    };
    let check = format!("rule:{}", rule.name);
    let Some(v) = node.values.get(bk).and_then(Value::as_f64) else {
        return Some(Reason {
            check,
            status: CheckStatus::Unknown,
            message: format!("{label}: no {bk} recorded, the fit with {pk} {shown} is unknown"),
        });
    };
    let (fits, text) = match (rule.operator, target) {
        (Operator::WithinRange, ProductValue::Range { min, max }) => {
            let fits = (*min..=*max).contains(&v);
            let word = if fits { "within" } else { "outside" };
            (fits, format!("is {word} {pk} {shown}"))
        }
        (Operator::AtMost, ProductValue::Number(n)) => {
            let fits = v <= *n;
            let word = if fits { "within" } else { "above" };
            (fits, format!("is {word} the maximum {pk} {shown}"))
        }
        (Operator::AtLeast, ProductValue::Number(n)) => {
            let fits = v >= *n;
            let word = if fits { "within" } else { "below" };
            (fits, format!("is {word} the minimum {pk} {shown}"))
        }
        _ => return None,
    };
    Some(Reason {
        check,
        status: if fits {
            CheckStatus::Ok
        } else {
            CheckStatus::Fail
        },
        message: format!("{label}: {bk} {v} {text}"),
    })
}

/// The reason one bell's motor gives for a product that declares `motor_kw`: its motor must be at
/// least as strong as the derived one. Phases are covered by the power check.
fn motor_reason(bell: &BellMotor, product: &ProductFacts) -> Option<Reason> {
    let ProductValue::Number(have) = product.attributes.get(MOTOR_KW_KEY)? else {
        return None;
    };
    let label = &bell.label;
    let (status, message) = match &bell.result {
        Ok(m) => {
            let fits = *have >= m.kw;
            (
                if fits { CheckStatus::Ok } else { CheckStatus::Fail },
                format!(
                    "{label}: needs a motor of at least {} kW (size {}, {}), the product's {have} kW is {}",
                    m.kw,
                    m.size,
                    m.brand,
                    if fits { "enough" } else { "too small" }
                ),
            )
        }
        Err(e @ MotorError::MissingData(_)) => (CheckStatus::Unknown, format!("{label}: {e}")),
        Err(e) => (CheckStatus::Fail, format!("{label}: {e}")),
    };
    Some(Reason {
        check: "motor".into(),
        status,
        message,
    })
}

/// Judges one product. With an empty baseline and no grid there is nothing to judge against, so
/// the answer is `unknown` with a single reason rather than a vacuous "suitable".
pub fn evaluate(site: &Site, product: &ProductFacts) -> Evaluation {
    if site.baseline.is_empty() && !site.has_grid {
        return Evaluation {
            status: MatchStatus::Unknown,
            reasons: vec![Reason {
                check: "baseline".into(),
                status: CheckStatus::Unknown,
                message: "no baseline data".into(),
            }],
        };
    }
    let mut reasons: Vec<Reason> = power_reason(&product.power, site.has_grid)
        .into_iter()
        .collect();
    for rule in site.rules.iter().filter(|r| r.active) {
        reasons.extend(
            site.baseline
                .iter()
                .filter(|n| n.type_code == rule.baseline_type_code)
                .filter_map(|n| rule_reason(rule, n, product)),
        );
    }
    reasons.extend(
        site.bell_motors
            .iter()
            .filter_map(|b| motor_reason(b, product)),
    );
    Evaluation {
        status: overall(&reasons),
        reasons,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::Utc;
    use serde_json::json;
    use uuid::Uuid;

    fn node(type_code: &str, name: Option<&str>, values: Value) -> BaselineNode {
        BaselineNode {
            type_code: type_code.into(),
            name: name.map(str::to_string),
            values,
        }
    }

    fn dial(mm: f64) -> BaselineNode {
        node("clock_dial", None, json!({ "dial_diameter_mm": mm }))
    }

    fn rule(op: Operator) -> Rule {
        Rule {
            name: "Dial size fits product".into(),
            baseline_type_code: "clock_dial".into(),
            baseline_attribute_key: "dial_diameter_mm".into(),
            product_attribute_key: "dial_size_mm".into(),
            operator: op,
            active: true,
        }
    }

    fn product(v: Option<ProductValue>) -> ProductFacts {
        ProductFacts {
            attributes: v
                .map(|v| HashMap::from([("dial_size_mm".to_string(), v)]))
                .unwrap_or_default(),
            power: PowerCompatibility::NotApplicable,
        }
    }

    fn range(min: f64, max: f64) -> Option<ProductValue> {
        Some(ProductValue::Range { min, max })
    }

    fn run(baseline: &[BaselineNode], rules: &[Rule], p: &ProductFacts) -> Evaluation {
        evaluate(
            &Site {
                baseline,
                rules,
                has_grid: true,
                bell_motors: &[],
            },
            p,
        )
    }

    fn statuses(e: &Evaluation) -> Vec<CheckStatus> {
        e.reasons.iter().map(|r| r.status).collect()
    }

    #[test]
    fn within_range_includes_both_bounds() {
        let rules = [rule(Operator::WithinRange)];
        let p = product(range(800.0, 1400.0));
        for (mm, expected) in [
            (800.0, MatchStatus::Suitable),
            (1400.0, MatchStatus::Suitable),
            (1000.0, MatchStatus::Suitable),
            (799.9, MatchStatus::Unsuitable),
            (1400.1, MatchStatus::Unsuitable),
        ] {
            assert_eq!(run(&[dial(mm)], &rules, &p).status, expected, "{mm}");
        }
    }

    #[test]
    fn within_range_messages_carry_the_numbers() {
        let rules = [rule(Operator::WithinRange)];
        let p = product(range(800.0, 1400.0));
        let ok = run(&[dial(1000.0)], &rules, &p);
        assert_eq!(ok.reasons.len(), 1);
        assert_eq!(ok.reasons[0].check, "rule:Dial size fits product");
        assert_eq!(ok.reasons[0].status, CheckStatus::Ok);
        assert_eq!(
            ok.reasons[0].message,
            "clock_dial: dial_diameter_mm 1000 is within dial_size_mm 800..1400"
        );
        let bad = run(&[dial(1500.5)], &rules, &p);
        assert_eq!(
            bad.reasons[0].message,
            "clock_dial: dial_diameter_mm 1500.5 is outside dial_size_mm 800..1400"
        );
    }

    #[test]
    fn at_most_and_at_least_include_the_limit() {
        let most = [rule(Operator::AtMost)];
        let least = [rule(Operator::AtLeast)];
        let p = product(Some(ProductValue::Number(1000.0)));
        assert_eq!(
            run(&[dial(1000.0)], &most, &p).status,
            MatchStatus::Suitable
        );
        assert_eq!(
            run(&[dial(1000.1)], &most, &p).status,
            MatchStatus::Unsuitable
        );
        assert_eq!(
            run(&[dial(1000.0)], &least, &p).status,
            MatchStatus::Suitable
        );
        assert_eq!(
            run(&[dial(999.9)], &least, &p).status,
            MatchStatus::Unsuitable
        );
        let e = run(&[dial(1200.0)], &most, &p);
        assert_eq!(
            e.reasons[0].message,
            "clock_dial: dial_diameter_mm 1200 is above the maximum dial_size_mm 1000"
        );
        let e = run(&[dial(900.0)], &least, &p);
        assert_eq!(
            e.reasons[0].message,
            "clock_dial: dial_diameter_mm 900 is below the minimum dial_size_mm 1000"
        );
    }

    #[test]
    fn a_product_without_the_attribute_is_not_judged_by_the_rule() {
        let e = run(
            &[dial(5000.0)],
            &[rule(Operator::WithinRange)],
            &product(None),
        );
        assert_eq!(e.status, MatchStatus::Suitable);
        assert!(e.reasons.is_empty());
    }

    #[test]
    fn a_product_attribute_of_the_wrong_shape_is_not_judged_either() {
        let p = product(Some(ProductValue::Number(1.0)));
        let e = run(&[dial(5000.0)], &[rule(Operator::WithinRange)], &p);
        assert!(e.reasons.is_empty());
        let p = product(range(1.0, 2.0));
        let e = run(&[dial(5000.0)], &[rule(Operator::AtMost)], &p);
        assert!(e.reasons.is_empty());
    }

    #[test]
    fn a_baseline_without_an_item_of_the_type_makes_the_rule_not_applicable() {
        let bell = node("bell", None, json!({ "weight_kg": 100 }));
        let e = run(
            &[bell],
            &[rule(Operator::WithinRange)],
            &product(range(1.0, 2.0)),
        );
        assert_eq!(e.status, MatchStatus::Suitable);
        assert!(e.reasons.is_empty());
    }

    #[test]
    fn a_missing_baseline_value_is_unknown_not_unsuitable() {
        let blank = node("clock_dial", Some("south face"), json!({}));
        let e = run(
            &[blank],
            &[rule(Operator::WithinRange)],
            &product(range(1.0, 2.0)),
        );
        assert_eq!(e.status, MatchStatus::Unknown);
        assert_eq!(e.reasons[0].status, CheckStatus::Unknown);
        assert_eq!(
            e.reasons[0].message,
            "clock_dial \"south face\": no dial_diameter_mm recorded, the fit with dial_size_mm 1..2 is unknown"
        );
    }

    #[test]
    fn a_product_must_fit_every_dial() {
        let rules = [rule(Operator::WithinRange)];
        let p = product(range(600.0, 1000.0));
        let e = run(&[dial(800.0), dial(1400.0)], &rules, &p);
        assert_eq!(e.status, MatchStatus::Unsuitable);
        assert_eq!(statuses(&e), [CheckStatus::Ok, CheckStatus::Fail]);
        let e = run(&[dial(800.0), dial(900.0)], &rules, &p);
        assert_eq!(e.status, MatchStatus::Suitable);
        assert_eq!(statuses(&e), [CheckStatus::Ok, CheckStatus::Ok]);
    }

    #[test]
    fn a_failure_outweighs_an_unknown() {
        let rules = [rule(Operator::WithinRange)];
        let blank = node("clock_dial", None, json!({}));
        let e = run(
            &[blank, dial(1400.0)],
            &rules,
            &product(range(600.0, 1000.0)),
        );
        assert_eq!(e.status, MatchStatus::Unsuitable);
        assert_eq!(statuses(&e), [CheckStatus::Unknown, CheckStatus::Fail]);
    }

    fn item(type_code: &str, values: Value, children: Vec<BaselineItem>) -> BaselineItem {
        BaselineItem {
            id: Uuid::now_v7(),
            parent_id: None,
            type_code: type_code.into(),
            name: None,
            quantity: 1,
            values,
            sort_order: 0,
            created_at: Utc::now(),
            updated_at: Utc::now(),
            children,
        }
    }

    #[test]
    fn items_nested_in_groups_count() {
        let tree = vec![item(
            "assembly",
            json!({}),
            vec![item(
                "clock_dial",
                json!({ "dial_diameter_mm": 1400 }),
                vec![],
            )],
        )];
        let flat = flatten(&tree);
        assert_eq!(flat.len(), 2);
        let e = run(
            &flat,
            &[rule(Operator::WithinRange)],
            &product(range(600.0, 1000.0)),
        );
        assert_eq!(e.status, MatchStatus::Unsuitable);
    }

    fn grid() -> PowerGrid {
        PowerGrid {
            id: Uuid::now_v7(),
            country_code: "BE".into(),
            name: "BE 3x400V".into(),
            voltage_v: 400,
            phases: 3,
            frequency_hz: 50,
            active: true,
        }
    }

    fn supply(v: i32, phases: i16) -> PowerSupply {
        PowerSupply {
            id: Uuid::now_v7(),
            current_type: "ac".into(),
            voltage_v: v,
            phases: Some(phases),
            frequency_hz: Some(50),
            tolerance_pct: 10,
            voltage_min_v: None,
            voltage_max_v: None,
        }
    }

    #[test]
    fn a_power_failure_and_a_fitting_rule_make_the_product_unsuitable() {
        let mut p = product(range(600.0, 1400.0));
        p.power = PowerCompatibility::Incompatible {
            supported: vec![supply(230, 1)],
            available: vec![grid()],
        };
        let e = run(&[dial(800.0)], &[rule(Operator::WithinRange)], &p);
        assert_eq!(e.status, MatchStatus::Unsuitable);
        assert_eq!(e.reasons[0].check, "power");
        assert_eq!(e.reasons[0].status, CheckStatus::Fail);
        assert_eq!(
            e.reasons[0].message,
            "runs on 230V 1-phase 50Hz (+/-10%) but the site grid offers BE 3x400V (400V 3-phase 50Hz)"
        );
        assert_eq!(e.reasons[1].check, "rule:Dial size fits product");
        assert_eq!(e.reasons[1].status, CheckStatus::Ok);
    }

    #[test]
    fn power_results_map_to_reasons() {
        let cases = [
            (PowerCompatibility::Compatible, Some(CheckStatus::Ok)),
            (PowerCompatibility::UnknownGrid, Some(CheckStatus::Unknown)),
            (
                PowerCompatibility::NeedsExternalSupply,
                Some(CheckStatus::Ok),
            ),
            (PowerCompatibility::NotApplicable, None),
        ];
        for (power, expected) in cases {
            let mut p = product(None);
            p.power = power.clone();
            let e = run(&[dial(800.0)], &[], &p);
            assert_eq!(e.reasons.first().map(|r| r.status), expected, "{power:?}");
            assert!(e.reasons.iter().all(|r| r.check == "power"));
        }
        let mut p = product(None);
        p.power = PowerCompatibility::NeedsExternalSupply;
        let e = run(&[dial(800.0)], &[], &p);
        assert_eq!(e.reasons[0].message, "needs an external power supply");
    }

    #[test]
    fn an_electrical_product_without_a_grid_is_unknown() {
        let mut p = product(None);
        p.power = PowerCompatibility::UnknownGrid;
        let site = Site {
            baseline: &[dial(800.0)],
            rules: &[],
            has_grid: false,
            bell_motors: &[],
        };
        let e = evaluate(&site, &p);
        assert_eq!(e.status, MatchStatus::Unknown);
        assert_eq!(
            e.reasons[0].message,
            "the opportunity has no power grid; the fit is unknown"
        );
    }

    #[test]
    fn an_empty_baseline_without_a_grid_is_unknown_for_every_product() {
        let site = Site {
            baseline: &[],
            rules: &[rule(Operator::WithinRange)],
            has_grid: false,
            bell_motors: &[],
        };
        for p in [product(None), product(range(1.0, 2.0))] {
            let e = evaluate(&site, &p);
            assert_eq!(e.status, MatchStatus::Unknown);
            assert_eq!(
                e.reasons,
                [Reason {
                    check: "baseline".into(),
                    status: CheckStatus::Unknown,
                    message: "no baseline data".into()
                }]
            );
        }
    }

    #[test]
    fn an_empty_baseline_with_a_grid_is_judged_on_power_alone() {
        let mut p = product(range(1.0, 2.0));
        p.power = PowerCompatibility::Compatible;
        let e = run(&[], &[rule(Operator::WithinRange)], &p);
        assert_eq!(e.status, MatchStatus::Suitable);
        assert_eq!(e.reasons.len(), 1);
        assert_eq!(e.reasons[0].check, "power");
    }

    #[test]
    fn inactive_rules_are_ignored() {
        let mut r = rule(Operator::WithinRange);
        r.active = false;
        let e = run(&[dial(5000.0)], &[r], &product(range(1.0, 2.0)));
        assert_eq!(e.status, MatchStatus::Suitable);
        assert!(e.reasons.is_empty());
    }

    #[test]
    fn nothing_applicable_is_suitable_without_reasons() {
        let e = run(&[dial(800.0)], &[], &product(None));
        assert_eq!(e.status, MatchStatus::Suitable);
        assert!(e.reasons.is_empty());
    }

    #[test]
    fn overall_status_precedence() {
        let r = |s| Reason {
            check: "x".into(),
            status: s,
            message: String::new(),
        };
        use CheckStatus::*;
        assert_eq!(overall(&[]), MatchStatus::Suitable);
        assert_eq!(overall(&[r(Ok), r(Unknown)]), MatchStatus::Unknown);
        assert_eq!(
            overall(&[r(Unknown), r(Fail), r(Ok)]),
            MatchStatus::Unsuitable
        );
    }

    fn bell(name: &str) -> BaselineNode {
        node("bell", Some(name), json!({}))
    }

    fn motor(kw: f64) -> Result<RequiredMotor, MotorError> {
        Ok(RequiredMotor {
            kw,
            size: "71".into(),
            brand: "mez_1000".into(),
            phases: 3,
            weight_per_wheel_kg: 450.0,
            effective_motion: "falling".into(),
            bumped_classes: 0,
        })
    }

    fn motor_product(kw: Option<f64>) -> ProductFacts {
        let mut p = product(None);
        if let Some(kw) = kw {
            p.attributes
                .insert(MOTOR_KW_KEY.to_string(), ProductValue::Number(kw));
        }
        p
    }

    fn run_motors(bells: &[BellMotor], p: &ProductFacts) -> Evaluation {
        evaluate(
            &Site {
                baseline: &[bell("Bourdon")],
                rules: &[],
                has_grid: true,
                bell_motors: bells,
            },
            p,
        )
    }

    fn bell_motor(result: Result<RequiredMotor, MotorError>) -> BellMotor {
        BellMotor {
            label: node_label(&bell("Bourdon")),
            result,
        }
    }

    #[test]
    fn a_motor_at_least_as_strong_as_required_fits_including_the_boundary() {
        let bells = [bell_motor(motor(0.25))];
        for (kw, expected) in [
            (0.25, MatchStatus::Suitable),
            (0.37, MatchStatus::Suitable),
            (0.18, MatchStatus::Unsuitable),
        ] {
            let e = run_motors(&bells, &motor_product(Some(kw)));
            assert_eq!(e.status, expected, "{kw}");
            assert_eq!(e.reasons.len(), 1);
            assert_eq!(e.reasons[0].check, "motor");
        }
        let e = run_motors(&bells, &motor_product(Some(0.18)));
        assert_eq!(
            e.reasons[0].message,
            "bell \"Bourdon\": needs a motor of at least 0.25 kW (size 71, mez_1000), the product's 0.18 kW is too small"
        );
        let e = run_motors(&bells, &motor_product(Some(0.37)));
        assert_eq!(
            e.reasons[0].message,
            "bell \"Bourdon\": needs a motor of at least 0.25 kW (size 71, mez_1000), the product's 0.37 kW is enough"
        );
    }

    #[test]
    fn products_without_motor_kw_are_not_judged_by_the_motor_check() {
        let bells = [bell_motor(motor(0.25))];
        let e = run_motors(&bells, &motor_product(None));
        assert_eq!(e.status, MatchStatus::Suitable);
        assert!(e.reasons.is_empty());
    }

    #[test]
    fn motor_errors_map_to_fail_or_unknown_with_the_message() {
        let cases = [
            (
                MotorError::TooLarge("too heavy".into()),
                CheckStatus::Fail,
                MatchStatus::Unsuitable,
            ),
            (
                MotorError::NotAvailableForPhases("no 1-phase".into()),
                CheckStatus::Fail,
                MatchStatus::Unsuitable,
            ),
            (
                MotorError::MissingData("no weight".into()),
                CheckStatus::Unknown,
                MatchStatus::Unknown,
            ),
        ];
        for (err, check, status) in cases {
            let text = err.to_string();
            let e = run_motors(&[bell_motor(Err(err))], &motor_product(Some(5.0)));
            assert_eq!(e.status, status);
            assert_eq!(e.reasons[0].status, check);
            assert_eq!(e.reasons[0].message, format!("bell \"Bourdon\": {text}"));
        }
    }

    #[test]
    fn the_product_must_fit_every_bell() {
        let bells = [bell_motor(motor(0.12)), bell_motor(motor(0.55))];
        let e = run_motors(&bells, &motor_product(Some(0.25)));
        assert_eq!(e.status, MatchStatus::Unsuitable);
        assert_eq!(statuses(&e), [CheckStatus::Ok, CheckStatus::Fail]);
    }
}
