//! Administration: one destination with a section per area, each shown only with its permission.
//! Mirrors `app/lib/features/admin/admin_page.dart` (without the site baseline types and the
//! configurator builder shortcut). Every section is deep-linkable as `/admin/<section>`.

pub mod attributes;
pub mod audit;
pub mod company;
pub mod identity;
pub mod imports;
pub mod languages;
pub mod modules;
pub mod translations;
pub mod users;
pub mod vat;
pub mod zones;

use leptos::prelude::*;
use leptos_router::components::A;
use leptos_router::hooks::use_params_map;

pub(crate) use crate::components::async_ops::{bump, is_current, refresh_me, spawn_api};
pub use crate::components::feedback::{Feedback, FeedbackView};
pub(crate) use crate::components::files::{
    begin_file_read, format_file_size as file_size, save_file, PickedFile,
};
use crate::state::AppContext;

/// The sections of the administration, in the order Flutter shows them.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AdminSection {
    Users,
    Modules,
    Company,
    Vat,
    Zones,
    Attributes,
    Identity,
    Audit,
    Import,
}

impl AdminSection {
    pub const ALL: [AdminSection; 9] = [
        AdminSection::Users,
        AdminSection::Modules,
        AdminSection::Company,
        AdminSection::Vat,
        AdminSection::Zones,
        AdminSection::Attributes,
        AdminSection::Identity,
        AdminSection::Audit,
        AdminSection::Import,
    ];

    /// The path segment: `/admin/<key>`.
    pub fn key(self) -> &'static str {
        match self {
            Self::Users => "users",
            Self::Modules => "modules",
            Self::Company => "company",
            Self::Vat => "vat",
            Self::Zones => "zones",
            Self::Attributes => "attributes",
            Self::Identity => "identity",
            Self::Audit => "audit",
            Self::Import => "import",
        }
    }

    pub fn label(self) -> &'static str {
        match self {
            Self::Users => "Users",
            Self::Modules => "Modules",
            Self::Company => "Company",
            Self::Vat => "VAT rates",
            Self::Zones => "Price zones",
            Self::Attributes => "Attributes",
            Self::Identity => "Identity providers",
            Self::Audit => "Audit trail",
            Self::Import => "Import",
        }
    }

    pub fn from_key(key: &str) -> Option<Self> {
        Self::ALL.into_iter().find(|s| s.key() == key)
    }

    /// Whether a user holding the permissions `can` answers for may open the section. Mirrors the
    /// gating of the Flutter admin page.
    pub fn allowed(self, can: &impl Fn(&str) -> bool) -> bool {
        match self {
            // User administration needs users.admin; price zones are open to prices.write.
            Self::Users | Self::Modules | Self::Company | Self::Vat => can("users.admin"),
            Self::Zones => can("prices.write"),
            Self::Attributes => can("products.write"),
            Self::Identity => can("identity.admin"),
            Self::Audit => can("audit.view"),
            Self::Import => can("imports.admin"),
        }
    }
}

/// The sections the permissions allow, in display order.
pub fn allowed_sections(can: impl Fn(&str) -> bool) -> Vec<AdminSection> {
    AdminSection::ALL
        .into_iter()
        .filter(|s| s.allowed(&can))
        .collect()
}

/// The section to show for the requested path segment: the requested one when it is allowed,
/// else the first allowed one; none when nothing is allowed.
pub fn pick_section(requested: Option<&str>, allowed: &[AdminSection]) -> Option<AdminSection> {
    requested
        .and_then(AdminSection::from_key)
        .filter(|s| allowed.contains(s))
        .or_else(|| allowed.first().copied())
}

/// Display name of a role code; unknown codes show as they are.
pub(crate) fn role_name(code: &str) -> &str {
    match code {
        "admin" => "Administrator",
        "sales_manager" => "Sales manager",
        "sales" => "Sales",
        "support" => "Support",
        "production" => "Production",
        "warehouse" => "Warehouse",
        "product_manager" => "Product manager",
        "workshop" => "Workshop",
        "technician" => "Technician",
        "dispatcher" => "Dispatcher",
        "logistics" => "Logistics",
        "viewer" => "Viewer",
        "finance" => "Finance",
        other => other,
    }
}

/// Display name of a module code; unknown codes show as they are.
pub(crate) fn module_name(code: &str) -> &str {
    match code {
        "customers" => "Customers",
        "products" => "Products",
        "sales" => "Sales",
        "engineering" => "Engineering",
        "inventory" => "Inventory",
        "helpdesk" => "Helpdesk",
        "kb" => "Knowledge base",
        "repairs" => "Repairs",
        "field" => "Field service",
        "delivery" => "Delivery",
        "production" => "Production",
        "finance" => "Finance",
        "todo" => "To-do",
        other => other,
    }
}

/// `names` of the module codes, comma separated.
pub(crate) fn module_names(codes: &[String]) -> String {
    codes
        .iter()
        .map(|c| module_name(c))
        .collect::<Vec<_>>()
        .join(", ")
}

#[component]
pub fn AdminPage() -> impl IntoView {
    let ctx = expect_context::<AppContext>();
    let params = use_params_map();

    let allowed = Memo::new(move |_| {
        ctx.session.with(|s| match s {
            Some(active) => allowed_sections(|p| active.me.has_permission(p)),
            None => Vec::new(),
        })
    });
    let section = Memo::new(move |_| {
        let requested = params.with(|p| p.get("section"));
        allowed.with(|list| pick_section(requested.as_deref(), list))
    });
    let is_signed_in = Memo::new(move |_| ctx.session.with(|s| s.is_some()));

    view! {
        <div data-target="admin-page">
            <div class="tc-page-header">
                <div>
                    <h1 class="tc-page-title">"Administration"</h1>
                    <p class="tc-page-subtitle">
                        {move || section.get().map(|s| s.label()).unwrap_or("")}
                    </p>
                </div>
            </div>
            <Show
                when=move || is_signed_in.get()
                fallback=|| view! {
                    <div class="tc-card">
                        <p style="margin: 0 0 var(--space-md);">"Sign in to open the administration."</p>
                        <A href=crate::components::shell::app_href("/login") attr:class="tc-btn tc-btn-primary" attr:data-target="admin-go-login">
                            "Go to sign in"
                        </A>
                    </div>
                }
            >
                <Show
                    when=move || !allowed.with(Vec::is_empty)
                    fallback=|| view! {
                        <div class="tc-card" data-target="admin-no-access">
                            <p style="margin: 0;">"You have no permission for any part of the administration."</p>
                        </div>
                    }
                >
                    <Show when=move || allowed.with(|l| l.len() > 1)>
                        <nav class="tc-inline-tabs" aria-label="Administration sections" data-target="admin-sections" style="margin-bottom: var(--space-md); flex-wrap: wrap;">
                            {move || allowed.get().into_iter().map(|s| {
                                let active = move || section.get() == Some(s);
                                view! {
                                    <A
                                        href=crate::components::shell::app_href(&format!("/admin/{}", s.key()))
                                        attr:class=move || if active() { "tc-inline-tab-btn tc-inline-tab-active" } else { "tc-inline-tab-btn" }
                                        attr:aria-current=move || active().then_some("page")
                                        attr:data-target=format!("admin-section-{}", s.key())
                                    >
                                        {s.label()}
                                    </A>
                                }
                            }).collect_view()}
                        </nav>
                    </Show>
                    {move || match section.get() {
                        Some(AdminSection::Users) => view! { <users::UsersSection /> }.into_any(),
                        Some(AdminSection::Modules) => view! { <modules::ModulesSection /> }.into_any(),
                        Some(AdminSection::Company) => view! { <company::CompanySection /> }.into_any(),
                        Some(AdminSection::Vat) => view! { <vat::VatSection /> }.into_any(),
                        Some(AdminSection::Zones) => view! { <zones::ZonesSection /> }.into_any(),
                        Some(AdminSection::Attributes) => view! { <attributes::AttributesSection /> }.into_any(),
                        Some(AdminSection::Identity) => view! { <identity::IdentitySection /> }.into_any(),
                        Some(AdminSection::Audit) => view! { <audit::AuditSection /> }.into_any(),
                        Some(AdminSection::Import) => view! { <imports::ImportsSection /> }.into_any(),
                        None => view! { <div></div> }.into_any(),
                    }}
                </Show>
            </Show>
        </div>
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sections_follow_the_permissions() {
        assert!(allowed_sections(|_| false).is_empty());
        assert_eq!(
            allowed_sections(|p| p == "users.admin"),
            vec![
                AdminSection::Users,
                AdminSection::Modules,
                AdminSection::Company,
                AdminSection::Vat
            ]
        );
        assert_eq!(
            allowed_sections(|p| p == "prices.write"),
            vec![AdminSection::Zones]
        );
        assert_eq!(
            allowed_sections(|p| p == "products.write"),
            vec![AdminSection::Attributes]
        );
    }

    #[test]
    fn picks_the_requested_section_or_the_first_allowed() {
        let allowed = [AdminSection::Users];
        assert_eq!(
            pick_section(Some("users"), &allowed),
            Some(AdminSection::Users)
        );
        assert_eq!(
            pick_section(Some("nope"), &allowed),
            Some(AdminSection::Users)
        );
        assert_eq!(pick_section(None, &allowed), Some(AdminSection::Users));
        assert_eq!(pick_section(Some("users"), &[]), None);
    }

    #[test]
    fn formats_file_sizes() {
        assert_eq!(file_size(512), "512 B");
        assert_eq!(file_size(1536), "1.5 KB");
        assert_eq!(file_size(3 * 1024 * 1024), "3.0 MB");
    }

    #[test]
    fn names_roles_and_modules() {
        assert_eq!(role_name("sales_manager"), "Sales manager");
        assert_eq!(role_name("custom"), "custom");
        assert_eq!(
            module_names(&["kb".into(), "todo".into()]),
            "Knowledge base, To-do"
        );
    }
}
