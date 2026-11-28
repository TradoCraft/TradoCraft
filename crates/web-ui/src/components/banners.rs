//! Environment and background-worker health banners (ADR 0043 / ADR 0052).

use leptos::prelude::*;
use leptos::task::spawn_local;
use tradocraft_api_client::{Client, EnvKind, EnvironmentInfo, WorkerState, WorkerStatus};

use crate::api::{resolve_base_url, ConnectionMode};
use crate::i18n::tr;
use crate::pages::set_alive;
use crate::state::AppContext;

/// Returns `(data_target, css_class, display_text)` for non-live environments, or `None` on Live.
pub fn environment_banner_info(
    env: Option<&EnvironmentInfo>,
) -> Option<(&'static str, &'static str, String)> {
    let env = env?;
    match env.kind {
        EnvKind::Live => None,
        EnvKind::Test => Some((
            "env-banner-test",
            "tc-env-banner-test",
            format!("TEST · {}", env.name),
        )),
        EnvKind::Tutorial => Some((
            "env-banner-tutorial",
            "tc-env-banner-tutorial",
            format!("TUTORIAL · {}", env.name),
        )),
    }
}

/// Formats a UTC timestamp as `YYYY-MM-DD HH:MM UTC` without requiring `chrono`'s `alloc`/`std` formatting feature.
fn format_utc_timestamp(dt: chrono::DateTime<chrono::Utc>) -> String {
    use chrono::{Datelike, Timelike};
    format!(
        "{:04}-{:02}-{:02} {:02}:{:02} UTC",
        dt.year(),
        dt.month(),
        dt.day(),
        dt.hour(),
        dt.minute()
    )
}

/// Returns a warning message when the background worker is down or never seen, or `None` otherwise.
pub fn worker_banner_message(status: Option<&WorkerStatus>) -> Option<String> {
    let status = status?;
    match status.state {
        WorkerState::Running => None,
        WorkerState::Down => match status.last_beat_at {
            Some(last) => Some(format!(
                "Background worker has been unreachable since {} — outbound and inbound e-mail are paused.",
                format_utc_timestamp(last)
            )),
            None => Some(tr(
                "banner.worker_never_seen",
                "No background worker heartbeat has been recorded yet — outbound and inbound e-mail are paused.",
            )),
        },
        WorkerState::NeverSeen => Some(tr(
            "banner.worker_never_seen",
            "No background worker heartbeat has been recorded yet — outbound and inbound e-mail are paused.",
        )),
    }
}

/// Probes `GET /api/v1/meta/environment` once against the current origin and stores the result.
pub fn spawn_environment_probe(ctx: AppContext) {
    let base = resolve_base_url("");
    if base.is_empty() {
        return;
    }
    spawn_local(async move {
        if let Ok(info) = Client::new(base).environment().await {
            let _ = set_alive(ctx.environment, Some(info));
        }
    });
}

/// Watches `ctx.session` and polls `GET /api/v1/admin/worker` whenever an administrator signs in.
/// Clears the banner for non-admin users, mock sessions, or failed checks.
pub fn setup_worker_probe(ctx: AppContext) {
    let worker_gen = StoredValue::new(0_u64);
    Effect::new(move |_| {
        let gen = worker_gen
            .try_update_value(|g| {
                *g = g.wrapping_add(1);
                *g
            })
            .unwrap_or(0);
        let session = ctx.session.get();
        let Some(active) = session else {
            ctx.worker_status.set(None);
            return;
        };
        if !active.me.has_permission("users.admin") {
            ctx.worker_status.set(None);
            return;
        }
        let ConnectionMode::Live(raw_session) = active.connection else {
            ctx.worker_status.set(None);
            return;
        };
        let mut resolved = raw_session;
        resolved.base_url = resolve_base_url(&resolved.base_url);
        if resolved.base_url.is_empty() {
            ctx.worker_status.set(None);
            return;
        }
        let client = Client::from_session(resolved);
        spawn_local(async move {
            let res = client.get_worker().await;
            if worker_gen.try_get_value() != Some(gen) {
                return;
            }
            match res {
                Ok(status) => {
                    let _ = set_alive(ctx.worker_status, Some(status));
                }
                Err(_) => {
                    // Never claim the worker is down when the check itself failed.
                    let _ = set_alive(ctx.worker_status, None);
                }
            }
        });
    });
}

#[component]
pub fn EnvironmentBanner() -> impl IntoView {
    let ctx = expect_context::<AppContext>();
    view! {
        {move || {
            ctx.environment
                .with(|env| environment_banner_info(env.as_ref()))
                .map(|(kind_target, kind_class, text)| {
                    let classes = format!("tc-env-banner {kind_class}");
                    view! {
                        <div
                            class=classes
                            role="status"
                            aria-live="polite"
                            data-target="env-banner"
                        >
                            <span data-target=kind_target>{text}</span>
                        </div>
                    }
                })
        }}
    }
}

#[component]
pub fn WorkerBanner() -> impl IntoView {
    let ctx = expect_context::<AppContext>();
    view! {
        {move || {
            ctx.worker_status
                .with(|st| worker_banner_message(st.as_ref()))
                .map(|msg| {
                    view! {
                        <div
                            class="tc-worker-banner"
                            role="alert"
                            data-target="worker-banner"
                        >
                            <span>{msg}</span>
                        </div>
                    }
                })
        }}
    }
}

#[cfg(test)]
mod tests {
    use chrono::TimeZone;

    use super::*;

    fn env(kind: EnvKind, name: &str) -> EnvironmentInfo {
        EnvironmentInfo {
            name: name.into(),
            kind,
            db_name: "db".into(),
            version: "0.4.0".into(),
            instance_id: "inst".into(),
        }
    }

    fn worker(
        state: WorkerState,
        last_beat_at: Option<chrono::DateTime<chrono::Utc>>,
    ) -> WorkerStatus {
        WorkerStatus {
            state,
            last_beat_at,
            age_seconds: None,
            started_at: None,
            interval_seconds: None,
            late_after_seconds: None,
            version: None,
            host: None,
            last_outage: None,
        }
    }

    #[test]
    fn environment_banner_hides_live_and_formats_test_and_tutorial() {
        assert!(environment_banner_info(None).is_none());
        assert!(environment_banner_info(Some(&env(EnvKind::Live, "prod"))).is_none());
        assert_eq!(
            environment_banner_info(Some(&env(EnvKind::Test, "staging"))),
            Some((
                "env-banner-test",
                "tc-env-banner-test",
                "TEST · staging".to_string()
            ))
        );
        assert_eq!(
            environment_banner_info(Some(&env(EnvKind::Tutorial, "tutorial"))),
            Some((
                "env-banner-tutorial",
                "tc-env-banner-tutorial",
                "TUTORIAL · tutorial".to_string()
            ))
        );
    }

    #[test]
    fn worker_banner_hides_running_and_warns_on_down_or_never_seen() {
        assert!(worker_banner_message(None).is_none());
        assert!(worker_banner_message(Some(&worker(WorkerState::Running, None))).is_none());

        let never = worker_banner_message(Some(&worker(WorkerState::NeverSeen, None))).unwrap();
        assert!(never.contains("No background worker heartbeat"));

        let dt = chrono::Utc
            .with_ymd_and_hms(2026, 11, 28, 6, 15, 0)
            .unwrap();
        let down = worker_banner_message(Some(&worker(WorkerState::Down, Some(dt)))).unwrap();
        assert!(down.contains("2026-11-28 06:15 UTC"));
    }
}
