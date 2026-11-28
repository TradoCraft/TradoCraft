use leptos::prelude::*;
use serde_json::json;
use tradocraft_api_client::products::{ProductMedia, UploadProductMediaParams};
use uuid::Uuid;

use super::phase2::{self as ui, Field, FieldType, Mutation, Status};
use crate::components::files::{begin_file_read, save_file};

#[component]
pub(super) fn MediaTab(id: Uuid) -> impl IntoView {
    let revision = RwSignal::new(0);
    let mutation = Mutation::new(revision);
    let data = ui::load(revision, move |client| async move {
        client.list_product_media(id).await
    });
    let selected = RwSignal::new(None::<ProductMedia>);
    let caption = RwSignal::new(String::new());
    view! {
        <section>
            <h2>"Product media"</h2>
            <Status mutation=mutation />
            <div class="tc-phase-actions">
                <label class="tc-phase-field">"Caption for new media"
                    <input class="tc-input" on:input=move |ev| caption.set(event_target_value(&ev)) />
                </label>
                <label class="tc-phase-field">"Upload image, video, or GLB model"
                    <input type="file" accept="image/jpeg,image/png,image/webp,image/svg+xml,video/mp4,video/webm,.glb"
                        disabled=move || mutation.pending.get() on:change=move |ev| {
                            let caption = caption.get_untracked();
                            begin_file_read(ev, 64 * 1024 * 1024, "The maximum file size is 64 MB.", move |file| {
                                if selected.is_disposed() {return;}
                                match file {
                                    Ok(file) => mutation.run(move |client| async move {
                                        client.upload_product_media(id, &UploadProductMediaParams {
                                            caption: Some(caption), filename: Some(file.name), client_id: Some(Uuid::new_v4()),
                                        }, file.bytes).await
                                    }, move |_| {mutation.saved("Media uploaded.");Ok(())}),
                                    Err(err) if !err.is_empty() => mutation.message.set(Some(Err(err))),
                                    _ => (),
                                }
                            });
                        } />
                </label>
            </div>
            {ui::loaded(data, move |items| ui::table(&["File","Caption","Kind","Default","Actions"], items.into_iter().map(|media| {
                let media_id = media.id;
                let preview = media.clone();
                let edit = ui::save(mutation,"Edit media",vec![
                    Field::text("caption","Caption"),Field::new("is_default","Default media",FieldType::Toggle),
                ],json!(media),move |client,mut body:tradocraft_api_client::products::MediaUpdate| async move {
                    body.caption = Some(body.caption.unwrap_or_default());
                    client.update_product_media(id,media_id,&body).await
                });
                let delete = ui::action(mutation,"Delete",Some("Delete this media file?"), move |client| async move {
                    client.delete_product_media(id,media_id).await
                });
                let filename = media.filename.clone();
                let kind = media.content_type.clone();
                vec![view! {
                    <button type="button" class="tc-btn" on:click=move |_| selected.set(Some(preview.clone()))>{filename}</button>
                }.into_any(), ui::text(media.caption),ui::text(media.kind),ui::text(ui::yes_no(media.is_default)),view! {
                    <div class="tc-phase-actions">
                        {edit}{delete}
                        <button type="button" class="tc-btn" disabled=move || mutation.pending.get() on:click=move |_| {
                            let name = media.filename.clone();
                            let kind = kind.clone();
                            mutation.run(move |client| async move {client.get_product_media(id, media_id).await},
                                move |bytes| save_file(&name, &kind, &bytes));
                        }>"Download"</button>
                    </div>
                }.into_any()]
            }).collect(), "No product media."))}
            {move || selected.get().map(|media| view! {<MediaPreview id media selected />})}
        </section>
    }
}

#[component]
fn MediaPreview(
    id: Uuid,
    media: ProductMedia,
    selected: RwSignal<Option<ProductMedia>>,
) -> impl IntoView {
    let media_id = media.id;
    let bytes = ui::load(RwSignal::new(0), move |client| async move {
        client.get_product_media(id, media_id).await
    });
    let stored = StoredValue::new(media);
    view! {
        <section class="tc-phase-section">
            <h3>{move || stored.with_value(|m| m.filename.clone())}</h3>
            <button type="button" class="tc-btn" on:click=move |_| selected.set(None)>"Close preview"</button>
            {ui::loaded(bytes,move |bytes| {
                let media = stored.get_value();
                view! {<MediaObject bytes content_type=media.content_type label=media.filename />}.into_any()
            })}
        </section>
    }
}

#[component]
fn MediaObject(bytes: Vec<u8>, content_type: String, label: String) -> impl IntoView {
    #[cfg(target_arch = "wasm32")]
    {
        let parts = js_sys::Array::new();
        parts.push(&js_sys::Uint8Array::from(bytes.as_slice()));
        let options = web_sys::BlobPropertyBag::new();
        options.set_type(&content_type);
        let url = web_sys::Blob::new_with_u8_array_sequence_and_options(&parts, &options)
            .and_then(|blob| web_sys::Url::create_object_url_with_blob(&blob));
        let Ok(url) = url else {
            return ui::text("The browser could not open this preview.");
        };
        on_cleanup({
            let url = url.clone();
            move || {
                let _ = web_sys::Url::revoke_object_url(&url);
            }
        });
        match content_type.as_str() {
            "model/gltf-binary" => {
                if load_model_viewer().is_err() {
                    return ui::text(
                        "The 3D viewer could not be loaded. Use Download to open the file.",
                    );
                }
                view! {
                    <model-viewer class="tc-product-media" src=url alt=label camera-controls="true"
                        touch-action="pan-y" shadow-intensity="1"></model-viewer>
                }
                .into_any()
            }
            mime if mime.starts_with("image/") => {
                view! {<img class="tc-product-media" src=url alt=label />}.into_any()
            }
            mime if mime.starts_with("video/") => {
                view! {<video class="tc-product-media" controls src=url aria-label=label></video>}
                    .into_any()
            }
            _ => ui::text("Preview unavailable for this file type."),
        }
    }
    #[cfg(not(target_arch = "wasm32"))]
    {
        let _ = (bytes, content_type, label);
        ui::text("Media previews are available in the browser.")
    }
}

#[cfg(target_arch = "wasm32")]
fn load_model_viewer() -> Result<(), wasm_bindgen::JsValue> {
    use wasm_bindgen::JsValue;

    let document = web_sys::window()
        .and_then(|window| window.document())
        .ok_or_else(|| JsValue::from_str("Document unavailable"))?;
    const SCRIPT_ID: &str = "product-model-viewer";
    if document.get_element_by_id(SCRIPT_ID).is_none() {
        // The browser verifies the pinned bundle before it can execute in the app.
        let script = document.create_element("script")?;
        script.set_id(SCRIPT_ID);
        script.set_attribute("type", "module")?;
        script.set_attribute("crossorigin", "anonymous")?;
        script.set_attribute(
            "src",
            "https://cdn.jsdelivr.net/npm/@google/model-viewer@4.1.0/dist/model-viewer.min.js",
        )?;
        script.set_attribute(
            "integrity",
            "sha384-T4vc5AP9W2o3EVVQC6Is5mbKqFE2eysxg1XHwaZLquK0SjtY+4cLHoN3j1mK/MmB",
        )?;
        document
            .document_element()
            .ok_or_else(|| JsValue::from_str("Document root unavailable"))?
            .append_child(&script)?;
    }
    Ok(())
}
