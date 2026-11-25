use leptos::ev::SubmitEvent;
use leptos::prelude::*;
use leptos::task::spawn_local;
use leptos_router::components::A;
use rust_decimal::Decimal;
use tradocraft_api_client::sales::{
    ConvertQuotationRequest, CreateQuotationRequest, ListQuotationsParams, Quotation,
    QuotationLine, QuotationLineInput, QuotationPage, QuotationStatus, QuotationSummary,
    UpdateQuotationRequest,
};
use tradocraft_api_client::{ApiError, Client};
use uuid::Uuid;

use crate::api::{
    resolve_base_url, ApiClient, ConnectionMode, Customer, ListCustomersParams, ListProductsParams,
    Product, WebApiClient,
};
use crate::pages::{opt_trimmed, parse_decimal, parse_i32, parse_opt_decimal, parse_uuid};
use crate::state::AppContext;

#[derive(Debug, Clone, PartialEq, Eq)]
struct QuotationLineDraft {
    key: u64,
    product_id: String,
    description: String,
    quantity: String,
    line_discount_percent: String,
    unit_price: String,
    vat_rate: String,
    customer_remark: String,
}

impl QuotationLineDraft {
    fn new_blank(key: u64, default_product_id: &str) -> Self {
        Self {
            key,
            product_id: default_product_id.to_string(),
            description: String::new(),
            quantity: "1".to_string(),
            line_discount_percent: "0".to_string(),
            unit_price: String::new(),
            vat_rate: String::new(),
            customer_remark: String::new(),
        }
    }

    fn from_line(key: u64, line: &QuotationLine) -> Self {
        Self {
            key,
            product_id: line.product_id.map(|id| id.to_string()).unwrap_or_default(),
            description: line.description.clone(),
            quantity: line.quantity.to_string(),
            line_discount_percent: line.line_discount_percent.to_string(),
            unit_price: if line.price_on_request && line.price_confirmed {
                line.list_unit_price.to_string()
            } else {
                String::new()
            },
            vat_rate: line.vat_rate.to_string(),
            customer_remark: line.customer_remark.clone(),
        }
    }

    fn to_input(&self, idx: usize) -> Result<QuotationLineInput, String> {
        let row = idx + 1;
        let product_id = parse_uuid(&format!("Line {row} product"), &self.product_id)?;
        let quantity = parse_decimal(
            &format!("Line {row} quantity"),
            &self.quantity,
            Decimal::ONE,
        )?;
        if quantity <= Decimal::ZERO {
            return Err(format!("Line {row} quantity must be greater than zero."));
        }
        let line_discount_percent = parse_decimal(
            &format!("Line {row} discount %"),
            &self.line_discount_percent,
            Decimal::ZERO,
        )?;
        let unit_price = parse_opt_decimal(&format!("Line {row} unit price"), &self.unit_price)?;
        let vat_rate = parse_opt_decimal(&format!("Line {row} VAT %"), &self.vat_rate)?;
        Ok(QuotationLineInput {
            product_id,
            description: opt_trimmed(&self.description),
            quantity,
            line_discount_percent,
            unit_price,
            vat_rate,
            customer_remark: self.customer_remark.trim().to_string(),
            ..QuotationLineInput::default()
        })
    }
}

#[derive(Debug, Clone, PartialEq)]
struct QuotationTab {
    instance_id: u64,
    tab_id: String,
    quotation_id: Option<Uuid>,
    version: Option<i64>,
    title: String,
    status: QuotationStatus,
    shipping_status: String,
    loading_detail: bool,
    busy: bool,
    dirty: bool,
    error: Option<String>,
    notice: Option<String>,
    customer_id: String,
    purpose: String,
    delivery_country_code: String,
    valid_days: String,
    quote_date: String,
    notes: String,
    override_shipping: bool,
    convert_reference: String,
    convert_notes: String,
    line_drafts: Vec<QuotationLineDraft>,
    next_line_key: u64,
    detail: Option<Quotation>,
}

impl QuotationTab {
    fn new_draft(instance_id: u64, default_customer_id: &str, default_product_id: &str) -> Self {
        Self {
            instance_id,
            tab_id: "new".to_string(),
            quotation_id: None,
            version: None,
            title: "New Quotation".to_string(),
            status: QuotationStatus::Draft,
            shipping_status: "not_required".to_string(),
            loading_detail: false,
            busy: false,
            dirty: false,
            error: None,
            notice: None,
            customer_id: default_customer_id.to_string(),
            purpose: "installation".to_string(),
            delivery_country_code: String::new(),
            valid_days: "30".to_string(),
            quote_date: String::new(),
            notes: String::new(),
            override_shipping: false,
            convert_reference: String::new(),
            convert_notes: String::new(),
            line_drafts: vec![QuotationLineDraft::new_blank(1, default_product_id)],
            next_line_key: 2,
            detail: None,
        }
    }

    fn from_summary(instance_id: u64, summary: &QuotationSummary, loading_detail: bool) -> Self {
        Self {
            instance_id,
            tab_id: format!("edit:{}", summary.id),
            quotation_id: Some(summary.id),
            version: None,
            title: format!("{} · {}", summary.number, summary.customer_name),
            status: summary.status,
            shipping_status: summary.shipping_status.clone(),
            loading_detail,
            busy: false,
            dirty: false,
            error: None,
            notice: None,
            customer_id: summary.customer_id.to_string(),
            purpose: summary.purpose.clone(),
            delivery_country_code: String::new(),
            valid_days: "30".to_string(),
            quote_date: summary.quote_date.to_string(),
            notes: String::new(),
            override_shipping: false,
            convert_reference: String::new(),
            convert_notes: String::new(),
            line_drafts: Vec::new(),
            next_line_key: 1,
            detail: None,
        }
    }

    fn apply_quotation(&mut self, q: &Quotation, notice: Option<String>) {
        let line_drafts: Vec<QuotationLineDraft> = q
            .lines
            .iter()
            .enumerate()
            .map(|(i, line)| QuotationLineDraft::from_line((i + 1) as u64, line))
            .collect();
        let next_key = (line_drafts.len() + 1) as u64;
        let valid_days = (q.valid_until - q.quote_date).num_days().clamp(1, 365);
        self.tab_id = format!("edit:{}", q.id);
        self.quotation_id = Some(q.id);
        self.version = Some(q.version);
        self.title = format!("{} (r{}) · {}", q.number, q.revision, q.customer_name);
        self.status = q.status;
        self.shipping_status = q.shipping_status.clone();
        self.loading_detail = false;
        self.busy = false;
        self.dirty = false;
        self.error = None;
        self.notice = notice;
        self.customer_id = q.customer_id.to_string();
        self.purpose = q.purpose.clone();
        self.delivery_country_code = q.delivery_country_code.clone().unwrap_or_default();
        self.valid_days = valid_days.to_string();
        self.quote_date = q.quote_date.to_string();
        self.notes = q.notes.clone();
        self.line_drafts = line_drafts;
        self.next_line_key = next_key;
        self.detail = Some(q.clone());
    }

    fn is_editable(&self) -> bool {
        self.quotation_id.is_none()
            || (self.status == QuotationStatus::Draft && self.detail.is_some())
    }

    fn can_edit(&self) -> bool {
        self.is_editable() && !self.busy
    }

    fn to_request(&self) -> Result<CreateQuotationRequest, String> {
        let customer_id = parse_uuid("Customer", &self.customer_id)?;
        if self.line_drafts.is_empty() {
            return Err("Add at least one line before saving the quotation.".to_string());
        }
        let mut lines = Vec::with_capacity(self.line_drafts.len());
        for (idx, draft) in self.line_drafts.iter().enumerate() {
            lines.push(draft.to_input(idx)?);
        }
        let delivery_country_code =
            opt_trimmed(&self.delivery_country_code).map(|code| code.to_ascii_uppercase());
        if let Some(ref cc) = delivery_country_code {
            if cc.len() != 2 {
                return Err("Delivery country must be a 2-letter ISO code (e.g. BE).".to_string());
            }
        }
        let quote_date = match opt_trimmed(&self.quote_date) {
            Some(raw) => Some(
                raw.parse()
                    .map_err(|_| "Quote date must be YYYY-MM-DD.".to_string())?,
            ),
            None => None,
        };
        let valid_days = if self.valid_days.trim().is_empty() {
            None
        } else {
            let days = parse_i32("Valid days", &self.valid_days, 30)?;
            if days <= 0 {
                return Err("Valid days must be positive.".to_string());
            }
            Some(i64::from(days))
        };

        Ok(UpdateQuotationRequest {
            customer_id,
            quote_date,
            valid_days,
            purpose: opt_trimmed(&self.purpose),
            delivery_country_code,
            notes: self.notes.trim().to_string(),
            expected_version: self.version,
            lines,
            ..CreateQuotationRequest::default()
        })
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
            "Sales endpoints require a live API connection; switch to Dev User or Bearer mode on the sign-in screen."
                .to_string(),
        )),
    }
}

fn read_quotation_tab<R>(
    tabs: &RwSignal<Vec<QuotationTab>>,
    tab_id: &str,
    f: impl FnOnce(&QuotationTab) -> R,
) -> Option<R> {
    tabs.with(|list| list.iter().find(|t| t.tab_id == tab_id).map(f))
}

fn update_quotation_tab(
    tabs: &RwSignal<Vec<QuotationTab>>,
    tab_id: &str,
    f: impl FnOnce(&mut QuotationTab),
) {
    tabs.update(|list| {
        if let Some(tab) = list.iter_mut().find(|t| t.tab_id == tab_id) {
            f(tab);
        }
    });
}

fn update_quotation_tab_by_instance(
    tabs: &RwSignal<Vec<QuotationTab>>,
    instance_id: u64,
    f: impl FnOnce(&mut QuotationTab),
) {
    tabs.update(|list| {
        if let Some(tab) = list.iter_mut().find(|t| t.instance_id == instance_id) {
            f(tab);
        }
    });
}

fn close_quotation_tab(
    tabs: &RwSignal<Vec<QuotationTab>>,
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

fn quotation_status_badge_class(status: QuotationStatus) -> &'static str {
    match status {
        QuotationStatus::Draft => "tc-badge",
        QuotationStatus::Sent => "tc-badge tc-badge-primary",
        QuotationStatus::Accepted => "tc-badge tc-badge-success",
        QuotationStatus::Rejected => "tc-badge tc-badge-error",
        QuotationStatus::Superseded => "tc-badge tc-badge-warning",
    }
}

#[component]
pub fn QuotationsPage() -> impl IntoView {
    let ctx = expect_context::<AppContext>();

    let search = RwSignal::new(String::new());
    let status_filter = RwSignal::new(String::new());

    let loading = RwSignal::new(false);
    let error = RwSignal::new(Option::<String>::None);
    let page_notice = RwSignal::new(Option::<String>::None);
    let items = RwSignal::new(Vec::<QuotationSummary>::new());
    let total = RwSignal::new(0_i64);
    let reload_nonce = RwSignal::new(0_u64);

    let customers = RwSignal::new(Vec::<Customer>::new());
    let products = RwSignal::new(Vec::<Product>::new());

    let open_tabs = RwSignal::new(Vec::<QuotationTab>::new());
    let active_tab_id = RwSignal::new(Option::<String>::None);
    let fetch_gen = StoredValue::new(0_u64);
    let next_tab_instance_id = StoredValue::new(0_u64);

    let alloc_tab_instance_id = move || {
        let id = next_tab_instance_id.get_value().wrapping_add(1);
        next_tab_instance_id.set_value(id);
        id
    };

    let fetch_quotations = move |connection: ConnectionMode, params: ListQuotationsParams| {
        let req_gen = fetch_gen.get_value().wrapping_add(1);
        fetch_gen.set_value(req_gen);
        loading.set(true);
        error.set(None);
        spawn_local(async move {
            let result: Result<QuotationPage, ApiError> = match live_client(&connection) {
                Ok(client) => client.list_quotations(&params).await,
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

    // Load lookup lists for the quotation builder whenever a live session starts.
    Effect::new(move |_| {
        let Some(session) = ctx.session.get() else {
            customers.set(Vec::new());
            products.set(Vec::new());
            return;
        };
        let connection = session.connection;
        spawn_local(async move {
            let cust_params = ListCustomersParams::new().active(true).limit(200);
            if let Ok(page) = WebApiClient.list_customers(&connection, &cust_params).await {
                customers.set(page.items);
            }
            let prod_params = ListProductsParams::new().active(true).limit(200);
            if let Ok(page) = WebApiClient.list_products(&connection, &prod_params).await {
                products.set(page.items);
            }
        });
    });

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
            page_notice.set(None);
            open_tabs.set(Vec::new());
            active_tab_id.set(None);
            return;
        };

        let params = ListQuotationsParams {
            q: (!q.trim().is_empty()).then_some(q),
            status: (!status.trim().is_empty()).then_some(status),
            limit: Some(50),
            offset: Some(0),
            ..ListQuotationsParams::default()
        };
        fetch_quotations(session.connection, params);
    });

    let is_signed_in = Memo::new(move |_| ctx.session.with(|s| s.is_some()));

    let on_create_click = move |_| {
        let default_customer = customers
            .with_untracked(|list| list.first().map(|c| c.id.to_string()))
            .unwrap_or_default();
        let default_product = products
            .with_untracked(|list| list.first().map(|p| p.id.to_string()))
            .unwrap_or_default();
        open_tabs.update(|list| {
            if !list.iter().any(|t| t.tab_id == "new") {
                let instance_id = alloc_tab_instance_id();
                list.push(QuotationTab::new_draft(
                    instance_id,
                    &default_customer,
                    &default_product,
                ));
            }
        });
        active_tab_id.set(Some("new".to_string()));
    };

    let open_quotation_row = move |summary: QuotationSummary| {
        let tab_id = format!("edit:{}", summary.id);
        let mut target_instance: Option<u64> = None;
        open_tabs.update(|list| {
            if let Some(tab) = list.iter_mut().find(|t| t.tab_id == tab_id) {
                if !tab.busy {
                    tab.loading_detail = true;
                    target_instance = Some(tab.instance_id);
                }
            } else {
                let instance_id = alloc_tab_instance_id();
                list.push(QuotationTab::from_summary(instance_id, &summary, true));
                target_instance = Some(instance_id);
            }
        });
        active_tab_id.set(Some(tab_id.clone()));

        let Some(instance_id) = target_instance else {
            return;
        };
        if let Some(session) = ctx.session.get_untracked() {
            let connection = session.connection;
            let quotation_id = summary.id;
            spawn_local(async move {
                let res = match live_client(&connection) {
                    Ok(client) => client.get_quotation(quotation_id).await,
                    Err(err) => Err(err),
                };
                match res {
                    Ok(fresh) => {
                        update_quotation_tab_by_instance(&open_tabs, instance_id, |tab| {
                            if tab.busy {
                                return;
                            }
                            if !tab.dirty {
                                tab.apply_quotation(&fresh, None);
                            } else {
                                tab.loading_detail = false;
                                if tab.version.is_none() {
                                    tab.version = Some(fresh.version);
                                }
                                tab.detail = Some(fresh);
                            }
                        });
                    }
                    Err(err) => {
                        update_quotation_tab_by_instance(&open_tabs, instance_id, |tab| {
                            if tab.busy {
                                return;
                            }
                            tab.loading_detail = false;
                            if tab.error.is_none() {
                                tab.error = Some(err.user_message());
                            }
                        });
                    }
                }
            });
        } else {
            update_quotation_tab_by_instance(&open_tabs, instance_id, |tab| {
                tab.loading_detail = false;
            });
        }
    };

    view! {
        <div data-target="quotations-page">
            <div class="tc-page-header">
                <div>
                    <h1 class="tc-page-title">"Quotations"</h1>
                    <p class="tc-page-subtitle" data-target="quotations-total">
                        {move || format!("Sales quotations ({} total)", total.get())}
                    </p>
                </div>
                <div class="tc-header-actions">
                    <button
                        type="button"
                        data-target="quotations-create"
                        class="tc-btn tc-btn-primary"
                        disabled=move || !is_signed_in.get()
                        on:click=on_create_click
                    >
                        "+ New Quotation"
                    </button>
                    <button
                        type="button"
                        data-target="quotations-refresh"
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
                            "Sign in to load quotations from GET /api/v1/quotations."
                        </p>
                        <A href=crate::components::shell::app_href("/login") attr:class="tc-btn tc-btn-primary" attr:data-target="quotations-go-login">
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
                                data-target="quotations-search"
                                class="tc-input"
                                style="min-width: 240px;"
                                type="search"
                                placeholder="Search number or customer..."
                                prop:value=move || search.get()
                                on:input=move |ev| search.set(event_target_value(&ev))
                            />
                            <select
                                data-target="quotations-status-filter"
                                class="tc-select"
                                prop:value=move || status_filter.get()
                                on:change=move |ev| status_filter.set(event_target_value(&ev))
                            >
                                <option value="">"All statuses"</option>
                                <option value="draft">"Draft"</option>
                                <option value="sent">"Sent"</option>
                                <option value="accepted">"Accepted"</option>
                                <option value="rejected">"Rejected"</option>
                                <option value="superseded">"Superseded"</option>
                            </select>
                        </div>

                        {move || error.get().map(|msg| view! {
                            <div class="tc-alert-error" style="margin-bottom: var(--space-md);" role="alert" data-target="quotations-error">
                                {msg}
                            </div>
                        })}

                        {move || page_notice.get().map(|msg| view! {
                            <div class="tc-alert-success" style="margin-bottom: var(--space-md);" role="status" data-target="quotations-notice">
                                {msg}
                            </div>
                        })}

                        <div class="tc-table-wrap">
                            <table class="tc-table" data-target="quotations-table">
                                <thead>
                                    <tr>
                                        <th>"Number"</th>
                                        <th>"Customer"</th>
                                        <th>"Quote date"</th>
                                        <th>"Valid until"</th>
                                        <th>"Purpose"</th>
                                        <th>"Shipping"</th>
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
                                                        "Loading quotations..."
                                                    } else {
                                                        "No quotations match the current filter."
                                                    }}
                                                </td>
                                            </tr>
                                        }
                                    >
                                        <For
                                            each=move || items.get()
                                            key=|q| (q.id, q.revision, q.status.as_str(), q.total)
                                            children=move |summary| {
                                                let open_summary = summary.clone();
                                                let row_tab_id = format!("edit:{}", summary.id);
                                                let row_target = format!("quotation-row-{}", summary.number);
                                                let badge_class = quotation_status_badge_class(summary.status);
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
                                                        title="Open quotation detail & lines"
                                                        on:click=move |_| open_quotation_row(open_summary.clone())
                                                    >
                                                        <td class="tc-mono">{format!("{} r{}", summary.number, summary.revision)}</td>
                                                        <td>{summary.customer_name}</td>
                                                        <td class="tc-mono">{summary.quote_date.to_string()}</td>
                                                        <td class="tc-mono">{summary.valid_until.to_string()}</td>
                                                        <td>{summary.purpose}</td>
                                                        <td>{summary.shipping_status}</td>
                                                        <td class="tc-num tc-mono">{format!("{} {}", summary.total, summary.currency)}</td>
                                                        <td><span class=badge_class>{summary.status.as_str()}</span></td>
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
                        let tab_id_submit = current_tab_id.clone();
                        let tab_id_send = current_tab_id.clone();
                        let tab_id_accept = current_tab_id.clone();
                        let tab_id_convert = current_tab_id.clone();
                        let tab_id_cancel = current_tab_id.clone();
                        let tab_id_header = current_tab_id.clone();
                        let tab_id_subtitle = current_tab_id.clone();
                        let tab_id_error = current_tab_id.clone();
                        let tab_id_notice = current_tab_id.clone();
                        let tab_id_status = current_tab_id.clone();
                        let tab_id_editable = current_tab_id.clone();
                        let tab_id_lines_ro = current_tab_id.clone();
                        let tab_id_lines_edit = current_tab_id.clone();
                        let tab_id_totals = current_tab_id.clone();
                        let tab_id_convert_ui = current_tab_id.clone();
                        let tab_id_ship_override = current_tab_id.clone();
                        let tab_id_actions = current_tab_id.clone();

                        let on_save = move |ev: SubmitEvent| {
                            ev.prevent_default();
                            let Some(session) = ctx.session.get_untracked() else {
                                return;
                            };
                            let Some(snapshot) = read_quotation_tab(&open_tabs, &tab_id_submit, Clone::clone) else {
                                return;
                            };
                            if snapshot.busy || !snapshot.is_editable() {
                                return;
                            }
                            let instance_id = snapshot.instance_id;
                            let req = match snapshot.to_request() {
                                Ok(req) => req,
                                Err(msg) => {
                                    update_quotation_tab_by_instance(&open_tabs, instance_id, |tab| {
                                        tab.error = Some(msg);
                                        tab.notice = None;
                                    });
                                    return;
                                }
                            };

                            update_quotation_tab_by_instance(&open_tabs, instance_id, |tab| {
                                tab.busy = true;
                                tab.error = None;
                                tab.notice = None;
                            });

                            let current_id = tab_id_submit.clone();
                            let connection = session.connection;
                            let quotation_id = snapshot.quotation_id;
                            spawn_local(async move {
                                let res = match live_client(&connection) {
                                    Ok(client) => match quotation_id {
                                        Some(id) => client.update_quotation(id, &req).await,
                                        None => client.create_quotation(&req).await,
                                    },
                                    Err(err) => Err(err),
                                };
                                match res {
                                    Ok(saved) => {
                                        let next_id = format!("edit:{}", saved.id);
                                        let mut updated_current_tab = false;
                                        open_tabs.update(|list| {
                                            if list.iter().any(|t| t.instance_id == instance_id) {
                                                list.retain(|t| t.instance_id == instance_id || t.tab_id != next_id);
                                                if let Some(tab) = list.iter_mut().find(|t| t.instance_id == instance_id) {
                                                    tab.apply_quotation(&saved, Some("Quotation saved.".to_string()));
                                                    updated_current_tab = true;
                                                }
                                            }
                                        });
                                        if updated_current_tab
                                            && active_tab_id.get_untracked().as_deref() == Some(current_id.as_str())
                                        {
                                            active_tab_id.set(Some(next_id));
                                        }
                                        reload_nonce.update(|n| *n += 1);
                                    }
                                    Err(err) => {
                                        update_quotation_tab_by_instance(&open_tabs, instance_id, |tab| {
                                            tab.busy = false;
                                            tab.error = Some(err.user_message());
                                        });
                                    }
                                }
                            });
                        };

                        let on_send = move |_| {
                            let Some(session) = ctx.session.get_untracked() else {
                                return;
                            };
                            let Some(snapshot) = read_quotation_tab(&open_tabs, &tab_id_send, Clone::clone) else {
                                return;
                            };
                            let Some(qid) = snapshot.quotation_id else {
                                return;
                            };
                            if snapshot.busy || snapshot.detail.is_none() {
                                return;
                            }
                            let instance_id = snapshot.instance_id;
                            if snapshot.dirty {
                                update_quotation_tab_by_instance(&open_tabs, instance_id, |tab| {
                                    tab.error = Some("Save changes before sending the quotation.".to_string());
                                    tab.notice = None;
                                });
                                return;
                            }
                            update_quotation_tab_by_instance(&open_tabs, instance_id, |tab| {
                                tab.busy = true;
                                tab.error = None;
                                tab.notice = None;
                            });
                            let connection = session.connection;
                            let override_shipping = snapshot.override_shipping;
                            spawn_local(async move {
                                let res = match live_client(&connection) {
                                    Ok(client) => client.send_quotation(qid, override_shipping).await,
                                    Err(err) => Err(err),
                                };
                                match res {
                                    Ok(updated) => {
                                        update_quotation_tab_by_instance(&open_tabs, instance_id, |tab| {
                                            tab.apply_quotation(&updated, Some("Quotation sent.".to_string()));
                                        });
                                        reload_nonce.update(|n| *n += 1);
                                    }
                                    Err(err) => {
                                        update_quotation_tab_by_instance(&open_tabs, instance_id, |tab| {
                                            tab.busy = false;
                                            tab.error = Some(err.user_message());
                                        });
                                    }
                                }
                            });
                        };

                        let on_accept = move |_| {
                            let Some(session) = ctx.session.get_untracked() else {
                                return;
                            };
                            let Some(snapshot) = read_quotation_tab(&open_tabs, &tab_id_accept, Clone::clone) else {
                                return;
                            };
                            let Some(qid) = snapshot.quotation_id else {
                                return;
                            };
                            if snapshot.busy {
                                return;
                            }
                            let instance_id = snapshot.instance_id;
                            update_quotation_tab_by_instance(&open_tabs, instance_id, |tab| {
                                tab.busy = true;
                                tab.error = None;
                                tab.notice = None;
                            });
                            let connection = session.connection;
                            spawn_local(async move {
                                let res = match live_client(&connection) {
                                    Ok(client) => client.accept_quotation(qid).await,
                                    Err(err) => Err(err),
                                };
                                match res {
                                    Ok(updated) => {
                                        update_quotation_tab_by_instance(&open_tabs, instance_id, |tab| {
                                            tab.apply_quotation(&updated, Some("Quotation accepted.".to_string()));
                                        });
                                        reload_nonce.update(|n| *n += 1);
                                    }
                                    Err(err) => {
                                        update_quotation_tab_by_instance(&open_tabs, instance_id, |tab| {
                                            tab.busy = false;
                                            tab.error = Some(err.user_message());
                                        });
                                    }
                                }
                            });
                        };

                        let on_convert = move |_| {
                            let Some(session) = ctx.session.get_untracked() else {
                                return;
                            };
                            let Some(snapshot) = read_quotation_tab(&open_tabs, &tab_id_convert, Clone::clone) else {
                                return;
                            };
                            let Some(qid) = snapshot.quotation_id else {
                                return;
                            };
                            if snapshot.busy {
                                return;
                            }
                            let instance_id = snapshot.instance_id;
                            update_quotation_tab_by_instance(&open_tabs, instance_id, |tab| {
                                tab.busy = true;
                                tab.error = None;
                                tab.notice = None;
                            });
                            let req = ConvertQuotationRequest {
                                customer_reference: snapshot.convert_reference.trim().to_string(),
                                notes: snapshot.convert_notes.trim().to_string(),
                            };
                            let connection = session.connection;
                            spawn_local(async move {
                                let res = match live_client(&connection) {
                                    Ok(client) => client.convert_quotation(qid, &req).await,
                                    Err(err) => Err(err),
                                };
                                match res {
                                    Ok(order) => {
                                        let msg = format!(
                                            "Converted to sales order {} (rev {}).",
                                            order.order.number, order.revision
                                        );
                                        update_quotation_tab_by_instance(&open_tabs, instance_id, |tab| {
                                            tab.busy = false;
                                            tab.notice = Some(msg.clone());
                                        });
                                        page_notice.set(Some(msg));
                                        reload_nonce.update(|n| *n += 1);
                                    }
                                    Err(err) => {
                                        update_quotation_tab_by_instance(&open_tabs, instance_id, |tab| {
                                            tab.busy = false;
                                            tab.error = Some(err.user_message());
                                        });
                                    }
                                }
                            });
                        };

                        view! {
                            <aside class="tc-card tc-detail-drawer" data-target="quotation-detail-drawer">
                                <div class="tc-inline-tabs" data-target="quotation-detail-tabs">
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
                                                        on:click=move |_| close_quotation_tab(&open_tabs, &active_tab_id, &close_id)
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
                                                read_quotation_tab(&open_tabs, &tab_id_header, |t| t.title.clone())
                                                    .unwrap_or_else(|| "Quotation".to_string())
                                            }}
                                        </h2>
                                        <p class="tc-page-subtitle tc-mono">
                                            {move || {
                                                read_quotation_tab(&open_tabs, &tab_id_subtitle, |t| {
                                                    match (t.quotation_id, t.version) {
                                                        (Some(id), Some(v)) if t.loading_detail => format!("{id} · v{v} (loading...)"),
                                                        (Some(id), Some(v)) => format!("{id} · v{v}"),
                                                        (Some(id), None) => id.to_string(),
                                                        (None, _) => "POST /api/v1/quotations".to_string(),
                                                    }
                                                })
                                                .unwrap_or_default()
                                            }}
                                        </p>
                                    </div>
                                    {move || read_quotation_tab(&open_tabs, &tab_id_status, |t| t.status).map(|st| {
                                        view! { <span class=quotation_status_badge_class(st)>{st.as_str()}</span> }
                                    })}
                                </div>

                                {move || {
                                    read_quotation_tab(&open_tabs, &tab_id_error, |t| t.error.clone())
                                        .flatten()
                                        .map(|msg| view! {
                                            <div class="tc-alert-error" role="alert" data-target="quotation-form-error">
                                                {msg}
                                            </div>
                                        })
                                }}

                                {move || {
                                    read_quotation_tab(&open_tabs, &tab_id_notice, |t| t.notice.clone())
                                        .flatten()
                                        .map(|msg| view! {
                                            <div class="tc-alert-success" role="status" data-target="quotation-form-notice">
                                                {msg}
                                            </div>
                                        })
                                }}

                                <form data-target="quotation-form" on:submit=on_save style="display: flex; flex-direction: column; gap: var(--space-md);">
                                    <div class="tc-form-grid">
                                        <div class="tc-field tc-form-span-2">
                                            <label class="tc-label" for="quotation-form-customer">"Customer *"</label>
                                            <Show
                                                when=move || !customers.with(Vec::is_empty)
                                                fallback=move || {
                                                    view! {
                                                        <input
                                                            id="quotation-form-customer"
                                                            data-target="quotation-form-customer"
                                                            class="tc-input tc-mono"
                                                            type="text"
                                                            placeholder="Customer UUID"
                                                            disabled=move || !tab_id_sv.with_value(|tid| read_quotation_tab(&open_tabs, tid, QuotationTab::can_edit).unwrap_or(false))
                                                            prop:value=move || tab_id_sv.with_value(|tid| read_quotation_tab(&open_tabs, tid, |t| t.customer_id.clone()).unwrap_or_default())
                                                            on:input=move |ev| {
                                                                let v = event_target_value(&ev);
                                                                tab_id_sv.with_value(|tid| {
                                                                    update_quotation_tab(&open_tabs, tid, |t| {
                                                                        if !t.can_edit() {
                                                                            return;
                                                                        }
                                                                        t.customer_id = v;
                                                                        t.dirty = true;
                                                                    });
                                                                });
                                                            }
                                                        />
                                                    }
                                                }
                                            >
                                                <select
                                                    id="quotation-form-customer"
                                                    data-target="quotation-form-customer"
                                                    class="tc-select"
                                                    disabled=move || !tab_id_sv.with_value(|tid| read_quotation_tab(&open_tabs, tid, QuotationTab::can_edit).unwrap_or(false))
                                                    prop:value=move || tab_id_sv.with_value(|tid| read_quotation_tab(&open_tabs, tid, |t| t.customer_id.clone()).unwrap_or_default())
                                                    on:change=move |ev| {
                                                        let v = event_target_value(&ev);
                                                        tab_id_sv.with_value(|tid| {
                                                            update_quotation_tab(&open_tabs, tid, |t| {
                                                                if !t.can_edit() {
                                                                    return;
                                                                }
                                                                t.customer_id = v;
                                                                t.dirty = true;
                                                            });
                                                        });
                                                    }
                                                >
                                                    <option value="">"Select customer..."</option>
                                                    {move || customers.get().into_iter().map(|c| {
                                                        let id = c.id.to_string();
                                                        let label = format!("{} · {}", c.code, c.name);
                                                        view! { <option value=id>{label}</option> }
                                                    }).collect_view()}
                                                </select>
                                            </Show>
                                        </div>

                                        {quotation_select_field(
                                            &open_tabs,
                                            &current_tab_id,
                                            "Purpose",
                                            "quotation-form-purpose",
                                            &[("installation", "Installation"), ("stock", "Stock")],
                                            |t| t.purpose.clone(),
                                            |t, v| t.purpose = v,
                                        )}
                                        {quotation_text_field(
                                            &open_tabs,
                                            &current_tab_id,
                                            "Delivery country",
                                            "quotation-form-delivery-country",
                                            "BE (optional)",
                                            false,
                                            |t| t.delivery_country_code.clone(),
                                            |t, v| t.delivery_country_code = v,
                                        )}
                                        {quotation_text_field(
                                            &open_tabs,
                                            &current_tab_id,
                                            "Quote date",
                                            "quotation-form-quote-date",
                                            "YYYY-MM-DD",
                                            false,
                                            |t| t.quote_date.clone(),
                                            |t, v| t.quote_date = v,
                                        )}
                                        {quotation_text_field(
                                            &open_tabs,
                                            &current_tab_id,
                                            "Valid days",
                                            "quotation-form-valid-days",
                                            "30",
                                            false,
                                            |t| t.valid_days.clone(),
                                            |t, v| t.valid_days = v,
                                        )}
                                        {quotation_text_field(
                                            &open_tabs,
                                            &current_tab_id,
                                            "Notes",
                                            "quotation-form-notes",
                                            "Quotation notes",
                                            true,
                                            |t| t.notes.clone(),
                                            |t, v| t.notes = v,
                                        )}
                                    </div>

                                    <div style="display: flex; align-items: center; justify-content: space-between;">
                                        <span class="tc-label">"Lines"</span>
                                        <Show when=move || read_quotation_tab(&open_tabs, &tab_id_editable, QuotationTab::is_editable).unwrap_or(false)>
                                            <button
                                                type="button"
                                                data-target="quotation-add-line"
                                                class="tc-btn tc-btn-sm"
                                                disabled=move || !tab_id_sv.with_value(|tid| read_quotation_tab(&open_tabs, tid, QuotationTab::can_edit).unwrap_or(false))
                                                on:click=move |_| {
                                                    let default_prod = products
                                                        .with_untracked(|list| list.first().map(|p| p.id.to_string()))
                                                        .unwrap_or_default();
                                                    tab_id_sv.with_value(|tid| {
                                                        update_quotation_tab(&open_tabs, tid, |tab| {
                                                            if !tab.can_edit() {
                                                                return;
                                                            }
                                                            let key = tab.next_line_key;
                                                            tab.next_line_key += 1;
                                                            tab.line_drafts.push(QuotationLineDraft::new_blank(key, &default_prod));
                                                            tab.dirty = true;
                                                        });
                                                    });
                                                }
                                            >
                                                "+ Add Line"
                                            </button>
                                        </Show>
                                    </div>

                                    {move || {
                                        let editable = read_quotation_tab(&open_tabs, &tab_id_lines_edit, QuotationTab::is_editable).unwrap_or(false);
                                        if editable {
                                            let tid_list = tab_id_lines_edit.clone();
                                            let tid_item = tab_id_lines_edit.clone();
                                            view! {
                                                <div style="display: flex; flex-direction: column; gap: var(--space-sm);" data-target="quotation-lines-editor">
                                                    <For
                                                        each=move || {
                                                            read_quotation_tab(&open_tabs, &tid_list, |t| t.line_drafts.clone())
                                                                .unwrap_or_default()
                                                        }
                                                        key=|line| line.key
                                                        children=move |line| {
                                                            let line_key = line.key;
                                                            let tid = tid_item.clone();
                                                            view! {
                                                                <div class="tc-card" style="padding: var(--space-sm); display: flex; flex-direction: column; gap: var(--space-xs);">
                                                                    <div class="tc-form-grid">
                                                                        <div class="tc-field tc-form-span-2">
                                                                            <label class="tc-label">"Product *"</label>
                                                                            <Show
                                                                                when=move || !products.with(Vec::is_empty)
                                                                                fallback=move || {
                                                                                    view! {
                                                                                        <input
                                                                                            class="tc-input tc-mono"
                                                                                            type="text"
                                                                                            placeholder="Product UUID"
                                                                                            disabled=move || !tab_id_sv.with_value(|tid_d| read_quotation_tab(&open_tabs, tid_d, QuotationTab::can_edit).unwrap_or(false))
                                                                                            prop:value=move || {
                                                                                                tab_id_sv.with_value(|tid_r| {
                                                                                                    read_quotation_tab(&open_tabs, tid_r, |t| {
                                                                                                        t.line_drafts.iter().find(|l| l.key == line_key).map(|l| l.product_id.clone()).unwrap_or_default()
                                                                                                    }).unwrap_or_default()
                                                                                                })
                                                                                            }
                                                                                            on:input=move |ev| {
                                                                                                let v = event_target_value(&ev);
                                                                                                tab_id_sv.with_value(|tid_w| {
                                                                                                    update_quotation_tab(&open_tabs, tid_w, |t| {
                                                                                                        if !t.can_edit() {
                                                                                                            return;
                                                                                                        }
                                                                                                        if let Some(l) = t.line_drafts.iter_mut().find(|l| l.key == line_key) {
                                                                                                            l.product_id = v;
                                                                                                        }
                                                                                                        t.dirty = true;
                                                                                                    });
                                                                                                });
                                                                                            }
                                                                                        />
                                                                                    }
                                                                                }
                                                                            >
                                                                                <select
                                                                                    class="tc-select"
                                                                                    disabled=move || !tab_id_sv.with_value(|tid_d| read_quotation_tab(&open_tabs, tid_d, QuotationTab::can_edit).unwrap_or(false))
                                                                                    prop:value=move || {
                                                                                        tab_id_sv.with_value(|tid_r| {
                                                                                            read_quotation_tab(&open_tabs, tid_r, |t| {
                                                                                                t.line_drafts.iter().find(|l| l.key == line_key).map(|l| l.product_id.clone()).unwrap_or_default()
                                                                                            }).unwrap_or_default()
                                                                                        })
                                                                                    }
                                                                                    on:change=move |ev| {
                                                                                        let v = event_target_value(&ev);
                                                                                        tab_id_sv.with_value(|tid_w| {
                                                                                            update_quotation_tab(&open_tabs, tid_w, |t| {
                                                                                                if !t.can_edit() {
                                                                                                    return;
                                                                                                }
                                                                                                if let Some(l) = t.line_drafts.iter_mut().find(|l| l.key == line_key) {
                                                                                                    l.product_id = v;
                                                                                                }
                                                                                                t.dirty = true;
                                                                                            });
                                                                                        });
                                                                                    }
                                                                                >
                                                                                    <option value="">"Select product..."</option>
                                                                                    {move || products.get().into_iter().map(|p| {
                                                                                        let id = p.id.to_string();
                                                                                        let label = format!("{} · {}", p.code, p.name);
                                                                                        view! { <option value=id>{label}</option> }
                                                                                    }).collect_view()}
                                                                                </select>
                                                                            </Show>
                                                                        </div>

                                                                        <div class="tc-field">
                                                                            <label class="tc-label">"Qty *"</label>
                                                                            <input
                                                                                class="tc-input tc-num"
                                                                                type="text"
                                                                                disabled={
                                                                                    let tid_d = tid.clone();
                                                                                    move || !read_quotation_tab(&open_tabs, &tid_d, QuotationTab::can_edit).unwrap_or(false)
                                                                                }
                                                                                prop:value={
                                                                                    let tid_r = tid.clone();
                                                                                    move || read_quotation_tab(&open_tabs, &tid_r, |t| {
                                                                                        t.line_drafts.iter().find(|l| l.key == line_key).map(|l| l.quantity.clone()).unwrap_or_default()
                                                                                    }).unwrap_or_default()
                                                                                }
                                                                                on:input={
                                                                                    let tid_w = tid.clone();
                                                                                    move |ev| {
                                                                                        let v = event_target_value(&ev);
                                                                                        update_quotation_tab(&open_tabs, &tid_w, |t| {
                                                                                            if !t.can_edit() {
                                                                                                return;
                                                                                            }
                                                                                            if let Some(l) = t.line_drafts.iter_mut().find(|l| l.key == line_key) {
                                                                                                l.quantity = v;
                                                                                            }
                                                                                            t.dirty = true;
                                                                                        });
                                                                                    }
                                                                                }
                                                                            />
                                                                        </div>

                                                                        <div class="tc-field">
                                                                            <label class="tc-label">"Discount %"</label>
                                                                            <input
                                                                                class="tc-input tc-num"
                                                                                type="text"
                                                                                disabled={
                                                                                    let tid_d = tid.clone();
                                                                                    move || !read_quotation_tab(&open_tabs, &tid_d, QuotationTab::can_edit).unwrap_or(false)
                                                                                }
                                                                                prop:value={
                                                                                    let tid_r = tid.clone();
                                                                                    move || read_quotation_tab(&open_tabs, &tid_r, |t| {
                                                                                        t.line_drafts.iter().find(|l| l.key == line_key).map(|l| l.line_discount_percent.clone()).unwrap_or_default()
                                                                                    }).unwrap_or_default()
                                                                                }
                                                                                on:input={
                                                                                    let tid_w = tid.clone();
                                                                                    move |ev| {
                                                                                        let v = event_target_value(&ev);
                                                                                        update_quotation_tab(&open_tabs, &tid_w, |t| {
                                                                                            if !t.can_edit() {
                                                                                                return;
                                                                                            }
                                                                                            if let Some(l) = t.line_drafts.iter_mut().find(|l| l.key == line_key) {
                                                                                                l.line_discount_percent = v;
                                                                                            }
                                                                                            t.dirty = true;
                                                                                        });
                                                                                    }
                                                                                }
                                                                            />
                                                                        </div>

                                                                        <div class="tc-field tc-form-span-2">
                                                                            <label class="tc-label">"Description override"</label>
                                                                            <input
                                                                                class="tc-input"
                                                                                type="text"
                                                                                placeholder="Optional custom description"
                                                                                disabled={
                                                                                    let tid_d = tid.clone();
                                                                                    move || !read_quotation_tab(&open_tabs, &tid_d, QuotationTab::can_edit).unwrap_or(false)
                                                                                }
                                                                                prop:value={
                                                                                    let tid_r = tid.clone();
                                                                                    move || read_quotation_tab(&open_tabs, &tid_r, |t| {
                                                                                        t.line_drafts.iter().find(|l| l.key == line_key).map(|l| l.description.clone()).unwrap_or_default()
                                                                                    }).unwrap_or_default()
                                                                                }
                                                                                on:input={
                                                                                    let tid_w = tid.clone();
                                                                                    move |ev| {
                                                                                        let v = event_target_value(&ev);
                                                                                        update_quotation_tab(&open_tabs, &tid_w, |t| {
                                                                                            if !t.can_edit() {
                                                                                                return;
                                                                                            }
                                                                                            if let Some(l) = t.line_drafts.iter_mut().find(|l| l.key == line_key) {
                                                                                                l.description = v;
                                                                                            }
                                                                                            t.dirty = true;
                                                                                        });
                                                                                    }
                                                                                }
                                                                            />
                                                                        </div>
                                                                    </div>

                                                                    <div style="display: flex; justify-content: flex-end;">
                                                                        <button
                                                                            type="button"
                                                                            class="tc-btn tc-btn-ghost tc-btn-sm"
                                                                            disabled={
                                                                                let tid_d = tid.clone();
                                                                                move || !read_quotation_tab(&open_tabs, &tid_d, QuotationTab::can_edit).unwrap_or(false)
                                                                            }
                                                                            on:click={
                                                                                let tid_rm = tid.clone();
                                                                                move |_| {
                                                                                    update_quotation_tab(&open_tabs, &tid_rm, |t| {
                                                                                        if !t.can_edit() {
                                                                                            return;
                                                                                        }
                                                                                        t.line_drafts.retain(|l| l.key != line_key);
                                                                                        t.dirty = true;
                                                                                    });
                                                                                }
                                                                            }
                                                                        >
                                                                            "Remove line"
                                                                        </button>
                                                                    </div>
                                                                </div>
                                                            }
                                                        }
                                                    />
                                                </div>
                                            }.into_any()
                                        } else {
                                            let detail_lines = read_quotation_tab(&open_tabs, &tab_id_lines_ro, |t| {
                                                t.detail.as_ref().map(|d| d.lines.clone()).unwrap_or_default()
                                            })
                                            .unwrap_or_default();
                                            view! {
                                                <div class="tc-table-wrap" data-target="quotation-lines-table">
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
                                                            {detail_lines.into_iter().map(|line| view! {
                                                                <tr>
                                                                    <td class="tc-mono">{line.position}</td>
                                                                    <td>
                                                                        <div class="tc-mono">{line.product_code}</div>
                                                                        <div style="font-size: 11px; color: var(--on-surface-variant);">{line.description}</div>
                                                                    </td>
                                                                    <td class="tc-num tc-mono">{format!("{} {}", line.quantity, line.unit)}</td>
                                                                    <td class="tc-num tc-mono">{line.net_unit_price.to_string()}</td>
                                                                    <td class="tc-num tc-mono">{line.line_total.to_string()}</td>
                                                                </tr>
                                                            }).collect_view()}
                                                        </tbody>
                                                    </table>
                                                </div>
                                            }.into_any()
                                        }
                                    }}

                                    {move || read_quotation_tab(&open_tabs, &tab_id_totals, |t| t.detail.clone()).flatten().map(|d| view! {
                                        <div class="tc-card" style="padding: var(--space-sm); display: flex; justify-content: space-between; font-size: 12px;" data-target="quotation-totals">
                                            <span>{format!("Subtotal: {} {}", d.subtotal, d.currency)}</span>
                                            <span>{format!("VAT: {} {}", d.vat_total, d.currency)}</span>
                                            <strong>{format!("Total: {} {}", d.total, d.currency)}</strong>
                                        </div>
                                    })}

                                    <Show when=move || {
                                        read_quotation_tab(&open_tabs, &tab_id_ship_override, |t| {
                                            t.quotation_id.is_some()
                                                && t.status == QuotationStatus::Draft
                                                && t.shipping_status == "pending"
                                        })
                                        .unwrap_or(false)
                                    }>
                                        <label class="tc-checkbox-row" for="quotation-override-shipping">
                                            <input
                                                id="quotation-override-shipping"
                                                data-target="quotation-override-shipping"
                                                type="checkbox"
                                                disabled=move || !tab_id_sv.with_value(|tid| read_quotation_tab(&open_tabs, tid, QuotationTab::can_edit).unwrap_or(false))
                                                prop:checked=move || tab_id_sv.with_value(|tid| read_quotation_tab(&open_tabs, tid, |t| t.override_shipping).unwrap_or(false))
                                                on:change=move |ev| {
                                                    let checked = event_target_checked(&ev);
                                                    tab_id_sv.with_value(|tid| {
                                                        update_quotation_tab(&open_tabs, tid, |t| {
                                                            if !t.can_edit() {
                                                                return;
                                                            }
                                                            t.override_shipping = checked;
                                                        });
                                                    });
                                                }
                                            />
                                            <span>"Override pending shipping quote when sending"</span>
                                        </label>
                                    </Show>

                                    <Show when=move || {
                                        read_quotation_tab(&open_tabs, &tab_id_convert_ui, |t| {
                                            t.quotation_id.is_some()
                                                && matches!(t.status, QuotationStatus::Sent | QuotationStatus::Accepted)
                                        })
                                        .unwrap_or(false)
                                    }>
                                        {move || {
                                            let tid = tab_id_sv.get_value();
                                            view! {
                                                <div class="tc-form-grid">
                                                    {quotation_text_field_always_editable(
                                                        &open_tabs,
                                                        &tid,
                                                        "Customer PO reference",
                                                        "quotation-convert-ref",
                                                        "PO-2026-001",
                                                        false,
                                                        |t| t.convert_reference.clone(),
                                                        |t, v| t.convert_reference = v,
                                                    )}
                                                    {quotation_text_field_always_editable(
                                                        &open_tabs,
                                                        &tid,
                                                        "Order notes",
                                                        "quotation-convert-notes",
                                                        "Optional notes",
                                                        false,
                                                        |t| t.convert_notes.clone(),
                                                        |t, v| t.convert_notes = v,
                                                    )}
                                                </div>
                                            }
                                        }}
                                    </Show>

                                    <div class="tc-form-actions">
                                        <button
                                            type="button"
                                            data-target="quotation-cancel"
                                            class="tc-btn"
                                            on:click=move |_| close_quotation_tab(&open_tabs, &active_tab_id, &tab_id_cancel)
                                        >
                                            "Close"
                                        </button>

                                        {move || {
                                            let state = read_quotation_tab(&open_tabs, &tab_id_actions, |t| {
                                                (t.quotation_id.is_some(), t.status, t.busy, t.detail.is_some())
                                            });
                                            let Some((has_id, status, busy, has_detail)) = state else {
                                                return view! { <span></span> }.into_any();
                                            };
                                            let waiting_detail = has_id && !has_detail;
                                            view! {
                                                <>
                                                    {(!has_id || status == QuotationStatus::Draft).then(|| view! {
                                                        <button
                                                            type="submit"
                                                            data-target="quotation-save"
                                                            class="tc-btn tc-btn-primary"
                                                            disabled=busy || waiting_detail
                                                        >
                                                            {if busy { "Saving..." } else { "Save" }}
                                                        </button>
                                                    })}
                                                    {(has_id && status == QuotationStatus::Draft).then(|| view! {
                                                        <button
                                                            type="button"
                                                            data-target="quotation-send"
                                                            class="tc-btn"
                                                            disabled=busy || waiting_detail
                                                            on:click=on_send.clone()
                                                        >
                                                            "Send"
                                                        </button>
                                                    })}
                                                    {(has_id && status == QuotationStatus::Sent).then(|| view! {
                                                        <button
                                                            type="button"
                                                            data-target="quotation-accept"
                                                            class="tc-btn"
                                                            disabled=busy
                                                            on:click=on_accept.clone()
                                                        >
                                                            "Accept"
                                                        </button>
                                                    })}
                                                    {(has_id && matches!(status, QuotationStatus::Sent | QuotationStatus::Accepted)).then(|| view! {
                                                        <button
                                                            type="button"
                                                            data-target="quotation-convert"
                                                            class="tc-btn tc-btn-primary"
                                                            disabled=busy
                                                            on:click=on_convert.clone()
                                                        >
                                                            "Convert to Order"
                                                        </button>
                                                    })}
                                                </>
                                            }.into_any()
                                        }}
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
fn quotation_select_field(
    tabs: &RwSignal<Vec<QuotationTab>>,
    tab_id: &str,
    label: &'static str,
    target: &'static str,
    options: &'static [(&'static str, &'static str)],
    get: fn(&QuotationTab) -> String,
    set: fn(&mut QuotationTab, String),
) -> impl IntoView {
    let tabs = *tabs;
    let tid_read = tab_id.to_string();
    let tid_write = tab_id.to_string();
    let tid_dis = tab_id.to_string();
    view! {
        <div class="tc-field">
            <label class="tc-label" for=target>{label}</label>
            <select
                id=target
                data-target=target
                class="tc-select"
                disabled=move || !read_quotation_tab(&tabs, &tid_dis, QuotationTab::can_edit).unwrap_or(false)
                prop:value=move || read_quotation_tab(&tabs, &tid_read, get).unwrap_or_default()
                on:change=move |ev| {
                    let val = event_target_value(&ev);
                    update_quotation_tab(&tabs, &tid_write, |tab| {
                        if !tab.can_edit() {
                            return;
                        }
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
fn quotation_text_field(
    tabs: &RwSignal<Vec<QuotationTab>>,
    tab_id: &str,
    label: &'static str,
    target: &'static str,
    placeholder: &'static str,
    span_two: bool,
    get: fn(&QuotationTab) -> String,
    set: fn(&mut QuotationTab, String),
) -> impl IntoView {
    let tabs = *tabs;
    let tid_read = tab_id.to_string();
    let tid_write = tab_id.to_string();
    let tid_dis = tab_id.to_string();
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
                disabled=move || !read_quotation_tab(&tabs, &tid_dis, QuotationTab::can_edit).unwrap_or(false)
                prop:value=move || read_quotation_tab(&tabs, &tid_read, get).unwrap_or_default()
                on:input=move |ev| {
                    let val = event_target_value(&ev);
                    update_quotation_tab(&tabs, &tid_write, |tab| {
                        if !tab.can_edit() {
                            return;
                        }
                        set(tab, val);
                        tab.dirty = true;
                    });
                }
            />
        </div>
    }
}

#[allow(clippy::too_many_arguments)]
fn quotation_text_field_always_editable(
    tabs: &RwSignal<Vec<QuotationTab>>,
    tab_id: &str,
    label: &'static str,
    target: &'static str,
    placeholder: &'static str,
    span_two: bool,
    get: fn(&QuotationTab) -> String,
    set: fn(&mut QuotationTab, String),
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
                prop:value=move || read_quotation_tab(&tabs, &tid_read, get).unwrap_or_default()
                on:input=move |ev| {
                    let val = event_target_value(&ev);
                    update_quotation_tab(&tabs, &tid_write, |tab| {
                        set(tab, val);
                    });
                }
            />
        </div>
    }
}
