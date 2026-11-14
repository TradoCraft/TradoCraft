//! The XLSX and ODS readers (on `calamine`), producing a [`RawTable`].
//!
//! Streaming and limits: XLSX is read cell by cell with `calamine`'s `XlsxCellReader`, so the
//! row, cells-per-row and total-cell limits stop the read as soon as they are exceeded and a
//! sparse sheet never allocates its bounding box. `calamine` cannot stream ODS: it parses every
//! sheet of `content.xml` into dense ranges when the workbook is opened. Before that happens
//! [`scan_ods`] walks `content.xml` once, cheaply, and refuses a file whose sheets would expand
//! beyond the limits (repeated rows and columns make that possible in a few bytes).

use std::io::{BufReader, Cursor, Read};

use calamine::{Data, ExcelDateTime, Ods, Range, Reader, SheetType, Xlsx};
use chrono::{NaiveDate, NaiveDateTime};
use quick_xml::events::{BytesStart, Event};
use zip::ZipArchive;

use crate::csv_io::{format_error, limit_error, RowError, MAX_REPORTED_ERRORS};
use crate::import::{CellValue, Limits, RawRow, RawTable};

/// Which spreadsheet format to read.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    Xlsx,
    Ods,
}

/// Names of the worksheets of an XLSX or ODS file.
pub fn sheet_names(
    bytes: &[u8],
    kind: Kind,
    limits: &Limits,
) -> Result<Vec<String>, Vec<RowError>> {
    match kind {
        Kind::Xlsx => Ok(open_xlsx(bytes)?.1),
        Kind::Ods => {
            scan_ods(bytes, limits)?;
            Ok(open_ods(bytes)?.1)
        }
    }
}

/// Reads one sheet of an XLSX or ODS file: `sheet` by name, or the first worksheet. The archive
/// must already have passed [`crate::import::archive::check`].
pub fn read(
    bytes: &[u8],
    kind: Kind,
    sheet: Option<&str>,
    limits: &Limits,
) -> Result<RawTable, Vec<RowError>> {
    match kind {
        Kind::Xlsx => read_xlsx(bytes, sheet, limits),
        Kind::Ods => read_ods(bytes, sheet, limits),
    }
}

fn fatal(message: impl Into<String>) -> Vec<RowError> {
    vec![format_error(1, message)]
}

fn over_limit(message: impl Into<String>) -> Vec<RowError> {
    vec![limit_error(1, message)]
}

fn pick_sheet(names: &[String], wanted: Option<&str>) -> Result<String, Vec<RowError>> {
    match wanted {
        None => names
            .first()
            .cloned()
            .ok_or_else(|| fatal("the workbook has no sheets")),
        Some(w) => names.iter().find(|n| *n == w).cloned().ok_or_else(|| {
            fatal(format!(
                "unknown sheet {w:?}; the sheets are: {}",
                names.join(", ")
            ))
        }),
    }
}

// ---------------------------------------------------------------------------------------------
// Values
// ---------------------------------------------------------------------------------------------

/// A calamine value as a typed cell, or the reason it cannot be one.
fn convert(data: Data) -> Result<CellValue, String> {
    match data {
        Data::Empty => Ok(CellValue::Empty),
        Data::String(s) => Ok(CellValue::text(s)),
        Data::Int(i) => Ok(CellValue::int(i)),
        Data::Float(f) => CellValue::from_f64(f),
        Data::Bool(b) => Ok(CellValue::Bool(b)),
        Data::DateTime(d) => convert_excel_date(d),
        Data::DateTimeIso(s) => convert_iso_date(&s),
        Data::DurationIso(s) => Err(format!("{s} is a time or duration, which is not supported")),
        Data::Error(e) => Err(format!("the cell holds the spreadsheet error {e}")),
    }
}

/// A date cell is a [`CellValue::Date`] when it has no time part, else a date-time.
fn convert_excel_date(d: ExcelDateTime) -> Result<CellValue, String> {
    if d.is_duration() {
        return Err("a duration is not supported".into());
    }
    let dt = d.as_datetime().ok_or("the date is out of range")?;
    Ok(if dt.time() == chrono::NaiveTime::MIN {
        CellValue::Date(dt.date())
    } else {
        CellValue::DateTime(dt)
    })
}

fn convert_iso_date(s: &str) -> Result<CellValue, String> {
    if let Ok(d) = NaiveDate::parse_from_str(s, "%Y-%m-%d") {
        return Ok(CellValue::Date(d));
    }
    NaiveDateTime::parse_from_str(s, "%Y-%m-%dT%H:%M:%S%.f")
        .map(CellValue::DateTime)
        .map_err(|_| format!("{s:?} is not a date"))
}

/// Column letters of a 0-based column index (`A`, `B`, ..., `AA`).
fn column_letters(mut col: usize) -> String {
    let mut out = Vec::new();
    loop {
        out.push(b'A' + (col % 26) as u8);
        if col < 26 {
            break;
        }
        col = col / 26 - 1;
    }
    out.reverse();
    String::from_utf8_lossy(&out).into_owned()
}

// ---------------------------------------------------------------------------------------------
// Assembling the table
// ---------------------------------------------------------------------------------------------

/// A row of the sheet as the readers deliver it: sparse cells with their 0-based column.
struct SheetRow {
    /// 1-based row number in the sheet.
    row: usize,
    cells: Vec<(usize, Result<CellValue, String>)>,
}

/// Keeps `error` unless [`MAX_REPORTED_ERRORS`] are kept already; then only notes that some were
/// left out.
fn record(errors: &mut Vec<RowError>, truncated: &mut bool, error: RowError) {
    if errors.len() < MAX_REPORTED_ERRORS {
        errors.push(error);
    } else {
        *truncated = true;
    }
}

/// Turns sheet rows into a [`RawTable`] and enforces the limits as the rows arrive. The header is
/// the first row with a cell; its first cell's column starts the table. Fully empty rows are
/// skipped.
struct Builder<'a> {
    limits: &'a Limits,
    header: Option<(usize, Vec<String>)>, // (header row, names)
    first_col: usize,
    rows: Vec<RawRow>,
    errors: Vec<RowError>,
    errors_truncated: bool,
    /// Data rows read but not kept ([`Limits::keep_rows`]).
    dropped_rows: usize,
    /// Data rows seen, the ones with an error cell included.
    data_rows: usize,
    failed_rows: usize,
    /// Cells of the data rows (the header is not counted), the failed rows included.
    total_cells: usize,
}

impl<'a> Builder<'a> {
    fn new(limits: &'a Limits) -> Self {
        Builder {
            limits,
            header: None,
            first_col: 0,
            rows: Vec::new(),
            errors: Vec::new(),
            errors_truncated: false,
            dropped_rows: 0,
            data_rows: 0,
            failed_rows: 0,
            total_cells: 0,
        }
    }

    fn push(&mut self, row: SheetRow) -> Result<(), Vec<RowError>> {
        // Empty cells (styled but blank) do not make a row.
        let cells: Vec<_> = row
            .cells
            .into_iter()
            .filter(|(_, v)| !matches!(v, Ok(CellValue::Empty)))
            .collect();
        if cells.is_empty() {
            return Ok(());
        }
        // The readers deliver a row's cells in column order; anything else would make the width
        // arithmetic below meaningless.
        if cells.windows(2).any(|w| w[0].0 >= w[1].0) {
            return Err(fatal(format!(
                "the cells of row {} are not in column order",
                row.row
            )));
        }
        if self.header.is_none() {
            return self.push_header(row.row, cells);
        }
        self.push_data(row.row, cells)
    }

    fn push_header(
        &mut self,
        row: usize,
        cells: Vec<(usize, Result<CellValue, String>)>,
    ) -> Result<(), Vec<RowError>> {
        let first = cells[0].0;
        let last = cells[cells.len() - 1].0;
        if last - first + 1 > self.limits.cells_per_row {
            return Err(vec![limit_error(
                1,
                format!(
                    "too many columns: at most {} are accepted",
                    self.limits.cells_per_row
                ),
            )]);
        }
        let mut names = vec![String::new(); last - first + 1];
        let mut errors = Vec::new();
        for (col, value) in cells {
            match value {
                Ok(v) => names[col - first] = v.render().unwrap_or_default(),
                Err(message) => errors.push(RowError {
                    row,
                    column: Some(column_letters(col)),
                    message,
                    limit: false,
                }),
            }
        }
        if !errors.is_empty() {
            return Err(errors);
        }
        self.first_col = first;
        self.header = Some((row, names));
        Ok(())
    }

    fn push_data(
        &mut self,
        row: usize,
        cells: Vec<(usize, Result<CellValue, String>)>,
    ) -> Result<(), Vec<RowError>> {
        let Some((_, names)) = &self.header else {
            return Ok(());
        };
        let width = names.len();
        let last = cells[cells.len() - 1].0;
        if last >= self.first_col && last - self.first_col + 1 > self.limits.cells_per_row {
            return Err(vec![limit_error(
                1,
                format!(
                    "too many columns: at most {} are accepted",
                    self.limits.cells_per_row
                ),
            )]);
        }
        // A row counts against the limits whether or not it can be used.
        if self.data_rows >= self.limits.rows {
            return Err(vec![limit_error(
                1,
                format!("too many rows: at most {} are accepted", self.limits.rows),
            )]);
        }
        self.data_rows += 1;
        self.total_cells += width.max(if last >= self.first_col {
            last - self.first_col + 1
        } else {
            0
        });
        if self.total_cells > self.limits.total_cells {
            return Err(vec![limit_error(
                1,
                format!(
                    "too many cells: at most {} are accepted",
                    self.limits.total_cells
                ),
            )]);
        }
        if self.limits.keep_rows.is_some_and(|k| self.rows.len() >= k) {
            self.dropped_rows += 1;
            return Ok(());
        }
        let mut dense: Vec<CellValue> = Vec::new();
        let mut failed = false;
        for (col, value) in cells {
            if col < self.first_col {
                record(
                    &mut self.errors,
                    &mut self.errors_truncated,
                    RowError {
                        row,
                        column: None,
                        message: "a value to the left of the first header column".into(),
                        limit: false,
                    },
                );
                failed = true;
                continue;
            }
            let i = col - self.first_col;
            match value {
                Ok(v) => {
                    if dense.len() <= i {
                        dense.resize(i + 1, CellValue::Empty);
                    }
                    dense[i] = v;
                }
                Err(message) => {
                    let column = names
                        .get(i)
                        .map(|n| n.trim())
                        .filter(|n| !n.is_empty())
                        .map(str::to_string)
                        .unwrap_or_else(|| column_letters(col));
                    record(
                        &mut self.errors,
                        &mut self.errors_truncated,
                        RowError {
                            row,
                            column: Some(column),
                            message,
                            limit: false,
                        },
                    );
                    failed = true;
                }
            }
        }
        if failed {
            self.failed_rows += 1;
            return Ok(());
        }
        if dense.len() < width {
            dense.resize(width, CellValue::Empty);
        }
        self.rows.push(RawRow { row, cells: dense });
        Ok(())
    }

    fn finish(self, sheets: Vec<String>) -> Result<RawTable, Vec<RowError>> {
        let Some((header_row, header)) = self.header else {
            return Err(fatal("the sheet is empty"));
        };
        Ok(RawTable {
            sheets,
            header_row,
            header,
            rows: self.rows,
            errors: self.errors,
            failed_rows: self.failed_rows,
            dropped_rows: self.dropped_rows,
            errors_truncated: self.errors_truncated,
        })
    }
}

// ---------------------------------------------------------------------------------------------
// XLSX
// ---------------------------------------------------------------------------------------------

fn damaged(what: &str, e: impl std::fmt::Display) -> Vec<RowError> {
    fatal(format!("the file cannot be read as {what} ({e})"))
}

/// Opens the workbook and lists its worksheets (not chart or macro sheets).
type XlsxBook<'a> = Xlsx<Cursor<&'a [u8]>>;
type OdsBook<'a> = Ods<Cursor<&'a [u8]>>;

fn open_xlsx(bytes: &[u8]) -> Result<(XlsxBook<'_>, Vec<String>), Vec<RowError>> {
    let wb: Xlsx<_> = calamine::open_workbook_from_rs(Cursor::new(bytes))
        .map_err(|e| damaged("an XLSX workbook", e))?;
    let names = wb
        .sheets_metadata()
        .iter()
        .filter(|s| s.typ == SheetType::WorkSheet)
        .map(|s| s.name.clone())
        .collect();
    Ok((wb, names))
}

fn read_xlsx(
    bytes: &[u8],
    sheet: Option<&str>,
    limits: &Limits,
) -> Result<RawTable, Vec<RowError>> {
    let (mut wb, names) = open_xlsx(bytes)?;
    let name = pick_sheet(&names, sheet)?;
    let mut reader = wb
        .worksheet_cells_reader(&name)
        .map_err(|e| damaged("an XLSX workbook", e))?;
    let mut builder = Builder::new(limits);
    let mut current: Option<SheetRow> = None;
    while let Some(cell) = reader
        .next_cell()
        .map_err(|e| damaged("an XLSX workbook", e))?
    {
        let (r, c) = cell.get_position();
        let row = r as usize + 1;
        let value = convert(Data::from(cell.get_value().clone()));
        match &mut current {
            Some(cur) if cur.row == row => cur.cells.push((c as usize, value)),
            Some(cur) if cur.row > row => {
                return Err(fatal(format!(
                    "the sheet's rows are not in order (row {row} comes after row {})",
                    cur.row
                )))
            }
            _ => {
                if let Some(done) = current.take() {
                    builder.push(done)?;
                }
                current = Some(SheetRow {
                    row,
                    cells: vec![(c as usize, value)],
                });
            }
        }
    }
    if let Some(done) = current {
        builder.push(done)?;
    }
    builder.finish(names)
}

// ---------------------------------------------------------------------------------------------
// ODS
// ---------------------------------------------------------------------------------------------

fn open_ods(bytes: &[u8]) -> Result<(OdsBook<'_>, Vec<String>), Vec<RowError>> {
    let wb: Ods<_> = calamine::open_workbook_from_rs(Cursor::new(bytes))
        .map_err(|e| damaged("an ODS workbook", e))?;
    let names = wb
        .sheets_metadata()
        .iter()
        .filter(|s| s.typ == SheetType::WorkSheet)
        .map(|s| s.name.clone())
        .collect();
    Ok((wb, names))
}

fn read_ods(bytes: &[u8], sheet: Option<&str>, limits: &Limits) -> Result<RawTable, Vec<RowError>> {
    let mut error_cells = scan_ods(bytes, limits)?;
    let (mut wb, names) = open_ods(bytes)?;
    let name = pick_sheet(&names, sheet)?;
    let error_cells = error_cells.remove(&name).unwrap_or_default();
    let range: Range<Data> = wb
        .worksheet_range(&name)
        .map_err(|e| damaged("an ODS workbook", e))?;
    drop(wb);
    let Some((start_row, start_col)) = range.start() else {
        return Err(fatal("the sheet is empty"));
    };
    let mut builder = Builder::new(limits);
    for (i, cells) in range.rows().enumerate() {
        let row = SheetRow {
            row: start_row as usize + i + 1,
            cells: cells
                .iter()
                .enumerate()
                .filter(|(_, d)| !matches!(d, Data::Empty))
                .map(|(j, d)| {
                    let col = start_col as usize + j;
                    (
                        col,
                        convert_ods(d, &error_cells, start_row as u64 + i as u64, col as u64),
                    )
                })
                .collect(),
        };
        builder.push(row)?;
    }
    builder.finish(names)
}

/// Where the cells that ODS marks as errors are (`calcext:value-type="error"`): `calamine` turns
/// such a cell into a text cell holding the error text, so the position is the only way to tell
/// it from a text that happens to read `#N/A`.
#[derive(Debug, Clone, Copy)]
struct ErrorCells {
    row: u64,
    rows: u64,
    col: u64,
    cols: u64,
}

fn convert_ods(
    data: &Data,
    error_cells: &[ErrorCells],
    row: u64,
    col: u64,
) -> Result<CellValue, String> {
    if let Data::String(text) = data {
        let marked = error_cells.iter().any(|e| {
            (e.row..e.row.saturating_add(e.rows)).contains(&row)
                && (e.col..e.col.saturating_add(e.cols)).contains(&col)
        });
        if marked {
            return Err(format!("the cell holds the spreadsheet error {text}"));
        }
    }
    convert(data.clone())
}

fn attr_u64(e: &BytesStart<'_>, name: &str) -> Result<u64, Vec<RowError>> {
    match e.try_get_attribute(name) {
        Ok(Some(a)) => a
            .value
            .trim()
            .parse::<u64>()
            .ok()
            .ok_or_else(|| fatal(format!("the file has an invalid {name} value"))),
        Ok(None) => Ok(1),
        Err(_) => Err(fatal("the file has a malformed attribute")),
    }
}

/// Walks `content.xml` and refuses a file whose sheets would expand beyond the limits. The extent
/// of a sheet is the rectangle up to its last non-empty row and widest non-empty row: trailing
/// empty rows and columns (LibreOffice writes a million of them) cost nothing, but a row or cell
/// that is repeated a million times and holds a value does.
fn scan_ods(
    bytes: &[u8],
    limits: &Limits,
) -> Result<std::collections::HashMap<String, Vec<ErrorCells>>, Vec<RowError>> {
    let mut zip = ZipArchive::new(Cursor::new(bytes)).map_err(|e| damaged("an ODS workbook", e))?;
    let entry = zip
        .by_name("content.xml")
        .map_err(|_| fatal("the ODS file has no content.xml"))?;
    scan_ods_content(BufReader::new(entry), limits)
}

/// What the scan needs from the attributes of one `table:table-cell`.
#[derive(Default)]
struct CellAttrs {
    repeat: u64,
    /// `calamine` keeps the cell: it has a value, a formula or a value type.
    stored: bool,
    error: bool,
    /// Bytes of an `office:string-value`.
    text: u64,
}

fn cell_attrs(e: &BytesStart<'_>) -> Result<CellAttrs, Vec<RowError>> {
    let mut out = CellAttrs {
        repeat: 1,
        ..Default::default()
    };
    for a in e.attributes().with_checks(false) {
        let a = a.map_err(|_| fatal("the file has a malformed attribute"))?;
        match a.key.as_ref() {
            "table:number-columns-repeated" => {
                out.repeat = a.value.trim().parse::<u64>().ok().ok_or_else(|| {
                    fatal("the file has an invalid table:number-columns-repeated value")
                })?;
            }
            "office:value"
            | "office:date-value"
            | "office:time-value"
            | "office:boolean-value"
            | "office:value-type"
            | "table:formula" => out.stored = true,
            "office:string-value" => {
                out.stored = true;
                out.text = a.value.len() as u64;
            }
            "calcext:value-type" => {
                out.stored = true;
                out.error = a.value == "error";
            }
            _ => {}
        }
    }
    Ok(out)
}

/// `calamine` stores at most this many cells of one row.
const ODS_MAX_COLUMNS: u64 = 16_384;

fn scan_ods_content(
    input: impl Read,
    limits: &Limits,
) -> Result<std::collections::HashMap<String, Vec<ErrorCells>>, Vec<RowError>> {
    let mut reader = quick_xml::Reader::from_reader(BufReader::new(input));
    let mut buf = Vec::new();
    let mut depth = 0u32; // nesting of table:table
                          // Current table: the row cursor, the used rectangle (rows `first_row..end_row`, columns
                          // `first_col..end_col`, both counted from the sheet origin).
    let (mut cursor, mut first_row, mut end_row) = (0u64, None::<u64>, 0u64);
    let (mut first_col, mut end_col) = (u64::MAX, 0u64);
    // Current row: its repeat count, the column cursor, the first and last stored column.
    let (mut row_repeat, mut col) = (1u64, 0u64);
    let (mut row_first, mut row_end) = (None::<u64>, 0u64);
    let (mut in_row, mut in_cell, mut cell_repeat) = (false, false, 1u64);
    // What calamine holds: the cells it stores per row (from column A, a repeated row is stored
    // once) and the dense rectangle of every sheet, each over all sheets together.
    let (mut stored, mut dense) = (0u128, 0u128);
    let mut text = 0u128;
    let mut table_name = String::new();
    let mut error_cells: std::collections::HashMap<String, Vec<ErrorCells>> = Default::default();
    let mut errors_seen = 0usize;
    // The limit counts the data rows; the header row is allowed on top.
    let allowed_cells = (limits.total_cells + limits.cells_per_row) as u128;
    let too_many_cells = || {
        over_limit(format!(
            "too many cells: at most {} are accepted in the workbook's sheets together",
            limits.total_cells
        ))
    };
    let too_much_text = || {
        over_limit(format!(
            "too much text: the cells hold more than {} bytes of text",
            limits.unpacked_bytes
        ))
    };
    loop {
        buf.clear();
        let event = reader
            .read_event_into(&mut buf)
            .map_err(|e| damaged("an ODS workbook", e))?;
        let (e, empty) = match &event {
            Event::Start(e) => (Some(e), false),
            Event::Empty(e) => (Some(e), true),
            _ => (None, false),
        };
        if let Some(e) = e {
            match e.name().as_ref() {
                "table:table" if depth >= 1 => {
                    return Err(fatal("tables inside tables are not supported"));
                }
                "table:table" if !empty => {
                    depth = 1;
                    (cursor, first_row, end_row) = (0, None, 0);
                    (first_col, end_col) = (u64::MAX, 0);
                    table_name = match e.try_get_attribute("table:name") {
                        Ok(Some(a)) => quick_xml::escape::unescape(&a.value)
                            .map(|n| n.into_owned())
                            .unwrap_or_else(|_| a.value.to_string()),
                        _ => String::new(),
                    };
                }
                "table:table-row" if depth == 1 => {
                    row_repeat = attr_u64(e, "table:number-rows-repeated")?;
                    (col, row_first, row_end) = (0, None, 0);
                    if empty {
                        cursor = cursor.saturating_add(row_repeat);
                    } else {
                        in_row = true;
                    }
                }
                "table:table-cell" | "table:covered-table-cell" if depth == 1 && in_row => {
                    if in_cell {
                        return Err(fatal("cells inside cells are not supported"));
                    }
                    let attrs = cell_attrs(e)?;
                    if attrs.error {
                        errors_seen += 1;
                        if errors_seen > 100_000 {
                            return Err(fatal("the file has too many cells with errors"));
                        }
                        error_cells
                            .entry(table_name.clone())
                            .or_default()
                            .push(ErrorCells {
                                row: cursor,
                                rows: row_repeat,
                                col,
                                cols: attrs.repeat,
                            });
                    }
                    if attrs.stored {
                        row_first.get_or_insert(col);
                    }
                    col = col.saturating_add(attrs.repeat);
                    if attrs.stored {
                        row_end = col;
                    }
                    text += u128::from(attrs.text) * u128::from(attrs.repeat);
                    if text > u128::from(limits.unpacked_bytes) {
                        return Err(too_much_text());
                    }
                    if !empty {
                        in_cell = true;
                        cell_repeat = attrs.repeat;
                    }
                }
                "text:s" if in_cell => {
                    let n = attr_u64(e, "text:c")?;
                    text += u128::from(n) * u128::from(cell_repeat);
                    if text > u128::from(limits.unpacked_bytes) {
                        return Err(too_much_text());
                    }
                }
                _ => {}
            }
        } else if let Event::Text(t) = &event {
            if in_cell {
                text += t.len() as u128 * u128::from(cell_repeat);
                if text > u128::from(limits.unpacked_bytes) {
                    return Err(too_much_text());
                }
            }
        } else if let Event::End(e) = &event {
            match e.name().as_ref() {
                "table:table-cell" | "table:covered-table-cell" => in_cell = false,
                "table:table-row" if depth == 1 && in_row => {
                    in_row = false;
                    in_cell = false;
                    if let Some(first) = row_first {
                        first_row.get_or_insert(cursor);
                        end_row = cursor.saturating_add(row_repeat);
                        first_col = first_col.min(first);
                        end_col = end_col.max(row_end.min(ODS_MAX_COLUMNS));
                        stored += u128::from(row_end.min(ODS_MAX_COLUMNS));
                        if end_col.saturating_sub(first_col) > limits.cells_per_row as u64 {
                            return Err(over_limit(format!(
                                "too many columns: at most {} are accepted",
                                limits.cells_per_row
                            )));
                        }
                        if stored > allowed_cells {
                            return Err(too_many_cells());
                        }
                        // The header is a row too; a repeated row is one element but many rows.
                        if end_row - first_row.unwrap_or(0) > limits.rows as u64 + 1 {
                            return Err(over_limit(format!(
                                "too many rows: at most {} are accepted (the sheet would expand \
                                 to too many cells)",
                                limits.rows
                            )));
                        }
                    }
                    cursor = cursor.saturating_add(row_repeat);
                }
                "table:table" => {
                    if depth == 1 {
                        if let Some(first) = first_row {
                            dense += u128::from(end_row - first)
                                * u128::from(end_col.saturating_sub(first_col));
                        }
                        if dense > allowed_cells {
                            return Err(too_many_cells());
                        }
                    }
                    depth = depth.saturating_sub(1);
                }
                _ => {}
            }
        } else if matches!(event, Event::Eof) {
            return Ok(error_cells);
        }
    }
}

#[cfg(test)]
mod scan_tests {
    use super::*;

    fn content(tables: &str) -> Vec<u8> {
        format!(
            r#"<?xml version="1.0"?><office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" xmlns:calcext="urn:org:documentfoundation:names:experimental:calc:xmlns:calcext:1.0"><office:body><office:spreadsheet>{tables}</office:spreadsheet></office:body></office:document-content>"#
        )
        .into_bytes()
    }

    fn scan(tables: &str) -> Result<(), String> {
        scan_ods_content(content(tables).as_slice(), &Limits::request())
            .map(|_| ())
            .map_err(|e| e[0].message.clone())
    }

    fn sheet(rows: &str) -> String {
        format!(r#"<table:table table:name="S">{rows}</table:table>"#)
    }

    #[test]
    fn a_cell_with_a_value_attribute_and_no_value_type_is_not_free() {
        // 10 000 rows of one cell repeated 16 384 times: 164 million cells in calamine.
        let rows = r#"<table:table-row><table:table-cell office:value="1" table:number-columns-repeated="16384"/></table:table-row>"#
            .repeat(10_000);
        let e = scan(&sheet(&rows)).unwrap_err();
        assert!(e.contains("too many"), "{e}");
    }

    #[test]
    fn every_attribute_that_makes_calamine_keep_a_cell_counts() {
        for attrs in [
            r#"table:formula="of:=1""#,
            r#"office:string-value="x""#,
            r#"office:date-value="2024-01-01""#,
            r#"office:time-value="PT1H""#,
            r#"office:boolean-value="true""#,
            r#"office:value-type="string""#,
        ] {
            let rows = format!(
                r#"<table:table-row><table:table-cell {attrs} table:number-columns-repeated="16384"/></table:table-row>"#
            )
            .repeat(1_000);
            let e = scan(&sheet(&rows));
            assert!(e.is_err(), "{attrs}");
        }
    }

    #[test]
    fn repeated_rows_of_valued_cells_without_a_value_type_count() {
        let rows = r#"<table:table-row table:number-rows-repeated="1000000"><table:table-cell office:value="1"/><table:table-cell office:value="2"/></table:table-row>"#;
        let e = scan(&sheet(rows)).unwrap_err();
        assert!(e.contains("too many cells"), "{e}");
    }

    #[test]
    fn stored_cells_are_counted_from_column_a_across_all_sheets() {
        // Narrow (one column) but 100 000 cells to the left of it in every row of two sheets.
        let rows = r#"<table:table-row table:number-rows-repeated="10"><table:table-cell table:number-columns-repeated="16000"/><table:table-cell office:value="1"/></table:table-row>"#;
        let one = sheet(rows);
        assert!(scan(&one).is_ok());
        let many = (0..20)
            .map(|i| format!(r#"<table:table table:name="N{i}">{rows}</table:table>"#))
            .collect::<String>();
        assert!(scan(&many).is_ok(), "rows repeat, they are stored once");
        let unrepeated = r#"<table:table-row><table:table-cell table:number-columns-repeated="16000"/><table:table-cell office:value="1"/></table:table-row>"#
            .repeat(200);
        let e = scan(&sheet(&unrepeated)).unwrap_err();
        assert!(e.contains("the workbook's sheets together"), "{e}");
    }

    #[test]
    fn a_huge_space_run_in_a_text_is_refused() {
        let cell = r#"<table:table-cell office:value-type="string"><text:p>a<text:s text:c="4000000000"/></text:p></table:table-cell>"#;
        let e = scan(&sheet(&format!(
            "<table:table-row>{cell}</table:table-row>"
        )))
        .unwrap_err();
        assert!(e.contains("too much text"), "{e}");
    }

    #[test]
    fn a_long_text_in_a_repeated_cell_is_counted_every_time() {
        let long = "x".repeat(1_000_000);
        let cell = format!(
            r#"<table:table-cell office:string-value="{long}" table:number-columns-repeated="100"/>"#
        );
        let rows = format!("<table:table-row>{cell}</table:table-row>");
        // 100 MB of text from 1 MB of file.
        let e = scan(&sheet(&rows)).unwrap_err();
        assert!(e.contains("too much text"), "{e}");
    }

    #[test]
    fn the_width_is_counted_from_the_first_used_column() {
        let row = format!(
            "<table:table-row><table:table-cell table:number-columns-repeated=\"150\"/>{}</table:table-row>",
            r#"<table:table-cell office:value="1"/>"#.repeat(10)
        );
        assert!(scan(&sheet(&row.repeat(3))).is_ok());
    }

    #[test]
    fn nested_tables_and_cells_are_refused() {
        let nested = r#"<table:table-row><table:table-cell office:value-type="string"><table:table table:name="in"/><table:table table:name="in2"><table:table-row/></table:table></table:table-cell></table:table-row>"#;
        assert!(scan(&sheet(nested)).is_err());
    }
}
