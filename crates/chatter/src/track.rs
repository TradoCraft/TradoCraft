//! Curated change messages: the readable subset of an audit event.

use sqlx::PgConnection;
use tradocraft_core::{new_id, CurrentUser};
use uuid::Uuid;

use crate::RecordKind;

/// Writes one `system` message with the *tracked* fields among the changes of an audit event
/// (`audit::Changes::into_data()`, i.e. `{"changes": {"field": {"from", "to"}}}`). Call it next to
/// `audit::record`, in the same transaction. Writes nothing when no tracked field changed.
pub async fn track(
    conn: &mut PgConnection,
    user: &CurrentUser,
    kind: RecordKind,
    record_id: Uuid,
    audit_data: &serde_json::Value,
    tracked: &[&str],
) -> Result<(), sqlx::Error> {
    let Some(changes) = audit_data.get("changes").and_then(|c| c.as_object()) else {
        return Ok(());
    };
    let kept: Vec<serde_json::Value> = tracked
        .iter()
        .filter_map(|f| {
            changes.get(*f).map(|c| {
                serde_json::json!({
                    "field": f,
                    "from": c.get("from").cloned().unwrap_or(serde_json::Value::Null),
                    "to": c.get("to").cloned().unwrap_or(serde_json::Value::Null),
                })
            })
        })
        .collect();
    if kept.is_empty() {
        return Ok(());
    }
    sqlx::query(
        "INSERT INTO chatter.messages
             (id, company_id, record_kind, record_id, kind, author_user_id, changes)
         VALUES ($1, $2, $3, $4, 'system', $5, $6)",
    )
    .bind(new_id())
    .bind(user.company_id)
    .bind(kind.as_str())
    .bind(record_id)
    .bind(user.user_id)
    .bind(serde_json::Value::Array(kept))
    .execute(&mut *conn)
    .await?;
    Ok(())
}

/// Writes one `system` message for a single lifecycle step (a status change, an order sent). The
/// author is empty for a step taken by the system, such as a customer confirming in the portal.
/// `body` is an optional human text (a cancellation reason); it is shown as written.
#[allow(clippy::too_many_arguments)]
pub async fn log(
    conn: &mut PgConnection,
    company_id: Uuid,
    author: Option<Uuid>,
    kind: RecordKind,
    record_id: Uuid,
    field: &str,
    from: serde_json::Value,
    to: serde_json::Value,
    body: &str,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        "INSERT INTO chatter.messages
             (id, company_id, record_kind, record_id, kind, author_user_id, body, changes)
         VALUES ($1, $2, $3, $4, 'system', $5, $6, $7)",
    )
    .bind(new_id())
    .bind(company_id)
    .bind(kind.as_str())
    .bind(record_id)
    .bind(author)
    .bind(body.chars().take(10_000).collect::<String>())
    .bind(serde_json::json!([{ "field": field, "from": from, "to": to }]))
    .execute(&mut *conn)
    .await?;
    Ok(())
}
