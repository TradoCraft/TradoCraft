//! Prepared answers ("text modules"): reusable replies with one text per language and
//! `{{placeholders}}`. Rendered for a ticket in its language; the agent edits before sending.

use std::collections::BTreeMap;

use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::Json;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection};
use tradocraft_core::{
    audit, is_language, new_id, AppError, AppResult, AppState, CurrentUser, Permission, LANGUAGES,
};
use utoipa::{IntoParams, ToSchema};
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::render::{render, PLACEHOLDERS};

type ErrorBody = tradocraft_core::error::ErrorBody;

pub const KINDS: [&str; 4] = ["reply", "internal_note", "handover", "notice"];

fn default_kind() -> String {
    "reply".into()
}

/// Lower-cased, trimmed, de-duplicated keywords (at most 20 of at most 40 characters).
pub fn clean_keywords(raw: &[String]) -> AppResult<Vec<String>> {
    let mut out: Vec<String> = Vec::new();
    for k in raw {
        let k = k.trim().to_lowercase();
        if k.is_empty() {
            continue;
        }
        if k.chars().count() > 40 {
            return Err(AppError::Validation(
                "a keyword is at most 40 characters".into(),
            ));
        }
        if !out.contains(&k) {
            out.push(k);
        }
    }
    if out.len() > 20 {
        return Err(AppError::Validation("at most 20 keywords".into()));
    }
    Ok(out)
}

/// The team must belong to the company.
async fn check_team(conn: &mut PgConnection, company_id: Uuid, team: Option<Uuid>) -> AppResult<()> {
    let Some(team) = team else { return Ok(()) };
    let ok: bool = sqlx::query_scalar(
        "SELECT EXISTS (SELECT 1 FROM helpdesk.teams WHERE id = $1 AND company_id = $2)",
    )
    .bind(team)
    .bind(company_id)
    .fetch_one(conn)
    .await?;
    if ok {
        Ok(())
    } else {
        Err(AppError::NotFound("team"))
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, FromRow, ToSchema)]
pub struct AnswerText {
    /// nl | fr | en | de | es
    pub language: String,
    #[serde(default)]
    pub subject: String,
    pub body: String,
}

#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct PreparedAnswer {
    pub id: Uuid,
    /// Short code to find the answer quickly, e.g. `order-confirmed`.
    pub code: String,
    pub name: String,
    pub category: Option<String>,
    /// reply | internal_note | handover | notice
    pub kind: String,
    /// Absent: usable by every team.
    pub team_id: Option<Uuid>,
    /// Lower-case words; a ticket subject containing one ranks the answer higher.
    pub keywords: Vec<String>,
    pub active: bool,
    pub updated_at: DateTime<Utc>,
    pub texts: Vec<AnswerText>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct PreparedAnswerInput {
    pub code: String,
    pub name: String,
    pub category: Option<String>,
    #[serde(default = "default_kind")]
    pub kind: String,
    pub team_id: Option<Uuid>,
    #[serde(default)]
    pub keywords: Vec<String>,
    #[serde(default = "default_true")]
    pub active: bool,
    /// At least one language; missing languages fall back to English, then any other.
    pub texts: Vec<AnswerText>,
}

fn default_true() -> bool {
    true
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct ListParams {
    /// Searches code, name and texts.
    pub q: Option<String>,
    pub active: Option<bool>,
    /// reply | internal_note | handover | notice
    pub kind: Option<String>,
    /// Answers a ticket of this team can use: company-wide ones and this team's own.
    pub team_id: Option<Uuid>,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct RenderedAnswer {
    pub answer_id: Uuid,
    /// Language of the text used.
    pub language: String,
    /// True when no text exists in the ticket's language and another language was used.
    pub fallback: bool,
    pub subject: String,
    pub body: String,
}

#[derive(FromRow)]
struct Row {
    id: Uuid,
    code: String,
    name: String,
    category: Option<String>,
    kind: String,
    team_id: Option<Uuid>,
    keywords: Vec<String>,
    active: bool,
    updated_at: DateTime<Utc>,
}

async fn texts(conn: &mut PgConnection, ids: &[Uuid]) -> AppResult<Vec<(Uuid, AnswerText)>> {
    #[derive(FromRow)]
    struct T {
        answer_id: Uuid,
        language: String,
        subject: String,
        body: String,
    }
    let rows: Vec<T> = sqlx::query_as(
        "SELECT answer_id, language::text AS language, subject, body FROM helpdesk.prepared_answer_texts
         WHERE answer_id = ANY($1)
         ORDER BY array_position(ARRAY['nl','fr','en','de','es'], language::text)",
    )
    .bind(ids)
    .fetch_all(conn)
    .await?;
    Ok(rows
        .into_iter()
        .map(|t| {
            (
                t.answer_id,
                AnswerText {
                    language: t.language,
                    subject: t.subject,
                    body: t.body,
                },
            )
        })
        .collect())
}

pub async fn load(conn: &mut PgConnection, company_id: Uuid, id: Uuid) -> AppResult<PreparedAnswer> {
    let r: Row = sqlx::query_as(
        "SELECT id, code, name, category, kind, team_id, keywords, active, updated_at FROM helpdesk.prepared_answers WHERE id = $1 AND company_id = $2",
    )
    .bind(id)
    .bind(company_id)
    .fetch_optional(&mut *conn)
    .await?
    .ok_or(AppError::NotFound("prepared answer"))?;
    let t = texts(conn, &[id]).await?;
    Ok(PreparedAnswer {
        id: r.id,
        code: r.code,
        name: r.name,
        category: r.category,
        kind: r.kind,
        team_id: r.team_id,
        keywords: r.keywords,
        active: r.active,
        updated_at: r.updated_at,
        texts: t.into_iter().map(|(_, t)| t).collect(),
    })
}

impl PreparedAnswerInput {
    fn validate(&self) -> AppResult<()> {
        if self.code.trim().is_empty() || self.name.trim().is_empty() {
            return Err(AppError::Validation("code and name are required".into()));
        }
        if !KINDS.contains(&self.kind.as_str()) {
            return Err(AppError::Validation(format!(
                "kind must be one of {}",
                KINDS.join(", ")
            )));
        }
        clean_keywords(&self.keywords)?;
        let filled: Vec<&AnswerText> = self
            .texts
            .iter()
            .filter(|t| !t.body.trim().is_empty())
            .collect();
        if filled.is_empty() {
            return Err(AppError::Validation(
                "write the answer in at least one language".into(),
            ));
        }
        let mut seen = Vec::new();
        for t in &filled {
            if !is_language(&t.language) {
                return Err(AppError::Validation(format!(
                    "language must be one of {}",
                    LANGUAGES.join(", ")
                )));
            }
            if seen.contains(&t.language) {
                return Err(AppError::Validation(format!(
                    "language {} appears twice",
                    t.language
                )));
            }
            seen.push(t.language.clone());
        }
        Ok(())
    }
}

async fn save_texts(
    conn: &mut PgConnection,
    id: Uuid,
    input: &PreparedAnswerInput,
) -> AppResult<()> {
    sqlx::query("DELETE FROM helpdesk.prepared_answer_texts WHERE answer_id = $1")
        .bind(id)
        .execute(&mut *conn)
        .await?;
    for t in input.texts.iter().filter(|t| !t.body.trim().is_empty()) {
        sqlx::query(
            "INSERT INTO helpdesk.prepared_answer_texts (answer_id, language, subject, body) VALUES ($1, $2, $3, $4)",
        )
        .bind(id)
        .bind(&t.language)
        .bind(t.subject.trim())
        .bind(&t.body)
        .execute(&mut *conn)
        .await?;
    }
    Ok(())
}

#[utoipa::path(get, path = "/prepared-answers", tag = "helpdesk", params(ListParams),
    responses((status = 200, body = Vec<PreparedAnswer>)))]
async fn list_answers(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(p): Query<ListParams>,
) -> AppResult<Json<Vec<PreparedAnswer>>> {
    user.require(Permission::HelpdeskRead)?;
    let pattern =
        p.q.as_deref()
            .map(|q| format!("%{}%", q.trim().to_lowercase()));
    let rows: Vec<Row> = sqlx::query_as(
        "SELECT a.id, a.code, a.name, a.category, a.kind, a.team_id, a.keywords, a.active, a.updated_at FROM helpdesk.prepared_answers a
         WHERE a.company_id = $1 AND ($3::boolean IS NULL OR a.active = $3)
           AND ($2::text IS NULL OR lower(a.code) LIKE $2 OR lower(a.name) LIKE $2
                OR EXISTS (SELECT 1 FROM helpdesk.prepared_answer_texts t
                           WHERE t.answer_id = a.id AND lower(t.body) LIKE $2))
           AND ($4::text IS NULL OR a.kind = $4)
           AND ($5::uuid IS NULL OR a.team_id IS NULL OR a.team_id = $5)
         ORDER BY a.category NULLS LAST, a.name",
    )
    .bind(user.company_id)
    .bind(&pattern)
    .bind(p.active)
    .bind(&p.kind)
    .bind(p.team_id)
    .fetch_all(&state.db)
    .await?;
    let mut conn = state.db.acquire().await?;
    let ids: Vec<Uuid> = rows.iter().map(|r| r.id).collect();
    let all = texts(&mut conn, &ids).await?;
    Ok(Json(
        rows.into_iter()
            .map(|r| PreparedAnswer {
                texts: all
                    .iter()
                    .filter(|(id, _)| *id == r.id)
                    .map(|(_, t)| t.clone())
                    .collect(),
                id: r.id,
                code: r.code,
                name: r.name,
                category: r.category,
                kind: r.kind,
                team_id: r.team_id,
                keywords: r.keywords,
                active: r.active,
                updated_at: r.updated_at,
            })
            .collect(),
    ))
}

/// Placeholders that can be used in prepared answers, e.g. `{{quotation.number}}`.
#[utoipa::path(get, path = "/prepared-answers/placeholders", tag = "helpdesk",
    responses((status = 200, body = Vec<String>)))]
async fn placeholders(user: CurrentUser) -> AppResult<Json<Vec<String>>> {
    user.require(Permission::HelpdeskRead)?;
    Ok(Json(PLACEHOLDERS.iter().map(|p| p.to_string()).collect()))
}

#[utoipa::path(post, path = "/prepared-answers", tag = "helpdesk", request_body = PreparedAnswerInput,
    responses((status = 201, body = PreparedAnswer), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn create_answer(
    State(state): State<AppState>,
    user: CurrentUser,
    Json(input): Json<PreparedAnswerInput>,
) -> AppResult<(StatusCode, Json<PreparedAnswer>)> {
    user.require(Permission::AnswersWrite)?;
    input.validate()?;
    let keywords = clean_keywords(&input.keywords)?;
    let mut tx = state.db.begin().await?;
    check_team(&mut tx, user.company_id, input.team_id).await?;
    let id = new_id();
    sqlx::query("INSERT INTO helpdesk.prepared_answers (id, company_id, code, name, category, active, kind, team_id, keywords) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)")
        .bind(id)
        .bind(user.company_id)
        .bind(input.code.trim())
        .bind(input.name.trim())
        .bind(input.category.as_deref().map(str::trim).filter(|c| !c.is_empty()))
        .bind(input.active)
        .bind(&input.kind)
        .bind(input.team_id)
        .bind(&keywords)
        .execute(&mut *tx)
        .await?;
    save_texts(&mut tx, id, &input).await?;
    audit::record(
        &mut tx,
        &user,
        "prepared_answer",
        id,
        "created",
        serde_json::json!({ "code": input.code, "kind": input.kind, "team_id": input.team_id }),
    )
    .await?;
    let a = load(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(a)))
}

#[utoipa::path(put, path = "/prepared-answers/{id}", tag = "helpdesk", params(("id" = Uuid, Path)),
    request_body = PreparedAnswerInput, responses((status = 200, body = PreparedAnswer)))]
async fn update_answer(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<PreparedAnswerInput>,
) -> AppResult<Json<PreparedAnswer>> {
    user.require(Permission::AnswersWrite)?;
    input.validate()?;
    let keywords = clean_keywords(&input.keywords)?;
    let mut tx = state.db.begin().await?;
    check_team(&mut tx, user.company_id, input.team_id).await?;
    let r = sqlx::query(
        "UPDATE helpdesk.prepared_answers SET code = $3, name = $4, category = $5, active = $6, kind = $7,
                team_id = $8, keywords = $9, updated_at = now()
         WHERE id = $1 AND company_id = $2",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(input.code.trim())
    .bind(input.name.trim())
    .bind(input.category.as_deref().map(str::trim).filter(|c| !c.is_empty()))
    .bind(input.active)
    .bind(&input.kind)
    .bind(input.team_id)
    .bind(&keywords)
    .execute(&mut *tx)
    .await?;
    if r.rows_affected() == 0 {
        return Err(AppError::NotFound("prepared answer"));
    }
    save_texts(&mut tx, id, &input).await?;
    audit::record(
        &mut tx,
        &user,
        "prepared_answer",
        id,
        "updated",
        serde_json::json!({ "kind": input.kind, "team_id": input.team_id }),
    )
    .await?;
    let a = load(&mut tx, user.company_id, id).await?;
    tx.commit().await?;
    Ok(Json(a))
}

/// Picks the text for `language`: exact match, else English, else the company's default, else any.
pub fn pick_text<'a>(
    texts: &'a [AnswerText],
    language: &str,
    company_default: &str,
) -> Option<(&'a AnswerText, bool)> {
    let find = |l: &str| texts.iter().find(|t| t.language == l);
    if let Some(t) = find(language) {
        return Some((t, false));
    }
    find("en")
        .or_else(|| find(company_default))
        .or_else(|| texts.first())
        .map(|t| (t, true))
}

/// What the ranking needs to know about one answer.
pub struct Candidate<'a> {
    pub code: &'a str,
    pub name: &'a str,
    pub keywords: &'a [String],
    pub team_id: Option<Uuid>,
    /// The answer has a text in the ticket's own language.
    pub has_language: bool,
}

/// How well an answer fits a ticket, or `None` when a typed query matches nothing. Higher is better:
/// exact code 100, code prefix 60, name or keyword hit 30 or 25; keywords found in the ticket
/// subject +20 each (at most 40); the ticket's own team +15; a text in the ticket's language +5.
pub fn score(
    c: &Candidate,
    q: &str,
    ticket_team: Option<Uuid>,
    ticket_subject: &str,
) -> Option<i32> {
    let q = q.trim().to_lowercase();
    let code = c.code.to_lowercase();
    let mut s = 0;
    if !q.is_empty() {
        s += if code == q {
            100
        } else if code.starts_with(&q) {
            60
        } else if c.name.to_lowercase().contains(&q) {
            30
        } else if c.keywords.iter().any(|k| k.contains(&q)) {
            25
        } else {
            return None;
        };
    }
    let subject = ticket_subject.to_lowercase();
    let hits = c.keywords.iter().filter(|k| subject.contains(k.as_str())).count() as i32;
    s += (hits * 20).min(40);
    if c.team_id.is_some() && c.team_id == ticket_team {
        s += 15;
    }
    if c.has_language {
        s += 5;
    }
    Some(s)
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct SuggestParams {
    /// Typed text: a code, part of a name or a keyword. Empty: the best fits for the ticket.
    pub q: Option<String>,
    /// reply | internal_note | handover | notice. Absent: every kind.
    pub kind: Option<String>,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct SuggestedAnswer {
    pub answer_id: Uuid,
    pub code: String,
    pub name: String,
    pub kind: String,
    pub team_id: Option<Uuid>,
    /// Language of the text used.
    pub language: String,
    pub fallback: bool,
    pub subject: String,
    pub body: String,
    pub score: i32,
}

/// The best prepared answers for a ticket, filled in and in the ticket's language, at most ten.
/// Answers of other teams are left out.
#[utoipa::path(get, path = "/tickets/{id}/prepared-answers/suggest", tag = "helpdesk",
    params(("id" = Uuid, Path), SuggestParams),
    responses((status = 200, body = Vec<SuggestedAnswer>), (status = 404, body = ErrorBody)))]
async fn suggest(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(ticket_id): Path<Uuid>,
    Query(p): Query<SuggestParams>,
) -> AppResult<Json<Vec<SuggestedAnswer>>> {
    user.require(Permission::HelpdeskRead)?;
    let mut conn = state.db.acquire().await?;
    let (language, values) = ticket_values(&mut conn, &user, ticket_id).await?;
    let team: Option<Uuid> =
        sqlx::query_scalar("SELECT team_id FROM helpdesk.tickets WHERE id = $1 AND company_id = $2")
            .bind(ticket_id)
            .bind(user.company_id)
            .fetch_one(&mut *conn)
            .await?;
    let rows: Vec<Row> = sqlx::query_as(
        "SELECT a.id, a.code, a.name, a.category, a.kind, a.team_id, a.keywords, a.active, a.updated_at
         FROM helpdesk.prepared_answers a
         WHERE a.company_id = $1 AND a.active AND ($2::text IS NULL OR a.kind = $2)
           AND (a.team_id IS NULL OR a.team_id = $3)",
    )
    .bind(user.company_id)
    .bind(&p.kind)
    .bind(team)
    .fetch_all(&mut *conn)
    .await?;
    let ids: Vec<Uuid> = rows.iter().map(|r| r.id).collect();
    let all = texts(&mut conn, &ids).await?;
    let subject = values.get("ticket.subject").cloned().unwrap_or_default();
    let q = p.q.clone().unwrap_or_default();
    let mut ranked: Vec<(i32, Row)> = rows
        .into_iter()
        .filter_map(|r| {
            let has_language = all.iter().any(|(id, t)| *id == r.id && t.language == language);
            let s = score(
                &Candidate { code: &r.code, name: &r.name, keywords: &r.keywords, team_id: r.team_id, has_language },
                &q,
                team,
                &subject,
            )?;
            Some((s, r))
        })
        .collect();
    ranked.sort_by(|a, b| b.0.cmp(&a.0).then_with(|| a.1.name.cmp(&b.1.name)));
    ranked.truncate(10);
    let mut out = Vec::new();
    for (s, r) in ranked {
        let mine: Vec<AnswerText> =
            all.iter().filter(|(id, _)| *id == r.id).map(|(_, t)| t.clone()).collect();
        let Some((text, fallback)) = pick_text(&mine, &language, &values["__company_language"]) else {
            continue;
        };
        out.push(SuggestedAnswer {
            answer_id: r.id,
            code: r.code,
            name: r.name,
            kind: r.kind,
            team_id: r.team_id,
            language: text.language.clone(),
            fallback,
            subject: render(&text.subject, &values),
            body: render(&text.body, &values),
            score: s,
        });
    }
    Ok(Json(out))
}

/// The values for the placeholders of a ticket, for the logged-in agent.
pub async fn ticket_values(
    conn: &mut PgConnection,
    user: &CurrentUser,
    ticket_id: Uuid,
) -> AppResult<(String, BTreeMap<String, String>)> {
    ticket_values_for(conn, user.company_id, &user.display_name, ticket_id).await
}

/// The same without a logged-in user: `agent_name` is who the text speaks for (the ticket's
/// owner in automation mail).
pub async fn ticket_values_for(
    conn: &mut PgConnection,
    company_id: Uuid,
    agent_name: &str,
    ticket_id: Uuid,
) -> AppResult<(String, BTreeMap<String, String>)> {
    #[derive(FromRow)]
    struct V {
        language: String,
        number: String,
        subject: String,
        contact_name: String,
        contact_first_name: Option<String>,
        contact_last_name: Option<String>,
        contact_title: Option<String>,
        contact_address_form: Option<String>,
        customer_name: Option<String>,
        company_name: String,
        company_language: String,
        team_name: Option<String>,
        quotation_number: Option<String>,
        quotation_revision: Option<i32>,
        quotation_total: Option<rust_decimal::Decimal>,
        order_number: Option<String>,
        order_reference: Option<String>,
    }
    let v: V = sqlx::query_as(
        "SELECT t.language::text AS language, t.number, t.subject, t.contact_name, ct.first_name AS contact_first_name,
                ct.last_name AS contact_last_name, ct.title AS contact_title, ct.address_form AS contact_address_form,
                c.name AS customer_name, co.name AS company_name, co.default_language::text AS company_language,
                tm.name AS team_name,
                q.number AS quotation_number, q.revision AS quotation_revision, q.total AS quotation_total,
                o.number AS order_number, o.customer_reference AS order_reference
         FROM helpdesk.tickets t
         JOIN core.companies co ON co.id = t.company_id
         LEFT JOIN crm.customers c ON c.id = t.customer_id
         LEFT JOIN crm.contacts ct ON ct.id = t.contact_id
         LEFT JOIN helpdesk.teams tm ON tm.id = t.team_id
         LEFT JOIN sales.quotations q ON q.id = t.quotation_id
         LEFT JOIN sales.orders o ON o.id = t.order_id
         WHERE t.id = $1 AND t.company_id = $2",
    )
    .bind(ticket_id)
    .bind(company_id)
    .fetch_optional(conn)
    .await?
    .ok_or(AppError::NotFound("ticket"))?;
    let customer = v
        .customer_name
        .clone()
        .unwrap_or_else(|| v.contact_name.clone());
    let contact = if v.contact_name.is_empty() {
        customer.clone()
    } else {
        v.contact_name.clone()
    };
    let values = BTreeMap::from([
        ("customer.name".to_string(), customer),
        ("contact.name".to_string(), contact),
        (
            "contact.first_name".to_string(),
            v.contact_first_name.clone().unwrap_or_default(),
        ),
        (
            "contact.last_name".to_string(),
            v.contact_last_name.clone().unwrap_or_default(),
        ),
        // The greeting in the language of the answer and the way this person wants to be
        // addressed. Empty (so left visible) when the ticket has no known person.
        (
            "contact.salutation".to_string(),
            match (
                &v.contact_last_name,
                &v.contact_title,
                &v.contact_address_form,
            ) {
                (Some(last), Some(title), Some(form)) => tradocraft_crm::contacts::greeting(
                    &v.language,
                    title,
                    form,
                    v.contact_first_name.as_deref().unwrap_or_default(),
                    last,
                ),
                _ => String::new(),
            },
        ),
        ("ticket.number".to_string(), v.number),
        ("ticket.subject".to_string(), v.subject),
        ("agent.name".to_string(), agent_name.to_string()),
        ("team.name".to_string(), v.team_name.unwrap_or_default()),
        ("company.name".to_string(), v.company_name),
        (
            "quotation.number".to_string(),
            v.quotation_number.unwrap_or_default(),
        ),
        (
            "quotation.revision".to_string(),
            v.quotation_revision
                .map(|r| r.to_string())
                .unwrap_or_default(),
        ),
        (
            "quotation.total".to_string(),
            v.quotation_total
                .map(|t| format!("€ {}", tradocraft_documents::format_amount(t)))
                .unwrap_or_default(),
        ),
        (
            "order.number".to_string(),
            v.order_number.unwrap_or_default(),
        ),
        (
            "order.reference".to_string(),
            v.order_reference.unwrap_or_default(),
        ),
        ("__company_language".to_string(), v.company_language),
    ]);
    Ok((v.language, values))
}

/// Fills in a prepared answer for a ticket, in the ticket's language. Nothing is sent.
#[utoipa::path(post, path = "/tickets/{id}/prepared-answers/{answer_id}/render", tag = "helpdesk",
    params(("id" = Uuid, Path), ("answer_id" = Uuid, Path)),
    responses((status = 200, body = RenderedAnswer), (status = 404, body = ErrorBody)))]
async fn render_answer(
    State(state): State<AppState>,
    user: CurrentUser,
    Path((ticket_id, answer_id)): Path<(Uuid, Uuid)>,
) -> AppResult<Json<RenderedAnswer>> {
    user.require(Permission::HelpdeskRead)?;
    let mut conn = state.db.acquire().await?;
    let (language, values) = ticket_values(&mut conn, &user, ticket_id).await?;
    let answer = load(&mut conn, user.company_id, answer_id).await?;
    let (text, fallback) = pick_text(&answer.texts, &language, &values["__company_language"])
        .ok_or_else(|| AppError::Validation("this prepared answer has no text".into()))?;
    Ok(Json(RenderedAnswer {
        answer_id,
        language: text.language.clone(),
        fallback,
        subject: render(&text.subject, &values),
        body: render(&text.body, &values),
    }))
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(list_answers, create_answer))
        .routes(routes!(placeholders))
        .routes(routes!(update_answer))
        .routes(routes!(render_answer))
        .routes(routes!(suggest))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn t(l: &str) -> AnswerText {
        AnswerText {
            language: l.into(),
            subject: String::new(),
            body: l.into(),
        }
    }

    #[test]
    fn picks_the_ticket_language_then_falls_back() {
        let texts = vec![t("nl"), t("en"), t("de")];
        assert_eq!(
            pick_text(&texts, "de", "nl").map(|(t, f)| (t.language.as_str(), f)),
            Some(("de", false))
        );
        assert_eq!(
            pick_text(&texts, "es", "nl").map(|(t, f)| (t.language.as_str(), f)),
            Some(("en", true))
        );
        let no_en = vec![t("fr"), t("nl")];
        assert_eq!(
            pick_text(&no_en, "es", "nl").map(|(t, f)| (t.language.as_str(), f)),
            Some(("nl", true))
        );
        assert!(pick_text(&[], "nl", "nl").is_none());
    }

    #[test]
    fn keywords_are_trimmed_lowercased_and_unique() {
        let raw = vec![" Firmware ".to_string(), "firmware".into(), "".into(), "Update".into()];
        assert_eq!(clean_keywords(&raw).unwrap(), ["firmware", "update"]);
        assert!(clean_keywords(&["x".repeat(41)]).is_err());
        let many: Vec<String> = (0..21).map(|i| format!("k{i}")).collect();
        assert!(clean_keywords(&many).is_err());
    }

    fn cand<'a>(code: &'a str, name: &'a str, keywords: &'a [String], team: Option<Uuid>, has_language: bool) -> Candidate<'a> {
        Candidate { code, name, keywords, team_id: team, has_language }
    }

    #[test]
    fn an_exact_code_beats_a_prefix_beats_a_name_match() {
        let none: Vec<String> = vec![];
        let exact = score(&cand("pump", "Pump", &none, None, true), "pump", None, "").unwrap();
        let prefix = score(&cand("pump-fault", "Fault", &none, None, true), "pump", None, "").unwrap();
        let name = score(&cand("f1", "About the pump", &none, None, true), "pump", None, "").unwrap();
        assert!(exact > prefix && prefix > name, "{exact} {prefix} {name}");
        assert_eq!(score(&cand("zzz", "Other", &none, None, true), "pump", None, ""), None);
    }

    #[test]
    fn keywords_in_the_subject_team_and_language_raise_the_score() {
        let kw = vec!["firmware".to_string()];
        let team = Uuid::from_u128(7);
        let base = score(&cand("a", "A", &kw, None, false), "", None, "Pump noise").unwrap();
        let with_kw = score(&cand("a", "A", &kw, None, false), "", None, "Firmware update").unwrap();
        let with_team = score(&cand("a", "A", &kw, Some(team), false), "", Some(team), "Pump noise").unwrap();
        let with_lang = score(&cand("a", "A", &kw, None, true), "", None, "Pump noise").unwrap();
        assert!(with_kw > base && with_team > base && with_lang > base);
    }

    #[test]
    fn a_keyword_alone_can_match_the_query() {
        let kw = vec!["firmware".to_string()];
        assert!(score(&cand("a", "A", &kw, None, true), "firm", None, "").is_some());
    }
}
