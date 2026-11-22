-- Allow negative unit prices on products (e.g. configurator deduction/omission options).
ALTER TABLE pricing.zone_prices
    DROP CONSTRAINT IF EXISTS zone_prices_unit_price_check;
