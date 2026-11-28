//! Record chatter side panel, topbar Inbox button & drawer (ADR 0086).

use chrono::{DateTime, Datelike, NaiveDate, Timelike, Utc};
use leptos::ev::SubmitEvent;
use leptos::prelude::*;
use leptos_router::hooks::use_navigate;
use leptos_router::NavigateOptions;
use tradocraft_api_client::chatter::{
    Activity, ActivityDoneInput, ActivityInput, ActivityKind, ChatterNoteEdit, ChatterNoteInput,
    Followers, Inbox, ListThreadParams, RecordKind, ThreadItem,
};
use tradocraft_api_client::FileInfo;
use uuid::Uuid;

use crate::components::async_ops::{set_alive, spawn_api, RequestGuard};
use crate::components::feedback::{Feedback, FeedbackView};
use crate::components::files::{begin_file_read, format_file_size, save_file};
use crate::components::modal::Modal;
use crate::i18n::tr;
use crate::state::AppContext;

const MAX_CHATTER_FILE_BYTES: usize = 10 * 1024 * 1024;

/// Computes `(total_items, has_overdue)` for the topbar inbox badge.
pub fn inbox_badge_count(inbox: Option<&Inbox>) -> (usize, bool) {
    let Some(inbox) = inbox else {
        return (0, false);
    };
    let count = inbox.activities.len() + inbox.unread.len();
    let overdue = inbox.activities.iter().any(|a| a.overdue);
    (count, overdue)
}

/// Formats a UTC timestamp using `chrono` without locale features (`YYYY-MM-DD HH:MM UTC`).
pub fn format_timestamp(dt: DateTime<Utc>) -> String {
    format!(
        "{:04}-{:02}-{:02} {:02}:{:02}",
        dt.year(),
        dt.month(),
        dt.day(),
        dt.hour(),
        dt.minute()
    )
}

/// Formats one entry from a system change message `[{"field", "from", "to"}]`.
pub fn format_change_entry(v: &serde_json::Value) -> Option<String> {
    let field = v.get("field").and_then(|f| f.as_str())?;
    let from = value_brief(v.get("from"));
    let to = value_brief(v.get("to"));
    match (from.as_deref(), to.as_deref()) {
        (Some(f), Some(t)) => Some(format!("{field}: {f} -> {t}")),
        (None, Some(t)) => Some(format!("{field}: -> {t}")),
        (Some(f), None) => Some(format!("{field}: {f} -> (cleared)")),
        (None, None) => Some(field.to_string()),
    }
}

fn value_brief(v: Option<&serde_json::Value>) -> Option<String> {
    let val = v?;
    match val {
        serde_json::Value::Null => None,
        serde_json::Value::String(s) if s.is_empty() => None,
        serde_json::Value::String(s) => Some(s.clone()),
        other => Some(other.to_string()),
    }
}

#[cfg(target_arch = "wasm32")]
fn default_due_date_str() -> String {
    let d = js_sys::Date::new_0();
    format!(
        "{:04}-{:02}-{:02}",
        d.get_full_year(),
        d.get_month() + 1,
        d.get_date()
    )
}

#[cfg(not(target_arch = "wasm32"))]
fn default_due_date_str() -> String {
    "2026-12-01".to_string()
}

/// Keeps `ctx.inbox` up to date while signed in.
pub fn setup_inbox_probe(ctx: AppContext) {
    let guard = RequestGuard::new();
    Effect::new(move |_| {
        let _ = ctx.inbox_nonce.get();
        let has_live = ctx.session.with(|s| {
            s.as_ref()
                .is_some_and(|a| matches!(a.connection, crate::api::ConnectionMode::Live(_)))
        });
        if !has_live {
            let _ = guard.bump();
            ctx.inbox.set(None);
            return;
        }
        let gen = guard.bump();
        spawn_api(
            ctx,
            |client| async move { client.chatter_inbox().await },
            move |res| {
                if !guard.is_current(gen) {
                    return;
                }
                if let Ok(inbox) = res {
                    ctx.inbox.set(Some(inbox));
                }
            },
        );
    });
}

/// Self-contained chatter panel: followers, scheduled activities, note/file composer, and feed.
#[component]
pub fn ChatterPanel(kind: &'static str, record_id: Uuid) -> impl IntoView {
    let ctx = expect_context::<AppContext>();

    let items = RwSignal::new(Vec::<ThreadItem>::new());
    let next_before_id = RwSignal::new(Option::<Uuid>::None);
    let activities = RwSignal::new(Vec::<Activity>::new());
    let followers = RwSignal::new(Option::<Followers>::None);
    let loading = RwSignal::new(true);
    let loading_older = RwSignal::new(false);
    let posting = RwSignal::new(false);
    let show_activity_form = RwSignal::new(false);
    let act_kind = RwSignal::new("todo".to_string());
    let act_summary = RwSignal::new(String::new());
    let act_due = RwSignal::new(default_due_date_str());
    let act_note = RwSignal::new(String::new());
    let note_body = RwSignal::new(String::new());
    let pending_files = RwSignal::new(Vec::<FileInfo>::new());
    let editing_note = RwSignal::new(Option::<Uuid>::None);
    let edit_note_body = RwSignal::new(String::new());

    let fb = Feedback::new();
    // `guard` owns the head refresh (and `loading`); `older_guard` owns the "Load older" request
    // (and `loading_older`). Paging never invalidates a pending refresh. A refresh does invalidate
    // a pending older page, because that page was asked for with the cursor of the old head.
    let guard = RequestGuard::new();
    let older_guard = RequestGuard::new();
    let reload = RwSignal::new(0_u64);

    Effect::new(move |_| {
        let _ = reload.get();
        let is_live = ctx.session.with(|s| {
            s.as_ref()
                .is_some_and(|a| matches!(a.connection, crate::api::ConnectionMode::Live(_)))
        });
        if !is_live {
            let _ = guard.bump();
            let _ = older_guard.bump();
            loading.set(false);
            loading_older.set(false);
            return;
        }
        let gen = guard.bump();
        let _ = older_guard.bump();
        loading_older.set(false);
        loading.set(true);

        spawn_api(
            ctx,
            move |client| async move {
                let thread = client
                    .chatter_thread(kind, record_id, &ListThreadParams::default())
                    .await;
                let acts = client.chatter_activities(kind, record_id).await;
                let fol = client.chatter_followers(kind, record_id).await;
                // Acknowledge only what the person could actually read.
                if thread.is_ok() {
                    let _ = client.chatter_mark_read(kind, record_id).await;
                }
                Ok((thread, acts, fol))
            },
            move |res| {
                // A superseded refresh leaves `loading` alone: the newer one set it and clears it.
                if !guard.is_current(gen) {
                    return;
                }
                let _ = set_alive(loading, false);
                match res {
                    Ok((thread_res, acts_res, fol_res)) => {
                        match thread_res {
                            Ok(page) => {
                                let _ = set_alive(next_before_id, page.next_before_id);
                                let _ = set_alive(items, page.items);
                            }
                            Err(err) => {
                                fb.fail(err.user_message());
                            }
                        }
                        if let Ok(list) = acts_res {
                            let _ = set_alive(activities, list);
                        }
                        if let Ok(f) = fol_res {
                            let _ = set_alive(followers, Some(f));
                        }
                        ctx.bump_inbox();
                    }
                    Err(err) => {
                        fb.fail(err.user_message());
                    }
                }
            },
        );
    });

    let on_toggle_follow = move |_| {
        let following = followers.with_untracked(|f| f.as_ref().is_some_and(|v| v.following));
        spawn_api(
            ctx,
            move |client| async move {
                if following {
                    client.chatter_unfollow(kind, record_id).await
                } else {
                    client.chatter_follow(kind, record_id).await
                }
            },
            move |res| match res {
                Ok(next) => {
                    let _ = set_alive(followers, Some(next));
                    ctx.bump_inbox();
                }
                Err(err) => {
                    fb.fail(err.user_message());
                }
            },
        );
    };

    let on_post_note = move |ev: SubmitEvent| {
        ev.prevent_default();
        if posting.get_untracked() {
            return;
        }
        let body = note_body.get_untracked().trim().to_string();
        if body.is_empty() {
            fb.fail("Write a note before posting.");
            return;
        }
        let sent_body = note_body.get_untracked();
        let file_ids: Vec<Uuid> =
            pending_files.with_untracked(|list| list.iter().map(|f| f.id).collect());
        posting.set(true);
        fb.clear();

        let req = ChatterNoteInput {
            body,
            client_id: Some(Uuid::new_v4()),
            file_ids,
        };
        spawn_api(
            ctx,
            move |client| async move { client.chatter_post_note(kind, record_id, &req).await },
            move |res| {
                let _ = set_alive(posting, false);
                match res {
                    Ok(_) => {
                        if note_body.try_get_untracked().as_deref() == Some(sent_body.as_str()) {
                            let _ = set_alive(note_body, String::new());
                        }
                        let _ = set_alive(pending_files, Vec::new());
                        let _ = reload.try_update(|n| *n = n.wrapping_add(1));
                    }
                    Err(err) => {
                        fb.fail(err.user_message());
                    }
                }
            },
        );
    };

    let on_pick_file = move |ev: leptos::ev::Event| {
        begin_file_read(
            ev,
            MAX_CHATTER_FILE_BYTES,
            "File is larger than the 10 MB limit.",
            move |picked| match picked {
                Ok(file) => {
                    spawn_api(
                        ctx,
                        move |client| async move {
                            client
                                .chatter_upload_file(
                                    kind,
                                    record_id,
                                    &file.name,
                                    Some(Uuid::new_v4()),
                                    file.bytes,
                                )
                                .await
                        },
                        move |res| match res {
                            Ok(info) => {
                                pending_files.try_update(|list| list.push(info));
                            }
                            Err(err) => {
                                fb.fail(err.user_message());
                            }
                        },
                    );
                }
                Err(msg) if !msg.is_empty() => {
                    fb.fail(msg);
                }
                Err(_) => {}
            },
        );
    };

    let on_schedule_activity = move |ev: SubmitEvent| {
        ev.prevent_default();
        let summary = act_summary.get_untracked().trim().to_string();
        if summary.is_empty() {
            fb.fail("Activity summary is required.");
            return;
        }
        let due_raw = act_due.get_untracked();
        let Ok(due_date) = NaiveDate::parse_from_str(due_raw.trim(), "%Y-%m-%d") else {
            fb.fail("Due date must use YYYY-MM-DD.");
            return;
        };
        let Some(assignee_id) = ctx
            .session
            .with_untracked(|s| s.as_ref().map(|a| a.me.user_id))
        else {
            return;
        };
        let kind_val = ActivityKind::parse(&act_kind.get_untracked()).unwrap_or(ActivityKind::Todo);
        let note = act_note.get_untracked().trim().to_string();
        let req = ActivityInput {
            kind: kind_val,
            summary,
            note,
            assignee_id,
            due_date,
            client_id: Some(Uuid::new_v4()),
        };
        spawn_api(
            ctx,
            move |client| async move { client.chatter_create_activity(kind, record_id, &req).await },
            move |res| match res {
                Ok(_) => {
                    let _ = set_alive(act_summary, String::new());
                    let _ = set_alive(act_note, String::new());
                    let _ = set_alive(show_activity_form, false);
                    let _ = reload.try_update(|n| *n = n.wrapping_add(1));
                }
                Err(err) => {
                    fb.fail(err.user_message());
                }
            },
        );
    };

    let on_load_older = move |_| {
        let Some(cursor) = next_before_id.get_untracked() else {
            return;
        };
        // Wait for a pending refresh: its page replaces the feed and the cursor.
        if loading_older.get_untracked() || loading.get_untracked() {
            return;
        }
        let gen = older_guard.bump();
        loading_older.set(true);
        let params = ListThreadParams {
            before_id: Some(cursor),
            limit: None,
        };
        spawn_api(
            ctx,
            move |client| async move { client.chatter_thread(kind, record_id, &params).await },
            move |res| {
                // Superseded by a refresh (which already cleared the flag) or a newer request.
                if !older_guard.is_current(gen) {
                    return;
                }
                let _ = set_alive(loading_older, false);
                match res {
                    Ok(page) => {
                        items.try_update(|list| list.extend(page.items));
                        let _ = set_alive(next_before_id, page.next_before_id);
                    }
                    Err(err) => {
                        fb.fail(err.user_message());
                    }
                }
            },
        );
    };

    view! {
        <aside class="tc-card tc-chatter" data-target="chatter-panel">
            <div class="tc-chatter-head">
                <h3 style="margin: 0; font-size: 15px;">"Chatter"</h3>
                <div class="tc-header-actions">
                    {move || followers.get().map(|f| view! {
                        <span class="tc-badge" data-target="chatter-followers-count">
                            {format!("{} followers", f.items.len())}
                        </span>
                        <button
                            type="button"
                            class=if f.following { "tc-btn tc-btn-primary tc-btn-sm" } else { "tc-btn tc-btn-sm" }
                            data-target="chatter-follow-toggle"
                            on:click=on_toggle_follow
                        >
                            {if f.following { "Following" } else { "Follow" }}
                        </button>
                    })}
                </div>
            </div>

            <FeedbackView fb prefix="chatter" />

            <div class="tc-chatter-section" data-target="chatter-activities">
                <div class="tc-chatter-section-head">
                    <span class="tc-label">"Activities"</span>
                    <button
                        type="button"
                        class="tc-btn tc-btn-ghost tc-btn-sm"
                        data-target="chatter-activity-toggle"
                        on:click=move |_| show_activity_form.update(|v| *v = !*v)
                    >
                        {move || if show_activity_form.get() { "Cancel" } else { "+ Schedule" }}
                    </button>
                </div>

                <Show when=move || show_activity_form.get()>
                    <form class="tc-chatter-activity-form" data-target="chatter-activity-form" on:submit=on_schedule_activity>
                        <div class="tc-form-grid">
                            <select
                                class="tc-select"
                                data-target="chatter-activity-kind"
                                prop:value=move || act_kind.get()
                                on:change=move |ev| act_kind.set(event_target_value(&ev))
                            >
                                {ActivityKind::ALL.into_iter().map(|k| view! {
                                    <option value=k.as_str()>{k.label()}</option>
                                }).collect_view()}
                            </select>
                            <input
                                type="date"
                                class="tc-input"
                                data-target="chatter-activity-due"
                                prop:value=move || act_due.get()
                                on:input=move |ev| act_due.set(event_target_value(&ev))
                            />
                            <input
                                type="text"
                                class="tc-input tc-form-span-2"
                                placeholder="Summary (e.g. Call about quote)"
                                data-target="chatter-activity-summary"
                                prop:value=move || act_summary.get()
                                on:input=move |ev| act_summary.set(event_target_value(&ev))
                            />
                            <input
                                type="text"
                                class="tc-input tc-form-span-2"
                                placeholder="Optional note"
                                data-target="chatter-activity-note"
                                prop:value=move || act_note.get()
                                on:input=move |ev| act_note.set(event_target_value(&ev))
                            />
                        </div>
                        <div style="display: flex; justify-content: flex-end;">
                            <button type="submit" class="tc-btn tc-btn-primary tc-btn-sm" data-target="chatter-activity-submit">
                                "Schedule"
                            </button>
                        </div>
                    </form>
                </Show>

                {move || {
                    let list = activities.get();
                    if list.is_empty() {
                        return view! {
                            <p style="margin: 0; font-size: 12px; color: var(--on-surface-variant);">
                                "No open activities."
                            </p>
                        }
                        .into_any();
                    }
                    view! {
                        <ul class="tc-home-list">
                            {list
                                .into_iter()
                                .map(|act| {
                                    let aid_done = act.id;
                                    let aid_del = act.id;
                                    view! {
                                        <li class="tc-home-list-item" data-target=format!("chatter-activity-{}", act.id)>
                                            <div style="min-width: 0; flex: 1;">
                                                <div style="display: flex; align-items: center; gap: 6px; flex-wrap: wrap;">
                                                    <span class="tc-badge">{act.kind}</span>
                                                    <strong>{act.summary}</strong>
                                                    <span class=if act.overdue { "tc-badge tc-badge-error" } else { "tc-badge" }>
                                                        {act.due_date.to_string()}
                                                    </span>
                                                </div>
                                                <div style="font-size: 11px; color: var(--on-surface-variant);">
                                                    {act.assignee_name}
                                                </div>
                                            </div>
                                            <div class="tc-header-actions">
                                                <button
                                                    type="button"
                                                    class="tc-btn tc-btn-sm"
                                                    data-target="chatter-activity-done"
                                                    on:click=move |_| {
                                                        spawn_api(
                                                            ctx,
                                                            move |c| async move {
                                                                c.chatter_complete_activity(aid_done, &ActivityDoneInput::default()).await
                                                            },
                                                            move |res| match res {
                                                                Ok(()) => {
                                                                    let _ = reload.try_update(|n| *n = n.wrapping_add(1));
                                                                }
                                                                Err(err) => {
                                                                    fb.fail(err.user_message());
                                                                }
                                                            },
                                                        );
                                                    }
                                                >
                                                    "Done"
                                                </button>
                                                <button
                                                    type="button"
                                                    class="tc-btn tc-btn-ghost tc-btn-sm"
                                                    data-target="chatter-activity-delete"
                                                    on:click=move |_| {
                                                        spawn_api(
                                                            ctx,
                                                            move |c| async move { c.chatter_delete_activity(aid_del).await },
                                                            move |res| match res {
                                                                Ok(()) => {
                                                                    let _ = reload.try_update(|n| *n = n.wrapping_add(1));
                                                                }
                                                                Err(err) => {
                                                                    fb.fail(err.user_message());
                                                                }
                                                            },
                                                        );
                                                    }
                                                >
                                                    "×"
                                                </button>
                                            </div>
                                        </li>
                                    }
                                })
                                .collect_view()}
                        </ul>
                    }
                    .into_any()
                }}
            </div>

            <form class="tc-chatter-composer" data-target="chatter-composer" on:submit=on_post_note>
                <textarea
                    class="tc-input"
                    rows="2"
                    placeholder="Write an internal note…"
                    data-target="chatter-note-input"
                    prop:value=move || note_body.get()
                    on:input=move |ev| note_body.set(event_target_value(&ev))
                />
                {move || {
                    let list = pending_files.get();
                    (!list.is_empty()).then(|| view! {
                        <div class="tc-chip-row">
                            {list
                                .into_iter()
                                .map(|file| {
                                    let fid = file.id;
                                    view! {
                                        <span class="tc-badge">
                                            {format!("{} ({})", file.filename, format_file_size(i64::from(file.size_bytes)))}
                                            <button
                                                type="button"
                                                class="tc-tab-close"
                                                style="margin-left: 4px;"
                                                on:click=move |_| pending_files.update(|l| l.retain(|f| f.id != fid))
                                            >
                                                "×"
                                            </button>
                                        </span>
                                    }
                                })
                                .collect_view()}
                        </div>
                    })
                }}
                <div class="tc-chatter-composer-actions">
                    <label class="tc-btn tc-btn-sm" style="cursor: pointer;">
                        "Attach"
                        <input
                            type="file"
                            style="display: none;"
                            data-target="chatter-file-input"
                            on:change=on_pick_file
                        />
                    </label>
                    <button
                        type="submit"
                        class="tc-btn tc-btn-primary tc-btn-sm"
                        data-target="chatter-post-note"
                        disabled=move || posting.get()
                    >
                        {move || if posting.get() { "Posting…" } else { "Post note" }}
                    </button>
                </div>
            </form>

            <div class="tc-chatter-feed" data-target="chatter-thread">
                {move || {
                    let list = items.get();
                    if loading.get() && list.is_empty() {
                        return view! {
                            <p style="margin: 0; font-size: 12px; color: var(--on-surface-variant);">"Loading chatter…"</p>
                        }
                        .into_any();
                    }
                    if list.is_empty() {
                        return view! {
                            <p style="margin: 0; font-size: 12px; color: var(--on-surface-variant);" data-target="chatter-empty">
                                "No notes or activity yet."
                            </p>
                        }
                        .into_any();
                    }
                    list.into_iter()
                        .map(|entry| {
                            let eid = entry.id;
                            let is_system = entry.kind == "system";
                            let editable = entry.editable;
                            let entry_body_for_edit = entry.body.clone();
                            let changes = entry.changes.clone();
                            let files = entry.files.clone();
                            let stamp = format_timestamp(entry.created_at);
                            view! {
                                <div class="tc-chatter-item" data-target=format!("chatter-item-{eid}")>
                                    <div class="tc-chatter-item-head">
                                        <span style="font-weight: 600;">
                                            {if is_system {
                                                "System".to_string()
                                            } else {
                                                entry.author_name.unwrap_or_else(|| "User".to_string())
                                            }}
                                        </span>
                                        <span class="tc-mono" style="font-size: 11px; color: var(--on-surface-variant);">
                                            {stamp}
                                        </span>
                                    </div>
                                    <Show
                                        when=move || editing_note.get() == Some(eid)
                                        fallback={
                                            let body_display = entry.body.clone();
                                            move || view! {
                                                <p style="margin: 4px 0 0; white-space: pre-wrap;">{body_display.clone()}</p>
                                            }
                                        }
                                    >
                                        <form
                                            style="display: flex; flex-direction: column; gap: 6px; margin-top: 4px;"
                                            on:submit=move |ev: SubmitEvent| {
                                                ev.prevent_default();
                                                let body = edit_note_body.get_untracked().trim().to_string();
                                                if body.is_empty() {
                                                    return;
                                                }
                                                spawn_api(
                                                    ctx,
                                                    move |c| async move {
                                                        c.chatter_edit_note(eid, &ChatterNoteEdit { body }).await
                                                    },
                                                    move |res| match res {
                                                        Ok(_) => {
                                                            let _ = set_alive(editing_note, None);
                                                            let _ = reload.try_update(|n| *n = n.wrapping_add(1));
                                                        }
                                                        Err(err) => {
                                                            fb.fail(err.user_message());
                                                        }
                                                    },
                                                );
                                            }
                                        >
                                            <textarea
                                                class="tc-input"
                                                rows="2"
                                                prop:value=move || edit_note_body.get()
                                                on:input=move |ev| edit_note_body.set(event_target_value(&ev))
                                            />
                                            <div class="tc-header-actions">
                                                <button type="submit" class="tc-btn tc-btn-primary tc-btn-sm">"Save"</button>
                                                <button
                                                    type="button"
                                                    class="tc-btn tc-btn-sm"
                                                    on:click=move |_| editing_note.set(None)
                                                >
                                                    "Cancel"
                                                </button>
                                            </div>
                                        </form>
                                    </Show>

                                    {(!changes.is_empty()).then(|| view! {
                                        <ul style="margin: 4px 0 0; padding-left: 16px; font-size: 12px; color: var(--on-surface-variant);">
                                            {changes
                                                .iter()
                                                .filter_map(format_change_entry)
                                                .map(|line| view! { <li>{line}</li> })
                                                .collect_view()}
                                        </ul>
                                    })}

                                    {(!files.is_empty()).then(|| view! {
                                        <div class="tc-chip-row" style="margin-top: 6px;">
                                            {files
                                                .into_iter()
                                                .map(|f| {
                                                    let fid = f.id;
                                                    let fname = f.filename.clone();
                                                    let ctype = f.content_type.clone();
                                                    let label = format!("{} ({})", f.filename, format_file_size(i64::from(f.size_bytes)));
                                                    view! {
                                                        <button
                                                            type="button"
                                                            class="tc-chip"
                                                            on:click=move |_| {
                                                                let fname_s = fname.clone();
                                                                let ctype_s = ctype.clone();
                                                                spawn_api(
                                                                    ctx,
                                                                    move |c| async move { c.chatter_download_file(kind, record_id, fid).await },
                                                                    move |res| match res {
                                                                        Ok(bytes) => {
                                                                            if let Err(err) = save_file(&fname_s, &ctype_s, &bytes) {
                                                                                fb.fail(err);
                                                                            }
                                                                        }
                                                                        Err(err) => {
                                                                            fb.fail(err.user_message());
                                                                        }
                                                                    },
                                                                );
                                                            }
                                                        >
                                                            {label}
                                                        </button>
                                                    }
                                                })
                                                .collect_view()}
                                        </div>
                                    })}

                                    {(editable && editing_note.get() != Some(eid)).then(|| {
                                        let init_edit = entry_body_for_edit.clone();
                                        view! {
                                            <div class="tc-header-actions" style="margin-top: 4px;">
                                                <button
                                                    type="button"
                                                    class="tc-btn tc-btn-ghost tc-btn-sm"
                                                    on:click=move |_| {
                                                        edit_note_body.set(init_edit.clone());
                                                        editing_note.set(Some(eid));
                                                    }
                                                >
                                                    "Edit"
                                                </button>
                                                <button
                                                    type="button"
                                                    class="tc-btn tc-btn-ghost tc-btn-sm"
                                                    on:click=move |_| {
                                                        spawn_api(
                                                            ctx,
                                                            move |c| async move { c.chatter_delete_note(eid).await },
                                                            move |res| match res {
                                                                Ok(()) => {
                                                                    let _ = reload.try_update(|n| *n = n.wrapping_add(1));
                                                                }
                                                                Err(err) => {
                                                                    fb.fail(err.user_message());
                                                                }
                                                            },
                                                        );
                                                    }
                                                >
                                                    "Delete"
                                                </button>
                                            </div>
                                        }
                                    })}
                                </div>
                            }
                        })
                        .collect_view()
                        .into_any()
                }}
                <Show when=move || next_before_id.get().is_some()>
                    <button
                        type="button"
                        class="tc-btn tc-btn-sm"
                        data-target="chatter-load-older"
                        disabled=move || loading_older.get()
                        on:click=on_load_older
                    >
                        {move || if loading_older.get() { "Loading…" } else { "Load older" }}
                    </button>
                </Show>
            </div>
        </aside>
    }
}

/// Topbar button opening [`ChatterInboxDrawer`] with a live unread + due activity count badge.
#[component]
pub fn ChatterInboxButton(open: RwSignal<bool>) -> impl IntoView {
    let ctx = expect_context::<AppContext>();
    let badge = Memo::new(move |_| ctx.inbox.with(|i| inbox_badge_count(i.as_ref())));

    view! {
        <button
            type="button"
            class="tc-btn tc-btn-ghost tc-btn-sm"
            data-target="inbox-toggle"
            on:click=move |_| {
                ctx.bump_inbox();
                open.update(|v| *v = !*v);
            }
        >
            <span>{move || tr("shell.inbox", "Inbox")}</span>
            {move || {
                let (count, overdue) = badge.get();
                (count > 0).then(|| view! {
                    <span
                        class=if overdue { "tc-badge tc-badge-error" } else { "tc-badge tc-badge-primary" }
                        data-target="inbox-badge"
                    >
                        {count}
                    </span>
                })
            }}
        </button>
    }
}

/// Modal drawer listing due activities and unread followed chatter threads.
#[component]
pub fn ChatterInboxDrawer(open: RwSignal<bool>) -> impl IntoView {
    let ctx = expect_context::<AppContext>();
    let navigate = use_navigate();
    let title = Signal::derive(move || tr("shell.inbox", "Inbox"));

    let go_to_record = Callback::new(move |(kind, id): (String, Uuid)| {
        let Some(rk) = RecordKind::parse(&kind) else {
            return;
        };
        let dest = rk.route_for(id);
        open.set(false);
        ctx.active_tab.set(None);
        navigate(&dest, NavigateOptions::default());
    });

    view! {
        <Modal
            open=open
            title=title
            on_close=Callback::new(move |()| open.set(false))
            target="inbox-drawer"
        >
            {move || {
                let Some(inbox) = ctx.inbox.get() else {
                    return view! {
                        <p style="margin: 0; color: var(--on-surface-variant);" data-target="inbox-empty">
                            "No unread messages or due activities."
                        </p>
                    }
                    .into_any();
                };
                if inbox.activities.is_empty() && inbox.unread.is_empty() {
                    return view! {
                        <p style="margin: 0; color: var(--on-surface-variant);" data-target="inbox-empty">
                            "No unread messages or due activities."
                        </p>
                    }
                    .into_any();
                }

                let activities_sec = (!inbox.activities.is_empty()).then(|| view! {
                    <div class="tc-inbox-section" data-target="inbox-activities">
                        <div class="tc-nav-group-label">"Due activities"</div>
                        <ul class="tc-home-list">
                            {inbox
                                .activities
                                .into_iter()
                                .map(|a| {
                                    let rkind = a.record_kind.clone();
                                    let rid = a.record_id;
                                    view! {
                                        <li>
                                            <button
                                                type="button"
                                                class="tc-home-list-item tc-home-list-btn"
                                                data-target=format!("inbox-activity-{}", a.id)
                                                on:click=move |_| go_to_record.run((rkind.clone(), rid))
                                            >
                                                <div>
                                                    <div>{format!("[{}] {}", a.kind, a.summary)}</div>
                                                    <div style="font-size: 11px; color: var(--on-surface-variant);">
                                                        {a.label.unwrap_or_else(|| a.record_kind.clone())}
                                                    </div>
                                                </div>
                                                <span class=if a.overdue { "tc-badge tc-badge-error" } else { "tc-badge" }>
                                                    {a.due_date.to_string()}
                                                </span>
                                            </button>
                                        </li>
                                    }
                                })
                                .collect_view()}
                        </ul>
                    </div>
                });

                let unread_sec = (!inbox.unread.is_empty()).then(|| view! {
                    <div class="tc-inbox-section" data-target="inbox-unread">
                        <div class="tc-nav-group-label">"Unread threads"</div>
                        <ul class="tc-home-list">
                            {inbox
                                .unread
                                .into_iter()
                                .map(|u| {
                                    let rkind = u.record_kind.clone();
                                    let rid = u.record_id;
                                    view! {
                                        <li>
                                            <button
                                                type="button"
                                                class="tc-home-list-item tc-home-list-btn"
                                                data-target=format!("inbox-unread-{}", u.record_id)
                                                on:click=move |_| go_to_record.run((rkind.clone(), rid))
                                            >
                                                <span>{u.label.unwrap_or_else(|| u.record_kind.clone())}</span>
                                                <span class="tc-badge tc-badge-primary">{u.unread}</span>
                                            </button>
                                        </li>
                                    }
                                })
                                .collect_view()}
                        </ul>
                    </div>
                });

                view! {
                    <div class="tc-inbox-drawer">
                        {activities_sec}
                        {unread_sec}
                    </div>
                }
                .into_any()
            }}
        </Modal>
    }
}

#[cfg(test)]
mod tests {
    use chrono::TimeZone;
    use tradocraft_api_client::chatter::{InboxActivity, InboxRecord};

    use super::*;

    #[test]
    fn inbox_badge_counts_unread_and_overdue() {
        assert_eq!(inbox_badge_count(None), (0, false));
        let empty = Inbox::default();
        assert_eq!(inbox_badge_count(Some(&empty)), (0, false));

        let stamp = Utc.with_ymd_and_hms(2026, 11, 28, 9, 5, 0).unwrap();
        let inbox = Inbox {
            unread: vec![InboxRecord {
                record_kind: "customer".into(),
                record_id: Uuid::nil(),
                label: Some("Acme".into()),
                unread: 2,
                last_at: stamp,
            }],
            activities: vec![InboxActivity {
                id: Uuid::nil(),
                record_kind: "quotation".into(),
                record_id: Uuid::nil(),
                label: Some("Q-001".into()),
                kind: "call".into(),
                summary: "Follow up".into(),
                due_date: NaiveDate::from_ymd_opt(2026, 11, 20).unwrap(),
                overdue: true,
            }],
        };
        assert_eq!(inbox_badge_count(Some(&inbox)), (2, true));
    }

    #[test]
    fn formats_timestamps_and_change_entries() {
        let stamp = Utc.with_ymd_and_hms(2026, 11, 28, 9, 5, 0).unwrap();
        assert_eq!(format_timestamp(stamp), "2026-11-28 09:05");

        let entry = serde_json::json!({"field": "status", "from": "draft", "to": "sent"});
        assert_eq!(
            format_change_entry(&entry).as_deref(),
            Some("status: draft -> sent")
        );
    }
}
