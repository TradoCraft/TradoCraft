# 0087 — Generic kanban view

**Status:** Accepted (UI framework phase 5, first part: the view and the opportunity pipeline;
builds on [ADR 0078](0078-repository-layer.md), [ADR 0081](0081-generic-list-view.md) and
[ADR 0085](0085-generic-form-view.md))

**Context.** The opportunities page shows the pipeline as a row of summary cards above a list. Moving
an opportunity to another stage means opening it and pressing a button. The planning board already
has drag and drop (`resource_board.dart`), but it is built around time and lanes and cannot be
reused for cards in columns. Tickets will need the same view later, so it is built once.

**Decision.** `lib/framework/views/kanban/` holds a generic board, configured per entity like the
list and form views (ADR 0081, 0085), with no server-driven layout and **no backend change**: an
entity only needs a way to list the items of one column and a way to move an item.

*Config.* `KanbanConfig<T>`:
- `columns`: id, label, optional accent colour;
- `idOf(T)`, `columnOf(T)` (the column an item sits in) and `cardBuilder(context, T)`;
- `loadColumn(columnId, offset, limit) → KanbanPage<T>` (items and the column's total);
- `columnSummary(columnId)` (optional text under the label, such as a sum), loaded with the board;
- `move(T, toColumnId) → Future<MoveResult>`: the entity decides what a move means and may ask the
  user first (a reason). `MoveResult.moved` | `cancelled`; an error is thrown and shown;
- `onOpen(T)` and an optional `onCreate(columnId)` (the "+" in a column header).

*Behaviour.*
- **Loading per column, server side.** Each column loads its first 50 items on its own, in
  parallel, so a slow or failing column does not hide the others (a failed column shows a retry).
  A column with more items shows "Show N more", which loads the next page. No client-side
  paging of a full list.
- **Moving is optimistic.** Dropping a card puts it at the top of the target column at once and
  calls `move`; on `cancelled` or an error the card goes back and the error is shown on the board.
  After a move the two columns' summaries are reloaded, since the numbers changed. Dropping on the
  column the card is in does nothing.
- **Mouse and touch.** A card is picked up with a short hold (150 ms, as on the planning board),
  so scrolling by touch still works. The board scrolls horizontally; each column scrolls
  vertically on its own.
- **Keyboard and screen readers.** Drag and drop is not the only way: every card has a "Move to…"
  menu listing the other columns (focusable, reachable with Tab), and Enter on a card opens it.
  Columns and cards carry semantics labels (column name and count; card title).
- **Narrow layouts.** Columns keep their width (280 px) and the board scrolls sideways; there is
  no separate phone layout in this step.

*Opportunities.* The page gets a List | Board switch. The board has one column per stage in
pipeline order. Cards show number and title, customer, expected value and close date, and the
probability. A column's summary is the sum and the weighted sum from the existing
`GET /opportunities/pipeline`. Columns load with `GET /opportunities?stage=&limit=50`.
`move` calls `POST /opportunities/{id}/stage`. Moving to **Lost** asks for the reason first
(cancelling the dialog cancels the move), as the opportunity screen does; moving out of Won or
Lost reopens the opportunity, which the server already allows. The search box filters the whole
board with the list's `q` parameter. The "+" in a column creates an opportunity with the
existing form and, when the column is not the first, moves it there.

**Consequences.**
- A second entity (tickets, ADR to follow) is one `KanbanConfig` and a page switch.
- The board does not show live changes made by colleagues; it reloads on a pull-down refresh and
  when it is opened. Live updates would need a channel that tells a column to reload, which the
  record channel (ADR 0073) does not offer for lists.
- An opportunity has no row version, so two people moving the same card is last writer wins, as
  it already is on the opportunity screen.
- Ordering inside a column is the server's (expected close date, then number). Dragging to a
  position within or between columns is not supported: a card lands at the top of its new column
  until the next reload puts it where the server sorts it.

**Not yet.** Tickets on the board; the calendar view; grouping by a field other than the stage;
swimlanes; card colours by priority; saved board filters; live updates; WIP limits.
