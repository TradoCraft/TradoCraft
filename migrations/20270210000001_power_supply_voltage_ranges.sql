-- Explicit voltage ranges for product power supplies (ADR 0068). Without bounds the effective
-- range stays voltage_v +/- tolerance_pct; with bounds, [voltage_min_v, voltage_max_v] decides.
ALTER TABLE products.product_power_supplies
    ADD COLUMN voltage_min_v integer,
    ADD COLUMN voltage_max_v integer,
    ADD CONSTRAINT product_power_supplies_voltage_range CHECK (
        (voltage_min_v IS NULL AND voltage_max_v IS NULL)
        OR (voltage_min_v IS NOT NULL AND voltage_max_v IS NOT NULL
            AND voltage_min_v > 0
            AND voltage_min_v <= voltage_max_v
            AND voltage_v BETWEEN voltage_min_v AND voltage_max_v));
