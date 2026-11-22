//! Product relation rules: compatible, incompatible and suggested, plus computed "often bought
//! together" data (ADR 0027).
//!
//! A rule side is one product or a whole family. [`evaluate`] is pure: it turns the products of a
//! quotation or order into conflicts (explicit `incompatible` rules only) and suggestions (manual
//! `suggested` rules first, computed co-occurrence below them). Sales calls [`check_products`]
//! instead of reading these tables.

use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};

use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::Json;
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection};
use tradocraft_core::{audit, new_id, AppError, AppResult, AppState, CurrentUser, Permission};
use utoipa::{IntoParams, ToSchema};
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

const KINDS: [&str; 3] = ["compatible", "incompatible", "suggested"];

// ------------------------------------------------------------------------------------------
// Configuration
// ------------------------------------------------------------------------------------------

/// Default: a pair needs at least this many orders together to be suggested.
pub const DEFAULT_MIN_ORDERS_TOGETHER: i64 = 3;
/// Default: share of the orders with product X that also contain Y.
pub const DEFAULT_MIN_CONFIDENCE: f64 = 0.3;
/// Default: at most this many products suggested for one family side.
pub const DEFAULT_MAX_FAMILY_EXPANSION: usize = 5;
/// Default: at most this many computed suggestions per evaluation.
pub const DEFAULT_MAX_COMPUTED: usize = 5;

/// Thresholds of the suggestions. Defaults can be overridden with the environment variables
/// `RELATIONS_MIN_ORDERS_TOGETHER` and `RELATIONS_MIN_CONFIDENCE`.
#[derive(Debug, Clone, PartialEq)]
pub struct RelationConfig {
    pub min_orders_together: i64,
    pub min_confidence: f64,
    pub max_family_expansion: usize,
    pub max_computed: usize,
}

impl Default for RelationConfig {
    fn default() -> Self {
        Self {
            min_orders_together: DEFAULT_MIN_ORDERS_TOGETHER,
            min_confidence: DEFAULT_MIN_CONFIDENCE,
            max_family_expansion: DEFAULT_MAX_FAMILY_EXPANSION,
            max_computed: DEFAULT_MAX_COMPUTED,
        }
    }
}

impl RelationConfig {
    pub fn from_env() -> Self {
        let mut c = Self::default();
        if let Some(v) = std::env::var("RELATIONS_MIN_ORDERS_TOGETHER")
            .ok()
            .and_then(|v| v.trim().parse().ok())
        {
            c.min_orders_together = v;
        }
        if let Some(v) = std::env::var("RELATIONS_MIN_CONFIDENCE")
            .ok()
            .and_then(|v| v.trim().parse::<f64>().ok())
            .filter(|v| (0.0..=1.0).contains(v))
        {
            c.min_confidence = v;
        }
        c
    }
}

// ------------------------------------------------------------------------------------------
// Data
// ------------------------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct ProductRelation {
    pub id: Uuid,
    /// compatible | incompatible | suggested
    pub kind: String,
    pub a_product_id: Option<Uuid>,
    pub a_product_code: Option<String>,
    pub a_family_id: Option<Uuid>,
    pub a_family_code: Option<String>,
    pub b_product_id: Option<Uuid>,
    pub b_product_code: Option<String>,
    pub b_family_id: Option<Uuid>,
    pub b_family_code: Option<String>,
    /// The rule also applies with the sides swapped.
    pub bidirectional: bool,
    /// 1 to 100, the weight of a suggested rule.
    pub strength: i32,
    pub note: String,
    pub active: bool,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct ProductRelationInput {
    /// compatible | incompatible | suggested
    pub kind: String,
    /// Exactly one of `a_product_id` and `a_family_id`.
    pub a_product_id: Option<Uuid>,
    pub a_family_id: Option<Uuid>,
    /// Exactly one of `b_product_id` and `b_family_id`.
    pub b_product_id: Option<Uuid>,
    pub b_family_id: Option<Uuid>,
    #[serde(default = "default_true")]
    pub bidirectional: bool,
    #[serde(default = "default_strength")]
    pub strength: i32,
    #[serde(default)]
    pub note: String,
    #[serde(default = "default_true")]
    pub active: bool,
}

fn default_true() -> bool {
    true
}

fn default_strength() -> i32 {
    50
}

const SELECT: &str = "SELECT r.id, r.kind,
        r.a_product_id, ap.code AS a_product_code, r.a_family_id, af.code AS a_family_code,
        r.b_product_id, bp.code AS b_product_code, r.b_family_id, bf.code AS b_family_code,
        r.bidirectional, r.strength, r.note, r.active
     FROM products.product_relations r
     LEFT JOIN products.products ap ON ap.id = r.a_product_id
     LEFT JOIN products.product_families af ON af.id = r.a_family_id
     LEFT JOIN products.products bp ON bp.id = r.b_product_id
     LEFT JOIN products.product_families bf ON bf.id = r.b_family_id";

/// A product of the set that is being checked (quotation or order lines).
#[derive(Debug, Clone, PartialEq, FromRow)]
pub struct SetProduct {
    pub id: Uuid,
    pub code: String,
    pub name: String,
    pub family_id: Option<Uuid>,
}

/// A product that may be suggested.
#[derive(Debug, Clone, PartialEq, FromRow)]
pub struct CatalogProduct {
    pub id: Uuid,
    pub code: String,
    pub name: String,
    pub family_id: Option<Uuid>,
    pub active: bool,
}

/// One row of `product_cooccurrence`, `a < b`.
#[derive(Debug, Clone, PartialEq, FromRow)]
pub struct Cooccurrence {
    pub product_a_id: Uuid,
    pub product_b_id: Uuid,
    pub orders_together: i32,
    pub orders_with_a: i32,
    pub orders_with_b: i32,
}

/// Two products of the set that an `incompatible` rule excludes.
#[derive(Debug, Clone, PartialEq, Serialize, ToSchema)]
pub struct Conflict {
    pub relation_id: Uuid,
    pub product_a_id: Uuid,
    pub product_a_code: String,
    pub product_b_id: Uuid,
    pub product_b_code: String,
    pub note: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum SuggestionReason {
    /// A manual `suggested` rule.
    Rule,
    /// Computed from past orders.
    OftenBoughtTogether,
}

#[derive(Debug, Clone, PartialEq, Serialize, ToSchema)]
pub struct Suggestion {
    pub product_id: Uuid,
    pub product_code: String,
    pub product_name: String,
    pub reason: SuggestionReason,
    /// 1 to 100, from the manual rule.
    pub strength: Option<i32>,
    /// 0 to 1, share of the orders with the other product that also contain this one.
    pub confidence: Option<f64>,
    /// The product of the set that triggered the suggestion.
    pub because_of_code: String,
    /// Note of the manual rule.
    pub note: String,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize, ToSchema)]
pub struct Evaluation {
    pub conflicts: Vec<Conflict>,
    pub suggestions: Vec<Suggestion>,
}

// ------------------------------------------------------------------------------------------
// Pure evaluation
// ------------------------------------------------------------------------------------------

fn side_matches(product: Option<Uuid>, family: Option<Uuid>, p: &SetProduct) -> bool {
    product == Some(p.id) || (family.is_some() && family == p.family_id)
}

/// The rule links `x` (side A) to `y` (side B).
fn forward(r: &ProductRelation, x: &SetProduct, y: &SetProduct) -> bool {
    side_matches(r.a_product_id, r.a_family_id, x) && side_matches(r.b_product_id, r.b_family_id, y)
}

/// Rule specificity: product-vs-product beats product-vs-family beats family-vs-family.
fn specificity(r: &ProductRelation) -> u8 {
    u8::from(r.a_product_id.is_some()) + u8::from(r.b_product_id.is_some())
}

fn matches_pair(r: &ProductRelation, x: &SetProduct, y: &SetProduct) -> bool {
    forward(r, x, y) || (r.bidirectional && forward(r, y, x))
}

/// Finds the explicit incompatibilities between the products of the set. Both products are present,
/// so the direction of a rule does not matter here. Absence of a rule is never a conflict, and
/// `compatible` rules never produce one.
fn conflicts_of(set: &[SetProduct], relations: &[ProductRelation]) -> Vec<Conflict> {
    let mut rules: Vec<&ProductRelation> = relations
        .iter()
        .filter(|r| r.active && r.kind == "incompatible")
        .collect();
    rules.sort_by_key(|r| (std::cmp::Reverse(specificity(r)), r.id));
    let mut out = Vec::new();
    for (i, x) in set.iter().enumerate() {
        for y in &set[i + 1..] {
            if x.id == y.id {
                continue;
            }
            let hit = rules
                .iter()
                .find(|r| forward(r, x, y) || forward(r, y, x))
                .copied();
            if let Some(r) = hit {
                out.push(Conflict {
                    relation_id: r.id,
                    product_a_id: x.id,
                    product_a_code: x.code.clone(),
                    product_b_id: y.id,
                    product_b_code: y.code.clone(),
                    note: r.note.clone(),
                });
            }
        }
    }
    out
}

/// Turns the products of a quotation or order into conflicts and suggestions.
///
/// * Rules apply product-vs-product, product-vs-family and family-vs-family; a `bidirectional`
///   rule also works with the sides swapped.
/// * Conflicts come from explicit `incompatible` rules only.
/// * `suggested` rules suggest the other side's active products (a family side expands to at most
///   `max_family_expansion` of them, by code) with the rule's strength.
/// * Computed co-occurrence suggests the partner of a pair when `orders_together` and the
///   confidence (together / orders with the product in the set) reach the thresholds. It is
///   placed after all manual suggestions, never repeats one, and never produces conflicts.
/// * Nothing already in the set, inactive, or incompatible with the set is suggested.
pub fn evaluate(
    set: &[SetProduct],
    relations: &[ProductRelation],
    cooccurrence: &[Cooccurrence],
    catalogue: &[CatalogProduct],
    config: &RelationConfig,
) -> Evaluation {
    let in_set: HashSet<Uuid> = set.iter().map(|p| p.id).collect();
    let conflicts = conflicts_of(set, relations);

    // Candidates that clash with a member of the set are not suggested.
    let clashes = |c: &CatalogProduct| -> bool {
        let cp = SetProduct {
            id: c.id,
            code: c.code.clone(),
            name: c.name.clone(),
            family_id: c.family_id,
        };
        set.iter().any(|m| {
            relations
                .iter()
                .any(|r| r.active && r.kind == "incompatible" && matches_pair(r, m, &cp))
        })
    };
    let by_id: HashMap<Uuid, &CatalogProduct> = catalogue.iter().map(|c| (c.id, c)).collect();

    // Manual suggestions: best strength per target.
    let mut manual: BTreeMap<Uuid, Suggestion> = BTreeMap::new();
    let mut rules: Vec<&ProductRelation> = relations
        .iter()
        .filter(|r| r.active && r.kind == "suggested")
        .collect();
    rules.sort_by_key(|r| r.id);
    for r in rules {
        for p in set {
            // (matches the trigger side, target side product / family)
            let mut sides = Vec::new();
            if side_matches(r.a_product_id, r.a_family_id, p) {
                sides.push((r.b_product_id, r.b_family_id));
            }
            if r.bidirectional && side_matches(r.b_product_id, r.b_family_id, p) {
                sides.push((r.a_product_id, r.a_family_id));
            }
            for (tp, tf) in sides {
                let mut targets: Vec<&CatalogProduct> = match (tp, tf) {
                    (Some(id), _) => by_id.get(&id).copied().into_iter().collect(),
                    (None, Some(f)) => {
                        let mut v: Vec<&CatalogProduct> = catalogue
                            .iter()
                            .filter(|c| {
                                c.active && c.family_id == Some(f) && !in_set.contains(&c.id)
                            })
                            .collect();
                        v.sort_by(|a, b| a.code.cmp(&b.code));
                        v.truncate(config.max_family_expansion);
                        v
                    }
                    _ => vec![],
                };
                targets.retain(|c| c.active && !in_set.contains(&c.id) && !clashes(c));
                for c in targets {
                    let better = manual
                        .get(&c.id)
                        .is_none_or(|s| s.strength.unwrap_or(0) < r.strength);
                    if better {
                        manual.insert(
                            c.id,
                            Suggestion {
                                product_id: c.id,
                                product_code: c.code.clone(),
                                product_name: c.name.clone(),
                                reason: SuggestionReason::Rule,
                                strength: Some(r.strength),
                                confidence: None,
                                because_of_code: p.code.clone(),
                                note: r.note.clone(),
                            },
                        );
                    }
                }
            }
        }
    }
    let mut suggestions: Vec<Suggestion> = manual.into_values().collect();
    suggestions.sort_by(|a, b| {
        b.strength
            .cmp(&a.strength)
            .then_with(|| a.product_code.cmp(&b.product_code))
    });

    // Computed suggestions: strictly after the manual ones, never a repeat.
    let manual_ids: HashSet<Uuid> = suggestions.iter().map(|s| s.product_id).collect();
    let mut computed: BTreeMap<Uuid, Suggestion> = BTreeMap::new();
    for c in cooccurrence {
        if i64::from(c.orders_together) < config.min_orders_together {
            continue;
        }
        for (trigger, target, with_trigger) in [
            (c.product_a_id, c.product_b_id, c.orders_with_a),
            (c.product_b_id, c.product_a_id, c.orders_with_b),
        ] {
            let Some(p) = set.iter().find(|p| p.id == trigger) else {
                continue;
            };
            if with_trigger <= 0 || in_set.contains(&target) || manual_ids.contains(&target) {
                continue;
            }
            let confidence = f64::from(c.orders_together) / f64::from(with_trigger);
            if confidence < config.min_confidence {
                continue;
            }
            let Some(cand) = by_id.get(&target).copied().filter(|c| c.active) else {
                continue;
            };
            if clashes(cand) {
                continue;
            }
            let better = computed
                .get(&target)
                .is_none_or(|s| s.confidence.unwrap_or(0.0) < confidence);
            if better {
                computed.insert(
                    target,
                    Suggestion {
                        product_id: cand.id,
                        product_code: cand.code.clone(),
                        product_name: cand.name.clone(),
                        reason: SuggestionReason::OftenBoughtTogether,
                        strength: None,
                        confidence: Some(confidence),
                        because_of_code: p.code.clone(),
                        note: String::new(),
                    },
                );
            }
        }
    }
    let mut computed: Vec<Suggestion> = computed.into_values().collect();
    computed.sort_by(|a, b| {
        b.confidence
            .partial_cmp(&a.confidence)
            .unwrap_or(std::cmp::Ordering::Equal)
            .then_with(|| a.product_code.cmp(&b.product_code))
    });
    computed.truncate(config.max_computed);
    suggestions.extend(computed);

    Evaluation {
        conflicts,
        suggestions,
    }
}

/// Counts, per unordered pair of products, the orders that contain both. Every inner vector is the
/// product set of one order; duplicates inside an order count once. Pairs are returned with
/// `a < b`.
pub fn count_pairs(orders: &[Vec<Uuid>]) -> Vec<Cooccurrence> {
    let mut single: HashMap<Uuid, i32> = HashMap::new();
    let mut pairs: BTreeMap<(Uuid, Uuid), i32> = BTreeMap::new();
    for order in orders {
        let set: BTreeSet<Uuid> = order.iter().copied().collect();
        let ids: Vec<Uuid> = set.into_iter().collect();
        for (i, a) in ids.iter().enumerate() {
            *single.entry(*a).or_default() += 1;
            for b in &ids[i + 1..] {
                *pairs.entry((*a, *b)).or_default() += 1;
            }
        }
    }
    pairs
        .into_iter()
        .map(|((a, b), together)| Cooccurrence {
            product_a_id: a,
            product_b_id: b,
            orders_together: together,
            orders_with_a: single[&a],
            orders_with_b: single[&b],
        })
        .collect()
}

// ------------------------------------------------------------------------------------------
// Database
// ------------------------------------------------------------------------------------------

/// Replaces the content of `product_cooccurrence` in one transaction.
pub async fn replace_cooccurrence(db: &sqlx::PgPool, pairs: &[Cooccurrence]) -> AppResult<usize> {
    let mut tx = db.begin().await?;
    sqlx::query("DELETE FROM products.product_cooccurrence")
        .execute(&mut *tx)
        .await?;
    for chunk in pairs.chunks(2000) {
        let a: Vec<Uuid> = chunk.iter().map(|c| c.product_a_id).collect();
        let b: Vec<Uuid> = chunk.iter().map(|c| c.product_b_id).collect();
        let t: Vec<i32> = chunk.iter().map(|c| c.orders_together).collect();
        let wa: Vec<i32> = chunk.iter().map(|c| c.orders_with_a).collect();
        let wb: Vec<i32> = chunk.iter().map(|c| c.orders_with_b).collect();
        sqlx::query(
            "INSERT INTO products.product_cooccurrence
                (product_a_id, product_b_id, orders_together, orders_with_a, orders_with_b)
             SELECT * FROM unnest($1::uuid[], $2::uuid[], $3::int[], $4::int[], $5::int[])",
        )
        .bind(a)
        .bind(b)
        .bind(t)
        .bind(wa)
        .bind(wb)
        .execute(&mut *tx)
        .await?;
    }
    tx.commit().await?;
    Ok(pairs.len())
}

/// Loads everything [`evaluate`] needs for a set of products and runs it.
pub async fn check_products(
    conn: &mut PgConnection,
    product_ids: &[Uuid],
) -> AppResult<Evaluation> {
    if product_ids.is_empty() {
        return Ok(Evaluation::default());
    }
    let set: Vec<SetProduct> = sqlx::query_as(
        "SELECT p.id, p.code, p.name, p.family_id FROM products.products p
         JOIN unnest($1::uuid[]) WITH ORDINALITY AS u(id, ord) ON u.id = p.id ORDER BY u.ord",
    )
    .bind(product_ids)
    .fetch_all(&mut *conn)
    .await?;
    let families: Vec<Uuid> = set.iter().filter_map(|p| p.family_id).collect();
    let relations: Vec<ProductRelation> = sqlx::query_as(sqlx::AssertSqlSafe(format!(
        "{SELECT} WHERE r.active AND (
            r.a_product_id = ANY($1) OR r.b_product_id = ANY($1)
            OR r.a_family_id = ANY($2) OR r.b_family_id = ANY($2))"
    )))
    .bind(product_ids)
    .bind(&families)
    .fetch_all(&mut *conn)
    .await?;
    let cooccurrence: Vec<Cooccurrence> = sqlx::query_as(
        "SELECT product_a_id, product_b_id, orders_together, orders_with_a, orders_with_b
         FROM products.product_cooccurrence
         WHERE product_a_id = ANY($1) OR product_b_id = ANY($1)",
    )
    .bind(product_ids)
    .fetch_all(&mut *conn)
    .await?;
    // Candidates: other sides of the rules, family members of those, and co-occurrence partners.
    let mut wanted: BTreeSet<Uuid> = BTreeSet::new();
    let mut wanted_families: BTreeSet<Uuid> = BTreeSet::new();
    for r in &relations {
        wanted.extend(r.a_product_id);
        wanted.extend(r.b_product_id);
        wanted_families.extend(r.a_family_id);
        wanted_families.extend(r.b_family_id);
    }
    for c in &cooccurrence {
        wanted.insert(c.product_a_id);
        wanted.insert(c.product_b_id);
    }
    // The family members come with a limit per family so a huge family cannot flood the query:
    // evaluate() only uses the first few by code anyway (plus the set members to skip).
    let wanted: Vec<Uuid> = wanted.into_iter().collect();
    let wanted_families: Vec<Uuid> = wanted_families.into_iter().collect();
    let cfg = RelationConfig::from_env();
    let catalogue: Vec<CatalogProduct> = sqlx::query_as(
        "SELECT id, code, name, family_id, active FROM products.products WHERE id = ANY($1)
         UNION
         SELECT id, code, name, family_id, active FROM (
            SELECT p.*, row_number() OVER (PARTITION BY p.family_id ORDER BY p.code) AS rn
            FROM products.products p
            WHERE p.active AND p.family_id = ANY($2) AND p.id <> ALL($3)) m
         WHERE rn <= $4",
    )
    .bind(&wanted)
    .bind(&wanted_families)
    .bind(product_ids)
    .bind(i64::try_from(cfg.max_family_expansion).unwrap_or(5))
    .fetch_all(&mut *conn)
    .await?;
    Ok(evaluate(&set, &relations, &cooccurrence, &catalogue, &cfg))
}

// ------------------------------------------------------------------------------------------
// Routes
// ------------------------------------------------------------------------------------------

async fn load(db: &mut PgConnection, id: Uuid) -> AppResult<ProductRelation> {
    sqlx::query_as(sqlx::AssertSqlSafe(format!("{SELECT} WHERE r.id = $1")))
        .bind(id)
        .fetch_optional(db)
        .await?
        .ok_or(AppError::NotFound("product relation"))
}

fn validate(input: &ProductRelationInput) -> AppResult<()> {
    if !KINDS.contains(&input.kind.as_str()) {
        return Err(AppError::Validation(format!(
            "kind must be one of {}",
            KINDS.join(", ")
        )));
    }
    if input.a_product_id.is_some() == input.a_family_id.is_some() {
        return Err(AppError::Validation(
            "side A needs exactly one of a_product_id and a_family_id".into(),
        ));
    }
    if input.b_product_id.is_some() == input.b_family_id.is_some() {
        return Err(AppError::Validation(
            "side B needs exactly one of b_product_id and b_family_id".into(),
        ));
    }
    if input.a_product_id.is_some() && input.a_product_id == input.b_product_id {
        return Err(AppError::Validation(
            "a product cannot be related to itself".into(),
        ));
    }
    if !(1..=100).contains(&input.strength) {
        return Err(AppError::Validation(
            "strength must be between 1 and 100".into(),
        ));
    }
    Ok(())
}

/// The referenced products and families exist, and the mirrored rule does not exist yet.
async fn check_references(
    conn: &mut PgConnection,
    input: &ProductRelationInput,
    own_id: Option<Uuid>,
) -> AppResult<()> {
    for id in [input.a_product_id, input.b_product_id]
        .into_iter()
        .flatten()
    {
        let ok: bool =
            sqlx::query_scalar("SELECT EXISTS (SELECT 1 FROM products.products WHERE id = $1)")
                .bind(id)
                .fetch_one(&mut *conn)
                .await?;
        if !ok {
            return Err(AppError::Validation(format!("unknown product {id}")));
        }
    }
    for id in [input.a_family_id, input.b_family_id].into_iter().flatten() {
        let ok: bool = sqlx::query_scalar(
            "SELECT EXISTS (SELECT 1 FROM products.product_families WHERE id = $1)",
        )
        .bind(id)
        .fetch_one(&mut *conn)
        .await?;
        if !ok {
            return Err(AppError::Validation(format!("unknown product family {id}")));
        }
    }
    // Same kind with the sides swapped is the same rule.
    let mirrored: bool = sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM products.product_relations
         WHERE kind = $1 AND ($6::uuid IS NULL OR id <> $6)
           AND a_product_id IS NOT DISTINCT FROM $4 AND a_family_id IS NOT DISTINCT FROM $5
           AND b_product_id IS NOT DISTINCT FROM $2 AND b_family_id IS NOT DISTINCT FROM $3)",
    )
    .bind(&input.kind)
    .bind(input.a_product_id)
    .bind(input.a_family_id)
    .bind(input.b_product_id)
    .bind(input.b_family_id)
    .bind(own_id)
    .fetch_one(&mut *conn)
    .await?;
    if mirrored {
        return Err(AppError::Conflict(
            "the same rule already exists with the sides swapped".into(),
        ));
    }
    Ok(())
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct RelationParams {
    /// Rules that apply to this product, directly or through its family.
    pub product_id: Option<Uuid>,
    /// Rules that name this family.
    pub family_id: Option<Uuid>,
    /// compatible | incompatible | suggested
    pub kind: Option<String>,
}

#[utoipa::path(get, path = "/product-relations", tag = "products", params(RelationParams),
    responses((status = 200, body = Vec<ProductRelation>), (status = 422, body = tradocraft_core::error::ErrorBody)))]
async fn list_product_relations(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(p): Query<RelationParams>,
) -> AppResult<Json<Vec<ProductRelation>>> {
    user.require(Permission::ProductsRead)?;
    if let Some(k) = &p.kind {
        if !KINDS.contains(&k.as_str()) {
            return Err(AppError::Validation(format!("unknown kind {k}")));
        }
    }
    Ok(Json(
        sqlx::query_as(sqlx::AssertSqlSafe(format!(
            "{SELECT} WHERE ($1::text IS NULL OR r.kind = $1)
               AND ($2::uuid IS NULL OR r.a_product_id = $2 OR r.b_product_id = $2
                    OR r.a_family_id = (SELECT family_id FROM products.products WHERE id = $2)
                    OR r.b_family_id = (SELECT family_id FROM products.products WHERE id = $2))
               AND ($3::uuid IS NULL OR r.a_family_id = $3 OR r.b_family_id = $3)
             ORDER BY r.kind, r.created_at, r.id"
        )))
        .bind(&p.kind)
        .bind(p.product_id)
        .bind(p.family_id)
        .fetch_all(&state.db)
        .await?,
    ))
}

#[utoipa::path(post, path = "/product-relations", tag = "products", request_body = ProductRelationInput,
    responses((status = 201, body = ProductRelation), (status = 409, body = tradocraft_core::error::ErrorBody),
              (status = 422, body = tradocraft_core::error::ErrorBody)))]
async fn create_product_relation(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<ProductRelationInput>,
) -> AppResult<(StatusCode, Json<ProductRelation>)> {
    user.require(Permission::ProductsWrite)?;
    validate(&input)?;
    let id = new_id();
    let mut tx = state.db.begin().await?;
    check_references(&mut tx, &input, None).await?;
    sqlx::query(
        "INSERT INTO products.product_relations
            (id, kind, a_product_id, a_family_id, b_product_id, b_family_id, bidirectional, strength, note, active)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)",
    )
    .bind(id)
    .bind(&input.kind)
    .bind(input.a_product_id)
    .bind(input.a_family_id)
    .bind(input.b_product_id)
    .bind(input.b_family_id)
    .bind(input.bidirectional)
    .bind(input.strength)
    .bind(input.note.trim())
    .bind(input.active)
    .execute(&mut *tx)
    .await?;
    audit::record(
        &mut tx,
        &user,
        "product_relation",
        id,
        "created",
        serde_json::json!({ "kind": input.kind }),
    )
    .await?;
    let out = load(&mut tx, id).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(out)))
}

#[utoipa::path(put, path = "/product-relations/{id}", tag = "products", params(("id" = Uuid, Path)),
    request_body = ProductRelationInput,
    responses((status = 200, body = ProductRelation), (status = 404, body = tradocraft_core::error::ErrorBody),
              (status = 409, body = tradocraft_core::error::ErrorBody), (status = 422, body = tradocraft_core::error::ErrorBody)))]
async fn update_product_relation(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<ProductRelationInput>,
) -> AppResult<Json<ProductRelation>> {
    user.require(Permission::ProductsWrite)?;
    validate(&input)?;
    let mut tx = state.db.begin().await?;
    check_references(&mut tx, &input, Some(id)).await?;
    let r = sqlx::query(
        "UPDATE products.product_relations
         SET kind = $2, a_product_id = $3, a_family_id = $4, b_product_id = $5, b_family_id = $6,
             bidirectional = $7, strength = $8, note = $9, active = $10, updated_at = now()
         WHERE id = $1",
    )
    .bind(id)
    .bind(&input.kind)
    .bind(input.a_product_id)
    .bind(input.a_family_id)
    .bind(input.b_product_id)
    .bind(input.b_family_id)
    .bind(input.bidirectional)
    .bind(input.strength)
    .bind(input.note.trim())
    .bind(input.active)
    .execute(&mut *tx)
    .await?;
    if r.rows_affected() == 0 {
        return Err(AppError::NotFound("product relation"));
    }
    audit::record(
        &mut tx,
        &user,
        "product_relation",
        id,
        "updated",
        serde_json::json!({}),
    )
    .await?;
    let out = load(&mut tx, id).await?;
    tx.commit().await?;
    Ok(Json(out))
}

/// What the rules and the order history say about one product.
#[derive(Debug, Serialize, ToSchema)]
pub struct RelatedProducts {
    /// Active rules that apply to the product, directly or through its family.
    pub rules: Vec<ProductRelation>,
    /// Manual suggestions first, then computed ones.
    pub suggestions: Vec<Suggestion>,
}

#[utoipa::path(get, path = "/products/{id}/related", tag = "products", params(("id" = Uuid, Path)),
    responses((status = 200, body = RelatedProducts), (status = 404, body = tradocraft_core::error::ErrorBody)))]
async fn get_related_products(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<RelatedProducts>> {
    user.require(Permission::ProductsRead)?;
    let mut conn = state.db.acquire().await?;
    let family: Option<Option<Uuid>> =
        sqlx::query_scalar("SELECT family_id FROM products.products WHERE id = $1")
            .bind(id)
            .fetch_optional(&mut *conn)
            .await?;
    let family = family.ok_or(AppError::NotFound("product"))?;
    let rules: Vec<ProductRelation> = sqlx::query_as(sqlx::AssertSqlSafe(format!(
        "{SELECT} WHERE r.active AND (r.a_product_id = $1 OR r.b_product_id = $1
            OR ($2::uuid IS NOT NULL AND (r.a_family_id = $2 OR r.b_family_id = $2)))
         ORDER BY r.kind, r.created_at, r.id"
    )))
    .bind(id)
    .bind(family)
    .fetch_all(&mut *conn)
    .await?;
    let eval = check_products(&mut conn, &[id]).await?;
    Ok(Json(RelatedProducts {
        rules,
        suggestions: eval.suggestions,
    }))
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(list_product_relations, create_product_relation))
        .routes(routes!(update_product_relation))
        .routes(routes!(get_related_products))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn id(n: u128) -> Uuid {
        Uuid::from_u128(n)
    }

    fn sp(n: u128, family: Option<u128>) -> SetProduct {
        SetProduct {
            id: id(n),
            code: format!("P{n}"),
            name: format!("Product {n}"),
            family_id: family.map(id),
        }
    }

    fn cp(n: u128, family: Option<u128>, active: bool) -> CatalogProduct {
        CatalogProduct {
            id: id(n),
            code: format!("P{n}"),
            name: format!("Product {n}"),
            family_id: family.map(id),
            active,
        }
    }

    /// Side: `p(n)` product, `f(n)` family.
    #[derive(Clone, Copy)]
    enum S {
        P(u128),
        F(u128),
    }

    fn rule(kind: &str, a: S, b: S, bidirectional: bool, strength: i32) -> ProductRelation {
        let (ap, af) = match a {
            S::P(n) => (Some(id(n)), None),
            S::F(n) => (None, Some(id(n))),
        };
        let (bp, bf) = match b {
            S::P(n) => (Some(id(n)), None),
            S::F(n) => (None, Some(id(n))),
        };
        ProductRelation {
            id: Uuid::from_u128(rand_id()),
            kind: kind.into(),
            a_product_id: ap,
            a_product_code: None,
            a_family_id: af,
            a_family_code: None,
            b_product_id: bp,
            b_product_code: None,
            b_family_id: bf,
            b_family_code: None,
            bidirectional,
            strength,
            note: format!("{kind} note"),
            active: true,
        }
    }

    fn rand_id() -> u128 {
        use std::sync::atomic::{AtomicU64, Ordering};
        static N: AtomicU64 = AtomicU64::new(1_000_000);
        u128::from(N.fetch_add(1, Ordering::Relaxed))
    }

    fn pair(a: u128, b: u128, together: i32, wa: i32, wb: i32) -> Cooccurrence {
        let (a, b, wa, wb) = if a < b {
            (a, b, wa, wb)
        } else {
            (b, a, wb, wa)
        };
        Cooccurrence {
            product_a_id: id(a),
            product_b_id: id(b),
            orders_together: together,
            orders_with_a: wa,
            orders_with_b: wb,
        }
    }

    fn cfg() -> RelationConfig {
        RelationConfig {
            min_orders_together: 3,
            min_confidence: 0.3,
            max_family_expansion: 2,
            max_computed: 5,
        }
    }

    fn eval(
        set: &[SetProduct],
        rel: &[ProductRelation],
        co: &[Cooccurrence],
        cat: &[CatalogProduct],
    ) -> Evaluation {
        evaluate(set, rel, co, cat, &cfg())
    }

    #[test]
    fn incompatible_products_conflict() {
        let r = [rule("incompatible", S::P(1), S::P(2), true, 50)];
        let e = eval(&[sp(1, None), sp(2, None)], &r, &[], &[]);
        assert_eq!(e.conflicts.len(), 1);
        assert_eq!(e.conflicts[0].product_a_code, "P1");
        assert_eq!(e.conflicts[0].product_b_code, "P2");
        assert_eq!(e.conflicts[0].note, "incompatible note");
        // swapped order in the set gives the same single conflict
        assert_eq!(
            eval(&[sp(2, None), sp(1, None)], &r, &[], &[])
                .conflicts
                .len(),
            1
        );
    }

    #[test]
    fn no_rule_compatible_or_missing_partner_is_no_conflict() {
        let r = [rule("compatible", S::P(1), S::P(2), true, 50)];
        assert!(eval(&[sp(1, None), sp(2, None)], &r, &[], &[])
            .conflicts
            .is_empty());
        assert!(eval(&[sp(1, None), sp(3, None)], &r, &[], &[])
            .conflicts
            .is_empty());
        let r = [rule("incompatible", S::P(1), S::P(2), true, 50)];
        assert!(eval(&[sp(1, None), sp(3, None)], &r, &[], &[])
            .conflicts
            .is_empty());
        // a compatible rule next to an incompatible one does not cancel it
        let both = [
            rule("compatible", S::P(1), S::P(2), true, 50),
            rule("incompatible", S::P(1), S::P(2), true, 50),
        ];
        assert_eq!(
            eval(&[sp(1, None), sp(2, None)], &both, &[], &[])
                .conflicts
                .len(),
            1
        );
    }

    #[test]
    fn inactive_rules_are_ignored() {
        let mut r = rule("incompatible", S::P(1), S::P(2), true, 50);
        r.active = false;
        assert!(eval(&[sp(1, None), sp(2, None)], &[r], &[], &[])
            .conflicts
            .is_empty());
    }

    #[test]
    fn family_rules_conflict() {
        let set = [sp(1, Some(10)), sp(2, Some(20))];
        // family vs family
        let r = [rule("incompatible", S::F(10), S::F(20), true, 50)];
        assert_eq!(eval(&set, &r, &[], &[]).conflicts.len(), 1);
        // product vs family
        let r = [rule("incompatible", S::P(1), S::F(20), false, 50)];
        assert_eq!(eval(&set, &r, &[], &[]).conflicts.len(), 1);
        // family vs product, other orientation
        let r = [rule("incompatible", S::F(20), S::P(1), false, 50)];
        assert_eq!(eval(&set, &r, &[], &[]).conflicts.len(), 1);
        // other family does not match
        let r = [rule("incompatible", S::F(30), S::F(20), true, 50)];
        assert!(eval(&set, &r, &[], &[]).conflicts.is_empty());
    }

    #[test]
    fn same_family_rule_never_pairs_a_product_with_itself() {
        let r = [rule("incompatible", S::F(10), S::F(10), true, 50)];
        assert!(eval(&[sp(1, Some(10))], &r, &[], &[]).conflicts.is_empty());
        assert_eq!(
            eval(&[sp(1, Some(10)), sp(2, Some(10))], &r, &[], &[])
                .conflicts
                .len(),
            1
        );
    }

    #[test]
    fn suggested_rule_suggests_other_side_bidirectionally() {
        let cat = [cp(1, None, true), cp(2, None, true)];
        let r = [rule("suggested", S::P(1), S::P(2), true, 70)];
        let e = eval(&[sp(1, None)], &r, &[], &cat);
        assert_eq!(e.suggestions.len(), 1);
        let s = &e.suggestions[0];
        assert_eq!(s.product_id, id(2));
        assert_eq!(s.reason, SuggestionReason::Rule);
        assert_eq!(s.strength, Some(70));
        assert_eq!(s.because_of_code, "P1");
        // reverse direction works when bidirectional
        assert_eq!(
            eval(&[sp(2, None)], &r, &[], &cat).suggestions[0].product_id,
            id(1)
        );
        // and not when one-way
        let r = [rule("suggested", S::P(1), S::P(2), false, 70)];
        assert!(eval(&[sp(2, None)], &r, &[], &cat).suggestions.is_empty());
        assert_eq!(eval(&[sp(1, None)], &r, &[], &cat).suggestions.len(), 1);
    }

    #[test]
    fn family_target_expands_to_active_products_capped() {
        let cat = [
            cp(1, None, true),
            cp(21, Some(20), true),
            cp(22, Some(20), false),
            cp(23, Some(20), true),
            cp(24, Some(20), true),
        ];
        let r = [rule("suggested", S::P(1), S::F(20), false, 40)];
        let e = eval(&[sp(1, None)], &r, &[], &cat);
        let ids: Vec<Uuid> = e.suggestions.iter().map(|s| s.product_id).collect();
        // inactive 22 skipped, cap of 2 applied by code order
        assert_eq!(ids, vec![id(21), id(23)]);
    }

    #[test]
    fn family_trigger_side() {
        let cat = [cp(2, None, true)];
        let r = [rule("suggested", S::F(10), S::P(2), false, 40)];
        assert_eq!(eval(&[sp(1, Some(10))], &r, &[], &cat).suggestions.len(), 1);
        assert!(eval(&[sp(1, Some(11))], &r, &[], &cat)
            .suggestions
            .is_empty());
    }

    #[test]
    fn never_suggest_what_is_in_the_set_or_inactive_or_clashing() {
        let r = [
            rule("suggested", S::P(1), S::P(2), true, 50),
            rule("suggested", S::P(1), S::P(3), true, 50),
            rule("suggested", S::P(1), S::P(4), true, 50),
            rule("incompatible", S::P(5), S::P(4), true, 50),
        ];
        let cat = [cp(2, None, true), cp(3, None, false), cp(4, None, true)];
        let e = eval(&[sp(1, None), sp(2, None), sp(5, None)], &r, &[], &cat);
        assert!(e.suggestions.is_empty(), "{:?}", e.suggestions);
    }

    #[test]
    fn strongest_manual_rule_wins_per_target() {
        let cat = [cp(2, None, true)];
        let r = [
            rule("suggested", S::P(1), S::P(2), true, 20),
            rule("suggested", S::P(1), S::P(2), true, 90),
        ];
        let e = eval(&[sp(1, None)], &r, &[], &cat);
        assert_eq!(e.suggestions.len(), 1);
        assert_eq!(e.suggestions[0].strength, Some(90));
    }

    #[test]
    fn computed_needs_thresholds() {
        let cat = [cp(1, None, true), cp(2, None, true)];
        let set = [sp(1, None)];
        // too few orders together
        assert!(eval(&set, &[], &[pair(1, 2, 2, 2, 2)], &cat)
            .suggestions
            .is_empty());
        // enough orders, confidence 3/20 = 0.15 < 0.3
        assert!(eval(&set, &[], &[pair(1, 2, 3, 20, 3)], &cat)
            .suggestions
            .is_empty());
        // 3/6 = 0.5
        let e = eval(&set, &[], &[pair(1, 2, 3, 6, 3)], &cat);
        assert_eq!(e.suggestions.len(), 1);
        let s = &e.suggestions[0];
        assert_eq!(s.reason, SuggestionReason::OftenBoughtTogether);
        assert_eq!(s.confidence, Some(0.5));
        assert_eq!(s.strength, None);
        assert!(e.conflicts.is_empty());
    }

    #[test]
    fn computed_confidence_is_per_direction() {
        let cat = [cp(1, None, true), cp(2, None, true)];
        // 1 is rare (3 orders), 2 is common (30): from 1 the confidence is 1.0, from 2 it is 0.1
        let co = [pair(1, 2, 3, 3, 30)];
        assert_eq!(eval(&[sp(1, None)], &[], &co, &cat).suggestions.len(), 1);
        assert!(eval(&[sp(2, None)], &[], &co, &cat).suggestions.is_empty());
    }

    #[test]
    fn manual_beats_computed_and_comes_first() {
        let cat = [cp(2, None, true), cp(3, None, true)];
        let r = [rule("suggested", S::P(1), S::P(2), true, 10)];
        let co = [pair(1, 2, 9, 9, 9), pair(1, 3, 4, 4, 4)];
        let e = eval(&[sp(1, None)], &r, &co, &cat);
        assert_eq!(e.suggestions.len(), 2);
        assert_eq!(e.suggestions[0].product_id, id(2));
        assert_eq!(e.suggestions[0].reason, SuggestionReason::Rule);
        assert_eq!(e.suggestions[1].product_id, id(3));
        assert_eq!(
            e.suggestions[1].reason,
            SuggestionReason::OftenBoughtTogether
        );
    }

    #[test]
    fn computed_skips_set_inactive_and_incompatible() {
        let cat = [cp(2, None, true), cp(3, None, false), cp(4, None, true)];
        let r = [rule("incompatible", S::P(1), S::P(4), true, 50)];
        let co = [
            pair(1, 2, 9, 9, 9),
            pair(1, 3, 9, 9, 9),
            pair(1, 4, 9, 9, 9),
        ];
        // 2 is in the set, 3 inactive, 4 incompatible with 1
        let e = eval(&[sp(1, None), sp(2, None)], &r, &co, &cat);
        assert!(e.suggestions.is_empty(), "{:?}", e.suggestions);
    }

    #[test]
    fn computed_is_capped_and_sorted_by_confidence() {
        let cat: Vec<CatalogProduct> = (2..=9).map(|n| cp(n, None, true)).collect();
        let co: Vec<Cooccurrence> = (2..=9).map(|n| pair(1, n, 5, 10, 5 + n as i32)).collect();
        let mut c = cfg();
        c.max_computed = 3;
        let e = evaluate(&[sp(1, None)], &[], &co, &cat, &c);
        assert_eq!(e.suggestions.len(), 3);
    }

    #[test]
    fn count_pairs_counts_each_order_once() {
        let (a, b, c) = (id(1), id(2), id(3));
        let orders = vec![vec![a, b, b], vec![b, a], vec![a, c], vec![c]];
        let pairs = count_pairs(&orders);
        let ab = pairs
            .iter()
            .find(|p| p.product_a_id == a && p.product_b_id == b)
            .unwrap();
        assert_eq!(
            (ab.orders_together, ab.orders_with_a, ab.orders_with_b),
            (2, 3, 2)
        );
        let ac = pairs
            .iter()
            .find(|p| p.product_a_id == a && p.product_b_id == c)
            .unwrap();
        assert_eq!(
            (ac.orders_together, ac.orders_with_a, ac.orders_with_b),
            (1, 3, 2)
        );
        assert_eq!(pairs.len(), 2);
    }
}
