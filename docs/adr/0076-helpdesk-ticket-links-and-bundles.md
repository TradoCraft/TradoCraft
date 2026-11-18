# 0076 — Helpdesk ticket links and bundles

**Status:** Accepted (roadmap item A9)

**Context.** Merge ([ADR 0017](0017-helpdesk-sla-teams-attachments.md)) and split
([ADR 0021](0021-helpdesk-business-hours-automation-reporting.md)) exist, but both change what a ticket
*is*. Support often needs the opposite: tickets that stay separate because they belong to different
customers, yet belong together. One outage produces a ticket per customer; a customer writes twice
about the same fault; two tickets concern the same machine. Agents need to see the connection from
either ticket, judge the group at a glance, and answer all of it once.

**Decision.** A link table with three kinds, shown on both tickets, and a bundle mass update that is
previewed before it is applied.

*Data (`helpdesk.ticket_links`, migration `20270221000001`).* One row per link: `kind`, `source_id`,
`target_id`, `company_id`.
* `bundle`: source is the parent, target the child.
* `related`: symmetric, stored once with `source_id < target_id`.
* `duplicate`: source is the duplicate, target the original.

Rules enforced by unique indexes and checked in the API for a readable 409:
* any two tickets are linked at most once, whatever the kind;
* a child has one parent; a parent is never a child; a bundle is therefore a star, one level deep.
  Deeper trees were considered and left out: "one outage, many customers" does not need them, and a
  mass update over a tree needs rules (which level, what order) that nobody asked for;
* a duplicate has one original, and an original is never itself a duplicate;
* a ticket that was merged into another one cannot be linked, and merging a ticket removes its links
  (the notes written when the links were made stay in the other tickets' history).

*API (all under `/tickets/{id}`).* `GET /links` returns the links grouped by how the ticket stands to
the other (`parent`, `children`, `related`, `duplicate_of`, `duplicates`), each with the other
ticket's status, priority, customer, owner and whether it was merged, which is what the bundle's state
at a glance is made of. `POST /links` takes a `target_id` and a `relation` seen from this ticket
(`child`, `parent`, `related`, `duplicate_of`, `duplicated_by`). `DELETE /links/{link_id}` works from
either side. Reading needs `helpdesk.read`, changing needs `helpdesk.write`. Both tickets get an
internal note and an audit event (`linked`, `unlinked`), and an open ticket screen is told through the
live channel of [ADR 0075](0075-helpdesk-live-ticket-updates.md) (kind `links`). A link does not move the
ticket `version` (like a tag), so it never makes an open property form stale.

*Bundle mass update (`POST /tickets/{id}/bundle/update`).* One action for every child of the bundle, or
a chosen subset: a customer **reply**, an internal **note**, or a **status** change. The action is
the code of the ordinary endpoint: `queue_reply`, `post_note` and `change_status` were lifted out of
the handlers into `pub(crate)` functions that run in the caller's transaction, so a bundle reply goes
through the same mailbox choice, threading, automation rules and close gate as a reply written by hand.

* **Each child has a transaction of its own.** A child that refuses (no recipient, an incomplete
  checklist on a team that requires it) is reported as `failed` with the reason and does not stop the
  others. A child that was merged away, or is already in the requested status, is `skipped`.
* **The preview is the real action, rolled back.** With `dry_run` every child's transaction is
  rolled back instead of committed, so the result lists exactly what would happen, including who
  would get the mail and what would be refused, without a second implementation of the rules that
  could disagree with the first. Nothing is published to the live channel and no audit event is
  written for a preview.
* An applied update writes an audit event (`bundle_update`) on each child, a note on the parent
  saying what was done and to how many, and publishes to each ticket.
* A reply needs `helpdesk.reply` as well as `helpdesk.write`.
* Every child gets the same text. Greeting and language per customer (a template with placeholders,
  A6) is a follow-up.

*App.* `TicketLinksCard` in the ticket's side panel lists the links, with the bundle's progress
("2 of 5 still open"), opens the other ticket on tap, adds links (relation, then a ticket from a
searchable list) and removes them. On a parent, **Update bundle** opens a dialog: action, text, status;
**Preview** shows each ticket with where the mail would go and what is refused; unticking a ticket
leaves it out; **Apply** sends only the ticked ones.

**Not done (follow-ups).**
* A link badge and a "bundles" filter in the ticket list; a bundle shown on the customer.
* Per-customer greeting and language in a bundle reply (templates, A6).
* Closing the parent offered to the children, and automation rules that react to a link.
* Mail ingested by the worker (a customer replying) does not suggest linking to an open bundle.
* Deeper bundles (a tree), if a use for them appears.
