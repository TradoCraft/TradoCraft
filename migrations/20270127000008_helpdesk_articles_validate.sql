-- Checks the existing rows against the constraints that were added NOT VALID. VALIDATE CONSTRAINT
-- takes only a SHARE UPDATE EXCLUSIVE lock: reads and writes go on while it scans.
ALTER TABLE helpdesk.articles VALIDATE CONSTRAINT articles_company_id_not_null;
ALTER TABLE helpdesk.articles VALIDATE CONSTRAINT articles_company_id_fkey;
ALTER TABLE helpdesk.tickets VALIDATE CONSTRAINT tickets_mailbox_id_fkey;
ALTER TABLE helpdesk.articles VALIDATE CONSTRAINT articles_mailbox_id_fkey;
