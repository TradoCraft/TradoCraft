//! PDF rendering with Typst.
//!
//! Templates live in `templates/*.typ` and read their data from `data.json`.
//! The API formats every amount itself (Belgian notation), so templates only
//! lay out text and never calculate.

use std::time::Duration;

use anyhow::{bail, Context};
use chrono::NaiveDate;
use rust_decimal::{Decimal, RoundingStrategy};
use serde::Serialize;
use tradocraft_core::DocumentConfig;

pub mod price_list;

/// Formats a money amount as `1.234,56` (Belgian/continental notation).
pub fn format_amount(d: Decimal) -> String {
    format_grouped(
        d.round_dp_with_strategy(2, RoundingStrategy::MidpointAwayFromZero),
        2,
    )
}

/// Formats a unit price with 2 to 4 decimals (`12,50`, `0,3125`).
pub fn format_unit_price(d: Decimal) -> String {
    let scale = d.normalize().scale().clamp(2, 4);
    format_grouped(
        d.round_dp_with_strategy(scale, RoundingStrategy::MidpointAwayFromZero),
        scale,
    )
}

/// Formats a quantity or percentage without trailing zeros (`2`, `2,5`).
pub fn format_number(d: Decimal) -> String {
    let n = d.normalize();
    format_grouped(n, n.scale())
}

pub fn format_date(d: NaiveDate) -> String {
    d.format("%d/%m/%Y").to_string()
}

fn format_grouped(d: Decimal, scale: u32) -> String {
    let negative = d.is_sign_negative() && !d.is_zero();
    let s = format!("{:.*}", scale as usize, d.abs());
    let (int_part, frac_part) = match s.split_once('.') {
        Some((i, f)) => (i.to_string(), Some(f.to_string())),
        None => (s, None),
    };
    let mut grouped = String::new();
    for (i, ch) in int_part.chars().enumerate() {
        if i > 0 && (int_part.len() - i) % 3 == 0 {
            grouped.push('.');
        }
        grouped.push(ch);
    }
    let mut out = if negative {
        format!("-{grouped}")
    } else {
        grouped
    };
    if let Some(f) = frac_part {
        out.push(',');
        out.push_str(&f);
    }
    out
}

/// Renders `templates/<template>.typ` with `data` to PDF bytes.
pub async fn render_pdf<T: Serialize>(
    config: &DocumentConfig,
    template: &str,
    data: &T,
) -> anyhow::Result<Vec<u8>> {
    render_pdf_with_files(config, template, data, &[]).await
}

/// Like [`render_pdf`], with extra files (images) placed next to `data.json`. `files` are
/// `(name, bytes)` pairs; a name must be a plain file name.
pub async fn render_pdf_with_files<T: Serialize>(
    config: &DocumentConfig,
    template: &str,
    data: &T,
    files: &[(String, Vec<u8>)],
) -> anyhow::Result<Vec<u8>> {
    let template_path = config.template_dir.join(format!("{template}.typ"));
    let work = tempfile::tempdir().context("creating temp dir")?;
    let main = work.path().join("main.typ");
    tokio::fs::copy(&template_path, &main)
        .await
        .with_context(|| format!("reading template {}", template_path.display()))?;
    tokio::fs::write(work.path().join("data.json"), serde_json::to_vec(data)?).await?;
    for (name, bytes) in files {
        if name.contains(['/', '\\']) || name.starts_with('.') {
            bail!("invalid attachment name {name}");
        }
        tokio::fs::write(work.path().join(name), bytes).await?;
    }
    let out = work.path().join("out.pdf");

    let child = tokio::process::Command::new(&config.typst_bin)
        .arg("compile")
        .arg("--root")
        .arg(work.path())
        .arg(&main)
        .arg(&out)
        .kill_on_drop(true)
        .output();
    let output = tokio::time::timeout(Duration::from_secs(30), child)
        .await
        .context("typst timed out")?
        .with_context(|| format!("running {}", config.typst_bin.display()))?;
    if !output.status.success() {
        bail!("typst failed: {}", String::from_utf8_lossy(&output.stderr));
    }
    Ok(tokio::fs::read(&out).await?)
}

#[cfg(test)]
mod tests {
    use super::*;
    use rust_decimal_macros::dec;

    #[test]
    fn amounts_use_belgian_notation() {
        assert_eq!(format_amount(dec!(0)), "0,00");
        assert_eq!(format_amount(dec!(12.5)), "12,50");
        assert_eq!(format_amount(dec!(999.999)), "1.000,00");
        assert_eq!(format_amount(dec!(1234567.891)), "1.234.567,89");
        assert_eq!(format_amount(dec!(-1234.5)), "-1.234,50");
    }

    #[test]
    fn unit_prices_keep_significant_decimals() {
        assert_eq!(format_unit_price(dec!(12.5000)), "12,50");
        assert_eq!(format_unit_price(dec!(0.3125)), "0,3125");
        assert_eq!(format_unit_price(dec!(1500)), "1.500,00");
    }

    #[test]
    fn numbers_drop_trailing_zeros() {
        assert_eq!(format_number(dec!(2.0000)), "2");
        assert_eq!(format_number(dec!(2.5)), "2,5");
        assert_eq!(format_number(dec!(1000)), "1.000");
    }
}
