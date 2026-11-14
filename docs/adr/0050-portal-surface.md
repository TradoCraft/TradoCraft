# 0050 — Portal surface: a separate customer-facing server

**Status:** Accepted

**Context.** The customer portal ([ADR 0014](0014-contacts-calls-and-customer-portal.md)) is the
only part of the system that strangers on the internet must reach. Its own design holds up:
passwordless links, opaque revocable sessions of which only hashes are stored, access re-checked
on every request, and a narrow query layer per module that takes the logged-in contact
(`helpdesk::portal`, `repairs::portal`, `sales::order_portal`, `kb::reader`). The weakness was
where it ran. One process on one listener served everything, so publishing the portal also
published the whole staff API, the interactive API documentation, the setup wizard and the
environment endpoint; it answered every browser origin; nothing limited requests except one login
mail a minute per contact; and customers shared the staff API's database pool.

Options considered:
* *One server, a reverse proxy that forwards only `/api/v1/portal/*`.* Cheap, but the separation
  is one line of proxy configuration that nothing tests, and the staff code is still in the
  process a stranger talks to.
* *A separate application in front that calls the staff API.* It would hold a powerful service
  credential on the most exposed machine and repeat the "what may this contact see" rules, which
  then drift.
* *The same crates, built into a second small server.* Chosen.

**Decision.**
* **`apps/portal-api`** (`tradocraft-portal-api`) mounts `portal::router()`,
  `kb::public::router()` and `helpdesk::csat::router()` under `/api/v1`, plus `/health`. Staff
  routers, `/docs`, the OpenAPI document, `/setup/*` and `/meta/environment` are not in the
  process. A test walks every operation of `api/openapi.json` and requires 404 for everything
  outside those three prefixes, so a new staff module cannot appear there by accident.
  The portal web build (`lib/portal/portal_main.dart`) is unchanged; only `PORTAL_API_URL` points
  at this server. The staff API keeps the portal routes too (tests, single-machine development).
* **No staff sign-in exists there.** It runs with `AuthConfig::Disabled`: the staff extractor
  answers 401 whatever `AUTH_MODE` or headers say.
* **It never migrates.** The staff API owns the schema and starts first.
* **Requests are limited per client address** (`limit.rs`, a token bucket in memory): all routes
  together (`PORTAL_RATE_PER_MINUTE`, 300) and login attempts — asking for a link, exchanging one —
  separately (`PORTAL_LOGIN_RATE_PER_MINUTE`, 10). A refusal is `429` with `Retry-After` and
  `error: rate_limited`. IPv6 counts per /64. `X-Forwarded-For` is believed only when the
  connection comes from `PORTAL_TRUSTED_PROXIES`, and then the right-most address that is not one
  of ours; without that setting the header is ignored. The per-contact mail throttle of ADR 0014
  stays.
* **Every request has a deadline** (`PORTAL_REQUEST_TIMEOUT_SECONDS`, 30; `503`), and the server
  has **its own small database pool** (`PORTAL_DB_MAX_CONNECTIONS`, 5) and may have **its own
  connection string** (`PORTAL_DATABASE_URL`).
* **CORS comes from configuration** (`core::cors`, closes roadmap D7). The portal server answers
  `PORTAL_ALLOWED_ORIGINS`, else the origin of every company's `portal_url`, and refuses to start
  when it knows none. The staff API answers `CORS_ALLOWED_ORIGINS`; unset means any origin with
  `AUTH_MODE=dev` and none with `AUTH_MODE=oidc`.
* **Deployment** ([runbook](../runbooks/customer-portal.md)): a TLS reverse proxy publishes the
  portal's static files and this server on the portal's host name. The staff API is reachable
  from the office network or VPN only.

**Consequences.**
* A web build of the staff app on another origin needs `CORS_ALLOWED_ORIGINS` once the API runs
  with OIDC. Desktop and mobile apps send no `Origin` and are unaffected.
* Changing a company's `portal_url` needs a restart of the portal server (origins are read at
  start), unless `PORTAL_ALLOWED_ORIGINS` is set.
* Limits are per process and in memory: several portal servers behind a balancer each count on
  their own, and a restart forgets the counts. Good enough against guessing and flooding from one
  address; a distributed attack is the reverse proxy's or the hosting provider's job.
* Both servers must run the same version: the portal server expects the schema the API migrated.
* The session token is still in the browser's local storage (ADR 0014), so the portal's origin
  must serve nothing but the portal.

**Later.**
* A PostgreSQL role for `PORTAL_DATABASE_URL` with rights on only the tables the portal layers
  touch (nothing on purchasing, finance, pricing or users), with a test that runs the portal suite
  under it.
* Row-level security for tenant isolation (roadmap checklist).
* Limits shared between instances, if more than one portal server is ever needed.
