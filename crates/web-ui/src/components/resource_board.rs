use leptos::prelude::*;

/// A resource label followed by one cell per time bucket, in column order.
pub struct ResourceRow {
    pub label: String,
    pub cells: Vec<AnyView>,
}

/// A scrollable schedule with row and column headings. Cell contents and actions are supplied
/// by the feature using the board.
#[component]
pub fn ResourceBoard(
    label: &'static str,
    columns: Vec<String>,
    rows: Vec<ResourceRow>,
) -> impl IntoView {
    view! {
        <div class="tc-table-wrap tc-phase-resource" tabindex="0" aria-label=label>
            <table class="tc-table" aria-label=label>
                <thead><tr><th scope="col">"Resource"</th>
                    {columns.into_iter().map(|column| view! {<th scope="col">{column}</th>}).collect_view()}
                </tr></thead>
                <tbody>
                    {rows.into_iter().map(|row| view! {
                        <tr>
                            <th scope="row">{row.label}</th>
                            {row.cells.into_iter().map(|cell| view! {<td>{cell}</td>}).collect_view()}
                        </tr>
                    }).collect_view()}
                </tbody>
            </table>
        </div>
    }
}
