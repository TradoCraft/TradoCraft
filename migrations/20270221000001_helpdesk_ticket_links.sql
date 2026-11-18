-- Helpdesk ticket links (A9): tickets that stay separate but belong together.
--
--   bundle     source = parent, target = child. A child has one parent and a bundle is one level
--              deep (a parent is never a child), so "the bundle of an outage" is a star.
--   related    symmetric; stored once with source < target.
--   duplicate  source = the duplicate, target = the original. A duplicate has one original and an
--              original is never itself a duplicate.
-- Any two tickets are linked at most once, whatever the kind (see the unique index on the pair).
CREATE TABLE helpdesk.ticket_links (
    id         uuid PRIMARY KEY,
    company_id uuid NOT NULL REFERENCES core.companies(id) ON DELETE CASCADE,
    kind       text NOT NULL CHECK (kind IN ('bundle', 'related', 'duplicate')),
    source_id  uuid NOT NULL REFERENCES helpdesk.tickets(id) ON DELETE CASCADE,
    target_id  uuid NOT NULL REFERENCES helpdesk.tickets(id) ON DELETE CASCADE,
    created_by uuid REFERENCES core.users(id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CHECK (source_id <> target_id),
    CHECK (kind <> 'related' OR source_id < target_id)
);

CREATE UNIQUE INDEX ticket_links_pair_idx
    ON helpdesk.ticket_links (LEAST(source_id, target_id), GREATEST(source_id, target_id));
CREATE UNIQUE INDEX ticket_links_one_parent_idx
    ON helpdesk.ticket_links (target_id) WHERE kind = 'bundle';
CREATE UNIQUE INDEX ticket_links_one_original_idx
    ON helpdesk.ticket_links (source_id) WHERE kind = 'duplicate';
CREATE INDEX ticket_links_source_idx ON helpdesk.ticket_links (source_id);
CREATE INDEX ticket_links_company_idx ON helpdesk.ticket_links (company_id);
