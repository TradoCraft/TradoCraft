//! Price list document (ADR 0069): the data handed to `templates/price_list.typ` and the Excel
//! rendering of the same data. Every value is already formatted and every label already chosen
//! here, so the template only lays out and the two formats cannot drift apart.

use rust_xlsxwriter::{Format, Workbook, XlsxError};
use serde::Serialize;

/// The labels of a price list in one language.
#[derive(Debug, Clone, Serialize)]
pub struct PriceListLabels {
    pub code: &'static str,
    pub description: &'static str,
    pub unit: &'static str,
    pub price: &'static str,
    pub on_request: &'static str,
    pub net: &'static str,
    pub indicative: &'static str,
    pub valid_from: &'static str,
    pub zone: &'static str,
    pub page: &'static str,
}

/// Labels for `language` (nl, fr, en, de, es); anything else gets English.
pub fn labels(language: &str) -> PriceListLabels {
    match language {
        "nl" => PriceListLabels {
            code: "Code",
            description: "Omschrijving",
            unit: "Eenheid",
            price: "Prijs",
            on_request: "OP AANVRAAG",
            net: "NETTO",
            indicative: "Indicatieve prijs, nog te bevestigen",
            valid_from: "Geldig vanaf",
            zone: "Prijszone",
            page: "Pagina",
        },
        "fr" => PriceListLabels {
            code: "Code",
            description: "Description",
            unit: "Unité",
            price: "Prix",
            on_request: "SUR DEMANDE",
            net: "NET",
            indicative: "Prix indicatif, à confirmer",
            valid_from: "Valable à partir du",
            zone: "Zone de prix",
            page: "Page",
        },
        "de" => PriceListLabels {
            code: "Artikel",
            description: "Beschreibung",
            unit: "Einheit",
            price: "Preis",
            on_request: "AUF ANFRAGE",
            net: "NETTO",
            indicative: "Richtpreis, noch zu bestätigen",
            valid_from: "Gültig ab",
            zone: "Preiszone",
            page: "Seite",
        },
        "es" => PriceListLabels {
            code: "Código",
            description: "Descripción",
            unit: "Unidad",
            price: "Precio",
            on_request: "BAJO PEDIDO",
            net: "NETO",
            indicative: "Precio orientativo, por confirmar",
            valid_from: "Válido desde",
            zone: "Zona de precios",
            page: "Página",
        },
        _ => PriceListLabels {
            code: "Code",
            description: "Description",
            unit: "Unit",
            price: "Price",
            on_request: "ON REQUEST",
            net: "NET",
            indicative: "Indicative price, to be confirmed",
            valid_from: "Valid from",
            zone: "Price zone",
            page: "Page",
        },
    }
}

#[derive(Debug, Clone, Serialize)]
pub struct PriceListRow {
    pub code: String,
    pub description: String,
    pub unit: String,
    /// Formatted price; empty when the row is `on_request`.
    pub price: String,
    pub on_request: bool,
    pub net: bool,
    pub indicative: bool,
}

/// A titled group with its own rows. Sections come in document order (a group before its
/// sub-groups); `level` is 0 for a chapter.
#[derive(Debug, Clone, Serialize)]
pub struct PriceListSection {
    pub level: usize,
    /// Empty when `show_title` is false.
    pub title: String,
    /// False for an untitled group: no title block, only `gap_mm` of space before its rows.
    pub show_title: bool,
    pub gap_mm: f64,
    pub page_break: bool,
    pub rows: Vec<PriceListRow>,
}

#[derive(Debug, Clone, Serialize)]
pub struct PriceListDoc {
    pub language: String,
    pub title: String,
    pub company_name: String,
    pub zone_name: String,
    pub valid_from: String,
    /// Currency symbol or code printed before every price.
    pub currency: String,
    pub footer_text: String,
    /// `#rrggbb`
    pub accent_color: String,
    pub show_unit: bool,
    pub has_indicative: bool,
    /// Name of the logo image next to `data.json` (PDF only); null prints no logo.
    pub logo_file: Option<String>,
    pub labels: PriceListLabels,
    pub sections: Vec<PriceListSection>,
}

/// Renders the price list as PDF through `templates/price_list.typ`. `files` are the images
/// next to `data.json`, i.e. the logo named by `doc.logo_file`.
pub async fn render_pdf(
    config: &tradocraft_core::DocumentConfig,
    doc: &PriceListDoc,
    files: &[(String, Vec<u8>)],
) -> anyhow::Result<Vec<u8>> {
    crate::render_pdf_with_files(config, "price_list", doc, files).await
}

/// A valid Excel sheet name from a title: at most 31 characters, none of `[]:*?/\\`, and no
/// apostrophe at either end. Empty when nothing usable is left (the default name is kept then).
fn sheet_name(title: &str) -> String {
    let cleaned: String = title
        .chars()
        .filter(|c| !"[]:*?/\\".contains(*c))
        .take(31)
        .collect();
    cleaned.trim().trim_matches('\'').trim().to_string()
}

/// Renders the price list as an Excel workbook: one sheet, group titles as rows.
pub fn render_xlsx(doc: &PriceListDoc) -> Result<Vec<u8>, XlsxError> {
    let mut wb = Workbook::new();
    let ws = wb.add_worksheet();
    let sheet = sheet_name(&doc.title);
    if !sheet.is_empty() {
        ws.set_name(&sheet)?;
    }
    let bold = Format::new().set_bold();
    let right = Format::new().set_align(rust_xlsxwriter::FormatAlign::Right);
    let mut row: u32 = 0;
    ws.write_string_with_format(row, 0, &doc.title, &bold)?;
    row += 1;
    ws.write_string(
        row,
        0,
        format!(
            "{}: {} / {}: {}",
            doc.labels.zone, doc.zone_name, doc.labels.valid_from, doc.valid_from
        ),
    )?;
    row += 2;
    let (c_code, c_desc, c_unit, c_price) = (0u16, 1u16, 2u16, 3u16);
    ws.write_string_with_format(row, c_code, doc.labels.code, &bold)?;
    ws.write_string_with_format(row, c_desc, doc.labels.description, &bold)?;
    if doc.show_unit {
        ws.write_string_with_format(row, c_unit, doc.labels.unit, &bold)?;
    }
    ws.write_string_with_format(row, c_price, doc.labels.price, &bold)?;
    ws.set_freeze_panes(row + 1, 0)?;
    row += 1;
    for section in &doc.sections {
        if !section.title.is_empty() {
            ws.write_string_with_format(row, c_code, &section.title, &bold)?;
            row += 1;
        }
        for r in &section.rows {
            ws.write_string(row, c_code, &r.code)?;
            ws.write_string(row, c_desc, &r.description)?;
            if doc.show_unit {
                ws.write_string(row, c_unit, &r.unit)?;
            }
            let price = if r.on_request {
                doc.labels.on_request.to_string()
            } else {
                let mut p = format!("{} {}", doc.currency, r.price);
                if r.net {
                    p.push_str(&format!(" {}", doc.labels.net));
                }
                if r.indicative {
                    p.push('*');
                }
                p
            };
            ws.write_string_with_format(row, c_price, price, &right)?;
            row += 1;
        }
    }
    if doc.has_indicative {
        row += 1;
        ws.write_string(row, c_code, format!("* {}", doc.labels.indicative))?;
    }
    ws.set_column_width(c_code, 18)?;
    ws.set_column_width(c_desc, 70)?;
    ws.set_column_width(c_unit, 10)?;
    ws.set_column_width(c_price, 22)?;
    wb.save_to_buffer()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn doc() -> PriceListDoc {
        PriceListDoc {
            language: "nl".into(),
            title: "Prijslijst".into(),
            company_name: "Acme".into(),
            zone_name: "Zone 1".into(),
            valid_from: "01/01/2027".into(),
            currency: "€".into(),
            footer_text: String::new(),
            accent_color: "#1f4e79".into(),
            show_unit: true,
            has_indicative: true,
            logo_file: None,
            labels: labels("nl"),
            sections: vec![PriceListSection {
                level: 0,
                title: "Klokken".into(),
                show_title: true,
                gap_mm: 0.0,
                page_break: false,
                rows: vec![
                    PriceListRow {
                        code: "A1".into(),
                        description: "Wijzer".into(),
                        unit: "st".into(),
                        price: "12,50".into(),
                        on_request: false,
                        net: false,
                        indicative: true,
                    },
                    PriceListRow {
                        code: "A2".into(),
                        description: "Motor".into(),
                        unit: "st".into(),
                        price: String::new(),
                        on_request: true,
                        net: false,
                        indicative: false,
                    },
                ],
            }],
        }
    }

    #[test]
    fn unknown_language_gets_english_labels() {
        assert_eq!(labels("xx").on_request, "ON REQUEST");
        assert_eq!(labels("nl").on_request, "OP AANVRAAG");
    }

    #[test]
    fn xlsx_is_a_zip_with_content() {
        let bytes = render_xlsx(&doc()).unwrap();
        assert_eq!(&bytes[..2], b"PK");
        assert!(bytes.len() > 1000);
    }

    #[test]
    fn sheet_names_never_start_or_end_with_an_apostrophe() {
        assert_eq!(sheet_name("'Prijslijst'"), "Prijslijst");
        assert_eq!(sheet_name("''Rock 'n' roll''"), "Rock 'n' roll");
        assert_eq!(sheet_name("'[x]'"), "x");
        assert_eq!(sheet_name("'''"), "");
        let mut d = doc();
        d.title = "'Prijslijst 2027'".into();
        assert!(render_xlsx(&d).is_ok());
        d.title = "''".into();
        assert!(render_xlsx(&d).is_ok());
    }
}
