use leptos::ev::SubmitEvent;
use leptos::prelude::*;
use leptos::task::spawn_local;
use leptos_router::components::A;
use tradocraft_api_client::helpdesk::{
    AnswerText, CreateTicketInput, EscalateInput, ListPreparedAnswersParams, ListTicketsParams,
    NoteInput, PreparedAnswer, ReplyInput, TagInput, TicketDetail, TicketPage, TicketStatusInput,
    TicketSummary, TicketTimeEntries, TimeEntryInput, UpdateTicketInput,
};
use tradocraft_api_client::{ApiError, Client};
use uuid::Uuid;

use crate::api::{
    resolve_base_url, ApiClient, ConnectionMode, Customer, ListCustomersParams, WebApiClient,
};
use crate::pages::{opt_trimmed, parse_i32, parse_uuid};
use crate::state::AppContext;

const TICKET_STATUSES: &[(&str, &str)] = &[
    ("new", "New"),
    ("open", "Open"),
    ("pending_customer", "Pending customer"),
    ("pending_internal", "Pending internal"),
    ("closed", "Closed"),
];

const TICKET_PRIORITIES: &[(&str, &str)] = &[
    ("low", "Low"),
    ("normal", "Normal"),
    ("high", "High"),
    ("urgent", "Urgent"),
];

const TICKET_CATEGORIES: &[(&str, &str)] = &[
    ("question", "Question"),
    ("lead", "Lead"),
    ("quote_change", "Quote change"),
    ("order_confirmation", "Order confirmation"),
    ("production_question", "Production question"),
    ("service", "Service"),
    ("complaint", "Complaint"),
    ("other", "Other"),
];

const TICKET_LANGUAGES: &[(&str, &str)] = &[
    ("en", "English (en)"),
    ("nl", "Nederlands (nl)"),
    ("fr", "Français (fr)"),
    ("de", "Deutsch (de)"),
    ("es", "Español (es)"),
];

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum DrawerSection {
    Thread,
    TagsTime,
    Escalate,
    Properties,
}

#[derive(Debug, Clone, PartialEq)]
struct TicketTab {
    tab_id: String,
    ticket_id: Option<Uuid>,
    title: String,
    section: DrawerSection,
    summary: Option<TicketSummary>,
    detail: Option<TicketDetail>,
    time_entries: Option<TicketTimeEntries>,
    loading_detail: bool,
    busy: bool,
    error: Option<String>,
    notice: Option<String>,
    // New ticket fields
    new_subject: String,
    new_category: String,
    new_customer_id: String,
    new_contact_name: String,
    new_contact_email: String,
    new_language: String,
    new_internal: bool,
    new_body: String,
    // Quick status
    quick_status: String,
    // Thread: reply & internal note
    reply_subject: String,
    reply_body: String,
    reply_status: String,
    note_body: String,
    // Tags & Time
    tag_input: String,
    time_minutes: String,
    time_billable: bool,
    time_note: String,
    // Escalate
    escalate_reason: String,
    escalate_raise_priority: bool,
    escalate_to_user: String,
    escalate_to_team: String,
    // Properties
    prop_subject: String,
    prop_status: String,
    prop_priority: String,
    prop_category: String,
    prop_language: String,
    prop_customer_id: String,
    prop_contact_name: String,
    prop_contact_email: String,
}

impl TicketTab {
    fn new_draft(default_customer_id: &str) -> Self {
        Self {
            tab_id: "new".to_string(),
            ticket_id: None,
            title: "New Ticket".to_string(),
            section: DrawerSection::Thread,
            summary: None,
            detail: None,
            time_entries: None,
            loading_detail: false,
            busy: false,
            error: None,
            notice: None,
            new_subject: String::new(),
            new_category: "question".to_string(),
            new_customer_id: default_customer_id.to_string(),
            new_contact_name: String::new(),
            new_contact_email: String::new(),
            new_language: String::new(),
            new_internal: false,
            new_body: String::new(),
            quick_status: "new".to_string(),
            reply_subject: String::new(),
            reply_body: String::new(),
            reply_status: "pending_customer".to_string(),
            note_body: String::new(),
            tag_input: String::new(),
            time_minutes: "15".to_string(),
            time_billable: false,
            time_note: String::new(),
            escalate_reason: String::new(),
            escalate_raise_priority: false,
            escalate_to_user: String::new(),
            escalate_to_team: String::new(),
            prop_subject: String::new(),
            prop_status: "new".to_string(),
            prop_priority: "normal".to_string(),
            prop_category: "question".to_string(),
            prop_language: "en".to_string(),
            prop_customer_id: String::new(),
            prop_contact_name: String::new(),
            prop_contact_email: String::new(),
        }
    }

    fn from_summary(summary: &TicketSummary, loading_detail: bool) -> Self {
        let mut tab = Self::new_draft("");
        tab.tab_id = format!("ticket:{}", summary.id);
        tab.ticket_id = Some(summary.id);
        tab.title = format!("{} · {}", summary.number, summary.subject);
        tab.summary = Some(summary.clone());
        tab.loading_detail = loading_detail;
        tab.sync_properties_from_summary(summary);
        tab
    }

    fn sync_properties_from_summary(&mut self, t: &TicketSummary) {
        self.quick_status = t.status.clone();
        self.prop_subject = t.subject.clone();
        self.prop_status = t.status.clone();
        self.prop_priority = t.priority.clone();
        self.prop_category = t.category.clone();
        self.prop_language = t.language.clone();
        self.prop_customer_id = t.customer_id.map(|id| id.to_string()).unwrap_or_default();
        self.prop_contact_name = t.contact_name.clone();
        self.prop_contact_email = t.contact_email.clone();
    }

    fn apply_detail(&mut self, detail: &TicketDetail, notice: Option<String>) {
        self.tab_id = format!("ticket:{}", detail.ticket.id);
        self.ticket_id = Some(detail.ticket.id);
        self.title = format!("{} · {}", detail.ticket.number, detail.ticket.subject);
        self.summary = Some(detail.ticket.clone());
        self.detail = Some(detail.clone());
        self.loading_detail = false;
        self.busy = false;
        self.error = None;
        self.notice = notice;
        self.sync_properties_from_summary(&detail.ticket);
    }

    fn current_ticket(&self) -> Option<&TicketSummary> {
        self.detail
            .as_ref()
            .map(|d| &d.ticket)
            .or(self.summary.as_ref())
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
            "Helpdesk endpoints require a live API connection; switch to Dev User or Bearer mode on the sign-in screen."
                .to_string(),
        )),
    }
}

fn parse_opt_uuid(label: &str, raw: &str) -> Result<Option<Uuid>, String> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return Ok(None);
    }
    parse_uuid(label, trimmed).map(Some)
}

fn read_ticket_tab<R>(
    tabs: &RwSignal<Vec<TicketTab>>,
    tab_id: &str,
    f: impl FnOnce(&TicketTab) -> R,
) -> Option<R> {
    tabs.with(|list| list.iter().find(|t| t.tab_id == tab_id).map(f))
}

fn update_ticket_tab(
    tabs: &RwSignal<Vec<TicketTab>>,
    tab_id: &str,
    f: impl FnOnce(&mut TicketTab),
) {
    tabs.update(|list| {
        if let Some(tab) = list.iter_mut().find(|t| t.tab_id == tab_id) {
            f(tab);
        }
    });
}

fn close_ticket_tab(
    tabs: &RwSignal<Vec<TicketTab>>,
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

fn ticket_status_badge_class(status: &str) -> &'static str {
    match status {
        "new" => "tc-badge tc-badge-primary",
        "open" => "tc-badge tc-badge-warning",
        "pending_customer" | "pending_internal" => "tc-badge",
        "closed" => "tc-badge tc-badge-success",
        _ => "tc-badge",
    }
}

fn priority_badge_class(priority: &str) -> &'static str {
    match priority {
        "urgent" => "tc-badge tc-badge-error",
        "high" => "tc-badge tc-badge-warning",
        "normal" => "tc-badge tc-badge-primary",
        _ => "tc-badge",
    }
}

fn sla_badge_class(state: &str) -> &'static str {
    match state {
        "breached" => "tc-badge tc-badge-error",
        "at_risk" => "tc-badge tc-badge-warning",
        "on_time" => "tc-badge tc-badge-success",
        _ => "tc-badge",
    }
}

fn article_kind_badge_class(kind: &str) -> &'static str {
    match kind {
        "note" => "tc-badge tc-badge-warning",
        "email_out" | "call_out" => "tc-badge tc-badge-primary",
        "email_in" | "portal_in" | "call_in" => "tc-badge tc-badge-success",
        _ => "tc-badge",
    }
}

fn pick_answer_text<'a>(answer: &'a PreparedAnswer, language: &str) -> Option<&'a AnswerText> {
    answer
        .texts
        .iter()
        .find(|t| t.language.eq_ignore_ascii_case(language))
        .or_else(|| answer.texts.iter().find(|t| t.language == "en"))
        .or_else(|| answer.texts.first())
}

#[component]
pub fn HelpdeskPage() -> impl IntoView {
    let ctx = expect_context::<AppContext>();

    let search = RwSignal::new(String::new());
    let status_filter = RwSignal::new(String::new());

    let loading = RwSignal::new(false);
    let error = RwSignal::new(Option::<String>::None);
    let items = RwSignal::new(Vec::<TicketSummary>::new());
    let total = RwSignal::new(0_i64);
    let reload_nonce = RwSignal::new(0_u64);

    let customers = RwSignal::new(Vec::<Customer>::new());
    let prepared_answers = RwSignal::new(Vec::<PreparedAnswer>::new());

    let open_tabs = RwSignal::new(Vec::<TicketTab>::new());
    let active_tab_id = RwSignal::new(Option::<String>::None);

    let fetch_tickets = move |connection: ConnectionMode, params: ListTicketsParams| {
        loading.set(true);
        error.set(None);
        spawn_local(async move {
            let result: Result<TicketPage, ApiError> = match live_client(&connection) {
                Ok(client) => client.list_tickets(&params).await,
                Err(err) => Err(err),
            };
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

    // Load customers and prepared answers when session starts.
    Effect::new(move |_| {
        let Some(session) = ctx.session.get() else {
            customers.set(Vec::new());
            prepared_answers.set(Vec::new());
            return;
        };
        let connection = session.connection;
        spawn_local(async move {
            let cust_params = ListCustomersParams::new().active(true).limit(200);
            if let Ok(page) = WebApiClient.list_customers(&connection, &cust_params).await {
                customers.set(page.items);
            }
            if let Ok(client) = live_client(&connection) {
                let ans_params = ListPreparedAnswersParams::new().active(true);
                if let Ok(list) = client.list_prepared_answers(&ans_params).await {
                    prepared_answers.set(list);
                }
            }
        });
    });

    // Reload ticket list whenever filters or reload_nonce change.
    Effect::new(move |_| {
        let _ = reload_nonce.get();
        let active_session = ctx.session.get();
        let q = search.get();
        let status = status_filter.get();

        let Some(session) = active_session else {
            items.set(Vec::new());
            total.set(0);
            error.set(None);
            open_tabs.set(Vec::new());
            active_tab_id.set(None);
            return;
        };

        let params = ListTicketsParams {
            q: (!q.trim().is_empty()).then_some(q),
            status: (!status.trim().is_empty()).then_some(status),
            limit: Some(50),
            offset: Some(0),
            ..ListTicketsParams::default()
        };
        fetch_tickets(session.connection, params);
    });

    let is_signed_in = Memo::new(move |_| ctx.session.with(|s| s.is_some()));

    let on_create_click = move |_| {
        let default_customer = customers
            .with_untracked(|list| list.first().map(|c| c.id.to_string()))
            .unwrap_or_default();
        open_tabs.update(|list| {
            if !list.iter().any(|t| t.tab_id == "new") {
                list.push(TicketTab::new_draft(&default_customer));
            }
        });
        active_tab_id.set(Some("new".to_string()));
    };

    let open_ticket_row = move |summary: TicketSummary| {
        let tab_id = format!("ticket:{}", summary.id);
        let already_open = open_tabs.with_untracked(|list| list.iter().any(|t| t.tab_id == tab_id));
        if !already_open {
            open_tabs.update(|list| list.push(TicketTab::from_summary(&summary, true)));
        }
        active_tab_id.set(Some(tab_id.clone()));

        if let Some(session) = ctx.session.get_untracked() {
            let connection = session.connection;
            let ticket_id = summary.id;
            spawn_local(async move {
                let client = match live_client(&connection) {
                    Ok(c) => c,
                    Err(err) => {
                        update_ticket_tab(&open_tabs, &tab_id, |tab| {
                            tab.loading_detail = false;
                            tab.error = Some(err.user_message());
                        });
                        return;
                    }
                };
                match client.get_ticket(ticket_id).await {
                    Ok(fresh) => {
                        update_ticket_tab(&open_tabs, &tab_id, |tab| {
                            tab.apply_detail(&fresh, None);
                        });
                    }
                    Err(err) => {
                        update_ticket_tab(&open_tabs, &tab_id, |tab| {
                            tab.loading_detail = false;
                            if tab.error.is_none() {
                                tab.error = Some(err.user_message());
                            }
                        });
                    }
                }
                if let Ok(entries) = client.list_ticket_time_entries(ticket_id).await {
                    update_ticket_tab(&open_tabs, &tab_id, |tab| {
                        tab.time_entries = Some(entries);
                    });
                }
            });
        }
    };

    view! {
        <div data-target="helpdesk-page">
            <div class="tc-page-header">
                <div>
                    <h1 class="tc-page-title">"Helpdesk"</h1>
                    <p class="tc-page-subtitle" data-target="helpdesk-total">
                        {move || format!("Support tickets ({} total)", total.get())}
                    </p>
                </div>
                <div class="tc-header-actions">
                    <button
                        type="button"
                        data-target="helpdesk-create"
                        class="tc-btn tc-btn-primary"
                        disabled=move || !is_signed_in.get()
                        on:click=on_create_click
                    >
                        "+ New Ticket"
                    </button>
                    <button
                        type="button"
                        data-target="helpdesk-refresh"
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
                            "Sign in to load support tickets from GET /api/v1/tickets."
                        </p>
                        <A href=crate::components::shell::app_href("/login") attr:class="tc-btn tc-btn-primary" attr:data-target="helpdesk-go-login">
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
                                data-target="helpdesk-search"
                                class="tc-input"
                                style="min-width: 240px;"
                                type="search"
                                placeholder="Search number, subject, contact or customer..."
                                prop:value=move || search.get()
                                on:input=move |ev| search.set(event_target_value(&ev))
                            />
                            <select
                                data-target="helpdesk-status-filter"
                                class="tc-select"
                                prop:value=move || status_filter.get()
                                on:change=move |ev| status_filter.set(event_target_value(&ev))
                            >
                                <option value="">"All statuses"</option>
                                <option value="active">"Active (not closed)"</option>
                                <option value="new">"New"</option>
                                <option value="open">"Open"</option>
                                <option value="pending_customer">"Pending customer"</option>
                                <option value="pending_internal">"Pending internal"</option>
                                <option value="closed">"Closed"</option>
                            </select>
                        </div>

                        {move || error.get().map(|msg| view! {
                            <div class="tc-alert-error" style="margin-bottom: var(--space-md);" role="alert" data-target="helpdesk-error">
                                {msg}
                            </div>
                        })}

                        <div class="tc-table-wrap">
                            <table class="tc-table" data-target="helpdesk-table">
                                <thead>
                                    <tr>
                                        <th>"Number"</th>
                                        <th>"Subject"</th>
                                        <th>"Customer / Contact"</th>
                                        <th>"Category"</th>
                                        <th>"Priority"</th>
                                        <th>"SLA"</th>
                                        <th>"Updated"</th>
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
                                                        "Loading tickets..."
                                                    } else {
                                                        "No tickets match the current filter."
                                                    }}
                                                </td>
                                            </tr>
                                        }
                                    >
                                        <For
                                            each=move || items.get()
                                            key=|t| (t.id, t.version, t.status.clone(), t.priority.clone(), t.updated_at)
                                            children=move |summary| {
                                                let open_summary = summary.clone();
                                                let row_tab_id = format!("ticket:{}", summary.id);
                                                let row_target = format!("ticket-row-{}", summary.number);
                                                let status_cls = ticket_status_badge_class(&summary.status);
                                                let prio_cls = priority_badge_class(&summary.priority);
                                                let sla_cls = sla_badge_class(&summary.sla.state);
                                                let updated_date = summary.updated_at.date_naive().to_string();
                                                let customer_label = summary
                                                    .customer_name
                                                    .clone()
                                                    .filter(|s| !s.trim().is_empty())
                                                    .unwrap_or_else(|| {
                                                        if summary.internal {
                                                            "Internal".to_string()
                                                        } else {
                                                            "—".to_string()
                                                        }
                                                    });
                                                let contact_label = if !summary.contact_name.trim().is_empty() {
                                                    summary.contact_name.clone()
                                                } else {
                                                    summary.contact_email.clone()
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
                                                        title="Open ticket detail drawer"
                                                        on:click=move |_| open_ticket_row(open_summary.clone())
                                                    >
                                                        <td class="tc-mono">{summary.number}</td>
                                                        <td>
                                                            <div style="font-weight: 600;">{summary.subject}</div>
                                                            {(!summary.tags.is_empty()).then(|| view! {
                                                                <div style="font-size: 11px; color: var(--on-surface-variant);">
                                                                    {summary.tags.join(", ")}
                                                                </div>
                                                            })}
                                                        </td>
                                                        <td>
                                                            <div>{customer_label}</div>
                                                            {(!contact_label.trim().is_empty()).then(|| view! {
                                                                <div style="font-size: 11px; color: var(--on-surface-variant);">{contact_label}</div>
                                                            })}
                                                        </td>
                                                        <td>{summary.category}</td>
                                                        <td><span class=prio_cls>{summary.priority}</span></td>
                                                        <td><span class=sla_cls>{summary.sla.state}</span></td>
                                                        <td class="tc-mono">{updated_date}</td>
                                                        <td><span class=status_cls>{summary.status}</span></td>
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
                        let tab_id_status_badge = current_tab_id.clone();
                        let tab_id_error = current_tab_id.clone();
                        let tab_id_notice = current_tab_id.clone();
                        let tab_id_is_new = current_tab_id.clone();
                        let tab_id_close = current_tab_id.clone();

                        let on_create_submit = move |ev: SubmitEvent| {
                            ev.prevent_default();
                            let Some(session) = ctx.session.get_untracked() else {
                                return;
                            };
                            let tid = tab_id_sv.get_value();
                            let Some(snapshot) = read_ticket_tab(&open_tabs, &tid, Clone::clone) else {
                                return;
                            };
                            if snapshot.busy {
                                return;
                            }
                            let subject = snapshot.new_subject.trim().to_string();
                            let body = snapshot.new_body.trim().to_string();
                            if subject.is_empty() || body.is_empty() {
                                update_ticket_tab(&open_tabs, &tid, |tab| {
                                    tab.error = Some("Subject and initial body are required.".to_string());
                                    tab.notice = None;
                                });
                                return;
                            }
                            let customer_id = match parse_opt_uuid("Customer ID", &snapshot.new_customer_id) {
                                Ok(id) => id,
                                Err(msg) => {
                                    update_ticket_tab(&open_tabs, &tid, |tab| {
                                        tab.error = Some(msg);
                                        tab.notice = None;
                                    });
                                    return;
                                }
                            };
                            let req = CreateTicketInput {
                                subject,
                                customer_id,
                                contact_id: None,
                                contact_name: snapshot.new_contact_name.trim().to_string(),
                                contact_email: snapshot.new_contact_email.trim().to_string(),
                                language: opt_trimmed(&snapshot.new_language),
                                category: snapshot.new_category.clone(),
                                internal: snapshot.new_internal,
                                body,
                            };
                            update_ticket_tab(&open_tabs, &tid, |tab| {
                                tab.busy = true;
                                tab.error = None;
                                tab.notice = None;
                            });
                            let connection = session.connection;
                            spawn_local(async move {
                                let res = match live_client(&connection) {
                                    Ok(client) => client.create_ticket(&req).await,
                                    Err(err) => Err(err),
                                };
                                match res {
                                    Ok(created) => {
                                        let next_id = format!("ticket:{}", created.ticket.id);
                                        open_tabs.update(|list| {
                                            list.retain(|t| t.tab_id != next_id);
                                            if let Some(tab) = list.iter_mut().find(|t| t.tab_id == tid) {
                                                tab.apply_detail(
                                                    &created,
                                                    Some(format!("Ticket {} created.", created.ticket.number)),
                                                );
                                            }
                                        });
                                        if active_tab_id.get_untracked().as_deref() == Some(tid.as_str()) {
                                            active_tab_id.set(Some(next_id));
                                        }
                                        reload_nonce.update(|n| *n += 1);
                                    }
                                    Err(err) => {
                                        update_ticket_tab(&open_tabs, &tid, |tab| {
                                            tab.busy = false;
                                            tab.error = Some(err.user_message());
                                        });
                                    }
                                }
                            });
                        };

                        let on_send_reply = move |ev: SubmitEvent| {
                            ev.prevent_default();
                            let Some(session) = ctx.session.get_untracked() else {
                                return;
                            };
                            let tid = tab_id_sv.get_value();
                            let Some(snapshot) = read_ticket_tab(&open_tabs, &tid, Clone::clone) else {
                                return;
                            };
                            let Some(ticket_id) = snapshot.ticket_id else {
                                return;
                            };
                            if snapshot.busy {
                                return;
                            }
                            let body = snapshot.reply_body.trim().to_string();
                            if body.is_empty() {
                                update_ticket_tab(&open_tabs, &tid, |tab| {
                                    tab.error = Some("Reply body cannot be empty.".to_string());
                                    tab.notice = None;
                                });
                                return;
                            }
                            let req = ReplyInput {
                                subject: opt_trimmed(&snapshot.reply_subject),
                                body,
                                status: opt_trimmed(&snapshot.reply_status),
                                ..ReplyInput::default()
                            };
                            update_ticket_tab(&open_tabs, &tid, |tab| {
                                tab.busy = true;
                                tab.error = None;
                                tab.notice = None;
                            });
                            let connection = session.connection;
                            spawn_local(async move {
                                let res = match live_client(&connection) {
                                    Ok(client) => client.reply_ticket(ticket_id, &req).await,
                                    Err(err) => Err(err),
                                };
                                match res {
                                    Ok(updated) => {
                                        update_ticket_tab(&open_tabs, &tid, |tab| {
                                            tab.reply_body.clear();
                                            tab.reply_subject.clear();
                                            tab.apply_detail(&updated, Some("Reply sent.".to_string()));
                                        });
                                        reload_nonce.update(|n| *n += 1);
                                    }
                                    Err(err) => {
                                        update_ticket_tab(&open_tabs, &tid, |tab| {
                                            tab.busy = false;
                                            tab.error = Some(err.user_message());
                                        });
                                    }
                                }
                            });
                        };

                        let on_add_note = move |ev: SubmitEvent| {
                            ev.prevent_default();
                            let Some(session) = ctx.session.get_untracked() else {
                                return;
                            };
                            let tid = tab_id_sv.get_value();
                            let Some(snapshot) = read_ticket_tab(&open_tabs, &tid, Clone::clone) else {
                                return;
                            };
                            let Some(ticket_id) = snapshot.ticket_id else {
                                return;
                            };
                            if snapshot.busy {
                                return;
                            }
                            let body = snapshot.note_body.trim().to_string();
                            if body.is_empty() {
                                update_ticket_tab(&open_tabs, &tid, |tab| {
                                    tab.error = Some("Internal note body cannot be empty.".to_string());
                                    tab.notice = None;
                                });
                                return;
                            }
                            let req = NoteInput {
                                body,
                                ..NoteInput::default()
                            };
                            update_ticket_tab(&open_tabs, &tid, |tab| {
                                tab.busy = true;
                                tab.error = None;
                                tab.notice = None;
                            });
                            let connection = session.connection;
                            spawn_local(async move {
                                let res = match live_client(&connection) {
                                    Ok(client) => client.add_ticket_note(ticket_id, &req).await,
                                    Err(err) => Err(err),
                                };
                                match res {
                                    Ok(updated) => {
                                        update_ticket_tab(&open_tabs, &tid, |tab| {
                                            tab.note_body.clear();
                                            tab.apply_detail(&updated, Some("Internal note added.".to_string()));
                                        });
                                        reload_nonce.update(|n| *n += 1);
                                    }
                                    Err(err) => {
                                        update_ticket_tab(&open_tabs, &tid, |tab| {
                                            tab.busy = false;
                                            tab.error = Some(err.user_message());
                                        });
                                    }
                                }
                            });
                        };

                        let on_add_tag = move |ev: SubmitEvent| {
                            ev.prevent_default();
                            let Some(session) = ctx.session.get_untracked() else {
                                return;
                            };
                            let tid = tab_id_sv.get_value();
                            let Some(snapshot) = read_ticket_tab(&open_tabs, &tid, Clone::clone) else {
                                return;
                            };
                            let Some(ticket_id) = snapshot.ticket_id else {
                                return;
                            };
                            if snapshot.busy {
                                return;
                            }
                            let tag = snapshot.tag_input.trim().to_string();
                            if tag.is_empty() {
                                update_ticket_tab(&open_tabs, &tid, |tab| {
                                    tab.error = Some("Enter a tag name.".to_string());
                                    tab.notice = None;
                                });
                                return;
                            }
                            let req = TagInput { tag };
                            update_ticket_tab(&open_tabs, &tid, |tab| {
                                tab.busy = true;
                                tab.error = None;
                                tab.notice = None;
                            });
                            let connection = session.connection;
                            spawn_local(async move {
                                let res = match live_client(&connection) {
                                    Ok(client) => client.add_ticket_tag(ticket_id, &req).await,
                                    Err(err) => Err(err),
                                };
                                match res {
                                    Ok(updated) => {
                                        update_ticket_tab(&open_tabs, &tid, |tab| {
                                            tab.tag_input.clear();
                                            tab.apply_detail(&updated, Some("Tag added.".to_string()));
                                        });
                                        reload_nonce.update(|n| *n += 1);
                                    }
                                    Err(err) => {
                                        update_ticket_tab(&open_tabs, &tid, |tab| {
                                            tab.busy = false;
                                            tab.error = Some(err.user_message());
                                        });
                                    }
                                }
                            });
                        };

                        let on_log_time = move |ev: SubmitEvent| {
                            ev.prevent_default();
                            let Some(session) = ctx.session.get_untracked() else {
                                return;
                            };
                            let tid = tab_id_sv.get_value();
                            let Some(snapshot) = read_ticket_tab(&open_tabs, &tid, Clone::clone) else {
                                return;
                            };
                            let Some(ticket_id) = snapshot.ticket_id else {
                                return;
                            };
                            if snapshot.busy {
                                return;
                            }
                            let minutes = match parse_i32("Minutes", &snapshot.time_minutes, 0) {
                                Ok(m) if (1..=1440).contains(&m) => m,
                                Ok(_) => {
                                    update_ticket_tab(&open_tabs, &tid, |tab| {
                                        tab.error = Some("Minutes must be between 1 and 1440.".to_string());
                                        tab.notice = None;
                                    });
                                    return;
                                }
                                Err(msg) => {
                                    update_ticket_tab(&open_tabs, &tid, |tab| {
                                        tab.error = Some(msg);
                                        tab.notice = None;
                                    });
                                    return;
                                }
                            };
                            let req = TimeEntryInput {
                                minutes,
                                note: snapshot.time_note.trim().to_string(),
                                billable: snapshot.time_billable,
                            };
                            update_ticket_tab(&open_tabs, &tid, |tab| {
                                tab.busy = true;
                                tab.error = None;
                                tab.notice = None;
                            });
                            let connection = session.connection;
                            spawn_local(async move {
                                let res = match live_client(&connection) {
                                    Ok(client) => client.add_ticket_time_entry(ticket_id, &req).await,
                                    Err(err) => Err(err),
                                };
                                match res {
                                    Ok(entries) => {
                                        update_ticket_tab(&open_tabs, &tid, |tab| {
                                            tab.busy = false;
                                            tab.time_note.clear();
                                            tab.time_entries = Some(entries);
                                            tab.notice = Some("Time entry logged.".to_string());
                                        });
                                        reload_nonce.update(|n| *n += 1);
                                    }
                                    Err(err) => {
                                        update_ticket_tab(&open_tabs, &tid, |tab| {
                                            tab.busy = false;
                                            tab.error = Some(err.user_message());
                                        });
                                    }
                                }
                            });
                        };

                        let on_escalate = move |ev: SubmitEvent| {
                            ev.prevent_default();
                            let Some(session) = ctx.session.get_untracked() else {
                                return;
                            };
                            let tid = tab_id_sv.get_value();
                            let Some(snapshot) = read_ticket_tab(&open_tabs, &tid, Clone::clone) else {
                                return;
                            };
                            let Some(ticket_id) = snapshot.ticket_id else {
                                return;
                            };
                            if snapshot.busy {
                                return;
                            }
                            let reason = snapshot.escalate_reason.trim().to_string();
                            if reason.is_empty() {
                                update_ticket_tab(&open_tabs, &tid, |tab| {
                                    tab.error = Some("Escalation reason is required.".to_string());
                                    tab.notice = None;
                                });
                                return;
                            }
                            let to_user_id = match parse_opt_uuid("Target user ID", &snapshot.escalate_to_user) {
                                Ok(v) => v,
                                Err(msg) => {
                                    update_ticket_tab(&open_tabs, &tid, |tab| {
                                        tab.error = Some(msg);
                                        tab.notice = None;
                                    });
                                    return;
                                }
                            };
                            let to_team_id = match parse_opt_uuid("Target team ID", &snapshot.escalate_to_team) {
                                Ok(v) => v,
                                Err(msg) => {
                                    update_ticket_tab(&open_tabs, &tid, |tab| {
                                        tab.error = Some(msg);
                                        tab.notice = None;
                                    });
                                    return;
                                }
                            };
                            let req = EscalateInput {
                                reason,
                                to_user_id,
                                to_team_id,
                                raise_priority: snapshot.escalate_raise_priority,
                            };
                            update_ticket_tab(&open_tabs, &tid, |tab| {
                                tab.busy = true;
                                tab.error = None;
                                tab.notice = None;
                            });
                            let connection = session.connection;
                            spawn_local(async move {
                                let res = match live_client(&connection) {
                                    Ok(client) => client.escalate_ticket(ticket_id, &req).await,
                                    Err(err) => Err(err),
                                };
                                match res {
                                    Ok(updated) => {
                                        update_ticket_tab(&open_tabs, &tid, |tab| {
                                            tab.escalate_reason.clear();
                                            tab.apply_detail(&updated, Some("Ticket escalated.".to_string()));
                                        });
                                        reload_nonce.update(|n| *n += 1);
                                    }
                                    Err(err) => {
                                        update_ticket_tab(&open_tabs, &tid, |tab| {
                                            tab.busy = false;
                                            tab.error = Some(err.user_message());
                                        });
                                    }
                                }
                            });
                        };

                        let on_change_status = move |_| {
                            let Some(session) = ctx.session.get_untracked() else {
                                return;
                            };
                            let tid = tab_id_sv.get_value();
                            let Some(snapshot) = read_ticket_tab(&open_tabs, &tid, Clone::clone) else {
                                return;
                            };
                            let Some(ticket_id) = snapshot.ticket_id else {
                                return;
                            };
                            if snapshot.busy {
                                return;
                            }
                            let req = TicketStatusInput {
                                status: snapshot.quick_status.clone(),
                                expected_version: snapshot.current_ticket().map(|t| t.version),
                            };
                            update_ticket_tab(&open_tabs, &tid, |tab| {
                                tab.busy = true;
                                tab.error = None;
                                tab.notice = None;
                            });
                            let connection = session.connection;
                            spawn_local(async move {
                                let res = match live_client(&connection) {
                                    Ok(client) => client.change_ticket_status(ticket_id, &req).await,
                                    Err(err) => Err(err),
                                };
                                match res {
                                    Ok(updated) => {
                                        update_ticket_tab(&open_tabs, &tid, |tab| {
                                            tab.apply_detail(
                                                &updated,
                                                Some(format!("Status updated to {}.", updated.ticket.status)),
                                            );
                                        });
                                        reload_nonce.update(|n| *n += 1);
                                    }
                                    Err(err) => {
                                        update_ticket_tab(&open_tabs, &tid, |tab| {
                                            tab.busy = false;
                                            tab.error = Some(err.user_message());
                                        });
                                    }
                                }
                            });
                        };

                        let on_save_properties = move |ev: SubmitEvent| {
                            ev.prevent_default();
                            let Some(session) = ctx.session.get_untracked() else {
                                return;
                            };
                            let tid = tab_id_sv.get_value();
                            let Some(snapshot) = read_ticket_tab(&open_tabs, &tid, Clone::clone) else {
                                return;
                            };
                            let Some(ticket_id) = snapshot.ticket_id else {
                                return;
                            };
                            if snapshot.busy {
                                return;
                            }
                            let subject = snapshot.prop_subject.trim().to_string();
                            if subject.is_empty() {
                                update_ticket_tab(&open_tabs, &tid, |tab| {
                                    tab.error = Some("Subject is required.".to_string());
                                    tab.notice = None;
                                });
                                return;
                            }
                            let customer_id = match parse_opt_uuid("Customer ID", &snapshot.prop_customer_id) {
                                Ok(v) => v,
                                Err(msg) => {
                                    update_ticket_tab(&open_tabs, &tid, |tab| {
                                        tab.error = Some(msg);
                                        tab.notice = None;
                                    });
                                    return;
                                }
                            };
                            let base_ticket = snapshot.current_ticket().cloned();
                            let req = UpdateTicketInput {
                                subject,
                                status: snapshot.prop_status.clone(),
                                priority: snapshot.prop_priority.clone(),
                                category: snapshot.prop_category.clone(),
                                language: snapshot.prop_language.clone(),
                                owner_user_id: base_ticket.as_ref().and_then(|t| t.owner_user_id),
                                customer_id,
                                contact_id: base_ticket.as_ref().and_then(|t| t.contact_id),
                                contact_name: snapshot.prop_contact_name.trim().to_string(),
                                contact_email: snapshot.prop_contact_email.trim().to_string(),
                                quotation_id: base_ticket.as_ref().and_then(|t| t.quotation_id),
                                opportunity_id: base_ticket.as_ref().and_then(|t| t.opportunity_id),
                                expected_version: base_ticket.as_ref().map(|t| t.version),
                            };
                            update_ticket_tab(&open_tabs, &tid, |tab| {
                                tab.busy = true;
                                tab.error = None;
                                tab.notice = None;
                            });
                            let connection = session.connection;
                            spawn_local(async move {
                                let res = match live_client(&connection) {
                                    Ok(client) => client.update_ticket(ticket_id, &req).await,
                                    Err(err) => Err(err),
                                };
                                match res {
                                    Ok(updated) => {
                                        update_ticket_tab(&open_tabs, &tid, |tab| {
                                            tab.apply_detail(&updated, Some("Ticket properties saved.".to_string()));
                                        });
                                        reload_nonce.update(|n| *n += 1);
                                    }
                                    Err(err) => {
                                        update_ticket_tab(&open_tabs, &tid, |tab| {
                                            tab.busy = false;
                                            tab.error = Some(err.user_message());
                                        });
                                    }
                                }
                            });
                        };

                        view! {
                            <aside class="tc-card tc-detail-drawer" data-target="ticket-details">
                                <div class="tc-inline-tabs" data-target="ticket-detail-tabs">
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
                                                        on:click=move |_| close_ticket_tab(&open_tabs, &active_tab_id, &close_id)
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
                                                read_ticket_tab(&open_tabs, &tab_id_header, |t| t.title.clone())
                                                    .unwrap_or_else(|| "Ticket".to_string())
                                            }}
                                        </h2>
                                        <p class="tc-page-subtitle tc-mono">
                                            {move || {
                                                read_ticket_tab(&open_tabs, &tab_id_subtitle, |t| {
                                                    if let Some(ticket) = t.current_ticket() {
                                                        if t.loading_detail {
                                                            format!("{} (loading...)", ticket.id)
                                                        } else {
                                                            format!(
                                                                "{} · v{} · {}m logged",
                                                                ticket.id, ticket.version, ticket.time_minutes
                                                            )
                                                        }
                                                    } else {
                                                        "Create a new ticket (POST /api/v1/tickets)".to_string()
                                                    }
                                                })
                                                .unwrap_or_default()
                                            }}
                                        </p>
                                    </div>
                                    <div style="display: flex; align-items: center; gap: var(--space-xs);">
                                        {move || read_ticket_tab(&open_tabs, &tab_id_status_badge, |t| {
                                            t.current_ticket().map(|tk| tk.status.clone())
                                        }).flatten().map(|st| {
                                            let cls = ticket_status_badge_class(&st);
                                            view! { <span class=cls>{st}</span> }
                                        })}
                                        <button
                                            type="button"
                                            class="tc-btn tc-btn-sm tc-btn-ghost"
                                            data-target="ticket-detail-close"
                                            on:click=move |_| close_ticket_tab(&open_tabs, &active_tab_id, &tab_id_close)
                                        >
                                            "Close"
                                        </button>
                                    </div>
                                </div>

                                {move || {
                                    read_ticket_tab(&open_tabs, &tab_id_error, |t| t.error.clone())
                                        .flatten()
                                        .map(|msg| view! {
                                            <div class="tc-alert-error" role="alert" data-target="ticket-detail-error">
                                                {msg}
                                            </div>
                                        })
                                }}

                                {move || {
                                    read_ticket_tab(&open_tabs, &tab_id_notice, |t| t.notice.clone())
                                        .flatten()
                                        .map(|msg| view! {
                                            <div class="tc-alert-success" role="status" data-target="ticket-detail-notice">
                                                {msg}
                                            </div>
                                        })
                                }}

                                <Show
                                    when=move || {
                                        read_ticket_tab(&open_tabs, &tab_id_is_new, |t| t.ticket_id.is_none())
                                            .unwrap_or(false)
                                    }
                                    fallback=move || {
                                        let tid_subtabs = tab_id_sv.get_value();
                                        let tid_section = tab_id_sv.get_value();
                                        let tid_quick_status = tab_id_sv.get_value();
                                        let tid_meta = tab_id_sv.get_value();

                                        view! {
                                            <div style="display: flex; flex-direction: column; gap: var(--space-md);">
                                                {move || read_ticket_tab(&open_tabs, &tid_meta, |t| t.current_ticket().cloned()).flatten().map(|tk| {
                                                    let customer_name = tk.customer_name.clone().unwrap_or_else(|| "—".to_string());
                                                    let sla_cls = sla_badge_class(&tk.sla.state);
                                                    let prio_cls = priority_badge_class(&tk.priority);
                                                    view! {
                                                        <div style="display: flex; flex-wrap: wrap; gap: var(--space-xs); align-items: center; font-size: 12px;">
                                                            <span class=prio_cls>{format!("Priority: {}", tk.priority)}</span>
                                                            <span class=sla_cls>{format!("SLA: {}", tk.sla.state)}</span>
                                                            <span class="tc-badge">{format!("Customer: {}", customer_name)}</span>
                                                            {tk.escalated_at.map(|dt| view! {
                                                                <span class="tc-badge tc-badge-error">
                                                                    {format!("Escalated {}", dt.date_naive())}
                                                                </span>
                                                            })}
                                                        </div>
                                                    }
                                                })}

                                                <div style="display: flex; align-items: center; gap: var(--space-sm);">
                                                    <select
                                                        data-target="ticket-quick-status"
                                                        class="tc-select"
                                                        style="flex: 1;"
                                                        prop:value=move || {
                                                            read_ticket_tab(&open_tabs, &tid_quick_status, |t| t.quick_status.clone())
                                                                .unwrap_or_default()
                                                        }
                                                        on:change=move |ev| {
                                                            let val = event_target_value(&ev);
                                                            tab_id_sv.with_value(|tid| {
                                                                update_ticket_tab(&open_tabs, tid, |t| t.quick_status = val);
                                                            });
                                                        }
                                                    >
                                                        {TICKET_STATUSES.iter().map(|(val, label)| view! {
                                                            <option value=*val>{*label}</option>
                                                        }).collect_view()}
                                                    </select>
                                                    <button
                                                        type="button"
                                                        data-target="ticket-apply-status"
                                                        class="tc-btn tc-btn-sm"
                                                        disabled=move || {
                                                            tab_id_sv.with_value(|tid| {
                                                                read_ticket_tab(&open_tabs, tid, |t| t.busy).unwrap_or(false)
                                                            })
                                                        }
                                                        on:click=on_change_status
                                                    >
                                                        "Update Status"
                                                    </button>
                                                </div>

                                                <div class="tc-inline-tabs" data-target="ticket-drawer-subtabs">
                                                    {
                                                        [
                                                            (DrawerSection::Thread, "Thread & Reply", "ticket-tab-thread"),
                                                            (DrawerSection::TagsTime, "Tags & Time", "ticket-tab-tags-time"),
                                                            (DrawerSection::Escalate, "Escalate", "ticket-tab-escalate"),
                                                            (DrawerSection::Properties, "Properties", "ticket-tab-properties"),
                                                        ]
                                                        .into_iter()
                                                        .map(|(sec, label, target)| {
                                                            let tid_check = tid_subtabs.clone();
                                                            let tid_click = tid_subtabs.clone();
                                                            view! {
                                                                <button
                                                                    type="button"
                                                                    data-target=target
                                                                    class=move || {
                                                                        let active = read_ticket_tab(&open_tabs, &tid_check, |t| t.section == sec)
                                                                            .unwrap_or(false);
                                                                        if active {
                                                                            "tc-inline-tab tc-inline-tab-active"
                                                                        } else {
                                                                            "tc-inline-tab"
                                                                        }
                                                                    }
                                                                    on:click=move |_| {
                                                                        update_ticket_tab(&open_tabs, &tid_click, |t| t.section = sec);
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
                                                    let section = read_ticket_tab(&open_tabs, &tid_section, |t| t.section)
                                                        .unwrap_or(DrawerSection::Thread);
                                                    match section {
                                                        DrawerSection::Thread => {
                                                            let tid_articles = tab_id_sv.get_value();
                                                            let tid_ans = tab_id_sv.get_value();
                                                            view! {
                                                                <div style="display: flex; flex-direction: column; gap: var(--space-md);">
                                                                    <div style="display: flex; flex-direction: column; gap: var(--space-sm);" data-target="ticket-articles">
                                                                        {move || {
                                                                            let articles = read_ticket_tab(&open_tabs, &tid_articles, |t| {
                                                                                t.detail.as_ref().map(|d| d.articles.clone()).unwrap_or_default()
                                                                            }).unwrap_or_default();
                                                                            if articles.is_empty() {
                                                                                view! {
                                                                                    <div style="font-size: 12px; color: var(--on-surface-variant);">
                                                                                        "No messages in this thread yet."
                                                                                    </div>
                                                                                }.into_any()
                                                                            } else {
                                                                                articles.into_iter().map(|art| {
                                                                                    let kind_cls = article_kind_badge_class(&art.kind);
                                                                                    let author = art
                                                                                        .author_name
                                                                                        .clone()
                                                                                        .filter(|s| !s.trim().is_empty())
                                                                                        .unwrap_or_else(|| {
                                                                                            if !art.from_name.trim().is_empty() {
                                                                                                art.from_name.clone()
                                                                                            } else if !art.from_address.trim().is_empty() {
                                                                                                art.from_address.clone()
                                                                                            } else {
                                                                                                "System".to_string()
                                                                                            }
                                                                                        });
                                                                                    let stamp = format!("{} {}", art.created_at.date_naive(), art.created_at.time());
                                                                                    view! {
                                                                                        <div style="padding: var(--space-sm) var(--space-md); border-radius: var(--radius-sm); border: 1px solid var(--outline-variant); background: var(--surface);">
                                                                                            <div style="display: flex; justify-content: space-between; align-items: center; gap: var(--space-xs); margin-bottom: 4px; font-size: 11px;">
                                                                                                <div style="display: flex; align-items: center; gap: var(--space-xs);">
                                                                                                    <span class=kind_cls>{art.kind}</span>
                                                                                                    <strong>{author}</strong>
                                                                                                    {art.delivery.map(|d| view! {
                                                                        <span class="tc-badge">{d}</span>
                                                                    })}
                                                                </div>
                                                                <span class="tc-mono" style="color: var(--on-surface-variant);">{stamp}</span>
                                                            </div>
                                                            <div style="white-space: pre-wrap; font-size: 13px;">{art.body}</div>
                                                        </div>
                                                                                    }
                                                                                }).collect_view().into_any()
                                                                            }
                                                                        }}
                                                                    </div>

                                                                    <div class="tc-field">
                                                                        <label class="tc-label" for="helpdesk-prepared-answers">"Prepared Answers"</label>
                                                                        <select
                                                                            id="helpdesk-prepared-answers"
                                                                            data-target="helpdesk-prepared-answers"
                                                                            class="tc-select"
                                                                            prop:value=""
                                                                            on:change=move |ev| {
                                                                                let val = event_target_value(&ev);
                                                                                let Ok(ans_id) = Uuid::parse_str(val.trim()) else {
                                                                                    return;
                                                                                };
                                                                                let Some(answer) = prepared_answers.with_untracked(|list| {
                                                                                    list.iter().find(|a| a.id == ans_id).cloned()
                                                                                }) else {
                                                                                    return;
                                                                                };
                                                                                let ticket_lang = read_ticket_tab(&open_tabs, &tid_ans, |t| {
                                                                                    t.current_ticket()
                                                                                        .map(|tk| tk.language.clone())
                                                                                        .unwrap_or_else(|| "en".to_string())
                                                                                }).unwrap_or_else(|| "en".to_string());
                                                                                if let Some(txt) = pick_answer_text(&answer, &ticket_lang) {
                                                                                    let body_text = txt.body.clone();
                                                                                    let subj_text = txt.subject.clone();
                                                                                    let is_note = answer.kind == "internal_note";
                                                                                    update_ticket_tab(&open_tabs, &tid_ans, |tab| {
                                                                                        if is_note {
                                                                                            if tab.note_body.trim().is_empty() {
                                                                                                tab.note_body = body_text;
                                                                                            } else {
                                                                                                tab.note_body.push_str("\n\n");
                                                                                                tab.note_body.push_str(&body_text);
                                                                                            }
                                                                                        } else {
                                                                                            if tab.reply_body.trim().is_empty() {
                                                                                                tab.reply_body = body_text;
                                                                                            } else {
                                                                                                tab.reply_body.push_str("\n\n");
                                                                                                tab.reply_body.push_str(&body_text);
                                                                                            }
                                                                                            if tab.reply_subject.trim().is_empty() && !subj_text.trim().is_empty() {
                                                                                                tab.reply_subject = subj_text;
                                                                                            }
                                                                                        }
                                                                                    });
                                                                                }
                                                                            }
                                                                        >
                                                                            <option value="">"Insert prepared answer..."</option>
                                                                            <For
                                                                                each=move || prepared_answers.get()
                                                                                key=|a| (a.id, a.code.clone(), a.name.clone())
                                                                                children=move |ans| {
                                                                                    let val = ans.id.to_string();
                                                                                    let label = format!("[{}] {} ({})", ans.code, ans.name, ans.kind);
                                                                                    view! { <option value=val>{label}</option> }
                                                                                }
                                                                            />
                                                                        </select>
                                                                    </div>

                                                                    <form
                                                                        data-target="ticket-reply-form"
                                                                        style="display: flex; flex-direction: column; gap: var(--space-sm); border-top: 1px solid var(--outline-variant); padding-top: var(--space-sm);"
                                                                        on:submit=on_send_reply
                                                                    >
                                                                        <div class="tc-form-grid">
                                                                            <div class="tc-field">
                                                                                <label class="tc-label" for="ticket-reply-subject">"Reply subject (optional)"</label>
                                                                                <input
                                                                                    id="ticket-reply-subject"
                                                                                    data-target="ticket-reply-subject"
                                                                                    class="tc-input"
                                                                                    type="text"
                                                                                    placeholder="Defaults to Re: <subject>"
                                                                                    prop:value=move || tab_id_sv.with_value(|tid| read_ticket_tab(&open_tabs, tid, |t| t.reply_subject.clone()).unwrap_or_default())
                                                                                    on:input=move |ev| {
                                                                                        let val = event_target_value(&ev);
                                                                                        tab_id_sv.with_value(|tid| update_ticket_tab(&open_tabs, tid, |t| t.reply_subject = val));
                                                                                    }
                                                                                />
                                                                            </div>
                                                                            <div class="tc-field">
                                                                                <label class="tc-label" for="ticket-reply-status">"Status after reply"</label>
                                                                                <select
                                                                                    id="ticket-reply-status"
                                                                                    data-target="ticket-reply-status"
                                                                                    class="tc-select"
                                                                                    prop:value=move || tab_id_sv.with_value(|tid| read_ticket_tab(&open_tabs, tid, |t| t.reply_status.clone()).unwrap_or_default())
                                                                                    on:change=move |ev| {
                                                                                        let val = event_target_value(&ev);
                                                                                        tab_id_sv.with_value(|tid| update_ticket_tab(&open_tabs, tid, |t| t.reply_status = val));
                                                                                    }
                                                                                >
                                                                                    {TICKET_STATUSES.iter().map(|(val, label)| view! {
                                                                                        <option value=*val>{*label}</option>
                                                                                    }).collect_view()}
                                                                                </select>
                                                                            </div>
                                                                        </div>
                                                                        <div class="tc-field">
                                                                            <label class="tc-label" for="ticket-reply-body">"Customer Reply"</label>
                                                                            <textarea
                                                                                id="ticket-reply-body"
                                                                                data-target="ticket-reply-body"
                                                                                class="tc-input"
                                                                                style="min-height: 76px; resize: vertical; font-family: inherit; font-size: 13px;"
                                                                                placeholder="Write an email reply to the customer..."
                                                                                prop:value=move || tab_id_sv.with_value(|tid| read_ticket_tab(&open_tabs, tid, |t| t.reply_body.clone()).unwrap_or_default())
                                                                                on:input=move |ev| {
                                                                                    let val = event_target_value(&ev);
                                                                                    tab_id_sv.with_value(|tid| update_ticket_tab(&open_tabs, tid, |t| t.reply_body = val));
                                                                                }
                                                                            />
                                                                        </div>
                                                                        <div class="tc-form-actions" style="border-top: none; padding-top: 0;">
                                                                            <button
                                                                                type="submit"
                                                                                data-target="ticket-send"
                                                                                class="tc-btn tc-btn-primary"
                                                                                disabled=move || tab_id_sv.with_value(|tid| read_ticket_tab(&open_tabs, tid, |t| t.busy).unwrap_or(false))
                                                                            >
                                                                                "Send Reply"
                                                                            </button>
                                                                        </div>
                                                                    </form>

                                                                    <form
                                                                        data-target="ticket-note-form"
                                                                        style="display: flex; flex-direction: column; gap: var(--space-sm); border-top: 1px solid var(--outline-variant); padding-top: var(--space-sm);"
                                                                        on:submit=on_add_note
                                                                    >
                                                                        <div class="tc-field">
                                                                            <label class="tc-label" for="ticket-note-body">"Internal Note (staff only)"</label>
                                                                            <textarea
                                                                                id="ticket-note-body"
                                                                                data-target="ticket-note-body"
                                                                                class="tc-input"
                                                                                style="min-height: 64px; resize: vertical; font-family: inherit; font-size: 13px;"
                                                                                placeholder="Add an internal note (never sent to customer)..."
                                                                                prop:value=move || tab_id_sv.with_value(|tid| read_ticket_tab(&open_tabs, tid, |t| t.note_body.clone()).unwrap_or_default())
                                                                                on:input=move |ev| {
                                                                                    let val = event_target_value(&ev);
                                                                                    tab_id_sv.with_value(|tid| update_ticket_tab(&open_tabs, tid, |t| t.note_body = val));
                                                                                }
                                                                            />
                                                                        </div>
                                                                        <div class="tc-form-actions" style="border-top: none; padding-top: 0;">
                                                                            <button
                                                                                type="submit"
                                                                                data-target="ticket-note-submit"
                                                                                class="tc-btn"
                                                                                disabled=move || tab_id_sv.with_value(|tid| read_ticket_tab(&open_tabs, tid, |t| t.busy).unwrap_or(false))
                                                                            >
                                                                                "Add Internal Note"
                                                                            </button>
                                                                        </div>
                                                                    </form>
                                                                </div>
                                                            }.into_any()
                                                        }
                                                        DrawerSection::TagsTime => {
                                                            let tid_tags = tab_id_sv.get_value();
                                                            let tid_time = tab_id_sv.get_value();
                                                            view! {
                                                                <div style="display: flex; flex-direction: column; gap: var(--space-md);">
                                                                    <div style="display: flex; flex-direction: column; gap: var(--space-sm);">
                                                                        <div class="tc-label">"Tags"</div>
                                                                        <div class="tc-chip-row" data-target="ticket-tags-list">
                                                                            {move || {
                                                                                let tags = read_ticket_tab(&open_tabs, &tid_tags, |t| {
                                                                                    t.current_ticket().map(|tk| tk.tags.clone()).unwrap_or_default()
                                                                                }).unwrap_or_default();
                                                                                if tags.is_empty() {
                                                                                    view! {
                                                                                        <span style="font-size: 12px; color: var(--on-surface-variant);">"No tags yet."</span>
                                                                                    }.into_any()
                                                                                } else {
                                                                                    tags.into_iter().map(|tag| view! {
                                                                                        <span class="tc-badge tc-badge-primary">{tag}</span>
                                                                                    }).collect_view().into_any()
                                                                                }
                                                                            }}
                                                                        </div>
                                                                        <form
                                                                            style="display: flex; gap: var(--space-sm);"
                                                                            on:submit=on_add_tag
                                                                        >
                                                                            <input
                                                                                data-target="ticket-tag-input"
                                                                                class="tc-input"
                                                                                style="flex: 1;"
                                                                                type="text"
                                                                                placeholder="Add tag (e.g. warranty)..."
                                                                                prop:value=move || tab_id_sv.with_value(|tid| read_ticket_tab(&open_tabs, tid, |t| t.tag_input.clone()).unwrap_or_default())
                                                                                on:input=move |ev| {
                                                                                    let val = event_target_value(&ev);
                                                                                    tab_id_sv.with_value(|tid| update_ticket_tab(&open_tabs, tid, |t| t.tag_input = val));
                                                                                }
                                                                            />
                                                                            <button
                                                                                type="submit"
                                                                                data-target="ticket-tag-submit"
                                                                                class="tc-btn"
                                                                                disabled=move || tab_id_sv.with_value(|tid| read_ticket_tab(&open_tabs, tid, |t| t.busy).unwrap_or(false))
                                                                            >
                                                                                "Add Tag"
                                                                            </button>
                                                                        </form>
                                                                    </div>

                                                                    <div style="display: flex; flex-direction: column; gap: var(--space-sm); border-top: 1px solid var(--outline-variant); padding-top: var(--space-md);">
                                                                        <div class="tc-label">"Time Entries"</div>
                                                                        {move || {
                                                                            let entries = read_ticket_tab(&open_tabs, &tid_time, |t| t.time_entries.clone()).flatten();
                                                                            match entries {
                                                                                Some(te) => view! {
                                                                                    <div style="display: flex; flex-direction: column; gap: var(--space-xs);" data-target="ticket-time-entries-list">
                                                                                        <div style="font-size: 12px; color: var(--on-surface-variant);">
                                                                                            {format!("Total: {} min ({} min billable)", te.total_minutes, te.billable_minutes)}
                                                                                        </div>
                                                                                        {te.items.into_iter().map(|item| {
                                                                                            let stamp = format!("{} {}", item.created_at.date_naive(), item.created_at.time());
                                                                                            view! {
                                                                                                <div style="display: flex; justify-content: space-between; align-items: center; padding: 6px var(--space-sm); border: 1px solid var(--outline-variant); border-radius: var(--radius-sm); font-size: 12px;">
                                                                                                    <div>
                                                                                                        <strong>{format!("{}m", item.minutes)}</strong>
                                                                                                        <span>{format!(" · {} ", item.user_name)}</span>
                                                                                                        {(!item.note.trim().is_empty()).then(|| view! {
                                                                                                            <span style="color: var(--on-surface-variant);">{format!("— {}", item.note)}</span>
                                                                                                        })}
                                                                                                    </div>
                                                                                                    <div style="display: flex; align-items: center; gap: var(--space-xs);">
                                                                                                        {item.billable.then(|| view! {
                                                                                                            <span class="tc-badge tc-badge-success">"Billable"</span>
                                                                                                        })}
                                                                                                        <span class="tc-mono" style="font-size: 11px; color: var(--on-surface-variant);">{stamp}</span>
                                                                                                    </div>
                                                                                                </div>
                                                                                            }
                                                                                        }).collect_view()}
                                                                                    </div>
                                                                                }.into_any(),
                                                                                None => view! {
                                                                                    <div style="font-size: 12px; color: var(--on-surface-variant);">"Loading time entries..."</div>
                                                                                }.into_any(),
                                                                            }
                                                                        }}

                                                                        <form
                                                                            style="display: flex; flex-direction: column; gap: var(--space-sm);"
                                                                            on:submit=on_log_time
                                                                        >
                                                                            <div class="tc-form-grid">
                                                                                <div class="tc-field">
                                                                                    <label class="tc-label" for="ticket-time-minutes">"Minutes (1-1440) *"</label>
                                                                                    <input
                                                                                        id="ticket-time-minutes"
                                                                                        data-target="ticket-time-minutes"
                                                                                        class="tc-input tc-mono"
                                                                                        type="number"
                                                                                        min="1"
                                                                                        max="1440"
                                                                                        prop:value=move || tab_id_sv.with_value(|tid| read_ticket_tab(&open_tabs, tid, |t| t.time_minutes.clone()).unwrap_or_default())
                                                                                        on:input=move |ev| {
                                                                                            let val = event_target_value(&ev);
                                                                                            tab_id_sv.with_value(|tid| update_ticket_tab(&open_tabs, tid, |t| t.time_minutes = val));
                                                                                        }
                                                                                    />
                                                                                </div>
                                                                                <div class="tc-field" style="justify-content: flex-end;">
                                                                                    <label class="tc-checkbox-row">
                                                                                        <input
                                                                                            data-target="ticket-time-billable"
                                                                                            type="checkbox"
                                                                                            prop:checked=move || tab_id_sv.with_value(|tid| read_ticket_tab(&open_tabs, tid, |t| t.time_billable).unwrap_or(false))
                                                                                            on:change=move |ev| {
                                                                                                let checked = event_target_checked(&ev);
                                                                                                tab_id_sv.with_value(|tid| update_ticket_tab(&open_tabs, tid, |t| t.time_billable = checked));
                                                                                            }
                                                                                        />
                                                                                        <span>"Billable"</span>
                                                                                    </label>
                                                                                </div>
                                                                                <div class="tc-field tc-form-span-2">
                                                                                    <label class="tc-label" for="ticket-time-note">"Note"</label>
                                                                                    <input
                                                                                        id="ticket-time-note"
                                                                                        data-target="ticket-time-note"
                                                                                        class="tc-input"
                                                                                        type="text"
                                                                                        placeholder="Work performed..."
                                                                                        prop:value=move || tab_id_sv.with_value(|tid| read_ticket_tab(&open_tabs, tid, |t| t.time_note.clone()).unwrap_or_default())
                                                                                        on:input=move |ev| {
                                                                                            let val = event_target_value(&ev);
                                                                                            tab_id_sv.with_value(|tid| update_ticket_tab(&open_tabs, tid, |t| t.time_note = val));
                                                                                        }
                                                                                    />
                                                                                </div>
                                                                            </div>
                                                                            <div class="tc-form-actions" style="border-top: none; padding-top: 0;">
                                                                                <button
                                                                                    type="submit"
                                                                                    data-target="ticket-log-time"
                                                                                    class="tc-btn tc-btn-primary"
                                                                                    disabled=move || tab_id_sv.with_value(|tid| read_ticket_tab(&open_tabs, tid, |t| t.busy).unwrap_or(false))
                                                                                >
                                                                                    "Log Time"
                                                                                </button>
                                                                            </div>
                                                                        </form>
                                                                    </div>
                                                                </div>
                                                            }.into_any()
                                                        }
                                                        DrawerSection::Escalate => {
                                                            let tid_esc_info = tab_id_sv.get_value();
                                                            view! {
                                                                <form
                                                                    style="display: flex; flex-direction: column; gap: var(--space-md);"
                                                                    on:submit=on_escalate
                                                                >
                                                                    {move || read_ticket_tab(&open_tabs, &tid_esc_info, |t| {
                                                                        t.current_ticket().and_then(|tk| {
                                                                            tk.escalated_at.map(|dt| (dt, tk.escalated_by_name.clone()))
                                                                        })
                                                                    }).flatten().map(|(dt, by)| view! {
                                                                        <div class="tc-alert-error" style="font-size: 12px;">
                                                                            {format!(
                                                                                "Already escalated on {} by {}",
                                                                                dt.date_naive(),
                                                                                by.unwrap_or_else(|| "a colleague".to_string())
                                                                            )}
                                                                        </div>
                                                                    })}

                                                                    <div class="tc-field">
                                                                        <label class="tc-label" for="escalate-reason">"Escalation reason *"</label>
                                                                        <textarea
                                                                            id="escalate-reason"
                                                                            data-target="escalate-reason"
                                                                            class="tc-input"
                                                                            style="min-height: 76px; resize: vertical; font-family: inherit; font-size: 13px;"
                                                                            placeholder="Explain why this ticket needs escalation..."
                                                                            prop:value=move || tab_id_sv.with_value(|tid| read_ticket_tab(&open_tabs, tid, |t| t.escalate_reason.clone()).unwrap_or_default())
                                                                            on:input=move |ev| {
                                                                                let val = event_target_value(&ev);
                                                                                tab_id_sv.with_value(|tid| update_ticket_tab(&open_tabs, tid, |t| t.escalate_reason = val));
                                                                            }
                                                                        />
                                                                    </div>

                                                                    <label class="tc-checkbox-row">
                                                                        <input
                                                                            data-target="escalate-raise-priority"
                                                                            type="checkbox"
                                                                            prop:checked=move || tab_id_sv.with_value(|tid| read_ticket_tab(&open_tabs, tid, |t| t.escalate_raise_priority).unwrap_or(false))
                                                                            on:change=move |ev| {
                                                                                let checked = event_target_checked(&ev);
                                                                                tab_id_sv.with_value(|tid| update_ticket_tab(&open_tabs, tid, |t| t.escalate_raise_priority = checked));
                                                                            }
                                                                        />
                                                                        <span>"Raise priority one step"</span>
                                                                    </label>

                                                                    <div class="tc-form-grid">
                                                                        <div class="tc-field">
                                                                            <label class="tc-label" for="escalate-to-user">"To user UUID (optional)"</label>
                                                                            <input
                                                                                id="escalate-to-user"
                                                                                data-target="escalate-to-user"
                                                                                class="tc-input tc-mono"
                                                                                type="text"
                                                                                placeholder="Leave empty for team leads"
                                                                                prop:value=move || tab_id_sv.with_value(|tid| read_ticket_tab(&open_tabs, tid, |t| t.escalate_to_user.clone()).unwrap_or_default())
                                                                                on:input=move |ev| {
                                                                                    let val = event_target_value(&ev);
                                                                                    tab_id_sv.with_value(|tid| update_ticket_tab(&open_tabs, tid, |t| t.escalate_to_user = val));
                                                                                }
                                                                            />
                                                                        </div>
                                                                        <div class="tc-field">
                                                                            <label class="tc-label" for="escalate-to-team">"To team UUID (optional)"</label>
                                                                            <input
                                                                                id="escalate-to-team"
                                                                                data-target="escalate-to-team"
                                                                                class="tc-input tc-mono"
                                                                                type="text"
                                                                                placeholder="Or escalate to team"
                                                                                prop:value=move || tab_id_sv.with_value(|tid| read_ticket_tab(&open_tabs, tid, |t| t.escalate_to_team.clone()).unwrap_or_default())
                                                                                on:input=move |ev| {
                                                                                    let val = event_target_value(&ev);
                                                                                    tab_id_sv.with_value(|tid| update_ticket_tab(&open_tabs, tid, |t| t.escalate_to_team = val));
                                                                                }
                                                                            />
                                                                        </div>
                                                                    </div>

                                                                    <div class="tc-form-actions">
                                                                        <button
                                                                            type="submit"
                                                                            data-target="escalate-ticket"
                                                                            class="tc-btn tc-btn-primary"
                                                                            disabled=move || tab_id_sv.with_value(|tid| read_ticket_tab(&open_tabs, tid, |t| t.busy).unwrap_or(false))
                                                                        >
                                                                            "Escalate Ticket"
                                                                        </button>
                                                                    </div>
                                                                </form>
                                                            }.into_any()
                                                        }
                                                        DrawerSection::Properties => {
                                                            view! {
                                                                <form
                                                                    style="display: flex; flex-direction: column; gap: var(--space-md);"
                                                                    on:submit=on_save_properties
                                                                >
                                                                    <div class="tc-form-grid">
                                                                        <div class="tc-field tc-form-span-2">
                                                                            <label class="tc-label" for="ticket-prop-subject">"Subject *"</label>
                                                                            <input
                                                                                id="ticket-prop-subject"
                                                                                data-target="ticket-prop-subject"
                                                                                class="tc-input"
                                                                                type="text"
                                                                                prop:value=move || tab_id_sv.with_value(|tid| read_ticket_tab(&open_tabs, tid, |t| t.prop_subject.clone()).unwrap_or_default())
                                                                                on:input=move |ev| {
                                                                                    let val = event_target_value(&ev);
                                                                                    tab_id_sv.with_value(|tid| update_ticket_tab(&open_tabs, tid, |t| t.prop_subject = val));
                                                                                }
                                                                            />
                                                                        </div>

                                                                        <div class="tc-field">
                                                                            <label class="tc-label" for="ticket-prop-status">"Status"</label>
                                                                            <select
                                                                                id="ticket-prop-status"
                                                                                data-target="ticket-prop-status"
                                                                                class="tc-select"
                                                                                prop:value=move || tab_id_sv.with_value(|tid| read_ticket_tab(&open_tabs, tid, |t| t.prop_status.clone()).unwrap_or_default())
                                                                                on:change=move |ev| {
                                                                                    let val = event_target_value(&ev);
                                                                                    tab_id_sv.with_value(|tid| update_ticket_tab(&open_tabs, tid, |t| t.prop_status = val));
                                                                                }
                                                                            >
                                                                                {TICKET_STATUSES.iter().map(|(val, label)| view! {
                                                                                    <option value=*val>{*label}</option>
                                                                                }).collect_view()}
                                                                            </select>
                                                                        </div>

                                                                        <div class="tc-field">
                                                                            <label class="tc-label" for="ticket-prop-priority">"Priority"</label>
                                                                            <select
                                                                                id="ticket-prop-priority"
                                                                                data-target="ticket-prop-priority"
                                                                                class="tc-select"
                                                                                prop:value=move || tab_id_sv.with_value(|tid| read_ticket_tab(&open_tabs, tid, |t| t.prop_priority.clone()).unwrap_or_default())
                                                                                on:change=move |ev| {
                                                                                    let val = event_target_value(&ev);
                                                                                    tab_id_sv.with_value(|tid| update_ticket_tab(&open_tabs, tid, |t| t.prop_priority = val));
                                                                                }
                                                                            >
                                                                                {TICKET_PRIORITIES.iter().map(|(val, label)| view! {
                                                                                    <option value=*val>{*label}</option>
                                                                                }).collect_view()}
                                                                            </select>
                                                                        </div>

                                                                        <div class="tc-field">
                                                                            <label class="tc-label" for="ticket-prop-category">"Category"</label>
                                                                            <select
                                                                                id="ticket-prop-category"
                                                                                data-target="ticket-prop-category"
                                                                                class="tc-select"
                                                                                prop:value=move || tab_id_sv.with_value(|tid| read_ticket_tab(&open_tabs, tid, |t| t.prop_category.clone()).unwrap_or_default())
                                                                                on:change=move |ev| {
                                                                                    let val = event_target_value(&ev);
                                                                                    tab_id_sv.with_value(|tid| update_ticket_tab(&open_tabs, tid, |t| t.prop_category = val));
                                                                                }
                                                                            >
                                                                                {TICKET_CATEGORIES.iter().map(|(val, label)| view! {
                                                                                    <option value=*val>{*label}</option>
                                                                                }).collect_view()}
                                                                            </select>
                                                                        </div>

                                                                        <div class="tc-field">
                                                                            <label class="tc-label" for="ticket-prop-language">"Language"</label>
                                                                            <select
                                                                                id="ticket-prop-language"
                                                                                data-target="ticket-prop-language"
                                                                                class="tc-select"
                                                                                prop:value=move || tab_id_sv.with_value(|tid| read_ticket_tab(&open_tabs, tid, |t| t.prop_language.clone()).unwrap_or_default())
                                                                                on:change=move |ev| {
                                                                                    let val = event_target_value(&ev);
                                                                                    tab_id_sv.with_value(|tid| update_ticket_tab(&open_tabs, tid, |t| t.prop_language = val));
                                                                                }
                                                                            >
                                                                                {TICKET_LANGUAGES.iter().map(|(val, label)| view! {
                                                                                    <option value=*val>{*label}</option>
                                                                                }).collect_view()}
                                                                            </select>
                                                                        </div>

                                                                        <div class="tc-field tc-form-span-2">
                                                                            <label class="tc-label" for="ticket-prop-customer-id">"Customer ID (UUID)"</label>
                                                                            <input
                                                                                id="ticket-prop-customer-id"
                                                                                data-target="ticket-prop-customer-id"
                                                                                class="tc-input tc-mono"
                                                                                type="text"
                                                                                placeholder="Optional customer UUID"
                                                                                prop:value=move || tab_id_sv.with_value(|tid| read_ticket_tab(&open_tabs, tid, |t| t.prop_customer_id.clone()).unwrap_or_default())
                                                                                on:input=move |ev| {
                                                                                    let val = event_target_value(&ev);
                                                                                    tab_id_sv.with_value(|tid| update_ticket_tab(&open_tabs, tid, |t| t.prop_customer_id = val));
                                                                                }
                                                                            />
                                                                            <Show when=move || !customers.with(Vec::is_empty)>
                                                                                <select
                                                                                    data-target="ticket-prop-customer-pick"
                                                                                    class="tc-select"
                                                                                    prop:value=move || tab_id_sv.with_value(|tid| read_ticket_tab(&open_tabs, tid, |t| t.prop_customer_id.clone()).unwrap_or_default())
                                                                                    on:change=move |ev| {
                                                                                        let val = event_target_value(&ev);
                                                                                        tab_id_sv.with_value(|tid| update_ticket_tab(&open_tabs, tid, |t| t.prop_customer_id = val));
                                                                                    }
                                                                                >
                                                                                    <option value="">"Unlinked / pick customer..."</option>
                                                                                    <For
                                                                                        each=move || customers.get()
                                                                                        key=|c| (c.id, c.name.clone())
                                                                                        children=move |c| {
                                                                                            let val = c.id.to_string();
                                                                                            let label = format!("{} · {}", c.code, c.name);
                                                                                            view! { <option value=val>{label}</option> }
                                                                                        }
                                                                                    />
                                                                                </select>
                                                                            </Show>
                                                                        </div>

                                                                        <div class="tc-field">
                                                                            <label class="tc-label" for="ticket-prop-contact-name">"Contact name"</label>
                                                                            <input
                                                                                id="ticket-prop-contact-name"
                                                                                data-target="ticket-prop-contact-name"
                                                                                class="tc-input"
                                                                                type="text"
                                                                                prop:value=move || tab_id_sv.with_value(|tid| read_ticket_tab(&open_tabs, tid, |t| t.prop_contact_name.clone()).unwrap_or_default())
                                                                                on:input=move |ev| {
                                                                                    let val = event_target_value(&ev);
                                                                                    tab_id_sv.with_value(|tid| update_ticket_tab(&open_tabs, tid, |t| t.prop_contact_name = val));
                                                                                }
                                                                            />
                                                                        </div>

                                                                        <div class="tc-field">
                                                                            <label class="tc-label" for="ticket-prop-contact-email">"Contact email"</label>
                                                                            <input
                                                                                id="ticket-prop-contact-email"
                                                                                data-target="ticket-prop-contact-email"
                                                                                class="tc-input"
                                                                                type="email"
                                                                                prop:value=move || tab_id_sv.with_value(|tid| read_ticket_tab(&open_tabs, tid, |t| t.prop_contact_email.clone()).unwrap_or_default())
                                                                                on:input=move |ev| {
                                                                                    let val = event_target_value(&ev);
                                                                                    tab_id_sv.with_value(|tid| update_ticket_tab(&open_tabs, tid, |t| t.prop_contact_email = val));
                                                                                }
                                                                            />
                                                                        </div>
                                                                    </div>

                                                                    <div class="tc-form-actions">
                                                                        <button
                                                                            type="submit"
                                                                            data-target="ticket-save-properties"
                                                                            class="tc-btn tc-btn-primary"
                                                                            disabled=move || tab_id_sv.with_value(|tid| read_ticket_tab(&open_tabs, tid, |t| t.busy).unwrap_or(false))
                                                                        >
                                                                            "Save Properties"
                                                                        </button>
                                                                    </div>
                                                                </form>
                                                            }.into_any()
                                                        }
                                                    }
                                                }}
                                            </div>
                                        }
                                    }
                                >
                                    <form
                                        data-target="helpdesk-new-ticket-form"
                                        style="display: flex; flex-direction: column; gap: var(--space-md);"
                                        on:submit=on_create_submit
                                    >
                                        <div class="tc-form-grid">
                                            <div class="tc-field tc-form-span-2">
                                                <label class="tc-label" for="new-ticket-subject">"Subject *"</label>
                                                <input
                                                    id="new-ticket-subject"
                                                    data-target="new-ticket-subject"
                                                    class="tc-input"
                                                    type="text"
                                                    placeholder="Short summary of the customer request"
                                                    prop:value=move || tab_id_sv.with_value(|tid| read_ticket_tab(&open_tabs, tid, |t| t.new_subject.clone()).unwrap_or_default())
                                                    on:input=move |ev| {
                                                        let val = event_target_value(&ev);
                                                        tab_id_sv.with_value(|tid| update_ticket_tab(&open_tabs, tid, |t| t.new_subject = val));
                                                    }
                                                />
                                            </div>

                                            <div class="tc-field">
                                                <label class="tc-label" for="new-ticket-category">"Category"</label>
                                                <select
                                                    id="new-ticket-category"
                                                    data-target="new-ticket-category"
                                                    class="tc-select"
                                                    prop:value=move || tab_id_sv.with_value(|tid| read_ticket_tab(&open_tabs, tid, |t| t.new_category.clone()).unwrap_or_default())
                                                    on:change=move |ev| {
                                                        let val = event_target_value(&ev);
                                                        tab_id_sv.with_value(|tid| update_ticket_tab(&open_tabs, tid, |t| t.new_category = val));
                                                    }
                                                >
                                                    {TICKET_CATEGORIES.iter().map(|(val, label)| view! {
                                                        <option value=*val>{*label}</option>
                                                    }).collect_view()}
                                                </select>
                                            </div>

                                            <div class="tc-field">
                                                <label class="tc-label" for="new-ticket-language">"Language"</label>
                                                <select
                                                    id="new-ticket-language"
                                                    data-target="new-ticket-language"
                                                    class="tc-select"
                                                    prop:value=move || tab_id_sv.with_value(|tid| read_ticket_tab(&open_tabs, tid, |t| t.new_language.clone()).unwrap_or_default())
                                                    on:change=move |ev| {
                                                        let val = event_target_value(&ev);
                                                        tab_id_sv.with_value(|tid| update_ticket_tab(&open_tabs, tid, |t| t.new_language = val));
                                                    }
                                                >
                                                    <option value="">"Auto (customer / company)"</option>
                                                    {TICKET_LANGUAGES.iter().map(|(val, label)| view! {
                                                        <option value=*val>{*label}</option>
                                                    }).collect_view()}
                                                </select>
                                            </div>

                                            <div class="tc-field tc-form-span-2">
                                                <label class="tc-label" for="new-ticket-customer-id">"Customer ID (optional UUID)"</label>
                                                <input
                                                    id="new-ticket-customer-id"
                                                    data-target="new-ticket-customer-id"
                                                    class="tc-input tc-mono"
                                                    type="text"
                                                    placeholder="Leave empty for internal / unassigned customer"
                                                    prop:value=move || tab_id_sv.with_value(|tid| read_ticket_tab(&open_tabs, tid, |t| t.new_customer_id.clone()).unwrap_or_default())
                                                    on:input=move |ev| {
                                                        let val = event_target_value(&ev);
                                                        tab_id_sv.with_value(|tid| update_ticket_tab(&open_tabs, tid, |t| t.new_customer_id = val));
                                                    }
                                                />
                                                <Show when=move || !customers.with(Vec::is_empty)>
                                                    <select
                                                        data-target="new-ticket-customer-pick"
                                                        class="tc-select"
                                                        prop:value=move || tab_id_sv.with_value(|tid| read_ticket_tab(&open_tabs, tid, |t| t.new_customer_id.clone()).unwrap_or_default())
                                                        on:change=move |ev| {
                                                            let val = event_target_value(&ev);
                                                            tab_id_sv.with_value(|tid| update_ticket_tab(&open_tabs, tid, |t| t.new_customer_id = val));
                                                        }
                                                    >
                                                        <option value="">"No customer selected"</option>
                                                        <For
                                                            each=move || customers.get()
                                                            key=|c| (c.id, c.name.clone())
                                                            children=move |c| {
                                                                let val = c.id.to_string();
                                                                let label = format!("{} · {}", c.code, c.name);
                                                                view! { <option value=val>{label}</option> }
                                                            }
                                                        />
                                                    </select>
                                                </Show>
                                            </div>

                                            <div class="tc-field">
                                                <label class="tc-label" for="new-ticket-contact-name">"Contact name"</label>
                                                <input
                                                    id="new-ticket-contact-name"
                                                    data-target="new-ticket-contact-name"
                                                    class="tc-input"
                                                    type="text"
                                                    prop:value=move || tab_id_sv.with_value(|tid| read_ticket_tab(&open_tabs, tid, |t| t.new_contact_name.clone()).unwrap_or_default())
                                                    on:input=move |ev| {
                                                        let val = event_target_value(&ev);
                                                        tab_id_sv.with_value(|tid| update_ticket_tab(&open_tabs, tid, |t| t.new_contact_name = val));
                                                    }
                                                />
                                            </div>

                                            <div class="tc-field">
                                                <label class="tc-label" for="new-ticket-contact-email">"Contact email"</label>
                                                <input
                                                    id="new-ticket-contact-email"
                                                    data-target="new-ticket-contact-email"
                                                    class="tc-input"
                                                    type="email"
                                                    prop:value=move || tab_id_sv.with_value(|tid| read_ticket_tab(&open_tabs, tid, |t| t.new_contact_email.clone()).unwrap_or_default())
                                                    on:input=move |ev| {
                                                        let val = event_target_value(&ev);
                                                        tab_id_sv.with_value(|tid| update_ticket_tab(&open_tabs, tid, |t| t.new_contact_email = val));
                                                    }
                                                />
                                            </div>

                                            <div class="tc-field tc-form-span-2">
                                                <label class="tc-checkbox-row">
                                                    <input
                                                        data-target="new-ticket-internal"
                                                        type="checkbox"
                                                        prop:checked=move || tab_id_sv.with_value(|tid| read_ticket_tab(&open_tabs, tid, |t| t.new_internal).unwrap_or(false))
                                                        on:change=move |ev| {
                                                            let checked = event_target_checked(&ev);
                                                            tab_id_sv.with_value(|tid| update_ticket_tab(&open_tabs, tid, |t| t.new_internal = checked));
                                                        }
                                                    />
                                                    <span>"Internal ticket (no SLA / customer e-mail)"</span>
                                                </label>
                                            </div>

                                            <div class="tc-field tc-form-span-2">
                                                <label class="tc-label" for="new-ticket-body">"Description / First note *"</label>
                                                <textarea
                                                    id="new-ticket-body"
                                                    data-target="new-ticket-body"
                                                    class="tc-input"
                                                    style="min-height: 92px; resize: vertical; font-family: inherit; font-size: 13px;"
                                                    placeholder="Describe what was asked or observed..."
                                                    prop:value=move || tab_id_sv.with_value(|tid| read_ticket_tab(&open_tabs, tid, |t| t.new_body.clone()).unwrap_or_default())
                                                    on:input=move |ev| {
                                                        let val = event_target_value(&ev);
                                                        tab_id_sv.with_value(|tid| update_ticket_tab(&open_tabs, tid, |t| t.new_body = val));
                                                    }
                                                />
                                            </div>
                                        </div>

                                        <div class="tc-form-actions">
                                            <button
                                                type="submit"
                                                data-target="new-ticket-submit"
                                                class="tc-btn tc-btn-primary"
                                                disabled=move || tab_id_sv.with_value(|tid| read_ticket_tab(&open_tabs, tid, |t| t.busy).unwrap_or(false))
                                            >
                                                {move || {
                                                    let busy = tab_id_sv.with_value(|tid| read_ticket_tab(&open_tabs, tid, |t| t.busy).unwrap_or(false));
                                                    if busy { "Creating..." } else { "Create Ticket" }
                                                }}
                                            </button>
                                        </div>
                                    </form>
                                </Show>
                            </aside>
                        }
                    })}
                </div>
            </Show>
        </div>
    }
}
