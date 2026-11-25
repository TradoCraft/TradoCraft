use leptos::prelude::*;
use leptos_router::components::A;
use leptos_router::hooks::{use_location, use_navigate};
use leptos_router::NavigateOptions;

use crate::api::ConnectionMode;
use crate::state::{AppContext, ThemeMode, WorkspaceTab};

const APP_BASE: &str = "/app";

pub fn app_href(path: &str) -> String {
    format!("{APP_BASE}{path}")
}

struct NavItem {
    id: &'static str,
    path: &'static str,
    label: &'static str,
    live: bool,
}

struct NavGroup {
    title: &'static str,
    items: &'static [NavItem],
}

/// Module groupings matching `app/lib/core/navigation/app_groups.dart`.
const NAV_GROUPS: &[NavGroup] = &[
    NavGroup {
        title: "Master Data",
        items: &[
            NavItem {
                id: "nav-products",
                path: "/products",
                label: "Products",
                live: true,
            },
            NavItem {
                id: "nav-customers",
                path: "/customers",
                label: "Customers",
                live: true,
            },
            NavItem {
                id: "nav-price-lists",
                path: "/price-lists",
                label: "Price Lists",
                live: false,
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
            },
            NavItem {
                id: "nav-quotations",
                path: "/quotations",
                label: "Quotations",
                live: true,
            },
            NavItem {
                id: "nav-orders",
                path: "/orders",
                label: "Orders",
                live: true,
            },
            NavItem {
                id: "nav-delivery",
                path: "/delivery",
                label: "Delivery",
                live: false,
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
            },
            NavItem {
                id: "nav-repairs",
                path: "/repairs",
                label: "Repairs",
                live: false,
            },
            NavItem {
                id: "nav-production",
                path: "/production",
                label: "Production",
                live: false,
            },
            NavItem {
                id: "nav-stock",
                path: "/stock",
                label: "Inventory",
                live: false,
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
            },
            NavItem {
                id: "nav-finance",
                path: "/finance",
                label: "Finance",
                live: false,
            },
            NavItem {
                id: "nav-admin",
                path: "/admin",
                label: "Admin",
                live: false,
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
            },
            NavItem {
                id: "nav-portal",
                path: "/portal",
                label: "Customer Portal",
                live: true,
            },
        ],
    },
];

#[component]
pub fn AppShell(children: Children) -> impl IntoView {
    let ctx = expect_context::<AppContext>();
    let location = use_location();
    let navigate = use_navigate();
    let tutorial_state = RwSignal::new(crate::tutorial::TutorialState::new());

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

    let active_tab_data = Memo::new(move |_| {
        let active_id = ctx.active_tab.get();
        active_id.and_then(|id| {
            ctx.tabs
                .with(|tabs| tabs.iter().find(|t| t.id == id).cloned())
        })
    });

    let on_toggle_theme = move |_| {
        ctx.theme.update(|t| *t = t.toggle());
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
                                data-target="tutorial-toggle"
                                class="tc-btn tc-btn-ghost tc-btn-sm"
                                on:click=move |_| tutorial_state.update(|t| t.active = !t.active)
                            >
                                "Tutorial"
                            </button>
                            <button
                                type="button"
                                data-target="theme-toggle"
                                class="tc-btn tc-btn-ghost tc-btn-sm"
                                on:click=on_toggle_theme
                            >
                                {move || match ctx.theme.get() {
                                    ThemeMode::Dark => "Light mode",
                                    ThemeMode::Light => "Dark mode",
                                }}
                            </button>
                            <button
                                type="button"
                                data-target="sign-out"
                                class="tc-btn tc-btn-sm"
                                on:click=on_sign_out.clone()
                            >
                                "Sign out"
                            </button>
                        }.into_any(),
                        None => view! {
                            <button
                                type="button"
                                data-target="tutorial-toggle"
                                class="tc-btn tc-btn-ghost tc-btn-sm"
                                on:click=move |_| tutorial_state.update(|t| t.active = !t.active)
                            >
                                "Tutorial"
                            </button>
                            <button
                                type="button"
                                data-target="theme-toggle"
                                class="tc-btn tc-btn-ghost tc-btn-sm"
                                on:click=on_toggle_theme
                            >
                                {move || match ctx.theme.get() {
                                    ThemeMode::Dark => "Light mode",
                                    ThemeMode::Light => "Dark mode",
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
                        if ctx.active_tab.get().is_none() {
                            "tc-tab tc-tab-active"
                        } else {
                            "tc-tab"
                        }
                    }
                    on:click=move |_| ctx.active_tab.set(None)
                >
                    "Overview"
                </button>
                <For
                    each=move || ctx.tabs.get()
                    key=|tab| tab.id.clone()
                    children=move |tab| {
                        let tab_id_select = tab.id.clone();
                        let tab_id_active = tab.id.clone();
                        let tab_id_close = tab.id.clone();
                        let tab_target = format!("workspace-tab-{}", tab.id);
                        view! {
                            <div
                                data-target=tab_target
                                class=move || {
                                    if ctx.active_tab.get().as_deref() == Some(tab_id_active.as_str()) {
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
                {NAV_GROUPS.iter().map(|group| {
                    view! {
                        <div>
                            <div class="tc-nav-group-label">{group.title}</div>
                            <div class="tc-nav-list">
                                {group.items.iter().map(|item| {
                                    let href = app_href(item.path);
                                    let active_href = href.clone();
                                    let active_class = move || {
                                        if location.pathname.get() == active_href {
                                            "tc-nav-item active"
                                        } else {
                                            "tc-nav-item"
                                        }
                                    };
                                    view! {
                                        <A
                                            href=href
                                            attr:class=active_class
                                            attr:data-target=item.id
                                            on:click=move |_| ctx.active_tab.set(None)
                                        >
                                            <span>{item.label}</span>
                                            {if !item.live {
                                                view! { <span class="tc-badge">"Soon"</span> }.into_any()
                                            } else {
                                                view! { <span></span> }.into_any()
                                            }}
                                        </A>
                                    }
                                }).collect_view()}
                            </div>
                        </div>
                    }
                }).collect_view()}
            </aside>

            <main class="tc-main">
                {move || match active_tab_data.get() {
                    Some(tab) => view! { <WorkspaceTabPlaceholder tab=tab /> }.into_any(),
                    None => view! { <div></div> }.into_any(),
                }}
                <div style:display=move || if active_tab_data.get().is_some() { "none" } else { "block" }>
                    {children()}
                </div>
            </main>
            <crate::components::tutorial_overlay::TutorialOverlay state=tutorial_state />
        </div>
    }
}

#[component]
fn WorkspaceTabPlaceholder(tab: WorkspaceTab) -> impl IntoView {
    let ctx = expect_context::<AppContext>();
    let tab_id = tab.id.clone();

    view! {
        <div class="tc-card" style="max-width: 680px;" data-target="workspace-tab-placeholder">
            <div class="tc-page-header" style="margin-bottom: var(--space-md);">
                <div>
                    <h2 class="tc-page-title" style="font-size: 18px;">{tab.title}</h2>
                    <p class="tc-page-subtitle tc-mono">{tab.route}</p>
                </div>
                <button
                    type="button"
                    data-target="workspace-tab-placeholder-close"
                    class="tc-btn tc-btn-sm"
                    on:click=move |_| ctx.close_tab(&tab_id)
                >
                    "Close tab"
                </button>
            </div>
            <p style="margin: 0 0 var(--space-md); color: var(--on-surface-variant);">
                {tab.subtitle}
            </p>
            <p style="margin: 0; font-size: 12px; color: var(--outline);">
                "ADR 0041 workspace-tab placeholder: detail editors stay mounted per tab while switching back to Overview."
            </p>
        </div>
    }
}
