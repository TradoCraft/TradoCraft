//! Writing a table of typed cells as CSV, XLSX or ODS.

use chrono::{Datelike, NaiveDate, NaiveDateTime, Timelike};
use rust_xlsxwriter::{ExcelDateTime, Format as XlsxFormat, Workbook};

use crate::csv_io::write_csv;
use crate::error::{AppError, AppResult};
use crate::import::cell::exact_f64;
use crate::import::{ods_writer, CellValue, Format};

/// Checks a sheet name for both spreadsheet formats: not empty, no `[ ] : * ? / \`, no apostrophe
/// at either end. (XLSX also limits it to 31 characters.)
pub(crate) fn check_sheet_name(name: &str) -> AppResult<()> {
    let bad = name.is_empty()
        || name
            .chars()
            .any(|c| "[]:*?/\\".contains(c) || c.is_control())
        || name.starts_with('\'')
        || name.ends_with('\'')
        || name.chars().count() > 31;
    if bad {
        return Err(AppError::Validation(format!(
            "{name:?} is not a valid sheet name"
        )));
    }
    Ok(())
}

/// Writes `header` and `rows` as one file of `format`. The sheet (XLSX, ODS) is named
/// `sheet_name`; CSV ignores it.
///
/// Text is always stored as text: a code `00123` keeps its zeros and a value starting with `=`
/// is not a formula (CSV gets the apostrophe protection of ADR 0029, the spreadsheet formats need
/// none). Numbers are number cells, booleans boolean cells, dates date cells with a date format. A
/// number that a spreadsheet's binary double cannot hold exactly (more than about 15 digits) is
/// written as text instead, never rounded. Empty cells are left out.
pub fn write(
    format: Format,
    sheet_name: &str,
    header: &[&str],
    rows: impl IntoIterator<Item = Vec<CellValue>>,
) -> AppResult<Vec<u8>> {
    match format {
        Format::Csv => Ok(write_csv(
            header,
            rows.into_iter()
                .map(|r| r.iter().map(|c| c.render().unwrap_or_default()).collect()),
        )
        .into_bytes()),
        Format::Xlsx => write_xlsx(sheet_name, header, rows),
        Format::Ods => ods_writer::write_ods(sheet_name, header, rows),
    }
}

fn xlsx_error(e: rust_xlsxwriter::XlsxError) -> AppError {
    AppError::Validation(format!("the spreadsheet cannot be written: {e}"))
}

/// The date as an Excel date, if it is one Excel can hold (1900 or later).
fn excel_date(d: NaiveDate) -> Option<ExcelDateTime> {
    let year = u16::try_from(d.year()).ok()?;
    ExcelDateTime::from_ymd(year, d.month() as u8, d.day() as u8).ok()
}

fn excel_datetime(t: NaiveDateTime) -> Option<ExcelDateTime> {
    excel_date(t.date())?
        .and_hms_milli(
            t.hour() as u16,
            t.minute() as u8,
            t.second() as u8,
            (t.nanosecond() / 1_000_000) as u16,
        )
        .ok()
}

fn write_xlsx(
    sheet_name: &str,
    header: &[&str],
    rows: impl IntoIterator<Item = Vec<CellValue>>,
) -> AppResult<Vec<u8>> {
    check_sheet_name(sheet_name)?;
    let date_format = XlsxFormat::new().set_num_format("yyyy-mm-dd");
    let datetime_format = XlsxFormat::new().set_num_format("yyyy-mm-dd hh:mm:ss");
    let mut workbook = Workbook::new();
    let sheet = workbook.add_worksheet();
    sheet.set_name(sheet_name).map_err(xlsx_error)?;
    for (c, h) in header.iter().enumerate() {
        sheet.write_string(0, c as u16, *h).map_err(xlsx_error)?;
    }
    for (r, row) in rows.into_iter().enumerate() {
        let r = (r + 1) as u32;
        for (c, cell) in row.into_iter().enumerate() {
            let c = c as u16;
            match cell {
                CellValue::Empty => continue,
                CellValue::Text(s) => sheet.write_string(r, c, s),
                CellValue::Number(d) => match exact_f64(d) {
                    Some(f) => sheet.write_number(r, c, f),
                    None => sheet.write_string(r, c, crate::csv_io::format_decimal(d)),
                },
                CellValue::Bool(b) => sheet.write_boolean(r, c, b),
                CellValue::Date(d) => match excel_date(d) {
                    Some(x) => sheet.write_datetime_with_format(r, c, x, &date_format),
                    None => sheet.write_string(r, c, d.format("%Y-%m-%d").to_string()),
                },
                CellValue::DateTime(t) => match excel_datetime(t) {
                    Some(x) => sheet.write_datetime_with_format(r, c, x, &datetime_format),
                    None => sheet.write_string(r, c, t.format("%Y-%m-%dT%H:%M:%S%.f").to_string()),
                },
            }
            .map_err(xlsx_error)?;
        }
    }
    workbook.save_to_buffer().map_err(xlsx_error)
}
