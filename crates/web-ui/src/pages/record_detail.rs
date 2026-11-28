//! Deep-link record detail view and route wrapper, mounting real entity details, linked To-dos,
//! and record [`ChatterPanel`] side-by-side (ADR 0041 & ADR 0086).

use leptos::prelude::*;
use leptos_router::components::A;
use leptos_router::hooks::use_params_map;
use tradocraft_api_client::chatter::RecordKind;
use tradocraft_api_client::kb::KbEntry;
use tradocraft_api_client::{Customer, Order, Product, Quotation, Supplier, TicketDetail};
use uuid::Uuid;

use crate::api::{ApiClient, WebApiClient};
use crate::components::async_ops::{live_client, set_alive, RequestGuard};
use crate::components::chatter::ChatterPanel;
use crate::components::files::format_file_size;
use crate::components::shell::app_href;
use crate::components::todo_widgets::ObjectTodosButton;
use crate::state::AppContext;
use crate::state::WorkspaceTab;

/// Supported record types for deep links and mounted workspace tabs.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DetailKind {
    Product,
    Customer,
    Quotation,
    Order,
    Supplier,
    Ticket,
    KbEntry,
}

impl DetailKind {
    pub fn key(self) -> &'static str {
        match self {
            Self::Product => "product",
            Self::Customer => "customer",
            Self::Quotation => "quotation",
            Self::Order => "order",
            Self::Supplier => "supplier",
            Self::Ticket => "ticket",
            Self::KbEntry => "kb",
        }
    }

    pub fn label(self) -> &'static str {
        match self {
            Self::Product => "Product",
            Self::Customer => "Customer",
            Self::Quotation => "Quotation",
            Self::Order => "Order",
            Self::Supplier => "Supplier",
            Self::Ticket => "Ticket",
            Self::KbEntry => "Article",
        }
    }

    pub fn list_route(self) -> &'static str {
        match self {
            Self::Product => "/products",
            Self::Customer => "/customers",
            Self::Quotation => "/quotations",
            Self::Order => "/orders",
            Self::Supplier => "/purchasing",
            Self::Ticket => "/helpdesk",
            Self::KbEntry => "/kb",
        }
    }

    pub fn route(self, id: Uuid) -> String {
        match self {
            Self::Product => format!("/products/{id}"),
            Self::Customer => format!("/customers/{id}"),
            Self::Quotation => format!("/quotations/{id}"),
            Self::Order => format!("/orders/{id}"),
            Self::Supplier => format!("/suppliers/{id}"),
            Self::Ticket => format!("/helpdesk/{id}"),
            Self::KbEntry => format!("/kb/{id}"),
        }
    }

    pub fn tab_id(self, id: Uuid) -> String {
        format!("{}:{id}", self.key())
    }

    /// Corresponding `chatter` record kind when supported by `/api/v1/chatter/{kind}/{id}/...`.
    pub fn chatter_kind(self) -> Option<&'static str> {
        match self {
            Self::Customer => Some(RecordKind::Customer.as_str()),
            Self::Quotation => Some(RecordKind::Quotation.as_str()),
            Self::Order => Some(RecordKind::Order.as_str()),
            _ => None,
        }
    }

    /// Corresponding `todo.items.link_kind` string.
    pub fn todo_link_kind(self) -> &'static str {
        match self {
            Self::Product => "product",
            Self::Customer => "customer",
            Self::Quotation => "quotation",
            Self::Order => "order",
            Self::Supplier => "supplier",
            Self::Ticket => "ticket",
            Self::KbEntry => "kb_entry",
        }
    }

    /// Parses `/customers/<uuid>`, `/quotations/<uuid>`, `/app/orders/<uuid>`, etc.
    pub fn parse_route(route: &str) -> Option<(Self, Uuid)> {
        let stripped = route
            .trim()
            .trim_start_matches("/app")
            .trim_start_matches('/');
        let mut parts = stripped.split('/');
        let segment = parts.next()?;
        let id_str = parts.next()?;
        if parts.next().is_some() {
            return None;
        }
        let kind = match segment {
            "products" => Self::Product,
            "customers" => Self::Customer,
            "quotations" => Self::Quotation,
            "orders" => Self::Order,
            "suppliers" => Self::Supplier,
            "helpdesk" => Self::Ticket,
            "kb" => Self::KbEntry,
            _ => return None,
        };
        let id = Uuid::parse_str(id_str).ok()?;
        Some((kind, id))
    }
}

#[derive(Clone)]
enum LoadedRecord {
    Product(Product),
    Customer(Customer),
    Quotation(Box<Quotation>),
    Order(Box<Order>),
    Supplier(Supplier),
    Ticket(Box<TicketDetail>),
    KbEntry(Box<KbEntry>),
}

impl LoadedRecord {
    fn title_and_subtitle(&self) -> (String, String) {
        match self {
            Self::Product(p) => (p.name.clone(), p.code.clone()),
            Self::Customer(c) => (c.name.clone(), c.code.clone()),
            Self::Quotation(q) => (q.number.clone(), q.customer_name.clone()),
            Self::Order(o) => (o.order.number.clone(), o.order.customer_name.clone()),
            Self::Supplier(s) => (s.name.clone(), s.code.clone()),
            Self::Ticket(t) => (
                format!("{} · {}", t.ticket.number, t.ticket.subject),
                t.ticket.status.clone(),
            ),
            Self::KbEntry(e) => {
                let title = e
                    .text_for("en")
                    .or_else(|| e.texts.first())
                    .map(|t| t.title.clone())
                    .filter(|t| !t.is_empty())
                    .unwrap_or_else(|| e.number.clone());
                (title, e.number.clone())
            }
        }
    }
}

fn kv_row(label: &'static str, value: impl Into<String>) -> impl IntoView {
    let val = value.into();
    view! {
        <div class="tc-detail-kv">
            <span class="tc-label">{label}</span>
            <span>{if val.is_empty() { "—".to_string() } else { val }}</span>
        </div>
    }
}

/// Real mounted record detail view shared between deep-link routes and workspace tabs.
#[component]
pub fn RecordDetailView(
    kind: DetailKind,
    id: Uuid,
    #[prop(optional)] on_loaded: Option<Callback<(String, String)>>,
) -> impl IntoView {
    let ctx = expect_context::<AppContext>();
    let loading = RwSignal::new(true);
    let error = RwSignal::new(Option::<String>::None);
    let loaded = RwSignal::new(Option::<LoadedRecord>::None);
    let reload = RwSignal::new(0_u64);
    let guard = RequestGuard::new();

    Effect::new(move |_| {
        let _ = reload.get();
        let Some(active) = ctx.session.get() else {
            let _ = guard.bump();
            loading.set(false);
            loaded.set(None);
            return;
        };
        let gen = guard.bump();
        loading.set(true);
        error.set(None);

        let conn = active.connection;
        leptos::task::spawn_local(async move {
            let res = match kind {
                DetailKind::Product => WebApiClient
                    .get_product(&conn, id)
                    .await
                    .map(LoadedRecord::Product),
                DetailKind::Customer => WebApiClient
                    .get_customer(&conn, id)
                    .await
                    .map(LoadedRecord::Customer),
                DetailKind::Quotation => match live_client(&conn) {
                    Ok(c) => c
                        .get_quotation(id)
                        .await
                        .map(|q| LoadedRecord::Quotation(Box::new(q))),
                    Err(err) => Err(err),
                },
                DetailKind::Order => match live_client(&conn) {
                    Ok(c) => c
                        .get_order(id)
                        .await
                        .map(|o| LoadedRecord::Order(Box::new(o))),
                    Err(err) => Err(err),
                },
                DetailKind::Supplier => match live_client(&conn) {
                    Ok(c) => c.get_supplier(id).await.map(LoadedRecord::Supplier),
                    Err(err) => Err(err),
                },
                DetailKind::Ticket => match live_client(&conn) {
                    Ok(c) => c
                        .get_ticket(id)
                        .await
                        .map(|t| LoadedRecord::Ticket(Box::new(t))),
                    Err(err) => Err(err),
                },
                DetailKind::KbEntry => match live_client(&conn) {
                    Ok(c) => c
                        .get_kb_entry(id)
                        .await
                        .map(|e| LoadedRecord::KbEntry(Box::new(e))),
                    Err(err) => Err(err),
                },
            };

            if !guard.is_current(gen) {
                return;
            }
            let _ = set_alive(loading, false);
            match res {
                Ok(record) => {
                    let meta = record.title_and_subtitle();
                    let _ = set_alive(loaded, Some(record));
                    if let Some(cb) = on_loaded {
                        cb.run(meta);
                    }
                }
                Err(err) => {
                    let _ = set_alive(error, Some(err.user_message()));
                }
            }
        });
    });

    let title_sig = Signal::derive(move || {
        loaded.with(|opt| {
            opt.as_ref()
                .map(|r| r.title_and_subtitle().0)
                .unwrap_or_else(|| kind.label().to_string())
        })
    });
    let subtitle_sig = Signal::derive(move || {
        loaded.with(|opt| {
            opt.as_ref()
                .map(|r| r.title_and_subtitle().1)
                .unwrap_or_else(|| id.to_string())
        })
    });
    let has_chatter = kind.chatter_kind().is_some();
    let route_str = kind.route(id);

    view! {
        <div
            data-target=format!("record-detail-{}", kind.key())
            data-record-id=id.to_string()
        >
            <div class="tc-page-header">
                <div>
                    <div class="tc-header-actions" style="margin-bottom: 4px;">
                        <span class="tc-badge tc-badge-primary">{kind.label()}</span>
                        <span class="tc-mono" style="font-size: 12px; color: var(--on-surface-variant);">
                            {move || subtitle_sig.get()}
                        </span>
                    </div>
                    <h1 class="tc-page-title" data-target="record-detail-title">
                        {move || title_sig.get()}
                    </h1>
                </div>
                <div class="tc-header-actions">
                    <ObjectTodosButton
                        kind=kind.todo_link_kind()
                        id=id
                        label=title_sig
                        location=route_str
                    />
                    <button
                        type="button"
                        class="tc-btn tc-btn-sm"
                        data-target="record-detail-refresh"
                        on:click=move |_| reload.update(|n| *n = n.wrapping_add(1))
                    >
                        "Refresh"
                    </button>
                    <A
                        href=app_href(kind.list_route())
                        attr:class="tc-btn tc-btn-sm"
                        attr:data-target="record-detail-back"
                    >
                        "All records"
                    </A>
                </div>
            </div>

            <Show
                when=move || ctx.session.with(Option::is_some)
                fallback=|| view! {
                    <div class="tc-card" style="max-width: 520px;">
                        <p style="margin: 0 0 var(--space-md);">"Sign in to view this record."</p>
                        <A href=app_href("/login") attr:class="tc-btn tc-btn-primary" attr:data-target="record-detail-go-login">
                            "Go to sign in"
                        </A>
                    </div>
                }
            >
                <div class=if has_chatter { "tc-record-layout" } else { "tc-record-layout-single" }>
                    <div class="tc-card" data-target="record-detail-main">
                        {move || error.get().map(|msg| view! {
                            <div class="tc-alert-error" style="margin-bottom: var(--space-md);" role="alert" data-target="record-detail-error">
                                {msg}
                            </div>
                        })}
                        {move || {
                            if loading.get() && loaded.with(Option::is_none) {
                                return view! {
                                    <p style="margin: 0; color: var(--on-surface-variant);">"Loading record…"</p>
                                }
                                .into_any();
                            }
                            let Some(rec) = loaded.get() else {
                                return view! { <div></div> }.into_any();
                            };
                            match rec {
                                LoadedRecord::Customer(c) => view! {
                                    <div class="tc-detail-grid">
                                        {kv_row("Code", c.code)}
                                        {kv_row("Name", c.name)}
                                        {kv_row("VAT number", c.vat_number.unwrap_or_default())}
                                        {kv_row("VAT regime", c.vat_regime)}
                                        {kv_row("Email", c.email.unwrap_or_default())}
                                        {kv_row("Phone", c.phone.unwrap_or_default())}
                                        {kv_row("Address", format!("{}, {} {} {}", c.street, c.postal_code, c.city, c.country_code))}
                                        {kv_row("Language", c.language)}
                                        {kv_row("Active", if c.active { "Yes" } else { "No" })}
                                    </div>
                                }
                                .into_any(),
                                LoadedRecord::Product(p) => view! {
                                    <div class="tc-detail-grid">
                                        {kv_row("Code", p.code)}
                                        {kv_row("Name", p.name)}
                                        {kv_row("Type", p.product_type)}
                                        {kv_row("Unit", p.unit)}
                                        {kv_row("VAT %", p.vat_rate.to_string())}
                                        {kv_row("Tracking", p.tracking)}
                                        {kv_row("Barcode", p.barcode.unwrap_or_default())}
                                        {kv_row("Description", p.description)}
                                    </div>
                                }
                                .into_any(),
                                LoadedRecord::Quotation(q) => view! {
                                    <div style="display: flex; flex-direction: column; gap: var(--space-lg);">
                                        <div class="tc-detail-grid">
                                            {kv_row("Number", format!("{} (rev {})", q.number, q.revision))}
                                            {kv_row("Status", q.status.as_str())}
                                            {kv_row("Customer", q.customer_name)}
                                            {kv_row("Quote date", q.quote_date.to_string())}
                                            {kv_row("Valid until", q.valid_until.to_string())}
                                            {kv_row("Total", format!("{} {}", q.currency, q.total))}
                                        </div>
                                        <div class="tc-table-wrap">
                                            <table class="tc-table">
                                                <thead>
                                                    <tr>
                                                        <th>"Code"</th>
                                                        <th>"Description"</th>
                                                        <th class="tc-num">"Qty"</th>
                                                        <th class="tc-num">"Net"</th>
                                                        <th class="tc-num">"Line total"</th>
                                                    </tr>
                                                </thead>
                                                <tbody>
                                                    {q.lines.into_iter().map(|l| view! {
                                                        <tr>
                                                            <td class="tc-mono">{l.product_code}</td>
                                                            <td>{l.description}</td>
                                                            <td class="tc-num">{l.quantity.to_string()}</td>
                                                            <td class="tc-num">{l.net_unit_price.to_string()}</td>
                                                            <td class="tc-num">{l.line_total.to_string()}</td>
                                                        </tr>
                                                    }).collect_view()}
                                                </tbody>
                                            </table>
                                        </div>
                                    </div>
                                }
                                .into_any(),
                                LoadedRecord::Order(o) => view! {
                                    <div style="display: flex; flex-direction: column; gap: var(--space-lg);">
                                        <div class="tc-detail-grid">
                                            {kv_row("Number", format!("{} (rev {})", o.order.number, o.revision))}
                                            {kv_row("Status", o.order.status)}
                                            {kv_row("Customer", o.order.customer_name)}
                                            {kv_row("Quotation", o.order.quotation_number)}
                                            {kv_row("Order date", o.order.order_date.to_string())}
                                            {kv_row("Total", format!("{} {}", o.order.currency, o.order.total))}
                                        </div>
                                        <div class="tc-table-wrap">
                                            <table class="tc-table">
                                                <thead>
                                                    <tr>
                                                        <th>"Code"</th>
                                                        <th>"Description"</th>
                                                        <th class="tc-num">"Qty"</th>
                                                        <th class="tc-num">"Net"</th>
                                                        <th class="tc-num">"Line total"</th>
                                                    </tr>
                                                </thead>
                                                <tbody>
                                                    {o.lines.into_iter().map(|l| view! {
                                                        <tr>
                                                            <td class="tc-mono">{l.product_code}</td>
                                                            <td>{l.description}</td>
                                                            <td class="tc-num">{l.quantity.to_string()}</td>
                                                            <td class="tc-num">{l.net_unit_price.to_string()}</td>
                                                            <td class="tc-num">{l.line_total.to_string()}</td>
                                                        </tr>
                                                    }).collect_view()}
                                                </tbody>
                                            </table>
                                        </div>
                                    </div>
                                }
                                .into_any(),
                                LoadedRecord::Supplier(s) => view! {
                                    <div class="tc-detail-grid">
                                        {kv_row("Code", s.code)}
                                        {kv_row("Name", s.name)}
                                        {kv_row("Country", s.country)}
                                        {kv_row("Currency", s.currency)}
                                        {kv_row("Email", s.email)}
                                        {kv_row("Phone", s.phone)}
                                        {kv_row("Contact", s.contact_person)}
                                        {kv_row("Payment terms", format!("{} days", s.payment_terms_days))}
                                    </div>
                                }
                                .into_any(),
                                LoadedRecord::Ticket(t) => view! {
                                    <div style="display: flex; flex-direction: column; gap: var(--space-md);">
                                        <div class="tc-detail-grid">
                                            {kv_row("Number", t.ticket.number)}
                                            {kv_row("Status", t.ticket.status)}
                                            {kv_row("Priority", t.ticket.priority)}
                                            {kv_row("Category", t.ticket.category)}
                                            {kv_row("Customer", t.ticket.customer_name.unwrap_or_default())}
                                            {kv_row("Owner", t.ticket.owner_name.unwrap_or_default())}
                                        </div>
                                        {t.articles.into_iter().map(|a| view! {
                                            <div class="tc-chatter-item">
                                                <div class="tc-chatter-item-head">
                                                    <strong>{a.from_name}</strong>
                                                    <span class="tc-badge">{a.kind}</span>
                                                </div>
                                                <p style="margin: 4px 0 0; white-space: pre-wrap;">{a.body}</p>
                                            </div>
                                        }).collect_view()}
                                    </div>
                                }
                                .into_any(),
                                LoadedRecord::KbEntry(e) => {
                                    let texts = e.texts;
                                    let images = e.images;
                                    view! {
                                        <div style="display: flex; flex-direction: column; gap: var(--space-md);">
                                            <div class="tc-detail-grid">
                                                {kv_row("Number", e.number)}
                                                {kv_row("Status", e.status)}
                                                {kv_row("Visibility", e.visibility)}
                                                {kv_row("Tags", e.tags.join(", "))}
                                            </div>
                                            {texts.into_iter().map(|txt| view! {
                                                <div class="tc-chatter-item">
                                                    <div class="tc-chatter-item-head">
                                                        <strong>{txt.title}</strong>
                                                        <span class="tc-badge">{txt.language}</span>
                                                    </div>
                                                    {(!txt.summary.is_empty()).then(|| view! {
                                                        <p style="margin: 4px 0 0; color: var(--on-surface-variant);">{txt.summary}</p>
                                                    })}
                                                    {(!txt.body.is_empty()).then(|| view! {
                                                        <p style="margin: 6px 0 0; white-space: pre-wrap;">{txt.body}</p>
                                                    })}
                                                </div>
                                            }).collect_view()}
                                            {(!images.is_empty()).then(|| view! {
                                                <div class="tc-chip-row">
                                                    {images.into_iter().map(|img| view! {
                                                        <span class="tc-badge">
                                                            {format!("{} ({})", img.filename, format_file_size(i64::from(img.size_bytes)))}
                                                        </span>
                                                    }).collect_view()}
                                                </div>
                                            })}
                                        </div>
                                    }
                                    .into_any()
                                }
                            }
                        }}
                    </div>
                    {kind.chatter_kind().map(|ck| view! { <ChatterPanel kind=ck record_id=id /> })}
                </div>
            </Show>
        </div>
    }
}

/// Deep-link route page reading `:id`, registering a workspace tab, and mounting [`RecordDetailView`].
#[component]
pub fn RecordDetailPage(kind: DetailKind) -> impl IntoView {
    let ctx = expect_context::<AppContext>();
    let params = use_params_map();

    let parsed_id = Memo::new(move |_| {
        params.with(|p| p.get("id").and_then(|raw| Uuid::parse_str(raw.trim()).ok()))
    });

    Effect::new(move |_| {
        if let Some(id) = parsed_id.get() {
            ctx.register_tab(WorkspaceTab {
                id: kind.tab_id(id),
                title: kind.label().to_string(),
                route: kind.route(id),
                subtitle: id.to_string(),
            });
        }
    });

    view! {
        {move || match parsed_id.get() {
            Some(id) => {
                let on_loaded = Callback::new(move |(title, subtitle): (String, String)| {
                    ctx.register_tab(WorkspaceTab {
                        id: kind.tab_id(id),
                        title,
                        route: kind.route(id),
                        subtitle,
                    });
                });
                view! { <RecordDetailView kind=kind id=id on_loaded=on_loaded /> }.into_any()
            }
            None => view! {
                <div class="tc-card" style="max-width: 520px;" data-target="record-detail-invalid-id">
                    <h2 class="tc-page-title" style="font-size: 16px; margin-bottom: var(--space-sm);">
                        "Invalid record identifier"
                    </h2>
                    <A href=app_href(kind.list_route()) attr:class="tc-btn tc-btn-primary tc-btn-sm">
                        "Back to list"
                    </A>
                </div>
            }
            .into_any(),
        }}
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_deep_link_routes() {
        let id = Uuid::nil();
        assert_eq!(
            DetailKind::parse_route(&format!("/customers/{id}")),
            Some((DetailKind::Customer, id))
        );
        assert_eq!(
            DetailKind::parse_route(&format!("/app/quotations/{id}")),
            Some((DetailKind::Quotation, id))
        );
        assert_eq!(
            DetailKind::parse_route(&format!("/orders/{id}")),
            Some((DetailKind::Order, id))
        );
        assert_eq!(
            DetailKind::parse_route(&format!("/suppliers/{id}")),
            Some((DetailKind::Supplier, id))
        );
        assert_eq!(
            DetailKind::parse_route(&format!("/helpdesk/{id}")),
            Some((DetailKind::Ticket, id))
        );
        assert_eq!(
            DetailKind::parse_route(&format!("/kb/{id}")),
            Some((DetailKind::KbEntry, id))
        );
        assert_eq!(DetailKind::parse_route("/customers/not-a-uuid"), None);
        assert_eq!(
            DetailKind::parse_route("/unknown/00000000-0000-0000-0000-000000000000"),
            None
        );
    }

    #[test]
    fn chatter_and_todo_link_mappings_match_backend() {
        assert_eq!(DetailKind::Customer.chatter_kind(), Some("customer"));
        assert_eq!(DetailKind::Quotation.chatter_kind(), Some("quotation"));
        assert_eq!(DetailKind::Order.chatter_kind(), Some("order"));
        assert_eq!(DetailKind::Product.chatter_kind(), None);
        assert_eq!(DetailKind::KbEntry.todo_link_kind(), "kb_entry");
    }
}
