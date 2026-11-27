# Architecture decision records

Short records of decisions that are expensive to reverse. Add a new file instead of rewriting an
accepted one; mark superseded records as such.

| # | Decision | Status |
|---|---|---|
| [0001](0001-modular-monolith.md) | Modular monolith in Rust, one PostgreSQL database | Accepted |
| [0002](0002-money-and-pricing.md) | Decimal money and a pure, server-side pricing engine | Accepted |
| [0003](0003-multi-company.md) | Multi-company data model from day one | Accepted |
| [0004](0004-authentication.md) | OIDC authentication, roles per company in the ERP | Accepted |
| [0005](0005-api-contract-and-codegen.md) | OpenAPI generated from Rust, Dart client generated from OpenAPI | Accepted |
| [0006](0006-offline-sync.md) | Narrow, append-only offline sync for technicians | Proposed |
| [0007](0007-ledgers.md) | Ledgers with projections for stock and money | Accepted for stock (0019); finance Proposed |
| [0008](0008-accounting-stays-external.md) | Statutory accounting stays in the accounting package; Peppol via an access point | Accepted |
| [0009](0009-pdf-with-typst.md) | PDF documents with Typst | Accepted |
| [0010](0010-flutter-desktop-first.md) | Flutter, desktop-first for the office | Accepted |
| [0011](0011-bom-revisions-and-serial-genealogy.md) | BOM revisions and serial-number genealogy | Accepted |
| [0012](0012-rebates-price-dates-and-price-changes.md) | Rebates, pricing types, price dates and price changes | Accepted |
| [0013](0013-helpdesk-email-and-languages.md) | Helpdesk: e-mail tickets, prepared answers, orders, five languages | Accepted |
| [0014](0014-contacts-calls-and-customer-portal.md) | Contacts with language and address form, phone calls, customer portal | Accepted |
| [0015](0015-repairs-field-service-and-photos.md) | Repairs and departments, field jobs for technicians, photo storage | Accepted |
| [0016](0016-order-lifecycle.md) | Order lifecycle: revisions, customer confirmation, priority | Accepted |
| [0017](0017-helpdesk-sla-teams-attachments.md) | Helpdesk: SLA and escalation, teams, attachments, tags, merge, time, satisfaction | Accepted |
| [0018](0018-knowledge-base.md) | Knowledge base: five languages, full-text search, versions, portal and public reading | Accepted |
| [0019](0019-inventory-stock-ledger.md) | Inventory: stock ledger, balances, lots, reservations, counts | Accepted |
| [0020](0020-field-service-reports-contracts.md) | Field service: signature, parts, installed base and warranty, service report, maintenance contracts | Accepted |
| [0021](0021-helpdesk-business-hours-automation-reporting.md) | Helpdesk: business hours in the SLA, automation rules, ticket split, reporting | Accepted |
| [0022](0022-technician-offline-queue.md) | Technician offline queue: idempotent field writes, persistent replay queue, read cache | Accepted |
| [0023](0023-helpdesk-collaboration.md) | Helpdesk collaboration: escalation, hand-over, watchers, unread, timeline, soft presence | Accepted |
| [0024](0024-planning-board.md) | Planning board for field jobs: calendars, skills, conflicts, suggestions | Accepted |
| [0025](0025-power-grid-compatibility.md) | Power grids per country, product supply profiles and grid-compatibility warnings | Accepted |
| [0026](0026-shipping-workflow-and-purpose.md) | Shipping-quote workflow, packaging categories and quote purpose | Accepted |
| [0027](0027-product-relations.md) | Product relation rules, computed co-occurrence and quotation conflicts and suggestions | Accepted |
| [0028](0028-modules-and-user-admin.md) | Modules switched off per company and user, and user administration | Accepted |
| [0029](0029-csv-export-import.md) | CSV export and all-or-nothing import of customers and products | Accepted |
| [0030](0030-incoming-packages-and-repair-handover.md) | Incoming packages, repair hand-over, warranty and billing through sales | Accepted |
| [0031](0031-purchasing.md) | Purchasing: Suppliers, Purchase Orders, and Goods Receipts | Accepted |
| [0032](0032-customer-closures.md) | Customer closures: periods in which a customer cannot receive deliveries | Accepted |
| [0033](0033-configured-quotations.md) | Configured quotations: line structure, percent-of-parent pricing and import | Accepted |
| [0034](0034-configurators.md) | Admin-defined configurators: definitions, a safe formula language, evaluation and quoting | Accepted |
| [0035](0035-delivery.md) | Delivery: delivery notes, picking, shipping and the closure policy | Accepted |
| [0036](0036-production.md) | Production: production orders from the BOM, reservation, backflush and output | Accepted |
| [0037](0037-line-remarks-and-product-options.md) | Quotation line remarks, remark history and product options | Accepted |
| [0038](0038-vat-regime-and-surcharges.md) | VAT regime per customer and negative rebates | Accepted |
| [0040](0040-profiles.md) | Profiles: isolated sessions in separate windows | Accepted |
| [0041](0041-workspace-tabs.md) | Workspace tabs for detail screens | Accepted |
| [0042](0042-report-builder.md) | User-defined reports: catalog, definition, query engine, CSV and PDF export | Accepted |
| [0043](0043-environments.md) | Environments: one database and API instance each, kinds live, test and tutorial, banner and switcher | Accepted |
| [0045](0045-story-mission-tutorial.md) | Story-mission tutorial: engine, missions, spotlight, progress, only in test or tutorial environments | Accepted |
| [0046](0046-supplier-invoices-and-three-way-match.md) | Supplier invoices and the three-way match (accounts-payable register) | Accepted |
| [0047](0047-company-bootstrap.md) | Company bootstrap: setup wizard and `POST /setup/bootstrap` create the first company in an empty database | Accepted |
| [0048](0048-environment-clones-and-outbound-safety.md) | Environment clones (pg_dump/pg_restore), envctl, outbound safety policy and clone scrub | Accepted |
| [0049](0049-production-division-membership.md) | Production division membership: members per division, default queue scope (`mine`), unassigned orders always shown | Accepted |
| [0050](0050-portal-surface.md) | Portal surface: a separate customer-facing server with only the portal routes, rate limits, and CORS from configuration | Accepted |
| [0051](0051-material-and-cupertino-as-packages.md) | Material and Cupertino as packages: `material_ui`/`cupertino_ui` replace `package:flutter/material.dart`; Flutter pinned to 3.50.0 | Accepted |
| [0052](0052-worker-heartbeat.md) | Worker heartbeat: one beat row, `GET /admin/worker`, an in-app warning and a "worker was down" mail to administrators | Accepted |
| [0053](0053-interactive-sign-in.md) | Interactive sign-in: OIDC code + PKCE in the app with the `oidc` package behind our own interface, loopback redirect on desktop, `token_use` per provider, Dio interceptor, secure storage | Proposed |
| [0054](0054-helpdesk-mailboxes.md) | Helpdesk mailboxes: several per company, Microsoft Graph (Exchange Online) or IMAP/SMTP, secrets only in the worker environment, replies through the ticket's mailbox | Accepted |
| [0055](0055-configurable-identity-providers.md) | Configurable identity providers: per installation, selected by issuer, hardened verifier, e-mail trust policies, admin API with lock-out safeguards | Accepted |
| [0056](0056-backup-and-restore.md) | Backup and restore: physical base backups with `scripts/backupctl`, grandfather-father-son retention, verify by restoring, restore drill through a clone | Accepted |
| [0057](0057-accent-insensitive-search.md) | Accent-insensitive search: `core.search_fold` (lower and `unaccent`) on column and text, trigram indexes, customers, contacts, products and suppliers | Accepted |
| [0058](0058-vat-number-validation-and-lookup.md) | VAT numbers: EU format and check-digit validation, duplicate warning through a comparison key, VIES lookup that pre-fills and never blocks | Accepted (live VIES request unverified) |
| [0059](0059-audit-trail-viewer.md) | Audit trail viewer: `audit.view` for administrators, cursor-paged endpoints, field-level changes, Admin tab and History button | Accepted |
| [0060](0060-keyboard-shortcuts.md) | Keyboard shortcuts: common business-app chords (Alt, Ctrl on macOS), scoped handler registry, hint badges, web policy (Alt+Shift digits) | Accepted (phase A) |
| [0061](0061-todo-items.md) | To-do items: private to owner and assignee, two levels, polymorphic link without foreign key (permission-gated label), completion rules, `todo` module and `todo.use` | Accepted |
| [0062](0062-sales-favorites.md) | Sales favorites: company-wide main product with options and comments, no prices, customer remarks per language, line fields `customer_remark_language` and `favorite_item_id`, add-only translations | Accepted |
| [0063](0063-work-centres-routings-and-operations.md) | Work centres, routings and operations: calendars and closures, a routing on the BOM revision (copied by a new revision), operations snapshotted and scheduled at release, completion totals for labour, capacity per day, multi-level auto-release for the shortfall, cost roll-up behind `inventory.cost`, a traveller PDF | Accepted |
| [0064](0064-helpdesk-sla-customer-notices.md) | Helpdesk SLA notices to the customer: acknowledgement on creation and optional late notice, per team and priority, in the ticket's language, breach notice only in business hours | Accepted |
| [0065](0065-scheduled-report-mails.md) | Scheduled report mails: one scheduler for saved reports and helpdesk reports, daily/weekly/monthly as CSV or PDF, runs with the owner's current permissions, new permission `reports.schedule`, worker pass through the outbox | Accepted |
| [0066](0066-helpdesk-send-email-action.md) | Helpdesk automation `send_email` action: inline subject and body with placeholders, recipients, queued in the outbox (environment switch-off applies), per rule and ticket loop guard | Accepted |
| [0067](0067-data-import-framework.md) | Data import framework: one importer in core behind an `Importable` trait, CSV/XLSX/ODS readers with typed cells and archive limits, XLSX/ODS export, admin screen with saved column mappings, all-or-nothing background jobs | Accepted |
| [0068](0068-site-baseline-and-product-suitability.md) | Site baseline on opportunities and product suitability: admin-defined attribute definitions, voltage and range suitability on products, a baseline item tree and power grid on the opportunity, motor derivation through configurator lookup tables, advisory product matches | Proposed |
| [0069](0069-dependency-vulnerability-scanning-and-disclosure.md) | Dependency vulnerability scanning (OSV), secret scanning, SBOM and private disclosure; the same checks run locally before a push | Accepted |
| [0070](0070-safer-defaults.md) | Safer defaults for the example setup: dev-mode CORS answers this machine only, labelled and configurable Compose defaults, build context without secrets, Android release signed with the maintainer's own key | Accepted |
| [0071](0071-country-vat-defaults.md) | Country-aware, temporal, and building-age VAT defaults: `core.country_vat_rates`, product VAT categories/overrides, derived customer & quotation regimes (including domestic B2B installation reverse charge), construction age rules, purchasing/AP defaults, and multi-country Typst notices | Accepted |
| [0072](0072-helpdesk-reply-templates.md) | Helpdesk reply templates and ticket language: `kind`, optional `team_id` and `keywords` on prepared answers, ranked `/suggest` endpoint, `answer_id` on `send_email` actions, `tickets.language_source`, `ticket_languages` rule condition | Accepted |
| [0073](0073-concurrent-edit-protection.md) | Concurrent-edit protection and shared live-events channel: row `version` trigger and optional `expected_version` (409 `record_changed`) on customers, quotations, orders and tickets; shared `GET /api/v1/events/records` SSE push channel; Flutter live warning banner and conflict handling | Accepted |
| [0074](0074-price-lists.md) | Price lists: a layout of titled groups and sorted products per company, zone and date, prices looked up at render time, ON REQUEST rules, PDF through Typst and Excel, `price_lists.read/write` | Proposed |
| [0075](0075-helpdesk-live-ticket-updates.md) | Helpdesk immediate change notification (A8): every API ticket mutation and presence published on the shared SSE channel (worker-ingested customer replies do not publish an event and so may not appear live in `TicketScreen`), conversation refreshed live, three-way merge of the property form with a compare dialog, 409 handled as a merge | Accepted |
| [0076](0076-helpdesk-ticket-links-and-bundles.md) | Helpdesk ticket links and bundles (A9): bundle, related and duplicate links shown on both tickets, a one-level bundle, and a bundle mass update (reply, note, status) whose preview is the real action rolled back | Accepted |
| [0077](0077-ui-theme-tokens-and-dark-mode.md) | UI theme tokens and dark mode: colour, spacing, radius and type tokens in `core/theme`, `AppTheme.light()/dark()`, persisted `themeModeProvider` with a System/Light/Dark entry in the user menu, golden-test harness | Accepted |
| [0078](0078-repository-layer.md) | Repository layer for the Flutter app: small generic base (`ListQuery`, `Page`, capability interfaces) wrapping the generated clients, Riverpod providers, errors passed through, incremental migration starting with customers and quotations | Accepted |
| [0079](0079-app-switcher-and-breadcrumbs.md) | Application switcher and breadcrumbs: permission-filtered `AppGroup`s with a launcher grid, rail and bar showing only the active group, a `Section > record` bar above the workspace body and a `Breadcrumbs.report` hook for sub-pages | Accepted |
| [0080](0080-global-search-and-notifications.md) | Global search and notifications centre: Ctrl/Cmd+K palette that fans out to the `q` parameter of the permitted list endpoints, "Go to" for sections, a bell with a client-side aggregated feed (to-dos, worker); server-side search and feed are future work | Accepted |
| [0081](0081-generic-list-view.md) | Generic list view: opt-in sortable headers via `loadQuery(ListQuery)`, resizable and hideable columns, per-user persisted layout, multi-select with bulk actions; grouping, inline edit, facets and saved filters deferred | Accepted |
| [0082](0082-list-sorting.md) | Server-side list sorting: `sort=field` / `sort=-field` (up to 3 keys) on list endpoints, per-endpoint whitelist in `core::sort`, primary-key tiebreak, NULLs last, 422 on unknown keys; pilot on customers, products and quotations | Accepted |
| [0083](0083-list-filters-and-favourites.md) | List filters, facets and favourites: multi-select filters (OR within a filter, AND across filters) shown as chips in the search bar, `filter::values` parser in `core` with `= ANY` binds and 422 on unknown values, first endpoints customers, products and quotations, per-user favourites in the preference store | Accepted |
| [0084](0084-price-flags-and-planned-price-corrections.md) | Three price flags and corrections of planned prices: `non_discountable`, `price_on_request` (price entered per quotation line, required before sending) and `price_is_indicative` (printed marker) replace `pricing_type`; zone prices that have not started can be corrected or deleted, and bulk changes can replace them | Accepted |
| [0085](0085-generic-form-view.md) | Generic form view: `RecordFormController` (dirty, busy, error, 409 and live notice of ADR 0073), `RecordFormView` page with header, actions, status bar, smart buttons, sheet and tabs, `Many2OneField` built on `SearchPicker`; customers moved over, quotations next | Accepted |
| [0086](0086-generic-chatter-and-activities.md) | Generic chatter, followers and activities: polymorphic `(record_kind, record_id)` address, notes with attachments, curated change messages beside the audit trail, record-visible activities (separate from private to-dos), live updates without moving the record version; first kinds customers, quotations, orders and opportunities; tickets not migrated yet | Accepted |
| [0087](0087-generic-kanban-view.md) | Generic kanban view: `KanbanConfig` per entity, columns loaded and paged on the server, optimistic moves that revert on refusal, drag with a 150 ms hold plus a "Move to…" menu for keyboards and screen readers; first use is the opportunity pipeline, no backend change | Accepted |
| [0088](0088-tickets-on-the-kanban-board.md) | Tickets on the kanban board: `POST /tickets/{id}/status` (a status and nothing else, through the shared `change_status`: automation, SLA, timeline, close gate and survey), five status columns with the list's owner switch, a confirmation before closing, moves without a version | Accepted |
| [0089](0089-list-group-by.md) | List grouping: `group_by` is a filter key, `GET /<resource>/groups` returns value counts for the same search and filters (whitelist in `core::group`, at most 200 groups, 422 on absent or unknown key), collapsible group headers in the list that load rows with the group value as filter, grouping stored in favourites; first endpoints customers, products and quotations | Accepted |
| [0090](0090-work-centre-planning-board.md) | Work-centre planning board: day granularity, finite loading (a day offers capacity minus the other operations' load, one operation uses one unit), conflicts of a move (error: inactive centre, started operation, closed day, overload, before the predecessor; warning: after the successor or the planned-ready date), `GET /production/planning-board`, dry-run `PUT .../operations/{id}/move` with `force`, `finite` re-schedule, board on `ResourceBoard` |
| [0091](0091-material-requirements-planning.md) | Material requirements planning: a run nets open order lines, production components, stock and open purchase and production orders per product from the top of the BOMs down, and proposes what to buy or build one lead time before it is needed (floor = larger of safety stock and reorder level, reorder maximum, supplier minimum and order multiple); proposals become draft purchase orders or released production orders, or are dismissed; no permission of its own |
| [0092](0092-no-wildcard-cors-with-dev-auth-or-in-live.md) | No wildcard CORS with dev authentication or in a live environment: the staff API refuses `CORS_ALLOWED_ORIGINS=*` with `AUTH_MODE=dev` or `APP_ENV_KIND=live`; dev authentication on a non-loopback address with `ALLOW_INSECURE_DEV_AUTH=true` warns |
| [0093](0093-helpdesk-ticket-checklists.md) | Helpdesk ticket checklists: ordered items per ticket (done, who and when), templates with optional team and category applied by hand or by the `apply_checklist` automation action, `done/total` badge, a per-team switch that blocks closing with open items (409 `checklist_incomplete`) | Accepted |
| [0094](0094-mcp-pilot.md) | MCP pilot `apps/mcp`: one read-only `get_order` tool over Streamable HTTP, OAuth protected resource (`at+jwt`, exact audience, `orders:read`), hand-provisioned `core.mcp_order_read_grants` mapping subject and client to one user and company, reuses `read_order` | Accepted (pilot) |
| [0095](0095-frontend-ux-navigation-and-home.md) | Navigation ergonomics: list search clear and wrapping header, active group label, top-bar search pill, narrow bar capped at five with a More sheet, permission-gated `/home` overview, product form editable in a workspace tab | Accepted |
| [0096](0096-product-media-and-3d-viewer.md) | Product media and 3D viewer: pictures, SVG (checked), videos and `.glb` models as `core.files` uploads linked by `products.media`, one default per product printed on documents, hover thumbnails, GLB viewer with named nodes, tutorial models auto-staged | Accepted |
| [0097](0097-customer-billing-and-rebates.md) | Customer billing: invoices from shipped delivery lines and credit notes against posted invoice lines, snapshotted with per-rate VAT; turnover from verified opening balances (no ledger); tiered rebate rates reviewed and approved per year; live posting behind `CUSTOMER_BILLING_LIVE_COMPANIES` | Accepted |
| [0098](0098-document-library-and-mail-merge.md) | Document library and customer mail merge: knowledge-base documents with uploaded PDFs in five languages and numbered revisions, attachable to helpdesk replies; one mail-merge draft per user with placeholders, all-or-nothing queue to the outbox, permission `mail_merge.send` | Accepted |
| [0099](0099-mail-merge-opt-out-and-unsubscribe.md) | Mail merge opt-out and unsubscribe: per-company opt-out register keyed by normalised address, opted-out recipients left out of the preview, a one-click unsubscribe link with a hashed token in every mailing, served by the portal server | Accepted |
