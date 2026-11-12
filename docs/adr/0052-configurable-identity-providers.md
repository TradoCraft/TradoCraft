# 0052 — Configurable identity providers

**Status:** Accepted

**Context.** [ADR 0004](0004-authentication.md) signs people in through OpenID Connect against one
issuer read from `OIDC_ISSUER` and `OIDC_AUDIENCE` at start-up. Changing the identity provider
means editing the environment and restarting, and an installation cannot accept two providers
(for example Microsoft Entra ID for staff and Keycloak for a partner). The verifier was also
thin: no timeouts, no size limit, no URL checks, keys cached forever and re-fetched on every
unknown `kid`, no algorithm allow-list. The administrator now configures identity providers in the
app, which makes the URLs they type an input the server fetches: it has to be treated as untrusted.
A token is verified before the company is known, and `core.users` is global, so a provider cannot
belong to a company.

**Decision.** ADR 0004 stays valid (roles per company in the ERP, users provisioned in the ERP,
the identity provider only proves who someone is); this ADR replaces its "one issuer from the
environment" part.

*Providers per installation.* `core.identity_providers` holds any number of providers: name,
issuer (normalised, trailing slash stripped, unique), audience, optional `client_id` and `scopes`
(the public client of the interactive sign-in of a later phase; no client secret is stored, because
verifying a token needs only public information, so there is no encryption at rest to design),
accepted algorithms, the e-mail claim, the e-mail policy, the name of the verification claim, an
optional list of allowed e-mail domains and `enabled`. Presets (Entra ID, Keycloak, Google) live in
the app and only fill this form; the server stores plain settings. Out of scope: client secrets,
SCIM or just-in-time provisioning (users are still created in the ERP), and per-company providers.

*Selection by issuer.* The verifier reads the unverified `iss` only to choose the configuration; the
signature is then verified with that provider's keys, and `iss` must equal the provider's issuer
again afterwards. An unknown or disabled issuer is 401. The same issuer cannot be configured twice,
nor in the database and in the environment.

*Hardened verifier.* Discovery and JWKS are fetched with a 5 s connect and 10 s total timeout, no
redirects, and a 1 MiB body limit. The discovery `issuer` must equal the configured issuer
(otherwise no key is trusted) and `jwks_uri` obeys the URL rules below. Keys are cached for one
hour and refreshed early when a token carries an unknown `kid`, at most once per 30 s per provider
(so a flood of forged `kid`s cannot make the API hammer the provider). The token header's algorithm
must be in the provider's list, which can only contain RS*, ES* and PS* algorithms (never HS*,
EdDSA or `none`, also not in the database constraint). `exp` is required; `exp` and `nbf` are
checked with 60 s leeway; `aud` must contain the audience; `sub` is required. Claims are read as a
JSON map so the configured claim names work. Tokens are never logged.

*URL rules (SSRF).* Admin-supplied URLs must be `https`, without credentials. The host is resolved
and every resulting address must be public: loopback, private, link-local (including the
169.254.169.254 metadata address), CGNAT, unique-local, multicast, unspecified and reserved ranges
(also when embedded in an IPv6 address) are refused. The checked addresses are pinned for the
connection, so a DNS answer cannot change between check and connect. The only exception is
`ALLOW_INSECURE_IDP_URLS=true`, meant for local development and tests, which the API refuses to
honour unless `AUTH_MODE=dev` or the bind address is loopback (like the dev-auth guard).

*E-mail trust policies.* The first sign-in of a person binds the identity to the user found by
e-mail; per provider, `email_policy` says when that is allowed:
`require_verified_claim` (default: the claim named in `verified_claim`, `email_verified` unless
changed, e.g. `xms_edov` for Entra ID, must be true; the strings "true"/"1" and the number 1 count
as true), `trust_provider_email` (no verification claim; for a single-company directory such as
an Entra tenant where the company controls every address), and `subject_only` (never bind by
e-mail: only users whose subject an administrator set can sign in, through
`PUT /admin/users/{id}/oidc-subject`). When `allowed_email_domains` is not empty, only addresses of
those domains can be bound by e-mail. A user already bound to another subject is refused, as before.

*Issuer-qualified subjects.* The same `sub` can legitimately repeat across issuers, so for database
providers `core.users.oidc_subject` stores `<issuer>|<sub>`. The environment provider keeps the
legacy unqualified `sub` so existing installations keep working; nothing is migrated silently (a
migration would need to know which issuer each stored subject came from, and a wrong guess would
lock someone out or attach an identity to the wrong person). Moving a user to a database provider
means setting the new subject with the endpoint above or letting the next sign-in bind by e-mail
after clearing the old one.

*Environment fallback.* `OIDC_ISSUER` and `OIDC_AUDIENCE` (plus the optional `OIDC_CLIENT_ID` and
`OIDC_SCOPES`, default `openid profile email`, which make interactive sign-in possible for it) become
an optional, read-only provider (source `env`): listed in the admin screen, never editable or deletable there, available when the
database providers are wrong or gone. `AUTH_MODE=oidc` may start without them when the database
has providers; with neither, every request answers 401 and the bootstrap with `BOOTSTRAP_TOKEN`
still works.

*Who may edit.* New permission `identity.admin`, always on (like `users.admin`) and granted to the
`admin` role only. Because roles are per company but providers decide who can sign in to the whole
installation, the caller must in addition hold the admin role in the installation's *primary
company*, an explicit flag (`core.companies.is_primary`, at most one company, enforced by a unique
partial index). A migration flags the oldest company on existing installations and the bootstrap
flags the first company of an empty database; if no company were primary the oldest is used. An
administrator of another company cannot change the providers. `POST /admin/companies/{id}/make-primary`
moves the flag in one transaction (audited, `company` / `made_primary`); only an administrator of the
current primary company may call it, an unknown company is 404 and the current primary one 409.
This replaces the earlier rule "the oldest company", which a later deletion or import could change
silently.

*Lock-out safeguards.* Create and update read discovery and keys and are rejected (422 with the
reason) when they cannot be read or the issuer does not match (a disabled provider is not probed on
update, so it can be switched off while its provider is down). The test endpoint tries a draft or
saved configuration, optionally with a sample token, and shows keys, algorithms, `claims_supported`,
the check results and which user the token would bind to (or why not), without binding or storing
anything. Disabling, deleting or changing the issuer of the last enabled provider is refused (409)
unless the environment fallback exists or `confirm_lockout` is set, and so is doing it to the
provider the caller's own token came from. Every change is audited (`identity_provider`).

*Hot reload.* The registry sits behind a lock inside `AuthConfig::Oidc`. It loads at start-up, is
reloaded right after every admin change, and every 60 s so other API instances follow. Key caches
survive a reload for providers whose settings did not change.

*Public list.* `GET /api/v1/auth/providers` (no sign-in) returns `name`, `issuer`, `client_id`,
`scopes` and `source` (`database` or `env`, so the page can label the fallback) of the enabled providers for the sign-in page; nothing else. Empty in dev mode.
