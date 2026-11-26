//! Cross-platform HTTP client abstraction over `reqwest` (native + `wasm32-unknown-unknown`).

use std::net::{Ipv4Addr, Ipv6Addr};

use serde::de::DeserializeOwned;
use serde::Serialize;

use crate::auth::{Auth, Session, COMPANY_HEADER, DEV_USER_HEADER};
use crate::error::{ApiError, ErrorBody};

/// Typed HTTP client for the TradoCraft REST API.
///
/// Uses `reqwest` with `rustls-tls` on native targets and browser `fetch` on
/// `wasm32-unknown-unknown`.
///
/// # URL and credential transport policy
///
/// - Requests require a non-empty, absolute `http://` or `https://` `base_url` with a host
///   (in browser WASM builds, callers should resolve same-origin empty URLs against
///   `window.location.origin` before constructing [`Client`]).
/// - Bearer credentials ([`Auth::BearerToken`]) are only sent over `https://` URLs, with
///   explicit loopback exemptions (`http://localhost`, `http://127.0.0.1`, `http://[::1]`)
///   for local development. Other non-HTTPS URLs are rejected with [`ApiError::InvalidConfig`].
#[derive(Debug, Clone)]
pub struct Client {
    http: reqwest::Client,
    session: Session,
}

impl Client {
    /// Creates an unauthenticated client targeting `base_url` (e.g. `http://localhost:8080`).
    pub fn new(base_url: impl Into<String>) -> Self {
        Self::from_session(Session::anonymous(base_url))
    }

    /// Creates a client configured from an existing [`Session`].
    pub fn from_session(session: Session) -> Self {
        Self {
            http: reqwest::Client::new(),
            session,
        }
    }

    /// Creates a client using a caller-provided `reqwest::Client`.
    pub fn with_http_client(http: reqwest::Client, session: Session) -> Self {
        Self { http, session }
    }

    /// Returns a clone of this client bound to a different [`Session`], reusing the underlying
    /// `reqwest::Client` connection pool.
    pub fn with_session(&self, session: Session) -> Self {
        Self {
            http: self.http.clone(),
            session,
        }
    }

    /// Returns the active [`Session`].
    pub fn session(&self) -> &Session {
        &self.session
    }

    /// Replaces the active [`Session`].
    pub fn set_session(&mut self, session: Session) {
        self.session = session;
    }

    /// Builds a full URL for an API path such as `/api/v1/products`.
    ///
    /// Rejects empty or malformed `base_url` values with [`ApiError::InvalidConfig`] so callers
    /// never construct relative URLs that `reqwest` cannot parse on native or `wasm32`.
    pub fn url(&self, path: &str) -> Result<String, ApiError> {
        let base = self.session.base_url.trim();
        if base.is_empty() {
            return Err(ApiError::InvalidConfig(
                "base_url cannot be empty; configure an absolute http(s) URL".to_string(),
            ));
        }
        let parsed = reqwest::Url::parse(base)
            .map_err(|err| ApiError::InvalidConfig(format!("invalid base_url '{base}': {err}")))?;
        if !matches!(parsed.scheme(), "http" | "https") || parsed.host_str().is_none() {
            return Err(ApiError::InvalidConfig(format!(
                "base_url must use http or https with a host, got '{base}'"
            )));
        }
        let trimmed = path.trim_start_matches('/');
        Ok(format!("{}/{trimmed}", base.trim_end_matches('/')))
    }

    pub(crate) async fn get_json<Q, T>(&self, path: &str, query: &Q) -> Result<T, ApiError>
    where
        Q: Serialize + ?Sized,
        T: DeserializeOwned,
    {
        let url = self.url(path)?;
        let req = self.apply_headers(self.http.get(url).query(query))?;
        self.send_json(req).await
    }

    pub(crate) async fn post_json<B, T>(&self, path: &str, body: &B) -> Result<T, ApiError>
    where
        B: Serialize + ?Sized,
        T: DeserializeOwned,
    {
        let url = self.url(path)?;
        let req = self.apply_headers(self.http.post(url).json(body))?;
        self.send_json(req).await
    }

    pub(crate) async fn put_json<B, T>(&self, path: &str, body: &B) -> Result<T, ApiError>
    where
        B: Serialize + ?Sized,
        T: DeserializeOwned,
    {
        let url = self.url(path)?;
        let req = self.apply_headers(self.http.put(url).json(body))?;
        self.send_json(req).await
    }

    pub(crate) async fn patch_json<B, T>(&self, path: &str, body: &B) -> Result<T, ApiError>
    where
        B: Serialize + ?Sized,
        T: DeserializeOwned,
    {
        let url = self.url(path)?;
        let req = self.apply_headers(self.http.patch(url).json(body))?;
        self.send_json(req).await
    }

    /// Sends an authenticated `DELETE` expecting an empty 2xx body (such as `204 No Content`).
    pub(crate) async fn delete_empty(&self, path: &str) -> Result<(), ApiError> {
        let url = self.url(path)?;
        let req = self.apply_headers(self.http.delete(url))?;
        let _ = self.send_checked(req).await?;
        Ok(())
    }

    /// Sends an unauthenticated JSON `POST` expecting an empty 2xx body (such as `202 Accepted`).
    pub(crate) async fn post_json_unauthenticated_empty<B>(
        &self,
        path: &str,
        body: &B,
    ) -> Result<(), ApiError>
    where
        B: Serialize + ?Sized,
    {
        let url = self.url(path)?;
        let req = self.http.post(url).json(body);
        let _ = self.send_checked(req).await?;
        Ok(())
    }

    fn apply_headers(
        &self,
        mut req: reqwest::RequestBuilder,
    ) -> Result<reqwest::RequestBuilder, ApiError> {
        if let Some(auth) = &self.session.auth {
            match auth {
                Auth::DevUser(email) if !email.trim().is_empty() => {
                    req = req.header(DEV_USER_HEADER, email.trim());
                }
                Auth::BearerToken(token) if !token.trim().is_empty() => {
                    validate_bearer_base_url(&self.session.base_url)?;
                    req = req.bearer_auth(token.trim());
                }
                _ => {}
            }
        }
        if let Some(company_id) = self.session.company_id {
            req = req.header(COMPANY_HEADER, company_id.to_string());
        }
        Ok(req)
    }

    async fn send_checked(&self, req: reqwest::RequestBuilder) -> Result<String, ApiError> {
        let resp = req.send().await?;
        let status = resp.status();
        let text = resp.text().await?;
        if !status.is_success() {
            let body = serde_json::from_str::<ErrorBody>(&text).ok();
            return Err(ApiError::Http {
                status: status.as_u16(),
                body,
                raw_body: text,
            });
        }
        Ok(text)
    }

    async fn send_json<T: DeserializeOwned>(
        &self,
        req: reqwest::RequestBuilder,
    ) -> Result<T, ApiError> {
        let text = self.send_checked(req).await?;
        serde_json::from_str::<T>(&text).map_err(|err| ApiError::Decode {
            message: err.to_string(),
            body: text,
        })
    }
}

/// Enforces HTTPS for bearer token transport, with an explicit loopback HTTP exemption for local
/// development (`http://localhost`, `http://127.0.0.1`, `http://[::1]`).
fn validate_bearer_base_url(base_url: &str) -> Result<(), ApiError> {
    let base = base_url.trim();
    let parsed = reqwest::Url::parse(base).map_err(|err| {
        ApiError::InvalidConfig(format!(
            "cannot send bearer credentials to invalid base_url '{base}': {err}"
        ))
    })?;
    match parsed.scheme() {
        "https" if parsed.host_str().is_some() => Ok(()),
        "http" if parsed.host_str().is_some_and(is_loopback_host) => Ok(()),
        _ => Err(ApiError::InvalidConfig(format!(
            "refusing to send bearer credentials over insecure base_url '{base}'; \
             use https:// (loopback http://localhost, http://127.0.0.1, and http://[::1] \
             are permitted for local development)"
        ))),
    }
}

fn is_loopback_host(host: &str) -> bool {
    if host.eq_ignore_ascii_case("localhost") {
        return true;
    }
    if let Ok(ip) = host.parse::<Ipv4Addr>() {
        return ip.is_loopback();
    }
    if let Some(inner) = host.strip_prefix('[').and_then(|s| s.strip_suffix(']')) {
        if let Ok(ip) = inner.parse::<Ipv6Addr>() {
            return ip.is_loopback();
        }
    }
    false
}

#[cfg(test)]
mod tests {
    use std::future::Future;
    use std::task::{Context, Poll, RawWaker, RawWakerVTable, Waker};

    use uuid::Uuid;

    use super::*;

    fn block_on_ready<F: Future>(fut: F) -> F::Output {
        fn no_op(_: *const ()) {}
        fn clone(ptr: *const ()) -> RawWaker {
            RawWaker::new(ptr, &VTABLE)
        }
        static VTABLE: RawWakerVTable = RawWakerVTable::new(clone, no_op, no_op, no_op);
        let waker = unsafe { Waker::from_raw(RawWaker::new(std::ptr::null(), &VTABLE)) };
        let mut cx = Context::from_waker(&waker);
        let mut pinned = Box::pin(fut);
        match pinned.as_mut().poll(&mut cx) {
            Poll::Ready(out) => out,
            Poll::Pending => panic!("expected future to resolve immediately without network I/O"),
        }
    }

    #[test]
    fn url_joins_base_and_path_cleanly_and_builds_request() {
        let client = Client::new("http://localhost:8080/");
        let products_url = client.url("/api/v1/products").unwrap();
        assert_eq!(products_url, "http://localhost:8080/api/v1/products");
        let req = client.http.get(&products_url).build().unwrap();
        assert_eq!(req.url().as_str(), "http://localhost:8080/api/v1/products");

        assert_eq!(
            client.url("api/v1/me").unwrap(),
            "http://localhost:8080/api/v1/me"
        );

        let empty_base = Client::new("");
        let err = empty_base.url("/api/v1/me").unwrap_err();
        assert!(matches!(err, ApiError::InvalidConfig(_)));
    }

    #[test]
    fn apply_headers_sets_dev_user_and_company() {
        let company_id = Uuid::nil();
        let client = Client::from_session(
            Session::dev("http://localhost:8080", "sales@example.com")
                .with_company_id(Some(company_id)),
        );
        let req = client
            .apply_headers(client.http.get(client.url("/api/v1/me").unwrap()))
            .unwrap()
            .build()
            .unwrap();
        assert_eq!(
            req.headers()
                .get(DEV_USER_HEADER)
                .unwrap()
                .to_str()
                .unwrap(),
            "sales@example.com"
        );
        assert_eq!(
            req.headers().get(COMPANY_HEADER).unwrap().to_str().unwrap(),
            company_id.to_string()
        );
        assert!(req.headers().get("authorization").is_none());
    }

    #[test]
    fn apply_headers_sets_bearer_token_for_https_and_loopback_http() {
        for base in [
            "https://api.tradocraft.example",
            "http://localhost:8080",
            "http://127.0.0.1:8080",
            "http://[::1]:8080",
        ] {
            let client = Client::from_session(Session::bearer(base, "tok_123"));
            let req = client
                .apply_headers(client.http.get(client.url("/api/v1/me").unwrap()))
                .unwrap()
                .build()
                .unwrap();
            assert_eq!(
                req.headers()
                    .get("authorization")
                    .unwrap()
                    .to_str()
                    .unwrap(),
                "Bearer tok_123",
                "failed for base {base}"
            );
            assert!(req.headers().get(DEV_USER_HEADER).is_none());
        }
    }

    #[test]
    fn bearer_credentials_reject_non_https_non_loopback_urls() {
        for bad_base in [
            "http://api.tradocraft.example",
            "http://192.168.1.50:8080",
            "http://localhost.evil.com:8080",
            "ftp://localhost:8080",
            "",
        ] {
            let mut client = Client::from_session(Session::bearer(bad_base, "tok_123"));
            let err = block_on_ready(client.me()).unwrap_err();
            assert!(
                matches!(err, ApiError::InvalidConfig(_)),
                "expected InvalidConfig for base '{bad_base}', got {err:?}"
            );

            let sign_in_err =
                block_on_ready(client.sign_in(Auth::BearerToken("tok_123".into()))).unwrap_err();
            assert!(
                matches!(sign_in_err, ApiError::InvalidConfig(_)),
                "expected InvalidConfig on sign_in for base '{bad_base}', got {sign_in_err:?}"
            );
        }
    }
}
