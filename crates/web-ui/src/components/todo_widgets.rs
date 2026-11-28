//! Reusable To-do navigation badge and per-record ObjectTodosButton modal widget (ADR 0061).

use leptos::ev::SubmitEvent;
use leptos::prelude::*;
use tradocraft_api_client::todo::{ListTodosParams, TodoCounts, TodoCreate, TodoItem};
use tradocraft_api_client::ApiError;
use uuid::Uuid;

use crate::components::async_ops::{set_alive, spawn_api, RequestGuard};
use crate::components::feedback::{Feedback, FeedbackView};
use crate::components::modal::{ConfirmDialog, Modal};
use crate::state::{ActiveSession, AppContext};

/// Computes the nav badge count `(open, has_overdue)` or `None` when nothing is open.
pub fn todo_badge_state(counts: Option<TodoCounts>) -> Option<(i64, bool)> {
    let c = counts?;
    if c.open > 0 {
        Some((c.open, c.overdue > 0))
    } else {
        None
    }
}

fn can_use_todo(active: &ActiveSession) -> bool {
    let module_ok = active
        .me
        .modules
        .iter()
        .find(|m| m.code == "todo")
        .is_none_or(|m| m.enabled);
    module_ok && active.me.has_permission("todo.use")
}

fn todo_error_code(err: &ApiError) -> Option<&str> {
    match err {
        ApiError::Http { body, .. } => body.as_ref().and_then(|b| b.code.as_deref()),
        _ => None,
    }
}

/// Watches the active session and `ctx.todo_counts_nonce`, refreshing live To-do badge counts.
pub fn setup_todo_counts_probe(ctx: AppContext) {
    let guard = RequestGuard::new();
    Effect::new(move |_| {
        let _ = ctx.todo_counts_nonce.get();
        let allowed = ctx.session.with(|s| s.as_ref().is_some_and(can_use_todo));
        if !allowed {
            let _ = guard.bump();
            ctx.todo_counts.set(None);
            return;
        }
        let gen = guard.bump();
        spawn_api(
            ctx,
            |client| async move { client.todo_counts().await },
            move |res| {
                if !guard.is_current(gen) {
                    return;
                }
                if let Ok(counts) = res {
                    ctx.todo_counts.set(Some(counts));
                }
            },
        );
    });
}

/// Header button + modal showing and creating the caller's open To-dos linked to a record.
#[component]
pub fn ObjectTodosButton(
    kind: &'static str,
    id: Uuid,
    #[prop(into)] label: Signal<String>,
    #[prop(into)] location: String,
) -> impl IntoView {
    let ctx = expect_context::<AppContext>();
    let allowed = Memo::new(move |_| ctx.session.with(|s| s.as_ref().is_some_and(can_use_todo)));

    let open = RwSignal::new(false);
    let items = RwSignal::new(Vec::<TodoItem>::new());
    let loading = RwSignal::new(false);
    let fb = Feedback::new();
    let draft_title = RwSignal::new(String::new());
    let guard = RequestGuard::new();
    let reload = RwSignal::new(0_u64);
    let location_sv = StoredValue::new(location);

    Effect::new(move |_| {
        let _ = reload.get();
        if !allowed.get() {
            let _ = guard.bump();
            items.set(Vec::new());
            return;
        }
        let gen = guard.bump();
        loading.set(true);
        let params = ListTodosParams {
            done: Some(false),
            link_kind: Some(kind.to_string()),
            link_id: Some(id),
            ..ListTodosParams::default()
        };
        spawn_api(
            ctx,
            move |client| async move { client.list_todos(&params).await },
            move |res| {
                if !guard.is_current(gen) {
                    return;
                }
                let _ = set_alive(loading, false);
                match res {
                    Ok(list) => {
                        let _ = set_alive(items, list);
                    }
                    Err(err) => {
                        fb.fail(err.user_message());
                    }
                }
            },
        );
    });

    let on_add = move |ev: SubmitEvent| {
        ev.prevent_default();
        let title = draft_title.get_untracked().trim().to_string();
        if title.is_empty() {
            return;
        }
        let link_label = label.get_untracked();
        let req = TodoCreate {
            client_id: Some(Uuid::new_v4()),
            title: title.clone(),
            link_kind: Some(kind.to_string()),
            link_id: Some(id),
            link_label: (!link_label.trim().is_empty()).then_some(link_label),
            link_location: Some(location_sv.get_value()),
            ..TodoCreate::default()
        };
        spawn_api(
            ctx,
            move |client| async move { client.create_todo(&req).await },
            move |res| match res {
                Ok(_) => {
                    if draft_title.try_get_untracked().as_deref() == Some(title.as_str()) {
                        let _ = set_alive(draft_title, String::new());
                    }
                    let _ = reload.try_update(|n| *n = n.wrapping_add(1));
                    ctx.bump_todo_counts();
                    fb.clear();
                }
                Err(err) => {
                    fb.fail(err.user_message());
                }
            },
        );
    };

    // The item whose open sub-items the person has to confirm completing (the server refuses
    // with `open_sub_items` first; the sub-items are never completed without asking).
    let confirm_all = RwSignal::new(Option::<Uuid>::None);

    let complete_item = move |todo_id: Uuid, complete_children: bool| {
        spawn_api(
            ctx,
            move |client| async move { client.complete_todo(todo_id, complete_children).await },
            move |res| match res {
                Ok(_) => {
                    let _ = set_alive(confirm_all, None);
                    let _ = reload.try_update(|n| *n = n.wrapping_add(1));
                    ctx.bump_todo_counts();
                    fb.clear();
                }
                Err(err) if todo_error_code(&err) == Some("open_sub_items") => {
                    let _ = set_alive(confirm_all, Some(todo_id));
                }
                Err(err) => {
                    let _ = set_alive(confirm_all, None);
                    fb.fail(err.user_message());
                }
            },
        );
    };

    let modal_title = Signal::derive(move || format!("To-dos · {}", label.get()));

    view! {
        <Show when=move || allowed.get()>
            <button
                type="button"
                class="tc-btn tc-btn-sm"
                data-target="object-todos-button"
                on:click=move |_| open.set(true)
            >
                <span>"To-dos"</span>
                {move || {
                    let count = items.with(Vec::len);
                    (count > 0).then(|| view! {
                        <span class="tc-badge tc-badge-primary" data-target="object-todos-badge">
                            {count}
                        </span>
                    })
                }}
            </button>

            <Modal
                open=open
                title=modal_title
                on_close=Callback::new(move |()| open.set(false))
                target="object-todos-modal"
            >
                <FeedbackView fb prefix="object-todos" />
                <form class="tc-toolbar" data-target="object-todos-add-form" on:submit=on_add>
                    <input
                        type="text"
                        class="tc-input"
                        style="flex: 1;"
                        placeholder="Add task linked to this record…"
                        data-target="object-todos-add-input"
                        prop:value=move || draft_title.get()
                        on:input=move |ev| draft_title.set(event_target_value(&ev))
                    />
                    <button
                        type="submit"
                        class="tc-btn tc-btn-primary tc-btn-sm"
                        data-target="object-todos-add-submit"
                    >
                        "Add"
                    </button>
                </form>

                {move || {
                    let list = items.get();
                    if loading.get() && list.is_empty() {
                        return view! {
                            <p style="margin: 0; color: var(--on-surface-variant);">"Loading…"</p>
                        }
                        .into_any();
                    }
                    if list.is_empty() {
                        return view! {
                            <p style="margin: 0; color: var(--on-surface-variant);" data-target="object-todos-empty">
                                "No open to-do items for this record."
                            </p>
                        }
                        .into_any();
                    }
                    view! {
                        <ul class="tc-home-list" data-target="object-todos-list">
                            {list
                                .into_iter()
                                .map(|item| {
                                    let tid = item.id;
                                    view! {
                                        <li class="tc-home-list-item" data-target=format!("object-todo-item-{tid}")>
                                            <span>{item.title}</span>
                                            <button
                                                type="button"
                                                class="tc-btn tc-btn-sm"
                                                data-target=format!("object-todo-done-{tid}")
                                                on:click=move |_| complete_item(tid, false)
                                            >
                                                "Done"
                                            </button>
                                        </li>
                                    }
                                })
                                .collect_view()}
                        </ul>
                    }
                    .into_any()
                }}
            </Modal>

            <ConfirmDialog
                open=Signal::derive(move || confirm_all.get().is_some())
                title="Complete open sub-items?"
                message="This task still has open sub-items. Complete them all?"
                confirm_label="Complete all"
                target="object-todos-complete-all"
                on_confirm=Callback::new(move |()| {
                    if let Some(id) = confirm_all.get_untracked() {
                        complete_item(id, true);
                    }
                })
                on_cancel=Callback::new(move |()| confirm_all.set(None))
            />
        </Show>
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn todo_badge_hides_at_zero_and_marks_overdue() {
        assert_eq!(todo_badge_state(None), None);
        assert_eq!(
            todo_badge_state(Some(TodoCounts {
                open: 0,
                overdue: 0,
                due_today: 0,
            })),
            None
        );
        assert_eq!(
            todo_badge_state(Some(TodoCounts {
                open: 3,
                overdue: 0,
                due_today: 1,
            })),
            Some((3, false))
        );
        assert_eq!(
            todo_badge_state(Some(TodoCounts {
                open: 3,
                overdue: 1,
                due_today: 0,
            })),
            Some((3, true))
        );
    }
}
