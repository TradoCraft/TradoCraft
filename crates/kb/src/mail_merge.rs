//! Saved, staff-only drafts and read-only audience previews. A preview does not enqueue mail.
//! Every mailing carries an unsubscribe link; addresses on the company's opt-out register are
//! left out (ADR 0099).
use std::collections::{BTreeMap, HashMap, HashSet};

use axum::{
    extract::{Path, State},
    http::StatusCode,
    Json,
};
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection};
use tradocraft_core::{audit, AppError, AppResult, AppState, CurrentUser, Permission};
use utoipa::ToSchema;
use utoipa_axum::{router::OpenApiRouter, routes};
use uuid::Uuid;

use crate::unsubscribe;

type ErrorBody = tradocraft_core::error::ErrorBody;

const LANGUAGES: [&str; 5] = ["en", "nl", "fr", "de", "es"];

#[derive(Deserialize, Serialize, ToSchema)]
struct MailMergeMessage {
    subject: String,
    body: String,
}

#[derive(Deserialize, Serialize, ToSchema)]
struct MailMergeDraft {
    document_id: Uuid,
    revision: i32,
    messages: BTreeMap<String, MailMergeMessage>,
    #[serde(default)]
    recipients: BTreeMap<Uuid, Uuid>,
}

#[derive(Deserialize, Serialize, FromRow, ToSchema)]
struct MailMergeContact {
    customer_id: Uuid,
    id: Uuid,
    name: String,
    language: Option<String>,
    email: Option<String>,
}

#[derive(FromRow)]
struct Customer {
    id: Uuid,
    name: String,
    language: String,
    email: Option<String>,
}

#[derive(Deserialize, Serialize, ToSchema)]
struct MailMergeRecipient {
    customer_id: Uuid,
    customer_name: String,
    contact_id: Option<Uuid>,
    contacts: Vec<MailMergeContact>,
    language: String,
    email: Option<String>,
    subject: Option<String>,
    body: Option<String>,
    /// The unsubscribe footer appended below the body when the mail is queued; the link in the
    /// preview is a placeholder, each delivery gets its own.
    #[serde(default)]
    footer: Option<String>,
    pdf: Option<String>,
    issues: Vec<String>,
}

#[derive(Deserialize, Serialize, ToSchema)]
struct MailMergePreview {
    approval_id: Option<Uuid>,
    draft: Option<MailMergeDraft>,
    audience: Vec<MailMergeRecipient>,
}

fn authorize(user: &CurrentUser) -> AppResult<()> {
    user.require(Permission::CustomersWrite)?;
    user.require(Permission::KbRead)
}

#[utoipa::path(get, path = "/customers/mail-merge", tag = "crm", operation_id = "get_mail_merge_draft",
    responses((status = 200, body = MailMergePreview)))]
async fn get_draft(
    State(state): State<AppState>,
    user: CurrentUser,
) -> AppResult<Json<MailMergePreview>> {
    authorize(&user)?;
    let saved: Option<Option<sqlx::types::Json<MailMergePreview>>> = sqlx::query_scalar(
        "SELECT approved_preview FROM crm.mail_merge_drafts WHERE company_id = $1 AND user_id = $2",
    )
    .bind(user.company_id)
    .bind(user.user_id)
    .fetch_optional(&state.db)
    .await?;
    if let Some(Some(preview)) = saved {
        return Ok(Json(preview.0));
    }
    let draft: Option<sqlx::types::Json<MailMergeDraft>> = sqlx::query_scalar(
        "SELECT jsonb_build_object('document_id',document_id,'revision',revision,'messages',messages,'recipients',recipients)
         FROM crm.mail_merge_drafts WHERE company_id = $1 AND user_id = $2",
    ).bind(user.company_id).bind(user.user_id).fetch_optional(&state.db).await?;
    let mut conn = state.db.acquire().await?;
    build_preview(&mut conn, &user, draft.map(|row| row.0))
        .await
        .map(Json)
}

#[utoipa::path(put, path = "/customers/mail-merge", tag = "crm", operation_id = "save_mail_merge_draft",
    request_body = MailMergeDraft, responses((status = 200, body = MailMergePreview)))]
async fn save_draft(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(draft): Json<MailMergeDraft>,
) -> AppResult<Json<MailMergePreview>> {
    authorize(&user)?;
    for (language, message) in &draft.messages {
        if !LANGUAGES.contains(&language.as_str())
            || message.subject.contains(['\r', '\n'])
            || message.subject.len() > 500
            || message.body.len() > 32_000
        {
            return Err(AppError::Validation(
                "invalid mailing language, subject or body".into(),
            ));
        }
    }
    let mut conn = state.db.acquire().await?;
    let mut result = build_preview(&mut conn, &user, Some(draft)).await?;
    result.approval_id = Some(tradocraft_core::new_id());
    let draft = result.draft.as_ref().expect("saved draft");
    let saved: sqlx::types::Json<MailMergePreview> = sqlx::query_scalar(
        "INSERT INTO crm.mail_merge_drafts (company_id,user_id,document_id,revision,messages,recipients,approved_preview)
         VALUES ($1,$2,$3,$4,$5,$6,$7)
         ON CONFLICT (company_id,user_id) DO UPDATE SET document_id=excluded.document_id,
          revision=excluded.revision,messages=excluded.messages,recipients=excluded.recipients,
          approved_preview=CASE
            WHEN crm.mail_merge_drafts.approved_preview - 'approval_id' = excluded.approved_preview - 'approval_id'
            THEN crm.mail_merge_drafts.approved_preview ELSE excluded.approved_preview END
         RETURNING approved_preview",
    ).bind(user.company_id).bind(user.user_id).bind(draft.document_id).bind(draft.revision)
     .bind(sqlx::types::Json(&draft.messages)).bind(sqlx::types::Json(&draft.recipients)).bind(sqlx::types::Json(&result))
     .fetch_one(&mut *conn).await?;
    Ok(Json(saved.0))
}

fn usable_email(value: &str) -> bool {
    let Some((local, domain)) = value.split_once('@') else {
        return false;
    };
    !local.is_empty()
        && !domain.is_empty()
        && !domain.contains('@')
        && !value
            .chars()
            .any(|c| c.is_whitespace() || matches!(c, ',' | ';' | '<' | '>'))
}

fn render(text: &str, customer: &str, contact: &str) -> String {
    // Replace tokens in the original text only. A customer name can contain literal braces.
    let mut out = String::new();
    let mut remaining = text;
    while let Some((prefix, tail)) = remaining.split_once("{{") {
        out.push_str(prefix);
        let Some((token, after)) = tail.split_once("}}") else {
            out.push_str("{{");
            out.push_str(tail);
            return out;
        };
        match token.trim() {
            "customer.name" => out.push_str(customer),
            "contact.name" => out.push_str(contact),
            _ => {
                out.push_str("{{");
                out.push_str(token);
                out.push_str("}}");
            }
        }
        remaining = after;
    }
    out.push_str(remaining);
    out
}

async fn build_preview(
    conn: &mut PgConnection,
    user: &CurrentUser,
    draft: Option<MailMergeDraft>,
) -> AppResult<MailMergePreview> {
    let Some(d) = &draft else {
        return Ok(MailMergePreview {
            approval_id: None,
            draft,
            audience: vec![],
        });
    };
    let pdfs: BTreeMap<String, String> = sqlx::query_as::<_, (String, String)>(
        "SELECT p.language, f.filename FROM kb.document_pdfs p
         JOIN kb.document_revisions r USING (document_id, revision)
         JOIN kb.documents d ON d.id = p.document_id
         JOIN core.files f ON f.id = p.file_id AND f.company_id = d.company_id
         WHERE d.company_id = $1 AND p.document_id = $2 AND p.revision = $3
           AND r.published_at IS NOT NULL AND f.content_type = 'application/pdf'",
    )
    .bind(user.company_id)
    .bind(d.document_id)
    .bind(d.revision)
    .fetch_all(&mut *conn)
    .await?
    .into_iter()
    .collect();
    if pdfs.is_empty() {
        return Err(AppError::NotFound("published document revision"));
    }
    let sender = sender(&mut *conn, user.company_id).await?;
    let placeholder =
        unsubscribe::link(sender.portal_url.as_deref().unwrap_or_default(), "\u{2026}");
    let opted_out: HashSet<String> =
        sqlx::query_scalar("SELECT email FROM crm.mailing_opt_outs WHERE company_id = $1")
            .bind(user.company_id)
            .fetch_all(&mut *conn)
            .await?
            .into_iter()
            .collect();

    // Customers are shared master data. The recipient list is limited to customers
    // associated with this company through its commercial terms.
    let customers: Vec<Customer> = sqlx::query_as(
        "SELECT c.id,c.name,c.language::text,c.email FROM crm.customers c
         JOIN crm.customer_terms t ON t.customer_id = c.id AND t.company_id = $1
         WHERE c.active ORDER BY lower(c.name),c.id",
    )
    .bind(user.company_id)
    .fetch_all(&mut *conn)
    .await?;
    let ids = customers.iter().map(|c| c.id).collect::<Vec<_>>();
    let contacts: Vec<MailMergeContact> = sqlx::query_as(
        "SELECT c.customer_id,c.id,concat_ws(' ', nullif(trim(c.first_name),''),trim(c.last_name)) AS name,
                c.language::text, e.email
         FROM crm.contacts c LEFT JOIN LATERAL (
           SELECT email FROM crm.contact_emails e WHERE contact_id = c.id
           ORDER BY is_primary DESC, email LIMIT 1
         ) e ON true WHERE c.active AND c.customer_id = ANY($1) ORDER BY name,c.id",
    ).bind(&ids).fetch_all(&mut *conn).await?;
    let mut by_customer: HashMap<Uuid, Vec<MailMergeContact>> = HashMap::new();
    for c in contacts {
        by_customer.entry(c.customer_id).or_default().push(c);
    }
    let mut audience = Vec::with_capacity(customers.len());
    let mut addresses = HashMap::new();
    for customer in customers {
        let contacts = by_customer.remove(&customer.id).unwrap_or_default();
        let selected = match d.recipients.get(&customer.id) {
            Some(id) => contacts.iter().find(|c| &c.id == id),
            None if contacts.len() == 1 => contacts.first(),
            None => None,
        };
        let mut issues = Vec::new();
        let email = match selected {
            Some(contact) => contact.email.as_ref(),
            None if contacts.is_empty() && !d.recipients.contains_key(&customer.id) => {
                customer.email.as_ref()
            }
            None => {
                issues.push("select_contact".into());
                None
            }
        }
        .map(|email| email.trim().to_lowercase())
        .filter(|email| usable_email(email));
        if let Some(email) = &email {
            *addresses.entry(email.clone()).or_insert(0usize) += 1;
            if opted_out.contains(email) {
                issues.push("opted_out".into());
            }
        } else if issues.is_empty() {
            issues.push("missing_address".into());
        }
        let language = selected
            .and_then(|c| c.language.clone())
            .unwrap_or(customer.language);
        let message = d
            .messages
            .get(&language)
            .filter(|m| !m.subject.trim().is_empty() && !m.body.trim().is_empty());
        if message.is_none() {
            issues.push("missing_translation".into());
        }
        let pdf = pdfs.get(&language).cloned();
        if pdf.is_none() {
            issues.push("missing_pdf".into());
        }
        let name = selected.map_or(customer.name.as_str(), |c| c.name.as_str());
        let subject = message.map(|m| render(&m.subject, &customer.name, name));
        let body = message.map(|m| render(&m.body, &customer.name, name));
        let footer = message.map(|_| unsubscribe::footer(&language, &sender.name, &placeholder));
        audience.push(MailMergeRecipient {
            customer_id: customer.id,
            customer_name: customer.name,
            contact_id: selected.map(|c| c.id),
            contacts,
            language,
            email,
            subject,
            body,
            footer,
            pdf,
            issues,
        });
    }
    for row in &mut audience {
        if row.email.as_ref().is_some_and(|email| addresses[email] > 1) {
            row.issues.push("duplicate_address".into());
        }
    }
    Ok(MailMergePreview {
        approval_id: None,
        draft,
        audience,
    })
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(get_draft, save_draft))
        .routes(routes!(confirm))
        .routes(routes!(history))
        .routes(routes!(list_opt_outs, add_opt_out))
        .routes(routes!(remove_opt_out))
}

/// The sending company: its name signs the unsubscribe footer and its portal hosts the link.
struct Sender {
    name: String,
    portal_url: Option<String>,
}

async fn sender(conn: &mut PgConnection, company: Uuid) -> AppResult<Sender> {
    let (name, portal_url): (String, Option<String>) =
        sqlx::query_as("SELECT name, portal_url FROM core.companies WHERE id = $1")
            .bind(company)
            .fetch_one(conn)
            .await?;
    Ok(Sender {
        name,
        portal_url: portal_url
            .map(|url| url.trim().to_string())
            .filter(|url| !url.is_empty()),
    })
}

#[derive(Serialize, FromRow, ToSchema)]
struct MailingDelivery {
    mailing_id: Uuid,
    document_id: Uuid,
    document_title: String,
    revision: i32,
    confirmed_at: chrono::DateTime<chrono::Utc>,
    customer_name: String,
    language: String,
    email: String,
    subject: String,
    pdf: String,
    delivery: String,
    delivery_error: Option<String>,
}

#[utoipa::path(get, path = "/customers/mail-merge/history", tag = "crm", operation_id = "mail_merge_history",
    responses((status = 200, body = Vec<MailingDelivery>)))]
async fn history(
    State(state): State<AppState>,
    user: CurrentUser,
) -> AppResult<Json<Vec<MailingDelivery>>> {
    authorize(&user)?;
    Ok(Json(sqlx::query_as(
        "SELECT m.id AS mailing_id,m.document_id,d.title AS document_title,m.revision,m.confirmed_at,
                a.customer_name,a.language,o.to_address AS email,o.subject,
                coalesce(o.attachment_name,'') AS pdf,o.delivery,o.delivery_error
         FROM crm.mailings m JOIN crm.mailing_deliveries a ON a.mailing_id = m.id
         JOIN kb.documents d ON d.id = m.document_id
         JOIN core.mail_outbox o ON o.id = a.outbox_id
         WHERE m.company_id = $1 AND m.sender_id = $2
         ORDER BY m.confirmed_at DESC,m.id,a.customer_name,a.customer_id",
    ).bind(user.company_id).bind(user.user_id).fetch_all(&state.db).await?))
}

#[utoipa::path(post, path = "/customers/mail-merge/{approval_id}/confirm", tag = "crm", operation_id = "confirm_mail_merge",
    params(("approval_id" = Uuid, Path)), responses((status = 204)))]
async fn confirm(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(approval_id): Path<Uuid>,
) -> AppResult<axum::http::StatusCode> {
    authorize(&user)?;
    user.require(Permission::MailMergeSend)?;
    let mut tx = state.db.begin().await?;
    // Saving a draft takes the same row lock. One confirmation commits the whole
    // outbox batch, including its immutable history, or leaves all of it retryable.
    let snapshot: Option<Option<sqlx::types::Json<MailMergePreview>>> = sqlx::query_scalar(
        "SELECT approved_preview FROM crm.mail_merge_drafts WHERE company_id = $1 AND user_id = $2 FOR UPDATE",
    ).bind(user.company_id).bind(user.user_id).fetch_optional(&mut *tx).await?;
    let already: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM crm.mailings WHERE id = $1 AND company_id = $2 AND sender_id = $3)",
    ).bind(approval_id).bind(user.company_id).bind(user.user_id).fetch_one(&mut *tx).await?;
    if already {
        return Ok(axum::http::StatusCode::NO_CONTENT);
    }
    let preview = snapshot
        .flatten()
        .map(|s| s.0)
        .filter(|p| p.approval_id == Some(approval_id))
        .ok_or_else(|| {
            AppError::Conflict("save and review the current draft before confirming".into())
        })?;
    let draft = preview.draft.ok_or(AppError::NotFound("mailing draft"))?;
    let sender = sender(&mut tx, user.company_id).await?;
    let Some(portal_url) = sender.portal_url.as_deref() else {
        return Err(AppError::Validation(
            "set the company's portal address first: every mailing carries an unsubscribe link to the portal".into(),
        ));
    };
    let eligible: Vec<_> = preview
        .audience
        .iter()
        .filter(|r| r.issues.is_empty())
        .collect();
    if eligible.is_empty() {
        return Err(AppError::Validation(
            "the preview has no eligible recipients".into(),
        ));
    }
    // Opt-outs recorded from here on wait for this confirmation; the preview below re-reads the
    // register, so an approved recipient who opted out since the review is refused (409).
    unsubscribe::lock_register(&mut tx, user.company_id).await?;
    let current = build_preview(&mut tx, &user, Some(draft)).await?;
    let recipient_key = |row: &MailMergeRecipient| {
        (
            row.customer_id,
            (row.contact_id, row.email.clone(), row.language.clone()),
        )
    };
    let approved_recipients: BTreeMap<_, _> = eligible.iter().copied().map(recipient_key).collect();
    let current_recipients = current
        .audience
        .iter()
        .filter(|row| row.issues.is_empty())
        .map(recipient_key)
        .collect();
    if approved_recipients != current_recipients {
        return Err(AppError::Conflict(
            "mailing recipients changed; save and review the current draft before confirming"
                .into(),
        ));
    }
    let draft = current.draft.expect("revalidated draft");
    sqlx::query("INSERT INTO crm.mailings (id,company_id,sender_id,document_id,revision) VALUES ($1,$2,$3,$4,$5)")
        .bind(approval_id).bind(user.company_id).bind(user.user_id).bind(draft.document_id).bind(draft.revision)
        .execute(&mut *tx).await?;
    let target = Target {
        company: user.company_id,
        company_name: &sender.name,
        portal_url,
        mailing: approval_id,
    };
    for row in eligible {
        queue_delivery(&mut tx, &target, &draft, row).await?;
    }
    tx.commit().await?;
    Ok(axum::http::StatusCode::NO_CONTENT)
}

/// Where a confirmed mailing goes out from.
struct Target<'a> {
    company: Uuid,
    company_name: &'a str,
    portal_url: &'a str,
    mailing: Uuid,
}

async fn queue_delivery(
    conn: &mut PgConnection,
    target: &Target<'_>,
    draft: &MailMergeDraft,
    row: &MailMergeRecipient,
) -> AppResult<()> {
    let outbox_id = tradocraft_core::new_id();
    // A fresh token per delivery; only its hash is stored, the token is only in the mail.
    let (token, token_hash) = unsubscribe::new_token();
    let footer = unsubscribe::footer(
        &row.language,
        target.company_name,
        &unsubscribe::link(target.portal_url, &token),
    );
    let body = format!("{}\n\n{footer}\n", row.body.as_deref().unwrap_or_default());
    let result = sqlx::query(
        "WITH queued AS (
            INSERT INTO core.mail_outbox (id,company_id,to_address,subject,body,attachment_name,attachment_type,attachment_storage_key)
            SELECT $1,$2,$3,$4,$5,f.filename,f.content_type,f.storage_key
            FROM kb.document_pdfs p JOIN kb.documents d ON d.id = p.document_id
            JOIN kb.document_revisions r USING (document_id,revision)
            JOIN core.files f ON f.id = p.file_id AND f.company_id = d.company_id
            WHERE d.company_id = $2 AND p.document_id = $6 AND p.revision = $7
              AND p.language = $8 AND r.published_at IS NOT NULL
            RETURNING id
        ) INSERT INTO crm.mailing_deliveries (mailing_id,customer_id,customer_name,language,outbox_id,unsubscribe_token_hash)
          SELECT $9,$10,$11,$8,id,$12 FROM queued",
    ).bind(outbox_id).bind(target.company).bind(&row.email).bind(&row.subject).bind(&body)
     .bind(draft.document_id).bind(draft.revision).bind(&row.language).bind(target.mailing)
     .bind(row.customer_id).bind(&row.customer_name).bind(&token_hash).execute(conn).await?;
    if result.rows_affected() == 0 {
        return Err(AppError::NotFound("published document PDF"));
    }
    Ok(())
}

/// An address on the company's opt-out register.
#[derive(Serialize, FromRow, ToSchema)]
struct MailingOptOut {
    email: String,
    opted_out_at: chrono::DateTime<chrono::Utc>,
    /// staff | unsubscribe_link
    source: String,
    recorded_by: Option<Uuid>,
    recorded_by_name: Option<String>,
}

#[derive(Deserialize, ToSchema)]
struct MailingOptOutInput {
    email: String,
}

fn normalise_email(email: &str) -> AppResult<String> {
    let email = email.trim().to_lowercase();
    if usable_email(&email) {
        Ok(email)
    } else {
        Err(AppError::Validation("enter a valid email address".into()))
    }
}

#[utoipa::path(get, path = "/customers/mail-merge/opt-outs", tag = "crm", operation_id = "list_mailing_opt_outs",
    responses((status = 200, body = Vec<MailingOptOut>)))]
async fn list_opt_outs(
    State(state): State<AppState>,
    user: CurrentUser,
) -> AppResult<Json<Vec<MailingOptOut>>> {
    authorize(&user)?;
    Ok(Json(
        sqlx::query_as(
            "SELECT o.email,o.opted_out_at,o.source,o.recorded_by,u.display_name AS recorded_by_name
             FROM crm.mailing_opt_outs o LEFT JOIN core.users u ON u.id = o.recorded_by
             WHERE o.company_id = $1 ORDER BY o.opted_out_at DESC,o.email",
        )
        .bind(user.company_id)
        .fetch_all(&state.db)
        .await?,
    ))
}

/// Puts an address on the register, e.g. after a customer asked by phone. Idempotent.
#[utoipa::path(post, path = "/customers/mail-merge/opt-outs", tag = "crm", operation_id = "add_mailing_opt_out",
    request_body = MailingOptOutInput,
    responses((status = 204), (status = 422, body = ErrorBody)))]
async fn add_opt_out(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<MailingOptOutInput>,
) -> AppResult<StatusCode> {
    authorize(&user)?;
    let email = normalise_email(&input.email)?;
    let mut tx = state.db.begin().await?;
    unsubscribe::lock_register(&mut tx, user.company_id).await?;
    let added = sqlx::query(
        "INSERT INTO crm.mailing_opt_outs (company_id,email,source,recorded_by) VALUES ($1,$2,'staff',$3)
         ON CONFLICT DO NOTHING",
    )
    .bind(user.company_id)
    .bind(&email)
    .bind(user.user_id)
    .execute(&mut *tx)
    .await?;
    let cancelled = unsubscribe::cancel_queued(&mut tx, user.company_id, &email).await?;
    if added.rows_affected() > 0 {
        audit::record(
            &mut tx,
            &user,
            "mailing_opt_out",
            user.company_id,
            "added",
            serde_json::json!({ "email": email, "source": "staff", "cancelled_mails": cancelled }),
        )
        .await?;
    }
    tx.commit().await?;
    Ok(StatusCode::NO_CONTENT)
}

/// Takes an address off the register when its owner asks to receive mailings again.
#[utoipa::path(delete, path = "/customers/mail-merge/opt-outs/{email}", tag = "crm", operation_id = "remove_mailing_opt_out",
    params(("email" = String, Path)),
    responses((status = 204), (status = 404, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn remove_opt_out(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(email): Path<String>,
) -> AppResult<StatusCode> {
    authorize(&user)?;
    let email = normalise_email(&email)?;
    let mut tx = state.db.begin().await?;
    let source: Option<String> = sqlx::query_scalar(
        "DELETE FROM crm.mailing_opt_outs WHERE company_id = $1 AND email = $2 RETURNING source",
    )
    .bind(user.company_id)
    .bind(&email)
    .fetch_optional(&mut *tx)
    .await?;
    let Some(source) = source else {
        return Err(AppError::NotFound("opt-out"));
    };
    audit::record(
        &mut tx,
        &user,
        "mailing_opt_out",
        user.company_id,
        "removed",
        serde_json::json!({ "email": email, "source": source }),
    )
    .await?;
    tx.commit().await?;
    Ok(StatusCode::NO_CONTENT)
}
