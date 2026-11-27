//! Administration, section "Audit trail" (ADR 0059): the company-wide trail, newest first, filtered
//! by kind of record, action and period, older events on request. Mirrors `audit_trail_page.dart`
//! and the event tile of `shared/record_history.dart`.

use chrono::{DateTime, NaiveDate, Utc};
use leptos::ev::SubmitEvent;
use leptos::prelude::*;
use tradocraft_api_client::audit::{AuditEvent, ListAuditEventsParams};

use super::{spawn_api, Feedback, FeedbackView};
use crate::pages::set_alive;
use crate::state::AppContext;

/// Who did it: the user's name, else their e-mail address, else "System".
pub(crate) fn audit_who(e: &AuditEvent) -> String {
    for v in [&e.user_name, &e.user_email] {
        if let Some(s) = v.as_deref().map(str::trim).filter(|s| !s.is_empty()) {
            return s.to_string();
        }
    }
    "System".into()
}

/// One value of an event as short text.
pub(crate) fn audit_value(v: &serde_json::Value) -> String {
    match v {
        serde_json::Value::Null => "\u{2013}".into(),
        serde_json::Value::String(s) if s.is_empty() => "\"\"".into(),
        serde_json::Value::String(s) => s.clone(),
        serde_json::Value::Number(n) => n.to_string(),
        serde_json::Value::Bool(b) => b.to_string(),
        other => other.to_string(),
    }
}

/// The lines under an event: one per changed field, then the other recorded values in full.
pub(crate) fn audit_details(data: &serde_json::Value) -> Vec<String> {
    let none = || vec!["No details were recorded.".to_string()];
    let Some(map) = data.as_object().filter(|m| !m.is_empty()) else {
        return none();
    };
    let mut lines = Vec::new();
    if let Some(changes) = map.get("changes").and_then(|c| c.as_object()) {
        for (field, c) in changes {
            if let Some(c) = c.as_object() {
                let null = serde_json::Value::Null;
                lines.push(format!(
                    "{field}: {} \u{2192} {}",
                    audit_value(c.get("from").unwrap_or(&null)),
                    audit_value(c.get("to").unwrap_or(&null))
                ));
            }
        }
    }
    let rest: Vec<String> = map
        .iter()
        .filter(|(k, _)| k.as_str() != "changes")
        .map(|(k, v)| format!("{k}: {}", audit_value(v)))
        .collect();
    if !rest.is_empty() {
        lines.push(rest.join(", "));
    }
    if lines.is_empty() {
        none()
    } else {
        lines
    }
}

/// The start of a local day, in UTC.
#[cfg(target_arch = "wasm32")]
fn local_day_start(d: NaiveDate) -> Option<DateTime<Utc>> {
    use chrono::Datelike;
    let js =
        js_sys::Date::new_with_year_month_day(d.year() as u32, d.month0() as i32, d.day() as i32);
    DateTime::from_timestamp_millis(js.get_time() as i64)
}

#[cfg(not(target_arch = "wasm32"))]
fn local_day_start(d: NaiveDate) -> Option<DateTime<Utc>> {
    d.and_hms_opt(0, 0, 0).map(|t| t.and_utc())
}

/// Whole local days: from the start of the first to the start of the day after the last.
pub(crate) fn period_bounds(
    from: Option<NaiveDate>,
    to: Option<NaiveDate>,
) -> (Option<DateTime<Utc>>, Option<DateTime<Utc>>) {
    (
        from.and_then(local_day_start),
        to.and_then(|d| d.succ_opt()).and_then(local_day_start),
    )
}

/// `dd/MM/yyyy HH:mm` in the browser's time zone.
#[cfg(target_arch = "wasm32")]
fn format_when(t: DateTime<Utc>) -> String {
    let d = js_sys::Date::new(&wasm_bindgen::JsValue::from_f64(t.timestamp_millis() as f64));
    format!(
        "{:02}/{:02}/{:04} {:02}:{:02}",
        d.get_date(),
        d.get_month() + 1,
        d.get_full_year(),
        d.get_hours(),
        d.get_minutes()
    )
}

#[cfg(not(target_arch = "wasm32"))]
fn format_when(t: DateTime<Utc>) -> String {
    use chrono::{Datelike, Timelike};
    format!(
        "{:02}/{:02}/{:04} {:02}:{:02}",
        t.day(),
        t.month(),
        t.year(),
        t.hour(),
        t.minute()
    )
}

fn parse_date(raw: &str) -> Option<NaiveDate> {
    NaiveDate::parse_from_str(raw.trim(), "%Y-%m-%d").ok()
}

#[component]
pub fn AuditSection() -> impl IntoView {
    let ctx = expect_context::<AppContext>();
    let fb = Feedback::new();

    let entities = RwSignal::new(Vec::<String>::new());
    let entity = RwSignal::new(String::new());
    let action_input = RwSignal::new(String::new());
    // The action the list on screen was loaded with; "load older" keeps asking for it.
    let applied_action = RwSignal::new(Option::<String>::None);
    let from = RwSignal::new(String::new());
    let to = RwSignal::new(String::new());
    let events = RwSignal::new(Vec::<AuditEvent>::new());
    let next = RwSignal::new(Option::<i64>::None);
    let loading = RwSignal::new(false);
    // A filter change while a page is on its way: only the newest request may fill the list.
    let seq = StoredValue::new(0_u64);

    spawn_api(
        ctx,
        |c| async move { c.audit_facets().await },
        move |res| {
            // Without facets the filter offers "all" only; the trail reports real problems.
            if let Ok(f) = res {
                set_alive(entities, f.entities);
            }
        },
    );

    let load = move |reset: bool| {
        let my_seq = seq
            .try_update_value(|s| {
                *s += 1;
                *s
            })
            .unwrap_or(0);
        loading.set(true);
        fb.error.set(None);
        if reset {
            events.set(Vec::new());
            next.set(None);
            let typed = action_input.get_untracked().trim().to_string();
            applied_action.set((!typed.is_empty()).then_some(typed));
        }
        let (from_t, to_t) = period_bounds(
            parse_date(&from.get_untracked()),
            parse_date(&to.get_untracked()),
        );
        let ent = entity.get_untracked();
        let params = ListAuditEventsParams {
            entity: (!ent.is_empty()).then_some(ent),
            action: applied_action.get_untracked(),
            from: from_t,
            to: to_t,
            before_id: if reset { None } else { next.get_untracked() },
            ..ListAuditEventsParams::default()
        };
        spawn_api(
            ctx,
            move |c| async move { c.list_audit_events(&params).await },
            move |res| {
                if seq.try_get_value() != Some(my_seq) || !set_alive(loading, false) {
                    return;
                }
                match res {
                    Ok(page) => {
                        events.update(|e| e.extend(page.items));
                        next.set(page.next_before_id);
                    }
                    Err(err) => {
                        fb.fail(err.user_message());
                    }
                }
            },
        );
    };
    load(true);

    let on_action = move |ev: SubmitEvent| {
        ev.prevent_default();
        load(true);
    };

    view! {
        <section data-target="admin-audit" aria-labelledby="admin-audit-title">
            <h2 id="admin-audit-title" class="tc-page-title" style="font-size: 18px;">"Audit trail"</h2>
            <form class="tc-toolbar" data-target="admin-audit-filters" on:submit=on_action>
                <div class="tc-field">
                    <label class="tc-label" for="admin-audit-entity">"Record type"</label>
                    <select id="admin-audit-entity" data-target="admin-audit-entity" class="tc-select"
                        on:change=move |ev| {
                            entity.set(event_target_value(&ev));
                            load(true);
                        }>
                        <option value="" selected=move || entity.get().is_empty()>"All"</option>
                        {move || entities.get().into_iter().map(|e| {
                            let e_sel = e.clone();
                            let e_val = e.clone();
                            view! { <option value=e_val selected=move || entity.get() == e_sel>{e}</option> }
                        }).collect_view()}
                    </select>
                </div>
                <div class="tc-field">
                    <label class="tc-label" for="admin-audit-action">"Action"</label>
                    <input id="admin-audit-action" data-target="admin-audit-action" class="tc-input" type="text"
                        prop:value=move || action_input.get()
                        on:input=move |ev| action_input.set(event_target_value(&ev)) />
                </div>
                <div class="tc-field">
                    <label class="tc-label" for="admin-audit-from">"From"</label>
                    <input id="admin-audit-from" data-target="admin-audit-from" class="tc-input" type="date"
                        prop:value=move || from.get()
                        on:change=move |ev| {
                            from.set(event_target_value(&ev));
                            load(true);
                        } />
                </div>
                <div class="tc-field">
                    <label class="tc-label" for="admin-audit-to">"Until"</label>
                    <input id="admin-audit-to" data-target="admin-audit-to" class="tc-input" type="date"
                        prop:value=move || to.get()
                        on:change=move |ev| {
                            to.set(event_target_value(&ev));
                            load(true);
                        } />
                </div>
                <button type="submit" class="tc-btn" data-target="admin-audit-apply">"Apply"</button>
                <Show when=move || !from.get().is_empty() || !to.get().is_empty()>
                    <button type="button" class="tc-btn" data-target="admin-audit-clear-dates"
                        on:click=move |_| {
                            from.set(String::new());
                            to.set(String::new());
                            load(true);
                        }>
                        "Clear dates"
                    </button>
                </Show>
            </form>
            <FeedbackView fb prefix="admin-audit" />
            {move || {
                let empty = events.with(Vec::is_empty);
                if empty && loading.get() {
                    view! { <p class="tc-label">"Loading events..."</p> }.into_any()
                } else if empty && fb.error.with(Option::is_some) {
                    view! {
                        <button type="button" class="tc-btn" data-target="admin-audit-retry" on:click=move |_| load(true)>"Retry"</button>
                    }.into_any()
                } else if empty {
                    view! { <p data-target="admin-audit-empty">"No events found."</p> }.into_any()
                } else {
                    view! { <div></div> }.into_any()
                }
            }}
            <ul data-target="admin-audit-list" style="list-style: none; margin: 0; padding: 0;">
                <For
                    each=move || events.get()
                    key=|e| e.id
                    children=move |e| {
                        let details = audit_details(&e.data);
                        let meta = format!("{}  \u{b7}  {}", audit_who(&e), format_when(e.occurred_at));
                        view! {
                            <li class="tc-card" style="margin-bottom: var(--space-sm);" data-target=format!("admin-audit-event-{}", e.id)>
                                <div style="display: flex; gap: var(--space-sm); flex-wrap: wrap; align-items: baseline;">
                                    <strong data-target="admin-audit-event-action">{e.action.clone()}</strong>
                                    <span class="tc-label" data-target="admin-audit-event-entity">{format!("\u{b7}  {}", e.entity)}</span>
                                    <span class="tc-label tc-mono" style="user-select: all;">{e.entity_id.to_string()}</span>
                                </div>
                                <div class="tc-label">{meta}</div>
                                {details.into_iter().map(|line| view! {
                                    <div style="font-size: 13px; white-space: pre-wrap; word-break: break-word;">{line}</div>
                                }).collect_view()}
                            </li>
                        }
                    }
                />
            </ul>
            <Show when=move || next.get().is_some() && !events.with(Vec::is_empty)>
                <button type="button" class="tc-btn" data-target="admin-audit-more"
                    disabled=move || loading.get()
                    on:click=move |_| load(false)>
                    "Load older events"
                </button>
            </Show>
        </section>
    }
}

#[cfg(test)]
mod tests {
    use serde_json::json;
    use uuid::Uuid;

    use super::*;

    fn event(name: Option<&str>, email: Option<&str>) -> AuditEvent {
        AuditEvent {
            id: 1,
            occurred_at: DateTime::UNIX_EPOCH,
            entity: "customer".into(),
            entity_id: Uuid::nil(),
            action: "updated".into(),
            data: json!({}),
            user_id: None,
            user_name: name.map(Into::into),
            user_email: email.map(Into::into),
        }
    }

    #[test]
    fn who_falls_back_to_email_then_system() {
        assert_eq!(audit_who(&event(Some("Ann"), Some("a@x"))), "Ann");
        assert_eq!(audit_who(&event(Some(" "), Some("a@x"))), "a@x");
        assert_eq!(audit_who(&event(None, None)), "System");
    }

    #[test]
    fn details_list_changes_then_the_rest() {
        let lines = audit_details(&json!({
            "changes": {"name": {"from": "A", "to": null}, "note": {"from": "", "to": 3}},
            "via": "portal", "flag": true
        }));
        assert_eq!(lines[0], "name: A \u{2192} \u{2013}");
        assert_eq!(lines[1], "note: \"\" \u{2192} 3");
        assert!(lines[2].contains("via: portal") && lines[2].contains("flag: true"));
        assert_eq!(audit_details(&json!({})), vec!["No details were recorded."]);
        assert_eq!(
            audit_details(&json!(null)),
            vec!["No details were recorded."]
        );
    }

    #[test]
    fn period_covers_whole_days() {
        let (from, to) = period_bounds(
            NaiveDate::from_ymd_opt(2026, 11, 1),
            NaiveDate::from_ymd_opt(2026, 11, 2),
        );
        let day = |d: u32| {
            NaiveDate::from_ymd_opt(2026, 11, d)
                .and_then(|n| n.and_hms_opt(0, 0, 0))
                .map(|t| t.and_utc())
        };
        assert_eq!(from, day(1));
        assert_eq!(to, day(3));
        assert_eq!(format_when(day(3).unwrap()), "03/11/2026 00:00");
        assert_eq!(period_bounds(None, None), (None, None));
    }
}
