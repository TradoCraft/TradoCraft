-- Production division membership (ADR 0049): which users work in which division. A user can be a
-- member of several divisions. Membership only sets the default scope of the production queue.
-- Divisions and users are company-scoped, so the row carries the company and both foreign keys
-- are composite: a member of another company cannot be linked.
ALTER TABLE production.divisions ADD CONSTRAINT divisions_id_company_key UNIQUE (id, company_id);

CREATE TABLE production.division_members (
    company_id  uuid NOT NULL REFERENCES core.companies(id),
    division_id uuid NOT NULL,
    user_id     uuid NOT NULL REFERENCES core.users(id) ON DELETE CASCADE,
    PRIMARY KEY (division_id, user_id),
    FOREIGN KEY (division_id, company_id) REFERENCES production.divisions (id, company_id) ON DELETE CASCADE,
    FOREIGN KEY (user_id, company_id) REFERENCES core.user_companies (user_id, company_id) ON DELETE CASCADE
);
CREATE INDEX division_members_user_idx ON production.division_members (user_id);
