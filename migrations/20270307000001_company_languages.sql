-- ADR 0101: the content languages of a company, configured by its administrators. Any ISO 639-1
-- code (the API checks the code against the list; the database only checks the format). The
-- company's default language (core.companies.default_language) is always one of them.
CREATE TABLE core.company_languages (
    company_id uuid NOT NULL REFERENCES core.companies (id) ON DELETE CASCADE,
    language   text NOT NULL CHECK (language ~ '^[a-z]{2}$'),
    sort_order integer NOT NULL CHECK (sort_order >= 0),
    PRIMARY KEY (company_id, language),
    UNIQUE (company_id, sort_order) DEFERRABLE INITIALLY DEFERRED
);

-- The default language may be any language code now (the API checks it against ISO 639-1).
ALTER TABLE core.companies DROP CONSTRAINT companies_default_language_check,
    ADD CONSTRAINT companies_default_language_check CHECK (default_language ~ '^[a-z]{2}$');

-- Existing companies keep exactly what they had: the five languages that were built in, in the
-- order the application listed them, with the company's default included in any case.
INSERT INTO core.company_languages (company_id, language, sort_order)
SELECT c.id, l.language, l.ord - 1
FROM core.companies c
CROSS JOIN unnest(ARRAY['nl', 'fr', 'en', 'de', 'es']) WITH ORDINALITY AS l (language, ord);

-- A company always has at least its default language: a company inserted without going through
-- provisioning (which sets the whole list) starts with just that one.
CREATE FUNCTION core.company_default_language_row() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO core.company_languages (company_id, language, sort_order)
    VALUES (NEW.id, NEW.default_language, 0)
    ON CONFLICT (company_id, language) DO NOTHING;
    RETURN NEW;
END
$$;
CREATE TRIGGER companies_default_language_row
    AFTER INSERT ON core.companies
    FOR EACH ROW EXECUTE FUNCTION core.company_default_language_row();
