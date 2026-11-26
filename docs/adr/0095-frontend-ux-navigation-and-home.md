# 0095 — Navigation ergonomics, home overview and product editing in a tab

**Status:** Accepted (shared UI framework; builds on [ADR 0041](0041-workspace-tabs.md), [ADR 0079](0079-app-switcher-and-breadcrumbs.md), [ADR 0080](0080-global-search-and-notifications.md) and [ADR 0081](0081-generic-list-view.md))

**Context.** A review of the Flutter app found a set of small frictions rather than one missing
feature. Clearing a list search meant selecting and deleting the text. The `EntityList` header
was a rigid `Row` (title, spacer, actions, create button) that clipped on narrow windows. The
rail showed only the active `AppGroup` (ADR 0079) but not its name, and global search (ADR 0080)
was reachable only through the rail button and Ctrl/Cmd+K. On narrow screens the
`NavigationBar` received every destination of the active group, six for Service and Sales, more
than a bottom bar holds. There was no landing page: a user started on `/quotations` or was sent
to the first permitted section. The product form, with media uploads, pricing flags, VAT and
tracking, opened as a blocking `AlertDialog`, so the user could not look at another tab while
filling it in. The work was planned as five phases in
`docs/superpowers/plans/2026-11-23-frontend-ux-roadmap.md` and merged in PRs #152 to #156.

**Decision.**

1. **List search and header** (`app/lib/shared/entity_list.dart`). The search `TextField` shows a
   clear `IconButton` (`ValueKey('entity-list-clear-search')`, `AppIcons.close`, the Material
   "delete" tooltip) as `suffixIcon` while the text is not empty; it rebuilds through a
   `ValueListenableBuilder` on the controller. `_clearSearch` cancels the pending debounce, clears
   the field and reloads at once instead of waiting the 300 ms of `_onSearchChanged`. The header
   is a `Wrap` (`WrapAlignment.spaceBetween`, spacing 8) of the title and an inner `Wrap` of
   `actions` and the create button, so on a narrow window the actions move to the next line
   rather than overflowing. There is no overflow menu; all actions stay visible.
2. **Active group label** (`app/lib/core/navigation/app_switcher.dart`). `AppSwitcherButton`
   gains `showLabel` (default false). When true and a group is active it shows the group's label
   under the icon in `labelSmall`, one line, ellipsised. The shell passes `showLabel: wide`, so
   the label appears on the rail (width at least 800) and not in the narrow app bar. The button
   keeps its `appSwitcherTooltip` and `ValueKey('app-switcher')`.
3. **Search pill in the top bar** (`app/lib/core/navigation/global_search.dart`,
   `app/lib/app/shell.dart`). On the wide layout the `SectionBreadcrumbs` bar becomes a `Row`
   with the breadcrumbs (expanded) and a `GlobalSearchPill` (`ValueKey('top-bar-search')`): an
   `OutlinedButton.icon` labelled "Search (<shortcut>)", where the shortcut text comes from
   `ShortcutAction.palette.describe()`, so a rebound shortcut shows its new chord. It opens the
   same `showGlobalSearch` palette with the same "Go to" destinations as the rail button and the
   shortcut. The narrow layout keeps only the app-bar `GlobalSearchButton`.
4. **Narrow bottom bar capped at five** (`_NarrowNavigationBar` in `app/lib/app/shell.dart`).
   With five or fewer destinations the bar is unchanged. With more it shows the first four and a
   fifth "More" destination (`ValueKey('nav-more-button')`, `AppIcons.moreVert`, label from
   `MaterialLocalizations.moreButtonTooltip`). "More" opens a modal bottom sheet listing the
   remaining destinations as `ListTile`s; picking one navigates like a bar item. While the
   current section is one of the sheet entries, "More" is the selected bar item and the entry is
   marked selected in the sheet. The order is the order of the group's permitted destinations;
   the menu-number hints (`hinted`) keep their flat-list indices.
5. **Home overview** (`app/lib/features/home/home_page.dart`, route `/home` in
   `app/lib/app/router.dart`). `HomePage` shows "Overview" and a `Wrap` of cards (each 280 to
   420 px wide, `ValueKey('home-card-<id>')`), built only when the user holds the permission, so
   a hidden card makes no request:
   - **Open tabs** (only when tabs are open): every workspace tab by title (or location); a tap
     focuses the tab.
   - **To-dos** (`todo.use`): the first five of `TodoFilter.open` from `todoRepositoryProvider`;
     the header and the rows go to `/todo`.
   - **Helpdesk** (`helpdesk.read`): `GET /api/v1/tickets?status=open&limit=5`.
   - **Quotations** (`quotations.read`): `GET /api/v1/quotations?limit=5`.
   - **Purchase orders** (`purchasing.read`): `GET /api/v1/purchase-orders?limit=5`.

   The three API cards share `_ApiListCard` (plain `dioProvider` GET, reads `items`, takes five,
   shows number and customer, supplier or subject); a row pushes the detail location, which opens
   in a workspace tab, and the header goes to the section list. Each card has loading, error
   (`errorMessage`) and empty ("—") states. A home `IconButton`
   (`ValueKey('shell-home-button')`, `AppIcons.home`, tooltip `shortcutHome`) sits on the wide
   rail above the search button and in the narrow app bar; it calls `focusHome()` and goes to
   `/home`. The shell's "page not for this user" redirect (`found < 0`) exempts `/home`. The
   initial location stays `/quotations` and `ShortcutAction.menus` still index the flat,
   permission-filtered destination list.
6. **Product form in a tab** (`app/lib/features/products/product_form.dart`,
   `product_screen.dart`, `products_page.dart`). `ProductForm` gains `asTab`, `onSaved` and
   `onCancel`. With `asTab` it renders as a `Scaffold` with a title row (Cancel and Save on the
   right), a divider and a scrolling body capped at 720 px, instead of the 520 px
   `AlertDialog`; `showProductForm` keeps the dialog for callers outside the workspace. Edits to
   the tracked controllers, media and copy-from mark the form dirty once through
   `TabScope.reportDirty`, so closing the tab goes through the unsaved-changes prompt of
   `requestCloseTab` (ADR 0041). Cancel asks the same question itself when the caller passed
   `onCancel`, otherwise it calls `requestCloseTab` (or pops outside a tab). Saving clears the
   dirty flag, bumps `productsRefreshProvider` (which `ProductsPage` now listens to and reloads
   its list) and calls `onSaved`. The `TutorialTarget(id: 'product-form-save')` stays on the Save
   button.
   - **Create:** `ProductsPage.onCreate` pushes `/products/new` when a `GoRouter` is present
     (else the dialog). `detailScreen` maps it to `ProductScreen(id: 'new')`, which opens in a
     tab and renders `ProductForm(asTab: true)`; on save it closes its tab and focuses home (or
     goes to `/products/<id>` when not in a tab).
   - **Edit:** inside a tab, the Edit button of `ProductScreen` sets `_editing` and swaps the
     detail for `ProductForm(product: p, asTab: true)` in the same tab. Save invalidates
     `productProvider(id)` and returns to the detail; Cancel clears the dirty flag and returns.
     Outside a tab Edit still opens the dialog.

**Consequences.**

- Every `EntityList` gets the clear button and the wrapping header without opting in. A page
  with many actions grows a second header line on narrow windows rather than hiding actions in a
  menu.
- `/home` is not a destination: it is in no `AppGroup`, so on it the rail and bar fall back to
  the flat list, select the first section, and the breadcrumbs name that section.
- The home cards load once per build of the page (no polling, no reaction to the
  `todoBadgeSyncProvider`). The helpdesk card lists open tickets, not tickets assigned to the
  user; the quotation and purchase-order cards list the first five rows in the list endpoint's
  default order, not items awaiting approval. To-do rows open the to-do list, not the item.
- `/home` is reachable by the button and (since a later shortcut change) by the Home shortcut,
  but it is not the start page. Making it the default landing route, and a server-side summary
  endpoint instead of one list call per card, are deferred.
- The "More" sheet lists only the remaining destinations of the shown list; it has no link to
  switch groups (the switcher stays in the app bar).
- Only `ProductForm` has the tab mode. Other heavy dialog forms keep the blocking
  `AlertDialog`; moving them, or a wide side-sheet mode, is deferred.
- A new-product tab has no title until saved (`reportTitle` ignores the empty code), so it shows
  the tab's default label.
