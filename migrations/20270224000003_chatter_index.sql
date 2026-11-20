-- The thread is read newest first and paged by message id (ids are time ordered), so the index
-- that serves it ends in `id DESC`. The unread query still needs the creation time per record.
DROP INDEX chatter.chatter_messages_record_idx;
CREATE INDEX chatter_messages_thread_idx
    ON chatter.messages (company_id, record_kind, record_id, id DESC);
CREATE INDEX chatter_messages_created_idx
    ON chatter.messages (company_id, record_kind, record_id, created_at);
