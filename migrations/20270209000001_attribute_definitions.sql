-- Admin-defined attribute definitions (ADR 0068): what can be recorded about a product or about a
-- site baseline item (key, label, kind, unit, select options). Nothing domain-specific is
-- hard-coded; scope is 'product' or the code of a baseline item type.

CREATE TABLE products.attribute_definitions (
    id          uuid PRIMARY KEY,
    company_id  uuid NOT NULL REFERENCES core.companies(id),
    key         text NOT NULL CHECK (key ~ '^[a-z][a-z0-9_]*$' AND length(key) <= 64),
    label       text NOT NULL CHECK (btrim(label) <> ''),
    kind        text NOT NULL CHECK (kind IN ('number', 'range', 'select', 'text')),
    unit        text CHECK (unit IS NULL OR btrim(unit) <> ''),
    -- [{"value": "flying", "label": "Flying"}], only for kind 'select'.
    options     jsonb NOT NULL DEFAULT '[]' CHECK (jsonb_typeof(options) = 'array'),
    scope       text NOT NULL DEFAULT 'product' CHECK (btrim(scope) <> ''),
    sort_order  integer NOT NULL DEFAULT 0,
    active      boolean NOT NULL DEFAULT true,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now(),
    UNIQUE (company_id, key),
    CONSTRAINT attribute_definitions_options_only_select CHECK (
        (kind = 'select' AND jsonb_array_length(options) > 0) OR
        (kind <> 'select' AND jsonb_array_length(options) = 0)),
    CONSTRAINT attribute_definitions_unit_numeric CHECK (
        unit IS NULL OR kind IN ('number', 'range'))
);

CREATE INDEX attribute_definitions_scope ON products.attribute_definitions (company_id, scope, sort_order);
