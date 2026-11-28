use leptos::prelude::*;
use serde_json::json;
use tradocraft_api_client::production::*;
use uuid::Uuid;

use super::phase2::{self as ui, Field, FieldType, Lookup, Mutation, Status};

pub(super) const PRODUCTION_STATUSES: [(&str, &str); 4] = [
    ("released", "Released"),
    ("in_progress", "In progress"),
    ("completed", "Completed"),
    ("cancelled", "Cancelled"),
];

pub(super) fn production_nav() -> AnyView {
    view! {
        <nav class="tc-phase-actions" aria-label="Production sections">
            {ui::link("Production orders","/production")}
            {ui::link("Release queue","/production/release")}
            {ui::link("Divisions","/production/divisions")}
            {ui::link("Work centres","/production/work-centres")}
            {ui::link("Capacity","/production/capacity")}
            {ui::link("Planning board","/production/board")}
        </nav>
    }
    .into_any()
}

pub(super) fn order_link(id: Uuid, title: impl Into<String>) -> AnyView {
    ui::link(title, &format!("/production/{id}"))
}

fn orders_table(orders: Vec<ProductionSummary>) -> AnyView {
    ui::table(
        &[
            "Production order",
            "Product",
            "Quantity",
            "Status",
            "Division",
            "Planned ready",
            "Operations",
            "Shortages",
        ],
        orders
            .into_iter()
            .map(|o| {
                vec![
                    order_link(o.id, o.number),
                    ui::link(
                        format!("{} · {}", o.product_code, o.product_name),
                        &format!("/products/{}", o.product_id),
                    ),
                    ui::text(format!("{} {}", o.quantity, o.unit)),
                    ui::text(o.status.replace('_', " ")),
                    ui::text(o.division_name.unwrap_or_default()),
                    ui::text(
                        o.planned_ready_date
                            .map(|d| d.to_string())
                            .unwrap_or_default(),
                    ),
                    ui::text(format!("{}/{}", o.operations_done, o.operation_count)),
                    ui::text(o.short_components),
                ]
            })
            .collect(),
        "No production orders.",
    )
}

#[component]
pub fn ProductionPage() -> impl IntoView {
    let revision = RwSignal::new(0);
    let query = RwSignal::new(String::new());
    let status = RwSignal::new(String::new());
    let mine = RwSignal::new(false);
    let division = RwSignal::new(None::<Uuid>);
    let offset = RwSignal::new(0);
    let divisions = ui::load(RwSignal::new(0), |client| async move {
        client.list_divisions().await
    });
    let data = ui::load(revision, move |client| {
        let q = query.get();
        let status = status.get();
        let params = ListProductionOrdersParams {
            q: (!q.is_empty()).then_some(q),
            status: (!status.is_empty()).then_some(status),
            mine: Some(mine.get()),
            division_id: division.get(),
            offset: Some(offset.get()),
            limit: Some(50),
            ..Default::default()
        };
        async move { client.list_production_orders(&params).await }
    });
    view! {
        <div>
            <h1>"Production orders"</h1>
            {production_nav()}
            <div class="tc-phase-actions">
                <label class="tc-phase-field">"Search production orders"
                    <input class="tc-input" type="search" on:change=move |ev| {offset.set(0);query.set(event_target_value(&ev));}/>
                </label>
                <label class="tc-phase-field">"Status"
                    <select class="tc-input" on:change=move |ev| {offset.set(0);status.set(event_target_value(&ev));}>
                        <option value="">"All statuses"</option>
                        {PRODUCTION_STATUSES.into_iter().map(|(value,label)|view! {<option value=value>{label}</option>}).collect_view()}
                    </select>
                </label>
                <label class="tc-phase-field">"Division"
                    <select class="tc-input" on:change=move |ev| {offset.set(0);division.set(event_target_value(&ev).parse().ok());}>
                        <option value="">"All divisions"</option>
                        {move || divisions.get().and_then(Result::ok).unwrap_or_default().into_iter().map(|d|view! {
                            <option value=d.id.to_string()>{d.name}</option>
                        }).collect_view()}
                    </select>
                </label>
                <label><input type="checkbox" on:change=move |ev| {offset.set(0);mine.set(event_target_checked(&ev));} />" My divisions"</label>
            </div>
            {ui::loaded(data,move |page|view! {{orders_table(page.items)}{ui::pager(offset,50,page.total)}}.into_any())}
        </div>
    }
}

#[component]
pub fn ProductionReleasePage() -> impl IntoView {
    view! {<div><h1>"Release production"</h1>{production_nav()}<ReleaseQueue /></div>}
}

#[component]
fn ReleaseQueue(
    #[prop(optional)] order_id: Option<Uuid>,
    #[prop(optional)] revision: Option<RwSignal<u64>>,
) -> impl IntoView {
    let revision = revision.unwrap_or_else(|| RwSignal::new(0));
    let mutation = Mutation::new(revision);
    let queue = ui::load(revision, move |client| async move {
        let mut queue = client.production_to_release().await?;
        if let Some(order_id) = order_id {
            queue.retain(|item| item.order_id == order_id);
        }
        Ok(queue)
    });
    let lookups = ui::load(RwSignal::new(0), |client| async move {
        client.list_divisions().await
    });
    view! {
        <section>
            <Status mutation=mutation />
            {move || lookups.get().and_then(Result::ok).and_then(|divisions| order_id.is_none().then(|| {
                let mut fields = release_fields(&divisions);
                fields.insert(0,Field::lookup("product_id","Manufactured product", Lookup::ManufacturedProduct, vec![]).required());
                fields.insert(1,Field::text("quantity","Quantity").required());
                release_editor(mutation,"Release for stock",fields,json!({}),None)
            }))}
            {ui::loaded(queue,move |items| {
                let divisions = lookups.get().and_then(Result::ok).unwrap_or_default();
                let rows = items.into_iter().map(|item| {
                    let mut fields = release_fields(&divisions);
                    fields.insert(0,Field::text("quantity","Quantity to build"));
                    let release = release_editor(mutation,"Release",fields,json!({"quantity":item.to_build}),Some((item.order_id,item.order_line_id)));
                    vec![ui::link(item.order_number,&format!("/orders/{}",item.order_id)),ui::text(item.customer_name),
                        ui::link(format!("{} · {}",item.product_code,item.product_name),&format!("/products/{}",item.product_id)),
                        ui::text(item.ordered),ui::text(item.planned),ui::text(item.to_build),release]
                }).collect();
                ui::table(&["Sales order","Customer","Product","Ordered","Already planned","To build","Actions"],rows,"No lines awaiting release.")
            })}
        </section>
    }
}

fn release_fields(divisions: &[Division]) -> Vec<Field> {
    vec![
        Field::select(
            "division_id",
            "Division",
            divisions
                .iter()
                .filter(|d| d.active)
                .map(|d| (d.id, d.name.clone())),
        ),
        Field::new("start_date", "Earliest start", FieldType::Date),
        Field::new("planned_ready_date", "Planned ready", FieldType::Date),
        Field::new(
            "auto_release_subassemblies",
            "Release subassemblies as needed",
            FieldType::Toggle,
        ),
        Field::new("notes", "Notes", FieldType::Multiline),
    ]
}

fn release_editor(
    mutation: Mutation,
    title: &'static str,
    fields: Vec<Field>,
    initial: serde_json::Value,
    order_line: Option<(Uuid, Uuid)>,
) -> AnyView {
    ui::editor(title, fields, initial, mutation, move |value, open| {
        let mut body: ReleaseProductionInput = match serde_json::from_value(value) {
            Ok(body) => body,
            Err(err) => {
                mutation.message.set(Some(Err(err.to_string())));
                return;
            }
        };
        if let Some((order_id, line_id)) = order_line {
            body.order_id = Some(order_id);
            body.order_line_id = Some(line_id);
        }
        mutation.run(
            move |client| async move { client.release_production(&body).await },
            move |order| {
                open.set(false);
                mutation.saved(&format!("Released {}.", order.summary.number));
                Ok(())
            },
        );
    })
}

#[component]
pub(super) fn OrderProductionPanel(order_id: Uuid) -> impl IntoView {
    let revision = RwSignal::new(0);
    let offset = RwSignal::new(0);
    let orders = ui::load(revision, move |client| {
        let offset = offset.get();
        async move {
            client
                .list_production_orders(&ListProductionOrdersParams {
                    order_id: Some(order_id),
                    limit: Some(25),
                    offset: Some(offset),
                    ..Default::default()
                })
                .await
        }
    });
    view! {
        <section class="tc-phase-section">
            <h2>"Production"</h2>
            {ui::loaded(orders,move |page|view! {{orders_table(page.items)}{ui::pager(offset,25,page.total)}}.into_any())}
            <details>
                <summary>"Lines awaiting release"</summary>
                <ReleaseQueue order_id revision />
            </details>
        </section>
    }
}

fn settings_fields() -> Vec<Field> {
    vec![
        Field::text("code", "Code").required(),
        Field::text("name", "Name").required(),
        Field::new("sort_order", "Sort order", FieldType::Integer),
        Field::new("active", "Active", FieldType::Toggle),
    ]
}

fn division_fields() -> Vec<Field> {
    let mut fields = settings_fields();
    fields.push(Field::new(
        "member_user_ids",
        "Member user IDs, separated by commas",
        FieldType::List,
    ));
    fields
}

#[component]
pub fn ProductionDivisionsPage() -> impl IntoView {
    let revision = RwSignal::new(0);
    let mutation = Mutation::new(revision);
    let divisions = ui::load(
        revision,
        |client| async move { client.list_divisions().await },
    );
    view! {
        <div>
            <h1>"Production divisions"</h1>{production_nav()}<Status mutation=mutation />
            {ui::save(mutation,"New division",division_fields(),json!({"active":true}),|client,body|async move {client.create_division(&body).await})}
            {ui::loaded(divisions,move |divisions|ui::table(&["Code","Division","Members","Open orders","Active","Actions"],divisions.into_iter().map(|d| {
                let id = d.id;
                let mut initial = json!(d);
                initial["member_user_ids"] = json!(d.members.iter().map(|u|u.user_id).collect::<Vec<_>>());
                let edit = ui::save(mutation,"Edit division",division_fields(),initial,move |client,body|async move {client.update_division(id,&body).await});
                let delete = ui::action(mutation,"Delete",Some("Delete this division?"),
                    move |client|async move {client.delete_division(id).await});
                vec![ui::text(d.code),ui::text(d.name),ui::text(d.members.into_iter().map(|u|u.display_name).collect::<Vec<_>>().join(", ")),
                    ui::text(d.open_orders),ui::text(ui::yes_no(d.active)),view! {<div class="tc-phase-actions">{edit}{delete}</div>}.into_any()]
            }).collect(),"No divisions."))}
        </div>
    }
}

fn centre_fields(divisions: &[Division]) -> Vec<Field> {
    let mut fields = settings_fields();
    fields.extend([
        Field::select(
            "division_id",
            "Division",
            divisions.iter().map(|d| (d.id, d.name.clone())),
        ),
        Field::new("capacity", "Parallel capacity", FieldType::Integer),
        Field::text("cost_per_hour", "Cost per hour"),
        Field::new("notes", "Notes", FieldType::Multiline),
    ]);
    fields
}

#[component]
pub fn ProductionWorkCentresPage() -> impl IntoView {
    let revision = RwSignal::new(0);
    let mutation = Mutation::new(revision);
    let data = ui::load(revision, |client| async move {
        Ok((
            client
                .list_work_centres(&ListWorkCentresParams::default())
                .await?,
            client.list_divisions().await?,
        ))
    });
    view! {
        <div>
            <h1>"Work centres"</h1>{production_nav()}<Status mutation=mutation />
            {ui::loaded(data,move |(centres,divisions)| {
                let new = ui::save(mutation,"New work centre",centre_fields(&divisions),json!({"active":true}),|client,body|async move {
                    client.create_work_centre(&body).await
                });
                let rows = centres.iter().map(|c| {
                    let id = c.id;
                    let edit = ui::save(mutation,"Edit centre",centre_fields(&divisions),json!(c),move |client,body|async move {client.update_work_centre(id,&body).await});
                    let hours = ui::save(mutation,"Set opening hours",vec![
                        Field::new("slots","Weekly opening blocks (empty uses the default week)",FieldType::Rows(vec![
                            Field::new("weekday","Weekday (1 Monday – 7 Sunday)",FieldType::Integer).required(),
                            Field::text("start_time","Start (HH:MM)").required(),Field::text("end_time","End (HH:MM)").required(),
                        ]))
                    ],json!({"slots":c.hours}),move |client,body|async move {client.set_work_centre_hours(id,&body).await});
                    let delete = ui::action(mutation,"Delete",Some("Delete this work centre?"),move |client|async move {client.delete_work_centre(id).await});
                    vec![ui::text(&c.code),ui::text(&c.name),ui::text(c.division_name.as_deref().unwrap_or_default()),
                        ui::text(c.capacity),ui::text(c.open_operations),ui::text(ui::yes_no(c.active)),
                        view! {<div class="tc-phase-actions">{edit}{hours}{delete}</div>}.into_any()]
                }).collect();
                let centre_choices = centres.into_iter().map(|c|(c.id,c.name)).collect();
                view! {{new}{ui::table(&["Code","Work centre","Division","Capacity","Open operations","Active","Actions"],rows,"No work centres.")}
                    <Closures centre_choices revision />
                }.into_any()
            })}
        </div>
    }
}

#[component]
fn Closures(centre_choices: Vec<(Uuid, String)>, revision: RwSignal<u64>) -> impl IntoView {
    let mutation = Mutation::new(revision);
    let choices = StoredValue::new(centre_choices);
    let closures = ui::load(revision, |client| async move {
        client
            .list_work_centre_closures(&ListWorkCentreClosuresParams::default())
            .await
    });
    let fields = move || {
        vec![
            Field::select(
                "work_centre_id",
                "Work centre (blank for all)",
                choices.get_value(),
            ),
            Field::new("from_date", "From", FieldType::Date).required(),
            Field::new("to_date", "To", FieldType::Date).required(),
            Field::select(
                "kind",
                "Kind",
                [
                    ("other", "Other"),
                    ("holiday", "Holiday"),
                    ("maintenance", "Maintenance"),
                ],
            ),
            Field::text("note", "Note"),
        ]
    };
    view! {
        <section class="tc-phase-section">
            <h2>"Work centre closures"</h2><Status mutation=mutation />
            {ui::save(mutation,"New closure",fields(),json!({}),|client,body|async move {client.create_work_centre_closure(&body).await})}
            {ui::loaded(closures,move |closures|ui::table(&["Work centre","From","To","Kind","Note","Actions"],closures.into_iter().map(|c| {
                let id = c.id;
                let edit = ui::save(mutation,"Edit closure",fields(),json!(c),move |client,body|async move {client.update_work_centre_closure(id,&body).await});
                let delete = ui::action(mutation,"Delete",Some("Delete this work centre closure?"),move |client|async move {client.delete_work_centre_closure(id).await});
                vec![ui::text(c.work_centre_code.unwrap_or_else(||"All centres".into())),ui::text(c.from_date),ui::text(c.to_date),
                    ui::text(c.kind),ui::text(c.note),view! {<div class="tc-phase-actions">{edit}{delete}</div>}.into_any()]
            }).collect(),"No work centre closures."))}
        </section>
    }
}
