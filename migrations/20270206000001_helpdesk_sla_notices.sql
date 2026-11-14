-- SLA notices to the customer (ADR 0064): which tickets get an acknowledgement and a breach notice,
-- per team and priority, and a log that keeps each notice to once per ticket.
CREATE TABLE helpdesk.sla_notice_settings (
    id              uuid PRIMARY KEY,
    company_id      uuid NOT NULL REFERENCES core.companies(id),
    -- null = every team / every priority
    team_id         uuid REFERENCES helpdesk.teams(id) ON DELETE CASCADE,
    priority        text CHECK (priority IN ('low', 'normal', 'high', 'urgent')),
    ack_enabled     boolean NOT NULL DEFAULT false,
    breach_enabled  boolean NOT NULL DEFAULT false,
    updated_at      timestamptz NOT NULL DEFAULT now(),
    UNIQUE NULLS NOT DISTINCT (company_id, team_id, priority)
);

CREATE TABLE helpdesk.sla_notice_log (
    ticket_id   uuid NOT NULL REFERENCES helpdesk.tickets(id) ON DELETE CASCADE,
    kind        text NOT NULL CHECK (kind IN ('ack', 'breach')),
    company_id  uuid NOT NULL REFERENCES core.companies(id),
    address     text NOT NULL,
    sent_at     timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (ticket_id, kind)
);
-- The per-address rate limit looks at recent notices to one address.
CREATE INDEX sla_notice_log_address_idx ON helpdesk.sla_notice_log (company_id, address, sent_at);
