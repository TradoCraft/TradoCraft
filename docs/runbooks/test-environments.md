# Runbook: test and tutorial environments (envctl)

See [ADR 0048](../adr/0048-environment-clones-and-outbound-safety.md). Needs `psql`, `pg_dump`,
`pg_restore`, `curl`, `jq` and a built API (`cargo build --release -p tradocraft-api -p
tradocraft-worker`; without one, `cargo run` is used). Docker is not needed.

## Set up

Put the connection in `.env` (or export it): `DATABASE_URL=postgresql://user:pass@host:5432/tradocraft`.
The user must be able to create and drop databases. Optional: `AUTH_MODE`, `DEV_DEFAULT_USER`,
`OIDC_*`, `ENVCTL_DIR`, `ENVCTL_PORT_MIN`/`ENVCTL_PORT_MAX`, `ENVCTL_API_BIN`. Protect the live
database from `drop`: `scripts/envctl register live_main --database tradocraft --kind live`.

## Do the tutorial in three commands

`scripts/tutorial-env` is a thin wrapper over `envctl` that gives you a clean environment of kind
`tutorial` with the demo data, to do the story-mission tutorial ([ADR 0045](../adr/0045-story-mission-tutorial.md)) in.

```bash
scripts/tutorial-env up       # create (first time), start, print the address and the steps
# in the app: login page > Environments > add the printed address; sign in as
# admin@example.com; account menu > Tutorial > Start chapter 0
scripts/tutorial-env reset    # replay from chapter 0 (drops and recreates; asks first, --yes skips)
scripts/tutorial-env down     # stop the instance, keep the data (`up` starts it again)
```

Also `status` (address, kind, state, migration and app version) and `address` (only the URL, for
scripts). `--name NAME` replaces the default name `tutorial`; `--config`, `--dir` and
`--database-url` are passed to `envctl` unchanged. `reset` refuses any environment that is not
registered as kind tutorial or test.

- Demo data: the demo company with the development users (for example `admin@example.com`). It
  needs `AUTH_MODE=dev` (the `envctl` default), so there is no password.
- Mail goes to files only (`ENVCTL_DIR/envs/<name>/outbox`) and mailbox polling is off, as in every
  non-live environment.
- The database is new and separate, so the tutorial `TUT-` records never mix with real data.
- Needs a running PostgreSQL reachable through `DATABASE_URL` and the API binary or cargo (see
  Set up). Set `TYPST_BIN` if `typst` is not on `PATH`: chapters 8 and 9 create quotation and order
  PDFs (`up` warns when it is missing).
- Run the Flutter app from an up-to-date checkout, add the environment with the printed address.
- `scripts/tutorial-env-smoke-test.sh` verifies the wrapper end to end (throwaway PostgreSQL in
  Docker on port 55470, or `SMOKE_DATABASE_URL`).

## Clone, start, connect

```bash
scripts/envctl clone tradocraft trial1 --kind test             # copy, scrub, start the API
scripts/envctl clone tradocraft trial2 --anonymize --worker    # also anonymize; run the worker
scripts/envctl create-empty practice --kind tutorial --seed    # empty database (seed needs AUTH_MODE=dev)
scripts/envctl list; scripts/envctl status; scripts/envctl versions
scripts/envctl stop trial1 && scripts/envctl start trial1 --worker
```

`clone` prints the URL (for example `http://127.0.0.1:8100`). In the app, add an environment with
that URL: its kind and name come from the server and show in the banner. Sign-in: with
`AUTH_MODE=dev` use any copied user (the admin keeps its address even with `--anonymize`; other
users become `user-<hash>@example.test`). With OIDC the clone instance needs the same
`OIDC_ISSUER`/`OIDC_AUDIENCE`; identity bindings were cleared, so the first sign-in binds by
e-mail. Instances bind to loopback only. To reach one from other machines, put it behind a reverse
proxy only when the clone uses OIDC, or the proxy itself authenticates users, restricts who may
connect and strips any `X-Dev-User` header: forwarding to the loopback listener with the default
dev authentication is not sufficient, because every caller could then choose any identity. Dev
authentication refuses non-loopback binds for the same reason.

## Drop

```bash
scripts/envctl drop trial1          # asks you to type the name; --yes skips the question
```

It stops the instance, drops the database and removes `ENVCTL_DIR/envs/<name>`. It only drops
environments it created, and only when `DATABASE_URL` points to the server it was created on
(the registry stores host and port). The names `live`, `postgres`, `template0`, `template1`,
`default` and `all` are reserved.

## What a clone changes

- Always: portal login links and sessions and CSAT links deleted; OIDC bindings cleared; queued
  mail cancelled. Mail is written to `ENVCTL_DIR/envs/<name>/outbox/*.eml`; the worker does not
  poll the mailbox (override only with a dedicated mailbox: `ALLOW_INBOUND_MAIL_IN_NON_LIVE=1`).
- `--anonymize` additionally: e-mail addresses and phone numbers of customers, suppliers, company,
  contacts, tickets and queued mail; raw e-mails and mail attachments; non-admin users.
- Not scrubbed, even with `--anonymize`: names, postal addresses, VAT numbers, IBANs, free text,
  ticket subjects and bodies, audit data. Do not hand an anonymized clone to people who may not
  see that data.

## Limits

- A clone is a snapshot at copy time and never syncs. Attachments and photos live in the database,
  so they are copied (a large database takes time to clone).
- The tool runs on one host. Hosted or containerised setups need their own orchestration (one
  database and one API per environment, same variables as above).
- `scripts/envctl-smoke-test.sh` verifies the tool end to end (it starts a throwaway PostgreSQL in
  Docker, or uses `SMOKE_DATABASE_URL`).
