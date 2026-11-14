//! Automation rules: when a ticket is created, updated or answered by the customer, rules whose
//! conditions all match change the ticket (owner, team, priority, category, tag, internal).
//!
//! The decision is a pure function ([`evaluate`]) over a snapshot of the ticket ([`Facts`]);
//! [`run`] loads the facts, evaluates and applies the changes in the caller's transaction, with
//! one audit event per change. Rules do not send e-mail and run no scripts.
//!
//! Loop guard: the rules run once per event, in order, each at most once. The changes they make
//! are written directly and never raise a new event, so a rule can neither trigger itself nor
//! another rule.

use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::Json;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection};
use tradocraft_core::{audit, new_id, AppError, AppResult, AppState, CurrentUser, Permission};
use utoipa::ToSchema;
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::tickets::{CATEGORIES, PRIORITIES, STATUSES};

type ErrorBody = tradocraft_core::error::ErrorBody;

pub const TRIGGERS: [&str; 3] = ["created", "updated", "customer_replied"];
pub const CHANNELS: [&str; 5] = ["email", "portal", "phone", "manual", "internal"];
pub const ACTION_KINDS: [&str; 7] = [
    "set_owner",
    "set_team",
    "set_priority",
    "set_category",
    "add_tag",
    "set_internal",
    "send_email",
];

// ---------------------------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------------------------

/// What a ticket must look like for a rule to apply. Every given condition has to hold; a list
/// holds when the ticket has any one of its values. Empty conditions match every ticket.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
pub struct RuleConditions {
    #[serde(default)]
    pub priorities: Vec<String>,
    #[serde(default)]
    pub categories: Vec<String>,
    #[serde(default)]
    pub statuses: Vec<String>,
    pub customer_id: Option<Uuid>,
    /// The language of the customer (nl, fr, en, de, es).
    #[serde(default)]
    pub customer_languages: Vec<String>,
    /// email | portal | phone | manual | internal
    #[serde(default)]
    pub channels: Vec<String>,
    /// Case-insensitive part of the subject.
    pub subject_contains: Option<String>,
    /// The part of the contact's address after the `@`, case-insensitive.
    pub sender_domain: Option<String>,
    pub tag: Option<String>,
    pub team_id: Option<Uuid>,
    /// `empty` (nobody owns the ticket) or `set` (somebody does).
    pub owner: Option<String>,
}

/// One change a rule makes. `kind` decides which of the other fields is used:
/// `set_owner` (`user_id`), `set_team` (`team_id`), `set_priority` (`value`), `set_category`
/// (`value`), `add_tag` (`value`), `set_internal` (`flag`), `send_email` (`recipient`, `team_id` or
/// `address`, `subject`, `body`, `period_hours`; ADR 0063).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
pub struct RuleAction {
    pub kind: String,
    pub user_id: Option<Uuid>,
    pub team_id: Option<Uuid>,
    pub value: Option<String>,
    pub flag: Option<bool>,
    /// `send_email`: customer | assignee | team | address.
    #[serde(default)]
    pub recipient: Option<String>,
    /// `send_email` to `address`: the fixed recipient.
    #[serde(default)]
    pub address: Option<String>,
    /// `send_email`: one line; `{ticket_number}`, `{subject}`, `{customer}`, `{agent}` are replaced.
    #[serde(default)]
    pub subject: Option<String>,
    /// `send_email`: the text, with the same placeholders.
    #[serde(default)]
    pub body: Option<String>,
    /// `send_email`: at most one mail per ticket and rule in this many hours (default 24).
    #[serde(default)]
    pub period_hours: Option<i32>,
}

#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct Rule {
    pub id: Uuid,
    pub name: String,
    pub active: bool,
    /// Rules run in this order.
    pub position: i32,
    /// created | updated | customer_replied
    pub trigger: String,
    pub conditions: RuleConditions,
    pub actions: Vec<RuleAction>,
    /// Later rules are not looked at when this one matched.
    pub stop_on_match: bool,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct RuleInput {
    pub name: String,
    #[serde(default = "yes")]
    pub active: bool,
    pub trigger: String,
    #[serde(default)]
    pub conditions: RuleConditions,
    pub actions: Vec<RuleAction>,
    #[serde(default)]
    pub stop_on_match: bool,
}

fn yes() -> bool {
    true
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct RuleOrder {
    /// Every rule of the company, in the wanted order.
    pub ids: Vec<Uuid>,
}

/// A snapshot of the ticket as far as rules can see it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Facts {
    pub priority: String,
    pub category: String,
    pub status: String,
    pub customer_id: Option<Uuid>,
    pub customer_language: Option<String>,
    pub channel: String,
    pub subject: String,
    pub contact_email: String,
    pub tags: Vec<String>,
    pub team_id: Option<Uuid>,
    pub owner_user_id: Option<Uuid>,
    pub internal: bool,
}

/// A change a rule made (or, in a dry run, would make).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, ToSchema)]
pub struct RuleChange {
    pub kind: String,
    pub from: Option<String>,
    pub to: Option<String>,
}

/// What happened to one rule in one evaluation.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, ToSchema)]
pub struct RuleOutcome {
    pub rule_id: Uuid,
    pub rule_name: String,
    /// matched | no_match | inactive | other_trigger | after_stop
    pub result: String,
    /// The changes that actually change the ticket (actions that change nothing are left out).
    pub changes: Vec<RuleChange>,
}

// ---------------------------------------------------------------------------------------------
// The pure evaluator
// ---------------------------------------------------------------------------------------------

fn any_of(list: &[String], value: &str) -> bool {
    list.is_empty() || list.iter().any(|v| v == value)
}

/// True when every condition holds for the ticket.
pub fn matches(c: &RuleConditions, f: &Facts) -> bool {
    let domain = f
        .contact_email
        .rsplit_once('@')
        .map(|(_, d)| d.trim().to_lowercase())
        .unwrap_or_default();
    any_of(&c.priorities, &f.priority)
        && any_of(&c.categories, &f.category)
        && any_of(&c.statuses, &f.status)
        && c.customer_id.is_none_or(|id| f.customer_id == Some(id))
        && (c.customer_languages.is_empty()
            || f.customer_language
                .as_deref()
                .is_some_and(|l| c.customer_languages.iter().any(|x| x == l)))
        && any_of(&c.channels, &f.channel)
        && c.subject_contains
            .as_deref()
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .is_none_or(|s| f.subject.to_lowercase().contains(&s.to_lowercase()))
        && c.sender_domain
            .as_deref()
            .map(|d| d.trim().trim_start_matches('@').to_lowercase())
            .filter(|d| !d.is_empty())
            .is_none_or(|d| domain == d)
        && c.tag
            .as_deref()
            .map(str::trim)
            .filter(|t| !t.is_empty())
            .is_none_or(|t| f.tags.iter().any(|x| x.eq_ignore_ascii_case(t)))
        && c.team_id.is_none_or(|id| f.team_id == Some(id))
        && match c.owner.as_deref() {
            Some("empty") => f.owner_user_id.is_none(),
            Some("set") => f.owner_user_id.is_some(),
            _ => true,
        }
}

/// Applies one action to the facts. Returns the change, or `None` when the ticket already looks
/// like that (nothing to do, nothing to audit).
pub fn apply(a: &RuleAction, f: &mut Facts) -> Option<RuleChange> {
    let s = |v: &Option<String>| v.as_deref().unwrap_or_default().to_string();
    match a.kind.as_str() {
        "set_owner" if f.owner_user_id != a.user_id && a.user_id.is_some() => {
            let from = f.owner_user_id.map(|u| u.to_string());
            f.owner_user_id = a.user_id;
            Some(RuleChange {
                kind: a.kind.clone(),
                from,
                to: a.user_id.map(|u| u.to_string()),
            })
        }
        "set_team" if f.team_id != a.team_id && a.team_id.is_some() => {
            let from = f.team_id.map(|u| u.to_string());
            f.team_id = a.team_id;
            Some(RuleChange {
                kind: a.kind.clone(),
                from,
                to: a.team_id.map(|u| u.to_string()),
            })
        }
        "set_priority" if a.value.as_deref().is_some_and(|v| v != f.priority) => {
            let from = std::mem::replace(&mut f.priority, s(&a.value));
            Some(RuleChange {
                kind: a.kind.clone(),
                from: Some(from),
                to: a.value.clone(),
            })
        }
        "set_category" if a.value.as_deref().is_some_and(|v| v != f.category) => {
            let from = std::mem::replace(&mut f.category, s(&a.value));
            Some(RuleChange {
                kind: a.kind.clone(),
                from: Some(from),
                to: a.value.clone(),
            })
        }
        "add_tag" => {
            let tag = s(&a.value).to_lowercase();
            if tag.is_empty() || f.tags.contains(&tag) {
                return None;
            }
            f.tags.push(tag.clone());
            Some(RuleChange {
                kind: a.kind.clone(),
                from: None,
                to: Some(tag),
            })
        }
        "set_internal" if a.flag.is_some_and(|v| v != f.internal) => {
            let from = f.internal;
            f.internal = a.flag.unwrap_or_default();
            Some(RuleChange {
                kind: a.kind.clone(),
                from: Some(from.to_string()),
                to: Some(f.internal.to_string()),
            })
        }
        "send_email" => Some(RuleChange {
            kind: a.kind.clone(),
            from: None,
            to: a.recipient.clone(),
        }),
        _ => None,
    }
}

/// Runs the rules for `trigger` over the facts, in order of position. Each rule is looked at once;
/// the changes of a rule are visible to the rules after it. A rule with `stop_on_match` ends the
/// run. Returns one outcome per rule and the facts as they end up.
pub fn evaluate(rules: &[Rule], trigger: &str, facts: &Facts) -> (Vec<RuleOutcome>, Facts) {
    let mut facts = facts.clone();
    let mut ordered: Vec<&Rule> = rules.iter().collect();
    ordered.sort_by_key(|r| (r.position, r.id));
    let mut stopped = false;
    let mut out = Vec::new();
    for r in ordered {
        let result = if r.trigger != trigger {
            "other_trigger"
        } else if !r.active {
            "inactive"
        } else if stopped {
            "after_stop"
        } else if matches(&r.conditions, &facts) {
            "matched"
        } else {
            "no_match"
        };
        let mut changes = Vec::new();
        if result == "matched" {
            for a in &r.actions {
                changes.extend(apply(a, &mut facts));
            }
            stopped = r.stop_on_match;
        }
        out.push(RuleOutcome {
            rule_id: r.id,
            rule_name: r.name.clone(),
            result: result.into(),
            changes,
        });
    }
    (out, facts)
}

// ---------------------------------------------------------------------------------------------
// Database
// ---------------------------------------------------------------------------------------------

#[derive(FromRow)]
struct RuleRow {
    id: Uuid,
    name: String,
    active: bool,
    position: i32,
    trigger: String,
    conditions: serde_json::Value,
    actions: serde_json::Value,
    stop_on_match: bool,
    updated_at: DateTime<Utc>,
}

impl From<RuleRow> for Rule {
    fn from(r: RuleRow) -> Self {
        Rule {
            id: r.id,
            name: r.name,
            active: r.active,
            position: r.position,
            trigger: r.trigger,
            conditions: serde_json::from_value(r.conditions).unwrap_or_default(),
            actions: serde_json::from_value(r.actions).unwrap_or_default(),
            stop_on_match: r.stop_on_match,
            updated_at: r.updated_at,
        }
    }
}

const SELECT_RULE: &str =
    "SELECT id, name, active, position, trigger, conditions, actions, stop_on_match, updated_at
     FROM helpdesk.automation_rules";

async fn load_rules(conn: &mut PgConnection, company_id: Uuid) -> AppResult<Vec<Rule>> {
    let rows: Vec<RuleRow> = sqlx::query_as(&format!(
        "{SELECT_RULE} WHERE company_id = $1 ORDER BY position, id"
    ))
    .bind(company_id)
    .fetch_all(conn)
    .await?;
    Ok(rows.into_iter().map(Rule::from).collect())
}

async fn load_rule(conn: &mut PgConnection, company_id: Uuid, id: Uuid) -> AppResult<Rule> {
    let row: RuleRow = sqlx::query_as(&format!("{SELECT_RULE} WHERE id = $1 AND company_id = $2"))
        .bind(id)
        .bind(company_id)
        .fetch_optional(conn)
        .await?
        .ok_or(AppError::NotFound("rule"))?;
    Ok(row.into())
}

async fn load_facts(
    conn: &mut PgConnection,
    company_id: Uuid,
    ticket_id: Uuid,
) -> AppResult<Facts> {
    #[derive(FromRow)]
    struct Row {
        priority: String,
        category: String,
        status: String,
        customer_id: Option<Uuid>,
        customer_language: Option<String>,
        channel: String,
        subject: String,
        contact_email: String,
        team_id: Option<Uuid>,
        owner_user_id: Option<Uuid>,
        internal: bool,
    }
    let r: Row = sqlx::query_as(
        "SELECT t.priority, t.category, t.status, t.customer_id, c.language::text AS customer_language, t.channel,
                t.subject, t.contact_email, t.team_id, t.owner_user_id, t.internal
         FROM helpdesk.tickets t LEFT JOIN crm.customers c ON c.id = t.customer_id
         WHERE t.id = $1 AND t.company_id = $2",
    )
    .bind(ticket_id)
    .bind(company_id)
    .fetch_optional(&mut *conn)
    .await?
    .ok_or(AppError::NotFound("ticket"))?;
    let tags: Vec<String> = sqlx::query_scalar(
        "SELECT tag FROM helpdesk.ticket_tags WHERE ticket_id = $1 ORDER BY tag",
    )
    .bind(ticket_id)
    .fetch_all(conn)
    .await?;
    Ok(Facts {
        priority: r.priority,
        category: r.category,
        status: r.status,
        customer_id: r.customer_id,
        customer_language: r.customer_language,
        channel: r.channel,
        subject: r.subject,
        contact_email: r.contact_email,
        tags,
        team_id: r.team_id,
        owner_user_id: r.owner_user_id,
        internal: r.internal,
    })
}

/// Runs the active rules of the company for this event on the ticket, in the caller's
/// transaction. Every change is written and audited with the name of the rule. A new ticket is
/// also acknowledged to the customer when the SLA notice settings ask for it (ADR 0064), after the
/// rules, so the notice states the priority and team the rules left.
pub async fn run(
    conn: &mut PgConnection,
    company_id: Uuid,
    ticket_id: Uuid,
    trigger: &str,
) -> AppResult<Vec<RuleOutcome>> {
    let outcomes = run_rules(conn, company_id, ticket_id, trigger).await?;
    if trigger == "created" {
        crate::sla_notice::acknowledge(conn, company_id, ticket_id).await?;
    }
    Ok(outcomes)
}

async fn run_rules(
    conn: &mut PgConnection,
    company_id: Uuid,
    ticket_id: Uuid,
    trigger: &str,
) -> AppResult<Vec<RuleOutcome>> {
    let rules = load_rules(conn, company_id).await?;
    if !rules.iter().any(|r| r.active && r.trigger == trigger) {
        return Ok(Vec::new());
    }
    let facts = load_facts(conn, company_id, ticket_id).await?;
    let (outcomes, _) = evaluate(&rules, trigger, &facts);
    let mut sla_changed = false;
    for o in outcomes.iter().filter(|o| !o.changes.is_empty()) {
        let rule = rules.iter().find(|r| r.id == o.rule_id);
        for change in o.changes.iter().filter(|c| c.kind != "send_email") {
            let applied = apply_change(conn, company_id, ticket_id, change, rule).await?;
            if !applied {
                continue;
            }
            sla_changed |= matches!(
                change.kind.as_str(),
                "set_priority" | "set_internal" | "set_team"
            );
            audit::record_system(
                conn,
                company_id,
                "ticket",
                ticket_id,
                "automation_rule_applied",
                serde_json::json!({
                    "rule_id": o.rule_id, "rule_name": o.rule_name, "trigger": trigger,
                    "change": change.kind, "from": change.from, "to": change.to,
                }),
            )
            .await?;
        }
    }
    if sla_changed {
        crate::sla::sync(conn, ticket_id).await?;
    }
    // Mail last, so it describes the ticket as the rules left it. The loop guard keeps a rule from
    // mailing the same ticket again within its period (ADR 0063).
    for o in outcomes.iter().filter(|o| o.result == "matched") {
        let Some(rule) = rules.iter().find(|r| r.id == o.rule_id) else {
            continue;
        };
        for (no, a) in rule.actions.iter().enumerate() {
            if a.kind == "send_email" {
                crate::automail::send(conn, company_id, ticket_id, rule, no, a).await?;
            }
        }
    }
    Ok(outcomes)
}

/// Writes one change. Returns false when it could not be applied (for example the user is no
/// longer a member of the company); nothing is audited then.
async fn apply_change(
    conn: &mut PgConnection,
    company_id: Uuid,
    ticket_id: Uuid,
    change: &RuleChange,
    rule: Option<&Rule>,
) -> AppResult<bool> {
    let to = change.to.clone().unwrap_or_default();
    let done = match change.kind.as_str() {
        "set_owner" => {
            sqlx::query(
                "UPDATE helpdesk.tickets SET owner_user_id = $3 WHERE id = $1 AND company_id = $2
                 AND EXISTS (SELECT 1 FROM core.user_companies WHERE user_id = $3 AND company_id = $2)",
            )
            .bind(ticket_id)
            .bind(company_id)
            .bind(Uuid::parse_str(&to).ok())
            .execute(conn)
            .await?
            .rows_affected()
        }
        "set_team" => {
            sqlx::query(
                "UPDATE helpdesk.tickets SET team_id = $3 WHERE id = $1 AND company_id = $2
                 AND EXISTS (SELECT 1 FROM helpdesk.teams WHERE id = $3 AND company_id = $2 AND active)",
            )
            .bind(ticket_id)
            .bind(company_id)
            .bind(Uuid::parse_str(&to).ok())
            .execute(conn)
            .await?
            .rows_affected()
        }
        "set_priority" => {
            sqlx::query("UPDATE helpdesk.tickets SET priority = $3 WHERE id = $1 AND company_id = $2")
                .bind(ticket_id)
                .bind(company_id)
                .bind(&to)
                .execute(conn)
                .await?
                .rows_affected()
        }
        "set_category" => {
            sqlx::query("UPDATE helpdesk.tickets SET category = $3 WHERE id = $1 AND company_id = $2")
                .bind(ticket_id)
                .bind(company_id)
                .bind(&to)
                .execute(conn)
                .await?
                .rows_affected()
        }
        "set_internal" => {
            sqlx::query("UPDATE helpdesk.tickets SET internal = $3 WHERE id = $1 AND company_id = $2")
                .bind(ticket_id)
                .bind(company_id)
                .bind(to == "true")
                .execute(conn)
                .await?
                .rows_affected()
        }
        "add_tag" => {
            sqlx::query(
                "INSERT INTO helpdesk.ticket_tags (ticket_id, tag) SELECT id, $3 FROM helpdesk.tickets
                 WHERE id = $1 AND company_id = $2 ON CONFLICT DO NOTHING",
            )
            .bind(ticket_id)
            .bind(company_id)
            .bind(&to)
            .execute(conn)
            .await?
            .rows_affected()
        }
        _ => 0,
    };
    if done == 0 {
        tracing::warn!(rule = ?rule.map(|r| r.name.as_str()), kind = %change.kind, "automation change not applied");
    }
    Ok(done > 0)
}

// ---------------------------------------------------------------------------------------------
// Validation and endpoints
// ---------------------------------------------------------------------------------------------

fn check_list(field: &str, values: &[String], allowed: &[&str]) -> AppResult<()> {
    match values.iter().find(|v| !allowed.contains(&v.as_str())) {
        Some(bad) => Err(AppError::Validation(format!(
            "{field}: {bad:?} is not one of {}",
            allowed.join(", ")
        ))),
        None => Ok(()),
    }
}

async fn validate(
    conn: &mut PgConnection,
    company_id: Uuid,
    input: &mut RuleInput,
) -> AppResult<()> {
    if input.name.trim().is_empty() {
        return Err(AppError::Validation("a rule needs a name".into()));
    }
    input.name = input.name.trim().to_string();
    if !TRIGGERS.contains(&input.trigger.as_str()) {
        return Err(AppError::Validation(format!(
            "trigger must be one of {}",
            TRIGGERS.join(", ")
        )));
    }
    if input.actions.is_empty() {
        return Err(AppError::Validation(
            "a rule needs at least one action".into(),
        ));
    }
    let c = &input.conditions;
    check_list("priorities", &c.priorities, &PRIORITIES)?;
    check_list("categories", &c.categories, &CATEGORIES)?;
    check_list("statuses", &c.statuses, &STATUSES)?;
    check_list(
        "customer_languages",
        &c.customer_languages,
        &tradocraft_core::LANGUAGES,
    )?;
    check_list("channels", &c.channels, &CHANNELS)?;
    if c.owner
        .as_deref()
        .is_some_and(|o| !matches!(o, "empty" | "set"))
    {
        return Err(AppError::Validation("owner must be empty or set".into()));
    }
    if let Some(team) = c.team_id {
        team_exists(conn, company_id, team, false).await?;
    }
    for a in &mut input.actions {
        if !ACTION_KINDS.contains(&a.kind.as_str()) {
            return Err(AppError::Validation(format!(
                "action kind must be one of {}",
                ACTION_KINDS.join(", ")
            )));
        }
        match a.kind.as_str() {
            "set_owner" => {
                let user = a
                    .user_id
                    .ok_or_else(|| AppError::Validation("set_owner needs user_id".into()))?;
                let ok: bool = sqlx::query_scalar(
                    "SELECT EXISTS (SELECT 1 FROM core.user_companies WHERE user_id = $1 AND company_id = $2)",
                )
                .bind(user)
                .bind(company_id)
                .fetch_one(&mut *conn)
                .await?;
                if !ok {
                    return Err(AppError::Validation(
                        "the owner is not a member of this company".into(),
                    ));
                }
            }
            "set_team" => {
                let team = a
                    .team_id
                    .ok_or_else(|| AppError::Validation("set_team needs team_id".into()))?;
                team_exists(conn, company_id, team, true).await?;
            }
            "set_priority" => check_list(
                "set_priority",
                &[a.value.clone().unwrap_or_default()],
                &PRIORITIES,
            )?,
            "set_category" => check_list(
                "set_category",
                &[a.value.clone().unwrap_or_default()],
                &CATEGORIES,
            )?,
            "add_tag" => {
                a.value = Some(crate::extras::normalize_tag(
                    a.value.as_deref().unwrap_or(""),
                )?)
            }
            "send_email" => crate::automail::validate_action(conn, company_id, a).await?,
            _ => {
                if a.flag.is_none() {
                    return Err(AppError::Validation("set_internal needs flag".into()));
                }
            }
        }
    }
    Ok(())
}

async fn team_exists(
    conn: &mut PgConnection,
    company_id: Uuid,
    team: Uuid,
    must_be_active: bool,
) -> AppResult<()> {
    let ok: bool = sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM helpdesk.teams WHERE id = $1 AND company_id = $2 AND (active OR NOT $3))",
    )
    .bind(team)
    .bind(company_id)
    .bind(must_be_active)
    .fetch_one(conn)
    .await?;
    if ok {
        Ok(())
    } else {
        Err(AppError::Validation(
            "the team does not exist or is not active".into(),
        ))
    }
}

#[utoipa::path(get, path = "/helpdesk/automation/rules", tag = "helpdesk",
    responses((status = 200, body = Vec<Rule>), (status = 403, body = ErrorBody)))]
async fn list_rules(
    State(state): State<AppState>,
    user: CurrentUser,
) -> AppResult<Json<Vec<Rule>>> {
    user.require(Permission::HelpdeskAdmin)?;
    let mut conn = state.db.acquire().await?;
    Ok(Json(load_rules(&mut conn, user.company_id).await?))
}

#[utoipa::path(post, path = "/helpdesk/automation/rules", tag = "helpdesk", request_body = RuleInput,
    responses((status = 201, body = Rule), (status = 403, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn create_rule(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(mut input): Json<RuleInput>,
) -> AppResult<(StatusCode, Json<Rule>)> {
    user.require(Permission::HelpdeskAdmin)?;
    let mut tx = state.db.begin().await?;
    validate(&mut tx, user.company_id, &mut input).await?;
    let id = new_id();
    sqlx::query(
        "INSERT INTO helpdesk.automation_rules (id, company_id, name, active, position, trigger, conditions, actions,
                                                stop_on_match, created_by)
         VALUES ($1, $2, $3, $4,
                 (SELECT coalesce(max(position), 0) + 1 FROM helpdesk.automation_rules WHERE company_id = $2),
                 $5, $6, $7, $8, $9)",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(&input.name)
    .bind(input.active)
    .bind(&input.trigger)
    .bind(serde_json::to_value(&input.conditions).unwrap_or_default())
    .bind(serde_json::to_value(&input.actions).unwrap_or_default())
    .bind(input.stop_on_match)
    .bind(user.user_id)
    .execute(&mut *tx)
    .await?;
    audit::record(
        &mut tx,
        &user,
        "automation_rule",
        id,
        "created",
        serde_json::json!({ "name": input.name, "trigger": input.trigger }),
    )
    .await?;
    let rule = load_rule(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(rule)))
}

#[utoipa::path(put, path = "/helpdesk/automation/rules/{id}", tag = "helpdesk", params(("id" = Uuid, Path)),
    request_body = RuleInput,
    responses((status = 200, body = Rule), (status = 404, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn update_rule(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(mut input): Json<RuleInput>,
) -> AppResult<Json<Rule>> {
    user.require(Permission::HelpdeskAdmin)?;
    let mut tx = state.db.begin().await?;
    load_rule(&mut tx, user.company_id, id).await?;
    validate(&mut tx, user.company_id, &mut input).await?;
    sqlx::query(
        "UPDATE helpdesk.automation_rules SET name = $3, active = $4, trigger = $5, conditions = $6, actions = $7,
                stop_on_match = $8, updated_at = now()
         WHERE id = $1 AND company_id = $2",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(&input.name)
    .bind(input.active)
    .bind(&input.trigger)
    .bind(serde_json::to_value(&input.conditions).unwrap_or_default())
    .bind(serde_json::to_value(&input.actions).unwrap_or_default())
    .bind(input.stop_on_match)
    .execute(&mut *tx)
    .await?;
    audit::record(
        &mut tx,
        &user,
        "automation_rule",
        id,
        "updated",
        serde_json::json!({ "name": input.name, "active": input.active }),
    )
    .await?;
    let rule = load_rule(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok(Json(rule))
}

#[utoipa::path(delete, path = "/helpdesk/automation/rules/{id}", tag = "helpdesk", params(("id" = Uuid, Path)),
    responses((status = 204), (status = 404, body = ErrorBody)))]
async fn delete_rule(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<StatusCode> {
    user.require(Permission::HelpdeskAdmin)?;
    let mut tx = state.db.begin().await?;
    let name: Option<String> = sqlx::query_scalar(
        "DELETE FROM helpdesk.automation_rules WHERE id = $1 AND company_id = $2 RETURNING name",
    )
    .bind(id)
    .bind(user.company_id)
    .fetch_optional(&mut *tx)
    .await?;
    let name = name.ok_or(AppError::NotFound("rule"))?;
    audit::record(
        &mut tx,
        &user,
        "automation_rule",
        id,
        "deleted",
        serde_json::json!({ "name": name }),
    )
    .await?;
    tx.commit().await?;
    Ok(StatusCode::NO_CONTENT)
}

/// Sets the order in which rules run. The list must contain every rule of the company once.
#[utoipa::path(put, path = "/helpdesk/automation/order", tag = "helpdesk", operation_id = "reorder_rules", request_body = RuleOrder,
    responses((status = 200, body = Vec<Rule>), (status = 422, body = ErrorBody)))]
async fn reorder(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<RuleOrder>,
) -> AppResult<Json<Vec<Rule>>> {
    user.require(Permission::HelpdeskAdmin)?;
    let mut tx = state.db.begin().await?;
    let mut existing: Vec<Uuid> = sqlx::query_scalar(
        "SELECT id FROM helpdesk.automation_rules WHERE company_id = $1 FOR UPDATE",
    )
    .bind(user.company_id)
    .fetch_all(&mut *tx)
    .await?;
    let mut wanted = input.ids.clone();
    existing.sort();
    wanted.sort();
    if existing != wanted {
        return Err(AppError::Validation(
            "the order must list every rule of the company exactly once".into(),
        ));
    }
    for (i, id) in input.ids.iter().enumerate() {
        sqlx::query(
            "UPDATE helpdesk.automation_rules SET position = $3 WHERE id = $1 AND company_id = $2",
        )
        .bind(id)
        .bind(user.company_id)
        .bind(i as i32 + 1)
        .execute(&mut *tx)
        .await?;
    }
    audit::record(
        &mut tx,
        &user,
        "helpdesk_settings",
        user.company_id,
        "automation_rules_reordered",
        serde_json::json!({ "ids": input.ids }),
    )
    .await?;
    let rules = load_rules(&mut tx, user.company_id).await?;
    tx.commit().await?;
    Ok(Json(rules))
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct DryRunInput {
    pub ticket_id: Uuid,
    /// created | updated | customer_replied
    pub trigger: String,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct DryRun {
    pub ticket_number: String,
    pub trigger: String,
    /// One entry per rule, in running order. Nothing was changed.
    pub rules: Vec<RuleOutcome>,
}

/// Shows which rules would match the ticket for an event and what they would change, without
/// changing anything.
#[utoipa::path(post, path = "/helpdesk/automation/dry-run", tag = "helpdesk", request_body = DryRunInput,
    responses((status = 200, body = DryRun), (status = 404, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn dry_run(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<DryRunInput>,
) -> AppResult<Json<DryRun>> {
    user.require(Permission::HelpdeskAdmin)?;
    if !TRIGGERS.contains(&input.trigger.as_str()) {
        return Err(AppError::Validation(format!(
            "trigger must be one of {}",
            TRIGGERS.join(", ")
        )));
    }
    let mut conn = state.db.acquire().await?;
    let number: String =
        sqlx::query_scalar("SELECT number FROM helpdesk.tickets WHERE id = $1 AND company_id = $2")
            .bind(input.ticket_id)
            .bind(user.company_id)
            .fetch_optional(&mut *conn)
            .await?
            .ok_or(AppError::NotFound("ticket"))?;
    let rules = load_rules(&mut conn, user.company_id).await?;
    let facts = load_facts(&mut conn, user.company_id, input.ticket_id).await?;
    let (outcomes, _) = evaluate(&rules, &input.trigger, &facts);
    Ok(Json(DryRun {
        ticket_number: number,
        trigger: input.trigger,
        rules: outcomes,
    }))
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(list_rules, create_rule))
        .routes(routes!(update_rule, delete_rule))
        .routes(routes!(reorder))
        .routes(routes!(dry_run))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn facts() -> Facts {
        Facts {
            priority: "normal".into(),
            category: "question".into(),
            status: "open".into(),
            customer_id: None,
            customer_language: Some("nl".into()),
            channel: "email".into(),
            subject: "Pump makes NOISE".into(),
            contact_email: "Jan@Alpha.Example".into(),
            tags: vec!["warranty".into()],
            team_id: None,
            owner_user_id: None,
            internal: false,
        }
    }

    fn act(kind: &str) -> RuleAction {
        RuleAction {
            kind: kind.into(),
            user_id: None,
            team_id: None,
            value: None,
            flag: None,
            recipient: None,
            address: None,
            subject: None,
            body: None,
            period_hours: None,
        }
    }

    fn rule(
        name: &str,
        position: i32,
        conditions: RuleConditions,
        actions: Vec<RuleAction>,
    ) -> Rule {
        Rule {
            id: Uuid::from_u128(position as u128),
            name: name.into(),
            active: true,
            position,
            trigger: "created".into(),
            conditions,
            actions,
            stop_on_match: false,
            updated_at: Utc::now(),
        }
    }

    fn priority(v: &str) -> RuleAction {
        RuleAction {
            value: Some(v.into()),
            ..act("set_priority")
        }
    }

    #[test]
    fn empty_conditions_match_everything() {
        assert!(matches(&RuleConditions::default(), &facts()));
    }

    #[test]
    fn every_given_condition_must_hold() {
        let f = facts();
        let ok = RuleConditions {
            priorities: vec!["normal".into(), "high".into()],
            categories: vec!["question".into()],
            statuses: vec!["open".into()],
            customer_languages: vec!["nl".into(), "fr".into()],
            channels: vec!["email".into()],
            subject_contains: Some("noise".into()),
            sender_domain: Some("@ALPHA.example".into()),
            tag: Some("Warranty".into()),
            owner: Some("empty".into()),
            ..Default::default()
        };
        assert!(matches(&ok, &f));
        for broken in [
            RuleConditions {
                priorities: vec!["low".into()],
                ..ok.clone()
            },
            RuleConditions {
                categories: vec!["lead".into()],
                ..ok.clone()
            },
            RuleConditions {
                statuses: vec!["closed".into()],
                ..ok.clone()
            },
            RuleConditions {
                customer_languages: vec!["de".into()],
                ..ok.clone()
            },
            RuleConditions {
                channels: vec!["portal".into()],
                ..ok.clone()
            },
            RuleConditions {
                subject_contains: Some("leak".into()),
                ..ok.clone()
            },
            RuleConditions {
                sender_domain: Some("beta.example".into()),
                ..ok.clone()
            },
            RuleConditions {
                tag: Some("urgent".into()),
                ..ok.clone()
            },
            RuleConditions {
                owner: Some("set".into()),
                ..ok.clone()
            },
            RuleConditions {
                team_id: Some(Uuid::from_u128(9)),
                ..ok.clone()
            },
            RuleConditions {
                customer_id: Some(Uuid::from_u128(9)),
                ..ok.clone()
            },
        ] {
            assert!(!matches(&broken, &f), "{broken:?}");
        }
    }

    #[test]
    fn a_customer_language_condition_needs_a_known_customer() {
        let mut f = facts();
        f.customer_language = None;
        let c = RuleConditions {
            customer_languages: vec!["nl".into()],
            ..Default::default()
        };
        assert!(!matches(&c, &f));
    }

    #[test]
    fn actions_that_change_nothing_are_not_changes() {
        let mut f = facts();
        assert_eq!(apply(&priority("normal"), &mut f), None);
        let c = apply(&priority("high"), &mut f).unwrap();
        assert_eq!(
            (c.from.as_deref(), c.to.as_deref()),
            (Some("normal"), Some("high"))
        );
        assert_eq!(f.priority, "high");
        let tag = RuleAction {
            value: Some("Warranty".into()),
            ..act("add_tag")
        };
        assert_eq!(apply(&tag, &mut f), None, "already tagged");
        let tag = RuleAction {
            value: Some("vip".into()),
            ..act("add_tag")
        };
        assert!(apply(&tag, &mut f).is_some());
        assert_eq!(f.tags, vec!["warranty", "vip"]);
        let internal = RuleAction {
            flag: Some(true),
            ..act("set_internal")
        };
        assert!(apply(&internal, &mut f).is_some());
        assert_eq!(apply(&internal, &mut f), None);
    }

    #[test]
    fn rules_run_in_order_and_see_the_changes_of_earlier_rules() {
        let team = Uuid::from_u128(77);
        let rules = vec![
            // Position 2 is listed first on purpose: order is by position.
            rule(
                "second",
                2,
                RuleConditions {
                    priorities: vec!["urgent".into()],
                    team_id: Some(team),
                    ..Default::default()
                },
                vec![RuleAction {
                    value: Some("escalated".into()),
                    ..act("add_tag")
                }],
            ),
            rule(
                "first",
                1,
                RuleConditions {
                    subject_contains: Some("noise".into()),
                    ..Default::default()
                },
                vec![
                    priority("urgent"),
                    RuleAction {
                        team_id: Some(team),
                        ..act("set_team")
                    },
                ],
            ),
        ];
        let (out, end) = evaluate(&rules, "created", &facts());
        assert_eq!(
            out.iter()
                .map(|o| (o.rule_name.as_str(), o.result.as_str()))
                .collect::<Vec<_>>(),
            vec![("first", "matched"), ("second", "matched")]
        );
        assert_eq!(end.priority, "urgent");
        assert_eq!(end.team_id, Some(team));
        assert!(end.tags.contains(&"escalated".to_string()));
    }

    #[test]
    fn all_matching_rules_apply_unless_one_stops_the_run() {
        let mut rules = vec![
            rule("a", 1, RuleConditions::default(), vec![priority("high")]),
            rule(
                "b",
                2,
                RuleConditions::default(),
                vec![RuleAction {
                    value: Some("x".into()),
                    ..act("add_tag")
                }],
            ),
            rule("c", 3, RuleConditions::default(), vec![priority("low")]),
        ];
        let (out, end) = evaluate(&rules, "created", &facts());
        assert!(out.iter().all(|o| o.result == "matched"));
        assert_eq!(end.priority, "low", "the last matching rule wins");
        rules[1].stop_on_match = true;
        let (out, end) = evaluate(&rules, "created", &facts());
        assert_eq!(out[2].result, "after_stop");
        assert!(out[2].changes.is_empty());
        assert_eq!(end.priority, "high");
    }

    #[test]
    fn inactive_rules_and_other_triggers_are_skipped() {
        let mut off = rule("off", 1, RuleConditions::default(), vec![priority("high")]);
        off.active = false;
        let mut other = rule(
            "other",
            2,
            RuleConditions::default(),
            vec![priority("high")],
        );
        other.trigger = "updated".into();
        let (out, end) = evaluate(&[off, other], "created", &facts());
        assert_eq!(out[0].result, "inactive");
        assert_eq!(out[1].result, "other_trigger");
        assert_eq!(end, facts());
    }

    #[test]
    fn a_rule_is_looked_at_once_so_it_cannot_loop() {
        // The rule's action makes its own condition true again; it still runs a single time.
        let r = rule(
            "flip",
            1,
            RuleConditions {
                priorities: vec!["normal".into()],
                ..Default::default()
            },
            vec![priority("high")],
        );
        let r2 = rule(
            "flip back",
            2,
            RuleConditions {
                priorities: vec!["high".into()],
                ..Default::default()
            },
            vec![priority("normal")],
        );
        let (out, end) = evaluate(&[r, r2], "created", &facts());
        assert_eq!(out.iter().filter(|o| o.result == "matched").count(), 2);
        assert_eq!(end.priority, "normal");
        assert_eq!(out[0].changes.len(), 1);
        assert_eq!(out[1].changes.len(), 1);
    }
}
