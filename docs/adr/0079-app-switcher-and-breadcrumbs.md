# 0079 — Application switcher and breadcrumbs

**Status:** Accepted (phase of the shared UI framework; builds on [ADR 0077](0077-ui-theme-tokens-and-dark-mode.md) and the workspace tabs)

**Context.** The navigation rail lists every permitted section in one flat column. With about
twenty-five destinations it needs scrolling on a normal window, and a user who works in Service
still sees Finance and Planning. Detail pages open in workspace tabs, but nothing in the frame says
where a record sits: the tab label shows the record, the rail highlights the section.

**Decision.**

1. **Groups.** `core/navigation/app_groups.dart` defines `AppGroup(id, label, icon, art, paths)` and
   six groups: Sales, Service, Operations, Master data, Back office, Insight. A group holds
   destination paths; it is visible when at least one of its destinations is permitted
   (`visibleGroups`). The flat destination list in `shell.dart` stays the source of truth, so
   permissions, the "first permitted section" redirect, Home and the Alt+1-9 menu shortcuts (which
   index the flat, permission-filtered list) are unchanged.
2. **Switcher.** A grid button (tooltip, semantics label, `app-switcher` key) sits at the top of the
   rail and in the narrow app bar. It opens a dialog with one tile per visible group (module
   artwork, label, focusable, the active group focused first). Choosing a group goes to its first
   permitted destination. The button is hidden when only one group is visible.
3. **Rail and bar show the active group.** The active group is derived from the section of the
   focused tab or page, not stored. The rail and the bottom bar list only its destinations. A path
   that belongs to no group, or a group with a single permitted destination (a rail and a bar need
   two), falls back to the flat list.
4. **Breadcrumbs.** A slim bar above the workspace body (wide layout) shows `Section > record`,
   from the active destination label and the focused tab's title. The section crumb focuses the main
   area and navigates to the section. The bar is hidden for list pages and until a title is known.
   `Breadcrumbs.report(context, crumbs)` mirrors `TabScope.reportTitle`: a sub-page inside a tab
   reports the steps below the section, kept per tab id in a Riverpod notifier. Nothing is reported
   outside a tab. The narrow layout has no bar (the tab menu and app bar already name the record).
5. **No router changes**; both features sit in the shell. Strings use the `appSwitcher*`,
   `appGroup*` and `breadcrumb*` keys in all five languages.

**Consequences.**

- Shorter rail, and a place to put new modules without growing a flat list.
- A user needs one more click to reach a section outside the active group; the Alt+1-9 shortcuts
  still reach the first nine permitted sections across groups.
- Group membership is a second list next to the destination list; a new destination must be added
  to a group or it appears only in the flat fallback.
