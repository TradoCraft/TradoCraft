//! The data import format layer (ADR 0064): read CSV, XLSX and ODS into one table of typed cells,
//! bind it to an entity's columns, and write the same cells back as CSV, XLSX or ODS.
//!
//! ```text
//! bytes --detect--> Format --read_raw--> RawTable --bind--> Table (rows of typed cells)
//! header + rows of CellValue --write--> bytes
//! ```
//!
//! [`read_table`] does all three reading steps; the typed accessors are [`Cells`].

pub mod archive;
mod cell;
pub mod csv;
pub mod engine;
pub mod entity;
mod format;
mod importable;
mod limits;
mod ods_writer;
mod raw;
pub mod sheet;
mod table;
mod writer;

pub use cell::CellValue;
pub use engine::{
    column_names, export_request, export_rows, import_request, run_import, ExportFormat,
    ExportParams, RunOptions,
};
pub use entity::{BoxFuture, ImportEntity};
pub use format::{detect, download, Format};
pub use importable::{
    Column, ColumnKind, ImportDescription, Importable, NoProgress, Phase, Progress,
};
pub use limits::Limits;
pub use raw::{RawRow, RawTable};
pub use table::{bind, Cell, Cells, Row, Table};
pub use writer::write;

use crate::csv_io::{format_error, limit_error, RowError};

fn one(message: impl Into<String>) -> Vec<RowError> {
    vec![format_error(1, message)]
}

/// Whether a file was refused only because it exceeds `limits` (too large, too many rows, columns
/// or cells, too large an archive): with larger limits ([`Limits::job`]) it could be read. Other
/// problems (an unsupported type, a damaged file, an unknown sheet) are not limits.
pub fn exceeds_limits(errors: &[RowError]) -> bool {
    errors.iter().any(|e| e.limit)
}

/// Detects the format of `bytes` and returns it with the checked limits applied: the file size
/// and, for XLSX and ODS, the archive directory (entry count, declared unpacked size).
pub fn inspect(bytes: &[u8], limits: &Limits) -> Result<Format, Vec<RowError>> {
    if bytes.len() > limits.file_bytes {
        return Err(vec![limit_error(
            1,
            format!(
                "the file is larger than the {} MiB that are accepted",
                limits.file_bytes / (1024 * 1024)
            ),
        )]);
    }
    let format = detect(bytes).map_err(one)?;
    if format != Format::Csv {
        archive::check(bytes, limits).map_err(|r| {
            let error = if r.limit {
                limit_error(1, r.message)
            } else {
                format_error(1, r.message)
            };
            vec![error]
        })?;
    }
    Ok(format)
}

/// Reads a file into one raw table. The format comes from the content. `sheet_name` names the sheet of
/// a workbook (the first worksheet when None; ignored for CSV). All problems of the file as a
/// whole are returned as errors; problems in single rows are in [`RawTable::errors`].
pub fn read_raw(
    bytes: &[u8],
    sheet_name: Option<&str>,
    limits: &Limits,
) -> Result<(Format, RawTable), Vec<RowError>> {
    let format = inspect(bytes, limits)?;
    let table = match format {
        Format::Csv => csv::read(bytes, limits)?,
        Format::Xlsx => sheet::read(bytes, sheet::Kind::Xlsx, sheet_name, limits)?,
        Format::Ods => sheet::read(bytes, sheet::Kind::Ods, sheet_name, limits)?,
    };
    Ok((format, table))
}

/// The names of the sheets of a file (empty for CSV), with the same checks as [`read_raw`].
pub fn sheet_names(bytes: &[u8], limits: &Limits) -> Result<(Format, Vec<String>), Vec<RowError>> {
    let format = inspect(bytes, limits)?;
    let names = match format {
        Format::Csv => Vec::new(),
        Format::Xlsx => sheet::sheet_names(bytes, sheet::Kind::Xlsx, limits)?,
        Format::Ods => sheet::sheet_names(bytes, sheet::Kind::Ods, limits)?,
    };
    Ok((format, names))
}

/// Reads a file and binds it to an entity's columns: [`read_raw`] followed by [`bind`]. Without a
/// `mapping` the header must name the known columns (ADR 0029); with one, `file column -> field`
/// pairs pick the columns (see [`bind`]).
pub fn read_table(
    bytes: &[u8],
    sheet_name: Option<&str>,
    limits: &Limits,
    known: &[&str],
    required: &[&str],
    mapping: Option<&[(String, String)]>,
) -> Result<(Format, Table), Vec<RowError>> {
    let (format, raw) = read_raw(bytes, sheet_name, limits)?;
    Ok((format, bind(raw, known, required, mapping)?))
}

#[cfg(test)]
mod tests;
