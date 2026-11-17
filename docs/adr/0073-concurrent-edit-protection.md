# 0073 — Concurrent-edit protection and shared live-events channel

**Status:** Accepted (customers, quotations, orders, tickets, shared SSE channel, and Flutter screens)

**Context.** Updates carried no version check, so two people who opened the same customer, quotation,
order or ticket and saved one after the other overwrote each other without a warning: the second save
replaced the first person's changes with a form built from older data. Roadmap item D3, and the
shared push channel for A8.

Delivery notes already had a check (ADR 0035): the note carries `updated_at`, the app sends it back as
`expected_updated_at`, and a stale value is a 409 `delivery_note_changed`. That is the pattern to extend,
with two changes explained below, plus a shared Server-Sent Events (SSE) push channel so open screens
notice external changes immediately.

**Decision.** Optimistic concurrency on a row version, paired with a shared SSE push channel.

*Why not an edit lock.* A lock that shows who has the record open needs somewhere to keep it (a table
with expiry, or session state), a heartbeat from every open form, a way out when someone closes a
laptop or loses the connection, and an administrator override for the lock that never expires. It also
only works for people using the app: a script, an import or the portal ignores it. A version check is
enforced where the write happens, needs no state beyond the row, and cannot be left behind. Showing
who else has a ticket open is already handled by soft presence (ADR 0023).

*Why a counter and not `updated_at`.* Two reasons found while reading the code.
1. `updated_at` is not set by every `UPDATE` (several status and totals updates leave it alone), so
   a change could go unnoticed. A trigger that raises a counter on every update of the row cannot be
   forgotten by a new statement.
2. The app also runs on the web, where a Dart `DateTime` keeps milliseconds. PostgreSQL stores
   microseconds, so a timestamp that went through the app would compare unequal to the stored one
   and refuse a save that was not stale. An integer round-trips exactly.

*What changed (optimistic concurrency).*
* Migration `20270219000002_record_versions.sql`: `version bigint NOT NULL DEFAULT 1` on
  `crm.customers`, `sales.quotations`, `sales.orders` and `helpdesk.tickets`, and one trigger
  function, `core.bump_row_version()`, that raises it on every update of the row. Adding the column
  does not rewrite the tables.
* The read models (`Customer`, `Quotation`, `Order` at its top level, and `Ticket`) return `version`.
* The update inputs (`CustomerInput`, `QuotationInput`, `OrderEditInput`, `TicketInput`) take an
  optional `expected_version`. The check runs after the row is locked (`FOR UPDATE`) and before
  anything is written, in `core::concurrency::check_version`. A stale value is a **409** with code
  `record_changed` and a message naming the record. Two saves from the same version therefore give one
  success and one 409: the second waits for the lock, then finds the version moved on.
* **The field is optional.** A save without it is not checked, as before. Scripts, the CSV customer
  import and the configurator's re-import keep overwriting on purpose. The app sends it on every save.
* A refused save changes nothing, and the version only moves on a real write.
* Delivery notes keep `expected_updated_at` for now; they work and have a test. They can move to the
  counter when a note is next touched.

*What changed (shared SSE push channel).*
* `core::live_events::LiveEvents` holds an in-process `tokio::sync::broadcast` hub in `AppState`,
  publishing a `RecordEvent` (`entity_type`, `record_id`, `version`, `changed_by_id`,
  `changed_by_name`, `kind`, `summary`, `at`) after a transaction commits.
* `GET /api/v1/events/records?entity_type=...&record_id=...` checks the caller's read permission for
  that entity type, filters events by `company_id`, `entity_type` and `record_id`, and streams
  `record_changed` SSE events with a 20-second keep-alive. A8 reuses this same channel for live
  ticket updates (notes, replies, status changes).

*What changed (Flutter app).*
* `RecordLiveWatcher` / `watchRecordChanges` (`app/lib/shared/live_record_watcher.dart`) connects to
  the SSE endpoint via Dio's `ResponseType.stream` while a customer, quotation, order or ticket screen
  is open. When another user updates the record, `RecordConflictBanner` warns the user and offers a
  one-click Reload.
* Customer, quotation, order and ticket save calls send `expected_version`. On a `409 record_changed`
  response, the screen preserves the user's unsaved edits and shows `RecordConflictBanner` with a
  Reload action.

**Not done here (follow-ups).**
* **Other records.** Suppliers, products, contacts, opportunities and the rest can adopt the same
  recipe: migration (column and trigger), `version` on the read model, optional `expected_version` on
  the input, one `check_version` call after the row lock, and `live_events.publish_record_change`
  after commit.
* **A8 (helpdesk immediate change notification).** The shared SSE channel is in place and ticket
  updates/notes already publish to it; A8 will wire live article/timeline updates and draft merge UI
  in `TicketScreen` on top of it.
