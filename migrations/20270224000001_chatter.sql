-- Chatter, followers and activities on records (ADR 0086).
--
-- One polymorphic address (record_kind, record_id) without a foreign key to the record: the record
-- lives in another module's table (same trade-off as todo.items.link_kind, ADR 0061). The API
-- checks that the record exists in the caller's company before it reads or writes anything here.
-- The first kinds are customers, quotations, orders and opportunities.
CREATE SCHEMA IF NOT EXISTS chatter;

-- Notes written by people and curated change messages ("system") written next to the audit event.
CREATE TABLE chatter.messages (
    id             uuid PRIMARY KEY,
    company_id     uuid NOT NULL REFERENCES core.companies(id),
    record_kind    text NOT NULL CHECK (record_kind IN ('customer', 'quotation', 'order', 'opportunity')),
    record_id      uuid NOT NULL,
    kind           text NOT NULL CHECK (kind IN ('note', 'system')),
    -- empty for a change made by the system (a worker, a customer in the portal)
    author_user_id uuid REFERENCES core.users(id),
    body           text NOT NULL DEFAULT '' CHECK (char_length(body) <= 10000),
    -- tracked fields of a system message: [{"field", "from", "to"}]
    changes        jsonb NOT NULL DEFAULT '[]',
    -- chosen by the client so that a retried post does not post twice
    client_id      uuid,
    created_at     timestamptz NOT NULL DEFAULT now(),
    edited_at      timestamptz,
    CHECK (kind = 'system' OR (author_user_id IS NOT NULL AND btrim(body) <> ''))
);
CREATE INDEX chatter_messages_record_idx
    ON chatter.messages (company_id, record_kind, record_id, created_at DESC, id DESC);
CREATE UNIQUE INDEX chatter_messages_client_idx
    ON chatter.messages (company_id, client_id) WHERE client_id IS NOT NULL;

-- Followers. `muted_at` is an explicit unfollow, honoured until the user acts on the record again.
CREATE TABLE chatter.followers (
    company_id   uuid NOT NULL REFERENCES core.companies(id),
    record_kind  text NOT NULL CHECK (record_kind IN ('customer', 'quotation', 'order', 'opportunity')),
    record_id    uuid NOT NULL,
    user_id      uuid NOT NULL REFERENCES core.users(id),
    reason       text NOT NULL DEFAULT 'manual' CHECK (reason IN ('manual', 'author', 'assigned')),
    muted_at     timestamptz,
    followed_at  timestamptz NOT NULL DEFAULT now(),
    -- what the user has seen of the thread; unread is "a message by someone else after this"
    last_read_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (company_id, record_kind, record_id, user_id)
);
CREATE INDEX chatter_followers_user_idx ON chatter.followers (company_id, user_id)
    WHERE muted_at IS NULL;

-- Scheduled activities: visible to everyone who can read the record, unlike a private to-do.
CREATE TABLE chatter.activities (
    id          uuid PRIMARY KEY,
    company_id  uuid NOT NULL REFERENCES core.companies(id),
    record_kind text NOT NULL CHECK (record_kind IN ('customer', 'quotation', 'order', 'opportunity')),
    record_id   uuid NOT NULL,
    kind        text NOT NULL CHECK (kind IN ('todo', 'call', 'email', 'meeting')),
    summary     text NOT NULL CHECK (btrim(summary) <> '' AND char_length(summary) <= 200),
    note        text NOT NULL DEFAULT '' CHECK (char_length(note) <= 4000),
    assignee_id uuid NOT NULL REFERENCES core.users(id),
    due_date    date NOT NULL,
    created_by  uuid NOT NULL REFERENCES core.users(id),
    done_at     timestamptz,
    done_by     uuid REFERENCES core.users(id),
    done_note   text NOT NULL DEFAULT '' CHECK (char_length(done_note) <= 4000),
    client_id   uuid,
    created_at  timestamptz NOT NULL DEFAULT now(),
    CHECK ((done_at IS NULL) = (done_by IS NULL))
);
CREATE INDEX chatter_activities_record_idx
    ON chatter.activities (company_id, record_kind, record_id, due_date);
CREATE INDEX chatter_activities_assignee_idx
    ON chatter.activities (company_id, assignee_id, due_date) WHERE done_at IS NULL;
CREATE UNIQUE INDEX chatter_activities_client_idx
    ON chatter.activities (company_id, client_id) WHERE client_id IS NOT NULL;
