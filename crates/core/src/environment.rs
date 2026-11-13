//! Which environment this API instance is: a name, a kind and the database it runs on.
//!
//! One database and one API instance exist per environment (ADR 0043). The app shows the
//! environment on every screen, so a user never mistakes a test or tutorial environment for live
//! data (or the other way round). The document is small and not sensitive, so it can be read
//! without signing in: the login screen shows it too.

use axum::extract::State;
use axum::{Extension, Json};
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;

use crate::{AppResult, AppState};

/// What an environment is for. Everything that reaches the outside world (e-mail, webhooks) may
/// only run for [`EnvKind::Live`].
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "snake_case")]
pub enum EnvKind {
    /// Real company data.
    #[default]
    Live,
    /// A copy of live data, or scratch data, to try things out.
    Test,
    /// A practice environment for the guided tutorial.
    Tutorial,
}

impl EnvKind {
    /// The word used in the API and in `APP_ENV_KIND`.
    pub fn as_str(self) -> &'static str {
        match self {
            EnvKind::Live => "live",
            EnvKind::Test => "test",
            EnvKind::Tutorial => "tutorial",
        }
    }
}

impl std::str::FromStr for EnvKind {
    type Err = String;

    /// Parses `live`, `test` or `tutorial` (any case, surrounding spaces allowed).
    fn from_str(s: &str) -> Result<Self, String> {
        match s.trim().to_ascii_lowercase().as_str() {
            "live" => Ok(EnvKind::Live),
            "test" => Ok(EnvKind::Test),
            "tutorial" => Ok(EnvKind::Tutorial),
            other => Err(format!(
                "unknown APP_ENV_KIND {other:?} (expected live, test or tutorial)"
            )),
        }
    }
}

/// Settings of this instance, read once at start-up (`APP_ENV_NAME`, `APP_ENV_KIND`).
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct EnvironmentConfig {
    /// Display name; the database name when absent.
    pub name: Option<String>,
    pub kind: EnvKind,
}

impl EnvironmentConfig {
    /// Parses the two settings; an empty value counts as unset and an unknown kind is an error,
    /// so a typo cannot make a test instance look like live (or the reverse).
    pub fn from_values(name: Option<&str>, kind: Option<&str>) -> Result<Self, String> {
        fn non_empty(v: Option<&str>) -> Option<&str> {
            v.map(str::trim).filter(|v| !v.is_empty())
        }
        Ok(Self {
            name: non_empty(name).map(str::to_string),
            kind: match non_empty(kind) {
                Some(k) => k.parse()?,
                None => EnvKind::Live,
            },
        })
    }

    /// Reads `APP_ENV_NAME` and `APP_ENV_KIND` from the process environment. A variable that is
    /// absent counts as unset (kind `live`); one that is present but not valid Unicode is an
    /// error, never silently the default.
    pub fn from_env() -> Result<Self, String> {
        Self::from_os_values(
            std::env::var_os("APP_ENV_NAME").as_deref(),
            std::env::var_os("APP_ENV_KIND").as_deref(),
        )
    }

    /// Like [`Self::from_values`] for raw environment values: `None` is an absent variable, a
    /// value that is not valid Unicode is an error naming the variable.
    pub fn from_os_values(
        name: Option<&std::ffi::OsStr>,
        kind: Option<&std::ffi::OsStr>,
    ) -> Result<Self, String> {
        fn text<'a>(var: &str, v: Option<&'a std::ffi::OsStr>) -> Result<Option<&'a str>, String> {
            match v {
                None => Ok(None),
                Some(os) => os
                    .to_str()
                    .map(Some)
                    .ok_or_else(|| format!("{var} is not valid UTF-8")),
            }
        }
        Self::from_values(text("APP_ENV_NAME", name)?, text("APP_ENV_KIND", kind)?)
    }
}

/// Environment variable that lets a non-live worker poll a mailbox anyway (`1` or `true`).
pub const ALLOW_INBOUND_MAIL_VAR: &str = "ALLOW_INBOUND_MAIL_IN_NON_LIVE";

/// The one policy for what may reach the outside world (ADR 0048). Computed once at start-up from
/// the environment kind; the API and the worker both apply it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OutboundPolicy {
    /// The kind of environment the policy was computed for.
    pub kind: EnvKind,
    /// The mail transport to use: what was requested for live, always `files` otherwise.
    pub mail_transport: String,
    /// Whether the worker may fetch mail from a mailbox (IMAP or Microsoft Graph).
    pub inbound_allowed: bool,
}

impl OutboundPolicy {
    /// Computes the policy. `requested_transport` is `MAIL_TRANSPORT` (default `files`);
    /// `allow_inbound` is the explicit opt-in for polling a mailbox in a non-live environment.
    pub fn resolve(kind: EnvKind, requested_transport: &str, allow_inbound: bool) -> Self {
        let live = kind == EnvKind::Live;
        Self {
            kind,
            mail_transport: if live {
                requested_transport.to_string()
            } else {
                "files".to_string()
            },
            inbound_allowed: live || allow_inbound,
        }
    }

    /// Parses the opt-in value: only `1` and `true` (any case) enable it.
    pub fn parse_opt_in(value: Option<&str>) -> bool {
        matches!(
            value.map(|v| v.trim().to_ascii_lowercase()).as_deref(),
            Some("1" | "true")
        )
    }

    /// True when nothing is restricted (live).
    pub fn is_unrestricted(&self) -> bool {
        self.kind == EnvKind::Live
    }

    /// The lines of the start-up warning: what this policy disables. Empty for live.
    pub fn warnings(&self, requested_transport: &str) -> Vec<String> {
        if self.is_unrestricted() {
            return Vec::new();
        }
        let mut w = vec![format!(
            "OUTBOUND SAFETY: environment kind is {}: outbound side effects are disabled",
            self.kind.as_str()
        )];
        w.push(if requested_transport == "files" {
            "OUTBOUND SAFETY: e-mail is written to .eml files, never sent (MAIL_TRANSPORT=files)"
                .to_string()
        } else {
            format!(
                "OUTBOUND SAFETY: MAIL_TRANSPORT={requested_transport} overridden to files: e-mail is never sent"
            )
        });
        w.push(if self.inbound_allowed {
            format!(
                "OUTBOUND SAFETY: {ALLOW_INBOUND_MAIL_VAR} is set: the mailbox WILL be polled and fetched mail is marked read there"
            )
        } else {
            format!(
                "OUTBOUND SAFETY: inbound mailbox polling (Graph and IMAP) is disabled (set {ALLOW_INBOUND_MAIL_VAR}=1 to opt in)"
            )
        });
        w
    }

    /// Logs [`Self::warnings`] at WARN level.
    pub fn log_warnings(&self, requested_transport: &str) {
        for line in self.warnings(requested_transport) {
            tracing::warn!("{line}");
        }
    }
}

impl EnvironmentConfig {
    /// Whether this environment may send e-mail or call external services: live only.
    pub fn outbound_allowed(&self) -> bool {
        self.kind == EnvKind::Live
    }

    /// The outbound policy for this environment; reads `ALLOW_INBOUND_MAIL_IN_NON_LIVE`.
    pub fn outbound_policy(&self, requested_transport: &str) -> OutboundPolicy {
        OutboundPolicy::resolve(
            self.kind,
            requested_transport,
            OutboundPolicy::parse_opt_in(std::env::var(ALLOW_INBOUND_MAIL_VAR).ok().as_deref()),
        )
    }
}

/// The environment this API instance serves.
#[derive(Debug, Serialize, ToSchema)]
pub struct EnvironmentInfo {
    /// Display name (`APP_ENV_NAME`, default: the database name).
    pub name: String,
    pub kind: EnvKind,
    /// Name of the database only; never host, user or password.
    pub db_name: String,
    /// Version of the API.
    pub version: String,
}

#[utoipa::path(get, path = "/meta/environment", tag = "core", security(()),
    responses((status = 200, body = EnvironmentInfo)))]
/// Describes this instance: the configured name and kind, plus the database it is connected to.
async fn get_environment(
    State(state): State<AppState>,
    Extension(config): Extension<EnvironmentConfig>,
) -> AppResult<Json<EnvironmentInfo>> {
    let db_name: String = sqlx::query_scalar("SELECT current_database()")
        .fetch_one(&state.db)
        .await?;
    Ok(Json(EnvironmentInfo {
        name: config.name.clone().unwrap_or_else(|| db_name.clone()),
        kind: config.kind,
        db_name,
        version: env!("CARGO_PKG_VERSION").to_string(),
    }))
}

/// `GET /meta/environment`: no sign-in and no company needed.
pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new().routes(routes!(get_environment))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn defaults_to_live_without_a_name() {
        let c = EnvironmentConfig::from_values(None, None).unwrap();
        assert_eq!(c, EnvironmentConfig::default());
        assert_eq!(c.kind, EnvKind::Live);
        assert_eq!(c.name, None);
    }

    #[test]
    fn empty_values_count_as_unset() {
        let c = EnvironmentConfig::from_values(Some("  "), Some("")).unwrap();
        assert_eq!(c, EnvironmentConfig::default());
    }

    #[test]
    fn parses_every_kind_case_insensitively() {
        for (s, k) in [
            ("live", EnvKind::Live),
            ("TEST", EnvKind::Test),
            (" Tutorial ", EnvKind::Tutorial),
        ] {
            let c = EnvironmentConfig::from_values(Some("Acme"), Some(s)).unwrap();
            assert_eq!(c.kind, k);
            assert_eq!(c.name.as_deref(), Some("Acme"));
        }
    }

    #[cfg(unix)]
    #[test]
    fn a_value_that_is_not_unicode_is_an_error() {
        use std::os::unix::ffi::OsStrExt;
        let bad = std::ffi::OsStr::from_bytes(&[0x74, 0xff, 0x73]);
        let e = EnvironmentConfig::from_os_values(None, Some(bad)).unwrap_err();
        assert!(e.contains("APP_ENV_KIND") && e.contains("UTF-8"), "{e}");
        let e = EnvironmentConfig::from_os_values(Some(bad), None).unwrap_err();
        assert!(e.contains("APP_ENV_NAME"), "{e}");
    }

    #[test]
    fn absent_os_values_are_the_defaults() {
        assert_eq!(
            EnvironmentConfig::from_os_values(None, None).unwrap(),
            EnvironmentConfig::default()
        );
    }

    #[test]
    fn live_keeps_the_requested_transport_and_imap() {
        let p = OutboundPolicy::resolve(EnvKind::Live, "smtp", false);
        assert_eq!(p.mail_transport, "smtp");
        assert!(p.inbound_allowed && p.is_unrestricted());
        assert!(p.warnings("smtp").is_empty());
    }

    #[test]
    fn non_live_forces_files_and_disables_imap() {
        for kind in [EnvKind::Test, EnvKind::Tutorial] {
            let p = OutboundPolicy::resolve(kind, "smtp", false);
            assert_eq!(p.mail_transport, "files");
            assert!(!p.inbound_allowed);
            let w = p.warnings("smtp").join("\n");
            assert!(
                w.contains("overridden to files")
                    && w.contains("inbound mailbox polling (Graph and IMAP) is disabled")
            );
        }
    }

    #[test]
    fn imap_needs_the_explicit_opt_in_in_non_live() {
        let p = OutboundPolicy::resolve(EnvKind::Test, "files", true);
        assert!(p.inbound_allowed);
        assert_eq!(p.mail_transport, "files");
        assert!(p.warnings("files").join("\n").contains("WILL be polled"));
        assert!(OutboundPolicy::parse_opt_in(Some(" TRUE ")));
        assert!(OutboundPolicy::parse_opt_in(Some("1")));
        assert!(!OutboundPolicy::parse_opt_in(Some("yes")));
        assert!(!OutboundPolicy::parse_opt_in(Some("0")));
        assert!(!OutboundPolicy::parse_opt_in(None));
    }

    #[test]
    fn only_live_allows_outbound() {
        for (k, ok) in [
            (EnvKind::Live, true),
            (EnvKind::Test, false),
            (EnvKind::Tutorial, false),
        ] {
            let c = EnvironmentConfig {
                name: None,
                kind: k,
            };
            assert_eq!(c.outbound_allowed(), ok);
        }
    }

    #[test]
    fn an_unknown_kind_is_an_error() {
        let e = EnvironmentConfig::from_values(None, Some("staging")).unwrap_err();
        assert!(e.contains("APP_ENV_KIND") && e.contains("staging"), "{e}");
    }
}
