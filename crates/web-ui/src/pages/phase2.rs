//! Shared table, form and request handling for the CRM and manufacturing pages.

use std::future::Future;

use leptos::prelude::*;
use leptos_router::components::A;
use leptos_router::hooks::use_params_map;
use serde::de::DeserializeOwned;
use serde_json::{Map, Value};
use uuid::Uuid;

use crate::api::{ApiError, Client, ConnectionMode};
use crate::components::async_ops::{live_client, spawn_api, RequestGuard};
use crate::components::inputs::{api_picker_search, SearchPicker};
use crate::components::shell::app_href;
use crate::state::AppContext;
use tradocraft_api_client::{ListCustomersParams, ListProductsParams};

pub(super) fn record_id() -> Memo<Option<Uuid>> {
    let params = use_params_map();
    Memo::new(move |_| params.with(|p| p.get("id")?.parse().ok()))
}

pub(super) fn load<T, F, Fut>(
    revision: RwSignal<u64>,
    fetch: F,
) -> ReadSignal<Option<Result<T, String>>>
where
    T: Clone + Send + Sync + 'static,
    F: Fn(Client) -> Fut + Copy + 'static,
    Fut: Future<Output = Result<T, ApiError>> + 'static,
{
    let ctx = expect_context::<AppContext>();
    let (result, set_result) = signal(None);
    let generation = RequestGuard::new();
    Effect::new(move |_| {
        revision.track();
        let current = generation.bump();
        set_result.set(None);
        let Some(session) = ctx.session.get() else {
            set_result.set(Some(Err("Sign in to load this page.".into())));
            return;
        };
        if session.connection == ConnectionMode::MockDemo {
            set_result.set(Some(
                Err("This page requires a live API connection.".into()),
            ));
            return;
        }
        match live_client(&session.connection) {
            Ok(client) => {
                // Read any route IDs and filters while the effect is tracking.
                let request = fetch(client);
                leptos::task::spawn_local(async move {
                    let response = request.await.map_err(|err| err.to_string());
                    if generation.is_current(current) {
                        set_result.set(Some(response));
                    }
                });
            }
            Err(err) => set_result.set(Some(Err(err.to_string()))),
        }
    });
    result
}

#[derive(Clone, Copy)]
pub(super) struct Mutation {
    ctx: AppContext,
    pub pending: RwSignal<bool>,
    pub message: RwSignal<Option<Result<String, String>>>,
    pub revision: RwSignal<u64>,
}

impl Mutation {
    pub fn new(revision: RwSignal<u64>) -> Self {
        Self {
            ctx: expect_context(),
            pending: RwSignal::new(false),
            message: RwSignal::new(None),
            revision,
        }
    }

    pub fn run<T, F, Fut, D>(self, request: F, done: D)
    where
        T: 'static,
        F: FnOnce(Client) -> Fut + 'static,
        Fut: Future<Output = Result<T, ApiError>> + 'static,
        D: FnOnce(T) -> Result<(), String> + 'static,
    {
        if self.pending.get_untracked() {
            return;
        }
        self.message.set(None);
        let Some(session) = self.ctx.session.get_untracked() else {
            self.message.set(Some(Err("Sign in to continue.".into())));
            return;
        };
        self.pending.set(true);
        spawn_api(self.ctx, request, move |result| {
            if self.pending.try_set(false).is_some()
                || self
                    .ctx
                    .session
                    .try_get_untracked()
                    .flatten()
                    .map(|s| s.connection)
                    != Some(session.connection)
            {
                return;
            }
            if let Err(err) = result.map_err(|err| err.to_string()).and_then(done) {
                self.message.set(Some(Err(err)));
            }
        });
    }

    pub fn saved(self, message: &str) {
        self.message.set(Some(Ok(message.into())));
        self.revision.update(|value| *value = value.wrapping_add(1));
    }
}

#[component]
pub(super) fn Status(mutation: Mutation) -> impl IntoView {
    move || {
        mutation.message.get().map(|result| match result {
            Ok(text) => view! { <p class="tc-alert-success" role="status">{text}</p> }.into_any(),
            Err(text) => view! { <p class="tc-alert-error" role="alert">{text}</p> }.into_any(),
        })
    }
}

pub(super) fn loaded<T: Clone + Send + Sync + 'static>(
    data: ReadSignal<Option<Result<T, String>>>,
    render: impl Fn(T) -> AnyView + Send + 'static,
) -> impl IntoView {
    move || match data.get() {
        None => view! { <p role="status">"Loading…"</p> }.into_any(),
        Some(Err(error)) => view! { <p class="tc-alert-error" role="alert">{error}</p> }.into_any(),
        Some(Ok(value)) => render(value),
    }
}

pub(super) fn link(label: impl Into<String>, path: &str) -> AnyView {
    let label = label.into();
    view! { <A href=app_href(path)>{label}</A> }.into_any()
}

pub(super) fn text(value: impl ToString) -> AnyView {
    value.to_string().into_any()
}

pub(super) fn table(headers: &[&str], rows: Vec<Vec<AnyView>>, empty: &str) -> AnyView {
    if rows.is_empty() {
        return view! { <p>{empty.to_owned()}</p> }.into_any();
    }
    let headings = headers
        .iter()
        .map(|h| view! { <th scope="col">{h.to_string()}</th> })
        .collect_view();
    view! {
        <div class="tc-table-wrap">
            <table class="tc-table">
                <thead><tr>{headings}</tr></thead>
                <tbody>{rows.into_iter().map(|row| view! {
                    <tr>{row.into_iter().map(|cell| view! { <td>{cell}</td> }).collect_view()}</tr>
                }).collect_view()}</tbody>
            </table>
        </div>
    }
    .into_any()
}

pub(super) fn pager(offset: RwSignal<i64>, limit: i64, total: i64) -> AnyView {
    view! {
        <div class="tc-phase-actions" aria-label="Pagination">
            <button type="button" class="tc-btn" disabled=move || offset.get() == 0
                on:click=move |_| offset.update(|n| *n = (*n - limit).max(0))>"Previous"</button>
            <span>{move || format!("{}–{} of {total}", (offset.get() + 1).min(total), (offset.get() + limit).min(total))}</span>
            <button type="button" class="tc-btn" disabled=move || offset.get() + limit >= total
                on:click=move |_| offset.update(|n| *n += limit)>"Next"</button>
        </div>
    }.into_any()
}

#[derive(Clone)]
pub(super) enum FieldType {
    Text,
    Integer,
    Date,
    Multiline,
    Toggle,
    Select(Vec<(String, String)>),
    Lookup(Lookup, Vec<(Uuid, String)>),
    Rows(Vec<Field>),
    Group(Vec<Field>),
    List,
}

#[derive(Clone, Copy)]
pub(super) enum Lookup {
    Customer,
    Product,
    ManufacturedProduct,
}

#[derive(Clone)]
pub(super) struct Field {
    key: String,
    label: String,
    kind: FieldType,
    required: bool,
}

impl Field {
    pub fn new(key: &'static str, label: &'static str, kind: FieldType) -> Self {
        Self::owned(key.into(), label.into(), kind)
    }

    pub fn owned(key: String, label: String, kind: FieldType) -> Self {
        Self {
            key,
            label,
            kind,
            required: false,
        }
    }

    pub fn required(mut self) -> Self {
        self.required = true;
        self
    }

    pub fn text(key: &'static str, label: &'static str) -> Self {
        Self::new(key, label, FieldType::Text)
    }

    pub fn lookup(
        key: &'static str,
        label: &'static str,
        lookup: Lookup,
        choices: Vec<(Uuid, String)>,
    ) -> Self {
        Self::new(key, label, FieldType::Lookup(lookup, choices))
    }

    pub fn select(
        key: &'static str,
        label: &'static str,
        options: impl IntoIterator<Item = (impl ToString, impl ToString)>,
    ) -> Self {
        Self::new(
            key,
            label,
            FieldType::Select(
                options
                    .into_iter()
                    .map(|(value, label)| (value.to_string(), label.to_string()))
                    .collect(),
            ),
        )
    }
}

fn form_value(fields: &[Field], original: &Value) -> Value {
    Value::Object(
        fields
            .iter()
            .filter_map(|field| {
                let value = original
                    .get(&field.key)
                    .cloned()
                    .unwrap_or_else(|| match field.kind {
                        FieldType::Toggle => Value::Bool(false),
                        FieldType::Rows(_) | FieldType::List => Value::Array(vec![]),
                        _ => Value::Null,
                    });
                (!value.is_null()).then_some((field.key.clone(), value))
            })
            .collect(),
    )
}

fn display(value: Option<&Value>) -> String {
    match value {
        Some(Value::String(value)) => value.clone(),
        Some(value) if !value.is_null() => value.to_string(),
        _ => String::new(),
    }
}

fn set_key(value: RwSignal<Value>, key: &str, field: Value) {
    value.update(|value| {
        if let Some(map) = value.as_object_mut() {
            if field.is_null() {
                map.remove(key);
            } else {
                map.insert(key.into(), field);
            }
        }
    });
}

fn form_fields(fields: Vec<Field>, value: RwSignal<Value>) -> impl IntoView {
    static PICKER_SEQUENCE: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
    fields.into_iter().map(|field| {
        let Field { key, label, kind, required } = field;
        let key = StoredValue::new(key);
        let checked_value = move || key.with_value(|key| value.with(|v| v[key].as_bool().unwrap_or_default()));
        let set = move |entry| key.with_value(|key| set_key(value, key, entry));
        let read = move || key.with_value(|key| value.with(|v| display(v.get(key))));
        let set_text = move |event| {
            let input = event_target_value(&event);
            set(if input.trim().is_empty() {Value::Null} else {Value::String(input)});
        };
        let control = match kind {
            FieldType::Lookup(lookup, choices) => {
                let ctx = expect_context::<AppContext>();
                let current_id = key.with_value(|key| value.with_untracked(|v| v[key].as_str().and_then(|id| id.parse::<Uuid>().ok())));
                let selection = RwSignal::new(current_id.map(|id| {
                    let name = choices.into_iter().find(|(key, _)| *key == id)
                        .map_or_else(|| id.to_string(), |(_, name)| name);
                    (id, name)
                }));
                let search = api_picker_search(ctx, move |client, q| async move {
                    match lookup {
                        Lookup::Customer => Ok(client.list_customers(&ListCustomersParams::new().q(q).limit(25))
                            .await?.items.into_iter().map(|c| (c.id, format!("{} · {}", c.code, c.name))).collect()),
                        Lookup::Product | Lookup::ManufacturedProduct => {
                            let mut params = ListProductsParams::new().q(q).active(true).limit(25);
                            if matches!(lookup, Lookup::ManufacturedProduct) {
                                params.product_type = Some("manufactured".into());
                            }
                            Ok(client.list_products(&params).await?.items.into_iter()
                                .map(|p| (p.id, format!("{} · {}", p.code, p.name))).collect())
                        }
                    }
                });
                return view! {
                    <SearchPicker search selected=selection
                        label={label}
                        target=format!("record-picker-{}", PICKER_SEQUENCE.fetch_add(1, std::sync::atomic::Ordering::Relaxed))
                        display=Callback::new(|(_, name): (Uuid, String)| name)
                        on_select=Callback::new(move |choice: Option<(Uuid, String)>| {
                            set(choice.map_or(Value::Null, |(id, _)| Value::String(id.to_string())));
                        })
                        allow_clear=!required
                    />
                }.into_any();
            }
            FieldType::Group(columns) => return view! {
                <fieldset class="tc-phase-fieldset">
                    <legend>{label}</legend>
                    <GroupFields columns value field=key />
                </fieldset>
            }.into_any(),
            FieldType::Rows(columns) => return view! {
                <fieldset class="tc-phase-fieldset">
                    <legend>{label}</legend>
                    <ArrayFields columns value field=key />
                </fieldset>
            }.into_any(),
            FieldType::Toggle => view! {
                <input type="checkbox" prop:checked=checked_value
                    on:change=move |ev| set(Value::Bool(event_target_checked(&ev))) />
            }.into_any(),
            FieldType::Integer => view! {
                <input class="tc-input" type="number" step="1" required=required prop:value=read
                    on:input=move |ev| set(event_target_value(&ev).parse::<i64>().ok().map(Value::from).unwrap_or_default()) />
            }.into_any(),
            FieldType::Select(options) => view! {
                <select class="tc-input" required=required on:change=set_text>
                    <option value="" selected=move || read().is_empty()>"Select…"</option>
                    {options.into_iter().map(|(id, name)| {
                        let selected = id.clone();
                        view! { <option value=id selected=move || read() == selected>{name}</option> }
                    }).collect_view()}
                </select>
            }.into_any(),
            FieldType::Multiline => view! {
                <textarea class="tc-input" required=required prop:value=read on:input=set_text></textarea>
            }.into_any(),
            FieldType::List => view! {
                <input class="tc-input" type="text" required=required
                    value=key.with_value(|key| value.with_untracked(|v| v[key].as_array().into_iter().flatten().map(|item| display(Some(item))).collect::<Vec<_>>().join(", ")))
                    on:input=move |ev| {
                        let input = event_target_value(&ev);
                        let items = input.split(',').map(str::trim).filter(|s| !s.is_empty()).map(Value::from).collect();
                        set(Value::Array(items));
                    } />
            }.into_any(),
            FieldType::Text | FieldType::Date => view! {
                <input class="tc-input" type=if matches!(kind, FieldType::Date) { "date" } else { "text" }
                    required=required prop:value=read on:input=set_text />
            }.into_any(),
        };
        view! { <label class="tc-phase-field"><span>{label}</span>{control}</label> }.into_any()
    }).collect_view()
}

#[component]
fn GroupFields(
    columns: Vec<Field>,
    value: RwSignal<Value>,
    field: StoredValue<String>,
) -> impl IntoView {
    let initial = field.with_value(|key| value.with_untracked(|v| v[key].clone()));
    let group = RwSignal::new(form_value(&columns, &initial));
    Effect::new(move |_| {
        let group = group.get();
        field.with_value(|key| set_key(value, key, group));
    });
    view! { <div class="tc-phase-form">{form_fields(columns, group)}</div> }
}

#[component]
fn ArrayFields(
    columns: Vec<Field>,
    value: RwSignal<Value>,
    field: StoredValue<String>,
) -> impl IntoView {
    let next = StoredValue::new(0_u64);
    let row_columns = columns.clone();
    let item = move |initial: Value| {
        next.update_value(|id| *id += 1);
        // The key is independent of the contents, so editing a row keeps its focus.
        (
            next.get_value(),
            ArcRwSignal::new(form_value(&columns, &initial)),
        )
    };
    let initial = field
        .with_value(|key| value.with_untracked(|v| v[key].as_array().cloned().unwrap_or_default()));
    let rows = RwSignal::new(initial.into_iter().map(&item).collect::<Vec<_>>());
    Effect::new(move |_| {
        let values = rows.with(|rows| rows.iter().map(|(_, row)| row.get()).collect());
        field.with_value(|key| set_key(value, key, Value::Array(values)));
    });
    view! {
        <For each=move || rows.get() key=|(id, _)| *id children=move |(id, row)| {
            let signal = RwSignal::new(row.get_untracked());
            Effect::new(move |_| row.set(signal.get()));
            view! {
                <div class="tc-phase-row">
                    {form_fields(row_columns.clone(), signal)}
                    <button type="button" class="tc-btn" on:click=move |_| rows.update(|rows| rows.retain(|(key, _)| *key != id))>"Remove row"</button>
                </div>
            }
        } />
        <button type="button" class="tc-btn" on:click=move |_| rows.update(|rows| rows.push(item(Value::Object(Map::new()))))>"Add row"</button>
    }
}

#[component]
pub(super) fn DialogPanel(
    #[prop(into)] title: String,
    on_close: Callback<()>,
    #[prop(into, default = Signal::derive(|| true))] open: Signal<bool>,
    children: Children,
) -> impl IntoView {
    let dialog = NodeRef::<leptos::html::Dialog>::new();
    Effect::new(move |_| {
        let show = open.get();
        if let Some(dialog) = dialog.get() {
            #[cfg(target_arch = "wasm32")]
            if show && !dialog.open() {
                let _ = dialog.show_modal();
            } else if !show && dialog.open() {
                dialog.close();
            }
            #[cfg(not(target_arch = "wasm32"))]
            let _ = (show, dialog);
        }
    });
    view! {
        <dialog node_ref=dialog class="tc-phase-overlay" aria-label=title
            on:cancel=move |ev: leptos::ev::Event| {ev.prevent_default(); on_close.run(());}>
            <section class="tc-card tc-phase-dialog">{children()}</section>
        </dialog>
    }
}

pub(super) fn editor(
    title: impl Into<String> + Send,
    fields: Vec<Field>,
    initial: Value,
    mutation: Mutation,
    submit: impl Fn(Value, RwSignal<bool>) + Clone + Send + 'static,
) -> AnyView {
    let title = title.into();
    let open = RwSignal::new(false);
    view! {
        <button type="button" class="tc-btn" disabled=move || mutation.pending.get()
            on:click=move |_| open.set(true)>{title.clone()}</button>
        {move || open.get().then(|| {
            let initial = form_value(&fields, &initial);
            let draft = RwSignal::new(initial);
            let submit = submit.clone();
            let form = form_fields(fields.clone(), draft);
            let title = title.clone();
            view! {
                <DialogPanel title=title.clone() on_close=Callback::new(move |()| {
                    if !mutation.pending.get_untracked() {open.set(false);}
                })>
                        <h2>{title.clone()}</h2>
                        <Status mutation=mutation />
                        <form on:submit=move |ev| {
                            ev.prevent_default();
                            submit(draft.get_untracked(), open);
                        }>
                            <div class="tc-phase-form">{form}</div>
                            <div class="tc-phase-actions">
                                <button type="submit" class="tc-btn tc-btn-primary" disabled=move || mutation.pending.get()>"Save"</button>
                                <button type="button" class="tc-btn" disabled=move || mutation.pending.get() on:click=move |_| open.set(false)>"Cancel"</button>
                            </div>
                        </form>
                </DialogPanel>
            }
        })}
    }.into_any()
}

pub(super) fn save<T, R, F, Fut>(
    mutation: Mutation,
    title: impl Into<String> + Send,
    fields: Vec<Field>,
    initial: Value,
    request: F,
) -> AnyView
where
    T: DeserializeOwned + 'static,
    R: 'static,
    F: FnOnce(Client, T) -> Fut + Clone + Send + 'static,
    Fut: Future<Output = Result<R, ApiError>> + 'static,
{
    editor(title, fields, initial, mutation, move |value, open| {
        let body = match serde_json::from_value(value) {
            Ok(body) => body,
            Err(err) => {
                mutation
                    .message
                    .set(Some(Err(format!("Check the form fields. {err}"))));
                return;
            }
        };
        let request = request.clone();
        mutation.run(
            move |client| request(client, body),
            move |_| {
                let _ = open.try_set(false);
                mutation.saved("Saved.");
                Ok(())
            },
        );
    })
}

pub(super) fn action<T, F, Fut>(
    mutation: Mutation,
    title: &'static str,
    question: Option<&'static str>,
    request: F,
) -> AnyView
where
    T: 'static,
    F: FnOnce(Client) -> Fut + Clone + Send + 'static,
    Fut: Future<Output = Result<T, ApiError>> + 'static,
{
    let run = move || {
        mutation.run(request.clone(), move |_| {
            mutation.saved("Saved.");
            Ok(())
        });
    };
    if let Some(question) = question {
        let open = RwSignal::new(false);
        return view! {
            <button type="button" class="tc-btn" disabled=move || mutation.pending.get()
                on:click=move |_| open.set(true)>{title}</button>
            {move || open.get().then(|| {
                let confirm = run.clone();
                view! {<DialogPanel title on_close=Callback::new(move |()| open.set(false))>
                        <p>{question}</p>
                        <div class="tc-phase-actions">
                            <button type="button" class="tc-btn tc-btn-primary" on:click={
                                move |_| { open.set(false); confirm(); }
                            }>{title}</button>
                            <button type="button" class="tc-btn" on:click=move |_| open.set(false)>"Cancel"</button>
                        </div>
                </DialogPanel>}
            })}
        }.into_any();
    }
    view! { <button type="button" class="tc-btn" disabled=move || mutation.pending.get()
    on:click=move |_| run()>{title}</button> }
    .into_any()
}

pub(super) fn decode<T: DeserializeOwned>(value: Value) -> Result<T, ApiError> {
    serde_json::from_value(value).map_err(|err| ApiError::InvalidConfig(err.to_string()))
}

pub(super) fn yes_no(value: bool) -> &'static str {
    if value {
        "Yes"
    } else {
        "No"
    }
}

pub(super) fn management(title: &'static str, contents: impl FnOnce() -> AnyView) -> AnyView {
    let open = RwSignal::new(false);
    let contents = contents();
    view! {
        <button type="button" class="tc-btn" on:click=move |_| open.set(true)>{title}</button>
        <DialogPanel title open on_close=Callback::new(move |()| open.set(false))>
            <h2>{title}</h2>
            {contents}
            <button type="button" class="tc-btn" on:click=move |_| open.set(false)>"Close"</button>
        </DialogPanel>
    }
    .into_any()
}

pub(super) fn can(permission: &str) -> bool {
    expect_context::<AppContext>().session.with(|session| {
        session
            .as_ref()
            .is_some_and(|s| s.me.has_permission(permission))
    })
}
