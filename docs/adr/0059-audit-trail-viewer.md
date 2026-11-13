# 0059 — Audit trail viewer

**Status:** Accepted

**Context.** `audit.events` has been written in the transaction of every business change since the
first migration (ADR 0007, `core::audit::record`; some 200 call sites). Nothing could read it: no
endpoint, no screen. "Who changed this customer's discount?" meant a database session. Roadmap item D6.

What the table holds is whatever each module chose to put in `data`. Most modules record the action and
an identifier; few record what changed. A viewer shows that faithfully, and is only as good as the events.

**Decision.** Read-only endpoints for administrators, an Admin tab and a History button, and field-level
changes for the two entities whose update paths this work already touched.

*Permission.* `audit.view`, held by `admin` only. It is named `.view` and not `.read` on purpose: every
`.read` permission belongs to the read-only viewer role (`viewer_is_read_only` pins that), and the viewer
must not see the trail. The trail holds what every module chose to record, which can include values a role may not
read on the record itself, so it cannot be opened to the people who can read each record until every
entity has a rule for which of its fields they may see. A company that wants a non-admin auditor
adds a role; nothing else changes. It is not a module: no company can switch the viewer off
(`ALWAYS_ON`, like user administration).

*Endpoints* (tag `audit`):
- `GET /audit/events`: the company-wide trail, filters `entity`, `entity_id`, `action`, `user_id`,
  `from` (inclusive), `to` (exclusive), page size `limit` (50, at most 200).
- `GET /audit/records/{entity}/{id}`: the history of one record.
- `GET /audit/facets`: the kinds of record that have events, for the filter.

An event is `{id, occurred_at, user_id, user_name, user_email, entity, entity_id, action, data}`. An event
with no staff user (a customer acting in the portal, a background job) has no user fields and says who
acted in `data`; the app shows it as "System".

*Scope.* Always the active company: `WHERE company_id = $1`. Events without a company would never be
shown to anyone (there are none today); another company's events on the same record id are not shown.

*Paging by cursor.* Newest first by `id` (a sequence that grows with time), a page at a time with
`before_id`; the answer carries `next_before_id` while there is more. No total: counting a table that
grows with every transaction gets slower every month, and a deep `OFFSET` reads everything it skips.
The primary key already serves "newest first within the company" (it walks backwards and stops after one
page); a single record's history uses the existing `(entity, entity_id)` index. One index is new,
`(company_id, entity, id DESC)`, for the list of kinds of record, which walks it entity by entity: 0.2 ms
on half a million events against 54 ms for a `DISTINCT`. (A second index for the plain company-wide page
was tried and dropped: the planner did not need it, in an even or in a skewed table, and every index
taxes every business transaction.)

*What changed.* `core::audit::Changes` collects, for an update, the fields that differ as
`{"changes": {"field": {"from": .., "to": ..}}}`; a save that changed nothing records `{}`. Customer
updates (15 fields, including the commercial terms of the active company) and supplier updates (11
fields, next to the keys the event already had) now record it. Other modules adopt it by calling
`Changes::new().field(..)` where they record an update.

*App.* Administration gets an "Audit trail" tab for users with `audit.view`: filters by kind of record,
action and period, one tile per event, older events on request. Customer and supplier screens get a
"History" button (customer form, supplier detail) for the same users, showing that record's events.
Changed fields read `name: Acme -> Acme NV`; other recorded values are shown as written.

**Alternatives.**
- *Per-record history for anyone who can read the record.* The obvious reading of "a permission-gated
  history per record". It needs a rule per entity for which of its recorded fields a role may see,
  and the events do not follow one shape. A leak of cost or a note is worse than an admin-only first
  version that can be widened.
- *A total count and `OFFSET` paging, like the lists.* Consistent with the other lists, but the
  audit table is the one that grows without bound.
- *Triggers that diff every row change.* Complete, but it records every column change of every table,
  including the ones that are not business events, and it cannot know the user of the application.
  The modules already say what is business-significant.
- *Changing every `audit::record` caller now.* About 200 sites; the viewer needs to exist first, and
  each module knows its own fields. The helper makes it a small change per module.

**Consequences.**
- Most "updated" events outside customers and suppliers still show only the action and whatever the
  module recorded. The viewer makes that visible, which is a reason to adopt `Changes` module by module.
- No user filter in the app yet (the API has `user_id`); the person is on every tile.
- No export and no retention rule: the trail is kept as it is today. A retention policy would be its
  own decision (and the backup runbook, ADR 0056, covers the table like any other).
- Identity provider events belong to the company of the administrator who made them
  (installation-level changes have no company of their own), so they appear in that company's trail.
- Reading the trail is not itself audited.
