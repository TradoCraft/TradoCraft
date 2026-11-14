//! Tests of the format layer: detection, readers, writers, limits and archive checks.

use std::io::{Cursor, Read, Write};

use chrono::NaiveDate;
use rust_decimal::Decimal;
use rust_decimal_macros::dec;
use rust_xlsxwriter::{Formula, Workbook};
use zip::write::SimpleFileOptions;
use zip::{CompressionMethod, ZipArchive, ZipWriter};

use super::*;
use crate::csv_io::RowError;

const FOREIGN_XLSX: &[u8] = include_bytes!("../../tests/fixtures/import/foreign.xlsx");
const FOREIGN_ODS: &[u8] = include_bytes!("../../tests/fixtures/import/foreign.ods");

// ---------------------------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------------------------

fn t(s: &str) -> CellValue {
    CellValue::Text(s.to_string())
}

fn n(d: Decimal) -> CellValue {
    CellValue::Number(d)
}

fn date(y: i32, m: u32, d: u32) -> NaiveDate {
    NaiveDate::from_ymd_opt(y, m, d).unwrap()
}

fn raw(bytes: &[u8]) -> RawTable {
    read_raw(bytes, None, &Limits::request()).unwrap().1
}

fn raw_err(bytes: &[u8], sheet: Option<&str>, limits: &Limits) -> Vec<RowError> {
    read_raw(bytes, sheet, limits).unwrap_err()
}

fn zip_of(entries: &[(&str, &[u8])]) -> Vec<u8> {
    let mut zip = ZipWriter::new(Cursor::new(Vec::new()));
    for (name, body) in entries {
        zip.start_file(*name, SimpleFileOptions::default()).unwrap();
        zip.write_all(body).unwrap();
    }
    zip.finish().unwrap().into_inner()
}

/// The archive with one entry's content replaced by `f(content)` (the entry is stored again).
fn rewrite_entry(bytes: &[u8], name: &str, f: impl Fn(String) -> String) -> Vec<u8> {
    let mut zip = ZipArchive::new(Cursor::new(bytes)).unwrap();
    let mut out = ZipWriter::new(Cursor::new(Vec::new()));
    for i in 0..zip.len() {
        let mut entry = zip.by_index(i).unwrap();
        let entry_name = entry.name().unwrap().to_string();
        let mut body = Vec::new();
        entry.read_to_end(&mut body).unwrap();
        if entry_name == name {
            body = f(String::from_utf8(body).unwrap()).into_bytes();
        }
        let method = if entry_name == "mimetype" {
            CompressionMethod::Stored
        } else {
            CompressionMethod::Deflated
        };
        out.start_file(
            entry_name,
            SimpleFileOptions::default().compression_method(method),
        )
        .unwrap();
        out.write_all(&body).unwrap();
    }
    out.finish().unwrap().into_inner()
}

/// Changes the uncompressed size an entry declares, in its local header and in the central
/// directory, leaving the compressed data alone: an archive that lies about its size.
fn declare_size(bytes: &[u8], name: &str, size: u32) -> Vec<u8> {
    let mut out = bytes.to_vec();
    let le32 = |b: &[u8], at: usize| u32::from_le_bytes(b[at..at + 4].try_into().unwrap());
    let le16 = |b: &[u8], at: usize| u16::from_le_bytes(b[at..at + 2].try_into().unwrap()) as usize;
    let eocd = (0..bytes.len() - 3)
        .rev()
        .find(|&i| &bytes[i..i + 4] == b"PK\x05\x06")
        .unwrap();
    let count = le16(bytes, eocd + 10);
    let mut at = le32(bytes, eocd + 16) as usize;
    for _ in 0..count {
        assert_eq!(&bytes[at..at + 4], b"PK\x01\x02");
        let (name_len, extra_len, comment_len) = (
            le16(bytes, at + 28),
            le16(bytes, at + 30),
            le16(bytes, at + 32),
        );
        let entry_name = std::str::from_utf8(&bytes[at + 46..at + 46 + name_len]).unwrap();
        if entry_name == name {
            out[at + 24..at + 28].copy_from_slice(&size.to_le_bytes());
            let local = le32(bytes, at + 42) as usize;
            assert_eq!(&bytes[local..local + 4], b"PK\x03\x04");
            out[local + 22..local + 26].copy_from_slice(&size.to_le_bytes());
            return out;
        }
        at += 46 + name_len + extra_len + comment_len;
    }
    panic!("no entry {name}");
}

/// An ODS file with the given `table:table` elements, built by hand (not by our writer).
fn ods_of(tables: &str) -> Vec<u8> {
    let content = format!(
        r#"<?xml version="1.0" encoding="UTF-8"?>
<office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" xmlns:calcext="urn:org:documentfoundation:names:experimental:calc:xmlns:calcext:1.0" office:version="1.2"><office:body><office:spreadsheet>{tables}</office:spreadsheet></office:body></office:document-content>"#
    );
    let mut zip = ZipWriter::new(Cursor::new(Vec::new()));
    zip.start_file(
        "mimetype",
        SimpleFileOptions::default().compression_method(CompressionMethod::Stored),
    )
    .unwrap();
    zip.write_all(format::ODS_MIMETYPE.as_bytes()).unwrap();
    zip.start_file("META-INF/manifest.xml", SimpleFileOptions::default())
        .unwrap();
    zip.write_all(
        br#"<?xml version="1.0" encoding="UTF-8"?><manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" manifest:version="1.2"><manifest:file-entry manifest:full-path="/" manifest:media-type="application/vnd.oasis.opendocument.spreadsheet"/></manifest:manifest>"#,
    )
    .unwrap();
    zip.start_file("content.xml", SimpleFileOptions::default())
        .unwrap();
    zip.write_all(content.as_bytes()).unwrap();
    zip.finish().unwrap().into_inner()
}

fn s_cell(text: &str) -> String {
    format!(
        r#"<table:table-cell office:value-type="string"><text:p>{text}</text:p></table:table-cell>"#
    )
}

fn f_cell(v: &str) -> String {
    format!(
        r#"<table:table-cell office:value-type="float" office:value="{v}"><text:p>{v}</text:p></table:table-cell>"#
    )
}

fn row(cells: &[String]) -> String {
    format!("<table:table-row>{}</table:table-row>", cells.concat())
}

fn xlsx_with(f: impl FnOnce(&mut rust_xlsxwriter::Worksheet)) -> Vec<u8> {
    let mut wb = Workbook::new();
    f(wb.add_worksheet());
    wb.save_to_buffer().unwrap()
}

const FORMATS: [Format; 2] = [Format::Xlsx, Format::Ods];

fn written(format: Format, header: &[&str], rows: Vec<Vec<CellValue>>) -> Vec<u8> {
    write(format, "Data", header, rows).unwrap()
}

// ---------------------------------------------------------------------------------------------
// Format detection
// ---------------------------------------------------------------------------------------------

#[test]
fn csv_is_everything_that_is_not_a_known_container() {
    for body in [
        &b""[..],
        b"code,name\n1,a\n",
        "\u{feff}a;b\n".as_bytes(),
        b"PK is not a zip",
    ] {
        assert_eq!(detect(body), Ok(Format::Csv), "{body:?}");
    }
}

#[test]
fn xlsx_and_ods_are_found_by_content() {
    let header = ["a"];
    assert_eq!(
        detect(&written(Format::Xlsx, &header, vec![])),
        Ok(Format::Xlsx)
    );
    assert_eq!(
        detect(&written(Format::Ods, &header, vec![])),
        Ok(Format::Ods)
    );
    assert_eq!(detect(FOREIGN_XLSX), Ok(Format::Xlsx));
    assert_eq!(detect(FOREIGN_ODS), Ok(Format::Ods));
    // Macro-enabled workbooks have the same workbook part.
    let xlsm = zip_of(&[
        ("[Content_Types].xml", b"<x/>"),
        ("xl/workbook.xml", b"<x/>"),
        ("xl/vbaProject.bin", b"\0"),
    ]);
    assert_eq!(detect(&xlsm), Ok(Format::Xlsx));
}

#[test]
fn other_containers_are_refused_with_one_clear_message() {
    let ole = [
        &[0xD0u8, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1][..],
        &[0u8; 64],
    ]
    .concat();
    assert!(detect(&ole).unwrap_err().contains(".xls"));
    let xlsb = zip_of(&[("xl/workbook.bin", b"\0")]);
    assert!(detect(&xlsb).unwrap_err().contains(".xlsb"));
    let docx = zip_of(&[
        ("[Content_Types].xml", b"<x/>"),
        ("word/document.xml", b"<x/>"),
    ]);
    assert!(detect(&docx).unwrap_err().contains("not a spreadsheet"));
    let odt = zip_of(&[("mimetype", b"application/vnd.oasis.opendocument.text")]);
    assert!(detect(&odt).unwrap_err().contains("not a spreadsheet"));
    let damaged = [&b"PK\x03\x04"[..], &[7u8; 40]].concat();
    assert!(detect(&damaged).unwrap_err().contains("zip"));
    // The same through the reader: one error, not a CSV parse of binary junk.
    for bytes in [ole, xlsb, docx, odt] {
        assert_eq!(raw_err(&bytes, None, &Limits::request()).len(), 1);
    }
}

#[test]
fn the_format_comes_from_the_bytes_not_a_name() {
    // An XLSX is an XLSX whatever it is called, and the reader never sees a name at all.
    let bytes = written(Format::Xlsx, &["code"], vec![vec![t("a")]]);
    let (format, table) = read_raw(&bytes, None, &Limits::request()).unwrap();
    assert_eq!(format, Format::Xlsx);
    assert_eq!(table.rows.len(), 1);
}

// ---------------------------------------------------------------------------------------------
// Round trips through our writers
// ---------------------------------------------------------------------------------------------

fn texts() -> Vec<String> {
    let mut v: Vec<String> = [
        "00123",
        "=1+1",
        "+32 9",
        "-5",
        "@SUM(A1)",
        "'=quoted",
        "   ",
        " ",
        "  leading",
        "trailing  ",
        "  both  ",
        "a  b   c",
        "ünïcödé ✓ 日本語 😀",
        "line\nbreak",
        "tab\there",
        "<b>&amp; \"quotes\" 'x'</b>",
        "0",
        "1e5",
        "true",
        " \n ",
        "x ",
    ]
    .iter()
    .map(|s| s.to_string())
    .collect();
    v.push("long text ".repeat(3000)); // 30 000 characters
    v
}

#[test]
fn text_round_trips_exactly_in_every_format() {
    for format in FORMATS {
        let rows: Vec<_> = texts().iter().map(|s| vec![t(s)]).collect();
        let table = raw(&written(format, &["t"], rows.clone()));
        assert_eq!(table.rows.len(), rows.len(), "{format:?}");
        for (got, want) in table.rows.iter().zip(&rows) {
            assert_eq!(got.cells, *want, "{format:?}");
        }
        assert_eq!(table.header, ["t"]);
        assert_eq!(table.sheets, ["Data"]);
    }
}

#[test]
fn every_cell_type_round_trips_in_every_format() {
    let moment = date(2024, 1, 31).and_hms_opt(10, 30, 5).unwrap();
    let rows = vec![
        vec![
            t("00123"),
            n(dec!(0.1)),
            CellValue::Bool(true),
            CellValue::Date(date(2024, 1, 31)),
            CellValue::DateTime(moment),
        ],
        vec![
            t("=1+1"),
            n(dec!(7.5)),
            CellValue::Bool(false),
            CellValue::Date(date(1999, 12, 31)),
            CellValue::DateTime(date(2000, 2, 29).and_hms_opt(23, 59, 59).unwrap()),
        ],
        vec![
            CellValue::Empty,
            n(dec!(1234567.89)),
            CellValue::Empty,
            CellValue::Empty,
            CellValue::Empty,
        ],
        vec![
            t("  spaced  "),
            n(dec!(-42)),
            CellValue::Empty,
            CellValue::Date(date(1900, 3, 1)),
            CellValue::Empty,
        ],
        vec![
            t("-"),
            n(dec!(-0.5)),
            CellValue::Empty,
            CellValue::Empty,
            CellValue::Empty,
        ],
        vec![
            t("0"),
            n(dec!(0)),
            CellValue::Empty,
            CellValue::Empty,
            CellValue::Empty,
        ],
        vec![
            t("big"),
            n(dec!(1000000)),
            CellValue::Empty,
            CellValue::Empty,
            CellValue::Empty,
        ],
    ];
    let header = ["text", "num", "flag", "day", "moment"];
    for format in FORMATS {
        let table = raw(&written(format, &header, rows.clone()));
        assert_eq!(table.header, header);
        assert_eq!(table.header_row, 1);
        assert_eq!(table.rows.len(), rows.len(), "{format:?}");
        for (i, (got, want)) in table.rows.iter().zip(&rows).enumerate() {
            assert_eq!(got.row, i + 2);
            assert_eq!(got.cells, *want, "{format:?} row {}", got.row);
        }
    }
}

#[test]
fn a_number_a_double_cannot_hold_is_written_as_text_not_rounded() {
    let long = dec!(0.1234567890123456789012345678);
    for format in FORMATS {
        let table = raw(&written(format, &["v"], vec![vec![n(long)]]));
        assert_eq!(table.rows[0].cells, [t("0.1234567890123456789012345678")]);
    }
}

#[test]
fn csv_written_and_read_back() {
    let rows = vec![vec![
        t("=1+1"),
        n(dec!(12.50)),
        CellValue::Bool(true),
        CellValue::Empty,
    ]];
    let bytes = written(Format::Csv, &["a", "b", "c", "d"], rows);
    assert!(bytes.starts_with(b"a,b,c,d\r\n'=1+1,12.5,true,\r\n"));
    let table = raw(&bytes);
    assert!(table.sheets.is_empty());
    assert_eq!(
        table.rows[0].cells,
        [t("=1+1"), t("12.5"), t("true"), CellValue::Empty]
    );
}

#[test]
fn a_midnight_date_time_reads_back_as_a_date_in_xlsx_only() {
    // Excel stores both as the same serial number; ODS keeps the two apart.
    let midnight = CellValue::DateTime(date(2024, 5, 1).and_hms_opt(0, 0, 0).unwrap());
    let x = raw(&written(Format::Xlsx, &["d"], vec![vec![midnight.clone()]]));
    assert_eq!(x.rows[0].cells, [CellValue::Date(date(2024, 5, 1))]);
    let o = raw(&written(Format::Ods, &["d"], vec![vec![midnight.clone()]]));
    assert_eq!(o.rows[0].cells, [midnight]);
}

#[test]
fn milliseconds_survive() {
    let m = date(2024, 1, 31).and_hms_milli_opt(10, 30, 5, 250).unwrap();
    for format in FORMATS {
        let table = raw(&written(format, &["d"], vec![vec![CellValue::DateTime(m)]]));
        assert_eq!(table.rows[0].cells, [CellValue::DateTime(m)], "{format:?}");
    }
}

#[test]
fn text_cells_are_never_formulas_or_guessed_numbers() {
    // The XLSX holds a shared string, not a formula, and the ODS a string cell.
    let rows = vec![vec![t("=1+1"), t("00123"), t("12")]];
    let x = written(Format::Xlsx, &["a", "b", "c"], rows.clone());
    let mut zip = ZipArchive::new(Cursor::new(&x)).unwrap();
    let mut sheet = String::new();
    zip.by_name("xl/worksheets/sheet1.xml")
        .unwrap()
        .read_to_string(&mut sheet)
        .unwrap();
    assert!(!sheet.contains("<f>"), "{sheet}");
    assert_eq!(sheet.matches(r#"t="s""#).count(), 6);
    let o = written(Format::Ods, &["a", "b", "c"], rows);
    let mut zip = ZipArchive::new(Cursor::new(&o)).unwrap();
    let mut content = String::new();
    zip.by_name("content.xml")
        .unwrap()
        .read_to_string(&mut content)
        .unwrap();
    assert!(!content.contains("table:formula"));
    assert_eq!(content.matches(r#"office:value-type="string""#).count(), 6);
}

#[test]
fn the_ods_container_is_well_formed() {
    let o = written(Format::Ods, &["a"], vec![vec![t("x")]]);
    // `mimetype` first, stored, with no extra field: the type sits right after the file name.
    assert_eq!(&o[..4], b"PK\x03\x04");
    assert_eq!(&o[30..38], b"mimetype");
    let mime = format::ODS_MIMETYPE.as_bytes();
    assert_eq!(&o[38..38 + mime.len()], mime);
    let zip = ZipArchive::new(Cursor::new(&o)).unwrap();
    let names: Vec<_> = zip.file_names().map(|n| n.unwrap().to_string()).collect();
    assert_eq!(names, ["mimetype", "META-INF/manifest.xml", "content.xml"]);
}

#[test]
fn writers_refuse_what_they_cannot_hold() {
    let bad_name = write(Format::Xlsx, "a/b", &["a"], vec![]);
    assert!(bad_name.is_err());
    assert!(write(Format::Ods, "", &["a"], vec![]).is_err());
    assert!(write(Format::Ods, &"x".repeat(32), &["a"], vec![]).is_err());
    // Longer than a spreadsheet cell can hold.
    let too_long = vec![vec![t(&"x".repeat(32_768))]];
    assert!(write(Format::Xlsx, "Data", &["a"], too_long).is_err());
    // A control character XML cannot carry.
    assert!(write(Format::Ods, "Data", &["a"], vec![vec![t("a\u{1}b")]]).is_err());
    // Neither limit applies to CSV.
    assert!(write(Format::Csv, "", &["a"], vec![vec![t(&"x".repeat(40_000))]]).is_ok());
}

#[test]
fn download_headers() {
    let (h, body) = download(Format::Xlsx, "products", vec![1, 2]);
    assert_eq!(
        h["content-type"],
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    );
    assert_eq!(
        h["content-disposition"],
        "attachment; filename=\"products.xlsx\""
    );
    assert_eq!(body, [1, 2]);
    let (h, _) = download(Format::Ods, "p", vec![]);
    assert_eq!(
        h["content-type"],
        "application/vnd.oasis.opendocument.spreadsheet"
    );
    assert_eq!(h["content-disposition"], "attachment; filename=\"p.ods\"");
    let (h, _) = download(Format::Csv, "p", vec![]);
    assert_eq!(h["content-type"], "text/csv; charset=utf-8");
}

// ---------------------------------------------------------------------------------------------
// Foreign files (LibreOffice)
// ---------------------------------------------------------------------------------------------

fn check_foreign(bytes: &[u8]) {
    let (_, table) = read_raw(bytes, None, &Limits::request()).unwrap();
    assert_eq!(table.sheets, ["Products", "Second"]);
    assert_eq!(
        table.header,
        ["Code", "Name", "Price", "Active", "Created", "Total"]
    );
    assert_eq!(table.header_row, 1);
    assert!(table.errors.is_empty());
    let rows: Vec<_> = table
        .rows
        .iter()
        .map(|r| (r.row, r.cells.clone()))
        .collect();
    assert_eq!(
        rows,
        [
            (
                2,
                vec![
                    t("00123"),
                    t("Widget & Co"),
                    n(dec!(7.5)),
                    CellValue::Bool(true),
                    CellValue::Date(date(2024, 1, 31)),
                    n(dec!(15)),
                ]
            ),
            // Rows 3 and 4 are empty and skipped.
            (
                5,
                vec![
                    t("00124"),
                    t("  padded   name "),
                    n(dec!(0.1)),
                    CellValue::Bool(false),
                    CellValue::Empty,
                    n(dec!(0.2)),
                ]
            ),
            (
                6,
                vec![
                    t("=SUM(A1)"),
                    t("caf\u{e9} \u{2013} line\ntwo"),
                    n(dec!(1234567.89)),
                    CellValue::Empty,
                    CellValue::Empty,
                    CellValue::Empty,
                ]
            ),
        ]
    );
    let (_, second) = read_raw(bytes, Some("Second"), &Limits::request()).unwrap();
    assert_eq!(second.header, ["code"]);
    assert_eq!(second.rows[0].cells, [t("from second")]);
}

#[test]
fn a_libreoffice_xlsx_is_read() {
    check_foreign(FOREIGN_XLSX);
}

#[test]
fn a_libreoffice_ods_is_read() {
    check_foreign(FOREIGN_ODS);
}

// ---------------------------------------------------------------------------------------------
// Sheets, header position, empty rows
// ---------------------------------------------------------------------------------------------

#[test]
fn the_first_sheet_is_the_default_and_another_can_be_named() {
    let bytes = {
        let mut wb = Workbook::new();
        let a = wb.add_worksheet();
        a.set_name("First").unwrap();
        a.write_string(0, 0, "code").unwrap();
        a.write_string(1, 0, "one").unwrap();
        let b = wb.add_worksheet();
        b.set_name("Other").unwrap();
        b.write_string(0, 0, "code").unwrap();
        b.write_string(1, 0, "two").unwrap();
        wb.save_to_buffer().unwrap()
    };
    let limits = Limits::request();
    assert_eq!(raw(&bytes).rows[0].cells, [t("one")]);
    let (_, other) = read_raw(&bytes, Some("Other"), &limits).unwrap();
    assert_eq!(other.rows[0].cells, [t("two")]);
    assert_eq!(other.sheets, ["First", "Other"]);
    let e = raw_err(&bytes, Some("Nope"), &limits);
    assert_eq!(e.len(), 1);
    assert!(e[0].message.contains("\"Nope\""), "{}", e[0].message);
    assert!(e[0].message.contains("First, Other"), "{}", e[0].message);
    assert_eq!(sheet_names(&bytes, &limits).unwrap().1, ["First", "Other"]);
    // ODS
    let ods = ods_of(&format!(
        r#"<table:table table:name="A">{}</table:table><table:table table:name="B">{}</table:table>"#,
        row(&[s_cell("code")]) + &row(&[s_cell("a")]),
        row(&[s_cell("code")]) + &row(&[s_cell("b")]),
    ));
    assert_eq!(raw(&ods).rows[0].cells, [t("a")]);
    assert_eq!(
        read_raw(&ods, Some("B"), &limits).unwrap().1.rows[0].cells,
        [t("b")]
    );
    let e = raw_err(&ods, Some("C"), &limits);
    assert!(e[0].message.contains("A, B"));
    assert_eq!(sheet_names(&ods, &limits).unwrap().1, ["A", "B"]);
    // CSV has no sheets and ignores a sheet name.
    assert_eq!(
        sheet_names(b"a\n1\n", &limits).unwrap(),
        (Format::Csv, vec![])
    );
    assert!(read_raw(b"a\n1\n", Some("x"), &limits).is_ok());
}

#[test]
fn the_header_is_the_first_non_empty_row_and_empty_rows_are_skipped() {
    let xlsx = xlsx_with(|s| {
        s.write_string(2, 0, "code").unwrap(); // row 3
        s.write_string(2, 1, "name").unwrap();
        s.write_string(3, 0, "a").unwrap(); // row 4
        s.write_string(4, 1, "only name").unwrap(); // row 5
                                                    // row 6 empty
        s.write_string(6, 0, "z").unwrap(); // row 7
        s.write_string(6, 1, "last").unwrap();
    });
    let ods = ods_of(&format!(
        r#"<table:table table:name="S"><table:table-row table:number-rows-repeated="2"><table:table-cell table:number-columns-repeated="2"/></table:table-row>{}{}{}<table:table-row><table:table-cell/></table:table-row>{}</table:table>"#,
        row(&[s_cell("code"), s_cell("name")]),
        row(&[s_cell("a")]),
        row(&[String::from("<table:table-cell/>"), s_cell("only name")]),
        row(&[s_cell("z"), s_cell("last")]),
    ));
    for bytes in [xlsx, ods] {
        let table = raw(&bytes);
        assert_eq!(table.header_row, 3);
        assert_eq!(table.header, ["code", "name"]);
        let rows: Vec<_> = table
            .rows
            .iter()
            .map(|r| (r.row, r.cells.clone()))
            .collect();
        assert_eq!(
            rows,
            [
                (4, vec![t("a"), CellValue::Empty]),
                (5, vec![CellValue::Empty, t("only name")]),
                (7, vec![t("z"), t("last")]),
            ]
        );
        // And bound: errors and cells carry the real sheet rows.
        let bound = bind(table, &["code", "name"], &["code"], None).unwrap();
        assert_eq!(bound.rows[1].line, 5);
        assert_eq!(bound.rows[1].get_trimmed("code"), None);
    }
}

#[test]
fn a_table_that_starts_right_of_column_a_is_read_from_its_header() {
    let xlsx = xlsx_with(|s| {
        s.write_string(1, 2, "code").unwrap(); // C2
        s.write_string(1, 3, "name").unwrap();
        s.write_string(2, 2, "a").unwrap();
        s.write_string(2, 3, "b").unwrap();
        s.write_string(3, 0, "stray").unwrap(); // A4, left of the table
    });
    let table = raw(&xlsx);
    assert_eq!(table.header, ["code", "name"]);
    assert_eq!(table.rows.len(), 1);
    assert_eq!(table.errors.len(), 1);
    assert_eq!(table.errors[0].row, 4);
    assert!(table.errors[0]
        .message
        .contains("left of the first header column"));
}

#[test]
fn header_cells_that_are_not_text_are_taken_as_their_text() {
    let xlsx = xlsx_with(|s| {
        s.write_number(0, 0, 2024.0).unwrap();
        s.write_number(0, 1, 1.5).unwrap();
        s.write_boolean(0, 2, true).unwrap();
        s.write_string(1, 0, "a").unwrap();
    });
    assert_eq!(raw(&xlsx).header, ["2024", "1.5", "true"]);
    let ods = ods_of(&format!(
        r#"<table:table table:name="S">{}{}</table:table>"#,
        row(&[f_cell("2024"), f_cell("1.5")]),
        row(&[s_cell("a")]),
    ));
    assert_eq!(raw(&ods).header, ["2024", "1.5"]);
}

#[test]
fn an_empty_sheet_is_an_error() {
    let xlsx = xlsx_with(|_| {});
    assert!(raw_err(&xlsx, None, &Limits::request())[0]
        .message
        .contains("empty"));
    let ods = ods_of(
        r#"<table:table table:name="S"><table:table-row><table:table-cell/></table:table-row></table:table>"#,
    );
    assert!(raw_err(&ods, None, &Limits::request())[0]
        .message
        .contains("empty"));
    assert!(raw_err(b"", None, &Limits::request())[0]
        .message
        .contains("empty"));
}

#[test]
fn a_foreign_workbook_binds_with_a_mapping() {
    let (_, table) = read_table(
        FOREIGN_XLSX,
        None,
        &Limits::request(),
        &["code", "name", "price", "active"],
        &["code"],
        Some(&[
            ("CODE".to_string(), "code".to_string()),
            (" price ".to_string(), "price".to_string()),
            ("Active".to_string(), "active".to_string()),
        ]),
    )
    .unwrap();
    assert_eq!(table.columns, ["code", "price", "active"]);
    assert_eq!(table.rows[0].get("code"), Some("00123"));
    assert_eq!(table.rows[0].get("price"), Some("7.5"));
    let mut errors = vec![];
    let mut cells = Cells::new(&table.rows[0], &mut errors);
    assert_eq!(cells.decimal("price"), Cell::Value(dec!(7.5)));
    assert_eq!(cells.boolean("active"), Cell::Value(true));
    assert!(errors.is_empty());
    // The same file without a mapping: our header rules apply and its headers are unknown.
    let e = read_table(FOREIGN_XLSX, None, &Limits::request(), &["code"], &[], None).unwrap_err();
    assert!(e.iter().any(|e| e.message.starts_with("unknown column")));
    // A mapping to a column the sheet does not have.
    let e = read_table(
        FOREIGN_XLSX,
        None,
        &Limits::request(),
        &["code"],
        &[],
        Some(&[("nope".to_string(), "code".to_string())]),
    )
    .unwrap_err();
    assert_eq!(e[0].message, "mapped column is not in the file");
}

// ---------------------------------------------------------------------------------------------
// Values: formulas, errors, floats
// ---------------------------------------------------------------------------------------------

#[test]
fn formulas_are_read_as_their_cached_value() {
    let xlsx = xlsx_with(|s| {
        for (c, h) in ["num", "text", "flag", "none"].iter().enumerate() {
            s.write_string(0, c as u16, *h).unwrap();
        }
        s.write_formula(1, 0, Formula::new("=1+2").set_result("3"))
            .unwrap();
        s.write_formula(1, 1, Formula::new("=\"a\"&\"b\"").set_result("ab"))
            .unwrap();
        s.write_formula(1, 2, Formula::new("=TRUE()").set_result("TRUE"))
            .unwrap();
        s.write_formula(1, 3, Formula::new("=1+1")).unwrap();
    });
    // A formula the producer left no cached result for is an empty cell.
    let xlsx = rewrite_entry(&xlsx, "xl/worksheets/sheet1.xml", |x| {
        x.replacen("<f>1+1</f><v>0</v>", "<f>1+1</f>", 1)
    });
    let table = raw(&xlsx);
    assert_eq!(
        table.rows[0].cells,
        [n(dec!(3)), t("ab"), CellValue::Bool(true), CellValue::Empty]
    );

    let ods = ods_of(&format!(
        r#"<table:table table:name="S">{}<table:table-row><table:table-cell table:formula="of:=1+2" office:value-type="float" office:value="3"><text:p>3</text:p></table:table-cell><table:table-cell table:formula="of:=&quot;a&quot;" office:value-type="string" office:string-value="ab"><text:p>ab</text:p></table:table-cell><table:table-cell table:formula="of:=TRUE()" office:value-type="boolean" office:boolean-value="true"><text:p>TRUE</text:p></table:table-cell><table:table-cell table:formula="of:=1+1"/></table:table-row></table:table>"#,
        row(&[
            s_cell("num"),
            s_cell("text"),
            s_cell("flag"),
            s_cell("none")
        ])
    ));
    assert_eq!(
        raw(&ods).rows[0].cells,
        [n(dec!(3)), t("ab"), CellValue::Bool(true), CellValue::Empty]
    );
}

#[test]
fn an_error_cell_is_a_row_error_naming_the_column() {
    let xlsx = xlsx_with(|s| {
        s.write_string(0, 0, "code").unwrap();
        s.write_string(0, 1, "price").unwrap();
        s.write_string(1, 0, "a").unwrap();
        s.write_string(1, 1, "1").unwrap();
        s.write_string(2, 0, "b").unwrap();
        s.write_formula(2, 1, Formula::new("=NA()").set_result("#N/A"))
            .unwrap();
        s.write_string(3, 0, "c").unwrap();
        s.write_formula(3, 1, Formula::new("=1/0").set_result("#DIV/0!"))
            .unwrap();
    });
    let ods = ods_of(&format!(
        r#"<table:table table:name="S">{}{}{}</table:table>"#,
        row(&[s_cell("code"), s_cell("price")]),
        row(&[s_cell("a"), s_cell("1")]),
        row(&[
            s_cell("b"),
            r##"<table:table-cell table:formula="of:=NA()" office:value-type="string" office:string-value="" calcext:value-type="error"><text:p>#N/A</text:p></table:table-cell>"##.to_string()
        ]),
    ));
    for (bytes, first) in [(xlsx, "#N/A"), (ods, "#N/A")] {
        let table = raw(&bytes);
        assert_eq!(table.rows.len(), 1, "the bad rows are left out");
        assert_eq!(table.rows[0].cells[0], t("a"));
        let e = &table.errors[0];
        assert_eq!(e.row, 3);
        assert_eq!(e.column.as_deref(), Some("price"));
        assert!(e.message.contains(first), "{}", e.message);
    }
    let table = raw(&xlsx_with(|s| {
        s.write_string(0, 0, "price").unwrap();
        s.write_formula(1, 0, Formula::new("=1/0").set_result("#DIV/0!"))
            .unwrap();
    }));
    assert!(table.errors[0].message.contains("#DIV/0!"));
    // The errors travel on to the bound table.
    let bound = bind(table, &["price"], &[], None).unwrap();
    assert_eq!(bound.width_errors.len(), 1);
}

#[test]
fn an_error_in_the_header_ends_the_read() {
    let xlsx = xlsx_with(|s| {
        s.write_string(0, 0, "code").unwrap();
        s.write_formula(0, 1, Formula::new("=NA()").set_result("#N/A"))
            .unwrap();
        s.write_string(1, 0, "a").unwrap();
    });
    let e = raw_err(&xlsx, None, &Limits::request());
    assert_eq!(e[0].row, 1);
    assert_eq!(e[0].column.as_deref(), Some("B"));
}

#[test]
fn a_float_with_no_exact_decimal_is_a_row_error() {
    let xlsx = xlsx_with(|s| {
        s.write_string(0, 0, "v").unwrap();
        s.write_number(1, 0, 1e-30).unwrap();
        s.write_number(2, 0, 7.5).unwrap();
        s.write_number(3, 0, 1e300).unwrap();
    });
    let table = raw(&xlsx);
    assert_eq!(table.rows.len(), 1);
    assert_eq!(table.rows[0].cells, [n(dec!(7.5))]);
    let rows: Vec<_> = table.errors.iter().map(|e| e.row).collect();
    assert_eq!(rows, [2, 4]);
    assert!(table.errors[0].message.contains("more digits"));
    assert_eq!(table.errors[0].column.as_deref(), Some("v"));
}

#[test]
fn binary_floats_read_as_their_shortest_decimal() {
    let xlsx = xlsx_with(|s| {
        s.write_string(0, 0, "v").unwrap();
        for (i, v) in [7.5, 0.1, 0.2, 1234567.89, 100.0, -2.25].iter().enumerate() {
            s.write_number(i as u32 + 1, 0, *v).unwrap();
        }
    });
    let values: Vec<_> = raw(&xlsx).rows.iter().map(|r| r.cells[0].clone()).collect();
    assert_eq!(
        values,
        [
            n(dec!(7.5)),
            n(dec!(0.1)),
            n(dec!(0.2)),
            n(dec!(1234567.89)),
            n(dec!(100)),
            n(dec!(-2.25))
        ]
    );
}

#[test]
fn dates_and_times_in_xlsx() {
    use rust_xlsxwriter::{ExcelDateTime, Format as F};
    let xlsx = xlsx_with(|s| {
        let df = F::new().set_num_format("dd/mm/yyyy");
        let tf = F::new().set_num_format("hh:mm");
        s.write_string(0, 0, "d").unwrap();
        s.write_datetime_with_format(1, 0, ExcelDateTime::from_ymd(2024, 2, 29).unwrap(), &df)
            .unwrap();
        s.write_datetime_with_format(
            2,
            0,
            ExcelDateTime::from_ymd(2024, 2, 29)
                .unwrap()
                .and_hms(13, 45, 0)
                .unwrap(),
            &df,
        )
        .unwrap();
        s.write_datetime_with_format(3, 0, ExcelDateTime::from_hms(0, 0, 0).unwrap(), &tf)
            .unwrap();
    });
    let table = raw(&xlsx);
    assert_eq!(table.rows[0].cells, [CellValue::Date(date(2024, 2, 29))]);
    assert_eq!(
        table.rows[1].cells,
        [CellValue::DateTime(
            date(2024, 2, 29).and_hms_opt(13, 45, 0).unwrap()
        )]
    );
}

#[test]
fn an_ods_time_value_is_a_row_error() {
    let ods = ods_of(&format!(
        r#"<table:table table:name="S">{}<table:table-row><table:table-cell office:value-type="time" office:time-value="PT10H30M00S"><text:p>10:30</text:p></table:table-cell></table:table-row></table:table>"#,
        row(&[s_cell("t")])
    ));
    let table = raw(&ods);
    assert!(table.rows.is_empty());
    assert!(table.errors[0].message.contains("not supported"));
}

// ---------------------------------------------------------------------------------------------
// Limits
// ---------------------------------------------------------------------------------------------

fn small() -> Limits {
    Limits {
        rows: 3,
        cells_per_row: 4,
        total_cells: 14,
        ..Limits::request()
    }
}

fn grid(format: Format, rows: usize, cols: usize) -> Vec<u8> {
    let header: Vec<String> = (0..cols).map(|c| format!("c{c}")).collect();
    let header: Vec<&str> = header.iter().map(String::as_str).collect();
    let body = (0..rows)
        .map(|r| (0..cols).map(|c| t(&format!("{r}.{c}"))).collect())
        .collect();
    written(format, &header, body)
}

#[test]
fn row_cell_and_total_limits_stop_every_format() {
    for format in [Format::Csv, Format::Xlsx, Format::Ods] {
        // 3 rows x 4 cells + header = 16 cells; the limit is 14 in total.
        assert!(
            read_raw(&grid(format, 3, 3), None, &small()).is_ok(),
            "{format:?}"
        );
        let e = raw_err(&grid(format, 4, 2), None, &small());
        assert!(e[0].message.contains("too many rows"), "{format:?} {e:?}");
        assert_eq!(e.len(), 1);
        let e = raw_err(&grid(format, 1, 5), None, &small());
        assert!(
            e[0].message.contains("too many columns"),
            "{format:?} {e:?}"
        );
        let e = raw_err(&grid(format, 3, 4), None, &small());
        assert!(e[0].message.contains("too many cells"), "{format:?} {e:?}");
    }
}

#[test]
fn the_job_limits_are_more_generous_than_one_request() {
    let mut csv = String::from("v\n");
    csv.push_str(&"x\n".repeat(Limits::request().rows + 1));
    assert!(raw_err(csv.as_bytes(), None, &Limits::request())[0]
        .message
        .contains("too many rows"));
    assert_eq!(
        read_raw(csv.as_bytes(), None, &Limits::job())
            .unwrap()
            .1
            .rows
            .len(),
        Limits::request().rows + 1
    );
    let too_big = Limits {
        file_bytes: 10,
        ..Limits::request()
    };
    assert!(raw_err(b"code,name\n1,a\n", None, &too_big)[0]
        .message
        .contains("larger than"));
}

#[test]
fn limit_errors_are_told_apart_from_other_problems() {
    // Every kind of limit, in every format.
    for format in [Format::Csv, Format::Xlsx, Format::Ods] {
        for (rows, cols) in [(4, 2), (1, 5), (3, 4)] {
            let e = raw_err(&grid(format, rows, cols), None, &small());
            assert!(exceeds_limits(&e), "{format:?} {rows}x{cols} {e:?}");
        }
    }
    let too_big = Limits {
        file_bytes: 10,
        ..Limits::request()
    };
    assert!(exceeds_limits(&raw_err(
        b"code,name\n1,a\n",
        None,
        &too_big
    )));
    let few = Limits {
        archive_entries: 1,
        ..Limits::request()
    };
    let xlsx = grid(Format::Xlsx, 1, 1);
    assert!(exceeds_limits(&raw_err(&xlsx, None, &few)));
    let unpacked = Limits {
        unpacked_bytes: 1,
        ..Limits::request()
    };
    assert!(exceeds_limits(&raw_err(&xlsx, None, &unpacked)));
    // Problems of the file itself are not limits, and neither is an unknown sheet.
    assert!(!exceeds_limits(&raw_err(
        b"a,\"b\n",
        None,
        &Limits::request()
    )));
    assert!(!exceeds_limits(&raw_err(b"", None, &Limits::request())));
    assert!(!exceeds_limits(&raw_err(
        &xlsx,
        Some("Nope"),
        &Limits::request()
    )));
    assert!(!exceeds_limits(&raw_err(
        b"PK\x03\x04 damaged",
        None,
        &Limits::request()
    )));
    assert!(!exceeds_limits(&[]));
}

#[test]
fn a_sparse_xlsx_cell_far_away_is_refused_without_allocating_its_bounding_box() {
    let xlsx = xlsx_with(|s| {
        s.write_string(0, 0, "code").unwrap();
        s.write_string(1, 0, "a").unwrap();
        s.write_string(1_048_575, 16_383, "far").unwrap(); // XFD1048576
    });
    let e = raw_err(&xlsx, None, &Limits::request());
    assert!(e[0].message.contains("too many columns"), "{e:?}");
    // Far down but in range: fine, and the real row number is kept.
    let xlsx = xlsx_with(|s| {
        s.write_string(0, 0, "code").unwrap();
        s.write_string(1_048_575, 0, "far").unwrap();
    });
    assert_eq!(raw(&xlsx).rows[0].row, 1_048_576);
}

#[test]
fn ods_sheets_that_expand_beyond_the_limits_are_refused_before_calamine_builds_them() {
    // A value in a row repeated a million times, and in a cell repeated a million times.
    let tall = ods_of(&format!(
        r#"<table:table table:name="S">{}<table:table-row table:number-rows-repeated="1000000">{}</table:table-row></table:table>"#,
        row(&[s_cell("a"), s_cell("b")]),
        s_cell("x") + &s_cell("y")
    ));
    assert!(raw_err(&tall, None, &Limits::request())[0]
        .message
        .contains("too many cells"));
    let wide = ods_of(&format!(
        r#"<table:table table:name="S">{}<table:table-row><table:table-cell office:value-type="string" table:number-columns-repeated="1000000"><text:p>x</text:p></table:table-cell></table:table-row></table:table>"#,
        row(&[s_cell("a")])
    ));
    assert!(raw_err(&wide, None, &Limits::request())[0]
        .message
        .contains("too many columns"));
    // Many sheets add up.
    let sheet = format!(
        r#"<table:table table:name="N{{}}"><table:table-row table:number-rows-repeated="1000">{}</table:table-row></table:table>"#,
        (0..100).map(|_| s_cell("x")).collect::<String>()
    );
    let many = ods_of(
        &(0..30)
            .map(|i| sheet.replace("{}", &i.to_string()))
            .collect::<String>(),
    );
    assert!(raw_err(&many, None, &Limits::request())[0]
        .message
        .contains("too many cells"));
    // What LibreOffice writes at the end of every sheet is harmless: empty rows and columns,
    // repeated a million times.
    let trailing = ods_of(&format!(
        r#"<table:table table:name="S">{}<table:table-row table:number-rows-repeated="1048570"><table:table-cell table:number-columns-repeated="16384"/></table:table-row></table:table>"#,
        row(&[s_cell("a")])
            + &row(&[
                s_cell("1"),
                "<table:table-cell table:number-columns-repeated=\"16383\"/>".to_string()
            ])
    ));
    assert_eq!(raw(&trailing).rows.len(), 1);
}

// ---------------------------------------------------------------------------------------------
// Archive checks
// ---------------------------------------------------------------------------------------------

#[test]
fn too_many_archive_entries_are_refused() {
    let names: Vec<String> = (0..1_001).map(|i| format!("junk/{i}.txt")).collect();
    let mut entries: Vec<(&str, &[u8])> = vec![("xl/workbook.xml", b"<x/>")];
    entries.extend(names.iter().map(|n| (n.as_str(), &b"x"[..])));
    let bytes = zip_of(&entries);
    let e = raw_err(&bytes, None, &Limits::request());
    assert_eq!(e.len(), 1);
    assert!(e[0].message.contains("1002 entries"), "{}", e[0].message);
    // At the limit it is let through to the reader (which then finds no workbook).
    let few = Limits {
        archive_entries: 1_002,
        ..Limits::request()
    };
    assert!(archive::check(&bytes, &few).is_ok());
}

#[test]
fn a_declared_unpacked_size_over_the_limit_is_refused_before_unpacking() {
    let zeros = vec![0u8; 3 * 1024 * 1024];
    let bytes = zip_of(&[("xl/workbook.xml", b"<x/>"), ("xl/big.bin", &zeros)]);
    assert!(bytes.len() < 50_000, "it compresses to almost nothing");
    let limits = Limits {
        unpacked_bytes: 1024 * 1024,
        ..Limits::request()
    };
    let e = raw_err(&bytes, None, &limits);
    assert_eq!(e.len(), 1);
    assert!(
        e[0].message.contains("unpacks to more than"),
        "{}",
        e[0].message
    );
    assert!(archive::check(&bytes, &Limits::request()).is_ok());
}

#[test]
fn a_lying_declared_size_is_stopped_while_inflating() {
    // The raw zip reader: an entry that inflates to 20 MiB but declares 1000 bytes passes the
    // directory check (its declared size is small) and is stopped by the reader after the
    // declared size, without buffering what follows.
    let zeros = vec![0u8; 20 * 1024 * 1024];
    let honest = zip_of(&[("big.bin", &zeros)]);
    let lying = declare_size(&honest, "big.bin", 1000);
    assert!(archive::check(&lying, &Limits::request()).is_ok());
    let mut zip = ZipArchive::new(Cursor::new(&lying)).unwrap();
    let mut buf = Vec::new();
    let result = zip.by_name("big.bin").unwrap().read_to_end(&mut buf);
    assert!(result.is_err(), "the oversized entry must not be read");
    assert!(buf.len() <= 1001, "read {} bytes", buf.len());
    // Also when read in small pieces.
    let mut entry = zip.by_name("big.bin").unwrap();
    let mut total = 0;
    let mut chunk = [0u8; 512];
    let error = loop {
        match entry.read(&mut chunk) {
            Ok(0) => break None,
            Ok(n) => total += n,
            Err(e) => break Some(e),
        }
    };
    assert!(error.is_some() && total <= 1512, "{total}");

    // Through calamine, for both formats: a workbook whose sheet part lies about its size is an
    // error of the file, not an out-of-memory.
    let rows: Vec<_> = (0..2000).map(|i| vec![t(&format!("row {i}"))]).collect();
    let xlsx = written(Format::Xlsx, &["v"], rows.clone());
    let lying = declare_size(&xlsx, "xl/worksheets/sheet1.xml", 100);
    assert!(read_raw(&lying, None, &Limits::request()).is_err());
    let ods = written(Format::Ods, &["v"], rows);
    let lying = declare_size(&ods, "content.xml", 100);
    assert!(read_raw(&lying, None, &Limits::request()).is_err());
    // A declared size that is too small for the shared strings of an XLSX.
    let lying = declare_size(&xlsx, "xl/sharedStrings.xml", 50);
    assert!(read_raw(&lying, None, &Limits::request()).is_err());
}

#[test]
fn an_ods_error_cell_is_found_by_position_and_a_text_that_looks_like_one_is_not() {
    let err = |text: &str| {
        format!(
            r#"<table:table-cell office:value-type="string" office:string-value="" calcext:value-type="error"><text:p>{text}</text:p></table:table-cell>"#
        )
    };
    let ods = ods_of(&format!(
        r#"<table:table table:name="S"><table:table-row table:number-rows-repeated="2"><table:table-cell table:number-columns-repeated="3"/></table:table-row>{}{}{}{}</table:table>"#,
        row(&[s_cell("code"), s_cell("note")]),
        row(&[s_cell("a"), s_cell("#N/A")]), // a typed text, not an error
        row(&[s_cell("b"), err("#REF!")]),
        row(&[err("Err:502"), s_cell("c")]),
    ));
    let table = raw(&ods);
    assert_eq!(table.header_row, 3);
    assert_eq!(table.rows.len(), 1);
    assert_eq!(table.rows[0].cells, [t("a"), t("#N/A")]);
    let found: Vec<_> = table
        .errors
        .iter()
        .map(|e| (e.row, e.column.clone().unwrap(), e.message.clone()))
        .collect();
    assert_eq!(found.len(), 2);
    assert_eq!((found[0].0, found[0].1.as_str()), (5, "note"));
    assert!(found[0].2.contains("#REF!"));
    assert_eq!((found[1].0, found[1].1.as_str()), (6, "code"));
}
