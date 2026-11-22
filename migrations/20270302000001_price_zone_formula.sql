ALTER TABLE pricing.price_zones
    ADD COLUMN default_multiplier NUMERIC(10, 4),
    ADD COLUMN default_rounding TEXT;
