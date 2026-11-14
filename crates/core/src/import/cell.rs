//! The typed value of one cell, whatever the file format.

use chrono::{NaiveDate, NaiveDateTime};
use rust_decimal::Decimal;

/// What one cell of an import file holds. CSV yields only `Empty` and `Text`; spreadsheets yield
/// every variant, as stored (not as displayed).
#[derive(Debug, Clone, PartialEq)]
pub enum CellValue {
    Empty,
    Text(String),
    /// An exact decimal. A spreadsheet's binary float arrives here through its shortest decimal
    /// representation (see [`CellValue::from_f64`]).
    Number(Decimal),
    Bool(bool),
    Date(NaiveDate),
    DateTime(NaiveDateTime),
}

impl CellValue {
    /// A text cell; the empty string is an empty cell.
    pub fn text(value: impl Into<String>) -> Self {
        let value = value.into();
        if value.is_empty() {
            CellValue::Empty
        } else {
            CellValue::Text(value)
        }
    }

    /// A whole number cell.
    pub fn int(value: i64) -> Self {
        CellValue::Number(Decimal::from(value))
    }

    /// A number read from a binary float. The float is turned into text with Rust's shortest
    /// round-trip representation and that text is read as a decimal, so `7.5` is exactly 7.5 and
    /// `0.1` is exactly 0.1 (not 0.1000000000000000055...). A float that has no exact decimal
    /// form (NaN, infinite, out of range, more than 28 decimals) is an error and is never rounded.
    pub fn from_f64(value: f64) -> Result<Self, String> {
        if !value.is_finite() {
            return Err(format!("{value} is not a finite number"));
        }
        let text = format!("{value}");
        match Decimal::from_str_exact(&text) {
            Ok(d) => Ok(CellValue::Number(d)),
            Err(_) => Err(match text.parse::<Decimal>() {
                Ok(_) => format!("{text} has more digits than can be stored without rounding"),
                Err(_) => format!("{text} is out of range"),
            }),
        }
    }

    /// The text form of the value, `None` for an empty cell: a number without trailing zeros, a
    /// boolean as `true`/`false`, a date or date-time in ISO 8601.
    pub fn render(&self) -> Option<String> {
        match self {
            CellValue::Empty => None,
            CellValue::Text(s) => Some(s.clone()),
            CellValue::Number(d) => Some(crate::csv_io::format_decimal(*d)),
            CellValue::Bool(b) => Some(b.to_string()),
            CellValue::Date(d) => Some(d.format("%Y-%m-%d").to_string()),
            CellValue::DateTime(d) => Some(d.format("%Y-%m-%dT%H:%M:%S%.f").to_string()),
        }
    }

    /// True for an empty cell and for a text cell of only spaces.
    pub fn is_blank(&self) -> bool {
        match self {
            CellValue::Empty => true,
            CellValue::Text(s) => s.trim().is_empty(),
            _ => false,
        }
    }
}

/// The `f64` closest to `d` when it reads back as exactly `d`; `None` when a spreadsheet number
/// (a binary double) could not hold the decimal without rounding.
pub(crate) fn exact_f64(d: Decimal) -> Option<f64> {
    use rust_decimal::prelude::ToPrimitive;
    let f = d.to_f64()?;
    match CellValue::from_f64(f) {
        Ok(CellValue::Number(back)) if back == d => Some(f),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use rust_decimal_macros::dec;

    #[test]
    fn floats_become_their_shortest_decimal() {
        for (f, d) in [
            (7.5, dec!(7.5)),
            (0.1, dec!(0.1)),
            (1234567.89, dec!(1234567.89)),
            (-0.25, dec!(-0.25)),
            (1000.0, dec!(1000)),
            (0.30000000000000004, dec!(0.30000000000000004)),
        ] {
            assert_eq!(CellValue::from_f64(f).unwrap(), CellValue::Number(d), "{f}");
        }
    }

    #[test]
    fn floats_without_an_exact_decimal_are_errors() {
        assert!(CellValue::from_f64(f64::NAN).is_err());
        assert!(CellValue::from_f64(f64::INFINITY).is_err());
        assert!(CellValue::from_f64(1e300)
            .unwrap_err()
            .contains("out of range"));
        assert!(CellValue::from_f64(1e-30)
            .unwrap_err()
            .contains("more digits"));
    }

    #[test]
    fn rendering() {
        assert_eq!(CellValue::Empty.render(), None);
        assert_eq!(CellValue::int(1000).render().unwrap(), "1000");
        assert_eq!(CellValue::Number(dec!(12.50)).render().unwrap(), "12.5");
        assert_eq!(CellValue::Bool(true).render().unwrap(), "true");
        let d = NaiveDate::from_ymd_opt(2024, 1, 31).unwrap();
        assert_eq!(CellValue::Date(d).render().unwrap(), "2024-01-31");
        let t = d.and_hms_opt(10, 30, 5).unwrap();
        assert_eq!(
            CellValue::DateTime(t).render().unwrap(),
            "2024-01-31T10:30:05"
        );
        let t = d.and_hms_milli_opt(10, 30, 5, 250).unwrap();
        assert_eq!(
            CellValue::DateTime(t).render().unwrap(),
            "2024-01-31T10:30:05.250"
        );
    }

    #[test]
    fn exact_f64_refuses_what_a_double_cannot_hold() {
        assert_eq!(exact_f64(dec!(0.1)), Some(0.1));
        assert_eq!(exact_f64(dec!(1234567.89)), Some(1234567.89));
        assert_eq!(exact_f64(dec!(0.1234567890123456789012345678)), None);
    }
}
