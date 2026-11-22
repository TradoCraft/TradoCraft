-- Unique identifier for this database instance, generated when the database is created/migrated.
-- Returned by GET /api/v1/meta/environment so clients detect when a tutorial/test DB was reset.
CREATE TABLE core.instance_meta (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid()
);

INSERT INTO core.instance_meta (id) VALUES (gen_random_uuid());
