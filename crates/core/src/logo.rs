//! The company logo: one small PNG, JPEG or SVG per company, kept in PostgreSQL. The type is
//! decided from the first bytes, never from the declared content type. Documents load it with
//! [`load`]; the administrator manages it through `/admin/company/logo` (see `admin.rs`).
//! Uploads are decoded (PNG, JPEG) or parsed (SVG) before they are kept, so a truncated or
//! corrupt file is refused instead of failing later inside the PDF renderer.

use sqlx::PgConnection;
use uuid::Uuid;

use crate::{AppError, AppResult};

/// Largest accepted logo.
pub const MAX_LOGO_BYTES: usize = 512 * 1024;

pub const PNG: &str = "image/png";
pub const JPEG: &str = "image/jpeg";
pub const SVG: &str = "image/svg+xml";

/// File extension for a stored logo type (used to name the file handed to the PDF renderer).
pub fn extension(content_type: &str) -> &'static str {
    match content_type {
        PNG => "png",
        SVG => "svg",
        _ => "jpg",
    }
}

/// Largest accepted side, and number of pixels, of a PNG or JPEG logo (bounds decoding memory).
const MAX_SIDE: u32 = 8192;
const MAX_PIXELS: u64 = 9_000_000;

/// Checks a logo upload and returns its content type: size, signature, that a PNG or JPEG
/// decodes completely and an SVG is well-formed XML, and for SVG that it carries nothing active
/// (scripts, foreign content, event handlers, external references).
pub fn validate(bytes: &[u8]) -> AppResult<&'static str> {
    if bytes.is_empty() {
        return Err(AppError::Validation("the logo is empty".into()));
    }
    if bytes.len() > MAX_LOGO_BYTES {
        return Err(AppError::Validation(format!(
            "the logo is too large (at most {} KB)",
            MAX_LOGO_BYTES / 1024
        )));
    }
    if bytes.starts_with(&[0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A]) {
        decode_png(bytes).map_err(|why| AppError::Validation(format!("the PNG logo is {why}")))?;
        Ok(PNG)
    } else if bytes.starts_with(&[0xFF, 0xD8, 0xFF]) {
        decode_jpeg(bytes)
            .map_err(|why| AppError::Validation(format!("the JPEG logo is {why}")))?;
        Ok(JPEG)
    } else if let Some(reason) = svg_problem(bytes) {
        Err(AppError::Validation(match reason {
            None => "the logo must be a PNG, JPEG or SVG image".to_string(),
            Some(why) => format!("the SVG logo is not accepted: {why}"),
        }))
    } else {
        Ok(SVG)
    }
}

fn check_dimensions(width: u32, height: u32) -> Result<(), String> {
    if width == 0 || height == 0 {
        return Err("empty".into());
    }
    if width > MAX_SIDE || height > MAX_SIDE || u64::from(width) * u64::from(height) > MAX_PIXELS {
        return Err("too large in pixels".into());
    }
    Ok(())
}

/// Decodes the first frame completely and checks the stream ends properly.
fn decode_png(bytes: &[u8]) -> Result<(), String> {
    let corrupt = |e: png::DecodingError| format!("not a valid image ({e})");
    let mut reader = png::Decoder::new(std::io::Cursor::new(bytes))
        .read_info()
        .map_err(corrupt)?;
    let info = reader.info();
    check_dimensions(info.width, info.height)?;
    let size = reader
        .output_buffer_size()
        .ok_or_else(|| "too large in pixels".to_string())?;
    let mut buf = vec![0; size];
    reader.next_frame(&mut buf).map_err(corrupt)?;
    reader.finish().map_err(corrupt)
}

/// Decodes the whole image.
fn decode_jpeg(bytes: &[u8]) -> Result<(), String> {
    let corrupt = |e: zune_jpeg::errors::DecodeErrors| format!("not a valid image ({e:?})");
    let mut decoder =
        zune_jpeg::JpegDecoder::new(zune_jpeg::zune_core::bytestream::ZCursor::new(bytes));
    decoder.decode_headers().map_err(corrupt)?;
    let (width, height) = decoder
        .dimensions()
        .ok_or_else(|| "not a valid image".to_string())?;
    check_dimensions(width as u32, height as u32)?;
    decoder.decode().map_err(corrupt)?;
    Ok(())
}

/// The document is well-formed XML whose root element is `svg`.
fn svg_is_well_formed(text: &str) -> bool {
    use quick_xml::events::Event;
    let mut reader = quick_xml::Reader::from_str(text);
    let (mut depth, mut root_seen) = (0usize, false);
    loop {
        match reader.read_event() {
            Ok(Event::Start(e)) => {
                if depth == 0 {
                    if root_seen || e.local_name().as_ref() != "svg" {
                        return false;
                    }
                    root_seen = true;
                }
                depth += 1;
            }
            Ok(Event::Empty(e)) => {
                if depth == 0 {
                    if root_seen || e.local_name().as_ref() != "svg" {
                        return false;
                    }
                    root_seen = true;
                }
            }
            Ok(Event::End(_)) => depth = depth.saturating_sub(1),
            Ok(Event::Eof) => return root_seen && depth == 0,
            Err(_) => return false,
            _ => {}
        }
    }
}

/// `None` when `bytes` is an acceptable SVG; `Some(None)` when it is not an SVG at all;
/// `Some(Some(why))` when it is an SVG with active or external content.
fn svg_problem(bytes: &[u8]) -> Option<Option<&'static str>> {
    let Ok(text) = std::str::from_utf8(bytes) else {
        return Some(None);
    };
    let text = text.trim_start_matches('\u{feff}').trim_start();
    if !(text.starts_with("<?xml") || text.starts_with("<svg") || text.starts_with("<!--")) {
        return Some(None);
    }
    let lower = text.to_ascii_lowercase();
    if !lower.contains("<svg") {
        return Some(None);
    }
    for (needle, why) in [
        ("<script", "scripts are not allowed"),
        ("<foreignobject", "foreignObject is not allowed"),
        ("<!entity", "entity declarations are not allowed"),
        ("<!doctype", "a document type is not allowed"),
        ("javascript:", "scripts are not allowed"),
        ("<iframe", "embedded documents are not allowed"),
        ("<embed", "embedded documents are not allowed"),
        ("<object", "embedded documents are not allowed"),
        ("<animate", "animation is not allowed"),
        ("<set", "animation is not allowed"),
    ] {
        if lower.contains(needle) {
            return Some(Some(why));
        }
    }
    if has_event_handler(&lower) {
        return Some(Some("event handlers are not allowed"));
    }
    if has_external_reference(&lower) {
        return Some(Some("external references are not allowed"));
    }
    if !svg_is_well_formed(text) {
        return Some(Some("it is not well-formed (truncated or malformed)"));
    }
    None
}

/// An attribute like `onload=` or `onclick =` outside of a word (so `font="..."` is fine).
fn has_event_handler(lower: &str) -> bool {
    let b = lower.as_bytes();
    let mut from = 0;
    while let Some(at) = lower[from..].find("on") {
        let i = from + at;
        from = i + 2;
        if i == 0 || !(b[i - 1].is_ascii_whitespace() || b[i - 1] == b'"' || b[i - 1] == b'\'') {
            continue;
        }
        let name_end = lower[i..]
            .find(|c: char| !c.is_ascii_alphabetic())
            .map_or(lower.len(), |n| i + n);
        if name_end > i + 2 && lower[name_end..].trim_start().starts_with('=') {
            return true;
        }
    }
    false
}

/// An `href` / `xlink:href` / `src` or `url(...)` pointing anywhere but inside the document
/// (`#id`) or at a `data:` image.
fn has_external_reference(lower: &str) -> bool {
    let mut rest = lower;
    while let Some(at) = rest.find("href") {
        rest = &rest[at + 4..];
        let value = rest.trim_start();
        let Some(value) = value.strip_prefix('=') else {
            continue;
        };
        let value = value.trim_start().trim_start_matches(['"', '\'']);
        if !(value.starts_with('#') || value.starts_with("data:image/")) {
            return true;
        }
    }
    let mut rest = lower;
    while let Some(at) = rest.find("url(") {
        rest = &rest[at + 4..];
        let value = rest.trim_start().trim_start_matches(['"', '\'']);
        if !value.starts_with('#') {
            return true;
        }
    }
    false
}

/// A stored logo.
pub struct Logo {
    pub content_type: String,
    pub bytes: Vec<u8>,
    pub updated_at: chrono::DateTime<chrono::Utc>,
}

/// The company's logo, if one was uploaded.
pub async fn load(conn: &mut PgConnection, company_id: Uuid) -> AppResult<Option<Logo>> {
    let row: Option<(String, Vec<u8>, chrono::DateTime<chrono::Utc>)> = sqlx::query_as(
        "SELECT content_type, bytes, updated_at FROM core.company_logos WHERE company_id = $1",
    )
    .bind(company_id)
    .fetch_optional(conn)
    .await?;
    Ok(row.map(|(content_type, bytes, updated_at)| Logo {
        content_type,
        bytes,
        updated_at,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A valid 1x1 PNG.
    const PNG_BYTES: [u8; 69] = [
        0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44,
        0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x02, 0x00, 0x00, 0x00, 0x90,
        0x77, 0x53, 0xde, 0x00, 0x00, 0x00, 0x0c, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0xf8,
        0xcf, 0xc0, 0x00, 0x00, 0x03, 0x01, 0x01, 0x00, 0xc9, 0xfe, 0x92, 0xef, 0x00, 0x00, 0x00,
        0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
    ];
    /// A valid 1x1 grayscale JPEG (base64).
    const JPEG_B64: &str = "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDABALDA4MChAODQ4SERATGCgaGBYWGDEjJR0oOjM9PDkzODdASFxOQERXRTc4UG1RV19iZ2hnPk1xeXBkeFxlZ2P/wAALCAABAAEBAREA/8QAFAABAAAAAAAAAAAAAAAAAAAAAP/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AP//Z";

    fn jpeg_bytes() -> Vec<u8> {
        use base64::Engine;
        base64::engine::general_purpose::STANDARD
            .decode(JPEG_B64)
            .unwrap()
    }

    fn check(b: &[u8]) -> Result<&'static str, String> {
        validate(b).map_err(|e| e.to_string())
    }

    #[test]
    fn signatures_decide_the_type() {
        assert_eq!(check(&PNG_BYTES), Ok(PNG));
        assert_eq!(check(&jpeg_bytes()), Ok(JPEG));
        assert_eq!(
            check(
                b"<?xml version=\"1.0\"?>\n<svg xmlns=\"http://www.w3.org/2000/svg\"><rect/></svg>"
            ),
            Ok(SVG)
        );
        assert_eq!(
            check(
                "\u{feff}  <svg viewBox=\"0 0 1 1\"><path d=\"M0 0\" fill=\"url(#a)\"/></svg>"
                    .as_bytes()
            ),
            Ok(SVG)
        );
    }

    #[test]
    fn other_content_is_refused() {
        for bytes in [
            &b"GIF89a....."[..],
            b"%PDF-1.7",
            b"RIFF\0\0\0\0WEBPVP8 ",
            b"<html><svg></svg></html>",
            b"plain text <svg>",
            &[0xFF, 0xFE, 0x00][..],
        ] {
            assert!(check(bytes).is_err(), "{bytes:?}");
        }
        assert!(check(b"").is_err());
    }

    #[test]
    fn size_is_limited() {
        let mut big = PNG_BYTES.to_vec();
        big.resize(MAX_LOGO_BYTES + 1, 0);
        assert!(check(&big).unwrap_err().contains("too large"));
    }

    #[test]
    fn truncated_or_corrupt_images_are_refused() {
        let jpeg = jpeg_bytes();
        for bytes in [
            PNG_BYTES[..8].to_vec(),
            PNG_BYTES[..40].to_vec(),
            PNG_BYTES[..PNG_BYTES.len() - 12].to_vec(), // no IEND
            {
                let mut v = PNG_BYTES.to_vec();
                v[30] ^= 0xFF; // IHDR checksum
                v
            },
            vec![0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0],
            jpeg[..3].to_vec(),
            jpeg[..jpeg.len() / 2].to_vec(),
            vec![0xFF, 0xD8, 0xFF, 0xE0, 1, 2],
        ] {
            assert!(check(&bytes).is_err(), "{} bytes", bytes.len());
        }
    }

    #[test]
    fn malformed_svg_is_refused() {
        for svg in [
            "<svg xmlns=\"http://www.w3.org/2000/svg\"><rect/>",
            "<svg><g></svg>",
            "<svg xmlns=\"http://www.w3.org/2000/svg\"><rect",
            "<svg></svg><svg></svg>",
            "<?xml version=\"1.0\"?><svg>",
            "<!-- <svg> -->",
        ] {
            assert!(check(svg.as_bytes()).is_err(), "{svg}");
        }
    }

    #[test]
    fn active_svg_content_is_refused() {
        for svg in [
            "<svg><script>alert(1)</script></svg>",
            "<svg><SCRIPT src=x></SCRIPT></svg>",
            "<svg><foreignObject><div/></foreignObject></svg>",
            "<svg onload=\"x()\"></svg>",
            "<svg\n onclick = 'x()'></svg>",
            "<svg><a href=\"javascript:x()\"><rect/></a></svg>",
            "<svg><image href=\"http://evil/x.png\"/></svg>",
            "<svg><image xlink:href=\"file:///etc/passwd\"/></svg>",
            "<svg><rect style=\"fill:url(http://evil/x)\"/></svg>",
            "<!DOCTYPE svg [<!ENTITY a \"b\">]><svg/>",
            "<svg><animate attributeName=\"href\"/></svg>",
        ] {
            assert!(check(svg.as_bytes()).is_err(), "{svg}");
        }
    }

    #[test]
    fn harmless_attributes_with_on_in_the_name_pass() {
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\"><text font-weight=\"bold\" \
                   text-anchor=\"middle\">Acme</text><image href=\"data:image/png;base64,AAAA\"/></svg>";
        assert_eq!(check(svg.as_bytes()), Ok(SVG));
    }

    #[test]
    fn extensions_follow_the_type() {
        assert_eq!(extension(PNG), "png");
        assert_eq!(extension(JPEG), "jpg");
        assert_eq!(extension(SVG), "svg");
    }
}
