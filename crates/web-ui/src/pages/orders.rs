use leptos::prelude::*;
use leptos::task::spawn_local;
use leptos_router::components::A;
use tradocraft_api_client::sales::{
    ConfirmOrderRequest, ListOrdersParams, Order, OrderPage, OrderSummary,
};
use tradocraft_api_client::ApiError;
use uuid::Uuid;

use crate::api::ConnectionMode;
use crate::components::async_ops::live_client;
use crate::state::AppContext;

#[derive(Debug, Clone, PartialEq)]
struct OrderTab {
    instance_id: u64,
    op_gen: u64,
    tab_id: String,
    order_id: Uuid,
    title: String,
    summary: OrderSummary,
    detail: Option<Order>,
    loading_detail: bool,
    busy: bool,
    error: Option<String>,
    notice: Option<String>,
    confirm_note: String,
}

impl OrderTab {
    fn from_summary(instance_id: u64, summary: &OrderSummary, loading_detail: bool) -> Self {
        Self {
            instance_id,
            op_gen: 0,
            tab_id: format!("order:{}", summary.id),
            order_id: summary.id,
            title: format!("{} · {}", summary.number, summary.customer_name),
            summary: summary.clone(),
            detail: None,
            loading_detail,
            busy: false,
            error: None,
            notice: None,
            confirm_note: String::new(),
        }
    }

    fn apply_order(&mut self, order: &Order, notice: Option<String>) {
        self.summary = order.order.clone();
        self.title = format!(
            "{} (r{}) · {}",
            order.order.number, order.revision, order.order.customer_name
        );
        self.detail = Some(order.clone());
        self.loading_detail = false;
        self.busy = false;
        self.error = None;
        self.notice = notice;
    }

    fn revision_status(&self) -> &str {
        self.detail
            .as_ref()
            .map(|d| d.revision_status.as_str())
            .unwrap_or_else(|| self.summary.status.as_str())
    }
}

fn read_order_tab<R>(
    tabs: &RwSignal<Vec<OrderTab>>,
    tab_id: &str,
    f: impl FnOnce(&OrderTab) -> R,
) -> Option<R> {
    tabs.with(|list| list.iter().find(|t| t.tab_id == tab_id).map(f))
}

fn update_order_tab(tabs: &RwSignal<Vec<OrderTab>>, tab_id: &str, f: impl FnOnce(&mut OrderTab)) {
    tabs.update(|list| {
        if let Some(tab) = list.iter_mut().find(|t| t.tab_id == tab_id) {
            f(tab);
        }
    });
}

fn update_order_tab_for_op(
    tabs: &RwSignal<Vec<OrderTab>>,
    instance_id: u64,
    op_gen: u64,
    f: impl FnOnce(&mut OrderTab),
) {
    tabs.update(|list| {
        if let Some(tab) = list
            .iter_mut()
            .find(|t| t.instance_id == instance_id && t.op_gen == op_gen)
        {
            f(tab);
        }
    });
}

fn close_order_tab(
    tabs: &RwSignal<Vec<OrderTab>>,
    active_tab_id: &RwSignal<Option<String>>,
    tab_id: &str,
) {
    let mut next_active = None;
    tabs.update(|list| {
        if let Some(idx) = list.iter().position(|t| t.tab_id == tab_id) {
            list.remove(idx);
            if !list.is_empty() {
                let pick = idx.min(list.len() - 1);
                next_active = Some(list[pick].tab_id.clone());
            }
        }
    });
    if active_tab_id.get_untracked().as_deref() == Some(tab_id) {
        active_tab_id.set(next_active);
    }
}

fn order_status_badge_class(status: &str) -> &'static str {
    match status {
        "draft" => "tc-badge",
        "sent" => "tc-badge tc-badge-primary",
        "confirmed" | "ready_for_shipping" | "shipped" => "tc-badge tc-badge-success",
        "in_planning" | "planned" | "in_production" | "partially_shipped" => {
            "tc-badge tc-badge-warning"
        }
        "cancelled" => "tc-badge tc-badge-error",
        _ => "tc-badge",
    }
}

#[component]
pub fn OrdersPage() -> impl IntoView {
    let ctx = expect_context::<AppContext>();

    let search = RwSignal::new(String::new());
    let status_filter = RwSignal::new(String::new());

    let loading = RwSignal::new(false);
    let error = RwSignal::new(Option::<String>::None);
    let items = RwSignal::new(Vec::<OrderSummary>::new());
    let total = RwSignal::new(0_i64);
    let reload_nonce = RwSignal::new(0_u64);

    let open_tabs = RwSignal::new(Vec::<OrderTab>::new());
    let active_tab_id = RwSignal::new(Option::<String>::None);
    let fetch_gen = StoredValue::new(0_u64);
    let next_tab_instance_id = StoredValue::new(0_u64);

    let fetch_orders = move |connection: ConnectionMode, params: ListOrdersParams| {
        let req_gen = fetch_gen.get_value().wrapping_add(1);
        fetch_gen.set_value(req_gen);
        loading.set(true);
        error.set(None);
        spawn_local(async move {
            let result: Result<OrderPage, ApiError> = match live_client(&connection) {
                Ok(client) => client.list_orders(&params).await,
                Err(err) => Err(err),
            };
            if fetch_gen.try_get_value() != Some(req_gen) {
                return;
            }
            match result {
                Ok(page) => {
                    items.set(page.items);
                    total.set(page.total);
                    loading.set(false);
                }
                Err(err) => {
                    loading.set(false);
                    error.set(Some(err.user_message()));
                }
            }
        });
    };

    Effect::new(move |_| {
        let _ = reload_nonce.get();
        let active_session = ctx.session.get();
        let q = search.get();
        let status = status_filter.get();

        let Some(session) = active_session else {
            fetch_gen.set_value(fetch_gen.get_value().wrapping_add(1));
            loading.set(false);
            items.set(Vec::new());
            total.set(0);
            error.set(None);
            open_tabs.set(Vec::new());
            active_tab_id.set(None);
            return;
        };

        let params = ListOrdersParams {
            q: (!q.trim().is_empty()).then_some(q),
            status: (!status.trim().is_empty()).then_some(status),
            limit: Some(50),
            offset: Some(0),
            ..ListOrdersParams::default()
        };
        fetch_orders(session.connection, params);
    });

    let is_signed_in = Memo::new(move |_| ctx.session.with(|s| s.is_some()));

    let open_order_row = move |summary: OrderSummary| {
        let tab_id = format!("order:{}", summary.id);
        let mut target: Option<(u64, u64)> = None;
        open_tabs.update(|list| {
            if let Some(tab) = list.iter_mut().find(|t| t.tab_id == tab_id) {
                if !tab.busy {
                    tab.loading_detail = true;
                    tab.op_gen = tab.op_gen.wrapping_add(1);
                    target = Some((tab.instance_id, tab.op_gen));
                }
            } else {
                let instance_id = next_tab_instance_id.get_value().wrapping_add(1);
                next_tab_instance_id.set_value(instance_id);
                let mut tab = OrderTab::from_summary(instance_id, &summary, true);
                tab.op_gen = 1;
                list.push(tab);
                target = Some((instance_id, 1));
            }
        });
        active_tab_id.set(Some(tab_id.clone()));

        let Some((instance_id, op_gen)) = target else {
            return;
        };
        if let Some(session) = ctx.session.get_untracked() {
            let connection = session.connection;
            let order_id = summary.id;
            spawn_local(async move {
                let res = match live_client(&connection) {
                    Ok(client) => client.get_order(order_id).await,
                    Err(err) => Err(err),
                };
                match res {
                    Ok(fresh) => {
                        update_order_tab_for_op(&open_tabs, instance_id, op_gen, |tab| {
                            tab.apply_order(&fresh, None);
                        });
                    }
                    Err(err) => {
                        update_order_tab_for_op(&open_tabs, instance_id, op_gen, |tab| {
                            tab.loading_detail = false;
                            if tab.error.is_none() {
                                tab.error = Some(err.user_message());
                            }
                        });
                    }
                }
            });
        } else {
            update_order_tab_for_op(&open_tabs, instance_id, op_gen, |tab| {
                tab.loading_detail = false;
            });
        }
    };

    view! {
        <div data-target="orders-page">
            <div class="tc-page-header">
                <div>
                    <h1 class="tc-page-title">"Orders"</h1>
                    <p class="tc-page-subtitle" data-target="orders-total">
                        {move || format!("Sales orders ({} total)", total.get())}
                    </p>
                </div>
                <div class="tc-header-actions">
                    <button
                        type="button"
                        data-target="orders-refresh"
                        class="tc-btn"
                        disabled=move || loading.get() || !is_signed_in.get()
                        on:click=move |_| reload_nonce.update(|n| *n += 1)
                    >
                        {move || if loading.get() { "Loading..." } else { "Refresh" }}
                    </button>
                </div>
            </div>

            <Show
                when=move || is_signed_in.get()
                fallback=|| view! {
                    <div class="tc-card">
                        <p style="margin: 0 0 var(--space-md);">
                            "Sign in to load sales orders from GET /api/v1/orders."
                        </p>
                        <A href=crate::components::shell::app_href("/login") attr:class="tc-btn tc-btn-primary" attr:data-target="orders-go-login">
                            "Go to sign in"
                        </A>
                    </div>
                }
            >
                <div class=move || {
                    if active_tab_id.get().is_some() {
                        "tc-workspace-split"
                    } else {
                        ""
                    }
                }>
                    <div>
                        <div class="tc-toolbar">
                            <input
                                data-target="orders-search"
                                class="tc-input"
                                style="min-width: 240px;"
                                type="search"
                                placeholder="Search order, quote, customer or PO ref..."
                                prop:value=move || search.get()
                                on:input=move |ev| search.set(event_target_value(&ev))
                            />
                            <select
                                data-target="orders-status-filter"
                                class="tc-select"
                                prop:value=move || status_filter.get()
                                on:change=move |ev| status_filter.set(event_target_value(&ev))
                            >
                                <option value="">"All statuses"</option>
                                <option value="draft">"Draft"</option>
                                <option value="sent">"Sent"</option>
                                <option value="confirmed">"Confirmed"</option>
                                <option value="in_planning">"In planning"</option>
                                <option value="planned">"Planned"</option>
                                <option value="in_production">"In production"</option>
                                <option value="ready_for_shipping">"Ready for shipping"</option>
                                <option value="partially_shipped">"Partially shipped"</option>
                                <option value="shipped">"Shipped"</option>
                                <option value="cancelled">"Cancelled"</option>
                            </select>
                        </div>

                        {move || error.get().map(|msg| view! {
                            <div class="tc-alert-error" style="margin-bottom: var(--space-md);" role="alert" data-target="orders-error">
                                {msg}
                            </div>
                        })}

                        <div class="tc-table-wrap">
                            <table class="tc-table" data-target="orders-table">
                                <thead>
                                    <tr>
                                        <th>"Number"</th>
                                        <th>"Quotation"</th>
                                        <th>"Customer"</th>
                                        <th>"Reference"</th>
                                        <th>"Order date"</th>
                                        <th>"Priority"</th>
                                        <th class="tc-num">"Total"</th>
                                        <th>"Status"</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    <Show
                                        when=move || !items.with(Vec::is_empty)
                                        fallback=move || view! {
                                            <tr>
                                                <td colspan="8" style="text-align: center; color: var(--on-surface-variant); padding: var(--space-xl);">
                                                    {move || if loading.get() {
                                                        "Loading orders..."
                                                    } else {
                                                        "No orders match the current filter."
                                                    }}
                                                </td>
                                            </tr>
                                        }
                                    >
                                        <For
                                            each=move || items.get()
                                            key=|o| (o.id, o.current_revision, o.status.clone(), o.total)
                                            children=move |summary| {
                                                let open_summary = summary.clone();
                                                let row_tab_id = format!("order:{}", summary.id);
                                                let row_target = format!("order-row-{}", summary.number);
                                                let badge_class = order_status_badge_class(&summary.status);
                                                let reference = if summary.customer_reference.trim().is_empty() {
                                                    "—".to_string()
                                                } else {
                                                    summary.customer_reference.clone()
                                                };
                                                view! {
                                                    <tr
                                                        class=move || {
                                                            if active_tab_id.get().as_deref() == Some(row_tab_id.as_str()) {
                                                                "tc-row-clickable tc-row-selected"
                                                            } else {
                                                                "tc-row-clickable"
                                                            }
                                                        }
                                                        data-target=row_target
                                                        title="Open order detail & lines"
                                                        on:click=move |_| open_order_row(open_summary.clone())
                                                    >
                                                        <td class="tc-mono">{format!("{} r{}", summary.number, summary.current_revision)}</td>
                                                        <td class="tc-mono">{format!("{} r{}", summary.quotation_number, summary.quotation_revision)}</td>
                                                        <td>{summary.customer_name}</td>
                                                        <td class="tc-mono">{reference}</td>
                                                        <td class="tc-mono">{summary.order_date.to_string()}</td>
                                                        <td>{summary.priority}</td>
                                                        <td class="tc-num tc-mono">{format!("{} {}", summary.total, summary.currency)}</td>
                                                        <td><span class=badge_class>{summary.status}</span></td>
                                                    </tr>
                                                }
                                            }
                                        />
                                    </Show>
                                </tbody>
                            </table>
                        </div>
                    </div>

                    {move || active_tab_id.get().map(|current_tab_id| {
                        let tab_id_sv = StoredValue::new(current_tab_id.clone());
                        let tab_id_header = current_tab_id.clone();
                        let tab_id_subtitle = current_tab_id.clone();
                        let tab_id_badge = current_tab_id.clone();
                        let tab_id_error = current_tab_id.clone();
                        let tab_id_notice = current_tab_id.clone();
                        let tab_id_body = current_tab_id.clone();
                        let tab_id_confirm_note = current_tab_id.clone();
                        let tab_id_send = current_tab_id.clone();
                        let tab_id_confirm = current_tab_id.clone();
                        let tab_id_close = current_tab_id.clone();
                        let tab_id_actions = current_tab_id.clone();

                        let on_send = move |_| {
                            let Some(session) = ctx.session.get_untracked() else {
                                return;
                            };
                            let mut target: Option<(u64, u64, Uuid)> = None;
                            open_tabs.update(|list| {
                                if let Some(tab) = list.iter_mut().find(|t| t.tab_id == tab_id_send) {
                                    if tab.busy {
                                        return;
                                    }
                                    tab.busy = true;
                                    tab.loading_detail = false;
                                    tab.op_gen = tab.op_gen.wrapping_add(1);
                                    tab.error = None;
                                    tab.notice = None;
                                    target = Some((tab.instance_id, tab.op_gen, tab.order_id));
                                }
                            });
                            let Some((instance_id, op_gen, order_id)) = target else {
                                return;
                            };
                            let connection = session.connection;
                            spawn_local(async move {
                                let res = match live_client(&connection) {
                                    Ok(client) => client.send_order(order_id).await,
                                    Err(err) => Err(err),
                                };
                                match res {
                                    Ok(updated) => {
                                        update_order_tab_for_op(&open_tabs, instance_id, op_gen, |tab| {
                                            tab.apply_order(&updated, Some("Order confirmation sent.".to_string()));
                                        });
                                        reload_nonce.update(|n| *n += 1);
                                    }
                                    Err(err) => {
                                        update_order_tab_for_op(&open_tabs, instance_id, op_gen, |tab| {
                                            tab.busy = false;
                                            tab.error = Some(err.user_message());
                                        });
                                    }
                                }
                            });
                        };

                        let on_confirm = move |_| {
                            let Some(session) = ctx.session.get_untracked() else {
                                return;
                            };
                            let mut target: Option<(u64, u64, Uuid, ConfirmOrderRequest)> = None;
                            open_tabs.update(|list| {
                                if let Some(tab) = list.iter_mut().find(|t| t.tab_id == tab_id_confirm) {
                                    if tab.busy {
                                        return;
                                    }
                                    let req = ConfirmOrderRequest {
                                        note: tab.confirm_note.trim().to_string(),
                                        revision: tab.detail.as_ref().map(|d| d.revision),
                                    };
                                    tab.busy = true;
                                    tab.loading_detail = false;
                                    tab.op_gen = tab.op_gen.wrapping_add(1);
                                    tab.error = None;
                                    tab.notice = None;
                                    target = Some((tab.instance_id, tab.op_gen, tab.order_id, req));
                                }
                            });
                            let Some((instance_id, op_gen, order_id, req)) = target else {
                                return;
                            };
                            let connection = session.connection;
                            spawn_local(async move {
                                let res = match live_client(&connection) {
                                    Ok(client) => client.confirm_order(order_id, &req).await,
                                    Err(err) => Err(err),
                                };
                                match res {
                                    Ok(updated) => {
                                        update_order_tab_for_op(&open_tabs, instance_id, op_gen, |tab| {
                                            tab.apply_order(&updated, Some("Order confirmed.".to_string()));
                                        });
                                        reload_nonce.update(|n| *n += 1);
                                    }
                                    Err(err) => {
                                        update_order_tab_for_op(&open_tabs, instance_id, op_gen, |tab| {
                                            tab.busy = false;
                                            tab.error = Some(err.user_message());
                                        });
                                    }
                                }
                            });
                        };

                        view! {
                            <aside class="tc-card tc-detail-drawer" data-target="order-detail-drawer">
                                <div class="tc-inline-tabs" data-target="order-detail-tabs">
                                    <For
                                        each=move || open_tabs.get()
                                        key=|t| (t.tab_id.clone(), t.title.clone())
                                        children=move |tab| {
                                            let select_id = tab.tab_id.clone();
                                            let active_check_id = tab.tab_id.clone();
                                            let close_id = tab.tab_id.clone();
                                            view! {
                                                <div class=move || {
                                                    if active_tab_id.get().as_deref() == Some(active_check_id.as_str()) {
                                                        "tc-inline-tab tc-inline-tab-active"
                                                    } else {
                                                        "tc-inline-tab"
                                                    }
                                                }>
                                                    <button
                                                        type="button"
                                                        class="tc-inline-tab-btn"
                                                        on:click=move |_| active_tab_id.set(Some(select_id.clone()))
                                                    >
                                                        {tab.title}
                                                    </button>
                                                    <button
                                                        type="button"
                                                        class="tc-tab-close"
                                                        aria-label="Close tab"
                                                        on:click=move |_| close_order_tab(&open_tabs, &active_tab_id, &close_id)
                                                    >
                                                        "×"
                                                    </button>
                                                </div>
                                            }
                                        }
                                    />
                                </div>

                                <div class="tc-page-header" style="margin-bottom: 0;">
                                    <div>
                                        <h2 class="tc-page-title" style="font-size: 16px;">
                                            {move || {
                                                read_order_tab(&open_tabs, &tab_id_header, |t| t.title.clone())
                                                    .unwrap_or_else(|| "Order".to_string())
                                            }}
                                        </h2>
                                        <p class="tc-page-subtitle tc-mono">
                                            {move || {
                                                read_order_tab(&open_tabs, &tab_id_subtitle, |t| {
                                                    if t.loading_detail {
                                                        format!("{} (loading...)", t.order_id)
                                                    } else if let Some(d) = &t.detail {
                                                        format!("{} · v{}", t.order_id, d.version)
                                                    } else {
                                                        t.order_id.to_string()
                                                    }
                                                })
                                                .unwrap_or_default()
                                            }}
                                        </p>
                                    </div>
                                    {move || read_order_tab(&open_tabs, &tab_id_badge, |t| t.summary.status.clone()).map(|st| {
                                        let cls = order_status_badge_class(&st);
                                        view! { <span class=cls>{st}</span> }
                                    })}
                                </div>

                                {move || {
                                    read_order_tab(&open_tabs, &tab_id_error, |t| t.error.clone())
                                        .flatten()
                                        .map(|msg| view! {
                                            <div class="tc-alert-error" role="alert" data-target="order-detail-error">
                                                {msg}
                                            </div>
                                        })
                                }}

                                {move || {
                                    read_order_tab(&open_tabs, &tab_id_notice, |t| t.notice.clone())
                                        .flatten()
                                        .map(|msg| view! {
                                            <div class="tc-alert-success" role="status" data-target="order-detail-notice">
                                                {msg}
                                            </div>
                                        })
                                }}

                                {move || read_order_tab(&open_tabs, &tab_id_body, Clone::clone).map(|tab| {
                                    let s = &tab.summary;
                                    let reference = if s.customer_reference.trim().is_empty() {
                                        "—".to_string()
                                    } else {
                                        s.customer_reference.clone()
                                    };
                                    let promised = s.promised_date.map(|d| d.to_string()).unwrap_or_else(|| "—".to_string());
                                    view! {
                                        <div style="display: flex; flex-direction: column; gap: var(--space-md);">
                                            <div class="tc-form-grid" style="font-size: 12px;">
                                                <div>
                                                    <div class="tc-label">"Customer"</div>
                                                    <div>{s.customer_name.clone()}</div>
                                                </div>
                                                <div>
                                                    <div class="tc-label">"Source quotation"</div>
                                                    <div class="tc-mono">{format!("{} r{}", s.quotation_number, s.quotation_revision)}</div>
                                                </div>
                                                <div>
                                                    <div class="tc-label">"Customer PO ref"</div>
                                                    <div class="tc-mono">{reference}</div>
                                                </div>
                                                <div>
                                                    <div class="tc-label">"Purpose / VAT regime"</div>
                                                    <div>{format!("{} · {}", s.purpose, s.vat_regime)}</div>
                                                </div>
                                                <div>
                                                    <div class="tc-label">"Order date"</div>
                                                    <div class="tc-mono">{s.order_date.to_string()}</div>
                                                </div>
                                                <div>
                                                    <div class="tc-label">"Promised date"</div>
                                                    <div class="tc-mono">{promised}</div>
                                                </div>
                                                <div>
                                                    <div class="tc-label">"Salesperson"</div>
                                                    <div>{s.salesperson_name.clone()}</div>
                                                </div>
                                                <div>
                                                    <div class="tc-label">"Revision status"</div>
                                                    <div class="tc-mono">{tab.revision_status().to_string()}</div>
                                                </div>
                                            </div>

                                            {tab.detail.as_ref().map(|d| view! {
                                                <div style="display: flex; flex-direction: column; gap: var(--space-md);">
                                                    {(!d.notes.trim().is_empty()).then(|| view! {
                                                        <div style="font-size: 12px; color: var(--on-surface-variant);">
                                                            <span class="tc-label">"Notes: "</span>
                                                            <span>{d.notes.clone()}</span>
                                                        </div>
                                                    })}

                                                    {(!d.confirmation_note.trim().is_empty()).then(|| view! {
                                                        <div style="font-size: 12px; color: var(--on-surface-variant);">
                                                            <span class="tc-label">"Confirmation note: "</span>
                                                            <span>{d.confirmation_note.clone()}</span>
                                                        </div>
                                                    })}

                                                    <div class="tc-table-wrap" data-target="order-lines-table">
                                                        <table class="tc-table">
                                                            <thead>
                                                                <tr>
                                                                    <th>"#"</th>
                                                                    <th>"Product"</th>
                                                                    <th class="tc-num">"Qty"</th>
                                                                    <th class="tc-num">"Net"</th>
                                                                    <th class="tc-num">"Total"</th>
                                                                </tr>
                                                            </thead>
                                                            <tbody>
                                                                {d.lines.iter().map(|line| view! {
                                                                    <tr>
                                                                        <td class="tc-mono">{line.position}</td>
                                                                        <td>
                                                                            <div class="tc-mono">{line.product_code.clone()}</div>
                                                                            <div style="font-size: 11px; color: var(--on-surface-variant);">{line.description.clone()}</div>
                                                                        </td>
                                                                        <td class="tc-num tc-mono">{format!("{} {}", line.quantity, line.unit)}</td>
                                                                        <td class="tc-num tc-mono">{line.net_unit_price.to_string()}</td>
                                                                        <td class="tc-num tc-mono">{line.line_total.to_string()}</td>
                                                                    </tr>
                                                                }).collect_view()}
                                                            </tbody>
                                                        </table>
                                                    </div>

                                                    <div class="tc-card" style="padding: var(--space-sm); display: flex; justify-content: space-between; font-size: 12px;" data-target="order-totals">
                                                        <span>{format!("Subtotal: {} {}", d.order.subtotal, d.order.currency)}</span>
                                                        <span>{format!("VAT: {} {}", d.vat_total, d.order.currency)}</span>
                                                        <strong>{format!("Total: {} {}", d.order.total, d.order.currency)}</strong>
                                                    </div>

                                                    {(!d.revisions.is_empty()).then(|| view! {
                                                        <div style="font-size: 12px;">
                                                            <div class="tc-label" style="margin-bottom: var(--space-xs);">"Revisions"</div>
                                                            <div style="display: flex; flex-direction: column; gap: 4px;">
                                                                {d.revisions.iter().map(|rev| view! {
                                                                    <div style="display: flex; justify-content: space-between; color: var(--on-surface-variant);">
                                                                        <span class="tc-mono">{format!("r{} ({})", rev.revision, rev.status)}</span>
                                                                        <span class="tc-mono">{format!("{} {}", rev.total, d.order.currency)}</span>
                                                                    </div>
                                                                }).collect_view()}
                                                            </div>
                                                        </div>
                                                    })}
                                                </div>
                                            })}
                                        </div>
                                    }
                                })}

                                <Show when=move || {
                                    read_order_tab(&open_tabs, &tab_id_confirm_note, |t| {
                                        matches!(t.revision_status(), "draft" | "sent")
                                    })
                                    .unwrap_or(false)
                                }>
                                    <div class="tc-field">
                                        <label class="tc-label" for="order-confirm-note">"Confirmation note"</label>
                                        <input
                                            id="order-confirm-note"
                                            data-target="order-confirm-note"
                                            class="tc-input"
                                            type="text"
                                            placeholder="e.g. Confirmed by phone"
                                            prop:value=move || tab_id_sv.with_value(|tid| read_order_tab(&open_tabs, tid, |t| t.confirm_note.clone()).unwrap_or_default())
                                            on:input=move |ev| {
                                                let val = event_target_value(&ev);
                                                tab_id_sv.with_value(|tid| {
                                                    update_order_tab(&open_tabs, tid, |t| t.confirm_note = val);
                                                });
                                            }
                                        />
                                    </div>
                                </Show>

                                <div class="tc-form-actions">
                                    <button
                                        type="button"
                                        data-target="order-detail-close"
                                        class="tc-btn"
                                        on:click=move |_| close_order_tab(&open_tabs, &active_tab_id, &tab_id_close)
                                    >
                                        "Close"
                                    </button>

                                    {move || {
                                        let state = read_order_tab(&open_tabs, &tab_id_actions, |t| {
                                            (t.revision_status().to_string(), t.busy)
                                        });
                                        let Some((rev_status, busy)) = state else {
                                            return view! { <span></span> }.into_any();
                                        };
                                        view! {
                                            <>
                                                {(rev_status == "draft").then(|| view! {
                                                    <button
                                                        type="button"
                                                        data-target="order-send"
                                                        class="tc-btn"
                                                        disabled=busy
                                                        on:click=on_send.clone()
                                                    >
                                                        "Send Order"
                                                    </button>
                                                })}
                                                {matches!(rev_status.as_str(), "draft" | "sent").then(|| view! {
                                                    <button
                                                        type="button"
                                                        data-target="order-confirm"
                                                        class="tc-btn tc-btn-primary"
                                                        disabled=busy
                                                        on:click=on_confirm.clone()
                                                    >
                                                        {if busy { "Working..." } else { "Confirm Order" }}
                                                    </button>
                                                })}
                                            </>
                                        }.into_any()
                                    }}
                                </div>
                            </aside>
                        }
                    })}
                </div>
            </Show>
        </div>
    }
}
