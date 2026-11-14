-- Automation action `send_email` (ADR 0063): the loop guard. One row per rule, ticket and action
-- position records when that action last queued its mail; the guard is an atomic upsert.
CREATE TABLE helpdesk.automation_mail_log (
    company_id  uuid NOT NULL REFERENCES core.companies(id),
    rule_id     uuid NOT NULL REFERENCES helpdesk.automation_rules(id) ON DELETE CASCADE,
    ticket_id   uuid NOT NULL REFERENCES helpdesk.tickets(id) ON DELETE CASCADE,
    action_no   integer NOT NULL,
    sent_at     timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (rule_id, ticket_id, action_no)
);
CREATE INDEX automation_mail_log_ticket_idx ON helpdesk.automation_mail_log (ticket_id);
