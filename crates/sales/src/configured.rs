//! Configured quotations imported from an external configurator (ADR 0033).
//!
//! A configurator sends a tree of lines by product code together with its own configuration
//! payload. The import resolves the codes through the products module, prices the lines with the
//! normal draft pricing (including percent-of-parent lines) and stores the payload verbatim for
//! traceability. It is idempotent per company, `source` and `external_ref`: importing again updates
//! the latest revision while it is a draft, or creates the next revision when it was already sent
//! (or rejected), through the same code paths as `PUT /quotations/{id}` and
//! `POST /quotations/{id}/revise`.

use axum::extract::State;
use axum::http::StatusCode;
use axum::Json;
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use tradocraft_core::{audit, AppError, AppResult, AppState, CurrentUser, Permission};
use utoipa::ToSchema;
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::model::*;
use crate::routes::{create_draft, quotation_hints, revise, update_draft};
use crate::service;

type ErrorBody = tradocraft_core::error::ErrorBody;

/// Deepest accepted line tree (a top-level line is depth 1).
pub const MAX_DEPTH: usize = 8;
/// Most lines accepted in one import.
pub const MAX_LINES: usize = 500;
/// Longest accepted `source` or `external_ref`.
pub const MAX_REF_LEN: usize = 200;

/// One line of a configuration: a product by code, with its options or sub-lines as `children`.
#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct ConfiguredLineInput {
    /// Product code, matched exactly against active products.
    pub code: String,
    #[schema(value_type = String, example = "1")]
    pub quantity: Decimal,
    /// Heading on the document; children without one are shown under their parent's.
    pub section: Option<String>,
    /// Extra text printed below the line.
    pub comment: Option<String>,
    /// Overrides the product name on the document.
    pub description: Option<String>,
    /// Confirmed unit price for an indicative product (as on `QuotationLineInput`).
    #[schema(value_type = Option<String>, example = "6500")]
    pub unit_price: Option<Decimal>,
    /// Prices the line as this percentage of its parent line's unit price (only on children).
    #[schema(value_type = Option<String>, example = "20")]
    pub percent_of_parent: Option<Decimal>,
    /// Defaults to `parent_list_unit_price`.
    pub percent_base: Option<PercentBase>,
    #[serde(default)]
    #[schema(no_recursion)]
    pub children: Vec<ConfiguredLineInput>,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct ConfiguredQuotationInput {
    /// The system the configuration comes from, e.g. `configurator`.
    pub source: String,
    /// The configuration's identifier in that system. Importing the same source and reference
    /// again updates the quotation (see the endpoint).
    pub external_ref: String,
    pub customer_id: Uuid,
    /// The price zone the configurator expects. Prices always come from the customer's own zone;
    /// a different value only adds a `price_zone_mismatch` warning (422 when `strict`).
    pub price_zone_code: Option<String>,
    /// `installation` (default) or `stock`. On a re-import: unchanged when omitted.
    pub purpose: Option<String>,
    /// Defaults to the customer's country for an installation.
    pub delivery_country_code: Option<String>,
    pub power_grid_id: Option<Uuid>,
    /// Defaults to 30 days.
    pub valid_days: Option<i64>,
    #[serde(default)]
    pub notes: String,
    /// The configurator's own payload, stored verbatim on the quotation for traceability.
    #[serde(default)]
    #[schema(value_type = Object)]
    pub configuration: serde_json::Value,
    /// Refuse the import (422) when a product code is unknown or the price zone differs, instead
    /// of skipping the line with a warning.
    #[serde(default)]
    pub strict: bool,
    pub lines: Vec<ConfiguredLineInput>,
}

#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct ConfiguredImportResult {
    /// created (new quotation) | updated (the draft was replaced) | revised (a new revision of a
    /// sent or rejected quotation)
    pub action: String,
    /// The stored quotation. Its `warnings` start with the import's own (`unknown_product`,
    /// `price_zone_mismatch`), followed by the usual power grid and product relation warnings.
    pub quotation: Quotation,
}

/// A line tree flattened into quotation lines (parents before their children), with the warnings
/// for the codes that were skipped.
#[derive(Debug, Default)]
pub struct Flattened {
    pub lines: Vec<QuotationLineInput>,
    pub warnings: Vec<SalesWarning>,
}

fn count_lines(lines: &[ConfiguredLineInput], depth: usize) -> AppResult<usize> {
    // Leaves at the deepest allowed level have an empty child list one level further down.
    if depth > MAX_DEPTH && !lines.is_empty() {
        return Err(AppError::Validation(format!(
            "lines are nested deeper than {MAX_DEPTH} levels"
        )));
    }
    let mut n = 0;
    for l in lines {
        n += 1 + count_lines(&l.children, depth + 1)?;
    }
    Ok(n)
}

fn collect_codes(lines: &[ConfiguredLineInput], out: &mut Vec<String>) {
    for l in lines {
        let code = l.code.trim().to_string();
        if !out.contains(&code) {
            out.push(code);
        }
        collect_codes(&l.children, out);
    }
}

/// Depth-first flattening. `resolve` maps a code to a product id; a line with an unknown code is
/// skipped together with everything below it, with one warning. `path` is the line's place in the
/// tree ("2.1" = first child of the second top-level line).
pub fn flatten(lines: &[ConfiguredLineInput], resolve: &dyn Fn(&str) -> Option<Uuid>) -> Flattened {
    fn walk(
        lines: &[ConfiguredLineInput],
        parent: Option<i32>,
        prefix: &str,
        resolve: &dyn Fn(&str) -> Option<Uuid>,
        out: &mut Flattened,
    ) {
        for (i, l) in lines.iter().enumerate() {
            let path = if prefix.is_empty() {
                (i + 1).to_string()
            } else {
                format!("{prefix}.{}", i + 1)
            };
            let code = l.code.trim();
            let Some(product_id) = resolve(code) else {
                let skipped = count_lines(&l.children, 0).unwrap_or(0);
                out.warnings.push(SalesWarning {
                    kind: "unknown_product".into(),
                    product_code: code.to_string(),
                    message: if skipped == 0 {
                        format!("line {path}: no active product with code {code}; the line was skipped")
                    } else {
                        format!(
                            "line {path}: no active product with code {code}; the line and its {skipped} sub-line(s) were skipped"
                        )
                    },
                    details: serde_json::json!({ "path": path, "skipped_children": skipped }),
                });
                continue;
            };
            out.lines.push(QuotationLineInput {
                product_id,
                quantity: l.quantity,
                line_discount_percent: Decimal::ZERO,
                description: l.description.clone(),
                unit_price: l.unit_price,
                parent_position: parent,
                section: l.section.clone(),
                comment: l.comment.clone(),
                percent_of_parent: l.percent_of_parent,
                percent_base: l.percent_base,
                production_remark: String::new(),
                customer_remark: String::new(),
                customer_remark_language: None,
                favorite_item_id: None,
                add_options: false,
            });
            let me = out.lines.len() as i32;
            walk(&l.children, Some(me), &path, resolve, out);
        }
    }
    let mut out = Flattened::default();
    walk(lines, None, "", resolve, &mut out);
    out
}

fn check_ref(name: &str, v: &str) -> AppResult<String> {
    let v = v.trim();
    if v.is_empty() || v.chars().count() > MAX_REF_LEN {
        return Err(AppError::Validation(format!(
            "{name} is required (at most {MAX_REF_LEN} characters)"
        )));
    }
    Ok(v.to_string())
}

/// Imports a configured quotation, or re-imports it.
///
/// * First import of `(source, external_ref)`: a new draft quotation (201, `created`).
/// * Latest revision is a draft: it is replaced and repriced today (200, `updated`).
/// * Latest revision is sent or rejected: the next revision is created and filled (201,
///   `revised`), as `POST /quotations/{id}/revise` followed by an update.
/// * Latest revision is accepted: 409.
///
/// Unknown or inactive product codes are skipped with an `unknown_product` warning (with their
/// sub-lines), or refused with 422 when `strict`. Needs `quotations.import`.
#[utoipa::path(post, path = "/quotations/configured", tag = "sales", request_body = ConfiguredQuotationInput,
    responses((status = 201, body = ConfiguredImportResult), (status = 200, body = ConfiguredImportResult),
        (status = 403, body = ErrorBody), (status = 404, body = ErrorBody), (status = 409, body = ErrorBody),
        (status = 422, body = ErrorBody)))]
async fn import_configured(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<ConfiguredQuotationInput>,
) -> AppResult<(StatusCode, Json<ConfiguredImportResult>)> {
    user.require(Permission::QuotationsImport)?;
    let result = import(&state.db, &user, input).await?;
    let status = if result.action == "updated" {
        StatusCode::OK
    } else {
        StatusCode::CREATED
    };
    Ok((status, Json(result)))
}

/// Imports a configured quotation (the body of `POST /quotations/configured`, see there), for
/// callers inside the monolith such as the configurator module. The caller checks permissions;
/// this function runs its own transaction.
pub async fn import(
    db: &sqlx::PgPool,
    user: &CurrentUser,
    input: ConfiguredQuotationInput,
) -> AppResult<ConfiguredImportResult> {
    let source = check_ref("source", &input.source)?;
    let external_ref = check_ref("external_ref", &input.external_ref)?;
    if input.lines.is_empty() {
        return Err(AppError::Validation(
            "a configuration needs at least one line".into(),
        ));
    }
    let total = count_lines(&input.lines, 1)?;
    if total > MAX_LINES {
        return Err(AppError::Validation(format!(
            "a configuration has at most {MAX_LINES} lines"
        )));
    }

    let mut codes = Vec::new();
    collect_codes(&input.lines, &mut codes);
    let ids = tradocraft_products::active_ids_by_code(db, &codes).await?;
    let flat = flatten(&input.lines, &|c| ids.get(c).copied());
    let mut import_warnings = flat.warnings;

    // The customer must exist in this company (404 otherwise); its zone decides the prices.
    let customer =
        tradocraft_crm::get_customer_for_quoting(db, user.company_id, input.customer_id).await?;
    if let Some(zone) = input
        .price_zone_code
        .as_deref()
        .map(str::trim)
        .filter(|z| !z.is_empty())
    {
        if zone != customer.price_zone_code {
            import_warnings.push(SalesWarning {
                kind: "price_zone_mismatch".into(),
                product_code: String::new(),
                message: format!(
                    "the configuration was made for price zone {zone}, but the customer is priced in zone {}",
                    customer.price_zone_code
                ),
                details: serde_json::json!({
                    "expected": zone, "customer_zone": customer.price_zone_code,
                }),
            });
        }
    }
    if input.strict && !import_warnings.is_empty() {
        return Err(AppError::Validation(
            import_warnings
                .iter()
                .map(|w| w.message.clone())
                .collect::<Vec<_>>()
                .join("; "),
        ));
    }
    if flat.lines.is_empty() {
        return Err(AppError::Validation(
            "none of the product codes of the configuration is known".into(),
        ));
    }

    let today = service::today();
    let mut quotation_input = QuotationInput {
        customer_id: input.customer_id,
        opportunity_id: None,
        // An import is always priced on today's price list.
        quote_date: Some(today),
        price_date: Some(today),
        valid_days: input.valid_days,
        notes: input.notes.clone(),
        purpose: input.purpose.clone(),
        delivery_country_code: input.delivery_country_code.clone(),
        power_grid_id: input.power_grid_id,
        clear_power_grid: None,
        lines: flat.lines,
    };

    let mut tx = db.begin().await?;
    // Serialises imports of the same configuration, so that two concurrent first imports cannot
    // create two quotations.
    sqlx::query("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))")
        .bind(format!(
            "sales.configured:{}:{source}:{external_ref}",
            user.company_id
        ))
        .execute(&mut *tx)
        .await?;
    let latest: Option<(Uuid, String, Option<Uuid>, Uuid)> = sqlx::query_as(
        "SELECT id, status, opportunity_id, customer_id FROM sales.quotations
         WHERE company_id = $1 AND import_source = $2 AND import_external_ref = $3
         ORDER BY revision DESC LIMIT 1",
    )
    .bind(user.company_id)
    .bind(&source)
    .bind(&external_ref)
    .fetch_optional(&mut *tx)
    .await?;

    let (id, action) = match latest {
        None => (
            create_draft(&mut tx, db, user, &quotation_input).await?,
            "created",
        ),
        Some((id, status, opportunity_id, customer_id)) => {
            // A link to an opportunity made in the ERP survives the re-import, unless the
            // configuration moved to another customer (the opportunity belongs to the old one).
            quotation_input.opportunity_id =
                opportunity_id.filter(|_| customer_id == input.customer_id);
            match QuotationStatus::parse(&status) {
                Some(QuotationStatus::Draft) => {
                    update_draft(&mut tx, db, user, id, &quotation_input, false).await?;
                    (id, "updated")
                }
                Some(QuotationStatus::Sent | QuotationStatus::Rejected) => {
                    let new_id =
                        revise(&mut tx, db, user, id, RevisionPricing::Keep).await?;
                    update_draft(&mut tx, db, user, new_id, &quotation_input, false)
                        .await?;
                    (new_id, "revised")
                }
                _ => {
                    return Err(AppError::Conflict(format!(
                        "the quotation for {source} {external_ref} is {status} and can no longer be changed"
                    )))
                }
            }
        }
    };
    sqlx::query(
        "UPDATE sales.quotations SET import_source = $2, import_external_ref = $3, configuration = $4
         WHERE id = $1",
    )
    .bind(id)
    .bind(&source)
    .bind(&external_ref)
    .bind(&input.configuration)
    .execute(&mut *tx)
    .await?;
    let unknown: Vec<&str> = import_warnings
        .iter()
        .filter(|w| w.kind == "unknown_product")
        .map(|w| w.product_code.as_str())
        .collect();
    audit::record(
        &mut tx,
        user,
        "quotation",
        id,
        "imported",
        serde_json::json!({
            "source": source, "external_ref": external_ref, "action": action,
            "unknown_codes": unknown,
        }),
    )
    .await?;
    let mut q = service::load_quotation(&mut tx, user.company_id, id, false).await?;
    quotation_hints(&mut tx, &mut q).await?;
    import_warnings.append(&mut q.warnings);
    q.warnings = import_warnings;
    tx.commit().await?;
    Ok(ConfiguredImportResult {
        action: action.into(),
        quotation: q,
    })
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new().routes(routes!(import_configured))
}

#[cfg(test)]
mod tests {
    use super::*;
    use rust_decimal_macros::dec;

    fn node(code: &str, children: Vec<ConfiguredLineInput>) -> ConfiguredLineInput {
        ConfiguredLineInput {
            code: code.into(),
            quantity: dec!(1),
            section: None,
            comment: None,
            description: None,
            unit_price: None,
            percent_of_parent: None,
            percent_base: None,
            children,
        }
    }

    #[test]
    fn flattens_depth_first_and_skips_unknown_subtrees() {
        let a = Uuid::from_u128(1);
        let b = Uuid::from_u128(2);
        let c = Uuid::from_u128(3);
        let tree = vec![
            node(
                "A",
                vec![
                    node("B", vec![node("C", vec![])]),
                    node("X", vec![node("C", vec![])]),
                ],
            ),
            node("C", vec![]),
        ];
        let f = flatten(&tree, &|code| match code {
            "A" => Some(a),
            "B" => Some(b),
            "C" => Some(c),
            _ => None,
        });
        let got: Vec<(Uuid, Option<i32>)> = f
            .lines
            .iter()
            .map(|l| (l.product_id, l.parent_position))
            .collect();
        assert_eq!(got, [(a, None), (b, Some(1)), (c, Some(2)), (c, None)]);
        assert_eq!(f.warnings.len(), 1);
        assert_eq!(f.warnings[0].product_code, "X");
        assert_eq!(f.warnings[0].details["path"], "1.2");
        assert_eq!(f.warnings[0].details["skipped_children"], 1);
    }

    #[test]
    fn rejects_too_deep_trees() {
        // MAX_DEPTH levels are accepted, one more is not.
        let mut tree = node("A", vec![]);
        for _ in 1..MAX_DEPTH {
            tree = node("A", vec![tree]);
        }
        assert_eq!(count_lines(&[tree.clone()], 1).unwrap(), MAX_DEPTH);
        let tree = node("A", vec![tree]);
        assert!(count_lines(&[tree], 1).is_err());
        assert_eq!(
            count_lines(&[node("A", vec![node("B", vec![])])], 1).unwrap(),
            2
        );
    }
}
