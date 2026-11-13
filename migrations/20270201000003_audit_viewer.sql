-- Audit trail viewer (ADR 0059, roadmap D6).
--
-- The viewer reads newest first within a company, a page at a time by `id < $cursor`, and a single
-- record's history through the existing (entity, entity_id) index. Two indexes serve the rest.
--
-- (company_id, id DESC): the newest page of a company. The primary key alone does it when the
-- company wrote most of the table (it walks backwards and stops after one page), but not for a
-- company that has been quiet while another one wrote: then it walks back through every event of
-- the other company first (108 ms for a company with 300,000 old events next to a million newer
-- ones, 0.07 ms with this index, and growing with the other company's volume).
CREATE INDEX audit_events_company_idx ON audit.events (company_id, id DESC);

-- (company_id, entity, id DESC): the list of kinds of record a company has events for, which walks
-- this index entity by entity (0.2 ms on half a million events, against 54 ms for a DISTINCT), and
-- the trail filtered by kind of record.
CREATE INDEX audit_events_company_entity_idx ON audit.events (company_id, entity, id DESC);
