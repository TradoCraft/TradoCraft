//! CSV building blocks shared by the exports and imports: RFC 4180 writing and reading, delimiter
//! detection, typed cell parsing (decimal comma) and the common import report.
//!
//! An import is always all-or-nothing: every row is checked first and *all* row errors are
//! reported together ([`ImportReport`]); nothing is written unless there are none.

use axum::http::{header, HeaderMap, HeaderValue, StatusCode};
use axum::Json;
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use utoipa::{IntoParams, ToSchema};

use crate::error::{AppError, AppResult};
use crate::import::{self, Limits};

// One table type serves every format; the CSV names stay for the entity importers.
pub use crate::import::{bind, Cell, Cells, Row as CsvRow, Table as CsvTable};

/// Largest accepted import body.
pub const MAX_BODY_BYTES: usize = 5 * 1024 * 1024;
/// Largest accepted number of data rows in an import.
pub const MAX_ROWS: usize = 20_000;
/// Largest accepted number of cells in one record (the widest known file has 19 columns).
pub const MAX_COLUMNS: usize = 100;
/// How often an import is planned again when a concurrent writer wins a unique key between the
/// planning and the write (see [`with_replan`]).
pub const MAX_PLAN_ATTEMPTS: usize = 3;

// ---------------------------------------------------------------------------------------------
// Writing
// ---------------------------------------------------------------------------------------------

/// One cell, quoted when needed. A value that would run as a formula in a spreadsheet gets a
/// leading apostrophe; [`unquote_formula`] undoes that on import. A literal value that starts with
/// apostrophes followed by a formula character (`'=x`) is protected the same way (`''=x`), so the
/// two cases stay distinguishable and every value round-trips exactly.
pub fn quote_cell(value: &str) -> String {
    let value = if needs_protection(value) {
        format!("'{value}")
    } else {
        value.to_string()
    };
    if value.contains([',', '"', '\n', '\r', ';']) {
        format!("\"{}\"", value.replace('"', "\"\""))
    } else {
        value
    }
}

const FORMULA_START: [char; 6] = ['=', '+', '-', '@', '\t', '\r'];

/// True when the value, after any leading apostrophes, starts like a formula. Such a value is
/// exported with one more apostrophe in front.
fn needs_protection(value: &str) -> bool {
    value.trim_start_matches('\'').starts_with(FORMULA_START)
}

/// Removes the one apostrophe [`quote_cell`] added; any other value is returned as it is.
pub(crate) fn unquote_formula(value: &str) -> &str {
    match value.strip_prefix('\'') {
        Some(rest) if needs_protection(value) => rest,
        _ => value,
    }
}

/// A CSV document: comma separated, CRLF lines, header row first, no byte order mark.
pub fn write_csv(header: &[&str], rows: impl IntoIterator<Item = Vec<String>>) -> String {
    let mut out = header.join(",");
    out.push_str("\r\n");
    for r in rows {
        out.push_str(
            &r.iter()
                .map(|c| quote_cell(c))
                .collect::<Vec<_>>()
                .join(","),
        );
        out.push_str("\r\n");
    }
    out
}

/// Headers and body of a CSV download.
pub fn download(filename: &str, body: String) -> (HeaderMap, String) {
    let mut headers = HeaderMap::new();
    headers.insert(
        header::CONTENT_TYPE,
        HeaderValue::from_static("text/csv; charset=utf-8"),
    );
    headers.insert(
        header::CONTENT_DISPOSITION,
        HeaderValue::from_str(&format!("attachment; filename=\"{filename}\""))
            .unwrap_or_else(|_| HeaderValue::from_static("attachment")),
    );
    (headers, body)
}

// ---------------------------------------------------------------------------------------------
// Report
// ---------------------------------------------------------------------------------------------

/// One problem in an import file.
#[derive(Debug, Clone, Serialize, ToSchema, PartialEq, Eq)]
pub struct RowError {
    /// Line in the file where the row starts (the header is line 1).
    pub row: usize,
    /// Column name; null when the problem concerns the whole row.
    pub column: Option<String>,
    pub message: String,
}

/// Outcome of an import (or of its dry run). `errors` is empty on success; with errors nothing was
/// written and the counts are 0.
#[derive(Debug, Default, Serialize, ToSchema)]
pub struct ImportReport {
    pub created: usize,
    pub updated: usize,
    pub unchanged: usize,
    pub errors: Vec<RowError>,
}

impl ImportReport {
    /// The report of a planned import: the counts are filled in by the caller. `width_errors` (rows
    /// the parser could not use) and `plan_errors` (found while checking the other rows) are
    /// combined in file order.
    pub fn planned(
        unchanged: usize,
        width_errors: &[RowError],
        plan_errors: Vec<RowError>,
    ) -> Self {
        let mut errors = width_errors.to_vec();
        errors.extend(plan_errors);
        errors.sort_by_key(|e| e.row);
        ImportReport {
            unchanged,
            errors,
            ..Default::default()
        }
    }

    /// 200 with the counts, or 422 with the errors.
    pub fn into_response(mut self) -> (StatusCode, Json<ImportReport>) {
        if self.errors.is_empty() {
            (StatusCode::OK, Json(self))
        } else {
            self.created = 0;
            self.updated = 0;
            self.unchanged = 0;
            (StatusCode::UNPROCESSABLE_ENTITY, Json(self))
        }
    }

    /// A report of an import that was rejected before planning (nothing is counted).
    pub fn failed(errors: Vec<RowError>) -> Self {
        ImportReport {
            errors,
            ..Default::default()
        }
    }
}

/// Runs an import attempt and runs it again (a fresh plan in a fresh transaction) when it fails
/// with a conflict: a concurrent writer took a unique key (a barcode, a new code) or changed the
/// stock after the plan was made. The new plan sees the committed data and reports the conflict as
/// a row error or turns the create into an update. After [`MAX_PLAN_ATTEMPTS`] the conflict is
/// returned as it is.
pub async fn with_replan<T, F, Fut>(mut attempt: F) -> AppResult<T>
where
    F: FnMut() -> Fut,
    Fut: std::future::Future<Output = AppResult<T>>,
{
    let mut tries = 1;
    loop {
        match attempt().await {
            Err(AppError::Conflict(_)) if tries < MAX_PLAN_ATTEMPTS => tries += 1,
            result => return result,
        }
    }
}

/// Query parameters of the import endpoints.
#[derive(Debug, Deserialize, IntoParams)]
pub struct ImportParams {
    /// Validate and count only; nothing is written.
    #[serde(default)]
    pub dry_run: bool,
    /// The sheet to read from an XLSX or ODS file (the first sheet when absent); ignored for CSV.
    pub sheet: Option<String>,
}

// ---------------------------------------------------------------------------------------------
// Reading
// ---------------------------------------------------------------------------------------------

/// The delimiter of a file: `;` when the header line has more semicolons than commas (Excel in
/// many locales), else `,`.
pub fn detect_delimiter(text: &str) -> char {
    let (mut commas, mut semis, mut quoted) = (0, 0, false);
    for c in text.chars() {
        match c {
            '"' => quoted = !quoted,
            '\n' if !quoted => break,
            ',' if !quoted => commas += 1,
            ';' if !quoted => semis += 1,
            _ => {}
        }
    }
    if semis > commas {
        ';'
    } else {
        ','
    }
}

/// A format error of the file as a whole at `row`.
pub(crate) fn format_error(row: usize, message: impl Into<String>) -> RowError {
    RowError {
        row,
        column: None,
        message: message.into(),
    }
}

/// Parses an import body as CSV and binds it to the entity's columns (ADR 0029). Header problems
/// (unknown, duplicate or missing columns, an empty file, too many rows or columns, malformed
/// quoting, bad encoding) are returned as errors on line 1 / the offending line. A data row with a
/// different number of cells than the header is a row error (extra cells are tolerated when they
/// are all empty) and is left out of the table; the other rows are kept. Cell values are not
/// trimmed (see [`Cells`]); header names are.
///
/// This is the CSV-only entry point with the limits of one request; the other formats, the column
/// mapping and the job limits are in [`crate::import`].
pub fn parse_table(
    body: &[u8],
    known: &[&str],
    required: &[&str],
) -> Result<CsvTable, Vec<RowError>> {
    let raw = import::csv::read(body, &Limits::request())?;
    import::bind(raw, known, required, None)
}

/// A decimal with `.` or `,` as the decimal separator. Thousands separators are not accepted, so
/// `1,234` is 1.234 and `1.234,5` is rejected rather than guessed. A value that does not fit a
/// [`Decimal`] exactly (more than 28 decimals or 28 digits) is rejected, never rounded.
pub fn parse_decimal(v: &str) -> Result<Decimal, String> {
    let bad = || format!("{v:?} is not a number");
    if v.contains(',') && v.contains('.') {
        return Err(format!(
            "{v:?} is ambiguous: use a single decimal separator and no thousands separator"
        ));
    }
    let norm = v.replace(',', ".");
    Decimal::from_str_exact(&norm).map_err(|_| match norm.parse::<Decimal>() {
        Ok(_) => format!("{v:?} has more digits than can be stored without rounding"),
        Err(_) => bad(),
    })
}

/// A boolean: `true/false/1/0/yes/no/y/n`, any case.
pub fn parse_bool(v: &str) -> Result<bool, String> {
    match v.to_lowercase().as_str() {
        "true" | "1" | "yes" | "y" => Ok(true),
        "false" | "0" | "no" | "n" => Ok(false),
        _ => Err(format!("{v:?} is not true or false")),
    }
}

/// Decimal as written by exports: plain, no exponent, `.` separator, trailing zeros trimmed.
pub fn format_decimal(d: Decimal) -> String {
    d.normalize().to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn quoting_and_formula_guard_round_trip() {
        assert_eq!(quote_cell("plain"), "plain");
        assert_eq!(quote_cell("a,b"), "\"a,b\"");
        assert_eq!(quote_cell("say \"hi\""), "\"say \"\"hi\"\"\"");
        assert_eq!(quote_cell("+32 9"), "'+32 9");
        let t = parse_table(
            write_csv(
                &["code", "name"],
                [vec!["a".into(), "+32 9\n\"x\", y".into()]],
            )
            .as_bytes(),
            &["code", "name"],
            &["code"],
        )
        .unwrap();
        assert_eq!(t.rows[0].get("name").unwrap(), "+32 9\n\"x\", y");
    }

    #[test]
    fn delimiter_bom_order_and_line_numbers() {
        let text = "\u{feff} Name ;CODE\r\n\r\nAlpha;a1\r\n\"B;eta\";b2\r\n";
        assert_eq!(detect_delimiter(text), ';');
        let t = parse_table(text.as_bytes(), &["code", "name"], &["code"]).unwrap();
        assert_eq!(t.columns, ["name", "code"]);
        assert_eq!(t.rows.len(), 2);
        assert_eq!((t.rows[0].line, t.rows[1].line), (3, 4));
        assert_eq!(t.rows[1].get("name").unwrap(), "B;eta");
    }

    #[test]
    fn header_problems_are_all_reported() {
        let e =
            parse_table(b"code,bogus,code\n", &["code", "name"], &["code", "name"]).unwrap_err();
        let msgs: Vec<_> = e.iter().map(|e| e.message.as_str()).collect();
        assert!(msgs.iter().any(|m| m.starts_with("unknown column")));
        assert!(msgs.contains(&"column appears twice"));
        assert!(msgs.contains(&"required column is missing"));
        assert!(parse_table(b"", &["code"], &[]).is_err());
        assert!(parse_table(b"code\n\"open", &["code"], &[]).is_err());
    }

    #[test]
    fn decimals_and_bools() {
        assert_eq!(parse_decimal("12,5").unwrap(), Decimal::new(125, 1));
        assert_eq!(parse_decimal("12.5").unwrap(), Decimal::new(125, 1));
        assert!(parse_decimal("1.234,5").is_err());
        assert!(parse_decimal("abc").is_err());
        assert_eq!(format_decimal(Decimal::new(21_00, 2)), "21");
        assert!(parse_bool("Yes").unwrap());
        assert!(parse_bool("maybe").is_err());
    }

    fn one_column(values: &[&str]) -> Vec<String> {
        let csv = write_csv(&["v"], values.iter().map(|v| vec![v.to_string()]));
        let t = parse_table(csv.as_bytes(), &["v"], &["v"]).unwrap();
        assert!(t.width_errors.is_empty());
        t.rows
            .iter()
            .map(|r| r.get("v").unwrap().to_string())
            .collect()
    }

    #[test]
    fn formulas_and_literal_apostrophes_are_distinguishable() {
        assert_eq!(quote_cell("=1+1"), "'=1+1");
        assert_eq!(quote_cell("'=Literal"), "''=Literal");
        assert_eq!(quote_cell("''-x"), "'''-x");
        assert_eq!(quote_cell("'plain"), "'plain");
        assert_eq!(quote_cell("'"), "'");
        assert_eq!(quote_cell(" =x"), " =x");
        let values = [
            "=1+1",
            "'=Literal",
            "''=Literal",
            "'+1",
            "'plain",
            "'",
            "''",
            "@a",
            "-5",
            " =x",
            "a'=b",
            "\t x",
        ];
        assert_eq!(one_column(&values), values);
    }

    #[test]
    fn cells_keep_their_surrounding_spaces() {
        let t = parse_table(b"v,w\n  a b  , \n", &["v", "w"], &["v"]).unwrap();
        assert_eq!(t.rows[0].get("v").unwrap(), "  a b  ");
        assert_eq!(t.rows[0].get("w").unwrap(), " ");
        let mut errors = Vec::new();
        let mut cells = Cells::new(&t.rows[0], &mut errors);
        assert_eq!(cells.text("w"), Cell::Value(" ".to_string()));
        assert_eq!(cells.trimmed("v"), Cell::Value("a b".to_string()));
        assert_eq!(cells.trimmed("w"), Cell::Blank);
        assert_eq!(cells.decimal("w"), Cell::Blank);
        assert!(errors.is_empty());
    }

    #[test]
    fn rows_of_the_wrong_width_are_errors_but_the_other_rows_are_kept() {
        let t = parse_table(
            b"a,b,c\n1,2,3\n4,5\n6,7,8,9\n10,11,12,\n13,14,15,  \n\n",
            &["a", "b", "c"],
            &["a"],
        )
        .unwrap();
        let lines: Vec<_> = t.rows.iter().map(|r| r.line).collect();
        assert_eq!(lines, [2, 5, 6]);
        let bad: Vec<_> = t.width_errors.iter().map(|e| e.row).collect();
        assert_eq!(bad, [3, 4]);
        assert!(t.width_errors[0].message.contains("2 values"));
    }

    #[test]
    fn quoting_must_be_well_formed() {
        for text in [
            "v\nab\"cd\"\n",
            "v\n\"ab\"cd\n",
            "v\n\"ab\" \n",
            "v\n a\"b\n",
            "v\n\"ab\"\"\n",
        ] {
            let e = parse_table(text.as_bytes(), &["v"], &[]).unwrap_err();
            assert_eq!(e.len(), 1, "{text:?}");
            assert_eq!(e[0].row, 2, "{text:?}");
        }
        // Valid: quoted delimiters, escaped quotes, empty quoted value, quote then CRLF.
        let t = parse_table(b"v,w\r\n\"a,\"\"b\"\"\",\"\"\r\n", &["v", "w"], &["v"]).unwrap();
        assert_eq!(t.rows[0].get("v").unwrap(), "a,\"b\"");
        assert_eq!(t.rows[0].get("w").unwrap(), "");
    }

    #[test]
    fn row_and_column_limits_stop_the_parse() {
        let mut ok = String::from("v\n");
        ok.push_str(&"x\n".repeat(MAX_ROWS));
        let t = parse_table(ok.as_bytes(), &["v"], &[]).unwrap();
        assert_eq!(t.rows.len(), MAX_ROWS);
        let e = parse_table(format!("{ok}x\n").as_bytes(), &["v"], &[]).unwrap_err();
        assert_eq!(e.len(), 1);
        assert!(e[0].message.contains("too many rows"));

        // Hundreds of unknown columns give one bounded error, not one error per column.
        let wide = vec!["c"; MAX_COLUMNS + 1].join(",");
        let e = parse_table(format!("{wide}\n").as_bytes(), &["v"], &[]).unwrap_err();
        assert_eq!(e.len(), 1);
        assert!(e[0].message.contains("too many columns"));
    }

    #[test]
    fn decimals_never_lose_precision() {
        let exact = "0.1234567890123456789012345678";
        assert_eq!(parse_decimal(exact).unwrap().to_string(), exact);
        assert_eq!(parse_decimal("21,50").unwrap().to_string(), "21.50");
        let e = parse_decimal("21.1234567890123456789012345678901").unwrap_err();
        assert!(e.contains("more digits"), "{e}");
        assert!(parse_decimal("1e").unwrap_err().contains("not a number"));
    }
}
