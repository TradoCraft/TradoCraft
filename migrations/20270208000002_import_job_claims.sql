-- Import jobs: tie every outcome to one claim, and tell the jobs run inside a request apart.

-- Set whenever a job becomes `running` (a worker's claim, or an inline run); a run may only write
-- progress and its outcome while its own token is still on the row, so a run that was reclaimed
-- in the meantime cannot overwrite what the next one does.
ALTER TABLE core.import_jobs ADD COLUMN claim_token uuid;

-- A job run inside the request of the admin screen. Nobody is waiting to see it applied later, so
-- the worker fails such a job when its heartbeat goes stale instead of queueing it again.
ALTER TABLE core.import_jobs ADD COLUMN inline boolean NOT NULL DEFAULT false;
