# Leptos Web UI Module Parity & Implementation Plan

> **For implementers:** Execute one item per isolated git worktree and pull request branched from `origin/main`, verifying each item against the OpenAPI drift check, formatter, clippy, native/WASM tests, trunk release build, and Leptos Playwright E2E suite before merging.

**Goal:** Reach full operational parity between the Leptos CSR web interface (`crates/web-ui/` + `crates/api-client/`) and the Flutter desktop/web application (`app/lib/`).

**Baseline (`origin/main`):**
- Backend API surface (`api/openapi.json`): **647 operations across 475 paths**.
- Typed WASM HTTP client (`crates/api-client`): **95 path templates** covered.
- Existing live Leptos modules: Products (core CRUD), Customers (core CRUD), Quotations (core workflow), Orders (list/detail/send/confirm), Purchasing (Suppliers only), Helpdesk (tickets + prepared answers), To-do (core checklist), Knowledge Base (public reader + staff articles), Customer Portal (tickets + order confirm), Administration (9 of 11 sections), and Tutorial overlay.

---

## 1. Missing Modules in Leptos (Present in Flutter)

### A. Stubbed as `PlaceholderPage` in Leptos (7 modules)

| # | Module | Flutter Routes & Feature Dir | Backend API Surface | Dependencies (`crates/core/src/modules.rs`) |
|---|---|---|---|---|
| 1 | **Price Lists** | `/price-lists`, `/price-lists/:id` (`app/lib/features/price_lists/`) | 16 endpoints (`products` tag: lists, groups/chapters, items, zones, export profiles, export plan, render) | `products` |
| 2 | **Opportunities** | `/opportunities`, `/opportunities/:id` (`app/lib/features/opportunities/`) | 13 endpoints (`crm` tag: list, pipeline Kanban, stages, site baseline items/import/source, match rules & product matches) | `customers` |
| 3 | **Delivery** | `/delivery`, `/delivery/settings`, `/delivery/:id` (`app/lib/features/delivery/`) | 11 endpoints (`delivery` tag: list/detail/edit, serial unit picks, ship, cancel, PDF, closure settings, order deliveries) | `sales`, `inventory` |
| 4 | **Repairs** | `/repairs`, `/repairs/departments`, `/repairs/:id` (`app/lib/features/repairs/`) | 21 endpoints (`repairs` tag: CRUD, status, findings, notes, photos, serial unit, warranty check/override/recheck, routing, departments, ticket repairs) | `customers` |
| 5 | **Production** | `/production`, `/production/release`, `/production/divisions`, `/production/work-centres`, `/production/capacity`, `/production/board`, `/production/:id` (`app/lib/features/production/`) | 38 endpoints (`production` tag: orders, release queue, divisions, work centres/hours/closures, capacity, planning board, operations, component reservations/serials/sub-builds, completion, cost rollup, PDF) | `sales`, `inventory`, `engineering` |
| 6 | **Inventory (Stock)** | `/stock`, `/stock/warehouses`, `/stock/counts`, `/stock/counts/:id`, `/stock/products/:id` (`app/lib/features/inventory/`) | 32 endpoints (`inventory` tag: stock balances, warehouses/locations, UoMs, lots, moves/reversals, receipts/issues/transfers/adjustments, cycle counts, reservations, order availability, integrity/rebuild) | `products` |
| 7 | **Finance** | `/finance`, `/supplier-invoices/:id` (`app/lib/features/finance/` — Supplier Invoices, Customer Invoices, Annual Rebates, Match Settings) | 31 endpoints (`finance`: 12; `customer_billing`: 19 — AP invoices & 3-way match/approve/dispute/pay, customer invoices/credits/legacy/post/PDF, annual rebate schedules/assignments/history/rates/settings) | `purchasing` |

### B. Completely Absent from Leptos Routes & Navigation (10 modules)

| # | Module | Flutter Routes & Feature Dir | Backend API Surface | Dependencies |
|---|---|---|---|---|
| 8 | **Engineering (BOMs & Serial Genealogy)** | Embedded tabs in `ProductScreen` (`bom_tab.dart`, `serials_tab.dart`) | 13 endpoints (`engineering` tag: BOM revisions/explode/activate, serials CRUD, component genealogy, status, warranty) | `products` |
| 9 | **Incoming Packages & Repair Intake** | `/packages`, `/intake` (`app/lib/features/packages/`) | 11 endpoints (`repairs` tag: packages CRUD, open/close, photos, repair suggestions, link/unlink repairs) | `repairs` |
| 10 | **Field Service** | `/jobs`, `/jobs/:id`, `/jobs/contracts`, `/jobs/contracts/:id`, `/jobs/equipment/:customerId` (`app/lib/features/field/`) | 33 endpoints (`field` tag: jobs & my-jobs, tasks, work logs, parts, equipment, photos, signature/declined, report PDF & email, maintenance contracts & upcoming jobs, customer equipment) | `customers` |
| 11 | **Planning Board** | `/planning`, `/planning/settings` (`app/lib/features/planning/`) | 19 endpoints (`planning` tag: resource board, agenda, backlog, job scheduling, conflict & skill suggestions, working hours, absences, skills) | `field` |
| 12 | **MRP** | `/mrp` (`app/lib/features/mrp/`) | 5 endpoints (`mrp` tag: runs, proposals list, convert to PO/production, dismiss) | `production`, `inventory`, `purchasing` |
| 13 | **Shipping Requests** | `/shipping` (`app/lib/features/shipping/`) | 3 endpoints (`sales` tag: list shipping requests, request quote, quote shipping) | `sales` |
| 14 | **Product Configurator (Runner & Builder)** | `/configurator`, `/configurator/configurations/:id`, `/configurator/builder`, `/configurator/builder/models/:id`, `/configurator/builder/revisions/:id` (`app/lib/features/configurator/`) | 19 endpoints (`configurator` tag: models, revisions, activate, evaluate, expression check, function catalog, import/export, saved configurations, convert to quotation) | `products`, `sales` |
| 15 | **Reports & Report Builder** | `/reports`, `/reports/new`, `/reports/:id`, `/reports/:id/edit`, `/reports/schedules` (`app/lib/features/reports/`) | 14 endpoints (`reports` tag: catalog, saved reports CRUD, ad-hoc & saved run, export, scheduled report emails & test send) | Cross-module (read-perm gated) |
| 16 | **Home / Workspace Overview** | `/home` (`app/lib/features/home/`) | Aggregates open workspace tabs, To-do summary, open Helpdesk tickets, recent Quotations, recent POs | Shell / Cross-module |
| 17 | **Company Bootstrap Setup Wizard** | `/setup` (`app/lib/features/setup/`) | 2 endpoints (`core` tag: `GET /api/v1/setup/status`, `POST /api/v1/setup/bootstrap`) | Unauthenticated / core |

---

## 2. Partial Modules in Leptos (Missing Sub-Modules & Major Parity Gaps)

| Module in Leptos | What Exists | Missing Parts (vs Flutter) |
|---|---|---|
| **Purchasing** (`pages/suppliers.rs`) | Suppliers list/CRUD + supplier-product prices | **Purchase Orders** segment & detail (`/purchase-orders/:id`, lines, goods picker, approve/send/cancel, VAT check); **Goods Receipts** (`/goods-receipts/:id`, receive dialog) |
| **Products** (`pages/products.rs`) | Basic product list & CRUD drawer | **Engineering** (BOM & Serials tabs), **Media & 3D GLB viewer**, **Prices tab & Bulk price adjustment**, **Options**, **Power grids & voltage ranges**, **Families**, **Packaging categories**, **Product relations**, **Site suitability**, CSV export/import |
| **Customers** (`pages/customers.rs`) | Basic customer list & CRUD drawer | **Mail Merge & Opt-outs** (`/customers/mail-merge`), **Contacts**, **Customer Rebates**, **Closures**, **VIES VAT check**, smart counts, CSV export/import |
| **Quotations** (`pages/quotations.rs`) | List, create/edit, send, accept, convert | **PDF download**, **Revise / Reject / Repricing**, **Configured quotations**, **Sales Favorites** (6 endpoints), **Options & line remark history**, **Pricing preview**, shipping quote trigger |
| **Orders** (`pages/orders.rs`) | List, detail, send, confirm | **Order editing & Cancel**, **Order Revisions & Revision PDF**, **Priority & priority requests**, embedded **Deliveries / Stock / Production** panels |
| **Helpdesk** (`pages/helpdesk.rs`, `pages/answers.rs`) | Tickets CRUD, team/owner assignment, replies/notes, attachments, tags, time entries, prepared answers | Sub-pages: **`/helpdesk/settings`** (mailboxes, SLA notices), **`/helpdesk/calendar`**, **`/helpdesk/automation`**, **`/helpdesk/reports`**, **Kanban board**. Ticket actions: **Checklists**, **Merge / Split / Links & Bundles**, **Escalation / Delegation / Watchers / Soft presence / Live updates**, **Phone calls**, **KB suggestions & Library PDF picker**, convert to quotation/repair |
| **Knowledge Base** (`pages/kb.rs`, `pages/kb_staff.rs`) | Public reader + staff article CRUD/publish/archive | Sub-pages: **`/kb/documents`** (Document Library drafts/revisions/publish), **`/kb/categories`** (category CRUD). Entry features: **images upload/delete**, **version history & restore**, tags & related articles |
| **Customer Portal** (`pages/portal.rs`) | Login link/session, profile view, tickets, order confirm (inside staff `AppShell`) | **Portal Repairs** (`/repairs`, announce + photos), **Portal Help/KB & votes** (`/help`), public **`/csat`** & **`/unsubscribe`** pages, ticket attachments, order priority requests, profile edit, standalone layout outside staff `AppShell` |
| **Admin** (`pages/admin/`) | 9 of 11 tabs live (Users, Modules, Company + Languages + Interface Translations, VAT, Price Zones, Attributes, Identity Providers, Audit Trail, Imports) | **Site Baseline Types** (`/admin/baseline`) and **Configurator Builder** shortcut |
| **To-do** (`pages/todo.rs`) | Full task/sub-item CRUD, complete/reopen, filters | **Record linking & `ObjectTodosButton`**, colleague hand-over, global **Quick-add**, live **nav badge** count |

---

## 3. Cross-Cutting Shell & Infrastructure Gaps

1. **Permission- & module-gated navigation (`shell.rs`):** Filter sidebar items by `me.permissions` and enabled modules (`me.modules`), aligning groups with `app/lib/core/navigation/app_groups.dart`.
2. **Real deep-link & workspace tab routing (ADR 0041):** Replace `WorkspaceTabPlaceholder` with mounted detail views and deep-link `/<entity>/:id` routes.
3. **Reusable UI components (`crates/web-ui/src/components/`):**
   - Extract shared `spawn_api`, request-generation staleness guards, `FeedbackView`, file upload, and authenticated Blob/PDF download helpers out of `pages/admin/mod.rs`.
   - Generic `EntityTable` (search, sort, filters, group-by, pagination, saved favourites).
   - `SearchPicker` (`Many2One` async selector), `DecimalInput`, `ConfirmDialog`, `AuditHistoryModal`, `ConcurrentEditBanner`.
   - Generic `KanbanBoard` (Opportunities & Helpdesk) and `ResourceBoard` timeline grid (Field Planning & Production Work-Centre Board).
4. **Chatter & Activities (`chatter` tag, 18 endpoints):** Reusable side panel on detail screens + Inbox view.
5. **Global Search (`Ctrl+K`), Notifications, Keyboard Shortcuts, Environment & Worker Health banners.**

---

## 4. Phased Implementation Plan

### Phase 0 — Platform & Shared UI Foundation
- [ ] **PR 0.1 — Shell Parity, `/home`, `/setup`, Environment & Worker Health Banners**
  - Permission- and module-gated navigation in `crates/web-ui/src/components/shell.rs`.
  - Environment banner (`GET /api/v1/meta/environment`) and admin-only Worker health banner (`GET /api/v1/admin/worker`).
  - `/home` (`HomePage` role-aware overview cards) and `/setup` (`SetupPage` first-company bootstrap wizard).
  - Placeholder routes for remaining Flutter destinations (`Configurator`, `Packages`, `Intake`, `Jobs`, `MRP`, `Shipping`, `Planning`, `Reports`).
- [ ] **PR 0.2 — Shared Leptos UI Primitives**
  - Promote `spawn_api`, generation guards, `FeedbackView`, file upload, and Blob/PDF download to `crates/web-ui/src/components/`.
  - Add reusable `EntityTable`, `SearchPicker`, `DecimalInput`, `Modal`/`ConfirmDialog`, and `SegmentedTabs`.
- [ ] **PR 0.3 — Real Workspace Tabs, Deep Links, Chatter & Global Search**
  - Replace `WorkspaceTabPlaceholder` with mounted detail screens for `/<entity>/:id` routes.
  - Add `crates/api-client/src/chatter.rs` (18 endpoints), reusable `ChatterPanel`, and Inbox drawer.
  - Add `GlobalSearch` modal (`Ctrl+K`) and To-do `ObjectTodosButton` + sidebar badge.

### Phase 1 — Core Commercial & Supply-Chain Loop
- [ ] **PR 1.1 — Purchasing Completion (Purchase Orders & Goods Receipts)**
  - Complete the 19 `purchasing` endpoints in `crates/api-client`.
  - Segmented `/purchasing` hub (`Suppliers` | `Purchase Orders`) + `/purchase-orders/:id` and `/goods-receipts/:id`.
- [ ] **PR 1.2 — Inventory (Stock)**
  - Add `crates/api-client/src/inventory.rs` (32 endpoints).
  - Implement `/stock`, `/stock/products/:id`, `/stock/warehouses`, `/stock/counts`, `/stock/counts/:id`, and `OrderStockPanel`.
- [ ] **PR 1.3 — Delivery & Shipping Requests**
  - Add `crates/api-client/src/delivery.rs` (11 endpoints) + 3 shipping-request endpoints in `sales.rs`.
  - Implement `/delivery`, `/delivery/:id`, `/delivery/settings`, `OrderDeliveriesPanel`, and `/shipping`.
- [ ] **PR 1.4 — Price Lists**
  - Add 16 price-list endpoints in `crates/api-client/src/price_lists.rs`.
  - Implement `/price-lists` and `/price-lists/:id` (groups/chapters, items, zones, export profiles, export plan & render).
- [ ] **PR 1.5 — Finance & Customer Billing**
  - Add `crates/api-client/src/finance.rs` (12 endpoints) and `crates/api-client/src/customer_billing.rs` (19 endpoints).
  - Implement `/finance` segmented hub (`Supplier Invoices` + `/supplier-invoices/:id`, `Customer Invoices`, `Annual Rebates`, `Settings`).

### Phase 2 — CRM Pipeline, Engineering & Manufacturing
- [ ] **PR 2.1 — Opportunities, Site Baseline & Reusable Kanban**
  - Reusable `KanbanBoard` component + `crates/api-client/src/opportunities.rs`.
  - Implement `/opportunities`, `/opportunities/:id`, and `/admin/baseline` (Site Baseline Types).
- [ ] **PR 2.2 — Engineering (BOMs & Serials) & Full Product Detail Tabs**
  - Add `crates/api-client/src/engineering.rs` (13 endpoints) + remaining `products` endpoints.
  - Upgrade `/products/:id` with BOMs, Serials, Media (with 3D GLB viewer), Prices & Bulk adjust, Options, Power Grids, Related, and Suitability tabs.
- [ ] **PR 2.3 — Production, Reusable Resource Board & MRP**
  - Reusable `ResourceBoard` grid + `production.rs` (38 endpoints) and `mrp.rs` (5 endpoints).
  - Implement `/production`, `/production/release`, `/production/divisions`, `/production/work-centres`, `/production/capacity`, `/production/board`, `/production/:id`, `OrderProductionPanel`, and `/mrp`.

### Phase 3 — After-Sales Service, Field Operations & Planning
- [ ] **PR 3.1 — Repairs, Incoming Packages & Intake**
  - Add `crates/api-client/src/repairs.rs` (32 endpoints).
  - Implement `/repairs`, `/repairs/departments`, `/repairs/:id`, `/packages`, and `/intake`.
- [ ] **PR 3.2 — Field Service (Jobs, Contracts & Equipment)**
  - Add `crates/api-client/src/field.rs` (33 endpoints).
  - Implement `/jobs`, `/jobs/:id`, `/jobs/contracts`, `/jobs/contracts/:id`, and `/jobs/equipment/:customerId`.
- [ ] **PR 3.3 — Planning Board**
  - Add `crates/api-client/src/planning.rs` (19 endpoints).
  - Implement `/planning` (reusing `ResourceBoard`, agenda, backlog, schedule/conflicts/suggestions) and `/planning/settings`.

### Phase 4 — Configurator & Custom Reports
- [ ] **PR 4.1 — Product Configurator (Runner & Builder)**
  - Add `crates/api-client/src/configurator.rs` (19 endpoints).
  - Implement `/configurator`, `/configurator/configurations/:id`, `/configurator/builder`, `/configurator/builder/models/:id`, `/configurator/builder/revisions/:id`, and Admin builder link.
- [ ] **PR 4.2 — Custom Reports, Report Builder & Schedules**
  - Add `crates/api-client/src/reports.rs` (14 endpoints).
  - Implement `/reports`, `/reports/new`, `/reports/:id`, `/reports/:id/edit`, and `/reports/schedules`.

### Phase 5 — Deep Parity on Existing Leptos Modules
- [ ] **PR 5.1 — Customers, Quotations & Orders Deep Parity**
  - Customers: Contacts, Closures, Rebates, VIES check, `/customers/mail-merge`, CSV import/export.
  - Quotations & Orders: Favorites, PDF/revise/reject/repricing/options/remarks/pricing preview, order edit/cancel/revisions/priority.
- [ ] **PR 5.2 — Helpdesk & Knowledge Base Deep Parity**
  - Helpdesk: `/helpdesk/settings`, `/helpdesk/calendar`, `/helpdesk/automation`, `/helpdesk/reports`, Kanban board, checklists, merge/split/links/bundles, escalation/delegation/watchers/presence/live updates, calls, KB suggestions & library PDFs.
  - KB: `/kb/documents`, `/kb/categories`, entry images, version history & restore.
- [ ] **PR 5.3 — Customer Portal Full Parity & Standalone Surface**
  - Standalone Portal shell/routes outside staff `AppShell`, public `/csat` and `/unsubscribe`, Portal Repairs, Portal Help/KB & votes, ticket attachments, order priority requests, and profile editing.

---

## 5. Per-PR Verification Gate

Every PR must pass all checks inside its dedicated worktree before commit:

```bash
./scripts/gen-api-client.sh --check
cargo fmt --all --check
cargo clippy -p tradocraft-api-client -p tradocraft-web-ui --all-targets -- -D warnings
cargo test -p tradocraft-api-client -p tradocraft-web-ui
cargo check -p tradocraft-api-client -p tradocraft-web-ui --target wasm32-unknown-unknown
(cd crates/web-ui && trunk build --release)
(cd e2e && npm run test:leptos)
```
