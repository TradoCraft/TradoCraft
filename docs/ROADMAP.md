# Roadmap: parity with a CRM, an accounting package and open-source ERPs

Target: the *operational* 80% of a CRM (CRM, service), an accounting package (stock, purchasing, production)
and open-source ERPs (helpdesk, knowledge base, field service, planning, MRP) for a 20-50 user manufacturing and
service company. Statutory accounting stays in the accounting package ([ADR 0008](adr/0008-accounting-stays-external.md)).
Module overview: [ARCHITECTURE.md](ARCHITECTURE.md).

## Status

| Item | State |
|---|---|
| Order lifecycle (revisions, confirmation, priority) | Done, [ADR 0016](adr/0016-order-lifecycle.md) |
| Quotation line remarks, remark history and product options | Done, [ADR 0037](adr/0037-line-remarks-and-product-options.md) (stacked on ADR 0033) |
| A1 Helpdesk SLA, teams, attachments, tags, merge, time, CSAT | Done, ADR 0017 (PR #2) |
| A2 Knowledge base | Done, ADR 0018 (PR #2) |
| A3 Field service completion | Done, ADR 0020 and [ADR 0022](adr/0022-technician-offline-queue.md) |
| A4 Helpdesk collaboration (manual escalation, hand-over, watchers, unread, timeline, soft presence) | Done, [ADR 0023](adr/0023-helpdesk-collaboration.md) |
| Helpdesk follow-up: business hours, automation rules, split, reporting | Done, ADR 0021 |
| Helpdesk mailboxes: several per company, Microsoft 365 (Graph) or IMAP/SMTP, replies through the ticket's mailbox | Done, [ADR 0054](adr/0054-helpdesk-mailboxes.md) |
| User-defined reports (customers, quotations, orders; joins, grouping, charts, CSV and PDF) | Done, [ADR 0042](adr/0042-report-builder.md) |
| Environment awareness (`/meta/environment`, environment list, banner and switcher in the app) | Done, [ADR 0043](adr/0043-environments.md); clone script, bootstrap wizard and outbound-side-effect switch-off follow |
| A5 Helpdesk customer mail: e-mail actions in automation rules, SLA notices to the customer, scheduled report mails | Open (builds on ADR 0021) |
| A6 Helpdesk reply templates and language detection | Open |
| A7 Helpdesk ticket checklists | Open |
| A8 Helpdesk immediate change notification (concurrent updates seen by both people) | Open (shares its push channel with D3) |
| A9 Helpdesk ticket bundles (linked tickets) | Open (merge and split are done, ADR 0017 and ADR 0021) |
| B1 Inventory foundation | Done, [ADR 0019](adr/0019-inventory-stock-ledger.md) |
| B2 Purchasing | In progress, [ADR 0031](adr/0031-purchasing.md) |
| B2b Supplier invoices and three-way match (AP register, no ledger) | Backend done, [ADR 0046](adr/0046-supplier-invoices-and-three-way-match.md); Flutter screens follow |
| B3 Delivery | Done, [ADR 0035](adr/0035-delivery.md) |
| C1a Production orders | Done, [ADR 0036](adr/0036-production.md) |
| C1b Work centres, routings, operations | Done, [ADR 0063](adr/0063-work-centres-routings-and-operations.md) |
| C2 MRP | Open (needs B1, B2, C1) |
| C3 Planning board, field-jobs half (calendars, absences, skills, conflicts, suggestions, drag-and-drop board) | Done, [ADR 0024](adr/0024-planning-board.md) |
| C3 Planning board, work-centre half (finite loading, drag-and-drop board) | Open; the capacity view and the work-centre calendars are done in C1b ([ADR 0063](adr/0063-work-centres-routings-and-operations.md)); reuses `ResourceBoard` |
| D1 Worker heartbeat and "worker was down" alert | Done, [ADR 0052](adr/0052-worker-heartbeat.md) |
| D2 Backup and restore runbook | Done, [ADR 0056](adr/0056-backup-and-restore.md) |
| D3 Concurrent-edit protection on records | Open |
| D4 VAT number validation, registry lookup and duplicate warning | Open |
| D5 Accent-insensitive search | Open |
| D6 Audit log viewer | Open |
| D7 Restrict CORS to configured origins | Open |
| D8 Draft autosave | Open |
| D9 Two-factor authentication | Open |
| D10 Data import framework (CSV, XLSX, ODS, Parquet) | Open (extends ADR 0029) |
| D11 VAT number validation, registry lookup and duplicate warning | Done, [ADR 0058](adr/0058-vat-number-validation-and-lookup.md); the request to the live VIES service is untested (see the ADR) |
| D12 Accent-insensitive search | Done for customers, contacts, suppliers and products, [ADR 0057](adr/0057-accent-insensitive-search.md); the other lists follow |
| D13 Audit log viewer | Done, [ADR 0059](adr/0059-audit-trail-viewer.md); field-level changes are recorded for customers and suppliers, other modules adopt `audit::Changes` |
| D14 Restrict CORS to configured origins | Done, [ADR 0050](adr/0050-portal-surface.md) |

## Sequencing

Dependencies drive the order: **stock ledger -> purchasing -> production and MRP -> planning**.
The service track (A) and the field-jobs half of the planning board are independent and can run in
parallel with the supply chain. Each item ends shippable: migrations, API, regenerated OpenAPI and Dart
client, Flutter screens, five-language strings, tests and an ADR.

## Track A - Service

**A3 Field service completion** (medium-large)
- Service report PDF (Typst, pattern `crates/sales/src/order_doc.rs`), customer signature capture.
- Parts used: record-only first; deduction from stock follows B1.
- Job to `engineering.serial_units` link (installed base) and a warranty flag.
- Maintenance contracts: contract, visit template and recurrence that generates jobs; SLA on contracts.
- Offline queue in the Flutter app ([ADR 0006](adr/0006-offline-sync.md), [ADR 0022](adr/0022-technician-offline-queue.md)). Done.

Helpdesk follow-up, done ([ADR 0021](adr/0021-helpdesk-business-hours-automation-reporting.md)): business hours and holidays in the SLA, automation rules, ticket split, reporting with CSV export.
Per-team business calendars are done (ADR 0021).
Remaining helpdesk gaps are planned as A5 to A9 below, inspired by Zammad.
Remaining report builder gaps ([ADR 0042](adr/0042-report-builder.md)): more objects (products, stock, tickets), dashboards, report folders, scheduled report mails.
Remaining knowledge base gaps (ADR 0018): non-image attachments, analytics, semantic search, a public web page.

**A5 Helpdesk customer mail** (medium)
- E-mail actions in automation rules (ADR 0021): a `send_email` action with a recipient (customer,
  assignee, team, fixed address), a subject and body from a template (A6), through the outbox so the
  environment switch-off ([ADR 0043](adr/0043-environments.md)) applies. A per-rule guard stops mail
  loops (one mail per ticket and rule per period).
- SLA notices to the customer: an acknowledgement on creation with the ticket number and the target
  response time, and an optional "we are late" notice on breach; configurable per team and priority,
  in the customer's language.
- Scheduled report mails: a saved helpdesk report (ADR 0021) or user-defined report
  ([ADR 0042](adr/0042-report-builder.md)) mailed on a schedule (daily, weekly, monthly) to users or
  addresses as CSV or PDF, run by the worker. One scheduler serves both report kinds.

**A6 Reply templates and language detection** (medium)
- Templates (text modules): per company or team, with placeholders (customer, ticket number, agent,
  order), one variant per language (nl, fr, en, de, es), a shortcut or search in the reply editor,
  and optional keyword triggers. The same templates feed the A5 mails.
- Language detection: the language of an incoming ticket or e-mail is detected, stored on the ticket
  and proposed as the reply and notice language; the agent can override it. Falls back to the
  customer's language, then the company default. Decide in the ADR between a small offline detector
  crate and an external service (offline first, since customer text should not leave the system).
- Optional automation condition `language` so tickets can route to a team by language.

**A7 Ticket checklists** (small-medium)
- A checklist per ticket (ordered items, done flag, who and when), applied from checklist templates
  per team or ticket category, and added by an automation rule on a trigger.
- Shown in the ticket and on the list (progress, for example 2/5); an optional rule blocks closing
  while items are open. Reuse the field-service checklist model ([ADR 0020](adr/0020-field-service-reports-contracts.md))
  where it fits.

**A8 Immediate change notification** (medium)
- When a ticket is updated while someone else has it open, both notice right away: the viewer sees
  the change appear (or a banner naming who changed what) without a reload, and the person who made
  the change sees who else is working on the ticket (builds on soft presence, ADR 0023).
- A change that conflicts with an unsaved edit is flagged before it can overwrite anything; the
  other person's change is shown next to the draft so it can be kept or reloaded.
- Delivered through a server-sent events channel per ticket. D3 uses the same channel for the
  conflict warning on other records.

**A9 Ticket bundles** (small-medium)
- Merge (ADR 0017) and split (ADR 0021) exist. Add links between tickets that stay separate: a
  parent with child tickets ("bundle"), related, or duplicate-of; shown in both tickets.
- A bundle shows its members' states; a reply or state change on the parent can be offered to all
  children (mass update with a preview), for example one outage with many customer tickets.

## Track B - Supply chain (sequential)

**B1 Inventory foundation** (large, done), [ADR 0019](adr/0019-inventory-stock-ledger.md) finalises the stock part of [ADR 0007](adr/0007-ledgers.md)
- Crate `inventory`: warehouses and locations (including service vans), an immutable `stock_moves` ledger
  with reversal corrections, a balance table updated in the same transaction, units of measure and
  conversions, lot/batch tracking (extend `tracking`), counts, adjustments, transfers.
- Product additions: cost, reorder min/max, lead time, barcode. Cost is hidden from sales ([ADR 0004](adr/0004-authentication.md)).
- Reservations against confirmed orders; availability (ATP) on the order screen.
- Deferred to later items: two-step transfers, valuation beyond the standard-cost snapshot, a UI for product-specific units, van stock for technicians (A3), open POs/MOs in ATP (B2, C1).

**B2 Purchasing** (large)
- Crate `purchasing`: suppliers, supplier price lists, product codes, MOQ and lead times;
  RFQ -> PO -> goods receipt; a receipt creates stock moves and serial units ([ADR 0011](adr/0011-bom-revisions-and-serial-genealogy.md)).
- PO PDF and mail to the supplier through the outbox; approval limits; vendor bill matching: see B2b for the three-way match.
- Numbering through `core::numbering::next_number` (new codes PO, GR). Export of bills and valuation to the accounting package later.

**B3 Delivery** (small-medium, done), [ADR 0035](adr/0035-delivery.md)
- Delivery notes for confirmed orders (also while partly shipped), picking from the reservations, a
  planned date, shipping with a carrier and tracking reference (consumes the reservations; the order
  becomes `partially_shipped`, then `shipped`), a PDF in five languages.
- Planning a date checks the customer's closures ([ADR 0032](adr/0032-customer-closures.md)); the
  administrator chooses per company whether that only warns, needs an override reason and right, or blocks.
- Later: carrier integrations, returns, invoicing from a shipped note, `ready_for_shipping` from production (C1).

## Track C - Production and planning (needs B1)

**C1a Production orders** (large, done), [ADR 0036](adr/0036-production.md), Phase 2 of [ADR 0016](adr/0016-order-lifecycle.md)
- Crate `production`: divisions, production orders from the active BOM (revision frozen), released by a
  planner for an order line or for stock, components reserved at release, backflush consumption with actual
  quantities and scrap, output into stock (lots, serial units with as-built genealogy).
- Planned-ready dates drive the order statuses `in_planning -> planned -> in_production ->
  ready_for_shipping` and the order's promised date (the latest one); queues sort by order priority.

**C1b Work centres, routings and operations** (large, done), [ADR 0063](adr/0063-work-centres-routings-and-operations.md)
- Work centres with opening hours and closures, a routing on the BOM revision (draft-only, copied by a new
  revision), operations on the production order (snapshotted and scheduled at release, finished with the
  minutes worked), a capacity grid, multi-level auto-release for the shortfall, a cost roll-up and the
  planned and actual cost of an order (behind `inventory.cost`), and a traveller PDF.
- Later: the work-centre planning board (C3), per-person time and a shop-floor offline queue, valuation and
  work in progress at actual cost, parallel or overlapping operations, routing times in MRP.

**C2 MRP** (large)
- Reorder rules and an MRP run for make-to-stock and make-to-order: net requirements from orders, stock and
  open POs/MOs; proposals for POs and MOs; lead-time offsetting.

**C3 Planning board** (medium-large)
- One calendar/Gantt component in Flutter for field jobs (drag-assign, availability, absences, skills,
  conflicts, travel-time estimate) and work centres (capacity, finite loading).
  Resource calendars are the shared backend piece.
- Field-jobs half: Done ([ADR 0024](adr/0024-planning-board.md)). Work-centre half: Open; reuse
  `planning.working_hours`/`absences`, the pure conflict/suggestion functions and `ResourceBoard`.

## Track D - Platform and operations (independent of A, B and C)

Each item gets its own ADR when it is picked up. D1 and D2 come first: both are small and protect
production.

**D1 Worker heartbeat and "worker was down" alert** (small)
- `apps/worker` is one polling loop (IMAP, SLA escalation, contract visits, outbox). When it stops,
  nothing reports it.
- The loop writes a heartbeat row each pass; the API exposes its age, the app shows a warning to
  administrators, and a system mail goes out when the worker resumes after a gap.
- Done ([ADR 0052](adr/0052-worker-heartbeat.md)): `GET /admin/worker`, an amber strip for
  administrators, and outages recorded in `core.worker_outages`.

**D2 Backup and restore runbook** (small)
- A scripted backup that copes with the files stored in `bytea` (a physical backup rather than
  `pg_dump` while those live in the database), a retention rule, and a restore that is tested
  against a clone ([ADR 0043](adr/0043-environments.md)).
- A runbook in `docs/runbooks/`.
- Done ([ADR 0056](adr/0056-backup-and-restore.md)): `scripts/backupctl` (`pg_basebackup` with a
  manifest, 7 daily, 4 weekly and 6 monthly backups kept, `verify` restores into a throwaway
  server and reads every row) and the [runbook](runbooks/backup-and-restore.md), with a restore
  drill through `envctl clone`.

**D3 Concurrent-edit protection on records** (medium)
- Updates carry no version check today, so two people who edit the same customer, quotation or
  order overwrite each other without a warning.
- Decide in the ADR between optimistic concurrency (a row version checked on update, a 409 and a
  reload prompt in the app) and a short-lived edit lock that shows who has the record open.
- Zammad-style editing-conflict warning: while a record is open, show when someone else changed it or
  is editing it, and offer a reload or merge before saving. Tickets get this through A8; D3 covers
  the other records and the 409 on the API.

**D4 VAT number validation, registry lookup and duplicate warning** (small-medium)
- `vat_number` on customers was stored unchecked; the supplier's `tax_id` (free text) was never looked at.
- Format and check-digit validation, a VIES lookup that pre-fills name and address on create (with
  a fallback when the service is down), and a warning when the number already exists.
- Done ([ADR 0058](adr/0058-vat-number-validation-and-lookup.md)): `core::vat` (format for the 27 member
  states, check digits for 19, cross-checked against an independent implementation), a refusal of a
  new or changed wrong number on customers and suppliers (an unchanged legacy number is left alone),
  `GET /customers/vat-check` and `GET /suppliers/vat-check` (status, duplicates, optional VIES lookup),
  and a VAT field in the customer and supplier forms that shows the verdict as the user types and has a
  lookup button. `VIES_URL` configures or switches off the lookup.
- Still to do: one lookup against the live VIES service (the build environment could not reach it);
  check digits for the other countries (BG CY CZ ES IE LT LV MT); validating the company's own number.

**D5 Accent-insensitive search** (small)
- List and lookup searches use `ILIKE`, so "Liege" does not find "Liège". Customers, contacts,
  suppliers and products in five languages need accent folding (`unaccent` with a matching index).
- Done ([ADR 0057](adr/0057-accent-insensitive-search.md)): `core.search_fold` and `core::search`, applied to
  those four searches, trigram indexes for the three large tables, and a `q` on `GET /suppliers` (the
  app's supplier list no longer filters in Dart).
- Still to do: the other lists that search with `lower(...) LIKE` (orders, quotations, tickets, repairs,
  packages, delivery notes, field jobs, contracts, stock, production orders, finance invoices, report
  filters): each is a one-line change to `search::matches`.

**D6 Audit log viewer** (medium)
- `audit.events` is written in every transaction but cannot be read: no endpoint and no screen.
- A permission-gated history per record (who changed what and when) and a company-wide view with
  filters for administrators.
- Done ([ADR 0059](adr/0059-audit-trail-viewer.md)): permission `audit.view` (administrators), `GET /audit/events`,
  `GET /audit/records/{entity}/{id}` and `GET /audit/facets` with cursor paging, an Audit trail tab in
  Administration and a History button on customers and suppliers. Customer and supplier updates now
  record which fields changed (`audit::Changes`).
- Still to do: the other modules record little more than the action; adopt `audit::Changes` where
  they record an update. A user filter in the app, an export, and a retention rule.

**D7 Restrict CORS to configured origins** (small)
- Done ([ADR 0050](adr/0050-portal-surface.md)): the API reads `CORS_ALLOWED_ORIGINS` (any origin
  only with `AUTH_MODE=dev`); the customer portal server answers the companies' `portal_url`
  origins or `PORTAL_ALLOWED_ORIGINS`.

**D8 Draft autosave** (small-medium)
- A long text (ticket reply, internal note, knowledge base article, quotation remark) is saved as a
  server-side draft every few seconds and on leaving the screen, per user and record, so a closed
  tab, a crash or a lost connection loses nothing. The draft is offered again on return and removed
  on send.
- Local copy in the app when offline (reuse [ADR 0022](adr/0022-technician-offline-queue.md)
  storage), synced when back online. Interacts with D3: a draft records the record version it began on.

**D9 Two-factor authentication** (medium)
- [ADR 0004](adr/0004-authentication.md) lists MFA as a next step; nothing is built. Decide in the ADR
  whether it is enforced by the identity provider or by the application: TOTP enrolment with a QR
  code, single-use recovery codes, an administrator policy (off, optional, required per role) and a
  reset by an administrator that is audited (D6).
- Passkeys (WebAuthn) as a later second factor; the customer portal can opt in separately.

**D10 Data import framework** (large)
- Today only customers and products import, from CSV ([ADR 0029](adr/0029-csv-export-import.md)), with
  the code duplicated per entity in `crates/crm/src/csv.rs` and `crates/products/src/csv.rs`.
  Build one importer in `core` that other crates plug into with a small trait (columns, validation,
  upsert key, write).
- File formats behind one reader interface that yields rows of typed cells: CSV (existing), XLSX,
  ODS and Parquet. XLSX and ODS: first sheet by default with a sheet picker, cell values read as
  stored (dates, numbers) instead of display text, formulas read as their cached value, macros
  ignored, and size limits checked before unpacking (zip bombs). Parquet: columnar types mapped to
  the same cell types, read in row batches. Choose the crates in the ADR (candidates: `calamine`
  for XLSX and ODS, `parquet`/`arrow` for Parquet).
- Admin screen: upload, choose entity and sheet, map file columns to fields (remembered per entity as a
  saved mapping), dry run with the per-row error report, then apply. Keep the ADR 0029 rules:
  everything validates first, any error means nothing is written, one transaction, one audit event per
  record with the source, upsert by code, nothing is deleted.
- Larger files than the 5 MB / 20 000 row CSV limit: a background import job through the worker with
  progress and a downloadable error report, instead of one request.
- More entities, in order of onboarding value: contacts, suppliers (after B2), stock opening
  balances through the stock ledger ([ADR 0019](adr/0019-inventory-stock-ledger.md)), open sales
  orders and quotations, and helpdesk tickets from another system. Export gets the same formats
  (XLSX and ODS) so a round trip works.
- Permission `<entity>.write` per entity plus an administrator right for saved mappings and
  background jobs.

## Working in parallel

Items that can run at the same time on separate branches: A3, A5 to A9, B1, the field-jobs half of C3, and the
Track D items. A6 comes before A5's mail actions (shared templates); A8 and D3 share the live channel, so build it once.

Shared files that will conflict between branches:
- `crates/core/src/auth.rs` (permissions)
- `api/openapi.json` and `app/lib/api/generated/`
- `app/lib/l10n/*.arb` and the generated l10n Dart files
- `Cargo.toml`, `apps/api/src/lib.rs`, `app/lib/app/router.dart`, `app/lib/app/shell.dart`

Rules:
- One branch and one PR per item. Merge the earlier PRs first so everyone starts from the same base.
- After a rebase, regenerate the generated files (`scripts/generate-api-client.sh`, `flutter gen-l10n`)
  instead of resolving them by hand.
- Give migrations unique timestamps (agree a date prefix per session) so two branches never share a name.
- Agree table shapes in an ADR before another module builds on them (for example B1 before B2 and C1).

## Per-item checklist

- Crate per module, schema per module, `company_id` on every transactional table, a `utoipa` router,
  permissions in `crates/core/src/auth.rs`, audit through `core::audit::record`.
- Tenant isolation: add row-level security, or a test that scans queries for `company_id`, before stock and
  purchasing data lands.
- Strings in all five languages (nl, fr, en, de, es); an ADR; DB-backed tests (`sqlx::test`); widget tests.
- Move file storage off PostgreSQL `bytea` before attachments multiply.

Verification for every item:

```bash
export DATABASE_URL=postgresql://tradocraft:tradocraft@localhost:5433/tradocraft   # docker compose up -d db
cargo fmt --all --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
cd app && flutter analyze && flutter test
```

## Out of scope (use the accounting package or external tools)

Statutory accounting, VAT returns, bank reconciliation, payroll, e-commerce, marketing automation.
