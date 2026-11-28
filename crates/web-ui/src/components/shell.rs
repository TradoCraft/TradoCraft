use leptos::prelude::*;
use leptos_router::components::A;
use leptos_router::hooks::{use_location, use_navigate};
use leptos_router::NavigateOptions;

use crate::api::ConnectionMode;
use crate::components::banners::{EnvironmentBanner, WorkerBanner};
use crate::components::chatter::{ChatterInboxButton, ChatterInboxDrawer};
use crate::components::global_search::GlobalSearchModal;
use crate::components::todo_widgets::todo_badge_state;
use crate::i18n::{tr, InterfaceLanguagePicker};
use crate::pages::record_detail::{DetailKind, RecordDetailView};
use crate::state::{ActiveSession, AppContext, ThemeMode, WorkspaceTab};

const APP_BASE: &str = "/app";

pub fn app_href(path: &str) -> String {
    format!("{APP_BASE}{path}")
}

pub struct NavItem {
    pub id: &'static str,
    pub path: &'static str,
    pub label: &'static str,
    pub live: bool,
    pub permission: Option<&'static str>,
    pub also_for: &'static [&'static str],
    pub module: Option<&'static str>,
    pub when_signed_out: bool,
}

pub struct NavGroup {
    pub title: &'static str,
    pub items: &'static [NavItem],
}

/// Module groupings matching `app/lib/core/navigation/app_groups.dart` and `app/lib/app/shell.dart`.
const NAV_GROUPS: &[NavGroup] = &[
    NavGroup {
        title: "Workspace",
        items: &[NavItem {
            id: "nav-home",
            path: "/home",
            label: "Home",
            live: true,
            permission: None,
            also_for: &[],
            module: None,
            when_signed_out: false,
        }],
    },
    NavGroup {
        title: "Master Data",
        items: &[
            NavItem {
                id: "nav-products",
                path: "/products",
                label: "Products",
                live: true,
                permission: Some("products.read"),
                also_for: &[],
                module: Some("products"),
                when_signed_out: false,
            },
            NavItem {
                id: "nav-customers",
                path: "/customers",
                label: "Customers",
                live: true,
                permission: Some("customers.read"),
                also_for: &[],
                module: Some("customers"),
                when_signed_out: false,
            },
            NavItem {
                id: "nav-price-lists",
                path: "/price-lists",
                label: "Price Lists",
                live: false,
                permission: Some("price_lists.read"),
                also_for: &[],
                module: Some("products"),
                when_signed_out: false,
            },
        ],
    },
    NavGroup {
        title: "Sales",
        items: &[
            NavItem {
                id: "nav-opportunities",
                path: "/opportunities",
                label: "Opportunities",
                live: false,
                permission: Some("opportunities.read"),
                also_for: &[],
                module: Some("customers"),
                when_signed_out: false,
            },
            NavItem {
                id: "nav-quotations",
                path: "/quotations",
                label: "Quotations",
                live: true,
                permission: Some("quotations.read"),
                also_for: &[],
                module: Some("sales"),
                when_signed_out: false,
            },
            NavItem {
                id: "nav-configurator",
                path: "/configurator",
                label: "Configurator",
                live: false,
                permission: Some("configurator.use"),
                also_for: &["configurator.design"],
                module: Some("configurator"),
                when_signed_out: false,
            },
            NavItem {
                id: "nav-orders",
                path: "/orders",
                label: "Orders",
                live: true,
                permission: Some("orders.read"),
                also_for: &[],
                module: Some("sales"),
                when_signed_out: false,
            },
            NavItem {
                id: "nav-delivery",
                path: "/delivery",
                label: "Delivery",
                live: false,
                permission: Some("delivery.read"),
                also_for: &[],
                module: Some("delivery"),
                when_signed_out: false,
            },
            NavItem {
                id: "nav-shipping",
                path: "/shipping",
                label: "Shipping",
                live: false,
                permission: Some("shipping.manage"),
                also_for: &[],
                module: Some("sales"),
                when_signed_out: false,
            },
        ],
    },
    NavGroup {
        title: "Service & Operations",
        items: &[
            NavItem {
                id: "nav-helpdesk",
                path: "/helpdesk",
                label: "Helpdesk",
                live: true,
                permission: Some("helpdesk.read"),
                also_for: &[],
                module: Some("helpdesk"),
                when_signed_out: false,
            },
            NavItem {
                id: "nav-answers",
                path: "/helpdesk/answers",
                label: "Standard answers",
                live: true,
                permission: Some("answers.write"),
                also_for: &["helpdesk.read"],
                module: Some("helpdesk"),
                when_signed_out: false,
            },
            NavItem {
                id: "nav-todo",
                path: "/todo",
                label: "To-do",
                live: true,
                permission: Some("todo.use"),
                also_for: &[],
                module: Some("todo"),
                when_signed_out: false,
            },
            NavItem {
                id: "nav-repairs",
                path: "/repairs",
                label: "Repairs",
                live: false,
                permission: Some("repairs.read"),
                also_for: &[],
                module: Some("repairs"),
                when_signed_out: false,
            },
            NavItem {
                id: "nav-packages",
                path: "/packages",
                label: "Packages",
                live: false,
                permission: Some("packages.read"),
                also_for: &[],
                module: Some("repairs"),
                when_signed_out: false,
            },
            NavItem {
                id: "nav-intake",
                path: "/intake",
                label: "Repair intake",
                live: false,
                permission: Some("repairs.intake"),
                also_for: &[],
                module: Some("repairs"),
                when_signed_out: false,
            },
            NavItem {
                id: "nav-jobs",
                path: "/jobs",
                label: "Field jobs",
                live: false,
                permission: Some("field.read"),
                also_for: &[],
                module: Some("field"),
                when_signed_out: false,
            },
            NavItem {
                id: "nav-planning",
                path: "/planning",
                label: "Planning",
                live: false,
                permission: Some("planning.read"),
                also_for: &[],
                module: Some("field"),
                when_signed_out: false,
            },
            NavItem {
                id: "nav-production",
                path: "/production",
                label: "Production",
                live: false,
                permission: Some("production.read"),
                also_for: &[],
                module: Some("production"),
                when_signed_out: false,
            },
            NavItem {
                id: "nav-mrp",
                path: "/mrp",
                label: "MRP",
                live: false,
                permission: Some("production.read"),
                also_for: &["purchasing.read"],
                module: None,
                when_signed_out: false,
            },
            NavItem {
                id: "nav-stock",
                path: "/stock",
                label: "Inventory",
                live: false,
                permission: Some("inventory.read"),
                also_for: &[],
                module: Some("inventory"),
                when_signed_out: false,
            },
        ],
    },
    NavGroup {
        title: "Back Office",
        items: &[
            NavItem {
                id: "nav-purchasing",
                path: "/purchasing",
                label: "Purchasing",
                live: true,
                permission: Some("purchasing.read"),
                also_for: &[],
                module: Some("purchasing"),
                when_signed_out: false,
            },
            NavItem {
                id: "nav-finance",
                path: "/finance",
                label: "Finance",
                live: false,
                permission: Some("finance.read"),
                also_for: &["billing.read", "rebates.admin"],
                module: Some("finance"),
                when_signed_out: false,
            },
            NavItem {
                id: "nav-reports",
                path: "/reports",
                label: "Reports",
                live: false,
                permission: Some("reports.read"),
                also_for: &[],
                module: Some("reports"),
                when_signed_out: false,
            },
            NavItem {
                id: "nav-admin",
                path: "/admin",
                label: "Admin",
                live: true,
                permission: Some("users.admin"),
                also_for: &[
                    "prices.write",
                    "products.write",
                    "identity.admin",
                    "audit.view",
                    "imports.admin",
                ],
                module: None,
                when_signed_out: false,
            },
        ],
    },
    NavGroup {
        title: "Customer Facing",
        items: &[
            NavItem {
                id: "nav-kb",
                path: "/kb",
                label: "Knowledge Base",
                live: true,
                permission: None,
                also_for: &[],
                module: None,
                when_signed_out: true,
            },
            NavItem {
                id: "nav-portal",
                path: "/portal",
                label: "Customer Portal",
                live: true,
                permission: None,
                also_for: &[],
                module: None,
                when_signed_out: true,
            },
        ],
    },
];

/// Returns whether a module is enabled for `active`, treating unlisted modules (e.g. test stubs)
/// as enabled while respecting explicit `enabled: false` flags from `GET /api/v1/me`.
pub(crate) fn module_available(active: &ActiveSession, code: Option<&str>) -> bool {
    let Some(code) = code else {
        return true;
    };
    active
        .me
        .modules
        .iter()
        .find(|m| m.code == code)
        .is_none_or(|m| m.enabled)
}

/// Whether `item` is visible in the navigation rail for `session`.
pub fn item_visible(item: &NavItem, session: Option<&ActiveSession>) -> bool {
    let Some(active) = session else {
        return item.when_signed_out;
    };
    if !module_available(active, item.module) {
        return false;
    }
    match item.permission {
        None => true,
        Some(perm) => {
            active.me.has_permission(perm)
                || item.also_for.iter().any(|p| active.me.has_permission(p))
        }
    }
}

/// Visible navigation groups and their items for `session`; groups with zero visible items are omitted.
pub fn visible_nav_groups(
    session: Option<&ActiveSession>,
) -> Vec<(&'static NavGroup, Vec<&'static NavItem>)> {
    NAV_GROUPS
        .iter()
        .filter_map(|group| {
            let items: Vec<&'static NavItem> = group
                .items
                .iter()
                .filter(|item| item_visible(item, session))
                .collect();
            (!items.is_empty()).then_some((group, items))
        })
        .collect()
}

/// The translation key of a navigation item: `nav-products` is `nav.products` (ADR 0101).
pub fn nav_key(id: &str) -> String {
    format!("nav.{}", id.trim_start_matches("nav-").replace('-', "_"))
}

/// The translation key of a navigation group title: `Service & Operations` is
/// `nav.group.service_operations`.
pub fn nav_group_key(title: &str) -> String {
    let lower = title.to_lowercase();
    let words: Vec<&str> = lower
        .split(|c: char| !c.is_ascii_alphanumeric())
        .filter(|w| !w.is_empty())
        .collect();
    format!("nav.group.{}", words.join("_"))
}

/// The English navigation texts by translation key, for the source catalogue.
pub fn nav_source_texts() -> Vec<(String, String)> {
    NAV_GROUPS
        .iter()
        .flat_map(|g| {
            std::iter::once((nav_group_key(g.title), g.title.to_string()))
                .chain(g.items.iter().map(|i| (nav_key(i.id), i.label.to_string())))
        })
        .collect()
}

/// Whether the navigation item at `href` is the current one: its own page, or a page below it
/// (such as `/app/admin/users`) that no other item names exactly.
pub fn nav_item_active(pathname: &str, href: &str) -> bool {
    if pathname == href {
        return true;
    }
    let below = pathname
        .strip_prefix(href)
        .is_some_and(|rest| rest.starts_with('/'));
    below
        && !NAV_GROUPS
            .iter()
            .flat_map(|g| g.items.iter())
            .any(|item| app_href(item.path) == pathname)
}

#[component]
pub fn AppShell(children: Children) -> impl IntoView {
    let ctx = expect_context::<AppContext>();
    let location = use_location();
    let navigate = use_navigate();
    let tutorial_state = RwSignal::new(crate::tutorial::TutorialState::new());
    let search_open = RwSignal::new(false);
    let inbox_open = RwSignal::new(false);

    #[cfg(target_arch = "wasm32")]
    {
        use wasm_bindgen::closure::Closure;
        use wasm_bindgen::JsCast;
        if let Some(win) = web_sys::window() {
            let target: web_sys::EventTarget = win.into();
            let cb = Closure::<dyn FnMut(web_sys::KeyboardEvent)>::new(
                move |ev: web_sys::KeyboardEvent| {
                    let is_shortcut =
                        (ev.ctrl_key() || ev.meta_key()) && ev.key().eq_ignore_ascii_case("k");
                    if is_shortcut && ctx.session.with_untracked(Option::is_some) {
                        ev.prevent_default();
                        search_open.update(|v| *v = !*v);
                    }
                },
            );
            let _ = target.add_event_listener_with_callback("keydown", cb.as_ref().unchecked_ref());
            let target_cleanup = target;
            let cb_holder = StoredValue::new_local(cb);
            on_cleanup(move || {
                cb_holder.with_value(|cb| {
                    let _ = target_cleanup.remove_event_listener_with_callback(
                        "keydown",
                        cb.as_ref().unchecked_ref(),
                    );
                });
            });
        }
    }

    let session_info = Memo::new(move |_| {
        ctx.session.with(|s| {
            s.as_ref().map(|active| {
                (
                    active.me.display_name.clone(),
                    active.me.company.name.clone(),
                )
            })
        })
    });

    // Key only on (id, route) so updating tab title/subtitle on load does not re-mount the view.
    let active_tab_key = Memo::new(move |_| {
        let active_id = ctx.active_tab.get()?;
        ctx.tabs.with(|tabs| {
            tabs.iter()
                .find(|t| t.id == active_id)
                .map(|t| (t.id.clone(), t.route.clone()))
        })
    });

    let on_toggle_theme = move |_| {
        ctx.theme.update(|t| *t = t.toggle());
    };

    let on_overview = {
        let navigate = navigate.clone();
        move |_| {
            ctx.active_tab.set(None);
            let deep = location
                .pathname
                .with_untracked(|p| DetailKind::parse_route(p));
            if let Some((kind, _)) = deep {
                navigate(kind.list_route(), NavigateOptions::default());
            }
        }
    };

    let on_sign_out = {
        let navigate = navigate.clone();
        move |_| {
            ctx.draft_connection.update(|mode| {
                if let ConnectionMode::Live(session) = mode {
                    *session = session.signed_out();
                }
            });
            ctx.sign_out();
            navigate("/login", NavigateOptions::default());
        }
    };

    view! {
        <div class="tc-app-frame">
            <EnvironmentBanner />
            <WorkerBanner />
            <div class="tc-shell">
                <header class="tc-topbar">
                    <div class="tc-brand">
                        <span class="tc-brand-mark">"TC"</span>
                        <span>"TradoCraft"</span>
                        <span class="tc-badge tc-badge-primary">"Web UI Spike"</span>
                    </div>

                    <div class="tc-topbar-meta">
                        {move || match session_info.get() {
                            Some((user_name, company_name)) => view! {
                                <span class="tc-badge" data-target="active-company">{company_name}</span>
                                <span
                                    style="font-size: 12px; color: var(--on-surface-variant);"
                                    data-target="active-user"
                                >
                                    {user_name}
                                </span>
                                <button
                                    type="button"
                                    data-target="global-search-open"
                                    class="tc-btn tc-btn-ghost tc-btn-sm"
                                    on:click=move |_| search_open.set(true)
                                >
                                    <span>{move || tr("shell.search", "Search")}</span>
                                    <kbd class="tc-kbd">"Ctrl+K"</kbd>
                                </button>
                                <ChatterInboxButton open=inbox_open />
                                <button
                                    type="button"
                                    data-target="tutorial-toggle"
                                    class="tc-btn tc-btn-ghost tc-btn-sm"
                                    on:click=move |_| tutorial_state.update(|t| t.active = !t.active)
                                >
                                    {move || tr("shell.tutorial", "Tutorial")}
                                </button>
                                <button
                                    type="button"
                                    data-target="theme-toggle"
                                    class="tc-btn tc-btn-ghost tc-btn-sm"
                                    on:click=on_toggle_theme
                                >
                                    {move || match ctx.theme.get() {
                                        ThemeMode::Dark => tr("shell.light_mode", "Light mode"),
                                        ThemeMode::Light => tr("shell.dark_mode", "Dark mode"),
                                    }}
                                </button>
                                <button
                                    type="button"
                                    data-target="sign-out"
                                    class="tc-btn tc-btn-sm"
                                    on:click=on_sign_out.clone()
                                >
                                    {move || tr("shell.sign_out", "Sign out")}
                                </button>
                                <InterfaceLanguagePicker />
                            }.into_any(),
                            None => view! {
                                <button
                                    type="button"
                                    data-target="tutorial-toggle"
                                    class="tc-btn tc-btn-ghost tc-btn-sm"
                                    on:click=move |_| tutorial_state.update(|t| t.active = !t.active)
                                >
                                    {move || tr("shell.tutorial", "Tutorial")}
                                </button>
                                <button
                                    type="button"
                                    data-target="theme-toggle"
                                    class="tc-btn tc-btn-ghost tc-btn-sm"
                                    on:click=on_toggle_theme
                                >
                                    {move || match ctx.theme.get() {
                                        ThemeMode::Dark => tr("shell.light_mode", "Light mode"),
                                        ThemeMode::Light => tr("shell.dark_mode", "Dark mode"),
                                    }}
                                </button>
                                <A href=app_href("/login") attr:class="tc-btn tc-btn-primary tc-btn-sm" attr:data-target="sign-in-link">
                                    "Sign in"
                                </A>
                            }.into_any(),
                        }}
                    </div>
                </header>

                <nav class="tc-tabbar" aria-label="Workspace tabs" data-target="workspace-tabbar">
                    <button
                        type="button"
                        data-target="workspace-tab-overview"
                        class=move || {
                            let on_deep = location
                                .pathname
                                .with(|p| DetailKind::parse_route(p).is_some());
                            if ctx.active_tab.get().is_none() && !on_deep {
                                "tc-tab tc-tab-active"
                            } else {
                                "tc-tab"
                            }
                        }
                        on:click=on_overview
                    >
                        "Overview"
                    </button>
                    <For
                        each=move || ctx.tabs.get()
                        key=|tab| (tab.id.clone(), tab.title.clone())
                        children=move |tab| {
                            let tab_id_select = tab.id.clone();
                            let tab_id_active = tab.id.clone();
                            let tab_id_close = tab.id.clone();
                            let tab_route_active = app_href(&tab.route);
                            let tab_target = format!("workspace-tab-{}", tab.id);
                            view! {
                                <div
                                    data-target=tab_target
                                    class=move || {
                                        let by_id = ctx.active_tab.get().as_deref() == Some(tab_id_active.as_str());
                                        let by_route = ctx.active_tab.get().is_none()
                                            && location.pathname.with(|p| p == &tab_route_active);
                                        if by_id || by_route {
                                            "tc-tab tc-tab-active"
                                        } else {
                                            "tc-tab"
                                        }
                                    }
                                >
                                    <button
                                        type="button"
                                        class="tc-tab-close"
                                        style="color: inherit; font-size: 12px;"
                                        on:click=move |_| ctx.active_tab.set(Some(tab_id_select.clone()))
                                    >
                                        {tab.title.clone()}
                                    </button>
                                    <button
                                        type="button"
                                        class="tc-tab-close"
                                        data-target="workspace-tab-close"
                                        aria-label="Close tab"
                                        on:click=move |_| ctx.close_tab(&tab_id_close)
                                    >
                                        "×"
                                    </button>
                                </div>
                            }
                        }
                    />
                </nav>

                <aside class="tc-sidebar" aria-label="Modules" data-target="module-nav">
                    {move || {
                        ctx.session
                            .with(|s| visible_nav_groups(s.as_ref()))
                            .into_iter()
                            .map(|(group, items)| {
                                view! {
                                    <div>
                                        <div class="tc-nav-group-label">
                                            {move || tr(&nav_group_key(group.title), group.title)}
                                        </div>
                                        <div class="tc-nav-list">
                                            {items.into_iter().map(|item| {
                                                let href = app_href(item.path);
                                                let active_href = href.clone();
                                                let active_class = move || {
                                                    if nav_item_active(&location.pathname.get(), &active_href) {
                                                        "tc-nav-item active"
                                                    } else {
                                                        "tc-nav-item"
                                                    }
                                                };
                                                let is_todo_item = item.id == "nav-todo";
                                                view! {
                                                    <A
                                                        href=href
                                                        attr:class=active_class
                                                        attr:data-target=item.id
                                                        on:click=move |_| ctx.active_tab.set(None)
                                                    >
                                                        <span>{move || tr(&nav_key(item.id), item.label)}</span>
                                                        {if !item.live {
                                                            view! { <span class="tc-badge">"Soon"</span> }.into_any()
                                                        } else if is_todo_item {
                                                            view! {
                                                                {move || todo_badge_state(ctx.todo_counts.get()).map(|(count, overdue)| view! {
                                                                    <span
                                                                        class=if overdue { "tc-badge tc-badge-error" } else { "tc-badge tc-badge-primary" }
                                                                        data-target="todo-nav-badge"
                                                                    >
                                                                        {count}
                                                                    </span>
                                                                })}
                                                            }.into_any()
                                                        } else {
                                                            view! { <span></span> }.into_any()
                                                        }}
                                                    </A>
                                                }
                                            }).collect_view()}
                                        </div>
                                    </div>
                                }
                            })
                            .collect_view()
                    }}
                </aside>

                <main class="tc-main">
                    {move || match active_tab_key.get() {
                        Some((tab_id, route)) => view! { <WorkspaceTabView tab_id=tab_id route=route /> }.into_any(),
                        None => view! { <div></div> }.into_any(),
                    }}
                    <div style:display=move || if active_tab_key.get().is_some() { "none" } else { "block" }>
                        {children()}
                    </div>
                </main>
                <GlobalSearchModal open=search_open />
                <ChatterInboxDrawer open=inbox_open />
                <crate::components::tutorial_overlay::TutorialOverlay state=tutorial_state />
            </div>
        </div>
    }
}

#[component]
fn WorkspaceTabView(tab_id: String, route: String) -> impl IntoView {
    let ctx = expect_context::<AppContext>();
    let parsed = DetailKind::parse_route(&route);
    let tab_id_close = tab_id.clone();
    let route_fallback = route.clone();

    view! {
        <div data-target="workspace-tab-view">
            {match parsed {
                Some((kind, id)) => {
                    let tab_id_loaded = tab_id.clone();
                    let tab_route = route.clone();
                    let on_loaded = Callback::new(move |(title, subtitle): (String, String)| {
                        ctx.register_tab(WorkspaceTab {
                            id: tab_id_loaded.clone(),
                            title,
                            route: tab_route.clone(),
                            subtitle,
                        });
                    });
                    view! { <RecordDetailView kind=kind id=id on_loaded=on_loaded /> }.into_any()
                }
                None => view! {
                    <div class="tc-card" style="max-width: 680px;" data-target="workspace-tab-fallback">
                        <div class="tc-page-header" style="margin-bottom: var(--space-md);">
                            <div>
                                <h2 class="tc-page-title" style="font-size: 18px;">{route_fallback}</h2>
                            </div>
                            <button
                                type="button"
                                class="tc-btn tc-btn-sm"
                                on:click=move |_| ctx.close_tab(&tab_id_close)
                            >
                                "Close tab"
                            </button>
                        </div>
                    </div>
                }
                .into_any(),
            }}
        </div>
    }
}

#[cfg(test)]
mod tests {
    use tradocraft_api_client::{Company, Me, MeModule};
    use uuid::Uuid;

    use super::*;

    fn session_with(perms: &[&str], modules: &[(&str, bool)]) -> ActiveSession {
        ActiveSession {
            connection: ConnectionMode::MockDemo,
            me: Me {
                user_id: Uuid::nil(),
                email: "user@example.com".into(),
                display_name: "User".into(),
                company: Company {
                    id: Uuid::nil(),
                    name: "Demo".into(),
                    vat_number: None,
                    street: String::new(),
                    postal_code: String::new(),
                    city: String::new(),
                    country_code: "BE".into(),
                    currency: "EUR".into(),
                    email: None,
                    phone: None,
                    iban: None,
                    default_language: "en".into(),
                    languages: vec!["en".into()],
                    is_primary: true,
                    quotation_single_line_items: true,
                    autosave_minutes: 5,
                },
                roles: vec![],
                permissions: perms.iter().map(|s| s.to_string()).collect(),
                modules: modules
                    .iter()
                    .map(|(c, enabled)| MeModule {
                        code: (*c).to_string(),
                        enabled: *enabled,
                    })
                    .collect(),
                memberships: vec![],
            },
        }
    }

    fn visible_ids(session: Option<&ActiveSession>) -> Vec<&'static str> {
        visible_nav_groups(session)
            .into_iter()
            .flat_map(|(_, items)| items.into_iter().map(|i| i.id))
            .collect()
    }

    #[test]
    fn sub_pages_mark_their_parent_unless_another_item_matches() {
        assert!(nav_item_active("/app/admin", "/app/admin"));
        assert!(nav_item_active("/app/admin/users", "/app/admin"));
        assert!(!nav_item_active("/app/administration", "/app/admin"));
        assert!(!nav_item_active("/app/helpdesk/answers", "/app/helpdesk"));
        assert!(nav_item_active(
            "/app/helpdesk/answers",
            "/app/helpdesk/answers"
        ));
    }

    #[test]
    fn signed_out_nav_shows_only_public_destinations() {
        assert_eq!(visible_ids(None), vec!["nav-kb", "nav-portal"]);
    }

    #[test]
    fn nav_respects_permissions_and_disabled_modules() {
        let sales = session_with(&["products.read", "quotations.read", "todo.use"], &[]);
        let ids = visible_ids(Some(&sales));
        assert!(ids.contains(&"nav-home"));
        assert!(ids.contains(&"nav-products"));
        assert!(ids.contains(&"nav-quotations"));
        assert!(ids.contains(&"nav-todo"));
        assert!(ids.contains(&"nav-kb"));
        assert!(ids.contains(&"nav-portal"));
        assert!(!ids.contains(&"nav-admin"));
        assert!(!ids.contains(&"nav-finance"));
        assert!(!ids.contains(&"nav-purchasing"));

        // Explicit module switch-off hides the item even if a permission string remained.
        let disabled_products = session_with(&["products.read"], &[("products", false)]);
        assert!(!visible_ids(Some(&disabled_products)).contains(&"nav-products"));

        // Non-admin permissions that grant Admin section access still show nav-admin.
        let auditor = session_with(&["audit.view"], &[]);
        assert!(visible_ids(Some(&auditor)).contains(&"nav-admin"));
    }
}
