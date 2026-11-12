# OIDC sign-in spike

Throw-away experiments for [ADR 0053](../../docs/adr/0053-interactive-sign-in.md): can the
Flutter app sign in interactively (authorization code + PKCE, refresh) with the `oidc`
package family, or should the app own the flow? Nothing here is imported by `app/`.

| Experiment | Code | What it is |
| --- | --- | --- |
| A | `test/experiment_a_oidc_test.dart` | `oidc` 5.0.2 (`OidcUserManager`, `oidc_linux`/`oidc_desktop` loopback listener) against Keycloak |
| B | `lib/inhouse_oidc.dart`, `test/experiment_b_inhouse_test.dart` | minimal in-house flow (`HttpServer` + `dio` + `crypto`, about 350 lines without comments) |
| Store probe | `integration_test/store_probe_test.dart` | `oidc_default_store` + `flutter_secure_storage` 11.2 in a real Linux Flutter app with libsecret |

Both experiments use the same fake browser (`lib/fake_browser.dart`): the test opens the
authorization URL with a plain HTTP client, submits the Keycloak login form (alice) and
follows the redirect to the loopback listener, exactly like a browser would. No real browser
is needed. `lib/keycloak_admin.dart` revokes sessions through the Keycloak admin API.

## Run

The package depends on Flutter (the `oidc` package does), so use `flutter test`, not `dart test`.
Docker is needed for Keycloak (port 18080, bound to 127.0.0.1, container
`tradocraft-oidc-spike-keycloak`).

```bash
cd tool/oidc-spike
docker compose -p oidcspike up -d          # first start imports realm-tradocraft.json, ~15 s
until curl -sf http://127.0.0.1:18080/realms/tradocraft/.well-known/openid-configuration >/dev/null; do sleep 2; done
nice flutter pub get
nice flutter test -r expanded test         # both experiments; the tests print their evidence
nice flutter test --dart-define=OIDC_LOG=true test/experiment_a_oidc_test.dart   # package logs
docker compose -p oidcspike down -v        # remove container, network and volumes
```

The realm (`realm-tradocraft.json`): public client `tradocraft-app` (no client authentication,
standard flow only, PKCE S256, redirect `http://127.0.0.1/*`, web origins `+`), an audience
mapper adding `tradocraft-app` to access tokens, `offline_access` as an optional scope, user
`alice` / `alice-pass` (`alice@example.test`, e-mail verified, realm role `offline_access`),
access token lifespan 60 s, refresh token rotation (`revokeRefreshToken`, reuse 0). Admin
console: `admin` / `admin`. Keycloak 26.4.7.

Gotcha found while building it: without the `offline_access` realm role on the user, Keycloak
answers the token request with `not_allowed: Offline tokens not allowed for the user or client`,
and `oidc` reports that as a misleading "authorization error response is missing the `iss`
parameter" (see the ADR).

### Real libsecret store probe (Linux, headless)

Needs `xvfb`, `gnome-keyring`, `dbus-run-session`, the GTK/libsecret development packages and
`flutter create --platforms=linux .` already applied (the `linux/` runner is committed). The
keyring must be a fresh, unlocked one in a private session, otherwise `flutter_secure_storage`
waits for a prompt that never comes:

```bash
export XDG_DATA_HOME=$(mktemp -d)
dbus-run-session -- bash -c '
  eval "$(echo -n spike | gnome-keyring-daemon --login)"
  eval "$(echo -n spike | gnome-keyring-daemon --start --components=secrets)"
  export GNOME_KEYRING_CONTROL
  nice xvfb-run -a flutter test integration_test/store_probe_test.dart -d linux'
rm -rf build   # the Linux build is about 330 MB
```

## Results

The numbers and the recommendation are in the ADR; the raw output of the runs is reproduced by
the commands above.
