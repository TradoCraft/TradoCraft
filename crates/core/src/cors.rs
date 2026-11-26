//! Which browser origins may call a server (ADR 0050).
//!
//! Native clients (the Windows and mobile apps) send no `Origin` header and are not affected. A
//! browser client (the web build of the app, the customer portal) is only answered with CORS
//! headers when its origin is on the list.

use axum::http::HeaderValue;
use reqwest::Url;
use tower_http::cors::{AllowHeaders, AllowOrigin, Any, CorsLayer};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CorsConfig {
    /// Every origin: tests only. `CORS_ALLOWED_ORIGINS=*` asks for it explicitly; the staff API
    /// refuses it with dev authentication and in a live environment ([`CorsConfig::for_api`]).
    Any,
    /// Pages served from this machine (`localhost`, `127.0.0.1`, `[::1]`, any port): the default
    /// of `AUTH_MODE=dev`, so a web page on the internet cannot reach a developer's local API.
    Loopback,
    /// Exactly these origins (`https://portal.example.com`); empty refuses every browser origin.
    Origins(Vec<String>),
}

impl CorsConfig {
    /// Parses a comma-separated list of origins; `*` alone means any origin.
    pub fn parse(list: &str) -> Result<Self, String> {
        let items: Vec<&str> = list
            .split(',')
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .collect();
        if items == ["*"] {
            return Ok(CorsConfig::Any);
        }
        let mut origins = Vec::new();
        for item in items {
            // An origin has no path, query or fragment; one trailing slash is forgiven.
            let bare = item.strip_suffix('/').unwrap_or(item);
            let has_path = Url::parse(bare)
                .is_ok_and(|u| u.path() != "/" || u.query().is_some() || u.fragment().is_some());
            let origin = origin_of(bare).filter(|_| !has_path).ok_or_else(|| {
                format!("{item} is not an origin (expected e.g. https://portal.example.com)")
            })?;
            if !origins.contains(&origin) {
                origins.push(origin);
            }
        }
        Ok(CorsConfig::Origins(origins))
    }

    /// The staff API's browser origins at start-up from `CORS_ALLOWED_ORIGINS` (ADR 0050, 0070,
    /// 0092). Unset: this machine only with dev authentication, no browser origin otherwise.
    /// Every origin (`*`) is refused with dev authentication (any web page could then call the
    /// API with an `X-Dev-User` header of its choosing) and in a live environment; it is meant
    /// for test and tutorial environments.
    pub fn for_api(list: Option<&str>, dev_auth: bool, live: bool) -> Result<Self, String> {
        let cors = match list {
            Some(list) => Self::parse(list)?,
            None if dev_auth => return Ok(CorsConfig::Loopback),
            None => return Ok(CorsConfig::Origins(Vec::new())),
        };
        if cors == CorsConfig::Any {
            if dev_auth {
                return Err(
                    "`*` (every origin) is refused with AUTH_MODE=dev: any web page \
                            could call this API with an X-Dev-User header of its choosing. \
                            Leave it empty (pages of this machine) or list the origins"
                        .into(),
                );
            }
            if live {
                return Err("`*` (every origin) is refused in a live environment \
                            (APP_ENV_KIND=live): list the origins of the web app, e.g. \
                            https://erp.example.com"
                    .into());
            }
        }
        Ok(cors)
    }

    pub fn layer(&self) -> CorsLayer {
        // The headers a preflight asks for are allowed by name: the wildcard `*` does not cover
        // `Authorization` (Fetch standard), which every signed-in request sends.
        let layer = CorsLayer::new()
            .allow_methods(Any)
            .allow_headers(AllowHeaders::mirror_request());
        match self {
            CorsConfig::Any => layer.allow_origin(Any),
            CorsConfig::Loopback => layer.allow_origin(AllowOrigin::predicate(|origin, _| {
                origin.to_str().is_ok_and(is_loopback_origin)
            })),
            CorsConfig::Origins(origins) => layer.allow_origin(AllowOrigin::list(
                origins.iter().filter_map(|o| HeaderValue::from_str(o).ok()),
            )),
        }
    }
}

/// Whether an `Origin` header value names this machine: `http(s)://localhost`, `127.0.0.1` or
/// `[::1]` with any port. A host that merely starts with `localhost` does not count.
pub fn is_loopback_origin(origin: &str) -> bool {
    origin_of(origin).is_some_and(|o| {
        Url::parse(&o).is_ok_and(|u| match u.host() {
            Some(url::Host::Domain(d)) => d == "localhost",
            Some(url::Host::Ipv4(ip)) => ip.is_loopback(),
            Some(url::Host::Ipv6(ip)) => ip.is_loopback(),
            None => false,
        })
    })
}

/// The origin (`scheme://host[:port]`) of an http(s) URL, as a browser sends it in the `Origin`
/// header: lower case, an internationalised host name in its ASCII form, the default port left
/// out. `None` when the text is not such a URL.
pub fn origin_of(url: &str) -> Option<String> {
    let url = Url::parse(url.trim()).ok()?;
    if !matches!(url.scheme(), "http" | "https") {
        return None;
    }
    // An address with a user name or password is not where a portal lives.
    if !url.username().is_empty() || url.password().is_some() {
        return None;
    }
    url.host_str().filter(|h| !h.is_empty())?;
    Some(url.origin().ascii_serialization())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn origin_is_scheme_host_and_port() {
        assert_eq!(
            origin_of("https://Portal.Example.com/login#token=x").as_deref(),
            Some("https://portal.example.com")
        );
        assert_eq!(
            origin_of(" http://localhost:8081/ ").as_deref(),
            Some("http://localhost:8081")
        );
        assert_eq!(
            origin_of("https://portal.example.com:443").as_deref(),
            Some("https://portal.example.com")
        );
        // An internationalised host name, as the browser sends it.
        assert_eq!(
            origin_of("https://Bücher.example/login").as_deref(),
            Some("https://xn--bcher-kva.example")
        );
        assert_eq!(
            origin_of("http://[::1]:8081/").as_deref(),
            Some("http://[::1]:8081")
        );
        assert_eq!(origin_of("portal.example.com"), None);
        assert_eq!(origin_of("ftp://example.com"), None);
        assert_eq!(origin_of("https://user@example.com"), None);
        assert_eq!(origin_of("https://"), None);
    }

    #[test]
    fn loopback_origins_are_this_machine_only() {
        for ok in [
            "http://localhost:8081",
            "http://localhost",
            "https://localhost:3000",
            "http://127.0.0.1:5000",
            "http://[::1]:8081",
        ] {
            assert!(is_loopback_origin(ok), "{ok}");
        }
        for bad in [
            "https://evil.example",
            "http://localhost.evil.example",
            "http://127.0.0.1.evil.example",
            "http://192.168.1.5:8081",
            "http://0.0.0.0:8081",
            "null",
            "file://",
            "",
        ] {
            assert!(!is_loopback_origin(bad), "{bad}");
        }
    }

    #[test]
    fn parses_a_list_and_refuses_what_is_not_an_origin() {
        assert_eq!(CorsConfig::parse("*"), Ok(CorsConfig::Any));
        assert_eq!(CorsConfig::parse(""), Ok(CorsConfig::Origins(vec![])));
        assert_eq!(
            CorsConfig::parse("https://a.example, http://localhost:8081/,https://a.example"),
            Ok(CorsConfig::Origins(vec![
                "https://a.example".into(),
                "http://localhost:8081".into()
            ]))
        );
        assert_eq!(
            CorsConfig::parse("https://bücher.example"),
            Ok(CorsConfig::Origins(vec![
                "https://xn--bcher-kva.example".into()
            ]))
        );
        assert!(CorsConfig::parse("https://a.example/portal").is_err());
        assert!(CorsConfig::parse("https://a.example?x=1").is_err());
        assert!(CorsConfig::parse("https://a.example/#top").is_err());
        assert!(CorsConfig::parse("a.example").is_err());
        assert!(CorsConfig::parse("*, https://a.example").is_err());
    }

    #[test]
    fn the_api_never_answers_every_origin_with_dev_auth_or_in_live() {
        // Unset: this machine with dev authentication, nobody with real sign-in.
        assert_eq!(
            CorsConfig::for_api(None, true, true),
            Ok(CorsConfig::Loopback)
        );
        assert_eq!(
            CorsConfig::for_api(None, false, true),
            Ok(CorsConfig::Origins(vec![]))
        );
        // `*` is refused with dev authentication in every environment, and in live.
        for (dev, live) in [(true, true), (true, false), (false, true)] {
            assert!(
                CorsConfig::for_api(Some("*"), dev, live).is_err(),
                "dev={dev} live={live}"
            );
            assert!(CorsConfig::for_api(Some(" * "), dev, live).is_err());
        }
        // A test or tutorial environment with real sign-in may still ask for it.
        assert_eq!(
            CorsConfig::for_api(Some("*"), false, false),
            Ok(CorsConfig::Any)
        );
        // A list works everywhere; an empty value with dev authentication answers nobody.
        for (dev, live) in [(true, true), (false, true), (false, false)] {
            assert_eq!(
                CorsConfig::for_api(Some("https://erp.example"), dev, live),
                Ok(CorsConfig::Origins(vec!["https://erp.example".into()]))
            );
        }
        assert_eq!(
            CorsConfig::for_api(Some(""), true, true),
            Ok(CorsConfig::Origins(vec![]))
        );
        assert!(CorsConfig::for_api(Some("erp.example"), false, true).is_err());
    }
}
