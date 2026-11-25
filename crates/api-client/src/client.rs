//! Cross-platform HTTP client abstraction over `reqwest` (native + `wasm32-unknown-unknown`).

use serde::de::DeserializeOwned;
use serde::Serialize;

use crate::auth::{Auth, Session, COMPANY_HEADER, DEV_USER_HEADER};
use crate::error::{ApiError, ErrorBody};

/// Typed HTTP client for the TradoCraft REST API.
///
/// Uses `reqwest` with `rustls-tls` on native targets and browser `fetch` on
/// `wasm32-unknown-unknown`.
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
    pub fn url(&self, path: &str) -> String {
        let trimmed = path.trim_start_matches('/');
        if self.session.base_url.is_empty() {
            format!("/{trimmed}")
        } else {
            format!("{}/{trimmed}", self.session.base_url)
        }
    }

    pub(crate) async fn get_json<Q, T>(&self, path: &str, query: &Q) -> Result<T, ApiError>
    where
        Q: Serialize + ?Sized,
        T: DeserializeOwned,
    {
        let req = self.apply_headers(self.http.get(self.url(path)).query(query));
        self.send_json(req).await
    }

    pub(crate) async fn post_json<B, T>(&self, path: &str, body: &B) -> Result<T, ApiError>
    where
        B: Serialize + ?Sized,
        T: DeserializeOwned,
    {
        let req = self.apply_headers(self.http.post(self.url(path)).json(body));
        self.send_json(req).await
    }

    pub(crate) async fn put_json<B, T>(&self, path: &str, body: &B) -> Result<T, ApiError>
    where
        B: Serialize + ?Sized,
        T: DeserializeOwned,
    {
        let req = self.apply_headers(self.http.put(self.url(path)).json(body));
        self.send_json(req).await
    }

    fn apply_headers(&self, mut req: reqwest::RequestBuilder) -> reqwest::RequestBuilder {
        if let Some(auth) = &self.session.auth {
            match auth {
                Auth::DevUser(email) if !email.trim().is_empty() => {
                    req = req.header(DEV_USER_HEADER, email.trim());
                }
                Auth::BearerToken(token) if !token.trim().is_empty() => {
                    req = req.bearer_auth(token.trim());
                }
                _ => {}
            }
        }
        if let Some(company_id) = self.session.company_id {
            req = req.header(COMPANY_HEADER, company_id.to_string());
        }
        req
    }

    async fn send_json<T: DeserializeOwned>(
        &self,
        req: reqwest::RequestBuilder,
    ) -> Result<T, ApiError> {
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
        serde_json::from_str::<T>(&text).map_err(|err| ApiError::Decode {
            message: err.to_string(),
            body: text,
        })
    }
}

#[cfg(test)]
mod tests {
    use uuid::Uuid;

    use super::*;

    #[test]
    fn url_joins_base_and_path_cleanly() {
        let client = Client::new("http://localhost:8080/");
        assert_eq!(
            client.url("/api/v1/products"),
            "http://localhost:8080/api/v1/products"
        );
        assert_eq!(client.url("api/v1/me"), "http://localhost:8080/api/v1/me");

        let same_origin = Client::new("");
        assert_eq!(same_origin.url("/api/v1/me"), "/api/v1/me");
    }

    #[test]
    fn apply_headers_sets_dev_user_and_company() {
        let company_id = Uuid::nil();
        let client = Client::from_session(
            Session::dev("http://localhost:8080", "sales@example.com")
                .with_company_id(Some(company_id)),
        );
        let req = client
            .apply_headers(client.http.get(client.url("/api/v1/me")))
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
    fn apply_headers_sets_bearer_token() {
        let client = Client::from_session(Session::bearer("http://localhost:8080", "tok_123"));
        let req = client
            .apply_headers(client.http.get(client.url("/api/v1/me")))
            .build()
            .unwrap();
        assert_eq!(
            req.headers()
                .get("authorization")
                .unwrap()
                .to_str()
                .unwrap(),
            "Bearer tok_123"
        );
        assert!(req.headers().get(DEV_USER_HEADER).is_none());
    }
}
