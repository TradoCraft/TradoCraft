use sqlx::PgConnection;
use uuid::Uuid;

use crate::auth::CurrentUser;

/// Appends a business event to the audit trail, in the caller's transaction.
pub async fn record(
    conn: &mut PgConnection,
    user: &CurrentUser,
    entity: &str,
    entity_id: Uuid,
    action: &str,
    data: serde_json::Value,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        "INSERT INTO audit.events (company_id, user_id, entity, entity_id, action, data)
         VALUES ($1, $2, $3, $4, $5, $6)",
    )
    .bind(user.company_id)
    .bind(user.user_id)
    .bind(entity)
    .bind(entity_id)
    .bind(action)
    .bind(data)
    .execute(conn)
    .await?;
    Ok(())
}

/// Appends an event that has no staff user behind it (e.g. a customer acting in the portal).
/// Put who acted in `data`.
pub async fn record_system(
    conn: &mut PgConnection,
    company_id: Uuid,
    entity: &str,
    entity_id: Uuid,
    action: &str,
    data: serde_json::Value,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        "INSERT INTO audit.events (company_id, user_id, entity, entity_id, action, data)
         VALUES ($1, NULL, $2, $3, $4, $5)",
    )
    .bind(company_id)
    .bind(entity)
    .bind(entity_id)
    .bind(action)
    .bind(data)
    .execute(conn)
    .await?;
    Ok(())
}

/// What changed in a record, for the `data` of an "updated" event (ADR 0059): for every field that
/// differs, the value before and after. The audit viewer shows it, which is what turns "customer
/// updated" into "who changed which field from what to what".
///
/// ```ignore
/// let changes = Changes::new()
///     .field("name", &before.name, &after.name)
///     .field("city", &before.city, &after.city);
/// audit::record(conn, user, "customer", id, "updated", changes.into_data()).await?;
/// ```
///
/// Values are compared as JSON. Numbers that are equal but written differently (a decimal `5` and
/// `5.00`) would count as a change: normalise them before passing them in.
#[derive(Debug, Default)]
pub struct Changes(serde_json::Map<String, serde_json::Value>);

impl Changes {
    pub fn new() -> Self {
        Self::default()
    }

    /// Notes the field when `before` and `after` differ.
    pub fn field<T: serde::Serialize + ?Sized>(
        mut self,
        name: &str,
        before: &T,
        after: &T,
    ) -> Self {
        let before = serde_json::to_value(before).unwrap_or(serde_json::Value::Null);
        let after = serde_json::to_value(after).unwrap_or(serde_json::Value::Null);
        if before != after {
            self.0.insert(
                name.to_string(),
                serde_json::json!({ "from": before, "to": after }),
            );
        }
        self
    }

    /// True when no field changed.
    pub fn is_empty(&self) -> bool {
        self.0.is_empty()
    }

    /// The event data: `{"changes": {"field": {"from": .., "to": ..}}}`, or `{}` for no change.
    pub fn into_data(self) -> serde_json::Value {
        if self.0.is_empty() {
            serde_json::json!({})
        } else {
            serde_json::json!({ "changes": self.0 })
        }
    }

    /// Like [`Changes::into_data`] with further keys of the event next to the changes.
    pub fn into_data_with(self, extra: serde_json::Value) -> serde_json::Value {
        let mut data = match extra {
            serde_json::Value::Object(m) => m,
            _ => serde_json::Map::new(),
        };
        if !self.0.is_empty() {
            data.insert("changes".to_string(), serde_json::Value::Object(self.0));
        }
        serde_json::Value::Object(data)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_differing_fields_are_noted() {
        let c = Changes::new()
            .field("name", &"Acme", &"Acme NV")
            .field("city", &"Gent", &"Gent")
            .field("phone", &Some("1"), &None::<&str>)
            .field("active", &true, &false);
        assert!(!c.is_empty());
        assert_eq!(
            c.into_data(),
            serde_json::json!({ "changes": {
                "name": { "from": "Acme", "to": "Acme NV" },
                "phone": { "from": "1", "to": null },
                "active": { "from": true, "to": false },
            }})
        );
    }

    #[test]
    fn no_change_is_an_empty_event() {
        let c = Changes::new().field("name", &"x", &"x");
        assert!(c.is_empty());
        assert_eq!(c.into_data(), serde_json::json!({}));
    }

    #[test]
    fn extra_keys_stay_next_to_the_changes() {
        let data = Changes::new()
            .field("n", &1, &2)
            .into_data_with(serde_json::json!({ "code": "C1" }));
        assert_eq!(data["code"], "C1");
        assert_eq!(data["changes"]["n"]["to"], 2);
        let none = Changes::new().into_data_with(serde_json::json!({ "code": "C1" }));
        assert_eq!(none, serde_json::json!({ "code": "C1" }));
    }
}
