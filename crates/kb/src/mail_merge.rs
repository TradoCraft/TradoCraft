//! Saved, staff-only drafts and read-only audience previews. A preview does not enqueue mail.
use std::collections::{BTreeMap, HashMap};

use axum::{
    extract::{Path, State},
    Json,
};
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection};
use tradocraft_core::{AppError, AppResult, AppState, CurrentUser, Permission};
use utoipa::ToSchema;
use utoipa_axum::{router::OpenApiRouter, routes};
use uuid::Uuid;

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
        audience.push(MailMergeRecipient {
            customer_id: customer.id,
            customer_name: customer.name,
            contact_id: selected.map(|c| c.id),
            contacts,
            language,
            email,
            subject,
            body,
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
    for row in eligible {
        queue_delivery(&mut tx, user.company_id, approval_id, &draft, row).await?;
    }
    tx.commit().await?;
    Ok(axum::http::StatusCode::NO_CONTENT)
}

async fn queue_delivery(
    conn: &mut PgConnection,
    company: Uuid,
    mailing: Uuid,
    draft: &MailMergeDraft,
    row: &MailMergeRecipient,
) -> AppResult<()> {
    let outbox_id = tradocraft_core::new_id();
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
        ) INSERT INTO crm.mailing_deliveries (mailing_id,customer_id,customer_name,language,outbox_id)
          SELECT $9,$10,$11,$8,id FROM queued",
    ).bind(outbox_id).bind(company).bind(&row.email).bind(&row.subject).bind(&row.body)
     .bind(draft.document_id).bind(draft.revision).bind(&row.language).bind(mailing)
     .bind(row.customer_id).bind(&row.customer_name).execute(conn).await?;
    if result.rows_affected() == 0 {
        return Err(AppError::NotFound("published document PDF"));
    }
    Ok(())
}
