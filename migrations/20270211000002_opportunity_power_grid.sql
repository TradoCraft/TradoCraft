-- The power grid of the site (ADR 0068, extends ADR 0025): matching and new quotations default to
-- it. Optional; when set it must belong to the customer's country (checked by the API, like the
-- grid of a quotation).
ALTER TABLE crm.opportunities ADD COLUMN power_grid_id uuid REFERENCES products.power_grids(id);
CREATE INDEX opportunities_power_grid_idx ON crm.opportunities (power_grid_id)
    WHERE power_grid_id IS NOT NULL;
