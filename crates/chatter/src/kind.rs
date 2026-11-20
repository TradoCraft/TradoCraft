//! The kinds of record that carry a chatter, and what each one needs.

use serde::{Deserialize, Serialize};
use sqlx::PgConnection;
use tradocraft_core::{AppError, AppResult, CurrentUser, Permission};
use utoipa::ToSchema;
use uuid::Uuid;

/// Mirrored by the `CHECK` on the `chatter` tables and by the app's registry.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum RecordKind {
    Customer,
    Quotation,
    Order,
    Opportunity,
}

impl RecordKind {
    pub const ALL: [RecordKind; 4] = [
        RecordKind::Customer,
        RecordKind::Quotation,
        RecordKind::Order,
        RecordKind::Opportunity,
    ];

    pub fn as_str(self) -> &'static str {
        match self {
            RecordKind::Customer => "customer",
            RecordKind::Quotation => "quotation",
            RecordKind::Order => "order",
            RecordKind::Opportunity => "opportunity",
        }
    }

    pub fn parse(s: &str) -> Option<RecordKind> {
        Self::ALL.into_iter().find(|k| k.as_str() == s)
    }

    pub fn read_permission(self) -> Permission {
        match self {
            RecordKind::Customer => Permission::CustomersRead,
            RecordKind::Quotation => Permission::QuotationsRead,
            RecordKind::Order => Permission::OrdersRead,
            RecordKind::Opportunity => Permission::OpportunitiesRead,
        }
    }

    pub fn write_permission(self) -> Permission {
        match self {
            RecordKind::Customer => Permission::CustomersWrite,
            RecordKind::Quotation => Permission::QuotationsWrite,
            RecordKind::Order => Permission::OrdersWrite,
            RecordKind::Opportunity => Permission::OpportunitiesWrite,
        }
    }

    /// The table that holds the records of this kind.
    pub(crate) fn table(self) -> &'static str {
        match self {
            RecordKind::Customer => "crm.customers",
            RecordKind::Quotation => "sales.quotations",
            RecordKind::Order => "sales.orders",
            RecordKind::Opportunity => "crm.opportunities",
        }
    }

    /// `SELECT 1` that finds the record. Customers are shared master data (ADR 0003) and have no
    /// company; the chatter rows about them still belong to one company.
    fn exists_sql(self) -> &'static str {
        match self {
            RecordKind::Customer => {
                "SELECT 1 FROM crm.customers WHERE id = $1 AND $2::uuid IS NOT NULL"
            }
            RecordKind::Quotation => {
                "SELECT 1 FROM sales.quotations WHERE id = $1 AND company_id = $2"
            }
            RecordKind::Order => "SELECT 1 FROM sales.orders WHERE id = $1 AND company_id = $2",
            RecordKind::Opportunity => {
                "SELECT 1 FROM crm.opportunities WHERE id = $1 AND company_id = $2"
            }
        }
    }

    fn label_sql(self) -> &'static str {
        match self {
            RecordKind::Customer => "SELECT name FROM crm.customers WHERE id = $1 AND $2::uuid IS NOT NULL",
            RecordKind::Quotation => "SELECT number FROM sales.quotations WHERE id = $1 AND company_id = $2",
            RecordKind::Order => "SELECT number FROM sales.orders WHERE id = $1 AND company_id = $2",
            RecordKind::Opportunity => {
                "SELECT number || ' ' || title FROM crm.opportunities WHERE id = $1 AND company_id = $2"
            }
        }
    }

    /// 404 unless the record exists in the caller's company.
    pub async fn ensure_visible(
        self,
        conn: &mut PgConnection,
        user: &CurrentUser,
        id: Uuid,
    ) -> AppResult<()> {
        let found: Option<i32> = sqlx::query_scalar(self.exists_sql())
            .bind(id)
            .bind(user.company_id)
            .fetch_optional(&mut *conn)
            .await?;
        found.map(|_| ()).ok_or(AppError::NotFound("record"))
    }

    pub async fn label(
        self,
        conn: &mut PgConnection,
        company_id: Uuid,
        id: Uuid,
    ) -> AppResult<Option<String>> {
        Ok(sqlx::query_scalar(self.label_sql())
            .bind(id)
            .bind(company_id)
            .fetch_optional(&mut *conn)
            .await?)
    }
}

/// Parses the `{kind}` path segment.
pub(crate) fn parse_kind(s: &str) -> AppResult<RecordKind> {
    RecordKind::parse(s)
        .ok_or_else(|| AppError::Validation(format!("unsupported record kind: {s}")))
}
