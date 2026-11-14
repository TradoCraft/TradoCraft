//! Contacts: the people at a customer (sales contact, technician, purchasing, ...).
//!
//! * **Language** — the customer has the language of the company; a contact may have their own
//!   (`language`, NULL = same as the customer). [`Contact::effective_language`] is the one to
//!   write to.
//! * **Address** — `title` and `address_form` (formal "u / vous / Sie", informal "je / tu / du")
//!   decide the greeting, see [`greeting`].
//! * **Lookup** — by e-mail address (incoming mail) and by phone number (calls), see
//!   [`find_by_email`] and [`find_by_phone`].

use std::collections::{BTreeSet, HashMap};

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

type ErrorBody = tradocraft_core::error::ErrorBody;

pub const ROLES: [&str; 7] = [
    "sales_contact",
    "technical",
    "purchasing",
    "invoicing",
    "management",
    "quality",
    "other",
];
pub const TITLES: [&str; 3] = ["mr", "ms", "none"];
pub const ADDRESS_FORMS: [&str; 2] = ["formal", "informal"];
pub const PHONE_LABELS: [&str; 4] = ["work", "mobile", "direct", "other"];
pub const PORTAL_SCOPES: [&str; 2] = ["own", "customer"];

// ---------------------------------------------------------------------------------------------
// Pure helpers
// ---------------------------------------------------------------------------------------------

/// Country calling codes for the countries we do business with. Countries that keep the trunk
/// "0" after the country code (Italy) are left out on purpose.
const CALLING_CODES: [(&str, &str); 15] = [
    ("BE", "32"),
    ("NL", "31"),
    ("FR", "33"),
    ("DE", "49"),
    ("ES", "34"),
    ("LU", "352"),
    ("GB", "44"),
    ("AT", "43"),
    ("CH", "41"),
    ("PL", "48"),
    ("PT", "351"),
    ("IE", "353"),
    ("DK", "45"),
    ("SE", "46"),
    ("US", "1"),
];

/// Reduces a phone number to digits with country code, so that "+32 475 12 34 56",
/// "0032 (0)475/12.34.56" and (for a Belgian default) "0475 12 34 56" all become `32475123456`.
/// Returns `None` if it is not a plausible number or the national format cannot be resolved.
pub fn normalize_phone(raw: &str, default_country: &str) -> Option<String> {
    let raw = raw.trim();
    let mut digits: String = raw.chars().filter(char::is_ascii_digit).collect();
    let international = if raw.starts_with('+') {
        true
    } else if let Some(rest) = digits.strip_prefix("00") {
        digits = rest.to_string();
        true
    } else {
        false
    };
    if international {
        // "+32 (0)475 ...": the trunk zero after the country code is not dialled.
        if let Some((_, code)) = CALLING_CODES
            .iter()
            .filter(|(_, code)| digits.starts_with(code))
            .max_by_key(|(_, code)| code.len())
        {
            if digits[code.len()..].starts_with('0') {
                digits.remove(code.len());
            }
        }
    } else {
        let rest = digits.strip_prefix('0')?;
        let code = CALLING_CODES
            .iter()
            .find(|(c, _)| c.eq_ignore_ascii_case(default_country))?
            .1;
        digits = format!("{code}{rest}");
    }
    (6..=15).contains(&digits.len()).then_some(digits)
}

/// The salutation line of a letter or e-mail, in the person's language and address form.
/// Without a title (`none`) the full name is used, so nobody is addressed with the wrong gender.
pub fn greeting(
    language: &str,
    title: &str,
    address_form: &str,
    first_name: &str,
    last_name: &str,
) -> String {
    let (first, last) = (first_name.trim(), last_name.trim());
    let full = [first, last]
        .iter()
        .filter(|p| !p.is_empty())
        .copied()
        .collect::<Vec<_>>()
        .join(" ");
    let informal = address_form == "informal";
    // Informal greetings use the first name when we have one.
    let casual = if first.is_empty() { last } else { first };
    match (language, informal) {
        ("nl", true) => format!("Dag {casual},"),
        ("nl", false) => match title {
            "mr" => format!("Geachte heer {last},"),
            "ms" => format!("Geachte mevrouw {last},"),
            _ => format!("Geachte {full},"),
        },
        ("fr", true) => format!("Bonjour {casual},"),
        ("fr", false) => match title {
            "mr" => format!("Bonjour Monsieur {last},"),
            "ms" => format!("Bonjour Madame {last},"),
            _ => format!("Bonjour {full},"),
        },
        ("de", true) => format!("Hallo {casual},"),
        ("de", false) => match title {
            "mr" => format!("Sehr geehrter Herr {last},"),
            "ms" => format!("Sehr geehrte Frau {last},"),
            _ => format!("Guten Tag {full},"),
        },
        ("es", true) => format!("Hola {casual},"),
        ("es", false) => match title {
            "mr" => format!("Estimado Sr. {last},"),
            "ms" => format!("Estimada Sra. {last},"),
            _ => format!("Estimado/a {full},"),
        },
        (_, true) => format!("Hi {casual},"),
        (_, false) => match title {
            "mr" => format!("Dear Mr. {last},"),
            "ms" => format!("Dear Ms. {last},"),
            _ => format!("Dear {full},"),
        },
    }
}

fn check_one_of(field: &str, value: &str, allowed: &[&str]) -> AppResult<()> {
    if allowed.contains(&value) {
        Ok(())
    } else {
        Err(AppError::Validation(format!(
            "{field} must be one of {}",
            allowed.join(", ")
        )))
    }
}

// ---------------------------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------------------------

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct ContactEmail {
    pub email: String,
    pub is_primary: bool,
}

#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct ContactPhone {
    /// work | mobile | direct | other
    pub label: String,
    /// As entered.
    pub number: String,
    /// Digits with country code, used for lookup.
    pub normalized: String,
}

#[derive(Debug, Clone, Serialize, ToSchema)]
pub struct Contact {
    pub id: Uuid,
    pub customer_id: Uuid,
    pub customer_code: String,
    pub customer_name: String,
    pub first_name: String,
    pub last_name: String,
    pub full_name: String,
    pub job_title: String,
    /// mr | ms | none
    pub title: String,
    /// formal | informal
    pub address_form: String,
    /// The person's own language; null means the same as the customer.
    pub language: Option<String>,
    /// The language of the customer (company level).
    pub customer_language: String,
    /// The language to write to this person in: their own, else the customer's.
    pub effective_language: String,
    /// Ready-made salutation in the effective language and address form.
    pub greeting: String,
    /// sales_contact | technical | purchasing | invoicing | management | quality | other
    pub roles: Vec<String>,
    pub notes: String,
    pub active: bool,
    pub portal_access: bool,
    /// own | customer
    pub portal_scope: String,
    pub emails: Vec<ContactEmail>,
    pub phones: Vec<ContactPhone>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

impl Contact {
    pub fn primary_email(&self) -> Option<&str> {
        self.emails
            .iter()
            .find(|e| e.is_primary)
            .or(self.emails.first())
            .map(|e| e.email.as_str())
    }
}

#[derive(FromRow)]
struct ContactRow {
    id: Uuid,
    customer_id: Uuid,
    customer_code: String,
    customer_name: String,
    customer_language: String,
    first_name: String,
    last_name: String,
    job_title: String,
    title: String,
    address_form: String,
    language: Option<String>,
    roles: Vec<String>,
    notes: String,
    active: bool,
    portal_access: bool,
    portal_scope: String,
    created_at: DateTime<Utc>,
    updated_at: DateTime<Utc>,
}

const SELECT: &str = "SELECT c.id, c.customer_id, cu.code AS customer_code, cu.name AS customer_name,
        cu.language::text AS customer_language, c.first_name, c.last_name, c.job_title, c.title, c.address_form,
        c.language::text AS language, c.roles, c.notes, c.active, c.portal_access, c.portal_scope,
        c.created_at, c.updated_at
     FROM crm.contacts c JOIN crm.customers cu ON cu.id = c.customer_id";

/// Adds e-mail addresses and phone numbers to contact rows.
async fn assemble(conn: &mut PgConnection, rows: Vec<ContactRow>) -> AppResult<Vec<Contact>> {
    let ids: Vec<Uuid> = rows.iter().map(|r| r.id).collect();
    let emails: Vec<(Uuid, String, bool)> = sqlx::query_as(
        "SELECT contact_id, email, is_primary FROM crm.contact_emails WHERE contact_id = ANY($1)
         ORDER BY is_primary DESC, email",
    )
    .bind(&ids)
    .fetch_all(&mut *conn)
    .await?;
    let phones: Vec<(Uuid, String, String, String)> = sqlx::query_as(
        "SELECT contact_id, label, number, normalized FROM crm.contact_phones WHERE contact_id = ANY($1)
         ORDER BY label, number",
    )
    .bind(&ids)
    .fetch_all(&mut *conn)
    .await?;
    let mut email_map: HashMap<Uuid, Vec<ContactEmail>> = HashMap::new();
    for (id, email, is_primary) in emails {
        email_map
            .entry(id)
            .or_default()
            .push(ContactEmail { email, is_primary });
    }
    let mut phone_map: HashMap<Uuid, Vec<ContactPhone>> = HashMap::new();
    for (id, label, number, normalized) in phones {
        phone_map.entry(id).or_default().push(ContactPhone {
            label,
            number,
            normalized,
        });
    }
    Ok(rows
        .into_iter()
        .map(|r| {
            let effective = r
                .language
                .clone()
                .unwrap_or_else(|| r.customer_language.clone());
            Contact {
                full_name: [r.first_name.trim(), r.last_name.trim()]
                    .iter()
                    .filter(|p| !p.is_empty())
                    .copied()
                    .collect::<Vec<_>>()
                    .join(" "),
                greeting: greeting(
                    &effective,
                    &r.title,
                    &r.address_form,
                    &r.first_name,
                    &r.last_name,
                ),
                emails: email_map.remove(&r.id).unwrap_or_default(),
                phones: phone_map.remove(&r.id).unwrap_or_default(),
                effective_language: effective,
                id: r.id,
                customer_id: r.customer_id,
                customer_code: r.customer_code,
                customer_name: r.customer_name,
                first_name: r.first_name,
                last_name: r.last_name,
                job_title: r.job_title,
                title: r.title,
                address_form: r.address_form,
                language: r.language,
                customer_language: r.customer_language,
                roles: {
                    let mut roles = r.roles;
                    roles.sort();
                    roles
                },
                notes: r.notes,
                active: r.active,
                portal_access: r.portal_access,
                portal_scope: r.portal_scope,
                created_at: r.created_at,
                updated_at: r.updated_at,
            }
        })
        .collect())
}

pub async fn get_contact(conn: &mut PgConnection, id: Uuid) -> AppResult<Contact> {
    let rows: Vec<ContactRow> = sqlx::query_as(&format!("{SELECT} WHERE c.id = $1"))
        .bind(id)
        .fetch_all(&mut *conn)
        .await?;
    assemble(conn, rows)
        .await?
        .into_iter()
        .next()
        .ok_or(AppError::NotFound("contact"))
}

/// The contact that owns an e-mail address (exact match, case-insensitive), if any. Inactive
/// contacts are found too: a former colleague still writes from the same address.
pub async fn find_by_email(conn: &mut PgConnection, email: &str) -> AppResult<Option<Contact>> {
    let rows: Vec<ContactRow> = sqlx::query_as(&format!(
        "{SELECT} JOIN crm.contact_emails e ON e.contact_id = c.id WHERE e.email = $1"
    ))
    .bind(email.trim().to_lowercase())
    .fetch_all(&mut *conn)
    .await?;
    Ok(assemble(conn, rows).await?.into_iter().next())
}

/// Contacts with this phone number (active ones first). `default_country` resolves numbers in
/// national format ("0475 ..."). Empty if the number is not recognised.
pub async fn find_by_phone(
    conn: &mut PgConnection,
    number: &str,
    default_country: &str,
) -> AppResult<Vec<Contact>> {
    let Some(n) = normalize_phone(number, default_country) else {
        return Ok(vec![]);
    };
    let rows: Vec<ContactRow> = sqlx::query_as(&format!(
        "{SELECT} WHERE c.id IN (SELECT contact_id FROM crm.contact_phones WHERE normalized = $1)
         ORDER BY c.active DESC, c.last_name, c.first_name"
    ))
    .bind(n)
    .fetch_all(&mut *conn)
    .await?;
    assemble(conn, rows).await
}

// ---------------------------------------------------------------------------------------------
// Input
// ---------------------------------------------------------------------------------------------

#[derive(Debug, Deserialize, ToSchema)]
pub struct PhoneInput {
    /// work | mobile | direct | other
    #[serde(default = "default_label")]
    pub label: String,
    /// Any common format. Without a country code the customer's country is assumed.
    pub number: String,
}

fn default_label() -> String {
    "work".into()
}
fn default_title() -> String {
    "none".into()
}
fn default_address_form() -> String {
    "formal".into()
}
fn default_scope() -> String {
    "own".into()
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct ContactInput {
    #[serde(default)]
    pub first_name: String,
    pub last_name: String,
    #[serde(default)]
    pub job_title: String,
    /// mr | ms | none — used in the salutation.
    #[serde(default = "default_title")]
    pub title: String,
    /// formal | informal.
    #[serde(default = "default_address_form")]
    pub address_form: String,
    /// nl | fr | en | de | es; null = same as the customer.
    pub language: Option<String>,
    #[serde(default)]
    pub roles: Vec<String>,
    #[serde(default)]
    pub notes: String,
    #[serde(default = "default_true")]
    pub active: bool,
    #[serde(default)]
    pub portal_access: bool,
    /// own | customer
    #[serde(default = "default_scope")]
    pub portal_scope: String,
    /// The first one is the primary address.
    #[serde(default)]
    pub emails: Vec<String>,
    #[serde(default)]
    pub phones: Vec<PhoneInput>,
}

fn default_true() -> bool {
    true
}

struct Checked {
    emails: Vec<String>,
    phones: Vec<(String, String, String)>,
    roles: Vec<String>,
    language: Option<String>,
}

impl ContactInput {
    fn check(&self, customer_country: &str) -> AppResult<Checked> {
        if self.last_name.trim().is_empty() {
            return Err(AppError::Validation("last_name is required".into()));
        }
        check_one_of("title", &self.title, &TITLES)?;
        check_one_of("address_form", &self.address_form, &ADDRESS_FORMS)?;
        check_one_of("portal_scope", &self.portal_scope, &PORTAL_SCOPES)?;
        let language = self.language.as_deref().map(str::to_lowercase);
        if let Some(l) = &language {
            if !is_language(l) {
                return Err(AppError::Validation(format!(
                    "language must be one of {}",
                    LANGUAGES.join(", ")
                )));
            }
        }
        let roles: BTreeSet<String> = self.roles.iter().map(|r| r.trim().to_string()).collect();
        for r in &roles {
            check_one_of("role", r, &ROLES)?;
        }
        let mut emails: Vec<String> = Vec::new();
        for e in &self.emails {
            let e = e.trim().to_lowercase();
            let valid = e.len() >= 3
                && e.matches('@').count() == 1
                && !e.starts_with('@')
                && !e.ends_with('@')
                && !e.contains(char::is_whitespace);
            if !valid {
                return Err(AppError::Validation(format!("invalid e-mail address {e}")));
            }
            if !emails.contains(&e) {
                emails.push(e);
            }
        }
        let mut phones: Vec<(String, String, String)> = Vec::new();
        for p in &self.phones {
            check_one_of("phone label", &p.label, &PHONE_LABELS)?;
            let normalized = normalize_phone(&p.number, customer_country).ok_or_else(|| {
                AppError::Validation(format!(
                    "phone number {} is not recognised: enter it with the country code (+32 ...)",
                    p.number.trim()
                ))
            })?;
            if !phones.iter().any(|(_, _, n)| *n == normalized) {
                phones.push((p.label.clone(), p.number.trim().to_string(), normalized));
            }
        }
        if self.portal_access && emails.is_empty() {
            return Err(AppError::Validation(
                "portal access needs an e-mail address to send the login link to".into(),
            ));
        }
        Ok(Checked {
            emails,
            phones,
            roles: roles.into_iter().collect(),
            language,
        })
    }
}

/// Addresses must be unique over all contacts: say who has it instead of a database error.
async fn ensure_emails_free(
    conn: &mut PgConnection,
    emails: &[String],
    except: Option<Uuid>,
) -> AppResult<()> {
    let taken: Option<(String, String, String)> = sqlx::query_as(
        "SELECT e.email, c.first_name || ' ' || c.last_name, cu.name
         FROM crm.contact_emails e JOIN crm.contacts c ON c.id = e.contact_id
         JOIN crm.customers cu ON cu.id = c.customer_id
         WHERE e.email = ANY($1) AND ($2::uuid IS NULL OR c.id <> $2) LIMIT 1",
    )
    .bind(emails)
    .bind(except)
    .fetch_optional(conn)
    .await?;
    match taken {
        Some((email, name, customer)) => Err(AppError::Conflict(format!(
            "{email} already belongs to {} ({customer})",
            name.trim()
        ))),
        None => Ok(()),
    }
}

async fn replace_addresses(conn: &mut PgConnection, id: Uuid, checked: &Checked) -> AppResult<()> {
    sqlx::query("DELETE FROM crm.contact_emails WHERE contact_id = $1")
        .bind(id)
        .execute(&mut *conn)
        .await?;
    sqlx::query("DELETE FROM crm.contact_phones WHERE contact_id = $1")
        .bind(id)
        .execute(&mut *conn)
        .await?;
    for (i, email) in checked.emails.iter().enumerate() {
        sqlx::query(
            "INSERT INTO crm.contact_emails (id, contact_id, email, is_primary) VALUES ($1, $2, $3, $4)",
        )
        .bind(new_id())
        .bind(id)
        .bind(email)
        .bind(i == 0)
        .execute(&mut *conn)
        .await?;
    }
    for (label, number, normalized) in &checked.phones {
        sqlx::query(
            "INSERT INTO crm.contact_phones (id, contact_id, label, number, normalized) VALUES ($1, $2, $3, $4, $5)",
        )
        .bind(new_id())
        .bind(id)
        .bind(label)
        .bind(number)
        .bind(normalized)
        .execute(&mut *conn)
        .await?;
    }
    Ok(())
}

async fn customer_country(conn: &mut PgConnection, customer_id: Uuid) -> AppResult<String> {
    sqlx::query_scalar("SELECT country_code::text FROM crm.customers WHERE id = $1")
        .bind(customer_id)
        .fetch_optional(conn)
        .await?
        .ok_or(AppError::NotFound("customer"))
}

// ---------------------------------------------------------------------------------------------
// Endpoints
// ---------------------------------------------------------------------------------------------

#[derive(Debug, Deserialize, IntoParams)]
pub struct CustomerContactsParams {
    /// Include contacts who left or are otherwise inactive.
    #[serde(default)]
    pub include_inactive: bool,
}

#[utoipa::path(get, path = "/customers/{id}/contacts", tag = "crm", operation_id = "list_customer_contacts",
    params(("id" = Uuid, Path), CustomerContactsParams),
    responses((status = 200, body = Vec<Contact>), (status = 404, body = ErrorBody)))]
async fn list_customer_contacts(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Query(p): Query<CustomerContactsParams>,
) -> AppResult<Json<Vec<Contact>>> {
    user.require(Permission::CustomersRead)?;
    let mut conn = state.db.acquire().await?;
    customer_country(&mut conn, id).await?;
    let rows: Vec<ContactRow> = sqlx::query_as(&format!(
        "{SELECT} WHERE c.customer_id = $1 AND ($2 OR c.active) ORDER BY c.active DESC, c.last_name, c.first_name"
    ))
    .bind(id)
    .bind(p.include_inactive)
    .fetch_all(&mut *conn)
    .await?;
    Ok(Json(assemble(&mut conn, rows).await?))
}

#[utoipa::path(post, path = "/customers/{id}/contacts", tag = "crm", operation_id = "create_contact",
    params(("id" = Uuid, Path)), request_body = ContactInput,
    responses((status = 201, body = Contact), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn create_contact(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(customer_id): Path<Uuid>,
    Json(input): Json<ContactInput>,
) -> AppResult<(StatusCode, Json<Contact>)> {
    user.require(Permission::ContactsWrite)?;
    let mut tx = state.db.begin().await?;
    let country = customer_country(&mut tx, customer_id).await?;
    let checked = input.check(&country)?;
    ensure_emails_free(&mut tx, &checked.emails, None).await?;
    let id = new_id();
    sqlx::query(
        "INSERT INTO crm.contacts (id, customer_id, first_name, last_name, job_title, title, address_form, language,
                                   roles, notes, active, portal_access, portal_scope)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)",
    )
    .bind(id)
    .bind(customer_id)
    .bind(input.first_name.trim())
    .bind(input.last_name.trim())
    .bind(input.job_title.trim())
    .bind(&input.title)
    .bind(&input.address_form)
    .bind(&checked.language)
    .bind(&checked.roles)
    .bind(&input.notes)
    .bind(input.active)
    .bind(input.portal_access)
    .bind(&input.portal_scope)
    .execute(&mut *tx)
    .await?;
    replace_addresses(&mut tx, id, &checked).await?;
    audit::record(
        &mut tx,
        &user,
        "contact",
        id,
        "created",
        serde_json::json!({ "customer_id": customer_id }),
    )
    .await?;
    let contact = get_contact(&mut tx, id).await?;
    tx.commit().await?;
    Ok((StatusCode::CREATED, Json(contact)))
}

#[utoipa::path(get, path = "/contacts/{id}", tag = "crm", operation_id = "get_contact",
    params(("id" = Uuid, Path)), responses((status = 200, body = Contact), (status = 404, body = ErrorBody)))]
async fn get_contact_handler(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<Contact>> {
    user.require(Permission::CustomersRead)?;
    let mut conn = state.db.acquire().await?;
    Ok(Json(get_contact(&mut conn, id).await?))
}

#[utoipa::path(put, path = "/contacts/{id}", tag = "crm", operation_id = "update_contact",
    params(("id" = Uuid, Path)), request_body = ContactInput,
    responses((status = 200, body = Contact), (status = 409, body = ErrorBody), (status = 422, body = ErrorBody)))]
async fn update_contact(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Json(input): Json<ContactInput>,
) -> AppResult<Json<Contact>> {
    user.require(Permission::ContactsWrite)?;
    let mut tx = state.db.begin().await?;
    let existing = get_contact(&mut tx, id).await?;
    let country = customer_country(&mut tx, existing.customer_id).await?;
    let checked = input.check(&country)?;
    ensure_emails_free(&mut tx, &checked.emails, Some(id)).await?;
    sqlx::query(
        "UPDATE crm.contacts SET first_name = $2, last_name = $3, job_title = $4, title = $5, address_form = $6,
                language = $7, roles = $8, notes = $9, active = $10, portal_access = $11, portal_scope = $12,
                updated_at = now()
         WHERE id = $1",
    )
    .bind(id)
    .bind(input.first_name.trim())
    .bind(input.last_name.trim())
    .bind(input.job_title.trim())
    .bind(&input.title)
    .bind(&input.address_form)
    .bind(&checked.language)
    .bind(&checked.roles)
    .bind(&input.notes)
    .bind(input.active)
    .bind(input.portal_access)
    .bind(&input.portal_scope)
    .execute(&mut *tx)
    .await?;
    replace_addresses(&mut tx, id, &checked).await?;
    if !input.active || !input.portal_access {
        // Leaving or losing access ends the open portal sessions at once.
        sqlx::query(
            "UPDATE portal.sessions SET revoked_at = now() WHERE contact_id = $1 AND revoked_at IS NULL",
        )
        .bind(id)
        .execute(&mut *tx)
        .await?;
    }
    audit::record(
        &mut tx,
        &user,
        "contact",
        id,
        "updated",
        serde_json::json!({ "portal_access": input.portal_access, "active": input.active }),
    )
    .await?;
    let contact = get_contact(&mut tx, id).await?;
    tx.commit().await?;
    Ok(Json(contact))
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct LookupParams {
    /// A phone number in any format, e.g. the caller id.
    pub phone: Option<String>,
    /// An e-mail address.
    pub email: Option<String>,
    /// Part of a name (first, last or customer), ignoring case and accents.
    pub q: Option<String>,
}

/// A customer found through its main phone number or e-mail address, when no contact matches.
#[derive(Debug, Serialize, FromRow, ToSchema)]
pub struct CustomerMatch {
    pub id: Uuid,
    pub code: String,
    pub name: String,
    pub language: String,
    /// phone | email
    pub matched_on: String,
}

#[derive(Debug, Serialize, ToSchema)]
pub struct LookupResult {
    pub contacts: Vec<Contact>,
    /// Customers whose main phone number or e-mail address matches. Useful when the caller is
    /// not (yet) a known contact, or calls from the customer's switchboard.
    pub customers: Vec<CustomerMatch>,
}

/// Finds who is calling or writing: by phone number, e-mail address or name.
#[utoipa::path(get, path = "/contacts/lookup", tag = "crm", operation_id = "lookup_contacts", params(LookupParams),
    responses((status = 200, body = LookupResult), (status = 422, body = ErrorBody)))]
async fn lookup(
    State(state): State<AppState>,
    user: CurrentUser,
    Query(p): Query<LookupParams>,
) -> AppResult<Json<LookupResult>> {
    user.require(Permission::CustomersRead)?;
    let phone = p.phone.as_deref().map(str::trim).filter(|s| !s.is_empty());
    let email = p.email.as_deref().map(str::trim).filter(|s| !s.is_empty());
    let q = p.q.as_deref().map(str::trim).filter(|s| !s.is_empty());
    if phone.is_none() && email.is_none() && q.is_none() {
        return Err(AppError::Validation(
            "give a phone number, an e-mail address or a name".into(),
        ));
    }
    let mut conn = state.db.acquire().await?;
    let country = tradocraft_core::company::get_company(&state.db, user.company_id)
        .await?
        .country_code;
    let mut contacts: Vec<Contact> = vec![];
    let mut customers: Vec<CustomerMatch> = vec![];
    if let Some(phone) = phone {
        let Some(n) = normalize_phone(phone, &country) else {
            return Err(AppError::Validation(format!(
                "phone number {phone} is not recognised: include the country code"
            )));
        };
        contacts = find_by_phone(&mut conn, phone, &country).await?;
        // Main numbers are stored as typed, so compare the last 8 digits.
        let tail = &n[n.len().saturating_sub(8)..];
        customers = sqlx::query_as(
            "SELECT id, code, name, language::text AS language, 'phone' AS matched_on FROM crm.customers
             WHERE active AND phone IS NOT NULL
               AND right(regexp_replace(phone, '[^0-9]', '', 'g'), 8) = $1 AND length($1) = 8
             ORDER BY name LIMIT 10",
        )
        .bind(tail)
        .fetch_all(&mut *conn)
        .await?;
    }
    if let Some(email) = email {
        if let Some(c) = find_by_email(&mut conn, email).await? {
            if !contacts.iter().any(|x| x.id == c.id) {
                contacts.push(c);
            }
        }
        let by_email: Vec<CustomerMatch> = sqlx::query_as(
            "SELECT id, code, name, language::text AS language, 'email' AS matched_on FROM crm.customers
             WHERE active AND lower(email) = lower($1) ORDER BY name LIMIT 10",
        )
        .bind(email)
        .fetch_all(&mut *conn)
        .await?;
        customers.extend(by_email);
    }
    if let Some(pattern) = tradocraft_core::search::pattern(q) {
        let rows: Vec<ContactRow> = sqlx::query_as(&format!(
            "{SELECT} WHERE {} OR {} OR {}
             ORDER BY c.active DESC, c.last_name, c.first_name LIMIT 20",
            tradocraft_core::search::matches("c.first_name || ' ' || c.last_name", "$1"),
            tradocraft_core::search::matches("c.last_name || ' ' || c.first_name", "$1"),
            tradocraft_core::search::matches("cu.name", "$1"),
        ))
        .bind(pattern)
        .fetch_all(&mut *conn)
        .await?;
        for c in assemble(&mut conn, rows).await? {
            if !contacts.iter().any(|x| x.id == c.id) {
                contacts.push(c);
            }
        }
    }
    contacts.sort_by_key(|c| !c.active);
    contacts.truncate(20);
    Ok(Json(LookupResult {
        contacts,
        customers,
    }))
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(list_customer_contacts, create_contact))
        .routes(routes!(get_contact_handler, update_contact))
        .routes(routes!(lookup))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn phone_numbers_in_any_format_normalize_the_same() {
        let expected = Some("32475123456".to_string());
        for raw in [
            "+32 475 12 34 56",
            "0032 475 12 34 56",
            "+32 (0)475/12.34.56",
            "0475 12 34 56",
            "  0475-12-34-56 ",
        ] {
            assert_eq!(normalize_phone(raw, "BE"), expected, "{raw}");
        }
    }

    #[test]
    fn national_numbers_use_the_default_country() {
        assert_eq!(normalize_phone("0221 123456", "DE").unwrap(), "49221123456");
        assert_eq!(
            normalize_phone("06 12 34 56 78", "fr").unwrap(),
            "33612345678"
        );
        // A country we cannot resolve, and rubbish, are refused rather than guessed.
        assert_eq!(normalize_phone("0221 123456", "XX"), None);
        assert_eq!(normalize_phone("123456", "BE"), None);
        assert_eq!(normalize_phone("abc", "BE"), None);
        assert_eq!(normalize_phone("+32 1", "BE"), None);
    }

    #[test]
    fn formal_greetings_follow_language_and_title() {
        assert_eq!(
            greeting("nl", "mr", "formal", "Jan", "Peeters"),
            "Geachte heer Peeters,"
        );
        assert_eq!(
            greeting("nl", "ms", "formal", "Els", "Peeters"),
            "Geachte mevrouw Peeters,"
        );
        assert_eq!(
            greeting("fr", "ms", "formal", "Marie", "Dupont"),
            "Bonjour Madame Dupont,"
        );
        assert_eq!(
            greeting("de", "mr", "formal", "Hans", "Müller"),
            "Sehr geehrter Herr Müller,"
        );
        assert_eq!(
            greeting("es", "ms", "formal", "Ana", "Ruiz"),
            "Estimada Sra. Ruiz,"
        );
        assert_eq!(
            greeting("en", "mr", "formal", "Tom", "Hill"),
            "Dear Mr. Hill,"
        );
    }

    #[test]
    fn without_title_the_full_name_is_used() {
        assert_eq!(
            greeting("nl", "none", "formal", "Sam", "Peeters"),
            "Geachte Sam Peeters,"
        );
        assert_eq!(greeting("en", "none", "formal", "", "Hill"), "Dear Hill,");
    }

    #[test]
    fn informal_greetings_use_the_first_name() {
        assert_eq!(
            greeting("nl", "mr", "informal", "Jan", "Peeters"),
            "Dag Jan,"
        );
        assert_eq!(
            greeting("fr", "ms", "informal", "Marie", "Dupont"),
            "Bonjour Marie,"
        );
        assert_eq!(
            greeting("de", "none", "informal", "Hans", "Müller"),
            "Hallo Hans,"
        );
        assert_eq!(
            greeting("es", "none", "informal", "Ana", "Ruiz"),
            "Hola Ana,"
        );
        assert_eq!(greeting("en", "none", "informal", "", "Hill"), "Hi Hill,");
    }
}
