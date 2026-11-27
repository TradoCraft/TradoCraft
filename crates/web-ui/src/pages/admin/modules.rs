//! Administration, section "Modules": company-wide module switches shown as a dependency tree.
//! Mirrors `modules_page.dart` and the pure rules of `modules_tree.dart`. The server validates the
//! dependencies again and answers 422 with a message.

use std::collections::{BTreeSet, HashSet};

use leptos::prelude::*;
use tradocraft_api_client::admin::{ModuleInfo, ModulesInput};

use super::{module_name, module_names, refresh_me, spawn_api, Feedback, FeedbackView};
use crate::pages::set_alive;
use crate::state::AppContext;

/// One row of the module tree. A module with several requirements appears once under each of
/// them; only the first occurrence has `repeat` false.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct ModuleTreeNode {
    pub code: String,
    pub depth: usize,
    /// The module this row is listed under; none for roots.
    pub parent: Option<String>,
    /// True when the module was already listed elsewhere in the tree.
    pub repeat: bool,
    /// Direct requirements other than `parent`.
    pub other_requires: Vec<String>,
    /// All direct requirements, in catalogue order.
    pub requires: Vec<String>,
    pub children: Vec<ModuleTreeNode>,
}

impl ModuleTreeNode {
    /// A stable id for the expansion state: the code for the first occurrence.
    pub fn id(&self) -> String {
        if self.repeat {
            format!(
                "{}-under-{}",
                self.code,
                self.parent.as_deref().unwrap_or("")
            )
        } else {
            self.code.clone()
        }
    }
}

/// One visible row of the module tree: a node without its subtree.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct ModuleRow {
    pub id: String,
    pub code: String,
    pub depth: usize,
    pub repeat: bool,
    pub other_requires: Vec<String>,
    pub requires: Vec<String>,
    pub has_children: bool,
}

/// Builds the forest from `catalogue` (module code -> direct requirements, in catalogue order).
/// Roots have no requirements; children are the modules that require the parent. Requirements on
/// unknown codes are ignored; modules on a cycle are still listed (as extra roots).
pub(crate) fn build_module_tree(catalogue: &[(String, Vec<String>)]) -> Vec<ModuleTreeNode> {
    let order: Vec<&str> = catalogue.iter().map(|(c, _)| c.as_str()).collect();
    let requires_of = |c: &str| -> &[String] {
        catalogue
            .iter()
            .find(|(k, _)| k == c)
            .map(|(_, r)| r.as_slice())
            .unwrap_or(&[])
    };
    let reqs = |c: &str| -> Vec<String> {
        order
            .iter()
            .filter(|o| requires_of(c).iter().any(|r| r == *o))
            .map(|o| o.to_string())
            .collect()
    };
    let dependents = |c: &str| -> Vec<String> {
        order
            .iter()
            .filter(|o| **o != c && requires_of(o).iter().any(|r| r == c))
            .map(|o| o.to_string())
            .collect()
    };

    fn make(
        code: &str,
        depth: usize,
        parent: Option<&str>,
        path: &HashSet<String>,
        seen: &mut HashSet<String>,
        reqs: &dyn Fn(&str) -> Vec<String>,
        dependents: &dyn Fn(&str) -> Vec<String>,
    ) -> ModuleTreeNode {
        let repeat = !seen.insert(code.to_string());
        let r = reqs(code);
        let mut node = ModuleTreeNode {
            code: code.to_string(),
            depth,
            parent: parent.map(str::to_string),
            repeat,
            other_requires: r
                .iter()
                .filter(|o| Some(o.as_str()) != parent)
                .cloned()
                .collect(),
            requires: r,
            children: Vec::new(),
        };
        if !repeat {
            let mut next = path.clone();
            next.insert(code.to_string());
            for child in dependents(code) {
                if next.contains(&child) {
                    continue;
                }
                node.children.push(make(
                    &child,
                    depth + 1,
                    Some(code),
                    &next,
                    seen,
                    reqs,
                    dependents,
                ));
            }
        }
        node
    }

    let mut seen = HashSet::new();
    let mut roots = Vec::new();
    for c in &order {
        if reqs(c).is_empty() {
            roots.push(make(
                c,
                0,
                None,
                &HashSet::new(),
                &mut seen,
                &reqs,
                &dependents,
            ));
        }
    }
    for c in &order {
        if !seen.contains(*c) {
            roots.push(make(
                c,
                0,
                None,
                &HashSet::new(),
                &mut seen,
                &reqs,
                &dependents,
            ));
        }
    }
    roots
}

/// The result of one switch: the new disabled set and which other modules moved with it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct ModuleToggle {
    pub disabled: BTreeSet<String>,
    /// Other modules whose state changed, in catalogue order.
    pub also_changed: Vec<String>,
}

/// Switches `code` on or off and keeps the server's rule true: switching off also switches off
/// every module that (transitively) requires it; switching on also switches on every module it
/// (transitively) requires.
pub(crate) fn toggle_module(
    catalogue: &[(String, Vec<String>)],
    disabled: &BTreeSet<String>,
    code: &str,
    on: bool,
) -> ModuleToggle {
    let edges = |c: &str| -> Vec<String> {
        if on {
            catalogue
                .iter()
                .find(|(k, _)| k == c)
                .map(|(_, r)| r.clone())
                .unwrap_or_default()
        } else {
            catalogue
                .iter()
                .filter(|(_, r)| r.iter().any(|x| x == c))
                .map(|(k, _)| k.clone())
                .collect()
        }
    };
    let mut affected: HashSet<String> = HashSet::new();
    let mut todo = vec![code.to_string()];
    while let Some(n) = todo.pop() {
        for e in edges(&n) {
            if affected.insert(e.clone()) {
                todo.push(e);
            }
        }
    }
    affected.remove(code);
    let mut next = disabled.clone();
    if on {
        next.remove(code);
    } else {
        next.insert(code.to_string());
    }
    let mut also = Vec::new();
    for (c, _) in catalogue {
        if !affected.contains(c) {
            continue;
        }
        let changed = if on {
            next.remove(c)
        } else {
            next.insert(c.clone())
        };
        if changed {
            also.push(c.clone());
        }
    }
    ModuleToggle {
        disabled: next,
        also_changed: also,
    }
}

/// The visible rows: a depth-first walk that skips the children of collapsed rows.
pub(crate) fn visible_rows(
    roots: &[ModuleTreeNode],
    collapsed: &HashSet<String>,
) -> Vec<ModuleRow> {
    fn walk(n: &ModuleTreeNode, collapsed: &HashSet<String>, out: &mut Vec<ModuleRow>) {
        let id = n.id();
        let is_collapsed = collapsed.contains(&id);
        out.push(ModuleRow {
            id,
            code: n.code.clone(),
            depth: n.depth,
            repeat: n.repeat,
            other_requires: n.other_requires.clone(),
            requires: n.requires.clone(),
            has_children: !n.children.is_empty(),
        });
        if is_collapsed {
            return;
        }
        for c in &n.children {
            walk(c, collapsed, out);
        }
    }
    let mut out = Vec::new();
    for r in roots {
        walk(r, collapsed, &mut out);
    }
    out
}

fn off_in(list: &[ModuleInfo]) -> BTreeSet<String> {
    list.iter()
        .filter(|m| !m.enabled)
        .map(|m| m.code.clone())
        .collect()
}

fn catalogue_of(list: &[ModuleInfo]) -> Vec<(String, Vec<String>)> {
    list.iter()
        .map(|m| (m.code.clone(), m.requires.clone()))
        .collect()
}

#[component]
pub fn ModulesSection() -> impl IntoView {
    let ctx = expect_context::<AppContext>();
    let fb = Feedback::new();

    let catalogue = RwSignal::new(Option::<Vec<(String, Vec<String>)>>::None);
    let saved = RwSignal::new(BTreeSet::<String>::new());
    let disabled = RwSignal::new(BTreeSet::<String>::new());
    let collapsed = RwSignal::new(HashSet::<String>::new());
    let saving = RwSignal::new(false);
    let reload = RwSignal::new(0_u64);
    let cascade_note = RwSignal::new(Option::<String>::None);
    // The initial load failed (shown with a Retry instead of "Loading modules...").
    let load_error = RwSignal::new(Option::<String>::None);

    Effect::new(move |_| {
        let _ = reload.get();
        load_error.set(None);
        spawn_api(
            ctx,
            |c| async move { c.list_modules().await },
            move |res| match res {
                Ok(list) => {
                    if set_alive(catalogue, Some(catalogue_of(&list))) {
                        saved.set(off_in(&list));
                        disabled.set(off_in(&list));
                    }
                }
                Err(err) => {
                    if catalogue.try_with_untracked(Option::is_some) == Some(false) {
                        set_alive(load_error, Some(err.user_message()));
                    } else {
                        fb.fail(err.user_message());
                    }
                }
            },
        );
    });

    // The tree changes with the catalogue only; collapsing just re-walks it.
    let tree = Memo::new(move |_| {
        catalogue.with(|c| c.as_deref().map(build_module_tree).unwrap_or_default())
    });
    let rows = Memo::new(move |_| tree.with(|t| collapsed.with(|col| visible_rows(t, col))));
    let changed = Memo::new(move |_| disabled.get() != saved.get());

    let toggle = move |code: String, on: bool| {
        let Some(cat) = catalogue.get_untracked() else {
            return;
        };
        let r = toggle_module(&cat, &disabled.get_untracked(), &code, on);
        disabled.set(r.disabled);
        cascade_note.set((!r.also_changed.is_empty()).then(|| {
            let names = module_names(&r.also_changed);
            if on {
                format!("Also switches on: {names}")
            } else {
                format!("Also switches off: {names}")
            }
        }));
    };

    let on_save = move |_| {
        cascade_note.set(None);
        saving.set(true);
        let body = ModulesInput {
            disabled_modules: disabled.get_untracked().into_iter().collect(),
        };
        spawn_api(
            ctx,
            move |c| async move { c.set_modules(&body).await },
            move |res| {
                if !set_alive(saving, false) {
                    return;
                }
                match res {
                    Ok(list) => {
                        catalogue.set(Some(catalogue_of(&list)));
                        saved.set(off_in(&list));
                        disabled.set(off_in(&list));
                        fb.ok("Modules saved");
                        // The server filters permissions by module, so the navigation changes.
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
        <section data-target="admin-modules" aria-labelledby="admin-modules-title">
            <div class="tc-page-header" style="margin-bottom: var(--space-sm);">
                <h2 id="admin-modules-title" class="tc-page-title" style="font-size: 18px;">"Modules"</h2>
                <button
                    type="button"
                    data-target="admin-modules-save"
                    class="tc-btn tc-btn-primary"
                    disabled=move || !changed.get() || saving.get()
                    on:click=on_save
                >
                    {move || if saving.get() { "Saving..." } else { "Save" }}
                </button>
            </div>
            <p style="color: var(--on-surface-variant);">
                "Switch off the modules this company does not use. People no longer see them and the server refuses their requests."
            </p>
            <FeedbackView fb prefix="admin-modules" />
            {move || cascade_note.get().map(|msg| view! {
                <div class="tc-alert-success" role="status" data-target="admin-modules-cascade" style="margin-bottom: var(--space-md);">{msg}</div>
            })}
            <Show
                when=move || catalogue.with(Option::is_some)
                fallback=move || match load_error.get() {
                    Some(msg) => view! {
                        <div class="tc-alert-error" role="alert" data-target="admin-modules-load-error">
                            {msg}
                            " "
                            <button type="button" class="tc-btn tc-btn-sm" data-target="admin-modules-retry" on:click=move |_| reload.update(|n| *n += 1)>
                                "Retry"
                            </button>
                        </div>
                    }.into_any(),
                    None => view! { <p class="tc-label">"Loading modules..."</p> }.into_any(),
                }
            >
                <ul data-target="admin-modules-tree" role="list" style="list-style: none; margin: 0; padding: 0;">
                    <For
                        each=move || rows.get()
                        key=|n| n.id.clone()
                        children=move |n| {
                            let id = n.id.clone();
                            let id_toggle = id.clone();
                            let id_state = id.clone();
                            let code = n.code.clone();
                            let code_on = code.clone();
                            let code_toggle = code.clone();
                            let name = module_name(&n.code).to_string();
                            let hint = if n.repeat {
                                Some(format!("Also needs {}", module_names(&n.other_requires)))
                            } else if !n.requires.is_empty() {
                                Some(format!("Needs {}", module_names(&n.requires)))
                            } else {
                                None
                            };
                            let has_children = n.has_children;
                            let on = Memo::new(move |_| disabled.with(|d| !d.contains(&code_on)));
                            let is_collapsed = Memo::new(move |_| collapsed.with(|c| c.contains(&id_state)));
                            let indent = format!(
                                "margin-left: {}px; padding: var(--space-xs) var(--space-sm); display: flex; align-items: center; gap: var(--space-sm);{}",
                                n.depth * 24,
                                if n.depth > 0 { " border-left: 2px solid var(--outline-variant, var(--outline));" } else { "" }
                            );
                            let name_expand = name.clone();
                            let hint_id = format!("admin-module-hint-{id}");
                            view! {
                                <li style=indent data-target=format!("admin-module-row-{id}") attr:aria-level=(n.depth + 1).to_string()>
                                    <span style="width: 32px; display: inline-flex;">
                                        {has_children.then(|| view! {
                                            <button
                                                type="button"
                                                class="tc-btn tc-btn-ghost tc-btn-sm"
                                                data-target=format!("admin-module-expand-{id}")
                                                aria-expanded=move || (!is_collapsed.get()).to_string()
                                                aria-label=move || if is_collapsed.get() { format!("Expand {name_expand}") } else { format!("Collapse {name_expand}") }
                                                on:click=move |_| collapsed.update(|c| {
                                                    if !c.remove(&id_toggle) {
                                                        c.insert(id_toggle.clone());
                                                    }
                                                })
                                            >
                                                {move || if is_collapsed.get() { "\u{25b8}" } else { "\u{25be}" }}
                                            </button>
                                        })}
                                    </span>
                                    <label class="tc-checkbox-row" style="flex: 1;">
                                        <input
                                            type="checkbox"
                                            role="switch"
                                            data-target=format!("admin-module-{id}")
                                            aria-describedby=hint_id.clone()
                                            prop:checked=move || on.get()
                                            disabled=move || saving.get()
                                            on:change=move |ev| toggle(code_toggle.clone(), event_target_checked(&ev))
                                        />
                                        <span>
                                            <strong>{name}</strong>
                                            <span id=hint_id class="tc-label" style="display: block;">
                                                {hint.unwrap_or_default()}
                                            </span>
                                        </span>
                                    </label>
                                    <span
                                        data-target=format!("admin-module-state-{id}")
                                        class=move || if on.get() { "tc-badge tc-badge-success" } else { "tc-badge tc-badge-error" }
                                    >
                                        {move || if on.get() { "On" } else { "Off" }}
                                    </span>
                                </li>
                            }
                        }
                    />
                </ul>
            </Show>
        </section>
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn cat(items: &[(&str, &[&str])]) -> Vec<(String, Vec<String>)> {
        items
            .iter()
            .map(|(c, r)| (c.to_string(), r.iter().map(|x| x.to_string()).collect()))
            .collect()
    }

    fn set(items: &[&str]) -> BTreeSet<String> {
        items.iter().map(|s| s.to_string()).collect()
    }

    #[test]
    fn builds_a_tree_with_repeats_for_several_requirements() {
        let c = cat(&[
            ("customers", &[]),
            ("products", &[]),
            ("sales", &["customers", "products"]),
            ("delivery", &["sales"]),
        ]);
        let roots = build_module_tree(&c);
        assert_eq!(roots.len(), 2);
        let sales = &roots[0].children[0];
        assert_eq!(sales.code, "sales");
        assert!(!sales.repeat);
        assert_eq!(sales.children[0].code, "delivery");
        let repeat = &roots[1].children[0];
        assert!(repeat.repeat);
        assert_eq!(repeat.id(), "sales-under-products");
        assert_eq!(repeat.other_requires, vec!["customers"]);
        assert!(repeat.children.is_empty());
    }

    #[test]
    fn cycles_still_list_every_module() {
        let c = cat(&[("a", &["b"]), ("b", &["a"])]);
        let roots = build_module_tree(&c);
        let codes: Vec<_> = visible_rows(&roots, &HashSet::new())
            .into_iter()
            .map(|n| n.code)
            .collect();
        assert!(codes.contains(&"a".to_string()) && codes.contains(&"b".to_string()));
    }

    #[test]
    fn switching_off_cascades_to_dependents_and_on_to_requirements() {
        let c = cat(&[
            ("customers", &[]),
            ("sales", &["customers"]),
            ("delivery", &["sales"]),
        ]);
        let off = toggle_module(&c, &set(&[]), "customers", false);
        assert_eq!(off.disabled, set(&["customers", "sales", "delivery"]));
        assert_eq!(off.also_changed, vec!["sales", "delivery"]);
        let on = toggle_module(&c, &off.disabled, "delivery", true);
        assert!(on.disabled.is_empty());
        assert_eq!(on.also_changed, vec!["customers", "sales"]);
    }

    #[test]
    fn collapsed_rows_hide_their_children() {
        let c = cat(&[("customers", &[]), ("sales", &["customers"])]);
        let roots = build_module_tree(&c);
        assert_eq!(visible_rows(&roots, &HashSet::new()).len(), 2);
        let collapsed: HashSet<String> = ["customers".to_string()].into();
        let rows = visible_rows(&roots, &collapsed);
        assert_eq!(rows.len(), 1);
        assert!(rows[0].has_children);
        assert_eq!(rows[0].id, "customers");
    }
}
