//! Microsoft Graph as a mail transport for Exchange Online mailboxes (ADR 0054).
//!
//! The worker signs in as an application (client credentials) and works on one mailbox:
//! * fetching: the unread messages of the inbox are downloaded as raw MIME (`/$value`), ingested
//!   like any other e-mail, and only then marked read;
//! * sending: the MIME message built by the mailer is uploaded as a draft, which returns the
//!   Message-ID Exchange gave it, and the draft is then sent.
//!
//! Nothing else of Graph is used: no change notifications (the worker polls, the API is not
//! reachable from the internet) and no `reply` (the helpdesk composes its own messages).
//!
//! What comes back is untrusted. Every answer and every message is size-capped, an id is capped
//! and written into an address as one percent-encoded piece, redirects are never followed, and a
//! next page is followed only at the address Graph is spoken to at. The token and the mail never
//! appear in an error: an error says what was being done, the status, and Graph's own one-line
//! message. Ids are immutable ids (`Prefer: IdType="ImmutableId"`), so a message that Outlook
//! moves between listing and fetching is still found.
//!
//! One message that cannot be fetched (gone, forbidden, invalid, too large) is skipped and
//! reported; it does not stop the messages after it. A sign-in that is refused, a busy answer or
//! a server error stops the pass, which the next pass tries again.
//!
//! Sending is the one thing that must never be repeated without looking: after an answer that
//! does not say whether the message went (a timeout, a 5xx), the draft is looked up. Gone means it
//! was sent. Still there means it was not. When even that cannot be told, the e-mail is marked
//! failed instead of being tried again ([`SendUnknown`]).

use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant};

use anyhow::Context;
use base64::Engine;
use serde::de::DeserializeOwned;
use serde::Deserialize;
use sqlx::PgPool;
use tokio::sync::Mutex;
use uuid::Uuid;

use crate::ingest::{self, Source};

const GRAPH_URL: &str = "https://graph.microsoft.com/v1.0";
const LOGIN_URL: &str = "https://login.microsoftonline.com";
/// Unread messages fetched from one mailbox in one pass; the rest follows in the next pass.
const MAX_PER_POLL: usize = 200;
/// Unread messages listed per pass: more than are processed, so that ones that keep failing (they
/// go last) cannot hide the later ones.
const MAX_LISTED: usize = 1_000;
/// Pages of a list followed in one pass, whatever they hold (a page of nothing but oversized ids
/// adds nothing to the count of messages).
const MAX_PAGES: usize = 100;
/// The longest id taken from Graph (ids are a few hundred characters).
const MAX_ID: usize = 1_024;
/// The largest message downloaded. Graph's own limit is far above it; a larger one stays unread
/// and the mailbox shows why.
pub const MAX_MESSAGE_BYTES: usize = 35 * 1024 * 1024;
/// The largest JSON answer read.
const MAX_ANSWER_BYTES: usize = 5 * 1024 * 1024;
/// A token is renewed this long before it expires.
const TOKEN_MARGIN: Duration = Duration::from_secs(120);
const REQUEST_TIMEOUT: Duration = Duration::from_secs(60);
/// What every request about mail asks for of ids.
const PREFER_IDS: &str = "IdType=\"ImmutableId\"";

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

/// Graph (or the sign-in service) answered with a status that is not a success. Callers look at
/// [`GraphStatus::status`] with `downcast_ref` to tell "this message" from "this mailbox".
#[derive(Debug)]
pub struct GraphStatus {
    pub status: u16,
    /// Seconds a busy answer asked to wait.
    pub retry_after: Option<u64>,
    text: String,
}

impl std::fmt::Display for GraphStatus {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.text)
    }
}

impl std::error::Error for GraphStatus {}

/// A send whose outcome is not known: the answer did not say, and the draft could not be looked
/// up either. The e-mail is not tried again, because that could send it twice.
#[derive(Debug)]
pub struct SendUnknown(String);

impl std::fmt::Display for SendUnknown {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "Microsoft 365 did not say whether the e-mail was sent ({}); it is not tried again, so check the mailbox's Sent Items before sending it again",
            self.0
        )
    }
}

impl std::error::Error for SendUnknown {}

/// An answer or a message larger than it may be.
#[derive(Debug)]
struct TooLarge;

impl std::fmt::Display for TooLarge {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("larger than it may be")
    }
}

impl std::error::Error for TooLarge {}

/// What one pass over a mailbox did.
#[derive(Debug, Default)]
pub struct Polled {
    /// E-mails stored as tickets or articles.
    pub ingested: usize,
    /// Things that did not work, in words for the mailbox's status line.
    pub problems: Vec<String>,
    /// False when the pass was stopped before it reached the end of the unread mail.
    pub complete: bool,
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
    /// Per mailbox: how often a message that is still unread could not be dealt with. Those are
    /// tried after the others, so a few bad mails cannot occupy every pass.
    failures: Arc<Mutex<HashMap<Uuid, HashMap<String, u32>>>>,
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

#[derive(Deserialize)]
struct Found {
    value: Vec<FoundMessage>,
}

#[derive(Deserialize)]
struct FoundMessage {
    id: String,
    #[serde(rename = "internetMessageId")]
    internet_message_id: Option<String>,
}

/// Seconds a `Retry-After` header asks for: a number of them, or the time to come back at (RFC
/// 9110 §10.2.3). No longer than a day.
fn retry_after_seconds(value: &str) -> Option<u64> {
    let value = value.trim();
    let seconds = match value.parse::<u64>() {
        Ok(s) => s,
        Err(_) => {
            let at = chrono::DateTime::parse_from_rfc2822(value).ok()?;
            u64::try_from((at.with_timezone(&chrono::Utc) - chrono::Utc::now()).num_seconds())
                .unwrap_or(0)
        }
    };
    Some(seconds.min(86_400))
}

/// An id as one piece of an address: everything but letters, digits and `-._~` as `%XX`. Ids may
/// hold `=`, and are not promised to stay free of `/`, `+` or `?`.
fn encode_segment(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for b in text.bytes() {
        if b.is_ascii_alphanumeric() || matches!(b, b'-' | b'.' | b'_' | b'~') {
            out.push(b as char);
        } else {
            out.push_str(&format!("%{b:02X}"));
        }
    }
    out
}

/// Whether `link` is at the same scheme, host and port as `base`.
fn same_origin(base: &str, link: &str) -> bool {
    let (Ok(base), Ok(link)) = (reqwest::Url::parse(base), reqwest::Url::parse(link)) else {
        return false;
    };
    base.scheme() == link.scheme()
        && base.host_str() == link.host_str()
        && base.port_or_known_default() == link.port_or_known_default()
}

/// Reads an answer up to `max` bytes; a larger one is [`TooLarge`], whatever it announces.
async fn read_capped(mut res: reqwest::Response, max: usize) -> anyhow::Result<Vec<u8>> {
    if res
        .content_length()
        .is_some_and(|n| usize::try_from(n).map_or(true, |n| n > max))
    {
        return Err(TooLarge.into());
    }
    let mut out = Vec::new();
    while let Some(chunk) = res
        .chunk()
        .await
        .context("reading the answer of Microsoft Graph")?
    {
        if out.len() + chunk.len() > max {
            return Err(TooLarge.into());
        }
        out.extend_from_slice(&chunk);
    }
    Ok(out)
}

async fn json<T: DeserializeOwned>(res: reqwest::Response, what: &str) -> anyhow::Result<T> {
    let bytes = read_capped(res, MAX_ANSWER_BYTES)
        .await
        .with_context(|| format!("reading {what}"))?;
    serde_json::from_slice(&bytes).with_context(|| format!("reading {what}"))
}

/// Turns a failed response into an error with Graph's own message (`error.message`, or
/// `error_description` of the sign-in service), never with a token. The error is a
/// [`GraphStatus`].
async fn check(res: reqwest::Response, what: &str) -> anyhow::Result<reqwest::Response> {
    let status = res.status();
    if status.is_success() {
        return Ok(res);
    }
    let retry_after = res
        .headers()
        .get("retry-after")
        .and_then(|v| v.to_str().ok())
        .and_then(retry_after_seconds);
    let retry = retry_after
        .map(|s| format!(" (retry after {s} s)"))
        .unwrap_or_default();
    let body = read_capped(res, 64 * 1024).await.unwrap_or_default();
    let detail = serde_json::from_slice::<serde_json::Value>(&body)
        .ok()
        .and_then(|v| {
            v["error"]["message"]
                .as_str()
                .or(v["error_description"].as_str())
                .map(|s| s.lines().next().unwrap_or_default().to_string())
        })
        .unwrap_or_default();
    let text = format!("{what}: HTTP {}{retry} {detail}", status.as_u16());
    Err(anyhow::Error::new(GraphStatus {
        status: status.as_u16(),
        retry_after,
        text: text.trim_end().to_string(),
    }))
}

fn status_of(e: &anyhow::Error) -> Option<u16> {
    e.downcast_ref::<GraphStatus>().map(|s| s.status)
}

/// A failure that belongs to one message, not to the mailbox: the message is skipped.
fn about_one_message(e: &anyhow::Error) -> bool {
    matches!(status_of(e), Some(400 | 403 | 404 | 410))
}

fn build_http(timeout: Duration) -> reqwest::Client {
    reqwest::Client::builder()
        .timeout(timeout)
        .connect_timeout(Duration::from_secs(15))
        // A redirect would carry the request, and with it the trust, somewhere else.
        .redirect(reqwest::redirect::Policy::none())
        .build()
        .expect("building the HTTP client")
}

enum DraftState {
    Present,
    Gone,
    Unknown,
}

impl GraphClient {
    pub fn new() -> Self {
        Self::with_urls(GRAPH_URL, LOGIN_URL)
    }

    /// For tests and national clouds: other base URLs for Graph (with its version) and the
    /// sign-in service.
    pub fn with_urls(graph_url: &str, login_url: &str) -> Self {
        Self {
            http: build_http(REQUEST_TIMEOUT),
            graph_url: graph_url.trim_end_matches('/').to_string(),
            login_url: login_url.trim_end_matches('/').to_string(),
            tokens: Arc::default(),
            failures: Arc::default(),
        }
    }

    /// The same client with another timeout for each request.
    pub fn with_timeout(mut self, timeout: Duration) -> Self {
        self.http = build_http(timeout);
        self
    }

    fn request(&self, method: reqwest::Method, url: &str, token: &str) -> reqwest::RequestBuilder {
        self.http
            .request(method, url)
            .bearer_auth(token)
            .header("Prefer", PREFER_IDS)
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
        let res = check(res, "signing in to Microsoft 365").await?;
        let t: TokenResponse = json(res, "the sign-in answer").await?;
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

    /// A refused token is not asked with again.
    async fn forget_if_refused(&self, m: &GraphMailbox, e: &anyhow::Error) {
        if status_of(e) == Some(401) {
            self.forget_token(m).await;
        }
    }

    fn user_url(&self, m: &GraphMailbox) -> String {
        // The address is validated when the mailbox is saved (no '/', '?', '#' or spaces).
        format!("{}/users/{}", self.graph_url, m.address)
    }

    fn message_url(&self, m: &GraphMailbox, id: &str) -> String {
        format!("{}/messages/{}", self.user_url(m), encode_segment(id))
    }

    /// The ids of the unread messages of the inbox, and what went wrong on the way that did not
    /// stop the list.
    async fn list_unread(
        &self,
        m: &GraphMailbox,
        token: &str,
    ) -> anyhow::Result<(Vec<String>, Vec<String>)> {
        let mut ids: Vec<String> = Vec::new();
        let mut notes: Vec<String> = Vec::new();
        let mut too_long = 0;
        let mut pages = 0;
        let mut url = format!(
            "{}/mailFolders/inbox/messages?$filter=isRead%20eq%20false&$select=id&$top=50",
            self.user_url(m)
        );
        loop {
            let res = self
                .request(reqwest::Method::GET, &url, token)
                .send()
                .await
                .context("reaching Microsoft Graph")?;
            let res = check(res, "listing unread mail").await?;
            let page: MessagePage = json(res, "the list of unread mail").await?;
            pages += 1;
            for r in page.value {
                if r.id.len() > MAX_ID {
                    too_long += 1;
                } else {
                    ids.push(r.id);
                }
            }
            match page.next_link {
                Some(next) if ids.len() < MAX_LISTED && pages < MAX_PAGES => {
                    if !same_origin(&self.graph_url, &next) {
                        notes.push(
                            "Microsoft Graph named another address for the next page; it was not followed"
                                .into(),
                        );
                        break;
                    }
                    url = next;
                }
                _ => break,
            }
        }
        if too_long > 0 {
            notes.push(format!(
                "{too_long} e-mail(s) with an id that is too long were left unread"
            ));
        }
        Ok((ids, notes))
    }

    /// Fetches unread messages of the inbox, ingests each one and marks it read. A message is only
    /// marked read after it has been stored, so nothing is lost if this fails; one that cannot be
    /// ingested stays unread. A message that cannot be fetched is skipped and reported, and the
    /// pass goes on; a refused sign-in, a busy answer or a server error stops it (`complete` is
    /// false) and the next pass tries again. Messages that were skipped before are tried after the
    /// others, so a few bad mails cannot occupy the whole pass.
    pub async fn poll(
        &self,
        db: &PgPool,
        m: &GraphMailbox,
        company_id: Uuid,
        source: Source,
    ) -> anyhow::Result<Polled> {
        let token = self.token(m).await?;
        let (mut ids, notes) = match self.list_unread(m, &token).await {
            Ok(listed) => listed,
            Err(e) => {
                self.forget_if_refused(m, &e).await;
                return Err(e);
            }
        };
        // Messages that failed before go last (the sort is stable: otherwise in the order Graph
        // listed them); only the ones still unread keep a failure count.
        let mut failed = self
            .failures
            .lock()
            .await
            .remove(&m.mailbox_id)
            .unwrap_or_default();
        {
            let listed: std::collections::HashSet<&String> = ids.iter().collect();
            failed.retain(|id, _| listed.contains(id));
        }
        ids.sort_by_key(|id| failed.get(id).copied().unwrap_or(0));
        let mut out = Polled {
            ingested: 0,
            problems: notes,
            complete: true,
        };
        for id in ids.iter().take(MAX_PER_POLL) {
            match self
                .one(db, m, &token, company_id, source, id, &mut out)
                .await
            {
                Ok(true) => {
                    failed.remove(id);
                }
                Ok(false) => *failed.entry(id.clone()).or_insert(0) += 1,
                Err(e) => {
                    self.forget_if_refused(m, &e).await;
                    out.problems.push(format!("{e:#}"));
                    out.complete = false;
                    break;
                }
            }
        }
        // Also after a stop: what failed so far keeps its place at the back.
        self.failures.lock().await.insert(m.mailbox_id, failed);
        Ok(out)
    }

    /// One unread message. `Ok(true)` when it is stored and marked read, `Ok(false)` when it was
    /// skipped (noted in `out`), `Err` when the pass should stop.
    #[allow(clippy::too_many_arguments)]
    async fn one(
        &self,
        db: &PgPool,
        m: &GraphMailbox,
        token: &str,
        company_id: Uuid,
        source: Source,
        id: &str,
        out: &mut Polled,
    ) -> anyhow::Result<bool> {
        let message_url = self.message_url(m, id);
        let res = self
            .request(
                reqwest::Method::GET,
                &format!("{message_url}/$value"),
                token,
            )
            .send()
            .await
            .context("reaching Microsoft Graph")?;
        let downloaded = match check(res, "downloading an e-mail").await {
            Ok(res) => read_capped(res, MAX_MESSAGE_BYTES).await,
            Err(e) => Err(e),
        };
        let raw = match downloaded {
            Ok(raw) => raw,
            Err(e) if e.is::<TooLarge>() => {
                out.problems.push(format!(
                    "an e-mail is larger than {} MB and was left unread",
                    MAX_MESSAGE_BYTES / 1024 / 1024
                ));
                return Ok(false);
            }
            Err(e) if about_one_message(&e) => {
                out.problems
                    .push(format!("an e-mail could not be downloaded ({e})"));
                return Ok(false);
            }
            Err(e) => return Err(e),
        };
        match ingest::ingest_from(db, company_id, &raw, Some(source)).await {
            Ok(r) => {
                tracing::info!(ticket = %r.ticket_number, new = r.new_ticket, "e-mail ingested")
            }
            Err(e) => {
                tracing::error!(error = ?e, "could not ingest e-mail; it stays unread");
                out.problems.push(
                    "an e-mail could not be turned into a ticket (see the worker log)".into(),
                );
                return Ok(false);
            }
        }
        out.ingested += 1;
        let res = self
            .request(reqwest::Method::PATCH, &message_url, token)
            .json(&serde_json::json!({ "isRead": true }))
            .send()
            .await
            .context("reaching Microsoft Graph")?;
        match check(res, "marking an e-mail as read").await {
            Ok(_) => Ok(true),
            Err(e) if about_one_message(&e) => {
                out.problems
                    .push(format!("an e-mail was stored but not marked read ({e})"));
                Ok(false)
            }
            Err(e) => Err(e),
        }
    }

    /// Uploads a MIME message as a draft in the mailbox. Returns the draft's id and the
    /// Message-ID Exchange says it has.
    async fn make_draft(
        &self,
        m: &GraphMailbox,
        token: &str,
        mime: &[u8],
    ) -> anyhow::Result<(String, Option<String>)> {
        let res = self
            .request(
                reqwest::Method::POST,
                &format!("{}/messages", self.user_url(m)),
                token,
            )
            .header("content-type", "text/plain")
            .body(base64::engine::general_purpose::STANDARD.encode(mime))
            .send()
            .await
            .context("reaching Microsoft Graph")?;
        let res = check(res, "handing the e-mail to Exchange").await?;
        let draft: Draft = json(res, "the draft").await?;
        anyhow::ensure!(
            !draft.id.is_empty() && draft.id.len() <= MAX_ID,
            "Microsoft Graph named a draft with an unusable id"
        );
        Ok((
            draft.id,
            draft
                .internet_message_id
                .map(|id| bare(&id))
                .filter(|id| !id.is_empty()),
        ))
    }

    async fn post_send(&self, draft_url: &str, token: &str) -> anyhow::Result<()> {
        let res = self
            .request(reqwest::Method::POST, &format!("{draft_url}/send"), token)
            .header("content-length", "0")
            .send()
            .await
            .context("reaching Microsoft Graph")?;
        check(res, "sending the e-mail").await?;
        Ok(())
    }

    async fn draft_state(&self, draft_url: &str, token: &str) -> DraftState {
        match self
            .request(
                reqwest::Method::GET,
                &format!("{draft_url}?$select=id"),
                token,
            )
            .send()
            .await
        {
            Ok(res) if res.status().is_success() => DraftState::Present,
            Ok(res) if res.status() == reqwest::StatusCode::NOT_FOUND => DraftState::Gone,
            _ => DraftState::Unknown,
        }
    }

    async fn drop_draft(&self, draft_url: &str, token: &str) {
        let _ = self
            .request(reqwest::Method::DELETE, draft_url, token)
            .send()
            .await;
    }

    /// Sends a complete MIME message from the mailbox. Returns the Message-ID Exchange gave it
    /// (without angle brackets), which can differ from the one in the message.
    ///
    /// When the answer to the send itself does not say whether the message went (a timeout, a
    /// 5xx), the draft is looked up: gone means it was sent. Where that cannot be told either,
    /// the error is a [`SendUnknown`] and the e-mail must not be sent again.
    pub async fn send(&self, m: &GraphMailbox, mime: &[u8]) -> anyhow::Result<Option<String>> {
        let token = self.token(m).await?;
        let (draft_id, assigned) = match self.make_draft(m, &token, mime).await {
            Ok(draft) => draft,
            Err(e) => {
                self.forget_if_refused(m, &e).await;
                return Err(e);
            }
        };
        let draft_url = self.message_url(m, &draft_id);
        let Err(e) = self.post_send(&draft_url, &token).await else {
            return Ok(assigned);
        };
        self.forget_if_refused(m, &e).await;
        // A refusal (4xx, a busy answer) is a "no": nothing was sent.
        if status_of(&e).is_some_and(|s| s < 500) {
            self.drop_draft(&draft_url, &token).await;
            return Err(e);
        }
        match self.draft_state(&draft_url, &token).await {
            DraftState::Gone => Ok(assigned),
            DraftState::Present => {
                self.drop_draft(&draft_url, &token).await;
                Err(e)
            }
            DraftState::Unknown => Err(anyhow::Error::new(SendUnknown(format!("{e:#}")))),
        }
    }

    /// Finds a message by its subject in a folder of the mailbox, waiting for it to arrive.
    async fn find_by_subject(
        &self,
        m: &GraphMailbox,
        token: &str,
        folder: &str,
        subject: &str,
        options: &CheckOptions,
    ) -> anyhow::Result<Option<FoundMessage>> {
        let filter = encode_segment(&format!("subject eq '{subject}'"));
        let url = format!(
            "{}/mailFolders/{folder}/messages?$filter={filter}&$select=id,internetMessageId&$top=5",
            self.user_url(m)
        );
        for attempt in 0..options.tries.max(1) {
            if attempt > 0 {
                tokio::time::sleep(options.delay).await;
            }
            let res = self
                .request(reqwest::Method::GET, &url, token)
                .send()
                .await
                .context("reaching Microsoft Graph")?;
            let res = check(res, "looking for the test message").await?;
            let found: Found = json(res, "the test message").await?;
            if let Some(first) = found.value.into_iter().next() {
                return Ok(Some(first));
            }
        }
        Ok(None)
    }

    /// A real round trip with the mailbox, for an administrator to run once after setting it up
    /// (`tradocraft-worker check-mailbox`): signs in, runs the query the worker uses, sends a
    /// message to the mailbox itself, finds both copies, compares the Message-ID at every stage,
    /// and removes the test mail. Never run by itself.
    pub async fn check_mailbox(&self, m: &GraphMailbox, options: &CheckOptions) -> CheckReport {
        let mut report = CheckReport::default();
        let token = match self.token(m).await {
            Ok(t) => {
                report.step("sign in", true, "a token was issued");
                t
            }
            Err(e) => {
                report.step("sign in", false, format!("{e:#}"));
                return report;
            }
        };
        match self.list_unread(m, &token).await {
            Ok((ids, notes)) => report.step(
                "the query the worker uses for unread mail",
                notes.is_empty(),
                format!(
                    "{} unread message(s) in the inbox{}",
                    ids.len(),
                    notes.join("; ")
                ),
            ),
            Err(e) => {
                report.step(
                    "the query the worker uses for unread mail",
                    false,
                    format!("{e:#}"),
                );
                return report;
            }
        }

        let id = Uuid::now_v7();
        let subject = format!("tradocraft mailbox check {id}");
        let domain = m.address.rsplit('@').next().unwrap_or("localhost");
        let mime_id = format!("check-{id}@{domain}");
        let mime = match test_message(&m.address, &subject, &mime_id) {
            Ok(mime) => mime,
            Err(e) => {
                report.step("compose the test message", false, format!("{e:#}"));
                return report;
            }
        };
        let (draft_id, draft_message_id) = match self.make_draft(m, &token, &mime).await {
            Ok(draft) => {
                report.step(
                    "make a draft from MIME",
                    true,
                    format!(
                        "the message says <{mime_id}>, Exchange says the draft is <{}>",
                        draft.1.as_deref().unwrap_or("(nothing)")
                    ),
                );
                draft
            }
            Err(e) => {
                report.step("make a draft from MIME", false, format!("{e:#}"));
                return report;
            }
        };
        let draft_url = self.message_url(m, &draft_id);
        if let Err(e) = self.post_send(&draft_url, &token).await {
            report.step("send the draft", false, format!("{e:#}"));
            self.drop_draft(&draft_url, &token).await;
            return report;
        }
        report.step("send the draft", true, "Exchange accepted it (202)");

        let delivered = self
            .find_by_subject(m, &token, "inbox", &subject, options)
            .await;
        let sent = self
            .find_by_subject(m, &token, "sentitems", &subject, options)
            .await;
        let describe = |found: &anyhow::Result<Option<FoundMessage>>| match found {
            Ok(Some(f)) => (
                true,
                format!(
                    "<{}>",
                    bare(f.internet_message_id.as_deref().unwrap_or_default())
                ),
            ),
            Ok(None) => (false, "not there after waiting".to_string()),
            Err(e) => (false, format!("{e:#}")),
        };
        let (ok, text) = describe(&delivered);
        report.step("find the delivered copy in the inbox", ok, text);
        let (ok, text) = describe(&sent);
        report.step("find the copy in Sent Items", ok, text);

        let mut header_id = None;
        if let Ok(Some(f)) = &delivered {
            let res = self
                .request(
                    reqwest::Method::GET,
                    &format!("{}/$value", self.message_url(m, &f.id)),
                    &token,
                )
                .send()
                .await;
            let raw = match res {
                Ok(res) => match check(res, "downloading the test message").await {
                    Ok(res) => read_capped(res, MAX_MESSAGE_BYTES).await,
                    Err(e) => Err(e),
                },
                Err(e) => Err(anyhow::Error::new(e).context("reaching Microsoft Graph")),
            };
            match raw {
                Ok(raw) => {
                    header_id = header_value(&raw, "message-id").map(|v| bare(&v));
                    report.step(
                        "download the delivered message",
                        header_id.is_some(),
                        format!(
                            "its Message-ID header is <{}>",
                            header_id.as_deref().unwrap_or("(missing)")
                        ),
                    );
                }
                Err(e) => report.step("download the delivered message", false, format!("{e:#}")),
            }
        }

        if let (Ok(Some(delivered)), Some(draft_message_id)) = (&delivered, &draft_message_id) {
            let delivered_id = bare(delivered.internet_message_id.as_deref().unwrap_or_default());
            let sent_id = match &sent {
                Ok(Some(s)) => bare(s.internet_message_id.as_deref().unwrap_or_default()),
                _ => delivered_id.clone(),
            };
            let header_id = header_id.unwrap_or_else(|| delivered_id.clone());
            let all_equal = |expected: &str| {
                [&delivered_id, &sent_id, &header_id, draft_message_id]
                    .iter()
                    .all(|id| id.as_str() == expected)
            };
            let verdict = if all_equal(&mime_id) {
                MessageIdVerdict::Kept
            } else if all_equal(draft_message_id) {
                MessageIdVerdict::ReplacedAtDraft
            } else {
                MessageIdVerdict::ReplacedAtSend
            };
            report.verdict = Some(verdict);
            report.step("Message-ID", true, verdict.explain());
        }

        // Clean up: the two copies (to Deleted Items) and any draft left over.
        let mut leftovers = Vec::new();
        for found in [&delivered, &sent].into_iter().flatten().flatten() {
            let res = self
                .request(
                    reqwest::Method::DELETE,
                    &self.message_url(m, &found.id),
                    &token,
                )
                .send()
                .await;
            if !res.is_ok_and(|r| r.status().is_success()) {
                leftovers.push(found.id.chars().take(12).collect::<String>());
            }
        }
        self.drop_draft(&draft_url, &token).await;
        report.step(
            "remove the test mail",
            leftovers.is_empty(),
            if leftovers.is_empty() {
                "moved to Deleted Items".to_string()
            } else {
                "some of it could not be removed: delete \"tradocraft mailbox check\" mail by hand"
                    .to_string()
            },
        );
        report
    }
}

/// A Message-ID without its angle brackets.
fn bare(id: &str) -> String {
    id.trim()
        .trim_start_matches('<')
        .trim_end_matches('>')
        .to_string()
}

fn header_value(raw: &[u8], name: &str) -> Option<String> {
    let text = String::from_utf8_lossy(raw);
    let head = text.split("\r\n\r\n").next()?.split("\n\n").next()?;
    head.lines().find_map(|line| {
        let (have, value) = line.split_once(':')?;
        have.trim()
            .eq_ignore_ascii_case(name)
            .then(|| value.trim().to_string())
    })
}

fn test_message(address: &str, subject: &str, message_id: &str) -> anyhow::Result<Vec<u8>> {
    let mailbox: lettre::message::Mailbox = address.parse().context("the mailbox address")?;
    let message = lettre::Message::builder()
        .from(mailbox.clone())
        .to(mailbox)
        .subject(subject)
        .message_id(Some(format!("<{message_id}>")))
        .body("Sent by tradocraft-worker check-mailbox. It is removed again.".to_string())?;
    Ok(message.formatted())
}

/// How long [`GraphClient::check_mailbox`] waits for the test message to arrive.
#[derive(Debug, Clone, Copy)]
pub struct CheckOptions {
    pub tries: usize,
    pub delay: Duration,
}

impl Default for CheckOptions {
    fn default() -> Self {
        Self {
            tries: 12,
            delay: Duration::from_secs(5),
        }
    }
}

/// What Exchange did with the Message-ID of the test message.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MessageIdVerdict {
    /// The one the message was made with, everywhere.
    Kept,
    /// Exchange gave the draft an id of its own, which every copy carries: what the helpdesk
    /// stores is what a customer's reply will cite.
    ReplacedAtDraft,
    /// The copies carry another id than the draft said: what the helpdesk stores is not what a
    /// customer's reply will cite.
    ReplacedAtSend,
}

impl MessageIdVerdict {
    pub fn explain(self) -> &'static str {
        match self {
            Self::Kept => {
                "kept: Exchange leaves the Message-ID of the message as it was made; replies thread by Message-ID"
            }
            Self::ReplacedAtDraft => {
                "replaced when the draft is made, and the same in every copy: the helpdesk stores the one Exchange gave, so replies thread by Message-ID"
            }
            Self::ReplacedAtSend => {
                "WARNING: changed when the message is sent, so the Message-ID the helpdesk stores is not the one customers' replies cite; replies still thread by the ticket number in the subject, but not by Message-ID"
            }
        }
    }
}

#[derive(Debug, Clone)]
pub struct CheckStep {
    pub name: String,
    pub ok: bool,
    pub detail: String,
}

/// The result of [`GraphClient::check_mailbox`].
#[derive(Debug, Clone, Default)]
pub struct CheckReport {
    pub steps: Vec<CheckStep>,
    pub verdict: Option<MessageIdVerdict>,
}

impl CheckReport {
    fn step(&mut self, name: &str, ok: bool, detail: impl Into<String>) {
        self.steps.push(CheckStep {
            name: name.to_string(),
            ok,
            detail: detail.into(),
        });
    }

    /// Every step worked.
    pub fn ok(&self) -> bool {
        !self.steps.is_empty() && self.steps.iter().all(|s| s.ok)
    }

    /// One line per step.
    pub fn lines(&self) -> Vec<String> {
        self.steps
            .iter()
            .map(|s| {
                format!(
                    "{} {}: {}",
                    if s.ok { "ok  " } else { "FAIL" },
                    s.name,
                    s.detail
                )
            })
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ids_are_written_into_an_address_as_one_piece() {
        assert_eq!(encode_segment("AAMkAGI2-xy_z~."), "AAMkAGI2-xy_z~.");
        // `=` is padding in Graph's ids; it is encoded too, which every server decodes.
        assert_eq!(encode_segment("AAA="), "AAA%3D");
        assert_eq!(encode_segment("a/b+c?d#e f"), "a%2Fb%2Bc%3Fd%23e%20f");
        assert_eq!(encode_segment("é"), "%C3%A9");
    }

    #[test]
    fn retry_after_is_a_number_or_a_date() {
        assert_eq!(retry_after_seconds("30"), Some(30));
        assert_eq!(retry_after_seconds(" 7 "), Some(7));
        assert_eq!(retry_after_seconds("999999999"), Some(86_400));
        assert_eq!(retry_after_seconds("soon"), None);
        let in_a_minute = (chrono::Utc::now() + chrono::Duration::seconds(65)).to_rfc2822();
        let s = retry_after_seconds(&in_a_minute).unwrap();
        assert!((55..=65).contains(&s), "{s}");
        assert_eq!(
            retry_after_seconds("Wed, 21 Oct 2015 07:28:00 GMT"),
            Some(0)
        );
    }

    #[test]
    fn only_the_graph_origin_is_followed() {
        let base = "https://graph.microsoft.com/v1.0";
        assert!(same_origin(
            base,
            "https://graph.microsoft.com/v1.0/users/x?$skiptoken=1"
        ));
        assert!(same_origin(base, "https://graph.microsoft.com:443/v1.0/x"));
        assert!(!same_origin(
            base,
            "https://graph.microsoft.com.evil.example/v1.0/x"
        ));
        assert!(!same_origin(
            base,
            "https://evil.example/graph.microsoft.com"
        ));
        assert!(!same_origin(base, "http://graph.microsoft.com/v1.0/x"));
        assert!(!same_origin(
            base,
            "https://graph.microsoft.com:8443/v1.0/x"
        ));
        assert!(!same_origin(base, "not a url"));
        assert!(!same_origin(base, "//graph.microsoft.com/v1.0"));
    }

    #[test]
    fn message_ids_compare_without_brackets() {
        assert_eq!(bare(" <a@b> "), "a@b");
        assert_eq!(bare("a@b"), "a@b");
        assert_eq!(
            header_value(b"From: x\r\nMessage-ID: <a@b>\r\n\r\nbody", "message-id").as_deref(),
            Some("<a@b>")
        );
    }
}
