//! One-click unsubscribe from customer mailings (ADR 0099). Every mail-merge delivery carries a
//! link with a random 256-bit token; only its SHA-256 hash is stored on the delivery. Whoever
//! holds the link may put that address on the company's opt-out register: no portal login is
//! needed, which is the point of a one-click unsubscribe. Links do not expire.

use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::Json;
use rand::RngCore;
use serde::Serialize;
use sha2::{Digest, Sha256};
use sqlx::{FromRow, PgConnection};
use tradocraft_core::{audit, AppError, AppResult, AppState};
use utoipa::ToSchema;
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

type ErrorBody = tradocraft_core::error::ErrorBody;

pub const TOKEN_PREFIX: &str = "tcu_";

/// A new random token and its hash.
pub(crate) fn new_token() -> (String, Vec<u8>) {
    let mut bytes = [0u8; 32];
    rand::rng().fill_bytes(&mut bytes);
    let token = format!(
        "{TOKEN_PREFIX}{}",
        bytes.iter().map(|b| format!("{b:02x}")).collect::<String>()
    );
    let hash = hash_token(&token);
    (token, hash)
}

pub fn hash_token(token: &str) -> Vec<u8> {
    Sha256::digest(token.trim().as_bytes()).to_vec()
}

/// The unsubscribe link of a delivery.
pub(crate) fn link(portal_url: &str, token: &str) -> String {
    format!(
        "{}/unsubscribe#token={token}",
        portal_url.trim_end_matches('/')
    )
}

/// The footer appended to every mailing, in the recipient's language.
pub(crate) fn footer(language: &str, company: &str, link: &str) -> String {
    match language {
        "nl" => format!(
            "U ontvangt deze mailing als klant van {company}. Wilt u deze mailings niet meer ontvangen? Schrijf u hier uit: {link}"
        ),
        "fr" => format!(
            "Vous recevez cet envoi en tant que client de {company}. Vous ne souhaitez plus recevoir ces envois ? Désabonnez-vous ici : {link}"
        ),
        "de" => format!(
            "Sie erhalten dieses Mailing als Kunde von {company}. Sie möchten diese Mailings nicht mehr erhalten? Hier abmelden: {link}"
        ),
        "es" => format!(
            "Recibe este envío como cliente de {company}. ¿No desea recibir más estos envíos? Dese de baja aquí: {link}"
        ),
        _ => format!(
            "You receive this mailing as a customer of {company}. No longer want to receive these mailings? Unsubscribe here: {link}"
        ),
    }
}

/// `jane@example.com` → `j***@example.com`: enough for the recipient to recognise the address,
/// not enough to learn it from a forwarded link.
fn mask(email: &str) -> String {
    match email.split_once('@') {
        Some((local, domain)) => {
            let first = local.chars().next().map(String::from).unwrap_or_default();
            format!("{first}***@{domain}")
        }
        None => "***".into(),
    }
}

#[derive(Debug, Serialize, ToSchema)]
pub struct UnsubscribeInfo {
    pub company_name: String,
    /// The address the mailing went to, masked (`j***@example.com`).
    pub email: String,
    /// The language of the mailing, for the page the recipient lands on.
    pub language: String,
    /// Whether the address is already on the company's opt-out register.
    pub unsubscribed: bool,
}

#[derive(FromRow)]
struct DeliveryRow {
    company_id: Uuid,
    company_name: String,
    mailing_id: Uuid,
    customer_id: Uuid,
    email: String,
    language: String,
    unsubscribed: bool,
}

async fn find(conn: &mut PgConnection, token: &str) -> AppResult<DeliveryRow> {
    sqlx::query_as(
        "SELECT m.company_id, co.name AS company_name, a.mailing_id, a.customer_id,
                lower(btrim(o.to_address)) AS email, a.language,
                EXISTS (SELECT 1 FROM crm.mailing_opt_outs x
                        WHERE x.company_id = m.company_id AND x.email = lower(btrim(o.to_address))) AS unsubscribed
         FROM crm.mailing_deliveries a JOIN crm.mailings m ON m.id = a.mailing_id
         JOIN core.mail_outbox o ON o.id = a.outbox_id AND o.company_id = m.company_id
         JOIN core.companies co ON co.id = m.company_id
         WHERE a.unsubscribe_token_hash = $1",
    )
    .bind(hash_token(token))
    .fetch_optional(conn)
    .await?
    .ok_or(AppError::NotFound("unsubscribe link"))
}

fn info(row: DeliveryRow) -> UnsubscribeInfo {
    UnsubscribeInfo {
        company_name: row.company_name,
        email: mask(&row.email),
        language: row.language,
        unsubscribed: row.unsubscribed,
    }
}

/// What the recipient sees before unsubscribing. Reading changes nothing, so mail scanners that
/// open links do not unsubscribe anyone.
#[utoipa::path(get, path = "/mailing-unsubscribe/{token}", tag = "crm", operation_id = "get_mailing_unsubscribe",
    params(("token" = String, Path)),
    responses((status = 200, body = UnsubscribeInfo), (status = 404, body = ErrorBody)))]
async fn get_unsubscribe(
    State(state): State<AppState>,
    Path(token): Path<String>,
) -> AppResult<Json<UnsubscribeInfo>> {
    let mut conn = state.db.acquire().await?;
    Ok(Json(info(find(&mut conn, &token).await?)))
}

/// Puts the address on the company's opt-out register. Idempotent: unsubscribing twice is fine.
#[utoipa::path(post, path = "/mailing-unsubscribe/{token}", tag = "crm", operation_id = "mailing_unsubscribe",
    params(("token" = String, Path)),
    responses((status = 204), (status = 404, body = ErrorBody)))]
async fn unsubscribe(
    State(state): State<AppState>,
    Path(token): Path<String>,
) -> AppResult<StatusCode> {
    let mut tx = state.db.begin().await?;
    let row = find(&mut tx, &token).await?;
    let added = sqlx::query(
        "INSERT INTO crm.mailing_opt_outs (company_id, email, source) VALUES ($1, $2, 'unsubscribe_link')
         ON CONFLICT DO NOTHING",
    )
    .bind(row.company_id)
    .bind(&row.email)
    .execute(&mut *tx)
    .await?;
    if added.rows_affected() > 0 {
        audit::record_system(
            &mut tx,
            row.company_id,
            "mailing_opt_out",
            row.company_id,
            "added",
            serde_json::json!({
                "email": row.email,
                "source": "unsubscribe_link",
                "mailing_id": row.mailing_id,
                "customer_id": row.customer_id,
            }),
        )
        .await?;
    }
    tx.commit().await?;
    Ok(StatusCode::NO_CONTENT)
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new().routes(routes!(get_unsubscribe, unsubscribe))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_language_has_the_link_and_the_company() {
        for l in ["nl", "fr", "en", "de", "es"] {
            let text = footer(l, "Alpha NV", "https://p/unsubscribe#token=tcu_x");
            assert!(text.contains("https://p/unsubscribe#token=tcu_x"), "{l}");
            assert!(text.contains("Alpha NV"), "{l}");
        }
        assert_ne!(footer("nl", "A", "x"), footer("en", "A", "x"));
    }

    #[test]
    fn links_and_masks() {
        assert_eq!(
            link("https://portal.example/", "tcu_1"),
            "https://portal.example/unsubscribe#token=tcu_1"
        );
        assert_eq!(mask("jane@example.com"), "j***@example.com");
        assert_eq!(mask("élise@example.com"), "é***@example.com");
        assert_eq!(mask("broken"), "***");
    }

    #[test]
    fn tokens_are_long_random_and_hashed() {
        let (a, ha) = new_token();
        let (b, _) = new_token();
        assert_ne!(a, b);
        assert!(a.starts_with(TOKEN_PREFIX) && a.len() == TOKEN_PREFIX.len() + 64);
        assert_eq!(ha, hash_token(&a));
        assert_ne!(ha, a.as_bytes());
    }
}
