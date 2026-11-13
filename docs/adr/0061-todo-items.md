# 0061 — To-do items

**Status:** Accepted (PR 1 of 3: backend and a minimal page; context capture, the jump and reminders follow)

**Context.** The only list of things to do is `field.job_tasks`, the checklist of one field job. People
keep their own to-dos elsewhere, away from the records the to-dos are about, and cannot hand one to a
colleague. We want a to-do list that stands on its own, can point at the record the user was working on
(a quotation, a ticket, a repair) and takes the user back there in one click, and has sub-items.

**Decision.** One table, `todo.items`, a crate `tradocraft-todo`, a switchable module `todo` with the
permission `todo.use`, and a page `/todo`.

*Data model* (migration `20270202000001_todo.sql`). `id`, `company_id` (not null), `parent_id` (self
foreign key, `ON DELETE CASCADE`), `position`, `title`, `notes`, `owner_id`, `assignee_id` (nullable),
`created_by`, `due_date` (a date), `done`, `done_at`, `done_by`, the link (`link_kind`, `link_id`,
`link_label`, `link_location`), `reminded_at` (unused until PR 3), `client_id`, timestamps.
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
- `link_location` is the app path to jump to (`/quotations/<id>`); the API accepts only paths that start
  with a single `/`, so a stored location can never leave the app.

*Privacy.* A to-do is private to its owner and its assignee, in the active company. There is no company
wide sharing yet; it may come later as a separate rule. Anyone else, including an administrator and a user
of another company, gets 404 (not 403) on every endpoint, and lists never contain the item. The owner is
the creator; the owner may hand a root item to an active colleague of the same company (`assignee_id`,
cascading to its sub-items), take it back, and delete it. The assignee sees, edits, completes and reopens
it, but can neither reassign nor delete (403). `GET /todo/items` has the scopes `mine` (on my plate:
handed to me, or mine and not handed to anyone), `assigned` (mine, handed to a colleague) and `all-mine`.

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
by administrators (`audit.view`), so events record *that* the text changed (`text_changed`), never what it
says. Rows are locked with `SELECT .. FOR UPDATE` before they change; related rows are locked parent first.

*Endpoints* (tag `todo`; all need `todo.use`): `GET /todo/items` (filters `scope`, `done`, `link_kind` with
`link_id`, `due_before`; a flat list ordered by parent, then position), `GET /todo/items/counts` (open,
overdue and due today on my plate), `POST /todo/items`, `PATCH /todo/items/{id}` (title, notes, due date,
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

**Follow-ups.**
- PR 2: link-kind registry beside `detail_routes.dart` (a test that every kind resolves), a current-context
  provider, a quick-add dialog with "link to current screen", the link chip that jumps, a "to-dos for this
  object" chip on quotations, orders, tickets and jobs, and the `/customers/:id` route.
- PR 3: count badge on the shell, an overdue and due-today section, and a worker pass that claims
  `reminded_at` idempotently and mails the recipient in their language, respecting the outbound policy and
  a per-user opt-out.
- Later: company-wide sharing, comments on an item, an offline queue.
