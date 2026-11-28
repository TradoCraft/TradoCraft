//! Shared inline success and error feedback banner state and renderer.

use leptos::prelude::*;

use crate::components::async_ops::set_alive;

/// Holds the current inline error and success notice messages for a section or dialog.
#[derive(Clone, Copy)]
pub struct Feedback {
    pub error: RwSignal<Option<String>>,
    pub notice: RwSignal<Option<String>>,
}

impl Default for Feedback {
    fn default() -> Self {
        Self::new()
    }
}

impl Feedback {
    /// Creates an empty feedback holder.
    pub fn new() -> Self {
        Self {
            error: RwSignal::new(None),
            notice: RwSignal::new(None),
        }
    }

    /// Shows a success notice and clears any prior error. Returns `false` if disposed.
    pub fn ok(self, msg: impl Into<String>) -> bool {
        set_alive(self.error, None) && set_alive(self.notice, Some(msg.into()))
    }

    /// Shows an error alert and clears any prior notice. Returns `false` if disposed.
    pub fn fail(self, msg: impl Into<String>) -> bool {
        set_alive(self.notice, None) && set_alive(self.error, Some(msg.into()))
    }

    /// Clears both error and notice messages. Returns `false` if disposed.
    pub fn clear(self) -> bool {
        set_alive(self.error, None) && set_alive(self.notice, None)
    }
}

/// Renders a [`Feedback`] as an error alert and status banner using `data-target` values
/// `<prefix>-error` and `<prefix>-notice`.
#[component]
pub fn FeedbackView(
    fb: Feedback,
    prefix: &'static str,
    #[prop(optional)] dismissible: bool,
) -> impl IntoView {
    let class_error = if dismissible {
        "tc-alert-error tc-alert-dismissible"
    } else {
        "tc-alert-error"
    };
    let class_notice = if dismissible {
        "tc-alert-success tc-alert-dismissible"
    } else {
        "tc-alert-success"
    };

    view! {
        {move || fb.error.get().map(|msg| view! {
            <div class=class_error style="margin-bottom: var(--space-md);" role="alert" data-target=format!("{prefix}-error")>
                <span>{msg}</span>
                {dismissible.then(|| view! {
                    <button
                        type="button"
                        class="tc-btn tc-btn-ghost tc-btn-sm tc-alert-dismiss"
                        aria-label="Dismiss error"
                        data-target=format!("{prefix}-error-dismiss")
                        on:click=move |_| { fb.error.set(None); }
                    >
                        "×"
                    </button>
                })}
            </div>
        })}
        {move || fb.notice.get().map(|msg| view! {
            <div class=class_notice style="margin-bottom: var(--space-md);" role="status" data-target=format!("{prefix}-notice")>
                <span>{msg}</span>
                {dismissible.then(|| view! {
                    <button
                        type="button"
                        class="tc-btn tc-btn-ghost tc-btn-sm tc-alert-dismiss"
                        aria-label="Dismiss notice"
                        data-target=format!("{prefix}-notice-dismiss")
                        on:click=move |_| { fb.notice.set(None); }
                    >
                        "×"
                    </button>
                })}
            </div>
        })}
    }
}
