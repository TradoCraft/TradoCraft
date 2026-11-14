//! The `send_email` automation action (ADR 0063): placeholders, recipients and the loop guard.
//!
//! The mail is queued in `core.mail_outbox` in the caller's transaction, so the outbound policy of
//! the environment (ADR 0043, 0048) applies where the outbox is emptied.

use sqlx::PgConnection;
use tradocraft_core::{audit, mail, AppError, AppResult};
use uuid::Uuid;

use crate::automation::{Rule, RuleAction};

pub const RECIPIENTS: [&str; 4] = ["customer", "assignee", "team", "address"];
pub const PLACEHOLDERS: [&str; 4] = ["ticket_number", "subject", "customer", "agent"];
pub const DEFAULT_PERIOD_HOURS: i32 = 24;
pub const MAX_PERIOD_HOURS: i32 = 24 * 90;

/// A plausible e-mail address: one `@`, no whitespace, a dotted domain.
pub fn valid_address(e: &str) -> bool {
    let Some((local, domain)) = e.split_once('@') else {
        return false;
    };
    e.len() <= 254
        && !e.contains(char::is_whitespace)
        && !local.is_empty()
        && !domain.contains('@')
        && domain.contains('.')
        && domain.split('.').all(|label| !label.is_empty())
}

/// The values a template can use.
pub struct Vars<'a> {
    pub ticket_number: &'a str,
    pub subject: &'a str,
    pub customer: &'a str,
    pub agent: &'a str,
}

/// Replaces `{ticket_number}`, `{subject}`, `{customer}` and `{agent}`. Other text, including
/// braces that do not name a placeholder, is left as it is.
pub fn render(template: &str, v: &Vars) -> String {
    let mut out = String::with_capacity(template.len());
    let mut rest = template;
    while let Some(start) = rest.find('{') {
        out.push_str(&rest[..start]);
        let tail = &rest[start..];
        let value = [
            ("{ticket_number}", v.ticket_number),
            ("{subject}", v.subject),
            ("{customer}", v.customer),
            ("{agent}", v.agent),
        ]
        .into_iter()
        .find(|(p, _)| tail.starts_with(p));
        match value {
            Some((p, val)) => {
                out.push_str(val);
                rest = &tail[p.len()..];
            }
            None => {
                out.push('{');
                rest = &tail[1..];
            }
        }
    }
    out.push_str(rest);
    out
}

/// A subject is one line: line breaks (which could inject headers) become spaces.
pub fn one_line(s: &str) -> String {
    s.split_whitespace().collect::<Vec<_>>().join(" ")
}

/// Rejects `{word}` that is not a placeholder, so a typo is found when the rule is saved.
pub fn check_template(field: &str, text: &str) -> AppResult<()> {
    let mut rest = text;
    while let Some(start) = rest.find('{') {
        let after = &rest[start + 1..];
        if let Some(end) = after.find('}') {
            let name = &after[..end];
            let word = !name.is_empty() && name.chars().all(|c| c.is_ascii_lowercase() || c == '_');
            if word && !PLACEHOLDERS.contains(&name) {
                return Err(AppError::Validation(format!(
                    "{field}: {{{name}}} is not a placeholder (use {})",
                    PLACEHOLDERS.map(|p| format!("{{{p}}}")).join(", ")
                )));
            }
        }
        rest = after;
    }
    Ok(())
}

/// Validates a `send_email` action and normalises its fields.
pub async fn validate_action(
    conn: &mut PgConnection,
    company_id: Uuid,
    a: &mut RuleAction,
) -> AppResult<()> {
    let recipient = a.recipient.clone().unwrap_or_default();
    if !RECIPIENTS.contains(&recipient.as_str()) {
        return Err(AppError::Validation(format!(
            "send_email: recipient must be one of {}",
            RECIPIENTS.join(", ")
        )));
    }
    match recipient.as_str() {
        "team" => {
            let team = a
                .team_id
                .ok_or_else(|| AppError::Validation("send_email to a team needs team_id".into()))?;
            let ok: bool = sqlx::query_scalar(
                "SELECT EXISTS (SELECT 1 FROM helpdesk.teams WHERE id = $1 AND company_id = $2)",
            )
            .bind(team)
            .bind(company_id)
            .fetch_one(&mut *conn)
            .await?;
            if !ok {
                return Err(AppError::NotFound("team"));
            }
        }
        "address" => {
            let address = a.address.as_deref().unwrap_or("").trim().to_lowercase();
            if !valid_address(&address) {
                return Err(AppError::Validation(
                    "send_email: a valid e-mail address is required".into(),
                ));
            }
            a.address = Some(address);
        }
        _ => {}
    }
    let subject = one_line(a.subject.as_deref().unwrap_or(""));
    let body = a.body.as_deref().unwrap_or("").trim().to_string();
    if subject.is_empty() || subject.chars().count() > 200 {
        return Err(AppError::Validation(
            "send_email: a subject of at most 200 characters is required".into(),
        ));
    }
    if body.is_empty() || body.chars().count() > 5000 {
        return Err(AppError::Validation(
            "send_email: a body of at most 5000 characters is required".into(),
        ));
    }
    check_template("subject", &subject)?;
    check_template("body", &body)?;
    a.subject = Some(subject);
    a.body = Some(body);
    let period = a.period_hours.unwrap_or(DEFAULT_PERIOD_HOURS);
    if !(1..=MAX_PERIOD_HOURS).contains(&period) {
        return Err(AppError::Validation(format!(
            "send_email: period_hours must be between 1 and {MAX_PERIOD_HOURS}"
        )));
    }
    a.period_hours = Some(period);
    Ok(())
}

/// Claims the right to send for this rule, ticket and action: true when no mail was queued for it
/// within the period. One atomic statement, so concurrent events send once.
async fn claim(
    conn: &mut PgConnection,
    company_id: Uuid,
    rule_id: Uuid,
    ticket_id: Uuid,
    action_no: i32,
    period_hours: i32,
) -> AppResult<bool> {
    let claimed: Option<i32> = sqlx::query_scalar(
        "INSERT INTO helpdesk.automation_mail_log AS l (company_id, rule_id, ticket_id, action_no)
         VALUES ($1, $2, $3, $4)
         ON CONFLICT (rule_id, ticket_id, action_no) DO UPDATE SET sent_at = now()
             WHERE l.sent_at <= now() - make_interval(hours => $5)
         RETURNING 1",
    )
    .bind(company_id)
    .bind(rule_id)
    .bind(ticket_id)
    .bind(action_no)
    .bind(period_hours)
    .fetch_optional(conn)
    .await?;
    Ok(claimed.is_some())
}

/// Queues the mail of one `send_email` action for a ticket. Returns the number of mails queued
/// (0 when the loop guard held it back or nobody could be addressed).
pub async fn send(
    conn: &mut PgConnection,
    company_id: Uuid,
    ticket_id: Uuid,
    rule: &Rule,
    action_no: usize,
    a: &RuleAction,
) -> AppResult<usize> {
    #[derive(sqlx::FromRow)]
    struct T {
        number: String,
        subject: String,
        internal: bool,
        contact_name: String,
        contact_email: String,
        customer_name: Option<String>,
        agent_name: Option<String>,
        agent_email: Option<String>,
        agent_active: Option<bool>,
    }
    let t: T = sqlx::query_as(
        "SELECT t.number, t.subject, t.internal, t.contact_name, t.contact_email,
                c.name AS customer_name, u.display_name AS agent_name, u.email AS agent_email,
                (u.active AND EXISTS (SELECT 1 FROM core.user_companies uc
                                WHERE uc.user_id = u.id AND uc.company_id = $2 AND uc.active))
                AS agent_active
         FROM helpdesk.tickets t
         LEFT JOIN crm.customers c ON c.id = t.customer_id
         LEFT JOIN core.users u ON u.id = t.owner_user_id
         WHERE t.id = $1 AND t.company_id = $2",
    )
    .bind(ticket_id)
    .bind(company_id)
    .fetch_optional(&mut *conn)
    .await?
    .ok_or(AppError::NotFound("ticket"))?;
    let recipient = a.recipient.as_deref().unwrap_or_default();
    let to: Vec<String> = match recipient {
        // An internal ticket has no customer contact (ADR 0021).
        "customer" if !t.internal && valid_address(t.contact_email.trim()) => {
            vec![t.contact_email.trim().to_string()]
        }
        "assignee" if t.agent_active == Some(true) => t.agent_email.clone().into_iter().collect(),
        "team" => {
            sqlx::query_scalar(
                "SELECT u.email FROM helpdesk.team_members m
                 JOIN helpdesk.teams tm ON tm.id = m.team_id AND tm.company_id = $2
                 JOIN core.users u ON u.id = m.user_id AND u.active
                 JOIN core.user_companies uc ON uc.user_id = u.id AND uc.company_id = $2 AND uc.active
                 WHERE m.team_id = $1 ORDER BY u.email",
            )
            .bind(a.team_id)
            .bind(company_id)
            .fetch_all(&mut *conn)
            .await?
        }
        "address" => a.address.clone().into_iter().collect(),
        _ => Vec::new(),
    };
    if to.is_empty() {
        return Ok(0);
    }
    let period = a.period_hours.unwrap_or(DEFAULT_PERIOD_HOURS);
    if !claim(
        conn,
        company_id,
        rule.id,
        ticket_id,
        action_no as i32,
        period,
    )
    .await?
    {
        return Ok(0);
    }
    let customer = t
        .customer_name
        .filter(|n| !n.trim().is_empty())
        .unwrap_or(t.contact_name);
    let vars = Vars {
        ticket_number: &t.number,
        subject: &t.subject,
        customer: &customer,
        agent: t.agent_name.as_deref().unwrap_or(""),
    };
    let subject = one_line(&render(a.subject.as_deref().unwrap_or(""), &vars));
    let body = render(a.body.as_deref().unwrap_or(""), &vars);
    for address in &to {
        mail::enqueue(conn, company_id, address, &subject, &body).await?;
    }
    audit::record_system(
        conn,
        company_id,
        "ticket",
        ticket_id,
        "automation_mail_queued",
        serde_json::json!({
            "rule_id": rule.id, "rule_name": rule.name, "recipient": recipient,
            "mails": to.len(),
        }),
    )
    .await?;
    Ok(to.len())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn placeholders_are_replaced_and_other_braces_are_kept() {
        let v = Vars {
            ticket_number: "T-0001",
            subject: "Pump",
            customer: "Alpha",
            agent: "Sam",
        };
        assert_eq!(
            render("{ticket_number} {subject} {customer} {agent} {x} {}", &v),
            "T-0001 Pump Alpha Sam {x} {}"
        );
    }

    #[test]
    fn inserted_values_stay_literal() {
        let v = Vars {
            ticket_number: "{subject}",
            subject: "{customer}",
            customer: "{agent}",
            agent: "{ticket_number}",
        };
        assert_eq!(
            render("{ticket_number}|{subject}|{customer}|{agent}", &v),
            "{subject}|{customer}|{agent}|{ticket_number}"
        );
    }

    #[test]
    fn unknown_placeholders_are_rejected() {
        assert!(check_template("body", "Ticket {ticket_number}").is_ok());
        assert!(check_template("body", "{ticket_numbr}").is_err());
        assert!(check_template("body", "json {\"a\": 1} {}").is_ok());
    }

    #[test]
    fn subjects_are_one_line() {
        assert_eq!(one_line("a\r\nBcc: x\n b"), "a Bcc: x b");
    }

    #[test]
    fn addresses_are_checked() {
        assert!(valid_address("a@b.example"));
        assert!(!valid_address("a@b"));
        assert!(!valid_address("a b@c.example"));
    }
}
