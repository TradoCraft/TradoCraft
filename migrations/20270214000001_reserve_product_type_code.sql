-- The code of a baseline item type is the scope of its attribute definitions, and `product` is
-- the scope of the product attributes (ADR 0068). NOT VALID: only new and changed rows are
-- checked, the API refuses the code as well.
ALTER TABLE crm.baseline_item_types
    ADD CONSTRAINT baseline_item_types_code_not_product CHECK (code <> 'product') NOT VALID;
