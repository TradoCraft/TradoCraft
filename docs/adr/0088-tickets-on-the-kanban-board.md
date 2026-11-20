# 0088 — Tickets on the kanban board and a status endpoint

**Status:** Accepted (UI framework phase 5; second use of the generic board of
[ADR 0087](0087-generic-kanban-view.md); status rules from [ADR 0017](0017-helpdesk-sla-teams-attachments.md),
[ADR 0021](0021-helpdesk-business-hours-automation-reporting.md) and
[ADR 0073](0073-concurrent-edit-protection.md))

**Context.** The ticket list is the working queue of support, and a ticket's status is the thing
people change most. Today that means opening the ticket, changing the status and saving the whole
form. The only API for it is `PUT /tickets/{id}`, which replaces subject, priority, category,
language, owner, customer, contact and links together with the status. A board that moved a
ticket through it would have to re-send all of those, and a drop would overwrite whatever a
colleague had just changed in those fields.

**Decision.**

*Backend: `POST /tickets/{id}/status {status, expected_version?}`.* A status change and nothing
else, returning the ticket detail. It goes through the same `change_status` as everything else
that sets a status (a reply, a note, a split-off ticket), so it has the same effects:
- the automation rules for "updated" run, the SLA is recalculated (resolution pauses and resumes
  with the status), and a `status` timeline event is written (ADR 0023); the audit trail gets
  `status_changed {from, to}`; a live event is published as for any save (ADR 0075);
- **closing** is refused with 409 `checklist_incomplete` while the team requires a finished
  checklist, and queues the customer's satisfaction survey, once per ticket (ADR 0017);
  reopening clears the closing time;
- the same status again changes nothing (no write, no event, no new version);
- `expected_version` is optional and follows ADR 0073: given, a ticket that has moved on is
  refused (409 `record_changed`). Needs `helpdesk.write`; another company's ticket is 404.

*App: a List | Board switch on the tickets page.* One column per status (new, open, waiting for
customer, waiting for us, closed), loaded with the existing `GET /tickets?status=` (50 per
column, the server's order: priority, then last update). The board has its own search and the
list's "my tickets / unassigned / all" switch (my tickets by default, as on the list). A card
shows the number, the priority when it is high or urgent, an escalation mark, an unread dot, the
subject, the customer or contact, the SLA state, the checklist progress and the owner.
- **Moving** posts the status and **leaves out the version**. A board move is a status and
  nothing else, so a colleague's edits to other fields must not make it fail; the server still
  refuses what it must (the close gate, and its message is shown on the board).
- **Closing asks first.** Closing can send the customer a survey, which cannot be taken back, and a
  drop is easy to make by mistake. Moving a card to *closed* opens a confirmation; backing out
  puts the card back without an error. Moving out of *closed* (reopening) asks nothing.
- **"+"** on every column except closed opens the existing new-ticket dialog (a call, a visit or
  an internal question; mail tickets arrive by themselves) and then moves the new ticket into
  that column when it is not the one the server chose.
- A new language or new user rights reach a board that is already open without reloading its
  cards (as on the opportunity board).

**Consequences.**
- A second entity needed one config, one page switch and one small endpoint, with no change to the
  generic view. That is the evidence the config of ADR 0087 is the right size.
- Because a board move carries no version, two people moving the same ticket is last writer wins;
  the timeline shows both moves.
- The board does not show colleagues' changes until it reloads (ADR 0087). The ticket's live
  channel (ADR 0075) is per ticket and does not help a list.
- Filters beyond owner and search (team, tag, SLA, unread, escalated) stay on the list.

**Not yet.** Team, tag and SLA filters on the board; cards coloured by SLA; moving by dragging
within a column to set an order; swimlanes by owner or team; live updates.
