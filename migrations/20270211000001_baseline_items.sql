-- Site baseline of an opportunity (ADR 0068): admin-defined item types (clock dial, bell group,
-- bell ...) and the tree of items an opportunity starts from. The `code` of a type is the `scope`
-- of the attribute definitions that describe its items (products.attribute_definitions).

CREATE TABLE crm.baseline_item_types (
    id                    uuid PRIMARY KEY,
    company_id            uuid NOT NULL REFERENCES core.companies(id),
    code                  text NOT NULL CHECK (code ~ '^[a-z][a-z0-9_]*$' AND length(code) <= 64),
    name                  text NOT NULL CHECK (btrim(name) <> ''),
    -- Type codes this type may be nested under. Empty means it has no parent type.
    allowed_parent_codes  text[] NOT NULL DEFAULT '{}',
    -- Whether an item of this type may stand at the top level of the baseline. A type with no
    -- allowed parent must be allowed there, otherwise it could never be placed.
    allow_top_level       boolean NOT NULL DEFAULT true,
    sort_order            integer NOT NULL DEFAULT 0,
    active                boolean NOT NULL DEFAULT true,
    created_at            timestamptz NOT NULL DEFAULT now(),
    updated_at            timestamptz NOT NULL DEFAULT now(),
    UNIQUE (company_id, code),
    CONSTRAINT baseline_item_types_placeable
        CHECK (allow_top_level OR cardinality(allowed_parent_codes) > 0)
);

CREATE TABLE crm.opportunity_baseline_items (
    id              uuid PRIMARY KEY,
    company_id      uuid NOT NULL REFERENCES core.companies(id),
    opportunity_id  uuid NOT NULL REFERENCES crm.opportunities(id) ON DELETE CASCADE,
    parent_id       uuid,
    type_code       text NOT NULL,
    name            text CHECK (name IS NULL OR btrim(name) <> ''),
    quantity        integer NOT NULL DEFAULT 1 CHECK (quantity >= 1),
    -- Attribute values keyed by attribute definition key; validated by the API.
    "values"        jsonb NOT NULL DEFAULT '{}' CHECK (jsonb_typeof("values") = 'object'),
    sort_order      integer NOT NULL DEFAULT 0,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    UNIQUE (opportunity_id, id),
    -- A parent belongs to the same opportunity; a parent with children cannot be deleted.
    FOREIGN KEY (opportunity_id, parent_id)
        REFERENCES crm.opportunity_baseline_items (opportunity_id, id),
    FOREIGN KEY (company_id, type_code) REFERENCES crm.baseline_item_types (company_id, code),
    CHECK (parent_id IS NULL OR parent_id <> id)
);
CREATE INDEX baseline_items_opportunity_idx ON crm.opportunity_baseline_items (opportunity_id, sort_order);
CREATE INDEX baseline_items_type_idx ON crm.opportunity_baseline_items (company_id, type_code);

-- The tower clock and bell setup, as editable data. Idempotent and never overwrites what an
-- administrator changed: rows that exist (same type code or attribute key) are left alone.
-- Called below for every existing company and by company provisioning for new ones.
CREATE FUNCTION crm.seed_baseline_defaults(p_company_id uuid) RETURNS void
LANGUAGE sql AS $$
    INSERT INTO crm.baseline_item_types
        (id, company_id, code, name, allowed_parent_codes, allow_top_level, sort_order)
    VALUES
        (gen_random_uuid(), p_company_id, 'clock_dial', 'Clock dial', '{}', true, 1),
        (gen_random_uuid(), p_company_id, 'bell_group', 'Bell group', '{}', true, 2),
        (gen_random_uuid(), p_company_id, 'bell', 'Bell', '{bell_group}', true, 3)
    ON CONFLICT (company_id, code) DO NOTHING;

    INSERT INTO products.attribute_definitions
        (id, company_id, key, label, kind, unit, options, scope, sort_order)
    VALUES
        (gen_random_uuid(), p_company_id, 'dial_diameter_mm', 'Dial diameter', 'number', 'mm', '[]', 'clock_dial', 1),
        (gen_random_uuid(), p_company_id, 'weight_kg', 'Weight', 'number', 'kg', '[]', 'bell', 1),
        (gen_random_uuid(), p_company_id, 'diameter_mm', 'Diameter', 'number', 'mm', '[]', 'bell', 2),
        (gen_random_uuid(), p_company_id, 'height_mm', 'Height', 'number', 'mm', '[]', 'bell', 3),
        (gen_random_uuid(), p_company_id, 'motion', 'Motion', 'select', NULL,
         '[{"value": "flying", "label": "Flying"},
           {"value": "falling", "label": "Falling"},
           {"value": "balanced", "label": "Balanced"},
           {"value": "volteo", "label": "Volteo"},
           {"value": "ambrosiano", "label": "Ambrosiano"},
           {"value": "veronese", "label": "Veronese"},
           {"value": "synchro_falling", "label": "Synchro falling"},
           {"value": "synchro_flying", "label": "Synchro flying"}]', 'bell', 4),
        (gen_random_uuid(), p_company_id, 'note', 'Note', 'text', NULL, '[]', 'bell', 5),
        (gen_random_uuid(), p_company_id, 'dial_size_mm', 'Dial size', 'range', 'mm', '[]', 'product', 1)
    ON CONFLICT (company_id, key) DO NOTHING;
$$;

SELECT crm.seed_baseline_defaults(id) FROM core.companies;
