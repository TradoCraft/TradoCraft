//! Global search modal (`Ctrl+K` / topbar button) across visible navigation destinations and
//! permission-gated live business entities.

use leptos::prelude::*;
use leptos_router::hooks::use_navigate;
use leptos_router::NavigateOptions;
use tradocraft_api_client::helpdesk::ListTicketsParams;
use tradocraft_api_client::kb::ListKbEntriesParams;
use tradocraft_api_client::sales::{ListOrdersParams, ListQuotationsParams};
use tradocraft_api_client::suppliers::ListSuppliersParams;

use crate::api::{ConnectionMode, ListCustomersParams, ListProductsParams};
use crate::components::async_ops::{set_alive, spawn_api, RequestGuard};
use crate::components::modal::Modal;
use crate::components::shell::visible_nav_groups;
use crate::i18n::tr;
use crate::pages::home::has_card_access;
use crate::state::{ActiveSession, AppContext};

const SEARCH_ENTITY_LIMIT: i64 = 5;

/// One navigable match in the global search modal.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SearchHit {
    pub title: String,
    pub subtitle: Option<String>,
    pub path: String,
}

/// Search hits from one source (navigation destinations or one API entity).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SearchGroup {
    pub id: &'static str,
    pub label: &'static str,
    pub hits: Vec<SearchHit>,
    pub failed: bool,
}

/// Lowercases `input` and folds common Western European diacritics for accent-insensitive search.
pub fn fold_for_search(input: &str) -> String {
    input
        .to_lowercase()
        .chars()
        .map(|c| match c {
            'à' | 'á' | 'â' | 'ã' | 'ä' | 'å' => 'a',
            'ç' => 'c',
            'è' | 'é' | 'ê' | 'ë' => 'e',
            'ì' | 'í' | 'î' | 'ï' => 'i',
            'ñ' => 'n',
            'ò' | 'ó' | 'ô' | 'õ' | 'ö' => 'o',
            'ù' | 'ú' | 'û' | 'ü' => 'u',
            'ý' | 'ÿ' => 'y',
            other => other,
        })
        .collect()
}

/// Matches visible sidebar destinations against `query` using case- and accent-folded substrings.
pub fn match_nav_hits(query: &str, session: Option<&ActiveSession>) -> Vec<SearchHit> {
    let needle = fold_for_search(query.trim());
    if needle.is_empty() {
        return Vec::new();
    }
    let mut hits = Vec::new();
    for (group, items) in visible_nav_groups(session) {
        for item in items {
            let label = item.label;
            if fold_for_search(label).contains(&needle)
                || fold_for_search(group.title).contains(&needle)
                || fold_for_search(item.path).contains(&needle)
            {
                hits.push(SearchHit {
                    title: label.to_string(),
                    subtitle: Some(group.title.to_string()),
                    path: item.path.to_string(),
                });
            }
        }
    }
    hits
}

fn join_parts(parts: &[Option<&str>]) -> Option<String> {
    let joined: Vec<&str> = parts
        .iter()
        .flatten()
        .map(|s| s.trim())
        .filter(|s| !s.is_empty())
        .collect();
    (!joined.is_empty()).then(|| joined.join(" · "))
}

async fn run_live_entity_search(
    client: tradocraft_api_client::Client,
    active: ActiveSession,
    query: String,
) -> Vec<SearchGroup> {
    let mut groups = Vec::new();

    if has_card_access(&active, "customers.read", "customers") {
        let params = ListCustomersParams {
            q: Some(query.clone()),
            limit: Some(SEARCH_ENTITY_LIMIT),
            ..ListCustomersParams::default()
        };
        let group = match client.list_customers(&params).await {
            Ok(page) => SearchGroup {
                id: "customers",
                label: "Customers",
                hits: page
                    .items
                    .into_iter()
                    .map(|c| SearchHit {
                        title: c.name,
                        subtitle: join_parts(&[Some(&c.code), Some(&c.city)]),
                        path: format!("/customers/{}", c.id),
                    })
                    .collect(),
                failed: false,
            },
            Err(_) => SearchGroup {
                id: "customers",
                label: "Customers",
                hits: Vec::new(),
                failed: true,
            },
        };
        if group.failed || !group.hits.is_empty() {
            groups.push(group);
        }
    }

    if has_card_access(&active, "products.read", "products") {
        let params = ListProductsParams {
            q: Some(query.clone()),
            limit: Some(SEARCH_ENTITY_LIMIT),
            ..ListProductsParams::default()
        };
        let group = match client.list_products(&params).await {
            Ok(page) => SearchGroup {
                id: "products",
                label: "Products",
                hits: page
                    .items
                    .into_iter()
                    .map(|p| SearchHit {
                        title: p.name,
                        subtitle: join_parts(&[Some(&p.code)]),
                        path: format!("/products/{}", p.id),
                    })
                    .collect(),
                failed: false,
            },
            Err(_) => SearchGroup {
                id: "products",
                label: "Products",
                hits: Vec::new(),
                failed: true,
            },
        };
        if group.failed || !group.hits.is_empty() {
            groups.push(group);
        }
    }

    if has_card_access(&active, "quotations.read", "sales") {
        let params = ListQuotationsParams::new()
            .q(query.clone())
            .limit(SEARCH_ENTITY_LIMIT);
        let group = match client.list_quotations(&params).await {
            Ok(page) => SearchGroup {
                id: "quotations",
                label: "Quotations",
                hits: page
                    .items
                    .into_iter()
                    .map(|q| SearchHit {
                        title: q.number,
                        subtitle: join_parts(&[Some(&q.customer_name)]),
                        path: format!("/quotations/{}", q.id),
                    })
                    .collect(),
                failed: false,
            },
            Err(_) => SearchGroup {
                id: "quotations",
                label: "Quotations",
                hits: Vec::new(),
                failed: true,
            },
        };
        if group.failed || !group.hits.is_empty() {
            groups.push(group);
        }
    }

    if has_card_access(&active, "orders.read", "sales") {
        let params = ListOrdersParams {
            q: Some(query.clone()),
            limit: Some(SEARCH_ENTITY_LIMIT),
            ..ListOrdersParams::default()
        };
        let group = match client.list_orders(&params).await {
            Ok(page) => SearchGroup {
                id: "orders",
                label: "Orders",
                hits: page
                    .items
                    .into_iter()
                    .map(|o| SearchHit {
                        title: o.number,
                        subtitle: join_parts(&[Some(&o.customer_name)]),
                        path: format!("/orders/{}", o.id),
                    })
                    .collect(),
                failed: false,
            },
            Err(_) => SearchGroup {
                id: "orders",
                label: "Orders",
                hits: Vec::new(),
                failed: true,
            },
        };
        if group.failed || !group.hits.is_empty() {
            groups.push(group);
        }
    }

    if has_card_access(&active, "helpdesk.read", "helpdesk") {
        let params = ListTicketsParams::new()
            .q(query.clone())
            .limit(SEARCH_ENTITY_LIMIT);
        let group = match client.list_tickets(&params).await {
            Ok(page) => SearchGroup {
                id: "tickets",
                label: "Helpdesk",
                hits: page
                    .items
                    .into_iter()
                    .map(|t| SearchHit {
                        title: format!("{} · {}", t.number, t.subject),
                        subtitle: join_parts(&[t.customer_name.as_deref()]),
                        path: format!("/helpdesk/{}", t.id),
                    })
                    .collect(),
                failed: false,
            },
            Err(_) => SearchGroup {
                id: "tickets",
                label: "Helpdesk",
                hits: Vec::new(),
                failed: true,
            },
        };
        if group.failed || !group.hits.is_empty() {
            groups.push(group);
        }
    }

    if has_card_access(&active, "kb.read", "kb") {
        let params = ListKbEntriesParams {
            q: Some(query.clone()),
            limit: Some(SEARCH_ENTITY_LIMIT),
            ..ListKbEntriesParams::default()
        };
        let group = match client.list_kb_entries(&params).await {
            Ok(entries) => SearchGroup {
                id: "kb",
                label: "Knowledge Base",
                hits: entries
                    .into_iter()
                    .map(|e| SearchHit {
                        title: e.title,
                        subtitle: join_parts(&[Some(&e.number)]),
                        path: format!("/kb/{}", e.id),
                    })
                    .collect(),
                failed: false,
            },
            Err(_) => SearchGroup {
                id: "kb",
                label: "Knowledge Base",
                hits: Vec::new(),
                failed: true,
            },
        };
        if group.failed || !group.hits.is_empty() {
            groups.push(group);
        }
    }

    if has_card_access(&active, "purchasing.read", "purchasing") {
        let params = ListSuppliersParams {
            q: Some(query),
            ..ListSuppliersParams::default()
        };
        let group = match client.list_suppliers(&params).await {
            Ok(list) => SearchGroup {
                id: "suppliers",
                label: "Suppliers",
                hits: list
                    .into_iter()
                    .take(SEARCH_ENTITY_LIMIT as usize)
                    .map(|s| SearchHit {
                        title: s.name,
                        subtitle: join_parts(&[Some(&s.code)]),
                        path: format!("/suppliers/{}", s.id),
                    })
                    .collect(),
                failed: false,
            },
            Err(_) => SearchGroup {
                id: "suppliers",
                label: "Suppliers",
                hits: Vec::new(),
                failed: true,
            },
        };
        if group.failed || !group.hits.is_empty() {
            groups.push(group);
        }
    }

    groups
}

/// Command palette modal (`Ctrl+K`) searching visible destinations and permitted live records.
#[component]
pub fn GlobalSearchModal(open: RwSignal<bool>) -> impl IntoView {
    let ctx = expect_context::<AppContext>();
    let navigate = use_navigate();

    let query = RwSignal::new(String::new());
    let loading = RwSignal::new(false);
    let entity_groups = RwSignal::new(Vec::<SearchGroup>::new());
    let highlighted = RwSignal::new(0_usize);
    let guard = RequestGuard::new();
    let input_ref = NodeRef::<leptos::html::Input>::new();

    Effect::new(move |_| {
        if open.get() {
            highlighted.set(0);
            if let Some(el) = input_ref.get() {
                let _ = el.focus();
            }
        } else {
            let _ = guard.bump();
            query.set(String::new());
            entity_groups.set(Vec::new());
            loading.set(false);
        }
    });

    Effect::new(move |_| {
        if !open.get() {
            return;
        }
        let raw = query.get();
        let trimmed = raw.trim().to_string();
        highlighted.set(0);
        if trimmed.is_empty() {
            let _ = guard.bump();
            loading.set(false);
            entity_groups.set(Vec::new());
            return;
        }

        let Some(active) = ctx.session.get_untracked() else {
            return;
        };
        if !matches!(active.connection, ConnectionMode::Live(_)) {
            loading.set(false);
            entity_groups.set(Vec::new());
            return;
        }

        let gen = guard.bump();
        loading.set(true);
        spawn_api(
            ctx,
            move |client| async move {
                Ok::<_, tradocraft_api_client::ApiError>(
                    run_live_entity_search(client, active, trimmed).await,
                )
            },
            move |res| {
                if !guard.is_current(gen) {
                    return;
                }
                let _ = set_alive(loading, false);
                if let Ok(groups) = res {
                    let _ = set_alive(entity_groups, groups);
                }
            },
        );
    });

    let all_groups = Memo::new(move |_| {
        let q = query.get();
        let nav_hits = ctx.session.with(|s| match_nav_hits(&q, s.as_ref()));
        let mut out = Vec::new();
        if !nav_hits.is_empty() {
            out.push(SearchGroup {
                id: "navigation",
                label: "Modules & pages",
                hits: nav_hits,
                failed: false,
            });
        }
        out.extend(entity_groups.get());
        out
    });

    let open_hit = Callback::new(move |path: String| {
        open.set(false);
        ctx.active_tab.set(None);
        navigate(&path, NavigateOptions::default());
    });

    let title = Signal::derive(move || tr("shell.search", "Search"));

    view! {
        <Modal
            open=open
            title=title
            subtitle=Signal::derive(|| Some("Jump to modules or search records (Ctrl+K)".to_string()))
            on_close=Callback::new(move |()| open.set(false))
            target="global-search"
        >
            <div class="tc-global-search">
                <input
                    node_ref=input_ref
                    type="search"
                    class="tc-input"
                    placeholder="Type a module, customer, product, quote, order…"
                    data-target="global-search-input"
                    prop:value=move || query.get()
                    on:input=move |ev| query.set(event_target_value(&ev))
                    on:keydown=move |ev: leptos::ev::KeyboardEvent| match ev.key().as_str() {
                        "ArrowDown" => {
                            ev.prevent_default();
                            let count: usize =
                                all_groups.with_untracked(|gs| gs.iter().map(|g| g.hits.len()).sum());
                            if count > 0 {
                                highlighted.update(|idx| {
                                    if *idx + 1 < count {
                                        *idx += 1;
                                    }
                                });
                            }
                        }
                        "ArrowUp" => {
                            ev.prevent_default();
                            highlighted.update(|idx| *idx = idx.saturating_sub(1));
                        }
                        "Enter" => {
                            let target_idx = highlighted.get_untracked();
                            let picked = all_groups.with_untracked(|gs| {
                                gs.iter()
                                    .flat_map(|g| g.hits.iter())
                                    .nth(target_idx)
                                    .map(|h| h.path.clone())
                            });
                            if let Some(path) = picked {
                                ev.prevent_default();
                                open_hit.run(path);
                            }
                        }
                        _ => {}
                    }
                />

                {move || {
                    let q = query.get();
                    if q.trim().is_empty() {
                        return view! {
                            <p style="margin: 0; font-size: 12px; color: var(--on-surface-variant);" data-target="global-search-hint">
                                "Start typing to search modules, customers, products, quotations, orders, tickets, or knowledge base articles."
                            </p>
                        }
                        .into_any();
                    }
                    let groups = all_groups.get();
                    if groups.is_empty() {
                        let msg = if loading.get() {
                            "Searching…"
                        } else {
                            "No matching modules or records."
                        };
                        return view! {
                            <p style="margin: 0; font-size: 12px; color: var(--on-surface-variant);" data-target="global-search-empty">
                                {msg}
                            </p>
                        }
                        .into_any();
                    }

                    let mut flat_idx = 0_usize;
                    view! {
                        <div class="tc-global-search-results" data-target="global-search-results">
                            {loading.get().then(|| view! {
                                <div style="font-size: 12px; color: var(--on-surface-variant);">"Searching live records…"</div>
                            })}
                            {groups
                                .into_iter()
                                .map(|group| {
                                    let group_view = group
                                        .hits
                                        .into_iter()
                                        .map(|hit| {
                                            let idx = flat_idx;
                                            flat_idx += 1;
                                            let path = hit.path.clone();
                                            view! {
                                                <button
                                                    type="button"
                                                    class=move || {
                                                        if highlighted.get() == idx {
                                                            "tc-global-search-hit tc-global-search-hit-active"
                                                        } else {
                                                            "tc-global-search-hit"
                                                        }
                                                    }
                                                    data-target=format!("global-search-hit-{idx}")
                                                    on:mouseenter=move |_| highlighted.set(idx)
                                                    on:click=move |_| open_hit.run(path.clone())
                                                >
                                                    <span>{hit.title}</span>
                                                    {hit.subtitle.map(|sub| view! {
                                                        <span class="tc-badge">{sub}</span>
                                                    })}
                                                </button>
                                            }
                                        })
                                        .collect_view();
                                    view! {
                                        <div class="tc-global-search-group" data-target=format!("global-search-group-{}", group.id)>
                                            <div class="tc-nav-group-label">{group.label}</div>
                                            {if group.failed {
                                                view! {
                                                    <div style="font-size: 12px; color: var(--error);">"Search request failed."</div>
                                                }.into_any()
                                            } else {
                                                view! { <div class="tc-global-search-list">{group_view}</div> }.into_any()
                                            }}
                                        </div>
                                    }
                                })
                                .collect_view()}
                        </div>
                    }
                    .into_any()
                }}
            </div>
        </Modal>
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
                    .map(|(code, enabled)| MeModule {
                        code: (*code).to_string(),
                        enabled: *enabled,
                    })
                    .collect(),
                memberships: vec![],
            },
        }
    }

    #[test]
    fn fold_for_search_normalizes_case_and_diacritics() {
        assert_eq!(fold_for_search("Café Été"), "cafe ete");
        assert_eq!(fold_for_search("QUOTATIONS"), "quotations");
    }

    #[test]
    fn match_nav_hits_respects_permissions_and_modules() {
        let s = session_with(&["customers.read"], &[("products", false)]);
        let hits = match_nav_hits("cust", Some(&s));
        assert!(hits.iter().any(|h| h.path == "/customers"));
        assert!(match_nav_hits("prod", Some(&s)).is_empty());
        assert!(match_nav_hits("   ", Some(&s)).is_empty());
    }
}
