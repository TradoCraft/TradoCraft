-- The purchase order as a document (ADR 0061): the language a supplier is written to, and a record
-- of when and to whom an order was sent.
ALTER TABLE purchasing.suppliers
    ADD COLUMN language text NOT NULL DEFAULT 'en' CHECK (language IN ('nl', 'fr', 'en', 'de', 'es'));

-- Existing suppliers get the language of their country where there is an obvious one.
UPDATE purchasing.suppliers SET language = CASE
    WHEN country IN ('NL', 'BE') THEN 'nl'
    WHEN country IN ('FR', 'LU') THEN 'fr'
    WHEN country IN ('DE', 'AT') THEN 'de'
    WHEN country = 'ES' THEN 'es'
    ELSE 'en' END;

ALTER TABLE purchasing.purchase_orders
    ADD COLUMN sent_at         timestamptz,
    ADD COLUMN sent_by_user_id uuid REFERENCES core.users(id),
    ADD COLUMN sent_to         text NOT NULL DEFAULT '';
