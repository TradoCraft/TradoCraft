# Roadmap: parity with a CRM, an accounting package and open-source ERPs

Target: the *operational* 80% of a CRM (CRM, service), an accounting package (stock, purchasing, production)
and open-source ERPs (helpdesk, knowledge base, field service, planning, MRP) for a 20-50 user manufacturing and
service company. Statutory accounting stays in the accounting package ([ADR 0008](adr/0008-accounting-stays-external.md)).
Module overview: [ARCHITECTURE.md](ARCHITECTURE.md).

## Leptos release gate for v0.4.0

Hold v0.4.0 until all four workflows pass in the packaged Leptos web frontend at `/app/`.
Flutter remains available for the rest of the application. Full Flutter feature parity is outside
this release gate.

- [x] **Helpdesk.** A staff user can find and open tickets, create a ticket, assign it to a team
  or owner, add an internal note, send a customer reply with an attachment, and change or reopen
  its status. Verify that the reply reaches the local outbox in the tutorial environment and
  that the ticket history and attachment are still available after a reload.
- [x] **To-do.** A staff user can open To-do from the navigation, create a task and a sub-item,
  edit the task and its due date, complete and reopen it, and filter the list by Open, Done, or
  All. Verify that changes survive a reload.
- [x] **Knowledge Base.** Staff can search and read articles by category and language.
  Users with edit permission can create, edit, and publish an article with the intended visibility.
  Verify that a public article is discoverable in the public reader and that drafts and staff-only
  articles stay out of public results.
- [x] **Standard Answers (Prepared Answers).** Users with permission can create and edit reusable
  reply templates with subject and body translations. In Helpdesk, an agent can find an answer,
  insert it into a ticket reply in the ticket's language, review the rendered placeholders, and
  edit the draft before sending. Verify that the resulting reply reaches the tutorial outbox.
- [ ] **Release verification.** Exercise all four workflows in browser tests against the real API
  and a seeded database. Smoke-test the packaged `/app/` entry point before tagging v0.4.0.
  Done: Playwright specs for all four workflows in `e2e/tests-leptos/` (`npm run test:leptos`), run against the
  API with the dev seed, and run by the `e2e-leptos` job in `.github/workflows/ci.yml`. Open: smoke-test the packaged
  Docker image.

The existing [Leptos Helpdesk](../crates/web-ui/src/pages/helpdesk.rs) and
[Flutter To-do](../app/lib/features/todo/todo_page.dart) are the starting points. See also the
[Leptos public knowledge-base reader](../crates/web-ui/src/pages/kb.rs) and
[Flutter Prepared Answers](../app/lib/features/helpdesk/answers_page.dart).

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
| A5 Helpdesk customer mail (`send_email` automation action, SLA notices to the customer, scheduled report mails) | Done, [ADR 0064](adr/0064-helpdesk-sla-customer-notices.md), [ADR 0065](adr/0065-scheduled-report-mails.md), [ADR 0066](adr/0066-helpdesk-send-email-action.md); mail templates are A6 |
| A6 Helpdesk reply templates and language | Done, [ADR 0072](adr/0072-helpdesk-reply-templates.md) (builds on the prepared answers of ADR 0013); SLA notices to the customer still use built-in texts, see A6b |
| A6b Helpdesk SLA notices from templates | Open (needs deadline placeholders and rendering without a user) |
| A7 Helpdesk ticket checklists (templates per team, `apply_checklist` automation action, progress badge, optional close gate) | Done (PR #100), [ADR 0093](adr/0093-helpdesk-ticket-checklists.md) |
| A8 Helpdesk immediate change notification (concurrent updates seen by both people) | Done, [ADR 0075](adr/0075-helpdesk-live-ticket-updates.md) (builds on the SSE channel of [ADR 0073](adr/0073-concurrent-edit-protection.md)); mail ingested by the worker follows |
| A9 Helpdesk ticket bundles (linked tickets: bundle, related, duplicate; bundle mass update with preview) | Done, [ADR 0076](adr/0076-helpdesk-ticket-links-and-bundles.md); list badge, per-customer greeting in a bundle reply and automation on links follow |
| B1 Inventory foundation | Done, [ADR 0019](adr/0019-inventory-stock-ledger.md) |
| B2 Purchasing | Done, [ADR 0031](adr/0031-purchasing.md) |
| B2b Supplier invoices and three-way match (AP register, no ledger) | Done, [ADR 0046](adr/0046-supplier-invoices-and-three-way-match.md) |
| B3 Delivery | Done, [ADR 0035](adr/0035-delivery.md) |
| C1a Production orders | Done, [ADR 0036](adr/0036-production.md) |
| C1b Work centres, routings, operations | Done, [ADR 0063](adr/0063-work-centres-routings-and-operations.md) |
| C2 MRP | Done, [ADR 0091](adr/0091-material-requirements-planning.md): a run nets open order lines, production components, stock and open purchase and production orders per product down the BOMs and proposes what to buy or build (`/mrp`); safety stock and order multiple on the product; a proposal becomes a draft purchase order or a released production order. Routing times and calendars in lead times, supplier calendars, net-change runs, a worker job, per-line delivery dates and reschedule proposals follow |
| C3 Planning board, field-jobs half (calendars, absences, skills, conflicts, suggestions, drag-and-drop board) | Done, [ADR 0024](adr/0024-planning-board.md) |
| C3 Planning board, work-centre half (finite loading, drag-and-drop board) | Done, [ADR 0090](adr/0090-work-centre-planning-board.md): `GET /production/planning-board`, a dry-run `PUT .../operations/{id}/move` with `force`, a `finite` re-schedule and the board in the app (`ResourceBoard`, day granularity). Suggestions of the earliest free slot, a re-flow of the queue after a move, per-hour sequencing and parent/subassembly dependencies follow |
| D1 Worker heartbeat and "worker was down" alert | Done, [ADR 0052](adr/0052-worker-heartbeat.md) |
| D2 Backup and restore runbook | Done, [ADR 0056](adr/0056-backup-and-restore.md) |
| D3 Concurrent-edit protection on records | Done for customers, quotations, orders and tickets (shared SSE push channel + Flutter UI), [ADR 0073](adr/0073-concurrent-edit-protection.md); other records follow |
| D4 VAT number validation, registry lookup and duplicate warning | Done, [ADR 0058](adr/0058-vat-number-validation-and-lookup.md); the request to the live VIES service is untested (see the ADR) |
| D4b Country-aware, temporal, and building-age VAT defaults | Done, [ADR 0071](adr/0071-country-vat-defaults.md) |
| D5 Accent-insensitive search | Done for customers, contacts, suppliers and products, [ADR 0057](adr/0057-accent-insensitive-search.md); the other lists follow |
| D6 Audit log viewer | Done, [ADR 0059](adr/0059-audit-trail-viewer.md); field-level changes are recorded for customers and suppliers, other modules adopt `audit::Changes` |
| D7 Restrict CORS to configured origins | Done, [ADR 0050](adr/0050-portal-surface.md) |
| D8 Draft autosave | Open |
| D9 Two-factor authentication | Open |
| D10 Data import framework (CSV, XLSX, ODS, Parquet) | Done for the shared importer, CSV/XLSX/ODS readers, XLSX/ODS export, admin screen and background jobs, [ADR 0067](adr/0067-data-import-framework.md); Parquet and further entities (contacts, suppliers, stock opening balances, quotations, orders, tickets) follow |
| P1 Price lists (zones, chapters, export profiles, PDF and Excel) | Done (PRs #95, #97), [ADR 0074](adr/0074-price-lists.md); never run in a real app (see the release checklist) |
| P2 Site baseline and product suitability | **Deferred from the first release**, [ADR 0068](adr/0068-site-baseline-and-product-suitability.md) (still Proposed). Baseline, matching, tower configurator import and quotation picker suitability are implemented. The quote can open its linked baseline directly. An end-to-end test remains open. |
| U1 Shared UI framework (theme tokens and dark mode, repository layer, app switcher and breadcrumbs, global search and notifications, generic list view, server-side sort, filters, facets and saved favourites, group-by, generic form view, kanban, chatter) | In progress. Done and merged: phases 0 to 3 ([ADR 0077](adr/0077-ui-theme-tokens-and-dark-mode.md) to [ADR 0085](adr/0085-generic-form-view.md), including list group-by, [ADR 0089](adr/0089-list-group-by.md)); the generic list view now serves orders, tickets, products and suppliers as well, and the generic form view customers, quotations, orders, products and suppliers (PRs #109 to #113, #119, #123, #159). The invoice line editor and smart buttons on quotations and orders exist. Phase 4, chatter, followers and activities ([ADR 0086](adr/0086-generic-chatter-and-activities.md), accepted, on customers, quotations, orders and opportunities; PR #124): backend, panel, file attachments on notes, field-level messages, assignment mail, live updates and clean-up are done. Phase 5, kanban: the generic board and the opportunity pipeline ([ADR 0087](adr/0087-generic-kanban-view.md), PR #125) and tickets on the board ([ADR 0088](adr/0088-tickets-on-the-kanban-board.md), PR #126) are done. Open: the ticket record screen on the generic form view, a one2many line editor beyond invoices, the calendar view, live updates of the board, team, tag and SLA filters on the ticket board, attachments on activities, messages for quotation and order line changes. |
| UX1 Frontend UX phases 1 to 5 (entity list search clear and responsive header, active group label and top-bar search pill, five-item navigation bar with a More sheet, role-aware home overview, non-blocking tab editing in the product form) | Done (PRs #152 to #156), [ADR 0095](adr/0095-frontend-ux-navigation-and-home.md) |
| T1 Tutorial chapters 10 and 11 (10: working a helpdesk ticket; 11: custom product properties) and the tutorial tooling (assisted steps, menu guidance, show control, instance-scoped progress, `tutorial-env` update) | Merged (PRs #116, #127, #128, #133, #134, #136 to #138); both chapters are in the e2e walk (`e2e/tests/tutorial.spec.ts`). The chapter 10 text was written without being run: run `flutter gen-l10n`, the tutorial tests and the e2e walk. Open from chapter 10: links and bundles, checklists, watching, hand-over and the call log |
| W1 Portable Windows demo (tutorial ZIP and per-user setup EXE) and release artifacts | Done (PR #161, `windows-demo.yml`, `release.yml`); published with v0.3.0 |
| PM1 Product media (pictures, videos, SVG, default selection) and the `.glb` 3D assembly viewer | Done (PRs #132, #148, #158), [ADR 0096](adr/0096-product-media-and-3d-viewer.md) |
| F1 Customer billing (customer invoices, correction credits, annual rebates) | Done (PR #147; `crates/finance`), [ADR 0097](adr/0097-customer-billing-and-rebates.md) |
| DL1 Document library and customer mail merge | Done (PR #131; `crates/kb`), [ADR 0098](adr/0098-document-library-and-mail-merge.md) |
| PR1 Negative unit prices; three price flags and planned zone price corrections; multi-zone pricing table, product copy and shortcut preferences | Done, [ADR 0084](adr/0084-price-flags-and-planned-price-corrections.md) (PR #118); negative prices and the pricing table in PRs #149 and #150 |
| M1 MCP pilot (`apps/mcp`: delegated, read-only `get_order` over Streamable HTTP with OAuth, same company boundary and permission as the staff API) | Done as a pilot (PR #115, [README](../apps/mcp/README.md)); [ADR 0094](adr/0094-mcp-pilot.md), no further tools planned |

## First release checklist

v0.2.0 and v0.3.0 are tagged and published by `.github/workflows/release.yml` (Docker images, Windows
artifacts, checksums, a portable Windows demo). Versions are `0.3.0` across Cargo, OpenAPI, the Flutter app and
the deploy files; [CHANGELOG.md](../CHANGELOG.md) and [RELEASING.md](RELEASING.md) now exist. The items below are what
remains before a distributable release. The findings below come from
`docs/security-review-2026-11-14.md` (no Critical or High findings). That file is not in the repository, so the
finding numbers were **not** checked against it: each finding was re-verified from its one-line description in this
roadmap, against the current code.

**Blockers**
- Security. Medium findings #1 to #7 are handled in the code (below); nothing here was run on a device or in a live
  environment.
  - #1 portal photo upload IDOR and file-ID oracle: real, fixed. A portal upload no longer uses the customer's
    `client_id` as the file id; the stored id is derived from company, contact, record and `client_id`
    (`portal_file_id`). Two database tests fail without the fix. A portal file id no longer equals the `client_id` sent.
    Staff uploads still use `client_id` directly.
  - #2 OIDC first login trusts an unverified email: already fixed in the code (`require_verified_claim` is the
    default everywhere); a test now locks it in.
  - #3 and #4 wildcard CORS and dev-auth defaults: mostly in place; the gap was `CORS_ALLOWED_ORIGINS=*` with
    `AUTH_MODE=dev`. The staff API now refuses to start with `*` under dev auth or `APP_ENV_KIND=live`
    ([ADR 0092](adr/0092-no-wildcard-cors-with-dev-auth-or-in-live.md)). Breaking for a live setup that used `*`.
    Checked by starting the binary: `*` with dev auth, or in a live environment, refuses to start; `*` with real sign-in in a
    tutorial environment starts with a warning; dev auth on a non-loopback address refuses. The portal server still
    only warns on `*`.
  - #5 JWKS refresh throttle and timeout: the throttle existed; timeouts for the host lookup and for the whole fetch
    were added, with tests against a provider that never answers.
  - #6 Android release signed with the debug key: the debug-key fallback is removed; a release build fails without a
    keystore. `.github/workflows/android-release.yml` builds a signed AAB and APK from secrets and fails on a debug
    certificate ([app/android/SIGNING.md](../app/android/SIGNING.md)). The Gradle check and the workflow have not been run.
  - #7 tokens in SharedPreferences and `allowBackup`: tokens moved to `flutter_secure_storage` with a one-time migration;
    `allowBackup` is off with backup exclusion rules. Tested with an in-memory fake only, not on Android, Windows, Linux or web.
  - Tenant isolation: the `company_id` query-scan test (`crates/core/tests/tenant_query_scan.rs`) flagged 381
    statements; 4 were fixed (division delete, ticket merge lock, serial-unit lock) and 377 are allowlisted with a
    reason in `tenant_scan_allowlist.txt`. None was a direct cross-tenant read or write. The 4 fixes have no database
    tests of their own. Review the allowlist: many entries were judged by pattern ("the row was loaded with
    `company_id` earlier"). Shared by design and worth confirming: product media and the "often bought together"
    counts are not scoped by company. Three portal items (global login-link rate limit, session creation marking the
    contact's links used in every company) are allowlisted, not changed.
- Release mechanics. Done in the repository: a release workflow, the tag convention, a non-root Docker user,
  `.env*` in `.dockerignore`, a Docker `HEALTHCHECK` on `/health`, pinned base image tags (they exist on Docker Hub; not
  digests), no default database password (`POSTGRES_PASSWORD` is required, a breaking deployment change), a
  versioning policy and release procedure ([RELEASING.md](RELEASING.md), `scripts/bump-version.sh`), a CHANGELOG, cosign
  keyless signing of the images and of `SHA256SUMS`, and an accurate README status line. **Not run:** the image build,
  the `HEALTHCHECK` in a container, the cosign steps and the release workflow; try them on a test tag in a fork first.
  **Owner action:** create the Android release keystore and the four `ANDROID_*` secrets; the production keys are
  never created or held by the tooling.
- P2 (site baseline): **deferred from the first release.** It stays in the tree and its migrations run, but it is not
  part of the first release's scope or support, and [ADR 0068](adr/0068-site-baseline-and-product-suitability.md) stays Proposed.
  It is not gated by a module switch (it lives inside Customers and Products); decide whether to add one. Before it
  ships: an end-to-end test, the ADR accepted, and its migrations applied to a database that already has companies.
- Run in a real app what had only been tested in isolation:
  - Done: one live request to VIES (D4). It worked; the client maps all three real answers (valid, invalid, member
    state busy) correctly, now pinned as tests. A quotation PDF with 18 long lines and a price-list PDF in nl, fr and
    en were rendered through the API with Typst 0.15.1; layout is fine. File names in the price-list export are
    sanitised for Windows (reserved names, byte limits, collisions), with tests.
  - Open: price-list save, open and share in the Flutter app; a real Windows run (only the `windows-demo.yml` job
    covers it).
  - Done on the merged code (2026-11-26): `cargo test --workspace` (1,709 tests, none failing), `cargo clippy --workspace --all-targets -D warnings`, `cargo fmt --check`, the OpenAPI document, the API-client contract and the wasm32 check; the Flutter suite (1,703 tests). One earlier full Flutter run had a single timing-dependent failure in `configurator_test` under load; it passes alone and on rerun.
- Translations: the nl, de, fr and es strings of price lists and site baseline were reviewed and 23 fixed
  ([translation-review-2026-11.md](translation-review-2026-11.md)). A native speaker should confirm the open questions in that file.

**Housekeeping**
- ADR numbering was fixed in `3eb5d9b`; the ADR index lists 0001 to 0098 with no duplicate numbers.
- Keep the `printing` package: `app/lib/features/kb/document_library_page.dart` uses its `PdfPreview`. Never commit the
  hook-created `.compliance/` (none is in the tree today).
- Remote branches were pruned on 2026-11-26; four unmerged ones remain to review (`claude/trusting-dirac-n4w811`, `feat/product-media`, `fix/duplicate-migration-version`, `fix/logo-wordmark`).
- No Dependabot PRs are pending; note the deferred `swagger-parser-2` migration (PR #94).

**After the first release**: A6b, D8, D9, and security findings
#8 to #17.

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
Helpdesk customer mail (A5) is done: `send_email` in automation rules, SLA notices to the customer and scheduled report mails (ADR 0064 to 0066). Remaining helpdesk gaps are planned as A6 to A9 below, inspired by Zammad; mail templates (A6) replace the inline text of `send_email`.
Remaining report builder gaps ([ADR 0042](adr/0042-report-builder.md)): more objects (products, stock, tickets), dashboards, report folders. Scheduled report mails are done (ADR 0065).
Remaining knowledge base gaps (ADR 0018): non-image attachments, analytics, semantic search, a public web page.

**A5 Helpdesk customer mail** (medium, done, ADR 0064 to 0066)
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

**A6 Reply templates and language detection** (medium, done, [ADR 0072](adr/0072-helpdesk-reply-templates.md)): Prepared answers remain the single template model and gained `kind` (`reply`, `internal_note`, `handover`, `notice`), optional `team_id` scope, and `keywords`. `GET /tickets/{id}/prepared-answers/suggest` returns ranked, filled-in suggestions (excluding other teams' templates), `send_email` automation actions can reference a prepared answer via `answer_id` (validated for subjects and known placeholders on save), tickets record `language_source` (`record`, `detected`, `agent`) with creator-language fallback on internal tickets, and automation rules can match `ticket_languages`. SLA notices to the customer still use built-in texts (deferred to A6b).

**A7 Ticket checklists** (small-medium, done, PR #100)
- A checklist per ticket (ordered items, done flag, who and when), applied from checklist templates
  per team or ticket category, and added by an automation rule on a trigger.
- Shown in the ticket and on the list (progress, for example 2/5); an optional rule blocks closing
  while items are open. Reuse the field-service checklist model ([ADR 0020](adr/0020-field-service-reports-contracts.md))
  where it fits.

**A8 Immediate change notification** (medium, done, [ADR 0075](adr/0075-helpdesk-live-ticket-updates.md))
- When a ticket is updated while someone else has it open, both notice right away: the viewer sees
  the change appear (or a banner naming who changed what) without a reload, and the person who made
  the change sees who else is working on the ticket (builds on soft presence, ADR 0023).
- A change that conflicts with an unsaved edit is flagged before it can overwrite anything; the
  other person's change is shown next to the draft so it can be kept or reloaded.
- Delivered through a server-sent events channel per ticket. D3 uses the same channel for the
  conflict warning on other records.

**A9 Ticket bundles** (small-medium, done, [ADR 0076](adr/0076-helpdesk-ticket-links-and-bundles.md))
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

**B2 Purchasing** (large, done), [ADR 0031](adr/0031-purchasing.md)
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
- Later: per-person time and a shop-floor offline queue, valuation and
  work in progress at actual cost, parallel or overlapping operations, routing times in MRP.

**C2 MRP** (large, done, [ADR 0091](adr/0091-material-requirements-planning.md))
- Reorder rules and an MRP run for make-to-stock and make-to-order: net requirements from orders, stock and
  open POs/MOs; proposals for POs and MOs; lead-time offsetting.
- Done: `POST /mrp/runs`, the proposals with their pegging, conversion to a draft purchase order or a
  released production order, `safety_stock` and `order_multiple` on the product, and the proposals page
  (`/mrp`). Lead times are calendar days (`lead_time_days`, the preferred supplier's).
- Still to do: routing times and work-centre calendars in the lead time of a built product, supplier
  calendars, net-change runs and a worker job, a delivery date per order line, forecast demand, reschedule
  proposals for orders that arrive too early or too late.

**C3 Planning board** (medium-large)
- One calendar/Gantt component in Flutter for field jobs (drag-assign, availability, absences, skills,
  conflicts, travel-time estimate) and work centres (capacity, finite loading).
  Resource calendars are the shared backend piece.
- Field-jobs half: Done ([ADR 0024](adr/0024-planning-board.md)). Work-centre half: Done
  ([ADR 0090](adr/0090-work-centre-planning-board.md)): finite loading (`production::finite`), the checked
  move with `dry_run` and `force`, a `finite` re-schedule and the board on `ResourceBoard`. Still to do:
  suggestions (earliest free slot or centre), a re-flow of the queue after a move, sequencing within a day,
  and the parent/subassembly dependencies in the checks.

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

**D3 Concurrent-edit protection on records** (medium, done for customers, quotations, orders and tickets, [ADR 0073](adr/0073-concurrent-edit-protection.md))
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
  once the relevant action succeeds: a send for a reply or note, a save for a quotation remark, a
  save or publish for a knowledge base article.
- Between two server saves the app also keeps the text in a local copy on every keystroke batch
  (reuse [ADR 0022](adr/0022-technician-offline-queue.md) storage), so a crash inside the save
  interval loses nothing either. Offline, the local copy syncs when the connection is back. The
  newer of the local and server draft is offered on return. Interacts with D3: a draft records the
  record version it began on.

**D9 Two-factor authentication** (medium)
- [ADR 0004](adr/0004-authentication.md) lists MFA as a next step; nothing is built. Decide in the ADR
  whether it is enforced by the identity provider or by the application: TOTP enrolment with a QR
  code, single-use recovery codes, an administrator policy (off, optional, required per role) and a
  reset by an administrator that is audited (D6).
- Passkeys (WebAuthn) as a later second factor; the customer portal can opt in separately.

**D10 Data import framework** (large, shared importer, XLSX/ODS and background jobs done, [ADR 0067](adr/0067-data-import-framework.md); Parquet and further entities open)
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
- File storage: moved off PostgreSQL `bytea` to the filesystem (PR #104).

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
