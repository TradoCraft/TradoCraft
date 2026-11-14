//! Bell motor derivation (ADR 0068, decision 6 and Phase 5b): which motor a bell needs, read from
//! admin-editable configurator lookup tables with [`CompiledTable::lookup`], the same engine the
//! formulas use. The tables live in the active revision of the model [`MODEL_CODE`] of the
//! company (seeded by migration `20270213000001`) and hold every domain rule:
//!
//! * `motion_rules` (key `motion`, column `effective`): the motion the motor tables are read with,
//!   `falling` or `flying`.
//! * `motion_bumps` (keys `phases`, `brand`, `motion`, column `bump`): how many weight classes a
//!   motion moves the choice up on top of the first class that fits; no row means none.
//! * `phase_limits` (key `phases`, column `max_kw`): the largest motor the phases allow; an empty
//!   cell is no limit.
//! * `motors` (keys `phases`, `brand`, `motion`, range `weight_kg` over `weight_min_kg` ..
//!   `weight_max_kg`, columns `kw`, `size`): the first class whose maximum is at or above the
//!   weight per wheel; above the largest class a bell is too large.
//!
//! [`required_motor`] is pure; [`ConfiguratorMotors`] loads the tables and plugs it into the
//! product matching of `tradocraft_crm`.

use std::collections::BTreeMap;

use rust_decimal::prelude::{FromPrimitive, ToPrimitive};
use sqlx::PgConnection;
use tradocraft_core::{AppError, AppResult};
use tradocraft_crm::matching::BaselineNode;
use tradocraft_crm::product_matches::{BellMotorProvider, BoxFuture};
use uuid::Uuid;

use crate::definition::{self, Definition, TableKind};
use crate::expr::Value;
use crate::tables::CompiledTable;

pub use tradocraft_crm::matching::{MotorError, RequiredMotor};

/// Code of the configurator model that holds the motor tables.
pub const MODEL_CODE: &str = "bell_motors";

/// The bell values the derivation reads (baseline attributes `weight_kg`, `motion`, `num_wheels`).
#[derive(Debug, Clone, Default, PartialEq)]
pub struct BellInput {
    pub weight_kg: Option<f64>,
    pub motion: Option<String>,
    /// The weight is shared over the wheels; one wheel when absent.
    pub num_wheels: Option<f64>,
}

/// The four compiled lookup tables.
#[derive(Debug, Clone)]
pub struct MotorTables {
    motion_rules: CompiledTable,
    motion_bumps: CompiledTable,
    phase_limits: CompiledTable,
    motors: CompiledTable,
}

impl MotorTables {
    /// Compiles the tables of a definition and checks their shape (names, keys, columns).
    pub fn from_definition(def: &Definition) -> Result<Self, String> {
        let get = |name: &str,
                   kind: TableKind,
                   keys: &[&str],
                   columns: &[&str],
                   range_key: Option<&str>|
         -> Result<CompiledTable, String> {
            let t = def
                .tables
                .iter()
                .find(|t| t.name == name)
                .ok_or_else(|| format!("the motor tables lack the table {name}"))?;
            let has = |c: &&str| t.columns.iter().any(|x| x.name == **c);
            let missing: Vec<&str> = keys
                .iter()
                .chain(columns)
                .filter(|c| !has(c))
                .copied()
                .collect();
            if !missing.is_empty() {
                return Err(format!(
                    "table {name} lacks the columns {}",
                    missing.join(", ")
                ));
            }
            if t.kind != kind
                || t.keys != keys
                || t.range.as_ref().map(|r| r.key.as_str()) != range_key
            {
                return Err(format!("table {name} has the wrong kind or keys"));
            }
            CompiledTable::compile(t, name).map_err(|e| {
                e.into_iter()
                    .map(|e| format!("{}: {}", e.path, e.message))
                    .collect::<Vec<_>>()
                    .join("; ")
            })
        };
        Ok(MotorTables {
            motion_rules: get(
                "motion_rules",
                TableKind::Exact,
                &["motion"],
                &["effective"],
                None,
            )?,
            motion_bumps: get(
                "motion_bumps",
                TableKind::Exact,
                &["phases", "brand", "motion"],
                &["bump"],
                None,
            )?,
            phase_limits: get(
                "phase_limits",
                TableKind::Exact,
                &["phases"],
                &["max_kw"],
                None,
            )?,
            motors: get(
                "motors",
                TableKind::Range,
                &["phases", "brand", "motion"],
                &["kw", "size"],
                Some("weight_kg"),
            )?,
        })
    }

    pub fn from_json(v: &serde_json::Value) -> Result<Self, String> {
        let def = definition::from_json(v).map_err(|e| e.message)?;
        Self::from_definition(&def)
    }

    fn rows<'a>(
        &'a self,
        phases: i64,
        brand: Option<&'a str>,
        motion: Option<&'a str>,
    ) -> impl Iterator<Item = &'a BTreeMap<String, Value>> {
        self.motors.rows.iter().filter(move |r| {
            r.get("phases").and_then(Value::as_int) == Some(phases)
                && brand.is_none_or(|b| text(r.get("brand")) == b)
                && motion.is_none_or(|m| text(r.get("motion")) == m)
        })
    }
}

fn text(v: Option<&Value>) -> &str {
    match v {
        Some(Value::Str(s)) => s,
        _ => "",
    }
}

fn dec(x: f64) -> Value {
    rust_decimal::Decimal::from_f64(x).map_or(Value::Null, Value::Dec)
}

fn keys<const N: usize>(pairs: [(&str, Value); N]) -> BTreeMap<String, Value> {
    pairs.into_iter().map(|(k, v)| (k.to_string(), v)).collect()
}

fn field(v: &Value, name: &str) -> Option<Value> {
    match v {
        Value::Record(r) => r.get(name).cloned().filter(|v| !v.is_null()),
        _ => None,
    }
}

/// One brand: the first class at or above the weight per wheel, moved up by the motion bump, and
/// held against the limit of the phases.
fn for_brand(
    tables: &MotorTables,
    phases: i64,
    brand: &str,
    motion: &str,
    effective: &str,
    per_wheel: f64,
) -> Result<RequiredMotor, MotorError> {
    let internal = |e: String| MotorError::MissingData(e);
    if tables
        .rows(phases, Some(brand), Some(effective))
        .next()
        .is_none()
    {
        return Err(MotorError::NotAvailableForPhases(format!(
            "there are no {brand} {effective}-motion motors for {phases}-phase"
        )));
    }
    let bump = tables
        .motion_bumps
        .lookup(
            &keys([
                ("phases", Value::Int(phases)),
                ("brand", Value::Str(brand.into())),
                ("motion", Value::Str(motion.into())),
            ]),
            0,
        )
        .map_err(internal)?;
    let bump = field(&bump, "bump")
        .and_then(|v| v.as_int())
        .unwrap_or(0)
        .max(0);
    let row = tables
        .motors
        .lookup(
            &keys([
                ("phases", Value::Int(phases)),
                ("brand", Value::Str(brand.into())),
                ("motion", Value::Str(effective.into())),
                ("weight_kg", dec(per_wheel)),
            ]),
            bump,
        )
        .map_err(|_| MotorError::TooLarge(String::new()))?;
    let (Some(kw), Some(size)) = (
        field(&row, "kw")
            .and_then(|v| v.as_decimal())
            .and_then(|d| d.to_f64()),
        field(&row, "size"),
    ) else {
        let largest = tables
            .rows(phases, Some(brand), Some(effective))
            .filter_map(|r| r.get("weight_max_kg").and_then(Value::as_decimal))
            .max()
            .map_or(String::new(), |m| m.normalize().to_string());
        let moved = if bump > 0 {
            format!(" (the {motion} motion moves it up {bump} class(es))")
        } else {
            String::new()
        };
        return Err(MotorError::TooLarge(format!(
            "{per_wheel} kg per wheel{moved} is above the largest {phases}-phase {brand} motor class ({largest} kg); more wheels may help"
        )));
    };
    let limit = tables
        .phase_limits
        .lookup(&keys([("phases", Value::Int(phases))]), 0)
        .map_err(internal)?;
    if let Some(max) = field(&limit, "max_kw")
        .and_then(|v| v.as_decimal())
        .and_then(|d| d.to_f64())
    {
        if kw > max {
            return Err(MotorError::NotAvailableForPhases(format!(
                "needs {kw} kW ({brand}) but {phases}-phase supply allows motors up to {max} kW"
            )));
        }
    }
    Ok(RequiredMotor {
        kw,
        size: size.to_text(),
        brand: brand.to_string(),
        phases,
        weight_per_wheel_kg: per_wheel,
        effective_motion: effective.to_string(),
        bumped_classes: bump,
    })
}

/// The motor a bell needs on a grid with `phases`, optionally of one `brand` (otherwise the
/// weakest motor of all brands that can drive it).
pub fn required_motor(
    bell: &BellInput,
    phases: Option<i64>,
    brand: Option<&str>,
    tables: &MotorTables,
) -> Result<RequiredMotor, MotorError> {
    let missing = |m: &str| MotorError::MissingData(m.to_string());
    let weight = match bell.weight_kg {
        None => return Err(missing("no weight recorded")),
        Some(w) if w <= 0.0 || !w.is_finite() => return Err(missing("the weight must be above 0")),
        Some(w) => w,
    };
    let motion = bell
        .motion
        .as_deref()
        .ok_or_else(|| missing("no motion recorded"))?;
    let phases = phases.ok_or_else(|| missing("the power grid has no known phases"))?;
    let wheels = bell.num_wheels.unwrap_or(1.0);
    if wheels < 1.0 || !wheels.is_finite() {
        return Err(missing("the number of wheels must be at least 1"));
    }
    let effective = tables
        .motion_rules
        .lookup(&keys([("motion", Value::Str(motion.into()))]), 0)
        .map_err(MotorError::MissingData)?;
    let effective = field(&effective, "effective")
        .map(|v| v.to_text())
        .ok_or_else(|| {
            MotorError::MissingData(format!("the motion {motion} is not in the motion table"))
        })?;
    let mut brands: Vec<&str> = tables
        .rows(phases, None, None)
        .map(|r| text(r.get("brand")))
        .collect();
    brands.sort_unstable();
    brands.dedup();
    if brands.is_empty() {
        return Err(MotorError::NotAvailableForPhases(format!(
            "there are no motors for {phases}-phase"
        )));
    }
    if let Some(b) = brand {
        if !brands.contains(&b) {
            return Err(MotorError::NotAvailableForPhases(format!(
                "there are no {b} motors for {phases}-phase"
            )));
        }
        brands = vec![b];
    }
    let per_wheel = weight / wheels;
    let mut best: Option<RequiredMotor> = None;
    let mut errors = Vec::new();
    for b in brands {
        match for_brand(tables, phases, b, motion, &effective, per_wheel) {
            Ok(m) if best.as_ref().is_none_or(|x| m.kw < x.kw) => best = Some(m),
            Ok(_) => {}
            Err(e) => errors.push(e),
        }
    }
    if let Some(m) = best {
        return Ok(m);
    }
    let first = errors
        .iter()
        .find(|e| matches!(e, MotorError::TooLarge(_)))
        .or(errors.first());
    Err(first
        .cloned()
        .unwrap_or_else(|| missing("no motor could be derived")))
}

fn bell_input(n: &BaselineNode) -> (BellInput, Option<String>) {
    let num = |k: &str| n.values.get(k).and_then(serde_json::Value::as_f64);
    let txt = |k: &str| {
        n.values
            .get(k)
            .and_then(serde_json::Value::as_str)
            .map(str::to_string)
    };
    (
        BellInput {
            weight_kg: num("weight_kg"),
            motion: txt("motion"),
            num_wheels: num("num_wheels"),
        },
        txt("motor_brand"),
    )
}

/// The active motor tables of a company, `None` when the model or its active revision is gone.
pub async fn load_tables(
    conn: &mut PgConnection,
    company_id: Uuid,
) -> AppResult<Option<Result<MotorTables, String>>> {
    let def: Option<serde_json::Value> = sqlx::query_scalar(
        "SELECT r.definition
         FROM configurator.models m
         JOIN configurator.model_revisions r ON r.model_id = m.id AND r.status = 'active'
         WHERE m.company_id = $1 AND m.code = $2",
    )
    .bind(company_id)
    .bind(MODEL_CODE)
    .fetch_optional(&mut *conn)
    .await
    .map_err(AppError::from)?;
    Ok(def.map(|d| MotorTables::from_json(&d)))
}

/// Plugs the tables into the product matching of the CRM.
pub struct ConfiguratorMotors;

impl BellMotorProvider for ConfiguratorMotors {
    fn derive<'a>(
        &'a self,
        conn: &'a mut PgConnection,
        company_id: Uuid,
        phases: Option<i64>,
        bells: &'a [BaselineNode],
    ) -> BoxFuture<'a, AppResult<Vec<Result<RequiredMotor, MotorError>>>> {
        Box::pin(async move {
            let tables = match load_tables(conn, company_id).await? {
                Some(Ok(t)) => t,
                other => {
                    let why = match other {
                        Some(Err(e)) => format!("the motor tables are invalid: {e}"),
                        _ => format!("no active configurator model {MODEL_CODE} with motor tables"),
                    };
                    return Ok(bells
                        .iter()
                        .map(|_| Err(MotorError::MissingData(why.clone())))
                        .collect());
                }
            };
            Ok(bells
                .iter()
                .map(|n| {
                    let (bell, brand) = bell_input(n);
                    required_motor(&bell, phases, brand.as_deref(), &tables)
                })
                .collect())
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The seed of the migration is the single source of the table rows.
    fn seed_json() -> serde_json::Value {
        let sql = include_str!("../../../migrations/20270213000001_bell_motor_tables.sql");
        let marker = "$bell_motors$";
        let start = sql.find(marker).unwrap() + marker.len();
        let end = start + sql[start..].find(marker).unwrap();
        serde_json::from_str(&sql[start..end]).unwrap()
    }

    fn seeded() -> MotorTables {
        MotorTables::from_json(&seed_json()).unwrap()
    }

    fn bell(weight: f64, motion: &str) -> BellInput {
        BellInput {
            weight_kg: Some(weight),
            motion: Some(motion.into()),
            num_wheels: None,
        }
    }

    fn kw(b: &BellInput, phases: i64, brand: &str) -> Result<f64, MotorError> {
        required_motor(b, Some(phases), Some(brand), &seeded()).map(|m| m.kw)
    }

    #[test]
    fn the_first_class_at_or_above_the_weight_wins_on_the_boundary() {
        // 3-phase MEZ falling: 450 -> 0.12, 700 -> 0.18, 1100 -> 0.25.
        for (w, expected) in [
            (1.0, 0.12),
            (450.0, 0.12),
            (450.1, 0.18),
            (700.0, 0.18),
            (700.5, 0.25),
            (5000.0, 1.1),
        ] {
            assert_eq!(kw(&bell(w, "falling"), 3, "mez_1000"), Ok(expected), "{w}");
        }
        let m = required_motor(
            &bell(450.0, "falling"),
            Some(3),
            Some("mez_1000"),
            &seeded(),
        )
        .unwrap();
        assert_eq!(
            (
                m.size.as_str(),
                m.effective_motion.as_str(),
                m.bumped_classes,
                m.brand.as_str()
            ),
            ("63", "falling", 0, "mez_1000")
        );
    }

    #[test]
    fn flying_uses_its_own_lighter_classes() {
        assert_eq!(kw(&bell(230.0, "flying"), 3, "mez_1000"), Ok(0.12));
        assert_eq!(kw(&bell(231.0, "flying"), 3, "mez_1000"), Ok(0.18));
        assert_eq!(kw(&bell(150.0, "flying"), 3, "adda_750"), Ok(0.12));
        // The other special motions map to falling or flying.
        assert_eq!(kw(&bell(450.0, "ambrosiano"), 3, "mez_1000"), Ok(0.12));
        assert_eq!(kw(&bell(230.0, "synchro_flying"), 3, "mez_1000"), Ok(0.12));
        assert_eq!(kw(&bell(450.0, "synchro_falling"), 3, "mez_1000"), Ok(0.12));
    }

    #[test]
    fn above_the_largest_class_is_too_large() {
        assert_eq!(kw(&bell(5000.0, "falling"), 3, "mez_1000"), Ok(1.1));
        let e = kw(&bell(5000.5, "falling"), 3, "mez_1000").unwrap_err();
        assert!(
            matches!(&e, MotorError::TooLarge(m) if m.contains("5000 kg") && m.contains("mez_1000")),
            "{e:?}"
        );
    }

    #[test]
    fn more_wheels_share_the_weight() {
        let mut b = bell(900.0, "falling");
        b.num_wheels = Some(2.0);
        assert_eq!(kw(&b, 3, "mez_1000"), Ok(0.12));
        assert!(matches!(
            kw(&bell(9000.0, "falling"), 3, "mez_1000"),
            Err(MotorError::TooLarge(_))
        ));
        // 9000 kg on two wheels is 4500 kg per wheel: the 1.1 kW class.
        b.weight_kg = Some(9000.0);
        assert_eq!(kw(&b, 3, "mez_1000"), Ok(1.1));
    }

    #[test]
    fn volteo_bumps_one_weight_class() {
        // 450 kg falling is class 0.12; volteo takes the next class.
        let m =
            required_motor(&bell(450.0, "volteo"), Some(3), Some("mez_1000"), &seeded()).unwrap();
        assert_eq!((m.kw, m.bumped_classes), (0.18, 1));
        // In the last class there is no next class: too large.
        assert!(matches!(
            kw(&bell(5000.0, "volteo"), 3, "mez_1000"),
            Err(MotorError::TooLarge(m)) if m.contains("volteo")
        ));
    }

    #[test]
    fn balanced_bumps_only_on_one_phase_mez() {
        assert_eq!(kw(&bell(100.0, "falling"), 1, "mez_1000"), Ok(0.12));
        assert_eq!(kw(&bell(100.0, "balanced"), 1, "mez_1000"), Ok(0.18));
        // Not on 3-phase MEZ, nor on another 1-phase brand.
        assert_eq!(kw(&bell(450.0, "balanced"), 3, "mez_1000"), Ok(0.12));
        assert_eq!(kw(&bell(66.0, "balanced"), 1, "adda_750"), Ok(0.12));
    }

    #[test]
    fn single_phase_above_055_kw_is_rejected() {
        // 1-phase MEZ falling: 1100 -> 0.55 is allowed, volteo moves it past the last class.
        assert_eq!(kw(&bell(1100.0, "falling"), 1, "mez_1000"), Ok(0.55));
        assert!(matches!(
            kw(&bell(1100.1, "falling"), 1, "mez_1000"),
            Err(MotorError::TooLarge(_))
        ));
        // The cap itself: lower it in the tables and a 0.55 kW motor is refused.
        let mut json = seed_json();
        json["tables"][2]["rows"][0]["max_kw"] = serde_json::json!(0.37);
        let tables = MotorTables::from_json(&json).unwrap();
        let e = required_motor(&bell(1100.0, "falling"), Some(1), Some("mez_1000"), &tables)
            .unwrap_err();
        assert!(
            matches!(&e, MotorError::NotAvailableForPhases(m) if m.contains("0.37 kW")),
            "{e:?}"
        );
        // The seed has no motor above 0.55 kW on 1 phase at all.
        let max = seeded()
            .rows(1, None, None)
            .filter_map(|r| r.get("kw").and_then(Value::as_decimal))
            .max()
            .unwrap();
        assert_eq!(max.to_string(), "0.55");
    }

    #[test]
    fn missing_values_are_missing_data() {
        let t = seeded();
        let ok = bell(450.0, "falling");
        let cases = [
            (
                BellInput {
                    weight_kg: None,
                    ..ok.clone()
                },
                Some(3),
            ),
            (
                BellInput {
                    motion: None,
                    ..ok.clone()
                },
                Some(3),
            ),
            (
                BellInput {
                    weight_kg: Some(0.0),
                    ..ok.clone()
                },
                Some(3),
            ),
            (
                BellInput {
                    num_wheels: Some(0.0),
                    ..ok.clone()
                },
                Some(3),
            ),
            (
                BellInput {
                    motion: Some("swinging".into()),
                    ..ok.clone()
                },
                Some(3),
            ),
            (ok.clone(), None),
        ];
        for (b, phases) in cases {
            let e = required_motor(&b, phases, None, &t).unwrap_err();
            assert!(
                matches!(e, MotorError::MissingData(_)),
                "{b:?} {phases:?} {e:?}"
            );
        }
    }

    #[test]
    fn phases_without_motors_and_unknown_brands_are_not_available() {
        let t = seeded();
        let b = bell(450.0, "falling");
        for (phases, brand) in [(2, None), (3, Some("de_coster_1000")), (1, Some("nope"))] {
            let e = required_motor(&b, Some(phases), brand, &t).unwrap_err();
            assert!(
                matches!(e, MotorError::NotAvailableForPhases(_)),
                "{phases} {brand:?} {e:?}"
            );
        }
    }

    #[test]
    fn without_a_brand_the_weakest_motor_of_any_brand_wins() {
        let t = seeded();
        // 450 kg falling, 3-phase: MEZ 0.12 (class to 450) and ADDA 0.25 (class 300..500 is 0.18).
        let m = required_motor(&bell(450.0, "falling"), Some(3), None, &t).unwrap();
        assert_eq!((m.kw, m.brand.as_str()), (0.12, "mez_1000"));
        // Too large for MEZ (>5000) but ADDA falling goes to 4500 only: still too large overall.
        assert!(matches!(
            required_motor(&bell(6000.0, "falling"), Some(3), None, &t),
            Err(MotorError::TooLarge(_))
        ));
        // Flying 5000 kg: MEZ tops out at 4400, ADDA reaches 6000 (2.2 kW).
        let m = required_motor(&bell(5000.0, "flying"), Some(3), None, &t).unwrap();
        assert_eq!((m.kw, m.brand.as_str()), (2.2, "adda_750"));
    }

    #[test]
    fn broken_tables_are_refused_with_a_reason() {
        let mut json = seed_json();
        json["tables"]
            .as_array_mut()
            .unwrap()
            .retain(|t| t["name"] != "phase_limits");
        assert!(MotorTables::from_json(&json)
            .unwrap_err()
            .contains("phase_limits"));
    }
}
