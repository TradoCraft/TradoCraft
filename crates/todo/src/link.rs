//! The records a to-do item can be linked to.

use serde::{Deserialize, Serialize};
use tradocraft_core::Permission;
use utoipa::ToSchema;

/// The kind of record an item is linked to. Closed list, mirrored by the `CHECK` on
/// `todo.items.link_kind` and by the app's link registry.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum TodoLinkKind {
    Customer,
    Quotation,
    Order,
    Ticket,
    Repair,
    Job,
    ProductionOrder,
    Delivery,
    Product,
    Opportunity,
    PurchaseOrder,
    GoodsReceipt,
    Supplier,
    SupplierInvoice,
    KbEntry,
    StockCount,
}

impl TodoLinkKind {
    pub const ALL: [TodoLinkKind; 16] = [
        TodoLinkKind::Customer,
        TodoLinkKind::Quotation,
        TodoLinkKind::Order,
        TodoLinkKind::Ticket,
        TodoLinkKind::Repair,
        TodoLinkKind::Job,
        TodoLinkKind::ProductionOrder,
        TodoLinkKind::Delivery,
        TodoLinkKind::Product,
        TodoLinkKind::Opportunity,
        TodoLinkKind::PurchaseOrder,
        TodoLinkKind::GoodsReceipt,
        TodoLinkKind::Supplier,
        TodoLinkKind::SupplierInvoice,
        TodoLinkKind::KbEntry,
        TodoLinkKind::StockCount,
    ];

    /// The value stored in `todo.items.link_kind`.
    pub fn as_str(self) -> &'static str {
        match self {
            TodoLinkKind::Customer => "customer",
            TodoLinkKind::Quotation => "quotation",
            TodoLinkKind::Order => "order",
            TodoLinkKind::Ticket => "ticket",
            TodoLinkKind::Repair => "repair",
            TodoLinkKind::Job => "job",
            TodoLinkKind::ProductionOrder => "production_order",
            TodoLinkKind::Delivery => "delivery",
            TodoLinkKind::Product => "product",
            TodoLinkKind::Opportunity => "opportunity",
            TodoLinkKind::PurchaseOrder => "purchase_order",
            TodoLinkKind::GoodsReceipt => "goods_receipt",
            TodoLinkKind::Supplier => "supplier",
            TodoLinkKind::SupplierInvoice => "supplier_invoice",
            TodoLinkKind::KbEntry => "kb_entry",
            TodoLinkKind::StockCount => "stock_count",
        }
    }

    pub fn parse(s: &str) -> Option<TodoLinkKind> {
        TodoLinkKind::ALL.into_iter().find(|k| k.as_str() == s)
    }

    /// The permission that lets a user read records of this kind: needed to link to one and to see
    /// the label of a linked one.
    pub fn read_permission(self) -> Permission {
        match self {
            TodoLinkKind::Customer => Permission::CustomersRead,
            TodoLinkKind::Quotation => Permission::QuotationsRead,
            TodoLinkKind::Order => Permission::OrdersRead,
            TodoLinkKind::Ticket => Permission::HelpdeskRead,
            TodoLinkKind::Repair => Permission::RepairsRead,
            TodoLinkKind::Job => Permission::FieldRead,
            TodoLinkKind::ProductionOrder => Permission::ProductionRead,
            TodoLinkKind::Delivery => Permission::DeliveryRead,
            TodoLinkKind::Product => Permission::ProductsRead,
            TodoLinkKind::Opportunity => Permission::OpportunitiesRead,
            TodoLinkKind::PurchaseOrder | TodoLinkKind::GoodsReceipt | TodoLinkKind::Supplier => {
                Permission::PurchasingRead
            }
            TodoLinkKind::SupplierInvoice => Permission::FinanceRead,
            TodoLinkKind::KbEntry => Permission::KbRead,
            TodoLinkKind::StockCount => Permission::InventoryRead,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn codes_round_trip_and_match_serde() {
        for k in TodoLinkKind::ALL {
            assert_eq!(TodoLinkKind::parse(k.as_str()), Some(k));
            assert_eq!(
                serde_json::to_value(k).unwrap(),
                serde_json::json!(k.as_str())
            );
        }
        assert_eq!(TodoLinkKind::parse("nope"), None);
    }

    #[test]
    fn every_kind_needs_a_read_permission() {
        for k in TodoLinkKind::ALL {
            assert!(k.read_permission().as_str().ends_with(".read"), "{k:?}");
        }
    }
}
