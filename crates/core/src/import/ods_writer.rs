//! A small OpenDocument spreadsheet writer: one sheet of typed cells on the `zip` crate.

use std::io::{Cursor, Write};

use zip::write::SimpleFileOptions;
use zip::{CompressionMethod, ZipWriter};

use crate::csv_io::format_decimal;
use crate::error::{AppError, AppResult};
use crate::import::cell::exact_f64;
use crate::import::format::ODS_MIMETYPE;
use crate::import::writer::{check_sheet_name, name_record};
use crate::import::CellValue;

const MANIFEST: &str = concat!(
    r#"<?xml version="1.0" encoding="UTF-8"?>"#,
    r#"<manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" manifest:version="1.2">"#,
    r#"<manifest:file-entry manifest:full-path="/" manifest:version="1.2" manifest:media-type="application/vnd.oasis.opendocument.spreadsheet"/>"#,
    r#"<manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>"#,
    r#"</manifest:manifest>"#
);

const CONTENT_START: &str = concat!(
    r#"<?xml version="1.0" encoding="UTF-8"?>"#,
    r#"<office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" "#,
    r#"xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" "#,
    r#"xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" "#,
    r#"xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" "#,
    r#"xmlns:number="urn:oasis:names:tc:opendocument:xmlns:datastyle:1.0" office:version="1.2">"#,
    r#"<office:automatic-styles>"#,
    r#"<number:date-style style:name="N-date">"#,
    r#"<number:year number:style="long"/><number:text>-</number:text><number:month number:style="long"/><number:text>-</number:text><number:day number:style="long"/>"#,
    r#"</number:date-style>"#,
    r#"<number:date-style style:name="N-datetime">"#,
    r#"<number:year number:style="long"/><number:text>-</number:text><number:month number:style="long"/><number:text>-</number:text><number:day number:style="long"/>"#,
    r#"<number:text> </number:text><number:hours number:style="long"/><number:text>:</number:text><number:minutes number:style="long"/><number:text>:</number:text><number:seconds number:style="long"/>"#,
    r#"</number:date-style>"#,
    r#"<number:boolean-style style:name="N-bool"><number:boolean/></number:boolean-style>"#,
    r#"<style:style style:name="ce-bool" style:family="table-cell" style:data-style-name="N-bool"/>"#,
    r#"<style:style style:name="ce-date" style:family="table-cell" style:data-style-name="N-date"/>"#,
    r#"<style:style style:name="ce-datetime" style:family="table-cell" style:data-style-name="N-datetime"/>"#,
    r#"</office:automatic-styles>"#,
    r#"<office:body><office:spreadsheet>"#
);

const CONTENT_END: &str = "</office:spreadsheet></office:body></office:document-content>";

/// Whether XML 1.0 can carry the character at all.
fn xml_char(c: char) -> bool {
    matches!(c, '\t' | '\n' | '\r' | '\u{20}'..='\u{D7FF}' | '\u{E000}'..='\u{FFFD}' | '\u{10000}'..)
}

/// Escapes a value for an XML attribute.
fn attr(s: &str) -> AppResult<String> {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '"' => out.push_str("&quot;"),
            '\'' => out.push_str("&apos;"),
            '\t' => out.push_str("&#9;"),
            '\n' => out.push_str("&#10;"),
            '\r' => out.push_str("&#13;"),
            c if xml_char(c) => out.push(c),
            _ => return Err(bad_char(c)),
        }
    }
    Ok(out)
}

fn bad_char(c: char) -> AppError {
    AppError::Validation(format!(
        "the text contains the character U+{:04X}, which an ODS file cannot hold",
        c as u32
    ))
}

/// The content of one `text:p`. Spaces survive: a run of spaces at the start or end of the text,
/// next to a tab or line break, or longer than one, is written with `text:s` (XML and ODF would
/// otherwise collapse or drop them); tabs and line breaks have their own elements.
fn paragraph(s: &str) -> AppResult<String> {
    let chars: Vec<char> = s.chars().collect();
    let mut out = String::with_capacity(s.len() + 16);
    let mut i = 0;
    while i < chars.len() {
        let c = chars[i];
        match c {
            ' ' => {
                let mut j = i;
                while j < chars.len() && chars[j] == ' ' {
                    j += 1;
                }
                let run = j - i;
                let breaks = |c: Option<&char>| matches!(c, None | Some('\n' | '\t'));
                let edge =
                    breaks(i.checked_sub(1).and_then(|k| chars.get(k))) || breaks(chars.get(j));
                if edge {
                    out.push_str(&format!(r#"<text:s text:c="{run}"/>"#));
                } else if run == 1 {
                    out.push(' ');
                } else {
                    out.push_str(&format!(r#" <text:s text:c="{}"/>"#, run - 1));
                }
                i = j;
                continue;
            }
            '\n' => out.push_str("<text:line-break/>"),
            '\t' => out.push_str("<text:tab/>"),
            '\r' => out.push_str("&#13;"),
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            c if xml_char(c) => out.push(c),
            _ => return Err(bad_char(c)),
        }
        i += 1;
    }
    Ok(out)
}

fn cell(out: &mut String, value: &CellValue) -> AppResult<()> {
    match value {
        CellValue::Empty => out.push_str("<table:table-cell/>"),
        CellValue::Text(s) => {
            out.push_str(&format!(
                r#"<table:table-cell office:value-type="string"><text:p>{}</text:p></table:table-cell>"#,
                paragraph(s)?
            ));
        }
        CellValue::Number(d) => match exact_f64(*d) {
            Some(_) => {
                let v = format_decimal(*d);
                out.push_str(&format!(
                    r#"<table:table-cell office:value-type="float" office:value="{v}"><text:p>{v}</text:p></table:table-cell>"#
                ));
            }
            // More digits than a spreadsheet's double holds: keep them as text.
            None => cell(out, &CellValue::Text(format_decimal(*d)))?,
        },
        CellValue::Bool(b) => {
            let shown = if *b { "TRUE" } else { "FALSE" };
            out.push_str(&format!(
                r#"<table:table-cell table:style-name="ce-bool" office:value-type="boolean" office:boolean-value="{b}"><text:p>{shown}</text:p></table:table-cell>"#
            ));
        }
        CellValue::Date(d) => {
            let v = d.format("%Y-%m-%d");
            out.push_str(&format!(
                r#"<table:table-cell table:style-name="ce-date" office:value-type="date" office:date-value="{v}"><text:p>{v}</text:p></table:table-cell>"#
            ));
        }
        CellValue::DateTime(t) => {
            let v = t.format("%Y-%m-%dT%H:%M:%S%.f");
            let shown = t.format("%Y-%m-%d %H:%M:%S");
            out.push_str(&format!(
                r#"<table:table-cell table:style-name="ce-datetime" office:value-type="date" office:date-value="{v}"><text:p>{shown}</text:p></table:table-cell>"#
            ));
        }
    }
    Ok(())
}

pub(crate) fn write_ods(
    sheet_name: &str,
    header: &[&str],
    rows: impl IntoIterator<Item = Vec<CellValue>>,
) -> AppResult<Vec<u8>> {
    check_sheet_name(sheet_name)?;
    let mut content = String::from(CONTENT_START);
    content.push_str(&format!(
        r#"<table:table table:name="{}">"#,
        attr(sheet_name)?
    ));
    content.push_str("<table:table-row>");
    for h in header {
        cell(&mut content, &CellValue::text(*h))?;
    }
    content.push_str("</table:table-row>");
    for (r, row) in rows.into_iter().enumerate() {
        content.push_str("<table:table-row>");
        for (c, value) in row.iter().enumerate() {
            let column = header.get(c).copied().unwrap_or_default();
            cell(&mut content, value).map_err(|e| name_record(e, r + 2, row.first(), column))?;
        }
        content.push_str("</table:table-row>");
    }
    content.push_str("</table:table>");
    content.push_str(CONTENT_END);

    let zip_err = |e: zip::result::ZipError| AppError::Internal(e.into());
    let io_err = |e: std::io::Error| AppError::Internal(e.into());
    let mut zip = ZipWriter::new(Cursor::new(Vec::new()));
    // The type comes first and is stored, so a program can find it without unpacking anything.
    let stored = SimpleFileOptions::default().compression_method(CompressionMethod::Stored);
    let deflated = SimpleFileOptions::default().compression_method(CompressionMethod::Deflated);
    zip.start_file("mimetype", stored).map_err(zip_err)?;
    zip.write_all(ODS_MIMETYPE.as_bytes()).map_err(io_err)?;
    zip.start_file("META-INF/manifest.xml", deflated)
        .map_err(zip_err)?;
    zip.write_all(MANIFEST.as_bytes()).map_err(io_err)?;
    zip.start_file("content.xml", deflated).map_err(zip_err)?;
    zip.write_all(content.as_bytes()).map_err(io_err)?;
    Ok(zip.finish().map_err(zip_err)?.into_inner())
}
