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
| User-defined reports (customers, quotations, orders; joins, grouping, charts, CSV and PDF) | Done, [ADR 0042](adr/0042-report-builder.md) |
| Environment awareness (`/meta/environment`, environment list, banner and switcher in the app) | Done, [ADR 0043](adr/0043-environments.md); clone script, bootstrap wizard and outbound-side-effect switch-off follow |
| B1 Inventory foundation | Done, [ADR 0019](adr/0019-inventory-stock-ledger.md) |
| B2 Purchasing | In progress, [ADR 0031](adr/0031-purchasing.md) |
| B2b Supplier invoices and three-way match (AP register, no ledger) | Backend done, [ADR 0046](adr/0046-supplier-invoices-and-three-way-match.md); Flutter screens follow |
| B3 Delivery | Done, [ADR 0035](adr/0035-delivery.md) |
| C1a Production orders | Done, [ADR 0036](adr/0036-production.md) |
| C1b Work centres, routings, operations | Open (needs C1a) |
| C2 MRP | Open (needs B1, B2, C1) |
| C3 Planning board, field-jobs half (calendars, absences, skills, conflicts, suggestions, drag-and-drop board) | Done, [ADR 0024](adr/0024-planning-board.md) |
| C3 Planning board, work-centre half (capacity, finite loading) | Open (needs C1; reuses the resource calendar and `ResourceBoard`) |
| D1 Worker heartbeat and "worker was down" alert | Done, [ADR 0052](adr/0052-worker-heartbeat.md) |
| D2 Backup and restore runbook | Open |
| D3 Concurrent-edit protection on records | Open |
| D4 VAT number validation, registry lookup and duplicate warning | Open |
| D5 Accent-insensitive search | Open |
| D6 Audit log viewer | Open |
| D7 Restrict CORS to configured origins | Done, [ADR 0050](adr/0050-portal-surface.md) |

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
Remaining helpdesk gaps: e-mail actions in automation rules, scheduled report mails, SLA notices to the customer.
Remaining report builder gaps ([ADR 0042](adr/0042-report-builder.md)): more objects (products, stock, tickets), dashboards, report folders, scheduled report mails.
Remaining knowledge base gaps (ADR 0018): non-image attachments, analytics, semantic search, a public web page.

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

**C1b Work centres, routings and operations** (large)
- Work centres, routings on the BOM, operations on the production order, labour and capacity; the
  work-centre half of C3 builds on it. Also: multi-level auto-release, a production order PDF, cost roll-up.

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

**D3 Concurrent-edit protection on records** (medium)
- Updates carry no version check today, so two people who edit the same customer, quotation or
  order overwrite each other without a warning.
- Decide in the ADR between optimistic concurrency (a row version checked on update, a 409 and a
  reload prompt in the app) and a short-lived edit lock that shows who has the record open.

**D4 VAT number validation, registry lookup and duplicate warning** (small-medium)
- `vat_number` on customers is stored unchecked; suppliers have no VAT number field yet.
- Format and check-digit validation, a VIES lookup that pre-fills name and address on create (with
  a fallback when the service is down), and a warning when the number already exists in the company.

**D5 Accent-insensitive search** (small)
- List and lookup searches use `ILIKE`, so "Liege" does not find "Liège". Customers, contacts,
  suppliers and products in five languages need accent folding (`unaccent` with a matching index).

**D6 Audit log viewer** (medium)
- `audit.events` is written in every transaction but cannot be read: no endpoint and no screen.
- A permission-gated history per record (who changed what and when) and a company-wide view with
  filters for administrators.

**D7 Restrict CORS to configured origins** (small)
- Done ([ADR 0050](adr/0050-portal-surface.md)): the API reads `CORS_ALLOWED_ORIGINS` (any origin
  only with `AUTH_MODE=dev`); the customer portal server answers the companies' `portal_url`
  origins or `PORTAL_ALLOWED_ORIGINS`.

## Working in parallel

Items that can run at the same time on separate branches: A3, B1, the field-jobs half of C3, and the
Track D items.

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
