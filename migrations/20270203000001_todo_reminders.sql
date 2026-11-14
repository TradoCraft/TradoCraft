-- To-do reminders (ADR 0061, PR 3): a per-user, per-company switch for the reminder mail, stored on
-- the server so that it follows the user across devices. No row means the default: reminders on.
CREATE TABLE todo.user_settings (
    user_id         uuid NOT NULL REFERENCES core.users(id),
    company_id      uuid NOT NULL REFERENCES core.companies(id),
    email_reminders boolean NOT NULL DEFAULT true,
    updated_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, company_id)
);

-- The reminder pass looks for open items that are due and not yet reminded.
CREATE INDEX todo_items_unreminded_idx ON todo.items (due_date)
    WHERE NOT done AND reminded_at IS NULL AND due_date IS NOT NULL;
