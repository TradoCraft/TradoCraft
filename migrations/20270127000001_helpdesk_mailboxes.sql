-- Helpdesk mailboxes (ADR 0054). A company can have several mailboxes; each is read and sent
-- through Microsoft Graph (Exchange Online) or IMAP/SMTP (Exchange Server on-premises and any
-- other server). No secret is stored here: `secret_ref` names the worker environment variable
-- MAILBOX_SECRET_<secret_ref> that holds the password or the client secret.
CREATE TABLE helpdesk.mailboxes (
    id              uuid PRIMARY KEY,
    company_id      uuid NOT NULL REFERENCES core.companies(id),
    name            text NOT NULL CHECK (btrim(name) <> ''),
    -- The address customers write to and replies are sent from; stored in lower case.
    address         text NOT NULL CHECK (address = lower(address) AND position('@' in address) > 1),
    kind            text NOT NULL CHECK (kind IN ('graph', 'imap_smtp')),
    -- New tickets from this mailbox start in this team (else the company's default team).
    team_id         uuid REFERENCES helpdesk.teams(id) ON DELETE SET NULL,
    -- The mailbox for system mail and for replies on tickets that have no mailbox.
    is_default      boolean NOT NULL DEFAULT false,
    active          boolean NOT NULL DEFAULT true,
    -- Fetch incoming mail; off for a mailbox that only sends.
    inbound_enabled boolean NOT NULL DEFAULT true,
    secret_ref      text NOT NULL CHECK (secret_ref ~ '^[A-Z][A-Z0-9_]{0,39}$'),
    -- Microsoft Graph (application sign-in).
    tenant_id       text,
    client_id       text,
    -- IMAP and SMTP.
    username        text,
    imap_host       text,
    imap_port       integer CHECK (imap_port BETWEEN 1 AND 65535),
    imap_tls        boolean NOT NULL DEFAULT true,
    imap_folder     text NOT NULL DEFAULT 'INBOX',
    smtp_host       text,
    smtp_port       integer CHECK (smtp_port BETWEEN 1 AND 65535),
    smtp_security   text NOT NULL DEFAULT 'starttls' CHECK (smtp_security IN ('starttls', 'tls', 'none')),
    -- Written by the worker after every attempt to fetch mail.
    last_poll_at    timestamptz,
    last_ok_at      timestamptz,
    last_error      text,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    UNIQUE (company_id, address),
    UNIQUE (company_id, name),
    CHECK (kind <> 'graph' OR (tenant_id IS NOT NULL AND client_id IS NOT NULL)),
    CHECK (kind <> 'imap_smtp' OR (username IS NOT NULL AND smtp_host IS NOT NULL
                                   AND (imap_host IS NOT NULL OR NOT inbound_enabled)))
);
CREATE UNIQUE INDEX mailboxes_one_default_idx ON helpdesk.mailboxes (company_id) WHERE is_default;

-- The mailbox a ticket came in on: replies leave through it. Empty for tickets made by hand, from
-- the portal, or fetched through the worker's IMAP_* variables.
ALTER TABLE helpdesk.tickets ADD COLUMN mailbox_id uuid REFERENCES helpdesk.mailboxes(id) ON DELETE SET NULL;
-- The mailbox an e-mail was received on or is sent through.
ALTER TABLE helpdesk.articles ADD COLUMN mailbox_id uuid REFERENCES helpdesk.mailboxes(id) ON DELETE SET NULL;
