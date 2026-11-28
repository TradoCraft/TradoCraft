//! Administration, section "Company": interface translations of the web UI (ADR 0101). The
//! English source catalogue is exported as JSON; a translated JSON file (`key → text`) is
//! uploaded per language into the `web` domain and loaded by every browser that chooses it.

use std::collections::BTreeMap;

use leptos::prelude::*;
use tradocraft_api_client::translations::{CatalogueInfo, CatalogueInput};

use super::{begin_file_read, save_file, spawn_api, Feedback, FeedbackView};
use crate::i18n::{source_catalogue, tr};
use crate::pages::set_alive;
use crate::state::AppContext;

/// The largest catalogue file accepted.
const MAX_FILE_BYTES: usize = 2 * 1024 * 1024;

/// The texts of an uploaded JSON or ARB file: string values whose keys do not start with `@`.
pub(crate) fn parse_catalogue(bytes: &[u8]) -> Result<BTreeMap<String, String>, String> {
    let value: serde_json::Value =
        serde_json::from_slice(bytes).map_err(|_| "The file is not JSON.".to_string())?;
    let obj = value
        .as_object()
        .ok_or_else(|| "The file must hold one JSON object of texts.".to_string())?;
    Ok(obj
        .iter()
        .filter(|(k, _)| !k.starts_with('@'))
        .filter_map(|(k, v)| v.as_str().map(|v| (k.clone(), v.to_string())))
        .collect())
}

#[component]
pub fn InterfaceTranslations() -> impl IntoView {
    let ctx = expect_context::<AppContext>();
    let fb = Feedback::new();
    let list = RwSignal::new(Vec::<CatalogueInfo>::new());
    let language = RwSignal::new(String::new());
    let busy = RwSignal::new(false);
    let reload = RwSignal::new(0_u32);

    Effect::new(move |_| {
        let _ = reload.get();
        spawn_api(
            ctx,
            |c| async move { c.list_catalogues("web").await },
            move |res| {
                if let Ok(l) = res {
                    set_alive(list, l);
                }
            },
        );
    });

    let export = move |_| {
        let json = serde_json::to_vec_pretty(&source_catalogue()).unwrap_or_default();
        if let Err(msg) = save_file("web_en.json", "application/json", &json) {
            fb.fail(msg);
        }
    };

    let upload = move |ev: leptos::ev::Event| {
        let code = language.get_untracked().trim().to_lowercase();
        if code.len() != 2 {
            fb.fail("Enter the two-letter code of the language first.");
            return;
        }
        busy.set(true);
        begin_file_read(ev, MAX_FILE_BYTES, "The file is too large.", move |res| {
            let entries = match res.and_then(|p| parse_catalogue(&p.bytes)) {
                Ok(e) => e,
                Err(msg) => {
                    if set_alive(busy, false) && !msg.is_empty() {
                        fb.fail(msg);
                    }
                    return;
                }
            };
            let body = CatalogueInput { entries };
            spawn_api(
                ctx,
                move |c| async move { c.put_catalogue("web", &code, &body).await },
                move |res| {
                    if !set_alive(busy, false) {
                        return;
                    }
                    match res {
                        Ok(_) => {
                            fb.ok("Catalogue saved");
                            reload.update(|n| *n += 1);
                        }
                        Err(err) => {
                            fb.fail(err.user_message());
                        }
                    }
                },
            );
        });
    };

    let remove = move |code: String| {
        busy.set(true);
        spawn_api(
            ctx,
            move |c| async move { c.delete_catalogue("web", &code).await },
            move |res| {
                if !set_alive(busy, false) {
                    return;
                }
                match res {
                    Ok(()) => {
                        fb.ok("Catalogue removed");
                        reload.update(|n| *n += 1);
                    }
                    Err(err) => {
                        fb.fail(err.user_message());
                    }
                }
            },
        );
    };

    view! {
        <section data-target="admin-translations" aria-labelledby="admin-translations-title">
            <h2 id="admin-translations-title" class="tc-page-title" style="font-size: 18px; margin-top: var(--space-xl);">
                {move || tr("admin.translations.title", "Interface translations")}
            </h2>
            <p style="color: var(--on-surface-variant);">
                {move || tr(
                    "admin.translations.help",
                    "Upload a JSON catalogue (key → text) to add an interface language to the web UI or to correct texts. Texts missing in a language are shown in English.",
                )}
            </p>
            <FeedbackView fb prefix="admin-translations" />
            <ul style="list-style: none; padding: 0;" data-target="admin-translations-list">
                {move || list.get().into_iter().filter(|c| c.company_entries > 0).map(|c| {
                    let code = c.language.clone();
                    view! {
                        <li class="tc-toolbar" data-target=format!("admin-translation-{}", c.language)>
                            <span style="flex: 1;">{format!("{} · {} texts", c.language, c.company_entries)}</span>
                            <button type="button" class="tc-btn tc-btn-sm" disabled=move || busy.get()
                                on:click=move |_| remove(code.clone())>
                                {move || tr("admin.translations.remove", "Remove")}
                            </button>
                        </li>
                    }
                }).collect_view()}
            </ul>
            <div class="tc-toolbar">
                <button type="button" class="tc-btn" data-target="admin-translations-export" on:click=export>
                    {move || tr("admin.translations.export", "Export English template")}
                </button>
                <label class="tc-label" for="admin-translations-language">"ISO 639-1"</label>
                <input id="admin-translations-language" class="tc-input" style="width: 64px;" maxlength="2"
                    data-target="admin-translations-language"
                    prop:value=move || language.get()
                    on:input=move |ev| language.set(event_target_value(&ev)) />
                <label class="tc-label" for="admin-translations-upload">
                    {move || tr("admin.translations.upload", "Upload catalogue")}
                </label>
                <input id="admin-translations-upload" type="file" class="tc-input" accept=".json,.arb,application/json"
                    data-target="admin-translations-upload"
                    disabled=move || busy.get()
                    on:change=upload />
            </div>
        </section>
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_flat_json_and_arb() {
        let e = parse_catalogue(br#"{"@@locale":"pt","nav.products":"Produtos","n":1}"#).unwrap();
        assert_eq!(e.len(), 1);
        assert_eq!(e["nav.products"], "Produtos");
        assert!(parse_catalogue(b"[1]").is_err());
        assert!(parse_catalogue(b"nope").is_err());
    }
}
