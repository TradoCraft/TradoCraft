//! The CSV reader: the strict RFC 4180 parser of ADR 0029 producing a [`RawTable`].

use crate::csv_io::{detect_delimiter, format_error, limit_error, unquote_formula, RowError};
use crate::import::{CellValue, Limits, RawRow, RawTable};

/// The records of a text: those kept, and how many there were in all.
#[derive(Default)]
struct Records {
    kept: Vec<(usize, Vec<String>)>,
    /// Records read, the header included, the dropped ones too.
    seen: usize,
    /// Cells of the data rows.
    cells: usize,
}

/// Ends the current record: pushes the last field and keeps the record unless the line is blank.
/// Fails when this would be more records than the header plus `limits.rows` data rows, or more
/// cells than `limits.total_cells`. With [`Limits::keep_rows`] data rows beyond that many are
/// counted and dropped.
fn finish_record(
    records: &mut Records,
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
    if records.seen > limits.rows {
        return Err(limit_error(
            1,
            format!("too many rows: at most {} are accepted", limits.rows),
        ));
    }
    // The header is not counted: a file of `rows` x `cells_per_row` is within the limits.
    if records.seen > 0 {
        records.cells += record.len();
    }
    if records.cells > limits.total_cells {
        return Err(limit_error(
            1,
            format!(
                "too many cells: at most {} are accepted",
                limits.total_cells
            ),
        ));
    }
    records.seen += 1;
    // The header and `keep_rows` data rows are kept.
    if limits.keep_rows.is_none_or(|k| records.kept.len() <= k) {
        records.kept.push((start, record));
    }
    Ok(())
}

/// Splits RFC 4180 text into records, each with the line number where it starts. Blank lines are
/// skipped. The shape is checked while reading, before anything large is built: a quote inside an
/// unquoted value, text after a closing quote, an unclosed quote, more data rows, cells in a
/// record or cells in total than the limits allow end the parse with one error.
fn parse_records(text: &str, delim: char, limits: &Limits) -> Result<Records, RowError> {
    let mut records = Records::default();
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
                    return Err(limit_error(
                        start,
                        format!(
                            "too many columns: at most {} are accepted",
                            limits.cells_per_row
                        ),
                    ));
                }
            }
            '\r' if chars.peek() == Some(&'\n') => {}
            '\r' => {
                return Err(format_error(
                    start,
                    "a carriage return outside quotes must be part of a CRLF line break",
                ))
            }
            '\n' => {
                finish_record(&mut records, &mut fields, &mut field, start, limits)?;
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
        finish_record(&mut records, &mut fields, &mut field, start, limits)?;
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
    let parsed = parse_records(text, delim, limits).map_err(|e| vec![e])?;
    let dropped_rows = parsed.seen - parsed.kept.len();
    let mut records = parsed.kept;
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
        dropped_rows,
        ..Default::default()
    })
}

#[cfg(test)]
mod limit_tests {
    use super::*;

    #[test]
    fn a_file_exactly_at_the_row_and_column_limits_is_read() {
        let limits = Limits::request();
        let header = vec!["c"; limits.cells_per_row].join(",");
        let row = vec!["x"; limits.cells_per_row].join(",");
        let mut body = format!("{header}\n");
        for _ in 0..limits.rows {
            body.push_str(&row);
            body.push('\n');
        }
        let t = read(body.as_bytes(), &limits).unwrap();
        assert_eq!(t.rows.len(), limits.rows);
        assert_eq!(t.header.len(), limits.cells_per_row);
    }

    #[test]
    fn the_delimiter_comes_from_the_first_non_blank_record() {
        let t = read(b"\n\r\na;b;c\n1;2;3\n", &Limits::request()).unwrap();
        assert_eq!(t.header, vec!["a", "b", "c"]);
        assert_eq!(t.header_row, 3);
    }

    #[test]
    fn a_lone_carriage_return_is_rejected_but_crlf_and_quoted_cr_are_kept() {
        let e = read(b"a,b\r1,2\n", &Limits::request()).unwrap_err();
        assert!(e[0].message.contains("carriage return"), "{e:?}");
        assert!(read(b"a,b\r", &Limits::request()).is_err());
        let t = read(b"a,b\r\n1,2\r\n", &Limits::request()).unwrap();
        assert_eq!(t.rows.len(), 1);
        let t = read(b"a,b\r\n\"x\ry\",2\r\n", &Limits::request()).unwrap();
        assert_eq!(t.rows[0].cells[0], CellValue::text("x\ry"));
    }
}
