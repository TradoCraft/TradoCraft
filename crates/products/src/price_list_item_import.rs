//! Price list items as an importable entity (ADR 0100): one row per product of a list, an upsert on
//! (list, product) in the shared engine of ADR 0067.
//!
//! A row names its place with a dotted `position`. How the position is read is a setting of the
//! list (`settings`, [`PriceListSettings`]), never a rule of the importer:
//!
//! * the first `import_group_levels` segments are the group path: each is the `sort_order` of a
//!   group among its siblings, so `2.3.10` with two levels is item `10` of group 3 of chapter 2.
//!   Groups that do not exist are created along the path (with their parents);
//! * the remaining segments are the item's sort key;
//! * a position with fewer segments names a shallower group (the item gets an empty sort key) or
//!   is an error (`import_short_position`);
//! * the titles in `group_title_<language>` belong to the deepest group of the path. When rows of
//!   one group disagree, `import_title_conflict` decides: the row with the lowest position, the
//!   first row of the file, or an error. Empty title cells are ignored.
//!
//! A group created without any title in the file is untitled (`show_title` false, no title text).
//! Nothing is deleted: items and groups that are not in the file stay as they are. Item
//! descriptions are not part of the file.

use std::cmp::Ordering;
use std::collections::{BTreeMap, HashMap};

use sqlx::types::Json as SqlJson;
use sqlx::{PgConnection, PgPool};
use tradocraft_core::import::{
    family_language, family_languages, AuditEvent, Cell, CellValue, Cells, Column, ColumnKind,
    ExportTable, ImportEntity, Importable, Row, Table, KEY_SEPARATOR,
};
use tradocraft_core::{new_id, AppResult, CurrentUser, Permission};
use uuid::Uuid;

use crate::price_lists::{
    sort_key_cmp, ImportShortPosition, ImportTitleConflict, PriceListSettings, MAX_DEPTH,
};

const COLUMNS: [Column; 8] = [
    Column::new("price_list", ColumnKind::Code, true),
    Column::new("product_code", ColumnKind::Code, true),
    Column::new("position", ColumnKind::Code, true),
    Column::per_language(GROUP_TITLE, ColumnKind::Text),
    Column::new("price_on_request", ColumnKind::Boolean, false),
    Column::new("net", ColumnKind::Boolean, false),
    Column::new("indicative", ColumnKind::Boolean, false),
    Column::new("hidden", ColumnKind::Boolean, false),
];

/// The prefix of the title columns `group_title_<code>`.
const GROUP_TITLE: &str = "group_title";
/// Longest group title (as in the editor).
const MAX_TITLE: usize = 300;
/// Longest item sort key (as in the editor).
const MAX_SORT_KEY: usize = 64;

// ---------------------------------------------------------------------------------------------
// Positions (pure)
// ---------------------------------------------------------------------------------------------

/// A position split into the group path and the item's sort key.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Position {
    /// The `sort_order` of each group from the top.
    pub groups: Vec<i32>,
    pub sort_key: String,
}

impl Position {
    /// The normalised position, for comparing two rows (`1.02` and `1.2` are the same group).
    pub fn text(&self) -> String {
        let mut parts: Vec<String> = self.groups.iter().map(i32::to_string).collect();
        if !self.sort_key.is_empty() {
            parts.push(self.sort_key.clone());
        }
        parts.join(".")
    }
}

/// Reads a position with `levels` group segments. Spaces around it and dots at either end are
/// dropped (`"3."` is `3`); a segment in between must not be empty. Group segments are whole
/// numbers, the rest letters and digits.
pub fn parse_position(
    raw: &str,
    levels: usize,
    short: ImportShortPosition,
) -> Result<Position, String> {
    let text = raw.trim().trim_matches('.').trim();
    if text.is_empty() {
        return Err("the position is empty".into());
    }
    let segments: Vec<&str> = text.split('.').collect();
    if segments.iter().any(|s| s.is_empty()) {
        return Err(format!("{text:?} has an empty segment"));
    }
    if segments.len() < levels && short == ImportShortPosition::Error {
        return Err(format!(
            "{text:?} needs at least {levels} segments (the group levels of the list)"
        ));
    }
    let split = levels.min(segments.len());
    let mut groups = Vec::with_capacity(split);
    for s in &segments[..split] {
        match s.parse::<i32>() {
            Ok(n) if s.chars().all(|c| c.is_ascii_digit()) => groups.push(n),
            _ => {
                return Err(format!(
                    "group segment {s:?} of {text:?} is not a whole number"
                ))
            }
        }
    }
    let rest = &segments[split..];
    if !rest
        .iter()
        .all(|s| s.chars().all(|c| c.is_ascii_alphanumeric()))
    {
        return Err(format!(
            "{text:?} may only hold letters and digits between the dots"
        ));
    }
    let sort_key = rest.join(".");
    if sort_key.len() > MAX_SORT_KEY {
        return Err(format!(
            "the part after the groups is longer than {MAX_SORT_KEY} characters"
        ));
    }
    Ok(Position { groups, sort_key })
}

/// A title a row offers for its group in one language.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Candidate {
    pub title: String,
    /// The row's normalised position ([`Position::text`]).
    pub position: String,
    pub line: usize,
}

/// Whether `new` replaces the chosen title `old` under `rule` (for [`ImportTitleConflict::Error`]
/// the first stays; the disagreement is reported separately).
fn replaces(rule: ImportTitleConflict, old: &Candidate, new: &Candidate) -> bool {
    match rule {
        ImportTitleConflict::LowestPosition => {
            sort_key_cmp(&new.position, &old.position).then(new.line.cmp(&old.line))
                == Ordering::Less
        }
        ImportTitleConflict::FirstRow | ImportTitleConflict::Error => new.line < old.line,
    }
}

/// The titles of one group: per language the chosen one, and the lines that disagree with it
/// (only collected for [`ImportTitleConflict::Error`]).
#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct GroupTitles {
    pub chosen: BTreeMap<String, Candidate>,
    pub conflicts: Vec<(usize, String)>,
}

impl GroupTitles {
    /// Adds the title a row offers in `language`.
    pub fn offer(&mut self, rule: ImportTitleConflict, language: &str, new: Candidate) {
        match self.chosen.get(language) {
            None => {
                self.chosen.insert(language.to_string(), new);
            }
            Some(old) if old.title == new.title => {}
            Some(old) => {
                if rule == ImportTitleConflict::Error {
                    let message = format!(
                        "the title in {language} differs from line {} ({:?})",
                        old.line, old.title
                    );
                    self.conflicts.push((new.line, message));
                } else if replaces(rule, old, &new) {
                    self.chosen.insert(language.to_string(), new);
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------------------------
// The entity
// ---------------------------------------------------------------------------------------------

/// A stored item.
#[derive(Debug, Clone, sqlx::FromRow)]
pub struct StoredItem {
    id: Uuid,
    group_id: Uuid,
    sort_key: String,
    price_on_request: bool,
    net: bool,
    indicative: bool,
    hidden: bool,
}

/// What one row writes.
pub struct ItemChange {
    list_id: Uuid,
    product_id: Uuid,
    /// The group path; the groups are found or created when the row is written.
    path: Vec<i32>,
    /// Per level of `path`: whether the file gives that group a title (a group created without
    /// one is untitled).
    titled: Vec<bool>,
    /// The group, when it exists already.
    group_id: Option<Uuid>,
    sort_key: String,
    price_on_request: bool,
    net: bool,
    indicative: bool,
    hidden: bool,
    /// Titles to write on the group (only those that differ from what is stored), carried by the
    /// first row of the group.
    titles: BTreeMap<String, String>,
}

/// A list of the file.
struct ListInfo {
    id: Uuid,
    settings: PriceListSettings,
}

/// A stored group.
struct StoredGroup {
    id: Uuid,
    parent_id: Option<Uuid>,
    sort_order: i32,
    titles: BTreeMap<String, String>,
}

/// The lookups of one run, and what the whole file says about each group.
pub struct ItemContext {
    lists: HashMap<String, ListInfo>,
    products: HashMap<String, Uuid>,
    groups: HashMap<Uuid, Vec<StoredGroup>>,
    /// The title languages in the file.
    languages: Vec<String>,
    /// Per (list, group path): the titles the file gives it.
    titles: HashMap<(Uuid, Vec<i32>), GroupTitles>,
    /// Per (list, group path): the line of its first row, which writes the titles.
    carriers: HashMap<(Uuid, Vec<i32>), usize>,
}

/// The group of `path` among `groups`: `Ok(None)` when (a part of) the path does not exist yet,
/// an error when two siblings share a position.
fn find_group(groups: &[StoredGroup], path: &[i32]) -> Result<Option<Uuid>, String> {
    let mut parent: Option<Uuid> = None;
    for (depth, order) in path.iter().enumerate() {
        let mut found = groups
            .iter()
            .filter(|g| g.parent_id == parent && g.sort_order == *order);
        let Some(first) = found.next() else {
            return Ok(None);
        };
        if found.next().is_some() {
            let at: Vec<String> = path[..=depth].iter().map(i32::to_string).collect();
            return Err(format!(
                "two groups of the list are at position {}; give them different positions in the editor first",
                at.join(".")
            ));
        }
        parent = Some(first.id);
    }
    Ok(parent)
}

/// The group path of `group_id` (the `sort_order`s from the top).
fn path_of(groups: &[StoredGroup], group_id: Uuid) -> Vec<i32> {
    let mut path = Vec::new();
    let mut cursor = Some(group_id);
    while let Some(id) = cursor {
        let Some(g) = groups.iter().find(|g| g.id == id) else {
            break;
        };
        path.push(g.sort_order);
        cursor = g.parent_id;
        if path.len() > MAX_DEPTH {
            break;
        }
    }
    path.reverse();
    path
}

fn split_key(key: &str) -> (&str, &str) {
    key.split_once(KEY_SEPARATOR).unwrap_or((key, ""))
}

fn title_column(language: &str) -> String {
    format!("{GROUP_TITLE}_{language}")
}

/// The title cells of a row with a value: language -> trimmed title.
fn row_titles(row: &Row, languages: &[String]) -> Vec<(String, String)> {
    languages
        .iter()
        .filter_map(|l| {
            let title = row.get(&title_column(l))?.trim();
            (!title.is_empty()).then(|| (l.clone(), title.to_string()))
        })
        .collect()
}

/// list, id, parent, sort_order, titles.
type GroupRow = (
    Uuid,
    Uuid,
    Option<Uuid>,
    i32,
    SqlJson<BTreeMap<String, String>>,
);

async fn load_groups(
    conn: &mut PgConnection,
    company_id: Uuid,
    list_ids: &[Uuid],
) -> AppResult<HashMap<Uuid, Vec<StoredGroup>>> {
    let rows: Vec<GroupRow> = sqlx::query_as(
        "SELECT g.price_list_id, g.id, g.parent_id, g.sort_order,
                COALESCE((SELECT jsonb_object_agg(t.language::text, t.title)
                          FROM pricing.price_list_group_titles t WHERE t.group_id = g.id),
                         '{}'::jsonb)
             FROM pricing.price_list_groups g
             WHERE g.company_id = $1 AND g.price_list_id = ANY($2)",
    )
    .bind(company_id)
    .bind(list_ids)
    .fetch_all(conn)
    .await?;
    let mut out: HashMap<Uuid, Vec<StoredGroup>> = HashMap::new();
    for (list, id, parent_id, sort_order, titles) in rows {
        out.entry(list).or_default().push(StoredGroup {
            id,
            parent_id,
            sort_order,
            titles: titles.0,
        });
    }
    Ok(out)
}

/// Finds or creates the groups of `path` in `list_id` and returns the deepest.
async fn ensure_path(
    conn: &mut PgConnection,
    company_id: Uuid,
    list_id: Uuid,
    path: &[i32],
    titled: &[bool],
) -> AppResult<Uuid> {
    let mut parent: Option<Uuid> = None;
    for (depth, order) in path.iter().enumerate() {
        let found: Option<Uuid> = sqlx::query_scalar(
            "SELECT id FROM pricing.price_list_groups
             WHERE price_list_id = $1 AND parent_id IS NOT DISTINCT FROM $2 AND sort_order = $3
               AND company_id = $4
             ORDER BY id LIMIT 1",
        )
        .bind(list_id)
        .bind(parent)
        .bind(order)
        .bind(company_id)
        .fetch_optional(&mut *conn)
        .await?;
        let id = match found {
            Some(id) => id,
            None => {
                let id = new_id();
                sqlx::query(
                    "INSERT INTO pricing.price_list_groups
                        (id, company_id, price_list_id, parent_id, sort_order, show_title)
                     VALUES ($1, $2, $3, $4, $5, $6)",
                )
                .bind(id)
                .bind(company_id)
                .bind(list_id)
                .bind(parent)
                .bind(order)
                .bind(titled.get(depth).copied().unwrap_or(false))
                .execute(&mut *conn)
                .await?;
                id
            }
        };
        parent = Some(id);
    }
    parent
        .ok_or_else(|| tradocraft_core::AppError::Validation("the position names no group".into()))
}

/// Finds or creates the group, writes its titles and returns its id; marks the list changed.
async fn prepare_group(
    conn: &mut PgConnection,
    user: &CurrentUser,
    change: &ItemChange,
) -> AppResult<Uuid> {
    let group_id = match change.group_id {
        Some(id) => id,
        None => {
            ensure_path(
                conn,
                user.company_id,
                change.list_id,
                &change.path,
                &change.titled,
            )
            .await?
        }
    };
    for (language, title) in &change.titles {
        sqlx::query(
            "INSERT INTO pricing.price_list_group_titles (group_id, company_id, language, title)
             VALUES ($1, $2, $3, $4)
             ON CONFLICT (group_id, language) DO UPDATE SET title = EXCLUDED.title",
        )
        .bind(group_id)
        .bind(user.company_id)
        .bind(language)
        .bind(title)
        .execute(&mut *conn)
        .await?;
    }
    sqlx::query(
        "UPDATE pricing.price_lists SET updated_at = now() WHERE id = $1 AND company_id = $2",
    )
    .bind(change.list_id)
    .bind(user.company_id)
    .execute(&mut *conn)
    .await?;
    Ok(group_id)
}

/// Price list items, keyed by list code and product code.
pub struct PriceListItems;

impl Importable for PriceListItems {
    type Stored = StoredItem;
    type Change = ItemChange;
    type Context = ItemContext;

    const KEY: &'static str = "price_list_items";
    const AUDIT_ENTITY: &'static str = "price_list";
    const READ: Permission = Permission::PriceListsRead;
    const WRITE: Permission = Permission::PriceListsWrite;
    const FILE_STEM: &'static str = "price_list_items";
    const COLUMNS: &'static [Column] = &COLUMNS;
    const KEY_COLUMN: &'static str = "price_list";
    const KEY_COLUMNS: &'static [&'static str] = &["price_list", "product_code"];

    async fn context(
        conn: &mut PgConnection,
        user: &CurrentUser,
        table: &Table,
    ) -> AppResult<ItemContext> {
        let list_codes: Vec<&str> = table
            .rows
            .iter()
            .filter_map(|r| r.get_trimmed("price_list"))
            .collect();
        let lists: Vec<(String, Uuid, SqlJson<PriceListSettings>)> = sqlx::query_as(
            "SELECT code, id, settings FROM pricing.price_lists
             WHERE company_id = $1 AND code = ANY($2)",
        )
        .bind(user.company_id)
        .bind(&list_codes)
        .fetch_all(&mut *conn)
        .await?;
        let lists: HashMap<String, ListInfo> = lists
            .into_iter()
            .map(|(code, id, settings)| {
                (
                    code,
                    ListInfo {
                        id,
                        settings: settings.0,
                    },
                )
            })
            .collect();
        let product_codes: Vec<&str> = table
            .rows
            .iter()
            .filter_map(|r| r.get_trimmed("product_code"))
            .collect();
        let products = sqlx::query_as::<_, (String, Uuid)>(
            "SELECT code, id FROM products.products WHERE code = ANY($1)",
        )
        .bind(&product_codes)
        .fetch_all(&mut *conn)
        .await?
        .into_iter()
        .collect();
        let list_ids: Vec<Uuid> = lists.values().map(|l| l.id).collect();
        let groups = load_groups(conn, user.company_id, &list_ids).await?;
        let languages = family_languages(&table.columns, GROUP_TITLE);

        // What the whole file says about each group: its first row and its titles.
        let mut titles: HashMap<(Uuid, Vec<i32>), GroupTitles> = HashMap::new();
        let mut carriers: HashMap<(Uuid, Vec<i32>), usize> = HashMap::new();
        for row in &table.rows {
            let Some(list) = row.get_trimmed("price_list").and_then(|c| lists.get(c)) else {
                continue;
            };
            let Some(Ok(position)) = row.get_trimmed("position").map(|p| {
                parse_position(
                    p,
                    usize::from(list.settings.import_group_levels),
                    list.settings.import_short_position,
                )
            }) else {
                continue;
            };
            let group = (list.id, position.groups.clone());
            carriers.entry(group.clone()).or_insert(row.line);
            let entry = titles.entry(group).or_default();
            for (language, title) in row_titles(row, &languages) {
                let candidate = Candidate {
                    title,
                    position: position.text(),
                    line: row.line,
                };
                entry.offer(list.settings.import_title_conflict, &language, candidate);
            }
        }
        Ok(ItemContext {
            lists,
            products,
            groups,
            languages,
            titles,
            carriers,
        })
    }

    async fn load(
        conn: &mut PgConnection,
        user: &CurrentUser,
        keys: &[String],
    ) -> AppResult<Vec<(String, StoredItem)>> {
        let (lists, products): (Vec<&str>, Vec<&str>) = keys.iter().map(|k| split_key(k)).unzip();
        // Lock the lists first, as an edit in the editor does: that serialises changes of their
        // group trees.
        sqlx::query(
            "SELECT id FROM pricing.price_lists WHERE company_id = $1 AND code = ANY($2)
             ORDER BY id FOR UPDATE",
        )
        .bind(user.company_id)
        .bind(&lists)
        .execute(&mut *conn)
        .await?;
        #[derive(sqlx::FromRow)]
        struct Found {
            #[sqlx(flatten)]
            item: StoredItem,
            list_code: String,
            product_code: String,
        }
        let found: Vec<Found> = sqlx::query_as(
            "SELECT i.id, i.group_id, i.sort_key, i.price_on_request, i.net, i.indicative, i.hidden,
                    l.code AS list_code, p.code AS product_code
             FROM pricing.price_list_items i
             JOIN pricing.price_lists l ON l.id = i.price_list_id
             JOIN products.products p ON p.id = i.product_id
             WHERE l.company_id = $1
               AND (l.code, p.code) IN (SELECT * FROM unnest($2::text[], $3::text[]))
             ORDER BY i.id
             FOR UPDATE OF i",
        )
        .bind(user.company_id)
        .bind(&lists)
        .bind(&products)
        .fetch_all(conn)
        .await?;
        Ok(found
            .into_iter()
            .map(|f| {
                (
                    format!("{}{KEY_SEPARATOR}{}", f.list_code, f.product_code),
                    f.item,
                )
            })
            .collect())
    }

    fn stored_id(stored: &StoredItem) -> Uuid {
        stored.id
    }

    async fn plan_row(
        _conn: &mut PgConnection,
        _user: &CurrentUser,
        context: &mut ItemContext,
        key: &str,
        current: Option<&StoredItem>,
        row: &Row,
        cells: &mut Cells<'_>,
    ) -> AppResult<ItemChange> {
        let (list_code, product_code) = split_key(key);
        let list = context.lists.get(list_code);
        if list.is_none() {
            cells.error(
                Some("price_list"),
                format!("unknown price list {list_code:?}"),
            );
        }
        let product_id = context.products.get(product_code).copied();
        if product_id.is_none() {
            cells.error(
                Some("product_code"),
                format!("unknown product {product_code:?}"),
            );
        }
        let mut change = ItemChange {
            list_id: list.map(|l| l.id).unwrap_or_default(),
            product_id: product_id.unwrap_or_default(),
            path: Vec::new(),
            titled: Vec::new(),
            group_id: current.map(|c| c.group_id),
            sort_key: current.map(|c| c.sort_key.clone()).unwrap_or_default(),
            price_on_request: current.is_some_and(|c| c.price_on_request),
            net: current.is_some_and(|c| c.net),
            indicative: current.is_some_and(|c| c.indicative),
            hidden: current.is_some_and(|c| c.hidden),
            titles: BTreeMap::new(),
        };
        cells
            .boolean("price_on_request")
            .apply(&mut change.price_on_request);
        cells.boolean("net").apply(&mut change.net);
        cells.boolean("indicative").apply(&mut change.indicative);
        cells.boolean("hidden").apply(&mut change.hidden);
        let titles = row_titles(row, &context.languages);
        for (language, title) in &titles {
            if title.chars().count() > MAX_TITLE {
                cells.error(
                    Some(&title_column(language)),
                    format!("a group title is longer than {MAX_TITLE} characters"),
                );
            }
        }
        let Some(list) = list else {
            return Ok(change);
        };
        let groups = context
            .groups
            .get(&list.id)
            .map(Vec::as_slice)
            .unwrap_or_default();
        let position = match cells.trimmed("position") {
            Cell::Value(p) => {
                match parse_position(
                    &p,
                    usize::from(list.settings.import_group_levels),
                    list.settings.import_short_position,
                ) {
                    Ok(p) => Some(p),
                    Err(m) => {
                        cells.error(Some("position"), m);
                        return Ok(change);
                    }
                }
            }
            _ => None,
        };
        let Some(position) = position else {
            // Without a position the item stays where it is; a new one needs one.
            match current {
                Some(c) => {
                    change.path = path_of(groups, c.group_id);
                    if !titles.is_empty() {
                        cells.error(
                            Some("position"),
                            "group titles need the position of the group",
                        );
                    }
                }
                None => cells.error(Some("position"), "position is required for a new item"),
            }
            return Ok(change);
        };
        change.group_id = match find_group(groups, &position.groups) {
            Ok(found) => found,
            Err(m) => {
                cells.error(Some("position"), m);
                return Ok(change);
            }
        };
        change.sort_key = position.sort_key.clone();
        change.titled = (1..=position.groups.len())
            .map(|depth| {
                context
                    .titles
                    .get(&(list.id, position.groups[..depth].to_vec()))
                    .is_some_and(|t| !t.chosen.is_empty())
            })
            .collect();
        let group = (list.id, position.groups.clone());
        change.path = position.groups;
        if let Some(group_titles) = context.titles.get(&group) {
            for (line, message) in &group_titles.conflicts {
                if *line == row.line {
                    cells.error(Some("position"), message.clone());
                }
            }
            // The group's first row writes its titles, once.
            if context.carriers.get(&group) == Some(&row.line) {
                let stored = change
                    .group_id
                    .and_then(|id| groups.iter().find(|g| g.id == id))
                    .map(|g| &g.titles);
                for (language, chosen) in &group_titles.chosen {
                    if stored.and_then(|t| t.get(language)) != Some(&chosen.title) {
                        change.titles.insert(language.clone(), chosen.title.clone());
                    }
                }
            }
        }
        Ok(change)
    }

    fn unchanged(stored: &StoredItem, change: &ItemChange) -> bool {
        change.group_id == Some(stored.group_id)
            && stored.sort_key == change.sort_key
            && stored.price_on_request == change.price_on_request
            && stored.net == change.net
            && stored.indicative == change.indicative
            && stored.hidden == change.hidden
            && change.titles.is_empty()
    }

    async fn create(
        conn: &mut PgConnection,
        user: &CurrentUser,
        id: Uuid,
        change: &ItemChange,
    ) -> AppResult<()> {
        let group_id = prepare_group(conn, user, change).await?;
        sqlx::query(
            "INSERT INTO pricing.price_list_items
                (id, company_id, price_list_id, product_id, group_id, sort_key, price_on_request,
                 net, indicative, hidden)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)",
        )
        .bind(id)
        .bind(user.company_id)
        .bind(change.list_id)
        .bind(change.product_id)
        .bind(group_id)
        .bind(&change.sort_key)
        .bind(change.price_on_request)
        .bind(change.net)
        .bind(change.indicative)
        .bind(change.hidden)
        .execute(conn)
        .await?;
        Ok(())
    }

    async fn update(
        conn: &mut PgConnection,
        user: &CurrentUser,
        id: Uuid,
        change: &ItemChange,
    ) -> AppResult<()> {
        let group_id = prepare_group(conn, user, change).await?;
        sqlx::query(
            "UPDATE pricing.price_list_items SET group_id = $2, sort_key = $3,
                    price_on_request = $4, net = $5, indicative = $6, hidden = $7
             WHERE id = $1 AND company_id = $8",
        )
        .bind(id)
        .bind(group_id)
        .bind(&change.sort_key)
        .bind(change.price_on_request)
        .bind(change.net)
        .bind(change.indicative)
        .bind(change.hidden)
        .bind(user.company_id)
        .execute(conn)
        .await?;
        Ok(())
    }

    /// The events of the editor, on the list.
    fn audit_event(id: Uuid, _key: &str, change: &ItemChange, created: bool) -> AuditEvent {
        let mut data = serde_json::Map::new();
        data.insert("item_id".into(), id.to_string().into());
        if created {
            data.insert("product_id".into(), change.product_id.to_string().into());
        }
        if !change.titles.is_empty() {
            data.insert("group_titles".into(), serde_json::json!(change.titles));
        }
        AuditEvent {
            entity: "price_list",
            id: change.list_id,
            action: if created {
                "item_added"
            } else {
                "item_updated"
            },
            data,
        }
    }

    /// Every item of every list of the company, by list and position. The position is the group
    /// path and the sort key; the titles are those of the item's group.
    async fn export(pool: &PgPool, user: &CurrentUser) -> AppResult<ExportTable> {
        let mut conn = pool.acquire().await?;
        let lists: Vec<(Uuid, String)> = sqlx::query_as(
            "SELECT id, code FROM pricing.price_lists WHERE company_id = $1 ORDER BY code",
        )
        .bind(user.company_id)
        .fetch_all(&mut *conn)
        .await?;
        let ids: Vec<Uuid> = lists.iter().map(|l| l.0).collect();
        let groups = load_groups(&mut conn, user.company_id, &ids).await?;
        #[derive(sqlx::FromRow)]
        struct Item {
            price_list_id: Uuid,
            product_code: String,
            #[sqlx(flatten)]
            item: StoredItem,
        }
        let items: Vec<Item> = sqlx::query_as(
            "SELECT i.price_list_id, p.code AS product_code, i.id, i.group_id, i.sort_key,
                    i.price_on_request, i.net, i.indicative, i.hidden
             FROM pricing.price_list_items i JOIN products.products p ON p.id = i.product_id
             WHERE i.company_id = $1",
        )
        .bind(user.company_id)
        .fetch_all(&mut *conn)
        .await?;
        let mut languages: Vec<String> = groups
            .values()
            .flatten()
            .flat_map(|g| g.titles.keys().cloned())
            .filter(|l| family_language(&title_column(l), GROUP_TITLE).is_some())
            .collect();
        languages.sort();
        languages.dedup();

        let mut rows: Vec<(usize, String, String, Vec<CellValue>)> = Vec::new();
        for i in &items {
            let Some(list_index) = lists.iter().position(|l| l.0 == i.price_list_id) else {
                continue;
            };
            let list_groups = groups
                .get(&i.price_list_id)
                .map(Vec::as_slice)
                .unwrap_or_default();
            let position = Position {
                groups: path_of(list_groups, i.item.group_id),
                sort_key: i.item.sort_key.clone(),
            }
            .text();
            let titles = list_groups
                .iter()
                .find(|g| g.id == i.item.group_id)
                .map(|g| &g.titles);
            let mut cells = vec![
                CellValue::text(&lists[list_index].1),
                CellValue::text(&i.product_code),
                CellValue::text(&position),
            ];
            for language in &languages {
                cells.push(CellValue::text(
                    titles
                        .and_then(|t| t.get(language))
                        .cloned()
                        .unwrap_or_default(),
                ));
            }
            cells.extend([
                CellValue::Bool(i.item.price_on_request),
                CellValue::Bool(i.item.net),
                CellValue::Bool(i.item.indicative),
                CellValue::Bool(i.item.hidden),
            ]);
            rows.push((list_index, position, i.product_code.clone(), cells));
        }
        rows.sort_by(|a, b| {
            a.0.cmp(&b.0)
                .then_with(|| sort_key_cmp(&a.1, &b.1))
                .then_with(|| a.2.cmp(&b.2))
        });
        let mut header: Vec<String> = vec![
            "price_list".into(),
            "product_code".into(),
            "position".into(),
        ];
        header.extend(languages.iter().map(|l| title_column(l)));
        header.extend(["price_on_request", "net", "indicative", "hidden"].map(String::from));
        Ok(ExportTable {
            header,
            rows: rows.into_iter().map(|r| r.3).collect(),
        })
    }
}

/// The price list items' handle for the import registry and the background worker.
pub fn price_list_items_import() -> ImportEntity {
    ImportEntity::of::<PriceListItems>()
}

#[cfg(test)]
mod tests {
    use super::*;

    const SHALLOW: ImportShortPosition = ImportShortPosition::ShallowerGroup;

    fn pos(groups: &[i32], sort_key: &str) -> Position {
        Position {
            groups: groups.to_vec(),
            sort_key: sort_key.into(),
        }
    }

    #[test]
    fn a_position_is_split_into_groups_and_a_sort_key() {
        assert_eq!(parse_position("2.3.10", 2, SHALLOW), Ok(pos(&[2, 3], "10")));
        assert_eq!(
            parse_position(" 2.3.1.b ", 2, SHALLOW),
            Ok(pos(&[2, 3], "1.b"))
        );
        assert_eq!(parse_position("02.3", 2, SHALLOW), Ok(pos(&[2, 3], "")));
        assert_eq!(parse_position("4.1.7", 3, SHALLOW), Ok(pos(&[4, 1, 7], "")));
        assert_eq!(
            parse_position("4.1.7.x", 1, SHALLOW),
            Ok(pos(&[4], "1.7.x"))
        );
        // Dots at either end are dropped.
        assert_eq!(parse_position("0.", 1, SHALLOW), Ok(pos(&[0], "")));
        assert_eq!(parse_position(".5.6.", 2, SHALLOW), Ok(pos(&[5, 6], "")));
        assert_eq!(pos(&[2, 3], "010").text(), "2.3.010");
        assert_eq!(pos(&[2], "").text(), "2");
    }

    #[test]
    fn a_short_position_follows_the_setting() {
        assert_eq!(parse_position("3", 2, SHALLOW), Ok(pos(&[3], "")));
        let e = parse_position("3", 2, ImportShortPosition::Error).unwrap_err();
        assert!(e.contains("at least 2 segments"), "{e}");
        assert_eq!(
            parse_position("3.4", 2, ImportShortPosition::Error),
            Ok(pos(&[3, 4], ""))
        );
    }

    #[test]
    fn bad_positions_are_refused() {
        for (raw, part) in [
            ("", "empty"),
            (" . ", "empty"),
            ("1..2", "empty segment"),
            ("A.2", "not a whole number"),
            ("1.-2", "not a whole number"),
            ("1.+2", "not a whole number"),
            ("99999999999.1", "not a whole number"),
            ("1.2.a-b", "letters and digits"),
            ("1.2.a b", "letters and digits"),
        ] {
            let e = parse_position(raw, 2, SHALLOW).unwrap_err();
            assert!(e.contains(part), "{raw:?}: {e}");
        }
        let long = format!("1.2.{}", "x".repeat(MAX_SORT_KEY + 1));
        assert!(parse_position(&long, 2, SHALLOW).is_err());
    }

    fn offer(titles: &mut GroupTitles, rule: ImportTitleConflict, line: usize, p: &str, t: &str) {
        titles.offer(
            rule,
            "nl",
            Candidate {
                title: t.into(),
                position: p.into(),
                line,
            },
        );
    }

    #[test]
    fn the_lowest_position_gives_the_title_by_default() {
        let rule = ImportTitleConflict::LowestPosition;
        let mut t = GroupTitles::default();
        offer(&mut t, rule, 2, "1.2.10", "Late");
        offer(&mut t, rule, 3, "1.2.9", "Early");
        offer(&mut t, rule, 4, "1.2.9", "Same position, later line");
        offer(&mut t, rule, 5, "1.2.b", "Text after numbers");
        assert_eq!(t.chosen["nl"].title, "Early");
        assert!(t.conflicts.is_empty());
    }

    #[test]
    fn the_first_row_or_an_error_when_the_list_says_so() {
        let rule = ImportTitleConflict::FirstRow;
        let mut t = GroupTitles::default();
        offer(&mut t, rule, 2, "1.2.10", "First");
        offer(&mut t, rule, 3, "1.2.1", "Lower");
        assert_eq!(t.chosen["nl"].title, "First");

        let rule = ImportTitleConflict::Error;
        let mut t = GroupTitles::default();
        offer(&mut t, rule, 2, "1.2.10", "First");
        offer(&mut t, rule, 3, "1.2.1", "First");
        offer(&mut t, rule, 4, "1.2.1", "Other");
        assert_eq!(t.chosen["nl"].title, "First");
        assert_eq!(t.conflicts.len(), 1);
        assert_eq!(t.conflicts[0].0, 4);
        assert!(t.conflicts[0].1.contains("line 2"));
    }

    fn g(id: u128, parent: Option<u128>, sort_order: i32) -> StoredGroup {
        StoredGroup {
            id: Uuid::from_u128(id),
            parent_id: parent.map(Uuid::from_u128),
            sort_order,
            titles: BTreeMap::new(),
        }
    }

    #[test]
    fn groups_are_found_by_their_sort_order_among_siblings() {
        let groups = [
            g(1, None, 1),
            g(2, Some(1), 3),
            g(3, None, 2),
            g(4, Some(3), 3),
        ];
        assert_eq!(find_group(&groups, &[1, 3]), Ok(Some(Uuid::from_u128(2))));
        assert_eq!(find_group(&groups, &[2, 3]), Ok(Some(Uuid::from_u128(4))));
        assert_eq!(find_group(&groups, &[2]), Ok(Some(Uuid::from_u128(3))));
        assert_eq!(find_group(&groups, &[1, 4]), Ok(None));
        assert_eq!(find_group(&groups, &[5, 1]), Ok(None));
        assert_eq!(path_of(&groups, Uuid::from_u128(4)), [2, 3]);
        let twins = [g(1, None, 1), g(2, None, 1)];
        assert!(find_group(&twins, &[1]).unwrap_err().contains("position 1"));
    }
}
