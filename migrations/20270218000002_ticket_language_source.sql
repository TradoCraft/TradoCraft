-- A6 (ADR 0071): where a ticket's language came from. `record`: its contact, customer, creator or
-- the company default. `detected`: guessed from the first message. `agent`: given or changed by a person.
ALTER TABLE helpdesk.tickets
    ADD COLUMN language_source text NOT NULL DEFAULT 'record'
        CHECK (language_source IN ('record', 'detected', 'agent'));
