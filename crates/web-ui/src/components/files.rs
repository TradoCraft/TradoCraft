//! Shared browser file picking, authenticated Blob/PDF downloads, and file size formatting.

use std::future::Future;

#[cfg(target_arch = "wasm32")]
use leptos::task::spawn_local;
use tradocraft_api_client::{ApiError, Client};

use crate::components::async_ops::spawn_api;
use crate::components::feedback::Feedback;
use crate::state::AppContext;

/// A file selected by the user in a browser file input.
pub struct PickedFile {
    pub name: String,
    pub bytes: Vec<u8>,
}

/// Reads the first file chosen in a `<input type="file">` change event, clears the input so the
/// same file can be picked again, and runs `validate(name, len)` before reading its bytes into
/// memory. Calls `done(Err(String::new()))` when the file dialog is cancelled.
#[cfg(target_arch = "wasm32")]
pub fn begin_file_read_validated<V, D>(ev: leptos::ev::Event, validate: V, done: D)
where
    V: FnOnce(&str, usize) -> Result<(), String>,
    D: FnOnce(Result<PickedFile, String>) + 'static,
{
    use wasm_bindgen::JsCast;
    let Some(input) = ev
        .target()
        .and_then(|t| t.dyn_into::<web_sys::HtmlInputElement>().ok())
    else {
        done(Err(String::new()));
        return;
    };
    let Some(file) = input.files().and_then(|list| list.get(0)) else {
        done(Err(String::new()));
        return;
    };
    input.set_value("");
    let name = file.name();
    let size = file.size() as usize;
    if let Err(msg) = validate(&name, size) {
        done(Err(msg));
        return;
    }
    spawn_local(async move {
        let result = wasm_bindgen_futures::JsFuture::from(file.array_buffer())
            .await
            .map(|buffer| PickedFile {
                name,
                bytes: js_sys::Uint8Array::new(&buffer).to_vec(),
            })
            .map_err(|_| "The file could not be read.".to_string());
        done(result);
    });
}

#[cfg(not(target_arch = "wasm32"))]
pub fn begin_file_read_validated<V, D>(_ev: leptos::ev::Event, _validate: V, done: D)
where
    V: FnOnce(&str, usize) -> Result<(), String>,
    D: FnOnce(Result<PickedFile, String>) + 'static,
{
    done(Err("Choosing files needs the browser build.".to_string()));
}

/// Reads the first file chosen in a `<input type="file">` change event, rejecting files larger
/// than `max_bytes` with `too_big` before loading their bytes into memory.
pub fn begin_file_read(
    ev: leptos::ev::Event,
    max_bytes: usize,
    too_big: &'static str,
    done: impl FnOnce(Result<PickedFile, String>) + 'static,
) {
    begin_file_read_validated(
        ev,
        move |_, len| {
            if len > max_bytes {
                Err(too_big.to_string())
            } else {
                Ok(())
            }
        },
        done,
    );
}

/// Offers `bytes` to the browser as a file download using a temporary Blob object URL.
#[cfg(target_arch = "wasm32")]
pub fn save_file(filename: &str, content_type: &str, bytes: &[u8]) -> Result<(), String> {
    use wasm_bindgen::JsCast;
    let fail = |_| "The browser could not save the file.".to_string();
    let parts = js_sys::Array::new();
    parts.push(&js_sys::Uint8Array::from(bytes));
    let options = web_sys::BlobPropertyBag::new();
    options.set_type(content_type);
    let blob =
        web_sys::Blob::new_with_u8_array_sequence_and_options(&parts, &options).map_err(fail)?;
    let url = web_sys::Url::create_object_url_with_blob(&blob).map_err(fail)?;
    let anchor = web_sys::window()
        .and_then(|w| w.document())
        .and_then(|d| d.create_element("a").ok())
        .and_then(|e| e.dyn_into::<web_sys::HtmlAnchorElement>().ok())
        .ok_or_else(|| "The browser could not save the file.".to_string())?;
    anchor.set_href(&url);
    anchor.set_download(filename);
    anchor.click();
    let _ = web_sys::Url::revoke_object_url(&url);
    Ok(())
}

#[cfg(not(target_arch = "wasm32"))]
pub fn save_file(_filename: &str, _content_type: &str, _bytes: &[u8]) -> Result<(), String> {
    Err("Downloading files needs the browser build.".to_string())
}

/// Offers `bytes` to the browser as a PDF file download.
pub fn save_pdf(filename: &str, bytes: &[u8]) -> Result<(), String> {
    save_file(filename, "application/pdf", bytes)
}

/// Fetches an authenticated file via `fetch`, saves it as `filename`, and reports the outcome on
/// `fb`.
pub fn download_api_file<F, Fut>(
    ctx: AppContext,
    fb: Feedback,
    filename: String,
    content_type: &'static str,
    fetch: F,
) where
    F: FnOnce(Client) -> Fut + 'static,
    Fut: Future<Output = Result<Vec<u8>, ApiError>> + 'static,
{
    spawn_api(ctx, fetch, move |res| match res {
        Ok(bytes) => match save_file(&filename, content_type, &bytes) {
            Ok(()) => {
                fb.ok(format!("Downloaded {filename}."));
            }
            Err(err) => {
                fb.fail(err);
            }
        },
        Err(err) => {
            fb.fail(err.user_message());
        }
    });
}

/// Fetches an authenticated PDF document via `fetch`, saves it as `filename`, and reports the
/// outcome on `fb`.
pub fn download_api_pdf<F, Fut>(ctx: AppContext, fb: Feedback, filename: String, fetch: F)
where
    F: FnOnce(Client) -> Fut + 'static,
    Fut: Future<Output = Result<Vec<u8>, ApiError>> + 'static,
{
    download_api_file(ctx, fb, filename, "application/pdf", fetch);
}

/// Human-readable file size such as `512 B`, `1.5 KB`, or `3.0 MB`.
pub fn format_file_size(bytes: i64) -> String {
    const KB: f64 = 1024.0;
    let clamped = bytes.max(0);
    let b = clamped as f64;
    if b < KB {
        format!("{clamped} B")
    } else if b < KB * KB {
        format!("{:.1} KB", b / KB)
    } else {
        format!("{:.1} MB", b / (KB * KB))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn formats_file_sizes_across_units() {
        assert_eq!(format_file_size(-5), "0 B");
        assert_eq!(format_file_size(0), "0 B");
        assert_eq!(format_file_size(512), "512 B");
        assert_eq!(format_file_size(1023), "1023 B");
        assert_eq!(format_file_size(1536), "1.5 KB");
        assert_eq!(format_file_size(3 * 1024 * 1024), "3.0 MB");
    }
}
