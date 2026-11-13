-- no-transaction
-- The per-company unique index, built without blocking writes. It needs its own migration with the
-- directive above (no transaction) and exactly one statement: CREATE INDEX CONCURRENTLY cannot run
-- inside a transaction, and several statements sent together would form one. The old
-- articles_message_id_key stays until a later migration, so duplicates are prevented at every step.
-- If this fails halfway, PostgreSQL leaves an INVALID index of this name: drop it and run again.
CREATE UNIQUE INDEX CONCURRENTLY articles_company_message_id_idx
    ON helpdesk.articles (company_id, message_id);
