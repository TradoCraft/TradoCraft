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
    /// Every origin: local development and tests only.
    Any,
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

    pub fn layer(&self) -> CorsLayer {
        // The headers a preflight asks for are allowed by name: the wildcard `*` does not cover
        // `Authorization` (Fetch standard), which every signed-in request sends.
        let layer = CorsLayer::new()
            .allow_methods(Any)
            .allow_headers(AllowHeaders::mirror_request());
        match self {
            CorsConfig::Any => layer.allow_origin(Any),
            CorsConfig::Origins(origins) => layer.allow_origin(AllowOrigin::list(
                origins.iter().filter_map(|o| HeaderValue::from_str(o).ok()),
            )),
        }
    }
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
}
