-- Step towards NOT NULL without a scan under a heavy lock: the check is added NOT VALID (instant);
-- the next migration validates it, and SET NOT NULL then skips its own scan (PostgreSQL 12+; the
-- project runs 16). Kept in a migration of its own because ADD CONSTRAINT takes an exclusive lock
-- until the end of its transaction, which must not include the validating scan.
ALTER TABLE helpdesk.articles ADD CONSTRAINT articles_company_id_not_null
    CHECK (company_id IS NOT NULL) NOT VALID;
