use leptos::ev::SubmitEvent;
use leptos::prelude::*;
use leptos::task::spawn_local;
use tradocraft_api_client::portal::{
    ConfirmPortalOrder, LoginLinkInput, MessageInput, NewTicket, PortalOrder, PortalOrderDetail,
    PortalProfile, PortalTicket, PortalTicketDetail, SessionInput,
};
use tradocraft_api_client::{Client, Session};
use uuid::Uuid;

use crate::api::{resolve_base_url, ConnectionMode};
use crate::pages::{opt_trimmed, parse_uuid};
use crate::state::AppContext;

fn portal_client(base_url: &str, token: Option<&str>) -> Client {
    let resolved = resolve_base_url(base_url);
    match token {
        Some(tok) if !tok.trim().is_empty() => Client::from_session(Session::bearer(resolved, tok)),
        _ => Client::from_session(Session::anonymous(resolved)),
    }
}

fn default_portal_connection(ctx: &AppContext) -> (String, String) {
    match ctx.session.get_untracked() {
        Some(active) => match active.connection {
            ConnectionMode::Live(s) => (
                s.base_url,
                s.company_id.unwrap_or(active.me.company.id).to_string(),
            ),
            ConnectionMode::MockDemo => (String::new(), active.me.company.id.to_string()),
        },
        None => match ctx.draft_connection.get_untracked() {
            ConnectionMode::Live(s) => (
                s.base_url,
                s.company_id.map(|id| id.to_string()).unwrap_or_default(),
            ),
            ConnectionMode::MockDemo => (String::new(), String::new()),
        },
    }
}

fn token_from_url_hash() -> Option<String> {
    #[cfg(target_arch = "wasm32")]
    {
        if let Some(hash) = web_sys::window().and_then(|w| w.location().hash().ok()) {
            let trimmed = hash.trim_start_matches('#');
            for part in trimmed.split('&') {
                if let Some(val) = part.strip_prefix("token=") {
                    if !val.trim().is_empty() {
                        return Some(val.trim().to_string());
                    }
                }
            }
        }
    }
    None
}

#[component]
pub fn PortalPage() -> impl IntoView {
    let ctx = expect_context::<AppContext>();
    let (init_base, init_company) = default_portal_connection(&ctx);

    let base_url = RwSignal::new(init_base);
    let company_id_input = RwSignal::new(init_company);

    // Passwordless login-link + session exchange state
    let login_email = RwSignal::new(String::new());
    let link_busy = RwSignal::new(false);
    let link_notice = RwSignal::new(Option::<String>::None);

    let session_token_input = RwSignal::new(token_from_url_hash().unwrap_or_default());
    let session_busy = RwSignal::new(false);

    let portal_token = RwSignal::new(Option::<String>::None);
    let portal_profile = RwSignal::new(Option::<PortalProfile>::None);
    let auth_error = RwSignal::new(Option::<String>::None);

    // Workspace data state
    let loading_data = RwSignal::new(false);
    let portal_error = RwSignal::new(Option::<String>::None);
    let portal_notice = RwSignal::new(Option::<String>::None);

    let tickets = RwSignal::new(Vec::<PortalTicket>::new());
    let selected_ticket = RwSignal::new(Option::<PortalTicketDetail>::None);
    let loading_ticket = RwSignal::new(false);
    let new_ticket_subject = RwSignal::new(String::new());
    let new_ticket_category = RwSignal::new("question".to_string());
    let new_ticket_body = RwSignal::new(String::new());
    let creating_ticket = RwSignal::new(false);
    let reply_body = RwSignal::new(String::new());
    let sending_reply = RwSignal::new(false);

    let orders = RwSignal::new(Vec::<PortalOrder>::new());
    let selected_order = RwSignal::new(Option::<PortalOrderDetail>::None);
    let loading_order = RwSignal::new(false);
    let confirm_note = RwSignal::new(String::new());
    let confirming_order = RwSignal::new(false);

    let refresh_portal_data = move || {
        let Some(tok) = portal_token.get_untracked() else {
            return;
        };
        let base = base_url.get_untracked();
        let client = portal_client(&base, Some(&tok));
        loading_data.set(true);
        portal_error.set(None);
        spawn_local(async move {
            let me_res = client.portal_me().await;
            let tickets_res = client.list_portal_tickets().await;
            let orders_res = client.list_portal_orders().await;
            loading_data.set(false);
            if let Ok(me) = me_res {
                portal_profile.set(Some(me));
            }
            match (tickets_res, orders_res) {
                (Ok(t), Ok(o)) => {
                    tickets.set(t);
                    orders.set(o);
                }
                (Err(err), _) | (_, Err(err)) => {
                    portal_error.set(Some(err.user_message()));
                }
            }
        });
    };

    let on_request_login_link = move |ev: SubmitEvent| {
        ev.prevent_default();
        if link_busy.get_untracked() {
            return;
        }
        let raw_company = company_id_input.get_untracked();
        let company_id = match parse_uuid("Company ID", &raw_company) {
            Ok(id) => id,
            Err(msg) => {
                auth_error.set(Some(msg));
                return;
            }
        };
        let Some(email) = opt_trimmed(&login_email.get_untracked()) else {
            auth_error.set(Some("Email address is required.".to_string()));
            return;
        };

        let base = base_url.get_untracked();
        let client = portal_client(&base, None);
        link_busy.set(true);
        auth_error.set(None);
        link_notice.set(None);
        spawn_local(async move {
            let req = LoginLinkInput { company_id, email };
            match client.request_portal_login_link(&req).await {
                Ok(()) => {
                    link_busy.set(false);
                    link_notice.set(Some(
                        "If this address is enabled for the portal, a login link has been sent."
                            .to_string(),
                    ));
                }
                Err(err) => {
                    link_busy.set(false);
                    auth_error.set(Some(err.user_message()));
                }
            }
        });
    };

    let on_exchange_session = move |ev: SubmitEvent| {
        ev.prevent_default();
        if session_busy.get_untracked() {
            return;
        }
        let Some(token) = opt_trimmed(&session_token_input.get_untracked()) else {
            auth_error.set(Some("Login link token is required.".to_string()));
            return;
        };

        let base = base_url.get_untracked();
        let client = portal_client(&base, None);
        session_busy.set(true);
        auth_error.set(None);
        spawn_local(async move {
            match client.create_portal_session(&SessionInput { token }).await {
                Ok(session) => {
                    portal_token.set(Some(session.token));
                    portal_profile.set(Some(session.profile));
                    session_token_input.set(String::new());
                    session_busy.set(false);
                    refresh_portal_data();
                }
                Err(err) => {
                    session_busy.set(false);
                    auth_error.set(Some(err.user_message()));
                }
            }
        });
    };

    let open_ticket = move |ticket_id: Uuid| {
        let Some(tok) = portal_token.get_untracked() else {
            return;
        };
        let base = base_url.get_untracked();
        let client = portal_client(&base, Some(&tok));
        loading_ticket.set(true);
        portal_error.set(None);
        spawn_local(async move {
            match client.get_portal_ticket(ticket_id).await {
                Ok(detail) => {
                    selected_ticket.set(Some(detail));
                    loading_ticket.set(false);
                }
                Err(err) => {
                    loading_ticket.set(false);
                    portal_error.set(Some(err.user_message()));
                }
            }
        });
    };

    let on_create_ticket = move |ev: SubmitEvent| {
        ev.prevent_default();
        if creating_ticket.get_untracked() {
            return;
        }
        let Some(tok) = portal_token.get_untracked() else {
            return;
        };
        let Some(subject) = opt_trimmed(&new_ticket_subject.get_untracked()) else {
            portal_error.set(Some("Ticket subject is required.".to_string()));
            return;
        };
        let Some(body) = opt_trimmed(&new_ticket_body.get_untracked()) else {
            portal_error.set(Some("Ticket message is required.".to_string()));
            return;
        };
        let category = new_ticket_category.get_untracked();
        let base = base_url.get_untracked();
        let client = portal_client(&base, Some(&tok));

        creating_ticket.set(true);
        portal_error.set(None);
        portal_notice.set(None);
        spawn_local(async move {
            let req = NewTicket {
                subject,
                category,
                body,
            };
            match client.create_portal_ticket(&req).await {
                Ok(detail) => {
                    new_ticket_subject.set(String::new());
                    new_ticket_body.set(String::new());
                    creating_ticket.set(false);
                    portal_notice.set(Some(format!("Ticket {} opened.", detail.ticket.number)));
                    selected_ticket.set(Some(detail));
                    refresh_portal_data();
                }
                Err(err) => {
                    creating_ticket.set(false);
                    portal_error.set(Some(err.user_message()));
                }
            }
        });
    };

    let on_send_reply = move |ev: SubmitEvent| {
        ev.prevent_default();
        if sending_reply.get_untracked() {
            return;
        }
        let Some(tok) = portal_token.get_untracked() else {
            return;
        };
        let Some(ticket_id) = selected_ticket.with_untracked(|t| t.as_ref().map(|d| d.ticket.id))
        else {
            return;
        };
        let Some(body) = opt_trimmed(&reply_body.get_untracked()) else {
            portal_error.set(Some("Reply text is required.".to_string()));
            return;
        };

        let base = base_url.get_untracked();
        let client = portal_client(&base, Some(&tok));
        sending_reply.set(true);
        portal_error.set(None);
        portal_notice.set(None);
        spawn_local(async move {
            let req = MessageInput {
                body,
                attachment_ids: Vec::new(),
            };
            match client.add_portal_ticket_message(ticket_id, &req).await {
                Ok(detail) => {
                    reply_body.set(String::new());
                    sending_reply.set(false);
                    selected_ticket.set(Some(detail));
                    portal_notice.set(Some("Reply sent.".to_string()));
                    refresh_portal_data();
                }
                Err(err) => {
                    sending_reply.set(false);
                    portal_error.set(Some(err.user_message()));
                }
            }
        });
    };

    let open_order = move |order_id: Uuid| {
        let Some(tok) = portal_token.get_untracked() else {
            return;
        };
        let base = base_url.get_untracked();
        let client = portal_client(&base, Some(&tok));
        loading_order.set(true);
        portal_error.set(None);
        spawn_local(async move {
            match client.get_portal_order(order_id).await {
                Ok(detail) => {
                    selected_order.set(Some(detail));
                    confirm_note.set(String::new());
                    loading_order.set(false);
                }
                Err(err) => {
                    loading_order.set(false);
                    portal_error.set(Some(err.user_message()));
                }
            }
        });
    };

    let confirm_selected_order = move || {
        if confirming_order.get_untracked() {
            return;
        }
        let Some(tok) = portal_token.get_untracked() else {
            return;
        };
        let Some((order_id, revision)) =
            selected_order.with_untracked(|o| o.as_ref().map(|d| (d.order.id, d.order.revision)))
        else {
            return;
        };
        let note = confirm_note.get_untracked().trim().to_string();
        let base = base_url.get_untracked();
        let client = portal_client(&base, Some(&tok));

        confirming_order.set(true);
        portal_error.set(None);
        portal_notice.set(None);
        spawn_local(async move {
            let req = ConfirmPortalOrder { revision, note };
            match client.confirm_portal_order(order_id, &req).await {
                Ok(detail) => {
                    confirming_order.set(false);
                    confirm_note.set(String::new());
                    portal_notice.set(Some(format!(
                        "Order {} (rev {}) confirmed.",
                        detail.order.number, detail.order.revision
                    )));
                    selected_order.set(Some(detail));
                    refresh_portal_data();
                }
                Err(err) => {
                    confirming_order.set(false);
                    portal_error.set(Some(err.user_message()));
                }
            }
        });
    };

    let sign_out_portal = move |_| {
        portal_token.set(None);
        portal_profile.set(None);
        tickets.set(Vec::new());
        selected_ticket.set(None);
        orders.set(Vec::new());
        selected_order.set(None);
        portal_error.set(None);
        portal_notice.set(None);
    };

    let is_signed_in = Memo::new(move |_| portal_token.with(Option::is_some));

    view! {
        <div data-target="portal-page">
            <div class="tc-page-header">
                <div>
                    <h1 class="tc-page-title">"Customer Portal"</h1>
                    <p class="tc-page-subtitle" data-target="portal-profile">
                        {move || match portal_profile.get() {
                            Some(p) => format!(
                                "{} · {} (scope: {})",
                                p.full_name, p.customer_name, p.scope
                            ),
                            None => "Passwordless customer portal sign-in, tickets & orders".to_string(),
                        }}
                    </p>
                </div>
                <Show when=move || is_signed_in.get()>
                    <div class="tc-header-actions">
                        <button
                            type="button"
                            class="tc-btn"
                            data-target="portal-refresh"
                            disabled=move || loading_data.get()
                            on:click=move |_| refresh_portal_data()
                        >
                            {move || if loading_data.get() { "Loading..." } else { "Refresh" }}
                        </button>
                        <button
                            type="button"
                            class="tc-btn tc-btn-ghost"
                            data-target="portal-signout"
                            on:click=sign_out_portal
                        >
                            "Sign out"
                        </button>
                    </div>
                </Show>
            </div>

            <Show
                when=move || is_signed_in.get()
                fallback=move || view! {
                    <div style="display: flex; flex-direction: column; gap: var(--space-lg); max-width: 820px;">
                        {move || auth_error.get().map(|msg| view! {
                            <div class="tc-alert-error" role="alert" data-target="portal-auth-error">
                                {msg}
                            </div>
                        })}
                        {move || link_notice.get().map(|msg| view! {
                            <div class="tc-alert-success" role="status" data-target="portal-link-notice">
                                {msg}
                            </div>
                        })}

                        <div class="tc-form-grid">
                            <form
                                class="tc-card"
                                style="display: flex; flex-direction: column; gap: var(--space-md);"
                                data-target="portal-login-form"
                                on:submit=on_request_login_link
                            >
                                <h2 class="tc-page-title" style="font-size: 16px;">
                                    "1. Request login link"
                                </h2>
                                <div class="tc-field">
                                    <label class="tc-label" for="portal-base-url">"API Base URL"</label>
                                    <input
                                        id="portal-base-url"
                                        data-target="portal-base-url"
                                        class="tc-input tc-mono"
                                        type="text"
                                        placeholder="Leave empty for same-origin /api"
                                        prop:value=move || base_url.get()
                                        on:input=move |ev| base_url.set(event_target_value(&ev))
                                    />
                                </div>
                                <div class="tc-field">
                                    <label class="tc-label" for="portal-company-id">"Company ID *"</label>
                                    <input
                                        id="portal-company-id"
                                        data-target="portal-company-id"
                                        class="tc-input tc-mono"
                                        type="text"
                                        placeholder="00000000-0000-0000-0000-000000000000"
                                        prop:value=move || company_id_input.get()
                                        on:input=move |ev| company_id_input.set(event_target_value(&ev))
                                    />
                                </div>
                                <div class="tc-field">
                                    <label class="tc-label" for="portal-login-email">"Contact email *"</label>
                                    <input
                                        id="portal-login-email"
                                        data-target="portal-login-email"
                                        class="tc-input"
                                        type="email"
                                        placeholder="contact@customer.example"
                                        prop:value=move || login_email.get()
                                        on:input=move |ev| login_email.set(event_target_value(&ev))
                                    />
                                </div>
                                <div class="tc-form-actions">
                                    <button
                                        type="submit"
                                        class="tc-btn tc-btn-primary"
                                        data-target="portal-login-submit"
                                        disabled=move || link_busy.get()
                                    >
                                        {move || if link_busy.get() { "Sending..." } else { "Send login link" }}
                                    </button>
                                </div>
                            </form>

                            <form
                                class="tc-card"
                                style="display: flex; flex-direction: column; gap: var(--space-md);"
                                data-target="portal-session-form"
                                on:submit=on_exchange_session
                            >
                                <h2 class="tc-page-title" style="font-size: 16px;">
                                    "2. Exchange link token"
                                </h2>
                                <p class="tc-page-subtitle" style="margin: 0;">
                                    "Paste the one-time token from your email link (POST /api/v1/portal/sessions)."
                                </p>
                                <div class="tc-field">
                                    <label class="tc-label" for="portal-session-token">"Login token *"</label>
                                    <input
                                        id="portal-session-token"
                                        data-target="portal-session-token"
                                        class="tc-input tc-mono"
                                        type="text"
                                        placeholder="pll_..."
                                        prop:value=move || session_token_input.get()
                                        on:input=move |ev| session_token_input.set(event_target_value(&ev))
                                    />
                                </div>
                                <div class="tc-form-actions" style="margin-top: auto;">
                                    <button
                                        type="submit"
                                        class="tc-btn tc-btn-primary"
                                        data-target="portal-session-submit"
                                        disabled=move || session_busy.get()
                                    >
                                        {move || if session_busy.get() { "Signing in..." } else { "Start portal session" }}
                                    </button>
                                </div>
                            </form>
                        </div>
                    </div>
                }
            >
                <div style="display: flex; flex-direction: column; gap: var(--space-xl);">
                    {move || portal_error.get().map(|msg| view! {
                        <div class="tc-alert-error" role="alert" data-target="portal-error">
                            {msg}
                        </div>
                    })}
                    {move || portal_notice.get().map(|msg| view! {
                        <div class="tc-alert-success" role="status" data-target="portal-notice">
                            {msg}
                        </div>
                    })}

                    // -------------------------------------------------------------------------
                    // Portal Orders
                    // -------------------------------------------------------------------------
                    <section style="display: flex; flex-direction: column; gap: var(--space-md);">
                        <div class="tc-page-header" style="margin-bottom: 0;">
                            <div>
                                <h2 class="tc-page-title" style="font-size: 18px;">"Orders"</h2>
                                <p class="tc-page-subtitle">
                                    {move || format!("{} orders available", orders.with(Vec::len))}
                                </p>
                            </div>
                        </div>

                        <div class=move || {
                            if selected_order.with(Option::is_some) {
                                "tc-workspace-split"
                            } else {
                                ""
                            }
                        }>
                            <div class="tc-table-wrap" data-target="portal-orders-list">
                                <table class="tc-table">
                                    <thead>
                                        <tr>
                                            <th>"Order"</th>
                                            <th>"Rev"</th>
                                            <th>"Reference"</th>
                                            <th>"Date"</th>
                                            <th>"Status"</th>
                                            <th class="tc-num">"Total"</th>
                                            <th>"Action"</th>
                                        </tr>
                                    </thead>
                                    <tbody>
                                        <Show
                                            when=move || !orders.with(Vec::is_empty)
                                            fallback=|| view! {
                                                <tr>
                                                    <td colspan="7" style="text-align: center; color: var(--on-surface-variant); padding: var(--space-lg);">
                                                        "No portal orders yet."
                                                    </td>
                                                </tr>
                                            }
                                        >
                                            <For
                                                each=move || orders.get()
                                                key=|o| (o.id, o.revision, o.status.clone(), o.can_confirm)
                                                children=move |order| {
                                                    let order_id = order.id;
                                                    let status_class = match order.status.as_str() {
                                                        "confirmed" => "tc-badge tc-badge-success",
                                                        "cancelled" => "tc-badge tc-badge-error",
                                                        _ => "tc-badge tc-badge-primary",
                                                    };
                                                    let order_row_target = format!("portal-order-row-{}", order.number);
                                                    view! {
                                                        <tr
                                                            class=move || {
                                                                if selected_order.with(|d| d.as_ref().is_some_and(|x| x.order.id == order_id)) {
                                                                    "tc-row-clickable tc-row-selected"
                                                                } else {
                                                                    "tc-row-clickable"
                                                                }
                                                            }
                                                            data-target=order_row_target
                                                            on:click=move |_| open_order(order_id)
                                                        >
                                                            <td class="tc-mono">{order.number}</td>
                                                            <td class="tc-mono">{format!("r{}", order.revision)}</td>
                                                            <td>{order.customer_reference}</td>
                                                            <td class="tc-mono">{order.order_date.to_string()}</td>
                                                            <td><span class=status_class>{order.status}</span></td>
                                                            <td class="tc-num tc-mono">{format!("{} {}", order.total, order.currency)}</td>
                                                            <td>
                                                                {if order.can_confirm {
                                                                    view! { <span class="tc-badge tc-badge-warning">"Awaiting confirm"</span> }.into_any()
                                                                } else {
                                                                    view! { <span class="tc-badge">"View"</span> }.into_any()
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

                            {move || selected_order.get().map(|detail| {
                                let ord = detail.order;
                                let lines = detail.lines;
                                view! {
                                    <aside class="tc-card tc-detail-drawer" data-target="portal-order-detail">
                                        <div class="tc-page-header" style="margin-bottom: 0;">
                                            <div>
                                                <h3 class="tc-page-title" style="font-size: 16px;">
                                                    {format!("{} (rev {})", ord.number, ord.revision)}
                                                </h3>
                                                <p class="tc-page-subtitle">
                                                    {if loading_order.get() {
                                                        "Loading order...".to_string()
                                                    } else {
                                                        format!("Status: {} · Date: {}", ord.status, ord.order_date)
                                                    }}
                                                </p>
                                            </div>
                                            <button
                                                type="button"
                                                class="tc-btn tc-btn-sm tc-btn-ghost"
                                                on:click=move |_| selected_order.set(None)
                                            >
                                                "Close"
                                            </button>
                                        </div>

                                        <div class="tc-table-wrap">
                                            <table class="tc-table">
                                                <thead>
                                                    <tr>
                                                        <th>"Code"</th>
                                                        <th>"Qty"</th>
                                                        <th class="tc-num">"Net"</th>
                                                        <th class="tc-num">"Total"</th>
                                                    </tr>
                                                </thead>
                                                <tbody>
                                                    {lines.into_iter().map(|line| view! {
                                                        <tr>
                                                            <td class="tc-mono">{line.product_code}</td>
                                                            <td class="tc-mono">{format!("{} {}", line.quantity, line.unit)}</td>
                                                            <td class="tc-num tc-mono">{line.net_unit_price.to_string()}</td>
                                                            <td class="tc-num tc-mono">{line.line_total.to_string()}</td>
                                                        </tr>
                                                    }).collect_view()}
                                                </tbody>
                                            </table>
                                        </div>

                                        <div style="display: flex; justify-content: space-between; font-size: 13px;">
                                            <span style="color: var(--on-surface-variant);">
                                                {format!("Subtotal {} + VAT {}", ord.subtotal, ord.vat_total)}
                                            </span>
                                            <strong class="tc-mono">
                                                {format!("{} {}", ord.total, ord.currency)}
                                            </strong>
                                        </div>

                                        {ord.can_confirm.then(|| view! {
                                            <div style="display: flex; flex-direction: column; gap: var(--space-sm); border-top: 1px solid var(--outline-variant); padding-top: var(--space-md);">
                                                <div class="tc-field">
                                                    <label class="tc-label" for="portal-order-confirm-note">"Confirmation note (optional)"</label>
                                                    <input
                                                        id="portal-order-confirm-note"
                                                        data-target="portal-order-confirm-note"
                                                        class="tc-input"
                                                        type="text"
                                                        placeholder="PO reference or delivery note"
                                                        prop:value=move || confirm_note.get()
                                                        on:input=move |ev| confirm_note.set(event_target_value(&ev))
                                                    />
                                                </div>
                                                <div class="tc-form-actions" style="border-top: none; padding-top: 0;">
                                                    <button
                                                        type="button"
                                                        class="tc-btn tc-btn-primary"
                                                        data-target="portal-order-confirm"
                                                        disabled=move || confirming_order.get()
                                                        on:click=move |_| confirm_selected_order()
                                                    >
                                                        {move || if confirming_order.get() { "Confirming..." } else { "Confirm order" }}
                                                    </button>
                                                </div>
                                            </div>
                                        })}
                                    </aside>
                                }
                            })}
                        </div>
                    </section>

                    // -------------------------------------------------------------------------
                    // Portal Tickets
                    // -------------------------------------------------------------------------
                    <section style="display: flex; flex-direction: column; gap: var(--space-md);">
                        <div class="tc-page-header" style="margin-bottom: 0;">
                            <div>
                                <h2 class="tc-page-title" style="font-size: 18px;">"Support Tickets"</h2>
                                <p class="tc-page-subtitle">
                                    {move || format!("{} tickets visible", tickets.with(Vec::len))}
                                </p>
                            </div>
                        </div>

                        <div class="tc-workspace-split">
                            <div style="display: flex; flex-direction: column; gap: var(--space-md);">
                                <div class="tc-table-wrap" data-target="portal-tickets-list">
                                    <table class="tc-table">
                                        <thead>
                                            <tr>
                                                <th>"Number"</th>
                                                <th>"Subject"</th>
                                                <th>"Category"</th>
                                                <th>"Status"</th>
                                                <th>"Updated"</th>
                                            </tr>
                                        </thead>
                                        <tbody>
                                            <Show
                                                when=move || !tickets.with(Vec::is_empty)
                                                fallback=|| view! {
                                                    <tr>
                                                        <td colspan="5" style="text-align: center; color: var(--on-surface-variant); padding: var(--space-lg);">
                                                            "No tickets yet."
                                                        </td>
                                                    </tr>
                                                }
                                            >
                                                <For
                                                    each=move || tickets.get()
                                                    key=|t| (t.id, t.status.clone(), t.updated_at)
                                                    children=move |ticket| {
                                                        let ticket_id = ticket.id;
                                                        let status_class = match ticket.status.as_str() {
                                                            "closed" => "tc-badge",
                                                            "pending_customer" => "tc-badge tc-badge-warning",
                                                            _ => "tc-badge tc-badge-primary",
                                                        };
                                                        let ticket_row_target = format!("portal-ticket-row-{}", ticket.number);
                                                        view! {
                                                            <tr
                                                                class=move || {
                                                                    if selected_ticket.with(|d| d.as_ref().is_some_and(|x| x.ticket.id == ticket_id)) {
                                                                        "tc-row-clickable tc-row-selected"
                                                                    } else {
                                                                        "tc-row-clickable"
                                                                    }
                                                                }
                                                                data-target=ticket_row_target
                                                                on:click=move |_| open_ticket(ticket_id)
                                                            >
                                                                <td class="tc-mono">{ticket.number}</td>
                                                                <td>{ticket.subject}</td>
                                                                <td>{ticket.category}</td>
                                                                <td><span class=status_class>{ticket.status}</span></td>
                                                                <td class="tc-mono">{ticket.updated_at.date_naive().to_string()}</td>
                                                            </tr>
                                                        }
                                                    }
                                                />
                                            </Show>
                                        </tbody>
                                    </table>
                                </div>

                                <form
                                    class="tc-card"
                                    style="display: flex; flex-direction: column; gap: var(--space-md);"
                                    data-target="portal-ticket-create"
                                    on:submit=on_create_ticket
                                >
                                    <h3 class="tc-page-title" style="font-size: 15px;">"Open a new ticket"</h3>
                                    <div class="tc-form-grid">
                                        <div class="tc-field">
                                            <label class="tc-label" for="portal-ticket-subject">"Subject *"</label>
                                            <input
                                                id="portal-ticket-subject"
                                                data-target="portal-ticket-subject"
                                                class="tc-input"
                                                type="text"
                                                placeholder="Short summary of your question"
                                                prop:value=move || new_ticket_subject.get()
                                                on:input=move |ev| new_ticket_subject.set(event_target_value(&ev))
                                            />
                                        </div>
                                        <div class="tc-field">
                                            <label class="tc-label" for="portal-ticket-category">"Category"</label>
                                            <select
                                                id="portal-ticket-category"
                                                data-target="portal-ticket-category"
                                                class="tc-select"
                                                prop:value=move || new_ticket_category.get()
                                                on:change=move |ev| new_ticket_category.set(event_target_value(&ev))
                                            >
                                                <option value="question">"Question"</option>
                                                <option value="service">"Service"</option>
                                                <option value="complaint">"Complaint"</option>
                                                <option value="other">"Other"</option>
                                            </select>
                                        </div>
                                        <div class="tc-field tc-form-span-2">
                                            <label class="tc-label" for="portal-ticket-body">"Message *"</label>
                                            <textarea
                                                id="portal-ticket-body"
                                                data-target="portal-ticket-body"
                                                class="tc-input"
                                                style="min-height: 88px; resize: vertical; font-family: inherit; font-size: 13px;"
                                                placeholder="Describe what you need help with..."
                                                prop:value=move || new_ticket_body.get()
                                                on:input=move |ev| new_ticket_body.set(event_target_value(&ev))
                                            />
                                        </div>
                                    </div>
                                    <div class="tc-form-actions">
                                        <button
                                            type="submit"
                                            class="tc-btn tc-btn-primary"
                                            data-target="portal-ticket-submit"
                                            disabled=move || creating_ticket.get()
                                        >
                                            {move || if creating_ticket.get() { "Submitting..." } else { "Create ticket" }}
                                        </button>
                                    </div>
                                </form>
                            </div>

                            <aside class="tc-card tc-detail-drawer" data-target="portal-ticket-detail">
                                <Show
                                    when=move || selected_ticket.with(Option::is_some)
                                    fallback=move || view! {
                                        <p style="margin: 0; color: var(--on-surface-variant);">
                                            {move || if loading_ticket.get() {
                                                "Loading ticket thread..."
                                            } else {
                                                "Select a ticket to read messages and post a reply."
                                            }}
                                        </p>
                                    }
                                >
                                    {move || selected_ticket.get().map(|detail| {
                                        let ticket = detail.ticket;
                                        let messages = detail.messages;
                                        view! {
                                            <div class="tc-page-header" style="margin-bottom: 0;">
                                                <div>
                                                    <h3 class="tc-page-title" style="font-size: 16px;">
                                                        {format!("{} · {}", ticket.number, ticket.subject)}
                                                    </h3>
                                                    <p class="tc-page-subtitle">
                                                        {format!("{} · {} · {}", ticket.status, ticket.category, ticket.contact_name)}
                                                    </p>
                                                </div>
                                                <button
                                                    type="button"
                                                    class="tc-btn tc-btn-sm tc-btn-ghost"
                                                    on:click=move |_| selected_ticket.set(None)
                                                >
                                                    "Close"
                                                </button>
                                            </div>

                                            <div style="display: flex; flex-direction: column; gap: var(--space-sm);">
                                                {messages.into_iter().map(|m| {
                                                    let is_incoming = m.direction == "incoming";
                                                    view! {
                                                        <div
                                                            style="padding: var(--space-sm) var(--space-md); border-radius: var(--radius-sm); border: 1px solid var(--outline-variant); background: var(--surface);"
                                                        >
                                                            <div style="display: flex; justify-content: space-between; font-size: 11px; color: var(--on-surface-variant); margin-bottom: 4px;">
                                                                <strong>
                                                                    {if is_incoming {
                                                                        format!("{} (You)", m.author_name)
                                                                    } else {
                                                                        format!("{} (Support)", m.author_name)
                                                                    }}
                                                                </strong>
                                                                <span class="tc-mono">{format!("{} {}", m.created_at.date_naive(), m.created_at.time())}</span>
                                                            </div>
                                                            <div style="white-space: pre-wrap; font-size: 13px;">{m.body}</div>
                                                        </div>
                                                    }
                                                }).collect_view()}
                                            </div>

                                            <form
                                                data-target="portal-ticket-reply"
                                                on:submit=on_send_reply
                                                style="display: flex; flex-direction: column; gap: var(--space-sm); border-top: 1px solid var(--outline-variant); padding-top: var(--space-md);"
                                            >
                                                <div class="tc-field">
                                                    <label class="tc-label" for="portal-reply-body">"Reply"</label>
                                                    <textarea
                                                        id="portal-reply-body"
                                                        data-target="portal-reply-body"
                                                        class="tc-input"
                                                        style="min-height: 76px; resize: vertical; font-family: inherit; font-size: 13px;"
                                                        placeholder="Write a reply (reopens closed tickets)..."
                                                        prop:value=move || reply_body.get()
                                                        on:input=move |ev| reply_body.set(event_target_value(&ev))
                                                    />
                                                </div>
                                                <div class="tc-form-actions" style="border-top: none; padding-top: 0;">
                                                    <button
                                                        type="submit"
                                                        class="tc-btn tc-btn-primary"
                                                        data-target="portal-reply-submit"
                                                        disabled=move || sending_reply.get()
                                                    >
                                                        {move || if sending_reply.get() { "Sending..." } else { "Send reply" }}
                                                    </button>
                                                </div>
                                            </form>
                                        }
                                    })}
                                </Show>
                            </aside>
                        </div>
                    </section>
                </div>
            </Show>
        </div>
    }
}
