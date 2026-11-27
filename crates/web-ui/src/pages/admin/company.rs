//! Administration, section "Company": the company logo (preview, upload with type and size checks,
//! remove) and the company-wide quotation layout and draft autosave settings. Mirrors
//! `company_logo_page.dart`.

use leptos::prelude::*;
use tradocraft_api_client::admin::CompanySettingsInput;

use super::{begin_file_read, file_size, refresh_me, spawn_api, Feedback, FeedbackView};
use crate::pages::set_alive;
use crate::state::AppContext;

/// The server's limit for the logo.
pub(crate) const MAX_LOGO_BYTES: usize = 512 * 1024;

/// The autosave intervals offered, in minutes (0 = off).
const AUTOSAVE_OPTIONS: [i32; 7] = [0, 1, 2, 5, 10, 15, 30];

/// `image/png`, `image/jpeg` or `image/svg+xml` from the first bytes, the way the server reads
/// them; none for anything else.
pub(crate) fn logo_content_type(b: &[u8]) -> Option<&'static str> {
    if b.len() >= 8 && b[..4] == [0x89, 0x50, 0x4e, 0x47] {
        return Some("image/png");
    }
    if b.len() >= 3 && b[..3] == [0xff, 0xd8, 0xff] {
        return Some("image/jpeg");
    }
    let head: String = b
        .iter()
        .take(512)
        .map(|c| (*c as char).to_ascii_lowercase())
        .collect();
    if head.contains("<svg") || (head.contains("<?xml") && head.contains("svg")) {
        return Some("image/svg+xml");
    }
    None
}

/// Checks a chosen logo before it is sent (the server checks again).
pub(crate) fn check_logo(bytes: &[u8]) -> Result<(), &'static str> {
    if bytes.len() > MAX_LOGO_BYTES {
        return Err("The file is larger than 512 KB.");
    }
    if logo_content_type(bytes).is_none() {
        return Err("Only PNG, JPEG or SVG files are accepted.");
    }
    Ok(())
}

/// An object URL for the logo bytes, for the preview image.
#[cfg(target_arch = "wasm32")]
fn object_url(bytes: &[u8], content_type: &str) -> Option<String> {
    let parts = js_sys::Array::new();
    parts.push(&js_sys::Uint8Array::from(bytes));
    let options = web_sys::BlobPropertyBag::new();
    options.set_type(content_type);
    let blob = web_sys::Blob::new_with_u8_array_sequence_and_options(&parts, &options).ok()?;
    web_sys::Url::create_object_url_with_blob(&blob).ok()
}

#[cfg(not(target_arch = "wasm32"))]
fn object_url(_bytes: &[u8], _content_type: &str) -> Option<String> {
    None
}

#[cfg(target_arch = "wasm32")]
fn revoke_url(url: &str) {
    let _ = web_sys::Url::revoke_object_url(url);
}

#[cfg(not(target_arch = "wasm32"))]
fn revoke_url(_url: &str) {}

/// The loaded logo: its bytes' type and size and a preview URL.
#[derive(Debug, Clone, PartialEq, Eq)]
struct Logo {
    content_type: String,
    size: usize,
    url: Option<String>,
}

#[component]
pub fn CompanySection() -> impl IntoView {
    let ctx = expect_context::<AppContext>();
    let fb = Feedback::new();

    // None = loading, Some(None) = no logo.
    let logo = RwSignal::new(Option::<Option<Logo>>::None);
    let logo_error = RwSignal::new(Option::<String>::None);
    let reload = RwSignal::new(0_u64);
    let busy = RwSignal::new(false);
    let confirm_remove = RwSignal::new(false);

    Effect::new(move |_| {
        let _ = reload.get();
        logo_error.set(None);
        spawn_api(
            ctx,
            |c| async move { c.company_logo().await },
            move |res| match res {
                Ok(bytes) => {
                    let next = bytes.map(|b| {
                        let ct = logo_content_type(&b).unwrap_or("application/octet-stream");
                        Logo {
                            content_type: ct.to_string(),
                            size: b.len(),
                            url: object_url(&b, ct),
                        }
                    });
                    let previous = logo.try_get_untracked().flatten().flatten();
                    if set_alive(logo, Some(next)) {
                        if let Some(url) = previous.and_then(|l| l.url) {
                            revoke_url(&url);
                        }
                    }
                }
                Err(err) => {
                    if set_alive(logo_error, Some(err.user_message())) {
                        logo.set(Some(None));
                    }
                }
            },
        );
    });
    on_cleanup(move || {
        if let Some(url) = logo
            .try_get_untracked()
            .flatten()
            .flatten()
            .and_then(|l| l.url)
        {
            revoke_url(&url);
        }
    });

    let on_choose = move |ev: leptos::ev::Event| {
        begin_file_read(
            ev,
            MAX_LOGO_BYTES,
            "The file is larger than 512 KB.",
            move |res| {
                let picked = match res {
                    Ok(p) => p,
                    Err(msg) => {
                        if !msg.is_empty() {
                            fb.fail(msg);
                        }
                        return;
                    }
                };
                if let Err(msg) = check_logo(&picked.bytes) {
                    fb.fail(msg);
                    return;
                }
                if !set_alive(busy, true) {
                    return;
                }
                spawn_api(
                    ctx,
                    move |c| async move { c.upload_company_logo(picked.bytes).await },
                    move |res| {
                        if !set_alive(busy, false) {
                            return;
                        }
                        match res {
                            Ok(_) => {
                                fb.ok("Logo saved");
                                reload.update(|n| *n += 1);
                            }
                            Err(err) => {
                                fb.fail(err.user_message());
                            }
                        }
                    },
                );
            },
        );
    };

    let on_remove = move |_| {
        confirm_remove.set(false);
        busy.set(true);
        spawn_api(
            ctx,
            |c| async move { c.delete_company_logo().await },
            move |res| {
                if !set_alive(busy, false) {
                    return;
                }
                match res {
                    Ok(()) => {
                        fb.ok("Logo removed");
                        reload.update(|n| *n += 1);
                    }
                    Err(err) => {
                        fb.fail(err.user_message());
                    }
                }
            },
        );
    };

    let company = Memo::new(move |_| {
        ctx.session.with(|s| {
            s.as_ref().map(|a| {
                (
                    a.me.company.quotation_single_line_items,
                    a.me.company.autosave_minutes,
                )
            })
        })
    });
    // What was just saved, shown until the refreshed company confirms it.
    let pending = RwSignal::new(Option::<(bool, i32)>::None);
    let settings = Memo::new(move |_| pending.get().or(company.get()).unwrap_or((true, 5)));
    Effect::new(move |_| {
        if pending.get_untracked().is_some() && company.get() == pending.get_untracked() {
            pending.set(None);
        }
    });

    let save_settings = move |single_line: bool, autosave: i32| {
        busy.set(true);
        let body = CompanySettingsInput {
            quotation_single_line_items: single_line,
            autosave_minutes: Some(autosave),
        };
        spawn_api(
            ctx,
            move |c| async move { c.update_company_settings(&body).await },
            move |res| {
                if !set_alive(busy, false) {
                    return;
                }
                match res {
                    Ok(_) => {
                        pending.set(Some((single_line, autosave)));
                        fb.ok("Company settings saved");
                        refresh_me(ctx);
                    }
                    Err(err) => {
                        fb.fail(err.user_message());
                    }
                }
            },
        );
    };

    view! {
        <section data-target="admin-company" aria-labelledby="admin-company-title">
            <h2 id="admin-company-title" class="tc-page-title" style="font-size: 18px;">"Company logo"</h2>
            <p style="color: var(--on-surface-variant);">
                "PNG, JPEG or SVG, at most 512 KB. Printed in the header of price lists."
            </p>
            <FeedbackView fb prefix="admin-company" />
            {move || match (logo.get(), logo_error.get()) {
                (_, Some(msg)) => view! {
                    <div class="tc-alert-error" role="alert" data-target="admin-logo-error">
                        {msg}
                        " "
                        <button type="button" class="tc-btn tc-btn-sm" data-target="admin-logo-retry" on:click=move |_| reload.update(|n| *n += 1)>
                            "Retry"
                        </button>
                    </div>
                }.into_any(),
                (None, None) => view! { <p class="tc-label">"Loading logo..."</p> }.into_any(),
                (Some(None), None) => view! {
                    <p data-target="admin-logo-none">"No logo uploaded."</p>
                }.into_any(),
                (Some(Some(l)), None) => view! {
                    <div data-target="admin-logo-preview">
                        <div style="max-width: 320px; max-height: 160px; padding: 8px; background: #fff; border: 1px solid var(--outline); display: inline-block;">
                            {l.url.map(|url| view! {
                                <img src=url alt="Company logo" style="max-width: 300px; max-height: 140px; object-fit: contain; display: block;" />
                            })}
                        </div>
                        <p class="tc-label" data-target="admin-logo-info">
                            {format!("{} \u{b7} {}", l.content_type, file_size(l.size as i64))}
                        </p>
                    </div>
                }.into_any(),
            }}
            <div class="tc-toolbar" style="margin-top: var(--space-md);">
                <label class="tc-label" for="admin-logo-choose">"Choose file"</label>
                <input
                    id="admin-logo-choose"
                    type="file"
                    class="tc-input"
                    data-target="admin-logo-choose"
                    accept=".png,.jpg,.jpeg,.svg,image/png,image/jpeg,image/svg+xml"
                    disabled=move || busy.get()
                    on:change=on_choose
                />
                <Show when=move || matches!(logo.get(), Some(Some(_)))>
                    <button
                        type="button"
                        data-target="admin-logo-remove"
                        class="tc-btn"
                        disabled=move || busy.get()
                        on:click=move |_| confirm_remove.set(true)
                    >
                        "Remove logo"
                    </button>
                </Show>
            </div>
            <Show when=move || confirm_remove.get()>
                <div class="tc-toolbar" role="alert" data-target="admin-logo-remove-confirm-row">
                    <span>"Remove the company logo?"</span>
                    <button type="button" class="tc-btn tc-btn-primary tc-btn-sm" data-target="admin-logo-remove-confirm" on:click=on_remove>
                        "Remove logo"
                    </button>
                    <button type="button" class="tc-btn tc-btn-sm" on:click=move |_| confirm_remove.set(false)>"Cancel"</button>
                </div>
            </Show>

            <h2 class="tc-page-title" style="font-size: 18px; margin-top: var(--space-xl);">"Quotation item layout"</h2>
            <label class="tc-checkbox-row">
                <input
                    type="checkbox"
                    role="switch"
                    data-target="admin-quotation-single-line"
                    aria-describedby="admin-quotation-single-line-help"
                    prop:checked=move || settings.get().0
                    disabled=move || busy.get()
                    on:change=move |ev| {
                        let on = event_target_checked(&ev);
                        save_settings(on, settings.get_untracked().1);
                    }
                />
                "Single line per item"
            </label>
            <p id="admin-quotation-single-line-help" class="tc-label" style="margin-top: 0;">
                "Show each item on one compact row with remarks in a dialog; turn off to show remark fields on a second line."
            </p>

            <h2 class="tc-page-title" style="font-size: 18px; margin-top: var(--space-xl);">"Draft autosave"</h2>
            <p style="color: var(--on-surface-variant);">
                "Default interval for autosaving open drafts (users can override this in their preferences)."
            </p>
            <div class="tc-field" style="max-width: 320px;">
                <label class="tc-label" for="admin-autosave-minutes">"Draft autosave"</label>
                <select
                    id="admin-autosave-minutes"
                    data-target="admin-autosave-minutes"
                    class="tc-select"
                    disabled=move || busy.get()
                    on:change=move |ev| {
                        if let Ok(m) = event_target_value(&ev).parse::<i32>() {
                            save_settings(settings.get_untracked().0, m);
                        }
                    }
                >
                    {AUTOSAVE_OPTIONS.into_iter().map(|m| {
                        let label = if m == 0 { "Off".to_string() } else { format!("{m} min") };
                        view! {
                            <option
                                value=m.to_string()
                                selected=move || {
                                    let current = settings.get().1;
                                    let shown = if AUTOSAVE_OPTIONS.contains(&current) { current } else { 5 };
                                    shown == m
                                }
                            >
                                {label}
                            </option>
                        }
                    }).collect_view()}
                </select>
            </div>
        </section>
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sniffs_png_jpeg_and_svg() {
        assert_eq!(
            logo_content_type(&[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
            Some("image/png")
        );
        assert_eq!(
            logo_content_type(&[0xff, 0xd8, 0xff, 0xe0]),
            Some("image/jpeg")
        );
        assert_eq!(
            logo_content_type(b"<?xml version=\"1.0\"?><SVG xmlns=\"\">"),
            Some("image/svg+xml")
        );
        assert_eq!(logo_content_type(b"GIF89a"), None);
    }

    #[test]
    fn refuses_large_or_unknown_files() {
        assert!(check_logo(b"<svg/>").is_ok());
        assert_eq!(
            check_logo(b"hello").unwrap_err(),
            "Only PNG, JPEG or SVG files are accepted."
        );
        let mut big = b"<svg>".to_vec();
        big.resize(MAX_LOGO_BYTES + 1, b' ');
        assert_eq!(
            check_logo(&big).unwrap_err(),
            "The file is larger than 512 KB."
        );
    }
}
