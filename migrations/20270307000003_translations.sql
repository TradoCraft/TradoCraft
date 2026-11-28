-- ADR 0101: translation catalogues a company adds or overrides, per domain and language. The
-- application ships the texts of `documents` and `mail` in its binary; `app` and `web` hold
-- interface texts the clients load at runtime over their compiled-in texts.
CREATE TABLE core.translations (
    company_id uuid NOT NULL REFERENCES core.companies (id) ON DELETE CASCADE,
    domain     text NOT NULL CHECK (domain IN ('documents', 'mail', 'app', 'web')),
    language   text NOT NULL CHECK (language ~ '^[a-z]{2}$'),
    -- key -> text
    entries    jsonb NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(entries) = 'object'),
    updated_at timestamptz NOT NULL DEFAULT now(),
    updated_by uuid REFERENCES core.users (id),
    PRIMARY KEY (company_id, domain, language)
);
