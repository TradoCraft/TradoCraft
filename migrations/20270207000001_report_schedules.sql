-- Scheduled report mails (ADR 0065): one scheduler for saved custom reports (ADR 0042) and the
-- helpdesk reports (ADR 0021). The worker finds due rows, builds the file as the schedule's owner
-- and queues one mail per recipient in core.mail_outbox.
CREATE TABLE reports.schedules (
    id            uuid PRIMARY KEY,
    company_id    uuid NOT NULL REFERENCES core.companies(id),
    -- The person whose permissions the report runs with, every time.
    owner_id      uuid NOT NULL REFERENCES core.users(id),
    name          text NOT NULL CHECK (btrim(name) <> ''),
    source        text NOT NULL CHECK (source IN ('custom', 'helpdesk')),
    report_id     uuid REFERENCES reports.reports(id) ON DELETE CASCADE,
    -- {table, period, team_id, owner_id, category, group}
    helpdesk      jsonb,
    frequency     text NOT NULL CHECK (frequency IN ('daily', 'weekly', 'monthly')),
    weekday       smallint CHECK (weekday BETWEEN 1 AND 7),
    day_of_month  smallint CHECK (day_of_month BETWEEN 1 AND 28),
    send_time     time NOT NULL DEFAULT '07:00',
    time_zone     text NOT NULL DEFAULT 'Europe/Brussels',
    format        text NOT NULL CHECK (format IN ('csv', 'pdf')),
    user_ids      uuid[] NOT NULL DEFAULT '{}',
    addresses     text[] NOT NULL DEFAULT '{}',
    active        boolean NOT NULL DEFAULT true,
    next_run_at   timestamptz NOT NULL,
    last_run_at   timestamptz,
    last_status   text CHECK (last_status IN ('sent', 'failed')),
    last_error    text,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    CHECK ((source = 'custom' AND report_id IS NOT NULL AND helpdesk IS NULL)
        OR (source = 'helpdesk' AND report_id IS NULL AND helpdesk IS NOT NULL)),
    CHECK ((frequency = 'weekly') = (weekday IS NOT NULL)),
    CHECK ((frequency = 'monthly') = (day_of_month IS NOT NULL))
);
CREATE INDEX report_schedules_due_idx ON reports.schedules (next_run_at) WHERE active;
CREATE INDEX report_schedules_company_idx ON reports.schedules (company_id, name);
