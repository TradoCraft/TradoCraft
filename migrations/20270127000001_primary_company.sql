-- The primary company holds the installation-wide settings (identity providers, ADR 0055): only its
-- administrators may change them. At most one company is primary.
ALTER TABLE core.companies ADD COLUMN is_primary boolean NOT NULL DEFAULT false;

-- A partial unique index over a constant: a second primary company is refused by the database.
CREATE UNIQUE INDEX companies_one_primary ON core.companies ((true)) WHERE is_primary;

-- Existing installations: the oldest company becomes primary.
UPDATE core.companies SET is_primary = true
WHERE id = (SELECT id FROM core.companies ORDER BY created_at, id LIMIT 1);
