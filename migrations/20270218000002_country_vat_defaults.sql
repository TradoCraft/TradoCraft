-- Country-aware, temporally valid, and building-age-aware VAT defaults.

CREATE TABLE core.country_vat_rates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    country_code TEXT NOT NULL CHECK (country_code ~ '^[A-Z]{2}$'),
    category TEXT NOT NULL CHECK (category IN ('standard', 'intermediate', 'reduced', 'zero', 'construction')),
    rate NUMERIC(5, 2) NOT NULL CHECK (rate >= 0 AND rate < 100),
    min_building_age_years INT NULL CHECK (min_building_age_years IS NULL OR (min_building_age_years > 0 AND min_building_age_years <= 200)),
    start_date DATE NOT NULL DEFAULT DATE '2000-01-01',
    end_date DATE NULL,
    notes TEXT NOT NULL DEFAULT '',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT country_vat_rates_date_order CHECK (end_date IS NULL OR end_date >= start_date),
    CONSTRAINT country_vat_rates_construction_age CHECK (
        (category = 'construction' AND min_building_age_years IS NOT NULL)
        OR (category <> 'construction' AND min_building_age_years IS NULL)
    )
);

CREATE INDEX idx_country_vat_rates_lookup
    ON core.country_vat_rates (country_code, category, start_date DESC);

-- Seed EU-27 + XI + key non-EU countries, including historical rate periods and renovation rules.
INSERT INTO core.country_vat_rates (country_code, category, rate, min_building_age_years, start_date, end_date, notes) VALUES
    -- Austria (AT)
    ('AT', 'standard',     20.00, NULL, DATE '2000-01-01', NULL, 'Standard VAT rate'),
    ('AT', 'intermediate', 13.00, NULL, DATE '2000-01-01', NULL, 'Intermediate rate'),
    ('AT', 'reduced',      10.00, NULL, DATE '2000-01-01', NULL, 'Reduced rate'),
    ('AT', 'zero',          0.00, NULL, DATE '2000-01-01', NULL, 'Zero rate'),
    -- Belgium (BE)
    ('BE', 'standard',     21.00, NULL, DATE '2000-01-01', NULL, 'Standard VAT rate'),
    ('BE', 'intermediate', 12.00, NULL, DATE '2000-01-01', NULL, 'Intermediate rate'),
    ('BE', 'reduced',       6.00, NULL, DATE '2000-01-01', NULL, 'Reduced rate'),
    ('BE', 'zero',          0.00, NULL, DATE '2000-01-01', NULL, 'Zero rate'),
    ('BE', 'construction',  6.00,    5, DATE '2000-01-01', DATE '2016-02-11', 'Renovation of private dwellings >= 5 years old'),
    ('BE', 'construction',  6.00,   10, DATE '2016-02-12', NULL, 'Renovation of private dwellings >= 10 years old'),
    -- Bulgaria (BG)
    ('BG', 'standard',     20.00, NULL, DATE '2000-01-01', NULL, 'Standard VAT rate'),
    ('BG', 'reduced',       9.00, NULL, DATE '2000-01-01', NULL, 'Reduced rate'),
    ('BG', 'zero',          0.00, NULL, DATE '2000-01-01', NULL, 'Zero rate'),
    -- Cyprus (CY)
    ('CY', 'standard',     19.00, NULL, DATE '2000-01-01', NULL, 'Standard VAT rate'),
    ('CY', 'intermediate',  9.00, NULL, DATE '2000-01-01', NULL, 'Intermediate rate'),
    ('CY', 'reduced',       5.00, NULL, DATE '2000-01-01', NULL, 'Reduced rate'),
    ('CY', 'zero',          0.00, NULL, DATE '2000-01-01', NULL, 'Zero rate'),
    -- Czechia (CZ)
    ('CZ', 'standard',     21.00, NULL, DATE '2000-01-01', NULL, 'Standard VAT rate'),
    ('CZ', 'reduced',      12.00, NULL, DATE '2000-01-01', NULL, 'Reduced rate'),
    ('CZ', 'zero',          0.00, NULL, DATE '2000-01-01', NULL, 'Zero rate'),
    -- Germany (DE) including COVID-19 temporary reduction
    ('DE', 'standard',     16.00, NULL, DATE '2000-01-01', DATE '2006-12-31', 'Historical standard rate'),
    ('DE', 'standard',     19.00, NULL, DATE '2007-01-01', DATE '2020-06-30', 'Standard VAT rate'),
    ('DE', 'standard',     16.00, NULL, DATE '2020-07-01', DATE '2020-12-31', 'Temporary COVID-19 reduction'),
    ('DE', 'standard',     19.00, NULL, DATE '2021-01-01', NULL, 'Standard VAT rate'),
    ('DE', 'reduced',       7.00, NULL, DATE '2000-01-01', DATE '2020-06-30', 'Reduced rate'),
    ('DE', 'reduced',       5.00, NULL, DATE '2020-07-01', DATE '2020-12-31', 'Temporary COVID-19 reduction'),
    ('DE', 'reduced',       7.00, NULL, DATE '2021-01-01', NULL, 'Reduced rate'),
    ('DE', 'zero',          0.00, NULL, DATE '2000-01-01', NULL, 'Zero rate'),
    -- Denmark (DK)
    ('DK', 'standard',     25.00, NULL, DATE '2000-01-01', NULL, 'Standard VAT rate'),
    ('DK', 'zero',          0.00, NULL, DATE '2000-01-01', NULL, 'Zero rate'),
    -- Estonia (EE)
    ('EE', 'standard',     18.00, NULL, DATE '2000-01-01', DATE '2009-06-30', 'Historical standard rate'),
    ('EE', 'standard',     20.00, NULL, DATE '2009-07-01', DATE '2023-12-31', 'Historical standard rate'),
    ('EE', 'standard',     22.00, NULL, DATE '2024-01-01', DATE '2025-06-30', 'Historical standard rate'),
    ('EE', 'standard',     24.00, NULL, DATE '2025-07-01', NULL, 'Standard VAT rate'),
    ('EE', 'reduced',       9.00, NULL, DATE '2000-01-01', NULL, 'Reduced rate'),
    ('EE', 'zero',          0.00, NULL, DATE '2000-01-01', NULL, 'Zero rate'),
    -- Spain (ES)
    ('ES', 'standard',     21.00, NULL, DATE '2000-01-01', NULL, 'Standard VAT rate'),
    ('ES', 'intermediate', 10.00, NULL, DATE '2000-01-01', NULL, 'Intermediate rate'),
    ('ES', 'reduced',       4.00, NULL, DATE '2000-01-01', NULL, 'Super-reduced rate'),
    ('ES', 'zero',          0.00, NULL, DATE '2000-01-01', NULL, 'Zero rate'),
    ('ES', 'construction', 10.00,    2, DATE '2012-09-01', NULL, 'Housing renovation >= 2 years old'),
    -- Finland (FI)
    ('FI', 'standard',     22.00, NULL, DATE '2000-01-01', DATE '2010-06-30', 'Historical standard rate'),
    ('FI', 'standard',     23.00, NULL, DATE '2010-07-01', DATE '2012-12-31', 'Historical standard rate'),
    ('FI', 'standard',     24.00, NULL, DATE '2013-01-01', DATE '2024-08-31', 'Historical standard rate'),
    ('FI', 'standard',     25.50, NULL, DATE '2024-09-01', NULL, 'Standard VAT rate'),
    ('FI', 'intermediate', 14.00, NULL, DATE '2000-01-01', NULL, 'Intermediate rate'),
    ('FI', 'reduced',      10.00, NULL, DATE '2000-01-01', NULL, 'Reduced rate'),
    ('FI', 'zero',          0.00, NULL, DATE '2000-01-01', NULL, 'Zero rate'),
    -- France (FR)
    ('FR', 'standard',     20.60, NULL, DATE '2000-01-01', DATE '2000-03-31', 'Historical standard rate'),
    ('FR', 'standard',     19.60, NULL, DATE '2000-04-01', DATE '2013-12-31', 'Historical standard rate'),
    ('FR', 'standard',     20.00, NULL, DATE '2014-01-01', NULL, 'Standard VAT rate'),
    ('FR', 'intermediate', 10.00, NULL, DATE '2014-01-01', NULL, 'Intermediate rate'),
    ('FR', 'reduced',       5.50, NULL, DATE '2000-01-01', NULL, 'Reduced rate'),
    ('FR', 'zero',          0.00, NULL, DATE '2000-01-01', NULL, 'Zero rate'),
    ('FR', 'construction', 10.00,    2, DATE '2014-01-01', NULL, 'Residential renovation >= 2 years old'),
    -- Greece (GR)
    ('GR', 'standard',     24.00, NULL, DATE '2000-01-01', NULL, 'Standard VAT rate'),
    ('GR', 'intermediate', 13.00, NULL, DATE '2000-01-01', NULL, 'Intermediate rate'),
    ('GR', 'reduced',       6.00, NULL, DATE '2000-01-01', NULL, 'Reduced rate'),
    ('GR', 'zero',          0.00, NULL, DATE '2000-01-01', NULL, 'Zero rate'),
    -- Croatia (HR)
    ('HR', 'standard',     25.00, NULL, DATE '2000-01-01', NULL, 'Standard VAT rate'),
    ('HR', 'intermediate', 13.00, NULL, DATE '2000-01-01', NULL, 'Intermediate rate'),
    ('HR', 'reduced',       5.00, NULL, DATE '2000-01-01', NULL, 'Reduced rate'),
    ('HR', 'zero',          0.00, NULL, DATE '2000-01-01', NULL, 'Zero rate'),
    -- Hungary (HU)
    ('HU', 'standard',     27.00, NULL, DATE '2000-01-01', NULL, 'Standard VAT rate'),
    ('HU', 'intermediate', 18.00, NULL, DATE '2000-01-01', NULL, 'Intermediate rate'),
    ('HU', 'reduced',       5.00, NULL, DATE '2000-01-01', NULL, 'Reduced rate'),
    ('HU', 'zero',          0.00, NULL, DATE '2000-01-01', NULL, 'Zero rate'),
    -- Ireland (IE)
    ('IE', 'standard',     23.00, NULL, DATE '2000-01-01', NULL, 'Standard VAT rate'),
    ('IE', 'intermediate', 13.50, NULL, DATE '2000-01-01', NULL, 'Intermediate rate'),
    ('IE', 'reduced',       9.00, NULL, DATE '2000-01-01', NULL, 'Reduced rate'),
    ('IE', 'zero',          0.00, NULL, DATE '2000-01-01', NULL, 'Zero rate'),
    -- Italy (IT)
    ('IT', 'standard',     22.00, NULL, DATE '2000-01-01', NULL, 'Standard VAT rate'),
    ('IT', 'intermediate', 10.00, NULL, DATE '2000-01-01', NULL, 'Intermediate rate'),
    ('IT', 'reduced',       5.00, NULL, DATE '2000-01-01', NULL, 'Reduced rate'),
    ('IT', 'zero',          0.00, NULL, DATE '2000-01-01', NULL, 'Zero rate'),
    ('IT', 'construction', 10.00,    1, DATE '2000-01-01', NULL, 'Residential building maintenance/renovation'),
    -- Lithuania (LT)
    ('LT', 'standard',     21.00, NULL, DATE '2000-01-01', NULL, 'Standard VAT rate'),
    ('LT', 'intermediate',  9.00, NULL, DATE '2000-01-01', NULL, 'Intermediate rate'),
    ('LT', 'reduced',       5.00, NULL, DATE '2000-01-01', NULL, 'Reduced rate'),
    ('LT', 'zero',          0.00, NULL, DATE '2000-01-01', NULL, 'Zero rate'),
    -- Luxembourg (LU)
    ('LU', 'standard',     15.00, NULL, DATE '2000-01-01', DATE '2014-12-31', 'Historical standard rate'),
    ('LU', 'standard',     17.00, NULL, DATE '2015-01-01', DATE '2022-12-31', 'Standard VAT rate'),
    ('LU', 'standard',     16.00, NULL, DATE '2023-01-01', DATE '2023-12-31', 'Temporary 2023 reduction'),
    ('LU', 'standard',     17.00, NULL, DATE '2024-01-01', NULL, 'Standard VAT rate'),
    ('LU', 'intermediate', 14.00, NULL, DATE '2015-01-01', NULL, 'Intermediate rate'),
    ('LU', 'reduced',       8.00, NULL, DATE '2015-01-01', NULL, 'Reduced rate'),
    ('LU', 'zero',          0.00, NULL, DATE '2000-01-01', NULL, 'Zero rate'),
    ('LU', 'construction',  3.00,   10, DATE '2015-01-01', NULL, 'Housing renovation super-reduced rate >= 10 years old'),
    -- Latvia (LV)
    ('LV', 'standard',     21.00, NULL, DATE '2000-01-01', NULL, 'Standard VAT rate'),
    ('LV', 'intermediate', 12.00, NULL, DATE '2000-01-01', NULL, 'Intermediate rate'),
    ('LV', 'reduced',       5.00, NULL, DATE '2000-01-01', NULL, 'Reduced rate'),
    ('LV', 'zero',          0.00, NULL, DATE '2000-01-01', NULL, 'Zero rate'),
    -- Malta (MT)
    ('MT', 'standard',     18.00, NULL, DATE '2000-01-01', NULL, 'Standard VAT rate'),
    ('MT', 'intermediate',  7.00, NULL, DATE '2000-01-01', NULL, 'Intermediate rate'),
    ('MT', 'reduced',       5.00, NULL, DATE '2000-01-01', NULL, 'Reduced rate'),
    ('MT', 'zero',          0.00, NULL, DATE '2000-01-01', NULL, 'Zero rate'),
    -- Netherlands (NL)
    ('NL', 'standard',     19.00, NULL, DATE '2000-01-01', DATE '2012-09-30', 'Historical standard rate'),
    ('NL', 'standard',     21.00, NULL, DATE '2012-10-01', NULL, 'Standard VAT rate'),
    ('NL', 'reduced',       6.00, NULL, DATE '2000-01-01', DATE '2018-12-31', 'Historical reduced rate'),
    ('NL', 'reduced',       9.00, NULL, DATE '2019-01-01', NULL, 'Reduced rate'),
    ('NL', 'zero',          0.00, NULL, DATE '2000-01-01', NULL, 'Zero rate'),
    ('NL', 'construction',  9.00,    2, DATE '2019-01-01', NULL, 'Insulation/painting/plastering on dwellings >= 2 years old'),
    -- Poland (PL)
    ('PL', 'standard',     23.00, NULL, DATE '2000-01-01', NULL, 'Standard VAT rate'),
    ('PL', 'intermediate',  8.00, NULL, DATE '2000-01-01', NULL, 'Intermediate rate'),
    ('PL', 'reduced',       5.00, NULL, DATE '2000-01-01', NULL, 'Reduced rate'),
    ('PL', 'zero',          0.00, NULL, DATE '2000-01-01', NULL, 'Zero rate'),
    -- Portugal (PT)
    ('PT', 'standard',     23.00, NULL, DATE '2000-01-01', NULL, 'Standard VAT rate'),
    ('PT', 'intermediate', 13.00, NULL, DATE '2000-01-01', NULL, 'Intermediate rate'),
    ('PT', 'reduced',       6.00, NULL, DATE '2000-01-01', NULL, 'Reduced rate'),
    ('PT', 'zero',          0.00, NULL, DATE '2000-01-01', NULL, 'Zero rate'),
    -- Romania (RO)
    ('RO', 'standard',     19.00, NULL, DATE '2000-01-01', DATE '2025-07-31', 'Standard VAT rate'),
    ('RO', 'standard', 21.00, NULL, DATE '2025-08-01', NULL, 'VAT rate from August 2025'),
    ('RO', 'intermediate',  9.00, NULL, DATE '2000-01-01', DATE '2025-07-31', 'Intermediate rate'),
    ('RO', 'intermediate', 11.00, NULL, DATE '2025-08-01', NULL, 'VAT rate from August 2025'),
    ('RO', 'reduced',       5.00, NULL, DATE '2000-01-01', DATE '2025-07-31', 'Reduced rate'),
    ('RO', 'reduced', 11.00, NULL, DATE '2025-08-01', NULL, 'VAT rate from August 2025'),
    ('RO', 'zero',          0.00, NULL, DATE '2000-01-01', NULL, 'Zero rate'),
    -- Sweden (SE)
    ('SE', 'standard',     25.00, NULL, DATE '2000-01-01', NULL, 'Standard VAT rate'),
    ('SE', 'intermediate', 12.00, NULL, DATE '2000-01-01', NULL, 'Intermediate rate'),
    ('SE', 'reduced',       6.00, NULL, DATE '2000-01-01', NULL, 'Reduced rate'),
    ('SE', 'zero',          0.00, NULL, DATE '2000-01-01', NULL, 'Zero rate'),
    -- Slovenia (SI)
    ('SI', 'standard',     22.00, NULL, DATE '2000-01-01', NULL, 'Standard VAT rate'),
    ('SI', 'intermediate',  9.50, NULL, DATE '2000-01-01', NULL, 'Intermediate rate'),
    ('SI', 'reduced',       5.00, NULL, DATE '2000-01-01', NULL, 'Reduced rate'),
    ('SI', 'zero',          0.00, NULL, DATE '2000-01-01', NULL, 'Zero rate'),
    -- Slovakia (SK)
    ('SK', 'standard',     20.00, NULL, DATE '2000-01-01', DATE '2003-12-31', 'Historical standard rate'),
    ('SK', 'standard',     19.00, NULL, DATE '2004-01-01', DATE '2010-12-31', 'Historical standard rate'),
    ('SK', 'standard',     20.00, NULL, DATE '2011-01-01', DATE '2024-12-31', 'Historical standard rate'),
    ('SK', 'standard',     23.00, NULL, DATE '2025-01-01', NULL, 'Standard VAT rate'),
    ('SK', 'intermediate', 19.00, NULL, DATE '2025-01-01', NULL, 'Intermediate rate'),
    ('SK', 'reduced',      10.00, NULL, DATE '2000-01-01', DATE '2024-12-31', 'Historical reduced rate'),
    ('SK', 'reduced',       5.00, NULL, DATE '2025-01-01', NULL, 'Reduced rate'),
    ('SK', 'zero',          0.00, NULL, DATE '2000-01-01', NULL, 'Zero rate'),
    -- Northern Ireland (XI)
    ('XI', 'standard',     20.00, NULL, DATE '2000-01-01', NULL, 'Standard VAT rate'),
    ('XI', 'reduced',       5.00, NULL, DATE '2000-01-01', NULL, 'Reduced rate'),
    ('XI', 'zero',          0.00, NULL, DATE '2000-01-01', NULL, 'Zero rate'),
    -- United Kingdom (GB)
    ('GB', 'standard',     20.00, NULL, DATE '2000-01-01', NULL, 'Standard VAT rate'),
    ('GB', 'reduced',       5.00, NULL, DATE '2000-01-01', NULL, 'Reduced rate'),
    ('GB', 'zero',          0.00, NULL, DATE '2000-01-01', NULL, 'Zero rate'),
    -- Switzerland (CH)
    ('CH', 'standard',      7.60, NULL, DATE '2000-01-01', DATE '2010-12-31', 'Historical standard rate'),
    ('CH', 'standard',      8.00, NULL, DATE '2011-01-01', DATE '2017-12-31', 'Historical standard rate'),
    ('CH', 'standard',      7.70, NULL, DATE '2018-01-01', DATE '2023-12-31', 'Historical standard rate'),
    ('CH', 'standard',      8.10, NULL, DATE '2024-01-01', NULL, 'Standard VAT rate'),
    ('CH', 'intermediate',  3.80, NULL, DATE '2024-01-01', NULL, 'Accommodation rate'),
    ('CH', 'reduced',       2.60, NULL, DATE '2024-01-01', NULL, 'Reduced rate'),
    ('CH', 'zero',          0.00, NULL, DATE '2000-01-01', NULL, 'Zero rate'),
    -- Norway (NO)
    ('NO', 'standard',     25.00, NULL, DATE '2000-01-01', NULL, 'Standard MVA rate'),
    ('NO', 'intermediate', 15.00, NULL, DATE '2000-01-01', NULL, 'Foodstuffs rate'),
    ('NO', 'reduced',      12.00, NULL, DATE '2000-01-01', NULL, 'Reduced rate'),
    ('NO', 'zero',          0.00, NULL, DATE '2000-01-01', NULL, 'Zero rate'),
    -- Iceland (IS)
    ('IS', 'standard',     24.00, NULL, DATE '2000-01-01', NULL, 'Standard VAT rate'),
    ('IS', 'reduced',      11.00, NULL, DATE '2000-01-01', NULL, 'Reduced rate'),
    ('IS', 'zero',          0.00, NULL, DATE '2000-01-01', NULL, 'Zero rate'),
    -- United States (US), Canada (CA), Australia (AU)
    ('US', 'standard',      0.00, NULL, DATE '2000-01-01', NULL, 'No federal VAT (sales tax handled externally)'),
    ('US', 'zero',          0.00, NULL, DATE '2000-01-01', NULL, 'Zero rate'),
    ('CA', 'standard',      5.00, NULL, DATE '2000-01-01', NULL, 'Federal GST rate'),
    ('CA', 'zero',          0.00, NULL, DATE '2000-01-01', NULL, 'Zero rate'),
    ('AU', 'standard',     10.00, NULL, DATE '2000-01-01', NULL, 'GST rate'),
    ('AU', 'zero',          0.00, NULL, DATE '2000-01-01', NULL, 'Zero rate');

-- Products: VAT category + optional explicit rate override.
ALTER TABLE products.products
    ADD COLUMN vat_category TEXT NOT NULL DEFAULT 'standard'
        CHECK (vat_category IN ('standard', 'intermediate', 'reduced', 'zero')),
    ADD COLUMN vat_rate_override NUMERIC(5, 2) NULL
        CHECK (vat_rate_override IS NULL OR (vat_rate_override >= 0 AND vat_rate_override < 100));

-- Preserve legacy product rates; abort rather than silently discard an invalid rate.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM products.products WHERE NOT (vat_rate >= 0 AND vat_rate < 100)) THEN
        RAISE EXCEPTION 'Existing product VAT rates must be in [0, 100) before migration';
    END IF;
END;
$$;
UPDATE products.products SET vat_rate_override = vat_rate;

-- Keep direct SQL `UPDATE products.products SET vat_rate = ...` compatible with vat_rate_override.
CREATE OR REPLACE FUNCTION products.sync_direct_vat_rate_update()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.vat_rate IS DISTINCT FROM OLD.vat_rate
       AND NEW.vat_rate_override IS NOT DISTINCT FROM OLD.vat_rate_override
       AND NEW.vat_category IS NOT DISTINCT FROM OLD.vat_category
       AND current_setting('tradocraft.updating_product', true) IS DISTINCT FROM '1' THEN
        NEW.vat_rate_override := NEW.vat_rate;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_products_sync_direct_vat_rate
    BEFORE UPDATE OF vat_rate ON products.products
    FOR EACH ROW EXECUTE FUNCTION products.sync_direct_vat_rate_update();

-- CRM: widen VAT regimes to include domestic_reverse_charge, store per-company override on customer_terms,
-- and track building construction year on opportunities.
ALTER TABLE crm.customers DROP CONSTRAINT IF EXISTS customers_vat_regime_check;
ALTER TABLE crm.customers
    ADD CONSTRAINT customers_vat_regime_check
        CHECK (vat_regime IN ('domestic', 'domestic_reverse_charge', 'intra_eu', 'outside_eu'));

ALTER TABLE crm.customer_terms
    ADD COLUMN vat_regime TEXT NULL
        CHECK (vat_regime IS NULL OR vat_regime IN ('domestic', 'domestic_reverse_charge', 'intra_eu', 'outside_eu'));

-- Legacy selections have no provenance: preserve all stored regimes, including domestic.
UPDATE crm.customer_terms t
SET vat_regime = c.vat_regime
FROM crm.customers c
WHERE c.id = t.customer_id AND t.vat_regime IS NULL;

ALTER TABLE crm.opportunities
    ADD COLUMN building_construction_year INT NULL
        CHECK (building_construction_year IS NULL OR (building_construction_year >= 800 AND building_construction_year <= 2200));

-- Sales: quotations & orders store effective vat_regime and building_construction_year.
ALTER TABLE sales.quotations DROP CONSTRAINT IF EXISTS quotations_vat_regime_check;
ALTER TABLE sales.quotations
    ADD CONSTRAINT quotations_vat_regime_check
        CHECK (vat_regime IN ('domestic', 'domestic_reverse_charge', 'intra_eu', 'outside_eu')),
    ADD COLUMN vat_regime_override TEXT NULL
        CHECK (vat_regime_override IS NULL OR vat_regime_override IN ('domestic', 'domestic_reverse_charge', 'intra_eu', 'outside_eu')),
    ADD COLUMN building_construction_year INT NULL
        CHECK (building_construction_year IS NULL OR (building_construction_year >= 800 AND building_construction_year <= 2200));

ALTER TABLE sales.orders
    ADD COLUMN vat_regime TEXT NOT NULL DEFAULT 'domestic'
        CHECK (vat_regime IN ('domestic', 'domestic_reverse_charge', 'intra_eu', 'outside_eu')),
    ADD COLUMN building_construction_year INT NULL
        CHECK (building_construction_year IS NULL OR (building_construction_year >= 800 AND building_construction_year <= 2200));

UPDATE sales.orders o
SET vat_regime = q.vat_regime,
    building_construction_year = q.building_construction_year
FROM sales.quotations q
WHERE q.id = o.quotation_id;

-- Purchasing: store per-line VAT rate on purchase order lines.
ALTER TABLE purchasing.purchase_order_lines
    ADD COLUMN vat_rate NUMERIC(5, 2) NOT NULL DEFAULT 0
        CHECK (vat_rate >= 0 AND vat_rate < 100);
