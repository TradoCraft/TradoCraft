-- The mailbox links added in the previous migration were created NOT VALID so that adding them
-- does not scan the tables while holding a lock; the existing rows are checked here.
ALTER TABLE helpdesk.tickets VALIDATE CONSTRAINT tickets_mailbox_id_fkey;
ALTER TABLE helpdesk.articles VALIDATE CONSTRAINT articles_mailbox_id_fkey;

-- A Message-ID is unique per company, not across the installation: two companies can receive the
-- same message (a mail to both), and one company's mail must not hide another's. The company comes
-- from the ticket; a trigger fills it so that the places that insert articles stay as they are.
ALTER TABLE helpdesk.articles ADD COLUMN company_id uuid REFERENCES core.companies(id);
UPDATE helpdesk.articles a SET company_id = t.company_id FROM helpdesk.tickets t WHERE t.id = a.ticket_id;
ALTER TABLE helpdesk.articles ALTER COLUMN company_id SET NOT NULL;

CREATE FUNCTION helpdesk.articles_set_company() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    SELECT company_id INTO NEW.company_id FROM helpdesk.tickets WHERE id = NEW.ticket_id;
    RETURN NEW;
END $$;
CREATE TRIGGER articles_set_company BEFORE INSERT ON helpdesk.articles
    FOR EACH ROW EXECUTE FUNCTION helpdesk.articles_set_company();

ALTER TABLE helpdesk.articles DROP CONSTRAINT articles_message_id_key;
CREATE UNIQUE INDEX articles_company_message_id_idx ON helpdesk.articles (company_id, message_id);
