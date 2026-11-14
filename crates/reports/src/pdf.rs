//! The data for `templates/report.typ`: a report result with every value already formatted
//! (Belgian number and date notation, the company's language).

use chrono::{DateTime, NaiveDate};
use rust_decimal::Decimal;
use serde::Serialize;
use serde_json::Value;
use tradocraft_documents::{format_date, format_number};

use crate::catalog::{self, ReportFieldType};
use crate::definition::{ReportChartKind, ReportDefinition, ReportLogic, ReportOp};
use crate::engine::ReportRunResult;
use crate::relative::RelativeDate;

/// A PDF is for reading; bigger results belong in the CSV export.
pub const MAX_PDF_ROWS: i64 = 2000;
/// Bars drawn in the chart.
pub const MAX_BARS: usize = 30;

/// A column heading of the PDF table.
#[derive(Debug, Serialize)]
pub struct PdfColumn {
    pub label: String,
    pub align: &'static str,
}

/// One bar (or pie slice) of the PDF chart.
#[derive(Debug, Serialize, PartialEq)]
pub struct PdfBar {
    pub label: String,
    pub text: String,
    /// Bar length, 0 to 100, relative to the largest value.
    pub pct: f64,
    /// Share of the total, for pie charts; empty otherwise.
    pub share: String,
}

/// The chart drawn in the PDF.
#[derive(Debug, Serialize)]
pub struct PdfChart {
    pub title: String,
    pub bars: Vec<PdfBar>,
}

/// Everything the PDF template needs, already formatted for the reader.
#[derive(Debug, Serialize)]
pub struct PdfData {
    pub language: String,
    pub title: String,
    pub description: String,
    pub company: String,
    pub generated: String,
    pub filters: Vec<String>,
    pub logic: &'static str,
    pub columns: Vec<PdfColumn>,
    pub rows: Vec<Vec<String>>,
    pub totals: Option<Vec<String>>,
    pub row_count: i64,
    pub chart: Option<PdfChart>,
}

fn yes_no(lang: &str, b: bool) -> &'static str {
    match (lang, b) {
        ("nl", true) => "ja",
        ("nl", false) => "nee",
        ("fr", true) => "oui",
        ("fr", false) => "non",
        ("de", true) => "ja",
        ("de", false) => "nein",
        ("es", true) => "sí",
        ("es", false) => "no",
        (_, true) => "yes",
        (_, false) => "no",
    }
}

fn totals_label(lang: &str) -> &'static str {
    match lang {
        "nl" => "Totaal",
        "de" => "Gesamt",
        _ => "Total",
    }
}

/// Suffix for the chart title when groups are left out of the drawing.
fn truncated_note(lang: &str, omitted: usize) -> String {
    if omitted == 0 {
        return String::new();
    }
    let shown = MAX_BARS;
    match lang {
        "nl" => format!(" (eerste {shown} groepen getoond, {omitted} weggelaten)"),
        "fr" => format!(" ({shown} premiers groupes affichés, {omitted} omis)"),
        "de" => format!(" (erste {shown} Gruppen angezeigt, {omitted} ausgelassen)"),
        "es" => format!(" (primeros {shown} grupos mostrados, {omitted} omitidos)"),
        _ => format!(" (first {shown} groups shown, {omitted} omitted)"),
    }
}

fn op_text(lang: &str, op: ReportOp) -> &'static str {
    match (op, lang) {
        (ReportOp::Eq, _) => "=",
        (ReportOp::Ne, _) => "≠",
        (ReportOp::Gt, _) => ">",
        (ReportOp::Gte, _) => "≥",
        (ReportOp::Lt, _) => "<",
        (ReportOp::Lte, _) => "≤",
        (ReportOp::Contains, "nl") => "bevat",
        (ReportOp::Contains, "fr") => "contient",
        (ReportOp::Contains, "de") => "enthält",
        (ReportOp::Contains, "es") => "contiene",
        (ReportOp::Contains, _) => "contains",
        (ReportOp::StartsWith, "nl") => "begint met",
        (ReportOp::StartsWith, "fr") => "commence par",
        (ReportOp::StartsWith, "de") => "beginnt mit",
        (ReportOp::StartsWith, "es") => "empieza por",
        (ReportOp::StartsWith, _) => "starts with",
        (ReportOp::In, "nl") => "is een van",
        (ReportOp::In, "fr") => "est parmi",
        (ReportOp::In, "de") => "ist eines von",
        (ReportOp::In, "es") => "es uno de",
        (ReportOp::In, _) => "is one of",
        (ReportOp::IsNull, "nl") => "is leeg",
        (ReportOp::IsNull, "fr") => "est vide",
        (ReportOp::IsNull, "de") => "ist leer",
        (ReportOp::IsNull, "es") => "está vacío",
        (ReportOp::IsNull, _) => "is empty",
        (ReportOp::NotNull, "nl") => "is niet leeg",
        (ReportOp::NotNull, "fr") => "n'est pas vide",
        (ReportOp::NotNull, "de") => "ist nicht leer",
        (ReportOp::NotNull, "es") => "no está vacío",
        (ReportOp::NotNull, _) => "is not empty",
    }
}

fn decimal(v: &Value) -> Option<Decimal> {
    match v {
        Value::Number(n) => n.to_string().parse().ok(),
        Value::String(s) => s.parse().ok(),
        _ => None,
    }
}

/// One value as text, by the type of its column.
pub fn format_value(lang: &str, ty: ReportFieldType, v: &Value) -> String {
    match (ty, v) {
        (_, Value::Null) => String::new(),
        (ReportFieldType::Number, v) => decimal(v)
            .map(format_number)
            .unwrap_or_else(|| v.to_string()),
        (ReportFieldType::Date, Value::String(s)) => NaiveDate::parse_from_str(s, "%Y-%m-%d")
            .map(format_date)
            .unwrap_or_else(|_| s.clone()),
        (ReportFieldType::Datetime, Value::String(s)) => DateTime::parse_from_rfc3339(s)
            .map(|d| d.naive_utc().format("%d/%m/%Y %H:%M").to_string())
            .unwrap_or_else(|_| s.clone()),
        (ReportFieldType::Bool, Value::Bool(b)) => yes_no(lang, *b).to_string(),
        (_, Value::String(s)) => s.clone(),
        (_, other) => other.to_string(),
    }
}

fn filter_value(lang: &str, ty: ReportFieldType, v: &Value, today: NaiveDate) -> String {
    match v {
        Value::Object(_) => match RelativeDate::parse(v).and_then(|r| Ok((r, r.range(today)?))) {
            Ok((r, (a, b))) if a == b => format!("{} ({})", r.words(lang), format_date(a)),
            Ok((r, (a, b))) => {
                format!(
                    "{} ({} - {})",
                    r.words(lang),
                    format_date(a),
                    format_date(b)
                )
            }
            Err(_) => v.to_string(),
        },
        Value::Array(items) => items
            .iter()
            .map(|i| filter_value(lang, ty, i, today))
            .collect::<Vec<_>>()
            .join(", "),
        Value::String(s) if matches!(ty, ReportFieldType::Date | ReportFieldType::Datetime) => {
            format_value(lang, ReportFieldType::Date, &Value::String(s.clone()))
        }
        other => format_value(lang, ty, other),
    }
}

fn filter_lines(lang: &str, def: &ReportDefinition, today: NaiveDate) -> Vec<String> {
    let multi = !def.joins.is_empty();
    def.filters
        .iter()
        .filter_map(|f| {
            let (o, fd) = catalog::resolve(&f.field)?;
            let name = if multi {
                format!("{}: {}", o.label, fd.label)
            } else {
                fd.label.to_string()
            };
            let value = match f.op {
                ReportOp::IsNull | ReportOp::NotNull => String::new(),
                _ => f
                    .value
                    .as_ref()
                    .map(|v| filter_value(lang, fd.ty, v, today))
                    .unwrap_or_default(),
            };
            Some(
                format!("{name} {} {value}", op_text(lang, f.op))
                    .trim_end()
                    .to_string(),
            )
        })
        .collect()
}

fn chart(lang: &str, def: &ReportDefinition, result: &ReportRunResult) -> Option<PdfChart> {
    let ch = def.chart.as_ref()?;
    let xi = result.columns.iter().position(|c| c.key == ch.x)?;
    let yi = result.columns.iter().position(|c| c.key == ch.y)?;
    let value_of = |r: &Vec<Value>| r[yi].as_f64().unwrap_or(0.0).max(0.0);
    let values: Vec<(String, f64)> = result
        .rows
        .iter()
        .take(MAX_BARS)
        .map(|r| {
            (
                format_value(lang, result.columns[xi].ty, &r[xi]),
                value_of(r),
            )
        })
        .collect();
    let max = values.iter().map(|(_, v)| *v).fold(0.0, f64::max);
    // Shares are of the whole result, not only of the groups that are drawn.
    let sum: f64 = result.rows.iter().map(value_of).sum();
    let omitted = result.rows.len().saturating_sub(MAX_BARS);
    let bars = values
        .into_iter()
        .enumerate()
        .map(|(i, (label, v))| PdfBar {
            label,
            text: format_value(lang, result.columns[yi].ty, &result.rows[i][yi]),
            pct: if max > 0.0 {
                (v / max * 100.0).round()
            } else {
                0.0
            },
            share: if ch.kind == ReportChartKind::Pie && sum > 0.0 {
                format!("{:.1} %", v / sum * 100.0).replace('.', ",")
            } else {
                String::new()
            },
        })
        .collect();
    Some(PdfChart {
        title: format!(
            "{} / {}{}",
            result.columns[yi].label,
            result.columns[xi].label,
            truncated_note(lang, omitted)
        ),
        bars,
    })
}

/// The data for a plain table (the helpdesk reports of ADR 0021): text columns, numbers aligned
/// right when every cell of the column is a number, no chart.
pub fn from_table(
    title: &str,
    filters: Vec<String>,
    header: &[String],
    rows: &[Vec<String>],
    company: &str,
    lang: &str,
    today: NaiveDate,
) -> PdfData {
    let numeric = |i: usize| {
        !rows.is_empty()
            && rows.iter().all(|r| {
                r.get(i)
                    .is_some_and(|c| c.is_empty() || c.parse::<f64>().is_ok())
            })
    };
    PdfData {
        language: lang.to_string(),
        title: title.to_string(),
        description: String::new(),
        company: company.to_string(),
        generated: format_date(today),
        filters,
        logic: "and",
        columns: header
            .iter()
            .enumerate()
            .map(|(i, h)| PdfColumn {
                label: h.clone(),
                align: if numeric(i) { "right" } else { "left" },
            })
            .collect(),
        rows: rows.to_vec(),
        totals: None,
        row_count: rows.len() as i64,
        chart: None,
    }
}

/// Turns a run result into the data for the PDF template.
pub fn build(
    name: &str,
    description: &str,
    def: &ReportDefinition,
    result: &ReportRunResult,
    company: &str,
    lang: &str,
    today: NaiveDate,
) -> PdfData {
    let columns = result
        .columns
        .iter()
        .map(|c| PdfColumn {
            label: c.label.clone(),
            align: if c.ty == ReportFieldType::Number {
                "right"
            } else {
                "left"
            },
        })
        .collect();
    let rows = result
        .rows
        .iter()
        .map(|r| {
            r.iter()
                .zip(&result.columns)
                .map(|(v, c)| format_value(lang, c.ty, v))
                .collect()
        })
        .collect();
    let totals = result.totals.as_ref().map(|t| {
        t.iter()
            .zip(&result.columns)
            .enumerate()
            .map(|(i, (v, c))| {
                if i == 0 && v.is_null() {
                    totals_label(lang).to_string()
                } else {
                    format_value(lang, c.ty, v)
                }
            })
            .collect()
    });
    PdfData {
        language: lang.to_string(),
        title: name.to_string(),
        description: description.to_string(),
        company: company.to_string(),
        generated: format_date(today),
        filters: filter_lines(lang, def, today),
        logic: if def.filter_logic == ReportLogic::Or {
            "or"
        } else {
            "and"
        },
        columns,
        rows,
        totals,
        row_count: result.total,
        chart: chart(lang, def, result),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::definition::{plan, ReportColumnKind};
    use crate::engine::ReportRunColumn;
    use serde_json::json;

    fn today() -> NaiveDate {
        NaiveDate::from_ymd_opt(2026, 11, 11).unwrap()
    }

    fn def(v: Value) -> ReportDefinition {
        serde_json::from_value(v).unwrap()
    }

    #[test]
    fn values_follow_the_belgian_notation() {
        assert_eq!(
            format_value("nl", ReportFieldType::Number, &json!(1234.5)),
            "1.234,5"
        );
        assert_eq!(
            format_value("nl", ReportFieldType::Number, &json!(500.0)),
            "500"
        );
        assert_eq!(
            format_value("nl", ReportFieldType::Date, &json!("2027-01-31")),
            "31/01/2027"
        );
        assert_eq!(
            format_value(
                "nl",
                ReportFieldType::Datetime,
                &json!("2027-01-31T13:05:00+00:00")
            ),
            "31/01/2027 13:05"
        );
        assert_eq!(
            format_value("nl", ReportFieldType::Bool, &json!(true)),
            "ja"
        );
        assert_eq!(
            format_value("fr", ReportFieldType::Bool, &json!(false)),
            "non"
        );
        assert_eq!(format_value("en", ReportFieldType::Text, &json!(null)), "");
        assert_eq!(format_value("en", ReportFieldType::Text, &json!("x")), "x");
    }

    #[test]
    fn filters_read_like_sentences() {
        let d = def(json!({
        "object": "quotation", "columns": [{"field": "quotation.number"}],
        "filters": [
            {"field": "quotation.total", "op": "gte", "value": 100},
            {"field": "quotation.quote_date", "op": "lt", "value": "2027-02-01"},
            {"field": "quotation.status", "op": "in", "value": ["sent", "draft"]},
            {"field": "quotation.sent_at", "op": "is_null"}
        ]}));
        assert_eq!(
            filter_lines("en", &d, today()),
            [
                "Total ≥ 100",
                "Quote date < 01/02/2027",
                "Status is one of sent, draft",
                "Sent is empty"
            ]
        );
        assert_eq!(filter_lines("nl", &d, today())[3], "Sent is leeg");
    }

    #[test]
    fn relative_dates_read_in_words_with_the_resolved_range() {
        let d = def(json!({
        "object": "quotation", "columns": [{"field": "quotation.number"}],
        "filters": [
            {"field": "quotation.quote_date", "op": "eq", "value": {"relative": "last_n_days", "n": 30}},
            {"field": "quotation.sent_at", "op": "gte", "value": {"relative": "today"}}
        ]}));
        assert_eq!(
            filter_lines("en", &d, today()),
            [
                "Quote date = the last 30 days (13/10/2026 - 11/11/2026)",
                "Sent ≥ today (11/11/2026)"
            ]
        );
        assert_eq!(
            filter_lines("nl", &d, today())[1],
            "Sent ≥ vandaag (11/11/2026)"
        );
    }

    fn grouped_result() -> (ReportDefinition, ReportRunResult) {
        let d = def(json!({
            "object": "quotation",
            "columns": [{"field": "quotation.total", "summary": "sum"}],
            "group_by": [{"field": "quotation.status"}],
            "chart": {"kind": "pie", "x": "quotation.status", "y": "quotation.total:sum"}
        }));
        let p = plan(&d, today()).unwrap();
        let r = ReportRunResult {
            columns: p
                .columns
                .iter()
                .map(|c| ReportRunColumn {
                    key: c.key.clone(),
                    label: c.label.clone(),
                    ty: c.ty,
                    kind: c.kind,
                })
                .collect(),
            rows: vec![
                vec![json!("accepted"), json!(750.0)],
                vec![json!("draft"), json!(250.0)],
            ],
            total: 2,
            totals: Some(vec![Value::Null, json!(1000.0)]),
            chart: d.chart.clone(),
            as_of: today(),
        };
        (d, r)
    }

    #[test]
    fn grouped_report_gets_totals_row_and_chart() {
        let (d, r) = grouped_result();
        let today = NaiveDate::from_ymd_opt(2027, 3, 1).unwrap();
        let data = build("Totals", "", &d, &r, "ACME", "nl", today);
        assert_eq!(data.generated, "01/03/2027");
        assert_eq!(data.columns[1].align, "right");
        assert_eq!(data.columns[0].align, "left");
        assert_eq!(data.rows, [["accepted", "750"], ["draft", "250"]]);
        assert_eq!(
            data.totals,
            Some(vec!["Totaal".to_string(), "1.000".to_string()])
        );
        let chart = data.chart.unwrap();
        assert_eq!(chart.title, "Sum of Total / Status");
        assert_eq!(
            chart.bars,
            [
                PdfBar {
                    label: "accepted".into(),
                    text: "750".into(),
                    pct: 100.0,
                    share: "75,0 %".into()
                },
                PdfBar {
                    label: "draft".into(),
                    text: "250".into(),
                    pct: 33.0,
                    share: "25,0 %".into()
                },
            ]
        );
        assert_eq!(r.columns[0].kind, ReportColumnKind::Group);
    }

    #[test]
    fn a_chart_of_zeros_does_not_divide_by_zero() {
        let (d, mut r) = grouped_result();
        r.rows = vec![vec![json!("x"), json!(0)], vec![json!("y"), json!(-5)]];
        let c = chart("en", &d, &r).unwrap();
        assert!(c.bars.iter().all(|b| b.pct == 0.0 && b.share.is_empty()));
    }

    #[test]
    fn pie_shares_use_every_group_and_the_title_says_when_groups_are_left_out() {
        let (d, mut r) = grouped_result();
        r.rows = (0..40)
            .map(|i| vec![json!(format!("g{i}")), json!(10)])
            .collect();
        let c = chart("en", &d, &r).unwrap();
        assert_eq!(c.bars.len(), MAX_BARS);
        // 10 of 400, not 10 of 300.
        assert_eq!(c.bars[0].share, "2,5 %");
        assert!(c.title.ends_with("(first 30 groups shown, 10 omitted)"));
        r.rows.truncate(2);
        assert!(!chart("nl", &d, &r).unwrap().title.contains("weggelaten"));
        assert_eq!(truncated_note("fr", 0), "");
        assert!(truncated_note("de", 5).contains("ausgelassen"));
    }
}
