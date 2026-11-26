//! Standard Answers (prepared answers) management page: reusable reply templates with a subject
//! and body per language. Mirrors `app/lib/features/helpdesk/answers_page.dart`. Everybody with
//! Helpdesk access can read the list; creating and editing needs `answers.write`.

use leptos::ev::SubmitEvent;
use leptos::prelude::*;
use leptos::task::spawn_local;
use leptos_router::components::A;
use tradocraft_api_client::helpdesk::{
    AnswerText, ListPreparedAnswersParams, PreparedAnswer, PreparedAnswerInput,
};
use tradocraft_api_client::{ApiError, Client};
use uuid::Uuid;

use crate::api::{resolve_base_url, ConnectionMode};
use crate::pages::{opt_trimmed, set_alive};
use crate::state::AppContext;

const WRITE_PERMISSION: &str = "answers.write";

/// Languages an answer can be written in, in the order the editor shows them.
const LANGUAGES: [(&str, &str); 5] = [
    ("nl", "Nederlands"),
    ("fr", "Francais"),
    ("en", "English"),
    ("de", "Deutsch"),
    ("es", "Espanol"),
];

const KINDS: [(&str, &str); 4] = [
    ("reply", "Reply"),
    ("internal_note", "Internal note"),
    ("handover", "Hand-over"),
    ("notice", "Notice"),
];

fn kind_label(kind: &str) -> &str {
    KINDS
        .iter()
        .find(|(k, _)| *k == kind)
        .map(|(_, l)| *l)
        .unwrap_or(kind)
}

/// Splits a comma separated keyword field into lower-case words.
fn parse_keywords(raw: &str) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    for word in raw.split(',') {
        let word = word.trim().to_lowercase();
        if !word.is_empty() && !out.contains(&word) {
            out.push(word);
        }
    }
    out
}

/// The text of one language as typed in the editor.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
struct LangDraft {
    subject: String,
    body: String,
}

/// Everything the editor form holds.
#[derive(Debug, Clone, PartialEq, Eq)]
struct Draft {
    code: String,
    name: String,
    category: String,
    kind: String,
    team_id: Option<Uuid>,
    keywords: String,
    /// The keywords the answer was loaded with. Kept as they are while the field is untouched, so a
    /// keyword that contains a comma is not split by saving another field.
    keywords_orig: Option<Vec<String>>,
    active: bool,
    texts: [LangDraft; 5],
}

impl Default for Draft {
    fn default() -> Self {
        Self {
            code: String::new(),
            name: String::new(),
            category: String::new(),
            kind: "reply".to_string(),
            team_id: None,
            keywords: String::new(),
            keywords_orig: None,
            active: true,
            texts: Default::default(),
        }
    }
}

impl Draft {
    fn from_answer(a: &PreparedAnswer) -> Self {
        let mut texts: [LangDraft; 5] = Default::default();
        for (i, (code, _)) in LANGUAGES.iter().enumerate() {
            if let Some(t) = a.texts.iter().find(|t| t.language == *code) {
                texts[i] = LangDraft {
                    subject: t.subject.clone(),
                    body: t.body.clone(),
                };
            }
        }
        Self {
            code: a.code.clone(),
            name: a.name.clone(),
            category: a.category.clone().unwrap_or_default(),
            kind: a.kind.clone(),
            team_id: a.team_id,
            keywords: a.keywords.join(", "),
            keywords_orig: Some(a.keywords.clone()),
            active: a.active,
            texts,
        }
    }

    /// Validates like the server does and builds the request. Languages without a body are
    /// left out.
    fn to_input(&self) -> Result<PreparedAnswerInput, String> {
        let Some(code) = opt_trimmed(&self.code) else {
            return Err("Code is required.".to_string());
        };
        let Some(name) = opt_trimmed(&self.name) else {
            return Err("Name is required.".to_string());
        };
        let mut texts = Vec::new();
        for (i, (lang, label)) in LANGUAGES.iter().enumerate() {
            let t = &self.texts[i];
            if t.body.trim().is_empty() {
                continue;
            }
            if t.subject.trim().is_empty() {
                return Err(format!("A subject is required for {label}."));
            }
            texts.push(AnswerText {
                language: (*lang).to_string(),
                subject: t.subject.trim().to_string(),
                body: t.body.clone(),
            });
        }
        if texts.is_empty() {
            return Err("Write the answer in at least one language.".to_string());
        }
        Ok(PreparedAnswerInput {
            code,
            name,
            category: opt_trimmed(&self.category),
            kind: self.kind.clone(),
            team_id: self.team_id,
            keywords: match &self.keywords_orig {
                Some(orig) if orig.join(", ") == self.keywords => orig.clone(),
                _ => parse_keywords(&self.keywords),
            },
            active: self.active,
            texts,
        })
    }
}

/// Appends `{{placeholder}}` to a body, on a space boundary.
fn append_placeholder(body: &str, placeholder: &str) -> String {
    let token = format!("{{{{{placeholder}}}}}");
    if body.is_empty() || body.ends_with(char::is_whitespace) {
        format!("{body}{token}")
    } else {
        format!("{body} {token}")
    }
}

/// Case-insensitive match on code, name, category and keywords.
fn matches_query(a: &PreparedAnswer, q: &str) -> bool {
    let q = q.trim().to_lowercase();
    if q.is_empty() {
        return true;
    }
    a.code.to_lowercase().contains(&q)
        || a.name.to_lowercase().contains(&q)
        || a.category
            .as_deref()
            .is_some_and(|c| c.to_lowercase().contains(&q))
        || a.keywords.iter().any(|k| k.contains(&q))
}

fn live_client(connection: &ConnectionMode) -> Result<Client, ApiError> {
    match connection {
        ConnectionMode::Live(session) => {
            let mut resolved = session.clone();
            resolved.base_url = resolve_base_url(&session.base_url);
            Ok(Client::from_session(resolved))
        }
        ConnectionMode::MockDemo => Err(ApiError::InvalidConfig(
            "Standard answers require a live API connection; switch to Dev User or Bearer mode on the sign-in screen."
                .to_string(),
        )),
    }
}

/// Which answer the editor is open for.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum EditorTarget {
    New,
    Edit(Uuid),
}

#[component]
pub fn AnswersPage() -> impl IntoView {
    let ctx = expect_context::<AppContext>();

    let answers = RwSignal::new(Vec::<PreparedAnswer>::new());
    let placeholders = RwSignal::new(Vec::<String>::new());
    let loading = RwSignal::new(false);
    let error = RwSignal::new(Option::<String>::None);
    let reload = RwSignal::new(0_u64);
    let fetch_generation = StoredValue::new(0_u64);
    let search = RwSignal::new(String::new());

    let editor = RwSignal::new(Option::<EditorTarget>::None);
    let saving = RwSignal::new(false);
    let editor_error = RwSignal::new(Option::<String>::None);
    let f_code = RwSignal::new(String::new());
    let f_name = RwSignal::new(String::new());
    let f_category = RwSignal::new(String::new());
    let f_kind = RwSignal::new("reply".to_string());
    let f_team = RwSignal::new(Option::<Uuid>::None);
    let f_keywords = RwSignal::new(String::new());
    let f_keywords_orig = RwSignal::new(Option::<Vec<String>>::None);
    // Counts editor openings, so a slow save cannot close or fill a newer editor.
    let editor_gen = RwSignal::new(0_u64);
    let f_active = RwSignal::new(true);
    let f_subject: [RwSignal<String>; 5] = std::array::from_fn(|_| RwSignal::new(String::new()));
    let f_body: [RwSignal<String>; 5] = std::array::from_fn(|_| RwSignal::new(String::new()));
    let lang_tab = RwSignal::new(0_usize);

    let is_signed_in = Memo::new(move |_| ctx.session.with(|s| s.is_some()));
    let can_write = Memo::new(move |_| {
        ctx.session.with(|s| {
            s.as_ref()
                .is_some_and(|s| s.me.has_permission(WRITE_PERMISSION))
        })
    });

    Effect::new(move |_| {
        let _ = reload.get();
        let session = ctx.session.get();
        let req_gen = fetch_generation
            .try_update_value(|g| {
                *g += 1;
                *g
            })
            .unwrap_or(0);
        let Some(session) = session else {
            loading.set(false);
            answers.set(Vec::new());
            return;
        };
        loading.set(true);
        let client = live_client(&session.connection);
        // The placeholder list is a convenience: it loads on its own so a slow or failing request
        // never delays or hides the answers.
        if let Ok(client) = client.as_ref().map(Clone::clone) {
            spawn_local(async move {
                let ph = client.list_prepared_answer_placeholders().await;
                if fetch_generation.try_get_value() == Some(req_gen) {
                    if let Ok(ph) = ph {
                        placeholders.set(ph);
                    }
                }
            });
        }
        spawn_local(async move {
            let res = match client {
                Ok(client) => {
                    client
                        .list_prepared_answers(&ListPreparedAnswersParams::new())
                        .await
                }
                Err(err) => Err(err),
            };
            if fetch_generation.try_get_value() != Some(req_gen) {
                return;
            }
            loading.set(false);
            match res {
                Ok(list) => {
                    error.set(None);
                    answers.set(list);
                }
                Err(err) => error.set(Some(err.user_message())),
            }
        });
    });

    let load_draft = move |draft: &Draft| {
        f_code.set(draft.code.clone());
        f_name.set(draft.name.clone());
        f_category.set(draft.category.clone());
        f_kind.set(draft.kind.clone());
        f_team.set(draft.team_id);
        f_keywords.set(draft.keywords.clone());
        f_keywords_orig.set(draft.keywords_orig.clone());
        editor_gen.update(|g| *g = g.wrapping_add(1));
        f_active.set(draft.active);
        for i in 0..5 {
            f_subject[i].set(draft.texts[i].subject.clone());
            f_body[i].set(draft.texts[i].body.clone());
        }
        lang_tab.set(0);
        editor_error.set(None);
    };

    let open_new = move |_| {
        load_draft(&Draft::default());
        editor.set(Some(EditorTarget::New));
    };
    let open_edit = move |a: PreparedAnswer| {
        load_draft(&Draft::from_answer(&a));
        editor.set(Some(EditorTarget::Edit(a.id)));
    };

    let on_save = move |ev: SubmitEvent| {
        ev.prevent_default();
        let Some(target) = editor.get_untracked() else {
            return;
        };
        if !can_write.get_untracked() {
            return;
        }
        let draft = Draft {
            code: f_code.get_untracked(),
            name: f_name.get_untracked(),
            category: f_category.get_untracked(),
            kind: f_kind.get_untracked(),
            team_id: f_team.get_untracked(),
            keywords: f_keywords.get_untracked(),
            keywords_orig: f_keywords_orig.get_untracked(),
            active: f_active.get_untracked(),
            texts: std::array::from_fn(|i| LangDraft {
                subject: f_subject[i].get_untracked(),
                body: f_body[i].get_untracked(),
            }),
        };
        let input = match draft.to_input() {
            Ok(i) => i,
            Err(msg) => {
                editor_error.set(Some(msg));
                return;
            }
        };
        let Some(session) = ctx.session.get_untracked() else {
            return;
        };
        saving.set(true);
        let save_gen = editor_gen.get_untracked();
        spawn_local(async move {
            let res = match live_client(&session.connection) {
                Ok(client) => match target {
                    EditorTarget::New => client.create_prepared_answer(&input).await,
                    EditorTarget::Edit(id) => client.update_prepared_answer(id, &input).await,
                },
                Err(err) => Err(err),
            };
            if !set_alive(saving, false) {
                return;
            }
            // The write is committed whichever editor is open now, so always refresh the list; only
            // the editor that submitted it is closed or shown the error.
            let still_open = editor_gen.try_get_untracked() == Some(save_gen);
            match res {
                Ok(_) => {
                    if still_open {
                        editor.set(None);
                        editor_error.set(None);
                    }
                    reload.update(|n| *n += 1);
                }
                Err(err) => {
                    if still_open {
                        editor_error.set(Some(err.user_message()));
                    }
                }
            }
        });
    };

    let visible = Memo::new(move |_| {
        let q = search.get();
        answers.with(|list| {
            list.iter()
                .filter(|a| matches_query(a, &q))
                .cloned()
                .collect::<Vec<_>>()
        })
    });

    view! {
        <div data-target="answers-page">
            <div class="tc-page-header">
                <div>
                    <h1 class="tc-page-title">"Standard answers"</h1>
                    <p class="tc-page-subtitle" data-target="answers-total">
                        {move || format!("{} answers", visible.with(Vec::len))}
                    </p>
                </div>
                <div class="tc-header-actions">
                    <A href=crate::components::shell::app_href("/helpdesk") attr:class="tc-btn" attr:data-target="answers-back">
                        "Back to Helpdesk"
                    </A>
                    <button
                        type="button"
                        data-target="answers-refresh"
                        class="tc-btn"
                        disabled=move || loading.get() || !is_signed_in.get()
                        on:click=move |_| reload.update(|n| *n += 1)
                    >
                        {move || if loading.get() { "Loading..." } else { "Refresh" }}
                    </button>
                    <Show when=move || can_write.get()>
                        <button
                            type="button"
                            data-target="answers-new"
                            class="tc-btn tc-btn-primary"
                            on:click=open_new
                        >
                            "New answer"
                        </button>
                    </Show>
                </div>
            </div>

            <p style="color: var(--on-surface-variant);" data-target="answers-help">
                "Reusable answers to recurring questions, one text per language. Placeholders such as {{quotation.number}} are filled in for the ticket; the text can still be edited before sending."
            </p>

            <Show
                when=move || is_signed_in.get()
                fallback=|| view! {
                    <div class="tc-card">
                        <p style="margin: 0 0 var(--space-md);">
                            "Sign in to load the standard answers from GET /api/v1/prepared-answers."
                        </p>
                        <A href=crate::components::shell::app_href("/login") attr:class="tc-btn tc-btn-primary" attr:data-target="answers-go-login">
                            "Go to sign in"
                        </A>
                    </div>
                }
            >
                <div class="tc-toolbar">
                    <input
                        data-target="answers-search"
                        class="tc-input"
                        style="min-width: 280px;"
                        type="search"
                        placeholder="Search code, name, category or keyword..."
                        prop:value=move || search.get()
                        on:input=move |ev| search.set(event_target_value(&ev))
                    />
                </div>

                {move || error.get().map(|msg| view! {
                    <div class="tc-alert-error" style="margin-bottom: var(--space-md);" role="alert" data-target="answers-error">
                        {msg}
                    </div>
                })}

                <Show when=move || editor.get().is_some() && can_write.get()>
                    <form class="tc-card" data-target="answers-editor" on:submit=on_save style="margin-bottom: var(--space-md);">
                        <h2 style="margin-top: 0;" data-target="answers-editor-title">
                            {move || if editor.get() == Some(EditorTarget::New) { "New answer" } else { "Edit answer" }}
                        </h2>
                        <div class="tc-toolbar">
                            <input data-target="answers-code" class="tc-input" type="text" placeholder="Code" aria-label="Code"
                                prop:value=move || f_code.get()
                                on:input=move |ev| f_code.set(event_target_value(&ev)) />
                            <input data-target="answers-name" class="tc-input" style="min-width: 240px;" type="text" placeholder="Name" aria-label="Name"
                                prop:value=move || f_name.get()
                                on:input=move |ev| f_name.set(event_target_value(&ev)) />
                            <input data-target="answers-category" class="tc-input" type="text" placeholder="Category" aria-label="Category"
                                prop:value=move || f_category.get()
                                on:input=move |ev| f_category.set(event_target_value(&ev)) />
                            <select data-target="answers-kind" class="tc-select" aria-label="Kind"
                                prop:value=move || f_kind.get()
                                on:change=move |ev| f_kind.set(event_target_value(&ev))>
                                {KINDS.iter().map(|(k, l)| view! {
                                    <option value=*k selected=move || f_kind.get() == *k>{*l}</option>
                                }).collect_view()}
                            </select>
                            <label style="display: inline-flex; align-items: center; gap: var(--space-xs);">
                                <input data-target="answers-active" type="checkbox"
                                    prop:checked=move || f_active.get()
                                    on:change=move |ev| f_active.set(event_target_checked(&ev)) />
                                "Active"
                            </label>
                        </div>
                        <div class="tc-toolbar">
                            <input data-target="answers-keywords" class="tc-input" style="min-width: 360px;" type="text"
                                placeholder="Keywords, comma separated" aria-label="Keywords"
                                prop:value=move || f_keywords.get()
                                on:input=move |ev| f_keywords.set(event_target_value(&ev)) />
                            <span class="tc-label">"A ticket subject containing a keyword ranks this answer higher."</span>
                        </div>

                        <div class="tc-inline-tabs" data-target="answers-lang-tabs" role="group" aria-label="Language">
                            {LANGUAGES.iter().enumerate().map(|(i, (code, label))| view! {
                                <button
                                    type="button"
                                    data-target=format!("answers-lang-{code}")
                                    class=move || if lang_tab.get() == i {
                                        "tc-inline-tab-btn tc-inline-tab-active"
                                    } else {
                                        "tc-inline-tab-btn"
                                    }
                                    aria-pressed=move || (lang_tab.get() == i).to_string()
                                    on:click=move |_| lang_tab.set(i)
                                >
                                    {*label}
                                    {move || (!f_body[i].with(|b| b.trim().is_empty())).then_some(" *")}
                                </button>
                            }).collect_view()}
                        </div>
                        {LANGUAGES.iter().enumerate().map(|(i, (code, label))| view! {
                            <div style=move || if lang_tab.get() == i { "" } else { "display: none;" }
                                data-target=format!("answers-text-{code}")>
                                <div class="tc-toolbar">
                                    <input data-target=format!("answers-subject-{code}") class="tc-input" style="flex: 1; min-width: 320px;"
                                        type="text" placeholder="Subject" aria-label=format!("Subject ({label})")
                                        prop:value=move || f_subject[i].get()
                                        on:input=move |ev| f_subject[i].set(event_target_value(&ev)) />
                                </div>
                                <textarea data-target=format!("answers-body-{code}") class="tc-input"
                                    style="width: 100%; min-height: 180px;" placeholder="Text"
                                    aria-label=format!("Text ({label})")
                                    prop:value=move || f_body[i].get()
                                    on:input=move |ev| f_body[i].set(event_target_value(&ev))></textarea>
                            </div>
                        }).collect_view()}

                        <p class="tc-label" data-target="answers-placeholders-help">
                            "Placeholders are filled in when the answer is used on a ticket. Click one to add it to the open text."
                        </p>
                        <div class="tc-chip-row" data-target="answers-placeholders">
                            <For
                                each=move || placeholders.get()
                                key=|p| p.clone()
                                children=move |p| {
                                    let token = p.clone();
                                    view! {
                                        <button type="button" class="tc-chip"
                                            data-target=format!("answers-placeholder-{p}")
                                            on:click=move |_| {
                                                let i = lang_tab.get_untracked();
                                                f_body[i].update(|b| *b = append_placeholder(b, &token));
                                            }>
                                            {format!("{{{{{p}}}}}")}
                                        </button>
                                    }
                                }
                            />
                        </div>

                        {move || editor_error.get().map(|msg| view! {
                            <div class="tc-alert-error" style="margin-top: var(--space-md);" role="alert" data-target="answers-editor-error">
                                {msg}
                            </div>
                        })}
                        <div class="tc-toolbar" style="margin-top: var(--space-md);">
                            <button type="submit" data-target="answers-save" class="tc-btn tc-btn-primary" disabled=move || saving.get()>
                                {move || if saving.get() { "Saving..." } else { "Save" }}
                            </button>
                            <button type="button" data-target="answers-cancel" class="tc-btn"
                                on:click=move |_| editor.set(None)>
                                "Cancel"
                            </button>
                        </div>
                    </form>
                </Show>

                <Show
                    when=move || !visible.with(Vec::is_empty)
                    fallback=move || view! {
                        <p data-target="answers-empty" style="color: var(--on-surface-variant); padding: var(--space-xl) 0;">
                            {move || if loading.get() { "Loading standard answers..." } else { "No standard answers." }}
                        </p>
                    }
                >
                    <ul data-target="answers-list" style="list-style: none; margin: 0; padding: 0;">
                        <For
                            each=move || visible.get()
                            key=|a| format!("{}:{}", a.id, a.updated_at)
                            children=move |a| {
                                let id = a.id;
                                let subtitle = answer_subtitle(&a);
                                let langs = a.texts.iter().map(|t| t.language.clone()).collect::<Vec<_>>();
                                let name = a.name.clone();
                                let edit_answer = a.clone();
                                view! {
                                    <li class="tc-card" style="margin-bottom: var(--space-sm);" data-target=format!("answers-item-{id}")>
                                        <div style="display: flex; align-items: center; gap: var(--space-sm); flex-wrap: wrap;">
                                            <div style="flex: 1; min-width: 200px;">
                                                <strong data-target=format!("answers-name-{id}")>{name}</strong>
                                                <div class="tc-label" data-target=format!("answers-meta-{id}")>{subtitle}</div>
                                            </div>
                                            {LANGUAGES.iter().map(|(code, _)| {
                                                let has = langs.iter().any(|l| l == code);
                                                view! {
                                                    <span
                                                        data-target=format!("answers-lang-badge-{id}-{code}")
                                                        class=if has { "tc-badge tc-badge-primary" } else { "tc-badge" }
                                                    >
                                                        {code.to_uppercase()}
                                                    </span>
                                                }
                                            }).collect_view()}
                                            <Show when=move || can_write.get()>
                                                <button
                                                    type="button"
                                                    data-target=format!("answers-edit-{id}")
                                                    class="tc-btn tc-btn-sm"
                                                    on:click={
                                                        let edit_answer = edit_answer.clone();
                                                        move |_| open_edit(edit_answer.clone())
                                                    }
                                                >
                                                    "Edit"
                                                </button>
                                            </Show>
                                        </div>
                                    </li>
                                }
                            }
                        />
                    </ul>
                </Show>
            </Show>
        </div>
    }
}

/// `code · kind · category · inactive`, as the Flutter list shows it (a plain reply has no kind).
fn answer_subtitle(a: &PreparedAnswer) -> String {
    let mut parts = vec![a.code.clone()];
    if a.kind != "reply" {
        parts.push(kind_label(&a.kind).to_string());
    }
    if let Some(c) = a.category.as_deref().filter(|c| !c.is_empty()) {
        parts.push(c.to_string());
    }
    if !a.active {
        parts.push("inactive".to_string());
    }
    parts.join(" \u{b7} ")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn answer(texts: Vec<AnswerText>) -> PreparedAnswer {
        PreparedAnswer {
            id: Uuid::nil(),
            code: "pump-bleed".into(),
            name: "Pump bleeding".into(),
            category: Some("Service".into()),
            kind: "handover".into(),
            team_id: None,
            keywords: vec!["pump".into()],
            active: false,
            updated_at: chrono::DateTime::UNIX_EPOCH,
            texts,
        }
    }

    fn text(lang: &str, subject: &str, body: &str) -> AnswerText {
        AnswerText {
            language: lang.into(),
            subject: subject.into(),
            body: body.into(),
        }
    }

    #[test]
    fn keywords_are_lowercased_trimmed_and_deduplicated() {
        assert_eq!(
            parse_keywords(" Pump, air ,, PUMP,noise "),
            vec!["pump", "air", "noise"]
        );
        assert!(parse_keywords("  ").is_empty());
    }

    #[test]
    fn draft_requires_code_name_and_one_text() {
        let mut d = Draft::default();
        assert_eq!(d.to_input().unwrap_err(), "Code is required.");
        d.code = "c".into();
        assert_eq!(d.to_input().unwrap_err(), "Name is required.");
        d.name = "n".into();
        assert!(d.to_input().unwrap_err().contains("at least one language"));
    }

    #[test]
    fn draft_requires_subject_for_filled_language_only() {
        let mut d = Draft {
            code: "c".into(),
            name: "n".into(),
            ..Draft::default()
        };
        d.texts[2].body = "Hello".into();
        assert_eq!(
            d.to_input().unwrap_err(),
            "A subject is required for English."
        );
        d.texts[2].subject = " Re: hi ".into();
        let input = d.to_input().unwrap();
        assert_eq!(input.texts.len(), 1);
        assert_eq!(input.texts[0].language, "en");
        assert_eq!(input.texts[0].subject, "Re: hi");
        assert_eq!(input.kind, "reply");
        assert!(input.active);
        assert!(input.category.is_none());
    }

    #[test]
    fn draft_round_trips_an_existing_answer() {
        let a = answer(vec![
            text("nl", "Onderwerp", "Tekst"),
            text("de", "Betreff", "Text"),
        ]);
        let d = Draft::from_answer(&a);
        assert_eq!(d.texts[0].subject, "Onderwerp");
        assert_eq!(d.texts[3].body, "Text");
        assert!(d.texts[1].body.is_empty());
        let input = d.to_input().unwrap();
        assert_eq!(input.texts.len(), 2);
        assert_eq!(input.texts[0].language, "nl");
        assert_eq!(input.texts[1].language, "de");
        assert_eq!(input.keywords, vec!["pump"]);
        assert!(!input.active);
        assert_eq!(input.category.as_deref(), Some("Service"));
    }

    #[test]
    fn untouched_keywords_keep_their_boundaries() {
        let mut a = answer(vec![text("en", "S", "B")]);
        a.keywords = vec!["pump, noisy".into(), "air".into()];
        let mut d = Draft::from_answer(&a);
        assert_eq!(d.to_input().unwrap().keywords, a.keywords);
        d.keywords = "pump, noisy, air, new".into();
        assert_eq!(d.to_input().unwrap().keywords.len(), 4);
    }

    #[test]
    fn placeholder_is_appended_on_a_word_boundary() {
        assert_eq!(append_placeholder("", "ticket.number"), "{{ticket.number}}");
        assert_eq!(
            append_placeholder("Dear", "contact.name"),
            "Dear {{contact.name}}"
        );
        assert_eq!(
            append_placeholder("Dear ", "contact.name"),
            "Dear {{contact.name}}"
        );
    }

    #[test]
    fn query_matches_code_name_category_and_keywords() {
        let a = answer(vec![]);
        assert!(matches_query(&a, ""));
        assert!(matches_query(&a, "BLEED"));
        assert!(matches_query(&a, "service"));
        assert!(matches_query(&a, "pump"));
        assert!(!matches_query(&a, "invoice"));
    }

    #[test]
    fn subtitle_lists_code_kind_category_and_inactive() {
        let a = answer(vec![]);
        assert_eq!(
            answer_subtitle(&a),
            "pump-bleed \u{b7} Hand-over \u{b7} Service \u{b7} inactive"
        );
        let mut b = answer(vec![]);
        b.kind = "reply".into();
        b.category = None;
        b.active = true;
        assert_eq!(answer_subtitle(&b), "pump-bleed");
    }
}
