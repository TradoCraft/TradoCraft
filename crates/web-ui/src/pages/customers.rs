use leptos::prelude::*;
use leptos::task::spawn_local;
use leptos_router::components::A;

use crate::api::{ApiClient, ConnectionMode, Customer, ListCustomersParams, WebApiClient};
use crate::state::{AppContext, WorkspaceTab};

#[component]
pub fn CustomersPage() -> impl IntoView {
    let ctx = expect_context::<AppContext>();

    let search = RwSignal::new(String::new());
    let active_filter = RwSignal::new("all".to_string());

    let loading = RwSignal::new(false);
    let error = RwSignal::new(Option::<String>::None);
    let items = RwSignal::new(Vec::<Customer>::new());
    let total = RwSignal::new(0_i64);
    let reload_nonce = RwSignal::new(0_u64);

    let fetch_customers = move |connection: ConnectionMode, params: ListCustomersParams| {
        loading.set(true);
        error.set(None);
        spawn_local(async move {
            match WebApiClient.list_customers(&connection, &params).await {
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
        let af = active_filter.get();

        let Some(session) = active_session else {
            items.set(Vec::new());
            total.set(0);
            error.set(None);
            return;
        };

        let active = match af.as_str() {
            "active" => Some(true),
            "inactive" => Some(false),
            _ => None,
        };
        let params = ListCustomersParams {
            q: (!q.trim().is_empty()).then_some(q),
            active,
            limit: Some(50),
            offset: Some(0),
            ..ListCustomersParams::default()
        };
        fetch_customers(session.connection, params);
    });

    let is_signed_in = Memo::new(move |_| ctx.session.with(|s| s.is_some()));

    view! {
        <div data-target="customers-page">
            <div class="tc-page-header">
                <div>
                    <h1 class="tc-page-title">"Customers"</h1>
                    <p class="tc-page-subtitle" data-target="customers-total">
                        {move || format!("Read-only CRM directory ({} total)", total.get())}
                    </p>
                </div>
                <button
                    type="button"
                    data-target="customers-refresh"
                    class="tc-btn"
                    disabled=move || loading.get() || !is_signed_in.get()
                    on:click=move |_| reload_nonce.update(|n| *n += 1)
                >
                    {move || if loading.get() { "Loading..." } else { "Refresh" }}
                </button>
            </div>

            <Show
                when=move || is_signed_in.get()
                fallback=|| view! {
                    <div class="tc-card">
                        <p style="margin: 0 0 var(--space-md);">
                            "Sign in to load customers from GET /api/v1/customers (or pick Offline Mock on the sign-in screen)."
                        </p>
                        <A href="/login" attr:class="tc-btn tc-btn-primary" attr:data-target="customers-go-login">
                            "Go to sign in"
                        </A>
                    </div>
                }
            >
                <div class="tc-toolbar">
                    <input
                        data-target="customers-search"
                        class="tc-input"
                        style="min-width: 240px;"
                        type="search"
                        placeholder="Search code, name, VAT or city..."
                        prop:value=move || search.get()
                        on:input=move |ev| search.set(event_target_value(&ev))
                    />
                    <select
                        data-target="customers-active-filter"
                        class="tc-select"
                        prop:value=move || active_filter.get()
                        on:change=move |ev| active_filter.set(event_target_value(&ev))
                    >
                        <option value="all">"All statuses"</option>
                        <option value="active">"Active only"</option>
                        <option value="inactive">"Inactive only"</option>
                    </select>
                </div>

                {move || error.get().map(|msg| view! {
                    <div class="tc-alert-error" style="margin-bottom: var(--space-md);" role="alert" data-target="customers-error">
                        {msg}
                    </div>
                })}

                <div class="tc-table-wrap">
                    <table class="tc-table" data-target="customers-table">
                        <thead>
                            <tr>
                                <th>"Code"</th>
                                <th>"Name"</th>
                                <th>"VAT"</th>
                                <th>"City"</th>
                                <th>"Country"</th>
                                <th>"Zone"</th>
                                <th>"Status"</th>
                            </tr>
                        </thead>
                        <tbody>
                            <Show
                                when=move || !items.with(Vec::is_empty)
                                fallback=move || view! {
                                    <tr>
                                        <td colspan="7" style="text-align: center; color: var(--on-surface-variant); padding: var(--space-xl);">
                                            {move || if loading.get() {
                                                "Loading customers..."
                                            } else {
                                                "No customers match the current filter."
                                            }}
                                        </td>
                                    </tr>
                                }
                            >
                                <For
                                    each=move || items.get()
                                    key=|c| c.id
                                    children=move |customer| {
                                        let open_customer = customer.clone();
                                        let row_target = format!("customer-row-{}", customer.code);
                                        view! {
                                            <tr
                                                class="tc-row-clickable"
                                                data-target=row_target
                                                title="Open in workspace tab"
                                                on:click=move |_| {
                                                    ctx.open_tab(WorkspaceTab {
                                                        id: format!("customer:{}", open_customer.id),
                                                        title: format!("{} · {}", open_customer.code, open_customer.name),
                                                        route: format!("/customers/{}", open_customer.id),
                                                        subtitle: format!(
                                                            "{}, {} ({}, VAT regime: {})",
                                                            open_customer.city,
                                                            open_customer.country_code,
                                                            open_customer.vat_number.as_deref().unwrap_or("no VAT"),
                                                            open_customer.vat_regime,
                                                        ),
                                                    });
                                                }
                                            >
                                                <td class="tc-mono">{customer.code}</td>
                                                <td>{customer.name}</td>
                                                <td class="tc-mono">{customer.vat_number.unwrap_or_else(|| "—".to_string())}</td>
                                                <td>{customer.city}</td>
                                                <td>{customer.country_code}</td>
                                                <td class="tc-mono">{customer.price_zone_code.unwrap_or_else(|| "—".to_string())}</td>
                                                <td>
                                                    {if customer.active {
                                                        view! { <span class="tc-badge tc-badge-success">"Active"</span> }.into_any()
                                                    } else {
                                                        view! { <span class="tc-badge">"Inactive"</span> }.into_any()
                                                    }}
                                                </td>
                                            </tr>
                                        }
                                    }
                                />
                            </Show>
                        </tbody>
                    </table>
                </div>
            </Show>
        </div>
    }
}
