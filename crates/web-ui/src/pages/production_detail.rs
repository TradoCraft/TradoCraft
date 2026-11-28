use leptos::prelude::*;
use serde_json::{json, Value};
use tradocraft_api_client::production::*;
use uuid::Uuid;

use super::phase2::{self as ui, Field, FieldType, Mutation, Status};
use super::production::{order_link, production_nav};
use crate::components::files::save_file;

#[component]
pub fn ProductionDetailPage() -> impl IntoView {
    let id = ui::record_id();
    view! {
        <div>
            {production_nav()}
            {move || id.get().map_or_else(||ui::text("Invalid production order ID."),|id|view! {<ProductionDetail id />}.into_any())}
        </div>
    }
}

#[component]
fn ProductionDetail(id: Uuid) -> impl IntoView {
    let revision = RwSignal::new(0);
    let mutation = Mutation::new(revision);
    let data = ui::load(revision, move |client| async move {
        client.get_production_order(id).await
    });
    let references = ui::load(RwSignal::new(0), |client| async move {
        let divisions = client.list_divisions().await.unwrap_or_default();
        let centres = client
            .list_work_centres(&ListWorkCentresParams::default())
            .await
            .unwrap_or_default();
        Ok((divisions, centres))
    });
    view! {
        <Status mutation=mutation />
        {ui::loaded(data,move |order| {
            let (divisions,centres) = references.get().and_then(Result::ok).unwrap_or_default();
            let s = &order.summary;
            let open = matches!(s.status.as_str(),"released"|"in_progress");
            let edit = open.then(||ui::save(mutation,"Edit order",vec![
                Field::select("division_id","Division",divisions.into_iter().map(|d|(d.id,d.name))),
                Field::new("planned_ready_date","Planned ready",FieldType::Date),
                Field::new("notes","Notes",FieldType::Multiline),
            ],json!({"division_id":s.division_id,"planned_ready_date":s.planned_ready_date,"notes":order.notes}),
            move |client,body|async move {client.update_production_order(id,&body).await}));
            let schedule = open.then(||ui::save(mutation,"Schedule operations",vec![
                Field::new("start_date","Earliest start",FieldType::Date),
                Field::new("finite","Respect available capacity",FieldType::Toggle),
            ],json!({"finite":true}),move |client,body|async move {client.schedule_production_order(id,&body).await}));
            let reserve = open.then(||ui::action(mutation,"Reserve components",None,
                move |client|async move {client.reserve_production_components(id).await}));
            let start = (s.status=="released").then(||ui::action(mutation,"Start production",None,
                move |client|async move {client.start_production_order(id).await}));
            let cancel = open.then(||ui::save(mutation,"Cancel production",vec![
                Field::new("reason","Cancellation reason",FieldType::Multiline).required(),
            ],json!({}),move |client,body|async move {client.cancel_production_order(id,&body).await}));
            let filename = format!("{}.pdf",s.number);
            let pdf = view! {
                <button type="button" class="tc-btn" disabled=move || mutation.pending.get() on:click=move |_| {
                    let filename=filename.clone();
                    mutation.run(move |client|async move {client.production_order_pdf(id,&ProductionOrderPdfParams::default()).await},
                        move |bytes| save_file(&filename,"application/pdf",&bytes));
                }>"Download PDF"</button>
            };
            let operation_rows = order.operations.iter().map(|op| operation_row(mutation,id,op,&centres,open)).collect();
            let components = order.components.iter().map(|c|component_row(mutation,id,c,open)).collect();
            let sub_orders = order.sub_orders.iter().map(|o|vec![
                order_link(o.id,o.number.clone()),ui::text(&o.product_name),ui::text(format!("{} {}",o.quantity,o.unit)),ui::text(&o.status),
            ]).collect();
            let outputs = order.outputs.iter().map(|o|vec![
                ui::text(&o.quantity),ui::text(o.lot_number.as_deref().unwrap_or_default()),ui::text(o.serial_number.as_deref().unwrap_or_default()),
            ]).collect();
            let rollup_quantity = s.quantity.clone();
            let product_id = s.product_id;
            let order_number = s.number.clone();
            let details = format!("{} · {} {} · {}",s.product_name,s.quantity,s.unit,s.status.replace('_'," "));
            let parent = order.parent_order_id.map(|id|order_link(id,format!("Parent · {}",order.parent_order_number.as_deref().unwrap_or_default())));
            let sales_order = s.order_id.map(|id| ui::link(format!("Sales order · {}",s.order_number.as_deref().unwrap_or_default()),&format!("/orders/{id}")));
            let complete = (s.status=="in_progress").then(|| {
                let order = order.clone();
                view! {<Completion order revision />}
            });
            view! {
                <h1>{order_number}</h1><p>{details}</p>
                <div class="tc-phase-actions">{parent}{sales_order}</div>
                {order.production_remark.map(|remark|view! {<p><strong>"Production remark "</strong>{remark}</p>})}
                <p>{order.notes}</p>
                {order.cancel_reason.map(|reason|view! {<p><strong>"Cancellation reason "</strong>{reason}</p>})}
                <div class="tc-phase-actions">{edit}{schedule}{reserve}{start}{complete}{cancel}{pdf}</div>
                <section class="tc-phase-section">
                    <h2>"Operations"</h2>
                    {ui::table(&["Position","Operation","Work centre","Start","End","Planned minutes","Actual minutes","Status","Actions"],operation_rows,"No operations.")}
                </section>
                <section class="tc-phase-section">
                    <h2>"Components"</h2>
                    {ui::table(&["Component","Required","Reserved","Consumed","Scrap","Tracking","Actions"],components,"No components.")}
                </section>
                {(!order.sub_orders.is_empty()).then(||view! {
                    <section class="tc-phase-section"><h2>"Sub-builds"</h2>
                        {ui::table(&["Order","Product","Quantity","Status"],sub_orders,"")}
                    </section>
                })}
                {(!order.outputs.is_empty()).then(||view! {
                    <section class="tc-phase-section"><h2>"Completed output"</h2>
                        {ui::table(&["Quantity","Lot","Serial"],outputs,"")}
                    </section>
                })}
                <section class="tc-phase-section">
                    <h2>"Costs"</h2>
                    {order.planned_cost.map(|cost|cost_summary("Planned cost",cost))}
                    {order.actual_cost.map(|cost|cost_summary("Actual cost",cost))}
                    <CostRollup product_id quantity=rollup_quantity />
                </section>
            }.into_any()
        })}
    }
}

fn cost_summary(title: &'static str, cost: ProductionOrderCost) -> AnyView {
    let incomplete = if cost.incomplete {
        " · incomplete"
    } else {
        ""
    };
    view! {
        <p><strong>{title}</strong>" · "
            {format!("{} total · {} materials · {} labour{incomplete}",cost.total_cost,cost.material_cost,cost.labour_cost)}
        </p>
    }.into_any()
}

fn operation_row(
    mutation: Mutation,
    id: Uuid,
    op: &ProductionOperation,
    centres: &[WorkCentre],
    open: bool,
) -> Vec<AnyView> {
    let op_id = op.id;
    let edit = (open && op.status == "pending").then(|| {
        ui::save(
            mutation,
            "Edit schedule",
            vec![
                Field::select(
                    "work_centre_id",
                    "Work centre",
                    centres.iter().map(|c| (c.id, c.name.clone())),
                ),
                Field::new("planned_start", "Planned start", FieldType::Date),
                Field::new("planned_end", "Planned end", FieldType::Date),
            ],
            json!(op),
            move |client, body| async move {
                client.update_production_operation(id, op_id, &body).await
            },
        )
    });
    let status_action = if open {
        match op.status.as_str() {
            "pending" => Some(ui::action(
                mutation,
                "Start",
                None,
                move |client| async move { client.start_production_operation(id, op_id).await },
            )),
            "in_progress" => Some(ui::save(
                mutation,
                "Finish",
                vec![
                    Field::new("actual_minutes", "Actual minutes", FieldType::Integer),
                    Field::text("note", "Note"),
                ],
                json!({}),
                move |client, body| async move {
                    client.finish_production_operation(id, op_id, &body).await
                },
            )),
            "done" => Some(ui::action(
                mutation,
                "Reopen",
                Some("Reopen this operation?"),
                move |client| async move { client.reopen_production_operation(id, op_id).await },
            )),
            _ => None,
        }
    } else {
        None
    };
    vec![
        ui::text(op.position),
        ui::text(&op.name),
        ui::text(&op.work_centre_name),
        ui::text(op.planned_start),
        ui::text(op.planned_end),
        ui::text(op.planned_minutes),
        ui::text(op.actual_minutes.map(|n| n.to_string()).unwrap_or_default()),
        ui::text(op.status.replace('_', " ")),
        view! {<div class="tc-phase-actions">{edit}{status_action}</div>}.into_any(),
    ]
}

fn component_row(
    mutation: Mutation,
    id: Uuid,
    c: &ProductionComponent,
    open: bool,
) -> Vec<AnyView> {
    let c_id = c.id;
    let build =
        (open && c.manufactured && c.short).then(|| {
            ui::save(
                mutation,
                "Build subassembly",
                vec![Field::new(
                    "auto_release_subassemblies",
                    "Release nested subassemblies",
                    FieldType::Toggle,
                )],
                json!({}),
                move |client, body| async move {
                    client.build_production_component(id, c_id, &body).await
                },
            )
        });
    vec![
        ui::link(
            format!("{} · {}", c.component_code, c.component_name),
            &format!("/products/{}", c.component_product_id),
        ),
        ui::text(format!("{} {}", c.required_quantity, c.unit)),
        ui::text(&c.reserved_quantity),
        ui::text(&c.consumed_quantity),
        ui::text(&c.scrap_quantity),
        ui::text(&c.tracking),
        view! {{c.short.then(||ui::text("Shortage"))}{build}}.into_any(),
    ]
}

#[component]
fn Completion(order: ProductionOrder, revision: RwSignal<u64>) -> impl IntoView {
    let id = order.summary.id;
    let order = StoredValue::new(order);
    let mutation = Mutation::new(revision);
    let inputs = ui::load(RwSignal::new(0), move |client| async move {
        let locations = client
            .list_warehouses()
            .await?
            .into_iter()
            .filter(|w| w.active)
            .flat_map(|w| {
                let code = w.code;
                w.locations
                    .into_iter()
                    .filter(|l| l.active)
                    .map(move |l| (l.id, format!("{code} · {} · {}", l.code, l.name)))
            })
            .collect::<Vec<_>>();
        let mut serials = std::collections::BTreeMap::new();
        let detail = order.get_value();
        for c in detail.components.iter().filter(|c| c.tracking == "serial") {
            let candidates = client
                .production_serial_candidates(
                    id,
                    c.id,
                    &ProductionSerialCandidatesParams::default(),
                )
                .await?;
            serials.insert(c.id, candidates);
        }
        Ok((locations, serials))
    });
    view! {
        <Status mutation=mutation />
        {ui::loaded(inputs,move |(locations,serials)| {
            let order=order.get_value();
            let mut fields=vec![];
            let mut initial=json!({});
            let mut output=vec![Field::text("quantity","Output quantity").required(),
                Field::select("location_id","Output location",locations.clone()).required()];
            match order.summary.product_tracking.as_str() {
                "serial"=>output.push(Field::new("serial_numbers","Output serial numbers, separated by commas",FieldType::List).required()),
                "lot"=>output.extend([Field::text("lot_number","Lot number").required(),Field::new("expiry_date","Expiry",FieldType::Date)]),
                _=>(),
            }
            initial["output"]=json!({"quantity":order.summary.quantity});
            fields.push(Field::new("output","Finished output",FieldType::Group(output)));
            for c in &order.components {
                let key=c.id.to_string();
                let mut actual=vec![Field::text("consumed_quantity","Consumed quantity")];
                if c.tracking=="serial" {
                    let choices=serials.get(&c.id).into_iter().flatten().map(|s|(s.id,format!("{} · {}",s.serial_number,s.location))).collect::<Vec<_>>();
                    actual.push(Field::new("serial_units","Consumed serial units",FieldType::Rows(vec![
                        Field::select("id","Serial unit",choices).required()
                    ])));
                } else {
                    actual.extend([Field::text("scrap_quantity","Scrap quantity"),
                        Field::select("extra_location_id","Location for unreserved stock",locations.clone()),
                        Field::text("extra_lot_id","Unreserved lot ID (lot-tracked components)")]);
                }
                initial[&key]=json!({"consumed_quantity":c.required_quantity});
                fields.push(Field::owned(key,format!("{} · {}",c.component_code,c.component_name),FieldType::Group(actual)));
            }
            if !order.operations.is_empty() {
                let operations=order.operations.iter().map(|op| {
                    let key=op.id.to_string();
                    let name=format!("Actual minutes · {}",op.name);
                    initial[&key]=json!(op.actual_minutes.unwrap_or(op.planned_minutes));
                    Field::owned(key,name,FieldType::Integer)
                });
                fields.extend(operations);
            }
            fields.push(Field::new("note","Completion note",FieldType::Multiline));
            let components = order.components.iter().map(|c|c.id).collect::<Vec<_>>();
            let operations = order.operations.iter().map(|op|op.id).collect::<Vec<_>>();
            ui::save(mutation,"Complete production",fields,initial,move |client,mut value:Value| {
                let components=components.clone();
                let operations=operations.clone();
                async move {
                    let mut actuals=vec![];
                    for id in components {
                        let mut row=value[&id.to_string()].take();
                        row["component_id"]=json!(id);
                        if let Some(units)=row["serial_units"].as_array() {
                            row["serial_unit_ids"]=json!(units.iter().map(|unit|unit["id"].clone()).collect::<Vec<_>>());
                        }
                        actuals.push(ui::decode::<ProductionComponentActual>(row)?);
                    }
                    let operations=operations.into_iter().filter_map(|id|value[&id.to_string()].as_i64()
                        .and_then(|minutes|i32::try_from(minutes).ok()).map(|minutes|ProductionOperationActual {operation_id:id,actual_minutes:Some(minutes)})).collect();
                    let body=CompleteProductionInput {
                        output:ui::decode(value["output"].take())?,
                        components:Some(actuals),
                        operations:Some(operations),
                        note:value["note"].as_str().map(str::to_owned),
                    };
                    client.complete_production_order(id,&body).await
                }
            })
        })}
    }
}

#[component]
fn CostRollup(product_id: Uuid, quantity: String) -> impl IntoView {
    let mutation = Mutation::new(RwSignal::new(0));
    let report = RwSignal::new(None::<ProductionCostRollup>);
    view! {
        <button type="button" class="tc-btn" disabled=move || mutation.pending.get() on:click=move |_| {
            let quantity=Some(quantity.clone());
            mutation.run(move |client|async move {client.production_cost_rollup(product_id,&ProductionCostRollupParams{quantity}).await},
                move |value| {report.set(Some(value));Ok(())});
        }>"Calculate BOM cost"</button>
        <Status mutation=mutation />
        {move || report.get().map(|report| {
            let header=format!("{} {} total · {} {} per unit",report.total_cost,report.currency,report.unit_cost,report.currency);
            let warnings=report.gaps.into_iter().map(|gap|view! {<li>{format!("{} · {}",gap.code,gap.kind)}</li>}).collect_view();
            let rows=report.levels.into_iter().map(|l|vec![ui::text(l.level),ui::text(l.product_name),
                ui::text(format!("{} {}",l.quantity,l.unit)),ui::text(l.material_cost),ui::text(l.labour_cost)]).collect();
            view! {<div><p>{header}</p><ul>{warnings}</ul>
                {ui::table(&["Level","Product","Quantity","Material cost","Labour cost"],rows,"No costs.")}
            </div>}
        })}
    }
}
