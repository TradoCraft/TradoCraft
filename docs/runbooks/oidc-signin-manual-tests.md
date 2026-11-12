# Interactive sign-in: manual tests

What the spike (`tool/oidc-spike`, ADR 0053) could not test. Run these when the sign-in is
built (phases 3 to 5) and again before each release that changes the auth layer or the `oidc`
version. Tick a result per platform; a failing step is a bug or a reason to revisit the package
choice in ADR 0053.

Common setup: a Keycloak (`docker compose -p oidcspike up -d` in `tool/oidc-spike`, port 18080,
user `alice` / `alice-pass`) registered as a provider on a test API instance with `client_id`
`tradocraft-app`, `token_use` `id_token`, and `ALLOW_INSECURE_IDP_URLS=true` (development only,
ADR 0052). Admin console `http://127.0.0.1:18080` (`admin` / `admin`) for revoking sessions.
Windows and Android need the Keycloak reachable from that machine. The default compose file
binds `127.0.0.1` only and stays unchanged; use an override file kept outside the repository
(for example `/tmp/oidc-lan.yml`), with `<LAN-IP>` the host's address on the test network:

```yaml
services:
  keycloak:
    ports: !override
      - "<LAN-IP>:18080:8080"
    environment:
      KC_HOSTNAME: http://<LAN-IP>:18080
      KC_HOSTNAME_STRICT: "true"
```

Start it with `docker compose -p oidcspike -f docker-compose.yml -f /tmp/oidc-lan.yml up -d`, open
only that port to the test machine, and remove it afterwards (`down -v`). Keycloak builds the
issuer from `KC_HOSTNAME` (behind a reverse proxy it would also need `KC_PROXY_HEADERS`), so the
issuer is `http://<LAN-IP>:18080/realms/tradocraft`; enter exactly that issuer in tradocraft. The
redirect URI stays the loopback `http://127.0.0.1:<port>/callback` (it is opened by the browser
on the test machine itself). The Android emulator reaches the host as `10.0.2.2`: use that as
`<LAN-IP>` there and in the issuer.

## 1. Linux

Reference cases verified by the spike without UI: code + PKCE through a loopback listener,
rotation, libsecret store with an unlocked keyring. Repeat them through the real app.

1. With a browser and keyring (desktop session, `xdg-open` works, GNOME Keyring or KWallet):
   sign in. Expected: the default browser opens the provider page, after login a tab says
   "you can close this tab", the app comes to the front signed in as alice. Quit and restart the
   app: still signed in, no browser. Sign out: signed out, the browser shows the provider's
   logged-out page; restart: signed out.
2. Wrong port or blocked: during sign-in, stop the app's listener (kill the app) and reload the
   callback tab. Expected: the tab shows a connection error, nothing is stored, the app can start a
   new sign-in.
3. Without a browser (`env -u DISPLAY`/SSH, or `PATH` without `xdg-open`): sign in. Expected:
   within 2 s the app shows the authorization URL as selectable text with a Copy button and
   "waiting"; opening the URL on the same machine in any browser completes the sign-in; Cancel
   ends the wait and frees the port (`ss -ltn` shows no leftover 127.0.0.1 listener); waiting
   5 minutes ends with a clear timeout message.
4. Without a keyring (no Secret Service running, for example a minimal window manager or
   `dbus-run-session` without keyring): sign in. Expected: the app tells once that tokens cannot
   be stored, the session works until the app closes, nothing readable is written to disk
   (search for the real token values without printing them: put the access and refresh token of
   the session in a file readable only by you (`$TOKENS`, one per line, copied from a debug
   build), then run `for d in ~/.local/share ~/.config <app data dir>; do grep -rqFf "$TOKENS" "$d"
   && echo "FOUND in $d" || echo "not found in $d"; done`; expected: not found everywhere; delete
   `$TOKENS` afterwards), next start
   asks for sign-in.
5. Locked keyring without a prompter (the spike hung here for more than 100 s): start with a
   keyring that is locked and no keyring prompt available. Expected: after about 3 s the app falls
   back as in step 4 instead of freezing.
6. Redirect rejected: remove `http://127.0.0.1/*` from the client's redirect URIs and sign in.
   Expected: the provider shows its own error, the app shows "no answer from the browser, check
   the redirect URIs" after the timeout or Cancel, and recovers.
7. Revocation: while signed in, in the Keycloak admin console sign out all sessions and delete the
   offline consent of alice; trigger an API call after the access token expired (60 s lifetime in
   the test realm). Expected: this environment is signed out with the cause, other signed-in
   environments are untouched, the sign-in screen is shown.
8. Two environments: sign in to two environments (two provider entries). Expected: independent
   sessions, signing out of one keeps the other, restart keeps both.

## 2. Windows (clean machine or VM, Windows 10 and 11)

Not verified at all by the spike.

1. Install the app on a machine that never ran it, default Windows Defender Firewall, standard
   user. Sign in. Expected: the default browser opens; **no firewall prompt** appears, because the
   listener is bound to 127.0.0.1 only. If a prompt appears, record the text and whether denying
   it breaks the sign-in (it should not, loopback traffic is not blocked), then fix the bind
   address.
2. After login the "you can close this tab" page shows, the app window comes to the front
   (`window_to_front`), signed in.
3. Restart the app: still signed in (Windows Credential Store). Check in `Credential Manager`,
   Windows Credentials, that an entry exists and that its content is not readable plain text in
   the app data directory.
4. Browser variants: Edge default, Firefox default, and a browser with a strict `localhost`/
   loopback policy if available. Expected: all complete.
5. Sign out, revoke in the admin console, two environments: as Linux steps 1, 7 and 8.
6. Antivirus or corporate proxy: note whether the loopback redirect is blocked on a managed
   machine.

## 3. Android (emulator, then one real device)

1. Register the redirect `com.tradocraft.app:/oauth2redirect` (the real reverse-DNS id) in the
   provider, add the intent filter or manifest placeholder for that scheme. Emulator Android 13+
   with Chrome, the Keycloak reachable from the emulator (`10.0.2.2:18080` for the host).
2. Sign in. Expected: an Auth Tab or custom tab opens, after login it closes itself and the app is
   signed in without the user tapping anything.
3. Cancel by pressing Back in the tab. Expected: the app shows "sign-in cancelled" and can retry;
   no stuck "waiting" state.
4. Kill the app while the tab is open, finish the login. Expected: no crash on return; the user
   can start a new sign-in; no half-written session.
5. Restart: still signed in (Keystore-backed storage). Clear the app data: signed out.
6. Provider with a wrong redirect scheme: the tab shows the provider's error and Back returns to
   the app signed out.
7. Real device with another default browser (Samsung Internet or Firefox): sign in completes.
8. Airplane mode during refresh: session kept, API calls fail with the "cannot reach the identity
   provider" message, recover when the network returns.

## 4. Web (later, when the web sign-in is built)

1. Redirect with `web/auth.html` and, separately, popup: sign in completes, tokens stay in memory
   only (reload signs out, which is expected), no token in `localStorage`/`sessionStorage`
   (browser developer tools, Application tab).
2. Pop-up blocker enabled: the app explains and offers the redirect variant.
3. CORS: the token endpoint call from the browser works against the provider (Keycloak web origins
   `+`; Entra needs the Single-page application platform).
4. Entra only: refresh token expires after 24 hours; the app then asks for sign-in without errors.

## 5. Entra ID with a throwaway tenant

Use a free developer tenant, never a customer tenant. Follow
`identity-provider-setup.md`, Microsoft Entra ID, step by step and record every place where the
portal differs from the text.

1. Tokens: sign in and open the provider Test button. Expected: `iss` is
   `https://login.microsoftonline.com/<tenant>/v2.0`, `aud` equals the audience entered, the
   scope claim `scp` is `access_as_user`, `ver` is `2.0`. If `iss` is `https://sts.windows.net/...`
   or `ver` is `1.0`, `requestedAccessTokenVersion` is not 2.
2. E-mail: `email` present for a member and for a guest user; `xms_edov` present as `true` and
   accepted by the server's `require_verified_claim` policy; a user without `email` falls back as
   configured.
3. Loopback redirect with the manifest entry `http://127.0.0.1` of type `InstalledClient` on
   Linux and Windows with a random port. Expected: accepted; with `http://localhost` rejected
   (`AADSTS50011`).
4. Consent: pre-authorised client, a non-admin user signs in without a consent dialog. Remove the
   pre-authorisation and admin consent once to see the failure text (`AADSTS65001`), restore.
5. Refresh: leave the app 24 hours and 8 days (use a second session or wait): record when
   `invalid_grant` / `interaction_required` first appears and that the app shows signed out.
6. Account removal: disable the user in Entra; the next refresh must sign the app out.
7. Logout: end-session with `id_token_hint` works, there is no revocation endpoint (expected).
8. `sub` stability: sign in on two machines; the same `sub` appears. Record that a new app
   registration changes `sub` (do not do this in production).
9. Record anything the documentation got wrong in `identity-provider-setup.md`.
