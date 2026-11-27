//! Administration, section "Price zones": list, create, edit and delete (the server refuses deleting
//! a zone in use). Mirrors `price_zones_page.dart`.

use std::str::FromStr;

use leptos::ev::SubmitEvent;
use leptos::prelude::*;
use rust_decimal::Decimal;
use tradocraft_api_client::price_zones::{PriceZone, PriceZoneInput};
use uuid::Uuid;

use super::{spawn_api, Feedback, FeedbackView};
use crate::pages::set_alive;
use crate::state::AppContext;

const ROUNDING_OPTIONS: [&str; 8] = [
    "none", "0.01", "0.05", "0.10", "0.50", "1.00", "5.00", "10.00",
];

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct ZoneDraft {
    pub code: String,
    pub name: String,
    pub sort: String,
    pub multiplier: String,
    pub rounding: String,
}

impl Default for ZoneDraft {
    fn default() -> Self {
        Self {
            code: String::new(),
            name: String::new(),
            sort: "0".into(),
            multiplier: String::new(),
            rounding: "none".into(),
        }
    }
}

impl ZoneDraft {
    fn from_zone(z: &PriceZone) -> Self {
        let rounding = z
            .default_rounding
            .clone()
            .filter(|r| ROUNDING_OPTIONS.contains(&r.as_str()))
            .unwrap_or_else(|| "none".into());
        Self {
            code: z.code.clone(),
            name: z.name.clone(),
            sort: z.sort_order.to_string(),
            multiplier: z
                .default_multiplier
                .map(|m| m.normalize().to_string())
                .unwrap_or_default(),
            rounding,
        }
    }

    /// Validates like Flutter does and builds the request.
    pub fn to_input(&self) -> Result<PriceZoneInput, String> {
        if self.code.trim().is_empty() || self.name.trim().is_empty() {
            return Err("Code and name are required.".into());
        }
        let sort = self
            .sort
            .trim()
            .parse::<i32>()
            .map_err(|_| "Sort order must be a whole number.".to_string())?;
        let multiplier = if self.multiplier.trim().is_empty() {
            None
        } else {
            match Decimal::from_str(&self.multiplier.trim().replace(',', ".")) {
                Ok(m) if m > Decimal::ZERO => Some(m),
                _ => return Err("Multiplier must be a positive number".into()),
            }
        };
        Ok(PriceZoneInput {
            code: self.code.trim().to_string(),
            name: self.name.trim().to_string(),
            sort_order: sort,
            default_multiplier: multiplier,
            default_rounding: (self.rounding != "none").then(|| self.rounding.clone()),
        })
    }
}

/// `Sort order: 1  ·  × 1.15 (Rounding: 0.05)`.
pub(crate) fn zone_subtitle(z: &PriceZone) -> String {
    let base = format!("Sort order: {}", z.sort_order);
    let Some(m) = z.default_multiplier else {
        return base;
    };
    let round = match z.default_rounding.as_deref() {
        Some(r) if r != "none" => format!(" (Rounding: {r})"),
        _ => String::new(),
    };
    format!("{base}  \u{b7}  \u{d7} {}{round}", m.normalize())
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Editor {
    New,
    Edit(Uuid),
}

#[component]
pub fn ZonesSection() -> impl IntoView {
    let ctx = expect_context::<AppContext>();
    let fb = Feedback::new();
    let zones = RwSignal::new(Option::<Vec<PriceZone>>::None);
    let reload = RwSignal::new(0_u64);
    let load_error = RwSignal::new(Option::<String>::None);
    let can_write = Memo::new(move |_| {
        ctx.session.with(|s| {
            s.as_ref()
                .is_some_and(|a| a.me.has_permission("prices.write"))
        })
    });

    let editor = RwSignal::new(Option::<Editor>::None);
    let editor_gen = RwSignal::new(0_u64);
    let draft = RwSignal::new(ZoneDraft::default());
    let editor_error = RwSignal::new(Option::<String>::None);
    let saving = RwSignal::new(false);
    let confirm_delete = RwSignal::new(Option::<Uuid>::None);

    Effect::new(move |_| {
        let _ = reload.get();
        load_error.set(None);
        spawn_api(
            ctx,
            |c| async move { c.list_price_zones().await },
            move |res| match res {
                Ok(list) => {
                    set_alive(zones, Some(list));
                }
                Err(err) => {
                    set_alive(load_error, Some(err.user_message()));
                }
            },
        );
    });

    let open = move |target: Editor, d: ZoneDraft| {
        draft.set(d);
        editor_error.set(None);
        editor_gen.update(|g| *g = g.wrapping_add(1));
        editor.set(Some(target));
    };

    let on_save = move |ev: SubmitEvent| {
        ev.prevent_default();
        let Some(target) = editor.get_untracked() else {
            return;
        };
        let input = match draft.with_untracked(ZoneDraft::to_input) {
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
                    Editor::New => c.create_price_zone(&input).await,
                    Editor::Edit(id) => c.update_price_zone(id, &input).await,
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
            move |c| async move { c.delete_price_zone(id).await },
            move |res| match res {
                Ok(()) => {
                    if fb.ok("Price zone deleted") {
                        reload.update(|n| *n += 1);
                    }
                }
                Err(err) => {
                    fb.fail(err.user_message());
                }
            },
        );
    };

    view! {
        <section data-target="admin-zones" aria-labelledby="admin-zones-title">
            <div class="tc-page-header" style="margin-bottom: var(--space-sm);">
                <h2 id="admin-zones-title" class="tc-page-title" style="font-size: 18px;">"Price zones"</h2>
                <Show when=move || can_write.get()>
                    <button type="button" data-target="admin-zone-new" class="tc-btn tc-btn-primary"
                        on:click=move |_| open(Editor::New, ZoneDraft::default())>
                        "New price zone"
                    </button>
                </Show>
            </div>
            <FeedbackView fb prefix="admin-zones" />

            <Show when=move || editor.with(Option::is_some)>
                <form class="tc-card" data-target="admin-zone-editor" on:submit=on_save style="margin-bottom: var(--space-md);" aria-labelledby="admin-zone-editor-title">
                    <h3 id="admin-zone-editor-title" style="margin-top: 0;">
                        {move || if editor.get() == Some(Editor::New) { "New price zone" } else { "Edit price zone" }}
                    </h3>
                    <div class="tc-form-grid">
                        <div class="tc-field">
                            <label class="tc-label" for="admin-zone-code">"Code"</label>
                            <input id="admin-zone-code" data-target="admin-zone-code" class="tc-input" type="text"
                                prop:value=move || draft.with(|d| d.code.clone())
                                on:input=move |ev| draft.update(|d| d.code = event_target_value(&ev)) />
                        </div>
                        <div class="tc-field">
                            <label class="tc-label" for="admin-zone-name">"Name"</label>
                            <input id="admin-zone-name" data-target="admin-zone-name" class="tc-input" type="text"
                                prop:value=move || draft.with(|d| d.name.clone())
                                on:input=move |ev| draft.update(|d| d.name = event_target_value(&ev)) />
                        </div>
                        <div class="tc-field">
                            <label class="tc-label" for="admin-zone-sort">"Sort order"</label>
                            <input id="admin-zone-sort" data-target="admin-zone-sort" class="tc-input" type="text" inputmode="numeric"
                                prop:value=move || draft.with(|d| d.sort.clone())
                                on:input=move |ev| draft.update(|d| d.sort = event_target_value(&ev)) />
                        </div>
                        <div class="tc-field">
                            <label class="tc-label" for="admin-zone-multiplier">"Default multiplier"</label>
                            <input id="admin-zone-multiplier" data-target="admin-zone-multiplier" class="tc-input" type="text" inputmode="decimal"
                                aria-describedby="admin-zone-multiplier-help"
                                prop:value=move || draft.with(|d| d.multiplier.clone())
                                on:input=move |ev| draft.update(|d| d.multiplier = event_target_value(&ev)) />
                            <span id="admin-zone-multiplier-help" class="tc-label">"Relative to the first zone (e.g. 1.15 = +15%)"</span>
                        </div>
                        <div class="tc-field">
                            <label class="tc-label" for="admin-zone-rounding">"Rounding"</label>
                            <select id="admin-zone-rounding" data-target="admin-zone-rounding" class="tc-select"
                                on:change=move |ev| draft.update(|d| d.rounding = event_target_value(&ev))>
                                {ROUNDING_OPTIONS.into_iter().map(|r| view! {
                                    <option value=r selected=move || draft.with(|d| d.rounding == r)>
                                        {if r == "none" { "None" } else { r }}
                                    </option>
                                }).collect_view()}
                            </select>
                        </div>
                    </div>
                    {move || editor_error.get().map(|msg| view! {
                        <div class="tc-alert-error" style="margin-top: var(--space-md);" role="alert" data-target="admin-zone-editor-error">{msg}</div>
                    })}
                    <div class="tc-toolbar" style="margin-top: var(--space-md);">
                        <button type="submit" data-target="admin-zone-save" class="tc-btn tc-btn-primary" disabled=move || saving.get()>
                            {move || if saving.get() { "Saving..." } else { "Save" }}
                        </button>
                        <button type="button" class="tc-btn" disabled=move || saving.get() on:click=move |_| editor.set(None)>"Cancel"</button>
                    </div>
                </form>
            </Show>

            {move || load_error.get().map(|msg| view! {
                <div class="tc-alert-error" role="alert" data-target="admin-zones-load-error" style="margin-bottom: var(--space-md);">
                    {msg}
                    " "
                    <button type="button" class="tc-btn tc-btn-sm" data-target="admin-zones-retry" on:click=move |_| reload.update(|n| *n += 1)>"Retry"</button>
                </div>
            })}

            {move || match zones.get() {
                None => view! { <p class="tc-label">"Loading price zones..."</p> }.into_any(),
                Some(list) if list.is_empty() => view! { <p data-target="admin-zones-empty">"No price zones yet."</p> }.into_any(),
                Some(list) => view! {
                    <ul data-target="admin-zones-list" style="list-style: none; margin: 0; padding: 0;">
                        {list.into_iter().map(|z| {
                            let id = z.id;
                            let code = z.code.clone();
                            let row_target = format!("admin-zone-{code}");
                            let title = format!("{}  {}", z.code, z.name);
                            let subtitle = zone_subtitle(&z);
                            let draft_of = ZoneDraft::from_zone(&z);
                            let question = format!("Delete price zone {}? This is refused when prices or customers use it.", z.code);
                            view! {
                                <li class="tc-card" style="margin-bottom: var(--space-sm);" data-target=row_target>
                                    <div style="display: flex; align-items: center; gap: var(--space-sm); flex-wrap: wrap;">
                                        <div style="flex: 1; min-width: 200px;">
                                            <strong>{title}</strong>
                                            <div class="tc-label">{subtitle}</div>
                                        </div>
                                        <Show when=move || can_write.get()>
                                            {
                                                let draft_of = draft_of.clone();
                                                let code = code.clone();
                                                view! {
                                                    <button type="button" class="tc-btn tc-btn-sm" data-target=format!("admin-zone-edit-{code}")
                                                        aria-label=format!("Edit price zone {code}")
                                                        on:click=move |_| open(Editor::Edit(id), draft_of.clone())>"Edit"</button>
                                                    <button type="button" class="tc-btn tc-btn-sm" data-target=format!("admin-zone-delete-{code}")
                                                        aria-label=format!("Delete price zone {code}")
                                                        on:click=move |_| confirm_delete.set(Some(id))>"Delete"</button>
                                                }
                                            }
                                        </Show>
                                    </div>
                                    <Show when=move || confirm_delete.get() == Some(id)>
                                        <div class="tc-toolbar" role="alert" style="margin-top: var(--space-sm);">
                                            <span>{question.clone()}</span>
                                            <button type="button" class="tc-btn tc-btn-primary tc-btn-sm" data-target="admin-zone-delete-confirm"
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
    fn validates_like_flutter() {
        let mut d = ZoneDraft::default();
        assert_eq!(d.to_input().unwrap_err(), "Code and name are required.");
        d.code = " B ".into();
        d.name = "Export".into();
        d.sort = "x".into();
        assert_eq!(
            d.to_input().unwrap_err(),
            "Sort order must be a whole number."
        );
        d.sort = "2".into();
        d.multiplier = "0".into();
        assert!(d.to_input().is_err());
        d.multiplier = "1,15".into();
        d.rounding = "0.05".into();
        let input = d.to_input().unwrap();
        assert_eq!(input.code, "B");
        assert_eq!(input.default_multiplier.unwrap().to_string(), "1.15");
        assert_eq!(input.default_rounding.as_deref(), Some("0.05"));
        d.rounding = "none".into();
        assert_eq!(d.to_input().unwrap().default_rounding, None);
    }

    #[test]
    fn subtitle_shows_multiplier_and_rounding() {
        let mut z = PriceZone {
            id: Uuid::nil(),
            code: "B".into(),
            name: "Export".into(),
            sort_order: 1,
            default_multiplier: None,
            default_rounding: None,
        };
        assert_eq!(zone_subtitle(&z), "Sort order: 1");
        z.default_multiplier = Some("1.1500".parse().unwrap());
        z.default_rounding = Some("0.05".into());
        assert_eq!(
            zone_subtitle(&z),
            "Sort order: 1  \u{b7}  \u{d7} 1.15 (Rounding: 0.05)"
        );
    }
}
