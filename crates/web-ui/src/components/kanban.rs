use leptos::prelude::*;

/// A lane and the cards supplied by the caller, in display order.
pub struct KanbanLane {
    pub title: String,
    pub summary: String,
    pub cards: Vec<AnyView>,
}

/// Renders a horizontally scrollable pipeline. The caller supplies card actions.
#[component]
pub fn KanbanBoard(lanes: Vec<KanbanLane>) -> impl IntoView {
    view! {
        <div class="tc-phase-board" aria-label="Pipeline">
            {lanes.into_iter().map(|lane| view! {
                <section class="tc-card" aria-label=lane.title.clone()>
                    <h2>{lane.title.clone()}</h2>
                    <p>{lane.summary}</p>
                    <ul>{lane.cards.into_iter().map(|card| view! { <li>{card}</li> }).collect_view()}</ul>
                </section>
            }).collect_view()}
        </div>
    }
}
