//! Accessible Modal dialog and ConfirmDialog components.

use leptos::prelude::*;

/// Accessible modal dialog with backdrop and Escape dismissal.
#[component]
pub fn Modal(
    #[prop(into)] open: Signal<bool>,
    #[prop(into)] title: Signal<String>,
    on_close: Callback<()>,
    #[prop(into, default = "modal".to_string())] target: String,
    #[prop(default = true)] close_on_backdrop: bool,
    #[prop(default = true)] close_on_escape: bool,
    #[prop(into, optional)] subtitle: Option<Signal<Option<String>>>,
    #[prop(into, optional)] footer: Option<ViewFn>,
    children: ChildrenFn,
) -> impl IntoView {
    let target_sv = StoredValue::new(target);
    let children_sv = StoredValue::new(children);
    let footer_sv = StoredValue::new(footer);
    let dialog_ref = NodeRef::<leptos::html::Dialog>::new();

    Effect::new(move |_| {
        if open.get() {
            if let Some(el) = dialog_ref.get() {
                #[cfg(target_arch = "wasm32")]
                let _ = el.show_modal();
                #[cfg(not(target_arch = "wasm32"))]
                let _ = el;
            }
        }
    });

    view! {
        <Show when=move || open.get()>
            {
                let t = target_sv.get_value();
                let title_id = format!("{t}-title");
                let heading_id = title_id.clone();
                let subtitle_el = subtitle.map(|sub| {
                    view! {
                        {move || sub.get().map(|text| view! {
                            <p class="tc-modal-subtitle">{text}</p>
                        })}
                    }
                });
                let body_view = children_sv.with_value(|c| c());
                let render_footer = footer_sv.get_value();

                view! {
                    <dialog
                        node_ref=dialog_ref
                        class="tc-modal-backdrop"
                        aria-labelledby=title_id
                        data-target=format!("{t}-backdrop")
                        on:click=move |_| {
                            if close_on_backdrop {
                                on_close.run(());
                            }
                        }
                        on:cancel=move |ev: leptos::ev::Event| {
                            ev.prevent_default();
                            if close_on_escape {
                                on_close.run(());
                            }
                        }
                    >
                        <div
                            class="tc-modal"
                            data-target=t.clone()
                            on:click=|ev: leptos::ev::MouseEvent| ev.stop_propagation()
                        >
                            <div class="tc-modal-header">
                                <div>
                                    <h2 id=heading_id class="tc-modal-title">
                                        {move || title.get()}
                                    </h2>
                                    {subtitle_el}
                                </div>
                                <button
                                    type="button"
                                    class="tc-btn tc-btn-ghost tc-btn-sm tc-modal-close"
                                    aria-label="Close"
                                    data-target=format!("{t}-close")
                                    on:click=move |_| on_close.run(())
                                >
                                    "×"
                                </button>
                            </div>
                            <div class="tc-modal-body" data-target=format!("{t}-body")>
                                {body_view}
                            </div>
                            {render_footer.map(|f| view! {
                                <div class="tc-modal-footer" data-target=format!("{t}-footer")>
                                    {f.run()}
                                </div>
                            })}
                        </div>
                    </dialog>
                }
            }
        </Show>
    }
}

/// Confirmation dialog built on [`Modal`] with Cancel and Confirm buttons and optional destructive
/// styling.
#[component]
pub fn ConfirmDialog(
    #[prop(into)] open: Signal<bool>,
    #[prop(into)] title: Signal<String>,
    #[prop(into)] message: Signal<String>,
    #[prop(into, default = "Confirm".to_string())] confirm_label: String,
    #[prop(into, default = "Cancel".to_string())] cancel_label: String,
    #[prop(default = false)] destructive: bool,
    #[prop(into, default = Signal::derive(|| false))] busy: Signal<bool>,
    #[prop(into, default = "confirm-dialog".to_string())] target: String,
    on_confirm: Callback<()>,
    on_cancel: Callback<()>,
) -> impl IntoView {
    let confirm_class = if destructive {
        "tc-btn tc-btn-danger"
    } else {
        "tc-btn tc-btn-primary"
    };
    let cancel_target = format!("{target}-cancel");
    let confirm_target = format!("{target}-confirm");
    let confirm_label = StoredValue::new(confirm_label);
    let cancel_label = StoredValue::new(cancel_label);

    let on_dismiss = Callback::new(move |()| {
        if !busy.get_untracked() {
            on_cancel.run(());
        }
    });

    let footer = ViewFn::from(move || {
        view! {
            <button
                type="button"
                class="tc-btn"
                data-target=cancel_target.clone()
                disabled=move || busy.get()
                on:click=move |_| on_cancel.run(())
            >
                {cancel_label.get_value()}
            </button>
            <button
                type="button"
                class=confirm_class
                data-target=confirm_target.clone()
                disabled=move || busy.get()
                on:click=move |_| on_confirm.run(())
            >
                {confirm_label.get_value()}
            </button>
        }
    });

    view! {
        <Modal
            open=open
            title=title
            on_close=on_dismiss
            target=target
            footer=footer
        >
            <p style="margin: 0;">{move || message.get()}</p>
        </Modal>
    }
}
