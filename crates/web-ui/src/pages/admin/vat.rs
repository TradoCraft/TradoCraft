//! Administration, section "VAT rates": country-specific, temporal and building-age VAT rules.
//! Mirrors `vat_rates_page.dart`.

use std::str::FromStr;

use chrono::NaiveDate;
use leptos::ev::SubmitEvent;
use leptos::prelude::*;
use rust_decimal::Decimal;
use tradocraft_api_client::vat::{CountryVatRate, CountryVatRateInput};
use uuid::Uuid;

use super::{spawn_api, Feedback, FeedbackView};
use crate::pages::set_alive;
use crate::state::AppContext;

const CATEGORIES: [&str; 5] = [
    "standard",
    "intermediate",
    "reduced",
    "zero",
    "construction",
];

pub(crate) fn category_label(category: &str) -> &str {
    match category {
        "standard" => "Standard",
        "intermediate" => "Intermediate",
        "reduced" => "Reduced",
        "zero" => "Zero rate",
        "construction" => "Construction (renovation)",
        other => other,
    }
}

/// A strict `YYYY-MM-DD` date.
fn parse_iso_date(raw: &str) -> Option<NaiveDate> {
    let t = raw.trim();
    if t.len() != 10 {
        return None;
    }
    NaiveDate::parse_from_str(t, "%Y-%m-%d").ok()
}

/// What the VAT rate editor holds.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct VatDraft {
    pub country: String,
    pub category: String,
    pub rate: String,
    pub min_age: String,
    pub start: String,
    pub end: String,
    pub notes: String,
    pub close_previous: bool,
}

impl VatDraft {
    fn new(country: &str, today: &str) -> Self {
        Self {
            country: country.to_string(),
            category: "standard".into(),
            rate: String::new(),
            min_age: String::new(),
            start: today.to_string(),
            end: String::new(),
            notes: String::new(),
            close_previous: true,
        }
    }

    fn from_rule(r: &CountryVatRate) -> Self {
        Self {
            country: r.country_code.clone(),
            category: r.category.clone(),
            rate: r.rate.normalize().to_string(),
            min_age: r
                .min_building_age_years
                .map(|a| a.to_string())
                .unwrap_or_default(),
            start: r.start_date.to_string(),
            end: r.end_date.map(|d| d.to_string()).unwrap_or_default(),
            notes: r.notes.clone(),
            close_previous: false,
        }
    }

    /// Validates like Flutter does and builds the request; `creating` sends `close_previous`.
    pub fn to_input(&self, creating: bool) -> Result<CountryVatRateInput, String> {
        let cc = self.country.trim().to_uppercase();
        if cc.chars().count() != 2 {
            return Err("The country code must have two letters.".into());
        }
        let rate = Decimal::from_str(self.rate.trim().replace(',', ".").as_str())
            .map_err(|_| "The rate must be a number.".to_string())?;
        let start = parse_iso_date(&self.start)
            .ok_or_else(|| "The start date must be a date (YYYY-MM-DD).".to_string())?;
        let end = if self.end.trim().is_empty() {
            None
        } else {
            Some(
                parse_iso_date(&self.end)
                    .ok_or_else(|| "The end date must be a date (YYYY-MM-DD).".to_string())?,
            )
        };
        let min_age = if self.category == "construction" {
            match self.min_age.trim().parse::<i32>() {
                Ok(a) if (1..=200).contains(&a) => Some(a),
                _ => {
                    return Err(
                        "The minimum building age must be a whole number from 1 to 200.".into(),
                    )
                }
            }
        } else {
            None
        };
        Ok(CountryVatRateInput {
            country_code: cc,
            category: self.category.clone(),
            rate,
            min_building_age_years: min_age,
            start_date: Some(start),
            end_date: end,
            notes: self.notes.trim().to_string(),
            close_previous: creating.then_some(self.close_previous),
        })
    }
}

/// `BE · Standard · 21 %`.
fn rule_title(r: &CountryVatRate) -> String {
    format!(
        "{} \u{b7} {} \u{b7} {} %",
        r.country_code,
        category_label(&r.category),
        r.rate.normalize()
    )
}

/// The period, building age and notes of a rule.
fn rule_subtitle(r: &CountryVatRate) -> String {
    let mut parts = vec![format!(
        "{} \u{2013} {}",
        r.start_date,
        r.end_date
            .map(|d| d.to_string())
            .unwrap_or_else(|| "Ongoing".into())
    )];
    if let Some(a) = r.min_building_age_years {
        parts.push(format!("Min. building age (years): \u{2265} {a}"));
    }
    if !r.notes.is_empty() {
        parts.push(r.notes.clone());
    }
    parts.join(" \u{b7} ")
}

#[cfg(target_arch = "wasm32")]
fn today_iso() -> String {
    let now = js_sys::Date::new_0();
    format!(
        "{:04}-{:02}-{:02}",
        now.get_full_year(),
        now.get_month() + 1,
        now.get_date()
    )
}

#[cfg(not(target_arch = "wasm32"))]
fn today_iso() -> String {
    String::new()
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Editor {
    New,
    Edit(Uuid),
}

#[component]
pub fn VatSection() -> impl IntoView {
    let ctx = expect_context::<AppContext>();
    let fb = Feedback::new();

    let rules = RwSignal::new(Option::<Vec<CountryVatRate>>::None);
    let reload = RwSignal::new(0_u64);
    let load_error = RwSignal::new(Option::<String>::None);
    let company_country = Memo::new(move |_| {
        ctx.session
            .with(|s| s.as_ref().map(|a| a.me.company.country_code.clone()))
            .unwrap_or_else(|| "BE".into())
    });
    let can_edit = Memo::new(move |_| {
        ctx.session.with(|s| {
            s.as_ref()
                .is_some_and(|a| a.me.has_permission("users.admin"))
        })
    });
    let country_filter = RwSignal::new(company_country.get_untracked());

    let editor = RwSignal::new(Option::<Editor>::None);
    let editor_gen = RwSignal::new(0_u64);
    let draft = RwSignal::new(VatDraft::new("", ""));
    let editor_error = RwSignal::new(Option::<String>::None);
    let saving = RwSignal::new(false);
    let confirm_delete = RwSignal::new(Option::<Uuid>::None);

    Effect::new(move |_| {
        let _ = reload.get();
        load_error.set(None);
        spawn_api(
            ctx,
            |c| async move { c.list_vat_rates().await },
            move |res| match res {
                Ok(list) => {
                    set_alive(rules, Some(list));
                }
                Err(err) => {
                    set_alive(load_error, Some(err.user_message()));
                }
            },
        );
    });

    let countries = Memo::new(move |_| {
        let mut list: Vec<String> =
            rules.with(|r| r.iter().flatten().map(|r| r.country_code.clone()).collect());
        list.sort();
        list.dedup();
        list
    });
    // A filter on a country without rules shows everything.
    let filter = Memo::new(move |_| {
        let f = country_filter.get();
        if countries.with(|c| c.contains(&f)) {
            f
        } else {
            String::new()
        }
    });
    let visible = Memo::new(move |_| {
        let f = filter.get();
        rules.with(|r| {
            r.iter()
                .flatten()
                .filter(|r| f.is_empty() || r.country_code == f)
                .cloned()
                .collect::<Vec<_>>()
        })
    });

    let open = move |target: Editor, d: VatDraft| {
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
        let input = match draft.with_untracked(|d| d.to_input(target == Editor::New)) {
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
                    Editor::New => c.create_vat_rate(&input).await,
                    Editor::Edit(id) => c.update_vat_rate(id, &input).await,
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
            move |c| async move { c.delete_vat_rate(id).await },
            move |res| match res {
                Ok(()) => {
                    if fb.ok("Saved") {
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
        <section data-target="admin-vat" aria-labelledby="admin-vat-title">
            <div class="tc-page-header" style="margin-bottom: var(--space-sm);">
                <h2 id="admin-vat-title" class="tc-page-title" style="font-size: 18px;">"Country VAT rates"</h2>
                <Show when=move || can_edit.get()>
                    <button
                        type="button"
                        data-target="admin-vat-add"
                        class="tc-btn tc-btn-primary"
                        on:click=move |_| {
                            let f = filter.get_untracked();
                            let country = if f.is_empty() { company_country.get_untracked() } else { f };
                            open(Editor::New, VatDraft::new(&country, &today_iso()));
                        }
                    >
                        "Add VAT rate"
                    </button>
                </Show>
            </div>
            <FeedbackView fb prefix="admin-vat" />

            <Show when=move || editor.with(Option::is_some)>
                <form class="tc-card" data-target="admin-vat-editor" on:submit=on_save style="margin-bottom: var(--space-md);" aria-labelledby="admin-vat-editor-title">
                    <h3 id="admin-vat-editor-title" style="margin-top: 0;">
                        {move || if editor.get() == Some(Editor::New) { "Add VAT rate" } else { "Edit VAT rate" }}
                    </h3>
                    <div class="tc-form-grid">
                        <div class="tc-field">
                            <label class="tc-label" for="admin-vat-country">"Country code"</label>
                            <input id="admin-vat-country" data-target="admin-vat-country" class="tc-input" type="text" maxlength="2"
                                style="text-transform: uppercase;"
                                prop:value=move || draft.with(|d| d.country.clone())
                                on:input=move |ev| draft.update(|d| d.country = event_target_value(&ev)) />
                        </div>
                        <div class="tc-field">
                            <label class="tc-label" for="admin-vat-category">"Category"</label>
                            <select id="admin-vat-category" data-target="admin-vat-category" class="tc-select"
                                on:change=move |ev| draft.update(|d| d.category = event_target_value(&ev))>
                                {CATEGORIES.into_iter().map(|c| view! {
                                    <option value=c selected=move || draft.with(|d| d.category == c)>{category_label(c).to_string()}</option>
                                }).collect_view()}
                            </select>
                        </div>
                        <div class="tc-field">
                            <label class="tc-label" for="admin-vat-rate">"Rate (%)"</label>
                            <input id="admin-vat-rate" data-target="admin-vat-rate" class="tc-input" type="text" inputmode="decimal"
                                prop:value=move || draft.with(|d| d.rate.clone())
                                on:input=move |ev| draft.update(|d| d.rate = event_target_value(&ev)) />
                        </div>
                        <Show when=move || draft.with(|d| d.category == "construction")>
                            <div class="tc-field">
                                <label class="tc-label" for="admin-vat-min-age">"Min. building age (years)"</label>
                                <input id="admin-vat-min-age" data-target="admin-vat-min-age" class="tc-input" type="text" inputmode="numeric"
                                    prop:value=move || draft.with(|d| d.min_age.clone())
                                    on:input=move |ev| draft.update(|d| d.min_age = event_target_value(&ev)) />
                            </div>
                        </Show>
                        <div class="tc-field">
                            <label class="tc-label" for="admin-vat-start">"Start date (YYYY-MM-DD)"</label>
                            <input id="admin-vat-start" data-target="admin-vat-start" class="tc-input" type="text"
                                prop:value=move || draft.with(|d| d.start.clone())
                                on:input=move |ev| draft.update(|d| d.start = event_target_value(&ev)) />
                        </div>
                        <div class="tc-field">
                            <label class="tc-label" for="admin-vat-end">"End date (optional)"</label>
                            <input id="admin-vat-end" data-target="admin-vat-end" class="tc-input" type="text"
                                prop:value=move || draft.with(|d| d.end.clone())
                                on:input=move |ev| draft.update(|d| d.end = event_target_value(&ev)) />
                        </div>
                        <div class="tc-field tc-form-span-2">
                            <label class="tc-label" for="admin-vat-notes">"Notes"</label>
                            <input id="admin-vat-notes" data-target="admin-vat-notes" class="tc-input" type="text"
                                prop:value=move || draft.with(|d| d.notes.clone())
                                on:input=move |ev| draft.update(|d| d.notes = event_target_value(&ev)) />
                        </div>
                    </div>
                    <Show when=move || editor.get() == Some(Editor::New)>
                        <label class="tc-checkbox-row" style="margin-top: var(--space-sm);">
                            <input type="checkbox" data-target="admin-vat-close-previous"
                                prop:checked=move || draft.with(|d| d.close_previous)
                                on:change=move |ev| {
                                    let on = event_target_checked(&ev);
                                    draft.update(|d| d.close_previous = on);
                                } />
                            "Close previous open rule automatically"
                        </label>
                    </Show>
                    {move || editor_error.get().map(|msg| view! {
                        <div class="tc-alert-error" style="margin-top: var(--space-md);" role="alert" data-target="admin-vat-editor-error">{msg}</div>
                    })}
                    <div class="tc-toolbar" style="margin-top: var(--space-md);">
                        <button type="submit" data-target="admin-vat-save" class="tc-btn tc-btn-primary" disabled=move || saving.get()>
                            {move || if saving.get() { "Saving..." } else { "Save" }}
                        </button>
                        <button type="button" class="tc-btn" disabled=move || saving.get() on:click=move |_| editor.set(None)>"Cancel"</button>
                    </div>
                </form>
            </Show>

            {move || load_error.get().map(|msg| view! {
                <div class="tc-alert-error" role="alert" data-target="admin-vat-load-error" style="margin-bottom: var(--space-md);">
                    {msg}
                    " "
                    <button type="button" class="tc-btn tc-btn-sm" on:click=move |_| reload.update(|n| *n += 1)>"Retry"</button>
                </div>
            })}

            <div class="tc-field" style="max-width: 240px; margin-bottom: var(--space-md);">
                <label class="tc-label" for="admin-vat-filter">"Country code"</label>
                <select id="admin-vat-filter" data-target="admin-vat-filter" class="tc-select"
                    on:change=move |ev| country_filter.set(event_target_value(&ev))>
                    <option value="" selected=move || filter.get().is_empty()>"All"</option>
                    {move || countries.get().into_iter().map(|c| {
                        let c_sel = c.clone();
                        let c_val = c.clone();
                        view! { <option value=c_val selected=move || filter.get() == c_sel>{c}</option> }
                    }).collect_view()}
                </select>
            </div>

            <Show
                when=move || rules.with(Option::is_some)
                fallback=|| view! { <p class="tc-label">"Loading VAT rates..."</p> }
            >
                <ul data-target="admin-vat-list" style="list-style: none; margin: 0; padding: 0;">
                    <For
                        each=move || visible.get()
                        key=|r| format!("{}:{}", r.id, r.updated_at)
                        children=move |r| {
                            let id = r.id;
                            let title = rule_title(&r);
                            let subtitle = rule_subtitle(&r);
                            let draft_of = VatDraft::from_rule(&r);
                            let question = format!(
                                "Delete VAT rate rule for {} ({})?",
                                r.country_code,
                                category_label(&r.category)
                            );
                            view! {
                                <li class="tc-card" style="margin-bottom: var(--space-sm);" data-target=format!("admin-vat-rate-{id}")>
                                    <div style="display: flex; align-items: center; gap: var(--space-sm); flex-wrap: wrap;">
                                        <div style="flex: 1; min-width: 200px;">
                                            <strong data-target="admin-vat-rate-title">{title.clone()}</strong>
                                            <div class="tc-label">{subtitle}</div>
                                        </div>
                                        <Show when=move || can_edit.get()>
                                            {
                                                let draft_of = draft_of.clone();
                                                let title = title.clone();
                                                view! {
                                                    <button type="button" class="tc-btn tc-btn-sm" data-target=format!("admin-vat-edit-{id}")
                                                        aria-label=format!("Edit {title}")
                                                        on:click=move |_| open(Editor::Edit(id), draft_of.clone())>
                                                        "Edit"
                                                    </button>
                                                    <button type="button" class="tc-btn tc-btn-sm" data-target=format!("admin-vat-delete-{id}")
                                                        aria-label=format!("Delete {title}")
                                                        on:click=move |_| confirm_delete.set(Some(id))>
                                                        "Delete"
                                                    </button>
                                                }
                                            }
                                        </Show>
                                    </div>
                                    <Show when=move || confirm_delete.get() == Some(id)>
                                        <div class="tc-toolbar" role="alert" style="margin-top: var(--space-sm);">
                                            <span>{question.clone()}</span>
                                            <button type="button" class="tc-btn tc-btn-primary tc-btn-sm" data-target=format!("admin-vat-delete-confirm-{id}")
                                                on:click=move |_| on_delete(id)>
                                                "Delete"
                                            </button>
                                            <button type="button" class="tc-btn tc-btn-sm" on:click=move |_| confirm_delete.set(None)>"Cancel"</button>
                                        </div>
                                    </Show>
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

    fn draft() -> VatDraft {
        VatDraft {
            rate: "21".into(),
            ..VatDraft::new("be", "2026-01-01")
        }
    }

    #[test]
    fn builds_a_create_request() {
        let input = draft().to_input(true).unwrap();
        assert_eq!(input.country_code, "BE");
        assert_eq!(input.rate, Decimal::from(21));
        assert_eq!(input.start_date, NaiveDate::from_ymd_opt(2026, 1, 1));
        assert_eq!(input.close_previous, Some(true));
        assert_eq!(input.min_building_age_years, None);
        assert_eq!(draft().to_input(false).unwrap().close_previous, None);
    }

    #[test]
    fn validates_country_rate_dates_and_building_age() {
        let mut d = draft();
        d.country = "BEL".into();
        assert!(d.to_input(true).unwrap_err().contains("two letters"));
        let mut d = draft();
        d.rate = "x".into();
        assert!(d.to_input(true).unwrap_err().contains("rate"));
        let mut d = draft();
        d.start = "2026-02-30".into();
        assert!(d.to_input(true).unwrap_err().contains("start date"));
        let mut d = draft();
        d.end = "soon".into();
        assert!(d.to_input(true).unwrap_err().contains("end date"));
        let mut d = draft();
        d.category = "construction".into();
        d.min_age = "0".into();
        assert!(d.to_input(true).unwrap_err().contains("building age"));
        d.min_age = "10".into();
        assert_eq!(d.to_input(true).unwrap().min_building_age_years, Some(10));
    }

    #[test]
    fn decimal_comma_is_accepted() {
        let mut d = draft();
        d.rate = "5,5".into();
        assert_eq!(d.to_input(true).unwrap().rate.to_string(), "5.5");
    }
}
