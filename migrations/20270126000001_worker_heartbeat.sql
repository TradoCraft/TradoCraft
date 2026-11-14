-- Worker heartbeat (ADR 0052, roadmap D1). The background worker writes one row on every pass;
-- the API reports its age to administrators. Several workers may run at once: the row says that
-- at least one of them is alive, not which.
CREATE TABLE core.worker_heartbeat (
    -- One row only.
    id               boolean PRIMARY KEY DEFAULT true CHECK (id),
    last_beat_at     timestamptz NOT NULL,
    -- When the worker process that wrote the last beat started.
    started_at       timestamptz NOT NULL,
    -- That worker's polling interval (POLL_SECONDS): the beat is late after a few of these.
    interval_seconds integer NOT NULL CHECK (interval_seconds > 0),
    version          text NOT NULL,
    host             text NOT NULL
);

-- Periods in which no worker beat, recorded when a worker comes back after a gap. Not per company:
-- the worker serves every company in the database.
CREATE TABLE core.worker_outages (
    id          uuid PRIMARY KEY,
    down_from   timestamptz NOT NULL,
    down_until  timestamptz NOT NULL,
    CHECK (down_until > down_from)
);
CREATE INDEX worker_outages_recent_idx ON core.worker_outages (down_until DESC);
