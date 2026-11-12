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
| [0052](0052-configurable-identity-providers.md) | Configurable identity providers: per installation, selected by issuer, hardened verifier, e-mail trust policies, admin API with lock-out safeguards | Accepted |
