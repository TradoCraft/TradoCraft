//! Binding a read file to an entity's columns, and typed access to the cells of a row. The same
//! code serves every format; the rules are those of ADR 0029 and ADR 0064 section 2.

use std::collections::{HashMap, HashSet};

use rust_decimal::prelude::ToPrimitive;
use rust_decimal::Decimal;

use crate::csv_io::{format_error, parse_bool, parse_decimal, RowError};
use crate::import::{CellValue, RawTable};

/// An import file bound to an entity: known columns in any order, one [`Row`] per usable data
/// row.
#[derive(Debug)]
pub struct Table {
    /// The entity's field names present in the file.
    pub columns: Vec<String>,
    pub rows: Vec<Row>,
    /// Rows left out of `rows`: their width does not match the header, or (spreadsheets) a cell
    /// holds an error. The importers check the other rows anyway and report these together with
    /// their own errors.
    pub width_errors: Vec<RowError>,
    /// How many rows `width_errors` stands for (a row with several error cells is one row).
    pub failed_rows: usize,
    /// The reader stopped listing errors; there are more than `width_errors` holds.
    pub errors_truncated: bool,
}

impl Table {
    /// Whether the file has this column.
    pub fn has(&self, column: &str) -> bool {
        self.columns.iter().any(|c| c == column)
    }
}

/// One data row (see [`Cells`] for typed access).
#[derive(Debug)]
pub struct Row {
    /// Line (CSV) or sheet row (XLSX, ODS) where the row is.
    pub line: usize,
    cells: HashMap<String, CellValue>,
    /// Text form of the cells that are not text (numbers, booleans, dates).
    rendered: HashMap<String, String>,
}

impl Row {
    /// The cell as text (surrounding spaces kept; a number without trailing zeros), if the file
    /// has the column. An empty cell is `""`.
    pub fn get(&self, column: &str) -> Option<&str> {
        match self.cells.get(column)? {
            CellValue::Empty => Some(""),
            CellValue::Text(s) => Some(s),
            _ => self.rendered.get(column).map(String::as_str),
        }
    }

    /// The cell as text without surrounding spaces; None when the file lacks the column or the
    /// cell is empty or only spaces.
    pub fn get_trimmed(&self, column: &str) -> Option<&str> {
        self.get(column).map(str::trim).filter(|v| !v.is_empty())
    }

    /// The typed value of the cell, if the file has the column.
    pub fn value(&self, column: &str) -> Option<&CellValue> {
        self.cells.get(column)
    }
}

/// Binds a read file to the columns of an entity.
///
/// Without a `mapping` the header must name the entity's columns (`known`), compared trimmed and
/// case-insensitively; an unknown or duplicate column and a missing `required` one are header
/// errors, all reported together.
///
/// With a `mapping` (`file column -> field`, both compared trimmed and case-insensitively) only
/// the mapped file columns are used and the others are ignored. Header errors: a field that is not
/// known, a mapped file column that is not in the header (or is there twice), two file columns
/// mapped to one field, one file column mapped to two fields, a missing `required` field.
///
/// A data row with fewer cells than the header, or non-empty cells beyond it, is a row error in
/// `width_errors` and is left out; the other rows are kept. Cell values are not trimmed (see
/// [`Cells`]).
pub fn bind(
    raw: RawTable,
    known: &[&str],
    required: &[&str],
    mapping: Option<&[(String, String)]>,
) -> Result<Table, Vec<RowError>> {
    let header_row = raw.header_row;
    let file_columns: Vec<String> = raw.header.iter().map(|h| h.trim().to_lowercase()).collect();
    let (fields, errors) = match mapping {
        None => bind_by_name(&file_columns, known, required, header_row),
        Some(m) => bind_by_mapping(&file_columns, known, required, m, header_row),
    };
    if !errors.is_empty() {
        return Err(errors);
    }

    let width = file_columns.len();
    let columns: Vec<String> = fields.iter().flatten().cloned().collect();
    let mut rows = Vec::with_capacity(raw.rows.len());
    let mut width_errors = raw.errors;
    let mut failed_rows = raw.failed_rows;
    for r in raw.rows {
        let wrong_width = r.cells.len() < width || r.cells[width..].iter().any(|c| !c.is_blank());
        if wrong_width {
            width_errors.push(format_error(
                r.row,
                format!(
                    "{} values but the header has {} columns",
                    r.cells.len(),
                    width
                ),
            ));
            failed_rows += 1;
            continue;
        }
        let mut cells = HashMap::new();
        let mut rendered = HashMap::new();
        for (field, value) in fields.iter().zip(r.cells) {
            let Some(field) = field else { continue };
            if !matches!(value, CellValue::Empty | CellValue::Text(_)) {
                if let Some(text) = value.render() {
                    rendered.insert(field.clone(), text);
                }
            }
            cells.insert(field.clone(), value);
        }
        rows.push(Row {
            line: r.row,
            cells,
            rendered,
        });
    }
    width_errors.sort_by_key(|e| e.row);
    Ok(Table {
        columns,
        rows,
        width_errors,
        failed_rows,
        errors_truncated: raw.errors_truncated,
    })
}

type Fields = Vec<Option<String>>;

fn header_error(row: usize, column: &str, message: impl Into<String>) -> RowError {
    RowError {
        row,
        column: Some(column.to_string()),
        message: message.into(),
        limit: false,
    }
}

/// The ADR 0029 rules: the header names the known columns.
fn bind_by_name(
    columns: &[String],
    known: &[&str],
    required: &[&str],
    row: usize,
) -> (Fields, Vec<RowError>) {
    let mut errors = Vec::new();
    let mut seen = HashSet::new();
    for c in columns {
        if !known.contains(&c.as_str()) {
            errors.push(header_error(
                row,
                c,
                format!("unknown column; known columns are {}", known.join(", ")),
            ));
        } else if !seen.insert(c.as_str()) {
            errors.push(header_error(row, c, "column appears twice"));
        }
    }
    for r in required {
        if !columns.iter().any(|c| c == r) {
            errors.push(header_error(row, r, "required column is missing"));
        }
    }
    (columns.iter().cloned().map(Some).collect(), errors)
}

/// The mapping rules: `file column -> field`, unmapped file columns are ignored.
fn bind_by_mapping(
    columns: &[String],
    known: &[&str],
    required: &[&str],
    mapping: &[(String, String)],
    row: usize,
) -> (Fields, Vec<RowError>) {
    let mut errors = Vec::new();
    let mut fields: Fields = vec![None; columns.len()];
    // field -> the file columns mapped to it; file column -> its field.
    let mut by_field: Vec<(String, Vec<String>)> = Vec::new();
    let mut by_column: HashMap<String, String> = HashMap::new();
    for (file, field) in mapping {
        let (file, field) = (file.trim().to_lowercase(), field.trim().to_lowercase());
        if by_column.get(&file) == Some(&field) {
            continue; // the same pair twice
        }
        if !known.contains(&field.as_str()) {
            errors.push(header_error(
                row,
                &field,
                format!("unknown field; known fields are {}", known.join(", ")),
            ));
            continue;
        }
        let occurrences = columns.iter().filter(|c| **c == file).count();
        if occurrences == 0 {
            errors.push(header_error(row, &file, "mapped column is not in the file"));
            continue;
        }
        if occurrences > 1 {
            errors.push(header_error(row, &file, "column appears twice"));
            continue;
        }
        if let Some(other) = by_column.get(&file) {
            errors.push(header_error(
                row,
                &file,
                format!("column is mapped to both {other} and {field}"),
            ));
            continue;
        }
        by_column.insert(file.clone(), field.clone());
        match by_field.iter_mut().find(|(f, _)| *f == field) {
            Some((_, files)) => files.push(file),
            None => by_field.push((field, vec![file])),
        }
    }
    for (field, files) in &by_field {
        if files.len() > 1 {
            errors.push(header_error(
                row,
                field,
                format!(
                    "field is mapped from more than one column: {}",
                    files.join(", ")
                ),
            ));
        }
    }
    for (i, c) in columns.iter().enumerate() {
        fields[i] = by_column.get(c).cloned();
    }
    for r in required {
        if !by_field.iter().any(|(f, _)| f == r) {
            errors.push(header_error(row, r, "required field is not mapped"));
        }
    }
    (fields, errors)
}

/// What a cell holds: the column is not in the file, the cell is empty, or it has a value.
#[derive(Debug, Clone, PartialEq)]
pub enum Cell<T> {
    Absent,
    Blank,
    Value(T),
}

impl<T> Cell<T> {
    /// Sets a required field: only a value changes it (blank and absent keep the current one).
    pub fn apply(self, target: &mut T) {
        if let Cell::Value(v) = self {
            *target = v;
        }
    }

    /// Sets an optional field: a value sets it, a blank cell clears it, an absent column keeps it.
    pub fn apply_opt(self, target: &mut Option<T>) {
        match self {
            Cell::Value(v) => *target = Some(v),
            Cell::Blank => *target = None,
            Cell::Absent => {}
        }
    }

    /// The value, if the cell has one.
    pub fn value(self) -> Option<T> {
        match self {
            Cell::Value(v) => Some(v),
            _ => None,
        }
    }
}

/// Typed access to the cells of one row; parse problems are recorded as row errors.
///
/// Text cells ([`Cells::text`]) keep their surrounding spaces, so an exported value comes back
/// exactly as it was; an empty cell is blank, a cell of only spaces is a value (it must not clear
/// or change a stored value of that kind). Numbers, booleans and codes/keywords
/// ([`Cells::trimmed`], [`Cells::decimal`], ...) are read without surrounding spaces, and there a
/// cell of only spaces is blank.
///
/// A spreadsheet cell keeps its type: a number cell is a number for [`Cells::decimal`] and
/// [`Cells::int`] and is the text `1000` (not `1000.0`) for [`Cells::text`]; a date cell is the
/// text `2024-01-31`; a boolean cell is a boolean for [`Cells::boolean`] (the numbers 1 and 0
/// too) and `true`/`false` as text. A text cell is read under the CSV rules everywhere.
pub struct Cells<'a> {
    row: &'a Row,
    errors: &'a mut Vec<RowError>,
}

impl<'a> Cells<'a> {
    /// Typed access to `row`; problems are pushed onto `errors`.
    pub fn new(row: &'a Row, errors: &'a mut Vec<RowError>) -> Self {
        Cells { row, errors }
    }

    /// How many errors have been recorded so far (in the whole import).
    pub fn error_count(&self) -> usize {
        self.errors.len()
    }

    /// Records a problem with the row (`column` None = the row as a whole).
    pub fn error(&mut self, column: Option<&str>, message: impl Into<String>) {
        self.errors.push(RowError {
            row: self.row.line,
            column: column.map(str::to_string),
            message: message.into(),
            limit: false,
        });
    }

    /// Whether an error for `column` was recorded since the count was `since`
    /// (see [`Cells::error_count`]).
    pub fn failed_since(&self, since: usize, column: &str) -> bool {
        self.errors[since..]
            .iter()
            .any(|e| e.column.as_deref() == Some(column))
    }

    /// Records one error per validation message, on the first of `columns` the message starts
    /// with (the row as a whole when none). The rules of the API name their field first.
    pub fn problems(&mut self, messages: impl IntoIterator<Item = String>, columns: &[&str]) {
        for m in messages {
            let column = columns.iter().find(|c| m.starts_with(**c)).copied();
            self.error(column, m);
        }
    }

    fn raw(&self, column: &str) -> Cell<&'a CellValue> {
        match self.row.cells.get(column) {
            None => Cell::Absent,
            Some(CellValue::Empty) => Cell::Blank,
            Some(v) => Cell::Value(v),
        }
    }

    /// The cell as text, spaces kept.
    fn raw_text(&self, column: &str) -> Cell<&'a str> {
        match self.raw(column) {
            Cell::Absent => Cell::Absent,
            Cell::Blank => Cell::Blank,
            Cell::Value(CellValue::Text(s)) => Cell::Value(s),
            Cell::Value(_) => match self.row.rendered.get(column) {
                Some(s) => Cell::Value(s),
                None => Cell::Blank,
            },
        }
    }

    fn trimmed_raw(&self, column: &str) -> Cell<&'a str> {
        match self.raw_text(column) {
            Cell::Value(v) if v.trim().is_empty() => Cell::Blank,
            Cell::Value(v) => Cell::Value(v.trim()),
            other => other,
        }
    }

    /// A free text cell, exactly as written.
    pub fn text(&self, column: &str) -> Cell<String> {
        match self.raw_text(column) {
            Cell::Absent => Cell::Absent,
            Cell::Blank => Cell::Blank,
            Cell::Value(v) => Cell::Value(v.to_string()),
        }
    }

    /// A code or keyword cell: surrounding spaces removed, only spaces = blank.
    pub fn trimmed(&self, column: &str) -> Cell<String> {
        match self.trimmed_raw(column) {
            Cell::Absent => Cell::Absent,
            Cell::Blank => Cell::Blank,
            Cell::Value(v) => Cell::Value(v.to_string()),
        }
    }

    /// Reads a typed cell: `typed` handles the cell types other than text, `parse` the text.
    fn parsed<T>(
        &mut self,
        column: &str,
        typed: impl Fn(&CellValue, &str) -> Result<T, String>,
        parse: impl Fn(&str) -> Result<T, String>,
    ) -> Cell<T> {
        let result = match self.raw(column) {
            Cell::Absent => return Cell::Absent,
            Cell::Blank => return Cell::Blank,
            Cell::Value(CellValue::Text(_)) => match self.trimmed_raw(column) {
                Cell::Value(v) => parse(v),
                _ => return Cell::Blank,
            },
            Cell::Value(v) => {
                let shown = self.row.rendered.get(column).map(String::as_str);
                typed(v, shown.unwrap_or(""))
            }
        };
        match result {
            Ok(t) => Cell::Value(t),
            Err(m) => {
                self.error(Some(column), m);
                Cell::Absent
            }
        }
    }

    /// A decimal cell: a number cell, or text under the rules of [`parse_decimal`].
    pub fn decimal(&mut self, column: &str) -> Cell<Decimal> {
        self.parsed(
            column,
            |v, shown| match v {
                CellValue::Number(d) => Ok(*d),
                _ => Err(format!("{shown:?} is not a number")),
            },
            parse_decimal,
        )
    }

    /// A whole number cell: a number cell without a fraction, or text.
    pub fn int(&mut self, column: &str) -> Cell<i32> {
        self.parsed(
            column,
            |v, shown| match v {
                CellValue::Number(d) if d.fract().is_zero() => d
                    .to_i32()
                    .ok_or_else(|| format!("{shown:?} is out of range")),
                _ => Err(format!("{shown:?} is not a whole number")),
            },
            |v| {
                v.parse()
                    .map_err(|_| format!("{v:?} is not a whole number"))
            },
        )
    }

    /// A boolean cell: a boolean cell, the numbers 1 and 0, or text under the rules of
    /// [`parse_bool`].
    pub fn boolean(&mut self, column: &str) -> Cell<bool> {
        self.parsed(
            column,
            |v, shown| match v {
                CellValue::Bool(b) => Ok(*b),
                CellValue::Number(d) if *d == Decimal::ONE => Ok(true),
                CellValue::Number(d) if d.is_zero() => Ok(false),
                _ => Err(format!("{shown:?} is not true or false")),
            },
            parse_bool,
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::import::RawRow;
    use chrono::NaiveDate;
    use rust_decimal_macros::dec;

    fn raw(header: &[&str], rows: Vec<(usize, Vec<CellValue>)>) -> RawTable {
        RawTable {
            sheets: vec![],
            header_row: 1,
            header: header.iter().map(|h| h.to_string()).collect(),
            rows: rows
                .into_iter()
                .map(|(row, cells)| RawRow { row, cells })
                .collect(),
            ..Default::default()
        }
    }

    fn map(pairs: &[(&str, &str)]) -> Vec<(String, String)> {
        pairs
            .iter()
            .map(|(a, b)| (a.to_string(), b.to_string()))
            .collect()
    }

    fn messages(e: &[RowError]) -> Vec<String> {
        e.iter()
            .map(|e| format!("{}: {}", e.column.as_deref().unwrap_or("-"), e.message))
            .collect()
    }

    const KNOWN: [&str; 3] = ["code", "name", "price"];

    #[test]
    fn without_a_mapping_the_header_rules_apply() {
        let e = bind(
            raw(&["Code", "bogus", "code"], vec![]),
            &KNOWN,
            &["code", "name"],
            None,
        )
        .unwrap_err();
        let m = messages(&e);
        assert!(m.iter().any(|m| m.starts_with("bogus: unknown column")));
        assert!(m.contains(&"code: column appears twice".to_string()));
        assert!(m.contains(&"name: required column is missing".to_string()));
        assert!(e.iter().all(|e| e.row == 1));
    }

    #[test]
    fn a_mapping_picks_columns_and_ignores_the_rest() {
        let t = bind(
            raw(
                &[" Item No ", "Description", "Remark"],
                vec![(
                    4,
                    vec![
                        CellValue::text("A1"),
                        CellValue::text("Widget"),
                        CellValue::text("x"),
                    ],
                )],
            ),
            &KNOWN,
            &["code"],
            Some(&map(&[("item no", "code"), (" DESCRIPTION", "Name")])),
        )
        .unwrap();
        assert_eq!(t.columns, ["code", "name"]);
        assert_eq!(t.rows[0].line, 4);
        assert_eq!(t.rows[0].get("code"), Some("A1"));
        assert_eq!(t.rows[0].get("name"), Some("Widget"));
        assert_eq!(t.rows[0].get("remark"), None);
        assert!(!t.has("price"));
    }

    #[test]
    fn mapping_errors_are_all_reported() {
        let header = ["a", "b", "c", "d"];
        let e = bind(
            raw(&header, vec![]),
            &KNOWN,
            &["code", "name"],
            Some(&map(&[
                ("a", "code"),
                ("b", "code"),
                ("c", "bogus"),
                ("zzz", "price"),
                ("d", "price"),
                ("d", "name"),
            ])),
        )
        .unwrap_err();
        let m = messages(&e);
        assert!(m
            .iter()
            .any(|m| m.starts_with("code: field is mapped from more than one column")));
        assert!(m.iter().any(|m| m.starts_with("bogus: unknown field")));
        assert!(m.contains(&"zzz: mapped column is not in the file".to_string()));
        assert!(m
            .iter()
            .any(|m| m.starts_with("d: column is mapped to both price and name")));
        assert!(m.contains(&"name: required field is not mapped".to_string()));
    }

    #[test]
    fn a_missing_required_field_and_duplicate_file_columns_are_errors() {
        let e = bind(
            raw(&["a", "A"], vec![]),
            &KNOWN,
            &["name"],
            Some(&map(&[("a", "code")])),
        )
        .unwrap_err();
        let m = messages(&e);
        assert!(m.contains(&"a: column appears twice".to_string()));
        assert!(m.contains(&"name: required field is not mapped".to_string()));
    }

    #[test]
    fn rows_of_the_wrong_width_are_errors_in_every_format() {
        let n = CellValue::text;
        let t = bind(
            raw(
                &["code", "name"],
                vec![
                    (2, vec![n("a"), n("b")]),
                    (3, vec![n("a")]),
                    (4, vec![n("a"), n("b"), n("extra")]),
                    (5, vec![n("a"), n("b"), CellValue::Text("  ".into())]),
                    (6, vec![n("a"), n("b"), CellValue::Number(dec!(1))]),
                ],
            ),
            &KNOWN,
            &[],
            None,
        )
        .unwrap();
        let lines: Vec<_> = t.rows.iter().map(|r| r.line).collect();
        assert_eq!(lines, [2, 5]);
        let bad: Vec<_> = t.width_errors.iter().map(|e| e.row).collect();
        assert_eq!(bad, [3, 4, 6]);
    }

    fn one(header: &str, value: CellValue) -> Table {
        bind(
            raw(&[header], vec![(2, vec![value])]),
            &["v"],
            &[],
            Some(&map(&[(header, "v")])),
        )
        .unwrap()
    }

    #[test]
    fn text_fields_accept_every_cell_type() {
        let d = NaiveDate::from_ymd_opt(2024, 1, 31).unwrap();
        for (value, expected) in [
            (CellValue::Number(dec!(1000)), "1000"),
            (CellValue::Number(dec!(12.50)), "12.5"),
            (CellValue::Number(dec!(-3)), "-3"),
            (CellValue::Bool(true), "true"),
            (CellValue::Bool(false), "false"),
            (CellValue::Date(d), "2024-01-31"),
            (
                CellValue::DateTime(d.and_hms_opt(8, 5, 0).unwrap()),
                "2024-01-31T08:05:00",
            ),
            (CellValue::Text("  a b ".into()), "  a b "),
            (CellValue::Text("  ".into()), "  "),
        ] {
            let t = one("v", value);
            let mut errors = vec![];
            let cells = Cells::new(&t.rows[0], &mut errors);
            assert_eq!(cells.text("v"), Cell::Value(expected.to_string()));
            match cells.trimmed("v") {
                Cell::Value(v) => assert_eq!(v, expected.trim()),
                other => {
                    assert!(expected.trim().is_empty(), "{other:?}");
                    assert_eq!(other, Cell::Blank);
                }
            }
            assert!(errors.is_empty());
        }
        let t = one("v", CellValue::Empty);
        let mut errors = vec![];
        let cells = Cells::new(&t.rows[0], &mut errors);
        assert_eq!(cells.text("v"), Cell::Blank);
        assert_eq!(cells.text("other"), Cell::Absent);
    }

    #[test]
    fn number_and_int_fields() {
        let mut errors = vec![];
        for (value, dec, int) in [
            (CellValue::Number(dec!(7.5)), Some(dec!(7.5)), None),
            (CellValue::Number(dec!(12)), Some(dec!(12)), Some(12)),
            (CellValue::Text(" 12,5 ".into()), Some(dec!(12.5)), None),
            (CellValue::Text("12".into()), Some(dec!(12)), Some(12)),
            (CellValue::Text("abc".into()), None, None),
            (CellValue::Bool(true), None, None),
            (
                CellValue::Number(dec!(5000000000)),
                Some(dec!(5000000000)),
                None,
            ),
        ] {
            let t = one("v", value.clone());
            let mut e1 = vec![];
            let mut cells = Cells::new(&t.rows[0], &mut e1);
            assert_eq!(cells.decimal("v").value(), dec, "{value:?}");
            let mut e2 = vec![];
            let mut cells = Cells::new(&t.rows[0], &mut e2);
            assert_eq!(cells.int("v").value(), int, "{value:?}");
            errors.extend(e1);
        }
        assert_eq!(errors.len(), 2); // "abc" and true are not numbers
        let t = one("v", CellValue::Text("   ".into()));
        let mut e = vec![];
        assert_eq!(Cells::new(&t.rows[0], &mut e).decimal("v"), Cell::Blank);
        assert!(e.is_empty());
    }

    #[test]
    fn a_number_with_a_fraction_is_not_a_whole_number() {
        let t = one("v", CellValue::Number(dec!(1.5)));
        let mut e = vec![];
        assert_eq!(Cells::new(&t.rows[0], &mut e).int("v"), Cell::Absent);
        assert_eq!(e[0].column.as_deref(), Some("v"));
        assert!(e[0].message.contains("not a whole number"));
        assert_eq!(e[0].row, 2);
    }

    #[test]
    fn boolean_fields() {
        for (value, expected) in [
            (CellValue::Bool(true), Some(true)),
            (CellValue::Bool(false), Some(false)),
            (CellValue::Number(dec!(1)), Some(true)),
            (CellValue::Number(dec!(0)), Some(false)),
            (CellValue::Number(dec!(2)), None),
            (CellValue::Text("Yes".into()), Some(true)),
            (CellValue::Text(" n ".into()), Some(false)),
            (CellValue::Text("maybe".into()), None),
            (
                CellValue::Date(NaiveDate::from_ymd_opt(2024, 1, 1).unwrap()),
                None,
            ),
        ] {
            let t = one("v", value.clone());
            let mut e = vec![];
            assert_eq!(
                Cells::new(&t.rows[0], &mut e).boolean("v").value(),
                expected,
                "{value:?}"
            );
            assert_eq!(e.is_empty(), expected.is_some(), "{value:?}");
        }
    }

    #[test]
    fn reader_errors_are_kept_with_the_width_errors() {
        let mut r = raw(&["code"], vec![(3, vec![CellValue::text("a")])]);
        r.errors.push(RowError {
            row: 2,
            column: Some("code".into()),
            message: "the cell holds the spreadsheet error #N/A".into(),
            limit: false,
        });
        let t = bind(r, &KNOWN, &[], None).unwrap();
        assert_eq!(t.rows.len(), 1);
        assert_eq!(t.width_errors[0].row, 2);
    }
}
