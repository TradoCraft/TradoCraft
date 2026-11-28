//! Administration, section "Company": the company's content languages (ADR 0101), an ordered list
//! with one default. Mirrors `company_languages_section.dart`.

use leptos::prelude::*;
use tradocraft_api_client::admin::{CompanyLanguagesInput, LanguageInfo};

use super::{refresh_me, spawn_api, Feedback, FeedbackView};
use crate::pages::set_alive;
use crate::state::AppContext;

/// Moves the language at `i` one place up (`up`) or down; out-of-range moves change nothing.
pub(crate) fn move_language(list: &mut [String], i: usize, up: bool) {
    let j = if up { i.checked_sub(1) } else { Some(i + 1) };
    if let Some(j) = j.filter(|j| *j < list.len()) {
        list.swap(i, j);
    }
}

/// The label of a language: its own name with the code, or the code alone when unknown.
pub(crate) fn language_label(all: &[LanguageInfo], code: &str) -> String {
    all.iter()
        .find(|l| l.code == code)
        .map(|l| format!("{} ({}, {code})", l.name, l.english_name))
        .unwrap_or_else(|| code.to_string())
}

/// The edited language list and default language.
type Draft = (Vec<String>, String);

#[component]
pub fn CompanyLanguages() -> impl IntoView {
    let ctx = expect_context::<AppContext>();
    let fb = Feedback::new();
    let all = RwSignal::new(Vec::<LanguageInfo>::new());
    let busy = RwSignal::new(false);
    // The edited list and default; None until something is changed.
    let draft = RwSignal::new(Option::<Draft>::None);
    let adding = RwSignal::new(String::new());

    spawn_api(
        ctx,
        |c| async move { c.list_languages().await },
        move |res| {
            if let Ok(list) = res {
                set_alive(all, list);
            }
        },
    );

    let saved = Memo::new(move |_| {
        ctx.session.with(|s| {
            s.as_ref()
                .map(|a| {
                    let c = &a.me.company;
                    let langs = if c.languages.is_empty() {
                        vec![c.default_language.clone()]
                    } else {
                        c.languages.clone()
                    };
                    (langs, c.default_language.clone())
                })
                .unwrap_or_else(|| (vec!["en".into()], "en".into()))
        })
    });
    let current = Memo::new(move |_| draft.get().unwrap_or_else(|| saved.get()));
    let edit = move |f: &dyn Fn(&mut Draft)| {
        let mut next = current.get_untracked();
        f(&mut next);
        draft.set(Some(next));
    };

    let save = move |_| {
        let Some((languages, default_language)) = draft.get_untracked() else {
            return;
        };
        if busy.get_untracked() {
            return;
        }
        busy.set(true);
        let body = CompanyLanguagesInput {
            languages,
            default_language,
        };
        spawn_api(
            ctx,
            move |c| async move { c.set_company_languages(&body).await },
            move |res| {
                if !set_alive(busy, false) {
                    return;
                }
                match res {
                    Ok(_) => {
                        draft.set(None);
                        fb.ok("Languages saved");
                        refresh_me(ctx);
                    }
                    Err(err) => {
                        fb.fail(err.user_message());
                    }
                }
            },
        );
    };

    view! {
        <section data-target="admin-languages" aria-labelledby="admin-languages-title">
            <h2 id="admin-languages-title" class="tc-page-title" style="font-size: 18px; margin-top: var(--space-xl);">
                "Content languages"
            </h2>
            <p style="color: var(--on-surface-variant);">
                "The languages your company writes and prints in. Language pickers offer them in this order."
            </p>
            <FeedbackView fb prefix="admin-languages" />
            <ul class="tc-list" data-target="admin-languages-list" style="list-style: none; padding: 0; max-width: 560px;">
                {move || {
                    let (langs, def) = current.get();
                    let n = langs.len();
                    langs.into_iter().enumerate().map(|(i, code)| {
                        let is_default = code == def;
                        let first = i == 0;
                        let last = i + 1 == n;
                        let label = all.with(|a| language_label(a, &code));
                        let c1 = code.clone();
                        let c2 = code.clone();
                        view! {
                            <li class="tc-toolbar" data-target=format!("admin-language-{code}")>
                                <span style="flex: 1;">{label}</span>
                                {is_default.then(|| view! { <span class="tc-chip">"Default"</span> })}
                                <button type="button" class="tc-btn tc-btn-sm" aria-label="Move up"
                                    disabled=move || busy.get() || first
                                    on:click=move |_| edit(&|d| move_language(&mut d.0, i, true))>"↑"</button>
                                <button type="button" class="tc-btn tc-btn-sm" aria-label="Move down"
                                    disabled=move || busy.get() || last
                                    on:click=move |_| edit(&|d| move_language(&mut d.0, i, false))>"↓"</button>
                                <button type="button" class="tc-btn tc-btn-sm"
                                    data-target=format!("admin-language-default-{code}")
                                    disabled=move || busy.get() || is_default
                                    on:click=move |_| { let c = c1.clone(); edit(&move |d| d.1 = c.clone()) }>"Make default"</button>
                                <button type="button" class="tc-btn tc-btn-sm"
                                    data-target=format!("admin-language-remove-{code}")
                                    disabled=move || busy.get() || is_default
                                    on:click=move |_| { let c = c2.clone(); edit(&move |d| d.0.retain(|l| *l != c)) }>"Remove"</button>
                            </li>
                        }
                    }).collect_view()
                }}
            </ul>
            <div class="tc-toolbar">
                <label class="tc-label" for="admin-language-add">"Add language"</label>
                <select id="admin-language-add" class="tc-select" data-target="admin-language-add"
                    prop:value=move || adding.get()
                    on:change=move |ev| adding.set(event_target_value(&ev))>
                    <option value="">"Choose..."</option>
                    {move || {
                        let taken = current.get().0;
                        all.get().into_iter().filter(|l| !taken.contains(&l.code)).map(|l| view! {
                            <option value=l.code.clone()>{format!("{} ({}, {})", l.name, l.english_name, l.code)}</option>
                        }).collect_view()
                    }}
                </select>
                <button type="button" class="tc-btn" data-target="admin-language-add-button"
                    disabled=move || busy.get() || adding.get().is_empty()
                    on:click=move |_| {
                        let code = adding.get_untracked();
                        adding.set(String::new());
                        edit(&move |d| if !d.0.contains(&code) { d.0.push(code.clone()) });
                    }>"Add"</button>
                <button type="button" class="tc-btn tc-btn-primary" data-target="admin-languages-save"
                    disabled=move || busy.get() || draft.get().is_none()
                    on:click=save>"Save languages"</button>
            </div>
        </section>
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn moves_within_bounds() {
        let mut l: Vec<String> = ["nl", "fr", "en"].map(String::from).to_vec();
        move_language(&mut l, 0, true);
        assert_eq!(l, ["nl", "fr", "en"]);
        move_language(&mut l, 0, false);
        assert_eq!(l, ["fr", "nl", "en"]);
        move_language(&mut l, 2, false);
        assert_eq!(l, ["fr", "nl", "en"]);
        move_language(&mut l, 2, true);
        assert_eq!(l, ["fr", "en", "nl"]);
    }

    #[test]
    fn labels_known_and_unknown_codes() {
        let all = vec![LanguageInfo {
            code: "pt".into(),
            english_name: "Portuguese".into(),
            name: "Português".into(),
        }];
        assert_eq!(language_label(&all, "pt"), "Português (Portuguese, pt)");
        assert_eq!(language_label(&all, "zz"), "zz");
    }
}
