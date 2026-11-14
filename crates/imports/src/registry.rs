//! The entities that can be imported. A new entity is one `Importable` implementation in its own
//! crate and one line here; the admin screen and the jobs pick it up from this list.

use tradocraft_core::import::ImportEntity;

/// Every importable entity.
pub fn entities() -> Vec<ImportEntity> {
    vec![
        tradocraft_crm::customers_import(),
        tradocraft_products::products_import(),
    ]
}

/// The entity with this key (`customers`, `products`).
pub fn entity(key: &str) -> Option<ImportEntity> {
    entities().into_iter().find(|e| e.describe().key == key)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_registry_lists_customers_and_products_and_finds_them_by_key() {
        let keys: Vec<String> = entities()
            .iter()
            .map(|e| e.describe().key.clone())
            .collect();
        assert_eq!(keys, ["customers", "products"]);
        assert_eq!(
            entity("products").map(|e| e.describe().key_column.clone()),
            Some("code".to_string())
        );
        assert!(entity("nope").is_none());
        assert!(entity("").is_none());
    }
}
