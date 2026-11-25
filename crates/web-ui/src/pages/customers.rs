use leptos::ev::SubmitEvent;
use leptos::prelude::*;
use leptos::task::spawn_local;
use leptos_router::components::A;
use rust_decimal::Decimal;
use uuid::Uuid;

use crate::api::{
    ApiClient, ConnectionMode, CreateCustomerRequest, Customer, ListCustomersParams,
    UpdateCustomerRequest, WebApiClient,
};
use crate::pages::{fmt_opt_display, opt_trimmed, parse_decimal, parse_i32, parse_uuid};
use crate::state::AppContext;

const DEFAULT_PRICE_ZONE_ID: &str = "00000000-0000-7000-8000-000000000201";

#[derive(Debug, Clone, PartialEq, Eq)]
struct CustomerTab {
    tab_id: String,
    customer_id: Option<Uuid>,
    version: Option<i64>,
    title: String,
    loading_detail: bool,
    saving: bool,
    dirty: bool,
    error: Option<String>,
    notice: Option<String>,
    code: String,
    name: String,
    vat_number: String,
    vat_regime: String,
    email: String,
    phone: String,
    street: String,
    postal_code: String,
    city: String,
    country_code: String,
    language: String,
    active: bool,
    price_zone_id: String,
    discount_percent: String,
    payment_terms_days: String,
}

impl CustomerTab {
    fn new_draft(default_zone_id: &str) -> Self {
        Self {
            tab_id: "new".to_string(),
            customer_id: None,
            version: None,
            title: "New Customer".to_string(),
            loading_detail: false,
            saving: false,
            dirty: false,
            error: None,
            notice: None,
            code: String::new(),
            name: String::new(),
            vat_number: String::new(),
            vat_regime: String::new(),
            email: String::new(),
            phone: String::new(),
            street: String::new(),
            postal_code: String::new(),
            city: String::new(),
            country_code: "BE".to_string(),
            language: "nl".to_string(),
            active: true,
            price_zone_id: default_zone_id.to_string(),
            discount_percent: "0".to_string(),
            payment_terms_days: "30".to_string(),
        }
    }

    fn from_customer(c: &Customer, loading_detail: bool, default_zone_id: &str) -> Self {
        Self {
            tab_id: format!("edit:{}", c.id),
            customer_id: Some(c.id),
            version: Some(c.version),
            title: format!("{} · {}", c.code, c.name),
            loading_detail,
            saving: false,
            dirty: false,
            error: None,
            notice: None,
            code: c.code.clone(),
            name: c.name.clone(),
            vat_number: c.vat_number.clone().unwrap_or_default(),
            vat_regime: c.vat_regime.clone(),
            email: c.email.clone().unwrap_or_default(),
            phone: c.phone.clone().unwrap_or_default(),
            street: c.street.clone(),
            postal_code: c.postal_code.clone(),
            city: c.city.clone(),
            country_code: c.country_code.clone(),
            language: c.language.clone(),
            active: c.active,
            price_zone_id: c
                .price_zone_id
                .map(|id| id.to_string())
                .unwrap_or_else(|| default_zone_id.to_string()),
            discount_percent: c
                .discount_percent
                .map(|d| d.to_string())
                .unwrap_or_else(|| "0".to_string()),
            payment_terms_days: fmt_opt_display(c.payment_terms_days.or(Some(30))),
        }
    }

    fn apply_saved(&mut self, saved: &Customer, notice: Option<String>, default_zone_id: &str) {
        let mut updated = Self::from_customer(saved, false, default_zone_id);
        updated.notice = notice;
        *self = updated;
    }

    fn to_request(&self) -> Result<CreateCustomerRequest, String> {
        let code = self.code.trim();
        let name = self.name.trim();
        if code.is_empty() || name.is_empty() {
            return Err("Code and name are required.".to_string());
        }
        let country_code = self.country_code.trim();
        if country_code.len() != 2 {
            return Err("Country code must be a 2-letter ISO code (e.g. BE).".to_string());
        }
        let language = self.language.trim();
        Ok(UpdateCustomerRequest {
            code: code.to_string(),
            name: name.to_string(),
            vat_number: opt_trimmed(&self.vat_number),
            vat_regime: opt_trimmed(&self.vat_regime),
            email: opt_trimmed(&self.email),
            phone: opt_trimmed(&self.phone),
            street: self.street.trim().to_string(),
            postal_code: self.postal_code.trim().to_string(),
            city: self.city.trim().to_string(),
            country_code: country_code.to_ascii_uppercase(),
            language: if language.is_empty() {
                "nl".to_string()
            } else {
                language.to_ascii_lowercase()
            },
            active: self.active,
            price_zone_id: parse_uuid("Price zone ID", &self.price_zone_id)?,
            discount_percent: parse_decimal("Discount %", &self.discount_percent, Decimal::ZERO)?,
            payment_terms_days: parse_i32("Payment terms (days)", &self.payment_terms_days, 30)?,
            expected_version: self.version,
        })
    }
}

fn read_customer_tab<R>(
    tabs: &RwSignal<Vec<CustomerTab>>,
    tab_id: &str,
    f: impl FnOnce(&CustomerTab) -> R,
) -> Option<R> {
    tabs.with(|list| list.iter().find(|t| t.tab_id == tab_id).map(f))
}

fn update_customer_tab(
    tabs: &RwSignal<Vec<CustomerTab>>,
    tab_id: &str,
    f: impl FnOnce(&mut CustomerTab),
) {
    tabs.update(|list| {
        if let Some(tab) = list.iter_mut().find(|t| t.tab_id == tab_id) {
            f(tab);
        }
    });
}

fn close_customer_tab(
    tabs: &RwSignal<Vec<CustomerTab>>,
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

    let open_tabs = RwSignal::new(Vec::<CustomerTab>::new());
    let active_tab_id = RwSignal::new(Option::<String>::None);

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
            open_tabs.set(Vec::new());
            active_tab_id.set(None);
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

    let inferred_default_zone = move || -> String {
        items.with_untracked(|list| {
            list.iter()
                .find_map(|c| c.price_zone_id)
                .map(|id| id.to_string())
                .unwrap_or_else(|| DEFAULT_PRICE_ZONE_ID.to_string())
        })
    };

    let known_zones = Memo::new(move |_| {
        items.with(|list| {
            let mut zones: Vec<(String, String)> = Vec::new();
            for c in list {
                if let Some(zid) = c.price_zone_id {
                    let id_str = zid.to_string();
                    if !zones.iter().any(|(existing, _)| existing == &id_str) {
                        let label = c
                            .price_zone_code
                            .clone()
                            .unwrap_or_else(|| id_str[..8].to_string());
                        zones.push((id_str, label));
                    }
                }
            }
            zones
        })
    });

    let on_create_click = move |_| {
        let default_zone = inferred_default_zone();
        open_tabs.update(|list| {
            if !list.iter().any(|t| t.tab_id == "new") {
                list.push(CustomerTab::new_draft(&default_zone));
            }
        });
        active_tab_id.set(Some("new".to_string()));
    };

    let open_customer_row = move |customer: Customer| {
        let default_zone = inferred_default_zone();
        let tab_id = format!("edit:{}", customer.id);
        let already_open = open_tabs.with_untracked(|list| list.iter().any(|t| t.tab_id == tab_id));
        if !already_open {
            open_tabs.update(|list| {
                list.push(CustomerTab::from_customer(&customer, true, &default_zone));
            });
        }
        active_tab_id.set(Some(tab_id.clone()));

        if let Some(session) = ctx.session.get_untracked() {
            let connection = session.connection;
            let customer_id = customer.id;
            spawn_local(async move {
                match WebApiClient.get_customer(&connection, customer_id).await {
                    Ok(fresh) => {
                        update_customer_tab(&open_tabs, &tab_id, |tab| {
                            if !tab.dirty {
                                tab.apply_saved(&fresh, None, &default_zone);
                            } else {
                                tab.loading_detail = false;
                                tab.version = Some(fresh.version);
                            }
                        });
                    }
                    Err(err) => {
                        update_customer_tab(&open_tabs, &tab_id, |tab| {
                            tab.loading_detail = false;
                            if tab.error.is_none() {
                                tab.error = Some(err.user_message());
                            }
                        });
                    }
                }
            });
        }
    };

    view! {
        <div data-target="customers-page">
            <div class="tc-page-header">
                <div>
                    <h1 class="tc-page-title">"Customers"</h1>
                    <p class="tc-page-subtitle" data-target="customers-total">
                        {move || format!("CRM directory ({} total)", total.get())}
                    </p>
                </div>
                <div class="tc-header-actions">
                    <button
                        type="button"
                        data-target="customers-create"
                        class="tc-btn tc-btn-primary"
                        disabled=move || !is_signed_in.get()
                        on:click=on_create_click
                    >
                        "+ New Customer"
                    </button>
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
            </div>

            <Show
                when=move || is_signed_in.get()
                fallback=|| view! {
                    <div class="tc-card">
                        <p style="margin: 0 0 var(--space-md);">
                            "Sign in to load customers from GET /api/v1/customers (or pick Offline Mock on the sign-in screen)."
                        </p>
                        <A href=crate::components::shell::app_href("/login") attr:class="tc-btn tc-btn-primary" attr:data-target="customers-go-login">
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
                                            key=|c| (c.id, c.version, c.code.clone(), c.name.clone(), c.active)
                                            children=move |customer| {
                                                let open_customer = customer.clone();
                                                let row_tab_id = format!("edit:{}", customer.id);
                                                let row_target = format!("customer-row-{}", customer.code);
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
                                                        title="Open customer detail & edit form"
                                                        on:click=move |_| open_customer_row(open_customer.clone())
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
                    </div>

                    {move || active_tab_id.get().map(|current_tab_id| {
                        let tab_id_for_submit = current_tab_id.clone();
                        let tab_id_for_cancel = current_tab_id.clone();
                        let tab_id_for_header = current_tab_id.clone();
                        let tab_id_for_badge = current_tab_id.clone();
                        let tab_id_for_error = current_tab_id.clone();
                        let tab_id_for_notice = current_tab_id.clone();
                        let tab_id_for_saving = current_tab_id.clone();
                        let tab_id_for_zones = StoredValue::new(current_tab_id.clone());
                        let tab_id_for_zone_input = current_tab_id.clone();
                        let tab_id_for_active = current_tab_id.clone();

                        let on_submit = move |ev: SubmitEvent| {
                            ev.prevent_default();
                            let Some(session) = ctx.session.get_untracked() else {
                                return;
                            };
                            let Some(snapshot) = read_customer_tab(&open_tabs, &tab_id_for_submit, Clone::clone) else {
                                return;
                            };
                            if snapshot.saving {
                                return;
                            }
                            let req = match snapshot.to_request() {
                                Ok(req) => req,
                                Err(msg) => {
                                    update_customer_tab(&open_tabs, &tab_id_for_submit, |tab| {
                                        tab.error = Some(msg);
                                        tab.notice = None;
                                    });
                                    return;
                                }
                            };

                            update_customer_tab(&open_tabs, &tab_id_for_submit, |tab| {
                                tab.saving = true;
                                tab.error = None;
                                tab.notice = None;
                            });

                            let current_id = tab_id_for_submit.clone();
                            let connection = session.connection;
                            let customer_id = snapshot.customer_id;
                            let default_zone = inferred_default_zone();
                            spawn_local(async move {
                                let res = match customer_id {
                                    Some(id) => WebApiClient.update_customer(&connection, id, &req).await,
                                    None => WebApiClient.create_customer(&connection, &req).await,
                                };
                                match res {
                                    Ok(saved) => {
                                        let next_id = format!("edit:{}", saved.id);
                                        open_tabs.update(|list| {
                                            if current_id != next_id {
                                                list.retain(|t| t.tab_id != next_id);
                                            }
                                            if let Some(tab) = list.iter_mut().find(|t| t.tab_id == current_id) {
                                                tab.apply_saved(&saved, Some("Saved".to_string()), &default_zone);
                                            }
                                        });
                                        if active_tab_id.get_untracked().as_deref() == Some(current_id.as_str()) {
                                            active_tab_id.set(Some(next_id));
                                        }
                                        reload_nonce.update(|n| *n += 1);
                                    }
                                    Err(err) => {
                                        update_customer_tab(&open_tabs, &current_id, |tab| {
                                            tab.saving = false;
                                            tab.error = Some(err.user_message());
                                        });
                                    }
                                }
                            });
                        };

                        view! {
                            <aside class="tc-card tc-detail-drawer" data-target="customer-detail-drawer">
                                <div class="tc-inline-tabs" data-target="customer-detail-tabs">
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
                                                        on:click=move |_| close_customer_tab(&open_tabs, &active_tab_id, &close_id)
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
                                                read_customer_tab(&open_tabs, &tab_id_for_header, |t| t.title.clone())
                                                    .unwrap_or_else(|| "Customer".to_string())
                                            }}
                                        </h2>
                                        <p class="tc-page-subtitle tc-mono">
                                            {move || {
                                                read_customer_tab(&open_tabs, &tab_id_for_badge, |t| {
                                                    match (t.customer_id, t.version) {
                                                        (Some(id), Some(v)) if t.loading_detail => format!("{id} · v{v} (loading...)"),
                                                        (Some(id), Some(v)) => format!("{id} · v{v}"),
                                                        (Some(id), None) => id.to_string(),
                                                        (None, _) => "POST /api/v1/customers".to_string(),
                                                    }
                                                })
                                                .unwrap_or_default()
                                            }}
                                        </p>
                                    </div>
                                </div>

                                {move || {
                                    read_customer_tab(&open_tabs, &tab_id_for_error, |t| t.error.clone())
                                        .flatten()
                                        .map(|msg| view! {
                                            <div class="tc-alert-error" role="alert" data-target="customer-form-error">
                                                {msg}
                                            </div>
                                        })
                                }}

                                {move || {
                                    read_customer_tab(&open_tabs, &tab_id_for_notice, |t| t.notice.clone())
                                        .flatten()
                                        .map(|msg| view! {
                                            <div class="tc-alert-success" role="status" data-target="customer-form-notice">
                                                {msg}
                                            </div>
                                        })
                                }}

                                <form data-target="customer-form" on:submit=on_submit style="display: flex; flex-direction: column; gap: var(--space-md);">
                                    <div class="tc-form-grid">
                                        {customer_text_field(&open_tabs, &current_tab_id, "Code *", "customer-form-code", "C0001", false, |t| t.code.clone(), |t, v| t.code = v)}
                                        {customer_text_field(&open_tabs, &current_tab_id, "Country *", "customer-form-country-code", "BE", false, |t| t.country_code.clone(), |t, v| t.country_code = v)}
                                        {customer_text_field(&open_tabs, &current_tab_id, "Name *", "customer-form-name", "Customer BV", true, |t| t.name.clone(), |t, v| t.name = v)}
                                        {customer_text_field(&open_tabs, &current_tab_id, "VAT number", "customer-form-vat-number", "BE0412345678", false, |t| t.vat_number.clone(), |t, v| t.vat_number = v)}

                                        {customer_select_field(
                                            &open_tabs,
                                            &current_tab_id,
                                            "VAT regime",
                                            "customer-form-vat-regime",
                                            &[
                                                ("", "Auto-derive"),
                                                ("domestic", "Domestic"),
                                                ("domestic_reverse_charge", "Domestic reverse charge"),
                                                ("intra_eu", "Intra-EU"),
                                                ("outside_eu", "Outside EU"),
                                            ],
                                            |t| t.vat_regime.clone(),
                                            |t, val| t.vat_regime = val,
                                        )}

                                        {customer_text_field(&open_tabs, &current_tab_id, "Email", "customer-form-email", "orders@example.com", false, |t| t.email.clone(), |t, v| t.email = v)}
                                        {customer_text_field(&open_tabs, &current_tab_id, "Phone", "customer-form-phone", "+32 3 555 01 00", false, |t| t.phone.clone(), |t, v| t.phone = v)}
                                        {customer_text_field(&open_tabs, &current_tab_id, "Street", "customer-form-street", "Meir 10", true, |t| t.street.clone(), |t, v| t.street = v)}
                                        {customer_text_field(&open_tabs, &current_tab_id, "Postal code", "customer-form-postal-code", "2000", false, |t| t.postal_code.clone(), |t, v| t.postal_code = v)}
                                        {customer_text_field(&open_tabs, &current_tab_id, "City", "customer-form-city", "Antwerpen", false, |t| t.city.clone(), |t, v| t.city = v)}

                                        {customer_select_field(
                                            &open_tabs,
                                            &current_tab_id,
                                            "Language",
                                            "customer-form-language",
                                            &[
                                                ("nl", "nl"),
                                                ("fr", "fr"),
                                                ("en", "en"),
                                                ("de", "de"),
                                                ("es", "es"),
                                            ],
                                            |t| t.language.clone(),
                                            |t, val| t.language = val,
                                        )}

                                        {customer_text_field(&open_tabs, &current_tab_id, "Discount %", "customer-form-discount-percent", "0", false, |t| t.discount_percent.clone(), |t, v| t.discount_percent = v)}
                                        {customer_text_field(&open_tabs, &current_tab_id, "Payment terms (days)", "customer-form-payment-terms", "30", false, |t| t.payment_terms_days.clone(), |t, v| t.payment_terms_days = v)}

                                        <div class="tc-field tc-form-span-2">
                                            <label class="tc-label" for="customer-form-price-zone-id">"Price zone ID *"</label>
                                            <input
                                                id="customer-form-price-zone-id"
                                                data-target="customer-form-price-zone-id"
                                                class="tc-input tc-mono"
                                                type="text"
                                                placeholder=DEFAULT_PRICE_ZONE_ID
                                                prop:value={
                                                    let tid = tab_id_for_zone_input.clone();
                                                    move || read_customer_tab(&open_tabs, &tid, |t| t.price_zone_id.clone()).unwrap_or_default()
                                                }
                                                on:input={
                                                    let tid = tab_id_for_zone_input;
                                                    move |ev| {
                                                        let val = event_target_value(&ev);
                                                        update_customer_tab(&open_tabs, &tid, |t| {
                                                            t.price_zone_id = val;
                                                            t.dirty = true;
                                                        });
                                                    }
                                                }
                                            />
                                            <Show when=move || !known_zones.with(Vec::is_empty)>
                                                <div class="tc-chip-row">
                                                    {move || {
                                                        let tid = tab_id_for_zones.get_value();
                                                        known_zones.get().into_iter().map(move |(zid, label)| {
                                                            let tid = tid.clone();
                                                            view! {
                                                                <button
                                                                    type="button"
                                                                    class="tc-chip"
                                                                    on:click=move |_| {
                                                                        let zone_id = zid.clone();
                                                                        update_customer_tab(&open_tabs, &tid, |t| {
                                                                            t.price_zone_id = zone_id;
                                                                            t.dirty = true;
                                                                        });
                                                                    }
                                                                >
                                                                    {label}
                                                                </button>
                                                            }
                                                        }).collect_view()
                                                    }}
                                                </div>
                                            </Show>
                                        </div>
                                    </div>

                                    <label class="tc-checkbox-row" for="customer-form-active">
                                        <input
                                            id="customer-form-active"
                                            data-target="customer-form-active"
                                            type="checkbox"
                                            prop:checked={
                                                let tid = tab_id_for_active.clone();
                                                move || read_customer_tab(&open_tabs, &tid, |t| t.active).unwrap_or(true)
                                            }
                                            on:change={
                                                let tid = tab_id_for_active;
                                                move |ev| {
                                                    let checked = event_target_checked(&ev);
                                                    update_customer_tab(&open_tabs, &tid, |t| {
                                                        t.active = checked;
                                                        t.dirty = true;
                                                    });
                                                }
                                            }
                                        />
                                        <span>"Active"</span>
                                    </label>

                                    <div class="tc-form-actions">
                                        <button
                                            type="button"
                                            data-target="customer-form-cancel"
                                            class="tc-btn"
                                            on:click=move |_| close_customer_tab(&open_tabs, &active_tab_id, &tab_id_for_cancel)
                                        >
                                            "Cancel"
                                        </button>
                                        <button
                                            type="submit"
                                            data-target="customer-form-save"
                                            class="tc-btn tc-btn-primary"
                                            disabled=move || read_customer_tab(&open_tabs, &tab_id_for_saving, |t| t.saving).unwrap_or(false)
                                        >
                                            {move || {
                                                if read_customer_tab(&open_tabs, &current_tab_id, |t| t.saving).unwrap_or(false) {
                                                    "Saving..."
                                                } else {
                                                    "Save"
                                                }
                                            }}
                                        </button>
                                    </div>
                                </form>
                            </aside>
                        }
                    })}
                </div>
            </Show>
        </div>
    }
}

#[allow(clippy::too_many_arguments)]
fn customer_select_field(
    tabs: &RwSignal<Vec<CustomerTab>>,
    tab_id: &str,
    label: &'static str,
    target: &'static str,
    options: &'static [(&'static str, &'static str)],
    get: fn(&CustomerTab) -> String,
    set: fn(&mut CustomerTab, String),
) -> impl IntoView {
    let tabs = *tabs;
    let tid_read = tab_id.to_string();
    let tid_write = tab_id.to_string();
    view! {
        <div class="tc-field">
            <label class="tc-label" for=target>{label}</label>
            <select
                id=target
                data-target=target
                class="tc-select"
                prop:value=move || read_customer_tab(&tabs, &tid_read, get).unwrap_or_default()
                on:change=move |ev| {
                    let val = event_target_value(&ev);
                    update_customer_tab(&tabs, &tid_write, |tab| {
                        set(tab, val);
                        tab.dirty = true;
                    });
                }
            >
                {options.iter().map(|(value, text)| {
                    view! { <option value=*value>{*text}</option> }
                }).collect_view()}
            </select>
        </div>
    }
}

#[allow(clippy::too_many_arguments)]
fn customer_text_field(
    tabs: &RwSignal<Vec<CustomerTab>>,
    tab_id: &str,
    label: &'static str,
    target: &'static str,
    placeholder: &'static str,
    span_two: bool,
    get: fn(&CustomerTab) -> String,
    set: fn(&mut CustomerTab, String),
) -> impl IntoView {
    let tabs = *tabs;
    let tid_read = tab_id.to_string();
    let tid_write = tab_id.to_string();
    let field_class = if span_two {
        "tc-field tc-form-span-2"
    } else {
        "tc-field"
    };
    view! {
        <div class=field_class>
            <label class="tc-label" for=target>{label}</label>
            <input
                id=target
                data-target=target
                class="tc-input"
                type="text"
                placeholder=placeholder
                prop:value=move || read_customer_tab(&tabs, &tid_read, get).unwrap_or_default()
                on:input=move |ev| {
                    let val = event_target_value(&ev);
                    update_customer_tab(&tabs, &tid_write, |tab| {
                        set(tab, val);
                        tab.dirty = true;
                    });
                }
            />
        </div>
    }
}
