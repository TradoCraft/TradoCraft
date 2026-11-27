//! Printable price lists (ADR 0074).
//!
//! A price list is a layout: a tree of titled groups with products in it, published for one or
//! more price zones (each with its own languages) on one date. It stores no prices; they are
//! looked up in the zone prices (valid on the list's `valid_from`, through
//! [`resolve_zone_price`]) every time the list is rendered, so a list can never disagree with the
//! zone it is printed for. Export profiles select groups of any depth (with everything below them) for a file. [`assemble`] is pure and decides what is
//! printed in which order; the handlers load the data, call it and hand the result to
//! `tradocraft-documents` for PDF or Excel.

use std::cmp::Ordering;
use std::collections::{BTreeMap, HashMap, HashSet};

use axum::extract::{Path, Query, State};
use axum::http::{header, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::Json;
use chrono::NaiveDate;
use rust_decimal::prelude::ToPrimitive;
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use sqlx::types::Json as SqlJson;
use sqlx::{FromRow, PgConnection};
use tradocraft_core::company::get_company;
use tradocraft_core::error::ErrorBody;
use tradocraft_core::logo;
use tradocraft_core::{audit, new_id, AppError, AppResult, AppState, CurrentUser, Permission};
use tradocraft_documents::format_date;
use tradocraft_documents::format_unit_price;
use tradocraft_documents::price_list::{self as doc, PriceListDoc, PriceListRow, PriceListSection};
use tradocraft_pricing::{resolve_zone_price, ZonePrice};

use crate::price_list_plan::{export_plan, ExportPlanEntry, PlanExport, PlanZone, RenderFormat};
use utoipa::{IntoParams, ToSchema};
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

/// Languages a price list can be published in; the labels exist for exactly these.
pub const LANGUAGES: [&str; 5] = ["nl", "fr", "en", "de", "es"];
/// Chapter, group, sub-group, sub-sub-group.
pub const MAX_DEPTH: usize = 4;
const MAX_TEXT: usize = 300;

type Texts = BTreeMap<String, String>;

// ---------------------------------------------------------------------------------------------
// Assembly (pure)
// ---------------------------------------------------------------------------------------------

#[derive(Debug, Clone)]
pub struct AssembleGroup {
    pub id: Uuid,
    pub parent_id: Option<Uuid>,
    pub sort_order: i32,
    pub title: Texts,
    pub page_break: bool,
    /// False: the title is never printed (see `gap_mm`).
    pub show_title: bool,
    /// Vertical space in millimetres before an untitled group.
    pub gap_mm: Decimal,
}

#[derive(Debug, Clone)]
pub struct AssembleItem {
    pub group_id: Uuid,
    pub sort_key: String,
    pub product_code: String,
    /// The product's own name, last resort of the description.
    pub product_name: String,
    pub unit: String,
    /// Product name per language.
    pub translations: Texts,
    /// Description override of this item per language; wins over the translation.
    pub description: Texts,
    /// Zone price valid on the list date; `None` when the zone has none.
    pub price: Option<Decimal>,
    pub price_on_request: bool,
    pub net: bool,
    pub indicative: bool,
    pub hidden: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub struct AssembledRow {
    pub code: String,
    pub description: String,
    pub unit: String,
    /// `None` prints ON REQUEST: flagged, or a price of zero.
    pub price: Option<Decimal>,
    pub net: bool,
    pub indicative: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub struct AssembledSection {
    /// Absolute depth in the tree (0 for a top-level group).
    pub level: usize,
    /// Number of ancestors whose title is printed; styling follows this, not `level`, so hidden
    /// section or chapter nodes do not shrink the headings below them.
    pub print_level: usize,
    /// Empty when the group is untitled (`show_title` false).
    pub title: String,
    pub show_title: bool,
    pub gap_mm: Decimal,
    pub page_break: bool,
    pub rows: Vec<AssembledRow>,
}

/// The first non-empty text in the language chain, else any non-empty text, else "".
fn pick(texts: &Texts, chain: &[String]) -> Option<String> {
    chain
        .iter()
        .filter_map(|l| texts.get(l))
        .chain(texts.values())
        .map(|t| t.trim())
        .find(|t| !t.is_empty())
        .map(str::to_string)
}

/// The languages to try, in order: the requested one, the company's, then the list's own.
pub fn language_chain(
    requested: &str,
    company_default: &str,
    list_languages: &[String],
) -> Vec<String> {
    let mut chain: Vec<String> = Vec::new();
    for l in [requested, company_default]
        .into_iter()
        .chain(list_languages.iter().map(String::as_str))
    {
        if !l.is_empty() && !chain.iter().any(|c| c == l) {
            chain.push(l.to_string());
        }
    }
    chain
}

/// Orders dotted sort keys segment by segment: numbers numerically (`1.2` before `1.10`) and
/// before text, text case-insensitively; a key before the keys it is a prefix of.
pub fn sort_key_cmp(a: &str, b: &str) -> Ordering {
    let seg = |s: &str, i: usize| -> Option<String> { s.split('.').nth(i).map(str::to_string) };
    if a.is_empty() || b.is_empty() {
        return a.is_empty().cmp(&b.is_empty()).reverse();
    }
    let n = a.split('.').count().max(b.split('.').count());
    for i in 0..n {
        let (x, y) = match (seg(a, i), seg(b, i)) {
            (Some(x), Some(y)) => (x, y),
            (None, Some(_)) => return Ordering::Less,
            (Some(_), None) => return Ordering::Greater,
            (None, None) => break,
        };
        let o = match (x.parse::<u64>(), y.parse::<u64>()) {
            (Ok(p), Ok(q)) => p.cmp(&q),
            (Ok(_), Err(_)) => Ordering::Less,
            (Err(_), Ok(_)) => Ordering::Greater,
            (Err(_), Err(_)) => x.to_lowercase().cmp(&y.to_lowercase()).then(x.cmp(&y)),
        };
        if o != Ordering::Equal {
            return o;
        }
    }
    Ordering::Equal
}

/// Builds the printable structure: groups by `sort_order`, items by sort key then product code,
/// groups without any printable item (in themselves or below) left out. An item is printed when
/// it is not hidden and either has a zone price or is flagged price-on-request; a price of zero
/// prints as ON REQUEST like the flag does. Text falls back along `chain`.
pub fn assemble(
    groups: &[AssembleGroup],
    items: &[AssembleItem],
    chain: &[String],
) -> Vec<AssembledSection> {
    let mut children: HashMap<Option<Uuid>, Vec<&AssembleGroup>> = HashMap::new();
    for g in groups {
        children.entry(g.parent_id).or_default().push(g);
    }
    for list in children.values_mut() {
        list.sort_by(|a, b| {
            a.sort_order
                .cmp(&b.sort_order)
                .then_with(|| pick(&a.title, chain).cmp(&pick(&b.title, chain)))
                .then(a.id.cmp(&b.id))
        });
    }
    let mut by_group: HashMap<Uuid, Vec<&AssembleItem>> = HashMap::new();
    for i in items {
        if !i.hidden && (i.price_on_request || i.price.is_some()) {
            by_group.entry(i.group_id).or_default().push(i);
        }
    }
    for list in by_group.values_mut() {
        list.sort_by(|a, b| {
            sort_key_cmp(&a.sort_key, &b.sort_key).then_with(|| a.product_code.cmp(&b.product_code))
        });
    }

    fn walk(
        parent: Option<Uuid>,
        level: usize,
        print_level: usize,
        children: &HashMap<Option<Uuid>, Vec<&AssembleGroup>>,
        by_group: &HashMap<Uuid, Vec<&AssembleItem>>,
        chain: &[String],
        out: &mut Vec<AssembledSection>,
    ) {
        if level >= 2 * MAX_DEPTH {
            return;
        }
        for g in children.get(&parent).into_iter().flatten() {
            let rows: Vec<AssembledRow> = by_group
                .get(&g.id)
                .into_iter()
                .flatten()
                .map(|i| {
                    let on_request =
                        i.price_on_request || i.price.is_none_or(|p| p <= Decimal::ZERO);
                    AssembledRow {
                        code: i.product_code.clone(),
                        description: chain
                            .iter()
                            .find_map(|l| {
                                i.description
                                    .get(l)
                                    .filter(|t| !t.trim().is_empty())
                                    .or_else(|| {
                                        i.translations.get(l).filter(|t| !t.trim().is_empty())
                                    })
                            })
                            .map(|t| t.trim().to_string())
                            .unwrap_or_else(|| i.product_name.clone()),
                        unit: i.unit.clone(),
                        price: if on_request { None } else { i.price },
                        net: !on_request && i.net,
                        indicative: !on_request && i.indicative,
                    }
                })
                .collect();
            let at = out.len();
            out.push(AssembledSection {
                level,
                print_level,
                title: if g.show_title {
                    pick(&g.title, chain).unwrap_or_default()
                } else {
                    String::new()
                },
                show_title: g.show_title,
                gap_mm: g.gap_mm,
                page_break: g.page_break,
                rows,
            });
            walk(
                Some(g.id),
                level + 1,
                print_level + usize::from(g.show_title),
                children,
                by_group,
                chain,
                out,
            );
            if out.len() == at + 1 && out[at].rows.is_empty() {
                out.pop();
            }
        }
    }
    let mut out = Vec::new();
    walk(None, 0, 0, &children, &by_group, chain, &mut out);
    out
}

/// The groups an export profile prints: every chosen group (of any depth) with all its
/// descendants. A group is kept when it or any ancestor is chosen, so overlapping selections are
/// printed once. An empty `chosen` is the whole list. The result keeps the order of `groups` and
/// [`assemble`] orders by `sort_order`, so a profile never reorders the list: print order is tree
/// order, not selection order.
pub fn select_groups(groups: &[AssembleGroup], chosen: &[Uuid]) -> Vec<AssembleGroup> {
    if chosen.is_empty() {
        return groups.to_vec();
    }
    let parents: HashMap<Uuid, Option<Uuid>> = groups.iter().map(|g| (g.id, g.parent_id)).collect();
    let chosen: HashSet<Uuid> = chosen.iter().copied().collect();
    let kept: HashSet<Uuid> = groups
        .iter()
        .filter(|g| {
            let mut cursor = Some(g.id);
            // The tree is validated acyclic; the step cap only guards against corrupt data.
            for _ in 0..=groups.len() {
                let Some(id) = cursor else { return false };
                if chosen.contains(&id) {
                    return true;
                }
                cursor = parents.get(&id).copied().flatten();
            }
            false
        })
        .map(|g| g.id)
        .collect();
    groups
        .iter()
        .filter(|g| kept.contains(&g.id))
        .map(|g| {
            let mut g = g.clone();
            // The parent of a selected group is not printed: it becomes a root of the selection.
            if g.parent_id.is_some_and(|p| !kept.contains(&p)) {
                g.parent_id = None;
            }
            g
        })
        .collect()
}

/// Checks the groups of an export profile: no duplicates, all of them groups of the list.
/// `all` are the ids of the list's groups.
pub fn check_export_groups(all: &HashSet<Uuid>, ids: &[Uuid]) -> Result<(), &'static str> {
    let unique: HashSet<&Uuid> = ids.iter().collect();
    if unique.len() != ids.len() {
        return Err("group_ids contains a group twice");
    }
    if ids.iter().any(|id| !all.contains(id)) {
        return Err("group_ids must be groups of this price list");
    }
    Ok(())
}

/// `(id, parent_id, sort_order, titles)` of a group.
pub type GroupTitles = (Uuid, Option<Uuid>, i32, Texts);

/// The groups at 1-based `depth` (1 = top level) as `(id, title)`, in tree order (siblings by
/// `sort_order` then id, parents before their children). `groups` are
/// `(id, parent_id, sort_order, title)`.
pub fn groups_at_depth(groups: &[GroupTitles], depth: usize) -> Vec<(Uuid, Texts)> {
    let mut children: HashMap<Option<Uuid>, Vec<&GroupTitles>> = HashMap::new();
    for g in groups {
        children.entry(g.1).or_default().push(g);
    }
    for list in children.values_mut() {
        list.sort_by_key(|g| (g.2, g.0));
    }
    let mut level: Vec<Option<Uuid>> = vec![None];
    for _ in 1..depth {
        level = level
            .iter()
            .flat_map(|p| children.get(p).into_iter().flatten().map(|g| Some(g.0)))
            .collect();
    }
    level
        .iter()
        .flat_map(|p| children.get(p).into_iter().flatten())
        .map(|g| (g.0, g.3.clone()))
        .collect()
}

/// Validates the position of a group in the tree. `groups` are `(id, parent_id)` of the list as
/// stored; `id` is the group being changed (`None` for a new one). Rejects a parent outside the
/// list, a group below itself or its own descendant, and a tree deeper than [`MAX_DEPTH`].
pub fn check_position(
    groups: &[(Uuid, Option<Uuid>)],
    id: Option<Uuid>,
    parent: Option<Uuid>,
) -> Result<(), &'static str> {
    let parents: HashMap<Uuid, Option<Uuid>> = groups.iter().copied().collect();
    let mut depth = 1; // the group itself
    let mut cursor = parent;
    while let Some(p) = cursor {
        if Some(p) == id {
            return Err("a group cannot be placed below itself");
        }
        let Some(next) = parents.get(&p) else {
            return Err("the parent group does not belong to this price list");
        };
        depth += 1;
        if depth > MAX_DEPTH {
            return Err("groups can be nested at most four levels deep");
        }
        cursor = *next;
    }
    // Height of the subtree that moves along.
    if let Some(id) = id {
        let mut height = 1;
        let mut level = vec![id];
        while !level.is_empty() {
            level = groups
                .iter()
                .filter(|(_, p)| p.is_some_and(|p| level.contains(&p)))
                .map(|(g, _)| *g)
                .collect();
            if !level.is_empty() {
                height += 1;
            }
            if height > MAX_DEPTH + 1 {
                break;
            }
        }
        if depth + height - 1 > MAX_DEPTH {
            return Err("groups can be nested at most four levels deep");
        }
    }
    Ok(())
}

// ---------------------------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------------------------

/// Presentation of a list. No row means defaults apply to every key.
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
#[serde(default, deny_unknown_fields)]
pub struct PriceListSettings {
    /// Printed in the page footer after the company name.
    pub footer_text: String,
    /// Printed before prices; empty uses the company currency (EUR as the euro sign).
    pub currency_symbol: String,
    /// Colour of the title and chapter headings, `#rrggbb`.
    pub accent_color: String,
    /// Show the unit column.
    pub show_unit: bool,
    /// Print the company logo in the PDF header when one is uploaded.
    pub show_logo: bool,
    /// Import of the items (ADR 0100): how many leading segments of a `position` name the group
    /// path (each the `sort_order` of a group among its siblings); the rest is the item's sort
    /// key. 1 to 4, default 2.
    pub import_group_levels: u8,
    /// Import of the items: which title a group gets when its rows disagree.
    pub import_title_conflict: ImportTitleConflict,
    /// Import of the items: what a position with fewer segments than `import_group_levels` means.
    pub import_short_position: ImportShortPosition,
}

/// How an import picks a group's title in one language when its rows hold different ones.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum ImportTitleConflict {
    /// The row with the lowest position (compared segment by segment) wins.
    #[default]
    LowestPosition,
    /// The first row of the file wins.
    FirstRow,
    /// Different titles are row errors.
    Error,
}

/// What an import does with a position that names fewer groups than the list's group levels.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum ImportShortPosition {
    /// The item goes into the (shallower) group the position names, with an empty sort key.
    #[default]
    ShallowerGroup,
    /// The row is an error.
    Error,
}

impl Default for PriceListSettings {
    fn default() -> Self {
        Self {
            footer_text: String::new(),
            currency_symbol: String::new(),
            accent_color: "#1f4e79".into(),
            show_unit: true,
            show_logo: true,
            import_group_levels: 2,
            import_title_conflict: ImportTitleConflict::default(),
            import_short_position: ImportShortPosition::default(),
        }
    }
}

impl PriceListSettings {
    fn validate(&mut self) -> AppResult<()> {
        self.footer_text = self.footer_text.trim().to_string();
        self.currency_symbol = self.currency_symbol.trim().to_string();
        self.accent_color = self.accent_color.trim().to_string();
        let hex = self.accent_color.strip_prefix('#').unwrap_or("");
        if hex.len() != 6 || !hex.chars().all(|c| c.is_ascii_hexdigit()) {
            return Err(AppError::Validation(
                "accent_color must look like #1f4e79".into(),
            ));
        }
        if !(1..=MAX_DEPTH).contains(&usize::from(self.import_group_levels)) {
            return Err(AppError::Validation(format!(
                "import_group_levels must be between 1 and {MAX_DEPTH}"
            )));
        }
        if self.footer_text.chars().count() > 200 || self.currency_symbol.chars().count() > 8 {
            return Err(AppError::Validation(
                "footer_text (200) or currency_symbol (8) is too long".into(),
            ));
        }
        Ok(())
    }
}

/// A zone a list is published for.
#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct PriceListZone {
    pub price_zone_id: Uuid,
    pub price_zone_code: String,
    pub price_zone_name: String,
    /// Languages published for this zone; the first is the default.
    pub languages: Vec<String>,
    pub sort_order: i32,
}

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct PriceList {
    pub id: Uuid,
    pub code: String,
    pub name: String,
    /// Zones in print order. Prices are those valid on `valid_from` in each zone.
    #[schema(value_type = Vec<PriceListZone>)]
    pub zones: SqlJson<Vec<PriceListZone>>,
    pub valid_from: NaiveDate,
    #[schema(value_type = PriceListSettings)]
    pub settings: SqlJson<PriceListSettings>,
    pub item_count: i64,
}

const SELECT_LIST: &str = "SELECT l.id, l.code, l.name, l.valid_from, l.settings,
        COALESCE((SELECT jsonb_agg(jsonb_build_object(
                'price_zone_id', lz.price_zone_id, 'price_zone_code', z.code,
                'price_zone_name', z.name,
                'languages', COALESCE((SELECT jsonb_agg(zl.language::text ORDER BY zl.sort_order)
                    FROM pricing.price_list_zone_languages zl
                    WHERE zl.price_list_zone_id = lz.id), '[]'::jsonb),
                'sort_order', lz.sort_order)
                ORDER BY lz.sort_order, z.code)
            FROM pricing.price_list_zones lz JOIN pricing.price_zones z ON z.id = lz.price_zone_id
            WHERE lz.price_list_id = l.id), '[]'::jsonb) AS zones,
        (SELECT count(*) FROM pricing.price_list_items i WHERE i.price_list_id = l.id) AS item_count
     FROM pricing.price_lists l";

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct PriceListInput {
    pub code: String,
    pub name: String,
    /// Accepts `2027-01-01` and the datetime string the Dart client sends.
    #[serde(deserialize_with = "tradocraft_core::serde_util::date")]
    pub valid_from: NaiveDate,
    #[serde(default)]
    pub settings: PriceListSettings,
}

/// Normalises and checks a language list: non-empty, no duplicates, only [`LANGUAGES`].
fn clean_languages(languages: &[String]) -> AppResult<Vec<String>> {
    let languages: Vec<String> = languages.iter().map(|l| l.trim().to_lowercase()).collect();
    let unique: HashSet<&String> = languages.iter().collect();
    if languages.is_empty()
        || unique.len() != languages.len()
        || !languages.iter().all(|l| LANGUAGES.contains(&l.as_str()))
    {
        return Err(AppError::Validation(format!(
            "languages must be a non-empty list without duplicates from {}",
            LANGUAGES.join(", ")
        )));
    }
    Ok(languages)
}

impl PriceListInput {
    fn validate(&mut self) -> AppResult<()> {
        self.code = self.code.trim().to_string();
        self.name = self.name.trim().to_string();
        if self.code.is_empty() || self.code.chars().count() > 32 {
            return Err(AppError::Validation(
                "code is required (at most 32 characters)".into(),
            ));
        }
        if self.name.is_empty() {
            return Err(AppError::Validation("name is required".into()));
        }
        self.settings.validate()
    }
}

/// One zone of a list; the position in the request is the print order.
#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct PriceListZoneInput {
    pub price_zone_id: Uuid,
    /// Subset of nl, fr, en, de, es; the first is the default.
    pub languages: Vec<String>,
}

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct PriceListGroup {
    pub id: Uuid,
    pub parent_id: Option<Uuid>,
    pub sort_order: i32,
    /// Title per language code.
    #[schema(value_type = BTreeMap<String, String>)]
    pub title: SqlJson<Texts>,
    /// Start a new page before this group (any level; not before the first printed content).
    pub page_break: bool,
    /// False: the title is kept for the editor but never printed.
    pub show_title: bool,
    /// Millimetres of space before an untitled group (0 to 50), always two decimals.
    #[schema(value_type = String)]
    #[serde(serialize_with = "serialize_gap")]
    pub gap_mm: Decimal,
}

/// Postgres returns `numeric(5,2)` zero without its scale; keep the output at two decimals.
fn serialize_gap<S: serde::Serializer>(gap: &Decimal, s: S) -> Result<S::Ok, S::Error> {
    let mut gap = *gap;
    gap.rescale(2);
    s.serialize_str(&gap.to_string())
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct PriceListGroupInput {
    #[serde(default)]
    pub parent_id: Option<Uuid>,
    #[serde(default)]
    pub sort_order: i32,
    /// Title per language code (nl, fr, en, de, es); at least one.
    pub title: BTreeMap<String, String>,
    #[serde(default)]
    pub page_break: bool,
    /// Print the title (default true). When false the title is only for the editor.
    #[serde(default = "default_true")]
    pub show_title: bool,
    /// Millimetres of space before the group when its title is not printed, 0 to 50 (default 0).
    #[serde(default)]
    #[schema(value_type = Option<String>)]
    pub gap_mm: Decimal,
}

fn default_true() -> bool {
    true
}

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct PriceListItem {
    pub id: Uuid,
    pub product_id: Uuid,
    pub product_code: String,
    pub product_name: String,
    pub group_id: Uuid,
    /// Dotted position inside the group, e.g. `2.10`.
    pub sort_key: String,
    pub price_on_request: bool,
    pub net: bool,
    pub indicative: bool,
    pub hidden: bool,
    /// Replaces the product name in that language.
    #[schema(value_type = BTreeMap<String, String>)]
    pub description: SqlJson<Texts>,
}

const SELECT_ITEM: &str =
    "SELECT i.id, i.product_id, p.code AS product_code, p.name AS product_name,
        i.group_id, i.sort_key, i.price_on_request, i.net, i.indicative, i.hidden,
        COALESCE((SELECT jsonb_object_agg(d.language::text, d.description)
                  FROM pricing.price_list_item_descriptions d WHERE d.item_id = i.id), '{}'::jsonb) AS description
     FROM pricing.price_list_items i JOIN products.products p ON p.id = i.product_id";

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct PriceListItemInput {
    pub product_id: Uuid,
    pub group_id: Uuid,
    #[serde(default)]
    pub sort_key: String,
    #[serde(default)]
    pub price_on_request: bool,
    #[serde(default)]
    pub net: bool,
    #[serde(default)]
    pub indicative: bool,
    #[serde(default)]
    pub hidden: bool,
    #[serde(default)]
    pub description: BTreeMap<String, String>,
}

/// Change of an item; the product of an item never changes (remove and add instead).
#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct PriceListItemUpdate {
    pub group_id: Uuid,
    #[serde(default)]
    pub sort_key: String,
    #[serde(default)]
    pub price_on_request: bool,
    #[serde(default)]
    pub net: bool,
    #[serde(default)]
    pub indicative: bool,
    #[serde(default)]
    pub hidden: bool,
    #[serde(default)]
    pub description: BTreeMap<String, String>,
}

/// Trims a language-to-text map, rejecting bad language codes and over-long texts; empty texts
/// are dropped.
fn clean_texts(what: &str, texts: &BTreeMap<String, String>) -> AppResult<Texts> {
    let mut out = Texts::new();
    for (lang, text) in texts {
        let lang = lang.trim().to_lowercase();
        let text = text.trim();
        if lang.len() != 2 || !lang.chars().all(|c| c.is_ascii_lowercase()) {
            return Err(AppError::Validation(format!(
                "{what}: '{lang}' is not a 2-letter language code"
            )));
        }
        if text.chars().count() > MAX_TEXT {
            return Err(AppError::Validation(format!(
                "{what} in '{lang}' is longer than {MAX_TEXT} characters"
            )));
        }
        if !text.is_empty() {
            out.insert(lang, text.to_string());
        }
    }
    Ok(out)
}

fn clean_sort_key(key: &str) -> AppResult<String> {
    let key = key.trim();
    let ok = key.is_empty()
        || key
            .split('.')
            .all(|s| !s.is_empty() && s.chars().all(|c| c.is_ascii_alphanumeric()));
    if !ok || key.len() > 64 {
        return Err(AppError::Validation(
            "sort_key must be dotted letters and digits, e.g. 2.10.3".into(),
        ));
    }
    Ok(key.to_string())
}

// ---------------------------------------------------------------------------------------------
// Persistence helpers
// ---------------------------------------------------------------------------------------------

fn code_taken() -> AppError {
    AppError::Conflict("a price list with this code already exists".into())
}

async fn load_list(db: &mut PgConnection, company_id: Uuid, id: Uuid) -> AppResult<PriceList> {
    sqlx::query_as(sqlx::AssertSqlSafe(format!(
        "{SELECT_LIST} WHERE l.id = $1 AND l.company_id = $2"
    )))
    .bind(id)
    .bind(company_id)
    .fetch_optional(db)
    .await?
    .ok_or(AppError::NotFound("price list"))
}

/// Locks the list row, which serialises edits of its tree, and proves it is in the company.
async fn lock_list(db: &mut PgConnection, company_id: Uuid, id: Uuid) -> AppResult<()> {
    sqlx::query_scalar::<_, Uuid>(
        "SELECT id FROM pricing.price_lists WHERE id = $1 AND company_id = $2 FOR UPDATE",
    )
    .bind(id)
    .bind(company_id)
    .fetch_optional(db)
    .await?
    .map(|_| ())
    .ok_or(AppError::NotFound("price list"))
}

async fn touch(db: &mut PgConnection, id: Uuid) -> AppResult<()> {
    sqlx::query("UPDATE pricing.price_lists SET updated_at = now() WHERE id = $1")
        .bind(id)
        .execute(db)
        .await?;
    Ok(())
}

// ---------------------------------------------------------------------------------------------
// Lists
// ---------------------------------------------------------------------------------------------

#[utoipa::path(get, path = "/price-lists", tag = "products",
    responses((status = 200, body = Vec<PriceList>)))]
async fn list_price_lists(
    State(state): State<AppState>,
    user: CurrentUser,
) -> AppResult<Json<Vec<PriceList>>> {
    user.require(Permission::PriceListsRead)?;
    Ok(Json(
        sqlx::query_as(sqlx::AssertSqlSafe(format!(
            "{SELECT_LIST} WHERE l.company_id = $1 ORDER BY l.code"
        )))
        .bind(user.company_id)
        .fetch_all(&state.db)
        .await?,
    ))
}

#[utoipa::path(get, path = "/price-lists/{id}", tag = "products", params(("id" = Uuid, Path)),
    responses((status = 200, body = PriceList), (status = 404, body = ErrorBody)))]
async fn get_price_list(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<PriceList>> {
    user.require(Permission::PriceListsRead)?;
    let mut conn = state.db.acquire().await?;
    Ok(Json(load_list(&mut conn, user.company_id, id).await?))
}

#[utoipa::path(post, path = "/price-lists", tag = "products", request_body = PriceListInput,
    responses((status = 201, body = PriceList), (status = 409, body = ErrorBody),
        (status = 422, body = ErrorBody)))]
async fn create_price_list(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(mut input): Json<PriceListInput>,
) -> AppResult<(StatusCode, Json<PriceList>)> {
    user.require(Permission::PriceListsWrite)?;
    input.validate()?;
    let id = new_id();
    let mut tx = state.db.begin().await?;
    sqlx::query_scalar::<_, Uuid>(
        "INSERT INTO pricing.price_lists (id, company_id, code, name, valid_from, settings)
         VALUES ($1, $2, $3, $4, $5, $6)
         ON CONFLICT (company_id, code) DO NOTHING RETURNING id",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(&input.code)
    .bind(&input.name)
    .bind(input.valid_from)
    .bind(SqlJson(&input.settings))
    .fetch_optional(&mut *tx)
    .await?
    .ok_or_else(code_taken)?;
    audit::record(
        &mut tx,
        &user,
        "price_list",
        id,
        "created",
        serde_json::json!({ "code": input.code }),
    )
    .await?;
    let list = load_list(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(list)))
}

#[utoipa::path(put, path = "/price-lists/{id}", tag = "products", params(("id" = Uuid, Path)),
    request_body = PriceListInput,
    responses((status = 200, body = PriceList), (status = 404, body = ErrorBody),
        (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn update_price_list(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(mut input): Json<PriceListInput>,
) -> AppResult<Json<PriceList>> {
    user.require(Permission::PriceListsWrite)?;
    input.validate()?;
    let mut tx = state.db.begin().await?;
    lock_list(&mut tx, user.company_id, id).await?;
    let taken: bool = sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM pricing.price_lists WHERE company_id = $1 AND code = $2 AND id <> $3)",
    )
    .bind(user.company_id)
    .bind(&input.code)
    .bind(id)
    .fetch_one(&mut *tx)
    .await?;
    if taken {
        return Err(code_taken());
    }
    sqlx::query(
        "UPDATE pricing.price_lists SET code = $2, name = $3, valid_from = $4, settings = $5,
                updated_at = now() WHERE id = $1",
    )
    .bind(id)
    .bind(&input.code)
    .bind(&input.name)
    .bind(input.valid_from)
    .bind(SqlJson(&input.settings))
    .execute(&mut *tx)
    .await?;
    audit::record(
        &mut tx,
        &user,
        "price_list",
        id,
        "updated",
        serde_json::json!({ "code": input.code }),
    )
    .await?;
    let list = load_list(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok(Json(list))
}

/// Deletes a price list with its zones, groups, items and export profiles. The products and prices are untouched.
#[utoipa::path(delete, path = "/price-lists/{id}", tag = "products", params(("id" = Uuid, Path)),
    responses((status = 204), (status = 404, body = ErrorBody)))]
async fn delete_price_list(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<StatusCode> {
    user.require(Permission::PriceListsWrite)?;
    let mut tx = state.db.begin().await?;
    lock_list(&mut tx, user.company_id, id).await?;
    let code: String = sqlx::query_scalar("SELECT code FROM pricing.price_lists WHERE id = $1")
        .bind(id)
        .fetch_one(&mut *tx)
        .await?;
    sqlx::query("DELETE FROM pricing.price_lists WHERE id = $1")
        .bind(id)
        .execute(&mut *tx)
        .await?;
    audit::record(
        &mut tx,
        &user,
        "price_list",
        id,
        "deleted",
        serde_json::json!({ "code": code }),
    )
    .await?;
    tx.commit().await?;
    Ok(StatusCode::NO_CONTENT)
}

// ---------------------------------------------------------------------------------------------
// Zones
// ---------------------------------------------------------------------------------------------

/// Replaces the zones of a list (and with them the languages published per zone). The order of
/// the request is the print order. An empty array leaves a list that cannot be rendered.
#[utoipa::path(put, path = "/price-lists/{id}/zones", tag = "products", params(("id" = Uuid, Path)),
    request_body = Vec<PriceListZoneInput>,
    responses((status = 200, body = PriceList), (status = 404, body = ErrorBody),
        (status = 422, body = ErrorBody)))]
async fn replace_zones(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<Vec<PriceListZoneInput>>,
) -> AppResult<Json<PriceList>> {
    user.require(Permission::PriceListsWrite)?;
    let mut zones = Vec::new();
    let mut seen = HashSet::new();
    for z in &input {
        if !seen.insert(z.price_zone_id) {
            return Err(AppError::Validation(
                "a price zone can be listed only once".into(),
            ));
        }
        zones.push((z.price_zone_id, clean_languages(&z.languages)?));
    }
    let mut tx = state.db.begin().await?;
    lock_list(&mut tx, user.company_id, id).await?;
    let ids: Vec<Uuid> = zones.iter().map(|(z, _)| *z).collect();
    let known: i64 = sqlx::query_scalar(
        "SELECT count(*) FROM pricing.price_zones WHERE company_id = $1 AND id = ANY($2)",
    )
    .bind(user.company_id)
    .bind(&ids)
    .fetch_one(&mut *tx)
    .await?;
    if known != ids.len() as i64 {
        return Err(AppError::Validation(
            "a price zone does not belong to the active company".into(),
        ));
    }
    sqlx::query("DELETE FROM pricing.price_list_zones WHERE price_list_id = $1")
        .bind(id)
        .execute(&mut *tx)
        .await?;
    for (i, (zone_id, languages)) in zones.iter().enumerate() {
        let row_id = new_id();
        sqlx::query(
            "INSERT INTO pricing.price_list_zones (id, company_id, price_list_id, price_zone_id, sort_order)
             VALUES ($1, $2, $3, $4, $5)",
        )
        .bind(row_id)
        .bind(user.company_id)
        .bind(id)
        .bind(zone_id)
        .bind(i as i32)
        .execute(&mut *tx)
        .await?;
        // The zone needs one language at commit (deferred constraint trigger); the API has
        // already rejected an empty list.
        let orders: Vec<i32> = (0..languages.len() as i32).collect();
        sqlx::query(
            "INSERT INTO pricing.price_list_zone_languages (price_list_zone_id, company_id, language, sort_order)
             SELECT $1, $2, l, o FROM unnest($3::text[], $4::int[]) AS t(l, o)",
        )
        .bind(row_id)
        .bind(user.company_id)
        .bind(languages)
        .bind(&orders)
        .execute(&mut *tx)
        .await?;
    }
    touch(&mut tx, id).await?;
    audit::record(
        &mut tx,
        &user,
        "price_list",
        id,
        "zones_replaced",
        serde_json::json!({ "zones": ids }),
    )
    .await?;
    let list = load_list(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok(Json(list))
}

// ---------------------------------------------------------------------------------------------
// Groups
// ---------------------------------------------------------------------------------------------

/// The title map is rebuilt from `price_list_group_titles`.
const SELECT_GROUP: &str = "SELECT g.id, g.parent_id, g.sort_order,
        COALESCE((SELECT jsonb_object_agg(t.language::text, t.title)
                  FROM pricing.price_list_group_titles t WHERE t.group_id = g.id), '{}'::jsonb) AS title,
        g.page_break, g.show_title, g.gap_mm
     FROM pricing.price_list_groups g";

/// Replaces the per-language texts of one owner (group title or item description). `table` and
/// `column` are fixed identifiers of this module, never user input.
async fn replace_texts(
    db: &mut PgConnection,
    (table, key, column): (&str, &str, &str),
    company_id: Uuid,
    owner: Uuid,
    texts: &Texts,
) -> AppResult<()> {
    sqlx::query(sqlx::AssertSqlSafe(format!(
        "DELETE FROM pricing.{table} WHERE {key} = $1"
    )))
    .bind(owner)
    .execute(&mut *db)
    .await?;
    if texts.is_empty() {
        return Ok(());
    }
    let langs: Vec<&str> = texts.keys().map(String::as_str).collect();
    let values: Vec<&str> = texts.values().map(String::as_str).collect();
    sqlx::query(sqlx::AssertSqlSafe(format!(
        "INSERT INTO pricing.{table} ({key}, company_id, language, {column})
         SELECT $1, $2, l, v FROM unnest($3::text[], $4::text[]) AS t(l, v)"
    )))
    .bind(owner)
    .bind(company_id)
    .bind(&langs)
    .bind(&values)
    .execute(db)
    .await?;
    Ok(())
}

const GROUP_TITLES: (&str, &str, &str) = ("price_list_group_titles", "group_id", "title");
const ITEM_DESCRIPTIONS: (&str, &str, &str) =
    ("price_list_item_descriptions", "item_id", "description");

async fn load_group(db: &mut PgConnection, group_id: Uuid) -> AppResult<PriceListGroup> {
    sqlx::query_as(sqlx::AssertSqlSafe(format!(
        "{SELECT_GROUP} WHERE g.id = $1"
    )))
    .bind(group_id)
    .fetch_optional(db)
    .await?
    .ok_or(AppError::NotFound("price list group"))
}

#[utoipa::path(get, path = "/price-lists/{id}/groups", tag = "products", params(("id" = Uuid, Path)),
    responses((status = 200, body = Vec<PriceListGroup>), (status = 404, body = ErrorBody)))]
async fn list_groups(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<Vec<PriceListGroup>>> {
    user.require(Permission::PriceListsRead)?;
    let mut conn = state.db.acquire().await?;
    load_list(&mut conn, user.company_id, id).await?;
    Ok(Json(
        sqlx::query_as(sqlx::AssertSqlSafe(format!(
            "{SELECT_GROUP} WHERE g.price_list_id = $1 ORDER BY g.parent_id NULLS FIRST, g.sort_order, g.id"
        )))
        .bind(id)
        .fetch_all(&mut *conn)
        .await?,
    ))
}

/// The gap before an untitled group: 0 to 50 mm, at most two decimals.
fn check_gap(gap_mm: Decimal) -> AppResult<()> {
    if gap_mm < Decimal::ZERO || gap_mm > Decimal::from(50) || gap_mm.round_dp(2) != gap_mm {
        return Err(AppError::Validation(
            "gap_mm must be between 0 and 50 with at most two decimals".into(),
        ));
    }
    Ok(())
}

/// Refuses (409) a change to a group that an export profile of the list selects.
async fn ensure_not_in_export(
    db: &mut PgConnection,
    list_id: Uuid,
    group_id: Uuid,
    what: &str,
) -> AppResult<()> {
    let codes: Vec<String> = sqlx::query_scalar(
        "SELECT e.code FROM pricing.price_list_exports e
         JOIN pricing.price_list_export_groups eg ON eg.export_id = e.id
         WHERE eg.price_list_id = $1 AND eg.group_id = $2 ORDER BY e.code",
    )
    .bind(list_id)
    .bind(group_id)
    .fetch_all(db)
    .await?;
    if codes.is_empty() {
        Ok(())
    } else {
        Err(AppError::Conflict(format!(
            "the group cannot be {what}: export profile(s) {} use it",
            codes.join(", ")
        )))
    }
}

/// Validates a group body against the stored tree; `group` is the group being changed.
async fn validate_group(
    tx: &mut PgConnection,
    list_id: Uuid,
    group: Option<Uuid>,
    input: &PriceListGroupInput,
) -> AppResult<Texts> {
    let title = clean_texts("title", &input.title)?;
    check_gap(input.gap_mm)?;
    if title.is_empty() {
        return Err(AppError::Validation(
            "a group needs a title in at least one language".into(),
        ));
    }
    let tree: Vec<(Uuid, Option<Uuid>)> = sqlx::query_as(
        "SELECT id, parent_id FROM pricing.price_list_groups WHERE price_list_id = $1",
    )
    .bind(list_id)
    .fetch_all(tx)
    .await?;
    check_position(&tree, group, input.parent_id).map_err(|m| AppError::Validation(m.into()))?;
    Ok(title)
}

#[utoipa::path(post, path = "/price-lists/{id}/groups", tag = "products", params(("id" = Uuid, Path)),
    request_body = PriceListGroupInput,
    responses((status = 201, body = PriceListGroup), (status = 404, body = ErrorBody),
        (status = 422, body = ErrorBody)))]
async fn create_group(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<PriceListGroupInput>,
) -> AppResult<(StatusCode, Json<PriceListGroup>)> {
    user.require(Permission::PriceListsWrite)?;
    let mut tx = state.db.begin().await?;
    lock_list(&mut tx, user.company_id, id).await?;
    let title = validate_group(&mut tx, id, None, &input).await?;
    let gid = new_id();
    sqlx::query(
        "INSERT INTO pricing.price_list_groups (id, company_id, price_list_id, parent_id, sort_order, page_break, show_title, gap_mm)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)",
    )
    .bind(gid)
    .bind(user.company_id)
    .bind(id)
    .bind(input.parent_id)
    .bind(input.sort_order)
    .bind(input.page_break)
    .bind(input.show_title)
    .bind(input.gap_mm)
    .execute(&mut *tx)
    .await?;
    replace_texts(&mut tx, GROUP_TITLES, user.company_id, gid, &title).await?;
    let group = load_group(&mut tx, gid).await?;
    touch(&mut tx, id).await?;
    audit::record(
        &mut tx,
        &user,
        "price_list",
        id,
        "group_created",
        serde_json::json!({ "group_id": gid, "title": title }),
    )
    .await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(group)))
}

#[utoipa::path(put, path = "/price-lists/{id}/groups/{group_id}", tag = "products",
    params(("id" = Uuid, Path), ("group_id" = Uuid, Path)), request_body = PriceListGroupInput,
    responses((status = 200, body = PriceListGroup), (status = 404, body = ErrorBody),
        (status = 422, body = ErrorBody)))]
async fn update_group(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((id, group_id)): Path<(Uuid, Uuid)>,
    Json(input): Json<PriceListGroupInput>,
) -> AppResult<Json<PriceListGroup>> {
    user.require(Permission::PriceListsWrite)?;
    let mut tx = state.db.begin().await?;
    lock_list(&mut tx, user.company_id, id).await?;
    let title = validate_group(&mut tx, id, Some(group_id), &input).await?;
    let updated = sqlx::query(
        "UPDATE pricing.price_list_groups SET parent_id = $3, sort_order = $4, page_break = $5, show_title = $6, gap_mm = $7
         WHERE id = $1 AND price_list_id = $2",
    )
    .bind(group_id)
    .bind(id)
    .bind(input.parent_id)
    .bind(input.sort_order)
    .bind(input.page_break)
    .bind(input.show_title)
    .bind(input.gap_mm)
    .execute(&mut *tx)
    .await?
    .rows_affected();
    if updated == 0 {
        return Err(AppError::NotFound("price list group"));
    }
    replace_texts(&mut tx, GROUP_TITLES, user.company_id, group_id, &title).await?;
    let group = load_group(&mut tx, group_id).await?;
    touch(&mut tx, id).await?;
    audit::record(
        &mut tx,
        &user,
        "price_list",
        id,
        "group_updated",
        serde_json::json!({ "group_id": group_id }),
    )
    .await?;
    tx.commit().await?;
    Ok(Json(group))
}

/// Deletes an empty group: refused (409) while it has sub-groups or items, or while an export
/// profile still uses it (remove it from the profile first).
#[utoipa::path(delete, path = "/price-lists/{id}/groups/{group_id}", tag = "products",
    params(("id" = Uuid, Path), ("group_id" = Uuid, Path)),
    responses((status = 204), (status = 404, body = ErrorBody), (status = 409, body = ErrorBody)))]
async fn delete_group(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((id, group_id)): Path<(Uuid, Uuid)>,
) -> AppResult<StatusCode> {
    user.require(Permission::PriceListsWrite)?;
    let mut tx = state.db.begin().await?;
    lock_list(&mut tx, user.company_id, id).await?;
    ensure_not_in_export(&mut tx, id, group_id, "deleted").await?;
    let (children, items): (i64, i64) = sqlx::query_as(
        "SELECT (SELECT count(*) FROM pricing.price_list_groups WHERE parent_id = $1),
                (SELECT count(*) FROM pricing.price_list_items WHERE group_id = $1)",
    )
    .bind(group_id)
    .fetch_one(&mut *tx)
    .await?;
    if children + items > 0 {
        return Err(AppError::Conflict(format!(
            "the group still has {children} sub-groups and {items} items"
        )));
    }
    let deleted =
        sqlx::query("DELETE FROM pricing.price_list_groups WHERE id = $1 AND price_list_id = $2")
            .bind(group_id)
            .bind(id)
            .execute(&mut *tx)
            .await?
            .rows_affected();
    if deleted == 0 {
        return Err(AppError::NotFound("price list group"));
    }
    touch(&mut tx, id).await?;
    audit::record(
        &mut tx,
        &user,
        "price_list",
        id,
        "group_deleted",
        serde_json::json!({ "group_id": group_id }),
    )
    .await?;
    tx.commit().await?;
    Ok(StatusCode::NO_CONTENT)
}

// ---------------------------------------------------------------------------------------------
// Items
// ---------------------------------------------------------------------------------------------

#[utoipa::path(get, path = "/price-lists/{id}/items", tag = "products", params(("id" = Uuid, Path)),
    responses((status = 200, body = Vec<PriceListItem>), (status = 404, body = ErrorBody)))]
async fn list_items(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<Vec<PriceListItem>>> {
    user.require(Permission::PriceListsRead)?;
    let mut conn = state.db.acquire().await?;
    load_list(&mut conn, user.company_id, id).await?;
    let mut items: Vec<PriceListItem> = sqlx::query_as(sqlx::AssertSqlSafe(format!(
        "{SELECT_ITEM} WHERE i.price_list_id = $1 ORDER BY i.group_id, p.code"
    )))
    .bind(id)
    .fetch_all(&mut *conn)
    .await?;
    items.sort_by(|a, b| {
        a.group_id
            .cmp(&b.group_id)
            .then_with(|| sort_key_cmp(&a.sort_key, &b.sort_key))
            .then_with(|| a.product_code.cmp(&b.product_code))
    });
    Ok(Json(items))
}

async fn check_group(db: &mut PgConnection, list_id: Uuid, group_id: Uuid) -> AppResult<()> {
    let ok: bool = sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM pricing.price_list_groups WHERE id = $1 AND price_list_id = $2)",
    )
    .bind(group_id)
    .bind(list_id)
    .fetch_one(db)
    .await?;
    if ok {
        Ok(())
    } else {
        Err(AppError::Validation(
            "the group does not belong to this price list".into(),
        ))
    }
}

#[utoipa::path(post, path = "/price-lists/{id}/items", tag = "products", params(("id" = Uuid, Path)),
    request_body = PriceListItemInput,
    responses((status = 201, body = PriceListItem), (status = 404, body = ErrorBody),
        (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn create_item(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<PriceListItemInput>,
) -> AppResult<(StatusCode, Json<PriceListItem>)> {
    user.require(Permission::PriceListsWrite)?;
    let sort_key = clean_sort_key(&input.sort_key)?;
    let description = clean_texts("description", &input.description)?;
    let mut tx = state.db.begin().await?;
    lock_list(&mut tx, user.company_id, id).await?;
    check_group(&mut tx, id, input.group_id).await?;
    let product_ok: bool =
        sqlx::query_scalar("SELECT EXISTS (SELECT 1 FROM products.products WHERE id = $1)")
            .bind(input.product_id)
            .fetch_one(&mut *tx)
            .await?;
    if !product_ok {
        return Err(AppError::NotFound("product"));
    }
    let item_id = new_id();
    sqlx::query_scalar::<_, Uuid>(
        "INSERT INTO pricing.price_list_items
            (id, company_id, price_list_id, product_id, group_id, sort_key, price_on_request, net, indicative, hidden)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
         ON CONFLICT (price_list_id, product_id) DO NOTHING RETURNING id",
    )
    .bind(item_id)
    .bind(user.company_id)
    .bind(id)
    .bind(input.product_id)
    .bind(input.group_id)
    .bind(&sort_key)
    .bind(input.price_on_request)
    .bind(input.net)
    .bind(input.indicative)
    .bind(input.hidden)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or_else(|| AppError::Conflict("the product is already in this price list".into()))?;
    replace_texts(
        &mut tx,
        ITEM_DESCRIPTIONS,
        user.company_id,
        item_id,
        &description,
    )
    .await?;
    touch(&mut tx, id).await?;
    audit::record(
        &mut tx,
        &user,
        "price_list",
        id,
        "item_added",
        serde_json::json!({ "item_id": item_id, "product_id": input.product_id }),
    )
    .await?;
    let item = sqlx::query_as(sqlx::AssertSqlSafe(format!(
        "{SELECT_ITEM} WHERE i.id = $1"
    )))
    .bind(item_id)
    .fetch_one(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(item)))
}

#[utoipa::path(put, path = "/price-lists/{id}/items/{item_id}", tag = "products",
    params(("id" = Uuid, Path), ("item_id" = Uuid, Path)), request_body = PriceListItemUpdate,
    responses((status = 200, body = PriceListItem), (status = 404, body = ErrorBody),
        (status = 422, body = ErrorBody)))]
async fn update_item(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((id, item_id)): Path<(Uuid, Uuid)>,
    Json(input): Json<PriceListItemUpdate>,
) -> AppResult<Json<PriceListItem>> {
    user.require(Permission::PriceListsWrite)?;
    let sort_key = clean_sort_key(&input.sort_key)?;
    let description = clean_texts("description", &input.description)?;
    let mut tx = state.db.begin().await?;
    lock_list(&mut tx, user.company_id, id).await?;
    check_group(&mut tx, id, input.group_id).await?;
    let updated = sqlx::query(
        "UPDATE pricing.price_list_items SET group_id = $3, sort_key = $4, price_on_request = $5,
                net = $6, indicative = $7, hidden = $8
         WHERE id = $1 AND price_list_id = $2",
    )
    .bind(item_id)
    .bind(id)
    .bind(input.group_id)
    .bind(&sort_key)
    .bind(input.price_on_request)
    .bind(input.net)
    .bind(input.indicative)
    .bind(input.hidden)
    .execute(&mut *tx)
    .await?
    .rows_affected();
    if updated == 0 {
        return Err(AppError::NotFound("price list item"));
    }
    replace_texts(
        &mut tx,
        ITEM_DESCRIPTIONS,
        user.company_id,
        item_id,
        &description,
    )
    .await?;
    touch(&mut tx, id).await?;
    audit::record(
        &mut tx,
        &user,
        "price_list",
        id,
        "item_updated",
        serde_json::json!({ "item_id": item_id }),
    )
    .await?;
    let item = sqlx::query_as(sqlx::AssertSqlSafe(format!(
        "{SELECT_ITEM} WHERE i.id = $1"
    )))
    .bind(item_id)
    .fetch_one(&mut *tx)
    .await?;
    tx.commit().await?;
    Ok(Json(item))
}

#[utoipa::path(delete, path = "/price-lists/{id}/items/{item_id}", tag = "products",
    params(("id" = Uuid, Path), ("item_id" = Uuid, Path)),
    responses((status = 204), (status = 404, body = ErrorBody)))]
async fn delete_item(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((id, item_id)): Path<(Uuid, Uuid)>,
) -> AppResult<StatusCode> {
    user.require(Permission::PriceListsWrite)?;
    let mut tx = state.db.begin().await?;
    lock_list(&mut tx, user.company_id, id).await?;
    let deleted =
        sqlx::query("DELETE FROM pricing.price_list_items WHERE id = $1 AND price_list_id = $2")
            .bind(item_id)
            .bind(id)
            .execute(&mut *tx)
            .await?
            .rows_affected();
    if deleted == 0 {
        return Err(AppError::NotFound("price list item"));
    }
    touch(&mut tx, id).await?;
    audit::record(
        &mut tx,
        &user,
        "price_list",
        id,
        "item_removed",
        serde_json::json!({ "item_id": item_id }),
    )
    .await?;
    tx.commit().await?;
    Ok(StatusCode::NO_CONTENT)
}

// ---------------------------------------------------------------------------------------------
// Export profiles
// ---------------------------------------------------------------------------------------------

/// Which groups go into one file. One group is an individual chapter (or section), several a
/// combination; each is printed with everything below it.
#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct PriceListExport {
    pub id: Uuid,
    pub code: String,
    pub name: String,
    pub sort_order: i32,
    /// Groups of the list, of any depth; empty means the whole list.
    pub group_ids: Vec<Uuid>,
    /// Optional file name template (placeholders `{list}`, `{zone}`, `{lang}`, `{name}`,
    /// `{code}`); the name is used when absent.
    pub file_name: Option<String>,
}

/// `group_ids` is rebuilt from `price_list_export_groups` in profile order.
const SELECT_EXPORT: &str = "SELECT e.id, e.code, e.name, e.sort_order,
        COALESCE((SELECT array_agg(eg.group_id ORDER BY eg.sort_order)
                  FROM pricing.price_list_export_groups eg WHERE eg.export_id = e.id), '{}'::uuid[]) AS group_ids,
        e.file_name
     FROM pricing.price_list_exports e";

/// Replaces the groups of a profile. The foreign keys prove the groups belong to the same list.
async fn replace_export_groups(
    db: &mut PgConnection,
    company_id: Uuid,
    list_id: Uuid,
    export_id: Uuid,
    group_ids: &[Uuid],
) -> AppResult<()> {
    sqlx::query("DELETE FROM pricing.price_list_export_groups WHERE export_id = $1")
        .bind(export_id)
        .execute(&mut *db)
        .await?;
    if group_ids.is_empty() {
        return Ok(());
    }
    let orders: Vec<i32> = (0..group_ids.len() as i32).collect();
    sqlx::query(
        "INSERT INTO pricing.price_list_export_groups (export_id, group_id, price_list_id, company_id, sort_order)
         SELECT $1, g, $2, $3, o FROM unnest($4::uuid[], $5::int[]) AS t(g, o)",
    )
    .bind(export_id)
    .bind(list_id)
    .bind(company_id)
    .bind(group_ids)
    .bind(&orders)
    .execute(db)
    .await?;
    Ok(())
}

async fn load_export(db: &mut PgConnection, export_id: Uuid) -> AppResult<PriceListExport> {
    sqlx::query_as(sqlx::AssertSqlSafe(format!(
        "{SELECT_EXPORT} WHERE e.id = $1"
    )))
    .bind(export_id)
    .fetch_optional(db)
    .await?
    .ok_or(AppError::NotFound("price list export"))
}

#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct PriceListExportInput {
    /// Unique per list, at most 32 characters.
    pub code: String,
    pub name: String,
    #[serde(default)]
    pub sort_order: i32,
    /// Groups of this list, of any depth; empty means the whole list.
    #[serde(default)]
    pub group_ids: Vec<Uuid>,
    #[serde(default)]
    pub file_name: Option<String>,
}

impl PriceListExportInput {
    fn validate(&mut self) -> AppResult<()> {
        self.code = self.code.trim().to_string();
        self.name = self.name.trim().to_string();
        if self.code.is_empty() || self.code.chars().count() > 32 {
            return Err(AppError::Validation(
                "code is required (at most 32 characters)".into(),
            ));
        }
        if self.name.is_empty() || self.name.chars().count() > 120 {
            return Err(AppError::Validation(
                "name is required (at most 120 characters)".into(),
            ));
        }
        self.file_name = self
            .file_name
            .take()
            .map(|f| f.trim().to_string())
            .filter(|f| !f.is_empty());
        if self
            .file_name
            .as_ref()
            .is_some_and(|f| f.chars().count() > 120)
        {
            return Err(AppError::Validation(
                "file_name is longer than 120 characters".into(),
            ));
        }
        Ok(())
    }
}

/// Every group of the list as `(id, parent_id, sort_order, titles)`.
async fn list_group_titles(db: &mut PgConnection, list_id: Uuid) -> AppResult<Vec<GroupTitles>> {
    let rows: Vec<(Uuid, Option<Uuid>, i32, SqlJson<Texts>)> = sqlx::query_as(
        "SELECT g.id, g.parent_id, g.sort_order,
                COALESCE((SELECT jsonb_object_agg(t.language::text, t.title)
                          FROM pricing.price_list_group_titles t WHERE t.group_id = g.id), '{}'::jsonb)
         FROM pricing.price_list_groups g
         WHERE g.price_list_id = $1",
    )
    .bind(list_id)
    .fetch_all(db)
    .await?;
    Ok(rows
        .into_iter()
        .map(|(i, p, o, t)| (i, p, o, t.0))
        .collect())
}

async fn check_export_input(
    tx: &mut PgConnection,
    list_id: Uuid,
    input: &PriceListExportInput,
) -> AppResult<()> {
    let all: HashSet<Uuid> = list_group_titles(tx, list_id)
        .await?
        .into_iter()
        .map(|g| g.0)
        .collect();
    check_export_groups(&all, &input.group_ids).map_err(|m| AppError::Validation(m.into()))
}

fn export_code_taken() -> AppError {
    AppError::Conflict("an export profile with this code already exists in this price list".into())
}

async fn load_exports(db: &mut PgConnection, list_id: Uuid) -> AppResult<Vec<PriceListExport>> {
    Ok(sqlx::query_as(sqlx::AssertSqlSafe(format!(
        "{SELECT_EXPORT} WHERE e.price_list_id = $1 ORDER BY e.sort_order, e.code"
    )))
    .bind(list_id)
    .fetch_all(db)
    .await?)
}

#[utoipa::path(get, path = "/price-lists/{id}/exports", tag = "products", params(("id" = Uuid, Path)),
    responses((status = 200, body = Vec<PriceListExport>), (status = 404, body = ErrorBody)))]
async fn list_exports(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<Vec<PriceListExport>>> {
    user.require(Permission::PriceListsRead)?;
    let mut conn = state.db.acquire().await?;
    load_list(&mut conn, user.company_id, id).await?;
    Ok(Json(load_exports(&mut conn, id).await?))
}

#[utoipa::path(post, path = "/price-lists/{id}/exports", tag = "products", params(("id" = Uuid, Path)),
    request_body = PriceListExportInput,
    responses((status = 201, body = PriceListExport), (status = 404, body = ErrorBody),
        (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn create_export(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(mut input): Json<PriceListExportInput>,
) -> AppResult<(StatusCode, Json<PriceListExport>)> {
    user.require(Permission::PriceListsWrite)?;
    input.validate()?;
    let mut tx = state.db.begin().await?;
    lock_list(&mut tx, user.company_id, id).await?;
    check_export_input(&mut tx, id, &input).await?;
    let export_id = new_id();
    sqlx::query_scalar::<_, Uuid>(
        "INSERT INTO pricing.price_list_exports (id, company_id, price_list_id, code, name, sort_order, file_name)
         VALUES ($1, $2, $3, $4, $5, $6, $7)
         ON CONFLICT (price_list_id, code) DO NOTHING
         RETURNING id",
    )
    .bind(export_id)
    .bind(user.company_id)
    .bind(id)
    .bind(&input.code)
    .bind(&input.name)
    .bind(input.sort_order)
    .bind(&input.file_name)
    .fetch_optional(&mut *tx)
    .await?
    .ok_or_else(export_code_taken)?;
    replace_export_groups(&mut tx, user.company_id, id, export_id, &input.group_ids).await?;
    let export = load_export(&mut tx, export_id).await?;
    touch(&mut tx, id).await?;
    audit::record(
        &mut tx,
        &user,
        "price_list",
        id,
        "export_created",
        serde_json::json!({ "export_id": export_id, "code": input.code }),
    )
    .await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(export)))
}

#[utoipa::path(put, path = "/price-lists/{id}/exports/{export_id}", tag = "products",
    params(("id" = Uuid, Path), ("export_id" = Uuid, Path)), request_body = PriceListExportInput,
    responses((status = 200, body = PriceListExport), (status = 404, body = ErrorBody),
        (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn update_export(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((id, export_id)): Path<(Uuid, Uuid)>,
    Json(mut input): Json<PriceListExportInput>,
) -> AppResult<Json<PriceListExport>> {
    user.require(Permission::PriceListsWrite)?;
    input.validate()?;
    let mut tx = state.db.begin().await?;
    lock_list(&mut tx, user.company_id, id).await?;
    check_export_input(&mut tx, id, &input).await?;
    let taken: bool = sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM pricing.price_list_exports WHERE price_list_id = $1 AND code = $2 AND id <> $3)",
    )
    .bind(id)
    .bind(&input.code)
    .bind(export_id)
    .fetch_one(&mut *tx)
    .await?;
    if taken {
        return Err(export_code_taken());
    }
    let updated = sqlx::query(
        "UPDATE pricing.price_list_exports SET code = $3, name = $4, sort_order = $5, file_name = $6
         WHERE id = $1 AND price_list_id = $2",
    )
    .bind(export_id)
    .bind(id)
    .bind(&input.code)
    .bind(&input.name)
    .bind(input.sort_order)
    .bind(&input.file_name)
    .execute(&mut *tx)
    .await?
    .rows_affected();
    if updated == 0 {
        return Err(AppError::NotFound("price list export"));
    }
    replace_export_groups(&mut tx, user.company_id, id, export_id, &input.group_ids).await?;
    let export = load_export(&mut tx, export_id).await?;
    touch(&mut tx, id).await?;
    audit::record(
        &mut tx,
        &user,
        "price_list",
        id,
        "export_updated",
        serde_json::json!({ "export_id": export_id }),
    )
    .await?;
    tx.commit().await?;
    Ok(Json(export))
}

#[utoipa::path(delete, path = "/price-lists/{id}/exports/{export_id}", tag = "products",
    params(("id" = Uuid, Path), ("export_id" = Uuid, Path)),
    responses((status = 204), (status = 404, body = ErrorBody)))]
async fn delete_export(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((id, export_id)): Path<(Uuid, Uuid)>,
) -> AppResult<StatusCode> {
    user.require(Permission::PriceListsWrite)?;
    let mut tx = state.db.begin().await?;
    lock_list(&mut tx, user.company_id, id).await?;
    let deleted =
        sqlx::query("DELETE FROM pricing.price_list_exports WHERE id = $1 AND price_list_id = $2")
            .bind(export_id)
            .bind(id)
            .execute(&mut *tx)
            .await?
            .rows_affected();
    if deleted == 0 {
        return Err(AppError::NotFound("price list export"));
    }
    touch(&mut tx, id).await?;
    audit::record(
        &mut tx,
        &user,
        "price_list",
        id,
        "export_deleted",
        serde_json::json!({ "export_id": export_id }),
    )
    .await?;
    tx.commit().await?;
    Ok(StatusCode::NO_CONTENT)
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct PerChapterParams {
    /// 1-based depth of the groups to create a profile for (1 = top level, the default; at most 4).
    pub level: Option<usize>,
}

/// Creates one profile per group at depth `level` (default 1, the top level) that has no profile
/// consisting of exactly that group yet (code `ch-<last 12 hex of the group id>`, name = the group
/// title in the company's default language). Idempotent: a second call creates nothing. Returns
/// all profiles of the list.
#[utoipa::path(post, path = "/price-lists/{id}/exports/per-chapter", tag = "products",
    params(("id" = Uuid, Path), PerChapterParams),
    responses((status = 200, body = Vec<PriceListExport>), (status = 404, body = ErrorBody),
        (status = 422, body = ErrorBody)))]
async fn create_per_chapter_exports(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Query(params): Query<PerChapterParams>,
) -> AppResult<Json<Vec<PriceListExport>>> {
    user.require(Permission::PriceListsWrite)?;
    let level = params.level.unwrap_or(1);
    if !(1..=MAX_DEPTH).contains(&level) {
        return Err(AppError::Validation(format!(
            "level must be between 1 and {MAX_DEPTH}"
        )));
    }
    let mut tx = state.db.begin().await?;
    lock_list(&mut tx, user.company_id, id).await?;
    let company = get_company(&mut *tx, user.company_id)
        .await
        .map_err(AppError::from)?;
    let chapters = groups_at_depth(&list_group_titles(&mut tx, id).await?, level);
    let existing = load_exports(&mut tx, id).await?;
    let mut next_order = existing
        .iter()
        .map(|e| e.sort_order)
        .max()
        .map_or(0, |m| m + 1);
    let mut created = Vec::new();
    for (gid, title) in chapters {
        if existing.iter().any(|e| e.group_ids == [gid]) {
            continue;
        }
        let chain = vec![company.default_language.clone()];
        let name: String = pick(&title, &chain)
            .unwrap_or_else(|| "Chapter".into())
            .chars()
            .take(120)
            .collect();
        let code = format!("ch-{}", &gid.simple().to_string()[20..]);
        let export_id = new_id();
        let inserted = sqlx::query(
            "INSERT INTO pricing.price_list_exports (id, company_id, price_list_id, code, name, sort_order)
             VALUES ($1, $2, $3, $4, $5, $6) ON CONFLICT (price_list_id, code) DO NOTHING",
        )
        .bind(export_id)
        .bind(user.company_id)
        .bind(id)
        .bind(&code)
        .bind(&name)
        .bind(next_order)
        .execute(&mut *tx)
        .await?
        .rows_affected();
        if inserted == 1 {
            replace_export_groups(&mut tx, user.company_id, id, export_id, &[gid]).await?;
            next_order += 1;
            created.push(export_id);
        }
    }
    if !created.is_empty() {
        touch(&mut tx, id).await?;
        audit::record(
            &mut tx,
            &user,
            "price_list",
            id,
            "exports_per_chapter_created",
            serde_json::json!({ "export_ids": created }),
        )
        .await?;
    }
    let all = load_exports(&mut tx, id).await?;
    tx.commit().await?;
    Ok(Json(all))
}

// ---------------------------------------------------------------------------------------------
// Render
// ---------------------------------------------------------------------------------------------

#[derive(Debug, Deserialize, IntoParams)]
pub struct RenderParams {
    /// Zone to print; required when the list has several zones.
    pub zone_id: Option<Uuid>,
    /// One of the languages of that zone; defaults to its first.
    pub lang: Option<String>,
    /// Export profile: only its chapters (with everything below them). Whole list when absent.
    pub export_id: Option<Uuid>,
    /// `pdf` (default) or `xlsx`.
    pub format: Option<RenderFormat>,
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct PlanParams {
    /// `pdf` (default) or `xlsx`.
    pub format: Option<RenderFormat>,
}

/// The zone a render is for: the requested one, or the only one of the list.
fn pick_zone(list: &PriceList, requested: Option<Uuid>) -> AppResult<&PriceListZone> {
    match (requested, list.zones.0.as_slice()) {
        (_, []) => Err(AppError::Validation(
            "the price list has no zones; add one first".into(),
        )),
        (Some(id), zones) => zones.iter().find(|z| z.price_zone_id == id).ok_or_else(|| {
            AppError::Validation("the price list is not published for this zone".into())
        }),
        (None, [only]) => Ok(only),
        (None, _) => Err(AppError::Validation(
            "the price list has several zones; zone_id is required".into(),
        )),
    }
}

#[derive(FromRow)]
struct ItemRow {
    product_id: Uuid,
    group_id: Uuid,
    sort_key: String,
    product_code: String,
    product_name: String,
    unit: String,
    price_on_request: bool,
    net: bool,
    indicative: bool,
    hidden: bool,
    description: SqlJson<Texts>,
}

/// ASCII-only file name stem for the download header: `<list>-<zone>[-<profile>]-<lang>`.
fn file_stem(parts: &[&str]) -> String {
    parts
        .iter()
        .map(|p| {
            p.chars()
                .map(|c| {
                    if c.is_ascii_alphanumeric() || c == '-' || c == '_' {
                        c
                    } else {
                        '_'
                    }
                })
                .collect::<String>()
        })
        .collect::<Vec<_>>()
        .join("-")
}

/// Renders the list for one of its zones, at the list date, as PDF or Excel, in one of that
/// zone's languages. With `export_id` only that profile's chapters are printed.
#[utoipa::path(post, path = "/price-lists/{id}/render", tag = "products",
    params(("id" = Uuid, Path), RenderParams),
    responses((status = 200, content_type = "application/octet-stream",
        description = "The rendered file (PDF or XLSX) as raw bytes"),
        (status = 404, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn render_price_list(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Query(params): Query<RenderParams>,
) -> AppResult<Response> {
    user.require(Permission::PriceListsRead)?;
    let mut conn = state.db.acquire().await?;
    let list = load_list(&mut conn, user.company_id, id).await?;
    let zone = pick_zone(&list, params.zone_id)?.clone();
    let lang = params
        .lang
        .as_deref()
        .map(|l| l.trim().to_lowercase())
        .unwrap_or_else(|| zone.languages[0].clone());
    if !zone.languages.contains(&lang) {
        return Err(AppError::Validation(format!(
            "the list is not published in '{lang}' for zone {} (languages: {})",
            zone.price_zone_code,
            zone.languages.join(", ")
        )));
    }
    let export: Option<PriceListExport> = match params.export_id {
        Some(export_id) => Some(
            sqlx::query_as(sqlx::AssertSqlSafe(format!(
                "{SELECT_EXPORT} WHERE e.id = $1 AND e.price_list_id = $2"
            )))
            .bind(export_id)
            .bind(id)
            .fetch_optional(&mut *conn)
            .await?
            .ok_or(AppError::NotFound("price list export"))?,
        ),
        None => None,
    };
    let company = get_company(&mut *conn, user.company_id)
        .await
        .map_err(AppError::from)?;
    let chain = language_chain(&lang, &company.default_language, &zone.languages);
    let format = params.format.unwrap_or(RenderFormat::Pdf);
    // The logo is only for the PDF header; a company without one prints without.
    let logo: Option<(String, Vec<u8>)> =
        if matches!(format, RenderFormat::Pdf) && list.settings.0.show_logo {
            logo::load(&mut conn, user.company_id).await?.map(|l| {
                (
                    format!("logo.{}", logo::extension(&l.content_type)),
                    l.bytes,
                )
            })
        } else {
            None
        };

    // One snapshot for everything the document is made of, so a concurrent edit cannot give a
    // list whose items and chapters disagree. Committed before rendering: no connection is held
    // while Typst or Excel work.
    let mut tx = sqlx::Connection::begin(&mut *conn).await?;
    sqlx::query("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY")
        .execute(&mut *tx)
        .await?;
    let all_groups: Vec<AssembleGroup> = sqlx::query_as::<_, PriceListGroup>(sqlx::AssertSqlSafe(
        format!("{SELECT_GROUP} WHERE g.price_list_id = $1"),
    ))
    .bind(id)
    .fetch_all(&mut *tx)
    .await?
    .into_iter()
    .map(|g| AssembleGroup {
        id: g.id,
        parent_id: g.parent_id,
        sort_order: g.sort_order,
        title: g.title.0,
        page_break: g.page_break,
        show_title: g.show_title,
        gap_mm: g.gap_mm,
    })
    .collect();
    // A profile prints only its chapters; products of other chapters simply find no group.
    let groups = select_groups(
        &all_groups,
        export.as_ref().map_or(&[][..], |e| e.group_ids.as_slice()),
    );

    // Inactive products are not offered any more and stay off the printed list.
    let rows: Vec<ItemRow> = sqlx::query_as(
        "SELECT i.product_id, i.group_id, i.sort_key, p.code AS product_code, p.name AS product_name,
                p.unit, i.price_on_request, i.net, i.indicative, i.hidden,
                COALESCE((SELECT jsonb_object_agg(d.language::text, d.description)
                          FROM pricing.price_list_item_descriptions d WHERE d.item_id = i.id), '{}'::jsonb) AS description
         FROM pricing.price_list_items i JOIN products.products p ON p.id = i.product_id
         WHERE i.price_list_id = $1 AND p.active",
    )
    .bind(id)
    .fetch_all(&mut *tx)
    .await?;
    let product_ids: Vec<Uuid> = rows.iter().map(|r| r.product_id).collect();

    let mut translations: HashMap<Uuid, Texts> = HashMap::new();
    let tr: Vec<(Uuid, String, String)> = sqlx::query_as(
        "SELECT product_id, language::text, name FROM products.product_translations
         WHERE product_id = ANY($1) AND language = ANY($2)",
    )
    .bind(&product_ids)
    .bind(&chain)
    .fetch_all(&mut *tx)
    .await?;
    for (product, language, name) in tr {
        translations
            .entry(product)
            .or_default()
            .insert(language, name);
    }

    #[derive(FromRow)]
    struct PriceRow {
        product_id: Uuid,
        unit_price: Decimal,
        valid_from: NaiveDate,
    }
    let price_rows: Vec<PriceRow> = sqlx::query_as(
        "SELECT product_id, unit_price, valid_from FROM pricing.zone_prices
         WHERE company_id = $1 AND zone_id = $2 AND product_id = ANY($3) AND valid_from <= $4",
    )
    .bind(user.company_id)
    .bind(zone.price_zone_id)
    .bind(&product_ids)
    .bind(list.valid_from)
    .fetch_all(&mut *tx)
    .await?;
    tx.commit().await?;
    drop(conn);
    let mut history: HashMap<Uuid, Vec<ZonePrice>> = HashMap::new();
    for r in price_rows {
        history.entry(r.product_id).or_default().push(ZonePrice {
            zone_id: zone.price_zone_id,
            unit_price: r.unit_price,
            valid_from: r.valid_from,
        });
    }

    let items: Vec<AssembleItem> = rows
        .into_iter()
        .map(|r| AssembleItem {
            group_id: r.group_id,
            sort_key: r.sort_key,
            price: history
                .get(&r.product_id)
                .and_then(|h| resolve_zone_price(h, zone.price_zone_id, list.valid_from)),
            translations: translations.remove(&r.product_id).unwrap_or_default(),
            product_code: r.product_code,
            product_name: r.product_name,
            unit: r.unit,
            description: r.description.0,
            price_on_request: r.price_on_request,
            net: r.net,
            indicative: r.indicative,
            hidden: r.hidden,
        })
        .collect();
    let sections = assemble(&groups, &items, &chain);

    let settings = &list.settings.0;
    let currency = if !settings.currency_symbol.is_empty() {
        settings.currency_symbol.clone()
    } else if company.currency == "EUR" {
        "€".into()
    } else {
        company.currency.clone()
    };
    let has_indicative = sections.iter().flat_map(|s| &s.rows).any(|r| r.indicative);
    let document = PriceListDoc {
        language: lang.clone(),
        title: list.name.clone(),
        company_name: company.name.clone(),
        zone_name: zone.price_zone_name.clone(),
        valid_from: format_date(list.valid_from),
        currency,
        footer_text: settings.footer_text.clone(),
        accent_color: settings.accent_color.clone(),
        show_unit: settings.show_unit,
        has_indicative,
        logo_file: logo.as_ref().map(|(name, _)| name.clone()),
        labels: doc::labels(&lang),
        sections: sections
            .into_iter()
            .map(|s| PriceListSection {
                level: s.level,
                print_level: s.print_level,
                title: s.title,
                show_title: s.show_title,
                gap_mm: s.gap_mm.to_f64().unwrap_or(0.0),
                page_break: s.page_break,
                rows: s
                    .rows
                    .into_iter()
                    .map(|r| PriceListRow {
                        code: r.code,
                        description: r.description,
                        unit: r.unit,
                        on_request: r.price.is_none(),
                        price: r.price.map(format_unit_price).unwrap_or_default(),
                        net: r.net,
                        indicative: r.indicative,
                    })
                    .collect(),
            })
            .collect(),
    };

    let stem = file_stem(&match &export {
        Some(e) => vec![
            list.code.as_str(),
            zone.price_zone_code.as_str(),
            e.code.as_str(),
            lang.as_str(),
        ],
        None => vec![
            list.code.as_str(),
            zone.price_zone_code.as_str(),
            lang.as_str(),
        ],
    });
    let (content_type, extension, bytes) = match format {
        RenderFormat::Pdf => {
            let files: Vec<(String, Vec<u8>)> = logo.into_iter().collect();
            let pdf = match doc::render_pdf(&state.documents, &document, &files).await {
                Ok(pdf) => pdf,
                // A logo typst cannot read must not stop the price list from printing.
                Err(e) if !files.is_empty() => {
                    tracing::warn!(error = ?e, "price list with logo failed; rendering without");
                    let bare = PriceListDoc {
                        logo_file: None,
                        ..document
                    };
                    doc::render_pdf(&state.documents, &bare, &[]).await?
                }
                Err(e) => return Err(e.into()),
            };
            ("application/pdf", "pdf", pdf)
        }
        RenderFormat::Xlsx => (
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "xlsx",
            doc::render_xlsx(&document).map_err(|e| AppError::Internal(e.into()))?,
        ),
    };
    Ok((
        [
            (header::CONTENT_TYPE, content_type.to_string()),
            (
                header::CONTENT_DISPOSITION,
                format!("attachment; filename=\"{stem}.{extension}\""),
            ),
        ],
        bytes,
    )
        .into_response())
}

/// Every file the export profiles produce for the list: per zone, per language of that zone, the
/// whole list and then each profile, with a sanitized relative path computed here.
#[utoipa::path(get, path = "/price-lists/{id}/export-plan", tag = "products",
    params(("id" = Uuid, Path), PlanParams),
    responses((status = 200, body = Vec<ExportPlanEntry>), (status = 404, body = ErrorBody)))]
async fn get_export_plan(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Query(params): Query<PlanParams>,
) -> AppResult<Json<Vec<ExportPlanEntry>>> {
    user.require(Permission::PriceListsRead)?;
    let mut conn = state.db.acquire().await?;
    let list = load_list(&mut conn, user.company_id, id).await?;
    let exports = load_exports(&mut conn, id).await?;
    let zones: Vec<PlanZone> = list
        .zones
        .0
        .iter()
        .map(|z| PlanZone {
            id: z.price_zone_id,
            code: z.price_zone_code.clone(),
            name: z.price_zone_name.clone(),
            languages: z.languages.clone(),
        })
        .collect();
    let exports: Vec<PlanExport> = exports
        .into_iter()
        .map(|e| PlanExport {
            id: e.id,
            code: e.code,
            name: e.name,
            file_name: e.file_name,
        })
        .collect();
    Ok(Json(export_plan(
        &list.name,
        &zones,
        &exports,
        params.format.unwrap_or(RenderFormat::Pdf),
    )))
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(list_price_lists, create_price_list))
        .routes(routes!(
            get_price_list,
            update_price_list,
            delete_price_list
        ))
        .routes(routes!(list_groups, create_group))
        .routes(routes!(update_group, delete_group))
        .routes(routes!(list_items, create_item))
        .routes(routes!(update_item, delete_item))
        .routes(routes!(replace_zones))
        .routes(routes!(list_exports, create_export))
        .routes(routes!(create_per_chapter_exports))
        .routes(routes!(update_export, delete_export))
        .routes(routes!(render_price_list))
        .routes(routes!(get_export_plan))
}

#[cfg(test)]
mod tests {
    use super::*;
    use rust_decimal_macros::dec;

    fn texts(pairs: &[(&str, &str)]) -> Texts {
        pairs
            .iter()
            .map(|(k, v)| (k.to_string(), v.to_string()))
            .collect()
    }

    fn chain(l: &[&str]) -> Vec<String> {
        l.iter().map(|s| s.to_string()).collect()
    }

    fn group(id: u128, parent: Option<u128>, order: i32, title: &[(&str, &str)]) -> AssembleGroup {
        AssembleGroup {
            id: Uuid::from_u128(id),
            parent_id: parent.map(Uuid::from_u128),
            sort_order: order,
            title: texts(title),
            page_break: false,
            show_title: true,
            gap_mm: Decimal::ZERO,
        }
    }

    fn untitled(mut g: AssembleGroup, gap: Decimal) -> AssembleGroup {
        g.show_title = false;
        g.gap_mm = gap;
        g
    }

    fn item(group: u128, key: &str, code: &str, price: Option<Decimal>) -> AssembleItem {
        AssembleItem {
            group_id: Uuid::from_u128(group),
            sort_key: key.into(),
            product_code: code.into(),
            product_name: format!("name {code}"),
            unit: "pcs".into(),
            translations: Texts::new(),
            description: Texts::new(),
            price,
            price_on_request: false,
            net: false,
            indicative: false,
            hidden: false,
        }
    }

    #[test]
    fn sort_keys_compare_numerically_per_segment() {
        let mut keys = vec!["1.10", "1.2", "", "1", "2.1.1", "1.2.a", "1.b", "10"];
        keys.sort_by(|a, b| sort_key_cmp(a, b));
        assert_eq!(
            keys,
            ["", "1", "1.2", "1.2.a", "1.10", "1.b", "2.1.1", "10"]
        );
    }

    #[test]
    fn groups_follow_sort_order_and_items_sort_key_then_code() {
        let groups = [
            group(2, None, 20, &[("nl", "Tweede")]),
            group(1, None, 10, &[("nl", "Eerste")]),
            group(3, Some(1), 0, &[("nl", "Sub")]),
        ];
        let items = [
            item(1, "1.10", "B", Some(dec!(5))),
            item(1, "1.2", "Z", Some(dec!(5))),
            item(1, "1.2", "A", Some(dec!(5))),
            item(2, "", "C", Some(dec!(5))),
            item(3, "", "D", Some(dec!(5))),
        ];
        let out = assemble(&groups, &items, &chain(&["nl"]));
        let shape: Vec<(usize, &str, Vec<&str>)> = out
            .iter()
            .map(|s| {
                (
                    s.level,
                    s.title.as_str(),
                    s.rows.iter().map(|r| r.code.as_str()).collect(),
                )
            })
            .collect();
        assert_eq!(
            shape,
            vec![
                (0, "Eerste", vec!["A", "Z", "B"]),
                (1, "Sub", vec!["D"]),
                (0, "Tweede", vec!["C"]),
            ]
        );
    }

    #[test]
    fn groups_without_printable_items_are_skipped_but_parents_of_printable_ones_stay() {
        let groups = [
            group(1, None, 0, &[("nl", "Leeg")]),
            group(2, None, 1, &[("nl", "Ouder")]),
            group(3, Some(2), 0, &[("nl", "Kind")]),
            group(4, None, 2, &[("nl", "Alleen verborgen")]),
            group(5, None, 3, &[("nl", "Zonder prijs")]),
        ];
        let mut hidden = item(4, "", "H", Some(dec!(1)));
        hidden.hidden = true;
        let items = [
            item(3, "", "K", Some(dec!(1))),
            hidden,
            item(5, "", "N", None),
        ];
        let out = assemble(&groups, &items, &chain(&["nl"]));
        let titles: Vec<&str> = out.iter().map(|s| s.title.as_str()).collect();
        assert_eq!(titles, ["Ouder", "Kind"]);
        assert!(out[0].rows.is_empty());
    }

    #[test]
    fn untitled_group_prints_its_items_without_title_and_empty_ones_are_skipped() {
        let groups = [
            group(1, None, 0, &[("nl", "Eerste")]),
            untitled(group(2, None, 1, &[("nl", "Intern")]), dec!(6.5)),
            untitled(group(3, None, 2, &[("nl", "Ook intern")]), dec!(3)),
        ];
        let items = [
            item(1, "", "A", Some(dec!(1))),
            item(2, "", "B", Some(dec!(2))),
        ];
        let out = assemble(&groups, &items, &chain(&["nl"]));
        assert_eq!(out.len(), 2, "the untitled group without items is skipped");
        assert!(out[0].show_title && out[0].title == "Eerste");
        assert!(!out[1].show_title);
        assert_eq!(
            out[1].title, "",
            "the title is never handed to the template"
        );
        assert_eq!(out[1].gap_mm, dec!(6.5));
        assert_eq!(out[1].rows.len(), 1);
    }

    #[test]
    fn gap_is_limited_to_zero_to_fifty_millimetres() {
        for ok in [dec!(0), dec!(0.25), dec!(50)] {
            assert!(check_gap(ok).is_ok(), "{ok}");
        }
        for bad in [dec!(-0.01), dec!(50.01), dec!(1.234)] {
            assert!(check_gap(bad).is_err(), "{bad}");
        }
    }

    #[test]
    fn zero_price_and_flag_print_on_request_and_drop_markers() {
        let groups = [group(1, None, 0, &[("nl", "G")])];
        let mut flagged = item(1, "2", "F", Some(dec!(9)));
        flagged.price_on_request = true;
        flagged.net = true;
        let mut flagged_no_price = item(1, "3", "G", None);
        flagged_no_price.price_on_request = true;
        let mut net = item(1, "4", "N", Some(dec!(3.5)));
        net.net = true;
        net.indicative = true;
        let items = [
            item(1, "1", "Z", Some(dec!(0))),
            flagged,
            flagged_no_price,
            net,
        ];
        let rows = &assemble(&groups, &items, &chain(&["nl"]))[0].rows;
        assert_eq!(rows.len(), 4);
        for r in &rows[..3] {
            assert_eq!(r.price, None);
            assert!(!r.net && !r.indicative);
        }
        assert_eq!(rows[3].price, Some(dec!(3.5)));
        assert!(rows[3].net && rows[3].indicative);
    }

    #[test]
    fn text_falls_back_along_the_language_chain() {
        let groups = [
            group(1, None, 0, &[("en", "Clocks"), ("nl", "Klokken")]),
            group(2, None, 1, &[("de", "Nur Deutsch")]),
        ];
        let mut a = item(1, "1", "A", Some(dec!(1)));
        a.translations = texts(&[("nl", "Wijzer"), ("fr", "Aiguille")]);
        let mut b = item(1, "2", "B", Some(dec!(1)));
        b.translations = texts(&[("nl", "Motor")]);
        b.description = texts(&[("fr", "Moteur special")]);
        let c = item(1, "3", "C", Some(dec!(1)));
        let d = item(2, "", "D", Some(dec!(1)));
        let out = assemble(&groups, &[a, b, c, d], &chain(&["fr", "nl", "en"]));
        assert_eq!(out[0].title, "Klokken");
        let desc: Vec<&str> = out[0].rows.iter().map(|r| r.description.as_str()).collect();
        // The override wins in its language; the product name is the last resort.
        assert_eq!(desc, ["Aiguille", "Moteur special", "name C"]);
        assert_eq!(out[1].title, "Nur Deutsch");
    }

    #[test]
    fn profile_selects_groups_of_any_depth_with_descendants_in_list_order() {
        let groups = [
            group(1, None, 30, &[("nl", "C")]),
            group(2, None, 10, &[("nl", "A")]),
            group(3, Some(2), 0, &[("nl", "A sub")]),
            group(4, Some(3), 0, &[("nl", "A subsub")]),
            group(5, None, 20, &[("nl", "B")]),
            group(6, Some(5), 0, &[("nl", "B sub")]),
        ];
        let id = |n| Uuid::from_u128(n);
        // The profile lists C before A; the print order stays the list order.
        let picked = select_groups(&groups, &[id(1), id(2)]);
        let ids: Vec<Uuid> = picked.iter().map(|g| g.id).collect();
        assert_eq!(ids, [id(1), id(2), id(3), id(4)]);
        // Empty = whole list; a nested group selects itself and its descendants only.
        assert_eq!(select_groups(&groups, &[]).len(), 6);
        let nested: Vec<Uuid> = select_groups(&groups, &[id(3)])
            .iter()
            .map(|g| g.id)
            .collect();
        assert_eq!(nested, [id(3), id(4)]);
        // Overlap: a group and its ancestor/descendant are included once.
        let overlap: Vec<Uuid> = select_groups(&groups, &[id(4), id(2), id(3)])
            .iter()
            .map(|g| g.id)
            .collect();
        assert_eq!(overlap, [id(2), id(3), id(4)]);
        // An unknown id selects nothing.
        assert!(select_groups(&groups, &[id(99)]).is_empty());

        let items = [
            item(4, "", "DEEP", Some(dec!(1))),
            item(6, "", "OTHER", Some(dec!(1))),
            item(1, "", "CEE", Some(dec!(1))),
        ];
        let out = assemble(
            &select_groups(&groups, &[id(1), id(2)]),
            &items,
            &chain(&["nl"]),
        );
        let titles: Vec<&str> = out.iter().map(|s| s.title.as_str()).collect();
        assert_eq!(
            titles,
            ["A", "A sub", "A subsub", "C"],
            "B has no selected items"
        );
        let codes: Vec<&str> = out
            .iter()
            .flat_map(|s| &s.rows)
            .map(|r| r.code.as_str())
            .collect();
        assert_eq!(codes, ["DEEP", "CEE"]);
        let b = assemble(&select_groups(&groups, &[id(5)]), &items, &chain(&["nl"]));
        assert_eq!(
            b.iter().map(|s| s.title.as_str()).collect::<Vec<_>>(),
            ["B", "B sub"]
        );
        // A profile on a nested group prints that subtree only, and its levels count from it.
        let sub = assemble(&select_groups(&groups, &[id(3)]), &items, &chain(&["nl"]));
        assert_eq!(
            sub.iter()
                .map(|s| (s.title.as_str(), s.level))
                .collect::<Vec<_>>(),
            [("A sub", 0), ("A subsub", 1)]
        );
    }

    #[test]
    fn print_level_counts_only_ancestors_with_a_printed_title() {
        // section (hidden) > chapter (hidden) > titled group > untitled subchapter > titled leaf
        let groups = [
            untitled(group(1, None, 0, &[("nl", "Sectie")]), Decimal::ZERO),
            untitled(group(2, Some(1), 0, &[("nl", "Hoofdstuk")]), Decimal::ZERO),
            group(3, Some(2), 0, &[("nl", "Groep")]),
            untitled(group(4, Some(3), 0, &[("nl", "Sub")]), dec!(5)),
            group(5, Some(4), 0, &[("nl", "Blad")]),
            group(6, Some(3), 1, &[("nl", "Kind")]),
        ];
        let items = [
            item(4, "", "A", Some(dec!(1))),
            item(5, "", "B", Some(dec!(1))),
            item(6, "", "C", Some(dec!(1))),
        ];
        let out = assemble(&groups, &items, &chain(&["nl"]));
        let got: Vec<(&str, usize, usize)> = out
            .iter()
            .map(|s| (s.title.as_str(), s.level, s.print_level))
            .collect();
        assert_eq!(
            got,
            [
                ("", 0, 0),
                ("", 1, 0),
                ("Groep", 2, 0),
                ("", 3, 1),
                ("Blad", 4, 1),
                ("Kind", 3, 1)
            ]
        );
    }

    #[test]
    fn groups_at_depth_are_in_tree_order() {
        let g = |n: u128, p: Option<u128>, o: i32| {
            (
                Uuid::from_u128(n),
                p.map(Uuid::from_u128),
                o,
                texts(&[("nl", &format!("g{n}"))]),
            )
        };
        let groups = [
            g(1, None, 20),
            g(2, None, 10),
            g(3, Some(1), 0),
            g(4, Some(2), 5),
            g(5, Some(2), 1),
            g(6, Some(5), 0),
        ];
        let ids = |d| -> Vec<u128> {
            groups_at_depth(&groups, d)
                .iter()
                .map(|(i, _)| i.as_u128())
                .collect()
        };
        assert_eq!(ids(1), [2, 1]);
        assert_eq!(ids(2), [5, 4, 3]);
        assert_eq!(ids(3), [6]);
        assert!(ids(4).is_empty());
    }

    #[test]
    fn profile_groups_must_be_unique_groups_of_the_list() {
        let all: HashSet<Uuid> = [Uuid::from_u128(1), Uuid::from_u128(2)].into();
        assert!(check_export_groups(&all, &[]).is_ok());
        assert!(check_export_groups(&all, &[Uuid::from_u128(1), Uuid::from_u128(2)]).is_ok());
        assert!(check_export_groups(&all, &[Uuid::from_u128(1), Uuid::from_u128(1)]).is_err());
        assert!(check_export_groups(&all, &[Uuid::from_u128(3)]).is_err());
    }

    #[test]
    fn zone_is_required_when_the_list_has_several() {
        let zone = |n: u128| PriceListZone {
            price_zone_id: Uuid::from_u128(n),
            price_zone_code: format!("Z{n}"),
            price_zone_name: format!("Zone {n}"),
            languages: vec!["nl".into()],
            sort_order: n as i32,
        };
        let list = |zones: Vec<PriceListZone>| PriceList {
            id: Uuid::nil(),
            code: "L".into(),
            name: "L".into(),
            zones: SqlJson(zones),
            valid_from: NaiveDate::from_ymd_opt(2027, 1, 1).unwrap(),
            settings: SqlJson(PriceListSettings::default()),
            item_count: 0,
        };
        assert!(pick_zone(&list(vec![]), None).is_err());
        assert_eq!(
            pick_zone(&list(vec![zone(1)]), None)
                .unwrap()
                .price_zone_code,
            "Z1"
        );
        let two = list(vec![zone(1), zone(2)]);
        assert!(pick_zone(&two, None).is_err());
        assert_eq!(
            pick_zone(&two, Some(Uuid::from_u128(2)))
                .unwrap()
                .price_zone_code,
            "Z2"
        );
        assert!(pick_zone(&two, Some(Uuid::from_u128(9))).is_err());
    }

    #[test]
    fn download_name_is_ascii_safe() {
        assert_eq!(file_stem(&["PL 2027", "Z1", "nl"]), "PL_2027-Z1-nl");
        assert_eq!(file_stem(&["../x", "é"]), "___x-_");
    }

    #[test]
    fn language_chain_is_requested_company_then_list_without_duplicates() {
        assert_eq!(
            language_chain("fr", "nl", &chain(&["nl", "fr", "en"])),
            ["fr", "nl", "en"]
        );
    }

    fn tree(pairs: &[(u128, Option<u128>)]) -> Vec<(Uuid, Option<Uuid>)> {
        pairs
            .iter()
            .map(|(i, p)| (Uuid::from_u128(*i), p.map(Uuid::from_u128)))
            .collect()
    }

    #[test]
    fn position_rejects_foreign_parent_cycles_and_depth() {
        let t = tree(&[(1, None), (2, Some(1)), (3, Some(2)), (4, Some(3))]);
        let u = |n| Some(Uuid::from_u128(n));
        assert!(check_position(&t, None, None).is_ok());
        assert!(check_position(&t, None, u(3)).is_ok());
        assert!(check_position(&t, None, u(4)).is_err(), "fifth level");
        assert!(check_position(&t, None, u(99)).is_err(), "unknown parent");
        assert!(check_position(&t, u(1), u(1)).is_err(), "below itself");
        assert!(
            check_position(&t, u(1), u(3)).is_err(),
            "below its descendant"
        );
        // Moving a sub-tree must keep its own height within the limit.
        let t2 = tree(&[
            (1, None),
            (2, Some(1)),
            (5, None),
            (6, Some(5)),
            (7, Some(6)),
        ]);
        assert!(
            check_position(&t2, u(5), u(2)).is_err(),
            "3 levels below level 2 is 5 deep"
        );
        assert!(check_position(&t2, u(5), u(1)).is_ok());
        assert!(check_position(&t2, u(2), None).is_ok());
    }

    #[test]
    fn sort_key_and_text_validation() {
        assert_eq!(clean_sort_key(" 2.10.3 ").unwrap(), "2.10.3");
        assert!(clean_sort_key("").is_ok());
        assert!(clean_sort_key("1..2").is_err());
        assert!(clean_sort_key(".1").is_err());
        assert!(clean_sort_key("1 2").is_err());
        let t = clean_texts(
            "t",
            &[
                ("NL".to_string(), " Hoi ".to_string()),
                ("fr".into(), " ".into()),
            ]
            .into(),
        )
        .unwrap();
        assert_eq!(t, texts(&[("nl", "Hoi")]));
        assert!(clean_texts("t", &[("nld".to_string(), "x".to_string())].into()).is_err());
    }

    #[test]
    fn settings_validate_the_colour() {
        let mut s = PriceListSettings::default();
        assert!(s.validate().is_ok());
        s.accent_color = "red".into();
        assert!(s.validate().is_err());
        assert!(
            PriceListSettings::default().show_logo,
            "the logo shows by default"
        );
    }

    #[test]
    fn settings_validate_the_import_rules() {
        let s: PriceListSettings = serde_json::from_value(serde_json::json!({})).unwrap();
        assert_eq!(s.import_group_levels, 2);
        assert_eq!(s.import_title_conflict, ImportTitleConflict::LowestPosition);
        assert_eq!(s.import_short_position, ImportShortPosition::ShallowerGroup);
        let s: PriceListSettings = serde_json::from_value(serde_json::json!({
            "import_group_levels": 3,
            "import_title_conflict": "first_row",
            "import_short_position": "error",
        }))
        .unwrap();
        assert_eq!(s.import_title_conflict, ImportTitleConflict::FirstRow);
        assert_eq!(s.import_short_position, ImportShortPosition::Error);
        for (levels, ok) in [(0, false), (1, true), (4, true), (5, false)] {
            let mut s = PriceListSettings {
                import_group_levels: levels,
                ..Default::default()
            };
            assert_eq!(s.validate().is_ok(), ok, "{levels}");
        }
        assert!(serde_json::from_value::<PriceListSettings>(
            serde_json::json!({"import_title_conflict": "longest"})
        )
        .is_err());
    }
}
