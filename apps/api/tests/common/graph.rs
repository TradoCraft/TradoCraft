//! A stand-in for the parts of Microsoft Graph and the Microsoft sign-in service that the
//! helpdesk's mailboxes use (ADR 0054). Nothing here leaves this machine.
//!
//! The first stand-in answered canned bodies on a few routes and took whatever it was sent. This
//! one keeps a mailbox (inbox, drafts, sent items, deleted items) and holds the client to the
//! contract of Graph v1.0 as its documentation has it:
//!
//! - **Sign-in.** `POST /{tenant}/oauth2/v2.0/token` takes a client-credentials request for its
//!   tenant and secret only. Tokens are issued one by one and live `expires_in` seconds;
//!   [`State::revoke_tokens`] makes every issued token stop working (401 until a new sign-in);
//!   [`State::token_failures`] queues refusals of the sign-in itself.
//! - **Every other route** needs `Authorization: Bearer` with a live token (401), names the
//!   mailbox it holds (404 otherwise), and answers errors as Graph words them (`{"error":
//!   {"code", "message"}}`).
//! - **Messages.** `GET /users/{mb}/mailFolders/{folder}/messages` (filters `isRead eq false`,
//!   `subject eq '…'` and `internetMessageId eq '…'`; `$top`, `$select`, `$skiptoken`, `Prefer:
//!   odata.maxpagesize`; an `$orderby` that is not in the `$filter` is 400 `InefficientFilter`,
//!   as Graph is reported to answer, and an `$expand` is 400); `GET/PATCH/DELETE
//!   /users/{mb}/messages/{id}`; `GET …/$value`; `POST /users/{mb}/messages` makes a draft of
//!   base64 MIME (`Content-Type: text/plain`); `POST …/{id}/send` sends a draft and only a draft.
//! - **Ids.** An id is one piece of an address: one with `/`, `?` or `+` that is not written as
//!   `%XX` names nothing (the address falls apart). Ids are immutable ids only when `Prefer:
//!   IdType="ImmutableId"` is said; otherwise a message answers by an id that
//!   [`State::rotate_ids_after_list`] changes, as the id of a message that is moved does.
//! - **Message-ID.** Whether Exchange keeps the `Message-ID` of a draft, assigns its own when the
//!   draft is made, or changes it when the message is sent is not something this repository has
//!   seen on a real tenant: [`MessageIds`] has all three, and the client has to work with each.
//! - **Faults on demand:** per message [`Fault`] (404, 403, 400, 429 for a few answers);
//!   [`State::fail_next`] (a status for the next request of a kind); [`SendOutcome`] (a gateway
//!   timeout before or after the message went, an answer that never comes); hostile answers
//!   ([`Hostile`]): a next link or redirect to another origin, an id of 5,000 characters.
//!
//! Not modelled: delta queries, attachments and large uploads, mailboxes other than the one.

use std::collections::HashMap;
use std::sync::{Arc, Mutex, MutexGuard};
use std::time::Duration;

use axum::body::Bytes;
use axum::extract::State as AxumState;
use axum::http::{HeaderMap, HeaderValue, Method, StatusCode, Uri};
use axum::response::{IntoResponse, Response};
use base64::Engine;
use serde_json::{json, Value};
use tradocraft_helpdesk::graph::GraphClient;

pub const TENANT: &str = "contoso.onmicrosoft.com";
pub const CLIENT_SECRET: &str = "s3cret-value";
pub const MAILBOX: &str = "support@contoso.example";

/// What Exchange does with the `Message-ID` of a message made from MIME.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum MessageIds {
    /// Keeps the one in the MIME, in the draft and in every copy.
    Kept,
    /// Assigns its own when the draft is made; the draft and every copy carry it.
    AssignedAtDraft,
    /// The draft says the one in the MIME, and the sent and delivered copies carry another.
    ChangedAtSend,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Fault {
    /// 404 `ErrorItemNotFound`, every time.
    Gone,
    /// 403 `ErrorAccessDenied`, every time.
    Denied,
    /// 400 `ErrorInvalidRequest`, every time.
    Invalid,
    /// 429 for this many requests, then as usual.
    Throttled(usize),
}

/// What `POST …/send` does.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SendOutcome {
    Normal,
    /// 504, and the message was not sent.
    GatewayTimeoutBefore,
    /// The message is sent, then 504: the gateway gave up waiting for the answer.
    GatewayTimeoutAfter,
    /// The message is sent, and the answer comes after this long.
    SlowAfter(Duration),
}

#[derive(Clone, Debug, PartialEq, Eq, Default)]
pub enum Hostile {
    #[default]
    None,
    /// The first page of a list names this address as the next page.
    NextLink(String),
    /// A list is answered with a redirect to this address.
    Redirect(String),
    /// The message with this key is listed under an id of 5,000 characters.
    HugeId(String),
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Folder {
    Inbox,
    Drafts,
    SentItems,
    Deleted,
}

impl Folder {
    fn named(name: &str) -> Option<Folder> {
        Some(match name.to_ascii_lowercase().as_str() {
            "inbox" => Folder::Inbox,
            "drafts" => Folder::Drafts,
            "sentitems" => Folder::SentItems,
            "deleteditems" => Folder::Deleted,
            _ => return None,
        })
    }
}

#[derive(Clone, Debug)]
pub struct Msg {
    /// The immutable id.
    pub key: String,
    /// The id of the message where it is now; changes when it is moved.
    pub mutable: String,
    pub folder: Folder,
    pub read: bool,
    pub internet_id: String,
    pub subject: String,
    pub to: Vec<String>,
    pub mime: Vec<u8>,
}

/// A request as the stand-in saw it, for a test to look at.
#[derive(Clone, Debug)]
pub struct Logged {
    pub method: String,
    /// The path as it came, percent-encoding and all.
    pub path: String,
    pub query: String,
    pub prefer: Option<String>,
}

pub struct State {
    pub base: String,
    pub token_requests: usize,
    pub last_token_form: String,
    /// How long a token lives, in seconds.
    pub expires_in: u64,
    issued: Vec<String>,
    live: Vec<String>,
    /// Refusals of the sign-in, taken one at a time: (status, body).
    pub token_failures: Vec<(u16, Value)>,
    pub messages: Vec<Msg>,
    pub faults: HashMap<String, Fault>,
    pub ids: MessageIds,
    pub rotate_ids_after_list: bool,
    /// Messages in a page when the client does not say.
    pub page_size: usize,
    /// `(kind, status, code)`: the next request of this kind (`list`, `value`, `patch`, `get`,
    /// `draft`, `send`, `delete`) is answered so.
    pub fail_next: Vec<(String, u16, String)>,
    pub send_outcome: SendOutcome,
    pub hostile: Hostile,
    pub requests: Vec<Logged>,
    /// The MIME of every message that was sent.
    pub sent_mimes: Vec<Vec<u8>>,
    /// The keys of messages marked read, in order.
    pub read_marks: Vec<String>,
    /// The keys of messages deleted, in order.
    pub deleted: Vec<String>,
    counter: usize,
    retry_after: String,
}

pub type Shared = Arc<Mutex<State>>;

/// What a request is answered with.
enum Reply {
    Json(u16, Value),
    JsonWith(u16, Value, Vec<(&'static str, String)>),
    Bytes(u16, Vec<u8>),
    Empty(u16),
    Redirect(String),
    Later(Duration, Box<Reply>),
}

fn error(status: u16, code: &str, message: &str) -> Reply {
    Reply::Json(
        status,
        json!({ "error": { "code": code, "message": message } }),
    )
}

/// The stand-in, listening on a port of this machine.
pub struct Standin {
    shared: Shared,
    pub base: String,
}

impl Standin {
    pub async fn start() -> Standin {
        let shared: Shared = Arc::new(Mutex::new(State::new()));
        let app = axum::Router::new()
            .fallback(handle)
            .with_state(shared.clone());
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let base = format!("http://{}", listener.local_addr().unwrap());
        shared.lock().unwrap().base = base.clone();
        tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
        Standin { shared, base }
    }

    /// A client whose Graph and sign-in services are this stand-in.
    pub fn client(&self) -> GraphClient {
        GraphClient::with_urls(
            &format!("{}/v1.0", self.base),
            &format!("{}/login", self.base),
        )
    }

    pub fn state(&self) -> MutexGuard<'_, State> {
        self.shared.lock().unwrap()
    }
}

/// What reached the second listener: a path and the `Authorization` header it came with.
pub type Hit = (String, Option<String>);

/// A second listener standing for "somewhere else": it records what reaches it.
pub struct Evil {
    pub base: String,
    pub hits: Arc<Mutex<Vec<Hit>>>,
}

impl Evil {
    pub async fn start() -> Evil {
        let hits: Arc<Mutex<Vec<Hit>>> = Arc::default();
        let seen = hits.clone();
        let app = axum::Router::new().fallback(move |uri: Uri, headers: HeaderMap| {
            let seen = seen.clone();
            async move {
                seen.lock().unwrap().push((
                    uri.path().to_string(),
                    headers
                        .get("authorization")
                        .and_then(|v| v.to_str().ok())
                        .map(str::to_string),
                ));
                (StatusCode::OK, "{}")
            }
        });
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let base = format!("http://{}", listener.local_addr().unwrap());
        tokio::spawn(async move { axum::serve(listener, app).await.unwrap() });
        Evil { base, hits }
    }

    pub fn count(&self) -> usize {
        self.hits.lock().unwrap().len()
    }
}

/// A plain-text e-mail as raw MIME.
pub fn mail(from: &str, to: &str, subject: &str, headers: &str) -> Vec<u8> {
    format!(
        "From: {from}\r\nTo: {to}\r\nSubject: {subject}\r\n{headers}Content-Type: text/plain; charset=utf-8\r\n\r\nHello\r\n"
    )
    .into_bytes()
}

/// The value of a header of raw MIME.
pub fn header(mime: &[u8], name: &str) -> Option<String> {
    let text = String::from_utf8_lossy(mime);
    let head = text.split("\r\n\r\n").next()?;
    head.lines().find_map(|line| {
        let (have, value) = line.split_once(':')?;
        have.trim()
            .eq_ignore_ascii_case(name)
            .then(|| value.trim().to_string())
    })
}

fn replace_message_id(mime: &[u8], id: &str) -> Vec<u8> {
    let text = String::from_utf8_lossy(mime).to_string();
    let mut out = Vec::new();
    let mut replaced = false;
    let (head, body) = text.split_once("\r\n\r\n").unwrap_or((&text, ""));
    for line in head.lines() {
        if line.to_ascii_lowercase().starts_with("message-id:") {
            out.push(format!("Message-ID: {id}"));
            replaced = true;
        } else {
            out.push(line.to_string());
        }
    }
    if !replaced {
        out.push(format!("Message-ID: {id}"));
    }
    format!("{}\r\n\r\n{body}", out.join("\r\n")).into_bytes()
}

fn pct_decode(text: &str) -> String {
    let bytes = text.as_bytes();
    let mut out = Vec::new();
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' && i + 2 < bytes.len() {
            if let Ok(v) = u8::from_str_radix(&text[i + 1..i + 3], 16) {
                out.push(v);
                i += 3;
                continue;
            }
        }
        out.push(bytes[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).to_string()
}

fn query_of(raw: &str) -> HashMap<String, String> {
    raw.split('&')
        .filter(|p| !p.is_empty())
        .map(|p| {
            let (k, v) = p.split_once('=').unwrap_or((p, ""));
            (pct_decode(k), pct_decode(v))
        })
        .collect()
}

async fn handle(
    AxumState(shared): AxumState<Shared>,
    method: Method,
    uri: Uri,
    headers: HeaderMap,
    body: Bytes,
) -> Response {
    let reply = {
        let mut state = shared.lock().unwrap();
        state.route(&method, &uri, &headers, &body)
    };
    respond(reply).await
}

fn respond(reply: Reply) -> std::pin::Pin<Box<dyn std::future::Future<Output = Response> + Send>> {
    Box::pin(async move {
        match reply {
            Reply::Json(status, v) => (
                StatusCode::from_u16(status).unwrap(),
                [("content-type", "application/json")],
                v.to_string(),
            )
                .into_response(),
            Reply::JsonWith(status, v, extra) => {
                let mut r = (
                    StatusCode::from_u16(status).unwrap(),
                    [("content-type", "application/json")],
                    v.to_string(),
                )
                    .into_response();
                for (k, v) in extra {
                    r.headers_mut()
                        .insert(k, HeaderValue::from_str(&v).unwrap());
                }
                r
            }
            Reply::Bytes(status, b) => (
                StatusCode::from_u16(status).unwrap(),
                [("content-type", "message/rfc822")],
                b,
            )
                .into_response(),
            Reply::Empty(status) => StatusCode::from_u16(status).unwrap().into_response(),
            Reply::Redirect(to) => {
                (StatusCode::FOUND, [("location", to)], String::new()).into_response()
            }
            Reply::Later(d, inner) => {
                tokio::time::sleep(d).await;
                respond(*inner).await
            }
        }
    })
}

impl State {
    fn new() -> State {
        State {
            base: String::new(),
            token_requests: 0,
            last_token_form: String::new(),
            expires_in: 3599,
            issued: Vec::new(),
            live: Vec::new(),
            token_failures: Vec::new(),
            messages: Vec::new(),
            faults: HashMap::new(),
            ids: MessageIds::AssignedAtDraft,
            rotate_ids_after_list: false,
            page_size: 50,
            fail_next: Vec::new(),
            send_outcome: SendOutcome::Normal,
            hostile: Hostile::None,
            requests: Vec::new(),
            sent_mimes: Vec::new(),
            read_marks: Vec::new(),
            deleted: Vec::new(),
            counter: 0,
            retry_after: "30".into(),
        }
    }

    /// An unread message in the inbox.
    pub fn add_unread(&mut self, key: &str, mime: Vec<u8>) {
        let m = Msg {
            key: key.to_string(),
            mutable: format!("{key}-m0"),
            folder: Folder::Inbox,
            read: false,
            internet_id: header(&mime, "Message-ID").unwrap_or_default(),
            subject: header(&mime, "Subject").unwrap_or_default(),
            to: Vec::new(),
            mime,
        };
        self.messages.push(m);
    }

    /// Every token issued so far stops working.
    pub fn revoke_tokens(&mut self) {
        self.live.clear();
    }

    pub fn in_folder(&self, folder: Folder) -> Vec<&Msg> {
        self.messages
            .iter()
            .filter(|m| m.folder == folder)
            .collect()
    }

    /// The number of messages sent so far.
    pub fn sent_count(&self) -> usize {
        self.sent_mimes.len()
    }

    pub fn is_read(&self, key: &str) -> bool {
        self.messages.iter().any(|m| m.key == key && m.read)
    }

    fn id_form(&self, m: &Msg, prefer: &Option<String>) -> String {
        if prefers_immutable(prefer) {
            m.key.clone()
        } else {
            m.mutable.clone()
        }
    }

    /// The message an id names: its immutable id always, its other id only while that is its id.
    fn find(&self, id: &str) -> Option<usize> {
        self.messages
            .iter()
            .position(|m| m.key == id || m.mutable == id)
    }

    fn take_fail(&mut self, kind: &str) -> Option<Reply> {
        let at = self.fail_next.iter().position(|(k, _, _)| k == kind)?;
        let (_, status, code) = self.fail_next.remove(at);
        let message = match status {
            403 => "Access is denied. Check credentials and try again.",
            429 => "Too many requests",
            _ => "Failed on demand.",
        };
        let body = json!({ "error": { "code": code, "message": message } });
        Some(if status == 429 {
            Reply::JsonWith(
                status,
                body,
                vec![("retry-after", self.retry_after.clone())],
            )
        } else {
            Reply::Json(status, body)
        })
    }

    fn fault_for(&mut self, key: &str) -> Option<Reply> {
        let fault = *self.faults.get(key)?;
        Some(match fault {
            Fault::Gone => error(
                404,
                "ErrorItemNotFound",
                "The specified object was not found in the store.",
            ),
            Fault::Denied => error(
                403,
                "ErrorAccessDenied",
                "Access is denied. Check credentials and try again.",
            ),
            Fault::Invalid => error(400, "ErrorInvalidRequest", "The request is invalid."),
            Fault::Throttled(n) => {
                if n <= 1 {
                    self.faults.remove(key);
                } else {
                    self.faults.insert(key.to_string(), Fault::Throttled(n - 1));
                }
                Reply::JsonWith(
                    429,
                    json!({ "error": { "code": "TooManyRequests", "message": "Too many requests" } }),
                    vec![("retry-after", self.retry_after.clone())],
                )
            }
        })
    }

    fn route(&mut self, method: &Method, uri: &Uri, headers: &HeaderMap, body: &Bytes) -> Reply {
        let path = uri.path().to_string();
        let query = uri.query().unwrap_or("").to_string();
        let prefer = headers
            .get("prefer")
            .and_then(|v| v.to_str().ok())
            .map(str::to_string);
        self.requests.push(Logged {
            method: method.to_string(),
            path: path.clone(),
            query: query.clone(),
            prefer: prefer.clone(),
        });
        let parts: Vec<&str> = path.trim_start_matches('/').split('/').collect();
        // The sign-in service.
        if parts.len() == 5 && parts[0] == "login" && parts[2] == "oauth2" && parts[4] == "token" {
            return self.token(method, parts[1], body);
        }
        if parts.len() < 3 || parts[0] != "v1.0" || parts[1] != "users" {
            return error(
                404,
                "ResourceNotFound",
                "Resource not found for the segment.",
            );
        }
        let live = headers
            .get("authorization")
            .and_then(|v| v.to_str().ok())
            .and_then(|v| v.strip_prefix("Bearer "))
            .is_some_and(|t| self.live.iter().any(|l| l == t));
        if !live {
            return error(401, "InvalidAuthenticationToken", "Access token is empty.");
        }
        if pct_decode(parts[2]) != MAILBOX {
            return error(
                404,
                "ResourceNotFound",
                "The specified user could not be found.",
            );
        }
        let rest = &parts[3..];
        match (method.as_str(), rest) {
            ("GET", ["mailFolders", folder, "messages"]) => self.list(folder, &query, &prefer),
            ("POST", ["messages"]) => self.make_draft(headers, body, &prefer),
            ("GET", ["messages", id, "$value"]) => self.value(id),
            ("POST", ["messages", id, "send"]) => self.send(id),
            ("GET", ["messages", id]) => self.get(id, &prefer),
            ("PATCH", ["messages", id]) => self.patch(id, headers, body),
            ("DELETE", ["messages", id]) => self.delete(id),
            _ => error(
                404,
                "ResourceNotFound",
                "Resource not found for the segment.",
            ),
        }
    }

    fn token(&mut self, method: &Method, tenant: &str, body: &Bytes) -> Reply {
        let form = String::from_utf8_lossy(body).to_string();
        self.token_requests += 1;
        self.last_token_form = form.clone();
        if method != Method::POST {
            return error(405, "MethodNotAllowed", "POST only.");
        }
        if !self.token_failures.is_empty() {
            let (status, body) = self.token_failures.remove(0);
            return Reply::Json(status, body);
        }
        let wrong = |why: &str| {
            Reply::Json(
                401,
                json!({ "error": "invalid_client",
                        "error_description": format!("AADSTS7000215: {why}\r\nTrace ID: x") }),
            )
        };
        if tenant != TENANT {
            return Reply::Json(
                400,
                json!({ "error": "invalid_request",
                        "error_description": "AADSTS90002: Tenant not found.\r\nTrace ID: x" }),
            );
        }
        if !form.contains("grant_type=client_credentials") {
            return Reply::Json(400, json!({ "error": "unsupported_grant_type" }));
        }
        if !form.contains(&format!("client_secret={CLIENT_SECRET}")) {
            return wrong("Invalid client secret provided.");
        }
        self.counter += 1;
        let token = format!("token-{}", self.counter);
        self.issued.push(token.clone());
        self.live.push(token.clone());
        Reply::Json(
            200,
            json!({ "token_type": "Bearer", "expires_in": self.expires_in, "access_token": token }),
        )
    }

    fn list(&mut self, folder: &str, raw_query: &str, prefer: &Option<String>) -> Reply {
        if let Some(r) = self.take_fail("list") {
            return r;
        }
        if let Hostile::Redirect(to) = self.hostile.clone() {
            return Reply::Redirect(to);
        }
        let Some(folder) = Folder::named(folder) else {
            return error(404, "ErrorInvalidParameter", "The folder does not exist.");
        };
        let q = query_of(raw_query);
        if q.contains_key("$expand") {
            return error(400, "BadRequest", "Parsing OData Select and Expand failed.");
        }
        let filter = q.get("$filter").cloned().unwrap_or_default();
        if let Some(order) = q.get("$orderby") {
            let property = order.split_whitespace().next().unwrap_or_default();
            if !filter.contains(property) {
                return error(
                    400,
                    "InefficientFilter",
                    "The restriction or sort order is too complex for this operation.",
                );
            }
        }
        enum Want {
            All,
            Unread,
            Subject(String),
            InternetId(String),
        }
        let want = if filter.is_empty() {
            Want::All
        } else if filter == "isRead eq false" {
            Want::Unread
        } else if let Some(v) = filter
            .strip_prefix("subject eq '")
            .and_then(|v| v.strip_suffix('\''))
        {
            Want::Subject(v.to_string())
        } else if let Some(v) = filter
            .strip_prefix("internetMessageId eq '")
            .and_then(|v| v.strip_suffix('\''))
        {
            Want::InternetId(v.to_string())
        } else {
            return error(400, "BadRequest", "Invalid filter clause.");
        };
        let matching: Vec<usize> = self
            .messages
            .iter()
            .enumerate()
            .filter(|(_, m)| m.folder == folder)
            .filter(|(_, m)| match &want {
                Want::All => true,
                Want::Unread => !m.read,
                Want::Subject(s) => &m.subject == s,
                Want::InternetId(s) => &m.internet_id == s,
            })
            .map(|(i, _)| i)
            .collect();
        let skip: usize = q
            .get("$skiptoken")
            .and_then(|t| t.parse().ok())
            .unwrap_or(0);
        let top: usize = q
            .get("$top")
            .and_then(|t| t.parse().ok())
            .unwrap_or(self.page_size);
        let max_page: usize = prefer
            .as_deref()
            .and_then(|p| p.split("odata.maxpagesize=").nth(1))
            .and_then(|p| p.split([',', ';']).next())
            .and_then(|p| p.trim().parse().ok())
            .unwrap_or(usize::MAX);
        let size = top.min(self.page_size).min(max_page).max(1);
        let page: Vec<usize> = matching.iter().skip(skip).take(size).copied().collect();
        let entries: Vec<Value> = page
            .iter()
            .map(|&i| {
                let m = &self.messages[i];
                let id = match &self.hostile {
                    Hostile::HugeId(key) if *key == m.key => "X".repeat(5_000),
                    _ => self.id_form(m, prefer),
                };
                json!({ "id": id, "internetMessageId": m.internet_id,
                        "subject": m.subject, "isRead": m.read })
            })
            .collect();
        let mut answer = json!({ "value": entries });
        if skip + size < matching.len() {
            answer["@odata.nextLink"] = match (&self.hostile, skip) {
                (Hostile::NextLink(elsewhere), 0) => json!(elsewhere),
                _ => json!(format!(
                    "{}/v1.0/users/{MAILBOX}/mailFolders/{}/messages?{}&$skiptoken={}",
                    self.base,
                    match folder {
                        Folder::Inbox => "inbox",
                        Folder::Drafts => "drafts",
                        Folder::SentItems => "sentitems",
                        Folder::Deleted => "deleteditems",
                    },
                    raw_query
                        .split('&')
                        .filter(|p| !p.starts_with("$skiptoken="))
                        .collect::<Vec<_>>()
                        .join("&"),
                    skip + size
                )),
            };
        }
        if self.rotate_ids_after_list {
            for m in &mut self.messages {
                m.mutable.push_str("-r");
            }
        }
        Reply::Json(200, answer)
    }

    fn value(&mut self, id: &str) -> Reply {
        if let Some(r) = self.take_fail("value") {
            return r;
        }
        let id = pct_decode(id);
        let Some(i) = self.find(&id) else {
            return error(
                404,
                "ErrorItemNotFound",
                "The specified object was not found in the store.",
            );
        };
        let key = self.messages[i].key.clone();
        if let Some(r) = self.fault_for(&key) {
            return r;
        }
        Reply::Bytes(200, self.messages[i].mime.clone())
    }

    fn get(&mut self, id: &str, prefer: &Option<String>) -> Reply {
        if let Some(r) = self.take_fail("get") {
            return r;
        }
        let id = pct_decode(id);
        match self.find(&id) {
            Some(i) => {
                let m = &self.messages[i];
                Reply::Json(
                    200,
                    json!({ "id": self.id_form(m, prefer), "isDraft": m.folder == Folder::Drafts }),
                )
            }
            None => error(
                404,
                "ErrorItemNotFound",
                "The specified object was not found in the store.",
            ),
        }
    }

    fn patch(&mut self, id: &str, headers: &HeaderMap, body: &Bytes) -> Reply {
        if let Some(r) = self.take_fail("patch") {
            return r;
        }
        let id = pct_decode(id);
        let json_type = headers
            .get("content-type")
            .and_then(|v| v.to_str().ok())
            .is_some_and(|t| t.starts_with("application/json"));
        let Ok(v) = serde_json::from_slice::<Value>(body) else {
            return error(400, "ErrorInvalidRequest", "The request body is not JSON.");
        };
        if !json_type || v != json!({ "isRead": true }) {
            return error(
                400,
                "ErrorInvalidRequest",
                "Only isRead can be changed here.",
            );
        }
        let Some(i) = self.find(&id) else {
            return error(
                404,
                "ErrorItemNotFound",
                "The specified object was not found in the store.",
            );
        };
        let key = self.messages[i].key.clone();
        if let Some(r) = self.fault_for(&key) {
            return r;
        }
        self.messages[i].read = true;
        self.read_marks.push(key);
        Reply::Json(200, json!({}))
    }

    fn delete(&mut self, id: &str) -> Reply {
        if let Some(r) = self.take_fail("delete") {
            return r;
        }
        let id = pct_decode(id);
        let Some(i) = self.find(&id) else {
            return error(
                404,
                "ErrorItemNotFound",
                "The specified object was not found in the store.",
            );
        };
        self.deleted.push(self.messages[i].key.clone());
        self.messages[i].folder = Folder::Deleted;
        Reply::Empty(204)
    }

    fn make_draft(&mut self, headers: &HeaderMap, body: &Bytes, prefer: &Option<String>) -> Reply {
        if let Some(r) = self.take_fail("draft") {
            return r;
        }
        let text_plain = headers
            .get("content-type")
            .and_then(|v| v.to_str().ok())
            .is_some_and(|t| t.to_ascii_lowercase().starts_with("text/plain"));
        if !text_plain {
            return error(
                415,
                "ErrorUnsupportedMediaType",
                "A draft is made of MIME as text/plain here.",
            );
        }
        let Ok(mime) = base64::engine::general_purpose::STANDARD.decode(body.as_ref().trim_ascii())
        else {
            return error(
                400,
                "ErrorMimeContentInvalidBase64String",
                "The MIME content is not valid base64.",
            );
        };
        self.counter += 1;
        let n = self.counter;
        let mime_id = header(&mime, "Message-ID").unwrap_or_default();
        let internet_id = match self.ids {
            MessageIds::AssignedAtDraft => format!("<EXCH-{n}@prod.outlook.com>"),
            _ => mime_id,
        };
        let to: Vec<String> = header(&mime, "To")
            .map(|v| {
                v.split(',')
                    .map(|a| {
                        let a = a.trim();
                        a.rsplit_once('<')
                            .map_or(a, |(_, r)| r.trim_end_matches('>'))
                            .to_string()
                    })
                    .filter(|a| !a.is_empty())
                    .collect()
            })
            .unwrap_or_default();
        let m = Msg {
            key: format!("draft-{n}"),
            mutable: format!("draft-{n}-m0"),
            folder: Folder::Drafts,
            read: true,
            internet_id,
            subject: header(&mime, "Subject").unwrap_or_default(),
            to,
            mime,
        };
        let answer = json!({ "id": self.id_form(&m, prefer), "internetMessageId": m.internet_id,
                             "isDraft": true });
        self.messages.push(m);
        Reply::Json(201, answer)
    }

    fn send(&mut self, id: &str) -> Reply {
        if let Some(r) = self.take_fail("send") {
            return r;
        }
        let id = pct_decode(id);
        let Some(i) = self.find(&id) else {
            return error(
                404,
                "ErrorItemNotFound",
                "The specified object was not found in the store.",
            );
        };
        if self.messages[i].folder != Folder::Drafts {
            return error(400, "ErrorInvalidRequest", "Only a draft can be sent.");
        }
        if self.messages[i].to.is_empty() {
            return error(
                400,
                "ErrorInvalidRecipients",
                "At least one recipient is required.",
            );
        }
        let key = self.messages[i].key.clone();
        if let Some(r) = self.fault_for(&key) {
            return r;
        }
        if self.send_outcome == SendOutcome::GatewayTimeoutBefore {
            return error(
                504,
                "ErrorTimeoutExpired",
                "The gateway did not get an answer in time.",
            );
        }
        self.deliver(i);
        match self.send_outcome {
            SendOutcome::GatewayTimeoutAfter => error(
                504,
                "ErrorTimeoutExpired",
                "The gateway did not get an answer in time.",
            ),
            SendOutcome::SlowAfter(d) => Reply::Later(d, Box::new(Reply::Empty(202))),
            _ => Reply::Empty(202),
        }
    }

    /// The draft at `i` is sent: it leaves Drafts, a copy is filed in Sent Items, and a copy
    /// arrives in the inbox when one of its recipients is this mailbox.
    fn deliver(&mut self, i: usize) {
        let draft = self.messages.remove(i);
        self.counter += 1;
        let n = self.counter;
        let mime_id = header(&draft.mime, "Message-ID").unwrap_or_default();
        let final_id = match self.ids {
            MessageIds::Kept => mime_id,
            MessageIds::AssignedAtDraft => draft.internet_id.clone(),
            MessageIds::ChangedAtSend => format!("<changed-{n}@prod.outlook.com>"),
        };
        let mime = replace_message_id(&draft.mime, &final_id);
        self.sent_mimes.push(draft.mime.clone());
        let copy = |folder: Folder, read: bool, suffix: &str| Msg {
            key: format!("{}-{suffix}", draft.key),
            mutable: format!("{}-{suffix}-m0", draft.key),
            folder,
            read,
            internet_id: final_id.clone(),
            subject: draft.subject.clone(),
            to: draft.to.clone(),
            mime: mime.clone(),
        };
        self.messages.push(copy(Folder::SentItems, true, "sent"));
        if draft.to.iter().any(|a| a.eq_ignore_ascii_case(MAILBOX)) {
            self.messages.push(copy(Folder::Inbox, false, "in"));
        }
    }
}

fn prefers_immutable(prefer: &Option<String>) -> bool {
    prefer
        .as_deref()
        .is_some_and(|p| p.replace(' ', "").contains("IdType=\"ImmutableId\""))
}
