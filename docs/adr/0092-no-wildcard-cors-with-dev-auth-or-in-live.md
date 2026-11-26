# 0092 — No wildcard CORS with dev authentication or in a live environment

**Status:** Accepted (security review of 2026-11-14, findings #3 and #4; amends
[ADR 0050](0050-portal-surface.md) and [ADR 0070](0070-safer-defaults.md))

**Context.** ADR 0070 made the staff API answer only pages of this machine with `AUTH_MODE=dev`
when `CORS_ALLOWED_ORIGINS` is unset, and kept `CORS_ALLOWED_ORIGINS=*` as an explicit way to answer
every origin, with a warning. Together with dev authentication that one setting undoes the
protection: any web page the developer visits can call the local API with an `X-Dev-User` header
of its choosing. In a live environment with real sign-in, `*` is not needed (the web app's origin
is known) and only widens what a browser lets other sites do. Dev authentication itself was
already guarded (the binary defaults to `AUTH_MODE=oidc`; dev mode refuses a non-loopback
`BIND_ADDR` unless `ALLOW_INSECURE_DEV_AUTH=true`), but bypassing that guard was not logged.

**Decision.**

* The staff API refuses to start with `CORS_ALLOWED_ORIGINS=*` when `AUTH_MODE=dev` (any
  environment) or when `APP_ENV_KIND=live` (any authentication). `*` remains for test and tutorial
  environments with real sign-in, with a warning (`CorsConfig::for_api`).
* Dev authentication on a non-loopback address with `ALLOW_INSECURE_DEV_AUTH=true` logs a second
  warning naming the address (`auth::dev_auth_startup`). Refusing `AUTH_MODE=dev` together with
  `APP_ENV_KIND=live` stays out, as ADR 0070 decided.
* The customer portal server is unchanged: it does not know the environment kind, and it already
  refuses to start without a known origin.

**Consequences.** A setup that runs `AUTH_MODE=dev` or a live environment with
`CORS_ALLOWED_ORIGINS=*` no longer starts; the error says to leave the value empty (dev: pages of
this machine) or to list the origins. No example file uses `*`.
