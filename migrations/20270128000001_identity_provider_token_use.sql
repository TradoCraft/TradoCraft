-- Which token the interactive sign-in sends as the bearer token (ADR 0053): the ID token
-- (default; `aud` = client id) or the access token (e.g. Microsoft Entra ID, our own API).
-- The server verifies either the same way (signature, issuer, audience), so this only tells
-- the client what to send.
ALTER TABLE core.identity_providers
    ADD COLUMN token_use text NOT NULL DEFAULT 'id_token'
        CHECK (token_use IN ('id_token','access_token'));
