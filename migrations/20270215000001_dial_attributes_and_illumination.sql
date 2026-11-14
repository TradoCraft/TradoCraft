-- Optional clock dial attributes, boolean attributes and the "requires if true" match rule
-- (ADR 0068, step 2). The application stays general: nothing here is read by name in code, these
-- are seed rows an administrator may edit or delete.
--
-- * attribute definitions may now be `boolean` (baseline values and product attributes);
-- * match rules may use the operator `requires_if_true`: when the baseline boolean is true the
--   product's boolean must be true; false or unset on the baseline means the rule does not apply;
-- * crm.seed_baseline_defaults (same function as before, used for new companies and the dev seed)
--   now also seeds the dial attributes mounting, wall_thickness_mm,
--   faces, movement, illumination_wanted, the product attribute can_illuminate and the rule
--   "Illumination supported". Idempotent: ON CONFLICT DO NOTHING keeps what an admin changed.
--   Existing companies get only these new rows (targeted backfill at the end), so defaults an
--   administrator deleted earlier are not resurrected.

ALTER TABLE products.attribute_definitions
    DROP CONSTRAINT attribute_definitions_kind_check,
    ADD CONSTRAINT attribute_definitions_kind_check
        CHECK (kind IN ('number', 'range', 'select', 'text', 'boolean'));

ALTER TABLE crm.match_rules
    DROP CONSTRAINT match_rules_operator_check,
    ADD CONSTRAINT match_rules_operator_check
        CHECK (operator IN ('within_range', 'at_most', 'at_least', 'requires_if_true'));

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
        (gen_random_uuid(), p_company_id, 'num_wheels', 'Number of wheels', 'number', NULL, '[]', 'bell', 6),
        (gen_random_uuid(), p_company_id, 'motor_brand', 'Motor brand', 'select', NULL,
         '[{"value": "mez_1000", "label": "MEZ 1000"},
           {"value": "adda_750", "label": "ADDA 750"},
           {"value": "de_coster_1000", "label": "DE COSTER 1000"}]', 'bell', 7),
        (gen_random_uuid(), p_company_id, 'dial_size_mm', 'Dial size', 'range', 'mm', '[]', 'product', 1),
        (gen_random_uuid(), p_company_id, 'motor_kw', 'Motor power', 'number', 'kW', '[]', 'product', 2),
        (gen_random_uuid(), p_company_id, 'mounting', 'Mounting', 'select', NULL,
         '[{"value": "wall", "label": "Wall"},
           {"value": "on_dial", "label": "On the dial"}]', 'clock_dial', 2),
        (gen_random_uuid(), p_company_id, 'wall_thickness_mm', 'Wall thickness', 'number', 'mm', '[]', 'clock_dial', 3),
        (gen_random_uuid(), p_company_id, 'faces', 'Number of faces', 'select', NULL,
         '[{"value": "1", "label": "1"},
           {"value": "2", "label": "2"},
           {"value": "3", "label": "3"},
           {"value": "4", "label": "4"}]', 'clock_dial', 4),
        (gen_random_uuid(), p_company_id, 'movement', 'Movement', 'select', NULL,
         '[{"value": "central", "label": "Central movement"},
           {"value": "per_dial_motor", "label": "Motor per dial"}]', 'clock_dial', 5),
        (gen_random_uuid(), p_company_id, 'illumination_wanted', 'Illumination wanted', 'boolean', NULL, '[]', 'clock_dial', 6),
        (gen_random_uuid(), p_company_id, 'can_illuminate', 'Can be illuminated', 'boolean', NULL, '[]', 'product', 3)
    ON CONFLICT (company_id, key) DO NOTHING;

    INSERT INTO crm.match_rules
        (id, company_id, name, baseline_type_code, baseline_attribute_key, product_attribute_key,
         operator, sort_order)
    VALUES
        (gen_random_uuid(), p_company_id, 'Dial size fits product', 'clock_dial',
         'dial_diameter_mm', 'dial_size_mm', 'within_range', 1),
        (gen_random_uuid(), p_company_id, 'Illumination supported', 'clock_dial',
         'illumination_wanted', 'can_illuminate', 'requires_if_true', 2)
    ON CONFLICT (company_id, name) DO NOTHING;

    SELECT configurator.seed_bell_motors(p_company_id);
$$;

-- Backfill existing companies with ONLY what this migration introduces. The complete seeder is
-- deliberately not called here: it would re-create earlier defaults an administrator deleted since.
INSERT INTO products.attribute_definitions
    (id, company_id, key, label, kind, unit, options, scope, sort_order)
SELECT gen_random_uuid(), c.id, v.key, v.label, v.kind, v.unit, v.options::jsonb, v.scope, v.sort_order
FROM core.companies c
CROSS JOIN (VALUES
    ('mounting', 'Mounting', 'select', NULL,
     '[{"value": "wall", "label": "Wall"},
       {"value": "on_dial", "label": "On the dial"}]', 'clock_dial', 2),
    ('wall_thickness_mm', 'Wall thickness', 'number', 'mm', '[]', 'clock_dial', 3),
    ('faces', 'Number of faces', 'select', NULL,
     '[{"value": "1", "label": "1"},
       {"value": "2", "label": "2"},
       {"value": "3", "label": "3"},
       {"value": "4", "label": "4"}]', 'clock_dial', 4),
    ('movement', 'Movement', 'select', NULL,
     '[{"value": "central", "label": "Central movement"},
       {"value": "per_dial_motor", "label": "Motor per dial"}]', 'clock_dial', 5),
    ('illumination_wanted', 'Illumination wanted', 'boolean', NULL, '[]', 'clock_dial', 6),
    ('can_illuminate', 'Can be illuminated', 'boolean', NULL, '[]', 'product', 3)
) AS v(key, label, kind, unit, options, scope, sort_order)
ON CONFLICT (company_id, key) DO NOTHING;

INSERT INTO crm.match_rules
    (id, company_id, name, baseline_type_code, baseline_attribute_key, product_attribute_key,
     operator, sort_order)
SELECT gen_random_uuid(), c.id, 'Illumination supported', 'clock_dial',
       'illumination_wanted', 'can_illuminate', 'requires_if_true', 2
FROM core.companies c
ON CONFLICT (company_id, name) DO NOTHING;
