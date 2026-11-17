-- Helpdesk ticket checklists (A7): reusable templates, per-ticket checklist items,
-- idempotent template application tracking, and per-team close gate.

ALTER TABLE helpdesk.teams
    ADD COLUMN require_checklist_done boolean NOT NULL DEFAULT false;

CREATE TABLE helpdesk.checklist_templates (
    id          uuid PRIMARY KEY,
    company_id  uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
    name        text NOT NULL CHECK (btrim(name) <> ''),
    team_id     uuid REFERENCES helpdesk.teams(id) ON DELETE SET NULL,
    category    text,
    active      boolean NOT NULL DEFAULT true,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX checklist_templates_company_idx
    ON helpdesk.checklist_templates (company_id, active);

CREATE TABLE helpdesk.checklist_template_items (
    id          uuid PRIMARY KEY,
    template_id uuid NOT NULL REFERENCES helpdesk.checklist_templates(id) ON DELETE CASCADE,
    position    integer NOT NULL,
    description text NOT NULL CHECK (btrim(description) <> ''),
    UNIQUE (template_id, position)
);

CREATE TABLE helpdesk.ticket_checklist_items (
    id          uuid PRIMARY KEY,
    ticket_id   uuid NOT NULL REFERENCES helpdesk.tickets(id) ON DELETE CASCADE,
    template_id uuid REFERENCES helpdesk.checklist_templates(id) ON DELETE SET NULL,
    position    integer NOT NULL,
    description text NOT NULL CHECK (btrim(description) <> ''),
    done        boolean NOT NULL DEFAULT false,
    done_by     uuid REFERENCES core.users(id) ON DELETE SET NULL,
    done_at     timestamptz,
    UNIQUE (ticket_id, position)
);

CREATE TABLE helpdesk.ticket_applied_templates (
    ticket_id   uuid NOT NULL REFERENCES helpdesk.tickets(id) ON DELETE CASCADE,
    template_id uuid NOT NULL REFERENCES helpdesk.checklist_templates(id) ON DELETE CASCADE,
    applied_at  timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (ticket_id, template_id)
);
