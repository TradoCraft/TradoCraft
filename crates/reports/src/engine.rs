//! Builds and runs the query for a [`Plan`].
//!
//! The SQL text comes from the catalog and from fixed fragments in this file; every value (the
//! company, filter values, limit, offset) is a bound parameter.

use serde::Serialize;
use sqlx::postgres::Postgres;
use sqlx::{PgConnection, QueryBuilder, Row};
use tradocraft_core::{AppError, AppResult};
use utoipa::ToSchema;
use uuid::Uuid;

use crate::catalog::{self, ReportFieldType};
use crate::definition::{Plan, ReportColumnKind, ReportDir, ReportLogic, ReportOp, Shape, Val};

/// What a query returns: the page of rows, the number of rows, or the overall totals.
#[derive(Debug, Clone, Copy)]
pub enum Mode {
    Rows {
        limit: i64,
        offset: i64,
    },
    /// Number of rows the report has (grouped and plain reports).
    Count,
    /// The summary columns over everything, ignoring the grouping.
    Totals,
}

/// Pushes `text` where each `{company}` is replaced by a bound company id and `{on}` by `on`.
fn push_template(q: &mut QueryBuilder<Postgres>, text: &str, company: Uuid, on: &str) {
    let mut rest = text;
    while let Some(i) = rest.find('{') {
        q.push(&rest[..i]);
        rest = &rest[i..];
        if let Some(r) = rest.strip_prefix("{company}") {
            q.push_bind(company);
            rest = r;
        } else if let Some(r) = rest.strip_prefix("{on}") {
            q.push(on);
            rest = r;
        } else {
            q.push("{");
            rest = &rest[1..];
        }
    }
    q.push(rest);
}

fn push_filter(q: &mut QueryBuilder<Postgres>, f: &crate::definition::BoundFilter) {
    if let (ReportOp::Eq | ReportOp::Ne, Val::Range(a, b)) = (&f.op, &f.value) {
        // A range of days; a NULL date is outside every range, so never "equal" and always
        // "not equal". Parenthesised because filters are joined with AND or OR.
        q.push("(");
        if f.op == ReportOp::Eq {
            q.push(&f.lhs).push(" >= ").push_bind(*a);
            q.push(" AND ").push(&f.lhs).push(" <= ").push_bind(*b);
        } else {
            q.push(&f.lhs)
                .push(" IS NULL OR ")
                .push(&f.lhs)
                .push(" < ")
                .push_bind(*a);
            q.push(" OR ").push(&f.lhs).push(" > ").push_bind(*b);
        }
        q.push(")");
        return;
    }
    q.push(&f.lhs);
    match (&f.op, &f.value) {
        (ReportOp::IsNull, _) => {
            q.push(" IS NULL");
        }
        (ReportOp::NotNull, _) => {
            q.push(" IS NOT NULL");
        }
        (ReportOp::Contains | ReportOp::StartsWith, Val::Text(t)) => {
            q.push(" ILIKE ").push_bind(t.clone());
        }
        (ReportOp::In, v) => {
            q.push(" = ANY(");
            match v {
                Val::Texts(x) => q.push_bind(x.clone()),
                Val::Nums(x) => q.push_bind(x.clone()),
                Val::Dates(x) => q.push_bind(x.clone()),
                _ => q.push("NULL"),
            };
            q.push(")");
        }
        (op, v) => {
            q.push(match op {
                ReportOp::Eq => " = ",
                ReportOp::Ne => " IS DISTINCT FROM ",
                ReportOp::Gt => " > ",
                ReportOp::Gte => " >= ",
                ReportOp::Lt => " < ",
                _ => " <= ",
            });
            match v {
                Val::Text(x) => q.push_bind(x.clone()),
                Val::Num(x) => q.push_bind(*x),
                Val::Date(x) => q.push_bind(*x),
                Val::Bool(x) => q.push_bind(*x),
                _ => q.push("NULL"),
            };
        }
    }
}

impl Plan {
    fn push_body(&self, q: &mut QueryBuilder<Postgres>, company: Uuid, grouped: bool) {
        q.push(" FROM ");
        push_template(q, catalog::base_from(self.base), company, "");
        for (obj, on) in &self.joins {
            push_template(q, catalog::join_from(obj), company, on);
        }
        q.push(" WHERE TRUE");
        if let Some(f) = catalog::base_filter(self.base) {
            q.push(" AND ");
            push_template(q, f, company, "");
        }
        if !self.filters.is_empty() {
            q.push(" AND (");
            for (i, f) in self.filters.iter().enumerate() {
                if i > 0 {
                    q.push(if self.logic == ReportLogic::And {
                        " AND "
                    } else {
                        " OR "
                    });
                }
                push_filter(q, f);
            }
            q.push(")");
        }
        if grouped && self.shape == Shape::Grouped {
            let groups: Vec<&str> = self
                .columns
                .iter()
                .filter(|c| c.kind == ReportColumnKind::Group)
                .map(|c| c.raw.as_str())
                .collect();
            q.push(" GROUP BY ").push(groups.join(", "));
        }
    }

    /// Builds the SQL for one mode; all values are bound parameters.
    pub fn build(&self, company: Uuid, mode: Mode) -> QueryBuilder<Postgres> {
        let mut q: QueryBuilder<Postgres> = QueryBuilder::new("");
        match mode {
            Mode::Count => {
                q.push("SELECT count(*) FROM (SELECT 1");
                self.push_body(&mut q, company, true);
                q.push(") t");
            }
            Mode::Totals => {
                let cols: Vec<String> = self
                    .columns
                    .iter()
                    .filter(|c| c.kind == ReportColumnKind::Summary)
                    .map(|c| format!("to_jsonb({})", c.raw))
                    .collect();
                q.push("SELECT ").push(cols.join(", "));
                self.push_body(&mut q, company, false);
            }
            Mode::Rows { limit, offset } => {
                let cols: Vec<String> = self
                    .columns
                    .iter()
                    .map(|c| format!("to_jsonb({})", c.raw))
                    .collect();
                q.push("SELECT ").push(cols.join(", "));
                self.push_body(&mut q, company, true);
                let mut order: Vec<String> = self
                    .sort
                    .iter()
                    .map(|(i, d)| {
                        format!(
                            "{} {} NULLS LAST",
                            self.columns[*i].raw,
                            if *d == ReportDir::Asc { "ASC" } else { "DESC" }
                        )
                    })
                    .collect();
                match self.shape {
                    Shape::Rows => {
                        // Base id first, then the joined objects' ids, so rows that share a
                        // base record keep one order across LIMIT/OFFSET pages.
                        order.push(format!("{}.id", self.base.alias));
                        order.extend(self.joins.iter().map(|(o, _)| format!("{}.id", o.alias)));
                    }
                    Shape::Grouped => order.extend(
                        self.columns
                            .iter()
                            .filter(|c| c.kind == ReportColumnKind::Group)
                            .map(|c| format!("{} NULLS LAST", c.raw)),
                    ),
                    Shape::Single => {}
                }
                if !order.is_empty() {
                    q.push(" ORDER BY ").push(order.join(", "));
                }
                q.push(" LIMIT ").push_bind(limit);
                q.push(" OFFSET ").push_bind(offset);
            }
        }
        q
    }
}

/// A column of a run result.
#[derive(Debug, Serialize, ToSchema)]
pub struct ReportRunColumn {
    /// Key to use in `sort` and `chart`.
    pub key: String,
    pub label: String,
    #[serde(rename = "type")]
    pub ty: ReportFieldType,
    pub kind: ReportColumnKind,
}

/// The result of running a report.
#[derive(Debug, Serialize, ToSchema)]
pub struct ReportRunResult {
    pub columns: Vec<ReportRunColumn>,
    /// One array per row, aligned with `columns`. Numbers are JSON numbers, dates `YYYY-MM-DD`
    /// or ISO 8601 date-times, missing values null.
    pub rows: Vec<Vec<serde_json::Value>>,
    /// Number of rows the report has, before paging.
    pub total: i64,
    /// For grouped reports: the summaries over everything, aligned with `columns`
    /// (null for grouping columns).
    pub totals: Option<Vec<serde_json::Value>>,
    pub chart: Option<crate::definition::ReportChart>,
    /// The date (`YYYY-MM-DD`) relative dates were resolved against. Send it back as `as_of`
    /// when fetching further pages so every page comes from the same range, even across midnight.
    pub as_of: chrono::NaiveDate,
}

fn json_row(row: &sqlx::postgres::PgRow, n: usize) -> Result<Vec<serde_json::Value>, sqlx::Error> {
    (0..n)
        .map(|i| {
            Ok(row
                .try_get::<Option<serde_json::Value>, _>(i)?
                .unwrap_or(serde_json::Value::Null))
        })
        .collect()
}

/// Runs a planned report for a company: one page of rows, the row count and (for grouped reports) the totals.
pub async fn run(
    conn: &mut PgConnection,
    company: Uuid,
    plan: &Plan,
    limit: i64,
    offset: i64,
) -> AppResult<ReportRunResult> {
    let n = plan.columns.len();
    let rows = plan
        .build(company, Mode::Rows { limit, offset })
        .build()
        .fetch_all(&mut *conn)
        .await?;
    let rows = rows
        .iter()
        .map(|r| json_row(r, n))
        .collect::<Result<Vec<_>, _>>()?;

    let total = match plan.shape {
        Shape::Single => 1,
        _ => {
            let row = plan
                .build(company, Mode::Count)
                .build()
                .fetch_one(&mut *conn)
                .await?;
            row.try_get::<i64, _>(0)?
        }
    };

    let totals = if plan.shape == Shape::Grouped {
        let summaries = plan
            .columns
            .iter()
            .filter(|c| c.kind == ReportColumnKind::Summary)
            .count();
        let row = plan
            .build(company, Mode::Totals)
            .build()
            .fetch_one(&mut *conn)
            .await?;
        let values = json_row(&row, summaries)?;
        let mut it = values.into_iter();
        Some(
            plan.columns
                .iter()
                .map(|c| {
                    if c.kind == ReportColumnKind::Summary {
                        it.next().unwrap_or(serde_json::Value::Null)
                    } else {
                        serde_json::Value::Null
                    }
                })
                .collect(),
        )
    } else {
        None
    };

    Ok(ReportRunResult {
        columns: plan
            .columns
            .iter()
            .map(|c| ReportRunColumn {
                key: c.key.clone(),
                label: c.label.clone(),
                ty: c.ty,
                kind: c.kind,
            })
            .collect(),
        rows,
        total,
        totals,
        chart: plan.chart.clone(),
        as_of: plan.as_of,
    })
}

/// Longest page a client may ask for through the JSON endpoints.
pub const MAX_PAGE: i64 = 500;

/// Rows for an export: everything, or an error when it is more than the export limit.
pub async fn run_all(
    conn: &mut PgConnection,
    company: Uuid,
    plan: &Plan,
) -> AppResult<ReportRunResult> {
    let max = tradocraft_core::csv_io::MAX_ROWS as i64;
    let result = run(conn, company, plan, max + 1, 0).await?;
    if result.rows.len() as i64 > max {
        return Err(AppError::Validation(format!(
            "the report has more than {max} rows; add filters or group it"
        )));
    }
    Ok(result)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::definition::{plan, ReportDefinition};
    use serde_json::json;

    fn sql(def: serde_json::Value, mode: Mode) -> String {
        let d: ReportDefinition = serde_json::from_value(def).unwrap();
        let p = plan(&d, chrono::NaiveDate::from_ymd_opt(2026, 11, 11).unwrap()).unwrap();
        p.build(Uuid::nil(), mode).sql().as_str().to_string()
    }

    const ROWS: Mode = Mode::Rows {
        limit: 50,
        offset: 0,
    };

    #[test]
    fn plain_report_is_company_scoped_and_ordered_by_id() {
        let s = sql(
            json!({"object": "quotation",
                   "columns": [{"field": "quotation.number"}, {"field": "quotation.total"}]}),
            ROWS,
        );
        assert_eq!(
            s,
            "SELECT to_jsonb(q.number), to_jsonb(q.total) FROM sales.quotations q \
             WHERE TRUE AND q.company_id = $1 ORDER BY q.id LIMIT $2 OFFSET $3"
        );
    }

    #[test]
    fn customers_get_their_terms_of_the_company_and_no_company_filter() {
        let s = sql(
            json!({"object": "customer",
                   "columns": [{"field": "customer.name"}, {"field": "customer.discount_percent"}]}),
            ROWS,
        );
        assert!(s.contains(
            "FROM crm.customers c LEFT JOIN crm.customer_terms ct ON ct.customer_id = c.id AND ct.company_id = $1 WHERE TRUE ORDER BY c.id"
        ));
    }

    #[test]
    fn relative_ranges_are_bound_and_parenthesised() {
        let q = sql(
            json!({"object": "quotation", "columns": [{"field": "quotation.number"}],
                   "filters": [
                       {"field": "quotation.quote_date", "op": "eq", "value": {"relative": "last_month"}},
                       {"field": "quotation.quote_date", "op": "ne", "value": {"relative": "this_year"}}],
                   "filter_logic": "or"}),
            ROWS,
        );
        assert!(q.contains(" AND ("), "{q}");
        assert!(!q.contains("2026"), "{q}");
        assert!(!q.contains("last_month"), "{q}");
        assert_eq!(q.matches(" >= $").count(), 1, "{q}");
        assert!(q.contains(" IS NULL OR "), "{q}");
    }

    #[test]
    fn filters_become_bound_parameters_never_text() {
        let s = sql(
            json!({"object": "quotation",
                   "columns": [{"field": "quotation.number"}],
                   "filters": [
                       {"field": "quotation.status", "op": "eq", "value": "x'; DROP TABLE a; --"},
                       {"field": "quotation.total", "op": "gte", "value": 100},
                       {"field": "quotation.number", "op": "contains", "value": "50%"},
                       {"field": "quotation.status", "op": "in", "value": ["draft", "sent"]},
                       {"field": "quotation.created_at", "op": "lt", "value": "2027-01-31"},
                       {"field": "quotation.sent_at", "op": "is_null"},
                       {"field": "quotation.currency", "op": "ne", "value": "EUR"}
                   ],
                   "filter_logic": "or"}),
            ROWS,
        );
        assert!(!s.contains("DROP"));
        assert!(s.contains(
            "AND (q.status = $2 OR q.total >= $3 OR q.number ILIKE $4 OR q.status = ANY($5) \
             OR (q.created_at AT TIME ZONE 'UTC')::date < $6 \
             OR (q.sent_at AT TIME ZONE 'UTC')::date IS NULL OR q.currency::text IS DISTINCT FROM $7)"
        ));
    }

    #[test]
    fn grouped_report_groups_orders_and_counts() {
        let def = json!({"object": "quotation",
            "columns": [{"field": "quotation.total", "summary": "sum"},
                        {"field": "quotation.records", "summary": "count"}],
            "group_by": [{"field": "quotation.quote_date", "bucket": "month"},
                         {"field": "quotation.status"}],
            "sort": [{"column": "quotation.total:sum", "dir": "desc"}]});
        let s = sql(def.clone(), ROWS);
        assert_eq!(
            s,
            "SELECT to_jsonb(date_trunc('month', q.quote_date)::date), to_jsonb(q.status), \
             to_jsonb(sum(q.total)), to_jsonb(count(q.id)) FROM sales.quotations q \
             WHERE TRUE AND q.company_id = $1 \
             GROUP BY date_trunc('month', q.quote_date)::date, q.status \
             ORDER BY sum(q.total) DESC NULLS LAST, \
             date_trunc('month', q.quote_date)::date NULLS LAST, q.status NULLS LAST \
             LIMIT $2 OFFSET $3"
        );
        assert!(sql(def.clone(), Mode::Count)
            .starts_with("SELECT count(*) FROM (SELECT 1 FROM sales.quotations q"));
        assert!(sql(def.clone(), Mode::Count).contains("GROUP BY"));
        let t = sql(def, Mode::Totals);
        assert_eq!(
            t,
            "SELECT to_jsonb(sum(q.total)), to_jsonb(count(q.id)) FROM sales.quotations q \
             WHERE TRUE AND q.company_id = $1"
        );
    }

    #[test]
    fn joined_sales_objects_stay_inside_the_company() {
        let s = sql(
            json!({"object": "customer", "joins": ["quotation"],
                   "columns": [{"field": "customer.name"}, {"field": "quotation.total"}]}),
            ROWS,
        );
        assert!(s.contains(
            "LEFT JOIN sales.quotations q ON q.customer_id = c.id AND q.company_id = $2"
        ));
        let s = sql(
            json!({"object": "quotation", "joins": ["customer"],
                   "columns": [{"field": "customer.name"}]}),
            ROWS,
        );
        assert!(s.contains(
            "LEFT JOIN crm.customers c ON q.customer_id = c.id LEFT JOIN crm.customer_terms ct"
        ));
        // Binds are numbered in the order they appear in the text: the join's company first.
        assert!(s.contains("ct.company_id = $1"));
        assert!(s.contains("WHERE TRUE AND q.company_id = $2"));
    }
}
