# 0086 — Generic chatter, followers and activities

**Status:** Accepted (in implementation) (UI framework phase 4; builds on [ADR 0023](0023-helpdesk-collaboration.md),
[ADR 0059](0059-audit-trail-viewer.md), [ADR 0061](0061-todo-items.md),
[ADR 0073](0073-concurrent-edit-protection.md), [ADR 0075](0075-helpdesk-live-ticket-updates.md)
and [ADR 0085](0085-generic-form-view.md))

**Context.** The generic form view (ADR 0085) deferred "chatter beside the sheet". Only tickets
have a conversation, followers and a timeline today, and all of it is ticket-specific:
`helpdesk.articles`, `ticket_events`, `ticket_watchers`, `ticket_reads`, `ticket_attachments`. The
other record screens have three separate, narrower things:

- **History** is `audit.events` (ADR 0059). It is complete and written in every business
  transaction, but it needs `audit.view` (administrators), holds raw `{"changes": …}` JSON and
  has no author-written text.
- **To-dos** (`todo.items`, ADR 0061) are *private* lists of one user, with an optional
  polymorphic link to a record. A colleague who opens the record sees nothing of them.
- **Attachments** exist for tickets and field jobs only (`core.files`, ADR 0015).

People cannot leave a note on a quotation, see who follows an order, schedule "call back on
Friday" for a colleague where everyone working on the record sees it, or read a short, readable
history of a customer without being an administrator. Phase 4 adds that for every record kind.

**Decision.** A new schema `chatter` and a crate `tradocraft-chatter`, always on (not a
switchable module: it is part of every record screen, and the records themselves are already
gated by their own module). Three concepts, one polymorphic address `(record_kind, record_id)`.

*Address.* `record_kind` is a closed list, a Rust enum `RecordKind` mirrored by a `CHECK` and by
the app's registry, using the same names as the to-do link (`customer`, `quotation`, `order`,
`ticket`, …; the enum is shared, not duplicated). As in ADR 0061 there is **no foreign key** to
the target: it lives in another module's table. Instead each kind registers, in one place
(`RecordKind::info`), four things: the read permission, the write permission, a `visible(conn,
company_id, id)` check that the record exists in the caller's company, and a label function for
notifications. Every chatter endpoint first runs `visible` and answers 404 otherwise, so another
company's ids and deleted records say nothing.

*Permissions.* Reading the chatter of a record needs the kind's **read** permission. Posting a
note, scheduling or completing an activity, and adding *another* user as follower need its
**write** permission. Following yourself needs read only. Nothing in the chatter is ever visible
to the customer or the portal; customer-facing mail stays in the helpdesk.

*Data model* (migration `<date>_chatter.sql`; every table has `company_id` and every query
filters on the caller's company):

- `chatter.messages`: `id`, `company_id`, `record_kind`, `record_id`, `kind`
  (`note` | `system`), `author_user_id` (empty for `system` written by the worker),
  `body` (plain text, at most 10 000 characters, may be empty for `system`), `changes jsonb`
  (the tracked fields of a `system` message: `[{"field","label_key","from","to"}]`, labels are
  translation keys, never text), `client_id` (idempotent create, same rule as ADR 0061),
  `created_at`, `edited_at`. Indexes `(company_id, record_kind, record_id, id DESC)` for the thread
  (message ids are time ordered, so they are also the paging cursor) and `(…, created_at)` for the
  unread query.
  A note can be edited and deleted by its author for 15 minutes; `system` messages never. Deleting
  leaves nothing behind (no tombstone); the audit trail still has the change.
- `chatter.message_files`: `(file_id → core.files, message_id → chatter.messages ON DELETE CASCADE)`.
  Files go through the existing `core::files` sniffing and size limit (12 MB; images and PDF) and
  are uploaded first, then linked when the note is posted, exactly like `ticket_attachments`.
- `chatter.followers`: `(company_id, record_kind, record_id, user_id)` primary key, `reason`
  (`manual` | `author` | `assigned` | `mentioned`), `muted_at` (an explicit unfollow is honoured
  until the user acts on the record again, as in ADR 0023), `last_read_at`. Automatic followers:
  whoever posts a note or is assigned an activity.
- `chatter.activities`: `id`, `company_id`, `record_kind`, `record_id`, `kind` (`todo` | `call` |
  `email` | `meeting`; a closed list, extendable by migration; companies cannot define types in
  this step), `summary`, `note`, `assignee_id`, `due_date` (a date), `created_by`, `done_at`,
  `done_by`, `done_note`, `client_id`. Indexes `(company_id, assignee_id, done_at, due_date)` and
  `(company_id, record_kind, record_id)`.

*Activities are not to-dos.* A to-do item is private to its owner and assignee; an activity is
visible to everyone who can read the record, belongs to the record, and is *done* with an
optional closing note that becomes a `system` message ("Call · done by Jo: spoke to …"). They
stay two tables because merging them would make either the privacy rule or the "visible on the
record" rule conditional. To avoid two places to look, the to-do page and its badge **are planned**
to include the user's open assigned activities as a read-only group, and an activity could be
turned into a private to-do with one action. Reminder mail for activities (ADR 0061 PR 3) is
planned the same way. None of this exists yet: today an assigned activity reaches its assignee
through the notifications centre (`GET /chatter/inbox`) and the assignment mail.

*Change log (`system` messages).* The audit trail stays the complete, administrator-only record
(ADR 0059) and is **not** replaced. Chatter shows a *curated* subset that anyone with read
access may see: each kind declares its **tracked fields** (for a quotation: status, customer,
total, valid-until; for a customer: name, language, VAT number, active; …). A handler that
already calls `audit::record` calls `chatter::track(conn, user, kind, id, &changes)` next to it,
in the same transaction, passing only the changed tracked fields; one `system` message per save.
Values are stored as display-neutral strings or ids; the app resolves ids to names it is allowed
to read, and shows a plain "changed" for a field it cannot resolve. Untracked fields, money
details and anything a read-only user should not learn are simply not in the list.

*API* (OpenAPI and the Dart client are generated as usual, ADR 0005). Everything about one
record is under `/api/v1/chatter/{kind}/{id}`; a single note or activity is addressed by its own
id under `/api/v1/chatter/notes/{id}` and `/api/v1/chatter/activities/{id}`:

- `GET …/thread?before_id=&limit=` the feed of notes and change messages **newest first** (a
  completed activity appears in it as a message), paged by message id: pass the returned
  `next_before_id` as `before_id` for the next, older page (no totals). `POST …/notes
  {body, file_ids?, client_id?}`; `PATCH`/`DELETE /chatter/notes/{id}` (own note, 15 minutes;
  `PATCH` takes `{body}` only, files cannot be added afterwards).
- `GET …/activities` lists the **open** activities of the record (a completed one leaves the list
  and is in the thread); `POST …/activities`; `POST /chatter/activities/{id}/done {note?}`;
  `PATCH`/`DELETE /chatter/activities/{id}` (creator or assignee). An assignee must be an active
  colleague who may read the record.
- `POST …/files` and `GET …/files/{file_id}` (see *Files*).
- `GET …/followers`; `PUT`/`DELETE …/follow` (yourself); `POST …/followers {user_id}` and
  `DELETE …/followers/{user_id}` (write permission; the user must be able to read the record).
- `POST …/read` sets `last_read_at`; `GET /chatter/inbox` returns the records with something new
  for the caller (followed records only) and the activities due, for the notifications centre.

*Live updates.* Each mutation publishes a `RecordEvent` after the commit on the existing channel
(ADR 0073, 0075) with `entity_type` = the record kind, new kinds `chatter_note`,
`chatter_activity`, `chatter_followers`, and **without moving the record `version`**, so an open
form is never made stale by a note. The app's chatter panel subscribes through the form
controller that already holds the subscription and reloads only the thread.

*Notifications.* In-app only in this step: the notifications centre (ADR 0080) merges a server
feed (`GET /chatter/inbox`) of (a) the user's open activities due today or earlier and (b)
followed records with messages by others since `last_read_at`. No mail on a note; assignment of an activity
to someone else sends the same single plain mail as an escalation (ADR 0023: user's language,
one per assignee and record per 10 minutes). Mentions (`@name`) are **not** part of this step.

*App.* `lib/framework/components/chatter/` holds `ChatterPanel(kind, id)` (composer, feed,
attachments), `ActivityPanel` (open activities above the feed, schedule dialog, mark done),
`FollowerBar` and a `ChatterRepository` (ADR 0078). `RecordFormView` gets an optional `chatter`
slot, shown beside the sheet on wide layouts and below it on narrow ones, hidden on new
unsaved records. Customers and quotations adopt it first (ADR 0085 already moved them). The
panel is permission-aware (no composer without write permission) and follows the keyboard
conventions of the list and form views (focusable feed, Ctrl+Enter posts).

*Helpdesk.* **Tickets are not migrated in this step.** The ticket screen keeps its conversation,
timeline, watchers and presence (ADR 0023, 0075): they carry mail delivery, SLA and customer
visibility that a generic note does not. The generic panel is *not* shown on tickets, to avoid
two histories on one screen. A later step may expose the ticket's internal notes and events
through the same read endpoints (a `kind = 'ticket'` adapter) and then decide about the rest.

**Consequences.**

- Any record screen gets a readable history, notes, followers and activities by passing a kind
  and an id; a new kind is one enum variant, one `CHECK` value and a tracked-field list.
- The polymorphic address cannot be enforced by the database: a deleted record leaves orphaned
  rows. An hourly pass in the worker removes the rows of records that no longer exist (see
  *Clean-up*); records that are only archived keep theirs.
- Change messages duplicate a small part of `audit.events` on purpose: the audit trail is the
  evidence, the chatter is the story. The cost is one extra insert per tracked save.
- `RecordEvent` consumers that assumed every event moves the version already filter by kind
  (ADR 0075); the new kinds join the list that does not.
- The in-process hub does not reach the worker, so notes or activities created by the worker
  (reminders) appear on the next load, as with ticket mail (ADR 0075).
- Following is per user and company; leaving a company drops nothing, the rows are filtered by
  the active company.

**Delivered.** The backend (notes with file attachments, followers, activities that can be
edited and handed over, inbox, live events); change messages for customers (tracked fields:
name, VAT number and regime, e-mail, phone, language, active, discount), quotations (customer
name, quote date, valid until, total, purpose, delivery country) and orders (total, customer
reference, delivery country, purpose), written with `chatter::track` next to the audit event;
lifecycle messages written with `chatter::log` (quotation status, order confirmed, sent, revised
and cancelled with its reason, opportunity stage with the lost reason); the mail to a new
assignee of an activity; a worker pass that removes rows of deleted records; and the app panel
(`ChatterPanel`) on the customer and quotation forms and on the order and opportunity screens,
plus the notifications centre entries. The panel sits beside the sheet on wide forms that opt in
(customers) and below it where the sheet needs the width (quotations, whose line editor is
wide). A chatter event never shows the "someone else saved" banner: the form controller (or the
screen, for orders and opportunities) hands it to the panel (`ChatterTick`).

*Files.* `POST /chatter/{kind}/{id}/files` stores a JPEG, PNG, WebP or PDF (at most 12 MB, by
signature, through `core::files`) as a pending upload of the caller; `file_ids` on the note links
up to ten pending uploads of the caller on that record; a file is on one note only. Until linked,
only its uploader can download it; afterwards everyone who can read the record can, through
`GET /chatter/{kind}/{id}/files/{file_id}`, and only through the record it belongs to. Deleting a
note removes the link. A retried upload (same `client_id`) may only meet its own earlier upload:
a file id that exists for any other reason is refused with 409 and never adopted. Downloads are
sent with `Cache-Control: private, no-store`. Pending uploads older than a day are dropped by the
worker pass, which also deletes the `core.files` row of a file no other table references (the
referencing tables are read from the catalog); the blob goes with the blob sweep.

*Assignment mail.* Scheduling an activity for somebody else, or handing one over, queues one
plain mail in the assignee's language (record, kind, summary, due date). At most one per
assignee and record per ten minutes (`chatter.followers.last_notified_at`, claimed in the same
transaction as the mail); never to oneself. Notes do not send mail.

*Clean-up.* `chatter::remove_orphans` runs in the worker's hourly sweep and deletes messages,
activities, followers and file links whose record no longer exists, and pending uploads older
than a day.

Still to follow: field-level messages for the fields of quotation and order lines, attachments
on activities, and live updates of the opportunity record itself (it has no row version, so the
screen only reacts to the chatter).

**Not yet.** Mentions and mail on notes; activity types defined per company; recurring
activities; editing history of notes; reactions and threads; rich text and inline images;
attachments on activities; calendar view of activities (UI framework phase 5); email-in to a
record; migrating tickets, orders-from-tickets and field jobs onto the generic panel; a
server-side unread count on lists.

**Decided.**

1. Posting a note, scheduling or completing an activity and adding another follower need the
   kind's **write** permission; reading and following oneself need **read**.
2. To-dos and chatter share one `RecordKind` list.
3. The first cut supports `customer`, `quotation`, `order` and `opportunity` only. The enum and
   the `CHECK` list exactly these four; more kinds are one variant and one migration each.
