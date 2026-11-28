//! Interface texts of the web UI at runtime (ADR 0101). The English texts stay in the code;
//! [`tr`] looks a key up in the catalogue of the chosen interface language (the `web` domain
//! of `core.translations`, uploaded by an administrator) and falls back to the English text.
//! [`source_catalogue`] lists every key with its English text: the template a translator gets.

use std::collections::{BTreeMap, HashMap};

use leptos::prelude::*;

use crate::components::shell::nav_source_texts;
use crate::pages::admin::spawn_api;
use crate::pages::set_alive;
use crate::state::AppContext;

/// Texts used through [`tr`] outside the navigation: `(key, English)`.
pub const SOURCE: &[(&str, &str)] = &[
    ("shell.tutorial", "Tutorial"),
    ("shell.light_mode", "Light mode"),
    ("shell.dark_mode", "Dark mode"),
    ("shell.sign_out", "Sign out"),
    ("shell.interface_language", "Interface language"),
    (
        "banner.worker_never_seen",
        "No background worker heartbeat has been recorded yet — outbound and inbound e-mail are paused.",
    ),
    ("home.title", "Overview"),
    (
        "home.subtitle",
        "Open workspace items, pending tasks, and recent records.",
    ),
    ("home.refresh", "Refresh"),
    ("home.see_all", "See all"),
    ("home.open_tabs", "Open tabs"),
    ("home.todo", "To-do"),
    ("home.helpdesk", "Helpdesk"),
    ("home.quotations", "Quotations"),
    ("home.purchasing", "Purchase orders"),
    (
        "home.empty",
        "No overview cards are available for your current permissions. Use the module navigation to open a section.",
    ),
    ("setup.title", "First-company setup"),
    (
        "setup.already_done",
        "This server already has a company configured.",
    ),
    ("setup.go_login", "Go to sign in"),
    ("admin.translations.title", "Interface translations"),
    (
        "admin.translations.help",
        "Upload a JSON catalogue (key → text) to add an interface language to the web UI or to correct texts. Texts missing in a language are shown in English.",
    ),
    ("admin.translations.export", "Export English template"),
    ("admin.translations.upload", "Upload catalogue"),
    ("admin.translations.remove", "Remove"),
];

/// The chosen interface language and its loaded catalogue.
#[derive(Clone, Copy)]
pub struct I18n {
    /// ISO 639-1 code; `en` shows the texts of the code.
    pub language: RwSignal<String>,
    pub catalogue: RwSignal<HashMap<String, String>>,
}

impl I18n {
    pub fn new() -> Self {
        Self {
            language: RwSignal::new(stored_language().unwrap_or_else(|| "en".to_string())),
            catalogue: RwSignal::new(HashMap::new()),
        }
    }
}

impl Default for I18n {
    fn default() -> Self {
        Self::new()
    }
}

/// The text of `key` in the interface language, `english` when the catalogue has none. Reactive:
/// call it inside a view closure to follow a change of language.
pub fn tr(key: &str, english: &str) -> String {
    match use_context::<I18n>() {
        Some(i) => i
            .catalogue
            .with(|c| c.get(key).cloned())
            .unwrap_or_else(|| english.to_string()),
        None => english.to_string(),
    }
}

/// Every key the web UI translates, with its English text.
pub fn source_catalogue() -> BTreeMap<String, String> {
    SOURCE
        .iter()
        .map(|(k, v)| (k.to_string(), v.to_string()))
        .chain(nav_source_texts())
        .collect()
}

/// Loads the `web` catalogue of the chosen language (none for English) into `i18n`.
pub fn load_catalogue(ctx: AppContext, i18n: I18n) {
    let language = i18n.language.get_untracked();
    if language == "en" {
        i18n.catalogue.set(HashMap::new());
        return;
    }
    spawn_api(
        ctx,
        move |c| async move { c.get_catalogue("web", &language).await },
        move |res| {
            let entries = res
                .map(|d| d.entries.into_iter().collect())
                .unwrap_or_default();
            set_alive(i18n.catalogue, entries);
        },
    );
}

/// Chooses the interface language: English (the texts of the code) or a language an
/// administrator installed for the web UI.
#[component]
pub fn InterfaceLanguagePicker() -> impl IntoView {
    let ctx = expect_context::<AppContext>();
    let Some(i18n) = use_context::<I18n>() else {
        return view! { <span></span> }.into_any();
    };
    let installed = RwSignal::new(Vec::<String>::new());
    spawn_api(
        ctx,
        |c| async move { c.list_catalogues("web").await },
        move |res| {
            if let Ok(list) = res {
                set_alive(
                    installed,
                    list.into_iter()
                        .filter(|c| c.company_entries > 0)
                        .map(|c| c.language)
                        .collect(),
                );
            }
        },
    );
    view! {
        <select
            class="tc-select tc-select-sm"
            data-target="interface-language"
            aria-label=move || tr("shell.interface_language", "Interface language")
            prop:value=move || i18n.language.get()
            on:change=move |ev| {
                let code = event_target_value(&ev);
                store_language(&code);
                i18n.language.set(code);
                load_catalogue(ctx, i18n);
            }
        >
            <option value="en">"English"</option>
            {move || installed.get().into_iter().filter(|c| c != "en").map(|c| view! {
                <option value=c.clone()>{c.to_uppercase()}</option>
            }).collect_view()}
        </select>
    }
    .into_any()
}

mod names {
    include!("../../core/src/languages/names_table.rs");
}

/// The language's own name, or the code when unknown.
pub fn language_name(code: &str) -> String {
    names::LANGUAGE_NAMES
        .binary_search_by(|(c, _, _)| (*c).cmp(code))
        .map(|i| names::LANGUAGE_NAMES[i].2.to_string())
        .unwrap_or_else(|_| code.to_string())
}

/// The content languages a server from before ADR 0101 supports (it sends no list).
const LEGACY_LANGUAGES: [&str; 5] = ["nl", "fr", "en", "de", "es"];

/// The company's content languages in their order (ADR 0101), plus `current` when it is not one
/// of them, as `(code, "Name (code)")` for a select.
pub fn language_options(ctx: &AppContext, current: Option<&str>) -> Vec<(String, String)> {
    let mut codes: Vec<String> = ctx
        .session
        .with_untracked(|s| s.as_ref().map(|a| a.me.company.languages.clone()))
        .filter(|l| !l.is_empty())
        .unwrap_or_else(|| LEGACY_LANGUAGES.map(String::from).to_vec());
    if let Some(c) = current.filter(|c| !c.is_empty()) {
        if !codes.iter().any(|x| x == c) {
            codes.push(c.to_string());
        }
    }
    codes
        .into_iter()
        .map(|c| {
            let label = format!("{} ({c})", language_name(&c));
            (c, label)
        })
        .collect()
}

#[cfg(target_arch = "wasm32")]
const STORAGE_KEY: &str = "tradocraft.web.language";

#[cfg(target_arch = "wasm32")]
fn storage() -> Option<web_sys::Storage> {
    web_sys::window()?.local_storage().ok().flatten()
}

/// The interface language chosen earlier in this browser.
#[cfg(target_arch = "wasm32")]
pub fn stored_language() -> Option<String> {
    storage()?.get_item(STORAGE_KEY).ok().flatten()
}

#[cfg(not(target_arch = "wasm32"))]
pub fn stored_language() -> Option<String> {
    None
}

/// Remembers the interface language in this browser.
#[cfg(target_arch = "wasm32")]
pub fn store_language(code: &str) {
    if let Some(s) = storage() {
        let _ = s.set_item(STORAGE_KEY, code);
    }
}

#[cfg(not(target_arch = "wasm32"))]
pub fn store_language(_code: &str) {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn names_come_from_the_shared_table() {
        assert_eq!(language_name("pt"), "Português");
        assert_eq!(language_name("zz"), "zz");
    }

    #[test]
    fn falls_back_to_english_without_a_context() {
        assert_eq!(tr("shell.sign_out", "Sign out"), "Sign out");
    }

    #[test]
    fn the_source_has_navigation_and_shell_texts() {
        let s = source_catalogue();
        assert_eq!(
            s.get("shell.sign_out").map(String::as_str),
            Some("Sign out")
        );
        assert_eq!(s.get("nav.products").map(String::as_str), Some("Products"));
        assert!(s.keys().all(|k| k
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '_' | '.' | '-'))));
    }
}
