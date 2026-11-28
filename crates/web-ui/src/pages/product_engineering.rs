use leptos::prelude::*;
use serde_json::json;
use tradocraft_api_client::engineering::*;
use tradocraft_api_client::production::ListWorkCentresParams;
use uuid::Uuid;

use super::phase2::{self as ui, Field, FieldType, Lookup, Mutation, Status};

#[component]
pub(super) fn BomsTab(id: Uuid) -> impl IntoView {
    let revision = RwSignal::new(0);
    let mutation = Mutation::new(revision);
    let selected = RwSignal::new(None::<Uuid>);
    let explosion = RwSignal::new(None::<Explosion>);
    let data = ui::load(
        revision,
        move |client| async move { client.list_boms(id).await },
    );
    view! {
        <section>
            <h2>"Bills of materials"</h2>
            <Status mutation=mutation />
            {ui::loaded(data, move |boms| {
                let new = ui::save(mutation, "New BOM revision", vec![
                    Field::select("copy_from", "Copy revision (blank uses active BOM)", boms.iter().map(|b| (b.id, format!("Revision {} · {}", b.revision, b.status)))),
                    Field::new("notes", "Notes", FieldType::Multiline),
                ], json!({}), move |client, body| async move { client.create_bom(id, &body).await });
                let explode = boms.iter().any(|b| b.status == "active").then(|| ui::editor("Explode active BOM",
                    vec![Field::text("quantity", "Build quantity").required()], json!({"quantity":"1"}), mutation,
                    move |value, open| {
                        let quantity = value["quantity"].as_str().map(str::to_owned);
                        mutation.run(move |client| async move {
                            client.explode_bom(id, &ExplodeBomParams {quantity}).await
                        }, move |result| {
                            explosion.set(Some(result));
                            open.set(false);
                            Ok(())
                        });
                    }));
                let rows = boms.into_iter().map(|bom| {
                    let bom_id = bom.id;
                    let version = view! {
                        <button type="button" class="tc-btn" on:click=move |_| selected.set(Some(bom_id))>
                            {format!("Revision {}", bom.revision)}
                        </button>
                    }.into_any();
                    vec![version, ui::text(bom.status), ui::text(bom.line_count), ui::text(bom.notes)]
                }).collect();
                view! {
                    <div class="tc-phase-actions">{new}{explode}</div>
                    {ui::table(&["Revision", "Status", "Components", "Notes"], rows, "No BOM revisions.")}
                }.into_any()
            })}
            {move || selected.get().map(|bom_id| view! { <BomDetail bom_id revision /> })}
            {move || explosion.get().map(|result| {
                let rows = result.nodes.into_iter().map(|r| vec![
                    ui::link(format!("{}{} · {}", " ".repeat(r.level.max(0) as usize), r.code, r.name), &format!("/products/{}", r.product_id)),
                    ui::text(r.required_quantity), ui::text(r.unit), ui::text(r.scrap_percent),
                ]).collect();
                view! {
                    <section class="tc-phase-section">
                        <h3>{format!("Requirements for {} units", result.quantity)}</h3>
                        {ui::table(&["Product", "Required quantity", "Unit", "Scrap (%)"], rows, "No component requirements.")}
                        <button type="button" class="tc-btn" on:click=move |_| explosion.set(None)>"Close requirements"</button>
                    </section>
                }
            })}
        </section>
    }
}

#[component]
fn BomDetail(bom_id: Uuid, revision: RwSignal<u64>) -> impl IntoView {
    let mutation = Mutation::new(revision);
    let data = ui::load(revision, move |client| async move {
        client.get_bom(bom_id).await
    });
    view! {
        <section class="tc-phase-section">
            <Status mutation=mutation />
            {ui::loaded(data, move |bom| {
                let edit = if bom.status == "draft" {
                    let current = json!(&bom);
                    let products = bom.lines.iter().map(|line| (
                        line.component_product_id, format!("{} · {}", line.component_code, line.component_name)
                    )).collect();
                    let lines = vec![
                        Field::lookup("component_product_id", "Component", Lookup::Product, products).required(),
                        Field::text("quantity", "Quantity").required(),
                        Field::text("scrap_percent", "Scrap (%)"),
                        Field::text("notes", "Notes"),
                    ];
                    let fields = vec![
                        Field::new("notes", "Notes", FieldType::Multiline),
                        Field::new("lines", "Components", FieldType::Rows(lines)),
                    ];
                    Some(ui::save(mutation, "Edit revision", fields, current, move |client, body| async move {
                        client.update_bom(bom_id, &body).await
                    }))
                } else { None };
                let activate = (bom.status == "draft").then(|| ui::action(mutation, "Activate revision",
                    Some("Activate this revision? The current active revision will become obsolete."),
                    move |client| async move {client.activate_bom(bom_id).await}));
                let rows = bom.lines.into_iter().map(|line| vec![
                    ui::text(line.position),
                    ui::link(format!("{} · {}", line.component_code, line.component_name), &format!("/products/{}", line.component_product_id)),
                    ui::text(line.quantity), ui::text(line.component_unit), ui::text(line.scrap_percent), ui::text(line.notes),
                ]).collect();
                let editable = bom.status == "draft";
                view! {
                    <h3>{format!("BOM revision {} · {}", bom.revision, bom.status)}</h3>
                    <div class="tc-phase-actions">{edit}{activate}</div>
                    {ui::table(&["Position","Component","Quantity","Unit","Scrap (%)","Notes"], rows, "No components.")}
                    <BomRoutingPanel bom_id revision editable />
                }.into_any()
            })}
        </section>
    }
}

#[component]
fn BomRoutingPanel(bom_id: Uuid, revision: RwSignal<u64>, editable: bool) -> impl IntoView {
    let mutation = Mutation::new(revision);
    let data = ui::load(revision, move |client| async move {
        client.get_routing(bom_id).await
    });
    let centres = ui::load(RwSignal::new(0), |client| async move {
        client
            .list_work_centres(&ListWorkCentresParams::default())
            .await
    });
    view! {
        <details>
            <summary>"Production routing"</summary>
            <Status mutation=mutation />
            {ui::loaded(data, move |routing| {
                let edit = editable.then(|| {
                    let centres = centres.get().and_then(Result::ok).unwrap_or_default();
                    let fields = vec![Field::new("operations", "Operations", FieldType::Rows(vec![
                        Field::text("name", "Operation").required(),
                        Field::select("work_centre_id", "Work centre", centres.into_iter().map(|c| (c.id, c.name))).required(),
                        Field::new("setup_minutes", "Setup minutes", FieldType::Integer),
                        Field::text("run_minutes_per_unit", "Run minutes per unit"),
                        Field::text("notes", "Instructions"),
                    ]))];
                    ui::save(mutation, "Edit routing", fields, json!(routing),
                        move |client, body| async move { client.set_routing(bom_id, &body).await })
                });
                let rows = routing.operations.into_iter().map(|op| vec![
                    ui::text(op.name), ui::text(op.work_centre_name), ui::text(op.setup_minutes), ui::text(op.run_minutes_per_unit),
                ]).collect();
                view! { {edit} {ui::table(&["Operation","Work centre","Setup (min)","Run per unit (min)"], rows, "No routing operations.")} }.into_any()
            })}
        </details>
    }
}

const SERIAL_STATUSES: [(&str, &str); 4] = [
    ("in_stock", "In stock"),
    ("delivered", "Delivered"),
    ("installed", "Installed"),
    ("scrapped", "Scrapped"),
];

#[component]
pub(super) fn SerialsTab(id: Uuid) -> impl IntoView {
    let revision = RwSignal::new(0);
    let mutation = Mutation::new(revision);
    let query = RwSignal::new(String::new());
    let offset = RwSignal::new(0);
    let selected = RwSignal::new(None::<Uuid>);
    let data = ui::load(revision, move |client| {
        let q = query.get();
        let offset = offset.get();
        async move {
            client
                .list_serials(&ListSerialsParams {
                    product_id: Some(id),
                    q: (!q.is_empty()).then_some(q),
                    offset: Some(offset),
                    limit: Some(50),
                    ..Default::default()
                })
                .await
        }
    });
    let boms = ui::load(RwSignal::new(0), move |client| async move {
        client.list_boms(id).await
    });
    view! {
        <section>
            <h2>"Serials & genealogy"</h2>
            <Status mutation=mutation />
            <div class="tc-phase-actions">
                <label class="tc-phase-field">"Search serial numbers"
                    <input type="search" class="tc-input" on:change=move |ev| {
                        offset.set(0);
                        query.set(event_target_value(&ev));
                    } />
                </label>
                {move || {
                    let boms = boms.get().and_then(Result::ok).unwrap_or_default();
                    ui::save(mutation, "Register serial number", vec![
                        Field::text("serial_number", "Serial number").required(),
                        Field::select("bom_id", "BOM revision", boms.into_iter().map(|bom| (bom.id, format!("Revision {} · {}", bom.revision, bom.status)))),
                        Field::new("notes", "Notes", FieldType::Multiline),
                    ], json!({}), move |client, body| async move {client.create_serial(id, &body).await})
                }}
            </div>
            {ui::loaded(data, move |page| {
                let table = ui::table(&["Serial number","Status","Customer","Warranty"], page.items.into_iter().map(|unit| {
                    let unit_id = unit.id;
                    vec![view! {
                        <button type="button" class="tc-btn" on:click=move |_| selected.set(Some(unit_id))>{unit.serial_number}</button>
                    }.into_any(), ui::text(unit.status), ui::text(unit.customer_name.unwrap_or_default()), ui::text(unit.warranty_status)]
                }).collect(), "No serial numbers.");
                view! {{table}{ui::pager(offset, 50, page.total)}}.into_any()
            })}
            {move || selected.get().map(|id| view! {<SerialDetail id selected revision />})}
        </section>
    }
}

#[component]
fn SerialDetail(
    id: Uuid,
    selected: RwSignal<Option<Uuid>>,
    revision: RwSignal<u64>,
) -> impl IntoView {
    let mutation = Mutation::new(revision);
    let data = ui::load(revision, move |client| async move {
        client.get_serial(id).await
    });
    let query = RwSignal::new(String::new());
    let candidates = ui::load(revision, move |client| {
        let q = query.get();
        async move {
            if q.is_empty() {
                return Ok(vec![]);
            }
            Ok(client
                .list_serials(&ListSerialsParams {
                    q: Some(q),
                    limit: Some(50),
                    ..Default::default()
                })
                .await?
                .items)
        }
    });
    view! {
        <section class="tc-phase-section">
            <Status mutation=mutation />
            {ui::loaded(data, move |detail| {
                let unit = detail.unit;
                let change = ui::save(mutation, "Change status", vec![
                    Field::select("status", "Status", SERIAL_STATUSES).required(),
                    Field::lookup("customer_id", "Customer", Lookup::Customer, unit.customer_id.iter().map(|id| (*id, unit.customer_name.clone().unwrap_or_default())).collect()),
                ], json!(unit), move |client, body| async move {client.set_status(id, &body).await});
                let warranty = ui::save(mutation, "Edit warranty", vec![
                    Field::new("warranty_until", "Warranty until", FieldType::Date),
                    Field::new("warranty_note", "Warranty note", FieldType::Multiline),
                ], json!(unit), move |client, body| async move {client.set_warranty(id, &body).await});
                let rows = detail.components.into_iter().map(|child| {
                    let child_id = child.id;
                    let number = format!("{}{}", " ".repeat(child.level.saturating_sub(1) as usize), child.serial_number);
                    let remove = (child.parent_id == id).then(|| ui::save(mutation, "Detach", vec![
                        Field::select("child_status", "Status after detaching", [("in_stock","In stock"),("scrapped","Scrapped")]),
                    ], json!({}), move |client, body| async move {client.detach_component(id, child_id, &body).await}));
                    vec![
                        view! {<button type="button" class="tc-btn" on:click=move |_| selected.set(Some(child_id))>{number}</button>}.into_any(),
                        ui::text(child.product_code), ui::text(child.status), view! {{remove}}.into_any()
                    ]
                }).collect();
                let history = detail.history.into_iter().map(|entry| vec![
                    ui::text(entry.serial_number), ui::text(entry.added_by_name),
                    ui::text(entry.added_at), ui::text(entry.removed_at.map(|d| d.to_string()).unwrap_or_default()),
                ]).collect();
                view! {
                    <h3>{format!("{} · {}", unit.product_code, unit.serial_number)}</h3>
                    <p>{format!("{} · {}", unit.status, unit.warranty_status)}</p>
                    {unit.parent_id.map(|parent| view! {
                        <button type="button" class="tc-btn" on:click=move |_| selected.set(Some(parent))>
                            {format!("Parent · {}", unit.parent_serial_number.unwrap_or_default())}
                        </button>
                    })}
                    <div class="tc-phase-actions">{change}{warranty}</div>
                    <h4>"Components"</h4>
                    {ui::table(&["Serial","Product","Status","Actions"], rows, "No components.")}
                    <h4>"Link history"</h4>
                    {ui::table(&["Serial","Added by","Added","Removed"], history, "No component changes.")}
                }.into_any()
            })}
            <label class="tc-phase-field">"Find a serial to attach"
                <input type="search" class="tc-input" on:change=move |ev| query.set(event_target_value(&ev)) />
            </label>
            {ui::loaded(candidates, move |choices| {
                let choices = choices.into_iter().filter(|u| u.id != id && u.parent_id.is_none() && u.status == "in_stock").map(|u|
                    (u.id, format!("{} · {}", u.serial_number, u.product_code))).collect::<Vec<_>>();
                if choices.is_empty() { return ui::text(""); }
                ui::save(mutation, "Attach component",
                    vec![Field::select("child_id", "Component serial", choices).required()], json!({}),
                    move |client, body| async move {client.attach_component(id, &body).await})
            })}
        </section>
    }
}
