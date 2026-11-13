-- Concurrent-edit protection (ADR 0060, roadmap D3).
--
-- A row version on the records people edit by hand. The API returns it, the app sends it back as
-- `expected_version` when saving, and a save against an older version is refused (409
-- `record_changed`) instead of overwriting the other person's work.
--
-- The trigger bumps the version on every UPDATE of the row, whichever statement it comes from, so
-- no `UPDATE` in the code has to remember to do it (several of them do not touch `updated_at`).
-- Adding a column with a constant default does not rewrite the table on PostgreSQL 11 and later.

CREATE OR REPLACE FUNCTION core.bump_row_version() RETURNS trigger
    LANGUAGE plpgsql AS
$$
BEGIN
    NEW.version := OLD.version + 1;
    RETURN NEW;
END;
$$;

ALTER TABLE crm.customers    ADD COLUMN version bigint NOT NULL DEFAULT 1;
ALTER TABLE sales.quotations ADD COLUMN version bigint NOT NULL DEFAULT 1;
ALTER TABLE sales.orders     ADD COLUMN version bigint NOT NULL DEFAULT 1;

CREATE TRIGGER customers_bump_version    BEFORE UPDATE ON crm.customers
    FOR EACH ROW EXECUTE FUNCTION core.bump_row_version();
CREATE TRIGGER quotations_bump_version   BEFORE UPDATE ON sales.quotations
    FOR EACH ROW EXECUTE FUNCTION core.bump_row_version();
CREATE TRIGGER orders_bump_version       BEFORE UPDATE ON sales.orders
    FOR EACH ROW EXECUTE FUNCTION core.bump_row_version();
