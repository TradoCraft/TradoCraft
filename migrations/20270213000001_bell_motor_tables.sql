-- Bell motor lookup tables (ADR 0068, Phase 5b): the rotating-motor tables of the tower
-- configurator reference project as an ordinary configurator model of tables only, so an
-- administrator edits them through draft revisions like any configurator. Also the bell and product
-- attributes the derivation reads. Idempotent like crm.seed_baseline_defaults, which calls it.
--
-- Table semantics (crates/configurator/src/motor.rs): `motors` is a range table over the weight per
-- wheel; a class covers (previous maximum, own maximum], the first class that fits wins. The lowest
-- class has no minimum, the largest maximum is the "too large" limit. Brands: mez_1000, adda_750,
-- de_coster_1000.

CREATE FUNCTION configurator.seed_bell_motors(p_company_id uuid) RETURNS void
LANGUAGE plpgsql AS $fn$
DECLARE
    v_model uuid;
BEGIN
    IF EXISTS (SELECT 1 FROM configurator.models WHERE company_id = p_company_id AND code = 'bell_motors') THEN
        RETURN;
    END IF;
    v_model := gen_random_uuid();
    INSERT INTO configurator.models (id, company_id, code, name, description)
    VALUES (v_model, p_company_id, 'bell_motors', 'Bell motors',
            'Lookup tables that derive the motor of a bell for product matching.');
    INSERT INTO configurator.model_revisions (id, model_id, revision, status, definition, notes, activated_at)
    VALUES (gen_random_uuid(), v_model, 1, 'active', $bell_motors${
 "schema_version": 1,
 "name": "Bell motors",
 "description": "Lookup tables that derive the motor of a bell (ADR 0068, phase 5b). Edit the rows; keep the table and column names.",
 "tables": [
  {
   "name": "motion_rules",
   "label": "Effective motion",
   "kind": "exact",
   "keys": [
    "motion"
   ],
   "on_missing": "null",
   "columns": [
    {
     "name": "motion",
     "type": "text"
    },
    {
     "name": "effective",
     "type": "text"
    }
   ],
   "rows": [
    {
     "motion": "flying",
     "effective": "flying"
    },
    {
     "motion": "falling",
     "effective": "falling"
    },
    {
     "motion": "balanced",
     "effective": "falling"
    },
    {
     "motion": "volteo",
     "effective": "falling"
    },
    {
     "motion": "ambrosiano",
     "effective": "falling"
    },
    {
     "motion": "veronese",
     "effective": "falling"
    },
    {
     "motion": "synchro_falling",
     "effective": "falling"
    },
    {
     "motion": "synchro_flying",
     "effective": "flying"
    }
   ]
  },
  {
   "name": "motion_bumps",
   "label": "Weight classes to bump per motion",
   "kind": "exact",
   "keys": [
    "phases",
    "brand",
    "motion"
   ],
   "on_missing": "null",
   "columns": [
    {
     "name": "phases",
     "type": "integer"
    },
    {
     "name": "brand",
     "type": "text"
    },
    {
     "name": "motion",
     "type": "text"
    },
    {
     "name": "bump",
     "type": "integer"
    }
   ],
   "rows": [
    {
     "phases": 1,
     "brand": "adda_750",
     "motion": "volteo",
     "bump": 1
    },
    {
     "phases": 1,
     "brand": "de_coster_1000",
     "motion": "volteo",
     "bump": 1
    },
    {
     "phases": 1,
     "brand": "mez_1000",
     "motion": "volteo",
     "bump": 1
    },
    {
     "phases": 3,
     "brand": "adda_750",
     "motion": "volteo",
     "bump": 1
    },
    {
     "phases": 3,
     "brand": "mez_1000",
     "motion": "volteo",
     "bump": 1
    },
    {
     "phases": 1,
     "brand": "mez_1000",
     "motion": "balanced",
     "bump": 1
    }
   ]
  },
  {
   "name": "phase_limits",
   "label": "Largest motor per number of phases",
   "kind": "exact",
   "keys": [
    "phases"
   ],
   "on_missing": "null",
   "columns": [
    {
     "name": "phases",
     "type": "integer"
    },
    {
     "name": "max_kw",
     "type": "number"
    }
   ],
   "rows": [
    {
     "phases": 1,
     "max_kw": 0.55
    },
    {
     "phases": 3
    }
   ]
  },
  {
   "name": "motors",
   "label": "Motor per weight per wheel",
   "kind": "range",
   "keys": [
    "phases",
    "brand",
    "motion"
   ],
   "range": {
    "key": "weight_kg",
    "min": "weight_min_kg",
    "max": "weight_max_kg"
   },
   "on_missing": "null",
   "columns": [
    {
     "name": "phases",
     "type": "integer"
    },
    {
     "name": "brand",
     "type": "text"
    },
    {
     "name": "motion",
     "type": "text"
    },
    {
     "name": "weight_min_kg",
     "type": "number"
    },
    {
     "name": "weight_max_kg",
     "type": "number"
    },
    {
     "name": "kw",
     "type": "number"
    },
    {
     "name": "size",
     "type": "text"
    }
   ],
   "rows": [
    {
     "phases": 3,
     "brand": "mez_1000",
     "motion": "falling",
     "weight_max_kg": 450,
     "kw": 0.12,
     "size": "63"
    },
    {
     "phases": 3,
     "brand": "mez_1000",
     "motion": "falling",
     "weight_max_kg": 700,
     "kw": 0.18,
     "size": "71",
     "weight_min_kg": 450
    },
    {
     "phases": 3,
     "brand": "mez_1000",
     "motion": "falling",
     "weight_max_kg": 1100,
     "kw": 0.25,
     "size": "71",
     "weight_min_kg": 700
    },
    {
     "phases": 3,
     "brand": "mez_1000",
     "motion": "falling",
     "weight_max_kg": 1800,
     "kw": 0.37,
     "size": "80",
     "weight_min_kg": 1100
    },
    {
     "phases": 3,
     "brand": "mez_1000",
     "motion": "falling",
     "weight_max_kg": 2500,
     "kw": 0.55,
     "size": "80",
     "weight_min_kg": 1800
    },
    {
     "phases": 3,
     "brand": "mez_1000",
     "motion": "falling",
     "weight_max_kg": 3800,
     "kw": 0.74,
     "size": "90",
     "weight_min_kg": 2500
    },
    {
     "phases": 3,
     "brand": "mez_1000",
     "motion": "falling",
     "weight_max_kg": 5000,
     "kw": 1.1,
     "size": "90",
     "weight_min_kg": 3800
    },
    {
     "phases": 3,
     "brand": "mez_1000",
     "motion": "flying",
     "weight_max_kg": 230,
     "kw": 0.12,
     "size": "63"
    },
    {
     "phases": 3,
     "brand": "mez_1000",
     "motion": "flying",
     "weight_max_kg": 350,
     "kw": 0.18,
     "size": "71",
     "weight_min_kg": 230
    },
    {
     "phases": 3,
     "brand": "mez_1000",
     "motion": "flying",
     "weight_max_kg": 550,
     "kw": 0.25,
     "size": "71",
     "weight_min_kg": 350
    },
    {
     "phases": 3,
     "brand": "mez_1000",
     "motion": "flying",
     "weight_max_kg": 900,
     "kw": 0.37,
     "size": "80",
     "weight_min_kg": 550
    },
    {
     "phases": 3,
     "brand": "mez_1000",
     "motion": "flying",
     "weight_max_kg": 1400,
     "kw": 0.55,
     "size": "80",
     "weight_min_kg": 900
    },
    {
     "phases": 3,
     "brand": "mez_1000",
     "motion": "flying",
     "weight_max_kg": 2200,
     "kw": 0.74,
     "size": "90",
     "weight_min_kg": 1400
    },
    {
     "phases": 3,
     "brand": "mez_1000",
     "motion": "flying",
     "weight_max_kg": 3300,
     "kw": 1.1,
     "size": "90",
     "weight_min_kg": 2200
    },
    {
     "phases": 3,
     "brand": "mez_1000",
     "motion": "flying",
     "weight_max_kg": 4400,
     "kw": 1.47,
     "size": "100",
     "weight_min_kg": 3300
    },
    {
     "phases": 3,
     "brand": "adda_750",
     "motion": "falling",
     "weight_max_kg": 300,
     "kw": 0.12,
     "size": "C63-8"
    },
    {
     "phases": 3,
     "brand": "adda_750",
     "motion": "falling",
     "weight_max_kg": 500,
     "kw": 0.18,
     "size": "C71-8",
     "weight_min_kg": 300
    },
    {
     "phases": 3,
     "brand": "adda_750",
     "motion": "falling",
     "weight_max_kg": 1000,
     "kw": 0.25,
     "size": "C80-8",
     "weight_min_kg": 500
    },
    {
     "phases": 3,
     "brand": "adda_750",
     "motion": "falling",
     "weight_max_kg": 1500,
     "kw": 0.37,
     "size": "C80-8",
     "weight_min_kg": 1000
    },
    {
     "phases": 3,
     "brand": "adda_750",
     "motion": "falling",
     "weight_max_kg": 2200,
     "kw": 0.55,
     "size": "C90S-8",
     "weight_min_kg": 1500
    },
    {
     "phases": 3,
     "brand": "adda_750",
     "motion": "falling",
     "weight_max_kg": 3300,
     "kw": 0.74,
     "size": "C90L-8",
     "weight_min_kg": 2200
    },
    {
     "phases": 3,
     "brand": "adda_750",
     "motion": "falling",
     "weight_max_kg": 4500,
     "kw": 1.1,
     "size": "C100L-8",
     "weight_min_kg": 3300
    },
    {
     "phases": 3,
     "brand": "adda_750",
     "motion": "flying",
     "weight_max_kg": 150,
     "kw": 0.12,
     "size": "C63-8"
    },
    {
     "phases": 3,
     "brand": "adda_750",
     "motion": "flying",
     "weight_max_kg": 250,
     "kw": 0.18,
     "size": "C71-8",
     "weight_min_kg": 150
    },
    {
     "phases": 3,
     "brand": "adda_750",
     "motion": "flying",
     "weight_max_kg": 500,
     "kw": 0.25,
     "size": "C80-8",
     "weight_min_kg": 250
    },
    {
     "phases": 3,
     "brand": "adda_750",
     "motion": "flying",
     "weight_max_kg": 800,
     "kw": 0.37,
     "size": "C80-8",
     "weight_min_kg": 500
    },
    {
     "phases": 3,
     "brand": "adda_750",
     "motion": "flying",
     "weight_max_kg": 1200,
     "kw": 0.55,
     "size": "C90S-8",
     "weight_min_kg": 800
    },
    {
     "phases": 3,
     "brand": "adda_750",
     "motion": "flying",
     "weight_max_kg": 2000,
     "kw": 0.74,
     "size": "C90L-8",
     "weight_min_kg": 1200
    },
    {
     "phases": 3,
     "brand": "adda_750",
     "motion": "flying",
     "weight_max_kg": 3000,
     "kw": 1.1,
     "size": "C100L-8",
     "weight_min_kg": 2000
    },
    {
     "phases": 3,
     "brand": "adda_750",
     "motion": "flying",
     "weight_max_kg": 4400,
     "kw": 1.47,
     "size": "C100L-8",
     "weight_min_kg": 3000
    },
    {
     "phases": 3,
     "brand": "adda_750",
     "motion": "flying",
     "weight_max_kg": 6000,
     "kw": 2.2,
     "size": "C112MT-8",
     "weight_min_kg": 4400
    },
    {
     "phases": 1,
     "brand": "de_coster_1000",
     "motion": "falling",
     "weight_max_kg": 250,
     "kw": 0.12,
     "size": "BC3"
    },
    {
     "phases": 1,
     "brand": "de_coster_1000",
     "motion": "falling",
     "weight_max_kg": 400,
     "kw": 0.18,
     "size": "BC5",
     "weight_min_kg": 250
    },
    {
     "phases": 1,
     "brand": "de_coster_1000",
     "motion": "falling",
     "weight_max_kg": 750,
     "kw": 0.25,
     "size": "BC6",
     "weight_min_kg": 400
    },
    {
     "phases": 1,
     "brand": "de_coster_1000",
     "motion": "falling",
     "weight_max_kg": 1200,
     "kw": 0.37,
     "size": "BC7",
     "weight_min_kg": 750
    },
    {
     "phases": 1,
     "brand": "de_coster_1000",
     "motion": "falling",
     "weight_max_kg": 1800,
     "kw": 0.55,
     "size": "BC7",
     "weight_min_kg": 1200
    },
    {
     "phases": 1,
     "brand": "de_coster_1000",
     "motion": "flying",
     "weight_max_kg": 200,
     "kw": 0.12,
     "size": "BC3"
    },
    {
     "phases": 1,
     "brand": "de_coster_1000",
     "motion": "flying",
     "weight_max_kg": 300,
     "kw": 0.18,
     "size": "BC5",
     "weight_min_kg": 200
    },
    {
     "phases": 1,
     "brand": "de_coster_1000",
     "motion": "flying",
     "weight_max_kg": 500,
     "kw": 0.25,
     "size": "BC6",
     "weight_min_kg": 300
    },
    {
     "phases": 1,
     "brand": "de_coster_1000",
     "motion": "flying",
     "weight_max_kg": 900,
     "kw": 0.37,
     "size": "BC7",
     "weight_min_kg": 500
    },
    {
     "phases": 1,
     "brand": "de_coster_1000",
     "motion": "flying",
     "weight_max_kg": 1200,
     "kw": 0.55,
     "size": "BC7",
     "weight_min_kg": 900
    },
    {
     "phases": 1,
     "brand": "mez_1000",
     "motion": "falling",
     "weight_max_kg": 100,
     "kw": 0.12,
     "size": "63"
    },
    {
     "phases": 1,
     "brand": "mez_1000",
     "motion": "falling",
     "weight_max_kg": 250,
     "kw": 0.18,
     "size": "71",
     "weight_min_kg": 100
    },
    {
     "phases": 1,
     "brand": "mez_1000",
     "motion": "falling",
     "weight_max_kg": 450,
     "kw": 0.25,
     "size": "71",
     "weight_min_kg": 250
    },
    {
     "phases": 1,
     "brand": "mez_1000",
     "motion": "falling",
     "weight_max_kg": 700,
     "kw": 0.37,
     "size": "80",
     "weight_min_kg": 450
    },
    {
     "phases": 1,
     "brand": "mez_1000",
     "motion": "falling",
     "weight_max_kg": 1100,
     "kw": 0.55,
     "size": "80",
     "weight_min_kg": 700
    },
    {
     "phases": 1,
     "brand": "mez_1000",
     "motion": "flying",
     "weight_max_kg": 130,
     "kw": 0.18,
     "size": "71"
    },
    {
     "phases": 1,
     "brand": "mez_1000",
     "motion": "flying",
     "weight_max_kg": 230,
     "kw": 0.25,
     "size": "71",
     "weight_min_kg": 130
    },
    {
     "phases": 1,
     "brand": "mez_1000",
     "motion": "flying",
     "weight_max_kg": 350,
     "kw": 0.37,
     "size": "80",
     "weight_min_kg": 230
    },
    {
     "phases": 1,
     "brand": "mez_1000",
     "motion": "flying",
     "weight_max_kg": 550,
     "kw": 0.55,
     "size": "80",
     "weight_min_kg": 350
    },
    {
     "phases": 1,
     "brand": "adda_750",
     "motion": "falling",
     "weight_max_kg": 66,
     "kw": 0.12,
     "size": "63"
    },
    {
     "phases": 1,
     "brand": "adda_750",
     "motion": "falling",
     "weight_max_kg": 178,
     "kw": 0.18,
     "size": "71",
     "weight_min_kg": 66
    },
    {
     "phases": 1,
     "brand": "adda_750",
     "motion": "falling",
     "weight_max_kg": 410,
     "kw": 0.25,
     "size": "71",
     "weight_min_kg": 178
    },
    {
     "phases": 1,
     "brand": "adda_750",
     "motion": "falling",
     "weight_max_kg": 583,
     "kw": 0.37,
     "size": "80",
     "weight_min_kg": 410
    },
    {
     "phases": 1,
     "brand": "adda_750",
     "motion": "falling",
     "weight_max_kg": 968,
     "kw": 0.55,
     "size": "80",
     "weight_min_kg": 583
    },
    {
     "phases": 1,
     "brand": "adda_750",
     "motion": "flying",
     "weight_max_kg": 84,
     "kw": 0.12,
     "size": "63"
    },
    {
     "phases": 1,
     "brand": "adda_750",
     "motion": "flying",
     "weight_max_kg": 164,
     "kw": 0.18,
     "size": "71",
     "weight_min_kg": 84
    },
    {
     "phases": 1,
     "brand": "adda_750",
     "motion": "flying",
     "weight_max_kg": 318,
     "kw": 0.25,
     "size": "71",
     "weight_min_kg": 164
    },
    {
     "phases": 1,
     "brand": "adda_750",
     "motion": "flying",
     "weight_max_kg": 488,
     "kw": 0.37,
     "size": "80",
     "weight_min_kg": 318
    },
    {
     "phases": 1,
     "brand": "adda_750",
     "motion": "flying",
     "weight_max_kg": 642,
     "kw": 0.55,
     "size": "80",
     "weight_min_kg": 488
    }
   ]
  }
 ]
}$bell_motors$::jsonb, 'seed', now());
END;
$fn$;

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
        (gen_random_uuid(), p_company_id, 'motor_kw', 'Motor power', 'number', 'kW', '[]', 'product', 2)
    ON CONFLICT (company_id, key) DO NOTHING;

    INSERT INTO crm.match_rules
        (id, company_id, name, baseline_type_code, baseline_attribute_key, product_attribute_key,
         operator, sort_order)
    VALUES
        (gen_random_uuid(), p_company_id, 'Dial size fits product', 'clock_dial',
         'dial_diameter_mm', 'dial_size_mm', 'within_range', 1)
    ON CONFLICT (company_id, name) DO NOTHING;

    SELECT configurator.seed_bell_motors(p_company_id);
$$;

SELECT crm.seed_baseline_defaults(id) FROM core.companies;
