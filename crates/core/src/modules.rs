//! Modules: groups of permissions that a company can switch off, and that can be switched off
//! for single users (ADR 0028). Everything here is pure; enforcement lives in `auth.rs`.

use crate::auth::Permission;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub enum Module {
    /// Customers, contacts, opportunities and rebates (the `crm` crate).
    Customers,
    Products,
    Sales,
    Engineering,
    Inventory,
    Helpdesk,
    Kb,
    Repairs,
    Field,
    Purchasing,
    /// Admin-defined product configurators (ADR 0034).
    Configurator,
    /// Delivery notes, picking and shipping (ADR 0035).
    Delivery,
    /// Production orders, divisions and the order status that follows them (ADR 0036).
    Production,
    /// User-defined reports over the other modules' data (ADR 0042).
    Reports,
    /// Supplier invoices and the three-way match: an AP register, not a ledger (ADR 0046).
    Finance,
    /// To-do items: private checklists with sub-items and links to records (ADR 0061).
    Todo,
}

/// Permissions that belong to no module: they cannot be switched off.
pub const ALWAYS_ON: [Permission; 3] = [
    Permission::UsersAdmin,
    Permission::IdentityAdmin,
    Permission::AuditView,
];

impl Module {
    pub const ALL: [Module; 16] = [
        Module::Customers,
        Module::Products,
        Module::Sales,
        Module::Engineering,
        Module::Inventory,
        Module::Helpdesk,
        Module::Kb,
        Module::Repairs,
        Module::Field,
        Module::Purchasing,
        Module::Configurator,
        Module::Delivery,
        Module::Production,
        Module::Reports,
        Module::Finance,
        Module::Todo,
    ];

    pub fn code(self) -> &'static str {
        match self {
            Module::Customers => "customers",
            Module::Products => "products",
            Module::Sales => "sales",
            Module::Engineering => "engineering",
            Module::Inventory => "inventory",
            Module::Helpdesk => "helpdesk",
            Module::Kb => "kb",
            Module::Repairs => "repairs",
            Module::Field => "field",
            Module::Purchasing => "purchasing",
            Module::Configurator => "configurator",
            Module::Delivery => "delivery",
            Module::Production => "production",
            Module::Reports => "reports",
            Module::Finance => "finance",
            Module::Todo => "todo",
        }
    }

    pub fn from_code(code: &str) -> Option<Module> {
        Module::ALL.into_iter().find(|m| m.code() == code)
    }

    /// The permissions this module owns. Every permission is owned by exactly one module,
    /// except those in [`ALWAYS_ON`].
    pub fn permissions(self) -> &'static [Permission] {
        use Permission::*;
        match self {
            Module::Customers => &[
                CustomersRead,
                CustomersWrite,
                ContactsWrite,
                OpportunitiesRead,
                OpportunitiesWrite,
                RebatesWrite,
                ClosuresWrite,
            ],
            Module::Products => &[ProductsRead, ProductsWrite, PricesWrite, InventoryCost],
            Module::Sales => &[
                QuotationsRead,
                QuotationsWrite,
                QuotationsImport,
                OrdersRead,
                OrdersWrite,
                PricesBackdate,
                ShippingManage,
            ],
            Module::Engineering => &[BomRead, BomWrite, SerialsRead, SerialsWrite],
            Module::Inventory => &[InventoryRead, InventoryWrite, InventoryAdmin],
            Module::Helpdesk => &[
                HelpdeskRead,
                HelpdeskWrite,
                HelpdeskReply,
                HelpdeskAdmin,
                AnswersWrite,
            ],
            Module::Kb => &[KbRead, KbWrite, KbAdmin],
            Module::Repairs => &[
                RepairsRead,
                RepairsWrite,
                RepairsRoute,
                RepairsIntake,
                RepairsWarrantyVoid,
                PackagesRead,
                PackagesWrite,
                PackagesOpen,
                DepartmentsWrite,
            ],
            Module::Field => &[
                FieldRead,
                FieldWork,
                FieldPlan,
                PlanningRead,
                PlanningWrite,
                PlanningAdmin,
            ],
            Module::Purchasing => &[
                PurchasingRead,
                PurchasingWrite,
                PurchasingApprove,
                GoodsReceipt,
            ],
            Module::Configurator => &[ConfiguratorDesign, ConfiguratorUse],
            Module::Delivery => &[
                DeliveryRead,
                DeliveryWrite,
                DeliveryShip,
                DeliveryOverrideClosure,
                DeliveryAdmin,
            ],
            Module::Production => &[
                ProductionRead,
                ProductionWrite,
                ProductionRun,
                ProductionAdmin,
            ],
            Module::Reports => &[ReportsRead, ReportsWrite],
            Module::Finance => &[FinanceRead, FinanceWrite, FinanceApprove],
            Module::Todo => &[TodoUse],
        }
    }

    /// Modules that must stay enabled for this one to be usable: the ones whose records it
    /// cannot do without (mandatory references in the data model).
    pub fn requires(self) -> &'static [Module] {
        match self {
            Module::Sales => &[Module::Customers, Module::Products],
            Module::Purchasing => &[Module::Products, Module::Inventory],
            // Invoices are matched against purchase orders and goods receipts.
            Module::Finance => &[Module::Purchasing],
            Module::Engineering | Module::Inventory => &[Module::Products],
            Module::Repairs | Module::Field => &[Module::Customers],
            // Models reference products; configurations become quotations.
            Module::Configurator => &[Module::Products, Module::Sales],
            // Delivers sales orders out of stock.
            Module::Delivery => &[Module::Sales, Module::Inventory],
            // Builds what sales orders ask for from the BOM, out of stock.
            Module::Production => &[Module::Sales, Module::Inventory, Module::Engineering],
            // A report checks the read permission of each object it touches, so it needs no
            // module of its own to be present.
            Module::Customers
            | Module::Products
            | Module::Helpdesk
            | Module::Kb
            | Module::Reports
            // A link to a record is checked against that record's read permission, so the
            // list needs no other module to be present.
            | Module::Todo => &[],
        }
    }
}

/// The module that owns a permission; `None` for always-on permissions.
pub fn permission_module(p: Permission) -> Option<Module> {
    Module::ALL
        .into_iter()
        .find(|m| m.permissions().contains(&p))
}

/// Parses module codes, rejecting unknown ones. Duplicates collapse; the result follows the
/// catalogue order.
pub fn parse_codes(codes: &[String]) -> Result<Vec<Module>, String> {
    let mut found = Vec::new();
    for c in codes {
        match Module::from_code(c.trim()) {
            Some(m) => found.push(m),
            None => return Err(format!("unknown module '{c}'")),
        }
    }
    Ok(Module::ALL
        .into_iter()
        .filter(|m| found.contains(m))
        .collect())
}

/// Checks a set of disabled modules: no enabled module may need a disabled one.
pub fn check_requires(disabled: &[Module]) -> Result<(), String> {
    for m in Module::ALL {
        if disabled.contains(&m) {
            continue;
        }
        if let Some(missing) = m.requires().iter().find(|r| disabled.contains(r)) {
            return Err(format!(
                "module '{}' requires '{}'",
                m.code(),
                missing.code()
            ));
        }
    }
    Ok(())
}

/// Validates the modules a company switches off: known codes, dependencies satisfied.
pub fn validate_company_disabled(codes: &[String]) -> Result<Vec<Module>, String> {
    let modules = parse_codes(codes)?;
    check_requires(&modules)?;
    Ok(modules)
}

/// What a user ends up without: the company's disabled modules plus their own. A user can
/// narrow what the company allows, never widen it. Unknown codes in the database are ignored.
pub fn effective_disabled(company: &[String], user: &[String]) -> Vec<Module> {
    Module::ALL
        .into_iter()
        .filter(|m| company.iter().any(|c| c == m.code()) || user.iter().any(|c| c == m.code()))
        .collect()
}

/// Validates the modules switched off for one user, given the company's: known codes, and the
/// combined set still satisfies the dependencies.
pub fn validate_user_disabled(company: &[String], user: &[String]) -> Result<Vec<Module>, String> {
    let modules = parse_codes(user)?;
    let user_codes: Vec<String> = modules.iter().map(|m| m.code().to_string()).collect();
    check_requires(&effective_disabled(company, &user_codes))?;
    Ok(modules)
}

pub fn codes(modules: &[Module]) -> Vec<String> {
    modules.iter().map(|m| m.code().to_string()).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn s(v: &[&str]) -> Vec<String> {
        v.iter().map(|x| x.to_string()).collect()
    }

    #[test]
    fn every_permission_belongs_to_exactly_one_module_or_is_always_on() {
        for p in Permission::ALL {
            let owners: Vec<_> = Module::ALL
                .into_iter()
                .filter(|m| m.permissions().contains(&p))
                .collect();
            if ALWAYS_ON.contains(&p) {
                assert!(owners.is_empty(), "{} is always on", p.as_str());
            } else {
                assert_eq!(owners.len(), 1, "{}: {owners:?}", p.as_str());
            }
        }
    }

    #[test]
    fn modules_only_own_known_permissions() {
        for m in Module::ALL {
            for p in m.permissions() {
                assert!(Permission::ALL.contains(p), "{}", p.as_str());
            }
        }
    }

    #[test]
    fn permission_module_maps_both_ways() {
        assert_eq!(
            permission_module(Permission::ShippingManage),
            Some(Module::Sales)
        );
        assert_eq!(
            permission_module(Permission::InventoryCost),
            Some(Module::Products)
        );
        assert_eq!(permission_module(Permission::UsersAdmin), None);
        // Switching the repairs module off also hides the incoming parcels.
        for p in [
            Permission::PackagesRead,
            Permission::PackagesWrite,
            Permission::PackagesOpen,
            Permission::RepairsIntake,
            Permission::RepairsWarrantyVoid,
        ] {
            assert_eq!(
                permission_module(p),
                Some(Module::Repairs),
                "{}",
                p.as_str()
            );
        }
    }

    #[test]
    fn the_to_do_module_owns_its_permission_and_needs_no_other_module() {
        assert_eq!(Module::Todo.code(), "todo");
        assert_eq!(Module::Todo.permissions(), &[Permission::TodoUse]);
        assert_eq!(permission_module(Permission::TodoUse), Some(Module::Todo));
        assert!(Module::Todo.requires().is_empty());
        // It can be switched off on its own.
        assert!(validate_company_disabled(&s(&["todo"])).is_ok());
    }

    #[test]
    fn codes_round_trip_and_are_unique() {
        for m in Module::ALL {
            assert_eq!(Module::from_code(m.code()), Some(m));
        }
        assert_eq!(Module::from_code("nope"), None);
    }

    #[test]
    fn requires_never_points_at_itself_or_cycles() {
        for m in Module::ALL {
            assert!(!m.requires().contains(&m));
            for r in m.requires() {
                assert!(!r.requires().contains(&m), "{m:?} <-> {r:?}");
            }
        }
    }

    #[test]
    fn company_validation_rejects_unknown_codes_and_broken_dependencies() {
        assert!(validate_company_disabled(&[]).unwrap().is_empty());
        assert!(validate_company_disabled(&s(&["kb", "helpdesk"])).is_ok());
        assert!(validate_company_disabled(&s(&["bogus"]))
            .unwrap_err()
            .contains("unknown module"));
        // Sales needs customers and products.
        assert!(validate_company_disabled(&s(&["customers"]))
            .unwrap_err()
            .contains("requires 'customers'"));
        assert!(validate_company_disabled(&s(&["customers", "sales"])).is_err());
        assert!(
            validate_company_disabled(&s(&["customers", "sales", "repairs", "field"])).is_err()
        );
        assert!(validate_company_disabled(&s(&[
            "customers",
            "sales",
            "repairs",
            "field",
            "configurator",
            "delivery",
            "production"
        ]))
        .is_ok());
        // Delivery takes stock out for sales orders: it needs both.
        // (the other dependants of sales and of inventory are switched off too, so the only one
        // left to complain is delivery).
        assert_eq!(
            validate_company_disabled(&s(&["sales", "configurator"])).unwrap_err(),
            "module 'delivery' requires 'sales'"
        );
        assert_eq!(
            validate_company_disabled(&s(&["inventory", "purchasing"])).unwrap_err(),
            "module 'delivery' requires 'inventory'"
        );
        assert!(validate_company_disabled(&s(&["delivery"])).is_ok());
        // Duplicates collapse.
        assert_eq!(
            validate_company_disabled(&s(&["kb", "kb"])).unwrap().len(),
            1
        );
    }

    #[test]
    fn effective_set_is_the_union_and_user_cannot_widen() {
        let eff = effective_disabled(&s(&["kb"]), &s(&["helpdesk"]));
        assert_eq!(eff, vec![Module::Helpdesk, Module::Kb]);
        let eff = effective_disabled(&s(&["kb"]), &s(&[]));
        assert_eq!(eff, vec![Module::Kb]);
        assert!(effective_disabled(&s(&["unknown"]), &s(&[])).is_empty());
    }

    #[test]
    fn user_validation_checks_the_combined_set() {
        assert!(validate_user_disabled(&s(&[]), &s(&["kb"])).is_ok());
        // Disabling products for a user who still has sales breaks the dependency.
        assert!(validate_user_disabled(&s(&[]), &s(&["products"])).is_err());
        // ...unless the company already switched sales off.
        assert!(validate_user_disabled(&s(&["sales"]), &s(&["products"])).is_err());
        assert!(validate_user_disabled(
            &s(&[
                "sales",
                "engineering",
                "inventory",
                "purchasing",
                "finance",
                "configurator",
                "delivery",
                "production"
            ]),
            &s(&["products"])
        )
        .is_ok());
        assert!(validate_user_disabled(&s(&[]), &s(&["bogus"])).is_err());
    }
}
