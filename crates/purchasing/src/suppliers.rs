use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::{FromRow, PgConnection};
use tradocraft_core::vat_check::{Assessment, VatDuplicate};
use tradocraft_core::{audit, new_id, search, vat, AppError, AppResult, CurrentUser};
use utoipa::ToSchema;
use uuid::Uuid;

/// A supplier of the company.
#[derive(Debug, Clone, Serialize, FromRow, ToSchema)]
pub struct Supplier {
    pub id: Uuid,
    pub company_id: Uuid,
    pub name: String,
    pub code: String,
    pub country: String,
    pub currency: String,
    pub email: String,
    pub phone: String,
    pub contact_person: String,
    pub payment_terms_days: i32,
    pub tax_id: String,
    pub active: bool,
    pub notes: String,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// Payload to create a supplier.
#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct NewSupplierInput {
    pub name: String,
    pub code: Option<String>,
    pub country: String,
    pub currency: Option<String>,
    pub email: Option<String>,
    pub phone: Option<String>,
    pub contact_person: Option<String>,
    pub payment_terms_days: Option<i32>,
    pub tax_id: Option<String>,
    pub notes: Option<String>,
}

/// Partial supplier update; omitted fields keep their value.
#[derive(Debug, Clone, Deserialize, ToSchema)]
pub struct UpdateSupplierInput {
    pub name: Option<String>,
    pub code: Option<String>,
    pub country: Option<String>,
    pub currency: Option<String>,
    pub email: Option<String>,
    pub phone: Option<String>,
    pub contact_person: Option<String>,
    pub payment_terms_days: Option<i32>,
    pub tax_id: Option<String>,
    pub active: Option<bool>,
    pub notes: Option<String>,
}

/// Normalizes a currency code to upper case and requires exactly 3 ASCII letters.
pub fn normalize_currency(raw: &str) -> AppResult<String> {
    let c = raw.trim().to_uppercase();
    if c.len() != 3 || !c.chars().all(|ch| ch.is_ascii_alphabetic()) {
        return Err(AppError::Validation(
            "currency must be a 3-letter code".into(),
        ));
    }
    Ok(c)
}

/// Loads a supplier of the company.
pub async fn load(conn: &mut PgConnection, company_id: Uuid, id: Uuid) -> AppResult<Supplier> {
    sqlx::query_as::<_, Supplier>(
        "SELECT id, company_id, name, code, country, currency, email, phone, contact_person,
                payment_terms_days, tax_id, active, notes, created_at, updated_at
         FROM purchasing.suppliers
         WHERE company_id = $1 AND id = $2",
    )
    .bind(company_id)
    .bind(id)
    .fetch_optional(conn)
    .await?
    .ok_or(AppError::NotFound("supplier"))
}

/// Lists suppliers of the company, optionally only active ones and only those whose name, code,
/// e-mail address or contact person contains `q`, ignoring case and accents (ADR 0057).
pub async fn list(
    conn: &mut PgConnection,
    company_id: Uuid,
    active_only: bool,
    q: Option<&str>,
) -> AppResult<Vec<Supplier>> {
    let filter = format!(
        "($3::text IS NULL OR {} OR {} OR {} OR {})",
        search::matches("name", "$3"),
        search::matches("code", "$3"),
        search::matches("email", "$3"),
        search::matches("contact_person", "$3"),
    );
    sqlx::query_as::<_, Supplier>(&format!(
        "SELECT id, company_id, name, code, country, currency, email, phone, contact_person,
                payment_terms_days, tax_id, active, notes, created_at, updated_at
         FROM purchasing.suppliers
         WHERE company_id = $1 AND ($2 = false OR active = true) AND {filter}
         ORDER BY name ASC"
    ))
    .bind(company_id)
    .bind(active_only)
    .bind(search::pattern(q))
    .fetch_all(conn)
    .await
    .map_err(Into::into)
}

/// Creates a supplier; a duplicate code yields a conflict.
pub async fn create(
    conn: &mut PgConnection,
    user: &CurrentUser,
    input: NewSupplierInput,
) -> AppResult<Supplier> {
    let name = input.name.trim();
    if name.is_empty() {
        return Err(AppError::Validation("supplier name cannot be empty".into()));
    }
    let country = input.country.trim().to_uppercase();
    if country.len() != 2 {
        return Err(AppError::Validation(
            "country must be a 2-letter ISO code".into(),
        ));
    }
    let code = input.code.unwrap_or_default().trim().to_uppercase();
    let currency = normalize_currency(input.currency.as_deref().unwrap_or("EUR"))?;
    let tax_id = input.tax_id.unwrap_or_default().trim().to_string();
    if let Some(m) = vat::problem(&tax_id, Some(&country)) {
        return Err(AppError::Validation(m));
    }
    let id = new_id();

    let res = sqlx::query_as::<_, Supplier>(
        "INSERT INTO purchasing.suppliers (
            id, company_id, name, code, country, currency, email, phone, contact_person,
            payment_terms_days, tax_id, active, notes, created_at, updated_at
         )
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, true, $12, now(), now())
         RETURNING id, company_id, name, code, country, currency, email, phone, contact_person,
                   payment_terms_days, tax_id, active, notes, created_at, updated_at",
    )
    .bind(id)
    .bind(user.company_id)
    .bind(name)
    .bind(&code)
    .bind(&country)
    .bind(&currency)
    .bind(input.email.unwrap_or_default().trim())
    .bind(input.phone.unwrap_or_default().trim())
    .bind(input.contact_person.unwrap_or_default().trim())
    .bind(input.payment_terms_days.unwrap_or(30))
    .bind(&tax_id)
    .bind(input.notes.unwrap_or_default().trim())
    .fetch_one(&mut *conn)
    .await;

    let s = match res {
        Ok(s) => s,
        Err(sqlx::Error::Database(e)) if e.is_unique_violation() => {
            return Err(AppError::Conflict("supplier code already exists".into()));
        }
        Err(e) => return Err(e.into()),
    };

    audit::record(
        conn,
        user,
        "supplier",
        id,
        "created",
        serde_json::json!({ "name": name, "code": code }),
    )
    .await?;

    Ok(s)
}

/// Updates a supplier (row-locked read-merge-write) and records an audit event.
pub async fn update(
    conn: &mut PgConnection,
    user: &CurrentUser,
    id: Uuid,
    input: UpdateSupplierInput,
) -> AppResult<Supplier> {
    sqlx::query_scalar::<_, Uuid>(
        "SELECT id FROM purchasing.suppliers WHERE company_id = $1 AND id = $2 FOR UPDATE",
    )
    .bind(user.company_id)
    .bind(id)
    .fetch_optional(&mut *conn)
    .await?
    .ok_or(AppError::NotFound("supplier"))?;
    let current = load(conn, user.company_id, id).await?;
    let before = current.clone();
    let previous_tax_id = current.tax_id.clone();
    let name = input
        .name
        .map(|n| n.trim().to_string())
        .unwrap_or(current.name);
    if name.is_empty() {
        return Err(AppError::Validation("supplier name cannot be empty".into()));
    }
    let country = input
        .country
        .map(|c| c.trim().to_uppercase())
        .unwrap_or(current.country);
    if country.len() != 2 {
        return Err(AppError::Validation(
            "country must be a 2-letter ISO code".into(),
        ));
    }
    let code = input
        .code
        .map(|c| c.trim().to_uppercase())
        .unwrap_or(current.code);
    let currency = normalize_currency(input.currency.as_deref().unwrap_or(&current.currency))?;
    let email = input
        .email
        .map(|e| e.trim().to_string())
        .unwrap_or(current.email);
    let phone = input
        .phone
        .map(|p| p.trim().to_string())
        .unwrap_or(current.phone);
    let contact_person = input
        .contact_person
        .map(|p| p.trim().to_string())
        .unwrap_or(current.contact_person);
    let payment_terms_days = input
        .payment_terms_days
        .unwrap_or(current.payment_terms_days);
    let tax_id = input
        .tax_id
        .map(|t| t.trim().to_string())
        .unwrap_or(current.tax_id);
    // A number entered before numbers were checked stays editable around: only a new or changed
    // number has to pass (ADR 0058).
    if !vat::same_number(&tax_id, &previous_tax_id, Some(&country)) {
        if let Some(m) = vat::problem(&tax_id, Some(&country)) {
            return Err(AppError::Validation(m));
        }
    }
    let active = input.active.unwrap_or(current.active);
    let notes = input
        .notes
        .map(|n| n.trim().to_string())
        .unwrap_or(current.notes);

    let res = sqlx::query_as::<_, Supplier>(
        "UPDATE purchasing.suppliers
         SET name = $3, code = $4, country = $5, currency = $6, email = $7, phone = $8,
             contact_person = $9, payment_terms_days = $10, tax_id = $11, active = $12,
             notes = $13, updated_at = now()
         WHERE company_id = $1 AND id = $2
         RETURNING id, company_id, name, code, country, currency, email, phone, contact_person,
                   payment_terms_days, tax_id, active, notes, created_at, updated_at",
    )
    .bind(user.company_id)
    .bind(id)
    .bind(&name)
    .bind(&code)
    .bind(&country)
    .bind(&currency)
    .bind(&email)
    .bind(&phone)
    .bind(&contact_person)
    .bind(payment_terms_days)
    .bind(&tax_id)
    .bind(active)
    .bind(&notes)
    .fetch_one(&mut *conn)
    .await;

    let s = match res {
        Ok(s) => s,
        Err(sqlx::Error::Database(e)) if e.is_unique_violation() => {
            return Err(AppError::Conflict("supplier code already exists".into()));
        }
        Err(e) => return Err(e.into()),
    };

    // What changed, field by field, next to the identifying keys, for the audit viewer (ADR 0059).
    let changes = audit::Changes::new()
        .field("name", &before.name, &name)
        .field("code", &before.code, &code)
        .field("country", &before.country, &country)
        .field("currency", &before.currency, &currency)
        .field("email", &before.email, &email)
        .field("phone", &before.phone, &phone)
        .field("contact_person", &before.contact_person, &contact_person)
        .field(
            "payment_terms_days",
            &before.payment_terms_days,
            &payment_terms_days,
        )
        .field("tax_id", &before.tax_id, &tax_id)
        .field("active", &before.active, &active)
        .field("notes", &before.notes, &notes);
    audit::record(
        conn,
        user,
        "supplier",
        id,
        "updated",
        changes.into_data_with(serde_json::json!({ "name": name, "code": code, "active": active })),
    )
    .await?;

    Ok(s)
}

/// Suppliers of the company with the same VAT number (ADR 0058): the number's key, or the bare
/// national part for a supplier in the number's country. Other companies' suppliers are not looked
/// at.
pub async fn vat_duplicates(
    conn: &mut PgConnection,
    company_id: Uuid,
    a: &Assessment,
    exclude: Option<Uuid>,
) -> AppResult<Vec<VatDuplicate>> {
    let (bare, countries) = a.bare.clone().unwrap_or_default();
    sqlx::query_as::<_, VatDuplicate>(
        "SELECT id, code, name, active FROM purchasing.suppliers
         WHERE company_id = $1 AND tax_id <> ''
           AND (core.vat_key(tax_id) = ANY($2)
                OR (core.vat_key(tax_id) = $3 AND upper(country) = ANY($4)))
           AND ($5::uuid IS NULL OR id <> $5)
         ORDER BY active DESC, name LIMIT 10",
    )
    .bind(company_id)
    .bind(&a.keys)
    .bind(bare)
    .bind(countries)
    .bind(exclude)
    .fetch_all(conn)
    .await
    .map_err(Into::into)
}

/// Looks up supplier names by id (for modules that only hold the id, such as finance). Unknown
/// or foreign ids are simply absent from the result.
pub async fn names_by_id(
    conn: &mut PgConnection,
    company_id: Uuid,
    ids: &[Uuid],
) -> AppResult<Vec<(Uuid, String)>> {
    sqlx::query_as::<_, (Uuid, String)>(
        "SELECT id, name FROM purchasing.suppliers WHERE company_id = $1 AND id = ANY($2)",
    )
    .bind(company_id)
    .bind(ids)
    .fetch_all(conn)
    .await
    .map_err(Into::into)
}
