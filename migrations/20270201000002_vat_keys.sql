-- VAT number duplicate warning (ADR 0058, roadmap D4).
--
-- VAT numbers are stored as typed ("BE 0428.759.497", "be0428759497"). To find the same number
-- spelled differently, both sides are reduced to a key: letters and digits only, upper case, and
-- Greece's ISO prefix GR written as VIES writes it, EL. The key is computed, never stored, so there
-- is nothing to keep in step with the typed value. The expression indexes make the lookup exact
-- and cheap on any table size.

CREATE FUNCTION core.vat_key(text) RETURNS text
    LANGUAGE sql IMMUTABLE PARALLEL SAFE STRICT
    AS $$ SELECT regexp_replace(upper(regexp_replace($1, '[^A-Za-z0-9]', '', 'g')), '^GR', 'EL') $$;

-- Customers are shared master data (ADR 0003): one table for every company.
CREATE INDEX customers_vat_key_idx ON crm.customers (core.vat_key(vat_number))
    WHERE vat_number IS NOT NULL AND vat_number <> '';

-- A supplier's `tax_id` is its VAT number (or, outside the EU, whatever tax number it has). The
-- warning is within the company, so the company leads the index.
CREATE INDEX suppliers_vat_key_idx ON purchasing.suppliers (company_id, core.vat_key(tax_id))
    WHERE tax_id <> '';
