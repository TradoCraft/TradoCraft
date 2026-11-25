use leptos::prelude::*;
use leptos::task::spawn_local;
use leptos_router::components::A;

use crate::api::{ApiClient, ConnectionMode, ListProductsParams, Product, WebApiClient};
use crate::state::{AppContext, WorkspaceTab};

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

    let fetch_products = move |connection: ConnectionMode, params: ListProductsParams| {
        loading.set(true);
        error.set(None);
        spawn_local(async move {
            match WebApiClient.list_products(&connection, &params).await {
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
        let pt = product_type.get();
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

    view! {
        <div data-target="products-page">
            <div class="tc-page-header">
                <div>
                    <h1 class="tc-page-title">"Products"</h1>
                    <p class="tc-page-subtitle" data-target="products-total">
                        {move || format!("Read-only master catalogue ({} total)", total.get())}
                    </p>
                </div>
                <button
                    type="button"
                    data-target="products-refresh"
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
                            "Sign in to load products from GET /api/v1/products (or pick Offline Mock on the sign-in screen)."
                        </p>
                        <A href="/login" attr:class="tc-btn tc-btn-primary" attr:data-target="products-go-login">
                            "Go to sign in"
                        </A>
                    </div>
                }
            >
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
                                    key=|p| p.id
                                    children=move |product| {
                                        let open_product = product.clone();
                                        let row_target = format!("product-row-{}", product.code);
                                        let type_badge_class = match product.product_type.as_str() {
                                            "manufactured" => "tc-badge tc-badge-primary",
                                            "configurable" => "tc-badge tc-badge-warning",
                                            _ => "tc-badge",
                                        };
                                        view! {
                                            <tr
                                                class="tc-row-clickable"
                                                data-target=row_target
                                                title="Open in workspace tab"
                                                on:click=move |_| {
                                                    ctx.open_tab(WorkspaceTab {
                                                        id: format!("product:{}", open_product.id),
                                                        title: format!("{} · {}", open_product.code, open_product.name),
                                                        route: format!("/products/{}", open_product.id),
                                                        subtitle: format!(
                                                            "{} ({}, VAT {}%, tracking: {})",
                                                            open_product.description,
                                                            open_product.product_type,
                                                            open_product.vat_rate,
                                                            open_product.tracking,
                                                        ),
                                                    });
                                                }
                                            >
                                                <td class="tc-mono">{product.code}</td>
                                                <td>{product.name}</td>
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
            </Show>
        </div>
    }
}
