//! The entities that can be imported. A new entity is one `Importable` implementation in its own
//! crate and one line here; the admin screen and the jobs pick it up from this list.

use tradocraft_core::import::ImportEntity;

/// Every importable entity.
pub fn entities() -> Vec<ImportEntity> {
    vec![
        tradocraft_crm::customers_import(),
        tradocraft_products::products_import(),
        tradocraft_products::zone_prices_import(),
        tradocraft_products::price_list_items_import(),
    ]
}

/// The entity with this key (`customers`, `products`, `zone_prices`, `price_list_items`).
pub fn entity(key: &str) -> Option<ImportEntity> {
    entities().into_iter().find(|e| e.describe().key == key)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_registry_lists_the_entities_and_finds_them_by_key() {
        let keys: Vec<String> = entities()
            .iter()
            .map(|e| e.describe().key.clone())
            .collect();
        assert_eq!(
            keys,
            ["customers", "products", "zone_prices", "price_list_items"]
        );
        assert_eq!(
            entity("products").map(|e| e.describe().key_columns.clone()),
            Some(vec!["code".to_string()])
        );
        assert_eq!(
            entity("zone_prices").map(|e| e.describe().key_columns.clone()),
            Some(vec![
                "product_code".to_string(),
                "zone".to_string(),
                "valid_from".to_string()
            ])
        );
        let items = entity("price_list_items").unwrap();
        assert_eq!(items.describe().key_column, "price_list");
        assert!(items.header().contains(&"group_title_*".to_string()));
        assert!(entity("nope").is_none());
        assert!(entity("").is_none());
    }
}
