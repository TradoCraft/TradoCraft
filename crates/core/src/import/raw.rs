//! The result of reading a file, before its columns are bound to an entity.

use crate::csv_io::RowError;
use crate::import::CellValue;

/// One data row as read: the number of the row in the file and its cells in file order.
#[derive(Debug, Clone, PartialEq)]
pub struct RawRow {
    /// Line (CSV) or sheet row (XLSX, ODS) of the row, 1-based; the first line is 1.
    pub row: usize,
    pub cells: Vec<CellValue>,
}

/// A file as one table: nothing is interpreted yet. Bind it to an entity's columns with
/// [`crate::import::bind`].
#[derive(Debug, Clone, PartialEq, Default)]
pub struct RawTable {
    /// Names of the sheets in workbook order; empty for CSV.
    pub sheets: Vec<String>,
    /// Row of the header in the file.
    pub header_row: usize,
    /// The header cells as text, exactly as written.
    pub header: Vec<String>,
    /// The data rows, fully empty rows left out. Rows with a spreadsheet error cell are not here
    /// but in `errors`.
    pub rows: Vec<RawRow>,
    /// Problems found in single rows while reading (a spreadsheet error cell, a number that has no
    /// exact decimal form). The row is left out of `rows`.
    pub errors: Vec<RowError>,
    /// Data rows read but not kept (see [`crate::import::Limits::keep_rows`]); 0 otherwise.
    pub dropped_rows: usize,
    /// How many rows `errors` stands for (a row with several error cells is one row).
    pub failed_rows: usize,
    /// The reader stopped listing errors at [`crate::csv_io::MAX_REPORTED_ERRORS`]; there are more.
    pub errors_truncated: bool,
}
