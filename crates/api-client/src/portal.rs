//! Public knowledge base and customer portal DTOs and endpoints
//! (`/api/v1/public/kb/...` and `/api/v1/portal/...`).

use chrono::{DateTime, NaiveDate, Utc};
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::client::Client;
use crate::error::ApiError;

// -------------------------------------------------------------------------------------------------
// Public Knowledge Base (`/api/v1/public/kb/{company_id}/...`)
// -------------------------------------------------------------------------------------------------

/// Category returned by `GET /api/v1/public/kb/{company_id}/categories`
/// (OpenAPI schema `ReaderCategory`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ReaderCategory {
    pub id: Uuid,
    pub name: String,
    #[serde(default)]
    pub parent_id: Option<Uuid>,
    pub sort_order: i32,
    /// Entries the reader can open in this category, sub-categories included.
    pub entry_count: i64,
}

/// Public summary of a KB hit returned by `GET /api/v1/public/kb/{company_id}/entries`
/// (OpenAPI schema `ReaderSummary`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ReaderSummary {
    pub id: Uuid,
    pub number: String,
    pub slug: String,
    pub language: String,
    pub fallback: bool,
    #[serde(default)]
    pub category_id: Option<Uuid>,
    pub title: String,
    /// Plain text; matched words are wrapped in `U+E000` / `U+E001` when searching.
    pub snippet: String,
    #[serde(default)]
    pub tags: Vec<String>,
    pub updated_at: DateTime<Utc>,
}

/// Image attached to a KB entry (OpenAPI schema `ReaderImage`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ReaderImage {
    pub id: Uuid,
    pub filename: String,
}

/// Related KB article link (OpenAPI schema `ReaderLink`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ReaderLink {
    pub id: Uuid,
    pub number: String,
    pub title: String,
}

/// Full public KB entry returned by `GET /api/v1/public/kb/{company_id}/entries/{id}`
/// (OpenAPI schema `ReaderEntry`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ReaderEntry {
    pub id: Uuid,
    pub number: String,
    pub slug: String,
    /// The language of the text shown.
    pub language: String,
    /// True when the text is not in the language asked for.
    pub fallback: bool,
    #[serde(default)]
    pub available_languages: Vec<String>,
    #[serde(default)]
    pub category_id: Option<Uuid>,
    pub title: String,
    pub summary: String,
    /// Simple Markdown. Images are written as `image:<id>` and listed in `images`.
    pub body: String,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default)]
    pub related: Vec<ReaderLink>,
    #[serde(default)]
    pub images: Vec<ReaderImage>,
    /// The vote of the logged-in contact (portal only): `true` = helpful.
    #[serde(default)]
    pub my_vote: Option<bool>,
    pub updated_at: DateTime<Utc>,
}

/// Optional language query parameter (`nl | fr | en | de | es`).
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
pub struct KbLanguageParams {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub language: Option<String>,
}

impl KbLanguageParams {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn language(mut self, language: impl Into<String>) -> Self {
        self.language = Some(language.into());
        self
    }
}

/// Query parameters for `GET /api/v1/public/kb/{company_id}/entries`.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
pub struct ListPublicKbEntriesParams {
    /// Search words.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub q: Option<String>,
    /// Includes the sub-categories of this category.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub category_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tag: Option<String>,
    /// `nl | fr | en | de | es` (default: the company's language).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub language: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub limit: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub offset: Option<i64>,
}

impl ListPublicKbEntriesParams {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn q(mut self, q: impl Into<String>) -> Self {
        self.q = Some(q.into());
        self
    }

    pub fn category_id(mut self, category_id: Uuid) -> Self {
        self.category_id = Some(category_id);
        self
    }

    pub fn tag(mut self, tag: impl Into<String>) -> Self {
        self.tag = Some(tag.into());
        self
    }

    pub fn language(mut self, language: impl Into<String>) -> Self {
        self.language = Some(language.into());
        self
    }

    pub fn limit(mut self, limit: i64) -> Self {
        self.limit = Some(limit);
        self
    }

    pub fn offset(mut self, offset: i64) -> Self {
        self.offset = Some(offset);
        self
    }
}

// -------------------------------------------------------------------------------------------------
// Customer Portal (`/api/v1/portal/...`)
// -------------------------------------------------------------------------------------------------

/// Request payload for `POST /api/v1/portal/login-links`
/// (OpenAPI schema `LoginLinkInput`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LoginLinkInput {
    /// The company whose portal this is.
    pub company_id: Uuid,
    pub email: String,
}

/// Request payload for `POST /api/v1/portal/sessions`
/// (OpenAPI schema `SessionInput`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SessionInput {
    /// The token from the login link.
    pub token: String,
}

/// Logged-in portal contact profile returned by `GET /api/v1/portal/me`
/// (OpenAPI schema `PortalProfile`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PortalProfile {
    pub contact_id: Uuid,
    pub customer_name: String,
    pub first_name: String,
    pub last_name: String,
    pub full_name: String,
    #[serde(default)]
    pub email: Option<String>,
    pub job_title: String,
    /// `mr | ms | none`
    pub title: String,
    /// `formal | informal`
    pub address_form: String,
    /// The person's own language; `None` means the same as the company.
    #[serde(default)]
    pub language: Option<String>,
    pub customer_language: String,
    /// The language the portal and e-mails use for this person.
    pub effective_language: String,
    pub greeting: String,
    #[serde(default)]
    pub roles: Vec<String>,
    /// `own | customer`
    pub scope: String,
}

/// Session response returned by `POST /api/v1/portal/sessions`
/// (OpenAPI schema `PortalSession`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PortalSession {
    /// Send as `Authorization: Bearer <token>` on every portal request.
    pub token: String,
    pub expires_at: DateTime<Utc>,
    pub profile: PortalProfile,
}

/// Portal ticket summary returned by `GET /api/v1/portal/tickets`
/// (OpenAPI schema `PortalTicket`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PortalTicket {
    pub id: Uuid,
    pub number: String,
    pub subject: String,
    /// `open | pending_customer | closed`
    pub status: String,
    pub category: String,
    /// Who raised it (colleagues' tickets are visible with the `customer` scope).
    pub contact_name: String,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    #[serde(default)]
    pub closed_at: Option<DateTime<Utc>>,
}

/// Attachment metadata returned inside [`PortalMessage`]
/// (OpenAPI schema `FileInfo`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct FileInfo {
    pub id: Uuid,
    pub filename: String,
    /// `image/jpeg | image/png | image/webp | application/pdf`
    pub content_type: String,
    pub size_bytes: i32,
    pub uploader_name: String,
    pub created_at: DateTime<Utc>,
}

/// Message in a portal ticket thread (OpenAPI schema `PortalMessage`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PortalMessage {
    pub id: Uuid,
    /// `incoming` (from the customer) | `outgoing` (from staff)
    pub direction: String,
    pub author_name: String,
    pub body: String,
    pub created_at: DateTime<Utc>,
    /// Files sent with the message. Files on internal notes are never shown.
    #[serde(default)]
    pub attachments: Vec<FileInfo>,
}

/// Portal ticket with message thread returned by `GET /api/v1/portal/tickets/{id}`,
/// `POST /api/v1/portal/tickets`, and `POST /api/v1/portal/tickets/{id}/messages`
/// (OpenAPI schema `PortalTicketDetail`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PortalTicketDetail {
    pub ticket: PortalTicket,
    #[serde(default)]
    pub messages: Vec<PortalMessage>,
}

/// Request payload for `POST /api/v1/portal/tickets`
/// (OpenAPI schema `NewTicket`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct NewTicket {
    pub subject: String,
    /// `question | service | complaint | other`
    #[serde(default = "default_ticket_category")]
    pub category: String,
    pub body: String,
}

fn default_ticket_category() -> String {
    "question".to_string()
}

impl Default for NewTicket {
    fn default() -> Self {
        Self {
            subject: String::new(),
            category: default_ticket_category(),
            body: String::new(),
        }
    }
}

/// Request payload for `POST /api/v1/portal/tickets/{id}/messages`
/// (OpenAPI schema `MessageInput`).
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct MessageInput {
    pub body: String,
    /// Files uploaded to the ticket (`POST /portal/tickets/{id}/attachments`) to send along.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub attachment_ids: Vec<Uuid>,
}

/// Portal order summary returned by `GET /api/v1/portal/orders`
/// (OpenAPI schema `PortalOrder`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PortalOrder {
    pub id: Uuid,
    pub number: String,
    /// `sent | confirmed | cancelled`
    pub status: String,
    /// The revision shown here: the latest that was sent or confirmed, never a draft.
    pub revision: i32,
    pub customer_reference: String,
    pub order_date: NaiveDate,
    pub currency: String,
    pub subtotal: Decimal,
    pub vat_total: Decimal,
    pub total: Decimal,
    #[serde(default)]
    pub confirmed_at: Option<DateTime<Utc>>,
    /// True while this revision is the latest and waits for the customer's confirmation.
    pub can_confirm: bool,
    pub open_priority_requests: i64,
}

/// Line item inside [`PortalOrderDetail`] (OpenAPI schema `PortalOrderLine`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PortalOrderLine {
    pub position: i32,
    pub product_code: String,
    pub description: String,
    pub unit: String,
    pub quantity: Decimal,
    pub list_unit_price: Decimal,
    pub net_unit_price: Decimal,
    pub line_total: Decimal,
    pub vat_rate: Decimal,
}

/// Portal order with line items returned by `GET /api/v1/portal/orders/{id}` and
/// `POST /api/v1/portal/orders/{id}/confirm` (OpenAPI schema `PortalOrderDetail`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PortalOrderDetail {
    pub order: PortalOrder,
    #[serde(default)]
    pub lines: Vec<PortalOrderLine>,
}

/// Request payload for `POST /api/v1/portal/orders/{id}/confirm`
/// (OpenAPI schema `ConfirmPortalOrder`).
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ConfirmPortalOrder {
    /// The revision the customer is looking at; refused when it is no longer the latest.
    pub revision: i32,
    #[serde(default)]
    pub note: String,
}

impl Client {
    /// Lists public KB categories with published public entries
    /// (`GET /api/v1/public/kb/{company_id}/categories`).
    pub async fn list_public_kb_categories(
        &self,
        company_id: Uuid,
        params: &KbLanguageParams,
    ) -> Result<Vec<ReaderCategory>, ApiError> {
        self.get_json(
            &format!("/api/v1/public/kb/{company_id}/categories"),
            params,
        )
        .await
    }

    /// Lists or searches public KB entries (`GET /api/v1/public/kb/{company_id}/entries`).
    pub async fn list_public_kb_entries(
        &self,
        company_id: Uuid,
        params: &ListPublicKbEntriesParams,
    ) -> Result<Vec<ReaderSummary>, ApiError> {
        self.get_json(&format!("/api/v1/public/kb/{company_id}/entries"), params)
            .await
    }

    /// Fetches a single public KB entry (`GET /api/v1/public/kb/{company_id}/entries/{id}`).
    pub async fn get_public_kb_entry(
        &self,
        company_id: Uuid,
        id: Uuid,
        params: &KbLanguageParams,
    ) -> Result<ReaderEntry, ApiError> {
        self.get_json(
            &format!("/api/v1/public/kb/{company_id}/entries/{id}"),
            params,
        )
        .await
    }

    /// Requests a passwordless portal login link (`POST /api/v1/portal/login-links`).
    ///
    /// The server responds with `202 Accepted` and an empty body regardless of whether the
    /// email belongs to an active portal user.
    pub async fn request_portal_login_link(&self, req: &LoginLinkInput) -> Result<(), ApiError> {
        self.post_json_unauthenticated_empty("/api/v1/portal/login-links", req)
            .await
    }

    /// Exchanges a one-time login link token for a portal bearer session
    /// (`POST /api/v1/portal/sessions`).
    pub async fn create_portal_session(
        &self,
        req: &SessionInput,
    ) -> Result<PortalSession, ApiError> {
        self.post_json("/api/v1/portal/sessions", req).await
    }

    /// Fetches the authenticated portal contact profile (`GET /api/v1/portal/me`).
    pub async fn portal_me(&self) -> Result<PortalProfile, ApiError> {
        self.get_json("/api/v1/portal/me", &()).await
    }

    /// Lists portal tickets visible to the logged-in contact (`GET /api/v1/portal/tickets`).
    pub async fn list_portal_tickets(&self) -> Result<Vec<PortalTicket>, ApiError> {
        self.get_json("/api/v1/portal/tickets", &()).await
    }

    /// Fetches a portal ticket and its visible message thread (`GET /api/v1/portal/tickets/{id}`).
    pub async fn get_portal_ticket(&self, id: Uuid) -> Result<PortalTicketDetail, ApiError> {
        self.get_json(&format!("/api/v1/portal/tickets/{id}"), &())
            .await
    }

    /// Opens a new portal ticket (`POST /api/v1/portal/tickets`).
    pub async fn create_portal_ticket(
        &self,
        req: &NewTicket,
    ) -> Result<PortalTicketDetail, ApiError> {
        self.post_json("/api/v1/portal/tickets", req).await
    }

    /// Adds a reply message to a portal ticket (`POST /api/v1/portal/tickets/{id}/messages`).
    pub async fn add_portal_ticket_message(
        &self,
        id: Uuid,
        req: &MessageInput,
    ) -> Result<PortalTicketDetail, ApiError> {
        self.post_json(&format!("/api/v1/portal/tickets/{id}/messages"), req)
            .await
    }

    /// Lists orders visible in the portal (`GET /api/v1/portal/orders`).
    pub async fn list_portal_orders(&self) -> Result<Vec<PortalOrder>, ApiError> {
        self.get_json("/api/v1/portal/orders", &()).await
    }

    /// Fetches a single portal order and its lines (`GET /api/v1/portal/orders/{id}`).
    pub async fn get_portal_order(&self, id: Uuid) -> Result<PortalOrderDetail, ApiError> {
        self.get_json(&format!("/api/v1/portal/orders/{id}"), &())
            .await
    }

    /// Confirms the latest sent revision of a portal order
    /// (`POST /api/v1/portal/orders/{id}/confirm`).
    pub async fn confirm_portal_order(
        &self,
        id: Uuid,
        req: &ConfirmPortalOrder,
    ) -> Result<PortalOrderDetail, ApiError> {
        self.post_json(&format!("/api/v1/portal/orders/{id}/confirm"), req)
            .await
    }
}

#[cfg(test)]
mod tests {
    use std::str::FromStr;

    use super::*;

    #[test]
    fn deserialize_reader_categories() {
        let json = r#"[
            {
                "id": "01900000-0000-7000-8000-000000000011",
                "name": "Installation",
                "parent_id": null,
                "sort_order": 1,
                "entry_count": 4
            },
            {
                "id": "01900000-0000-7000-8000-000000000012",
                "name": "Pumps",
                "parent_id": "01900000-0000-7000-8000-000000000011",
                "sort_order": 2,
                "entry_count": 2
            }
        ]"#;
        let cats: Vec<ReaderCategory> = serde_json::from_str(json).unwrap();
        assert_eq!(cats.len(), 2);
        assert_eq!(cats[0].parent_id, None);
        assert_eq!(cats[0].entry_count, 4);
        assert_eq!(
            cats[1].parent_id,
            Some(Uuid::parse_str("01900000-0000-7000-8000-000000000011").unwrap())
        );
    }

    #[test]
    fn deserialize_reader_summary_and_entry() {
        let summary_json = r#"{
            "id": "01900000-0000-7000-8000-000000000021",
            "number": "KB-0012",
            "slug": "bleeding-circulation-pump",
            "language": "en",
            "fallback": false,
            "category_id": "01900000-0000-7000-8000-000000000011",
            "title": "Bleeding a circulation pump",
            "snippet": "Open the \uE000vent\uE001 screw slowly.",
            "tags": ["pump", "maintenance"],
            "updated_at": "2026-05-01T10:30:00Z"
        }"#;
        let summary: ReaderSummary = serde_json::from_str(summary_json).unwrap();
        assert_eq!(summary.number, "KB-0012");
        assert_eq!(summary.tags, vec!["pump", "maintenance"]);

        let entry_json = r#"{
            "id": "01900000-0000-7000-8000-000000000021",
            "number": "KB-0012",
            "slug": "bleeding-circulation-pump",
            "language": "en",
            "fallback": true,
            "available_languages": ["en", "nl"],
            "category_id": null,
            "title": "Bleeding a circulation pump",
            "summary": "Step-by-step air vent instructions.",
            "body": "1. Switch off power.\n2. Open image:01900000-0000-7000-8000-000000000031",
            "tags": ["pump"],
            "related": [
                {
                    "id": "01900000-0000-7000-8000-000000000022",
                    "number": "KB-0013",
                    "title": "Checking shaft seals"
                }
            ],
            "images": [
                {
                    "id": "01900000-0000-7000-8000-000000000031",
                    "filename": "vent-screw.png"
                }
            ],
            "my_vote": null,
            "updated_at": "2026-05-01T10:30:00Z"
        }"#;
        let entry: ReaderEntry = serde_json::from_str(entry_json).unwrap();
        assert!(entry.fallback);
        assert_eq!(entry.available_languages, vec!["en", "nl"]);
        assert_eq!(entry.related.len(), 1);
        assert_eq!(entry.images.len(), 1);
        assert_eq!(entry.images[0].filename, "vent-screw.png");
        assert_eq!(entry.my_vote, None);
    }

    #[test]
    fn public_kb_query_params_serialize_only_set_fields() {
        let company_id = Uuid::nil();
        let cat_id = Uuid::parse_str("01900000-0000-7000-8000-000000000011").unwrap();
        let params = ListPublicKbEntriesParams::new()
            .q("pump")
            .category_id(cat_id)
            .language("nl")
            .limit(20);
        let req = reqwest::Client::new()
            .get(format!(
                "http://localhost:8080/api/v1/public/kb/{company_id}/entries"
            ))
            .query(&params)
            .build()
            .unwrap();
        assert_eq!(
            req.url().query(),
            Some("q=pump&category_id=01900000-0000-7000-8000-000000000011&language=nl&limit=20")
        );

        let lang_params = KbLanguageParams::new().language("fr");
        let lang_req = reqwest::Client::new()
            .get(format!(
                "http://localhost:8080/api/v1/public/kb/{company_id}/categories"
            ))
            .query(&lang_params)
            .build()
            .unwrap();
        assert_eq!(lang_req.url().query(), Some("language=fr"));
    }

    #[test]
    fn deserialize_portal_auth_and_profile() {
        let login_input: LoginLinkInput = serde_json::from_str(
            r#"{
                "company_id": "01900000-0000-7000-8000-000000000001",
                "email": "buyer@acme.example"
            }"#,
        )
        .unwrap();
        assert_eq!(login_input.email, "buyer@acme.example");

        let session_input: SessionInput =
            serde_json::from_str(r#"{"token":"pll_secret_token"}"#).unwrap();
        assert_eq!(session_input.token, "pll_secret_token");

        let session_json = r#"{
            "token": "ps_live_token",
            "expires_at": "2026-05-10T12:00:00Z",
            "profile": {
                "contact_id": "01900000-0000-7000-8000-000000000050",
                "customer_name": "Acme NV",
                "first_name": "Jan",
                "last_name": "Peeters",
                "full_name": "Jan Peeters",
                "email": "jan@acme.example",
                "job_title": "Purchasing Manager",
                "title": "mr",
                "address_form": "formal",
                "language": null,
                "customer_language": "nl",
                "effective_language": "nl",
                "greeting": "Geachte heer Peeters",
                "roles": ["buyer"],
                "scope": "customer"
            }
        }"#;
        let session: PortalSession = serde_json::from_str(session_json).unwrap();
        assert_eq!(session.token, "ps_live_token");
        assert_eq!(session.profile.customer_name, "Acme NV");
        assert_eq!(session.profile.scope, "customer");
        assert_eq!(session.profile.language, None);
    }

    #[test]
    fn deserialize_portal_tickets_and_inputs() {
        let new_ticket: NewTicket = serde_json::from_str(
            r#"{
                "subject": "Pump vibration",
                "body": "Noise starts above 1500 rpm."
            }"#,
        )
        .unwrap();
        assert_eq!(new_ticket.category, "question");

        let msg_input = MessageInput {
            body: "Attached photo of serial plate.".to_string(),
            attachment_ids: vec![],
        };
        let msg_val = serde_json::to_value(&msg_input).unwrap();
        assert!(msg_val.get("attachment_ids").is_none());
        let msg_roundtrip: MessageInput = serde_json::from_value(msg_val).unwrap();
        assert_eq!(msg_roundtrip.body, msg_input.body);

        let detail_json = r#"{
            "ticket": {
                "id": "01900000-0000-7000-8000-000000000060",
                "number": "TCK-2026-0042",
                "subject": "Pump vibration",
                "status": "pending_customer",
                "category": "service",
                "contact_name": "Jan Peeters",
                "created_at": "2026-05-01T09:00:00Z",
                "updated_at": "2026-05-01T11:15:00Z",
                "closed_at": null
            },
            "messages": [
                {
                    "id": "01900000-0000-7000-8000-000000000061",
                    "direction": "incoming",
                    "author_name": "Jan Peeters",
                    "body": "Noise starts above 1500 rpm.",
                    "created_at": "2026-05-01T09:00:00Z",
                    "attachments": [
                        {
                            "id": "01900000-0000-7000-8000-000000000062",
                            "filename": "plate.jpg",
                            "content_type": "image/jpeg",
                            "size_bytes": 102400,
                            "uploader_name": "Jan Peeters",
                            "created_at": "2026-05-01T09:00:00Z"
                        }
                    ]
                }
            ]
        }"#;
        let detail: PortalTicketDetail = serde_json::from_str(detail_json).unwrap();
        assert_eq!(detail.ticket.number, "TCK-2026-0042");
        assert_eq!(detail.ticket.status, "pending_customer");
        assert_eq!(detail.messages.len(), 1);
        assert_eq!(detail.messages[0].attachments.len(), 1);
        assert_eq!(detail.messages[0].attachments[0].size_bytes, 102400);
    }

    #[test]
    fn deserialize_portal_orders_and_confirm() {
        let detail_json = r#"{
            "order": {
                "id": "01900000-0000-7000-8000-000000000070",
                "number": "SO-2026-0018",
                "status": "sent",
                "revision": 2,
                "customer_reference": "PO-9981",
                "order_date": "2026-05-01",
                "currency": "EUR",
                "subtotal": "1000.00",
                "vat_total": "210.00",
                "total": "1210.00",
                "confirmed_at": null,
                "can_confirm": true,
                "open_priority_requests": 0
            },
            "lines": [
                {
                    "position": 1,
                    "product_code": "PUMP-100",
                    "description": "Circulation Pump 100W",
                    "unit": "pcs",
                    "quantity": "2",
                    "list_unit_price": "550.00",
                    "net_unit_price": "500.00",
                    "line_total": "1000.00",
                    "vat_rate": "21"
                }
            ]
        }"#;
        let detail: PortalOrderDetail = serde_json::from_str(detail_json).unwrap();
        assert_eq!(detail.order.number, "SO-2026-0018");
        assert_eq!(detail.order.revision, 2);
        assert!(detail.order.can_confirm);
        assert_eq!(detail.order.total, Decimal::from_str("1210.00").unwrap());
        assert_eq!(
            detail.order.order_date,
            NaiveDate::from_ymd_opt(2026, 5, 1).unwrap()
        );
        assert_eq!(detail.lines.len(), 1);
        assert_eq!(
            detail.lines[0].net_unit_price,
            Decimal::from_str("500.00").unwrap()
        );

        let confirm: ConfirmPortalOrder = serde_json::from_str(r#"{"revision":2}"#).unwrap();
        assert_eq!(confirm.revision, 2);
        assert_eq!(confirm.note, "");
    }

    #[test]
    fn request_portal_login_link_validates_base_url_via_client() {
        use std::future::Future;
        use std::task::{Context, Poll, RawWaker, RawWakerVTable, Waker};

        fn no_op(_: *const ()) {}
        fn clone(ptr: *const ()) -> RawWaker {
            RawWaker::new(ptr, &VTABLE)
        }
        static VTABLE: RawWakerVTable = RawWakerVTable::new(clone, no_op, no_op, no_op);
        let waker = unsafe { Waker::from_raw(RawWaker::new(std::ptr::null(), &VTABLE)) };
        let mut cx = Context::from_waker(&waker);

        let client = Client::new("");
        let input = LoginLinkInput {
            company_id: Uuid::nil(),
            email: "buyer@acme.example".to_string(),
        };
        let mut fut = Box::pin(client.request_portal_login_link(&input));
        match fut.as_mut().poll(&mut cx) {
            Poll::Ready(Err(ApiError::InvalidConfig(_))) => {}
            other => panic!("expected InvalidConfig, got {other:?}"),
        }
    }
}
