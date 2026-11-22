-- Annual customer rebate settings, tier schedules, opening balances, and approved pricing rates.
CREATE TABLE finance.customer_rebate_settings (
    company_id      uuid PRIMARY KEY REFERENCES core.companies(id) ON DELETE CASCADE,
    show_on_invoices boolean NOT NULL DEFAULT false,
    wording         jsonb NOT NULL CHECK (jsonb_typeof(wording) = 'array')
);

CREATE TABLE finance.customer_rebate_schedules (
    id              uuid PRIMARY KEY,
    company_id      uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
    name            text NOT NULL CHECK (btrim(name) <> ''),
    effective_year  integer NOT NULL CHECK (effective_year BETWEEN 2 AND 9999),
    tiers           jsonb NOT NULL CHECK (jsonb_typeof(tiers) = 'array'),
    UNIQUE (company_id, name, effective_year),
    UNIQUE (company_id, id)
);

CREATE TABLE finance.customer_rebate_assignments (
    company_id      uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
    customer_id     uuid NOT NULL REFERENCES crm.customers(id) ON DELETE CASCADE,
    schedule_name   text NOT NULL CHECK (btrim(schedule_name) <> ''),
    PRIMARY KEY (company_id, customer_id)
);

-- Currency is the legal entity's currency. The amount includes activity through cutoff.
CREATE TABLE finance.customer_rebate_openings (
    company_id      uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
    customer_id     uuid NOT NULL REFERENCES crm.customers(id) ON DELETE CASCADE,
    year            integer NOT NULL CHECK (year BETWEEN 2 AND 9999),
    cutoff          date NOT NULL,
    eligible_sales  numeric(19, 2) NOT NULL,
    verified_by     uuid NOT NULL REFERENCES core.users(id),
    verified_at     timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (company_id, customer_id, year),
    CHECK (cutoff BETWEEN make_date(year - 1, 12, 31) AND make_date(year, 12, 31)),
    CHECK (cutoff >= make_date(year, 1, 1) OR eligible_sales = 0)
);

-- Keep the approved rate and its basis even if a schedule or its inputs later change.
CREATE TABLE finance.customer_rebate_rates (
    company_id      uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
    customer_id     uuid NOT NULL REFERENCES crm.customers(id) ON DELETE CASCADE,
    rate_year       integer NOT NULL CHECK (rate_year BETWEEN 2 AND 9999),
    schedule_id     uuid NOT NULL,
    eligible_sales  numeric(19, 2) NOT NULL,
    rate            numeric(7, 4) NOT NULL CHECK (rate BETWEEN 0 AND 100),
    approved_by     uuid NOT NULL REFERENCES core.users(id),
    approved_at     timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (company_id, customer_id, rate_year),
    FOREIGN KEY (company_id, schedule_id) REFERENCES finance.customer_rebate_schedules(company_id, id)
);
