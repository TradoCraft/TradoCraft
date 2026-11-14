# Runbook: putting the customer portal on the internet

See [ADR 0050](../adr/0050-portal-surface.md) and
[ADR 0014](../adr/0014-contacts-calls-and-customer-portal.md).

## What runs where

| Piece | Reachable from | Notes |
|---|---|---|
| `tradocraft-api` (staff API) | office network / VPN only | migrates the database; `AUTH_MODE=oidc` |
| `tradocraft-worker` | nowhere (no listener) | sends the login e-mails |
| `tradocraft-portal-api` | the reverse proxy only | bind it to loopback or a private network |
| Reverse proxy (TLS) | the internet | serves the portal's files and forwards `/api/` |
| PostgreSQL | the three programs above | never published |

The API must not be published "just for the portal": the portal server exists so that it does not
have to be.

## Set up

1. In the app, set the company's portal address (`portal_url`), e.g. `https://portal.example.com`.
   Login links point there, and the portal server answers that browser origin.
2. Build the portal with the public address of the portal server (same host name, so the proxy
   can serve both):

   ```bash
   cd app
   flutter build web -t lib/portal/portal_main.dart \
     --dart-define=PORTAL_API_URL=https://portal.example.com \
     --dart-define=PORTAL_COMPANY_ID=<company id>
   ```

   Copy `build/web` to the proxy's document root.
3. Start the portal server next to the API (same version, same database):

   ```bash
   DATABASE_URL=postgresql://... \
   PORTAL_BIND_ADDR=127.0.0.1:8090 \
   PORTAL_TRUSTED_PROXIES=127.0.0.1 \
   tradocraft-portal-api
   ```

   `PORTAL_TRUSTED_PROXIES` is the address (or network, `172.16.0.0/12`) the proxy connects from.
   Leave it out and every customer counts as one client, so one busy customer locks out the rest.
   Set it to something a stranger can connect from and they can dodge the limits with a header.
4. Reverse proxy. Caddy, as an example:

   ```
   portal.example.com {
       encode gzip
       header {
           Strict-Transport-Security "max-age=31536000"
           X-Content-Type-Options "nosniff"
           X-Frame-Options "DENY"
           Referrer-Policy "no-referrer"
           # The portal is a Flutter web build: scripts and wasm from its own origin only.
           Content-Security-Policy "default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'"
       }
       handle /api/* {
           reverse_proxy 127.0.0.1:8090
       }
       handle {
           root * /srv/portal
           try_files {path} /index.html    # /login#token=... and /csat#token=... are app routes
           file_server
       }
   }
   ```

   The proxy must **append** the connecting address to `X-Forwarded-For` (Caddy and nginx's
   `$proxy_add_x_forwarded_for` do) and must be the only way to reach port 8090. Try the policy in
   the browser's console before relying on it: a Flutter renderer that loads fonts or CanvasKit
   from a CDN needs those hosts added, or build with `--no-web-resources-cdn`.
5. The worker needs `MAIL_TRANSPORT=smtp` in the live environment, or no login link arrives.

## Check

```bash
curl -s  https://portal.example.com/api/v1/portal/tickets          # 401 unauthorized
curl -si https://portal.example.com/api/v1/customers | head -1    # 404: no staff route
curl -si https://portal.example.com/docs | head -1                # 404 from the portal server (or the app's index.html from the proxy)
for i in $(seq 12); do curl -s -o /dev/null -w '%{http_code}\n' -X POST \
  -H 'content-type: application/json' -d '{"company_id":"<company id>","email":"x@example.com"}' \
  https://portal.example.com/api/v1/portal/login-links; done      # 202 ten times, then 429
```

From outside the office network, the staff API's host name must not answer at all.

## Settings

| Variable | Default | Meaning |
|---|---|---|
| `PORTAL_BIND_ADDR` | `127.0.0.1:8090` | where it listens |
| `PORTAL_DATABASE_URL` | `DATABASE_URL` | its own connection string |
| `PORTAL_DB_MAX_CONNECTIONS` | `5` | database connections it may hold |
| `PORTAL_ALLOWED_ORIGINS` | the companies' `portal_url` | browser origins that are answered |
| `PORTAL_RATE_PER_MINUTE` | `300` | requests a minute per client address; `0` = off |
| `PORTAL_LOGIN_RATE_PER_MINUTE` | `10` | login attempts a minute per client address; `0` = off |
| `PORTAL_TRUSTED_PROXIES` | none | proxies whose `X-Forwarded-For` is believed |
| `PORTAL_REQUEST_TIMEOUT_SECONDS` | `30` | deadline per request |

## When something is wrong

* *The server stops at start with "no portal origin is known".* No company has a `portal_url`
  and `PORTAL_ALLOWED_ORIGINS` is empty.
* *It stops with an error about `portal_url` or a missing table.* The database was not migrated:
  start the API (same version) first.
* *The portal shows a network error, the browser console mentions CORS.* The page is served from
  an origin that is not the company's `portal_url`; fix the address or set
  `PORTAL_ALLOWED_ORIGINS`, then restart the portal server.
* *Customers get "too many requests" together.* `PORTAL_TRUSTED_PROXIES` does not match the
  address the proxy connects from; the log line `rate limit reached client=...` shows the proxy's
  address instead of a customer's.
