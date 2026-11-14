# 0061 — To-do items

**Status:** Accepted (PR 1 of 3: backend and a minimal page. PR 2 of 3: context capture, the jump, the record button and `/customers/:id`, see below. PR 3 of 3: the badge, reminders by e-mail and removing a dead link, see below)

**Context.** The only list of things to do is `field.job_tasks`, the checklist of one field job. People
keep their own to-dos elsewhere, away from the records the to-dos are about, and cannot hand one to a
colleague. We want a to-do list that stands on its own, can point at the record the user was working on
(a quotation, a ticket, a repair) and takes the user back there in one click, and has sub-items.

**Decision.** One table, `todo.items`, a crate `tradocraft-todo`, a switchable module `todo` with the
permission `todo.use`, and a page `/todo`.

*Data model* (migration `20270202000001_todo.sql`). `id`, `company_id` (not null), `parent_id` (self
foreign key, `ON DELETE CASCADE`), `position`, `title`, `notes`, `owner_id`, `assignee_id` (nullable),
`created_by`, `due_date` (a date), `done`, `done_at`, `done_by`, the link (`link_kind`, `link_id`,
`link_label`, `link_location`), `reminded_at` (set by the reminder pass, PR 3), `client_id`, timestamps.
- Two levels: a trigger requires the parent to be an item of the same company that is itself a root, and
  forbids an item with sub-items from becoming a sub-item. A sub-item always shares owner and assignee
  with its root; moving an item under another root requires the same owner.
- `UNIQUE (company_id, client_id) WHERE client_id IS NOT NULL` makes a create idempotent: a retried
  `POST` returns the existing item (200, not 201). The id belongs to the company, so a `client_id` held by
  an item the caller cannot see answers 409 and says nothing more.
- Indexes: `(company_id, owner_id, done, due_date)`, the same for the assignee, `(link_kind, link_id)`,
  `(parent_id, position)`.

*The polymorphic link.* `link_kind` is one of a closed list (customer, quotation, order, ticket, repair,
job, production_order, delivery, product, opportunity, purchase_order, goods_receipt, supplier,
supplier_invoice, kb_entry, stock_count), enforced by a `CHECK` and mirrored by the Rust enum `LinkKind`
and, in PR 2, a registry in the app. `CHECK ((link_kind IS NULL) = (link_id IS NULL))`. Trade-offs:
- **No foreign key to the target.** The target lives in another module's table and a to-do must not
  block, or be deleted with, a record. The cost: a link can dangle. The app shows a "target missing"
  state when the jump fails (PR 2); nothing cleans up links.
- **The label is a snapshot** (`link_label`), taken when the link is made, so a list needs no joins into
  eleven modules. It goes stale when the record is renamed; the jump shows the current record.
- **The label is permission-gated.** The snapshot can name a record the viewer may not read (an
  assignee without that module). The API returns `link_label` only to a viewer who holds the read
  permission of the kind (`LinkKind::read_permission`); otherwise it is null and the app shows "Linked
  item". Creating or changing a link needs that same permission (403 otherwise). Permission, not
  existence, is checked at link time: the id is not verified against the target table.
- **Jobs are checked per record.** `field.read` means different things: a technician (`field.work`
  without `field.plan`) sees only the jobs they are assigned to, planners and read-only roles see all
  (`tradocraft_fieldservice::sees_all`). Linking a job therefore needs the right to read *that* job
  (404 otherwise, the same answer as for an unknown id), and a job link is shown to a viewer only if
  they can read that job now. Every other kind is shared master data or a record whose "mine" scopes
  are list filters, not access rules (customers, products, suppliers, opportunities, quotations,
  orders, tickets, repairs, deliveries, production orders: readable by everyone holding the kind's
  read permission; ADR 0049 division membership restricts who works on a production order, not who
  reads it), so the kind-level permission is enough for them. If one of them gets a record-level
  rule, it joins the job check.
- **What a viewer who may not read the link sees.** The item keeps `link_kind` (the app shows "Linked
  item"); `link_id`, `link_label` and `link_location` are omitted, so the viewer cannot reach or
  learn about the record. This holds for a missing kind permission and for an unreadable job alike.
- `link_location` is the app path to jump to (`/quotations/<id>`); the API accepts only paths that start
  with a single `/`, so a stored location can never leave the app.

*Privacy.* A to-do is private to its owner and its assignee, in the active company. There is no company
wide sharing yet; it may come later as a separate rule. Anyone else, including an administrator and a user
of another company, gets 404 (not 403) on every endpoint, and lists never contain the item. The owner is
the creator; the owner may hand a root item to an active colleague of the same company (`assignee_id`,
cascading to its sub-items), take it back, and delete it. The assignee sees, edits, completes and reopens
it, but can neither reassign nor delete (403). `GET /todo/items` has the scopes `mine` (on my plate:
handed to me, or mine and not handed to anyone), `assigned` (mine, handed to a colleague) and `all-mine`.

*Hand-over rule.* Only a root item is handed over. Changing `assignee_id` or `clear_assignee` on an item
that is, or in the same call becomes, a sub-item is 422; with `make_root` it is allowed.

*Reordering.* The listed items take, in the new order, the places the listed items hold in the full
order of their siblings (position, then creation time, then id, the order lists use). Siblings that are
not listed (hidden finished ones) keep their places, equal positions are settled by that order, and the
siblings are renumbered 0..n, so showing hidden items again moves nothing. A repeat of the same order
writes nothing.

*Dates.* `due_date` is a date. The Dart client serialises a `DateTime` with a time part, so the API
reads only the first ten characters (the repo's `serde_util::opt_date`), as the other crates do.

*Lock order.* Every request that changes several rows locks the parent before its sub-items, and
siblings by id: completing a parent locks it, then its open sub-items; reopening, updating (including a
move, whose new parent is locked in the same pass) and reordering lock the parent first, then the
item(s). After locking an item its parent is read again and the pass restarts if it moved (409 after
three tries). A test runs complete, reopen, move and reorder concurrently and checks for deadlocks.

*Completion.* `POST /todo/items/{id}/complete` takes `complete_children`. Completing an item that still
has open sub-items without it answers 409 (code `open_sub_items`); with it, the open sub-items are
completed in the same transaction. The app asks the user first. Reopening a sub-item reopens its done
parent (the invariant is that a done parent has no open sub-item); adding an open sub-item to, or moving
one under, a done parent reopens it too. Reopening a parent leaves its sub-items done. Both operations
are idempotent.

*Module and permission.* `Permission::TodoUse` (`todo.use`) belongs to `Module::Todo` (`todo`), which
requires no other module (a link is checked against the target's own read permission). It is not a
`.read` permission, so the read-only `viewer` role does not get it (`viewer_is_read_only` pins that); the
`integration` service account does not either. Every other role, and admin, has it. Stored disabled
modules list what is off (ADR 0028), so the module is on for every existing company and user and no
backfill migration is needed; a company switches it off in the admin screen like any module.

*Audit.* Every mutation records in its transaction (`core::audit::record`, entity `todo`): created,
updated, completed, reopened, reordered, deleted. Updates use the `Changes` helper for ids, dates and
positions. Titles, notes and link labels are private to the owner and the assignee while the trail is read
by administrators (`audit.view`), so events record *that* the text changed (`text_changed`: `title`, `notes`, `link_label`, `link_location`), never what it
says. Rows are locked with `SELECT .. FOR UPDATE` before they change; related rows are locked parent first.

*Endpoints* (tag `todo`; all need `todo.use`): `GET /todo/items` (filters `scope`, `done`, `link_kind` with
`link_id`, `due_before`; a flat list ordered by parent, then position), `GET /todo/items/counts` (open,
overdue and due today on my plate, root items only since PR 3), `POST /todo/items`, `PATCH /todo/items/{id}` (title, notes, due date,
assignee, move between parents, position, link; `clear_*` flags clear a value), `POST
/todo/items/{id}/complete`, `POST /todo/items/{id}/reopen`, `POST /todo/items/reorder` (an ordered list
of siblings, which take the positions the same items had), `DELETE /todo/items/{id}` (cascades).

*Portal separation.* The customer portal server serves only the portal surface. `/todo` is a staff
route and is absent there; `apps/portal-api/tests/surface.rs` walks the OpenAPI contract and fails if any
staff operation, this one included, answers anything but 404 on the portal server.

*Offline.* To-dos are online only for now: no local queue. The `client_id` makes a create idempotent so a
later queue can retry safely. The Flutter page reloads after every change.

**Consequences.** To-dos get a home of their own with a path back to the work. Cost: dangling links and
stale labels (accepted), a private list that the owner alone can delete, and an audit trail that says
little about content on purpose.

*PR 2: context capture and jump (the app).*
- **Link-kind registry** (`app/lib/features/todo/link_kinds.dart`). For each of the 16 kinds: the route
  template (`/quotations/{id}`, `/helpdesk/{id}`, `/purchase-orders/{id}`, `/stock/counts/{id}`, `/kb/{id}`,
  `/customers/{id}`, ...), the label (the workspace tab labels, singular), an icon and the read permission. The
  permission column mirrors `LinkKind::read_permission` in `crates/todo/src/link.rs`; a unit test reads that Rust
  file and fails when the two drift. Another test checks that every built location is accepted by
  `isDetailLocation` and resolved by `detailScreen`, that `parse(build(kind, id))` round-trips, and that pages
  of a section that are not records (`/helpdesk/answers`, `/jobs/contracts`, `/quotations/new`, ...) parse to null.
- **The location is built, the stored one is a fallback.** A link is opened at the location the registry builds
  from kind and id, so a route rename in the app does not strand old to-dos. `link_location` (stored at link
  time) is used only when the kind has no template or the registry cannot build a route (a kind of a newer
  server), and only if it is a path inside the app (one leading slash).
- **Current context** (`currentContextProvider`): the focused workspace tab's location, else the main area's
  (`WorkspaceNotifier.homeLocation`, kept by the shell), the same recipe as `TutorialHost._located` but not tied to
  the tutorial; the title is `WorkTab.title` (what `TabScope.reportTitle` set), resolved through the registry to an
  optional record (kind, id, label, location). A list or settings page has no object and is not linkable. A
  popup (bottom sheet, menu) opened inside a tab no longer replaces the tab's location (`_TabObserver` tracks
  page routes only).
- **Quick add** replaces the PR 1 dialog: title, optional due date, and a "Link to current screen" switch that is
  on by default when the current screen is linkable (kind icon, label) and off, disabled and explained when it is
  not. Saving sends `link_kind`, `link_id`, `link_label` and `link_location` with a `client_id`. It opens from the
  New to-do button of `/todo`, from Shift+T (ADR 0060; shell layer; needs `todo.use`, and the server drops that
  permission when the module is off) and from the account menu (same gate), so it is always reachable. The
  dialog is modal for shortcuts.
- **The link chip** on `/todo` opens or focuses the record's tab (`context.push`). A link the viewer may not read
  (only `link_kind` came back) shows "Linked item" and is not tappable. "Remove link" in the item menu clears a
  link (`clear_link`).
- **A missing target** has no server-side check. The jump lands on the record's screen, which answers 404:
  the order, quotation, ticket, job and customer screens now show a clear "not found" state with a way back
  (`LoadFailedView`, not a spinner or an error line). The to-do keeps its link until the owner removes it.
- **To-dos for this record** (`ObjectTodosButton`) sits in the headers of quotations, orders, tickets, jobs and
  customers: a button with the count of the caller's own open items for the record (`GET /todo/items?link_kind&link_id&done=false`,
  the privacy rule unchanged: only the caller's items), and a sheet to complete them and add one that is already
  linked. Hidden without `todo.use`.
- **`/customers/:id`** is a workspace detail route (`CustomerScreen`) that loads the customer and shows the same
  form as the list's dialog; the list still opens its dialog.

*PR 3: the badge, reminders and removing a dead link* (migration `20270203000001_todo_reminders.sql`).
- **Counts are roots only.** `GET /todo/items/counts` now counts open root items on my plate (handed to me, or
  mine and not handed on), so the number equals what the page lists by default; sub-items are not counted. The
  response shape (`open`, `overdue`, `due_today`) is unchanged; overdue and due today use the database date
  (`CURRENT_DATE`), as the reminder pass does. Before PR 3 it counted sub-items too; the app did not use it.
- **The shell badge.** The `/todo` destination (rail and narrow bar) shows `open`; it turns red when `overdue > 0`
  and is hidden at zero and without `todo.use` (nothing is requested then). A tap is the normal destination tap.
  It is kept fresh cheaply: one provider on the counts endpoint, invalidated (debounced, 500 ms) after every
  change made in the app (the repository calls back after each create, update, complete, reopen, delete and
  reorder, so link, due date and assignee changes are covered), refreshed every 3 minutes while the app is in
  the foreground, and on resume. It stops when the user signs out. Changes made elsewhere show up at the next
  refresh. The per-record button turns its count badge red when a listed item is overdue.
- **Remove link on "not found".** When a record screen shows its not-found state (HTTP 404, `LoadFailedView`)
  and the caller holds linked to-dos for that kind and id (`GET /todo/items?scope=all-mine&link_kind&link_id`),
  one button "Remove link from my to-dos" clears the link (`PATCH clear_link`) of all of them. Hidden for other
  errors, without linked items and without `todo.use`.
- **Reminder opt-out, on the server.** `todo.user_settings (user_id, company_id, email_reminders default true,
  updated_at)`, primary key `(user_id, company_id)`; no row means on. `GET /todo/settings` and `PUT
  /todo/settings` (both `todo.use`, own row only) back the switch "E-mail reminders" on the page, so the choice
  follows the user to other devices. A change is audited (entity `todo_settings`, entity id the user, data
  `{"email_reminders": bool}` only; an unchanged value writes nothing).
- **Reminder rules** (`tradocraft_todo::send_due_reminders`, one idempotent pass of the worker loop). An item is
  reminded once, when it is open, `due_date <= CURRENT_DATE` and `reminded_at IS NULL`. The recipient is the
  assignee when the item is handed on, else the owner. Done items and sub-items of a done parent are never
  reminded; sub-items of an open parent are, like any item. All of one person's items in one pass make one
  digest mail (one per company when a person works in two). Changing an item's due date resets `reminded_at`
  (a new date is a new deadline); other edits, reopening and handing it over do not.
- **Who is skipped, and the opt-in rule.** Recipients who are inactive, no longer active members of the company,
  lack `todo.use` (role) or have the module off, and recipients who switched reminders off, are skipped and
  their items are left unreminded (`reminded_at` stays NULL). The rule for switching reminders on again is the
  simplest correct one: nothing is marked while opted out, so the next pass reminds the items that are due or
  overdue at that moment, in one digest. A single mail is not a flood, and an item that is still overdue is
  still something to act on; the alternative (marking items at opt-out time) needs a second state and a
  background write for every opt-out.
- **Claiming.** The pass runs in one transaction. It takes a transaction advisory lock (a worker that does not
  get it skips the pass, so a person's items are claimed by one worker and make one digest), selects the due
  rows with `FOR UPDATE OF i SKIP LOCKED` (rows an editor holds are left to the next pass), queues the digests
  with `core::mail::enqueue`, then sets `reminded_at = now()` on the claimed rows, and commits. A crash rolls
  all of it back: nothing is sent twice and no reminder is lost. The permission check (role and modules) is done
  in Rust with `CurrentUser::can`, the same code as the API, not repeated in SQL.
- **Outbound policy (ADR 0048).** The pass only queues mail in `core.mail_outbox`, like every other system mail;
  what happens to it is decided where the outbox is emptied: outside a live environment the worker's transport
  is forced to files, so test and tutorial environments never send a real reminder. The item is claimed when the
  mail is queued, not when it is delivered, so in such an environment the reminder exists as a file and is not
  repeated.
- **The mail.** In the recipient's `core.users.language` (the company's default when empty), in English, German,
  Spanish, French and Dutch. Subject "To-do reminder: N items are due"; the body lists one line per item with
  title, due today or "overdue since DATE" and, only when the recipient may read the linked record (the same
  rule as the API), "about LABEL", and ends with a footer on how to switch reminders off in the app. Notes are
  never included. A title is the owner's content, mailed to the owner (or to the person it was handed to).
- **Worker.** The pass runs once per loop next to the other passes, errors are logged and do not stop the loop.
  It is not part of the heartbeat (ADR 0052 records liveness of the loop, not per-pass results); a stopped
  worker is announced by the heartbeat as before, and reminders resume when it runs again.
- **Not done.** An overdue and due-today section on the page (the badge and the existing due-date display
  carry it); a time of day for reminders (the digest goes out in the first pass of the day the item is due,
  by database date).

**Follow-ups.**
- PR 2 and PR 3: done (see above).
- Later: company-wide sharing, comments on an item, an offline queue.
