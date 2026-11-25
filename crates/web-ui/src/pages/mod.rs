pub mod customers;
pub mod helpdesk;
pub mod kb;
pub mod login;
pub mod orders;
pub mod placeholder;
pub mod portal;
pub mod products;
pub mod quotations;
pub mod suppliers;

use std::str::FromStr;

use rust_decimal::Decimal;
use uuid::Uuid;

pub(crate) fn opt_trimmed(raw: &str) -> Option<String> {
    let trimmed = raw.trim();
    (!trimmed.is_empty()).then(|| trimmed.to_string())
}

pub(crate) fn parse_opt_decimal(label: &str, raw: &str) -> Result<Option<Decimal>, String> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return Ok(None);
    }
    Decimal::from_str(trimmed)
        .map(Some)
        .map_err(|_| format!("{label} must be a valid decimal number."))
}

pub(crate) fn parse_decimal(label: &str, raw: &str, default: Decimal) -> Result<Decimal, String> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return Ok(default);
    }
    Decimal::from_str(trimmed).map_err(|_| format!("{label} must be a valid decimal number."))
}

pub(crate) fn parse_opt_i32(label: &str, raw: &str) -> Result<Option<i32>, String> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return Ok(None);
    }
    trimmed
        .parse::<i32>()
        .map(Some)
        .map_err(|_| format!("{label} must be a whole integer."))
}

pub(crate) fn parse_i32(label: &str, raw: &str, default: i32) -> Result<i32, String> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return Ok(default);
    }
    trimmed
        .parse::<i32>()
        .map_err(|_| format!("{label} must be a whole integer."))
}

pub(crate) fn parse_uuid(label: &str, raw: &str) -> Result<Uuid, String> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return Err(format!("{label} is required."));
    }
    Uuid::parse_str(trimmed).map_err(|_| format!("{label} must be a valid UUID."))
}

pub(crate) fn fmt_opt_display<T: ToString>(value: Option<T>) -> String {
    value.map(|v| v.to_string()).unwrap_or_default()
}
