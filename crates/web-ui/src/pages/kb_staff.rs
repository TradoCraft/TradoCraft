//! Staff side of the Knowledge Base: search and read articles of every status by category and
//! language, and (with `kb.write`) create and edit them with a visibility choice. Publishing,
//! unpublishing and archiving need `kb.admin`, as on the server. Mirrors
//! `app/lib/features/kb/kb_page.dart` and `kb_entry_screen.dart`.

use std::future::Future;

use leptos::ev::SubmitEvent;
use leptos::prelude::*;
use leptos::task::spawn_local;
use tradocraft_api_client::kb::{
    KbCategory, KbEntry, KbEntryInput, KbEntrySummary, KbEntryText, ListKbEntriesParams,
    KB_LANGUAGES, KB_VISIBILITIES,
};
use tradocraft_api_client::{ApiError, Client};
use uuid::Uuid;

use crate::api::{resolve_base_url, ConnectionMode};
use crate::pages::kb::snippet_segments;
use crate::pages::{opt_trimmed, set_alive};
use crate::state::AppContext;

/// Permission strings as exposed by `GET /api/v1/me`.
const PERM_READ: &str = "kb.read";
const PERM_WRITE: &str = "kb.write";
const PERM_ADMIN: &str = "kb.admin";

const STATUSES: [&str; 3] = ["draft", "published", "archived"];

fn visibility_label(visibility: &str) -> &'static str {
    match visibility {
        "internal" => "Staff only",
        "portal" => "Customers (portal)",
        "public" => "Public",
        _ => "Unknown",
    }
}

fn status_label(status: &str) -> &'static str {
    match status {
        "draft" => "Draft",
        "published" => "Published",
        "archived" => "Archived",
        _ => "Unknown",
    }
}

fn status_badge_class(status: &str) -> &'static str {
    match status {
        "published" => "tc-badge tc-badge-success",
        "draft" => "tc-badge tc-badge-warning",
        _ => "tc-badge",
    }
}

/// Splits a comma separated tag field; blanks and repeats are dropped.
fn parse_tags(raw: &str) -> Vec<String> {
    let mut tags: Vec<String> = Vec::new();
    for tag in raw.split(',') {
        let tag = tag.trim();
        if !tag.is_empty() && !tags.iter().any(|t| t.eq_ignore_ascii_case(tag)) {
            tags.push(tag.to_string());
        }
    }
    tags
}

/// One language of the editor form.
#[derive(Debug, Clone, PartialEq, Eq)]
struct TextDraft {
    language: String,
    title: String,
    summary: String,
    body: String,
}

impl TextDraft {
    fn is_blank(&self) -> bool {
        self.title.trim().is_empty()
            && self.summary.trim().is_empty()
            && self.body.trim().is_empty()
    }
}

/// Builds the create / edit payload. Fields the form does not show (related entries, products,
/// ticket categories) are kept from `base` when editing.
fn build_input(
    base: Option<&KbEntry>,
    category: &str,
    visibility: &str,
    tags: &str,
    drafts: &[TextDraft],
) -> Result<KbEntryInput, String> {
    if !KB_VISIBILITIES.contains(&visibility) {
        return Err("Choose who can see the article.".to_string());
    }
    let category_id = match opt_trimmed(category) {
        Some(raw) => Some(Uuid::parse_str(&raw).map_err(|_| "Category is not valid.".to_string())?),
        None => None,
    };
    let mut texts = Vec::new();
    for draft in drafts.iter().filter(|d| !d.is_blank()) {
        if draft.title.trim().is_empty() {
            return Err(format!("A title is required ({}).", draft.language));
        }
        texts.push(KbEntryText {
            language: draft.language.clone(),
            title: draft.title.trim().to_string(),
            summary: draft.summary.trim().to_string(),
            body: draft.body.clone(),
        });
    }
    if texts.is_empty() {
        return Err("Write the article in at least one language.".to_string());
    }
    let mut input = base.map(KbEntry::to_input).unwrap_or(KbEntryInput {
        category_id: None,
        visibility: String::new(),
        texts: Vec::new(),
        tags: Vec::new(),
        related_ids: Vec::new(),
        product_ids: Vec::new(),
        ticket_categories: Vec::new(),
    });
    input.category_id = category_id;
    input.visibility = visibility.to_string();
    input.texts = texts;
    input.tags = parse_tags(tags);
    Ok(input)
}

/// The text to show: the preferred language, else English, else the first one.
fn shown_text<'a>(entry: &'a KbEntry, preferred: &str) -> Option<&'a KbEntryText> {
    entry
        .text_for(preferred)
        .or_else(|| entry.text_for("en"))
        .or_else(|| entry.texts.first())
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
struct Filters {
    q: String,
    category: String,
    language: String,
    status: String,
    visibility: String,
    /// Rows requested; 0 means one page. "Load more" adds a page, any filter change resets it.
    limit: u32,
}

const PAGE: u32 = 100;

impl Filters {
    fn effective_limit(&self) -> u32 {
        if self.limit == 0 {
            PAGE
        } else {
            self.limit
        }
    }
}

fn list_params(filters: &Filters) -> ListKbEntriesParams {
    ListKbEntriesParams {
        q: opt_trimmed(&filters.q),
        category_id: opt_trimmed(&filters.category).and_then(|c| Uuid::parse_str(&c).ok()),
        tag: None,
        language: opt_trimmed(&filters.language),
        visibility: opt_trimmed(&filters.visibility),
        status: opt_trimmed(&filters.status),
        limit: Some(i64::from(filters.effective_limit())),
        offset: Some(0),
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
            "Knowledge Base staff endpoints require a live API connection; switch to Dev User or Bearer mode on the sign-in screen."
                .to_string(),
        )),
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum EditorMode {
    New,
    Edit(Uuid),
}

/// The editor holds all five languages; only the selected one is shown.
#[derive(Clone, Copy)]
struct TextSlot {
    language: &'static str,
    title: RwSignal<String>,
    summary: RwSignal<String>,
    body: RwSignal<String>,
}

impl TextSlot {
    fn new(language: &'static str) -> Self {
        Self {
            language,
            title: RwSignal::new(String::new()),
            summary: RwSignal::new(String::new()),
            body: RwSignal::new(String::new()),
        }
    }

    fn draft(self) -> TextDraft {
        TextDraft {
            language: self.language.to_string(),
            title: self.title.get_untracked(),
            summary: self.summary.get_untracked(),
            body: self.body.get_untracked(),
        }
    }

    fn load(self, entry: Option<&KbEntry>) {
        let text = entry.and_then(|e| e.text_for(self.language));
        self.title
            .set(text.map(|t| t.title.clone()).unwrap_or_default());
        self.summary
            .set(text.map(|t| t.summary.clone()).unwrap_or_default());
        self.body
            .set(text.map(|t| t.body.clone()).unwrap_or_default());
    }
}

/// Everything the handlers share. All fields are `Copy`.
#[derive(Clone, Copy)]
struct StaffUi {
    ctx: AppContext,
    error: RwSignal<Option<String>>,
    reload: RwSignal<u64>,
    selected: RwSignal<Option<Uuid>>,
    active: RwSignal<Option<KbEntry>>,
    loading_article: RwSignal<bool>,
    article_gen: RwSignal<u64>,
    view_lang: RwSignal<String>,
    editor: RwSignal<Option<EditorMode>>,
    edit_lang: RwSignal<&'static str>,
    slots: [TextSlot; 5],
    edit_category: RwSignal<String>,
    edit_visibility: RwSignal<String>,
    edit_tags: RwSignal<String>,
    saving: RwSignal<bool>,
}

impl StaffUi {
    fn client(self) -> Result<Client, ApiError> {
        match self.ctx.session.get_untracked() {
            Some(session) => live_client(&session.connection),
            None => Err(ApiError::InvalidConfig(
                "Sign in to use the staff Knowledge Base.".to_string(),
            )),
        }
    }

    fn open(self, id: Uuid) {
        let req_gen = self.article_gen.get_untracked().wrapping_add(1);
        self.article_gen.set(req_gen);
        self.selected.set(Some(id));
        self.active.set(None);
        self.editor.set(None);
        self.loading_article.set(true);
        self.error.set(None);
        let client = self.client();
        spawn_local(async move {
            let res = match client {
                Ok(client) => client.get_kb_entry(id).await,
                Err(err) => Err(err),
            };
            // The page may have been left while the request was running.
            if self.article_gen.try_get_untracked() != Some(req_gen) {
                return;
            }
            self.loading_article.set(false);
            match res {
                Ok(entry) => {
                    self.show(&entry);
                    self.active.set(Some(entry));
                }
                Err(err) => self.error.set(Some(err.user_message())),
            }
        });
    }

    /// Picks the language the reader opens in.
    fn show(self, entry: &KbEntry) {
        let preferred = self.view_lang.get_untracked();
        if let Some(text) = shown_text(entry, &preferred) {
            self.view_lang.set(text.language.clone());
        }
    }

    fn close(self) {
        self.article_gen.update(|g| *g = g.wrapping_add(1));
        self.selected.set(None);
        self.active.set(None);
        self.editor.set(None);
        self.loading_article.set(false);
    }

    fn start_new(self) {
        // A pending article request must not fill or block the new editor.
        self.article_gen.update(|g| *g = g.wrapping_add(1));
        self.loading_article.set(false);
        for slot in self.slots {
            slot.load(None);
        }
        self.edit_category.set(String::new());
        self.edit_visibility.set("internal".to_string());
        self.edit_tags.set(String::new());
        self.edit_lang.set("en");
        self.error.set(None);
        self.selected.set(None);
        self.active.set(None);
        self.editor.set(Some(EditorMode::New));
    }

    fn start_edit(self, entry: &KbEntry) {
        self.article_gen.update(|g| *g = g.wrapping_add(1));
        self.loading_article.set(false);
        for slot in self.slots {
            slot.load(Some(entry));
        }
        self.edit_category
            .set(entry.category_id.map(|c| c.to_string()).unwrap_or_default());
        self.edit_visibility.set(entry.visibility.clone());
        self.edit_tags.set(entry.tags.join(", "));
        let first = shown_text(entry, "en")
            .and_then(|t| KB_LANGUAGES.iter().find(|l| **l == t.language))
            .copied()
            .unwrap_or("en");
        self.edit_lang.set(first);
        self.error.set(None);
        self.editor.set(Some(EditorMode::Edit(entry.id)));
    }

    /// Runs a status change and shows the entry the server returns.
    fn transition<F, Fut>(self, f: F)
    where
        F: FnOnce(Client) -> Fut + 'static,
        Fut: Future<Output = Result<KbEntry, ApiError>> + 'static,
    {
        let client = self.client();
        let owner = self.article_gen.get_untracked();
        self.saving.set(true);
        spawn_local(async move {
            let res = match client {
                Ok(client) => f(client).await,
                Err(err) => Err(err),
            };
            if set_alive(self.saving, false) {
                // Show the result only while the same article is still open.
                if self.article_gen.get_untracked() == owner {
                    match res {
                        Ok(entry) => {
                            self.error.set(None);
                            self.active.set(Some(entry));
                        }
                        Err(err) => self.error.set(Some(err.user_message())),
                    }
                }
                self.reload.update(|n| *n += 1);
            }
        });
    }

    /// Saves the editor and optionally publishes right after, so the chosen visibility is the
    /// one readers get.
    fn save(self, publish: bool) {
        let Some(mode) = self.editor.get_untracked() else {
            return;
        };
        let base = match mode {
            EditorMode::Edit(_) => self.active.get_untracked(),
            EditorMode::New => None,
        };
        let drafts: Vec<TextDraft> = self.slots.iter().map(|s| s.draft()).collect();
        let input = match build_input(
            base.as_ref(),
            &self.edit_category.get_untracked(),
            &self.edit_visibility.get_untracked(),
            &self.edit_tags.get_untracked(),
            &drafts,
        ) {
            Ok(input) => input,
            Err(msg) => {
                self.error.set(Some(msg));
                return;
            }
        };
        let client = self.client();
        // The editor (or article) this save belongs to; a newer one must not be overwritten.
        let owner = self.article_gen.get_untracked();
        self.saving.set(true);
        self.error.set(None);
        spawn_local(async move {
            let client = match client {
                Ok(client) => client,
                Err(err) => {
                    if set_alive(self.saving, false) {
                        self.error.set(Some(err.user_message()));
                    }
                    return;
                }
            };
            let saved = match mode {
                EditorMode::New => client.create_kb_entry(&input).await,
                EditorMode::Edit(id) => client.update_kb_entry(id, &input).await,
            };
            let saved = match saved {
                Ok(entry) => entry,
                Err(err) => {
                    if set_alive(self.saving, false) && self.article_gen.get_untracked() == owner {
                        self.error.set(Some(err.user_message()));
                    }
                    return;
                }
            };
            let mut entry = saved;
            let mut publish_error = None;
            if publish {
                match client.publish_kb_entry(entry.id).await {
                    Ok(published) => entry = published,
                    Err(err) => publish_error = Some(err.user_message()),
                }
            }
            // The writes are committed; only touch the screen if it still shows this editor.
            if !set_alive(self.saving, false) {
                return;
            }
            if self.article_gen.get_untracked() == owner {
                self.selected.set(Some(entry.id));
                match publish_error {
                    Some(msg) => {
                        // Keep the editor open on the saved article, so a retry updates it.
                        self.editor.set(Some(EditorMode::Edit(entry.id)));
                        self.error
                            .set(Some(format!("Saved, but not published: {msg}")));
                    }
                    None => self.editor.set(None),
                }
                self.show(&entry);
                self.active.set(Some(entry));
            }
            self.reload.update(|n| *n += 1);
        });
    }
}

#[component]
pub fn KbStaff() -> impl IntoView {
    let ctx = expect_context::<AppContext>();

    let can_read = Memo::new(move |_| {
        ctx.session
            .with(|s| s.as_ref().is_some_and(|a| a.me.has_permission(PERM_READ)))
    });
    let can_write = Memo::new(move |_| {
        ctx.session
            .with(|s| s.as_ref().is_some_and(|a| a.me.has_permission(PERM_WRITE)))
    });
    let can_admin = Memo::new(move |_| {
        ctx.session
            .with(|s| s.as_ref().is_some_and(|a| a.me.has_permission(PERM_ADMIN)))
    });

    let filters = RwSignal::new(Filters::default());
    let entries = RwSignal::new(Vec::<KbEntrySummary>::new());
    let categories = RwSignal::new(Vec::<KbCategory>::new());
    let loading = RwSignal::new(false);
    let list_error = RwSignal::new(Option::<String>::None);
    let list_gen = StoredValue::new(0_u64);

    let ui = StaffUi {
        ctx,
        error: RwSignal::new(None),
        reload: RwSignal::new(0),
        selected: RwSignal::new(None),
        active: RwSignal::new(None),
        loading_article: RwSignal::new(false),
        article_gen: RwSignal::new(0),
        view_lang: RwSignal::new(String::new()),
        editor: RwSignal::new(None),
        edit_lang: RwSignal::new("en"),
        slots: KB_LANGUAGES.map(TextSlot::new),
        edit_category: RwSignal::new(String::new()),
        edit_visibility: RwSignal::new("internal".to_string()),
        edit_tags: RwSignal::new(String::new()),
        saving: RwSignal::new(false),
    };

    // Categories, once per sign-in and after changes.
    Effect::new(move |_| {
        let _ = ui.reload.get();
        if !can_read.get() {
            categories.set(Vec::new());
            return;
        }
        let client = ui.client();
        spawn_local(async move {
            if let Ok(client) = client {
                if let Ok(list) = client.list_kb_categories().await {
                    categories.set(list);
                }
            }
        });
    });

    // The list follows the filters.
    Effect::new(move |_| {
        let _ = ui.reload.get();
        let params = list_params(&filters.get());
        let readable = can_read.get();
        let req_gen = list_gen
            .try_update_value(|g| {
                *g += 1;
                *g
            })
            .unwrap_or(0);
        if !readable {
            entries.set(Vec::new());
            loading.set(false);
            return;
        }
        let client = ui.client();
        loading.set(true);
        spawn_local(async move {
            let res = match client {
                Ok(client) => client.list_kb_entries(&params).await,
                Err(err) => Err(err),
            };
            if list_gen.try_get_value() != Some(req_gen) {
                return;
            }
            loading.set(false);
            match res {
                Ok(list) => {
                    list_error.set(None);
                    entries.set(list);
                }
                Err(err) => list_error.set(Some(err.user_message())),
            }
        });
    });

    let category_label = move |id: Option<Uuid>| -> String {
        let Some(id) = id else {
            return "—".to_string();
        };
        let lang = filters.with(|f| f.language.clone());
        let lang = if lang.is_empty() {
            "en".to_string()
        } else {
            lang
        };
        categories.with(|list| {
            list.iter()
                .find(|c| c.id == id)
                .map(|c| c.name_for(&lang))
                .unwrap_or_else(|| "—".to_string())
        })
    };

    view! {
        <div data-target="kb-staff-page">
            <Show
                when=move || can_read.get()
                fallback=|| view! {
                    <div class="tc-card" data-target="kb-staff-unavailable">
                        <p style="margin: 0;">
                            "Sign in with a user who has the Knowledge Base permission (kb.read) to search and read all articles."
                        </p>
                    </div>
                }
            >
                <div class="tc-page-header">
                    <div>
                        <p class="tc-page-subtitle" data-target="kb-staff-total">
                            {move || format!("{} articles", entries.with(Vec::len))}
                        </p>
                    </div>
                    <div class="tc-header-actions">
                        <Show when=move || can_write.get()>
                            <button
                                type="button"
                                data-target="kb-staff-new"
                                class="tc-btn tc-btn-primary"
                                on:click=move |_| ui.start_new()
                            >
                                "New article"
                            </button>
                        </Show>
                        <button
                            type="button"
                            data-target="kb-staff-refresh"
                            class="tc-btn"
                            disabled=move || loading.get()
                            on:click=move |_| ui.reload.update(|n| *n += 1)
                        >
                            {move || if loading.get() { "Loading..." } else { "Refresh" }}
                        </button>
                    </div>
                </div>

                <div class="tc-toolbar">
                    <input
                        data-target="kb-staff-search"
                        class="tc-input"
                        style="min-width: 240px;"
                        type="search"
                        placeholder="Search all articles..."
                        prop:value=move || filters.with(|f| f.q.clone())
                        on:input=move |ev| {
                            let v = event_target_value(&ev);
                            filters.update(|f| {
                                f.q = v;
                                f.limit = 0;
                            });
                        }
                    />
                    <select
                        data-target="kb-staff-category-filter"
                        class="tc-select"
                        prop:value=move || filters.with(|f| f.category.clone())
                        on:change=move |ev| {
                            let v = event_target_value(&ev);
                            filters.update(|f| {
                                f.category = v;
                                f.limit = 0;
                            });
                        }
                    >
                        <option value="">"All categories"</option>
                        <For
                            each=move || categories.get()
                            key=|c| (c.id, c.entry_count, c.name_for("en"))
                            children=move |cat| {
                                let value = cat.id.to_string();
                                let label = move || {
                                    let lang = filters.with(|f| f.language.clone());
                                    format!(
                                        "{} ({})",
                                        cat.name_for(if lang.is_empty() { "en" } else { &lang }),
                                        cat.entry_count
                                    )
                                };
                                view! { <option value=value>{label}</option> }
                            }
                        />
                    </select>
                    <select
                        data-target="kb-staff-language-filter"
                        class="tc-select"
                        prop:value=move || filters.with(|f| f.language.clone())
                        on:change=move |ev| {
                            let v = event_target_value(&ev);
                            filters.update(|f| {
                                f.language = v;
                                f.limit = 0;
                            });
                        }
                    >
                        <option value="">"Company default language"</option>
                        {KB_LANGUAGES
                            .into_iter()
                            .map(|l| view! { <option value=l>{l}</option> })
                            .collect_view()}
                    </select>
                    <select
                        data-target="kb-staff-status-filter"
                        class="tc-select"
                        prop:value=move || filters.with(|f| f.status.clone())
                        on:change=move |ev| {
                            let v = event_target_value(&ev);
                            filters.update(|f| {
                                f.status = v;
                                f.limit = 0;
                            });
                        }
                    >
                        <option value="">"Any status"</option>
                        {STATUSES
                            .into_iter()
                            .map(|s| view! { <option value=s>{status_label(s)}</option> })
                            .collect_view()}
                    </select>
                    <select
                        data-target="kb-staff-visibility-filter"
                        class="tc-select"
                        prop:value=move || filters.with(|f| f.visibility.clone())
                        on:change=move |ev| {
                            let v = event_target_value(&ev);
                            filters.update(|f| {
                                f.visibility = v;
                                f.limit = 0;
                            });
                        }
                    >
                        <option value="">"Any visibility"</option>
                        {KB_VISIBILITIES
                            .into_iter()
                            .map(|v| view! { <option value=v>{visibility_label(v)}</option> })
                            .collect_view()}
                    </select>
                </div>

                {move || list_error.get().map(|msg| view! {
                    <div class="tc-alert-error" style="margin-bottom: var(--space-md);" role="alert" data-target="kb-staff-list-error">
                        {msg}
                    </div>
                })}

                {move || ui.error.get().map(|msg| view! {
                    <div class="tc-alert-error" style="margin-bottom: var(--space-md);" role="alert" data-target="kb-staff-error">
                        {msg}
                    </div>
                })}

                {move || (!can_write.get()).then(|| view! {
                    <p class="tc-page-subtitle" data-target="kb-staff-readonly-note" style="margin-bottom: var(--space-md);">
                        "You can read articles. Creating and editing needs the kb.write permission."
                    </p>
                })}

                <div class=move || {
                    if ui.selected.get().is_some() || ui.editor.get().is_some() {
                        "tc-workspace-split"
                    } else {
                        ""
                    }
                }>
                    <div class="tc-table-wrap" data-target="kb-staff-list">
                        <table class="tc-table">
                            <thead>
                                <tr>
                                    <th>"Number"</th>
                                    <th>"Article"</th>
                                    <th>"Category"</th>
                                    <th>"Lang"</th>
                                    <th>"Status"</th>
                                    <th>"Visibility"</th>
                                    <th>"Updated"</th>
                                </tr>
                            </thead>
                            <tbody>
                                <Show
                                    when=move || !entries.with(Vec::is_empty)
                                    fallback=move || view! {
                                        <tr>
                                            <td colspan="7" data-target="kb-staff-empty" style="text-align: center; color: var(--on-surface-variant); padding: var(--space-xl);">
                                                {move || if loading.get() { "Loading articles..." } else { "No articles match." }}
                                            </td>
                                        </tr>
                                    }
                                >
                                    <For
                                        each=move || entries.get()
                                        key=|item| (
                                            item.id,
                                            item.updated_at,
                                            item.status.clone(),
                                            item.visibility.clone(),
                                            item.snippet.clone(),
                                            item.title.clone(),
                                            item.language.clone(),
                                        )
                                        children=move |item| {
                                            let id = item.id;
                                            let row_target = format!("kb-staff-row-{}", item.number);
                                            let segs = snippet_segments(&item.snippet);
                                            let category_id = item.category_id;
                                            let updated = item.updated_at.date_naive().to_string();
                                            view! {
                                                <tr
                                                    class=move || if ui.selected.get() == Some(id) {
                                                        "tc-row-clickable tc-row-selected"
                                                    } else {
                                                        "tc-row-clickable"
                                                    }
                                                    data-target=row_target
                                                    on:click=move |_| ui.open(id)
                                                >
                                                    <td class="tc-mono">{item.number}</td>
                                                    <td>
                                                        <button
                                                            type="button"
                                                            style="background: none; border: none; padding: 0; font: inherit; font-weight: 600; color: inherit; cursor: pointer; text-align: left;"
                                                            on:click=move |ev| {
                                                                ev.stop_propagation();
                                                                ui.open(id);
                                                            }
                                                        >
                                                            {item.title}
                                                        </button>
                                                        {(!segs.is_empty()).then(|| view! {
                                                            <div style="font-size: 12px; color: var(--on-surface-variant); margin-top: 2px;">
                                                                {segs.into_iter().map(|(text, hit)| {
                                                                    if hit {
                                                                        view! { <mark>{text}</mark> }.into_any()
                                                                    } else {
                                                                        view! { <span>{text}</span> }.into_any()
                                                                    }
                                                                }).collect_view()}
                                                            </div>
                                                        })}
                                                    </td>
                                                    <td>{move || category_label(category_id)}</td>
                                                    <td>
                                                        <span class=if item.fallback { "tc-badge tc-badge-warning" } else { "tc-badge" }>
                                                            {item.language}
                                                        </span>
                                                    </td>
                                                    <td>
                                                        <span class=status_badge_class(&item.status)>
                                                            {status_label(&item.status)}
                                                        </span>
                                                    </td>
                                                    <td>{visibility_label(&item.visibility)}</td>
                                                    <td class="tc-mono">{updated}</td>
                                                </tr>
                                            }
                                        }
                                    />
                                </Show>
                            </tbody>
                        </table>
                        <Show when=move || { let shown = entries.with(Vec::len) as u32; shown >= filters.with(Filters::effective_limit) }>
                            <div style="padding: var(--space-md); text-align: center;">
                                <button
                                    type="button"
                                    data-target="kb-staff-load-more"
                                    class="tc-btn"
                                    disabled=move || loading.get()
                                    on:click=move |_| filters.update(|f| f.limit = f.effective_limit() + PAGE)
                                >
                                    "Load more"
                                </button>
                            </div>
                        </Show>
                    </div>

                    {move || ui.editor.get().map(|mode| editor_view(ui, mode, categories, can_admin))}

                    {move || (ui.editor.get().is_none() && ui.selected.get().is_some()).then(|| {
                        reader_view(ui, categories, can_write, can_admin)
                    })}
                </div>
            </Show>
        </div>
    }
}

fn reader_view(
    ui: StaffUi,
    categories: RwSignal<Vec<KbCategory>>,
    can_write: Memo<bool>,
    can_admin: Memo<bool>,
) -> impl IntoView {
    view! {
        <aside class="tc-card tc-detail-drawer" data-target="kb-staff-article-view">
            <div class="tc-page-header" style="margin-bottom: 0;">
                <div>
                    <h2 class="tc-page-title" style="font-size: 17px;" data-target="kb-staff-article-title">
                        {move || {
                            ui.active
                                .with(|a| {
                                    a.as_ref().and_then(|e| {
                                        shown_text(e, &ui.view_lang.get()).map(|t| t.title.clone())
                                    })
                                })
                                .unwrap_or_else(|| "Article".to_string())
                        }}
                    </h2>
                    <p class="tc-page-subtitle tc-mono">
                        {move || {
                            if ui.loading_article.get() {
                                "Loading article...".to_string()
                            } else {
                                ui.active
                                    .with(|a| {
                                        a.as_ref().map(|e| {
                                            format!("{} · v{} · {}", e.number, e.version, e.updated_at.date_naive())
                                        })
                                    })
                                    .unwrap_or_default()
                            }
                        }}
                    </p>
                </div>
                <button
                    type="button"
                    class="tc-btn tc-btn-sm tc-btn-ghost"
                    data-target="kb-staff-article-close"
                    on:click=move |_| ui.close()
                >
                    "Close"
                </button>
            </div>

            {move || ui.active.get().map(|entry| {
                let status = entry.status.clone();
                let id = entry.id;
                let entry_for_edit = entry.clone();
                let category = entry.category_id.map(|cid| {
                    categories.with(|list| {
                        list.iter()
                            .find(|c| c.id == cid)
                            .map(|c| c.name_for(&ui.view_lang.get_untracked()))
                            .unwrap_or_default()
                    })
                });
                let text = shown_text(&entry, &ui.view_lang.get()).cloned();
                view! {
                    <div style="display: flex; flex-direction: column; gap: var(--space-md);">
                        <div class="tc-chip-row">
                            <span class=status_badge_class(&entry.status) data-target="kb-staff-article-status">
                                {status_label(&entry.status)}
                            </span>
                            <span class="tc-badge tc-badge-primary" data-target="kb-staff-article-visibility">
                                {visibility_label(&entry.visibility)}
                            </span>
                            {category.filter(|c| !c.is_empty()).map(|c| view! { <span class="tc-badge">{c}</span> })}
                            {entry.tags.iter().map(|tag| view! { <span class="tc-badge">{tag.clone()}</span> }).collect_view()}
                        </div>

                        <div class="tc-chip-row">
                            {entry.texts.iter().map(|t| {
                                let code = t.language.clone();
                                let click = code.clone();
                                let active_code = code.clone();
                                view! {
                                    <button
                                        type="button"
                                        data-target=format!("kb-staff-article-lang-{code}")
                                        class=move || if ui.view_lang.get() == active_code {
                                            "tc-chip tc-inline-tab-active"
                                        } else {
                                            "tc-chip"
                                        }
                                        on:click=move |_| ui.view_lang.set(click.clone())
                                    >
                                        {code.clone()}
                                    </button>
                                }
                            }).collect_view()}
                        </div>

                        {text.map(|t| view! {
                            <div style="display: flex; flex-direction: column; gap: var(--space-sm);">
                                {(!t.summary.trim().is_empty()).then(|| view! {
                                    <p style="margin: 0; color: var(--on-surface-variant); font-size: 13px;">{t.summary.clone()}</p>
                                })}
                                <div
                                    data-target="kb-staff-article-body"
                                    style="white-space: pre-wrap; line-height: 1.55; font-size: 13px; padding: var(--space-md); background: var(--surface); border: 1px solid var(--outline-variant); border-radius: var(--radius-sm);"
                                >
                                    {t.body}
                                </div>
                            </div>
                        })}

                        {(!entry.related.is_empty()).then(|| view! {
                            <div class="tc-field">
                                <span class="tc-label">"Related articles"</span>
                                <div style="display: flex; flex-direction: column; gap: var(--space-xs);">
                                    {entry.related.iter().map(|rel| {
                                        let rel_id = rel.id;
                                        view! {
                                            <button
                                                type="button"
                                                class="tc-btn tc-btn-sm"
                                                style="justify-content: flex-start;"
                                                on:click=move |_| ui.open(rel_id)
                                            >
                                                <span class="tc-mono">{rel.number.clone()}</span>
                                                <span>{rel.title.clone()}</span>
                                            </button>
                                        }
                                    }).collect_view()}
                                </div>
                            </div>
                        })}

                        <div class="tc-form-actions">
                            <Show when=move || can_write.get()>
                                {
                                    let entry = entry_for_edit.clone();
                                    view! {
                                        <button
                                            type="button"
                                            data-target="kb-staff-edit"
                                            class="tc-btn"
                                            disabled=move || ui.saving.get()
                                            on:click=move |_| ui.start_edit(&entry)
                                        >
                                            "Edit"
                                        </button>
                                    }
                                }
                            </Show>
                            <Show when=move || can_admin.get() && status != "published">
                                <button
                                    type="button"
                                    data-target="kb-staff-publish"
                                    class="tc-btn tc-btn-primary"
                                    disabled=move || ui.saving.get()
                                    on:click=move |_| ui.transition(move |c| async move { c.publish_kb_entry(id).await })
                                >
                                    "Publish"
                                </button>
                            </Show>
                            <Show when=move || can_admin.get() && ui.active.with(|a| a.as_ref().is_some_and(|e| e.status == "published"))>
                                <button
                                    type="button"
                                    data-target="kb-staff-unpublish"
                                    class="tc-btn"
                                    disabled=move || ui.saving.get()
                                    on:click=move |_| ui.transition(move |c| async move { c.unpublish_kb_entry(id).await })
                                >
                                    "Unpublish"
                                </button>
                            </Show>
                            <Show when=move || can_admin.get() && ui.active.with(|a| a.as_ref().is_some_and(|e| e.status != "archived"))>
                                <button
                                    type="button"
                                    data-target="kb-staff-archive"
                                    class="tc-btn"
                                    disabled=move || ui.saving.get()
                                    on:click=move |_| ui.transition(move |c| async move { c.archive_kb_entry(id).await })
                                >
                                    "Archive"
                                </button>
                            </Show>
                        </div>
                        {move || (can_write.get() && !can_admin.get()).then(|| view! {
                            <p class="tc-page-subtitle" data-target="kb-staff-publish-note" style="margin: 0;">
                                "Publishing needs the kb.admin permission."
                            </p>
                        })}
                    </div>
                }
            })}
        </aside>
    }
}

fn editor_view(
    ui: StaffUi,
    mode: EditorMode,
    categories: RwSignal<Vec<KbCategory>>,
    can_admin: Memo<bool>,
) -> impl IntoView {
    let on_submit = move |ev: SubmitEvent| {
        ev.prevent_default();
        ui.save(false);
    };
    let heading = match mode {
        EditorMode::New => "New article",
        EditorMode::Edit(_) => "Edit article",
    };
    // Changing who sees a published article needs kb.admin on the server.
    let visibility_locked = move || {
        !can_admin.get()
            && matches!(mode, EditorMode::Edit(_))
            && ui
                .active
                .with(|a| a.as_ref().is_some_and(|e| e.status == "published"))
    };

    // Publishing a published article would fail after a successful save.
    let already_published = move || {
        matches!(mode, EditorMode::Edit(_))
            && ui
                .active
                .with(|a| a.as_ref().is_some_and(|e| e.status == "published"))
    };

    view! {
        <aside class="tc-card tc-detail-drawer" data-target="kb-staff-editor">
            <div class="tc-page-header" style="margin-bottom: 0;">
                <h2 class="tc-page-title" style="font-size: 17px;">{heading}</h2>
                <button
                    type="button"
                    class="tc-btn tc-btn-sm tc-btn-ghost"
                    data-target="kb-staff-editor-cancel"
                    on:click=move |_| {
                        ui.editor.set(None);
                        ui.error.set(None);
                    }
                >
                    "Cancel"
                </button>
            </div>

            <form class="tc-form-grid" on:submit=on_submit>
                <div class="tc-field">
                    <label class="tc-label" for="kb-editor-category">"Category"</label>
                    <select
                        id="kb-editor-category"
                        data-target="kb-staff-editor-category"
                        class="tc-select"
                        prop:value=move || ui.edit_category.get()
                        on:change=move |ev| ui.edit_category.set(event_target_value(&ev))
                    >
                        <option value="">"No category"</option>
                        {move || categories
                            .get()
                            .into_iter()
                            .map(|c| {
                                let label = c.name_for("en");
                                view! { <option value=c.id.to_string()>{label}</option> }
                            })
                            .collect_view()}
                    </select>
                </div>

                <div class="tc-field">
                    <label class="tc-label" for="kb-editor-visibility">"Visibility"</label>
                    <select
                        id="kb-editor-visibility"
                        data-target="kb-staff-editor-visibility"
                        class="tc-select"
                        disabled=visibility_locked
                        prop:value=move || ui.edit_visibility.get()
                        on:change=move |ev| ui.edit_visibility.set(event_target_value(&ev))
                    >
                        {KB_VISIBILITIES
                            .into_iter()
                            .map(|v| view! { <option value=v>{visibility_label(v)}</option> })
                            .collect_view()}
                    </select>
                </div>

                <div class="tc-field tc-form-span-2">
                    <label class="tc-label" for="kb-editor-tags">"Tags (comma separated)"</label>
                    <input
                        id="kb-editor-tags"
                        data-target="kb-staff-editor-tags"
                        class="tc-input"
                        type="text"
                        prop:value=move || ui.edit_tags.get()
                        on:input=move |ev| ui.edit_tags.set(event_target_value(&ev))
                    />
                </div>

                <div class="tc-field tc-form-span-2">
                    <div class="tc-inline-tabs" role="group" aria-label="Language">
                        {KB_LANGUAGES
                            .into_iter()
                            .map(|lang| view! {
                                <button
                                    type="button"
                                    data-target=format!("kb-staff-editor-lang-{lang}")
                                    class=move || if ui.edit_lang.get() == lang {
                                        "tc-inline-tab-btn tc-inline-tab-active"
                                    } else {
                                        "tc-inline-tab-btn"
                                    }
                                    on:click=move |_| ui.edit_lang.set(lang)
                                >
                                    {lang}
                                </button>
                            })
                            .collect_view()}
                    </div>
                </div>

                {ui.slots
                    .into_iter()
                    .map(|slot| view! {
                        <div
                            class="tc-form-span-2"
                            hidden=move || ui.edit_lang.get() != slot.language
                        >
                          <div style="display: flex; flex-direction: column; gap: var(--space-sm);">
                            <div class="tc-field">
                                <label class="tc-label" for=format!("kb-editor-title-{}", slot.language)>{format!("Title ({})", slot.language)}</label>
                                <input
                                    id=format!("kb-editor-title-{}", slot.language)
                                    data-target=format!("kb-staff-editor-title-{}", slot.language)
                                    class="tc-input"
                                    type="text"
                                    prop:value=move || slot.title.get()
                                    on:input=move |ev| slot.title.set(event_target_value(&ev))
                                />
                            </div>
                            <div class="tc-field">
                                <label class="tc-label" for=format!("kb-editor-summary-{}", slot.language)>"Summary"</label>
                                <input
                                    id=format!("kb-editor-summary-{}", slot.language)
                                    data-target=format!("kb-staff-editor-summary-{}", slot.language)
                                    class="tc-input"
                                    type="text"
                                    prop:value=move || slot.summary.get()
                                    on:input=move |ev| slot.summary.set(event_target_value(&ev))
                                />
                            </div>
                            <div class="tc-field">
                                <label class="tc-label" for=format!("kb-editor-body-{}", slot.language)>"Body (simple Markdown)"</label>
                                <textarea
                                    id=format!("kb-editor-body-{}", slot.language)
                                    data-target=format!("kb-staff-editor-body-{}", slot.language)
                                    class="tc-input"
                                    rows="10"
                                    prop:value=move || slot.body.get()
                                    on:input=move |ev| slot.body.set(event_target_value(&ev))
                                ></textarea>
                            </div>
                          </div>
                        </div>
                    })
                    .collect_view()}

                <div class="tc-form-actions tc-form-span-2">
                    <button
                        type="submit"
                        data-target="kb-staff-editor-save"
                        class="tc-btn tc-btn-primary"
                        disabled=move || ui.saving.get()
                    >
                        {move || if ui.saving.get() { "Saving..." } else { "Save" }}
                    </button>
                    <Show when=move || can_admin.get() && !already_published()>
                        <button
                            type="button"
                            data-target="kb-staff-editor-publish"
                            class="tc-btn"
                            disabled=move || ui.saving.get()
                            on:click=move |_| ui.save(true)
                        >
                            "Save and publish"
                        </button>
                    </Show>
                </div>
            </form>
        </aside>
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn draft(language: &str, title: &str, body: &str) -> TextDraft {
        TextDraft {
            language: language.to_string(),
            title: title.to_string(),
            summary: String::new(),
            body: body.to_string(),
        }
    }

    #[test]
    fn parses_tags_without_blanks_or_repeats() {
        assert_eq!(
            parse_tags(" a, b ,, A ,c"),
            vec!["a".to_string(), "b".to_string(), "c".to_string()]
        );
        assert!(parse_tags("  ").is_empty());
    }

    #[test]
    fn builds_input_from_filled_languages_only() {
        let drafts = vec![
            draft("nl", "", ""),
            draft("en", " Reset ", " Steps "),
            draft("fr", "Titre", ""),
        ];
        let input = build_input(None, "", "public", "x, y", &drafts).unwrap();
        assert_eq!(input.visibility, "public");
        assert_eq!(input.texts.len(), 2);
        assert_eq!(input.texts[0].title, "Reset");
        // The Markdown body is kept as typed (leading indentation is significant).
        assert_eq!(input.texts[0].body, " Steps ");
        assert_eq!(input.tags, vec!["x".to_string(), "y".to_string()]);
        assert_eq!(input.category_id, None);
    }

    #[test]
    fn rejects_missing_title_text_or_visibility() {
        let no_title = vec![draft("en", "", "body")];
        assert!(build_input(None, "", "internal", "", &no_title).is_err());
        assert!(build_input(None, "", "internal", "", &[draft("en", "", "")]).is_err());
        let ok = vec![draft("en", "T", "")];
        assert!(build_input(None, "", "everyone", "", &ok).is_err());
        assert!(build_input(None, "not-a-uuid", "internal", "", &ok).is_err());
    }

    #[test]
    fn list_params_drop_blank_filters() {
        let filters = Filters {
            q: "  reset ".into(),
            language: "nl".into(),
            status: "draft".into(),
            ..Filters::default()
        };
        let params = list_params(&filters);
        assert_eq!(params.q.as_deref(), Some("reset"));
        assert_eq!(params.language.as_deref(), Some("nl"));
        assert_eq!(params.status.as_deref(), Some("draft"));
        assert_eq!(params.visibility, None);
        assert_eq!(params.category_id, None);
    }

    #[test]
    fn labels_visibility_for_staff() {
        assert_eq!(visibility_label("internal"), "Staff only");
        assert_eq!(visibility_label("public"), "Public");
        assert_eq!(status_label("draft"), "Draft");
    }
}
