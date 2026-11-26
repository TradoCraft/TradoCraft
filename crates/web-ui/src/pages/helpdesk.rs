use leptos::ev::SubmitEvent;
use leptos::prelude::*;
use leptos::task::spawn_local;
use leptos_router::components::A;
use tradocraft_api_client::helpdesk::{
    AssignmentInput, CreateTicketInput, EscalateInput, ListPreparedAnswersParams,
    ListTicketsParams, NoteInput, PreparedAnswer, ReplyInput, TagInput, Team, TicketDetail,
    TicketPage, TicketStatusInput, TicketSummary, TicketTimeEntries, TimeEntryInput,
    UpdateTicketInput,
};
use tradocraft_api_client::{ApiError, Client, FileInfo};
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
    reply_attachments: Vec<FileInfo>,
    uploading: bool,
    note_body: String,
    // Prepared answers
    answer_query: String,
    answer_pick: String,
    answer_busy: bool,
    answer_notice: Option<String>,
    // Assignment
    assign_team: String,
    assign_owner: String,
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
            reply_attachments: Vec::new(),
            uploading: false,
            note_body: String::new(),
            answer_query: String::new(),
            answer_pick: String::new(),
            answer_busy: false,
            answer_notice: None,
            assign_team: String::new(),
            assign_owner: String::new(),
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
        self.assign_team = t.team_id.map(|id| id.to_string()).unwrap_or_default();
        self.assign_owner = t.owner_user_id.map(|id| id.to_string()).unwrap_or_default();
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

/// Most answers listed in the picker at once.
const MAX_ANSWER_OPTIONS: usize = 50;
/// Files per message the API accepts.
const MAX_ATTACHMENTS: usize = 10;
/// Largest upload the API accepts (12 MiB).
const MAX_ATTACHMENT_BYTES: usize = 12 * 1024 * 1024;

/// Where a prepared answer is inserted: the customer reply or the internal note.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum AnswerTarget {
    Reply,
    Note,
}

fn answer_target(kind: &str) -> AnswerTarget {
    if kind == "internal_note" {
        AnswerTarget::Note
    } else {
        AnswerTarget::Reply
    }
}

/// Active prepared answers matching `query` (code, name, keyword or category, case-insensitive;
/// a leading `/` is ignored like in the Flutter picker). Answers of another team are hidden
/// when the ticket belongs to a team. Capped at [`MAX_ANSWER_OPTIONS`].
fn filter_answers<'a>(
    answers: &'a [PreparedAnswer],
    query: &str,
    ticket_team: Option<Uuid>,
) -> Vec<&'a PreparedAnswer> {
    let needle = query.trim().trim_start_matches('/').to_lowercase();
    answers
        .iter()
        .filter(|a| a.active)
        .filter(|a| match (a.team_id, ticket_team) {
            (Some(answer_team), Some(ticket_team)) => answer_team == ticket_team,
            (Some(_), None) => false,
            (None, _) => true,
        })
        .filter(|a| {
            needle.is_empty()
                || a.code.to_lowercase().contains(&needle)
                || a.name.to_lowercase().contains(&needle)
                || a.category
                    .as_deref()
                    .is_some_and(|c| c.to_lowercase().contains(&needle))
                || a.keywords
                    .iter()
                    .any(|k| k.to_lowercase().contains(&needle))
        })
        .take(MAX_ANSWER_OPTIONS)
        .collect()
}

/// Appends `inserted` to a draft, separated by a blank line; an empty draft is replaced.
fn merge_draft(existing: &str, inserted: &str) -> String {
    if existing.trim().is_empty() {
        inserted.to_string()
    } else {
        format!("{}\n\n{inserted}", existing.trim_end())
    }
}

/// Message shown after a prepared answer was rendered into a draft.
fn rendered_notice(code: &str, target: AnswerTarget, language: &str, fallback: bool) -> String {
    let place = match target {
        AnswerTarget::Reply => "reply",
        AnswerTarget::Note => "internal note",
    };
    let lang = language.to_uppercase();
    if fallback {
        format!(
            "Inserted [{code}] into the {place} in {lang} (no text in the ticket's language). Review and edit the draft before sending."
        )
    } else {
        format!(
            "Inserted [{code}] into the {place} in {lang}. Review the filled-in placeholders and edit the draft before sending."
        )
    }
}

/// Human readable size such as `12 B`, `3.4 KB` or `1.2 MB`.
fn format_file_size(bytes: i64) -> String {
    const KB: f64 = 1024.0;
    let b = bytes.max(0) as f64;
    if b < KB {
        format!("{} B", bytes.max(0))
    } else if b < KB * KB {
        format!("{:.1} KB", b / KB)
    } else {
        format!("{:.1} MB", b / (KB * KB))
    }
}

/// Client-side checks before uploading a file to a draft reply.
fn validate_attachment(name: &str, len: usize, already_attached: usize) -> Result<(), String> {
    if name.trim().is_empty() {
        return Err("The selected file has no name.".to_string());
    }
    if len == 0 {
        return Err(format!("{name} is empty."));
    }
    if len > MAX_ATTACHMENT_BYTES {
        return Err(format!(
            "{name} is {} - the limit is {}.",
            format_file_size(len as i64),
            format_file_size(MAX_ATTACHMENT_BYTES as i64)
        ));
    }
    if already_attached >= MAX_ATTACHMENTS {
        return Err(format!("At most {MAX_ATTACHMENTS} files per message."));
    }
    Ok(())
}

/// Builds the assignment request from the team and owner selects (empty clears).
fn assignment_from_form(team: &str, owner: &str) -> Result<AssignmentInput, String> {
    Ok(AssignmentInput {
        team_id: parse_opt_uuid("Team", team)?,
        owner_user_id: parse_opt_uuid("Owner", owner)?,
    })
}

/// Owners that can be picked: the members of the given team, or of every team when none is
/// chosen. Each person once, sorted by name.
fn owner_options(teams: &[Team], team_id: Option<Uuid>) -> Vec<(Uuid, String)> {
    let mut out: Vec<(Uuid, String)> = Vec::new();
    for team in teams.iter().filter(|t| team_id.is_none_or(|id| t.id == id)) {
        for member in &team.members {
            if !out.iter().any(|(id, _)| *id == member.user_id) {
                out.push((member.user_id, member.display_name.clone()));
            }
        }
    }
    out.sort_by_key(|(_, name)| name.to_lowercase());
    out
}

/// A file the agent chose in a browser file input.
struct PickedFile {
    name: String,
    bytes: Vec<u8>,
}

/// Reads the file chosen in the `change` event's file input and clears the input so the same
/// file can be picked again. Calls `done` once the bytes are available.
#[cfg(target_arch = "wasm32")]
fn begin_file_read(ev: leptos::ev::Event, done: impl FnOnce(Result<PickedFile, String>) + 'static) {
    use wasm_bindgen::JsCast;
    let Some(input) = ev
        .target()
        .and_then(|t| t.dyn_into::<web_sys::HtmlInputElement>().ok())
    else {
        return;
    };
    let Some(file) = input.files().and_then(|list| list.get(0)) else {
        return;
    };
    input.set_value("");
    let name = file.name();
    spawn_local(async move {
        let result = wasm_bindgen_futures::JsFuture::from(file.array_buffer())
            .await
            .map(|buffer| PickedFile {
                name,
                bytes: js_sys::Uint8Array::new(&buffer).to_vec(),
            })
            .map_err(|_| "Could not read the selected file.".to_string());
        done(result);
    });
}

#[cfg(not(target_arch = "wasm32"))]
fn begin_file_read(
    _ev: leptos::ev::Event,
    done: impl FnOnce(Result<PickedFile, String>) + 'static,
) {
    done(Err("Attaching files needs the browser build.".to_string()));
}

/// Offers `bytes` to the browser as a file download.
#[cfg(target_arch = "wasm32")]
fn save_file(filename: &str, content_type: &str, bytes: &[u8]) -> Result<(), String> {
    use wasm_bindgen::JsCast;
    let fail = |_| "The browser could not save the file.".to_string();
    let parts = js_sys::Array::new();
    parts.push(&js_sys::Uint8Array::from(bytes));
    let options = web_sys::BlobPropertyBag::new();
    options.set_type(content_type);
    let blob =
        web_sys::Blob::new_with_u8_array_sequence_and_options(&parts, &options).map_err(fail)?;
    let url = web_sys::Url::create_object_url_with_blob(&blob).map_err(fail)?;
    let anchor = web_sys::window()
        .and_then(|w| w.document())
        .and_then(|d| d.create_element("a").ok())
        .and_then(|e| e.dyn_into::<web_sys::HtmlAnchorElement>().ok())
        .ok_or_else(|| "The browser could not save the file.".to_string())?;
    anchor.set_href(&url);
    anchor.set_download(filename);
    anchor.click();
    let _ = web_sys::Url::revoke_object_url(&url);
    Ok(())
}

#[cfg(not(target_arch = "wasm32"))]
fn save_file(_filename: &str, _content_type: &str, _bytes: &[u8]) -> Result<(), String> {
    Err("Downloading files needs the browser build.".to_string())
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
    let teams = RwSignal::new(Vec::<Team>::new());

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
            teams.set(Vec::new());
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
                if let Ok(list) = client.list_helpdesk_teams().await {
                    teams.set(list.into_iter().filter(|t| t.active).collect());
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
                                if snapshot.uploading {
                                    update_ticket_tab(&open_tabs, &tid, |tab| {
                                        tab.error = Some("Wait for the attachment upload to finish.".to_string());
                                        tab.notice = None;
                                    });
                                    return;
                                }
                                let req = ReplyInput {
                                    subject: opt_trimmed(&snapshot.reply_subject),
                                    body,
                                    status: opt_trimmed(&snapshot.reply_status),
                                    attachment_ids: snapshot.reply_attachments.iter().map(|f| f.id).collect(),
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
                                                tab.reply_attachments.clear();
                                                tab.answer_notice = None;
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

                            let on_assign = move |_| {
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
                                let req = match assignment_from_form(&snapshot.assign_team, &snapshot.assign_owner) {
                                    Ok(req) => req,
                                    Err(msg) => {
                                        update_ticket_tab(&open_tabs, &tid, |tab| {
                                            tab.error = Some(msg);
                                            tab.notice = None;
                                        });
                                        return;
                                    }
                                };
                                update_ticket_tab(&open_tabs, &tid, |tab| {
                                    tab.busy = true;
                                    tab.error = None;
                                    tab.notice = None;
                                });
                                let connection = session.connection;
                                spawn_local(async move {
                                    let res = match live_client(&connection) {
                                        Ok(client) => client.assign_ticket(ticket_id, &req).await,
                                        Err(err) => Err(err),
                                    };
                                    match res {
                                        Ok(updated) => {
                                            update_ticket_tab(&open_tabs, &tid, |tab| {
                                                tab.apply_detail(&updated, Some("Assignment saved.".to_string()));
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

                            let on_pick_answer = move |ans_id: Uuid| {
                                let Some(session) = ctx.session.get_untracked() else {
                                    return;
                                };
                                let tid = tab_id_sv.get_value();
                                let Some(ticket_id) = read_ticket_tab(&open_tabs, &tid, |t| t.ticket_id).flatten() else {
                                    return;
                                };
                                let Some(answer) = prepared_answers
                                    .with_untracked(|list| list.iter().find(|a| a.id == ans_id).cloned())
                                else {
                                    return;
                                };
                                update_ticket_tab(&open_tabs, &tid, |tab| {
                                    tab.answer_busy = true;
                                    tab.error = None;
                                    tab.notice = None;
                                });
                                let connection = session.connection;
                                spawn_local(async move {
                                    let res = match live_client(&connection) {
                                        Ok(client) => client.render_prepared_answer(ticket_id, ans_id).await,
                                        Err(err) => Err(err),
                                    };
                                    match res {
                                        Ok(rendered) => {
                                            let target = answer_target(&answer.kind);
                                            update_ticket_tab(&open_tabs, &tid, |tab| {
                                                tab.answer_busy = false;
                                                tab.answer_pick.clear();
                                                match target {
                                                    AnswerTarget::Note => {
                                                        tab.note_body = merge_draft(&tab.note_body, &rendered.body);
                                                    }
                                                    AnswerTarget::Reply => {
                                                        tab.reply_body = merge_draft(&tab.reply_body, &rendered.body);
                                                        if tab.reply_subject.trim().is_empty()
                                                            && !rendered.subject.trim().is_empty()
                                                        {
                                                            tab.reply_subject = rendered.subject.clone();
                                                        }
                                                    }
                                                }
                                                tab.answer_notice = Some(rendered_notice(
                                                    &answer.code,
                                                    target,
                                                    &rendered.language,
                                                    rendered.fallback,
                                                ));
                                            });
                                        }
                                        Err(err) => {
                                            update_ticket_tab(&open_tabs, &tid, |tab| {
                                                tab.answer_busy = false;
                                                tab.answer_pick.clear();
                                                tab.error = Some(err.user_message());
                                            });
                                        }
                                    }
                                });
                            };

                            let on_attach_file = move |ev: leptos::ev::Event| {
                                let Some(session) = ctx.session.get_untracked() else {
                                    return;
                                };
                                let tid = tab_id_sv.get_value();
                                let Some((ticket_id, count, uploading)) = read_ticket_tab(&open_tabs, &tid, |t| {
                                    (t.ticket_id, t.reply_attachments.len(), t.uploading)
                                }) else {
                                    return;
                                };
                                let Some(ticket_id) = ticket_id else {
                                    return;
                                };
                                if uploading {
                                    return;
                                }
                                let connection = session.connection;
                                begin_file_read(ev, move |picked| {
                                    let file = match picked {
                                        Ok(file) => file,
                                        Err(msg) => {
                                            update_ticket_tab(&open_tabs, &tid, |tab| tab.error = Some(msg));
                                            return;
                                        }
                                    };
                                    if let Err(msg) = validate_attachment(&file.name, file.bytes.len(), count) {
                                        update_ticket_tab(&open_tabs, &tid, |tab| {
                                            tab.error = Some(msg);
                                            tab.notice = None;
                                        });
                                        return;
                                    }
                                    update_ticket_tab(&open_tabs, &tid, |tab| {
                                        tab.uploading = true;
                                        tab.error = None;
                                        tab.notice = None;
                                    });
                                    spawn_local(async move {
                                        let res = match live_client(&connection) {
                                            Ok(client) => {
                                                client
                                                    .upload_ticket_attachment(
                                                        ticket_id,
                                                        &file.name,
                                                        Some(Uuid::new_v4()),
                                                        file.bytes,
                                                    )
                                                    .await
                                            }
                                            Err(err) => Err(err),
                                        };
                                        update_ticket_tab(&open_tabs, &tid, |tab| {
                                            tab.uploading = false;
                                            match res {
                                                Ok(info) => {
                                                    tab.notice = Some(format!("Attached {}.", info.filename));
                                                    tab.reply_attachments.push(info);
                                                }
                                                Err(err) => tab.error = Some(err.user_message()),
                                            }
                                        });
                                    });
                                });
                            };

                            let on_download_attachment = move |file: FileInfo| {
                                let Some(session) = ctx.session.get_untracked() else {
                                    return;
                                };
                                let tid = tab_id_sv.get_value();
                                let Some(ticket_id) = read_ticket_tab(&open_tabs, &tid, |t| t.ticket_id).flatten() else {
                                    return;
                                };
                                let connection = session.connection;
                                spawn_local(async move {
                                    let res = match live_client(&connection) {
                                        Ok(client) => client
                                            .download_ticket_attachment(ticket_id, file.id)
                                            .await
                                            .map_err(|err| err.user_message()),
                                        Err(err) => Err(err.user_message()),
                                    };
                                    let saved = res.and_then(|bytes| save_file(&file.filename, &file.content_type, &bytes));
                                    update_ticket_tab(&open_tabs, &tid, |tab| match saved {
                                        Ok(()) => {
                                            tab.error = None;
                                            tab.notice = Some(format!("Downloaded {}.", file.filename));
                                        }
                                        Err(msg) => tab.error = Some(msg),
                                    });
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
                                                                <span class="tc-badge" data-target="ticket-team-badge">
                                                                    {format!("Team: {}", tk.team_name.clone().unwrap_or_else(|| "unassigned".to_string()))}
                                                                </span>
                                                                <span class="tc-badge" data-target="ticket-owner-badge">
                                                                    {format!("Owner: {}", tk.owner_name.clone().unwrap_or_else(|| "unassigned".to_string()))}
                                                                </span>
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

                                                    <div style="display: flex; align-items: flex-end; gap: var(--space-sm); flex-wrap: wrap;" data-target="ticket-assignment">
                                                        <div class="tc-field" style="flex: 1; min-width: 140px;">
                                                            <label class="tc-label" for="ticket-assign-team">"Team"</label>
                                                            <select
                                                                id="ticket-assign-team"
                                                                data-target="ticket-assign-team"
                                                                class="tc-select"
                                                                prop:value=move || tab_id_sv.with_value(|tid| read_ticket_tab(&open_tabs, tid, |t| t.assign_team.clone()).unwrap_or_default())
                                                                on:change=move |ev| {
                                                                    let val = event_target_value(&ev);
                                                                    tab_id_sv.with_value(|tid| update_ticket_tab(&open_tabs, tid, |t| {
                                                                        t.assign_team = val;
                                                                        // The owner list follows the team; drop an owner who is not in it.
                                                                        let team = Uuid::parse_str(t.assign_team.trim()).ok();
                                                                        let keep = Uuid::parse_str(t.assign_owner.trim()).ok().is_some_and(|owner| {
                                                                            teams.with_untracked(|list| owner_options(list, team).iter().any(|(id, _)| *id == owner))
                                                                        });
                                                                        if !keep {
                                                                            t.assign_owner.clear();
                                                                        }
                                                                    }));
                                                                }
                                                            >
                                                                <option value="">"No team"</option>
                                                                {move || teams.get().into_iter().map(|team| view! {
                                                                    <option value=team.id.to_string()>{team.name}</option>
                                                                }).collect_view()}
                                                            </select>
                                                        </div>
                                                        <div class="tc-field" style="flex: 1; min-width: 140px;">
                                                            <label class="tc-label" for="ticket-assign-owner">"Owner"</label>
                                                            <select
                                                                id="ticket-assign-owner"
                                                                data-target="ticket-assign-owner"
                                                                class="tc-select"
                                                                prop:value=move || tab_id_sv.with_value(|tid| read_ticket_tab(&open_tabs, tid, |t| t.assign_owner.clone()).unwrap_or_default())
                                                                on:change=move |ev| {
                                                                    let val = event_target_value(&ev);
                                                                    tab_id_sv.with_value(|tid| update_ticket_tab(&open_tabs, tid, |t| t.assign_owner = val));
                                                                }
                                                            >
                                                                <option value="">"Unassigned"</option>
                                                                {move || {
                                                                    let team = tab_id_sv
                                                                        .with_value(|tid| read_ticket_tab(&open_tabs, tid, |t| t.assign_team.clone()))
                                                                        .and_then(|raw| Uuid::parse_str(raw.trim()).ok());
                                                                    let current = tab_id_sv
                                                                        .with_value(|tid| read_ticket_tab(&open_tabs, tid, |t| (t.assign_owner.clone(), t.current_ticket().and_then(|tk| tk.owner_name.clone()))));
                                                                    let mut options = teams.with(|list| owner_options(list, team));
                                                                    // Keep the current owner selectable even when they are in no listed team.
                                                                    if let Some((raw, name)) = current {
                                                                        if let Ok(id) = Uuid::parse_str(raw.trim()) {
                                                                            if !options.iter().any(|(oid, _)| *oid == id) {
                                                                                options.push((id, name.unwrap_or_else(|| id.to_string())));
                                                                            }
                                                                        }
                                                                    }
                                                                    options.into_iter().map(|(id, name)| view! {
                                                                        <option value=id.to_string()>{name}</option>
                                                                    }).collect_view()
                                                                }}
                                                            </select>
                                                        </div>
                                                        <button
                                                            type="button"
                                                            data-target="ticket-assign-save"
                                                            class="tc-btn tc-btn-sm"
                                                            disabled=move || {
                                                                tab_id_sv.with_value(|tid| {
                                                                    read_ticket_tab(&open_tabs, tid, |t| t.busy).unwrap_or(false)
                                                                })
                                                            }
                                                            on:click=on_assign
                                                        >
                                                            "Assign"
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
                                                                {(!art.attachments.is_empty()).then(|| view! {
                                                                    <div class="tc-chip-row" style="margin-top: var(--space-xs);" data-target="ticket-article-attachments">
                                                                        {art.attachments.iter().cloned().map(|file| {
                                                                            let label = format!("{} ({})", file.filename, format_file_size(i64::from(file.size_bytes)));
                                                                            let name = file.filename.clone();
                                                                            view! {
                                                                                <button
                                                                                    type="button"
                                                                                    class="tc-chip"
                                                                                    data-target="ticket-attachment-download"
                                                                                    data-filename=name
                                                                                    on:click=move |_| on_download_attachment(file.clone())
                                                                                >
                                                                                    {label}
                                                                                </button>
                                                                            }
                                                                        }).collect_view()}
                                                                    </div>
                                                                })}
                                                            </div>
                                                                                        }
                                                                                    }).collect_view().into_any()
                                                                                }
                                                                            }}
                                                                        </div>

                                                                        <div class="tc-field" data-target="helpdesk-answer-picker">
                                                                            <label class="tc-label" for="helpdesk-answer-search">"Prepared Answers"</label>
                                                                            <input
                                                                                id="helpdesk-answer-search"
                                                                                data-target="helpdesk-answer-search"
                                                                                class="tc-input"
                                                                                type="search"
                                                                                placeholder="Search by code, name or keyword (e.g. /delivery)..."
                                                                                prop:value=move || tab_id_sv.with_value(|tid| read_ticket_tab(&open_tabs, tid, |t| t.answer_query.clone()).unwrap_or_default())
                                                                                on:input=move |ev| {
                                                                                    let val = event_target_value(&ev);
                                                                                    tab_id_sv.with_value(|tid| update_ticket_tab(&open_tabs, tid, |t| t.answer_query = val));
                                                                                }
                                                                            />
                                                                            <select
                                                                                id="helpdesk-prepared-answers"
                                                                                data-target="helpdesk-prepared-answers"
                                                                                class="tc-select"
                                                                                disabled=move || tab_id_sv.with_value(|tid| read_ticket_tab(&open_tabs, tid, |t| t.answer_busy).unwrap_or(false))
                                                                                prop:value=move || tab_id_sv.with_value(|tid| read_ticket_tab(&open_tabs, tid, |t| t.answer_pick.clone()).unwrap_or_default())
                                                                                on:change=move |ev| {
                                                                                    let val = event_target_value(&ev);
                                                                                    let Ok(ans_id) = Uuid::parse_str(val.trim()) else {
                                                                                        return;
                                                                                    };
                                                                                    tab_id_sv.with_value(|tid| update_ticket_tab(&open_tabs, tid, |t| t.answer_pick = val));
                                                                                    on_pick_answer(ans_id);
                                                                                }
                                                                            >
                                                                                <option value="">
                                                                                    {move || if tab_id_sv.with_value(|tid| read_ticket_tab(&open_tabs, tid, |t| t.answer_busy).unwrap_or(false)) {
                                                                                        "Filling in placeholders..."
                                                                                    } else {
                                                                                        "Insert prepared answer..."
                                                                                    }}
                                                                                </option>
                                                                                {move || {
                                                                                    let (query, team) = tab_id_sv.with_value(|tid| {
                                                                                        read_ticket_tab(&open_tabs, tid, |t| {
                                                                                            (t.answer_query.clone(), t.current_ticket().and_then(|tk| tk.team_id))
                                                                                        })
                                                                                    }).unwrap_or_default();
                                                                                    prepared_answers.with(|list| {
                                                                                        filter_answers(list, &query, team)
                                                                                            .into_iter()
                                                                                            .map(|ans| {
                                                                                                let label = format!("[{}] {} ({})", ans.code, ans.name, ans.kind);
                                                                                                view! { <option value=ans.id.to_string()>{label}</option> }
                                                                                            })
                                                                                            .collect_view()
                                                                                    })
                                                                                }}
                                                                            </select>
                                                                            {move || tab_id_sv.with_value(|tid| read_ticket_tab(&open_tabs, tid, |t| t.answer_notice.clone())).flatten().map(|msg| view! {
                                                                                <div class="tc-alert-success" role="status" data-target="helpdesk-answer-notice">{msg}</div>
                                                                            })}
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
                                                                            <div class="tc-field">
                                                                                <label class="tc-label" for="ticket-reply-attach">"Attachment"</label>
                                                                                <input
                                                                                    id="ticket-reply-attach"
                                                                                    data-target="ticket-reply-attach"
                                                                                    class="tc-input"
                                                                                    type="file"
                                                                                    disabled=move || tab_id_sv.with_value(|tid| read_ticket_tab(&open_tabs, tid, |t| t.uploading).unwrap_or(false))
                                                                                    on:change=on_attach_file
                                                                                />
                                                                                {move || tab_id_sv.with_value(|tid| read_ticket_tab(&open_tabs, tid, |t| t.uploading)).unwrap_or(false).then(|| view! {
                                                                                    <div style="font-size: 12px; color: var(--on-surface-variant);" data-target="ticket-reply-uploading">"Uploading..."</div>
                                                                                })}
                                                                                <div class="tc-chip-row" data-target="ticket-reply-attachments">
                                                                                    {move || {
                                                                                        let files = tab_id_sv
                                                                                            .with_value(|tid| read_ticket_tab(&open_tabs, tid, |t| t.reply_attachments.clone()))
                                                                                            .unwrap_or_default();
                                                                                        files.into_iter().map(|file| {
                                                                                            let id = file.id;
                                                                                            let label = format!("{} ({}) ✕", file.filename, format_file_size(i64::from(file.size_bytes)));
                                                                                            view! {
                                                                                                <button
                                                                                                    type="button"
                                                                                                    class="tc-chip"
                                                                                                    data-target="ticket-reply-attachment-remove"
                                                                                                    data-filename=file.filename.clone()
                                                                                                    title="Remove from this reply"
                                                                                                    on:click=move |_| tab_id_sv.with_value(|tid| update_ticket_tab(&open_tabs, tid, |t| t.reply_attachments.retain(|f| f.id != id)))
                                                                                                >
                                                                                                    {label}
                                                                                                </button>
                                                                                            }
                                                                                        }).collect_view()
                                                                                    }}
                                                                                </div>
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

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::{TimeZone, Utc};
    use tradocraft_api_client::helpdesk::TeamMember;

    fn answer(
        code: &str,
        name: &str,
        kind: &str,
        team: Option<Uuid>,
        active: bool,
    ) -> PreparedAnswer {
        PreparedAnswer {
            id: Uuid::new_v4(),
            code: code.to_string(),
            name: name.to_string(),
            category: Some("shipping".to_string()),
            kind: kind.to_string(),
            team_id: team,
            keywords: vec!["tracking".to_string()],
            active,
            updated_at: Utc.with_ymd_and_hms(2026, 11, 1, 0, 0, 0).unwrap(),
            texts: Vec::new(),
        }
    }

    #[test]
    fn answer_target_routes_internal_notes_to_the_note() {
        assert_eq!(answer_target("internal_note"), AnswerTarget::Note);
        assert_eq!(answer_target("reply"), AnswerTarget::Reply);
        assert_eq!(answer_target("handover"), AnswerTarget::Reply);
    }

    #[test]
    fn filter_answers_matches_code_name_keyword_and_ignores_slash() {
        let list = vec![
            answer("DELIVERY", "Delivery date", "reply", None, true),
            answer("SORRY", "Apology", "reply", None, true),
            answer("OLD", "Delivery old", "reply", None, false),
        ];
        assert_eq!(filter_answers(&list, "", None).len(), 2);
        assert_eq!(filter_answers(&list, "/deliv", None).len(), 1);
        assert_eq!(filter_answers(&list, "apology", None)[0].code, "SORRY");
        assert_eq!(filter_answers(&list, "TRACKING", None).len(), 2);
        assert_eq!(filter_answers(&list, "SHIPPING", None).len(), 2);
        assert!(filter_answers(&list, "zzz", None).is_empty());
    }

    #[test]
    fn filter_answers_respects_the_ticket_team() {
        let team_a = Uuid::new_v4();
        let team_b = Uuid::new_v4();
        let list = vec![
            answer("ALL", "Company wide", "reply", None, true),
            answer("A", "Team A", "reply", Some(team_a), true),
            answer("B", "Team B", "reply", Some(team_b), true),
        ];
        let codes = |team| {
            filter_answers(&list, "", team)
                .iter()
                .map(|a| a.code.clone())
                .collect::<Vec<_>>()
        };
        assert_eq!(codes(Some(team_a)), vec!["ALL", "A"]);
        assert_eq!(codes(None), vec!["ALL"]);
    }

    #[test]
    fn merge_draft_appends_with_blank_line() {
        assert_eq!(merge_draft("", "Hello"), "Hello");
        assert_eq!(merge_draft("  \n", "Hello"), "Hello");
        assert_eq!(merge_draft("Hi Jan,\n", "Hello"), "Hi Jan,\n\nHello");
    }

    #[test]
    fn rendered_notice_mentions_language_and_fallback() {
        let ok = rendered_notice("DELIVERY", AnswerTarget::Reply, "nl", false);
        assert!(ok.contains("[DELIVERY]") && ok.contains("reply") && ok.contains("NL"));
        assert!(!ok.contains("no text"));
        let fb = rendered_notice("DELIVERY", AnswerTarget::Note, "en", true);
        assert!(fb.contains("internal note") && fb.contains("no text in the ticket's language"));
    }

    #[test]
    fn format_file_size_scales_units() {
        assert_eq!(format_file_size(0), "0 B");
        assert_eq!(format_file_size(-5), "0 B");
        assert_eq!(format_file_size(1023), "1023 B");
        assert_eq!(format_file_size(1536), "1.5 KB");
        assert_eq!(format_file_size(5 * 1024 * 1024), "5.0 MB");
    }

    #[test]
    fn validate_attachment_checks_name_size_and_count() {
        assert!(validate_attachment("a.pdf", 10, 0).is_ok());
        assert!(validate_attachment(" ", 10, 0).is_err());
        assert!(validate_attachment("a.pdf", 0, 0).is_err());
        assert!(validate_attachment("a.pdf", MAX_ATTACHMENT_BYTES + 1, 0).is_err());
        assert!(validate_attachment("a.pdf", MAX_ATTACHMENT_BYTES, 0).is_ok());
        assert!(validate_attachment("a.pdf", 10, MAX_ATTACHMENTS).is_err());
    }

    #[test]
    fn assignment_from_form_parses_and_clears() {
        let team = Uuid::new_v4();
        let owner = Uuid::new_v4();
        let req = assignment_from_form(&team.to_string(), &format!(" {owner} ")).unwrap();
        assert_eq!(req.team_id, Some(team));
        assert_eq!(req.owner_user_id, Some(owner));
        let cleared = assignment_from_form("", "  ").unwrap();
        assert_eq!(cleared, AssignmentInput::default());
        assert!(assignment_from_form("nope", "").is_err());
    }

    #[test]
    fn owner_options_dedup_sort_and_filter_by_team() {
        let (u1, u2) = (Uuid::new_v4(), Uuid::new_v4());
        let member = |id, name: &str| TeamMember {
            user_id: id,
            display_name: name.to_string(),
            is_lead: false,
        };
        let team = |name: &str, members| Team {
            id: Uuid::new_v4(),
            name: name.to_string(),
            active: true,
            require_checklist_done: false,
            members,
        };
        let a = team("A", vec![member(u2, "Zed"), member(u1, "alice")]);
        let b = team("B", vec![member(u1, "alice")]);
        let teams = vec![a.clone(), b.clone()];
        let all = owner_options(&teams, None);
        assert_eq!(
            all.iter().map(|(_, n)| n.as_str()).collect::<Vec<_>>(),
            vec!["alice", "Zed"]
        );
        assert_eq!(owner_options(&teams, Some(b.id)).len(), 1);
        assert!(owner_options(&teams, Some(Uuid::new_v4())).is_empty());
    }
}
