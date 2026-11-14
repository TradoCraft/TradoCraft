-- Tower configurator import (ADR 0068). Imported baseline items carry the id of their import
-- source, so a re-import replaces exactly what the previous import created and never touches
-- items entered by hand, and the source as received, so no field of the foreign format is lost
-- even when it has no attribute definition. Idempotent.

ALTER TABLE crm.opportunity_baseline_items
    ADD COLUMN IF NOT EXISTS import_source text,
    ADD COLUMN IF NOT EXISTS source_data jsonb;

ALTER TABLE crm.opportunity_baseline_items
    DROP CONSTRAINT IF EXISTS baseline_items_import_source_check;
ALTER TABLE crm.opportunity_baseline_items
    ADD CONSTRAINT baseline_items_import_source_check
        CHECK (import_source IS NULL OR (btrim(import_source) <> '' AND char_length(import_source) <= 100));

CREATE INDEX IF NOT EXISTS baseline_items_import_source_idx
    ON crm.opportunity_baseline_items (opportunity_id, import_source)
    WHERE import_source IS NOT NULL;
