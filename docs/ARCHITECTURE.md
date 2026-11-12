# Architecture

## Goal

One integrated platform for the full lifecycle of a manufacturing and service business
(20–50 users, make-to-stock and make-to-order, in-house repairs, installation and maintenance teams):

enquiry → quotation → sales order → engineering → purchasing → production → stock → delivery →
installation → maintenance → repair → helpdesk → invoicing

It replaces the CRM (CRM, quotations) first and the accounting package's operational parts (components,
stock, production, invoicing) later. Statutory accounting stays in the accounting package until the operational
system is proven (see [ADR 0008](adr/0008-accounting-stays-external.md)).

## Shape

```
Flutter app (Windows desktop for office, Android/iOS for technicians, web optional)
        │  HTTPS · REST/JSON · OpenAPI (generated Dart client)
Rust API (Axum) — modular monolith
  core · crm · products/pricing · sales · inventory · helpdesk · portal · (production · service · finance)
        │  SQLx, one transaction per business operation
PostgreSQL — one database, one schema per module
  + object storage (documents, photos)
  + worker (apps/worker): IMAP polling, e-mail outbox; later PDF, Peppol, accounting sync

Customers (portal web build)  ──HTTPS──▶  portal server (apps/portal-api): the same crates,
  only the portal, public knowledge base and survey routes; the one server that faces the internet
```

* **Modular monolith** ([ADR 0001](adr/0001-modular-monolith.md)): one deployable, modules as crates.
  A module owns its schema; other modules call its public Rust functions, never its tables.
  Example: `sales` uses `crm::get_customer_for_quoting` and `products::get_products_for_quoting`,
  and accepting a quotation calls `crm::opportunities::mark_won` in the same transaction.
  Read-only joins to another module's tables for display (names, codes) are allowed;
  writes and business rules always go through the owning module.
* **Two servers from one codebase** ([ADR 0050](adr/0050-portal-surface.md)): the staff API stays
  on the internal network; customers reach `apps/portal-api`, which mounts only the customer-facing
  routers and has no staff route, API documentation or setup endpoint in the process at all.
* **Pricing is authoritative on the server** ([ADR 0002](adr/0002-money-and-pricing.md)).
  The app calls `POST /pricing/preview` while editing; it never calculates prices.
* **Multi-company from day one** ([ADR 0003](adr/0003-multi-company.md)).
* **Documents are snapshots**: a sent quotation never changes; changes create a revision.
* **History is never overwritten**: prices are dated rows, audit events are append-only;
  stock is a movement ledger plus a balance projection ([ADR 0019](adr/0019-inventory-stock-ledger.md), [ADR 0007](adr/0007-ledgers.md)).

## Modules

| Module | Status | Owns (schema) |
|---|---|---|
| core | slice | companies, users, memberships/roles, numbering, audit |
| crm | slice | customers, **contacts** (people with roles, language, form of address, e-mails and phones; lookup by e-mail and phone — [ADR 0014](adr/0014-contacts-calls-and-customer-portal.md)), per-company terms (zone, general rebate, payment terms), product/family rebates, opportunities / pipeline, customer closures (periods a customer cannot receive deliveries; [ADR 0032](adr/0032-customer-closures.md)) |
| products / pricing | slice | products, families, typed product attributes (ADR 0034), a default production remark and product options offered with a product on a quotation ([ADR 0037](adr/0037-line-remarks-and-product-options.md)), pricing types (list/net/indicative), price zones, dated zone prices, bulk price changes ([ADR 0012](adr/0012-rebates-price-dates-and-price-changes.md)) |
| sales | slice | quotations (snapshots, price date, revisions keeping or updating prices), linked to opportunities; sales orders from an accepted revision with a draft → sent → confirmed lifecycle, revisions, order confirmation PDF by e-mail, customer confirmation (staff or portal) and priority with history ([ADR 0016](adr/0016-order-lifecycle.md)); configured quotations with sections, options under a parent line, percent-of-parent prices and an idempotent import from an external configurator ([ADR 0033](adr/0033-configured-quotations.md)); a production and a customer remark per line with a history of earlier remarks per customer, language or overall, and required options added as option lines ([ADR 0037](adr/0037-line-remarks-and-product-options.md)) |
| documents | slice | PDF rendering (Typst) |
| engineering | slice | BOM revisions (multi-level via subassemblies), explosion, serial units and as-built genealogy ([ADR 0011](adr/0011-bom-revisions-and-serial-genealogy.md)); routings planned |
| configurator | slice | admin-defined product configurators: models with revisioned JSON definitions (project, group and item fields, lookup tables, computed values, output rules, validations) in a safe formula language, a pure evaluator with traces and pinned overrides, saved configurations that become quotations through the sales import ([ADR 0034](adr/0034-configurators.md)); runner and builder screens planned |
| purchasing | slice | suppliers with price lists (supplier article code, price, MOQ, lead time, preferred flag), purchase orders (draft, approved, sent, partially received, received, cancelled) and goods receipts that post `inventory::post_move` receipts and register serial units ([ADR 0031](adr/0031-purchasing.md)); permissions `purchasing.read/write/approve/receipt`; the app has the supplier screens (list, detail tab, price list), purchase orders and receipts follow; vendor bill matching waits for the finance module |
| delivery | slice | delivery notes for confirmed orders: planned date, picking from the stock reservations, shipping through the stock ledger (order `partially_shipped` / `shipped`), carrier and tracking reference, PDF in five languages; a per-company policy for planning on a day the customer is closed (warn, override with a reason, or block) ([ADR 0035](adr/0035-delivery.md)) |
| inventory | slice | warehouses and locations (incl. service vans), units of measure, lot and serial tracking, an append-only stock move ledger with a balance projection, transfers, adjustments and counts, reservations for confirmed order lines and availability (ATP) on the order ([ADR 0019](adr/0019-inventory-stock-ledger.md)); other modules post moves through `inventory::post_move`; purchasing receipts, valuation and MRP planned; delivery posts the shipment moves (see delivery) |
| production | slice | divisions with their members (the queue defaults to a worker's own divisions, [ADR 0049](adr/0049-production-division-membership.md)) and production orders built from the active BOM (revision frozen at release), released by a planner for an order line or for stock; components reserved at release and backflushed at completion with actual quantities and scrap; output into stock with lots, or serial units with the as-built genealogy; the sales order follows (`in_planning` → `planned` → `in_production` → `ready_for_shipping`) with a promised date ([ADR 0036](adr/0036-production.md)); work centres, routings and MRP planned |
| quality | planned | inspections, non-conformances, traceability |
| service | planned | installed assets (builds on serial units), warranties |
| helpdesk | slice | e-mail-to-ticket (IMAP) with threading and matching, replies via outbox (SMTP), prepared answers in 5 languages, leads / orders / production questions from tickets ([ADR 0013](adr/0013-helpdesk-email-and-languages.md)), phone calls logged on tickets; SLA with escalation, teams, attachments, tags, merge, time entries and satisfaction surveys ([ADR 0017](adr/0017-helpdesk-sla-teams-attachments.md)); a company business calendar with holidays for the SLA, automation rules (created / updated / customer replied, audited, with a dry run), ticket split and a helpdesk report with CSV export ([ADR 0021](adr/0021-helpdesk-business-hours-automation-reporting.md)); per-team calendars, e-mail actions in rules and scheduled report mails planned |
| repairs | slice | repairs customers send in (announced → received → routed → worked → shipped), workshop departments made by the admin, photos ([ADR 0015](adr/0015-repairs-field-service-and-photos.md)); incoming packages: a parcel is registered at the dock, opened, then matched with an announced repair or turned into a new one before routing ([ADR 0030](adr/0030-incoming-packages-and-repair-handover.md), phase 1) |
| field service | slice | jobs at customer sites: address and navigation, instructions, task checklist, work logs, photos; technicians see only their own jobs ([ADR 0015](adr/0015-repairs-field-service-and-photos.md)); customer signature, parts used, equipment with warranty, service report PDF in five languages and maintenance contracts that generate planned jobs ([ADR 0020](adr/0020-field-service-reports-contracts.md)); offline queue and planning board planned |
| kb | slice | knowledge base: categories and articles in 5 languages with Markdown, full-text search per language, versions, tags and related articles, images, suggestions on tickets, helpful votes, reading for staff, portal contacts and the public ([ADR 0018](adr/0018-knowledge-base.md)); attachments other than images, comments, analytics, semantic search, translation workflow and SEO export planned |
| portal | slice | customer portal: passwordless login for contacts, their tickets and profile; Flutter web entry point ([ADR 0014](adr/0014-contacts-calls-and-customer-portal.md)) |
| finance | slice | supplier invoices as an accounts-payable register only (no general ledger): a three-way match of purchase order, goods receipt and invoice with per-company tolerances, approval (with an audited override), dispute and paid status ([ADR 0046](adr/0046-supplier-invoices-and-three-way-match.md)); permissions `finance.read/write/approve`; the app has a Finance section with the supplier invoice list, create dialog, detail tab (match report per line, approve with override reason, dispute, mark paid) and the tolerance settings, plus a "Create supplier invoice" shortcut on received purchase orders; customer invoices, credit notes, Peppol via access point and the accounting integration planned ([ADR 0008](adr/0008-accounting-stays-external.md)) |

## Conventions

* Primary keys: UUIDv7 (`core::new_id`), safe to generate on offline devices.
* Money: `NUMERIC` in PostgreSQL, `rust_decimal::Decimal` in Rust, **strings** in JSON.
* Every business table that belongs to a legal entity has `company_id`.
* Every change of business significance writes `audit.events` in the same transaction.
* Errors: JSON `{ "error": "<code>", "message": "..." }` with 401/403/404/409/422/500.
* Permissions are checked in handlers (`user.require(Permission::...)`); roles map to permissions
  per company.

## Roadmap

1. **Foundation & sales** — customers, opportunities, quotations; next: contacts, activities, sales orders, e-mailing quotes.
2. **Engineering & inventory** — BOM revisions and serial numbers, warehouses, stock ledger, lots, reservations and counts (done); next: routings, configurator, purchasing.
3. **Manufacturing** — MRP for MTS and MTO, production orders, labour, quality.
4. **Service** — installed assets, repairs, field service planning, mobile app with offline sync.
5. **Helpdesk & portal** — tickets from e-mail, prepared answers, orders, contacts, phone calls and a ticket portal (done); SLA, teams, attachments, tags, merge, time entries and satisfaction surveys (done, ADR 0017); business hours, automation rules, ticket split and reporting (done, ADR 0021); knowledge base with portal help and ticket deflection (done, ADR 0018; remaining: attachments other than images, comments and ratings text, analytics, AI/semantic search, translation workflow, SEO export); next: e-mail actions in rules, scheduled report mails, quotations in the portal.
6. **Finance** — supplier invoices and the three-way match (AP register, done); next: customer invoicing, Peppol, payment export, accounting integration.

Each release runs alongside the CRM and the accounting package, with one system clearly owning each kind of record
during the transition.
