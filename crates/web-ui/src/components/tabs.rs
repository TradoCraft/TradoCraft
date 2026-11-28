//! Permission-gated segmented tab switcher matching Flutter hub screens.

use leptos::prelude::*;
use leptos_router::components::A;

use crate::components::shell::app_href;

/// Descriptor for one item in [`SegmentedTabs`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SegmentTab {
    pub key: String,
    pub label: String,
    pub badge: Option<String>,
    pub href: Option<String>,
    pub target: Option<String>,
}

impl SegmentTab {
    /// Creates a button-mode segment descriptor.
    pub fn new(key: impl Into<String>, label: impl Into<String>) -> Self {
        Self {
            key: key.into(),
            label: label.into(),
            badge: None,
            href: None,
            target: None,
        }
    }

    /// Attaches an optional trailing badge (such as a count).
    pub fn with_badge(mut self, badge: impl Into<String>) -> Self {
        self.badge = Some(badge.into());
        self
    }

    /// Attaches a router destination path (`<A href=...>` instead of `<button>`).
    pub fn with_href(mut self, href: impl Into<String>) -> Self {
        self.href = Some(href.into());
        self
    }

    /// Overrides the default `data-target` attribute on this segment element.
    pub fn with_target(mut self, target: impl Into<String>) -> Self {
        self.target = Some(target.into());
        self
    }
}

/// Keeps only segments whose permission/feature flag evaluates to `true`, preserving order.
pub fn visible_segments(tabs: Vec<(SegmentTab, bool)>) -> Vec<SegmentTab> {
    tabs.into_iter()
        .filter_map(|(tab, allowed)| allowed.then_some(tab))
        .collect()
}

/// Resolves the active segment key: `requested` when present in `visible`, otherwise the first
/// visible segment's key.
pub fn resolve_active_segment(requested: Option<&str>, visible: &[SegmentTab]) -> Option<String> {
    requested
        .and_then(|key| visible.iter().find(|t| t.key == key))
        .or_else(|| visible.first())
        .map(|t| t.key.clone())
}

/// Permission-gated segmented switcher. Hides itself when only one segment is visible unless
/// `always_show` is `true`.
#[component]
pub fn SegmentedTabs(
    #[prop(into)] tabs: Signal<Vec<SegmentTab>>,
    #[prop(into)] active: Signal<String>,
    #[prop(optional)] on_select: Option<Callback<String>>,
    #[prop(into, default = "Sections".to_string())] aria_label: String,
    #[prop(into, default = "segmented-tabs".to_string())] target: String,
    #[prop(default = false)] always_show: bool,
) -> impl IntoView {
    let target_nav = StoredValue::new(target);
    let aria_label_sv = StoredValue::new(aria_label);

    view! {
        <Show when=move || tabs.with(|t| always_show || t.len() >= 2)>
            <nav
                class="tc-segments"
                role="tablist"
                aria-label=move || aria_label_sv.get_value()
                data-target=move || target_nav.get_value()
            >
                {move || {
                    let prefix = target_nav.get_value();
                    tabs.get()
                        .into_iter()
                        .map(|tab| {
                            let key = tab.key.clone();
                            let item_target = tab
                                .target
                                .clone()
                                .unwrap_or_else(|| format!("{prefix}-{}", tab.key));
                            let label = tab.label.clone();
                            let badge = tab.badge.clone();
                            match tab.href {
                                Some(href) => {
                                    let active_link = key.clone();
                                    let resolved_href = app_href(&href);
                                    view! {
                                        <A
                                            href=resolved_href
                                            attr:role="tab"
                                            attr:class=move || {
                                                if active.with(|a| a == &active_link) {
                                                    "tc-segment-btn tc-segment-btn-active"
                                                } else {
                                                    "tc-segment-btn"
                                                }
                                            }
                                            attr:aria-selected=move || {
                                                if active.with(|a| a == &key) { "true" } else { "false" }
                                            }
                                            attr:data-target=item_target
                                        >
                                            <span>{label}</span>
                                            {badge.map(|b| view! { <span class="tc-badge">{b}</span> })}
                                        </A>
                                    }
                                    .into_any()
                                }
                                None => {
                                    let key_select = key.clone();
                                    let key_aria = key.clone();
                                    view! {
                                        <button
                                            type="button"
                                            role="tab"
                                            class=move || {
                                                if active.with(|a| a == &key) {
                                                    "tc-segment-btn tc-segment-btn-active"
                                                } else {
                                                    "tc-segment-btn"
                                                }
                                            }
                                            aria-selected=move || {
                                                if active.with(|a| a == &key_aria) { "true" } else { "false" }
                                            }
                                            data-target=item_target
                                            on:click=move |_| {
                                                if let Some(cb) = on_select {
                                                    cb.run(key_select.clone());
                                                }
                                            }
                                        >
                                            <span>{label}</span>
                                            {badge.map(|b| view! { <span class="tc-badge">{b}</span> })}
                                        </button>
                                    }
                                    .into_any()
                                }
                            }
                        })
                        .collect_view()
                }}
            </nav>
        </Show>
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn visible_segments_filters_while_keeping_order() {
        let out = visible_segments(vec![
            (SegmentTab::new("suppliers", "Suppliers"), true),
            (SegmentTab::new("po", "Purchase orders"), false),
            (SegmentTab::new("receipts", "Goods receipts"), true),
        ]);
        let keys: Vec<_> = out.into_iter().map(|t| t.key).collect();
        assert_eq!(keys, vec!["suppliers", "receipts"]);
    }

    #[test]
    fn resolve_active_segment_picks_requested_or_first_visible() {
        let tabs = vec![
            SegmentTab::new("suppliers", "Suppliers"),
            SegmentTab::new("po", "Purchase orders"),
        ];
        assert_eq!(
            resolve_active_segment(Some("po"), &tabs).as_deref(),
            Some("po")
        );
        assert_eq!(
            resolve_active_segment(Some("unknown"), &tabs).as_deref(),
            Some("suppliers")
        );
        assert_eq!(
            resolve_active_segment(None, &tabs).as_deref(),
            Some("suppliers")
        );
        assert_eq!(resolve_active_segment(Some("po"), &[]), None);
    }
}
