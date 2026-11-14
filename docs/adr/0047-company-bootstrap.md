# 0047 — Company bootstrap

**Status:** Accepted

**Context.** A new, empty database (a tutorial environment, ADR 0043, or a first production
install) could only become a working company by loading `seed/dev_seed.sql` (demo data, well-known
users, dev authentication only) or by hand-written SQL. We want to do it from the app.

What a company needs to be usable, as found in the migrations and `crates/core`:

* `core.companies` (name, VAT number, country, currency, default language; `legal_name` is new
  in this change), `core.users` (global; unique on lower-case e-mail) and `core.user_companies`
  (the membership with `roles` and `is_default`; a request without `X-Company-Id` needs a default
  membership, and `AuthConfig::Oidc` finds users by e-mail and binds `oidc_subject` on first sign-in).
* Numbering: `core.number_sequences` rows are created on first use by `numbering::next_number`
  (upsert), so none are required; creating them up front makes the sequences visible and starts
  them at 1. Codes in use: opportunity, quotation, order, ticket, repair, job, package, DN, GR, PO,
  CNT, MO, SC (per year) and KB (year 0).
* Stock: purchasing, delivery, production and counts need a warehouse with an internal location
  and the virtual locations (supplier, customer, production_*, transit, adjustment, scrap; these
  are otherwise created on first use).
* Price zones (`pricing.price_zones`) are per company; the dev seed uses Z1-Z5.
* Units of measure (`inventory.uoms`) are global and filled by a migration: nothing to create.
* VAT: there is no VAT table; the rate is a column on each product and the regime is per customer
  (ADR 0038): nothing to create.
* Module settings (`planning.settings`, `helpdesk.settings`, `delivery.settings`) fall back to
  defaults while the row is missing; modules are all on (`disabled_modules` is empty).
* Customers, products and BOMs are global tables and not needed to start; the dev seed's hard-coded
  ids (`00000000-0000-7000-8000-...`) are used only by the demo data and tests, and stay.

**Decision.** `core::companies::provision(conn, spec)` creates all of this in the caller's
transaction; the bootstrap endpoint wraps it.

*Provision.* Input: name, legal name, VAT number, country, currency, default language, admin
e-mail and display name, validated and normalised (country/currency upper case, language one of
nl/fr/en/de/es, e-mail shape, VAT 4-20 letters and digits). Creates: the company; the admin user
(an existing active user with that e-mail is reused; a deactivated one is a 409) with a membership
holding the role `admin`, the default one if the user has none; the numbering sequences of the
current year; warehouse `MAIN` with location `MAIN` plus the seven virtual locations; price zones
Z1-Z5. No demo catalogue. A company whose name (case-insensitive) already exists is refused with
409. Provision takes an advisory transaction lock, so concurrent provisioning is serialised.

*Endpoints* (both unauthenticated, no company needed, like `/meta/environment`):

* `GET /setup/status` returns `{needs_setup, token_required, auth_mode}`. `needs_setup` is true
  only while `core.companies` is empty and bootstrapping is enabled; `token_required` is true when
  `BOOTSTRAP_TOKEN` is set; `auth_mode` (`dev` or `oidc`) lets the wizard word its last step.
* `POST /setup/bootstrap` takes the provision spec plus an optional `token` and answers 201 with
  the company and the admin summary (id, e-mail, display name, roles; no secrets).

*Rules.* It works only while `core.companies` is empty: inside the transaction, after taking the
advisory lock, the count is checked, so two simultaneous calls give one 201 and one 409. Outside
`AUTH_MODE=dev` the endpoint requires `BOOTSTRAP_TOKEN` to be set; if it is not, it answers 404 and
the status reports `needs_setup: false`. When a token is configured (any mode) the request must
carry it: missing or wrong gives 403, compared in constant time. In dev mode with no token
configured the token is optional. The token is read once from the environment, never logged,
never returned, and its `Debug` output is redacted. The creation is audited
(`company`/`bootstrapped`, with the name and admin e-mail only).

*Per environment.* In dev mode the admin e-mail simply becomes the dev user: the app stores it as
the session's `X-Dev-User` and is signed in as soon as the company exists. With OIDC the admin is
pre-provisioned by e-mail; the first sign-in through the identity provider with that e-mail binds
the subject (ADR 0004 flow) only when the identity provider marks that e-mail as verified (`email_verified` must be true; `preferred_username` is no longer a fallback), so the operator must make sure the IdP account of that e-mail
belongs to the intended person. The wizard shows these instructions instead of signing in.

*App.* A top-level `/setup` wizard (company, legal name and VAT, country, currency and language,
admin, token when `token_required`, review, create), offered by the login screen and after adding
an environment when the server `needs_setup`; it validates like the backend and shows 403, 404
and 409 clearly.

**Consequences.**

* The endpoint is a high-value target while the database is empty: anyone who reaches an empty
  server in dev mode without a token can claim it. Dev mode is already loopback-only; outside it
  the token is mandatory. Use a long random token, and unset it after setup (the empty-database
  rule then keeps the endpoint closed anyway). The token is sent in a request body, so serve the
  API over TLS; there is no built-in rate limit on guesses, so put a high-entropy token and, if the
  server is public, a proxy rate limit in front.
* The app sends the token only to https addresses or loopback http, and never follows a redirect
  of the bootstrap request (a 3xx is an error). A browser build follows redirects inside
  XHR/fetch where Dart cannot stop it, so there it can only detect afterwards that the request
  ended on another origin; https-only targets and mixed-content blocking do the preventing.
* `GET /setup/status` reveals whether a server is empty (not sensitive).
* The legal name is stored (`core.companies.legal_name`) but not yet shown or used on documents.
* Only the first company can be bootstrapped; further companies need a later, authenticated flow
  built on the same `provision`.
* VAT rates and units need no seeding today; if VAT becomes a table, `provision` seeds it.
