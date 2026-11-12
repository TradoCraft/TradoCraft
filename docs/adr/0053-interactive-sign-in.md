# 0053 — Interactive sign-in (OIDC authorization code with PKCE in the app)

**Status:** Proposed

**Context.** The API verifies bearer tokens against the identity providers an administrator
configures (ADR 0004, ADR 0052). Today the app gets a token by pasting it, which is fine for
developers and not for staff. The app has to sign people in itself: authorization code with PKCE
as a public client (no client secret, ADR 0052 stores only `client_id` and `scopes`), refresh in
the background, one session per environment (ADR 0043) and provider. First release: Microsoft
Entra ID (the access token of our own exposed API) and Keycloak or any generic OIDC provider;
Google later. Platforms: Linux, Windows, Android, web last, iOS and macOS later. A spike
(`tool/oidc-spike/`) compared the package `oidc` (Bdaya) with an in-house flow against a real
Keycloak 26.4.7. The spike could **not** verify Entra, Windows, Android, web or a locked keyring
(see Consequences); those need the manual checklist in
`docs/runbooks/oidc-signin-manual-tests.md`.

**Decision.**

*Package.* Use `oidc` (5.0.2, with `oidc_core` 4.0.0 and `oidc_default_store` 2.0.0, which uses
`flutter_secure_storage` 11.2) with **exact version pins**, behind a small interface of our own
(`SignInSession`: sign in, `accessToken(minValidity)`, sign out, state stream; one instance per
environment and provider), so the package can be replaced by the in-house flow without touching
the UI or the Dio layer. The in-house prototype stays in the spike folder as the documented
fallback. We switch to it if the manual Windows or Android checks fail in a way the package
cannot be configured around, or if the package keeps breaking its API (see risks).

*Evidence from the spike.*

| Question | `oidc` on Linux against Keycloak | In-house (about 350 lines) |
| --- | --- | --- |
| Code + PKCE S256, state, nonce, loopback `127.0.0.1:<random>` | works; id token validated, RFC 9207 `iss` checked | works |
| Claims | access token: `iss`, `aud` = `[tradocraft-app, account]` (audience mapper), `sub`, 60 s lifetime; id token: `aud` = client id, `email`, `email_verified` = true | same |
| Port-agnostic redirect | three logins on three random ports accepted with `http://127.0.0.1/*`; `http://localhost:<port>` rejected, see below | same |
| Refresh twice | access token, id token and refresh token all new each time (rotation); the manager keeps the newest | same |
| Refresh token revoked | `OidcException` `invalid_grant` ("Offline user session not found"); `OidcTokenRefreshFailedEvent` kind `terminal`; `getAccessToken` throws `OidcInteractionRequiredException`; `currentUser` is **not** cleared | `SignedOutException(invalid_grant)`, store cleared |
| Reuse of a rotated token (online session) | `invalid_grant` "Maximum allowed refresh token reuse exceeded" and the newest token is dead too (family revoked) | same server behaviour |
| Concurrent refresh | `getAccessToken(minValidity)`: 8 parallel calls, 1 token request | 8 parallel calls, 1 token request |
| Logout | `logout()` opens `end_session_endpoint` with `id_token_hint`, `post_logout_redirect_uri`, `state` through the loopback listener, clears the store; the old refresh token is dead | local delete first, revocation (RFC 7009), end-session URL returned, no redirect back to the app |
| No browser | the launch hook (`OidcPlatformSpecificOptions_Native.launchUrl`) is ours: returning `false` only logs a warning and the flow keeps waiting; if the hook shows the URL and returns `true`, completing the flow in another browser works | `present(url)` callback, completing elsewhere works, `cancelSignIn()` and a timeout exist |
| Several managers | `OidcUserManager(id: ...)` with one shared store: independent sessions, session restored after a restart per id | independent clients and stores |
| Secure store | `OidcDefaultStore` in a real Linux Flutter app (Xvfb, gnome-keyring): login, restore after restart, another manager id sees nothing | not written (a `TokenStore` interface only) |

Problems found with `oidc` that shape our wrapper:

1. A token endpoint failure during the code exchange (`not_allowed`, offline tokens not allowed)
   is rethrown as "authorization error response is missing the `iss` parameter" when the provider
   advertises RFC 9207 (Keycloak does). The real cause is only visible in the HTTP log. Our
   wrapper must log the original response and map errors itself; do not show package messages.
2. No timeout by default (`flowTimeoutSeconds` is null) and no cancel API for a pending flow:
   always set a timeout (5 minutes) and always supply `launchUrl`.
3. A rejected `redirect_uri` (Keycloak shows its own error page) never reaches the listener: the
   flow just times out. The UI must say "no answer from the browser, check the redirect URIs".
4. `currentUser` stays set after a terminal refresh failure; only the event and the thrown
   `OidcInteractionRequiredException` tell. The wrapper clears the session on those.
5. Every refresh also fetches `userinfo` and the JWKS; set `sendUserInfoRequest: false` (we only
   need the tokens) to save two requests per refresh.
6. The manager is a very large class (about 6,400 lines in one file: DPoP, PAR, mTLS, JAR,
   dynamic registration). We use a small part of it.
7. `OidcDefaultStore` calls `flutter_secure_storage`; with an existing but locked Secret Service
   and no prompter (headless, SSH, some minimal desktops) a write **never returns** (the spike
   run was cut off after 100 s). The store must be wrapped: timeout, then the fallback below.
8. Maintenance: 5 major versions between 2026-07-14 (1.0.0) and 2026-10-05 (5.0.0), the 5.0.0
   changelog lists breaking changes in the store dependency and discovery validation. Active
   (more than 100 commits since May 2026, two main authors, 0 open issues, 105 closed, 155 of 160
   pub points, about 32,000 downloads in 30 days, 51 likes, MIT), but young.

Comparison (platform coverage is as documented on pub.dev, not tested except Linux):

| | `oidc` 5.0.2 | In-house | `flutter_appauth` |
| --- | --- | --- | --- |
| Platforms | Linux, Windows, Android, web, iOS, macOS | desktop loopback only; Android, web, iOS need plugins we would pick and wire | no Linux, Windows or web |
| Desktop loopback | `127.0.0.1:<random>` via `oidc_loopback_listener`, single request, window to front; Linux verified | same design, verified on Linux, about 70 lines | not applicable |
| Code we own | adapter, store wrapper, error mapping (about 200 lines estimated) | about 350 lines now, about 800 with Android, web and storage (estimate) | |
| Maintenance | young, very active, 5 majors in 12 weeks | ours | not relevant |
| API fit | `getAccessToken(minValidity)` single-flight, typed refresh events, per-id managers; odd error masking, no cancel | exactly what the interceptor needs, by construction | |
| Testability | needs a `launchUrl` hook (available) and `OidcPlatform.instance`; runs under `flutter test` against a fake browser | pure Dart, plain `dio` adapters | |

The in-house flow needed no workaround for any of the above and is smaller to reason about, but
it only covers desktop loopback. What it lacks compared with `oidc`: the Android redirect
handling (custom scheme or Auth Tab), the web redirect and popup flows, Windows window-to-front,
`flutter_secure_storage` integration, front-channel logout, PAR, DPoP, dynamic registration,
ID token signature validation (it relies on TLS to the token endpoint, which OIDC Core allows),
and a conformance suite behind it (the package runs the OpenID certification tests in CI). The
hard part of the project is the per-platform redirect, which the package already ships for five
platforms; that decides it. The recommendation is `oidc`, behind our interface and pinned.

*Redirect per platform.*
- Linux and Windows: system browser plus loopback listener on `http://127.0.0.1:<random>/callback`
  (RFC 8252 section 7.3), bound to 127.0.0.1 only, answering "you can close this tab". Providers
  register `http://127.0.0.1` (Keycloak: `http://127.0.0.1/*`; Entra: platform "Mobile and desktop
  applications", see the runbook). When no browser can be opened (no `xdg-open`, SSH session)
  the app shows the authorization URL as copyable text with a "copy" button and keeps the
  listener open, so the user can open it on the same machine; the redirect only works on that
  machine, so a remote browser is out of scope for the first release.
- Android: custom scheme `<reverse-dns>:/oauth2redirect` (for example
  `com.tradocraft.app:/oauth2redirect`), registered as a redirect URI at the provider; the
  package uses an Auth Tab or custom tab.
- Web, last: redirect or popup with a static `web/auth.html` as the redirect page. Entra needs
  the redirect registered under the platform "Single-page application", whose refresh tokens
  last 24 hours (documentation, not verified); web may therefore stay on the pasted token until
  a web release is planned.
- iOS and macOS: later (the package supports both).

*Token to send.* New per-provider server setting `token_use` = `id_token` | `access_token`,
default `id_token`, returned by `GET /api/v1/auth/providers` next to `client_id` and `scopes`.
The server already verifies `aud`, so what the app sends must carry the audience the
administrator configured:
- Keycloak and generic OIDC: `id_token` works out of the box (`aud` = client id). `access_token`
  works when the client has an audience mapper (verified in the spike: `aud` contains
  `tradocraft-app`).
- Entra ID: `access_token` of our own exposed API (`api://<client-id>/access_as_user`),
  with the app manifest `requestedAccessTokenVersion` = 2 so the token is v2 (issuer
  `https://login.microsoftonline.com/<tenant>/v2.0`). Entra access tokens for other resources
  (Microsoft Graph) must never be sent to the API.

*Dio interceptor.* One interceptor per environment, using that environment's session:
`onRequest` asks the session for `accessToken(minValidity: 120 s)`; the session refreshes only
when the token expires within 120 s, and concurrent requests share one refresh (single-flight,
verified: 8 calls, 1 token request). On a 401 the request is retried once with a forced refresh.
`invalid_grant` or `interaction_required` (`OidcInteractionRequiredException`, terminal event)
means signed out for that environment only: clear the session, keep other environments, show the
sign-in screen with the cause. A network or 5xx error on refresh keeps the session and retries
with backoff (1 s, 2 s, 4 s, ... capped at 60 s); the request fails with a "cannot reach the
identity provider" error. The rotated refresh token is persisted **before** the new access
token is used: with rotation, a lost write means the old token is reused and the provider revokes
the whole family (verified on Keycloak online sessions). Tokens are never logged.

*Storage.* Refresh, access and id tokens only in secure storage: Keychain (iOS, macOS),
Keystore-backed encrypted preferences (Android), libsecret (Linux), Windows Credential Store.
Keys are namespaced by session id `<environment id>/<provider id>`. Web: memory only (a
refresh token in `localStorage` is readable by any script on the origin). Linux without a usable
keyring (no Secret Service, locked and no prompter, or the call times out after 3 s): ask once,
then keep the session in memory only for this run ("you will have to sign in again next time");
never write tokens to a plain file by default.

*Logout.* Delete the local tokens first (the user is signed out even if the network is down),
then revoke the refresh token where the provider has a `revocation_endpoint`, then open the
`end_session_endpoint` with `id_token_hint` (and a post-logout redirect on the loopback where
registered). Entra has no revocation endpoint: only end-session and local deletion.

*Sessions.* One session per (environment, provider), keyed as above. Changing environment
switches the interceptor's session; signing out of one never touches another. The same person
can be signed in to the live and the tutorial environment with different providers.

*Phases.* (1) Server: `token_use` column, API field, admin form, tests; small (about 150 lines
plus tests). (2) Core auth layer: `SignInSession` interface, `oidc` adapter, secure store
wrapper with timeout and fallback, fake provider for tests; medium. (3) UI: provider choice
on the login screen, "waiting for the browser" with cancel and copy-URL, signed-out cause;
medium. (4) Dio interceptor and 401 handling, replacing the pasted token for providers that have
a `client_id`; small to medium. (5) Platforms in order: Linux, Windows, Android (each mostly
configuration plus the manual checklist), web last; small each.

**Consequences.** Staff sign in with their company account and never handle tokens. The paste
path stays for development. The server learns one setting; it stays free of client secrets.

*Risks.* Entra issues v1 tokens (different issuer and `aud`) unless
`requestedAccessTokenVersion` = 2; the runbook makes it a checklist step and the provider Test
button shows the `aud` of a real token. Entra's `sub` is per application, so the client id must
never be rotated or every user would look new (users are bound by e-mail and subject, ADR 0052).
`oidc` is young and moves fast: pin exact versions, review each upgrade, and keep the wrapper
thin so the fallback stays possible. Windows may show a firewall prompt for the loopback
listener (it binds 127.0.0.1 only, so the prompt should not appear; to be confirmed on a clean
machine). Linux keyring problems: see Storage; a locked keyring without a prompter hangs the
package's store call, the wrapper's timeout is mandatory. A rejected redirect URI shows only the
provider's error page, so the runbook lists every URI to register.

*Not verified by the spike.* Everything on a real Entra tenant (v2 access token, `aud`, the
`127.0.0.1` redirect through the manifest, `xms_edov`, refresh token lifetime), Windows (loopback
and firewall), Android (custom scheme, Auth Tab), web, and the Linux store with a locked or
missing Secret Service (only "hang after 100 s with a locked keyring and no prompter" was seen).
Verified headless: the Linux store with libsecret and an unlocked gnome-keyring in a private
session. Not exercised: the default launcher (`url_launcher`/`xdg-open`); the spike always
supplied its own launch hook.
