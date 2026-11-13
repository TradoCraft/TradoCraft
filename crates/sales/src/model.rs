use chrono::{DateTime, NaiveDate, Utc};
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use utoipa::{IntoParams, ToSchema};
use uuid::Uuid;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum QuotationStatus {
    Draft,
    Sent,
    Accepted,
    Rejected,
    Superseded,
}

impl QuotationStatus {
    pub fn as_str(self) -> &'static str {
        match self {
            QuotationStatus::Draft => "draft",
            QuotationStatus::Sent => "sent",
            QuotationStatus::Accepted => "accepted",
            QuotationStatus::Rejected => "rejected",
            QuotationStatus::Superseded => "superseded",
        }
    }

    pub fn parse(s: &str) -> Option<Self> {
        Some(match s {
            "draft" => QuotationStatus::Draft,
            "sent" => QuotationStatus::Sent,
            "accepted" => QuotationStatus::Accepted,
            "rejected" => QuotationStatus::Rejected,
            "superseded" => QuotationStatus::Superseded,
            _ => return None,
        })
    }
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct QuotationLineInput {
    pub product_id: Uuid,
    #[schema(value_type = String, example = "2")]
    pub quantity: Decimal,
    #[serde(default)]
    #[schema(value_type = String, example = "0")]
    pub line_discount_percent: Decimal,
    /// Overrides the product name on the document.
    pub description: Option<String>,
    /// Confirmed unit price (before rebates) for an indicative product. Indicative lines must be
    /// confirmed before the quotation can be sent. Not allowed for other products.
    #[schema(value_type = Option<String>, example = "6500")]
    pub unit_price: Option<Decimal>,
    /// Makes this an option or sub-line of an earlier line: the 1-based position of that line in
    /// this list. Omitted: a top-level line.
    #[serde(default)]
    pub parent_position: Option<i32>,
    /// Heading the line is grouped under on the document. A sub-line without a section is shown
    /// under its parent's section.
    #[serde(default)]
    pub section: Option<String>,
    /// Extra text printed below the line on the document.
    #[serde(default)]
    pub comment: Option<String>,
    /// Prices the line as this percentage (0 to 1000, 3 decimals) of its parent line's unit price
    /// instead of the product's own price. Needs `parent_position`; not combined with `unit_price`.
    #[serde(default)]
    #[schema(value_type = Option<String>, example = "20")]
    pub percent_of_parent: Option<Decimal>,
    /// Which parent price `percent_of_parent` applies to; defaults to `parent_list_unit_price`.
    #[serde(default)]
    pub percent_base: Option<PercentBase>,
    /// Internal remark for production; never printed for or shown to the customer. When empty,
    /// the product's default production remark is used.
    #[serde(default)]
    pub production_remark: String,
    /// Remark printed under the description on the quotation and order documents.
    #[serde(default)]
    pub customer_remark: String,
    /// Also adds the required options of the product as option lines directly below this line
    /// (quantity: this line's quantity times the option's default quantity), unless the product is
    /// already an option line of this line. Not stored: send the resulting lines on later saves.
    #[serde(default)]
    pub add_options: bool,
}

/// Which price of the parent line a percent-of-parent line is computed from.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum PercentBase {
    /// The parent's list unit price; the line then gets its own rebate and line discount.
    ParentListUnitPrice,
    /// The parent's net unit price; the line is net (no rebate, no line discount).
    ParentNetUnitPrice,
}

impl PercentBase {
    pub fn to_pricing(self) -> tradocraft_pricing::PercentBase {
        match self {
            PercentBase::ParentListUnitPrice => {
                tradocraft_pricing::PercentBase::ParentListUnitPrice
            }
            PercentBase::ParentNetUnitPrice => tradocraft_pricing::PercentBase::ParentNetUnitPrice,
        }
    }

    pub fn parse(s: &str) -> Option<Self> {
        match tradocraft_pricing::PercentBase::parse(s)? {
            tradocraft_pricing::PercentBase::ParentListUnitPrice => {
                Some(PercentBase::ParentListUnitPrice)
            }
            tradocraft_pricing::PercentBase::ParentNetUnitPrice => {
                Some(PercentBase::ParentNetUnitPrice)
            }
        }
    }
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct QuotationInput {
    pub customer_id: Uuid,
    /// Links the quotation to an open opportunity of the same customer.
    pub opportunity_id: Option<Uuid>,
    /// Defaults to today.
    #[serde(default, deserialize_with = "tradocraft_core::serde_util::opt_date")]
    pub quote_date: Option<NaiveDate>,
    /// Date of the price list used. Defaults to the quote date (on update: unchanged).
    /// A date before the quote date needs the prices.backdate permission.
    #[serde(default, deserialize_with = "tradocraft_core::serde_util::opt_date")]
    pub price_date: Option<NaiveDate>,
    /// Defaults to 30 days.
    pub valid_days: Option<i64>,
    #[serde(default)]
    pub notes: String,
    /// `installation` (default) or `stock`. On update: unchanged when omitted.
    pub purpose: Option<String>,
    /// ISO 3166 alpha-2 country the goods go to. Defaults to the customer's country for an
    /// installation (on update: unchanged when omitted, unless the customer changes).
    pub delivery_country_code: Option<String>,
    /// The power grid at the delivery country the goods are connected to; it must belong to that
    /// country. On update: kept when omitted, unless the delivery country changes (then cleared).
    pub power_grid_id: Option<Uuid>,
    /// `true` clears the stored grid ("any grid of the delivery country"); it wins over the keep
    /// rule above and is refused (422) together with a `power_grid_id`. Absent or `false`: no effect.
    pub clear_power_grid: Option<bool>,
    /// The `version` the form was loaded with. On an update, a quotation that has changed since is
    /// refused (409 `record_changed`); left out, the save always goes through. Ignored on create.
    #[serde(default)]
    pub expected_version: Option<i64>,
    pub lines: Vec<QuotationLineInput>,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct PricingPreviewInput {
    pub customer_id: Uuid,
    #[serde(default, deserialize_with = "tradocraft_core::serde_util::opt_date")]
    pub quote_date: Option<NaiveDate>,
    /// Price list date; defaults to the quote date.
    #[serde(default, deserialize_with = "tradocraft_core::serde_util::opt_date")]
    pub price_date: Option<NaiveDate>,
    /// `installation` (default) or `stock`; a stock purpose skips the power grid warnings.
    pub purpose: Option<String>,
    /// Defaults to the customer's country.
    pub delivery_country_code: Option<String>,
    pub power_grid_id: Option<Uuid>,
    /// The saved draft quotation being edited. When it belongs to the caller's company (else 404)
    /// and is a draft with a quoted shipping cost, and a product line still needs a shipping quote,
    /// the preview also contains the `SHIPPING` line (as `shipping::shipping_line` builds it) in
    /// `lines`, `vat_groups` and the totals. Ignored for quotations that are not drafts.
    pub quotation_id: Option<Uuid>,
    pub lines: Vec<QuotationLineInput>,
}

/// A hint about a line that never blocks anything.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct SalesWarning {
    /// power_grid | incompatible_products
    pub kind: String,
    pub product_code: String,
    pub message: String,
    /// Machine-readable details: `status` (incompatible | needs_external_supply | unknown_grid),
    /// `country_code`, `supported` and `available` profiles. For `incompatible_products`:
    /// `product_codes` (the pair), `note` and `relation_id`.
    #[schema(value_type = Object)]
    pub details: serde_json::Value,
}

/// A product worth adding to the quotation or order. Never blocking, never added automatically.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct SalesSuggestion {
    pub product_id: Uuid,
    pub product_code: String,
    pub product_name: String,
    /// rule | often_bought_together
    pub reason: String,
    /// 1 to 100, for `rule`.
    pub strength: Option<i32>,
    /// 0 to 1, for `often_bought_together`.
    pub confidence: Option<f64>,
    /// The product on the quotation that triggered the suggestion.
    pub because_of_code: String,
    pub note: String,
}

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct QuotationLine {
    pub position: i32,
    pub product_id: Option<Uuid>,
    pub product_code: String,
    pub description: String,
    pub unit: String,
    #[schema(value_type = String)]
    pub quantity: Decimal,
    /// Zone list price, or the confirmed price of an indicative product.
    #[schema(value_type = String)]
    pub list_unit_price: Decimal,
    /// list | net | indicative
    pub pricing_type: String,
    /// Customer rebate applied to this line.
    #[schema(value_type = String)]
    pub rebate_percent: Decimal,
    /// Where the rebate comes from: product | family | general | net
    pub rebate_source: String,
    #[schema(value_type = String)]
    pub line_discount_percent: Decimal,
    #[schema(value_type = String)]
    pub net_unit_price: Decimal,
    #[schema(value_type = String)]
    pub line_total: Decimal,
    #[schema(value_type = String)]
    pub vat_rate: Decimal,
    /// False for an indicative price that still has to be confirmed.
    pub price_confirmed: bool,
    /// Position of the parent line (this is an option or sub-line of it).
    #[schema(required = false)]
    pub parent_position: Option<i32>,
    #[schema(required = false)]
    pub section: Option<String>,
    #[schema(required = false)]
    pub comment: Option<String>,
    /// Set when the line is priced as a percentage of its parent line.
    #[schema(value_type = Option<String>, required = false)]
    pub percent_of_parent: Option<Decimal>,
    /// parent_list_unit_price | parent_net_unit_price
    #[schema(required = false)]
    pub percent_base: Option<String>,
    /// Internal remark for production (never printed for customers).
    #[schema(required = false)]
    pub production_remark: String,
    /// Remark printed under the description on the documents.
    #[schema(required = false)]
    pub customer_remark: String,
}

#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct VatGroup {
    #[schema(value_type = String)]
    pub vat_rate: Decimal,
    #[schema(value_type = String)]
    pub base: Decimal,
    #[schema(value_type = String)]
    pub vat: Decimal,
}

/// Result of pricing lines without saving anything.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct PricingPreview {
    pub price_zone_code: String,
    #[schema(value_type = String)]
    pub customer_discount_percent: Decimal,
    pub quote_date: NaiveDate,
    pub price_date: NaiveDate,
    /// Indicative prices still to confirm; the quotation cannot be sent while this is not 0.
    pub unconfirmed_lines: i32,
    /// The priced product lines in input order, then (only when the input had a `quotation_id`
    /// with a quoted shipping cost) the `SHIPPING` line, which has no `product_id`.
    pub lines: Vec<QuotationLine>,
    pub vat_groups: Vec<VatGroup>,
    #[schema(value_type = String)]
    pub subtotal: Decimal,
    #[schema(value_type = String)]
    pub vat_total: Decimal,
    #[schema(value_type = String)]
    pub total: Decimal,
    /// Hints about the lines (power grid fit, incompatible products). Never blocking.
    pub warnings: Vec<SalesWarning>,
    /// Products worth adding (manual rules, then often bought together). Never blocking.
    pub suggestions: Vec<SalesSuggestion>,
}

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct QuotationSummary {
    pub id: Uuid,
    pub number: String,
    pub revision: i32,
    #[schema(value_type = QuotationStatus)]
    pub status: String,
    pub customer_id: Uuid,
    pub opportunity_id: Option<Uuid>,
    pub customer_name: String,
    /// installation | stock
    pub purpose: String,
    /// not_required | pending | quoted: whether a shipping cost still has to be requested.
    pub shipping_status: String,
    pub quote_date: NaiveDate,
    pub valid_until: NaiveDate,
    pub currency: String,
    #[schema(value_type = String)]
    pub subtotal: Decimal,
    #[schema(value_type = String)]
    pub total: Decimal,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct QuotationPage {
    pub items: Vec<QuotationSummary>,
    pub total: i64,
}

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct QuotationHeader {
    pub id: Uuid,
    pub company_id: Uuid,
    pub number: String,
    pub revision: i32,
    /// Raised on every change. Send it back as `expected_version` when saving: a quotation someone
    /// else changed meanwhile is refused (409 `record_changed`).
    pub version: i64,
    #[schema(value_type = QuotationStatus)]
    pub status: String,
    pub customer_id: Uuid,
    pub opportunity_id: Option<Uuid>,
    pub customer_name: String,
    pub customer_vat_number: Option<String>,
    /// `domestic` (VAT charged), `intra_eu` (reverse charge) or `outside_eu`: VAT is only shown and
    /// charged for `domestic`.
    pub vat_regime: String,
    pub customer_street: String,
    pub customer_postal_code: String,
    pub customer_city: String,
    pub customer_country_code: String,
    pub customer_language: String,
    pub price_zone_code: String,
    #[schema(value_type = String)]
    pub customer_discount_percent: Decimal,
    /// installation | stock
    pub purpose: String,
    /// Country the goods are delivered to (ISO alpha-2).
    pub delivery_country_code: Option<String>,
    /// The grid at the delivery country the goods are connected to.
    pub power_grid_id: Option<Uuid>,
    /// not_required | pending (shipping cost still to be quoted; sending is blocked) | quoted
    pub shipping_status: String,
    pub currency: String,
    pub quote_date: NaiveDate,
    pub price_date: NaiveDate,
    pub valid_until: NaiveDate,
    pub notes: String,
    #[schema(value_type = String)]
    pub subtotal: Decimal,
    #[schema(value_type = String)]
    pub vat_total: Decimal,
    #[schema(value_type = String)]
    pub total: Decimal,
    pub supersedes_id: Option<Uuid>,
    pub created_by: Uuid,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub sent_at: Option<DateTime<Utc>>,
}

/// A quotation with its lines (flat JSON: header fields, `lines`, `vat_groups`).
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct Quotation {
    pub id: Uuid,
    pub company_id: Uuid,
    pub number: String,
    pub revision: i32,
    /// Raised on every change. Send it back as `expected_version` when saving: a quotation someone
    /// else changed meanwhile is refused (409 `record_changed`).
    pub version: i64,
    #[schema(value_type = QuotationStatus)]
    pub status: String,
    pub customer_id: Uuid,
    pub opportunity_id: Option<Uuid>,
    pub customer_name: String,
    pub customer_vat_number: Option<String>,
    /// `domestic` (VAT charged), `intra_eu` (reverse charge) or `outside_eu`: VAT is only shown and
    /// charged for `domestic`.
    pub vat_regime: String,
    pub customer_street: String,
    pub customer_postal_code: String,
    pub customer_city: String,
    pub customer_country_code: String,
    pub customer_language: String,
    pub price_zone_code: String,
    #[schema(value_type = String)]
    pub customer_discount_percent: Decimal,
    /// installation | stock
    pub purpose: String,
    /// Country the goods are delivered to (ISO alpha-2).
    pub delivery_country_code: Option<String>,
    /// The grid at the delivery country the goods are connected to.
    pub power_grid_id: Option<Uuid>,
    /// not_required | pending (shipping cost still to be quoted; sending is blocked) | quoted
    pub shipping_status: String,
    pub currency: String,
    pub quote_date: NaiveDate,
    pub price_date: NaiveDate,
    pub valid_until: NaiveDate,
    pub notes: String,
    #[schema(value_type = String)]
    pub subtotal: Decimal,
    #[schema(value_type = String)]
    pub vat_total: Decimal,
    #[schema(value_type = String)]
    pub total: Decimal,
    pub supersedes_id: Option<Uuid>,
    pub created_by: Uuid,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub sent_at: Option<DateTime<Utc>>,
    pub lines: Vec<QuotationLine>,
    pub vat_groups: Vec<VatGroup>,
    /// Hints about the lines (power grid fit, incompatible products); filled when the quotation is
    /// created or updated, empty otherwise. Never blocking.
    pub warnings: Vec<SalesWarning>,
    /// Products worth adding; filled together with `warnings`.
    pub suggestions: Vec<SalesSuggestion>,
}

impl Quotation {
    pub fn new(h: QuotationHeader, lines: Vec<QuotationLine>, vat_groups: Vec<VatGroup>) -> Self {
        Quotation {
            id: h.id,
            company_id: h.company_id,
            number: h.number,
            revision: h.revision,
            version: h.version,
            status: h.status,
            customer_id: h.customer_id,
            opportunity_id: h.opportunity_id,
            customer_name: h.customer_name,
            customer_vat_number: h.customer_vat_number,
            vat_regime: h.vat_regime,
            customer_street: h.customer_street,
            customer_postal_code: h.customer_postal_code,
            customer_city: h.customer_city,
            customer_country_code: h.customer_country_code,
            customer_language: h.customer_language,
            price_zone_code: h.price_zone_code,
            customer_discount_percent: h.customer_discount_percent,
            purpose: h.purpose,
            delivery_country_code: h.delivery_country_code,
            power_grid_id: h.power_grid_id,
            shipping_status: h.shipping_status,
            currency: h.currency,
            quote_date: h.quote_date,
            price_date: h.price_date,
            valid_until: h.valid_until,
            notes: h.notes,
            subtotal: h.subtotal,
            vat_total: h.vat_total,
            total: h.total,
            supersedes_id: h.supersedes_id,
            created_by: h.created_by,
            created_at: h.created_at,
            updated_at: h.updated_at,
            sent_at: h.sent_at,
            lines,
            vat_groups,
            warnings: Vec::new(),
            suggestions: Vec::new(),
        }
    }
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct ListParams {
    /// Searches number and customer name.
    pub q: Option<String>,
    pub status: Option<String>,
    pub customer_id: Option<Uuid>,
    pub opportunity_id: Option<Uuid>,
    pub limit: Option<i64>,
    pub offset: Option<i64>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum RevisionPricing {
    /// Keep the agreed prices, rebates and price list date of the revised quotation.
    Keep,
    /// Reprice at today's price list and rebates. Indicative prices must be confirmed again.
    Current,
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct ReviseInput {
    pub pricing: RevisionPricing,
}

/// One line of a quotation compared with today's prices.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct RepricingLine {
    pub position: i32,
    pub product_code: String,
    pub description: String,
    #[schema(value_type = String)]
    pub quantity: Decimal,
    pub pricing_type: String,
    #[schema(value_type = String)]
    pub old_list_unit_price: Decimal,
    #[schema(value_type = String)]
    pub new_list_unit_price: Decimal,
    #[schema(value_type = String)]
    pub old_rebate_percent: Decimal,
    #[schema(value_type = String)]
    pub new_rebate_percent: Decimal,
    #[schema(value_type = String)]
    pub old_line_total: Decimal,
    #[schema(value_type = String)]
    pub new_line_total: Decimal,
    #[schema(value_type = String)]
    pub difference: Decimal,
    /// The new price is an indicative suggestion that must be confirmed.
    pub needs_confirmation: bool,
}

/// What would change if a quotation were repriced at today's prices.
#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct RepricingComparison {
    pub old_price_date: NaiveDate,
    pub new_price_date: NaiveDate,
    pub lines: Vec<RepricingLine>,
    #[schema(value_type = String)]
    pub old_subtotal: Decimal,
    #[schema(value_type = String)]
    pub new_subtotal: Decimal,
    #[schema(value_type = String)]
    pub difference: Decimal,
    /// The shipping charge currently on the quotation (zero when it has none). Not part of the
    /// subtotals above, which cover product lines only. The server always sends it; the schema marks
    /// it optional so clients tolerate an older server, where an absent value means unknown.
    #[schema(value_type = String, required = false)]
    pub old_shipping_total: Decimal,
    /// True when the quotation has a shipping line or its products require a shipping quote:
    /// repricing means the shipping cost must be quoted again. The server always sends it; the schema
    /// marks it optional so clients tolerate an older server, where an absent value means unknown.
    #[schema(required = false)]
    pub shipping_requote_needed: bool,
}
