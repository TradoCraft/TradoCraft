# 0060 — Concurrent-edit protection

**Status:** Accepted (customers, quotations and orders; the app screens follow)

**Context.** Updates carried no version check, so two people who opened the same customer, quotation or
order and saved one after the other overwrote each other without a warning: the second save replaced the
first person's changes with a form built from older data. Roadmap item D3.

Delivery notes already had a check (ADR 0035): the note carries `updated_at`, the app sends it back as
`expected_updated_at`, and a stale value is a 409 `delivery_note_changed`. That is the pattern to extend,
with two changes explained below.

**Decision.** Optimistic concurrency on a row version, not an edit lock.

*Why not a lock.* A lock that shows who has the record open needs somewhere to keep it (a table with
expiry, or session state), a heartbeat from every open form, a way out when someone closes a laptop or
loses the connection, and an administrator override for the lock that never expires. It also only works
for people using the app: a script, an import or the portal ignores it. A version check is enforced
where the write happens, needs no state beyond the row, and cannot be left behind. The cost is that the
second person finds out when they save, not when they open the record. Showing who else has a record open
is a separate, softer feature (helpdesk has it, ADR 0023) and can be added on top later.

*Why a counter and not `updated_at`.* Two reasons found while reading the code.
1. `updated_at` is not set by every `UPDATE` (several status and totals updates leave it alone), so
   a change could go unnoticed. A trigger that raises a counter on every update of the row cannot be
   forgotten by a new statement.
2. The app also runs on the web, where a Dart `DateTime` keeps milliseconds. PostgreSQL stores
   microseconds, so a timestamp that went through the app would compare unequal to the stored one
   and refuse a save that was not stale. An integer round-trips exactly.

*What changed.*
* Migration `20270202000001_record_versions.sql`: `version bigint NOT NULL DEFAULT 1` on
  `crm.customers`, `sales.quotations` and `sales.orders`, and one trigger function,
  `core.bump_row_version()`, that raises it on every update of the row. Adding the column does not
  rewrite the tables.
* The read models (`Customer`, `Quotation`, and `Order` at its top level) return `version`.
* The update inputs (`CustomerInput`, `QuotationInput`, `OrderEditInput`) take an optional
  `expected_version`. The check runs after the row is locked (`FOR UPDATE`) and before anything is
  written, in `core::concurrency::check_version`. A stale value is a **409** with code
  `record_changed` and a message naming the record. Two saves from the same version therefore give one
  success and one 409: the second waits for the lock, then finds the version moved on (tested with two
  simultaneous requests).
* **The field is optional.** A save without it is not checked, as before. Scripts, the CSV customer
  import and the configurator's re-import keep overwriting on purpose. The app sends it on every save.
  Making it mandatory later is a one-line change per input once nothing else depends on the old behaviour.
* A refused save changes nothing, and the version only moves on a real write.
* Delivery notes keep `expected_updated_at` for now; they work and have a test. They can move to the
  counter when a note is next touched.

**Not done here (follow-ups).**
* **Flutter.** The generated Dart client and the edit screens still have to send `expected_version`
  and, on `record_changed`, offer to reload (keeping what the person typed visible). This needs
  `scripts/generate-api-client.sh` (the Dart toolchain), five-language strings, and widget tests.
  Until then the app behaves as before: it does not send the field, so nothing is refused.
* **Other records.** Suppliers, products, contacts, opportunities, tickets and the rest are open. The
  recipe is the migration (column and trigger), the `version` field on the read model, the optional
  `expected_version` on the input, and one `check_version` call after the row lock.
* **Status transitions** on quotations and orders (send, confirm, cancel, revise) are not given the
  check; each already refuses a record that is no longer in the status it needs.
* A customer's commercial terms live in `crm.customer_terms`, per company, and are saved together with
  the customer, which always touches the customer row. If terms ever get a save of their own, that save
  needs its own version or must touch the customer row.
