# Identity provider setup for interactive sign-in

Checklists for the administrator who connects an identity provider to tradocraft (ADR 0055 for
verification on the server, ADR 0053 for the sign-in in the app). The app is a **public client**:
no client secret is created, entered or stored anywhere.

How much is verified:

- **Keycloak: verified** in the spike (`tool/oidc-spike`, Keycloak 26.4.7): every setting below
  was exercised with authorization code + PKCE, refresh with rotation, revocation and logout.
- **Microsoft Entra ID: from Microsoft documentation only.** The spike had no tenant. Work
  through "Test with a throwaway tenant" in `oidc-signin-manual-tests.md` before relying on it,
  and expect to correct this page.

## Microsoft Entra ID (documentation only, not verified)

Register the app (single tenant)

1. Entra admin center, Identity, Applications, App registrations, New registration.
2. Name `tradocraft`; supported account types **Accounts in this organizational directory only**
   (single tenant). Leave the redirect URI empty for now. Register.
3. Copy **Application (client) ID** and **Directory (tenant) ID**. Never delete and re-create the
   registration later: the user `sub` claim is per application, so a new client id makes every
   user look new.

Authentication

4. Authentication, Add a platform, **Mobile and desktop applications**. Add the Android custom
   scheme redirect `com.tradocraft.app:/oauth2redirect` (replace with the real reverse-DNS
   application id) and save.
5. The portal rejects `http://127.0.0.1/callback` in that box. Add it through the manifest instead:
   App registration, Manifest, find `replyUrlsWithType` and add
   `{ "url": "http://127.0.0.1/callback", "type": "InstalledClient" }`, save. The path must be the
   one the app uses (`/callback`); Entra ignores the port of a loopback redirect, so the random
   port of the app matches. Use `127.0.0.1`, not `localhost`.
6. Authentication, Advanced settings: **Allow public client flows** = **Yes**. Save.
7. Web, later: add the platform **Single-page application** with the web app's `auth.html` URL.
   Do not put the web redirect under "Web".

Expose our own API (the app sends the access token of this API, not a Microsoft Graph token)

8. Expose an API, Application ID URI: Set, accept `api://<client-id>`.
9. Add a scope: name `access_as_user`, who can consent **Admins and users**, display name
   "Access tradocraft as the signed-in user", state Enabled.
10. Under "Authorized client applications" add this same client id with the scope checked
    (pre-authorises the app, so users are not asked for consent).
11. Manifest: set `"requestedAccessTokenVersion": 2` (under `api`, or `accessTokenAcceptedVersion`
    in the older manifest format). Without it the token is a v1 token with another issuer
    (`https://sts.windows.net/<tenant>/`) and another `aud`, and the API rejects it.

Permissions and claims

12. API permissions, Add a permission, Microsoft Graph, Delegated: `openid`, `profile`, `email`,
    `offline_access`. Add, My APIs, tradocraft, Delegated: `access_as_user`.
13. **Grant admin consent** for the tenant and check every row shows "Granted".
14. Token configuration, Add optional claim, token type **ID** (and **Access** if you send the
    access token and want `email` in it): `email`, and `xms_edov` (e-mail domain owner
    verified). Accept the Graph permission prompt if shown.

Settings to enter in tradocraft (Administration, Identity providers)

15. Preset "Microsoft Entra ID", then:
    - Issuer: `https://login.microsoftonline.com/<tenant-id>/v2.0` (tenant GUID, never `common`).
    - Client id: the Application (client) ID.
    - Audience: the **API's client id**, which is the same GUID here. v2 access tokens carry the
      client id GUID in `aud`, v1 tokens carry `api://<client-id>`. Do not guess: sign in once, use
      the Test button on a real token and copy the `aud` it shows.
    - Scopes: `openid profile email offline_access api://<client-id>/access_as_user`.
    - `token_use`: `access_token`.
    - Caution: Entra may not return `xms_edov` for every user (accounts without a verified
      domain, guests, some tenants), and `require_verified_claim` then refuses their first
      sign-in. For such accounts choose one: (a) add the optional claim and check in a real token
      that it is populated; (b) keep the policy and have an administrator link the subject
      (`PUT /admin/users/{id}/oidc-subject`) with the `subject_only` rule ("only existing
      subjects"); (c) `trust_provider_email` only for a single-tenant directory the company
      fully controls, together with `allowed_email_domains`.
    - E-mail claim `email` (or `preferred_username` if `email` is empty for some accounts) and
      verification claim `xms_edov`; or e-mail policy `trust_provider_email` for a single-tenant
      directory your company fully controls (ADR 0055).
16. Check with the Test button: token accepted, `iss` ends with `/v2.0`, `aud` equals the
    audience, the e-mail resolves to a tradocraft user.

## Keycloak and other generic OpenID Connect providers (Keycloak verified)

Client (Keycloak: realm, Clients, Create client)

1. Client type OpenID Connect, client id `tradocraft-app` (any stable id).
2. Capability config: **Client authentication Off** (public client), **Standard flow** On, direct
   access grants Off, implicit flow Off.
3. Advanced, Advanced settings: **Proof Key for Code Exchange Code Challenge Method** = `S256`.
4. Valid redirect URIs: `http://127.0.0.1/*` (desktop loopback, any port; verified: random ports
   accepted, `http://localhost:<port>` rejected, and a rejected redirect only shows Keycloak's own
   error page, the app just waits), the Android scheme `com.tradocraft.app:/oauth2redirect`, and
   later the web `auth.html` URL. Valid post logout redirect URIs: `http://127.0.0.1/*`. Web origins: `+`.
5. Audience: Client scopes, `<client>-dedicated`, Add mapper, By configuration, **Audience**,
   included client audience = the client id, **Add to access token** on. (Needed only when
   `token_use` = `access_token`; the ID token already has `aud` = client id.)
6. Refresh tokens: allow `offline_access`: the optional client scope `offline_access` must exist
   on the client and the **users need the realm role `offline_access`** (new realms give it to
   users by default; a realm import does not). Without it the token request fails with `not_allowed:
   Offline tokens not allowed for the user or client`. Recommended: revoke refresh token On (rotation).
7. Users: a verified e-mail (`emailVerified` true), otherwise the default `require_verified_claim`
   policy refuses the first sign-in.

Settings to enter in tradocraft

8. Preset "Keycloak" (or generic):
   - Issuer: `https://<host>/realms/<realm>` (no trailing slash; must be https and public, ADR 0055).
   - Client id: `tradocraft-app`.
   - Audience: the client id (works for the ID token and, with the mapper, the access token).
   - Scopes: `openid profile email offline_access`.
   - `token_use`: `id_token` (default) or `access_token` with the audience mapper.
   - E-mail claim `email`, verification claim `email_verified`, e-mail policy `require_verified_claim`.
9. Test button with a real token: accepted, `aud` shown, e-mail resolves to a user.

Notes from the spike for any provider: access token lifetime does not matter to the app (it
refreshes when a token expires within 120 s); keep refresh token rotation on, the app persists
the rotated token before using it; an administrator revoking the user's sessions or offline
tokens signs the user out in the app on the next refresh (`invalid_grant`).

## Migrating existing users from the OIDC_ISSUER fallback to a database provider

Users who signed in through `OIDC_ISSUER` before database providers existed have an unqualified
`core.users.oidc_subject` (the bare `sub`). Database providers store `<issuer>|<sub>`, and an
unqualified subject is deliberately never accepted for a database provider (a wrong guess would
attach an identity to the wrong person), so those users cannot sign in through it until their
subject is qualified or cleared (ADR 0055).

The database provider and the `OIDC_ISSUER` fallback cannot share an issuer. Creating or updating
a database provider whose issuer equals `OIDC_ISSUER` is refused with 409 ("this issuer is already
configured through OIDC_ISSUER"), enabled or not, and `PUT /admin/users/{id}/oidc-subject` only
accepts an issuer that already has a database provider row. So for the **same** issuer the
`OIDC_ISSUER` setting has to be removed before the database provider is added, and nothing in the
admin API can qualify subjects earlier. Clearing subjects first does not help either: while the
fallback is active, a cleared user signing in through it is bound again by e-mail with an
unqualified subject.

Supported order, when an administrator can sign in through a **different** identity provider
(a database provider with another issuer, which stays active throughout):

1. Remove `OIDC_ISSUER`/`OIDC_AUDIENCE` and restart the API. From now on tokens of that issuer
   are refused until step 2; users of that issuer cannot sign in meanwhile.
2. As the administrator of the other provider, add and test the database provider for the issuer
   (Admin > Identity providers, or `/api/v1/admin/identity-providers`).
3. For each affected user, either set the new subject with
   `PUT /api/v1/admin/users/{id}/oidc-subject` (body `{"issuer": "<issuer>", "subject": "<sub>"}`,
   or "Link identity" on the users page), or clear it (empty subject). A cleared user is bound by
   e-mail at the next sign-in, as the provider's e-mail rule allows.

If the issuer is the installation's only provider, no administrator can call the admin API after
step 1, so this order cannot be completed through the product: it needs a code change (for
example letting a database provider be staged, disabled, for the issuer that `OIDC_ISSUER` still
serves, then enabled when the fallback is removed). Until that exists, use the SQL recovery below
only as a deliberate break-glass step, and do not rely on an untested sequence.

Moving to a database provider with a **different** issuer has no such conflict: add it while
`OIDC_ISSUER` is set, fix the users as in step 3, and remove `OIDC_ISSUER`/`OIDC_AUDIENCE` last.

If the step was missed: users with an old subject are refused by the database provider. An
administrator who can still sign in fixes them with the same endpoint. If nobody can sign in,
restore `OIDC_ISSUER`/`OIDC_AUDIENCE` (the fallback accepts the unqualified subjects again), or
clear the subjects in SQL: `UPDATE core.users SET oidc_subject = NULL WHERE id = '<user id>'`, and
let the next sign-in bind by e-mail.
