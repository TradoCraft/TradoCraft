use leptos::prelude::*;
use serde_json::json;
use tradocraft_api_client::mrp::*;
use tradocraft_api_client::{ListSuppliersParams, Supplier};
use uuid::Uuid;

use super::phase2::{self as ui, Field, FieldType, Mutation, Status};
use super::production::order_link;

#[component]
pub fn MrpPage() -> impl IntoView {
    let revision = RwSignal::new(0);
    let mutation = Mutation::new(revision);
    let status = RwSignal::new("open".to_owned());
    let kind = RwSignal::new(String::new());
    let run = RwSignal::new(None::<Uuid>);
    let cursors = RwSignal::new(vec![None::<Uuid>]);
    let runs = ui::load(
        revision,
        |client| async move { client.list_mrp_runs().await },
    );
    let references = ui::load(RwSignal::new(0), |client| async move {
        let divisions = client.list_divisions().await.unwrap_or_default();
        let suppliers = client
            .list_suppliers(&ListSuppliersParams::default())
            .await
            .unwrap_or_default();
        Ok((divisions, suppliers))
    });
    let proposals = ui::load(revision, move |client| {
        let status = status.get();
        let kind = kind.get();
        let params = ListMrpProposalsParams {
            status: (!status.is_empty()).then_some(status),
            kind: (!kind.is_empty()).then_some(kind),
            run_id: run.get(),
            after: cursors.with(|c| c.last().copied().flatten()),
            limit: Some(50),
            ..Default::default()
        };
        async move { client.list_mrp_proposals(&params).await }
    });
    let conversion = RwSignal::new(None::<(String, MrpConversion)>);
    view! {
        <div>
            <h1>"Material requirements planning"</h1>
            <Status mutation=mutation />
            {ui::save(mutation,"Run MRP",vec![Field::new("horizon_days","Planning horizon (days)",FieldType::Integer)],
                json!({"horizon_days":90}),|client,body|async move {client.start_mrp_run(&body).await})}
            <div class="tc-phase-actions">
                <label class="tc-phase-field">"Run"
                    <select class="tc-input" on:change=move |ev| {cursors.set(vec![None]);run.set(event_target_value(&ev).parse().ok());}>
                        <option value="">"All runs"</option>
                        {move ||runs.get().and_then(Result::ok).unwrap_or_default().into_iter().map(|r| {
                            let id=r.id;
                            view! {<option value=id.to_string() selected=move ||run.get()==Some(id)>
                                {format!("{} · {} · {} proposals",r.number,r.planned_on,r.proposals)}
                            </option>}
                        }).collect_view()}
                    </select>
                </label>
                <label class="tc-phase-field">"Status"
                    <select class="tc-input" on:change=move |ev| {cursors.set(vec![None]);status.set(event_target_value(&ev));}>
                        <option value="all">"All statuses"</option>
                        <option value="open" selected>"Open"</option>
                        <option value="converted">"Converted"</option>
                        <option value="dismissed">"Dismissed"</option><option value="superseded">"Superseded"</option>
                    </select>
                </label>
                <label class="tc-phase-field">"Kind"
                    <select class="tc-input" on:change=move |ev| {cursors.set(vec![None]);kind.set(event_target_value(&ev));}>
                        <option value="">"All proposals"</option><option value="purchase">"Buy"</option><option value="production">"Build"</option>
                    </select>
                </label>
            </div>
            {move ||conversion.get().map(|(kind,result)|view! {
                <p role="status">"Created "
                    {if kind=="production" {order_link(result.converted_to,result.number)}else{ui::text(result.number)}}
                </p>
            })}
            {ui::loaded(proposals,move |proposals| {
                let next=(proposals.len()==50).then(||proposals.last().map(|p|p.id)).flatten();
                let (divisions,suppliers)=references.get().and_then(Result::ok).unwrap_or_default();
                let table=ui::table(&["Product","Proposal","Quantity","Order on","Needed on","Run","Status","Demand","Actions"],
                    proposals.into_iter().map(|p| {
                        let id=p.id;
                        let convert=(p.status=="open").then(||conversion_editor(mutation,&p,&divisions,&suppliers,conversion));
                        let dismiss=(p.status=="open").then(||ui::action(mutation,"Dismiss",Some("Dismiss this proposal?"),
                            move |client|async move {client.dismiss_mrp_proposal(id).await}));
                        let demand=view! {<ul>{p.pegging.into_iter().map(|d|view! {
                            <li>{format!("{} · {} · {}",d.kind,d.number,d.quantity)}</li>
                        }).collect_view()}</ul>}.into_any();
                        vec![ui::link(format!("{} · {}",p.product_code,p.product_name),&format!("/products/{}",p.product_id)),
                            view! {<strong>{p.kind}</strong><div>{p.reason}</div>}.into_any(),ui::text(p.quantity),
                            ui::text(format!("{}{}",p.order_date,if p.late {" · Late"}else{""})),
                            ui::text(p.need_date),ui::text(p.run_number),ui::text(p.status),demand,
                            view! {<div class="tc-phase-actions">{convert}{dismiss}</div>}.into_any()]
                    }).collect(),"No MRP proposals.");
                view! {
                    {table}
                    <div class="tc-phase-actions" aria-label="Pagination">
                        <button type="button" class="tc-btn" disabled=move ||cursors.with(|c|c.len()<=1)
                            on:click=move |_|cursors.update(|c|{if c.len()>1 {c.pop();}})>"Previous"</button>
                        <button type="button" class="tc-btn" disabled=next.is_none()
                            on:click=move |_|{if let Some(next)=next {cursors.update(|c|c.push(Some(next)));}}>"Next"</button>
                    </div>
                }.into_any()
            })}
        </div>
    }
}

fn conversion_editor(
    mutation: Mutation,
    proposal: &MrpProposal,
    divisions: &[tradocraft_api_client::production::Division],
    suppliers: &[Supplier],
    conversion: RwSignal<Option<(String, MrpConversion)>>,
) -> AnyView {
    let id = proposal.id;
    let kind = proposal.kind.clone();
    let field = if kind == "production" {
        Field::select(
            "division_id",
            "Production division",
            divisions
                .iter()
                .filter(|d| d.active)
                .map(|d| (d.id, d.name.clone())),
        )
    } else {
        Field::select(
            "supplier_id",
            "Supplier",
            suppliers
                .iter()
                .filter(|s| s.active)
                .map(|s| (s.id, format!("{} · {}", s.code, s.name))),
        )
    };
    ui::editor(
        if kind == "production" {
            "Create production order"
        } else {
            "Create purchase order"
        },
        vec![field],
        json!({"supplier_id":proposal.supplier_id}),
        mutation,
        move |value, open| {
            let body = match serde_json::from_value(value) {
                Ok(body) => body,
                Err(err) => {
                    mutation.message.set(Some(Err(err.to_string())));
                    return;
                }
            };
            let kind = kind.clone();
            mutation.run(
                move |client| async move { client.convert_mrp_proposal(id, &body).await },
                move |result| {
                    open.set(false);
                    conversion.set(Some((kind, result)));
                    mutation.saved("Proposal converted.");
                    Ok(())
                },
            );
        },
    )
}
