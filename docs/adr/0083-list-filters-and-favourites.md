# 0083 — List filters, facets and favourites

**Status:** Accepted (shared UI framework; extends [ADR 0081](0081-generic-list-view.md), API side builds on [ADR 0082](0082-list-sorting.md))

**Context.** The generic list has one free-text search box. Narrowing a list by a known attribute
(only active customers, only draft quotations, only one product type) means typing into the search
and hoping it matches, or scrolling. People also repeat the same combination every day and have
nowhere to keep it.

**Decision.**

1. **Filter definition (`FilterDef`).** A page declares the filters its list offers: an API key, a
   label and a fixed list of options (value and label). A filter is multi-select: the selected
   values of one filter combine with OR, different filters combine with AND. Nothing is selected
   by default, so every existing list keeps today's result until a page opts in with
   `EntityList.filterDefs` (the older `filters` slot, a free widget for custom controls, is kept).
2. **Search bar with facets.** Active filter values appear as removable chips next to the search
   text (one chip per filter, "Status: Draft or Sent"). A filter menu button lists every filter
   with checkable options; a "Clear filters" entry removes all. Backspace in an empty search field
   removes the last chip. Changing a filter reloads from offset 0 and clears the selection, like a
   change of search or sort. Chips and menu entries have Semantics labels and meet the 48 px target
   on narrow layouts, where the same menu is used.
3. **Query contract.** `ListQuery.filters` maps the filter key to the selected values (a set of
   strings). Repositories pass them to the client as the comma-joined list the API expects.
4. **API.** A list endpoint takes one optional query parameter per filter it supports, named like
   the filter key. A value is a single value or a comma-separated list. A shared parser in
   `crates/core` (`filter::values`) takes the raw string and a per-endpoint list of allowed values
   (or a validator), returns the values, and fails with the standard validation error (422) on an
   unknown value, an empty item or more than 20 values. Values are bound as parameters
   (`= ANY($n)`), never put in the SQL text. Absent or blank means no filter, so existing callers
   are unaffected. Boolean filters keep the plain `true` / `false` form already used by
   `active` on products.
5. **First endpoints.** Customers: `active`, `country_code`. Products: `active` (already
   there), `product_type`. Quotations: `status` (extended from one value to a list). The other
   paged endpoints follow with sorting (ADR 0082).
6. **Favourites.** A favourite is a named set of search text and filter selections, saved per
   user and list (`prefsKey`) in the same per-user store as the column layout, under
   `entity_list_fav:<prefsKey>`. The menu can save the current state under a name, apply a
   favourite and delete it. A favourite that names an unknown filter or option is applied
   without that part; a damaged value is ignored. Sort is not part of a favourite (it already has
   its own saved state). Without `prefsKey` the favourites section is hidden.

**Consequences.**

- Pages stay thin: a list of `FilterDef` plus a repository that forwards `filters`.
- Server-side saved filters (shared between users or devices) are deferred; the store behind
  `prefsKey` is per user and per device.
- Free-form conditions (greater than, date ranges, custom field filters) are deferred; filters
  are fixed option lists. Group-by is the next step and will reuse the facet chips.
- The `filter` parser has the same whitelist discipline as `sort`: user input is looked up,
  never interpolated.
