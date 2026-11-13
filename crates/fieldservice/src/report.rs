//! The service report: a PDF of a job in the customer's language (`templates/service_report.typ`)
//! and the e-mail that carries it.
//!
//! The report shows what the customer is entitled to see: tasks and their result, time, parts,
//! equipment with its warranty, the completion text, a few photos and the signature. Instructions
//! for the technician, notes on work log entries and everything else internal are never printed.

use axum::extract::{Path, Query, State};
use axum::http::header;
use axum::response::{IntoResponse, Response};
use axum::Json;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::PgConnection;
use tradocraft_core::company::{get_company, Company};
use tradocraft_core::files;
use tradocraft_core::mail::Attachment;
use tradocraft_core::{audit, AppError, AppResult, AppState, CurrentUser, Permission};
use tradocraft_crm::Customer;
use tradocraft_documents::{format_date, format_number, render_pdf_with_files};
use utoipa::IntoParams;
use utoipa_axum::router::OpenApiRouter;
use utoipa_axum::routes;
use uuid::Uuid;

use crate::{ensure_can_work, load_detail, ErrorBody, JobDetail};

/// At most this many photos are printed.
pub const MAX_PHOTOS: usize = 6;
/// Photos are embedded as they are (no resizing), so larger ones are counted but not printed.
const MAX_PHOTO_BYTES: usize = 1_500_000;
const MAX_PHOTO_TOTAL: usize = 6_000_000;

#[derive(Serialize)]
pub struct Party {
    pub name: String,
    pub vat_number: String,
    pub street: String,
    pub city_line: String,
    pub country_code: String,
    pub contact: String,
}

#[derive(Serialize)]
pub struct DocTask {
    pub description: String,
    pub done: bool,
    pub done_by: String,
}

#[derive(Serialize)]
pub struct DocPart {
    pub description: String,
    pub quantity: String,
    pub unit: String,
    pub billable: bool,
}

#[derive(Serialize)]
pub struct DocEquipment {
    pub product: String,
    pub serial_number: String,
    /// in_warranty | expired | unknown
    pub warranty_status: String,
    pub warranty_until: String,
}

#[derive(Serialize)]
pub struct DocPhoto {
    pub file: String,
    pub caption: String,
}

#[derive(Serialize)]
pub struct DocSignature {
    pub signer: String,
    pub date: String,
    pub declined: bool,
    pub reason: String,
    /// The image file next to the data, when there is one.
    pub file: Option<String>,
}

#[derive(Serialize)]
pub struct Doc {
    pub language: String,
    pub draft: bool,
    pub number: String,
    pub kind: String,
    pub title: String,
    pub company: Party,
    pub customer: Party,
    pub site: String,
    pub contact_name: String,
    pub contract_number: String,
    pub scheduled_date: String,
    pub started_date: String,
    pub completed_date: String,
    pub technicians: String,
    pub tasks: Vec<DocTask>,
    pub work_time: String,
    pub travel_time: String,
    pub parts: Vec<DocPart>,
    pub equipment: Vec<DocEquipment>,
    pub completion_notes: String,
    pub photos: Vec<DocPhoto>,
    /// Photos of the job that are not printed (too many or too large).
    pub photos_not_shown: usize,
    pub signature: Option<DocSignature>,
}

fn hours(minutes: i64) -> String {
    format!("{}:{:02}", minutes / 60, minutes % 60)
}

fn date_of(d: Option<DateTime<Utc>>) -> String {
    d.map(|d| format_date(d.date_naive())).unwrap_or_default()
}

/// The document data. `photos` are the files that will be placed next to the data (already
/// chosen by the caller); `signature_file` is the name of the signature image, if one is attached.
pub fn document(
    company: &Company,
    customer: &Customer,
    detail: &JobDetail,
    language: &str,
    photos: Vec<DocPhoto>,
    signature_file: Option<String>,
) -> Doc {
    let job = &detail.job;
    Doc {
        language: language.to_string(),
        draft: job.status != "completed",
        number: job.number.clone(),
        kind: job.kind.clone(),
        title: job.title.clone(),
        company: Party {
            name: company.name.clone(),
            vat_number: company.vat_number.clone().unwrap_or_default(),
            street: company.street.clone(),
            city_line: format!("{} {}", company.postal_code, company.city)
                .trim()
                .to_string(),
            country_code: company.country_code.clone(),
            contact: [company.phone.clone(), company.email.clone()]
                .into_iter()
                .flatten()
                .collect::<Vec<_>>()
                .join(" · "),
        },
        customer: Party {
            name: customer.name.clone(),
            vat_number: customer.vat_number.clone().unwrap_or_default(),
            street: customer.street.clone(),
            city_line: format!("{} {}", customer.postal_code, customer.city)
                .trim()
                .to_string(),
            country_code: customer.country_code.clone(),
            contact: String::new(),
        },
        site: [job.site_name.as_str(), job.address.as_str()]
            .iter()
            .filter(|s| !s.trim().is_empty())
            .copied()
            .collect::<Vec<_>>()
            .join(", "),
        contact_name: job.contact_name.clone().unwrap_or_default(),
        contract_number: job.contract_number.clone().unwrap_or_default(),
        scheduled_date: date_of(job.scheduled_start),
        started_date: date_of(job.started_at),
        completed_date: date_of(job.completed_at),
        technicians: job
            .technicians
            .iter()
            .map(|t| t.display_name.clone())
            .collect::<Vec<_>>()
            .join(", "),
        tasks: detail
            .tasks
            .iter()
            .map(|t| DocTask {
                description: t.description.clone(),
                done: t.done,
                done_by: t.done_by_name.clone().unwrap_or_default(),
            })
            .collect(),
        work_time: hours(detail.work_minutes),
        travel_time: hours(detail.travel_minutes),
        parts: detail
            .parts
            .iter()
            .map(|p| DocPart {
                description: p.description.clone(),
                quantity: format_number(p.quantity),
                unit: p.unit.clone(),
                billable: p.billable,
            })
            .collect(),
        equipment: detail
            .equipment
            .iter()
            .map(|e| DocEquipment {
                product: format!("{} {}", e.product_code, e.product_name),
                serial_number: e.serial_number.clone(),
                warranty_status: e.warranty_status.clone(),
                warranty_until: e.warranty_until.map(format_date).unwrap_or_default(),
            })
            .collect(),
        completion_notes: job.completion_notes.clone(),
        photos_not_shown: detail.photos.len().saturating_sub(photos.len()),
        photos,
        signature: detail.signature.as_ref().map(|s| DocSignature {
            signer: s.signer_name.clone(),
            date: format_date(s.signed_at.date_naive()),
            declined: s.declined,
            reason: s.decline_reason.clone(),
            file: signature_file,
        }),
    }
}

/// Subject and body of the e-mail that carries the report.
pub fn report_mail(
    language: &str,
    company: &str,
    customer: &str,
    number: &str,
) -> (String, String) {
    match language {
        "nl" => (
            format!("Werkbon {number}"),
            format!("Geachte {customer},\n\nIn bijlage vindt u de werkbon {number} van onze interventie. Hebt u vragen, laat het ons dan weten.\n\nMet vriendelijke groeten\n{company}\n"),
        ),
        "fr" => (
            format!("Rapport d'intervention {number}"),
            format!("Bonjour {customer},\n\nVeuillez trouver ci-joint le rapport d'intervention {number}. Pour toute question, n'hésitez pas à nous contacter.\n\nCordialement\n{company}\n"),
        ),
        "de" => (
            format!("Servicebericht {number}"),
            format!("Guten Tag {customer},\n\nanbei erhalten Sie den Servicebericht {number} zu unserem Einsatz. Bei Fragen melden Sie sich gerne bei uns.\n\nMit freundlichen Grüßen\n{company}\n"),
        ),
        "es" => (
            format!("Informe de servicio {number}"),
            format!("Estimado cliente ({customer}),\n\nAdjuntamos el informe de servicio {number} de nuestra intervención. Si tiene alguna pregunta, póngase en contacto con nosotros.\n\nAtentamente\n{company}\n"),
        ),
        _ => (
            format!("Service report {number}"),
            format!("Dear {customer},\n\nPlease find attached service report {number} for our visit. If you have any questions, let us know.\n\nKind regards\n{company}\n"),
        ),
    }
}

struct Rendered {
    pdf: Vec<u8>,
    filename: String,
    language: String,
    customer: Customer,
    recipient: Option<String>,
}

/// Who gets the report: the job's contact when it has an address, otherwise the customer's main
/// address.
async fn recipient_of(
    conn: &mut PgConnection,
    detail: &JobDetail,
    customer: &Customer,
) -> AppResult<(Option<String>, String)> {
    if let Some(c) = detail.job.contact_id {
        let contact = tradocraft_crm::contacts::get_contact(conn, c).await?;
        if let Some(address) = contact.primary_email() {
            return Ok((
                Some(address.to_string()),
                contact.effective_language.clone(),
            ));
        }
        let lang = contact.effective_language.clone();
        let fallback = customer.email.clone().filter(|e| e.contains('@'));
        return Ok((fallback, lang));
    }
    Ok((
        customer.email.clone().filter(|e| e.contains('@')),
        customer.language.clone(),
    ))
}

async fn render(
    state: &AppState,
    conn: &mut PgConnection,
    user: &CurrentUser,
    id: Uuid,
    language: Option<&str>,
) -> AppResult<Rendered> {
    let detail = load_detail(conn, user, id).await?;
    let customer =
        tradocraft_crm::get_customer(&mut *conn, user.company_id, detail.job.customer_id).await?;
    let (recipient, default_language) = recipient_of(conn, &detail, &customer).await?;
    let language = match language {
        Some(l) if tradocraft_core::is_language(l) => l.to_string(),
        Some(_) => return Err(AppError::Validation("unknown language".into())),
        None if tradocraft_core::is_language(&default_language) => default_language,
        None => "en".to_string(),
    };
    let company = get_company(&state.db, user.company_id).await?;

    // Pictures next to the data: the signature, and up to six photos Typst can read and that are
    // small enough to embed as they are.
    let mut images: Vec<(String, Vec<u8>)> = Vec::new();
    let mut signature_file = None;
    if detail.signature.as_ref().is_some_and(|s| s.has_image) {
        let file: Option<Uuid> =
            sqlx::query_scalar("SELECT file_id FROM field.job_signatures WHERE job_id = $1")
                .bind(id)
                .fetch_one(&mut *conn)
                .await?;
        if let Some(f) = file {
            let (_, data) = files::load(conn, user.company_id, f).await?;
            images.push(("signature.png".into(), data));
            signature_file = Some("signature.png".to_string());
        }
    }
    let mut photos = Vec::new();
    let mut total = 0;
    for p in &detail.photos {
        if photos.len() >= MAX_PHOTOS {
            break;
        }
        let (ct, data) = files::load(conn, user.company_id, p.id).await?;
        let ext = match ct.as_str() {
            "image/jpeg" => "jpg",
            "image/png" => "png",
            _ => continue,
        };
        if data.len() > MAX_PHOTO_BYTES || total + data.len() > MAX_PHOTO_TOTAL {
            continue;
        }
        total += data.len();
        let name = format!("photo{}.{ext}", photos.len() + 1);
        images.push((name.clone(), data));
        photos.push(DocPhoto {
            file: name,
            caption: p.caption.clone(),
        });
    }

    let doc = document(
        &company,
        &customer,
        &detail,
        &language,
        photos,
        signature_file,
    );
    let pdf = match render_pdf_with_files(&state.documents, "service_report", &doc, &images).await {
        Ok(pdf) => pdf,
        Err(e) if !images.is_empty() => {
            // A picture Typst cannot decode must not make the report impossible.
            tracing::warn!(error = ?e, "service report with pictures failed; rendering without");
            let mut bare = document(&company, &customer, &detail, &language, vec![], None);
            bare.photos_not_shown = detail.photos.len();
            render_pdf_with_files(&state.documents, "service_report", &bare, &[]).await?
        }
        Err(e) => return Err(e.into()),
    };
    Ok(Rendered {
        pdf,
        filename: format!("{}-service-report.pdf", detail.job.number),
        language,
        customer,
        recipient,
    })
}

#[derive(Debug, Deserialize, IntoParams)]
pub struct ReportParams {
    /// nl, fr, en, de or es. Default: the language of the contact, else of the customer.
    pub language: Option<String>,
}

/// The service report of a job as PDF (a watermark marks it as draft until the job is completed).
#[utoipa::path(get, path = "/field/jobs/{id}/report", tag = "field", operation_id = "get_job_report",
    params(("id" = Uuid, Path), ReportParams),
    responses((status = 200, content_type = "application/pdf", body = Vec<u8>), (status = 404, body = ErrorBody)))]
async fn get_report(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
    Query(p): Query<ReportParams>,
) -> AppResult<Response> {
    user.require(Permission::FieldRead)?;
    let mut conn = state.db.acquire().await?;
    let r = render(&state, &mut conn, &user, id, p.language.as_deref()).await?;
    Ok((
        [
            (header::CONTENT_TYPE, "application/pdf".to_string()),
            (
                header::CONTENT_DISPOSITION,
                format!("inline; filename=\"{}\"", r.filename),
            ),
        ],
        r.pdf,
    )
        .into_response())
}

/// E-mails the service report of a completed job to its contact (or the customer's main address)
/// and records when and to whom. Sending again is allowed. Refused (409) when there is no
/// address or the job is not completed.
#[utoipa::path(post, path = "/field/jobs/{id}/report/send", tag = "field", operation_id = "send_job_report",
    params(("id" = Uuid, Path)),
    responses((status = 200, body = JobDetail), (status = 409, body = ErrorBody)))]
async fn send_report(
    State(state): State<AppState>,
    user: CurrentUser,
    Path(id): Path<Uuid>,
) -> AppResult<Json<JobDetail>> {
    let mut tx = state.db.begin().await?;
    ensure_can_work(&mut tx, &user, id).await?;
    let status: String =
        sqlx::query_scalar("SELECT status FROM field.jobs WHERE id = $1 AND company_id = $2")
            .bind(id)
            .bind(user.company_id)
            .fetch_optional(&mut *tx)
            .await?
            .ok_or(AppError::NotFound("job"))?;
    if status != "completed" {
        return Err(AppError::Conflict(
            "complete the job before sending the service report".into(),
        ));
    }
    let r = render(&state, &mut tx, &user, id, None).await?;
    let to = r.recipient.clone().ok_or_else(|| {
        AppError::Conflict(
            "there is no e-mail address to send the report to; add an address to the contact or the customer first"
                .into(),
        )
    })?;
    let company = get_company(&state.db, user.company_id).await?;
    let number = r
        .filename
        .trim_end_matches("-service-report.pdf")
        .to_string();
    let (subject, body) = report_mail(&r.language, &company.name, &r.customer.name, &number);
    tradocraft_core::mail::enqueue_with_attachment(
        &mut tx,
        user.company_id,
        &to,
        &subject,
        &body,
        Attachment {
            filename: &r.filename,
            content_type: "application/pdf",
            data: &r.pdf,
        },
    )
    .await?;
    sqlx::query("UPDATE field.jobs SET report_sent_at = now(), report_sent_to = $2, updated_at = now() WHERE id = $1")
        .bind(id)
        .bind(&to)
        .execute(&mut *tx)
        .await?;
    audit::record(
        &mut tx,
        &user,
        "job",
        id,
        "report_sent",
        serde_json::json!({ "to": to }),
    )
    .await?;
    let d = load_detail(&mut tx, &user, id).await?;
    tx.commit().await?;
    Ok(Json(d))
}

pub fn router() -> OpenApiRouter<AppState> {
    OpenApiRouter::new()
        .routes(routes!(get_report))
        .routes(routes!(send_report))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn internal_instructions_and_log_notes_never_reach_the_document() {
        use crate::{Job, Task, WorkLog};
        let job = Job {
            id: Uuid::nil(),
            number: "J2026-00001".into(),
            kind: "repair".into(),
            status: "completed".into(),
            priority: "normal".into(),
            title: "Pump".into(),
            instructions: "SECRET-INSTRUCTIONS".into(),
            customer_id: Uuid::nil(),
            customer_name: "Alpha".into(),
            contact_id: None,
            contact_name: None,
            ticket_id: None,
            repair_id: None,
            site_name: String::new(),
            street: "Street 1".into(),
            postal_code: "2000".into(),
            city: "Antwerp".into(),
            country_code: "BE".into(),
            address: "Street 1, 2000 Antwerp".into(),
            latitude: None,
            longitude: None,
            maps_url: None,
            scheduled_start: None,
            scheduled_end: None,
            started_at: None,
            completed_at: None,
            completion_notes: "Replaced the seals.".into(),
            technicians: vec![],
            tasks_total: 1,
            tasks_done: 1,
            contract_id: None,
            contract_number: None,
            due_date: None,
            report_sent_at: None,
            report_sent_to: String::new(),
        };
        let now = Utc::now();
        let detail = JobDetail {
            job,
            contact_phones: vec![],
            tasks: vec![Task {
                id: Uuid::nil(),
                position: 1,
                description: "Replace seals".into(),
                done: true,
                done_by_name: None,
                done_at: None,
            }],
            work_logs: vec![WorkLog {
                id: Uuid::nil(),
                user_id: Uuid::nil(),
                user_name: "Tom".into(),
                kind: "work".into(),
                started_at: now,
                ended_at: now,
                minutes: 90,
                notes: "SECRET-LOG-NOTE".into(),
            }],
            photos: vec![],
            equipment: vec![],
            parts: vec![],
            signature: None,
            work_minutes: 90,
            travel_minutes: 0,
        };
        let company = Company {
            id: Uuid::nil(),
            name: "Demo".into(),
            vat_number: None,
            street: String::new(),
            postal_code: String::new(),
            city: String::new(),
            country_code: "BE".into(),
            currency: "EUR".into(),
            email: None,
            phone: None,
            iban: None,
            default_language: "nl".into(),
            is_primary: true,
        };
        let customer = Customer {
            id: Uuid::nil(),
            version: 1,
            code: "C1".into(),
            name: "Alpha".into(),
            vat_number: None,
            vat_regime: "domestic".to_string(),
            email: None,
            phone: None,
            street: "Street 1".into(),
            postal_code: "2000".into(),
            city: "Antwerp".into(),
            country_code: "BE".into(),
            language: "nl".into(),
            active: true,
            price_zone_id: None,
            price_zone_code: None,
            discount_percent: None,
            payment_terms_days: None,
        };
        let doc = document(&company, &customer, &detail, "nl", vec![], None);
        let json = serde_json::to_string(&doc).unwrap();
        assert!(!json.contains("SECRET"), "{json}");
        assert!(json.contains("Replaced the seals.") && json.contains("1:30"));
    }

    #[test]
    fn minutes_are_shown_as_hours_and_minutes() {
        assert_eq!(hours(0), "0:00");
        assert_eq!(hours(75), "1:15");
        assert_eq!(hours(600), "10:00");
    }

    #[test]
    fn the_mail_is_written_in_the_language_of_the_customer() {
        for (lang, word) in [
            ("nl", "Werkbon"),
            ("fr", "Rapport"),
            ("de", "Servicebericht"),
            ("es", "Informe"),
            ("en", "Service report"),
        ] {
            let (subject, body) = report_mail(lang, "Acme", "Alpha", "J2026-00001");
            assert!(subject.starts_with(word), "{lang}");
            assert!(body.contains("J2026-00001") && body.contains("Acme"));
        }
    }
}
