-- Audit trail viewer (ADR 0059, roadmap D6).
--
-- The viewer reads newest first within a company, a page at a time by `id < $cursor`. The primary
-- key already serves that (it walks backwards from the newest event and stops after one page), and
-- the (entity, entity_id) index serves the history of a single record.
--
-- This index serves what they cannot: the list of kinds of record a company has events for, which
-- walks it entity by entity (0.2 ms on half a million events, against 54 ms for a DISTINCT), and a
-- small company's trail in an installation where another company wrote most of the table.
CREATE INDEX audit_events_company_entity_idx ON audit.events (company_id, entity, id DESC);
