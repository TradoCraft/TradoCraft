use leptos::ev::SubmitEvent;
use leptos::prelude::*;
use leptos::task::spawn_local;
use leptos_router::components::A;
use rust_decimal::Decimal;
use tradocraft_api_client::suppliers::{
    ListSuppliersParams, Supplier, SupplierInput, SupplierProduct, SupplierProductInput,
    UpdateSupplierInput,
};
use tradocraft_api_client::{ApiError, Client};
use uuid::Uuid;

use crate::api::{
    resolve_base_url, ApiClient, ConnectionMode, ListProductsParams, Product, WebApiClient,
};
use crate::pages::{
    opt_trimmed, parse_decimal, parse_i32, parse_opt_decimal, parse_opt_i32, parse_uuid,
};
use crate::state::AppContext;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum DrawerSection {
    Details,
    Products,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct SupplierTab {
    instance_id: u64,
    edit_generation: u64,
    tab_id: String,
    supplier_id: Option<Uuid>,
    title: String,
    section: DrawerSection,
    loading_detail: bool,
    saving: bool,
    dirty: bool,
    error: Option<String>,
    notice: Option<String>,
    code: String,
    name: String,
    country: String,
    currency: String,
    email: String,
    phone: String,
    contact_person: String,
    payment_terms_days: String,
    tax_id: String,
    active: bool,
    notes: String,
    products_generation: u64,
    products_loading: bool,
    products_loaded: bool,
    products_error: Option<String>,
    products: Vec<SupplierProduct>,
    price_form_open: bool,
    price_saving: bool,
    price_product_id: String,
    price_supplier_product_code: String,
    price_supplier_product_name: String,
    price_currency: String,
    price_unit_price: String,
    price_moq: String,
    price_lead_time_days: String,
    price_is_preferred: bool,
}

impl SupplierTab {
    fn new_draft(instance_id: u64) -> Self {
        Self {
            instance_id,
            edit_generation: 0,
            tab_id: "new".to_string(),
            supplier_id: None,
            title: "New Supplier".to_string(),
            section: DrawerSection::Details,
            loading_detail: false,
            saving: false,
            dirty: false,
            error: None,
            notice: None,
            code: String::new(),
            name: String::new(),
            country: "BE".to_string(),
            currency: "EUR".to_string(),
            email: String::new(),
            phone: String::new(),
            contact_person: String::new(),
            payment_terms_days: "30".to_string(),
            tax_id: String::new(),
            active: true,
            notes: String::new(),
            products_generation: 0,
            products_loading: false,
            products_loaded: false,
            products_error: None,
            products: Vec::new(),
            price_form_open: false,
            price_saving: false,
            price_product_id: String::new(),
            price_supplier_product_code: String::new(),
            price_supplier_product_name: String::new(),
            price_currency: "EUR".to_string(),
            price_unit_price: String::new(),
            price_moq: "1".to_string(),
            price_lead_time_days: "0".to_string(),
            price_is_preferred: false,
        }
    }

    fn from_supplier(s: &Supplier, loading_detail: bool, instance_id: u64) -> Self {
        let title = if s.code.trim().is_empty() {
            s.name.clone()
        } else {
            format!("{} · {}", s.code, s.name)
        };
        Self {
            instance_id,
            edit_generation: 0,
            tab_id: format!("edit:{}", s.id),
            supplier_id: Some(s.id),
            title,
            section: DrawerSection::Details,
            loading_detail,
            saving: false,
            dirty: false,
            error: None,
            notice: None,
            code: s.code.clone(),
            name: s.name.clone(),
            country: s.country.clone(),
            currency: s.currency.clone(),
            email: s.email.clone(),
            phone: s.phone.clone(),
            contact_person: s.contact_person.clone(),
            payment_terms_days: s.payment_terms_days.to_string(),
            tax_id: s.tax_id.clone(),
            active: s.active,
            notes: s.notes.clone(),
            products_generation: 0,
            products_loading: false,
            products_loaded: false,
            products_error: None,
            products: Vec::new(),
            price_form_open: false,
            price_saving: false,
            price_product_id: String::new(),
            price_supplier_product_code: String::new(),
            price_supplier_product_name: String::new(),
            price_currency: s.currency.clone(),
            price_unit_price: String::new(),
            price_moq: "1".to_string(),
            price_lead_time_days: "0".to_string(),
            price_is_preferred: false,
        }
    }

    fn mark_dirty(&mut self) {
        self.dirty = true;
        self.edit_generation += 1;
    }

    fn apply_saved(&mut self, saved: &Supplier, notice: Option<String>) {
        let title = if saved.code.trim().is_empty() {
            saved.name.clone()
        } else {
            format!("{} · {}", saved.code, saved.name)
        };
        self.tab_id = format!("edit:{}", saved.id);
        self.supplier_id = Some(saved.id);
        self.title = title;
        self.loading_detail = false;
        self.saving = false;
        self.dirty = false;
        self.error = None;
        self.notice = notice;
        self.code = saved.code.clone();
        self.name = saved.name.clone();
        self.country = saved.country.clone();
        self.currency = saved.currency.clone();
        self.email = saved.email.clone();
        self.phone = saved.phone.clone();
        self.contact_person = saved.contact_person.clone();
        self.payment_terms_days = saved.payment_terms_days.to_string();
        self.tax_id = saved.tax_id.clone();
        self.active = saved.active;
        self.notes = saved.notes.clone();
        if self.price_currency.trim().is_empty() {
            self.price_currency = saved.currency.clone();
        }
    }

    fn apply_saved_preserving_edits(&mut self, saved: &Supplier, notice: Option<String>) {
        let title = if self.code.trim().is_empty() {
            self.name.clone()
        } else {
            format!("{} · {}", self.code, self.name)
        };
        self.tab_id = format!("edit:{}", saved.id);
        self.supplier_id = Some(saved.id);
        self.title = title;
        self.loading_detail = false;
        self.saving = false;
        self.dirty = true;
        self.error = None;
        self.notice = notice;
    }

    fn reset_price_form(&mut self, default_product_id: &str) {
        self.price_form_open = true;
        self.price_saving = false;
        self.products_error = None;
        self.price_product_id = default_product_id.to_string();
        self.price_supplier_product_code.clear();
        self.price_supplier_product_name.clear();
        self.price_currency = if self.currency.trim().is_empty() {
            "EUR".to_string()
        } else {
            self.currency.trim().to_ascii_uppercase()
        };
        self.price_unit_price.clear();
        self.price_moq = "1".to_string();
        self.price_lead_time_days = "0".to_string();
        self.price_is_preferred = false;
    }

    fn populate_price_form(&mut self, entry: &SupplierProduct) {
        self.price_form_open = true;
        self.price_saving = false;
        self.products_error = None;
        self.price_product_id = entry.product_id.to_string();
        self.price_supplier_product_code = entry.supplier_product_code.clone();
        self.price_supplier_product_name = entry.supplier_product_name.clone();
        self.price_currency = entry.currency.clone();
        self.price_unit_price = entry.unit_price.to_string();
        self.price_moq = entry.moq.to_string();
        self.price_lead_time_days = entry.lead_time_days.to_string();
        self.price_is_preferred = entry.is_preferred;
    }

    fn validate_common(&self) -> Result<(String, String, String, i32), String> {
        let name = self.name.trim();
        if name.is_empty() {
            return Err("Supplier name is required.".to_string());
        }
        let country = self.country.trim().to_ascii_uppercase();
        if country.len() != 2 || !country.chars().all(|ch| ch.is_ascii_alphabetic()) {
            return Err("Country must be a 2-letter ISO code (e.g. BE).".to_string());
        }
        let currency = {
            let trimmed = self.currency.trim();
            if trimmed.is_empty() {
                "EUR".to_string()
            } else {
                trimmed.to_ascii_uppercase()
            }
        };
        if currency.len() != 3 || !currency.chars().all(|ch| ch.is_ascii_alphabetic()) {
            return Err("Currency must be a 3-letter ISO code (e.g. EUR).".to_string());
        }
        let payment_terms_days = parse_i32("Payment terms (days)", &self.payment_terms_days, 30)?;
        if payment_terms_days < 0 {
            return Err("Payment terms (days) cannot be negative.".to_string());
        }
        Ok((name.to_string(), country, currency, payment_terms_days))
    }

    fn to_create_request(&self) -> Result<SupplierInput, String> {
        let (name, country, currency, payment_terms_days) = self.validate_common()?;
        Ok(SupplierInput {
            name,
            code: opt_trimmed(&self.code).map(|c| c.to_ascii_uppercase()),
            country,
            currency: Some(currency),
            email: opt_trimmed(&self.email),
            phone: opt_trimmed(&self.phone),
            contact_person: opt_trimmed(&self.contact_person),
            payment_terms_days: Some(payment_terms_days),
            tax_id: opt_trimmed(&self.tax_id),
            notes: opt_trimmed(&self.notes),
        })
    }

    fn to_update_request(&self) -> Result<UpdateSupplierInput, String> {
        let (name, country, currency, payment_terms_days) = self.validate_common()?;
        Ok(UpdateSupplierInput {
            name: Some(name),
            code: Some(self.code.trim().to_ascii_uppercase()),
            country: Some(country),
            currency: Some(currency),
            email: Some(self.email.trim().to_string()),
            phone: Some(self.phone.trim().to_string()),
            contact_person: Some(self.contact_person.trim().to_string()),
            payment_terms_days: Some(payment_terms_days),
            tax_id: Some(self.tax_id.trim().to_string()),
            active: Some(self.active),
            notes: Some(self.notes.trim().to_string()),
        })
    }

    fn to_price_request(&self) -> Result<(Uuid, SupplierProductInput), String> {
        let product_id = parse_uuid("Product", &self.price_product_id)?;
        if self.price_unit_price.trim().is_empty() {
            return Err("Unit price is required.".to_string());
        }
        let unit_price = parse_decimal("Unit price", &self.price_unit_price, Decimal::ZERO)?;
        if unit_price < Decimal::ZERO {
            return Err("Unit price cannot be negative.".to_string());
        }
        let moq = parse_opt_decimal("MOQ", &self.price_moq)?;
        if let Some(m) = moq {
            if m <= Decimal::ZERO {
                return Err("MOQ must be greater than zero.".to_string());
            }
        }
        let lead_time_days = parse_opt_i32("Lead time (days)", &self.price_lead_time_days)?;
        if let Some(days) = lead_time_days {
            if days < 0 {
                return Err("Lead time (days) cannot be negative.".to_string());
            }
        }
        let currency = opt_trimmed(&self.price_currency).map(|c| c.to_ascii_uppercase());
        if let Some(ref curr) = currency {
            if curr.len() != 3 || !curr.chars().all(|ch| ch.is_ascii_alphabetic()) {
                return Err("Currency must be a 3-letter ISO code (e.g. EUR).".to_string());
            }
        }
        Ok((
            product_id,
            SupplierProductInput {
                supplier_product_code: Some(self.price_supplier_product_code.trim().to_string()),
                supplier_product_name: Some(self.price_supplier_product_name.trim().to_string()),
                currency,
                unit_price,
                moq,
                lead_time_days,
                is_preferred: Some(self.price_is_preferred),
            },
        ))
    }
}

fn live_client(connection: &ConnectionMode) -> Result<Client, ApiError> {
    match connection {
        ConnectionMode::Live(session) => {
            let mut resolved = session.clone();
            resolved.base_url = resolve_base_url(&session.base_url);
            Ok(Client::from_session(resolved))
        }
        ConnectionMode::MockDemo => Err(ApiError::InvalidConfig(
            "Supplier endpoints require a live API connection; switch to Dev User or Bearer mode on the sign-in screen."
                .to_string(),
        )),
    }
}

fn read_supplier_tab<R>(
    tabs: &RwSignal<Vec<SupplierTab>>,
    tab_id: &str,
    f: impl FnOnce(&SupplierTab) -> R,
) -> Option<R> {
    tabs.with(|list| list.iter().find(|t| t.tab_id == tab_id).map(f))
}

fn update_supplier_tab(
    tabs: &RwSignal<Vec<SupplierTab>>,
    tab_id: &str,
    f: impl FnOnce(&mut SupplierTab),
) {
    tabs.update(|list| {
        if let Some(tab) = list.iter_mut().find(|t| t.tab_id == tab_id) {
            f(tab);
        }
    });
}

fn update_supplier_tab_instance(
    tabs: &RwSignal<Vec<SupplierTab>>,
    tab_id: &str,
    instance_id: u64,
    f: impl FnOnce(&mut SupplierTab),
) {
    tabs.update(|list| {
        if let Some(tab) = list
            .iter_mut()
            .find(|t| t.tab_id == tab_id && t.instance_id == instance_id)
        {
            f(tab);
        }
    });
}

fn close_supplier_tab(
    tabs: &RwSignal<Vec<SupplierTab>>,
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
pub fn SuppliersPage() -> impl IntoView {
    let ctx = expect_context::<AppContext>();

    let search = RwSignal::new(String::new());
    let active_filter = RwSignal::new("all".to_string());

    let loading = RwSignal::new(false);
    let error = RwSignal::new(Option::<String>::None);
    let items = RwSignal::new(Vec::<Supplier>::new());
    let reload_nonce = RwSignal::new(0_u64);

    let catalog_products = RwSignal::new(Vec::<Product>::new());

    let open_tabs = RwSignal::new(Vec::<SupplierTab>::new());
    let active_tab_id = RwSignal::new(Option::<String>::None);
    let fetch_generation = StoredValue::new(0_u64);
    let next_tab_instance_id = StoredValue::new(1_u64);
    let alloc_instance_id = move || {
        next_tab_instance_id
            .try_update_value(|n| {
                let id = *n;
                *n += 1;
                id
            })
            .unwrap_or(0)
    };

    let fetch_suppliers =
        move |connection: ConnectionMode, params: ListSuppliersParams, only_inactive: bool| {
            let req_gen = fetch_generation
                .try_update_value(|g| {
                    *g += 1;
                    *g
                })
                .unwrap_or(0);
            loading.set(true);
            error.set(None);
            spawn_local(async move {
                let res = match live_client(&connection) {
                    Ok(client) => client.list_suppliers(&params).await,
                    Err(err) => Err(err),
                };
                if fetch_generation.try_get_value() != Some(req_gen) {
                    return;
                }
                match res {
                    Ok(mut list) => {
                        if only_inactive {
                            list.retain(|s| !s.active);
                        }
                        items.set(list);
                        loading.set(false);
                    }
                    Err(err) => {
                        loading.set(false);
                        error.set(Some(err.user_message()));
                    }
                }
            });
        };

    // Load active products once per session to populate the supplier price picker.
    Effect::new(move |_| {
        let Some(session) = ctx.session.get() else {
            catalog_products.set(Vec::new());
            return;
        };
        let connection = session.connection;
        spawn_local(async move {
            let params = ListProductsParams::new().active(true).limit(200);
            if let Ok(page) = WebApiClient.list_products(&connection, &params).await {
                catalog_products.set(page.items);
            }
        });
    });

    Effect::new(move |_| {
        let _ = reload_nonce.get();
        let active_session = ctx.session.get();
        let q = search.get();
        let af = active_filter.get();

        // Invalidate any in-flight list request whenever session or filters re-run.
        fetch_generation.try_update_value(|g| *g += 1);

        let Some(session) = active_session else {
            loading.set(false);
            items.set(Vec::new());
            error.set(None);
            open_tabs.set(Vec::new());
            active_tab_id.set(None);
            return;
        };

        let (active_only, only_inactive) = match af.as_str() {
            "active" => (Some(true), false),
            "inactive" => (None, true),
            _ => (None, false),
        };
        let params = ListSuppliersParams {
            active_only,
            q: (!q.trim().is_empty()).then_some(q),
        };
        fetch_suppliers(session.connection, params, only_inactive);
    });

    let is_signed_in = Memo::new(move |_| ctx.session.with(|s| s.is_some()));

    let load_supplier_products =
        move |connection: ConnectionMode, tab_id: String, instance_id: u64, supplier_id: Uuid| {
            let mut prod_gen = 0_u64;
            update_supplier_tab_instance(&open_tabs, &tab_id, instance_id, |tab| {
                tab.products_generation += 1;
                prod_gen = tab.products_generation;
                tab.products_loading = true;
                tab.products_error = None;
            });
            if prod_gen == 0 {
                return;
            }
            spawn_local(async move {
                let res = match live_client(&connection) {
                    Ok(client) => client.list_supplier_products(supplier_id).await,
                    Err(err) => Err(err),
                };
                update_supplier_tab_instance(&open_tabs, &tab_id, instance_id, |tab| {
                    if tab.products_generation != prod_gen {
                        return;
                    }
                    tab.products_loading = false;
                    match res {
                        Ok(list) => {
                            tab.products = list;
                            tab.products_loaded = true;
                            tab.products_error = None;
                        }
                        Err(err) => {
                            tab.products_error = Some(err.user_message());
                        }
                    }
                });
            });
        };

    let on_create_click = move |_| {
        open_tabs.update(|list| {
            if !list.iter().any(|t| t.tab_id == "new") {
                list.push(SupplierTab::new_draft(alloc_instance_id()));
            }
        });
        active_tab_id.set(Some("new".to_string()));
    };

    let open_supplier_row = move |supplier: Supplier| {
        let tab_id = format!("edit:{}", supplier.id);
        let mut tab_instance_id = open_tabs.with_untracked(|list| {
            list.iter()
                .find(|t| t.tab_id == tab_id)
                .map(|t| t.instance_id)
        });
        if tab_instance_id.is_none() {
            let instance_id = alloc_instance_id();
            open_tabs.update(|list| {
                list.push(SupplierTab::from_supplier(&supplier, true, instance_id));
            });
            tab_instance_id = Some(instance_id);
        }
        let Some(tab_instance_id) = tab_instance_id else {
            return;
        };
        active_tab_id.set(Some(tab_id.clone()));

        if let Some(session) = ctx.session.get_untracked() {
            let connection = session.connection;
            let supplier_id = supplier.id;
            let detail_connection = connection.clone();
            let detail_tab_id = tab_id.clone();
            spawn_local(async move {
                let res = match live_client(&detail_connection) {
                    Ok(client) => client.get_supplier(supplier_id).await,
                    Err(err) => Err(err),
                };
                match res {
                    Ok(fresh) => {
                        update_supplier_tab_instance(
                            &open_tabs,
                            &detail_tab_id,
                            tab_instance_id,
                            |tab| {
                                if !tab.dirty {
                                    tab.apply_saved(&fresh, None);
                                } else {
                                    tab.loading_detail = false;
                                }
                            },
                        );
                    }
                    Err(err) => {
                        update_supplier_tab_instance(
                            &open_tabs,
                            &detail_tab_id,
                            tab_instance_id,
                            |tab| {
                                tab.loading_detail = false;
                                if tab.error.is_none() {
                                    tab.error = Some(err.user_message());
                                }
                            },
                        );
                    }
                }
            });

            load_supplier_products(connection, tab_id, tab_instance_id, supplier_id);
        }
    };

    view! {
        <div data-target="suppliers-page">
            <div class="tc-page-header">
                <div>
                    <h1 class="tc-page-title">"Suppliers"</h1>
                    <p class="tc-page-subtitle" data-target="suppliers-total">
                        {move || format!("Purchasing directory ({} shown)", items.with(Vec::len))}
                    </p>
                </div>
                <div class="tc-header-actions">
                    <button
                        type="button"
                        data-target="suppliers-create"
                        class="tc-btn tc-btn-primary"
                        disabled=move || !is_signed_in.get()
                        on:click=on_create_click
                    >
                        "+ New Supplier"
                    </button>
                    <button
                        type="button"
                        data-target="suppliers-refresh"
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
                            "Sign in to load suppliers from GET /api/v1/suppliers."
                        </p>
                        <A href=crate::components::shell::app_href("/login") attr:class="tc-btn tc-btn-primary" attr:data-target="suppliers-go-login">
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
                                data-target="suppliers-search"
                                class="tc-input"
                                style="min-width: 240px;"
                                type="search"
                                placeholder="Search code, name, email or contact..."
                                prop:value=move || search.get()
                                on:input=move |ev| search.set(event_target_value(&ev))
                            />
                            <select
                                data-target="suppliers-active-filter"
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
                            <div class="tc-alert-error" style="margin-bottom: var(--space-md);" role="alert" data-target="suppliers-error">
                                {msg}
                            </div>
                        })}

                        <div class="tc-table-wrap">
                            <table class="tc-table" data-target="suppliers-table">
                                <thead>
                                    <tr>
                                        <th>"Code"</th>
                                        <th>"Name"</th>
                                        <th>"Contact"</th>
                                        <th>"Country"</th>
                                        <th>"Currency"</th>
                                        <th>"Terms"</th>
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
                                                        "Loading suppliers..."
                                                    } else {
                                                        "No suppliers match the current filter."
                                                    }}
                                                </td>
                                            </tr>
                                        }
                                    >
                                        <For
                                            each=move || items.get()
                                            key=|s| (s.id, s.code.clone(), s.name.clone(), s.active, s.currency.clone())
                                            children=move |supplier| {
                                                let open_supplier = supplier.clone();
                                                let open_supplier_btn = supplier.clone();
                                                let row_tab_id = format!("edit:{}", supplier.id);
                                                let row_target = if supplier.code.trim().is_empty() {
                                                    format!("supplier-row-{}", supplier.id)
                                                } else {
                                                    format!("supplier-row-{}", supplier.code)
                                                };
                                                let code_label = if supplier.code.trim().is_empty() {
                                                    "—".to_string()
                                                } else {
                                                    supplier.code.clone()
                                                };
                                                let aria_label = format!("Open supplier {}", supplier.name);
                                                let contact_label = if supplier.contact_person.trim().is_empty() {
                                                    if supplier.email.trim().is_empty() {
                                                        "—".to_string()
                                                    } else {
                                                        supplier.email.clone()
                                                    }
                                                } else {
                                                    supplier.contact_person.clone()
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
                                                        title="Open supplier detail & product prices"
                                                        on:click=move |_| open_supplier_row(open_supplier.clone())
                                                    >
                                                        <td class="tc-mono">
                                                            <button
                                                                type="button"
                                                                class="tc-inline-tab-btn"
                                                                style="text-align: left;"
                                                                aria-label=aria_label
                                                                on:click=move |ev| {
                                                                    ev.stop_propagation();
                                                                    open_supplier_row(open_supplier_btn.clone());
                                                                }
                                                            >
                                                                {code_label}
                                                            </button>
                                                        </td>
                                                        <td>{supplier.name}</td>
                                                        <td>{contact_label}</td>
                                                        <td>{supplier.country}</td>
                                                        <td class="tc-mono">{supplier.currency}</td>
                                                        <td class="tc-mono">{format!("{}d", supplier.payment_terms_days)}</td>
                                                        <td>
                                                            {if supplier.active {
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
                        let tab_id_sv = StoredValue::new(current_tab_id.clone());

                        let on_submit = move |ev: SubmitEvent| {
                            ev.prevent_default();
                            let Some(session) = ctx.session.get_untracked() else {
                                return;
                            };
                            let current_id = tab_id_sv.get_value();
                            let Some(snapshot) = read_supplier_tab(&open_tabs, &current_id, Clone::clone) else {
                                return;
                            };
                            if snapshot.saving {
                                return;
                            }

                            let create_or_update = match snapshot.supplier_id {
                                Some(id) => snapshot.to_update_request().map(|req| (Some(id), None, Some(req))),
                                None => snapshot.to_create_request().map(|req| (None, Some(req), None)),
                            };
                            let (supplier_id, create_req, update_req) = match create_or_update {
                                Ok(parsed) => parsed,
                                Err(msg) => {
                                    update_supplier_tab(&open_tabs, &current_id, |tab| {
                                        tab.error = Some(msg);
                                        tab.notice = None;
                                    });
                                    return;
                                }
                            };

                            update_supplier_tab(&open_tabs, &current_id, |tab| {
                                tab.saving = true;
                                tab.error = None;
                                tab.notice = None;
                            });

                            let tab_instance_id = snapshot.instance_id;
                            let snapshot_edit_gen = snapshot.edit_generation;
                            let connection = session.connection;
                            spawn_local(async move {
                                let res = match live_client(&connection) {
                                    Ok(client) => match (supplier_id, create_req, update_req) {
                                        (Some(id), _, Some(ref req)) => client.update_supplier(id, req).await,
                                        (None, Some(ref req), _) => client.create_supplier(req).await,
                                        _ => unreachable!(),
                                    },
                                    Err(err) => Err(err),
                                };
                                match res {
                                    Ok(saved) => {
                                        let next_id = format!("edit:{}", saved.id);
                                        let mut updated_matching_tab = false;
                                        open_tabs.update(|list| {
                                            let has_match = list.iter().any(|t| {
                                                t.tab_id == current_id && t.instance_id == tab_instance_id
                                            });
                                            if !has_match {
                                                return;
                                            }
                                            if current_id != next_id {
                                                list.retain(|t| t.tab_id != next_id);
                                            }
                                            if let Some(tab) = list.iter_mut().find(|t| {
                                                t.tab_id == current_id && t.instance_id == tab_instance_id
                                            }) {
                                                if tab.edit_generation == snapshot_edit_gen {
                                                    tab.apply_saved(&saved, Some("Saved".to_string()));
                                                } else {
                                                    tab.apply_saved_preserving_edits(
                                                        &saved,
                                                        Some("Saved".to_string()),
                                                    );
                                                }
                                                updated_matching_tab = true;
                                            }
                                        });
                                        if updated_matching_tab
                                            && active_tab_id.get_untracked().as_deref()
                                                == Some(current_id.as_str())
                                        {
                                            active_tab_id.set(Some(next_id));
                                        }
                                        reload_nonce.update(|n| *n += 1);
                                    }
                                    Err(err) => {
                                        update_supplier_tab_instance(
                                            &open_tabs,
                                            &current_id,
                                            tab_instance_id,
                                            |tab| {
                                                tab.saving = false;
                                                tab.error = Some(err.user_message());
                                            },
                                        );
                                    }
                                }
                            });
                        };

                        let on_price_submit = move |ev: SubmitEvent| {
                            ev.prevent_default();
                            let Some(session) = ctx.session.get_untracked() else {
                                return;
                            };
                            let tid = tab_id_sv.get_value();
                            let Some(snapshot) = read_supplier_tab(&open_tabs, &tid, Clone::clone) else {
                                return;
                            };
                            let Some(supplier_id) = snapshot.supplier_id else {
                                return;
                            };
                            if snapshot.price_saving {
                                return;
                            }
                            let (product_id, req) = match snapshot.to_price_request() {
                                Ok(parsed) => parsed,
                                Err(msg) => {
                                    update_supplier_tab(&open_tabs, &tid, |tab| {
                                        tab.products_error = Some(msg);
                                        tab.notice = None;
                                    });
                                    return;
                                }
                            };

                            update_supplier_tab(&open_tabs, &tid, |tab| {
                                tab.price_saving = true;
                                tab.products_error = None;
                                tab.notice = None;
                            });

                            let tab_instance_id = snapshot.instance_id;
                            let connection = session.connection;
                            spawn_local(async move {
                                let res = match live_client(&connection) {
                                    Ok(client) => {
                                        client.set_supplier_product(supplier_id, product_id, &req).await
                                    }
                                    Err(err) => Err(err),
                                };
                                update_supplier_tab_instance(
                                    &open_tabs,
                                    &tid,
                                    tab_instance_id,
                                    |tab| {
                                        tab.price_saving = false;
                                        match res {
                                            Ok(saved) => {
                                                if let Some(existing) = tab
                                                    .products
                                                    .iter_mut()
                                                    .find(|p| p.product_id == saved.product_id)
                                                {
                                                    *existing = saved;
                                                } else {
                                                    tab.products.push(saved);
                                                }
                                                tab.products_loaded = true;
                                                tab.price_form_open = false;
                                                tab.products_error = None;
                                                tab.notice = Some("Supplier price saved.".to_string());
                                            }
                                            Err(err) => {
                                                tab.products_error = Some(err.user_message());
                                            }
                                        }
                                    },
                                );
                            });
                        };

                        view! {
                            <aside class="tc-card tc-detail-drawer" data-target="supplier-detail-drawer">
                                <div class="tc-inline-tabs" data-target="supplier-detail-tabs">
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
                                                        on:click=move |_| close_supplier_tab(&open_tabs, &active_tab_id, &close_id)
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
                                                tab_id_sv.with_value(|tid| {
                                                    read_supplier_tab(&open_tabs, tid, |t| t.title.clone())
                                                })
                                                .unwrap_or_else(|| "Supplier".to_string())
                                            }}
                                        </h2>
                                        <p class="tc-page-subtitle tc-mono">
                                            {move || {
                                                tab_id_sv.with_value(|tid| {
                                                    read_supplier_tab(&open_tabs, tid, |t| {
                                                        match t.supplier_id {
                                                            Some(id) if t.loading_detail => format!("{id} (loading...)"),
                                                            Some(id) => id.to_string(),
                                                            None => "POST /api/v1/suppliers".to_string(),
                                                        }
                                                    })
                                                })
                                                .unwrap_or_default()
                                            }}
                                        </p>
                                    </div>
                                </div>

                                {move || {
                                    tab_id_sv.with_value(|tid| {
                                        read_supplier_tab(&open_tabs, tid, |t| t.error.clone())
                                    })
                                    .flatten()
                                    .map(|msg| view! {
                                        <div class="tc-alert-error" role="alert" data-target="supplier-form-error">
                                            {msg}
                                        </div>
                                    })
                                }}

                                {move || {
                                    tab_id_sv.with_value(|tid| {
                                        read_supplier_tab(&open_tabs, tid, |t| t.notice.clone())
                                    })
                                    .flatten()
                                    .map(|msg| view! {
                                        <div class="tc-alert-success" role="status" data-target="supplier-form-notice">
                                            {msg}
                                        </div>
                                    })
                                }}

                                <div class="tc-inline-tabs" data-target="supplier-drawer-subtabs">
                                    {
                                        [
                                            (DrawerSection::Details, "Details", "supplier-tab-details"),
                                            (DrawerSection::Products, "Products & Prices", "supplier-tab-products"),
                                        ]
                                        .into_iter()
                                        .map(|(sec, label, target)| {
                                            view! {
                                                <button
                                                    type="button"
                                                    data-target=target
                                                    class=move || {
                                                        let active = tab_id_sv
                                                            .with_value(|tid| read_supplier_tab(&open_tabs, tid, |t| t.section == sec))
                                                            .unwrap_or(false);
                                                        if active {
                                                            "tc-inline-tab tc-inline-tab-active"
                                                        } else {
                                                            "tc-inline-tab"
                                                        }
                                                    }
                                                    on:click=move |_| {
                                                        let tid = tab_id_sv.get_value();
                                                        let mut should_load: Option<(u64, Uuid)> = None;
                                                        update_supplier_tab(&open_tabs, &tid, |t| {
                                                            t.section = sec;
                                                            if sec == DrawerSection::Products
                                                                && !t.products_loaded
                                                                && !t.products_loading
                                                            {
                                                                if let Some(sid) = t.supplier_id {
                                                                    should_load = Some((t.instance_id, sid));
                                                                }
                                                            }
                                                        });
                                                        if let Some((inst_id, sid)) = should_load {
                                                            if let Some(session) = ctx.session.get_untracked() {
                                                                load_supplier_products(
                                                                    session.connection,
                                                                    tid,
                                                                    inst_id,
                                                                    sid,
                                                                );
                                                            }
                                                        }
                                                    }
                                                >
                                                    {label}
                                                </button>
                                            }
                                        })
                                        .collect_view()
                                    }
                                </div>

                                {move || {
                                    let section = tab_id_sv
                                        .with_value(|tid| read_supplier_tab(&open_tabs, tid, |t| t.section))
                                        .unwrap_or(DrawerSection::Details);
                                    let tid_for_fields = tab_id_sv.get_value();
                                    match section {
                                        DrawerSection::Details => view! {
                                            <form data-target="supplier-form" on:submit=on_submit style="display: flex; flex-direction: column; gap: var(--space-md);">
                                                <div class="tc-form-grid">
                                                    {supplier_text_field(&open_tabs, &tid_for_fields, "Code", "supplier-form-code", "SUP-001", false, true, |t| t.code.clone(), |t, v| t.code = v)}
                                                    {supplier_text_field(&open_tabs, &tid_for_fields, "Country *", "supplier-form-country", "BE", false, true, |t| t.country.clone(), |t, v| t.country = v)}
                                                    {supplier_text_field(&open_tabs, &tid_for_fields, "Name *", "supplier-form-name", "Nordic Components GmbH", true, true, |t| t.name.clone(), |t, v| t.name = v)}
                                                    {supplier_text_field(&open_tabs, &tid_for_fields, "Currency", "supplier-form-currency", "EUR", false, true, |t| t.currency.clone(), |t, v| t.currency = v)}
                                                    {supplier_text_field(&open_tabs, &tid_for_fields, "Payment terms (days)", "supplier-form-payment-terms", "30", false, true, |t| t.payment_terms_days.clone(), |t, v| t.payment_terms_days = v)}
                                                    {supplier_text_field(&open_tabs, &tid_for_fields, "Contact person", "supplier-form-contact-person", "Jan Weber", false, true, |t| t.contact_person.clone(), |t, v| t.contact_person = v)}
                                                    {supplier_text_field(&open_tabs, &tid_for_fields, "Tax / VAT ID", "supplier-form-tax-id", "BE0412345678", false, true, |t| t.tax_id.clone(), |t, v| t.tax_id = v)}
                                                    {supplier_text_field(&open_tabs, &tid_for_fields, "Email", "supplier-form-email", "purchasing@example.com", false, true, |t| t.email.clone(), |t, v| t.email = v)}
                                                    {supplier_text_field(&open_tabs, &tid_for_fields, "Phone", "supplier-form-phone", "+32 3 555 01 00", false, true, |t| t.phone.clone(), |t, v| t.phone = v)}

                                                    <div class="tc-field tc-form-span-2">
                                                        <label class="tc-label" for="supplier-form-notes">"Notes"</label>
                                                        <textarea
                                                            id="supplier-form-notes"
                                                            data-target="supplier-form-notes"
                                                            class="tc-input"
                                                            rows="3"
                                                            placeholder="Internal purchasing notes..."
                                                            prop:value=move || {
                                                                tab_id_sv
                                                                    .with_value(|tid| read_supplier_tab(&open_tabs, tid, |t| t.notes.clone()))
                                                                    .unwrap_or_default()
                                                            }
                                                            on:input=move |ev| {
                                                                let val = event_target_value(&ev);
                                                                tab_id_sv.with_value(|tid| {
                                                                    update_supplier_tab(&open_tabs, tid, |t| {
                                                                        t.notes = val;
                                                                        t.mark_dirty();
                                                                    });
                                                                });
                                                            }
                                                        />
                                                    </div>
                                                </div>

                                                <Show when=move || {
                                                    tab_id_sv
                                                        .with_value(|tid| read_supplier_tab(&open_tabs, tid, |t| t.supplier_id.is_some()))
                                                        .unwrap_or(false)
                                                }>
                                                    <label class="tc-checkbox-row" for="supplier-form-active">
                                                        <input
                                                            id="supplier-form-active"
                                                            data-target="supplier-form-active"
                                                            type="checkbox"
                                                            prop:checked=move || {
                                                                tab_id_sv
                                                                    .with_value(|tid| read_supplier_tab(&open_tabs, tid, |t| t.active))
                                                                    .unwrap_or(true)
                                                            }
                                                            on:change=move |ev| {
                                                                let checked = event_target_checked(&ev);
                                                                tab_id_sv.with_value(|tid| {
                                                                    update_supplier_tab(&open_tabs, tid, |t| {
                                                                        t.active = checked;
                                                                        t.mark_dirty();
                                                                    });
                                                                });
                                                            }
                                                        />
                                                        <span>"Active"</span>
                                                    </label>
                                                </Show>

                                                <div class="tc-form-actions">
                                                    <button
                                                        type="button"
                                                        data-target="supplier-form-cancel"
                                                        class="tc-btn"
                                                        on:click=move |_| {
                                                            tab_id_sv.with_value(|tid| close_supplier_tab(&open_tabs, &active_tab_id, tid));
                                                        }
                                                    >
                                                        "Cancel"
                                                    </button>
                                                    <button
                                                        type="submit"
                                                        data-target="supplier-form-save"
                                                        class="tc-btn tc-btn-primary"
                                                        disabled=move || {
                                                            tab_id_sv
                                                                .with_value(|tid| read_supplier_tab(&open_tabs, tid, |t| t.saving))
                                                                .unwrap_or(false)
                                                        }
                                                    >
                                                        {move || {
                                                            if tab_id_sv
                                                                .with_value(|tid| read_supplier_tab(&open_tabs, tid, |t| t.saving))
                                                                .unwrap_or(false)
                                                            {
                                                                "Saving..."
                                                            } else {
                                                                "Save"
                                                            }
                                                        }}
                                                    </button>
                                                </div>
                                            </form>
                                        }.into_any(),
                                        DrawerSection::Products => {
                                            view! {
                                                <div data-target="supplier-products-panel" style="display: flex; flex-direction: column; gap: var(--space-md);">
                                                    <Show
                                                        when=move || {
                                                            tab_id_sv
                                                                .with_value(|tid| read_supplier_tab(&open_tabs, tid, |t| t.supplier_id.is_some()))
                                                                .unwrap_or(false)
                                                        }
                                                        fallback=|| view! {
                                                            <div style="font-size: 13px; color: var(--on-surface-variant);">
                                                                "Save the supplier details first before adding product prices."
                                                            </div>
                                                        }
                                                    >
                                                        <div style="display: flex; justify-content: space-between; align-items: center; gap: var(--space-sm);">
                                                            <span style="font-size: 12px; color: var(--on-surface-variant);">
                                                                "Supplier price list entries"
                                                            </span>
                                                            <button
                                                                type="button"
                                                                data-target="supplier-price-add"
                                                                class="tc-btn tc-btn-sm tc-btn-primary"
                                                                on:click=move |_| {
                                                                    let default_pid = catalog_products
                                                                        .with_untracked(|list| list.first().map(|p| p.id.to_string()))
                                                                        .unwrap_or_default();
                                                                    tab_id_sv.with_value(|tid| {
                                                                        update_supplier_tab(&open_tabs, tid, |t| {
                                                                            t.reset_price_form(&default_pid);
                                                                        });
                                                                    });
                                                                }
                                                            >
                                                                "+ Add Price"
                                                            </button>
                                                        </div>

                                                        {move || {
                                                            tab_id_sv
                                                                .with_value(|tid| read_supplier_tab(&open_tabs, tid, |t| t.products_error.clone()))
                                                                .flatten()
                                                                .map(|msg| view! {
                                                                    <div class="tc-alert-error" role="alert" data-target="supplier-products-error">
                                                                        {msg}
                                                                    </div>
                                                                })
                                                        }}

                                                        <div class="tc-table-wrap" data-target="supplier-products-table">
                                                            <table class="tc-table">
                                                                <thead>
                                                                    <tr>
                                                                        <th>"Product"</th>
                                                                        <th class="tc-num">"Price"</th>
                                                                        <th class="tc-num">"MOQ"</th>
                                                                        <th class="tc-num">"Lead"</th>
                                                                        <th>""</th>
                                                                    </tr>
                                                                </thead>
                                                                <tbody>
                                                                    {move || {
                                                                        let state = tab_id_sv.with_value(|tid| {
                                                                            read_supplier_tab(&open_tabs, tid, |t| {
                                                                                (t.products_loading, t.products.clone())
                                                                            })
                                                                        });
                                                                        let Some((prod_loading, products)) = state else {
                                                                            return view! { <tr><td colspan="5"></td></tr> }.into_any();
                                                                        };
                                                                        if prod_loading && products.is_empty() {
                                                                            return view! {
                                                                                <tr>
                                                                                    <td colspan="5" style="text-align: center; color: var(--on-surface-variant);">
                                                                                        "Loading supplier prices..."
                                                                                    </td>
                                                                                </tr>
                                                                            }.into_any();
                                                                        }
                                                                        if products.is_empty() {
                                                                            return view! {
                                                                                <tr>
                                                                                    <td colspan="5" style="text-align: center; color: var(--on-surface-variant);">
                                                                                        "No product prices configured yet."
                                                                                    </td>
                                                                                </tr>
                                                                            }.into_any();
                                                                        }
                                                                        products.into_iter().map(|entry| {
                                                                            let edit_entry = entry.clone();
                                                                            let row_target = format!("supplier-product-row-{}", entry.product_code);
                                                                            view! {
                                                                                <tr data-target=row_target>
                                                                                    <td>
                                                                                        <div class="tc-mono">{entry.product_code}</div>
                                                                                        <div style="font-size: 11px; color: var(--on-surface-variant);">
                                                                                            {entry.product_name}
                                                                                            {if entry.is_preferred { " · Preferred" } else { "" }}
                                                                                        </div>
                                                                                    </td>
                                                                                    <td class="tc-num tc-mono">{format!("{} {}", entry.unit_price, entry.currency)}</td>
                                                                                    <td class="tc-num tc-mono">{entry.moq.to_string()}</td>
                                                                                    <td class="tc-num tc-mono">{format!("{}d", entry.lead_time_days)}</td>
                                                                                    <td>
                                                                                        <button
                                                                                            type="button"
                                                                                            class="tc-btn tc-btn-sm"
                                                                                            on:click=move |_| {
                                                                                                tab_id_sv.with_value(|tid| {
                                                                                                    update_supplier_tab(&open_tabs, tid, |t| {
                                                                                                        t.populate_price_form(&edit_entry);
                                                                                                    });
                                                                                                });
                                                                                            }
                                                                                        >
                                                                                            "Edit"
                                                                                        </button>
                                                                                    </td>
                                                                                </tr>
                                                                            }
                                                                        }).collect_view().into_any()
                                                                    }}
                                                                </tbody>
                                                            </table>
                                                        </div>

                                                        <Show when=move || {
                                                            tab_id_sv
                                                                .with_value(|tid| read_supplier_tab(&open_tabs, tid, |t| t.price_form_open))
                                                                .unwrap_or(false)
                                                        }>
                                                            {
                                                                let tid_price_fields = tab_id_sv.get_value();
                                                                view! {
                                                                    <form
                                                                        data-target="supplier-price-form"
                                                                        class="tc-card"
                                                                        style="display: flex; flex-direction: column; gap: var(--space-md);"
                                                                        on:submit=on_price_submit
                                                                    >
                                                                        <div class="tc-form-grid">
                                                                            <Show when=move || !catalog_products.with(Vec::is_empty)>
                                                                                <div class="tc-field tc-form-span-2">
                                                                                    <label class="tc-label" for="supplier-price-product-select">"Product"</label>
                                                                                    <select
                                                                                        id="supplier-price-product-select"
                                                                                        data-target="supplier-price-product-select"
                                                                                        class="tc-select"
                                                                                        prop:value=move || {
                                                                                            tab_id_sv
                                                                                                .with_value(|tid| read_supplier_tab(&open_tabs, tid, |t| t.price_product_id.clone()))
                                                                                                .unwrap_or_default()
                                                                                        }
                                                                                        on:change=move |ev| {
                                                                                            let val = event_target_value(&ev);
                                                                                            tab_id_sv.with_value(|tid| {
                                                                                                update_supplier_tab(&open_tabs, tid, |t| {
                                                                                                    t.price_product_id = val;
                                                                                                });
                                                                                            });
                                                                                        }
                                                                                    >
                                                                                        <option value="">"Select product or enter UUID below..."</option>
                                                                                        {move || catalog_products.get().into_iter().map(|p| {
                                                                                            let pid = p.id.to_string();
                                                                                            let label = format!("{} · {}", p.code, p.name);
                                                                                            view! {
                                                                                                <option value=pid>{label}</option>
                                                                                            }
                                                                                        }).collect_view()}
                                                                                    </select>
                                                                                </div>
                                                                            </Show>

                                                                            {supplier_text_field(&open_tabs, &tid_price_fields, "Product ID *", "supplier-price-product-id", "01900000-0000-7000-8000-000000000000", true, false, |t| t.price_product_id.clone(), |t, v| t.price_product_id = v)}
                                                                            {supplier_text_field(&open_tabs, &tid_price_fields, "Unit price *", "supplier-price-unit-price", "12.50", false, false, |t| t.price_unit_price.clone(), |t, v| t.price_unit_price = v)}
                                                                            {supplier_text_field(&open_tabs, &tid_price_fields, "Currency", "supplier-price-currency", "EUR", false, false, |t| t.price_currency.clone(), |t, v| t.price_currency = v)}
                                                                            {supplier_text_field(&open_tabs, &tid_price_fields, "MOQ", "supplier-price-moq", "1", false, false, |t| t.price_moq.clone(), |t, v| t.price_moq = v)}
                                                                            {supplier_text_field(&open_tabs, &tid_price_fields, "Lead time (days)", "supplier-price-lead-time", "0", false, false, |t| t.price_lead_time_days.clone(), |t, v| t.price_lead_time_days = v)}
                                                                            {supplier_text_field(&open_tabs, &tid_price_fields, "Supplier SKU", "supplier-price-code", "SUP-SKU", false, false, |t| t.price_supplier_product_code.clone(), |t, v| t.price_supplier_product_code = v)}
                                                                            {supplier_text_field(&open_tabs, &tid_price_fields, "Supplier item name", "supplier-price-name", "Vendor product name", false, false, |t| t.price_supplier_product_name.clone(), |t, v| t.price_supplier_product_name = v)}
                                                                        </div>

                                                                        <label class="tc-checkbox-row" for="supplier-price-preferred">
                                                                            <input
                                                                                id="supplier-price-preferred"
                                                                                data-target="supplier-price-preferred"
                                                                                type="checkbox"
                                                                                prop:checked=move || {
                                                                                    tab_id_sv
                                                                                        .with_value(|tid| read_supplier_tab(&open_tabs, tid, |t| t.price_is_preferred))
                                                                                        .unwrap_or(false)
                                                                                }
                                                                                on:change=move |ev| {
                                                                                    let checked = event_target_checked(&ev);
                                                                                    tab_id_sv.with_value(|tid| {
                                                                                        update_supplier_tab(&open_tabs, tid, |t| {
                                                                                            t.price_is_preferred = checked;
                                                                                        });
                                                                                    });
                                                                                }
                                                                            />
                                                                            <span>"Preferred supplier for this product"</span>
                                                                        </label>

                                                                        <div class="tc-form-actions">
                                                                            <button
                                                                                type="button"
                                                                                data-target="supplier-price-cancel"
                                                                                class="tc-btn tc-btn-sm"
                                                                                on:click=move |_| {
                                                                                    tab_id_sv.with_value(|tid| {
                                                                                        update_supplier_tab(&open_tabs, tid, |t| {
                                                                                            t.price_form_open = false;
                                                                                        });
                                                                                    });
                                                                                }
                                                                            >
                                                                                "Cancel"
                                                                            </button>
                                                                            <button
                                                                                type="submit"
                                                                                data-target="supplier-price-save"
                                                                                class="tc-btn tc-btn-sm tc-btn-primary"
                                                                                disabled=move || {
                                                                                    tab_id_sv
                                                                                        .with_value(|tid| read_supplier_tab(&open_tabs, tid, |t| t.price_saving))
                                                                                        .unwrap_or(false)
                                                                                }
                                                                            >
                                                                                {move || {
                                                                                    if tab_id_sv
                                                                                        .with_value(|tid| read_supplier_tab(&open_tabs, tid, |t| t.price_saving))
                                                                                        .unwrap_or(false)
                                                                                    {
                                                                                        "Saving..."
                                                                                    } else {
                                                                                        "Save Price"
                                                                                    }
                                                                                }}
                                                                            </button>
                                                                        </div>
                                                                    </form>
                                                                }
                                                            }
                                                        </Show>
                                                    </Show>
                                                </div>
                                            }.into_any()
                                        }
                                    }
                                }}
                            </aside>
                        }
                    })}
                </div>
            </Show>
        </div>
    }
}

#[allow(clippy::too_many_arguments)]
fn supplier_text_field(
    tabs: &RwSignal<Vec<SupplierTab>>,
    tab_id: &str,
    label: &'static str,
    target: &'static str,
    placeholder: &'static str,
    span_two: bool,
    mark_dirty: bool,
    get: fn(&SupplierTab) -> String,
    set: fn(&mut SupplierTab, String),
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
                prop:value=move || read_supplier_tab(&tabs, &tid_read, get).unwrap_or_default()
                on:input=move |ev| {
                    let val = event_target_value(&ev);
                    update_supplier_tab(&tabs, &tid_write, |tab| {
                        set(tab, val);
                        if mark_dirty {
                            tab.mark_dirty();
                        }
                    });
                }
            />
        </div>
    }
}
