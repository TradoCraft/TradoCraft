-- The company's logo, printed on documents that ask for it (price lists first). One row per
-- company; no row means no logo. The API validates type (PNG, JPEG, SVG by signature) and size.
CREATE TABLE core.company_logos (
    company_id    uuid PRIMARY KEY REFERENCES core.companies(id),
    content_type  text NOT NULL CHECK (content_type IN ('image/png', 'image/jpeg', 'image/svg+xml')),
    bytes         bytea NOT NULL CHECK (octet_length(bytes) BETWEEN 1 AND 524288),
    updated_at    timestamptz NOT NULL DEFAULT now()
);
