//! Approval limits on purchase orders (ADR 0062): the largest order a role may approve.

use std::collections::HashMap;

use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use sqlx::PgConnection;
use tradocraft_core::auth::{role_grants, ROLES};
use tradocraft_core::company::get_company;
use tradocraft_core::{audit, AppError, AppResult, CurrentUser, Permission};
use utoipa::ToSchema;
use uuid::Uuid;

use crate::orders::PurchaseOrderSummary;

/// The roles whose approvals can be limited: those that may approve orders, except `admin`, who is
/// never limited (so nobody can lock the company out of approving).
pub fn limitable_roles() -> Vec<&'static str> {
    ROLES
        .iter()
        .copied()
        .filter(|r| *r != "admin" && role_grants(r, Permission::PurchasingApprove))
        .collect()
}

/// The limit of one role; `None` means no limit.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct RoleLimit {
    pub role: String,
    #[schema(value_type = Option<String>)]
    pub max_amount: Option<Decimal>,
}

/// The approval limits of the company and the caller's own.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct ApprovalLimits {
    /// The limits are amounts of the order's net total in this currency.
    pub currency: String,
    /// Every role whose approvals can be limited, with its limit.
    pub roles: Vec<RoleLimit>,
    /// What the caller may approve at most; `None` when the caller has no limit.
    #[schema(value_type = Option<String>)]
    pub your_limit: Option<Decimal>,
}

/// A change to one role's limit.
#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct RoleLimitInput {
    pub role: String,
    /// The new limit (0 or more, at most 2 decimals); null removes it.
    #[schema(value_type = Option<String>)]
    pub max_amount: Option<Decimal>,
}

/// Payload to change limits; roles that are not listed keep theirs.
#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct UpdateApprovalLimitsInput {
    pub limits: Vec<RoleLimitInput>,
}

async fn stored(conn: &mut PgConnection, company_id: Uuid) -> AppResult<HashMap<String, Decimal>> {
    let rows: Vec<(String, Decimal)> = sqlx::query_as(
        "SELECT role, max_amount FROM purchasing.approval_limits WHERE company_id = $1",
    )
    .bind(company_id)
    .fetch_all(conn)
    .await?;
    Ok(rows.into_iter().collect())
}

/// What a user holding `roles` may approve at most; `None` is unlimited. Someone with several roles
/// gets the best of them: unlimited when any approving role has no limit, else the largest.
pub fn effective_limit(roles: &[String], limits: &HashMap<String, Decimal>) -> Option<Decimal> {
    let mut best = Decimal::ZERO;
    for role in roles {
        if !role_grants(role, Permission::PurchasingApprove) {
            continue;
        }
        if role == "admin" {
            return None;
        }
        // A role without a row is unlimited, which makes the whole answer "unlimited".
        best = best.max(*limits.get(role)?);
    }
    Some(best)
}

/// The limits of the company and the caller's.
pub async fn load(conn: &mut PgConnection, user: &CurrentUser) -> AppResult<ApprovalLimits> {
    let limits = stored(conn, user.company_id).await?;
    let company = get_company(&mut *conn, user.company_id).await?;
    Ok(ApprovalLimits {
        currency: company.currency,
        roles: limitable_roles()
            .into_iter()
            .map(|r| RoleLimit {
                role: r.to_string(),
                max_amount: limits.get(r).copied(),
            })
            .collect(),
        your_limit: effective_limit(&user.roles, &limits),
    })
}

/// Refuses (403) an approval above the approver's limit. The comparison is on the net total in the
/// company's currency; there is no conversion, so an order in another currency can only be approved
/// by someone without a limit.
pub async fn check(
    conn: &mut PgConnection,
    user: &CurrentUser,
    po: &PurchaseOrderSummary,
) -> AppResult<()> {
    let limits = stored(conn, user.company_id).await?;
    let Some(limit) = effective_limit(&user.roles, &limits) else {
        return Ok(());
    };
    let company = get_company(&mut *conn, user.company_id).await?;
    if po.currency != company.currency {
        return Err(AppError::Forbidden(format!(
            "order {} is in {}; approval limits are in {}, so only someone without a limit can approve it",
            po.number, po.currency, company.currency
        )));
    }
    if po.subtotal > limit {
        return Err(AppError::Forbidden(format!(
            "order {} totals {:.2} {} (excluding VAT), above your approval limit of {:.2} {}",
            po.number, po.subtotal, po.currency, limit, company.currency
        )));
    }
    Ok(())
}

/// Sets or removes the limits of the listed roles (audited).
pub async fn update(
    conn: &mut PgConnection,
    user: &CurrentUser,
    input: UpdateApprovalLimitsInput,
) -> AppResult<ApprovalLimits> {
    let allowed = limitable_roles();
    for l in &input.limits {
        if !allowed.contains(&l.role.as_str()) {
            return Err(AppError::Validation(format!(
                "role {} cannot be given an approval limit (limitable roles: {})",
                l.role,
                allowed.join(", ")
            )));
        }
        if let Some(m) = l.max_amount {
            if m < Decimal::ZERO || m.scale() > 2 {
                return Err(AppError::Validation(
                    "a limit must be 0 or more with at most 2 decimals".into(),
                ));
            }
        }
    }
    let before = stored(conn, user.company_id).await?;
    for l in &input.limits {
        match l.max_amount {
            Some(m) => {
                sqlx::query(
                    "INSERT INTO purchasing.approval_limits (company_id, role, max_amount, updated_by_user_id, updated_at)
                     VALUES ($1, $2, $3, $4, now())
                     ON CONFLICT (company_id, role) DO UPDATE
                     SET max_amount = $3, updated_by_user_id = $4, updated_at = now()",
                )
                .bind(user.company_id)
                .bind(&l.role)
                .bind(m)
                .bind(user.user_id)
                .execute(&mut *conn)
                .await?;
            }
            None => {
                sqlx::query(
                    "DELETE FROM purchasing.approval_limits WHERE company_id = $1 AND role = $2",
                )
                .bind(user.company_id)
                .bind(&l.role)
                .execute(&mut *conn)
                .await?;
            }
        }
    }
    let after = stored(conn, user.company_id).await?;
    let show = |m: &HashMap<String, Decimal>| {
        limitable_roles()
            .into_iter()
            .map(|r| (r.to_string(), m.get(r).map(|d| d.to_string())))
            .collect::<HashMap<_, _>>()
    };
    audit::record(
        conn,
        user,
        "purchasing_approval_limits",
        user.company_id,
        "updated",
        serde_json::json!({ "before": show(&before), "after": show(&after) }),
    )
    .await?;
    load(conn, user).await
}

#[cfg(test)]
mod tests {
    use super::*;

    fn roles(r: &[&str]) -> Vec<String> {
        r.iter().map(|s| s.to_string()).collect()
    }

    fn limits(l: &[(&str, i64)]) -> HashMap<String, Decimal> {
        l.iter()
            .map(|(r, v)| (r.to_string(), Decimal::from(*v)))
            .collect()
    }

    #[test]
    fn a_role_without_a_row_is_unlimited() {
        assert_eq!(effective_limit(&roles(&["purchaser"]), &limits(&[])), None);
    }

    #[test]
    fn a_limited_role_gets_its_limit() {
        assert_eq!(
            effective_limit(&roles(&["purchaser"]), &limits(&[("purchaser", 5000)])),
            Some(Decimal::from(5000))
        );
    }

    #[test]
    fn admin_is_never_limited() {
        assert_eq!(
            effective_limit(&roles(&["admin"]), &limits(&[("admin", 1)])),
            None
        );
        assert_eq!(
            effective_limit(
                &roles(&["purchaser", "admin"]),
                &limits(&[("purchaser", 1)])
            ),
            None
        );
    }

    #[test]
    fn roles_that_cannot_approve_do_not_count() {
        // A warehouse role has no say: only the purchaser's limit applies.
        assert_eq!(
            effective_limit(
                &roles(&["warehouse", "purchaser"]),
                &limits(&[("purchaser", 100)])
            ),
            Some(Decimal::from(100))
        );
    }

    #[test]
    fn nobody_who_cannot_approve_gets_a_free_pass() {
        assert_eq!(
            effective_limit(&roles(&["warehouse"]), &limits(&[])),
            Some(Decimal::ZERO)
        );
    }

    #[test]
    fn the_limitable_roles_are_the_approvers_but_admin() {
        assert_eq!(limitable_roles(), vec!["purchaser"]);
    }
}
