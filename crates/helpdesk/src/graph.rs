//! Microsoft Graph as a mail transport for Exchange Online mailboxes (ADR 0054).
//!
//! The worker signs in as an application (client credentials) and works on one mailbox:
//! * fetching: the unread messages of the inbox are downloaded as raw MIME (`/$value`), ingested
//!   like any other e-mail, and only then marked read;
//! * sending: the MIME message built by the mailer is uploaded as a draft, which returns the
//!   Message-ID that Exchange gave it, and the draft is then sent.
//!
//! Nothing else of Graph is used: no change notifications (the worker polls, the API is not
//! reachable from the internet) and no `reply` (the helpdesk composes its own messages).

use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant};

use anyhow::Context;
use base64::Engine;
use serde::Deserialize;
use sqlx::PgPool;
use tokio::sync::Mutex;
use uuid::Uuid;

use crate::ingest::{self, Source};

const GRAPH_URL: &str = "https://graph.microsoft.com/v1.0";
const LOGIN_URL: &str = "https://login.microsoftonline.com";
/// Unread messages fetched from one mailbox in one pass; the rest follows in the next pass.
const MAX_PER_POLL: usize = 200;
/// A token is renewed this long before it expires.
const TOKEN_MARGIN: Duration = Duration::from_secs(120);

/// One Exchange Online mailbox and the application that may use it.
#[derive(Clone)]
pub struct GraphMailbox {
    pub mailbox_id: Uuid,
    pub tenant_id: String,
    pub client_id: String,
    pub client_secret: String,
    /// The mailbox's address (the user principal name or primary SMTP address).
    pub address: String,
}

impl std::fmt::Debug for GraphMailbox {
    // Never the secret.
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("GraphMailbox")
            .field("address", &self.address)
            .field("tenant_id", &self.tenant_id)
            .field("client_id", &self.client_id)
            .finish_non_exhaustive()
    }
}

struct Token {
    value: String,
    expires: Instant,
}

/// The HTTP client and the access tokens, shared by all Graph mailboxes of the worker. Cloning is
/// cheap and shares the token cache.
#[derive(Clone)]
pub struct GraphClient {
    http: reqwest::Client,
    graph_url: String,
    login_url: String,
    /// Per tenant and application; a token is valid for every mailbox the application may use.
    tokens: Arc<Mutex<HashMap<(String, String), Token>>>,
}

impl Default for GraphClient {
    fn default() -> Self {
        Self::new()
    }
}

#[derive(Deserialize)]
struct TokenResponse {
    access_token: String,
    expires_in: u64,
}

#[derive(Deserialize)]
struct MessageRef {
    id: String,
}

#[derive(Deserialize)]
struct MessagePage {
    value: Vec<MessageRef>,
    #[serde(rename = "@odata.nextLink")]
    next_link: Option<String>,
}

#[derive(Deserialize)]
struct Draft {
    id: String,
    #[serde(rename = "internetMessageId")]
    internet_message_id: Option<String>,
}

/// Turns a failed response into an error with Graph's own message (`error.message`, or
/// `error_description` of the sign-in service), never with a token.
async fn check(res: reqwest::Response, what: &str) -> anyhow::Result<reqwest::Response> {
    let status = res.status();
    if status.is_success() {
        return Ok(res);
    }
    let retry = res
        .headers()
        .get("retry-after")
        .and_then(|v| v.to_str().ok())
        .map(|v| format!(" (retry after {v} s)"))
        .unwrap_or_default();
    let body = res.text().await.unwrap_or_default();
    let detail = serde_json::from_str::<serde_json::Value>(&body)
        .ok()
        .and_then(|v| {
            v["error"]["message"]
                .as_str()
                .or(v["error_description"].as_str())
                .map(|s| s.lines().next().unwrap_or_default().to_string())
        })
        .unwrap_or_default();
    anyhow::bail!("{what}: HTTP {}{retry} {detail}", status.as_u16())
}

impl GraphClient {
    pub fn new() -> Self {
        Self::with_urls(GRAPH_URL, LOGIN_URL)
    }

    /// For tests and national clouds: other base URLs for Graph and the sign-in service.
    pub fn with_urls(graph_url: &str, login_url: &str) -> Self {
        Self {
            http: reqwest::Client::builder()
                .timeout(Duration::from_secs(60))
                .connect_timeout(Duration::from_secs(15))
                .build()
                .expect("building the HTTP client"),
            graph_url: graph_url.trim_end_matches('/').to_string(),
            login_url: login_url.trim_end_matches('/').to_string(),
            tokens: Arc::default(),
        }
    }

    async fn token(&self, m: &GraphMailbox) -> anyhow::Result<String> {
        let key = (m.tenant_id.clone(), m.client_id.clone());
        let mut tokens = self.tokens.lock().await;
        if let Some(t) = tokens.get(&key) {
            if t.expires > Instant::now() {
                return Ok(t.value.clone());
            }
        }
        let res = self
            .http
            .post(format!(
                "{}/{}/oauth2/v2.0/token",
                self.login_url, m.tenant_id
            ))
            .form(&[
                ("grant_type", "client_credentials"),
                ("client_id", m.client_id.as_str()),
                ("client_secret", m.client_secret.as_str()),
                ("scope", "https://graph.microsoft.com/.default"),
            ])
            .send()
            .await
            .context("reaching the Microsoft sign-in service")?;
        let t: TokenResponse = check(res, "signing in to Microsoft 365")
            .await?
            .json()
            .await
            .context("reading the sign-in answer")?;
        let lifetime = Duration::from_secs(t.expires_in).saturating_sub(TOKEN_MARGIN);
        tokens.insert(
            key,
            Token {
                value: t.access_token.clone(),
                expires: Instant::now() + lifetime,
            },
        );
        Ok(t.access_token)
    }

    /// Forgets the token of this mailbox's application, so the next call signs in again.
    async fn forget_token(&self, m: &GraphMailbox) {
        self.tokens
            .lock()
            .await
            .remove(&(m.tenant_id.clone(), m.client_id.clone()));
    }

    fn user_url(&self, m: &GraphMailbox) -> String {
        // The address is validated when the mailbox is saved (no '/', '?', '#' or spaces).
        format!("{}/users/{}", self.graph_url, m.address)
    }

    /// Fetches unread messages of the inbox, ingests each one and marks it read. A message is only
    /// marked read after it has been stored, so nothing is lost if this fails; one that cannot be
    /// ingested stays unread. Returns the number processed.
    pub async fn poll(
        &self,
        db: &PgPool,
        m: &GraphMailbox,
        company_id: Uuid,
        source: Source,
    ) -> anyhow::Result<usize> {
        let token = self.token(m).await?;
        let mut ids: Vec<String> = Vec::new();
        let mut url = format!(
            "{}/mailFolders/inbox/messages?$filter=isRead%20eq%20false&$select=id&$top=50",
            self.user_url(m)
        );
        loop {
            let res = self
                .http
                .get(&url)
                .bearer_auth(&token)
                .send()
                .await
                .context("reaching Microsoft Graph")?;
            if res.status() == reqwest::StatusCode::UNAUTHORIZED {
                self.forget_token(m).await;
            }
            let page: MessagePage = check(res, "listing unread mail")
                .await?
                .json()
                .await
                .context("reading the list of unread mail")?;
            ids.extend(page.value.into_iter().map(|r| r.id));
            match page.next_link {
                // Only follow links to the same service: the token must not go anywhere else.
                Some(next) if ids.len() < MAX_PER_POLL && next.starts_with(&self.graph_url) => {
                    url = next
                }
                _ => break,
            }
        }
        let mut processed = 0;
        for id in ids.iter().take(MAX_PER_POLL) {
            let message_url = format!("{}/messages/{id}", self.user_url(m));
            let res = self
                .http
                .get(format!("{message_url}/$value"))
                .bearer_auth(&token)
                .send()
                .await
                .context("reaching Microsoft Graph")?;
            let raw = check(res, "downloading an e-mail").await?.bytes().await?;
            match ingest::ingest_from(db, company_id, &raw, Some(source)).await {
                Ok(r) => {
                    tracing::info!(ticket = %r.ticket_number, new = r.new_ticket, "e-mail ingested")
                }
                Err(e) => {
                    tracing::error!(error = ?e, "could not ingest e-mail; it stays unread");
                    continue;
                }
            }
            let res = self
                .http
                .patch(&message_url)
                .bearer_auth(&token)
                .json(&serde_json::json!({ "isRead": true }))
                .send()
                .await
                .context("reaching Microsoft Graph")?;
            check(res, "marking an e-mail as read").await?;
            processed += 1;
        }
        Ok(processed)
    }

    /// Sends a complete MIME message from the mailbox. Returns the Message-ID Exchange gave it
    /// (without angle brackets), which can differ from the one in the message.
    pub async fn send(&self, m: &GraphMailbox, mime: &[u8]) -> anyhow::Result<Option<String>> {
        let token = self.token(m).await?;
        let res = self
            .http
            .post(format!("{}/messages", self.user_url(m)))
            .bearer_auth(&token)
            .header("content-type", "text/plain")
            .body(base64::engine::general_purpose::STANDARD.encode(mime))
            .send()
            .await
            .context("reaching Microsoft Graph")?;
        if res.status() == reqwest::StatusCode::UNAUTHORIZED {
            self.forget_token(m).await;
        }
        let draft: Draft = check(res, "handing the e-mail to Exchange")
            .await?
            .json()
            .await
            .context("reading the draft")?;
        let draft_url = format!("{}/messages/{}", self.user_url(m), draft.id);
        let sent = async {
            let res = self
                .http
                .post(format!("{draft_url}/send"))
                .bearer_auth(&token)
                .header("content-length", "0")
                .send()
                .await
                .context("reaching Microsoft Graph")?;
            check(res, "sending the e-mail").await
        }
        .await;
        if let Err(e) = sent {
            // The next attempt makes a new draft: do not leave this one behind.
            let _ = self
                .http
                .delete(&draft_url)
                .bearer_auth(&token)
                .send()
                .await;
            return Err(e);
        }
        Ok(draft
            .internet_message_id
            .map(|id| {
                id.trim()
                    .trim_start_matches('<')
                    .trim_end_matches('>')
                    .to_string()
            })
            .filter(|id| !id.is_empty()))
    }
}
