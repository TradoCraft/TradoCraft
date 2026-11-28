//! Shared async API helpers, request-generation staleness guards, and alive signal updates.

use std::future::Future;
use std::sync::atomic::{AtomicU64, Ordering};

use leptos::prelude::*;
use leptos::task::spawn_local;
use tradocraft_api_client::{ApiError, Client};

use crate::api::{resolve_base_url, ConnectionMode};
use crate::state::{ActiveSession, AppContext};

/// Sets `signal` unless it was disposed (for example when a page unmounted while a request was
/// in flight). Returns `true` when the value was written (`try_set` itself returns `None` on
/// success, which is easy to misread).
pub fn set_alive<T: Send + Sync + 'static>(signal: RwSignal<T>, value: T) -> bool {
    signal.try_set(value).is_none()
}

/// Builds a typed live HTTP [`Client`] from `connection`, failing in offline `MockDemo` mode with
/// a user-facing message mentioning `area`.
pub fn live_client_for(connection: &ConnectionMode, area: &str) -> Result<Client, ApiError> {
    match connection {
        ConnectionMode::Live(session) => {
            let mut resolved = session.clone();
            resolved.base_url = resolve_base_url(&session.base_url);
            Ok(Client::from_session(resolved))
        }
        ConnectionMode::MockDemo => Err(ApiError::InvalidConfig(format!(
            "{area} needs a live API connection; switch to Dev User or Bearer mode on the sign-in screen."
        ))),
    }
}

/// Builds a live [`Client`] from `connection`, failing in `MockDemo` mode with a generic message.
pub fn live_client(connection: &ConnectionMode) -> Result<Client, ApiError> {
    live_client_for(connection, "This view")
}

/// Runs `f` against the live API and hands the result to `done`, unless the signed-in session is
/// gone. `done` runs after the page may have been left: callers must guard signal writes with
/// [`set_alive`].
pub fn spawn_api<T, F, Fut, D>(ctx: AppContext, f: F, done: D)
where
    T: 'static,
    F: FnOnce(Client) -> Fut + 'static,
    Fut: Future<Output = Result<T, ApiError>> + 'static,
    D: FnOnce(Result<T, ApiError>) + 'static,
{
    let Some(session) = ctx.session.get_untracked() else {
        return;
    };
    spawn_local(async move {
        let res = match live_client(&session.connection) {
            Ok(client) => f(client).await,
            Err(err) => Err(err),
        };
        done(res);
    });
}

/// Advances a wrapping request-generation counter.
pub fn next_generation(current: u64) -> u64 {
    current.wrapping_add(1)
}

/// Starts a new request generation on `v` and returns it. A response is applied only while its
/// generation is still [`is_current`]: a newer request (or the view being unmounted, which disposes
/// `v`) makes it stale.
pub fn bump(v: StoredValue<u64>) -> u64 {
    v.try_update_value(|g| {
        *g = next_generation(*g);
        *g
    })
    .unwrap_or(0)
}

/// Returns whether `gen` is still the newest generation of `v` (`false` once disposed).
pub fn is_current(v: StoredValue<u64>, gen: u64) -> bool {
    v.try_get_value() == Some(gen)
}

/// Monotonic per-view request-generation guard preventing stale out-of-order async responses from
/// overwriting newer state or disposed views.
#[derive(Clone, Copy)]
pub struct RequestGuard(StoredValue<u64>);

impl RequestGuard {
    /// Creates a new request guard initialized at generation `0`.
    pub fn new() -> Self {
        Self(StoredValue::new(0))
    }

    /// Starts a new generation and returns its token.
    pub fn bump(self) -> u64 {
        bump(self.0)
    }

    /// Returns `true` only if `gen` matches the latest generation and the owner is still alive.
    pub fn is_current(self, gen: u64) -> bool {
        is_current(self.0, gen)
    }
}

impl Default for RequestGuard {
    fn default() -> Self {
        Self::new()
    }
}

/// Monotonic generation counter for [`refresh_me`]; older responses are dropped.
static REFRESH_ME_GEN: AtomicU64 = AtomicU64::new(0);

/// Reloads `GET /api/v1/me` into the session after settings or module toggles change permissions.
/// Only the newest request is applied, and only while the same connection remains signed in.
pub fn refresh_me(ctx: AppContext) {
    let Some(issued_by) = ctx
        .session
        .with_untracked(|s| s.as_ref().map(|a| a.connection.clone()))
    else {
        return;
    };
    let gen = next_generation(REFRESH_ME_GEN.fetch_add(1, Ordering::Relaxed));
    spawn_api(
        ctx,
        |c| async move { c.me().await },
        move |res| {
            if REFRESH_ME_GEN.load(Ordering::Relaxed) != gen {
                return;
            }
            if let Ok(me) = res {
                ctx.session.try_update(|s| {
                    if let Some(ActiveSession {
                        connection,
                        me: current,
                    }) = s.as_mut()
                    {
                        if *connection == issued_by {
                            *current = me;
                        }
                    }
                });
            }
        },
    );
}

#[cfg(test)]
mod tests {
    use super::*;
    use tradocraft_api_client::Session;

    #[test]
    fn next_generation_increments_and_wraps() {
        assert_eq!(next_generation(0), 1);
        assert_eq!(next_generation(41), 42);
        assert_eq!(next_generation(u64::MAX), 0);
    }

    #[test]
    fn live_client_for_rejects_mock_demo_with_area() {
        let err = live_client_for(&ConnectionMode::MockDemo, "Purchasing")
            .expect_err("mock mode should fail");
        assert!(matches!(err, ApiError::InvalidConfig(msg) if msg.starts_with("Purchasing needs")));
    }

    #[test]
    fn live_client_accepts_live_connection() {
        let mode = ConnectionMode::Live(Session::dev(
            " http://127.0.0.1:8080/ ",
            "admin@example.com",
        ));
        let client = live_client(&mode).expect("live mode constructs client");
        assert_eq!(client.session().base_url, "http://127.0.0.1:8080");
    }
}
