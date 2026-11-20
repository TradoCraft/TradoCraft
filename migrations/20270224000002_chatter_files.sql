-- Files on chatter notes (ADR 0086). A file is uploaded to the record first (message_id empty) and
-- linked to the note when the note is posted. Deleting a note removes the link; the file row and
-- its blob stay in core.files, like ticket attachments.
CREATE TABLE chatter.message_files (
    file_id     uuid PRIMARY KEY REFERENCES core.files(id),
    company_id  uuid NOT NULL REFERENCES core.companies(id),
    record_kind text NOT NULL CHECK (record_kind IN ('customer', 'quotation', 'order', 'opportunity')),
    record_id   uuid NOT NULL,
    uploaded_by uuid NOT NULL REFERENCES core.users(id),
    message_id  uuid REFERENCES chatter.messages(id) ON DELETE CASCADE,
    created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX chatter_message_files_message_idx ON chatter.message_files (message_id);
CREATE INDEX chatter_message_files_record_idx
    ON chatter.message_files (company_id, record_kind, record_id);

-- Throttle for the mail to the assignee of an activity: at most one mail per user and record per
-- ten minutes, claimed with one UPDATE in the transaction that queues the mail.
ALTER TABLE chatter.followers ADD COLUMN last_notified_at timestamptz;
