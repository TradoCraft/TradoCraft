-- Approval limits for purchase orders (ADR 0062): the largest order (net total, in the company's
-- currency) a role may approve. A role without a row has no limit, so nothing changes until an
-- administrator sets one. Administrators are never limited and have no row.
CREATE TABLE purchasing.approval_limits (
    company_id         uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
    role               text NOT NULL,
    max_amount         numeric(15, 2) NOT NULL CHECK (max_amount >= 0),
    updated_by_user_id uuid REFERENCES core.users(id),
    updated_at         timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (company_id, role)
);
