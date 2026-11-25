use leptos::prelude::*;
use leptos::task::spawn_local;
use tradocraft_api_client::portal::{
    KbLanguageParams, ListPublicKbEntriesParams, ReaderCategory, ReaderEntry, ReaderSummary,
};
use tradocraft_api_client::{Client, Session};
use uuid::Uuid;

use crate::api::{resolve_base_url, ConnectionMode};
use crate::pages::parse_uuid;
use crate::state::AppContext;

fn kb_client(base_url: &str) -> Client {
    Client::from_session(Session::anonymous(resolve_base_url(base_url)))
}

fn default_session_params(ctx: &AppContext) -> (String, String) {
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

/// Splits a snippet with `U+E000` / `U+E001` match markers into `(text, highlighted)` segments.
fn snippet_segments(snippet: &str) -> Vec<(String, bool)> {
    let mut segments = Vec::new();
    let mut rest = snippet;
    while let Some(start) = rest.find('\u{E000}') {
        let before = &rest[..start];
        if !before.is_empty() {
            segments.push((before.to_string(), false));
        }
        let after_start = &rest[start + '\u{E000}'.len_utf8()..];
        if let Some(end) = after_start.find('\u{E001}') {
            let highlighted = &after_start[..end];
            if !highlighted.is_empty() {
                segments.push((highlighted.to_string(), true));
            }
            rest = &after_start[end + '\u{E001}'.len_utf8()..];
        } else {
            if !after_start.is_empty() {
                segments.push((after_start.to_string(), false));
            }
            return segments;
        }
    }
    if !rest.is_empty() {
        segments.push((rest.to_string(), false));
    }
    segments
}

#[component]
pub fn KbPage() -> impl IntoView {
    let ctx = expect_context::<AppContext>();
    let (init_base, init_company) = default_session_params(&ctx);

    let base_url = RwSignal::new(init_base);
    let company_id_input = RwSignal::new(init_company);
    let search = RwSignal::new(String::new());
    let selected_category = RwSignal::new(String::new());
    let language = RwSignal::new(String::new());
    let reload_nonce = RwSignal::new(0_u64);

    let categories = RwSignal::new(Vec::<ReaderCategory>::new());
    let entries = RwSignal::new(Vec::<ReaderSummary>::new());
    let loading = RwSignal::new(false);
    let error = RwSignal::new(Option::<String>::None);
    let categories_gen = RwSignal::new(0_u64);
    let entries_gen = RwSignal::new(0_u64);

    let selected_article_id = RwSignal::new(Option::<Uuid>::None);
    let active_article = RwSignal::new(Option::<ReaderEntry>::None);
    let loading_article = RwSignal::new(false);
    let article_error = RwSignal::new(Option::<String>::None);
    let article_gen = RwSignal::new(0_u64);

    // Sync default company_id and base_url when staff session changes.
    Effect::new(move |_| {
        if let Some(active) = ctx.session.get() {
            match active.connection {
                ConnectionMode::Live(s) => {
                    base_url.set(s.base_url);
                    let cid = s.company_id.unwrap_or(active.me.company.id).to_string();
                    if company_id_input.get_untracked().trim().is_empty() {
                        company_id_input.set(cid);
                    }
                }
                ConnectionMode::MockDemo => {
                    if company_id_input.get_untracked().trim().is_empty() {
                        company_id_input.set(active.me.company.id.to_string());
                    }
                }
            }
        }
    });

    // Load categories when company_id or language changes.
    Effect::new(move |_| {
        let _ = reload_nonce.get();
        let raw_company = company_id_input.get();
        let base = base_url.get();
        let lang = language.get();

        let req_gen = categories_gen.get_untracked().wrapping_add(1);
        categories_gen.set(req_gen);

        if raw_company.trim().is_empty() {
            categories.set(Vec::new());
            return;
        }
        let Ok(company_id) = parse_uuid("Company ID", &raw_company) else {
            return;
        };
        let lang_opt = (!lang.trim().is_empty()).then(|| lang.trim().to_string());
        let params = KbLanguageParams { language: lang_opt };
        let client = kb_client(&base);
        spawn_local(async move {
            if let Ok(list) = client.list_public_kb_categories(company_id, &params).await {
                if categories_gen.get_untracked() == req_gen {
                    categories.set(list);
                }
            }
        });
    });

    // Load entries when filters change.
    Effect::new(move |_| {
        let _ = reload_nonce.get();
        let raw_company = company_id_input.get();
        let base = base_url.get();
        let q = search.get();
        let cat = selected_category.get();
        let lang = language.get();

        let req_gen = entries_gen.get_untracked().wrapping_add(1);
        entries_gen.set(req_gen);

        if raw_company.trim().is_empty() {
            entries.set(Vec::new());
            loading.set(false);
            error.set(None);
            return;
        }
        let company_id = match parse_uuid("Company ID", &raw_company) {
            Ok(id) => id,
            Err(msg) => {
                entries.set(Vec::new());
                loading.set(false);
                error.set(Some(msg));
                return;
            }
        };
        let category_id = if cat.trim().is_empty() {
            None
        } else {
            Uuid::parse_str(cat.trim()).ok()
        };

        let params = ListPublicKbEntriesParams {
            q: (!q.trim().is_empty()).then(|| q.trim().to_string()),
            category_id,
            tag: None,
            language: (!lang.trim().is_empty()).then(|| lang.trim().to_string()),
            limit: Some(50),
            offset: Some(0),
        };

        let client = kb_client(&base);
        loading.set(true);
        error.set(None);
        spawn_local(async move {
            let res = client.list_public_kb_entries(company_id, &params).await;
            if entries_gen.get_untracked() != req_gen {
                return;
            }
            match res {
                Ok(list) => {
                    entries.set(list);
                    loading.set(false);
                }
                Err(err) => {
                    loading.set(false);
                    error.set(Some(err.user_message()));
                }
            }
        });
    });

    let open_article = move |entry_id: Uuid| {
        let req_gen = article_gen.get_untracked().wrapping_add(1);
        article_gen.set(req_gen);

        let raw_company = company_id_input.get_untracked();
        let Ok(company_id) = parse_uuid("Company ID", &raw_company) else {
            loading_article.set(false);
            article_error.set(Some("Enter a valid Company ID first.".to_string()));
            return;
        };
        let base = base_url.get_untracked();
        let lang = language.get_untracked();
        let params = KbLanguageParams {
            language: (!lang.trim().is_empty()).then(|| lang.trim().to_string()),
        };

        selected_article_id.set(Some(entry_id));
        active_article.set(None);
        loading_article.set(true);
        article_error.set(None);

        let client = kb_client(&base);
        spawn_local(async move {
            let res = client
                .get_public_kb_entry(company_id, entry_id, &params)
                .await;
            if article_gen.get_untracked() != req_gen {
                return;
            }
            match res {
                Ok(entry) => {
                    active_article.set(Some(entry));
                    loading_article.set(false);
                }
                Err(err) => {
                    loading_article.set(false);
                    article_error.set(Some(err.user_message()));
                }
            }
        });
    };

    view! {
        <div data-target="kb-page">
            <div class="tc-page-header">
                <div>
                    <h1 class="tc-page-title">"Knowledge Base"</h1>
                    <p class="tc-page-subtitle" data-target="kb-total">
                        {move || {
                            format!(
                                "Public articles ({} shown across {} categories)",
                                entries.with(Vec::len),
                                categories.with(Vec::len)
                            )
                        }}
                    </p>
                </div>
                <div class="tc-header-actions">
                    <button
                        type="button"
                        data-target="kb-refresh"
                        class="tc-btn"
                        disabled=move || loading.get()
                        on:click=move |_| reload_nonce.update(|n| *n += 1)
                    >
                        {move || if loading.get() { "Loading..." } else { "Refresh" }}
                    </button>
                </div>
            </div>

            <div class="tc-toolbar">
                <input
                    data-target="kb-search"
                    class="tc-input"
                    style="min-width: 240px;"
                    type="search"
                    placeholder="Search knowledge base..."
                    prop:value=move || search.get()
                    on:input=move |ev| search.set(event_target_value(&ev))
                />
                <select
                    data-target="kb-category-filter"
                    class="tc-select"
                    prop:value=move || selected_category.get()
                    on:change=move |ev| selected_category.set(event_target_value(&ev))
                >
                    <option value="">"All categories"</option>
                    <For
                        each=move || categories.get()
                        key=|c| (c.id, c.entry_count, c.name.clone())
                        children=move |cat| {
                            let val = cat.id.to_string();
                            let label = format!("{} ({})", cat.name, cat.entry_count);
                            view! { <option value=val>{label}</option> }
                        }
                    />
                </select>
                <select
                    data-target="kb-language-filter"
                    class="tc-select"
                    prop:value=move || language.get()
                    on:change=move |ev| language.set(event_target_value(&ev))
                >
                    <option value="">"Company default language"</option>
                    <option value="en">"English (en)"</option>
                    <option value="nl">"Nederlands (nl)"</option>
                    <option value="fr">"Français (fr)"</option>
                    <option value="de">"Deutsch (de)"</option>
                    <option value="es">"Español (es)"</option>
                </select>
                <input
                    data-target="kb-company-id"
                    class="tc-input tc-mono"
                    style="min-width: 290px;"
                    type="text"
                    placeholder="Company UUID (auto-filled when signed in)"
                    prop:value=move || company_id_input.get()
                    on:input=move |ev| company_id_input.set(event_target_value(&ev))
                />
            </div>

            {move || error.get().map(|msg| view! {
                <div class="tc-alert-error" style="margin-bottom: var(--space-md);" role="alert" data-target="kb-error">
                    {msg}
                </div>
            })}

            <div class=move || {
                if selected_article_id.get().is_some() {
                    "tc-workspace-split"
                } else {
                    ""
                }
            }>
                <div class="tc-table-wrap" data-target="kb-article-list">
                    <table class="tc-table">
                        <thead>
                            <tr>
                                <th>"Number"</th>
                                <th>"Article"</th>
                                <th>"Lang"</th>
                                <th>"Tags"</th>
                                <th>"Updated"</th>
                            </tr>
                        </thead>
                        <tbody>
                            <Show
                                when=move || !entries.with(Vec::is_empty)
                                fallback=move || view! {
                                    <tr>
                                        <td colspan="5" style="text-align: center; color: var(--on-surface-variant); padding: var(--space-xl);">
                                            {move || {
                                                if company_id_input.with(|s| s.trim().is_empty()) {
                                                    "Enter a Company UUID (or sign in) to browse public KB articles."
                                                } else if loading.get() {
                                                    "Loading articles..."
                                                } else {
                                                    "No public articles match your search."
                                                }
                                            }}
                                        </td>
                                    </tr>
                                }
                            >
                                <For
                                    each=move || entries.get()
                                    key=|item| (item.id, item.title.clone(), item.snippet.clone())
                                    children=move |item| {
                                        let entry_id = item.id;
                                        let row_target = format!("kb-article-row-{}", item.number);
                                        let segs = snippet_segments(&item.snippet);
                                        let tags_text = if item.tags.is_empty() {
                                            "—".to_string()
                                        } else {
                                            item.tags.join(", ")
                                        };
                                        let updated = item.updated_at.date_naive().to_string();
                                        view! {
                                            <tr
                                                class=move || {
                                                    if selected_article_id.get() == Some(entry_id) {
                                                        "tc-row-clickable tc-row-selected"
                                                    } else {
                                                        "tc-row-clickable"
                                                    }
                                                }
                                                data-target=row_target
                                                on:click=move |_| open_article(entry_id)
                                            >
                                                <td class="tc-mono">{item.number}</td>
                                                <td>
                                                    <button
                                                        type="button"
                                                        style="background: none; border: none; padding: 0; font: inherit; font-weight: 600; color: inherit; cursor: pointer; text-align: left;"
                                                        on:click=move |ev| {
                                                            ev.stop_propagation();
                                                            open_article(entry_id);
                                                        }
                                                    >
                                                        {item.title}
                                                    </button>
                                                    {(!segs.is_empty()).then(|| view! {
                                                        <div style="font-size: 12px; color: var(--on-surface-variant); margin-top: 2px;">
                                                            {segs.into_iter().map(|(text, hit)| {
                                                                if hit {
                                                                    view! {
                                                                        <mark style="background: var(--primary-container); color: var(--on-primary-container); padding: 0 2px; border-radius: 2px;">
                                                                            {text}
                                                                        </mark>
                                                                    }.into_any()
                                                                } else {
                                                                    view! { <span>{text}</span> }.into_any()
                                                                }
                                                            }).collect_view()}
                                                        </div>
                                                    })}
                                                </td>
                                                <td>
                                                    <span class=if item.fallback { "tc-badge tc-badge-warning" } else { "tc-badge" }>
                                                        {item.language}
                                                    </span>
                                                </td>
                                                <td>{tags_text}</td>
                                                <td class="tc-mono">{updated}</td>
                                            </tr>
                                        }
                                    }
                                />
                            </Show>
                        </tbody>
                    </table>
                </div>

                {move || selected_article_id.get().map(|_| {
                    view! {
                        <aside class="tc-card tc-detail-drawer" data-target="kb-article-view">
                            <div class="tc-page-header" style="margin-bottom: 0;">
                                <div>
                                    <h2 class="tc-page-title" style="font-size: 17px;">
                                        {move || {
                                            active_article
                                                .with(|a| a.as_ref().map(|e| e.title.clone()))
                                                .unwrap_or_else(|| "Article".to_string())
                                        }}
                                    </h2>
                                    <p class="tc-page-subtitle tc-mono">
                                        {move || {
                                            if loading_article.get() {
                                                "Loading article...".to_string()
                                            } else {
                                                active_article
                                                    .with(|a| a.as_ref().map(|e| {
                                                        format!("{} · {} · {}", e.number, e.language, e.updated_at.date_naive())
                                                    }))
                                                    .unwrap_or_default()
                                            }
                                        }}
                                    </p>
                                </div>
                                <button
                                    type="button"
                                    class="tc-btn tc-btn-sm tc-btn-ghost"
                                    data-target="kb-article-close"
                                    on:click=move |_| {
                                        article_gen.update(|g| *g = g.wrapping_add(1));
                                        selected_article_id.set(None);
                                        active_article.set(None);
                                        loading_article.set(false);
                                        article_error.set(None);
                                    }
                                >
                                    "Close"
                                </button>
                            </div>

                            {move || article_error.get().map(|msg| view! {
                                <div class="tc-alert-error" role="alert" data-target="kb-article-error">
                                    {msg}
                                </div>
                            })}

                            {move || active_article.get().map(|entry| {
                                view! {
                                    <div style="display: flex; flex-direction: column; gap: var(--space-md);">
                                        <div class="tc-chip-row">
                                            {entry.fallback.then(|| view! {
                                                <span class="tc-badge tc-badge-warning">"Fallback language"</span>
                                            })}
                                            {entry.available_languages.into_iter().map(|lang_code| {
                                                let click_lang = lang_code.clone();
                                                view! {
                                                    <button
                                                        type="button"
                                                        class="tc-chip"
                                                        on:click=move |_| {
                                                            language.set(click_lang.clone());
                                                            open_article(entry.id);
                                                        }
                                                    >
                                                        {lang_code}
                                                    </button>
                                                }
                                            }).collect_view()}
                                            {entry.tags.into_iter().map(|tag| view! {
                                                <span class="tc-badge tc-badge-primary">{tag}</span>
                                            }).collect_view()}
                                        </div>

                                        {(!entry.summary.trim().is_empty()).then(|| view! {
                                            <p style="margin: 0; color: var(--on-surface-variant); font-size: 13px;">
                                                {entry.summary}
                                            </p>
                                        })}

                                        <div
                                            data-target="kb-article-body"
                                            style="white-space: pre-wrap; line-height: 1.55; font-size: 13px; padding: var(--space-md); background: var(--surface); border: 1px solid var(--outline-variant); border-radius: var(--radius-sm);"
                                        >
                                            {entry.body}
                                        </div>

                                        {(!entry.images.is_empty()).then(|| view! {
                                            <div class="tc-field">
                                                <span class="tc-label">"Attachments / Images"</span>
                                                <div class="tc-chip-row">
                                                    {entry.images.into_iter().map(|img| view! {
                                                        <span class="tc-badge tc-mono">{img.filename}</span>
                                                    }).collect_view()}
                                                </div>
                                            </div>
                                        })}

                                        {(!entry.related.is_empty()).then(|| view! {
                                            <div class="tc-field">
                                                <span class="tc-label">"Related articles"</span>
                                                <div style="display: flex; flex-direction: column; gap: var(--space-xs);">
                                                    {entry.related.into_iter().map(|rel| {
                                                        let rel_id = rel.id;
                                                        view! {
                                                            <button
                                                                type="button"
                                                                class="tc-btn tc-btn-sm"
                                                                style="justify-content: flex-start;"
                                                                on:click=move |_| open_article(rel_id)
                                                            >
                                                                <span class="tc-mono">{rel.number}</span>
                                                                <span>{rel.title}</span>
                                                            </button>
                                                        }
                                                    }).collect_view()}
                                                </div>
                                            </div>
                                        })}
                                    </div>
                                }
                            })}
                        </aside>
                    }
                })}
            </div>
        </div>
    }
}
