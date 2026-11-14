# 0048 — Environment clones and outbound safety

**Status:** Accepted

**Context.** ADR 0043 made an environment one database plus one API instance. Trying things out
safely needs a test environment that holds realistic data, so it is a copy of an existing database.
A copy of live data is dangerous in two ways: the worker would keep fetching the real mailbox and
sending mail to real customers, and the copy contains data that can be used to sign in or that
identifies people.

**Decision.**

*Clone method.* `scripts/envctl clone` creates a new database and fills it with
`pg_dump --format=custom --no-owner --no-acl | pg_restore --no-owner --no-acl --exit-on-error`. The
dump runs in a read-only session, so the source is only ever read, and it can stay in use while it
is copied (the dump is a consistent snapshot). `CREATE DATABASE ... TEMPLATE` is not used: it needs
the source to have no other connections, which a running live API never satisfies, so it would
mean locking live users out while copying. If any step fails the new database is removed again.
The tool refuses an existing target, the database of `DATABASE_URL` as a target, and names that
are not a safe identifier (`^[a-z][a-z0-9_]{0,39}$`).

*Instance model.* Each environment runs as its own API instance (and optionally its own worker)
with its own `DATABASE_URL`, a free port from a configurable range (default 8100-8199, loopback),
`APP_ENV_NAME`, `APP_ENV_KIND` (`test` or `tutorial`), `MAIL_TRANSPORT=files` and a mail directory
inside the environment's own directory. Each instance migrates its database at boot, so a clone of
an older database is brought up to date by the new binary. Attachments and photos are stored in
the database (`bytea`), so a clone carries its own copy; there is no shared file storage.

*Registry.* One plain-text file per environment under `ENVCTL_DIR` (default
`~/.local/share/tradocraft-envs/registry/<name>.env`): name, kind, database, port, url, pid, worker
pid, source and whether it was anonymized. `envctl drop` only drops databases that it created and
registered, and refuses environments registered as `live` (`envctl register <name> --kind live
--database <db>` protects a live database that envctl did not create). `envctl` never creates or
starts a live environment.

*Outbound safety.* One policy, `OutboundPolicy` in `crates/core/src/environment.rs`, applied at
start-up by the API and the worker. For every kind except `live`:

- `MAIL_TRANSPORT` is forced to `files` (e-mail is written as `.eml` files, never sent over SMTP),
  whatever `MAIL_TRANSPORT` and `SMTP_*` say;
- the worker does not poll the IMAP mailbox, even when `IMAP_HOST` is set, unless the explicit
  opt-in `ALLOW_INBOUND_MAIL_IN_NON_LIVE=1` is present (polling marks mail as read in the real
  mailbox, so the opt-in is for a dedicated test mailbox);
- both processes log a WARN banner (`OUTBOUND SAFETY: ...`) saying what is disabled.

The inventory of outbound side effects found in the code: SMTP sending (worker: ticket replies and
system mail through the outbox) and IMAP polling (worker). The OIDC key fetch of the identity
provider is an inbound authentication check, not a side effect, and stays. There are no webhooks,
Peppol calls or other HTTP callbacks yet; a new outbound integration must be gated by
`EnvironmentConfig::outbound_allowed()`.

*Scrub.* `scripts/envctl.d/scrub_credentials.sql` is always applied to a clone: it deletes portal
login links and sessions and CSAT survey links, clears `core.users.oidc_subject` (the next OIDC
sign-in binds by e-mail again) and cancels system mail and ticket replies that were still queued.
Mailbox and SMTP passwords are not in the database (they are worker environment variables), so
they cannot leak into a clone. With `--anonymize`, `scripts/envctl.d/anonymize.sql` also replaces
e-mail addresses and phone numbers of customers, suppliers, the company, contacts and ticket mail
(with `@example.test` addresses), drops raw stored e-mails and mail attachments, and replaces users
who are not an `admin` in any company (admins keep their address so sign-in still works). Not
scrubbed: names, postal addresses, VAT numbers, IBANs, free text (notes, ticket subjects and
bodies), audit data and product and price data. Anonymizing is a privacy aid, not a guarantee.

**Consequences.** A test environment is safe to try things in, but it is a snapshot: it is not
kept in sync with live, and a fresh copy means a new name. `envctl` is an operations tool for a
single host; hosted setups need their own orchestration. The authentication mode is inherited from
the tool's environment (`AUTH_MODE`, default `dev` on loopback); users are copied, see the runbook
for signing in.
