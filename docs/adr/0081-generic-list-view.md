# 0081 — Generic list view: sorting, columns, selection

**Status:** Accepted (shared UI framework; extends `EntityList`, builds on [ADR 0060](0060-keyboard-shortcuts.md) and [ADR 0078](0078-repository-layer.md))

**Context.** `EntityList<T>` serves 17 master-data and document lists with search, paging and
keyboard navigation, but every list looks the same: no sorting, fixed columns, no way to act on
several rows. Each page that needed more would have grown its own table. The widget must gain
these features without changing any existing call site.

**Decision.** Every addition is an optional parameter whose default reproduces today's layout.

1. **Sortable headers.** `EntityColumn.sortKey` (the API key; null means not sortable). A click
   cycles none, ascending, descending, none and reloads from offset 0 (the stale-response
   generation counter drops older answers). Shift-click adds a secondary key (at most three). The
   sort is sent as `field` or `-field`, comma separated (`encodeListSort`). Headers are focusable;
   Enter and Space toggle; Semantics say "sorted ascending / descending / not sorted".
2. **`loadQuery` path.** `EntityList` takes either the old `load(query, offset, limit)` or the new
   `loadQuery(ListQuery)` (search, offset, limit, sort, filters), never both (assert). Repositories
   hand `ListQuery` through unchanged, so a page migrates by swapping one parameter.
3. **Resizable columns** (`resizableColumns: true`, wide layout only). Columns get explicit
   widths: stored widths are fixed, the others share the remaining space by `flex`; minimum 64 px.
   A drag handle on the header border resizes it (also Left / Right on the focused handle),
   a double-click resets it; too wide a table scrolls horizontally. Without the flag the original
   flex layout is untouched.
4. **Column menu** (`columnMenu: true`). Toggles `hideable` columns (at least one stays visible),
   honours `defaultVisible`, and has "Reset layout".
5. **Persistence** (`prefsKey`). Visibility, widths and the sort are stored as one JSON value
   under `entity_list:<prefsKey>` in the signed-in user's `userKvStoreProvider` store (found
   through the enclosing `ProviderScope`; `prefsStore` overrides it, which tests use). The first
   load waits for the stored sort. Unknown columns and keys, and damaged values, are ignored.
   Without `prefsKey` nothing is stored. The widget stays a plain `StatefulWidget`, so
   `GlobalKey<EntityListState<T>>` keeps working.
6. **Selection and bulk actions** (`selectable: true`, `idOf`). A leading checkbox column; the
   header checkbox selects all loaded rows; Shift-click selects a range; Space on a focused row
   toggles. Selection is by identity, survives "Load more", is cleared when search or sort
   changes and pruned to loaded rows on other reloads. `BulkAction` (label, icon, `run`, optional
   `confirm` dialog, optional `enabled`) appears in a bar that replaces the count; afterwards the
   list reloads and the selection clears; errors use the shared snack bar and keep the selection.
   `onSelectionChanged` reports the selected items. Narrow layout: long-press starts selection, tiles
   show a checkbox, taps toggle until the selection is empty.
7. **Keyboard and accessibility.** `GridKeyNav` only treats the row focus nodes as cells, so
   checkboxes and header controls do not disturb the arrow keys. Every new control has a tooltip
   or Semantics label (`list*` strings in all five languages); colours come from the theme;
   there are no new animations, so reduced motion is respected; narrow targets are 48 px.

**Consequences.**

- Existing lists are unchanged until a page opts in; a regression test pins the plain layout.
- A page that sorts must pass a `loadQuery` whose repository sends `sort`; wiring it per entity is
  the follow-up (see [ADR 0082](0082-list-sorting.md) for the API side).
- Narrow screens have no sort control yet (no header there).
- Deferred: grouping, inline editing, facets and saved filters, column reordering (only
  visibility and width are stored), and server-side selection of "all N matching rows".
