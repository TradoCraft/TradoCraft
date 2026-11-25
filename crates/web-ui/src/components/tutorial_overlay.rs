use leptos::prelude::*;
use leptos_router::hooks::{use_location, use_navigate};
use leptos_router::NavigateOptions;

use crate::components::shell::app_href;
use crate::tutorial::{all_chapters, TutorialState};

/// Floating narrator card (bottom-right) and chapter map modal for the TradoCraft tutorial.
#[component]
pub fn TutorialOverlay(state: RwSignal<TutorialState>) -> impl IntoView {
    let location = use_location();
    let navigate = use_navigate();

    let chapters = all_chapters();
    let total_chapters = chapters.len();

    view! {
        <div>
            {move || {
                let snapshot = state.get();
                if !snapshot.active {
                    let current_num = snapshot
                        .current_chapter()
                        .map(|c| c.number)
                        .unwrap_or(0);
                    let label = if snapshot.completed_chapters.is_empty() && snapshot.chapter_idx == 0 && snapshot.step_idx == 0 {
                        "Tutorial".to_string()
                    } else {
                        format!("Tutorial · Ch {current_num}")
                    };
                    return view! {
                        <div
                            style="position: fixed; right: 20px; bottom: 20px; z-index: 1000; display: flex; align-items: center; gap: 8px;"
                        >
                            <button
                                type="button"
                                class="tc-btn tc-btn-sm"
                                data-target="tutorial-chapter-map"
                                style="box-shadow: 0 6px 18px rgba(0, 0, 0, 0.28);"
                                on:click=move |_| state.update(TutorialState::toggle_map)
                            >
                                "Chapters"
                            </button>
                            <button
                                type="button"
                                class="tc-btn tc-btn-primary tc-btn-sm"
                                data-target="tutorial-open"
                                style="box-shadow: 0 6px 18px rgba(0, 0, 0, 0.28);"
                                on:click=move |_| state.update(TutorialState::start)
                            >
                                {label}
                            </button>
                        </div>
                    }.into_any();
                }

                let Some(chapter) = snapshot.current_chapter() else {
                    return view! { <div></div> }.into_any();
                };
                let Some(step) = snapshot.current_step() else {
                    return view! { <div></div> }.into_any();
                };

                let total_steps = chapter.steps.len();
                let step_number = snapshot.step_idx + 1;
                let can_prev = snapshot.chapter_idx > 0 || snapshot.step_idx > 0;
                let is_last_step_in_chapter = step_number >= total_steps;
                let is_last_chapter = snapshot.chapter_idx + 1 >= total_chapters;
                let next_label = if is_last_step_in_chapter && is_last_chapter {
                    "Finish"
                } else if is_last_step_in_chapter {
                    "Complete chapter"
                } else {
                    "Next"
                };

                let current_pathname = location.pathname.get();
                let nav_for_step = navigate.clone();

                view! {
                    <aside
                        class="tc-card"
                        data-target="tutorial-narrator"
                        aria-label="Tutorial narrator"
                        style="position: fixed; right: 20px; bottom: 20px; width: 390px; max-width: calc(100vw - 32px); z-index: 1000; display: flex; flex-direction: column; gap: var(--space-md); background: var(--surface-container); box-shadow: 0 12px 32px rgba(0, 0, 0, 0.36);"
                    >
                        <div style="display: flex; align-items: center; justify-content: space-between; gap: var(--space-sm);">
                            <div style="display: flex; align-items: center; gap: var(--space-xs); flex-wrap: wrap;">
                                <span class="tc-badge tc-badge-primary">
                                    {format!("Ch {} / {}", chapter.number, total_chapters.saturating_sub(1))}
                                </span>
                                <span class="tc-badge">
                                    {format!("Step {} / {}", step_number, total_steps)}
                                </span>
                                {if snapshot.is_chapter_completed(chapter.id) {
                                    view! { <span class="tc-badge tc-badge-success">"Done"</span> }.into_any()
                                } else {
                                    view! { <span></span> }.into_any()
                                }}
                            </div>

                            <div style="display: flex; align-items: center; gap: 4px;">
                                <button
                                    type="button"
                                    class="tc-btn tc-btn-ghost tc-btn-sm"
                                    data-target="tutorial-chapter-map"
                                    on:click=move |_| state.update(TutorialState::toggle_map)
                                >
                                    "Map"
                                </button>
                                <button
                                    type="button"
                                    class="tc-btn tc-btn-ghost tc-btn-sm"
                                    data-target="tutorial-close"
                                    aria-label="Close tutorial"
                                    on:click=move |_| state.update(TutorialState::pause)
                                >
                                    "×"
                                </button>
                            </div>
                        </div>

                        <div style="display: flex; flex-direction: column; gap: 4px;">
                            <div style="font-size: 11px; font-weight: 600; text-transform: uppercase; letter-spacing: 0.04em; color: var(--outline);">
                                {chapter.title}
                            </div>
                            <div style="font-size: 15px; font-weight: 600; color: var(--on-surface);">
                                {step.title}
                            </div>
                            <p style="margin: 0; font-size: 13px; color: var(--on-surface-variant); line-height: 1.45;">
                                {step.description}
                            </p>
                        </div>

                        {(step.route.is_some() || step.target.is_some()).then(|| {
                            let route_view = step.route.map(|route| {
                                let href = app_href(route);
                                let on_route = current_pathname == href;
                                let nav_click = nav_for_step.clone();
                                view! {
                                    <div style="display: flex; align-items: center; gap: 6px; flex-wrap: wrap;">
                                        {if on_route {
                                            view! {
                                                <span class="tc-badge tc-badge-success" data-target="tutorial-on-route">
                                                    {format!("On {href}")}
                                                </span>
                                            }.into_any()
                                        } else {
                                            view! {
                                                <button
                                                    type="button"
                                                    class="tc-btn tc-btn-sm"
                                                    data-target="tutorial-go-route"
                                                    on:click=move |_| nav_click(route, NavigateOptions::default())
                                                >
                                                    {format!("Open {route}")}
                                                </button>
                                            }.into_any()
                                        }}
                                    </div>
                                }
                            });

                            let target_view = step.target.map(|target| {
                                view! {
                                    <span class="tc-badge tc-mono" title="UI data-target hook">
                                        {format!("target: {target}")}
                                    </span>
                                }
                            });

                            view! {
                                <div style="display: flex; align-items: center; justify-content: space-between; gap: var(--space-xs); flex-wrap: wrap;">
                                    {route_view}
                                    {target_view}
                                </div>
                            }
                        })}

                        <div style="display: flex; align-items: center; justify-content: space-between; gap: var(--space-sm); padding-top: var(--space-sm); border-top: 1px solid var(--outline-variant);">
                            <button
                                type="button"
                                class="tc-btn tc-btn-sm"
                                data-target="tutorial-prev"
                                disabled=!can_prev
                                on:click=move |_| state.update(TutorialState::prev_step)
                            >
                                "Prev"
                            </button>

                            <div style="display: flex; align-items: center; gap: var(--space-xs);">
                                <button
                                    type="button"
                                    class="tc-btn tc-btn-ghost tc-btn-sm"
                                    data-target="tutorial-skip"
                                    on:click=move |_| state.update(TutorialState::skip_chapter)
                                >
                                    "Skip"
                                </button>
                                <button
                                    type="button"
                                    class="tc-btn tc-btn-primary tc-btn-sm"
                                    data-target="tutorial-next"
                                    on:click=move |_| state.update(TutorialState::next_step)
                                >
                                    {next_label}
                                </button>
                            </div>
                        </div>
                    </aside>
                }.into_any()
            }}

            {move || {
                let snapshot = state.get();
                if !snapshot.show_map {
                    return view! { <div></div> }.into_any();
                }

                let completed_count = snapshot.completed_chapters.len();

                view! {
                    <div
                        style="position: fixed; inset: 0; z-index: 1100; background: rgba(0, 0, 0, 0.58); display: grid; place-items: center; padding: 16px;"
                        data-target="tutorial-chapter-map-backdrop"
                    >
                        <div
                            class="tc-card"
                            data-target="tutorial-chapter-map-modal"
                            role="dialog"
                            aria-modal="true"
                            aria-label="Tutorial chapter map"
                            style="width: 720px; max-width: 100%; max-height: calc(100vh - 48px); display: flex; flex-direction: column; gap: var(--space-md); background: var(--surface-container); box-shadow: 0 18px 44px rgba(0, 0, 0, 0.45);"
                        >
                            <div style="display: flex; align-items: center; justify-content: space-between; gap: var(--space-md);">
                                <div>
                                    <h2 class="tc-page-title" style="font-size: 18px;">"Tutorial Chapters"</h2>
                                    <p class="tc-page-subtitle">
                                        {format!("{completed_count} of {total_chapters} chapters completed")}
                                    </p>
                                </div>
                                <button
                                    type="button"
                                    class="tc-btn tc-btn-sm"
                                    data-target="tutorial-map-close"
                                    on:click=move |_| state.update(|s| s.show_map = false)
                                >
                                    "Close"
                                </button>
                            </div>

                            <div style="overflow-y: auto; display: flex; flex-direction: column; gap: var(--space-sm); padding-right: 4px;">
                                {chapters.iter().enumerate().map(|(idx, chapter)| {
                                    let is_current = snapshot.chapter_idx == idx;
                                    let is_done = snapshot.is_chapter_completed(chapter.id);
                                    let jump_target = format!("tutorial-jump-{}", chapter.id);
                                    let border_style = if is_current {
                                        "border-color: var(--primary); background: var(--surface-container-high);"
                                    } else {
                                        "background: var(--surface-container-low);"
                                    };
                                    view! {
                                        <div
                                            class="tc-card"
                                            style=format!("padding: var(--space-md); display: flex; align-items: center; justify-content: space-between; gap: var(--space-md); {border_style}")
                                        >
                                            <div style="display: flex; flex-direction: column; gap: 4px; min-width: 0;">
                                                <div style="display: flex; align-items: center; gap: 6px; flex-wrap: wrap;">
                                                    <span class="tc-badge tc-mono">
                                                        {format!("{} · {}", chapter.number, chapter.id)}
                                                    </span>
                                                    <span style="font-weight: 600; color: var(--on-surface);">
                                                        {chapter.title}
                                                    </span>
                                                    {if is_done {
                                                        view! { <span class="tc-badge tc-badge-success">"Completed"</span> }.into_any()
                                                    } else if is_current {
                                                        view! { <span class="tc-badge tc-badge-primary">"Current"</span> }.into_any()
                                                    } else {
                                                        view! { <span class="tc-badge">{format!("{} steps", chapter.steps.len())}</span> }.into_any()
                                                    }}
                                                </div>
                                                <p style="margin: 0; font-size: 12px; color: var(--on-surface-variant);">
                                                    {chapter.goal}
                                                </p>
                                            </div>
                                            <button
                                                type="button"
                                                class=if is_current { "tc-btn tc-btn-primary tc-btn-sm" } else { "tc-btn tc-btn-sm" }
                                                data-target=jump_target
                                                on:click=move |_| state.update(|s| s.jump_to_chapter(idx))
                                            >
                                                {if is_current { "Resume" } else if is_done { "Replay" } else { "Start" }}
                                            </button>
                                        </div>
                                    }
                                }).collect_view()}
                            </div>
                        </div>
                    </div>
                }.into_any()
            }}
        </div>
    }
}
