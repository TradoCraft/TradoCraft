# 0080 — Global search and notifications centre

**Status:** Accepted (shared UI framework; builds on [ADR 0057](0057-accent-insensitive-search.md) and [ADR 0078](0078-repository-layer.md))

**Context.** Finding a record means opening its section first and using that list's search box.
People who work across sections (a customer, then their quotation, then a ticket) lose time on the
detour. `ShortcutAction.palette` (Ctrl/Cmd+K) was registered but did nothing. Things that need
attention (overdue to-dos, a stopped background worker) are shown in separate places, each only
while the right page is open or as a banner. The server has no search across entities and no
notification feed.

**Decision.**

1. **Global search is a client-side fan-out.** `showGlobalSearch` opens a command-palette dialog:
   one field, 250 ms debounce, arrow keys, Enter, Esc, mouse. `GlobalSearch` (in
   `core/navigation/global_search_model.dart`) asks the `q` parameter of the existing list endpoint
   of each entity in parallel, with a limit of 5. The `q` parameter already ignores case and
   accents (ADR 0057). A registry of `SearchEntity` (id, permission, label, icon, fetcher) is the
   only place that knows which client method serves which entity.
2. **Permissions gate the fan-out.** An entity is asked only when the user holds its read
   permission (the same strings as the shell's destinations). One entity that fails (offline,
   forbidden, server error) is shown as a failed group and never hides the others. A newer query
   discards the answer of an older one.
3. **"Go to".** The first group lists the shell's permitted sections whose label matches, so the
   palette also replaces clicking through the rail. The destinations are handed in by the shell,
   so the search does not depend on how the shell groups them.
4. **Opening a hit** is `context.go('/entity/:id')`; a detail location becomes a workspace tab
   (`DetailPortal`). Entities without a detail screen (packages) are not searched.
5. **Entry points.** Ctrl/Cmd+K through the shell's shortcut layer, and a search icon (tooltip
   with the shortcut) in the rail and the narrow app bar.
6. **Notifications centre, client-side.** `notificationsProvider` returns a list of
   `AppNotification` (id, title, subtitle, icon, severity, location), aggregated from what the app
   already knows: overdue and open to-dos (`todoCountsProvider`) and, for administrators, a worker
   that is down or never seen (`workerStatusProvider`). `NotificationsButton` shows a bell with a
   badge holding the number of entries (no badge at zero); an entry opens its location. Titles are
   translated when shown; `AppNotification.literal` takes ready-made text.

**Consequences.**

- No backend change and no new endpoint; the search costs one request per permitted entity per
  query, which is why the debounce and the small limit exist.
- Results are only as good as each list's `q` (the suppliers list has no `limit`, so it is cut on
  the client).
- Future work: a server-side search endpoint (one ranked request, cross-entity ranking, fewer
  round trips) and a server notifications feed (mentions, assignments, read state) that
  `notificationsProvider` can merge in without touching the bell. Offline-sync state is not part
  of the first version.
