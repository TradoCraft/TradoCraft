-- The validated check lets SET NOT NULL skip the scan; the check is then redundant. The old
-- installation-wide unique constraint goes last, after the per-company index exists.
ALTER TABLE helpdesk.articles ALTER COLUMN company_id SET NOT NULL;
ALTER TABLE helpdesk.articles DROP CONSTRAINT articles_company_id_not_null;
ALTER TABLE helpdesk.articles DROP CONSTRAINT articles_message_id_key;
