-- Move file, import, outbox attachment and raw e-mail payloads from PostgreSQL bytea to
-- filesystem storage (FILE_STORAGE_DIR). Pre-alpha cutover: any existing DB-stored blobs are
-- dropped without backfill.
--
-- Note: token_hash bytea columns (portal sessions / links) and core.company_logos (<= 512 KiB)
-- stay in PostgreSQL.

-- 1. core.files: drop core.file_blobs and store storage_key on core.files.
DROP TABLE core.file_blobs;
TRUNCATE TABLE core.files CASCADE;
ALTER TABLE core.files
    ADD COLUMN storage_key text NOT NULL;

-- 2. core.import_files: replace data bytea with storage_key.
TRUNCATE TABLE core.import_files CASCADE;
ALTER TABLE core.import_files
    DROP COLUMN data,
    ADD COLUMN storage_key text NOT NULL;

-- 3. core.mail_outbox: replace attachment_data bytea with attachment_storage_key.
ALTER TABLE core.mail_outbox
    DROP CONSTRAINT mail_outbox_attachment_complete,
    DROP COLUMN attachment_data,
    ADD COLUMN attachment_storage_key text;
UPDATE core.mail_outbox
    SET attachment_name = NULL, attachment_type = NULL
    WHERE attachment_name IS NOT NULL;
ALTER TABLE core.mail_outbox
    ADD CONSTRAINT mail_outbox_attachment_complete
        CHECK ((attachment_name IS NULL) = (attachment_storage_key IS NULL)
           AND (attachment_name IS NULL) = (attachment_type IS NULL));

-- 4. helpdesk.articles: replace raw_message bytea with raw_message_storage_key.
ALTER TABLE helpdesk.articles
    DROP COLUMN raw_message,
    ADD COLUMN raw_message_storage_key text;
