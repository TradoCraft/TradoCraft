use leptos::prelude::*;
use leptos_router::components::A;

#[component]
pub fn PlaceholderPage(#[prop(into)] title: String, #[prop(into)] route: String) -> impl IntoView {
    view! {
        <div class="tc-card" style="max-width: 640px;">
            <div class="tc-page-header" style="margin-bottom: var(--space-md);">
                <div>
                    <h1 class="tc-page-title">{title}</h1>
                    <p class="tc-page-subtitle tc-mono">{route}</p>
                </div>
                <span class="tc-badge">"Phase 1 Spike"</span>
            </div>
            <p style="margin: 0 0 var(--space-md); color: var(--on-surface-variant);">
                "This module screen is not part of the Phase 1 spike yet. Use Products to test the live API connection."
            </p>
            <A href="/products" attr:class="tc-btn tc-btn-primary">
                "Open Products"
            </A>
        </div>
    }
}
