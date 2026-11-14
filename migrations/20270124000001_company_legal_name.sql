-- The registered (legal) name of a company, when it differs from the trading name (ADR 0047).
ALTER TABLE core.companies ADD COLUMN legal_name text NOT NULL DEFAULT '';
