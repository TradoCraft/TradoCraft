-- A6 (ADR 0072): what a prepared answer is for, which team owns it, and words that rank it.
ALTER TABLE helpdesk.prepared_answers
    ADD COLUMN kind text NOT NULL DEFAULT 'reply'
        CHECK (kind IN ('reply', 'internal_note', 'handover', 'notice')),
    ADD COLUMN team_id uuid REFERENCES helpdesk.teams(id),
    ADD COLUMN keywords text[] NOT NULL DEFAULT '{}';
CREATE INDEX prepared_answers_team_idx ON helpdesk.prepared_answers (company_id, team_id);
