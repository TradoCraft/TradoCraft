//! The CSV reader: the strict RFC 4180 parser of ADR 0029 producing a [`RawTable`].

use crate::csv_io::{detect_delimiter, format_error, unquote_formula, RowError};
use crate::import::{CellValue, Limits, RawRow, RawTable};

/// Ends the current record: pushes the last field and keeps the record unless the line is blank.
/// Fails when this would be more records than the header plus `limits.rows` data rows, or more
/// cells than `limits.total_cells`.
fn finish_record(
    records: &mut Vec<(usize, Vec<String>)>,
    cells: &mut usize,
    fields: &mut Vec<String>,
    field: &mut String,
    start: usize,
    limits: &Limits,
) -> Result<(), RowError> {
    fields.push(std::mem::take(field));
    let blank = fields.len() == 1 && fields[0].is_empty();
    let record = std::mem::take(fields);
    if blank {
        return Ok(());
    }
    if records.len() > limits.rows {
        return Err(format_error(
            1,
            format!("too many rows: at most {} are accepted", limits.rows),
        ));
    }
    *cells += record.len();
    if *cells > limits.total_cells {
        return Err(format_error(
            1,
            format!(
                "too many cells: at most {} are accepted",
                limits.total_cells
            ),
        ));
    }
    records.push((start, record));
    Ok(())
}

/// Splits RFC 4180 text into records, each with the line number where it starts. Blank lines are
/// skipped. The shape is checked while reading, before anything large is built: a quote inside an
/// unquoted value, text after a closing quote, an unclosed quote, more data rows, cells in a
/// record or cells in total than the limits allow end the parse with one error.
fn parse_records(
    text: &str,
    delim: char,
    limits: &Limits,
) -> Result<Vec<(usize, Vec<String>)>, RowError> {
    let mut records = Vec::new();
    let mut cells = 0usize;
    let mut fields: Vec<String> = Vec::new();
    let mut field = String::new();
    let (mut line, mut start, mut quoted, mut closed) = (1usize, 1usize, false, false);
    let mut chars = text.chars().peekable();
    while let Some(c) = chars.next() {
        if quoted {
            match c {
                '"' if chars.peek() == Some(&'"') => {
                    chars.next();
                    field.push('"');
                }
                '"' => {
                    quoted = false;
                    closed = true;
                }
                '\n' => {
                    line += 1;
                    field.push(c);
                }
                _ => field.push(c),
            }
            continue;
        }
        match c {
            '"' if field.is_empty() && !closed => quoted = true,
            '"' if closed => {
                return Err(format_error(start, "unexpected text after a closing quote"))
            }
            '"' => {
                return Err(format_error(
                    start,
                    "a quote inside an unquoted value; quote the whole value and double the quotes in it",
                ))
            }
            c if c == delim => {
                fields.push(std::mem::take(&mut field));
                closed = false;
                if fields.len() >= limits.cells_per_row {
                    return Err(format_error(
                        start,
                        format!(
                            "too many columns: at most {} are accepted",
                            limits.cells_per_row
                        ),
                    ));
                }
            }
            '\r' => {}
            '\n' => {
                finish_record(&mut records, &mut cells, &mut fields, &mut field, start, limits)?;
                closed = false;
                line += 1;
                start = line;
            }
            _ if closed => return Err(format_error(start, "unexpected text after a closing quote")),
            _ => field.push(c),
        }
    }
    if quoted {
        return Err(format_error(start, "a quoted value is not closed"));
    }
    if !field.is_empty() || !fields.is_empty() {
        finish_record(
            &mut records,
            &mut cells,
            &mut fields,
            &mut field,
            start,
            limits,
        )?;
    }
    Ok(records)
}

/// Reads a CSV body: UTF-8, optional byte order mark, `,` or `;` as the delimiter (detected from
/// the header line), strict quoting. Cells are `Empty` or `Text`; the apostrophe an export puts in
/// front of a value that would run as a formula in a spreadsheet is taken off again (a CSV rule
/// only). Surrounding spaces are kept.
pub fn read(body: &[u8], limits: &Limits) -> Result<RawTable, Vec<RowError>> {
    let text = std::str::from_utf8(body)
        .map_err(|_| vec![format_error(1, "the file is not valid UTF-8")])?;
    let text = text.strip_prefix('\u{feff}').unwrap_or(text);
    let delim = detect_delimiter(text);
    let mut records = parse_records(text, delim, limits).map_err(|e| vec![e])?;
    if records.is_empty() {
        return Err(vec![format_error(1, "the file is empty")]);
    }
    let (header_row, header) = records.remove(0);
    let rows = records
        .into_iter()
        .map(|(row, cells)| RawRow {
            row,
            cells: cells
                .into_iter()
                .map(|c| CellValue::text(unquote_formula(&c)))
                .collect(),
        })
        .collect();
    Ok(RawTable {
        sheets: Vec::new(),
        header_row,
        header,
        rows,
        errors: Vec::new(),
    })
}
