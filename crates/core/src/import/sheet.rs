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

use crate::csv_io::{format_error, RowError};
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

/// Turns sheet rows into a [`RawTable`] and enforces the limits as the rows arrive. The header is
/// the first row with a cell; its first cell's column starts the table. Fully empty rows are
/// skipped.
struct Builder<'a> {
    limits: &'a Limits,
    header: Option<(usize, Vec<String>)>, // (header row, names)
    first_col: usize,
    rows: Vec<RawRow>,
    errors: Vec<RowError>,
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
            return Err(vec![format_error(
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
                }),
            }
        }
        if !errors.is_empty() {
            return Err(errors);
        }
        self.total_cells += names.len();
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
            return Err(vec![format_error(
                1,
                format!(
                    "too many columns: at most {} are accepted",
                    self.limits.cells_per_row
                ),
            )]);
        }
        if self.rows.len() >= self.limits.rows {
            return Err(vec![format_error(
                1,
                format!("too many rows: at most {} are accepted", self.limits.rows),
            )]);
        }
        let mut dense: Vec<CellValue> = Vec::new();
        let mut failed = false;
        for (col, value) in cells {
            if col < self.first_col {
                self.errors.push(RowError {
                    row,
                    column: None,
                    message: "a value to the left of the first header column".into(),
                });
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
                    self.errors.push(RowError {
                        row,
                        column: Some(column),
                        message,
                    });
                    failed = true;
                }
            }
        }
        if failed {
            return Ok(());
        }
        if dense.len() < width {
            dense.resize(width, CellValue::Empty);
        }
        self.total_cells += dense.len();
        if self.total_cells > self.limits.total_cells {
            return Err(vec![format_error(
                1,
                format!(
                    "too many cells: at most {} are accepted",
                    self.limits.total_cells
                ),
            )]);
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

fn scan_ods_content(
    input: impl Read,
    limits: &Limits,
) -> Result<std::collections::HashMap<String, Vec<ErrorCells>>, Vec<RowError>> {
    let mut reader = quick_xml::Reader::from_reader(BufReader::new(input));
    let mut buf = Vec::new();
    let mut depth = 0u32; // nesting of table:table
    let (mut cursor, mut end_row, mut width) = (0u64, 0u64, 0u64); // current table
    let (mut row_repeat, mut col, mut row_width) = (1u64, 0u64, 0u64);
    let mut in_row = false;
    let mut total = 0u128;
    let mut table_name = String::new();
    let mut error_cells: std::collections::HashMap<String, Vec<ErrorCells>> = Default::default();
    let mut errors_seen = 0usize;
    let too_many_columns = || {
        fatal(format!(
            "too many columns: at most {} are accepted",
            limits.cells_per_row
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
                "table:table" if !empty => {
                    depth += 1;
                    if depth == 1 {
                        (cursor, end_row, width) = (0, 0, 0);
                        table_name = match e.try_get_attribute("table:name") {
                            Ok(Some(a)) => quick_xml::escape::unescape(&a.value)
                                .map(|n| n.into_owned())
                                .unwrap_or_else(|_| a.value.to_string()),
                            _ => String::new(),
                        };
                    }
                }
                "table:table-row" if depth == 1 => {
                    row_repeat = attr_u64(e, "table:number-rows-repeated")?;
                    (col, row_width) = (0, 0);
                    if empty {
                        cursor = cursor.saturating_add(row_repeat);
                    } else {
                        in_row = true;
                    }
                }
                "table:table-cell" | "table:covered-table-cell" if depth == 1 && in_row => {
                    let repeat = attr_u64(e, "table:number-columns-repeated")?;
                    if e.try_get_attribute("calcext:value-type")
                        .ok()
                        .flatten()
                        .is_some_and(|a| a.value == "error")
                    {
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
                                cols: repeat,
                            });
                    }
                    col = col.saturating_add(repeat);
                    if e.try_get_attribute("office:value-type")
                        .map_err(|_| fatal("the file has a malformed attribute"))?
                        .is_some()
                    {
                        row_width = col;
                    }
                }
                _ => {}
            }
        } else if let Event::End(e) = &event {
            match e.name().as_ref() {
                "table:table-row" if depth == 1 && in_row => {
                    in_row = false;
                    if row_width > 0 {
                        end_row = cursor.saturating_add(row_repeat);
                        width = width.max(row_width);
                        if width > limits.cells_per_row as u64 {
                            return Err(too_many_columns());
                        }
                    }
                    cursor = cursor.saturating_add(row_repeat);
                }
                "table:table" => {
                    if depth == 1 {
                        total += u128::from(end_row) * u128::from(width);
                        if total > limits.total_cells as u128 {
                            return Err(fatal(format!(
                                "too many cells: at most {} are accepted",
                                limits.total_cells
                            )));
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
