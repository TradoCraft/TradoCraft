//! To-do page (ADR 0061): the caller's own checklist, two levels deep (items and sub-items), with
//! due dates and an Open / Done / All filter. Mirrors `app/lib/features/todo/todo_page.dart`.

use std::future::Future;

use chrono::NaiveDate;
use leptos::ev::SubmitEvent;
use leptos::prelude::*;
use leptos::task::spawn_local;
use leptos_router::components::A;
use tradocraft_api_client::todo::{ListTodosParams, TodoCreate, TodoItem, TodoPatch};
use tradocraft_api_client::{ApiError, Client};
use uuid::Uuid;

use crate::components::async_ops::live_client;
use crate::pages::{opt_trimmed, set_alive};
use crate::state::AppContext;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum TodoFilter {
    Open,
    Done,
    All,
}

impl TodoFilter {
    fn key(self) -> &'static str {
        match self {
            Self::Open => "open",
            Self::Done => "done",
            Self::All => "all",
        }
    }

    fn label(self) -> &'static str {
        match self {
            Self::Open => "Open",
            Self::Done => "Done",
            Self::All => "All",
        }
    }

    fn done_param(self) -> Option<bool> {
        match self {
            Self::Open => Some(false),
            Self::Done => Some(true),
            Self::All => None,
        }
    }
}

/// A pending inline confirmation.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Confirm {
    /// Complete an item together with its open sub-items.
    CompleteAll(Uuid),
    Delete(Uuid),
}

/// A root item with the sub-items the list holds for it.
#[derive(Debug, Clone, PartialEq, Eq)]
struct TodoNode {
    item: TodoItem,
    children: Vec<TodoItem>,
}

impl TodoNode {
    fn has_open_children(&self) -> bool {
        self.children.iter().any(|c| !c.done)
    }

    /// Changes whenever the node must be redrawn.
    fn key(&self) -> String {
        let mut key = format!("{}:{}", self.item.id, self.item.updated_at);
        for child in &self.children {
            key.push_str(&format!("|{}:{}", child.id, child.updated_at));
        }
        key
    }
}

/// Builds the tree from the flat list (ordered by parent, then position). An item whose parent is
/// not in the list (a finished sub-item of an open parent under the "Done" filter) is shown as a
/// root.
fn build_tree(items: &[TodoItem]) -> Vec<TodoNode> {
    let ids: Vec<Uuid> = items.iter().map(|i| i.id).collect();
    let mut roots: Vec<TodoNode> = Vec::new();
    for item in items {
        let parent_listed = item.parent_id.is_some_and(|p| ids.contains(&p));
        if !parent_listed {
            roots.push(TodoNode {
                item: item.clone(),
                children: Vec::new(),
            });
        }
    }
    for item in items {
        if let Some(parent) = item.parent_id {
            if let Some(node) = roots.iter_mut().find(|n| n.item.id == parent) {
                node.children.push(item.clone());
            }
        }
    }
    roots
}

fn parse_due(raw: &str) -> Result<Option<NaiveDate>, String> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return Ok(None);
    }
    NaiveDate::parse_from_str(trimmed, "%Y-%m-%d")
        .map(Some)
        .map_err(|_| "Due date must be a valid date.".to_string())
}

#[cfg(target_arch = "wasm32")]
fn today() -> Option<NaiveDate> {
    let now = js_sys::Date::new_0();
    NaiveDate::from_ymd_opt(
        now.get_full_year() as i32,
        now.get_month() + 1,
        now.get_date(),
    )
}

#[cfg(not(target_arch = "wasm32"))]
fn today() -> Option<NaiveDate> {
    None
}

fn is_overdue(item: &TodoItem, today: Option<NaiveDate>) -> bool {
    match (item.due_date, today) {
        (Some(due), Some(today)) => !item.done && due < today,
        _ => false,
    }
}

fn error_code(err: &ApiError) -> Option<&str> {
    match err {
        ApiError::Http { body, .. } => body.as_ref().and_then(|b| b.code.as_deref()),
        _ => None,
    }
}

/// The signals and actions every row shares. All fields are `Copy`.
#[derive(Clone, Copy)]
struct TodoUi {
    ctx: AppContext,
    error: RwSignal<Option<String>>,
    reload: RwSignal<u64>,
    editing: RwSignal<Option<Uuid>>,
    edit_title: RwSignal<String>,
    edit_notes: RwSignal<String>,
    edit_due: RwSignal<String>,
    child_parent: RwSignal<Option<Uuid>>,
    child_title: RwSignal<String>,
    child_due: RwSignal<String>,
    confirm: RwSignal<Option<Confirm>>,
}

impl TodoUi {
    /// Runs `f` against the live API, shows a failure, and reloads the list either way.
    fn run<F, Fut>(self, f: F)
    where
        F: FnOnce(Client) -> Fut + 'static,
        Fut: Future<Output = Result<(), ApiError>> + 'static,
    {
        self.run_then(f, || {});
    }

    /// Like [`Self::run`], and calls `on_ok` once the request succeeded (not on failure).
    fn run_then<F, Fut, G>(self, f: F, on_ok: G)
    where
        F: FnOnce(Client) -> Fut + 'static,
        Fut: Future<Output = Result<(), ApiError>> + 'static,
        G: FnOnce() + 'static,
    {
        let Some(session) = self.ctx.session.get_untracked() else {
            return;
        };
        spawn_local(async move {
            let res = match live_client(&session.connection) {
                Ok(client) => f(client).await,
                Err(err) => Err(err),
            };
            // The page may have been left while the request was running.
            let alive = match res {
                Ok(()) => {
                    let alive = set_alive(self.error, None);
                    if alive {
                        on_ok();
                    }
                    alive
                }
                Err(err) => set_alive(self.error, Some(err.user_message())),
            };
            if alive {
                self.reload.try_update(|n| *n += 1);
            }
        });
    }

    /// Validates and sends a create request. `on_ok` runs only after the API accepted it, so a
    /// failed request leaves the draft in place.
    fn create(
        self,
        parent_id: Option<Uuid>,
        title: &str,
        due: &str,
        on_ok: impl FnOnce() + 'static,
    ) {
        let Some(title) = opt_trimmed(title) else {
            self.error.set(Some("Title is required.".to_string()));
            return;
        };
        let due_date = match parse_due(due) {
            Ok(d) => d,
            Err(msg) => {
                self.error.set(Some(msg));
                return;
            }
        };
        let req = TodoCreate {
            client_id: Some(Uuid::new_v4()),
            parent_id,
            title,
            due_date,
            ..TodoCreate::default()
        };
        self.run_then(
            move |c| async move { c.create_todo(&req).await.map(|_| ()) },
            on_ok,
        );
    }

    fn toggle(self, item: &TodoItem, has_open_children: bool) {
        let id = item.id;
        if item.done {
            self.run(move |c| async move { c.reopen_todo(id).await.map(|_| ()) });
        } else if has_open_children {
            self.confirm.set(Some(Confirm::CompleteAll(id)));
        } else {
            self.complete(id, false);
        }
    }

    /// Completes an item. Sub-items the list does not show are still open on the server: the
    /// server then refuses with `open_sub_items` and the person is asked.
    fn complete(self, id: Uuid, complete_children: bool) {
        let Some(session) = self.ctx.session.get_untracked() else {
            return;
        };
        spawn_local(async move {
            let res = match live_client(&session.connection) {
                Ok(client) => client.complete_todo(id, complete_children).await,
                Err(err) => Err(err),
            };
            let alive = match res {
                Ok(_) => set_alive(self.error, None),
                Err(err) if error_code(&err) == Some("open_sub_items") => {
                    set_alive(self.confirm, Some(Confirm::CompleteAll(id)))
                }
                Err(err) => set_alive(self.error, Some(err.user_message())),
            };
            if alive {
                self.reload.try_update(|n| *n += 1);
            }
        });
    }

    fn start_edit(self, item: &TodoItem) {
        self.edit_title.set(item.title.clone());
        self.edit_notes.set(item.notes.clone());
        self.edit_due
            .set(item.due_date.map(|d| d.to_string()).unwrap_or_default());
        self.editing.set(Some(item.id));
    }

    fn save_edit(self, id: Uuid) {
        let Some(title) = opt_trimmed(&self.edit_title.get_untracked()) else {
            self.error.set(Some("Title is required.".to_string()));
            return;
        };
        let due = match parse_due(&self.edit_due.get_untracked()) {
            Ok(d) => d,
            Err(msg) => {
                self.error.set(Some(msg));
                return;
            }
        };
        let patch = TodoPatch {
            title: Some(title),
            notes: Some(self.edit_notes.get_untracked().trim().to_string()),
            due_date: due,
            clear_due_date: due.is_none(),
        };
        let editing = self.editing;
        self.run_then(
            move |c| async move { c.update_todo(id, &patch).await.map(|_| ()) },
            move || {
                if editing.get_untracked() == Some(id) {
                    editing.set(None);
                }
            },
        );
    }
}

#[component]
pub fn TodoPage() -> impl IntoView {
    let ctx = expect_context::<AppContext>();

    let filter = RwSignal::new(TodoFilter::Open);
    let items = RwSignal::new(Vec::<TodoItem>::new());
    // The filter the rows in `items` were loaded for.
    let shown_filter = RwSignal::new(TodoFilter::Open);
    let today_sig = RwSignal::new(today());
    let loading = RwSignal::new(false);
    let error = RwSignal::new(Option::<String>::None);
    let reload = RwSignal::new(0_u64);
    let fetch_generation = StoredValue::new(0_u64);

    let new_title = RwSignal::new(String::new());
    let new_due = RwSignal::new(String::new());

    let ui = TodoUi {
        ctx,
        error,
        reload,
        editing: RwSignal::new(None),
        edit_title: RwSignal::new(String::new()),
        edit_notes: RwSignal::new(String::new()),
        edit_due: RwSignal::new(String::new()),
        child_parent: RwSignal::new(None),
        child_title: RwSignal::new(String::new()),
        child_due: RwSignal::new(String::new()),
        confirm: RwSignal::new(None),
    };

    Effect::new(move |_| {
        let _ = reload.get();
        let current = filter.get();
        let session = ctx.session.get();
        today_sig.set(today());

        let req_gen = fetch_generation
            .try_update_value(|g| {
                *g += 1;
                *g
            })
            .unwrap_or(0);

        let Some(session) = session else {
            loading.set(false);
            items.set(Vec::new());
            return;
        };

        loading.set(true);
        spawn_local(async move {
            let params = ListTodosParams {
                scope: None,
                done: current.done_param(),
            };
            let res = match live_client(&session.connection) {
                Ok(client) => client.list_todos(&params).await,
                Err(err) => Err(err),
            };
            if fetch_generation.try_get_value() != Some(req_gen) {
                return;
            }
            if !set_alive(loading, false) {
                return;
            }
            match res {
                Ok(list) => {
                    items.set(list);
                    shown_filter.set(current);
                }
                Err(err) => {
                    // Rows of another filter must not stay on screen under this filter's tab.
                    if shown_filter.get_untracked() != current {
                        items.set(Vec::new());
                    }
                    error.set(Some(err.user_message()));
                }
            }
        });
    });

    let is_signed_in = Memo::new(move |_| ctx.session.with(|s| s.is_some()));
    let tree = Memo::new(move |_| items.with(|list| build_tree(list)));

    let on_add = move |ev: SubmitEvent| {
        ev.prevent_default();
        let (title, due) = (new_title.get_untracked(), new_due.get_untracked());
        let (sent_title, sent_due) = (title.clone(), due.clone());
        ui.create(None, &title, &due, move || {
            // Keep anything typed while the request was pending.
            if new_title.get_untracked() == sent_title {
                new_title.set(String::new());
            }
            if new_due.get_untracked() == sent_due {
                new_due.set(String::new());
            }
        });
    };

    view! {
        <div data-target="todo-page">
            <div class="tc-page-header">
                <div>
                    <h1 class="tc-page-title">"To-do"</h1>
                    <p class="tc-page-subtitle" data-target="todo-total">
                        {move || format!("{} items", tree.with(Vec::len))}
                    </p>
                </div>
                <div class="tc-header-actions">
                    <div class="tc-inline-tabs" data-target="todo-filter" role="group" aria-label="Filter">
                        {[TodoFilter::Open, TodoFilter::Done, TodoFilter::All]
                            .into_iter()
                            .map(|f| view! {
                                <button
                                    type="button"
                                    data-target=format!("todo-filter-{}", f.key())
                                    class=move || if filter.get() == f {
                                        "tc-inline-tab-btn tc-inline-tab-active"
                                    } else {
                                        "tc-inline-tab-btn"
                                    }
                                    aria-pressed=move || (filter.get() == f).to_string()
                                    on:click=move |_| filter.set(f)
                                >
                                    {f.label()}
                                </button>
                            })
                            .collect_view()}
                    </div>
                    <button
                        type="button"
                        data-target="todo-refresh"
                        class="tc-btn"
                        disabled=move || loading.get() || !is_signed_in.get()
                        on:click=move |_| reload.update(|n| *n += 1)
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
                            "Sign in to load your to-dos from GET /api/v1/todo/items."
                        </p>
                        <A href=crate::components::shell::app_href("/login") attr:class="tc-btn tc-btn-primary" attr:data-target="todo-go-login">
                            "Go to sign in"
                        </A>
                    </div>
                }
            >
                <form class="tc-toolbar" data-target="todo-add-form" on:submit=on_add>
                    <input
                        data-target="todo-add-title"
                        class="tc-input"
                        style="min-width: 280px;"
                        type="text"
                        placeholder="Add a task..."
                        prop:value=move || new_title.get()
                        on:input=move |ev| new_title.set(event_target_value(&ev))
                    />
                    <input
                        data-target="todo-add-due"
                        class="tc-input"
                        type="date"
                        aria-label="Due date"
                        prop:value=move || new_due.get()
                        on:input=move |ev| new_due.set(event_target_value(&ev))
                    />
                    <button type="submit" data-target="todo-add-submit" class="tc-btn tc-btn-primary">
                        "Add task"
                    </button>
                </form>

                {move || error.get().map(|msg| view! {
                    <div class="tc-alert-error" style="margin-bottom: var(--space-md);" role="alert" data-target="todo-error">
                        {msg}
                    </div>
                })}

                <Show
                    when=move || !tree.with(Vec::is_empty)
                    fallback=move || view! {
                        <p data-target="todo-empty" style="color: var(--on-surface-variant); padding: var(--space-xl) 0;">
                            {move || if loading.get() {
                                "Loading to-dos..."
                            } else if filter.get() == TodoFilter::Done {
                                "Nothing finished yet."
                            } else {
                                "Nothing to do. Add a task above."
                            }}
                        </p>
                    }
                >
                    <ul data-target="todo-list" style="list-style: none; margin: 0; padding: 0;">
                        <For
                            each=move || {
                                // Re-evaluated when the date changes, so overdue badges follow it.
                                let _ = today_sig.get();
                                tree.get()
                            }
                            key=move |node| format!("{}|{}", node.key(), today_sig.get_untracked().map(|d| d.to_string()).unwrap_or_default())
                            children=move |node| {
                                let open_children = node.has_open_children();
                                let children = node.children.clone();
                                let node_target = format!("todo-node-{}", node.item.id);
                                view! {
                                    <li class="tc-card" style="margin-bottom: var(--space-sm);" data-target=node_target>
                                        <ItemRow ui item=node.item.clone() open_children child=false today=today_sig.get_untracked() />
                                        <ul style="list-style: none; margin: 0 0 0 var(--space-xl); padding: 0;">
                                            {children
                                                .into_iter()
                                                .map(|child| {
                                                    let node_target = format!("todo-node-{}", child.id);
                                                    view! {
                                                        <li data-target=node_target>
                                                            <ItemRow ui item=child open_children=false child=true today=today_sig.get_untracked() />
                                                        </li>
                                                    }
                                                })
                                                .collect_view()}
                                        </ul>
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

#[component]
fn ItemRow(
    ui: TodoUi,
    item: TodoItem,
    open_children: bool,
    child: bool,
    today: Option<NaiveDate>,
) -> impl IntoView {
    let id = item.id;
    let done = item.done;
    let overdue = is_overdue(&item, today);
    let is_root = item.parent_id.is_none();
    let owner_can_delete = item.mine;
    let title = item.title.clone();
    let notes = item.notes.clone();
    let due_label = item.due_date.map(|d| d.to_string());
    let assignee = item.assignee_name.clone();
    let toggle_item = item.clone();
    let edit_item = item.clone();

    let editing_this = move || ui.editing.get() == Some(id);
    let adding_child = move || ui.child_parent.get() == Some(id);
    let confirm_this = move || {
        ui.confirm.get().filter(|c| match c {
            Confirm::CompleteAll(i) | Confirm::Delete(i) => *i == id,
        })
    };

    let on_save = move |ev: SubmitEvent| {
        ev.prevent_default();
        ui.save_edit(id);
    };
    let on_add_child = move |ev: SubmitEvent| {
        ev.prevent_default();
        let (title, due) = (ui.child_title.get_untracked(), ui.child_due.get_untracked());
        let sent_title = title.clone();
        ui.create(Some(id), &title, &due, move || {
            // Close the form only if it still holds what was sent.
            if ui.child_parent.get_untracked() == Some(id)
                && ui.child_title.get_untracked() == sent_title
            {
                ui.child_title.set(String::new());
                ui.child_due.set(String::new());
                ui.child_parent.set(None);
            }
        });
    };
    // A checkbox flips in the browser before the request is known to succeed. Put it back to the
    // server's state; on success the row is rebuilt with the new state.
    let checkbox = NodeRef::<leptos::html::Input>::new();

    view! {
        <div data-target=format!("todo-item-{id}") style="padding: var(--space-xs) 0;">
            <div style="display: flex; align-items: center; gap: var(--space-sm); flex-wrap: wrap;">
                <input
                    type="checkbox"
                    node_ref=checkbox
                    data-target=format!("todo-toggle-{id}")
                    aria-label=if done { "Reopen task" } else { "Complete task" }
                    prop:checked=done
                    on:change=move |_| {
                        if let Some(el) = checkbox.get_untracked() {
                            el.set_checked(done);
                        }
                        ui.toggle(&toggle_item, open_children)
                    }
                />
                <span
                    data-target=format!("todo-title-{id}")
                    style=if done {
                        "flex: 1; text-decoration: line-through; color: var(--on-surface-variant);"
                    } else {
                        "flex: 1;"
                    }
                >
                    {title}
                </span>
                {due_label.map(|due| view! {
                    <span
                        data-target=format!("todo-due-{id}")
                        class=if overdue { "tc-badge tc-badge-error" } else { "tc-badge" }
                    >
                        {due}
                    </span>
                })}
                {assignee.map(|name| view! { <span class="tc-badge">{name}</span> })}
                {(!is_root && !child).then(|| view! { <span class="tc-badge">"Sub-item"</span> })}
                <button
                    type="button"
                    data-target=format!("todo-edit-{id}")
                    class="tc-btn tc-btn-sm"
                    on:click=move |_| ui.start_edit(&edit_item)
                >
                    "Edit"
                </button>
                {(is_root && !done).then(|| view! {
                    <button
                        type="button"
                        data-target=format!("todo-add-child-{id}")
                        class="tc-btn tc-btn-sm"
                        on:click=move |_| {
                            ui.child_title.set(String::new());
                            ui.child_due.set(String::new());
                            ui.child_parent.set(Some(id));
                        }
                    >
                        "+ Sub-item"
                    </button>
                })}
                {owner_can_delete.then(|| view! {
                    <button
                        type="button"
                        data-target=format!("todo-delete-{id}")
                        class="tc-btn tc-btn-sm"
                        on:click=move |_| ui.confirm.set(Some(Confirm::Delete(id)))
                    >
                        "Delete"
                    </button>
                })}
            </div>

            {(!notes.is_empty()).then(|| view! {
                <p style="margin: var(--space-xs) 0 0 28px; color: var(--on-surface-variant); font-size: 13px; white-space: pre-wrap;">
                    {notes}
                </p>
            })}

            <Show when=editing_this>
                <form class="tc-toolbar" data-target=format!("todo-edit-form-{id}") on:submit=on_save style="margin-top: var(--space-sm);">
                    <input
                        data-target=format!("todo-edit-title-{id}")
                        class="tc-input"
                        style="min-width: 240px;"
                        type="text"
                        aria-label="Title"
                        prop:value=move || ui.edit_title.get()
                        on:input=move |ev| ui.edit_title.set(event_target_value(&ev))
                    />
                    <input
                        data-target=format!("todo-edit-due-{id}")
                        class="tc-input"
                        type="date"
                        aria-label="Due date"
                        prop:value=move || ui.edit_due.get()
                        on:input=move |ev| ui.edit_due.set(event_target_value(&ev))
                    />
                    <input
                        data-target=format!("todo-edit-notes-{id}")
                        class="tc-input"
                        style="min-width: 240px;"
                        type="text"
                        placeholder="Notes"
                        aria-label="Notes"
                        prop:value=move || ui.edit_notes.get()
                        on:input=move |ev| ui.edit_notes.set(event_target_value(&ev))
                    />
                    <button type="submit" data-target=format!("todo-edit-save-{id}") class="tc-btn tc-btn-primary tc-btn-sm">
                        "Save"
                    </button>
                    <button
                        type="button"
                        data-target=format!("todo-edit-cancel-{id}")
                        class="tc-btn tc-btn-sm"
                        on:click=move |_| ui.editing.set(None)
                    >
                        "Cancel"
                    </button>
                </form>
            </Show>

            <Show when=adding_child>
                <form class="tc-toolbar" data-target=format!("todo-child-form-{id}") on:submit=on_add_child style="margin-top: var(--space-sm);">
                    <input
                        data-target=format!("todo-child-title-{id}")
                        class="tc-input"
                        style="min-width: 240px;"
                        type="text"
                        placeholder="Add a sub-item..."
                        prop:value=move || ui.child_title.get()
                        on:input=move |ev| ui.child_title.set(event_target_value(&ev))
                    />
                    <input
                        data-target=format!("todo-child-due-{id}")
                        class="tc-input"
                        type="date"
                        aria-label="Due date"
                        prop:value=move || ui.child_due.get()
                        on:input=move |ev| ui.child_due.set(event_target_value(&ev))
                    />
                    <button type="submit" data-target=format!("todo-child-submit-{id}") class="tc-btn tc-btn-primary tc-btn-sm">
                        "Add"
                    </button>
                    <button
                        type="button"
                        class="tc-btn tc-btn-sm"
                        on:click=move |_| ui.child_parent.set(None)
                    >
                        "Cancel"
                    </button>
                </form>
            </Show>

            {move || confirm_this().map(|c| match c {
                Confirm::CompleteAll(_) => view! {
                    <div class="tc-toolbar" data-target=format!("todo-confirm-{id}") role="alert" style="margin-top: var(--space-sm);">
                        <span>"This task still has open sub-items. Complete them all?"</span>
                        <button
                            type="button"
                            data-target=format!("todo-complete-all-{id}")
                            class="tc-btn tc-btn-primary tc-btn-sm"
                            on:click=move |_| {
                                ui.confirm.set(None);
                                ui.complete(id, true);
                            }
                        >
                            "Complete all"
                        </button>
                        <button type="button" class="tc-btn tc-btn-sm" on:click=move |_| ui.confirm.set(None)>
                            "Cancel"
                        </button>
                    </div>
                }.into_any(),
                Confirm::Delete(_) => view! {
                    <div class="tc-toolbar" data-target=format!("todo-confirm-{id}") role="alert" style="margin-top: var(--space-sm);">
                        <span>"Delete this task and its sub-items?"</span>
                        <button
                            type="button"
                            data-target=format!("todo-confirm-delete-{id}")
                            class="tc-btn tc-btn-primary tc-btn-sm"
                            on:click=move |_| {
                                ui.confirm.set(None);
                                ui.run(move |c| async move { c.delete_todo(id).await });
                            }
                        >
                            "Delete"
                        </button>
                        <button type="button" class="tc-btn tc-btn-sm" on:click=move |_| ui.confirm.set(None)>
                            "Cancel"
                        </button>
                    </div>
                }.into_any(),
            })}
        </div>
    }
}

#[cfg(test)]
mod tests {
    use chrono::{TimeZone, Utc};

    use super::*;

    fn item(id: u128, parent: Option<u128>, done: bool, due: Option<&str>) -> TodoItem {
        let stamp = Utc.with_ymd_and_hms(2026, 11, 26, 10, 0, 0).unwrap();
        TodoItem {
            id: Uuid::from_u128(id),
            parent_id: parent.map(Uuid::from_u128),
            position: 0,
            title: format!("item {id}"),
            notes: String::new(),
            owner_id: Uuid::from_u128(99),
            owner_name: "Admin".into(),
            assignee_id: None,
            assignee_name: None,
            created_by: Uuid::from_u128(99),
            mine: true,
            due_date: due.map(|d| d.parse().unwrap()),
            done,
            done_at: None,
            done_by: None,
            link_kind: None,
            link_id: None,
            link_label: None,
            link_location: None,
            client_id: None,
            created_at: stamp,
            updated_at: stamp,
        }
    }

    #[test]
    fn groups_sub_items_under_their_parent() {
        let tree = build_tree(&[
            item(1, None, false, None),
            item(2, None, false, None),
            item(3, Some(1), false, None),
            item(4, Some(1), true, None),
        ]);
        assert_eq!(tree.len(), 2);
        assert_eq!(tree[0].children.len(), 2);
        assert!(tree[0].has_open_children());
        assert!(tree[1].children.is_empty());
    }

    #[test]
    fn sub_item_without_listed_parent_is_a_root() {
        let tree = build_tree(&[item(4, Some(1), true, None)]);
        assert_eq!(tree.len(), 1);
        assert_eq!(tree[0].item.id, Uuid::from_u128(4));
    }

    #[test]
    fn filter_maps_to_done_parameter() {
        assert_eq!(TodoFilter::Open.done_param(), Some(false));
        assert_eq!(TodoFilter::Done.done_param(), Some(true));
        assert_eq!(TodoFilter::All.done_param(), None);
    }

    #[test]
    fn parses_due_dates() {
        assert_eq!(parse_due("  "), Ok(None));
        assert_eq!(
            parse_due("2026-12-01"),
            Ok(NaiveDate::from_ymd_opt(2026, 12, 1))
        );
        assert!(parse_due("01/12/2026").is_err());
    }

    #[test]
    fn overdue_needs_an_open_item_due_before_today() {
        let today = NaiveDate::from_ymd_opt(2026, 11, 26);
        assert!(is_overdue(&item(1, None, false, Some("2026-11-25")), today));
        assert!(!is_overdue(
            &item(1, None, false, Some("2026-11-26")),
            today
        ));
        assert!(!is_overdue(&item(1, None, true, Some("2026-11-25")), today));
        assert!(!is_overdue(&item(1, None, false, None), today));
    }
}
