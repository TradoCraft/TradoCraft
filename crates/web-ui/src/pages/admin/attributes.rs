//! Administration, section "Attributes" (ADR 0068): the admin-tunable fields products and site
//! baseline items carry. List, create, edit (incl. select options), deactivate and delete; the
//! server refuses deleting a definition in use (409) and says to deactivate it. Mirrors
//! `attribute_definitions_page.dart`. Key, type and scope are fixed once created.

use leptos::ev::SubmitEvent;
use leptos::prelude::*;
use tradocraft_api_client::attributes::{
    AttributeDefinition, AttributeDefinitionInput, BaselineItemType, DefinitionKind, SelectOption,
};
use uuid::Uuid;

use super::{bump, is_current, spawn_api, Feedback, FeedbackView};
use crate::pages::set_alive;
use crate::state::AppContext;

pub(crate) fn kind_label(k: DefinitionKind) -> &'static str {
    match k {
        DefinitionKind::Number => "Number",
        DefinitionKind::Range => "Range",
        DefinitionKind::Select => "Select",
        DefinitionKind::Text => "Text",
        DefinitionKind::Boolean => "Yes/No",
    }
}

/// `^[a-z][a-z0-9_]{0,63}$`, as the server requires.
pub(crate) fn valid_key(key: &str) -> bool {
    let mut chars = key.chars();
    matches!(chars.next(), Some('a'..='z'))
        && key.len() <= 64
        && chars.all(|c| matches!(c, 'a'..='z' | '0'..='9' | '_'))
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct AttrDraft {
    pub key: String,
    pub label: String,
    pub unit: String,
    pub scope: String,
    pub sort: String,
    pub kind: DefinitionKind,
    pub active: bool,
    /// (value, label) per option row.
    pub options: Vec<(String, String)>,
}

impl Default for AttrDraft {
    fn default() -> Self {
        Self {
            key: String::new(),
            label: String::new(),
            unit: String::new(),
            scope: "product".into(),
            sort: "0".into(),
            kind: DefinitionKind::Number,
            active: true,
            options: Vec::new(),
        }
    }
}

impl AttrDraft {
    fn from_definition(d: &AttributeDefinition) -> Self {
        Self {
            key: d.key.clone(),
            label: d.label.clone(),
            unit: d.unit.clone().unwrap_or_default(),
            scope: d.scope.clone(),
            sort: d.sort_order.to_string(),
            kind: d.kind,
            active: d.active,
            options: d
                .options
                .iter()
                .map(|o| (o.value.clone(), o.label.clone()))
                .collect(),
        }
    }

    fn has_unit(&self) -> bool {
        matches!(self.kind, DefinitionKind::Number | DefinitionKind::Range)
    }

    /// Mirrors the server rules and builds the request.
    pub fn to_input(&self) -> Result<AttributeDefinitionInput, String> {
        let key = self.key.trim();
        if !valid_key(key) {
            return Err("The key must be lowercase letters, digits and underscores, start with a letter and have at most 64 characters.".into());
        }
        if self.label.trim().is_empty() {
            return Err("A label is required.".into());
        }
        let sort = self
            .sort
            .trim()
            .parse::<i32>()
            .map_err(|_| "Sort order must be a whole number.".to_string())?;
        let options = if self.kind == DefinitionKind::Select {
            if self.options.is_empty() {
                return Err("A select needs at least one option.".into());
            }
            let mut seen = Vec::new();
            let mut out = Vec::new();
            for (v, l) in &self.options {
                let (v, l) = (v.trim(), l.trim());
                if v.is_empty() || l.is_empty() {
                    return Err("Every option needs a value and a label.".into());
                }
                if seen.contains(&v) {
                    return Err("Option values must be unique.".into());
                }
                seen.push(v);
                out.push(SelectOption {
                    value: v.to_string(),
                    label: l.to_string(),
                });
            }
            Some(out)
        } else {
            None
        };
        let unit = self.unit.trim();
        Ok(AttributeDefinitionInput {
            key: key.to_string(),
            label: self.label.trim().to_string(),
            kind: self.kind,
            unit: (self.has_unit() && !unit.is_empty()).then(|| unit.to_string()),
            options,
            scope: Some(self.scope.clone()),
            sort_order: Some(sort),
            active: Some(self.active),
        })
    }
}

/// `key · Number · mm · product · inactive`.
pub(crate) fn definition_subtitle(d: &AttributeDefinition) -> String {
    let mut parts = vec![d.key.clone(), kind_label(d.kind).to_string()];
    if let Some(u) = d.unit.as_deref().filter(|u| !u.is_empty()) {
        parts.push(u.to_string());
    }
    parts.push(d.scope.clone());
    if !d.active {
        parts.push("inactive".into());
    }
    parts.join(" \u{b7} ")
}

/// The scopes on offer: product, the baseline item types (not a legacy type named `product`), and
/// a scope whose type is gone when editing.
pub(crate) fn scope_options(types: &[BaselineItemType], current: &str) -> Vec<(String, String)> {
    let mut out = vec![("product".to_string(), "Product".to_string())];
    for t in types.iter().filter(|t| t.code != "product") {
        out.push((t.code.clone(), format!("{} ({})", t.name, t.code)));
    }
    if !out.iter().any(|(c, _)| c == current) {
        out.push((current.to_string(), current.to_string()));
    }
    out
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Editor {
    New,
    Edit(Uuid),
}

#[component]
pub fn AttributesSection() -> impl IntoView {
    let ctx = expect_context::<AppContext>();
    let fb = Feedback::new();
    let defs = RwSignal::new(Option::<Vec<AttributeDefinition>>::None);
    let types = RwSignal::new(Vec::<BaselineItemType>::new());
    let reload = RwSignal::new(0_u64);
    let load_error = RwSignal::new(Option::<String>::None);
    let can_write = Memo::new(move |_| {
        ctx.session.with(|s| {
            s.as_ref()
                .is_some_and(|a| a.me.has_permission("products.write"))
        })
    });

    let editor = RwSignal::new(Option::<Editor>::None);
    let editor_gen = RwSignal::new(0_u64);
    let draft = RwSignal::new(AttrDraft::default());
    let editor_error = RwSignal::new(Option::<String>::None);
    let saving = RwSignal::new(false);
    let confirm_delete = RwSignal::new(Option::<Uuid>::None);

    // Only the newest list request may fill the list; set_alive only covers the page being left.
    let list_seq = StoredValue::new(0_u64);
    Effect::new(move |_| {
        let _ = reload.get();
        load_error.set(None);
        let gen = bump(list_seq);
        spawn_api(
            ctx,
            |c| async move { c.list_attribute_definitions().await },
            move |res| {
                if !is_current(list_seq, gen) {
                    return;
                }
                match res {
                    Ok(list) => {
                        set_alive(defs, Some(list));
                    }
                    Err(err) => {
                        set_alive(load_error, Some(err.user_message()));
                    }
                }
            },
        );
    });
    // The baseline item types only fill the scope choice; without them it offers Product.
    spawn_api(
        ctx,
        |c| async move { c.list_baseline_item_types().await },
        move |res| {
            if let Ok(list) = res {
                set_alive(types, list);
            }
        },
    );

    let open = move |target: Editor, d: AttrDraft| {
        draft.set(d);
        editor_error.set(None);
        editor_gen.update(|g| *g = g.wrapping_add(1));
        editor.set(Some(target));
    };
    let editing = Memo::new(move |_| matches!(editor.get(), Some(Editor::Edit(_))));

    let on_save = move |ev: SubmitEvent| {
        ev.prevent_default();
        let Some(target) = editor.get_untracked() else {
            return;
        };
        let input = match draft.with_untracked(AttrDraft::to_input) {
            Ok(i) => i,
            Err(msg) => {
                editor_error.set(Some(msg));
                return;
            }
        };
        saving.set(true);
        let gen = editor_gen.get_untracked();
        spawn_api(
            ctx,
            move |c| async move {
                match target {
                    Editor::New => c.create_attribute_definition(&input).await,
                    Editor::Edit(id) => c.update_attribute_definition(id, &input).await,
                }
            },
            move |res| {
                if !set_alive(saving, false) {
                    return;
                }
                let still_open = editor_gen.get_untracked() == gen;
                match res {
                    Ok(_) => {
                        if still_open {
                            editor.set(None);
                        }
                        fb.ok("Saved");
                        reload.update(|n| *n += 1);
                    }
                    Err(err) => {
                        if still_open {
                            editor_error.set(Some(err.user_message()));
                        } else {
                            fb.fail(err.user_message());
                        }
                    }
                }
            },
        );
    };

    let on_delete = move |id: Uuid| {
        confirm_delete.set(None);
        spawn_api(
            ctx,
            move |c| async move { c.delete_attribute_definition(id).await },
            move |res| match res {
                Ok(()) => {
                    if fb.ok("Attribute deleted.") {
                        reload.update(|n| *n += 1);
                    }
                }
                // A 409 (in use) is shown as the server's message: "... deactivate it instead".
                Err(err) => {
                    fb.fail(err.user_message());
                }
            },
        );
    };

    view! {
        <section data-target="admin-attributes" aria-labelledby="admin-attributes-title">
            <div class="tc-page-header" style="margin-bottom: var(--space-sm);">
                <h2 id="admin-attributes-title" class="tc-page-title" style="font-size: 18px;">"Attribute definitions"</h2>
                <Show when=move || can_write.get()>
                    <button type="button" data-target="admin-attr-new" class="tc-btn tc-btn-primary"
                        on:click=move |_| open(Editor::New, AttrDraft::default())>
                        "New attribute"
                    </button>
                </Show>
            </div>
            <FeedbackView fb prefix="admin-attributes" />

            <Show when=move || editor.with(Option::is_some)>
                <form class="tc-card" data-target="admin-attr-editor" on:submit=on_save style="margin-bottom: var(--space-md);" aria-labelledby="admin-attr-editor-title">
                    <h3 id="admin-attr-editor-title" style="margin-top: 0;">
                        {move || if editing.get() { "Edit attribute" } else { "New attribute" }}
                    </h3>
                    // Disabled while saving, so no edit is made after the request was sent and then lost.
                    <fieldset style="border: none; padding: 0; margin: 0; min-width: 0;" disabled=move || saving.get()>
                        <div class="tc-form-grid">
                            <div class="tc-field">
                                <label class="tc-label" for="admin-attr-key">"Key"</label>
                                <input id="admin-attr-key" data-target="admin-attr-key" class="tc-input" type="text"
                                    disabled=move || editing.get()
                                    prop:value=move || draft.with(|d| d.key.clone())
                                    on:input=move |ev| draft.update(|d| d.key = event_target_value(&ev)) />
                            </div>
                            <div class="tc-field">
                                <label class="tc-label" for="admin-attr-label">"Label"</label>
                                <input id="admin-attr-label" data-target="admin-attr-label" class="tc-input" type="text"
                                    prop:value=move || draft.with(|d| d.label.clone())
                                    on:input=move |ev| draft.update(|d| d.label = event_target_value(&ev)) />
                            </div>
                            <div class="tc-field">
                                <label class="tc-label" for="admin-attr-kind">"Type"</label>
                                <select id="admin-attr-kind" data-target="admin-attr-kind" class="tc-select"
                                    disabled=move || editing.get()
                                    on:change=move |ev| {
                                        if let Some(k) = DefinitionKind::parse(&event_target_value(&ev)) {
                                            draft.update(|d| d.kind = k);
                                        }
                                    }>
                                    {DefinitionKind::ALL.into_iter().map(|k| view! {
                                        <option value=k.as_str() selected=move || draft.with(|d| d.kind == k)>{kind_label(k)}</option>
                                    }).collect_view()}
                                </select>
                            </div>
                            <Show when=move || draft.with(AttrDraft::has_unit)>
                                <div class="tc-field">
                                    <label class="tc-label" for="admin-attr-unit">"Unit"</label>
                                    <input id="admin-attr-unit" data-target="admin-attr-unit" class="tc-input" type="text"
                                        prop:value=move || draft.with(|d| d.unit.clone())
                                        on:input=move |ev| draft.update(|d| d.unit = event_target_value(&ev)) />
                                </div>
                            </Show>
                            <div class="tc-field">
                                <label class="tc-label" for="admin-attr-scope">"Scope"</label>
                                <select id="admin-attr-scope" data-target="admin-attr-scope" class="tc-select"
                                    disabled=move || editing.get()
                                    on:change=move |ev| draft.update(|d| d.scope = event_target_value(&ev))>
                                    {move || {
                                        let current = draft.with(|d| d.scope.clone());
                                        types.with(|t| scope_options(t, &current)).into_iter().map(|(code, label)| {
                                            let selected = code == current;
                                            view! { <option value=code selected=selected>{label}</option> }
                                        }).collect_view()
                                    }}
                                </select>
                            </div>
                            <div class="tc-field">
                                <label class="tc-label" for="admin-attr-sort">"Sort order"</label>
                                <input id="admin-attr-sort" data-target="admin-attr-sort" class="tc-input" type="text" inputmode="numeric"
                                    prop:value=move || draft.with(|d| d.sort.clone())
                                    on:input=move |ev| draft.update(|d| d.sort = event_target_value(&ev)) />
                            </div>
                        </div>
                        <label class="tc-checkbox-row" style="margin-top: var(--space-sm);">
                            <input type="checkbox" data-target="admin-attr-active"
                                prop:checked=move || draft.with(|d| d.active)
                                on:change=move |ev| {
                                    let on = event_target_checked(&ev);
                                    draft.update(|d| d.active = on);
                                } />
                            "Active"
                        </label>
                        <Show when=move || draft.with(|d| d.kind == DefinitionKind::Select)>
                            <fieldset style="border: none; padding: 0; margin: var(--space-md) 0 0;" data-target="admin-attr-options">
                                <legend class="tc-label">"Options"</legend>
                                {move || (0..draft.with(|d| d.options.len())).map(|i| view! {
                                    <div class="tc-toolbar">
                                        <input class="tc-input" type="text" data-target=format!("admin-attr-option-value-{i}")
                                            aria-label=format!("Value of option {}", i + 1)
                                            placeholder="Value"
                                            prop:value=move || draft.with(|d| d.options.get(i).map(|o| o.0.clone()).unwrap_or_default())
                                            on:input=move |ev| draft.update(|d| if let Some(o) = d.options.get_mut(i) { o.0 = event_target_value(&ev); }) />
                                        <input class="tc-input" type="text" data-target=format!("admin-attr-option-label-{i}")
                                            aria-label=format!("Label of option {}", i + 1)
                                            placeholder="Option label"
                                            prop:value=move || draft.with(|d| d.options.get(i).map(|o| o.1.clone()).unwrap_or_default())
                                            on:input=move |ev| draft.update(|d| if let Some(o) = d.options.get_mut(i) { o.1 = event_target_value(&ev); }) />
                                        <button type="button" class="tc-btn tc-btn-sm" data-target=format!("admin-attr-option-remove-{i}")
                                            aria-label=format!("Remove option {}", i + 1)
                                            on:click=move |_| draft.update(|d| { if i < d.options.len() { d.options.remove(i); } })>
                                            "Remove"
                                        </button>
                                    </div>
                                }).collect_view()}
                                <button type="button" class="tc-btn tc-btn-sm" data-target="admin-attr-option-add"
                                    on:click=move |_| draft.update(|d| d.options.push((String::new(), String::new())))>
                                    "Add option"
                                </button>
                            </fieldset>
                        </Show>
                    </fieldset>
                    {move || editor_error.get().map(|msg| view! {
                        <div class="tc-alert-error" style="margin-top: var(--space-md);" role="alert" data-target="admin-attr-editor-error">{msg}</div>
                    })}
                    <div class="tc-toolbar" style="margin-top: var(--space-md);">
                        <button type="submit" data-target="admin-attr-save" class="tc-btn tc-btn-primary" disabled=move || saving.get()>
                            {move || if saving.get() { "Saving..." } else { "Save" }}
                        </button>
                        <button type="button" class="tc-btn" disabled=move || saving.get() on:click=move |_| editor.set(None)>"Cancel"</button>
                    </div>
                </form>
            </Show>

            {move || load_error.get().map(|msg| view! {
                <div class="tc-alert-error" role="alert" data-target="admin-attr-load-error" style="margin-bottom: var(--space-md);">
                    {msg}
                    " "
                    <button type="button" class="tc-btn tc-btn-sm" data-target="admin-attr-retry" on:click=move |_| reload.update(|n| *n += 1)>"Retry"</button>
                </div>
            })}

            {move || match defs.get() {
                None => view! { <p class="tc-label">"Loading attribute definitions..."</p> }.into_any(),
                Some(list) if list.is_empty() => view! { <p data-target="admin-attr-empty">"No attribute definitions yet."</p> }.into_any(),
                Some(list) => view! {
                    <ul data-target="admin-attr-list" style="list-style: none; margin: 0; padding: 0;">
                        {list.into_iter().map(|d| {
                            let id = d.id;
                            let key = d.key.clone();
                            let row_target = format!("admin-attr-{key}");
                            let subtitle = definition_subtitle(&d);
                            let draft_of = AttrDraft::from_definition(&d);
                            let question = format!("Delete attribute {}? If it is in use, deactivate it instead.", d.key);
                            view! {
                                <li class="tc-card" style="margin-bottom: var(--space-sm);" data-target=row_target>
                                    <div style="display: flex; align-items: center; gap: var(--space-sm); flex-wrap: wrap;">
                                        <div style="flex: 1; min-width: 200px;">
                                            <strong>{d.label.clone()}</strong>
                                            <div class="tc-label">{subtitle}</div>
                                        </div>
                                        <Show when=move || can_write.get()>
                                            {
                                                let draft_of = draft_of.clone();
                                                let key = key.clone();
                                                view! {
                                                    <button type="button" class="tc-btn tc-btn-sm" data-target=format!("admin-attr-edit-{key}")
                                                        aria-label=format!("Edit attribute {key}")
                                                        on:click=move |_| open(Editor::Edit(id), draft_of.clone())>"Edit"</button>
                                                    <button type="button" class="tc-btn tc-btn-sm" data-target=format!("admin-attr-delete-{key}")
                                                        aria-label=format!("Delete attribute {key}")
                                                        on:click=move |_| confirm_delete.set(Some(id))>"Delete"</button>
                                                }
                                            }
                                        </Show>
                                    </div>
                                    <Show when=move || confirm_delete.get() == Some(id)>
                                        <div class="tc-toolbar" role="alert" style="margin-top: var(--space-sm);">
                                            <span>{question.clone()}</span>
                                            <button type="button" class="tc-btn tc-btn-primary tc-btn-sm" data-target="admin-attr-delete-confirm"
                                                on:click=move |_| on_delete(id)>"Delete"</button>
                                            <button type="button" class="tc-btn tc-btn-sm" on:click=move |_| confirm_delete.set(None)>"Cancel"</button>
                                        </div>
                                    </Show>
                                </li>
                            }
                        }).collect_view()}
                    </ul>
                }.into_any(),
            }}
        </section>
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn keys_follow_the_server_pattern() {
        assert!(valid_key("width_mm"));
        assert!(valid_key("a"));
        assert!(!valid_key("Width"));
        assert!(!valid_key("1a"));
        assert!(!valid_key("a-b"));
        assert!(!valid_key(&"a".repeat(65)));
        assert!(valid_key(&"a".repeat(64)));
    }

    #[test]
    fn select_needs_unique_complete_options() {
        let mut d = AttrDraft {
            key: "colour".into(),
            label: "Colour".into(),
            kind: DefinitionKind::Select,
            ..AttrDraft::default()
        };
        assert_eq!(
            d.to_input().unwrap_err(),
            "A select needs at least one option."
        );
        d.options = vec![("red".into(), String::new())];
        assert_eq!(
            d.to_input().unwrap_err(),
            "Every option needs a value and a label."
        );
        d.options = vec![
            ("red".into(), "Red".into()),
            (" red ".into(), "Rood".into()),
        ];
        assert_eq!(d.to_input().unwrap_err(), "Option values must be unique.");
        d.options.pop();
        let input = d.to_input().unwrap();
        assert_eq!(input.options.unwrap().len(), 1);
        assert_eq!(input.unit, None);
    }

    #[test]
    fn unit_only_for_numbers_and_ranges() {
        let mut d = AttrDraft {
            key: "w".into(),
            label: "W".into(),
            unit: " mm ".into(),
            ..AttrDraft::default()
        };
        assert_eq!(d.to_input().unwrap().unit.as_deref(), Some("mm"));
        d.kind = DefinitionKind::Text;
        assert_eq!(d.to_input().unwrap().unit, None);
        assert_eq!(d.to_input().unwrap().options, None);
    }

    #[test]
    fn scopes_keep_a_vanished_type_visible() {
        let t = BaselineItemType {
            id: Uuid::nil(),
            code: "boiler".into(),
            name: "Boiler".into(),
            allowed_parent_codes: vec![],
            allow_top_level: true,
            sort_order: 0,
            active: true,
        };
        let opts = scope_options(&[t], "product");
        assert_eq!(opts.len(), 2);
        assert_eq!(opts[1].1, "Boiler (boiler)");
        assert_eq!(scope_options(&[], "gone").len(), 2);
    }
}
