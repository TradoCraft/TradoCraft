-- A Message-ID is unique per company, not across the installation: two companies can receive the
-- same message (a mail to both), and one company's mail must not hide another's. The company comes
-- from the ticket; a trigger fills it so that the places that insert articles stay as they are.
--
-- The change to the big articles table is done in small steps (this and the next five migrations)
-- so that no step holds a heavy lock for long: this one only adds the column, a link that is not
-- checked yet, and the trigger. The trigger comes before the backfill so that articles inserted
-- in between get their company too.
ALTER TABLE helpdesk.articles ADD COLUMN company_id uuid;
ALTER TABLE helpdesk.articles ADD CONSTRAINT articles_company_id_fkey
    FOREIGN KEY (company_id) REFERENCES core.companies(id) NOT VALID;

CREATE FUNCTION helpdesk.articles_set_company() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    SELECT company_id INTO NEW.company_id FROM helpdesk.tickets WHERE id = NEW.ticket_id;
    RETURN NEW;
END $$;
CREATE TRIGGER articles_set_company BEFORE INSERT ON helpdesk.articles
    FOR EACH ROW EXECUTE FUNCTION helpdesk.articles_set_company();
