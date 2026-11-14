use chrono::{Datelike, Duration, NaiveDate};
use rust_decimal::Decimal;
use sqlx::{PgConnection, PgPool};
use tradocraft_core::{new_id, numbering, AppError, AppResult, CurrentUser};
use tradocraft_crm::rebates::rebate_rules;
use tradocraft_crm::{get_customer_for_quoting, QuotingCustomer};
use tradocraft_pricing::{
    percent_of_parent_price, price_line, resolve_rebate, totals, LineInput, PricedLine,
    PricingType, RebateSource, Totals,
};
use tradocraft_products::get_products_for_quoting_with;
use uuid::Uuid;

use crate::model::*;

pub const DEFAULT_VALID_DAYS: i64 = 30;

/// Customer conditions + priced lines + totals: everything needed to store or show a quotation.
pub struct Priced {
    pub customer: QuotingCustomer,
    pub price_date: NaiveDate,
    pub lines: Vec<QuotationLine>,
    pub totals: Totals,
}

impl Priced {
    pub fn unconfirmed_lines(&self) -> i32 {
        self.lines.iter().filter(|l| !l.price_confirmed).count() as i32
    }
}

pub fn today() -> NaiveDate {
    tradocraft_core::today()
}

/// Longest accepted section heading.
pub const MAX_SECTION_LEN: usize = 120;

/// Longest accepted line remark.
pub const MAX_REMARK_LEN: usize = 2000;

/// Checks the structure of the lines: a parent is an earlier line, a percentage needs a parent and
/// excludes a confirmed unit price. Shared by previews, drafts and imports.
pub fn validate_structure(inputs: &[QuotationLineInput]) -> AppResult<()> {
    for (i, l) in inputs.iter().enumerate() {
        let n = i + 1;
        if let Some(p) = l.parent_position {
            if p < 1 || p as usize >= n {
                return Err(AppError::Validation(format!(
                    "line {n}: parent_position must refer to an earlier line"
                )));
            }
        }
        if l.section
            .as_deref()
            .is_some_and(|s| s.trim().chars().count() > MAX_SECTION_LEN)
        {
            return Err(AppError::Validation(format!(
                "line {n}: section is longer than {MAX_SECTION_LEN} characters"
            )));
        }
        for (name, v) in [
            ("production_remark", &l.production_remark),
            ("customer_remark", &l.customer_remark),
        ] {
            if v.trim().chars().count() > MAX_REMARK_LEN {
                return Err(AppError::Validation(format!(
                    "line {n}: {name} is longer than {MAX_REMARK_LEN} characters"
                )));
            }
        }
        if l.customer_remark_language
            .as_deref()
            .is_some_and(|c| !tradocraft_core::is_language(c))
        {
            return Err(AppError::Validation(format!(
                "line {n}: customer_remark_language must be one of {}",
                tradocraft_core::LANGUAGES.join(", ")
            )));
        }
        match l.percent_of_parent {
            Some(_) if l.parent_position.is_none() => {
                return Err(AppError::Validation(format!(
                    "line {n}: percent_of_parent needs a parent_position"
                )))
            }
            Some(_) if l.unit_price.is_some() => {
                return Err(AppError::Validation(format!(
                    "line {n}: percent_of_parent cannot be combined with unit_price"
                )))
            }
            Some(p) if p < Decimal::ZERO || p > Decimal::from(1000) => {
                return Err(AppError::Validation(format!(
                    "line {n}: percent_of_parent must be between 0 and 1000"
                )))
            }
            None if l.percent_base.is_some() => {
                return Err(AppError::Validation(format!(
                    "line {n}: percent_base needs percent_of_parent"
                )))
            }
            _ => {}
        }
    }
    Ok(())
}

/// Adds the required options of every line with `add_options` as option lines right below it
/// (and below the options already there), renumbering the parent positions. Without any such line
/// the input is returned unchanged.
pub async fn expand_options(
    db: &PgPool,
    inputs: &[QuotationLineInput],
) -> AppResult<Vec<QuotationLineInput>> {
    if !inputs.iter().any(|l| l.add_options) {
        return Ok(inputs.to_vec());
    }
    let ids: Vec<Uuid> = inputs
        .iter()
        .filter(|l| l.add_options)
        .map(|l| l.product_id)
        .collect();
    let options = tradocraft_products::options::required_options(db, &ids).await?;
    // The old position of every line -> its new position; children follow their parent directly,
    // so each line's descendants are emitted right after it.
    let n = inputs.len();
    let mut children: Vec<Vec<usize>> = vec![Vec::new(); n];
    let mut roots: Vec<usize> = Vec::new();
    for (i, l) in inputs.iter().enumerate() {
        match l.parent_position {
            Some(p) => children[(p as usize) - 1].push(i),
            None => roots.push(i),
        }
    }
    let mut out: Vec<QuotationLineInput> = Vec::with_capacity(n);
    // (old index, new parent position)
    let mut stack: Vec<(usize, Option<i32>)> = roots.iter().rev().map(|i| (*i, None)).collect();
    while let Some((i, parent)) = stack.pop() {
        let mut l = inputs[i].clone();
        l.parent_position = parent;
        let add = std::mem::take(&mut l.add_options);
        out.push(l);
        let me = out.len() as i32;
        let existing: Vec<Uuid> = children[i].iter().map(|c| inputs[*c].product_id).collect();
        let mut pending: Vec<(usize, Option<i32>)> = Vec::new();
        if add {
            for o in options.get(&inputs[i].product_id).into_iter().flatten() {
                if existing.contains(&o.option_product_id) {
                    continue;
                }
                let quantity = inputs[i]
                    .quantity
                    .checked_mul(o.default_quantity)
                    .ok_or_else(|| {
                        AppError::Validation(format!(
                            "quantity of option {} is too large",
                            o.option_code
                        ))
                    })?
                    .round_dp(4);
                // A synthetic input: index past the end, filled in below.
                out.push(QuotationLineInput {
                    product_id: o.option_product_id,
                    quantity,
                    line_discount_percent: Decimal::ZERO,
                    description: None,
                    unit_price: None,
                    parent_position: Some(me),
                    section: None,
                    comment: None,
                    percent_of_parent: None,
                    percent_base: None,
                    production_remark: String::new(),
                    customer_remark: String::new(),
                    customer_remark_language: None,
                    favorite_item_id: None,
                    add_options: false,
                });
            }
        }
        for c in children[i].iter().rev() {
            pending.push((*c, Some(me)));
        }
        // Existing children come after the added options; the stack pops in input order.
        stack.extend(pending);
    }
    Ok(out)
}

/// Every `favorite_item_id` must be an item of a favorite of the caller's company (422 otherwise;
/// an id that belongs to another company or no longer exists is not told apart).
pub async fn check_favorite_items(
    db: &PgPool,
    company_id: Uuid,
    inputs: &[QuotationLineInput],
) -> AppResult<()> {
    let mut ids: Vec<Uuid> = inputs.iter().filter_map(|l| l.favorite_item_id).collect();
    ids.sort();
    ids.dedup();
    if ids.is_empty() {
        return Ok(());
    }
    let found: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM sales.favorite_items i
         JOIN sales.favorites f ON f.id = i.favorite_id
         WHERE i.id = ANY($1) AND f.company_id = $2",
    )
    .bind(&ids)
    .bind(company_id)
    .fetch_one(db)
    .await?;
    if found != ids.len() as i64 {
        return Err(AppError::Validation(
            "favorite_item_id does not refer to a favorite of this company".into(),
        ));
    }
    Ok(())
}

/// The trimmed text, or `None` when it is absent or blank.
fn clean(s: &Option<String>) -> Option<String> {
    s.as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_string)
}

/// Prices quotation lines from the price list valid on `price_date`, with the customer's rebates
/// valid on that date. Used for previews, drafts and repriced revisions; never for sent quotations.
///
/// Lines are priced in order, so a line priced as a percentage of its parent (always an earlier
/// line) is resolved after the parent. The default description is the product name in the
/// customer's language, else the base name.
pub async fn price_lines(
    db: &PgPool,
    company_id: Uuid,
    customer_id: Uuid,
    price_date: NaiveDate,
    inputs: &[QuotationLineInput],
) -> AppResult<Priced> {
    validate_structure(inputs)?;
    check_favorite_items(db, company_id, inputs).await?;
    let expanded = expand_options(db, inputs).await?;
    let inputs = &expanded[..];
    let customer = get_customer_for_quoting(db, company_id, customer_id).await?;
    let rules = rebate_rules(db, company_id, customer_id).await?;
    let mut ids: Vec<Uuid> = inputs.iter().map(|l| l.product_id).collect();
    ids.sort();
    ids.dedup();
    // Products that only appear on percent-of-parent lines do not need a zone price.
    let price_optional: Vec<Uuid> = ids
        .iter()
        .copied()
        .filter(|id| {
            inputs
                .iter()
                .filter(|l| l.product_id == *id)
                .all(|l| l.percent_of_parent.is_some())
        })
        .collect();
    let products = get_products_for_quoting_with(
        db,
        company_id,
        customer.price_zone_id,
        &customer.price_zone_code,
        price_date,
        &ids,
        &price_optional,
    )
    .await?;
    let names =
        tradocraft_products::translations::names_in(db, &ids, &customer.customer.language).await?;

    let mut lines: Vec<QuotationLine> = Vec::with_capacity(inputs.len());
    let mut priced: Vec<PricedLine> = Vec::with_capacity(inputs.len());
    for (i, input) in inputs.iter().enumerate() {
        let n = i + 1;
        let qp = &products[&input.product_id];
        let pricing_type =
            PricingType::parse(&qp.product.pricing_type).unwrap_or(PricingType::List);
        let parent = input.parent_position.map(|p| (p as usize) - 1);
        let percent = input.percent_of_parent.map(|p| p.round_dp(3));
        let base = input
            .percent_base
            .unwrap_or(PercentBase::ParentListUnitPrice);
        let (list_price, confirmed, rebate, source) = match (percent, parent) {
            (Some(pct), Some(pi)) => {
                // Priced from the parent: a percentage of its list or net unit price. The line is
                // only as confirmed as its parent (an unconfirmed indicative parent price).
                let unit = percent_of_parent_price(&priced[pi], pct, base.to_pricing())
                    .map_err(|e| AppError::Validation(format!("line {n}: {e}")))?;
                let (rebate, source) = if base.to_pricing().is_net() {
                    if !input.line_discount_percent.is_zero() {
                        return Err(AppError::Validation(format!(
                            "line {n}: a percentage of the parent's net price cannot be discounted"
                        )));
                    }
                    (Decimal::ZERO, RebateSource::Net)
                } else {
                    resolve_rebate(
                        &rules,
                        customer.discount_percent,
                        qp.product.id,
                        qp.product.family_id,
                        pricing_type,
                        price_date,
                    )
                };
                (unit, lines[pi].price_confirmed, rebate, source)
            }
            _ => {
                let (list_price, confirmed) = match (pricing_type, input.unit_price) {
                    (PricingType::Indicative, Some(p)) => (p, true),
                    (PricingType::Indicative, None) => (qp.list_unit_price, false),
                    (_, Some(_)) => {
                        return Err(AppError::Validation(format!(
                        "line {n}: {} has a fixed list price; only indicative prices can be set",
                        qp.product.code
                    )))
                    }
                    (_, None) => (qp.list_unit_price, true),
                };
                let (rebate, source) = resolve_rebate(
                    &rules,
                    customer.discount_percent,
                    qp.product.id,
                    qp.product.family_id,
                    pricing_type,
                    price_date,
                );
                (list_price, confirmed, rebate, source)
            }
        };
        if pricing_type == PricingType::Net && !input.line_discount_percent.is_zero() {
            return Err(AppError::Validation(format!(
                "line {n}: {} has a net price and cannot be discounted",
                qp.product.code
            )));
        }
        let p = price_line(&LineInput {
            list_unit_price: list_price,
            quantity: input.quantity,
            customer_discount_percent: rebate,
            line_discount_percent: input.line_discount_percent,
            vat_rate: if customer.customer.vat_regime == "domestic" {
                qp.product.vat_rate
            } else {
                Decimal::ZERO
            },
        })
        .map_err(|e| AppError::Validation(format!("line {n}: {e}")))?;
        lines.push(QuotationLine {
            position: n as i32,
            product_id: Some(qp.product.id),
            product_code: qp.product.code.clone(),
            description: input
                .description
                .clone()
                .filter(|d| !d.trim().is_empty())
                .or_else(|| names.get(&qp.product.id).cloned())
                .unwrap_or_else(|| qp.product.name.clone()),
            unit: qp.product.unit.clone(),
            quantity: p.quantity,
            list_unit_price: p.list_unit_price,
            pricing_type: pricing_type.as_str().to_string(),
            rebate_percent: rebate,
            rebate_source: source.as_str().to_string(),
            line_discount_percent: p.line_discount_percent,
            net_unit_price: p.net_unit_price,
            line_total: p.line_total,
            vat_rate: p.vat_rate,
            price_confirmed: confirmed,
            parent_position: input.parent_position,
            section: clean(&input.section),
            comment: clean(&input.comment),
            percent_of_parent: percent,
            percent_base: percent.map(|_| base.to_pricing().as_str().to_string()),
            production_remark: if input.production_remark.trim().is_empty() {
                qp.product.default_production_remark.clone()
            } else {
                input.production_remark.trim().to_string()
            },
            customer_remark: input.customer_remark.trim().to_string(),
            customer_remark_language: input
                .customer_remark_language
                .clone()
                .filter(|_| !input.customer_remark.trim().is_empty()),
            favorite_item_id: input.favorite_item_id,
        });
        priced.push(p);
    }
    let totals = totals(&priced);
    Ok(Priced {
        customer,
        price_date,
        lines,
        totals,
    })
}

pub fn vat_groups(t: &Totals) -> Vec<VatGroup> {
    t.vat_groups
        .iter()
        .map(|g| VatGroup {
            vat_rate: g.vat_rate,
            base: g.base,
            vat: g.vat,
        })
        .collect()
}

/// Recomputes VAT groups from stored lines (same rules as when they were priced).
pub fn stored_totals(lines: &[QuotationLine]) -> Totals {
    let priced: Vec<PricedLine> = lines
        .iter()
        .map(|l| PricedLine {
            list_unit_price: l.list_unit_price,
            quantity: l.quantity,
            customer_discount_percent: l.rebate_percent,
            line_discount_percent: l.line_discount_percent,
            net_unit_price: l.net_unit_price,
            line_total: l.line_total,
            vat_rate: l.vat_rate,
        })
        .collect();
    totals(&priced)
}

/// The line inputs that reproduce a stored quotation (used for revisions and comparisons).
/// With `keep_confirmed_prices`, confirmed indicative prices are carried over.
pub fn line_inputs(
    lines: &[QuotationLine],
    keep_confirmed_prices: bool,
) -> AppResult<Vec<QuotationLineInput>> {
    // Lines without a product (the SHIPPING line) are not priced from a price list; the shipping
    // workflow decides again whether the repriced quotation needs one. Parent positions are mapped
    // onto the positions in the filtered list.
    let kept: Vec<i32> = lines
        .iter()
        .filter(|l| l.product_id.is_some())
        .map(|l| l.position)
        .collect();
    let new_position = |old: i32| kept.iter().position(|p| *p == old).map(|i| i as i32 + 1);
    lines
        .iter()
        .filter(|l| l.product_id.is_some())
        .map(|l| {
            let product_id = l.product_id.ok_or_else(|| {
                AppError::Validation(format!("line {} has no product", l.position))
            })?;
            Ok(QuotationLineInput {
                product_id,
                quantity: l.quantity,
                line_discount_percent: l.line_discount_percent,
                description: Some(l.description.clone()),
                unit_price: (keep_confirmed_prices
                    && l.pricing_type == "indicative"
                    && l.price_confirmed
                    && l.percent_of_parent.is_none())
                .then_some(l.list_unit_price),
                parent_position: l.parent_position.and_then(new_position),
                section: l.section.clone(),
                comment: l.comment.clone(),
                percent_of_parent: l.percent_of_parent,
                percent_base: l.percent_base.as_deref().and_then(PercentBase::parse),
                production_remark: l.production_remark.clone(),
                customer_remark: l.customer_remark.clone(),
                customer_remark_language: l.customer_remark_language.clone(),
                favorite_item_id: l.favorite_item_id,
                add_options: false,
            })
        })
        .collect()
}

pub fn validate_input(input: &QuotationInput) -> AppResult<()> {
    check_grid_clear(input.clear_power_grid, input.power_grid_id)?;
    if input.lines.is_empty() {
        return Err(AppError::Validation(
            "a quotation needs at least one line".into(),
        ));
    }
    if let Some(days) = input.valid_days {
        if !(1..=365).contains(&days) {
            return Err(AppError::Validation(
                "valid_days must be between 1 and 365".into(),
            ));
        }
    }
    if let Some(p) = &input.purpose {
        validate_purpose(p)?;
    }
    if let Some(c) = &input.delivery_country_code {
        normalize_country(c)?;
    }
    validate_structure(&input.lines)?;
    for (i, l) in input.lines.iter().enumerate() {
        if l.unit_price.is_some_and(|p| p < Decimal::ZERO) {
            return Err(AppError::Validation(format!(
                "line {}: unit price cannot be negative",
                i + 1
            )));
        }
    }
    Ok(())
}

pub async fn allocate_number(
    conn: &mut PgConnection,
    company_id: Uuid,
    date: NaiveDate,
) -> AppResult<String> {
    let n = numbering::next_number(conn, company_id, "quotation", date.year()).await?;
    Ok(format!("Q{}-{:05}", date.year(), n))
}

pub struct NewQuotation<'a> {
    pub number: &'a str,
    pub revision: i32,
    pub priced: &'a Priced,
    pub quote_date: NaiveDate,
    pub valid_until: NaiveDate,
    pub notes: &'a str,
    pub currency: &'a str,
    pub supersedes_id: Option<Uuid>,
    pub opportunity_id: Option<Uuid>,
    pub purpose: &'a str,
    pub delivery_country_code: Option<&'a str>,
    pub power_grid_id: Option<Uuid>,
}

pub const PURPOSES: [&str; 2] = ["installation", "stock"];

/// Checks a purpose value (`installation` or `stock`).
pub fn validate_purpose(purpose: &str) -> AppResult<&str> {
    PURPOSES
        .iter()
        .find(|p| **p == purpose)
        .copied()
        .ok_or_else(|| {
            AppError::Validation(format!("purpose must be one of: {}", PURPOSES.join(", ")))
        })
}

/// A 2-letter country code, uppercased. Blank counts as not given.
pub fn normalize_country(code: &str) -> AppResult<Option<String>> {
    let code = code.trim();
    if code.is_empty() {
        return Ok(None);
    }
    if code.len() != 2 || !code.chars().all(|c| c.is_ascii_alphabetic()) {
        return Err(AppError::Validation(
            "delivery_country_code must be a 2-letter code".into(),
        ));
    }
    Ok(Some(code.to_uppercase()))
}

/// The delivery country to store: the given one, else (for an installation) the customer's.
/// `fallback` is what applies when nothing is given (the stored value on an update).
pub fn resolve_delivery_country(
    given: Option<&str>,
    fallback: Option<String>,
    purpose: &str,
    customer_country: &str,
) -> AppResult<Option<String>> {
    if let Some(c) = given.map(normalize_country).transpose()?.flatten() {
        return Ok(Some(c));
    }
    // An invalid customer default must not block the quotation: it just yields no country.
    Ok(fallback.or_else(|| {
        (purpose == "installation")
            .then(|| normalize_country(customer_country).ok().flatten())
            .flatten()
    }))
}

/// `clear_power_grid: true` together with a `power_grid_id` contradicts itself (422).
pub fn check_grid_clear(clear: Option<bool>, given: Option<Uuid>) -> AppResult<()> {
    tradocraft_products::power::check_grid_clear(clear, given)
}

/// The grid to store on a quotation: a given grid must belong to the delivery country (422
/// otherwise); without a given one the `kept` grid stays only while it fits the country.
pub async fn resolve_power_grid(
    conn: &mut PgConnection,
    given: Option<Uuid>,
    kept: Option<Uuid>,
    delivery_country: Option<&str>,
) -> AppResult<Option<Uuid>> {
    tradocraft_products::power::resolve_power_grid(conn, given, kept, delivery_country, "delivery")
        .await
}

fn describe_supply(s: &tradocraft_products::power::PowerSupply) -> String {
    if s.current_type == "dc" {
        return format!("{}V DC", s.voltage_v);
    }
    format!(
        "{}V {}-phase {}Hz (+/-{}%)",
        s.voltage_v,
        s.phases.unwrap_or(1),
        s.frequency_hz
            .map_or("50/60".to_string(), |f| f.to_string()),
        s.tolerance_pct
    )
}

/// Power grid warnings for lines delivered to a country: none for stock purchases. `country` falls
/// back to the customer's country at the call sites. Warnings never block anything.
pub async fn power_warnings(
    conn: &mut PgConnection,
    purpose: &str,
    country: &str,
    grid_id: Option<Uuid>,
    lines: &[(Option<Uuid>, &str)],
) -> AppResult<Vec<SalesWarning>> {
    use tradocraft_products::power::{check_products, PowerCompatibility};
    if purpose == "stock" || normalize_country(country).ok().flatten().is_none() {
        return Ok(vec![]);
    }
    // Warnings are advisory: a stored grid that no longer belongs to the country (its country was
    // edited since) is ignored and the country's active grids are used instead.
    let grid_id = match grid_id {
        Some(g) if !tradocraft_products::power::grid_in_country(conn, g, country).await? => None,
        other => other,
    };
    let mut ids: Vec<Uuid> = lines.iter().filter_map(|(id, _)| *id).collect();
    ids.sort();
    ids.dedup();
    let findings = check_products(conn, &ids, country, grid_id).await?;
    let country = country.trim().to_uppercase();
    let mut out = Vec::new();
    for (id, code) in lines {
        let Some(f) = id.and_then(|id| findings.iter().find(|f| f.product_id == id)) else {
            continue;
        };
        if out.iter().any(|w: &SalesWarning| w.product_code == *code) {
            continue;
        }
        let (status, message, supported, available) = match &f.compatibility {
            PowerCompatibility::Incompatible {
                supported,
                available,
            } => (
                "incompatible",
                format!(
                    "{code} runs on {} but the grid in {country} offers {}",
                    supported
                        .iter()
                        .map(describe_supply)
                        .collect::<Vec<_>>()
                        .join(" / "),
                    available
                        .iter()
                        .map(|g| g.name.clone())
                        .collect::<Vec<_>>()
                        .join(" / "),
                ),
                serde_json::to_value(supported).unwrap_or_default(),
                serde_json::to_value(available).unwrap_or_default(),
            ),
            PowerCompatibility::NeedsExternalSupply => (
                "needs_external_supply",
                format!("{code} runs on DC and needs an external power supply"),
                serde_json::Value::Null,
                serde_json::Value::Null,
            ),
            PowerCompatibility::UnknownGrid => (
                "unknown_grid",
                format!("no power grid data for {country}; the fit of {code} is unknown"),
                serde_json::Value::Null,
                serde_json::Value::Null,
            ),
            _ => continue,
        };
        out.push(SalesWarning {
            kind: "power_grid".into(),
            product_code: (*code).to_string(),
            message,
            details: serde_json::json!({
                "status": status, "country_code": country,
                "supported": supported, "available": available,
            }),
        });
    }
    Ok(out)
}

/// Product relation checks for lines: a warning per incompatible pair and the suggested additions.
/// Skipped for stock purchases. Never blocks anything.
pub async fn relation_checks(
    conn: &mut PgConnection,
    purpose: &str,
    lines: &[(Option<Uuid>, &str)],
) -> AppResult<(Vec<SalesWarning>, Vec<crate::model::SalesSuggestion>)> {
    if purpose == "stock" {
        return Ok((vec![], vec![]));
    }
    let mut ids: Vec<Uuid> = Vec::new();
    for id in lines.iter().filter_map(|(id, _)| *id) {
        if !ids.contains(&id) {
            ids.push(id);
        }
    }
    let eval = tradocraft_products::relations::check_products(conn, &ids).await?;
    let warnings = eval
        .conflicts
        .into_iter()
        .map(|c| SalesWarning {
            kind: "incompatible_products".into(),
            message: if c.note.is_empty() {
                format!(
                    "{} and {} are not compatible",
                    c.product_a_code, c.product_b_code
                )
            } else {
                format!(
                    "{} and {} are not compatible: {}",
                    c.product_a_code, c.product_b_code, c.note
                )
            },
            details: serde_json::json!({
                "product_codes": [c.product_a_code, c.product_b_code],
                "note": c.note,
                "relation_id": c.relation_id,
            }),
            product_code: c.product_a_code,
        })
        .collect();
    let suggestions = eval
        .suggestions
        .into_iter()
        .map(|s| crate::model::SalesSuggestion {
            product_id: s.product_id,
            product_code: s.product_code,
            product_name: s.product_name,
            reason: match s.reason {
                tradocraft_products::relations::SuggestionReason::Rule => "rule",
                tradocraft_products::relations::SuggestionReason::OftenBoughtTogether => {
                    "often_bought_together"
                }
            }
            .into(),
            strength: s.strength,
            confidence: s.confidence,
            because_of_code: s.because_of_code,
            note: s.note,
        })
        .collect();
    Ok((warnings, suggestions))
}

pub async fn insert_quotation(
    conn: &mut PgConnection,
    user: &CurrentUser,
    q: NewQuotation<'_>,
) -> AppResult<Uuid> {
    let id = new_id();
    let c = &q.priced.customer;
    sqlx::query(
        "INSERT INTO sales.quotations (
            id, company_id, number, revision, status, customer_id, customer_name, customer_vat_number,
            customer_street, customer_postal_code, customer_city, customer_country_code, customer_language,
            price_zone_code, customer_discount_percent, currency, quote_date, valid_until, notes,
            subtotal, vat_total, total, supersedes_id, created_by, opportunity_id, price_date,
            purpose, delivery_country_code, power_grid_id, vat_regime)
         VALUES ($1, $2, $3, $4, 'draft', $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18,
                 $19, $20, $21, $22, $23, $24, $25, $26, $27, $28, $29)",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(q.number)
    .bind(q.revision)
    .bind(c.customer.id)
    .bind(&c.customer.name)
    .bind(&c.customer.vat_number)
    .bind(&c.customer.street)
    .bind(&c.customer.postal_code)
    .bind(&c.customer.city)
    .bind(&c.customer.country_code)
    .bind(&c.customer.language)
    .bind(&c.price_zone_code)
    .bind(c.discount_percent)
    .bind(q.currency)
    .bind(q.quote_date)
    .bind(q.valid_until)
    .bind(q.notes)
    .bind(q.priced.totals.subtotal)
    .bind(q.priced.totals.vat_total)
    .bind(q.priced.totals.total)
    .bind(q.supersedes_id)
    .bind(user.user_id)
    .bind(q.opportunity_id)
    .bind(q.priced.price_date)
    .bind(q.purpose)
    .bind(q.delivery_country_code)
    .bind(q.power_grid_id)
    .bind(&c.customer.vat_regime)
    .execute(&mut *conn)
    .await?;
    insert_lines(conn, id, &q.priced.lines).await?;
    Ok(id)
}

/// Inserts lines in position order. A line's `parent_position` must refer to an earlier line of
/// the same list; it becomes the `parent_line_id` of the stored row.
pub async fn insert_lines(
    conn: &mut PgConnection,
    quotation_id: Uuid,
    lines: &[QuotationLine],
) -> AppResult<()> {
    let mut ids: std::collections::HashMap<i32, Uuid> = std::collections::HashMap::new();
    let mut ordered: Vec<&QuotationLine> = lines.iter().collect();
    ordered.sort_by_key(|l| l.position);
    for l in ordered {
        let parent_line_id = match l.parent_position {
            Some(p) => Some(*ids.get(&p).ok_or_else(|| {
                AppError::Validation(format!(
                    "line {}: parent_position must refer to an earlier line",
                    l.position
                ))
            })?),
            None => None,
        };
        let id = new_id();
        ids.insert(l.position, id);
        sqlx::query(
            "INSERT INTO sales.quotation_lines (id, quotation_id, position, product_id, product_code, description,
                unit, quantity, list_unit_price, line_discount_percent, net_unit_price, line_total, vat_rate,
                pricing_type, rebate_percent, rebate_source, price_confirmed, parent_line_id, section, comment,
                percent_of_parent, percent_base, production_remark, customer_remark,
                customer_remark_language, favorite_item_id)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20,
                $21, $22, $23, $24, $25, $26)",
        )
        .bind(id)
        .bind(quotation_id)
        .bind(l.position)
        .bind(l.product_id)
        .bind(&l.product_code)
        .bind(&l.description)
        .bind(&l.unit)
        .bind(l.quantity)
        .bind(l.list_unit_price)
        .bind(l.line_discount_percent)
        .bind(l.net_unit_price)
        .bind(l.line_total)
        .bind(l.vat_rate)
        .bind(&l.pricing_type)
        .bind(l.rebate_percent)
        .bind(&l.rebate_source)
        .bind(l.price_confirmed)
        .bind(parent_line_id)
        .bind(&l.section)
        .bind(&l.comment)
        .bind(l.percent_of_parent)
        .bind(&l.percent_base)
        .bind(&l.production_remark)
        .bind(&l.customer_remark)
        .bind(&l.customer_remark_language)
        .bind(l.favorite_item_id)
        .execute(&mut *conn)
        .await?;
    }
    Ok(())
}

const SELECT_HEADER: &str = "SELECT id, company_id, number, revision, status, customer_id, opportunity_id, customer_name,
    customer_vat_number, vat_regime, customer_street, customer_postal_code, customer_city,
    customer_country_code::text AS customer_country_code, customer_language::text AS customer_language,
    price_zone_code, customer_discount_percent, purpose, delivery_country_code::text AS delivery_country_code, power_grid_id, shipping_status,
    currency::text AS currency, quote_date, price_date, valid_until,
    notes, subtotal, vat_total, total, supersedes_id, created_by, created_at, updated_at, sent_at
    FROM sales.quotations";

pub async fn load_quotation(
    conn: &mut PgConnection,
    company_id: Uuid,
    id: Uuid,
    lock: bool,
) -> AppResult<Quotation> {
    let sql = format!(
        "{SELECT_HEADER} WHERE id = $1 AND company_id = $2{}",
        if lock { " FOR UPDATE" } else { "" }
    );
    let header: QuotationHeader = sqlx::query_as(&sql)
        .bind(id)
        .bind(company_id)
        .fetch_optional(&mut *conn)
        .await?
        .ok_or(AppError::NotFound("quotation"))?;
    let lines: Vec<QuotationLine> = sqlx::query_as(
        "SELECT l.position, l.product_id, l.product_code, l.description, l.unit, l.quantity, l.list_unit_price,
                l.pricing_type, l.rebate_percent, l.rebate_source, l.line_discount_percent, l.net_unit_price,
                l.line_total, l.vat_rate, l.price_confirmed, p.position AS parent_position, l.section, l.comment,
                l.percent_of_parent, l.percent_base, l.production_remark, l.customer_remark,
                l.customer_remark_language::text AS customer_remark_language, l.favorite_item_id
         FROM sales.quotation_lines l
         LEFT JOIN sales.quotation_lines p ON p.id = l.parent_line_id
         WHERE l.quotation_id = $1 ORDER BY l.position",
    )
    .bind(id)
    .fetch_all(&mut *conn)
    .await?;
    let vat_groups = vat_groups(&stored_totals(&lines));
    Ok(Quotation::new(header, lines, vat_groups))
}

pub fn valid_until(date: NaiveDate, valid_days: Option<i64>) -> NaiveDate {
    date + Duration::days(valid_days.unwrap_or(DEFAULT_VALID_DAYS))
}

pub fn status_of(q: &Quotation) -> QuotationStatus {
    QuotationStatus::parse(&q.status).unwrap_or(QuotationStatus::Draft)
}

/// Pricing on a date before the quote date ("previous price list") needs a permission
/// and is recorded in the audit trail by the caller.
pub fn check_price_date(
    user: &CurrentUser,
    quote_date: NaiveDate,
    price_date: NaiveDate,
) -> AppResult<bool> {
    if price_date < quote_date {
        user.require(tradocraft_core::Permission::PricesBackdate)?;
        Ok(true)
    } else {
        Ok(false)
    }
}
