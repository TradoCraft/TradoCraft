use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use leptos::ev::SubmitEvent;
use leptos::prelude::*;
use leptos::task::spawn_local;
use leptos_router::components::A;
use leptos_router::hooks::use_navigate;
use leptos_router::NavigateOptions;
use tradocraft_api_client::Client;

use crate::api::{resolve_base_url, ApiClient, Auth, ConnectionMode, MockApiClient, WebApiClient};
use crate::components::shell::app_href;
use crate::pages::set_alive;
use crate::state::{ActiveSession, AppContext};

const DEMO_USERS: &[(&str, &str)] = &[
    ("admin", "admin@example.com"),
    ("sales", "sales@example.com"),
    ("viewer", "viewer@example.com"),
];

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum LoginMode {
    DevUser,
    Bearer,
    DemoMock,
}

#[component]
pub fn LoginPage() -> impl IntoView {
    let ctx = expect_context::<AppContext>();
    let navigate = use_navigate();

    let initial = ctx.draft_connection.get_untracked();
    let (initial_base, initial_mode, initial_user, initial_token) = match &initial {
        ConnectionMode::MockDemo => (
            String::new(),
            LoginMode::DemoMock,
            "sales@example.com".to_string(),
            String::new(),
        ),
        ConnectionMode::Live(session) => match &session.auth {
            Some(Auth::BearerToken(token)) => (
                session.base_url.clone(),
                LoginMode::Bearer,
                "sales@example.com".to_string(),
                token.clone(),
            ),
            Some(Auth::DevUser(email)) => (
                session.base_url.clone(),
                LoginMode::DevUser,
                email.clone(),
                String::new(),
            ),
            None => (
                session.base_url.clone(),
                LoginMode::DevUser,
                "sales@example.com".to_string(),
                String::new(),
            ),
        },
    };

    let base_url = RwSignal::new(initial_base);
    let mode = RwSignal::new(initial_mode);
    let dev_user = RwSignal::new(initial_user);
    let bearer = RwSignal::new(initial_token);
    let busy = RwSignal::new(false);
    let error = RwSignal::new(Option::<String>::None);
    let needs_setup = RwSignal::new(false);
    let active = Arc::new(AtomicBool::new(true));
    on_cleanup({
        let active = Arc::clone(&active);
        move || {
            active.store(false, Ordering::Release);
        }
    });

    {
        let resolved_probe = resolve_base_url(&base_url.get_untracked());
        let active = Arc::clone(&active);
        if !resolved_probe.is_empty() {
            spawn_local(async move {
                if let Ok(status) = Client::new(resolved_probe).setup_status().await {
                    if active.load(Ordering::Acquire) {
                        let _ = set_alive(needs_setup, status.needs_setup);
                    }
                }
            });
        }
    }

    let on_submit = move |ev: SubmitEvent| {
        ev.prevent_default();
        if busy.get_untracked() {
            return;
        }
        let base = base_url.get_untracked();
        let selected_mode = mode.get_untracked();
        let dev_email = dev_user.get_untracked();
        let token = bearer.get_untracked();

        busy.set(true);
        error.set(None);

        let nav = navigate.clone();
        let active = Arc::clone(&active);
        spawn_local(async move {
            let result = match selected_mode {
                LoginMode::DevUser => WebApiClient.sign_in(&base, Auth::DevUser(dev_email)).await,
                LoginMode::Bearer => WebApiClient.sign_in(&base, Auth::BearerToken(token)).await,
                LoginMode::DemoMock => {
                    MockApiClient
                        .sign_in(&base, Auth::DevUser("sales@example.com".to_string()))
                        .await
                }
            };
            // Discard the result if LoginPage was unmounted/abandoned while sign-in was in flight:
            // mutating AppContext or navigating after abandonment would activate a session
            // unexpectedly or yank the user away from their current route, and local signals
            // are already disposed.
            if !active.load(Ordering::Acquire) {
                return;
            }
            match result {
                Ok((connection, me)) => {
                    ctx.draft_connection.set(connection.clone());
                    ctx.session.set(Some(ActiveSession { connection, me }));
                    busy.set(false);
                    nav("/home", NavigateOptions::default());
                }
                Err(err) => {
                    busy.set(false);
                    error.set(Some(err.user_message()));
                }
            }
        });
    };

    view! {
        <div class="tc-login-wrap">
            <form class="tc-card tc-login-card" on:submit=on_submit data-target="login-form">
                <div class="tc-brand">
                    <span class="tc-brand-mark">"TC"</span>
                    <div>
                        <div style="font-size: 18px; font-weight: 600;">"TradoCraft"</div>
                        <div style="font-size: 12px; color: var(--on-surface-variant);">
                            "Sign in to start a session (GET /api/v1/me)"
                        </div>
                    </div>
                </div>

                {move || error.get().map(|msg| view! {
                    <div class="tc-alert-error" role="alert" data-target="login-error">{msg}</div>
                })}

                <Show when=move || needs_setup.get()>
                    <div class="tc-card" style="padding: var(--space-md); background: var(--surface-container);" data-target="login-setup-banner">
                        <div style="font-size: 13px; margin-bottom: var(--space-xs);">
                            "No company is set up on this server yet."
                        </div>
                        <A href=app_href("/setup") attr:class="tc-btn tc-btn-sm" attr:data-target="login-setup-link">
                            "Set up first company"
                        </A>
                    </div>
                </Show>

                <div class="tc-field">
                    <label class="tc-label" for="login-server">"API Base URL (blank uses Trunk /api proxy)"</label>
                    <input
                        id="login-server"
                        data-target="login-server"
                        class="tc-input tc-mono"
                        type="text"
                        placeholder="http://127.0.0.1:8080 or leave empty"
                        prop:value=move || base_url.get()
                        on:input=move |ev| base_url.set(event_target_value(&ev))
                    />
                </div>

                <div class="tc-field">
                    <span class="tc-label">"Authentication mode"</span>
                    <div class="tc-chip-row">
                        <button
                            type="button"
                            data-target="login-mode-dev"
                            class=move || if mode.get() == LoginMode::DevUser { "tc-btn tc-btn-primary tc-btn-sm" } else { "tc-btn tc-btn-sm" }
                            on:click=move |_| mode.set(LoginMode::DevUser)
                        >
                            "Dev User (X-Dev-User)"
                        </button>
                        <button
                            type="button"
                            data-target="login-mode-bearer"
                            class=move || if mode.get() == LoginMode::Bearer { "tc-btn tc-btn-primary tc-btn-sm" } else { "tc-btn tc-btn-sm" }
                            on:click=move |_| mode.set(LoginMode::Bearer)
                        >
                            "OIDC Bearer"
                        </button>
                        <button
                            type="button"
                            data-target="login-mode-mock"
                            class=move || if mode.get() == LoginMode::DemoMock { "tc-btn tc-btn-primary tc-btn-sm" } else { "tc-btn tc-btn-sm" }
                            on:click=move |_| mode.set(LoginMode::DemoMock)
                        >
                            "Offline Mock"
                        </button>
                    </div>
                </div>

                <Show when=move || mode.get() == LoginMode::DevUser>
                    <div class="tc-field">
                        <label class="tc-label" for="login-dev-user">"Dev user e-mail"</label>
                        <input
                            id="login-dev-user"
                            data-target="login-dev-user"
                            class="tc-input"
                            type="email"
                            placeholder="sales@example.com"
                            prop:value=move || dev_user.get()
                            on:input=move |ev| dev_user.set(event_target_value(&ev))
                        />
                        <div class="tc-chip-row">
                            {DEMO_USERS.iter().map(|(tag, email)| {
                                let email_str = *email;
                                let target_id = format!("login-demo-{tag}");
                                view! {
                                    <button
                                        type="button"
                                        data-target=target_id
                                        class="tc-chip"
                                        on:click=move |_| dev_user.set(email_str.to_string())
                                    >
                                        {email_str}
                                    </button>
                                }
                            }).collect_view()}
                        </div>
                    </div>
                </Show>

                <Show when=move || mode.get() == LoginMode::Bearer>
                    <div class="tc-field">
                        <label class="tc-label" for="login-token">"Bearer access token"</label>
                        <input
                            id="login-token"
                            data-target="login-token"
                            class="tc-input tc-mono"
                            type="password"
                            placeholder="eyJhbGciOi..."
                            prop:value=move || bearer.get()
                            on:input=move |ev| bearer.set(event_target_value(&ev))
                        />
                    </div>
                </Show>

                <Show when=move || mode.get() == LoginMode::DemoMock>
                    <div style="font-size: 12px; color: var(--on-surface-variant);">
                        "Uses the local MockApiClient seeded with demo products and customers from seed/dev_seed.sql."
                    </div>
                </Show>

                <button
                    type="submit"
                    data-target="login-submit"
                    class="tc-btn tc-btn-primary"
                    disabled=move || busy.get()
                >
                    {move || if busy.get() { "Signing in..." } else { "Sign in" }}
                </button>
            </form>
        </div>
    }
}
