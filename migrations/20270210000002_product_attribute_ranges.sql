-- Range attributes on products (ADR 0068): kind 'range' with value_min / value_max, used for
-- suitability such as the dial sizes a product fits. The configurator ignores the kind.
ALTER TABLE products.product_attributes
    ADD COLUMN value_min numeric,
    ADD COLUMN value_max numeric;

ALTER TABLE products.product_attributes
    DROP CONSTRAINT product_attributes_kind_check,
    DROP CONSTRAINT product_attributes_typed;

ALTER TABLE products.product_attributes
    ADD CONSTRAINT product_attributes_kind_check
        CHECK (kind IN ('number', 'text', 'boolean', 'range')),
    ADD CONSTRAINT product_attributes_typed CHECK (
        (kind = 'number'  AND value_number IS NOT NULL AND value_text IS NULL AND value_bool IS NULL
                          AND value_min IS NULL AND value_max IS NULL) OR
        (kind = 'text'    AND value_text   IS NOT NULL AND value_number IS NULL AND value_bool IS NULL
                          AND value_min IS NULL AND value_max IS NULL) OR
        (kind = 'boolean' AND value_bool   IS NOT NULL AND value_number IS NULL AND value_text IS NULL
                          AND value_min IS NULL AND value_max IS NULL) OR
        (kind = 'range'   AND value_min    IS NOT NULL AND value_max    IS NOT NULL
                          AND value_min <= value_max
                          AND value_number IS NULL AND value_text IS NULL AND value_bool IS NULL));
