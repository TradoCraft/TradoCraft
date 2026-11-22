CREATE TABLE core.user_preferences (
    user_id UUID PRIMARY KEY REFERENCES core.users(id) ON DELETE CASCADE,
    shortcuts JSONB NOT NULL DEFAULT '{}'::jsonb,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
