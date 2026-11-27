-- Marketing opt-outs for the customer mail merge (ADR 0099). Existing business customers are
-- mailed on an opt-out basis; every mailing carries a one-click unsubscribe link.

-- Addresses that asked this company not to send mailings any more. Customers are shared master
-- data, but each company sends on its own behalf, so the register is per company. The address is
-- stored trimmed and lowercased, the same way the mail merge resolves recipients.
CREATE TABLE crm.mailing_opt_outs (
    company_id   uuid NOT NULL REFERENCES core.companies(id),
    email        text NOT NULL CHECK (email = lower(btrim(email)) AND email <> ''),
    opted_out_at timestamptz NOT NULL DEFAULT now(),
    -- staff: recorded by a user; unsubscribe_link: the recipient clicked the link in a mailing
    source       text NOT NULL CHECK (source IN ('staff', 'unsubscribe_link')),
    recorded_by  uuid REFERENCES core.users(id),
    PRIMARY KEY (company_id, email)
);
CREATE INDEX mailing_opt_outs_recent_idx ON crm.mailing_opt_outs (company_id, opted_out_at DESC);

-- SHA-256 of the unsubscribe token in the mail; the token itself is never stored. Deliveries
-- queued before this migration have none.
ALTER TABLE crm.mailing_deliveries ADD COLUMN unsubscribe_token_hash bytea UNIQUE;
