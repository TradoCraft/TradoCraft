-- ADR 0101: languages are no longer limited to five. The checks that listed nl, fr, en, de and es
-- become format checks (two lowercase letters); the API checks the code against ISO 639-1 and,
-- where a company publishes in a set of languages, against the company's configured languages.
ALTER TABLE core.users DROP CONSTRAINT users_language_check,
    ADD CONSTRAINT users_language_check CHECK (language ~ '^[a-z]{2}$');
ALTER TABLE crm.customers DROP CONSTRAINT customers_language_check,
    ADD CONSTRAINT customers_language_check CHECK (language ~ '^[a-z]{2}$');
ALTER TABLE crm.contacts DROP CONSTRAINT contacts_language_check,
    ADD CONSTRAINT contacts_language_check CHECK (language ~ '^[a-z]{2}$');
ALTER TABLE sales.quotation_lines DROP CONSTRAINT quotation_lines_customer_remark_language_check,
    ADD CONSTRAINT quotation_lines_customer_remark_language_check
        CHECK (customer_remark_language ~ '^[a-z]{2}$');
ALTER TABLE sales.favorite_item_remarks DROP CONSTRAINT favorite_item_remarks_language_check,
    ADD CONSTRAINT favorite_item_remarks_language_check CHECK (language ~ '^[a-z]{2}$');
ALTER TABLE helpdesk.tickets DROP CONSTRAINT tickets_language_check,
    ADD CONSTRAINT tickets_language_check CHECK (language ~ '^[a-z]{2}$');
ALTER TABLE helpdesk.prepared_answer_texts DROP CONSTRAINT prepared_answer_texts_language_check,
    ADD CONSTRAINT prepared_answer_texts_language_check CHECK (language ~ '^[a-z]{2}$');
ALTER TABLE kb.category_names DROP CONSTRAINT category_names_language_check,
    ADD CONSTRAINT category_names_language_check CHECK (language ~ '^[a-z]{2}$');
ALTER TABLE kb.entry_texts DROP CONSTRAINT entry_texts_language_check,
    ADD CONSTRAINT entry_texts_language_check CHECK (language ~ '^[a-z]{2}$');
ALTER TABLE kb.document_pdfs DROP CONSTRAINT document_pdfs_language_check,
    ADD CONSTRAINT document_pdfs_language_check CHECK (language ~ '^[a-z]{2}$');
ALTER TABLE pricing.price_list_zone_languages
    DROP CONSTRAINT price_list_zone_languages_language_check,
    ADD CONSTRAINT price_list_zone_languages_language_check CHECK (language ~ '^[a-z]{2}$');

-- Full-text search of the knowledge base: every language Postgres ships a text search
-- configuration for gets it; any other language uses the language-neutral `simple` configuration
-- (existing texts are unaffected: only nl, fr, en, de and es could be stored before).
CREATE OR REPLACE FUNCTION kb.config(lang text) RETURNS regconfig
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT CASE lang
        WHEN 'nl' THEN 'dutch'::regconfig
        WHEN 'fr' THEN 'french'::regconfig
        WHEN 'de' THEN 'german'::regconfig
        WHEN 'es' THEN 'spanish'::regconfig
        WHEN 'ar' THEN 'arabic'::regconfig
        WHEN 'hy' THEN 'armenian'::regconfig
        WHEN 'eu' THEN 'basque'::regconfig
        WHEN 'ca' THEN 'catalan'::regconfig
        WHEN 'da' THEN 'danish'::regconfig
        WHEN 'fi' THEN 'finnish'::regconfig
        WHEN 'el' THEN 'greek'::regconfig
        WHEN 'hi' THEN 'hindi'::regconfig
        WHEN 'hu' THEN 'hungarian'::regconfig
        WHEN 'id' THEN 'indonesian'::regconfig
        WHEN 'ga' THEN 'irish'::regconfig
        WHEN 'it' THEN 'italian'::regconfig
        WHEN 'lt' THEN 'lithuanian'::regconfig
        WHEN 'ne' THEN 'nepali'::regconfig
        WHEN 'no' THEN 'norwegian'::regconfig
        WHEN 'nb' THEN 'norwegian'::regconfig
        WHEN 'nn' THEN 'norwegian'::regconfig
        WHEN 'pt' THEN 'portuguese'::regconfig
        WHEN 'ro' THEN 'romanian'::regconfig
        WHEN 'ru' THEN 'russian'::regconfig
        WHEN 'sr' THEN 'serbian'::regconfig
        WHEN 'sv' THEN 'swedish'::regconfig
        WHEN 'ta' THEN 'tamil'::regconfig
        WHEN 'tr' THEN 'turkish'::regconfig
        WHEN 'yi' THEN 'yiddish'::regconfig
        WHEN 'en' THEN 'english'::regconfig
        ELSE 'simple'::regconfig
    END
$$;

-- The position of a language in the company's configured order; a language the company no
-- longer has comes after all configured ones (ADR 0101).
CREATE FUNCTION core.language_order(company uuid, lang text) RETURNS integer
LANGUAGE sql STABLE PARALLEL SAFE AS $$
    SELECT coalesce((SELECT l.sort_order FROM core.company_languages l
                     WHERE l.company_id = company AND l.language = lang), 1000)
$$;

-- The rank of a language in the fallback chain for content wanted in `requested`: the requested
-- language, English, the company's default, then the company's order (ADR 0101).
CREATE FUNCTION core.language_rank(company uuid, requested text, lang text) RETURNS integer
LANGUAGE sql STABLE PARALLEL SAFE AS $$
    SELECT CASE
        WHEN lang = requested THEN 0
        WHEN lang = 'en' THEN 1
        WHEN lang = (SELECT c.default_language::text FROM core.companies c WHERE c.id = company) THEN 2
        ELSE 3 + core.language_order(company, lang)
    END
$$;
