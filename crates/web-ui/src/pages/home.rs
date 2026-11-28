//! Role-aware workspace overview (`/home`, ADR 0095).

use leptos::prelude::*;
use leptos::task::spawn_local;
use leptos_router::components::A;
use tradocraft_api_client::helpdesk::{ListTicketsParams, TicketSummary};
use tradocraft_api_client::sales::{ListQuotationsParams, QuotationSummary};
use tradocraft_api_client::suppliers::{ListPurchaseOrdersParams, PurchaseOrderSummary};
use tradocraft_api_client::todo::{ListTodosParams, TodoItem};
use tradocraft_api_client::Client;

use crate::api::{resolve_base_url, ConnectionMode};
use crate::components::shell::app_href;
use crate::i18n::tr;
use crate::pages::record_detail::DetailKind;
use crate::pages::set_alive;
use crate::state::{ActiveSession, AppContext, WorkspaceTab};

#[derive(Debug, Clone, PartialEq, Eq)]
struct CardState<T> {
    loading: bool,
    items: Vec<T>,
    error: Option<String>,
}

impl<T> Default for CardState<T> {
    fn default() -> Self {
        Self {
            loading: false,
            items: Vec::new(),
            error: None,
        }
    }
}

/// Checks both the required permission and that the owning module is not explicitly disabled.
pub(crate) fn has_card_access(active: &ActiveSession, perm: &str, module: &str) -> bool {
    let module_ok = active
        .me
        .modules
        .iter()
        .find(|m| m.code == module)
        .is_none_or(|m| m.enabled);
    module_ok && active.me.has_permission(perm)
}

#[component]
pub fn HomePage() -> impl IntoView {
    let ctx = expect_context::<AppContext>();

    let reload_nonce = RwSignal::new(0_u64);
    let fetch_gen = StoredValue::new(0_u64);

    let todo_state = RwSignal::new(CardState::<TodoItem>::default());
    let helpdesk_state = RwSignal::new(CardState::<TicketSummary>::default());
    let quotations_state = RwSignal::new(CardState::<QuotationSummary>::default());
    let purchasing_state = RwSignal::new(CardState::<PurchaseOrderSummary>::default());

    let is_signed_in = Memo::new(move |_| ctx.session.with(|s| s.is_some()));
    let can_todo = Memo::new(move |_| {
        ctx.session.with(|s| {
            s.as_ref()
                .is_some_and(|a| has_card_access(a, "todo.use", "todo"))
        })
    });
    let can_helpdesk = Memo::new(move |_| {
        ctx.session.with(|s| {
            s.as_ref()
                .is_some_and(|a| has_card_access(a, "helpdesk.read", "helpdesk"))
        })
    });
    let can_quotations = Memo::new(move |_| {
        ctx.session.with(|s| {
            s.as_ref()
                .is_some_and(|a| has_card_access(a, "quotations.read", "sales"))
        })
    });
    let can_purchasing = Memo::new(move |_| {
        ctx.session.with(|s| {
            s.as_ref()
                .is_some_and(|a| has_card_access(a, "purchasing.read", "purchasing"))
        })
    });
    let can_products = Memo::new(move |_| {
        ctx.session.with(|s| {
            s.as_ref()
                .is_some_and(|a| has_card_access(a, "products.read", "products"))
        })
    });
    let can_customers = Memo::new(move |_| {
        ctx.session.with(|s| {
            s.as_ref()
                .is_some_and(|a| has_card_access(a, "customers.read", "customers"))
        })
    });

    Effect::new(move |_| {
        let _ = reload_nonce.get();
        let req_gen = fetch_gen
            .try_update_value(|g| {
                *g = g.wrapping_add(1);
                *g
            })
            .unwrap_or(0);

        let Some(active) = ctx.session.get() else {
            todo_state.set(CardState::default());
            helpdesk_state.set(CardState::default());
            quotations_state.set(CardState::default());
            purchasing_state.set(CardState::default());
            return;
        };

        let show_todo = has_card_access(&active, "todo.use", "todo");
        let show_helpdesk = has_card_access(&active, "helpdesk.read", "helpdesk");
        let show_quotations = has_card_access(&active, "quotations.read", "sales");
        let show_purchasing = has_card_access(&active, "purchasing.read", "purchasing");

        let ConnectionMode::Live(raw_session) = active.connection else {
            todo_state.set(CardState::default());
            helpdesk_state.set(CardState::default());
            quotations_state.set(CardState::default());
            purchasing_state.set(CardState::default());
            return;
        };

        let mut resolved = raw_session;
        resolved.base_url = resolve_base_url(&resolved.base_url);
        let client = Client::from_session(resolved);

        if show_todo {
            todo_state.set(CardState {
                loading: true,
                items: Vec::new(),
                error: None,
            });
            let c = client.clone();
            spawn_local(async move {
                let res = c
                    .list_todos(&ListTodosParams {
                        scope: None,
                        done: Some(false),
                        ..ListTodosParams::default()
                    })
                    .await;
                if fetch_gen.try_get_value() != Some(req_gen) {
                    return;
                }
                let next = match res {
                    Ok(items) => CardState {
                        loading: false,
                        items: items.into_iter().take(5).collect(),
                        error: None,
                    },
                    Err(err) => CardState {
                        loading: false,
                        items: Vec::new(),
                        error: Some(err.user_message()),
                    },
                };
                let _ = set_alive(todo_state, next);
            });
        } else {
            todo_state.set(CardState::default());
        }

        if show_helpdesk {
            helpdesk_state.set(CardState {
                loading: true,
                items: Vec::new(),
                error: None,
            });
            let c = client.clone();
            spawn_local(async move {
                let res = c
                    .list_tickets(&ListTicketsParams::new().status("open").limit(5))
                    .await;
                if fetch_gen.try_get_value() != Some(req_gen) {
                    return;
                }
                let next = match res {
                    Ok(page) => CardState {
                        loading: false,
                        items: page.items.into_iter().take(5).collect(),
                        error: None,
                    },
                    Err(err) => CardState {
                        loading: false,
                        items: Vec::new(),
                        error: Some(err.user_message()),
                    },
                };
                let _ = set_alive(helpdesk_state, next);
            });
        } else {
            helpdesk_state.set(CardState::default());
        }

        if show_quotations {
            quotations_state.set(CardState {
                loading: true,
                items: Vec::new(),
                error: None,
            });
            let c = client.clone();
            spawn_local(async move {
                let res = c
                    .list_quotations(&ListQuotationsParams::new().limit(5))
                    .await;
                if fetch_gen.try_get_value() != Some(req_gen) {
                    return;
                }
                let next = match res {
                    Ok(page) => CardState {
                        loading: false,
                        items: page.items.into_iter().take(5).collect(),
                        error: None,
                    },
                    Err(err) => CardState {
                        loading: false,
                        items: Vec::new(),
                        error: Some(err.user_message()),
                    },
                };
                let _ = set_alive(quotations_state, next);
            });
        } else {
            quotations_state.set(CardState::default());
        }

        if show_purchasing {
            purchasing_state.set(CardState {
                loading: true,
                items: Vec::new(),
                error: None,
            });
            let c = client;
            spawn_local(async move {
                let res = c
                    .list_purchase_orders(&ListPurchaseOrdersParams::new())
                    .await;
                if fetch_gen.try_get_value() != Some(req_gen) {
                    return;
                }
                let next = match res {
                    Ok(items) => CardState {
                        loading: false,
                        items: items.into_iter().take(5).collect(),
                        error: None,
                    },
                    Err(err) => CardState {
                        loading: false,
                        items: Vec::new(),
                        error: Some(err.user_message()),
                    },
                };
                let _ = set_alive(purchasing_state, next);
            });
        } else {
            purchasing_state.set(CardState::default());
        }
    });

    let has_open_tabs = Memo::new(move |_| ctx.tabs.with(|t| !t.is_empty()));
    let has_any_card = Memo::new(move |_| {
        has_open_tabs.get()
            || can_todo.get()
            || can_helpdesk.get()
            || can_quotations.get()
            || can_purchasing.get()
    });

    view! {
        <div data-target="home-page">
            <div class="tc-page-header">
                <div>
                    <h1 class="tc-page-title">{move || tr("home.title", "Overview")}</h1>
                    <p class="tc-page-subtitle">
                        {move || tr("home.subtitle", "Open workspace items, pending tasks, and recent records.")}
                    </p>
                </div>
                <Show when=move || is_signed_in.get()>
                    <div class="tc-header-actions">
                        <button
                            type="button"
                            class="tc-btn tc-btn-sm"
                            data-target="home-refresh"
                            on:click=move |_| reload_nonce.update(|n| *n += 1)
                        >
                            {move || tr("home.refresh", "Refresh")}
                        </button>
                    </div>
                </Show>
            </div>

            <Show
                when=move || is_signed_in.get()
                fallback=|| view! {
                    <div class="tc-card" style="max-width: 520px;">
                        <p style="margin: 0 0 var(--space-md); color: var(--on-surface-variant);">
                            "Sign in to load your workspace overview."
                        </p>
                        <A href=app_href("/login") attr:class="tc-btn tc-btn-primary" attr:data-target="home-go-login">
                            "Go to sign in"
                        </A>
                    </div>
                }
            >
                <Show
                    when=move || has_any_card.get()
                    fallback=move || view! {
                        <div class="tc-card" style="max-width: 560px;" data-target="home-empty">
                            <p style="margin: 0 0 var(--space-md); color: var(--on-surface-variant);">
                                {move || tr("home.empty", "No overview cards are available for your current permissions. Use the module navigation to open a section.")}
                            </p>
                            <div class="tc-header-actions">
                                <Show when=move || can_products.get()>
                                    <A href=app_href("/products") attr:class="tc-btn tc-btn-primary tc-btn-sm">
                                        "Products"
                                    </A>
                                </Show>
                                <Show when=move || can_customers.get()>
                                    <A href=app_href("/customers") attr:class="tc-btn tc-btn-sm">
                                        "Customers"
                                    </A>
                                </Show>
                            </div>
                        </div>
                    }
                >
                    <div class="tc-home-grid" data-target="home-cards">
                        <Show when=move || has_open_tabs.get()>
                            <section class="tc-card tc-home-card" data-target="home-card-tabs">
                                <div class="tc-home-card-head">
                                    <h2 class="tc-home-card-title">{move || tr("home.open_tabs", "Open tabs")}</h2>
                                </div>
                                <ul class="tc-home-list">
                                    {move || ctx.tabs.get().into_iter().map(|tab| {
                                        let id = tab.id.clone();
                                        view! {
                                            <li>
                                                <button
                                                    type="button"
                                                    class="tc-home-list-item tc-home-list-btn"
                                                    on:click=move |_| ctx.active_tab.set(Some(id.clone()))
                                                >
                                                    <span>{tab.title}</span>
                                                    <span class="tc-mono" style="color: var(--on-surface-variant);">{tab.route}</span>
                                                </button>
                                            </li>
                                        }
                                    }).collect_view()}
                                </ul>
                            </section>
                        </Show>

                        <Show when=move || can_todo.get()>
                            <section class="tc-card tc-home-card" data-target="home-card-todo">
                                <div class="tc-home-card-head">
                                    <h2 class="tc-home-card-title">{move || tr("home.todo", "To-do")}</h2>
                                    <A href=app_href("/todo") attr:class="tc-btn tc-btn-ghost tc-btn-sm" attr:data-target="home-see-all-todo">
                                        {move || tr("home.see_all", "See all")}
                                    </A>
                                </div>
                                {move || {
                                    let st = todo_state.get();
                                    if let Some(err) = st.error {
                                        view! { <div class="tc-alert-error" data-target="home-error-todo">{err}</div> }.into_any()
                                    } else if st.loading {
                                        view! { <div style="color: var(--on-surface-variant); font-size: 13px;">"Loading..."</div> }.into_any()
                                    } else if st.items.is_empty() {
                                        view! { <div style="color: var(--on-surface-variant); font-size: 13px;">"No open to-do items."</div> }.into_any()
                                    } else {
                                        view! {
                                            <ul class="tc-home-list">
                                                {st.items.into_iter().map(|item| {
                                                    let due = item.due_date.map(|d| d.to_string());
                                                    view! {
                                                        <li class="tc-home-list-item">
                                                            <span>{item.title}</span>
                                                            {due.map(|d| view! { <span class="tc-badge">{d}</span> })}
                                                        </li>
                                                    }
                                                }).collect_view()}
                                            </ul>
                                        }.into_any()
                                    }
                                }}
                            </section>
                        </Show>

                        <Show when=move || can_helpdesk.get()>
                            <section class="tc-card tc-home-card" data-target="home-card-helpdesk">
                                <div class="tc-home-card-head">
                                    <h2 class="tc-home-card-title">{move || tr("home.helpdesk", "Helpdesk")}</h2>
                                    <A href=app_href("/helpdesk") attr:class="tc-btn tc-btn-ghost tc-btn-sm" attr:data-target="home-see-all-helpdesk">
                                        {move || tr("home.see_all", "See all")}
                                    </A>
                                </div>
                                {move || {
                                    let st = helpdesk_state.get();
                                    if let Some(err) = st.error {
                                        view! { <div class="tc-alert-error" data-target="home-error-helpdesk">{err}</div> }.into_any()
                                    } else if st.loading {
                                        view! { <div style="color: var(--on-surface-variant); font-size: 13px;">"Loading..."</div> }.into_any()
                                    } else if st.items.is_empty() {
                                        view! { <div style="color: var(--on-surface-variant); font-size: 13px;">"No open tickets."</div> }.into_any()
                                    } else {
                                        view! {
                                            <ul class="tc-home-list">
                                                {st.items.into_iter().map(|t| {
                                                    let label = format!("{} · {}", t.number, t.subject);
                                                    let tid = t.id;
                                                    let title = t.number.clone();
                                                    let sub = t.subject.clone();
                                                    view! {
                                                        <li>
                                                            <button
                                                                type="button"
                                                                class="tc-home-list-item tc-home-list-btn"
                                                                data-target=format!("home-ticket-{tid}")
                                                                on:click=move |_| {
                                                                    ctx.open_tab(WorkspaceTab {
                                                                        id: DetailKind::Ticket.tab_id(tid),
                                                                        title: title.clone(),
                                                                        route: DetailKind::Ticket.route(tid),
                                                                        subtitle: sub.clone(),
                                                                    });
                                                                }
                                                            >
                                                                <span>{label}</span>
                                                                <span class="tc-badge">{t.priority}</span>
                                                            </button>
                                                        </li>
                                                    }
                                                }).collect_view()}
                                            </ul>
                                        }.into_any()
                                    }
                                }}
                            </section>
                        </Show>

                        <Show when=move || can_quotations.get()>
                            <section class="tc-card tc-home-card" data-target="home-card-quotations">
                                <div class="tc-home-card-head">
                                    <h2 class="tc-home-card-title">{move || tr("home.quotations", "Quotations")}</h2>
                                    <A href=app_href("/quotations") attr:class="tc-btn tc-btn-ghost tc-btn-sm" attr:data-target="home-see-all-quotations">
                                        {move || tr("home.see_all", "See all")}
                                    </A>
                                </div>
                                {move || {
                                    let st = quotations_state.get();
                                    if let Some(err) = st.error {
                                        view! { <div class="tc-alert-error" data-target="home-error-quotations">{err}</div> }.into_any()
                                    } else if st.loading {
                                        view! { <div style="color: var(--on-surface-variant); font-size: 13px;">"Loading..."</div> }.into_any()
                                    } else if st.items.is_empty() {
                                        view! { <div style="color: var(--on-surface-variant); font-size: 13px;">"No quotations yet."</div> }.into_any()
                                    } else {
                                        view! {
                                            <ul class="tc-home-list">
                                                {st.items.into_iter().map(|q| {
                                                    let label = format!("{} · {}", q.number, q.customer_name);
                                                    let amount = format!("{} {}", q.currency, q.total);
                                                    let qid = q.id;
                                                    let title = q.number.clone();
                                                    let sub = q.customer_name.clone();
                                                    view! {
                                                        <li>
                                                            <button
                                                                type="button"
                                                                class="tc-home-list-item tc-home-list-btn"
                                                                data-target=format!("home-quotation-{qid}")
                                                                on:click=move |_| {
                                                                    ctx.open_tab(WorkspaceTab {
                                                                        id: DetailKind::Quotation.tab_id(qid),
                                                                        title: title.clone(),
                                                                        route: DetailKind::Quotation.route(qid),
                                                                        subtitle: sub.clone(),
                                                                    });
                                                                }
                                                            >
                                                                <span>{label}</span>
                                                                <span class="tc-badge tc-mono">{amount}</span>
                                                            </button>
                                                        </li>
                                                    }
                                                }).collect_view()}
                                            </ul>
                                        }.into_any()
                                    }
                                }}
                            </section>
                        </Show>

                        <Show when=move || can_purchasing.get()>
                            <section class="tc-card tc-home-card" data-target="home-card-purchasing">
                                <div class="tc-home-card-head">
                                    <h2 class="tc-home-card-title">{move || tr("home.purchasing", "Purchase orders")}</h2>
                                    <A href=app_href("/purchasing") attr:class="tc-btn tc-btn-ghost tc-btn-sm" attr:data-target="home-see-all-purchasing">
                                        {move || tr("home.see_all", "See all")}
                                    </A>
                                </div>
                                {move || {
                                    let st = purchasing_state.get();
                                    if let Some(err) = st.error {
                                        view! { <div class="tc-alert-error" data-target="home-error-purchasing">{err}</div> }.into_any()
                                    } else if st.loading {
                                        view! { <div style="color: var(--on-surface-variant); font-size: 13px;">"Loading..."</div> }.into_any()
                                    } else if st.items.is_empty() {
                                        view! { <div style="color: var(--on-surface-variant); font-size: 13px;">"No purchase orders yet."</div> }.into_any()
                                    } else {
                                        view! {
                                            <ul class="tc-home-list">
                                                {st.items.into_iter().map(|po| {
                                                    let label = format!("{} · {}", po.number, po.supplier_name);
                                                    let amount = format!("{} {}", po.currency, po.total);
                                                    view! {
                                                        <li class="tc-home-list-item">
                                                            <span>{label}</span>
                                                            <span class="tc-badge tc-mono">{amount}</span>
                                                        </li>
                                                    }
                                                }).collect_view()}
                                            </ul>
                                        }.into_any()
                                    }
                                }}
                            </section>
                        </Show>
                    </div>
                </Show>
            </Show>
        </div>
    }
}
