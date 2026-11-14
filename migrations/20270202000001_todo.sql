-- To-do items (ADR 0061): private checklists of one user, optionally handed to a colleague of the
-- same company and optionally linked to the record the user was working on. Two levels deep.
--
-- The module is new and stored values only list what is DISABLED (ADR 0028), so it is enabled for
-- every existing company and user by default; no backfill is needed.
CREATE SCHEMA IF NOT EXISTS todo;

CREATE TABLE todo.items (
    id            uuid PRIMARY KEY,
    company_id    uuid NOT NULL REFERENCES core.companies(id),
    -- A sub-item points at its root item; sub-items cannot have sub-items (trigger below).
    parent_id     uuid REFERENCES todo.items(id) ON DELETE CASCADE,
    position      integer NOT NULL DEFAULT 0,
    title         text NOT NULL CHECK (btrim(title) <> ''),
    notes         text NOT NULL DEFAULT '',
    owner_id      uuid NOT NULL REFERENCES core.users(id),
    assignee_id   uuid REFERENCES core.users(id),
    created_by    uuid NOT NULL REFERENCES core.users(id),
    due_date      date,
    done          boolean NOT NULL DEFAULT false,
    done_at       timestamptz,
    done_by       uuid REFERENCES core.users(id),
    -- A polymorphic link to the record the item is about. No foreign key by design: the target
    -- lives in another module's table, may be deleted, and may not be readable by the viewer.
    link_kind     text CHECK (link_kind IN (
                      'customer', 'quotation', 'order', 'ticket', 'repair', 'job',
                      'production_order', 'delivery', 'product', 'opportunity',
                      'purchase_order', 'goods_receipt', 'supplier', 'supplier_invoice',
                      'kb_entry', 'stock_count')),
    link_id       uuid,
    -- What the target was called when it was linked (shown only to viewers who may read it).
    link_label    text,
    -- The app location to jump to (for example /quotations/<id>).
    link_location text,
    -- Set by the reminder worker (later); unused for now.
    reminded_at   timestamptz,
    -- Chosen by the client so that a retried create does not create twice.
    client_id     uuid,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    CHECK ((link_kind IS NULL) = (link_id IS NULL)),
    CHECK (parent_id IS DISTINCT FROM id),
    CHECK (done OR (done_at IS NULL AND done_by IS NULL))
);

CREATE UNIQUE INDEX todo_items_client_idx ON todo.items (company_id, client_id)
    WHERE client_id IS NOT NULL;
CREATE INDEX todo_items_owner_idx ON todo.items (company_id, owner_id, done, due_date);
CREATE INDEX todo_items_assignee_idx ON todo.items (company_id, assignee_id, done, due_date)
    WHERE assignee_id IS NOT NULL;
CREATE INDEX todo_items_link_idx ON todo.items (link_kind, link_id) WHERE link_kind IS NOT NULL;
CREATE INDEX todo_items_parent_idx ON todo.items (parent_id, position);

-- The parent must be a root item of the same company: two levels, no cross-company trees.
CREATE FUNCTION todo.check_parent() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    p todo.items%ROWTYPE;
BEGIN
    IF NEW.parent_id IS NOT NULL THEN
        SELECT * INTO p FROM todo.items WHERE id = NEW.parent_id;
        IF NOT FOUND THEN
            RAISE foreign_key_violation USING MESSAGE = 'the parent item does not exist';
        END IF;
        IF p.company_id <> NEW.company_id THEN
            RAISE check_violation USING MESSAGE = 'the parent item belongs to another company';
        END IF;
        IF p.parent_id IS NOT NULL THEN
            RAISE check_violation USING MESSAGE = 'sub-items cannot have sub-items';
        END IF;
        IF EXISTS (SELECT 1 FROM todo.items WHERE parent_id = NEW.id) THEN
            RAISE check_violation USING MESSAGE = 'an item with sub-items cannot become a sub-item';
        END IF;
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER todo_items_check_parent
    BEFORE INSERT OR UPDATE OF parent_id, company_id ON todo.items
    FOR EACH ROW EXECUTE FUNCTION todo.check_parent();
