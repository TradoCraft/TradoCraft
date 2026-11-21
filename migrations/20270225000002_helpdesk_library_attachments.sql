ALTER TABLE helpdesk.ticket_attachments
    ADD COLUMN document_id uuid,
    ADD COLUMN document_revision integer,
    ADD COLUMN document_language text,
    ADD FOREIGN KEY (document_id, document_revision, document_language)
        REFERENCES kb.document_pdfs(document_id, revision, language) MATCH FULL;
