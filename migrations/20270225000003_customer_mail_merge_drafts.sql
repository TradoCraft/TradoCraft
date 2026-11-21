CREATE TABLE crm.mail_merge_drafts (
    company_id uuid NOT NULL REFERENCES core.companies(id),
    user_id uuid NOT NULL REFERENCES core.users(id),
    document_id uuid NOT NULL,
    revision integer NOT NULL,
    messages jsonb NOT NULL,
    recipients jsonb NOT NULL DEFAULT '{}',
    PRIMARY KEY (company_id, user_id),
    FOREIGN KEY (document_id, revision) REFERENCES kb.document_revisions(document_id, revision)
);
