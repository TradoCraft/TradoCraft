# tradocraft

An integrated business platform for a manufacturing and service company:
CRM, quotations, products, inventory, production, repairs, field service, helpdesk and invoicing,
built to progressively replace a CRM and an external accounting package. Inspired by the breadth of open-source ERPs, built around
our own processes.

**Stack:** Rust (Axum, SQLx) · PostgreSQL · Flutter (Windows, Android, iOS, web) · Typst for PDFs.

> Status: **vertical slice**. Customers and opportunities, products with families and five price
> zones, customer rebates (product / family / general), net and indicative prices, bulk price
> changes, quotations with revisions and server-side pricing (incl. earlier price lists), sales
> orders, a helpdesk (e-mail tickets, phone calls, prepared answers in five languages, production questions),
> contacts with their own language and form of address, a customer portal, PDF output, multi-level bills of materials
> with revisions, serial numbers with as-built genealogy, generated Dart API client and a Flutter app.
> See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the target architecture and roadmap.

## Repository layout

```
apps/api/            HTTP server: wires modules, OpenAPI, migrations, integration tests
crates/core/         errors, auth (OIDC / dev), companies, numbering, audit trail
crates/pricing/      pure pricing engine (no I/O): zone prices, discounts, rounding, VAT
crates/crm/          customers, contacts (people), per-company commercial terms, opportunities
crates/products/     products, price zones, price history
crates/sales/        quotations: drafts, snapshots, revisions, PDF data
crates/engineering/  BOM revisions, explosion, serial units and genealogy
crates/helpdesk/     tickets from e-mail and phone, threading, prepared answers, outbox, IMAP
crates/portal/       customer portal: passwordless login for contacts, their tickets, repairs and profile
crates/repairs/      repairs customers send in, workshop departments, routing workflow, photos
crates/fieldservice/ jobs at customer sites for technicians: tasks, work logs, photos
apps/worker/         background worker: IMAP polling, sending the e-mail outbox, heartbeat
apps/portal-api/     customer-facing HTTP server: only the portal, public knowledge base and survey routes
crates/documents/    Typst PDF rendering, Belgian number formatting
migrations/          SQLx migrations (one PostgreSQL schema per module)
templates/           Typst document templates (nl / fr / en)
seed/                development seed data (fictitious)
api/openapi.json     generated API contract (source of the Dart client)
app/                 Flutter application
docs/                architecture and decision records
```

## Running locally

Prerequisites: Rust (stable), PostgreSQL 16, [Typst](https://typst.app) CLI, Flutter SDK.

```bash
docker compose up --build
```

or without Docker, against a local PostgreSQL:

```bash
cp .env.example .env    # adjust DATABASE_URL
set -a; source .env; set +a
cargo run -p tradocraft-api
```

The API listens on `http://localhost:8080`; interactive API docs are at `/docs`.
With `SEED_DEV_DATA=true` a demo company is created with users `admin@example.com`,
`sales@example.com`, `manager@example.com` (sales manager), `support@example.com`,
`production@example.com`, `viewer@example.com` and `integration@example.com` (a service account
that imports configured quotations and can read customers, products and all quotations of the
company, but cannot edit or send them by hand) (development authentication only). The seed also loads a
demo configurator, a fictitious conveyor line
(`seed/configurators/conveyor_line.json`, [ADR 0034](docs/adr/0034-configurators.md)). `EXTRA_SEED_DIR`
adds your own `*.sql` demo data after the seed, and `TEMPLATE_DIR` points at your own Typst
document templates (see `.env.example`). The seed runs only once, on an empty database, so set
`EXTRA_SEED_DIR` before that first start; setting it later and restarting does not run the files.
`docker-compose.yml` does not pass `EXTRA_SEED_DIR` to the API: to use it with Docker Compose, add
it to the `api` service's `environment` and mount the directory into the container (a `volumes`
entry), or use the setup without Docker.

Environments ([ADR 0043](docs/adr/0043-environments.md)). Each environment is its own database
and its own API instance. `APP_ENV_KIND` (`live`, the default, `test` or `tutorial`; anything
else stops the API at start-up) and `APP_ENV_NAME` (default: the database name) say which one
this is. `GET /api/v1/meta/environment` returns `{name, kind, db_name, version}` without signing
in (never the host, user or password). The app keeps a list of environments, switches between
them from the account menu or the login page, and always shows the active one in a banner: red
for live, amber for test, blue for tutorial.

Test environments. `scripts/envctl clone <database> <name> [--anonymize]` copies a database
(`pg_dump | pg_restore`), clears credentials and starts a separate API instance with
`APP_ENV_KIND=test`; outside `live` the API and worker force `MAIL_TRANSPORT=files` and do not poll
IMAP unless `ALLOW_INBOUND_MAIL_IN_NON_LIVE=1`
([ADR 0048](docs/adr/0048-environment-clones-and-outbound-safety.md),
[runbook](docs/runbooks/test-environments.md)).

Story-mission tutorial. `scripts/tutorial-env up` creates a clean, throwaway environment of kind
`tutorial` with the demo data and prints its address; add that address in the app (login page >
Environments), sign in as `admin@example.com` and start it from the account menu > Tutorial.
`scripts/tutorial-env reset` replays it from chapter 0
([runbook](docs/runbooks/test-environments.md#do-the-tutorial-in-three-commands)).

Worker (helpdesk e-mail). By default outgoing mail is written to `./outbox` as `.eml` files;
set `MAIL_TRANSPORT=smtp` and `SMTP_*`, and `IMAP_*` to fetch incoming mail (see `.env.example`):

```bash
cargo run -p tradocraft-worker
```

Flutter app (in Dutch, French, English, German or Spanish; choose in the account menu):

```bash
cd app
flutter run -d windows     # or: -d chrome, -d <android device>
```

Sign in with server `http://localhost:8080` and a development user e-mail.

Several windows at once (for instance an admin and a sales user): start each as a named
profile. A profile has its own sign-in, language, offline queue and open tabs, stored in a file
of its own (`<app support dir>/profiles/<name>.json`), and its name and roles show in the window
title and in the navigation. Without a profile the app behaves as before.

```bash
scripts/run-profile.sh admin
scripts/run-profile.sh sales      # in a second terminal
# or by hand: flutter run -d linux --dart-entrypoint-args=--profile=sales
#             TRAYD_PROFILE=sales ./tradocraft_app
```

Detail screens (tickets, quotations, orders, repairs, jobs, products, opportunities, stock, KB
articles) open in tabs above the work area: a tab keeps its screen (unsent reply, half-edited
quote) while you work in another one. Middle-click or ctrl-click a list row to open it in the
background, right-click or long-press for "open in new tab", middle-click a tab to close it. Open
tabs are restored on restart, per profile. See [ADR 0041](docs/adr/0041-workspace-tabs.md).

Customer portal (a separate web build; the demo data has portal users such as
`jan.peeters@alpha.example`). The login link is e-mailed by the worker, so with
`MAIL_TRANSPORT=files` open the newest `.eml` in `./outbox`. The company needs a `portal_url`
(the demo company has one):

```bash
cd app
flutter run -d chrome --web-port 8081 -t lib/portal/portal_main.dart \
  --dart-define=PORTAL_API_URL=http://localhost:8080 \
  --dart-define=PORTAL_COMPANY_ID=00000000-0000-7000-8000-000000000001
```

Putting the portal on the internet ([ADR 0050](docs/adr/0050-portal-surface.md),
[runbook](docs/runbooks/customer-portal.md)). Do not publish the API for it. Customers talk to a
second, small server built from the same code, `tradocraft-portal-api`, which has the portal,
public knowledge base and survey routes and nothing else: no staff routes, no `/docs`, no setup
wizard. It limits requests per client address, answers only the portal's own browser origin and
has its own small database pool. The API stays on the internal network. Locally it listens on
`http://localhost:8090` (`docker compose up` starts it too); point the portal build at it with
`--dart-define=PORTAL_API_URL=http://localhost:8090`:

```bash
cargo run -p tradocraft-portal-api    # after the API has started once (it migrates the database)
```

The API itself answers browsers only from `CORS_ALLOWED_ORIGINS` (any origin with
`AUTH_MODE=dev`, none by default with `AUTH_MODE=oidc`); the Windows and mobile apps are not
affected.

Repairs and field service (seed users, all in development authentication): `support@example.com`
registers and routes repairs; `electronics@example.com` and `mechanic@example.com` work in their
departments; `admin@example.com` creates departments (Repairs → Departments);
`dispatcher@example.com` plans jobs and `technician@example.com` sees only their own ("Jobs").
Photos are JPEG/PNG/WebP up to 12 MB and are stored in the database.

Staff manage the people at a customer under Customers → Contacts, look up a caller with
"Who is calling?" in the helpdesk, and give a contact portal access in the contact form.

## First run: a new company

Without the demo seed (`SEED_DEV_DATA` unset) a new database is empty. Start the app, point it at
the server and choose "Set up a new company" on the sign-in screen (or in the add-environment
dialog). The wizard asks for the company (name, legal name, VAT number, country, currency,
language) and its first administrator, and creates the basics: numbering, a warehouse with its
locations and the price zones Z1-Z5 (units of measure ship with the migrations; no demo
catalogue). It works once, only while no company exists
([ADR 0047](docs/adr/0047-company-bootstrap.md)).

* `AUTH_MODE=dev`: the admin e-mail becomes the dev user and the app signs in as that user.
  `BOOTSTRAP_TOKEN` is optional.
* `AUTH_MODE=oidc`: set `BOOTSTRAP_TOKEN` (a long random string) before starting, or the setup
  endpoint answers 404. The wizard asks for it. Afterwards the administrator signs in through the
  identity provider with the same e-mail address; remove the token from the environment.

Without the app: `curl -X POST localhost:8080/api/v1/setup/bootstrap -H 'content-type:
application/json' -d '{"name": "Acme", "country_code": "BE", "currency": "EUR",
"default_language": "en", "admin_email": "me@acme.example", "admin_display_name": "Me",
"token": "..."}'`.

## Tests

```bash
cargo test                                   # unit tests + API tests (needs DATABASE_URL, typst)
cd app && flutter analyze && flutter test
```

API integration tests use `sqlx::test`, which creates a throw-away database per test, so
`DATABASE_URL` must point at a server where that user may create databases.

## Changing the API

The Dart client is generated from the Rust code. After changing endpoints or types:

```bash
./scripts/generate-api-client.sh
```

CI fails if `api/openapi.json` or the generated client is out of date.

## License

AGPL-3.0-or-later. See [LICENSE](LICENSE).
