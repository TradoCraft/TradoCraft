use leptos::ev::SubmitEvent;
use leptos::prelude::*;
use leptos::task::spawn_local;
use leptos_router::components::A;
use uuid::Uuid;

use crate::api::{
    ApiClient, ConnectionMode, CreateProductRequest, ListProductsParams, Product,
    UpdateProductRequest, WebApiClient,
};
use crate::pages::{fmt_opt_display, opt_trimmed, parse_opt_decimal, parse_opt_i32};
use crate::state::AppContext;

#[derive(Debug, Clone, PartialEq, Eq)]
struct ProductTab {
    instance_id: u64,
    edit_generation: u64,
    tab_id: String,
    product_id: Option<Uuid>,
    title: String,
    loading_detail: bool,
    saving: bool,
    dirty: bool,
    error: Option<String>,
    notice: Option<String>,
    code: String,
    name: String,
    description: String,
    unit: String,
    product_type: String,
    vat_category: String,
    vat_rate_override: String,
    tracking: String,
    non_discountable: bool,
    price_on_request: bool,
    price_is_indicative: bool,
    active: bool,
    standard_cost: String,
    reorder_min: String,
    reorder_max: String,
    lead_time_days: String,
    barcode: String,
    default_production_remark: String,
    family_id: Option<Uuid>,
    packaging_category_id: Option<Uuid>,
    length_mm: Option<i32>,
    width_mm: Option<i32>,
    height_mm: Option<i32>,
    weight_g: Option<i32>,
    included_in_turnover: Option<Option<bool>>,
}

impl ProductTab {
    fn new_draft(instance_id: u64) -> Self {
        Self {
            instance_id,
            edit_generation: 0,
            tab_id: "new".to_string(),
            product_id: None,
            title: "New Product".to_string(),
            loading_detail: false,
            saving: false,
            dirty: false,
            error: None,
            notice: None,
            code: String::new(),
            name: String::new(),
            description: String::new(),
            unit: "pcs".to_string(),
            product_type: "purchased".to_string(),
            vat_category: "standard".to_string(),
            vat_rate_override: String::new(),
            tracking: "none".to_string(),
            non_discountable: false,
            price_on_request: false,
            price_is_indicative: false,
            active: true,
            standard_cost: String::new(),
            reorder_min: String::new(),
            reorder_max: String::new(),
            lead_time_days: String::new(),
            barcode: String::new(),
            default_production_remark: String::new(),
            family_id: None,
            packaging_category_id: None,
            length_mm: None,
            width_mm: None,
            height_mm: None,
            weight_g: None,
            included_in_turnover: None,
        }
    }

    fn from_product(p: &Product, loading_detail: bool, instance_id: u64) -> Self {
        Self {
            instance_id,
            edit_generation: 0,
            tab_id: format!("edit:{}", p.id),
            product_id: Some(p.id),
            title: format!("{} · {}", p.code, p.name),
            loading_detail,
            saving: false,
            dirty: false,
            error: None,
            notice: None,
            code: p.code.clone(),
            name: p.name.clone(),
            description: p.description.clone(),
            unit: p.unit.clone(),
            product_type: p.product_type.clone(),
            vat_category: if p.vat_category.trim().is_empty() {
                "standard".to_string()
            } else {
                p.vat_category.clone()
            },
            vat_rate_override: fmt_opt_display(p.vat_rate_override),
            tracking: p.tracking.clone(),
            non_discountable: p.non_discountable,
            price_on_request: p.price_on_request,
            price_is_indicative: p.price_is_indicative,
            active: p.active,
            standard_cost: fmt_opt_display(p.standard_cost),
            reorder_min: fmt_opt_display(p.reorder_min),
            reorder_max: fmt_opt_display(p.reorder_max),
            lead_time_days: fmt_opt_display(p.lead_time_days),
            barcode: p.barcode.clone().unwrap_or_default(),
            default_production_remark: p.default_production_remark.clone(),
            family_id: p.family_id,
            packaging_category_id: p.packaging_category_id,
            length_mm: p.length_mm,
            width_mm: p.width_mm,
            height_mm: p.height_mm,
            weight_g: p.weight_g,
            included_in_turnover: Some(p.included_in_turnover),
        }
    }

    fn mark_dirty(&mut self) {
        self.dirty = true;
        self.edit_generation += 1;
    }

    fn apply_saved(&mut self, saved: &Product, notice: Option<String>) {
        let mut updated = Self::from_product(saved, false, self.instance_id);
        updated.notice = notice;
        *self = updated;
    }

    fn apply_saved_preserving_edits(&mut self, saved: &Product, notice: Option<String>) {
        self.tab_id = format!("edit:{}", saved.id);
        self.product_id = Some(saved.id);
        self.title = format!("{} · {}", self.code, self.name);
        self.loading_detail = false;
        self.saving = false;
        self.dirty = true;
        self.error = None;
        self.notice = notice;
        self.family_id = saved.family_id;
        self.packaging_category_id = saved.packaging_category_id;
        self.length_mm = saved.length_mm;
        self.width_mm = saved.width_mm;
        self.height_mm = saved.height_mm;
        self.weight_g = saved.weight_g;
        self.included_in_turnover = Some(saved.included_in_turnover);
    }

    fn to_request(&self) -> Result<CreateProductRequest, String> {
        let code = self.code.trim();
        let name = self.name.trim();
        if code.is_empty() || name.is_empty() {
            return Err("Code and name are required.".to_string());
        }
        let unit = self.unit.trim();
        Ok(UpdateProductRequest {
            code: code.to_string(),
            name: name.to_string(),
            description: self.description.trim().to_string(),
            unit: if unit.is_empty() {
                "pcs".to_string()
            } else {
                unit.to_string()
            },
            product_type: self.product_type.clone(),
            vat_rate: None,
            vat_category: opt_trimmed(&self.vat_category),
            vat_rate_override: parse_opt_decimal("VAT rate override", &self.vat_rate_override)?,
            tracking: self.tracking.clone(),
            family_id: self.family_id,
            non_discountable: self.non_discountable,
            price_on_request: self.price_on_request,
            price_is_indicative: self.price_is_indicative,
            included_in_turnover: self.included_in_turnover,
            active: self.active,
            standard_cost: parse_opt_decimal("Standard cost", &self.standard_cost)?,
            reorder_min: parse_opt_decimal("Reorder min", &self.reorder_min)?,
            reorder_max: parse_opt_decimal("Reorder max", &self.reorder_max)?,
            order_multiple: None,
            safety_stock: None,
            lead_time_days: parse_opt_i32("Lead time (days)", &self.lead_time_days)?,
            barcode: opt_trimmed(&self.barcode),
            packaging_category_id: self.packaging_category_id,
            length_mm: self.length_mm,
            width_mm: self.width_mm,
            height_mm: self.height_mm,
            weight_g: self.weight_g,
            default_production_remark: self.default_production_remark.trim().to_string(),
        })
    }
}

fn read_product_tab<R>(
    tabs: &RwSignal<Vec<ProductTab>>,
    tab_id: &str,
    f: impl FnOnce(&ProductTab) -> R,
) -> Option<R> {
    tabs.with(|list| list.iter().find(|t| t.tab_id == tab_id).map(f))
}

fn update_product_tab(
    tabs: &RwSignal<Vec<ProductTab>>,
    tab_id: &str,
    f: impl FnOnce(&mut ProductTab),
) {
    tabs.update(|list| {
        if let Some(tab) = list.iter_mut().find(|t| t.tab_id == tab_id) {
            f(tab);
        }
    });
}

fn update_product_tab_instance(
    tabs: &RwSignal<Vec<ProductTab>>,
    tab_id: &str,
    instance_id: u64,
    f: impl FnOnce(&mut ProductTab),
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

fn close_product_tab(
    tabs: &RwSignal<Vec<ProductTab>>,
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
pub fn ProductsPage() -> impl IntoView {
    let ctx = expect_context::<AppContext>();

    let search = RwSignal::new(String::new());
    let product_type = RwSignal::new(String::new());
    let active_filter = RwSignal::new("all".to_string());

    let loading = RwSignal::new(false);
    let error = RwSignal::new(Option::<String>::None);
    let items = RwSignal::new(Vec::<Product>::new());
    let total = RwSignal::new(0_i64);
    let reload_nonce = RwSignal::new(0_u64);

    let open_tabs = RwSignal::new(Vec::<ProductTab>::new());
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

    let fetch_products = move |connection: ConnectionMode, params: ListProductsParams| {
        let req_gen = fetch_generation
            .try_update_value(|g| {
                *g += 1;
                *g
            })
            .unwrap_or(0);
        loading.set(true);
        error.set(None);
        spawn_local(async move {
            match WebApiClient.list_products(&connection, &params).await {
                Ok(page) => {
                    if fetch_generation.try_get_value() != Some(req_gen) {
                        return;
                    }
                    items.set(page.items);
                    total.set(page.total);
                    loading.set(false);
                }
                Err(err) => {
                    if fetch_generation.try_get_value() != Some(req_gen) {
                        return;
                    }
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
        let pt = product_type.get();
        let af = active_filter.get();

        // Invalidate any in-flight list request whenever session or filters re-run.
        fetch_generation.update_value(|g| *g += 1);

        let Some(session) = active_session else {
            loading.set(false);
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
        let params = ListProductsParams {
            q: (!q.trim().is_empty()).then_some(q),
            active,
            product_type: (!pt.trim().is_empty()).then_some(pt),
            limit: Some(50),
            offset: Some(0),
            ..ListProductsParams::default()
        };
        fetch_products(session.connection, params);
    });

    let is_signed_in = Memo::new(move |_| ctx.session.with(|s| s.is_some()));

    let on_create_click = move |_| {
        open_tabs.update(|list| {
            if !list.iter().any(|t| t.tab_id == "new") {
                list.push(ProductTab::new_draft(alloc_instance_id()));
            }
        });
        active_tab_id.set(Some("new".to_string()));
    };

    let open_product_row = move |product: Product| {
        let tab_id = format!("edit:{}", product.id);
        let mut tab_instance_id = open_tabs.with_untracked(|list| {
            list.iter()
                .find(|t| t.tab_id == tab_id)
                .map(|t| t.instance_id)
        });
        if tab_instance_id.is_none() {
            let instance_id = alloc_instance_id();
            open_tabs
                .update(|list| list.push(ProductTab::from_product(&product, true, instance_id)));
            tab_instance_id = Some(instance_id);
        }
        let Some(tab_instance_id) = tab_instance_id else {
            return;
        };
        active_tab_id.set(Some(tab_id.clone()));

        if let Some(session) = ctx.session.get_untracked() {
            let connection = session.connection;
            let product_id = product.id;
            spawn_local(async move {
                match WebApiClient.get_product(&connection, product_id).await {
                    Ok(fresh) => {
                        update_product_tab_instance(&open_tabs, &tab_id, tab_instance_id, |tab| {
                            if !tab.dirty {
                                tab.apply_saved(&fresh, None);
                            } else {
                                tab.loading_detail = false;
                            }
                        });
                    }
                    Err(err) => {
                        update_product_tab_instance(&open_tabs, &tab_id, tab_instance_id, |tab| {
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
        <div data-target="products-page">
            <div class="tc-page-header">
                <div>
                    <h1 class="tc-page-title">"Products"</h1>
                    <p class="tc-page-subtitle" data-target="products-total">
                        {move || format!("Master catalogue ({} total)", total.get())}
                    </p>
                </div>
                <div class="tc-header-actions">
                    <button
                        type="button"
                        data-target="products-create"
                        class="tc-btn tc-btn-primary"
                        disabled=move || !is_signed_in.get()
                        on:click=on_create_click
                    >
                        "+ New Product"
                    </button>
                    <button
                        type="button"
                        data-target="products-refresh"
                        class="tc-btn"
                        disabled=move || loading.get() || !is_signed_in.get()
                        on:click=move |_| reload_nonce.update(|n| *n += 1)
                    >
                        {move || if loading.get() { "Loading..." } else { "Refresh" }}
                    </button>
                    <Show when=move || is_signed_in.get()>
                        <super::product_tabs::ProductCsvActions reload=reload_nonce />
                    </Show>
                </div>
            </div>

            <Show
                when=move || is_signed_in.get()
                fallback=|| view! {
                    <div class="tc-card">
                        <p style="margin: 0 0 var(--space-md);">
                            "Sign in to load products from GET /api/v1/products (or pick Offline Mock on the sign-in screen)."
                        </p>
                        <A href=crate::components::shell::app_href("/login") attr:class="tc-btn tc-btn-primary" attr:data-target="products-go-login">
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
                                data-target="products-search"
                                class="tc-input"
                                style="min-width: 240px;"
                                type="search"
                                placeholder="Search code or name..."
                                prop:value=move || search.get()
                                on:input=move |ev| search.set(event_target_value(&ev))
                            />
                            <select
                                data-target="products-type-filter"
                                class="tc-select"
                                prop:value=move || product_type.get()
                                on:change=move |ev| product_type.set(event_target_value(&ev))
                            >
                                <option value="">"All types"</option>
                                <option value="purchased">"Purchased"</option>
                                <option value="manufactured">"Manufactured"</option>
                                <option value="configurable">"Configurable"</option>
                                <option value="service">"Service"</option>
                            </select>
                            <select
                                data-target="products-active-filter"
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
                            <div class="tc-alert-error" style="margin-bottom: var(--space-md);" role="alert" data-target="products-error">
                                {msg}
                            </div>
                        })}

                        <div class="tc-table-wrap">
                            <table class="tc-table" data-target="products-table">
                                <thead>
                                    <tr>
                                        <th>"Code"</th>
                                        <th>"Name"</th>
                                        <th>"Type"</th>
                                        <th>"Family"</th>
                                        <th>"Unit"</th>
                                        <th>"Tracking"</th>
                                        <th class="tc-num">"VAT %"</th>
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
                                                        "Loading products..."
                                                    } else {
                                                        "No products match the current filter."
                                                    }}
                                                </td>
                                            </tr>
                                        }
                                    >
                                        <For
                                            each=move || items.get()
                                            key=|p| {
                                                (
                                                    p.id,
                                                    p.code.clone(),
                                                    p.name.clone(),
                                                    p.product_type.clone(),
                                                    p.family_code.clone(),
                                                    p.unit.clone(),
                                                    p.tracking.clone(),
                                                    p.vat_rate,
                                                    p.active,
                                                )
                                            }
                                            children=move |product| {
                                                let open_product = product.clone();
                                                let open_product_btn = product.clone();
                                                let details_href = crate::components::shell::app_href(&format!("/products/{}", product.id));
                                                let row_tab_id = format!("edit:{}", product.id);
                                                let row_target = format!("product-row-{}", product.code);
                                                let aria_label = format!("Open product {}", product.code);
                                                let type_badge_class = match product.product_type.as_str() {
                                                    "manufactured" => "tc-badge tc-badge-primary",
                                                    "configurable" => "tc-badge tc-badge-warning",
                                                    _ => "tc-badge",
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
                                                        title="Open product detail & edit form"
                                                        on:click=move |_event: leptos::ev::MouseEvent| {
                                                            #[cfg(target_arch = "wasm32")]
                                                            {
                                                                use wasm_bindgen::JsCast;
                                                                let link_clicked = _event.target()
                                                                    .and_then(|target| target.dyn_into::<web_sys::Element>().ok())
                                                                    .and_then(|element| element.closest("a").ok().flatten())
                                                                    .is_some();
                                                                if link_clicked {
                                                                    return;
                                                                }
                                                            }
                                                            open_product_row(open_product.clone());
                                                        }
                                                    >
                                                        <td class="tc-mono">
                                                            <button
                                                                type="button"
                                                                class="tc-inline-tab-btn"
                                                                style="text-align: left;"
                                                                aria-label=aria_label
                                                                on:click=move |ev| {
                                                                    ev.stop_propagation();
                                                                    open_product_row(open_product_btn.clone());
                                                                }
                                                            >
                                                                {product.code}
                                                            </button>
                                                        </td>
                                                        <td>
                                                            <A href=details_href>
                                                                {product.name}
                                                            </A>
                                                        </td>
                                                        <td><span class=type_badge_class>{product.product_type}</span></td>
                                                        <td class="tc-mono">{product.family_code.unwrap_or_else(|| "—".to_string())}</td>
                                                        <td>{product.unit}</td>
                                                        <td>{product.tracking}</td>
                                                        <td class="tc-num">{format!("{}%", product.vat_rate)}</td>
                                                        <td>
                                                            {if product.active {
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

                        let on_submit = move |ev: SubmitEvent| {
                            ev.prevent_default();
                            let Some(session) = ctx.session.get_untracked() else {
                                return;
                            };
                            let Some(snapshot) = read_product_tab(&open_tabs, &tab_id_for_submit, Clone::clone) else {
                                return;
                            };
                            if snapshot.saving {
                                return;
                            }
                            let req = match snapshot.to_request() {
                                Ok(req) => req,
                                Err(msg) => {
                                    update_product_tab(&open_tabs, &tab_id_for_submit, |tab| {
                                        tab.error = Some(msg);
                                        tab.notice = None;
                                    });
                                    return;
                                }
                            };

                            update_product_tab(&open_tabs, &tab_id_for_submit, |tab| {
                                tab.saving = true;
                                tab.error = None;
                                tab.notice = None;
                            });

                            let current_id = tab_id_for_submit.clone();
                            let tab_instance_id = snapshot.instance_id;
                            let snapshot_edit_gen = snapshot.edit_generation;
                            let connection = session.connection;
                            let product_id = snapshot.product_id;
                            spawn_local(async move {
                                let res = match product_id {
                                    Some(id) => WebApiClient.update_product(&connection, id, &req).await,
                                    None => WebApiClient.create_product(&connection, &req).await,
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
                                        update_product_tab_instance(
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

                        view! {
                            <aside class="tc-card tc-detail-drawer" data-target="product-detail-drawer">
                                <div class="tc-inline-tabs" data-target="product-detail-tabs">
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
                                                        on:click=move |_| close_product_tab(&open_tabs, &active_tab_id, &close_id)
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
                                                read_product_tab(&open_tabs, &tab_id_for_header, |t| t.title.clone())
                                                    .unwrap_or_else(|| "Product".to_string())
                                            }}
                                        </h2>
                                        <p class="tc-page-subtitle tc-mono">
                                            {move || {
                                                read_product_tab(&open_tabs, &tab_id_for_badge, |t| {
                                                    match t.product_id {
                                                        Some(id) if t.loading_detail => format!("{id} (loading...)"),
                                                        Some(id) => id.to_string(),
                                                        None => "POST /api/v1/products".to_string(),
                                                    }
                                                })
                                                .unwrap_or_default()
                                            }}
                                        </p>
                                    </div>
                                </div>

                                {move || {
                                    read_product_tab(&open_tabs, &tab_id_for_error, |t| t.error.clone())
                                        .flatten()
                                        .map(|msg| view! {
                                            <div class="tc-alert-error" role="alert" data-target="product-form-error">
                                                {msg}
                                            </div>
                                        })
                                }}

                                {move || {
                                    read_product_tab(&open_tabs, &tab_id_for_notice, |t| t.notice.clone())
                                        .flatten()
                                        .map(|msg| view! {
                                            <div class="tc-alert-success" role="status" data-target="product-form-notice">
                                                {msg}
                                            </div>
                                        })
                                }}

                                <form data-target="product-form" on:submit=on_submit style="display: flex; flex-direction: column; gap: var(--space-md);">
                                    <div class="tc-form-grid">
                                        {product_text_field(&open_tabs, &current_tab_id, "Code *", "product-form-code", "PUMP-100", false, |t| t.code.clone(), |t, v| t.code = v)}
                                        {product_text_field(&open_tabs, &current_tab_id, "Unit", "product-form-unit", "pcs", false, |t| t.unit.clone(), |t, v| t.unit = v)}
                                        {product_text_field(&open_tabs, &current_tab_id, "Name *", "product-form-name", "Circulation Pump", true, |t| t.name.clone(), |t, v| t.name = v)}
                                        {product_text_field(&open_tabs, &current_tab_id, "Description", "product-form-description", "Product description", true, |t| t.description.clone(), |t, v| t.description = v)}

                                        {product_select_field(
                                            &open_tabs,
                                            &current_tab_id,
                                            "Product type",
                                            "product-form-type",
                                            &[
                                                ("purchased", "Purchased"),
                                                ("manufactured", "Manufactured"),
                                                ("configurable", "Configurable"),
                                                ("service", "Service"),
                                            ],
                                            |t| t.product_type.clone(),
                                            |t, val| {
                                                if val == "service" {
                                                    t.tracking = "none".to_string();
                                                }
                                                t.product_type = val;
                                            },
                                        )}
                                        {product_select_field(
                                            &open_tabs,
                                            &current_tab_id,
                                            "Tracking",
                                            "product-form-tracking",
                                            &[("none", "None"), ("serial", "Serial"), ("lot", "Lot")],
                                            |t| t.tracking.clone(),
                                            |t, val| t.tracking = val,
                                        )}
                                        {product_select_field(
                                            &open_tabs,
                                            &current_tab_id,
                                            "VAT category",
                                            "product-form-vat-category",
                                            &[
                                                ("standard", "Standard"),
                                                ("intermediate", "Intermediate"),
                                                ("reduced", "Reduced"),
                                                ("zero", "Zero"),
                                            ],
                                            |t| t.vat_category.clone(),
                                            |t, val| t.vat_category = val,
                                        )}

                                        {product_text_field(&open_tabs, &current_tab_id, "VAT override %", "product-form-vat-override", "Optional e.g. 12.00", false, |t| t.vat_rate_override.clone(), |t, v| t.vat_rate_override = v)}
                                        {product_text_field(&open_tabs, &current_tab_id, "Barcode", "product-form-barcode", "EAN / SKU", false, |t| t.barcode.clone(), |t, v| t.barcode = v)}
                                        {product_text_field(&open_tabs, &current_tab_id, "Standard cost", "product-form-standard-cost", "42.50", false, |t| t.standard_cost.clone(), |t, v| t.standard_cost = v)}
                                        {product_text_field(&open_tabs, &current_tab_id, "Reorder min", "product-form-reorder-min", "10", false, |t| t.reorder_min.clone(), |t, v| t.reorder_min = v)}
                                        {product_text_field(&open_tabs, &current_tab_id, "Reorder max", "product-form-reorder-max", "40", false, |t| t.reorder_max.clone(), |t, v| t.reorder_max = v)}
                                        {product_text_field(&open_tabs, &current_tab_id, "Lead time (days)", "product-form-lead-time", "7", false, |t| t.lead_time_days.clone(), |t, v| t.lead_time_days = v)}
                                        {product_text_field(&open_tabs, &current_tab_id, "Production remark", "product-form-remark", "Internal quotation remark", true, |t| t.default_production_remark.clone(), |t, v| t.default_production_remark = v)}
                                    </div>

                                    <div class="tc-checkbox-grid">
                                        {product_checkbox(&open_tabs, &current_tab_id, "Active", "product-form-active", |t| t.active, |t, v| t.active = v)}
                                        {product_checkbox(&open_tabs, &current_tab_id, "Non-discountable", "product-form-non-discountable", |t| t.non_discountable, |t, v| t.non_discountable = v)}
                                        {product_checkbox(&open_tabs, &current_tab_id, "Price on request", "product-form-price-on-request", |t| t.price_on_request, |t, v| t.price_on_request = v)}
                                        {product_checkbox(&open_tabs, &current_tab_id, "Price is indicative", "product-form-price-is-indicative", |t| t.price_is_indicative, |t, v| t.price_is_indicative = v)}
                                    </div>

                                    <div class="tc-form-actions">
                                        <button
                                            type="button"
                                            data-target="product-form-cancel"
                                            class="tc-btn"
                                            on:click=move |_| close_product_tab(&open_tabs, &active_tab_id, &tab_id_for_cancel)
                                        >
                                            "Cancel"
                                        </button>
                                        <button
                                            type="submit"
                                            data-target="product-form-save"
                                            class="tc-btn tc-btn-primary"
                                            disabled=move || read_product_tab(&open_tabs, &tab_id_for_saving, |t| t.saving).unwrap_or(false)
                                        >
                                            {move || {
                                                if read_product_tab(&open_tabs, &current_tab_id, |t| t.saving).unwrap_or(false) {
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
fn product_select_field(
    tabs: &RwSignal<Vec<ProductTab>>,
    tab_id: &str,
    label: &'static str,
    target: &'static str,
    options: &'static [(&'static str, &'static str)],
    get: fn(&ProductTab) -> String,
    set: fn(&mut ProductTab, String),
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
                prop:value=move || read_product_tab(&tabs, &tid_read, get).unwrap_or_default()
                on:change=move |ev| {
                    let val = event_target_value(&ev);
                    update_product_tab(&tabs, &tid_write, |tab| {
                        set(tab, val);
                        tab.mark_dirty();
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
fn product_text_field(
    tabs: &RwSignal<Vec<ProductTab>>,
    tab_id: &str,
    label: &'static str,
    target: &'static str,
    placeholder: &'static str,
    span_two: bool,
    get: fn(&ProductTab) -> String,
    set: fn(&mut ProductTab, String),
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
                prop:value=move || read_product_tab(&tabs, &tid_read, get).unwrap_or_default()
                on:input=move |ev| {
                    let val = event_target_value(&ev);
                    update_product_tab(&tabs, &tid_write, |tab| {
                        set(tab, val);
                        tab.mark_dirty();
                    });
                }
            />
        </div>
    }
}

fn product_checkbox(
    tabs: &RwSignal<Vec<ProductTab>>,
    tab_id: &str,
    label: &'static str,
    target: &'static str,
    get: fn(&ProductTab) -> bool,
    set: fn(&mut ProductTab, bool),
) -> impl IntoView {
    let tabs = *tabs;
    let tid_read = tab_id.to_string();
    let tid_write = tab_id.to_string();
    view! {
        <label class="tc-checkbox-row" for=target>
            <input
                id=target
                data-target=target
                type="checkbox"
                prop:checked=move || read_product_tab(&tabs, &tid_read, get).unwrap_or(false)
                on:change=move |ev| {
                    let checked = event_target_checked(&ev);
                    update_product_tab(&tabs, &tid_write, |tab| {
                        set(tab, checked);
                        tab.mark_dirty();
                    });
                }
            />
            <span>{label}</span>
        </label>
    }
}
