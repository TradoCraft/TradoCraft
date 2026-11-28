//! First-company bootstrap setup wizard (`/setup`, ADR 0047).

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use leptos::prelude::*;
use leptos::task::spawn_local;
use leptos_router::components::A;
use leptos_router::hooks::use_navigate;
use leptos_router::NavigateOptions;
use tradocraft_api_client::setup::{BootstrapRequest, BootstrapResult, SetupStatus};
use tradocraft_api_client::{Auth, Client};

use crate::api::{resolve_base_url, ApiClient, ConnectionMode, WebApiClient};
use crate::components::shell::app_href;
use crate::i18n::tr;
use crate::pages::{opt_trimmed, set_alive};
use crate::state::{ActiveSession, AppContext};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SetupStep {
    Company,
    Region,
    Admin,
    Token,
    Review,
}

impl SetupStep {
    pub fn key(self) -> &'static str {
        match self {
            Self::Company => "company",
            Self::Region => "region",
            Self::Admin => "admin",
            Self::Token => "token",
            Self::Review => "review",
        }
    }

    pub fn label(self) -> &'static str {
        match self {
            Self::Company => "Company",
            Self::Region => "Region",
            Self::Admin => "Administrator",
            Self::Token => "Setup token",
            Self::Review => "Review",
        }
    }
}

/// Ordered steps for the setup wizard; omits `Token` when the server does not require one.
pub fn setup_steps(token_required: bool) -> Vec<SetupStep> {
    if token_required {
        vec![
            SetupStep::Company,
            SetupStep::Region,
            SetupStep::Admin,
            SetupStep::Token,
            SetupStep::Review,
        ]
    } else {
        vec![
            SetupStep::Company,
            SetupStep::Region,
            SetupStep::Admin,
            SetupStep::Review,
        ]
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SetupDraft {
    pub name: String,
    pub legal_name: String,
    pub vat_number: String,
    pub country_code: String,
    pub currency: String,
    pub default_language: String,
    pub admin_email: String,
    pub admin_display_name: String,
    pub token: String,
}

impl Default for SetupDraft {
    fn default() -> Self {
        Self {
            name: String::new(),
            legal_name: String::new(),
            vat_number: String::new(),
            country_code: "BE".to_string(),
            currency: "EUR".to_string(),
            default_language: "en".to_string(),
            admin_email: String::new(),
            admin_display_name: String::new(),
            token: String::new(),
        }
    }
}

fn valid_email(raw: &str) -> bool {
    let trimmed = raw.trim();
    let Some((local, domain)) = trimmed.split_once('@') else {
        return false;
    };
    trimmed.len() <= 254
        && !trimmed.contains(char::is_whitespace)
        && !local.is_empty()
        && !domain.contains('@')
        && domain.contains('.')
        && domain.split('.').all(|label| !label.is_empty())
}

/// Validates the fields of `step` (or all steps for `SetupStep::Review`) before advancing.
pub fn validate_step(
    step: SetupStep,
    draft: &SetupDraft,
    token_required: bool,
) -> Result<(), String> {
    match step {
        SetupStep::Company => {
            let name = draft.name.trim();
            if name.is_empty() || name.chars().count() > 200 {
                return Err("Company name is required (at most 200 characters).".to_string());
            }
            if draft.legal_name.trim().chars().count() > 200 {
                return Err("Legal name is at most 200 characters.".to_string());
            }
            if let Some(vat) = opt_trimmed(&draft.vat_number) {
                let normalized: String = vat.replace([' ', '.', '-'], "").to_ascii_uppercase();
                if !(4..=20).contains(&normalized.len())
                    || !normalized.chars().all(|c| c.is_ascii_alphanumeric())
                {
                    return Err("VAT number must be 4 to 20 letters and digits.".to_string());
                }
            }
            Ok(())
        }
        SetupStep::Region => {
            let country = draft.country_code.trim();
            if country.len() != 2 || !country.chars().all(|c| c.is_ascii_alphabetic()) {
                return Err("Country code must be two letters (e.g. BE).".to_string());
            }
            let currency = draft.currency.trim();
            if currency.len() != 3 || !currency.chars().all(|c| c.is_ascii_alphabetic()) {
                return Err("Currency must be three letters (e.g. EUR).".to_string());
            }
            let lang = draft.default_language.trim();
            if lang.len() != 2 || !lang.chars().all(|c| c.is_ascii_alphabetic()) {
                return Err(
                    "Default language must be a two-letter ISO 639-1 code (e.g. en).".to_string(),
                );
            }
            Ok(())
        }
        SetupStep::Admin => {
            if !valid_email(&draft.admin_email) {
                return Err("Administrator e-mail is not a valid e-mail address.".to_string());
            }
            let display = draft.admin_display_name.trim();
            if display.is_empty() || display.chars().count() > 200 {
                return Err(
                    "Administrator display name is required (at most 200 characters).".to_string(),
                );
            }
            Ok(())
        }
        SetupStep::Token => {
            if token_required && draft.token.trim().is_empty() {
                return Err("Setup token is required by this server.".to_string());
            }
            Ok(())
        }
        SetupStep::Review => {
            validate_step(SetupStep::Company, draft, token_required)?;
            validate_step(SetupStep::Region, draft, token_required)?;
            validate_step(SetupStep::Admin, draft, token_required)?;
            validate_step(SetupStep::Token, draft, token_required)
        }
    }
}

/// Converts the wizard form draft into the `BootstrapRequest` payload.
pub fn build_bootstrap_request(draft: &SetupDraft, token_required: bool) -> BootstrapRequest {
    BootstrapRequest {
        name: draft.name.trim().to_string(),
        legal_name: opt_trimmed(&draft.legal_name),
        vat_number: opt_trimmed(&draft.vat_number)
            .map(|v| v.replace([' ', '.', '-'], "").to_ascii_uppercase()),
        country_code: draft.country_code.trim().to_ascii_uppercase(),
        currency: draft.currency.trim().to_ascii_uppercase(),
        default_language: draft.default_language.trim().to_ascii_lowercase(),
        languages: Vec::new(),
        admin_email: draft.admin_email.trim().to_ascii_lowercase(),
        admin_display_name: draft.admin_display_name.trim().to_string(),
        token: if token_required {
            opt_trimmed(&draft.token)
        } else {
            None
        },
    }
}

#[component]
pub fn SetupPage() -> impl IntoView {
    let ctx = expect_context::<AppContext>();
    let navigate = use_navigate();

    let initial_base = match ctx.draft_connection.get_untracked() {
        ConnectionMode::Live(s) => s.base_url,
        ConnectionMode::MockDemo => String::new(),
    };
    let base_url = RwSignal::new(initial_base);
    let probing = RwSignal::new(true);
    let status = RwSignal::new(Option::<SetupStatus>::None);
    let status_error = RwSignal::new(Option::<String>::None);
    let reload = RwSignal::new(0_u64);
    let probe_gen = StoredValue::new(0_u64);

    let step_idx = RwSignal::new(0_usize);
    let draft = RwSignal::new(SetupDraft::default());
    let submit_error = RwSignal::new(Option::<String>::None);
    let busy = RwSignal::new(false);
    let completed = RwSignal::new(Option::<BootstrapResult>::None);

    let active = Arc::new(AtomicBool::new(true));
    on_cleanup({
        let active = Arc::clone(&active);
        move || {
            active.store(false, Ordering::Release);
        }
    });

    Effect::new(move |_| {
        let _ = reload.get();
        let req_gen = probe_gen
            .try_update_value(|g| {
                *g = g.wrapping_add(1);
                *g
            })
            .unwrap_or(0);
        let resolved = resolve_base_url(&base_url.get_untracked());
        if resolved.is_empty() {
            probing.set(false);
            status.set(None);
            status_error.set(Some(
                "Enter the API base URL to check setup status.".to_string(),
            ));
            return;
        }
        probing.set(true);
        status_error.set(None);
        spawn_local(async move {
            let res = Client::new(resolved).setup_status().await;
            if probe_gen.try_get_value() != Some(req_gen) {
                return;
            }
            if !set_alive(probing, false) {
                return;
            }
            match res {
                Ok(info) => {
                    step_idx.set(0);
                    submit_error.set(None);
                    status.set(Some(info));
                }
                Err(err) => {
                    status.set(None);
                    status_error.set(Some(err.user_message()));
                }
            }
        });
    });

    let on_next = move |_| {
        let Some(info) = status.get_untracked() else {
            return;
        };
        let steps = setup_steps(info.token_required);
        let idx = step_idx.get_untracked();
        let Some(&current) = steps.get(idx) else {
            return;
        };
        let d = draft.get_untracked();
        match validate_step(current, &d, info.token_required) {
            Ok(()) => {
                submit_error.set(None);
                if idx + 1 < steps.len() {
                    step_idx.set(idx + 1);
                }
            }
            Err(msg) => submit_error.set(Some(msg)),
        }
    };

    let on_back = move |_| {
        submit_error.set(None);
        step_idx.update(|i| *i = i.saturating_sub(1));
    };

    let on_submit = {
        let active = Arc::clone(&active);
        let navigate = navigate.clone();
        move |_| {
            if busy.get_untracked() {
                return;
            }
            let Some(info) = status.get_untracked() else {
                return;
            };
            let d = draft.get_untracked();
            if let Err(msg) = validate_step(SetupStep::Review, &d, info.token_required) {
                submit_error.set(Some(msg));
                return;
            }
            let raw_base = base_url.get_untracked();
            let resolved = resolve_base_url(&raw_base);
            let req = build_bootstrap_request(&d, info.token_required);
            busy.set(true);
            submit_error.set(None);

            let active = Arc::clone(&active);
            let nav = navigate.clone();
            spawn_local(async move {
                let res = Client::new(resolved).bootstrap_company(&req).await;
                if !active.load(Ordering::Acquire) {
                    return;
                }
                match res {
                    Ok(created) => {
                        if created.is_dev() {
                            let email = created.admin.email.clone();
                            match WebApiClient.sign_in(&raw_base, Auth::DevUser(email)).await {
                                Ok((connection, me)) => {
                                    if !active.load(Ordering::Acquire) {
                                        return;
                                    }
                                    ctx.draft_connection.set(connection.clone());
                                    ctx.session.set(Some(ActiveSession { connection, me }));
                                    busy.set(false);
                                    nav("/home", NavigateOptions::default());
                                    return;
                                }
                                Err(_) => {
                                    if !active.load(Ordering::Acquire) {
                                        return;
                                    }
                                }
                            }
                        }
                        busy.set(false);
                        completed.set(Some(created));
                    }
                    Err(err) => {
                        busy.set(false);
                        submit_error.set(Some(err.user_message()));
                    }
                }
            });
        }
    };

    view! {
        <div class="tc-setup-wrap" data-target="setup-page">
            <div class="tc-card tc-setup-card">
                <div class="tc-brand">
                    <span class="tc-brand-mark">"TC"</span>
                    <div>
                        <div style="font-size: 18px; font-weight: 600;">
                            {move || tr("setup.title", "First-company setup")}
                        </div>
                        <div style="font-size: 12px; color: var(--on-surface-variant);">
                            "Provision the initial legal entity and administrator account (ADR 0047)"
                        </div>
                    </div>
                </div>

                <div class="tc-field">
                    <label class="tc-label" for="setup-base-url">"API Base URL (blank uses current origin)"</label>
                    <div style="display: flex; gap: var(--space-sm);">
                        <input
                            id="setup-base-url"
                            data-target="setup-base-url"
                            class="tc-input tc-mono"
                            style="flex: 1;"
                            type="text"
                            placeholder="http://127.0.0.1:8080 or leave empty"
                            prop:value=move || base_url.get()
                            on:input=move |ev| base_url.set(event_target_value(&ev))
                        />
                        <button
                            type="button"
                            class="tc-btn tc-btn-sm"
                            data-target="setup-check-server"
                            on:click=move |_| reload.update(|n| *n += 1)
                        >
                            "Check"
                        </button>
                    </div>
                </div>

                {move || {
                    if let Some(created) = completed.get() {
                        return view! {
                            <div style="display: flex; flex-direction: column; gap: var(--space-md);" data-target="setup-complete">
                                <div class="tc-alert-success" role="status">
                                    {format!("Company '{}' created with administrator {}.", created.company.name, created.admin.email)}
                                </div>
                                <p style="margin: 0; color: var(--on-surface-variant);">
                                    {if created.is_dev() {
                                        "You can now sign in with development authentication."
                                    } else {
                                        "Sign in through your configured identity provider using this administrator e-mail."
                                    }}
                                </p>
                                <div>
                                    <A href=app_href("/login") attr:class="tc-btn tc-btn-primary" attr:data-target="setup-go-login">
                                        {move || tr("setup.go_login", "Go to sign in")}
                                    </A>
                                </div>
                            </div>
                        }.into_any();
                    }

                    if probing.get() {
                        return view! {
                            <div data-target="setup-loading" style="color: var(--on-surface-variant);">
                                "Checking server setup status..."
                            </div>
                        }.into_any();
                    }

                    if let Some(err) = status_error.get() {
                        return view! {
                            <div style="display: flex; flex-direction: column; gap: var(--space-md);" data-target="setup-status-error">
                                <div class="tc-alert-error" role="alert">{err}</div>
                                <div>
                                    <button
                                        type="button"
                                        class="tc-btn tc-btn-sm"
                                        data-target="setup-retry"
                                        on:click=move |_| reload.update(|n| *n += 1)
                                    >
                                        "Retry"
                                    </button>
                                </div>
                            </div>
                        }.into_any();
                    }

                    let Some(info) = status.get() else {
                        return view! { <div></div> }.into_any();
                    };

                    if !info.needs_setup {
                        return view! {
                            <div style="display: flex; flex-direction: column; gap: var(--space-md);" data-target="setup-already-done">
                                <div style="color: var(--on-surface-variant);">
                                    {move || tr("setup.already_done", "This server already has a company configured.")}
                                </div>
                                <div>
                                    <A href=app_href("/login") attr:class="tc-btn tc-btn-primary" attr:data-target="setup-go-login">
                                        {move || tr("setup.go_login", "Go to sign in")}
                                    </A>
                                </div>
                            </div>
                        }.into_any();
                    }

                    let steps = setup_steps(info.token_required);
                    let idx = step_idx.get().min(steps.len().saturating_sub(1));
                    let current = steps[idx];
                    let is_last = idx + 1 >= steps.len();

                    view! {
                        <div style="display: flex; flex-direction: column; gap: var(--space-lg);">
                            <div class="tc-setup-steps" data-target="setup-steps">
                                {steps.iter().enumerate().map(|(i, s)| {
                                    let cls = if i == idx {
                                        "tc-setup-step tc-setup-step-active"
                                    } else if i < idx {
                                        "tc-setup-step tc-setup-step-done"
                                    } else {
                                        "tc-setup-step"
                                    };
                                    let target = format!("setup-step-{}", s.key());
                                    view! {
                                        <span class=cls data-target=target>
                                            {format!("{}. {}", i + 1, s.label())}
                                        </span>
                                    }
                                }).collect_view()}
                            </div>

                            {move || submit_error.get().map(|msg| view! {
                                <div class="tc-alert-error" role="alert" data-target="setup-error">{msg}</div>
                            })}

                            {match current {
                                SetupStep::Company => view! {
                                    <div class="tc-form-grid">
                                        <div class="tc-field tc-form-span-2">
                                            <label class="tc-label" for="setup-name">"Company name *"</label>
                                            <input
                                                id="setup-name"
                                                data-target="setup-name"
                                                class="tc-input"
                                                type="text"
                                                prop:value=move || draft.with(|d| d.name.clone())
                                                on:input=move |ev| draft.update(|d| d.name = event_target_value(&ev))
                                            />
                                        </div>
                                        <div class="tc-field tc-form-span-2">
                                            <label class="tc-label" for="setup-legal-name">"Legal name (optional)"</label>
                                            <input
                                                id="setup-legal-name"
                                                data-target="setup-legal-name"
                                                class="tc-input"
                                                type="text"
                                                prop:value=move || draft.with(|d| d.legal_name.clone())
                                                on:input=move |ev| draft.update(|d| d.legal_name = event_target_value(&ev))
                                            />
                                        </div>
                                        <div class="tc-field tc-form-span-2">
                                            <label class="tc-label" for="setup-vat">"VAT number (optional)"</label>
                                            <input
                                                id="setup-vat"
                                                data-target="setup-vat"
                                                class="tc-input tc-mono"
                                                type="text"
                                                placeholder="BE0123456749"
                                                prop:value=move || draft.with(|d| d.vat_number.clone())
                                                on:input=move |ev| draft.update(|d| d.vat_number = event_target_value(&ev))
                                            />
                                        </div>
                                    </div>
                                }.into_any(),
                                SetupStep::Region => view! {
                                    <div class="tc-form-grid">
                                        <div class="tc-field">
                                            <label class="tc-label" for="setup-country">"Country code (ISO 2) *"</label>
                                            <input
                                                id="setup-country"
                                                data-target="setup-country"
                                                class="tc-input tc-mono"
                                                maxlength="2"
                                                type="text"
                                                prop:value=move || draft.with(|d| d.country_code.clone())
                                                on:input=move |ev| draft.update(|d| d.country_code = event_target_value(&ev))
                                            />
                                        </div>
                                        <div class="tc-field">
                                            <label class="tc-label" for="setup-currency">"Currency (ISO 3) *"</label>
                                            <input
                                                id="setup-currency"
                                                data-target="setup-currency"
                                                class="tc-input tc-mono"
                                                maxlength="3"
                                                type="text"
                                                prop:value=move || draft.with(|d| d.currency.clone())
                                                on:input=move |ev| draft.update(|d| d.currency = event_target_value(&ev))
                                            />
                                        </div>
                                        <div class="tc-field tc-form-span-2">
                                            <label class="tc-label" for="setup-language">"Default language (ISO 639-1) *"</label>
                                            <input
                                                id="setup-language"
                                                data-target="setup-language"
                                                class="tc-input tc-mono"
                                                maxlength="2"
                                                type="text"
                                                prop:value=move || draft.with(|d| d.default_language.clone())
                                                on:input=move |ev| draft.update(|d| d.default_language = event_target_value(&ev))
                                            />
                                        </div>
                                    </div>
                                }.into_any(),
                                SetupStep::Admin => view! {
                                    <div class="tc-form-grid">
                                        <div class="tc-field tc-form-span-2">
                                            <label class="tc-label" for="setup-admin-email">"Administrator e-mail *"</label>
                                            <input
                                                id="setup-admin-email"
                                                data-target="setup-admin-email"
                                                class="tc-input"
                                                type="email"
                                                placeholder="admin@company.example"
                                                prop:value=move || draft.with(|d| d.admin_email.clone())
                                                on:input=move |ev| draft.update(|d| d.admin_email = event_target_value(&ev))
                                            />
                                        </div>
                                        <div class="tc-field tc-form-span-2">
                                            <label class="tc-label" for="setup-admin-name">"Administrator display name *"</label>
                                            <input
                                                id="setup-admin-name"
                                                data-target="setup-admin-name"
                                                class="tc-input"
                                                type="text"
                                                prop:value=move || draft.with(|d| d.admin_display_name.clone())
                                                on:input=move |ev| draft.update(|d| d.admin_display_name = event_target_value(&ev))
                                            />
                                        </div>
                                    </div>
                                }.into_any(),
                                SetupStep::Token => view! {
                                    <div class="tc-field">
                                        <label class="tc-label" for="setup-token">"Bootstrap token *"</label>
                                        <input
                                            id="setup-token"
                                            data-target="setup-token"
                                            class="tc-input tc-mono"
                                            type="password"
                                            prop:value=move || draft.with(|d| d.token.clone())
                                            on:input=move |ev| draft.update(|d| d.token = event_target_value(&ev))
                                        />
                                    </div>
                                }.into_any(),
                                SetupStep::Review => {
                                    let d = draft.get();
                                    let legal = opt_trimmed(&d.legal_name).unwrap_or_else(|| "—".to_string());
                                    let vat = opt_trimmed(&d.vat_number).unwrap_or_else(|| "—".to_string());
                                    view! {
                                        <div class="tc-card" style="background: var(--surface-container);" data-target="setup-review">
                                            <div class="tc-form-grid">
                                                <div>
                                                    <div class="tc-label">"Company"</div>
                                                    <div>{d.name}</div>
                                                </div>
                                                <div>
                                                    <div class="tc-label">"Legal name"</div>
                                                    <div>{legal}</div>
                                                </div>
                                                <div>
                                                    <div class="tc-label">"VAT number"</div>
                                                    <div class="tc-mono">{vat}</div>
                                                </div>
                                                <div>
                                                    <div class="tc-label">"Region"</div>
                                                    <div class="tc-mono">
                                                        {format!(
                                                            "{} · {} · {}",
                                                            d.country_code.trim().to_ascii_uppercase(),
                                                            d.currency.trim().to_ascii_uppercase(),
                                                            d.default_language.trim().to_ascii_lowercase()
                                                        )}
                                                    </div>
                                                </div>
                                                <div>
                                                    <div class="tc-label">"Administrator"</div>
                                                    <div>{format!("{} <{}>", d.admin_display_name.trim(), d.admin_email.trim().to_ascii_lowercase())}</div>
                                                </div>
                                                <div>
                                                    <div class="tc-label">"Authentication mode"</div>
                                                    <div class="tc-mono">{info.auth_mode.clone()}</div>
                                                </div>
                                            </div>
                                        </div>
                                    }.into_any()
                                }
                            }}

                            <div class="tc-form-actions" style="justify-content: space-between;">
                                <A href=app_href("/login") attr:class="tc-btn tc-btn-ghost tc-btn-sm">
                                    "Back to sign in"
                                </A>
                                <div class="tc-header-actions">
                                    <Show when=move || step_idx.get() != 0>
                                        <button
                                            type="button"
                                            class="tc-btn"
                                            data-target="setup-back"
                                            disabled=move || busy.get()
                                            on:click=on_back
                                        >
                                            "Back"
                                        </button>
                                    </Show>
                                    {if is_last {
                                        view! {
                                            <button
                                                type="button"
                                                class="tc-btn tc-btn-primary"
                                                data-target="setup-submit"
                                                disabled=move || busy.get()
                                                on:click=on_submit.clone()
                                            >
                                                {move || if busy.get() { "Creating..." } else { "Create company" }}
                                            </button>
                                        }.into_any()
                                    } else {
                                        view! {
                                            <button
                                                type="button"
                                                class="tc-btn tc-btn-primary"
                                                data-target="setup-next"
                                                on:click=on_next
                                            >
                                                "Next"
                                            </button>
                                        }.into_any()
                                    }}
                                </div>
                            </div>
                        </div>
                    }.into_any()
                }}
            </div>
        </div>
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn setup_steps_include_token_only_when_required() {
        assert_eq!(
            setup_steps(false),
            vec![
                SetupStep::Company,
                SetupStep::Region,
                SetupStep::Admin,
                SetupStep::Review
            ]
        );
        assert_eq!(
            setup_steps(true),
            vec![
                SetupStep::Company,
                SetupStep::Region,
                SetupStep::Admin,
                SetupStep::Token,
                SetupStep::Review
            ]
        );
    }

    #[test]
    fn validates_each_step_and_builds_normalized_request() {
        let mut d = SetupDraft::default();
        assert!(validate_step(SetupStep::Company, &d, false).is_err());

        d.name = "  Demo BV ".into();
        d.vat_number = "be 0123.456-749".into();
        assert!(validate_step(SetupStep::Company, &d, false).is_ok());

        d.country_code = "be".into();
        d.currency = "eur".into();
        d.default_language = "NL".into();
        assert!(validate_step(SetupStep::Region, &d, false).is_ok());

        d.admin_email = "not-an-email".into();
        assert!(validate_step(SetupStep::Admin, &d, false).is_err());
        d.admin_email = " Admin@Demo.Test ".into();
        d.admin_display_name = " Ada Admin ".into();
        assert!(validate_step(SetupStep::Admin, &d, false).is_ok());

        assert!(validate_step(SetupStep::Token, &d, true).is_err());
        d.token = " secret-123 ".into();
        assert!(validate_step(SetupStep::Review, &d, true).is_ok());

        let req = build_bootstrap_request(&d, true);
        assert_eq!(req.name, "Demo BV");
        assert_eq!(req.vat_number.as_deref(), Some("BE0123456749"));
        assert_eq!(req.country_code, "BE");
        assert_eq!(req.currency, "EUR");
        assert_eq!(req.default_language, "nl");
        assert_eq!(req.admin_email, "admin@demo.test");
        assert_eq!(req.admin_display_name, "Ada Admin");
        assert_eq!(req.token.as_deref(), Some("secret-123"));

        let req_no_tok = build_bootstrap_request(&d, false);
        assert_eq!(req_no_tok.token, None);
    }
}
