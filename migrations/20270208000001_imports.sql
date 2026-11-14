-- Data import (ADR 0064): the uploaded files, the saved column mappings and the import jobs.

-- An uploaded file waiting to be imported. Kept apart from core.files: other types, sizes (up to
-- 50 MiB) and a short life (the worker removes a file 7 days after the upload).
CREATE TABLE core.import_files (
    id          uuid PRIMARY KEY,
    company_id  uuid NOT NULL REFERENCES core.companies(id),
    filename    text NOT NULL CHECK (btrim(filename) <> ''),
    -- detected from the bytes, never from the file name
    format      text NOT NULL CHECK (format IN ('csv', 'xlsx', 'ods')),
    size_bytes  bigint NOT NULL CHECK (size_bytes >= 0),
    data        bytea NOT NULL,
    uploaded_by uuid REFERENCES core.users(id),
    created_at  timestamptz NOT NULL DEFAULT now()
);
-- Listing what to clean up, and a company's files.
CREATE INDEX import_files_created_idx ON core.import_files (created_at);
CREATE INDEX import_files_company_idx ON core.import_files (company_id, created_at DESC);

-- A saved `file column -> field` mapping of one entity, proposed again for the next file.
CREATE TABLE core.import_mappings (
    id         uuid PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES core.companies(id),
    -- the key of the importable entity (`customers`, `products`)
    entity     text NOT NULL CHECK (btrim(entity) <> ''),
    name       text NOT NULL CHECK (btrim(name) <> ''),
    -- ordered list of {"column": "<file column>", "field": "<entity field>"}
    columns    jsonb NOT NULL CHECK (jsonb_typeof(columns) = 'array'),
    created_by uuid REFERENCES core.users(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (company_id, entity, name)
);

-- One run of an import: inline in the request, or queued for the worker.
CREATE TABLE core.import_jobs (
    id             uuid PRIMARY KEY,
    company_id     uuid NOT NULL REFERENCES core.companies(id),
    entity         text NOT NULL CHECK (btrim(entity) <> ''),
    -- the history survives the clean-up of the file
    file_id        uuid REFERENCES core.import_files(id) ON DELETE SET NULL,
    filename       text NOT NULL,
    format         text NOT NULL CHECK (format IN ('csv', 'xlsx', 'ods')),
    sheet          text,
    -- the {"column", "field"} pairs used; null = no mapping, the header names our columns
    columns        jsonb CHECK (columns IS NULL OR jsonb_typeof(columns) = 'array'),
    dry_run        boolean NOT NULL,
    status         text NOT NULL DEFAULT 'queued'
                   CHECK (status IN ('queued', 'running', 'done', 'failed', 'cancelled')),
    phase          text CHECK (phase IN ('reading', 'validating', 'writing')),
    total_rows     integer NOT NULL DEFAULT 0 CHECK (total_rows >= 0),
    processed_rows integer NOT NULL DEFAULT 0 CHECK (processed_rows >= 0),
    created_count  integer NOT NULL DEFAULT 0 CHECK (created_count >= 0),
    updated_count  integer NOT NULL DEFAULT 0 CHECK (updated_count >= 0),
    unchanged_count integer NOT NULL DEFAULT 0 CHECK (unchanged_count >= 0),
    -- all errors found, of which at most 10 000 are kept in `errors`
    error_count    integer NOT NULL DEFAULT 0 CHECK (error_count >= 0),
    -- [{"row", "column", "message"}]
    errors         jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(errors) = 'array'),
    -- why a job could not be carried out (status 'failed')
    message        text,
    requested_by   uuid REFERENCES core.users(id),
    created_at     timestamptz NOT NULL DEFAULT now(),
    started_at     timestamptz,
    finished_at    timestamptz,
    attempts       integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
    -- written by a running job; a stale heartbeat means the worker died
    heartbeat_at   timestamptz
);
-- The worker claims the oldest queued job.
CREATE INDEX import_jobs_queued_idx ON core.import_jobs (created_at) WHERE status = 'queued';
-- Finding running jobs whose worker died.
CREATE INDEX import_jobs_running_idx ON core.import_jobs (heartbeat_at) WHERE status = 'running';
-- The history of a company, newest first.
CREATE INDEX import_jobs_company_idx ON core.import_jobs (company_id, created_at DESC);
CREATE INDEX import_jobs_file_idx ON core.import_jobs (file_id) WHERE file_id IS NOT NULL;
