# Changelog

All notable changes to TradoCraft are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project follows
[Semantic Versioning](https://semver.org/) as described in [docs/RELEASING.md](docs/RELEASING.md).
Before 1.0.0 a minor version may contain breaking changes; they are listed under **Changed** or
**Removed** and marked **Breaking**.

This file was started after v0.3.0. The entries for v0.2.0 and v0.3.0 were reconstructed from the git
history and the status table in [docs/ROADMAP.md](docs/ROADMAP.md); they name the main user-visible
changes, not every commit. Items in the roadmap are linked to their ADRs in [docs/adr/](docs/adr/).

## [Unreleased]

### Added
- Leptos web frontend (`crates/web-ui`), served by the API at `/app/` and built in the Docker
  image: Helpdesk (find, create, assign, internal notes, replies with attachments, rendered Standard
  Answers), To-do, staff Knowledge Base, Standard Answers management, Products, Customers, Suppliers,
  Quotations, Orders, Portal and public Knowledge Base slices, and a tutorial overlay. It covers the
  four workflows of the v0.4.0 release gate; the Flutter app remains the full client.
- Leptos Administration area at `/app/admin`: users, modules, company (including the logo), VAT rates,
  price zones, attributes, identity providers, audit trail and the import wizard with job history, each
  section gated by the same permissions as in Flutter. Baseline types and the configurator builder
  stay in Flutter.
- Mail-merge consent ([ADR 0099](docs/adr/0099-mail-merge-consent.md)): every customer mailing carries
  an unsubscribe link in the recipient's language that records an opt-out on a public portal page
  without a sign-in. A per-company opt-out register (`/customers/mail-merge/opt-outs`) is managed by
  staff and audited; opted-out addresses are skipped in the preview and confirm refuses if an opt-out
  arrives in between. Confirming a mailing needs a portal address on the company (otherwise 422).
- `tradocraft-api-client`, a WASM-safe Rust API client crate used by the Leptos frontend.
- Playwright specs for the Leptos workflows (`e2e/tests-leptos/`) and wasm-bindgen component tests,
  run in CI.
- Material requirements planning (C2, [ADR 0091](docs/adr/0091-material-requirements-planning.md)):
  runs, proposals and their conversion to draft purchase orders or released production orders;
  safety stock and order multiple on the product; planning proposals page in the Flutter app.
- Work-centre planning board (C3, [ADR 0090](docs/adr/0090-work-centre-planning-board.md)): finite
  loading, dry-run moves with conflicts, a finite re-schedule and a drag-and-drop board.
- Docker `HEALTHCHECK` in the API image (`GET /health`); health checks for the portal server in both
  Compose files.
- Release images are signed with cosign (keyless, GitHub OIDC); the release publishes `SHA256SUMS`
  and its signature bundle. Images are tagged `X.Y.Z` and `X.Y`.
- `docs/RELEASING.md` (versioning policy, release procedure, signature verification) and this file.

### Changed
- **Breaking (deployment):** `docker-compose.yml` and the release `docker-compose.yml` no longer
  default the database password to `tradocraft`. Set `POSTGRES_PASSWORD` (for example in `.env`);
  Compose refuses to start without it. An existing `pgdata` volume keeps the password it was created
  with.
- Docker base images are pinned to exact tags (`rust`, `debian`, `postgres`, `nginx`); the release
  workflow no longer pushes a `latest` tag.
- README status line rewritten.

### Fixed
- Code-scanning alerts: workflow permissions and request-sized pre-allocation.
- Leptos pages no longer panic when left while a request is pending.

## [0.3.0] - 2026-11-25

### Added
- Portable Windows tutorial demo: a ZIP and a per-user setup EXE with bundled PostgreSQL and Typst,
  running offline on fictitious tutorial data (`windows-demo.yml`).
- Interactive tutorial database flow visualizer (`docs/tutorial-db-visualizer.html`).
- `.glb` 3D assembly models on products with a viewer of named nodes; fourteen models bundled with
  the tutorial products.
- Frontend UX phases 1 to 5: search clear button and responsive list header, active group label and
  top-bar search pill, five-item navigation bar with a More sheet, role-aware home overview,
  non-blocking tab editing in the product form.
- List group-by with group counts ([ADR 0089](docs/adr/0089-list-group-by.md)); the generic list and
  record form views now serve more entities (suppliers, products, orders); reusable one-to-many line
  editor; customer smart-button counts.
- Single-line quotation items, configurable autosave and environment ribbon updates; tutorial
  navigation shortcuts and Alt+Home.

### Changed
- Version references bumped to 0.3.0 across Cargo, OpenAPI, the Flutter app and the deploy files.

### Fixed
- Product form refresh after saving and closing a new-product tab; duplicate migration versions;
  model/gltf-binary allowed in `core.files`; stale tutorial product media queued for deletion.

## [0.2.0] - 2026-11-23

First tagged release. It packages the platform as it stood on that date; the modules below are
described in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and the roadmap status table.

### Added
- Rust API (Axum, SQLx, PostgreSQL), background worker and customer-facing portal server, with an
  OpenAPI document and a generated Dart client.
- Flutter app (Windows, Android, iOS, web) with the shared UI framework (theme tokens, dark mode,
  generic list, form and kanban views, chatter and activities; ADR 0077 to 0088).
- Sales: customers, contacts, opportunities, products with price zones, rebates, price lists, quotations
  with revisions, line remarks and options, order lifecycle, customer invoices, correction credits and
  annual rebates, negative unit prices, price flags and planned price corrections.
- Operations: stock ledger, purchasing with supplier invoices and three-way match, delivery,
  production orders, work centres, routings and operations, bills of materials with revisions, serial
  numbers and as-built genealogy.
- Service: helpdesk (SLA, teams, attachments, automation rules, reporting, several mailboxes including
  Microsoft 365, customer mail, reply templates, checklists, live updates, ticket bundles), knowledge
  base, field service with an offline technician queue, planning board for field jobs.
- Platform: customer portal, report builder, data import framework, audit log viewer, concurrent-edit
  protection, VAT number validation and lookup, accent-insensitive search, environment awareness,
  worker heartbeat, backup and restore runbook, document library and mail merge, product media.
- Tutorial environment with chapters 1 to 11, and recorded tutorial videos.
- Release workflow: backend and web Docker images on GHCR, Windows x64 zip, a packaged
  `docker-compose.yml` smoke-tested before publication.
- Safer defaults ([ADR 0070](docs/adr/0070-safer-defaults.md)): loopback-only CORS and dev
  authentication, non-root Docker user, `.env*` excluded from the Docker build context.

[Unreleased]: https://github.com/TradoCraft/TradoCraft/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/TradoCraft/TradoCraft/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/TradoCraft/TradoCraft/releases/tag/v0.2.0
