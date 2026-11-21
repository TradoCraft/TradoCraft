ALTER TABLE crm.mail_merge_drafts ADD COLUMN approved_preview jsonb;

CREATE TABLE crm.mailings (
    id uuid PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES core.companies(id),
    sender_id uuid NOT NULL REFERENCES core.users(id),
    document_id uuid NOT NULL,
    revision integer NOT NULL,
    confirmed_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (document_id, revision) REFERENCES kb.document_revisions(document_id, revision)
);
CREATE INDEX mailings_sender_idx ON crm.mailings (company_id, sender_id, confirmed_at DESC);

CREATE TABLE crm.mailing_deliveries (
    mailing_id uuid NOT NULL REFERENCES crm.mailings(id),
    customer_id uuid NOT NULL REFERENCES crm.customers(id),
    customer_name text NOT NULL,
    language text NOT NULL,
    outbox_id uuid NOT NULL UNIQUE REFERENCES core.mail_outbox(id),
    PRIMARY KEY (mailing_id, customer_id)
);
