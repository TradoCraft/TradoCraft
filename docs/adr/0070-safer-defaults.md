# 0070 — Safer defaults for the example setup

**Status:** Accepted

**Context.** TradoCraft is self-hosted: people copy `docker-compose.yml` and `.env.example` and run
them. The security review of 2026-11-14 found that the example setup was safe only on a developer's
own machine, and did not say so: `AUTH_MODE=dev` trusts the `X-Dev-User` header, the browser
origins answered in that mode were *all* of them, the database password was fixed, the Docker
build context could include `.env` files, and the Android release was signed with the public debug
key (see ADR 0069 for the follow-up list).

**Decision.**

* **Dev authentication stays the default of the example files** (the quick start needs it, and the
  maintainer's own workflow uses it), but it is now labelled as for this machine only, in the
  header of `docker-compose.yml`, and the loopback binding of the published ports is stated as the
  reason it is acceptable. The API's existing guard stays: dev mode refuses a non-loopback
  `BIND_ADDR` unless `ALLOW_INSECURE_DEV_AUTH=true`.
* **CORS in dev mode answers this machine only.** Without `CORS_ALLOWED_ORIGINS`, `AUTH_MODE=dev`
  answers pages served from `localhost`, `127.0.0.1` or `[::1]` on any port (`CorsConfig::Loopback`),
  no longer every origin. Otherwise any web page the developer visits could call the local API with
  an `X-Dev-User` header of its choosing. `CORS_ALLOWED_ORIGINS=*` still asks for every origin
  explicitly. Native apps send no `Origin` and are unaffected. This supersedes the "any origin with
  `AUTH_MODE=dev`" sentence of ADR 0050.
* **The database password of the Compose file is configurable** (`POSTGRES_PASSWORD`, default
  `tradocraft`). It is not made mandatory: the database port is published on loopback only, and a
  required secret would break the one-command start for no gain on that footing.
* **The Docker build context excludes** `.env` and `.env.*` (except `.env.example`), key files,
  `key.properties`, `.claude`, `e2e` and `.github`.
* **Android release signing uses the maintainer's own key** from the git-ignored
  `app/android/key.properties` (`app/android/README.md`). Without it the build still falls back to
  the debug key so `flutter run --release` works, and prints a warning that such a build must not be
  distributed.

**Consequences.**

* A developer who opens the web build from another machine or a non-local host against a dev-mode
  API must now list that origin in `CORS_ALLOWED_ORIGINS`. This is the one behaviour change.
* Not done here: pinning the Docker base images by digest (it needs a maintained update path;
  Dependabot's Docker ecosystem is the way), a health check in the API image, and refusing
  `AUTH_MODE=dev` together with `APP_ENV_KIND=live` (the maintainer's own local setup is exactly
  that; the loopback guard is the protection).
