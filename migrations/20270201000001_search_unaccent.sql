-- Accent-insensitive search (ADR 0057, roadmap D5).
--
-- "Liege" must find "Liège", "Koln" must find "Köln", "Werkstrasse" must find "Werkstraße".
-- `core.search_fold` lower-cases and strips accents; the list searches compare the folded column
-- with the folded search text (`core::search`). Both extensions are "trusted" (PostgreSQL 13+): the
-- owner of the database may create them, no superuser needed.

CREATE EXTENSION IF NOT EXISTS unaccent WITH SCHEMA public;
CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;

-- unaccent() is only STABLE, because its rules can be replaced, so an index cannot use it as it is.
-- This wrapper pins the dictionary by name and promises it does not change: should the rules ever
-- change, rebuild the indexes below (REINDEX) or the old entries no longer match.
CREATE FUNCTION core.search_fold(text) RETURNS text
    LANGUAGE sql IMMUTABLE PARALLEL SAFE STRICT
    AS $$ SELECT lower(public.unaccent('public.unaccent'::regdictionary, $1)) $$;

-- Trigram indexes on the folded columns, so `LIKE '%text%'` does not read the whole table once the
-- tables grow. A search ORs several columns; the planner only uses the indexes when every one of
-- them has one, hence all the columns a search looks at are here.
CREATE INDEX customers_code_fold_idx ON crm.customers
    USING gin (core.search_fold(code) public.gin_trgm_ops);
CREATE INDEX customers_name_fold_idx ON crm.customers
    USING gin (core.search_fold(name) public.gin_trgm_ops);
CREATE INDEX customers_vat_fold_idx ON crm.customers
    USING gin (core.search_fold(vat_number) public.gin_trgm_ops);
CREATE INDEX customers_city_fold_idx ON crm.customers
    USING gin (core.search_fold(city) public.gin_trgm_ops);

-- Contacts are found by "first last" or "last first" (and by their customer's name, above).
CREATE INDEX contacts_name_fold_idx ON crm.contacts
    USING gin (core.search_fold(first_name || ' ' || last_name) public.gin_trgm_ops);
CREATE INDEX contacts_name_reversed_fold_idx ON crm.contacts
    USING gin (core.search_fold(last_name || ' ' || first_name) public.gin_trgm_ops);

CREATE INDEX products_code_fold_idx ON products.products
    USING gin (core.search_fold(code) public.gin_trgm_ops);
CREATE INDEX products_name_fold_idx ON products.products
    USING gin (core.search_fold(name) public.gin_trgm_ops);

-- Suppliers are searched per company and stay in the hundreds, so they get no trigram index.
