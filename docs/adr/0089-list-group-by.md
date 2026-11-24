# 0084 — List grouping

**Status:** Accepted (shared UI framework; extends [ADR 0081](0081-generic-list-view.md) and [ADR 0083](0083-list-filters-and-favourites.md))

**Context.** Lists can be sorted and filtered, but not summarised: "how many quotations are in each
status" or "customers per country" means filtering one value at a time and reading the total.

**Decision.**

1. **Group-by is a filter key.** A page declares `GroupDef`s (key, label). Each key must also be
   a filter key (`FilterDef`) of the list, so that the rows of one group are exactly the list
   filtered to that value. Labels of group headers come from the filter options; a value without
   an option shows the raw value. Only one grouping is active at a time (nested grouping is
   deferred).
2. **Groups endpoint.** `GET /<resource>/groups?group_by=<key>` plus the same `q` and filter
   parameters as the list returns `{"group_by": "<key>", "groups": [{"value": "...", "count": n}]}`
   for the rows the list would show, ordered by value, without paging (at most 200 groups; more is
   a 422 telling the user to filter first). `group_by` is looked up in a per-endpoint whitelist
   (`crates/core` `group` module; the user value never reaches the SQL text). Only columns that
   are never NULL are offered, so every group has a filter value that selects exactly it.
   Absent or unknown `group_by` is a 422.
3. **First endpoints.** Customers: `active`, `country_code`. Products: `active`, `product_type`.
   Quotations: `status`.
4. **List UI.** The filter menu gains a "Group by" section (single choice, "None"). When a
   grouping is active the list shows collapsible group headers (label and count) instead of
   rows. Groups start collapsed. Expanding a group loads its first page with the group value added
   to the filter selection (sort and search apply as usual); a group with more rows than the page
   offers "Load more". Changing search, filters, sort or the grouping reloads the groups, collapses them and clears
   the selection. While the groups reload, the old headers are removed (loading state) and no
   group can load rows until the new groups arrived. A reload of the same query and grouping
   (e.g. after a failed bulk action) keeps the selection like the flat list: expanded groups stay
   expanded, each one's loaded range is re-read, and selected rows that are no longer returned
   (or whose group vanished) are dropped. The row selection works across groups (by identity). Headers are focusable;
   Enter and Space toggle; Semantics say "<label>, <count> rows, expanded / collapsed". On the
   narrow layout the headers are list tiles (48 px).
5. **Favourites** also store the grouping (optional field; older stored favourites still decode).
6. **Opt-in.** Without `groupDefs` and `loadGroups` the list and its menu are unchanged.

**Consequences.**

- Group headers show counts only. Sums and other aggregates (for example the quotation total per
  status) need typed measures per endpoint and are deferred.
- Grouping by nullable or free-text columns (city, family) is deferred; it needs a "no value"
  group and exact-match filters.
- The group count query runs once per change of query, not per expansion.
