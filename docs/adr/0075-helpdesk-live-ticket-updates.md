# 0075 — Helpdesk immediate change notification

**Status:** Accepted (roadmap item A8)

**Context.** D3 ([ADR 0073](0073-concurrent-edit-protection.md)) added a row version and a shared
Server-Sent Events (SSE) channel, and the ticket screen already warned "updated by X, reload" when a
colleague saved. That left four gaps for tickets:

1. Only a property save and a few notes published an event. A tag, a time entry, an attachment, a
   checklist item, an escalation, a hand-over, a merge or a split changed the ticket without the open
   screens hearing about it.
2. The only reaction was a banner and a Reload button. The conversation did not move, and a reload
   threw away the user's unsaved property edits.
3. A colleague arriving at the ticket or starting to reply showed up at the next presence beat, up to
   20 seconds later (ADR 0023).
4. A save refused with 409 gave the same "reload" dead end instead of showing what the other person
   changed.

**Decision.** Reuse the ADR 0073 channel and endpoint unchanged; publish more event kinds, and make
the ticket screen act on them. No new endpoint, no migration, no change to the OpenAPI document or the
Dart client.

*Backend.*
* `helpdesk::tickets::notify_change` publishes a `RecordEvent` for a ticket after the commit. It reads
  the version the commit left behind and never fails the request. Every ticket mutation that did not
  publish now does: escalate (`escalated`), delegate (`delegated`), tags (`tag`), time entries
  (`time`), merge (`merge`, for both tickets), split (`split`), attachments (`attachment`) and the four
  checklist mutations (`checklist`). A save now carries the new status as its summary.
* Presence is pushed as kind `presence` (summary: `viewing` or `replying`). `POST /tickets/{id}/presence`
  publishes only when the caller was not present within the presence window or changed mode, so the
  20-second heartbeat of someone who just keeps the ticket open is silent.
* Only a save or a note moves the ticket `version`. The other kinds leave it as it was on purpose:
  bumping it for a tag would make every property form that is open on that ticket stale. The client
  therefore filters stale events by version only for the kinds that always carry a new one
  (`updated`, `note`, `resync`, see `isVersionedChange`).
* Mail that arrives through the worker (a customer's reply) is not published: the worker is another
  process and the hub is in-process, as noted in ADR 0073. The API's own `inbound` path is unchanged.

*App (`TicketScreen`).* On an event from someone else:
* `presence`: reload the "who is here" list at once.
* Anything else: fetch the ticket and bring the conversation up to date, then lay the server's
  properties over the form with a per-field three-way merge (`ticket_merge.dart`): *base* is the ticket
  as the form was built, *mine* the form now, *theirs* the server.
  * the user changed nothing: the form is replaced, and a one-line notice says what happened ("Jo
    added a message.");
  * only the colleague changed a field: taken over; only the user changed it, or both changed it to
    the same value: kept;
  * both changed the same field differently: a **Compare** button opens a side-by-side dialog (mine,
    theirs, per field). Until the user decides, the ticket stays at the old version, so saving still
    goes through the 409 check and cannot overwrite the colleague's change. Cancelling changes nothing.
* After a merge the form shows the user's surviving edits on top of the current version, so the next
  save sends the current `expected_version` and is accepted.
* A save refused with 409 `record_changed` goes through the same path instead of ending in a reload.
* The composer (a reply or note being written) is never touched by a refresh.
* Events that arrive during a refresh are folded into one more refresh.

**Not done (follow-ups).**
* Live updates of knowledge base articles. On a ticket, the conversation, presence, activity
  timeline, time entries and checklist all reload when a colleague changes something.
* Contact link, quotation and opportunity conflicts show as ids when the name is not known to the
  screen (they show names for the ones the screen has loaded).
* Events for mail ingested by the worker (needs a database `LISTEN/NOTIFY` bridge, which would also
  make the hub work across several API instances).
