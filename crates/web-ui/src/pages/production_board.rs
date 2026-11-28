use chrono::{Days, NaiveDate};
use leptos::prelude::*;
use serde_json::json;
use tradocraft_api_client::production::*;
use uuid::Uuid;

use super::phase2::{self as ui, Field, FieldType, Mutation, Status};
use super::production::{order_link, production_nav};
use crate::components::resource_board::{ResourceBoard, ResourceRow};

#[cfg(target_arch = "wasm32")]
fn today() -> NaiveDate {
    let date = js_sys::Date::new_0();
    NaiveDate::from_ymd_opt(
        date.get_full_year() as i32,
        date.get_month() + 1,
        date.get_date(),
    )
    .expect("browser date is valid")
}

#[cfg(not(target_arch = "wasm32"))]
fn today() -> NaiveDate {
    let days = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
        / 86_400;
    NaiveDate::from_ymd_opt(1970, 1, 1).unwrap() + Days::new(days)
}

#[component]
pub fn ProductionCapacityPage() -> impl IntoView {
    view! {<CapacityBoard planning=false />}
}

#[component]
pub fn ProductionBoardPage() -> impl IntoView {
    view! {<CapacityBoard planning=true />}
}

#[component]
fn CapacityBoard(planning: bool) -> impl IntoView {
    let revision = RwSignal::new(0);
    let mutation = Mutation::new(revision);
    let from = RwSignal::new(today());
    let to = RwSignal::new(today() + Days::new(13));
    let division = RwSignal::new(None::<Uuid>);
    let divisions = ui::load(RwSignal::new(0), |client| async move {
        client.list_divisions().await
    });
    let centre_options = ui::load(RwSignal::new(0), |client| async move {
        client
            .list_work_centres(&ListWorkCentresParams {
                active: Some(true),
                division_id: None,
            })
            .await
    });
    let data = ui::load(revision, move |client| {
        let from = from.get();
        let to = to.get();
        let division_id = division.get();
        async move {
            if to < from {
                return Err(crate::api::ApiError::InvalidConfig(
                    "The end date must be on or after the start date.".into(),
                ));
            }
            if planning {
                client
                    .production_planning_board(&ProductionPlanningBoardParams {
                        from,
                        to,
                        division_id,
                    })
                    .await
            } else {
                let result = client
                    .production_capacity(&ProductionCapacityParams {
                        from,
                        to,
                        division_id,
                    })
                    .await?;
                Ok(ProductionPlanningBoard {
                    from: result.from,
                    to: result.to,
                    centres: result.centres,
                    operations: vec![],
                })
            }
        }
    });
    view! {
        <div>
            <h1>{if planning {"Production planning board"} else {"Production capacity"}}</h1>
            {production_nav()}
            <div class="tc-phase-actions">
                <label class="tc-phase-field">"From"
                    <input class="tc-input" type="date" prop:value=move ||from.get().to_string() on:change=move |ev| {
                        if let Ok(date)=event_target_value(&ev).parse(){from.set(date);}
                    } />
                </label>
                <label class="tc-phase-field">"Through"
                    <input class="tc-input" type="date" prop:value=move ||to.get().to_string() on:change=move |ev| {
                        if let Ok(date)=event_target_value(&ev).parse(){to.set(date);}
                    } />
                </label>
                <label class="tc-phase-field">"Division"
                    <select class="tc-input" on:change=move |ev|division.set(event_target_value(&ev).parse().ok())>
                        <option value="">"All divisions"</option>
                        {move ||divisions.get().and_then(Result::ok).unwrap_or_default().into_iter().map(|d|view! {
                            <option value=d.id.to_string()>{d.name}</option>
                        }).collect_view()}
                    </select>
                </label>
            </div>
            <Status mutation=mutation />
            {ui::loaded(data,move |board| {
                if board.centres.is_empty() {return ui::text("No work centres in this range.");}
                let dates=board.from.iter_days().take_while(|date|*date<=board.to).collect::<Vec<_>>();
                let choices=centre_options.get().and_then(Result::ok).unwrap_or_default();
                let columns=dates.iter().map(ToString::to_string).collect();
                let rows=board.centres.iter().map(|centre| {
                    let cells=dates.iter().map(|date| {
                        let day=centre.days.iter().find(|d|d.date==*date);
                        let capacity=day.map(|day|format!("{} / {} min{}",day.load_minutes,day.available_minutes,
                            if day.overloaded {" · Overloaded"} else {""})).unwrap_or_default();
                        let operations=board.operations.iter().filter(|op|op.work_centre_id==centre.id
                            &&op.planned_start<=*date&&op.planned_end>=*date).map(|op| {
                            if *date==op.planned_start.max(board.from) {
                                let edit=(!op.locked).then(||move_editor(mutation,op,&choices));
                                let label=format!("{} · {}",op.order_number,op.name);
                                view! {<li>{order_link(op.production_order_id,label)}
                                    <div>{format!("{} · {} min{}",op.product_name,op.planned_minutes,if op.late {" · Late"}else{""})}</div>
                                    {edit}
                                </li>}.into_any()
                            } else {
                                view! {<li>{format!("{} · {} continues",op.order_number,op.name)}</li>}.into_any()
                            }
                        }).collect_view();
                        view! {<span class:tc-phase-overloaded=day.is_some_and(|d|d.overloaded)>{capacity}</span><ul>{operations}</ul>}.into_any()
                    }).collect();
                    ResourceRow {label:format!("{} · {} · {} / {} min",centre.code,centre.name,
                        centre.total_load_minutes,centre.total_available_minutes),cells}
                }).collect();
                let label=if planning {"Scheduled operations by work centre"} else {"Capacity and load by work centre"};
                view! {<ResourceBoard label columns rows />}.into_any()
            })}
        </div>
    }
}

fn move_editor(
    mutation: Mutation,
    op: &ProductionBoardOperation,
    centres: &[WorkCentre],
) -> AnyView {
    let production_id = op.production_order_id;
    let op_id = op.id;
    ui::editor(
        "Move operation",
        vec![
            Field::select(
                "work_centre_id",
                "Work centre",
                centres
                    .iter()
                    .map(|c| (c.id, format!("{} · {}", c.code, c.name))),
            ),
            Field::new("planned_start", "Start", FieldType::Date).required(),
            Field::new("planned_end", "End", FieldType::Date).required(),
            Field::new(
                "force",
                "Apply despite scheduling conflicts",
                FieldType::Toggle,
            ),
        ],
        json!(op),
        mutation,
        move |value, open| {
            let body: ProductionOperationUpdate = match serde_json::from_value(value.clone()) {
                Ok(body) => body,
                Err(err) => {
                    mutation.message.set(Some(Err(err.to_string())));
                    return;
                }
            };
            let force = value["force"].as_bool() == Some(true);
            mutation.run(
                move |client| async move {
                    let preview = client
                        .move_production_operation(
                            production_id,
                            op_id,
                            &MoveProductionOperationParams {
                                dry_run: Some(true),
                                force: Some(false),
                            },
                            &body,
                        )
                        .await?;
                    if preview.conflicts.iter().any(|c| c.severity == "error") && !force {
                        return Ok(preview);
                    }
                    client
                        .move_production_operation(
                            production_id,
                            op_id,
                            &MoveProductionOperationParams {
                                dry_run: Some(false),
                                force: Some(force),
                            },
                            &body,
                        )
                        .await
                },
                move |result| {
                    let conflicts = result
                        .conflicts
                        .into_iter()
                        .map(|c| {
                            let kind = match c.kind.as_str() {
                                "overload" => "Capacity exceeded",
                                "before_predecessor" => "Starts before preceding operation ends",
                                "after_successor" => "Ends after following operation starts",
                                "later_than_ready" => "Finishes after the order is due",
                                "on_closure" => "Work centre is closed",
                                _ => &c.kind,
                            };
                            c.day
                                .map_or_else(|| kind.to_owned(), |d| format!("{kind} ({d})"))
                        })
                        .collect::<Vec<_>>();
                    if result.applied {
                        open.set(false);
                        let message = if conflicts.is_empty() {
                            "Operation moved.".into()
                        } else {
                            format!("Operation moved. {}", conflicts.join(". "))
                        };
                        mutation.saved(&message);
                        Ok(())
                    } else {
                        Err(format!(
                            "Review the scheduling conflicts. {}",
                            conflicts.join(". ")
                        ))
                    }
                },
            );
        },
    )
}
