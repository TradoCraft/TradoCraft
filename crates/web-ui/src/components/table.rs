//! Reusable searchable, sortable, filterable, groupable, paginated [`EntityTable`].

use std::collections::HashSet;

use leptos::prelude::*;

/// Maximum simultaneous sort columns, matching `app/lib/shared/entity_list.dart`.
pub const MAX_SORTS: usize = 3;

/// Single sort column and direction.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SortSpec {
    pub field: String,
    pub descending: bool,
}

impl SortSpec {
    /// Creates an ascending sort spec.
    pub fn asc(field: impl Into<String>) -> Self {
        Self {
            field: field.into(),
            descending: false,
        }
    }

    /// Creates a descending sort spec.
    pub fn desc(field: impl Into<String>) -> Self {
        Self {
            field: field.into(),
            descending: true,
        }
    }
}

/// Encodes sort specs into the comma-separated API query format (`field,-other`), matching
/// `encodeListSort` in Flutter.
pub fn encode_list_sort(sorts: &[SortSpec]) -> Option<String> {
    if sorts.is_empty() {
        return None;
    }
    Some(
        sorts
            .iter()
            .map(|s| {
                if s.descending {
                    format!("-{}", s.field)
                } else {
                    s.field.clone()
                }
            })
            .collect::<Vec<_>>()
            .join(","),
    )
}

/// Updates `sorts` when the user clicks column header `field`. Without `multi` (Shift), replaces
/// the sort with `field` cycling asc -> desc -> none. With `multi`, cycles/appends `field` up to
/// [`MAX_SORTS`].
pub fn toggle_sort(sorts: &[SortSpec], field: &str, multi: bool) -> Vec<SortSpec> {
    let existing = sorts.iter().position(|s| s.field == field);
    if !multi {
        return match existing.map(|i| sorts[i].descending) {
            None => vec![SortSpec::asc(field)],
            Some(false) => vec![SortSpec::desc(field)],
            Some(true) => Vec::new(),
        };
    }

    let mut next = sorts.to_vec();
    match existing {
        None => {
            if next.len() >= MAX_SORTS {
                next.remove(0);
            }
            next.push(SortSpec::asc(field));
        }
        Some(idx) if !next[idx].descending => {
            next[idx].descending = true;
        }
        Some(idx) => {
            next.remove(idx);
        }
    }
    next
}

/// Filter chip definition shown in the [`EntityTable`] toolbar.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FilterChip {
    pub key: String,
    pub label: String,
}

impl FilterChip {
    pub fn new(key: impl Into<String>, label: impl Into<String>) -> Self {
        Self {
            key: key.into(),
            label: label.into(),
        }
    }
}

/// Grouping option shown in the [`EntityTable`] group-by dropdown.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GroupOption {
    pub key: String,
    pub label: String,
}

impl GroupOption {
    pub fn new(key: impl Into<String>, label: impl Into<String>) -> Self {
        Self {
            key: key.into(),
            label: label.into(),
        }
    }
}

/// Search, sort, filter, grouping, and pagination state for [`EntityTable`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TableQuery {
    pub search: String,
    pub sorts: Vec<SortSpec>,
    pub active_filters: Vec<String>,
    pub group_by: Option<String>,
    pub offset: usize,
    pub limit: usize,
}

impl Default for TableQuery {
    fn default() -> Self {
        Self::new(50)
    }
}

impl TableQuery {
    /// Creates an empty query with page size `limit`.
    pub fn new(limit: usize) -> Self {
        Self {
            search: String::new(),
            sorts: Vec::new(),
            active_filters: Vec::new(),
            group_by: None,
            offset: 0,
            limit: limit.max(1),
        }
    }

    /// API `sort` query string, if any columns are sorted.
    pub fn sort_param(&self) -> Option<String> {
        encode_list_sort(&self.sorts)
    }

    /// Zero-based current page index.
    pub fn page_index(&self) -> usize {
        self.offset / self.limit.max(1)
    }

    /// Total number of pages for `total` items (minimum `1`).
    pub fn total_pages(&self, total: usize) -> usize {
        let limit = self.limit.max(1);
        total.div_ceil(limit).max(1)
    }

    /// Whether a previous page exists.
    pub fn has_prev(&self) -> bool {
        self.offset > 0
    }

    /// Whether a next page exists for `total` records.
    pub fn has_next(&self, total: usize) -> bool {
        self.offset.saturating_add(self.limit.max(1)) < total
    }

    /// Advances `offset` by one page when [`Self::has_next`] holds.
    pub fn next_page(&mut self, total: usize) -> bool {
        if self.has_next(total) {
            self.offset = self.offset.saturating_add(self.limit.max(1));
            true
        } else {
            false
        }
    }

    /// Moves `offset` back by one page when [`Self::has_prev`] holds.
    pub fn prev_page(&mut self) -> bool {
        if self.has_prev() {
            self.offset = self.offset.saturating_sub(self.limit.max(1));
            true
        } else {
            false
        }
    }

    /// Human-readable range label such as `"1–50 of 120"` or `"0 of 0"`.
    pub fn range_label(&self, shown: usize, total: usize) -> String {
        if total == 0 || shown == 0 {
            return format!("0 of {total}");
        }
        let start = self.offset.saturating_add(1);
        let end = self.offset.saturating_add(shown).min(total);
        format!("{start}\u{2013}{end} of {total}")
    }
}

/// Column definition for [`EntityTable`].
#[derive(Clone)]
pub struct TableColumn<T: 'static> {
    pub id: String,
    pub label: String,
    pub sort_key: Option<String>,
    pub align_right: bool,
    pub render: Callback<T, AnyView>,
}

impl<T: Send + Sync + 'static> TableColumn<T> {
    /// Creates an unsortable left-aligned column.
    pub fn new(
        id: impl Into<String>,
        label: impl Into<String>,
        render: impl Fn(T) -> AnyView + Send + Sync + 'static,
    ) -> Self {
        Self {
            id: id.into(),
            label: label.into(),
            sort_key: None,
            align_right: false,
            render: Callback::new(render),
        }
    }

    /// Marks the column as sortable on `sort_key`.
    pub fn sortable(mut self, sort_key: impl Into<String>) -> Self {
        self.sort_key = Some(sort_key.into());
        self
    }

    /// Marks the column as right-aligned (numeric/tabular values).
    pub fn align_right(mut self) -> Self {
        self.align_right = true;
        self
    }
}

/// A grouped bucket of rows when [`EntityTable`] is showing grouped data.
#[derive(Clone)]
pub struct TableGroup<T> {
    pub key: String,
    pub label: String,
    pub count: usize,
    pub rows: Vec<T>,
}

fn render_data_row<T>(
    row: T,
    row_target: String,
    columns: &[TableColumn<T>],
    on_row_click: Option<Callback<T>>,
    is_selected: Option<Callback<T, bool>>,
) -> AnyView
where
    T: Clone + Send + Sync + 'static,
{
    let selected = is_selected.is_some_and(|cb| cb.run(row.clone()));
    let clickable = on_row_click.is_some();
    let class = match (clickable, selected) {
        (true, true) => "tc-row-clickable tc-row-selected",
        (true, false) => "tc-row-clickable",
        (false, true) => "tc-row-selected",
        (false, false) => "",
    };
    let click_row = row.clone();
    let action_row = row.clone();
    let cells = columns
        .iter()
        .map(|col| {
            let cell_view = col.render.run(row.clone());
            let td_class = if col.align_right { "tc-num" } else { "" };
            view! {
                <td class=td_class>{cell_view}</td>
            }
        })
        .collect_view();

    view! {
        <tr
            class=class
            data-target=row_target
            on:click=move |_| {
                if let Some(cb) = on_row_click {
                    cb.run(click_row.clone());
                }
            }
        >
            {cells}
            {on_row_click.map(|callback| view! {
                <td>
                    <button type="button" class="tc-btn tc-btn-sm" on:click=move |event| {
                        event.stop_propagation();
                        callback.run(action_row.clone());
                    }>"Open"</button>
                </td>
            })}
        </tr>
    }
    .into_any()
}

/// Reusable searchable, sortable, filterable, groupable, and paginated entity data table.
#[component]
pub fn EntityTable<T>(
    columns: Vec<TableColumn<T>>,
    #[prop(into)] rows: Signal<Vec<T>>,
    query: RwSignal<TableQuery>,
    #[prop(optional)] groups: Option<Signal<Vec<TableGroup<T>>>>,
    #[prop(into, default = Signal::derive(|| 0usize))] total: Signal<usize>,
    #[prop(into, default = Signal::derive(|| false))] loading: Signal<bool>,
    #[prop(into, optional)] error: Option<Signal<Option<String>>>,
    #[prop(default = Vec::new())] filters: Vec<FilterChip>,
    #[prop(default = Vec::new())] group_options: Vec<GroupOption>,
    #[prop(optional)] on_row_click: Option<Callback<T>>,
    #[prop(optional)] is_selected: Option<Callback<T, bool>>,
    #[prop(optional)] on_query_change: Option<Callback<TableQuery>>,
    #[prop(into, default = "Search…".to_string())] search_placeholder: String,
    #[prop(into, default = "No records found.".to_string())] empty_text: String,
    #[prop(into, default = "entity-table".to_string())] target: String,
) -> impl IntoView
where
    T: Clone + Send + Sync + 'static,
{
    let columns_sv = StoredValue::new(columns);
    let collapsed_groups = RwSignal::new(HashSet::<String>::new());

    let mutate_query = move |f: &dyn Fn(&mut TableQuery)| {
        let mut next = query.get_untracked();
        f(&mut next);
        query.set(next.clone());
        if let Some(cb) = on_query_change {
            cb.run(next);
        }
    };

    let target_root = target.clone();
    let target_search = format!("{target}-search");
    let target_clear = format!("{target}-search-clear");
    let target_group = format!("{target}-group-by");
    let target_empty = format!("{target}-empty");
    let target_range = format!("{target}-range");
    let target_prev = format!("{target}-prev");
    let target_next = format!("{target}-next");
    let target_sort_prefix = format!("{target}-sort");
    let target_filter_prefix = format!("{target}-filter");
    let target_row_prefix = format!("{target}-row");
    let target_group_prefix = format!("{target}-group");
    let has_group_options = !group_options.is_empty();
    let has_filters = !filters.is_empty();

    view! {
        <div class="tc-entity-table" data-target=target_root>
            <div class="tc-entity-table-toolbar">
                <div class="tc-search-box">
                    <input
                        type="search"
                        class="tc-input tc-search-input"
                        placeholder=search_placeholder
                        data-target=target_search
                        prop:value=move || query.with(|q| q.search.clone())
                        on:input=move |ev| {
                            let val = event_target_value(&ev);
                            mutate_query(&|q| {
                                q.search = val.clone();
                                q.offset = 0;
                            });
                        }
                    />
                    {move || {
                        let non_empty = query.with(|q| !q.search.is_empty());
                        non_empty.then(|| {
                            let clear_target = target_clear.clone();
                            view! {
                                <button
                                    type="button"
                                    class="tc-btn tc-btn-ghost tc-btn-sm tc-search-clear"
                                    aria-label="Clear search"
                                    data-target=clear_target
                                    on:click=move |_| {
                                        mutate_query(&|q| {
                                            q.search.clear();
                                            q.offset = 0;
                                        });
                                    }
                                >
                                    "×"
                                </button>
                            }
                        })
                    }}
                </div>

                {has_filters.then(|| {
                    let prefix = target_filter_prefix.clone();
                    view! {
                        <div class="tc-filter-chips">
                            {filters
                                .into_iter()
                                .map(|chip| {
                                    let key = chip.key.clone();
                                    let key_click = chip.key.clone();
                                    let chip_target = format!("{prefix}-{}", chip.key);
                                    view! {
                                        <button
                                            type="button"
                                            class=move || {
                                                let active = query.with(|q| q.active_filters.contains(&key));
                                                if active { "tc-chip tc-chip-active" } else { "tc-chip" }
                                            }
                                            data-target=chip_target
                                            on:click=move |_| {
                                                mutate_query(&|q| {
                                                    if let Some(pos) = q
                                                        .active_filters
                                                        .iter()
                                                        .position(|k| k == &key_click)
                                                    {
                                                        q.active_filters.remove(pos);
                                                    } else {
                                                        q.active_filters.push(key_click.clone());
                                                    }
                                                    q.offset = 0;
                                                });
                                            }
                                        >
                                            {chip.label}
                                        </button>
                                    }
                                })
                                .collect_view()}
                        </div>
                    }
                })}

                {has_group_options.then(|| {
                    view! {
                        <select
                            class="tc-select"
                            aria-label="Group by"
                            data-target=target_group
                            prop:value=move || query.with(|q| q.group_by.clone().unwrap_or_default())
                            on:change=move |ev| {
                                let raw = event_target_value(&ev);
                                let next_group = (!raw.is_empty()).then_some(raw);
                                collapsed_groups.update(HashSet::clear);
                                mutate_query(&|q| {
                                    q.group_by = next_group.clone();
                                    q.offset = 0;
                                });
                            }
                        >
                            <option value="">"No grouping"</option>
                            {group_options
                                .into_iter()
                                .map(|opt| {
                                    view! {
                                        <option value=opt.key>{opt.label}</option>
                                    }
                                })
                                .collect_view()}
                        </select>
                    }
                })}
            </div>

            {move || {
                error.and_then(|sig| sig.get()).map(|msg| view! {
                    <div class="tc-alert-error" style="margin-bottom: var(--space-md);" role="alert">
                        {msg}
                    </div>
                })
            }}

            <div class="tc-table-wrap">
                <table class="tc-table">
                    <thead>
                        <tr>
                            {move || {
                                let sort_prefix = target_sort_prefix.clone();
                                columns_sv.with_value(|cols| {
                                    cols.iter()
                                        .map(|col| {
                                            let label = col.label.clone();
                                            let align_right = col.align_right;
                                            let th_class = if align_right { "tc-num" } else { "" };
                                            match col.sort_key.clone() {
                                                Some(sort_key) => {
                                                    let btn_target = format!("{sort_prefix}-{sort_key}");
                                                    let key_indicator = sort_key.clone();
                                                    let key_click = sort_key.clone();
                                                    view! {
                                                        <th class=th_class>
                                                            <button
                                                                type="button"
                                                                class="tc-table-sort"
                                                                data-target=btn_target
                                                                on:click=move |ev: leptos::ev::MouseEvent| {
                                                                    let multi = ev.shift_key();
                                                                    mutate_query(&|q| {
                                                                        q.sorts = toggle_sort(&q.sorts, &key_click, multi);
                                                                        q.offset = 0;
                                                                    });
                                                                }
                                                            >
                                                                <span>{label}</span>
                                                                <span class="tc-table-sort-ind">
                                                                    {move || {
                                                                        query.with(|q| {
                                                                            q.sorts
                                                                                .iter()
                                                                                .find(|s| s.field == key_indicator)
                                                                                .map(|s| if s.descending { "▼" } else { "▲" })
                                                                                .unwrap_or("")
                                                                        })
                                                                    }}
                                                                </span>
                                                            </button>
                                                        </th>
                                                    }
                                                    .into_any()
                                                }
                                                None => view! { <th class=th_class>{label}</th> }.into_any(),
                                            }
                                        })
                                        .collect_view()
                                })
                            }}
                            {on_row_click.is_some().then(|| view! {<th scope="col">"Actions"</th>})}
                        </tr>
                    </thead>
                    <tbody>
                        {move || {
                            let col_span = columns_sv.with_value(|cols| (cols.len() + usize::from(on_row_click.is_some())).max(1));
                            let is_loading = loading.get();
                            let grouped_active = groups.is_some()
                                && query.with(|q| q.group_by.is_some());

                            if grouped_active {
                                let group_list = groups
                                    .map(|sig| sig.get())
                                    .unwrap_or_default();
                                if group_list.is_empty() {
                                    let text = if is_loading {
                                        "Loading…".to_string()
                                    } else {
                                        empty_text.clone()
                                    };
                                    return view! {
                                        <tr data-target=target_empty.clone()>
                                            <td colspan=col_span style="text-align: center; color: var(--on-surface-variant);">
                                                {text}
                                            </td>
                                        </tr>
                                    }
                                    .into_any();
                                }
                                let g_prefix = target_group_prefix.clone();
                                let r_prefix = target_row_prefix.clone();
                                return columns_sv
                                    .with_value(|cols| {
                                        group_list
                                            .into_iter()
                                            .map(|group| {
                                                let gkey = group.key.clone();
                                                let gkey_toggle = gkey.clone();
                                                let is_collapsed = collapsed_groups
                                                    .with(|set| set.contains(&gkey));
                                                let grp_target = format!("{g_prefix}-{gkey}");
                                                let caret = if is_collapsed { "▸" } else { "▾" };
                                                let header = view! {
                                                    <tr
                                                        class="tc-table-group-row"
                                                        data-target=grp_target
                                                        on:click=move |_| {
                                                            collapsed_groups.update(|set| {
                                                                if !set.insert(gkey_toggle.clone()) {
                                                                    set.remove(&gkey_toggle);
                                                                }
                                                            });
                                                        }
                                                    >
                                                        <td colspan=col_span>
                                                            <span style="margin-right: 6px;">{caret}</span>
                                                            <strong>{group.label}</strong>
                                                            <span class="tc-badge" style="margin-left: 8px;">{group.count}</span>
                                                        </td>
                                                    </tr>
                                                };
                                                let child_rows = (!is_collapsed).then(|| {
                                                    group
                                                        .rows
                                                        .into_iter()
                                                        .enumerate()
                                                        .map(|(idx, row)| {
                                                            render_data_row(
                                                                row,
                                                                format!("{r_prefix}-{gkey}-{idx}"),
                                                                cols,
                                                                on_row_click,
                                                                is_selected,
                                                            )
                                                        })
                                                        .collect_view()
                                                });
                                                view! {
                                                    {header}
                                                    {child_rows}
                                                }
                                            })
                                            .collect_view()
                                    })
                                    .into_any();
                            }

                            let list = rows.get();
                            if list.is_empty() {
                                let text = if is_loading {
                                    "Loading…".to_string()
                                } else {
                                    empty_text.clone()
                                };
                                return view! {
                                    <tr data-target=target_empty.clone()>
                                        <td colspan=col_span style="text-align: center; color: var(--on-surface-variant);">
                                            {text}
                                        </td>
                                    </tr>
                                }
                                .into_any();
                            }

                            let r_prefix = target_row_prefix.clone();
                            columns_sv
                                .with_value(|cols| {
                                    list.into_iter()
                                        .enumerate()
                                        .map(|(idx, row)| {
                                            render_data_row(
                                                row,
                                                format!("{r_prefix}-{idx}"),
                                                cols,
                                                on_row_click,
                                                is_selected,
                                            )
                                        })
                                        .collect_view()
                                })
                                .into_any()
                        }}
                    </tbody>
                </table>
            </div>

            <div class="tc-table-footer">
                <span class="tc-table-range" data-target=target_range>
                    {move || {
                        let shown = rows.with(Vec::len);
                        let tot = total.get().max(shown);
                        query.with(|q| q.range_label(shown, tot))
                    }}
                </span>
                <div class="tc-pagination">
                    <button
                        type="button"
                        class="tc-btn tc-btn-sm"
                        data-target=target_prev
                        disabled=move || loading.get() || !query.with(TableQuery::has_prev)
                        on:click=move |_| {
                            mutate_query(&|q| {
                                q.prev_page();
                            });
                        }
                    >
                        "Previous"
                    </button>
                    <button
                        type="button"
                        class="tc-btn tc-btn-sm"
                        data-target=target_next
                        disabled=move || {
                            let tot = total.get();
                            loading.get() || !query.with(|q| q.has_next(tot))
                        }
                        on:click=move |_| {
                            let tot = total.get_untracked();
                            mutate_query(&|q| {
                                q.next_page(tot);
                            });
                        }
                    >
                        "Next"
                    </button>
                </div>
            </div>
        </div>
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn encodes_list_sort_strings() {
        assert_eq!(encode_list_sort(&[]), None);
        assert_eq!(
            encode_list_sort(&[SortSpec::asc("name")]),
            Some("name".to_string())
        );
        assert_eq!(
            encode_list_sort(&[SortSpec::desc("updated_at"), SortSpec::asc("code")]),
            Some("-updated_at,code".to_string())
        );
    }

    #[test]
    fn toggle_sort_cycles_single_and_multi_with_cap() {
        let s1 = toggle_sort(&[], "name", false);
        assert_eq!(s1, vec![SortSpec::asc("name")]);
        let s2 = toggle_sort(&s1, "name", false);
        assert_eq!(s2, vec![SortSpec::desc("name")]);
        let s3 = toggle_sort(&s2, "name", false);
        assert!(s3.is_empty());

        let m1 = toggle_sort(&s1, "code", true);
        let m2 = toggle_sort(&m1, "price", true);
        let m3 = toggle_sort(&m2, "created_at", true);
        assert_eq!(
            m3,
            vec![
                SortSpec::asc("code"),
                SortSpec::asc("price"),
                SortSpec::asc("created_at"),
            ]
        );
    }

    #[test]
    fn table_query_pagination_and_range_math() {
        let mut q = TableQuery::new(25);
        assert_eq!(q.total_pages(0), 1);
        assert_eq!(q.total_pages(60), 3);
        assert!(!q.has_prev());
        assert!(q.has_next(60));
        assert_eq!(q.range_label(25, 60), "1\u{2013}25 of 60");

        assert!(q.next_page(60));
        assert_eq!(q.page_index(), 1);
        assert!(q.has_prev());
        assert!(q.has_next(60));
        assert_eq!(q.range_label(25, 60), "26\u{2013}50 of 60");

        assert!(q.next_page(60));
        assert!(!q.has_next(60));
        assert_eq!(q.range_label(10, 60), "51\u{2013}60 of 60");
        assert!(!q.next_page(60));

        assert!(q.prev_page());
        assert_eq!(q.offset, 25);
    }
}
