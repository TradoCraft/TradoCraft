use leptos::prelude::*;
use serde_json::{json, Value};
use tradocraft_api_client::opportunities::*;
use tradocraft_api_client::{AttributeDefinition, BaselineItemType, DefinitionKind};
use uuid::Uuid;

use super::phase2::{self as ui, Field, FieldType, Lookup, Mutation, Status};
use crate::components::files::{begin_file_read, PickedFile};
use crate::components::kanban::{KanbanBoard, KanbanLane};

const PAGE_SIZE: i64 = 50;
const STAGES: [(&str, &str); 6] = [
    ("lead", "Lead"),
    ("qualified", "Qualified"),
    ("proposal", "Proposal"),
    ("negotiation", "Negotiation"),
    ("won", "Won"),
    ("lost", "Lost"),
];

impl StageLabel for OpportunityStage {
    fn index(&self) -> usize {
        match self {
            Self::Lead => 0,
            Self::Qualified => 1,
            Self::Proposal => 2,
            Self::Negotiation => 3,
            Self::Won => 4,
            Self::Lost => 5,
        }
    }
}

trait StageLabel {
    fn index(&self) -> usize;

    fn label(&self) -> &'static str {
        STAGES[self.index()].1
    }
}

fn opportunity_link(item: &Opportunity) -> AnyView {
    ui::link(
        format!("{} · {}", item.number, item.title),
        &format!("/opportunities/{}", item.id),
    )
}

#[component]
pub fn OpportunitiesPage() -> impl IntoView {
    let revision = RwSignal::new(0);
    let mutation = Mutation::new(revision);
    let query = RwSignal::new(String::new());
    let offset = RwSignal::new(0);
    let board = RwSignal::new(false);
    let data = ui::load(revision, move |client| {
        let q = query.get();
        let offset = offset.get();
        let board = board.get();
        async move {
            let params = ListOpportunitiesParams {
                q: (!q.is_empty()).then_some(q),
                limit: Some(PAGE_SIZE),
                offset: Some(offset),
                ..Default::default()
            };
            let page = client.list_opportunities(&params).await?;
            let stages = if board {
                client.opportunity_pipeline().await?
            } else {
                vec![]
            };
            Ok((page, stages))
        }
    });
    view! {
        <div>
            <h1>"Opportunities"</h1>
            <div class="tc-phase-actions">
                <label class="tc-phase-field">"Search opportunities"
                    <input class="tc-input" type="search" on:change=move |ev| {
                        offset.set(0);
                        query.set(event_target_value(&ev).trim().to_owned());
                    } />
                </label>
                <button type="button" class="tc-btn" aria-pressed=move || !board.get()
                    on:click=move |_| board.set(false)>"List"</button>
                <button type="button" class="tc-btn" aria-pressed=move || board.get()
                    on:click=move |_| board.set(true)>"Pipeline"</button>
                {ui::save(mutation, "New opportunity", opportunity_fields(vec![]), Value::Null,
                    |client, body| async move { client.create_opportunity(&body).await })}
            </div>
            <Status mutation=mutation />
            {ui::loaded(data, move |(page, totals)| {
                let pagination = ui::pager(offset, PAGE_SIZE, page.total);
                let content = if board.get_untracked() {
                    let lanes = STAGES.iter().enumerate().map(|(index, (_, label))| {
                        let summary = totals.iter().find(|stage| stage.stage.index() == index)
                            .map(|s| format!("{} opportunities · {} weighted", s.count, s.weighted_value))
                            .unwrap_or_default();
                        let cards = page.items.iter().filter(|item| item.stage.index() == index)
                            .map(|item| {
                                let title = opportunity_link(item);
                                let customer = item.customer_name.clone();
                                let value = format!("{} · {}%", item.expected_value, item.probability);
                                let transition = stage_editor(mutation, item);
                                view! { {title}<div>{customer}</div><div>{value}</div>{transition} }.into_any()
                            }).collect();
                        KanbanLane {title: label.to_string(), summary, cards}
                    }).collect();
                    view! { <KanbanBoard lanes /> }.into_any()
                } else {
                    ui::table(&["Opportunity", "Customer", "Owner", "Stage", "Expected value", "Probability", "Expected close"],
                        page.items.into_iter().map(|item| vec![opportunity_link(&item), ui::text(item.customer_name),
                            ui::text(item.owner_name), ui::text(item.stage.label()), ui::text(item.expected_value),
                            ui::text(format!("{}%", item.probability)), ui::text(item.expected_close.map(|d| d.to_string()).unwrap_or_default())]).collect(),
                        "No opportunities found.")
                };
                view! {{content}{pagination}}.into_any()
            })}
        </div>
    }
}

fn opportunity_fields(customers: Vec<(Uuid, String)>) -> Vec<Field> {
    vec![
        Field::text("title", "Title").required(),
        Field::lookup("customer_id", "Customer", Lookup::Customer, customers).required(),
        Field::text("expected_value", "Expected value"),
        Field::new("probability", "Probability (%)", FieldType::Integer),
        Field::new("expected_close", "Expected close", FieldType::Date),
        Field::new("notes", "Notes", FieldType::Multiline),
        Field::new(
            "building_construction_year",
            "Construction year",
            FieldType::Integer,
        ),
    ]
}

fn stage_editor(mutation: Mutation, item: &Opportunity) -> AnyView {
    let id = item.id;
    ui::save(
        mutation,
        "Change stage",
        vec![
            Field::select("stage", "Stage", STAGES).required(),
            Field::text("lost_reason", "Reason (required when marking lost)"),
            Field::new(
                "probability",
                "Override probability (%)",
                FieldType::Integer,
            ),
        ],
        json!({"stage": STAGES[item.stage.index()].0}),
        move |client, body| async move { client.change_opportunity_stage(id, &body).await },
    )
}

#[component]
pub fn OpportunityDetailPage() -> impl IntoView {
    let id = ui::record_id();
    view! {
        {move || match id.get() {
            Some(id) => view! { <OpportunityDetail id /> }.into_any(),
            None => ui::text("Invalid opportunity ID."),
        }}
    }
}

#[component]
fn OpportunityDetail(id: Uuid) -> impl IntoView {
    let revision = RwSignal::new(0);
    let mutation = Mutation::new(revision);
    let data = ui::load(revision, move |client| async move {
        client.get_opportunity(id).await
    });
    view! {
        <div>
            {ui::link("All opportunities", "/opportunities")}
            <Status mutation=mutation />
            {ui::loaded(data, move |item| {
                let title = format!("{} · {}", item.number, item.title);
                let summary = format!("{} · {} · {}%", item.customer_name, item.stage.label(), item.probability);
                let transition = stage_editor(mutation, &item);
                let mut fields = opportunity_fields(vec![(item.customer_id, item.customer_name.clone())]);
                let mut initial = serde_json::to_value(&item).unwrap_or_default();
                initial["clear_building_construction_year"] = Value::Bool(false);
                fields.extend([
                    Field::text("power_grid_id", "Site power grid ID"),
                    Field::new("clear_power_grid", "Clear site power grid", FieldType::Toggle),
                    Field::new("clear_building_construction_year", "Clear construction year", FieldType::Toggle),
                ]);
                let edit = ui::save(mutation, "Edit opportunity", fields, initial,
                    move |client, mut body: OpportunityInput| async move {
                        if body.clear_power_grid == Some(true) { body.power_grid_id = None; }
                        if body.clear_building_construction_year == Some(true) { body.building_construction_year = None; }
                        body.owner_user_id = Some(item.owner_user_id);
                        client.update_opportunity(id, &body).await
                    });
                view! {
                    <h1>{title}</h1><p>{summary}</p>
                    <p>{item.notes}</p>
                    <div class="tc-phase-actions">{transition}{edit}</div>
                }.into_any()
            })}
            <BaselinePanel id revision />
            <ProductMatches id revision />
        </div>
    }
}

fn flatten(items: Vec<BaselineItem>, depth: usize, result: &mut Vec<(usize, BaselineItem)>) {
    for mut item in items {
        let children = std::mem::take(&mut item.children);
        result.push((depth, item));
        flatten(children, depth + 1, result);
    }
}

fn json_attributes(fields: &mut Vec<Field>, defs: &[AttributeDefinition], values: &Value) -> Value {
    let mut initial = serde_json::Map::new();
    for def in defs.iter().filter(|def| def.active) {
        let key = def.key.clone();
        initial.insert(key.clone(), values.get(&key).cloned().unwrap_or_default());
        let kind = match def.kind {
            DefinitionKind::Boolean => FieldType::Select(vec![
                ("true".into(), "Yes".into()),
                ("false".into(), "No".into()),
            ]),
            DefinitionKind::Select => FieldType::Select(
                def.options
                    .iter()
                    .map(|o| (o.value.clone(), o.label.clone()))
                    .collect(),
            ),
            _ => FieldType::Text,
        };
        fields.push(Field::owned(key, def.label.clone(), kind));
    }
    Value::Object(initial)
}

fn baseline_item_editor(
    mutation: Mutation,
    id: Uuid,
    item: Option<BaselineItem>,
    item_type: &BaselineItemType,
    defs: &[AttributeDefinition],
    parents: &[(usize, BaselineItem)],
) -> AnyView {
    let type_code = item_type.code.clone();
    let item_id = item.as_ref().map(|i| i.id);
    let choices = parents
        .iter()
        .filter(|(_, candidate)| {
            Some(candidate.id) != item_id
                && item_type
                    .allowed_parent_codes
                    .contains(&candidate.type_code)
        })
        .map(|(_, item)| {
            (
                item.id,
                item.name.clone().unwrap_or_else(|| item.type_code.clone()),
            )
        });
    let parent = Field::select("parent_id", "Parent item", choices);
    let mut fields = vec![
        Field::text("name", "Name"),
        Field::new("quantity", "Quantity", FieldType::Integer).required(),
        if item_type.allow_top_level {
            parent
        } else {
            parent.required()
        },
        Field::new("sort_order", "Sort order", FieldType::Integer),
    ];
    let defs = defs
        .iter()
        .filter(|def| def.scope == type_code && def.active)
        .cloned()
        .collect::<Vec<_>>();
    let current_values = item.as_ref().map(|i| &i.values).unwrap_or(&Value::Null);
    let mut initial = json!({
        "name": item.as_ref().and_then(|i| i.name.as_deref()),
        "parent_id": item.as_ref().and_then(|i| i.parent_id),
        "quantity": item.as_ref().map_or(1, |i| i.quantity),
        "sort_order": item.as_ref().map_or(0, |i| i.sort_order),
    });
    let mut form_attributes = vec![];
    let attrs = json_attributes(&mut form_attributes, &defs, current_values);
    initial["attributes"] = attrs;
    fields.push(Field::new(
        "attributes",
        "Attributes",
        FieldType::Group(form_attributes),
    ));
    let label = if item_id.is_some() {
        format!("Edit {}", item_type.name)
    } else {
        format!("Add {}", item_type.name)
    };
    ui::save(
        mutation,
        label,
        fields,
        initial,
        move |client, mut payload: Value| {
            let type_code = type_code.clone();
            let defs = defs.clone();
            let mut attributes = payload["attributes"].take();
            if let Some(map) = attributes.as_object_mut() {
                for def in &defs {
                    if def.kind == DefinitionKind::Boolean {
                        if let Some(value) = map.get_mut(&def.key) {
                            if let Some(boolean) =
                                value.as_str().and_then(|s| s.parse::<bool>().ok())
                            {
                                *value = Value::Bool(boolean);
                            }
                        }
                    }
                }
            }
            payload["values"] = attributes;
            payload["type_code"] = Value::String(type_code);
            async move {
                let invalid =
                    |e: serde_json::Error| crate::api::ApiError::InvalidConfig(e.to_string());
                if let Some(item_id) = item_id {
                    client
                        .update_baseline_item(
                            id,
                            item_id,
                            &serde_json::from_value(payload).map_err(invalid)?,
                        )
                        .await
                } else {
                    client
                        .create_baseline_item(
                            id,
                            &serde_json::from_value(payload).map_err(invalid)?,
                        )
                        .await
                }
            }
        },
    )
}

#[component]
fn BaselinePanel(id: Uuid, revision: RwSignal<u64>) -> impl IntoView {
    let mutation = Mutation::new(revision);
    let data = ui::load(revision, move |client| async move {
        let items = client.get_baseline(id).await?;
        let types = client.list_baseline_item_types().await?;
        let definitions = client
            .list_attribute_definitions()
            .await
            .unwrap_or_default();
        Ok((items, types, definitions))
    });
    let source = RwSignal::new(None::<String>);
    view! {
        <section class="tc-phase-section">
            <h2>"Site baseline"</h2>
            <Status mutation=mutation />
            <BaselineImport id revision />
            {ui::loaded(data, move |(items, types, defs)| {
                let mut rows = vec![];
                flatten(items, 0, &mut rows);
                let create = types.iter().filter(|ty| ty.active).map(|ty|
                    baseline_item_editor(mutation, id, None, ty, &defs, &rows)).collect_view();
                let table = ui::table(&["Item", "Type", "Quantity", "Attributes", "Actions"], rows.iter().map(|(depth, item)| {
                    let item_id = item.id;
                    let name = format!("{}{}", " ".repeat(*depth), item.name.as_deref().unwrap_or(&item.type_code));
                    let values = item.values.as_object().into_iter().flatten().map(|(key, value)| {
                        let label = defs.iter().find(|def| def.scope == item.type_code && def.key == *key).map_or(key, |def| &def.label);
                        format!("{label} {}", value.as_str().map(str::to_owned).unwrap_or_else(|| value.to_string()))
                    }).collect::<Vec<_>>().join(", ");
                    let edit = types.iter().find(|ty| ty.code == item.type_code)
                        .map(|ty| baseline_item_editor(mutation, id, Some(item.clone()), ty, &defs, &rows));
                    let delete = ui::action(mutation, "Delete", Some("Delete this baseline item?"), move |client| async move {
                        client.delete_baseline_item(id, item_id).await
                    });
                    let imported = item.import_source.is_some();
                    vec![ui::text(name), ui::text(&item.type_code), ui::text(item.quantity), ui::text(values),
                        view! { <div class="tc-phase-actions">{edit}{delete}
                            {imported.then(|| view! {
                                <button type="button" class="tc-btn" disabled=move || mutation.pending.get() on:click=move |_| {
                                    mutation.run(move |client| async move { client.get_baseline_source(id, item_id).await },
                                        move |value| { source.set(serde_json::to_string_pretty(&value).ok()); Ok(()) });
                                }>"View source"</button>
                            })}
                        </div> }.into_any()]
                }).collect(), "No baseline items.");
                view! {<div class="tc-phase-actions">{create}</div>{table}}.into_any()
            })}
            {move || source.get().map(|content| view! {
                <ui::DialogPanel title="Import source" on_close=Callback::new(move |()| source.set(None))>
                    <pre>{content}</pre>
                    <button type="button" class="tc-btn" on:click=move |_| source.set(None)>"Close"</button>
                </ui::DialogPanel>
            })}
        </section>
    }
}

#[component]
fn BaselineImport(id: Uuid, revision: RwSignal<u64>) -> impl IntoView {
    let mutation = Mutation::new(revision);
    let preview = RwSignal::new(None::<(Value, BaselineImportReport)>);
    view! {
        <details>
            <summary>"Import a site baseline"</summary>
            <Status mutation=mutation />
            <label class="tc-phase-field">"Tower configurator JSON file"
                <input type="file" accept=".json,application/json" disabled=move || mutation.pending.get()
                    on:change=move |ev| {
                        preview.set(None);
                        begin_file_read(ev, 5 * 1024 * 1024, "The maximum file size is 5 MB.", move |file| {
                            if preview.is_disposed() { return; }
                            let body = file.and_then(|PickedFile { bytes, .. }|
                                serde_json::from_slice::<Value>(&bytes).map_err(|e| format!("Invalid JSON. {e}")));
                            let document = match body {
                                Ok(document) => document,
                                Err(err) => {
                                    if !err.is_empty() { mutation.message.set(Some(Err(err))); }
                                    return;
                                }
                            };
                            let request = document.clone();
                            mutation.run(move |client| async move {
                                client.import_baseline(id, &ImportBaselineParams {dry_run: Some(true), source_id: None}, &request).await
                            }, move |report| { preview.set(Some((document, report))); Ok(()) });
                        });
                    } />
            </label>
            {move || preview.get().map(|(document, report)| {
                view! {
                    <p>{format!("{} groups, {} bells and {} clock dials to import. {} existing items from this source will be replaced.",
                        report.created.bell_group, report.created.bell, report.created.clock_dial, report.replaced)}</p>
                    <ul>{report.warnings.into_iter().map(|p| view! { <li>{format!("{} · {}", p.field, p.message)}</li> }).collect_view()}</ul>
                    {(!report.unmapped_fields.is_empty()).then(|| view! {
                        <p>{format!("Unmapped fields kept with the source: {}", report.unmapped_fields.into_iter()
                            .map(|field| format!("{} ({})", field.field, field.count)).collect::<Vec<_>>().join(", "))}</p>
                    })}
                    {ui::table(&["Type", "Item"], report.items.into_iter()
                        .map(|item| vec![ui::text(item.type_code), ui::text(item.name)]).collect(), "No items to import.")}
                    <button type="button" class="tc-btn tc-btn-primary" disabled=move || mutation.pending.get()
                        on:click=move |_| {
                            let document = document.clone();
                            mutation.run(move |client| async move {
                                client.import_baseline(id, &ImportBaselineParams {dry_run: Some(false), source_id: None}, &document).await
                            }, move |_| {
                                preview.set(None);
                                mutation.saved("Baseline imported.");
                                Ok(())
                            });
                        }>"Import baseline"</button>
                }
            })}
        </details>
    }
}

#[component]
fn ProductMatches(id: Uuid, revision: RwSignal<u64>) -> impl IntoView {
    let offset = RwSignal::new(0);
    let status = RwSignal::new(String::new());
    let data = ui::load(revision, move |client| {
        let status = status.get();
        let offset = offset.get();
        async move {
            client
                .product_matches(
                    id,
                    &ProductMatchesParams {
                        status: (!status.is_empty()).then_some(status),
                        offset: Some(offset),
                        limit: Some(PAGE_SIZE),
                        ..Default::default()
                    },
                )
                .await
        }
    });
    view! {
        <section class="tc-phase-section">
            <h2>"Product matches"</h2>
            <label class="tc-phase-field">"Suitability"
                <select class="tc-input" on:change=move |ev| {offset.set(0); status.set(event_target_value(&ev));}>
                    <option value="">"All"</option><option value="suitable">"Suitable"</option>
                    <option value="unknown">"Unknown"</option><option value="unsuitable">"Unsuitable"</option>
                </select>
            </label>
            {ui::loaded(data, move |page| {
                let summary = format!("{} suitable · {} unknown · {} unsuitable", page.counts.suitable, page.counts.unknown, page.counts.unsuitable);
                let table = ui::table(&["Product", "Family", "Suitability", "Reasons"], page.items.into_iter().map(|item| vec![
                    ui::link(format!("{} · {}", item.code, item.name), &format!("/products/{}", item.id)),
                    ui::text(item.family_code.unwrap_or_default()),
                    ui::text(match item.status { MatchStatus::Suitable => "Suitable", MatchStatus::Unsuitable => "Unsuitable", MatchStatus::Unknown => "Unknown" }),
                    view! {<ul>{item.reasons.into_iter().map(|reason| view! {<li>{reason.message}</li>}).collect_view()}</ul>}.into_any(),
                ]).collect(), "No matching products.");
                view! {<p>{summary}</p>{table}{ui::pager(offset, PAGE_SIZE, page.total)}}.into_any()
            })}
        </section>
    }
}

fn type_fields(create: bool) -> Vec<Field> {
    let mut fields = vec![
        Field::text("name", "Name").required(),
        Field::new(
            "allowed_parent_codes",
            "Allowed parent codes, separated by commas",
            FieldType::List,
        ),
        Field::new("allow_top_level", "Allow at top level", FieldType::Toggle),
        Field::new("active", "Active", FieldType::Toggle),
        Field::new("sort_order", "Sort order", FieldType::Integer),
    ];
    if create {
        fields.insert(0, Field::text("code", "Code (snake_case)").required());
    }
    fields
}

#[component]
pub fn BaselineTypesPage() -> impl IntoView {
    let revision = RwSignal::new(0);
    let mutation = Mutation::new(revision);
    let data = ui::load(revision, |client| async move {
        client.list_baseline_item_types().await
    });
    view! {
        <div>
            <h2>"Site baseline types"</h2>
            <Status mutation=mutation />
            {ui::save(mutation, "New baseline type", type_fields(true), json!({"active":true,"allow_top_level":true}),
                |client, body| async move {client.create_baseline_item_type(&body).await})}
            {ui::loaded(data, move |types| ui::table(&["Code","Name","Parents","Top level","Active","Actions"], types.into_iter().map(|ty| {
                let id = ty.id;
                let edit = ui::save(mutation, "Edit", type_fields(false), json!(ty),
                    move |client, body| async move {client.update_baseline_item_type(id, &body).await});
                let delete = ui::action(mutation, "Delete", Some("Delete this baseline type?"),
                    move |client| async move {client.delete_baseline_item_type(id).await});
                vec![ui::text(ty.code),ui::text(ty.name),ui::text(ty.allowed_parent_codes.join(", ")),
                    ui::text(if ty.allow_top_level {"Yes"} else {"No"}),ui::text(if ty.active {"Yes"} else {"No"}),
                    view! {<div class="tc-phase-actions">{edit}{delete}</div>}.into_any()]
            }).collect(), "No baseline types."))}
        </div>
    }
}
