//! Findings, the serial unit of a repair and its warranty (ADR 0030, section 2.5).
//!
//! Three layers live on the repair row so the automatic result is never lost:
//!
//! * the lookup: the serial unit, its `warranty_until` and the result `warranty_auto`, compared
//!   with the date the product *arrived* (not today), written by the system only;
//! * the override: the workshop (`repairs.warranty_void`) may declare the warranty void for
//!   misuse, with who, when and why;
//! * `warranty`: the final status used everywhere. A void override wins, otherwise the automatic
//!   result; while the lookup is `unknown` staff may still set it by hand.

use axum::extract::{Path, State};
use axum::Json;
use chrono::{DateTime, NaiveDate, Utc};
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection};
use tradocraft_core::{audit, AppError, AppResult, AppState, CurrentUser, Permission};
use utoipa::ToSchema;
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::{add_event, ensure_can_work, load_detail, load_repair, ErrorBody, Event, RepairDetail};

// ---------------------------------------------------------------------------------------------
// Pure decisions
// ---------------------------------------------------------------------------------------------

/// The automatic result for a unit: `unknown` without a date, `in_warranty` when the warranty ran
/// at least until the arrival date (the last day counts), else `out_of_warranty`.
pub fn decide(warranty_until: Option<NaiveDate>, arrival: NaiveDate) -> &'static str {
    match warranty_until {
        None => "unknown",
        Some(until) if until >= arrival => "in_warranty",
        Some(_) => "out_of_warranty",
    }
}

/// What the search for a serial unit yields: exactly one match is accepted, several need a person.
#[derive(Debug, PartialEq, Eq)]
pub enum Pick {
    NoMatch,
    One(usize),
    Ambiguous,
}

pub fn pick(matches: usize) -> Pick {
    match matches {
        0 => Pick::NoMatch,
        1 => Pick::One(0),
        _ => Pick::Ambiguous,
    }
}

/// The final warranty status. `current` is what is stored now (a manual choice while the lookup
/// does not know); `previous_auto` is the lookup result before this run.
pub fn final_status<'a>(
    overridden: bool,
    auto: &'a str,
    previous_auto: &str,
    current: &'a str,
) -> &'a str {
    if overridden {
        "void"
    } else if auto != "unknown" {
        auto
    } else if previous_auto != "unknown" {
        // The lookup lost its basis (serial unit cleared or changed): back to undecided.
        "unknown"
    } else {
        current
    }
}

// ---------------------------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct SerialUnitRef {
    pub id: Uuid,
    pub product_id: Uuid,
    pub product_code: String,
    pub product_name: String,
    pub serial_number: String,
    pub customer_id: Option<Uuid>,
    pub warranty_until: Option<NaiveDate>,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct RepairWarranty {
    pub repair_id: Uuid,
    /// The final status: unknown | in_warranty | out_of_warranty | void
    pub warranty: String,
    /// The automatic result: unknown | in_warranty | out_of_warranty
    pub auto: String,
    /// The `warranty_until` the automatic result was based on.
    pub auto_until: Option<NaiveDate>,
    pub auto_at: Option<DateTime<Utc>>,
    /// The date the lookup compared with: when the product arrived, or today while it has not.
    pub compared_with: NaiveDate,
    /// False while the repair has not been received yet; the result is provisional then.
    pub arrived: bool,
    pub serial_unit: Option<SerialUnitRef>,
    /// Several serial units match the serial number: the intake person picks one.
    pub candidates: Vec<SerialUnitRef>,
    pub overridden: bool,
    pub override_by: Option<Uuid>,
    pub override_by_name: Option<String>,
    pub override_at: Option<DateTime<Utc>>,
    pub override_reason: String,
}

// ---------------------------------------------------------------------------------------------
// The lookup
// ---------------------------------------------------------------------------------------------

const UNIT_SELECT: &str =
    "SELECT s.id, s.product_id, p.code AS product_code, p.name AS product_name,
        s.serial_number, s.customer_id, s.warranty_until
     FROM engineering.serial_units s JOIN products.products p ON p.id = s.product_id";

async fn find_candidates(
    conn: &mut PgConnection,
    company_id: Uuid,
    serial: &str,
    product_id: Option<Uuid>,
    customer_id: Uuid,
) -> AppResult<Vec<SerialUnitRef>> {
    if serial.trim().is_empty() {
        return Ok(vec![]);
    }
    Ok(sqlx::query_as(sqlx::AssertSqlSafe(format!(
        "{UNIT_SELECT}
         WHERE s.company_id = $1 AND lower(btrim(s.serial_number)) = lower(btrim($2))
           AND ($3::uuid IS NULL OR s.product_id = $3)
           AND (s.customer_id IS NULL OR s.customer_id = $4)
         ORDER BY p.code, s.serial_number"
    )))
    .bind(company_id)
    .bind(serial)
    .bind(product_id)
    .bind(customer_id)
    .fetch_all(conn)
    .await?)
}

async fn load_unit(
    conn: &mut PgConnection,
    company_id: Uuid,
    id: Uuid,
) -> AppResult<SerialUnitRef> {
    sqlx::query_as(sqlx::AssertSqlSafe(format!(
        "{UNIT_SELECT} WHERE s.id = $1 AND s.company_id = $2"
    )))
    .bind(id)
    .bind(company_id)
    .fetch_optional(conn)
    .await?
    .ok_or(AppError::NotFound("serial unit"))
}

#[derive(FromRow)]
struct Basis {
    customer_id: Uuid,
    product_id: Option<Uuid>,
    serial_number: String,
    serial_unit_id: Option<Uuid>,
    received_at: Option<DateTime<Utc>>,
    warranty: String,
    warranty_auto: String,
    warranty_auto_until: Option<NaiveDate>,
    warranty_overridden: bool,
}

/// Runs the lookup for a repair and stores the result, in the caller's transaction. A change of
/// the automatic result is recorded as a `warranty_auto` event. `user` is None for system runs.
pub(crate) async fn refresh(
    conn: &mut PgConnection,
    company_id: Uuid,
    user: Option<&CurrentUser>,
    repair_id: Uuid,
) -> AppResult<()> {
    let b: Basis = sqlx::query_as(
        "SELECT customer_id, product_id, serial_number, serial_unit_id, received_at, warranty, warranty_auto,
                warranty_auto_until, warranty_overridden
         FROM repairs.repairs WHERE id = $1 AND company_id = $2 FOR UPDATE",
    )
    .bind(repair_id)
    .bind(company_id)
    .fetch_optional(&mut *conn)
    .await?
    .ok_or(AppError::NotFound("repair"))?;
    let unit = match b.serial_unit_id {
        Some(u) => Some(load_unit(conn, company_id, u).await?),
        None => {
            let mut found = find_candidates(
                conn,
                company_id,
                &b.serial_number,
                b.product_id,
                b.customer_id,
            )
            .await?;
            match pick(found.len()) {
                Pick::One(i) => Some(found.swap_remove(i)),
                _ => None,
            }
        }
    };
    let arrival = b
        .received_at
        .map(|t| t.date_naive())
        .unwrap_or_else(|| Utc::now().date_naive());
    let until = unit.as_ref().and_then(|u| u.warranty_until);
    let auto = decide(until, arrival);
    let warranty = final_status(b.warranty_overridden, auto, &b.warranty_auto, &b.warranty);
    sqlx::query(
        "UPDATE repairs.repairs SET serial_unit_id = $2, warranty_auto = $3, warranty_auto_until = $4,
                warranty_auto_at = now(), warranty = $5, updated_at = now()
         WHERE id = $1",
    )
    .bind(repair_id)
    .bind(unit.as_ref().map(|u| u.id))
    .bind(auto)
    .bind(until)
    .bind(warranty)
    .execute(&mut *conn)
    .await?;
    if auto != b.warranty_auto || until != b.warranty_auto_until {
        let note = match until {
            Some(d) => format!(
                "{} -> {auto} (warranty until {d}, compared with {arrival})",
                b.warranty_auto
            ),
            None => format!("{} -> {auto}", b.warranty_auto),
        };
        add_event(
            conn,
            repair_id,
            user.map(|u| u.user_id),
            user.map_or("system", |u| u.display_name.as_str()),
            Event {
                kind: "warranty_auto",
                from_status: None,
                to_status: None,
                from_department: None,
                to_department: None,
                note: &note,
            },
        )
        .await?;
    }
    Ok(())
}

async fn load_warranty(
    conn: &mut PgConnection,
    company_id: Uuid,
    repair_id: Uuid,
) -> AppResult<RepairWarranty> {
    #[derive(FromRow)]
    struct Row {
        customer_id: Uuid,
        product_id: Option<Uuid>,
        serial_number: String,
        serial_unit_id: Option<Uuid>,
        received_at: Option<DateTime<Utc>>,
        warranty: String,
        warranty_auto: String,
        warranty_auto_until: Option<NaiveDate>,
        warranty_auto_at: Option<DateTime<Utc>>,
        warranty_overridden: bool,
        warranty_override_by: Option<Uuid>,
        override_by_name: Option<String>,
        warranty_override_at: Option<DateTime<Utc>>,
        warranty_override_reason: String,
    }
    let r: Row = sqlx::query_as(
        "SELECT r.customer_id, r.product_id, r.serial_number, r.serial_unit_id, r.received_at, r.warranty,
                r.warranty_auto, r.warranty_auto_until, r.warranty_auto_at, r.warranty_overridden,
                r.warranty_override_by, u.display_name AS override_by_name, r.warranty_override_at,
                r.warranty_override_reason
         FROM repairs.repairs r LEFT JOIN core.users u ON u.id = r.warranty_override_by
         WHERE r.id = $1 AND r.company_id = $2",
    )
    .bind(repair_id)
    .bind(company_id)
    .fetch_optional(&mut *conn)
    .await?
    .ok_or(AppError::NotFound("repair"))?;
    let serial_unit = match r.serial_unit_id {
        Some(u) => Some(load_unit(conn, company_id, u).await?),
        None => None,
    };
    let candidates = if serial_unit.is_none() {
        let found = find_candidates(
            conn,
            company_id,
            &r.serial_number,
            r.product_id,
            r.customer_id,
        )
        .await?;
        if found.len() > 1 {
            found
        } else {
            vec![]
        }
    } else {
        vec![]
    };
    Ok(RepairWarranty {
        repair_id,
        warranty: r.warranty,
        auto: r.warranty_auto,
        auto_until: r.warranty_auto_until,
        auto_at: r.warranty_auto_at,
        compared_with: r
            .received_at
            .map(|t| t.date_naive())
            .unwrap_or_else(|| Utc::now().date_naive()),
        arrived: r.received_at.is_some(),
        serial_unit,
        candidates,
        overridden: r.warranty_overridden,
        override_by: r.warranty_override_by,
        override_by_name: r.override_by_name,
        override_at: r.warranty_override_at,
        override_reason: r.warranty_override_reason,
    })
}

// ---------------------------------------------------------------------------------------------
// Endpoints
// ---------------------------------------------------------------------------------------------

/// The warranty card: the automatic result, the serial unit it is based on, the override, and the
/// final status.
#[utoipa::path(get, path = "/repairs/{id}/warranty", tag = "repairs", operation_id = "get_repair_warranty",
    params(("id" = Uuid, Path)),
    responses((status = 200, body = RepairWarranty), (status = 404, body = ErrorBody)))]
async fn get_warranty(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<RepairWarranty>> {
    user.require(Permission::RepairsRead)?;
    let mut conn = state.db.acquire().await?;
    Ok(Json(load_warranty(&mut conn, user.company_id, id).await?))
}

/// Runs the warranty lookup again (after the serial unit's warranty date was filled in).
#[utoipa::path(post, path = "/repairs/{id}/warranty/recheck", tag = "repairs", operation_id = "recheck_repair_warranty",
    params(("id" = Uuid, Path)),
    responses((status = 200, body = RepairWarranty), (status = 403, body = ErrorBody), (status = 404, body = ErrorBody)))]
async fn recheck_warranty(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<RepairWarranty>> {
    let mut tx = state.db.begin().await?;
    load_repair(&mut tx, user.company_id, id).await?;
    ensure_can_work(&mut tx, &user, id).await?;
    refresh(&mut tx, user.company_id, Some(&user), id).await?;
    let w = load_warranty(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok(Json(w))
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct WarrantyOverrideInput {
    /// Why the warranty is void (misuse). Required.
    pub reason: String,
}

/// Declares the warranty void (misuse). The automatic result stays visible; who, when and why are
/// recorded. It cannot turn an out-of-warranty product into an in-warranty one.
#[utoipa::path(put, path = "/repairs/{id}/warranty/override", tag = "repairs", operation_id = "void_repair_warranty",
    params(("id" = Uuid, Path)), request_body = WarrantyOverrideInput,
    responses((status = 200, body = RepairDetail), (status = 403, body = ErrorBody), (status = 409, body = ErrorBody),
              (status = 422, body = ErrorBody)))]
async fn void_warranty(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<WarrantyOverrideInput>,
) -> AppResult<Json<RepairDetail>> {
    user.require(Permission::RepairsWarrantyVoid)?;
    let reason = input.reason.trim();
    if reason.is_empty() {
        return Err(AppError::Validation("say why the warranty is void".into()));
    }
    let mut tx = state.db.begin().await?;
    let current = load_repair(&mut tx, user.company_id, id).await?;
    ensure_can_work(&mut tx, &user, id).await?;
    if matches!(current.status.as_str(), "shipped" | "cancelled") {
        return Err(AppError::Conflict(format!(
            "the warranty of a repair that is {} can no longer change",
            current.status
        )));
    }
    let overridden: bool = sqlx::query_scalar(
        "SELECT warranty_overridden FROM repairs.repairs WHERE id = $1 FOR UPDATE",
    )
    .bind(id)
    .fetch_one(&mut *tx)
    .await?;
    if overridden {
        return Err(AppError::Conflict(
            "the warranty is already void; remove the override first".into(),
        ));
    }
    sqlx::query(
        "UPDATE repairs.repairs SET warranty = 'void', warranty_overridden = true, warranty_override_by = $2,
                warranty_override_at = now(), warranty_override_reason = $3, updated_at = now()
         WHERE id = $1",
    )
    .bind(id)
    .bind(user.user_id)
    .bind(reason)
    .execute(&mut *tx)
    .await?;
    add_event(
        &mut tx,
        id,
        Some(user.user_id),
        &user.display_name,
        Event {
            kind: "warranty_void",
            from_status: None,
            to_status: None,
            from_department: None,
            to_department: None,
            note: reason,
        },
    )
    .await?;
    audit::record(
        &mut tx,
        &user,
        "repair",
        id,
        "warranty_void",
        serde_json::json!({ "from": current.warranty, "reason": reason }),
    )
    .await?;
    let d = load_detail(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok(Json(d))
}

/// Removes the override: the warranty follows the automatic result again.
#[utoipa::path(delete, path = "/repairs/{id}/warranty/override", tag = "repairs",
    operation_id = "remove_repair_warranty_override",
    params(("id" = Uuid, Path)), request_body = WarrantyOverrideInput,
    responses((status = 200, body = RepairDetail), (status = 403, body = ErrorBody), (status = 409, body = ErrorBody),
              (status = 422, body = ErrorBody)))]
async fn remove_override(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<WarrantyOverrideInput>,
) -> AppResult<Json<RepairDetail>> {
    user.require(Permission::RepairsWarrantyVoid)?;
    let reason = input.reason.trim();
    if reason.is_empty() {
        return Err(AppError::Validation(
            "say why the override is removed".into(),
        ));
    }
    let mut tx = state.db.begin().await?;
    let current = load_repair(&mut tx, user.company_id, id).await?;
    ensure_can_work(&mut tx, &user, id).await?;
    if matches!(current.status.as_str(), "shipped" | "cancelled") {
        return Err(AppError::Conflict(format!(
            "the warranty of a repair that is {} can no longer change",
            current.status
        )));
    }
    let (overridden, auto): (bool, String) = sqlx::query_as(
        "SELECT warranty_overridden, warranty_auto FROM repairs.repairs WHERE id = $1 FOR UPDATE",
    )
    .bind(id)
    .fetch_one(&mut *tx)
    .await?;
    if !overridden {
        return Err(AppError::Conflict("the warranty is not void".into()));
    }
    // The override columns stay as the record of what was decided; the events keep both steps.
    sqlx::query(
        "UPDATE repairs.repairs SET warranty = warranty_auto, warranty_overridden = false, updated_at = now()
         WHERE id = $1",
    )
    .bind(id)
    .execute(&mut *tx)
    .await?;
    add_event(
        &mut tx,
        id,
        Some(user.user_id),
        &user.display_name,
        Event {
            kind: "warranty_void_removed",
            from_status: None,
            to_status: None,
            from_department: None,
            to_department: None,
            note: &format!("void -> {auto}: {reason}"),
        },
    )
    .await?;
    audit::record(
        &mut tx,
        &user,
        "repair",
        id,
        "warranty_void_removed",
        serde_json::json!({ "to": auto, "reason": reason }),
    )
    .await?;
    let d = load_detail(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok(Json(d))
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct FindingsInput {
    /// What was found when the parcel was looked at, and what is wrong.
    pub findings: String,
    /// The department's conclusion; leave out to keep it as it is.
    pub diagnosis: Option<String>,
}

/// Records the findings (and the diagnosis) of a repair.
#[utoipa::path(put, path = "/repairs/{id}/findings", tag = "repairs", operation_id = "set_repair_findings",
    params(("id" = Uuid, Path)), request_body = FindingsInput,
    responses((status = 200, body = RepairDetail), (status = 403, body = ErrorBody), (status = 404, body = ErrorBody)))]
async fn set_findings(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<FindingsInput>,
) -> AppResult<Json<RepairDetail>> {
    let mut tx = state.db.begin().await?;
    load_repair(&mut tx, user.company_id, id).await?;
    ensure_can_work(&mut tx, &user, id).await?;
    let findings = input.findings.trim();
    sqlx::query(
        "UPDATE repairs.repairs SET findings = $2, diagnosis = coalesce($3, diagnosis), updated_at = now()
         WHERE id = $1",
    )
    .bind(id)
    .bind(findings)
    .bind(input.diagnosis.as_deref().map(str::trim))
    .execute(&mut *tx)
    .await?;
    add_event(
        &mut tx,
        id,
        Some(user.user_id),
        &user.display_name,
        Event {
            kind: "findings",
            from_status: None,
            to_status: None,
            from_department: None,
            to_department: None,
            note: findings,
        },
    )
    .await?;
    let d = load_detail(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok(Json(d))
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct SerialUnitInput {
    /// The serial unit the repair is about.
    pub serial_unit_id: Option<Uuid>,
    /// True to unlink the serial unit (and the automatic warranty result with it).
    #[serde(default)]
    pub clear: bool,
}

/// Links the repair to a serial unit (or unlinks it) and reruns the warranty lookup. Fills the
/// product and serial number of the repair from the unit when they are empty.
#[utoipa::path(put, path = "/repairs/{id}/serial-unit", tag = "repairs", operation_id = "set_repair_serial_unit",
    params(("id" = Uuid, Path)), request_body = SerialUnitInput,
    responses((status = 200, body = RepairDetail), (status = 403, body = ErrorBody), (status = 404, body = ErrorBody),
              (status = 422, body = ErrorBody)))]
async fn set_serial_unit(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<SerialUnitInput>,
) -> AppResult<Json<RepairDetail>> {
    user.require(Permission::RepairsIntake)?;
    if input.serial_unit_id.is_some() == input.clear {
        return Err(AppError::Validation(
            "give either serial_unit_id or clear".into(),
        ));
    }
    let mut tx = state.db.begin().await?;
    let current = load_repair(&mut tx, user.company_id, id).await?;
    ensure_can_work(&mut tx, &user, id).await?;
    let note = match input.serial_unit_id {
        Some(uid) => {
            let unit = load_unit(&mut tx, user.company_id, uid).await?;
            if current.product_id.is_some_and(|p| p != unit.product_id) {
                return Err(AppError::Validation(
                    "the serial unit is of another product than the repair".into(),
                ));
            }
            sqlx::query(
                "UPDATE repairs.repairs SET serial_unit_id = $2, product_id = coalesce(product_id, $3),
                        serial_number = CASE WHEN btrim(serial_number) = '' THEN $4 ELSE serial_number END,
                        updated_at = now()
                 WHERE id = $1",
            )
            .bind(id)
            .bind(unit.id)
            .bind(unit.product_id)
            .bind(&unit.serial_number)
            .execute(&mut *tx)
            .await?;
            format!("linked to {} {}", unit.product_code, unit.serial_number)
        }
        None => {
            // No unit: the automatic result goes back to unknown; a recheck may find one again.
            sqlx::query("UPDATE repairs.repairs SET serial_unit_id = NULL, updated_at = now() WHERE id = $1")
                .bind(id)
                .execute(&mut *tx)
                .await?;
            "unlinked".to_string()
        }
    };
    add_event(
        &mut tx,
        id,
        Some(user.user_id),
        &user.display_name,
        Event {
            kind: "serial_unit",
            from_status: None,
            to_status: None,
            from_department: None,
            to_department: None,
            note: &note,
        },
    )
    .await?;
    if input.clear {
        // Do not search again right away: the person said there is no unit.
        sqlx::query(
            "UPDATE repairs.repairs SET warranty_auto = 'unknown', warranty_auto_until = NULL, warranty_auto_at = now(),
                    warranty = CASE WHEN warranty_overridden THEN warranty
                                    WHEN warranty_auto <> 'unknown' THEN 'unknown' ELSE warranty END
             WHERE id = $1",
        )
        .bind(id)
        .execute(&mut *tx)
        .await?;
    } else {
        refresh(&mut tx, user.company_id, Some(&user), id).await?;
    }
    let d = load_detail(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok(Json(d))
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(get_warranty))
        .routes(routes!(recheck_warranty))
        .routes(routes!(void_warranty, remove_override))
        .routes(routes!(set_findings))
        .routes(routes!(set_serial_unit))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn d(y: i32, m: u32, day: u32) -> NaiveDate {
        NaiveDate::from_ymd_opt(y, m, day).unwrap()
    }

    #[test]
    fn warranty_is_compared_with_the_arrival_date() {
        let arrival = d(2027, 3, 1);
        assert_eq!(decide(None, arrival), "unknown");
        assert_eq!(decide(Some(d(2027, 3, 1)), arrival), "in_warranty");
        assert_eq!(decide(Some(d(2027, 3, 2)), arrival), "in_warranty");
        assert_eq!(decide(Some(d(2027, 2, 28)), arrival), "out_of_warranty");
    }

    #[test]
    fn only_one_serial_match_is_accepted() {
        assert_eq!(pick(0), Pick::NoMatch);
        assert_eq!(pick(1), Pick::One(0));
        assert_eq!(pick(2), Pick::Ambiguous);
    }

    #[test]
    fn final_status_layers() {
        // A void override always wins.
        assert_eq!(
            final_status(true, "in_warranty", "in_warranty", "void"),
            "void"
        );
        assert_eq!(final_status(true, "unknown", "unknown", "void"), "void");
        // The automatic result decides when it knows.
        assert_eq!(
            final_status(false, "in_warranty", "unknown", "out_of_warranty"),
            "in_warranty"
        );
        assert_eq!(
            final_status(
                false,
                "out_of_warranty",
                "out_of_warranty",
                "out_of_warranty"
            ),
            "out_of_warranty"
        );
        // A manual choice stays while the lookup does not know.
        assert_eq!(
            final_status(false, "unknown", "unknown", "in_warranty"),
            "in_warranty"
        );
        // A lookup that loses its basis falls back to undecided.
        assert_eq!(
            final_status(false, "unknown", "in_warranty", "in_warranty"),
            "unknown"
        );
    }
}
