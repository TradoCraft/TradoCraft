//! The file formats and their detection from the bytes.

use std::io::{Cursor, Read};

use axum::http::{header, HeaderMap, HeaderValue};
use zip::ZipArchive;

/// The `mimetype` an OpenDocument spreadsheet carries as the first entry of its archive.
pub const ODS_MIMETYPE: &str = "application/vnd.oasis.opendocument.spreadsheet";

// `type: string, format: binary` in the OpenAPI document: a string schema alone would make a
// generated client send or decode the body as text, which corrupts a spreadsheet. Documentation
// only: the handlers take and return bytes.
/// The raw bytes of a file.
#[derive(utoipa::ToSchema)]
#[schema(value_type = String, format = Binary)]
pub struct BinaryFile(#[allow(dead_code)] Vec<u8>);

/// A supported file format.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Format {
    Csv,
    Xlsx,
    Ods,
}

impl Format {
    /// File name extension, without the dot.
    pub fn extension(self) -> &'static str {
        match self {
            Format::Csv => "csv",
            Format::Xlsx => "xlsx",
            Format::Ods => "ods",
        }
    }

    /// The value of the `Content-Type` header of a download.
    pub fn content_type(self) -> &'static str {
        match self {
            Format::Csv => "text/csv; charset=utf-8",
            Format::Xlsx => "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            Format::Ods => ODS_MIMETYPE,
        }
    }

    /// The value the audit event of an import carries as `data.source`.
    pub fn audit_source(self) -> &'static str {
        match self {
            Format::Csv => "csv_import",
            Format::Xlsx => "xlsx_import",
            Format::Ods => "ods_import",
        }
    }
}

/// Headers of a download of `body` named `{stem}.{extension}` (like [`crate::csv_io::download`]).
pub fn download(format: Format, stem: &str, body: Vec<u8>) -> (HeaderMap, Vec<u8>) {
    let mut headers = HeaderMap::new();
    headers.insert(
        header::CONTENT_TYPE,
        HeaderValue::from_static(format.content_type()),
    );
    headers.insert(
        header::CONTENT_DISPOSITION,
        HeaderValue::from_str(&format!(
            "attachment; filename=\"{stem}.{}\"",
            format.extension()
        ))
        .unwrap_or_else(|_| HeaderValue::from_static("attachment")),
    );
    (headers, body)
}

const OLE2_MAGIC: [u8; 4] = [0xD0, 0xCF, 0x11, 0xE0];

/// Finds the format from the content, never from a file name: a zip archive whose `mimetype` is
/// the OpenDocument spreadsheet type is ODS, one with `xl/workbook.xml` is XLSX (`.xlsm` too).
/// Any other zip archive, the legacy binary formats (`.xls`, magic `D0 CF 11 E0`) and `.xlsb`
/// (`xl/workbook.bin`) are refused with one message. Everything else is read as CSV.
pub fn detect(bytes: &[u8]) -> Result<Format, String> {
    if bytes.starts_with(&OLE2_MAGIC) {
        return Err(
            "this is a legacy binary Office file (.xls); save it as .xlsx, .ods or CSV \
             and upload that"
                .into(),
        );
    }
    if !(bytes.starts_with(b"PK\x03\x04") || bytes.starts_with(b"PK\x05\x06")) {
        return Ok(Format::Csv);
    }
    let mut zip = ZipArchive::new(Cursor::new(bytes))
        .map_err(|e| format!("the file is a damaged or unsupported zip archive ({e})"))?;
    if let Ok(entry) = zip.by_name("mimetype") {
        let mut mime = String::new();
        // Read a little more than the type is long: never the whole entry.
        if entry
            .take(ODS_MIMETYPE.len() as u64 + 1)
            .read_to_string(&mut mime)
            .is_ok()
            && mime.trim() == ODS_MIMETYPE
        {
            return Ok(Format::Ods);
        }
    }
    if zip.by_name("xl/workbook.xml").is_ok() {
        return Ok(Format::Xlsx);
    }
    if zip.by_name("xl/workbook.bin").is_ok() {
        return Err(
            "this is a binary Excel workbook (.xlsb); save it as .xlsx, .ods or CSV \
             and upload that"
                .into(),
        );
    }
    Err("this zip archive is not a spreadsheet; upload an .xlsx, .ods or CSV file".into())
}
