//! Zone prices as an importable entity (ADR 0100): one row per product, zone and start date, an
//! upsert on that key in the shared engine of ADR 0067.
//!
//! The rules are those of the price endpoints of a product: a new dated price can start on any
//! date; the price of an entry that is or was in effect (`valid_from` today or earlier) is history
//! and is not changed (a row that would change it is an error, the file adds a new date instead);
//! a price that has not started yet can be corrected. The audit events are those of the
//! endpoints, on the product (`price_added`, `price_corrected`). An import never applies the
//! default multiplier or rounding of a zone: the file holds the prices as they are.

use std::collections::HashMap;

use chrono::NaiveDate;
use rust_decimal::Decimal;
use sqlx::{PgConnection, PgPool};
use tradocraft_core::import::{
    AuditEvent, Cell, CellValue, Cells, Column, ColumnKind, ExportTable, ImportEntity, Importable,
    Row, Table, KEY_SEPARATOR,
};
use tradocraft_core::{AppResult, CurrentUser, Permission};
use uuid::Uuid;

const COLUMNS: [Column; 4] = [
    Column::new("product_code", ColumnKind::Code, true),
    Column::new("zone", ColumnKind::Code, true),
    Column::new("valid_from", ColumnKind::Code, true),
    Column::new("unit_price", ColumnKind::Decimal, true),
];

/// Largest absolute price `numeric(18,4)` holds.
fn max_price() -> Decimal {
    Decimal::new(999_999_999_999_999_999, 4)
}

/// A stored zone price.
#[derive(Debug, Clone, sqlx::FromRow)]
pub struct StoredZonePrice {
    id: Uuid,
    unit_price: Decimal,
}

/// What one row writes.
pub struct ZonePriceChange {
    product_id: Uuid,
    zone_id: Uuid,
    valid_from: NaiveDate,
    unit_price: Decimal,
    /// The stored price an update replaces.
    old_price: Option<Decimal>,
}

/// The lookups of one run.
pub struct ZonePriceContext {
    zones: HashMap<String, Uuid>,
    products: HashMap<String, Uuid>,
    today: NaiveDate,
}

/// A date of the key: `YYYY-MM-DD` exactly (a date cell of a spreadsheet is read that way), so
/// that one date is always one key.
fn parse_date(value: &str) -> Option<NaiveDate> {
    NaiveDate::parse_from_str(value, "%Y-%m-%d")
        .ok()
        .filter(|d| d.format("%Y-%m-%d").to_string() == value)
}

/// The parts of a key: product code, zone code, start date.
fn key_parts(key: &str) -> Option<(&str, &str, &str)> {
    let mut parts = key.split(KEY_SEPARATOR);
    let parts = (parts.next()?, parts.next()?, parts.next()?);
    Some(parts)
}

fn key(product: &str, zone: &str, valid_from: NaiveDate) -> String {
    format!("{product}{KEY_SEPARATOR}{zone}{KEY_SEPARATOR}{valid_from}")
}

/// Zone prices, keyed by product, zone and start date.
pub struct ZonePrices;

impl Importable for ZonePrices {
    type Stored = StoredZonePrice;
    type Change = ZonePriceChange;
    type Context = ZonePriceContext;

    const KEY: &'static str = "zone_prices";
    const AUDIT_ENTITY: &'static str = "product";
    const READ: Permission = Permission::ProductsRead;
    const WRITE: Permission = Permission::PricesWrite;
    const FILE_STEM: &'static str = "zone_prices";
    const COLUMNS: &'static [Column] = &COLUMNS;
    const KEY_COLUMN: &'static str = "product_code";
    const KEY_COLUMNS: &'static [&'static str] = &["product_code", "zone", "valid_from"];

    async fn context(
        conn: &mut PgConnection,
        user: &CurrentUser,
        table: &Table,
    ) -> AppResult<ZonePriceContext> {
        let zones = sqlx::query_as::<_, (String, Uuid)>(
            "SELECT code, id FROM pricing.price_zones WHERE company_id = $1",
        )
        .bind(user.company_id)
        .fetch_all(&mut *conn)
        .await?
        .into_iter()
        .collect();
        let codes: Vec<&str> = table
            .rows
            .iter()
            .filter_map(|r| r.get_trimmed("product_code"))
            .collect();
        let products = sqlx::query_as::<_, (String, Uuid)>(
            "SELECT code, id FROM products.products WHERE code = ANY($1)",
        )
        .bind(&codes)
        .fetch_all(conn)
        .await?
        .into_iter()
        .collect();
        Ok(ZonePriceContext {
            zones,
            products,
            today: tradocraft_core::today(),
        })
    }

    async fn load(
        conn: &mut PgConnection,
        user: &CurrentUser,
        keys: &[String],
    ) -> AppResult<Vec<(String, StoredZonePrice)>> {
        let (mut products, mut zones, mut dates) = (Vec::new(), Vec::new(), Vec::new());
        for (p, z, d) in keys.iter().filter_map(|k| key_parts(k)) {
            if let Some(d) = parse_date(d) {
                products.push(p);
                zones.push(z);
                dates.push(d);
            }
        }
        #[derive(sqlx::FromRow)]
        struct Found {
            #[sqlx(flatten)]
            price: StoredZonePrice,
            product_code: String,
            zone_code: String,
            valid_from: NaiveDate,
        }
        let found: Vec<Found> = sqlx::query_as(
            "SELECT zp.id, zp.unit_price, p.code AS product_code, z.code AS zone_code, zp.valid_from
             FROM pricing.zone_prices zp
             JOIN products.products p ON p.id = zp.product_id
             JOIN pricing.price_zones z ON z.id = zp.zone_id
             WHERE zp.company_id = $1
               AND (p.code, z.code, zp.valid_from) IN
                   (SELECT * FROM unnest($2::text[], $3::text[], $4::date[]))
             ORDER BY zp.id
             FOR UPDATE OF zp",
        )
        .bind(user.company_id)
        .bind(&products)
        .bind(&zones)
        .bind(&dates)
        .fetch_all(conn)
        .await?;
        Ok(found
            .into_iter()
            .map(|f| (key(&f.product_code, &f.zone_code, f.valid_from), f.price))
            .collect())
    }

    fn stored_id(stored: &StoredZonePrice) -> Uuid {
        stored.id
    }

    async fn plan_row(
        _conn: &mut PgConnection,
        _user: &CurrentUser,
        context: &mut ZonePriceContext,
        key: &str,
        current: Option<&StoredZonePrice>,
        _row: &Row,
        cells: &mut Cells<'_>,
    ) -> AppResult<ZonePriceChange> {
        let (product, zone, date) = key_parts(key).unwrap_or_default();
        let product_id = context.products.get(product).copied();
        if product_id.is_none() {
            cells.error(Some("product_code"), format!("unknown product {product:?}"));
        }
        let zone_id = context.zones.get(zone).copied();
        if zone_id.is_none() {
            cells.error(Some("zone"), format!("unknown price zone {zone:?}"));
        }
        let valid_from = parse_date(date);
        if valid_from.is_none() {
            cells.error(
                Some("valid_from"),
                format!("{date:?} is not a date written as YYYY-MM-DD"),
            );
        }
        let unit_price = match cells.decimal("unit_price") {
            Cell::Value(d) if d.normalize().scale() > 4 => {
                cells.error(Some("unit_price"), "at most 4 decimals are allowed");
                None
            }
            Cell::Value(d) if d.abs() > max_price() => {
                cells.error(
                    Some("unit_price"),
                    format!("must be at most {}", max_price()),
                );
                None
            }
            Cell::Value(d) => Some(d),
            Cell::Blank | Cell::Absent => {
                cells.error(Some("unit_price"), "unit_price is required");
                None
            }
        };
        // A price in effect is history (ADR 0012): it is never changed, as in the product form.
        if let (Some(c), Some(price), Some(from)) = (current, unit_price, valid_from) {
            if c.unit_price != price && from <= context.today {
                cells.error(
                    Some("unit_price"),
                    format!(
                        "the price of {} in zone {zone} is in effect since {from}; \
                         add a new dated price instead",
                        c.unit_price.normalize()
                    ),
                );
            }
        }
        Ok(ZonePriceChange {
            product_id: product_id.unwrap_or_default(),
            zone_id: zone_id.unwrap_or_default(),
            valid_from: valid_from.unwrap_or_default(),
            unit_price: unit_price.unwrap_or_default(),
            old_price: current.map(|c| c.unit_price),
        })
    }

    fn unchanged(stored: &StoredZonePrice, change: &ZonePriceChange) -> bool {
        stored.unit_price == change.unit_price
    }

    async fn create(
        conn: &mut PgConnection,
        user: &CurrentUser,
        id: Uuid,
        change: &ZonePriceChange,
    ) -> AppResult<()> {
        sqlx::query(
            "INSERT INTO pricing.zone_prices
                (id, company_id, zone_id, product_id, unit_price, valid_from, created_by)
             VALUES ($1, $2, $3, $4, $5, $6, $7)",
        )
        .bind(id)
        .bind(user.company_id)
        .bind(change.zone_id)
        .bind(change.product_id)
        .bind(change.unit_price)
        .bind(change.valid_from)
        .bind(user.user_id)
        .execute(conn)
        .await?;
        Ok(())
    }

    async fn update(
        conn: &mut PgConnection,
        _user: &CurrentUser,
        id: Uuid,
        change: &ZonePriceChange,
    ) -> AppResult<()> {
        sqlx::query("UPDATE pricing.zone_prices SET unit_price = $2 WHERE id = $1")
            .bind(id)
            .bind(change.unit_price)
            .execute(conn)
            .await?;
        Ok(())
    }

    /// The events of the price endpoints, on the product.
    fn audit_event(id: Uuid, _key: &str, change: &ZonePriceChange, created: bool) -> AuditEvent {
        let data = if created {
            serde_json::json!({
                "price_id": id,
                "zone_id": change.zone_id,
                "unit_price": change.unit_price,
                "valid_from": change.valid_from,
            })
        } else {
            serde_json::json!({
                "price_id": id,
                "zone_id": change.zone_id,
                "old": { "unit_price": change.old_price, "valid_from": change.valid_from },
                "new": { "unit_price": change.unit_price, "valid_from": change.valid_from },
            })
        };
        AuditEvent {
            entity: "product",
            id: change.product_id,
            action: if created {
                "price_added"
            } else {
                "price_corrected"
            },
            data: match data {
                serde_json::Value::Object(map) => map,
                _ => serde_json::Map::new(),
            },
        }
    }

    /// Every price of the company (the whole history), by product, zone and date.
    async fn export(pool: &PgPool, user: &CurrentUser) -> AppResult<ExportTable> {
        let rows: Vec<(String, String, NaiveDate, Decimal)> = sqlx::query_as(
            "SELECT p.code, z.code, zp.valid_from, zp.unit_price
             FROM pricing.zone_prices zp
             JOIN products.products p ON p.id = zp.product_id
             JOIN pricing.price_zones z ON z.id = zp.zone_id
             WHERE zp.company_id = $1
             ORDER BY p.code, z.sort_order, z.code, zp.valid_from",
        )
        .bind(user.company_id)
        .fetch_all(pool)
        .await?;
        Ok(ExportTable::fixed::<Self>(
            rows.into_iter()
                .map(|(product, zone, from, price)| {
                    vec![
                        CellValue::text(product),
                        CellValue::text(zone),
                        CellValue::Date(from),
                        CellValue::Number(price.normalize()),
                    ]
                })
                .collect(),
        ))
    }
}

/// The zone prices' handle for the import registry and the background worker.
pub fn zone_prices_import() -> ImportEntity {
    ImportEntity::of::<ZonePrices>()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_start_date_is_one_way_of_writing_a_day() {
        let d = NaiveDate::from_ymd_opt(2027, 1, 1).unwrap();
        assert_eq!(parse_date("2027-01-01"), Some(d));
        for bad in [
            "2027-1-1",
            "01/01/2027",
            "2027-02-30",
            "",
            "2027-01-01T00:00:00",
        ] {
            assert_eq!(parse_date(bad), None, "{bad}");
        }
    }

    #[test]
    fn keys_have_three_parts() {
        let d = NaiveDate::from_ymd_opt(2027, 1, 1).unwrap();
        let k = key("P-100", "Z1", d);
        assert_eq!(key_parts(&k), Some(("P-100", "Z1", "2027-01-01")));
        assert_eq!(key_parts("P-100"), None);
        assert_eq!(max_price().to_string(), "99999999999999.9999");
    }
}
