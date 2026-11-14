-- Admin-editable rules that match a baseline attribute of an opportunity with a product attribute
-- (ADR 0068, Phase 5a). The attribute keys refer to products.attribute_definitions: the baseline
-- key to the definitions of the baseline item type, the product key to the product scope. They are
-- validated by the API on write, not by foreign keys, like the values they read.

CREATE TABLE crm.match_rules (
    id                      uuid PRIMARY KEY,
    company_id              uuid NOT NULL REFERENCES core.companies(id),
    name                    text NOT NULL CHECK (btrim(name) <> ''),
    -- The baseline item type whose items the rule reads, and the attribute of those items.
    baseline_type_code      text NOT NULL CHECK (baseline_type_code ~ '^[a-z][a-z0-9_]*$'),
    baseline_attribute_key  text NOT NULL CHECK (baseline_attribute_key ~ '^[A-Za-z_][A-Za-z0-9_]*$'),
    -- The product attribute it is compared with: a range for within_range, a number otherwise.
    product_attribute_key   text NOT NULL CHECK (product_attribute_key ~ '^[A-Za-z_][A-Za-z0-9_]*$'),
    operator                text NOT NULL CHECK (operator IN ('within_range', 'at_most', 'at_least')),
    active                  boolean NOT NULL DEFAULT true,
    sort_order              integer NOT NULL DEFAULT 0,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    UNIQUE (company_id, name)
);

-- The tower setup rule. Keeps the earlier seed behaviour: idempotent, never overwrites a rule an
-- administrator renamed or changed (same name is left alone). Same function as the baseline types,
-- so every place that seeds them (this migration, company provisioning, the dev seed) seeds it.
CREATE OR REPLACE FUNCTION crm.seed_baseline_defaults(p_company_id uuid) RETURNS void
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

    INSERT INTO crm.match_rules
        (id, company_id, name, baseline_type_code, baseline_attribute_key, product_attribute_key,
         operator, sort_order)
    VALUES
        (gen_random_uuid(), p_company_id, 'Dial size fits product', 'clock_dial',
         'dial_diameter_mm', 'dial_size_mm', 'within_range', 1)
    ON CONFLICT (company_id, name) DO NOTHING;
$$;

SELECT crm.seed_baseline_defaults(id) FROM core.companies;
