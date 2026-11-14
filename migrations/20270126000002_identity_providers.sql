-- Identity providers an administrator configures in the app (ADR 0055). Verifying a token needs
-- only public information (issuer, audience, signing keys), so no secret is stored here.
CREATE TABLE core.identity_providers (
    id                    uuid PRIMARY KEY,
    name                  text NOT NULL CHECK (btrim(name) <> ''),
    -- Normalised: the trailing slash is stripped. The token's `iss` selects the provider.
    issuer                text NOT NULL UNIQUE CHECK (issuer !~ '/$'),
    audience              text NOT NULL CHECK (btrim(audience) <> ''),
    -- Public client of the interactive sign-in (authorization code + PKCE, no secret).
    client_id             text,
    scopes                text NOT NULL DEFAULT 'openid profile email',
    -- Accepted JWS algorithms; never HS* or none.
    algorithms            text[] NOT NULL DEFAULT ARRAY['RS256','RS384','RS512','ES256','ES384','PS256','PS384','PS512'],
    email_claim           text NOT NULL DEFAULT 'email',
    email_policy          text NOT NULL DEFAULT 'require_verified_claim'
                          CHECK (email_policy IN ('require_verified_claim','trust_provider_email','subject_only')),
    -- Boolean claim used by require_verified_claim (e.g. xms_edov for Microsoft Entra ID).
    verified_claim        text NOT NULL DEFAULT 'email_verified',
    -- When not empty, only e-mail addresses of these domains can be bound by e-mail.
    allowed_email_domains text[] NOT NULL DEFAULT '{}',
    enabled               boolean NOT NULL DEFAULT true,
    created_by            uuid REFERENCES core.users(id),
    created_at            timestamptz NOT NULL DEFAULT now(),
    updated_at            timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT identity_providers_algorithms_check CHECK (
        cardinality(algorithms) > 0
        AND algorithms <@ ARRAY['RS256','RS384','RS512','ES256','ES384','PS256','PS384','PS512']
    )
);
